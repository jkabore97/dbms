-- ============================================================
-- test_batch124.sql — Mara says hello, once, by e-mail (124).
--
-- The claims (per person — the same for the owner of a shop, a farm or
-- an association, a shopper or a courier):
--   * Google sign-in (born with a confirmed address) asks for one
--     welcome; the account's locale gives its language;
--   * e-mail and password asks when the address is confirmed, not
--     before; a phone account when it first adds a confirmed address;
--   * NO BACKFILL: an account made before 124 ran is never asked for —
--     not at once, not when it later confirms or changes its address —
--     and running 124 again neither moves the moment nor writes a row;
--   * never twice: a second sign-in event, a changed address, a second
--     claim, a second « done » — still one row, sent once;
--   * the claim hands the address, the first name and the language;
--   * the switch `welcome_email_on` (Réglages, journaled): off, nothing
--     is asked, and a row asked before is marked 'off', not sent;
--   * non-blocking: a broken ask (the webhook failing) never stops a
--     sign-up;
--   * businesses of the three kinds are untouched, and making one asks
--     for nothing more;
--   * the doors: the claim and the done are the service role's alone, the
--     trigger nobody's; the table closed to anon and authenticated, RLS
--     on; definers with a pinned search path.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated, service_role;
-- Earlier suites hand the app's roles every table and function: 124
-- again, so what follows is 124's own doors.
\i database/migrations/124_welcome_email.sql

\set mara    '''12412412-0000-0000-0000-000000000001'''
\set google  '''12412412-0000-0000-0000-000000000002'''
\set pwd     '''12412412-0000-0000-0000-000000000003'''
\set phone   '''12412412-0000-0000-0000-000000000004'''
\set old     '''12412412-0000-0000-0000-000000000005'''
\set oldph   '''12412412-0000-0000-0000-000000000006'''
\set late    '''12412412-0000-0000-0000-000000000007'''
\set broken  '''12412412-0000-0000-0000-000000000008'''
\set fowner  '''12412412-0000-0000-0000-000000000009'''
\set aowner  '''12412412-0000-0000-0000-000000000010'''
\set shop    '''12400000-0000-0000-0000-000000000001'''
\set farm    '''12400000-0000-0000-0000-000000000002'''
\set assoc   '''12400000-0000-0000-0000-000000000003'''

create or replace function pg_temp.as124(p_who uuid)
returns void
language sql
as $$ select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true); $$;

create or replace function pg_temp.refused124(p_sql text, p_role text default null)
returns text
language plpgsql
as $$
begin
    if p_role is not null then
        execute format('set local role %I', p_role);
    end if;
    execute p_sql;
    execute 'reset role';
    return '(went through)';
exception when others then
    execute 'reset role';
    return sqlerrm;
end;
$$;

create or replace function pg_temp.w124(p_who uuid)
returns text
language sql
as $$ select coalesce((select status from welcome_emails where user_id = p_who), '(none)'); $$;

-- The platform's account (made before 124's moment: an older account),
-- and the two older accounts the owner does not want e-mailed.
insert into auth.users (id, phone, email, email_confirmed_at, raw_user_meta_data, created_at) values
    (:mara,  '+22612401001', 'mara124@example.org', now(), '{"full_name": "Mara Cent-Vingt-Quatre"}', now() - interval '1 year'),
    (:old,   null,           'ancien124@example.org', now(), '{"full_name": "Ancien Compte"}',       now() - interval '30 days'),
    (:oldph, '+22612401006', null, null,                     '{"full_name": "Ancien Téléphone"}',    now() - interval '30 days');
update profiles set is_platform_admin = true where id = :mara;

\echo ''
\echo '--- TEST 1: Google sign-in asks for one welcome, in the account''s language ---'
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
    (:google, 'awa124@example.org', now(),
     '{"full_name": "Awa Ouédraogo", "given_name": "Awa", "locale": "en-GB"}');
