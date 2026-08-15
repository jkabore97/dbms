-- ============================================================
-- test_sale_on_credit.sql — crédit as a payment method.
--
-- Phone block 93. The claim under test: a credit sale is a real sale —
-- the sack leaves the shelf, the cost is snapshotted, the day's books
-- balance — with the money landing in créances and a debt in the carnet
-- that the repayment flow from 024 settles. And the old paths keep their
-- shape: cash sales unchanged, returns on credit refused, strangers out.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''93939393-0000-0000-0000-000000000001'''
\set clerk    '''93939393-0000-0000-0000-000000000002'''
\set stranger '''93939393-0000-0000-0000-000000000003'''
\set shop     '''93000000-0000-0000-0000-000000000001'''
\set other    '''93000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22693000001', '{"full_name": "Patronne"}'),
    (:clerk,    '+22693000002', '{"full_name": "Vendeuse"}'),
    (:stranger, '+22693000003', '{"full_name": "Voisin"}');

insert into orgs (id, name, slug, profile, default_currency) values
    (:shop,  'Boutique 93', 'boutique-93', 'retail', 'XOF'),
    (:other, 'Boutique 93b', 'boutique-93b', 'retail', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:shop,  :owner,    'owner',    'org', :shop),
    (:shop,  :clerk,    'employee', 'org', :shop),
    (:other, :stranger, 'owner',    'org', :other);

\echo ''
\echo '--- TEST 1: a credit sale moves the goods and books the créance ---'
begin;
set local "request.jwt.claim.sub" = '93939393-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_rice uuid; v_sale uuid;
    v_qty numeric; v_cost numeric;
    v_owed numeric; v_label text; v_debt_sale uuid;
    v_debit numeric; v_credit numeric;
    v_cash_touched int;
begin
    v_rice := ensure_product('93000000-0000-0000-0000-000000000001'::uuid,
        'Riz', p_sale_price => 600, p_cost_price => 450);
    perform receive_products('93000000-0000-0000-0000-000000000001'::uuid,
        v_rice, 10, 450);

    v_sale := record_sale('93000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_array(jsonb_build_object(
            'product_id', v_rice, 'name', 'Riz',
            'quantity', 2, 'unit_price', 600)),
        p_method        => 'credit',
        p_customer_name => 'Awa',
        p_client_uuid   => 'd3000000-0000-0000-0000-000000000001'::uuid);

    -- The sack left the shelf, exactly like a cash sale.
    select quantity into v_qty from products where id = v_rice;
    if v_qty <> 8 then
        raise exception 'FAIL: rice at % after selling 2 of 10 on credit', v_qty;
    end if;

    -- The margin base was snapshotted.
    select unit_cost into v_cost from sale_lines where sale_id = v_sale limit 1;
    if v_cost <> 450 then
        raise exception 'FAIL: credit sale snapshotted cost %', v_cost;
    end if;

    -- The carnet knows who, how much, and what was taken.
    select total_owed into v_owed
      from customer_debts('93000000-0000-0000-0000-000000000001'::uuid)
     where customer_name = 'Awa';
    if v_owed is distinct from 1200 then
        raise exception 'FAIL: Awa owes %, expected 1200', v_owed;
    end if;
    select label, sale_id into v_label, v_debt_sale from debts
     where org_id = '93000000-0000-0000-0000-000000000001';
    if v_label not like '%Riz%' then
        raise exception 'FAIL: the debt says "%" instead of naming the rice', v_label;
    end if;
    if v_debt_sale is distinct from v_sale then
        raise exception 'FAIL: the debt does not point back at its sale';
    end if;

    -- The books balance, and no cash account moved for this entry.
    select sum(l.debit), sum(l.credit) into v_debit, v_credit
      from journal_lines l
      join journal_entries e on e.id = l.journal_entry_id
     where e.org_id = '93000000-0000-0000-0000-000000000001';
    if v_debit <> v_credit then
        raise exception 'FAIL: books unbalanced (% / %)', v_debit, v_credit;
    end if;
    select count(*) into v_cash_touched
      from journal_lines l
      join accounts a on a.id = l.account_id
     where l.journal_entry_id = (select entry_id from sales where id = v_sale)
       and a.code in ('1000', '1010', '1020');
    if v_cash_touched <> 0 then
        raise exception 'FAIL: a credit sale touched a cash account';
    end if;
    raise notice 'PASS: goods moved, créance booked, cash untouched';
end $$;
commit;

