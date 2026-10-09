-- ============================================================
-- test_batch115.sql — the bell, everywhere, for everyone (115).
--
-- The claims, for a shop, a farm and an association alike:
--   * every row says whose list it is (scope) and each list counts its own
--     unread rows, the caller's only;
--   * P1: the bells of before are written with the same words; Mara's
--     message reaches the responsables, as before, unless « Toute
--     l'équipe » is asked;
--   * a refusal can carry its reason, kept on the order and said to the
--     customer; only the shop refuses, only a pending order;
--   * a type switched off writes nothing; the catalog's defaults hold
--     (the 7-day nudge off); account messages have no switch;
--   * an Android phone's token is saved as its owner; the Worker's book
--     has both kinds, 060's answer browsers only; neither book opens to
--     an app role;
--   * « M'envoyer une notification test » rings the caller alone, says
--     their devices, and the webhook's state to the platform only;
--   * the shopper hears their phone verified; the courier their dossier
--     received, a delivery near them (own couriers first, then the city),
--     a shop adding them, the cash confirmed, and the nudge only when
--     asked;
--   * home_counts: what asks for action, per kind, null for a stranger;
--   * the doors: closed to the street, the internals to everyone.
-- ============================================================
\set ON_ERROR_STOP on

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
-- As on Supabase, the app's role reads auth.uid() (an invoker function
-- and a policy run it as the caller); taken back at the end.
grant usage on schema auth to authenticated;
-- Earlier suites hand the app's roles every function: 115 again, so what
-- follows tests its own doors.
\i database/migrations/115_notifications.sql

\set mara    '''11511511-0000-0000-0000-000000000001'''
\set sowner  '''11511511-0000-0000-0000-000000000002'''
\set fowner  '''11511511-0000-0000-0000-000000000003'''
\set aowner  '''11511511-0000-0000-0000-000000000004'''
\set awa     '''11511511-0000-0000-0000-000000000005'''
\set clerk   '''11511511-0000-0000-0000-000000000006'''
\set ouaga   '''11511511-0000-0000-0000-000000000007'''
\set bobo    '''11511511-0000-0000-0000-000000000008'''
\set nocity  '''11511511-0000-0000-0000-000000000009'''
\set own     '''11511511-0000-0000-0000-000000000010'''
\set shop    '''11500000-0000-0000-0000-000000000001'''
\set farm    '''11500000-0000-0000-0000-000000000002'''
\set assoc   '''11500000-0000-0000-0000-000000000003'''

insert into auth.users (id, phone, email, raw_user_meta_data) values
    (:mara,   '+22611501001', 'mara115@example.com', '{"full_name": "Mara Cent-Quinze"}'),
    (:sowner, '+22611501002', null, '{"full_name": "Patronne 115"}'),
    (:fowner, '+22611501003', null, '{"full_name": "Fermier 115"}'),
    (:aowner, '+22611501004', null, '{"full_name": "Trésorière 115"}'),
    (:awa,    '+22611501005', 'awa115@example.com', '{"full_name": "Awa Cliente"}'),
    (:clerk,  '+22611501006', null, '{"full_name": "Vendeuse 115"}'),
    (:ouaga,  '+22611501007', null, '{"full_name": "Livreur Ouaga"}'),
    (:bobo,   '+22611501008', null, '{"full_name": "Livreur Bobo"}'),
    (:nocity, '+22611501009', null, '{"full_name": "Livreur Partout"}'),
    (:own,    '+22611501010', null, '{"full_name": "Livreur Maison"}');
update profiles set is_platform_admin = true where id = :mara;
insert into orgs (id, name, slug, profile, default_currency, plan, storefront_enabled, city) values
    (:shop,  'Boutique 115', 'boutique-115', 'retail',      'XOF', 'free', true, 'Ouagadougou'),
    (:farm,  'Ferme 115',    'ferme-115',    'farm',        'XOF', 'free', true, null),
    (:assoc, 'Entraide 115', 'entraide-115', 'association', 'XOF', 'free', true, 'Ouagadougou');
-- Delivery is a Pro tool (081): the shop and the farm are on Pro.
update orgs set plan = 'pro', plan_until = current_date + 30 where id in (:shop, :farm);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :sowner, 'owner',    'org', :shop,  'full'),
    (:shop,  :clerk,  'employee', 'org', :shop,  'summary'),
    (:farm,  :fowner, 'owner',    'org', :farm,  'full'),
    (:assoc, :aowner, 'owner',    'org', :assoc, 'full');
