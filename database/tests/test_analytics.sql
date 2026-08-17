-- ============================================================
-- test_analytics.sql — the owner and platform analytics of 036.
--
-- Phone block 14. What matters, in order of what it would cost to get wrong:
--   1. The owner's headline adds up (revenue, margin, units, baskets).
--   2. A restricted employee — one without full visibility — is refused, so
--      analytics never becomes the back door to the margins RLS hides.
--   3. Product performance ranks by revenue and reports a velocity.
--   4. The platform totals cross every business, and refuse anyone who is not
--      a platform admin.
--
-- The shop is inserted directly with a fixed id (14000000-...) and seeded, the
-- way the test needs a constant to name it by; create_org is proven elsewhere.
-- ============================================================
\set ON_ERROR_STOP on

\set admin '''14141414-0000-0000-0000-000000000001'''
\set owner '''14141414-0000-0000-0000-000000000002'''
\set clerk '''14141414-0000-0000-0000-000000000003'''
\set org   '''14000000-0000-0000-0000-000000000001'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:admin, '+22614000001', '{"full_name": "Plateforme"}'),
    (:owner, '+22614000002', '{"full_name": "Patronne"}'),
    (:clerk, '+22614000003', '{"full_name": "Vendeuse"}');
update profiles set is_platform_admin = true where id = :admin;

-- The shop, seeded, with the owner on full visibility and the clerk on summary.
insert into orgs (id, name, slug, profile, default_currency)
values (:org, 'Boutique Analyse', 'boutique-analyse-14', 'retail', 'XOF');
select seed_retail_accounts(:org);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:org, :owner, 'owner',   'org', :org, 'full'),
    (:org, :clerk, 'employee', 'org', :org, 'summary');

-- Stock and sell, placed in time so "when" has something to group.
begin;
set local "request.jwt.claim.sub" = '14141414-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v_rice uuid; v_oil uuid;
begin
    v_rice := ensure_product('14000000-0000-0000-0000-000000000001', 'Riz 5kg', 3000, 2000);
    v_oil  := ensure_product('14000000-0000-0000-0000-000000000001', 'Huile 1L', 1200, 900);
    perform receive_products('14000000-0000-0000-0000-000000000001', v_rice, 100, 2000);
    perform receive_products('14000000-0000-0000-0000-000000000001', v_oil, 100, 900);

    -- Rice: 10 units over two mornings. Revenue 30 000, cost 20 000.
    perform record_sale('14000000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', v_rice, 'quantity', 6, 'unit_price', 3000)),
        'cash', null, null, null, '2026-08-10 09:00+00');
    perform record_sale('14000000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', v_rice, 'quantity', 4, 'unit_price', 3000)),
        'cash', null, null, null, '2026-08-11 10:00+00');
    -- Oil: 5 units one afternoon. Revenue 6 000, cost 4 500.
    perform record_sale('14000000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', v_oil, 'quantity', 5, 'unit_price', 1200)),
        'cash', null, null, null, '2026-08-11 15:00+00');
end $$;
commit;

\echo ''
\echo '--- TEST 1: the owner headline adds up ---'
begin;
set local "request.jwt.claim.sub" = '14141414-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare r record;
begin
    select * into r from org_sales_headline('14000000-0000-0000-0000-000000000001');
    -- 3 sales, revenue 36 000, cost 24 500, margin 11 500, 15 units, 2 products.
    if r.sale_count <> 3 then raise exception 'FAIL: sale_count % (want 3)', r.sale_count; end if;
    if r.revenue <> 36000 then raise exception 'FAIL: revenue % (want 36000)', r.revenue; end if;
    if r.margin <> 11500 then raise exception 'FAIL: margin % (want 11500)', r.margin; end if;
    if r.units <> 15 then raise exception 'FAIL: units % (want 15)', r.units; end if;
    if r.products_sold <> 2 then raise exception 'FAIL: products_sold % (want 2)', r.products_sold; end if;
    if r.avg_basket <> 12000 then raise exception 'FAIL: avg_basket % (want 12000)', r.avg_basket; end if;
    raise notice 'PASS: headline 3 sales / 36000 / margin 11500 / 15 units';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: a restricted clerk cannot read the analytics ---'
begin;
set local "request.jwt.claim.sub" = '14141414-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare r record; v_raised boolean := false;
begin
    begin
        select * into r from org_sales_headline('14000000-0000-0000-0000-000000000001');
    exception when others then
        v_raised := true;
    end;
    if not v_raised then
        raise exception 'FAIL: a summary-visibility clerk read the owner analytics';
    end if;
    raise notice 'PASS: the clerk is refused';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: product performance ranks by revenue and reports velocity ---'
begin;
set local "request.jwt.claim.sub" = '14141414-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v_first text; v_first_units numeric; v_first_perday numeric;
begin
    select name, units, per_day into v_first, v_first_units, v_first_perday
    from org_product_performance('14000000-0000-0000-0000-000000000001')
    order by revenue desc limit 1;

    if v_first <> 'Riz 5kg' then
        raise exception 'FAIL: top product is % (want Riz 5kg)', v_first;
    end if;
    if v_first_units <> 10 then
        raise exception 'FAIL: rice units % (want 10)', v_first_units;
    end if;
    -- Rice sold across ~1 day, so a positive, non-absurd velocity is enough; the
    -- exact figure is span-dependent and not worth pinning.
    if v_first_perday <= 0 then
        raise exception 'FAIL: rice per_day % is not positive', v_first_perday;
    end if;
    raise notice 'PASS: rice tops the list, 10 units, % /day', v_first_perday;
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the platform total crosses businesses, admin only ---'
begin;
set local "request.jwt.claim.sub" = '14141414-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare r record; v_here boolean;
begin
    select * into r from platform_analytics_headline();
    if r.revenue < 36000 then
        raise exception 'FAIL: platform revenue % excludes this shop', r.revenue;
    end if;
    if r.active_businesses < 1 then
        raise exception 'FAIL: no active businesses counted';
    end if;

    select exists (
        select 1 from platform_business_performance()
        where org_id = '14000000-0000-0000-0000-000000000001' and revenue = 36000
    ) into v_here;
    if not v_here then
        raise exception 'FAIL: the shop is missing from platform_business_performance';
    end if;
    raise notice 'PASS: platform total includes the shop';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: a business owner is not a platform admin ---'
begin;
set local "request.jwt.claim.sub" = '14141414-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare r record; v_raised boolean := false;
begin
    begin
        select * into r from platform_analytics_headline();
    exception when others then
        v_raised := true;
    end;
    if not v_raised then
        raise exception 'FAIL: a business owner read platform-wide analytics';
    end if;
    raise notice 'PASS: the owner is refused the platform view';
end $$;
rollback;

\echo ''
\echo '=== test_analytics.sql: all checks passed ==='
