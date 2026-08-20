-- ============================================================
-- test_org_suspend.sql — a suspended business is read-only, not gone (049).
-- Phone block 24.
--
-- The claims: a member of a suspended business cannot write but can still read
-- and still sees the suspended flag; a platform admin is exempt and can lift
-- the suspension; only a platform admin may set it; and lifting it restores
-- writes exactly.
-- ============================================================
\set ON_ERROR_STOP on

\set plat  '''24242424-0000-0000-0000-000000000001'''
\set owner '''24242424-0000-0000-0000-000000000002'''
\set org   '''24000000-0000-0000-0000-000000000001'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:plat,  '+22624000001', '{"full_name": "Plateforme"}'),
    (:owner, '+22624000002', '{"full_name": "Patronne"}');
update profiles set is_platform_admin = true where id = :plat;

insert into orgs (id, name, slug, profile, default_currency)
values (:org, 'Boutique A', 'boutique-a-24', 'retail', 'XOF');
select seed_retail_accounts(:org);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
values (:org, :owner, 'owner', 'org', :org, 'full');


\echo ''
\echo '--- TEST 1: only a platform admin may suspend ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '24242424-0000-0000-0000-000000000002';
do $$ begin
    begin
        perform set_org_suspended('24000000-0000-0000-0000-000000000001', true);
        raise exception 'FAIL: a non-admin suspended a business';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the non-admin was refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 2: suspended freezes the member, exempts the platform admin, ---'
\echo '---         keeps reads, and lifts back cleanly ---'
begin;
set local role authenticated;

-- The platform admin freezes it.
set local "request.jwt.claim.sub" = '24242424-0000-0000-0000-000000000001';
select set_org_suspended('24000000-0000-0000-0000-000000000001', true);

-- The member: frozen for writes, still reading, still sees the flag.
set local "request.jwt.claim.sub" = '24242424-0000-0000-0000-000000000002';
do $$
declare v_rows int;
begin
    if can_write_org('24000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: a member can write while suspended';
    end if;
    if not (select suspended from my_orgs()
             where org_id = '24000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: my_orgs does not report the suspension';
    end if;
    -- Reads still work: the business is read-only, not invisible.
    select count(*) into v_rows from orgs
     where id = '24000000-0000-0000-0000-000000000001';
    if v_rows <> 1 then
        raise exception 'FAIL: a member lost read access to a suspended business';
    end if;
    -- A concrete write, through the products insert policy (can_write_org): no.
    begin
        insert into products (org_id, name, sale_price, cost_price)
        values ('24000000-0000-0000-0000-000000000001', 'Interdit', 100, 50);
        raise exception 'FAIL: a member inserted a product while suspended';
    exception when insufficient_privilege or check_violation then
        null; -- RLS refused, as it must
    end;
    raise notice 'PASS: the member is frozen for writes but not for reads';
end $$;

-- The platform admin is exempt while it is suspended.
set local "request.jwt.claim.sub" = '24242424-0000-0000-0000-000000000001';
do $$ begin
    if not can_write_org('24000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the platform admin was frozen out too';
    end if;
    raise notice 'PASS: the platform admin can still act on a suspended business';
end $$;

-- Lift it, and the member writes again.
select set_org_suspended('24000000-0000-0000-0000-000000000001', false);
set local "request.jwt.claim.sub" = '24242424-0000-0000-0000-000000000002';
do $$ begin
    if not can_write_org('24000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: lifting the suspension did not restore writes';
    end if;
    if (select suspended from my_orgs()
         where org_id = '24000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: my_orgs still reports it suspended after lifting';
    end if;
    raise notice 'PASS: lifting the suspension restores writes';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: suspending is idempotent — the timestamp does not reset ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '24242424-0000-0000-0000-000000000001';
do $$
declare v_first timestamptz; v_second timestamptz;
begin
    perform set_org_suspended('24000000-0000-0000-0000-000000000001', true);
    select suspended_at into v_first from orgs
     where id = '24000000-0000-0000-0000-000000000001';
    perform pg_sleep(0.01);
    perform set_org_suspended('24000000-0000-0000-0000-000000000001', true);
    select suspended_at into v_second from orgs
     where id = '24000000-0000-0000-0000-000000000001';
    if v_first is distinct from v_second then
        raise exception 'FAIL: a second suspend reset the timestamp (% -> %)', v_first, v_second;
    end if;
    raise notice 'PASS: suspending twice keeps the original moment';
end $$;
rollback;

\echo ''
\echo '=== test_org_suspend.sql: all checks passed ==='