insert into couriers (user_id, phone, status, decided_at) values
    (:ouaga,  '+22611501007', 'approved', now() - interval '30 days'),
    (:bobo,   '+22611501008', 'approved', now() - interval '30 days'),
    (:nocity, '+22611501009', 'approved', now() - interval '30 days'),
    (:own,    '+22611501010', 'approved', now() - interval '30 days');
insert into courier_applications (user_id, status, city) values
    (:ouaga, 'approved', ' ouagadougou '),
    (:bobo,  'approved', 'Bobo-Dioulasso');
insert into products (id, org_id, name, sale_price, cost_price, quantity, low_stock_at, is_active, is_published, is_service) values
    ('115aaaaa-0000-0000-0000-000000000001', :shop,  'Savon 115',  500, 300, 5, null, true, true, false),
    ('115aaaaa-0000-0000-0000-000000000002', :shop,  'Riz 115',   1000, 800, 0, null, true, true, false),
    ('115aaaaa-0000-0000-0000-000000000003', :shop,  'Huile 115', 1500, 900, 2, 3,    true, true, false),
    ('115aaaaa-0000-0000-0000-000000000004', :shop,  'Coupe 115', 1500,   0, 0, null, true, true, true),
    ('115aaaaa-0000-0000-0000-000000000005', :farm,  'Œufs 115',  2500,   0, 0, null, true, true, false),
    ('115aaaaa-0000-0000-0000-000000000007', :farm,  'Maïs 115',  2000,   0, 10, null, true, true, false),
    ('115aaaaa-0000-0000-0000-000000000006', :assoc, 'Bâches 115', 5000,  0, 0, null, true, true, true);

-- The caller, named the way PostgREST names them.
create or replace function pg_temp.as115(p_who uuid)
returns void
language sql
as $$ select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true); $$;

create or replace function pg_temp.refused115(p_sql text)
returns text
language plpgsql
as $$
begin
    execute p_sql;
    return '(went through)';
exception when others then
    return sqlerrm;
end;
$$;

-- The helpers run as the app's role too, where a test becomes it.
grant execute on function pg_temp.as115(uuid), pg_temp.refused115(text) to authenticated;

-- An order of Awa's at a business: one article line, or one service line.
create or replace function pg_temp.order115(p_org uuid, p_service boolean,
                                            p_fulfilment text default 'pickup')
returns uuid
language plpgsql
as $$
declare v uuid;
begin
    insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency,
                        address, delivery_fee)
    values (p_org, '11511511-0000-0000-0000-000000000005', 'Awa Cliente', 'pending', p_fulfilment,
            1500, 'XOF', case when p_fulfilment = 'delivery' then 'Zogona' end,
            case when p_fulfilment = 'delivery' then 500 end)
    returning id into v;
    insert into order_lines (order_id, product_id, name, unit_price, quantity, is_service)
    select v, p.id, p.name, p.sale_price, 1, p.is_service
      from products p where p.org_id = p_org and p.is_service = p_service
     order by p.name limit 1;
    return v;
end;
$$;

