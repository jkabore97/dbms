-- ============================================================
-- test_services.sql — services in the vitrine (098). Phone block 67.
--
-- The claims: a shop's service is never « épuisé » and a till sale does
-- not count it down (nor rings « Stock bas »), while the article sold
-- beside it is counted as always; a service is not received into stock,
-- not made, not an ingredient; the street (anon) reads is_service,
-- price_from and the unit, the service in stock; a basket of services
-- only is refused with a delivery or without a note, and taken as a
-- pickup with the date in the note, each line saying it is a service; a
-- mixed basket is delivered and charged as today; an association with
-- one published service is open and on the street, with none it is not,
-- while a shop still needs the minimum; a finished service order moves
-- nothing in the books or the stock (a shop's earns its cauris as any
-- order, an association's earns none); anon writes nothing; a name
-- belongs to one kind (a service never revives or converts an article,
-- retired or not, an article never takes a service's name, a rename onto
-- a held name and an article with stock turned service are refused in
-- French); an association's treasurer, under RLS, adds, edits and
-- publishes a service through the app's calls, it is booked, seen in
-- « Demandes » and finished, and the customer reads « réservation …
-- terminée »; an association with one service, no photo, a blurb and a
-- phone is on the street, as its settings promise.
-- ============================================================
\set ON_ERROR_STOP on
-- The owner's numbers: earlier suites change them for their own fixtures.
update platform_settings set value = '8' where key = 'vitrine_min_items';
update platform_settings set value = '1' where key = 'vitrine_min_items_association';
update platform_settings set value = '1' where key = 'path_gates_open';
update platform_settings set value = '60' where key = 'progress_street_pct';

\set owner  '''67676767-0000-0000-0000-000000000001'''
\set buyer  '''67676767-0000-0000-0000-000000000002'''
\set treas  '''67676767-0000-0000-0000-000000000003'''
\set other  '''67676767-0000-0000-0000-000000000004'''
\set shop   '''67000000-0000-0000-0000-000000000001'''
\set assoc  '''67000000-0000-0000-0000-000000000002'''
\set small  '''67000000-0000-0000-0000-000000000003'''

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
-- Earlier suites re-apply older migrations over 098's functions.
\i database/migrations/098_services.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22667000001', '{"full_name": "Awa"}'),
    (:buyer, '+22667000002', '{"full_name": "Client"}'),
    (:treas, '+22667000003', '{"full_name": "Trésorière"}'),
    (:other, '+22667000004', '{"full_name": "Voisin"}');
insert into orgs (id, name, slug, profile, default_currency, plan, progress_since,
                  storefront_enabled, storefront_blurb, phone, address, lat, lng) values
    (:shop,  'Salon 67', 'salon-67', 'retail', 'XOF', 'pro', null, true,
     'Coiffure et produits', '+22667000001', 'Gounghin', 12.37, -1.52),
    (:small, 'Petit 67', 'petit-67', 'retail', 'XOF', 'free', null, true,
     'Un seul service', '+22667000004', 'Pissy', 12.36, -1.55);
-- The association keeps the default progress_since: the street's own
-- quality gate (085) applies to it as to a new shop.
insert into orgs (id, name, slug, profile, default_currency,
                  storefront_enabled, storefront_blurb, phone, address, lat, lng) values
    (:assoc, 'Entraide 67', 'entraide-67', 'association', 'XOF', true,
     'Cours d''alphabétisation', '+22667000003', 'Tanghin', 12.39, -1.50);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :owner, 'owner', 'org', :shop,  'full'),
    (:assoc, :treas, 'owner', 'org', :assoc, 'full'),
    (:small, :other, 'owner', 'org', :small, 'full');

-- Seven articles and one service: eight on the window, the minimum.
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
select :shop, 'Article ' || i, 1000, 10, true, true from generate_series(1, 7) i;
-- Entered with a count and a threshold, as a faked service used to be.
insert into products (org_id, name, sale_price, quantity, low_stock_at, is_active,
                      is_published, is_service, price_from, unit)
values (:shop, 'Tresses', 5000, 5, 2, true, true, true, true, 'heure'),
       (:small, 'Réparation', 2000, 0, null, true, true, true, false, null);
