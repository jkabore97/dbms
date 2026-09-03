-- ============================================================
-- test_couriers.sql — who carries a delivery, and how (056).
-- Phone block 29.
--
-- The claims: anyone signed in may apply, but only the platform approves;
-- a pending or suspended courier sees no board and takes nothing; the
-- board shows only ready, unassigned deliveries of standing shops; a
-- taken job leaves the board and a second courier cannot take it; the
-- assigned courier walks récupérée → livrée and nobody else's courier
-- can; the shop sees who carries and keeps self-delivery; a cancelled
-- taken job tells the courier; and the customer's bell rings en route
-- and at the door.
-- ============================================================
\set ON_ERROR_STOP on

\set owner_a   '''29292929-0000-0000-0000-000000000001'''
\set customer  '''29292929-0000-0000-0000-000000000002'''
\set moto1     '''29292929-0000-0000-0000-000000000003'''
\set moto2     '''29292929-0000-0000-0000-000000000004'''
\set plat      '''29292929-0000-0000-0000-000000000005'''
\set shop_a    '''29000000-0000-0000-0000-000000000001'''
\set p_riz     '''29aaaaaa-0000-0000-0000-000000000001'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner_a,  '+22629000001', '{"full_name": "Esperance"}'),
    (:customer, '+22629000002', '{"full_name": "Awa Client"}'),
    (:moto1,    '+22629000003', '{"full_name": "Moussa Moto"}'),
    (:moto2,    '+22629000004', '{"full_name": "Issouf Moto"}'),
    (:plat,     '+22629000005', '{"full_name": "Plateforme"}');
update profiles set is_platform_admin = true where id = :plat;

insert into orgs (id, name, slug, profile, default_currency, address, storefront_enabled, lat, lng) values
    (:shop_a, 'Boutique Esperance', 'livreur-a-29', 'retail', 'XOF', 'Rood Woko', true, 12.3714, -1.5197);
select seed_retail_accounts(:shop_a);

insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop_a, :owner_a, 'owner', 'org', :shop_a, 'full');

insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published, created_by) values
    (:p_riz, :shop_a, 'Riz parfumé 25kg', 17500, 15000, 4, true, true, :owner_a);

-- One delivery order, accepted and made ready by the shop: what the board
-- will carry. Kept across the suite in a temp table.
create temporary table t_job29 (id uuid);
grant select, insert on t_job29 to authenticated;

begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :customer;
do $$
begin
    insert into t_job29
    select place_order('livreur-a-29',
        '[{"product_id":"29aaaaaa-0000-0000-0000-000000000001","quantity":1}]'::jsonb,
        'delivery', null, 'Dassasgho, en face de la pharmacie', '+22670000029');
end $$;
set local "request.jwt.claim.sub" = :owner_a;
do $$
declare v_id uuid;
begin
    select id into v_id from t_job29;
    perform decide_order(v_id, 'accepted');
    perform decide_order(v_id, 'ready');
end $$;
commit;

\echo ''
\echo '--- TEST 1: registering is open; carrying is not ---'
begin;
set local role authenticated;
do $$
begin
    begin
        perform register_courier();
        raise exception 'FAIL: the street registered as a courier';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the street cannot register — %', sqlerrm;
    end;
end $$;
set local "request.jwt.claim.sub" = :moto1;
do $$
declare v_status text;
begin
    perform register_courier('+22670000101');
    v_status := courier_status();
    if v_status <> 'pending' then
        raise exception 'FAIL: a fresh registration is % not pending', v_status;
    end if;
    begin
        perform available_deliveries();
        raise exception 'FAIL: a pending courier saw the board';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: registered and pending; the board is closed — %', sqlerrm;
    end;
    begin
        perform take_delivery((select id from t_job29));
        raise exception 'FAIL: a pending courier took a delivery';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: a pending courier takes nothing — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 2: only the platform approves ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :moto1;
select register_courier('+22670000101');
set local "request.jwt.claim.sub" = :owner_a;
do $$
begin
    begin
        perform decide_courier('29292929-0000-0000-0000-000000000003', 'approved');
        raise exception 'FAIL: a shop owner approved a courier';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the owner cannot approve — %', sqlerrm;
    end;
    begin
        perform platform_couriers();
        raise exception 'FAIL: a shop owner read the courier list';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the owner cannot read the list — %', sqlerrm;
    end;
end $$;
set local "request.jwt.claim.sub" = :plat;
do $$
declare v_rows int; v_name text;
begin
    select count(*), max(name) filter (where user_id = '29292929-0000-0000-0000-000000000003')
      into v_rows, v_name
      from platform_couriers()
     where user_id = '29292929-0000-0000-0000-000000000003';
    if v_rows <> 1 or v_name <> 'Moussa Moto' then
        raise exception 'FAIL: the platform sees % rows for Moussa (%)', v_rows, v_name;
    end if;
    perform decide_courier('29292929-0000-0000-0000-000000000003', 'approved');
    begin
        perform decide_courier('29292929-0000-0000-0000-000000000099', 'approved');
        raise exception 'FAIL: a missing courier was decided';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the platform approved Moussa; a ghost was refused';
    end;
end $$;
commit;

\echo ''
\echo '--- TEST 3: the board, taking, and a second courier refused ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :plat;
select register_courier('+22670000102');
-- moto2 registers and is approved too, to try to steal the job.
reset role;
insert into couriers (user_id, phone, status) values
    ('29292929-0000-0000-0000-000000000004', '+22670000102', 'approved')
on conflict (user_id) do update set status = 'approved';
set local role authenticated;
set local "request.jwt.claim.sub" = :moto1;
do $$
declare v_id uuid; v_shop text; v_drop text; v_total numeric; v_rows int;
begin
    select count(*) into v_rows from available_deliveries() a
     where a.shop_name = 'Boutique Esperance';
    if v_rows <> 1 then
        raise exception 'FAIL: the board shows % jobs for Esperance', v_rows;
    end if;
    select a.order_id, a.shop_name, a.drop_address, a.total
      into v_id, v_shop, v_drop, v_total
      from available_deliveries() a where a.shop_name = 'Boutique Esperance';
    if v_drop <> 'Dassasgho, en face de la pharmacie' or v_total <> 17500 then
        raise exception 'FAIL: the card is wrong (% / %)', v_drop, v_total;
    end if;
    perform take_delivery(v_id);
    if (select count(*) from available_deliveries() a
         where a.shop_name = 'Boutique Esperance') <> 0 then
        raise exception 'FAIL: a taken job is still on the board';
    end if;
    raise notice 'PASS: the board showed the job with door and total; taken, it left the board';
end $$;
set local "request.jwt.claim.sub" = :moto2;
do $$
begin
    begin
        perform take_delivery((select id from t_job29));
        raise exception 'FAIL: a second courier took a taken job';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: one job, one courier — %', sqlerrm;
    end;
    begin
        perform courier_mark((select id from t_job29), 'in_transit');
        raise exception 'FAIL: somebody else''s courier moved the parcel';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: not their delivery — %', sqlerrm;
    end;
end $$;
-- Released, it returns; retaken, it stays Moussa's for the rest.
set local "request.jwt.claim.sub" = :moto1;
do $$
declare v_id uuid;
begin
    select id into v_id from t_job29;
    perform release_delivery(v_id);
    if (select count(*) from available_deliveries() a
         where a.shop_name = 'Boutique Esperance') <> 1 then
        raise exception 'FAIL: a released job did not return to the board';
    end if;
    perform take_delivery(v_id);
    raise notice 'PASS: released, it returned; retaken, it is Moussa''s';
end $$;
commit;

\echo ''
\echo '--- TEST 4: récupérée, livrée, and the bells ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :moto1;
do $$
declare v_id uuid;
begin
    select id into v_id from t_job29;
    begin
        perform courier_mark(v_id, 'delivered');
        raise exception 'FAIL: delivered before collecting';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: collect first — %', sqlerrm;
    end;
    perform courier_mark(v_id, 'in_transit');
    perform courier_mark(v_id, 'delivered');
    if (select count(*) from courier_deliveries() d
         where d.status = 'delivered') <> 1 then
        raise exception 'FAIL: the courier''s own list does not show the delivered job';
    end if;
    begin
        perform courier_mark(v_id, 'in_transit');
        raise exception 'FAIL: a delivered parcel moved again';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: ready → in_transit → delivered, then final — %', sqlerrm;
    end;
end $$;
set local "request.jwt.claim.sub" = :customer;
do $$
declare v_bells int; v_courier text; v_status text;
begin
    -- Four, not three: TEST 3 took, released and retook the job, so the
    -- customer heard "un livreur s'occupe de votre commande" twice — which
    -- is right, because it was true twice.
    select count(*) into v_bells from notifications
     where recipient_id = '29292929-0000-0000-0000-000000000002'
       and kind in ('order_courier', 'order_in_transit', 'order_delivered');
    if v_bells <> 4 then
        raise exception 'FAIL: the customer''s bell rang % times, expected 4', v_bells;
    end if;
    if (select count(distinct kind) from notifications
         where recipient_id = '29292929-0000-0000-0000-000000000002'
           and kind in ('order_courier', 'order_in_transit', 'order_delivered')) <> 3 then
        raise exception 'FAIL: a step of the road rang no bell';
    end if;
    select m.courier_name, m.status into v_courier, v_status from my_orders() m limit 1;
    if v_courier <> 'Moussa Moto' or v_status <> 'delivered' then
        raise exception 'FAIL: the customer sees courier %, status %', v_courier, v_status;
    end if;
    raise notice 'PASS: taken (twice), en route, livrée — every step rang, and the courier is named';
end $$;
set local "request.jwt.claim.sub" = :owner_a;
do $$
declare v_courier text;
begin
    select s.courier_name into v_courier
      from shop_orders('29000000-0000-0000-0000-000000000001') s limit 1;
    if v_courier <> 'Moussa Moto' then
        raise exception 'FAIL: the shop sees courier %', v_courier;
    end if;
    raise notice 'PASS: the shop sees who carried';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: a suspended courier is off the road; a cancelled job tells its courier ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :plat;
select decide_courier('29292929-0000-0000-0000-000000000003', 'suspended');
set local "request.jwt.claim.sub" = :moto1;
do $$
begin
    begin
        perform available_deliveries();
        raise exception 'FAIL: a suspended courier saw the board';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: suspended, off the road — %', sqlerrm;
    end;
end $$;
rollback;

begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :owner_a;
do $$
declare v_id uuid;
begin
    select id into v_id from t_job29;
    -- The job is still 'ready' and Moussa's (TEST 4 rolled back).
    perform decide_order(v_id, 'cancelled');
end $$;
set local "request.jwt.claim.sub" = :moto1;
do $$
declare v_told int;
begin
    select count(*) into v_told from notifications
     where recipient_id = '29292929-0000-0000-0000-000000000003'
       and kind = 'delivery_cancelled';
    if v_told <> 1 then
        raise exception 'FAIL: the courier was told % times of the cancellation', v_told;
    end if;
    raise notice 'PASS: the shop cancelled and the courier was told';
end $$;
rollback;

\echo ''
\echo '=== test_couriers.sql: all checks passed ==='