\echo ''
\echo '--- TEST 1: each row knows its list; each list counts its own, the caller''s only ---'
begin;
do $$
declare v_shop uuid := '11500000-0000-0000-0000-000000000001'; c jsonb; v_order uuid;
begin
    v_order := pg_temp.order115(v_shop, false);
    perform pg_temp.as115('11511511-0000-0000-0000-000000000002');
    perform decide_order(v_order, 'accepted');
    perform notify_org_admins(v_shop, 'low_stock', 'Stock bas : Savon 115 (1 restant)',
                              jsonb_build_object('to', 'shop', 'name', 'Savon 115'));
    insert into notifications (recipient_id, org_id, kind, message, params) values
        ('11511511-0000-0000-0000-000000000005', null, 'new_device', 'Nouvelle connexion', '{"device": "X"}'),
        ('11511511-0000-0000-0000-000000000007', null, 'courier_approved', 'Vous êtes livreur', '{"to": "courier"}'),
        ('11511511-0000-0000-0000-000000000001', null, 'org_application', 'Nouvelle demande', null),
        ('11511511-0000-0000-0000-000000000001', null, 'spot_requested', 'Mise en avant', null),
        -- written before 099: no params, the customer's kind
        ('11511511-0000-0000-0000-000000000005', v_shop, 'order_ready', 'Votre commande : prête', null);
    if (select scope from notifications where kind = 'order_accepted' and recipient_id = '11511511-0000-0000-0000-000000000005') <> 'customer'
       or (select scope from notifications where kind = 'low_stock' and recipient_id = '11511511-0000-0000-0000-000000000002') <> 'shop'
       or (select scope from notifications where kind = 'new_device' and recipient_id = '11511511-0000-0000-0000-000000000005') <> 'me'
       or (select scope from notifications where kind = 'courier_approved' and recipient_id = '11511511-0000-0000-0000-000000000007') <> 'courier'
       or exists (select 1 from notifications where recipient_id = '11511511-0000-0000-0000-000000000001'
                                                 and kind in ('org_application', 'spot_requested') and scope <> 'platform')
       or (select scope from notifications where kind = 'order_ready' and recipient_id = '11511511-0000-0000-0000-000000000005') <> 'customer' then
        raise exception 'FAIL: a row is in the wrong list';
    end if;
    set local role authenticated;
    perform pg_temp.as115('11511511-0000-0000-0000-000000000005');
    c := notification_counts();
    if c <> jsonb_build_object('orgs', '{}'::jsonb, 'customer', 2, 'courier', 0, 'platform', 0, 'me', 1) then
        raise exception 'FAIL: Awa''s counts are %', c;
    end if;
    perform pg_temp.as115('11511511-0000-0000-0000-000000000002');
    c := notification_counts();
    -- The shop's bells: the stock line, and the new order where a trigger
    -- of before rings it.
    if (c -> 'orgs' ->> v_shop::text)::int
          <> (select count(*) from notifications where recipient_id = auth.uid() and org_id = v_shop)
       or (c -> 'orgs' ->> v_shop::text)::int < 1 or (c ->> 'customer')::int <> 0 then
        raise exception 'FAIL: the owner''s counts are %', c;
    end if;
    -- Reading clears only what was read: Awa's purchases, not her account row.
    perform pg_temp.as115('11511511-0000-0000-0000-000000000005');
    update notifications set read_at = now() where scope = 'customer';
    c := notification_counts();
    if (c ->> 'customer')::int <> 0 or (c ->> 'me')::int <> 1 then
        raise exception 'FAIL: reading the purchases cleared %', c;
    end if;
    reset role;
    if (select count(*) from notifications where recipient_id = '11511511-0000-0000-0000-000000000002' and read_at is not null) <> 0 then
        raise exception 'FAIL: Awa''s read touched the owner''s bell';
    end if;
    raise notice 'PASS: shop/customer/courier/platform/me lists; counts the caller''s own; a read clears only its rows';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: P1 — the same words as before; Mara''s message to the responsables by default ---'
begin;
do $$
declare v_shop uuid := '11500000-0000-0000-0000-000000000001'; v_order uuid; v_n int; m text;
begin
    v_order := pg_temp.order115(v_shop, false);
    perform pg_temp.as115('11511511-0000-0000-0000-000000000002');
    perform decide_order(v_order, 'refused');
    select message into m from notifications where kind = 'order_refused';
    if m <> 'Votre commande chez Boutique 115 : refusée' then
        raise exception 'FAIL: a refusal without reason now says %', m;
    end if;
    perform pg_temp.as115('11511511-0000-0000-0000-000000000001');
    v_n := send_platform_message(v_shop, 'Bonjour 115');
    if v_n <> 1 or exists (select 1 from notifications where kind = 'platform_message'
                                                       and recipient_id = '11511511-0000-0000-0000-000000000006') then
        raise exception 'FAIL: the old door reached % people', v_n;
    end if;
    if (select params from notifications where kind = 'platform_message')
       <> jsonb_build_object('to', 'shop', 'text', 'Bonjour 115', 'audience', 'admins')
       or (select message from notifications where kind = 'platform_message') <> 'Kaj : Bonjour 115' then
        raise exception 'FAIL: the message''s words or facts changed';
    end if;
    raise notice 'PASS: a refusal says what it said; send_platform_message reaches the responsables, with its facts';
end $$;
rollback;

begin;
do $$
declare v_shop uuid := '11500000-0000-0000-0000-000000000001';
        v_farm uuid := '11500000-0000-0000-0000-000000000002';
        v_assoc uuid := '11500000-0000-0000-0000-000000000003'; r jsonb;
