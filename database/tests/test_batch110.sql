-- ============================================================
-- test_batch110.sql — the vitrine's features on Mara's switchboard (110).
-- Phone block 111.
--
-- The claims, for a shop, a farm and an association (a legacy church
-- counted as one) alike:
--   P1 (in this database): with no rule written, none of the vitrine's
--      switches hides anything for any business, and no vitrine says
--      « Commandes fermées ». (The before/after proof is p1_110_before.sql
--      / p1_110_after.sql, its own CI step.)
--   P2: no dead switch — each of the seven keys, hidden, changes what the
--      vitrine shows AND is refused at its server doors: the shopper's
--      (an order, a booking, a delivery, Wave) in plain French to anyone,
--      the owner's (a service created, the rates, the Wave payout, the
--      dressing, a spot) with 104's MA002; visible again, each opens.
--   P3: what the business paid for is never hidden — a paid Pro keeps
--      delivery, Wave and Vitrine Plus, a spot paid for or running keeps
--      « Mettre en avant » — while Mara's gift is not a payment; each kind
--      is offered its own switches only (an association no delivery, only
--      a farm « À vendre »); only the platform switches, logged, undone,
--      the owner told; the new engine is closed to the street and to the
--      app's roles; the street's functions still answer a stranger.
-- ============================================================
\set ON_ERROR_STOP on

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
-- Earlier suites re-apply older migrations over the functions 104 and 110
-- rebuilt, and hand the app's roles every table and function: 104 and 110
-- again, so what follows tests their doors as they are live.
\i database/migrations/104_feature_switchboard.sql
\i database/migrations/110_vitrine_switches.sql

-- Ordering as today (109's phone check is off unless Mara turns it on).
create temp table b110_saved as
    select key, value from platform_settings where key = 'order_phone_verified';
update platform_settings set value = 'false' where key = 'order_phone_verified';

\set mara    '''11001100-0000-0000-0000-000000000001'''
\set powner  '''11001100-0000-0000-0000-000000000002'''
\set bowner  '''11001100-0000-0000-0000-000000000003'''
\set fowner  '''11001100-0000-0000-0000-000000000004'''
\set aowner  '''11001100-0000-0000-0000-000000000005'''
\set cowner  '''11001100-0000-0000-0000-000000000006'''
\set shopper '''11001100-0000-0000-0000-000000000007'''
\set pro     '''11000000-0000-0000-0000-000000000001'''
\set basic   '''11000000-0000-0000-0000-000000000002'''
\set farm    '''11000000-0000-0000-0000-000000000003'''
\set assoc   '''11000000-0000-0000-0000-000000000004'''
\set church  '''11000000-0000-0000-0000-000000000005'''

insert into auth.users (id, phone, raw_user_meta_data) values
    (:mara,    '+22611101001', '{"full_name": "Mara 111"}'),
    (:powner,  '+22611101002', '{"full_name": "Patronne Pro 111"}'),
    (:bowner,  '+22611101003', '{"full_name": "Patronne Basic 111"}'),
    (:fowner,  '+22611101004', '{"full_name": "Fermier 111"}'),
    (:aowner,  '+22611101005', '{"full_name": "Trésorière 111"}'),
    (:cowner,  '+22611101006', '{"full_name": "Pasteur 111"}'),
    (:shopper, '+22611101007', '{"full_name": "Cliente 111"}');
update profiles set is_platform_admin = true where id = :mara;
insert into orgs (id, name, slug, profile, default_currency, plan, plan_until, storefront_enabled,
                  storefront_blurb, phone, address, lat, lng) values
    (:pro,    'Pro 111',      'pro-111',      'retail',      'XOF', 'pro',  '2099-01-01', true, 'Pro', '+22611101002', 'Dapoya',   12.37, -1.52),
    (:basic,  'Basic 111',    'basic-111',    'retail',      'XOF', 'free', null,         true, 'Basic', '+22611101003', 'Gounghin', 12.36, -1.53),
    (:farm,   'Ferme 111',    'ferme-111',    'farm',        'XOF', 'free', null,         true, 'Ferme', '+22611101004', 'Saaba',    12.38, -1.42),
    (:assoc,  'Entraide 111', 'entraide-111', 'association', 'XOF', 'free', null,         true, 'Asso', '+22611101005', 'Tanghin',  12.40, -1.50),
    (:church, 'Chapelle 111', 'chapelle-111', 'church',      'XOF', 'free', null,         true, 'Culte', '+22611101006', 'Pissy',   12.33, -1.56);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:pro,    :powner, 'owner', 'org', :pro,    'full'),
    (:basic,  :bowner, 'owner', 'org', :basic,  'full'),
    (:farm,   :fowner, 'owner', 'org', :farm,   'full'),
    (:assoc,  :aowner, 'owner', 'org', :assoc,  'full'),
    (:church, :cowner, 'owner', 'org', :church, 'full');
-- Mara gives the Basic shop the whole of Pro: its delivery, Wave and
-- Vitrine Plus work — a gift, not a payment, so a switch still hides them.
insert into cauris_unlocks (org_id, feature, until, note, gifted_by) values
    (:basic, 'pro_all', now() + interval '30 days', 'Offert par Mara', :mara);
insert into cauris_ledger (org_id, delta, reason, ref) values
    (:basic, 5000, 'gift', 'b110-basic'), (:farm, 5000, 'gift', 'b110-farm');
update orgs set wave_allowed = true, wave_merchant = 'M111', wave_payout_number = '+22670111001',
                delivery_base = 500, delivery_per_km = 100, delivery_max_km = 20,
                storefront_style = '{"tagline": "Habillée", "layout": "large", "hide_out_of_stock": true, "accent": "#123456"}'
 where id in (:pro, :basic);
update orgs set wave_allowed = true, wave_merchant = 'M111A' where id in (:assoc, :church);

