-- ============================================================
-- test_cauris_unlocks.sql — cauris buy Pro tools; Basic opens step by
-- step (085). Phone block 55.
--
-- The claims: a tool unlocks for 30 days for its price, in one ledger
-- line, and every guard sees it (feature_access, pro_locked); a second
-- purchase adds 30 days; not enough cauris, an employee, an association,
-- a tool that waits for days on Mara — all refused; Mara Pro complet makes
-- the business Pro (org_plan), so delivery quotes and the free caps lift;
-- a delivery-only unlock opens the delivery door alone; an unlock that
-- ran out closes; a new business is on the street at 60 % and not before,
-- a business already here stays on it; feature_states() says all of it;
-- and only the platform sets the prices.
-- ============================================================
\set ON_ERROR_STOP on
-- 092 hides a vitrine below 8 items (test_vitrine_minimum.sql); this
-- suite is about something else, so it keeps the old rule (no minimum).
update platform_settings set value = '0' where key = 'vitrine_min_items';

\set owner    '''55555555-0000-0000-0000-000000000001'''
\set clerk    '''55555555-0000-0000-0000-000000000002'''
\set buyer    '''55555555-0000-0000-0000-000000000003'''
\set plat     '''55555555-0000-0000-0000-000000000004'''
\set shop     '''55000000-0000-0000-0000-000000000001'''
\set fresh    '''55000000-0000-0000-0000-000000000002'''
\set assoc    '''55000000-0000-0000-0000-000000000003'''

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
-- Earlier files re-run 081, whose doors ask the plan alone: run 085 again
-- so this file tests 085's own.
\i database/migrations/085_cauris_unlocks.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22655000001', '{"full_name": "Awa"}'),
    (:clerk, '+22655000002', '{"full_name": "Vendeur"}'),
    (:buyer, '+22655000003', '{"full_name": "Cliente"}'),
    (:plat,  '+22655000004', '{"full_name": "Plateforme"}');
update profiles set is_platform_admin = true where id = :plat;
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, lat, lng,
                  progress_since, created_at) values
    (:shop,  'Boutique Ancienne', 'ancienne-55', 'retail', 'XOF', true, 12.37, -1.52,
        null, now() - interval '200 days'),
    (:fresh, 'Boutique Neuve',    'neuve-55',    'retail', 'XOF', true, 12.37, -1.52,
        now(), now()),
    (:assoc, 'Association',       'assoc-55',    'association', 'XOF', false, null, null,
        null, now() - interval '200 days');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :owner, 'owner',    'org', :shop,  'full'),
    (:shop,  :clerk, 'employee', 'org', :shop,  'full'),
    (:fresh, :owner, 'owner',    'org', :fresh, 'full'),
    (:assoc, :owner, 'owner',    'org', :assoc, 'full');
insert into products (org_id, name, sale_price, quantity, is_active, is_published) values
    (:shop,  'Savon', 300, 5, true, true),
    (:fresh, 'Pain',  200, 5, true, true);

-- A wallet to spend from, as the platform would grant it.
insert into cauris_ledger (org_id, delta, reason, ref) values
    (:shop,  1000, 'prize', 't55-a'),
    (:fresh,  600, 'prize', 't55-b'),
    (:assoc, 1000, 'prize', 't55-c');