insert into documents (org_id, product_id, kind, r2_key, uploaded_by)
select org_id, id, 'product_photo', 'p/' || id, :owner from products where org_id = :shop;

\echo ''
\echo '--- TEST 1: a service has no count, and the till does not count it down ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '67676767-0000-0000-0000-000000000001';
do $$
declare
    v_service uuid;
    v_article uuid;
    v_sale    uuid;
    v_qty     numeric;
    v_low     numeric;
    v_total   numeric;
begin
    select id, quantity, low_stock_at into v_service, v_qty, v_low from products
     where org_id = '67000000-0000-0000-0000-000000000001' and name = 'Tresses';
    if v_qty <> 0 or v_low is not null then
        raise exception 'FAIL: a service was stored with a count (%) or a threshold (%)', v_qty, v_low;
    end if;
    select id into v_article from products
     where org_id = '67000000-0000-0000-0000-000000000001' and name = 'Article 1';

    v_sale := record_sale('67000000-0000-0000-0000-000000000001',
        jsonb_build_array(
            jsonb_build_object('product_id', v_service, 'quantity', 3, 'unit_price', 5000),
            jsonb_build_object('product_id', v_article, 'quantity', 2, 'unit_price', 1000)),
        'cash');
    select total into v_total from sales where id = v_sale;
    if v_total <> 17000 then
        raise exception 'FAIL: the sale totals %, not 17 000', v_total;
    end if;
    select quantity into v_qty from products where id = v_service;
    if v_qty <> 0 then
        raise exception 'FAIL: the till counted a service down to %', v_qty;
    end if;
    select quantity into v_qty from products where id = v_article;
    if v_qty <> 8 then
        raise exception 'FAIL: the article beside it reads %, not 8', v_qty;
    end if;
    if not exists (select 1 from journal_lines jl join accounts a on a.id = jl.account_id
                    where a.org_id = '67000000-0000-0000-0000-000000000001'
                      and a.name = 'Ventes' and jl.credit = 17000) then
        raise exception 'FAIL: the service''s money is not in the books';
    end if;
    if exists (select 1 from notifications
                where org_id = '67000000-0000-0000-0000-000000000001' and kind = 'low_stock') then
        raise exception 'FAIL: a service rang « Stock bas »';
    end if;
    -- Its return does not count it up either.
    perform record_return(v_sale);
    select quantity into v_qty from products where id = v_service;
    if v_qty <> 0 then
        raise exception 'FAIL: a return counted a service up to %', v_qty;
    end if;
    raise notice 'PASS: sold 3 hours, the service still has no count; the article is counted; the money is booked';
end $$;
commit;

\echo ''
\echo '--- TEST 2: a service is not received, not made, not an ingredient ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '67676767-0000-0000-0000-000000000001';
do $$
declare
    v_service uuid;
    v_article uuid;
begin
    select id into v_service from products
     where org_id = '67000000-0000-0000-0000-000000000001' and name = 'Tresses';
    select id into v_article from products
     where org_id = '67000000-0000-0000-0000-000000000001' and name = 'Article 2';
    begin
        perform receive_products('67000000-0000-0000-0000-000000000001', v_service, 4, 100);
        raise exception 'FAIL: a service was received into stock';
    exception when others then
        if sqlerrm not like 'Un service n''a pas de stock%' then raise; end if;
    end;
    begin
        perform record_production('67000000-0000-0000-0000-000000000001', 1,
            jsonb_build_array(jsonb_build_object('product_id', v_service, 'quantity', 1)),
            v_article);
        raise exception 'FAIL: a service was an ingredient';
    exception when others then
        if sqlerrm <> 'Un service ne peut pas être un ingrédient' then raise; end if;
    end;
    begin
        perform record_production('67000000-0000-0000-0000-000000000001', 1,
            jsonb_build_array(jsonb_build_object('product_id', v_article, 'quantity', 1)),
            v_service);
        raise exception 'FAIL: a service was made by a production';
    exception when others then
        if sqlerrm <> 'Un service ne se fabrique pas' then raise; end if;
    end;
    begin
        update products set is_ingredient = true where id = v_service;
        raise exception 'FAIL: a service was flagged an ingredient';
    exception when others then
        if sqlerrm <> 'Un service ne peut pas être un ingrédient' then raise; end if;
    end;
    raise notice 'PASS: receipt, production and ingredient refused for a service, in French';
