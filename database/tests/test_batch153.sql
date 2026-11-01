-- ============================================================
-- test_batch153.sql — 153: Événementiel, the fourth kind of business.
--
-- The claims:
--   1. installed twice, the same: forty-seven templates in two families
--      (twelve classic cards, twenty-one animated layouts, fourteen Premium
--      films); events.card references them; events.tz; the templates read
--      by a member, never by the street; what an Événementiel does
--      (business_activities); the six-argument event_create gone, the
--      seven-argument one a member's; the hour on the organiser's clock,
--      Ouagadougou's by default, an unknown zone falling back;
--   2. creating an Événementiel: refused to a person while the platform's
--      switch is off, made by a platform admin all the same, made by the
--      person once the switch is on — an 'events' business; update_org
--      takes the kind and refuses an unknown one; the request page may
--      offer the four kinds, keeps a list of three, none of four, and
--      refuses a fifth;
--   3. the cards are the Événementiel's: a shop's owner is refused by
--      event_create and sees no event, the switch on or not; the
--      Événementiel's owner makes a classic card and a Premium animated
--      one, an unknown template is refused, and the street's card says the
--      family and whether it is Premium;
--   4. the organiser's clock: the hour typed is the hour the card shows;
--      an unknown zone falls back to Ouagadougou's;
--   5. a card made under a shop before 153 goes with 153 (re-run here);
--      the Événementiel's cards stay.
-- Names: « Awa Événements », « Boutique Bako 153 ». Wrapped in one
-- transaction rolled back: runs twice the same.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
-- As on Supabase, where auth.uid() is every role's to call.
grant usage on schema auth to anon, authenticated;
-- Earlier suites re-apply older migrations over these functions (111's
-- create_my_business, 152's event_create): 153 again, twice — installed
-- twice, the same.
\i database/migrations/153_events_kind.sql
\i database/migrations/153_events_kind.sql
-- 154 (the edit token, event_public's third argument): restored after
-- 153's re-run, as the migrations run in order.
\i database/migrations/154_events_editor.sql
\i database/migrations/155_events_album.sql
\i database/migrations/156_events_published_open.sql

begin;

update platform_settings set value = 'false' where key = 'create_phone_verified';
delete from platform_settings where key = 'application_form';
update platform_settings set value = 'false' where key = 'events_public';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('15315315-0000-0000-0000-000000000001', '+22615310001', 'mara153@example.com', '{"full_name": "Mara Admin"}',    now()),
    ('15315315-0000-0000-0000-000000000002', '+22615310002', 'awa153@example.com',  '{"full_name": "Awa Planner"}',   now()),
    ('15315315-0000-0000-0000-000000000003', '+22615310003', 'bako153@example.com', '{"full_name": "Bako Boutique"}', now());
update profiles set is_platform_admin = true where id = '15315315-0000-0000-0000-000000000001';

insert into orgs (id, name, slug, profile, default_currency) values
    ('15315315-1111-0000-0000-000000000001', 'Boutique Bako 153', 'bako-153', 'retail', 'XOF');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('15315315-0000-0000-0000-000000000003', '15315315-1111-0000-0000-000000000001', 'owner', 'org',
     '15315315-1111-0000-0000-000000000001', 'full');

create temp table t153 (k text primary key, v text) on commit drop;
grant select, insert, update on t153 to authenticated;
grant select on t153 to anon;

-- 1. installed twice, the same
do $$
begin
    assert (select count(*) from event_templates) = 47, 'forty-seven templates';
    assert (select count(*) from event_templates where family = 'classique' and not premium) = 12, 'twelve classic cards';
    assert (select count(*) from event_templates where family = 'anime' and not premium) = 21, 'twenty-one animated layouts';
    assert (select count(*) from event_templates where family = 'anime' and premium) = 14, 'fourteen Premium films';
    assert (select count(distinct sort) from event_templates) = 47, 'each in its place';
    assert exists (select 1 from pg_constraint where conname = 'events_card_fkey'), 'events.card references the templates';
    assert exists (select 1 from information_schema.columns where table_name = 'events' and column_name = 'tz'), 'events.tz';
    assert (select relrowsecurity from pg_class where relname = 'event_templates'), 'the templates have row level security';
    assert has_table_privilege('authenticated', 'event_templates', 'select'), 'a member reads the templates';
    assert not has_table_privilege('anon', 'event_templates', 'select'), 'the street does not';
    assert business_activities('events') = array['mariage', 'famille', 'organisateur', 'entreprise', 'autre'],
        'what an Événementiel does';
    assert to_regprocedure('event_create(uuid, text, text, text, timestamptz, text)') is null, 'the six-argument form is gone';
    assert not (select prosecdef from pg_proc where oid = to_regprocedure('event_create(uuid, text, text, text, timestamptz, text, text)')),
        'event_create is SECURITY INVOKER still';
    assert has_function_privilege('authenticated', 'event_create(uuid, text, text, text, timestamptz, text, text)', 'execute'),
        'a member may create';
    assert not has_function_privilege('anon', 'event_create(uuid, text, text, text, timestamptz, text, text)', 'execute'),
        'the street may not';
    assert not has_function_privilege('public', 'event_create(uuid, text, text, text, timestamptz, text, text)', 'execute'),
        'nor PUBLIC';
    assert has_function_privilege('anon', 'event_public(text, text, text)', 'execute'), 'the street still opens a card';
    assert event_date_fr('2026-12-12 23:00+00', 'America/New_York') = 'Samedi 12 décembre 2026 · 18 h',
        'the hour on the organiser''s clock: ' || event_date_fr('2026-12-12 23:00+00', 'America/New_York');
    assert event_date_fr('2026-12-12 23:00+00') = 'Samedi 12 décembre 2026 · 23 h', 'Ouagadougou by default';
    assert event_date_fr('2026-12-12 23:00+00', 'Mars/Olympus') = 'Samedi 12 décembre 2026 · 23 h', 'an unknown zone falls back';
    assert event_date_fr('2027-02-13 18:30+00', 'Africa/Ouagadougou') = 'Samedi 13 février 2027 · 18 h 30', 'the half hour';
    assert event_date_fr('2026-12-12 23:00+00', '-05:00') = 'Samedi 12 décembre 2026 · 18 h',
        'the phone''s offset for the day: ' || event_date_fr('2026-12-12 23:00+00', '-05:00');
    assert event_date_fr('2026-12-12 23:00+00', '+05:30') = 'Dimanche 13 décembre 2026 · 4 h 30', 'an offset east';
    assert event_tz_known('Europe/Paris') and event_tz_known('-05:00') and event_tz_known('+14:00'), 'event_tz_known: a name, an offset';
    assert not event_tz_known('nope') and not event_tz_known(null) and not event_tz_known('+15:00'), 'event_tz_known: not these';
end $$;

-- 2. creating an Événementiel
do $$
declare
    v_org uuid;
    v_msg text;
    v_form jsonb;
begin
    -- A person, the switch off: refused.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15315315-0000-0000-0000-000000000002', true);
    begin
        v_org := create_my_business('events', 'Awa Événements', 'awa-evenements-153', 'organisateur',
                                    'Mariages et fêtes de famille', 'Ouagadougou', 'Dapoya', '+22670153002', 'XOF', null);
        v_msg := null;
    exception when others then v_msg := sqlerrm;
    end;
    assert v_msg = 'Ce type d''activité ne peut pas être créé pour l''instant.',
        'the switch off: a person cannot create an Événementiel: ' || coalesce(v_msg, 'created');
    begin
        v_org := create_my_business('cirque', 'Cirque', 'cirque-153', 'autre', null, 'Ouagadougou', null, '+22670153009', 'XOF', null);
        v_msg := null;
    exception when others then v_msg := sqlerrm;
    end;
    assert v_msg = 'Choisissez boutique, ferme, association ou événementiel.', 'a fifth kind: ' || coalesce(v_msg, 'created');

    -- A platform admin, the switch off: made.
    perform set_config('request.jwt.claim.sub', '15315315-0000-0000-0000-000000000001', true);
    v_org := create_my_business('events', 'Marakaj Fêtes', 'marakaj-fetes-153', 'entreprise',
                                null, 'Ouagadougou', null, '+22670153001', 'XOF', null);
    assert (select profile from orgs where id = v_org) = 'events', 'the platform admin''s Événementiel';
    insert into t153 values ('mara_org', v_org::text);
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);

    -- The switch on: the person makes hers.
    update platform_settings set value = 'true' where key = 'events_public';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15315315-0000-0000-0000-000000000002', true);
    v_org := create_my_business('events', 'Awa Événements', 'awa-evenements-153', 'organisateur',
                                'Mariages et fêtes de famille', 'Ouagadougou', 'Dapoya', '+22670153002', 'XOF', null);
    assert (select profile from orgs where id = v_org) = 'events', 'an events business';
    assert exists (select 1 from memberships where org_id = v_org and user_id = '15315315-0000-0000-0000-000000000002' and role = 'owner'),
        'owned by her';
    insert into t153 values ('awa_org', v_org::text);
    -- update_org takes the kind, refuses an unknown one.
    perform update_org(v_org, 'Awa Événements & Cie', null, 'events', null);
    assert (select name from orgs where id = v_org) = 'Awa Événements & Cie', 'renamed';
    begin
        perform update_org(v_org, null, null, 'cirque', null);
        v_msg := null;
    exception when others then v_msg := sqlerrm;
    end;
    assert v_msg like 'Unknown profile%', 'an unknown kind refused: ' || coalesce(v_msg, 'accepted');
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    -- What it does, kept (the platform's table: read here as the owner of the database).
    assert (select activity from business_creations where org_id = v_org) = 'organisateur', 'what it does, kept';

    -- The request page: four kinds to offer.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15315315-0000-0000-0000-000000000001', true);
    perform platform_set_application_form('{"kinds": ["retail", "farm", "association"]}'::jsonb);
    v_form := application_form();
    assert jsonb_array_length(v_form -> 'kinds') = 3 and not (v_form -> 'kinds' ? 'events'),
        'three of four: the list is kept: ' || v_form::text;
    perform platform_set_application_form('{"kinds": ["events", "retail", "farm", "association"]}'::jsonb);
    v_form := application_form();
    assert v_form is null or not (v_form ? 'kinds'), 'all four: no list: ' || coalesce(v_form::text, 'none');
    perform platform_set_application_form('{"kinds": ["events"]}'::jsonb);
    assert application_form() -> 'kinds' = '["events"]'::jsonb, 'events alone';
    begin
        perform platform_set_application_form('{"kinds": ["cirque"]}'::jsonb);
        v_msg := null;
    exception when others then v_msg := sqlerrm;
    end;
    assert v_msg = 'Les types proposés sont boutique, ferme, association ou événementiel.', 'a fifth kind on the page: ' || coalesce(v_msg, 'accepted');
    perform platform_set_application_form(null);
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- 3. the cards are the Événementiel's
do $$
declare
    v_awa uuid := (select v from t153 where k = 'awa_org')::uuid;
    r events;
    v_msg text;
    j jsonb;
begin
    -- The shop's owner, the switch on: refused, and sees nothing.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15315315-0000-0000-0000-000000000003', true);
    begin
        r := event_create('15315315-1111-0000-0000-000000000001', 'Soldes', 'gala', 'gala', null, null, null);
        v_msg := null;
    exception when others then v_msg := sqlerrm;
    end;
    assert v_msg = 'Les cartes d''événement se créent dans une activité Événementiel.',
        'a shop makes no card: ' || coalesce(v_msg, 'created');
    assert (select count(*) from events) = 0, 'and sees none';

    -- The Événementiel's owner: a classic card, a Premium animated one.
    perform set_config('request.jwt.claim.sub', '15315315-0000-0000-0000-000000000002', true);
    r := event_create(v_awa, 'Inès & Thomas', 'mariage', 'come', '2027-06-05 15:00+00', 'Villa Serena', 'Africa/Ouagadougou');
    assert r.card = 'come' and r.tz = 'Africa/Ouagadougou', 'the classic card';
    insert into t153 values ('slug1', r.slug), ('token1', r.preview_token);
    r := event_create(v_awa, 'Gala des Anciens', 'gala', 'anime_lotus_p', '2027-03-11 18:30+00', 'Hôtel Bravia', null);
    assert r.card = 'anime_lotus_p', 'the Premium animated card';
    insert into t153 values ('slug2', r.slug), ('token2', r.preview_token);
    begin
        r := event_create(v_awa, 'Sans modèle', 'mariage', 'nope', null, null, null);
        v_msg := null;
    exception when others then v_msg := sqlerrm;
    end;
    assert v_msg = 'Choisissez un modèle dans la liste.', 'an unknown template: ' || coalesce(v_msg, 'created');
    assert (select count(*) from events) = 2, 'she sees her two cards';
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);

    -- The street's card says the family.
    set local role anon;
    j := event_public((select v from t153 where k = 'slug1'), (select v from t153 where k = 'token1'));
    assert j ->> 'family' = 'classique' and not (j ->> 'premium')::boolean, 'a classic card: ' || j::text;
    assert j ->> 'tz' = 'Africa/Ouagadougou', 'with its clock';
    j := event_public((select v from t153 where k = 'slug2'), (select v from t153 where k = 'token2'));
    assert j ->> 'family' = 'anime' and (j ->> 'premium')::boolean, 'a Premium animated card: ' || j::text;
    assert j::text not like '%' || (select v from t153 where k = 'token2') || '%', 'the token never in the answer';
    reset role;
