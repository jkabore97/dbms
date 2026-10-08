-- ============================================================
-- test_product_search.sql — one search across every window (059).
-- Phone block 31.
--
-- The claims: the street finds a published article in any open vitrine by
-- typing part of its name; accents and case do not matter; an unpublished
-- article, a closed vitrine and a suspended shop are all invisible; a
-- shopper typing % or _ searches for those characters, not everything;
-- matches that start the name come first, and with a position the nearer
-- shop wins the tie; one letter is not a search; and the row carries
-- nothing behind the counter.
-- ============================================================
\set ON_ERROR_STOP on

\set owner_a  '''31313131-0000-0000-0000-000000000001'''
\set owner_b  '''31313131-0000-0000-0000-000000000002'''
\set shop_a   '''31000000-0000-0000-0000-000000000001'''
\set shop_b   '''31000000-0000-0000-0000-000000000002'''
\set shop_c   '''31000000-0000-0000-0000-000000000003'''
\set shop_d   '''31000000-0000-0000-0000-000000000004'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner_a, '+22631000001', '{"full_name": "Awa"}'),
    (:owner_b, '+22631000002', '{"full_name": "Binta"}');

-- A and B are open and placed — A at Rood Woko, B ~9 km north-east. C is
-- open but suspended by the platform; D never opened its vitrine.
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, lat, lng, suspended_at) values
    (:shop_a, 'Boutique Awa',   'recherche-a-31', 'retail', 'XOF', true,  12.3714, -1.5197, null),
    (:shop_b, 'Boutique Binta', 'recherche-b-31', 'retail', 'XOF', true,  12.4400, -1.4700, null),
    (:shop_c, 'Boutique Close', 'recherche-c-31', 'retail', 'XOF', true,  12.3800, -1.5100, now()),
    (:shop_d, 'Boutique Nulle', 'recherche-d-31', 'retail', 'XOF', false, null,    null,    null);
select seed_retail_accounts(:shop_a);
select seed_retail_accounts(:shop_b);
select seed_retail_accounts(:shop_c);
select seed_retail_accounts(:shop_d);

insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop_a, :owner_a, 'owner', 'org', :shop_a, 'full'),
    (:shop_b, :owner_b, 'owner', 'org', :shop_b, 'full');

insert into products (org_id, name, sale_price, cost_price, quantity, is_active, is_published, created_by) values
    -- A's window: two savons the street should find, a café for the accent
    -- test, a riz that is out of stock but still shown.
    (:shop_a, 'Savon Citec 31',    450,  300, 9, true, true,  :owner_a),
    (:shop_a, 'Café Touba 31',    1000,  700, 5, true, true,  :owner_a),
    (:shop_a, 'Riz local 25kg 31', 17500, 15000, 0, true, true, :owner_a),
    -- A keeps one savon off the vitrine.
    (:shop_a, 'Savon caché 31',    450,  300, 9, true, false, :owner_a),
    -- B's window: a prefix match and a buried match.
    (:shop_b, 'Savon noir 31',     500,  350, 3, true, true,  :owner_b),
    (:shop_b, 'Grand savon 31',    900,  600, 2, true, true,  :owner_b),
    -- Invisible however they are named: C is suspended, D never opened.
    (:shop_c, 'Savon suspendu 31', 450,  300, 9, true, true,  :owner_a),
    (:shop_d, 'Savon fermé 31',    450,  300, 9, true, true,  :owner_b);

\echo ''
\echo '--- TEST 1: the street finds published articles in open vitrines, nothing else ---'
begin;
set local role authenticated;
do $$
declare v_names text; v_rows int;
begin
    select string_agg(s.name, '|' order by s.name), count(*)
      into v_names, v_rows
      from search_products('savon') s
     where s.shop_slug like 'recherche-%-31';
    if v_rows <> 3 or v_names <> 'Grand savon 31|Savon Citec 31|Savon noir 31' then
        raise exception 'FAIL: expected the three visible savons, got % (%)', v_rows, v_names;
    end if;
    raise notice 'PASS: three savons found; the unpublished, the closed and the suspended are invisible';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: accents and case do not matter ---'
begin;
set local role authenticated;
do $$
declare v_rows int;
begin
    select count(*) into v_rows
      from search_products('cafe') s
     where s.shop_slug like 'recherche-%-31';
    if v_rows <> 1 then
        raise exception 'FAIL: "cafe" should find Café Touba, got % rows', v_rows;
    end if;
    select count(*) into v_rows
      from search_products('CAFÉ') s
     where s.shop_slug like 'recherche-%-31';
    if v_rows <> 1 then
        raise exception 'FAIL: "CAFÉ" should find Café Touba, got % rows', v_rows;
    end if;
    raise notice 'PASS: cafe and CAFÉ both find Café Touba';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: % and _ are characters, not wildcards; one letter is not a search ---'
begin;
set local role authenticated;
do $$
declare v_rows int;
begin
    select count(*) into v_rows from search_products('a%')
     where shop_slug like 'recherche-%-31';
    if v_rows <> 0 then
        raise exception 'FAIL: "a%%" matched % rows as a wildcard', v_rows;
    end if;
    select count(*) into v_rows from search_products('s_')
     where shop_slug like 'recherche-%-31';
    if v_rows <> 0 then
        raise exception 'FAIL: "s_" matched % rows as a wildcard', v_rows;
    end if;
    select count(*) into v_rows from search_products('s');
    if v_rows <> 0 then
        raise exception 'FAIL: a single letter returned % rows', v_rows;
    end if;
    select count(*) into v_rows from search_products('   ');
    if v_rows <> 0 then
        raise exception 'FAIL: blank returned % rows', v_rows;
    end if;
    raise notice 'PASS: wildcards are escaped and short queries return nothing';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: names first, then nearest; out of stock still shown ---'
begin;
set local role authenticated;
do $$
declare v_order text;
begin
    -- From Rood Woko (shop A's own pin): prefix matches (Savon …) before
    -- the buried one (Grand savon), and among prefixes A (0 km) before
    -- B (~9 km). Other suites' articles may interleave; the relative
    -- order of this block's three is what the ranking promises.
    select string_agg(s.name, '|' order by s.ord) into v_order
      from (select row_number() over () as ord, sp.name, sp.shop_slug
              from search_products('savon', 12.3714, -1.5197) sp) s
     where s.shop_slug like 'recherche-%-31';
    if v_order <> 'Savon Citec 31|Savon noir 31|Grand savon 31' then
        raise exception 'FAIL: the savons came back in the wrong order: %', v_order;
    end if;
    raise notice 'PASS: order is Savon Citec (here), Savon noir (9 km), Grand savon (buried match)';
end $$;
do $$
declare v_stock boolean; v_km double precision;
begin
    select s.in_stock, s.distance_km into strict v_stock, v_km
      from search_products('riz local', 12.3714, -1.5197) s
     where s.shop_slug = 'recherche-a-31';
    if v_stock then
        raise exception 'FAIL: Riz local is out of stock but says otherwise';
    end if;
    if v_km is null or v_km > 0.01 then
        raise exception 'FAIL: distance from the shop to itself should be ~0, got %', v_km;
    end if;
    raise notice 'PASS: an empty shelf is still in the answer, marked out of stock, with its distance';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: nothing behind the counter is on the row ---'
begin;
do $$
declare v_sig text;
begin
    select pg_get_function_result(p.oid) into v_sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'search_products';
    if v_sig ilike '%cost%' or v_sig ilike '%quantity%' or v_sig ilike '%phone%' then
        raise exception 'FAIL: the search row carries something it should not: %', v_sig;
    end if;
    raise notice 'PASS: the search row is the window only — %', v_sig;
end $$;
rollback;

\echo ''
\echo '=== test_product_search.sql: all checks passed ==='
