-- ============================================================
-- test_batch146.sql — batch 151 (146): « Protections contre la fraude ».
-- Phone block 146.
--
-- The claims:
--   1. installed twice, the same: the four settings (3, 2, 50 000, 5 000),
--      the two tables under RLS with the policies meant, the triggers, the
--      doors' security (block/unblock INVOKER, the rest DEFINER), every
--      new function's search path pinned;
--   2. order limits, for a shop, a farm and an association: a new account
--      (no finished order) holds 2 open orders across every business, the
--      3rd refused; once one is finished, 3 open at one business, the 4th
--      refused there and taken elsewhere; a passed booking's slot and an
--      order older than 7 days not counted; 0 turns each rule off; the
--      business, a migration or a seed inserting an order are not asked;
--   3. « Bloquer ce client »: the owner blocks from an order (shop, farm,
--      association), the shopper's next order there refused in words that
--      never say « bloqué » (each kind's own), taken elsewhere; an
--      employee, another business's owner and the shopper themself
--      cannot block; nobody but the business's admins sees a block, the
--      shopper included; no block of a stranger who never ordered there,
--      nor of oneself, nor written by hand for another business; unblocked,
--      the order is taken again; each block and unblock in the business's
--      Activité (audit_log);
--   4. the courier's cash cap: an approved courier takes cash orders up
--      to 50 000 FCFA held, the next refused, a Wave-paid order taken, one
--      above the cap alone refused in its own words; the shop's « argent
--      reçu » frees the room; an order in euros not capped; 0 = no cap;
--      courier_cash_status says held and cap per money, a courier's alone;
--   5. a return of a sale is an owner's or an administrator's: an
--      employee (the cashier) refused, the owner taken, another business
--      refused;
--   6. « Clôturer la caisse »: a cashier closes the shop's till blind —
--      counted against the server's expected (the float, counter sales and
--      pickup orders paid cash, less cash returns; Wave and a delivered
--      order's cash not in it); the gap kept; a second closing a new row;
--      the owner reads every closing, the cashier their own, another
--      business and a shopper nothing; nobody writes the table by hand;
--      a farm closes too, an association and an observer refused, a bad
--      day, offset or amount refused; journaled;
--   7. Mara's queue: a business with 3 blocks, a courier over the cap and
--      a closing whose gap reaches 5 000 FCFA listed, with the open
--      reports and the couriers waiting counted; the counter in « À
--      faire »; nothing for anybody but the platform;
--   8. Réglages: the four settings within their ranges (0–50 orders, 0 or
--      1 000–10 000 000 FCFA), journaled; the platform's alone;
--   9. the doors: nothing for anon (functions and tables), the internal
--      helpers nobody's, the app's doors authenticated's.
-- Names: brand-like businesses, « Cliente 1 », « Client 2 »; Ouagadougou.
-- Wrapped in one transaction rolled back, so it runs twice the same.
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
grant usage on schema auth to anon, authenticated;
-- As the other suites: every table to the app's role, so RLS is the wall —
-- then 146 again, twice: what it grants and revokes is what is tested.
grant select, insert, update, delete on all tables in schema public to authenticated;
\i database/migrations/146_fraud_guards.sql
\i database/migrations/146_fraud_guards.sql

begin;

update platform_settings set value = '1'
 where key in ('vitrine_min_items', 'vitrine_min_items_association');
update platform_settings set value = 'false'
 where key in ('order_phone_verified', 'create_phone_verified', 'courier_phone_verified', 'courier_licence_required');

\set mara    '''14614614-0000-0000-0000-000000000001'''
\set sowner  '''14614614-0000-0000-0000-000000000002'''
\set fowner  '''14614614-0000-0000-0000-000000000003'''
\set aowner  '''14614614-0000-0000-0000-000000000004'''
\set semp    '''14614614-0000-0000-0000-000000000005'''
\set c1      '''14614614-0000-0000-0000-000000000006'''
\set c2      '''14614614-0000-0000-0000-000000000007'''
\set c3      '''14614614-0000-0000-0000-000000000008'''
\set rider   '''14614614-0000-0000-0000-000000000009'''
\set bowner  '''14614614-0000-0000-0000-000000000010'''
\set watcher '''14614614-0000-0000-0000-000000000011'''
\set c4      '''14614614-0000-0000-0000-000000000012'''
\set shop    '''14600000-0000-0000-0000-000000000001'''
\set farm    '''14600000-0000-0000-0000-000000000002'''
\set assoc   '''14600000-0000-0000-0000-000000000003'''
\set bazar   '''14600000-0000-0000-0000-000000000004'''
\set eshop   '''14600000-0000-0000-0000-000000000005'''

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    (:mara,    '+22614600001', 'mara146@example.com',   '{"full_name": "Équipe Mara 146"}',            now()),
    (:sowner,  '+22614600002', 'shop146@example.com',   '{"full_name": "Gérance Kiosque Nova"}',       now() - interval '1 year'),
    (:fowner,  '+22614600003', 'farm146@example.com',   '{"full_name": "Gérance Ferme Horizon"}',      now() - interval '1 year'),
    (:aowner,  '+22614600004', 'asso146@example.com',   '{"full_name": "Trésorerie Fondation Espoir"}', now() - interval '1 year'),
    (:semp,    '+22614600005', 'caisse146@example.com', '{"full_name": "Caisse Kiosque Nova"}',        now() - interval '1 year'),
    (:c1,      '+22614600006', 'c1-146@example.com',    '{"full_name": "Cliente 1"}',                  now()),
    (:c2,      '+22614600007', 'c2-146@example.com',    '{"full_name": "Client 2"}',                   now()),
    (:c3,      '+22614600008', 'c3-146@example.com',    '{"full_name": "Client 3"}',                   now()),
    (:rider,   '+22614600009', 'rider146@example.com',  '{"full_name": "Livreur Rapide 146"}',         now() - interval '1 year'),
    (:bowner,  '+22614600010', 'bazar146@example.com',  '{"full_name": "Gérance Bazar Étoile"}',       now() - interval '1 year'),
    (:watcher, '+22614600011', 'obs146@example.com',    '{"full_name": "Regard Kiosque Nova"}',        now() - interval '1 year'),
    (:c4,      '+22614600012', 'c4-146@example.com',    '{"full_name": "Client 4"}',                   now());
update profiles set is_platform_admin = true where id = :mara;
update profiles p set phone = u.phone from auth.users u where u.id = p.id and p.phone is null;

insert into orgs (id, name, slug, profile, default_currency, plan, storefront_enabled, storefront_blurb, city) values
    (:shop,  'Kiosque Nova',     'kiosque-nova-146',     'retail',      'XOF', 'free', true, 'Bienvenue', 'Ouagadougou'),
    (:farm,  'Ferme Horizon',    'ferme-horizon-146',    'farm',        'XOF', 'free', true, 'Bienvenue', 'Ouagadougou'),
    (:assoc, 'Fondation Espoir', 'fondation-espoir-146', 'association', 'XOF', 'free', true, 'Bienvenue', 'Ouagadougou'),
    (:bazar, 'Bazar Étoile',     'bazar-etoile-146',     'retail',      'XOF', 'free', true, 'Bienvenue', 'Ouagadougou'),
    (:eshop, 'Maison Lumière',   'maison-lumiere-146',   'retail',      'EUR', 'free', true, 'Bienvenue', 'Ouagadougou');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :sowner,  'owner',    'org', :shop,  'full'),
    (:shop,  :semp,    'employee', 'org', :shop,  'full'),
    (:shop,  :watcher, 'observer', 'org', :shop,  'full'),
    (:farm,  :fowner,  'owner',    'org', :farm,  'full'),
    (:assoc, :aowner,  'owner',    'org', :assoc, 'full'),
    (:bazar, :bowner,  'owner',    'org', :bazar, 'full'),
    (:eshop, :bowner,  'owner',    'org', :eshop, 'full');
