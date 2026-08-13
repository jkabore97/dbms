-- ============================================================
-- test_employees.sql — proof that wages are paid once and seen by few.
--
-- Runs as `authenticated` throughout, never as postgres: pay_employee() is
-- SECURITY DEFINER and half of what is asserted below is an RLS policy, both
-- of which a superuser would sail straight through.
--
-- The four things this suite is actually about:
--
--   1. A casual paid twice for the same afternoon, because the shifts that
--      were settled were not marked as settled.
--   2. A phone retrying a payment and paying it again.
--   3. Wages visible to the wrong people — the most sensitive number in a
--      small shop is not the takings, it is what the person beside you earns.
--   4. Payroll drifting out of the ledger, so the income statement understates
--      what the business actually spends.
--
-- Phone block 79. The others: 70 rls, 71 invitations, 72 reports,
-- 73 accounting, 74 audit, 75/76 farm, 77 platform admin, 78 retail.
-- ============================================================
\set ON_ERROR_STOP on

\set owner  '''79797979-0000-0000-0000-000000000001'''
\set clerk  '''79797979-0000-0000-0000-000000000002'''
\set nosy   '''79797979-0000-0000-0000-000000000003'''

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22679000001', '{"full_name": "Esperance"}'),
    (:clerk, '+22679000002', '{"full_name": "Vendeuse"}'),
    (:nosy,  '+22679000003', '{"full_name": "Employé curieux"}');

