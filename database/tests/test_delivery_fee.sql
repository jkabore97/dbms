-- ============================================================
-- test_delivery_fee.sql — what a delivery costs (061).
-- Phone block 33.
--
-- The claims: the street can ask what a delivery would cost and gets a
-- number from base + per-km between the two pins, rounded to 25; no pin on
-- either side means no number, never a guess; a shop may set its own two
-- numbers (both or neither, never negative, administrators only) and they
-- win over the platform's; only the platform changes the defaults; the
-- fee is fixed on the order when it is placed and every reader of the
-- order — customer, shop, courier board, courier — sees it; a pickup has
-- none.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''33333333-0000-0000-0000-000000000001'''
\set customer '''33333333-0000-0000-0000-000000000002'''
\set courier  '''33333333-0000-0000-0000-000000000003'''
\set plat     '''33333333-0000-0000-0000-000000000004'''
\set shop_a   '''33000000-0000-0000-0000-000000000001'''
\set shop_b   '''33000000-0000-0000-0000-000000000002'''
\set p_riz    '''33aaaaaa-0000-0000-0000-000000000001'''
\set p_lait   '''33aaaaaa-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22633000001', '{"full_name": "Esperance"}'),
    (:customer, '+22633000002', '{"full_name": "Awa Client"}'),
    (:courier,  '+22633000003', '{"full_name": "Moussa"}'),
    (:plat,     '+22633000004', '{"full_name": "Plateforme"}');
update profiles set is_platform_admin = true where id = :plat;

-- A is placed at Rood Woko; B never placed itself.
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, lat, lng) values
    (:shop_a, 'Boutique Esperance', 'frais-a-33', 'retail', 'XOF', true, 12.3714, -1.5197),
    (:shop_b, 'Boutique Sans Pin',  'frais-b-33', 'retail', 'XOF', true, null,    null);
select seed_retail_accounts(:shop_a);
select seed_retail_accounts(:shop_b);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop_a, :owner, 'owner', 'org', :shop_a, 'full');
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published, created_by) values
    (:p_riz,  :shop_a, 'Riz 25kg 33', 17500, 15000, 4, true, true, :owner),
    (:p_lait, :shop_b, 'Lait 33',      3200,  2800, 2, true, true, :owner);
insert into couriers (user_id, phone, status) values (:courier, '+22633000003', 'approved');

-- 0.018° of latitude north of the shop is 2.0016 km: 500 + 150 × 2.0016
-- = 800.24, which rounds to 800.
\echo ''
\echo '--- TEST 1: the street gets a number from the two pins, or nothing ---'
begin;
set local role authenticated;
do $$
declare v_fee numeric;
begin
    v_fee := delivery_quote('frais-a-33', 12.3894, -1.5197);
    if v_fee <> 800 then
        raise exception 'FAIL: expected 800 for ~2 km at the defaults, got %', v_fee;
    end if;
    if delivery_quote('frais-a-33', null, null) is not null then
        raise exception 'FAIL: a quote with no customer pin answered a number';
    end if;
    if delivery_quote('frais-b-33', 12.3894, -1.5197) is not null then
        raise exception 'FAIL: a shop with no pin answered a number';
    end if;
    -- Ten kilometres: 500 + 1500.5 ≈ 2000 after rounding to 25.
    v_fee := delivery_quote('frais-a-33', 12.4614, -1.5197);
    if v_fee <> 2000 then
        raise exception 'FAIL: expected 2000 for ~10 km, got %', v_fee;
    end if;
    raise notice 'PASS: 800 at 2 km, 2000 at 10 km, nothing without a pin on either side';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: a shop sets its own numbers — both or neither, never negative, admins only ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :customer;
do $$
begin
    begin
        perform set_delivery_rates('33000000-0000-0000-0000-000000000001', 1000, 200);
        raise exception 'FAIL: a customer set a shop''s rates';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: a customer was refused — %', sqlerrm;
    end;
end $$;
set local "request.jwt.claim.sub" = :owner;
do $$
begin
    begin
        perform set_delivery_rates('33000000-0000-0000-0000-000000000001', 1000, null);
        raise exception 'FAIL: half a rate was accepted';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: half a rate was refused — %', sqlerrm;
    end;
    begin
        perform set_delivery_rates('33000000-0000-0000-0000-000000000001', -1, 200);
        raise exception 'FAIL: a negative rate was accepted';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: a negative rate was refused — %', sqlerrm;
    end;
