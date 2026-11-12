-- ============================================================
-- test_batch180.sql — 180: a shared card's link shows the card.
--
-- The claims:
--   1. no picture yet: the link shows none from here (173's photo stays);
--   2. the card's own picture (177): shown, tall;
--   3. the wide one: minted with the edit token only, shown wide, read by
--      Studio; the next replaces it, the old key answered for its bytes,
--      the card's own picture untouched;
--   4. a draft: only with its preview link; a stranger's slug: nothing;
--   5. the doors: anon's (the page and Studio are signed out).
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
\i database/migrations/180_card_share_picture.sql
\i database/migrations/180_card_share_picture.sql

begin;
insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('18018018-0000-0000-0000-000000000001', '+22618010001', 'awa180@example.com', '{"full_name": "Awa"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan, events_allowed) values
    ('18018018-1111-0000-0000-000000000001', 'Awa Fêtes 180', 'awa-fetes-180', 'events', 'XOF', 'pro', true);
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, tz, published) values
    ('18018018-2222-0000-0000-000000000001', '18018018-1111-0000-0000-000000000001', '18018018-0000-0000-0000-000000000001',
     'dot', 'come', 'dot-180', 'aaaaaaaaaaaaaaaaaaaa1801', 'bbbbbbbbbbbbbbbbbbbb1801', 'Dot', now() + interval '9 days', 'Bazoulé', '{}', 'Africa/Ouagadougou', false);

create temp table k180 (n int, v text) on commit drop;
grant all on k180 to anon;

set local role anon;
do $$ begin
    insert into k180 values (0, coalesce(event_share_image('dot-180', 'aaaaaaaaaaaaaaaaaaaa1801')::text, 'none'));
    -- the card's own picture (177)
    insert into k180 values (1, event_preview_slot('dot-180', 'bbbbbbbbbbbbbbbbbbbb1801', 'jpg'));
    perform event_preview_done((select v from k180 where n = 1), 'bbbbbbbbbbbbbbbbbbbb1801', 9000);
    insert into k180 values (2, event_share_image('dot-180', 'aaaaaaaaaaaaaaaaaaaa1801')::text);
    -- the wide one
    insert into k180 values (3, event_og_slot('dot-180', 'bbbbbbbbbbbbbbbbbbbb1801', 'jpg'));
    insert into k180 values (4, coalesce(event_og_done((select v from k180 where n = 3), 'bbbbbbbbbbbbbbbbbbbb1801', 7000), '-'));
    insert into k180 values (5, event_share_image('dot-180', 'aaaaaaaaaaaaaaaaaaaa1801')::text);
    insert into k180 values (6, event_og_of('dot-180', 'bbbbbbbbbbbbbbbbbbbb1801'));
    insert into k180 values (7, event_og_slot('dot-180', 'bbbbbbbbbbbbbbbbbbbb1801', 'jpg'));
    insert into k180 values (8, event_og_done((select v from k180 where n = 7), 'bbbbbbbbbbbbbbbbbbbb1801', 7100));
    insert into k180 values (9, coalesce(event_share_image('dot-180', null)::text, 'none'));
    insert into k180 values (10, coalesce(event_share_image('nobody-180', null)::text, 'none'));
end $$;
reset role;

do $$
declare
    own text := (select v from k180 where n = 1);
    wide1 text := (select v from k180 where n = 3);
    wide2 text := (select v from k180 where n = 7);
    msg text;
begin
    assert (select v from k180 where n = 0) = 'none', 'no picture yet: none';
    raise notice 'PASS: no picture yet — none from here';
    assert (select v::jsonb from k180 where n = 2) = jsonb_build_object('key', own, 'wide', false), 'the card''s own, tall';
    raise notice 'PASS: the card''s own picture, tall';
    assert (select v from k180 where n = 4) = '-', 'the first wide replaces nothing';
    assert (select v::jsonb from k180 where n = 5) = jsonb_build_object('key', wide1, 'wide', true), 'the wide one first';
    assert (select v from k180 where n = 6) = wide1, 'Studio reads it';
    assert (select v from k180 where n = 8) = wide1, 'the next replaces it, the old key answered';
    assert not exists (select 1 from event_pictures where key = wide1), 'the old row gone';
    assert exists (select 1 from event_pictures where key = own and state = 'stored'), 'the card''s own picture untouched';
    assert (select card_og from events where slug = 'dot-180') = wide2;
    begin perform event_og_slot('dot-180', 'ffffffffffffffffffffffff', 'jpg'); msg := null;
    exception when others then msg := sqlerrm; end;
    assert msg is not null, 'a wrong token mints nothing';
    raise notice 'PASS: the wide picture, minted with the edit token, shown wide, replaced with its key answered';
    assert (select v from k180 where n = 9) = 'none' and (select v from k180 where n = 10) = 'none', 'a draft without its link, or no card: nothing';
    raise notice 'PASS: a draft only with its preview link; no card, nothing';
    assert has_function_privilege('anon', 'event_share_image(text, text)', 'execute')
       and has_function_privilege('anon', 'event_og_slot(text, text, text)', 'execute')
       and has_function_privilege('anon', 'event_og_done(text, text, integer)', 'execute'), 'anon''s doors';
    raise notice 'PASS: the doors';
end $$;

rollback;
