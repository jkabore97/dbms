-- ============================================================
-- test_batch135.sql — « Continuer avec Apple » on the website, behind its
-- switch (135, batch 139).
--
-- The claims:
--   * apple_web_signin is seeded off; sign_in_options() then answers
--     {apple_web: false} to anon;
--   * a platform admin turns the switch on through platform_set_setting
--     (journaled; a number refused in French; an ordinary account
--     refused) and anon then reads {apple_web: true}; nothing else of
--     platform_settings is in the answer;
--   * sign_in_options() is a definer with its search path pinned, open to
--     anon and authenticated, closed to PUBLIC;
--   * running 135 twice changes nothing (the switch stays on).
-- Shop, farm and association alike: nothing here is a business's.
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
-- Earlier suites hand the app's roles every function: 135 again, so what
-- follows tests its own grants.
\i database/migrations/135_apple_web_signin.sql

\set mara  '''13513513-0000-0000-0000-000000000001'''
\set plain '''13513513-0000-0000-0000-000000000002'''
insert into auth.users (id, phone, raw_user_meta_data) values
    (:mara,  '+22613500001', '{"full_name": "Mara"}'),
    (:plain, '+22613500002', '{"full_name": "Client"}');
update profiles set is_platform_admin = true where id = :mara;

create or replace function pg_temp.refused135(p_sql text, p_role text)
returns text
language plpgsql
as $$
begin
    execute format('set local role %I', p_role);
    execute p_sql;
    execute 'reset role';
    return '(went through)';
exception when others then
    execute 'reset role';
    return sqlerrm;
end;
$$;

\echo ''
\echo '--- TEST 1: seeded off; anon reads « off » and nothing else ---'
do $$
declare r jsonb;
begin
    if (select value from platform_settings where key = 'apple_web_signin') <> 'false'::jsonb then
        raise exception 'FAIL: apple_web_signin is not seeded off';
    end if;
    execute 'set local role anon';
    r := sign_in_options();
    execute 'reset role';
    if r <> '{"apple_web": false}'::jsonb then
        raise exception 'FAIL: anon read % with the switch off', r;
    end if;
    raise notice 'PASS: seeded off; anon reads {apple_web: false} and nothing else';
end $$;

\echo ''
\echo '--- TEST 2: the switch in Réglages — a platform admin''s, journaled; then anon reads « on » ---'
do $$
declare r jsonb;
begin
    perform set_config('request.jwt.claim.sub', '13513513-0000-0000-0000-000000000002', true);
    if pg_temp.refused135($q$select platform_set_setting('apple_web_signin', 'true')$q$, 'authenticated')
       = '(went through)' then
        raise exception 'FAIL: an ordinary account turned the switch';
    end if;
    perform set_config('request.jwt.claim.sub', '13513513-0000-0000-0000-000000000001', true);
    if pg_temp.refused135($q$select platform_set_setting('apple_web_signin', '1')$q$, 'authenticated')
       <> 'Ce réglage attend oui ou non.' then
        raise exception 'FAIL: the switch took a number';
    end if;
    execute 'set local role authenticated';
    perform platform_set_setting('apple_web_signin', 'true');
    if not (platform_settings_board() ? 'apple_web_signin') then
        raise exception 'FAIL: Réglages does not show the switch';
    end if;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '', true);
    if not exists (select 1 from platform_actions where kind = 'setting'
                    and after ->> 'key' = 'apple_web_signin') then
        raise exception 'FAIL: the switch was not journaled';
    end if;
    execute 'set local role anon';
    r := sign_in_options();
    execute 'reset role';
    if r <> '{"apple_web": true}'::jsonb then
        raise exception 'FAIL: anon read % with the switch on', r;
    end if;
    raise notice 'PASS: an ordinary account refused, a number refused in French, the admin''s change journaled; anon reads {apple_web: true}';
end $$;

\echo ''
\echo '--- TEST 3: the doors ---'
do $$
declare v_bad text;
begin
    select string_agg(f || ' ' || r, ', ') into v_bad
      from (values ('sign_in_options()', 'anon', true),
                   ('sign_in_options()', 'authenticated', true)) t(f, r, ok)
     where has_function_privilege(r, f, 'execute') <> ok;
    if v_bad is not null then
        raise exception 'FAIL: the doors are wrong for %', v_bad;
    end if;
    if has_function_privilege('public', 'sign_in_options()', 'execute') then
        raise exception 'FAIL: PUBLIC may call sign_in_options()';
    end if;
    if not exists (select 1 from pg_proc where proname = 'sign_in_options' and prosecdef
                     and proconfig::text like '%search_path=public%') then
        raise exception 'FAIL: sign_in_options() is not a definer with its path pinned';
    end if;
    raise notice 'PASS: open to anon and authenticated, closed to PUBLIC; a definer, its path pinned';
end $$;

\echo ''
\echo '--- TEST 4: 135 twice changes nothing ---'
\i database/migrations/135_apple_web_signin.sql
do $$
begin
    if (select value from platform_settings where key = 'apple_web_signin') <> 'true'::jsonb then
        raise exception 'FAIL: running 135 again turned the switch off';
    end if;
    raise notice 'PASS: run twice, the switch kept';
end $$;

-- Left as found for the suites after this one.
update platform_settings set value = 'false' where key = 'apple_web_signin';
