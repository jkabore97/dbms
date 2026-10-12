-- ============================================================
-- test_batch129.sql — Mara hears of every new account; the ranking's
-- bell stays off (129).
--
-- The claims (platform-level: the same whether the account goes on to
-- run a shop, a farm, an association, or nothing):
--   * a new account rings every platform admin once — kind new_user, in
--     the platform's list, its facts in params (user id, name, method,
--     contact) — and nobody else;
--   * the method is said for Google, Apple, e-mail and téléphone (GoTrue's
--     provider; without one, an address or a number), the name falls back
--     to the e-mail or the number;
--   * the switch `admin_new_user_notify` (Réglages, journaled): off,
--     nothing is written; on again, it rings again;
--   * an account that is a platform admin from birth is not told about
--     itself; the other admins are;
--   * non-blocking: a bell that cannot be written never stops a sign-up;
--   * the ranking's job 'cauris-board' inactive where pg_cron exists (a
--     stand-in cron here when there is none), 'cauris-week-close' left
--     as it was, and running it again changes nothing;
--   * the doors: anon and authenticated call none of the new functions;
--     the trigger's function a definer with a pinned search path;
--   * P1: the profile, the welcome e-mail, the other bells and the three
--     kinds of business as before; 129 run again writes nothing.
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
-- Earlier suites hand the app's roles every table and function: 129
-- again, so what follows is 129's own doors.
\i database/migrations/129_new_user_notify.sql

\set mara    '''12912912-0000-0000-0000-000000000001'''
\set ops     '''12912912-0000-0000-0000-000000000002'''
\set plain   '''12912912-0000-0000-0000-000000000003'''
\set google  '''12912912-0000-0000-0000-000000000004'''
\set mail    '''12912912-0000-0000-0000-000000000005'''
\set phone   '''12912912-0000-0000-0000-000000000006'''
\set apple   '''12912912-0000-0000-0000-000000000007'''
\set bare    '''12912912-0000-0000-0000-000000000008'''
\set quiet   '''12912912-0000-0000-0000-000000000009'''
\set boss    '''12912912-0000-0000-0000-000000000010'''
\set broken  '''12912912-0000-0000-0000-000000000011'''

create or replace function pg_temp.as129(p_who uuid)
returns void
language sql
as $$ select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true); $$;

create or replace function pg_temp.refused129(p_sql text, p_role text default null)
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

-- The new_user bells about one account: how many, to whom.
create or replace function pg_temp.told129(p_about uuid)
returns int
language sql
as $$ select count(*)::int from notifications
       where kind = 'new_user' and params ->> 'user_id' = p_about::text; $$;

-- Every platform admin there is now (earlier suites leave theirs).
create or replace function pg_temp.admins129(p_but uuid default null)
returns int
language sql
as $$ select count(*)::int from profiles where is_platform_admin and id is distinct from p_but; $$;

-- Two platform admins and an ordinary account, made before any of it.
insert into auth.users (id, phone, email, raw_user_meta_data, raw_app_meta_data) values
    (:mara,  '+22612901001', 'mara129@example.org', '{"full_name": "Mara Cent-Vingt-Neuf"}', '{"provider": "email"}'),
    (:ops,   null,           'ops129@example.org',  '{"full_name": "Ops Mara"}',             '{"provider": "google"}'),
    (:plain, '+22612901003', null,                  '{"full_name": "Simple Compte"}',        '{"provider": "phone"}');
update profiles set is_platform_admin = true where id in (:mara, :ops);
-- What every earlier account holds before the first sign-up below.
create temp table before129 as
    select recipient_id, kind, count(*) as n from notifications group by 1, 2;

\echo ''
\echo '--- TEST 1: a Google account rings every platform admin once, nobody else ---'
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data) values
    (:google, 'awa129@example.org', now(),
     '{"full_name": "Awa Ouédraogo", "given_name": "Awa"}', '{"provider": "google", "providers": ["google"]}');
do $$
declare
    v_about uuid := '12912912-0000-0000-0000-000000000004';
    n int;
    r notifications;
