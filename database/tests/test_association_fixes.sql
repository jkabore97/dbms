-- ============================================================
-- test_association_fixes.sql — an association's second business, and a
-- bell that says what it is about (099). Phone block 68.
--
-- The claims: the owner of a Free association (or a church) is refused a
-- second business, as a shop's owner is, and org_progress() shows them
-- the lock; Pro on any business they own opens it; somebody who owns
-- nothing — an employee of a Free shop — applies for a first one and is
-- shown no lock; Mara's admins pass; with no caller the business's own
-- plan answers; nothing else locks for an association (invoices, credits,
-- production stay open, check_unlocks says nothing, path_state is null).
-- A booking rings the association's treasurer with its facts, and the
-- customer hears each status with theirs; a customer who cancels is
-- heard by the business; low stock, a member joining and a credit settled
-- carry what the app needs to open the article, the team, the customer;
-- every function that rings a business's or a person's bell gives its
-- params; the recipient reads them under RLS; and nobody signed in may
-- ring a bell themselves (notify_org_admins, notify_platform_spot).
-- ============================================================
\set ON_ERROR_STOP on
-- The owner's numbers: earlier suites change them for their own fixtures.
update platform_settings set value = '8' where key = 'vitrine_min_items';
update platform_settings set value = '1' where key = 'vitrine_min_items_association';
update platform_settings set value = '0' where key = 'path_gates_open';
update platform_settings set value = '3' where key = 'progress_credit_orders';

\set treas  '''68686868-0000-0000-0000-000000000001'''
\set buyer  '''68686868-0000-0000-0000-000000000002'''
\set pastor '''68686868-0000-0000-0000-000000000003'''
\set rich   '''68686868-0000-0000-0000-000000000004'''
\set clerk  '''68686868-0000-0000-0000-000000000005'''
\set boss   '''68686868-0000-0000-0000-000000000006'''
\set mara   '''68686868-0000-0000-0000-000000000007'''
\set joiner '''68686868-0000-0000-0000-000000000008'''
\set assoc  '''68000000-0000-0000-0000-000000000001'''
\set church '''68000000-0000-0000-0000-000000000002'''
\set club   '''68000000-0000-0000-0000-000000000003'''
\set prosh  '''68000000-0000-0000-0000-000000000004'''
\set shop   '''68000000-0000-0000-0000-000000000005'''

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
grant execute on all functions in schema public to authenticated;
-- Earlier suites re-apply older migrations over 099's functions, and 063
-- (test_least_privilege) re-grants every definer function: 099 again, so
-- what follows tests its own definitions and grants.
\i database/migrations/099_association_fixes.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:treas,  '+22668000001', '{"full_name": "Trésorière"}'),
    (:buyer,  '+22668000002', '{"full_name": "Awa"}'),
    (:pastor, '+22668000003', '{"full_name": "Pasteur"}'),
    (:rich,   '+22668000004', '{"full_name": "Riche"}'),
    (:clerk,  '+22668000005', '{"full_name": "Commis"}'),
    (:boss,   '+22668000006', '{"full_name": "Patron"}'),
    (:mara,   '+22668000007', '{"full_name": "Mara"}'),
    (:joiner, '+22668000008', '{"full_name": "Bénévole"}');
update profiles set is_platform_admin = true where id = :mara;
insert into orgs (id, name, slug, profile, default_currency, plan, progress_since,
                  storefront_enabled, storefront_blurb, phone, address, lat, lng) values
    (:assoc,  'Entraide 68', 'entraide-68', 'association', 'XOF', 'free', null, true,
     'Cours du soir', '+22668000001', 'Tanghin', 12.39, -1.50),
    (:church, 'Église 68',   'eglise-68',   'church',      'XOF', 'free', null, false,
     null, null, null, null, null),
    (:club,   'Club 68',     'club-68',     'association', 'XOF', 'pro',  null, false,
     null, null, null, null, null),
    (:prosh,  'Pro 68',      'pro-68',      'retail',      'XOF', 'pro',  null, false,
     null, null, null, null, null),
    (:shop,   'Boutique 68', 'boutique-68', 'retail',      'XOF', 'free', null, false,
     null, null, null, null, null);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:assoc,  :treas,  'owner',    'org', :assoc,  'full'),
    (:church, :pastor, 'owner',    'org', :church, 'full'),
    (:club,   :rich,   'owner',    'org', :club,   'full'),
    (:shop,   :boss,   'owner',    'org', :shop,   'full'),
    (:prosh,  :boss,   'owner',    'org', :prosh,  'full'),
    (:shop,   :clerk,  'employee', 'org', :shop,   'full');
