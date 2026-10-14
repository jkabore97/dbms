-- ============================================================
-- test_batch139.sql — « Mettre en avant » for 7 days, paid in the store
-- apps and by card, at a price per zone; Mara Pro by card at the zone's
-- own price (139, batch 142).
--
-- The claims, for a shop, a farm and an association alike:
--   * the zones: XOF (an XAF business the same number, in XAF), EUR,
--     USD for the rest; the settings seeded, read by name; spot_terms
--     keeps every older key and adds days 7, the zones, stripe_on and
--     version 139;
--   * request_promotion: 7 days only, the zone's price in the zone's
--     currency, Pro pays too (whatever pro_free_spots_month says);
--   * spot_settle (the service role's alone): a verified payment programs
--     the spot it names once — 7 days, an article after the strip's queue,
--     the vitrine at once — and is written down with its channel, amount
--     and currency; the same payment again is that spot, nothing more;
--     for another spot it is refused; a product of the other kind
--     refused; a sandbox payment only for a test account's business; a
--     payment for a spot no longer waiting buys 7 days after the one
--     running; the admins are rung;
--   * spot_verify_begin: an administrator of the spot's business only;
--   * spot_purchases: read by the business's admins only, written by
--     nobody but spot_settle; Mara's record outlives the business;
--   * spot_stripe_begin: the zone's 7-day price in Stripe's minor units
--     (XOF and XAF zero-decimal), the card's switch, the caller's own
--     waiting spot only; a 30-day spot asked before 139 keeps its price;
--   * stripe_begin (Mara Pro): the zone's own price and currency; and
--     plan_terms carries pro_zones, no dollars any more;
--   * Réglages: a euro or dollar price to the cent, the francs whole;
--   * a 30-day spot running from before 139 is untouched;
--   * the doors: definers with their path pinned, nothing for anon or
--     PUBLIC, spot_settle never authenticated's; run twice the same.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage on all sequences in schema public to authenticated;
\i database/migrations/139_spots_stores_zones.sql
-- This suite is about the spots, not the vitrine's minimum (092).
update platform_settings set value = '0' where key in ('vitrine_min_items', 'vitrine_min_items_association');

\set mara     '''13913913-0000-0000-0000-000000000001'''
\set sowner   '''13913913-0000-0000-0000-000000000002'''
\set fowner   '''13913913-0000-0000-0000-000000000003'''
\set aowner   '''13913913-0000-0000-0000-000000000004'''
\set clerk    '''13913913-0000-0000-0000-000000000005'''
\set stranger '''13913913-0000-0000-0000-000000000006'''
\set eowner   '''13913913-0000-0000-0000-000000000007'''
\set shop     '''13900000-0000-0000-0000-000000000001'''
\set farm     '''13900000-0000-0000-0000-000000000002'''
\set assoc    '''13900000-0000-0000-0000-000000000003'''
\set euro     '''13900000-0000-0000-0000-000000000004'''
\set dollar   '''13900000-0000-0000-0000-000000000005'''
\set cfa      '''13900000-0000-0000-0000-000000000006'''
\set other    '''13900000-0000-0000-0000-000000000007'''
\set maras    '''13900000-0000-0000-0000-000000000008'''

create or replace function pg_temp.as139(p_who uuid)
returns void
language sql
as $$
    select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true),
           set_config('request.jwt.claims',
                      json_build_object('sub', p_who, 'role', 'authenticated')::text, true);
$$;

-- The answer of p_sql as p_who under p_role, or the refusal's message.
create or replace function pg_temp.try139(p_who uuid, p_sql text, p_role text default 'authenticated')
returns text
language plpgsql
as $$
declare v text;
begin
    perform pg_temp.as139(p_who);
    execute format('set local role %I', p_role);
    execute p_sql into v;
    execute 'reset role';
    return coalesce(v, '(null)');
exception when others then
    execute 'reset role';
    return 'ERR: ' || sqlerrm;
end;
$$;

-- A spot asked by its business's owner, as the app asks it.
create or replace function pg_temp.ask139(p_owner uuid, p_org uuid, p_product uuid)
returns uuid
language plpgsql
as $$
declare v uuid;
begin
    perform pg_temp.as139(p_owner);
    execute 'set local role authenticated';
    v := request_promotion(p_org, p_product, 7);
    execute 'reset role';
    return v;
end;
$$;

-- The same, as the row it wrote (asked once: a volatile call in a WHERE
-- would be asked once per row scanned).
create or replace function pg_temp.asked139(p_owner uuid, p_org uuid, p_product uuid)
returns promotions
language plpgsql
as $$
declare
    v_id uuid := pg_temp.ask139(p_owner, p_org, p_product);
    v promotions%rowtype;
begin
    select * into v from promotions where id = v_id;
    if not found then
        raise exception 'FAIL: request_promotion answered % and wrote nothing', v_id;
    end if;
    return v;
end;
$$;

insert into auth.users (id, phone, email, email_confirmed_at, raw_user_meta_data) values
    (:mara,     '+22613901001', 'equipe139@example.org',      now(), '{"full_name": "Équipe Mara"}'),
    (:sowner,   '+22613901002', 'maison139@example.org',      now(), '{"full_name": "Maison Élégance"}'),
    (:fowner,   '+22613901003', 'horizon139@example.org',     now(), '{"full_name": "Ferme Horizon Vert"}'),
    (:aowner,   '+22613901004', 'espoir139@example.org',      now(), '{"full_name": "Fondation Espoir"}'),
    (:clerk,    '+22613901005', 'comptoir139@example.org',    now(), '{"full_name": "Comptoir 139"}'),
    (:stranger, '+22613901006', 'acacias139@example.org',     now(), '{"full_name": "Domaine des Acacias"}'),
    (:eowner,   '+33613901007', 'dore139@example.org',        now(), '{"full_name": "Le Comptoir Doré"}');
update profiles set is_platform_admin = true where id = :mara;
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled) values
    (:shop,   'Maison Élégance',     'maison-elegance-139', 'retail',      'XOF', true),
    (:farm,   'Ferme Horizon Vert',  'horizon-vert-139',    'farm',        'XOF', true),
    (:assoc,  'Fondation Espoir',    'fondation-espoir-139','association', 'XOF', true),
    (:euro,   'Le Comptoir Doré',    'comptoir-dore-139',   'retail',      'EUR', true),
    (:dollar, 'Atelier Lumière',     'atelier-lumiere-139', 'farm',        'GHS', true),
    (:cfa,    'Maison du Littoral',  'maison-littoral-139', 'association', 'XAF', true),
    (:other,  'Domaine des Acacias', 'domaine-acacias-139', 'retail',      'XOF', true),
    (:maras,  'Vitrine de Mara',     'vitrine-mara-139',    'retail',      'XOF', true);
update orgs set plan = 'pro', plan_until = current_date + 30 where id = :farm;
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,   :sowner,   'owner',    'org', :shop,   'full'),
    (:shop,   :clerk,    'employee', 'org', :shop,   'full'),
    (:farm,   :fowner,   'owner',    'org', :farm,   'full'),
    (:assoc,  :aowner,   'owner',    'org', :assoc,  'full'),
    (:euro,   :eowner,   'owner',    'org', :euro,   'full'),
    (:dollar, :fowner,   'owner',    'org', :dollar, 'full'),
    (:cfa,    :aowner,   'owner',    'org', :cfa,    'full'),
    (:other,  :stranger, 'owner',    'org', :other,  'full'),
    (:maras,  :mara,     'owner',    'org', :maras,  'full');
