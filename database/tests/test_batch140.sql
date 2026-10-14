-- ============================================================
-- test_batch140.sql — batch 144 (140): a business's money follows where
-- it is, for a shop, a farm and an association alike.
--
-- The claims:
--   * currency_decimals is ISO 4217's minor units: 0 for XOF, XAF, JPY,
--     GNF; 2 for EUR, USD, BRL, NGN and any code it does not know — and
--     for the dinars ISO gives three (TND, LYD, KWD, BHD, OMR, JOD), as
--     the books' numeric(14,2) columns keep; any case; amount_text and
--     money_text write an amount as the app's moneyFormat does, whatever
--     the server's locale — « 12 500 FCFA » for XOF and XAF alike,
--     « 12,50 EUR », « 1,23 TND », a trillion francs whole,
--     « 1 500 JPY », a negative « -3,00 EUR », no amount no text;
--   * the street's cards: storefront_currencies, read signed out, says the
--     money of each open vitrine asked for — a Paris shop EUR, a São Paulo
--     farm BRL, a New York association USD, an Ouagadougou shop XOF, a
--     Douala shop XAF — and nothing of a closed vitrine or a slug nobody
--     owns; it says the slug and the money only;
--   * a delivery's price: the franc CFA still rounded to 25 F (XOF and
--     XAF, the same answer as before 140), the euro to the cent (2,50 € +
--     0,80 €/km is never 0 € or 25 €), the platform's franc CFA tariff
--     never offered to a business in euros;
--   * the basket: an order is one vitrine's, in its money — a Paris
--     order's currency EUR, its total in euros with its cents; an article
--     of another vitrine (a São Paulo farm's in reais) refused in the same
--     basket;
--   * the bells: « Nouvelle commande … : 25,00 EUR » for Paris, « 18,90
--     BRL » for São Paulo, « 10 000 FCFA + livraison 1 200 FCFA » for
--     Douala (never « 12,000.00 XOF »); a courier told « (4,10 EUR) » and
--     thanked « : 25,00 EUR. », never « F »; Wave's « Commande payée par
--     Wave : 25,00 EUR. »; « Crédit soldé … 30,00 EUR »; each function's
--     signature, SECURITY DEFINER and pinned path unchanged;
--   * « Prix en baisse »: a follower of the Paris shop reads « à 9,90 EUR »
--     (not « à 10 EUR »), of the Ouagadougou shop « à 450 FCFA »;
--   * totals across businesses per money: a courier's tally, the
--     settlement, « Revenus de Mara » (delivery_cut in francs CFA only,
--     the others beside), the platform's analytics and each business's
--     money — platform-only or the courier's own, none open to anon;
--   * no business's money is changed by 140; grants: the helpers closed
--     to anon, storefront_currencies open to anon and authenticated, a
--     definer with its path pinned; run twice, the same.
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
grant usage on schema auth to authenticated;
-- Earlier suites re-apply older migrations (110's delivery_fee, 113's
-- trigger) and hand the app's roles every function: 140 again.
\i database/migrations/140_prices_by_area.sql

update platform_settings set value = '1'
 where key in ('vitrine_min_items', 'vitrine_min_items_association');

insert into auth.users (id, phone, raw_user_meta_data) values
    ('14014014-0000-0000-0000-000000000001', '+33614000001', '{"full_name": "Gérante Maison Élégance 140"}'),
    ('14014014-0000-0000-0000-000000000002', '+5511914000002', '{"full_name": "Gérant Ferme Soleil Levant 140"}'),
    ('14014014-0000-0000-0000-000000000003', '+12124000003', '{"full_name": "Trésorière Fondation Espoir 140"}'),
    ('14014014-0000-0000-0000-000000000004', '+22614000004', '{"full_name": "Gérant Atelier Lumière 140"}'),
    ('14014014-0000-0000-0000-000000000005', '+22614000005', '{"full_name": "Client 140"}');

insert into orgs (id, name, slug, profile, default_currency, plan, plan_until, storefront_enabled,
                  storefront_blurb, phone, lat, lng, delivery_base, delivery_per_km) values
    -- Paris: euros, its own tariff in euros.
    ('14000000-0000-0000-0000-0000000000a1', 'Maison Élégance',    'paris-140',    'retail',      'EUR', 'pro', '2099-01-01', true,
     'Bienvenue', '+33614000101', 48.8566, 2.3522, 2.5, 0.8),
    -- São Paulo: a farm in reais.
    ('14000000-0000-0000-0000-0000000000a2', 'Ferme Soleil Levant', 'saopaulo-140', 'farm',        'BRL', 'free', null,        true,
     'Bienvenue', '+5511914000102', -23.5505, -46.6333, null, null),
    -- New York: an association in dollars.
    ('14000000-0000-0000-0000-0000000000a3', 'Fondation Espoir',   'newyork-140',  'association', 'USD', 'free', null,        true,
     'Bienvenue', '+12124000103', 40.7128, -74.0060, null, null),
    -- Ouagadougou: francs CFA, its own tariff in francs.
    ('14000000-0000-0000-0000-0000000000a4', 'Atelier Lumière',    'ouaga-140',    'retail',      'XOF', 'pro', '2099-01-01', true,
     'Bienvenue', '+22670140104', 12.3714, -1.5197, 500, 150),
    -- Douala: the other franc CFA.
    ('14000000-0000-0000-0000-0000000000a5', 'Le Comptoir Doré',   'douala-140',   'retail',      'XAF', 'pro', '2099-01-01', true,
     'Bienvenue', '+23769140105', 4.0511, 9.7679, 300, 110),
    -- Paris again, with no tariff of its own: the platform's is in francs.
    ('14000000-0000-0000-0000-0000000000a6', 'Atelier Rivoli',     'rivoli-140',   'retail',      'EUR', 'pro', '2099-01-01', true,
     'Bienvenue', '+33614000106', 48.8606, 2.3376, null, null),
    -- A closed vitrine: nothing of it on the street.
    ('14000000-0000-0000-0000-0000000000a7', 'Maison Close',       'ferme-140',    'retail',      'EUR', 'free', null,        false,
     'Bienvenue', '+33614000107', null, null, null, null);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    ('14000000-0000-0000-0000-0000000000a1', '14014014-0000-0000-0000-000000000001', 'owner', 'org', '14000000-0000-0000-0000-0000000000a1', 'full'),
    ('14000000-0000-0000-0000-0000000000a6', '14014014-0000-0000-0000-000000000001', 'owner', 'org', '14000000-0000-0000-0000-0000000000a6', 'full'),
    ('14000000-0000-0000-0000-0000000000a2', '14014014-0000-0000-0000-000000000002', 'owner', 'org', '14000000-0000-0000-0000-0000000000a2', 'full'),
    ('14000000-0000-0000-0000-0000000000a3', '14014014-0000-0000-0000-000000000003', 'owner', 'org', '14000000-0000-0000-0000-0000000000a3', 'full'),
    ('14000000-0000-0000-0000-0000000000a4', '14014014-0000-0000-0000-000000000004', 'owner', 'org', '14000000-0000-0000-0000-0000000000a4', 'full'),
    ('14000000-0000-0000-0000-0000000000a5', '14014014-0000-0000-0000-000000000004', 'owner', 'org', '14000000-0000-0000-0000-0000000000a5', 'full'),
    ('14000000-0000-0000-0000-0000000000a7', '14014014-0000-0000-0000-000000000001', 'owner', 'org', '14000000-0000-0000-0000-0000000000a7', 'full');

insert into products (id, org_id, name, sale_price, cost_price, quantity, unit, is_active, is_published) values
    ('140aaaaa-0000-0000-0000-000000000001', '14000000-0000-0000-0000-0000000000a1', 'Foulard 140',    12.50, 6, 10, null,      true, true),
    ('140aaaaa-0000-0000-0000-000000000002', '14000000-0000-0000-0000-0000000000a2', 'Œufs 140',       18.90, 0, 40, 'plateau', true, true),
    ('140aaaaa-0000-0000-0000-000000000003', '14000000-0000-0000-0000-0000000000a3', 'Livre 140',       9.99, 0,  5, null,      true, true),
    ('140aaaaa-0000-0000-0000-000000000004', '14000000-0000-0000-0000-0000000000a4', 'Savon 140',       500, 300, 50, null,      true, true),
    ('140aaaaa-0000-0000-0000-000000000005', '14000000-0000-0000-0000-0000000000a5', 'Pagne 140',      5000, 3000, 9, null,      true, true),
    ('140aaaaa-0000-0000-0000-000000000006', '14000000-0000-0000-0000-0000000000a6', 'Bougie 140',      7.20, 3,  9, null,      true, true),
    ('140aaaaa-0000-0000-0000-000000000007', '14000000-0000-0000-0000-0000000000a7', 'Caché 140',       1.00, 1,  9, null,      true, true);

create temp table b140_before as select id, default_currency from orgs;

\echo ''
\echo '--- TEST 1: minor units and amounts ---'
do $$ begin
    if currency_decimals('XOF') <> 0 or currency_decimals('XAF') <> 0 or currency_decimals('JPY') <> 0
       or currency_decimals('GNF') <> 0 or currency_decimals('xof') <> 0 then
        raise exception 'FAIL: a money without a minor unit';
    end if;
    if currency_decimals('EUR') <> 2 or currency_decimals('USD') <> 2 or currency_decimals('BRL') <> 2
       or currency_decimals('NGN') <> 2 or currency_decimals('GHS') <> 2 or currency_decimals('ZZZ') <> 2
       or currency_decimals(null) <> 2 then
        raise exception 'FAIL: a money with cents';
    end if;
    -- ISO gives these three; the books' columns are numeric(14,2): two.
    if currency_decimals('TND') <> 2 or currency_decimals('KWD') <> 2 or currency_decimals('LYD') <> 2
       or currency_decimals('BHD') <> 2 or currency_decimals('OMR') <> 2 or currency_decimals('JOD') <> 2 then
        raise exception 'FAIL: a three-decimal dinar not kept at two';
    end if;
    -- As intl's fr_FR writes them: a narrow no-break space between the
    -- thousands, a no-break space before the money.
    if amount_text(12500, 'XOF') <> '12' || U&'\202F' || '500'
       or amount_text(450, 'XOF') <> '450'
       or amount_text(12.5, 'EUR') <> '12,50'
       or amount_text(0.5, 'USD') <> '0,50'
       or amount_text(1.2345, 'TND') <> '1,23'
       or amount_text(1234567.891, 'TND') <> '1' || U&'\202F' || '234' || U&'\202F' || '567,89'
       or amount_text(1234567890123, 'XOF') <> '1' || U&'\202F' || '234' || U&'\202F' || '567'
                                               || U&'\202F' || '890' || U&'\202F' || '123'
       or amount_text(2500000000.5, 'EUR') <> '2' || U&'\202F' || '500' || U&'\202F' || '000'
                                              || U&'\202F' || '000,50'
       or amount_text(1500, 'JPY') <> '1' || U&'\202F' || '500'
       or amount_text(999.995, 'EUR') <> '1' || U&'\202F' || '000,00'
       or amount_text(-3.004, 'EUR') <> '-3,00'
       or amount_text(-0.001, 'EUR') <> '0,00'
       or amount_text(null, 'EUR') is not null then
        raise exception 'FAIL: amount_text % % %', amount_text(12500, 'XOF'), amount_text(12.5, 'EUR'), amount_text(0.5, 'USD');
    end if;
    if money_text(12000, 'XOF') <> '12' || U&'\202F' || '000' || U&'\00A0' || 'FCFA'
       or money_text(12000, 'XAF') <> '12' || U&'\202F' || '000' || U&'\00A0' || 'FCFA'
       or money_text(12000, null) <> '12' || U&'\202F' || '000' || U&'\00A0' || 'FCFA'
       or money_text(12.5, 'EUR') <> '12,50' || U&'\00A0' || 'EUR'
       or money_text(12.5, 'eur') <> '12,50' || U&'\00A0' || 'EUR'
       or money_text(18.9, 'BRL') <> '18,90' || U&'\00A0' || 'BRL'
       or money_text(null, 'EUR') is not null then
        raise exception 'FAIL: money_text % %', money_text(12000, 'XAF'), money_text(12.5, 'EUR');
    end if;
    -- Whatever the server's locale: to_char's G and D are not used.
    if exists (select 1 from pg_proc where proname in ('amount_text', 'money_text', 'currency_symbol')
                and (prosrc ~ 'to_char' or prosecdef)) then
        raise exception 'FAIL: a money helper reads the locale, or is a definer';
    end if;
    raise notice 'PASS: XOF, XAF, JPY, GNF without decimals; EUR, USD, BRL, NGN, GHS and the unknown with two; the three-decimal dinars two, as the books keep; amounts of a billion and more; written as the app writes them, « FCFA » for both francs CFA';
end $$;

\echo ''
\echo '--- TEST 2: the street''s cards say each vitrine''s money, signed out ---'
begin;
set local role anon;
set local "request.jwt.claim.sub" = '';
do $$
declare got jsonb;
begin
    select jsonb_object_agg(slug, currency) into got
      from storefront_currencies(array['paris-140', 'saopaulo-140', 'newyork-140', 'ouaga-140',
                                       'douala-140', 'ferme-140', 'personne-140']);
    if got <> '{"paris-140": "EUR", "saopaulo-140": "BRL", "newyork-140": "USD",
                "ouaga-140": "XOF", "douala-140": "XAF"}'::jsonb then
        raise exception 'FAIL: the cards'' money %', got;
    end if;
    if exists (select 1 from storefront_currencies(null)) or exists (select 1 from storefront_currencies('{}')) then
        raise exception 'FAIL: no slug, no answer';
    end if;
    raise notice 'PASS: Paris EUR, São Paulo BRL, New York USD, Ouagadougou XOF, Douala XAF; a closed vitrine and a stranger''s slug say nothing';
