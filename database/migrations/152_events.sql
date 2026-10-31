-- ============================================================
-- 152_events.sql — Événementiel, piece 1: the events a business creates,
-- the guests' answers and photos, the card the guests open, and the
-- platform's switch that keeps the whole thing to Marakaj's admins until
-- it is opened to everyone.
--
-- The owner: « Start build Événementiel in Marakaj but make Marakaj admin
-- only can view. Make a tab in admin that can allow me to switch the
-- feature to public view. »
--
-- The design:
--   * events_public (Réglages › Événementiel): false. While it is off, the
--     module is the platform admins' alone — events_open() says who may
--     touch the tables, and every policy below asks it; event_public()
--     shows a published card to the street only once it is on. The one way
--     through while it is off: the card's own preview link, which carries
--     the event's preview_token (the organiser's and the admin's way to
--     look at the card before it is public).
--   * events: one row per event, owned by a business (a wedding planner's
--     shop, an association's gala, a farm's open day — the three kinds
--     alike), written by that business's admins (is_org_admin). The card's
--     words and pictures are one jsonb, content, in the shape the card
--     pages read (t:<key> for a text, p:<key> for a picture, type for the
--     kind of event): the same shape the editor writes.
--   * event_rsvps: what a guest answered, written by the street through
--     event_rsvp() (guests are not members and never sign in), read by the
--     business's admins.
--   * event_guest_photos: the guests' pictures, keyed in the uploads
--     bucket; the rows come with the uploads Worker's event routes (piece
--     2). The table is here so the card's shape is settled now.
--   * The street's three doors, granted to anon: events_options() (the
--     switch, for the app and the site), event_public(slug, preview) (the
--     card) and event_rsvp(…). Everything else is born closed to anon
--     (063) and stays so.
--
-- Shop, farm, association: the same tables, the same doors. Re-runnable.
-- No pgcrypto: the random hex (an address's tail, a preview token) comes
-- from gen_random_uuid(), core Postgres — on Supabase the extension sits in
-- `extensions`, out of every pinned search path (023).
-- ============================================================

insert into platform_settings (key, value) values ('events_public', 'false')
on conflict (key) do nothing;

-- The switch alone: read by events_open(), event_public(), event_rsvp()
-- and events_options().
create or replace function events_public_on()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((select value from platform_settings where key = 'events_public') = 'true'::jsonb, false);
$$;

-- Who may touch the events tables: everybody once the switch is on, the
-- platform's admins before. Asked by every policy below.
create or replace function events_open()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select events_public_on()
        or exists (select 1 from profiles where id = auth.uid() and is_platform_admin);
$$;

-- ------------------------------------------------------------
-- The tables
-- ------------------------------------------------------------
create table if not exists events (
    id            uuid primary key default gen_random_uuid(),
    org_id        uuid not null references orgs(id) on delete cascade,
    created_by    uuid references profiles(id) on delete set null,
    kind          text not null default 'mariage'
                  check (kind in ('mariage', 'dot', 'anniversaire', 'bapteme', 'naissance',
                                  'diplome', 'gala', 'inauguration', 'retraite', 'hommage')),
    card          text not null default 'come'
                  check (card in ('come', 'ravello', 'sahel', 'jardin', 'minuit', 'anniv', 'bapteme',
                                  'naissance', 'diplome', 'gala', 'dot', 'hommage')),
    slug          text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) <= 80),
    preview_token text not null check (length(preview_token) = 24),
    title         text not null check (length(title) between 1 and 120),
    starts_at     timestamptz,
    place         text check (place is null or length(place) <= 200),
    content       jsonb not null default '{}'::jsonb check (jsonb_typeof(content) = 'object'),
    rsvp_on       boolean not null default true,
    album_on      boolean not null default true,
    published     boolean not null default false,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);
create index if not exists events_org_idx on events (org_id, created_at desc);

