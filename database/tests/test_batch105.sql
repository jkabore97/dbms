-- ============================================================
-- test_batch105.sql — Mara's command center (105). Phone block 105.
--
-- The claims, for a shop, a farm and an association alike: only the
-- platform reads « À faire », searches the platform, acts on several
-- businesses at once or changes a setting — anybody else is refused in
-- French, a stranger at the door; the undos are nobody's to call but
-- platform_undo's. « À faire » counts what waits and what ends within 7
-- days, and each count's rows are listed. One search finds a business by
-- its name, its address or its owner's phone typed with spaces, a person
-- by e-mail, an order by the start of its number or its customer. Several
-- businesses at once: cauris (and cauris before a date), a tool until a
-- date, a message, an archive, a restore — each business one journal
-- line, one refused (a vitrine d'exemple gets no cauris) never stopping
-- the others; each undone where it can be (cauris taken back — never
-- more than is left, refused once spent — a tool back as it was, an
-- archive restored), a message never; an undo twice is refused. Réglages:
-- every setting but the markers, changed only with a value of its own
-- type, logged with before and after, undone unless changed since — the
-- two-step switch (078) included; every key the app's Réglages lists is
-- read by the server (no dead switch). And 105 itself changes nothing a
-- business or a vitrine shows.
-- ============================================================
\set ON_ERROR_STOP on

\set mara    '''10510510-0000-0000-0000-000000000001'''
\set sowner  '''10510510-0000-0000-0000-000000000002'''
\set fowner  '''10510510-0000-0000-0000-000000000003'''
\set aowner  '''10510510-0000-0000-0000-000000000004'''
\set cust    '''10510510-0000-0000-0000-000000000005'''
\set rider   '''10510510-0000-0000-0000-000000000006'''
\set shop    '''10500000-0000-0000-0000-000000000001'''
\set farm    '''10500000-0000-0000-0000-000000000002'''
\set assoc   '''10500000-0000-0000-0000-000000000003'''
\set show    '''10500000-0000-0000-0000-000000000004'''
\set quiet   '''10500000-0000-0000-0000-000000000005'''

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
-- Earlier suites hand the app's roles every function; 104 and 105 again,
-- so what follows tests their own doors.
\i database/migrations/104_feature_switchboard.sql
\i database/migrations/105_command_center.sql

insert into auth.users (id, phone, email, raw_user_meta_data) values
    (:mara,   '+22610500001', 'mara105@example.com',   '{"full_name": "Mara Cent-Cinq"}'),
    (:sowner, '+22670105002', 'awa105@example.com',    '{"full_name": "Awa Boutique105"}'),
    (:fowner, '+22610500003', null,                    '{"full_name": "Ignace Ferme105"}'),
    (:aowner, '+22610500004', null,                    '{"full_name": "Israël Entraide105"}'),
    (:cust,   '+22610500005', 'client105@example.com', '{"full_name": "Cliente Cent-Cinq"}'),
    (:rider,  '+22610500006', null,                    '{"full_name": "Livreur105"}');
update profiles set is_platform_admin = true where id = :mara;
insert into orgs (id, name, slug, profile, default_currency, plan, plan_until, showcase, last_activity_at, phone) values
    (:shop,  'Boutique Cent-Cinq', 'boutique-105', 'retail',      'XOF', 'pro',  null,             false, now(), '+226 70 99 10 50'),
    (:farm,  'Ferme Cent-Cinq',    'ferme-105',    'farm',        'XOF', 'free', null,             false, now(), null),
    (:assoc, 'Entraide Cent-Cinq', 'entraide-105', 'association', 'XOF', 'free', null,             false, now(), null),
    (:show,  'Exemple Cent-Cinq',  'exemple-105',  'retail',      'XOF', 'free', null,             true,  now(), null),
    (:quiet, 'Endormie Cent-Cinq', 'endormie-105', 'retail',      'XOF', 'free', null,             false, now() - interval '40 days', null);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :sowner, 'owner', 'org', :shop,  'full'),
    (:farm,  :fowner, 'owner', 'org', :farm,  'full'),
    (:assoc, :aowner, 'owner', 'org', :assoc, 'full'),
    (:quiet, :sowner, 'owner', 'org', :quiet, 'full');
-- Three open vitrines with something on the shelf, for TEST 8.
update orgs set storefront_enabled = true, storefront_blurb = 'Bienvenue'
 where id in (:shop, :farm, :assoc);
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
select o, 'Article 105', 1000, 10, true, true from unnest(array[:shop, :farm, :assoc]::uuid[]) o;

\echo ''
\echo '--- TEST 1: only the platform — a shop, a farm, an association owner refused in French; a stranger at the door ---'
do $$
declare
    who uuid;
    v_state text;
