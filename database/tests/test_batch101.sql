-- ============================================================
-- test_batch101.sql — stock that never goes below zero, vitrine orders
-- that move it, a farm's analyses behind the Pro line, and a business
-- asked for without a word about the person (101). Phone block 35.
--
-- The claims: the till, a credit sale, a typed name, a production's
-- ingredient, a production corrected down, a delivery reversed and a
-- direct write are each refused below zero, in French, naming the article
-- and what is left; a service sells freely; a count already negative is
-- left alone, may rise, never fall. A farm's feed is refused past what it
-- has, whoever records it. A vitrine order cannot ask for « Épuisé » nor
-- more than is left (lines added up); accepting it takes the stock, once;
-- refusing takes nothing; cancelling an accepted one — by the business or
-- by any other path — gives back exactly what it took, once; a service and
-- a pre-order move nothing; picking up moves nothing more. The street
-- reads how many it may put in a basket. farm_analytics answers a farm with
-- the tool (Pro or unlocked), with its month and the last, what sold, what
-- was spent, its flocks and feed; refused without the tool, to an
-- association, to a reader without full visibility, and closed to the
-- street. apply_for_org takes the person from the profile and the account.
-- A finished order is its own sale: once, its lines, cash or Wave booked to
-- 'Ventes', the shelf untouched (an order from before 101 takes then, as
-- far as the shelf goes); staff cannot forge one; finished is never
-- cancelled; the farm dates it by its finish and counts it once.
-- ============================================================
\set ON_ERROR_STOP on
-- The owner's numbers: earlier suites change them for their own fixtures.
update platform_settings set value = '1' where key = 'vitrine_min_items';
update platform_settings set value = '1' where key = 'path_gates_open';
update platform_settings set value = '["payroll","team_access","analytics","accounting","currencies","tontines"]'
 where key = 'pro_features';