\echo ''
\echo '--- TEST 2: the second delivery of the same credit sale is one sale ---'
begin;
set local "request.jwt.claim.sub" = '93939393-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v1 uuid; v2 uuid; v_debts int; v_qty numeric;
begin
    select id into v1 from sales
     where client_uuid = 'd3000000-0000-0000-0000-000000000001';
    v2 := record_sale('93000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_array(jsonb_build_object('name', 'Riz',
            'quantity', 2, 'unit_price', 600)),
        p_method        => 'credit',
        p_customer_name => 'Awa',
        p_client_uuid   => 'd3000000-0000-0000-0000-000000000001'::uuid);
    if v1 <> v2 then
        raise exception 'FAIL: replay created a second sale';
    end if;
    select count(*) into v_debts from debts
     where org_id = '93000000-0000-0000-0000-000000000001';
    if v_debts <> 1 then
        raise exception 'FAIL: % debts after a replay', v_debts;
    end if;
    select quantity into v_qty from products
     where org_id = '93000000-0000-0000-0000-000000000001'
       and lower(btrim(name)) = 'riz';
    if v_qty <> 8 then
        raise exception 'FAIL: replay moved the shelf to %', v_qty;
    end if;
    raise notice 'PASS: one sale, one debt, shelf unmoved';
end $$;
commit;

\echo ''
\echo '--- TEST 3: the 024 repayment flow settles a 029 debt ---'
begin;
set local "request.jwt.claim.sub" = '93939393-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_debt uuid; v_remaining numeric;
    v_debit numeric; v_credit numeric;
begin
    select id into v_debt from debts
     where org_id = '93000000-0000-0000-0000-000000000001';
    perform record_debt_payment(v_debt, 700,
        p_client_uuid => 'd3000000-0000-0000-0000-000000000002'::uuid);

    select remaining into v_remaining
      from debts_of_customer('93000000-0000-0000-0000-000000000001'::uuid,
        (select customer_id from debts where id = v_debt))
     where debt_id = v_debt;
    if v_remaining is distinct from 500 then
        raise exception 'FAIL: % remaining after 700 of 1200', v_remaining;
    end if;

    select sum(l.debit), sum(l.credit) into v_debit, v_credit
      from journal_lines l
      join journal_entries e on e.id = l.journal_entry_id
     where e.org_id = '93000000-0000-0000-0000-000000000001';
    if v_debit <> v_credit then
        raise exception 'FAIL: books unbalanced after repayment (% / %)', v_debit, v_credit;
    end if;
    raise notice 'PASS: 700 repaid, 500 due, books balance at % = %',
        v_debit, v_credit;
end $$;
commit;

\echo ''
\echo '--- TEST 4: no name, no credit; and a return on credit is refused ---'
begin;
set local "request.jwt.claim.sub" = '93939393-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_sale uuid;
begin
    begin
        perform record_sale('93000000-0000-0000-0000-000000000001'::uuid,
            jsonb_build_array(jsonb_build_object('name', 'Riz',
                'quantity', 1, 'unit_price', 600)),
            p_method => 'credit');
        raise exception 'FAIL: a credit sale without a customer was accepted';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: nameless credit refused — %', sqlerrm;
    end;

    select id into v_sale from sales
     where client_uuid = 'd3000000-0000-0000-0000-000000000001';
    begin
        perform record_return(v_sale);
        raise exception 'FAIL: a return was accepted on a credit sale';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: return on credit refused — %', sqlerrm;
    end;
end $$;
commit;

\echo ''
\echo '--- TEST 5: a cash sale still works and leaves no debt behind ---'
begin;
set local "request.jwt.claim.sub" = '93939393-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_debts_before int; v_debts_after int;
    v_qty numeric;
begin
    select count(*) into v_debts_before from debts
     where org_id = '93000000-0000-0000-0000-000000000001';

    perform record_sale('93000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_array(jsonb_build_object('name', 'Riz',
            'quantity', 1, 'unit_price', 600)));

    select quantity into v_qty from products
     where org_id = '93000000-0000-0000-0000-000000000001'
       and lower(btrim(name)) = 'riz';
    if v_qty <> 7 then
        raise exception 'FAIL: cash sale left the shelf at %', v_qty;
    end if;
    select count(*) into v_debts_after from debts
     where org_id = '93000000-0000-0000-0000-000000000001';
    if v_debts_after <> v_debts_before then
        raise exception 'FAIL: a cash sale wrote into the carnet';
    end if;
    raise notice 'PASS: the employee''s cash sale is a sale like before';
end $$;
commit;

\echo ''
\echo '--- TEST 6: the neighbour cannot sell here at all ---'
begin;
set local "request.jwt.claim.sub" = '93939393-0000-0000-0000-000000000003';
set local role authenticated;
do $$
begin
    begin
        perform record_sale('93000000-0000-0000-0000-000000000001'::uuid,
            jsonb_build_array(jsonb_build_object('name', 'Intrusion',
                'quantity', 1, 'unit_price', 100)));
        raise exception 'FAIL: a stranger recorded a sale';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: stranger refused — %', sqlerrm;
    end;
end $$;
commit;

\echo ''
\echo '=== test_sale_on_credit.sql: all assertions passed ==='