-- Eight articles on each shop and the farm, a service each; services for
-- the association and the church; photographs.
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_published, unit)
select ('11000000-0000-0000-00' || o.tag || '-00000000000' || g)::uuid, o.id, o.prefix || ' ' || g, 100 * g, 50 * g, 10 * g, true,
       case when o.tag = 'f0' then 'plateau' end
  from (values (:pro::uuid, 'Pagne 111', 'a0'), (:basic::uuid, 'Savon 111', 'b0'), (:farm::uuid, 'Œufs 111', 'f0')) o(id, prefix, tag)
 cross join generate_series(1, 8) g;
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_published, is_service, unit) values
    ('11000000-0000-0000-00a0-000000000009', :pro,    'Retouche 111', 1500, 0, 0, true, true, 'séance'),
    ('11000000-0000-0000-00b0-000000000009', :basic,  'Montage 111',  2000, 0, 0, true, true, 'séance'),
    ('11000000-0000-0000-00f0-000000000009', :farm,   'Labour 111',   9000, 0, 0, true, true, 'hectare'),
    ('11000000-0000-0000-00c0-000000000001', :assoc,  'Bâches 111',   5000, 0, 0, true, true, 'jour'),
    ('11000000-0000-0000-00d0-000000000001', :church, 'Cours 111',    1000, 0, 0, true, true, 'séance');
insert into documents (org_id, r2_key, kind, content_type, uploaded_by, product_id) values
    (:basic, 'b110/savon-1.jpg',   'product_photo', 'image/jpeg', :bowner, '11000000-0000-0000-00b0-000000000001'),
    (:basic, 'b110/montage.jpg',   'product_photo', 'image/jpeg', :bowner, '11000000-0000-0000-00b0-000000000009'),
    (:farm,  'b110/oeufs-1.jpg',   'product_photo', 'image/jpeg', :fowner, '11000000-0000-0000-00f0-000000000001'),
    (:assoc, 'b110/baches.jpg',    'product_photo', 'image/jpeg', :aowner, '11000000-0000-0000-00c0-000000000001');
-- « À la une »: Mara's pick on the Basic shop, a spot running on Pro.
update products set featured_until = now() + interval '5 days' where id = '11000000-0000-0000-00b0-000000000002';
insert into promotions (id, org_id, product_id, kind, days, price, currency, free, status, starts_at, ends_at, requested_by) values
    ('11000000-0000-0000-0000-0000000000e1', :pro, null, 'shop', 7, 2500, 'XOF', false, 'approved',
     now() - interval '1 day', now() + interval '6 days', :powner),
    ('11000000-0000-0000-0000-0000000000e2', :basic, null, 'shop', 7, 2500, 'XOF', false, 'requested',
     null, null, :bowner);

-- A door, knocked on: 'ok', or the SQLSTATE and the sentence.
create or replace function zz_b110_try(p_sql text)
returns text
language plpgsql
set search_path = public
as $$
declare
    v_state text;
    v_msg   text;
begin
    execute p_sql;
    return 'ok';
exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return v_state || ': ' || v_msg;
end;
$$;
grant execute on function zz_b110_try(text) to authenticated, anon;

