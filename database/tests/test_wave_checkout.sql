-- ============================================================
-- test_wave_checkout.sql — Wave checkout and the shop's payout (076).
-- Phone block 47.
--
-- The claims: nothing starts while the platform's switch is off; the
-- amount is the database's, for the caller's own order only, never twice
-- once paid, never for a shop with no payout number; a settled order is
-- paid, owes the shop its payout less the share, and a second delivery of
-- the webhook asks for nothing more; Kaj Pro and a spot paid by Wave
-- activate themselves; a failed payout is queued again; the console sees
-- it; and none of the Worker's functions answer an app user.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''47474747-0000-0000-0000-000000000001'''
\set buyer '''47474747-0000-0000-0000-000000000002'''
\set other '''47474747-0000-0000-0000-000000000003'''
\set plat  '''47474747-0000-0000-0000-000000000004'''
\set shop  '''47000000-0000-0000-0000-000000000001'''
\set bare  '''47000000-0000-0000-0000-000000000002'''
\set o1    '''47aaaaaa-0000-0000-0000-000000000001'''
\set o2    '''47aaaaaa-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22647000001', '{"full_name": "Propriétaire"}'),
    (:buyer, '+22647000002', '{"full_name": "Cliente"}'),
    (:other, '+22647000003', '{"full_name": "Autre"}'),
    (:plat,  '+22647000004', '{"full_name": "Plateforme"}');
update profiles set is_platform_admin = true where id = :plat;
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled) values
    (:shop, 'Boutique Wave', 'wave-47', 'retail', 'XOF', true),
    (:bare, 'Boutique Sans', 'sans-47', 'retail', 'XOF', true);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop, :owner, 'owner', 'org', :shop, 'full'),
    (:bare, :owner, 'owner', 'org', :bare, 'full');
insert into orders (id, org_id, customer_id, customer_name, status, fulfilment, total, currency) values
    (:o1, :shop, :buyer, 'Cliente', 'accepted', 'pickup', 5000, 'XOF'),
    (:o2, :bare, :buyer, 'Cliente', 'accepted', 'pickup', 3000, 'XOF');


\echo ''
\echo '--- TEST 1: off until the platform says so; the shop sets its number ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '47474747-0000-0000-0000-000000000002';
do $$ begin
    perform wave_begin('order', '47aaaaaa-0000-0000-0000-000000000001');
    raise exception 'FAIL: a payment began with Wave switched off';
exception when others then
    if sqlerrm not like 'Le paiement Wave n''est pas encore ouvert%' then raise; end if;
end $$;
set local "request.jwt.claim.sub" = '47474747-0000-0000-0000-000000000001';
select set_wave_payout_number(:shop, '70 47 00 01');
do $$ begin
    if (select wave_payout_number from orgs where id = '47000000-0000-0000-0000-000000000001')
       <> '+22670470001' then
        raise exception 'FAIL: the payout number was not normalised';
    end if;
    raise notice 'PASS: switched off by default; the owner''s number kept as +226…';
end $$;
rollback;

-- From here on: switched on, the shop has a number and a merchant id, 10 %.
update platform_settings set value = 'true' where key = 'wave_checkout';
update platform_settings set value = '10'   where key = 'wave_commission_pct';
-- Kaj's checkout for an order is Kaj Pro since 081: this shop is Pro.
update orgs set plan = 'pro' where id = :shop;
update orgs set wave_payout_number = '+22670470001', wave_merchant_ref = 'am-47'
 where id = :shop;

\echo ''
\echo '--- TEST 2: the amount is the database''s, the order the caller''s own ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '47474747-0000-0000-0000-000000000003';
do $$ begin
    perform wave_begin('order', '47aaaaaa-0000-0000-0000-000000000001');
    raise exception 'FAIL: a stranger began paying someone''s order';
exception when others then
    if sqlerrm not like 'Commande introuvable%' then raise; end if;
end $$;
set local "request.jwt.claim.sub" = '47474747-0000-0000-0000-000000000002';
do $$
declare b jsonb;
begin
    begin
        perform wave_begin('order', '47aaaaaa-0000-0000-0000-000000000002');
        raise exception 'FAIL: an order of a shop with no payout number began';
    exception when others then
        if sqlerrm not like 'Cette boutique ne reçoit pas encore%' then raise; end if;
    end;
    b := wave_begin('order', '47aaaaaa-0000-0000-0000-000000000001', 'card');
    if (b ->> 'amount')::numeric <> 5000 or b ->> 'aggregated_merchant_id' <> 'am-47' then
        raise exception 'FAIL: the session would be %', b;
    end if;
    if (select commission from wave_payments where id = (b ->> 'payment_id')::uuid) <> 500 then
        raise exception 'FAIL: the platform''s 10 %% share is not fixed at the start';
    end if;
    raise notice 'PASS: own order only, shop must be ready, 5000 F with a 500 F share';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: settled once: paid, payout owed, a second webhook asks nothing ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '47474747-0000-0000-0000-000000000002';
create temp table t_pay on commit drop as
select (wave_begin('order', :o1) ->> 'payment_id')::uuid as id;
reset role;
select wave_attach((select id from t_pay), 'cos-47', 'https://pay.wave.com/c/cos-47');
do $$
declare p jsonb;
begin
    p := wave_settle((select id from t_pay), 'cos-47', true, 'T47');
    if (p ->> 'amount')::numeric <> 4500 or p ->> 'mobile' <> '+22670470001' then
        raise exception 'FAIL: the payout asked is %', p;
    end if;
    if (select paid_at from orders where id = '47aaaaaa-0000-0000-0000-000000000001') is null then
        raise exception 'FAIL: the order is not paid';
    end if;
    if wave_settle((select id from t_pay), 'cos-47', true, 'T47') is not null then
        raise exception 'FAIL: a second delivery asked for a second payout';
    end if;
    if wave_settle((select id from t_pay), 'cos-other', true, 'T47') is not null then
        raise exception 'FAIL: a webhook for another session was believed';
    end if;
    perform wave_payout_done((select id from t_pay), false, null, 'timeout');
    if not exists (select 1 from wave_payout_queue() where payment_id = (select id from t_pay)) then
        raise exception 'FAIL: the failed payout is not queued again';
    end if;
    perform wave_payout_done((select id from t_pay), true, 'po-47');
    if exists (select 1 from wave_payout_queue() where payment_id = (select id from t_pay)) then
        raise exception 'FAIL: a sent payout is still queued';
    end if;
    raise notice 'PASS: paid, 4500 F to the shop, once; a failed payout retried';
end $$;
set local role authenticated;
set local "request.jwt.claim.sub" = '47474747-0000-0000-0000-000000000002';
do $$ begin
    if (select my_wave_payment((select id from t_pay)) ->> 'status') <> 'succeeded' then
        raise exception 'FAIL: the shopper does not read the payment as succeeded';
    end if;
    begin
        perform wave_begin('order', '47aaaaaa-0000-0000-0000-000000000001');
        raise exception 'FAIL: a paid order began again';
    exception when others then
        if sqlerrm not like 'Cette commande est déjà payée%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '47474747-0000-0000-0000-000000000004';
do $$ begin
    if (select payout_status from platform_wave_payments() limit 1) <> 'sent' then
        raise exception 'FAIL: the console does not see the payout';
    end if;
    raise notice 'PASS: shopper sees it paid, cannot pay twice; console sees the payout';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: Kaj Pro and a spot paid by Wave activate themselves ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '47474747-0000-0000-0000-000000000001';
create temp table t_pro on commit drop as
select (wave_begin('pro', :shop, 'wave', 'year') ->> 'payment_id')::uuid as id;
reset role;
insert into promotions (id, org_id, kind, days, price, status)
values ('47bbbbbb-0000-0000-0000-000000000001', :shop, 'shop', 7, 2500, 'requested');
set local role authenticated;
set local "request.jwt.claim.sub" = '47474747-0000-0000-0000-000000000001';
create temp table t_spot on commit drop as
select (wave_begin('spot', '47bbbbbb-0000-0000-0000-000000000001') ->> 'payment_id')::uuid as id;
reset role;
do $$ begin
    if (select amount from wave_payments where id = (select id from t_pro)) <> 25000 then
        raise exception 'FAIL: a year of Pro is not 25 000 F';
    end if;
    if wave_settle((select id from t_pro), null, true, 'TP') is not null then
        raise exception 'FAIL: Kaj Pro asked for a payout to the shop';
    end if;
    if (select plan || ':' || (plan_until >= current_date + 360)::text from orgs
         where id = '47000000-0000-0000-0000-000000000001') <> 'pro:true' then
        raise exception 'FAIL: Pro is not active for a year';
    end if;
    perform wave_settle((select id from t_spot), null, true, 'TS');
    if (select status from promotions where id = '47bbbbbb-0000-0000-0000-000000000001') <> 'approved' then
        raise exception 'FAIL: the paid spot is not approved';
    end if;
    raise notice 'PASS: Pro a year, spot approved, no payout asked for Kaj''s own money';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: the Worker''s functions answer no app user ---'
-- Every suite grants all functions to authenticated, as Supabase's default
-- privileges do to a new function. Hand the Worker's four to both app
-- roles on purpose, then apply 076 again (it is idempotent): what is
-- checked is that the migration itself takes them back. An earlier version
-- of this test revoked them by hand first, and so hid that it did not.
grant execute on function wave_settle(uuid, text, boolean, text)      to authenticated, anon;
grant execute on function wave_payout_queue()                         to authenticated, anon;
grant execute on function wave_attach(uuid, text, text)               to authenticated, anon;
grant execute on function wave_payout_done(uuid, boolean, text, text) to authenticated, anon;
\ir ../migrations/076_wave_checkout.sql
-- 076 re-applied puts back its own wave_terms(); the later migrations that
-- redefine it are applied again after it, so the suites that follow see
-- the database as it really is.
\ir ../migrations/081_delivery_pro.sql
do $$ begin
    if has_function_privilege('anon', 'wave_settle(uuid, text, boolean, text)', 'execute') then
        raise exception 'FAIL: the signed-out street can settle a payment';
    end if;
    if has_function_privilege('authenticated', 'wave_settle(uuid, text, boolean, text)', 'execute')
       or has_function_privilege('authenticated', 'wave_payout_queue()', 'execute')
       or has_function_privilege('authenticated', 'wave_attach(uuid, text, text)', 'execute')
       or has_function_privilege('authenticated', 'wave_payout_done(uuid, boolean, text, text)', 'execute') then
        raise exception 'FAIL: an app user can settle or read payouts';
    end if;
    raise notice 'PASS: settle, attach and the payout queue are the Worker''s alone';
end $$;

update platform_settings set value = 'false' where key = 'wave_checkout';
update platform_settings set value = '0'     where key = 'wave_commission_pct';

\echo ''
\echo 'test_wave_checkout: all passed'