create table if not exists event_rsvps (
    id         uuid primary key default gen_random_uuid(),
    event_id   uuid not null references events(id) on delete cascade,
    name       text not null check (length(name) between 1 and 80),
    people     integer not null default 1 check (people between 0 and 20),
    answer     text not null check (answer in ('oui', 'non', 'mot')),
    message    text check (message is null or length(message) <= 1000),
    extra      jsonb not null default '{}'::jsonb check (jsonb_typeof(extra) = 'object'),
    created_at timestamptz not null default now()
);
create index if not exists event_rsvps_event_idx on event_rsvps (event_id, created_at desc);

create table if not exists event_guest_photos (
    id         uuid primary key default gen_random_uuid(),
    event_id   uuid not null references events(id) on delete cascade,
    key        text not null unique,
    who        text check (who is null or length(who) <= 80),
    caption    text check (caption is null or length(caption) <= 200),
    approved   boolean not null default false,
    created_at timestamptz not null default now()
);
create index if not exists event_guest_photos_event_idx on event_guest_photos (event_id, created_at desc);

create or replace function events_touch()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;
drop trigger if exists events_touch on events;
create trigger events_touch before update on events
    for each row execute function events_touch();

-- ------------------------------------------------------------
-- Row level security: the business's admins, and only once the module is
-- open to them (events_open). The street never reads the tables: it goes
-- through the three functions below.
-- ------------------------------------------------------------
alter table events enable row level security;
alter table event_rsvps enable row level security;
alter table event_guest_photos enable row level security;

drop policy if exists "events seen by the business's admins" on events;
create policy "events seen by the business's admins"
on events for select
using (is_org_admin(org_id) and events_open());

drop policy if exists "events written by the business's admins" on events;
create policy "events written by the business's admins"
on events for insert
with check (is_org_admin(org_id) and events_open());

drop policy if exists "events changed by the business's admins" on events;
create policy "events changed by the business's admins"
on events for update
using (is_org_admin(org_id) and events_open())
with check (is_org_admin(org_id) and events_open());

drop policy if exists "events deleted by the business's admins" on events;
create policy "events deleted by the business's admins"
on events for delete
using (is_org_admin(org_id) and events_open());

drop policy if exists "rsvps seen by the business's admins" on event_rsvps;
create policy "rsvps seen by the business's admins"
on event_rsvps for select
using (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)));

drop policy if exists "rsvps deleted by the business's admins" on event_rsvps;
create policy "rsvps deleted by the business's admins"
on event_rsvps for delete
using (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)));

drop policy if exists "guest photos seen by the business's admins" on event_guest_photos;
create policy "guest photos seen by the business's admins"
on event_guest_photos for select
using (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)));

drop policy if exists "guest photos judged by the business's admins" on event_guest_photos;
create policy "guest photos judged by the business's admins"
on event_guest_photos for update
using (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)))
with check (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)));

drop policy if exists "guest photos removed by the business's admins" on event_guest_photos;
create policy "guest photos removed by the business's admins"
on event_guest_photos for delete
using (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)));

-- ------------------------------------------------------------
-- Creating an event: SECURITY INVOKER on purpose — the insert is bound by
-- the policies above, exactly as a direct write. The function is here for
-- what a client should not improvise: the address (slug), the preview
-- token, the first words of the card.
-- ------------------------------------------------------------

-- « samedi 12 décembre 2026 · 16 h », on Ouagadougou's clock, a capital
-- first: what the card shows until the organiser rewrites it.
create or replace function event_date_fr(p_at timestamptz)
returns text
language sql
immutable
set search_path = public
as $$
    select case when p_at is null then null else
        (select upper(left(s, 1)) || substr(s, 2) from (
            select (array['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'])
                       [extract(dow from l)::int + 1]
                   || ' ' || extract(day from l)::int
                   || ' ' || (array['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
                                    'septembre', 'octobre', 'novembre', 'décembre'])[extract(month from l)::int]
                   || ' ' || extract(year from l)::int
                   || ' · ' || extract(hour from l)::int || ' h'
                   || case when extract(minute from l)::int > 0
                           then ' ' || lpad(extract(minute from l)::int::text, 2, '0') else '' end as s
              from (select p_at at time zone 'Africa/Ouagadougou' as l) t) u)
    end;
