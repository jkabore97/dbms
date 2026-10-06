-- ============================================================
-- test_reach_and_locks.sql — a delivery has a reach; Factures, Photos and
-- Rapports are locked by the dial, not only hidden (069). Phone block 41.
--
-- The claims: a door within the shop's reach is priced and one beyond it
-- is not — delivery_check() says how far and how far the shop goes, and
-- the 7 660 km quote of the audit is gone; a shop sets its own reach and
-- only its administrator may; a delivery order beyond the reach is refused
-- at the door whatever path it took, while a pickup from anywhere and a
-- delivery with no pin pass. An employee the owner shut out of invoices
-- cannot create one, an employee with no rule can, and the owner always
-- can; photos follow the photos dial and an article's photo follows the
-- articles dial; the gallery and every report refuse a hidden dial and
-- answer the default one; and the renamed originals are closed to anon.
-- ============================================================
\set ON_ERROR_STOP on
-- 092 hides a vitrine below 8 items (test_vitrine_minimum.sql); this
-- suite is about something else, so it keeps the old rule (no minimum).
update platform_settings set value = '0' where key = 'vitrine_min_items';

\set owner  '''41414141-0000-0000-0000-000000000001'''
\set clerk  '''41414141-0000-0000-0000-000000000002'''
\set boss   '''41414141-0000-0000-0000-000000000003'''
\set buyer  '''41414141-0000-0000-0000-000000000004'''
\set shop   '''41000000-0000-0000-0000-000000000001'''
\set church '''41000000-0000-0000-0000-000000000002'''
\set item   '''41aaaaaa-0000-0000-0000-000000000001'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname='anon') then
        create role anon nologin;
    end if;
end $$;
grant usage on schema public to authenticated, anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- No blanket function grant here: every call below runs on the grants the
-- migrations themselves give.

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22641000001', '{"full_name": "Propriétaire"}'),
    (:clerk, '+22641000002', '{"full_name": "Vendeuse"}'),
    (:boss,  '+22641000003', '{"full_name": "Pasteur"}'),
    (:buyer, '+22641000004', '{"full_name": "Cliente"}');
-- Pinned in Ouagadougou, as a shop there would be.
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, lat, lng) values
    (:shop,   'Boutique Portée', 'portee-41', 'retail',      'XOF', true, 12.3714, -1.5197),
    (:church, 'Assemblée 41',    'assemblee-41', 'association', 'XOF', false, null, null);
select seed_retail_accounts(:shop);
-- Delivery is Kaj Pro since 081: the shops these claims deliver for are Pro.
update orgs set plan = 'pro' where profile = 'retail' and plan is distinct from 'pro' and slug ~ '^portee-';
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,   :owner, 'owner',    'org', :shop,   'full'),
    (:shop,   :clerk, 'employee', 'org', :shop,   'full'),
    (:church, :boss,  'owner',    'org', :church, 'full'),
    (:church, :clerk, 'employee', 'org', :church, 'full');
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published, created_by) values
    (:item, :shop, 'Savon', 450, 300, 20, true, true, :owner);


\echo ''
\echo '--- TEST 1: a door within reach is priced; one beyond it is not, and says so ---'
begin;
set local role anon;
do $$
declare r record; v numeric;
begin
    -- Patte d'Oie, about 3 km from the shop.
    select * into r from delivery_check('portee-41', 12.3420, -1.5050);
    if r.too_far or r.fee is null or r.max_km <> 15 or r.distance_km > 5 then
        raise exception 'FAIL: a 3 km door reads %', r;
    end if;
    -- Newark, New Jersey: the audit's 1 149 450 FCFA.
    select * into r from delivery_check('portee-41', 40.757953, -74.191392);
    if not r.too_far or r.fee is not null or r.distance_km < 7000 then
        raise exception 'FAIL: an ocean away reads %', r;
    end if;
    v := delivery_quote('portee-41', 40.757953, -74.191392);
    if v is not null then
        raise exception 'FAIL: the old question still prices an ocean: %', v;
    end if;
    raise notice 'PASS: 3 km priced, 7 660 km not; delivery_check says how far and how far the shop goes';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: a shop sets its own reach, and only its administrator ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '41414141-0000-0000-0000-000000000002';
do $$ begin
    begin
        perform set_delivery_reach('41000000-0000-0000-0000-000000000001', 40);
        raise exception 'FAIL: an employee set the reach';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '41414141-0000-0000-0000-000000000001';
do $$
declare r record;
begin
    begin
        perform set_delivery_reach('41000000-0000-0000-0000-000000000001', 500);
        raise exception 'FAIL: a 500 km reach was accepted';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    perform set_delivery_reach('41000000-0000-0000-0000-000000000001', 40);
    -- Koudougou side, about 25 km: beyond 15, within 40.
    select * into r from delivery_check('portee-41', 12.3714, -1.7500);
    if r.too_far or r.max_km <> 40 or r.fee is null then
        raise exception 'FAIL: the shop''s own reach did not apply: %', r;
    end if;
    perform set_delivery_reach('41000000-0000-0000-0000-000000000001', null);
    select * into r from delivery_check('portee-41', 12.3714, -1.7500);
    if not r.too_far or r.max_km <> 15 then
        raise exception 'FAIL: null did not return the shop to the default: %', r;
    end if;
    raise notice 'PASS: the employee refused, 500 km refused, 40 km applied, null back to 15';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: a delivery beyond the reach is refused at the door; pickup and no-pin pass ---'
begin;
do $$ begin
    begin
        insert into orders (org_id, customer_id, customer_name, fulfilment, address, drop_lat, drop_lng)
        values ('41000000-0000-0000-0000-000000000001', '41414141-0000-0000-0000-000000000004',
                'Cliente', 'delivery', 'Newark', 40.757953, -74.191392);
        raise exception 'FAIL: a 7 660 km delivery was taken';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like 'Trop loin pour une livraison%' then
            raise exception 'FAIL: the refusal does not say why — %', sqlerrm;
        end if;
    end;
    insert into orders (org_id, customer_id, customer_name, fulfilment, address, drop_lat, drop_lng)
    values ('41000000-0000-0000-0000-000000000001', '41414141-0000-0000-0000-000000000004',
            'Cliente', 'delivery', 'Patte d''Oie', 12.3420, -1.5050);
    insert into orders (org_id, customer_id, customer_name, fulfilment)
    values ('41000000-0000-0000-0000-000000000001', '41414141-0000-0000-0000-000000000004',
            'Cliente', 'pickup');
    insert into orders (org_id, customer_id, customer_name, fulfilment, address)
    values ('41000000-0000-0000-0000-000000000001', '41414141-0000-0000-0000-000000000004',
            'Cliente', 'delivery', 'Sans épingle');
    raise notice 'PASS: refused beyond the reach in words; within reach, pickup and no pin all taken';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: Factures — shut out means shut out; no rule and the owner both pass ---'
begin;
insert into org_feature_rules (org_id, tier, feature, access)
values (:shop, 'employee', 'invoices', 'hidden');
set local role authenticated;
set local "request.jwt.claim.sub" = '41414141-0000-0000-0000-000000000002';
do $$ begin
    begin
        perform create_invoice(
            p_org_id        => '41000000-0000-0000-0000-000000000001',
            p_customer_name => 'Hôtel',
            p_lines         => '[{"description": "Savon", "quantity": 2, "unit_price": 450}]'::jsonb);
        raise exception 'FAIL: a shut-out employee created an invoice';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like 'Les factures vous sont fermées%' then
            raise exception 'FAIL: refused for the wrong reason — %', sqlerrm;
        end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '41414141-0000-0000-0000-000000000001';
select create_invoice(
    p_org_id        => :shop,
    p_customer_name => 'Hôtel',
    p_lines         => '[{"description": "Savon", "quantity": 2, "unit_price": 450}]'::jsonb) is not null as owner_invoiced \gset
reset role;
delete from org_feature_rules where org_id = :shop and feature = 'invoices';
set local role authenticated;
set local "request.jwt.claim.sub" = '41414141-0000-0000-0000-000000000002';
do $$ begin
    perform create_invoice(
        p_org_id        => '41000000-0000-0000-0000-000000000001',
        p_customer_name => 'Hôtel',
        p_lines         => '[{"description": "Savon", "quantity": 1, "unit_price": 450}]'::jsonb);
    raise notice 'PASS: hidden refused in words; the owner and an employee with no rule invoice';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: Photos — the photos dial for a document, the articles dial for an article''s photo ---'
begin;
insert into org_feature_rules (org_id, tier, feature, access) values
    (:shop, 'employee', 'photos', 'view');
set local role authenticated;
set local "request.jwt.claim.sub" = '41414141-0000-0000-0000-000000000002';
do $$
declare n int;
begin
    begin
        perform record_document(p_org_id => '41000000-0000-0000-0000-000000000001',
                                p_r2_key => 'org/41000000-0000-0000-0000-000000000001/recu.jpg');
        raise exception 'FAIL: a view-only employee took a photo';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like 'Les photos vous sont fermées%' then
            raise exception 'FAIL: refused for the wrong reason — %', sqlerrm;
        end if;
    end;
    -- The article's own photo is the articles dial's (edit by default).
    perform record_document(p_org_id => '41000000-0000-0000-0000-000000000001',
                            p_r2_key => 'org/41000000-0000-0000-0000-000000000001/savon.jpg',
                            p_product_id => '41aaaaaa-0000-0000-0000-000000000001');
    -- And the gallery opens on 'view'.
    select count(*) into n from org_documents('41000000-0000-0000-0000-000000000001');
    raise notice 'PASS: a document refused on view, an article photo taken on articles edit, the gallery open on view (% rows)', n;
end $$;
reset role;
update org_feature_rules set access = 'hidden'
 where org_id = :shop and feature = 'photos';
set local role authenticated;
set local "request.jwt.claim.sub" = '41414141-0000-0000-0000-000000000002';
do $$ begin
    begin
        perform org_documents('41000000-0000-0000-0000-000000000001');
        raise exception 'FAIL: a hidden gallery answered';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    begin
        perform unfiled_documents('41000000-0000-0000-0000-000000000001');
        raise exception 'FAIL: a hidden unfiled list answered';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    raise notice 'PASS: both gallery lists refuse a hidden dial';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: Rapports — every report refuses a hidden dial and answers the default ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '41414141-0000-0000-0000-000000000002';
do $$
declare n int;
begin
    -- No rule: 'reports' defaults to view, so the default employee reads.
    select count(*) into n from income_statement('41000000-0000-0000-0000-000000000001');
    select count(*) into n from journal_page('41000000-0000-0000-0000-000000000001');
    select count(*) into n from church_balances('41000000-0000-0000-0000-000000000002');
    raise notice 'PASS: on the default dial the reports answer';
end $$;
reset role;
insert into org_feature_rules (org_id, tier, feature, access) values
    (:shop,   'employee', 'reports', 'hidden'),
    (:church, 'employee', 'reports', 'hidden');
set local role authenticated;
set local "request.jwt.claim.sub" = '41414141-0000-0000-0000-000000000002';
do $$
declare v_call text; v_refused int := 0;
begin
    foreach v_call in array array[
        'select * from income_statement(''41000000-0000-0000-0000-000000000001'')',
        'select * from balance_sheet(''41000000-0000-0000-0000-000000000001'')',
        'select * from trial_balance(''41000000-0000-0000-0000-000000000001'')',
        'select * from journal_page(''41000000-0000-0000-0000-000000000001'')',
        'select * from account_ledger(''41000000-0000-0000-0000-000000000001'', (select id from accounts where org_id = ''41000000-0000-0000-0000-000000000001'' limit 1))',
        'select * from church_weekly_summary(''41000000-0000-0000-0000-000000000002'')',
        'select * from church_balances(''41000000-0000-0000-0000-000000000002'')'
    ] loop
        begin
            execute v_call;
            raise exception 'FAIL: answered on a hidden dial: %', v_call;
        exception when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            if sqlerrm not like 'Les rapports vous sont fermés%' then
                raise exception 'FAIL: % refused for the wrong reason — %', v_call, sqlerrm;
            end if;
            v_refused := v_refused + 1;
        end;
    end loop;
    raise notice 'PASS: all % reports refuse a hidden dial in words', v_refused;
end $$;
set local "request.jwt.claim.sub" = '41414141-0000-0000-0000-000000000001';
do $$
declare n int;
begin
    select count(*) into n from income_statement('41000000-0000-0000-0000-000000000001');
    raise notice 'PASS: the owner reads whatever the employees'' dial says';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: the renamed originals are closed to anon, and the guards are what the names call ---'
do $$
declare v_core text; v_open text[] := '{}';
begin
    foreach v_core in array array[
        'income_statement_core(uuid, date, date)',
        'balance_sheet_core(uuid, date)',
        'trial_balance_core(uuid, date, date)',
        'account_ledger_core(uuid, uuid, date, date, integer)',
        'journal_page_core(uuid, date, date, integer, integer)',
        'church_weekly_summary_core(uuid, date)',
        'church_balances_core(uuid)',
        'member_giving_statement_core(uuid, integer)',
        'org_documents_core(uuid, text, integer, integer)',
        'unfiled_documents_core(uuid, integer)'
    ] loop
        if to_regprocedure(v_core) is null then
            raise exception 'FAIL: % does not exist', v_core;
        end if;
        if has_function_privilege('anon', v_core, 'execute') then
            v_open := v_open || v_core;
        end if;
    end loop;
    if array_length(v_open, 1) > 0 then
        raise exception 'FAIL: open to anon: %', v_open;
    end if;
    if (select prosrc from pg_proc where oid = 'income_statement(uuid, date, date)'::regprocedure)
       not like '%require_feature%' then
        raise exception 'FAIL: income_statement is not the guard';
    end if;
    raise notice 'PASS: ten originals renamed and closed to anon; the public names are the guards';
end $$;
