-- ============================================================
-- test_wave_payment.sql — the Wave prep of 037.
--
-- Phone block 15. What matters:
--   1. An owner sets the business's Wave handle; a stranger cannot.
--   2. A sale paid by Wave books its money to mobile money, not a stray "wave"
--      account, and attach_wave_payment stamps the sender name and confirms it.
--   3. attach_wave_payment refuses a caller who cannot write the sale's org, so
--      one business can never confirm payment on another's sale.
--
-- The shop is inserted directly with a fixed id (15000000-...) and seeded.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''15151515-0000-0000-0000-000000000001'''
\set clerk    '''15151515-0000-0000-0000-000000000002'''
\set stranger '''15151515-0000-0000-0000-000000000003'''
\set org      '''15000000-0000-0000-0000-000000000001'''
\set other    '''15000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22615000001', '{"full_name": "Patronne"}'),
    (:clerk,    '+22615000002', '{"full_name": "Vendeuse"}'),
    (:stranger, '+22615000003', '{"full_name": "Voisin"}');

-- Two shops: the one under test, and another the stranger owns.
insert into orgs (id, name, slug, profile, default_currency) values
    (:org,   'Boutique Wave',  'boutique-wave-15',  'retail', 'XOF'),
    (:other, 'Boutique Voisin','boutique-voisin-15','retail', 'XOF');
select seed_retail_accounts(:org);
select seed_retail_accounts(:other);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:org,   :owner,    'owner',    'org', :org,   'full'),
    (:org,   :clerk,    'employee', 'org', :org,   'summary'),
    (:other, :stranger, 'owner',    'org', :other, 'full');


\echo ''
\echo '--- TEST 1: the owner sets the Wave handle, a stranger cannot ---'
begin;
set local "request.jwt.claim.sub" = '15151515-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_merchant text;
begin
    perform set_org_wave('15000000-0000-0000-0000-000000000001', '  +226 70 00 00 00  ');
    select wave_merchant into v_merchant from orgs
     where id = '15000000-0000-0000-0000-000000000001';
    if v_merchant <> '+226 70 00 00 00' then
        raise exception 'FAIL: wave_merchant is % (want trimmed number)', v_merchant;
    end if;
    raise notice 'PASS: owner set the Wave handle';
end $$;
rollback;

begin;
set local "request.jwt.claim.sub" = '15151515-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_raised boolean := false;
begin
    begin
        perform set_org_wave('15000000-0000-0000-0000-000000000001', '+22677777777');
    exception when others then v_raised := true;
    end;
    if not v_raised then
        raise exception 'FAIL: a stranger set another business''s Wave handle';
    end if;
    raise notice 'PASS: the stranger is refused';
end $$;
rollback;


\echo ''
\echo '--- TEST 2: a Wave sale books to mobile money and carries the sender ---'
begin;
set local "request.jwt.claim.sub" = '15151515-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_prod uuid; v_sale uuid; v_mm numeric; v_sender text; v_status text; v_method text;
begin
    v_prod := ensure_product('15000000-0000-0000-0000-000000000001', 'Savon', 500, 300);
    perform receive_products('15000000-0000-0000-0000-000000000001', v_prod, 10, 300);

    v_sale := record_sale('15000000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', v_prod, 'quantity', 2, 'unit_price', 500)),
        'wave');

    -- The 1 000 lands in Mobile Money (1020), the account Wave routes to.
    select coalesce(sum(jl.debit), 0) into v_mm
    from journal_lines jl
    join accounts a on a.id = jl.account_id
    where a.org_id = '15000000-0000-0000-0000-000000000001' and a.code = '1020';
    if v_mm <> 1000 then
        raise exception 'FAIL: Wave sale booked % to mobile money (want 1000)', v_mm;
    end if;

    select method into v_method from sales where id = v_sale;
    if v_method <> 'wave' then
        raise exception 'FAIL: sale method is % (want wave)', v_method;
    end if;

    -- The signal-later step, done by hand today: stamp the sender and confirm.
    perform attach_wave_payment(v_sale, '  Awa Traoré  ', 'TXN-123');
    select wave_sender, payment_status into v_sender, v_status
    from sales where id = v_sale;
    if v_sender <> 'Awa Traoré' then
        raise exception 'FAIL: wave_sender is % (want Awa Traoré)', v_sender;
    end if;
    if v_status <> 'confirmed' then
        raise exception 'FAIL: payment_status is % (want confirmed)', v_status;
    end if;

    raise notice 'PASS: Wave sale to mobile money, sender Awa Traoré, confirmed';
end $$;
rollback;


\echo ''
\echo '--- TEST 3: no one confirms another business''s sale ---'
begin;
set local "request.jwt.claim.sub" = '15151515-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_prod uuid; v_sale uuid;
begin
    v_prod := ensure_product('15000000-0000-0000-0000-000000000001', 'Sel', 200, 100);
    perform receive_products('15000000-0000-0000-0000-000000000001', v_prod, 5, 100);
    v_sale := record_sale('15000000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', v_prod, 'quantity', 1, 'unit_price', 200)),
        'wave');
    -- Hand the sale id to the stranger via a temp table across the role switch.
    create temp table _wave_sale(id uuid) on commit drop;
    insert into _wave_sale values (v_sale);
end $$;

set local "request.jwt.claim.sub" = '15151515-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_sale uuid; v_raised boolean := false;
begin
    select id into v_sale from _wave_sale;
    begin
        perform attach_wave_payment(v_sale, 'Imposteur', 'TXN-999');
    exception when others then v_raised := true;
    end;
    if not v_raised then
        raise exception 'FAIL: a stranger confirmed another business''s Wave sale';
    end if;
    raise notice 'PASS: the stranger cannot confirm this sale';
end $$;
rollback;

\echo ''
\echo '=== test_wave_payment.sql: all checks passed ==='