begin
    perform pg_temp.as115('11511511-0000-0000-0000-000000000001');
    r := platform_bulk('message', array[v_shop, v_farm, v_assoc], '{"message": "Tous"}'::jsonb);
    if (r ->> 'done')::int <> 3
       or (select count(*) from notifications where kind = 'platform_message') <> 3 then
        raise exception 'FAIL: the default audience reached %', (select count(*) from notifications where kind = 'platform_message');
    end if;
    r := platform_bulk('message', array[v_shop], '{"message": "Équipe", "audience": "team"}'::jsonb);
    if (select count(*) from notifications where kind = 'platform_message' and params ->> 'text' = 'Équipe') <> 2
       or not exists (select 1 from notifications where params ->> 'text' = 'Équipe'
                                                  and recipient_id = '11511511-0000-0000-0000-000000000006')
       or not exists (select 1 from platform_actions where after ->> 'audience' = 'team'
                                                      and summary like '%(toute l''équipe)%') then
        raise exception 'FAIL: « Toute l''équipe » did not reach the employee, or the journal does not say so';
    end if;
    if pg_temp.refused115($q$select platform_bulk('message', array['11500000-0000-0000-0000-000000000001'::uuid], '{"message": "x", "audience": "tous"}'::jsonb)$q$)
       not like 'Destinataires inconnus%' then
        raise exception 'FAIL: an unknown audience went through';
    end if;
    raise notice 'PASS: platform_bulk — responsables by default for all three kinds, « Toute l''équipe » reaches every member and says so';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: « Refuser » with its reason — kept, said, the shop''s only, a pending order only ---'
begin;
do $$
declare v_shop uuid := '11500000-0000-0000-0000-000000000001'; v_order uuid; n notifications%rowtype;
begin
    v_order := pg_temp.order115(v_shop, false);
    perform pg_temp.as115('11511511-0000-0000-0000-000000000005');
    if pg_temp.refused115(format('select refuse_order(%L, %L)', v_order, 'non')) not like 'Only the shop%' then
        raise exception 'FAIL: the customer refused her own order';
    end if;
    perform pg_temp.as115('11511511-0000-0000-0000-000000000002');
    perform refuse_order(v_order, '  Plus de riz aujourd''hui  ');
    select * into n from notifications where kind = 'order_refused' and recipient_id = '11511511-0000-0000-0000-000000000005';
    if n.message <> 'Votre commande chez Boutique 115 : refusée — Plus de riz aujourd''hui'
       or n.params ->> 'reason' <> 'Plus de riz aujourd''hui' or n.params ->> 'status' <> 'refused'
       or (select refusal_reason from orders where id = v_order) <> 'Plus de riz aujourd''hui'
       or (select status from orders where id = v_order) <> 'refused' then
        raise exception 'FAIL: the reason was not kept or said: % %', n.message, n.params;
    end if;
    if pg_temp.refused115(format('select refuse_order(%L, %L)', v_order, 'encore')) not like 'An order cannot go from refused%' then
        raise exception 'FAIL: a refused order was refused again';
    end if;
    raise notice 'PASS: refuse_order keeps the reason (trimmed) and the customer reads it; not the customer''s, not twice';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: switches — off writes nothing; the defaults; no switch on the account ---'
