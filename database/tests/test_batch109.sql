-- ============================================================
-- test_batch109.sql — a number proved on WhatsApp before an order (109).
-- Phone block 109.
--
-- The claims, for a shop, a farm and an association (its services,
-- booked) alike:
--   * installed, the switch order_phone_verified is off, and placing an
--     order or a booking is what 101 made it — answer for answer, refusal
--     for refusal, the number kept and the bell rung (P1: 101's function
--     put back in the same transaction and the same orders placed again);
--   * Réglages lists the switch; only the platform turns it, oui or non
--     only, journaled, « Annuler » puts it back;
--   * on, an account with no proved number — none at all, or one typed
--     but never proved — is refused « Vérifiez d'abord votre numéro
--     WhatsApp » and nothing is written; a proved account orders and
--     books, and the order carries the proved number written « +226… »,
--     whatever was typed on the sheet; signing in is still asked first;
--   * order_phone_gate() tells the signed-in caller the switch and their
--     own number, and is closed to the street; the two helpers are
--     nobody's to call; place_order stays a signed-in person's door.
-- ============================================================
\set ON_ERROR_STOP on

\set mara    '''10910910-0000-0000-0000-000000000001'''
\set sowner  '''10910910-0000-0000-0000-000000000002'''
\set fowner  '''10910910-0000-0000-0000-000000000003'''
\set aowner  '''10910910-0000-0000-0000-000000000004'''
\set buyer   '''10910910-0000-0000-0000-000000000005'''
\set proved  '''10910910-0000-0000-0000-000000000006'''
\set typed   '''10910910-0000-0000-0000-000000000007'''
\set shop    '''10900000-0000-0000-0000-000000000001'''
\set farm    '''10900000-0000-0000-0000-000000000002'''
\set assoc   '''10900000-0000-0000-0000-000000000003'''

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
-- Earlier suites re-apply older migrations over 109's place_order (101's,
-- 099's) and hand the app's roles every function: 109 again, so what
-- follows tests its own definitions and its own doors.
\i database/migrations/109_shopper_order_gate.sql

-- The street's minimums, as 101's suite sets them: one article is a vitrine.
update platform_settings set value = '1'
 where key in ('vitrine_min_items', 'vitrine_min_items_association');

insert into auth.users (id, phone, email, raw_user_meta_data, phone_confirmed_at) values
    (:mara,   '+22610900001', 'mara109@example.com',   '{"full_name": "Mara Cent-Neuf"}',     null),
    (:sowner, '+22610900002', 'awa109@example.com',    '{"full_name": "Awa Boutique109"}',    null),
    (:fowner, '+22610900003', null,                    '{"full_name": "Ignace Ferme109"}',    null),
    (:aowner, '+22610900004', null,                    '{"full_name": "Israël Entraide109"}', null),
    -- A shopper signed in with Google: an e-mail, no number at all.
    (:buyer,  null,           'cliente109@example.com', '{"full_name": "Cliente Cent-Neuf"}', null),
    -- Proved on WhatsApp: Supabase keeps the number without its +.
    (:proved, '22670109006',  'prouve109@example.com', '{"full_name": "Client Prouvé"}',      now()),
    -- A number on the account, never proved.
    (:typed,  '+22670109007', 'tape109@example.com',   '{"full_name": "Client Tapé"}',        null);
update profiles set is_platform_admin = true where id = :mara;
-- The number the profile form saved: what 101 falls back on.
update profiles set phone = '+22670109055' where id = :buyer;
insert into orgs (id, name, slug, profile, default_currency, plan, storefront_enabled, storefront_blurb) values
    (:shop,  'Boutique Cent-Neuf', 'boutique-109', 'retail',      'XOF', 'free', true, 'Bienvenue'),
    (:farm,  'Ferme Cent-Neuf',    'ferme-109',    'farm',        'XOF', 'free', true, 'Bienvenue'),
    (:assoc, 'Entraide Cent-Neuf', 'entraide-109', 'association', 'XOF', 'free', true, 'Bienvenue');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :sowner, 'owner', 'org', :shop,  'full'),
    (:farm,  :fowner, 'owner', 'org', :farm,  'full'),
    (:assoc, :aowner, 'owner', 'org', :assoc, 'full');
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published) values
    ('109aaaaa-0000-0000-0000-000000000001', :shop, 'Savon 109',  500, 300, 5,  true, true),
    ('109aaaaa-0000-0000-0000-000000000002', :farm, 'Œufs 109',  2500,   0, 10, true, true);
