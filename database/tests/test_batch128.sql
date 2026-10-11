-- ============================================================
-- test_batch128.sql — Mara Pro sold in the store apps, and an account
-- that can really be deleted (128).
--
-- The claims, for a shop, a farm and an association alike:
--   * store billing: an active store subscription turns Pro on (org_plan,
--     my_orgs, feature_paid), an expired one turns it off, grace and
--     cancelled-but-paid keep it on until their end, a refund (revoked)
--     turns it off at once; a token written for one business is refused
--     for another; idempotent;
--   * only the Worker writes: no table privilege and no function for the
--     app (store_settle, store_org_of, store_due are the service role's);
--     anon calls nothing; another business's admin reads nothing, the
--     business's own employee reads nothing, its admin reads its row;
--     store_verify_begin answers an admin and refuses an employee;
--     my_store_subscription tells an owner their store account already
--     pays for another business;
--   * store_billing_on: off by default, in plan_terms, set by the
--     platform's Réglages only;
--   * P1: a Stripe/Wave Pro business, a dated one, a lapsed one, a free
--     one and a cauris one read the same plan and the same paid tools with
--     128's org_plan / feature_paid as with 085's / 110's.
--   * account deletion — TEST 7 onwards.
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
grant select on orgs, memberships, profiles to authenticated;
\i database/migrations/128_store_billing.sql

\set mara    '''12812812-0000-0000-0000-000000000001'''
\set sowner  '''12812812-0000-0000-0000-000000000002'''
\set fowner  '''12812812-0000-0000-0000-000000000003'''
\set aowner  '''12812812-0000-0000-0000-000000000004'''
\set clerk   '''12812812-0000-0000-0000-000000000005'''
\set stranger '''12812812-0000-0000-0000-000000000006'''
\set shop    '''12800000-0000-0000-0000-000000000001'''
\set farm    '''12800000-0000-0000-0000-000000000002'''
\set assoc   '''12800000-0000-0000-0000-000000000003'''
\set strip   '''12800000-0000-0000-0000-000000000004'''
\set dated   '''12800000-0000-0000-0000-000000000005'''
\set lapsed  '''12800000-0000-0000-0000-000000000006'''
\set free    '''12800000-0000-0000-0000-000000000007'''
\set cauris  '''12800000-0000-0000-0000-000000000008'''

create or replace function pg_temp.as128(p_who uuid)
returns void
language sql
as $$
    select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true),
           set_config('request.jwt.claims',
                      json_build_object('sub', p_who, 'role', 'authenticated')::text, true);
$$;

-- The answer of p_sql as p_who under p_role, or the refusal's message.
create or replace function pg_temp.try128(p_who uuid, p_sql text, p_role text default 'authenticated')
returns text
language plpgsql
as $$
declare v text;
begin
    perform pg_temp.as128(p_who);
    execute format('set local role %I', p_role);
    execute p_sql into v;
    execute 'reset role';
    return coalesce(v, '(null)');
exception when others then
    execute 'reset role';
    return 'ERR: ' || sqlerrm;
end;
$$;

-- The Worker's write, as it calls it.
create or replace function pg_temp.settle128(p_org uuid, p_platform text, p_id text, p_state text,
                                             p_expires timestamptz)
returns jsonb
language sql
as $$
    select store_settle(p_platform, p_org,
                        case when p_platform = 'apple' then 'bf.kaj.app.pro.monthly' else 'mara_pro:monthly' end,
                        p_id, p_state, p_expires, p_state = 'active', 'sandbox',
                        '{"test": true}'::jsonb, null, null);
$$;

insert into auth.users (id, phone, email, email_confirmed_at, raw_user_meta_data) values
    (:mara,     '+22612801001', 'mara128@example.org',     now(), '{"full_name": "Mara 128"}'),
    (:sowner,   '+22612801002', 'boutique128@example.org', now(), '{"full_name": "Patronne 128"}'),
    (:fowner,   '+22612801003', 'ferme128@example.org',    now(), '{"full_name": "Fermier 128"}'),
    (:aowner,   '+22612801004', 'entraide128@example.org', now(), '{"full_name": "Trésorière 128"}'),
    (:clerk,    '+22612801005', 'vendeur128@example.org',  now(), '{"full_name": "Vendeur 128"}'),
    (:stranger, '+22612801006', 'autre128@example.org',    now(), '{"full_name": "Autre Patron 128"}');
update profiles set is_platform_admin = true where id = :mara;
insert into orgs (id, name, slug, profile, default_currency) values
    (:shop,   'Boutique 128', 'boutique-128', 'retail',      'XOF'),
    (:farm,   'Ferme 128',    'ferme-128',    'farm',        'XOF'),
    (:assoc,  'Entraide 128', 'entraide-128', 'association', 'XOF'),
    (:strip,  'Carte 128',    'carte-128',    'retail',      'XOF'),
    (:dated,  'Wave 128',     'wave-128',     'farm',        'XOF'),
    (:lapsed, 'Passé 128',    'passe-128',    'association', 'XOF'),
    (:free,   'Libre 128',    'libre-128',    'retail',      'XOF'),
    (:cauris, 'Cauris 128',   'cauris-128',   'farm',        'XOF');
update orgs set plan = 'pro', plan_note = 'Stripe sub_128' where id = :strip;
update orgs set plan = 'pro', plan_until = current_date + 20 where id = :dated;
update orgs set plan = 'pro', plan_until = current_date - 3 where id = :lapsed;
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :sowner,   'owner',    'org', :shop,  'full'),
    (:farm,  :fowner,   'owner',    'org', :farm,  'full'),
    (:assoc, :aowner,   'owner',    'org', :assoc, 'full'),
    (:shop,  :clerk,    'employee', 'org', :shop,  'full'),
    (:free,  :stranger, 'owner',    'org', :free,  'full');
insert into cauris_unlocks (org_id, feature, until) values (:cauris, 'pro_all', now() + interval '5 days');

\echo ''
\echo '--- TEST 1: a store subscription turns Pro on, an expired one off, grace and cancelled keep it to their end, a refund at once ---'
begin;
do $$
declare
    v_orgs uuid[] := array['12800000-0000-0000-0000-000000000001', '12800000-0000-0000-0000-000000000002',
                           '12800000-0000-0000-0000-000000000003'];
    v_org uuid; v_r jsonb; i int; v_tool text;
