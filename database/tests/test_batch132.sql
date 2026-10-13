-- ============================================================
-- test_batch132.sql — « Aujourd'hui »'s new accounts and today's orders
-- (132). Phone block 132.
--
-- The claims:
--   * platform_today_counts() counts the accounts made in the last seven
--     days and the seven before, apart; the orders placed today (since
--     Ouagadougou's midnight) and on the same day last week up to the
--     same hour — yesterday's and last week's later hours are not counted;
--   * it answers a platform admin only: an owner and a plain account get
--     null; anon and PUBLIC may not call it; it is a definer function
--     with its search path pinned;
--   * running 132 twice changes nothing.
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
-- Earlier suites hand the app's roles every function (063's re-run among
-- them): 132 again, twice, so what follows tests its own grants.
\i database/migrations/132_admin_today.sql
\i database/migrations/132_admin_today.sql

\set mara  '''13213213-0000-0000-0000-000000000001'''
\set owner '''13213213-0000-0000-0000-000000000002'''
\set buyer '''13213213-0000-0000-0000-000000000003'''
\set shop  '''13200000-0000-0000-0000-000000000001'''

insert into auth.users (id, phone, raw_user_meta_data) values
    (:mara,  '+22613200001', '{"full_name": "Mara"}'),
    (:owner, '+22613200002', '{"full_name": "Propriétaire"}'),
    (:buyer, '+22613200003', '{"full_name": "Cliente"}');
update profiles set is_platform_admin = true where id = :mara;
insert into orgs (id, name, slug, profile, default_currency) values
    (:shop, 'Boutique 132', 'boutique-132', 'retail', 'XOF');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop, :owner, 'owner', 'org', :shop, 'full');

\echo ''
\echo '--- TEST 1: new accounts this week and the week before, apart ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '13213213-0000-0000-0000-000000000001';
create temp table t0 on commit drop as select platform_today_counts() as v;
reset role;
insert into auth.users (id, phone, created_at) values
    ('13213213-0000-0000-0000-000000000011', '+22613200011', now() - interval '1 hour'),
    ('13213213-0000-0000-0000-000000000012', '+22613200012', now() - interval '6 days'),
    ('13213213-0000-0000-0000-000000000013', '+22613200013', now() - interval '8 days'),
    ('13213213-0000-0000-0000-000000000014', '+22613200014', now() - interval '20 days');
set local role authenticated;
set local "request.jwt.claim.sub" = '13213213-0000-0000-0000-000000000001';
do $$
declare a jsonb := (select v from t0); b jsonb := platform_today_counts();
begin
    if a is null or b is null then
        raise exception 'FAIL: the platform admin got no counts';
    end if;
    if (b ->> 'accounts_week')::int - (a ->> 'accounts_week')::int <> 2 then
        raise exception 'FAIL: this week counts % new accounts (want 2)',
            (b ->> 'accounts_week')::int - (a ->> 'accounts_week')::int;
    end if;
    if (b ->> 'accounts_last_week')::int - (a ->> 'accounts_last_week')::int <> 1 then
        raise exception 'FAIL: last week counts % new accounts (want 1; 20 days ago is neither)',
            (b ->> 'accounts_last_week')::int - (a ->> 'accounts_last_week')::int;
    end if;
    raise notice 'PASS: two accounts this week, one the week before, the older one in neither';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: today''s orders, and the same day last week up to this hour ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '13213213-0000-0000-0000-000000000001';
create temp table t0 on commit drop as select platform_today_counts() as v;
reset role;
-- Today: one at midnight's first minute and one now. Last week's same
-- day: one at its first minute (counted), one an hour after now's hour a
-- week ago (not: later in that day than we are in ours). Yesterday's
-- last minute: neither.
insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency, created_at, updated_at)
select :shop, :buyer, 'Awa', s, 'pickup', 500, 'XOF', at, at
  from (values
        ('pending',   (select (v ->> 'day_start')::timestamptz from t0) + interval '1 minute'),
        ('delivered', now()),
        ('delivered', (select (v ->> 'day_start')::timestamptz from t0) - interval '7 days' + interval '1 minute'),
        ('cancelled', now() - interval '7 days' + interval '1 hour'),
        ('delivered', (select (v ->> 'day_start')::timestamptz from t0) - interval '1 minute')
       ) as x(s, at)
 -- At a minute past midnight, « one hour after now a week ago » may still
 -- be today a week ago, or after it: either way it is not counted.
 where at <= now();
set local role authenticated;
set local "request.jwt.claim.sub" = '13213213-0000-0000-0000-000000000001';
do $$
declare a jsonb := (select v from t0); b jsonb := platform_today_counts();
        today_start timestamptz := (select (v ->> 'day_start')::timestamptz from t0);
        want_today int := case when today_start + interval '1 minute' <= now() then 2 else 1 end;
begin
    if today_start <> (date_trunc('day', now() at time zone 'Africa/Ouagadougou')
                       at time zone 'Africa/Ouagadougou') then
        raise exception 'FAIL: the day does not start at midnight in Ouagadougou: %', today_start;
    end if;
    if (b ->> 'orders_today')::int - (a ->> 'orders_today')::int <> want_today then
        raise exception 'FAIL: today counts % orders (want %)',
            (b ->> 'orders_today')::int - (a ->> 'orders_today')::int, want_today;
    end if;
    if (b ->> 'orders_last_week')::int - (a ->> 'orders_last_week')::int <> 1 then
        raise exception 'FAIL: the same day last week counts % orders (want 1: its later hours are not ours yet)',
            (b ->> 'orders_last_week')::int - (a ->> 'orders_last_week')::int;
    end if;
    raise notice 'PASS: today''s orders since Ouagadougou''s midnight; last week''s same day up to this hour only; yesterday in neither';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: the platform''s only; closed to anon and PUBLIC; definer, path pinned ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '13213213-0000-0000-0000-000000000002';
do $$ begin
    if platform_today_counts() is not null then
        raise exception 'FAIL: an owner reads the platform''s counts';
    end if;
end $$;
set local "request.jwt.claim.sub" = '13213213-0000-0000-0000-000000000003';
do $$ begin
    if platform_today_counts() is not null then
        raise exception 'FAIL: a plain account reads the platform''s counts';
    end if;
end $$;
reset role;
do $$
declare p record;
begin
    if has_function_privilege('anon', 'public.platform_today_counts()', 'execute') then
        raise exception 'FAIL: anon may call platform_today_counts';
    end if;
    if exists (select 1 from information_schema.routine_privileges
                where routine_name = 'platform_today_counts' and grantee = 'PUBLIC') then
        raise exception 'FAIL: PUBLIC may call platform_today_counts';
    end if;
    if not has_function_privilege('authenticated', 'public.platform_today_counts()', 'execute') then
        raise exception 'FAIL: a signed-in admin may not call platform_today_counts';
    end if;
    select prosecdef, proconfig into p from pg_proc
     where oid = 'public.platform_today_counts()'::regprocedure;
    if not p.prosecdef or not ('search_path=public, auth' = any (p.proconfig)) then
        raise exception 'FAIL: platform_today_counts is not a definer with its path pinned: % %',
            p.prosecdef, p.proconfig;
    end if;
    raise notice 'PASS: an owner and a plain account get null; anon and PUBLIC may not call it; definer, search path pinned';
end $$;
set local role anon;
do $$ begin
    perform platform_today_counts();
    raise exception 'FAIL: anon called platform_today_counts';
exception when insufficient_privilege then
    raise notice 'PASS: anon is refused at the door';
end $$;
rollback;

\echo '=== test_batch132.sql: all checks passed ==='
