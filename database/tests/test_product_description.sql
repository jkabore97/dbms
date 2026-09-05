-- ============================================================
-- test_product_description.sql — a few words under the article reach the street (064).
-- Phone block 36.
--
-- The claims: a writer of the shop may put a description on an article and
-- the street reads it, trimmed, on the same row as the price; blank means
-- nothing — a description of spaces reads null, not ''; the database
-- refuses a description longer than 300 characters before the app can
-- store one nobody would read; the recreated storefront_products() is
-- still open to a stranger with the public key (063 makes a new function
-- born closed, so this is the grant 064 says explicitly); and the row
-- still carries nothing from behind the counter.
-- ============================================================
\set ON_ERROR_STOP on

\set owner_a  '''36363636-0000-0000-0000-000000000001'''
\set clerk_a  '''36363636-0000-0000-0000-000000000002'''
\set stranger '''36363636-0000-0000-0000-000000000003'''
\set shop_a   '''36000000-0000-0000-0000-000000000001'''
\set gateau   '''36aaaaaa-0000-0000-0000-000000000001'''
\set pagne    '''36aaaaaa-0000-0000-0000-000000000002'''

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

-- In this cluster the roles may have been created after every migration
-- ran, with 064's grant guarded away. Run it again now that they exist —
-- it is written to be re-run — so TEST 4 below tests the migration's own
-- grant and not this file's.
\i database/migrations/064_product_description.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner_a,  '+22636000001', '{"full_name": "Esperance"}'),
    (:clerk_a,  '+22636000002', '{"full_name": "Vendeuse"}'),
    (:stranger, '+22636000003', '{"full_name": "Passant"}');

insert into orgs (id, name, slug, profile, default_currency, storefront_enabled) values
    (:shop_a, 'Pâtisserie Esperance', 'vitrine-36', 'retail', 'XOF', true);
select seed_retail_accounts(:shop_a);

insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop_a, :owner_a, 'owner',    'org', :shop_a, 'full'),
    (:shop_a, :clerk_a, 'employee', 'org', :shop_a, 'full');

insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published, created_by) values
    (:gateau, :shop_a, 'Gâteau', 2500, 1200, 4, true, true, :owner_a),
    (:pagne,  :shop_a, 'Pagne',  6000, 4000, 9, true, true, :owner_a);


\echo ''
\echo '--- TEST 1: a writer describes the article and the street reads it, trimmed ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '36363636-0000-0000-0000-000000000002';
update products
   set description = '  Gâteau au chocolat, 8 parts. Commander la veille.  '
 where id = '36aaaaaa-0000-0000-0000-000000000001';
-- The street: no claim at all.
set local "request.jwt.claim.sub" = '';
do $$
declare v_desc text; v_price numeric;
begin
    select description, sale_price into v_desc, v_price
      from storefront_products('vitrine-36') where name = 'Gâteau';
    if v_desc is distinct from 'Gâteau au chocolat, 8 parts. Commander la veille.' then
        raise exception 'FAIL: the street did not read the trimmed description (got %)', v_desc;
    end if;
    if v_price <> 2500 then
        raise exception 'FAIL: the price left the row when the description arrived (%)', v_price;
    end if;
    raise notice 'PASS: the clerk''s description is on the street row, trimmed, beside the price';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: blank means nothing — spaces read null, and so does silence ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '36363636-0000-0000-0000-000000000001';
update products set description = '    '
 where id = '36aaaaaa-0000-0000-0000-000000000001';
set local "request.jwt.claim.sub" = '';
do $$
declare v_gateau text; v_pagne text; v_rows int;
begin
    select description into v_gateau
      from storefront_products('vitrine-36') where name = 'Gâteau';
    select description into v_pagne
      from storefront_products('vitrine-36') where name = 'Pagne';
    if v_gateau is not null then
        raise exception 'FAIL: a description of spaces reached the street as %', quote_literal(v_gateau);
    end if;
    if v_pagne is not null then
        raise exception 'FAIL: an article never described reads % on the street', quote_literal(v_pagne);
    end if;
    select count(*) into v_rows from storefront_products('vitrine-36');
    if v_rows <> 2 then
        raise exception 'FAIL: a missing description hid an article (% rows)', v_rows;
    end if;
    raise notice 'PASS: blank and absent both read null, and both articles stay in the window';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: 300 characters is the wall ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '36363636-0000-0000-0000-000000000001';
do $$
declare v_state text;
begin
    -- Exactly 300 fits.
    update products set description = repeat('a', 300)
     where id = '36aaaaaa-0000-0000-0000-000000000001';
    begin
        update products set description = repeat('a', 301)
         where id = '36aaaaaa-0000-0000-0000-000000000001';
        raise exception 'FAIL: a 301-character description was stored';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        get stacked diagnostics v_state = returned_sqlstate;
        if v_state <> '23514' then
            raise exception 'FAIL: the long description failed with % rather than the check constraint', v_state;
        end if;
    end;
    raise notice 'PASS: 300 characters are kept, 301 are refused by the constraint (23514)';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the recreated street function is still open to a stranger ---'
begin;
set local role anon;
do $$
declare v_rows int; v_sig text;
begin
    select count(*) into v_rows from storefront_products('vitrine-36');
    if v_rows <> 2 then
        raise exception 'FAIL: anon read % rows from the open vitrine', v_rows;
    end if;
    select pg_get_function_result(p.oid) into v_sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'storefront_products';
    if v_sig not ilike '%description%' then
        raise exception 'FAIL: the street row has no description column: %', v_sig;
    end if;
    if v_sig ilike '%cost%' or v_sig ilike '%quantity%' then
        raise exception 'FAIL: the window row carries something from behind the counter: %', v_sig;
    end if;
    raise notice 'PASS: anon reads the window with its description and nothing from behind the counter';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: a stranger cannot write a description ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '36363636-0000-0000-0000-000000000003';
do $$
declare v_rows int;
begin
    update products set description = 'Vandalisme'
     where id = '36aaaaaa-0000-0000-0000-000000000002';
    get diagnostics v_rows = row_count;
    if v_rows <> 0 then
        raise exception 'FAIL: a stranger described another shop''s article';
    end if;
    raise notice 'PASS: the stranger''s update touched no row';
end $$;
rollback;

\echo ''
\echo 'test_product_description.sql: all tests passed'