begin
    select key into v_tool from feature_catalog where pro_tool is not null order by key limit 1;
    for i in 1 .. 3 loop
        v_org := v_orgs[i];
        if org_plan(v_org) <> 'free' then raise exception 'FAIL: % is not free to start', v_org; end if;
        if feature_paid(v_org, v_tool) then raise exception 'FAIL: % has % paid to start', v_org, v_tool; end if;

        v_r := pg_temp.settle128(v_org, case when i = 2 then 'google' else 'apple' end,
                                 'orig-' || i, 'active', now() + interval '30 days');
        if not (v_r ->> 'ok')::boolean or not (v_r ->> 'pro')::boolean then
            raise exception 'FAIL: active did not turn % Pro: %', v_org, v_r;
        end if;
        if org_plan(v_org) <> 'pro' then raise exception 'FAIL: org_plan of % after active', v_org; end if;
        if not feature_paid(v_org, v_tool) then raise exception 'FAIL: % not paid after active', v_tool; end if;
        if not exists (select 1 from notifications where org_id = v_org and kind = 'pro_active') then
            raise exception 'FAIL: the admins of % were not told', v_org;
        end if;

        -- The same answer again: one row, nothing new.
        perform pg_temp.settle128(v_org, case when i = 2 then 'google' else 'apple' end,
                                  'orig-' || i, 'active', now() + interval '30 days');
        if (select count(*) from store_subscriptions where org_id = v_org) <> 1 then
            raise exception 'FAIL: settling twice made two rows';
        end if;

        perform pg_temp.settle128(v_org, case when i = 2 then 'google' else 'apple' end,
                                  'orig-' || i, 'grace', now() + interval '6 days');
        if org_plan(v_org) <> 'pro' then raise exception 'FAIL: grace turned % off', v_org; end if;

        perform pg_temp.settle128(v_org, case when i = 2 then 'google' else 'apple' end,
                                  'orig-' || i, 'cancelled', now() + interval '3 days');
        if org_plan(v_org) <> 'pro' then raise exception 'FAIL: cancelled-but-paid turned % off', v_org; end if;

        perform pg_temp.settle128(v_org, case when i = 2 then 'google' else 'apple' end,
                                  'orig-' || i, 'grace', now() - interval '1 minute');
        if org_plan(v_org) <> 'free' then raise exception 'FAIL: grace past its end kept % on', v_org; end if;

        perform pg_temp.settle128(v_org, case when i = 2 then 'google' else 'apple' end,
                                  'orig-' || i, 'active', now() + interval '30 days');
        perform pg_temp.settle128(v_org, case when i = 2 then 'google' else 'apple' end,
                                  'orig-' || i, 'expired', now() - interval '1 day');
        if org_plan(v_org) <> 'free' or feature_paid(v_org, v_tool) then
            raise exception 'FAIL: expired kept % on', v_org;
        end if;

        perform pg_temp.settle128(v_org, case when i = 2 then 'google' else 'apple' end,
                                  'orig-' || i, 'active', now() + interval '30 days');
        perform pg_temp.settle128(v_org, case when i = 2 then 'google' else 'apple' end,
                                  'orig-' || i, 'revoked', now() + interval '30 days');
        if org_plan(v_org) <> 'free' then raise exception 'FAIL: a refund kept % on', v_org; end if;

        for v_r in select to_jsonb(s) from unnest(array['on_hold', 'paused', 'pending']) s loop
            perform pg_temp.settle128(v_org, case when i = 2 then 'google' else 'apple' end,
                                      'orig-' || i, v_r #>> '{}', now() + interval '30 days');
            if org_plan(v_org) <> 'free' then raise exception 'FAIL: % gave Pro', v_r; end if;
        end loop;

        -- Back on, and seen in my_orgs by the owner.
        perform pg_temp.settle128(v_org, case when i = 2 then 'google' else 'apple' end,
                                  'orig-' || i, 'active', now() + interval '30 days');
        -- No orgs.plan written: Stripe's column is Stripe's.
        if (select plan from orgs where id = v_org) <> 'free' then
            raise exception 'FAIL: the store wrote orgs.plan';
        end if;
    end loop;
end $$;
select pg_temp.as128(:sowner);
set local role authenticated;
do $$ begin
    if (select plan from my_orgs() where org_id = '12800000-0000-0000-0000-000000000001') <> 'pro' then
        raise exception 'FAIL: my_orgs does not say Pro';
    end if;
end $$;
reset role;
-- A token is the business it was bought for.
do $$
declare v_r jsonb;
begin
    v_r := pg_temp.settle128('12800000-0000-0000-0000-000000000002', 'apple', 'orig-1', 'active', now() + interval '30 days');
    if (v_r ->> 'ok')::boolean or v_r ->> 'reason' <> 'another business' then
        raise exception 'FAIL: a token replayed for another business went through: %', v_r;
    end if;
    if (select org_id from store_subscriptions where original_id = 'orig-1')
       <> '12800000-0000-0000-0000-000000000001' then
        raise exception 'FAIL: the replay moved the row';
    end if;
    -- The same id on the other store is another purchase.
    v_r := pg_temp.settle128('12800000-0000-0000-0000-000000000002', 'google', 'orig-1', 'active', now() + interval '30 days');
    if not (v_r ->> 'ok')::boolean then raise exception 'FAIL: google orig-1 refused'; end if;
    -- Google's upgrade: the new token names the old one, which is over.
    perform store_settle('google', '12800000-0000-0000-0000-000000000002', 'mara_pro:yearly', 'orig-2b',
                         'active', now() + interval '365 days', true, 'production', null, null, 'orig-2');
    if (select state from store_subscriptions where platform = 'google' and original_id = 'orig-2') <> 'expired' then
        raise exception 'FAIL: the replaced token still runs';
    end if;
    -- Unknown business, unknown store, no id: refused, nothing written.
    if (store_settle('apple', gen_random_uuid(), 'p', 'x', 'active', now(), true, 'production') ->> 'ok')::boolean
       or (store_settle('steam', '12800000-0000-0000-0000-000000000001', 'p', 'x', 'active', now(), true, 'production') ->> 'ok')::boolean
       or (store_settle('apple', '12800000-0000-0000-0000-000000000001', 'p', '', 'active', now(), true, 'production') ->> 'ok')::boolean then
        raise exception 'FAIL: a bad settle went through';
    end if;
    raise notice 'PASS: shop (App Store), farm (Google Play), association (App Store) — active on, grace and cancelled on to their end, past grace off, expired off, refund off at once, on hold / paused / pending off; idempotent; my_orgs says Pro; orgs.plan untouched; a token replayed for another business refused; an upgrade ends the old token; bad settles refused';
end $$;
commit;

\echo ''
\echo '--- TEST 2: only the Worker writes; anon calls nothing ---'
do $$
declare v text; f text;
begin
    foreach f in array array[
        'store_settle(text, uuid, text, text, text, timestamptz, boolean, text, jsonb, uuid, text)',
        'store_org_of(text, text)', 'store_due()', 'store_pro_active(uuid)', 'store_billing_on()'] loop
        if has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: authenticated may run %', f;
        end if;
        if has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: anon may run %', f;
        end if;
    end loop;
    foreach f in array array['store_verify_begin(uuid)', 'my_store_subscription(uuid)', 'plan_terms()'] loop
        if has_function_privilege('anon', f, 'execute') then raise exception 'FAIL: anon may run %', f; end if;
        if not has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: the app may not run %', f;
        end if;
    end loop;
    foreach f in array array['insert', 'update', 'delete', 'truncate'] loop
        if has_table_privilege('authenticated', 'store_subscriptions', f) then
            raise exception 'FAIL: authenticated may % store_subscriptions', f;
        end if;
        if has_table_privilege('anon', 'store_subscriptions', f) then
            raise exception 'FAIL: anon may % store_subscriptions', f;
        end if;
    end loop;
    if has_table_privilege('anon', 'store_subscriptions', 'select') then
        raise exception 'FAIL: anon may read store_subscriptions';
    end if;
    -- Tried, as the owner of the shop.
    v := pg_temp.try128('12812812-0000-0000-0000-000000000002',
        $q$select store_settle('apple', '12800000-0000-0000-0000-000000000001', 'bf.kaj.app.pro.yearly', 'forged', 'active', now() + interval '1 year', true, 'production')::text$q$);
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: the owner settled: %', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000002',
        $q$insert into store_subscriptions (org_id, platform, product_id, original_id, state, expires_at) values ('12800000-0000-0000-0000-000000000001', 'apple', 'p', 'forged2', 'active', now() + interval '1 year') returning id::text$q$);
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: the owner inserted: %', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000002',
        $q$update store_subscriptions set expires_at = now() + interval '10 years' returning id::text$q$);
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: the owner updated: %', v; end if;
    v := pg_temp.try128(null, $q$select store_verify_begin('12800000-0000-0000-0000-000000000001')::text$q$, 'anon');
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: anon ran store_verify_begin: %', v; end if;
    v := pg_temp.try128(null, $q$select count(*)::text from store_subscriptions$q$, 'anon');
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: anon read: %', v; end if;
    raise notice 'PASS: store_settle / store_org_of / store_due / store_pro_active / store_billing_on are nobody''s in the app; no insert, update or delete for the app or anon; the owner''s forged settle, insert and update are refused; anon runs no store door and reads nothing';