insert into products (org_id, name, sale_price, quantity, is_active, is_published, is_service)
values (:assoc, 'Cours d''alphabétisation', 2000, 0, true, true, true);

\echo ''
\echo '--- TEST 1: a Free association''s owner is shown the lock, and held at the door ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '68686868-0000-0000-0000-000000000001';
do $$
declare p jsonb := org_progress('68000000-0000-0000-0000-000000000001');
begin
    if not (p -> 'locks' ->> 'second_business')::boolean then
        raise exception 'FAIL: the association''s owner is not shown the lock: %', p;
    end if;
    if (p -> 'locks' ->> 'invoices')::boolean or (p -> 'locks' ->> 'production')::boolean
       or (p -> 'locks' ->> 'credits')::boolean then
        raise exception 'FAIL: an association''s own tools locked: %', p -> 'locks';
    end if;
    begin
        perform apply_for_org('Entraide 68 bis', 'entraide-68-bis', 'association');
        raise exception 'FAIL: a second business for a Free association';
    exception when others then
        if sqlerrm not like 'Une deuxième entreprise : avec Mara Pro%' then raise; end if;
    end;
    begin
        perform apply_for_org('Boutique de l''asso', 'boutique-asso-68', 'retail');
        raise exception 'FAIL: a shop for a Free association''s owner';
    exception when others then
        if sqlerrm not like 'Une deuxième entreprise : avec Mara Pro%' then raise; end if;
    end;
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '68686868-0000-0000-0000-000000000003';
do $$ begin
    if not path_locked('68000000-0000-0000-0000-000000000002', 'second_business') then
        raise exception 'FAIL: a church''s owner is not shown the lock';
    end if;
    begin
        perform apply_for_org('Église 68 bis', 'eglise-68-bis', 'association');
        raise exception 'FAIL: a second business for a Free church';
    exception when others then
        if sqlerrm not like 'Une deuxième entreprise : avec Mara Pro%' then raise; end if;
    end;
    raise notice 'PASS: a Free association or church is shown the lock and refused a second business';
end $$;
commit;

\echo ''
\echo '--- TEST 2: Pro opens it; a first business, an employee and Mara pass ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '68686868-0000-0000-0000-000000000004';
do $$ begin
    if path_locked('68000000-0000-0000-0000-000000000003', 'second_business') then
        raise exception 'FAIL: a Pro association is shown the lock';
    end if;
    perform apply_for_org('Club 68 bis', 'club-68-bis', 'association');
end $$;
commit;
-- The owner of a Free shop who also owns a Pro one: Pro on one they own.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '68686868-0000-0000-0000-000000000006';
do $$ begin
    if path_locked('68000000-0000-0000-0000-000000000005', 'second_business') then
        raise exception 'FAIL: the Free shop of an owner with a Pro one shows the lock';
    end if;
    perform apply_for_org('Troisième 68', 'troisieme-68', 'retail');
end $$;
commit;
-- An employee of a Free shop owns nothing: no lock, and a first business.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '68686868-0000-0000-0000-000000000005';
do $$ begin
    if (org_progress('68000000-0000-0000-0000-000000000005') -> 'locks' ->> 'second_business')::boolean then
        raise exception 'FAIL: an employee who owns nothing is shown the lock';
    end if;
    perform apply_for_org('Commis 68', 'commis-68', 'association');
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '68686868-0000-0000-0000-000000000007';
do $$ begin
    if path_locked('68000000-0000-0000-0000-000000000001', 'second_business') then
        raise exception 'FAIL: Mara''s admin is shown the lock';
    end if;
    perform apply_for_org('Mara 68', 'mara-68', 'association');