begin
    foreach who in array array['10510510-0000-0000-0000-000000000002',
                               '10510510-0000-0000-0000-000000000003',
                               '10510510-0000-0000-0000-000000000004']::uuid[] loop
        perform set_config('request.jwt.claim.sub', who::text, true);
        execute 'set local role authenticated';
        begin perform platform_todo();
              raise exception 'FAIL: an owner read À faire';
        exception when others then
            if sqlerrm <> 'Réservé à la plateforme' then raise; end if;
        end;
        begin perform platform_todo_list('silent_30');
              raise exception 'FAIL: an owner listed the silent businesses';
        exception when others then
            if sqlerrm <> 'Réservé à la plateforme' then raise; end if;
        end;
        begin perform platform_search('Cent');
              raise exception 'FAIL: an owner searched the platform';
        exception when others then
            if sqlerrm <> 'Réservé à la plateforme' then raise; end if;
        end;
        begin perform platform_bulk('cauris', array['10500000-0000-0000-0000-000000000001']::uuid[],
                                    '{"points": 1000}');
              raise exception 'FAIL: an owner gave themself cauris';
        exception when others then
            if sqlerrm <> 'Réservé à la plateforme' then raise; end if;
        end;
        begin perform platform_settings_board();
              raise exception 'FAIL: an owner read the platform settings';
        exception when others then
            if sqlerrm <> 'Réservé à la plateforme' then raise; end if;
        end;
        begin perform platform_set_setting('pro_price_month', '1');
              raise exception 'FAIL: an owner set the Pro price';
        exception when others then
            if sqlerrm <> 'Réservé à la plateforme' then raise; end if;
        end;
        -- The undos are not a door: only platform_undo calls them.
        begin perform platform_undo_archive('{"org_id": "10500000-0000-0000-0000-000000000001"}');
              raise exception 'FAIL: an owner called an undo directly';
        exception when insufficient_privilege then null;
        end;
        execute 'reset role';
    end loop;

    if has_function_privilege('authenticated', 'platform_undo_setting(jsonb)', 'execute')
       or has_function_privilege('authenticated', 'platform_undo_cauris(jsonb)', 'execute')
       or has_function_privilege('authenticated', 'platform_undo_unlock(jsonb)', 'execute')
       or has_function_privilege('authenticated', 'platform_undo_restore(jsonb)', 'execute')
       or not has_function_privilege('authenticated', 'platform_bulk(text, uuid[], jsonb)', 'execute')
       or not has_function_privilege('authenticated', 'platform_set_setting(text, jsonb)', 'execute') then
        raise exception 'FAIL: the doors are not as 105 grants them';
    end if;

    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    begin
        perform platform_search('Cent');
        raise exception 'FAIL: a stranger searched the platform';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        get stacked diagnostics v_state = returned_sqlstate;
        if v_state <> '42501' then
            raise exception 'FAIL: platform_search refused a stranger inside (%), not at the door', v_state;
        end if;
    end;
    execute 'reset role';
    raise notice 'PASS: À faire, the search, the bulk acts and the settings refuse an owner of each kind (« Réservé à la plateforme ») and a stranger at the door (42501); the undos are platform_undo''s only';
end $$;

\echo ''
\echo '--- TEST 2: À faire counts what waits and what ends within 7 days; each count lists its rows ---'
do $$
declare
    v0 jsonb;
    v1 jsonb;
    k  text;
    v_list jsonb;
    v_total int;
begin
    perform set_config('request.jwt.claim.sub', '10510510-0000-0000-0000-000000000001', true);
    v0 := platform_todo();

    insert into org_applications (applicant_id, name, slug)
        values ('10510510-0000-0000-0000-000000000005', 'Demande Cent-Cinq', 'demande-105');
    update orgs set plan_until = current_date + 3 where id = '10500000-0000-0000-0000-000000000001';
    insert into plan_requests (org_id, user_id, amount)
        values ('10500000-0000-0000-0000-000000000002', '10510510-0000-0000-0000-000000000003', 2500);
    insert into promotions (org_id, kind, days, status)
        values ('10500000-0000-0000-0000-000000000001', 'shop', 7, 'paid_claimed');
    insert into promotions (org_id, kind, days, status, starts_at, ends_at)
        values ('10500000-0000-0000-0000-000000000001', 'shop', 7, 'approved', now() - interval '4 days', now() + interval '3 days');
    insert into couriers (user_id, phone) values ('10510510-0000-0000-0000-000000000006', '+22610500006');
    insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency, created_at, updated_at)
        values ('10500000-0000-0000-0000-000000000001', '10510510-0000-0000-0000-000000000005',
                'Cliente Cent-Cinq', 'pending', 'pickup', 1500, 'XOF', now() - interval '3 hours', now() - interval '3 hours');
    -- On the road for 4 hours: stuck, as 072 counted it. Collected at the
    -- counter 4 hours ago (« picked_up »): finished, never stuck.
    insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency, created_at, updated_at)
        values ('10500000-0000-0000-0000-000000000001', '10510510-0000-0000-0000-000000000005',
                'Route Cent-Cinq', 'in_transit', 'delivery', 2500, 'XOF', now() - interval '5 hours', now() - interval '4 hours'),
               ('10500000-0000-0000-0000-000000000001', '10510510-0000-0000-0000-000000000005',
                'Retirée Cent-Cinq', 'picked_up', 'pickup', 900, 'XOF', now() - interval '5 hours', now() - interval '4 hours');
    insert into cauris_unlocks (org_id, feature, until, gifted_by)
        values ('10500000-0000-0000-0000-000000000002', 'analytics', now() + interval '3 days',
                '10510510-0000-0000-0000-000000000001');
    insert into cauris_promos (org_id, points, left_points, expires_on, given_by)
        values ('10500000-0000-0000-0000-000000000003', 20, 20, cauris_today() + 3,
                '10510510-0000-0000-0000-000000000001');
    -- A business's own rule that says what is already true, until Friday.
    insert into feature_rules (scope, org_id, feature, state, until)
        values ('org', '10500000-0000-0000-0000-000000000003', 'invoices', 'visible', now() + interval '3 days');
    insert into wave_payments (kind, org_id, amount, status, payout_status, payout_error, paid_at)
        values ('pro', '10500000-0000-0000-0000-000000000001', 2500, 'succeeded', 'failed', 'Numéro refusé', now());

    v1 := platform_todo();
    for k in select unnest(array['applications', 'pro_paid', 'spots_paid', 'couriers',
                                 'plans_ending', 'unlocks_ending', 'promos_ending', 'spots_ending',
                                 'rules_ending', 'payouts_failed']) loop
        if (v1->>k)::int - (v0->>k)::int <> 1 then
            raise exception 'FAIL: À faire % went from % to %', k, v0->>k, v1->>k;
        end if;
    end loop;
    if (v1->>'orders_stuck')::int - (v0->>'orders_stuck')::int <> 2 then
        raise exception 'FAIL: stuck orders went from % to % (a pending one and one on the road, not one collected)',
            v0->>'orders_stuck', v1->>'orders_stuck';
    end if;
    if not platform_todo_list('orders_stuck') @> '[{"customer": "Route Cent-Cinq", "status": "in_transit"}]'
       or platform_todo_list('orders_stuck') @> '[{"customer": "Retirée Cent-Cinq"}]' then
        raise exception 'FAIL: the stuck list is not the waiting and the on-the-road orders';
    end if;

    -- « Silencieuses (30 j) » is the console list's own filter, to the unit.
    select total_count into v_total from search_orgs(p_status => 'active', p_activity => 'silent30', p_limit => 1);
    if (v1->>'silent_30')::int <> coalesce(v_total, 0) then
        raise exception 'FAIL: À faire says % silent, the list % ', v1->>'silent_30', v_total;
    end if;

    v_list := platform_todo_list('silent_30');
    if not v_list @> '[{"org_name": "Endormie Cent-Cinq"}]' then
        raise exception 'FAIL: the silent list misses the quiet shop: %', v_list;
    end if;
    if not platform_todo_list('unlocks_ending') @> '[{"org_name": "Ferme Cent-Cinq", "feature": "analytics", "gift": true}]'
       or not platform_todo_list('promos_ending') @> '[{"org_name": "Entraide Cent-Cinq", "points": 20}]'
       or not platform_todo_list('plans_ending') @> '[{"org_name": "Boutique Cent-Cinq"}]'
       or not platform_todo_list('rules_ending') @> '[{"org_name": "Entraide Cent-Cinq", "feature": "invoices"}]'
       or not platform_todo_list('orders_stuck') @> '[{"customer": "Cliente Cent-Cinq", "status": "pending"}]'
       or not platform_todo_list('payouts_failed') @> '[{"org_name": "Boutique Cent-Cinq", "error": "Numéro refusé"}]'
       or not platform_todo_list('spots_ending') @> '[{"org_name": "Boutique Cent-Cinq", "spot": "shop"}]' then
        raise exception 'FAIL: a count''s rows are not listed';
    end if;
    begin
        perform platform_todo_list('tout');
        raise exception 'FAIL: an unknown list answered';
    exception when others then
        if sqlerrm <> 'Liste inconnue : tout' then raise; end if;
    end;
    -- What the fixtures added goes away again for the suites after this one.
    delete from feature_rules where org_id = '10500000-0000-0000-0000-000000000003';
    delete from cauris_unlocks where org_id = '10500000-0000-0000-0000-000000000002';
    delete from cauris_promos where org_id = '10500000-0000-0000-0000-000000000003';
    raise notice 'PASS: À faire counts a request, a « J''ai payé » (Pro and spot), a courier, stuck orders (waiting 2 h, on the road 3 h — never one collected), and what ends in 7 days (a plan, a tool, promo cauris, a spot, a rule), a failed payout; silent = the list''s filter; each list has its rows';