$$;

-- An address from a title: « Inès & Thomas » → « ines-thomas-k7f2 ». The four
-- hex characters are gen_random_uuid()'s, core Postgres and CSPRNG-backed:
-- pgcrypto's gen_random_bytes() lives in Supabase's `extensions` schema, out
-- of every pinned search path (023 learnt it the hard way; the first live run
-- of this file learnt it again).
create or replace function event_slug(p_title text)
returns text
language sql
volatile
set search_path = public
as $$
    select coalesce(nullif(left(regexp_replace(regexp_replace(lower(
                translate(coalesce(p_title, ''),
                          'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ',
                          'aaaaaaceeeeiiiinooooouuuuyyoa')),
                '[^a-z0-9]+', '-', 'g'), '^-+|-+$', '', 'g'), 60), ''), 'evenement')
           || '-' || left(replace(gen_random_uuid()::text, '-', ''), 4);
$$;

create or replace function event_create(
    p_org uuid, p_title text, p_kind text, p_card text, p_starts_at timestamptz, p_place text)
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
    v_content jsonb;
    v_hex text;
    v_row events;
    v_try int := 0;
begin
    if v_title is null then
        raise exception 'Donnez un nom à l''événement.';
    end if;
    -- The card's first words: the title where the names go, the date and the
    -- place where every card writes them; the rest is the card's own until
    -- the organiser edits it. Escaped: the card writes them as HTML.
    v_content := jsonb_build_object(
        'type', v_kind,
        't:names', replace(replace(replace(v_title, '&', '&amp;'), '<', '&lt;'), '>', '&gt;'));
    if p_starts_at is not null then
        v_content := v_content || jsonb_build_object('t:date', event_date_fr(p_starts_at));
    end if;
    if v_place is not null then
        v_content := v_content || jsonb_build_object(
            't:place', replace(replace(replace(v_place, '&', '&amp;'), '<', '&lt;'), '>', '&gt;'));
    end if;
    loop
        begin
            -- The preview token: 24 of the 30 random hex characters of one
            -- gen_random_uuid(), the version (13th) and variant (17th) nibbles
            -- left out as 023 does — no pgcrypto, same on CI and on Supabase.
            v_hex := replace(gen_random_uuid()::text, '-', '');
            v_hex := substr(v_hex, 1, 12) || substr(v_hex, 14, 3) || substr(v_hex, 18, 15);
            insert into events (org_id, created_by, kind, card, slug, preview_token, title, starts_at, place, content)
            values (p_org, auth.uid(), v_kind, v_card, event_slug(v_title),
                    left(v_hex, 24), v_title, p_starts_at, v_place, v_content)
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
-- The street's doors: the switch, the card, the answer.
-- ------------------------------------------------------------
create or replace function events_options()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object('public', events_public_on());
$$;