end $$;
commit;

\echo ''
\echo '--- TEST 3: the street reads a service, « à partir de », by the hour ---'
begin;
set local role anon;
do $$
declare r record;
begin
    select * into r from storefront_products('salon-67') where name = 'Tresses';
    if not found then
        raise exception 'FAIL: the service is not on the window';
    end if;
    if not r.is_service or not r.price_from or r.unit <> 'heure'
       or not r.in_stock or r.sale_price <> 5000 then
        raise exception 'FAIL: the window reads %', row_to_json(r);
    end if;
    select * into r from storefront_products('salon-67') where name = 'Article 1';
    if r.is_service or r.price_from then
        raise exception 'FAIL: an article reads as a service: %', row_to_json(r);
    end if;
    if (select is_service from storefront_products('salon-67') limit 1) then
        raise exception 'FAIL: the services come before the articles';
    end if;
    if not (select in_stock from search_products('tresses') where shop_slug = 'salon-67') then
        raise exception 'FAIL: the search says a service is out of stock';
    end if;
    raise notice 'PASS: anon reads is_service, price_from, unit, and the service in stock';
end $$;
commit;

\echo ''
\echo '--- TEST 4: a basket of services only is an appointment ---'
-- The customer cannot read the shop's products table; the window's ids.
create temp table t67p as select name, id from products
 where org_id in ('67000000-0000-0000-0000-000000000001', '67000000-0000-0000-0000-000000000002');
grant select on t67p to authenticated;
create temp table t67 (which text, id uuid);
grant all on t67 to authenticated;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '67676767-0000-0000-0000-000000000002';
do $$
declare
    v_service uuid;
    v_article uuid;
    v_lines   jsonb;
    v_id      uuid;
    v_order   orders%rowtype;
begin
    select id into v_service from t67p where name = 'Tresses';
    select id into v_article from t67p where name = 'Article 3';
    v_lines := jsonb_build_array(jsonb_build_object('product_id', v_service, 'quantity', 2));

    begin
        perform place_order('salon-67', v_lines, 'delivery', 'Samedi 10 h',
                            'Dassasgho', null, 'cash', 12.371, -1.521);
        raise exception 'FAIL: a services-only basket was delivered';
    exception when others then
        if sqlerrm <> 'Un service se réserve sur rendez-vous : pas de livraison' then raise; end if;
    end;
    begin
        perform place_order('salon-67', v_lines, 'pickup', '   ');
        raise exception 'FAIL: a services-only basket went without a date';
    exception when others then
        if sqlerrm <> 'Indiquez la date et l''heure souhaitées' then raise; end if;
    end;

    v_id := place_order('salon-67', v_lines, 'pickup', 'Samedi 10 h');
    insert into t67 values ('services', v_id);
    select * into v_order from orders where id = v_id;
    if v_order.fulfilment <> 'pickup' or v_order.note <> 'Samedi 10 h'
       or v_order.delivery_fee is not null or v_order.total <> 10000 then
        raise exception 'FAIL: the appointment reads % / % / % / %',
            v_order.fulfilment, v_order.note, v_order.delivery_fee, v_order.total;
    end if;
    if not (select bool_and(is_service) from order_lines where order_id = v_id) then
        raise exception 'FAIL: the line does not remember it is a service';
    end if;
    if not exists (select 1 from my_orders() m, jsonb_array_elements(m.lines) l
                    where m.id = v_id and (l ->> 'is_service')::boolean) then
        raise exception 'FAIL: the customer''s list does not say « service »';
    end if;

    -- Mixed: the article travels, the fee is today's fee, no note needed.
    v_id := place_order('salon-67',
        jsonb_build_array(jsonb_build_object('product_id', v_service, 'quantity', 1),
                          jsonb_build_object('product_id', v_article, 'quantity', 2)),
        'delivery', null, 'Dassasgho', null, 'cash', 12.371, -1.521);
    insert into t67 values ('mixed', v_id);
    select * into v_order from orders where id = v_id;
    if v_order.fulfilment <> 'delivery'
       or v_order.delivery_fee is distinct from
          delivery_fee('67000000-0000-0000-0000-000000000001', 12.371, -1.521)
       or v_order.total <> 7000 then
        raise exception 'FAIL: the mixed basket reads % / fee % / %',
            v_order.fulfilment, v_order.delivery_fee, v_order.total;
    end if;
    if (select count(*) from order_lines where order_id = v_id and is_service) <> 1 then
        raise exception 'FAIL: the mixed basket does not mark its one service line';
    end if;
    raise notice 'PASS: refused with a delivery or without a date, taken as a pickup with one; mixed as today';
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '67676767-0000-0000-0000-000000000001';
do $$ begin
    if not exists (select 1 from shop_orders('67000000-0000-0000-0000-000000000001') s,
                          jsonb_array_elements(s.lines) l
                    where (l ->> 'is_service')::boolean and l ->> 'name' = 'Tresses') then
        raise exception 'FAIL: the shop''s list does not say « service »';
    end if;
    raise notice 'PASS: the shop sees its service lines marked';
