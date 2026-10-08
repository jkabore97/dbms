-- ============================================================
-- test_retail.sql — proof that a shop's books survive a shop.
--
-- Same discipline as the other suites here: every assertion runs as the
-- `authenticated` role with request.jwt.claim.sub set, never as the superuser
-- that owns the tables. record_sale() is SECURITY DEFINER; a suite run as
-- postgres would report a clean pass against checks that do nothing.
--
-- Most of this file is the four ways a retail module quietly lies about
-- money:
--
--   1. A sale recorded twice because the phone retried in a market.
--   2. A return that gives the money back but not the goods, or the goods but
--      not the money.
--   3. A product's cost price changed later, silently rewriting the margin on
--      sales already made.
--   4. Debits and credits drifting apart once sales post through a different
--      path than contributions do.
--
-- This suite owns phone block 78. Every suite commits into one database in
-- CI: 70 rls, 71 invitations, 72 reports, 73 accounting, 74 audit, 75 and 76
-- farm, 77 platform admin, 78 here.
--
-- Failures raise. A green run means every assertion below held.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''78787878-0000-0000-0000-000000000001'''
\set clerk '''78787878-0000-0000-0000-000000000002'''
\set rival '''78787878-0000-0000-0000-000000000003'''

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
    (:owner, '+22678000001', '{"full_name": "Esperance"}'),
    (:clerk, '+22678000002', '{"full_name": "Vendeuse"}'),
    (:rival, '+22678000003', '{"full_name": "Un autre commerçant"}');

-- Two shops, so cross-tenant isolation is testable. Created directly rather
-- than through create_org(), which needs the platform-admin flag and is
-- covered by its own suite.
insert into orgs (id, name, slug, profile, default_currency) values
    ('78000000-0000-0000-0000-000000000001', 'Boutique Esperance', 'boutique-esperance', 'retail', 'XOF'),
    ('78000000-0000-0000-0000-000000000002', 'Boutique Rivale',    'boutique-rivale',    'retail', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    ('78000000-0000-0000-0000-000000000001', :owner, 'owner',    'org', '78000000-0000-0000-0000-000000000001'),
    ('78000000-0000-0000-0000-000000000001', :clerk, 'employee', 'org', '78000000-0000-0000-0000-000000000001'),
    ('78000000-0000-0000-0000-000000000002', :rival, 'owner',    'org', '78000000-0000-0000-0000-000000000002');

select seed_retail_accounts('78000000-0000-0000-0000-000000000001');
select seed_retail_accounts('78000000-0000-0000-0000-000000000002');

\echo ''
\echo '--- TEST 1: a shop is seeded with accounts a shopkeeper recognises ---'
do $$
declare v_names text[];
begin
    select array_agg(name order by code) into v_names
    from accounts where org_id = '78000000-0000-0000-0000-000000000001';

    if not (v_names @> array['Caisse', 'Ventes', 'Achats de marchandises']) then
        raise exception 'FAIL: retail chart of accounts is %', v_names;
    end if;
    raise notice 'PASS: seeded % accounts, named for a shop', array_length(v_names, 1);
end $$;

\echo ''
\echo '--- TEST 2: stock arriving raises the count and books the purchase ---'
begin;
set local "request.jwt.claim.sub" = '78787878-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_product uuid;
    v_qty     numeric;
    v_expense numeric;
begin
    v_product := ensure_product('78000000-0000-0000-0000-000000000001',
                                'Sucre 1kg', 750, 500);
    perform receive_products('78000000-0000-0000-0000-000000000001',
                             v_product, 20, 500);

    select quantity into v_qty from products where id = v_product;
    if v_qty <> 20 then
        raise exception 'FAIL: 20 received, count reads %', v_qty;
    end if;

    -- 20 x 500 out of the till.
    select coalesce(sum(jl.debit), 0) into v_expense
    from journal_lines jl
    join accounts a on a.id = jl.account_id
    where a.org_id = '78000000-0000-0000-0000-000000000001'
      and a.name = 'Achats de marchandises';
    if v_expense <> 10000 then
        raise exception 'FAIL: purchase booked %, expected 10000', v_expense;
    end if;
    raise notice 'PASS: 20 in stock, 10 000 booked as a purchase';
end $$;
commit;

\echo ''
\echo '--- TEST 3: a sale moves goods and money in the same breath ---'
begin;
set local "request.jwt.claim.sub" = '78787878-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_product uuid;
    v_sale    uuid;
    v_qty     numeric;
    v_income  numeric;
    v_total   numeric;
begin
    select id into v_product from products
    where org_id = '78000000-0000-0000-0000-000000000001' and name = 'Sucre 1kg';

    v_sale := record_sale(
        '78000000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object(
            'product_id', v_product, 'quantity', 3, 'unit_price', 750)),
        'cash'
    );

    select total into v_total from sales where id = v_sale;
    if v_total <> 2250 then
        raise exception 'FAIL: sale total is %, expected 2250', v_total;
    end if;

    select quantity into v_qty from products where id = v_product;
    if v_qty <> 17 then
        raise exception 'FAIL: 3 sold from 20, count reads %', v_qty;
    end if;

    select coalesce(sum(jl.credit), 0) into v_income
    from journal_lines jl
    join accounts a on a.id = jl.account_id
    where a.org_id = '78000000-0000-0000-0000-000000000001'
      and a.name = 'Ventes';
    if v_income <> 2250 then
        raise exception 'FAIL: income booked %, expected 2250', v_income;
    end if;

    raise notice 'PASS: 3 sold, 17 left, 2 250 booked as income';
end $$;
commit;

\echo ''
\echo '--- TEST 4: the same sale retried from a market is still one sale ---'
begin;
set local "request.jwt.claim.sub" = '78787878-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_product uuid;
    v_first   uuid;
    v_second  uuid;
    v_qty     numeric;
    v_count   int;
    v_uuid    uuid := 'aaaaaaaa-0000-0000-0000-000000000078';
begin
    select id into v_product from products
    where org_id = '78000000-0000-0000-0000-000000000001' and name = 'Sucre 1kg';

    v_first := record_sale('78000000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object(
            'product_id', v_product, 'quantity', 2, 'unit_price', 750)),
        'cash', null, v_uuid);

    -- The phone gets signal, is not sure the first one landed, and retries.
    v_second := record_sale('78000000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object(
            'product_id', v_product, 'quantity', 2, 'unit_price', 750)),
        'cash', null, v_uuid);

    if v_first is distinct from v_second then
        raise exception 'FAIL: the retry made a second sale (% and %)', v_first, v_second;
    end if;

    select count(*) into v_count from sales
    where org_id = '78000000-0000-0000-0000-000000000001' and client_uuid = v_uuid;
    if v_count <> 1 then
        raise exception 'FAIL: % sales share one client_uuid', v_count;
    end if;

    select quantity into v_qty from products where id = v_product;
    if v_qty <> 15 then
        raise exception 'FAIL: 2 sold once, count reads % (expected 15)', v_qty;
    end if;

    raise notice 'PASS: retried sale returned the original, stock moved once';
end $$;
commit;

\echo ''
\echo '--- TEST 5: a return puts the goods back and the money out ---'
begin;
set local "request.jwt.claim.sub" = '78787878-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_product uuid;
    v_sale    uuid;
    v_return  uuid;
    v_qty     numeric;
    v_before  numeric;
    v_after   numeric;
begin
    select id into v_product from products
    where org_id = '78000000-0000-0000-0000-000000000001' and name = 'Sucre 1kg';
    select quantity into v_before from products where id = v_product;

    v_sale := record_sale('78000000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object(
            'product_id', v_product, 'quantity', 1, 'unit_price', 750)), 'cash');

    v_return := record_return(v_sale, 'Client a changé d''avis');

    select quantity into v_after from products where id = v_product;
    if v_after <> v_before then
        raise exception 'FAIL: sold 1 and returned 1, count went % -> %', v_before, v_after;
    end if;

    -- Both rows survive: the sale and the return.
    if not exists (select 1 from sales where id = v_sale and kind = 'sale') then
        raise exception 'FAIL: the original sale is gone';
    end if;
    if not exists (select 1 from sales where id = v_return
                     and kind = 'return' and reverses_id = v_sale) then
        raise exception 'FAIL: the return does not point at the sale';
    end if;

    raise notice 'PASS: goods back on the shelf, both rows still in the books';
end $$;
commit;

\echo ''
\echo '--- TEST 6: a sale cannot be returned twice ---'
begin;
set local "request.jwt.claim.sub" = '78787878-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_product uuid;
    v_sale    uuid;
begin
    select id into v_product from products
    where org_id = '78000000-0000-0000-0000-000000000001' and name = 'Sucre 1kg';

    v_sale := record_sale('78000000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object(
            'product_id', v_product, 'quantity', 1, 'unit_price', 750)), 'cash');
    perform record_return(v_sale);

    begin
        perform record_return(v_sale);
        raise exception 'FAIL: the same sale was returned twice';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: second return refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 7: changing a price does not rewrite a sale already made ---'
begin;
set local "request.jwt.claim.sub" = '78787878-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_product uuid;
    v_sale    uuid;
    v_cost    numeric;
begin
    select id into v_product from products
    where org_id = '78000000-0000-0000-0000-000000000001' and name = 'Sucre 1kg';

    v_sale := record_sale('78000000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object(
            'product_id', v_product, 'quantity', 1, 'unit_price', 750)), 'cash');

    -- The supplier puts the price up next week.
    update products set cost_price = 900 where id = v_product;

    select unit_cost into v_cost from sale_lines where sale_id = v_sale;
    if v_cost <> 500 then
        raise exception 'FAIL: the old sale now reports a cost of %', v_cost;
    end if;
    raise notice 'PASS: the sale kept the cost it was made at';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: expiry alerts value the risk, and the day adds up ---'
begin;
set local "request.jwt.claim.sub" = '78787878-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_milk  uuid;
    v_rows  int;
    v_risk  numeric;
    v_net   numeric;
begin
    v_milk := ensure_product('78000000-0000-0000-0000-000000000001',
                             'Lait frais', 1000, 700,
                             p_expires_on => current_date + 5);
    perform receive_products('78000000-0000-0000-0000-000000000001',
                             v_milk, 10, 700);

    select count(*), coalesce(sum(value_at_risk), 0)
      into v_rows, v_risk
    from expiring_products('78000000-0000-0000-0000-000000000001', 14);

    if v_rows < 1 then
        raise exception 'FAIL: milk expiring in 5 days is not being flagged';
    end if;
    if v_risk < 7000 then
        raise exception 'FAIL: 10 x 700 at risk reported as %', v_risk;
    end if;

    -- Sugar that expires next year must not be in the same list.
    if exists (select 1 from expiring_products('78000000-0000-0000-0000-000000000001', 14)
               where name = 'Sucre 1kg') then
        raise exception 'FAIL: a product with no expiry date is being flagged';
    end if;

    select net_sales into v_net
    from store_day('78000000-0000-0000-0000-000000000001', current_date);
    if v_net is null then
        raise exception 'FAIL: store_day returned nothing';
    end if;

    raise notice 'PASS: % expiring, % at risk, day nets %', v_rows, v_risk, v_net;
end $$;
rollback;

\echo ''
\echo '--- TEST 9: the books still balance after everything above ---'
do $$
declare
    v_debits  numeric;
    v_credits numeric;
begin
    select coalesce(sum(jl.debit), 0), coalesce(sum(jl.credit), 0)
      into v_debits, v_credits
    from journal_lines jl
    join accounts a on a.id = jl.account_id
    where a.org_id = '78000000-0000-0000-0000-000000000001';

    if v_debits <> v_credits then
        raise exception 'FAIL: debits % <> credits %', v_debits, v_credits;
    end if;
    if v_debits = 0 then
        raise exception 'FAIL: nothing was posted at all';
    end if;
    raise notice 'PASS: debits = credits = %', v_debits;
end $$;

\echo ''
\echo '--- TEST 10: the shop next door sees none of it ---'
begin;
set local "request.jwt.claim.sub" = '78787878-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_products int;
    v_sales    int;
    v_lines    int;
begin
    select count(*) into v_products from products;
    select count(*) into v_sales    from sales;
    select count(*) into v_lines    from sale_lines;

    if v_products <> 0 or v_sales <> 0 or v_lines <> 0 then
        raise exception 'FAIL: the rival sees % products, % sales, % lines',
            v_products, v_sales, v_lines;
    end if;
    raise notice 'PASS: a shopkeeper next door sees nothing of this shop';
end $$;
rollback;

\echo ''
\echo '--- TEST 11: an observer may read the shelves and may not touch them ---'
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
values ('78000000-0000-0000-0000-000000000001', :rival, 'observer', 'org',
        '78000000-0000-0000-0000-000000000001', 'full');

begin;
set local "request.jwt.claim.sub" = '78787878-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_products int;
begin
    select count(*) into v_products from products;
    if v_products = 0 then
        raise exception 'FAIL: an observer cannot see the shelves at all';
    end if;

    begin
        insert into products (org_id, name)
        values ('78000000-0000-0000-0000-000000000001', 'Marchandise fantôme');
        raise exception 'FAIL: an observer added a product';
    exception
        when insufficient_privilege then
            raise notice 'PASS: observer reads % products, writes none', v_products;
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: observer refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo 'test_retail.sql: all assertions held.'
