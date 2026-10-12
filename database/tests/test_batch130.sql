-- ============================================================
-- test_batch130.sql — the second security audit's database fixes (130).
--
-- The claims (platform-level: the same whether the business is a shop, a
-- farm or an association — the three are made below where it matters):
--   * M1: the migrations' ledger, made the way an older database had it
--     (no row security, INSERT/UPDATE/DELETE for authenticated), is locked
--     by 130: row security on, nothing for PUBLIC, anon or authenticated —
--     a signed-in account can neither pre-insert a migration nor delete
--     one; with no ledger at all (CI) 130 does nothing;
--   * M2: a sign-up named with a link, a tag, a line break and invisible
--     marks rings the admins with plain words: no « :// », no « www. », no
--     tag, no control character, the domain's dots gone, at most 60
--     characters, in the message and in params; the contact (an e-mail)
--     keeps its dots and still finds the person; an ordinary name and a
--     nameless account read as before; bells written before 130 are
--     rewritten the same way, and 130 again changes nothing;
--   * M4: a sandbox purchase counts for the App Review account's business
--     only when that account's address is confirmed; store_review_orgs,
--     when it names businesses, narrows it to those; a platform admin's
--     own business as before; an ordinary business never — for a shop, a
--     farm and an association alike;
--   * M6: otp_send_allow — 3 codes per number per 10 minutes, 10 a day;
--     5 per account per 10 minutes, 20 a day; the same number written
--     another way is the same number; a bad number refused; no number
--     kept in clear; an account's rows go with it; only the service role
--     calls it, the table is nobody's;
--   * the doors: anon and authenticated call none of the new functions;
--     the definers have a pinned search path.
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
-- Earlier suites hand the app's roles every table and function, and 129's
-- suite put 129's trigger back: 130 again, so what follows is 130's.
\i database/migrations/130_audit_fixes.sql

\set mara    '''13013013-0000-0000-0000-000000000001'''
\set phish   '''13013013-0000-0000-0000-000000000002'''
\set awa     '''13013013-0000-0000-0000-000000000003'''
\set issa    '''13013013-0000-0000-0000-000000000004'''
\set review  '''13013013-0000-0000-0000-000000000005'''
\set owner   '''13013013-0000-0000-0000-000000000006'''
\set otp1    '''13013013-0000-0000-0000-000000000007'''
\set otp2    '''13013013-0000-0000-0000-000000000008'''
\set gone    '''13013013-0000-0000-0000-000000000009'''
\set shop    '''13000000-0000-0000-0000-000000000001'''
\set farm    '''13000000-0000-0000-0000-000000000002'''
\set assoc   '''13000000-0000-0000-0000-000000000003'''
\set plain   '''13000000-0000-0000-0000-000000000004'''
\set mine    '''13000000-0000-0000-0000-000000000005'''

create or replace function pg_temp.try130(p_sql text, p_role text default null)
returns text
language plpgsql
as $$
declare v text;
begin
    if p_role is not null then
        execute format('set local role %I', p_role);
    end if;
    execute p_sql into v;
    execute 'reset role';
    return coalesce(v, '(went through)');
exception when others then
    execute 'reset role';
    return 'ERR: ' || sqlerrm;
end;
$$;

\echo ''
\echo '--- TEST 1 (M1): the ledger, as an older database had it, locked by 130 ---'
begin;
create table if not exists kaj_migrations (
    name       text primary key,
    applied_at timestamptz not null default now()
);
-- As found on the live copy: no row security, Supabase's grants.
alter table kaj_migrations disable row level security;
grant select, insert, update, delete on kaj_migrations to authenticated, anon;
insert into kaj_migrations (name) values ('129_new_user_notify.sql') on conflict do nothing;
do $$
begin
    if pg_temp.try130($q$insert into kaj_migrations (name) values ('131_next.sql') returning name$q$, 'authenticated') <> '131_next.sql' then
        raise exception 'FAIL: the setup did not reproduce the open ledger';
    end if;
    delete from kaj_migrations where name = '131_next.sql';