do $$
declare r welcome_emails;
begin
    select * into r from welcome_emails where user_id = '12412412-0000-0000-0000-000000000002';
    if r.user_id is null or r.status <> 'pending' or r.lang is distinct from 'en' or r.sent_at is not null then
        raise exception 'FAIL: Google sign-in gave %', to_jsonb(r);
    end if;
    raise notice 'PASS: a Google account is asked for once, pending, lang en from its locale';
end $$;

\echo ''
\echo '--- TEST 2: e-mail and password asks on confirmation; a phone account on its first confirmed address ---'
insert into auth.users (id, email, raw_user_meta_data) values
    (:pwd, 'issa124@example.org', '{"full_name": "Issa Traoré"}');
insert into auth.users (id, phone, raw_user_meta_data) values
    (:phone, '+22612401004', '{"full_name": "Fatou Sawadogo"}');
do $$
begin
    if pg_temp.w124('12412412-0000-0000-0000-000000000003') <> '(none)'
       or pg_temp.w124('12412412-0000-0000-0000-000000000004') <> '(none)' then
        raise exception 'FAIL: an unconfirmed address or no address was asked for';
    end if;
end $$;
update auth.users set email_confirmed_at = now() where id = :pwd;
-- A phone number proved changes nothing about an address.
update auth.users set phone_confirmed_at = now() where id = :phone;
do $$
begin
    if pg_temp.w124('12412412-0000-0000-0000-000000000004') <> '(none)' then
        raise exception 'FAIL: a phone account with no address was asked for';
    end if;
end $$;
update auth.users set email = 'fatou124@example.org', email_confirmed_at = now() where id = :phone;
do $$
declare r welcome_emails;
begin
    if pg_temp.w124('12412412-0000-0000-0000-000000000003') <> 'pending'
       or pg_temp.w124('12412412-0000-0000-0000-000000000004') <> 'pending' then
        raise exception 'FAIL: confirmation gave %, first address gave %',
            pg_temp.w124('12412412-0000-0000-0000-000000000003'),
            pg_temp.w124('12412412-0000-0000-0000-000000000004');
    end if;
    select * into r from welcome_emails where user_id = '12412412-0000-0000-0000-000000000003';
    if r.lang is not null then
        raise exception 'FAIL: no locale should give no language, gave %', r.lang;
    end if;
    raise notice 'PASS: asked on confirmation, and on a phone account''s first confirmed address; no locale, no language';
end $$;

