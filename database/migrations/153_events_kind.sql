-- ============================================================
-- 153_events_kind.sql — Événementiel, the fourth kind of business.
--
-- The owner, after 152: « It was supposed to be the fourth. Not in the
-- shop: in “create an activity” — shop, farm, association, and events. »
-- 152 had put « Événements » inside every business; this moves it to a
-- kind of its own, as asked:
--   * a business may now be an 'events' one (Événementiel), beside
--     retail, farm and association: create_my_business, update_org,
--     platform_update_org_identity and the request page's kinds (107)
--     accept it; business_activities says what such an activity does.
--     While the platform's switch (events_public, 152) is off, the kind
--     is Marakaj's admins' alone to create — the app offers it to nobody
--     else, and create_my_business refuses it too.
--   * the cards are the Événementiel's: every policy on events,
--     event_rsvps and event_guest_photos asks that the business be one,
--     and so does event_create. A shop, a farm or an association never
--     sees the module — it creates an Événementiel activity instead. The
--     one card made before this, under a shop, goes with it.
--   * event_templates: the designs one may choose, in two families —
--     « classique », the twelve photo-led cards of 152 (app/web/cartes),
--     and « anime », the twenty-one animated layouts and the fourteen
--     Premium films (app/web/evenements): the site picks the page by the
--     family, the app draws the gallery from this table. events.card now
--     references it.
--   * events.tz: the organiser's time zone, so the hour typed is the hour
--     the card shows (152 wrote every card on Ouagadougou's clock, and an
--     owner typing from another zone got the wrong hour). event_date_fr
--     takes the zone; event_create takes p_tz.
--
-- Shop, farm, association: untouched, except that the events entry they
-- never should have had is theirs no more. Re-runnable. No pgcrypto.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The templates
-- ------------------------------------------------------------
create table if not exists event_templates (
    key     text primary key check (key ~ '^[a-z0-9_]+$' and length(key) <= 40),
    family  text not null check (family in ('classique', 'anime')),
    name    text not null check (length(name) between 1 and 60),
    premium boolean not null default false,
    sort    integer not null default 0,
    -- The kinds of event the design was drawn for; empty: any.
    kinds   text[] not null default '{}',
    line    text not null default '' check (length(line) <= 120)
);
alter table event_templates enable row level security;
drop policy if exists "templates read by members" on event_templates;
create policy "templates read by members" on event_templates for select using (true);

