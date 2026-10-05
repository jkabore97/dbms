-- ============================================================
-- test_delivery_pro.sql — delivery and Kaj's online payment are Kaj Pro;
-- a minimum may cover the first kilometres (081). Phone block 51.
--
-- The claims: a Free shop quotes no delivery, its window says it does not
-- deliver, and a delivery order for it is refused by the table itself —
-- pickup still goes through; Kaj's checkout is not ready for a Free shop
-- and a payment for its order is refused; a Pro shop quotes and delivers;
-- with included kilometres the base covers every door within them and each
-- kilometre beyond adds the per-km price; with none, it is the old formula.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''51515151-0000-0000-0000-000000000001'''
\set buyer '''51515151-0000-0000-0000-000000000002'''
\set free  '''51000000-0000-0000-0000-000000000001'''
\set pro   '''51000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22651000001', '{"full_name": "Awa"}'),
    (:buyer, '+22651000002', '{"full_name": "Cliente"}');
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, lat, lng,
                  wave_payout_number) values
    (:free, 'Boutique Libre', 'libre-51', 'retail', 'XOF', true, 12.3714, -1.5197, '+22670510001'),
    (:pro,  'Boutique Pro',   'pro-51',   'retail', 'XOF', true, 12.3714, -1.5197, '+22670510002');
update orgs set plan = 'pro' where id = :pro;
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:free, :owner, 'owner', 'org', :free, 'full'),
    (:pro,  :owner, 'owner', 'org', :pro,  'full');

\echo ''
\echo '--- TEST 1: a Free shop does not deliver, and the table refuses it ---'
do $$
declare st jsonb;
begin
    if delivery_fee('51000000-0000-0000-0000-000000000001', 12.39, -1.5197) is not null then
        raise exception 'FAIL: a Free shop quoted a delivery';
    end if;
    select style into st from storefront('libre-51');
    if (st ->> 'delivers')::boolean then
        raise exception 'FAIL: a Free window says it delivers';
    end if;
    begin
        insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency)
        values ('51000000-0000-0000-0000-000000000001', '51515151-0000-0000-0000-000000000002',
                'Cliente', 'pending', 'delivery', 1000, 'XOF');
        raise exception 'FAIL: a Free shop took a delivery order';
    exception when others then
        if sqlerrm not like 'Kaj Pro : la livraison%' then raise; end if;
    end;
    insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency)
    values ('51000000-0000-0000-0000-000000000001', '51515151-0000-0000-0000-000000000002',
            'Cliente', 'pending', 'pickup', 1000, 'XOF');
    raise notice 'PASS: no quote, the window says so, delivery refused, pickup taken';
end $$;

\echo ''
\echo '--- TEST 2: Kaj''s online payment is Pro too ---'
do $$ begin
    if (wave_terms('51000000-0000-0000-0000-000000000001') ->> 'shop_ready')::boolean then
        raise exception 'FAIL: a Free shop is ready for Kaj''s checkout';
    end if;
    if not (wave_terms('51000000-0000-0000-0000-000000000002') ->> 'shop_ready')::boolean then
        raise exception 'FAIL: a Pro shop with a payout number is not ready';
    end if;
    begin
        insert into wave_payments (kind, org_id, amount) values
            ('order', '51000000-0000-0000-0000-000000000001', 1000);
        raise exception 'FAIL: a Free shop''s order was paid through Kaj';
    exception when others then
        if sqlerrm not like 'Kaj Pro : le paiement en ligne%' then raise; end if;
    end;
    if not (plan_terms() -> 'pro_features') ? 'delivery'
       or not (plan_terms() -> 'pro_features') ? 'online_payment' then
        raise exception 'FAIL: delivery or online payment is not on the Pro list';
    end if;
    raise notice 'PASS: not ready, refused, and both on the Pro list';
end $$;

\echo ''
\echo '--- TEST 3: a Pro shop delivers; a minimum covers the first kilometres ---'
update orgs set delivery_base = 1000, delivery_per_km = 200
 where id = '51000000-0000-0000-0000-000000000002';
do $$
declare
    near_km numeric := distance_km(12.3714, -1.5197, 12.3894, -1.5197);
    far_km  numeric := distance_km(12.3714, -1.5197, 12.4164, -1.5197);
    st jsonb;
begin
    select style into st from storefront('pro-51');
    if not (st ->> 'delivers')::boolean then
        raise exception 'FAIL: a pinned Pro window does not say it delivers';
    end if;
    -- No included kilometres: the old formula, from the shop's door.
    if delivery_fee('51000000-0000-0000-0000-000000000002', 12.3894, -1.5197)
       <> round((1000 + 200 * near_km) / 25) * 25 then
        raise exception 'FAIL: the per-km fee changed';
    end if;
    update orgs set delivery_included_km = 3
     where id = '51000000-0000-0000-0000-000000000002';
    if delivery_fee('51000000-0000-0000-0000-000000000002', 12.3894, -1.5197) <> 1000 then
        raise exception 'FAIL: a door within 3 km is not the minimum (%, % km)',
            delivery_fee('51000000-0000-0000-0000-000000000002', 12.3894, -1.5197), near_km;
    end if;
    if delivery_fee('51000000-0000-0000-0000-000000000002', 12.4164, -1.5197)
       <> round((1000 + 200 * (far_km - 3)) / 25) * 25 then
        raise exception 'FAIL: beyond 3 km each kilometre is not added';
    end if;
    insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency)
    values ('51000000-0000-0000-0000-000000000002', '51515151-0000-0000-0000-000000000002',
            'Cliente', 'pending', 'delivery', 1000, 'XOF');
    raise notice 'PASS: % km costs the minimum, % km adds % km of per-km; a Pro shop takes it',
        round(near_km, 1), round(far_km, 1), round(far_km - 3, 1);
end $$;

\echo ''
\echo '--- TEST 4: the shop sets its included kilometres; the platform has a default ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '51515151-0000-0000-0000-000000000001';
select set_delivery_included_km('51000000-0000-0000-0000-000000000002', 2.5);
do $$ begin
    begin
        perform set_delivery_included_km('51000000-0000-0000-0000-000000000002', 80);
        raise exception 'FAIL: 80 included kilometres were taken';
    exception when others then
        if sqlerrm not like 'Les kilomètres inclus%' then raise; end if;
    end;
    if (select delivery_included_km from orgs where id = '51000000-0000-0000-0000-000000000002') <> 2.5 then
        raise exception 'FAIL: the shop''s included kilometres were not kept';
    end if;
    raise notice 'PASS: kept, and bounded';
end $$;
rollback;
do $$ begin
    if (select (value #>> '{}')::numeric from platform_settings where key = 'delivery_included_km') <> 0 then
        raise exception 'FAIL: the platform default is not 0 (the old formula)';
    end if;
end $$;

\echo ''
\echo 'test_delivery_pro: all passed'
