-- ============================================================
-- test_product_lifecycle.sql — renaming and archiving a product.
--
-- Phone block 92. What matters: a rename cannot rewrite the history that
-- was written under the old name; "deleting" hides the product without
-- touching a single number it ever produced; only an owner or admin can
-- do the hiding; and it is reversible.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''92929292-0000-0000-0000-000000000001'''
\set clerk    '''92929292-0000-0000-0000-000000000002'''
\set stranger '''92929292-0000-0000-0000-000000000003'''
\set shop     '''92000000-0000-0000-0000-000000000001'''
\set other    '''92000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22692000001', '{"full_name": "Patronne"}'),
    (:clerk,    '+22692000002', '{"full_name": "Vendeuse"}'),
    (:stranger, '+22692000003', '{"full_name": "Voisin"}');

insert into orgs (id, name, slug, profile, default_currency) values
    (:shop,  'Boutique 92', 'boutique-92', 'retail', 'XOF'),
    (:other, 'Boutique 92b', 'boutique-92b', 'retail', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:shop,  :owner,    'owner',    'org', :shop),
    (:shop,  :clerk,    'employee', 'org', :shop),
    (:other, :stranger, 'owner',    'org', :other);

\echo ''
\echo '--- TEST 1: a rename does not rewrite what was sold under the old name ---'
begin;
set local "request.jwt.claim.sub" = '92929292-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_product uuid;
    v_sale uuid;
    v_line_name text;
begin
    v_product := ensure_product('92000000-0000-0000-0000-000000000001'::uuid,
        'Sucre 1kg', p_sale_price => 600, p_cost_price => 450);
    perform receive_products('92000000-0000-0000-0000-000000000001'::uuid,
        v_product, 10, 450);
    v_sale := record_sale('92000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_array(jsonb_build_object(
            'product_id', v_product, 'name', 'Sucre 1kg',
            'quantity', 2, 'unit_price', 600)));

    -- The rename an employee makes tomorrow: staff-level, plain RLS update.
    update products set name = 'Sucre blanc 1kg' where id = v_product;

    select name into v_line_name from sale_lines where sale_id = v_sale;
    if v_line_name is distinct from 'Sucre 1kg' then
        raise exception 'FAIL: yesterday''s receipt now says %', v_line_name;
    end if;
    raise notice 'PASS: renamed on the shelf, unchanged on the receipt';
end $$;
commit;

\echo ''
\echo '--- TEST 2: the employee cannot archive; the owner can ---'
begin;
set local "request.jwt.claim.sub" = '92929292-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v_product uuid;
begin
    select id into v_product from products
     where org_id = '92000000-0000-0000-0000-000000000001';
    begin
        perform archive_product(v_product);
        raise exception 'FAIL: an employee removed a product from the shop';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: employee refused — %', sqlerrm;
    end;
end $$;
commit;

begin;
set local "request.jwt.claim.sub" = '92929292-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_product uuid; v_active boolean; v_lines int;
begin
    select id into v_product from products
     where org_id = '92000000-0000-0000-0000-000000000001';
    perform archive_product(v_product);

    select is_active into v_active from products where id = v_product;
    if v_active then
        raise exception 'FAIL: archive_product left the product on the shelf';
    end if;

    -- The whole point of archiving instead of deleting: every number the
    -- product ever produced is still there.
    select count(*) into v_lines from sale_lines where product_id = v_product;
    if v_lines <> 1 then
        raise exception 'FAIL: archiving touched the sale history (% lines)', v_lines;
    end if;
    raise notice 'PASS: off the shelf, history intact';
end $$;
commit;

\echo ''
\echo '--- TEST 3: archiving is reversible ---'
begin;
set local "request.jwt.claim.sub" = '92929292-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_product uuid; v_active boolean;
begin
    select id into v_product from products
     where org_id = '92000000-0000-0000-0000-000000000001';
    perform archive_product(v_product, false);
    select is_active into v_active from products where id = v_product;
    if not v_active then
        raise exception 'FAIL: the product did not come back';
    end if;
    raise notice 'PASS: back on the shelf';
end $$;
commit;

\echo ''
\echo '--- TEST 4: the neighbour cannot archive across the wall ---'
-- The stranger owns their own shop, so is_org_admin is true somewhere — just
-- not here. The id arrives as if leaked, planted with a known value so the
-- test can name it from the other side of the RLS wall.
begin;
set local "request.jwt.claim.sub" = '92929292-0000-0000-0000-000000000001';
set local role authenticated;
insert into products (id, org_id, name, created_by)
values ('92aaaaaa-0000-0000-0000-000000000001',
        '92000000-0000-0000-0000-000000000001', 'Cible',
        '92929292-0000-0000-0000-000000000001');
commit;

begin;
set local "request.jwt.claim.sub" = '92929292-0000-0000-0000-000000000003';
set local role authenticated;
do $$
begin
    begin
        perform archive_product('92aaaaaa-0000-0000-0000-000000000001'::uuid);
        raise exception 'FAIL: a stranger archived another shop''s product';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: stranger refused even with a leaked id — %', sqlerrm;
    end;
end $$;
commit;

begin;
set local "request.jwt.claim.sub" = '92929292-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_active boolean;
begin
    select is_active into v_active from products
     where id = '92aaaaaa-0000-0000-0000-000000000001';
    if not v_active then
        raise exception 'FAIL: the stranger''s attempt actually archived it';
    end if;
    raise notice 'PASS: the product never moved';
end $$;
commit;

\echo ''
\echo '=== test_product_lifecycle.sql: all assertions passed ==='