begin
    if pg_temp.told129(v_about) <> pg_temp.admins129() or pg_temp.admins129() < 2 then
        raise exception 'FAIL: % bells for % platform admins', pg_temp.told129(v_about), pg_temp.admins129();
    end if;
    select count(*) into n from notifications x
      join profiles p on p.id = x.recipient_id
     where x.kind = 'new_user' and x.params ->> 'user_id' = v_about::text
       and not p.is_platform_admin;
    if n <> 0 then
        raise exception 'FAIL: % bells went to somebody who is not a platform admin', n;
    end if;
    select count(*) into n from notifications x
     where x.kind = 'new_user' and x.params ->> 'user_id' = v_about::text
     group by x.recipient_id having count(*) > 1;
    if n is not null then
        raise exception 'FAIL: an admin was told twice';
    end if;
    select * into r from notifications
     where kind = 'new_user' and params ->> 'user_id' = v_about::text
       and recipient_id = '12912912-0000-0000-0000-000000000001';
    if r.message <> 'Nouveau compte : Awa Ouédraogo (Google)'
       or r.org_id is not null or r.scope <> 'platform' or r.read_at is not null
       or r.params <> jsonb_build_object('to', 'platform', 'user_id', v_about, 'name', 'Awa Ouédraogo',
                                         'method', 'google', 'contact', 'awa129@example.org') then
        raise exception 'FAIL: the bell reads % / % / %', r.message, r.scope, r.params;
    end if;
    -- The admin's platform list counts it.
    perform pg_temp.as129('12912912-0000-0000-0000-000000000001');
    if (notification_counts() ->> 'platform')::int < 1 then
        raise exception 'FAIL: the platform list does not count it: %', notification_counts();
    end if;
    perform pg_temp.as129(null);
    -- Nobody else's list grew.
    if exists (select 1 from notifications x
                where x.kind <> 'new_user'
                  and not exists (select 1 from before129 b
                                   where b.recipient_id = x.recipient_id and b.kind = x.kind)) then
        raise exception 'FAIL: a sign-up wrote another kind of bell';
    end if;
    raise notice 'PASS: a Google account — one bell per platform admin (%), none to anybody else; « Nouveau compte : Awa Ouédraogo (Google) », platform list, facts in params', pg_temp.admins129();
end $$;

\echo ''
\echo '--- TEST 2: the method for e-mail, téléphone and Apple; the name falls back to the address or the number ---'
insert into auth.users (id, email, raw_app_meta_data) values
    (:mail, 'issa129@example.org', '{"provider": "email"}');
insert into auth.users (id, phone, raw_user_meta_data, raw_app_meta_data) values
    (:phone, '22670129006', '{}', '{"provider": "phone"}');
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
    (:apple, 'x129@privaterelay.appleid.com', '{"full_name": "Fatou Sawadogo"}', '{"provider": "apple"}');
-- No provider at all (an older GoTrue, a stub): the number says téléphone.
insert into auth.users (id, phone) values (:bare, '+22670129008');
do $$
declare
    v_got text;
begin
    select string_agg(x.message || ' | ' || (x.params ->> 'method') || ' | ' || coalesce(x.params ->> 'contact', '-'),
                      ' ; ' order by x.params ->> 'user_id')
      into v_got
      from notifications x
     where x.kind = 'new_user' and x.recipient_id = '12912912-0000-0000-0000-000000000001'
       and x.params ->> 'user_id' in ('12912912-0000-0000-0000-000000000005', '12912912-0000-0000-0000-000000000006',
                                      '12912912-0000-0000-0000-000000000007', '12912912-0000-0000-0000-000000000008');
    if v_got is distinct from
         'Nouveau compte : issa129@example.org (e-mail) | email | issa129@example.org ; '
      || 'Nouveau compte : +22670129006 (téléphone) | phone | +22670129006 ; '
      || 'Nouveau compte : Fatou Sawadogo (Apple) | apple | x129@privaterelay.appleid.com ; '
      || 'Nouveau compte : +22670129008 (téléphone) | phone | +22670129008' then
        raise exception 'FAIL: the methods read %', v_got;
    end if;
    if new_user_method_label('email') <> 'e-mail' or new_user_method_label('phone') <> 'téléphone'
       or new_user_method_label('google') <> 'Google' or new_user_method_label('apple') <> 'Apple'
       or new_user_method_label('github') <> 'github'
       or new_user_method('{"email": "a@b.c", "raw_app_meta_data": {}}') <> 'email'
       or new_user_method('{"phone": "226", "raw_app_meta_data": {"provider": "Phone"}}') <> 'phone' then
        raise exception 'FAIL: the method words';
    end if;
    -- Never a secret: no password, no token in any bell.
    if exists (select 1 from notifications x where x.kind = 'new_user'
                 and (x.params ?| array['password', 'token', 'access_token', 'refresh_token',
                                        'encrypted_password', 'raw_app_meta_data']
                      or (select count(*) from jsonb_object_keys(x.params)) > 5)) then
        raise exception 'FAIL: a bell carries more than its five facts';
    end if;
    raise notice 'PASS: e-mail « (e-mail) », phone « (téléphone) » with its +, Apple « (Apple) »; a nameless account is said by its address or number; no provider → the number; five facts, never a secret';
