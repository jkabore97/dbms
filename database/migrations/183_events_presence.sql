-- ============================================================
-- 183 — « Confirmer ma présence »: one button on the card, the photos
-- from the app, five per guest.
--
-- The owner: on a card, the answer form (« Serez-vous des nôtres ? »),
-- the guest's QR card and the album's upload (« Vos photos de la
-- cérémonie », a name, « Ajouter des photos ») conflict. One button
-- instead, « Confirmer ma présence — pour ajouter vos photos », to
-- marakaj.com/presence/<slug>: the guest signs in (or makes an account),
-- lands straight on the confirmation — how many, a word — and « Je
-- confirme ». They hear it in the app (« vous pouvez ajouter vos
-- photos »), the organiser hears who comes; in the app, « Mes
-- invitations » lists the cards confirmed, each with its photos added
-- from the phone, five per guest. The card keeps the album's photos for
-- everyone to look at, open full size and download.
--
--   * event_rsvps.user_id: the account that confirmed (null for the
--     answers of before, which stay). One answer per account and card:
--     confirming again changes how many and the word, nothing more — the
--     organiser hears of it the first time only.
--   * event_presence_info(slug, preview): the card as the confirmation
--     screen shows it, and the account's own answer if any.
--   * event_presence_confirm(slug, preview, people, message): signed in,
--     the card visible to the caller (event_visible, as every door), its
--     answers open (or its tickets on sale: a buyer confirms too). The
--     name is the account's, its phone the organiser's WhatsApp reminder
--     (extra.whatsapp, read as before). Two bells: the guest's
--     (« Présence confirmée à … : vous pouvez ajouter vos photos. »), the
--     business's admins' (« Awa a confirmé sa présence (2 personnes) —
--     Mariage »).
--   * my_event_invitations(): the account's confirmed cards, for « Mes
--     invitations » — the card's preview link only when it is a draft and
--     the link is the one the guest confirmed through; the album's state,
--     the guest's own photos and how many of the five are used.
--   * event_pictures.user_id; event_album_add_guest(slug, ext): a
--     confirmed guest's photo, counted by account on the server — five,
--     then « Vous avez déposé vos 5 photos : c'est le maximum par
--     invité. » — the album's 300 and the day's 200 (179) kept, the card
--     taken first (181), the album on and Marakaj Pro's (182; its
--     trigger stands too). event_album_done (155) completes it, as the
--     card's link did before, and now also for the slot's own account.
--   * event_album_add (181), the signed-out door of the old upload: the
--     pages no longer send to it; it says what to do instead, so a page
--     kept open from before cannot fill an album past the five per guest.
--     event_rsvp (152), the signed-out answer, stays for such a page.
--
-- The doors (063): the four new functions closed to public and anon,
-- open to authenticated. No view.
--
-- For a shop, a farm and an association: nothing (an Événementiel's
-- cards only). Applies twice.
-- ============================================================

alter table event_rsvps add column if not exists user_id uuid references auth.users (id) on delete set null;
create unique index if not exists event_rsvps_one_per_account on event_rsvps (event_id, user_id) where user_id is not null;
create index if not exists event_rsvps_user_idx on event_rsvps (user_id) where user_id is not null;

alter table event_pictures add column if not exists user_id uuid references auth.users (id) on delete set null;
create index if not exists event_pictures_guest_user_idx on event_pictures (event_id, user_id) where user_id is not null;

-- ------------------------------------------------------------
-- The account's name and number, as the organiser reads them
-- ------------------------------------------------------------
create or replace function event_presence_who(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select jsonb_build_object(
        'name', left(coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                              nullif(btrim(p.phone), ''), nullif(btrim(u.phone), ''), 'Invité'), 80),
        'phone', (select '+' || d from (select regexp_replace(coalesce(nullif(u.phone, ''), p.phone, ''), '\D', '', 'g') as d) x
                   where length(d) between 8 and 15))
      from auth.users u left join profiles p on p.id = u.id
     where u.id = p_user;
$$;

