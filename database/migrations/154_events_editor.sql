-- ============================================================
-- 154_events_editor.sql — Événementiel, piece 2: the card edited from
-- Marakaj — its words, its pictures.
--
-- The owner: « Start piece 2: edit the card's words and pictures from
-- Marakaj. » The card's own editor (the page's: touch a text to write it,
-- a picture to replace it, drag it to reframe — the one the owner's sister
-- chose) now saves to the server, and the app's card page opens it.
--
-- The design:
--   * events.edit_token: a second secret on each event, beside the
--     preview token, minted at creation (event_create) and backfilled.
--     The app reads it (the business's admins read their events) and
--     opens /e/<slug>?apercu=…&modifier=<edit_token>; the site writes
--     « editor » into the page; the page shows its editor bar. The token
--     is never in event_public's answer.
--   * event_content_save(slug, edit, content): the page's draft, in the
--     shape the pages keep it — type, t:<key> texts, p:<key> pictures
--     {key, pos}, and the animated page's a, b, date, time, place,
--     custom, pal, font — checked key by key and size by size, then
--     written to events.content. A picture may only be one of this
--     event's own, stored (below); never a data URL.
--   * event_pictures: the organiser's pictures, keyed in the uploads
--     bucket under events/<event_id>/… — minted by event_picture_slot
--     (with the edit token), confirmed by event_picture_done once the
--     bytes are in (the uploads Worker's event route, as the courier
--     dossier's does), and served to anyone by the Worker's public
--     objects route once event_picture_allowed says the key is a stored
--     one: a card's pictures show on its preview link before publication,
--     and the keys are unguessable, like the links.
--   * event_visible takes the edit token too: the editor's link opens the
--     card as the preview's does.
--
-- Shop, farm, association: untouched (the cards are the Événementiel's,
-- 153). Re-runnable. No pgcrypto.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Twenty-four random hex characters, from gen_random_uuid() (023)
-- ------------------------------------------------------------
create or replace function event_hex24()
returns text
language sql
volatile
set search_path = public
as $$
    select left(substr(h, 1, 12) || substr(h, 14, 3) || substr(h, 18, 15), 24)
      from (select replace(gen_random_uuid()::text, '-', '') as h) x;
$$;

-- ------------------------------------------------------------
-- 2. The edit token
-- ------------------------------------------------------------
alter table events add column if not exists edit_token text;
update events set edit_token = event_hex24() where edit_token is null;
alter table events alter column edit_token set not null;
-- Minted by the column itself too: an older event_create (a suite re-running
-- 152 or 153, an app before this) still makes a card with its token.
alter table events alter column edit_token set default event_hex24();
alter table events drop constraint if exists events_edit_token_check;
alter table events add constraint events_edit_token_check check (length(edit_token) = 24);

-- event_create (153), minting the edit token too.
create or replace function event_create(
    p_org uuid, p_title text, p_kind text, p_card text, p_starts_at timestamptz, p_place text,
    p_tz text default null)
returns events
language plpgsql
security invoker
set search_path = public, auth
as $$
declare
    v_title text := nullif(trim(coalesce(p_title, '')), '');
    v_place text := nullif(trim(coalesce(p_place, '')), '');
    v_kind  text := coalesce(nullif(trim(p_kind), ''), 'mariage');
    v_card  text := coalesce(nullif(trim(p_card), ''), 'come');
    v_tz    text := case when event_tz_known(p_tz) then trim(p_tz) else 'Africa/Ouagadougou' end;
    v_content jsonb;
    v_row events;
    v_try int := 0;
begin
    if v_title is null then
        raise exception 'Donnez un nom à l''événement.';
    end if;
    if not exists (select 1 from orgs where id = p_org and profile = 'events') then
        raise exception 'Les cartes d''événement se créent dans une activité Événementiel.';
    end if;
    if not exists (select 1 from event_templates where key = v_card) then
        raise exception 'Choisissez un modèle dans la liste.';
    end if;
    -- The card's first words: the title where the names go, the date and the
    -- place where every card writes them; the rest is the card's own until
    -- the organiser edits it. Escaped: the card writes them as HTML.
    v_content := jsonb_build_object(
        'type', v_kind,
        't:names', replace(replace(replace(v_title, '&', '&amp;'), '<', '&lt;'), '>', '&gt;'));
    if p_starts_at is not null then
        v_content := v_content || jsonb_build_object('t:date', event_date_fr(p_starts_at, v_tz));
    end if;
    if v_place is not null then
        v_content := v_content || jsonb_build_object(
            't:place', replace(replace(replace(v_place, '&', '&amp;'), '<', '&lt;'), '>', '&gt;'));
    end if;
    loop
        begin
            insert into events (org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at,
                                place, content, tz)
            values (p_org, auth.uid(), v_kind, v_card, event_slug(v_title),
                    event_hex24(), event_hex24(), v_title, p_starts_at, v_place, v_content, v_tz)
            returning * into v_row;
            return v_row;
        exception when unique_violation then
            v_try := v_try + 1;
            if v_try > 5 then raise; end if;
        end;
    end loop;
end;
$$;

-- ------------------------------------------------------------
-- 3. The organiser's pictures
-- ------------------------------------------------------------
create table if not exists event_pictures (
    key        text primary key
               check (key ~ '^events/[0-9a-f-]{36}/[0-9a-f]{32}\.(jpg|png|webp)$'),
    event_id   uuid not null references events(id) on delete cascade,
    state      text not null default 'slot' check (state in ('slot', 'stored')),
    bytes      integer check (bytes is null or bytes >= 0),
    created_at timestamptz not null default now(),
    done_at    timestamptz
);
create index if not exists event_pictures_event_idx on event_pictures (event_id, created_at desc);
alter table event_pictures enable row level security;

drop policy if exists "pictures seen by the business's admins" on event_pictures;
create policy "pictures seen by the business's admins"
on event_pictures for select
using (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)));