insert into products (id, org_id, name, sale_price, is_service, is_active, is_published) values
    ('109aaaaa-0000-0000-0000-000000000003', :assoc, 'Consultation 109', 1000, true, true, true);

-- One order tried and taken back: what it wrote (the order, its lines,
-- the bell) or how it was refused. Run as the database's owner with the
-- caller named the way PostgREST names them; the doors are tested below.
create or replace function pg_temp.t109_try(
    p_who uuid, p_slug text, p_lines jsonb, p_fulfilment text default 'pickup',
    p_note text default null, p_phone text default null)
returns jsonb
language plpgsql
as $$
declare
    v_id  uuid;
    v_out jsonb;
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true);
    begin
        v_id := place_order(p_slug, p_lines, p_fulfilment, p_note, null, p_phone);
        select jsonb_build_object(
                   'order', to_jsonb(o) - 'id' - 'created_at' - 'updated_at' - 'handover_code',
                   'lines', (select jsonb_agg(to_jsonb(l) - 'id' - 'order_id' order by l.name)
                               from order_lines l where l.order_id = v_id),
                   'bell',  (select jsonb_agg(jsonb_build_object('to', n.recipient_id, 'kind', n.kind,
                                                                 'message', n.message) order by n.recipient_id)
                               from notifications n
                              where n.kind = 'new_order' and n.created_at >= now()))
          into v_out
          from orders o where o.id = v_id;
        raise exception using errcode = 'P0109', message = 'taken back';
    exception
        when sqlstate 'P0109' then return v_out;
        when others then return jsonb_build_object('refused', sqlerrm, 'state', sqlstate);
    end;
end;
$$;

-- Every case, for the three kinds: kept, fallen back on, booked, and the
-- refusals each rule makes.
create or replace function pg_temp.t109_cases()
returns table (label text, outcome jsonb)
language sql
as $$
    select * from (values
        ('shop, a number typed', pg_temp.t109_try('10910910-0000-0000-0000-000000000005', 'boutique-109',
            '[{"product_id":"109aaaaa-0000-0000-0000-000000000001","quantity":2}]', 'pickup', 'Vers midi', '70 10 90 00')),
        ('farm, the profile''s number', pg_temp.t109_try('10910910-0000-0000-0000-000000000005', 'ferme-109',
            '[{"product_id":"109aaaaa-0000-0000-0000-000000000002","quantity":3}]')),
        ('association, a booking', pg_temp.t109_try('10910910-0000-0000-0000-000000000005', 'entraide-109',
            '[{"product_id":"109aaaaa-0000-0000-0000-000000000003","quantity":1}]', 'pickup', 'Samedi 10 h')),
        ('proved shopper, typed', pg_temp.t109_try('10910910-0000-0000-0000-000000000006', 'boutique-109',
            '[{"product_id":"109aaaaa-0000-0000-0000-000000000001","quantity":1}]', 'pickup', null, '70 00 00 01')),
        ('typed shopper', pg_temp.t109_try('10910910-0000-0000-0000-000000000007', 'ferme-109',
            '[{"product_id":"109aaaaa-0000-0000-0000-000000000002","quantity":1}]')),
        ('a booking with no day', pg_temp.t109_try('10910910-0000-0000-0000-000000000005', 'entraide-109',
            '[{"product_id":"109aaaaa-0000-0000-0000-000000000003","quantity":1}]')),
        ('more than is left', pg_temp.t109_try('10910910-0000-0000-0000-000000000005', 'boutique-109',
            '[{"product_id":"109aaaaa-0000-0000-0000-000000000001","quantity":9}]')),
        ('no such vitrine', pg_temp.t109_try('10910910-0000-0000-0000-000000000005', 'nulle-part-109',
            '[{"product_id":"109aaaaa-0000-0000-0000-000000000001","quantity":1}]')),
        ('signed out', pg_temp.t109_try(null, 'boutique-109',
            '[{"product_id":"109aaaaa-0000-0000-0000-000000000001","quantity":1}]'))
    ) c(label, outcome);