end $$;
commit;
do $$ begin
    -- The same vitrines the menu board shows (070).
    if (select array_agg(distinct slug order by slug)
          from storefront_previews(array['paris-140', 'ferme-140', 'saopaulo-140', 'personne-140']))
       <> (select array_agg(slug order by slug)
             from storefront_currencies(array['paris-140', 'ferme-140', 'saopaulo-140', 'personne-140'])) then
        raise exception 'FAIL: the previews and the money do not answer for the same vitrines';
    end if;
    if (select proargnames from pg_proc where proname = 'storefront_currencies')
       <> array['p_slugs', 'slug', 'currency'] then
        raise exception 'FAIL: the door says more than the slug and the money';
    end if;
    raise notice 'PASS: the slug and the money, nothing else';
end $$;

\echo ''
\echo '--- TEST 3: a delivery''s price in its own money ---'
do $$
declare
    -- A customer's door about 3 km from each shop.
    v_km  double precision;
    v_fee numeric;
    v_raw numeric;
begin
    -- Paris: 2,50 € + 0,80 €/km, to the cent.
    v_km  := distance_km(48.8566, 2.3522, 48.8800, 2.3700);
    v_raw := 2.5 + 0.8 * greatest(0, v_km);
    v_fee := delivery_fee('14000000-0000-0000-0000-0000000000a1', 48.8800, 2.3700);
    if v_fee is distinct from round(v_raw, 2) or v_fee in (0, 25) or v_fee <> round(v_fee, 2) then
        raise exception 'FAIL: the Paris fee % (raw %)', v_fee, v_raw;
    end if;
    -- Ouagadougou: 500 F + 150 F/km, to the 25 F as before 140.
    v_km  := distance_km(12.3714, -1.5197, 12.3900, -1.5000);
    v_raw := 500 + 150 * greatest(0, v_km);
    v_fee := delivery_fee('14000000-0000-0000-0000-0000000000a4', 12.3900, -1.5000);
    if v_fee is distinct from round(v_raw / 25) * 25 or mod(v_fee, 25) <> 0 then
        raise exception 'FAIL: the Ouagadougou fee % (raw %)', v_fee, v_raw;
    end if;
    -- Douala: the other franc CFA, to the 25 F too.
    v_raw := 300 + 110 * greatest(0, distance_km(4.0511, 9.7679, 4.0700, 9.7500));
    v_fee := delivery_fee('14000000-0000-0000-0000-0000000000a5', 4.0700, 9.7500);
    if v_fee is distinct from round(v_raw / 25) * 25 then
        raise exception 'FAIL: the Douala fee % (raw %)', v_fee, v_raw;
    end if;
    -- A euro shop with no tariff of its own: the platform's is in francs.
    if delivery_fee('14000000-0000-0000-0000-0000000000a6', 48.8700, 2.3500) is not null then
        raise exception 'FAIL: the platform''s franc tariff offered in euros';
    end if;
    raise notice 'PASS: Paris to the cent, Ouagadougou and Douala to the 25 F, no franc tariff for a euro shop';