end $$;

\echo ''
\echo '--- TEST 3: who reads, who may ask for a verification ---'
do $$
declare v text;
begin
    -- Its own admins read the row; its employee and another business's owner nothing.
    v := pg_temp.try128('12812812-0000-0000-0000-000000000002',
        $q$select count(*)::text from store_subscriptions where org_id = '12800000-0000-0000-0000-000000000001'$q$);
    if v <> '1' then raise exception 'FAIL: the shop''s owner reads % rows', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000005',
        $q$select count(*)::text from store_subscriptions$q$);
    if v <> '0' then raise exception 'FAIL: the shop''s employee reads % rows', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000006',
        $q$select count(*)::text from store_subscriptions$q$);
    if v <> '0' then raise exception 'FAIL: another business''s owner reads % rows', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000003',
        $q$select count(*)::text from store_subscriptions where org_id <> '12800000-0000-0000-0000-000000000002'$q$);
    if v <> '0' then raise exception 'FAIL: the farmer reads another business''s rows: %', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000006',
        $q$select coalesce(my_store_subscription('12800000-0000-0000-0000-000000000001')::text, '(nothing)')$q$);
    if v <> '(nothing)' then raise exception 'FAIL: another owner read my_store_subscription: %', v; end if;
    -- The doors: an admin yes, an employee or a stranger no, an archived business no.
    v := pg_temp.try128('12812812-0000-0000-0000-000000000004',
        $q$select store_verify_begin('12800000-0000-0000-0000-000000000003') ->> 'user_id'$q$);
    if v <> '12812812-0000-0000-0000-000000000004' then raise exception 'FAIL: the association''s owner: %', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000005',
        $q$select store_verify_begin('12800000-0000-0000-0000-000000000001')::text$q$);
    if v not like 'ERR: Seul un administrateur%' then raise exception 'FAIL: the employee began: %', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000006',
        $q$select store_verify_begin('12800000-0000-0000-0000-000000000002')::text$q$);
    if v not like 'ERR: Seul un administrateur%' then raise exception 'FAIL: a stranger began: %', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000001',
        $q$select (store_verify_begin('12800000-0000-0000-0000-000000000002') ->> 'store_billing_on')$q$);
    if v <> 'false' then raise exception 'FAIL: the platform: %', v; end if;
    raise notice 'PASS: a shop''s, a farm''s, an association''s admins read their own store row; the employee and another business''s owner read none; store_verify_begin answers the owner and the platform, refuses the employee and a stranger';
end $$;

