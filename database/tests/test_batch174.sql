-- ============================================================
-- test_batch174.sql — 174: the street's events show the card's own picture.
--
-- The claims:
--   1. a Studio card: its cover's photo, even when another block comes
--      first; a hidden block's photo is never shown; a key not stored is
--      passed over;
--   2. a Studio card with only a bank photo: 'poster_stock';
--   3. a classic card: p:hero first, else p:p1, else any p:<slot>;
--   4. a card without any photo: neither (the app draws its design);
--   5. the rest of the row as before (the price, the card's design);
--   6. the helper is nobody's door.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
\i database/migrations/165_events_spots.sql
\i database/migrations/174_street_event_picture.sql
\i database/migrations/174_street_event_picture.sql

begin;
insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('17417417-0000-0000-0000-000000000001', '+22617410001', 'awa174@example.com', '{"full_name": "Awa"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan) values
    ('17417417-1111-0000-0000-000000000001', 'Awa Fêtes 174', 'awa-fetes-174', 'events', 'XOF', 'pro');

-- six cards, all published, listed and to come
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, doc, tz, published, listed)
select ('17417417-2222-0000-0000-00000000000' || n)::uuid, '17417417-1111-0000-0000-000000000001', '17417417-0000-0000-0000-000000000001',
       'anniversaire', c, 'carte-174-' || n, 'aaaaaaaaaaaaaaaaaaaa174' || n, 'bbbbbbbbbbbbbbbbbbbb174' || n, 'Carte ' || n,
       now() + (n || ' days')::interval, 'Ouagadougou', ct::jsonb, d::jsonb, 'Africa/Ouagadougou', true, true
  from (values
    -- 1. Studio: a text block with a photo first, the cover's photo after, a hidden block's photo, an unstored key
    (1, 'come', '{}', '{"v":2,"blocks":[
        {"id":"h1","type":"photo","hidden":true,"props":{"photo":{"key":"events/17417417-2222-0000-0000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg"}}},
        {"id":"t1","type":"text","props":{"photo":{"key":"events/17417417-2222-0000-0000-000000000001/cccccccccccccccccccccccccccccccc.jpg"}}},
        {"id":"g1","type":"gallery","props":{"photos":[{"key":"events/17417417-2222-0000-0000-000000000001/dddddddddddddddddddddddddddddddd.jpg"}]}},
        {"id":"c1","type":"cover","props":{"photo":{"key":"events/17417417-2222-0000-0000-000000000001/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.jpg"}}}]}'),
    -- 2. Studio: a bank photo only
    (2, 'jardin', '{}', '{"v":2,"blocks":[{"id":"c1","type":"cover","props":{"photo":{"stock":"garden-2"}}}]}'),
    -- 3. classic: p:p1 (no hero)
    (3, 'dot', '{"p:p1":{"key":"events/17417417-2222-0000-0000-000000000003/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee.jpg"},"p:g1":{"key":"events/17417417-2222-0000-0000-000000000003/ffffffffffffffffffffffffffffffff.jpg"}}', null),
    -- 4. classic: the hero before the rest
    (4, 'come', '{"p:p1":{"key":"events/17417417-2222-0000-0000-000000000004/11111111111111111111111111111111.jpg"},"p:hero":{"key":"events/17417417-2222-0000-0000-000000000004/22222222222222222222222222222222.jpg"}}', null),
    -- 5. animated, no photo at all
    (5, 'anime_carnet', '{}', null),
    -- 6. classic: only a key that was never stored
    (6, 'gala', '{"p:hero":{"key":"events/17417417-2222-0000-0000-000000000006/33333333333333333333333333333333.jpg"}}', null)
  ) v(n, c, ct, d);

insert into event_pictures (key, event_id, state) values
    ('events/17417417-2222-0000-0000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg', '17417417-2222-0000-0000-000000000001', 'stored'),
    ('events/17417417-2222-0000-0000-000000000001/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.jpg', '17417417-2222-0000-0000-000000000001', 'stored'),
    ('events/17417417-2222-0000-0000-000000000001/dddddddddddddddddddddddddddddddd.jpg', '17417417-2222-0000-0000-000000000001', 'stored'),
    ('events/17417417-2222-0000-0000-000000000003/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee.jpg', '17417417-2222-0000-0000-000000000003', 'stored'),
    ('events/17417417-2222-0000-0000-000000000003/ffffffffffffffffffffffffffffffff.jpg', '17417417-2222-0000-0000-000000000003', 'stored'),
    ('events/17417417-2222-0000-0000-000000000004/11111111111111111111111111111111.jpg', '17417417-2222-0000-0000-000000000004', 'stored'),
    ('events/17417417-2222-0000-0000-000000000004/22222222222222222222222222222222.jpg', '17417417-2222-0000-0000-000000000004', 'stored'),
    ('events/17417417-2222-0000-0000-000000000006/33333333333333333333333333333333.jpg', '17417417-2222-0000-0000-000000000006', 'slot');

