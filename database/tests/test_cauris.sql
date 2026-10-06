-- ============================================================
-- test_cauris.sql — cauris are earned by doing well (084). Phone block 54.
--
-- The claims: a finished order earns, once, and not from the business's
-- own people, not under the smallest amount, not beyond N a customer a
-- day; a customer who comes back earns more; a quick acceptance earns; an
-- accepted order the business cancels costs, the customer's own
-- cancellation does not; distinct visitors earn, capped, members never;
-- the till kept 7 days running earns once; a farm's log earns once a day;
-- a complete vitrine and a referral that took off earn once; an idle
-- wallet expires; an association earns nothing; and the engine answers
-- nobody from an app — only the readers do, to the right people.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''54545454-0000-0000-0000-000000000001'''
\set clerk    '''54545454-0000-0000-0000-000000000002'''
\set buyer    '''54545454-0000-0000-0000-000000000003'''
\set buyer2   '''54545454-0000-0000-0000-000000000004'''
\set plat     '''54545454-0000-0000-0000-000000000005'''
\set shop     '''54000000-0000-0000-0000-000000000001'''
\set farm     '''54000000-0000-0000-0000-000000000002'''
\set church   '''54000000-0000-0000-0000-000000000003'''
\set newbie   '''54000000-0000-0000-0000-000000000004'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- The stub hands every function to everyone; 084 takes its engine back.
grant execute on all functions in schema public to authenticated, anon;
\i database/migrations/084_cauris.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,  '+22654000001', '{"full_name": "Awa"}'),
    (:clerk,  '+22654000002', '{"full_name": "Vendeur"}'),
    (:buyer,  '+22654000003', '{"full_name": "Cliente"}'),
    (:buyer2, '+22654000004', '{"full_name": "Client"}'),
    (:plat,   '+22654000005', '{"full_name": "Plateforme"}');
update profiles set is_platform_admin = true where id = :plat;
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled) values
    (:shop,   'Boutique Cauris', 'cauris-54',  'retail',      'XOF', true),
    (:farm,   'Ferme Cauris',    'ferme-54',   'farm',        'XOF', true),
    (:church, 'Église Cauris',   'eglise-54',  'association', 'XOF', false),
    (:newbie, 'Nouvelle',        'nouvelle-54','retail',      'XOF', true);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,   :owner, 'owner',    'org', :shop,   'full'),
    (:shop,   :clerk, 'employee', 'org', :shop,   'full'),
    (:farm,   :owner, 'owner',    'org', :farm,   'full'),
    (:church, :owner, 'owner',    'org', :church, 'full'),
    (:newbie, :buyer2, 'owner',   'org', :newbie, 'full');

create or replace function t54_order(p_org uuid, p_customer uuid, p_total numeric,
                                     p_ago interval default '0'::interval)
returns uuid language sql as $$
    insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency, created_at)
    values (p_org, p_customer, 'x', 'pending', 'pickup', p_total, 'XOF', now() - p_ago)
    returning id;
$$;

