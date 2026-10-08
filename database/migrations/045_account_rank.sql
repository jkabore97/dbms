-- ============================================================
-- 045_account_rank.sql — password resets and role changes follow the hierarchy.
--
-- 044 let any admin of a shared business reset any co-member's password and
-- change any non-owner's role. The owner asked for rank, and named the order:
-- super_admin is Kaj's own platform staff and sits above a store's owner; the
-- owner is the top of their own store, above the admins they appoint; an admin
-- reaches the responsables and staff beneath them. So a super_admin reaches an
-- owner and everyone below, an owner reaches the admins and below, an admin the
-- responsables and staff — and no one a peer or someone above them. The
-- platform's own is_platform_admin flag stays above all of this and bypasses
-- it. The same order governs who may reassign whose responsibility.
--
-- The rule is one comparison against a rank ladder. manages_user() is what the
-- account Worker asks before it resets a password, and what can_delete_user()
-- (unchanged) is built on — so a deletion inherits the same ceiling. Bodies are
-- 044 verbatim apart from the rank clause.
-- ============================================================

-- The ladder. Higher manages lower; equal manages neither. super_admin is
-- Kaj's platform staff and sits above a store's owner; the owner is the top of
-- their own store. An unknown role ranks at the bottom, so it can manage no one
-- and is managed by any admin.
create or replace function role_rank(p_role role_name)
returns int
language sql
immutable
as $$
    select case p_role
        when 'super_admin' then 100
        when 'owner'       then 90
        when 'admin'       then 80
        when 'manager'     then 60
        when 'supervisor'  then 50
        when 'approver'    then 40
        when 'employee'    then 30
        when 'observer'    then 20
        else 0
    end;
$$;

-- Whether the caller may reset this user's password: a platform admin, or an
-- admin of a shared business who outranks the target's highest role anywhere.
-- The "highest role anywhere" is deliberate: it stops an admin of a small shop
-- resetting the login of someone who is a super_admin or owner in another
-- business, since the password is one global credential, not a per-org one.
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
            where me.user_id = auth.uid()
              and me.role in ('owner', 'super_admin', 'admin')
              and me.org_id in (
                  select org_id from memberships where user_id = p_user_id
              )
              and role_rank(me.role) > (
                  select coalesce(max(role_rank(t.role)), 0)
                  from memberships t where t.user_id = p_user_id
              )
        );
$$;

-- Change a member's responsibility — now rank-bound. 044's guards stay (admin
-- of the org, never the owner's role, never *to* owner); added: the caller must
-- outrank both the role held and the role assigned, so an admin can shuffle the
-- staff and responsables below them but cannot touch a peer, promote anyone to
-- their own level, or lift themselves. A platform admin, who holds no
-- membership, runs the platform and is exempt from the rank test.
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
    v_org         uuid;
    v_role        role_name;
    v_caller_rank int;
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

    if not exists (select 1 from profiles
                   where id = auth.uid() and is_platform_admin) then
        select coalesce(max(role_rank(m.role)), 0) into v_caller_rank
        from memberships m
        where m.org_id = v_org and m.user_id = auth.uid();

        if v_caller_rank <= role_rank(v_role)
           or v_caller_rank <= role_rank(p_role) then
            raise exception 'You can only assign a responsibility below your own';
        end if;
    end if;

    update memberships set role = p_role where id = p_membership_id;
end;
$$;

notify pgrst, 'reload schema';