begin;
do $$
declare v_shop uuid := '11500000-0000-0000-0000-000000000001'; v_order uuid; v_book uuid; v_types int;
begin
    set local role authenticated;
    perform pg_temp.as115('11511511-0000-0000-0000-000000000005');
    select count(*) into v_types from my_notification_prefs();
    if v_types <> (select count(*) from notification_types())
       or (select enabled from my_notification_prefs() where type = 'courier_idle')
       or not (select enabled from my_notification_prefs() where type = 'order_updates') then
        raise exception 'FAIL: the catalog''s defaults are not what the person reads';
    end if;
    perform set_notification_pref('order_updates', false);
    if pg_temp.refused115($q$select set_notification_pref('new_device', false)$q$) not like 'Type de notification inconnu%' then
        raise exception 'FAIL: the account''s security message could be switched off';
    end if;
    if pg_temp.refused115($q$insert into notification_prefs (user_id, type, enabled) values ('11511511-0000-0000-0000-000000000005', 'bookings', false)$q$) = '(went through)' then
        raise exception 'FAIL: the switches were written around set_notification_pref';
    end if;
    perform pg_temp.as115('11511511-0000-0000-0000-000000000002');
    if exists (select 1 from notification_prefs) then
        raise exception 'FAIL: the owner reads Awa''s switches';
    end if;
    reset role;
    v_order := pg_temp.order115(v_shop, false);
    v_book := pg_temp.order115(v_shop, true);
    perform pg_temp.as115('11511511-0000-0000-0000-000000000002');
    perform decide_order(v_order, 'accepted');
    perform decide_order(v_book, 'accepted');
    if exists (select 1 from notifications where params ->> 'order_id' = v_order::text
                                             and recipient_id = '11511511-0000-0000-0000-000000000005') then
        raise exception 'FAIL: a switched-off order update still rang';
    end if;
    if not exists (select 1 from notifications where params ->> 'order_id' = v_book::text
                                                 and recipient_id = '11511511-0000-0000-0000-000000000005'
                                                 and kind = 'order_accepted') then
        raise exception 'FAIL: the booking (its own switch, on) did not ring';
    end if;
    insert into notifications (recipient_id, org_id, kind, message, params)
    values ('11511511-0000-0000-0000-000000000005', null, 'new_device', 'Nouvelle connexion', '{"device": "Y"}');
    if not exists (select 1 from notifications where kind = 'new_device' and recipient_id = '11511511-0000-0000-0000-000000000005') then
        raise exception 'FAIL: the account message was muted';
    end if;
    raise notice 'PASS: off = no row (so no push); bookings their own switch; new_device has none; switches the person''s own';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: an Android phone in the book; the Worker''s doors ---'
begin;
do $$
declare v_web int; v_all int;
begin
    set local role authenticated;
    perform pg_temp.as115(null);
    if pg_temp.refused115($q$select save_fcm_token('tok-stranger')$q$) not like '%signed-in%' then
        raise exception 'FAIL: a stranger saved a token';
    end if;
    perform pg_temp.as115('11511511-0000-0000-0000-000000000005');
    perform save_push_subscription('https://push.example/awa-115', 'p256', 'auth', 'Chrome');
    perform save_fcm_token('tok-awa-115', 'Tecno');
    if pg_temp.refused115($q$select save_fcm_token('   ')$q$) not like '%token is missing%' then
        raise exception 'FAIL: an empty token was saved';
    end if;
    if (select count(*) from push_subscriptions) <> 2
       or not exists (select 1 from push_subscriptions where endpoint = 'fcm:tok-awa-115'
                                                      and platform = 'android' and fcm_token = 'tok-awa-115') then
        raise exception 'FAIL: the phone''s row is not the owner''s, as android';
    end if;
    -- The same phone signed in as someone else moves to them.
    perform pg_temp.as115('11511511-0000-0000-0000-000000000006');
    perform save_fcm_token('tok-awa-115', 'Tecno');
    reset role;
    if (select user_id from push_subscriptions where endpoint = 'fcm:tok-awa-115') <> '11511511-0000-0000-0000-000000000006' then
        raise exception 'FAIL: the token did not move with the phone';
    end if;
    update push_subscriptions set user_id = '11511511-0000-0000-0000-000000000005' where endpoint = 'fcm:tok-awa-115';
    select count(*) into v_web from push_targets('11511511-0000-0000-0000-000000000005');
    select count(*) into v_all from push_devices('11511511-0000-0000-0000-000000000005');
    if v_web <> 1 or v_all <> 2 then
        raise exception 'FAIL: push_targets % (browsers only) / push_devices % (both)', v_web, v_all;
    end if;
    if pg_temp.refused115($q$insert into push_subscriptions (endpoint, user_id, platform) values ('fcm:x', '11511511-0000-0000-0000-000000000005', 'android')$q$) = '(went through)' then
        raise exception 'FAIL: a phone row without its token was stored';
    end if;
    if has_function_privilege('authenticated', 'push_devices(uuid)', 'execute')
       or has_function_privilege('anon', 'push_devices(uuid)', 'execute')
       or has_function_privilege('authenticated', 'push_targets(uuid)', 'execute') then
        raise exception 'FAIL: the Worker''s book is open to an app role';
    end if;
    raise notice 'PASS: save_fcm_token as the owner (moves with the phone); push_devices both, push_targets browsers; closed to the app';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: the test notification — the caller alone, their devices, the webhook to Mara only ---'