end $$;

\echo ''
\echo '--- TEST 4: one basket, one vitrine, one money ---'
create temp table t140 (which text primary key, id uuid);
grant all on t140 to authenticated, anon;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '14014014-0000-0000-0000-000000000005';
do $$ begin
    insert into t140 values ('paris', place_order('paris-140',
        jsonb_build_array(jsonb_build_object('product_id', '140aaaaa-0000-0000-0000-000000000001', 'quantity', 2)),
        'pickup', null, null, null, 'cash'));
    -- The São Paulo farm's eggs in the Paris basket: refused.
    begin
        perform place_order('paris-140',
            jsonb_build_array(
                jsonb_build_object('product_id', '140aaaaa-0000-0000-0000-000000000001', 'quantity', 1),
                jsonb_build_object('product_id', '140aaaaa-0000-0000-0000-000000000002', 'quantity', 1)),
            'pickup', null, null, null, 'cash');
        raise exception 'FAIL: two vitrines in one basket';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like '%not in this shop%' then raise exception 'FAIL: refused for %', sqlerrm; end if;
    end;
    insert into t140 values ('saopaulo', place_order('saopaulo-140',
        jsonb_build_array(jsonb_build_object('product_id', '140aaaaa-0000-0000-0000-000000000002', 'quantity', 1)),
        'pickup', null, null, null, 'cash'));