\echo ''
\echo '--- TEST 4: « your store account already pays for … » ---'
begin;
do $$
declare v text;
begin
    update store_subscriptions set bought_by = '12812812-0000-0000-0000-000000000002'
     where org_id = '12800000-0000-0000-0000-000000000001';
    -- The shop's owner also owns the farm.
    insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
        ('12800000-0000-0000-0000-000000000002', '12812812-0000-0000-0000-000000000002', 'admin', 'org',
         '12800000-0000-0000-0000-000000000002', 'full');
    v := pg_temp.try128('12812812-0000-0000-0000-000000000002',
        $q$select my_store_subscription('12800000-0000-0000-0000-000000000002') -> 'elsewhere' ->> 'name'$q$);
    if v <> 'Boutique 128' then raise exception 'FAIL: elsewhere = %', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000002',
        $q$select my_store_subscription('12800000-0000-0000-0000-000000000001') -> 'this' ->> 'state'$q$);
    if v <> 'active' then raise exception 'FAIL: this = %', v; end if;
    raise notice 'PASS: my_store_subscription says the owner''s store purchase pays for « Boutique 128 », and the shop''s own state';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: store_billing_on — off, in plan_terms, the platform''s switch ---'
do $$
declare v text;
begin
    if (plan_terms() ->> 'store_billing_on')::boolean is distinct from false then
        raise exception 'FAIL: store_billing_on is not off by default';
    end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000002',
        $q$select platform_set_setting('store_billing_on', 'true'::jsonb)::text$q$);
    if v not like 'ERR:%' then raise exception 'FAIL: an owner switched it: %', v; end if;
end $$;
begin;
select pg_temp.as128(:mara);
set local role authenticated;
select platform_set_setting('store_billing_on', 'true'::jsonb) is not null as switched;
do $$ begin
    if (plan_terms() ->> 'store_billing_on')::boolean is distinct from true then
        raise exception 'FAIL: the platform''s switch did not reach plan_terms';
    end if;
    begin
        perform platform_set_setting('store_billing_on', '1'::jsonb);
        raise exception 'FAIL: a number went into a switch';
    exception when others then
        if sqlerrm like 'FAIL%' then raise; end if;
    end;
    raise notice 'PASS: store_billing_on off by default, in plan_terms; the platform turns it on (oui/non only), an owner cannot';
end $$;
reset role;
rollback;

\echo ''
\echo '--- TEST 6: P1 — Stripe, Wave, lapsed, free and cauris businesses read as before ---'
begin;
create temp table b128_with on commit drop as
select o.id, org_plan(o.id) as plan,
       (select array_agg(c.key order by c.key) from feature_catalog c where feature_paid(o.id, c.key)) as paid,
       plan_terms() - 'store_billing_on' as terms
  from orgs o
 where o.id in ('12800000-0000-0000-0000-000000000004', '12800000-0000-0000-0000-000000000005',
                '12800000-0000-0000-0000-000000000006', '12800000-0000-0000-0000-000000000007',
                '12800000-0000-0000-0000-000000000008');
-- 085's org_plan and 110's feature_paid, as they were.
create or replace function org_plan(p_org_id uuid)
returns text language sql stable security definer set search_path = public as $$
    select case
        when o.plan = 'pro'
         and (o.plan_until is null
              or o.plan_until >= (now() at time zone 'Africa/Ouagadougou')::date)
        then 'pro'
        when exists (select 1 from cauris_unlocks u
                      where u.org_id = o.id and u.feature = 'pro_all' and u.until > now())
        then 'pro'
        else 'free'
    end
    from orgs o where o.id = p_org_id
    union all select 'free' where not exists (select 1 from orgs where id = p_org_id)
    limit 1;
$$;
create or replace function feature_paid(p_org uuid, p_key text)
returns boolean language sql stable security definer set search_path = public as $$
    select coalesce((
        select c.pro_tool is not null
           and (exists (select 1 from orgs o
                         where o.id = p_org and o.plan = 'pro'
                           and (o.plan_until is null
                                or o.plan_until >= (now() at time zone 'Africa/Ouagadougou')::date))
                or exists (select 1 from cauris_unlocks u
                            where u.org_id = p_org
                              and u.feature in (c.pro_tool, 'pro_all')
                              and u.until > now()
                              and u.gifted_by is null))
          from feature_catalog c where c.key = p_key), false)
        or (p_key = 'spots' and exists (
                select 1 from promotions pm
                 where pm.org_id = p_org
                   and (pm.status = 'paid_claimed'
                        or (pm.status = 'approved' and pm.ends_at > now()))));
$$;
do $$
declare r record; v_old text; v_paid text[]; n int := 0;
begin
    for r in select * from b128_with loop
        v_old := org_plan(r.id);
        select array_agg(c.key order by c.key) into v_paid from feature_catalog c where feature_paid(r.id, c.key);
        if v_old is distinct from r.plan or v_paid is distinct from r.paid then
            raise exception 'FAIL: P1 — % reads % / % with 128, % / % before', r.id, r.plan, r.paid, v_old, v_paid;
        end if;
        n := n + 1;
    end loop;
    if (select plan from b128_with where id = '12800000-0000-0000-0000-000000000004') <> 'pro'
       or (select plan from b128_with where id = '12800000-0000-0000-0000-000000000005') <> 'pro'
       or (select plan from b128_with where id = '12800000-0000-0000-0000-000000000006') <> 'free'
       or (select plan from b128_with where id = '12800000-0000-0000-0000-000000000007') <> 'free' then
        raise exception 'FAIL: the fixtures are not what they say';
    end if;
    if (select count(distinct terms) from b128_with) <> 1 then raise exception 'FAIL: terms vary'; end if;
    raise notice 'PASS: P1 — % businesses (Stripe Pro, dated Wave Pro, lapsed, free, cauris) read the same plan and the same paid tools with 128 as with 085/110; plan_terms is 121''s plus store_billing_on', n;
end $$;
rollback;


-- ============================================================
-- Account deletion (128 B)
-- ============================================================
\set downer  '''12812812-0000-0000-0000-000000000011'''
\set coowner '''12812812-0000-0000-0000-000000000012'''
\set member  '''12812812-0000-0000-0000-000000000013'''
\set yowner  '''12812812-0000-0000-0000-000000000014'''
\set buyer   '''12812812-0000-0000-0000-000000000015'''
\set courier '''12812812-0000-0000-0000-000000000016'''
\set carrier '''12812812-0000-0000-0000-000000000017'''
\set dshop   '''12800000-0000-0000-0000-000000000011'''
\set dfarm   '''12800000-0000-0000-0000-000000000012'''
\set dassoc  '''12800000-0000-0000-0000-000000000013'''
\set shared  '''12800000-0000-0000-0000-000000000014'''
\set yfarm   '''12800000-0000-0000-0000-000000000015'''