begin;
do $$
declare r jsonb; i int;
begin
    set local role authenticated;
    perform pg_temp.as115('11511511-0000-0000-0000-000000000005');
    perform save_fcm_token('tok-awa-test', 'Tecno');
    r := send_test_notification();
    if r <> '{"web": 0, "android": 1}'::jsonb then
        raise exception 'FAIL: Awa reads %', r;
    end if;
    perform pg_temp.as115('11511511-0000-0000-0000-000000000001');
    r := send_test_notification();
    if not (r ? 'webhook') or (r ->> 'webhook')::boolean then
        raise exception 'FAIL: Mara reads % (no webhook in CI)', r;
    end if;
    reset role;
    if (select count(*) from notifications where kind = 'test_push') <> 2
       or exists (select 1 from notifications where kind = 'test_push'
                   and (scope <> 'me' or recipient_id not in ('11511511-0000-0000-0000-000000000005',
                                                              '11511511-0000-0000-0000-000000000001'))) then
        raise exception 'FAIL: the test rang someone else';
    end if;
    set local role authenticated;
    perform pg_temp.as115('11511511-0000-0000-0000-000000000005');
    for i in 1..4 loop perform send_test_notification(); end loop;
    if pg_temp.refused115('select send_test_notification()') not like 'Cinq essais%' then
        raise exception 'FAIL: a sixth test in ten minutes went through';
    end if;
    raise notice 'PASS: send_test_notification rings the caller, counts their devices; the webhook state is Mara''s; five per ten minutes';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: the shopper — the phone verified ---'
begin;
do $$
begin
    update auth.users set phone_confirmed_at = now() where id = '11511511-0000-0000-0000-000000000005';
    if (select message from notifications where kind = 'phone_verified'
                                            and recipient_id = '11511511-0000-0000-0000-000000000005')
       <> 'Votre numéro +22611501005 est vérifié.' then
        raise exception 'FAIL: the verified phone was not said';
    end if;
    update auth.users set email = 'awa115b@example.com' where id = '11511511-0000-0000-0000-000000000005';
    if (select count(*) from notifications where kind = 'phone_verified') <> 1 then
        raise exception 'FAIL: another change rang again';
    end if;
    raise notice 'PASS: phone_verified once, in the account''s list';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: the courier — received, near me, own first, a shop adds me, the cash, the nudge ---'
begin;
do $$
declare v_shop uuid := '11500000-0000-0000-0000-000000000001';
        v_farm uuid := '11500000-0000-0000-0000-000000000002';
        v_order uuid; v_told text;
