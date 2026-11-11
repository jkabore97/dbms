-- ============================================================
-- test_batch177.sql — 177: the street shows the card itself.
--
-- The claims:
--   1. a preview: minted with the card's edit token only, confirmed as the
--      card's picture; Studio reads that it has one;
--   2. the next one replaces it: the old key answered (for its bytes), its
--      row gone; a confirmation with another card's token refused;
--   3. the street: the card's own picture before its photo; the
--      organiser's choice still first; a preview never among « Mes
--      photos » (source 'preview') nor counted in the organiser's eighty;
--   4. the doors: anon may mint and confirm (the token is the key);
--      street_event_picture nobody's.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
\i database/migrations/177_card_preview.sql
\i database/migrations/177_card_preview.sql

begin;
insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('17717717-0000-0000-0000-000000000001', '+22617710001', 'awa177@example.com', '{"full_name": "Awa"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan, events_allowed) values
    ('17717717-1111-0000-0000-000000000001', 'Awa Fêtes 177', 'awa-fetes-177', 'events', 'XOF', 'pro', true);
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, doc, tz, published, listed) values
    ('17717717-2222-0000-0000-000000000001', '17717717-1111-0000-0000-000000000001', '17717717-0000-0000-0000-000000000001',
     'mariage', 'come', 'carte-177-1', 'aaaaaaaaaaaaaaaaaaaa1771', 'bbbbbbbbbbbbbbbbbbbb1771', 'Carte 1',
     now() + interval '3 days', 'Ouagadougou', '{}',
     '{"v":2,"blocks":[{"id":"c1","type":"cover","props":{"photo":{"key":"events/17717717-2222-0000-0000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg"}}}]}',
     'Africa/Ouagadougou', true, true),
    ('17717717-2222-0000-0000-000000000002', '17717717-1111-0000-0000-000000000001', '17717717-0000-0000-0000-000000000001',
     'gala', 'gala', 'carte-177-2', 'aaaaaaaaaaaaaaaaaaaa1772', 'cccccccccccccccccccc1772', 'Carte 2',
     now() + interval '4 days', 'Ouagadougou', '{}', null, 'Africa/Ouagadougou', true, true);
insert into event_pictures (key, event_id, state) values
    ('events/17717717-2222-0000-0000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg', '17717717-2222-0000-0000-000000000001', 'stored');

create temp table k (n int, key text, old text) on commit drop;
grant all on k to anon;

-- as the signed-out Studio (anon), the edit token the key
set local role anon;
insert into k select 1, event_preview_slot('carte-177-1', 'bbbbbbbbbbbbbbbbbbbb1771', 'jpg'), null;
update k set old = coalesce(event_preview_done(key, 'bbbbbbbbbbbbbbbbbbbb1771', 4000), '-') where n = 1;
insert into k select 2, event_preview_slot('carte-177-1', 'bbbbbbbbbbbbbbbbbbbb1771', 'jpg'), null;
reset role;

do $$
declare
    first text := (select key from k where n = 1);
    second text := (select key from k where n = 2);
    r jsonb;
    msg text;
begin
    -- 1
    assert (select old from k where n = 1) = '-', 'the first preview replaces nothing';
    assert (select card_preview from events where slug = 'carte-177-1') = first, 'the card''s picture is the first';
    assert event_preview_of('carte-177-1', 'bbbbbbbbbbbbbbbbbbbb1771') = first, 'Studio reads it';
    begin perform event_preview_slot('carte-177-1', 'ffffffffffffffffffffffff', 'jpg'); msg := null;
    exception when others then msg := sqlerrm; end;
    assert msg is not null, 'a wrong token mints nothing';
    raise notice 'PASS: a preview minted with the card''s edit token only, confirmed as the card''s picture, read by Studio';

    -- 2
    begin perform event_preview_done(second, 'cccccccccccccccccccc1772', 1); msg := null;
    exception when others then msg := sqlerrm; end;
    assert msg is not null, 'another card''s token confirms nothing';
    assert event_preview_done(second, 'bbbbbbbbbbbbbbbbbbbb1771', 5000) = first, 'the old key answered, for its bytes';
    assert (select card_preview from events where slug = 'carte-177-1') = second, 'the second replaces it';
    assert not exists (select 1 from event_pictures where key = first), 'the old row gone';
    raise notice 'PASS: the next preview replaces the last, whose key is answered for its bytes';

    -- 3
    r := (select x from jsonb_array_elements(street_events()) x where x ->> 'slug' = 'carte-177-1');
    assert r ->> 'poster' = second, 'the street shows the card itself before its photo: ' || r::text;
    update events set street_picture = 'fete:mariage' where slug = 'carte-177-1';
    r := (select x from jsonb_array_elements(street_events()) x where x ->> 'slug' = 'carte-177-1');
    assert r ->> 'poster_fete' = 'mariage', 'the organiser''s choice still first';
    update events set street_picture = 'events/17717717-2222-0000-0000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg' where slug = 'carte-177-1';
    r := (select x from jsonb_array_elements(street_events()) x where x ->> 'slug' = 'carte-177-1');
    assert r ->> 'poster' like '%aaaaaaaa.jpg', 'its own photo chosen: that one';
    r := (select x from jsonb_array_elements(street_events()) x where x ->> 'slug' = 'carte-177-2');
    assert r -> 'poster' = 'null'::jsonb, 'a card without a picture: as 174';
    assert (select count(*) from event_pictures where event_id = '17717717-2222-0000-0000-000000000001' and source = 'organiser') = 1,
        'the preview not among the organiser''s photos';
    raise notice 'PASS: the street shows the card itself; the organiser''s choice first; never among « Mes photos »';

    -- 4
    assert has_function_privilege('anon', 'event_preview_slot(text, text, text)', 'execute'), 'Studio, signed out, mints';
    assert has_function_privilege('anon', 'event_preview_done(text, text, integer)', 'execute'), 'and confirms';
    assert not has_function_privilege('anon', 'street_event_picture(events)', 'execute'), 'the helper nobody''s door';
    raise notice 'PASS: the doors';
end $$;

rollback;
