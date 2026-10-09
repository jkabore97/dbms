-- ============================================================
-- test_batch121.sql — Mara Pro by card, charged in dollars (121).
--
-- The claims:
--   * the rate is a platform setting (stripe_xof_per_usd, 600 seeded),
--     on the Réglages board, changed through platform_set_setting: a
--     whole number above zero — zero, a negative, a decimal or a word
--     refused in French — and journaled like any other;
--   * stripe_begin charges the console's FCFA price in dollar cents,
--     rounded up to the cent (15 000 F → $25.00, 2 900 F → $4.84), the
--     FCFA price beside it for the line's name; the app's own amount is
--     never asked;
--   * plan_terms keeps every FCFA price as it was and says the same cents
--     (stripe_usd_month / stripe_usd_year) from the same function;
--   * no rate the server can read, a currency that is neither FCFA nor
--     dollars, or under Stripe's 50 cents: no card, said in French, and
--     plan_terms says null; a price already in dollars is charged as is;
--   * stripe_settle still makes the business Pro (it reads no amount);
--   * the doors: the helper is no one's to call, stripe_begin is a
--     signed-in owner's, never the street's.
-- Kinds: Mara Pro is the same for a shop, a farm and an association —
-- one of each subscribes here.
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
-- Earlier suites hand the app's roles every function and put back older
-- definitions (test_stripe_pro reruns 082, test_batch105 reruns 105):
-- 121 again, so what follows is 121's own.
\i database/migrations/121_stripe_usd.sql

\set mara   '''12112112-0000-0000-0000-000000000001'''
\set sowner '''12112112-0000-0000-0000-000000000002'''
\set fowner '''12112112-0000-0000-0000-000000000003'''
\set aowner '''12112112-0000-0000-0000-000000000004'''

insert into auth.users (id, phone, email, raw_user_meta_data) values
    (:mara,   '+22612100001', null,                  '{"full_name": "Mara Cent-Vingt-Et-Un"}'),
    (:sowner, '+22612100002', 'awa121@example.com',  '{"full_name": "Awa"}'),
    (:fowner, '+22612100003', 'ign121@example.com',  '{"full_name": "Ignace"}'),
    (:aowner, '+22612100004', 'isr121@example.com',  '{"full_name": "Israël"}');
update profiles set is_platform_admin = true where id = :mara;
insert into orgs (id, name, slug, profile, default_currency) values
    ('12100000-0000-0000-0000-000000000001', 'Boutique 121',  'boutique-121',  'retail',      'XOF'),
    ('12100000-0000-0000-0000-000000000002', 'Ferme 121',     'ferme-121',     'farm',        'XOF'),
    ('12100000-0000-0000-0000-000000000003', 'Entraide 121',  'entraide-121',  'association', 'XOF');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    ('12100000-0000-0000-0000-000000000001', :sowner, 'owner', 'org', '12100000-0000-0000-0000-000000000001', 'full'),
    ('12100000-0000-0000-0000-000000000002', :fowner, 'owner', 'org', '12100000-0000-0000-0000-000000000002', 'full'),
    ('12100000-0000-0000-0000-000000000003', :aowner, 'owner', 'org', '12100000-0000-0000-0000-000000000003', 'full');

-- What the suites before this one left, put back at the end.
create temp table b121_kept as
    select key, value from platform_settings
     where key in ('stripe_on', 'pro_price_month', 'pro_price_year', 'pro_currency', 'stripe_xof_per_usd');
grant select on b121_kept to authenticated;

update platform_settings set value = 'true'   where key = 'stripe_on';
update platform_settings set value = '15000'  where key = 'pro_price_month';
update platform_settings set value = '150000' where key = 'pro_price_year';
update platform_settings set value = '"XOF"'  where key = 'pro_currency';
update platform_settings set value = '600'    where key = 'stripe_xof_per_usd';

\echo ''
\echo '--- TEST 1: the rate is seeded, and on the Réglages board ---'
do $$ begin
    if not exists (select 1 from platform_settings where key = 'stripe_xof_per_usd') then
        raise exception 'FAIL: 121 seeded no rate';
    end if;
    perform set_config('request.jwt.claim.sub', '12112112-0000-0000-0000-000000000001', true);
    execute 'set local role authenticated';
    if not platform_settings_board() ? 'stripe_xof_per_usd' then
        raise exception 'FAIL: the rate is not on the Réglages board';
    end if;
    execute 'reset role';
    raise notice 'PASS: stripe_xof_per_usd seeded and on the board';
end $$;

\echo ''
\echo '--- TEST 2: each kind subscribes at the FCFA price, charged in dollar cents ---'
begin;
set local role authenticated;
do $$
declare
    b jsonb;
    o record;