-- Delivery and Wave are Mara Pro's (081, 085): all five on Pro.
update orgs set plan = 'pro', plan_until = current_date + 30
 where id in (:shop, :farm, :assoc, :bazar, :eshop);
-- The bazar takes Wave (090's « Wave autorisé »).
update orgs set wave_allowed = true, wave_merchant = 'https://pay.wave.com/m/bazar-146' where id = :bazar;
select seed_retail_accounts(:shop);
select seed_farm_accounts(:farm);
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published) values
    ('146aaaaa-0000-0000-0000-000000000001', :shop,  'Savon Karité 146',     1000, 600, 500, true, true),
    ('146aaaaa-0000-0000-0000-000000000002', :farm,  'Plateau d''œufs 146',  2500, 0,   500, true, true),
    ('146aaaaa-0000-0000-0000-000000000003', :assoc, 'T-shirt Espoir 146',   3000, 0,   500, true, true),
    ('146aaaaa-0000-0000-0000-000000000004', :bazar, 'Pagne Wax 146',        5000, 0,   500, true, true);
insert into couriers (user_id, phone, status, decided_at) values (:rider, '+22614600009', 'approved', now() - interval '6 months')
on conflict (user_id) do update set status = 'approved';

-- As PostgREST names a caller.
create function pg_temp.as146(p_who uuid)
returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true),
           set_config('request.jwt.claims', case when p_who is null then '' else
                      json_build_object('sub', p_who, 'role', 'authenticated')::text end, true);
$$;

-- A statement as somebody, under their role (anon when nobody): 'ok', or
-- the refusal's words.
create function pg_temp.run146(p_who uuid, p_sql text)
returns text language plpgsql as $$
begin
    perform pg_temp.as146(p_who);
    execute case when p_who is null then 'set local role anon' else 'set local role authenticated' end;
    execute p_sql;
    execute 'reset role';
    return 'ok';
exception when others then
    execute 'reset role';
    return sqlerrm;
end;
$$;

-- A value as somebody, under their role: its text, or « ERR: … ».
create function pg_temp.val146(p_who uuid, p_sql text)
returns text language plpgsql as $$
declare v text;
begin
    perform pg_temp.as146(p_who);
    execute case when p_who is null then 'set local role anon' else 'set local role authenticated' end;
    execute p_sql into v;
    execute 'reset role';
    return v;
exception when others then
    execute 'reset role';
    return 'ERR: ' || sqlerrm;
end;
$$;

-- An order of one article as a shopper: its id, or the refusal's words.
create function pg_temp.order146(p_who uuid, p_slug text, p_product uuid)
returns text language plpgsql as $$
begin
    return pg_temp.val146(p_who, format(
        'select place_order(%L, %L::jsonb, ''pickup'', ''Samedi 10 h'', null, ''+22670000000'')::text',
        p_slug, jsonb_build_array(jsonb_build_object('product_id', p_product, 'quantity', 1))::text));
end;
$$;

-- An order moved on by its business (decide_order as the owner).
create function pg_temp.move146(p_owner uuid, p_order text, p_status text)
returns void language plpgsql as $$
declare v text;
begin
    v := pg_temp.run146(p_owner, format('select decide_order(%L::uuid, %L)', p_order, p_status));
    if v <> 'ok' then
        raise exception 'FAIL: % could not be moved to %: %', p_order, p_status, v;
    end if;
end;
$$;

-- A ready cash delivery, as a business's earlier order would be.
create function pg_temp.ready146(p_org uuid, p_total numeric, p_payment text default 'cash',
                                 p_currency text default 'XOF')
returns uuid language sql as $$
    insert into orders (org_id, customer_id, customer_name, fulfilment, status, payment_method,
                        total, currency, address, paid_at)
    values (p_org, '14614614-0000-0000-0000-000000000012', 'Client 4', 'delivery', 'ready', p_payment,
            p_total, p_currency, 'Ouagadougou, Gounghin',
            case when p_payment = 'wave' then now() end)
    returning id;
$$;

grant execute on all functions in schema pg_temp to anon, authenticated;

\set refuse_first '''Un nouveau compte a peu de commandes en cours à la fois : attendez que l''''une d''''elles soit terminée.'''
\set refuse_shop  '''Vous avez déjà plusieurs commandes en cours ici : attendez qu''''une soit terminée pour en passer une autre.'''