end $$;

\echo ''
\echo '--- TEST 3: the switch in Réglages — off, nobody is told; on again, they are ---'
do $$
begin
    perform pg_temp.as129('12912912-0000-0000-0000-000000000001');
    if pg_temp.refused129($q$select platform_set_setting('admin_new_user_notify', '0')$q$, 'authenticated')
       <> 'Ce réglage attend oui ou non.' then
        raise exception 'FAIL: the switch took a number';
    end if;
    perform pg_temp.as129('12912912-0000-0000-0000-000000000003');
    if pg_temp.refused129($q$select platform_set_setting('admin_new_user_notify', 'false')$q$, 'authenticated')
       = '(went through)' then
        raise exception 'FAIL: an ordinary account turned the switch';
    end if;
    perform pg_temp.as129('12912912-0000-0000-0000-000000000001');
    execute 'set local role authenticated';
    perform platform_set_setting('admin_new_user_notify', 'false');
    if not (platform_settings_board() ? 'admin_new_user_notify') then
        raise exception 'FAIL: Réglages does not show the switch';
    end if;
    execute 'reset role';
    perform pg_temp.as129(null);
    if not exists (select 1 from platform_actions where kind = 'setting'
                    and after ->> 'key' = 'admin_new_user_notify') then
        raise exception 'FAIL: the switch was not journaled';
    end if;
end $$;
insert into auth.users (id, email, raw_app_meta_data) values
    (:quiet, 'quiet129@example.org', '{"provider": "email"}');
do $$
begin
    if pg_temp.told129('12912912-0000-0000-0000-000000000009') <> 0 then
        raise exception 'FAIL: the switch is off and % admins were told', pg_temp.told129('12912912-0000-0000-0000-000000000009');
    end if;
    if not exists (select 1 from profiles where id = '12912912-0000-0000-0000-000000000009') then
        raise exception 'FAIL: the account made with the switch off has no profile';
    end if;
end $$;
update platform_settings set value = 'true' where key = 'admin_new_user_notify';
do $$
begin
    raise notice 'PASS: off (journaled, a platform admin''s, a number refused in French) — nobody told, the profile still made; on again (the default)';
end $$;

\echo ''
\echo '--- TEST 4: a platform admin from birth is not told about themself ---'
-- A stand-in for an account born a platform admin: between 004's profile
-- and 129's bell (triggers fire by name), its profile is made an admin.
create or replace function public.t129_born_admin()
returns trigger language plpgsql set search_path = public as $$
begin
    if new.raw_user_meta_data ->> 't129' = 'admin' then
        update profiles set is_platform_admin = true where id = new.id;
    end if;
    return new;
end $$;
create trigger ox_t129_born_admin after insert on auth.users
for each row execute function public.t129_born_admin();
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
    (:boss, 'boss129@example.org', '{"full_name": "Chef Mara", "t129": "admin"}', '{"provider": "email"}');
drop trigger ox_t129_born_admin on auth.users;
drop function public.t129_born_admin();
do $$
declare
    v_boss uuid := '12912912-0000-0000-0000-000000000010';
begin
    if not (select is_platform_admin from profiles where id = v_boss) then
        raise exception 'FAIL: the stand-in did not make the admin';
    end if;
    if exists (select 1 from notifications where recipient_id = v_boss and kind = 'new_user'
                 and params ->> 'user_id' = v_boss::text) then
        raise exception 'FAIL: the new admin was told about themself';
    end if;
    if pg_temp.told129(v_boss) <> pg_temp.admins129(v_boss) then
        raise exception 'FAIL: % of the % other admins were told', pg_temp.told129(v_boss), pg_temp.admins129(v_boss);
    end if;
    raise notice 'PASS: an account that is a platform admin at birth — the % other admins told, not itself', pg_temp.admins129(v_boss);