-- Whether this call may see the event: the preview link's token, a
-- published card once the module is public, or its own business's admin.
create or replace function event_visible(p_event events, p_preview text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select (p_preview is not null and p_preview = p_event.preview_token)
        or (p_event.published and events_public_on())
        or (auth.uid() is not null and is_org_admin(p_event.org_id));
$$;

create or replace function event_public(p_slug text, p_preview text default null)
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
    if not found or not event_visible(e, p_preview) then
        return null;
    end if;
    return jsonb_build_object(
        'slug', e.slug,
        'kind', e.kind,
        'card', e.card,
        'title', e.title,
        'starts_at', e.starts_at,
        'place', e.place,
        'content', e.content,
        'rsvp_on', e.rsvp_on,
        'album_on', e.album_on,
        'published', e.published,
        'org_name', (select name from orgs where id = e.org_id),
        'preview', p_preview is not null and p_preview = e.preview_token);
end;
$$;

create or replace function event_rsvp(
    p_slug text, p_preview text, p_name text, p_people integer, p_answer text, p_message text, p_extra jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    e events;
    v_name text := nullif(trim(coalesce(p_name, '')), '');
    v_message text := nullif(trim(coalesce(p_message, '')), '');
    v_id uuid;
begin
    select * into e from events where slug = lower(trim(coalesce(p_slug, '')));
    if not found or not event_visible(e, p_preview) then
        raise exception 'Cette carte n''est pas ouverte.';
    end if;
    if not e.rsvp_on then
        raise exception 'Les réponses sont fermées pour cet événement.';
    end if;
    if v_name is null or length(v_name) > 80 then
        raise exception 'Votre nom, en 80 caractères au plus.';
    end if;
    if p_answer not in ('oui', 'non', 'mot') then
        raise exception 'Réponse inconnue.';
    end if;
    if p_people is not null and (p_people < 0 or p_people > 20) then
        raise exception 'Entre 0 et 20 personnes.';
    end if;
    if v_message is not null and length(v_message) > 1000 then
        raise exception 'Un mot de 1 000 caractères au plus.';
    end if;
    if p_extra is not null and (jsonb_typeof(p_extra) <> 'object' or length(p_extra::text) > 2000) then
        raise exception 'Réponse mal formée.';
    end if;
    if (select count(*) from event_rsvps where event_id = e.id) >= 2000 then
        raise exception 'Cet événement a reçu toutes les réponses qu''il peut tenir.';
    end if;
    insert into event_rsvps (event_id, name, people, answer, message, extra)
    values (e.id, v_name, coalesce(p_people, 1), p_answer, v_message, coalesce(p_extra, '{}'::jsonb))
    returning id into v_id;
    return v_id;
end;
$$;

-- ------------------------------------------------------------
-- Who may call what (063): the three doors open to the street, the rest
-- closed to it; the business's people keep what the policies give them.
-- ------------------------------------------------------------
revoke execute on function events_public_on()                                                  from public;
revoke execute on function events_open()                                                       from public;
revoke execute on function events_touch()                                                      from public;
revoke execute on function event_date_fr(timestamptz)                                          from public;
revoke execute on function event_slug(text)                                                    from public;
revoke execute on function event_create(uuid, text, text, text, timestamptz, text)             from public;
revoke execute on function events_options()                                                    from public;
revoke execute on function event_visible(events, text)                                         from public;
revoke execute on function event_public(text, text)                                            from public;
revoke execute on function event_rsvp(text, text, text, integer, text, text, jsonb)            from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function events_public_on()                                       from anon;
        revoke execute on function events_open()                                            from anon;
        revoke execute on function events_touch()                                           from anon;
        revoke execute on function event_date_fr(timestamptz)                               from anon;
        revoke execute on function event_slug(text)                                         from anon;
        revoke execute on function event_create(uuid, text, text, text, timestamptz, text)  from anon;
        revoke execute on function event_visible(events, text)                              from anon;
        grant  execute on function events_options()                                         to anon;
        grant  execute on function event_public(text, text)                                 to anon;
        grant  execute on function event_rsvp(text, text, text, integer, text, text, jsonb) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant  execute on function events_public_on()                                       to authenticated;
        grant  execute on function events_open()                                            to authenticated;
        grant  execute on function event_date_fr(timestamptz)                               to authenticated;
        grant  execute on function event_slug(text)                                         to authenticated;
        grant  execute on function event_create(uuid, text, text, text, timestamptz, text)  to authenticated;
        grant  execute on function events_options()                                         to authenticated;
        grant  execute on function event_public(text, text)                                 to authenticated;
        grant  execute on function event_rsvp(text, text, text, integer, text, text, jsonb) to authenticated;
        revoke execute on function event_visible(events, text)                              from authenticated;
        grant select, insert, update, delete on events               to authenticated;
        grant select, delete                 on event_rsvps          to authenticated;
        grant select, update, delete         on event_guest_photos   to authenticated;
    end if;
end $$;