-- The switch, as Mara writes it (the platform's own door).
create or replace function zz_b110_switch(p_scope text, p_kind text, p_org uuid, p_key text, p_state text)
returns uuid
language plpgsql
set search_path = public
as $$
declare
    v uuid;
    v_who text := current_setting('request.jwt.claim.sub', true);
begin
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000001', true);
    v := platform_set_feature_rule(p_scope, p_kind, p_org, p_key, p_state);
    perform set_config('request.jwt.claim.sub', coalesce(v_who, ''), true);
    return v;
end;
$$;

-- An order as the shopper sends it, or the refusal.
create or replace function zz_b110_order(p_slug text, p_lines jsonb, p_fulfilment text default 'pickup',
                                          p_note text default null, p_payment text default 'cash')
returns text
language plpgsql
set search_path = public
as $$
declare
    v_state text;
    v_msg   text;
begin
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000007', true);
    perform place_order(p_slug, p_lines, p_fulfilment, p_note,
                        case when p_fulfilment = 'delivery' then 'Porte bleue' end, null, p_payment,
                        case when p_fulfilment = 'delivery' then 12.371 end,
                        case when p_fulfilment = 'delivery' then -1.521 end);
    return 'ok';
exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return v_state || ': ' || v_msg;
end;
$$;

-- What the engine says, read by the suite as any role.
create or replace function zz_b110_hidden(p_org uuid, p_key text)
returns boolean
language sql
security definer
set search_path = public
as $$ select feature_hidden(p_org, p_key) $$;

\echo ''
\echo '--- TEST 1 (P1): no rule — nothing hidden, no vitrine closed, for every kind ---'
do $$
declare
    k text;
    o uuid;
    v jsonb;
begin
    foreach o in array array['11000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000002',
                             '11000000-0000-0000-0000-000000000003', '11000000-0000-0000-0000-000000000004',
                             '11000000-0000-0000-0000-000000000005']::uuid[] loop
        foreach k in array array['online_orders', 'services', 'delivery', 'online_payment',
                                 'vitrine_plus', 'spots', 'for_sale'] loop
            if zz_b110_hidden(o, k) then
                raise exception 'FAIL: % hidden for % with no rule', k, o;
            end if;
        end loop;
    end loop;
    execute 'set local role anon';
    for v in select to_jsonb(s) from storefront('pro-111') s
             union all select to_jsonb(s) from storefront('ferme-111') s
             union all select to_jsonb(s) from storefront('entraide-111') s
             union all select to_jsonb(s) from storefront('chapelle-111') s loop
        if v->'style' ? 'orders_closed' then
            raise exception 'FAIL: a vitrine says closed with no rule: %', v->>'slug';
        end if;
    end loop;
    if (select count(*) from storefront_products('entraide-111')) <> 1
       or (select count(*) from storefront_products('ferme-111')) <> 9
       or (select wave_merchant from storefront('pro-111')) <> 'M111'
       or not (select (style->>'delivers')::boolean from storefront('basic-111')) then
        raise exception 'FAIL: the vitrines are not what they were with no rule';
    end if;
    execute 'reset role';
    raise notice 'PASS: no rule — none of the 7 vitrine switches hides anything for a shop, a farm, an association or a church; no vitrine closed';
end $$;

\echo ''
\echo '--- TEST 2: each kind is offered its own vitrine switches only ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '11001100-0000-0000-0000-000000000001';
do $$
declare v text;
begin
    select string_agg(b->>'key', ',' order by (b->>'key')) into v
      from jsonb_array_elements(platform_feature_board('retail', null)) b where b->>'grp' = 'Vitrine';
    if v <> 'delivery,online_orders,online_payment,services,spots,vitrine_plus' then
        raise exception 'FAIL: the shop''s vitrine switches: %', v;
    end if;
    select string_agg(b->>'key', ',' order by (b->>'key')) into v
      from jsonb_array_elements(platform_feature_board('farm', null)) b where b->>'grp' = 'Vitrine';
    if v <> 'delivery,for_sale,online_orders,online_payment,services,spots,vitrine_plus' then
        raise exception 'FAIL: the farm''s vitrine switches: %', v;
    end if;
    select string_agg(b->>'key', ',' order by (b->>'key')) into v
      from jsonb_array_elements(platform_feature_board(null, '11000000-0000-0000-0000-000000000005')) b
     where b->>'grp' = 'Vitrine';
    if v <> 'online_orders,online_payment,services,spots,vitrine_plus' then
        raise exception 'FAIL: an association (a church) is offered: %', v;
    end if;
    if zz_b110_try($q$select platform_set_feature_rule('kind', 'association', null, 'delivery', 'hidden')$q$)
       <> 'P0001: Cette fonction n''existe pas pour ce type d''activité.'
       or zz_b110_try($q$select platform_set_feature_rule('kind', 'retail', null, 'for_sale', 'hidden')$q$)
       <> 'P0001: Cette fonction n''existe pas pour ce type d''activité.'
       or zz_b110_try($q$select platform_set_feature_rule('org', null, '11000000-0000-0000-0000-000000000004', 'for_sale', 'hidden')$q$)
       <> 'P0001: Cette fonction n''existe pas pour ce type d''activité.' then
        raise exception 'FAIL: a vitrine switch was offered to a kind that does not have it';
    end if;
    raise notice 'PASS: shops 6 vitrine switches, farms 7 (« À vendre » theirs alone), associations and churches 5 (no delivery) — and the others refused';
end $$;
rollback;

\echo ''
\echo '--- TEST 3 (P2): « Commandes en ligne » hidden — a showcase, every order refused, nothing lost ---'
begin;
do $$
declare
    v_old  uuid;
    v_got  text;
    s      record;
begin
    -- An order sent before the switch.
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000007', true);
    v_old := place_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000001", "quantity": 1}]'::jsonb);
    perform zz_b110_switch('org', null, '11000000-0000-0000-0000-000000000002', 'online_orders', 'hidden');
    perform zz_b110_switch('kind', 'association', null, 'online_orders', 'hidden');
    -- The street: the shelf is there, the vitrine says closed.
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    select * into s from storefront('basic-111');
    if not (s.style->>'orders_closed')::boolean
       or (select count(*) from storefront_products('basic-111')) <> 9
       or not (select (style->>'orders_closed')::boolean from storefront('chapelle-111'))
       or (select style ? 'orders_closed' from storefront('pro-111')) then
        raise exception 'FAIL: the closed vitrine is not a showcase (or another one closed): %', s.style;
    end if;
    execute 'reset role';
    -- Every order refused, to the shopper, in plain French.
    execute 'set local role authenticated';
    foreach v_got in array array[
        zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000001", "quantity": 1}]'),
        zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000009", "quantity": 1}]', 'pickup', 'Samedi'),
        zz_b110_order('entraide-111', '[{"product_id": "11000000-0000-0000-00c0-000000000001", "quantity": 1}]', 'pickup', 'Le 20'),
        zz_b110_order('chapelle-111', '[{"product_id": "11000000-0000-0000-00d0-000000000001", "quantity": 1}]', 'pickup', 'Lundi')] loop
        if v_got <> 'P0001: Commandes fermées pour le moment.' then
            raise exception 'FAIL: an order went through a closed vitrine: %', v_got;
        end if;
    end loop;
    -- Another shop is open.
    if zz_b110_order('pro-111', '[{"product_id": "11000000-0000-0000-00a0-000000000001", "quantity": 1}]') <> 'ok' then
        raise exception 'FAIL: a shop the switch does not touch refused an order';
    end if;
    -- The order sent before goes on: the shop answers it, the shopper may withdraw another.
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000003', true);
    perform decide_order(v_old, 'accepted');
    perform decide_order(v_old, 'ready');
    execute 'reset role';
    if (select status from orders where id = v_old) <> 'ready' then
        raise exception 'FAIL: an order sent before the switch was stuck';
    end if;
    -- Visible again: the vitrine takes orders.
    perform zz_b110_switch('org', null, '11000000-0000-0000-0000-000000000002', 'online_orders', 'default');
    execute 'set local role authenticated';
    if zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000001", "quantity": 1}]') <> 'ok' then
        raise exception 'FAIL: the vitrine stayed closed once visible';
    end if;
    execute 'reset role';
    execute 'set local role anon';
    if (select style ? 'orders_closed' from storefront('basic-111')) then
        raise exception 'FAIL: the vitrine still says closed';
    end if;
    execute 'reset role';
    raise notice 'PASS: « Commandes en ligne » hidden — the vitrine shows its shelf and « orders_closed », every order and booking refused « Commandes fermées pour le moment. » (a shop by its own switch, an association and a church by their kind''s), an order sent before goes on, another shop untouched; visible again it orders';
end $$;
rollback;

\echo ''
\echo '--- TEST 4 (P2): « Services et réservations » hidden — off the street, no booking, no new service ---'
begin;
do $$
declare v_got text;
begin
    perform zz_b110_switch('kind', 'retail', null, 'services', 'hidden');
    perform zz_b110_switch('org', null, '11000000-0000-0000-0000-000000000004', 'services', 'hidden');
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    if exists (select 1 from storefront_products('basic-111') where is_service)
       or exists (select 1 from storefront_products('pro-111') where is_service)
       or (select count(*) from storefront_products('basic-111')) <> 8
       or exists (select 1 from storefront_stock('basic-111') where id = '11000000-0000-0000-00b0-000000000009')
       or exists (select 1 from search_products('montage 111'))
       or exists (select 1 from search_products('bâches 111'))
       or exists (select 1 from storefront_previews(array['basic-111', 'entraide-111']) where name like 'Montage%' or name like 'Bâches%')
       or storefront_photo_allowed('b110/montage.jpg')
       or storefront_photo_allowed('b110/baches.jpg')
       or not storefront_photo_allowed('b110/savon-1.jpg') then
        raise exception 'FAIL: a hidden service is still on the street';
    end if;
    -- The association's vitrine opens on an empty shelf, never an error.
    if (select count(*) from storefront('entraide-111')) <> 1
       or (select count(*) from storefront_products('entraide-111')) <> 0 then
        raise exception 'FAIL: the association''s vitrine is not a page with nothing to book';
    end if;
    -- The farm keeps its services (another kind).
    if not exists (select 1 from storefront_products('ferme-111') where is_service) then
        raise exception 'FAIL: the shops'' switch reached the farm';
    end if;
    execute 'reset role';
    execute 'set local role authenticated';
    foreach v_got in array array[
        zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000009", "quantity": 1}]', 'pickup', 'Samedi'),
        zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000009", "quantity": 1},
                                     {"product_id": "11000000-0000-0000-00b0-000000000001", "quantity": 1}]'),
        zz_b110_order('entraide-111', '[{"product_id": "11000000-0000-0000-00c0-000000000001", "quantity": 1}]', 'pickup', 'Le 20')] loop
        if v_got <> 'P0001: Les réservations sont fermées pour le moment.' then
            raise exception 'FAIL: a hidden service was booked: %', v_got;
        end if;
    end loop;
    if zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000001", "quantity": 1}]') <> 'ok'
       or zz_b110_order('ferme-111', '[{"product_id": "11000000-0000-0000-00f0-000000000009", "quantity": 1}]', 'pickup', 'Lundi') <> 'ok' then
        raise exception 'FAIL: an article, or another kind''s service, was refused';
    end if;
    -- The owner: no new service, no article turned into one; the till and
    -- « tout mettre en vente » go on.
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000003', true);
    if zz_b110_try($q$select ensure_product('11000000-0000-0000-0000-000000000002', 'Réparation 111', 3000, p_is_service => true)$q$)
       <> 'MA002: Cette fonction n''est pas disponible pour votre activité.'
       or zz_b110_try($q$update products set is_service = true, quantity = 0 where id = '11000000-0000-0000-00b0-000000000008'$q$)
       not like 'MA002:%' then
        raise exception 'FAIL: a service was created while hidden';
    end if;
    if zz_b110_try($q$select ensure_product('11000000-0000-0000-0000-000000000002', 'Bougie 111', 300)$q$) <> 'ok'
       or zz_b110_try($q$select publish_all_products('11000000-0000-0000-0000-000000000002')$q$) <> 'ok'
       or zz_b110_try($q$update products set is_service = true, sale_price = 2500 where id = '11000000-0000-0000-00b0-000000000009'$q$) <> 'ok' then
        raise exception 'FAIL: an article, publishing, or editing a service already there was refused';
    end if;
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000001', true);
    if zz_b110_try($q$select ensure_product('11000000-0000-0000-0000-000000000004', 'Salle 111', 9000, p_is_service => true)$q$)
       not like 'MA002:%' then
        raise exception 'FAIL: Mara inside the association created a hidden service';
    end if;
    execute 'reset role';
    -- Visible again.
    perform zz_b110_switch('kind', 'retail', null, 'services', 'default');
    execute 'set local role authenticated';
    if zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000009", "quantity": 1}]', 'pickup', 'Samedi') <> 'ok' then
        raise exception 'FAIL: the service stayed closed once visible';
    end if;
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000003', true);
    if zz_b110_try($q$select ensure_product('11000000-0000-0000-0000-000000000002', 'Réparation 111', 3000, p_is_service => true)$q$) <> 'ok' then
        raise exception 'FAIL: no service could be created once visible';
    end if;
    execute 'reset role';
    raise notice 'PASS: « Services et réservations » hidden — off the shelf, the stock, the search, the previews and the photo gate; a booking (alone or in a basket) refused « Les réservations sont fermées pour le moment. »; no service created or converted (MA002, Mara inside too); articles, publishing, the farm''s services untouched; an association''s vitrine opens on an empty shelf; visible again it books';
