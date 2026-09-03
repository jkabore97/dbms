-- ============================================================
-- test_order_payments.sql — how an order is paid, and who says so (057).
-- Phone block 30.
--
-- The claims: cash is the default; Wave can only be chosen at a shop that
-- set its merchant link; the shop — and only the shop — says a payment
-- arrived, can unsay a mis-tap, and the customer's bell rings when it is
-- confirmed; the customer's order carries the shop's Wave link to pay
-- with; and the courier's card says what is already paid so nothing is
-- collected twice.
-- ============================================================
\set ON_ERROR_STOP on

\set owner_a   '''30303030-0000-0000-0000-000000000001'''
\set customer  '''30303030-0000-0000-0000-000000000002'''
\set moto1     '''30303030-0000-0000-0000-000000000003'''
\set shop_a    '''30000000-0000-0000-0000-000000000001'''
\set shop_b    '''30000000-0000-0000-0000-000000000002'''
\set p_riz     '''30aaaaaa-0000-0000-0000-000000000001'''
\set p_lait    '''30aaaaaa-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner_a,  '+22630000001', '{"full_name": "Esperance"}'),
    (:customer, '+22630000002', '{"full_name": "Awa Client"}'),
    (:moto1,    '+22630000003', '{"full_name": "Moussa Moto"}');

-- A takes Wave; B does not.
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, wave_merchant) values
    (:shop_a, 'Boutique Esperance', 'paiement-a-30', 'retail', 'XOF', true,
              'https://pay.wave.com/m/esperance'),
    (:shop_b, 'Boutique Sans Wave', 'paiement-b-30', 'retail', 'XOF', true, null);
select seed_retail_accounts(:shop_a);
select seed_retail_accounts(:shop_b);

insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop_a, :owner_a, 'owner', 'org', :shop_a, 'full'),
    (:shop_b, :owner_a, 'owner', 'org', :shop_b, 'full');

insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published, created_by) values
    (:p_riz,  :shop_a, 'Riz parfumé 25kg', 17500, 15000, 4, true, true, :owner_a),
    (:p_lait, :shop_b, 'Lait Nido',         3200,  2800, 2, true, true, :owner_a);

insert into couriers (user_id, phone, status) values
    (:moto1, '+22630000003', 'approved');

\echo ''
\echo '--- TEST 1: cash is the default; Wave only where the shop takes it ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :customer;
do $$
declare v_id uuid; v_method text; v_paid timestamptz;
begin
    v_id := place_order('paiement-a-30',
        '[{"product_id":"30aaaaaa-0000-0000-0000-000000000001","quantity":1}]'::jsonb);
    select payment_method, paid_at into v_method, v_paid from orders where id = v_id;
    if v_method <> 'cash' or v_paid is not null then
        raise exception 'FAIL: a plain order is % / paid %', v_method, v_paid;
    end if;
    begin
        perform place_order('paiement-b-30',
            '[{"product_id":"30aaaaaa-0000-0000-0000-000000000002","quantity":1}]'::jsonb,
            'pickup', null, null, null, 'wave');
        raise exception 'FAIL: Wave was accepted at a shop without Wave';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: no Wave at Sans Wave — %', sqlerrm;
    end;
    begin
        perform place_order('paiement-a-30',
            '[{"product_id":"30aaaaaa-0000-0000-0000-000000000001","quantity":1}]'::jsonb,
            'pickup', null, null, null, 'mattress');
        raise exception 'FAIL: an unknown method was accepted';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: cash by default, unknown methods refused — %', sqlerrm;
    end;
end $$;
rollback;

-- A Wave delivery order, kept: the rest of the suite follows it.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :customer;
do $$
declare v_wave text; v_method text;
begin
    perform place_order('paiement-a-30',
        '[{"product_id":"30aaaaaa-0000-0000-0000-000000000001","quantity":2}]'::jsonb,
        'delivery', null, 'Dassasgho', '+22670000030', 'wave');
    select m.payment_method, m.shop_wave into v_method, v_wave
      from my_orders() m limit 1;
    if v_method <> 'wave' or v_wave <> 'https://pay.wave.com/m/esperance' then
        raise exception 'FAIL: the customer''s order says % / %', v_method, v_wave;
    end if;
    raise notice 'PASS: a Wave order carries the shop''s Wave link to pay with';
end $$;
commit;

\echo ''
\echo '--- TEST 2: only the shop says the money arrived, and can unsay it ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :customer;
do $$
declare v_id uuid;
begin
    select id into v_id from orders where customer_id = '30303030-0000-0000-0000-000000000002';
    begin
        perform set_order_paid(v_id, true);
        raise exception 'FAIL: the customer confirmed their own payment';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: a claim is not a confirmation — %', sqlerrm;
    end;
end $$;
set local "request.jwt.claim.sub" = :owner_a;
do $$
declare v_id uuid; v_paid timestamptz;
begin
    select id into v_id from orders where org_id = '30000000-0000-0000-0000-000000000001';
    perform set_order_paid(v_id, true);
    select paid_at into v_paid from orders where id = v_id;
    if v_paid is null then raise exception 'FAIL: confirmed but not paid'; end if;
    perform set_order_paid(v_id, false);
    select paid_at into v_paid from orders where id = v_id;
    if v_paid is not null then raise exception 'FAIL: a mis-tap is forever'; end if;
    perform set_order_paid(v_id, true);
    raise notice 'PASS: the shop confirms, can unsay a mis-tap, and confirms again';
end $$;
set local "request.jwt.claim.sub" = :customer;
do $$
declare v_bells int; v_paid timestamptz;
begin
    select count(*) into v_bells from notifications
     where recipient_id = '30303030-0000-0000-0000-000000000002' and kind = 'order_paid';
    if v_bells < 1 then
        raise exception 'FAIL: the customer was never told the payment was confirmed';
    end if;
    select m.paid_at into v_paid from my_orders() m limit 1;
    if v_paid is null then
        raise exception 'FAIL: the customer''s order does not show paid';
    end if;
    raise notice 'PASS: the customer was told and their order shows paid';
end $$;
commit;

\echo ''
\echo '--- TEST 3: the courier collects nothing that is already paid ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :owner_a;
do $$
declare v_id uuid;
begin
    select id into v_id from orders where org_id = '30000000-0000-0000-0000-000000000001';
    perform decide_order(v_id, 'accepted');
    perform decide_order(v_id, 'ready');
end $$;
set local "request.jwt.claim.sub" = :moto1;
do $$
declare v_method text; v_paid timestamptz;
begin
    select a.payment_method, a.paid_at into v_method, v_paid
      from available_deliveries() a where a.shop_name = 'Boutique Esperance';
    if v_method <> 'wave' or v_paid is null then
        raise exception 'FAIL: the board says % / paid %', v_method, v_paid;
    end if;
    perform take_delivery((select a.order_id from available_deliveries() a
                            where a.shop_name = 'Boutique Esperance'));
    select d.paid_at into v_paid from courier_deliveries() d limit 1;
    if v_paid is null then
        raise exception 'FAIL: the courier''s card forgot the payment';
    end if;
    raise notice 'PASS: the board and the courier''s card both say déjà payé';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the window says whether the shop takes Wave ---'
begin;
set local role authenticated;
do $$
declare v_wave text;
begin
    select s.wave_merchant into v_wave from storefront('paiement-a-30') s;
    if v_wave <> 'https://pay.wave.com/m/esperance' then
        raise exception 'FAIL: the window hides the Wave link (%)', v_wave;
    end if;
    select s.wave_merchant into v_wave from storefront('paiement-b-30') s;
    if v_wave is not null then
        raise exception 'FAIL: a shop without Wave shows one';
    end if;
    raise notice 'PASS: the window says Wave where Wave is taken, and not where it is not';
end $$;
rollback;

\echo ''
\echo '=== test_order_payments.sql: all checks passed ==='