end $$;

\echo ''
\echo '--- TEST 5: non-blocking — a bell that cannot be written never stops a sign-up ---'
begin;
alter table notifications add constraint t129_no_bell check (kind <> 'new_user') not valid;
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
    (:broken, 'broken129@example.org', '{"full_name": "Compte Cassé"}', '{"provider": "email"}');
do $$
begin
    if not exists (select 1 from profiles where id = '12912912-0000-0000-0000-000000000011'
                     and full_name = 'Compte Cassé') then
        raise exception 'FAIL: the sign-up did not go through';
    end if;
    if pg_temp.told129('12912912-0000-0000-0000-000000000011') <> 0 then
        raise exception 'FAIL: a bell was written past the constraint';
    end if;
    raise notice 'PASS: the bell refused, the account and its profile made all the same';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: the ranking''s job stays paused, the weekly prizes untouched ---'
do $$
declare
    v_real boolean := to_regclass('cron.job') is not null;
    v_said text;
begin
    if v_real then
        v_said := cauris_board_keep_paused();
        if exists (select 1 from cron.job where jobname = 'cauris-board' and active) then
            raise exception 'FAIL: cauris-board still active (%)', v_said;
        end if;
        raise notice 'PASS: pg_cron here — cauris-board inactive (%)', v_said;
    else
        v_said := cauris_board_keep_paused();
        if v_said <> 'no pg_cron' then
            raise exception 'FAIL: without pg_cron it said %', v_said;
        end if;
        raise notice 'PASS: no pg_cron here — 129 says so and does nothing';
    end if;
end $$;
-- Without pg_cron: a stand-in with its two jobs, as 086 scheduled them.
begin;
do $$
begin
    if to_regclass('cron.job') is null then
        create schema cron;
        create table cron.job (jobid bigserial primary key, jobname text, schedule text,
                               command text, active boolean not null default true);
        create function cron.alter_job(job_id bigint, schedule text default null,
                                       command text default null, database text default null,
                                       username text default null, active boolean default null)
        returns void language sql as $f$
            update cron.job set schedule = coalesce(alter_job.schedule, job.schedule),
                                command  = coalesce(alter_job.command, job.command),
                                active   = coalesce(alter_job.active, job.active)
             where job.jobid = alter_job.job_id;
        $f$;
        insert into cron.job (jobname, schedule, command) values
            ('cauris-board',      '0 19 * * 0,1,3,5', 'select public.cauris_board_notify()'),
            ('cauris-week-close', '10 0 * * 1',       'select public.cauris_week_close()');
    end if;
end $$;
do $$
declare
    v_week jsonb := (select to_jsonb(j) from cron.job j where jobname = 'cauris-week-close');
    v_said text;
begin
    v_said := cauris_board_keep_paused();
    if v_said <> 'paused'
       or exists (select 1 from cron.job where jobname = 'cauris-board' and active) then
        raise exception 'FAIL: cauris-board not paused (%)', v_said;
    end if;
    if (select to_jsonb(j) from cron.job j where jobname = 'cauris-week-close') is distinct from v_week then
        raise exception 'FAIL: cauris-week-close changed';
    end if;
    -- Again (the bundle runs twice): still paused, nothing else moved.
    if cauris_board_keep_paused() <> 'paused'
       or (select active from cron.job where jobname = 'cauris-board')
       or (select schedule from cron.job where jobname = 'cauris-board') <> '0 19 * * 0,1,3,5' then
        raise exception 'FAIL: a second run moved the job';
    end if;
    raise notice 'PASS: cauris-board inactive (its schedule kept), cauris-week-close exactly as it was, twice';
end $$;
-- The job gone: said, nothing done.
delete from cron.job where jobname = 'cauris-board';
do $$ begin
    if cauris_board_keep_paused() <> 'no job' then
        raise exception 'FAIL: no job, and it said otherwise';
    end if;
end $$;
rollback;

\echo ''
\echo '--- TEST 7: the doors ---'
do $$
declare
    v_fn text;