end $$;

\echo ''
\echo '--- TEST 3: one search — a business by name, address or owner''s phone; a person by e-mail; an order by number or customer ---'
do $$
declare
    v jsonb;
    v_order uuid;
begin
    perform set_config('request.jwt.claim.sub', '10510510-0000-0000-0000-000000000001', true);
    if not (platform_search('cent-cinq')->'businesses') @> '[{"name": "Boutique Cent-Cinq"}, {"name": "Ferme Cent-Cinq"}, {"name": "Entraide Cent-Cinq"}]' then
        raise exception 'FAIL: the three kinds are not found by name';
    end if;
    if not (platform_search('entraide-105')->'businesses') @> '[{"slug": "entraide-105", "profile": "association"}]' then
        raise exception 'FAIL: an association not found by its address';
    end if;
    -- The owner's number, typed as people type it: spaces, no country.
    v := platform_search('70 10 50 02');
    if not (v->'businesses') @> '[{"name": "Boutique Cent-Cinq", "owner": "Awa Boutique105"}]' then
        raise exception 'FAIL: a business not found by its owner''s phone: %', v;
    end if;
    if not (v->'people') @> '[{"name": "Awa Boutique105"}]' then
        raise exception 'FAIL: a person not found by phone';
    end if;
    -- The business's own number too.
    if not (platform_search('99 10 50')->'businesses') @> '[{"name": "Boutique Cent-Cinq"}]' then
        raise exception 'FAIL: a business not found by its phone';
    end if;
    if not (platform_search('client105@example')->'people') @> '[{"email": "client105@example.com"}]' then
        raise exception 'FAIL: a person not found by e-mail';
    end if;
    select id into v_order from orders where org_id = '10500000-0000-0000-0000-000000000001' limit 1;
    if not (platform_search(left(v_order::text, 8))->'orders') @> jsonb_build_array(jsonb_build_object('id', v_order, 'org_name', 'Boutique Cent-Cinq')) then
        raise exception 'FAIL: an order not found by the start of its number';
    end if;
    if not (platform_search('Cliente Cent')->'orders') @> '[{"customer": "Cliente Cent-Cinq"}]' then
        raise exception 'FAIL: an order not found by its customer';
    end if;
    -- A « % » is a character, and one letter is not a search.
    if jsonb_array_length(platform_search('%')->'businesses') <> 0
       or jsonb_array_length(platform_search('_%_')->'businesses') <> 0 then
        raise exception 'FAIL: a « %% » matched everything';
    end if;
    if platform_search('C') <> '{"businesses": [], "people": [], "orders": []}' then
        raise exception 'FAIL: one letter searched';
    end if;
    -- « _ » is a character too, in every match: « e_1 » is not « e-1 »
    -- (boutique-105), and no word scans the orders' numbers.
    if (platform_search('e_1')->'businesses') @> '[{"slug": "boutique-105"}]'
       or (platform_search('n_e C')->'orders') @> '[{"customer": "Cliente Cent-Cinq"}]' then
        raise exception 'FAIL: a « _ » matched any character';
    end if;
    if (platform_search(left(v_order::text, 3))->'orders') @> jsonb_build_array(jsonb_build_object('id', v_order)) then
        raise exception 'FAIL: three characters scanned the orders'' numbers';
    end if;
    raise notice 'PASS: a shop, a farm, an association by name and address; by the owner''s phone typed with spaces; a person by phone and e-mail; an order by the start of its number (4 characters at least) and its customer; « %% » and « _ » are literal';
end $$;

\echo ''
\echo '--- TEST 4: cauris to several businesses — each a journal line, a vitrine d''exemple refused alone; undone, never twice; never more than is left ---'
do $$
declare
    v jsonb;
    v_ids uuid[];
    v_bal_shop int := cauris_balance('10500000-0000-0000-0000-000000000001');
    v_bal_farm int := cauris_balance('10500000-0000-0000-0000-000000000002');
    v_bal_assoc int := cauris_balance('10500000-0000-0000-0000-000000000003');
    v_action uuid;
    v_promo uuid;
