-- ============================================================
-- test_batch104.sql — Mara's switchboard (104). Phone block 11.
--
-- The claims, for a shop, a farm and an association (a legacy church
-- counted as one) alike:
--   P1 (in this database): with no rule written, no business of any kind
--      has any catalog feature hidden — feature_hidden is false for every
--      one, feature_states says « hidden: [] », the board says « Par
--      défaut » everywhere. (The before/after proof against 103 is
--      p1_104_before.sql / p1_104_after.sql, its own CI step.)
--   P2: no dead switch — every catalog key has a door at the server (a
--      trigger or a function that calls feature_guard), and each door,
--      called by a member with the feature hidden, refuses in French
--      (MA002); visible again, it opens.
--   P3: only a platform admin reads or changes the switchboard, its
--      journal or its undo; every change is logged with what it was and
--      what it became; an undo restores it once, through the whitelist,
--      and never a stale one; the owner is told of a change to their
--      business, never of a kind's.
--   And: a business's switch beats its kind's beats the catalog; an
--   expired switch is no switch; a feature the business PAID for (a paid
--   Pro, cauris it spent) is never hidden and cannot be — a gift from Mara
--   is not a payment; a kind cannot be given a switch for a tool it does
--   not have; no cauris are spent on a hidden tool; Mara's own people see
--   what the business sees.
-- ============================================================
\set ON_ERROR_STOP on
update platform_settings set value = '1' where key = 'path_gates_open';

\set mara    '''10404040-0000-0000-0000-000000000001'''
\set sowner  '''10404040-0000-0000-0000-000000000002'''
\set semp    '''10404040-0000-0000-0000-000000000003'''
\set fowner  '''10404040-0000-0000-0000-000000000004'''
\set aowner  '''10404040-0000-0000-0000-000000000005'''
\set cowner  '''10404040-0000-0000-0000-000000000006'''
\set bowner  '''10404040-0000-0000-0000-000000000007'''
\set stranger '''10404040-0000-0000-0000-000000000008'''
\set shop    '''10400000-0000-0000-0000-000000000001'''
\set basic   '''10400000-0000-0000-0000-000000000002'''
\set farm    '''10400000-0000-0000-0000-000000000003'''
\set assoc   '''10400000-0000-0000-0000-000000000004'''
\set church  '''10400000-0000-0000-0000-000000000005'''
\set bought  '''10400000-0000-0000-0000-000000000006'''

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
-- Earlier suites re-apply older migrations over 104's functions and hand
-- the app's roles every table and function: 103 and 104 again, so what
-- follows tests their doors as they are live.
\i database/migrations/103_admin_security.sql
\i database/migrations/104_feature_switchboard.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:mara,     '+22611040001', '{"full_name": "Mara Admin"}'),
    (:sowner,   '+22611040002', '{"full_name": "Patronne 11"}'),
    (:semp,     '+22611040003', '{"full_name": "Vendeuse 11"}'),
    (:fowner,   '+22611040004', '{"full_name": "Fermier 11"}'),
    (:aowner,   '+22611040005', '{"full_name": "Trésorière 11"}'),
    (:cowner,   '+22611040006', '{"full_name": "Pasteur 11"}'),
    (:bowner,   '+22611040007', '{"full_name": "Acheteuse 11"}'),
    (:stranger, '+22611040008', '{"full_name": "Inconnue 11"}');
update profiles set is_platform_admin = true where id = :mara;
insert into orgs (id, name, slug, profile, default_currency, plan, plan_until) values
    (:shop,   'Boutique 11',  'boutique-11',  'retail',      'XOF', 'pro',  '2099-01-01'),
    (:basic,  'Échoppe 11',   'echoppe-11',   'retail',      'XOF', 'free', null),
    (:farm,   'Ferme 11',     'ferme-11',     'farm',        'XOF', 'free', null),
    (:assoc,  'Entraide 11',  'entraide-11',  'association', 'XOF', 'free', null),
    (:church, 'Chapelle 11',  'chapelle-11',  'church',      'XOF', 'free', null),
    (:bought, 'Acheteuse 11', 'acheteuse-11', 'retail',      'XOF', 'free', null);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,   :sowner, 'owner',    'org', :shop,   'full'),
    (:shop,   :semp,   'employee', 'org', :shop,   'full'),
    (:basic,  :sowner, 'owner',    'org', :basic,  'full'),
    (:farm,   :fowner, 'owner',    'org', :farm,   'full'),
    (:assoc,  :aowner, 'owner',    'org', :assoc,  'full'),
    (:church, :cowner, 'owner',    'org', :church, 'full'),
    (:bought, :bowner, 'owner',    'org', :bought, 'full');
-- Mara's gifts open the Pro tools on the Basic shop and the farm — not a
-- payment, so a switch still hides them there.
insert into cauris_unlocks (org_id, feature, until, note, gifted_by) values
    (:basic, 'pro_all',   now() + interval '30 days', 'Offert par Mara', :mara),
    (:farm,  'analytics', now() + interval '30 days', 'Offert par Mara', :mara);
-- The tontines bought with the business's own cauris: paid.
insert into cauris_unlocks (org_id, feature, until) values
    (:bought, 'tontines', now() + interval '30 days');
insert into cauris_ledger (org_id, delta, reason, ref) values
    (:basic, 5000, 'gift', 'b104-basic'), (:bought, 5000, 'gift', 'b104-bought');
insert into employees (id, org_id, full_name, kind, hourly_rate) values
    ('10400000-0000-0000-0000-0000000000e1', :basic, 'Aide 11', 'casual', 500);
insert into products (id, org_id, name, sale_price, cost_price, quantity) values
    ('10400000-0000-0000-0000-0000000000a1', :shop, 'Savon 11',  500, 300, 50),
    ('10400000-0000-0000-0000-0000000000a2', :shop, 'Farine 11', 100,  60, 50);

-- A door, knocked on: 'ok', or the SQLSTATE and the sentence.
create or replace function zz_b104_try(p_sql text)
returns text
language plpgsql
set search_path = public
as $$
declare
    v_state text;
    v_msg   text;
begin
    execute p_sql;
    return 'ok';
exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return v_state || ': ' || v_msg;
end;
$$;
grant execute on function zz_b104_try(text) to authenticated;

