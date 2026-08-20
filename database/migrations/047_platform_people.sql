-- ============================================================
-- 047_platform_people.sql — the platform admin's global directory of people.
--
-- The console is business-first: it can find a business, but not a person. To
-- moderate the platform you need the other axis — search any account across
-- every business, see where they appear and as what, and act (reset a password
-- and delete an account through the existing account Worker; grant or revoke
-- platform access here). All three functions are platform-admin only and cross
-- every tenant on purpose, so — like the console's own reads (036) — the
-- is_platform_admin gate is the whole guard and is checked first.
-- ============================================================

-- Search every account by name, phone or email. Empty query lists everyone,
-- newest-relevant first. email lives on auth.users, which only a definer
-- function may read — one more reason this is not a view.
create or replace function platform_people(
    p_query  text default null,
    p_limit  int  default 50,
    p_offset int  default 0
)
returns table (
    user_id           uuid,
    full_name         text,
    phone             text,
    email             text,
    title             text,
    is_platform_admin boolean,
    business_count    bigint,
    created_at        timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_q text := nullif(btrim(coalesce(p_query, '')), '');
begin
    -- Qualified: this function returns a column also named is_platform_admin,
    -- so a bare reference here is ambiguous.
    if not exists (select 1 from profiles
                   where profiles.id = auth.uid()
                     and profiles.is_platform_admin) then
        raise exception 'Only a platform admin can list people';
    end if;

    return query
    select
        p.id,
        p.full_name,
        p.phone,
        u.email,
        p.title,
        p.is_platform_admin,
        (select count(distinct m.org_id) from memberships m where m.user_id = p.id),
        p.created_at
    from profiles p
    join auth.users u on u.id = p.id
    where v_q is null
       or p.full_name ilike '%' || v_q || '%'
       or p.phone     ilike '%' || v_q || '%'
       or u.email     ilike '%' || v_q || '%'
    order by coalesce(p.full_name, u.email, p.phone) nulls last
    limit greatest(1, least(coalesce(p_limit, 50), 200))
    offset greatest(0, coalesce(p_offset, 0));
end;
$$;

-- The businesses one person belongs to, and their role in each — the footprint
-- a moderator wants before they act on an account.
create or replace function platform_user_orgs(p_user_id uuid)
returns table (
    org_id   uuid,
    org_name text,
    profile  text,
    role     role_name,
    archived boolean
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles
                   where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can read a person''s businesses';
    end if;

    return query
    select o.id, o.name, o.profile, m.role, (o.archived_at is not null)
    from memberships m
    join orgs o on o.id = m.org_id
    where m.user_id = p_user_id
    order by o.name;
end;
$$;

-- Grant or revoke platform access. Platform admin only (the guard trigger from
-- 032 enforces the same, so this is belt and braces); never on oneself, so a
-- misclick cannot lock the platform's operator out of their own console.
create or replace function set_platform_admin(p_user_id uuid, p_value boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles
                   where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can grant or revoke platform access';
    end if;
    if p_user_id = auth.uid() then
        raise exception 'You cannot change your own platform access';
    end if;
    if not exists (select 1 from profiles where id = p_user_id) then
        raise exception 'No such account';
    end if;

    update profiles set is_platform_admin = coalesce(p_value, false)
     where id = p_user_id;
end;
$$;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function platform_people(text, int, int)   to authenticated;
        grant execute on function platform_user_orgs(uuid)          to authenticated;
        grant execute on function set_platform_admin(uuid, boolean) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
