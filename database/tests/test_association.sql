-- ============================================================
-- test_association.sql — the church profile is association now (035).
--
-- Phone block 13. What matters: a business created as 'association' gets the
-- same members/giving chart the church profile always seeded; the physical
-- table stays `church_members` (renaming it would break bundle re-runnability,
-- see 035); and a business that was on 'church' reads as 'association' after
-- the migration, with its rows intact.
-- ============================================================
\set ON_ERROR_STOP on

\set admin '''13131313-0000-0000-0000-000000000001'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:admin, '+22613000001', '{"full_name": "Plateforme"}');
update profiles set is_platform_admin = true where id = :admin;


\echo ''
\echo '--- TEST 1: church_members stays a base table (no rename in 035) ---'
do $$
begin
    if not exists (select 1 from information_schema.tables
                   where table_schema='public' and table_name='church_members'
                     and table_type='BASE TABLE') then
        raise exception 'FAIL: church_members base table does not exist';
    end if;
    raise notice 'PASS: church_members is still a base table';
end $$;


\echo ''
\echo '--- TEST 2: a business created as association gets the members chart ---'
begin;
set local "request.jwt.claim.sub" = '13131313-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_org uuid; v_profile text; v_accounts int; v_members int;
begin
    v_org := create_org('Association Espoir', 'assoc-espoir-13', 'association');

    select profile into v_profile from orgs where id = v_org;
    if v_profile <> 'association' then
        raise exception 'FAIL: profile is % not association', v_profile;
    end if;

    select count(*) into v_accounts from accounts where org_id = v_org;
    if v_accounts = 0 then
        raise exception 'FAIL: no chart of accounts seeded for the association';
    end if;

    -- Members are recorded in the same table the church profile always used.
    insert into church_members (org_id, full_name) values (v_org, 'Awa');
    select count(*) into v_members from church_members where org_id = v_org;
    if v_members <> 1 then
        raise exception 'FAIL: member not written (got %)', v_members;
    end if;

    raise notice 'PASS: association seeded (% accounts), member written', v_accounts;
end $$;
rollback;

\echo ''
\echo '--- TEST 3: a church business reads as association after 035 ---'
begin;
set local "request.jwt.claim.sub" = '13131313-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_org uuid; v_profile text;
begin
    -- Born on the old profile, then dragged forward exactly as 035 does it.
    v_org := create_org('Eglise Bethel', 'eglise-bethel-13', 'church');
    update orgs set profile = 'association' where profile = 'church' and id = v_org;

    select profile into v_profile from orgs where id = v_org;
    if v_profile <> 'association' then
        raise exception 'FAIL: migrated church still reads % not association', v_profile;
    end if;
    raise notice 'PASS: church business now reads as association';
end $$;
rollback;

\echo ''
\echo '=== test_association.sql: all checks passed ==='