begin
    for o in select * from (values
        ('12112112-0000-0000-0000-000000000002', '12100000-0000-0000-0000-000000000001', 'Boutique 121'),
        ('12112112-0000-0000-0000-000000000003', '12100000-0000-0000-0000-000000000002', 'Ferme 121'),
        ('12112112-0000-0000-0000-000000000004', '12100000-0000-0000-0000-000000000003', 'Entraide 121'))
        as t(owner, org, name) loop
        perform set_config('request.jwt.claim.sub', o.owner, true);
        b := stripe_begin(o.org::uuid, 'month');
        if (b ->> 'amount')::int <> 2500 or b ->> 'currency' <> 'usd'
           or (b ->> 'price')::numeric <> 15000 or b ->> 'price_currency' <> 'XOF'
           or b ->> 'org_name' <> o.name or b ->> 'period' <> 'month' then
            raise exception 'FAIL: % month is not 15 000 F as $25.00: %', o.name, b;
        end if;
        b := stripe_begin(o.org::uuid, 'year');
        if (b ->> 'amount')::int <> 25000 or (b ->> 'price')::numeric <> 150000 then
            raise exception 'FAIL: % year is not 150 000 F as $250.00: %', o.name, b;
        end if;
    end loop;
    -- Rounded up to the cent: 2 900 F at 600 is 483.33… cents.
    execute 'reset role';
    update platform_settings set value = '2900' where key = 'pro_price_month';
    execute 'set local role authenticated';
    if (stripe_begin('12100000-0000-0000-0000-000000000003', 'month') ->> 'amount')::int <> 484 then
        raise exception 'FAIL: 2 900 F is not rounded up to $4.84';
    end if;
    raise notice 'PASS: a shop, a farm and an association: 15 000 F = 2 500 cents, 150 000 F = 25 000, 2 900 F = 484 (up)';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: plan_terms keeps the FCFA prices and says the same cents ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '12112112-0000-0000-0000-000000000002';
do $$
declare t jsonb := plan_terms();
begin
    if (t ->> 'pro_price_month')::int <> 15000 or (t ->> 'pro_price_year')::int <> 150000
       or t ->> 'pro_currency' <> 'XOF' then
        raise exception 'FAIL: the prices the app shows are no longer the FCFA ones: %', t;
    end if;
    if (t ->> 'stripe_usd_month')::int <> 2500 or (t ->> 'stripe_usd_year')::int <> 25000 then
        raise exception 'FAIL: plan_terms does not say what the card charges: %', t;
    end if;
    if (t ->> 'stripe_usd_month')::int
       <> (stripe_begin('12100000-0000-0000-0000-000000000001', 'month') ->> 'amount')::int then
        raise exception 'FAIL: the app''s « ≈ » and Stripe''s amount differ';
    end if;
    raise notice 'PASS: FCFA prices as before; ≈ $25.00 / $250.00, the same as stripe_begin';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the rate in Réglages — a whole number above zero, journaled ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '12112112-0000-0000-0000-000000000001';
do $$
declare a uuid;
begin
    begin perform platform_set_setting('stripe_xof_per_usd', '0');
          raise exception 'FAIL: a rate of zero';
    exception when others then
        if sqlerrm <> 'Un nombre entier plus grand que zéro, s''il vous plaît.' then raise; end if; end;
    begin perform platform_set_setting('stripe_xof_per_usd', '-600');
          raise exception 'FAIL: a negative rate';
    exception when others then if sqlerrm <> 'Un nombre positif, s''il vous plaît.' then raise; end if; end;
    begin perform platform_set_setting('stripe_xof_per_usd', '600.5');
          raise exception 'FAIL: a decimal rate';
    exception when others then if sqlerrm <> 'Un nombre entier, s''il vous plaît.' then raise; end if; end;
    begin perform platform_set_setting('stripe_xof_per_usd', '"six cents"');
          raise exception 'FAIL: a word for the rate';
    exception when others then if sqlerrm <> 'Ce réglage attend un nombre.' then raise; end if; end;
    -- Every other number still takes zero, as 105 said.
    perform platform_set_setting('free_max_staff', '0');

    a := platform_set_setting('stripe_xof_per_usd', '500');
    if a is null or (select value from platform_settings where key = 'stripe_xof_per_usd') <> '500'::jsonb then
        raise exception 'FAIL: the rate was not changed';
    end if;
    execute 'reset role';
    if not exists (select 1 from platform_actions where id = a and kind = 'setting'
                     and before = jsonb_build_object('key', 'stripe_xof_per_usd', 'value', 600)) then
        raise exception 'FAIL: the rate''s change is not journaled with its before';
    end if;
    execute 'set local role authenticated';
    if (stripe_begin('12100000-0000-0000-0000-000000000001', 'month') ->> 'amount')::int <> 3000
       or (plan_terms() ->> 'stripe_usd_month')::int <> 3000 then
        raise exception 'FAIL: the next checkout is not at the new rate (15 000 F / 500 = $30.00)';
    end if;
    raise notice 'PASS: 0, -600, 600.5, a word refused in French; 500 taken, journaled, the next checkout at $30.00';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: no readable rate, another currency, under 50 cents: no card; dollars as is ---'
