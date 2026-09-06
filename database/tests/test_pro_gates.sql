-- ============================================================
-- test_pro_gates.sql — the line between Kaj and Kaj Pro is held by the database (066).
-- Phone block 38.
--
-- The claims: on a Free business a Pro tool answers 'view' and everything
-- else 'edit'; on a Pro business it answers 'edit'; a lapsed Pro reads
-- 'view' again and loses no row; the owner's dial still wins below the plan
-- (hidden stays hidden on Pro); the platform admin is never gated; the
-- fourth staff account is refused on Free and accepted on Pro; the
-- twenty-first invoice of the month and the fifty-first photo are refused
-- on Free (caps lowered for the test through the platform's own setting
-- function, inside a transaction that is rolled back); a shift, a new
-- tontine, a rate and a dial change are refused on Free with a message
-- that opens the door to pay; "J'ai payé" lands once per business and the
-- platform lists and handles it; and plan_terms() says the price.
-- ============================================================
\set ON_ERROR_STOP on

\set plat     '''38383838-0000-0000-0000-000000000001'''
\set owner_f  '''38383838-0000-0000-0000-000000000002'''
\set owner_p  '''38383838-0000-0000-0000-000000000003'''
\set clerk_p  '''38383838-0000-0000-0000-000000000004'''
\set staff1   '''38383838-0000-0000-0000-000000000005'''
\set staff2   '''38383838-0000-0000-0000-000000000006'''
\set staff3   '''38383838-0000-0000-0000-000000000007'''
\set staff4   '''38383838-0000-0000-0000-000000000008'''
\set org_f    '''38000000-0000-0000-0000-000000000001'''
\set org_p    '''38000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:plat,    '+22638000001', '{"full_name": "Plateforme"}'),
    (:owner_f, '+22638000002', '{"full_name": "Patronne Libre"}'),
    (:owner_p, '+22638000003', '{"full_name": "Patron Pro"}'),
    (:clerk_p, '+22638000004', '{"full_name": "Vendeuse Pro"}'),
    (:staff1,  '+22638000005', '{"full_name": "Un"}'),
    (:staff2,  '+22638000006', '{"full_name": "Deux"}'),
    (:staff3,  '+22638000007', '{"full_name": "Trois"}'),
    (:staff4,  '+22638000008', '{"full_name": "Quatre"}');
update profiles set is_platform_admin = true where id = :plat;

insert into orgs (id, name, slug, profile, default_currency, plan, plan_until) values
    (:org_f, 'Boutique Libre', 'boutique-libre-38', 'retail', 'XOF', 'free', null),
    (:org_p, 'Boutique Pro',   'boutique-pro-38',   'retail', 'XOF', 'pro',  current_date + 30);
select seed_retail_accounts(:org_f);
select seed_retail_accounts(:org_p);

-- Seeded as postgres (no session): the caps do not count the furniture.
-- The free shop already has its three staff accounts.
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:org_f, :owner_f, 'owner',    'org', :org_f, 'full'),
    (:org_f, :staff1,  'employee', 'org', :org_f, 'full'),
    (:org_f, :staff2,  'employee', 'org', :org_f, 'full'),
    (:org_f, :staff3,  'employee', 'org', :org_f, 'full'),
    (:org_p, :owner_p, 'owner',    'org', :org_p, 'full'),
    (:org_p, :clerk_p, 'employee', 'org', :org_p, 'full'),
    (:org_p, :staff1,  'employee', 'org', :org_p, 'full'),
    (:org_p, :staff2,  'employee', 'org', :org_p, 'full'),
    (:org_p, :staff3,  'employee', 'org', :org_p, 'full');

-- The Pro shop's owner hid the tontines from clerks: the dial must still win.
insert into org_feature_rules (org_id, tier, feature, access)
values (:org_p, 'employee', 'tontines', 'hidden');

-- One paid person in each shop, to record a shift for.
insert into employees (id, org_id, full_name, kind, hourly_rate) values
    ('38eeeeee-0000-0000-0000-000000000001', :org_f, 'Aide libre', 'casual', 500),
    ('38eeeeee-0000-0000-0000-000000000002', :org_p, 'Aide pro',   'casual', 500);


\echo ''
\echo '--- TEST 1: Free reads view on a Pro tool and edit elsewhere; Pro reads edit; the platform is never gated ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000002';
do $$
begin
    if feature_access('38000000-0000-0000-0000-000000000001', 'analytics') <> 'view' then
        raise exception 'FAIL: a Free owner reads % on analytics', feature_access('38000000-0000-0000-0000-000000000001', 'analytics');
    end if;
    if feature_access('38000000-0000-0000-0000-000000000001', 'payroll') <> 'view'
       or feature_access('38000000-0000-0000-0000-000000000001', 'tontines') <> 'view' then
        raise exception 'FAIL: payroll or tontines is not view on Free';
    end if;
    if feature_access('38000000-0000-0000-0000-000000000001', 'products') <> 'edit'
       or feature_access('38000000-0000-0000-0000-000000000001', 'credits') <> 'edit'
       or feature_access('38000000-0000-0000-0000-000000000001', 'invoices') <> 'edit' then
        raise exception 'FAIL: a free tool was lowered on a Free business';
    end if;
    if not pro_locked('38000000-0000-0000-0000-000000000001', 'analytics')
       or pro_locked('38000000-0000-0000-0000-000000000001', 'products') then
        raise exception 'FAIL: pro_locked() disagrees with feature_access()';
    end if;
end $$;
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000003';
do $$
begin
    if feature_access('38000000-0000-0000-0000-000000000002', 'analytics') <> 'edit'
       or feature_access('38000000-0000-0000-0000-000000000002', 'payroll') <> 'edit' then
        raise exception 'FAIL: a Pro owner is gated';
    end if;
    if pro_locked('38000000-0000-0000-0000-000000000002', 'analytics') then
        raise exception 'FAIL: pro_locked() on a Pro business';
    end if;
end $$;
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000001';
do $$
begin
    if feature_access('38000000-0000-0000-0000-000000000001', 'analytics') <> 'edit'
       or pro_locked('38000000-0000-0000-0000-000000000001', 'analytics') then
        raise exception 'FAIL: the platform admin is gated on a Free business';
    end if;
    raise notice 'PASS: Free = view on Pro tools and edit elsewhere; Pro = edit; platform = edit';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: the dial still wins below the plan ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000004';
do $$
begin
    if feature_access('38000000-0000-0000-0000-000000000002', 'tontines') <> 'hidden' then
        raise exception 'FAIL: a clerk hidden from tontines by the dial reads %',
            feature_access('38000000-0000-0000-0000-000000000002', 'tontines');
    end if;
    -- And a tool the dial left alone is edit on Pro for the clerk too.
    if feature_access('38000000-0000-0000-0000-000000000002', 'payroll') <> 'edit' then
        raise exception 'FAIL: the Pro clerk lost payroll';
    end if;
    raise notice 'PASS: hidden stays hidden on Pro; the rest is edit';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: the fourth staff account is refused on Free, accepted on Pro ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000002';
do $$
begin
    begin
        insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
        values ('38000000-0000-0000-0000-000000000001', '38383838-0000-0000-0000-000000000008',
                'employee', 'org', '38000000-0000-0000-0000-000000000001', 'full');
        raise exception 'FAIL: a fourth staff account was added on Free';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like 'Kaj Pro :%' then
            raise exception 'FAIL: the refusal does not open the door to pay — %', sqlerrm;
        end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000003';
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
values ('38000000-0000-0000-0000-000000000002', '38383838-0000-0000-0000-000000000008',
        'employee', 'org', '38000000-0000-0000-0000-000000000002', 'full');
do $$
declare v int;
begin
    select count(*) into v from memberships
     where org_id = '38000000-0000-0000-0000-000000000002' and role <> 'owner';
    if v <> 5 then
        raise exception 'FAIL: the Pro shop has % staff accounts, expected 5', v;
    end if;
    raise notice 'PASS: Free refused the fourth account with a Kaj Pro message; Pro took its fifth';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the invoice and photo caps, lowered for the test by the platform ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000001';
select set_platform_setting('free_max_invoices_month', '2');
select set_platform_setting('free_max_photos', '1');
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000002';
do $$
declare v_lines jsonb := '[{"description": "Sucre", "quantity": 1, "unit_price": 750}]';
begin
    perform create_invoice('38000000-0000-0000-0000-000000000001', 'Awa', v_lines);
    perform create_invoice('38000000-0000-0000-0000-000000000001', 'Bintou', v_lines);
    begin
        perform create_invoice('38000000-0000-0000-0000-000000000001', 'Coumba', v_lines);
        raise exception 'FAIL: a third invoice this month was raised on Free';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like 'Kaj Pro :%' then
            raise exception 'FAIL: the invoice refusal is not a Kaj Pro message — %', sqlerrm;
        end if;
    end;
    perform record_document('38000000-0000-0000-0000-000000000001',
        'org/38000000-0000-0000-0000-000000000001/one.jpg', 'photo');
    begin
        perform record_document('38000000-0000-0000-0000-000000000001',
            'org/38000000-0000-0000-0000-000000000001/two.jpg', 'photo');
        raise exception 'FAIL: a second photo was kept past the cap on Free';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like 'Kaj Pro :%' then
            raise exception 'FAIL: the photo refusal is not a Kaj Pro message — %', sqlerrm;
        end if;
    end;
end $$;
-- The Pro shop, under the same lowered caps, is not counted.
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000003';
do $$
declare v_lines jsonb := '[{"description": "Sucre", "quantity": 1, "unit_price": 750}]';
begin
    perform create_invoice('38000000-0000-0000-0000-000000000002', 'Awa', v_lines);
    perform create_invoice('38000000-0000-0000-0000-000000000002', 'Bintou', v_lines);
    perform create_invoice('38000000-0000-0000-0000-000000000002', 'Coumba', v_lines);
    perform record_document('38000000-0000-0000-0000-000000000002',
        'org/38000000-0000-0000-0000-000000000002/one.jpg', 'photo');
    perform record_document('38000000-0000-0000-0000-000000000002',
        'org/38000000-0000-0000-0000-000000000002/two.jpg', 'photo');
    raise notice 'PASS: Free stopped at 2 invoices and 1 photo; Pro went on';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: a shift, a tontine, a rate and a dial change are refused on Free, allowed on Pro ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000002';
do $$
declare v_rows int;
begin
    begin
        perform record_shift('38000000-0000-0000-0000-000000000001',
                             '38eeeeee-0000-0000-0000-000000000001', 4);
        raise exception 'FAIL: a shift was recorded on Free';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like 'Kaj Pro :%' then
            raise exception 'FAIL: the shift refusal is not a Kaj Pro message — %', sqlerrm;
        end if;
    end;
    begin
        insert into tontines (org_id, name, amount, created_by)
        values ('38000000-0000-0000-0000-000000000001', 'Tontine du marché', 1000,
                '38383838-0000-0000-0000-000000000002');
        raise exception 'FAIL: a tontine was opened on Free';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like 'Kaj Pro :%' then
            raise exception 'FAIL: the tontine refusal is not a Kaj Pro message — %', sqlerrm;
        end if;
    end;
    -- Policies refuse silently or with 42501; either way no row lands.
    begin
        insert into org_currency_rates (org_id, currency, rate)
        values ('38000000-0000-0000-0000-000000000001', 'EUR', 655.957);
    exception when insufficient_privilege then null;
    end;
    select count(*) into v_rows from org_currency_rates
     where org_id = '38000000-0000-0000-0000-000000000001';
    if v_rows <> 0 then
        raise exception 'FAIL: a Free owner set a currency rate';
    end if;
    begin
        insert into org_feature_rules (org_id, tier, feature, access)
        values ('38000000-0000-0000-0000-000000000001', 'employee', 'products', 'view');
    exception when insufficient_privilege then null;
    end;
    select count(*) into v_rows from org_feature_rules
     where org_id = '38000000-0000-0000-0000-000000000001';
    if v_rows <> 0 then
        raise exception 'FAIL: a Free owner changed the dial';
    end if;
end $$;
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000003';
do $$
declare v_rows int;
begin
    perform record_shift('38000000-0000-0000-0000-000000000002',
                         '38eeeeee-0000-0000-0000-000000000002', 4);
    insert into tontines (org_id, name, amount, created_by)
    values ('38000000-0000-0000-0000-000000000002', 'Tontine du marché', 1000,
            '38383838-0000-0000-0000-000000000003');
    insert into org_currency_rates (org_id, currency, rate)
    values ('38000000-0000-0000-0000-000000000002', 'EUR', 655.957);
    insert into org_feature_rules (org_id, tier, feature, access)
    values ('38000000-0000-0000-0000-000000000002', 'employee', 'products', 'view');
    select count(*) into v_rows from tontines where org_id = '38000000-0000-0000-0000-000000000002';
    if v_rows <> 1 then
        raise exception 'FAIL: the Pro owner could not open a tontine';
    end if;
    raise notice 'PASS: Free refused all four with the door to pay; Pro did all four';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: a lapsed Pro reads view again and loses nothing ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000003';
insert into tontines (org_id, name, amount, created_by)
values ('38000000-0000-0000-0000-000000000002', 'Tontine des femmes', 2000,
        '38383838-0000-0000-0000-000000000003');
insert into org_currency_rates (org_id, currency, rate)
values ('38000000-0000-0000-0000-000000000002', 'USD', 600);
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000001';
select set_org_plan('38000000-0000-0000-0000-000000000002', 'pro', current_date - 1, 'échu');
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000003';
do $$
declare v_t int; v_r int; v_rate numeric;
begin
    if feature_access('38000000-0000-0000-0000-000000000002', 'tontines') <> 'view' then
        raise exception 'FAIL: a lapsed Pro still reads edit on tontines';
    end if;
    select count(*) into v_t from tontines where org_id = '38000000-0000-0000-0000-000000000002';
    select count(*), max(rate) into v_r, v_rate from org_currency_rates
     where org_id = '38000000-0000-0000-0000-000000000002';
    if v_t <> 1 or v_r <> 1 or v_rate <> 600 then
        raise exception 'FAIL: lapsing lost rows (tontines %, rates %)', v_t, v_r;
    end if;
    -- The rate still applies (readable), it just cannot be changed.
    begin
        update org_currency_rates set rate = 610
         where org_id = '38000000-0000-0000-0000-000000000002' and currency = 'USD';
    exception when insufficient_privilege then null;
    end;
    select max(rate) into v_rate from org_currency_rates
     where org_id = '38000000-0000-0000-0000-000000000002';
    if v_rate <> 600 then
        raise exception 'FAIL: a lapsed Pro changed a rate';
    end if;
    raise notice 'PASS: lapsed reads view, keeps its tontine and its rate, cannot change the rate';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: "J''ai payé" lands once per business; the platform lists and handles it ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000005';
do $$
begin
    begin
        perform request_pro('38000000-0000-0000-0000-000000000001', 25000, 'Wave fait');
        raise exception 'FAIL: an employee requested Pro for the business';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000002';
do $$
declare v_a uuid; v_b uuid; v_rows int;
begin
    v_a := request_pro('38000000-0000-0000-0000-000000000001', 25000, '  Wave fait  ');
    v_b := request_pro('38000000-0000-0000-0000-000000000001', null, null);
    if v_a <> v_b then
        raise exception 'FAIL: tapping twice queued two requests';
    end if;
    select count(*) into v_rows from plan_requests
     where org_id = '38000000-0000-0000-0000-000000000001';
    if v_rows <> 1 then
        raise exception 'FAIL: % request rows for one business', v_rows;
    end if;
    -- Nobody outside the platform lists them.
    select count(*) into v_rows from plan_requests_open();
    if v_rows <> 0 then
        raise exception 'FAIL: an owner read the platform''s request list';
    end if;
end $$;
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000001';
do $$
declare v_id uuid; v_name text; v_amount numeric; v_note text; v_by text; v_rows int;
begin
    select id, org_name, amount, note, requested_by
      into v_id, v_name, v_amount, v_note, v_by
      from plan_requests_open();
    if v_name <> 'Boutique Libre' or v_amount <> 25000 or v_note <> 'Wave fait'
       or v_by <> 'Patronne Libre' then
        raise exception 'FAIL: the open request reads % / % / % / %', v_name, v_amount, v_note, v_by;
    end if;
    perform handle_plan_request(v_id);
    select count(*) into v_rows from plan_requests_open();
    if v_rows <> 0 then
        raise exception 'FAIL: a handled request is still open';
    end if;
    raise notice 'PASS: employee refused; one request per business; the platform read it and closed it';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: plan_terms() says the line and the price ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '38383838-0000-0000-0000-000000000002';
do $$
declare v jsonb := plan_terms();
begin
    if not (v -> 'pro_features') ? 'analytics' or (v ->> 'free_max_staff')::int <> 3
       or (v ->> 'pro_price_month')::int <> 2500 or (v ->> 'pro_price_year')::int <> 25000 then
        raise exception 'FAIL: plan_terms() reads %', v;
    end if;
    raise notice 'PASS: plan_terms carries the Pro list, the caps and the prices';
end $$;
rollback;

\echo ''
\echo 'test_pro_gates.sql: all tests passed'
