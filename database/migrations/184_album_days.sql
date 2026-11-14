-- ============================================================
-- 184 — The days a card's guests add their photos.
--
-- The owner: « Ajouter des photos » should open on the day of the event,
-- not before. Each card has its days, set by its organiser (« Photos
-- acceptées du … au … »); by default, from the day of the event to seven
-- days after, on the card's own clock (152) — guests often send their
-- photos the days after.
--
--   * events.album_from, events.album_until: the first and the last day
--     (dates, on the card's clock). Null: the default — the event's day,
--     and seven days after the first day. A card with no date and no days
--     set takes photos as before, any day.
--   * event_album_opens(e), event_album_closes(e): those two days.
--   * event_album_add_guest (183): before the first day, « Les photos
--     s'ajoutent à partir du 21/11/2026. »; after the last, « L'ajout de
--     photos est clos depuis le 28/11/2026. ». Everything else verbatim.
--   * my_event_invitations (183) and event_presence_info (183): the two
--     days and whether today is one of them (photos_from, photos_until,
--     photos_open), so « Mes invitations » greys the button and says from
--     when.
--   * The organiser writes the two columns (a grant on them alone, as
--     164's), the last day never before the first (a check).
--
-- Shop, farm, association: none of them has cards; nothing changes there.
-- ============================================================

alter table events add column if not exists album_from date;
alter table events add column if not exists album_until date;

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'events_album_days') then
        alter table events add constraint events_album_days
            check (album_from is null or album_until is null or album_until >= album_from);
    end if;
end $$;

-- The first day: the one set, or the event's own.
create or replace function event_album_opens(p_event events)
returns date
language sql
stable
set search_path = public
as $$
    select coalesce(p_event.album_from, event_local_date(p_event.starts_at, p_event.tz));
$$;

-- The last day: the one set, or seven days after the first.
create or replace function event_album_closes(p_event events)
returns date
language sql
stable
set search_path = public
as $$
    select coalesce(p_event.album_until, event_album_opens(p_event) + 7);
$$;

-- Today, on the card's clock, one of the days (no days at all: always).
create or replace function event_album_today(p_event events)
returns boolean
language sql
stable
set search_path = public
as $$
    select (event_album_opens(p_event) is null or event_local_date(now(), p_event.tz) >= event_album_opens(p_event))
       and (event_album_closes(p_event) is null or event_local_date(now(), p_event.tz) <= event_album_closes(p_event));
$$;

-- ------------------------------------------------------------
-- The confirmation screen's card (183), with the days
-- ------------------------------------------------------------
create or replace function event_presence_info(p_slug text, p_preview text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    e events;
    r event_rsvps;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous pour confirmer votre présence.';
    end if;
    select * into e from events where slug = lower(btrim(coalesce(p_slug, '')));
    if not found or not event_visible(e, nullif(btrim(coalesce(p_preview, '')), '')) then
        return null;
    end if;
    select * into r from event_rsvps where event_id = e.id and user_id = auth.uid();
    return jsonb_build_object(
        'slug', e.slug,
        'title', e.title,
        'kind', e.kind,
        'starts_at', e.starts_at,
        'tz', e.tz,
        'date_fr', case when e.starts_at is not null then event_date_fr(e.starts_at, e.tz) end,
        'place', e.place,
        'org_name', (select name from orgs where id = e.org_id),
        'cancelled', e.cancelled_at is not null,
        'open', e.cancelled_at is null and (e.rsvp_on or e.tickets_on)
                and (event_rsvp_closes(e) is null
                     or (now() at time zone coalesce(e.tz, 'Africa/Ouagadougou'))::date <= event_rsvp_closes(e)),
        'album', e.album_on and event_album_allowed(e.org_id),
        'photos_from', event_album_opens(e),
        'photos_until', event_album_closes(e),
        'photos_open', event_album_today(e),
        -- the account has a number to share (« Rappel WhatsApp la veille »)
        'phone', (event_presence_who(auth.uid()) ->> 'phone') is not null,
        'mine', case when r.id is not null then jsonb_build_object('people', r.people, 'message', r.message,
                                                                   'share_phone', r.extra ? 'whatsapp') end);
end;
$$;

-- ------------------------------------------------------------
-- « Mes invitations » (183), with the days
-- ------------------------------------------------------------
create or replace function my_event_invitations()
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select coalesce(jsonb_agg(jsonb_build_object(
        'id', e.id,
        'slug', e.slug,
        -- a draft's link, only the one this guest confirmed through and still the card's
        'preview', case when not e.published and r.extra ->> 'preview' = e.preview_token then e.preview_token end,
        'title', e.title,
        'kind', e.kind,
        'starts_at', e.starts_at,
        'tz', e.tz,
        'place', e.place,
        'card_preview', e.card_preview,
        'org_name', (select name from orgs where id = e.org_id),
        'people', r.people,
        'message', r.message,
        'album_on', e.album_on,
        'album_allowed', event_album_allowed(e.org_id),
        'album_review', e.album_review,
        'photos_from', event_album_opens(e),
        'photos_until', event_album_closes(e),
        'photos_open', event_album_today(e),
        'photos_used', (select count(*) from event_pictures p
                         where p.event_id = e.id and p.user_id = r.user_id and p.source = 'guest'
                           and (p.state = 'stored' or p.created_at > now() - interval '10 minutes')),
        'photos_limit', 5,
        'photos', coalesce((select jsonb_agg(jsonb_build_object('key', p.key, 'approved', p.approved) order by p.done_at desc)
                              from event_pictures p
                             where p.event_id = e.id and p.user_id = r.user_id and p.source = 'guest' and p.state = 'stored'), '[]'::jsonb),
        'confirmed_at', r.created_at)
        order by e.starts_at desc nulls first), '[]'::jsonb)
      from event_rsvps r join events e on e.id = r.event_id
     where r.user_id = auth.uid() and r.answer = 'oui';
$$;

-- ------------------------------------------------------------
-- A confirmed guest's photo (183): only on the card's days
-- ------------------------------------------------------------
create or replace function event_album_add_guest(p_slug text, p_ext text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    e events;
    v_me uuid := auth.uid();
    v_ext text := lower(btrim(coalesce(p_ext, '')));
    v_name text;
    v_link text;
    v_key text;
    v_today date;
begin
    if v_me is null then
        raise exception 'Connectez-vous pour ajouter vos photos.';
    end if;
    select * into e from events where slug = lower(btrim(coalesce(p_slug, '')));
    if not found then
        raise exception 'Cette carte n''est pas ouverte.';
    end if;
    select name, extra ->> 'preview' into v_name, v_link from event_rsvps where event_id = e.id and user_id = v_me and answer = 'oui';
    if not found then
        raise exception 'Confirmez d''abord votre présence pour ajouter vos photos.';
    end if;
    if e.cancelled_at is not null then
        raise exception 'Cet événement est annulé.';
    end if;
    -- the card still the guest's to see: published, or the draft's link they
    -- confirmed through still its link (a new one shuts them out too), or
    -- the organiser's own
    if not (e.published or (v_link is not null and v_link = e.preview_token) or is_org_admin(e.org_id)) then
        raise exception 'Cette carte n''est pas ouverte.';
    end if;
    if not e.album_on then
        raise exception 'L''album est fermé pour cet événement.';
    end if;
    if not event_album_allowed(e.org_id) then
        raise exception 'L''album de cette carte est fermé.';
    end if;
    -- the card's days (184), on its clock
    v_today := event_local_date(now(), e.tz);
    if event_album_opens(e) is not null and v_today < event_album_opens(e) then
        raise exception 'Les photos s''ajoutent à partir du %.', to_char(event_album_opens(e), 'DD/MM/YYYY');
    end if;
    if event_album_closes(e) is not null and v_today > event_album_closes(e) then
        raise exception 'L''ajout de photos est clos depuis le %.', to_char(event_album_closes(e), 'DD/MM/YYYY');
    end if;
    -- one photo of this card at a time (181)
    perform 1 from events where id = e.id for update;
    if v_ext not in ('jpg', 'png', 'webp') then
        raise exception 'Photos uniquement (JPEG, PNG ou WebP).';
    end if;
    -- the five, counted by account: those stored, and those on their way
    -- (ten minutes: the Worker has the photo in hand before it asks, so a
    -- slot older than that is an upload that failed)
    if (select count(*) from event_pictures
         where event_id = e.id and user_id = v_me and source = 'guest'
           and (state = 'stored' or created_at > now() - interval '10 minutes')) >= 5 then
        raise exception 'Vous avez déposé vos 5 photos : c''est le maximum par invité.';
    end if;
    if (select count(*) from event_pictures where event_id = e.id and source = 'guest') >= 300 then
        raise exception 'L''album est plein : 300 photos au plus.';
    end if;
    if (select count(*) from event_pictures
         where event_id = e.id and source = 'guest' and created_at > now() - interval '1 day') >= 200 then
        raise exception 'Trop de photos envoyées aujourd''hui. Réessayez demain.';
    end if;
    v_key := 'events/' || e.id || '/' || replace(gen_random_uuid()::text, '-', '') || '.' || v_ext;
    insert into event_pictures (key, event_id, state, source, guest, approved, user_id)
    values (v_key, e.id, 'slot', 'guest', left(v_name, 60), not e.album_review, v_me);
    return v_key;
end;
$$;

-- ------------------------------------------------------------
-- The doors (063)
-- ------------------------------------------------------------
revoke execute on function event_album_opens(events) from public;
revoke execute on function event_album_closes(events) from public;
revoke execute on function event_album_today(events) from public;
revoke execute on function event_presence_info(text, text) from public;
revoke execute on function my_event_invitations() from public;
revoke execute on function event_album_add_guest(text, text) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function event_album_opens(events) from anon;
        revoke execute on function event_album_closes(events) from anon;
        revoke execute on function event_album_today(events) from anon;
        revoke execute on function event_presence_info(text, text) from anon;
        revoke execute on function my_event_invitations() from anon;
        revoke execute on function event_album_add_guest(text, text) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- the helpers run inside the definer functions above, as their owner
        revoke execute on function event_album_opens(events) from authenticated;
        revoke execute on function event_album_closes(events) from authenticated;
        revoke execute on function event_album_today(events) from authenticated;
        grant execute on function event_presence_info(text, text) to authenticated;
        grant execute on function my_event_invitations() to authenticated;
        grant execute on function event_album_add_guest(text, text) to authenticated;
        -- the organiser's two days, as 164's album rules (RLS keeps them to its admins)
        grant update (album_from, album_until) on events to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
