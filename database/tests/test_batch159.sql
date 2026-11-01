-- ============================================================
-- test_batch159.sql — 159: the reminder the day before.
--
-- The claims:
--   1. installed twice, the same: the tick tells a published card's
--      admins the day before its event — how many said yes, how many
--      people, how many left a WhatsApp — once; a card not published, or
--      whose event is the day after tomorrow, or already told: nothing;
--   2. the event's own clock counts (an offset the phone gave), and the
--      tick is nobody's to call on the street.
-- Wrapped in one transaction rolled back: runs twice the same.
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
grant usage on schema auth to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- Installed twice, the same.
\i database/migrations/159_events_reminder.sql
\i database/migrations/159_events_reminder.sql

begin;

update platform_settings set value = 'true' where key = 'events_public';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('15915915-0000-0000-0000-000000000001', '+22615910001', 'awa159@example.com', '{"full_name": "Awa Planner"}', now()),
    ('15915915-0000-0000-0000-000000000002', '+22615910002', 'sam159@example.com', '{"full_name": "Sam Vendeur"}', now());
insert into orgs (id, name, slug, profile, default_currency) values
    ('15915915-1111-0000-0000-000000000001', 'Awa Événements 159', 'awa-evenements-159', 'events', 'XOF');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('15915915-0000-0000-0000-000000000001', '15915915-1111-0000-0000-000000000001', 'owner', 'org', '15915915-1111-0000-0000-000000000001', 'full'),
    ('15915915-0000-0000-0000-000000000002', '15915915-1111-0000-0000-000000000001', 'employee', 'org', '15915915-1111-0000-0000-000000000001', 'full');

-- Tomorrow at 15 h, the day after at 15 h, on Ouagadougou's clock.
create temp table t159 as
select (((now() at time zone 'Africa/Ouagadougou')::date + 1) + time '15:00') at time zone 'Africa/Ouagadougou' as tomorrow,
       (((now() at time zone 'Africa/Ouagadougou')::date + 2) + time '15:00') at time zone 'Africa/Ouagadougou' as after;

insert into events (org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, tz, published)
select '15915915-1111-0000-0000-000000000001'::uuid, '15915915-0000-0000-0000-000000000001'::uuid, 'mariage', 'come',
       'ines-thomas-159', 'aaaaaaaaaaaaaaaaaaaaaaa9', 'bbbbbbbbbbbbbbbbbbbbbbb9', 'Inès & Thomas', tomorrow, 'Villa Serena', '{}'::jsonb, 'Africa/Ouagadougou', true
  from t159
union all
select '15915915-1111-0000-0000-000000000001'::uuid, '15915915-0000-0000-0000-000000000001'::uuid, 'gala', 'gala',
       'brouillon-159', 'ccccccccccccccccccccccc9', 'ddddddddddddddddddddddd9', 'Brouillon', tomorrow, null::text, '{}'::jsonb, 'Africa/Ouagadougou', false
  from t159
union all
select '15915915-1111-0000-0000-000000000001'::uuid, '15915915-0000-0000-0000-000000000001'::uuid, 'anniversaire', 'anniv',
       'apres-demain-159', 'eeeeeeeeeeeeeeeeeeeeeee9', 'fffffffffffffffffffffff9', 'Après-demain', after, null::text, '{}'::jsonb, 'Africa/Ouagadougou', true
  from t159;

insert into event_rsvps (event_id, name, people, answer, extra)
select id, 'Tanti Rose', 2, 'oui', '{"whatsapp": "+226 70 12 34 56"}'::jsonb from events where slug = 'ines-thomas-159'
union all select id, 'Oncle Sam', 3, 'oui', '{}'::jsonb from events where slug = 'ines-thomas-159'
union all select id, 'Cousine Léa', 1, 'non', '{"whatsapp": "70 00 00 00"}'::jsonb from events where slug = 'ines-thomas-159';

-- 1. the tick, once
do $$
declare
    v_n integer;
    n record;
begin
    v_n := events_tomorrow_tick();
    assert v_n = 1, 'one card is tomorrow, published: ' || v_n;
    select * into n from notifications
     where kind = 'event_tomorrow' and recipient_id = '15915915-0000-0000-0000-000000000001';
    assert found, 'the owner is told';
    assert n.message like 'Demain : « Inès & Thomas » — 2 invités ont dit oui (5 personnes).%', 'in words: ' || n.message;
    assert (n.params ->> 'yes')::int = 2 and (n.params ->> 'people')::int = 5 and (n.params ->> 'whatsapp')::int = 1
       and n.params ->> 'slug' = 'ines-thomas-159' and n.params ->> 'title' = 'Inès & Thomas',
        'and in facts, the « non » with a number not counted: ' || n.params::text;
    assert not exists (select 1 from notifications where kind = 'event_tomorrow' and recipient_id = '15915915-0000-0000-0000-000000000002'),
        'an employee is not an admin: not told';
    assert (select reminded_at from events where slug = 'ines-thomas-159') is not null, 'the card remembers it';
    assert (select reminded_at from events where slug in ('brouillon-159', 'apres-demain-159') and reminded_at is not null limit 1) is null,
        'the draft and the day after tomorrow: not reminded';
    v_n := events_tomorrow_tick();
    assert v_n = 0, 'told once';
    assert (select count(*) from notifications where kind = 'event_tomorrow') = 1, 'one line, not two';
end $$;

-- 2. the event's own clock; the street cannot call it
do $$
declare
    v_n integer;
begin
    -- An event tomorrow at 00:30 on a clock five hours ahead: tomorrow there.
    insert into events (org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, tz, published)
    select '15915915-1111-0000-0000-000000000001'::uuid, '15915915-0000-0000-0000-000000000001'::uuid, 'gala', 'gala',
           'decale-159', '1111111111111111111111a9', '2222222222222222222222b9', 'Décalé',
           ((((now() + interval '5 hours') at time zone 'UTC')::date + 1) + time '00:30') at time zone 'UTC' - interval '5 hours', null::text, '{}'::jsonb, '+05:00', true;
    assert event_local_date((select starts_at from events where slug = 'decale-159'), '+05:00')
         = event_local_date(now(), '+05:00') + 1, 'the day on the phone''s clock';
    v_n := events_tomorrow_tick();
    assert v_n = 1, 'told on its own clock: ' || v_n;
    assert not has_function_privilege('anon', 'events_tomorrow_tick()', 'execute'), 'the street cannot tick';
    assert not has_function_privilege('authenticated', 'events_tomorrow_tick()', 'execute'), 'nor a member';
    assert not has_function_privilege('public', 'events_tomorrow_tick()', 'execute'), 'nor PUBLIC';
    raise notice 'PASS: 159 — the day before, a published card''s admins are told once how many said yes, on the event''s own clock';
end $$;

rollback;