insert into products (id, org_id, name, sale_price, quantity, is_active, is_published) values
    ('139aaaaa-0000-0000-0000-000000000001', :shop,   'Robe de soirée',    25000, 3,  true, true),
    ('139aaaaa-0000-0000-0000-000000000002', :farm,   'Plateau d''œufs',     2500, 40, true, true),
    ('139aaaaa-0000-0000-0000-000000000004', :euro,   'Coffret de thé',        18, 9,  true, true),
    ('139aaaaa-0000-0000-0000-000000000005', :dollar, 'Miel de forêt',         12, 9,  true, true),
    ('139aaaaa-0000-0000-0000-000000000007', :other,  'Panier tressé',       8000, 5,  true, true),
    ('139aaaaa-0000-0000-0000-000000000008', :maras,  'Carte cadeau',        1000, 5,  true, true);
insert into documents (org_id, r2_key, kind, uploaded_by, product_id)
select p.org_id, 'org/' || p.org_id || '/' || p.id || '.jpg', 'photo',
       (select user_id from memberships m where m.org_id = p.org_id and m.role = 'owner' limit 1), p.id
  from products p where p.id::text like '139aaaaa-%';

\echo ''
\echo '--- TEST 1: the zones, the settings, the terms ---'
do $$
declare v jsonb := spot_terms();
begin
    if price_zone('XOF') <> 'XOF' or price_zone('xaf') <> 'XOF' or price_zone(null) <> 'XOF'
       or price_zone('EUR') <> 'EUR' or price_zone('GHS') <> 'USD' or price_zone('USD') <> 'USD'
       or price_zone('CAD') <> 'USD' then
        raise exception 'FAIL: the zones are wrong';
    end if;
    -- Every currency the app offers a business (knownCurrencies): its zone
    -- and what it is charged in.
    if (select string_agg(c || ':' || price_zone(c) || '/' || zone_currency(c), ' ' order by c)
          from unnest(array['XOF','XAF','EUR','USD','GHS','NGN','GBP','CAD','MAD','CNY']) c)
       <> 'CAD:USD/USD CNY:USD/USD EUR:EUR/EUR GBP:USD/USD GHS:USD/USD MAD:USD/USD NGN:USD/USD USD:USD/USD XAF:XOF/XAF XOF:XOF/XOF' then
        raise exception 'FAIL: a currency of the app has no zone';
    end if;
    if zone_currency('XAF') <> 'XAF' or zone_currency('XOF') <> 'XOF' or zone_currency('EUR') <> 'EUR'
       or zone_currency('GHS') <> 'USD' then
        raise exception 'FAIL: a zone is charged in the wrong currency';
    end if;
    if (select count(*) from platform_settings where key in (
            'spot_price_article_7_eur', 'spot_price_shop_7_eur', 'spot_price_article_7_usd',
            'spot_price_shop_7_usd', 'pro_price_month_eur', 'pro_price_year_eur',
            'pro_price_month_usd', 'pro_price_year_usd')) <> 8 then
        raise exception 'FAIL: the zone settings are not all seeded';
    end if;
    -- The 30-day prices stay, inert; every key an older app reads is there.
    if not (v ? 'article_7' and v ? 'article_30' and v ? 'shop_7' and v ? 'shop_30'
            and v ? 'max_live' and v ? 'currency') then
        raise exception 'FAIL: spot_terms lost an older key: %', v;
    end if;
    if (v ->> 'days')::int <> 7 or (v ->> 'version')::int <> 139
       or (v -> 'zones' -> 'XOF' ->> 'article')::numeric <> 5000
       or (v -> 'zones' -> 'XOF' ->> 'shop')::numeric <> 15000
       or (v -> 'zones' -> 'EUR' ->> 'article')::numeric <> 14.99
       or (v -> 'zones' -> 'USD' ->> 'shop')::numeric <> 39.99
       or jsonb_typeof(v -> 'stripe_on') <> 'boolean' then
        raise exception 'FAIL: spot_terms'' zones: %', v;
    end if;
    raise notice 'PASS: XOF (and XAF, charged in XAF), EUR, USD for the rest; eight zone settings; spot_terms keeps the older keys and says 7 days, the zones, the card and 139';
end $$;

\echo ''
\echo '--- TEST 2: asking — 7 days only, the zone''s price in its currency, Pro pays too ---'
begin;
update platform_settings set value = '1' where key = 'pro_free_spots_month';
do $$
declare
    v promotions%rowtype;
    r text;
begin
    -- A shop's article, a Pro farm's article, an association's vitrine (XOF).
    v := pg_temp.asked139('13913913-0000-0000-0000-000000000002',
        '13900000-0000-0000-0000-000000000001', '139aaaaa-0000-0000-0000-000000000001');
    if v.days <> 7 or v.price <> 5000 or v.currency <> 'XOF' or v.status <> 'requested' or v.free then
        raise exception 'FAIL: the shop''s article spot: % % % % %', v.days, v.price, v.currency, v.status, v.free;
    end if;
    v := pg_temp.asked139('13913913-0000-0000-0000-000000000003',
        '13900000-0000-0000-0000-000000000002', '139aaaaa-0000-0000-0000-000000000002');
    if v.free or v.status <> 'requested' or v.price <> 5000 then
        raise exception 'FAIL: a Pro farm got a free spot: % % %', v.free, v.status, v.price;
    end if;
    v := pg_temp.asked139('13913913-0000-0000-0000-000000000004',
        '13900000-0000-0000-0000-000000000003', null);
    if v.kind <> 'shop' or v.price <> 15000 or v.currency <> 'XOF' then
        raise exception 'FAIL: the association''s vitrine spot: % % %', v.kind, v.price, v.currency;
    end if;
    -- Euros, dollars (a business in cedis), and FCFA in XAF.
    v := pg_temp.asked139('13913913-0000-0000-0000-000000000007',
        '13900000-0000-0000-0000-000000000004', '139aaaaa-0000-0000-0000-000000000004');
    if v.price <> 14.99 or v.currency <> 'EUR' then
        raise exception 'FAIL: a business in euros was asked % %', v.price, v.currency;
    end if;
    v := pg_temp.asked139('13913913-0000-0000-0000-000000000003',
        '13900000-0000-0000-0000-000000000005', null);
    if v.price <> 39.99 or v.currency <> 'USD' then
        raise exception 'FAIL: a business in cedis was asked % %', v.price, v.currency;
    end if;
    v := pg_temp.asked139('13913913-0000-0000-0000-000000000004',
        '13900000-0000-0000-0000-000000000006', null);
    if v.price <> 15000 or v.currency <> 'XAF' then
        raise exception 'FAIL: a business in XAF was asked % %', v.price, v.currency;
    end if;
    -- 30 days refused, in French.
    r := pg_temp.try139('13913913-0000-0000-0000-000000000006',
        $q$select request_promotion('13900000-0000-0000-0000-000000000007', null, 30)::text$q$);
    if r <> 'ERR: Une mise en avant dure 7 jours' then
        raise exception 'FAIL: 30 days gave %', r;
    end if;
    -- An employee, and another business's owner, cannot ask.
    r := pg_temp.try139('13913913-0000-0000-0000-000000000005',
        $q$select request_promotion('13900000-0000-0000-0000-000000000001', null, 7)::text$q$);
    if r not like 'ERR: Seul un administrateur%' then raise exception 'FAIL: an employee asked: %', r; end if;
    r := pg_temp.try139('13913913-0000-0000-0000-000000000006',
        $q$select request_promotion('13900000-0000-0000-0000-000000000001', null, 7)::text$q$);
    if r not like 'ERR: Seul un administrateur%' then raise exception 'FAIL: a stranger asked: %', r; end if;
    if exists (select 1 from notifications where kind = 'spot_requested' and message like '%30 jours%') then
        raise exception 'FAIL: the platform heard of 30 days';
    end if;
    raise notice 'PASS: 7 days at 5 000 F (article) and 15 000 F (vitrine) for a shop, a Pro farm and an association; 14,99 € in euros, 39,99 $ for a business in cedis, 15 000 in XAF; no free spot for Pro; 30 days, an employee and a stranger refused';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: who may have a payment verified; who may write it ---'
