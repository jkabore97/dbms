-- ============================================================
-- test_platform_admin_edit.sql — a platform admin can edit a business they run
-- from the console but do not belong to (041).
--
-- Phone block 19. The regression: feature_access() and has_full_visibility()
-- were membership-only, so a platform admin with no membership got 'hidden' /
-- false — and the products UPDATE policy (can_write_org AND feature_access =
-- 'edit') silently matched zero rows. This proves the platform admin now edits,
-- while a plain employee restricted by the dial still cannot.
-- ============================================================
\set ON_ERROR_STOP on

\set padmin '''19191919-0000-0000-0000-000000000001'''
\set owner  '''19191919-0000-0000-0000-000000000002'''
\set clerk  '''19191919-0000-0000-0000-000000000003'''
\set org    '''19000000-0000-0000-0000-000000000001'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:padmin, '+22619000001', '{"full_name": "Console"}'),
    (:owner,  '+22619000002', '{"full_name": "Patronne"}'),
    (:clerk,  '+22619000003', '{"full_name": "Vendeuse"}');
-- The platform admin does NOT own this shop — the owner does.
update profiles set is_platform_admin = true where id = :padmin;

insert into orgs (id, name, slug, profile, default_currency)
values (:org, 'Boutique Console', 'boutique-console-19', 'retail', 'XOF');
select seed_retail_accounts(:org);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:org, :owner, 'owner',    'org', :org, 'full'),
    (:org, :clerk, 'employee', 'org', :org, 'summary');

-- A product to edit, and the dial closed to the employee tier for 'products'.
insert into products (org_id, name, sale_price, cost_price)
values (:org, 'Savon', 500, 300);
insert into org_feature_rules (org_id, tier, feature, access)
values (:org, 'employee', 'products', 'view');


\echo ''
\echo '--- TEST 1: the platform admin (no membership) can edit a product ---'
begin;
set local "request.jwt.claim.sub" = '19191919-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_rows int;
begin
    if not is_org_member('19000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: platform admin cannot even read the org';
    end if;
    if feature_access('19000000-0000-0000-0000-000000000001','products') <> 'edit' then
        raise exception 'FAIL: feature_access is % not edit',
            feature_access('19000000-0000-0000-0000-000000000001','products');
    end if;

    update products set name = 'Savon Modifie'
     where org_id = '19000000-0000-0000-0000-000000000001';
    get diagnostics v_rows = row_count;
    if v_rows <> 1 then
        raise exception 'FAIL: the update changed % rows, not 1', v_rows;
    end if;

    if not has_full_visibility('19000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: platform admin lacks full visibility';
    end if;
    raise notice 'PASS: platform admin edits the product and sees every figure';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: an employee the dial set to view still cannot edit ---'
begin;
set local "request.jwt.claim.sub" = '19191919-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_rows int;
begin
    if feature_access('19000000-0000-0000-0000-000000000001','products') <> 'view' then
        raise exception 'FAIL: employee feature_access is % not view',
            feature_access('19000000-0000-0000-0000-000000000001','products');
    end if;
    update products set name = 'Interdit'
     where org_id = '19000000-0000-0000-0000-000000000001';
    get diagnostics v_rows = row_count;
    if v_rows <> 0 then
        raise exception 'FAIL: a view-only employee changed % rows', v_rows;
    end if;
    raise notice 'PASS: the restricted employee still cannot edit';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: the owner (member) still edits, unchanged ---'
begin;
set local "request.jwt.claim.sub" = '19191919-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v_rows int;
begin
    update products set name = 'Savon Patronne'
     where org_id = '19000000-0000-0000-0000-000000000001';
    get diagnostics v_rows = row_count;
    if v_rows <> 1 then
        raise exception 'FAIL: the owner edit changed % rows, not 1', v_rows;
    end if;
    raise notice 'PASS: the owner still edits';
end $$;
rollback;

\echo ''
\echo '=== test_platform_admin_edit.sql: all checks passed ==='