end $$;
commit;
do $$ begin
    -- No caller: the business's own plan.
    if not path_locked('68000000-0000-0000-0000-000000000001', 'second_business')
       or path_locked('68000000-0000-0000-0000-000000000003', 'second_business') then
        raise exception 'FAIL: with no caller the lock does not follow the plan';
    end if;
    if (select count(*) from org_applications
         where slug in ('club-68-bis', 'troisieme-68', 'commis-68', 'mara-68')) <> 4 then
        raise exception 'FAIL: an application that passes was not recorded';
    end if;
    raise notice 'PASS: Pro on any owned business, a first business, an employee and Mara pass';
end $$;

\echo ''
\echo '--- TEST 3: nothing else locks for an association ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '68686868-0000-0000-0000-000000000001';
do $$
declare v_debt uuid;
begin
    perform create_invoice('68000000-0000-0000-0000-000000000001', 'Mairie',
        '[{"description": "Location de salle", "quantity": 1, "unit_price": 25000}]'::jsonb);
    v_debt := record_credit_sale('68000000-0000-0000-0000-000000000001', 'Awa', 5000,
                                 'Cotisation de mars');
    if v_debt is null then
        raise exception 'FAIL: the association''s carnet took no debt';
    end if;
    if path_state('68000000-0000-0000-0000-000000000001') is not null then
        raise exception 'FAIL: an association is on Le Chemin';
    end if;
end $$;
commit;
do $$ begin
    if check_unlocks('68000000-0000-0000-0000-000000000001') <> 0
       or exists (select 1 from notifications
                   where org_id = '68000000-0000-0000-0000-000000000001' and kind = 'unlock') then
        raise exception 'FAIL: an association was told a tool unlocked';
    end if;
    raise notice 'PASS: invoices and the carnet stay open, no path, no unlock';
end $$;

\echo ''
\echo '--- TEST 4: a booking rings the treasurer; the customer hears each status ---'
create temp table t68 (which text primary key, id uuid);
grant all on t68 to authenticated;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '68686868-0000-0000-0000-000000000002';
do $$ begin
    insert into t68 values ('book', place_order('entraide-68',
        jsonb_build_array(jsonb_build_object(
            'product_id', (select id from storefront_products('entraide-68')),
            'quantity', 1)),
        'pickup', 'Lundi 18 h'));
    insert into t68 values ('later', place_order('entraide-68',
        jsonb_build_array(jsonb_build_object(
            'product_id', (select id from storefront_products('entraide-68')),
            'quantity', 2)),
        'pickup', 'Mardi 18 h'));
end $$;
commit;
do $$
declare n notifications%rowtype;
begin
    select * into n from notifications
     where recipient_id = '68686868-0000-0000-0000-000000000001' and kind = 'new_order'
       and params ->> 'order_id' = (select id::text from t68 where which = 'book');
    if not found then
        raise exception 'FAIL: the treasurer was not told of the booking';
    end if;
    if n.message not like 'Nouvelle demande de Awa : %'
       or n.org_id <> '68000000-0000-0000-0000-000000000001'
       or n.params ->> 'to' <> 'shop' or not (n.params ->> 'booking')::boolean
       or n.params ->> 'name' <> 'Awa' or (n.params ->> 'total')::numeric <> 2000
       or n.params ->> 'currency' <> 'XOF' or (n.params ->> 'wave')::boolean
       or n.params -> 'fee' <> 'null'::jsonb then
        raise exception 'FAIL: the booking''s bell reads % / %', n.message, n.params;
    end if;
