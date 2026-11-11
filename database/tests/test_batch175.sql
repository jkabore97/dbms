-- ============================================================
-- test_batch175.sql — 175: the organiser chooses the event's picture.
--
-- The claims:
--   1. no choice: 174's automatic picture, 'poster_fete' null;
--   2. a gallery picture: 'poster_fete', the card's own photo set aside;
--   3. one of the card's stored pictures: that one, before the cover;
--   4. another event's picture, or one not stored: the automatic choice;
--   5. the column takes nothing else (a URL, a path);
--   6. an admin of the business writes it, another business's cannot;
--      the helper stays nobody's door.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
grant select on all tables in schema public to authenticated;
\i database/migrations/165_events_spots.sql
\i database/migrations/174_street_event_picture.sql
\i database/migrations/175_street_picture_choice.sql
\i database/migrations/175_street_picture_choice.sql

begin;
insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('17517517-0000-0000-0000-000000000001', '+22617510001', 'awa175@example.com', '{"full_name": "Awa"}', now()),
    ('17517517-0000-0000-0000-000000000002', '+22617510002', 'moussa175@example.com', '{"full_name": "Moussa"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan, events_allowed) values
    ('17517517-1111-0000-0000-000000000001', 'Awa Fêtes 175', 'awa-fetes-175', 'events', 'XOF', 'pro', true),
    ('17517517-1111-0000-0000-000000000002', 'Moussa Fêtes 175', 'moussa-fetes-175', 'events', 'XOF', 'pro', true);
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('17517517-0000-0000-0000-000000000001', '17517517-1111-0000-0000-000000000001', 'owner', 'org', '17517517-1111-0000-0000-000000000001', 'full'),
    ('17517517-0000-0000-0000-000000000002', '17517517-1111-0000-0000-000000000002', 'owner', 'org', '17517517-1111-0000-0000-000000000002', 'full');

insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, doc, tz, published, listed) values
    ('17517517-2222-0000-0000-000000000001', '17517517-1111-0000-0000-000000000001', '17517517-0000-0000-0000-000000000001',
     'mariage', 'come', 'carte-175-1', 'aaaaaaaaaaaaaaaaaaaa1751', 'bbbbbbbbbbbbbbbbbbbb1751', 'Carte 1',
     now() + interval '3 days', 'Ouagadougou', '{}',
     '{"v":2,"blocks":[{"id":"c1","type":"cover","props":{"photo":{"key":"events/17517517-2222-0000-0000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg"}}}]}',
     'Africa/Ouagadougou', true, true),
    ('17517517-2222-0000-0000-000000000002', '17517517-1111-0000-0000-000000000002', '17517517-0000-0000-0000-000000000002',
     'gala', 'gala', 'carte-175-2', 'aaaaaaaaaaaaaaaaaaaa1752', 'bbbbbbbbbbbbbbbbbbbb1752', 'Carte 2',
     now() + interval '4 days', 'Bobo-Dioulasso', '{}', null, 'Africa/Ouagadougou', true, true);

insert into event_pictures (key, event_id, state) values
    ('events/17517517-2222-0000-0000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg', '17517517-2222-0000-0000-000000000001', 'stored'),
    ('events/17517517-2222-0000-0000-000000000001/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.jpg', '17517517-2222-0000-0000-000000000001', 'stored'),
    ('events/17517517-2222-0000-0000-000000000001/cccccccccccccccccccccccccccccccc.jpg', '17517517-2222-0000-0000-000000000001', 'slot'),
    ('events/17517517-2222-0000-0000-000000000002/dddddddddddddddddddddddddddddddd.jpg', '17517517-2222-0000-0000-000000000002', 'stored');


do $$
declare
    r jsonb;
begin
    -- 1. no choice: as 174
    r := (select x from jsonb_array_elements(street_events()) x where x ->> 'slug' = 'carte-175-1');
    assert r ->> 'poster' = 'events/17517517-2222-0000-0000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg'
       and r ? 'poster_fete' and r -> 'poster_fete' = 'null'::jsonb, 'no choice: the cover: ' || r::text;
    raise notice 'PASS: no choice — the automatic picture, as 174';

    -- 2. a gallery picture
    update events set street_picture = 'fete:mariage-2' where slug = 'carte-175-1';
    r := (select x from jsonb_array_elements(street_events()) x where x ->> 'slug' = 'carte-175-1');
    assert r ->> 'poster_fete' = 'mariage-2' and r -> 'poster' = 'null'::jsonb and r -> 'poster_stock' = 'null'::jsonb,
        'a gallery picture: ' || r::text;
    raise notice 'PASS: a gallery picture chosen — poster_fete, the card''s photo set aside';

    -- 3. one of the card's stored pictures, not its cover
    update events set street_picture = 'events/17517517-2222-0000-0000-000000000001/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.jpg' where slug = 'carte-175-1';
    r := (select x from jsonb_array_elements(street_events()) x where x ->> 'slug' = 'carte-175-1');
    assert r ->> 'poster' = 'events/17517517-2222-0000-0000-000000000001/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.jpg', 'its own picture: ' || r::text;
    raise notice 'PASS: one of the card''s own pictures chosen — that one, before the cover';

    -- 4. not stored, or another event's: the automatic choice
    update events set street_picture = 'events/17517517-2222-0000-0000-000000000001/cccccccccccccccccccccccccccccccc.jpg' where slug = 'carte-175-1';
    r := (select x from jsonb_array_elements(street_events()) x where x ->> 'slug' = 'carte-175-1');
    assert r ->> 'poster' like '%aaaaaaaa.jpg', 'an unstored choice: the cover: ' || r::text;
    update events set street_picture = 'events/17517517-2222-0000-0000-000000000002/dddddddddddddddddddddddddddddddd.jpg' where slug = 'carte-175-1';
    r := (select x from jsonb_array_elements(street_events()) x where x ->> 'slug' = 'carte-175-1');
    assert r ->> 'poster' like '%aaaaaaaa.jpg', 'another event''s picture: never: ' || r::text;
    raise notice 'PASS: a picture not stored, or another event''s — the automatic choice';

    -- 5. nothing else
    begin
        update events set street_picture = 'https://example.com/x.jpg' where slug = 'carte-175-1';
        raise exception 'a URL taken';
    exception when check_violation then null;
    end;
    begin
        update events set street_picture = 'fete:../../x' where slug = 'carte-175-1';
        raise exception 'a path taken';
    exception when check_violation then null;
    end;
    raise notice 'PASS: the column takes a gallery name or a picture key, nothing else';
end $$;

-- 6. who writes it
update events set street_picture = null where slug = 'carte-175-1';
set local role authenticated;
select set_config('request.jwt.claim.sub', '17517517-0000-0000-0000-000000000001', true);
update events set street_picture = 'fete:gala' where slug = 'carte-175-1';
update events set street_picture = 'fete:gala' where slug = 'carte-175-2';
reset role;
select set_config('request.jwt.claim.sub', '', true);
do $$ begin
    assert (select street_picture from events where slug = 'carte-175-1') = 'fete:gala', 'the business''s admin chooses';
    assert (select street_picture from events where slug = 'carte-175-2') is null, 'another business''s card untouched';
    assert not has_function_privilege('anon', 'street_event_picture(events)', 'execute'), 'nobody''s door (anon)';
    assert not has_function_privilege('authenticated', 'street_event_picture(events)', 'execute'), 'nobody''s door (signed in)';
    raise notice 'PASS: the business''s admins choose, nobody else; the helper nobody''s door';
end $$;

rollback;