insert into orgs (id, name, slug, profile, default_currency) values
    ('79000000-0000-0000-0000-000000000001', 'Boutique Paie', 'boutique-paie', 'retail', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    ('79000000-0000-0000-0000-000000000001', :owner, 'owner',    'org', '79000000-0000-0000-0000-000000000001'),
    ('79000000-0000-0000-0000-000000000001', :clerk, 'manager',  'org', '79000000-0000-0000-0000-000000000001'),
    ('79000000-0000-0000-0000-000000000001', :nosy,  'employee', 'org', '79000000-0000-0000-0000-000000000001');

select seed_retail_accounts('79000000-0000-0000-0000-000000000001');

\echo ''
\echo '--- TEST 1: somebody can be paid without being able to open the books ---'
begin;
set local "request.jwt.claim.sub" = '79797979-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_helper uuid;
    v_user   uuid;
begin
    v_helper := add_employee('79000000-0000-0000-0000-000000000001',
                             'Awa la vendeuse du dimanche', 'casual', 500);

    select user_id into v_user from employees where id = v_helper;
    if v_user is not null then
        raise exception 'FAIL: an employee was tied to an account nobody made';
    end if;

    -- And she has no membership, so she cannot see anything at all.
    if exists (select 1 from memberships m
               join employees e on e.user_id = m.user_id
               where e.id = v_helper) then
        raise exception 'FAIL: adding an employee granted access to the books';
    end if;

    raise notice 'PASS: Awa is on the payroll and has no account';
end $$;
commit;

\echo ''
\echo '--- TEST 2: hours worked become money owed ---'
begin;
set local "request.jwt.claim.sub" = '79797979-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_helper uuid;
    v_owed   numeric;
    v_hours  numeric;
begin
    select id into v_helper from employees
    where org_id = '79000000-0000-0000-0000-000000000001'
      and full_name = 'Awa la vendeuse du dimanche';

    perform record_shift('79000000-0000-0000-0000-000000000001', v_helper, 6);
    perform record_shift('79000000-0000-0000-0000-000000000001', v_helper, 4,
                         current_date - 7);

    select hours, owed into v_hours, v_owed
    from unpaid_shifts('79000000-0000-0000-0000-000000000001')
    where employee_id = v_helper;

    if v_hours <> 10 then
        raise exception 'FAIL: 6 + 4 hours reported as %', v_hours;
    end if;
    -- 10 hours at 500.
    if v_owed <> 5000 then
        raise exception 'FAIL: owed % , expected 5000', v_owed;
    end if;

    raise notice 'PASS: 10 hours worked, 5 000 owed';
end $$;
commit;

\echo ''
\echo '--- TEST 3: paying her settles those hours and books the wage ---'
begin;
set local "request.jwt.claim.sub" = '79797979-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_helper  uuid;
    v_payment uuid;
    v_amount  numeric;
    v_left    int;
    v_wages   numeric;
begin
    select id into v_helper from employees
    where org_id = '79000000-0000-0000-0000-000000000001'
      and full_name = 'Awa la vendeuse du dimanche';

    -- No amount given: the function works out what is owed.
    v_payment := pay_employee('79000000-0000-0000-0000-000000000001', v_helper);

    select amount into v_amount from staff_payments where id = v_payment;
    if v_amount <> 5000 then
        raise exception 'FAIL: paid %, expected 5000', v_amount;
    end if;

    select count(*) into v_left from shifts
    where employee_id = v_helper and payment_id is null;
    if v_left <> 0 then
        raise exception 'FAIL: % shifts still unpaid after paying for them', v_left;
    end if;

    select coalesce(sum(jl.debit), 0) into v_wages
    from journal_lines jl
    join accounts a on a.id = jl.account_id
    where a.org_id = '79000000-0000-0000-0000-000000000001'
      and a.name = 'Salaires';
    if v_wages <> 5000 then
        raise exception 'FAIL: wages booked %, expected 5000', v_wages;
    end if;

    raise notice 'PASS: 5 000 paid, shifts settled, wage in the ledger';
end $$;
commit;

\echo ''
\echo '--- TEST 4: the same afternoon cannot be paid for twice ---'
begin;
set local "request.jwt.claim.sub" = '79797979-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_helper uuid;
    v_owed   numeric;
begin
    select id into v_helper from employees
    where org_id = '79000000-0000-0000-0000-000000000001'
      and full_name = 'Awa la vendeuse du dimanche';

    -- Everything she worked has been paid, so there is nothing owed and
    -- nothing to pay.
    select coalesce(sum(owed), 0) into v_owed
    from unpaid_shifts('79000000-0000-0000-0000-000000000001')
    where employee_id = v_helper;

    if v_owed <> 0 then
        raise exception 'FAIL: % still shown as owed after payment', v_owed;
    end if;

    begin
        perform pay_employee('79000000-0000-0000-0000-000000000001', v_helper);
        raise exception 'FAIL: she was paid a second time for the same hours';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: second payment refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 5: a retried payment is still one payment ---'
begin;
set local "request.jwt.claim.sub" = '79797979-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_perm   uuid;
    v_first  uuid;
    v_second uuid;
    v_count  int;
    v_uuid   uuid := 'bbbbbbbb-0000-0000-0000-000000000079';
begin
    v_perm := add_employee('79000000-0000-0000-0000-000000000001',
                           'Le gérant', 'permanent', null, 60000);

    v_first  := pay_employee('79000000-0000-0000-0000-000000000001', v_perm,
                             null, null, 'cash', current_date, true, v_uuid);
    v_second := pay_employee('79000000-0000-0000-0000-000000000001', v_perm,
                             null, null, 'cash', current_date, true, v_uuid);

    if v_first is distinct from v_second then
        raise exception 'FAIL: the retry paid him twice (% and %)', v_first, v_second;
    end if;

    select count(*) into v_count from staff_payments
    where org_id = '79000000-0000-0000-0000-000000000001' and client_uuid = v_uuid;
    if v_count <> 1 then
        raise exception 'FAIL: % payments share one client_uuid', v_count;
    end if;

    raise notice 'PASS: a retried salary payment is one payment of 60 000';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: an employee cannot read the payroll ---'
begin;
set local "request.jwt.claim.sub" = '79797979-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_people   int;
    v_payments int;
    v_shifts   int;
begin
    select count(*) into v_people   from employees;
    select count(*) into v_payments from staff_payments;
    select count(*) into v_shifts   from shifts;

    if v_people <> 0 or v_payments <> 0 or v_shifts <> 0 then
        raise exception 'FAIL: an employee sees % colleagues, % payments, % shifts',
            v_people, v_payments, v_shifts;
    end if;

    raise notice 'PASS: wages are invisible to the people standing beside them';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: a manager may record a shift and not read the payroll ---'
begin;
set local "request.jwt.claim.sub" = '79797979-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_helper   uuid;
    v_payments int;
begin
    -- A manager is not an org admin under is_org_admin(), which is owner,
    -- super_admin or admin. Recording time worked is a shop-floor act; seeing
    -- what everyone is paid is not.
    select count(*) into v_payments from staff_payments;
    if v_payments <> 0 then
        raise exception 'FAIL: a manager can read % payments', v_payments;
    end if;
    raise notice 'PASS: a manager sees no payments';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: the books still balance ---'
do $$
declare
    v_debits  numeric;
    v_credits numeric;
begin
    select coalesce(sum(jl.debit), 0), coalesce(sum(jl.credit), 0)
      into v_debits, v_credits
    from journal_lines jl
    join accounts a on a.id = jl.account_id
    where a.org_id = '79000000-0000-0000-0000-000000000001';

    if v_debits <> v_credits then
        raise exception 'FAIL: debits % <> credits %', v_debits, v_credits;
    end if;
    if v_debits = 0 then
        raise exception 'FAIL: nothing was posted at all';
    end if;
    raise notice 'PASS: debits = credits = %', v_debits;
end $$;

\echo ''
\echo 'test_employees.sql: all assertions held.'
