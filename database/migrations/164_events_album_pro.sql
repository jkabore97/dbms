-- ============================================================
-- 164 — The guests' album, a Pro option (ticket sales, part 5).
--
-- The owner: the album « premium », removable, five pictures per invitee
-- or ticket. Classic and animated designs alike.
--
--   * Once the platform's switch events_tickets is on (the Pro side of
--     the Événementiel), opening an album is Marakaj Pro's — or a
--     business with one of Marakaj's admins among its members, as for
--     the tickets. A free business's new card starts with its album
--     closed; an album already open stays open (the owner: existing
--     albums are kept). Until the switch, nothing changes.
--   * album_limit: « 5 photos par invité » — a picture needs a guest's
--     pass (their answer's id, 158) or a ticket request (161); five per
--     pass, five per ticket of a request. Counted by the server.
--   * album_review: « photos visibles après validation » — a guest's
--     picture waits for the organiser's yes before the album shows it.
--   * event_album_add: the slot with the pass (the uploads Worker); the
--     old event_album_slot stays for cards not yet updated, and is held
--     to the same rules (no pass: refused when the album is limited).
--   * event_album_rules: what the card's page needs to say so.
--   * event_picture_approve: the organiser's yes.
--
-- For a shop, a farm or an association: nothing — the album is an
-- event's. Applies twice.
-- ============================================================

do $$ begin
    if to_regprocedure('event_cancel(uuid, text)') is null or to_regprocedure('event_album_slot(text, text, text, text)') is null then
        raise exception '164 needs 155 and 163 applied first';
    end if;
end $$;

alter table events add column if not exists album_limit boolean not null default false;
alter table events add column if not exists album_review boolean not null default false;
alter table event_pictures add column if not exists pass_id uuid;
alter table event_pictures add column if not exists approved boolean not null default true;
create index if not exists event_pictures_pass_idx on event_pictures (event_id, pass_id) where pass_id is not null;

-- ------------------------------------------------------------
-- 1. Who may open an album
-- ------------------------------------------------------------
create or replace function event_album_allowed(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select not coalesce((select value from platform_settings where key = 'events_tickets') = 'true'::jsonb, false)
        or event_tickets_allowed(p_org);
$$;
revoke execute on function event_album_allowed(uuid) from public;

create or replace function events_album_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if tg_op = 'INSERT' then
        -- A free business's new card: its album closed, quietly.
        if new.album_on and not event_album_allowed(new.org_id) then
            new.album_on := false;
        end if;
        if (new.album_limit or new.album_review) and not event_album_allowed(new.org_id) then
            new.album_limit := false;
            new.album_review := false;
        end if;
    elsif (new.album_on and not old.album_on)
       or (new.album_limit and not old.album_limit)
       or (new.album_review and not old.album_review) then
        if not event_album_allowed(new.org_id) then
            raise exception 'Marakaj Pro : l''album des invités fait partie de Marakaj Pro. Ouvrez Compte › Marakaj Pro.';
        end if;
    end if;
    return new;
end;
$$;
revoke execute on function events_album_guard() from public;
drop trigger if exists events_album_guard on events;
create trigger events_album_guard before insert or update of album_on, album_limit, album_review on events
    for each row execute function events_album_guard();

-- ------------------------------------------------------------
-- 2. A guest's picture: the pass, the five, the organiser's yes
-- ------------------------------------------------------------
-- How many pictures a pass may bring: five per guest's answer, five per
-- ticket of a request; null when it is no pass of this event.
create or replace function event_album_pass_quota(p_event uuid, p_pass uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case
        when exists (select 1 from event_rsvps r where r.id = p_pass and r.event_id = p_event) then 5
        when exists (select 1 from event_ticket_requests q where q.id = p_pass and q.event_id = p_event and q.status = 'paid')
            then 5 * greatest((select count(*) from event_tickets k where k.request_id = p_pass and k.status <> 'void'), 1)::integer
        when exists (select 1 from event_tickets k where k.id = p_pass and k.event_id = p_event and k.status <> 'void') then 5
        else null end;
$$;
revoke execute on function event_album_pass_quota(uuid, uuid) from public;

create or replace function event_album_add(p_slug text, p_preview text, p_ext text, p_guest text default null, p_pass uuid default null)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    e events;
    v_ext text := lower(btrim(coalesce(p_ext, '')));
    v_guest text := nullif(left(btrim(coalesce(p_guest, '')), 60), '');
    v_key text;
    v_quota integer;
begin
    e := event_for_album(p_slug, p_preview);
    if v_ext not in ('jpg', 'png', 'webp') then
        raise exception 'Photos uniquement (JPEG, PNG ou WebP).';
    end if;
    if e.album_limit then
        if p_pass is null then
            raise exception 'L''album est réservé aux invités : répondez d''abord à l''invitation, ou réservez votre billet, sur ce téléphone.';
        end if;
        v_quota := event_album_pass_quota(e.id, p_pass);
        if v_quota is null then
            raise exception 'L''album est réservé aux invités : cette carte d''invité ou ce billet n''est pas de cet événement.';
        end if;
        if (select count(*) from event_pictures where event_id = e.id and pass_id = p_pass and source = 'guest') >= v_quota then
            raise exception 'Vous avez déposé vos % photos : c''est le maximum par invité.', v_quota;
        end if;
    end if;
    if (select count(*) from event_pictures where event_id = e.id and source = 'guest') >= 300 then
        raise exception 'L''album est plein : 300 photos au plus.';
    end if;
    if (select count(*) from event_pictures
         where event_id = e.id and source = 'guest' and created_at > now() - interval '1 day') >= 200 then
        raise exception 'Trop de photos envoyées aujourd''hui. Réessayez demain.';
    end if;
    v_key := 'events/' || e.id || '/' || replace(gen_random_uuid()::text, '-', '') || '.' || v_ext;
    insert into event_pictures (key, event_id, state, source, guest, pass_id, approved)
    values (v_key, e.id, 'slot', 'guest', v_guest, p_pass, not e.album_review);
    return v_key;
end;
$$;

-- The old door (155), for a card not yet updated: the same rules, no pass.
create or replace function event_album_slot(p_slug text, p_preview text, p_ext text, p_guest text default null)
returns text
language sql
security definer
set search_path = public, auth
as $$
    select event_album_add(p_slug, p_preview, p_ext, p_guest, null);
$$;

-- The album, for the card's page: what the organiser let through.
create or replace function event_album(p_slug text, p_preview text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    e events;
begin
    select * into e from events where slug = lower(trim(coalesce(p_slug, '')));
    if not found or not event_visible(e, nullif(btrim(coalesce(p_preview, '')), '')) then
        return null;
    end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object('key', s.key, 'guest', s.guest, 'at', s.done_at) order by s.done_at desc)
          from (select key, guest, done_at from event_pictures
                 where event_id = e.id and source = 'guest' and state = 'stored' and approved
                 order by done_at desc limit 300) s), '[]'::jsonb);
end;
$$;

-- What the card says about its album.
create or replace function event_album_rules(p_slug text, p_preview text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    e events;
begin
    select * into e from events where slug = lower(trim(coalesce(p_slug, '')));
    if not found or not event_visible(e, nullif(btrim(coalesce(p_preview, '')), '')) then
        return null;
    end if;
    return jsonb_build_object('on', e.album_on, 'limit', e.album_limit, 'review', e.album_review, 'per_pass', 5);
end;
$$;

-- The organiser's yes: the picture joins the album.
create or replace function event_picture_approve(p_key text)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    p event_pictures;
begin
    select * into p from event_pictures where key = p_key;
    if not found or auth.uid() is null
       or not exists (select 1 from events e where e.id = p.event_id and is_org_admin(e.org_id)) then
        raise exception 'Seuls les administrateurs valident les photos.';
    end if;
    update event_pictures set approved = true where key = p_key;
    return true;
end;
$$;

-- ------------------------------------------------------------
-- 3. Grants
-- ------------------------------------------------------------
revoke execute on function event_album_add(text, text, text, text, uuid) from public;
revoke execute on function event_album_slot(text, text, text, text) from public;
revoke execute on function event_album(text, text) from public;
revoke execute on function event_album_rules(text, text) from public;
revoke execute on function event_picture_approve(text) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function event_album_allowed(uuid) from anon;
        revoke execute on function events_album_guard() from anon;
        revoke execute on function event_album_pass_quota(uuid, uuid) from anon;
        revoke execute on function event_picture_approve(text) from anon;
        grant execute on function event_album_add(text, text, text, text, uuid) to anon;
        grant execute on function event_album_slot(text, text, text, text) to anon;
        grant execute on function event_album(text, text) to anon;
        grant execute on function event_album_rules(text, text) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function event_album_add(text, text, text, text, uuid) to authenticated;
        grant execute on function event_album_slot(text, text, text, text) to authenticated;
        grant execute on function event_album(text, text) to authenticated;
        grant execute on function event_album_rules(text, text) to authenticated;
        grant execute on function event_picture_approve(text) to authenticated;
        grant update (album_limit, album_review) on events to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