\echo ''
\echo '--- TEST 1: installed twice, the same ---'
do $$
declare v_bad text;
begin
    if (select value::text from platform_settings where key = 'order_open_max_per_shop') <> '3'
       or (select value::text from platform_settings where key = 'order_first_open_max') <> '2'
       or (select value::text from platform_settings where key = 'courier_cash_cap') <> '50000'
       or (select value::text from platform_settings where key = 'till_gap_review') <> '5000'
       or (select count(*) from platform_settings where key in ('order_open_max_per_shop', 'order_first_open_max',
                                                                 'courier_cash_cap', 'till_gap_review')) <> 4 then
        raise exception 'FAIL: the four settings are not 3, 2, 50 000 and 5 000';
    end if;
    if not (select relrowsecurity from pg_class where oid = 'public.blocked_customers'::regclass)
       or not (select relrowsecurity from pg_class where oid = 'public.till_closings'::regclass) then
        raise exception 'FAIL: RLS is off on a new table';
    end if;
    if (select string_agg(polcmd::text, '' order by polcmd) from pg_policy
         where polrelid = 'public.blocked_customers'::regclass) <> 'adr'
       or (select string_agg(polcmd::text, '' order by polcmd) from pg_policy
            where polrelid = 'public.till_closings'::regclass) <> 'r' then
        raise exception 'FAIL: the policies are not read/add/remove for blocks and read alone for closings';
    end if;
    if (select count(*) from pg_trigger where not tgisinternal and tgname in
            ('orders_trust_guard', 'audit_blocked_customers', 'audit_till_closings', 'same_org')
          and tgrelid in ('public.orders'::regclass, 'public.blocked_customers'::regclass,
                          'public.till_closings'::regclass)) <> 4 then
        raise exception 'FAIL: a trigger is missing (or doubled)';
    end if;
    select string_agg(p.proname, ', ') into v_bad
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('block_customer', 'unblock_customer', 'shopper_open_orders', 'trg_orders_guard',
                         'courier_cash_cap_for', 'courier_cash_carried', 'take_delivery',
                         'courier_cash_status', 'record_return', 'close_till', 'review_queue_rows',
                         'review_todo_counts', 'platform_review_queue', 'platform_set_setting')
       and (not coalesce((select true from unnest(p.proconfig) c where c like 'search_path=%'), false)
            or p.prosecdef = (p.proname in ('block_customer', 'unblock_customer')));
    if v_bad is not null then
        raise exception 'FAIL: unpinned, or not the security meant: %', v_bad;
    end if;
    raise notice 'PASS: settings 3/2/50 000/5 000, RLS and policies, the four triggers, INVOKER block/unblock and DEFINER the rest, all pinned';
end $$;

\echo ''
\echo '--- TEST 2: order limits — a new account, then one business ---'
do $$
declare
    v1 text; v2 text; v3 text; v4 text; v5 text; v6 text; v7 text;
begin
    -- Cliente 1 is new: two open orders anywhere, the third refused.
    v1 := pg_temp.order146('14614614-0000-0000-0000-000000000006', 'kiosque-nova-146', '146aaaaa-0000-0000-0000-000000000001');
    v2 := pg_temp.order146('14614614-0000-0000-0000-000000000006', 'ferme-horizon-146', '146aaaaa-0000-0000-0000-000000000002');
    v3 := pg_temp.order146('14614614-0000-0000-0000-000000000006', 'fondation-espoir-146', '146aaaaa-0000-0000-0000-000000000003');
    if v1 is null or v1 like 'ERR:%' or v2 like 'ERR:%' then
        raise exception 'FAIL: a new account''s first two orders: % / %', v1, v2;
    end if;
    if v3 is distinct from 'ERR: ' || 'Un nouveau compte a peu de commandes en cours à la fois : attendez que l''une d''elles soit terminée.' then
        raise exception 'FAIL: a new account''s third open order read %', v3;
    end if;
    -- The shop hands the first over: no longer new.
    perform pg_temp.move146('14614614-0000-0000-0000-000000000002', v1, 'accepted');
    perform pg_temp.move146('14614614-0000-0000-0000-000000000002', v1, 'picked_up');
    v3 := pg_temp.order146('14614614-0000-0000-0000-000000000006', 'fondation-espoir-146', '146aaaaa-0000-0000-0000-000000000003');
    if v3 like 'ERR:%' then
        raise exception 'FAIL: one order finished, the association''s refused: %', v3;
    end if;
    -- Three open at the farm (one already), the fourth refused there.
    v4 := pg_temp.order146('14614614-0000-0000-0000-000000000006', 'ferme-horizon-146', '146aaaaa-0000-0000-0000-000000000002');
    v5 := pg_temp.order146('14614614-0000-0000-0000-000000000006', 'ferme-horizon-146', '146aaaaa-0000-0000-0000-000000000002');
    v6 := pg_temp.order146('14614614-0000-0000-0000-000000000006', 'ferme-horizon-146', '146aaaaa-0000-0000-0000-000000000002');
    if v4 like 'ERR:%' or v5 like 'ERR:%'
       or v6 is distinct from 'ERR: Vous avez déjà plusieurs commandes en cours ici : attendez qu''une soit terminée pour en passer une autre.' then
        raise exception 'FAIL: the farm''s 2nd, 3rd and 4th read % / % / %', v4, v5, v6;
    end if;
    -- ... and taken at another business.
    v7 := pg_temp.order146('14614614-0000-0000-0000-000000000006', 'kiosque-nova-146', '146aaaaa-0000-0000-0000-000000000001');
    if v7 like 'ERR:%' then
        raise exception 'FAIL: the shop refused once the farm was full: %', v7;
    end if;
    -- An open order made 8 days ago is not counted any more.
    update orders set created_at = now() - interval '8 days' where id = v4::uuid;
    v6 := pg_temp.order146('14614614-0000-0000-0000-000000000006', 'ferme-horizon-146', '146aaaaa-0000-0000-0000-000000000002');
    if v6 like 'ERR:%' then
        raise exception 'FAIL: an order 8 days old still counted: %', v6;
    end if;
    -- A booking whose slot passed two days ago is not counted either.
    update orders set booked_for = now() - interval '2 days' where id = v5::uuid;
    v6 := pg_temp.order146('14614614-0000-0000-0000-000000000006', 'ferme-horizon-146', '146aaaaa-0000-0000-0000-000000000002');
    if v6 like 'ERR:%' then
        raise exception 'FAIL: a passed slot still counted: %', v6;
    end if;
    v6 := pg_temp.order146('14614614-0000-0000-0000-000000000006', 'ferme-horizon-146', '146aaaaa-0000-0000-0000-000000000002');
    if v6 not like 'ERR: Vous avez déjà plusieurs%' then
        raise exception 'FAIL: the farm full again took %', v6;
    end if;
    -- 0 turns each rule off.
    update platform_settings set value = '0' where key = 'order_open_max_per_shop';
    v6 := pg_temp.order146('14614614-0000-0000-0000-000000000006', 'ferme-horizon-146', '146aaaaa-0000-0000-0000-000000000002');
    if v6 like 'ERR:%' then
        raise exception 'FAIL: the per-business limit at 0 still refused: %', v6;
    end if;
    update platform_settings set value = '3' where key = 'order_open_max_per_shop';
    v1 := pg_temp.order146('14614614-0000-0000-0000-000000000008', 'kiosque-nova-146', '146aaaaa-0000-0000-0000-000000000001');
    v2 := pg_temp.order146('14614614-0000-0000-0000-000000000008', 'bazar-etoile-146', '146aaaaa-0000-0000-0000-000000000004');
    update platform_settings set value = '0' where key = 'order_first_open_max';
    v3 := pg_temp.order146('14614614-0000-0000-0000-000000000008', 'fondation-espoir-146', '146aaaaa-0000-0000-0000-000000000003');
    update platform_settings set value = '2' where key = 'order_first_open_max';
    if v1 like 'ERR:%' or v2 like 'ERR:%' or v3 like 'ERR:%' then
        raise exception 'FAIL: the new-account limit at 0 still refused: % / % / %', v1, v2, v3;
    end if;
    -- Not the shopper's own insert (a business, a migration, a seed): not asked.
    perform pg_temp.as146(null);
    perform pg_temp.ready146('14600000-0000-0000-0000-000000000003', 3000);
    perform pg_temp.ready146('14600000-0000-0000-0000-000000000003', 3000);
    perform pg_temp.ready146('14600000-0000-0000-0000-000000000003', 3000);
    perform pg_temp.ready146('14600000-0000-0000-0000-000000000003', 3000);
    raise notice 'PASS: a new account 2 open, the 3rd refused; finished once, 3 open per business, the 4th refused there and taken elsewhere; 8 days old and a passed slot not counted; 0 = off; a seed not asked';
