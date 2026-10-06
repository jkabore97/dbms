-- ============================================================
-- test_farm_vitrine.sql — a farm has a vitrine (083). Phone block 53.
--
-- The claims: a farm's articles reach the street like a shop's, with the
-- unit after the price; a batch still to come is on the vitrine as a
-- pre-order, orderable with nothing in stock yet, and once its day has
-- come the stock decides again; no unit reads null; the database refuses
-- a blank unit and one of more than 20 characters; a customer can order from the
-- farm for pickup; and the recreated storefront_products() is still open to
-- a stranger with the public key.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''53535353-0000-0000-0000-000000000001'''
\set customer '''53535353-0000-0000-0000-000000000002'''
\set farm     '''53000000-0000-0000-0000-000000000001'''
\set oeufs    '''53aaaaaa-0000-0000-0000-000000000001'''
\set poulets  '''53aaaaaa-0000-0000-0000-000000000002'''
\set mais     '''53aaaaaa-0000-0000-0000-000000000003'''

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

-- Earlier files re-run 064, which recreates storefront_products() without
-- 083's columns: run 083 again so this file tests 083's own function and
-- grant.
\i database/migrations/083_farm_vitrine.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22653000001', '{"full_name": "Fermier"}'),
    (:customer, '+22653000002', '{"full_name": "Cliente"}');

insert into orgs (id, name, slug, profile, default_currency, storefront_enabled) values
    (:farm, 'Ferme du Kadiogo', 'ferme-53', 'farm', 'XOF', true);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:farm, :owner, 'owner', 'org', :farm, 'full');

insert into products (id, org_id, name, sale_price, quantity, unit, available_from,
                      is_active, is_published, created_by) values
    (:oeufs,   :farm, 'Œufs frais',       2500, 12, 'plateau', null, true, true, :owner),
    (:poulets, :farm, 'Poulets de chair', 3500,  0, 'tête',
        (now() at time zone 'Africa/Ouagadougou')::date + 10, true, true, :owner),
    (:mais,    :farm, 'Maïs',              300,  0, null,
        (now() at time zone 'Africa/Ouagadougou')::date - 1, true, true, :owner);

\echo ''
\echo '--- TEST 1: the street reads a farm''s articles, with their unit ---'
begin;
set local role anon;
do $$
declare r record;
begin
    select * into r from storefront_products('ferme-53')
     where id = '53aaaaaa-0000-0000-0000-000000000001';
    if r.unit is distinct from 'plateau' or r.sale_price <> 2500 or not r.in_stock
       or r.available_from is not null then
        raise exception 'FAIL: the eggs do not read as 2 500 F the tray, there now: %', r;
    end if;
    raise notice 'PASS: % F / %', r.sale_price, r.unit;
end $$;
rollback;

\echo ''
\echo '--- TEST 2: a batch to come is a pre-order; once its day passed, the stock decides ---'
begin;
set local role anon;
do $$
declare p record; m record;
begin
    select * into p from storefront_products('ferme-53')
     where id = '53aaaaaa-0000-0000-0000-000000000002';
    if not p.in_stock or p.available_from is null
       or p.available_from <= (now() at time zone 'Africa/Ouagadougou')::date then
        raise exception 'FAIL: the broilers are not a pre-order: %', p;
    end if;
    select * into m from storefront_products('ferme-53')
     where id = '53aaaaaa-0000-0000-0000-000000000003';
    if m.in_stock or m.available_from is not null then
        raise exception 'FAIL: a date that has passed still reads as a pre-order: %', m;
    end if;
    if m.unit is not null then
        raise exception 'FAIL: no unit does not read null';
    end if;
    raise notice 'PASS: broilers from %, maize back to its stock', p.available_from;
end $$;
rollback;

\echo ''
\echo '--- TEST 3: a unit is a few words, not a paragraph ---'
do $$ begin
    begin
        update products set unit = repeat('x', 21)
         where id = '53aaaaaa-0000-0000-0000-000000000001';
        raise exception 'FAIL: a 21-character unit was taken';
    exception when check_violation then null;
    end;
    begin
        update products set unit = '   '
         where id = '53aaaaaa-0000-0000-0000-000000000001';
        raise exception 'FAIL: a blank unit was taken (the app sends null)';
    exception when check_violation then null;
    end;
    raise notice 'PASS: refused';
end $$;

\echo ''
\echo '--- TEST 4: a customer orders from the farm, a pre-order included, for pickup ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '53535353-0000-0000-0000-000000000002';
do $$
declare v_order uuid;
begin
    v_order := place_order('ferme-53',
        '[{"product_id":"53aaaaaa-0000-0000-0000-000000000001","quantity":2},
          {"product_id":"53aaaaaa-0000-0000-0000-000000000002","quantity":3}]'::jsonb);
    if (select total from orders where id = v_order) <> 2 * 2500 + 3 * 3500 then
        raise exception 'FAIL: the farm''s order total is wrong';
    end if;
    raise notice 'PASS: ordered, % F', (select total from orders where id = v_order);
end $$;
rollback;

do $$ begin
    if not has_function_privilege('anon', 'storefront_products(text)', 'execute') then
        raise exception 'FAIL: the street cannot read a vitrine';
    end if;
end $$;

\echo ''
\echo 'test_farm_vitrine: all passed'