end $$;
\i database/migrations/130_audit_fixes.sql
do $$
declare v text; r text;
begin
    if not (select relrowsecurity from pg_class where oid = 'kaj_migrations'::regclass) then
        raise exception 'FAIL: kaj_migrations has no row security';
    end if;
    foreach r in array array['anon', 'authenticated', 'public'] loop
        if exists (select 1 from aclexplode((select relacl from pg_class where oid = 'kaj_migrations'::regclass)) a
                    where a.grantee = case r when 'public' then 0 else (select oid from pg_roles where rolname = r) end) then
            raise exception 'FAIL: % still holds a privilege on kaj_migrations', r;
        end if;
    end loop;
    v := pg_temp.try130($q$insert into kaj_migrations (name) values ('131_next.sql') returning name$q$, 'authenticated');
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: authenticated pre-inserted a migration: %', v; end if;
    v := pg_temp.try130($q$delete from kaj_migrations where name = '129_new_user_notify.sql' returning name$q$, 'authenticated');
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: authenticated deleted a migration: %', v; end if;
    v := pg_temp.try130($q$select count(*)::text from kaj_migrations$q$, 'anon');
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: anon read the ledger: %', v; end if;
    if not exists (select 1 from kaj_migrations where name = '129_new_user_notify.sql') then
        raise exception 'FAIL: 130 lost a ledger row';
    end if;
    raise notice 'PASS: M1 — an open ledger (no RLS, authenticated arwd) is locked by 130: row security on, nothing for PUBLIC, anon or authenticated; a pre-insert and a delete are refused; its rows kept';
end $$;
rollback;
do $$
begin
    if to_regclass('public.kaj_migrations') is not null then
        raise notice 'kaj_migrations exists here (a rig made it): left as it is';
    end if;
    raise notice 'PASS: M1 — with no ledger (CI), 130 runs and makes none';
end $$;

\echo ''
\echo '--- TEST 2 (M2): a sign-up named with a link rings the admins in plain words ---'
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data) values
    (:mara, 'mara130@example.org', now(), '{"full_name": "Mara 130"}', '{"provider": "email"}');
update profiles set is_platform_admin = true where id = :mara;
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
    (:phish, 'ceo@victim-company.bf',
     jsonb_build_object('full_name', E'Support Mara: compte suspendu,\nreconnectez-vous sur https://mara-login.example/verify <b>x</b> www.mara-help.bf‮​ URGENT'),
     '{"provider": "email"}');
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data) values
    (:awa, 'awa130@example.org', now(), '{"full_name": "Awa Ouédraogo"}', '{"provider": "google"}');
insert into auth.users (id, email, raw_app_meta_data) values
    (:issa, 'issa130@example.org', '{"provider": "email"}');
do $$
declare
    r notifications;
    v_name text;
begin
    select * into r from notifications
     where kind = 'new_user' and recipient_id = '13013013-0000-0000-0000-000000000001'
       and params ->> 'user_id' = '13013013-0000-0000-0000-000000000002';
    if r.id is null then raise exception 'FAIL: the sign-up rang nobody'; end if;
    v_name := r.params ->> 'name';
    if r.message ~ '[[:cntrl:]]' or v_name ~ '[[:cntrl:]]'
       or r.message like '%://%' or v_name like '%://%'
       or r.message ~* 'www\.' or v_name ~* 'www\.'
       or r.message ~ '[<>]' or v_name ~ '[<>]'
       or r.message ~ '[[:alnum:]]\.[[:alnum:]]' or v_name ~ '[[:alnum:]]\.[[:alnum:]]'
       or r.message ~ '[‮​]'
       or char_length(v_name) > 60 then
        raise exception 'FAIL: the bell still carries a link, a tag or a control: % / %', r.message, r.params;
    end if;
    if r.message <> format('Nouveau compte : %s (e-mail)', v_name)
       or v_name not like 'Support Mara: compte suspendu, reconnectez-vous sur https%' then
        raise exception 'FAIL: the bell reads %', r.message;
    end if;
    -- The contact: an e-mail, its dots kept — « Personnes » still finds it.
    if r.params ->> 'contact' <> 'ceo@victim-company.bf' then
        raise exception 'FAIL: the contact reads %', r.params ->> 'contact';
    end if;
    -- An ordinary name and a nameless account as 129 said them.
    if (select message from notifications where kind = 'new_user'
          and recipient_id = '13013013-0000-0000-0000-000000000001'
          and params ->> 'user_id' = '13013013-0000-0000-0000-000000000003') <> 'Nouveau compte : Awa Ouédraogo (Google)'
       or (select message from notifications where kind = 'new_user'
          and recipient_id = '13013013-0000-0000-0000-000000000001'
          and params ->> 'user_id' = '13013013-0000-0000-0000-000000000004') <> 'Nouveau compte : issa130@example.org (e-mail)' then
        raise exception 'FAIL: an ordinary bell changed';
    end if;
    if notify_plain(E'a\tb\r\nc') <> 'a b c' or notify_plain('   ') is not null
       or notify_plain(repeat('é', 200)) <> repeat('é', 60)
       or notify_plain('https://x.example/a', 60, true) <> 'https x.example/a'
       or notify_plain('M.Diallo WWW.x.bf') <> 'M Diallo x bf' then
        raise exception 'FAIL: notify_plain';
    end if;
    raise notice 'PASS: M2 — « % » : no ://, no www., no tag, no control or invisible mark, no domain dot, ≤ 60 characters; contact ceo@victim-company.bf kept for the search; ordinary bells as 129 wrote them', r.message;