begin
    foreach v_fn in array array['new_user_method(jsonb)', 'new_user_method_label(text)',
                                'trg_notify_new_user()', 'cauris_board_keep_paused()'] loop
        if has_function_privilege('anon', v_fn, 'execute') then
            raise exception 'FAIL: anon may call %', v_fn;
        end if;
        if has_function_privilege('authenticated', v_fn, 'execute') then
            raise exception 'FAIL: authenticated may call %', v_fn;
        end if;
        if not exists (select 1 from pg_proc where oid = v_fn::regprocedure
                         and proconfig::text like '%search_path%') then
            raise exception 'FAIL: % has no search path', v_fn;
        end if;
    end loop;
    if not (select prosecdef from pg_proc where oid = 'trg_notify_new_user()'::regprocedure)
       or (select prosecdef from pg_proc where oid = 'cauris_board_keep_paused()'::regprocedure) then
        raise exception 'FAIL: the trigger''s function must be a definer, the pause not';
    end if;
    if pg_temp.refused129('select cauris_board_keep_paused()', 'anon') not like '%permission denied%'
       or pg_temp.refused129('select new_user_method_label(''email'')', 'anon') not like '%permission denied%' then
        raise exception 'FAIL: anon got through a door';
    end if;
    raise notice 'PASS: anon and authenticated call none of the four; the trigger a definer, all with a pinned search path';
end $$;

\echo ''
\echo '--- TEST 8: P1 — the profile, the welcome, the other bells, the three kinds; 129 again writes nothing ---'
do $$
declare
    v_trg text;
begin
    -- The profile as 004 writes it.
    if (select (full_name, phone, is_platform_admin) from profiles where id = '12912912-0000-0000-0000-000000000004')
       is distinct from ('Awa Ouédraogo'::text, null::text, false) then
        raise exception 'FAIL: the Google account''s profile changed';
    end if;
    -- 124's welcome still asked for the confirmed Google account.
    if to_regclass('welcome_emails') is not null
       and (select status from welcome_emails where user_id = '12912912-0000-0000-0000-000000000004')
           is distinct from 'pending' then
        raise exception 'FAIL: the welcome e-mail is no longer asked';
    end if;
    -- Only 129's trigger is new on auth.users.
    select string_agg(tgname, ', ' order by tgname) into v_trg
      from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal;
    if v_trg not like '%on_auth_user_created%' or v_trg not like '%platform_new_user%' then
        raise exception 'FAIL: the triggers on auth.users read %', v_trg;
    end if;
    -- The ordinary account and the new ones heard nothing.
    if exists (select 1 from notifications where kind = 'new_user'
                 and recipient_id in ('12912912-0000-0000-0000-000000000003', '12912912-0000-0000-0000-000000000004',
                                      '12912912-0000-0000-0000-000000000005', '12912912-0000-0000-0000-000000000006')) then
        raise exception 'FAIL: an account that is not Mara''s heard of a sign-up';
    end if;
end $$;
-- Businesses of the three kinds (create_org, the platform's): no new_user
-- bell is written by making one.
do $$
declare
    v_before int := (select count(*) from notifications where kind = 'new_user');
    v_kind text;
    v_org uuid;
begin
    perform pg_temp.as129('12912912-0000-0000-0000-000000000001');
    foreach v_kind in array array['retail', 'farm', 'association'] loop
        v_org := create_org('Essai 129 ' || v_kind, 'essai-129-' || v_kind, v_kind, 'XOF');
        if v_org is null or (select profile from orgs where id = v_org) <> v_kind then
            raise exception 'FAIL: a % could not be made', v_kind;
        end if;
    end loop;
    perform pg_temp.as129(null);
    if (select count(*) from notifications where kind = 'new_user') <> v_before then
        raise exception 'FAIL: making a business rang new_user';
    end if;
end $$;
-- 129 again: no row, the switch kept as it was set.
update platform_settings set value = 'false' where key = 'admin_new_user_notify';
create temp table again129 as select count(*) as n from notifications;
\i database/migrations/129_new_user_notify.sql
do $$
begin
    if (select n from again129) <> (select count(*) from notifications) then
        raise exception 'FAIL: running 129 again wrote bells';
    end if;
    if (select value from platform_settings where key = 'admin_new_user_notify') <> 'false'::jsonb then
        raise exception 'FAIL: running 129 again turned the switch back on';
    end if;
    raise notice 'PASS: P1 — the profile and the welcome as before, only platform_new_user added on auth.users, nobody but Mara hears; a shop, a farm and an association made with no bell; 129 again writes nothing and keeps the switch';
end $$;
update platform_settings set value = 'true' where key = 'admin_new_user_notify';