begin;
create temp table t139 on commit drop as
select pg_temp.ask139('13913913-0000-0000-0000-000000000002', '13900000-0000-0000-0000-000000000001',
                      '139aaaaa-0000-0000-0000-000000000001') as id;
grant select on t139 to authenticated, anon;
do $$
declare r text;
begin
    r := pg_temp.try139('13913913-0000-0000-0000-000000000002',
        $q$select spot_verify_begin((select id from t139)) ->> 'org_id'$q$);
    if r <> '13900000-0000-0000-0000-000000000001' then raise exception 'FAIL: the owner was refused: %', r; end if;
    r := pg_temp.try139('13913913-0000-0000-0000-000000000005',
        $q$select spot_verify_begin((select id from t139))::text$q$);
    if r <> 'ERR: Mise en avant introuvable' then raise exception 'FAIL: an employee verifies: %', r; end if;
    r := pg_temp.try139('13913913-0000-0000-0000-000000000006',
        $q$select spot_verify_begin((select id from t139))::text$q$);
    if r <> 'ERR: Mise en avant introuvable' then raise exception 'FAIL: a stranger verifies: %', r; end if;
    r := pg_temp.try139(null, $q$select spot_verify_begin((select id from t139))::text$q$, 'anon');
    if r not like 'ERR: permission denied%' then raise exception 'FAIL: anon verifies: %', r; end if;
    -- spot_settle is the Worker's alone.
    r := pg_temp.try139('13913913-0000-0000-0000-000000000002',
        $q$select spot_settle('google', 'tok-self', (select id from t139), 'mara_spot_article_7', 0, 'XOF', 'production')::text$q$);
    if r not like 'ERR: permission denied%' then raise exception 'FAIL: an owner settled their own spot: %', r; end if;
    r := pg_temp.try139(null,
        $q$select spot_settle('google', 'tok-anon', (select id from t139), 'mara_spot_article_7', 0, 'XOF', 'production')::text$q$, 'anon');
    if r not like 'ERR: permission denied%' then raise exception 'FAIL: anon settled: %', r; end if;
    -- Nor a direct write.
    r := pg_temp.try139('13913913-0000-0000-0000-000000000002',
        $q$insert into spot_purchases (channel, external_id, product_id, kind) values ('google', 'x', 'y', 'shop') returning id::text$q$);
    if r not like 'ERR: permission denied%' then raise exception 'FAIL: an owner wrote a purchase: %', r; end if;
    if not has_function_privilege('service_role', 'spot_settle(text, text, uuid, text, numeric, text, text, uuid, jsonb, text, uuid)', 'execute') then
        raise exception 'FAIL: the Worker cannot settle';
    end if;
    raise notice 'PASS: the owner verifies; an employee, a stranger and anon do not; spot_settle and spot_purchases are the Worker''s alone';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: a verified payment programs its spot once — Google, Apple, Stripe; shop, farm, association ---'
begin;
create temp table t139 (k text primary key, id uuid) on commit drop;
insert into t139 values
    ('shop',  pg_temp.ask139('13913913-0000-0000-0000-000000000002', '13900000-0000-0000-0000-000000000001', '139aaaaa-0000-0000-0000-000000000001')),
    ('farm',  pg_temp.ask139('13913913-0000-0000-0000-000000000003', '13900000-0000-0000-0000-000000000002', '139aaaaa-0000-0000-0000-000000000002')),
    ('assoc', pg_temp.ask139('13913913-0000-0000-0000-000000000004', '13900000-0000-0000-0000-000000000003', null)),
    ('euro',  pg_temp.ask139('13913913-0000-0000-0000-000000000007', '13900000-0000-0000-0000-000000000004', null));
do $$
declare
    v_r jsonb;
    v   promotions%rowtype;
    p   spot_purchases%rowtype;
    v_shop  uuid := (select id from t139 where k = 'shop');
    v_farm  uuid := (select id from t139 where k = 'farm');
    v_assoc uuid := (select id from t139 where k = 'assoc');
    v_euro  uuid := (select id from t139 where k = 'euro');
begin
    -- Google, the shop's article.
    v_r := spot_settle('google', 'gp-token-139-a', v_shop, 'mara_spot_article_7', 1000, 'XOF', 'production',
                       '13913913-0000-0000-0000-000000000002', '{"orderId": "GPA.139"}', 'store');
    if not (v_r ->> 'ok')::boolean or not (v_r ->> 'granted')::boolean then raise exception 'FAIL: Google: %', v_r; end if;
    select * into v from promotions where id = v_shop;
    if v.status <> 'approved' or v.ends_at - v.starts_at <> interval '7 days'
       or abs(extract(epoch from v.starts_at - now())) > 5 or v.note <> 'Payé sur Google Play' then
        raise exception 'FAIL: the shop''s spot: % % % %', v.status, v.starts_at, v.ends_at, v.note;
    end if;
    select * into p from spot_purchases where channel = 'google' and external_id = 'gp-token-139-a';
    if p.promotion_id <> v_shop or p.amount <> 1000 or p.currency <> 'XOF' or p.kind <> 'article'
       or p.org_name <> 'Maison Élégance' or p.environment <> 'production' or p.amount_source <> 'store'
       or p.bought_by <> '13913913-0000-0000-0000-000000000002' then
        raise exception 'FAIL: the purchase was not written down as it was: %', to_jsonb(p);
    end if;
    if not exists (select 1 from notifications where org_id = '13900000-0000-0000-0000-000000000001'
                    and kind = 'spot_approved' and params ->> 'store' = 'google') then
        raise exception 'FAIL: the shop was not rung';
    end if;
    -- The same token again: the same spot, nothing more.
    v_r := spot_settle('google', 'gp-token-139-a', v_shop, 'mara_spot_article_7', 1000, 'XOF', 'production');
    if not (v_r ->> 'ok')::boolean or (v_r ->> 'granted')::boolean or (v_r ->> 'promotion_id')::uuid <> v_shop then
        raise exception 'FAIL: a replay: %', v_r;
    end if;
    if (select count(*) from spot_purchases where external_id = 'gp-token-139-a') <> 1
       or (select count(*) from promotions where org_id = '13900000-0000-0000-0000-000000000001') <> 1 then
        raise exception 'FAIL: a replay granted twice';
    end if;
    -- The same token for another spot: refused.
    v_r := spot_settle('google', 'gp-token-139-a', v_farm, 'mara_spot_article_7', 1000, 'XOF', 'production');
    if v_r ->> 'reason' is distinct from 'another spot' then raise exception 'FAIL: a token for two spots: %', v_r; end if;
    -- A vitrine product for an article spot: refused.
    v_r := spot_settle('apple', '3000000139', v_farm, 'bf.kaj.app.spot.shop7', 2.49, 'USD', 'production');
    if v_r ->> 'reason' is distinct from 'product' then raise exception 'FAIL: the wrong kind: %', v_r; end if;
    -- An unknown product.
    v_r := spot_settle('apple', '3000000140', v_farm, 'bf.kaj.app.pro.monthly', 2.49, 'USD', 'production');
    if v_r ->> 'reason' is distinct from 'product' then raise exception 'FAIL: Mara Pro as a spot: %', v_r; end if;
    -- Apple, the Pro farm's article, its price in the store's currency.
    v_r := spot_settle('apple', '3000000141', v_farm, 'bf.kaj.app.spot.article7', 1.99, 'eur', 'production');
    select * into v from promotions where id = v_farm;
    if v.status <> 'approved' or v.price <> 1.99 or v.currency <> 'EUR' or v.note <> 'Payé sur l''App Store' then
        raise exception 'FAIL: the farm''s Apple spot: % % % %', v.status, v.price, v.currency, v.note;
    end if;
    -- Stripe, the association's vitrine: at once.
    v_r := spot_settle('stripe', 'cs_test_139', v_assoc, 'stripe:shop', 2500, 'XOF', 'production');
    select * into v from promotions where id = v_assoc;
    if v.status <> 'approved' or abs(extract(epoch from v.starts_at - now())) > 5
       or v.note <> 'Payé sur carte' then
        raise exception 'FAIL: the association''s card spot: % % %', v.status, v.starts_at, v.note;
    end if;
    if (select channel from spot_purchases where promotion_id = v_assoc) <> 'stripe' then
        raise exception 'FAIL: the card payment not written';
    end if;
    -- A test card for a business that is not a test account's: refused,
    -- no spot — written as refused (the Worker refunds the test card), a
    -- sandbox one never in the platform's « À faire »; for Mara's own
    -- business: programmed.
    v_r := spot_settle('stripe', 'cs_test_139_sb', v_euro, 'stripe:shop', 4.99, 'EUR', 'sandbox');
    if v_r ->> 'reason' is distinct from 'sandbox' then raise exception 'FAIL: a test card counted: %', v_r; end if;
    if (select outcome || ' ' || environment from spot_purchases where external_id = 'cs_test_139_sb') <> 'refused sandbox'
       or (select status from promotions where id = v_euro) <> 'requested' then
        raise exception 'FAIL: a refused test payment left something';
    end if;
    raise notice 'PASS: Google, Apple and the card each program their spot for 7 days (an article in the strip''s queue, a vitrine at once) and write channel, amount, currency and buyer; a replay is the same spot; another spot, another kind, Mara Pro refused; a test card only for a test account';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: an article spot waits for the strip; a payment for a spot no longer waiting buys 7 days after the one running ---'