end $$;
commit;

\echo ''
\echo '--- TEST 5: an association opens with one service; a shop still needs the minimum ---'
begin;
set local role anon;
do $$ begin
    if storefront_open('entraide-67') is not null
       or exists (select 1 from storefront_directory() where slug = 'entraide-67') then
        raise exception 'FAIL: an association with nothing published is public';
    end if;
    if storefront_open('petit-67') is not null
       or exists (select 1 from storefront_directory() where slug = 'petit-67') then
        raise exception 'FAIL: a shop with one service skipped the minimum';
    end if;
end $$;
commit;
insert into products (org_id, name, sale_price, quantity, is_active, is_published,
                      is_service, unit)
values ('67000000-0000-0000-0000-000000000002', 'Cours du soir', 1500, 0, true, true, true, 'séance');
insert into documents (org_id, product_id, kind, r2_key, uploaded_by)
select org_id, id, 'product_photo', 'p/' || id, '67676767-0000-0000-0000-000000000003'
  from products where org_id = '67000000-0000-0000-0000-000000000002';
begin;
set local role anon;
do $$ begin
    if storefront_open('entraide-67') is null then
        raise exception 'FAIL: one published service does not open an association';
    end if;
    if not exists (select 1 from storefront_directory()
                    where slug = 'entraide-67' and profile = 'association') then
        raise exception 'FAIL: the association is not on the street as an association';
    end if;
    if not (select is_service from storefront_products('entraide-67')) then
        raise exception 'FAIL: the association''s service is not on its window';
    end if;
    if storefront_open('petit-67') is not null then
        raise exception 'FAIL: the shop below the minimum opened';
    end if;
    raise notice 'PASS: the association is public from 1 service, on the street; the shop still needs 8';
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '67676767-0000-0000-0000-000000000003';
do $$
declare c jsonb := vitrine_checklist('67000000-0000-0000-0000-000000000002');
begin
    if (c ->> 'min_items')::int <> 1 or (c ->> 'services')::int <> 1 then
        raise exception 'FAIL: the association''s checklist reads %', c;
    end if;
    if vitrine_score('67000000-0000-0000-0000-000000000002') < 100 then
        raise exception 'FAIL: one service with a photo does not make the association''s first step';
    end if;
    raise notice 'PASS: the checklist says 1 and counts the service';
end $$;
commit;

\echo ''
\echo '--- TEST 6: a finished service order moves nothing in the books or the stock ---'
create temp table t67books as
select o.id as org_id,
       (select count(*) from sales s where s.org_id = o.id) as sales,
       (select count(*) from journal_entries j where j.org_id = o.id) as entries
  from orgs o where o.id in ('67000000-0000-0000-0000-000000000001',
                             '67000000-0000-0000-0000-000000000002');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '67676767-0000-0000-0000-000000000002';
