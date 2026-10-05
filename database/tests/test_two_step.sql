-- ============================================================
-- test_two_step.sql — a platform admin passes two steps (077).
-- Phone block 48.
--
-- The claims: the gate lets the street, the worker and an ordinary
-- account through untouched; it refuses a platform admin below aal2
-- everywhere except my_two_step(), and lets them through at aal2;
-- my_two_step() says what to ask; the street can run the hook.
-- ============================================================
\set ON_ERROR_STOP on

\set admin  '''48484848-0000-0000-0000-000000000001'''
\set seller '''48484848-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname='anon') then
        create role anon nologin;
    end if;
end $$;
grant usage on schema public to authenticated, anon;
-- The rig creates the app's roles after the migrations ran, so 077's
-- grants skipped them. On Supabase they exist first; apply 077 again (it is
-- idempotent) so what is checked is what it grants.
\ir ../migrations/077_two_step.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:admin,  '+22648000001', '{"full_name": "Plateforme"}'),
    (:seller, '+22648000002', '{"full_name": "Vendeuse"}');
update profiles set is_platform_admin = true where id = :admin;


\echo ''
\echo '--- TEST 1: the street, the worker and a seller go through ---'
begin;
set local role anon;
select two_step_gate();
reset role;
-- The worker: service role, no user in the token.
select two_step_gate();
set local role authenticated;
set local "request.jwt.claim.sub" = '48484848-0000-0000-0000-000000000002';
set local "request.jwt.claims" = '{"aal": "aal1"}';
set local "request.path" = '/rpc/my_orgs';
select two_step_gate();
do $$ begin
    if (my_two_step() ->> 'required')::boolean then
        raise exception 'FAIL: a seller is held to two steps';
    end if;
    raise notice 'PASS: anon, the worker and a seller at aal1 are not stopped';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: an admin below aal2 is refused, but may ask what to do ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '48484848-0000-0000-0000-000000000001';
set local "request.jwt.claims" = '{"aal": "aal1"}';
set local "request.path" = '/rpc/platform_wave_payments';
do $$ begin
    perform two_step_gate();
    raise exception 'FAIL: an aal1 admin reached the console';
exception when insufficient_privilege then
    if sqlerrm not like 'Validation en deux étapes requise%' then raise; end if;
end $$;
set local "request.path" = 'orgs';
do $$ begin
    perform two_step_gate();
    raise exception 'FAIL: an aal1 admin read a table';
exception when insufficient_privilege then null;
end $$;
-- Both spellings PostgREST has used for the path.
set local "request.path" = '/rpc/my_two_step';
select two_step_gate();
set local "request.path" = 'rpc/my_two_step';
select two_step_gate();
do $$
declare s jsonb := my_two_step();
begin
    if s <> '{"required": true, "enrolled": false, "passed": false}'::jsonb then
        raise exception 'FAIL: my_two_step says %', s;
    end if;
    raise notice 'PASS: refused on tables and functions; my_two_step answers: enrol';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: enrolled and passed, the admin goes through ---'
insert into auth.mfa_factors (user_id, status) values (:admin, 'verified');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '48484848-0000-0000-0000-000000000001';
set local "request.jwt.claims" = '{"aal": "aal1"}';
do $$ begin
    if my_two_step() <> '{"required": true, "enrolled": true, "passed": false}'::jsonb then
        raise exception 'FAIL: an enrolled admin is not asked for the code';
    end if;
end $$;
set local "request.jwt.claims" = '{"aal": "aal2"}';
set local "request.path" = '/rpc/platform_wave_payments';
select two_step_gate();
do $$ begin
    if not (my_two_step() ->> 'passed')::boolean then
        raise exception 'FAIL: an aal2 token is not read as passed';
    end if;
    perform log_security_event('two_step_enabled');
    raise notice 'PASS: at aal2 the admin is through; the event is logged';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the hook is runnable by every role PostgREST uses ---'
do $$ begin
    if not has_function_privilege('anon', 'two_step_gate()', 'execute')
       or not has_function_privilege('authenticated', 'two_step_gate()', 'execute') then
        raise exception 'FAIL: a role cannot run the hook, and every request of it would fail';
    end if;
    if has_function_privilege('anon', 'my_two_step()', 'execute') then
        raise exception 'FAIL: the street can ask my_two_step';
    end if;
    raise notice 'PASS: anon and authenticated run the gate; my_two_step is closed to anon';
end $$;

\echo ''
\echo 'test_two_step: all passed'
