-- ============================================================
-- 155 — Événementiel, piece 3: the guests' album.
--
-- A guest with the card's link drops a picture on it, the day itself:
-- it lives with the event, under the guest's first name, and every
-- guest sees it in the card's album. The organiser sees the album in
-- Marakaj and removes a picture there. Nothing here for a shop, a farm
-- or an association: the cards are an Événementiel's (153).
--
-- Reads as:
--   1. event_pictures (154) says whose a picture is — the organiser's
--      (the card's own, 154) or a guest's — and the guest's name;
--   2. the organiser's limits count the organiser's own pictures only
--      (154 counted every row; a full album would have shut the editor);
--   3. the album's doors, for the street: event_album_slot mints a key
--      for a guest with the card's link (the preview token, or the
--      published card), album open, jpg/png/webp, three hundred a card
--      and two hundred a day; event_album_done confirms the bytes with
--      the same link; event_album lists the stored ones, newest first;
--   4. event_picture_delete, as the caller: the business's admins remove
--      a picture (RLS, 154's policy); the uploads Worker then drops the
--      bytes. event_picture_allowed (154) stops serving it at once.
--   5. grants (063): anon gets the three album doors, nothing else.
-- Applies twice.
-- ============================================================

do $$ begin
    if to_regclass('public.event_pictures') is null then
        raise exception '155 needs 154 (event_pictures) applied first';
    end if;
end $$;

-- ------------------------------------------------------------
-- 1. Whose picture, and the guest's name under it
-- ------------------------------------------------------------
alter table event_pictures add column if not exists source text not null default 'organiser';
alter table event_pictures drop constraint if exists event_pictures_source_check;
alter table event_pictures add constraint event_pictures_source_check check (source in ('organiser', 'guest'));
alter table event_pictures add column if not exists guest text;
alter table event_pictures drop constraint if exists event_pictures_guest_check;
alter table event_pictures add constraint event_pictures_guest_check check (guest is null or length(guest) <= 60);
create index if not exists event_pictures_album_idx on event_pictures (event_id, source, done_at desc);

-- ------------------------------------------------------------
-- 2. The organiser's limits are the organiser's own (154, amended)
-- ------------------------------------------------------------
create or replace function event_picture_slot(p_slug text, p_edit text, p_ext text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    e events;
    v_ext text := lower(btrim(coalesce(p_ext, '')));
    v_key text;
begin
    e := event_for_edit(p_slug, p_edit);
    if v_ext not in ('jpg', 'png', 'webp') then
        raise exception 'Photos uniquement (JPEG, PNG ou WebP).';
    end if;
    if (select count(*) from event_pictures where event_id = e.id and source = 'organiser') >= 80 then
        raise exception 'Trop d''images pour cette carte : retirez-en avant d''en ajouter.';
    end if;
    if (select count(*) from event_pictures
         where event_id = e.id and source = 'organiser' and created_at > now() - interval '1 day') >= 120 then
        raise exception 'Trop d''images envoyées aujourd''hui. Réessayez demain.';
    end if;
    v_key := 'events/' || e.id || '/' || replace(gen_random_uuid()::text, '-', '') || '.' || v_ext;
    insert into event_pictures (key, event_id, state, source) values (v_key, e.id, 'slot', 'organiser');
    return v_key;
end;
$$;

-- And the organiser's door confirms the organiser's own slots only (154
-- confirmed any slot with the edit token; a guest's is the album's).
create or replace function event_picture_done(p_key text, p_edit text, p_bytes integer default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    p event_pictures;
    e events;
begin
    select * into p from event_pictures
     where key = p_key and state = 'slot' and source = 'organiser' and created_at > now() - interval '1 hour'
     for update;
    if not found then
        raise exception 'Envoi inconnu.';
    end if;
    select * into e from events where id = p.event_id;
    if p_edit is null or p_edit <> e.edit_token then
        raise exception 'Cette carte ne peut pas être modifiée d''ici.';
    end if;
    update event_pictures set state = 'stored', bytes = p_bytes, done_at = clock_timestamp() where key = p_key;
    return true;
end;
$$;

-- ------------------------------------------------------------
-- 3. The album's doors (anon: a guest is signed out, the card's link
--    is the key)
-- ------------------------------------------------------------
-- The card a guest may see, with its album open — or an exception in
-- French. event_visible (154): the preview token, or the published card
-- once the module is public; never the edit token here.
create or replace function event_for_album(p_slug text, p_preview text)
returns events
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
        raise exception 'Cette carte n''est pas ouverte.';
    end if;
    if not e.album_on then
        raise exception 'L''album est fermé pour cet événement.';
    end if;
    return e;
end;
$$;

-- Where a guest's picture goes: a key under the event, minted here,
-- recorded as a slot with the guest's name until the bytes are in.
create or replace function event_album_slot(p_slug text, p_preview text, p_ext text, p_guest text default null)
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
begin
    e := event_for_album(p_slug, p_preview);
    if v_ext not in ('jpg', 'png', 'webp') then
        raise exception 'Photos uniquement (JPEG, PNG ou WebP).';
    end if;
    if (select count(*) from event_pictures where event_id = e.id and source = 'guest') >= 300 then
        raise exception 'L''album est plein : 300 photos au plus.';
    end if;
    if (select count(*) from event_pictures
         where event_id = e.id and source = 'guest' and created_at > now() - interval '1 day') >= 200 then
        raise exception 'Trop de photos envoyées aujourd''hui. Réessayez demain.';
    end if;
    v_key := 'events/' || e.id || '/' || replace(gen_random_uuid()::text, '-', '') || '.' || v_ext;
    insert into event_pictures (key, event_id, state, source, guest) values (v_key, e.id, 'slot', 'guest', v_guest);
    return v_key;
end;
$$;

-- The bytes are in: the picture is in the album.
create or replace function event_album_done(p_key text, p_preview text, p_bytes integer default null)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    p event_pictures;
    e events;
begin
    select * into p from event_pictures
     where key = p_key and state = 'slot' and source = 'guest' and created_at > now() - interval '1 hour'
     for update;
    if not found then
        raise exception 'Envoi inconnu.';
    end if;
    select * into e from events where id = p.event_id;
    if not event_visible(e, nullif(btrim(coalesce(p_preview, '')), '')) then
        raise exception 'Cette carte n''est pas ouverte.';
    end if;
    update event_pictures set state = 'stored', bytes = p_bytes, done_at = clock_timestamp() where key = p_key;
    return true;
end;
$$;

-- The album, for the card's page: the guests' stored pictures, newest
-- first, each with the name under it. Null when the card is not open to
-- the caller (nothing to tell), an empty list when the album is empty.
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
                 where event_id = e.id and source = 'guest' and state = 'stored'
                 order by done_at desc limit 300) s), '[]'::jsonb);
