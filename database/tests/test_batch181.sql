-- ============================================================
-- test_batch181.sql — 181: an album's counts hold when photos are sent
-- together.
--
-- The claims (a second connection, by dblink, sends at the same time):
--   1. while one photo of a card is being taken, another photo of that card
--      waits for it (here: gives up after half a second) — the count is
--      never read by two at once;
--   2. once the first is done, the second counts it: a phone at its two is
--      refused, as the owner wanted (three chosen at once had passed);
--   3. another card is not held up by it;
--   4. the doors: anon's, one album door.
-- Installed twice, the same. The rows are committed (the other connection
-- must see them) and deleted at the end.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
\i database/migrations/181_album_count_lock.sql
\i database/migrations/181_album_count_lock.sql
create extension if not exists dblink;

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('18118118-0000-0000-0000-000000000001', '+22618110001', 'awa181@example.com', '{"full_name": "Awa"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan, events_allowed) values
    ('18118118-1111-0000-0000-000000000001', 'Awa Fêtes 181', 'awa-fetes-181', 'events', 'XOF', 'pro', true);
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, content, tz, published, album_on, album_open_quota)
values ('18118118-2222-0000-0000-000000000001', '18118118-1111-0000-0000-000000000001', '18118118-0000-0000-0000-000000000001',
        'dot', 'come', 'dot-181', 'aaaaaaaaaaaaaaaaaaaa1811', 'bbbbbbbbbbbbbbbbbbbb1811', 'Dot', now() + interval '9 days', '{}', 'Africa/Ouagadougou', true, true, 2),
       ('18118118-2222-0000-0000-000000000002', '18118118-1111-0000-0000-000000000001', '18118118-0000-0000-0000-000000000001',
        'gala', 'gala', 'gala-181', 'aaaaaaaaaaaaaaaaaaaa1812', 'bbbbbbbbbbbbbbbbbbbb1812', 'Gala', now() + interval '9 days', '{}', 'Africa/Ouagadougou', true, true, 2);

create temp table r181 (n int, out text);
select dblink_connect('other181', format('dbname=%s user=%s port=%s host=%s', current_database(), current_user,
                      current_setting('port'), split_part(current_setting('unix_socket_directories'), ',', 1)));
select dblink_exec('other181', 'set lock_timeout = ''500ms''');

begin;
-- this phone's first photo is being taken (not yet done)
select event_album_add('dot-181', null, 'jpg', 'Nora', null, 'phone-aaaaaaaaaaaaaaaa') is not null as first;
do $$
declare v text;
begin
    -- 1: the same card, from the other connection, at the same time
    begin
        select k into v from dblink('other181', $q$select event_album_add('dot-181', null, 'jpg', 'Nora', null, 'phone-aaaaaaaaaaaaaaaa')$q$) as t(k text);
        insert into r181 values (1, 'TAKEN');
    exception when others then insert into r181 values (1, sqlerrm); end;
    -- 3: another card, not held up
    begin
        select k into v from dblink('other181', $q$select event_album_add('gala-181', null, 'jpg', 'Ali', null, 'phone-bbbbbbbbbbbbbbbb')$q$) as t(k text);
        insert into r181 values (3, v);
    exception when others then insert into r181 values (3, sqlerrm); end;
end $$;
commit;

-- 2: after the first: the second photo passes, the third is refused
do $$
declare v text;
begin
    select k into v from dblink('other181', $q$select event_album_add('dot-181', null, 'jpg', 'Nora', null, 'phone-aaaaaaaaaaaaaaaa')$q$) as t(k text);
    insert into r181 values (20, v);
    begin
        select k into v from dblink('other181', $q$select event_album_add('dot-181', null, 'jpg', 'Nora', null, 'phone-aaaaaaaaaaaaaaaa')$q$) as t(k text);
        insert into r181 values (21, 'TAKEN');
    exception when others then insert into r181 values (21, sqlerrm); end;
end $$;
select dblink_disconnect('other181');

do $$
begin
    assert (select out from r181 where n = 1) like '%lock timeout%', 'the same card waits: ' || (select out from r181 where n = 1);
    raise notice 'PASS: a card''s photos are counted one after the other';
    assert (select out from r181 where n = 20) like 'events/%', 'the second passes';
    assert (select out from r181 where n = 21) like '%2 photo(s)%maximum par personne%', 'the third refused: ' || (select out from r181 where n = 21);
    assert (select count(*) from event_pictures where event_id = '18118118-2222-0000-0000-000000000001' and device = 'phone-aaaaaaaaaaaaaaaa') = 2, 'two kept, not three';
    raise notice 'PASS: each counts those before it — two per phone, the third refused';
    assert (select out from r181 where n = 3) like 'events/%', 'another card not held up: ' || (select out from r181 where n = 3);
    raise notice 'PASS: another card is not held up';
    assert has_function_privilege('anon', 'event_album_add(text, text, text, text, uuid, text)', 'execute')
       and not has_function_privilege('public', 'event_album_add(text, text, text, text, uuid, text)', 'execute'), 'anon''s door';
    assert (select count(*) from pg_proc where proname = 'event_album_add') = 1, 'one album door';
    raise notice 'PASS: the doors';
end $$;

delete from event_pictures where event_id in ('18118118-2222-0000-0000-000000000001', '18118118-2222-0000-0000-000000000002');
delete from events where org_id = '18118118-1111-0000-0000-000000000001';
delete from orgs where id = '18118118-1111-0000-0000-000000000001';
delete from auth.users where id = '18118118-0000-0000-0000-000000000001';
drop table r181;
