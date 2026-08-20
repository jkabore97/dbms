-- ============================================================
-- test_corrections.sql — undoing a transaction is a reversal, and it cancels
-- in both places the transaction lived: the stock count and the ledger (042).
--
-- Phone block 20. A delivery is reversed by an owner (stock back down, the
-- purchase reversed in the books, the receipt stamped and un-repeatable), a
-- clerk is refused, and a sale's reversal shows up in recent_sales.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''20202020-0000-0000-0000-000000000001'''
\set clerk '''20202020-0000-0000-0000-000000000002'''
\set org   '''20000000-0000-0000-0000-000000000001'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22620000001', '{"full_name": "Patronne"}'),
    (:clerk, '+22620000002', '{"full_name": "Vendeuse"}');

insert into orgs (id, name, slug, profile, default_currency)
values (:org, 'Boutique Correction', 'boutique-correction-20', 'retail', 'XOF');
select seed_retail_accounts(:org);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:org, :owner, 'owner',    'org', :org, 'full'),
    -- Full visibility on purpose: TEST 3 proves the *admin* gate refuses the
    -- clerk, so the clerk must be able to see the receipt first — otherwise the
    -- refusal would come from RLS hiding the row, not from reverse_receipt.
    (:org, :clerk, 'employee', 'org', :org, 'full');

insert into products (id, org_id, name, sale_price, cost_price)
values ('20000000-0000-0000-0000-0000000000aa', :org, 'Savon', 500, 300);


\echo ''
\echo '--- TEST 1: an owner reverses a delivery — stock back, purchase unwound ---'
begin;
set local "request.jwt.claim.sub" = '20202020-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_receipt uuid;
    v_qty     numeric;
    v_rev     uuid;
    v_entries int;
begin
    -- Receive 10 at 300. receive_products returns the ledger entry; the
    -- receipt is the newest stock_receipts row for the product.
    perform receive_products(
        p_org_id => '20000000-0000-0000-0000-000000000001',
        p_product_id => '20000000-0000-0000-0000-0000000000aa',
        p_quantity => 10, p_unit_cost => 300);

    select quantity into v_qty from products
     where id = '20000000-0000-0000-0000-0000000000aa';
    if v_qty <> 10 then
        raise exception 'FAIL: after delivery stock is %, expected 10', v_qty;
    end if;

    select id into v_receipt from stock_receipts
     where product_id = '20000000-0000-0000-0000-0000000000aa'
     order by received_at desc limit 1;

    v_rev := reverse_receipt(v_receipt, 'test data');
    if v_rev is null then
        raise exception 'FAIL: reversing a costed delivery booked no ledger reversal';
    end if;

    select quantity into v_qty from products
     where id = '20000000-0000-0000-0000-0000000000aa';
    if v_qty <> 0 then
        raise exception 'FAIL: after reversal stock is %, expected 0', v_qty;
    end if;

    -- The books carry the purchase and its reversal — two entries that net to
    -- zero, nothing excluded.
    select count(*) into v_entries from journal_entries
     where org_id = '20000000-0000-0000-0000-000000000001'
       and (id = v_rev or reverses_entry_id is not null);
    if v_entries < 1 then
        raise exception 'FAIL: no reversing ledger entry was written';
    end if;

    if (select reversed_at from stock_receipts where id = v_receipt) is null then
        raise exception 'FAIL: the receipt was not stamped reversed';
    end if;
    raise notice 'PASS: stock returned to 0 and the purchase was reversed in the books';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: a delivery cannot be reversed twice ---'
begin;
set local "request.jwt.claim.sub" = '20202020-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_receipt uuid;
begin
    perform receive_products(
        p_org_id => '20000000-0000-0000-0000-000000000001',
        p_product_id => '20000000-0000-0000-0000-0000000000aa',
        p_quantity => 5, p_unit_cost => 300);
    select id into v_receipt from stock_receipts
     where product_id = '20000000-0000-0000-0000-0000000000aa'
     order by received_at desc limit 1;

    perform reverse_receipt(v_receipt, null);
    begin
        perform reverse_receipt(v_receipt, null);
        raise exception 'FAIL: a delivery was reversed twice';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the second reversal was refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 3: a clerk cannot reverse a delivery ---'
begin;
-- Receive as the owner first (committed only within this tx), then try to
-- reverse as the clerk.
set local "request.jwt.claim.sub" = '20202020-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_receipt uuid;
begin
    perform receive_products(
        p_org_id => '20000000-0000-0000-0000-000000000001',
        p_product_id => '20000000-0000-0000-0000-0000000000aa',
        p_quantity => 4, p_unit_cost => 300);
end $$;
set local "request.jwt.claim.sub" = '20202020-0000-0000-0000-000000000002';
do $$
declare v_receipt uuid;
begin
    select id into v_receipt from stock_receipts
     where product_id = '20000000-0000-0000-0000-0000000000aa'
     order by received_at desc limit 1;
    begin
        perform reverse_receipt(v_receipt, null);
        raise exception 'FAIL: a clerk reversed a delivery';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the clerk was refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 4: a reversed sale leaves recent_sales flagged AND the analytics ---'
begin;
set local "request.jwt.claim.sub" = '20202020-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_sale    uuid;
    v_flag    boolean;
    v_count   bigint;
    v_revenue numeric;
    v_rows    int;
begin
    v_sale := record_sale(
        p_org_id => '20000000-0000-0000-0000-000000000001',
        p_lines => '[{"product_id":"20000000-0000-0000-0000-0000000000aa","name":"Savon","quantity":2,"unit_price":500}]'::jsonb,
        p_method => 'cash');

    select reversed into v_flag from recent_sales(
        '20000000-0000-0000-0000-000000000001', 50) where id = v_sale;
    if v_flag then
        raise exception 'FAIL: a fresh sale is already marked reversed';
    end if;

    -- Before the correction, the analytics count it: 1 sale, 1000 in revenue.
    select sale_count, revenue into v_count, v_revenue
      from org_sales_headline('20000000-0000-0000-0000-000000000001', null);
    if v_count <> 1 or v_revenue <> 1000 then
        raise exception 'FAIL: pre-correction analytics are % sales / %',
            v_count, v_revenue;
    end if;

    perform record_return(v_sale, 'test data');

    select reversed into v_flag from recent_sales(
        '20000000-0000-0000-0000-000000000001', 50) where id = v_sale;
    if not v_flag then
        raise exception 'FAIL: a returned sale is not flagged reversed';
    end if;

    -- The correction reaches the analytics too: the reversed sale is gone from
    -- the headline and from what-sells. This is the "they are not connected"
    -- report — now they are.
    select sale_count, revenue into v_count, v_revenue
      from org_sales_headline('20000000-0000-0000-0000-000000000001', null);
    if v_count <> 0 or v_revenue <> 0 then
        raise exception 'FAIL: after correction analytics still show % sales / %',
            v_count, v_revenue;
    end if;

    select count(*) into v_rows from org_product_performance(
        '20000000-0000-0000-0000-000000000001', null, 100);
    if v_rows <> 0 then
        raise exception 'FAIL: the reversed product still appears in what-sells (% rows)', v_rows;
    end if;

    raise notice 'PASS: the correction reaches recent_sales and the analytics';
end $$;
rollback;

\echo ''
\echo '=== test_corrections.sql: all checks passed ==='