end $$;
rollback;

\echo ''
\echo '--- TEST 5 (P2, P3): « Livraison » hidden — pickup only, the rates kept still; a paid Pro keeps it ---'
begin;
do $$
declare v_got text;
begin
    -- Mara's gift is no payment: the Basic shop can lose it; the Pro shop
    -- pays and cannot.
    if zz_b110_try($q$select zz_b110_switch('org', null, '11000000-0000-0000-0000-000000000001', 'delivery', 'hidden')$q$)
       <> 'P0001: Fonction payée par l''activité : elle ne peut pas être masquée.' then
        raise exception 'FAIL: a paid delivery was hidden';
    end if;
    perform zz_b110_switch('kind', 'retail', null, 'delivery', 'hidden');
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    if (select (style->>'delivers')::boolean from storefront('basic-111'))
       or delivery_quote('basic-111', 12.361, -1.531) is not null
       or (select fee from delivery_check('basic-111', 12.361, -1.531)) is not null
       or not (select (style->>'delivers')::boolean from storefront('pro-111'))
       or delivery_quote('pro-111', 12.371, -1.521) is null then
        raise exception 'FAIL: the vitrine still offers a hidden delivery, or the paid one lost it';
    end if;
    execute 'reset role';
    execute 'set local role authenticated';
    v_got := zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000001", "quantity": 1}]', 'delivery');
    if v_got <> 'P0001: La livraison n''est pas proposée pour le moment. Choisissez le retrait.' then
        raise exception 'FAIL: a hidden delivery was ordered: %', v_got;
    end if;
    if zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000001", "quantity": 1}]') <> 'ok'
       or zz_b110_order('pro-111', '[{"product_id": "11000000-0000-0000-00a0-000000000001", "quantity": 1}]', 'delivery') <> 'ok' then
        raise exception 'FAIL: pickup, or the paid shop''s delivery, was refused';
    end if;
    -- The owner: the numbers do not move; the settings' save (the same
    -- numbers sent back, the included distance never set read 0) passes.
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000003', true);
    foreach v_got in array array[
        $q$select set_delivery_rates('11000000-0000-0000-0000-000000000002', 700, 150)$q$,
        $q$select set_delivery_reach('11000000-0000-0000-0000-000000000002', 8)$q$,
        $q$select set_delivery_included_km('11000000-0000-0000-0000-000000000002', 3)$q$] loop
        if zz_b110_try(v_got) <> 'MA002: Cette fonction n''est pas disponible pour votre activité.' then
            raise exception 'FAIL: % changed a hidden delivery: %', v_got, zz_b110_try(v_got);
        end if;
    end loop;
    if zz_b110_try($q$select set_delivery_rates('11000000-0000-0000-0000-000000000002', 500, 100)$q$) <> 'ok'
       or zz_b110_try($q$select set_delivery_reach('11000000-0000-0000-0000-000000000002', 20)$q$) <> 'ok'
       or zz_b110_try($q$select set_delivery_included_km('11000000-0000-0000-0000-000000000002', 0)$q$) <> 'ok' then
        raise exception 'FAIL: an unchanged save was refused';
    end if;
    -- No cauris for it either (104's door, through the catalog's Pro tool).
    if zz_b110_try($q$select spend_cauris('11000000-0000-0000-0000-000000000002', 'delivery')$q$) not like 'MA002:%' then
        raise exception 'FAIL: cauris were spent on a hidden delivery';
    end if;
    execute 'reset role';
    perform zz_b110_switch('kind', 'retail', null, 'delivery', 'default');
    execute 'set local role authenticated';
    if zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000001", "quantity": 1}]', 'delivery') <> 'ok' then
        raise exception 'FAIL: delivery stayed closed once visible';
    end if;
    execute 'reset role';
    raise notice 'PASS: « Livraison » hidden — no « delivers », no quote, no fee, a delivery order refused « La livraison n''est pas proposée pour le moment. Choisissez le retrait. », the rates, reach and distance kept (MA002; an unchanged save passes), no cauris spent; the paid Pro shop keeps delivering and cannot be switched; visible again it delivers';
