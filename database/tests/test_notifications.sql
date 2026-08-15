-- ============================================================
-- test_notifications.sql — the bell.
--
-- Phone block 94. What matters: the right people hear the right events
-- and nobody else — the employee's bell stays quiet, the neighbour hears
-- nothing at all; a threshold rings on the crossing, not on every sale
-- below it; and a recipient can mark their own bell read and only theirs.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''94949494-0000-0000-0000-000000000001'''
\set clerk    '''94949494-0000-0000-0000-000000000002'''
\set stranger '''94949494-0000-0000-0000-000000000003'''
\set padmin   '''94949494-0000-0000-0000-000000000004'''
\set shop     '''94000000-0000-0000-0000-000000000001'''
\set other    '''94000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22694000001', '{"full_name": "Patronne"}'),
    (:clerk,    '+22694000002', '{"full_name": "Vendeuse"}'),
    (:stranger, '+22694000003', '{"full_name": "Voisin"}'),
    (:padmin,   '+22694000004', '{"full_name": "Israel"}');

update profiles set is_platform_admin = true
 where id = '94949494-0000-0000-0000-000000000004';

insert into orgs (id, name, slug, profile, default_currency) values
    (:shop,  'Boutique 94', 'boutique-94', 'retail', 'XOF'),
    (:other, 'Boutique 94b', 'boutique-94b', 'retail', 'XOF');

-- Owner and stranger only; the clerk joins later, as a test.
insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:shop,  :owner,    'owner', 'org', :shop),
    (:other, :stranger, 'owner', 'org', :other);

\echo ''
\echo '--- TEST 1: joining rings the admins, not the person who joined ---'
begin;
set local role postgres;
insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    ('94000000-0000-0000-0000-000000000001',
     '94949494-0000-0000-0000-000000000002', 'employee', 'org',
     '94000000-0000-0000-0000-000000000001');
commit;

begin;
set local "request.jwt.claim.sub" = '94949494-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v int;
begin
    select count(*) into v from notifications
     where kind = 'member_joined' and message like '%a rejoint Boutique 94%';
    if v <> 1 then
        raise exception 'FAIL: owner has % join notifications, expected 1', v;
    end if;
    raise notice 'PASS: the owner heard the join';
end $$;
commit;

begin;
set local "request.jwt.claim.sub" = '94949494-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v int;
begin
    select count(*) into v from notifications;
    if v <> 0 then
        raise exception 'FAIL: the new employee was notified about themselves (%)', v;
    end if;
    raise notice 'PASS: the employee''s bell is silent';
end $$;
commit;

\echo ''
\echo '--- TEST 2: stock rings on the crossing, once ---'
begin;
set local "request.jwt.claim.sub" = '94949494-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_soap uuid; v int;
begin
    v_soap := ensure_product('94000000-0000-0000-0000-000000000001'::uuid,
        'Savon', p_sale_price => 300, p_cost_price => 200);
    perform receive_products('94000000-0000-0000-0000-000000000001'::uuid,
        v_soap, 6, 200);
    update products set low_stock_at = 5 where id = v_soap;

    -- 6 -> 4 crosses the threshold of 5: one ring.
    perform record_sale('94000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_array(jsonb_build_object('product_id', v_soap,
            'name', 'Savon', 'quantity', 2, 'unit_price', 300)));
    -- 4 -> 3 stays below it: no second ring.
    perform record_sale('94000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_array(jsonb_build_object('product_id', v_soap,
            'name', 'Savon', 'quantity', 1, 'unit_price', 300)));

    select count(*) into v from notifications
     where kind = 'low_stock' and message like '%Savon%';
    if v <> 1 then
        raise exception 'FAIL: % low-stock rings, expected exactly 1', v;
    end if;
    raise notice 'PASS: one crossing, one ring';
end $$;
commit;

\echo ''
\echo '--- TEST 3: a credit fully repaid is announced; a partial one is not ---'
begin;
set local "request.jwt.claim.sub" = '94949494-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_debt uuid; v int;
begin
    v_debt := record_credit_sale('94000000-0000-0000-0000-000000000001'::uuid,
        'Awa', 1000, 'Savon');
    perform record_debt_payment(v_debt, 400);
    select count(*) into v from notifications where kind = 'debt_settled';
    if v <> 0 then
        raise exception 'FAIL: a partial repayment was announced as settled';
    end if;
    perform record_debt_payment(v_debt, 600);
    select count(*) into v from notifications
     where kind = 'debt_settled' and message like '%Awa%';
    if v <> 1 then
        raise exception 'FAIL: % settled announcements, expected 1', v;
    end if;
    raise notice 'PASS: settled once, announced once';