begin;
-- Eight running article spots, ending on days 1..8: the strip is full.
insert into promotions (org_id, product_id, kind, days, status, starts_at, ends_at)
select '13900000-0000-0000-0000-000000000007', '139aaaaa-0000-0000-0000-000000000007',
       'article', 7, 'approved', now() - interval '1 day', now() + make_interval(days => g)
from generate_series(1, 8) g;
create temp table t139 on commit drop as
select pg_temp.ask139('13913913-0000-0000-0000-000000000002', '13900000-0000-0000-0000-000000000001',
                      '139aaaaa-0000-0000-0000-000000000001') as id;
do $$
declare
    v_id uuid := (select id from t139);
    v promotions%rowtype;
    v_r jsonb;
    v_end timestamptz;
begin
    perform spot_settle('google', 'gp-139-queue', v_id, 'mara_spot_article_7', 1000, 'XOF', 'production');
    select * into v from promotions where id = v_id;
    if abs(extract(epoch from v.starts_at - (now() + interval '1 day'))) > 5 then
        raise exception 'FAIL: the paid article starts at %, not when the strip frees', v.starts_at;
    end if;
    v_end := v.ends_at;
    -- Cancelled meanwhile (or paid by Wave), still eligible: a second
    -- payment still buys 7 days, after the one running.
    update promotions set status = 'cancelled' where id = v_id;
    insert into promotions (org_id, product_id, kind, days, status, starts_at, ends_at)
    values ('13900000-0000-0000-0000-000000000001', '139aaaaa-0000-0000-0000-000000000001', 'article', 7,
            'approved', now(), v_end);
    v_r := spot_settle('apple', '3000000150', v_id, 'bf.kaj.app.spot.article7', 1000, 'XOF', 'production');
    if not (v_r ->> 'ok')::boolean or (v_r ->> 'promotion_id')::uuid = v_id then
        raise exception 'FAIL: a payment for a cancelled spot: %', v_r;
    end if;
    select * into v from promotions where id = (v_r ->> 'promotion_id')::uuid;
    if v.status <> 'approved' or abs(extract(epoch from v.starts_at - v_end)) > 5
       or v.ends_at - v.starts_at <> interval '7 days' or v.product_id <> '139aaaaa-0000-0000-0000-000000000001' then
        raise exception 'FAIL: the 7 days bought after: % → %', v.starts_at, v.ends_at;
    end if;
    -- Shown again, it is that new spot.
    v_r := spot_settle('apple', '3000000150', v_id, 'bf.kaj.app.spot.article7', 1000, 'XOF', 'production');
    if (v_r ->> 'granted')::boolean or (v_r ->> 'promotion_id')::uuid <> v.id then
        raise exception 'FAIL: the replay of an extension: %', v_r;
    end if;
    raise notice 'PASS: a paid article waits for the strip; a payment for a spot no longer waiting buys its 7 days after the one running, once';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: the sandbox for Mara''s own business; Mara''s record outlives the business; RLS ---'
begin;
create temp table t139 (k text primary key, id uuid) on commit drop;
insert into t139 values
    ('mara', pg_temp.ask139('13913913-0000-0000-0000-000000000001', '13900000-0000-0000-0000-000000000008', '139aaaaa-0000-0000-0000-000000000008')),
    ('shop', pg_temp.ask139('13913913-0000-0000-0000-000000000002', '13900000-0000-0000-0000-000000000001', null));
grant select on t139 to authenticated;
do $$
declare v_r jsonb; r text;
begin
    v_r := spot_settle('apple', '3000000160', (select id from t139 where k = 'mara'),
                       'bf.kaj.app.spot.article7', 1000, 'XOF', 'sandbox');
    if not (v_r ->> 'ok')::boolean then raise exception 'FAIL: TestFlight on Mara''s own business: %', v_r; end if;
    if (select environment from spot_purchases where external_id = '3000000160') <> 'sandbox' then
        raise exception 'FAIL: the sandbox was not said';
    end if;
    -- Google said no amount (no order read): Mara's own zone price, said
    -- as Mara's — never the app's word, whatever source the Worker names.
    perform spot_settle('google', 'gp-139-rls', (select id from t139 where k = 'shop'),
                        'mara_spot_shop_7', null, null, 'production', null, null, 'app');
    if (select amount_source || ' ' || amount::text || ' ' || currency from spot_purchases
         where external_id = 'gp-139-rls') <> 'mara 15000.00 XOF' then
        raise exception 'FAIL: no store amount is not Mara''s price: %',
            (select row_to_json(p) from spot_purchases p where external_id = 'gp-139-rls');
    end if;
    -- RLS: the owner reads its own; an employee, a stranger, anon nothing.
    r := pg_temp.try139('13913913-0000-0000-0000-000000000002', $q$select count(*)::text from spot_purchases$q$);
    if r <> '1' then raise exception 'FAIL: the owner reads % purchases', r; end if;
    r := pg_temp.try139('13913913-0000-0000-0000-000000000005', $q$select count(*)::text from spot_purchases$q$);
    if r <> '0' then raise exception 'FAIL: an employee reads % purchases', r; end if;
    r := pg_temp.try139('13913913-0000-0000-0000-000000000006', $q$select count(*)::text from spot_purchases$q$);
    if r <> '0' then raise exception 'FAIL: a stranger reads % purchases', r; end if;
    r := pg_temp.try139(null, $q$select count(*)::text from spot_purchases$q$, 'anon');
    if r not like 'ERR: permission denied%' then raise exception 'FAIL: anon reads purchases: %', r; end if;
