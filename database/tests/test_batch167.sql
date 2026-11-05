-- ============================================================
-- test_batch167.sql — 167: an Événementiel allowed one by one.
--
-- The claims, the platform's switch off:
--   1. installed twice, the same;
--   2. a business not allowed: its own admin reads and writes no event
--      (the refusal the owner saw);
--   3. allowed by a platform admin: its admin reads, creates and changes
--      its events — and still nothing of another
--      Événementiel they are admin of that is not allowed;
--   4. only a platform admin sets the flag, only on an Événementiel;
--      my_events_allowed is the caller's own; events_allowed_orgs is the
--      platform's; a new Événementiel still cannot be created (events_open()
--      keeps its meaning); the street calls none of them.
-- Wrapped in one transaction rolled back.
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
\i database/migrations/167_events_allowed.sql
\i database/migrations/167_events_allowed.sql

begin;
update platform_settings set value = 'false' where key = 'events_public';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('16716716-0000-0000-0000-000000000001', '+22616710001', 'esperance167@example.com', '{"full_name": "Espérance"}', now()),
    ('16716716-0000-0000-0000-000000000002', '+22616710002', 'admin167@example.com', '{"full_name": "Admin Marakaj"}', now());
update profiles set is_platform_admin = true where id = '16716716-0000-0000-0000-000000000002';
insert into orgs (id, name, slug, profile, default_currency) values
    ('16716716-1111-0000-0000-000000000001', 'Mariage 167', 'mariage-167', 'events', 'XOF'),
    ('16716716-1111-0000-0000-000000000002', 'Autre fête 167', 'autre-fete-167', 'events', 'XOF'),
    ('16716716-1111-0000-0000-000000000003', 'Boutique 167', 'boutique-167', 'retail', 'XOF');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('16716716-0000-0000-0000-000000000001', '16716716-1111-0000-0000-000000000001', 'admin', 'org', '16716716-1111-0000-0000-000000000001', 'full'),
    ('16716716-0000-0000-0000-000000000001', '16716716-1111-0000-0000-000000000002', 'admin', 'org', '16716716-1111-0000-0000-000000000002', 'full');
insert into events (id, org_id, kind, card, slug, preview_token, edit_token, title, content, tz) values
    ('16716716-2222-0000-0000-000000000001', '16716716-1111-0000-0000-000000000001', 'mariage', 'come', 'mariage-167',
     rpad('a', 24, 'a'), rpad('b', 24, 'b'), 'Phanuel & Espérance', '{}', 'Africa/Ouagadougou'),
    ('16716716-2222-0000-0000-000000000002', '16716716-1111-0000-0000-000000000002', 'anniversaire', 'come', 'autre-167',
     rpad('c', 24, 'c'), rpad('d', 24, 'd'), 'Autre', '{}', 'Africa/Ouagadougou');

-- 2. not allowed: nothing
set local role authenticated;
select set_config('request.jwt.claim.sub', '16716716-0000-0000-0000-000000000001', true);
do $$
declare v_err text;
begin
    assert (select count(*) from events) = 0, 'not allowed: no event read';
    begin
        insert into events (org_id, kind, card, slug, preview_token, edit_token, title, content, tz)
        values ('16716716-1111-0000-0000-000000000001', 'mariage', 'come', 'neuf-167', rpad('e', 24, 'e'), rpad('f', 24, 'f'), 'Neuf', '{}', 'Africa/Ouagadougou');
        raise exception 'not allowed: an event was written';
    exception when insufficient_privilege then null;
    end;
    assert my_events_allowed() = '{}'::uuid[], 'nothing allowed yet';
    begin
        perform set_events_allowed('16716716-1111-0000-0000-000000000001', true);
        raise exception 'a business admin allowed their own business';
    exception when raise_exception then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Réservé%', v_err;
    end;
    begin
        perform events_allowed_orgs();
        raise exception 'a business admin read the platform list';
    exception when raise_exception then null;
    end;
    raise notice 'PASS: 167 — the switch off, a business not allowed reads and writes nothing, and cannot allow itself';
end $$;

-- 4a. a platform admin allows it; only an Événementiel
select set_config('request.jwt.claim.sub', '16716716-0000-0000-0000-000000000002', true);
do $$
declare v_err text;
begin
    perform set_events_allowed('16716716-1111-0000-0000-000000000001', true);
    begin
        perform set_events_allowed('16716716-1111-0000-0000-000000000003', true);
        raise exception 'a shop was allowed';
    exception when raise_exception then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Seul un événementiel%', v_err;
    end;
    assert events_allowed_orgs() = array['16716716-1111-0000-0000-000000000001'::uuid], 'the platform list';
    raise notice 'PASS: 167 — a platform admin allows an Événementiel, never a shop';
end $$;

-- 3. allowed: its own business opens, the other stays shut
select set_config('request.jwt.claim.sub', '16716716-0000-0000-0000-000000000001', true);
do $$
begin
    assert my_events_allowed() = array['16716716-1111-0000-0000-000000000001'::uuid], 'mine';
    assert (select count(*) from events) = 1, 'the allowed business''s event alone';
    assert (select org_id from events) = '16716716-1111-0000-0000-000000000001', 'not the other';
    update events set card = 'sahel' where id = '16716716-2222-0000-0000-000000000001';
    assert (select card from events where id = '16716716-2222-0000-0000-000000000001') = 'sahel', 'the design changed';
    insert into events (org_id, kind, card, slug, preview_token, edit_token, title, content, tz)
    values ('16716716-1111-0000-0000-000000000001', 'anniversaire', 'come', 'neuf-167', rpad('e', 24, 'e'), rpad('f', 24, 'f'), 'Neuf', '{}', 'Africa/Ouagadougou');
    assert (select count(*) from events) = 2, 'a new card made';
    update events set title = 'X' where id = '16716716-2222-0000-0000-000000000002';
    assert not found, 'the other business still shut';
    assert not events_open(), 'events_open() keeps its meaning: no new Événementiel';
    raise notice 'PASS: 167 — allowed, its admin reads, changes and makes its cards; the other stays shut';
end $$;

-- 4b. taken back; the street calls nothing
select set_config('request.jwt.claim.sub', '16716716-0000-0000-0000-000000000002', true);
select set_events_allowed('16716716-1111-0000-0000-000000000001', false);
select set_config('request.jwt.claim.sub', '16716716-0000-0000-0000-000000000001', true);
do $$
declare f text;
begin
    assert (select count(*) from events) = 0, 'taken back: shut again';
    foreach f in array array['events_open(uuid)', 'set_events_allowed(uuid, boolean)', 'my_events_allowed()', 'events_allowed_orgs()'] loop
        assert not has_function_privilege('anon', f, 'execute'), f || ' open to the street';
        assert has_function_privilege('authenticated', f, 'execute'), f || ' closed to a member';
    end loop;
    raise notice 'PASS: 167 — taken back, it shuts again; the street calls none of it';
end $$;
reset role;
rollback;