end $$;
commit;

\echo ''
\echo '--- TEST 4: a tontine round ready to close rings the admins ---'
begin;
set local "request.jwt.claim.sub" = '94949494-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_tontine uuid;
    v_m1 uuid; v_m2 uuid;
    v int;
begin
    insert into tontines (org_id, name, amount, period, created_by)
    values ('94000000-0000-0000-0000-000000000001', 'Marché', 1000, 'weekly',
            '94949494-0000-0000-0000-000000000001')
    returning id into v_tontine;
    insert into tontine_members (tontine_id, org_id, name, position)
    values (v_tontine, '94000000-0000-0000-0000-000000000001', 'Awa', 1)
    returning id into v_m1;
    insert into tontine_members (tontine_id, org_id, name, position)
    values (v_tontine, '94000000-0000-0000-0000-000000000001', 'Moussa', 2)
    returning id into v_m2;

    insert into tontine_contributions (tontine_id, member_id, org_id, round,
                                       amount, created_by)
    values (v_tontine, v_m1, '94000000-0000-0000-0000-000000000001', 1, 1000,
            '94949494-0000-0000-0000-000000000001');
    select count(*) into v from notifications where kind = 'tontine_ready';
    if v <> 0 then
        raise exception 'FAIL: half a round was announced as ready';
    end if;

    insert into tontine_contributions (tontine_id, member_id, org_id, round,
                                       amount, created_by)
    values (v_tontine, v_m2, '94000000-0000-0000-0000-000000000001', 1, 1000,
            '94949494-0000-0000-0000-000000000001');
    select count(*) into v from notifications
     where kind = 'tontine_ready' and message like '%Marché%tour 1%';
    if v <> 1 then
        raise exception 'FAIL: % ready announcements, expected 1', v;
    end if;
    raise notice 'PASS: the full round rang once';
end $$;
commit;

\echo ''
\echo '--- TEST 5: a business application rings the platform, not the shops ---'
begin;
set local "request.jwt.claim.sub" = '94949494-0000-0000-0000-000000000003';
set local role authenticated;
insert into org_applications (applicant_id, name, slug)
values ('94949494-0000-0000-0000-000000000003', 'Atelier 94', 'atelier-94');
commit;

begin;
set local "request.jwt.claim.sub" = '94949494-0000-0000-0000-000000000004';
set local role authenticated;
do $$
declare v int;
begin
    select count(*) into v from notifications
     where kind = 'org_application' and message like '%Atelier 94%';
    if v <> 1 then
        raise exception 'FAIL: platform admin has % application rings, expected 1', v;
    end if;
    raise notice 'PASS: the platform admin heard the application';
end $$;
commit;

begin;
set local "request.jwt.claim.sub" = '94949494-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v int;
begin
    select count(*) into v from notifications where kind = 'org_application';
    if v <> 0 then
        raise exception 'FAIL: a shop owner heard a platform application';
    end if;
    raise notice 'PASS: the shops did not';
end $$;
commit;

\echo ''
\echo '--- TEST 6: the bell is personal — reading, marking, and the wall ---'
begin;
set local "request.jwt.claim.sub" = '94949494-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v int;
begin
    select count(*) into v from notifications;
    if v <> 0 then
        raise exception 'FAIL: the neighbour reads % of another shop''s bell', v;
    end if;
    raise notice 'PASS: nothing crosses the wall';
end $$;
commit;

begin;
set local "request.jwt.claim.sub" = '94949494-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_unread int;
begin
    update notifications set read_at = now() where read_at is null;
    select count(*) into v_unread from notifications where read_at is null;
    if v_unread <> 0 then
        raise exception 'FAIL: % rows still unread after marking', v_unread;
    end if;
    raise notice 'PASS: marked read, all of them, own only by policy';
end $$;
commit;

\echo ''
\echo '=== test_notifications.sql: all assertions passed ==='