end $$;
-- The business goes (128's one path, the platform's « Supprimer » and an
-- owner's account deletion alike): Mara's record stays, with its name.
select purge_org('13900000-0000-0000-0000-000000000001', null, 'test 139');
do $$ begin
    if (select count(*) from spot_purchases where external_id = 'gp-139-rls' and org_id is null
          and promotion_id is null and org_name = 'Maison Élégance' and amount = 15000) <> 1 then
        raise exception 'FAIL: the payment went with the business';
    end if;
    raise notice 'PASS: a TestFlight purchase for Mara''s own business is programmed and said sandbox; no store amount is Mara''s zone price, said so; the owner reads its payments, nobody else; the record outlives the business, named';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: a spot by card — the zone''s price in Stripe''s minor units ---'
begin;
update platform_settings set value = 'true' where key = 'stripe_on';
create temp table t139 (k text primary key, id uuid) on commit drop;
insert into t139 values
    ('shop',   pg_temp.ask139('13913913-0000-0000-0000-000000000002', '13900000-0000-0000-0000-000000000001', '139aaaaa-0000-0000-0000-000000000001')),
    ('euro',   pg_temp.ask139('13913913-0000-0000-0000-000000000007', '13900000-0000-0000-0000-000000000004', '139aaaaa-0000-0000-0000-000000000004')),
    ('dollar', pg_temp.ask139('13913913-0000-0000-0000-000000000003', '13900000-0000-0000-0000-000000000005', null)),
    ('cfa',    pg_temp.ask139('13913913-0000-0000-0000-000000000004', '13900000-0000-0000-0000-000000000006', null));
-- A 30-day spot asked before 139, in francs and in euros.
insert into t139 values ('old',    '139bbbbb-0000-0000-0000-000000000001'), ('oldeur', '139bbbbb-0000-0000-0000-000000000002');
insert into promotions (id, org_id, product_id, kind, days, price, currency, status) values
    ('139bbbbb-0000-0000-0000-000000000001', '13900000-0000-0000-0000-000000000003', null, 'shop', 30, 8000, 'XOF', 'requested'),
    ('139bbbbb-0000-0000-0000-000000000002', '13900000-0000-0000-0000-000000000004', '139aaaaa-0000-0000-0000-000000000004', 'article', 30, 3000, 'EUR', 'requested');
delete from promotions where id = (select id from t139 where k = 'euro');
grant select on t139 to authenticated;
do $$
declare v jsonb; r text;
    function_sql text := $q$select spot_stripe_begin((select id from t139 where k = '%s'))::text$q$;
begin
    v := pg_temp.try139('13913913-0000-0000-0000-000000000002', format(function_sql, 'shop'))::jsonb;
    if (v ->> 'amount')::int <> 5000 or v ->> 'currency' <> 'xof' or v ->> 'kind' <> 'article'
       or v ->> 'label' <> 'Robe de soirée' or v ->> 'org_name' <> 'Maison Élégance' then
        raise exception 'FAIL: a shop''s article by card: %', v;
    end if;
    v := pg_temp.try139('13913913-0000-0000-0000-000000000003', format(function_sql, 'dollar'))::jsonb;
    if (v ->> 'amount')::int <> 3999 or v ->> 'currency' <> 'usd' or (v ->> 'price')::numeric <> 39.99 then
        raise exception 'FAIL: a vitrine in dollars by card: %', v;
    end if;
    v := pg_temp.try139('13913913-0000-0000-0000-000000000004', format(function_sql, 'cfa'))::jsonb;
    if (v ->> 'amount')::int <> 15000 or v ->> 'currency' <> 'xaf' then
        raise exception 'FAIL: a vitrine in XAF by card: %', v;
    end if;
    -- The 30-day spot asked before: its own price, in francs; in euros, refused.
    v := pg_temp.try139('13913913-0000-0000-0000-000000000004', format(function_sql, 'old'))::jsonb;
    if (v ->> 'amount')::int <> 8000 or (v ->> 'days')::int <> 30 then
        raise exception 'FAIL: an older 30-day spot by card: %', v;
    end if;
    r := pg_temp.try139('13913913-0000-0000-0000-000000000007', format(function_sql, 'oldeur'));
    if r <> 'ERR: Cette ancienne demande de 30 jours ne se paie pas par carte' then
        raise exception 'FAIL: an older 30-day spot in euros gave %', r;
    end if;
    -- Not the caller's: refused; not waiting: refused.
    r := pg_temp.try139('13913913-0000-0000-0000-000000000006', format(function_sql, 'shop'));
    if r <> 'ERR: Mise en avant introuvable' then raise exception 'FAIL: a stranger paid: %', r; end if;
    perform spot_settle('stripe', 'cs_139_paid', (select id from t139 where k = 'shop'), 'stripe:article', 1000, 'XOF', 'production');
    r := pg_temp.try139('13913913-0000-0000-0000-000000000002', format(function_sql, 'shop'));
    if r <> 'ERR: Cette mise en avant n''attend pas de paiement' then raise exception 'FAIL: paid twice: %', r; end if;
    raise notice 'PASS: 5 000 F is 5000 xof, 39,99 $ is 3999 usd, 15 000 in XAF is 15000 xaf; an older 30-day spot keeps its francs and is refused in euros; a stranger''s and a paid spot refused';
end $$;
-- The card switched off: nothing starts.
update platform_settings set value = 'false' where key = 'stripe_on';
do $$
declare r text;
begin
    r := pg_temp.try139('13913913-0000-0000-0000-000000000004',
        $q$select spot_stripe_begin((select id from t139 where k = 'cfa'))::text$q$);
    if r <> 'ERR: Le paiement par carte n''est pas encore ouvert' then raise exception 'FAIL: card off gave %', r; end if;
    raise notice 'PASS: the card''s switch off, no spot by card';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: Mara Pro by card at the zone''s own price; plan_terms ---'
begin;
update platform_settings set value = 'true' where key = 'stripe_on';
update platform_settings set value = '2900' where key = 'pro_price_month';
update platform_settings set value = '29900' where key = 'pro_price_year';
do $$
declare v jsonb; t jsonb;
begin
    v := pg_temp.try139('13913913-0000-0000-0000-000000000002',
        $q$select stripe_begin('13900000-0000-0000-0000-000000000001', 'month')::text$q$)::jsonb;
    if (v ->> 'amount')::int <> 2900 or v ->> 'currency' <> 'xof' or v ->> 'price_currency' <> 'XOF' then
        raise exception 'FAIL: Pro in francs: %', v;
    end if;
    v := pg_temp.try139('13913913-0000-0000-0000-000000000007',
        $q$select stripe_begin('13900000-0000-0000-0000-000000000004', 'year')::text$q$)::jsonb;
    if (v ->> 'amount')::int <> 4999 or v ->> 'currency' <> 'eur' or (v ->> 'price')::numeric <> 49.99 then
        raise exception 'FAIL: Pro in euros: %', v;
    end if;
    v := pg_temp.try139('13913913-0000-0000-0000-000000000003',
        $q$select stripe_begin('13900000-0000-0000-0000-000000000005', 'month')::text$q$)::jsonb;
    if (v ->> 'amount')::int <> 499 or v ->> 'currency' <> 'usd' then
        raise exception 'FAIL: Pro in dollars: %', v;
    end if;
    v := pg_temp.try139('13913913-0000-0000-0000-000000000004',
        $q$select stripe_begin('13900000-0000-0000-0000-000000000006', 'year')::text$q$)::jsonb;
    if (v ->> 'amount')::int <> 29900 or v ->> 'currency' <> 'xaf' then
        raise exception 'FAIL: Pro in XAF: %', v;
    end if;
    t := plan_terms();
    if (t -> 'pro_zones' -> 'XOF' ->> 'month')::numeric <> 2900
       or (t -> 'pro_zones' -> 'EUR' ->> 'year')::numeric <> 49.99
       or (t -> 'pro_zones' -> 'USD' ->> 'month')::numeric <> 4.99
       or t -> 'stripe_usd_month' <> 'null'::jsonb or (t ->> 'pro_price_month')::int <> 2900 then
        raise exception 'FAIL: plan_terms: %', t;
    end if;
    raise notice 'PASS: Pro by card is 2 900 xof, 49,99 € (4999 eur), 4,99 $ (499 usd), 29 900 xaf; plan_terms says the zones and no dollars';
end $$;
rollback;

\echo ''
\echo '--- TEST 9: Réglages — a euro or dollar price to the cent, journaled; francs whole ---'
begin;
do $$
declare a uuid; r text;
begin
    a := (select pg_temp.try139('13913913-0000-0000-0000-000000000001',
            $q$select platform_set_setting('spot_price_article_7_eur', '2.49')::text$q$))::uuid;
    if (select value from platform_settings where key = 'spot_price_article_7_eur') <> '2.49'::jsonb
       or (spot_terms() -> 'zones' -> 'EUR' ->> 'article')::numeric <> 2.49 then
        raise exception 'FAIL: 2,49 € not written';
    end if;
    if not exists (select 1 from platform_actions where id = a) then raise exception 'FAIL: not journaled'; end if;
    r := pg_temp.try139('13913913-0000-0000-0000-000000000001',
        $q$select platform_set_setting('pro_price_month_usd', '4.995')::text$q$);
    if r <> 'ERR: Deux chiffres après la virgule au plus, s''il vous plaît.' then
        raise exception 'FAIL: half a cent gave %', r;
    end if;
    r := pg_temp.try139('13913913-0000-0000-0000-000000000001',
        $q$select platform_set_setting('spot_price_shop_7', '2500.5')::text$q$);
    if r <> 'ERR: Un nombre entier, s''il vous plaît.' then raise exception 'FAIL: half a franc gave %', r; end if;
    r := pg_temp.try139('13913913-0000-0000-0000-000000000002',
        $q$select platform_set_setting('spot_price_shop_7_usd', '1')::text$q$);
    if r not like 'ERR:%' then raise exception 'FAIL: an owner set a price: %', r; end if;
    raise notice 'PASS: 2,49 € written and journaled, half a cent and half a franc refused, an owner refused';
end $$;
rollback;

\echo ''
\echo '--- TEST 10: a 30-day spot running from before 139 is untouched; run twice the same ---'
begin;
insert into promotions (id, org_id, kind, days, price, currency, status, starts_at, ends_at)
values ('139bbbbb-0000-0000-0000-000000000009', '13900000-0000-0000-0000-000000000002', 'shop', 30, 8000, 'XOF',
        'approved', now() - interval '3 days', now() + interval '27 days');
create temp table b139_seen on commit drop as
    select (select to_jsonb(p) from promotions p where id = '139bbbbb-0000-0000-0000-000000000009') as spot,
           spot_terms() as terms, plan_terms() as plan;
\i database/migrations/139_spots_stores_zones.sql
do $$ begin
    if (select spot from b139_seen) is distinct from
       (select to_jsonb(p) from promotions p where id = '139bbbbb-0000-0000-0000-000000000009')
       or (select terms from b139_seen) is distinct from spot_terms()
       or (select plan from b139_seen) is distinct from plan_terms() then
        raise exception 'FAIL: applying 139 again changed something';
    end if;
    if (select count(*) from pg_proc where proname in ('spot_settle', 'request_promotion', 'stripe_begin',
            'spot_stripe_begin', 'spot_verify_begin', 'platform_set_setting', 'spot_refund')) <> 7 then
        raise exception 'FAIL: an overload was left';
    end if;
    raise notice 'PASS: the running 30-day spot, spot_terms and plan_terms the same after 139 twice; no overload';
end $$;
rollback;

\echo ''
\echo '--- TEST 11: a payment taken back — recorded once, its spot ended (a waiting one cancelled); nobody but the Worker ---'
begin;
create temp table t139 (k text primary key, id uuid) on commit drop;
insert into t139 values
    ('shop',  pg_temp.ask139('13913913-0000-0000-0000-000000000002', '13900000-0000-0000-0000-000000000001', null)),
    ('farm',  pg_temp.ask139('13913913-0000-0000-0000-000000000003', '13900000-0000-0000-0000-000000000002', '139aaaaa-0000-0000-0000-000000000002')),
    ('assoc', pg_temp.ask139('13913913-0000-0000-0000-000000000004', '13900000-0000-0000-0000-000000000003', null));
grant select on t139 to authenticated;
do $$
declare v_r jsonb; v promotions%rowtype; r text;
begin
    -- A shop's vitrine bought on the App Store, running: Apple's REFUND ends it now.
    perform spot_settle('apple', '3000000190', (select id from t139 where k = 'shop'),
                        'bf.kaj.app.spot.shop7', 39.99, 'EUR', 'production');
    v_r := spot_refund('apple', '3000000190', 'apple REFUND');
    select * into v from promotions where id = (select id from t139 where k = 'shop');
    if not (v_r ->> 'ok')::boolean or v_r ->> 'spot' <> 'ended' or v.status <> 'approved'
       or v.ends_at > now() or v.note <> 'Paiement remboursé' then
        raise exception 'FAIL: Apple''s refund of a running vitrine: % / % %', v_r, v.status, v.ends_at;
    end if;
    if (select refund_reason from spot_purchases where external_id = '3000000190') <> 'apple REFUND'
       or (select refunded_at from spot_purchases where external_id = '3000000190') is null then
        raise exception 'FAIL: the refund not written';
    end if;
    -- Told twice: nothing more.
    v_r := spot_refund('apple', '3000000190', 'apple REFUND');
    if not (v_r ->> 'already')::boolean then raise exception 'FAIL: a second refund: %', v_r; end if;

    -- A farm's article waiting its turn (starts later), voided by Google: cancelled, never shown.
    perform spot_settle('google', 'gp-139-void', (select id from t139 where k = 'farm'),
                        'mara_spot_article_7', null, null, 'production');
    update promotions set starts_at = now() + interval '2 days', ends_at = now() + interval '9 days'
     where id = (select id from t139 where k = 'farm');
    v_r := spot_refund('google', 'gp-139-void', 'google voided');
    select * into v from promotions where id = (select id from t139 where k = 'farm');
    if v_r ->> 'spot' <> 'cancelled' or v.status <> 'cancelled' then
        raise exception 'FAIL: Google''s voided purchase of a waiting article: % / %', v_r, v.status;
    end if;

    -- An association's vitrine by card: Stripe's refund names the PaymentIntent.
    perform spot_settle('stripe', 'cs_139_refund', (select id from t139 where k = 'assoc'),
                        'stripe:shop', 15000, 'XOF', 'production', null,
                        '{"payment_intent": "pi_139_refund"}'::jsonb);
    v_r := spot_refund('stripe', 'pi_139_refund', 'stripe charge.refunded');
    select * into v from promotions where id = (select id from t139 where k = 'assoc');
    if v_r ->> 'spot' <> 'ended' or v.ends_at > now() then
        raise exception 'FAIL: Stripe''s refund of an association''s vitrine: %', v_r;
    end if;

    -- Not settled (yet), or not a spot's payment (Mara Pro's charge): its
    -- mark only, no spot touched.
    v_r := spot_refund('stripe', 'pi_pro_139', 'stripe charge.refunded');
    if not (v_r ->> 'tombstone')::boolean
       or (select outcome from spot_purchases where external_id = 'pi_pro_139') <> 'tombstone' then
        raise exception 'FAIL: a foreign refund: %', v_r;
    end if;
    -- The Worker's alone.
    r := pg_temp.try139('13913913-0000-0000-0000-000000000002', $q$select spot_refund('apple', '3000000190')::text$q$);
    if r not like 'ERR: permission denied%' then raise exception 'FAIL: an owner refunds: %', r; end if;
    r := pg_temp.try139(null, $q$select spot_refund('apple', '3000000190')::text$q$, 'anon');
    if r not like 'ERR: permission denied%' then raise exception 'FAIL: anon refunds: %', r; end if;
    -- The platform heard of it.
    if not exists (select 1 from notifications where kind = 'spot_paid' and message like 'Maison Élégance : mise en avant remboursée (App Store).') then
        raise exception 'FAIL: the platform was not told of the refund';
    end if;
    raise notice 'PASS: Apple''s refund ends a running vitrine, Google''s voided purchase cancels a waiting article, Stripe''s refund (by its PaymentIntent) ends an association''s; once; a foreign one a mark only; the Worker''s alone; the platform told';