\echo ''
\echo '--- TEST 1: a finished order earns once; not from inside, not too small, not too often ---'
do $$
declare a uuid; b uuid; c uuid; d uuid; e uuid; bal int;
begin
    a := t54_order('54000000-0000-0000-0000-000000000001', '54545454-0000-0000-0000-000000000003', 1000, '1 hour');
    update orders set status = 'accepted' where id = a;
    update orders set status = 'picked_up' where id = a;
    -- Set again: the same order earns nothing more.
    update orders set status = 'ready' where id = a;
    update orders set status = 'picked_up' where id = a;
    if cauris_balance('54000000-0000-0000-0000-000000000001') <> 10 then
        raise exception 'FAIL: one order did not earn 10, once (%)',
            cauris_balance('54000000-0000-0000-0000-000000000001');
    end if;
    -- The clerk orders from the shop: nothing. 300 F: nothing.
    b := t54_order('54000000-0000-0000-0000-000000000001', '54545454-0000-0000-0000-000000000002', 5000, '1 hour');
    update orders set status = 'accepted' where id = b;
    update orders set status = 'picked_up' where id = b;
    c := t54_order('54000000-0000-0000-0000-000000000001', '54545454-0000-0000-0000-000000000004', 300, '1 hour');
    update orders set status = 'accepted' where id = c;
    update orders set status = 'picked_up' where id = c;
    if cauris_balance('54000000-0000-0000-0000-000000000001') <> 10 then
        raise exception 'FAIL: an inside or a small order earned';
    end if;
    -- The same customer, second and third order today: the second earns
    -- (and she came back: +15), the third does not.
    d := t54_order('54000000-0000-0000-0000-000000000001', '54545454-0000-0000-0000-000000000003', 1000, '30 minutes');
    update orders set status = 'accepted' where id = d;
    update orders set status = 'delivered' where id = d;
    e := t54_order('54000000-0000-0000-0000-000000000001', '54545454-0000-0000-0000-000000000003', 1000, '20 minutes');
    update orders set status = 'accepted' where id = e;
    update orders set status = 'picked_up' where id = e;
    bal := cauris_balance('54000000-0000-0000-0000-000000000001');
    if bal <> 10 + 10 + 15 then
        raise exception 'FAIL: per-customer cap or the return bonus is wrong (%)', bal;
    end if;
    raise notice 'PASS: 10, once; inside and small earn nothing; 2 a customer a day; +15 she came back';
end $$;

\echo ''
\echo '--- TEST 2: quick acceptance earns; a cancellation by the business costs ---'
do $$
declare q uuid; s uuid; k uuid; before int;
begin
    before := cauris_balance('54000000-0000-0000-0000-000000000001');
    q := t54_order('54000000-0000-0000-0000-000000000001', '54545454-0000-0000-0000-000000000004', 800, '5 minutes');
    update orders set status = 'accepted' where id = q;
    s := t54_order('54000000-0000-0000-0000-000000000001', '54545454-0000-0000-0000-000000000004', 800, '2 hours');
    update orders set status = 'accepted' where id = s;          -- slow: nothing
    update orders set status = 'cancelled' where id = s;          -- by the shop: -10
    -- The customer cancels her own accepted order: no cost to the shop.
    k := t54_order('54000000-0000-0000-0000-000000000001', '54545454-0000-0000-0000-000000000004', 800, '2 hours');
    update orders set status = 'accepted' where id = k;
    perform set_config('request.jwt.claim.sub', '54545454-0000-0000-0000-000000000004', true);
    update orders set status = 'cancelled' where id = k;
    perform set_config('request.jwt.claim.sub', '', true);
    if cauris_balance('54000000-0000-0000-0000-000000000001') <> before + 3 - 10 then
        raise exception 'FAIL: quick +3 / shop cancel -10 / customer cancel 0 (% → %)',
            before, cauris_balance('54000000-0000-0000-0000-000000000001');
    end if;
    raise notice 'PASS: +3 quick, -10 dropped by the shop, 0 when the customer cancels';
end $$;

\echo ''
\echo '--- TEST 3: distinct visitors earn, capped; the business''s own people never ---'
update cauris_rules set daily_cap = 3 where key = 'visitor';
begin;
set local role anon;
select record_visitor('cauris-54', 'device-aaaaaaaa');
select record_visitor('cauris-54', 'device-aaaaaaaa');   -- same device: once
select record_visitor('cauris-54', 'device-bbbbbbbb');
select record_visitor('cauris-54', 'short');             -- not an id: nothing
select record_visitor('cauris-54', 'device-cccccccc');
select record_visitor('cauris-54', 'device-dddddddd');   -- past the cap of 3
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '54545454-0000-0000-0000-000000000002';
select record_visitor('cauris-54', 'device-clerk-001');  -- a member
commit;
do $$ begin
    if (select count(*) from cauris_ledger
         where org_id = '54000000-0000-0000-0000-000000000001' and reason = 'visitor') <> 3 then
        raise exception 'FAIL: visitors are not distinct, capped and outsiders only';
    end if;
    raise notice 'PASS: 3 distinct visitors, the cap held, the clerk did not count';