end $$;

-- A bell 129 wrote before 130 (its raw name) is rewritten; 130 again
-- changes nothing.
insert into notifications (recipient_id, org_id, kind, message, params) values
    (:mara, null, 'new_user', E'Nouveau compte : Clique\nhttps://evil.example (e-mail)',
     jsonb_build_object('to', 'platform', 'user_id', '13013013-0000-0000-0000-0000000000aa',
                        'name', E'Clique\nhttps://evil.example', 'method', 'email', 'contact', 'x@evil.example'));
\i database/migrations/130_audit_fixes.sql
create temp table plain130 as
    select id, message, params from notifications where kind = 'new_user';
\i database/migrations/130_audit_fixes.sql
do $$
declare r notifications;
begin
    select * into r from notifications
     where kind = 'new_user' and params ->> 'user_id' = '13013013-0000-0000-0000-0000000000aa';
    if r.message <> 'Nouveau compte : Clique https evil example (e-mail)'
       or r.params ->> 'name' <> 'Clique https evil example'
       or r.params ->> 'contact' <> 'x@evil.example' then
        raise exception 'FAIL: the older bell reads % / %', r.message, r.params;
    end if;
    if exists (select 1 from notifications n join plain130 p on p.id = n.id
                where n.message <> p.message or n.params <> p.params) then
        raise exception 'FAIL: 130 run again changed a bell';
    end if;
    if exists (select 1 from notifications where kind = 'new_user'
                 and (message ~ '[[:cntrl:]]' or message like '%://%')) then
        raise exception 'FAIL: a new_user bell is still raw';
    end if;
    raise notice 'PASS: M2 — a bell written before 130 is made plain (« % »); 130 again changes no bell', r.message;
end $$;

\echo ''
\echo '--- TEST 3 (M4): sandbox purchases — the review account confirmed, and the businesses named ---'
update platform_settings set value = '"review130@example.org"' where key = 'store_review_account';
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
    (:review, 'Review130@example.org', null, '{"full_name": "App Review 130"}'),
    (:owner,  'patron130@example.org', now(), '{"full_name": "Patron 130"}');
insert into orgs (id, name, slug, profile, default_currency) values
    (:shop,  'Boutique 130', 'boutique-130', 'retail',      'XOF'),
    (:farm,  'Ferme 130',    'ferme-130',    'farm',        'XOF'),
    (:assoc, 'Entraide 130', 'entraide-130', 'association', 'XOF'),
    (:plain, 'Simple 130',   'simple-130',   'retail',      'XOF'),
    (:mine,  'Mara 130',     'mara-130',     'retail',      'XOF');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :review, 'owner', 'org', :shop,  'full'),
    (:farm,  :review, 'owner', 'org', :farm,  'full'),
    (:assoc, :review, 'owner', 'org', :assoc, 'full'),
    (:plain, :owner,  'owner', 'org', :plain, 'full'),
    (:mine,  :mara,   'owner', 'org', :mine,  'full');
do $$
declare
    k uuid;
    v_r jsonb;