end $$;
commit;
do $$ begin
    if (select currency from orders where id = (select id from t140 where which = 'paris')) <> 'EUR'
       or (select total from orders where id = (select id from t140 where which = 'paris')) <> 25.00 then
        raise exception 'FAIL: the Paris order is not 25,00 EUR';
    end if;
    if (select currency from orders where id = (select id from t140 where which = 'saopaulo')) <> 'BRL'
       or (select total from orders where id = (select id from t140 where which = 'saopaulo')) <> 18.90 then
        raise exception 'FAIL: the São Paulo order is not 18,90 BRL';
    end if;
    if (select count(*) from orders where org_id = '14000000-0000-0000-0000-0000000000a1') <> 1 then
        raise exception 'FAIL: the refused basket left an order';
    end if;
    raise notice 'PASS: a Paris order in euros with its cents, a São Paulo order in reais, two vitrines never in one basket';
end $$;

\echo ''
\echo '--- TEST 4b: the bells say each order''s money as the app writes it ---'
-- A Douala delivery, to hear the fee too.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '14014014-0000-0000-0000-000000000005';
do $$ begin
    insert into t140 values ('douala', place_order('douala-140',
        jsonb_build_array(jsonb_build_object('product_id', '140aaaaa-0000-0000-0000-000000000005', 'quantity', 2)),
        'delivery', null, 'Akwa', null, 'cash', 4.0700, 9.7500));