\echo ''
\echo '--- TEST 1: analytics for 400 cauris, 30 days; every guard sees it ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '55555555-0000-0000-0000-000000000001';
do $$
declare r jsonb;
begin
    if feature_access('55000000-0000-0000-0000-000000000001', 'analytics') <> 'view'
       or not pro_locked('55000000-0000-0000-0000-000000000001', 'analytics') then
        raise exception 'FAIL: analytics is open before it is paid for';
    end if;
    r := spend_cauris('55000000-0000-0000-0000-000000000001', 'analytics');
    if (r ->> 'balance')::int <> 600
       or (r ->> 'until')::timestamptz < now() + interval '29 days' then
        raise exception 'FAIL: 400 cauris did not buy 30 days: %', r;
    end if;
    if feature_access('55000000-0000-0000-0000-000000000001', 'analytics') <> 'edit'
       or pro_locked('55000000-0000-0000-0000-000000000001', 'analytics') then
        raise exception 'FAIL: the guards do not see the unlock';
    end if;
    if feature_access('55000000-0000-0000-0000-000000000001', 'payroll') <> 'view' then
        raise exception 'FAIL: one unlock opened another tool';
    end if;
    -- Again: 30 more days on top.
    r := spend_cauris('55000000-0000-0000-0000-000000000001', 'analytics');
    if (r ->> 'until')::timestamptz < now() + interval '59 days' then
        raise exception 'FAIL: a second purchase did not add 30 days';
    end if;
    begin
        perform spend_cauris('55000000-0000-0000-0000-000000000001', 'analytics');
        raise exception 'FAIL: spent cauris it does not have';
    exception when others then
        if sqlerrm not like 'Il vous manque%' then raise; end if;
    end;
    raise notice 'PASS: unlocked, seen by every guard, extended, then refused for want of cauris';
end $$;
commit;

\echo ''
\echo '--- TEST 2: who may spend, and what waits for days on Mara ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '55555555-0000-0000-0000-000000000002';
do $$ begin
    begin
        perform spend_cauris('55000000-0000-0000-0000-000000000001', 'payroll');
        raise exception 'FAIL: an employee spent the shop''s cauris';
    exception when others then
        if sqlerrm not like 'Seul un administrateur%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '55555555-0000-0000-0000-000000000001';
do $$ begin
    begin
        perform spend_cauris('55000000-0000-0000-0000-000000000002', 'accounting');
        raise exception 'FAIL: accounting opened on a business a day old';
    exception when others then
        if sqlerrm not like '%après 60 jours%' then raise; end if;
    end;
    begin
        perform spend_cauris('55000000-0000-0000-0000-000000000003', 'analytics');
        raise exception 'FAIL: an association spent cauris';
    exception when others then
        if sqlerrm not like 'Les cauris sont pour%' then raise; end if;
    end;
    raise notice 'PASS: an employee, a day-old accounting, an association: refused';
end $$;
commit;

\echo ''
\echo '--- TEST 3: delivery alone, then Mara Pro complet ---'
insert into cauris_ledger (org_id, delta, reason, ref) values
    ('55000000-0000-0000-0000-000000000001', 2200, 'prize', 't55-d');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '55555555-0000-0000-0000-000000000001';