do $$
declare
    rows jsonb := (select street_events());
    r jsonb;
    function_row jsonb;
begin
    -- 1. Studio: the cover first; the hidden one and the unstored one passed over
    r := (select x from jsonb_array_elements(rows) x where x ->> 'slug' = 'carte-174-1');
    assert r ->> 'poster' = 'events/17417417-2222-0000-0000-000000000001/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.jpg', 'Studio: the cover''s photo: ' || r::text;
    assert r -> 'poster_stock' = 'null'::jsonb, 'no bank photo when there is a photo';
    raise notice 'PASS: a Studio card shows its cover''s photo, never a hidden block''s, never an unstored key';
    -- the cover without a photo: the next block's stored photo (the gallery), the hidden one still not
    update events set doc = jsonb_set(doc, '{blocks,3,props}', '{}') where slug = 'carte-174-1';
    r := (select x from jsonb_array_elements(street_events()) x where x ->> 'slug' = 'carte-174-1');
    assert r ->> 'poster' = 'events/17417417-2222-0000-0000-000000000001/dddddddddddddddddddddddddddddddd.jpg', 'Studio: the next stored photo: ' || r::text;
    raise notice 'PASS: a cover without a photo: the card''s next stored photo, in the guests'' order';
    -- 2. a bank photo
    r := (select x from jsonb_array_elements(rows) x where x ->> 'slug' = 'carte-174-2');
    assert r -> 'poster' = 'null'::jsonb and r ->> 'poster_stock' = 'garden-2', 'a bank photo: ' || r::text;
    raise notice 'PASS: a Studio card with a bank photo only: poster_stock';
    -- 3, 4. classic
    r := (select x from jsonb_array_elements(rows) x where x ->> 'slug' = 'carte-174-3');
    assert r ->> 'poster' = 'events/17417417-2222-0000-0000-000000000003/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee.jpg', 'classic: p:p1 before p:g1: ' || r::text;
    r := (select x from jsonb_array_elements(rows) x where x ->> 'slug' = 'carte-174-4');
    assert r ->> 'poster' = 'events/17417417-2222-0000-0000-000000000004/22222222222222222222222222222222.jpg', 'classic: the hero first: ' || r::text;
    raise notice 'PASS: a classic card: the hero, else p:p1, else another slot';
    -- 4, 6. nothing
    r := (select x from jsonb_array_elements(rows) x where x ->> 'slug' = 'carte-174-5');
    assert r -> 'poster' = 'null'::jsonb and r -> 'poster_stock' = 'null'::jsonb and r ->> 'card' = 'anime_carnet', 'no photo: the design only: ' || r::text;
    r := (select x from jsonb_array_elements(rows) x where x ->> 'slug' = 'carte-174-6');
    assert r -> 'poster' = 'null'::jsonb, 'a key never stored is no picture: ' || r::text;
    raise notice 'PASS: no photo, or none stored: neither (the app draws the design)';
    -- 5. the row as before
    assert (select count(*) from jsonb_array_elements(rows) x where x ->> 'slug' like 'carte-174-%') = 6, 'all six on the street';
    assert r ? 'date_fr' and r ? 'currency' and r ? 'sponsored' and r ? 'org_name', 'the row''s other fields kept';
    raise notice 'PASS: the street''s row otherwise unchanged';
end $$;

-- 6. the doors
do $$ begin
    assert not has_function_privilege('anon', 'street_event_picture(events)', 'execute'), 'nobody''s door (anon)';
    assert not has_function_privilege('authenticated', 'street_event_picture(events)', 'execute'), 'nobody''s door (signed in)';
    assert has_function_privilege('anon', 'street_events()', 'execute'), 'the street still reaches its list';
    raise notice 'PASS: the doors';
end $$;

rollback;