end $$;
commit;
do $$
declare
    nb  constant text := U&'\00A0';
    th  constant text := U&'\202F';
    m   text;
    v_o orders%rowtype;
    v_n int;
begin
    select message into m from notifications
     where kind = 'new_order' and params ->> 'order_id' = (select id from t140 where which = 'paris')::text;
    if m is distinct from 'Nouvelle commande de Client 140 : 25,00' || nb || 'EUR' then
        raise exception 'FAIL: the Paris order bell %', m;
    end if;
    select message into m from notifications
     where kind = 'new_order' and params ->> 'order_id' = (select id from t140 where which = 'saopaulo')::text;
    if m is distinct from 'Nouvelle commande de Client 140 : 18,90' || nb || 'BRL' then
        raise exception 'FAIL: the São Paulo order bell %', m;
    end if;
    select * into v_o from orders where id = (select id from t140 where which = 'douala');
    select message into m from notifications
     where kind = 'new_order' and params ->> 'order_id' = v_o.id::text;
    if v_o.delivery_fee is null
       or m is distinct from 'Nouvelle commande de Client 140 : 10' || th || '000' || nb || 'FCFA + livraison '
                             || money_text(v_o.delivery_fee, 'XAF')
       or m !~ ('livraison [0-9' || th || ']+' || nb || 'FCFA$') then
        raise exception 'FAIL: the Douala order bell %', m;
    end if;
    -- The params, from which the English line is written, unchanged.
    if (select params from notifications where kind = 'new_order' and params ->> 'order_id' = v_o.id::text)
       - 'order_id' <> jsonb_build_object('to', 'shop', 'booking', false, 'name', 'Client 140',
                                          'total', 10000, 'currency', 'XAF', 'wave', false,
                                          'fee', v_o.delivery_fee) then
        raise exception 'FAIL: the order bell''s params %',
            (select params from notifications where kind = 'new_order' and params ->> 'order_id' = v_o.id::text);
    end if;

    -- A courier of the Paris shop told of a delivery in euros, then thanked.
    insert into couriers (user_id, phone, status, decided_at)
    values ('14014014-0000-0000-0000-000000000004', '+22614000004', 'approved', now());
    insert into org_couriers (org_id, user_id)
    values ('14000000-0000-0000-0000-0000000000a1', '14014014-0000-0000-0000-000000000004');
    update orders set fulfilment = 'delivery', address = 'Rue de Rivoli', delivery_fee = 4.10,
                      drop_lat = 48.8800, drop_lng = 2.3700
     where id = (select id from t140 where which = 'paris');
    v_n := tell_couriers((select id from t140 where which = 'paris'), true);
    select message into m from notifications
     where kind = 'delivery_available' and recipient_id = '14014014-0000-0000-0000-000000000004'
       and params ->> 'order_id' = (select id from t140 where which = 'paris')::text;
    if v_n <> 1 or m is distinct from 'Nouvelle livraison près de vous : Maison Élégance (4,10' || nb || 'EUR)' then
        raise exception 'FAIL: the courier''s bell % (%)', m, v_n;
    end if;
    update orders set courier_id = '14014014-0000-0000-0000-000000000004', cash_received_at = now()
     where id = (select id from t140 where which = 'paris');
    select message into m from notifications
     where kind = 'courier_cash_received' and params ->> 'order_id' = (select id from t140 where which = 'paris')::text;
    if m is distinct from 'Maison Élégance confirme avoir reçu l''argent de la livraison pour Client 140 : 25,00'
                          || nb || 'EUR.' then
        raise exception 'FAIL: the courier''s cash bell %', m;
    end if;
    raise notice 'PASS: « 25,00 EUR », « 18,90 BRL », « 10 000 FCFA + livraison … FCFA » for Douala; the courier told « (4,10 EUR) » and thanked « 25,00 EUR. »; the params unchanged';