end $$;
rollback;

\echo ''
\echo '--- TEST 6 (P2, P3): « Paiement en ligne » hidden — cash only on the vitrine; 090''s tick still holds ---'
begin;
do $$
declare v_got text;
begin
    perform zz_b110_switch('kind', 'association', null, 'online_payment', 'hidden');
    perform zz_b110_switch('org', null, '11000000-0000-0000-0000-000000000002', 'online_payment', 'hidden');
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    if (select wave_merchant from storefront('entraide-111')) is not null
       or (select wave_merchant from storefront('chapelle-111')) is not null
       or (select wave_merchant from storefront('basic-111')) is not null
       or (select wave_merchant from storefront('pro-111')) <> 'M111' then
        raise exception 'FAIL: the vitrine still offers a hidden Wave (or the paid one lost it)';
    end if;
    execute 'reset role';
    execute 'set local role authenticated';
    foreach v_got in array array[
        zz_b110_order('entraide-111', '[{"product_id": "11000000-0000-0000-00c0-000000000001", "quantity": 1}]', 'pickup', 'Le 20', 'wave'),
        zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000001", "quantity": 1}]', 'pickup', null, 'wave')] loop
        if v_got <> 'P0001: Paiement en espèces uniquement pour le moment.' then
            raise exception 'FAIL: Wave was taken while hidden: %', v_got;
        end if;
    end loop;
    if zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000001", "quantity": 1}]') <> 'ok'
       or zz_b110_order('pro-111', '[{"product_id": "11000000-0000-0000-00a0-000000000001", "quantity": 1}]', 'pickup', null, 'wave') <> 'ok' then
        raise exception 'FAIL: cash, or the paid shop''s Wave, was refused';
    end if;
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000003', true);
    if (wave_terms('11000000-0000-0000-0000-000000000002')->>'shop_ready')::boolean then
        raise exception 'FAIL: a shop with Wave hidden is « ready »';
    end if;
    if zz_b110_try($q$select set_wave_payout_number('11000000-0000-0000-0000-000000000002', '70111999')$q$)
       <> 'MA002: Cette fonction n''est pas disponible pour votre activité.'
       or zz_b110_try($q$select set_wave_payout_number('11000000-0000-0000-0000-000000000002', '+22670111001')$q$) <> 'ok' then
        raise exception 'FAIL: the payout number moved while hidden (or an unchanged save failed)';
    end if;
    -- The till's own Wave handle is not a vitrine feature.
    if zz_b110_try($q$select set_org_wave('11000000-0000-0000-0000-000000000002', 'M111-caisse')$q$) <> 'ok' then
        raise exception 'FAIL: the till''s Wave handle was refused';
    end if;
    execute 'reset role';
    -- A Wave checkout for an order, whoever writes it.
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000007', true);
    if zz_b110_try($q$insert into wave_payments (kind, org_id, amount, payer_id)
                      values ('order', '11000000-0000-0000-0000-000000000002', 100, '11001100-0000-0000-0000-000000000007')$q$)
       <> 'P0001: Paiement en espèces uniquement pour le moment.' then
        raise exception 'FAIL: a Wave checkout began for a hidden online payment';
    end if;
    -- Both must say yes: visible again but Mara's tick off — still cash.
    perform zz_b110_switch('org', null, '11000000-0000-0000-0000-000000000002', 'online_payment', 'default');
    update orgs set wave_allowed = false where id = '11000000-0000-0000-0000-000000000002';
    execute 'set local role authenticated';
    if zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000001", "quantity": 1}]', 'pickup', null, 'wave')
       <> 'P0001: Paiement en espèces uniquement pour le moment.' then
        raise exception 'FAIL: 090''s tick no longer holds';
    end if;
    execute 'reset role';
    update orgs set wave_allowed = true where id = '11000000-0000-0000-0000-000000000002';
    execute 'set local role authenticated';
    if zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000001", "quantity": 1}]', 'pickup', null, 'wave') <> 'ok' then
        raise exception 'FAIL: Wave stayed closed with both saying yes';
    end if;
    execute 'reset role';
    raise notice 'PASS: « Paiement en ligne » hidden — Wave off the vitrine (a shop by its switch, an association and a church by their kind''s), a Wave order and a Wave checkout refused « Paiement en espèces uniquement pour le moment. », not « ready », the payout kept (MA002), the till''s handle free; the paid Pro shop keeps Wave; Wave needs both 090''s tick and the switch';
end $$;
rollback;

\echo ''
\echo '--- TEST 7 (P2, P3): « Vitrine Plus » hidden — the free basics only; a paid Pro keeps its dressing ---'
begin;
do $$
declare v jsonb;
begin
    if zz_b110_try($q$select zz_b110_switch('org', null, '11000000-0000-0000-0000-000000000001', 'vitrine_plus', 'hidden')$q$)
       <> 'P0001: Fonction payée par l''activité : elle ne peut pas être masquée.' then
        raise exception 'FAIL: a paid Vitrine Plus was hidden';
    end if;
    -- Before: the gifted Basic shop shows its Pro dressing.
    execute 'set local role anon';
    if (select style->>'layout' from storefront('basic-111')) <> 'large' then
        raise exception 'FAIL: the gift did not dress the vitrine to begin with';
    end if;
    execute 'reset role';
    perform zz_b110_switch('kind', 'retail', null, 'vitrine_plus', 'hidden');
    execute 'set local role anon';
    select style into v from storefront('basic-111');
    if v ? 'layout' or v ? 'hide_out_of_stock' or v->>'tagline' <> 'Habillée'
       or (select style->>'layout' from storefront('pro-111')) <> 'large' then
        raise exception 'FAIL: the vitrine is not down to its free basics (or the paid one lost its dressing): %', v;
    end if;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000003', true);
    execute 'set local role authenticated';
    if zz_b110_try($q$select set_storefront_style('11000000-0000-0000-0000-000000000002', '{"accent": "#654321"}'::jsonb)$q$)
       <> 'MA002: Cette fonction n''est pas disponible pour votre activité.' then
        raise exception 'FAIL: a Vitrine Plus colour was set while hidden (or offered Pro)';
    end if;
    perform set_storefront_style('11000000-0000-0000-0000-000000000002',
        '{"tagline": "Nouvelle", "accent": "#2E7D5B", "layout": "menu"}'::jsonb);
    execute 'reset role';
    select storefront_style into v from orgs where id = '11000000-0000-0000-0000-000000000002';
    -- The basics written, the Pro arrangement kept as it was (for the day it shows again).
    if v->>'tagline' <> 'Nouvelle' or v->>'layout' <> 'large' or v->>'accent' <> '#2E7D5B' then
        raise exception 'FAIL: the dressing saved while hidden is wrong: %', v;
    end if;
    -- The kind's default presentation (107), on a vitrine never dressed: its
    -- free colour, not its layout, on a hidden Vitrine Plus.
    insert into kind_settings (kind, key, value) values
        ('retail', 'vitrine_default', '{"layout": "list", "accent": "#2E7D5B"}')
    on conflict (kind, key) do update set value = excluded.value;
    update orgs set storefront_style = '{}' where id = '11000000-0000-0000-0000-000000000002';
    v := vitrine_default_style('11000000-0000-0000-0000-000000000002');
    if v ? 'layout' or v->>'accent' <> '#2E7D5B' then
        raise exception 'FAIL: the kind''s default gave a hidden Vitrine Plus its layout: %', v;
    end if;
    perform zz_b110_switch('kind', 'retail', null, 'vitrine_plus', 'default');
    if vitrine_default_style('11000000-0000-0000-0000-000000000002')->>'layout' <> 'list' then
        raise exception 'FAIL: the kind''s default lost its layout once visible';
    end if;
    update orgs set storefront_style = '{"tagline": "Habillée", "layout": "large"}'
     where id = '11000000-0000-0000-0000-000000000002';
    execute 'set local role anon';
    if (select style->>'layout' from storefront('basic-111')) <> 'large' then
        raise exception 'FAIL: the dressing did not come back once visible';
    end if;
    execute 'reset role';
    raise notice 'PASS: « Vitrine Plus » hidden — the gifted vitrine shows the free basics, the Pro part refused (MA002, no Pro door) while the basics save and the arrangement is kept; the paid Pro shop keeps its dressing and cannot be switched; visible again the dressing is back';
end $$;
rollback;

\echo ''
\echo '--- TEST 8 (P2, P3): « Mettre en avant » hidden — nothing asked, paid or read; a spot paid for runs to its end ---'
begin;
do $$
declare v_got text;
begin
    -- The Pro shop's spot runs: paid, never hidden.
    if zz_b110_try($q$select zz_b110_switch('org', null, '11000000-0000-0000-0000-000000000001', 'spots', 'hidden')$q$)
       <> 'P0001: Fonction payée par l''activité : elle ne peut pas être masquée.' then
        raise exception 'FAIL: a running spot was hidden';
    end if;
    perform zz_b110_switch('kind', 'retail', null, 'spots', 'hidden');
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    if exists (select 1 from storefront_featured() where shop_slug = 'basic-111')
       or not exists (select 1 from storefront_spotlights() where slug = 'pro-111') then
        raise exception 'FAIL: Mara''s pick stayed « À la une », or the paid spot stopped';
    end if;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000003', true);
    execute 'set local role authenticated';
    foreach v_got in array array[
        $q$select request_promotion('11000000-0000-0000-0000-000000000002', null, 7)$q$,
        $q$select claim_promotion_paid('11000000-0000-0000-0000-0000000000e2', 'Wave')$q$,
        $q$select * from my_promotions('11000000-0000-0000-0000-000000000002')$q$] loop
        if zz_b110_try(v_got) <> 'MA002: Cette fonction n''est pas disponible pour votre activité.' then
            raise exception 'FAIL: % passed a hidden « Mettre en avant »: %', v_got, zz_b110_try(v_got);
        end if;
    end loop;
    execute 'reset role';
    if zz_b110_try($q$insert into wave_payments (kind, org_id, amount, payer_id)
                      values ('spot', '11000000-0000-0000-0000-000000000002', 2500, '11001100-0000-0000-0000-000000000003')$q$)
       not like 'MA002:%' then
        raise exception 'FAIL: a Wave payment began for a hidden spot';
    end if;
    -- The paid one ends: the kind's switch now applies to it too.
    update promotions set ends_at = now() - interval '1 minute' where id = '11000000-0000-0000-0000-0000000000e1';
    if not zz_b110_hidden('11000000-0000-0000-0000-000000000001', 'spots') then
        raise exception 'FAIL: the switch did not apply once the paid spot ended';
    end if;
    perform zz_b110_switch('kind', 'retail', null, 'spots', 'default');
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000003', true);
    execute 'set local role authenticated';
    if zz_b110_try($q$select * from my_promotions('11000000-0000-0000-0000-000000000002')$q$) <> 'ok'
       or zz_b110_try($q$select claim_promotion_paid('11000000-0000-0000-0000-0000000000e2', 'Wave')$q$) <> 'ok' then
        raise exception 'FAIL: « Mettre en avant » stayed closed once visible';
    end if;
    execute 'reset role';
    raise notice 'PASS: « Mettre en avant » hidden — no spot asked for, paid (« J''ai payé » or Wave) or read (MA002), Mara''s pick off « À la une »; a spot running is paid: never hidden, it runs to its end, then the switch applies; visible again it opens';
end $$;
rollback;

\echo ''
\echo '--- TEST 9 (P2): « À vendre sur la vitrine » hidden — the farm''s articles off its vitrine, its services stay ---'
begin;
do $$
declare v_got text;
begin
    perform zz_b110_switch('org', null, '11000000-0000-0000-0000-000000000003', 'for_sale', 'hidden');
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    if exists (select 1 from storefront_products('ferme-111') where not is_service)
       or not exists (select 1 from storefront_products('ferme-111') where is_service)
       or exists (select 1 from search_products('œufs 111'))
       or exists (select 1 from storefront_previews(array['ferme-111']) where name like 'Œufs%')
       or storefront_photo_allowed('b110/oeufs-1.jpg')
       or (select count(*) from storefront('ferme-111')) <> 1
       or (select count(*) from storefront_products('basic-111')) <> 9 then
        raise exception 'FAIL: the farm''s articles are still on the street (or its vitrine, or a shop, changed)';
    end if;
    execute 'reset role';
    execute 'set local role authenticated';
    v_got := zz_b110_order('ferme-111', '[{"product_id": "11000000-0000-0000-00f0-000000000001", "quantity": 1}]');
    if v_got <> 'P0001: Cette ferme ne vend pas ses produits en ligne pour le moment.' then
        raise exception 'FAIL: a farm article was ordered while hidden: %', v_got;
    end if;
    if zz_b110_order('ferme-111', '[{"product_id": "11000000-0000-0000-00f0-000000000009", "quantity": 1}]', 'pickup', 'Lundi') <> 'ok'
       or zz_b110_order('basic-111', '[{"product_id": "11000000-0000-0000-00b0-000000000001", "quantity": 1}]') <> 'ok' then
        raise exception 'FAIL: the farm''s service, or a shop''s article, was refused';
    end if;
    -- The farm still keeps what it sells at the farm (« À vendre » is its list).
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000004', true);
    if zz_b110_try($q$select ensure_product('11000000-0000-0000-0000-000000000003', 'Poulet 111', 3500)$q$) <> 'ok' then
        raise exception 'FAIL: the farm could not add what it sells';
    end if;
    execute 'reset role';
    perform zz_b110_switch('org', null, '11000000-0000-0000-0000-000000000003', 'for_sale', 'default');
    execute 'set local role authenticated';
    if zz_b110_order('ferme-111', '[{"product_id": "11000000-0000-0000-00f0-000000000001", "quantity": 1}]') <> 'ok' then
        raise exception 'FAIL: the farm''s articles stayed off once visible';
    end if;
    execute 'reset role';
    raise notice 'PASS: « À vendre sur la vitrine » hidden — the farm''s articles off its shelf, the search, the previews and the photo gate, an order for one refused « Cette ferme ne vend pas ses produits en ligne pour le moment. »; its services, its own list and every shop untouched; visible again it sells';
end $$;
rollback;

\echo ''
\echo '--- TEST 10 (P3): only the platform switches; logged, the owner told, undone ---'
begin;
do $$
declare
    a uuid;
    n int;
begin
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000003', true);
    execute 'set local role authenticated';
    if zz_b110_try($q$select platform_set_feature_rule('org', null, '11000000-0000-0000-0000-000000000002', 'online_orders', 'hidden')$q$)
       <> 'P0001: Réservé à la plateforme' then
        raise exception 'FAIL: an owner switched their own vitrine';
    end if;
    execute 'reset role';
    a := zz_b110_switch('org', null, '11000000-0000-0000-0000-000000000002', 'online_orders', 'hidden');
    select count(*) into n from notifications
     where recipient_id = '11001100-0000-0000-0000-000000000003' and kind = 'feature_rule'
       and message = 'Mara a masqué « Commandes en ligne » pour votre activité.'
       and params->>'feature' = 'online_orders';
    if n <> 1 or (select summary from platform_actions where id = a)
                 <> '« Commandes en ligne » masqué — Basic 111' then
        raise exception 'FAIL: the switch was not logged or the owner not told (% bells)', n;
    end if;
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000003', true);
    execute 'set local role authenticated';
    if not (feature_states('11000000-0000-0000-0000-000000000002')->'hidden') ? 'online_orders' then
        raise exception 'FAIL: feature_states does not tell the owner';
    end if;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '11001100-0000-0000-0000-000000000001', true);
    execute 'set local role authenticated';
    perform platform_undo(a);
    execute 'reset role';
    if zz_b110_hidden('11000000-0000-0000-0000-000000000002', 'online_orders') then
        raise exception 'FAIL: the undo did not open the vitrine again';
    end if;
    raise notice 'PASS: an owner cannot switch; Mara''s switch is logged « « Commandes en ligne » masqué — Basic 111 », the owner told, feature_states says it, and the undo opens the vitrine again';