insert into event_templates (key, family, name, premium, sort, kinds, line) values
    ('come', 'classique', 'Côme', false, 1, array['mariage'], 'Un lac, une villa, le soir'),
    ('ravello', 'classique', 'Ravello', false, 2, array['mariage'], 'Citronniers et terrasses'),
    ('sahel', 'classique', 'Sahel', false, 3, array['mariage'], 'Sable, acacias, lumière dorée'),
    ('jardin', 'classique', 'Jardin', false, 4, array['mariage'], 'Un jardin sous les arbres'),
    ('minuit', 'classique', 'Minuit', false, 5, array['mariage'], 'Ciel étoilé et compte à rebours'),
    ('anniv', 'classique', 'Trente', false, 6, array['anniversaire'], 'Une fête, des bougies'),
    ('bapteme', 'classique', 'Noé', false, 7, array['bapteme'], 'Blanc, doux, en famille'),
    ('naissance', 'classique', 'Imani', false, 8, array['naissance'], 'Un bébé arrive'),
    ('diplome', 'classique', 'Promotion', false, 9, array['diplome'], 'La toque et le diplôme'),
    ('gala', 'classique', 'Dix ans', false, 10, array['gala'], 'Une soirée habillée'),
    ('dot', 'classique', 'Dot', false, 11, array['dot'], 'Les deux familles'),
    ('hommage', 'classique', 'Hommage', false, 12, array['hommage'], 'En sa mémoire'),
    ('anime_lettre', 'anime', 'La Lettre', false, 13, '{}', 'Une enveloppe qui s''ouvre'),
    ('anime_jardin', 'anime', 'Le Jardin', false, 14, '{}', 'Une arche fleurie qui pousse'),
    ('anime_nuit', 'anime', 'La Nuit', false, 15, '{}', 'Du coucher de soleil aux étoiles'),
    ('anime_pagne', 'anime', 'Le Pagne', false, 16, '{}', 'Couleurs tissées du Faso'),
    ('anime_mag', 'anime', 'Le Magazine', false, 17, '{}', 'Une couverture et des pages'),
    ('anime_blason', 'anime', 'Le Blason', false, 18, '{}', 'Un monogramme royal'),
    ('anime_carnet', 'anime', 'Le Carnet', false, 19, '{}', 'Polaroïds et petits mots'),
    ('anime_sahel', 'anime', 'Sahel', false, 20, '{}', 'Acacias, girafe, coucher de soleil'),
    ('anime_lotus', 'anime', 'Le Lotus', false, 21, '{}', 'Un étang, des carpes koï, des lotus'),
    ('anime_foret', 'anime', 'La Forêt', false, 22, '{}', 'Brume, rayons de lumière, fougères'),
    ('anime_cerisiers', 'anime', 'Les Cerisiers', false, 23, '{}', 'Une branche en fleurs, des pétales au vent'),
    ('anime_tournesols', 'anime', 'Les Tournesols', false, 24, '{}', 'Des fleurs qui suivent le soleil'),
    ('anime_lanternes', 'anime', 'Les Lanternes', false, 25, '{}', 'Des lanternes qui s''envolent sur l''eau'),
    ('anime_roseraie', 'anime', 'La Roseraie', false, 26, '{}', 'Des rosiers grimpants qui fleurissent'),
    ('anime_desert', 'anime', 'Le Désert', false, 27, '{}', 'Une bande-annonce dans les dunes'),
    ('anime_champagne', 'anime', 'Champagne', false, 28, '{}', 'Bulles, paillettes et lumières'),
    ('anime_papillons', 'anime', 'Les Papillons', false, 29, '{}', 'Un nuage de papillons qui dessine un cœur'),
    ('anime_hiver', 'anime', 'Boule à neige', false, 30, '{}', 'Un village d''hiver qu''on secoue'),
    ('anime_feux', 'anime', 'Feux d''artifice', false, 31, '{}', 'Vos prénoms écrits par les étincelles'),
    ('anime_aurore', 'anime', 'L''Aurore', false, 32, '{}', 'Des aurores boréales sur un lac'),
    ('anime_ocean', 'anime', 'L''Océan', false, 33, '{}', 'Des cartes postales du bord de mer'),
    ('anime_sahel_p', 'anime', 'Savane d''or', true, 34, '{}', 'Soleil couchant, acacias, un horizon d''or'),
    ('anime_lotus_p', 'anime', 'Étang de lotus', true, 35, '{}', 'Eau vivante, carpes koï, médaillon de verre'),
    ('anime_foret_p', 'anime', 'Forêt enchantée', true, 36, '{}', 'Brume, rayons de lumière, lucioles'),
    ('anime_cerisiers_p', 'anime', 'Paravent de cerisiers', true, 37, '{}', 'Panneaux d''or, papiers, sceau rouge'),
    ('anime_tournesols_p', 'anime', 'Champ d''or', true, 38, '{}', 'Affiche audacieuse, tournesols au soleil'),
    ('anime_lanternes_p', 'anime', 'Nuit des lanternes', true, 39, '{}', 'Chaque chapitre est une lanterne'),
    ('anime_roseraie_p', 'anime', 'Velours & roses', true, 40, '{}', 'Roses épanouies, cartes ivoire, sceau de cire'),
    ('anime_desert_p', 'anime', 'Caravane des dunes', true, 41, '{}', 'Dunes éclairées, piste d''étape en étape'),
    ('anime_ocean_p', 'anime', 'Carte du rivage', true, 42, '{}', 'Vagues réelles, rose des vents, écume'),
    ('anime_champagne_p', 'anime', 'Champagne Gatsby', true, 43, '{}', 'Bulles, or et cadres Art déco'),
    ('anime_papillons_p', 'anime', 'Herbier aux papillons', true, 44, '{}', 'Vieux papier, planches, papillons vrais'),
    ('anime_hiver_p', 'anime', 'Fenêtre givrée', true, 45, '{}', 'Le givre gagne la vitre en défilant'),
    ('anime_feux_p', 'anime', 'Grand soir', true, 46, '{}', 'Vos prénoms écrits par les étincelles'),
    ('anime_aurore_p', 'anime', 'Boréale', true, 47, '{}', 'Aurores sur le lac, une constellation')
on conflict (key) do update
    set family = excluded.family, name = excluded.name, premium = excluded.premium,
        sort = excluded.sort, kinds = excluded.kinds, line = excluded.line;

-- events.card: from 152's fixed list to the table.
alter table events drop constraint if exists events_card_check;
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'events_card_fkey') then
        alter table events add constraint events_card_fkey
            foreign key (card) references event_templates(key);
    end if;
end $$;

-- ------------------------------------------------------------
-- 2. The organiser's clock
-- ------------------------------------------------------------
alter table events add column if not exists tz text not null default 'Africa/Ouagadougou';
alter table events drop constraint if exists events_tz_check;
alter table events add constraint events_tz_check check (length(tz) between 1 and 64);

-- « Samedi 12 décembre 2026 · 16 h » on the organiser's clock, a capital
-- first. The zone is a name Postgres knows (Africa/Ouagadougou,
-- America/New_York) or the phone's offset for that day (« -05:00 »: a
-- phone knows its offset for a date, not always its zone's name). An
-- unknown zone falls back to Ouagadougou's, never fails a card.
create or replace function event_date_fr(p_at timestamptz, p_tz text)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
    v_tz text := nullif(trim(coalesce(p_tz, '')), '');
    l timestamp;
    s text;
