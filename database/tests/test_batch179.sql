-- ============================================================
-- test_batch179.sql — 179: an album open to everyone, so many per phone.
--
-- The claims:
--   1. album_open_quota 2: anyone with the link adds photos — no answer,
--      no ticket — two per phone, the third refused; another phone has
--      its own two;
--   2. no phone identifier (an old page): told to reload, nothing taken;
--   3. without the setting, as before: everyone, no count;
--   4. album_limit is the stricter rule and wins; the rules say
--      'open_quota' only when it applies;
--   5. the setting takes 1 to 20 only; the doors stay anon's.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
\i database/migrations/179_album_open_quota.sql
\i database/migrations/179_album_open_quota.sql

begin;
insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('17917917-0000-0000-0000-000000000001', '+22617910001', 'awa179@example.com', '{"full_name": "Awa"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan, events_allowed) values
    ('17917917-1111-0000-0000-000000000001', 'Awa Fêtes 179', 'awa-fetes-179', 'events', 'XOF', 'pro', true);
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, content, tz, published, album_on, album_open_quota)
values ('17917917-2222-0000-0000-000000000001', '17917917-1111-0000-0000-000000000001', '17917917-0000-0000-0000-000000000001',
        'dot', 'come', 'dot-179', 'aaaaaaaaaaaaaaaaaaaa1791', 'bbbbbbbbbbbbbbbbbbbb1791', 'Dot', now() + interval '9 days', '{}', 'Africa/Ouagadougou', true, true, 2),
       ('17917917-2222-0000-0000-000000000002', '17917917-1111-0000-0000-000000000001', '17917917-0000-0000-0000-000000000001',
        'gala', 'gala', 'gala-179', 'aaaaaaaaaaaaaaaaaaaa1792', 'bbbbbbbbbbbbbbbbbbbb1792', 'Gala', now() + interval '9 days', '{}', 'Africa/Ouagadougou', true, true, null);

create temp table r179 (n int, out text) on commit drop;
grant all on r179 to anon;

-- as a guest's phone, signed out (anon)
set local role anon;
do $$
declare v text;
begin
    insert into r179 values (1, event_album_add('dot-179', null, 'jpg', 'Nora', null, 'phone-aaaaaaaaaaaaaaaa'));
    insert into r179 values (2, event_album_add('dot-179', null, 'jpg', 'Nora', null, 'phone-aaaaaaaaaaaaaaaa'));
    begin v := event_album_add('dot-179', null, 'jpg', 'Nora', null, 'phone-aaaaaaaaaaaaaaaa'); insert into r179 values (3, 'TAKEN');
    exception when others then insert into r179 values (3, sqlerrm); end;
    insert into r179 values (4, event_album_add('dot-179', null, 'jpg', 'Ali', null, 'phone-bbbbbbbbbbbbbbbb'));
    begin v := event_album_add('dot-179', null, 'jpg', 'Sans', null, null); insert into r179 values (5, 'TAKEN');
    exception when others then insert into r179 values (5, sqlerrm); end;
    insert into r179 values (6, event_album_add('gala-179', null, 'jpg', 'Libre', null, null));
    insert into r179 values (7, event_album_add('gala-179', null, 'jpg', 'Libre', null, null));
    insert into r179 values (8, event_album_add('gala-179', null, 'jpg', 'Libre', null, null));
    insert into r179 values (9, (event_album_rules('dot-179', null) ->> 'open_quota'));
    insert into r179 values (10, coalesce(event_album_rules('gala-179', null) ->> 'open_quota', 'none'));
end $$;
reset role;

do $$
declare msg text;
begin
    -- 1
    assert (select out from r179 where n = 1) like 'events/%' and (select out from r179 where n = 2) like 'events/%', 'two photos from a phone, no answer, no ticket';
    assert (select out from r179 where n = 3) like '%2 photo(s)%maximum par personne%', 'the third refused: ' || (select out from r179 where n = 3);
    assert (select out from r179 where n = 4) like 'events/%', 'another phone has its own';
    assert (select count(*) from event_pictures where device = 'phone-aaaaaaaaaaaaaaaa') = 2, 'the phone kept on its pictures';
    raise notice 'PASS: open to everyone, two per phone, the third refused, another phone its own';
    -- 2
    assert (select out from r179 where n = 5) like 'Rechargez la carte%', 'no identifier: reload: ' || (select out from r179 where n = 5);
    raise notice 'PASS: an old page without the phone''s identifier is told to reload';
    -- 3
    assert (select count(*) from r179 where n in (6, 7, 8) and out like 'events/%') = 3, 'without the setting: as before, no count';
    raise notice 'PASS: without the setting, the album as before';
    -- 4
    assert (select out from r179 where n = 9) = '2' and (select out from r179 where n = 10) = 'none', 'the rules say it where it applies';
    update events set album_limit = true where slug = 'dot-179';
    assert event_album_rules('dot-179', null) -> 'open_quota' = 'null'::jsonb, 'album_limit wins: no open quota said';
    begin perform event_album_add('dot-179', null, 'jpg', 'Zoé', null, 'phone-cccccccccccccccc'); msg := null;
    exception when others then msg := sqlerrm; end;
    assert msg like 'L''album est réservé aux invités%', 'album_limit wins: ' || coalesce(msg, 'taken');
    raise notice 'PASS: album_limit is the stricter rule and wins';
    -- 5
    begin update events set album_open_quota = 0 where slug = 'gala-179'; msg := null;
    exception when check_violation then msg := 'refused'; end;
    assert msg = 'refused', '0 refused';
    begin update events set album_open_quota = 21 where slug = 'gala-179'; msg := null;
    exception when check_violation then msg := 'refused'; end;
    assert msg = 'refused', '21 refused';
    assert has_function_privilege('anon', 'event_album_add(text, text, text, text, uuid, text)', 'execute'), 'the guests'' door';
    assert not exists (select 1 from pg_proc where proname = 'event_album_add' and pronargs = 5), 'one album door, not two';
    raise notice 'PASS: 1 to 20 only; one door, the guests''';
end $$;

rollback;