end $$;

\echo ''
\echo '--- TEST 3: « Bloquer ce client » ---'
do $$
declare
    v_shop_order text; v_farm_order text; v_assoc_order text; v text;
begin
    -- Client 2 orders once at each business (and finishes the shop's).
    v_shop_order := pg_temp.order146('14614614-0000-0000-0000-000000000007', 'kiosque-nova-146', '146aaaaa-0000-0000-0000-000000000001');
    perform pg_temp.move146('14614614-0000-0000-0000-000000000002', v_shop_order, 'accepted');
    perform pg_temp.move146('14614614-0000-0000-0000-000000000002', v_shop_order, 'picked_up');
    v_farm_order := pg_temp.order146('14614614-0000-0000-0000-000000000007', 'ferme-horizon-146', '146aaaaa-0000-0000-0000-000000000002');
    v_assoc_order := pg_temp.order146('14614614-0000-0000-0000-000000000007', 'fondation-espoir-146', '146aaaaa-0000-0000-0000-000000000003');
    if v_farm_order like 'ERR:%' or v_assoc_order like 'ERR:%' then
        raise exception 'FAIL: Client 2 could not order: % / %', v_farm_order, v_assoc_order;
    end if;
    -- Who cannot block: the cashier, another business's owner, the shopper.
    if pg_temp.run146('14614614-0000-0000-0000-000000000005', format('select block_customer(%L)', v_shop_order))
           <> 'Seul le propriétaire ou un administrateur bloque un client'
       or pg_temp.run146('14614614-0000-0000-0000-000000000010', format('select block_customer(%L)', v_shop_order))
           <> 'Seul le propriétaire ou un administrateur bloque un client'
       or pg_temp.run146('14614614-0000-0000-0000-000000000007', format('select block_customer(%L)', v_shop_order))
           <> 'Seul le propriétaire ou un administrateur bloque un client'
       or pg_temp.run146(null, format('select block_customer(%L)', v_shop_order)) not like 'permission denied%' then
        raise exception 'FAIL: somebody other than the owner blocked';
    end if;
    -- The three owners block, with a reason.
    if pg_temp.run146('14614614-0000-0000-0000-000000000002', format('select block_customer(%L, ''Commandes jamais retirées'')', v_shop_order)) <> 'ok'
       or pg_temp.run146('14614614-0000-0000-0000-000000000003', format('select block_customer(%L)', v_farm_order)) <> 'ok'
       or pg_temp.run146('14614614-0000-0000-0000-000000000004', format('select block_customer(%L)', v_assoc_order)) <> 'ok'
       -- Twice is once.
       or pg_temp.run146('14614614-0000-0000-0000-000000000002', format('select block_customer(%L)', v_shop_order)) <> 'ok' then
        raise exception 'FAIL: an owner could not block';
    end if;
    if (select count(*) from blocked_customers where customer_id = '14614614-0000-0000-0000-000000000007') <> 3
       or (select name from blocked_customers where org_id = '14600000-0000-0000-0000-000000000001'
             and customer_id = '14614614-0000-0000-0000-000000000007') <> 'Client 2'
       or (select reason from blocked_customers where org_id = '14600000-0000-0000-0000-000000000001'
             and customer_id = '14614614-0000-0000-0000-000000000007') <> 'Commandes jamais retirées' then
        raise exception 'FAIL: the blocks are not one per business with the name and the reason';
    end if;
    -- The refusals, each kind its words, never « bloqué ».
    if pg_temp.order146('14614614-0000-0000-0000-000000000007', 'kiosque-nova-146', '146aaaaa-0000-0000-0000-000000000001')
           <> 'ERR: Cette boutique ne prend pas votre commande pour le moment.'
       or pg_temp.order146('14614614-0000-0000-0000-000000000007', 'ferme-horizon-146', '146aaaaa-0000-0000-0000-000000000002')
           <> 'ERR: Cette ferme ne prend pas votre commande pour le moment.'
       or pg_temp.order146('14614614-0000-0000-0000-000000000007', 'fondation-espoir-146', '146aaaaa-0000-0000-0000-000000000003')
           <> 'ERR: Cette association ne prend pas votre commande pour le moment.' then
        raise exception 'FAIL: a blocked shopper''s order not refused in the kind''s words';
    end if;
    -- Taken elsewhere.
    v := pg_temp.order146('14614614-0000-0000-0000-000000000007', 'bazar-etoile-146', '146aaaaa-0000-0000-0000-000000000004');
    if v like 'ERR:%' then
        raise exception 'FAIL: blocked at three, refused at the fourth: %', v;
    end if;
    -- Who sees a block: the business's admins alone.
    if pg_temp.val146('14614614-0000-0000-0000-000000000002', 'select count(*) from blocked_customers') <> '1'
       or pg_temp.val146('14614614-0000-0000-0000-000000000005', 'select count(*) from blocked_customers') <> '0'
       or pg_temp.val146('14614614-0000-0000-0000-000000000010', 'select count(*) from blocked_customers') <> '0'
       or pg_temp.val146('14614614-0000-0000-0000-000000000007', 'select count(*) from blocked_customers') <> '0'
       or pg_temp.val146(null, 'select count(*) from blocked_customers') not like 'ERR: permission denied%' then
        raise exception 'FAIL: a block is seen beyond the business''s admins';
    end if;
    -- No block of a stranger who never ordered here, of oneself, of
    -- another business's shopper written by hand; no edit of a block.
    if pg_temp.run146('14614614-0000-0000-0000-000000000002', format(
            'insert into blocked_customers (org_id, customer_id) values (%L, %L)',
            '14600000-0000-0000-0000-000000000001', '14614614-0000-0000-0000-000000000011')) not like '%row-level security%'
       or pg_temp.run146('14614614-0000-0000-0000-000000000002', format(
            'insert into blocked_customers (org_id, customer_id) values (%L, %L)',
            '14600000-0000-0000-0000-000000000001', '14614614-0000-0000-0000-000000000002')) not like '%row-level security%'
       or pg_temp.run146('14614614-0000-0000-0000-000000000010', format(
            'insert into blocked_customers (org_id, customer_id) values (%L, %L)',
            '14600000-0000-0000-0000-000000000001', '14614614-0000-0000-0000-000000000006')) not like '%row-level security%'
       or pg_temp.run146('14614614-0000-0000-0000-000000000002',
            'update blocked_customers set reason = ''x''') not like 'permission denied%' then
        raise exception 'FAIL: a block written beyond the rules';
    end if;
    -- Another business's owner cannot unblock here; the owner does.
    perform pg_temp.run146('14614614-0000-0000-0000-000000000010', format(
        'select unblock_customer(%L, %L)', '14600000-0000-0000-0000-000000000001', '14614614-0000-0000-0000-000000000007'));
    if (select count(*) from blocked_customers where customer_id = '14614614-0000-0000-0000-000000000007') <> 3 then
        raise exception 'FAIL: another business''s owner removed a block';
    end if;
    if pg_temp.run146('14614614-0000-0000-0000-000000000002', format(
           'select unblock_customer(%L, %L)', '14600000-0000-0000-0000-000000000001', '14614614-0000-0000-0000-000000000007')) <> 'ok' then
        raise exception 'FAIL: the owner could not unblock';
    end if;
    v := pg_temp.order146('14614614-0000-0000-0000-000000000007', 'kiosque-nova-146', '146aaaaa-0000-0000-0000-000000000001');
    if v like 'ERR:%' then
        raise exception 'FAIL: unblocked, still refused: %', v;
    end if;
    -- The business's Activité: the block and the unblock.
    if (select count(*) from audit_log where org_id = '14600000-0000-0000-0000-000000000001'
          and table_name = 'blocked_customers' and action in ('insert', 'delete')
          and summary = 'Client 2') <> 2 then
        raise exception 'FAIL: the block and the unblock are not in the business''s Activité';
    end if;
    raise notice 'PASS: the owners of a shop, a farm and an association block from an order; the cashier, another owner, the shopper and anon cannot; refused in each kind''s words, taken elsewhere; seen by the admins alone; no stranger, no self, no other business, no edit; unblocked by the owner alone; journaled';
end $$;

\echo ''
\echo '--- TEST 4: the courier''s cash cap ---'
do $$
declare
    o1 uuid := pg_temp.ready146('14600000-0000-0000-0000-000000000001', 30000);
    o2 uuid := pg_temp.ready146('14600000-0000-0000-0000-000000000001', 25000);
    o3 uuid := pg_temp.ready146('14600000-0000-0000-0000-000000000004', 40000, 'wave');
    o4 uuid := pg_temp.ready146('14600000-0000-0000-0000-000000000004', 60000);
    o5 uuid := pg_temp.ready146('14600000-0000-0000-0000-000000000005', 500, 'cash', 'EUR');
    v text;
    rider uuid := '14614614-0000-0000-0000-000000000009';
begin
    if pg_temp.run146(rider, format('select take_delivery(%L)', o1)) <> 'ok' then
        raise exception 'FAIL: 30 000 F of cash refused under a 50 000 F cap';
    end if;
    v := pg_temp.run146(rider, format('select take_delivery(%L)', o2));
    if v <> 'Vous portez déjà assez d''espèces : remettez l''argent aux boutiques avant de prendre une autre course payée en espèces.' then
        raise exception 'FAIL: 55 000 F held read %', v;
    end if;
    if pg_temp.run146(rider, format('select take_delivery(%L)', o3)) <> 'ok' then
        raise exception 'FAIL: a Wave-paid order counted as cash';
    end if;
    if pg_temp.run146(rider, format('select take_delivery(%L)', o5)) <> 'ok' then
        raise exception 'FAIL: an order in euros capped in francs';
    end if;
    if pg_temp.val146(rider, 'select string_agg(currency || ''='' || held || ''/'' || coalesce(cap::text, ''none''), '','' order by currency) from courier_cash_status()')
           <> 'EUR=500.00/none,XOF=30000.00/50000' then
        raise exception 'FAIL: courier_cash_status reads %',
            pg_temp.val146(rider, 'select string_agg(currency || ''='' || held || ''/'' || coalesce(cap::text, ''none''), '','' order by currency) from courier_cash_status()');
    end if;
    -- Delivered and not yet handed over still counts; received frees it.
    update orders set status = 'delivered' where id = o1;
    if pg_temp.run146(rider, format('select take_delivery(%L)', o2)) not like 'Vous portez déjà%' then
        raise exception 'FAIL: delivered cash not handed over stopped counting';
    end if;
    update orders set cash_received_at = now() where id = o1;
    v := pg_temp.run146(rider, format('select take_delivery(%L)', o4));
    if v <> 'Cette course dépasse ce qu''un livreur peut porter en espèces : la boutique la livre elle-même.' then
        raise exception 'FAIL: 60 000 F alone read %', v;
    end if;
    if pg_temp.run146(rider, format('select take_delivery(%L)', o2)) <> 'ok' then
        raise exception 'FAIL: the shop''s « argent reçu » did not free the room';
    end if;
    -- 0: no cap.
    update platform_settings set value = '0' where key = 'courier_cash_cap';
    if pg_temp.run146(rider, format('select take_delivery(%L)', o4)) <> 'ok'
       or pg_temp.val146(rider, 'select coalesce(cap::text, ''none'') from courier_cash_status() where currency = ''XOF''') <> 'none' then
        raise exception 'FAIL: a cap of 0 still capped';
    end if;
    update platform_settings set value = '50000' where key = 'courier_cash_cap';
    -- Not a courier: nothing.
    if pg_temp.val146('14614614-0000-0000-0000-000000000006', 'select count(*) from courier_cash_status()')
           <> 'ERR: Only an approved courier may do this'
       or pg_temp.val146(null, 'select count(*) from courier_cash_status()') not like 'ERR: permission denied%' then
        raise exception 'FAIL: courier_cash_status answered somebody else';
    end if;
    raise notice 'PASS: 30 000 F taken, 55 000 F refused, Wave not counted, euros not capped, delivered-not-handed-over counted, « reçu » frees it, 60 000 F alone refused in its words, 0 = no cap; the status a courier''s alone';
end $$;

\echo ''
\echo '--- TEST 5: a return is the owner''s ---'
do $$
declare v_sale uuid; v_other uuid; v text;
begin
    perform pg_temp.as146('14614614-0000-0000-0000-000000000005');
    v_sale := record_sale('14600000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', '146aaaaa-0000-0000-0000-000000000001',
                                             'quantity', 1, 'unit_price', 1000)), 'cash');
    v := pg_temp.run146('14614614-0000-0000-0000-000000000005', format('select record_return(%L)', v_sale));
    if v <> 'Seul le propriétaire ou un administrateur fait un retour de vente.' then
        raise exception 'FAIL: the cashier''s return read %', v;
    end if;
    if pg_temp.run146('14614614-0000-0000-0000-000000000010', format('select record_return(%L)', v_sale))
           <> 'You cannot record a return for this business' then
        raise exception 'FAIL: another business returned the sale';
    end if;
    v := pg_temp.run146('14614614-0000-0000-0000-000000000002', format('select record_return(%L, ''Article abîmé'')', v_sale));
    if v <> 'ok'
       or (select count(*) from sales where reverses_id = v_sale and kind = 'return') <> 1 then
        raise exception 'FAIL: the owner could not return the sale: %', v;
    end if;
    raise notice 'PASS: the cashier and another business refused, the owner returns the sale';
