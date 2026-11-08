-- ============================================================
-- 169 — A platform admin adds an existing account to a business.
--
-- The owner: « I want to be able to add a user that already has an
-- account to a business. » Until now the only way in was an invitation
-- code the person had to claim themselves; an existing account cannot be
-- matched on its phone alone (claim_my_invitations only takes accounts
-- made after the invitation).
--
--   * platform_add_member(org, user, role): the account joins the business
--     at once, for the whole business (scope 'org', visibility 'full'), as
--     the role chosen — any role an invitation can give: owner, admin,
--     manager, supervisor, employee, observer, approver; never super_admin.
--     A platform admin only. Refused when the account is already in that
--     business (its role is changed in Personnel), when the business is
--     archived, and — as when the person claims an invitation — when the
--     free plan's team is full (an owner never counts). The business's
--     admins are told « X a rejoint … » by the existing trigger. Logged in
--     the console's journal, undoable while the access is unchanged.
--   * platform_undo_add_member(args): takes that access away again.
--
-- For a shop, a farm, an association and an Événementiel alike: a
-- membership, nothing else. Applies twice.
-- ============================================================

create or replace function platform_add_member(p_org uuid, p_user uuid, p_role role_name)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org    orgs%rowtype;
    v_who    text;
    v_have   role_name;
    v_id     uuid;
begin
    perform platform_only();
    if p_org is null or p_user is null or p_role is null then
        raise exception 'Choisissez une entreprise, un compte et une responsabilité.';
    end if;
    if p_role = 'super_admin' then
        raise exception 'Cette responsabilité ne se donne pas ici.';
    end if;

    select * into v_org from orgs where id = p_org;
    if not found then
        raise exception 'Entreprise introuvable.';
    end if;
    if v_org.archived_at is not null then
        raise exception '« % » est archivée : restaurez-la d''abord.', v_org.name;
    end if;

    select coalesce(nullif(btrim(coalesce(p.full_name, '')), ''), u.email, u.phone, 'Ce compte')
      into v_who
      from profiles p left join auth.users u on u.id = p.id
     where p.id = p_user;
    if not found then
        raise exception 'Compte introuvable.';
    end if;

    select m.role into v_have
      from memberships m
     where m.org_id = p_org and m.user_id = p_user and not coalesce(m.is_trainer, false)
     order by role_rank(m.role) desc
     limit 1;
    if found then
        raise exception '% fait déjà partie de « % » (%). Changez sa responsabilité dans Personnel.',
            v_who, v_org.name, v_have;
    end if;

    -- The free plan's team limit, as for a person claiming an invitation
    -- (the cap trigger lets a platform admin's own writes through).
    if p_role <> 'owner' then
        perform pg_advisory_xact_lock(hashtext('team:' || p_org::text));
        if team_full(p_org) then
            raise exception '%', team_full_message(p_org);
        end if;
    end if;

    insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
    values (p_org, p_user, p_role, 'org', p_org, 'full')
    returning id into v_id;

    perform platform_log_action(
        p_org, 'member',
        format('%s ajouté·e à %s (%s)', v_who, v_org.name, p_role),
        null,
        jsonb_build_object('user_id', p_user, 'role', p_role),
        'platform_undo_add_member',
        jsonb_build_object('membership_id', v_id, 'org_id', p_org, 'user_id', p_user, 'role', p_role));
    return v_id;
end;
$$;

create or replace function platform_undo_add_member(p_args jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_id uuid := (p_args->>'membership_id')::uuid;
    r    memberships%rowtype;
begin
    perform platform_only();
    select * into r from memberships where id = v_id for update;
    if not found then
        raise exception 'Cet accès n''existe plus : il n''y a rien à annuler.';
    end if;
    if r.role::text is distinct from p_args->>'role' then
        raise exception 'Sa responsabilité a changé depuis : l''accès n''est pas retiré.';
    end if;
    delete from memberships where id = v_id;
end;
$$;

insert into platform_undo_fns (fn) values ('platform_undo_add_member')
on conflict do nothing;

revoke execute on function platform_add_member(uuid, uuid, role_name) from public;
revoke execute on function platform_undo_add_member(jsonb) from public;
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function platform_add_member(uuid, uuid, role_name) from anon;
        revoke execute on function platform_undo_add_member(jsonb) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function platform_add_member(uuid, uuid, role_name) to authenticated;
        revoke execute on function platform_undo_add_member(jsonb) from authenticated;
    end if;
end $$;