end;
$$;

-- ------------------------------------------------------------
-- 4. The organiser removes a picture — as the caller (154's delete
--    policy: the business's admins), so RLS is the rule; the uploads
--    Worker calls this with the admin's token, then drops the bytes.
-- ------------------------------------------------------------
create or replace function event_picture_delete(p_key text)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
begin
    delete from event_pictures where key = p_key;
    return found;
end;
$$;

-- ------------------------------------------------------------
-- 5. Who may call what (063)
-- ------------------------------------------------------------
revoke execute on function event_for_album(text, text)                         from public;
revoke execute on function event_album_slot(text, text, text, text)            from public;
revoke execute on function event_album_done(text, text, integer)               from public;
revoke execute on function event_album(text, text)                             from public;
revoke execute on function event_picture_delete(text)                          from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function event_for_album(text, text)                 from anon;
        grant  execute on function event_album_slot(text, text, text, text)    to anon;
        grant  execute on function event_album_done(text, text, integer)       to anon;
        grant  execute on function event_album(text, text)                     to anon;
        revoke execute on function event_picture_delete(text)                  from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function event_for_album(text, text)                 from authenticated;
        grant  execute on function event_album_slot(text, text, text, text)    to authenticated;
        grant  execute on function event_album_done(text, text, integer)       to authenticated;
        grant  execute on function event_album(text, text)                     to authenticated;
        grant  execute on function event_picture_delete(text)                  to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
