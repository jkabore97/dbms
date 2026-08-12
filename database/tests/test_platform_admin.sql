-- ============================================================
-- test_platform_admin.sql — proof that is_platform_admin opens every door,
-- and that nothing else opens even one.
--
-- Same discipline as test_rls.sql and test_invitations.sql: every assertion
-- runs as the `authenticated` role with request.jwt.claim.sub set, never as
-- the superuser that owns the tables. A superuser bypasses RLS, and
-- create_org is SECURITY DEFINER — a suite run as postgres would report a
-- clean pass against a check that does nothing.
--
-- create_org is the one function in the project whose authorization is not
-- RLS. Nothing can gate an INSERT into orgs on membership in an org that does
-- not exist yet, so the is_platform_admin test inside the function body IS the
-- lock. TEST 1 is therefore the most important assertion in this file.
--
-- Two blocks COMMIT rather than roll back: an org created in one transaction
-- is what the later tests read. Impersonation is still `set local` and still
-- ends with its transaction.
--
-- Failures raise. A green run means every assertion below held.
-- ============================================================
\set ON_ERROR_STOP on

-- Deliberately outside the cccccccc-… range: test_invitations.sql commits
-- users on those ids into the same database earlier in the CI run.
\set jairus '''12121212-0000-0000-0000-000000000001'''
\set israel '''12121212-0000-0000-0000-000000000002'''

-- ------------------------------------------------------------
-- The role the app actually connects as.
-- ------------------------------------------------------------
do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- ------------------------------------------------------------
-- Two people: the one who runs the platform, and an ordinary signed-in user
-- who belongs to nothing at all.
-- ------------------------------------------------------------
insert into auth.users (id, phone, raw_user_meta_data) values
    (:jairus, '+22672000001', '{"full_name": "Jairus"}'),
    (:israel, '+22672000002', '{"full_name": "Israel"}');

-- The on_auth_user_created trigger already wrote both profile rows; only the
-- flag needs setting, and only on one of them.
update profiles set is_platform_admin = true  where id = :jairus;
update profiles set is_platform_admin = false where id = :israel;

\echo ''
\echo '--- TEST 1: a signed-in user who is not a platform admin cannot create an org ---'
begin;
set local "request.jwt.claim.sub" = '12121212-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v_org uuid;
begin
    select create_org('Rogue Farm', 'rogue-farm') into v_org;
    raise exception 'FAIL: Israel created org % without the platform-admin flag', v_org;
exception
    when raise_exception then
        if sqlerrm like 'FAIL:%' then
            raise;
        end if;
        raise notice 'PASS: create_org refused — %', sqlerrm;
end $$;
rollback;

\echo ''
\echo '--- TEST 2: the platform admin can create one ---'
-- Committed, not rolled back: the tests below read the org this creates.
-- The new ids are found by slug rather than carried in a psql variable —
-- \gset does not interpolate inside a dollar-quoted body.
begin;
set local "request.jwt.claim.sub" = '12121212-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_org uuid;
begin
    select create_org('Ignace Poultry', 'ignace-poultry', 'farm') into v_org;
    if v_org is null then
        raise exception 'FAIL: create_org returned no org id';
    end if;
    raise notice 'PASS: platform admin created org %', v_org;
end $$;
commit;

\echo ''
\echo '--- TEST 3: he sees every business, and is recorded as owner of the new one ---'
begin;
set local "request.jwt.claim.sub" = '12121212-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_listed  int;
    v_visible int;
    v_roles   text[];
    v_vis     text;
    v_role    role_name;
    v_new     uuid;