begin
    if (select value #>> '{}' from platform_settings where key = 'store_review_orgs') is distinct from '' then
        raise exception 'FAIL: store_review_orgs default';
    end if;
    -- Unconfirmed: the address typed at a sign-up proves nothing.
    foreach k in array array['13000000-0000-0000-0000-000000000001', '13000000-0000-0000-0000-000000000002',
                             '13000000-0000-0000-0000-000000000003']::uuid[] loop
        if store_sandbox_allowed(k) then
            raise exception 'FAIL: an unconfirmed review account''s business % counts sandbox purchases', k;
        end if;
    end loop;
    v_r := store_settle('apple', '13000000-0000-0000-0000-000000000001', 'bf.kaj.app.pro.monthly', 'sbx-130-1',
                        'active', now() + interval '30 days', true, 'sandbox');
    if (v_r ->> 'ok')::boolean or v_r ->> 'reason' <> 'sandbox'
       or exists (select 1 from store_subscriptions where original_id = 'sbx-130-1') then
        raise exception 'FAIL: an unconfirmed review account''s sandbox purchase was written: %', v_r;
    end if;
    -- Confirmed: its businesses, the three kinds (the address's case aside).
    update auth.users set email_confirmed_at = now() where id = '13013013-0000-0000-0000-000000000005';
    foreach k in array array['13000000-0000-0000-0000-000000000001', '13000000-0000-0000-0000-000000000002',
                             '13000000-0000-0000-0000-000000000003']::uuid[] loop
        if not store_sandbox_allowed(k) then
            raise exception 'FAIL: the confirmed review account''s business % refused', k;
        end if;
    end loop;
    v_r := store_settle('apple', '13000000-0000-0000-0000-000000000001', 'bf.kaj.app.pro.monthly', 'sbx-130-1',
                        'active', now() + interval '30 days', true, 'sandbox');
    if not coalesce((v_r ->> 'pro')::boolean, false) or org_plan('13000000-0000-0000-0000-000000000001') <> 'pro' then
        raise exception 'FAIL: the confirmed review account''s sandbox purchase: %', v_r;
    end if;
    -- Named businesses: only those.
    update platform_settings set value = '"13000000-0000-0000-0000-000000000002, 13000000-0000-0000-0000-000000000003"'
     where key = 'store_review_orgs';
    if store_sandbox_allowed('13000000-0000-0000-0000-000000000001')
       or not store_sandbox_allowed('13000000-0000-0000-0000-000000000002')
       or not store_sandbox_allowed('13000000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: store_review_orgs does not narrow the review account';
    end if;
    if org_plan('13000000-0000-0000-0000-000000000001') <> 'free' then
        raise exception 'FAIL: a sandbox row still counts for a business no longer named';
    end if;
    -- A business named that the review account does not own: still no.
    update platform_settings set value = '"13000000-0000-0000-0000-000000000004"' where key = 'store_review_orgs';
    if store_sandbox_allowed('13000000-0000-0000-0000-000000000004') then
        raise exception 'FAIL: naming an ordinary business let its sandbox purchases in';
    end if;
    update platform_settings set value = '""' where key = 'store_review_orgs';
    -- An ordinary business never; a platform admin's own business as before.
    if store_sandbox_allowed('13000000-0000-0000-0000-000000000004') then
        raise exception 'FAIL: an ordinary business counts sandbox purchases';
    end if;
    if not store_sandbox_allowed('13000000-0000-0000-0000-000000000005') then
        raise exception 'FAIL: the platform''s own business refused';
    end if;
    -- No review account named: nobody but the platform.
    update platform_settings set value = '""' where key = 'store_review_account';
    if store_sandbox_allowed('13000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: an empty store_review_account matched';
    end if;
    update platform_settings set value = '"review.mara@gmail.com"' where key = 'store_review_account';
    raise notice 'PASS: M4 — unconfirmed review account: no sandbox (nothing written); confirmed: its shop, farm and association; store_review_orgs narrows it (and never opens a stranger''s); an ordinary business never; the platform''s own as before';
end $$;

\echo ''
\echo '--- TEST 4 (M6): the WhatsApp code, rationed ---'
insert into auth.users (id, email, email_confirmed_at) values
    (:otp1, 'otp130a@example.org', now()),
    (:otp2, 'otp130b@example.org', now()),
    (:gone, 'otp130c@example.org', now());
do $$
declare
    a uuid := '13013013-0000-0000-0000-000000000007';
    b uuid := '13013013-0000-0000-0000-000000000008';
    i int;
    v jsonb;
begin
    -- Per number: 3 in 10 minutes, whoever asks and however it is written.
    if not (otp_send_allow('22670130001', a) ->> 'ok')::boolean
       or not (otp_send_allow('+226 70 13 00 01', b) ->> 'ok')::boolean
       or not (otp_send_allow('226-70-130-001', null) ->> 'ok')::boolean then
        raise exception 'FAIL: the first three codes to a number';
    end if;
    v := otp_send_allow('22670130001', a);
    if (v ->> 'ok')::boolean or v ->> 'reason' <> 'phone_10_minutes' then
        raise exception 'FAIL: a fourth code in 10 minutes: %', v;
    end if;
    -- Ten minutes later: again, up to 10 in the day.
    update otp_sends set sent_at = sent_at - interval '11 minutes';
    for i in 1..3 loop
        if not (otp_send_allow('22670130001', null) ->> 'ok')::boolean then
            raise exception 'FAIL: code % after ten minutes', i + 3;
        end if;
    end loop;
    update otp_sends set sent_at = sent_at - interval '11 minutes';
    for i in 1..3 loop
        if not (otp_send_allow('22670130001', null) ->> 'ok')::boolean then
            raise exception 'FAIL: code % of the day', i + 6;
        end if;
    end loop;
    update otp_sends set sent_at = sent_at - interval '11 minutes';
    if not (otp_send_allow('22670130001', null) ->> 'ok')::boolean then
        raise exception 'FAIL: the tenth code of the day';
    end if;
    update otp_sends set sent_at = sent_at - interval '11 minutes';
    v := otp_send_allow('22670130001', null);
    if (v ->> 'ok')::boolean or v ->> 'reason' <> 'phone_day' then
        raise exception 'FAIL: an eleventh code in a day: %', v;
    end if;
    -- Another number is another count.
    if not (otp_send_allow('22670130002', null) ->> 'ok')::boolean then
        raise exception 'FAIL: another number refused';
    end if;
    -- Per account: 5 in 10 minutes across numbers.
    for i in 1..5 loop
        if not (otp_send_allow('2267013010' || i, a) ->> 'ok')::boolean then
            raise exception 'FAIL: the account''s code % to a new number', i;
        end if;
    end loop;
    v := otp_send_allow('22670130199', a);
    if (v ->> 'ok')::boolean or v ->> 'reason' <> 'account_10_minutes' then
        raise exception 'FAIL: a sixth code for one account in 10 minutes: %', v;
    end if;
    -- 20 a day per account.
    for i in 1..3 loop
        update otp_sends set sent_at = sent_at - interval '11 minutes' where user_id = a;
        perform otp_send_allow('2267013020' || i || '1', a), otp_send_allow('2267013020' || i || '2', a),
                otp_send_allow('2267013020' || i || '3', a), otp_send_allow('2267013020' || i || '4', a),
                otp_send_allow('2267013020' || i || '5', a);
    end loop;
    update otp_sends set sent_at = sent_at - interval '11 minutes' where user_id = a;
    if (select count(*) from otp_sends where user_id = a) <> 20 then
        raise exception 'FAIL: the account holds % codes, not 20', (select count(*) from otp_sends where user_id = a);
    end if;
    v := otp_send_allow('22670130299', a);
    if (v ->> 'ok')::boolean or v ->> 'reason' <> 'account_day' then
        raise exception 'FAIL: a 21st code for one account in a day: %', v;
    end if;
    -- A number that is not one.
    v := otp_send_allow('12345', b);
    if (v ->> 'ok')::boolean or v ->> 'reason' <> 'phone' then
        raise exception 'FAIL: a short number: %', v;
    end if;
    -- No number in clear.
    if exists (select 1 from otp_sends where phone_key like '%2267013%' or phone_key !~ '^[0-9a-f]{32}$') then
        raise exception 'FAIL: a number is kept in clear';
    end if;
    -- Older than two days: forgotten at the next call.
    update otp_sends set sent_at = now() - interval '3 days' where user_id = b;
    perform otp_send_allow('22670130999', null);
    if exists (select 1 from otp_sends where user_id = b) then
        raise exception 'FAIL: rows older than two days kept';
    end if;
    raise notice 'PASS: M6 — 3 per number in 10 minutes (however written, whoever asks), 10 a day; 5 per account in 10 minutes, 20 a day; another number another count; a bad number refused; md5 only, never the number; two days, then gone';
end $$;
-- An account's rows go with it.
do $$ begin perform otp_send_allow('22670130888', '13013013-0000-0000-0000-000000000009'); end $$;
delete from auth.users where id = :gone;
do $$
declare v text;
begin
    if exists (select 1 from otp_sends where user_id = '13013013-0000-0000-0000-000000000009') then
        raise exception 'FAIL: a deleted account''s codes kept';
    end if;
    -- The doors: the service role calls it; the app and anon do not, and
    -- read or write nothing.
    v := pg_temp.try130($q$select (otp_send_allow('22670130777', null) ->> 'ok')$q$, 'service_role');
    if v <> 'true' then raise exception 'FAIL: the service role could not ask: %', v; end if;
    v := pg_temp.try130($q$select (otp_send_allow('22670130776', null) ->> 'ok')$q$, 'authenticated');
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: authenticated asked: %', v; end if;
    v := pg_temp.try130($q$select (otp_send_allow('22670130775', null) ->> 'ok')$q$, 'anon');
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: anon asked: %', v; end if;
    v := pg_temp.try130($q$select count(*)::text from otp_sends$q$, 'authenticated');
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: authenticated read otp_sends: %', v; end if;
    v := pg_temp.try130($q$delete from otp_sends returning 'x'$q$, 'authenticated');
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: authenticated emptied otp_sends: %', v; end if;
    v := pg_temp.try130($q$select count(*)::text from otp_sends$q$, 'service_role');
    if v not like 'ERR: permission denied%' then raise exception 'FAIL: the service role reads otp_sends directly: %', v; end if;
    if not (select relrowsecurity from pg_class where oid = 'otp_sends'::regclass) then
        raise exception 'FAIL: otp_sends has no row security';
    end if;
    raise notice 'PASS: M6 — a deleted account''s rows go with it; the service role asks, authenticated and anon do not; the table is nobody''s to read or write, row security on';
end $$;

\echo ''
\echo '--- TEST 5: the doors ---'
do $$
declare f text;
begin
    foreach f in array array['notify_plain(text, integer, boolean)', 'otp_send_allow(text, uuid)',
                             'store_sandbox_allowed(uuid)', 'trg_notify_new_user()'] loop
        if has_function_privilege('anon', f, 'execute') then raise exception 'FAIL: anon may run %', f; end if;
        if has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: authenticated may run %', f;
        end if;
    end loop;
    if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public'
                  and p.proname in ('otp_send_allow', 'store_sandbox_allowed', 'trg_notify_new_user')
                  and (not p.prosecdef or p.proconfig is null
                       or not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'))) then
        raise exception 'FAIL: a definer without its pinned search path';
    end if;
    if has_table_privilege('anon', 'otp_sends', 'insert') or has_table_privilege('authenticated', 'otp_sends', 'select') then
        raise exception 'FAIL: otp_sends open to the app';
    end if;
    raise notice 'PASS: notify_plain, otp_send_allow, store_sandbox_allowed and the new-account trigger are nobody''s in the app; the definers pin their search path';
end $$;

\echo ''
\echo '--- TEST 6: « Mara Pro est actif » once per subscription, not once per renewal ---'
do $$
declare
    v_plain uuid := '13000000-0000-0000-0000-000000000004';   -- a shop
    v_farm  uuid := '13000000-0000-0000-0000-000000000002';   -- a farm
    v_r jsonb;
    told int;
begin
    -- Google: bought — one bell.
    v_r := store_settle('google', v_plain, 'mara_pro:yearly', 'renew-130-1', 'active',
                        now() + interval '30 minutes', true, 'production');
    if not (v_r ->> 'pro')::boolean then raise exception 'FAIL: the purchase: %', v_r; end if;
    select count(*) into told from notifications where org_id = v_plain and kind = 'pro_active';
    if told <> 1 then raise exception 'FAIL: % bells for the purchase', told; end if;
    -- Renewed, its news a few minutes after the paid end (the plan free
    -- meanwhile): no new bell. Twice.
    update store_subscriptions set expires_at = now() - interval '4 minutes' where original_id = 'renew-130-1';
    if org_plan(v_plain) <> 'free' then raise exception 'FAIL: the lapse is not a lapse'; end if;
    v_r := store_settle('google', v_plain, 'mara_pro:yearly', 'renew-130-1', 'active',
                        now() + interval '30 minutes', true, 'production');
    update store_subscriptions set expires_at = now() - interval '2 minutes', state = 'expired' where original_id = 'renew-130-1';
    v_r := store_settle('google', v_plain, 'mara_pro:yearly', 'renew-130-1', 'active',
                        now() + interval '30 minutes', true, 'production');
    if not (v_r ->> 'pro')::boolean then raise exception 'FAIL: the renewal: %', v_r; end if;
    select count(*) into told from notifications where org_id = v_plain and kind = 'pro_active';
    if told <> 1 then raise exception 'FAIL: a renewal rang again (% bells)', told; end if;
    -- A new token replacing it (an upgrade, a re-buy) while it ran in the
    -- last 24 hours: no bell either.
    update store_subscriptions set expires_at = now() - interval '10 minutes' where original_id = 'renew-130-1';
    v_r := store_settle('google', v_plain, 'mara_pro:monthly', 'renew-130-2', 'active',
                        now() + interval '30 days', true, 'production', null, null, 'renew-130-1');
    select count(*) into told from notifications where org_id = v_plain and kind = 'pro_active';
    if not (v_r ->> 'pro')::boolean or told <> 1 then
        raise exception 'FAIL: a replacing token rang (% bells) / %', told, v_r;
    end if;
    -- Lapsed more than 24 hours, then subscribed again: a new bell.
    update store_subscriptions set expires_at = now() - interval '25 hours', state = 'expired'
     where original_id = 'renew-130-2';
    if org_plan(v_plain) <> 'free' then raise exception 'FAIL: still Pro after the lapse'; end if;
    v_r := store_settle('google', v_plain, 'mara_pro:monthly', 'renew-130-2', 'active',
                        now() + interval '30 days', true, 'production');
    select count(*) into told from notifications where org_id = v_plain and kind = 'pro_active';
    if told <> 2 then raise exception 'FAIL: a re-subscription after 24 hours: % bells', told; end if;
    -- A brand-new token after a lapse of more than 24 hours: a bell.
    update store_subscriptions set expires_at = now() - interval '26 hours', state = 'expired'
     where org_id = v_plain;
    v_r := store_settle('google', v_plain, 'mara_pro:monthly', 'renew-130-3', 'active',
                        now() + interval '30 days', true, 'production', null, null, 'renew-130-2');
    select count(*) into told from notifications where org_id = v_plain and kind = 'pro_active';
    if told <> 3 then raise exception 'FAIL: a new token after 24 hours: % bells', told; end if;

    -- Apple (one originalTransactionId through every renewal), on a farm.
    v_r := store_settle('apple', v_farm, 'bf.kaj.app.pro.monthly', 'orig-130-a', 'active',
                        now() + interval '5 minutes', true, 'production');
    update store_subscriptions set expires_at = now() - interval '3 minutes' where original_id = 'orig-130-a';
    v_r := store_settle('apple', v_farm, 'bf.kaj.app.pro.monthly', 'orig-130-a', 'active',
                        now() + interval '30 days', true, 'production');
    select count(*) into told from notifications where org_id = v_farm and kind = 'pro_active';
    if told <> 1 then raise exception 'FAIL: Apple: % bells for a purchase and its renewal', told; end if;
    -- Refunded more than 24 hours ago, bought again: a bell.
    update store_subscriptions set state = 'revoked', last_verified_at = now() - interval '30 hours'
     where original_id = 'orig-130-a';
    v_r := store_settle('apple', v_farm, 'bf.kaj.app.pro.monthly', 'orig-130-a', 'active',
                        now() + interval '30 days', true, 'production');
    select count(*) into told from notifications where org_id = v_farm and kind = 'pro_active';
    if told <> 2 then raise exception 'FAIL: Apple: a re-subscription after a refund: % bells', told; end if;
    raise notice 'PASS: Pro bells — one for a purchase; none for a renewal whose news came minutes after the paid end (twice), nor for a Google token replacing one that ran in the last 24 hours; one for a re-subscription after 24 hours (same token, new token, Apple after a refund); a shop and a farm';
end $$;