end $$;
update cauris_rules set daily_cap = 30 where key = 'visitor';

\echo ''
\echo '--- TEST 4: the till 7 days running earns once; a farm''s log once a day ---'
do $$
declare f uuid; i int;
begin
    for i in 0..6 loop
        insert into sales (org_id, total, occurred_at)
        values ('54000000-0000-0000-0000-000000000001', 1000, now() - make_interval(days => i));
    end loop;
    insert into sales (org_id, total) values ('54000000-0000-0000-0000-000000000001', 500);
    if (select count(*) from cauris_ledger
         where org_id = '54000000-0000-0000-0000-000000000001' and reason = 'till_streak') <> 1 then
        raise exception 'FAIL: the 7-day till streak did not earn exactly once';
    end if;
    insert into flocks (org_id, batch_code, bird_count)
    values ('54000000-0000-0000-0000-000000000002', 'B-54', 200) returning id into f;
    insert into flock_events (flock_id, kind, quantity, created_by) values (f, 'mortality', 1, '54545454-0000-0000-0000-000000000001');
    insert into flock_events (flock_id, kind, quantity, created_by) values (f, 'weight', 1200, '54545454-0000-0000-0000-000000000001');
    if cauris_balance('54000000-0000-0000-0000-000000000002') <> 5 then
        raise exception 'FAIL: the farm''s log did not earn 5, once today';
    end if;
    raise notice 'PASS: +20 for the week''s till, +5 for the farm''s day';
end $$;

\echo ''
\echo '--- TEST 5: an association earns nothing ---'
do $$ begin
    if cauris_award('54000000-0000-0000-0000-000000000003', 'lesson', 'x') <> 0
       or cauris_balance('54000000-0000-0000-0000-000000000003') <> 0 then
        raise exception 'FAIL: an association earned cauris';
    end if;
    raise notice 'PASS: no cauris for an association';
end $$;

\echo ''
\echo '--- TEST 6: a complete vitrine and a referral that took off, once ---'
update orgs set storefront_blurb = 'Tout pour la maison', phone = '+22670540001',
                address = 'Ouaga 2000', lat = 12.3, lng = -1.5
 where id = '54000000-0000-0000-0000-000000000001';
insert into products (org_id, name, sale_price, quantity, is_active, is_published) values
    ('54000000-0000-0000-0000-000000000001', 'Savon', 300, 5, true, true);
insert into documents (org_id, product_id, kind, r2_key, uploaded_by)
select '54000000-0000-0000-0000-000000000001', id, 'product_photo', 'k/' || id,
       '54545454-0000-0000-0000-000000000001'
  from products where org_id = '54000000-0000-0000-0000-000000000001';
-- The newcomer says the shop brought it in, then takes off.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '54545454-0000-0000-0000-000000000004';
select set_referral('54000000-0000-0000-0000-000000000004', 'CAURIS-54');
do $$ begin
    begin
        perform set_referral('54000000-0000-0000-0000-000000000004', 'cauris-54');
        raise exception 'FAIL: a referral was set twice';
    exception when others then
        if sqlerrm not like 'Le parrain est déjà%' then raise; end if;
    end;
end $$;
commit;
update orgs set storefront_blurb = 'Neuf', phone = '+22670540004', address = 'Gounghin',
                lat = 12.3, lng = -1.5
 where id = '54000000-0000-0000-0000-000000000004';
insert into products (org_id, name, sale_price, quantity, is_active, is_published) values
    ('54000000-0000-0000-0000-000000000004', 'Pain', 200, 5, true, true);
insert into documents (org_id, product_id, kind, r2_key, uploaded_by)
select '54000000-0000-0000-0000-000000000004', id, 'product_photo', 'n/' || id,
       '54545454-0000-0000-0000-000000000004'
  from products where org_id = '54000000-0000-0000-0000-000000000004';
do $$
declare i int; o uuid;
begin
    for i in 1..3 loop
        o := t54_order('54000000-0000-0000-0000-000000000004', '54545454-0000-0000-0000-000000000003', 1000);
        update orders set status = 'accepted' where id = o;
        update orders set status = 'picked_up' where id = o;
    end loop;
