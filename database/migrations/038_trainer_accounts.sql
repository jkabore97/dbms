-- ============================================================
-- 038_trainer_accounts.sql — accounts for the people who train the businesses.
--
-- The user hires students to go out and train businesses and their staff on the
-- app. The question was whether each needs a special account and what it should
-- look like. The answer built here: a trainer is an ordinary account marked as
-- a trainer, whom the platform assigns to the specific businesses they help.
-- Inside one of those businesses the trainer sees everything, so they can guide,
-- and can change nothing, so a lesson can never cost the business its data.
--
-- HOW IT REUSES WHAT EXISTS, AND WHY THAT IS THE SAFE CHOICE. A training
-- assignment is a membership with role 'observer' and full visibility, flagged
-- is_trainer. That one modelling choice buys the whole feature from rules that
-- already hold and are already tested:
--   * has_full_visibility() is true → the trainer reads every report and line,
--     which is what advising needs.
--   * can_write_org() excludes 'observer' → the trainer records nothing.
--   * is_org_admin() excludes 'observer' → the trainer cannot rename, archive,
--     delete, or change who owns the business.
-- So no read/write policy is touched; the access is exactly an investor's,
-- narrowed by intent rather than by new plumbing. The is_trainer flag only
-- distinguishes these grants so a business's own team roster can leave them out
-- — a trainer is not the business's staff.
--
-- WHO MAY DO WHAT. Only a platform admin marks an account as a trainer and
-- assigns or unassigns it; a business cannot conscript a trainer, and a trainer
-- cannot enrol themselves. Every function here checks is_platform_admin first.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The flags. On the account: this user is a trainer. On the membership:
--    this grant is a training assignment, not the business's own team.
-- ------------------------------------------------------------
alter table profiles    add column if not exists is_trainer boolean not null default false;
alter table memberships add column if not exists is_trainer boolean not null default false;

-- ------------------------------------------------------------
-- 2. Mark (or unmark) a trainer account, found by the phone the platform admin
--    knows them by. Returns the account id. Unmarking does not touch existing
--    assignments — a paused trainer keeps their history until unassigned.
-- ------------------------------------------------------------
create or replace function set_trainer_by_phone(
    p_phone      text,
    p_is_trainer boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
    v_user  uuid;
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can manage trainers';
    end if;
    if v_phone is null then
        raise exception 'A phone number is required';
    end if;

    select id into v_user from profiles where phone = v_phone;
    if v_user is null then
        raise exception 'No account has the phone %', v_phone;
    end if;

    update profiles set is_trainer = coalesce(p_is_trainer, false) where id = v_user;
    return v_user;
end;
$$;

-- ------------------------------------------------------------
-- 3. Assign a trainer to a business — the observer/full/is_trainer grant.
--    Idempotent: re-assigning re-affirms the grant rather than doubling it.
-- ------------------------------------------------------------
create or replace function assign_trainer(
    p_org_id  uuid,
    p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can assign a trainer';
    end if;
    if not exists (select 1 from orgs where id = p_org_id) then
        raise exception 'No such business';
    end if;
    if not exists (select 1 from profiles where id = p_user_id and is_trainer) then
        raise exception 'That account is not a trainer';
    end if;

    insert into memberships (org_id, user_id, role, scope_kind, scope_id,
                             visibility, is_trainer)
    values (p_org_id, p_user_id, 'observer', 'org', p_org_id, 'full', true)
    on conflict (user_id, scope_kind, scope_id, role)
    do update set is_trainer = true, visibility = 'full';
end;
$$;

-- ------------------------------------------------------------
-- 4. Remove a training assignment. Only the training grant is deleted; if the
--    person somehow also holds another role here, that one is untouched.
-- ------------------------------------------------------------
create or replace function unassign_trainer(
    p_org_id  uuid,
    p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can unassign a trainer';
    end if;

    delete from memberships
    where org_id = p_org_id
      and user_id = p_user_id
      and role = 'observer'
      and is_trainer;
end;
$$;

-- ------------------------------------------------------------
-- 5. The trainer directory, for the console: every trainer account with how
--    many businesses they currently cover. Platform admin only.
-- ------------------------------------------------------------
create or replace function list_trainers()
returns table (
    user_id     uuid,
    full_name   text,
    phone       text,
    assignments bigint
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can list trainers';
    end if;

    return query
    select p.id, p.full_name, p.phone,
           count(m.*) filter (where m.is_trainer)
    from profiles p
    left join memberships m on m.user_id = p.id
    where p.is_trainer
    group by p.id, p.full_name, p.phone
    order by p.full_name nulls last, p.phone;
end;
$$;

-- ------------------------------------------------------------
-- 6. The businesses a trainer covers. A trainer sees their own list; a platform
--    admin may ask for anyone's. Returns nothing to anyone else.
-- ------------------------------------------------------------
create or replace function trainer_orgs(
    p_user_id uuid default null
)
returns table (
    org_id  uuid,
    name    text,
    slug    text,
    profile text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_target uuid := coalesce(p_user_id, auth.uid());
begin
    if v_target <> auth.uid()
       and not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'You cannot read another trainer''s businesses';
    end if;

    return query
    select o.id, o.name, o.slug, o.profile
    from memberships m
    join orgs o on o.id = m.org_id
    where m.user_id = v_target
      and m.is_trainer
      and o.archived_at is null
    order by o.name;
end;
$$;

-- ------------------------------------------------------------
-- 7. The trainers on one business — for the console, and for the business's own
--    admin, who is entitled to know who is training them.
-- ------------------------------------------------------------
create or replace function org_trainers(
    p_org_id uuid
)
returns table (
    user_id   uuid,
    full_name text,
    phone     text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
       and not is_org_admin(p_org_id) then
        raise exception 'You cannot read this business''s trainers';
    end if;

    return query
    select p.id, p.full_name, p.phone
    from memberships m
    join profiles p on p.id = m.user_id
    where m.org_id = p_org_id
      and m.is_trainer
    order by p.full_name nulls last, p.phone;
end;
$$;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_trainer_by_phone(text, boolean) to authenticated;
        grant execute on function assign_trainer(uuid, uuid)          to authenticated;
        grant execute on function unassign_trainer(uuid, uuid)        to authenticated;
        grant execute on function list_trainers()                     to authenticated;
        grant execute on function trainer_orgs(uuid)                  to authenticated;
        grant execute on function org_trainers(uuid)                  to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