insert into auth.users (id, phone, email, email_confirmed_at, raw_user_meta_data) values
    (:downer,  '+22612801011', 'patron-fin@example.org',   now(), '{"full_name": "Patron Fin"}'),
    (:coowner, '+22612801012', 'associe-fin@example.org',  now(), '{"full_name": "Associé Fin"}'),
    (:member,  '+22612801013', 'vendeuse-fin@example.org', now(), '{"full_name": "Vendeuse Fin"}'),
    (:yowner,  '+22612801014', 'fermier-y@example.org',    now(), '{"full_name": "Fermier Y"}'),
    (:buyer,   '+22612801015', 'cliente-fin@example.org',  now(), '{"full_name": "Cliente Fin"}'),
    (:courier, '+22612801016', 'livreur-fin@example.org',  now(), '{"full_name": "Livreur Fin"}'),
    (:carrier, '+22612801017', 'en-route@example.org',     now(), '{"full_name": "Livreur En Route"}');
update profiles set date_of_birth = '1990-05-01' where id = :downer;
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, setup_done_at) values
    (:dshop,  'Boutique Fin', 'boutique-fin', 'retail',      'XOF', true, now()),
    (:dfarm,  'Ferme Fin',    'ferme-fin',    'farm',        'XOF', true, now()),
    (:dassoc, 'Entraide Fin', 'entraide-fin', 'association', 'XOF', true, now()),
    (:shared, 'À Deux',       'a-deux',       'retail',      'XOF', true, now()),
    (:yfarm,  'Ferme Y',      'ferme-y',      'farm',        'XOF', true, now());
update orgs set plan = 'pro' where id in (:dshop, :dfarm, :dassoc, :shared, :yfarm);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:dshop,  :downer,  'owner',    'org', :dshop,  'full'),
    (:dfarm,  :downer,  'owner',    'org', :dfarm,  'full'),
    (:dassoc, :downer,  'owner',    'org', :dassoc, 'full'),
    (:shared, :downer,  'owner',    'org', :shared, 'full'),
    (:shared, :coowner, 'owner',    'org', :shared, 'full'),
    (:dshop,  :member,  'employee', 'org', :dshop,  'full'),
    (:yfarm,  :yowner,  'owner',    'org', :yfarm,  'full'),
    (:yfarm,  :member,  'employee', 'org', :yfarm,  'full');
select seed_retail_accounts(:dshop);
select seed_farm_accounts(:dfarm);
select seed_church_accounts(:dassoc);
select seed_retail_accounts(:shared);
select seed_farm_accounts(:yfarm);
insert into couriers (user_id, phone, status) values
    (:courier, '+22612801016', 'approved'),
    (:carrier, '+22612801017', 'approved');
insert into orders (id, org_id, customer_id, customer_name, phone, status, fulfilment, address, total, currency) values
    ('128aaaaa-0000-0000-0000-000000000001', :dshop, :buyer, 'Cliente Fin', '+22612801015', 'pending', 'pickup', null, 2500, 'XOF'),
    ('128aaaaa-0000-0000-0000-000000000002', :yfarm, :buyer, 'Cliente Fin', '+22612801015', 'pending', 'delivery', 'Pissy', 3000, 'XOF'),
    ('128aaaaa-0000-0000-0000-000000000003', :yfarm, :yowner, 'Fermier Y', null, 'pending', 'delivery', 'Gounghin', 1000, 'XOF');
-- One carried and delivered by the courier, one on the road with the other.
update orders set status = 'accepted' where id in ('128aaaaa-0000-0000-0000-000000000002', '128aaaaa-0000-0000-0000-000000000003');
update orders set status = 'ready' where id in ('128aaaaa-0000-0000-0000-000000000002', '128aaaaa-0000-0000-0000-000000000003');
update orders set courier_id = :courier, status = 'in_transit' where id = '128aaaaa-0000-0000-0000-000000000002';
update orders set status = 'delivered' where id = '128aaaaa-0000-0000-0000-000000000002';
update orders set courier_id = :carrier, status = 'in_transit' where id = '128aaaaa-0000-0000-0000-000000000003';

-- Each of the owner's businesses with real books: the shop's sale, its
-- reversal, its invoice and a photo; the farm's market day, a receipt, a
-- credit sale and its payment; the association's contribution and
-- expense — and the member's sale in the shop and entry at Ferme Y.
do $$
declare
    v_shop  uuid := '12800000-0000-0000-0000-000000000011';
    v_farm  uuid := '12800000-0000-0000-0000-000000000012';
    v_assoc uuid := '12800000-0000-0000-0000-000000000013';
    v_owner uuid := '12812812-0000-0000-0000-000000000011';
    v_p uuid; v_e uuid; v_debt uuid;
begin
    perform pg_temp.as128(v_owner);
    execute 'set local role authenticated';
    v_p := ensure_product(v_shop, 'Savon Fin', 500, 300);
    perform record_document(v_shop, 'org/12800000-0000-0000-0000-000000000011/fin/savon.jpg', 'product_photo',
                            null, 'image/jpeg', 100, null, null, null, null, v_p);
    v_e := record_entry(v_shop, 4000, 'out', 'Loyer Fin');
    perform reverse_entry(v_e, v_owner, 'erreur');
    perform create_invoice(v_shop, 'Client Fin', '[{"description": "Savon", "quantity": 2, "unit_price": 500}]'::jsonb);
    execute 'reset role';
    update products set quantity = 30 where id = v_p;
    perform pg_temp.as128(v_owner);
    execute 'set local role authenticated';
    perform record_sale(v_shop, jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 2)));
    v_e := record_entry(v_farm, 6000, 'in', 'Marché Fin');
    perform record_document(v_farm, 'org/12800000-0000-0000-0000-000000000012/fin/recu.jpg', 'receipt',
                            null, 'image/jpeg', 100, null, null, null, v_e);
    perform record_credit_sale(v_farm, 'Voisin Fin', 2500, 'Œufs à crédit');
    select id into v_debt from debts where org_id = v_farm limit 1;
    perform record_debt_payment(v_debt, 1000);
    perform record_contribution(v_assoc, 5000, 'offering', v_owner);
    perform record_expense(v_assoc, 1200, '5000', v_owner);
    execute 'reset role';
    perform pg_temp.as128('12812812-0000-0000-0000-000000000013');
    execute 'set local role authenticated';
    perform record_sale(v_shop, jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 1)));
    perform record_entry('12800000-0000-0000-0000-000000000015', 900, 'in', 'Vente du jour Y');
    execute 'reset role';
    perform pg_temp.as128(null);