end $$;
rollback;

\echo ''
\echo '--- TEST 13: what a payment must never do — overturn a refusal, revive an ineligible spot, outrun its refund, shorten an older 30-day spot; and what it leaves for the platform ---'
begin;
update platform_settings set value = 'true' where key = 'stripe_on';
create temp table t139 (k text primary key, id uuid) on commit drop;
insert into t139 values
    ('farm',  pg_temp.ask139('13913913-0000-0000-0000-000000000003', '13900000-0000-0000-0000-000000000002', '139aaaaa-0000-0000-0000-000000000002')),
    ('assoc', pg_temp.ask139('13913913-0000-0000-0000-000000000004', '13900000-0000-0000-0000-000000000003', null)),
    ('shop',  '139ddddd-0000-0000-0000-000000000001'),
    ('old',   '139ddddd-0000-0000-0000-000000000002');
-- The platform refused the shop's article (a photo it would not show).
insert into promotions (id, org_id, product_id, kind, days, price, currency, status, decided_at) values
    ('139ddddd-0000-0000-0000-000000000001', '13900000-0000-0000-0000-000000000001', '139aaaaa-0000-0000-0000-000000000001',
     'article', 7, 5000, 'XOF', 'refused', now()),
    -- A 30-day vitrine asked before 139, waiting, in francs.
    ('139ddddd-0000-0000-0000-000000000002', '13900000-0000-0000-0000-000000000003', null,
     'shop', 30, 8000, 'XOF', 'requested', null);