begin
    perform set_config('request.jwt.claim.sub', '10510510-0000-0000-0000-000000000001', true);
    execute 'set local role authenticated';
    v := platform_bulk('cauris', array['10500000-0000-0000-0000-000000000001',
                                       '10500000-0000-0000-0000-000000000002',
                                       '10500000-0000-0000-0000-000000000003',
                                       '10500000-0000-0000-0000-000000000004']::uuid[],
                       '{"points": 40, "note": "Bravo"}');
    execute 'reset role';
    if (v->>'done')::int <> 3 or jsonb_array_length(v->'failed') <> 1
       or v->'failed'->0->>'name' <> 'Exemple Cent-Cinq'
       or v->'failed'->0->>'error' <> 'Une vitrine d''exemple ne reçoit pas de cauris' then
        raise exception 'FAIL: bulk cauris said %', v;
    end if;
    if cauris_balance('10500000-0000-0000-0000-000000000001') <> v_bal_shop + 40
       or cauris_balance('10500000-0000-0000-0000-000000000002') <> v_bal_farm + 40
       or cauris_balance('10500000-0000-0000-0000-000000000003') <> v_bal_assoc + 40 then
        raise exception 'FAIL: the cauris did not arrive in each kind';
    end if;
    select array_agg(id) into v_ids from platform_actions
     where kind = 'cauris_gift' and org_id in ('10500000-0000-0000-0000-000000000001',
                                               '10500000-0000-0000-0000-000000000002',
                                               '10500000-0000-0000-0000-000000000003')
       and actor = '10510510-0000-0000-0000-000000000001';
    if cardinality(v_ids) <> 3 or (select count(*) from jsonb_array_elements(v->'actions')) <> 3 then
        raise exception 'FAIL: not one journal line per business';
    end if;
    if not exists (select 1 from notifications
                    where recipient_id = '10510510-0000-0000-0000-000000000004'
                      and kind = 'cauris_gift') then
        raise exception 'FAIL: the association''s owner was not told';
    end if;

    -- Undone for the farm: its 40 come back out, its bell says so.
    select id into v_action from platform_actions
     where kind = 'cauris_gift' and org_id = '10500000-0000-0000-0000-000000000002' order by at desc limit 1;
    execute 'set local role authenticated';
    perform platform_undo(v_action);
    begin
        perform platform_undo(v_action);
        raise exception 'FAIL: undone twice';
    exception when others then
        if sqlerrm <> 'Cette action a déjà été annulée.' then raise; end if;
    end;
    execute 'reset role';
    if cauris_balance('10500000-0000-0000-0000-000000000002') <> v_bal_farm then
        raise exception 'FAIL: the farm''s gift was not taken back';
    end if;
    if not exists (select 1 from notifications
                    where recipient_id = '10510510-0000-0000-0000-000000000003'
                      and kind = 'gift_undone' and message = 'Mara a repris 40 cauris offerts.') then
        raise exception 'FAIL: the farm was not told its gift was taken back';
    end if;

    -- Spent first, then undone: nothing to take back, the line stays open.
    perform cauris_take('10500000-0000-0000-0000-000000000003',
                        cauris_balance('10500000-0000-0000-0000-000000000003'), 'b105-spend', 'Test');
    select id into v_action from platform_actions
     where kind = 'cauris_gift' and org_id = '10500000-0000-0000-0000-000000000003' order by at desc limit 1;
    execute 'set local role authenticated';
    begin
        perform platform_undo(v_action);
        raise exception 'FAIL: spent cauris were taken back';
    exception when others then
        if sqlerrm <> 'Ces cauris ont déjà été dépensés : il n''y a rien à reprendre.' then raise; end if;
    end;
    execute 'reset role';
    if (select undone_at from platform_actions where id = v_action) is not null then
        raise exception 'FAIL: a refused undo was marked done';
    end if;

    -- Given 400, spent 400, then 400 earned by the business itself: the
    -- gift is gone — its undo is refused and the earned cauris stay.
    execute 'set local role authenticated';
    v := platform_bulk('cauris', array['10500000-0000-0000-0000-000000000002']::uuid[], '{"points": 400}');
    execute 'reset role';
    v_action := (v->'actions'->>0)::uuid;
    if (select undo_args->>'ledger_id' from platform_actions where id = v_action) is null then
        raise exception 'FAIL: the gift''s own ledger line is not in its journal line';
    end if;
    perform cauris_take('10500000-0000-0000-0000-000000000002', 400, 'b105-spend-400', 'Test');
    insert into cauris_ledger (org_id, delta, reason, ref, note)
        values ('10500000-0000-0000-0000-000000000002', 400, 'order_done', 'b105-earn-400', 'Commande');
    v_bal_farm := cauris_balance('10500000-0000-0000-0000-000000000002');
    execute 'set local role authenticated';
    begin
        perform platform_undo(v_action);
        raise exception 'FAIL: cauris earned after a spent gift were taken back';
    exception when others then
        if sqlerrm <> 'Ces cauris ont déjà été dépensés : il n''y a rien à reprendre.' then raise; end if;
    end;
    execute 'reset role';
    if cauris_balance('10500000-0000-0000-0000-000000000002') <> v_bal_farm then
        raise exception 'FAIL: the earned cauris moved';
    end if;
    -- Given 400, 100 of it spent: the undo takes back 300, no more.
    execute 'set local role authenticated';
    v := platform_bulk('cauris', array['10500000-0000-0000-0000-000000000002']::uuid[], '{"points": 400}');
    execute 'reset role';
    v_action := (v->'actions'->>0)::uuid;
    perform cauris_take('10500000-0000-0000-0000-000000000002', 100, 'b105-spend-100', 'Test');
    execute 'set local role authenticated';
    perform platform_undo(v_action);
    execute 'reset role';
    if cauris_balance('10500000-0000-0000-0000-000000000002') <> v_bal_farm then
        raise exception 'FAIL: the undo did not take back the 300 left of the gift (balance %, expected %)',
            cauris_balance('10500000-0000-0000-0000-000000000002'), v_bal_farm;
    end if;

    -- Promotional cauris before a date: undone, the lot is closed.
    execute 'set local role authenticated';
    v := platform_bulk('cauris', array['10500000-0000-0000-0000-000000000001']::uuid[],
                       jsonb_build_object('points', 25, 'expires_on', cauris_today() + 10));
    execute 'reset role';
    select (after->>'promo_id')::uuid, id into v_promo, v_action from platform_actions
     where id = (v->'actions'->>0)::uuid;
    if v_promo is null or not exists (select 1 from cauris_promos where id = v_promo and left_points = 25) then
        raise exception 'FAIL: the promo lot is not in the journal line';
    end if;
    execute 'set local role authenticated';
    perform platform_undo(v_action);
    execute 'reset role';
    if exists (select 1 from cauris_promos where id = v_promo and left_points > 0)
       or cauris_balance('10500000-0000-0000-0000-000000000001') <> v_bal_shop + 40 then
        raise exception 'FAIL: the promo cauris were not taken back';
    end if;

    -- A bad number refuses the whole act, before any business.
    execute 'set local role authenticated';
    begin
        perform platform_bulk('cauris', array['10500000-0000-0000-0000-000000000001']::uuid[], '{"points": 0}');
        raise exception 'FAIL: zero cauris given';
    exception when others then
        if sqlerrm <> 'Le nombre de cauris doit être entre 1 et 100 000' then raise; end if;
    end;
    begin
        perform platform_bulk('cauris', array[]::uuid[], '{"points": 5}');
        raise exception 'FAIL: nobody given cauris';
    exception when others then
        if sqlerrm <> 'Choisissez au moins une entreprise.' then raise; end if;
    end;
    execute 'reset role';
    raise notice 'PASS: cauris to a shop, a farm, an association — the vitrine d''exemple refused alone with its reason; one journal line each, naming the gift''s own ledger line; undone (bell), never twice; refused once spent, even with cauris earned since (untouched); the gift less what was spent taken back; a promo lot (found by what the gift wrote) closed by its undo';
