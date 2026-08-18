-- ============================================================
-- test_currency_rates.sql — the multi-currency prep of 039.
--
-- Phone block 17. What matters, in order of what it would cost to get wrong:
--   1. The books never move: a sale tendered in USD books exactly the same
--      home-currency ledger entry as a plain cash sale.
--   2. Only an admin writes rates; a plain employee and a stranger cannot,
--      though members read them (the till needs the chips).
--   3. attach_sale_tender stamps currency/amount/rate, normalizes the code,
--      refuses garbage, and refuses anyone outside the sale's business.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''17171717-0000-0000-0000-000000000001'''
\set clerk    '''17171717-0000-0000-0000-000000000002'''
\set stranger '''17171717-0000-0000-0000-000000000003'''
\set org      '''17000000-0000-0000-0000-000000000001'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22617000001', '{"full_name": "Patronne"}'),
    (:clerk,    '+22617000002', '{"full_name": "Vendeuse"}'),
    (:stranger, '+22617000003', '{"full_name": "Voisin"}');

insert into orgs (id, name, slug, profile, default_currency)
values (:org, 'Boutique Devises', 'boutique-devises-17', 'retail', 'XOF');
select seed_retail_accounts(:org);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:org, :owner, 'owner',    'org', :org, 'full'),
    (:org, :clerk, 'employee', 'org', :org, 'summary');


\echo ''
\echo '--- TEST 1: the owner sets a rate; the clerk reads it but cannot write ---'
begin;
set local "request.jwt.claim.sub" = '17171717-0000-0000-0000-000000000001';
set local role authenticated;
do $$
begin
    insert into org_currency_rates (org_id, currency, rate, updated_by)
    values ('17000000-0000-0000-0000-000000000001', 'USD', 600,
            '17171717-0000-0000-0000-000000000001');
end $$;

set local "request.jwt.claim.sub" = '17171717-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v_rate numeric; v_wrote boolean := true;
begin
    select rate into v_rate from org_currency_rates
    where org_id = '17000000-0000-0000-0000-000000000001' and currency = 'USD';
    if v_rate <> 600 then
        raise exception 'FAIL: the clerk reads rate % (want 600)', v_rate;
    end if;

    -- RLS swallows the write silently (0 rows), it must not land.
    begin
        insert into org_currency_rates (org_id, currency, rate)
        values ('17000000-0000-0000-0000-000000000001', 'GHS', 41);
        v_wrote := exists (select 1 from org_currency_rates
                           where org_id = '17000000-0000-0000-0000-000000000001'
                             and currency = 'GHS');
    exception when others then
        v_wrote := false;
    end;
    if v_wrote then
        raise exception 'FAIL: a plain employee wrote a rate';
    end if;
    raise notice 'PASS: clerk reads 600, cannot write';
end $$;

set local "request.jwt.claim.sub" = '17171717-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_count int;
begin
    select count(*) into v_count from org_currency_rates
    where org_id = '17000000-0000-0000-0000-000000000001';
    if v_count <> 0 then
        raise exception 'FAIL: a stranger reads another business''s rates';
    end if;
    raise notice 'PASS: the stranger sees no rates';
end $$;
rollback;


\echo ''
\echo '--- TEST 2: a USD-tendered sale books the same XOF ledger as cash ---'
begin;
set local "request.jwt.claim.sub" = '17171717-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_prod uuid; v_sale uuid; v_income numeric;
    v_cur text; v_amt numeric; v_rate numeric; v_total numeric;
begin
    insert into org_currency_rates (org_id, currency, rate, updated_by)
    values ('17000000-0000-0000-0000-000000000001', 'USD', 600,
            '17171717-0000-0000-0000-000000000001');

    v_prod := ensure_product('17000000-0000-0000-0000-000000000001', 'Tissu', 9000, 6000);
    perform receive_products('17000000-0000-0000-0000-000000000001', v_prod, 5, 6000);

    -- The sale is recorded in XOF exactly as always...
    v_sale := record_sale('17000000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', v_prod, 'quantity', 1, 'unit_price', 9000)),
        'cash');
    -- ...then the tender is described: the customer handed over 15 USD at 600.
    perform attach_sale_tender(v_sale, ' usd ', 15, 600);

    select total, tendered_currency, tendered_amount, tendered_rate
      into v_total, v_cur, v_amt, v_rate
      from sales where id = v_sale;
    if v_total <> 9000 then
        raise exception 'FAIL: sale total is % (want 9000 XOF)', v_total;
    end if;
    if v_cur <> 'USD' or v_amt <> 15 or v_rate <> 600 then
        raise exception 'FAIL: tender stamped as % % @ % (want USD 15 @ 600)',
            v_cur, v_amt, v_rate;
    end if;

    -- The ledger holds 9 000 XOF of income — the tender changed nothing.
    select coalesce(sum(jl.credit), 0) into v_income
    from journal_lines jl
    join accounts a on a.id = jl.account_id
    where a.org_id = '17000000-0000-0000-0000-000000000001' and a.name = 'Ventes';
    if v_income <> 9000 then
        raise exception 'FAIL: income booked % (want 9000)', v_income;
    end if;

    raise notice 'PASS: 9000 XOF booked, tender USD 15 @ 600 on the record';
end $$;
rollback;


\echo ''
\echo '--- TEST 3: garbage tenders and strangers are refused ---'
begin;
set local "request.jwt.claim.sub" = '17171717-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_prod uuid; v_sale uuid; v_raised boolean;
begin
    v_prod := ensure_product('17000000-0000-0000-0000-000000000001', 'Savon', 500, 300);
    perform receive_products('17000000-0000-0000-0000-000000000001', v_prod, 5, 300);
    v_sale := record_sale('17000000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', v_prod, 'quantity', 1, 'unit_price', 500)),
        'cash');

    v_raised := false;
    begin
        perform attach_sale_tender(v_sale, 'DOLLARS', 5, 600);
    exception when others then v_raised := true;
    end;
    if not v_raised then
        raise exception 'FAIL: a non-ISO currency was accepted';
    end if;

    v_raised := false;
    begin
        perform attach_sale_tender(v_sale, 'USD', 0, 600);
    exception when others then v_raised := true;
    end;
    if not v_raised then
        raise exception 'FAIL: a zero amount was accepted';
    end if;

    create temp table _tender_sale(id uuid) on commit drop;
    insert into _tender_sale values (v_sale);
    raise notice 'PASS: garbage currency and zero amount refused';
end $$;

set local "request.jwt.claim.sub" = '17171717-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_sale uuid; v_raised boolean := false;
begin
    select id into v_sale from _tender_sale;
    begin
        perform attach_sale_tender(v_sale, 'USD', 5, 600);
    exception when others then v_raised := true;
    end;
    if not v_raised then
        raise exception 'FAIL: a stranger stamped another business''s sale';
    end if;
    raise notice 'PASS: the stranger cannot describe this sale''s payment';
end $$;
rollback;

\echo ''
\echo '=== test_currency_rates.sql: all checks passed ==='
