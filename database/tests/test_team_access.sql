-- ============================================================
-- test_team_access.sql — the owner's dial.
--
-- Phone block 95. What matters: a business that never touched the dial
-- behaves exactly as yesterday; a tightened rule actually refuses at the
-- server, not just in the interface; supervisors and employees read
-- their own tiers; the owner is never dialled down; and only admins may
-- turn the dial at all.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''95959595-0000-0000-0000-000000000001'''
\set super    '''95959595-0000-0000-0000-000000000002'''
\set clerk    '''95959595-0000-0000-0000-000000000003'''
\set shop     '''95000000-0000-0000-0000-000000000001'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22695000001', '{"full_name": "Patronne"}'),
    (:super, '+22695000002', '{"full_name": "Cheffe"}'),
    (:clerk, '+22695000003', '{"full_name": "Vendeuse"}');

insert into orgs (id, name, slug, profile, default_currency) values
    (:shop, 'Boutique 95', 'boutique-95', 'retail', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:shop, :owner, 'owner',      'org', :shop),
    (:shop, :super, 'supervisor', 'org', :shop),
    (:shop, :clerk, 'employee',   'org', :shop);

\echo ''
\echo '--- TEST 1: no rules — yesterday''s behaviour, to the letter ---'
begin;
set local "request.jwt.claim.sub" = '95959595-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_soap uuid; v_debt uuid; v_price numeric;
begin
    v_soap := ensure_product('95000000-0000-0000-0000-000000000001'::uuid,
        'Savon', p_sale_price => 300, p_cost_price => 200);
    update products set sale_price = 350 where id = v_soap;
    select sale_price into v_price from products where id = v_soap;
    if v_price <> 350 then
        raise exception 'FAIL: default no longer lets an employee edit a price';
    end if;

    v_debt := record_credit_sale('95000000-0000-0000-0000-000000000001'::uuid,
        'Awa', 500, 'Savon');
    perform record_debt_payment(v_debt, 500);

    perform record_production('95000000-0000-0000-0000-000000000001'::uuid,
        5, jsonb_build_array(jsonb_build_object('name', 'Savon', 'quantity', 1)),
        p_product_name => 'Coffret');
    raise notice 'PASS: untouched dial, untouched behaviour';
end $$;
commit;

\echo ''
\echo '--- TEST 2: only an admin turns the dial ---'
begin;
set local "request.jwt.claim.sub" = '95959595-0000-0000-0000-000000000003';
set local role authenticated;
do $$
begin
    begin
        insert into org_feature_rules (org_id, tier, feature, access)
        values ('95000000-0000-0000-0000-000000000001', 'employee', 'credits', 'edit');
        raise exception 'FAIL: an employee wrote an access rule';
    exception
        when insufficient_privilege then
            raise notice 'PASS: the employee''s rule bounced off RLS';
        when raise_exception then
            raise;
    end;
end $$;
commit;

begin;
set local "request.jwt.claim.sub" = '95959595-0000-0000-0000-000000000001';
set local role authenticated;
insert into org_feature_rules (org_id, tier, feature, access, updated_by) values
    ('95000000-0000-0000-0000-000000000001', 'employee', 'products',   'view',
     '95959595-0000-0000-0000-000000000001'),
    ('95000000-0000-0000-0000-000000000001', 'employee', 'credits',    'view',
     '95959595-0000-0000-0000-000000000001'),
    ('95000000-0000-0000-0000-000000000001', 'employee', 'production', 'hidden',
     '95959595-0000-0000-0000-000000000001');
commit;

\echo ''
\echo '--- TEST 3: the tightened dial refuses at the server ---'
begin;
set local "request.jwt.claim.sub" = '95959595-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_soap uuid; v_price numeric;
begin
    select id into v_soap from products
     where org_id = '95000000-0000-0000-0000-000000000001'
       and lower(btrim(name)) = 'savon';

    -- Price edit: silently zero rows under the new policy, price unmoved.
    update products set sale_price = 9999 where id = v_soap;
    select sale_price into v_price from products where id = v_soap;
    if v_price = 9999 then
        raise exception 'FAIL: a viewed-only employee changed a price';
    end if;

    begin
        perform record_credit_sale('95000000-0000-0000-0000-000000000001'::uuid,
            'Moussa', 100, 'Savon');
        raise exception 'FAIL: credits at view still granted credit';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: credit refused — %', sqlerrm;
    end;

    begin
        perform record_production('95000000-0000-0000-0000-000000000001'::uuid,
            5, jsonb_build_array(jsonb_build_object('name', 'Savon', 'quantity', 1)),
            p_product_name => 'Coffret');
        raise exception 'FAIL: hidden production still recorded a run';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: production refused — %', sqlerrm;
    end;
end $$;
commit;

\echo ''
\echo '--- TEST 4: the supervisor tier is its own dial ---'
begin;
set local "request.jwt.claim.sub" = '95959595-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v_soap uuid; v_price numeric;
begin
    -- No supervisor rules were written: the supervisor keeps the default.
    select id into v_soap from products
     where org_id = '95000000-0000-0000-0000-000000000001'
       and lower(btrim(name)) = 'savon';
    update products set sale_price = 380 where id = v_soap;
    select sale_price into v_price from products where id = v_soap;
    if v_price <> 380 then
        raise exception 'FAIL: employee rules leaked onto the supervisor';
    end if;
    raise notice 'PASS: the supervisor edits while the employee views';
end $$;
commit;

\echo ''
\echo '--- TEST 5: the owner is never dialled down ---'
begin;
set local "request.jwt.claim.sub" = '95959595-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_soap uuid; v_price numeric; v_debt uuid;
begin
    select id into v_soap from products
     where org_id = '95000000-0000-0000-0000-000000000001'
       and lower(btrim(name)) = 'savon';
    update products set sale_price = 400 where id = v_soap;
    select sale_price into v_price from products where id = v_soap;
    if v_price <> 400 then
        raise exception 'FAIL: a rule reached the owner';
    end if;
    v_debt := record_credit_sale('95000000-0000-0000-0000-000000000001'::uuid,
        'Fatou', 200, 'Savon');
    if v_debt is null then
        raise exception 'FAIL: the owner could not grant credit';
    end if;
    raise notice 'PASS: the owner keeps every tool';
end $$;
commit;

\echo ''
\echo '--- TEST 6: the employee still sells — the counter never stops ---'
begin;
set local "request.jwt.claim.sub" = '95959595-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_soap uuid; v_sale uuid; v_qty numeric;
begin
    select id, quantity into v_soap, v_qty from products
     where org_id = '95000000-0000-0000-0000-000000000001'
       and lower(btrim(name)) = 'savon';
    v_sale := record_sale('95000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_array(jsonb_build_object('product_id', v_soap,
            'name', 'Savon', 'quantity', 1, 'unit_price', 400)));
    if v_sale is null then
        raise exception 'FAIL: view-level articles blocked a cash sale';
    end if;
    raise notice 'PASS: the sale went through, rules or no rules';
end $$;
commit;

\echo ''
\echo '=== test_team_access.sql: all assertions passed ==='
