-- ============================================================
-- test_delivery_runs.sql — a delivery that runs itself (073).
-- Phone block 45.
--
-- The claims: every status is a dated event; a delivery is closed at the
-- door with the shopper's code and not without it; a door that does not
-- open cancels with its reason; the shop can carry a stuck order itself,
-- with no platform share; the cash a courier holds is owed until the shop
-- says so; a shop's own couriers have its orders first, for ten minutes;
-- the board is nearest first; tracking shows the shopper their code and
-- nobody else's order.
-- ============================================================
\set ON_ERROR_STOP on

\set owner   '''45454545-0000-0000-0000-000000000001'''
\set buyer   '''45454545-0000-0000-0000-000000000002'''
\set moussa  '''45454545-0000-0000-0000-000000000003'''
\set awa     '''45454545-0000-0000-0000-000000000004'''
\set nosy    '''45454545-0000-0000-0000-000000000005'''
\set shop    '''45000000-0000-0000-0000-000000000001'''
\set far     '''45000000-0000-0000-0000-000000000002'''
\set o1      '''45aaaaaa-0000-0000-0000-000000000001'''
\set o2      '''45aaaaaa-0000-0000-0000-000000000002'''
\set o3      '''45aaaaaa-0000-0000-0000-000000000003'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,  '+22645000001', '{"full_name": "Propriétaire"}'),
    (:buyer,  '+22645000002', '{"full_name": "Cliente"}'),
    (:moussa, '+22645000003', '{"full_name": "Moussa"}'),
    (:awa,    '+22645000004', '{"full_name": "Awa"}'),
    (:nosy,   '+22645000005', '{"full_name": "Curieux"}');
insert into couriers (user_id, phone, status) values
    (:moussa, '+226 45 00 00 03', 'approved'),
    (:awa,    '+22645000004',     'approved');
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, lat, lng, phone) values
    (:shop, 'Boutique Course', 'course-45', 'retail', 'XOF', true, 12.3714, -1.5197, '+22670000045'),
    (:far,  'Boutique Loin',   'loin-45',   'retail', 'XOF', true, 12.4500, -1.6000, null);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop, :owner, 'owner', 'org', :shop, 'full'),
    (:far,  :owner, 'owner', 'org', :far,  'full');
insert into orders (id, org_id, customer_id, customer_name, status, fulfilment, address,
                    total, currency, drop_lat, drop_lng, delivery_fee) values
    (:o1, :shop, :buyer, 'Cliente', 'pending', 'delivery', 'Dassasgho', 5000, 'XOF', 12.38, -1.51, 800),
    (:o2, :far,  :buyer, 'Cliente', 'pending', 'delivery', 'Tampouy',   3000, 'XOF', 12.40, -1.55, 900),
    (:o3, :shop, :buyer, 'Cliente', 'pending', 'pickup',   null,        1000, 'XOF', null, null, null);


\echo ''
\echo '--- TEST 1: a code at birth for deliveries; every status dated ---'
begin;
do $$ begin
    if (select handover_code from orders where id = '45aaaaaa-0000-0000-0000-000000000001') !~ '^\d{4}$' then
        raise exception 'FAIL: a delivery has no four-digit code';
    end if;
    if (select handover_code from orders where id = '45aaaaaa-0000-0000-0000-000000000003') is not null then
        raise exception 'FAIL: a pickup got a code';
    end if;
end $$;
update orders set status = 'accepted' where id = :o1;
update orders set status = 'ready' where id = :o1;
do $$ begin
    if (select string_agg(status, '>' order by id) from order_events
         where order_id = '45aaaaaa-0000-0000-0000-000000000001') <> 'pending>accepted>ready' then
        raise exception 'FAIL: the timeline is %', (select string_agg(status, '>' order by id)
            from order_events where order_id = '45aaaaaa-0000-0000-0000-000000000001');
    end if;
    raise notice 'PASS: four-digit code on deliveries only; pending > accepted > ready dated';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: the door needs the code; a wrong one is refused ---'
begin;
update orders set status = 'in_transit', courier_id = :moussa where id = :o1;
set local role authenticated;
set local "request.jwt.claim.sub" = '45454545-0000-0000-0000-000000000003';
do $$
declare v_code text;
begin
    begin
        perform courier_mark('45aaaaaa-0000-0000-0000-000000000001', 'delivered');
        raise exception 'FAIL: delivered without the code';
    exception when others then
        if sqlerrm not like 'Demandez au client%' then raise; end if;
    end;
    begin
        perform courier_deliver('45aaaaaa-0000-0000-0000-000000000001', 'xxxx');
        raise exception 'FAIL: a wrong code closed the delivery';
    exception when others then
        if sqlerrm not like 'Code incorrect%' then raise; end if;
    end;
end $$;
reset role;
create temp table t_code on commit drop as
select handover_code as c from orders where id = :o1;
grant select on t_code to authenticated;
set local role authenticated;
set local "request.jwt.claim.sub" = '45454545-0000-0000-0000-000000000003';
select courier_deliver(:o1, (select c from t_code));
do $$ begin
    if (select status from orders where id = '45aaaaaa-0000-0000-0000-000000000001') <> 'delivered' then
        raise exception 'FAIL: the right code did not close the delivery';
    end if;
    raise notice 'PASS: no code, wrong code refused; the right code delivers';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: a door that does not open cancels with its reason ---'
begin;
update orders set status = 'in_transit', courier_id = :moussa where id = :o1;
set local role authenticated;
set local "request.jwt.claim.sub" = '45454545-0000-0000-0000-000000000003';
select courier_fail(:o1, 'absent');
do $$ begin
    if (select status || ':' || outcome from orders
         where id = '45aaaaaa-0000-0000-0000-000000000001') <> 'cancelled:absent' then
        raise exception 'FAIL: the failed delivery is not cancelled with its reason';
    end if;
    raise notice 'PASS: failed delivery cancelled, reason kept';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the shop carries a stuck order itself, with no share ---'
begin;
update orders set status = 'ready' where id = :o1;
set local role authenticated;
set local "request.jwt.claim.sub" = '45454545-0000-0000-0000-000000000001';
select shop_deliver_self(:o1);
select decide_order(:o1, 'delivered');
do $$ begin
    if (select status || ':' || self_delivered || ':' || platform_fee::int from orders
         where id = '45aaaaaa-0000-0000-0000-000000000001') <> 'delivered:true:0' then
        raise exception 'FAIL: self-delivery is %', (select status || ':' || self_delivered || ':' || platform_fee
            from orders where id = '45aaaaaa-0000-0000-0000-000000000001');
    end if;
    raise notice 'PASS: the shop delivered it itself, no platform share';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: the cash is owed until the shop says it was handed over ---'
begin;
update orders set status = 'delivered', courier_id = :moussa where id = :o1;
set local role authenticated;
set local "request.jwt.claim.sub" = '45454545-0000-0000-0000-000000000003';
do $$ begin
    if (select total from courier_cash() where order_id = '45aaaaaa-0000-0000-0000-000000000001') <> 5000 then
        raise exception 'FAIL: the courier does not hold the 5000';
    end if;
end $$;
set local "request.jwt.claim.sub" = '45454545-0000-0000-0000-000000000001';
do $$ begin
    if (select courier_name from shop_cash_owed('45000000-0000-0000-0000-000000000001')) <> 'Moussa' then
        raise exception 'FAIL: the shop does not see Moussa owes it';
    end if;
end $$;
select confirm_cash_received(:o1);
do $$ begin
    if exists (select 1 from shop_cash_owed('45000000-0000-0000-0000-000000000001')) then
        raise exception 'FAIL: still owed after the shop confirmed';
    end if;
    raise notice 'PASS: held by the courier, owed to the shop, cleared by the shop';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: own couriers first for ten minutes; the board nearest first ---'
begin;
update orders set status = 'ready' where id in (:o1, :o2);
set local role authenticated;
set local "request.jwt.claim.sub" = '45454545-0000-0000-0000-000000000001';
do $$ begin
    if add_org_courier('45000000-0000-0000-0000-000000000001', '70 45 00 00 03') is distinct from 'Moussa' then
        raise exception 'FAIL: the shop could not add Moussa by phone';
    end if;
end $$;
set local "request.jwt.claim.sub" = '45454545-0000-0000-0000-000000000004';
do $$ begin
    if exists (select 1 from delivery_board() where order_id = '45aaaaaa-0000-0000-0000-000000000001') then
        raise exception 'FAIL: another courier sees the shop''s order in its ten minutes';
    end if;
    begin
        perform take_delivery('45aaaaaa-0000-0000-0000-000000000001');
        raise exception 'FAIL: another courier took it in the ten minutes';
    exception when others then
        if sqlerrm not like 'Cette boutique a ses livreurs%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '45454545-0000-0000-0000-000000000003';
do $$ begin
    if (select order_id from delivery_board(12.45, -1.60) limit 1) <> '45aaaaaa-0000-0000-0000-000000000001' then
        raise exception 'FAIL: the shop''s own order is not first for its courier';
    end if;
end $$;
reset role;
delete from org_couriers;
set local role authenticated;
set local "request.jwt.claim.sub" = '45454545-0000-0000-0000-000000000004';
do $$ begin
    -- Standing at the far shop: the far shop's order first.
    if (select order_id from delivery_board(12.45, -1.60) limit 1) <> '45aaaaaa-0000-0000-0000-000000000002' then
        raise exception 'FAIL: the board is not nearest first';
    end if;
    raise notice 'PASS: own couriers first and alone for ten minutes; board nearest first';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: tracking shows the shopper their code, and nobody else anything ---'
begin;
update orders set status = 'in_transit', courier_id = :moussa where id = :o1;
set local role authenticated;
set local "request.jwt.claim.sub" = '45454545-0000-0000-0000-000000000002';
do $$
declare t jsonb := order_tracking('45aaaaaa-0000-0000-0000-000000000001');
begin
    if t ->> 'code' is null or t #>> '{courier,name}' <> 'Moussa'
       or t #>> '{courier,phone}' is null or t #>> '{shop,phone}' <> '+22670000045' then
        raise exception 'FAIL: the shopper''s page is %', t;
    end if;
end $$;
set local "request.jwt.claim.sub" = '45454545-0000-0000-0000-000000000001';
do $$ begin
    if order_tracking('45aaaaaa-0000-0000-0000-000000000001') ->> 'code' is not null then
        raise exception 'FAIL: the shop reads the shopper''s code';
    end if;
end $$;
set local "request.jwt.claim.sub" = '45454545-0000-0000-0000-000000000005';
do $$ begin
    if order_tracking('45aaaaaa-0000-0000-0000-000000000001') is not null then
        raise exception 'FAIL: a stranger tracks the order';
    end if;
    raise notice 'PASS: code for the shopper only; stranger gets nothing';
end $$;
rollback;

\echo ''
\echo 'test_delivery_runs: all passed'