begin
    -- The dossier sent: the applicant hears it.
    insert into courier_applications (user_id, status) values ('11511511-0000-0000-0000-000000000005', 'draft');
    update courier_applications set status = 'pending', sent_at = now() where user_id = '11511511-0000-0000-0000-000000000005';
    if (select scope from notifications where kind = 'courier_received'
                                          and recipient_id = '11511511-0000-0000-0000-000000000005') <> 'courier' then
        raise exception 'FAIL: the dossier received was not said';
    end if;
    -- A shop in Ouagadougou with no couriers of its own: the city's (and
    -- the ones with no city) at once, never Bobo's.
    v_order := pg_temp.order115(v_shop, false, 'delivery');
    perform pg_temp.as115('11511511-0000-0000-0000-000000000002');
    perform decide_order(v_order, 'accepted');
    perform decide_order(v_order, 'ready');
    select string_agg(p.full_name, ', ' order by p.full_name) into v_told
      from notifications n join profiles p on p.id = n.recipient_id
     where n.kind = 'delivery_available' and n.params ->> 'order_id' = v_order::text;
    if v_told <> 'Livreur Maison, Livreur Ouaga, Livreur Partout'
       or (select couriers_told_at from orders where id = v_order) is null then
        raise exception 'FAIL: the street told %', v_told;
    end if;
    -- A farm with its own courier: him at once, the street after the minutes.
    insert into org_couriers (org_id, user_id) values (v_farm, '11511511-0000-0000-0000-000000000010');
    if (select message from notifications where kind = 'courier_shop_added') <> 'Ferme 115 vous a ajouté à ses livreurs : ses livraisons vous arrivent en premier.' then
        raise exception 'FAIL: the courier added was not told';
    end if;
    v_order := pg_temp.order115(v_farm, false, 'delivery');
    perform pg_temp.as115('11511511-0000-0000-0000-000000000003');
    perform decide_order(v_order, 'accepted');
    perform decide_order(v_order, 'ready');
    if (select count(*) from notifications where kind = 'delivery_available' and params ->> 'order_id' = v_order::text) <> 1
       or not (select (params ->> 'own')::boolean from notifications where kind = 'delivery_available' and params ->> 'order_id' = v_order::text) then
        raise exception 'FAIL: the farm''s own courier was not alone first';
    end if;
    if deliveries_waiting() <> 0 then
        raise exception 'FAIL: the street heard before the minutes';
    end if;
    update orders set updated_at = now() - interval '11 minutes' where id = v_order;
    if deliveries_waiting() <> 3 or deliveries_waiting() <> 0 then
        raise exception 'FAIL: after the minutes the street (all three: the farm has no city) heard not once';
    end if;
    -- The cash handed over.
    update orders set status = 'delivered', courier_id = '11511511-0000-0000-0000-000000000007',
                      payment_method = 'cash' where id = v_order;
    perform confirm_cash_received(v_order);
    if (select recipient_id from notifications where kind = 'courier_cash_received') <> '11511511-0000-0000-0000-000000000007'
       or (select message from notifications where kind = 'courier_cash_received')
          <> 'Ferme 115 confirme avoir reçu l''argent de la livraison pour Awa Cliente : '
             || to_char(1500, 'FM999G999G999') || ' F.' then
        raise exception 'FAIL: the cash was not said: %', (select message from notifications where kind = 'courier_cash_received');
    end if;
    -- The nudge: only who switched it on, once a week.
    update orders set updated_at = now() - interval '8 days' where courier_id is not null;
    if courier_idle_nudge() <> 0 then
        raise exception 'FAIL: a nudge nobody asked for';
    end if;
    perform pg_temp.as115('11511511-0000-0000-0000-000000000008');
    perform set_notification_pref('courier_idle', true);
    if courier_idle_nudge() <> 1 or courier_idle_nudge() <> 0 then
        raise exception 'FAIL: the nudge is not once, for Bobo alone';
    end if;
    raise notice 'PASS: received; near me by city (own couriers first, the street after the minutes); added; cash; the nudge when asked';
end $$;
rollback;

\echo ''
\echo '--- TEST 9: home_counts — what asks for action, for a shop, a farm, an association ---'
begin;
do $$
declare v_shop uuid := '11500000-0000-0000-0000-000000000001';
        v_farm uuid := '11500000-0000-0000-0000-000000000002';
        v_assoc uuid := '11500000-0000-0000-0000-000000000003';
        v_cust uuid; v_flock uuid; v_entry uuid; c jsonb; v_due boolean;