do $$
declare v_id uuid;
begin
    v_id := place_order('entraide-67',
        jsonb_build_array(jsonb_build_object(
            'product_id', (select id from storefront_products('entraide-67')),
            'quantity', 3)),
        'pickup', 'Lundi 18 h');
    insert into t67 values ('assoc', v_id);
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '67676767-0000-0000-0000-000000000001';
select decide_order((select id from t67 where which = 'services'), 'accepted');
select decide_order((select id from t67 where which = 'services'), 'picked_up');
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '67676767-0000-0000-0000-000000000003';
select decide_order((select id from t67 where which = 'assoc'), 'accepted');
select decide_order((select id from t67 where which = 'assoc'), 'picked_up');
commit;
do $$
declare r record;
begin
    for r in select b.org_id, b.sales, b.entries,
                    (select count(*) from sales s where s.org_id = b.org_id) as sales_now,
                    (select count(*) from journal_entries j where j.org_id = b.org_id) as entries_now
               from t67books b loop
        if r.sales_now <> r.sales or r.entries_now <> r.entries then
            raise exception 'FAIL: a finished order wrote to the books of %: sales % → %, entries % → %',
                r.org_id, r.sales, r.sales_now, r.entries, r.entries_now;
        end if;
    end loop;
    if (select quantity from products
         where org_id = '67000000-0000-0000-0000-000000000001' and name = 'Tresses') <> 0 then
        raise exception 'FAIL: a finished service order moved its count';
    end if;
    if (select status from orders where id = (select id from t67 where which = 'assoc')) <> 'picked_up' then
        raise exception 'FAIL: the association could not finish its order';
    end if;
    if not exists (select 1 from cauris_ledger
                    where org_id = '67000000-0000-0000-0000-000000000001' and reason = 'order_done'
                      and ref = (select id from t67 where which = 'services')::text) then
        raise exception 'FAIL: the shop''s finished service order earned no cauris, unlike any order';
    end if;
    if exists (select 1 from cauris_ledger where org_id = '67000000-0000-0000-0000-000000000002') then
        raise exception 'FAIL: an association earned cauris';
    end if;
    raise notice 'PASS: finished, as any order: no sale, no entry, no stock; the shop''s cauris, none for the association';
end $$;

\echo ''
\echo '--- TEST 7: anon writes nothing ---'
begin;
set local role anon;
do $$
declare v_state text;
begin
    begin
        insert into products (org_id, name, sale_price, is_service)
        values ('67000000-0000-0000-0000-000000000002', 'Faux service', 1, true);
        raise exception 'FAIL: anon added a service';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    begin
        update products set price_from = false, sale_price = 1
         where org_id = '67000000-0000-0000-0000-000000000001';
        if exists (select 1 from products
                    where org_id = '67000000-0000-0000-0000-000000000001' and sale_price = 1) then
            raise exception 'FAIL: anon repriced a service';
        end if;
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    begin
        perform place_order('entraide-67', '[]'::jsonb, 'pickup', 'x');
        raise exception 'FAIL: anon placed an order';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
end $$;
commit;
do $$ begin
    if has_function_privilege('anon', 'vitrine_min(uuid)', 'execute')
       or has_function_privilege('authenticated', 'vitrine_min(uuid)', 'execute')
       or has_function_privilege('anon', 'trg_service_no_stock()', 'execute')
       or has_function_privilege('anon', 'trg_product_name_free()', 'execute')
       or has_function_privilege('anon',
              'ensure_product(uuid, text, numeric, numeric, text, date, uuid, boolean)', 'execute')
       or has_function_privilege('anon', 'trg_service_not_stocked()', 'execute')
       or has_function_privilege('authenticated', 'trg_service_not_stocked()', 'execute') then
        raise exception 'FAIL: 098''s helpers are open to the street';
    end if;
    if not has_function_privilege('anon', 'storefront_products(text)', 'execute')
       or not has_function_privilege('authenticated', 'storefront_products(text)', 'execute') then
        raise exception 'FAIL: the window lost its grant when it was recreated';
    end if;
    raise notice 'PASS: anon adds, reprices and orders nothing; the helpers are closed, the window open';
