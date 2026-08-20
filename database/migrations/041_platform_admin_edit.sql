-- ============================================================
-- 041_platform_admin_edit.sql — a platform admin can edit again.
--
-- THE BUG. is_org_admin(), is_org_member() and can_write_org() (010) all treat
-- a platform admin as full-access — they carry an explicit is_platform_admin
-- clause. But two guards written later were never given the same clause:
--   * feature_access() (031) returns 'hidden' when the caller has no
--     membership in the org — which a platform admin managing a business from
--     the console does not.
--   * has_full_visibility() (006) is likewise membership-only.
--
-- The products UPDATE policy (031) is `can_write_org AND feature_access =
-- 'edit'`. For a platform admin that is `true AND 'hidden'` → the row does not
-- match, and PostgREST reports a successful UPDATE of zero rows. The app sees
-- no error and reloads the unchanged product: "editing an article does
-- nothing." The same gap silently blocks a platform admin from adding a credit,
-- running production, or recording a repayment (the trg_guard_feature_edit
-- triggers), and refuses them a business's owner-analytics and report line
-- items (has_full_visibility).
--
-- THE FIX. Give both functions the platform-admin clause the other guards have,
-- so full access is decided the same way everywhere. Each body is the LATEST
-- version of the function verbatim — feature_access from 032, has_full_visibility
-- from 006 — apart from that one added branch. Rebuilding from an older copy
-- would silently revert whatever landed in between; 032 hardened the anonymous
-- answer to 'hidden' and made 'reports' default to 'view', and both stay.
-- ============================================================

-- feature_access: a platform admin edits everything, as they can already read
-- and administer everything. This is 032 verbatim with one branch added.
create or replace function feature_access(p_org_id uuid, p_feature text)
returns text
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_roles  text[];
    v_tier   text;
    v_access text;
begin
    -- No session: fail closed, as 032 made it. A permission function's answer
    -- for "nobody signed in" must never be its most-open one.
    if auth.uid() is null then
        return 'hidden';
    end if;

    -- The clause is_org_admin/can_write_org already carry, missing here until
    -- now: the platform runs the platform. After the anon check, so a session
    -- is still required to reach it.
    if exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return 'edit';
    end if;

    select array_agg(distinct role) into v_roles
      from memberships
     where org_id = p_org_id and user_id = auth.uid();

    if v_roles is null then
        return 'hidden';
    end if;
    if v_roles && array['owner', 'super_admin', 'admin'] then
        return 'edit';
    end if;

    v_tier := case
        when v_roles && array['manager', 'supervisor'] then 'supervisor'
        else 'employee'
    end;

    select access into v_access
      from org_feature_rules
     where org_id = p_org_id and tier = v_tier and feature = p_feature;

    -- No rule set: full access by default, so a business that never touched
    -- the dial works exactly as before 031 — except reports, which 032
    -- defaults to 'view'. Keep both; reverting either is a silent change.
    return coalesce(v_access,
        case when p_feature = 'reports' then 'view' else 'edit' end);
end;
$$;

-- has_full_visibility: a platform admin sees every figure — the same posture as
-- is_org_member, which they already pass.
create or replace function has_full_visibility(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
        or exists (
            select 1 from memberships m
            where m.user_id = auth.uid()
              and m.org_id = p_org_id
              and m.visibility = 'full'
        );
$$;

notify pgrst, 'reload schema';