end $$;
-- What the owner pays outside: Google Play for the shop, Stripe for the
-- farm, the App Store for the association.
select store_settle('google', :dshop, 'mara_pro:monthly', 'fin-google-token', 'active',
                    now() + interval '20 days', true, 'production');
select store_settle('apple', :dassoc, 'bf.kaj.app.pro.yearly', 'fin-apple-1', 'active',
                    now() + interval '200 days', true, 'production');
insert into stripe_subscriptions (org_id, customer_id, subscription_id, status, period, current_period_end)
values (:dfarm, 'cus_fin', 'sub_fin', 'active', 'month', now() + interval '10 days');

\echo ''
\echo '--- TEST 7: the confirmation says what disappears ---'
do $$
declare v jsonb; v_text text;
begin
    v := delete_my_account_plan('12812812-0000-0000-0000-000000000011');
    if v ->> 'blocked' is not null then raise exception 'FAIL: the owner is blocked: %', v ->> 'blocked'; end if;
    if (select jsonb_agg(b ->> 'name') from jsonb_array_elements(v -> 'businesses') b)
       <> '["Boutique Fin", "Entraide Fin", "Ferme Fin"]'::jsonb then
        raise exception 'FAIL: the businesses: %', v -> 'businesses';
    end if;
    if (select (b ->> 'members')::int from jsonb_array_elements(v -> 'businesses') b where b ->> 'name' = 'Boutique Fin') <> 1
       or (select (b ->> 'orders')::int from jsonb_array_elements(v -> 'businesses') b where b ->> 'name' = 'Boutique Fin') <> 1
       or (select (b ->> 'stripe')::boolean from jsonb_array_elements(v -> 'businesses') b where b ->> 'name' = 'Ferme Fin') is not true
       or (select b -> 'store' -> 0 ->> 'platform' from jsonb_array_elements(v -> 'businesses') b where b ->> 'name' = 'Entraide Fin') <> 'apple'
       or (v ->> 'apple_store')::int <> 1 then
        raise exception 'FAIL: the detail: %', v;
    end if;
    if v -> 'leaves' <> '[{"id": "12800000-0000-0000-0000-000000000014", "name": "À Deux"}]'::jsonb then
        raise exception 'FAIL: the co-owned business: %', v -> 'leaves';
    end if;
    -- The app's door, as the owner; nobody else's plan.
    v_text := pg_temp.try128('12812812-0000-0000-0000-000000000011',
        $q$select jsonb_array_length(delete_my_account_preview() -> 'businesses')::text$q$);
    if v_text <> '3' then raise exception 'FAIL: the preview: %', v_text; end if;
    v_text := pg_temp.try128('12812812-0000-0000-0000-000000000013',
        $q$select delete_my_account_preview()::text$q$);
    if v_text not like '%"businesses": []%' or v_text not like '%Boutique Fin%' then
        raise exception 'FAIL: the member''s preview: %', v_text;
    end if;
    raise notice 'PASS: the owner''s confirmation lists Boutique Fin (1 member, 1 open order, Google Play), Entraide Fin (App Store: 1 to cancel by hand), Ferme Fin (Stripe); « À Deux », co-owned, is only left; the member''s lists none to delete';
end $$;

\echo ''
\echo '--- TEST 8: what refuses a deletion ---'
do $$
declare v text;
begin
    v := pg_temp.try128('12812812-0000-0000-0000-000000000011', $q$select delete_my_account()::text$q$);
    if v not like 'ERR: Mettez Mara à jour%' then raise exception 'FAIL: an old app''s call: %', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000011',
        $q$select delete_my_account(array['12800000-0000-0000-0000-000000000011', '12800000-0000-0000-0000-000000000012']::uuid[])::text$q$);
    if v not like 'ERR: La liste de vos activités a changé%' then raise exception 'FAIL: a list short of one: %', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000011',
        $q$select delete_my_account(array['12800000-0000-0000-0000-000000000011', '12800000-0000-0000-0000-000000000012', '12800000-0000-0000-0000-000000000013', '12800000-0000-0000-0000-000000000014']::uuid[])::text$q$);
    if v not like 'ERR: La liste de vos activités a changé%' then raise exception 'FAIL: a list with the co-owned one: %', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000015', $q$select delete_my_account()::text$q$);
    if v not like 'ERR: Une commande est en cours%' then raise exception 'FAIL: the buyer with an open order: %', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000017', $q$select delete_my_account()::text$q$);
    if v not like 'ERR: Une livraison est en cours%' then raise exception 'FAIL: the courier on the road: %', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000001', $q$select delete_my_account()::text$q$);
    if v not like 'ERR: Un compte de la plateforme%' then raise exception 'FAIL: the platform: %', v; end if;
    v := pg_temp.try128(null, $q$select delete_my_account()::text$q$);
    if v not like 'ERR: Connectez-vous%' then raise exception 'FAIL: nobody: %', v; end if;
    -- An order paid online and not yet handed over, or on the road: the
    -- owner finishes or refunds it first.
    update orders set payment_method = 'wave', paid_at = now()
     where id = '128aaaaa-0000-0000-0000-000000000001';
    v := pg_temp.try128('12812812-0000-0000-0000-000000000011',
        $q$select delete_my_account(array['12800000-0000-0000-0000-000000000011', '12800000-0000-0000-0000-000000000012', '12800000-0000-0000-0000-000000000013']::uuid[])::text$q$);
    update orders set payment_method = 'cash', paid_at = null
     where id = '128aaaaa-0000-0000-0000-000000000001';
    if v not like 'ERR: Une commande de « Boutique Fin » est en route ou déjà payée en ligne%' then
        raise exception 'FAIL: a paid order: %', v;
    end if;
    if not exists (select 1 from orgs where id = '12800000-0000-0000-0000-000000000011') then
        raise exception 'FAIL: a refusal deleted something';
    end if;
    raise notice 'PASS: refused — an old app''s call for an owner, a list that is not the one shown (short, or with the co-owned business), the buyer''s open order, a delivery on the road, a business''s order paid online, the platform, nobody; nothing deleted';