-- What the engine says, read by the suite as any role (feature_hidden is
-- closed to the app's).
create or replace function zz_b104_hidden(p_org uuid, p_key text)
returns boolean
language sql
security definer
set search_path = public
as $$ select feature_hidden(p_org, p_key) $$;
grant execute on function zz_b104_hidden(uuid, text) to authenticated;

\echo ''
\echo '--- TEST 1 (P1): no rule, nothing hidden — a shop, a farm, an association, a church ---'
begin;
set local role authenticated;
do $$
declare
    r record;
    v jsonb;
begin
    for r in select * from (values
        ('10404040-0000-0000-0000-000000000002'::uuid, '10400000-0000-0000-0000-000000000001'::uuid),
        ('10404040-0000-0000-0000-000000000002'::uuid, '10400000-0000-0000-0000-000000000002'::uuid),
        ('10404040-0000-0000-0000-000000000004'::uuid, '10400000-0000-0000-0000-000000000003'::uuid),
        ('10404040-0000-0000-0000-000000000005'::uuid, '10400000-0000-0000-0000-000000000004'::uuid),
        ('10404040-0000-0000-0000-000000000006'::uuid, '10400000-0000-0000-0000-000000000005'::uuid),
        ('10404040-0000-0000-0000-000000000007'::uuid, '10400000-0000-0000-0000-000000000006'::uuid)) v(who, org)
    loop
        perform set_config('request.jwt.claim.sub', r.who::text, true);
        v := feature_states(r.org);
        if v->'hidden' is distinct from '[]'::jsonb then
            raise exception 'FAIL: % has % hidden with no rule', r.org, v->'hidden';
        end if;
    end loop;
    -- Every business in this database, of every kind (earlier suites' too).
    execute 'reset role';
    if exists (select 1 from orgs o cross join feature_catalog c where feature_hidden(o.id, c.key)) then
        raise exception 'FAIL: a feature is hidden with no rule';
    end if;
    if exists (select 1 from orgs o where features_hidden_for(o.id) <> '[]'::jsonb) then
        raise exception 'FAIL: a business has something hidden with no rule';
    end if;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    for r in select unnest(array['retail', 'farm', 'association', 'church']) as k loop
        if exists (select 1 from jsonb_array_elements(platform_feature_board(r.k, null)) b
                    where b->>'state' <> 'default' or b->>'effective' <> 'visible'
                       or b->>'source' <> 'catalog') then
            raise exception 'FAIL: the % board is not all « Par défaut »', r.k;
        end if;
    end loop;
    execute 'reset role';
    if exists (select 1 from feature_catalog where default_hidden_kinds <> '{}') then
        raise exception 'FAIL: the catalog hides something by default (today hides nothing by it)';
    end if;
    raise notice 'PASS: with no rule, every feature of every kind is visible, feature_states hides nothing, every board says « Par défaut »';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: each kind has its own tools — the board offers only those ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '10404040-0000-0000-0000-000000000001';
do $$
declare v text;
begin
    -- 104's own tools; the vitrine's group (110) is proven by test_batch110.
    select string_agg(b->>'key', ',' order by b->>'key') into v
      from jsonb_array_elements(platform_feature_board('association', null)) b
     where b->>'grp' <> 'Vitrine';
    if v <> 'accounting,credits,invoices,payroll,tontines' then
        raise exception 'FAIL: the association board offers %', v;
    end if;
    select string_agg(b->>'key', ',' order by b->>'key') into v
      from jsonb_array_elements(platform_feature_board(null, '10400000-0000-0000-0000-000000000005')) b
     where b->>'grp' <> 'Vitrine';
    if v <> 'accounting,credits,invoices,payroll,tontines' then
        raise exception 'FAIL: a legacy church is not an association: %', v;
    end if;
    select string_agg(b->>'key', ',' order by b->>'key') into v
      from jsonb_array_elements(platform_feature_board('farm', null)) b
     where b->>'grp' <> 'Vitrine';
    if v <> 'accounting,analytics,credits,invoices,payroll,production,tontines' then
        raise exception 'FAIL: the farm board offers %', v;
    end if;
    select count(*) into v from jsonb_array_elements(platform_feature_board('retail', null));
    execute 'reset role';
    if v::int <> (select count(*) from feature_catalog where 'retail' = any (kinds)) then
        raise exception 'FAIL: the shop board leaves something out';
    end if;
    execute 'set local role authenticated';
    if zz_b104_try($q$select platform_set_feature_rule('kind', 'association', null, 'production', 'hidden')$q$)
       <> 'P0001: Cette fonction n''existe pas pour ce type d''activité.'
       or zz_b104_try($q$select platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000004', 'analytics', 'hidden')$q$)
       <> 'P0001: Cette fonction n''existe pas pour ce type d''activité.' then
        raise exception 'FAIL: a switch was offered for a tool the kind does not have';
    end if;
    if zz_b104_try($q$select platform_set_feature_rule('kind', 'generic', null, 'credits', 'hidden')$q$) not like 'P0001: Type d''activité inconnu%'
       or zz_b104_try($q$select platform_set_feature_rule('kind', 'retail', null, 'nope', 'hidden')$q$) not like 'P0001: Fonction inconnue%'
       or zz_b104_try($q$select platform_set_feature_rule('kind', 'retail', null, 'credits', 'maybe')$q$) not like 'P0001: Réglage inconnu%'
       or zz_b104_try($q$select platform_set_feature_rule('kind', 'retail', null, 'credits', 'hidden', now() - interval '1 day')$q$)
          <> 'P0001: La date de fin doit être dans le futur' then
        raise exception 'FAIL: a malformed switch was accepted';
    end if;
    raise notice 'PASS: a shop has every tool; a farm no corrections; an association (a church too) no production, analyses or corrections — and is refused a switch for them';
end $$;
rollback;

\echo ''
\echo '--- TEST 3 (P3): only the platform reads or changes anything here ---'
begin;
set local role authenticated;
do $$
declare
    r record;
    v text;
begin
    for r in select unnest(array['10404040-0000-0000-0000-000000000002',   -- an owner
                                 '10404040-0000-0000-0000-000000000003',   -- an employee
                                 '10404040-0000-0000-0000-000000000008'])  -- a stranger
                    as who loop
        perform set_config('request.jwt.claim.sub', r.who, true);
        foreach v in array array[
            $q$select platform_feature_board('retail', null)$q$,
            $q$select platform_feature_board(null, '10400000-0000-0000-0000-000000000001')$q$,
            $q$select platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000001', 'credits', 'hidden')$q$,
            $q$select platform_set_feature_rule('kind', 'retail', null, 'credits', 'hidden')$q$,
            $q$select platform_feature_impact('retail', 'credits', 'hidden')$q$,
            $q$select platform_undo(gen_random_uuid())$q$,
            $q$select * from platform_actions_page()$q$] loop
            if zz_b104_try(v) <> 'P0001: Réservé à la plateforme' then
                raise exception 'FAIL: % ran « % »: %', r.who, v, zz_b104_try(v);
            end if;
        end loop;
        -- The tables themselves: no client reads or writes them.
        foreach v in array array[
            $q$select * from feature_rules$q$,
            $q$insert into feature_rules (scope, org_id, feature, state) values ('org', '10400000-0000-0000-0000-000000000001', 'credits', 'hidden')$q$,
            $q$select * from platform_actions$q$,
            $q$insert into platform_actions (kind, summary) values ('x', 'x')$q$,
            $q$insert into platform_undo_fns values ('delete_org')$q$,
            $q$update feature_catalog set default_hidden_kinds = '{retail}'$q$] loop
            if zz_b104_try(v) not like '42501:%' then
                raise exception 'FAIL: % reached a table: « % » → %', r.who, v, zz_b104_try(v);
            end if;
        end loop;
        -- And the engine is closed to them.
        foreach v in array array[
            $q$select feature_hidden('10400000-0000-0000-0000-000000000001', 'credits')$q$,
            $q$select platform_log_action(null, 'x', 'x', null, null, null, null)$q$,
            $q$select platform_restore_feature_rule('{}'::jsonb)$q$] loop
            if zz_b104_try(v) not like '42501:%' then
                raise exception 'FAIL: % ran the engine: « % » → %', r.who, v, zz_b104_try(v);
            end if;
        end loop;
    end loop;
    raise notice 'PASS: an owner, an employee and a stranger are refused every platform door, every table and the engine';
end $$;
rollback;
do $$
begin
    if has_function_privilege('anon', 'platform_set_feature_rule(text, text, uuid, text, text, timestamptz, text)', 'execute')
       or has_function_privilege('anon', 'platform_undo(uuid)', 'execute')
       or has_function_privilege('anon', 'feature_guard(uuid, text)', 'execute')
       or has_function_privilege('anon', 'feature_states(uuid)', 'execute') then
        raise exception 'FAIL: the street can reach the switchboard';
    end if;
    raise notice 'PASS: the street (anon) reaches none of it';
end $$;

\echo ''
\echo '--- TEST 4: a business beats its kind beats the catalog; an expired switch is none ---'
begin;
set local role authenticated;
do $$
declare
    v_a uuid;
    v jsonb;
begin
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    -- Every shop loses its invoices; this one keeps them.
    v_a := platform_set_feature_rule('kind', 'retail', null, 'invoices', 'hidden', null, 'essai');
    perform platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000001', 'invoices', 'visible');
    if not zz_b104_hidden('10400000-0000-0000-0000-000000000002', 'invoices')
       or not zz_b104_hidden('10400000-0000-0000-0000-000000000006', 'invoices')
       or zz_b104_hidden('10400000-0000-0000-0000-000000000001', 'invoices')
       or zz_b104_hidden('10400000-0000-0000-0000-000000000003', 'invoices') then
        raise exception 'FAIL: the kind''s switch or the business''s override is wrong';
    end if;
    -- Every association loses its carnet: a legacy church with it.
    perform platform_set_feature_rule('kind', 'association', null, 'credits', 'hidden');
    if not zz_b104_hidden('10400000-0000-0000-0000-000000000005', 'credits')
       or not zz_b104_hidden('10400000-0000-0000-0000-000000000004', 'credits')
       or zz_b104_hidden('10400000-0000-0000-0000-000000000001', 'credits') then
        raise exception 'FAIL: a church was not counted as an association';
    end if;
    -- A business hidden while its kind shows it.
    perform platform_set_feature_rule('kind', 'farm', null, 'production', 'visible');
    perform platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000003', 'production', 'hidden');
    if not zz_b104_hidden('10400000-0000-0000-0000-000000000003', 'production') then
        raise exception 'FAIL: a business''s own switch did not win over its kind''s';
    end if;
    v := platform_feature_board(null, '10400000-0000-0000-0000-000000000002');
    if (select b->>'source' || '/' || (b->>'effective') || '/' || (b->>'state')
          from jsonb_array_elements(v) b where b->>'key' = 'invoices') <> 'kind/hidden/default' then
        raise exception 'FAIL: the business board does not say its kind decides: %', v;
    end if;
    v := platform_feature_board(null, '10400000-0000-0000-0000-000000000001');
    if (select b->>'source' || '/' || (b->>'effective') || '/' || (b->>'state')
          from jsonb_array_elements(v) b where b->>'key' = 'invoices') <> 'org/visible/visible' then
        raise exception 'FAIL: the business board does not say its own switch decides';
    end if;
    v := platform_feature_board('retail', null);
    if (select b->>'state' || '/' || (b->>'note') from jsonb_array_elements(v) b where b->>'key' = 'invoices')
       <> 'hidden/essai' then
        raise exception 'FAIL: the kind board does not show its switch and note';
    end if;
    -- The members read the same: hidden in feature_states.
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000002', true);
    if not (feature_states('10400000-0000-0000-0000-000000000002')->'hidden') ? 'invoices'
       or (feature_states('10400000-0000-0000-0000-000000000001')->'hidden') ? 'invoices' then
        raise exception 'FAIL: feature_states does not say what is hidden';
    end if;
    -- Expired: the switch is no more.
    execute 'reset role';
    update feature_rules set until = now() - interval '1 minute'
     where scope = 'kind' and kind = 'retail' and feature = 'invoices';
    execute 'set local role authenticated';
    if zz_b104_hidden('10400000-0000-0000-0000-000000000002', 'invoices') then
        raise exception 'FAIL: an expired switch still hides';
    end if;
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    if (select b->>'state' from jsonb_array_elements(platform_feature_board('retail', null)) b
         where b->>'key' = 'invoices') <> 'default' then
        raise exception 'FAIL: the board still shows an expired switch';
    end if;
    raise notice 'PASS: business over kind over catalog, a church is an association, an expired switch is gone — and the board and feature_states say so';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: what the business paid for is never hidden; a gift from Mara is not a payment ---'
begin;
set local role authenticated;
do $$
declare v jsonb;
begin
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    -- Tontines hidden for every shop.
    v := platform_feature_impact('retail', 'tontines', 'hidden');
    perform platform_set_feature_rule('kind', 'retail', null, 'tontines', 'hidden');
    if zz_b104_hidden('10400000-0000-0000-0000-000000000001', 'tontines')   -- paid Mara Pro
       or zz_b104_hidden('10400000-0000-0000-0000-000000000006', 'tontines') -- bought with cauris
       or not zz_b104_hidden('10400000-0000-0000-0000-000000000002', 'tontines') then -- Mara's gift
        raise exception 'FAIL: paid tools were hidden, or a gift counted as paid';
    end if;
    if (v->>'paid')::int < 2 or (v->>'orgs')::int < 3 then
        raise exception 'FAIL: the impact does not count the paying shops: %', v;
    end if;
    -- A business's paid tool cannot be hidden by its own switch either.
    if zz_b104_try($q$select platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000006', 'tontines', 'hidden')$q$)
       <> 'P0001: Fonction payée par l''activité : elle ne peut pas être masquée.'
       or zz_b104_try($q$select platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000001', 'payroll', 'hidden')$q$)
       <> 'P0001: Fonction payée par l''activité : elle ne peut pas être masquée.' then
        raise exception 'FAIL: a paid tool was hidden for its business';
    end if;
    -- A tool no plan sells (the carnet) is hidden on Pro like anywhere.
    perform platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000001', 'credits', 'hidden');
    if not zz_b104_hidden('10400000-0000-0000-0000-000000000001', 'credits') then
        raise exception 'FAIL: a tool Pro does not sell was not hidden on Pro';
    end if;
    -- The board says why.
    if (select (b->>'paid')::boolean and b->>'effective' = 'visible' and b->>'source' = 'kind'
          from jsonb_array_elements(platform_feature_board(null, '10400000-0000-0000-0000-000000000006')) b
         where b->>'key' = 'tontines') is not true then
        raise exception 'FAIL: the board does not show the paid tool as paid and visible';
    end if;
    raise notice 'PASS: a paid Pro and cauris spent keep the tool through a kind''s switch and refuse a business''s; Mara''s gift does not; a tool Pro does not sell hides on Pro';
end $$;
rollback;

\echo ''
\echo '--- TEST 6 (P2): every key has a door, and every door refuses a hidden tool in French ---'
-- Fixtures made while everything is visible: the doors open (the second
-- half of the proof), and leave something to knock on with.
do $$
declare
    v_inv uuid; v_inv2 uuid; v_debt uuid; v_sale uuid; v_run uuid; v_rcpt uuid; v_ton uuid;
    v_mem uuid;
begin
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000002', true);
    execute 'set local role authenticated';
    v_inv := create_invoice('10400000-0000-0000-0000-000000000001', 'Client 11',
                            '[{"description": "Savon", "quantity": 2, "unit_price": 500}]'::jsonb);
    v_inv2 := create_invoice('10400000-0000-0000-0000-000000000001', 'Client 11 bis',
                             '[{"description": "Farine", "quantity": 1, "unit_price": 100}]'::jsonb);
    v_debt := record_credit_sale('10400000-0000-0000-0000-000000000001', 'Awa 11', 1000, 'Riz');
    v_sale := record_sale('10400000-0000-0000-0000-000000000001',
        '[{"product_id":"10400000-0000-0000-0000-0000000000a1","name":"Savon 11","quantity":1,"unit_price":500}]'::jsonb);
    perform receive_products('10400000-0000-0000-0000-000000000001',
                             '10400000-0000-0000-0000-0000000000a2', 5, 60);
    v_run := record_production('10400000-0000-0000-0000-000000000001', 2,
        jsonb_build_array(jsonb_build_object('product_id', '10400000-0000-0000-0000-0000000000a2', 'quantity', 1)),
        p_product_name => 'Gâteau 11');
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000002', true);
    insert into tontines (org_id, name, amount, created_by)
    values ('10400000-0000-0000-0000-000000000002', 'Tontine 11', 1000, '10404040-0000-0000-0000-000000000002')
    returning id into v_ton;
    insert into tontine_members (tontine_id, org_id, name, position)
    values (v_ton, '10400000-0000-0000-0000-000000000002', 'Awa', 1) returning id into v_mem;
    execute 'reset role';
    select id into v_rcpt from stock_receipts where org_id = '10400000-0000-0000-0000-000000000001'
     order by received_at desc limit 1;
    create temp table b104_ids (k text primary key, id uuid);
    insert into b104_ids values ('inv', v_inv), ('inv2', v_inv2), ('debt', v_debt), ('sale', v_sale),
        ('run', v_run), ('rcpt', v_rcpt), ('ton', v_ton), ('mem', v_mem);
    grant select on b104_ids to authenticated;
end $$;

begin;
set local role authenticated;
do $$
declare
    r record;
    v_got text;
    v_tested text[] := '{}';
    v_missing text;
    v_shop  constant text := '''10400000-0000-0000-0000-000000000001''';
    v_basic constant text := '''10400000-0000-0000-0000-000000000002''';
    v_farm  constant text := '''10400000-0000-0000-0000-000000000003''';
    i jsonb := (select jsonb_object_agg(k, id) from b104_ids);
    v_want constant text := 'MA002: Cette fonction n''est pas disponible pour votre activité.';
begin
    for r in select * from (values
        -- key, org, member, the door
        ('invoices', v_shop, 'create_invoice(' || v_shop || ', ''X'', ''[{"description": "a", "quantity": 1, "unit_price": 10}]''::jsonb)'),
        ('invoices', v_shop, 'record_invoice_payment(''' || (i->>'inv') || ''', 100)'),
        ('invoices', v_shop, 'cancel_invoice(''' || (i->>'inv2') || ''')'),
        ('invoices', v_shop, 'list_invoices(' || v_shop || ')'),
        ('invoices', v_shop, 'invoice_header(''' || (i->>'inv') || ''')'),
        ('invoices', v_shop, 'invoice_lines_of(''' || (i->>'inv') || ''')'),
        ('credits', v_shop, 'record_credit_sale(' || v_shop || ', ''Awa 11'', 500, ''Riz'')'),
        ('credits', v_shop, 'record_debt_payment(''' || (i->>'debt') || ''', 100)'),
        ('credits', v_shop, 'customer_debts(' || v_shop || ')'),
        ('credits', v_shop, 'debts_of_customer(' || v_shop || ', gen_random_uuid())'),
        ('corrections', v_shop, 'record_return(''' || (i->>'sale') || ''')'),
        ('corrections', v_shop, 'reverse_receipt(''' || (i->>'rcpt') || ''')'),
        ('production', v_shop, 'record_production(' || v_shop || ', 1, ''[{"product_id": "10400000-0000-0000-0000-0000000000a2", "quantity": 1}]''::jsonb, p_product_name => ''Gâteau 11'')'),
        ('production', v_shop, 'update_production_run(''' || (i->>'run') || ''', p_note => ''n'')'),
        ('production', v_shop, 'production_history(' || v_shop || ')'),
        ('tontines', v_basic, 'advance_tontine_round(''' || (i->>'ton') || ''')'),
        ('tontines', v_basic, 'tontine_round_status(''' || (i->>'ton') || ''')'),
        ('tontines', v_basic, 'spend_cauris(' || v_basic || ', ''tontines'')'),
        ('payroll', v_basic, 'record_shift(' || v_basic || ', ''10400000-0000-0000-0000-0000000000e1'', 4)'),
        ('payroll', v_basic, 'pay_employee(' || v_basic || ', ''10400000-0000-0000-0000-0000000000e1'', 1000)'),
        ('payroll', v_basic, 'unpaid_shifts(' || v_basic || ')'),
        ('analytics', v_basic, 'org_sales_headline(' || v_basic || ')'),
        ('analytics', v_basic, 'org_product_performance(' || v_basic || ')'),
        ('analytics', v_basic, 'org_sales_by_hour(' || v_basic || ')'),
        ('analytics', v_basic, 'org_sales_by_weekday(' || v_basic || ')'),
        ('analytics', v_basic, 'org_sales_daily(' || v_basic || ')'),
        ('analytics', v_farm, 'farm_analytics(' || v_farm || ')'),
        ('accounting', v_basic, 'chart_of_accounts(' || v_basic || ')'),
        ('accounting', v_basic, 'create_account(' || v_basic || ', ''Caisse 11'', ''asset'')'),
        ('accounting', v_basic, 'trial_balance(' || v_basic || ')'),
        ('accounting', v_basic, 'income_statement(' || v_basic || ')'),
        ('accounting', v_basic, 'balance_sheet(' || v_basic || ')'),
        ('accounting', v_basic, 'account_ledger(' || v_basic || ', gen_random_uuid())')
    ) v(key, org, door)
    loop
        -- Hidden, by Mara, for this business.
        perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
        perform platform_set_feature_rule('org', null, trim(both '''' from r.org)::uuid, r.key, 'hidden');
        -- Its owner knocks (the farm's owner on the farm).
        perform set_config('request.jwt.claim.sub',
            case when r.org = v_farm then '10404040-0000-0000-0000-000000000004'
                 else '10404040-0000-0000-0000-000000000002' end, true);
        v_got := zz_b104_try('select * from ' || r.door);
        if v_got <> v_want then
            raise exception 'FAIL: % with « % » hidden answered: %', r.door, r.key, v_got;
        end if;
        -- Mara herself, inside the business, meets the same door.
        perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
        v_got := zz_b104_try('select * from ' || r.door);
        if v_got <> v_want then
            raise exception 'FAIL: Mara inside the business passed % hidden: %', r.door, v_got;
        end if;
        -- Visible again: the door opens (or answers for its own reasons).
        perform platform_set_feature_rule('org', null, trim(both '''' from r.org)::uuid, r.key, 'default');
        perform set_config('request.jwt.claim.sub',
            case when r.org = v_farm then '10404040-0000-0000-0000-000000000004'
                 else '10404040-0000-0000-0000-000000000002' end, true);
        v_got := zz_b104_try('select * from ' || r.door);
        if v_got like 'MA002%' then
            raise exception 'FAIL: % still refused once visible', r.door;
        end if;
        v_tested := v_tested || r.key;
    end loop;
    -- A direct write, as the app writes its tontines: the trigger refuses.
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    perform platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000002', 'tontines', 'hidden');
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000002', true);
    foreach v_got in array array[
        $q$insert into tontines (org_id, name, amount, created_by) values ('10400000-0000-0000-0000-000000000002', 'T', 10, '10404040-0000-0000-0000-000000000002')$q$,
        format($q$insert into tontine_members (tontine_id, org_id, name, position) values (%L, '10400000-0000-0000-0000-000000000002', 'B', 2)$q$, i->>'ton'),
        format($q$insert into tontine_contributions (tontine_id, member_id, org_id, round, amount, created_by) values (%L, %L, '10400000-0000-0000-0000-000000000002', 1, 1000, '10404040-0000-0000-0000-000000000002')$q$, i->>'ton', i->>'mem')] loop
        if zz_b104_try(v_got) <> v_want then
            raise exception 'FAIL: a direct write passed a hidden tontine: % → %', v_got, zz_b104_try(v_got);
        end if;
    end loop;
    -- No door left untested (the vitrine's, 110, are knocked on in test_batch110).
    execute 'reset role';
    select string_agg(key, ', ') into v_missing from feature_catalog
     where not (key = any (v_tested)) and grp <> 'Vitrine';
    if v_missing is not null then
        raise exception 'FAIL: no door tested for %', v_missing;
    end if;
    raise notice 'PASS: % doors over every catalog key refuse a hidden tool in French (MA002) — to its owner and to Mara inside — and open again once visible; a direct write too',
        array_length(v_tested, 1);
end $$;
rollback;

do $$
declare v_missing text;
begin
    -- And structurally: each catalog key is named by a trigger or by a
    -- function that calls feature_guard — a key with neither is a dead
    -- switch, refused here before it ships. The vitrine's keys (110) are
    -- held to the same by test_batch110, once 110 is put back over what
    -- the suites before it re-applied.
    select string_agg(c.key, ', ') into v_missing
      from feature_catalog c
     where c.grp <> 'Vitrine'
       and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                        where n.nspname = 'public'
                          and p.prosrc like '%feature_guard(%''' || c.key || '''%')
       and not exists (select 1 from pg_trigger t
                        where t.tgfoid = 'trg_feature_hidden'::regproc
                          and split_part(encode(t.tgargs, 'escape'), '\000', 1) = c.key);
    if v_missing is not null then
        raise exception 'FAIL: dead switches: %', v_missing;
    end if;
    raise notice 'PASS: every catalog key has a server door (a trigger or a guarded function)';
end $$;

\echo ''
\echo '--- TEST 7: the guard answers only inside the business ---'
begin;
set local role authenticated;
do $$
begin
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    perform platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000001', 'credits', 'hidden');
    -- A stranger learns nothing (the function behind answers them with nothing).
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000008', true);
    perform feature_guard('10400000-0000-0000-0000-000000000001', 'credits');
    if zz_b104_try($q$select * from customer_debts('10400000-0000-0000-0000-000000000001')$q$) <> 'ok' then
        raise exception 'FAIL: a stranger was told the carnet is hidden';
    end if;
    -- The employee is refused like the owner.
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000003', true);
    if zz_b104_try($q$select * from customer_debts('10400000-0000-0000-0000-000000000001')$q$) not like 'MA002%' then
        raise exception 'FAIL: an employee passed a hidden carnet';
    end if;
    raise notice 'PASS: a stranger learns nothing; an employee is refused as the owner is';
end $$;
rollback;
-- A job with no signed-in caller passes (a repair, a webhook).
do $$
begin
    insert into feature_rules (scope, org_id, feature, state)
    values ('org', '10400000-0000-0000-0000-000000000001', 'credits', 'hidden');
    perform set_config('request.jwt.claim.sub', '', true);
    perform feature_guard('10400000-0000-0000-0000-000000000001', 'credits');
    delete from feature_rules where org_id = '10400000-0000-0000-0000-000000000001';
    raise notice 'PASS: a job with no caller is not refused';
end $$;

\echo ''
\echo '--- TEST 8 (P3): every change is logged, the owner told, and undone once ---'
begin;
set local role authenticated;
do $$
declare
    v_hide uuid;
    v_show uuid;
    v_kind uuid;
    v_none uuid;
    v_until timestamptz;
    a record;
    v_n int;
begin
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    v_hide := platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000003', 'credits',
                                        'hidden', now() + interval '10 days', 'saison sèche');
    select * into a from platform_actions_page('10400000-0000-0000-0000-000000000003') where id = v_hide;
    if a.kind <> 'feature_rule' or a.org_name <> 'Ferme 11' or a.actor_label <> 'Mara Admin'
       or a.before is not null or a.after->>'state' <> 'hidden' or a.after->>'note' <> 'saison sèche'
       or not a.undoable or a.summary not like '« Carnet de crédit » masqué — Ferme 11 (jusqu''au %' then
        raise exception 'FAIL: the journal line is wrong: %', row_to_json(a);
    end if;
    -- Nothing moved: nothing logged.
    execute 'reset role';
    select until into v_until from feature_rules where org_id = '10400000-0000-0000-0000-000000000003';
    execute 'set local role authenticated';
    v_none := platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000003', 'credits',
                                        'hidden', v_until, 'saison sèche');
    if v_none is not null then
        raise exception 'FAIL: a change that changed nothing was logged';
    end if;
    -- The owner was told, once; nobody for a kind.
    v_kind := platform_set_feature_rule('kind', 'farm', null, 'invoices', 'hidden');
    execute 'reset role';
    select count(*) into v_n from notifications
     where kind = 'feature_rule' and recipient_id = '10404040-0000-0000-0000-000000000004'
       and params->>'feature' = 'credits' and params->>'state' = 'hidden'
       and message = 'Mara a masqué « Carnet de crédit » pour votre activité.';
    if v_n <> 1 then
        raise exception 'FAIL: the farm''s owner was told % times', v_n;
    end if;
    if exists (select 1 from notifications where kind = 'feature_rule' and params->>'feature' = 'invoices') then
        raise exception 'FAIL: a kind''s switch rang a bell';
    end if;
    if (select org_id from platform_actions where id = v_kind) is not null then
        raise exception 'FAIL: a kind''s switch was logged against a business';
    end if;
    execute 'set local role authenticated';
    -- A newer change, then the older undone: refused, it is stale.
    v_show := platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000003', 'credits', 'visible');
    if zz_b104_try(format('select platform_undo(%L)', v_hide))
       <> 'P0001: Ce réglage a changé depuis : annulez d''abord le changement plus récent.' then
        raise exception 'FAIL: a stale undo was run';
    end if;
    -- Newest first: undone, then the older one.
    perform platform_undo(v_show);
    if not zz_b104_hidden('10400000-0000-0000-0000-000000000003', 'credits') then
        raise exception 'FAIL: the undo did not bring the hidden switch back';
    end if;
    perform platform_undo(v_hide);
    if (select b->>'state' from jsonb_array_elements(
            platform_feature_board(null, '10400000-0000-0000-0000-000000000003')) b
         where b->>'key' = 'credits') <> 'default'
       or zz_b104_hidden('10400000-0000-0000-0000-000000000003', 'credits') then
        raise exception 'FAIL: the undo did not clear the switch';
    end if;
    if zz_b104_try(format('select platform_undo(%L)', v_hide)) <> 'P0001: Cette action a déjà été annulée.' then
        raise exception 'FAIL: an action was undone twice';
    end if;
    select * into a from platform_actions_page() where id = v_hide;
    if a.undoable or a.undone_at is null or a.undone_by_label <> 'Mara Admin' then
        raise exception 'FAIL: the journal does not say it was undone';
    end if;
    -- The kind's switch, undone: every farm has its invoices again.
    perform platform_undo(v_kind);
    if zz_b104_hidden('10400000-0000-0000-0000-000000000003', 'invoices') then
        raise exception 'FAIL: the kind''s undo did not restore';
    end if;
    raise notice 'PASS: logged with before/after, nothing logged for no change, the owner told and nobody for a kind, a stale undo refused, undone once, newest first';
end $$;
rollback;

begin;
do $$
declare v_id uuid;
begin
    -- A line whose undo is not on the whitelist: never run.
    insert into platform_actions (kind, summary, undo_fn, undo_args)
    values ('x', 'piège', 'delete_org', '{}') returning id into v_id;
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    execute 'set local role authenticated';
    if zz_b104_try(format('select platform_undo(%L)', v_id)) <> 'P0001: Annulation inconnue : delete_org' then
        raise exception 'FAIL: an undo off the whitelist was run';
    end if;
    execute 'reset role';
    insert into platform_actions (kind, summary) values ('y', 'sans retour') returning id into v_id;
    execute 'set local role authenticated';
    if zz_b104_try(format('select platform_undo(%L)', v_id)) <> 'P0001: Cette action ne s''annule pas.' then
        raise exception 'FAIL: an action with no undo was "undone"';
    end if;
    execute 'reset role';
    -- And it cannot be written with one either.
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    if zz_b104_try($q$select platform_log_action(null, 'x', 'x', null, null, 'delete_org', '{}')$q$)
       <> 'P0001: Annulation inconnue : delete_org' then
        raise exception 'FAIL: a journal line was written with an undo off the whitelist';
    end if;
    raise notice 'PASS: an undo off the whitelist is never run nor written; a line with none says so';
end $$;
rollback;

\echo ''
\echo '--- TEST 9: no cauris spent on a hidden tool; Mara''s Pro complet still opens everything paid ---'
begin;
set local role authenticated;
do $$
declare v_before int;
begin
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    perform platform_set_feature_rule('kind', 'retail', null, 'analytics', 'hidden');
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000007', true);
    v_before := cauris_balance('10400000-0000-0000-0000-000000000006');
    if zz_b104_try($q$select spend_cauris('10400000-0000-0000-0000-000000000006', 'analytics')$q$)
       not like 'MA002%' then
        raise exception 'FAIL: cauris were spent on a hidden tool';
    end if;
    if cauris_balance('10400000-0000-0000-0000-000000000006') <> v_before then
        raise exception 'FAIL: the balance moved';
    end if;
    -- The whole of Pro, bought with its cauris: paid, so every Pro tool shows.
    perform spend_cauris('10400000-0000-0000-0000-000000000006', 'pro_all');
    if zz_b104_hidden('10400000-0000-0000-0000-000000000006', 'analytics') then
        raise exception 'FAIL: Mara Pro complet bought with cauris left a Pro tool hidden';
    end if;
    raise notice 'PASS: no cauris for a hidden tool; Pro complet bought with cauris is paid';
end $$;
rollback;

\echo ''
\echo '--- TEST 10: the journal pages by (at, id): lines of one moment are never skipped ---'
begin;
do $$
declare
    v_logged uuid[] := '{}';
    v_seen   uuid[];
    v_page   record;
    v_at     timestamptz;
    v_id     uuid;
    v_n      int;
    i        int;
    v_round  int;
begin
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    -- Five lines in one transaction, as a bulk call writes them.
    for i in 1..5 loop
        v_logged := v_logged || platform_log_action('10400000-0000-0000-0000-000000000004',
            'bulk_test', 'ligne ' || i, null, null, null, null);
    end loop;
    if (select count(distinct at) from platform_actions where id = any (v_logged)) <> 5 then
        raise exception 'FAIL: the lines of one transaction share a moment';
    end if;
    for v_round in 1..2 loop
        -- The second round: every line forced to the same moment.
        if v_round = 2 then
            update platform_actions set at = '2026-01-01 12:00:00+00' where id = any (v_logged);
        end if;
        execute 'set local role authenticated';
        v_seen := '{}'; v_at := null; v_id := null;
        loop
            v_n := 0;
            for v_page in select * from platform_actions_page(
                    '10400000-0000-0000-0000-000000000004', 2, v_at, v_id) loop
                v_seen := v_seen || v_page.id;
                v_at := v_page.at; v_id := v_page.id;
                v_n := v_n + 1;
            end loop;
            exit when v_n < 2;
        end loop;
        execute 'reset role';
        if array_length(v_seen, 1) <> 5
           or (select count(distinct x) from unnest(v_seen) x) <> 5
           or not (v_seen @> v_logged and v_logged @> v_seen) then
            raise exception 'FAIL: round %: paged % lines for 5: %', v_round, array_length(v_seen, 1), v_seen;
        end if;
    end loop;
    raise notice 'PASS: five lines of one transaction, paged two by two, come back exactly once — even sharing one moment';
end $$;
rollback;

\echo ''
\echo '--- TEST 11: a rule left over from a former kind decides nothing, is shown and cleared; the impact line refuses what the switch refuses ---'
begin;
do $$
declare
    b jsonb;
    a uuid;
    n int;
begin
    -- The farm's own Production hidden; then it becomes an association,
    -- which has no Production: the rule is left over.
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    execute 'set local role authenticated';
    perform platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000003', 'production', 'hidden');
    execute 'reset role';
    if not zz_b104_hidden('10400000-0000-0000-0000-000000000003', 'production') then
        raise exception 'FAIL: the farm''s own switch did not hide Production';
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    update orgs set profile = 'association' where id = '10400000-0000-0000-0000-000000000003';
    if zz_b104_hidden('10400000-0000-0000-0000-000000000003', 'production') then
        raise exception 'FAIL: a rule for a tool the kind does not have still hides it';
    end if;
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000004', true);
    execute 'set local role authenticated';
    if feature_states('10400000-0000-0000-0000-000000000003')->'hidden' ? 'production' then
        raise exception 'FAIL: feature_states still says Production is hidden';
    end if;
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    select x into b from jsonb_array_elements(platform_feature_board(null, '10400000-0000-0000-0000-000000000003')) x
     where x->>'key' = 'production';
    if b is null or not (b->>'leftover')::boolean or b->>'state' <> 'hidden' or b->>'effective' <> 'visible' then
        raise exception 'FAIL: the board does not show the leftover rule to clear: %', b;
    end if;
    if zz_b104_try($q$select platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000003', 'production', 'visible')$q$)
       <> 'P0001: Cette fonction n''existe pas pour ce type d''activité.' then
        raise exception 'FAIL: a leftover was switched instead of cleared';
    end if;
    execute 'reset role';
    select count(*) into n from notifications
     where recipient_id = '10404040-0000-0000-0000-000000000004' and kind = 'feature_rule';
    execute 'set local role authenticated';
    a := platform_set_feature_rule('org', null, '10400000-0000-0000-0000-000000000003', 'production', 'default');
    if a is null then
        raise exception 'FAIL: the leftover was not cleared';
    end if;
    if exists (select 1 from jsonb_array_elements(platform_feature_board(null, '10400000-0000-0000-0000-000000000003')) x
                where x->>'key' = 'production') then
        raise exception 'FAIL: the cleared leftover is still on the board';
    end if;
    execute 'reset role';
    if (select count(*) from notifications
         where recipient_id = '10404040-0000-0000-0000-000000000004' and kind = 'feature_rule') <> n then
        raise exception 'FAIL: clearing a leftover rang the owner about a tool they never had';
    end if;
    -- The impact line: only for a switch that could be saved.
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    execute 'set local role authenticated';
    if zz_b104_try($q$select platform_feature_impact('generic', 'credits', 'hidden')$q$) <> 'P0001: Type d''activité inconnu : generic'
       or zz_b104_try($q$select platform_feature_impact(null, 'credits', 'hidden')$q$) <> 'P0001: Type d''activité inconnu : '
       or zz_b104_try($q$select platform_feature_impact('retail', 'credits', 'masque')$q$) <> 'P0001: Réglage inconnu : masque'
       or zz_b104_try($q$select platform_feature_impact('association', 'production', 'hidden')$q$)
          <> 'P0001: Cette fonction n''existe pas pour ce type d''activité.'
       or zz_b104_try($q$select platform_feature_impact('church', 'credits', 'default')$q$) <> 'ok' then
        raise exception 'FAIL: the impact line answered for a switch that cannot be';
    end if;
    execute 'reset role';
    raise notice 'PASS: a farm turned association: its Production rule hides nothing, the board shows it « leftover » to clear, it cannot be switched, cleared without a bell; the impact line refuses an unknown kind or state and a tool the kind does not have';
end $$;
rollback;

\echo ''
\echo '--- TEST 12: a kind''s rule hides a Pro tool, Mara Pro ends: the rule applies, the owner is told once per lapse, « À faire » lists it, renewing brings it back ---'
begin;
do $$
declare
    v_msg text := 'Votre Mara Pro a pris fin : Analyses n''est plus disponible pour votre activité.';
    n int;
begin
    -- Every shop's Analyses hidden; the Pro shop pays, so it keeps them.
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    execute 'set local role authenticated';
    perform platform_set_feature_rule('kind', 'retail', null, 'analytics', 'hidden');
    execute 'reset role';
    if not exists (select 1 from feature_pay_watch where org_id = '10400000-0000-0000-0000-000000000001'
                      and feature = 'analytics' and state = 'kept') then
        raise exception 'FAIL: the paying shop was not remembered as keeping its tool';
    end if;
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000002', true);
    execute 'set local role authenticated';
    if feature_states('10400000-0000-0000-0000-000000000001')->'hidden' ? 'analytics' then
        raise exception 'FAIL: a paid tool hidden';
    end if;
    execute 'reset role';

    -- Mara Pro ends (its date passed). Read twice: hidden, told once.
    perform set_config('request.jwt.claim.sub', '', true);
    update orgs set plan_until = current_date - 2 where id = '10400000-0000-0000-0000-000000000001';
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000002', true);
    execute 'set local role authenticated';
    if not feature_states('10400000-0000-0000-0000-000000000001')->'hidden' ? 'analytics' then
        raise exception 'FAIL: the admin''s rule did not apply once nothing pays';
    end if;
    perform feature_states('10400000-0000-0000-0000-000000000001');
    -- The owner spends cauris on it: still refused.
    if zz_b104_try($q$select spend_cauris('10400000-0000-0000-0000-000000000001', 'analytics')$q$) not like 'MA002%' then
        raise exception 'FAIL: cauris opened a hidden tool after the lapse';
    end if;
    execute 'reset role';
    select count(*) into n from notifications
     where recipient_id = '10404040-0000-0000-0000-000000000002' and kind = 'feature_lapsed' and message = v_msg
       and org_id = '10400000-0000-0000-0000-000000000001' and params->>'feature' = 'analytics';
    if n <> 1 then
        raise exception 'FAIL: the owner was told % times (once expected)', n;
    end if;
    if exists (select 1 from notifications where kind = 'feature_lapsed'
                  and recipient_id = '10404040-0000-0000-0000-000000000003') then
        raise exception 'FAIL: the employee was told the owner''s news';
    end if;

    -- « À faire »: the business and the tool.
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    execute 'set local role authenticated';
    if (platform_todo()->>'features_lapsed')::int < 1
       or not platform_todo_list('features_lapsed') @> '[{"org_name": "Boutique 11", "feature": "analytics", "label": "Analyses"}]' then
        raise exception 'FAIL: « À faire » does not list the tool hidden after the payment ended';
    end if;
    execute 'reset role';

    -- Renewed: back, off the list; ended again: told again.
    perform set_config('request.jwt.claim.sub', '', true);
    update orgs set plan_until = '2099-01-01' where id = '10400000-0000-0000-0000-000000000001';
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000002', true);
    execute 'set local role authenticated';
    if feature_states('10400000-0000-0000-0000-000000000001')->'hidden' ? 'analytics' then
        raise exception 'FAIL: renewing Mara Pro did not bring the tool back';
    end if;
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    if platform_todo_list('features_lapsed') @> '[{"org_name": "Boutique 11"}]' then
        raise exception 'FAIL: a renewed business still in « À faire »';
    end if;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '', true);
    update orgs set plan_until = current_date - 2 where id = '10400000-0000-0000-0000-000000000001';
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000002', true);
    execute 'set local role authenticated';
    perform feature_states('10400000-0000-0000-0000-000000000001');
    execute 'reset role';
    if (select count(*) from notifications
         where recipient_id = '10404040-0000-0000-0000-000000000002' and kind = 'feature_lapsed') <> 2 then
        raise exception 'FAIL: the second lapse was not told';
    end if;
    -- The rule back « Par défaut »: nothing remembered, nothing hidden.
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000001', true);
    execute 'set local role authenticated';
    perform platform_set_feature_rule('kind', 'retail', null, 'analytics', 'default');
    perform set_config('request.jwt.claim.sub', '10404040-0000-0000-0000-000000000002', true);
    if feature_states('10400000-0000-0000-0000-000000000001')->'hidden' ? 'analytics' then
        raise exception 'FAIL: the cleared rule still hides';
    end if;
    execute 'reset role';
    if exists (select 1 from feature_pay_watch where org_id = '10400000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: a cleared rule left its watch';
    end if;
    raise notice 'PASS: Mara Pro ended under a kind''s rule — the tool hidden (cauris refused), the owner told once (not the employee), « À faire » lists it; renewed it is back and off the list; ended again, told again; the rule cleared, nothing left';
end $$;
rollback;

drop function zz_b104_try(text);
drop function zz_b104_hidden(uuid, text);
drop table if exists b104_ids;
update platform_settings set value = '0' where key = 'path_gates_open';

\echo ''
\echo '=== test_batch104.sql: all checks passed ==='