end $$;

-- Wave's bell for an order (the Worker's call, as postgres here).
do $$
declare
    v_pay uuid;
    m     text;
begin
    update orgs set wave_allowed = true where id = '14000000-0000-0000-0000-0000000000a1';
    insert into wave_payments (org_id, kind, order_id, amount, currency, commission, payer_id, status)
    values ('14000000-0000-0000-0000-0000000000a1', 'order', (select id from t140 where which = 'paris'),
            25, 'EUR', 0, '14014014-0000-0000-0000-000000000005', 'open')
    returning id into v_pay;
    perform wave_settle(v_pay, null, true, 'T140');
    select message into m from notifications
     where kind = 'order_paid' and params ->> 'to' = 'shop'
       and params ->> 'order_id' = (select id from t140 where which = 'paris')::text;
    if m is distinct from 'Commande payée par Wave : 25,00' || U&'\00A0' || 'EUR. L''argent part sur votre numéro Wave.' then
        raise exception 'FAIL: Wave''s bell %', m;
    end if;
    raise notice 'PASS: « Commande payée par Wave : 25,00 EUR. »';
end $$;

-- A credit settled in euros (it said « 30 », no money).
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '14014014-0000-0000-0000-000000000001';
do $$
declare v_debt uuid;
begin
    v_debt := record_credit_sale('14000000-0000-0000-0000-0000000000a1'::uuid, 'Awa 140', 30, 'Foulard');
    perform record_debt_payment(v_debt, 12.5);
    perform record_debt_payment(v_debt, 17.5);
end $$;
commit;
do $$
declare m text;
begin
    select message into m from notifications
     where kind = 'debt_settled' and org_id = '14000000-0000-0000-0000-0000000000a1';
    if m is distinct from 'Crédit soldé : Awa 140 a fini de payer 30,00' || U&'\00A0' || 'EUR' then
        raise exception 'FAIL: the credit bell %', m;
    end if;
    raise notice 'PASS: « Crédit soldé : Awa 140 a fini de payer 30,00 EUR »';
end $$;

-- The bells' functions: the same signature, a pinned definer each.
do $$
declare
    f text;
begin
    foreach f in array array[
        'place_order(text, jsonb, text, text, text, text, text, double precision, double precision)',
        'tell_couriers(uuid, boolean)', 'trg_notify_courier_cash()',
        'wave_settle(uuid, text, boolean, text)', 'trg_notify_debt_settled()',
        'trg_vitrine_news()', 'delivery_fee(uuid, double precision, double precision)'] loop
        if not exists (select 1 from pg_proc where oid = f::regprocedure and prosecdef
                         and proconfig @> array['search_path=public']) then
            raise exception 'FAIL: % is not a pinned definer', f;
        end if;
    end loop;
    if not has_function_privilege('authenticated', 'place_order(text, jsonb, text, text, text, text, text, double precision, double precision)', 'execute')
       or has_function_privilege('anon', 'place_order(text, jsonb, text, text, text, text, text, double precision, double precision)', 'execute')
       or has_function_privilege('authenticated', 'wave_settle(uuid, text, boolean, text)', 'execute')
       or has_function_privilege('authenticated', 'tell_couriers(uuid, boolean)', 'execute') then
        raise exception 'FAIL: a bell''s function changed hands';
    end if;
    raise notice 'PASS: each bell''s function a pinned definer, its grants as before';
end $$;

\echo ''
\echo '--- TEST 5: « Prix en baisse » in the money''s decimals ---'
insert into vitrine_follows (user_id, org_id, news) values
    ('14014014-0000-0000-0000-000000000005', '14000000-0000-0000-0000-0000000000a1', true),
    ('14014014-0000-0000-0000-000000000005', '14000000-0000-0000-0000-0000000000a4', true);
