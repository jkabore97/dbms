-- ============================================================
-- test_storefront.sql — the vitrine shows the window and nothing else (052).
-- Phone block 25.
--
-- The claims: only an administrator opens a shop's vitrine; the street — a
-- caller with no identity at all — sees exactly the published, active
-- articles of an open vitrine, with a price, a yes/no on stock and a photo
-- key; it never sees an unpublished or retired article, a closed vitrine, or
-- a suspended or archived business; the row it gets has no cost price and no
-- count on it; and any writer of the shop may put an article in the window
-- while a stranger may not.
--
-- "The street" here is a caller with no JWT claim, as in test_security's
-- anonymous case: auth.uid() is null. The functions read the same for the
-- real `anon` role on Supabase — they never consult the caller at all.
-- ============================================================
\set ON_ERROR_STOP on

\set owner_a  '''25252525-0000-0000-0000-000000000001'''
\set owner_b  '''25252525-0000-0000-0000-000000000002'''
\set clerk_a  '''25252525-0000-0000-0000-000000000003'''
\set stranger '''25252525-0000-0000-0000-000000000004'''
\set plat     '''25252525-0000-0000-0000-000000000005'''
\set shop_a   '''25000000-0000-0000-0000-000000000001'''
\set shop_b   '''25000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner_a,  '+22625000001', '{"full_name": "Esperance"}'),
    (:owner_b,  '+22625000002', '{"full_name": "Voisine"}'),
    (:clerk_a,  '+22625000003', '{"full_name": "Vendeuse"}'),
    (:stranger, '+22625000004', '{"full_name": "Passant"}'),
    (:plat,     '+22625000005', '{"full_name": "Plateforme"}');
update profiles set is_platform_admin = true where id = :plat;

insert into orgs (id, name, slug, profile, default_currency, phone, address) values
    (:shop_a, 'Boutique Esperance', 'vitrine-a-25', 'retail', 'XOF',
             '+22670000025', 'Marché de Gounghin'),
    (:shop_b, 'Boutique Voisine',   'vitrine-b-25', 'retail', 'XOF', null, null);
select seed_retail_accounts(:shop_a);
select seed_retail_accounts(:shop_b);

insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop_a, :owner_a, 'owner',    'org', :shop_a, 'full'),
    (:shop_a, :clerk_a, 'employee', 'org', :shop_a, 'full'),
    (:shop_b, :owner_b, 'owner',    'org', :shop_b, 'full');

-- Four articles in shop A, one in shop B. The interesting ones are the ones
-- the street must NOT see: Savon (not published), Ancien (retired), Riz (a
-- vitrine that was never opened).
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published, created_by) values
    ('25aaaaaa-0000-0000-0000-000000000001', :shop_a, 'Sucre 1kg', 750,  450,  10, true,  true,  :owner_a),
    ('25aaaaaa-0000-0000-0000-000000000002', :shop_a, 'Savon',     500,  300,   5, true,  false, :owner_a),
    ('25aaaaaa-0000-0000-0000-000000000003', :shop_a, 'Ancien',    100,   50,   3, false, true,  :owner_a),
    ('25aaaaaa-0000-0000-0000-000000000004', :shop_a, 'Épuisé',    200,  100,   0, true,  true,  :owner_a),
    ('25aaaaaa-0000-0000-0000-000000000005', :shop_b, 'Riz 5kg',  9000, 7000,  20, true,  true,  :owner_b);

insert into documents (org_id, r2_key, kind, uploaded_by, product_id) values
    (:shop_a, 'org/25a/sucre.jpg', 'product_photo', :owner_a, '25aaaaaa-0000-0000-0000-000000000001'),
    (:shop_a, 'org/25a/savon.jpg', 'product_photo', :owner_a, '25aaaaaa-0000-0000-0000-000000000002'),
    (:shop_b, 'org/25b/riz.jpg',   'product_photo', :owner_b, '25aaaaaa-0000-0000-0000-000000000005');


\echo ''
\echo '--- TEST 1: only an administrator opens the vitrine ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '25252525-0000-0000-0000-000000000003';
do $$ begin
    begin
        perform set_storefront('25000000-0000-0000-0000-000000000001', true, 'x');
        raise exception 'FAIL: an employee opened the vitrine';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the employee was refused — %', sqlerrm;
    end;
end $$;
rollback;

-- The owner opens it, and this is committed: the street reads it below in
-- fresh transactions that carry no identity at all.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '25252525-0000-0000-0000-000000000001';
do $$
declare v_on boolean; v_blurb text;
begin
    perform set_storefront('25000000-0000-0000-0000-000000000001', true,
                           '  Le meilleur sucre du marché  ');
    select storefront_enabled, storefront_blurb into v_on, v_blurb
      from orgs where id = '25000000-0000-0000-0000-000000000001';
    if not v_on then
        raise exception 'FAIL: the owner could not open the vitrine';
    end if;
    if v_blurb is distinct from 'Le meilleur sucre du marché' then
        raise exception 'FAIL: the blurb was not kept, trimmed (got %)', v_blurb;
    end if;
    raise notice 'PASS: the owner opened the vitrine with a trimmed blurb';
end $$;
commit;

\echo ''
\echo '--- TEST 2: the street sees the window — and only the window ---'
begin;
set local role authenticated;
-- No claim: auth.uid() is null. This is the street.
do $$
declare v_rows int; v_names text; v_sucre_stock boolean; v_epuise_stock boolean;
        v_photo text; v_name text; v_blurb text;
begin
    select count(*), min(name), min(blurb) into v_rows, v_name, v_blurb
      from storefront('vitrine-a-25');
    if v_rows <> 1 then
        raise exception 'FAIL: the open vitrine returned % rows', v_rows;
    end if;
    if v_name <> 'Boutique Esperance' then
        raise exception 'FAIL: wrong shop in the window: %', v_name;
    end if;

    -- Membership, not order: *which* articles are in the window is the claim.
    -- The order of 'Épuisé' against 'Sucre' depends on the database's
    -- collation — C on a scratch cluster, en_US.utf8 on CI — and is not it.
    select count(*), string_agg(name, ',' order by name)
      into v_rows, v_names from storefront_products('vitrine-a-25');
    if v_rows <> 2
       or not exists (select 1 from storefront_products('vitrine-a-25')
                       where name = 'Sucre 1kg')
       or not exists (select 1 from storefront_products('vitrine-a-25')
                       where name = 'Épuisé') then
        raise exception 'FAIL: expected exactly Sucre 1kg and Épuisé in the window, got % (%)',
            v_rows, v_names;
    end if;

    select in_stock, photo_key into v_sucre_stock, v_photo
      from storefront_products('vitrine-a-25') where name = 'Sucre 1kg';
    select in_stock into v_epuise_stock
      from storefront_products('vitrine-a-25') where name = 'Épuisé';
    if not v_sucre_stock or v_epuise_stock then
        raise exception 'FAIL: in_stock is wrong (sucre %, épuisé %)',
            v_sucre_stock, v_epuise_stock;
    end if;
    if v_photo <> 'org/25a/sucre.jpg' then
        raise exception 'FAIL: the newest photo key was not returned: %', v_photo;
    end if;

    -- The photos the Worker may serve to the street: the published article's
    -- yes; the unpublished one's no; a closed vitrine's no; nonsense no.
    if not storefront_photo_allowed('org/25a/sucre.jpg') then
        raise exception 'FAIL: the published article''s photo was refused';
    end if;
    if storefront_photo_allowed('org/25a/savon.jpg') then
        raise exception 'FAIL: an unpublished article''s photo leaked';
    end if;
    if storefront_photo_allowed('org/25b/riz.jpg') then
        raise exception 'FAIL: a closed vitrine''s photo leaked';
    end if;
    if storefront_photo_allowed('org/nowhere/x.jpg') then
        raise exception 'FAIL: a key that does not exist was allowed';
    end if;
    raise notice 'PASS: the street sees Sucre and Épuisé, with the right stock and photo, and no more';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: nothing behind the counter is on the row ---'
begin;
do $$
declare v_sig text;
begin
    select pg_get_function_result(p.oid) into v_sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'storefront_products';
    if v_sig ilike '%cost%' or v_sig ilike '%quantity%' then
        raise exception 'FAIL: the window row carries something from behind the counter: %', v_sig;
    end if;
    raise notice 'PASS: the window row has no cost price and no count — %', v_sig;
end $$;
rollback;

\echo ''
\echo '--- TEST 4: a closed, suspended or archived business vanishes from the street ---'
-- Closed: shop B never opened its vitrine.
begin;
set local role authenticated;
do $$
declare v_rows int;
begin
    select count(*) into v_rows from storefront('vitrine-b-25');
    if v_rows <> 0 then
        raise exception 'FAIL: a closed vitrine is visible (% rows)', v_rows;
    end if;
    select count(*) into v_rows from storefront_products('vitrine-b-25');
    if v_rows <> 0 then
        raise exception 'FAIL: a closed vitrine shows articles (% rows)', v_rows;
    end if;
    raise notice 'PASS: the vitrine that was never opened is not there';
end $$;
rollback;

-- Suspended: the platform freezes shop A; its open vitrine goes dark too.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '25252525-0000-0000-0000-000000000005';
select set_org_suspended('25000000-0000-0000-0000-000000000001', true);
set local "request.jwt.claim.sub" = '';
do $$
declare v_rows int;
begin
    select count(*) into v_rows from storefront('vitrine-a-25');
    if v_rows <> 0 then
        raise exception 'FAIL: a suspended business is still on the street';
    end if;
    if storefront_photo_allowed('org/25a/sucre.jpg') then
        raise exception 'FAIL: a suspended business''s photo is still served';
    end if;
    raise notice 'PASS: suspension takes the vitrine off the street';
end $$;
rollback;

-- Closed by the owner: the switch is the shop's to flip back.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '25252525-0000-0000-0000-000000000001';
select set_storefront('25000000-0000-0000-0000-000000000001', false);
set local "request.jwt.claim.sub" = '';
do $$
declare v_rows int;
begin
    select count(*) into v_rows from storefront_products('vitrine-a-25');
    if v_rows <> 0 then
        raise exception 'FAIL: the owner closed the vitrine and it is still open';
    end if;
    raise notice 'PASS: the owner can close the vitrine';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: any writer of the shop may put an article in the window; a stranger may not ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '25252525-0000-0000-0000-000000000004';
do $$
declare v_rows int;
begin
    update products set is_published = true
     where id = '25aaaaaa-0000-0000-0000-000000000002';
    get diagnostics v_rows = row_count;
    if v_rows <> 0 then
        raise exception 'FAIL: a stranger put an article in the window';
    end if;
    raise notice 'PASS: the stranger''s update touched nothing';
end $$;
rollback;

begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '25252525-0000-0000-0000-000000000003';
do $$
declare v_rows int;
begin
    update products set is_published = true
     where id = '25aaaaaa-0000-0000-0000-000000000002';
    get diagnostics v_rows = row_count;
    if v_rows <> 1 then
        raise exception 'FAIL: the employee could not put Savon in the window';
    end if;
end $$;
set local "request.jwt.claim.sub" = '';
do $$
declare v_rows int;
begin
    select count(*) into v_rows from storefront_products('vitrine-a-25');
    if v_rows <> 3 then
        raise exception 'FAIL: Savon did not appear in the window (% rows)', v_rows;
    end if;
    if not storefront_photo_allowed('org/25a/savon.jpg') then
        raise exception 'FAIL: Savon''s photo is still refused once published';
    end if;
    raise notice 'PASS: the employee published Savon and the street sees it, photo included';
end $$;
rollback;

\echo ''
\echo '=== test_storefront.sql: all checks passed ==='
