-- ============================================================
-- test_storefront_directory.sql — where the shops are, and which are near (053).
-- Phone block 26.
--
-- The claims: only an administrator places a shop on the map, and a position
-- is both coordinates or neither, inside the world; the street sees the open
-- vitrines and no closed one; with no position given the list is by name and
-- carries no distance; with a position given, the placed shops come first,
-- nearest first, with a distance that is right, and the unplaced follow by
-- name; and an administrator can lift the pin again.
-- ============================================================
\set ON_ERROR_STOP on

\set owner_a '''26262626-0000-0000-0000-000000000001'''
\set owner_b '''26262626-0000-0000-0000-000000000002'''
\set owner_c '''26262626-0000-0000-0000-000000000003'''
\set clerk_a '''26262626-0000-0000-0000-000000000004'''
\set shop_a  '''26000000-0000-0000-0000-000000000001'''
\set shop_b  '''26000000-0000-0000-0000-000000000002'''
\set shop_c  '''26000000-0000-0000-0000-000000000003'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner_a, '+22626000001', '{"full_name": "A"}'),
    (:owner_b, '+22626000002', '{"full_name": "B"}'),
    (:owner_c, '+22626000003', '{"full_name": "C"}'),
    (:clerk_a, '+22626000004', '{"full_name": "Vendeuse"}');

-- A and B are open; C is not. A is placed near the Ouaga centre (Naaba Koom),
-- B is open but unplaced, C is placed but closed — the street must not see it.
insert into orgs (id, name, slug, profile, default_currency, address, storefront_enabled, lat, lng) values
    (:shop_a, 'Alimentation Yaar',   'annuaire-a-26', 'retail', 'XOF', 'Place Naaba Koom', true,  12.3714, -1.5197),
    (:shop_b, 'Boutique Bilan',      'annuaire-b-26', 'retail', 'XOF', null,               true,  null,    null),
    (:shop_c, 'Comptoir Fermé',      'annuaire-c-26', 'retail', 'XOF', null,               false, 12.40,   -1.50);
select seed_retail_accounts(:shop_a);
select seed_retail_accounts(:shop_b);
select seed_retail_accounts(:shop_c);

insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop_a, :owner_a, 'owner',    'org', :shop_a, 'full'),
    (:shop_a, :clerk_a, 'employee', 'org', :shop_a, 'full'),
    (:shop_b, :owner_b, 'owner',    'org', :shop_b, 'full'),
    (:shop_c, :owner_c, 'owner',    'org', :shop_c, 'full');


\echo ''
\echo '--- TEST 1: only an administrator places the shop, both coordinates or neither, inside the world ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '26262626-0000-0000-0000-000000000004';
do $$ begin
    begin
        perform set_storefront_location('26000000-0000-0000-0000-000000000001', 12.0, -1.0);
        raise exception 'FAIL: an employee placed the shop on the map';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the employee was refused — %', sqlerrm;
    end;
end $$;
rollback;

begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '26262626-0000-0000-0000-000000000002';
do $$
declare v_lat double precision; v_lng double precision;
begin
    -- Half a position is refused.
    begin
        perform set_storefront_location('26000000-0000-0000-0000-000000000002', 12.35, null);
        raise exception 'FAIL: a latitude with no longitude was accepted';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    -- Off the world is refused by the table itself.
    begin
        perform set_storefront_location('26000000-0000-0000-0000-000000000002', 95.0, -1.5);
        raise exception 'FAIL: latitude 95 was accepted';
    exception when check_violation then
        null;
    end;
    -- A real one lands.
    perform set_storefront_location('26000000-0000-0000-0000-000000000002', 12.3600, -1.5300);
    select lat, lng into v_lat, v_lng from orgs where id = '26000000-0000-0000-0000-000000000002';
    if v_lat is distinct from 12.3600 or v_lng is distinct from -1.5300 then
        raise exception 'FAIL: the position was not stored (% , %)', v_lat, v_lng;
    end if;
    -- And lifted again with both nulls.
    perform set_storefront_location('26000000-0000-0000-0000-000000000002', null, null);
    select lat, lng into v_lat, v_lng from orgs where id = '26000000-0000-0000-0000-000000000002';
    if v_lat is not null or v_lng is not null then
        raise exception 'FAIL: the pin was not lifted';
    end if;
    raise notice 'PASS: the owner places the shop, half a position and an impossible one are refused, and the pin can be lifted';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: with no position, the street gets the open vitrines by name, no distance, no closed one ---'
begin;
set local role authenticated;
do $$
declare v_rows int; v_names text; v_dist_count int; v_sorted boolean;
begin
    -- Other suites leave open vitrines of their own in this database, so
    -- count only this suite's shops; but check the order across everything.
    select count(*), string_agg(name, '|' order by name)
      into v_rows, v_names
      from storefront_directory() where slug like 'annuaire-%-26';
    if v_rows <> 2 then
        raise exception 'FAIL: expected the 2 open vitrines, got % (%)', v_rows, v_names;
    end if;
    if exists (select 1 from storefront_directory() where slug = 'annuaire-c-26') then
        raise exception 'FAIL: the closed vitrine is in the directory';
    end if;
    select count(distance_km) into v_dist_count from storefront_directory();
    if v_dist_count <> 0 then
        raise exception 'FAIL: a distance was returned with no position given';
    end if;
    select bool_and(name >= prev) into v_sorted
      from (select name, lag(name) over () as prev from storefront_directory()) d
     where prev is not null;
    if v_sorted is distinct from true then
        raise exception 'FAIL: without a position the directory is not in name order';
    end if;
    raise notice 'PASS: the street sees A and B, no C, no distance, by name';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: with a position, the placed shops come first, nearest first, with a true distance ---'
begin;
set local role authenticated;
do $$
declare v_first text; v_dist double precision; v_b_dist double precision;
        v_a_pos int; v_b_pos int; v_placed_after_unplaced int;
begin
    -- About 1.3 km east-north-east of shop A's pin: the distance must land in
    -- a tight band around that, A must be first, and every placed shop must
    -- come before every unplaced one (B among them, with no distance).
    select slug, distance_km into v_first, v_dist
      from storefront_directory(12.3800, -1.5100) limit 1;
    if v_first <> 'annuaire-a-26' then
        raise exception 'FAIL: the nearest placed shop is not first (got %)', v_first;
    end if;
    if v_dist is null or v_dist < 1.0 or v_dist > 2.0 then
        raise exception 'FAIL: the distance to A is off (% km)', v_dist;
    end if;
    with ranked as (
        select slug, distance_km, row_number() over () as pos
          from storefront_directory(12.3800, -1.5100))
    select max(case when slug = 'annuaire-a-26' then pos end),
           max(case when slug = 'annuaire-b-26' then pos end),
           max(case when slug = 'annuaire-b-26' then distance_km end),
           count(*) filter (where distance_km is not null
                              and pos > (select min(pos) from ranked where distance_km is null))
      into v_a_pos, v_b_pos, v_b_dist, v_placed_after_unplaced
      from ranked;
    if v_b_pos is null or v_b_pos <= v_a_pos or v_b_dist is not null then
        raise exception 'FAIL: the unplaced shop should follow with no distance (pos %, %)', v_b_pos, v_b_dist;
    end if;
    if v_placed_after_unplaced <> 0 then
        raise exception 'FAIL: % placed shops sort after an unplaced one', v_placed_after_unplaced;
    end if;
    raise notice 'PASS: A first at % km, the unplaced shops after, B with no distance', round(v_dist::numeric, 2);
end $$;
rollback;

\echo ''
\echo '--- TEST 4: nothing behind the counter is on the row ---'
begin;
do $$
declare v_sig text;
begin
    select pg_get_function_result(p.oid) into v_sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'storefront_directory';
    if v_sig ilike '%cost%' or v_sig ilike '%quantity%' or v_sig ilike '%phone%' then
        raise exception 'FAIL: the directory row carries something it should not: %', v_sig;
    end if;
    raise notice 'PASS: the directory row is the window only — %', v_sig;
end $$;
rollback;

\echo ''
\echo '=== test_storefront_directory.sql: all checks passed ==='