end $$;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '68686868-0000-0000-0000-000000000001';
select decide_order((select id from t68 where which = 'book'), 'accepted');
select decide_order((select id from t68 where which = 'book'), 'picked_up');
select decide_order((select id from t68 where which = 'later'), 'refused');
commit;
do $$
declare v_got text;
begin
    select string_agg(n.kind || '=' || (n.params ->> 'status') || ':' || n.message, ' | '
                      order by n.created_at, n.kind)
      into v_got
      from notifications n
     where n.recipient_id = '68686868-0000-0000-0000-000000000002'
       and n.params ->> 'to' = 'customer' and (n.params ->> 'booking')::boolean
       and n.params ->> 'shop' = 'Entraide 68';
    if v_got is distinct from
       'order_accepted=accepted:Votre réservation chez Entraide 68 : acceptée'
       || ' | order_picked_up=picked_up:Votre réservation chez Entraide 68 : terminée'
       || ' | order_refused=refused:Votre réservation chez Entraide 68 : refusée' then
        raise exception 'FAIL: the customer heard %', v_got;
    end if;
    raise notice 'PASS: the treasurer hears the demande, the customer each status, with the facts';
end $$;

\echo ''
\echo '--- TEST 5: a customer who cancels is heard ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '68686868-0000-0000-0000-000000000002';
do $$ begin
    insert into t68 values ('gone', place_order('entraide-68',
        jsonb_build_array(jsonb_build_object(
            'product_id', (select id from storefront_products('entraide-68')),
            'quantity', 1)),
        'pickup', 'Jeudi 18 h'));
    perform cancel_order((select id from t68 where which = 'gone'));
    -- Answered already: no second cancellation, no second bell.
    begin
        perform cancel_order((select id from t68 where which = 'book'));
        raise exception 'FAIL: a finished booking was cancelled';
    exception when others then
        if sqlerrm not like 'This order can no longer be cancelled%' then raise; end if;
    end;
end $$;
commit;
do $$
declare n notifications%rowtype;
begin
    select * into n from notifications
     where recipient_id = '68686868-0000-0000-0000-000000000001' and kind = 'order_withdrawn';
    if not found or n.message <> 'Awa a annulé sa demande'
       or n.params ->> 'order_id' <> (select id::text from t68 where which = 'gone')
       or not (n.params ->> 'booking')::boolean or n.params ->> 'to' <> 'shop' then
        raise exception 'FAIL: the cancellation rang % / %', n.message, n.params;
    end if;
    if (select count(*) from notifications where kind = 'order_withdrawn'
         and org_id = '68000000-0000-0000-0000-000000000001') <> 1 then
        raise exception 'FAIL: the cancellation rang more than once';
    end if;
    raise notice 'PASS: « Awa a annulé sa demande », once, with the order';
end $$;

\echo ''
\echo '--- TEST 6: low stock, a member joining, a credit settled carry their facts ---'
insert into products (org_id, name, sale_price, quantity, low_stock_at, is_active)
values (:shop, 'Savon', 250, 10, 5, true);
update products set quantity = 3 where org_id = :shop and name = 'Savon';
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
values (:assoc, :joiner, 'employee', 'org', :assoc, 'full');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '68686868-0000-0000-0000-000000000001';
do $$
declare v_debt uuid := (select id from debts
                         where org_id = '68000000-0000-0000-0000-000000000001' limit 1);
begin
    perform record_debt_payment(v_debt, 5000);
end $$;
commit;
do $$
declare v_stock jsonb; v_join jsonb; v_debt jsonb;
begin
    select params into v_stock from notifications
     where recipient_id = '68686868-0000-0000-0000-000000000006' and kind = 'low_stock';
    select params into v_join from notifications
     where recipient_id = '68686868-0000-0000-0000-000000000001' and kind = 'member_joined';
    select params into v_debt from notifications
     where recipient_id = '68686868-0000-0000-0000-000000000001' and kind = 'debt_settled';
    if v_stock ->> 'product_id' is distinct from
           (select id::text from products where org_id = '68000000-0000-0000-0000-000000000005' and name = 'Savon')
       or v_stock ->> 'name' <> 'Savon' or (v_stock ->> 'quantity')::numeric <> 3 then
        raise exception 'FAIL: low stock carries %', v_stock;
    end if;
    if v_join ->> 'who' <> 'Bénévole' or v_join ->> 'org' <> 'Entraide 68' then
        raise exception 'FAIL: the member joining carries %', v_join;
    end if;
    if v_debt ->> 'customer_id' is distinct from
           (select customer_id::text from debts where org_id = '68000000-0000-0000-0000-000000000001' limit 1)
       or v_debt ->> 'customer' <> 'Awa' or (v_debt ->> 'amount')::numeric <> 5000 then
        raise exception 'FAIL: the credit settled carries %', v_debt;
    end if;
    raise notice 'PASS: the article, the member and the customer ride with their bells';
