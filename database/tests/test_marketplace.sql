-- ============================================================
-- test_marketplace.sql — the welcome page: the pin in the window, à la une (054).
-- Phone block 27.
--
-- The claims: the window now says where the shop is; only the platform can
-- put an article à la une, and neither a shop owner nor the street can; the
-- street sees the featured articles of open vitrines only — never an
-- unpublished one, never one in a closed vitrine, never one whose spot has
-- ended; the row it gets names the shop and carries no cost, count or
-- phone; and only the platform sees the list it chooses from.
-- ============================================================
\set ON_ERROR_STOP on

\set owner_a  '''27272727-0000-0000-0000-000000000001'''
\set owner_b  '''27272727-0000-0000-0000-000000000002'''
\set plat     '''27272727-0000-0000-0000-000000000003'''
\set shopper  '''27272727-0000-0000-0000-000000000004'''
\set shop_a   '''27000000-0000-0000-0000-000000000001'''
\set shop_b   '''27000000-0000-0000-0000-000000000002'''
\set p_riz    '''27aaaaaa-0000-0000-0000-000000000001'''
\set p_savon  '''27aaaaaa-0000-0000-0000-000000000002'''
\set p_lait   '''27aaaaaa-0000-0000-0000-000000000003'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner_a, '+22627000001', '{"full_name": "Esperance"}'),
    (:owner_b, '+22627000002', '{"full_name": "Voisine"}'),
    (:plat,    '+22627000003', '{"full_name": "Plateforme"}'),
    (:shopper, '+22627000004', '{"full_name": "Client"}');
update profiles set is_platform_admin = true where id = :plat;

-- A is open and placed; B is closed. Riz and Savon are A's — Riz published,
-- Savon not. Lait is B's, published, but B's vitrine is shut.
insert into orgs (id, name, slug, profile, default_currency, address, storefront_enabled, lat, lng) values
    (:shop_a, 'Boutique Esperance', 'marche-a-27', 'retail', 'XOF', 'Rood Woko', true,  12.3714, -1.5197),
    (:shop_b, 'Boutique Voisine',   'marche-b-27', 'retail', 'XOF', null,        false, null,    null);
select seed_retail_accounts(:shop_a);
select seed_retail_accounts(:shop_b);

insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop_a, :owner_a, 'owner', 'org', :shop_a, 'full'),
    (:shop_b, :owner_b, 'owner', 'org', :shop_b, 'full');

insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published, created_by) values
    (:p_riz,   :shop_a, 'Riz parfumé 25kg', 17500, 15000, 4, true, true,  :owner_a),
    (:p_savon, :shop_a, 'Savon',              450,   300, 9, true, false, :owner_a),
    (:p_lait,  :shop_b, 'Lait Nido',         3200,  2800, 2, true, true,  :owner_b);

\echo ''
\echo '--- TEST 1: only the platform puts an article à la une ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :owner_a;
do $$
begin
    begin
        perform set_product_featured('27aaaaaa-0000-0000-0000-000000000001', now() + interval '30 days');
        raise exception 'FAIL: the shop owner featured their own article';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the owner was refused — %', sqlerrm;
    end;
end $$;
rollback;

begin;
set local role authenticated;
do $$
begin
    begin
        perform set_product_featured('27aaaaaa-0000-0000-0000-000000000001', now() + interval '30 days');
        raise exception 'FAIL: the street featured an article';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the street was refused — %', sqlerrm;
    end;
end $$;
rollback;

-- The platform may, and this one stays: the street's view below depends on it.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :plat;
select set_product_featured(:p_riz,   now() + interval '30 days');
select set_product_featured(:p_savon, now() + interval '30 days');
select set_product_featured(:p_lait,  now() + interval '30 days');
do $$
begin
    begin
        perform set_product_featured('27aaaaaa-0000-0000-0000-000000000099', now());
        raise exception 'FAIL: a missing article was accepted';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the platform featured three articles; a missing one was refused';
    end;
end $$;
commit;

\echo ''
\echo '--- TEST 2: the street sees the featured articles of open vitrines, and nothing else ---'
begin;
set local role authenticated;
do $$
declare v_names text; v_shop text; v_slug text; v_rows int;
begin
    select string_agg(f.name, '|' order by f.name), count(*)
      into v_names, v_rows
      from storefront_featured() f
     where f.shop_slug like 'marche-%-27';
    if v_rows <> 1 or v_names <> 'Riz parfumé 25kg' then
        raise exception 'FAIL: expected only Riz à la une, got % (%)', v_rows, v_names;
    end if;
    select f.shop_name, f.shop_slug into v_shop, v_slug
      from storefront_featured() f where f.id = '27aaaaaa-0000-0000-0000-000000000001';
    if v_shop <> 'Boutique Esperance' or v_slug <> 'marche-a-27' then
        raise exception 'FAIL: the featured row does not name its shop (% / %)', v_shop, v_slug;
    end if;
    raise notice 'PASS: Riz à la une with its shop; Savon (unpublished) and Lait (closed vitrine) are not';
end $$;
rollback;

-- A spot that has ended ends by itself.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :plat;
select set_product_featured(:p_riz, now() - interval '1 hour');
set local "request.jwt.claim.sub" = '';
do $$
declare v_rows int;
begin
    select count(*) into v_rows from storefront_featured() f where f.shop_slug like 'marche-%-27';
    if v_rows <> 0 then
        raise exception 'FAIL: an ended spot is still shown (% rows)', v_rows;
    end if;
    raise notice 'PASS: an ended spot is gone from the street';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: the window says where the shop is ---'
begin;
set local role authenticated;
do $$
declare v_lat double precision; v_lng double precision; v_name text;
begin
    select s.name, s.lat, s.lng into v_name, v_lat, v_lng from storefront('marche-a-27') s;
    if v_name is null or v_lat is null or v_lng is null
       or abs(v_lat - 12.3714) > 1e-6 or abs(v_lng + 1.5197) > 1e-6 then
        raise exception 'FAIL: the window has no pin (% % %)', v_name, v_lat, v_lng;
    end if;
    if exists (select 1 from storefront('marche-b-27')) then
        raise exception 'FAIL: a closed vitrine still answers';
    end if;
    raise notice 'PASS: the window carries the pin; a closed one stays shut';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: only the platform sees what it can choose from ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :owner_a;
do $$
begin
    begin
        perform platform_featured_candidates();
        raise exception 'FAIL: a shop owner read the candidates';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the owner was refused — %', sqlerrm;
    end;
end $$;
set local "request.jwt.claim.sub" = :plat;
do $$
declare v_names text; v_rows int;
begin
    select string_agg(c.name, '|' order by c.name), count(*)
      into v_names, v_rows
      from platform_featured_candidates() c
     where c.shop_slug like 'marche-%-27';
    -- Riz (published, open vitrine) is a candidate; Savon is not published
    -- and Lait's vitrine is shut, so neither is offered.
    if v_rows <> 1 or v_names <> 'Riz parfumé 25kg' then
        raise exception 'FAIL: candidates should be Riz only, got % (%)', v_rows, v_names;
    end if;
    raise notice 'PASS: the platform chooses among the articles actually in a window';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: nothing behind the counter is on the featured row ---'
begin;
do $$
declare v_sig text;
begin
    select pg_get_function_result(p.oid) into v_sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'storefront_featured';
    if v_sig ilike '%cost%' or v_sig ilike '%quantity%' or v_sig ilike '%phone%' then
        raise exception 'FAIL: the featured row carries something it should not: %', v_sig;
    end if;
    raise notice 'PASS: the featured row is the window only — %', v_sig;
end $$;
rollback;

\echo ''
\echo '=== test_marketplace.sql: all checks passed ==='