update products set sale_price = 9.90 where id = '140aaaaa-0000-0000-0000-000000000001';
update products set sale_price = 450 where id = '140aaaaa-0000-0000-0000-000000000004';
do $$
declare m text;
begin
    select message into m from notifications
     where recipient_id = '14014014-0000-0000-0000-000000000005' and kind = 'vitrine_news'
       and org_id = '14000000-0000-0000-0000-0000000000a1';
    if m is distinct from 'Prix en baisse chez Maison Élégance : Foulard 140 à 9,90' || U&'\00A0' || 'EUR' then
        raise exception 'FAIL: the Paris bell %', m;
    end if;
    select message into m from notifications
     where recipient_id = '14014014-0000-0000-0000-000000000005' and kind = 'vitrine_news'
       and org_id = '14000000-0000-0000-0000-0000000000a4';
    if m is distinct from 'Prix en baisse chez Atelier Lumière : Savon 140 à 450' || U&'\00A0' || 'FCFA' then
        raise exception 'FAIL: the Ouagadougou bell %', m;
    end if;
    raise notice 'PASS: « à 9,90 EUR » for Paris, « à 450 FCFA » for Ouagadougou';
end $$;

\echo ''
\echo '--- TEST 6: grants, and no business''s money changed ---'
do $$ begin
    if has_function_privilege('anon', 'currency_decimals(text)', 'execute')
       or has_function_privilege('anon', 'amount_text(numeric, text)', 'execute')
       or has_function_privilege('anon', 'money_text(numeric, text)', 'execute')
       or has_function_privilege('anon', 'currency_symbol(text)', 'execute')
       or has_function_privilege('anon', 'delivery_fee(uuid, double precision, double precision)', 'execute')
       or has_function_privilege('anon', 'trg_vitrine_news()', 'execute') then
        raise exception 'FAIL: a helper open to anon';
    end if;
    if not has_function_privilege('anon', 'storefront_currencies(text[])', 'execute')
       or not has_function_privilege('authenticated', 'storefront_currencies(text[])', 'execute') then
        raise exception 'FAIL: the street cannot read its cards'' money';
    end if;
    if not (select prosecdef from pg_proc where proname = 'storefront_currencies')
       or not exists (select 1 from pg_proc where proname = 'storefront_currencies'
                       and proconfig @> array['search_path=public']) then
        raise exception 'FAIL: storefront_currencies is not a pinned definer';
    end if;
    if exists (select 1 from orgs o join b140_before b using (id)
                where o.default_currency is distinct from b.default_currency) then
        raise exception 'FAIL: a business''s money changed';
    end if;
    raise notice 'PASS: the helpers closed to anon, the street''s door open, a pinned definer; every business keeps its money';
end $$;

\echo ''
\echo '--- TEST 6b: totals across businesses, one money never added to another ---'
-- A courier who carried for Ouagadougou (francs) and Paris (euros) today.
insert into orders (org_id, customer_id, customer_name, status, fulfilment, address,
                    total, currency, courier_id, drop_lat, drop_lng, delivery_fee, updated_at) values
    ('14000000-0000-0000-0000-0000000000a4', '14014014-0000-0000-0000-000000000005', 'Client 140', 'delivered',
     'delivery', 'Dassasgho', 1000, 'XOF', '14014014-0000-0000-0000-000000000004', 12.3894, -1.5197, 800,
     date_trunc('day', now() at time zone 'Africa/Ouagadougou') at time zone 'Africa/Ouagadougou' + interval '1 minute'),
    ('14000000-0000-0000-0000-0000000000a1', '14014014-0000-0000-0000-000000000005', 'Client 140', 'delivered',
     'delivery', 'Rivoli', 25, 'EUR', '14014014-0000-0000-0000-000000000004', 48.8800, 2.3700, 4.10,
     date_trunc('day', now() at time zone 'Africa/Ouagadougou') at time zone 'Africa/Ouagadougou' + interval '1 minute');
update profiles set is_platform_admin = true where id = '14014014-0000-0000-0000-000000000003';
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '14014014-0000-0000-0000-000000000004';
do $$
declare got jsonb;
begin
    select jsonb_object_agg(currency, jsonb_build_array(courses, fees)) into got
      from courier_earnings_by_currency() where period = 'today';
    if got <> '{"XOF": [1, 800], "EUR": [1, 4.10]}'::jsonb then
        raise exception 'FAIL: the courier''s today by money %', got;
    end if;
    if (select count(*) from courier_earnings_by_currency()) <> 6 then
        raise exception 'FAIL: each period says each money';
    end if;
    raise notice 'PASS: the courier''s today « 800 FCFA » and « 4,10 EUR », not « 804,10 »';
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '14014014-0000-0000-0000-000000000003';
do $$
declare
    got jsonb;
    t   jsonb := platform_today() -> 'money';