-- ------------------------------------------------------------
-- The confirmation screen's card
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
        'open', (e.rsvp_on or e.tickets_on)
                and (event_rsvp_closes(e) is null
                     or (now() at time zone coalesce(e.tz, 'Africa/Ouagadougou'))::date <= event_rsvp_closes(e)),
        'album', e.album_on and event_album_allowed(e.org_id),
        'mine', case when r.id is not null then jsonb_build_object('people', r.people, 'message', r.message) end);
end;
$$;

-- ------------------------------------------------------------
-- « Je confirme »
-- ------------------------------------------------------------
create or replace function event_presence_confirm(p_slug text, p_preview text, p_people integer, p_message text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    e events;
    v_me uuid := auth.uid();
    v_who jsonb;
    v_name text;
    v_preview text := nullif(btrim(coalesce(p_preview, '')), '');
    v_message text := nullif(btrim(coalesce(p_message, '')), '');
    v_closes date;
    v_id uuid;
    v_first boolean;
    v_extra jsonb;
begin
    if v_me is null then
        raise exception 'Connectez-vous pour confirmer votre présence.';
    end if;
    select * into e from events where slug = lower(btrim(coalesce(p_slug, '')));
    if not found or not event_visible(e, v_preview) then
        raise exception 'Cette carte n''est pas ouverte.';
    end if;
    -- the answers open, or the tickets on sale (a buyer confirms too)
    if not (e.rsvp_on or e.tickets_on) then
        raise exception 'Les réponses sont fermées pour cet événement.';
    end if;
    v_closes := event_rsvp_closes(e);
    if v_closes is not null and (now() at time zone coalesce(e.tz, 'Africa/Ouagadougou'))::date > v_closes then
        raise exception 'Les réponses sont closes depuis le %.', to_char(v_closes, 'DD/MM/YYYY');
    end if;
    if p_people is null or p_people < 1 or p_people > 10 then
        raise exception 'Entre 1 et 10 personnes.';
    end if;
    if v_message is not null and length(v_message) > 500 then
        raise exception 'Un mot de 500 caractères au plus.';
    end if;
    v_who := event_presence_who(v_me);
    v_name := coalesce(v_who ->> 'name', 'Invité');
    v_extra := jsonb_strip_nulls(jsonb_build_object(
        'whatsapp', v_who ->> 'phone',
        'account', true,
        -- the draft's link the guest came through: « Mes invitations » opens it again
        'preview', case when v_preview is not null and v_preview = e.preview_token then v_preview end));
    -- one card's answers one after the other: the 2000 hold
    perform 1 from events where id = e.id for update;
    if not exists (select 1 from event_rsvps where event_id = e.id and user_id = v_me)
       and (select count(*) from event_rsvps where event_id = e.id) >= 2000 then
        raise exception 'Cet événement a reçu toutes les réponses qu''il peut tenir.';
    end if;
    insert into event_rsvps as r (event_id, user_id, name, people, answer, message, extra)
    values (e.id, v_me, v_name, p_people, 'oui', v_message, v_extra)
    on conflict (event_id, user_id) where user_id is not null do update
       set people = excluded.people, message = excluded.message, answer = 'oui', name = excluded.name,
           extra = r.extra || excluded.extra
    returning r.id, (xmax = 0) into v_id, v_first;

    if v_first then
        -- the guest's bell (115): « Mes invitations » is where the photos go
        insert into notifications (recipient_id, org_id, kind, message, params)
        select v_me, null, 'event_presence_guest',
               'Présence confirmée à « ' || e.title || ' » : vous pouvez ajouter vos photos.',
               jsonb_build_object('to', 'customer', 'event_id', e.id, 'slug', e.slug, 'title', e.title)
         where exists (select 1 from profiles where id = v_me);
        -- the organiser's
        perform notify_org_admins(e.org_id, 'event_presence',
            v_name || ' a confirmé sa présence (' || p_people || ' personne' || case when p_people > 1 then 's' else '' end || ') — ' || e.title,
            jsonb_build_object('to', 'shop', 'event_id', e.id, 'rsvp_id', v_id, 'name', v_name, 'people', p_people, 'title', e.title),
            v_me);
    end if;
    return jsonb_build_object('event_id', e.id, 'slug', e.slug, 'title', e.title, 'first', v_first);
end;
$$;

-- ------------------------------------------------------------
-- « Mes invitations »
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
        'photos_used', (select count(*) from event_pictures p
                         where p.event_id = e.id and p.user_id = r.user_id and p.source = 'guest'
                           and (p.state = 'stored' or p.created_at > now() - interval '1 hour')),
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
-- A confirmed guest's photo: five per account
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
    v_key text;
begin
    if v_me is null then
        raise exception 'Connectez-vous pour ajouter vos photos.';
    end if;
    select * into e from events where slug = lower(btrim(coalesce(p_slug, '')));
    if not found then
        raise exception 'Cette carte n''est pas ouverte.';
    end if;
    select name into v_name from event_rsvps where event_id = e.id and user_id = v_me and answer = 'oui';
    if not found then
        raise exception 'Confirmez d''abord votre présence pour ajouter vos photos.';
    end if;
    if not e.album_on then
        raise exception 'L''album est fermé pour cet événement.';
    end if;
    if not event_album_allowed(e.org_id) then
        raise exception 'L''album de cette carte est fermé.';
    end if;
    -- one photo of this card at a time (181)
    perform 1 from events where id = e.id for update;
    if v_ext not in ('jpg', 'png', 'webp') then
        raise exception 'Photos uniquement (JPEG, PNG ou WebP).';
    end if;
    -- the five, counted by account: those stored, and those on their way
    if (select count(*) from event_pictures
         where event_id = e.id and user_id = v_me and source = 'guest'
           and (state = 'stored' or created_at > now() - interval '1 hour')) >= 5 then
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

-- The bytes are in (155): by the card's link as before, or by the slot's
-- own account (a guest's photo from the app, whatever the card's state).
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
    if not (p.user_id is not null and p.user_id = auth.uid())
       and not event_visible(e, nullif(btrim(coalesce(p_preview, '')), '')) then
        raise exception 'Cette carte n''est pas ouverte.';
    end if;
    update event_pictures set state = 'stored', bytes = p_bytes, done_at = clock_timestamp() where key = p_key;
    return true;
end;
$$;

-- The old signed-out upload (155 to 181): its pages are gone; one kept
-- open from before is told the way now.
create or replace function event_album_add(p_slug text, p_preview text, p_ext text, p_guest text default null,
                                           p_pass uuid default null, p_device text default null)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    raise exception 'Pour ajouter vos photos : « Confirmer ma présence » sur la carte, puis « Mes invitations » dans Marakaj.';
end;
$$;

-- ------------------------------------------------------------
-- The doors (063)
-- ------------------------------------------------------------
revoke execute on function event_presence_who(uuid) from public;
revoke execute on function event_presence_info(text, text) from public;
revoke execute on function event_presence_confirm(text, text, integer, text) from public;
revoke execute on function my_event_invitations() from public;
revoke execute on function event_album_add_guest(text, text) from public;
revoke execute on function event_album_done(text, text, integer) from public;
revoke execute on function event_album_add(text, text, text, text, uuid, text) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function event_presence_who(uuid) from anon;
        revoke execute on function event_presence_info(text, text) from anon;
        revoke execute on function event_presence_confirm(text, text, integer, text) from anon;
        revoke execute on function my_event_invitations() from anon;
        revoke execute on function event_album_add_guest(text, text) from anon;
        -- as before (155, 181): the street's doors, a page of before kept open
        grant execute on function event_album_done(text, text, integer) to anon;
        grant execute on function event_album_add(text, text, text, text, uuid, text) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function event_presence_who(uuid) from authenticated;
        grant execute on function event_presence_info(text, text) to authenticated;
        grant execute on function event_presence_confirm(text, text, integer, text) to authenticated;
        grant execute on function my_event_invitations() to authenticated;
        grant execute on function event_album_add_guest(text, text) to authenticated;
        grant execute on function event_album_done(text, text, integer) to authenticated;
        grant execute on function event_album_add(text, text, text, text, uuid, text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