\echo ''
\echo '--- TEST 3: no backfill — an account made before 124 is never asked for ---'
do $$
declare v_since timestamptz; v_before text;
begin
    select (value #>> '{}')::timestamptz into v_since
      from platform_settings where key = 'welcome_email_since_marked';
    if v_since is null or not platform_setting_internal('welcome_email_since_marked') then
        raise exception 'FAIL: the moment 124 ran is not kept as an internal marker';
    end if;
    if exists (select 1 from welcome_emails w join auth.users u on u.id = w.user_id
                where u.created_at < v_since) then
        raise exception 'FAIL: an account older than 124 has a row';
    end if;
    raise notice 'PASS: no row for any account made before 124 (moment kept, internal)';
end $$;
-- The older accounts confirm, change, add an address: still nothing.
update auth.users set email = 'ancien124b@example.org', email_confirmed_at = now() where id = :old;
update auth.users set email = 'tel124@example.org', email_confirmed_at = now() where id = :oldph;
update auth.users set email_confirmed_at = now() where id = :mara;
create temp table b124_since as
    select value from platform_settings where key = 'welcome_email_since_marked';
create temp table b124_rows as select * from welcome_emails;
-- 124 again, as the bundle does.
\i database/migrations/124_welcome_email.sql
do $$
begin
    if pg_temp.w124('12412412-0000-0000-0000-000000000005') <> '(none)'
       or pg_temp.w124('12412412-0000-0000-0000-000000000006') <> '(none)'
       or pg_temp.w124('12412412-0000-0000-0000-000000000001') <> '(none)' then
        raise exception 'FAIL: an older account was asked for after a change of address';
    end if;
    if (select value from platform_settings where key = 'welcome_email_since_marked')
       is distinct from (select value from b124_since) then
        raise exception 'FAIL: running 124 again moved the moment';
    end if;
    if exists (select * from welcome_emails except select * from b124_rows)
       or exists (select * from b124_rows except select * from welcome_emails) then
        raise exception 'FAIL: running 124 again changed the rows';
    end if;
    raise notice 'PASS: older accounts stay unasked through confirmation, a new address and a second run of 124';
end $$;

\echo ''
\echo '--- TEST 4: the claim — the address, the first name, the language; then never twice ---'
do $$
declare c jsonb; c2 jsonb; c3 jsonb; d boolean;
begin
    c := welcome_email_claim('12412412-0000-0000-0000-000000000002');
    if not (c ->> 'send')::boolean or c ->> 'email' <> 'awa124@example.org'
       or c ->> 'first_name' <> 'Awa' or c ->> 'lang' <> 'en' then
        raise exception 'FAIL: the claim gave %', c;
    end if;
    if pg_temp.w124('12412412-0000-0000-0000-000000000002') <> 'sending' then
        raise exception 'FAIL: a claimed row is not sending';
    end if;
    c2 := welcome_email_claim('12412412-0000-0000-0000-000000000002');
    if (c2 ->> 'send')::boolean or c2 ->> 'reason' <> 'already sending' then
        raise exception 'FAIL: a second claim gave %', c2;
    end if;
    d := welcome_email_done('12412412-0000-0000-0000-000000000002', true, 're_124', null);
    if not d or pg_temp.w124('12412412-0000-0000-0000-000000000002') <> 'sent'
       or (select sent_at is null or resend_id <> 're_124' from welcome_emails
            where user_id = '12412412-0000-0000-0000-000000000002') then
        raise exception 'FAIL: done did not record the sending';
    end if;
    if welcome_email_done('12412412-0000-0000-0000-000000000002', false, null, 'late') then
        raise exception 'FAIL: a sent row was written again';
    end if;
    c3 := welcome_email_claim('12412412-0000-0000-0000-000000000002');
    if (c3 ->> 'send')::boolean or c3 ->> 'reason' <> 'already sent' then
        raise exception 'FAIL: a claim after the sending gave %', c3;
    end if;
    -- The first name from the profile's full name; no locale, null.
    c := welcome_email_claim('12412412-0000-0000-0000-000000000003');
    if c ->> 'first_name' <> 'Issa' or c -> 'lang' <> 'null'::jsonb then
        raise exception 'FAIL: the password account''s claim gave %', c;
    end if;
    perform welcome_email_done('12412412-0000-0000-0000-000000000003', false, null, 'domain not verified');
    if (select status <> 'failed' or error <> 'domain not verified' or sent_at is not null
          from welcome_emails where user_id = '12412412-0000-0000-0000-000000000003') then
        raise exception 'FAIL: a refusal was not recorded as failed with its words';
    end if;
    c := welcome_email_claim('12412412-0000-0000-0000-000000000003');
    if (c ->> 'send')::boolean then
        raise exception 'FAIL: a failed row was claimed again';
    end if;
    c := welcome_email_claim('12412412-0000-0000-0000-000000000005');
    if (c ->> 'send')::boolean or c ->> 'reason' <> 'not asked' then
        raise exception 'FAIL: an unasked account''s claim gave %', c;
    end if;
    raise notice 'PASS: claim → sending with address, first name and language; a second claim, a second done refused; failed kept with its words';
end $$;
-- Another sign-in event, a changed and confirmed address: still one row, still sent.
update auth.users set email = 'awa124b@example.org', email_confirmed_at = now() where id = :google;
update auth.users set raw_user_meta_data = raw_user_meta_data || '{"x": 1}' where id = :google;
do $$
begin
    if (select count(*) from welcome_emails where user_id = '12412412-0000-0000-0000-000000000002') <> 1
       or pg_temp.w124('12412412-0000-0000-0000-000000000002') <> 'sent' then
        raise exception 'FAIL: a new address asked for a second welcome';
    end if;
    raise notice 'PASS: a new address after the welcome asks for nothing more';
end $$;

\echo ''
\echo '--- TEST 5: the switch in Réglages — off, nothing asked; a row asked before is marked off ---'
begin;
do $$
begin
    perform pg_temp.as124('12412412-0000-0000-0000-000000000001');
    if pg_temp.refused124($q$select platform_set_setting('welcome_email_on', '0')$q$, 'authenticated')
       <> 'Ce réglage attend oui ou non.' then
        raise exception 'FAIL: the switch took a number';
    end if;
    execute 'set local role authenticated';
    perform platform_set_setting('welcome_email_on', 'false');
    if not (platform_settings_board() ? 'welcome_email_on')
       or platform_settings_board() ? 'welcome_email_since_marked' then
        raise exception 'FAIL: Réglages does not show the switch, or shows the marker';
    end if;
    execute 'reset role';
    if not exists (select 1 from platform_actions where kind = 'setting'
                    and after ->> 'key' = 'welcome_email_on') then
        raise exception 'FAIL: the switch was not journaled';
    end if;
end $$;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
    (:late, 'tard124@example.org', now(), '{"full_name": "Tard Venu"}');
do $$
declare c jsonb;
begin
    if pg_temp.w124('12412412-0000-0000-0000-000000000007') <> '(none)' then
        raise exception 'FAIL: switched off, a sign-up was asked for';
    end if;
    -- Fatou's row was asked before the switch: claimed now, it is off.
    c := welcome_email_claim('12412412-0000-0000-0000-000000000004');
    if (c ->> 'send')::boolean or c ->> 'reason' <> 'switched off'
       or pg_temp.w124('12412412-0000-0000-0000-000000000004') <> 'off' then
        raise exception 'FAIL: switched off, the claim gave % (%)', c,
            pg_temp.w124('12412412-0000-0000-0000-000000000004');
    end if;
    raise notice 'PASS: off (a yes or no, journaled, shown in Réglages without the marker): no ask, an earlier ask marked off';
end $$;
rollback;
do $$
begin
    if (select value from platform_settings where key = 'welcome_email_on') <> 'true'::jsonb then
        raise exception 'FAIL: the switch is not on by default';
    end if;
    raise notice 'PASS: on by default';
end $$;

\echo ''
\echo '--- TEST 6: non-blocking — a broken ask never stops a sign-up ---'
begin;
-- The webhook failing, as a trigger on welcome_emails that raises.
create function public.b124_boom() returns trigger language plpgsql
    set search_path = public as
    $$ begin raise exception 'webhook down'; end; $$;
create trigger b124_boom before insert on welcome_emails
    for each row execute function public.b124_boom();
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
    (:broken, 'casse124@example.org', now(), '{"full_name": "Compte Malgré Tout"}');
do $$
begin
    if not exists (select 1 from auth.users where id = '12412412-0000-0000-0000-000000000008')
       or not exists (select 1 from profiles where id = '12412412-0000-0000-0000-000000000008'
                       and full_name = 'Compte Malgré Tout') then
        raise exception 'FAIL: a failing welcome stopped the sign-up';
    end if;
    if pg_temp.w124('12412412-0000-0000-0000-000000000008') <> '(none)' then
        raise exception 'FAIL: the failed ask left a row';
    end if;
    raise notice 'PASS: the account and its profile are made when the ask fails';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: the three kinds — making a business asks for nothing, shows the same ---'
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
    (:fowner, 'ferme124@example.org',   now(), '{"full_name": "Fermier 124"}'),
    (:aowner, 'entraide124@example.org', now(), '{"full_name": "Trésorière 124"}');
create temp table b124_before as select * from welcome_emails;
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled) values
    (:shop,  'Boutique 124', 'boutique-124', 'retail',      'XOF', true),
    (:farm,  'Ferme 124',    'ferme-124',    'farm',        'XOF', true),
    (:assoc, 'Entraide 124', 'entraide-124', 'association', 'XOF', true);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :pwd,    'owner', 'org', :shop,  'full'),
    (:farm,  :fowner, 'owner', 'org', :farm,  'full'),
    (:assoc, :aowner, 'owner', 'org', :assoc, 'full');
