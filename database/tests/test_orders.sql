-- ============================================================
-- test_orders.sql — a customer's réservation, from both sides (055).
-- Phone block 28.
--
-- The claims: only a signed-in customer can order, and only what the
-- street can see, from a shop that is open; the total is the shelf's, not
-- the phone's; the shop's bell rings; the customer sees their own orders
-- and nobody else's, and may cancel only while the shop has not answered;
-- any writer of the shop may answer, a stranger, the customer and a
-- suspended shop may not; an order only moves along the drawn lines and a
-- final state is final; and nothing here touches stock.
-- ============================================================
\set ON_ERROR_STOP on

\set owner_a  '''28282828-0000-0000-0000-000000000001'''
\set clerk_a  '''28282828-0000-0000-0000-000000000002'''
\set customer '''28282828-0000-0000-0000-000000000003'''
\set stranger '''28282828-0000-0000-0000-000000000004'''
\set shop_a   '''28000000-0000-0000-0000-000000000001'''
\set shop_b   '''28000000-0000-0000-0000-000000000002'''
\set p_riz    '''28aaaaaa-0000-0000-0000-000000000001'''
\set p_savon  '''28aaaaaa-0000-0000-0000-000000000002'''
\set p_lait   '''28aaaaaa-0000-0000-0000-000000000003'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner_a,  '+22628000001', '{"full_name": "Esperance"}'),
    (:clerk_a,  '+22628000002', '{"full_name": "Vendeuse"}'),
    (:customer, '+22628000003', '{"full_name": "Awa Client"}'),
    (:stranger, '+22628000004', '{"full_name": "Passant"}');

insert into orgs (id, name, slug, profile, default_currency, storefront_enabled) values
    (:shop_a, 'Boutique Esperance', 'commande-a-28', 'retail', 'XOF', true),
    (:shop_b, 'Boutique Fermee',    'commande-b-28', 'retail', 'XOF', false);
select seed_retail_accounts(:shop_a);
select seed_retail_accounts(:shop_b);

insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop_a, :owner_a, 'owner',    'org', :shop_a, 'full'),
    (:shop_a, :clerk_a, 'employee', 'org', :shop_a, 'full');

insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published, created_by) values
    (:p_riz,   :shop_a, 'Riz parfumé 25kg', 17500, 15000, 4, true, true,  :owner_a),
    (:p_savon, :shop_a, 'Savon',              450,   300, 9, true, false, :owner_a),
    (:p_lait,  :shop_b, 'Lait Nido',         3200,  2800, 2, true, true,  :owner_a);

\echo ''
\echo '--- TEST 1: only a signed-in customer orders, only what the street sees, only from an open shop ---'
begin;
set local role authenticated;
do $$
begin
    begin
        perform place_order('commande-a-28', '[{"product_id":"28aaaaaa-0000-0000-0000-000000000001","quantity":1}]'::jsonb);
        raise exception 'FAIL: the street placed an order';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the street was refused — %', sqlerrm;
    end;
end $$;
set local "request.jwt.claim.sub" = :customer;
do $$
begin
    begin
        perform place_order('commande-b-28', '[{"product_id":"28aaaaaa-0000-0000-0000-000000000003","quantity":1}]'::jsonb);
        raise exception 'FAIL: an order was placed at a closed vitrine';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the closed shop refused — %', sqlerrm;
    end;
    begin
        perform place_order('commande-a-28', '[{"product_id":"28aaaaaa-0000-0000-0000-000000000002","quantity":1}]'::jsonb);
        raise exception 'FAIL: an unpublished article was ordered';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the unpublished article was refused — %', sqlerrm;
    end;
    begin
        perform place_order('commande-a-28', '[{"product_id":"28aaaaaa-0000-0000-0000-000000000001","quantity":1}]'::jsonb, 'delivery');
        raise exception 'FAIL: a delivery with no address was accepted';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: a delivery needs an address — %', sqlerrm;
    end;
    begin
        perform place_order('commande-a-28', '[]'::jsonb);
        raise exception 'FAIL: an empty order was accepted';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: an empty order was refused — %', sqlerrm;
    end;
    begin
        perform place_order('commande-a-28',
            '[{"product_id":"28aaaaaa-0000-0000-0000-000000000001","quantity":1}]'::jsonb,
            'delivery', null, 'Dassasgho', null, 'cash', 12.37, null);
        raise exception 'FAIL: half a delivery pin was accepted';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: half a pin is no pin — %', sqlerrm;
    end;
end $$;
rollback;

-- The pin itself (058): stored for a delivery, discarded for a pickup.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :customer;
do $$
declare v_id uuid; v_lat double precision; v_lng double precision;
begin
    v_id := place_order('commande-a-28',
        '[{"product_id":"28aaaaaa-0000-0000-0000-000000000001","quantity":1}]'::jsonb,
        'delivery', null, 'Dassasgho, en face de la pharmacie', null, 'cash',
        12.3901, -1.4877);
    select drop_lat, drop_lng into v_lat, v_lng from orders where id = v_id;
    if v_lat is distinct from 12.3901 or v_lng is distinct from -1.4877 then
        raise exception 'FAIL: the delivery pin was not kept (% / %)', v_lat, v_lng;
    end if;
    v_id := place_order('commande-a-28',
        '[{"product_id":"28aaaaaa-0000-0000-0000-000000000001","quantity":1}]'::jsonb,
        'pickup', null, null, null, 'cash', 12.3901, -1.4877);
    select drop_lat, drop_lng into v_lat, v_lng from orders where id = v_id;
    if v_lat is not null or v_lng is not null then
        raise exception 'FAIL: a pickup kept a pin (% / %)', v_lat, v_lng;
    end if;
    raise notice 'PASS: a delivery keeps its pin; a pickup''s destination is the shop';
end $$;
rollback;

-- A real order, kept: the rest of the suite follows it.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :customer;
do $$
declare v_id uuid; v_total numeric; v_lines int; v_name text; v_qty numeric;
begin
    v_id := place_order('commande-a-28',
        '[{"product_id":"28aaaaaa-0000-0000-0000-000000000001","quantity":2}]'::jsonb,
        'pickup', '  Je passe vers 17h  ', null, null);
    select total, customer_name into v_total, v_name from orders where id = v_id;
    if v_total <> 35000 then
        raise exception 'FAIL: the total is % not 35000', v_total;
    end if;
    if v_name <> 'Awa Client' then
        raise exception 'FAIL: the customer is named % not Awa Client', v_name;
    end if;
    select count(*), max(quantity) into v_lines, v_qty from order_lines where order_id = v_id;
    if v_lines <> 1 or v_qty <> 2 then
        raise exception 'FAIL: expected one line of 2, got % lines max %', v_lines, v_qty;
    end if;
    if (select quantity from products where id = '28aaaaaa-0000-0000-0000-000000000001') <> 4 then
        raise exception 'FAIL: an order moved stock';
    end if;
    raise notice 'PASS: the order is 2 × Riz = 35 000, stock untouched';
end $$;
-- The bell is the owner's, so only the owner can see it ring (030's RLS):
-- checking it as the customer would count somebody else's notifications.
set local "request.jwt.claim.sub" = :owner_a;
do $$
declare v_bell int;
begin
    select count(*) into v_bell from notifications
     where recipient_id = '28282828-0000-0000-0000-000000000001' and kind = 'new_order';
    if v_bell <> 1 then
        raise exception 'FAIL: the owner''s bell rang % times', v_bell;
    end if;
    raise notice 'PASS: the owner''s bell rang once';
end $$;
commit;

\echo ''
\echo '--- TEST 2: the customer sees their own orders; nobody else does ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :customer;
do $$
declare v_rows int; v_shop text; v_status text; v_lines jsonb;
begin
    select count(*) into v_rows from my_orders();
    if v_rows <> 1 then raise exception 'FAIL: the customer sees % orders', v_rows; end if;
    select shop_name, status, lines into v_shop, v_status, v_lines from my_orders() limit 1;
    if v_shop <> 'Boutique Esperance' or v_status <> 'pending' then
        raise exception 'FAIL: wrong order shown (% / %)', v_shop, v_status;
    end if;
    if jsonb_array_length(v_lines) <> 1 or (v_lines->0->>'name') <> 'Riz parfumé 25kg' then
        raise exception 'FAIL: the lines are wrong: %', v_lines;
    end if;
    raise notice 'PASS: the customer sees their pending order at Esperance with its line';
end $$;
set local "request.jwt.claim.sub" = :stranger;
do $$
declare v_rows int;
begin
    select count(*) into v_rows from my_orders();
    if v_rows <> 0 then raise exception 'FAIL: a stranger sees % orders', v_rows; end if;
    select count(*) into v_rows from orders;
    if v_rows <> 0 then raise exception 'FAIL: a stranger reads % order rows', v_rows; end if;
    select count(*) into v_rows from order_lines;
    if v_rows <> 0 then raise exception 'FAIL: a stranger reads % line rows', v_rows; end if;
    begin
        perform shop_orders('28000000-0000-0000-0000-000000000001');
        raise exception 'FAIL: a stranger read the shop''s orders';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: a stranger sees nothing — %', sqlerrm;
    end;
end $$;
set local "request.jwt.claim.sub" = :clerk_a;
do $$
declare v_rows int; v_pending int; v_name text;
begin
    select count(*) into v_rows from shop_orders('28000000-0000-0000-0000-000000000001');
    v_pending := shop_pending_orders('28000000-0000-0000-0000-000000000001');
    select customer_name into v_name from shop_orders('28000000-0000-0000-0000-000000000001') limit 1;
    if v_rows <> 1 or v_pending <> 1 or v_name <> 'Awa Client' then
        raise exception 'FAIL: the shop sees % orders, % pending, first by %', v_rows, v_pending, v_name;
    end if;
    raise notice 'PASS: the shop''s employee sees the order and one pending';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: the shop answers; the customer and a stranger cannot; lines are followed ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :customer;
do $$
declare v_id uuid;
begin
    select id into v_id from orders where customer_id = '28282828-0000-0000-0000-000000000003';
    begin
        perform decide_order(v_id, 'accepted');
        raise exception 'FAIL: the customer accepted their own order';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the customer cannot answer — %', sqlerrm;
    end;
end $$;
set local "request.jwt.claim.sub" = :clerk_a;
do $$
declare v_id uuid; v_status text; v_decided timestamptz;
begin
    select id into v_id from orders where org_id = '28000000-0000-0000-0000-000000000001';
    begin
        perform decide_order(v_id, 'picked_up');
        raise exception 'FAIL: a pending order jumped straight to picked_up';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: no skipping — %', sqlerrm;
    end;
    perform decide_order(v_id, 'accepted');
    select status, decided_at into v_status, v_decided from orders where id = v_id;
    if v_status <> 'accepted' or v_decided is null then
        raise exception 'FAIL: after accepting, status % decided %', v_status, v_decided;
    end if;
    begin
        perform decide_order(v_id, 'delivered');
        raise exception 'FAIL: a pickup was delivered';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: a pickup is picked up, not delivered — %', sqlerrm;
    end;
    perform decide_order(v_id, 'ready');
    perform decide_order(v_id, 'picked_up');
    begin
        perform decide_order(v_id, 'cancelled');
        raise exception 'FAIL: a final order was moved';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: accepted → ready → picked_up, then final — %', sqlerrm;
    end;
end $$;
set local "request.jwt.claim.sub" = :customer;
do $$
declare v_id uuid; v_bells int;
begin
    select id into v_id from orders where customer_id = '28282828-0000-0000-0000-000000000003';
    begin
        perform cancel_order(v_id);
        raise exception 'FAIL: the customer cancelled an answered order';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: too late to cancel — %', sqlerrm;
    end;
    select count(*) into v_bells from notifications
     where recipient_id = '28282828-0000-0000-0000-000000000003' and kind like 'order_%';
    if v_bells <> 3 then
        raise exception 'FAIL: the customer''s bell rang % times, expected 3', v_bells;
    end if;
    raise notice 'PASS: the customer was told each step (accepted, ready, picked up)';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the customer cancels a pending order, and the shop cannot then accept it ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :customer;
do $$
declare v_id uuid; v_status text;
begin
    v_id := place_order('commande-a-28',
        '[{"product_id":"28aaaaaa-0000-0000-0000-000000000001","quantity":1}]'::jsonb,
        'delivery', null, 'Dassasgho, en face de la pharmacie', '+22670000028');
    perform cancel_order(v_id);
    select status into v_status from orders where id = v_id;
    if v_status <> 'cancelled' then
        raise exception 'FAIL: cancel left the order %', v_status;
    end if;
    set local "request.jwt.claim.sub" = '28282828-0000-0000-0000-000000000001';
    begin
        perform decide_order(v_id, 'accepted');
        raise exception 'FAIL: a cancelled order was accepted';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: cancelled is final for the shop too — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 5: a suspended shop takes no orders and answers none ---'
-- The suspension itself is the platform's act, done here as the superuser;
-- the id crosses the role boundary in a temp table.
begin;
create temporary table t_order28 (id uuid) on commit drop;
grant insert, select on t_order28 to authenticated;
set local role authenticated;
set local "request.jwt.claim.sub" = :customer;
do $$
begin
    insert into t_order28
    select place_order('commande-a-28',
        '[{"product_id":"28aaaaaa-0000-0000-0000-000000000001","quantity":1}]'::jsonb);
end $$;
reset role;
update orgs set suspended_at = now() where id = :shop_a;
set local role authenticated;
set local "request.jwt.claim.sub" = :customer;
do $$
begin
    begin
        perform place_order('commande-a-28',
            '[{"product_id":"28aaaaaa-0000-0000-0000-000000000001","quantity":1}]'::jsonb);
        raise exception 'FAIL: a suspended shop took an order';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: suspended, no new orders — %', sqlerrm;
    end;
end $$;
set local "request.jwt.claim.sub" = :owner_a;
do $$
declare v_id uuid;
begin
    select id into v_id from t_order28;
    begin
        perform decide_order(v_id, 'accepted');
        raise exception 'FAIL: a suspended shop answered an order';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: suspended, no answers — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '=== test_orders.sql: all checks passed ==='