end $$;

\echo ''
\echo '--- TEST 6: « Clôturer la caisse » ---'
do $$
declare
    v_day   date := (now() at time zone 'UTC')::date;
    v_sale  uuid;
    v_deliv uuid;
    v_pick  text;
    r       jsonb;
    v       text;
    v_before int;
begin
    -- The shop's day so far: TEST 5's 1 000 F cash sale and its return,
    -- TEST 2/3's pickup orders handed over (1 000 F each, cash).
    -- Now: a 3 000 F cash sale and a 2 000 F mobile-money one by the
    -- cashier, a delivered order's 4 000 F cash (the courier's to hand over).
    perform pg_temp.as146('14614614-0000-0000-0000-000000000005');
    perform record_sale('14600000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', '146aaaaa-0000-0000-0000-000000000001',
                                             'quantity', 3, 'unit_price', 1000)), 'cash');
    perform record_sale('14600000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', '146aaaaa-0000-0000-0000-000000000001',
                                             'quantity', 2, 'unit_price', 1000)), 'mobile_money');
    v_deliv := pg_temp.ready146('14600000-0000-0000-0000-000000000001', 4000);
    insert into sales (org_id, kind, method, total, order_id, note)
    values ('14600000-0000-0000-0000-000000000001', 'sale', 'cash', 4000, v_deliv, 'Commande de Client 4');

    -- Blind: the cashier counts 9 500 F with 5 000 F of change.
    -- Expected: 5 000 + (1 000 + 1 000 + 1 000 + 3 000) − 1 000 = 10 000.
    r := pg_temp.val146('14614614-0000-0000-0000-000000000005', format(
            'select close_till(%L, %L, 0, 9500, 5000, ''Fin de journée'')::text',
            '14600000-0000-0000-0000-000000000001', v_day))::jsonb;
    if (r ->> 'cash_sales')::numeric <> 6000 or (r ->> 'cash_returns')::numeric <> 1000
       or (r ->> 'expected')::numeric <> 10000 or (r ->> 'counted')::numeric <> 9500
       or (r ->> 'gap')::numeric <> -500 or (r ->> 'opening_float')::numeric <> 5000
       or r ->> 'currency' <> 'XOF' then
        raise exception 'FAIL: the closing reads %', r;
    end if;
    -- Again: a new row, the first kept.
    r := pg_temp.val146('14614614-0000-0000-0000-000000000005', format(
            'select close_till(%L, %L, 0, 10000, 5000)::text', '14600000-0000-0000-0000-000000000001', v_day))::jsonb;
    if (r ->> 'gap')::numeric <> 0
       or (select count(*) from till_closings where org_id = '14600000-0000-0000-0000-000000000001') <> 2 then
        raise exception 'FAIL: a second closing is not a new row beside the first';
    end if;
    -- Who reads them.
    if pg_temp.val146('14614614-0000-0000-0000-000000000002', 'select count(*) from till_closings') <> '2'
       or pg_temp.val146('14614614-0000-0000-0000-000000000005', 'select count(*) from till_closings') <> '2'
       or pg_temp.val146('14614614-0000-0000-0000-000000000002', 'select min(gap)::text from till_closings') <> '-500.00'
       or pg_temp.val146('14614614-0000-0000-0000-000000000010', 'select count(*) from till_closings') <> '0'
       or pg_temp.val146('14614614-0000-0000-0000-000000000011', 'select count(*) from till_closings') <> '0'
       or pg_temp.val146('14614614-0000-0000-0000-000000000006', 'select count(*) from till_closings') <> '0'
       or pg_temp.val146(null, 'select count(*) from till_closings') not like 'ERR: permission denied%' then
        raise exception 'FAIL: the closings are read beyond the owner and their cashier';
    end if;
    -- Nobody writes the table by hand.
    if pg_temp.run146('14614614-0000-0000-0000-000000000002', format(
           'insert into till_closings (org_id, day, counted, gap) values (%L, %L, 0, 0)',
           '14600000-0000-0000-0000-000000000001', v_day)) not like 'permission denied%'
       or pg_temp.run146('14614614-0000-0000-0000-000000000005', 'update till_closings set gap = 0') not like 'permission denied%'
       or pg_temp.run146('14614614-0000-0000-0000-000000000002', 'delete from till_closings') not like 'permission denied%' then
        raise exception 'FAIL: a closing written, edited or removed by hand';
    end if;
    -- The farm closes too; an association, an observer, another business, anon refused.
    r := pg_temp.val146('14614614-0000-0000-0000-000000000003', format(
            'select close_till(%L, %L, 60, 0)::text', '14600000-0000-0000-0000-000000000002', v_day))::jsonb;
    if (r ->> 'expected')::numeric <> 0 or (r ->> 'gap')::numeric <> 0 then
        raise exception 'FAIL: the farm''s closing reads %', r;
    end if;
    if pg_temp.run146('14614614-0000-0000-0000-000000000004', format(
           'select close_till(%L, %L, 0, 0)', '14600000-0000-0000-0000-000000000003', v_day))
           <> 'Une association clôture sa journée, pas une caisse'
       or pg_temp.run146('14614614-0000-0000-0000-000000000011', format(
           'select close_till(%L, %L, 0, 0)', '14600000-0000-0000-0000-000000000001', v_day))
           <> 'Vous ne pouvez pas clôturer la caisse de cette activité'
       or pg_temp.run146('14614614-0000-0000-0000-000000000010', format(
           'select close_till(%L, %L, 0, 0)', '14600000-0000-0000-0000-000000000001', v_day))
           <> 'Vous ne pouvez pas clôturer la caisse de cette activité'
       or pg_temp.run146(null, format(
           'select close_till(%L, %L, 0, 0)', '14600000-0000-0000-0000-000000000001', v_day)) not like 'permission denied%' then
        raise exception 'FAIL: a closing taken from an association, an observer, a stranger or anon';
    end if;
    if pg_temp.run146('14614614-0000-0000-0000-000000000005', format(
           'select close_till(%L, %L, 0, -1)', '14600000-0000-0000-0000-000000000001', v_day)) <> 'Indiquez un montant positif'
       or pg_temp.run146('14614614-0000-0000-0000-000000000005', format(
           'select close_till(%L, %L, 0, 10, -5)', '14600000-0000-0000-0000-000000000001', v_day)) <> 'Indiquez un montant positif'
       or pg_temp.run146('14614614-0000-0000-0000-000000000005', format(
           'select close_till(%L, %L, 0, 10)', '14600000-0000-0000-0000-000000000001', v_day - 40)) <> 'Choisissez un jour des 31 derniers jours'
       or pg_temp.run146('14614614-0000-0000-0000-000000000005', format(
           'select close_till(%L, %L, 900, 10)', '14600000-0000-0000-0000-000000000001', v_day)) not like 'Décalage horaire invalide%' then
        raise exception 'FAIL: a bad amount, day or offset taken';
    end if;
    -- The business's Activité.
    if (select count(*) from audit_log where org_id = '14600000-0000-0000-0000-000000000001'
          and table_name = 'till_closings' and action = 'insert') <> 2 then
        raise exception 'FAIL: the closings are not in the business''s Activité';
    end if;
    raise notice 'PASS: blind count against the server''s expected (float + counter and pickup cash − cash returns; mobile money and a delivered order out), the gap kept; again a new row; the owner and their cashier read, nobody else; no write by hand; the farm closes, an association, an observer, a stranger and anon refused; bad inputs refused; journaled';