$$;

\echo ''
\echo '--- TEST 1: installed, the switch is off, and ordering is what 101 made it (P1, the three kinds) ---'
begin;
create temporary table t109_p1 (version text, label text, outcome jsonb) on commit drop;
do $$
begin
    if (select value from platform_settings where key = 'order_phone_verified') <> 'false'::jsonb then
        raise exception 'FAIL: the switch is not installed off';
    end if;
end $$;
insert into t109_p1 select '109', * from pg_temp.t109_cases();
-- 101's place_order put back, in this transaction only.
\i database/migrations/101_stock_farm_analytics.sql
insert into t109_p1 select '101', * from pg_temp.t109_cases();
do $$
declare
    r record;
    n int := 0;
begin
    for r in select a.label, a.outcome as now_, b.outcome as before_
               from t109_p1 a join t109_p1 b on b.label = a.label and b.version = '101'
              where a.version = '109' loop
        n := n + 1;
        if r.now_ is distinct from r.before_ then
            raise exception 'FAIL: « % » differs from 101: % instead of %', r.label, r.now_, r.before_;
        end if;
    end loop;
    if n <> 9 then
        raise exception 'FAIL: % cases compared, 9 expected', n;
    end if;
    -- And the cases are what they say: placed, kept, refused.
    if (select outcome #>> '{order,phone}' from t109_p1 where version = '109' and label = 'shop, a number typed') <> '70 10 90 00'
       or (select outcome #>> '{order,phone}' from t109_p1 where version = '109' and label = 'farm, the profile''s number') <> '+22670109055'
       or (select outcome #>> '{lines,0,is_service}' from t109_p1 where version = '109' and label = 'association, a booking') <> 'true'
       or (select jsonb_array_length(outcome -> 'bell') from t109_p1 where version = '109' and label = 'shop, a number typed') <> 1
       or (select outcome ->> 'refused' from t109_p1 where version = '109' and label = 'a booking with no day') <> 'Indiquez la date et l''heure souhaitées'
       or (select outcome ->> 'state' from t109_p1 where version = '109' and label = 'more than is left') <> 'MA001'
       or (select outcome ->> 'refused' from t109_p1 where version = '109' and label = 'no such vitrine') <> 'This shop is not taking orders'
       or (select outcome ->> 'refused' from t109_p1 where version = '109' and label = 'signed out') <> 'Sign in to order' then
        raise exception 'FAIL: the cases are not what they claim: %',
            (select jsonb_object_agg(label, outcome) from t109_p1 where version = '109');
    end if;
    raise notice 'PASS: off as installed — a shop, a farm and an association booking ordered, kept and refused exactly as 101 did (9 cases)';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: Réglages lists the switch; only the platform turns it, oui or non, journaled and undone ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '10910910-0000-0000-0000-000000000002';
do $$
begin
    begin
        perform platform_set_setting('order_phone_verified', 'true');
        raise exception 'FAIL: a shop owner turned the platform''s switch';
    exception when others then
        if sqlerrm <> 'Réservé à la plateforme' then raise; end if;
    end;
    raise notice 'PASS: a business owner is refused, in French';
end $$;
set local "request.jwt.claim.sub" = '10910910-0000-0000-0000-000000000001';
do $$
declare
    v_action uuid;
begin
    if platform_settings_board() -> 'order_phone_verified' ->> 'value' <> 'false' then
        raise exception 'FAIL: Réglages does not list the switch off';
    end if;
    begin
        perform platform_set_setting('order_phone_verified', '1');
        raise exception 'FAIL: the switch took a number';
    exception when others then
        if sqlerrm <> 'Ce réglage attend oui ou non.' then raise; end if;
    end;
    v_action := platform_set_setting('order_phone_verified', 'true');
    if v_action is null
       or platform_settings_board() -> 'order_phone_verified' ->> 'value' <> 'true'
       or not exists (select 1 from platform_actions_page(null, 50, null) a
                       where a.id = v_action) then
        raise exception 'FAIL: the switch was not turned on and journaled';
    end if;
    perform platform_undo(v_action);
    if platform_settings_board() -> 'order_phone_verified' ->> 'value' <> 'false' then
        raise exception 'FAIL: « Annuler » did not put the switch back off';
    end if;
    raise notice 'PASS: the platform turns it (oui/non only), the journal keeps it, « Annuler » puts it back';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: on — no proved number, no order nor booking; a proved one orders with that number ---'
begin;
update platform_settings set value = 'true' where key = 'order_phone_verified';
create temporary table t109_on (label text, outcome jsonb) on commit drop;
insert into t109_on select * from pg_temp.t109_cases();
do $$
declare
    v_refused constant text := 'Vérifiez d''abord votre numéro WhatsApp';
    v_out jsonb;
begin
    -- No number at all (the Google shopper), at a shop, a farm, an association.
    if (select outcome ->> 'refused' from t109_on where label = 'shop, a number typed') <> v_refused
       or (select outcome ->> 'refused' from t109_on where label = 'farm, the profile''s number') <> v_refused
       or (select outcome ->> 'refused' from t109_on where label = 'association, a booking') <> v_refused then
        raise exception 'FAIL: an account with no proved number ordered: %',
            (select jsonb_object_agg(label, outcome) from t109_on);
    end if;
    -- A number on the account, never proved: refused the same.
    if (select outcome ->> 'refused' from t109_on where label = 'typed shopper') <> v_refused then
        raise exception 'FAIL: a number never proved was taken for proved';
    end if;
    -- The proved number is the order's, written « +226… », not what was typed.
    if (select outcome #>> '{order,phone}' from t109_on where label = 'proved shopper, typed') <> '+22670109006'
       or (select outcome #>> '{order,status}' from t109_on where label = 'proved shopper, typed') <> 'pending' then
        raise exception 'FAIL: the proved shopper''s order: %',
            (select outcome from t109_on where label = 'proved shopper, typed');
    end if;
    -- Signing in is still asked first.
    if (select outcome ->> 'refused' from t109_on where label = 'signed out') <> 'Sign in to order' then
        raise exception 'FAIL: a stranger was asked for a number before signing in';
    end if;
    -- A proved shopper books at the association and orders at the farm.
    v_out := pg_temp.t109_try('10910910-0000-0000-0000-000000000006', 'entraide-109',
        '[{"product_id":"109aaaaa-0000-0000-0000-000000000003","quantity":1}]', 'pickup', 'Lundi 9 h');
    if v_out #>> '{order,phone}' <> '+22670109006' or v_out #>> '{lines,0,is_service}' <> 'true' then
        raise exception 'FAIL: the proved shopper''s booking: %', v_out;
    end if;
    v_out := pg_temp.t109_try('10910910-0000-0000-0000-000000000006', 'ferme-109',
        '[{"product_id":"109aaaaa-0000-0000-0000-000000000002","quantity":2}]');
    if v_out #>> '{order,phone}' <> '+22670109006' then
        raise exception 'FAIL: the proved shopper''s farm order: %', v_out;
    end if;
    -- The other rules still speak, after the number: a booking needs its day.
    v_out := pg_temp.t109_try('10910910-0000-0000-0000-000000000006', 'entraide-109',
        '[{"product_id":"109aaaaa-0000-0000-0000-000000000003","quantity":1}]');
    if v_out ->> 'refused' <> 'Indiquez la date et l''heure souhaitées' then
        raise exception 'FAIL: a proved booking with no day: %', v_out;
    end if;
    raise notice 'PASS: on — refused with no proved number (none, or typed and never proved) at a shop, a farm and an association; a proved shopper orders and books with « +22670109006 »; sign-in first, the other rules after';
end $$;
-- Nothing of a refused order is left behind.
do $$
begin
    if exists (select 1 from orders where customer_id in ('10910910-0000-0000-0000-000000000005',
                                                          '10910910-0000-0000-0000-000000000007')) then
        raise exception 'FAIL: a refused order left a row';
    end if;
    raise notice 'PASS: a refused order writes nothing';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: order_phone_gate() tells the caller the switch and their own number ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '10910910-0000-0000-0000-000000000005';
do $$
declare v jsonb := order_phone_gate();
begin
    if v <> jsonb_build_object('required', false, 'verified', false, 'phone', null) then
        raise exception 'FAIL: off, the Google shopper reads %', v;
    end if;
    raise notice 'PASS: off — not asked';
end $$;
reset role;
update platform_settings set value = 'true' where key = 'order_phone_verified';
set local role authenticated;
do $$
declare v jsonb := order_phone_gate();
begin
    if v <> jsonb_build_object('required', true, 'verified', false, 'phone', null) then
        raise exception 'FAIL: on, the Google shopper reads %', v;
    end if;
end $$;
set local "request.jwt.claim.sub" = '10910910-0000-0000-0000-000000000007';
do $$
declare v jsonb := order_phone_gate();
begin
    if v <> jsonb_build_object('required', true, 'verified', false, 'phone', null) then
        raise exception 'FAIL: a number never proved reads %', v;
    end if;
end $$;
set local "request.jwt.claim.sub" = '10910910-0000-0000-0000-000000000006';
do $$
declare v jsonb := order_phone_gate();
begin
    if v <> jsonb_build_object('required', true, 'verified', true, 'phone', '+22670109006') then
        raise exception 'FAIL: the proved shopper reads %', v;
    end if;
    raise notice 'PASS: on — asked; no number and a number never proved read « not verified »; a proved one reads its number';
end $$;
set local "request.jwt.claim.sub" = '';
do $$
begin
    begin
        perform order_phone_gate();
        raise exception 'FAIL: nobody signed in got an answer';
    exception when others then
        if sqlerrm <> 'Connectez-vous pour commander' then raise; end if;
    end;
    raise notice 'PASS: without a sign-in, « Connectez-vous pour commander »';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: the doors — the gate and the order for a signed-in person, the helpers for nobody, the street for neither ---'
do $$
begin
    if has_function_privilege('anon', 'order_phone_gate()', 'execute')
       or has_function_privilege('anon', 'place_order(text, jsonb, text, text, text, text, text, double precision, double precision)', 'execute')
       or has_function_privilege('anon', 'order_phone_required()', 'execute')
       or has_function_privilege('anon', 'my_verified_phone()', 'execute') then
        raise exception 'FAIL: the street can call an order door';
    end if;
    if has_function_privilege('authenticated', 'order_phone_required()', 'execute')
       or has_function_privilege('authenticated', 'my_verified_phone()', 'execute') then
        raise exception 'FAIL: a helper is open to the app';
    end if;
    if not has_function_privilege('authenticated', 'order_phone_gate()', 'execute')
       or not has_function_privilege('authenticated', 'place_order(text, jsonb, text, text, text, text, text, double precision, double precision)', 'execute') then
        raise exception 'FAIL: a signed-in person cannot ask or order';
    end if;
    -- The switch is read where the order is placed (no dead switch).
    if not exists (select 1 from pg_proc where proname = 'place_order' and prosrc like '%order_phone_required()%')
       or not exists (select 1 from pg_proc where proname = 'order_phone_required' and prosrc like '%''order_phone_verified''%') then
        raise exception 'FAIL: place_order does not read the switch';
    end if;
    raise notice 'PASS: gate and order for the signed-in only; helpers closed; the switch read by place_order';
end $$;
begin;
set local role anon;
do $$
begin
    begin
        perform order_phone_gate();
        raise exception 'FAIL: the street asked the gate';
    exception when insufficient_privilege then null;
    end;
    raise notice 'PASS: the street is refused at the gate';
end $$;
rollback;

\echo ''
\echo 'test_batch109: done'