drop policy if exists "pictures removed by the business's admins" on event_pictures;
create policy "pictures removed by the business's admins"
on event_pictures for delete
using (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)));

-- ------------------------------------------------------------
-- 4. Who may see the card: the edit token opens it too
-- ------------------------------------------------------------
create or replace function event_visible(p_event events, p_preview text, p_edit text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select (p_edit is not null and p_edit = p_event.edit_token)
        or (p_preview is not null and p_preview = p_event.preview_token)
        or (p_event.published and events_public_on())
        or (auth.uid() is not null and is_org_admin(p_event.org_id));
$$;

-- 152's two-argument form, kept for event_rsvp: no edit token.
create or replace function event_visible(p_event events, p_preview text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select event_visible(p_event, p_preview, null);
$$;

-- The card for the street (152, 153), opened by the edit token too, and
-- saying « editor » then — never the token itself. The two-argument form
-- goes, so a call names one function.
drop function if exists event_public(text, text);
create or replace function event_public(p_slug text, p_preview text default null, p_edit text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    e events;
    t event_templates;
begin
    select * into e from events where slug = lower(trim(coalesce(p_slug, '')));
    if not found or not event_visible(e, p_preview, p_edit) then
        return null;
    end if;
    select * into t from event_templates where key = e.card;
    return jsonb_build_object(
        'slug', e.slug,
        'kind', e.kind,
        'card', e.card,
        'family', coalesce(t.family, 'classique'),
        'premium', coalesce(t.premium, false),
        'title', e.title,
        'starts_at', e.starts_at,
        'tz', e.tz,
        'place', e.place,
        'content', e.content,
        'rsvp_on', e.rsvp_on,
        'album_on', e.album_on,
        'published', e.published,
        'org_name', (select name from orgs where id = e.org_id),
        'preview', p_preview is not null and p_preview = e.preview_token,
        'editor', p_edit is not null and p_edit = e.edit_token);
end;
$$;

-- ------------------------------------------------------------
-- 5. The editor's doors (anon: the page is signed out, the token is its key)
-- ------------------------------------------------------------
-- The event the edit token opens, or an exception in French.
create or replace function event_for_edit(p_slug text, p_edit text)
returns events
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    e events;
begin
    select * into e from events where slug = lower(trim(coalesce(p_slug, '')));
    if not found or p_edit is null or length(p_edit) <> 24 or p_edit <> e.edit_token then
        raise exception 'Cette carte ne peut pas être modifiée d''ici.';
    end if;
    return e;
end;
$$;

-- The page's draft, checked and kept. The shape is the pages' own: type,
-- t:<key> (a text, a few inline tags the page cleans), p:<key> ({key, pos}
-- — one of this event's stored pictures, never a data URL), and the
-- animated page's a, b, date, time, place, custom, pal, font.
create or replace function event_content_save(p_slug text, p_edit text, p_content jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    e events;
    k text;
    v jsonb;
    n int := 0;
    v_key text;
begin
    e := event_for_edit(p_slug, p_edit);
    if p_content is null or jsonb_typeof(p_content) <> 'object' then
        raise exception 'Contenu mal formé.';
    end if;
    if length(p_content::text) > 60000 then
        raise exception 'La carte est trop lourde : moins de texte, s''il vous plaît.';
    end if;
    for k, v in select * from jsonb_each(p_content) loop
        n := n + 1;
        if n > 80 then
            raise exception 'Trop de champs.';
        end if;
        if k ~ '^t:[a-z0-9-]{1,40}$' then
            if jsonb_typeof(v) <> 'string' or length(v #>> '{}') > 4000 then
                raise exception 'Un texte de 4 000 caractères au plus (%).', k;
            end if;
        elsif k ~ '^p:[a-z0-9-]{1,40}$' then
            if jsonb_typeof(v) <> 'object' or length(v::text) > 400 or v ? 'src' then
                raise exception 'Image mal formée (%).', k;
            end if;
            v_key := v ->> 'key';
            if v_key is not null and not exists (
                select 1 from event_pictures where key = v_key and event_id = e.id and state = 'stored') then
                raise exception 'Cette image n''est pas celle de la carte.';
            end if;
            if (v ->> 'pos') is not null and (v ->> 'pos') !~ '^[0-9]{1,3}(\.[0-9])?% [0-9]{1,3}(\.[0-9])?%$' then
                raise exception 'Cadrage mal formé.';
            end if;
        elsif k in ('type', 'font', 'a', 'b', 'custom', 'place', 'date', 'time') then
            if jsonb_typeof(v) <> 'string' or length(v #>> '{}') > 160 then
                raise exception 'Champ trop long (%).', k;
            end if;
        elsif k = 'pal' then
            if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric not between 0 and 9 then
                raise exception 'Couleur inconnue.';
            end if;
        else
            raise exception 'Champ inconnu : %', k;
        end if;
    end loop;
    update events set content = p_content where id = e.id;
    return true;
end;
$$;

-- Where a new picture goes: a key under the event, minted here, recorded
-- as a slot until the bytes are in.
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
    if (select count(*) from event_pictures where event_id = e.id) >= 80 then
        raise exception 'Trop d''images pour cette carte : retirez-en avant d''en ajouter.';
    end if;
    if (select count(*) from event_pictures where event_id = e.id and created_at > now() - interval '1 day') >= 120 then
        raise exception 'Trop d''images envoyées aujourd''hui. Réessayez demain.';
    end if;
    v_key := 'events/' || e.id || '/' || replace(gen_random_uuid()::text, '-', '') || '.' || v_ext;
    insert into event_pictures (key, event_id, state) values (v_key, e.id, 'slot');
    return v_key;
end;
$$;

-- The bytes are in: the picture is the card's.
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
     where key = p_key and state = 'slot' and created_at > now() - interval '1 hour'
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

-- Whether the street may see a picture: a stored one of a card. The key
-- is unguessable, as the card's links are; a deleted card takes its
-- pictures' rows with it, and the Worker then answers nothing.
create or replace function event_picture_allowed(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (select 1 from event_pictures where key = p_key and state = 'stored');
$$;

-- ------------------------------------------------------------
-- 6. Who may call what (063)
-- ------------------------------------------------------------
revoke execute on function event_hex24()                                          from public;
revoke execute on function event_visible(events, text, text)                      from public;
revoke execute on function event_visible(events, text)                            from public;
revoke execute on function event_public(text, text, text)                         from public;
revoke execute on function event_for_edit(text, text)                             from public;
revoke execute on function event_content_save(text, text, jsonb)                  from public;
revoke execute on function event_picture_slot(text, text, text)                   from public;
revoke execute on function event_picture_done(text, text, integer)                from public;
revoke execute on function event_picture_allowed(text)                            from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function event_hex24()                                  from anon;
        revoke execute on function event_visible(events, text, text)              from anon;
        revoke execute on function event_visible(events, text)                    from anon;
        revoke execute on function event_for_edit(text, text)                     from anon;
        grant  execute on function event_public(text, text, text)                 to anon;
        grant  execute on function event_content_save(text, text, jsonb)          to anon;
        grant  execute on function event_picture_slot(text, text, text)           to anon;
        grant  execute on function event_picture_done(text, text, integer)        to anon;
        grant  execute on function event_picture_allowed(text)                    to anon;
        revoke select on event_pictures from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant  execute on function event_hex24()                                  to authenticated;
        revoke execute on function event_visible(events, text, text)              from authenticated;
        revoke execute on function event_visible(events, text)                    from authenticated;
        revoke execute on function event_for_edit(text, text)                     from authenticated;
        grant  execute on function event_public(text, text, text)                 to authenticated;
        grant  execute on function event_content_save(text, text, jsonb)          to authenticated;
        grant  execute on function event_picture_slot(text, text, text)           to authenticated;
        grant  execute on function event_picture_done(text, text, integer)        to authenticated;
        grant  execute on function event_picture_allowed(text)                    to authenticated;
        grant  select, delete on event_pictures to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