\set boss    '''35353535-0000-0000-0000-000000000001'''
\set farmer  '''35353535-0000-0000-0000-000000000002'''
\set buyer   '''35353535-0000-0000-0000-000000000003'''
\set hand    '''35353535-0000-0000-0000-000000000004'''
\set treas   '''35353535-0000-0000-0000-000000000005'''
\set asker   '''35353535-0000-0000-0000-000000000006'''
\set shop    '''35000000-0000-0000-0000-000000000001'''
\set farm    '''35000000-0000-0000-0000-000000000002'''
\set assoc   '''35000000-0000-0000-0000-000000000003'''
\set profarm '''35000000-0000-0000-0000-000000000004'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
-- Earlier suites re-apply older migrations over 101's functions (099's
-- place_order, 017's apply_for_org), and 063 re-grants every definer
-- function: 101 again, so what follows tests its own definitions and grants.
\i database/migrations/101_stock_farm_analytics.sql

insert into auth.users (id, phone, email, raw_user_meta_data) values
    (:boss,   '+22635000001', null,                '{"full_name": "Patronne"}'),
    (:farmer, '+22635000002', null,                '{"full_name": "Fermier"}'),
    (:buyer,  '+22635000003', null,                '{"full_name": "Cliente"}'),
    (:hand,   '+22635000004', null,                '{"full_name": "Ouvrier"}'),
    (:treas,  '+22635000005', null,                '{"full_name": "Trésorière"}'),
    (:asker,  '+22635000006', 'asker35@example.com', '{"full_name": "Demandeuse"}');
update profiles set first_name = 'Aminata', last_name = 'Ouédraogo', phone = '+22635000066'
 where id = :asker;
insert into orgs (id, name, slug, profile, default_currency, plan, progress_since,
                  storefront_enabled) values
    (:shop,    'Boutique 35', 'boutique-35', 'retail',      'XOF', 'free', null, true),
    (:farm,    'Ferme 35',    'ferme-35',    'farm',        'XOF', 'free', null, true),
    (:assoc,   'Entraide 35', 'entraide-35', 'association', 'XOF', 'pro',  null, false),
    (:profarm, 'Ferme Pro 35','ferme-pro-35','farm',        'XOF', 'pro',  null, false);
select seed_retail_accounts(:shop);
select seed_farm_accounts(:farm);
select seed_farm_accounts(:profarm);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,    :boss,   'owner',    'org', :shop,    'full'),
    (:farm,    :farmer, 'owner',    'org', :farm,    'full'),
    (:farm,    :hand,   'employee', 'org', :farm,    'summary'),
    (:assoc,   :treas,  'owner',    'org', :assoc,   'full'),
    (:profarm, :farmer, 'owner',    'org', :profarm, 'full');

insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published) values
    ('35aaaaaa-0000-0000-0000-000000000001', :shop, 'Savon',  500, 300, 3, true, true),
    ('35aaaaaa-0000-0000-0000-000000000002', :shop, 'Farine', 200, 100, 4, true, false),
    ('35aaaaaa-0000-0000-0000-000000000003', :shop, 'Huile',  900, 600, 0, true, true),
    ('35aaaaaa-0000-0000-0000-000000000004', :farm, 'Œufs',  2500,   0, 10, true, true);
insert into products (id, org_id, name, sale_price, is_service, is_active, is_published) values
    ('35aaaaaa-0000-0000-0000-000000000005', :shop, 'Coiffure', 2000, true, true, true);
insert into products (id, org_id, name, sale_price, quantity, available_from, is_active, is_published) values
    ('35aaaaaa-0000-0000-0000-000000000006', :farm, 'Poulets', 3500, 0, current_date + 20, true, true);

\echo ''
\echo '--- TEST 1: the till, a credit sale, a typed name and a direct write stop at zero, in French ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000001';
do $$
declare
    v_org  uuid := '35000000-0000-0000-0000-000000000001';
    v_soap uuid := '35aaaaaa-0000-0000-0000-000000000001';
begin
    begin
        perform record_sale(v_org, jsonb_build_array(
            jsonb_build_object('product_id', v_soap, 'quantity', 4, 'unit_price', 500)));
        raise exception 'FAIL: the till sold 4 of 3';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Il ne reste que 3 Savon' then raise; end if;
    end;
    -- Two lines of one article add up.
    begin
        perform record_sale(v_org, jsonb_build_array(
            jsonb_build_object('product_id', v_soap, 'quantity', 2, 'unit_price', 500),
            jsonb_build_object('product_id', v_soap, 'quantity', 2, 'unit_price', 500)));
        raise exception 'FAIL: two lines sold 4 of 3';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Il ne reste que 1 Savon' then raise; end if;
    end;
    if (select quantity from products where id = v_soap) <> 3
       or exists (select 1 from sales where org_id = v_org) then
        raise exception 'FAIL: a refused sale left a trace';
    end if;
    perform record_sale(v_org, jsonb_build_array(
        jsonb_build_object('product_id', v_soap, 'quantity', 3, 'unit_price', 500)));
    if (select quantity from products where id = v_soap) <> 0 then
        raise exception 'FAIL: selling the last three did not empty the shelf';
    end if;
    begin
        perform record_sale(v_org, jsonb_build_array(
            jsonb_build_object('product_id', v_soap, 'quantity', 1, 'unit_price', 500)),
            p_method => 'credit', p_customer_name => 'Awa');
        raise exception 'FAIL: a credit sale took an empty shelf below zero';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Plus de Savon en stock' then raise; end if;
    end;
    -- A name typed at the till, never received: nothing to sell.
    begin
        perform record_sale(v_org, jsonb_build_array(
            jsonb_build_object('name', 'Bougie', 'quantity', 1, 'unit_price', 100)));
        raise exception 'FAIL: a typed name sold what was never received';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Plus de Bougie en stock' then raise; end if;
    end;
    -- A service has no stock and always sells.
    perform record_sale(v_org, jsonb_build_array(
        jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000005',
                           'quantity', 2, 'unit_price', 2000)));
    -- Straight through the API, under RLS: still refused.
    begin
        update products set quantity = -1 where id = '35aaaaaa-0000-0000-0000-000000000002';
        raise exception 'FAIL: a direct write set a count below zero';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Il ne reste que 4 Farine' then raise; end if;
    end;
    raise notice 'PASS: till, two lines, credit, a typed name and a direct write refused below zero; a service sells';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: a count already below zero is left alone, may rise, never fall ---'
alter table products disable trigger stock_not_below_zero;
update products set quantity = -5 where id = '35aaaaaa-0000-0000-0000-000000000002';
alter table products enable trigger stock_not_below_zero;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000001';
do $$
declare
    v_org   uuid := '35000000-0000-0000-0000-000000000001';
    v_flour uuid := '35aaaaaa-0000-0000-0000-000000000002';
begin
    begin
        perform record_sale(v_org, jsonb_build_array(
            jsonb_build_object('product_id', v_flour, 'quantity', 1, 'unit_price', 200)));
        raise exception 'FAIL: a negative count fell further';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Plus de Farine en stock' then raise; end if;
    end;
    perform receive_products(v_org, v_flour, 3, p_unit_cost => 100);
    if (select quantity from products where id = v_flour) <> -2 then
        raise exception 'FAIL: a delivery onto a negative count did not land';
    end if;
    -- An unrelated edit of the row (its price) is no decrease.
    update products set sale_price = 250 where id = v_flour;
    raise notice 'PASS: an old negative stays, rises with a delivery, cannot fall';
end $$;
rollback;
update products set quantity = 4 where id = '35aaaaaa-0000-0000-0000-000000000002';

\echo ''
\echo '--- TEST 3: a production, its correction and a reversed delivery stop at zero ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000001';
do $$
declare
    v_org   uuid := '35000000-0000-0000-0000-000000000001';
    v_flour uuid := '35aaaaaa-0000-0000-0000-000000000002';
    v_run   uuid;
    v_cake  uuid;
    v_rec   uuid;
begin
    begin
        perform record_production(v_org, 10,
            jsonb_build_array(jsonb_build_object('product_id', v_flour, 'quantity', 5)),
            p_product_name => 'Gâteau 35');
        raise exception 'FAIL: a production used 5 of 4';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Il ne reste que 4 Farine' then raise; end if;
    end;
    v_run := record_production(v_org, 10,
        jsonb_build_array(jsonb_build_object('product_id', v_flour, 'quantity', 4)),
        p_product_name => 'Gâteau 35');
    select product_id into v_cake from production_runs where id = v_run;
    perform record_sale(v_org, jsonb_build_array(
        jsonb_build_object('product_id', v_cake, 'quantity', 8, 'unit_price', 300)));
    -- 10 made, 8 sold: correcting the batch down to 5 would leave -3.
    begin
        perform update_production_run(v_run, p_quantity => 5);
        raise exception 'FAIL: a correction took the cakes below zero';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Il ne reste que 2 Gâteau 35' then raise; end if;
    end;
    -- A delivery already sold cannot be reversed past the shelf.
    perform receive_products(v_org, v_flour, 6, p_unit_cost => 100);
    select id into v_rec from stock_receipts where product_id = v_flour
     order by received_at desc limit 1;
    perform record_production(v_org, 2,
        jsonb_build_array(jsonb_build_object('product_id', v_flour, 'quantity', 4)),
        p_product_name => 'Gâteau 35');
    begin
        perform reverse_receipt(v_rec, 'Erreur');
        raise exception 'FAIL: a reversal took the flour below zero';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Il ne reste que 2 Farine' then raise; end if;
    end;
    raise notice 'PASS: a production, its correction and a reversed delivery refused below zero';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: a farm''s feed stops at zero, whoever records it ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000002';
select receive_stock('35000000-0000-0000-0000-000000000002', 'Aliment 35', 10);
select move_stock('35000000-0000-0000-0000-000000000002', 'Aliment 35', 4);
-- A worker without full visibility sees no movement under 009's policy;
-- the rule still counts them all.
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000004';
do $$
declare v_org uuid := '35000000-0000-0000-0000-000000000002';
begin
    begin
        perform move_stock(v_org, 'Aliment 35', 7);
        raise exception 'FAIL: 7 sacks used of 6';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Il ne reste que 6 Aliment 35' then raise; end if;
    end;
    begin
        perform move_stock(v_org, 'Aliment 35', -7, p_kind => 'adjusted');
        raise exception 'FAIL: a count took the feed below zero';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Il ne reste que 6 Aliment 35' then raise; end if;
    end;
    perform move_stock(v_org, 'Aliment 35', 6, p_kind => 'wasted');
    begin
        insert into stock_movements (org_id, item_id, kind, quantity, created_by)
        select v_org, id, 'consumed', 1, '35353535-0000-0000-0000-000000000004'
          from items where org_id = v_org and name = 'Aliment 35';
        raise exception 'FAIL: a direct insert used an empty sack';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Plus d''Aliment 35 en stock' then raise; end if;
    end;
    -- A count that finds more is always welcome.
    perform move_stock(v_org, 'Aliment 35', 2, p_kind => 'adjusted');
    raise notice 'PASS: feed used, lost or counted down never below zero; counted up always';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: the vitrine cannot order « Épuisé » nor more than is left; it reads what is left ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000003';
do $$
declare r record;
begin
    begin
        perform place_order('boutique-35', jsonb_build_array(
            jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000001', 'quantity', 4)));
        raise exception 'FAIL: the vitrine took an order for 4 of 3';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Il ne reste que 3 Savon' then raise; end if;
    end;
    begin
        perform place_order('boutique-35', jsonb_build_array(
            jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000001', 'quantity', 2),
            jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000001', 'quantity', 2)));
        raise exception 'FAIL: two lines ordered 4 of 3';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Il ne reste que 3 Savon' then raise; end if;
    end;
    begin
        perform place_order('boutique-35', jsonb_build_array(
            jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000003', 'quantity', 1)));
        raise exception 'FAIL: the vitrine took an order for « Épuisé »';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Plus d''Huile en stock' then raise; end if;
    end;
    -- A pre-order is ordered before there is anything to count (083).
    perform place_order('ferme-35', jsonb_build_array(
        jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000006', 'quantity', 5)));
    for r in select * from storefront_stock('boutique-35') loop
        if (r.id = '35aaaaaa-0000-0000-0000-000000000001' and r.stock_left <> 3)
           or (r.id = '35aaaaaa-0000-0000-0000-000000000003' and r.stock_left <> 0)
           or (r.id = '35aaaaaa-0000-0000-0000-000000000005' and r.stock_left is not null) then
            raise exception 'FAIL: the street reads % for %', r.stock_left, r.id;
        end if;
    end loop;
    if (select stock_left from storefront_stock('ferme-35')
         where id = '35aaaaaa-0000-0000-0000-000000000006') is not null then
        raise exception 'FAIL: a pre-order is capped';
    end if;
    raise notice 'PASS: « Épuisé » and past the shelf refused (lines added up); a pre-order ordered; the street reads what is left';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: accepting takes the stock once; refusing nothing; cancelling gives it back once ---'
create temporary table t35 (which text primary key, id uuid);
grant all on t35 to authenticated;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000003';
insert into t35 values ('a', place_order('boutique-35', jsonb_build_array(
    jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000001', 'quantity', 2),
    jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000005', 'quantity', 1)),
    p_note => 'Samedi 10h'));
insert into t35 values ('b', place_order('boutique-35', jsonb_build_array(
    jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000001', 'quantity', 1))));
insert into t35 values ('c', place_order('boutique-35', jsonb_build_array(
    jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000001', 'quantity', 3))));
insert into t35 values ('eggs', place_order('ferme-35', jsonb_build_array(
    jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000004', 'quantity', 4))));
insert into t35 values ('pre', place_order('ferme-35', jsonb_build_array(
    jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000006', 'quantity', 5))));
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000001';
do $$
declare
    v_soap uuid := '35aaaaaa-0000-0000-0000-000000000001';
    v_a uuid := (select id from t35 where which = 'a');
    v_b uuid := (select id from t35 where which = 'b');
    v_c uuid := (select id from t35 where which = 'c');
begin
    if (select quantity from products where id = v_soap) <> 3 then
        raise exception 'FAIL: a pending order moved the shelf';
    end if;
    perform decide_order(v_a, 'accepted');
    if (select quantity from products where id = v_soap) <> 1 then
        raise exception 'FAIL: accepting 2 left %', (select quantity from products where id = v_soap);
    end if;
    if (select count(*) from order_stock_moves where order_id = v_a) <> 1
       or (select quantity from order_stock_moves where order_id = v_a and direction = 'out') <> 2 then
        raise exception 'FAIL: the move is not recorded against the order (the service moved?)';
    end if;
    -- Accepting again is refused by the order's own path; nothing moves twice.
    begin
        perform decide_order(v_a, 'accepted');
        raise exception 'FAIL: an order was accepted twice';
    exception when raise_exception then null;
    end;
    -- 3 asked, 1 left: the acceptance is refused and the order stays pending.
    begin
        perform decide_order(v_c, 'accepted');
        raise exception 'FAIL: an order took more than the shelf';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Il ne reste que 1 Savon' then raise; end if;
    end;
    if (select status from orders where id = v_c) <> 'pending' then
        raise exception 'FAIL: a refused acceptance changed the order';
    end if;
    perform decide_order(v_c, 'refused');
    if (select quantity from products where id = v_soap) <> 1
       or exists (select 1 from order_stock_moves where order_id = v_c) then
        raise exception 'FAIL: refusing a pending order moved stock';
    end if;
    -- Cancelling the accepted one gives back its two, once.
    perform decide_order(v_a, 'cancelled');
    if (select quantity from products where id = v_soap) <> 3
       or (select quantity from order_stock_moves where order_id = v_a and direction = 'back') <> 2 then
        raise exception 'FAIL: cancelling did not give back what was taken';
    end if;
    -- Accepted, made ready, picked up: one take, nothing more.
    perform decide_order(v_b, 'accepted');
    perform decide_order(v_b, 'ready');
    perform decide_order(v_b, 'picked_up');
    if (select quantity from products where id = v_soap) <> 2 then
        raise exception 'FAIL: a picked-up order moved the shelf again';
    end if;
    raise notice 'PASS: accepted takes once, refused nothing, cancelled gives back once, picked up nothing more';
end $$;
commit;
-- Any other path to « cancelled » (a courier's failed delivery, 073) gives
-- back the same way; a second cancel-shaped write gives nothing more.
set role authenticated;
set "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000002';
select decide_order((select id from t35 where which = 'eggs'), 'accepted');
select decide_order((select id from t35 where which = 'pre'), 'accepted');
reset role;
reset "request.jwt.claim.sub";
do $$
declare v_eggs uuid := '35aaaaaa-0000-0000-0000-000000000004';
begin
    if (select quantity from products where id = v_eggs) <> 6 then
        raise exception 'FAIL: a farm''s accepted order left % trays', (select quantity from products where id = v_eggs);
    end if;
    if (select quantity from products where id = '35aaaaaa-0000-0000-0000-000000000006') <> 0
       or exists (select 1 from order_stock_moves m join t35 on t35.id = m.order_id where which = 'pre') then
        raise exception 'FAIL: a pre-order moved stock';
    end if;
    update orders set status = 'in_transit' where id = (select id from t35 where which = 'eggs');
    update orders set status = 'cancelled' where id = (select id from t35 where which = 'eggs');
    update orders set status = 'cancelled' where id = (select id from t35 where which = 'eggs');
    if (select quantity from products where id = v_eggs) <> 10 then
        raise exception 'FAIL: a failed delivery gave back % trays', (select quantity from products where id = v_eggs);
    end if;
    raise notice 'PASS: a farm''s order the same; a pre-order moves nothing; any path to cancelled gives back once';
end $$;

\echo ''
\echo '--- TEST 7: a farm''s analyses, behind the Pro line ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000002';
do $$
declare
    v_org uuid := '35000000-0000-0000-0000-000000000002';
    v_flock uuid;
begin
    perform record_farm_sale(v_org, 5000, 'Œufs du marché');
    perform record_entry(v_org, 2000, 'out', 'Aliment', p_category => 'Aliment');
    perform record_entry(v_org, 3000, 'in', 'Vente ancienne', p_category => 'Ventes d''œufs',
                         p_occurred_at => date_trunc('month', now()) - interval '10 days');
    v_flock := open_flock(v_org, 'B-35', 100);
    perform record_flock_event(v_flock, 'mortality', 3);
    perform record_eggs(v_org, 80, v_flock);
    perform receive_stock(v_org, 'Aliment 35', 10);
    perform move_stock(v_org, 'Aliment 35', 4);
    -- Free farm, no tool: refused, with the Pro words.
    begin
        perform farm_analytics(v_org);
        raise exception 'FAIL: a free farm read its analyses';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : les analyses%' then raise; end if;
    end;
end $$;
commit;
-- The tool unlocked with cauris opens it, as for a shop.
insert into cauris_unlocks (org_id, feature, until)
values ('35000000-0000-0000-0000-000000000002', 'analytics', now() + interval '30 days')
on conflict (org_id, feature) do update set until = excluded.until;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000002';
do $$
declare
    a jsonb := farm_analytics('35000000-0000-0000-0000-000000000002');
    m jsonb := a -> 'periods' -> 'month';
    l jsonb := a -> 'periods' -> 'last_month';
begin
    if (m ->> 'income')::numeric <> 5000 or (m ->> 'expenses')::numeric <> 2000
       or (l ->> 'income')::numeric <> 3000 or (l ->> 'expenses')::numeric <> 0 then
        raise exception 'FAIL: the month against the last reads % / %', m, l;
    end if;
    if (m ->> 'eggs')::int <> 80 or (m ->> 'deaths')::int <> 3 then
        raise exception 'FAIL: eggs and deaths read %', m;
    end if;
    -- The order for 4 trays was cancelled: nothing sold through the vitrine.
    if (m ->> 'orders')::int <> 0 then
        raise exception 'FAIL: a cancelled order counted as sold';
    end if;
    if (a -> 'flocks' -> 0 ->> 'alive')::int <> 97 or (a -> 'flocks' -> 0 ->> 'died_window')::int <> 3 then
        raise exception 'FAIL: the flock reads %', a -> 'flocks';
    end if;
    if (a -> 'feed' -> 0 ->> 'name') <> 'Aliment 35' or (a -> 'feed' -> 0 ->> 'month')::numeric <> 4 then
        raise exception 'FAIL: the feed reads %', a -> 'feed';
    end if;
    if (a -> 'expenses' -> 0 ->> 'name') <> 'Aliment'
       or (a -> 'income' -> 0 ->> 'amount')::numeric <> 8000 then
        raise exception 'FAIL: the accounts read % / %', a -> 'expenses', a -> 'income';
    end if;
    -- A shorter window leaves last month out.
    a := farm_analytics('35000000-0000-0000-0000-000000000002', date_trunc('month', now()));
    if (a -> 'periods' -> 'window' ->> 'income')::numeric <> 5000 then
        raise exception 'FAIL: the window reads %', a -> 'periods' -> 'window';
    end if;
    raise notice 'PASS: unlocked, the farm reads its month and the last, its flocks, feed and accounts';
end $$;
rollback;
-- What sold, best first: a finished vitrine order of trays, then a till line.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000003';
insert into t35 values ('done', place_order('ferme-35', jsonb_build_array(
    jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000004', 'quantity', 2))));
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000002';
select decide_order((select id from t35 where which = 'done'), 'accepted');
select decide_order((select id from t35 where which = 'done'), 'picked_up');
do $$
declare a jsonb := farm_analytics('35000000-0000-0000-0000-000000000002');
begin
    if (a -> 'products' -> 0 ->> 'name') <> 'Œufs' or (a -> 'products' -> 0 ->> 'revenue')::numeric <> 5000
       or (a -> 'periods' -> 'month' ->> 'orders')::int <> 1 then
        raise exception 'FAIL: what sold reads % / %', a -> 'products', a -> 'periods' -> 'month';
    end if;
    raise notice 'PASS: a finished vitrine order is what the farm sold';
end $$;
rollback;
-- Pro opens it; an association, a reader without full visibility and the
-- street are refused.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000002';
do $$ begin
    if farm_analytics('35000000-0000-0000-0000-000000000004') -> 'periods' is null then
        raise exception 'FAIL: a Pro farm cannot read its analyses';
    end if;
end $$;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000005';
do $$ begin
    begin
        perform farm_analytics('35000000-0000-0000-0000-000000000003');
        raise exception 'FAIL: an association read analyses';
    exception when raise_exception then
        if sqlerrm <> 'Les analyses ne concernent pas une association' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000004';
do $$ begin
    begin
        perform farm_analytics('35000000-0000-0000-0000-000000000002');
        raise exception 'FAIL: a worker without full visibility read the analyses';
    exception when raise_exception then
        if sqlerrm not like 'You cannot read%' then raise; end if;
    end;
    if has_function_privilege('anon', 'farm_analytics(uuid, timestamp with time zone)', 'execute') then
        raise exception 'FAIL: the street may call farm_analytics';
    end if;
    raise notice 'PASS: Pro opens it; an association, a partial reader and the street are refused';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: a business asked for by who is signed in, nothing asked about them ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000006';
do $$
declare v_app org_applications%rowtype;
begin
    perform apply_for_org('Atelier 35', 'atelier-35', 'retail', 'XOF', 'Couture à Gounghin');
    -- Since 111 the request is answered at once; who asked is kept all the
    -- same (null-safe: no row at all fails too).
    select * into v_app from org_applications
     where applicant_id = '35353535-0000-0000-0000-000000000006' and slug = 'atelier-35';
    if v_app.contact_name is distinct from 'Aminata Ouédraogo'
       or v_app.contact_phone is distinct from '+22635000066'
       or v_app.contact_email is distinct from 'asker35@example.com' then
        raise exception 'FAIL: the person was not taken from the profile: % / % / %',
            v_app.contact_name, v_app.contact_phone, v_app.contact_email;
    end if;
    raise notice 'PASS: name, phone and email from the profile and the account';
end $$;
rollback;

\echo ''
\echo '--- TEST 9: the doors ---'
do $$
declare f text;
begin
    foreach f in array array['farm_analytics(uuid, timestamp with time zone)',
        'place_order(text, jsonb, text, text, text, text, text, double precision, double precision)',
        'apply_for_org(text, text, text, text, text, text, text)'] loop
        if has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: the street may call %', f;
        end if;
        if not has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: the app may not call %', f;
        end if;
    end loop;
    foreach f in array array['stock_short_message(text, numeric)',
        'trg_stock_not_below_zero()', 'trg_movement_not_below_zero()',
        'trg_order_moves_stock()', 'trg_sale_order_by_trigger()'] loop
        if has_function_privilege('authenticated', f, 'execute')
           or has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: % is open to an app role', f;
        end if;
    end loop;
    if not has_function_privilege('anon', 'storefront_stock(text)', 'execute') then
        raise exception 'FAIL: the street cannot read what is left';
    end if;
    if has_table_privilege('authenticated', 'order_stock_moves', 'insert')
       or has_table_privilege('authenticated', 'order_stock_moves', 'update')
       or has_table_privilege('authenticated', 'order_stock_moves', 'delete')
       or has_table_privilege('anon', 'order_stock_moves', 'insert') then
        raise exception 'FAIL: an app role may write order_stock_moves';
    end if;
    raise notice 'PASS: the app''s doors for the signed-in; the triggers closed; the street reads what is left; the moves read-only';
end $$;

\echo ''
\echo '--- TEST 10: a finished order is its own sale — once, in the books, the shelf untouched ---'
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published) values
    ('35aaaaaa-0000-0000-0000-000000000007', :shop, 'Sucre', 500, 300, 10, true, true);
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000003';
insert into t35 values ('cash', place_order('boutique-35', jsonb_build_array(
    jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000007', 'quantity', 3))));
insert into t35 values ('wave', place_order('boutique-35', jsonb_build_array(
    jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000007', 'quantity', 2))));
commit;
-- Paid by Wave (076 sets it when the payment lands).
update orders set payment_method = 'wave' where id = (select id from t35 where which = 'wave');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000001';
do $$
declare
    v_sugar uuid := '35aaaaaa-0000-0000-0000-000000000007';
    v_cash  uuid := (select id from t35 where which = 'cash');
    v_wave  uuid := (select id from t35 where which = 'wave');
    v_sale  sales%rowtype;
begin
    perform decide_order(v_cash, 'accepted');
    perform decide_order(v_wave, 'accepted');
    if (select quantity from products where id = v_sugar) <> 5 then
        raise exception 'FAIL: accepting 3 + 2 left % sugar', (select quantity from products where id = v_sugar);
    end if;
    if exists (select 1 from sales where order_id in (v_cash, v_wave)) then
        raise exception 'FAIL: an accepted order is already a sale';
    end if;
    perform decide_order(v_cash, 'ready');
    perform decide_order(v_cash, 'picked_up');
    perform decide_order(v_wave, 'picked_up');
    if (select quantity from products where id = v_sugar) <> 5 then
        raise exception 'FAIL: finishing the orders moved the shelf again (%)', (select quantity from products where id = v_sugar);
    end if;
    select * into v_sale from sales where order_id = v_cash;
    if v_sale.id is null or v_sale.kind <> 'sale' or v_sale.method <> 'cash' or v_sale.total <> 1500
       or v_sale.entry_id is null then
        raise exception 'FAIL: the picked-up order is not a cash sale of 1500: %', row_to_json(v_sale);
    end if;
    if (select count(*) from sale_lines where sale_id = v_sale.id) <> 1
       or (select unit_cost from sale_lines where sale_id = v_sale.id) <> 300
       or (select line_total from sale_lines where sale_id = v_sale.id) <> 1500 then
        raise exception 'FAIL: the sale''s lines are not the order''s';
    end if;
    -- Booked as record_sale books it: the cash box in, 'Ventes' credited.
    if (select a.code from journal_lines jl join accounts a on a.id = jl.account_id
         where jl.journal_entry_id = v_sale.entry_id and jl.debit = 1500) <> '1000'
       or (select a.name from journal_lines jl join accounts a on a.id = jl.account_id
            where jl.journal_entry_id = v_sale.entry_id and jl.credit = 1500) <> 'Ventes' then
        raise exception 'FAIL: the cash order is not booked cash → Ventes';
    end if;
    select * into v_sale from sales where order_id = v_wave;
    if v_sale.method <> 'wave' or v_sale.total <> 1000
       or (select a.code from journal_lines jl join accounts a on a.id = jl.account_id
            where jl.journal_entry_id = v_sale.entry_id and jl.debit = 1000) <> '1020' then
        raise exception 'FAIL: the Wave order is not booked to mobile money';
    end if;
    -- The store's own day reads it, as any sale.
    if (select count(*) from sales where org_id = '35000000-0000-0000-0000-000000000001'
          and order_id in (v_cash, v_wave)) <> 2 then
        raise exception 'FAIL: two finished orders are not two sales';
    end if;
    -- Staff cannot claim an order's sale through the API.
    begin
        insert into sales (org_id, kind, method, total, recorded_by, order_id)
        values ('35000000-0000-0000-0000-000000000001', 'sale', 'cash', 1,
                '35353535-0000-0000-0000-000000000001',
                v_cash);
        raise exception 'FAIL: staff wrote an order''s sale';
    exception when raise_exception then
        if sqlerrm not like 'La vente d''une commande%' then raise; end if;
    end;
    -- Finished cannot be cancelled.
    begin
        perform decide_order(v_cash, 'cancelled');
        raise exception 'FAIL: a picked-up order was cancelled';
    exception when raise_exception then null;
    end;
    raise notice 'PASS: picked up = one sale (cash → 1000, Wave → 1020, Ventes), the order''s lines, the shelf untouched; staff cannot forge one; no cancel';
end $$;
commit;
-- Any other path: written again, no second sale; cancelled after it, refused.
do $$
declare v_cash uuid := (select id from t35 where which = 'cash');
begin
    update orders set status = 'ready' where id = v_cash;
    update orders set status = 'picked_up' where id = v_cash;
    if (select count(*) from sales where order_id = v_cash) <> 1 then
        raise exception 'FAIL: a second pass booked a second sale';
    end if;
    begin
        update orders set status = 'cancelled' where id = v_cash;
        raise exception 'FAIL: a picked-up order was cancelled by a direct write';
    exception when raise_exception then
        if sqlerrm <> 'Une commande remise ou livrée ne peut plus être annulée' then raise; end if;
    end;
    if (select quantity from products where id = '35aaaaaa-0000-0000-0000-000000000007') <> 5 then
        raise exception 'FAIL: the second pass moved the shelf';
    end if;
    raise notice 'PASS: once per order, whatever the path; finished stays finished';
end $$;
-- An order accepted before 101 took nothing: it takes at completion, as
-- far as the shelf goes, and still books; a courier (no member) closing it
-- at the door books it too.
do $$
declare
    v_old  uuid;
    v_far  uuid;
    v_sugar uuid := '35aaaaaa-0000-0000-0000-000000000007';
begin
    insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency)
    values ('35000000-0000-0000-0000-000000000001', '35353535-0000-0000-0000-000000000003',
            'Cliente', 'accepted', 'pickup', 1000, 'XOF')
    returning id into v_old;
    insert into order_lines (order_id, product_id, name, unit_price, quantity)
    values (v_old, v_sugar, 'Sucre', 500, 2);
    insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency)
    values ('35000000-0000-0000-0000-000000000001', '35353535-0000-0000-0000-000000000003',
            'Cliente', 'ready', 'pickup', 5000, 'XOF')
    returning id into v_far;
    insert into order_lines (order_id, product_id, name, unit_price, quantity)
    values (v_far, v_sugar, 'Sucre', 500, 10);
    update orders set status = 'picked_up' where id = v_old;
    if (select quantity from products where id = v_sugar) <> 3
       or (select quantity from order_stock_moves where order_id = v_old and direction = 'out') <> 2 then
        raise exception 'FAIL: an order accepted before 101 did not take its stock at completion';
    end if;
    perform set_config('request.jwt.claim.sub', '35353535-0000-0000-0000-000000000003', true);
    -- Closed by someone who is no member of the shop, as a courier is
    -- at the door (courier_deliver): record_entry's check would refuse.
    update orders set status = 'picked_up' where id = v_far;
    perform set_config('request.jwt.claim.sub', '', true);
    if (select quantity from products where id = v_sugar) <> 0
       or (select quantity from order_stock_moves where order_id = v_far and direction = 'out') <> 3 then
        raise exception 'FAIL: a short shelf was not taken to zero at the door';
    end if;
    if (select total from sales where order_id = v_far) <> 5000
       or (select recorded_by from sales where order_id = v_far) <> '35353535-0000-0000-0000-000000000003'
       or (select total from sales where order_id = v_old) <> 1000 then
        raise exception 'FAIL: the old order or the door did not book its sale';
    end if;
    raise notice 'PASS: an old order takes at completion (never below zero) and books; closed by a non-member, it books';
end $$;
-- The farm: a finished order is dated by its finish, not a later touch;
-- and it is counted once in what sold.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000003';
insert into t35 values ('farmdone', place_order('ferme-35', jsonb_build_array(
    jsonb_build_object('product_id', '35aaaaaa-0000-0000-0000-000000000004', 'quantity', 2))));
set local "request.jwt.claim.sub" = '35353535-0000-0000-0000-000000000002';
select decide_order((select id from t35 where which = 'farmdone'), 'accepted');
select decide_order((select id from t35 where which = 'farmdone'), 'picked_up');
reset role;
-- Touched later (a payment marked, a courier's cash): the date stays.
update orders set updated_at = now() - interval '70 days'
 where id = (select id from t35 where which = 'farmdone');
set local role authenticated;
do $$
declare a jsonb := farm_analytics('35000000-0000-0000-0000-000000000002');
begin
    if (a -> 'periods' -> 'month' ->> 'orders')::int <> 1
       or (a -> 'periods' -> 'month' ->> 'orders_total')::numeric <> 5000 then
        raise exception 'FAIL: the finished order is dated by a later touch: %', a -> 'periods' -> 'month';
    end if;
    if (a -> 'products' -> 0 ->> 'units')::numeric <> 2
       or (a -> 'products' -> 0 ->> 'revenue')::numeric <> 5000 then
        raise exception 'FAIL: the finished order counts twice in what sold: %', a -> 'products';
    end if;
    -- 5000 from the market (TEST 7) and 5000 from the order.
    if (a -> 'periods' -> 'month' ->> 'income')::numeric <> 10000 then
        raise exception 'FAIL: the order''s money is not in the farm''s income: %', a -> 'periods' -> 'month';
    end if;
    raise notice 'PASS: the farm''s order is dated by its finish, sold once, its money in the books';
end $$;
rollback;

\echo ''
\echo '=== test_batch101.sql: all checks passed ==='