end $$;

-- 4. the organiser's clock
do $$
declare
    v_awa uuid := (select v from t153 where k = 'awa_org')::uuid;
    r events;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15315315-0000-0000-0000-000000000002', true);
    r := event_create(v_awa, 'Les 30 ans de Rose', 'anniversaire', 'anniv', '2026-12-12 23:00+00', 'Newark', 'America/New_York');
    assert r.tz = 'America/New_York', 'the zone kept';
    assert r.content ->> 't:date' = 'Samedi 12 décembre 2026 · 18 h', 'the hour typed is the hour shown: ' || (r.content ->> 't:date');
    r := event_create(v_awa, 'Sur Mars', 'anniversaire', 'anniv', '2026-12-12 23:00+00', null, 'Mars/Olympus');
    assert r.tz = 'Africa/Ouagadougou', 'an unknown zone falls back';
    assert r.content ->> 't:date' = 'Samedi 12 décembre 2026 · 23 h', 'on Ouagadougou''s clock';
    r := event_create(v_awa, 'Depuis le téléphone', 'anniversaire', 'anniv', '2026-12-12 23:00+00', null, '-05:00');
    assert r.tz = '-05:00' and r.content ->> 't:date' = 'Samedi 12 décembre 2026 · 18 h', 'the phone''s offset kept and used';
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- 5. a card made under a shop before 153 goes with 153
insert into events (org_id, kind, card, slug, preview_token, title)
values ('15315315-1111-0000-0000-000000000001', 'mariage', 'come', 'vieille-carte-153', repeat('a', 24), 'Vieille carte');
\i database/migrations/153_events_kind.sql
\i database/migrations/154_events_editor.sql
\i database/migrations/155_events_album.sql
\i database/migrations/156_events_published_open.sql
do $$
begin
    assert not exists (select 1 from events where slug = 'vieille-carte-153'), 'the shop''s old card is gone';
    assert (select count(*) from events e join orgs o on o.id = e.org_id where o.profile = 'events') = 5,
        'the Événementiel''s five cards stay';
    raise notice 'PASS: 153 — Événementiel is the fourth kind: created by Marakaj''s admins while the switch is off, by anyone once on; the cards are its alone, from forty-seven templates in two families, on the organiser''s clock';
end $$;

rollback;