begin
    if p_at is null then
        return null;
    end if;
    begin
        if v_tz ~ '^[+-][0-9]{2}:[0-9]{2}$' then
            l := p_at at time zone (v_tz || ':00')::interval;
        else
            l := p_at at time zone coalesce(v_tz, 'Africa/Ouagadougou');
        end if;
    exception when others then
        l := p_at at time zone 'Africa/Ouagadougou';
    end;
    s := (array['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'])
             [extract(dow from l)::int + 1]
         || ' ' || extract(day from l)::int
         || ' ' || (array['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
                          'septembre', 'octobre', 'novembre', 'décembre'])[extract(month from l)::int]
         || ' ' || extract(year from l)::int
         || ' · ' || extract(hour from l)::int || ' h'
         || case when extract(minute from l)::int > 0
                 then ' ' || lpad(extract(minute from l)::int::text, 2, '0') else '' end;
    return upper(left(s, 1)) || substr(s, 2);
end;
$$;

-- 152's one-argument form, kept for whoever calls it: Ouagadougou's clock.
create or replace function event_date_fr(p_at timestamptz)
returns text
language sql
stable
set search_path = public
as $$
    select event_date_fr(p_at, 'Africa/Ouagadougou');
$$;

-- Whether a time zone is one Postgres knows: a name, or an offset for the
-- day (« +00:00 » to « -12:00 », as a phone says it).
create or replace function event_tz_known(p_tz text)
returns boolean
language plpgsql
stable
set search_path = public
as $$
begin
    if p_tz is null or trim(p_tz) = '' or length(p_tz) > 64 then
        return false;
    end if;
    if trim(p_tz) ~ '^[+-][0-9]{2}:[0-9]{2}$' then
        return (trim(p_tz) || ':00')::interval between interval '-14 hours' and interval '14 hours';
    end if;
    perform now() at time zone trim(p_tz);
    return true;
exception when others then
    return false;
end;
$$;

-- ------------------------------------------------------------
-- 3. The cards are the Événementiel's
-- ------------------------------------------------------------
-- The card made under a shop before the kind existed (the owner's own
-- test): it can be neither seen nor managed from now on, so it goes.
delete from events e using orgs o where o.id = e.org_id and o.profile is distinct from 'events';

drop policy if exists "events seen by the business's admins" on events;
create policy "events seen by the business's admins"
on events for select
using (is_org_admin(org_id) and events_open()
       and exists (select 1 from orgs o where o.id = org_id and o.profile = 'events'));

drop policy if exists "events written by the business's admins" on events;
create policy "events written by the business's admins"
on events for insert
with check (is_org_admin(org_id) and events_open()
            and exists (select 1 from orgs o where o.id = org_id and o.profile = 'events'));

drop policy if exists "events changed by the business's admins" on events;
create policy "events changed by the business's admins"
on events for update
using (is_org_admin(org_id) and events_open()
       and exists (select 1 from orgs o where o.id = org_id and o.profile = 'events'))
with check (is_org_admin(org_id) and events_open()
            and exists (select 1 from orgs o where o.id = org_id and o.profile = 'events'));

drop policy if exists "events deleted by the business's admins" on events;
create policy "events deleted by the business's admins"
on events for delete
using (is_org_admin(org_id) and events_open()
       and exists (select 1 from orgs o where o.id = org_id and o.profile = 'events'));

-- The answers and the photos follow their event: an event is only ever an
-- Événementiel's now, so the policies of 152 hold as they are.

-- event_create (152), with the kind of the business, the template looked up
-- and the organiser's clock. SECURITY INVOKER still: the insert is the
-- policies'. The six-argument form goes, so a call names one function.
drop function if exists event_create(uuid, text, text, text, timestamptz, text);
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
    v_hex text;
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
            -- The preview token: 24 of the 30 random hex characters of one
            -- gen_random_uuid(), the version (13th) and variant (17th) nibbles
            -- left out as 023 does — no pgcrypto, same on CI and on Supabase.
            v_hex := replace(gen_random_uuid()::text, '-', '');
            v_hex := substr(v_hex, 1, 12) || substr(v_hex, 14, 3) || substr(v_hex, 18, 15);
            insert into events (org_id, created_by, kind, card, slug, preview_token, title, starts_at,
                                place, content, tz)
            values (p_org, auth.uid(), v_kind, v_card, event_slug(v_title),
                    left(v_hex, 24), v_title, p_starts_at, v_place, v_content, v_tz)
            returning * into v_row;
            return v_row;
        exception when unique_violation then
            v_try := v_try + 1;
            if v_try > 5 then raise; end if;
        end;
    end loop;
end;
$$;

