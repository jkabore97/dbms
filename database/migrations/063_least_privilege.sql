-- ============================================================
-- 063_least_privilege.sql — the street may look, nobody else may knock.
--
-- Supabase grants EXECUTE on every new function to anon, authenticated and
-- service_role by default (pg_default_acl for postgres in public), and
-- Postgres itself grants it to PUBLIC. So every SECURITY DEFINER function
-- this project ever wrote — shop_orders, courier_mark, delete_org, all 150
-- of them — has been callable with the public key and no session. Each
-- one checks auth.uid() and refuses a stranger, so nothing leaked; but a
-- refusal inside the function is one line of plpgsql away from a leak,
-- and the linter (0028) is right to flag it. Defence in depth: the
-- database should refuse at the door, before the function runs.
--
-- Two moves, both dynamic so they cover what exists and re-run clean:
--
--   1. Every SECURITY DEFINER function in public loses EXECUTE for PUBLIC
--      and anon, and keeps it explicitly for authenticated and
--      service_role — except the street: the storefront readers, the
--      search, the delivery quote, the photo check the uploads Worker
--      makes with the public key, and the invitation preview a person
--      reads before they have an account. Those are the whole public
--      surface, listed by name below; place_order is not among them
--      because it already requires a session (055).
--
--   2. Default privileges change so the next function is born without
--      anon or PUBLIC execute. A future migration grants what it means to
--      grant, as this project's already do.
--
-- One family is deliberately left open besides the street: the handful of
-- helpers RLS policies call (is_org_member, is_org_admin, can_write_org,
-- has_full_visibility, feature_access, my_org_ids). A policy runs its
-- expression as the caller, so those must be executable by anon for a
-- stranger's select to come back empty instead of erroring. They are
-- found from pg_policy at run time, not listed by hand.
--
-- And the search_path linter (0011): the 28 SECURITY INVOKER helpers
-- written without `set search_path` get `public`, the same setting every
-- definer function here already carries. A function whose search path
-- follows the caller's can be pointed at a shadowing schema; pinning it
-- costs nothing. Extension-owned functions are left alone.
--
-- Roles are guarded because the test cluster creates anon and
-- authenticated lazily, per suite; on Supabase all three exist.
-- ============================================================

do $$
declare
    -- The public surface: what a stranger with the publishable key may run.
    v_street constant text[] := array[
        'storefront',
        'storefront_products',
        'storefront_featured',
        'storefront_directory',
        'storefront_open',
        'storefront_photo_allowed',
        'search_products',
        'delivery_quote',
        'invitation_preview'
    ];
    -- The functions RLS itself calls. A policy expression runs as the
    -- caller, so is_org_member() and its kin must stay executable by every
    -- role a policy can apply to — anon included: a stranger reading orgs
    -- gets an empty answer through the policy, and a revoked helper would
    -- turn that into "permission denied for function is_org_admin" on a
    -- plain select. Found from the policies rather than listed, so a
    -- helper added later is covered the day a policy uses it.
    v_policy_fns text[] := (
        with refs as (
            select pg_get_expr(polqual, polrelid) as e from pg_policy
            union all
            select pg_get_expr(polwithcheck, polrelid) from pg_policy
            union all
            select pg_get_viewdef(c.oid)
              from pg_class c join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relkind = 'v'
        )
        select coalesce(array_agg(distinct m[1]), '{}')
          from refs, regexp_matches(e, '([a-z_]+)\(', 'g') m
    );
    v_has_anon    boolean := exists (select 1 from pg_roles where rolname = 'anon');
    v_has_auth    boolean := exists (select 1 from pg_roles where rolname = 'authenticated');
    v_has_service boolean := exists (select 1 from pg_roles where rolname = 'service_role');
    r record;
    v_sig text;
begin
    for r in
        select p.oid, p.proname
          from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.prokind = 'f'
           and p.prosecdef
           and not exists (select 1 from pg_depend d
                            where d.objid = p.oid and d.deptype = 'e')
    loop
        v_sig := r.oid::regprocedure::text;
        if r.proname = any (v_street) or r.proname = any (v_policy_fns) then
            -- The street and the policy helpers stay open, and are said so
            -- here rather than left to the grants of 052–061: on a cluster
            -- where anon was created after those ran (the test cluster),
            -- this is what opens them.
            if v_has_anon then
                execute format('grant execute on function %s to anon', v_sig);
            end if;
            if v_has_auth then
                execute format('grant execute on function %s to authenticated', v_sig);
            end if;
            continue;
        end if;
        execute format('revoke execute on function %s from public', v_sig);
        if v_has_anon then
            execute format('revoke execute on function %s from anon', v_sig);
        end if;
        if v_has_auth then
            execute format('grant execute on function %s to authenticated', v_sig);
        end if;
        if v_has_service then
            execute format('grant execute on function %s to service_role', v_sig);
        end if;
    end loop;

    -- push_targets and remove_push_target (060) are service-role only and
    -- must stay that way: the loop above re-granted authenticated to every
    -- definer function, so take it back from these two.
    if v_has_auth then
        revoke execute on function push_targets(uuid) from authenticated;
        revoke execute on function remove_push_target(text) from authenticated;
    end if;

    -- The next function is born closed to the street. PUBLIC's execute
    -- comes from Postgres's built-in defaults, and a schema-scoped entry
    -- can only add to those, never take from them — so that one revoke is
    -- global (for this role, every schema); the rest stay in public.
    alter default privileges revoke execute on functions from public;
    if v_has_anon then
        alter default privileges in schema public revoke execute on functions from anon;
    end if;
    if v_has_auth then
        alter default privileges in schema public grant execute on functions to authenticated;
    end if;
    if v_has_service then
        alter default privileges in schema public grant execute on functions to service_role;
    end if;

    -- A pinned search path for every project function that lacked one.
    for r in
        select p.oid
          from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.prokind = 'f'
           and not exists (select 1 from pg_depend d
                            where d.objid = p.oid and d.deptype = 'e')
           and not coalesce((select true from unnest(p.proconfig) c
                              where c like 'search_path=%'), false)
    loop
        execute format('alter function %s set search_path = public',
                       r.oid::regprocedure::text);
    end loop;
end $$;

notify pgrst, 'reload schema';
