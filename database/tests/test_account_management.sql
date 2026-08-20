-- ============================================================
-- test_account_management.sql — changing a role, and the two authorisation
-- checks the account Worker forwards here before it resets a password or
-- deletes an account (044). Phone block 21.
--
-- The load-bearing claims: an admin reassigns a role but never the owner's and
-- never *to* owner; manages_user() is true only within a business the caller
-- administers; and can_delete_user() refuses an owner, refuses self, and — for
-- a business admin — refuses anyone who also belongs to a business the caller
-- does not administer, so a deletion cannot reach across tenants.
-- ============================================================
\set ON_ERROR_STOP on

\set ownerA '''21212121-0000-0000-0000-000000000001'''
\set adminA '''21212121-0000-0000-0000-000000000002'''
\set empE   '''21212121-0000-0000-0000-000000000003'''
\set plat   '''21212121-0000-0000-0000-000000000004'''
\set empF   '''21212121-0000-0000-0000-000000000005'''
\set ownerB '''21212121-0000-0000-0000-000000000006'''
\set saA    '''21212121-0000-0000-0000-000000000007'''
\set orgA   '''21000000-0000-0000-0000-000000000001'''
\set orgB   '''21000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:ownerA, '+22621000001', '{"full_name": "PatronneA"}'),
    (:adminA, '+22621000002', '{"full_name": "AdminA"}'),
    (:empE,   '+22621000003', '{"full_name": "EmployeE"}'),
    (:plat,   '+22621000004', '{"full_name": "Plateforme"}'),
    (:empF,   '+22621000005', '{"full_name": "EmployeF"}'),
    (:ownerB, '+22621000006', '{"full_name": "PatronneB"}'),
    (:saA,    '+22621000007', '{"full_name": "SuperA"}');
update profiles set is_platform_admin = true where id = :plat;

insert into orgs (id, name, slug, profile, default_currency) values
    (:orgA, 'Boutique A', 'boutique-a-21', 'retail', 'XOF'),
    (:orgB, 'Boutique B', 'boutique-b-21', 'retail', 'XOF');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:orgA, :ownerA, 'owner',       'org', :orgA, 'full'),
    (:orgA, :saA,    'super_admin', 'org', :orgA, 'full'),
    (:orgA, :adminA, 'admin',       'org', :orgA, 'full'),
    (:orgA, :empE,   'employee',    'org', :orgA, 'full'),
    (:orgA, :empF,   'employee',    'org', :orgA, 'full'),
    (:orgB, :ownerB, 'owner',       'org', :orgB, 'full'),
    (:orgB, :empF,   'employee',    'org', :orgB, 'full');


\echo ''
\echo '--- TEST 1: an admin reassigns an employee, but not the owner and not to owner ---'
begin;
set local "request.jwt.claim.sub" = '21212121-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_emp   uuid;
    v_owner uuid;
    v_role  role_name;
begin
    select id into v_emp   from memberships where user_id = '21212121-0000-0000-0000-000000000003' and org_id = '21000000-0000-0000-0000-000000000001';
    select id into v_owner from memberships where user_id = '21212121-0000-0000-0000-000000000001' and org_id = '21000000-0000-0000-0000-000000000001';

    perform set_membership_role(v_emp, 'manager');
    select role into v_role from memberships where id = v_emp;
    if v_role <> 'manager' then
        raise exception 'FAIL: role is % not manager', v_role;
    end if;

    begin
        perform set_membership_role(v_owner, 'admin');
        raise exception 'FAIL: the owner''s role was changed';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;

    begin
        perform set_membership_role(v_emp, 'owner');
        raise exception 'FAIL: an employee was promoted to owner';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;

    raise notice 'PASS: employee reassigned; owner and owner-promotion refused';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: a non-admin cannot change a role ---'
begin;
set local "request.jwt.claim.sub" = '21212121-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_emp uuid;
begin
    select id into v_emp from memberships where user_id = '21212121-0000-0000-0000-000000000003' and org_id = '21000000-0000-0000-0000-000000000001';
    begin
        perform set_membership_role(v_emp, 'admin');
        raise exception 'FAIL: an employee changed a role';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the employee was refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 3: manages_user is true only within a business the caller admins ---'
begin;
set local "request.jwt.claim.sub" = '21212121-0000-0000-0000-000000000002';
set local role authenticated;
do $$ begin
    if not manages_user('21212121-0000-0000-0000-000000000003') then
        raise exception 'FAIL: admin does not manage an employee of their org';
    end if;
    if manages_user('21212121-0000-0000-0000-000000000006') then
        raise exception 'FAIL: admin manages the owner of a different business';
    end if;
    raise notice 'PASS: admin manages within their org and not beyond';
end $$;
rollback;

begin;
set local "request.jwt.claim.sub" = '21212121-0000-0000-0000-000000000004';
set local role authenticated;
do $$ begin
    if not manages_user('21212121-0000-0000-0000-000000000003') then
        raise exception 'FAIL: platform admin does not manage a member';
    end if;
    raise notice 'PASS: the platform admin manages anyone';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: can_delete_user refuses owners, self, and cross-tenant deletions ---'
begin;
set local "request.jwt.claim.sub" = '21212121-0000-0000-0000-000000000002';
set local role authenticated;
do $$ begin
    -- empE is an employee only of orgA, which adminA administers.
    if not can_delete_user('21212121-0000-0000-0000-000000000003') then
        raise exception 'FAIL: admin cannot delete an employee of only their org';
    end if;
    -- ownerA owns orgA: never deletable here.
    if can_delete_user('21212121-0000-0000-0000-000000000001') then
        raise exception 'FAIL: an owner was deletable';
    end if;
    -- adminA cannot delete themselves.
    if can_delete_user('21212121-0000-0000-0000-000000000002') then
        raise exception 'FAIL: an admin could delete their own account';
    end if;
    -- empF also belongs to orgB, which adminA does not administer.
    if can_delete_user('21212121-0000-0000-0000-000000000005') then
        raise exception 'FAIL: a cross-tenant deletion was allowed';
    end if;
    raise notice 'PASS: owner, self and cross-tenant deletions all refused';
end $$;
rollback;

begin;
set local "request.jwt.claim.sub" = '21212121-0000-0000-0000-000000000004';
set local role authenticated;
do $$ begin
    -- The platform admin may delete a non-owner even across businesses.
    if not can_delete_user('21212121-0000-0000-0000-000000000005') then
        raise exception 'FAIL: platform admin cannot delete a multi-org employee';
    end if;
    -- But still not an owner.
    if can_delete_user('21212121-0000-0000-0000-000000000006') then
        raise exception 'FAIL: platform admin deleted an owner';
    end if;
    raise notice 'PASS: platform admin deletes a non-owner, never an owner';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: password reset follows the ladder, not just membership ---'
-- adminA (admin) may reset those below, never a super_admin, an owner, or a peer.
begin;
set local "request.jwt.claim.sub" = '21212121-0000-0000-0000-000000000002';
set local role authenticated;
do $$ begin
    if not manages_user('21212121-0000-0000-0000-000000000003') then
        raise exception 'FAIL: an admin cannot reset an employee below them';
    end if;
    if manages_user('21212121-0000-0000-0000-000000000007') then
        raise exception 'FAIL: an admin reset a super_admin above them';
    end if;
    if manages_user('21212121-0000-0000-0000-000000000001') then
        raise exception 'FAIL: an admin reset the owner';
    end if;
    raise notice 'PASS: the admin reaches below and no further';
end $$;
rollback;

-- saA (super_admin) may reset the admin and everyone below, never the owner.
begin;
set local "request.jwt.claim.sub" = '21212121-0000-0000-0000-000000000007';
set local role authenticated;
do $$ begin
    if not manages_user('21212121-0000-0000-0000-000000000002') then
        raise exception 'FAIL: a super_admin cannot reset an admin below them';
    end if;
    if manages_user('21212121-0000-0000-0000-000000000001') then
        raise exception 'FAIL: a super_admin reset the owner';
    end if;
    raise notice 'PASS: the super_admin reaches the admin, not the owner';
end $$;
rollback;

-- ownerA sits at the top: the super_admin and everyone under them.
begin;
set local "request.jwt.claim.sub" = '21212121-0000-0000-0000-000000000001';
set local role authenticated;
do $$ begin
    if not manages_user('21212121-0000-0000-0000-000000000007') then
        raise exception 'FAIL: the owner cannot reset a super_admin';
    end if;
    raise notice 'PASS: the owner reaches the super_admin';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: a role change cannot reach a peer or lift past the changer ---'
begin;
set local "request.jwt.claim.sub" = '21212121-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_sa  uuid;
    v_emp uuid;
begin
    select id into v_sa  from memberships where user_id = '21212121-0000-0000-0000-000000000007' and org_id = '21000000-0000-0000-0000-000000000001';
    select id into v_emp from memberships where user_id = '21212121-0000-0000-0000-000000000003' and org_id = '21000000-0000-0000-0000-000000000001';

    -- An admin cannot demote a super_admin above them.
    begin
        perform set_membership_role(v_sa, 'employee');
        raise exception 'FAIL: an admin reassigned a super_admin';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;

    -- Nor promote anyone to the admin's own level.
    begin
        perform set_membership_role(v_emp, 'admin');
        raise exception 'FAIL: an admin promoted a member to admin (their own level)';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;

    raise notice 'PASS: a role change stays strictly below the changer';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: an admin edits a member below them, never one above ---'
begin;
set local "request.jwt.claim.sub" = '21212121-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v_name text;
begin
    -- The employee below: the edit lands and full_name is reassembled.
    perform admin_save_member_profile(
        '21212121-0000-0000-0000-000000000003',
        p_first_name => 'Awa', p_last_name => 'Traoré', p_title => 'Vendeuse');
    select full_name into v_name from profiles
     where id = '21212121-0000-0000-0000-000000000003';
    if v_name <> 'Awa Traoré' then
        raise exception 'FAIL: the employee edit did not land (full_name=%)', v_name;
    end if;

    -- The super_admin above: refused, and their profile is untouched.
    begin
        perform admin_save_member_profile(
            '21212121-0000-0000-0000-000000000007',
            p_first_name => 'Piraté', p_last_name => 'Non');
        raise exception 'FAIL: an admin edited a super_admin above them';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;

    raise notice 'PASS: the admin edits below, and is refused above';
end $$;
rollback;

\echo ''
\echo '=== test_account_management.sql: all checks passed ==='