begin
    select id into v_new from orgs where slug = 'ignace-poultry';
    if v_new is null then
        raise exception 'FAIL: the org created in TEST 2 did not persist';
    end if;

    -- my_orgs() and the orgs policy must agree: the flag is one OR clause in
    -- both, and a mismatch means the picker shows a business the tables deny.
    select count(*) into v_listed  from my_orgs();
    select count(*) into v_visible from orgs;
    if v_listed <> v_visible then
        raise exception 'FAIL: my_orgs() lists % orgs but % rows are readable', v_listed, v_visible;
    end if;
    if v_listed < 2 then
        raise exception 'FAIL: platform admin sees only % org(s) — the bypass is not firing', v_listed;
    end if;

    select roles, visibility into v_roles, v_vis
    from my_orgs() where org_id = v_new;
    if v_roles is null then
        raise exception 'FAIL: the org he just created is missing from his own list';
    end if;
    if v_roles <> array['platform_admin'::text] or v_vis <> 'full' then
        raise exception 'FAIL: platform admin listed as % / %', v_roles, v_vis;
    end if;

    -- my_orgs() reports the bypass, not the grant, so ownership is proven
    -- against memberships: the creator must be a visible owner rather than a
    -- ghost with access nobody can trace.
    select role into v_role from memberships
    where org_id = v_new and user_id = '12121212-0000-0000-0000-000000000001';
    if v_role is distinct from 'owner' then
        raise exception 'FAIL: creator holds % on the new org, expected owner', v_role;
    end if;

    raise notice 'PASS: % orgs listed, all readable, and he owns the new one', v_listed;
end $$;
rollback;

\echo ''
\echo '--- TEST 4: a non-church profile gets the generic starter chart of accounts ---'
begin;
set local "request.jwt.claim.sub" = '12121212-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_count int;
    v_codes text[];
begin
    select count(*), array_agg(code order by code) into v_count, v_codes
    from accounts where org_id = (select id from orgs where slug = 'ignace-poultry');
    if v_count <> 6 then
        raise exception 'FAIL: farm org seeded with % accounts, expected the 6 generic ones', v_count;
    end if;
    if v_codes <> array['1000','1010','1020','4000','5000','5010'] then
        raise exception 'FAIL: unexpected generic chart of accounts: %', v_codes;
    end if;
    raise notice 'PASS: new org is not empty — 6 generic accounts, no church seed';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: an ordinary user with no memberships still sees nothing ---'
begin;
set local "request.jwt.claim.sub" = '12121212-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_orgs int;
    v_list int;
begin
    select count(*) into v_orgs from orgs;
    if v_orgs <> 0 then
        raise exception 'FAIL: Israel can see % org rows', v_orgs;
    end if;
    select count(*) into v_list from my_orgs();
    if v_list <> 0 then
        raise exception 'FAIL: my_orgs() offered Israel % businesses', v_list;
    end if;
    raise notice 'PASS: the flag widened nobody else — Israel still sees nothing';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: a church-profile org gets the real church seed, not the generic one ---'
begin;
set local "request.jwt.claim.sub" = '12121212-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_org    uuid;
    v_count  int;
    v_tithes int;
begin
    select create_org('Grace Chapel 2', 'grace-chapel-2', 'church') into v_org;

    select count(*) into v_count from accounts where org_id = v_org;
    if v_count <> 14 then
        raise exception 'FAIL: church org seeded with % accounts, expected 14', v_count;
    end if;
    select count(*) into v_tithes from accounts
    where org_id = v_org and code = '4000' and name = 'Tithes';
    if v_tithes <> 1 then
        raise exception 'FAIL: church org got the generic 4000, not Tithes';
    end if;
    raise notice 'PASS: church profile routed to seed_church_accounts';
end $$;
commit;

\echo ''
\echo '--- TEST 7: revoking the flag closes every door again ---'
-- The flag is read live by each helper, so clearing it must take effect with
-- no re-grant and no session change.
update profiles set is_platform_admin = false where id = :jairus;

begin;
set local "request.jwt.claim.sub" = '12121212-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_count int;
begin
    -- He keeps the two orgs he owns by membership, and loses the rest.
    select count(*) into v_count from my_orgs();
    if v_count <> 2 then
        raise exception 'FAIL: after revocation he lists % orgs, expected his own 2', v_count;
    end if;

    begin
        perform create_org('Should Not Exist', 'should-not-exist');
        raise exception 'FAIL: create_org still works after the flag was cleared';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then
                raise;
            end if;
    end;

    raise notice 'PASS: revoking the flag revokes the bypass and the create right';
end $$;
rollback;

-- Leave the fixture as the rest of the suite expects to find it.
update profiles set is_platform_admin = true where id = :jairus;