do $$ begin
    if org_delivers('55000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: a Free shop delivers before any unlock';
    end if;
    perform spend_cauris('55000000-0000-0000-0000-000000000001', 'delivery');
    if not org_delivers('55000000-0000-0000-0000-000000000001')
       or delivery_fee('55000000-0000-0000-0000-000000000001', 12.38, -1.52) is null then
        raise exception 'FAIL: the delivery unlock did not open delivery';
    end if;
    if org_plan('55000000-0000-0000-0000-000000000001') <> 'free'
       or org_has('55000000-0000-0000-0000-000000000001', 'online_payment') then
        raise exception 'FAIL: the delivery unlock opened more than delivery';
    end if;
    perform spend_cauris('55000000-0000-0000-0000-000000000001', 'pro_all');
    if org_plan('55000000-0000-0000-0000-000000000001') <> 'pro'
       or feature_access('55000000-0000-0000-0000-000000000001', 'payroll') <> 'edit' then
        raise exception 'FAIL: Mara Pro complet did not make the shop Pro';
    end if;
    raise notice 'PASS: delivery alone, then everything for 30 days';
end $$;
commit;
-- The order door, as the street knocks on it.
select id as savon from products
 where name = 'Savon' and org_id = '55000000-0000-0000-0000-000000000001' \gset
select set_config('t55.savon', :'savon', false);
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '55555555-0000-0000-0000-000000000003';
do $$ begin
    perform place_order('ancienne-55',
        jsonb_build_array(jsonb_build_object(
            'product_id', current_setting('t55.savon'),
            'quantity', 2)),
        'delivery', null, 'Ouaga 2000', '+22670550003', 'cash', 12.38, -1.52);
    raise notice 'PASS: the delivery order went through the door';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: an unlock that ran out closes ---'
update cauris_unlocks set until = now() - interval '1 minute'
 where org_id = '55000000-0000-0000-0000-000000000001';
do $$ begin
    if org_plan('55000000-0000-0000-0000-000000000001') <> 'free'
       or org_has('55000000-0000-0000-0000-000000000001', 'delivery')
       or org_has('55000000-0000-0000-0000-000000000001', 'analytics') then
        raise exception 'FAIL: an unlock outlived its 30 days';
    end if;
    raise notice 'PASS: closed when the time is up';
end $$;

\echo ''
\echo '--- TEST 5: a new business reaches the street at 60 %, an old one stays ---'
do $$ begin
    if not exists (select 1 from storefront_directory() where slug = 'ancienne-55') then
        raise exception 'FAIL: a business already here left the street';
    end if;
    if exists (select 1 from storefront_directory() where slug = 'neuve-55') then
        raise exception 'FAIL: a new vitrine at % %% is on the street', vitrine_score('55000000-0000-0000-0000-000000000002');
    end if;
end $$;
update orgs set storefront_blurb = 'Le meilleur pain', phone = '+22670550002',
                address = 'Ouaga 2000'
 where id = '55000000-0000-0000-0000-000000000002';
do $$ begin
    if vitrine_score('55000000-0000-0000-0000-000000000002') < 60
       or not exists (select 1 from storefront_directory() where slug = 'neuve-55') then
        raise exception 'FAIL: a new vitrine at % %% is not on the street',
            vitrine_score('55000000-0000-0000-0000-000000000002');
    end if;
    raise notice 'PASS: on the street at % %%', vitrine_score('55000000-0000-0000-0000-000000000002');
end $$;

\echo ''
\echo '--- TEST 6: feature_states says it all; the prices are the platform''s ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '55555555-0000-0000-0000-000000000001';
do $$
declare s jsonb := feature_states('55000000-0000-0000-0000-000000000002');
        t jsonb;
begin
    select x into t from jsonb_array_elements(s -> 'tools') x where x ->> 'feature' = 'accounting';
    if (t ->> 'cost')::int <> 500 or (t ->> 'waits_days')::int < 59
       or not (s -> 'progress' ->> 'gated')::boolean
       or not (s -> 'progress' ->> 'in_trial')::boolean
       or (s ->> 'balance')::int <> 600 then
        raise exception 'FAIL: feature_states is not the whole story: %', s;
    end if;
    begin
        perform set_cauris_cost('analytics', 1);
        raise exception 'FAIL: a shop set a price';
    exception when others then
        if sqlerrm not like 'Only the platform%' then raise; end if;
    end;
    raise notice 'PASS: prices, waits, the path and the trial, read in one call';
end $$;
set local "request.jwt.claim.sub" = '55555555-0000-0000-0000-000000000004';
select set_cauris_cost('analytics', 450);
commit;
do $$ begin
    if (select cost from cauris_costs where feature = 'analytics') <> 450 then
        raise exception 'FAIL: the platform could not set a price';
    end if;
    if has_function_privilege('anon', 'spend_cauris(uuid, text)', 'execute')
       or has_function_privilege('anon', 'feature_states(uuid)', 'execute') then
        raise exception 'FAIL: the street can spend or read wallets';
    end if;
end $$;
update cauris_costs set cost = 400 where feature = 'analytics';

\echo ''
\echo 'test_cauris_unlocks: all passed'