end $$;

\echo ''
\echo '--- TEST 5: a tool until a date, a message, an archive — each kind; the tool and the archive undone, the message never ---'
do $$
declare
    v jsonb;
    v_action uuid;
    v_until timestamptz;
    v_archived timestamptz;
    v_archiver uuid;
begin
    perform set_config('request.jwt.claim.sub', '10510510-0000-0000-0000-000000000001', true);
    -- The shop bought Analyses with its own cauris, open 2 more days.
    insert into cauris_unlocks (org_id, feature, until, note)
        values ('10500000-0000-0000-0000-000000000001', 'analytics', now() + interval '2 days', 'Acheté')
        on conflict (org_id, feature) do update set until = excluded.until, note = excluded.note, gifted_by = null;
    select until into v_until from cauris_unlocks
     where org_id = '10500000-0000-0000-0000-000000000001' and feature = 'analytics';
    execute 'set local role authenticated';
    v := platform_bulk('unlock', array['10500000-0000-0000-0000-000000000001',
                                       '10500000-0000-0000-0000-000000000002']::uuid[],
                       jsonb_build_object('feature', 'analytics', 'until', cauris_today() + 20));
    execute 'reset role';
    if (v->>'done')::int <> 2 then
        raise exception 'FAIL: bulk unlock said %', v;
    end if;
    if not exists (select 1 from cauris_unlocks where org_id = '10500000-0000-0000-0000-000000000002'
                      and feature = 'analytics' and gifted_by is not null and until > now() + interval '19 days') then
        raise exception 'FAIL: the farm''s tool was not opened';
    end if;
    -- Undo both: the farm's row goes, the shop's purchase comes back as it was.
    for v_action in select (jsonb_array_elements_text(v->'actions'))::uuid loop
        execute 'set local role authenticated';
        perform platform_undo(v_action);
        execute 'reset role';
    end loop;
    if exists (select 1 from cauris_unlocks where org_id = '10500000-0000-0000-0000-000000000002'
                  and feature = 'analytics') then
        raise exception 'FAIL: the farm''s gifted tool stayed open';
    end if;
    if not exists (select 1 from cauris_unlocks where org_id = '10500000-0000-0000-0000-000000000001'
                      and feature = 'analytics' and until = v_until and gifted_by is null and note = 'Acheté') then
        raise exception 'FAIL: the shop''s own purchase did not come back as it was';
    end if;
    delete from cauris_unlocks where org_id = '10500000-0000-0000-0000-000000000001' and feature = 'analytics';

    -- An association has no analyses (099): refused for it alone.
    execute 'set local role authenticated';
    v := platform_bulk('unlock', array['10500000-0000-0000-0000-000000000003']::uuid[],
                       jsonb_build_object('feature', 'analytics', 'until', cauris_today() + 5));
    if (v->>'done')::int <> 0
       or v->'failed'->0->>'error' <> 'Cet outil n''existe pas pour ce type d''activité' then
        raise exception 'FAIL: an association was opened analyses: %', v;
    end if;

    -- An unknown tool refuses the whole act.
    begin
        perform platform_bulk('unlock', array['10500000-0000-0000-0000-000000000002']::uuid[],
                              jsonb_build_object('feature', 'photo_slot', 'until', cauris_today() + 3));
        raise exception 'FAIL: a photo slot opened as a tool';
    exception when others then
        if sqlerrm <> 'Outil inconnu : photo_slot' then raise; end if;
    end;

    -- A message to a shop, a farm and an association: one line each, no undo.
    v := platform_bulk('message', array['10500000-0000-0000-0000-000000000001',
                                        '10500000-0000-0000-0000-000000000002',
                                        '10500000-0000-0000-0000-000000000003']::uuid[],
                       '{"message": "Pensez à vos photos"}');
    execute 'reset role';
    if (v->>'done')::int <> 3
       or (select count(*) from notifications where kind = 'platform_message'
             and org_id in ('10500000-0000-0000-0000-000000000001',
                            '10500000-0000-0000-0000-000000000002',
                            '10500000-0000-0000-0000-000000000003')
             and message like '%Pensez à vos photos') <> 3 then
        raise exception 'FAIL: the message did not reach each owner: %', v;
    end if;
    v_action := (v->'actions'->>0)::uuid;
    if (select undoable from platform_actions_page(null, 200, null) where id = v_action) then
        raise exception 'FAIL: a message offered « Annuler »';
    end if;
    execute 'set local role authenticated';
    begin
        perform platform_undo(v_action);
        raise exception 'FAIL: a message was unsent';
    exception when others then
        if sqlerrm <> 'Cette action ne s''annule pas.' then raise; end if;
    end;

    -- Archive the farm and the quiet shop; undo the farm's; restore the
    -- quiet one, and undo that restore.
    v := platform_bulk('archive', array['10500000-0000-0000-0000-000000000002',
                                        '10500000-0000-0000-0000-000000000005']::uuid[], null);
    execute 'reset role';
    if (v->>'done')::int <> 2
       or (select count(*) from orgs where archived_at is not null
            and id in ('10500000-0000-0000-0000-000000000002', '10500000-0000-0000-0000-000000000005')) <> 2 then
        raise exception 'FAIL: bulk archive said %', v;
    end if;
    execute 'set local role authenticated';
    -- Archived already: said, not redone.
    if (platform_bulk('archive', array['10500000-0000-0000-0000-000000000002']::uuid[], null)
          ->'failed'->0->>'error') <> 'Déjà archivée' then
        raise exception 'FAIL: an archived business archived twice';
    end if;
    execute 'reset role';
    select id into v_action from platform_actions where kind = 'archive'
       and org_id = '10500000-0000-0000-0000-000000000002' order by at desc limit 1;
    -- The quiet one archived a week ago by somebody else: its restore
    -- undone puts back that date and that hand, not the undo's.
    update orgs set archived_at = now() - interval '7 days', archived_by = '10510510-0000-0000-0000-000000000002'
     where id = '10500000-0000-0000-0000-000000000005';
    select archived_at, archived_by into v_archived, v_archiver from orgs
     where id = '10500000-0000-0000-0000-000000000005';
    execute 'set local role authenticated';
    perform platform_undo(v_action);
    v := platform_bulk('restore', array['10500000-0000-0000-0000-000000000005']::uuid[], null);
    perform platform_undo((v->'actions'->>0)::uuid);
    execute 'reset role';
    if (select archived_at from orgs where id = '10500000-0000-0000-0000-000000000002') is not null
       or (select archived_at from orgs where id = '10500000-0000-0000-0000-000000000005') is null then
        raise exception 'FAIL: archive and restore were not undone';
    end if;
    if (select (archived_at, archived_by) from orgs where id = '10500000-0000-0000-0000-000000000005')
       is distinct from (v_archived, v_archiver) then
        raise exception 'FAIL: the restore''s undo re-dated the archive';
    end if;
    raise notice 'PASS: a tool opened for a shop and a farm, undone back to the shop''s own purchase, never a tool an association does not have; a message to each kind, never undone; an archive undone, a restore undone with its first archive''s date and hand';