do $$
begin
    if exists (select * from welcome_emails except select * from b124_before)
       or exists (select * from b124_before except select * from welcome_emails) then
        raise exception 'FAIL: making a business changed the welcomes';
    end if;
    if pg_temp.w124('12412412-0000-0000-0000-000000000009') <> 'pending'
       or pg_temp.w124('12412412-0000-0000-0000-000000000010') <> 'pending' then
        raise exception 'FAIL: the farmer or the treasurer was not asked for';
    end if;
    raise notice 'PASS: one welcome per person, the same for a shop''s, a farm''s and an association''s owner; a business adds none';
end $$;

\echo ''
\echo '--- TEST 8: the doors ---'
do $$
declare v_role text; v_r text;
begin
    foreach v_role in array array['anon', 'authenticated'] loop
        if has_function_privilege(v_role, 'welcome_email_claim(uuid)', 'execute')
           or has_function_privilege(v_role, 'welcome_email_done(uuid, boolean, text, text)', 'execute')
           or has_function_privilege(v_role, 'trg_welcome_email_request()', 'execute') then
            raise exception 'FAIL: % may call a welcome function', v_role;
        end if;
        if has_table_privilege(v_role, 'welcome_emails', 'select')
           or has_table_privilege(v_role, 'welcome_emails', 'insert')
           or has_table_privilege(v_role, 'welcome_emails', 'update')
           or has_table_privilege(v_role, 'welcome_emails', 'delete') then
            raise exception 'FAIL: % has a right on welcome_emails', v_role;
        end if;
    end loop;
    if has_function_privilege('public', 'welcome_email_claim(uuid)', 'execute') then
        raise exception 'FAIL: PUBLIC may claim';
    end if;
    if not has_function_privilege('service_role', 'welcome_email_claim(uuid)', 'execute')
       or not has_function_privilege('service_role', 'welcome_email_done(uuid, boolean, text, text)', 'execute') then
        raise exception 'FAIL: the service role lost the Worker''s two calls';
    end if;
    v_r := pg_temp.refused124($q$select welcome_email_claim('12412412-0000-0000-0000-000000000009')$q$, 'authenticated');
    if v_r not like 'permission denied%' then
        raise exception 'FAIL: a signed-in person claiming gave « % »', v_r;
    end if;
    v_r := pg_temp.refused124('select count(*) from welcome_emails', 'anon');
    if v_r not like 'permission denied%' then
        raise exception 'FAIL: anon reading welcome_emails gave « % »', v_r;
    end if;
    if not (select relrowsecurity from pg_class where relname = 'welcome_emails') then
        raise exception 'FAIL: RLS is off on welcome_emails';
    end if;
    if exists (select 1 from pg_proc
                where proname in ('welcome_email_claim', 'welcome_email_done', 'trg_welcome_email_request')
                  and (not prosecdef
                       or not coalesce((select true from unnest(proconfig) c where c like 'search_path=%'), false))) then
        raise exception 'FAIL: a welcome function is not a definer with its search path';
    end if;
    raise notice 'PASS: claim and done the service role''s alone, the trigger nobody''s; welcome_emails closed, RLS on; definers with a search path';
end $$;

\echo '=== test_batch124.sql: all claims hold ==='