end $$;

\echo ''
\echo '--- TEST 8: one name, one kind ---'
\set farm '''67000000-0000-0000-0000-000000000004'''
insert into orgs (id, name, slug, profile, default_currency, plan, progress_since)
values (:farm, 'Ferme 67', 'ferme-67', 'farm', 'XOF', 'free', null);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
values (:farm, :owner, 'owner', 'org', :farm, 'full');
-- A retired article with goods still counted; a retired service; the
-- farm's service.
insert into products (org_id, name, sale_price, quantity, is_active) values
    (:shop, 'Lavage', 1000, 4, false);
insert into products (org_id, name, sale_price, is_active, is_service) values
    (:shop, 'Massage', 3000, false, true),
    (:farm, 'Labour', 15000, true, true);
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '67676767-0000-0000-0000-000000000001';
do $$
declare
    v_shop  constant uuid := '67000000-0000-0000-0000-000000000001';
    v_farm  constant uuid := '67000000-0000-0000-0000-000000000004';
    v_actor constant uuid := '67676767-0000-0000-0000-000000000001';
    v_id    uuid;
    v_row   products%rowtype;
    v_sale  uuid;
begin
    -- A service named like a retired article with stock: refused, the
    -- article untouched (still an article, still retired, still 4).
    begin
        perform ensure_product(v_shop, 'lavage ', 1500, p_actor => v_actor, p_is_service => true);
        raise exception 'FAIL: a service took a retired article''s name';
    exception when others then
        if sqlerrm <> 'Un article porte déjà ce nom' then raise; end if;
    end;
    select * into v_row from products where org_id = v_shop and name = 'Lavage';
    if v_row.is_service or v_row.is_active or v_row.quantity <> 4 then
        raise exception 'FAIL: the retired article was touched: service %, active %, count %',
            v_row.is_service, v_row.is_active, v_row.quantity;
    end if;
    -- Nor an active article's.
    begin
        perform ensure_product(v_shop, 'Article 5', 1500, p_actor => v_actor, p_is_service => true);
        raise exception 'FAIL: a service took an active article''s name';
    exception when others then
        if sqlerrm <> 'Un article porte déjà ce nom' then raise; end if;
    end;
    -- An article (shop or farm) named like a service: refused.
    begin
        perform ensure_product(v_shop, 'TRESSES', 1000, p_actor => v_actor, p_is_service => false);
        raise exception 'FAIL: an article took a service''s name';
    exception when others then
        if sqlerrm <> 'Un service porte déjà ce nom' then raise; end if;
    end;
    begin
        perform ensure_product(v_farm, 'Labour', 1000, p_actor => v_actor, p_is_service => false);
        raise exception 'FAIL: a farm article took a service''s name';
    exception when others then
        if sqlerrm <> 'Un service porte déjà ce nom' then raise; end if;
    end;
    -- A second service under an active service's name: refused.
    begin
        perform ensure_product(v_shop, 'Tresses', 1000, p_actor => v_actor, p_is_service => true);
        raise exception 'FAIL: a service was added twice';
    exception when others then
        if sqlerrm <> 'Un service porte déjà ce nom' then raise; end if;
    end;
    -- A retired service comes back as one (051), a new name is born one.
    v_id := ensure_product(v_shop, 'Massage', 3000, p_actor => v_actor, p_is_service => true);
    select * into v_row from products where id = v_id;
    if not v_row.is_active or not v_row.is_service then
        raise exception 'FAIL: the retired service did not come back as a service';
    end if;
    v_id := ensure_product(v_shop, 'Manucure', 2500, p_actor => v_actor, p_is_service => true);
    select * into v_row from products where id = v_id;
    if not v_row.is_service or v_row.quantity <> 0 or v_row.sale_price <> 2500 then
        raise exception 'FAIL: the new service reads %', row_to_json(v_row);
    end if;
    -- An article re-added as an article still works (051).
    if ensure_product(v_shop, 'Article 6', p_actor => v_actor, p_is_service => false)
       is distinct from (select id from products where org_id = v_shop and name = 'Article 6') then
        raise exception 'FAIL: re-adding an article by name did not find it';
    end if;
    -- The till, typing a service's name, still sells the service.
    v_sale := record_sale(v_shop,
        jsonb_build_array(jsonb_build_object('name', 'tresses', 'quantity', 1, 'unit_price', 5000)),
        'cash');
    if (select p.name from sale_lines l join products p on p.id = l.product_id
         where l.sale_id = v_sale) <> 'Tresses' then
        raise exception 'FAIL: the till did not ring up the service by its name';
    end if;

    -- A rename onto a name another row holds: French, with its kind.
    begin
        update products set name = 'article 1' where org_id = v_shop and name = 'Manucure';
        raise exception 'FAIL: a service was renamed onto an article';
    exception when others then
        if sqlerrm <> 'Un article porte déjà ce nom' then raise; end if;
    end;
    begin
        update products set name = 'Tresses ' where org_id = v_shop and name = 'Article 2';
        raise exception 'FAIL: an article was renamed onto a service';
    exception when others then
        if sqlerrm <> 'Un service porte déjà ce nom' then raise; end if;
    end;
    -- Its own name in other letters is no collision.
    update products set name = 'MANUCURE' where org_id = v_shop and name = 'Manucure';

    -- An article with goods is not turned into a service.
    begin
        update products set is_service = true where org_id = v_shop and name = 'Article 3';
        raise exception 'FAIL: an article with stock became a service';
    exception when others then
        if sqlerrm <> 'Cet article a du stock : il ne peut pas devenir un service' then raise; end if;
    end;
    if (select quantity from products where org_id = v_shop and name = 'Article 3') <> 10 then
        raise exception 'FAIL: the article''s count moved';
    end if;
    raise notice 'PASS: a service never takes an article''s name nor an article a service''s; renames and conversions refused in French; the till still sells by name';
