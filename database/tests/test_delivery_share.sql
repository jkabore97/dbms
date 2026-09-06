-- ============================================================
-- test_delivery_share.sql — the platform's part of a delivery fee (067).
-- Phone block 39.
--
-- The claims: a delivery order carries a share of its fee, fixed when the
-- fee is, whole francs, at the platform's percentage; a pickup carries
-- none; changing the percentage changes the next order and never one
-- already placed; the courier's tally shows fees, share and net that add
-- up; the platform reads one row per courier for the month with the same
-- numbers, and nobody else reads it.
-- ============================================================
\set ON_ERROR_STOP on

\set plat     '''39393939-0000-0000-0000-000000000001'''
\set owner    '''39393939-0000-0000-0000-000000000002'''
\set customer '''39393939-0000-0000-0000-000000000003'''
\set moussa   '''39393939-0000-0000-0000-000000000004'''
\set other    '''39393939-0000-0000-0000-000000000005'''
\set shop     '''39000000-0000-0000-0000-000000000001'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:plat,     '+22639000001', '{"full_name": "Plateforme"}'),
    (:owner,    '+22639000002', '{"full_name": "Esperance"}'),
    (:customer, '+22639000003', '{"full_name": "Awa Client"}'),
    (:moussa,   '+22639000004', '{"full_name": "Moussa Part"}'),
    (:other,    '+22639000005', '{"full_name": "Autre Part"}');
update profiles set is_platform_admin = true where id = :plat;
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, lat, lng) values
    (:shop, 'Boutique Part', 'part-39', 'retail', 'XOF', true, 12.3714, -1.5197);
select seed_retail_accounts(:shop);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop, :owner, 'owner', 'org', :shop, 'full');
insert into couriers (user_id, phone, status) values
    (:moussa, '+22639000004', 'approved'),
    (:other,  '+22639000005', 'approved');

-- Delivered today (one at the start of today in Ouagadougou, so the day
-- holds at any hour), plus a pickup and one still on the road.
insert into orders (id, org_id, customer_id, customer_name, status, fulfilment, address,
                    total, currency, courier_id, drop_lat, drop_lng, delivery_fee, updated_at) values
    ('39aaaaaa-0000-0000-0000-000000000001', :shop, :customer, 'Awa', 'delivered', 'delivery', 'Dassasgho', 17500, 'XOF', :moussa, 12.3894, -1.5197, 800, now()),
    ('39aaaaaa-0000-0000-0000-000000000002', :shop, :customer, 'Awa', 'delivered', 'delivery', 'Dassasgho',   450, 'XOF', :moussa, 12.3894, -1.5197, 1250,
        date_trunc('day', now() at time zone 'Africa/Ouagadougou') at time zone 'Africa/Ouagadougou'),
    ('39aaaaaa-0000-0000-0000-000000000003', :shop, :customer, 'Awa', 'delivered', 'pickup',   null,          450, 'XOF', null,    null,    null,    null, now()),
    ('39aaaaaa-0000-0000-0000-000000000004', :shop, :customer, 'Awa', 'delivered', 'delivery', 'Dassasgho',   450, 'XOF', :other,  12.3894, -1.5197, 800, now()),
    ('39aaaaaa-0000-0000-0000-000000000005', :shop, :customer, 'Awa', 'in_transit', 'delivery', 'Dassasgho',  450, 'XOF', :moussa, 12.3894, -1.5197, 800, now());


\echo ''
\echo '--- TEST 1: the share is fixed with the fee, whole francs, none on a pickup ---'
do $$
declare v numeric;
begin
    select platform_fee into v from orders where id = '39aaaaaa-0000-0000-0000-000000000001';
    if v <> 80 then
        raise exception 'FAIL: 10 %% of 800 read %', v;
    end if;
    select platform_fee into v from orders where id = '39aaaaaa-0000-0000-0000-000000000002';
    if v <> 125 then
        raise exception 'FAIL: 10 %% of 1250 read % (whole francs expected)', v;
    end if;
    select platform_fee into v from orders where id = '39aaaaaa-0000-0000-0000-000000000003';
    if v <> 0 then
        raise exception 'FAIL: a pickup carries a share of %', v;
    end if;
    raise notice 'PASS: 800 -> 80, 1250 -> 125, pickup -> 0';
end $$;

\echo ''
\echo '--- TEST 2: a new percentage changes the next order, never one already placed ---'
begin;
-- As the platform admin for the setting (the function reads the claim,
-- not the role), and as the furniture for the insert: an order placed by
-- hand, the way place_order() would have.
set local "request.jwt.claim.sub" = '39393939-0000-0000-0000-000000000001';
select set_platform_setting('delivery_share_pct', '20');
do $$
declare v_old numeric; v_new numeric;
begin
    insert into orders (id, org_id, customer_id, customer_name, status, fulfilment, address,
                        total, currency, drop_lat, drop_lng, delivery_fee)
    values ('39aaaaaa-0000-0000-0000-000000000009', '39000000-0000-0000-0000-000000000001',
            '39393939-0000-0000-0000-000000000003', 'Awa', 'pending', 'delivery', 'Dassasgho',
            450, 'XOF', 12.3894, -1.5197, 800);
    select platform_fee into v_new from orders where id = '39aaaaaa-0000-0000-0000-000000000009';
    select platform_fee into v_old from orders where id = '39aaaaaa-0000-0000-0000-000000000001';
    if v_new <> 160 then
        raise exception 'FAIL: at 20 %% a new 800 F fee carries %', v_new;
    end if;
    if v_old <> 80 then
        raise exception 'FAIL: an order already placed moved to %', v_old;
    end if;
    -- A status move does not touch the share either.
    update orders set status = 'accepted' where id = '39aaaaaa-0000-0000-0000-000000000009';
    select platform_fee into v_new from orders where id = '39aaaaaa-0000-0000-0000-000000000009';
    if v_new <> 160 then
        raise exception 'FAIL: a status move changed the share to %', v_new;
    end if;
    if (plan_terms() ->> 'delivery_share_pct')::int <> 20 then
        raise exception 'FAIL: plan_terms does not say the new percentage';
    end if;
    raise notice 'PASS: the next order at 20 %%, the old one still at 10 %%, a status move changes nothing';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: the courier''s tally shows fees, share and net that add up ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '39393939-0000-0000-0000-000000000004';
do $$
declare v record;
begin
    select * into v from courier_earnings() e where e.period = 'today';
    if v.courses <> 2 or v.fees <> 2050 or v.share <> 205 or v.net <> 1845 then
        raise exception 'FAIL: today = % courses, % F, share %, net %', v.courses, v.fees, v.share, v.net;
    end if;
    raise notice 'PASS: today 2 courses, 2050 F, share 205, net 1845';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the settlement, per courier, this month; platform only ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '39393939-0000-0000-0000-000000000002';
do $$
begin
    begin
        perform platform_delivery_settlement(null);
        raise exception 'FAIL: an owner read the settlement';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '39393939-0000-0000-0000-000000000001';
do $$
declare v record; v_rows int;
begin
    select * into v from platform_delivery_settlement(null) s
     where s.courier_id = '39393939-0000-0000-0000-000000000004';
    if v.name <> 'Moussa Part' or v.courses <> 2 or v.fees <> 2050
       or v.share <> 205 or v.net <> 1845 or v.phone <> '+22639000004' then
        raise exception 'FAIL: Moussa''s row reads % / % courses / % F / share % / net %',
            v.name, v.courses, v.fees, v.share, v.net;
    end if;
    select * into v from platform_delivery_settlement(current_date) s
     where s.courier_id = '39393939-0000-0000-0000-000000000005';
    if v.courses <> 1 or v.share <> 80 then
        raise exception 'FAIL: the other courier''s row reads % courses / share %', v.courses, v.share;
    end if;
    -- Another month: neither of them.
    select count(*) into v_rows from platform_delivery_settlement((current_date - interval '2 months')::date) s
     where s.courier_id in ('39393939-0000-0000-0000-000000000004', '39393939-0000-0000-0000-000000000005');
    if v_rows <> 0 then
        raise exception 'FAIL: this month''s courses appear two months back';
    end if;
    raise notice 'PASS: the owner is refused; Moussa 2 / 2050 / 205; the other 1 / 80; nothing two months back';
end $$;
rollback;

\echo ''
\echo 'test_delivery_share.sql: all tests passed'