end $$;

\echo ''
\echo '--- TEST 6: Réglages — every setting but the markers; its own type only; logged before and after; undone unless changed since; the two-step switch ---'
do $$
declare
    v jsonb;
    v_before jsonb := (select value from platform_settings where key = 'pro_price_month');
    a1 uuid;
    a2 uuid;
    n0 int;
    v_had boolean := exists (select 1 from platform_settings where key = 'application_form');
begin
    -- The request page (107) is its own setter's: never a Réglages setting.
    if not v_had then
        insert into platform_settings (key, value) values ('application_form', '{"welcome": "B105"}');
    end if;
    perform set_config('request.jwt.claim.sub', '10510510-0000-0000-0000-000000000001', true);
    execute 'set local role authenticated';
    v := platform_settings_board();
    if not v ? 'pro_price_month' or not v ? 'admin_two_step' or v ? 'path_seeded'
       or v ? 'team_seats_seeded' or v ? 'association_setup_marked' or v ? 'application_form' then
        raise exception 'FAIL: the board is not every setting but the markers and the request page: %', v;
    end if;
    begin perform platform_set_setting('application_form', '{"welcome": "Bonjour"}');
          raise exception 'FAIL: the request page written past its own setter';
    exception when others then if sqlerrm <> 'Réglage inconnu : application_form' then raise; end if; end;
    execute 'reset role';
    if not v_had then
        delete from platform_settings where key = 'application_form';
    end if;
    execute 'set local role authenticated';

    a1 := platform_set_setting('pro_price_month', to_jsonb((v_before #>> '{}')::numeric + 500));
    if a1 is null or (select value from platform_settings where key = 'pro_price_month')
                     <> to_jsonb((v_before #>> '{}')::numeric + 500) then
        raise exception 'FAIL: the Pro price was not changed';
    end if;
    execute 'reset role';
    if not exists (select 1 from platform_actions where id = a1 and kind = 'setting' and org_id is null
                      and before = jsonb_build_object('key', 'pro_price_month', 'value', v_before)
                      and actor = '10510510-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the change is not in the journal with its before';
    end if;
    execute 'set local role authenticated';
    if platform_settings_board()->'pro_price_month'->>'changed_by' <> 'Mara Cent-Cinq' then
        raise exception 'FAIL: the board does not say who changed it';
    end if;

    -- The same value again: nothing changed, nothing written.
    select count(*) into n0 from platform_actions_page(null, 200, null);
    if platform_set_setting('pro_price_month', to_jsonb((v_before #>> '{}')::numeric + 500)) is not null
       or (select count(*) from platform_actions_page(null, 200, null)) <> n0 then
        raise exception 'FAIL: an unchanged setting was journaled';
    end if;

    -- Its own type only; never below zero; a percentage never above 100.
    begin perform platform_set_setting('pro_price_month', '"trois mille"');
          raise exception 'FAIL: a word for a price';
    exception when others then if sqlerrm <> 'Ce réglage attend un nombre.' then raise; end if; end;
    begin perform platform_set_setting('pro_price_month', '-1');
          raise exception 'FAIL: a negative price';
    exception when others then if sqlerrm <> 'Un nombre positif, s''il vous plaît.' then raise; end if; end;
    begin perform platform_set_setting('delivery_share_pct', '150');
          raise exception 'FAIL: 150 %%';
    exception when others then if sqlerrm <> 'Un pourcentage ne dépasse pas 100.' then raise; end if; end;
    begin perform platform_set_setting('wave_checkout', '1');
          raise exception 'FAIL: a number for a switch';
    exception when others then if sqlerrm <> 'Ce réglage attend oui ou non.' then raise; end if; end;
    begin perform platform_set_setting('pro_features', '["payroll", 3]');
          raise exception 'FAIL: a number in the Pro list';
    exception when others then if sqlerrm <> 'Ce réglage attend une liste de mots.' then raise; end if; end;
    begin perform platform_set_setting('path_seeded', '"x"');
          raise exception 'FAIL: a marker changed';
    exception when others then if sqlerrm <> 'Réglage inconnu : path_seeded' then raise; end if; end;
    begin perform platform_set_setting('nouveau_reglage', '1');
          raise exception 'FAIL: a new key written';
    exception when others then if sqlerrm <> 'Réglage inconnu : nouveau_reglage' then raise; end if; end;

    -- A whole number where a reader reads an integer (plan_limit,
    -- cauris_param): « 12.5 » would break plan_terms(), the caps, the
    -- leagues. A decimal only for the delivery fee and reach and the Wave
    -- commission, read as numeric. Never above a billion; a 0/1 switch is 0
    -- or 1; « 2.0 » is written « 2 », as an integer reader reads it.
    begin perform platform_set_setting('free_max_staff', '12.5');
          raise exception 'FAIL: 12.5 people';
    exception when others then if sqlerrm <> 'Un nombre entier, s''il vous plaît.' then raise; end if; end;
    begin perform platform_set_setting('delivery_share_pct', '12.5');
          raise exception 'FAIL: 12.5 %% for a share read as an integer';
    exception when others then if sqlerrm <> 'Un nombre entier, s''il vous plaît.' then raise; end if; end;
    begin perform platform_set_setting('spot_price_shop_7', '2500.5');
          raise exception 'FAIL: half a franc';
    exception when others then if sqlerrm <> 'Un nombre entier, s''il vous plaît.' then raise; end if; end;
    begin perform platform_set_setting('vitrine_free_basics', '2');
          raise exception 'FAIL: a 0/1 switch at 2';
    exception when others then if sqlerrm <> 'Ce réglage vaut 0 (non) ou 1 (oui).' then raise; end if; end;
    begin perform platform_set_setting('pro_price_year', '2000000000');
          raise exception 'FAIL: two billion';
    exception when others then if sqlerrm <> 'Un nombre d''un milliard au plus.' then raise; end if; end;
    if (plan_terms()->>'free_max_staff') is null then
        raise exception 'FAIL: plan_terms() broke';
    end if;
    a2 := platform_set_setting('delivery_per_km', '152.5');
    if (select value from platform_settings where key = 'delivery_per_km') <> '152.5'::jsonb then
        raise exception 'FAIL: a decimal refused for the fee per km';
    end if;
    perform platform_undo(a2);
    a2 := platform_set_setting('free_max_staff', '2.0');
    if (select value::text from platform_settings where key = 'free_max_staff') <> '2'
       or (plan_terms()->>'free_max_staff')::int <> 2 then
        raise exception 'FAIL: « 2.0 » not written as the integer 2: %',
            (select value::text from platform_settings where key = 'free_max_staff');
    end if;
    perform platform_undo(a2);
    if (plan_terms()->>'free_max_staff') is null then
        raise exception 'FAIL: plan_terms() broke after the numbers';
    end if;

    -- Changed again since: the first change is not undone over the second.
    a2 := platform_set_setting('pro_price_month', to_jsonb((v_before #>> '{}')::numeric + 900));
    begin
        perform platform_undo(a1);
        raise exception 'FAIL: an undo overwrote a later change';
    exception when others then
        if sqlerrm <> 'Ce réglage a changé depuis : annulez d''abord le dernier changement.' then raise; end if;
    end;
    perform platform_undo(a2);
    perform platform_undo(a1);
    execute 'reset role';
    if (select value from platform_settings where key = 'pro_price_month') <> v_before then
        raise exception 'FAIL: the Pro price did not come back';
    end if;

    -- The two-step switch (078): on, logged; undone, off — two_step_on() reads it.
    execute 'set local role authenticated';
    a1 := platform_set_setting('admin_two_step', 'true');
    execute 'reset role';
    if not two_step_on() then
        raise exception 'FAIL: the two-step switch did not turn on';
    end if;
    execute 'set local role authenticated';
    perform platform_undo(a1);
    execute 'reset role';
    if two_step_on() then
        raise exception 'FAIL: the two-step switch did not come back off';
    end if;
    raise notice 'PASS: the board hides the markers and the request page (107''s own) and names who changed what; a change of its own type is journaled with its before, undone, not over a later one; a word, a negative, 150 %%, a number for a switch, a marker, a new key refused; 12.5 on an integer setting (people, a share, a price in francs), 2 on a 0/1 switch, two billion refused in French — plan_terms() still answers; a decimal for the fee per km, « 2.0 » written 2; the two-step switch on and back off';
end $$;

\echo ''
\echo '--- TEST 7: no dead switch in Réglages — every key the app lists exists and is read by the server ---'
do $$
declare
    -- The app's list: app/lib/features/admin/center/settings_section.dart
    -- (test/command_center_test.dart checks the two lists are the same).
    v_keys text[] := array[
        'pro_price_month', 'pro_price_year', 'pro_currency', 'platform_wave', 'platform_wave_name',
        'stripe_on',
        -- 121: read by stripe_usd_cents(), which stripe_begin and plan_terms ask.
        'stripe_xof_per_usd',
        'pro_features',
        'free_max_staff', 'free_max_invoices_month', 'free_max_photos', 'free_photo_items',
        'free_history_months', 'vitrine_free_basics',
        'vitrine_min_items', 'vitrine_min_items_association', 'progress_street_pct',
        'spots_max_live', 'pro_free_spots_month', 'spot_price_article_7', 'spot_price_article_30',
        'spot_price_shop_7', 'spot_price_shop_30',
        'delivery_base', 'delivery_per_km', 'delivery_currency', 'delivery_max_km',
        'delivery_included_km', 'delivery_share_pct', 'own_courier_minutes', 'stuck_ready_minutes',
        -- 112: read by courier_rules(), which the courier's dossier asks.
        'courier_licence_required', 'courier_phone_verified',
        -- 122: read by courier_reach(), which the couriers' bell and board ask.
        'courier_radius_km',
        'wave_checkout', 'wave_card', 'wave_commission_pct',
        'cauris_order_min', 'cauris_orders_per_customer', 'cauris_quick_minutes',
        'cauris_expire_days', 'cauris_unlock_days', 'cauris_prize_1', 'cauris_prize_2',
        'cauris_prize_3', 'league_small_max', 'league_medium_max', 'path_league_min',
        'progress_credit_orders', 'path_gates_open',
        'admin_two_step',
        -- 109: read by order_phone_required(), which place_order asks.
        'order_phone_verified',
        -- 111: read by create_phone_required(), which create_my_business asks.
        'create_phone_verified',
        -- 113: read by support_whatsapp(), which the shopper's page asks.
        'support_whatsapp',
        -- 126: read by support_contacts(), which /aide and the app's « Aide » ask.
        'support_email', 'support_hours',
        -- 122: read by app_store_links(), which the web's download pop-up asks.
        'play_store_live', 'app_store_url',
        -- 124: read by trg_welcome_email_request() and welcome_email_claim().
        'welcome_email_on'];
    v_dead text;
    v_missing text;
begin
    select string_agg(k, ', ') into v_missing from unnest(v_keys) k
     where not exists (select 1 from platform_settings s where s.key = k)
        or platform_setting_internal(k);
    if v_missing is not null then
        raise exception 'FAIL: the app lists settings the database does not have: %', v_missing;
    end if;
    -- Read by a function as it stands now (the prizes by their prefix).
    select string_agg(k, ', ') into v_dead from unnest(v_keys) k
     where not exists (
        select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname not like 'platform\_%'
           and (p.prosrc like '%''' || k || '''%'
                or (k like 'cauris_prize_%' and p.prosrc like '%''cauris_prize_''%')));
    if v_dead is not null then
        raise exception 'FAIL: Réglages lists settings nothing reads: %', v_dead;
    end if;
    raise notice 'PASS: % settings in Réglages, each in platform_settings and read by the server', cardinality(v_keys);
end $$;

\echo ''
\echo '--- TEST 8: 105 changes nothing a business or a vitrine shows ---'
begin;
create temp table b105_seen on commit drop as
    select 'setting ' || key as k, value::text as v from platform_settings
    union all
    select 'storefront ' || o.slug, (select jsonb_agg(to_jsonb(s)) from storefront(o.slug) s)::text
      from orgs o where o.slug in ('boutique-105', 'ferme-105', 'entraide-105')
    union all
    select 'shelf ' || o.slug, (select jsonb_agg(to_jsonb(s) order by s.id) from storefront_products(o.slug) s)::text
      from orgs o where o.slug in ('boutique-105', 'ferme-105', 'entraide-105')
    union all
    select 'hidden ' || o.slug, features_hidden_for(o.id)::text
      from orgs o where o.slug in ('boutique-105', 'ferme-105', 'entraide-105');
\i database/migrations/105_command_center.sql
do $$
declare v_diff text;
begin
    with now_seen as (
        select 'setting ' || key as k, value::text as v from platform_settings
        union all
        select 'storefront ' || o.slug, (select jsonb_agg(to_jsonb(s)) from storefront(o.slug) s)::text
          from orgs o where o.slug in ('boutique-105', 'ferme-105', 'entraide-105')
        union all
        select 'shelf ' || o.slug, (select jsonb_agg(to_jsonb(s) order by s.id) from storefront_products(o.slug) s)::text
          from orgs o where o.slug in ('boutique-105', 'ferme-105', 'entraide-105')
        union all
        select 'hidden ' || o.slug, features_hidden_for(o.id)::text
          from orgs o where o.slug in ('boutique-105', 'ferme-105', 'entraide-105'))
    select string_agg(coalesce(a.k, b.k), ', ') into v_diff
      from b105_seen a full join now_seen b on a.k = b.k
     where a.v is distinct from b.v;
    if v_diff is not null then
        raise exception 'FAIL: applying 105 changed %', v_diff;
    end if;
    raise notice 'PASS: every setting, a shop''s, a farm''s and an association''s vitrine, shelf and hidden tools the same after 105 as before';
end $$;
commit;

\echo ''
\echo '--- TEST 9: the Entreprises list''s one « Associations » finds the legacy churches with them; still the platform''s alone ---'
begin;
insert into orgs (id, name, slug, profile, default_currency, last_activity_at)
values ('10500000-0000-0000-0000-000000000009', 'Église Cent-Cinq', 'eglise-105', 'church', 'XOF', now());
do $$
declare
    v_assoc text[];
    v_church text[];
    v_shops text[];
begin
    perform set_config('request.jwt.claim.sub', '10510510-0000-0000-0000-000000000001', true);
    execute 'set local role authenticated';
    select array_agg(slug order by slug) into v_assoc
      from search_orgs(p_query => 'Cent-Cinq', p_profile => 'association', p_status => 'all');
    -- The legacy filter word still answers the same.
    select array_agg(slug order by slug) into v_church
      from search_orgs(p_query => 'Cent-Cinq', p_profile => 'church', p_status => 'all');
    select array_agg(slug order by slug) into v_shops
      from search_orgs(p_query => 'Cent-Cinq', p_profile => 'retail', p_status => 'all');
    if v_assoc is distinct from array['eglise-105', 'entraide-105']
       or v_church is distinct from v_assoc then
        raise exception 'FAIL: « Associations » lists % (church filter: %)', v_assoc, v_church;
    end if;
    if v_shops && array['eglise-105', 'entraide-105'] or not ('boutique-105' = any (v_shops)) then
        raise exception 'FAIL: the shops'' filter lists %', v_shops;
    end if;
    -- An association's owner is not the platform.
    perform set_config('request.jwt.claim.sub', '10510510-0000-0000-0000-000000000004', true);
    begin
        perform search_orgs(p_profile => 'association');
        raise exception 'FAIL: an owner listed every business';
    exception when raise_exception then
        if sqlerrm <> 'Only a platform admin can search every business' then raise; end if;
    end;
    execute 'reset role';
    raise notice 'PASS: « Associations » lists an association and a legacy church (the church word too), never a shop; a shop''s filter none of them; an owner refused';
end $$;
rollback;

-- What the suite archived, gave and wrote stays its own: the shared
-- numbers are as they were (TEST 6 undid its changes), the switch off.
update platform_settings set value = 'false' where key = 'admin_two_step';