-- The card for the street (152), now with the template's family — the site
-- picks the page by it — and the organiser's clock.
create or replace function event_public(p_slug text, p_preview text default null)
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
    if not found or not event_visible(e, p_preview) then
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
        'preview', p_preview is not null and p_preview = e.preview_token);
end;
$$;

-- ------------------------------------------------------------
-- 4. The fourth kind, known to the business functions
-- ------------------------------------------------------------
-- 111's, with what an Événementiel does.
create or replace function business_activities(p_kind text)
returns text[]
language sql
immutable
set search_path = public
as $$
    select case p_kind
        when 'retail' then array['alimentation', 'telephonie', 'vetements', 'beaute',
                                 'restaurant', 'quincaillerie', 'autre']
        when 'farm' then array['volaille', 'elevage', 'maraichage', 'cereales', 'mixte', 'autre']
        when 'association' then array['tontine', 'eglise', 'groupement', 'culturelle',
                                      'sportive', 'autre']
        when 'events' then array['mariage', 'famille', 'organisateur', 'entreprise', 'autre']
        else array[]::text[] end;
$$;

-- update_org — 147's, 'events' among the kinds.
create or replace function update_org(
    p_org_id   uuid,
    p_name     text default null,
    p_slug     text default null,
    p_profile  text default null,
    p_currency text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor   uuid := auth.uid();
    v_name    text := nullif(btrim(coalesce(p_name, '')), '');
    v_slug    text := nullif(lower(btrim(coalesce(p_slug, ''))), '');
    v_profile text := nullif(btrim(coalesce(p_profile, '')), '');
    v_problem text;
    v_old     text;
begin
    if v_actor is null then
        raise exception 'update_org() needs a signed-in caller';
    end if;

    if not is_org_admin(p_org_id) then
        raise exception 'You cannot change this business';
    end if;

    select profile::text into v_old from orgs where id = p_org_id;
    if not found then
        raise exception 'No such business';
    end if;

    if exists (select 1 from orgs where id = p_org_id and archived_at is not null) then
        raise exception 'This business is archived. Restore it before changing it.';
    end if;

    if v_slug is not null then
        v_problem := org_slug_problem(v_slug);
        if v_problem is not null then
            raise exception '%', v_problem;
        end if;
        if exists (select 1 from orgs where slug = v_slug and id <> p_org_id) then
            raise exception 'That address is already taken.';
        end if;
        if business_address_reserved(v_slug)
           and not caller_is_platform_admin()
           and not exists (select 1 from orgs where id = p_org_id and slug = v_slug) then
            raise exception 'Cette adresse est réservée à Marakaj : choisissez-en une autre.';
        end if;
    end if;

    if v_profile is not null
       and v_profile not in ('church', 'association', 'farm', 'retail', 'events', 'generic') then
        raise exception 'Unknown profile: %', v_profile;
    end if;
    if v_profile is not null and v_profile is distinct from v_old then
        if not is_org_owner(p_org_id) then
            raise exception 'Seul le propriétaire change le genre d''activité';
        end if;
        perform notify_org_owners(p_org_id, 'org_kind_changed',
            'Le genre de votre activité a été changé',
            jsonb_build_object('profile', v_profile));
    end if;

    update orgs set
        name             = coalesce(v_name, name),
        slug             = coalesce(v_slug, slug),
        profile          = coalesce(v_profile, profile),
        default_currency = coalesce(nullif(btrim(coalesce(p_currency, '')), ''),
                                    default_currency)
    where id = p_org_id;

    return p_org_id;
end;
$$;

-- platform_update_org_identity — 147's, 'events' among the kinds (no chart
-- of its own: the generic one of org_create_core serves).
create or replace function platform_update_org_identity(
    p_org      uuid,
    p_name     text    default null,
    p_profile  text    default null,
    p_slug     text    default null,
    p_currency text    default null,
    p_phone    text    default null,
    p_address  text    default null,
    p_verified boolean default null,
    p_confirm  text    default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    o         orgs%rowtype;
    v_old     jsonb;
    v_new     jsonb;
    v_before  jsonb := '{}'::jsonb;
    v_after   jsonb := '{}'::jsonb;
    v_name    text := nullif(btrim(coalesce(p_name, '')), '');
    v_profile text := nullif(btrim(coalesce(p_profile, '')), '');
    v_slug    text := nullif(lower(btrim(coalesce(p_slug, ''))), '');
    v_cur     text := nullif(upper(btrim(coalesce(p_currency, ''))), '');
    v_problem text;
    v_col     text;
    v_cols    text[];
    v_action  uuid;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à l''équipe Marakaj';
    end if;
    select * into o from orgs where id = p_org for update;
    if not found then
        raise exception 'Entreprise inconnue';
    end if;
    if o.archived_at is not null then
        raise exception 'Cette activité est archivée : restaurez-la avant de la modifier';
    end if;
    if p_name is not null and v_name is null then
        raise exception 'Le nom de l''activité ne peut pas être vide';
    end if;
    if v_slug is not null and v_slug is distinct from o.slug then
        v_problem := org_slug_problem(v_slug);
        if v_problem is not null then
            raise exception '%', v_problem;
        end if;
        if exists (select 1 from orgs where slug = v_slug and id <> p_org) then
            raise exception 'Cette adresse est déjà prise';
        end if;
    end if;
    if v_profile is not null and v_profile is distinct from o.profile::text then
        if v_profile not in ('retail', 'farm', 'association', 'events') then
            raise exception 'Type d''activité inconnu : %', v_profile;
        end if;
        if lower(btrim(coalesce(p_confirm, ''))) <> lower(btrim(o.name)) then
            raise exception 'Pour changer le type d''activité, tapez le nom de l''activité : %', o.name;
        end if;
    end if;
    if v_cur is not null and v_cur !~ '^[A-Z]{3}$' then
        raise exception 'Monnaie inconnue : %', p_currency;
    end if;
    if p_verified is not null
       and p_verified is distinct from (o.verified_at is not null)
       and coalesce(v_profile, o.profile::text) not in ('association', 'church') then
        raise exception 'La vérification par Marakaj concerne les associations';
    end if;

    v_old := to_jsonb(o);
    perform set_config('mara.logged_write', 'on', true);
    update orgs set
        name             = coalesce(v_name, name),
        slug             = coalesce(v_slug, slug),
        profile          = coalesce(v_profile, profile::text),
        default_currency = coalesce(v_cur, default_currency),
        phone            = case when p_phone is null then phone
                                else nullif(btrim(p_phone), '') end,
        address          = case when p_address is null then address
                                else nullif(btrim(p_address), '') end,
        verified_at      = case when p_verified is null then verified_at
                                when p_verified then coalesce(verified_at, now()) end,
        verified_by      = case when p_verified is null then verified_by
                                when p_verified then coalesce(verified_by, auth.uid()) end
     where id = p_org
    returning to_jsonb(orgs) into v_new;
    perform set_config('mara.logged_write', '', true);

    foreach v_col in array mara_edit_columns('identity') loop
        if v_old -> v_col is distinct from v_new -> v_col then
            v_before := v_before || jsonb_build_object(v_col, v_old -> v_col);
            v_after  := v_after  || jsonb_build_object(v_col, v_new -> v_col);
        end if;
    end loop;
    if v_before = '{}'::jsonb then
        return null;
    end if;

    -- A new kind finds its own chart of accounts (create_org's, 035);
    -- nothing of the old one is removed.
    if v_after ? 'profile' then
        case v_after ->> 'profile'
            when 'association' then perform seed_church_accounts(p_org);
            when 'retail'      then perform seed_retail_accounts(p_org);
            when 'farm'        then perform seed_farm_accounts(p_org);
            else null;
        end case;
    end if;

    v_action := platform_log_action(p_org, 'identity',
        mara_edit_summary('identity', v_after), v_before, v_after,
        'platform_undo_org_columns',
        jsonb_build_object('org', p_org, 'what', 'identity',
                           'before', v_before, 'after', v_after));
    v_cols := mara_edit_keys('identity', v_after);
    perform notify_org_owners(p_org, 'mara_edited',
        mara_edit_message('identity', v_cols, false),
        jsonb_build_object('what', 'identity', 'fields', to_jsonb(v_cols), 'action', v_action));
    return v_action;
end;
$$;

-- create_my_business — 147's, with the fourth kind and its gate.
create or replace function create_my_business(
    p_profile  text,
    p_name     text,
    p_slug     text,
    p_activity text  default null,
    p_about    text  default null,
    p_city     text  default null,
    p_area     text  default null,
    p_phone    text  default null,
    p_currency text  default 'XOF',
    p_answers  jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_profile  text := lower(btrim(coalesce(p_profile, '')));
    v_name     text := nullif(btrim(coalesce(p_name, '')), '');
    v_slug     text := lower(btrim(coalesce(p_slug, '')));
    v_activity text := nullif(lower(btrim(coalesce(p_activity, ''))), '');
    v_about    text := nullif(btrim(coalesce(p_about, '')), '');
    v_city     text := nullif(btrim(coalesce(p_city, '')), '');
    v_area     text := nullif(btrim(coalesce(p_area, '')), '');
    v_phone    text := nullif(regexp_replace(coalesce(p_phone, ''), '[\s().-]', '', 'g'), '');
    v_currency text := upper(coalesce(nullif(btrim(coalesce(p_currency, '')), ''), 'XOF'));
    v_proved   text;
    v_form     jsonb := application_form();
    v_answers  jsonb;
    v_problem  text;
    v_org      uuid;
    v_full     text;
    v_cphone   text;
    v_email    text;
begin
    if v_actor is null then
        raise exception 'Connectez-vous pour créer votre activité.';
    end if;

    -- The platform's switch: a number proved on WhatsApp first.
    v_proved := my_verified_phone();
    if create_phone_required() and v_proved is null then
        raise exception 'Vérifiez d''abord votre numéro WhatsApp';
    end if;

    if v_profile = 'church' then
        v_profile := 'association';
    end if;
    if v_profile not in ('retail', 'farm', 'association', 'events') then
        raise exception 'Choisissez boutique, ferme, association ou événementiel.';
    end if;
    -- Événementiel (153): the kind exists for Marakaj's admins until the
    -- platform's switch (events_public) opens it to everyone.
    if v_profile = 'events' and not events_open() then
        raise exception 'Ce type d''activité ne peut pas être créé pour l''instant.';
    end if;
    -- The kinds the creation page offers (107's form).
    if v_form is not null and jsonb_typeof(v_form -> 'kinds') = 'array'
       and not ((v_form -> 'kinds') ? v_profile) then
        raise exception 'Ce type d''activité ne peut pas être créé pour l''instant.';
    end if;

    if v_name is null then
        raise exception 'Le nom de votre activité, s''il vous plaît.';
    end if;
    if char_length(v_name) > 80 then
        raise exception 'Un nom de 80 caractères au plus.';
    end if;

    v_problem := org_slug_problem(v_slug);
    if v_problem is not null then
        raise exception '%', v_problem;
    end if;
    if business_address_reserved(v_slug) then
        raise exception 'Cette adresse est réservée à Marakaj : choisissez-en une autre.';
    end if;

    if v_activity is null then
        raise exception 'Dites ce que fait votre activité.';
    end if;
    if not v_activity = any (business_activities(v_profile)) then
        raise exception 'Choisissez ce que fait votre activité dans la liste.';
    end if;
    -- The vitrine's sentence, as the setup and the settings keep it (80).
    if char_length(coalesce(v_about, '')) > 80 then
        raise exception 'Une phrase de 80 caractères au plus.';
    end if;

    if v_city is null then
        raise exception 'La ville, s''il vous plaît.';
    end if;
    if char_length(v_city) > 60 or char_length(coalesce(v_area, '')) > 80 then
        raise exception 'La ville fait 60 caractères au plus, le quartier 80.';
    end if;

    -- The business's phone: the one typed, else the proved one.
    v_phone := coalesce(v_phone, v_proved);
    if v_phone is null then
        raise exception 'Le numéro de votre activité, s''il vous plaît.';
    end if;
    if left(v_phone, 2) = '00' then
        v_phone := '+' || substr(v_phone, 3);
    end if;
    if v_phone !~ '^\+[1-9][0-9]{7,14}$' then
        raise exception 'Ce numéro n''est pas valide : l''indicatif du pays, puis le numéro.';
    end if;

    if v_currency !~ '^[A-Z]{3}$' then
        raise exception 'Une monnaie s''écrit en trois lettres (XOF, GHS…).';
    end if;

    -- The page's questions, as 107 checks a request's.
    v_answers := business_answers(v_form, p_answers);

    -- One person, one creation at a time: two taps cannot both pass the
    -- rule below.
    perform pg_advisory_xact_lock(hashtext('create_my_business:' || v_actor::text));

    -- Three a day at most, whatever the plan: a loop of creations is not a
    -- person starting a business. Counted in the journal, which keeps the
    -- line even when the business is deleted afterwards.
    if (select count(*) from platform_actions
         where actor = v_actor and kind = 'business_created'
           and at > now() - interval '24 hours') >= 3 then
        raise exception 'Vous avez déjà créé 3 activités en 24 heures : c''est le maximum, réessayez demain.';
    end if;

    -- One free business per person; a second needs Mara Pro (099).
    if second_business_locked(v_actor) then
        raise exception '%', path_lock_message('second_business');
    end if;

    if exists (select 1 from orgs where slug = v_slug) then
        raise exception 'Cette adresse est déjà prise : choisissez-en une autre.';
    end if;

    begin
        v_org := org_create_core(v_actor, v_name, v_slug, v_profile, v_currency);
    exception when unique_violation then
        raise exception 'Cette adresse vient d''être prise : choisissez-en une autre.';
    end;

    -- Where the business keeps what it said: the setup and the vitrine
    -- start from it (102's kind and sentence for an association).
    update orgs
       set city             = v_city,
           address          = v_area,
           phone            = v_phone,
           storefront_blurb = v_about,
           association_kind = case when v_profile = 'association' then v_activity
                                   else association_kind end
     where id = v_org;

    select coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                    nullif(btrim(coalesce(p.full_name, '')), ''),
                    nullif(btrim(coalesce(u.raw_user_meta_data ->> 'full_name', '')), '')),
           coalesce(nullif(btrim(coalesce(p.phone, '')), ''),
                    nullif(btrim(coalesce(u.phone, '')), '')),
           nullif(btrim(coalesce(u.email, '')), '')
      into v_full, v_cphone, v_email
      from auth.users u
      left join profiles p on p.id = u.id
     where u.id = v_actor;

    insert into business_creations (org_id, created_by, activity, about, city, area, phone,
                                    answers, contact_name, contact_phone, contact_email)
    values (v_org, v_actor, v_activity, v_about, v_city, v_area, v_phone,
            v_answers, v_full, v_cphone, v_email);

    -- A request still waiting from an older app is what this became: it
    -- is closed with the business, so it can never be approved into a
    -- second one.
    update org_applications
       set status        = 'approved',
           name          = v_name,
           slug          = v_slug,
           profile       = v_profile,
           org_id        = v_org,
           reviewed_at   = now(),
           decision_note = 'Créée directement par la personne'
     where applicant_id = v_actor and status = 'pending';

    -- The platform's journal: who created what. Nothing to undo — the
    -- business is the person's; Mara archives it from its fiche if needed.
    insert into platform_actions (at, actor, org_id, kind, summary, before, after)
    values (clock_timestamp(), v_actor, v_org, 'business_created',
            'Activité créée : ' || v_name || ' (' || v_slug || ') — '
                || case v_profile when 'retail' then 'boutique'
                                  when 'farm' then 'ferme'
                                  when 'events' then 'événementiel'
                                  else 'association' end
                || ', ' || v_city,
            null,
            jsonb_build_object('name', v_name, 'slug', v_slug, 'profile', v_profile,
                               'activity', v_activity, 'city', v_city, 'area', v_area,
                               'phone', v_phone, 'currency', v_currency,
                               'answers', coalesce(v_answers, '[]'::jsonb)));

    return v_org;
end;
$$;

-- platform_set_application_form — 107's, four kinds to offer.
create or replace function platform_set_application_form(p_form jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_in       jsonb := case when p_form = 'null'::jsonb or p_form = '{}'::jsonb then null else p_form end;
    v_out      jsonb;
    v_before   jsonb;
    v_text     text;
    v_kinds    jsonb;
    v_qs       jsonb := '[]'::jsonb;
    v_ids      text[] := '{}';
    q          jsonb;
    v_id       text;
    v_label    text;
    v_help     text;
    v_type     text;
    v_opts     jsonb;
    v_opt      text;
    v_clean    jsonb;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;

    if v_in is not null then
        if jsonb_typeof(v_in) <> 'object' then
            raise exception 'La page de demande est mal formée.';
        end if;
        v_out := '{}'::jsonb;

        v_text := nullif(btrim(coalesce(v_in ->> 'welcome', '')), '');
        if v_text is not null then
            if char_length(v_text) > 600 then
                raise exception 'Le mot d''accueil fait 600 caractères au plus.';
            end if;
            v_out := v_out || jsonb_build_object('welcome', v_text);
        end if;

        if v_in ? 'kinds' and v_in -> 'kinds' <> 'null'::jsonb then
            if jsonb_typeof(v_in -> 'kinds') <> 'array'
               or exists (select 1 from jsonb_array_elements_text(v_in -> 'kinds') k
                           where k not in ('retail', 'farm', 'association', 'events')) then
                raise exception 'Les types proposés sont boutique, ferme, association ou événementiel.';
            end if;
            select jsonb_agg(k order by array_position(array['association', 'farm', 'retail', 'events'], k))
              into v_kinds
              from (select distinct k from jsonb_array_elements_text(v_in -> 'kinds') k) d;
            if v_kinds is null then
                raise exception 'Proposez au moins un type d''activité.';
            end if;
            -- All four is today's page: no list kept.
            if jsonb_array_length(v_kinds) < 4 then
                v_out := v_out || jsonb_build_object('kinds', v_kinds);
            end if;
        end if;

        if v_in ? 'questions' and v_in -> 'questions' <> 'null'::jsonb then
            if jsonb_typeof(v_in -> 'questions') <> 'array' then
                raise exception 'Les questions sont une liste.';
            end if;
            if jsonb_array_length(v_in -> 'questions') > 12 then
                raise exception 'Douze questions au plus.';
            end if;
            for q in select value from jsonb_array_elements(v_in -> 'questions') loop
                if jsonb_typeof(q) <> 'object' then
                    raise exception 'Une question est mal formée.';
                end if;
                v_label := nullif(btrim(coalesce(q ->> 'label', '')), '');
                if v_label is null then
                    raise exception 'Chaque question a son intitulé.';
                end if;
                if char_length(v_label) > 120 then
                    raise exception 'Un intitulé fait 120 caractères au plus.';
                end if;
                v_help := nullif(btrim(coalesce(q ->> 'help', '')), '');
                if v_help is not null and char_length(v_help) > 200 then
                    raise exception 'Une aide fait 200 caractères au plus.';
                end if;
                v_type := coalesce(nullif(q ->> 'type', ''), 'text');
                if v_type not in ('text', 'choice', 'number', 'yesno') then
                    raise exception 'Une question est un texte, un choix, un nombre ou oui-non.';
                end if;
                v_opts := null;
                if v_type = 'choice' then
                    if jsonb_typeof(q -> 'options') <> 'array' then
                        raise exception 'Une question à choix a de 2 à 12 réponses.';
                    end if;
                    v_opts := '[]'::jsonb;
                    for v_opt in select btrim(o) from jsonb_array_elements_text(q -> 'options') o loop
                        if v_opt = '' then
                            continue;
                        end if;
                        if char_length(v_opt) > 60 then
                            raise exception 'Une réponse proposée fait 60 caractères au plus.';
                        end if;
                        if v_opts ? v_opt then
                            raise exception 'Une réponse proposée ne se répète pas.';
                        end if;
                        v_opts := v_opts || to_jsonb(v_opt);
                    end loop;
                    if jsonb_array_length(v_opts) < 2 or jsonb_array_length(v_opts) > 12 then
                        raise exception 'Une question à choix a de 2 à 12 réponses.';
                    end if;
                end if;
                -- A question keeps its id, so answers already given still
                -- name it; a new one gets its own.
                v_id := q ->> 'id';
                if v_id is null or v_id !~ '^[a-z0-9_-]{1,40}$' or v_id = any (v_ids) then
                    v_id := 'q' || substr(md5(random()::text || clock_timestamp()::text), 1, 8);
                end if;
                v_ids := v_ids || v_id;
                v_clean := jsonb_build_object(
                    'id', v_id, 'label', v_label, 'type', v_type,
                    'required', coalesce(q -> 'required' = 'true'::jsonb, false));
                if v_help is not null then
                    v_clean := v_clean || jsonb_build_object('help', v_help);
                end if;
                if v_opts is not null then
                    v_clean := v_clean || jsonb_build_object('options', v_opts);
                end if;
                v_qs := v_qs || jsonb_build_array(v_clean);
            end loop;
            if jsonb_array_length(v_qs) > 0 then
                v_out := v_out || jsonb_build_object('questions', v_qs);
            end if;
        end if;
        v_in := nullif(v_out, '{}'::jsonb);
    end if;

    select s.value into v_before from platform_settings s where s.key = 'application_form';
    if v_before is not distinct from v_in then
        return null;
    end if;
    if v_in is null then
        delete from platform_settings where key = 'application_form';
    else
        insert into platform_settings (key, value) values ('application_form', v_in)
        on conflict (key) do update set value = excluded.value;
    end if;

    return platform_log_action(
        null,
        'application_form',
        case when v_in is null then 'Page de demande remise comme avant'
             else 'Page de demande modifiée — '
                  || coalesce(jsonb_array_length(v_in -> 'questions'), 0) || ' question(s), '
                  || coalesce((select string_agg(case k when 'retail' then 'boutique'
                                                         when 'farm' then 'ferme'
                                                         else 'association' end, ', ')
                                 from jsonb_array_elements_text(v_in -> 'kinds') k),
                              'tous les types')
        end,
        jsonb_build_object('form', v_before),
        jsonb_build_object('form', v_in),
        'platform_restore_application_form',
        jsonb_build_object('form', v_before, 'expect', v_in));
end;
$$;

-- ------------------------------------------------------------
-- 5. Who may call what (063)
-- ------------------------------------------------------------
revoke execute on function event_date_fr(timestamptz, text)                                       from public;
revoke execute on function event_date_fr(timestamptz)                                             from public;
revoke execute on function event_tz_known(text)                                                   from public;
revoke execute on function event_create(uuid, text, text, text, timestamptz, text, text)          from public;
revoke execute on function event_public(text, text)                                               from public;
revoke execute on function business_activities(text)                                              from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function event_date_fr(timestamptz, text)                              from anon;
        revoke execute on function event_date_fr(timestamptz)                                    from anon;
        revoke execute on function event_tz_known(text)                                          from anon;
        revoke execute on function event_create(uuid, text, text, text, timestamptz, text, text) from anon;
        revoke execute on function business_activities(text)                                     from anon;
        grant  execute on function event_public(text, text)                                      to anon;
        revoke select on event_templates from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant  execute on function event_date_fr(timestamptz, text)                              to authenticated;
        grant  execute on function event_date_fr(timestamptz)                                    to authenticated;
        grant  execute on function event_tz_known(text)                                          to authenticated;
        grant  execute on function event_create(uuid, text, text, text, timestamptz, text, text) to authenticated;
        grant  execute on function event_public(text, text)                                      to authenticated;
        revoke execute on function business_activities(text)                                     from authenticated;
        grant  select on event_templates to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