begin
    perform pg_temp.order115(v_shop, false);
    perform pg_temp.order115(v_shop, true);
    perform pg_temp.order115(v_assoc, true);
    insert into customers (org_id, name) values (v_shop, 'Client 115') returning id into v_cust;
    insert into invoices (org_id, customer_id, number, issued_on, due_on, total, created_by) values
        (v_shop, v_cust, 'F115-1', current_date - 20, current_date - 5, 10000, '11511511-0000-0000-0000-000000000002'),
        (v_shop, v_cust, 'F115-2', current_date - 20, current_date + 5, 10000, '11511511-0000-0000-0000-000000000002'),
        (v_shop, v_cust, 'F115-3', current_date - 20, current_date - 5, 10000, '11511511-0000-0000-0000-000000000002');
    insert into invoice_payments (invoice_id, amount, created_by)
    select id, 10000, '11511511-0000-0000-0000-000000000002' from invoices where number = 'F115-3';
    insert into pending_invitations (org_id, role, scope_kind, scope_id, code, created_by) values
        (v_shop, 'employee', 'org', v_shop, 'B115-ABCD', '11511511-0000-0000-0000-000000000002');
    v_due := exists (select 1 from information_schema.columns
                      where table_schema = 'public' and table_name = 'debts' and column_name = 'due_on');
    if v_due then
        insert into journal_entries (org_id, created_by) values (v_shop, '11511511-0000-0000-0000-000000000002')
        returning id into v_entry;
        execute 'insert into debts (org_id, customer_id, journal_entry_id, label, amount, created_by, due_on)
                 values ($1, $2, $3, ''Crédit 115'', 2000, $4, current_date - 1)'
          using v_shop, v_cust, v_entry, '11511511-0000-0000-0000-000000000002'::uuid;
    end if;
    insert into flocks (org_id, batch_code, bird_count) values (v_farm, 'B115', 100) returning id into v_flock;
    insert into flocks (org_id, batch_code, bird_count) values (v_farm, 'B115-2', 50);
    insert into egg_production (org_id, flock_id, egg_count, created_by)
    values (v_farm, v_flock, 80, '11511511-0000-0000-0000-000000000003');
    insert into items (org_id, name, reorder_level) values (v_farm, 'Aliment 115', 5);

    set local role authenticated;
    perform pg_temp.as115('11511511-0000-0000-0000-000000000002');
    c := home_counts(v_shop);
    if c <> jsonb_build_object('orders', 1, 'bookings', 1, 'articles', 2, 'invoices', 1,
                               'credit', case when v_due then 1 else 0 end, 'invitations', 1,
                               'supplies', 0, 'livestock', 0) then
        raise exception 'FAIL: the shop counts %', c;
    end if;
    -- The employee: what their access shows (the invitations are the admins').
    perform pg_temp.as115('11511511-0000-0000-0000-000000000006');
    if (home_counts(v_shop) ->> 'invitations')::int <> 0 or (home_counts(v_shop) ->> 'orders')::int <> 1 then
        raise exception 'FAIL: the employee counts %', home_counts(v_shop);
    end if;
    perform pg_temp.as115('11511511-0000-0000-0000-000000000003');
    c := home_counts(v_farm);
    if c <> jsonb_build_object('orders', 0, 'bookings', 0, 'articles', 1, 'invoices', 0, 'credit', 0,
                               'invitations', 0, 'supplies', 1, 'livestock', 1) then
        raise exception 'FAIL: the farm counts %', c;
    end if;
    perform pg_temp.as115('11511511-0000-0000-0000-000000000004');
    c := home_counts(v_assoc);
    if c <> jsonb_build_object('orders', 0, 'bookings', 1, 'articles', 0, 'invoices', 0, 'credit', 0,
                               'invitations', 0, 'supplies', 0, 'livestock', 0) then
        raise exception 'FAIL: the association counts %', c;
    end if;
    if home_counts(v_shop) is not null then
        raise exception 'FAIL: a stranger counted the shop';
    end if;
    raise notice 'PASS: shop (orders, bookings, articles 0/under alert, invoices past due, credit past due when 117 is in, invitations), farm (supplies, batches without today''s log), association (bookings); employee = their access; stranger null';
end $$;
rollback;

\echo ''
\echo '--- TEST 10: the doors ---'
do $$
declare v_open text;
begin
    select string_agg(f, ', ') into v_open
      from unnest(array['notification_counts()', 'save_fcm_token(text,text)', 'push_devices(uuid)',
                        'my_notification_prefs()', 'set_notification_pref(text,boolean)',
                        'send_test_notification()', 'refuse_order(uuid,text)', 'home_counts(uuid)',
                        'platform_message_send(uuid,text,text)', 'deliveries_waiting()',
                        'courier_idle_nudge()', 'tell_couriers(uuid,boolean)']) f
     where has_function_privilege('anon', f, 'execute');
    if v_open is not null then
        raise exception 'FAIL: open to the street: %', v_open;
    end if;
    select string_agg(f, ', ') into v_open
      from unnest(array['push_devices(uuid)', 'deliveries_waiting()', 'courier_idle_nudge()',
                        'tell_couriers(uuid,boolean)', 'trg_notification_prefs()',
                        'trg_notify_delivery_ready()', 'trg_notify_courier_cash()']) f
     where has_function_privilege('authenticated', f, 'execute');
    if v_open is not null then
        raise exception 'FAIL: internals open to the app: %', v_open;
    end if;
    if not has_function_privilege('authenticated', 'home_counts(uuid)', 'execute')
       or not has_function_privilege('authenticated', 'refuse_order(uuid,text)', 'execute')
       or not has_function_privilege('authenticated', 'notification_counts()', 'execute') then
        raise exception 'FAIL: the app lost a door it needs';
    end if;
    begin
        set local role authenticated;
        perform pg_temp.as115('11511511-0000-0000-0000-000000000002');
        perform platform_message_send(null, 'x', 'admins');
        raise exception 'FAIL: an owner wrote to every business';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    raise notice 'PASS: closed to anon; internals closed to authenticated; the platform''s message the platform''s';
end $$;

revoke usage on schema auth from authenticated;