end $$;
select set_delivery_rates(:shop_a, 1000, 200);
do $$
declare v_fee numeric;
begin
    v_fee := delivery_quote('frais-a-33', 12.3894, -1.5197);
    -- 1000 + 200 × 2.0016 = 1400.32 → 1400
    if v_fee <> 1400 then
        raise exception 'FAIL: the shop''s own rates should give 1400, got %', v_fee;
    end if;
    raise notice 'PASS: the shop''s own rates win — 1400';
end $$;
select set_delivery_rates(:shop_a, null, null);
do $$
begin
    if delivery_quote('frais-a-33', 12.3894, -1.5197) <> 800 then
        raise exception 'FAIL: clearing the rates did not return to the defaults';
    end if;
    raise notice 'PASS: null-null returns the shop to the platform''s defaults';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: only the platform changes the defaults ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :owner;
do $$
begin
    begin
        perform set_platform_setting('delivery_base', '9999');
        raise exception 'FAIL: a shop owner changed the platform defaults';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the owner was refused — %', sqlerrm;
    end;
end $$;
set local "request.jwt.claim.sub" = :plat;
select set_platform_setting('delivery_base', '700');
do $$
begin
    -- 700 + 300.24 = 1000.24 → 1000
    if delivery_quote('frais-a-33', 12.3894, -1.5197) <> 1000 then
        raise exception 'FAIL: the new default did not reach the quote';
    end if;
    raise notice 'PASS: the platform moved the base to 700 and the quote followed';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the fee is fixed on the order and every reader sees it; a pickup has none ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :customer;
create temp table t33 (which text, id uuid);
grant select, insert on t33 to authenticated;
insert into t33 values ('delivery', place_order('frais-a-33',
    '[{"product_id":"33aaaaaa-0000-0000-0000-000000000001","quantity":1}]'::jsonb,
    'delivery', null, 'Dassasgho, en face de la pharmacie', null, 'cash', 12.3894, -1.5197));
insert into t33 values ('pickup', place_order('frais-a-33',
    '[{"product_id":"33aaaaaa-0000-0000-0000-000000000001","quantity":1}]'::jsonb,
    'pickup', null, null, null, 'cash', 12.3894, -1.5197));
do $$
declare v_fee numeric; v_pick numeric;
begin
    select m.delivery_fee into v_fee from my_orders() m
     where m.id = (select id from t33 where which = 'delivery');
    select m.delivery_fee into v_pick from my_orders() m
     where m.id = (select id from t33 where which = 'pickup');
    if v_fee <> 800 or v_pick is not null then
        raise exception 'FAIL: customer sees fee % on the delivery and % on the pickup', v_fee, v_pick;
    end if;
    raise notice 'PASS: the customer sees 800 on the delivery and nothing on the pickup';
end $$;
set local "request.jwt.claim.sub" = :owner;
do $$
declare v_fee numeric;
begin
    select s.delivery_fee into v_fee from shop_orders('33000000-0000-0000-0000-000000000001') s
     where s.id = (select id from t33 where which = 'delivery');
    if v_fee <> 800 then
        raise exception 'FAIL: the shop sees fee %', v_fee;
    end if;
    -- Ready for a courier: the board must carry the fee and the distance.
    perform decide_order((select id from t33 where which = 'delivery'), 'accepted');
    perform decide_order((select id from t33 where which = 'delivery'), 'ready');
    raise notice 'PASS: the shop sees 800';
end $$;
set local "request.jwt.claim.sub" = :courier;
do $$
declare v_fee numeric; v_km double precision;
begin
    select a.delivery_fee, a.distance_km into v_fee, v_km from available_deliveries() a
     where a.order_id = (select id from t33 where which = 'delivery');
    if v_fee <> 800 or v_km is null or abs(v_km - 2.0016) > 0.01 then
        raise exception 'FAIL: the board shows fee % at % km', v_fee, v_km;
    end if;
    perform take_delivery((select id from t33 where which = 'delivery'));
    select c.delivery_fee into v_fee from courier_deliveries() c
     where c.order_id = (select id from t33 where which = 'delivery');
    if v_fee <> 800 then
        raise exception 'FAIL: the courier''s own list shows fee %', v_fee;
    end if;
    raise notice 'PASS: the board and the courier''s list carry 800 and ~2.0 km';
end $$;
rollback;

\echo ''
\echo '=== test_delivery_fee.sql: all checks passed ==='