begin
    select jsonb_object_agg(currency, fees) into got
      from platform_delivery_settlement_by_currency()
     where courier_id = '14014014-0000-0000-0000-000000000004';
    if got <> '{"XOF": 800, "EUR": 4.10}'::jsonb then
        raise exception 'FAIL: the settlement by money %', got;
    end if;
    if (t ->> 'delivery_cut')::numeric
         <> (select coalesce(sum(platform_fee), 0) from orders
              where status = 'delivered' and currency = 'XOF'
                and updated_at >= date_trunc('month', now() at time zone 'Africa/Ouagadougou')
                                  at time zone 'Africa/Ouagadougou')
       or (t -> 'other' -> 'EUR' ->> 'shops_sold')::numeric < 25
       or t -> 'other' ? 'XOF' then
        raise exception 'FAIL: « Revenus de Mara » adds moneys: %', t;
    end if;
    if (select sum(revenue) from platform_analytics_by_currency())
         <> (select revenue from platform_analytics_headline())
       or (select businesses from platform_analytics_by_currency() where currency = 'EUR') < 3
       or (select count(*) from platform_analytics_by_currency() where currency in ('BRL', 'USD', 'XAF')) <> 3 then
        raise exception 'FAIL: the analytics by money %',
            (select jsonb_agg(to_jsonb(x)) from platform_analytics_by_currency() x);
    end if;
    if (select jsonb_object_agg(org_id, currency) from platform_business_currencies()
         where org_id::text like '14000000-0000-0000-0000-0000000000a%')
       <> '{"14000000-0000-0000-0000-0000000000a1": "EUR", "14000000-0000-0000-0000-0000000000a2": "BRL",
            "14000000-0000-0000-0000-0000000000a3": "USD", "14000000-0000-0000-0000-0000000000a4": "XOF",
            "14000000-0000-0000-0000-0000000000a5": "XAF", "14000000-0000-0000-0000-0000000000a6": "EUR",
            "14000000-0000-0000-0000-0000000000a7": "EUR"}'::jsonb then
        raise exception 'FAIL: each business''s money';
    end if;
    raise notice 'PASS: the settlement, « Revenus de Mara » and the analytics each per money; every business''s money said';
end $$;
commit;
-- Nobody else reads them.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '14014014-0000-0000-0000-000000000005';
do $$ begin
    begin
        perform platform_analytics_by_currency();
        raise exception 'FAIL: a customer read the platform''s analytics';
    exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;
    begin
        perform platform_business_currencies();
        raise exception 'FAIL: a customer read every business''s money';
    exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;
    begin
        perform platform_delivery_settlement_by_currency();
        raise exception 'FAIL: a customer read the settlement';
    exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;
    begin
        perform courier_earnings_by_currency();
        raise exception 'FAIL: a customer read a courier''s tally';
    exception when others then if sqlerrm like 'FAIL:%' then raise; end if; end;
    if has_function_privilege('anon', 'courier_earnings_by_currency()', 'execute')
       or has_function_privilege('anon', 'platform_analytics_by_currency(timestamptz)', 'execute')
       or has_function_privilege('anon', 'platform_business_currencies()', 'execute')
       or has_function_privilege('anon', 'platform_delivery_settlement_by_currency(date)', 'execute') then
        raise exception 'FAIL: a total open to anon';
    end if;
    raise notice 'PASS: the platform''s totals the platform''s, a courier''s tally the courier''s, none open to anon';
end $$;
commit;
update profiles set is_platform_admin = false where id = '14014014-0000-0000-0000-000000000003';

\echo ''
\echo '--- TEST 7: run twice, 140 changes nothing ---'
create temp table b140_seen as
    select 'org ' || id as k, to_jsonb(o.default_currency) as v from orgs o
    union all select 'fee', to_jsonb(delivery_fee('14000000-0000-0000-0000-0000000000a1', 48.8800, 2.3700))
    union all select 'note ' || id, to_jsonb(message) from notifications where org_id::text like '14000000%';
\i database/migrations/140_prices_by_area.sql
do $$ begin
    if exists (
        (select 'org ' || id as k, to_jsonb(o.default_currency) as v from orgs o
         union all select 'fee', to_jsonb(delivery_fee('14000000-0000-0000-0000-0000000000a1', 48.8800, 2.3700))
         union all select 'note ' || id, to_jsonb(message) from notifications where org_id::text like '14000000%')
        except select k, v from b140_seen) then
        raise exception 'FAIL: 140 again changed something';
    end if;
    raise notice 'PASS: run twice, the same';
end $$;

revoke usage on schema auth from authenticated;

\echo ''
\echo '=== test_batch140.sql: all claims hold ==='
