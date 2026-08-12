-- ============================================================
-- 010_platform_admin.sql
--
-- Numbered 010, after 009_farm_profile.sql, because this was written as 006
-- on a branch while 006_report_access.sql was being written on another. The
-- order matters beyond avoiding a name collision: the four helpers replaced
-- below are the ones 006's policies call, so this has to be the last word on
-- them. Applied before 006 it would be silently undone.
--
-- Two problems, one column. Right now:
--   1. Seeing every business takes a manual membership grant per org —
--      admin@kajapp.com has to be re-granted every time a new one is made.
--   2. Nothing can create a new org at all. orgs has no INSERT policy, and
--      a naive INSERT would be blocked outright — you can't be "admin of
--      an org" that doesn't exist yet to grant you that role.
--
-- is_platform_admin on profiles solves both, added as one extra OR clause
-- to each existing SECURITY DEFINER helper below. Every signature, column
-- name, and column type matches 004_rls_policies.sql exactly — nothing
-- that already calls these changes, only what they return for this one
-- flag.
--
-- NOT changed here, on purpose: can_write_org's original body excludes
-- only 'observer', not 'approver' too. An approver being able to write
-- seems like it may be a pre-existing gap against the role's intended
-- read-plus-signoff meaning — worth a look on its own, not silently
-- folded into this migration.
-- ============================================================

alter table profiles add column if not exists is_platform_admin boolean not null default false;

create or replace function my_org_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public, auth
as $$
    select id from orgs
    where exists(select 1 from profiles where id = auth.uid() and is_platform_admin)
    union
    select distinct m.org_id
    from memberships m
    where m.user_id = auth.uid();
$$;

create or replace function is_org_member(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        exists(select 1 from profiles where id = auth.uid() and is_platform_admin)
        or exists (
            select 1 from memberships m
            where m.user_id = auth.uid() and m.org_id = p_org_id
        );
$$;

create or replace function is_org_admin(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        exists(select 1 from profiles where id = auth.uid() and is_platform_admin)
        or exists (
            select 1 from memberships m
            where m.user_id = auth.uid()
              and m.org_id = p_org_id
              and m.role in ('owner', 'super_admin', 'admin')
        );
$$;

create or replace function can_write_org(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        exists(select 1 from profiles where id = auth.uid() and is_platform_admin)
        or exists (
            select 1 from memberships m
            where m.user_id = auth.uid()
              and m.org_id = p_org_id
              and m.role <> 'observer'
        );
$$;

-- CREATE OR REPLACE cannot change a table-returning function's output
-- columns, and dropping is required even though this one's shape matches
-- the original exactly, in case a future edit doesn't.
drop function if exists my_orgs();

create or replace function my_orgs()
returns table (
    org_id           uuid,
    name             text,
    slug             text,
    profile          text,
    default_currency text,
    roles            text[],
    visibility       text
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        o.id, o.name, o.slug, o.profile, o.default_currency,
        array['platform_admin'::text],
        'full'::text
    from orgs o
    where exists(select 1 from profiles where id = auth.uid() and is_platform_admin)

    union all

    select
        o.id, o.name, o.slug, o.profile, o.default_currency,
        array_agg(distinct m.role::text order by m.role::text),
        case when bool_or(m.visibility = 'full') then 'full' else 'summary' end
    from memberships m
    join orgs o on o.id = m.org_id
    where m.user_id = auth.uid()
      and not exists(select 1 from profiles where id = auth.uid() and is_platform_admin)
    group by o.id, o.name, o.slug, o.profile, o.default_currency

    order by name;
$$;

-- ------------------------------------------------------------
-- Creating a business. SECURITY DEFINER on purpose, unlike
-- record_contribution/record_expense: RLS cannot gate an INSERT into orgs
-- on membership in an org that does not exist until this statement runs, so
-- the is_platform_admin check below IS the authorization, not a backstop.
-- ------------------------------------------------------------

create or replace function create_org(
    p_name     text,
    p_slug     text,
    p_profile  text default 'generic',
    p_currency text default 'XOF'
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org_id uuid;
begin
    if not exists(select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can create a new business';
    end if;

    insert into orgs (name, slug, profile, default_currency)
    values (p_name, p_slug, p_profile, p_currency)
    returning id into v_org_id;

    -- Ownership on the new org, even though platform-admin bypass already
    -- grants access — so the person who made it shows up as its owner, not
    -- an invisible ghost with access nobody can see the source of.
    insert into memberships (org_id, user_id, role, scope_kind, scope_id)
    values (v_org_id, auth.uid(), 'owner', 'org', v_org_id);

    -- Starter data by profile. Only 'church' has a dedicated module today
    -- (002_church_profile.sql); everything else gets a minimal generic
    -- chart of accounts so the org isn't empty before its own module exists.
    if p_profile = 'church' then
        perform seed_church_accounts(v_org_id);
    else
        insert into accounts (org_id, code, name, type) values
            (v_org_id, '1000', 'Cash on Hand',        'asset'),
            (v_org_id, '1010', 'Bank Account',        'asset'),
            (v_org_id, '1020', 'Mobile Money',        'asset'),
            (v_org_id, '4000', 'Sales',                'income'),
            (v_org_id, '5000', 'Purchases',            'expense'),
            (v_org_id, '5010', 'Operating Expenses',   'expense')
        on conflict (org_id, code) do nothing;
    end if;

    return v_org_id;
end;
$$;
