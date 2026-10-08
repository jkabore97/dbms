-- ============================================================
-- test_batch108.sql — the owner's fixes the database holds (108).
--
-- The claims, for a shop, a farm and an association (and a legacy church)
-- alike:
--   P1. Installing 108 moves nothing else: every purchase that went
--       through before goes through the same — the same answer, the same
--       cauris taken, the same days opened — and every refusal of before
--       (an employee, too few cauris, a hidden tool, the photo slot, an
--       unknown tool) is said the same: computed with 108's spend_cauris,
--       then with 104's put back verbatim in the same transaction (now()
--       is one moment there), and compared. feature_states is untouched.
--   1. E3: Le Chemin's « pin » step names the business's place — « La
--      position de ma boutique », « La position de ma ferme »; a title Mara
--      changed by hand is kept when 108 runs again.
--   2. E5, the wait: a new business is told « Disponible avec vos cauris
--      dans 60 jours, le … » with the day, nothing taken; once the
--      platform sets the wait to 0, the same cauris open the tool.
--   3. E5, the audit: with enough cauris and no wait, every tool a kind
--      has opens, for every kind; a tool the kind does not have (the
--      analyses and the delivery of an association) is refused with its
--      reason and takes nothing; a paid Mara Pro is not charged for what
--      it has; Mara Pro complet bought with cauris may still buy a tool;
--      a photo slot is bought wherever there is a photo limit.
--   4. 104's refusal of a hidden tool is kept (110 relies on it).
--   P3. platform_set_cauris_cost is the platform's alone, checked on the
--       server, journaled with its « Annuler », undone once, a stale undo
--       refused; 085's set_cauris_cost goes through it and keeps the
--       wait; the internals closed to the app, everything closed to the
--       street.
-- ============================================================
\set ON_ERROR_STOP on
\set mara     '''10810810-0000-0000-0000-000000000001'''
\set shopo    '''10810810-0000-0000-0000-000000000002'''
\set farmo    '''10810810-0000-0000-0000-000000000003'''
\set assoo    '''10810810-0000-0000-0000-000000000004'''
\set churcho  '''10810810-0000-0000-0000-000000000005'''
\set proo     '''10810810-0000-0000-0000-000000000006'''
\set clerk    '''10810810-0000-0000-0000-000000000007'''
\set newo     '''10810810-0000-0000-0000-000000000008'''
\set shop1    '''10800000-0000-0000-0000-000000000001'''
\set farm1    '''10800000-0000-0000-0000-000000000002'''
\set asso1    '''10800000-0000-0000-0000-000000000003'''
\set church1  '''10800000-0000-0000-0000-000000000004'''
\set pro1     '''10800000-0000-0000-0000-000000000005'''
\set new1     '''10800000-0000-0000-0000-000000000006'''
\set allpro   '''10800000-0000-0000-0000-000000000007'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
-- Earlier suites re-apply older migrations over 108's functions (085, 100,
-- 104…): 108 again.
\i database/migrations/108_owner_fixes.sql

-- The prices and waits as the suite found them: put back at the end.
create temp table b108_costs as select * from cauris_costs;
-- The prices as 085 and 100 seeded them, which every case below counts on.
update cauris_costs c set cost = v.cost, min_days = v.min_days
  from (values ('analytics', 400, 0), ('delivery', 600, 0), ('online_payment', 500, 0),
               ('vitrine_plus', 300, 0), ('accounting', 500, 60), ('team_access', 400, 0),
               ('payroll', 400, 0), ('currencies', 300, 0), ('tontines', 500, 90),
               ('pro_all', 1500, 0), ('photo_slot', 50, 0)) v(feature, cost, min_days)
 where c.feature = v.feature;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:mara,    '+22610810001', '{"full_name": "Mara"}'),
    (:shopo,   '+22610810002', '{"full_name": "Awa Boutique"}'),
    (:farmo,   '+22610810003', '{"full_name": "Fermier"}'),
    (:assoo,   '+22610810004', '{"full_name": "Trésorière"}'),
    (:churcho, '+22610810005', '{"full_name": "Pasteur"}'),
    (:proo,    '+22610810006', '{"full_name": "Pro"}'),
    (:clerk,   '+22610810007', '{"full_name": "Vendeur"}'),
    (:newo,    '+22610810008', '{"full_name": "Nouvelle"}');
update profiles set is_platform_admin = true where id = :mara;

insert into orgs (id, name, slug, profile, default_currency, plan, plan_until, storefront_enabled,
                  setup_done_at, created_at) values
    (:shop1,   'Boutique 108', 'boutique-108', 'retail',      'XOF', 'free', null, true, now(), now() - interval '200 days'),
    (:farm1,   'Ferme 108',    'ferme-108',    'farm',        'XOF', 'free', null, true, now(), now() - interval '200 days'),
    (:asso1,   'Entraide 108', 'entraide-108', 'association', 'XOF', 'free', null, true, now(), now() - interval '200 days'),
    (:church1, 'Église 108',   'eglise-108',   'church',      'XOF', 'free', null, true, now(), now() - interval '200 days'),
    (:pro1,    'Pro 108',      'pro-108',      'retail',      'XOF', 'pro',  null, true, now(), now() - interval '200 days'),
    (:new1,    'Neuve 108',    'neuve-108',    'retail',      'XOF', 'free', null, true, now(), now()),
    (:allpro,  'Complet 108',  'complet-108',  'retail',      'XOF', 'free', null, true, now(), now() - interval '200 days');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop1,   :shopo,   'owner',    'org', :shop1,   'full'),
    (:shop1,   :clerk,   'employee', 'org', :shop1,   'full'),
    (:farm1,   :farmo,   'owner',    'org', :farm1,   'full'),
    (:asso1,   :assoo,   'owner',    'org', :asso1,   'full'),
    (:church1, :churcho, 'owner',    'org', :church1, 'full'),
    (:pro1,    :proo,    'owner',    'org', :pro1,    'full'),
    (:new1,    :newo,    'owner',    'org', :new1,    'full'),
    (:allpro,  :shopo,   'owner',    'org', :allpro,  'full');
-- Mara Pro complet bought with cauris, open for ten more days.
insert into cauris_unlocks (org_id, feature, until) values (:allpro, 'pro_all', now() + interval '10 days');

-- Internal: a statement's answer, or its refusal, as one line.
create function pg_temp.try(p_sql text) returns text
language plpgsql
as $$
declare
    v_state text;
    v_msg   text;
    v_out   text;
begin
    execute p_sql into v_out;
    return coalesce(v_out, 'ok');
exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return v_state || ': ' || v_msg;
end;
$$;

-- A purchase tried and taken back: its answer (or refusal), the cauris it
-- took and the days it opened — by the function named, as [p_user].
create function pg_temp.spend_as(p_fn text, p_org uuid, p_user uuid, p_feature text,
                                 p_give int default 5000)
returns jsonb
language plpgsql
as $$
declare
    v_out jsonb;
begin
    begin
        if p_give > 0 then
            insert into cauris_ledger (org_id, delta, reason, ref)
            values (p_org, p_give, 'prize', 't108:' || p_feature || ':' || p_fn);
        end if;
        perform set_config('request.jwt.claim.sub', p_user::text, true);
        begin
            execute format('select %s($1, $2)::text', p_fn) into v_out using p_org, p_feature;
            v_out := jsonb_build_object('answer', v_out::jsonb);
        exception when others then
            v_out := jsonb_build_object('refused', sqlerrm);
        end;
        perform set_config('request.jwt.claim.sub', '', true);
        v_out := v_out || jsonb_build_object(
            'balance', cauris_balance(p_org),
            'spent', (select coalesce(sum(-delta), 0) from cauris_ledger
                       where org_id = p_org and reason = 'spent'),
            'unlocks', (select coalesce(jsonb_object_agg(u.feature, u.until), '{}'::jsonb)
                          from cauris_unlocks u where u.org_id = p_org));
        -- Taken back: the next case starts from the same wallet.
        raise exception using errcode = 'P0108', message = v_out::text;
    exception when sqlstate 'P0108' then
        return sqlerrm::jsonb;
    end;
end;
$$;

-- 104's spend_cauris, verbatim, for P1.
create function pg_temp.spend_104(p_org_id uuid, p_feature text)
returns jsonb
language plpgsql
set search_path = public, auth
as $$
declare
    v_cost   cauris_costs%rowtype;
    v_org    orgs%rowtype;
    v_until  timestamptz;
    v_days   int := cauris_param('cauris_unlock_days', 30);
    v_after  int;
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur dépense les cauris de l''entreprise';
    end if;
    -- The business moves: a payment that ended under a rule is noticed.
    perform feature_lapse_watch(p_org_id);
    -- No cauris for a tool the platform hid here (104).
    perform feature_guard(p_org_id, c.key) from feature_catalog c where c.pro_tool = p_feature;
    select * into v_cost from cauris_costs where feature = p_feature;
    if not found or p_feature = 'photo_slot' then
        raise exception 'Cet outil ne s''ouvre pas avec des cauris';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if v_cost.min_days > 0 and v_org.created_at > now() - make_interval(days => v_cost.min_days) then
        raise exception 'Cet outil s''ouvre avec des cauris après % jours sur Mara', v_cost.min_days;
    end if;

    v_after := cauris_take(p_org_id, v_cost.cost,
                           p_feature || ':' || gen_random_uuid()::text, p_feature);

    select greatest(coalesce(u.until, now()), now()) + make_interval(days => v_days)
      into v_until
      from (select 1) x left join cauris_unlocks u
        on u.org_id = p_org_id and u.feature = p_feature;

    insert into cauris_unlocks (org_id, feature, until)
    values (p_org_id, p_feature, v_until)
    on conflict (org_id, feature) do update
        set until = excluded.until, updated_at = now(), note = null, gifted_by = null;

    return jsonb_build_object('feature', p_feature, 'until', v_until,
                              'balance', v_after);
end;
$$;

\echo ''
\echo '--- TEST P1: every purchase and every refusal of before, the same with 108 ---'
begin;
-- A tool hidden here by Mara (104), for the refusal that says so.
insert into feature_rules (scope, org_id, feature, state)
values ('org', '10800000-0000-0000-0000-000000000002', 'payroll', 'hidden');
do $$
declare
    c       record;
    a       jsonb;
    b       jsonb;
    n       int := 0;
    v_shop  uuid := '10800000-0000-0000-0000-000000000001';
    v_farm  uuid := '10800000-0000-0000-0000-000000000002';
    v_asso  uuid := '10800000-0000-0000-0000-000000000003';
    v_ch    uuid := '10800000-0000-0000-0000-000000000004';
    v_all   uuid := '10800000-0000-0000-0000-000000000007';
    s_shop  uuid := '10810810-0000-0000-0000-000000000002';
    s_farm  uuid := '10810810-0000-0000-0000-000000000003';
    s_asso  uuid := '10810810-0000-0000-0000-000000000004';
    s_ch    uuid := '10810810-0000-0000-0000-000000000005';
    s_clerk uuid := '10810810-0000-0000-0000-000000000007';
    before_states jsonb;
begin
    -- feature_states before and after nothing but 108: read as the owners.
    perform set_config('request.jwt.claim.sub', s_shop::text, true);
    before_states := feature_states(v_shop);
    for c in select * from (values
        -- what went through before
        (v_shop, s_shop, 'analytics', 5000), (v_shop, s_shop, 'pro_all', 5000),
        (v_shop, s_shop, 'accounting', 5000), (v_shop, s_shop, 'tontines', 5000),
        (v_shop, s_shop, 'delivery', 5000), (v_shop, s_shop, 'vitrine_plus', 5000),
        (v_farm, s_farm, 'analytics', 5000), (v_farm, s_farm, 'currencies', 5000),
        (v_farm, s_farm, 'online_payment', 5000),
        (v_asso, s_asso, 'accounting', 5000), (v_asso, s_asso, 'tontines', 5000),
        (v_asso, s_asso, 'team_access', 5000), (v_asso, s_asso, 'pro_all', 5000),
        (v_ch,   s_ch,   'payroll', 5000), (v_ch, s_ch, 'vitrine_plus', 5000),
        (v_all,  s_shop, 'analytics', 5000),
        -- the refusals of before
        (v_shop, s_clerk, 'analytics', 5000),   -- an employee
        (v_shop, s_shop, 'pro_all', 0),         -- too few cauris
        (v_farm, s_farm, 'payroll', 5000),      -- hidden by Mara (104)
        (v_shop, s_shop, 'photo_slot', 5000),   -- not a tool
        (v_shop, s_shop, 'nope', 5000)          -- unknown
    ) x(org, who, feature, give) loop
        a := pg_temp.spend_as('spend_cauris', c.org, c.who, c.feature, c.give);
        b := pg_temp.spend_as('pg_temp.spend_104', c.org, c.who, c.feature, c.give);
        if a <> b then
            raise exception 'FAIL: % for % moved with 108: % / before: %', c.feature, c.org, a, b;
        end if;
        n := n + 1;
    end loop;
    perform set_config('request.jwt.claim.sub', s_shop::text, true);
    if feature_states(v_shop) <> before_states then
        raise exception 'FAIL: feature_states moved';
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    raise notice 'PASS: % purchases and refusals of before, answer for answer, cauris for cauris, day for day — shop, farm, association, church', n;
end $$;
rollback;

\echo ''
\echo '--- TEST 1: Le Chemin''s « pin » step names the business''s place (E3) ---'
do $$
declare
    s path_steps%rowtype;
begin
    select * into s from path_steps where key = 'pin';
    if path_text(s.title, s.title_farm, 'retail') <> 'La position de ma boutique'
       or path_text(s.title, s.title_farm, 'farm') <> 'La position de ma ferme' then
        raise exception 'FAIL: the pin step says %', to_jsonb(s);
    end if;
    if exists (select 1 from path_steps where title ilike 'Ma position%' or title_farm ilike 'Ma position%') then
        raise exception 'FAIL: a step still says « Ma position »';
    end if;
    raise notice 'PASS: « La position de ma boutique » for a shop, « La position de ma ferme » for a farm';
end $$;
-- A title Mara changed by hand is kept when 108 runs again.
update path_steps set title = 'Notre adresse sur la carte' where key = 'pin';
\i database/migrations/108_owner_fixes.sql
do $$ begin
    if (select title from path_steps where key = 'pin') <> 'Notre adresse sur la carte' then
        raise exception 'FAIL: 108 overwrote a title changed since';
    end if;
    raise notice 'PASS: 108 again leaves a title changed since as it is';
end $$;
update path_steps set title = 'La position de ma boutique' where key = 'pin';

\echo ''
\echo '--- TEST 2: the wait, said with its day; once lifted, the same cauris open the tool (E5) ---'
begin;
do $$
declare
    v_new  uuid := '10800000-0000-0000-0000-000000000006';
    s_new  uuid := '10810810-0000-0000-0000-000000000008';
    st     jsonb;
    r      jsonb;
    v_day  text := to_char(((select created_at from orgs where id = '10800000-0000-0000-0000-000000000006')
                            + interval '60 days') at time zone 'Africa/Ouagadougou', 'DD/MM/YYYY');
    v_act  uuid;
begin
    perform set_config('request.jwt.claim.sub', s_new::text, true);
    st := feature_states(v_new);
    if (select (t ->> 'waits_days')::int from jsonb_array_elements(st -> 'tools') t
         where t ->> 'feature' = 'accounting') <> 60
       or (select (t ->> 'waits_days')::int from jsonb_array_elements(st -> 'tools') t
            where t ->> 'feature' = 'tontines') <> 90 then
        raise exception 'FAIL: the waits are not said: %', st -> 'tools';
    end if;
    r := pg_temp.spend_as('spend_cauris', v_new, s_new, 'accounting');
    if r ->> 'refused' <> 'Disponible avec vos cauris dans 60 jours, le ' || v_day
                          || ' : il faut un peu d''activité pour que cet outil serve.'
       or (r ->> 'spent')::int <> 0 or r -> 'unlocks' <> '{}'::jsonb then
        raise exception 'FAIL: the wait is not said with its day, or cauris moved: %', r;
    end if;
    -- Mara lifts the wait.
    perform set_config('request.jwt.claim.sub', '10810810-0000-0000-0000-000000000001', true);
    v_act := platform_set_cauris_cost('accounting', 500, 0);
    perform set_config('request.jwt.claim.sub', s_new::text, true);
    st := feature_states(v_new);
    if (select t ->> 'waits_days' from jsonb_array_elements(st -> 'tools') t
         where t ->> 'feature' = 'accounting') is not null then
        raise exception 'FAIL: the wait outlived its lifting';
    end if;
    r := pg_temp.spend_as('spend_cauris', v_new, s_new, 'accounting', 500);
    if r ? 'refused' or (r ->> 'spent')::int <> 500 or (r #>> '{answer,balance}')::int <> 0
       or not (r -> 'unlocks' ? 'accounting') then
        raise exception 'FAIL: exactly enough cauris did not open accounting: %', r;
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    raise notice 'PASS: « Disponible avec vos cauris dans 60 jours, le % », nothing taken; the wait lifted, 500 cauris open accounting', v_day;
end $$;
rollback;

\echo ''
\echo '--- TEST 3: with enough cauris, every tool a kind has opens; what it has not is refused with its reason (E5 audit) ---'
begin;
update orgs set created_at = now() - interval '200 days'
 where id = '10800000-0000-0000-0000-000000000006';
do $$
declare
    c       record;
    f       record;
    r       jsonb;
    v_fits  boolean;
    v_open  text;
    v_line  text := '';
begin
    for c in select * from (values
        ('10800000-0000-0000-0000-000000000006'::uuid, '10810810-0000-0000-0000-000000000008'::uuid, 'retail'),
        ('10800000-0000-0000-0000-000000000002'::uuid, '10810810-0000-0000-0000-000000000003'::uuid, 'farm'),
        ('10800000-0000-0000-0000-000000000003'::uuid, '10810810-0000-0000-0000-000000000004'::uuid, 'association'),
        ('10800000-0000-0000-0000-000000000004'::uuid, '10810810-0000-0000-0000-000000000005'::uuid, 'church')
    ) x(org, who, kind) loop
        v_open := '';
        for f in select feature, cost from cauris_costs where feature <> 'photo_slot' order by sort loop
            -- The app's PlanTerms.fits, and the catalog's kinds.
            v_fits := not ((f.feature = 'analytics' and c.kind not in ('retail', 'farm'))
                           or (f.feature = 'delivery' and c.kind in ('association', 'church')));
            r := pg_temp.spend_as('spend_cauris', c.org, c.who, f.feature, f.cost);
            if v_fits then
                if r ? 'refused' or (r ->> 'spent')::int <> f.cost or (r #>> '{answer,balance}')::int <> 0
                   or not (r -> 'unlocks' ? f.feature) then
                    raise exception 'FAIL: % cauris did not open % for a %: %', f.cost, f.feature, c.kind, r;
                end if;
                v_open := v_open || f.feature || ' ';
            elsif r ->> 'refused' <> 'Cet outil n''existe pas pour votre activité : vos cauris restent à vous.'
                  or (r ->> 'spent')::int <> 0 or (r ->> 'balance')::int <> f.cost then
                raise exception 'FAIL: a % was charged for %, a tool it has not: %', c.kind, f.feature, r;
            end if;
        end loop;
        v_line := v_line || c.kind || ': ' || v_open || '| ';
    end loop;
    raise notice 'PASS: exactly enough cauris open, per kind — %', v_line;
end $$;
rollback;

-- A paid Mara Pro is not charged; Pro complet bought with cauris may buy.
begin;
do $$
declare r jsonb;
begin
    r := pg_temp.spend_as('spend_cauris', '10800000-0000-0000-0000-000000000005',
                          '10810810-0000-0000-0000-000000000006', 'analytics');
    if r ->> 'refused' <> 'Votre entreprise est sur Mara Pro : cet outil est déjà ouvert, vos cauris restent à vous.'
       or (r ->> 'spent')::int <> 0 then
        raise exception 'FAIL: a paid Pro was charged for a tool it has: %', r;
    end if;
    r := pg_temp.spend_as('spend_cauris', '10800000-0000-0000-0000-000000000007',
                          '10810810-0000-0000-0000-000000000002', 'analytics');
    if r ? 'refused' or (r ->> 'spent')::int <> 400 then
        raise exception 'FAIL: Pro complet bought with cauris could not buy a tool to keep: %', r;
    end if;
    raise notice 'PASS: a paid Pro keeps its cauris; Pro complet in cauris may still buy a tool to keep';
end $$;
rollback;

-- A photo slot, wherever there is a photo limit, with enough cauris.
begin;
do $$
declare
    c   record;
    v   jsonb;
    n   int := 0;
begin
    for c in select * from (values
        ('10800000-0000-0000-0000-000000000001'::uuid, '10810810-0000-0000-0000-000000000002'::uuid),
        ('10800000-0000-0000-0000-000000000002'::uuid, '10810810-0000-0000-0000-000000000003'::uuid),
        ('10800000-0000-0000-0000-000000000003'::uuid, '10810810-0000-0000-0000-000000000004'::uuid),
        ('10800000-0000-0000-0000-000000000004'::uuid, '10810810-0000-0000-0000-000000000005'::uuid)
    ) x(org, who) loop
        continue when org_photo_limit(c.org) is null;
        insert into cauris_ledger (org_id, delta, reason, ref) values (c.org, 50, 'prize', 't108:slot');
        perform set_config('request.jwt.claim.sub', c.who::text, true);
        v := buy_photo_slot(c.org);
        perform set_config('request.jwt.claim.sub', '', true);
        if (v ->> 'slots')::int < 1 then
            raise exception 'FAIL: 50 cauris did not buy a photo slot for %: %', c.org, v;
        end if;
        n := n + 1;
    end loop;
    if n < 2 then
        raise exception 'FAIL: no photo limit to buy into';
    end if;
    raise notice 'PASS: 50 cauris buy a photo slot in each of the % businesses with a photo limit', n;
end $$;
rollback;

\echo ''
\echo '--- TEST 4: no cauris for a tool Mara hid here — 104''s refusal kept ---'
begin;
insert into feature_rules (scope, org_id, feature, state)
values ('org', '10800000-0000-0000-0000-000000000001', 'accounting', 'hidden');
do $$
declare r jsonb;
begin
    r := pg_temp.spend_as('spend_cauris', '10800000-0000-0000-0000-000000000001',
                          '10810810-0000-0000-0000-000000000002', 'accounting');
    if r ->> 'refused' not like 'Pas disponible%' or (r ->> 'spent')::int <> 0 then
        raise exception 'FAIL: cauris were taken for a hidden tool: %', r;
    end if;
    raise notice 'PASS: a hidden tool is refused, nothing taken: %', r ->> 'refused';
end $$;
rollback;

\echo ''
\echo '--- TEST P3: the price and the wait — the platform''s alone, journaled, undone once, never stale ---'
do $$
declare
    v_act  uuid;
    v_act2 uuid;
    a      platform_actions%rowtype;
begin
    -- Nobody else: an owner, an anonymous caller.
    perform set_config('request.jwt.claim.sub', '10810810-0000-0000-0000-000000000002', true);
    if pg_temp.try($q$select platform_set_cauris_cost('accounting', 10, 0)$q$) <> 'P0001: Réservé à la plateforme'
       or pg_temp.try($q$select set_cauris_cost('accounting', 10)$q$) not like '%Only the platform%' then
        raise exception 'FAIL: an owner set a price';
    end if;
    perform set_config('request.jwt.claim.sub', '10810810-0000-0000-0000-000000000001', true);
    -- Checked on the server.
    if pg_temp.try($q$select platform_set_cauris_cost('accounting', 0, 0)$q$) <> 'P0001: Prix hors limites'
       or pg_temp.try($q$select platform_set_cauris_cost('accounting', 500, -1)$q$) not like 'P0001: Une attente de 0 à 3650 jours%'
       or pg_temp.try($q$select platform_set_cauris_cost('accounting', 500, 4000)$q$) not like 'P0001: Une attente de 0 à 3650 jours%'
       or pg_temp.try($q$select platform_set_cauris_cost('photo_slot', 50, 5)$q$) <> 'P0001: Une place photo s''achète sans attente.'
       or pg_temp.try($q$select platform_set_cauris_cost('nope', 50, 0)$q$) <> 'P0001: Outil inconnu : nope' then
        raise exception 'FAIL: a bad price or wait was taken';
    end if;
    -- Nothing changed: nothing written.
    if platform_set_cauris_cost('accounting', 500, 60) is not null
       or exists (select 1 from platform_actions where kind = 'cauris_cost' and after ->> 'feature' = 'accounting'
                     and at > now() - interval '1 minute' and undone_at is null) then
        raise exception 'FAIL: an unchanged price was journaled';
    end if;
    -- A change: in the journal, before and after.
    v_act := platform_set_cauris_cost('accounting', 450, 30);
    select * into a from platform_actions where id = v_act;
    if a.kind <> 'cauris_cost' or a.before <> '{"feature": "accounting", "cost": 500, "min_days": 60}'::jsonb
       or a.after <> '{"feature": "accounting", "cost": 450, "min_days": 30}'::jsonb
       or a.summary <> 'Cauris, la comptabilité : 500 → 450 cauris, attente 60 → 30 jours'
       or (select (cost, min_days) from cauris_costs where feature = 'accounting') <> (450, 30) then
        raise exception 'FAIL: the change or its line: % %', to_jsonb(a),
            (select to_jsonb(c) from cauris_costs c where feature = 'accounting');
    end if;
    -- Undone once.
    perform platform_undo(v_act);
    if (select (cost, min_days) from cauris_costs where feature = 'accounting') <> (500, 60)
       or pg_temp.try(format('select platform_undo(%L)', v_act)) <> 'P0001: Cette action a déjà été annulée.' then
        raise exception 'FAIL: the undo did not put it back, or ran twice';
    end if;
    -- A stale undo refused: changed since.
    v_act := platform_set_cauris_cost('tontines', 500, 30);
    v_act2 := platform_set_cauris_cost('tontines', 500, 10);
    if pg_temp.try(format('select platform_undo(%L)', v_act)) not like 'P0001: Ce prix a changé depuis%' then
        raise exception 'FAIL: a stale undo was taken';
    end if;
    perform platform_undo(v_act2);
    perform platform_undo(v_act);
    if (select (cost, min_days) from cauris_costs where feature = 'tontines') <> (500, 90) then
        raise exception 'FAIL: the two undos did not walk back to 90 days';
    end if;
    -- 085's price alone: journaled, the wait kept.
    perform set_cauris_cost('tontines', 520);
    if (select (cost, min_days) from cauris_costs where feature = 'tontines') <> (520, 90)
       or not exists (select 1 from platform_actions where kind = 'cauris_cost'
                         and after = '{"feature": "tontines", "cost": 520, "min_days": 90}'::jsonb) then
        raise exception 'FAIL: 085''s setter skipped the journal or lost the wait';
    end if;
    perform set_cauris_cost('tontines', 500);
    perform set_config('request.jwt.claim.sub', '', true);
    -- The doors.
    if has_function_privilege('anon', 'platform_set_cauris_cost(text, int, int)', 'execute')
       or has_function_privilege('anon', 'spend_cauris(uuid, text)', 'execute')
       or has_function_privilege('anon', 'set_cauris_cost(text, int)', 'execute')
       or has_function_privilege('authenticated', 'platform_undo_cauris_cost(jsonb)', 'execute')
       or has_function_privilege('authenticated', 'cauris_cost_label(text)', 'execute')
       or not has_function_privilege('authenticated', 'platform_set_cauris_cost(text, int, int)', 'execute')
       or not has_function_privilege('authenticated', 'spend_cauris(uuid, text)', 'execute')
       or not exists (select 1 from platform_undo_fns where fn = 'platform_undo_cauris_cost') then
        raise exception 'FAIL: a door is open, or one is shut that should not be';
    end if;
    raise notice 'PASS: only Mara, checked, journaled before → after, undone once, a stale undo refused, 085''s setter through the journal; the street shut out';
end $$;

-- Leave the prices and waits as the suite found them, and nothing of its own.
update cauris_costs c set cost = b.cost, min_days = b.min_days
  from b108_costs b where b.feature = c.feature;
delete from platform_actions where kind = 'cauris_cost'
   and actor = '10810810-0000-0000-0000-000000000001';
