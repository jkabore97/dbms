-- ============================================================
-- 044_account_management.sql — an admin manages the people in their business.
--
-- The People screen could invite and remove. This adds the rest of a real
-- account manager: change someone's responsibility (their role), and the two
-- authorisation checks a separate service-role Worker forwards here before it
-- resets a password or deletes an account. The Worker holds the service-role
-- key; it never decides who may use it — it asks Postgres, as the caller,
-- exactly the way the uploads Worker asks "are you a member of this org".
--
-- Owners are protected throughout: an owner's role cannot be reassigned and an
-- owner cannot be deleted, because either would leave a business no one can
-- administer. Transferring ownership or deleting the business come first.
-- ============================================================

-- Change a member's responsibility. Admin of that member's org only (which
-- includes a platform admin, via is_org_admin). Not the owner — reassigning the
-- owner's role is how a business loses its last administrator — and not *to*
-- owner, since minting a second owner is a transfer, not a role change.
create or replace function set_membership_role(
    p_membership_id uuid,
    p_role          role_name
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org  uuid;
    v_role role_name;
begin
    if auth.uid() is null then
        raise exception 'set_membership_role() needs a signed-in caller';
    end if;

    select org_id, role into v_org, v_role
    from memberships where id = p_membership_id;
    if v_org is null then
        raise exception 'No such membership';
    end if;

    if not is_org_admin(v_org) then
        raise exception 'Only an owner or admin can change a role';
    end if;
    if v_role = 'owner' then
        raise exception 'The owner''s role cannot be changed here';
    end if;
    if p_role = 'owner' then
        raise exception 'Use a transfer of ownership, not a role change';
    end if;

    update memberships set role = p_role where id = p_membership_id;
end;
$$;

-- Whether the caller may reset this user's password: a platform admin, or an
-- admin of some business the target belongs to. Read by the account Worker,
-- as the caller, before it uses the service-role key.
create or replace function manages_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        exists (select 1 from profiles
                where id = auth.uid() and is_platform_admin)
        or exists (
            select 1
            from memberships me
            join memberships them on them.org_id = me.org_id
            where me.user_id = auth.uid()
              and me.role in ('owner', 'super_admin', 'admin')
              and them.user_id = p_user_id
        );
$$;

-- Whether the caller may delete this user's account outright. Stricter than
-- managing them, because deletion is global — it removes the person from every
-- business, not only the caller's:
--
--   * an owner of any business is never deletable here (the business would be
--     orphaned); transfer or delete the business first;
--   * a platform admin may delete anyone else;
--   * a business admin may delete someone only if every business that person
--     belongs to is one this caller administers — so a deletion can never
--     reach into a business the caller has no authority over.
create or replace function can_delete_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        p_user_id <> auth.uid()
        and not exists (
            select 1 from memberships where user_id = p_user_id and role = 'owner'
        )
        and (
            exists (select 1 from profiles
                    where id = auth.uid() and is_platform_admin)
            or (
                manages_user(p_user_id)
                and not exists (
                    select 1 from memberships t
                    where t.user_id = p_user_id
                      and not is_org_admin(t.org_id)
                )
            )
        );
$$;

-- ------------------------------------------------------------
-- GRANTS
-- ------------------------------------------------------------
revoke execute on function set_membership_role(uuid, role_name) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_membership_role(uuid, role_name) to authenticated;
        grant execute on function manages_user(uuid)    to authenticated;
        grant execute on function can_delete_user(uuid) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
