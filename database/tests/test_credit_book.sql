-- ============================================================
-- test_credit_book.sql — the carnet de crédit.
--
-- Phone block 89. What matters here, in order of what it would cost to get
-- wrong: the books stay balanced when a sale is a promise; a repayment can
-- reach zero and never cross it; the second delivery of the same outbox row
-- does not double a debt; one business cannot read another's carnet; and
-- "who owes me" is oldest-first, because that is the collection order.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''89898989-0000-0000-0000-000000000001'''
\set clerk    '''89898989-0000-0000-0000-000000000002'''
\set stranger '''89898989-0000-0000-0000-000000000003'''
\set shop     '''89000000-0000-0000-0000-000000000001'''
\set other    '''89000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22689000001', '{"full_name": "Esperance"}'),
    (:clerk,    '+22689000002', '{"full_name": "Vendeuse"}'),
    (:stranger, '+22689000003', '{"full_name": "Voisin"}');

insert into orgs (id, name, slug, profile, default_currency) values
    (:shop,  'Boutique 89', 'boutique-89', 'retail', 'XOF'),
    (:other, 'Boutique 89b', 'boutique-89b', 'retail', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:shop,  :owner,    'owner',    'org', :shop),
    (:shop,  :clerk,    'employee', 'org', :shop),
    (:other, :stranger, 'owner',    'org', :other);

\echo ''
\echo '--- TEST 1: a credit sale posts balanced books and a debt ---'
begin;
set local "request.jwt.claim.sub" = '89898989-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_debt uuid;
    v_debit numeric; v_credit numeric;
    v_owed numeric;
begin
    v_debt := record_credit_sale(
        '89000000-0000-0000-0000-000000000001'::uuid,
        'Awa', 2000, 'Sac de riz',
        p_client_uuid => 'a0000000-0000-0000-0000-000000000001'::uuid);

    select sum(l.debit), sum(l.credit) into v_debit, v_credit
      from journal_lines l
      join journal_entries e on e.id = l.journal_entry_id
     where e.org_id = '89000000-0000-0000-0000-000000000001';
    if v_debit <> v_credit or v_debit <> 2000 then
        raise exception 'FAIL: unbalanced books (% / %)', v_debit, v_credit;
    end if;

    select total_owed into v_owed
      from customer_debts('89000000-0000-0000-0000-000000000001'::uuid)
     where customer_name = 'Awa';
    if v_owed is distinct from 2000 then
        raise exception 'FAIL: Awa owes %, expected 2000', v_owed;
    end if;
    raise notice 'PASS: balanced entry, Awa owes 2000';
end $$;
commit;

\echo ''
\echo '--- TEST 2: the second delivery of the same sale is one debt ---'
begin;
set local "request.jwt.claim.sub" = '89898989-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v1 uuid; v2 uuid; v_count int;
begin
    v1 := record_credit_sale('89000000-0000-0000-0000-000000000001'::uuid,
        'Moussa', 500, 'Huile',
        p_client_uuid => 'a0000000-0000-0000-0000-000000000002'::uuid);
    v2 := record_credit_sale('89000000-0000-0000-0000-000000000001'::uuid,
        'Moussa', 500, 'Huile',
        p_client_uuid => 'a0000000-0000-0000-0000-000000000002'::uuid);
    if v1 <> v2 then
        raise exception 'FAIL: replay created a second debt';
    end if;
    select count(*) into v_count from debts
     where client_uuid = 'a0000000-0000-0000-0000-000000000002';
    if v_count <> 1 then
        raise exception 'FAIL: % debts for one client_uuid', v_count;
    end if;
    raise notice 'PASS: replay returned the same debt';
end $$;
commit;

\echo ''
\echo '--- TEST 3: "awa " with a stray space is the same Awa ---'
begin;
set local "request.jwt.claim.sub" = '89898989-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_customers int;
begin
    perform record_credit_sale('89000000-0000-0000-0000-000000000001'::uuid,
        '  awa ', 1000, 'Savon');
    select count(*) into v_customers from customers
     where org_id = '89000000-0000-0000-0000-000000000001'
       and lower(btrim(name)) = 'awa';
    if v_customers <> 1 then
        raise exception 'FAIL: % customers named awa', v_customers;
    end if;
    raise notice 'PASS: one Awa, now owing 3000';
end $$;
commit;