grant select on t139 to authenticated;
do $$
declare v_r jsonb; v promotions%rowtype; r text; n int;
begin
    -- 1. A refused spot paid in the store: nothing programmed, the payment written for the platform.
    v_r := spot_settle('google', 'gp-139-refused', (select id from t139 where k = 'shop'),
                       'mara_spot_article_7', null, null, 'production');
    if (v_r ->> 'ok')::boolean or v_r ->> 'reason' <> 'refused' or not (v_r ->> 'recorded')::boolean then
        raise exception 'FAIL: a refused spot paid: %', v_r;
    end if;
    if exists (select 1 from promotions where org_id = '13900000-0000-0000-0000-000000000001' and status = 'approved') then
        raise exception 'FAIL: a refused spot went live by paying';
    end if;
    if (select outcome || ' ' || amount::text from spot_purchases where external_id = 'gp-139-refused') <> 'refused 5000.00' then
        raise exception 'FAIL: the refused payment not written';
    end if;
    -- Shown again: refused again, nothing more written.
    v_r := spot_settle('google', 'gp-139-refused', (select id from t139 where k = 'shop'),
                       'mara_spot_article_7', null, null, 'production');
    if v_r ->> 'reason' <> 'refused' or (select count(*) from spot_purchases where external_id = 'gp-139-refused') <> 1 then
        raise exception 'FAIL: the refused payment again: %', v_r;
    end if;

    -- 2. A spot no longer waiting whose article left the vitrine: a new one is not made.
    update promotions set status = 'cancelled' where id = (select id from t139 where k = 'farm');
    update products set is_published = false where id = '139aaaaa-0000-0000-0000-000000000002';
    v_r := spot_settle('apple', '3000000201', (select id from t139 where k = 'farm'),
                       'bf.kaj.app.spot.article7', 14.99, 'EUR', 'production');
    if v_r ->> 'reason' <> 'article' or exists (select 1 from promotions
            where org_id = '13900000-0000-0000-0000-000000000002' and status = 'approved') then
        raise exception 'FAIL: an ineligible article programmed: %', v_r;
    end if;
    update products set is_published = true where id = '139aaaaa-0000-0000-0000-000000000002';

    -- 3. The platform's « À faire »: the two to refund, then one done.
    r := pg_temp.try139('13913913-0000-0000-0000-000000000001', $q$select spot_refunds_todo() ->> 'spot_refunds'$q$);
    if r <> '2' then raise exception 'FAIL: the to-do counts % refunds', r; end if;
    r := pg_temp.try139('13913913-0000-0000-0000-000000000002', $q$select coalesce(spot_refunds_todo()::text, 'null')$q$);
    if r <> 'null' then raise exception 'FAIL: an owner reads the platform''s to-do: %', r; end if;
    r := pg_temp.try139('13913913-0000-0000-0000-000000000002', $q$select count(*)::text from platform_spot_refunds()$q$);
    if r not like 'ERR:%' then raise exception 'FAIL: an owner lists the refunds: %', r; end if;
    r := pg_temp.try139('13913913-0000-0000-0000-000000000001', $q$select string_agg(channel || ':' || reason, ',' order by created_at) from platform_spot_refunds()$q$);
    if r <> 'google:refused,apple:article' then raise exception 'FAIL: the refunds listed: %', r; end if;
    perform pg_temp.try139('13913913-0000-0000-0000-000000000001',
        format($q$select platform_spot_refund_done(%L)::text$q$, (select id from spot_purchases where external_id = '3000000201')));
    r := pg_temp.try139('13913913-0000-0000-0000-000000000001', $q$select spot_refunds_todo() ->> 'spot_refunds'$q$);
    if r <> '1' then raise exception 'FAIL: a refund said done still counts: %', r; end if;
    if not exists (select 1 from platform_actions where kind = 'spot_refund') then
        raise exception 'FAIL: the refund done not journaled';
    end if;

    -- 4. A refund heard before its payment was settled: the payment never programs.
    perform spot_refund('google', 'gp-139-early', 'google voided');
    v_r := spot_settle('google', 'gp-139-early', (select id from t139 where k = 'assoc'),
                       'mara_spot_shop_7', null, null, 'production');
    if v_r ->> 'reason' <> 'refunded' then raise exception 'FAIL: Google''s early refund outrun: %', v_r; end if;
    perform spot_refund('stripe', 'pi_139_early', 'stripe charge.refunded');
    v_r := spot_settle('stripe', 'cs_139_early', (select id from t139 where k = 'assoc'),
                       'stripe:shop', 15000, 'XOF', 'production', null, '{"payment_intent": "pi_139_early"}'::jsonb);
    if v_r ->> 'reason' <> 'refunded' then raise exception 'FAIL: Stripe''s early refund outrun: %', v_r; end if;
    perform spot_refund('apple', '3000000202', 'apple REFUND');
    v_r := spot_settle('apple', '3000000202', (select id from t139 where k = 'assoc'),
                       'bf.kaj.app.spot.shop7', 39.99, 'EUR', 'production');
    if v_r ->> 'reason' <> 'refunded' then raise exception 'FAIL: Apple''s early refund outrun: %', v_r; end if;
    if (select status from promotions where id = (select id from t139 where k = 'assoc')) <> 'requested' then
        raise exception 'FAIL: a refunded payment programmed the association''s vitrine';
    end if;

    -- 5. The purchase names another business than the spot's: refused, nothing written.
    v_r := spot_settle('google', 'gp-139-org', (select id from t139 where k = 'assoc'),
                       'mara_spot_shop_7', null, null, 'production', null, null, 'store',
                       '13900000-0000-0000-0000-000000000007');
    if v_r ->> 'reason' <> 'wrong_org' or exists (select 1 from spot_purchases where external_id = 'gp-139-org') then
        raise exception 'FAIL: another business''s purchase: %', v_r;
    end if;

    -- 6. A 30-day vitrine asked before 139, paid by card at its 30-day price: 30 days.
    v_r := pg_temp.try139('13913913-0000-0000-0000-000000000004',
            $q$select spot_stripe_begin('139ddddd-0000-0000-0000-000000000002')::text$q$)::jsonb;
    if (v_r ->> 'amount')::int <> 8000 then raise exception 'FAIL: the older spot''s card price: %', v_r; end if;
    v_r := spot_settle('stripe', 'cs_139_thirty', '139ddddd-0000-0000-0000-000000000002', 'stripe:shop',
                       8000, 'XOF', 'production');
    select * into v from promotions where id = '139ddddd-0000-0000-0000-000000000002';
    if v.status <> 'approved' or v.days <> 30 or v.ends_at - v.starts_at <> interval '30 days'
       or (v_r ->> 'ends_at')::timestamptz <> v.ends_at then
        raise exception 'FAIL: an older 30-day spot paid got % days (%)', v.days, v.ends_at - v.starts_at;
    end if;

    -- 7. A spot gone: the caller is told so (to have the payment written), nothing else.
    r := pg_temp.try139('13913913-0000-0000-0000-000000000002',
            $q$select spot_verify_begin('139eeeee-0000-0000-0000-000000000009')::text$q$);
    if (r::jsonb ->> 'missing')::boolean is not true or r::jsonb ? 'org_id' then
        raise exception 'FAIL: a spot gone: %', r;
    end if;
    v_r := spot_settle('apple', '3000000203', '139eeeee-0000-0000-0000-000000000009',
                       'bf.kaj.app.spot.article7', 14.99, 'EUR', 'production');
    if v_r ->> 'reason' <> 'no spot' or (select outcome from spot_purchases where external_id = '3000000203') <> 'refused' then
        raise exception 'FAIL: a payment for a spot gone not written: %', v_r;
    end if;

    -- 8. Réglages: no price below what the card takes.
    r := pg_temp.try139('13913913-0000-0000-0000-000000000001',
        $q$select platform_set_setting('spot_price_article_7', '200')::text$q$);
    if r <> 'ERR: Au moins 300 FCFA : le paiement par carte (Stripe) ne prend pas moins.' then
        raise exception 'FAIL: 200 FCFA gave %', r;
    end if;
    r := pg_temp.try139('13913913-0000-0000-0000-000000000001',
        $q$select platform_set_setting('pro_price_month_eur', '0.40')::text$q$);
    if r <> 'ERR: Au moins 0,50 : le paiement par carte (Stripe) ne prend pas moins.' then
        raise exception 'FAIL: 0,40 € gave %', r;
    end if;
    raise notice 'PASS: a refused spot is not overturned by paying, an ineligible article not revived — both written for the platform''s « À faire », counted, listed and said done (journaled); a refund heard first (Google, Stripe, Apple) wins; another business''s purchase refused; an older 30-day spot keeps its 30 days; a spot gone is written; no card price below 300 FCFA or 0,50';