end $$;
rollback;

\echo ''
\echo '--- TEST 11 (P2): no dead switch; the engine closed; the street still answers a stranger ---'
do $$
declare v_missing text;
begin
    -- Each catalog key has a server door: a function or trigger calling
    -- feature_guard or vitrine_refuse with it, or a 104 table trigger.
    select string_agg(c.key, ', ') into v_missing
      from feature_catalog c
     where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                        where n.nspname = 'public'
                          and (p.prosrc like '%feature_guard(%''' || c.key || '''%'
                               or p.prosrc like '%vitrine_refuse(%''' || c.key || '''%'))
       and not exists (select 1 from pg_trigger t
                        where t.tgfoid = 'trg_feature_hidden'::regproc
                          and split_part(encode(t.tgargs, 'escape'), '\000', 1) = c.key);
    if v_missing is not null then
        raise exception 'FAIL: dead switches: %', v_missing;
    end if;
    -- And each vitrine key changes what the street is served: named by a
    -- street function (or the engine it reads).
    select string_agg(k, ', ') into v_missing
      from unnest(array['online_orders', 'services', 'delivery', 'online_payment',
                        'vitrine_plus', 'spots', 'for_sale']) k
     where not exists (select 1 from pg_proc p
                        where p.proname in ('storefront', 'storefront_products', 'storefront_featured',
                                            'storefront_spotlights', 'org_delivers', 'delivery_fee',
                                            'vitrine_shows', 'vitrine_plus_on', 'wave_terms')
                          and p.prosrc like '%''' || k || '''%');
    if v_missing is not null then
        raise exception 'FAIL: a vitrine switch the street never reads: %', v_missing;
    end if;
    if has_function_privilege('anon', 'vitrine_refuse(uuid, text)', 'execute')
       or has_function_privilege('anon', 'vitrine_shows(uuid, boolean)', 'execute')
       or has_function_privilege('anon', 'vitrine_plus_on(uuid)', 'execute')
       or has_function_privilege('authenticated', 'vitrine_refuse(uuid, text)', 'execute')
       or has_function_privilege('authenticated', 'vitrine_shows(uuid, boolean)', 'execute')
       or has_function_privilege('authenticated', 'vitrine_plus_on(uuid)', 'execute')
       or has_function_privilege('authenticated', 'trg_order_closed_switch()', 'execute')
       or has_function_privilege('anon', 'trg_orgs_vitrine_switch()', 'execute') then
        raise exception 'FAIL: the new engine is open to the street or the app';
    end if;
    if not has_function_privilege('anon', 'storefront(text)', 'execute')
       or not has_function_privilege('anon', 'storefront_products(text)', 'execute')
       or not has_function_privilege('anon', 'storefront_stock(text)', 'execute')
       or not has_function_privilege('anon', 'search_products(text, double precision, double precision)', 'execute')
       or not has_function_privilege('anon', 'storefront_featured()', 'execute')
       or not has_function_privilege('anon', 'storefront_previews(text[])', 'execute')
       or not has_function_privilege('anon', 'storefront_spotlights()', 'execute')
       or not has_function_privilege('anon', 'storefront_photo_allowed(text)', 'execute')
       or not has_function_privilege('anon', 'delivery_quote(text, double precision, double precision)', 'execute') then
        raise exception 'FAIL: a street function lost its grant to the street';
    end if;
    raise notice 'PASS: every catalog key has a server door and every vitrine key is read by the street; the new engine is closed to anon and the app''s roles; the street''s functions still answer a stranger';
end $$;
begin;
set local role anon;
do $$
declare v int;
begin
    select count(*) into v from storefront('pro-111');
    select count(*) into v from storefront_products('ferme-111');
    select count(*) into v from storefront_stock('ferme-111');
    select count(*) into v from search_products('pagne', 12.36, -1.53);
    select count(*) into v from storefront_featured();
    select count(*) into v from storefront_previews(array['pro-111', 'ferme-111']);
    select count(*) into v from storefront_spotlights();
    perform storefront_photo_allowed('b110/savon-1.jpg');
    perform delivery_quote('pro-111', 12.371, -1.521);
    raise notice 'PASS: a stranger reads every rebuilt street function';
end $$;
rollback;

update platform_settings p set value = s.value from b110_saved s where p.key = s.key;
drop function zz_b110_try(text);
drop function zz_b110_switch(text, text, uuid, text, text);
drop function zz_b110_order(text, jsonb, text, text, text);
drop function zz_b110_hidden(uuid, text);

\echo ''
\echo '=== test_batch110.sql: all checks passed ==='