end $$;
commit;

\echo ''
\echo '--- TEST 9: the association''s treasurer, through the app''s own calls ---'
\set tres2 '''67676767-0000-0000-0000-000000000005'''
insert into auth.users (id, phone, raw_user_meta_data) values
    (:tres2, '+22667000005', '{"full_name": "Trésorier"}');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:assoc, :tres2, 'admin', 'org', :assoc, 'full');
create temp table t67hall (id uuid, order_id uuid);
grant all on t67hall to authenticated;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '67676767-0000-0000-0000-000000000005';
do $$
declare
    v_assoc constant uuid := '67000000-0000-0000-0000-000000000002';
    v_id    uuid;
    v_n     int;
    v_row   products%rowtype;
begin
    -- RetailRepository.ensureProduct(isService: true), then updateProduct.
    v_id := ensure_product(v_assoc, 'Location de salle', 25000,
                           p_actor => '67676767-0000-0000-0000-000000000005',
                           p_is_service => true);
    with u as (
        update products set name = 'Location de salle', sale_price = 25000,
               unit = 'soirée', is_published = false, description = 'Chaises comprises',
               is_service = true, price_from = true
         where id = v_id returning id)
    select count(*) into v_n from u;
    if v_n <> 1 then
        raise exception 'FAIL: the treasurer''s edit of the service did not land';
    end if;
    -- Published from the sheet's « Sur la vitrine ».
    with u as (update products set is_published = true where id = v_id returning id)
    select count(*) into v_n from u;
    select * into v_row from products where id = v_id;
    if v_n <> 1 or not v_row.is_published or not v_row.is_service
       or not v_row.price_from or v_row.unit <> 'soirée' then
        raise exception 'FAIL: the treasurer''s service reads %', row_to_json(v_row);
    end if;
    insert into t67hall (id) values (v_id);
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '67676767-0000-0000-0000-000000000002';
do $$
declare r record;
begin
    select * into r from storefront_products('entraide-67') where name = 'Location de salle';
    if not found or not r.is_service or not r.price_from or r.unit <> 'soirée' then
        raise exception 'FAIL: the customer does not see the hall as a service: %', row_to_json(r);
    end if;
    update t67hall set order_id = place_order('entraide-67',
        jsonb_build_array(jsonb_build_object('product_id', r.id, 'quantity', 1)),
        'pickup', 'Samedi 20 h');
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '67676767-0000-0000-0000-000000000005';
do $$
declare
    v_order uuid := (select order_id from t67hall);