end $$;

\echo ''
\echo '--- TEST 9: an owner deleted — the shop, the farm and the association gone, the members shoppers ---'
begin;
do $$
declare v text; r jsonb; n int;
begin
    v := pg_temp.try128('12812812-0000-0000-0000-000000000011',
        $q$select delete_my_account(array['12800000-0000-0000-0000-000000000013', '12800000-0000-0000-0000-000000000011', '12800000-0000-0000-0000-000000000012', '12800000-0000-0000-0000-000000000011']::uuid[])::text$q$);
    if v like 'ERR:%' then raise exception 'FAIL: the owner''s deletion: %', v; end if;
    r := v::jsonb;
    if r ->> 'user_id' <> '12812812-0000-0000-0000-000000000011' or r ->> 'mode' <> 'hard'
       or r -> 'businesses' <> '["Boutique Fin", "Entraide Fin", "Ferme Fin"]'::jsonb
       or r -> 'google' -> 0 ->> 'token' <> 'fin-google-token'
       or r -> 'stripe' <> '["sub_fin"]'::jsonb
       or (r ->> 'apple_store')::int <> 1 then
        raise exception 'FAIL: the answer: %', r;
    end if;
    -- The three businesses are gone, books and all, each with a tombstone.
    if exists (select 1 from orgs where id in ('12800000-0000-0000-0000-000000000011', '12800000-0000-0000-0000-000000000012', '12800000-0000-0000-0000-000000000013'))
       or exists (select 1 from journal_entries where org_id in ('12800000-0000-0000-0000-000000000011', '12800000-0000-0000-0000-000000000012', '12800000-0000-0000-0000-000000000013'))
       or exists (select 1 from store_subscriptions where original_id in ('fin-google-token', 'fin-apple-1'))
       or exists (select 1 from stripe_subscriptions where subscription_id = 'sub_fin') then
        raise exception 'FAIL: a business, its books or its subscription survived';
    end if;
    select count(*) into n from deleted_orgs
     where id in ('12800000-0000-0000-0000-000000000011', '12800000-0000-0000-0000-000000000012', '12800000-0000-0000-0000-000000000013')
       and deleted_label = 'Compte du propriétaire supprimé' and entry_count > 0;
    if n <> 3 then raise exception 'FAIL: % tombstones', n; end if;
    -- Off the street: nothing of them is read by the public.
    if exists (select 1 from orgs where slug in ('boutique-fin', 'ferme-fin', 'entraide-fin')) then
        raise exception 'FAIL: a vitrine is still in the street';
    end if;
    -- The member is a shopper of the shop no more, still of Ferme Y; told.
    if exists (select 1 from memberships where user_id = '12812812-0000-0000-0000-000000000013' and org_id = '12800000-0000-0000-0000-000000000011')
       or not exists (select 1 from memberships where user_id = '12812812-0000-0000-0000-000000000013' and org_id = '12800000-0000-0000-0000-000000000015')
       or not exists (select 1 from notifications where recipient_id = '12812812-0000-0000-0000-000000000013'
                        and kind = 'org_closed' and org_id is null and params ->> 'shop' = 'Boutique Fin') then
        raise exception 'FAIL: the member';
    end if;
    -- The buyer's open order is cancelled, and the notice outlives the shop.
    if not exists (select 1 from notifications where recipient_id = '12812812-0000-0000-0000-000000000015'
                     and kind = 'order_cancelled' and org_id is null and params ->> 'shop' = 'Boutique Fin'
                     and message like '%l''activité a fermé sur Mara%') then
        raise exception 'FAIL: the buyer was not told';
    end if;
    if exists (select 1 from orders where id = '128aaaaa-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the order survived its shop';
    end if;
    -- The co-owned business stays with its other owner.
    if not exists (select 1 from memberships where org_id = '12800000-0000-0000-0000-000000000014' and user_id = '12812812-0000-0000-0000-000000000012' and role = 'owner')
       or exists (select 1 from memberships where org_id = '12800000-0000-0000-0000-000000000014' and user_id = '12812812-0000-0000-0000-000000000011') then
        raise exception 'FAIL: « À Deux »';
    end if;
    -- The person: nothing personal left, and GoTrue's delete goes through.
    if exists (select 1 from profiles where id = '12812812-0000-0000-0000-000000000011'
                 and (full_name <> 'Compte supprimé' or phone is not null or date_of_birth is not null)) then
        raise exception 'FAIL: the profile still says who';
    end if;
    delete from auth.users where id = '12812812-0000-0000-0000-000000000011';
    if exists (select 1 from profiles where id = '12812812-0000-0000-0000-000000000011') then
        raise exception 'FAIL: the profile survived the auth user';
    end if;
    -- Other businesses' books untouched.
    if (select count(*) from journal_entries where org_id = '12800000-0000-0000-0000-000000000015') < 1 then
        raise exception 'FAIL: Ferme Y lost its books';
    end if;
    raise notice 'PASS: the owner of a shop, a farm and an association — all three archived and purged (books, photos, invoices, debts, the subscription rows; three tombstones), off the street; the employee is the shop''s no more (told, still at Ferme Y); the buyer''s order cancelled and told; « À Deux » kept by its other owner; Google token and Stripe subscription handed to the Worker, one App Store subscription to cancel by hand; profile emptied; the auth user deleted outright (hard)';
end $$;
rollback;

\echo ''
\echo '--- TEST 10: a member, a shopper and a courier ---'
begin;
do $$
declare v text; r jsonb; v_entries int;
begin
    select count(*) into v_entries from journal_entries where org_id = '12800000-0000-0000-0000-000000000015';
    -- The member's name is on Ferme Y's books (a NOT NULL « written by »):
    -- the account is kept as an empty shell (soft).
    v := pg_temp.try128('12812812-0000-0000-0000-000000000013', $q$select delete_my_account()::text$q$);
    if v like 'ERR:%' then raise exception 'FAIL: the member''s deletion: %', v; end if;
    r := v::jsonb;
    if r ->> 'mode' <> 'soft' or jsonb_array_length(r -> 'businesses') <> 0 then
        raise exception 'FAIL: the member''s answer: %', r;
    end if;
    if exists (select 1 from memberships where user_id = '12812812-0000-0000-0000-000000000013')
       or exists (select 1 from notifications where recipient_id = '12812812-0000-0000-0000-000000000013')
       or exists (select 1 from sales where recorded_by = '12812812-0000-0000-0000-000000000013')
       or exists (select 1 from profiles where id = '12812812-0000-0000-0000-000000000013'
                    and (full_name <> 'Compte supprimé' or phone is not null)) then
        raise exception 'FAIL: the member left something personal';
    end if;
    if (select count(*) from journal_entries where org_id = '12800000-0000-0000-0000-000000000015') <> v_entries
       or (select count(*) from sales where org_id = '12800000-0000-0000-0000-000000000011') < 2 then
        raise exception 'FAIL: a business lost its books to a member''s deletion';
    end if;
    begin
        delete from auth.users where id = '12812812-0000-0000-0000-000000000013';
        raise exception 'FAIL: a hard delete went through for a shell';
    exception when foreign_key_violation then null;
    end;

    -- The buyer, once Ferme Y's order is delivered: hard.
    v := pg_temp.try128('12812812-0000-0000-0000-000000000015', $q$select delete_my_account()::text$q$);
    if v not like 'ERR: Une commande est en cours%' then raise exception 'FAIL: the buyer: %', v; end if;
    delete from orders where id = '128aaaaa-0000-0000-0000-000000000001';
    v := pg_temp.try128('12812812-0000-0000-0000-000000000015', $q$select delete_my_account()::text$q$);
    if v like 'ERR:%' or (v::jsonb) ->> 'mode' <> 'hard' then raise exception 'FAIL: the buyer: %', v; end if;
    if (select customer_name from orders where id = '128aaaaa-0000-0000-0000-000000000002') <> 'Client supprimé'
       or (select phone from orders where id = '128aaaaa-0000-0000-0000-000000000002') is not null
       or (select customer_id from orders where id = '128aaaaa-0000-0000-0000-000000000002') is not null then
        raise exception 'FAIL: the buyer''s past order still says who';
    end if;
    delete from auth.users where id = '12812812-0000-0000-0000-000000000015';

    -- The courier with a delivery done: hard, the delivery kept unnamed.
    v := pg_temp.try128('12812812-0000-0000-0000-000000000016', $q$select delete_my_account()::text$q$);
    if v like 'ERR:%' or (v::jsonb) ->> 'mode' <> 'hard' then raise exception 'FAIL: the courier: %', v; end if;
    if exists (select 1 from couriers where user_id = '12812812-0000-0000-0000-000000000016')
       or (select courier_id from orders where id = '128aaaaa-0000-0000-0000-000000000002') is not null
       or (select status from orders where id = '128aaaaa-0000-0000-0000-000000000002') <> 'delivered' then
        raise exception 'FAIL: the courier';
    end if;
    delete from auth.users where id = '12812812-0000-0000-0000-000000000016';
    raise notice 'PASS: the member — memberships, notices, name on sales gone, Ferme Y''s and the shop''s books whole, kept as an empty shell (soft: a hard delete is refused by the books); the buyer — refused while an order is open, then hard, past order « Client supprimé »; the courier — hard, the delivery kept, unnamed';
end $$;
rollback;

\echo ''
\echo '--- TEST 11: the doors ---'
do $$
declare v text; f text;
begin
    foreach f in array array['purge_org(uuid, uuid, text)', 'delete_my_account_plan(uuid)'] loop
        if has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: % is the app''s', f;
        end if;
    end loop;
    foreach f in array array['delete_my_account(uuid[])', 'delete_my_account_preview()'] loop
        if has_function_privilege('anon', f, 'execute') then raise exception 'FAIL: anon may run %', f; end if;
        if not has_function_privilege('authenticated', f, 'execute') then raise exception 'FAIL: the app may not run %', f; end if;
    end loop;
    v := pg_temp.try128(null, $q$select delete_my_account()::text$q$, 'anon');
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: anon: %', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000011',
        $q$select purge_org('12800000-0000-0000-0000-000000000015', null, 'x')::text$q$);
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: an owner purged: %', v; end if;
    -- delete_org keeps its fences, and the platform's path still works.
    v := pg_temp.try128('12812812-0000-0000-0000-000000000014',
        $q$select delete_org('12800000-0000-0000-0000-000000000015', 'Ferme Y', true)::text$q$);
    if v not like 'ERR: Only a platform admin%' then raise exception 'FAIL: an owner''s delete_org: %', v; end if;
    v := pg_temp.try128('12812812-0000-0000-0000-000000000001',
        $q$select delete_org('12800000-0000-0000-0000-000000000015', 'Ferme Y', true)::text$q$);
    if v not like 'ERR: Archive Ferme Y first%' then raise exception 'FAIL: unarchived: %', v; end if;
    raise notice 'PASS: purge_org and the plan are nobody''s; delete_my_account and its preview the signed-in caller''s, not anon''s; an owner purges nothing; delete_org keeps its platform-only and archive-first fences';
end $$;
begin;
select pg_temp.as128(:mara);
update orgs set archived_at = now() where id = :yfarm;
set local role authenticated;
select delete_org(:yfarm, 'Ferme Y', true) = :yfarm as platform_deleted;
reset role;
do $$ begin
    if exists (select 1 from orgs where id = '12800000-0000-0000-0000-000000000015')
       or not exists (select 1 from deleted_orgs where id = '12800000-0000-0000-0000-000000000015' and deleted_label = 'Mara 128') then
        raise exception 'FAIL: the platform''s delete_org';
    end if;
    raise notice 'PASS: the platform''s delete_org, through purge_org, deletes an archived farm with books and leaves its tombstone';
end $$;
rollback;

\echo '=== test_batch128.sql: all claims hold ==='