end $$;

\echo ''
\echo '--- TEST 7: Mara''s review queue ---'
do $$
declare q jsonb; v text; v_gap text;
begin
    -- The farm blocks three shoppers this month.
    insert into blocked_customers (org_id, customer_id, name) values
        ('14600000-0000-0000-0000-000000000002', '14614614-0000-0000-0000-000000000006', 'Cliente 1'),
        ('14600000-0000-0000-0000-000000000002', '14614614-0000-0000-0000-000000000008', 'Client 3')
    on conflict do nothing;
    -- The courier holds 85 000 F (TEST 4) under a cap lowered to 20 000 F.
    update platform_settings set value = '20000' where key = 'courier_cash_cap';
    -- A closing 6 000 F short at the bazar.
    perform pg_temp.as146('14614614-0000-0000-0000-000000000010');
    perform close_till('14600000-0000-0000-0000-000000000004', (now() at time zone 'UTC')::date, 0, 0, 6000);
    perform pg_temp.as146('14614614-0000-0000-0000-000000000001');
    q := platform_review_queue();
    if not exists (select 1 from jsonb_array_elements(q -> 'businesses') b
                    where b ->> 'name' = 'Ferme Horizon' and (b ->> 'blocks_30')::int = 3)
       or exists (select 1 from jsonb_array_elements(q -> 'businesses') b where b ->> 'name' = 'Kiosque Nova') then
        raise exception 'FAIL: the businesses read %', q -> 'businesses';
    end if;
    if not exists (select 1 from jsonb_array_elements(q -> 'couriers') c
                    where c ->> 'name' = 'Livreur Rapide 146' and (c ->> 'cap')::numeric = 20000
                      and (c ->> 'held')::numeric > 20000) then
        raise exception 'FAIL: the courier over the cap is not listed: %', q -> 'couriers';
    end if;
    if not exists (select 1 from jsonb_array_elements(q -> 'tills') t
                    where t ->> 'name' = 'Bazar Étoile' and (t ->> 'gap')::numeric = -6000)
       or exists (select 1 from jsonb_array_elements(q -> 'tills') t where t ->> 'name' = 'Kiosque Nova') then
        raise exception 'FAIL: the tills read %', q -> 'tills';
    end if;
    if (q ->> 'reports_open') is null or (q ->> 'couriers_pending') is null
       or (q ->> 'cash_cap')::numeric <> 20000 or (q ->> 'till_gap_review')::numeric <> 5000 then
        raise exception 'FAIL: the counts and the thresholds read %', q;
    end if;
    if (review_todo_counts() ->> 'review')::int
       <> jsonb_array_length(q -> 'businesses') + jsonb_array_length(q -> 'couriers') + jsonb_array_length(q -> 'tills') then
        raise exception 'FAIL: the counter is not the queue''s length';
    end if;
    update platform_settings set value = '50000' where key = 'courier_cash_cap';
    -- Nobody but the platform.
    if pg_temp.val146('14614614-0000-0000-0000-000000000002', 'select review_todo_counts()::text') is not null
       or pg_temp.val146('14614614-0000-0000-0000-000000000002', 'select platform_review_queue()::text') <> 'ERR: Réservé à la plateforme'
       or pg_temp.val146(null, 'select platform_review_queue()::text') not like 'ERR: permission denied%'
       or pg_temp.val146(null, 'select review_todo_counts()::text') not like 'ERR: permission denied%'
       or pg_temp.val146('14614614-0000-0000-0000-000000000001', 'select review_queue_rows()::text') not like 'ERR: permission denied%' then
        raise exception 'FAIL: the queue answers somebody else';
    end if;
    raise notice 'PASS: the farm with 3 blocks, the courier over the cap and the 6 000 F gap listed (not the shop''s 500 F), the reports and the couriers waiting counted, the counter the queue''s length; the platform''s alone';