end $$;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '54545454-0000-0000-0000-000000000001';
select cauris_milestones('54000000-0000-0000-0000-000000000001');
select cauris_milestones('54000000-0000-0000-0000-000000000001');
set local "request.jwt.claim.sub" = '54545454-0000-0000-0000-000000000004';
select cauris_milestones('54000000-0000-0000-0000-000000000004');
select cauris_milestones('54000000-0000-0000-0000-000000000004');
commit;
do $$ begin
    if (select count(*) from cauris_ledger where org_id = '54000000-0000-0000-0000-000000000001'
          and reason = 'vitrine_complete') <> 1 then
        raise exception 'FAIL: a complete vitrine did not earn once (score %)',
            vitrine_score('54000000-0000-0000-0000-000000000001');
    end if;
    if (select count(*) from cauris_ledger where org_id = '54000000-0000-0000-0000-000000000001'
          and reason = 'referral') <> 1 then
        raise exception 'FAIL: the referral did not earn the shop once';
    end if;
    raise notice 'PASS: +50 for the vitrine, +200 for the business it brought in';
end $$;

\echo ''
\echo '--- TEST 7: the wallet, for its admins; an idle one expires ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '54545454-0000-0000-0000-000000000002';
do $$ begin
    if my_cauris('54000000-0000-0000-0000-000000000001') is not null then
        raise exception 'FAIL: an employee reads the wallet';
    end if;
    begin
        perform cauris_award('54000000-0000-0000-0000-000000000001', 'referral', 'cheat');
        raise exception 'FAIL: an app user awarded cauris';
    exception when insufficient_privilege then null;
    end;
    begin
        perform set_cauris_rule('order_done', 1000);
        raise exception 'FAIL: a shop set the rules';
    exception when others then
        if sqlerrm not like 'Only the platform%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '54545454-0000-0000-0000-000000000001';
do $$
declare w jsonb := my_cauris('54000000-0000-0000-0000-000000000001');
begin
    perform set_config('t54.balance', w ->> 'balance', true);
    if (w ->> 'balance')::int <= 0
       or jsonb_array_length(w -> 'history') < 5 or w ->> 'referral_code' <> 'cauris-54'
       or (w ->> 'week')::int <= 0 then
        raise exception 'FAIL: the owner does not read the wallet: %', w;
    end if;
    raise notice 'PASS: % cauris, % this week', w ->> 'balance', w ->> 'week';
end $$;
select set_config('t54.read', current_setting('t54.balance'), false);
commit;
do $$ begin
    if current_setting('t54.read')::int <> cauris_balance('54000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the wallet read is not the ledger''s sum';
    end if;
end $$;
update cauris_ledger set created_at = created_at - interval '200 days'
 where org_id = '54000000-0000-0000-0000-000000000002';
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '54545454-0000-0000-0000-000000000001';
select my_cauris('54000000-0000-0000-0000-000000000002');
commit;
do $$ begin
    if cauris_balance('54000000-0000-0000-0000-000000000002') <> 0
       or not exists (select 1 from cauris_ledger where org_id = '54000000-0000-0000-0000-000000000002'
                       and reason = 'expired' and delta = -5) then
        raise exception 'FAIL: an idle wallet did not expire';
    end if;
    raise notice 'PASS: 200 days idle, the 5 cauris expired';
end $$;

do $$ begin
    if has_function_privilege('authenticated', 'cauris_award(uuid, text, text, text)', 'execute')
       or has_function_privilege('anon', 'cauris_award(uuid, text, text, text)', 'execute')
       or not has_function_privilege('anon', 'record_visitor(text, text)', 'execute')
       or has_function_privilege('anon', 'my_cauris(uuid)', 'execute') then
        raise exception 'FAIL: the grants are not as drawn';
    end if;
end $$;

drop function t54_order(uuid, uuid, numeric, interval);

\echo ''
\echo 'test_cauris: all passed'
