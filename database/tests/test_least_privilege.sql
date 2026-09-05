-- ============================================================
-- test_least_privilege.sql — the street may look, nobody else may knock (063).
-- Phone block 35.
--
-- The claims: a stranger with the public key can still read the street
-- (the directory, a shop, the search, a delivery quote) and nothing else —
-- a call to any other SECURITY DEFINER function is refused by the
-- database itself, before the function runs; a signed-in person keeps
-- every function they had; the two service-role functions stay closed to
-- everyone else; a function created after 063 is born closed to the
-- street; and no project function is left without a pinned search path.
--
-- No preamble grant here on purpose: a blanket "grant execute on all
-- functions to authenticated" would hide what 063 itself grants.
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

-- On Supabase anon and authenticated exist before any migration runs; in
-- this cluster they were just created, after every migration ran with
-- its role guards skipping them. Run 063 again now that they exist — it
-- is written to be re-run — so what follows tests the migration's own
-- grants and revokes, not this file's.
\i database/migrations/063_least_privilege.sql

\echo ''
\echo '--- TEST 1: the street is still open to a stranger ---'
begin;
set local role anon;
do $$
declare v int;
begin
    select count(*) into v from storefront_directory(null, null);
    select count(*) into v from search_products('savon', null, null);
    perform storefront('nulle-part');
    perform delivery_quote('nulle-part', 12.37, -1.52);
    raise notice 'PASS: directory, search, storefront and quote answer a stranger';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: a stranger is refused at the door, not inside ---'
begin;
set local role anon;
do $$
declare v_state text;
begin
    begin
        perform my_orgs();
        raise exception 'FAIL: a stranger ran my_orgs()';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        get stacked diagnostics v_state = returned_sqlstate;
        if v_state <> '42501' then
            raise exception 'FAIL: my_orgs() failed inside the function (%) instead of at the door', v_state;
        end if;
    end;
    begin
        perform courier_earnings();
        raise exception 'FAIL: a stranger ran courier_earnings()';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        get stacked diagnostics v_state = returned_sqlstate;
        if v_state <> '42501' then
            raise exception 'FAIL: courier_earnings() failed inside (%) instead of at the door', v_state;
        end if;
    end;
    raise notice 'PASS: my_orgs() and courier_earnings() are permission denied (42501) to anon';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: the catalogue agrees — outside the street and the policy helpers, nothing is open to anon ---'
do $$
declare v_open text; v_helpers text;
begin
    with refs as (
        select pg_get_expr(polqual, polrelid) as e from pg_policy
        union all select pg_get_expr(polwithcheck, polrelid) from pg_policy
    ), helpers as (
        select distinct m[1] as fn from refs, regexp_matches(e, '([a-z_]+)\(', 'g') m
    )
    select string_agg(p.proname, ', ' order by p.proname),
           (select string_agg(fn, ', ' order by fn) from helpers
             where exists (select 1 from pg_proc q join pg_namespace qn on qn.oid = q.pronamespace
                            where qn.nspname = 'public' and q.proname = helpers.fn))
      into v_open, v_helpers
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
       and p.proname not in ('storefront', 'storefront_products', 'storefront_featured',
                             'storefront_directory', 'storefront_open',
                             'storefront_photo_allowed', 'search_products',
                             'delivery_quote', 'invitation_preview')
       and p.proname not in (select fn from helpers)
       and has_function_privilege('anon', p.oid, 'execute');
    if v_open is not null then
        raise exception 'FAIL: still open to anon: %', v_open;
    end if;
    -- The helpers are a short, known family; a policy calling something
    -- new should be a deliberate change, not a silent widening.
    if v_helpers <> 'can_write_org, feature_access, has_full_visibility, is_org_admin, is_org_member, my_org_ids' then
        raise exception 'FAIL: the policies now call % — check 063 means to open it to anon', v_helpers;
    end if;
    raise notice 'PASS: outside the street and the six policy helpers, every definer function is closed to anon';
end $$;

\echo ''
\echo '--- TEST 4: a signed-in person keeps the door; the service-role pair stays shut ---'
do $$
begin
    if not has_function_privilege('authenticated', 'my_orgs()', 'execute')
       or not has_function_privilege('authenticated', 'shop_orders(uuid)', 'execute')
       or not has_function_privilege('authenticated', 'courier_earnings()', 'execute') then
        raise exception 'FAIL: 063 took a function away from authenticated';
    end if;
    if has_function_privilege('authenticated', 'push_targets(uuid)', 'execute')
       or has_function_privilege('anon', 'push_targets(uuid)', 'execute')
       or has_function_privilege('authenticated', 'remove_push_target(text)', 'execute') then
        raise exception 'FAIL: the push address book is open to an app role';
    end if;
    raise notice 'PASS: authenticated keeps my_orgs/shop_orders/courier_earnings; push_targets stays service-role only';
end $$;

\echo ''
\echo '--- TEST 5: a function born after 063 is closed to the street ---'
drop function if exists public.zz_probe_063();
create function public.zz_probe_063() returns int language sql as 'select 1';
do $$
begin
    if has_function_privilege('anon', 'public.zz_probe_063()', 'execute') then
        raise exception 'FAIL: a new function is still executable by anon';
    end if;
    if not has_function_privilege('authenticated', 'public.zz_probe_063()', 'execute') then
        raise exception 'FAIL: a new function is not executable by authenticated';
    end if;
    raise notice 'PASS: a new function is born closed to anon and open to authenticated';
end $$;
drop function public.zz_probe_063();

\echo ''
\echo '--- TEST 6: every project function carries a pinned search path ---'
do $$
declare v_loose text;
begin
    select string_agg(p.proname, ', ' order by p.proname) into v_loose
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
       and not coalesce((select true from unnest(p.proconfig) c where c like 'search_path=%'), false);
    if v_loose is not null then
        raise exception 'FAIL: no search_path on: %', v_loose;
    end if;
    raise notice 'PASS: every project function has search_path set';
end $$;

\echo ''
\echo '=== test_least_privilege.sql: all checks passed ==='