end $$;

\echo ''
\echo '--- TEST 8: Réglages ---'
do $$
declare v_before int := (select count(*) from platform_actions where kind = 'setting'); v text;
begin
    perform pg_temp.as146('14614614-0000-0000-0000-000000000001');
    if pg_temp.run146('14614614-0000-0000-0000-000000000001', 'select platform_set_setting(''order_open_max_per_shop'', ''51'')')
           <> 'De 0 (sans limite) à 50 commandes, s''il vous plaît.'
       or pg_temp.run146('14614614-0000-0000-0000-000000000001', 'select platform_set_setting(''order_first_open_max'', ''2.5'')')
           <> 'Un nombre entier, s''il vous plaît.'
       or pg_temp.run146('14614614-0000-0000-0000-000000000001', 'select platform_set_setting(''courier_cash_cap'', ''500'')')
           <> 'De 1 000 à 10 000 000 FCFA, ou 0 pour aucun, s''il vous plaît.'
       or pg_temp.run146('14614614-0000-0000-0000-000000000001', 'select platform_set_setting(''till_gap_review'', ''10000001'')')
           <> 'De 1 000 à 10 000 000 FCFA, ou 0 pour aucun, s''il vous plaît.' then
        raise exception 'FAIL: a value out of range was taken';
    end if;
    -- One after the other (an OR's operands have no order in SQL).
    v := pg_temp.run146('14614614-0000-0000-0000-000000000001', 'select platform_set_setting(''order_open_max_per_shop'', ''5'')')
      || pg_temp.run146('14614614-0000-0000-0000-000000000001', 'select platform_set_setting(''order_first_open_max'', ''0'')');
    v := v || pg_temp.run146('14614614-0000-0000-0000-000000000001', 'select platform_set_setting(''courier_cash_cap'', ''75000'')');
    v := v || pg_temp.run146('14614614-0000-0000-0000-000000000001', 'select platform_set_setting(''till_gap_review'', ''0'')');
    if v <> 'okokokok'
       or (select value::text from platform_settings where key = 'courier_cash_cap') <> '75000'
       or (select count(*) from platform_actions where kind = 'setting') <> v_before + 4 then
        raise exception 'FAIL: the four settings were not set and journaled';
    end if;
    if pg_temp.run146('14614614-0000-0000-0000-000000000002', 'select platform_set_setting(''courier_cash_cap'', ''90000'')') = 'ok' then
        raise exception 'FAIL: an owner changed a platform setting';
    end if;
    -- The board lists them (Réglages reads it).
    if not (pg_temp.val146('14614614-0000-0000-0000-000000000001', 'select platform_settings_board()::text')::jsonb
            ?& array['order_open_max_per_shop', 'order_first_open_max', 'courier_cash_cap', 'till_gap_review']) then
        raise exception 'FAIL: the settings board leaves one out';
    end if;
    raise notice 'PASS: 51 orders, 2,5, 500 F and 10 000 001 F refused; 5, 0, 75 000 and 0 taken and journaled; an owner refused; on the board';
end $$;

\echo ''
\echo '--- TEST 9: the doors ---'
do $$
declare v_bad text;
begin
    select string_agg(sig, ', ') into v_bad from (values
        ('block_customer(uuid,text)'), ('unblock_customer(uuid,uuid)'), ('shopper_open_orders(uuid,uuid)'),
        ('trg_orders_guard()'), ('courier_cash_cap_for(text)'), ('courier_cash_carried(uuid,text)'),
        ('take_delivery(uuid)'), ('courier_cash_status()'), ('record_return(uuid,text,uuid)'),
        ('close_till(uuid,date,integer,numeric,numeric,text)'), ('review_queue_rows()'),
        ('review_todo_counts()'), ('platform_review_queue()'), ('platform_set_setting(text,jsonb)')) s(sig)
     where has_function_privilege('anon', sig, 'execute')
        or has_function_privilege('public', sig, 'execute');
    if v_bad is not null then
        raise exception 'FAIL: open to anon or PUBLIC: %', v_bad;
    end if;
    select string_agg(sig, ', ') into v_bad from (values
        ('shopper_open_orders(uuid,uuid)'), ('trg_orders_guard()'), ('courier_cash_cap_for(text)'),
        ('courier_cash_carried(uuid,text)'), ('review_queue_rows()')) s(sig)
     where has_function_privilege('authenticated', sig, 'execute');
    if v_bad is not null then
        raise exception 'FAIL: an internal helper open to authenticated: %', v_bad;
    end if;
    select string_agg(sig, ', ') into v_bad from (values
        ('block_customer(uuid,text)'), ('unblock_customer(uuid,uuid)'), ('take_delivery(uuid)'),
        ('courier_cash_status()'), ('record_return(uuid,text,uuid)'),
        ('close_till(uuid,date,integer,numeric,numeric,text)'), ('review_todo_counts()'),
        ('platform_review_queue()'), ('platform_set_setting(text,jsonb)')) s(sig)
     where not has_function_privilege('authenticated', sig, 'execute');
    if v_bad is not null then
        raise exception 'FAIL: an app door closed to authenticated: %', v_bad;
    end if;
    if has_table_privilege('anon', 'blocked_customers', 'select')
       or has_table_privilege('anon', 'till_closings', 'select')
       or has_table_privilege('authenticated', 'till_closings', 'insert')
       or has_table_privilege('authenticated', 'till_closings', 'update')
       or has_table_privilege('authenticated', 'blocked_customers', 'update') then
        raise exception 'FAIL: a table privilege beyond what the policies allow';
    end if;
    raise notice 'PASS: nothing for anon or PUBLIC, the helpers nobody''s, the app''s doors authenticated''s, the tables'' privileges as the policies';
end $$;

rollback;

\echo ''
\echo '=== test_batch146.sql: all claims hold ==='