end $$;
rollback;

\echo ''
\echo '--- TEST 12: the doors ---'
do $$
declare v text;
begin
    select string_agg(p.proname, ', ') into v
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('price_zone', 'zone_currency', 'spot_zone_price', 'pro_zone_price',
                         'stripe_minor_units', 'spot_terms', 'request_promotion', 'spot_verify_begin',
                         'spot_settle', 'spot_stripe_begin', 'stripe_begin', 'plan_terms',
                         'platform_set_setting', 'spot_refund', 'spot_ineligible', 'next_spot_start',
                         'decide_promotion', 'spot_refunds_todo', 'platform_spot_refunds',
                         'platform_spot_refund_done')
       and (has_function_privilege('anon', p.oid, 'execute')
            or not coalesce((select true from unnest(p.proconfig) c where c like 'search_path=%'), false));
    if v is not null then raise exception 'FAIL: open to anon, or no pinned path: %', v; end if;
    if has_function_privilege('authenticated', 'spot_settle(text, text, uuid, text, numeric, text, text, uuid, jsonb, text, uuid)', 'execute') then
        raise exception 'FAIL: spot_settle is authenticated''s';
    end if;
    if has_function_privilege('authenticated', 'spot_refund(text, text, text)', 'execute')
       or not has_function_privilege('service_role', 'spot_refund(text, text, text)', 'execute') then
        raise exception 'FAIL: spot_refund is not the Worker''s alone';
    end if;
    select string_agg(p.proname || ':' || p.prosecdef, ', ' order by p.proname) into v
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('spot_settle', 'spot_verify_begin', 'spot_stripe_begin',
                                                  'request_promotion', 'stripe_begin', 'price_zone', 'spot_zone_price');
    if v <> 'price_zone:false, request_promotion:true, spot_settle:true, spot_stripe_begin:true, spot_verify_begin:true, spot_zone_price:false, stripe_begin:true' then
        raise exception 'FAIL: definer or invoker not as meant: %', v;
    end if;
    if not (select relrowsecurity from pg_class where oid = 'spot_purchases'::regclass) then
        raise exception 'FAIL: spot_purchases without RLS';
    end if;
    if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                where n.nspname = 'public' and c.relkind = 'v' and c.relname like '%spot%') then
        raise exception 'FAIL: a view was added';
    end if;
    if not exists (select 1 from pg_trigger where tgrelid = 'spot_purchases'::regclass and tgname = 'same_org') then
        raise exception 'FAIL: spot_purchases has no same-business guard';
    end if;
    raise notice 'PASS: every 139 function pinned and closed to anon; spot_settle and spot_refund never authenticated''s; definers and invokers as meant; RLS on spot_purchases, 127''s guard, no view';
end $$;

\echo ''
\echo '=== test_batch139.sql: all checks passed ==='