begin
    if not exists (select 1 from shop_orders('67000000-0000-0000-0000-000000000002') s,
                          jsonb_array_elements(s.lines) l
                    where s.id = v_order and s.note = 'Samedi 20 h'
                      and (l ->> 'is_service')::boolean) then
        raise exception 'FAIL: the treasurer does not see the booking in « Demandes »';
    end if;
    perform decide_order(v_order, 'accepted');
    perform decide_order(v_order, 'picked_up');
    if (select status from orders where id = v_order) <> 'picked_up' then
        raise exception 'FAIL: the treasurer could not finish the booking';
    end if;
    raise notice 'PASS: the treasurer adds, edits and publishes a service; it is booked, seen and finished';
end $$;
commit;
do $$
declare v_order uuid := (select order_id from t67hall);
begin
    if not exists (select 1 from notifications
                    where recipient_id = '67676767-0000-0000-0000-000000000002'
                      and kind = 'order_picked_up'
                      and message = 'Votre réservation chez Entraide 67 : terminée') then
        raise exception 'FAIL: the customer was not told « réservation … terminée »: %',
            (select string_agg(message, ' | ') from notifications
              where recipient_id = '67676767-0000-0000-0000-000000000002');
    end if;
    if not exists (select 1 from notifications
                    where recipient_id = '67676767-0000-0000-0000-000000000002'
                      and kind = 'order_accepted'
                      and message = 'Votre réservation chez Entraide 67 : acceptée') then
        raise exception 'FAIL: the booking''s acceptance reads as an order';
    end if;
    raise notice 'PASS: the customer reads « Votre réservation … : acceptée / terminée »';
end $$;
-- A mixed basket keeps its order's words.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '67676767-0000-0000-0000-000000000001';
select decide_order((select id from t67 where which = 'mixed'), 'accepted');
commit;
do $$ begin
    if not exists (select 1 from notifications
                    where recipient_id = '67676767-0000-0000-0000-000000000002'
                      and kind = 'order_accepted'
                      and message = 'Votre commande chez Salon 67 : acceptée') then
        raise exception 'FAIL: a mixed basket''s acceptance does not read as an order';
    end if;
    raise notice 'PASS: a mixed basket is still « Votre commande »';
end $$;

\echo ''
\echo '--- TEST 10: an association on the street with one service, no photo, a blurb and a phone ---'
\set club '''67000000-0000-0000-0000-000000000005'''
-- The default progress_since: the street's quality gate (085) applies.
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled,
                  storefront_blurb, phone)
values (:club, 'Club 67', 'club-67', 'association', 'XOF', true,
        'Cours de couture', '+22667000006');
insert into products (org_id, name, sale_price, is_active, is_published, is_service)
values (:club, 'Cours de couture', 2000, true, true, true);
create temp table t67score as
select vitrine_score('67000000-0000-0000-0000-000000000005') as score,
       (select progress_since from orgs where slug = 'club-67') as since;
grant select on t67score to anon;
do $$ begin
    if (select since from t67score) is null then
        raise exception 'FAIL: the fixture skipped the street''s quality gate';
    end if;
    -- Published, photo (met for an association), blurb, phone: 4 of 6.
    if (select score from t67score) <> 67 then
        raise exception 'FAIL: the association scores %, not 67', (select score from t67score);
    end if;
end $$;
begin;
set local role anon;
do $$
declare v_score int := (select score from t67score);
begin
    if storefront_open('club-67') is null then
        raise exception 'FAIL: one published service does not open the association';
    end if;
    if not exists (select 1 from storefront_directory() where slug = 'club-67') then
        raise exception 'FAIL: the association is not on the street (score %)', v_score;
    end if;
    raise notice 'PASS: 1 service, no photo, blurb and phone: open and on the street (score %)', v_score;
end $$;
commit;

\echo ''
\echo 'test_services: all passed'