begin;
do $$
declare t jsonb;
begin
    perform set_config('request.jwt.claim.sub', '12112112-0000-0000-0000-000000000002', true);
    -- 061's older setter checks nothing: a word, or nothing at all.
    update platform_settings set value = '"six cents"' where key = 'stripe_xof_per_usd';
    execute 'set local role authenticated';
    t := plan_terms();
    if t -> 'stripe_usd_month' <> 'null'::jsonb or (t ->> 'pro_price_month')::int <> 15000 then
        raise exception 'FAIL: an unreadable rate still says dollars, or lost the FCFA price: %', t;
    end if;
    begin perform stripe_begin('12100000-0000-0000-0000-000000000001', 'month');
          raise exception 'FAIL: a checkout with no rate';
    exception when others then
        if sqlerrm <> 'Le taux de la carte (FCFA pour 1 $) n''est pas fixé' then raise; end if; end;
    execute 'reset role';
    delete from platform_settings where key = 'stripe_xof_per_usd';
    execute 'set local role authenticated';
    begin perform stripe_begin('12100000-0000-0000-0000-000000000001', 'month');
          raise exception 'FAIL: a checkout with the rate gone';
    exception when others then
        if sqlerrm not like 'Le taux de la carte%' then raise; end if; end;

    -- Under Stripe's minimum.
    execute 'reset role';
    insert into platform_settings (key, value) values ('stripe_xof_per_usd', '1000000000');
    execute 'set local role authenticated';
    begin perform stripe_begin('12100000-0000-0000-0000-000000000001', 'month');
          raise exception 'FAIL: a 1-cent checkout';
    exception when others then
        if sqlerrm not like 'Le prix en dollars est trop petit%' then raise; end if; end;

    -- A currency that is neither FCFA nor dollars.
    execute 'reset role';
    update platform_settings set value = '"EUR"' where key = 'pro_currency';
    execute 'set local role authenticated';
    begin perform stripe_begin('12100000-0000-0000-0000-000000000001', 'month');
          raise exception 'FAIL: euros converted at an FCFA rate';
    exception when others then
        if sqlerrm not like 'Le taux de la carte%' then raise; end if; end;

    -- Prices already in dollars: charged as they are, in cents.
    execute 'reset role';
    update platform_settings set value = '"USD"' where key = 'pro_currency';
    update platform_settings set value = '25' where key = 'pro_price_month';
    execute 'set local role authenticated';
    if (stripe_begin('12100000-0000-0000-0000-000000000001', 'month') ->> 'amount')::int <> 2500 then
        raise exception 'FAIL: $25 is not 2 500 cents';
    end if;
    execute 'reset role';
    raise notice 'PASS: a word or no rate, euros, 1 cent: refused in French, plan_terms null; $25 is 2 500 cents';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: Stripe''s word still makes the business Pro (no amount is read) ---'
begin;
do $$
declare r jsonb;
begin
    r := stripe_settle('12100000-0000-0000-0000-000000000002', 'sub_121', 'cus_121',
                       'active', 'month', '2030-06-10 12:00+00', false);
    if not (r ->> 'active')::boolean or org_plan('12100000-0000-0000-0000-000000000002') <> 'pro'
       or (select plan_until from orgs where id = '12100000-0000-0000-0000-000000000002') <> '2030-06-11' then
        raise exception 'FAIL: a dollar subscription did not make the farm Pro: %', r;
    end if;
    raise notice 'PASS: settled, Pro to the paid end and a day';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: the doors ---'
do $$ begin
    if has_function_privilege('anon', 'stripe_usd_cents(numeric)', 'execute')
       or has_function_privilege('authenticated', 'stripe_usd_cents(numeric)', 'execute')
       or has_function_privilege('public', 'stripe_usd_cents(numeric)', 'execute') then
        raise exception 'FAIL: the helper is callable on its own';
    end if;
    if has_function_privilege('anon', 'stripe_begin(uuid, text)', 'execute') then
        raise exception 'FAIL: the street may start a checkout';
    end if;
    if not has_function_privilege('authenticated', 'stripe_begin(uuid, text)', 'execute')
       or not has_function_privilege('authenticated', 'plan_terms()', 'execute')
       or not has_function_privilege('authenticated', 'platform_set_setting(text, jsonb)', 'execute') then
        raise exception 'FAIL: an owner cannot start or read the terms, or the platform cannot set';
    end if;
    raise notice 'PASS: the helper is no one''s; stripe_begin and plan_terms a signed-in caller''s';
end $$;

-- Leave the settings as the suites before this one left them.
update platform_settings s set value = k.value from b121_kept k where k.key = s.key;
delete from memberships where org_id::text like '12100000-%';
delete from orgs where id::text like '12100000-%';

\echo ''
\echo 'test_batch121: all passed'