\echo ''
\echo '--- TEST 4: repayment reduces, reaches zero, never crosses ---'
begin;
set local "request.jwt.claim.sub" = '89898989-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_debt uuid; v_remaining numeric;
begin
    select debt_id into v_debt
      from debts_of_customer('89000000-0000-0000-0000-000000000001'::uuid,
        (select id from customers
          where org_id = '89000000-0000-0000-0000-000000000001'
            and lower(btrim(name)) = 'moussa'))
     limit 1;

    perform record_debt_payment(v_debt, 300,
        p_client_uuid => 'b0000000-0000-0000-0000-000000000001'::uuid);
    select remaining into v_remaining
      from debts_of_customer('89000000-0000-0000-0000-000000000001'::uuid,
        (select customer_id from debts where id = v_debt))
     where debt_id = v_debt;
    if v_remaining is distinct from 200 then
        raise exception 'FAIL: remaining % after 300 of 500', v_remaining;
    end if;

    begin
        perform record_debt_payment(v_debt, 201);
        raise exception 'FAIL: an overpayment was accepted';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: overpayment refused — %', sqlerrm;
    end;

    perform record_debt_payment(v_debt, 200);
    if exists (
        select 1 from customer_debts('89000000-0000-0000-0000-000000000001'::uuid)
         where customer_name = 'Moussa') then
        raise exception 'FAIL: Moussa still listed after paying in full';
    end if;
    raise notice 'PASS: paid to zero and off the list';
end $$;
commit;

\echo ''
\echo '--- TEST 5: a repayment replay is one payment ---'
begin;
set local "request.jwt.claim.sub" = '89898989-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_debt uuid; p1 uuid; p2 uuid;
begin
    v_debt := record_credit_sale('89000000-0000-0000-0000-000000000001'::uuid,
        'Fatou', 800, 'Tissu');
    p1 := record_debt_payment(v_debt, 400,
        p_client_uuid => 'b0000000-0000-0000-0000-000000000002'::uuid);
    p2 := record_debt_payment(v_debt, 400,
        p_client_uuid => 'b0000000-0000-0000-0000-000000000002'::uuid);
    if p1 <> p2 then
        raise exception 'FAIL: replayed payment recorded twice';
    end if;
    raise notice 'PASS: replayed payment is one payment, 400 still due';
end $$;
commit;

\echo ''
\echo '--- TEST 6: the neighbour sees nothing and writes nothing ---'
begin;
set local "request.jwt.claim.sub" = '89898989-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_debt uuid;
begin
    if exists (
        select 1 from customer_debts('89000000-0000-0000-0000-000000000001'::uuid)) then
        raise exception 'FAIL: a stranger read the carnet';
    end if;

    begin
        perform record_credit_sale('89000000-0000-0000-0000-000000000001'::uuid,
            'Intrus', 100, 'X');
        raise exception 'FAIL: a stranger recorded a credit sale';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: stranger''s sale refused — %', sqlerrm;
    end;

    select id into v_debt from debts limit 1;
    if v_debt is not null then
        raise exception 'FAIL: RLS let a stranger select debts rows';
    end if;
    raise notice 'PASS: the carnet is invisible from next door';
end $$;
commit;

\echo ''
\echo '--- TEST 7: oldest debtor first — the collection order ---'
begin;
set local "request.jwt.claim.sub" = '89898989-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_first text;
begin
    perform record_credit_sale('89000000-0000-0000-0000-000000000001'::uuid,
        'Vieux', 100, 'Ancien', p_occurred_at => now() - interval '90 days');
    select customer_name into v_first
      from customer_debts('89000000-0000-0000-0000-000000000001'::uuid)
     limit 1;
    if v_first is distinct from 'Vieux' then
        raise exception 'FAIL: list starts with %, expected the oldest', v_first;
    end if;
    raise notice 'PASS: the 90-day debt tops the list';
end $$;
commit;

\echo ''
\echo '--- TEST 8: an employee can record; the trial balance still holds ---'
begin;
set local "request.jwt.claim.sub" = '89898989-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v_debit numeric; v_credit numeric;
begin
    perform record_credit_sale('89000000-0000-0000-0000-000000000001'::uuid,
        'Awa', 700, 'Sucre');
    select sum(l.debit), sum(l.credit) into v_debit, v_credit
      from journal_lines l
      join journal_entries e on e.id = l.journal_entry_id
     where e.org_id = '89000000-0000-0000-0000-000000000001';
    if v_debit <> v_credit then
        raise exception 'FAIL: books unbalanced (% / %)', v_debit, v_credit;
    end if;
    raise notice 'PASS: employee recorded; debits % = credits %', v_debit, v_credit;
end $$;
commit;

\echo ''
\echo '=== test_credit_book.sql: all assertions passed ==='