end $$;

\echo ''
\echo '--- TEST 7: every bell a business or a person hears gives its params ---'
-- The platform's own (an application, a spot to approve, the message the
-- platform typed) are French text for Mara's admins, and the fan-outs
-- themselves pass params through.
do $$
declare v_bare text;
begin
    select string_agg(p.proname, ', ' order by p.proname) into v_bare
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and (p.prosrc ~ 'insert into notifications' or p.prosrc ~ 'perform notify_org_admins')
       and p.prosrc !~ 'jsonb_build_object\(''(to|device)'''
       and p.proname not in ('notify_org_admins', 'notify_platform_spot',
                             'trg_notify_org_application', 'send_platform_message');
    if v_bare is not null then
        raise exception 'FAIL: these ring a bell without its params: %', v_bare;
    end if;
    raise notice 'PASS: every business and personal bell carries its params';
end $$;

\echo ''
\echo '--- TEST 8: the recipient reads the facts; nobody rings a bell by hand ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '68686868-0000-0000-0000-000000000002';
do $$
declare v_state text;
begin
    if (select count(*) from notifications where params ->> 'to' = 'customer') <> 3
       or exists (select 1 from notifications
                   where recipient_id <> '68686868-0000-0000-0000-000000000002') then
        raise exception 'FAIL: the customer does not read exactly their own bells';
    end if;
    begin
        perform notify_org_admins('68000000-0000-0000-0000-000000000001', 'platform_message',
                                  'Kaj : envoyez 10 000 F à ce numéro');
        raise exception 'FAIL: a signed-in person rang an association''s bell';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        get stacked diagnostics v_state = returned_sqlstate;
        if v_state <> '42501' then raise; end if;
    end;
    begin
        perform notify_org_admins('68000000-0000-0000-0000-000000000001', 'new_order',
                                  'Faux', '{}'::jsonb);
        raise exception 'FAIL: a signed-in person rang a bell with params';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        get stacked diagnostics v_state = returned_sqlstate;
        if v_state <> '42501' then raise; end if;
    end;
    begin
        perform notify_platform_spot('spot_paid', 'Faux');
        raise exception 'FAIL: a signed-in person rang the platform''s bell';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        get stacked diagnostics v_state = returned_sqlstate;
        if v_state <> '42501' then raise; end if;
    end;
end $$;
commit;
do $$ begin
    if has_function_privilege('anon', 'notify_org_admins(uuid, text, text, uuid)', 'execute')
       or has_function_privilege('authenticated', 'notify_org_admins(uuid, text, text, uuid)', 'execute')
       or has_function_privilege('authenticated', 'notify_org_admins(uuid, text, text, jsonb, uuid)', 'execute')
       or has_function_privilege('authenticated', 'notify_platform_spot(text, text)', 'execute')
       or has_function_privilege('authenticated', 'second_business_locked(uuid)', 'execute')
       or has_function_privilege('anon', 'second_business_locked(uuid)', 'execute') then
        raise exception 'FAIL: a bell or the lock is open to an app role';
    end if;
    if exists (select 1 from notifications where message like 'Faux%' or message like '%10 000 F%') then
        raise exception 'FAIL: a hand-rung bell landed';
    end if;
    raise notice 'PASS: the recipient reads their facts; only the server rings';
end $$;

\echo ''
\echo 'test_association_fixes: all passed'
