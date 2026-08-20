-- ============================================================
-- 049_org_suspend.sql — a business can be frozen without being destroyed.
--
-- The console can archive or delete a business, but there is nothing in
-- between: no way to stop a business operating — for non-payment, for abuse,
-- while a dispute is sorted — and let it resume untouched later. Deleting loses
-- the data; archiving is meant to be permanent. Suspension is the middle state.
--
-- The freeze rides the one write chokepoint. can_write_org() (010) is what every
-- write policy and every money function ultimately answers to — record_entry()
-- calls it, and the RLS policies name it directly. Making it false for a
-- suspended business turns the whole business read-only in one place: the till
-- stops, stock stops moving, no expense posts. The platform admin is exempt, so
-- they can still un-suspend and moderate; members keep full *read* access — a
-- suspension is read-only, not invisible — so their history and the banner
-- explaining why are still there.
-- ============================================================

alter table orgs add column if not exists suspended_at timestamptz;
comment on column orgs.suspended_at is
    'When a platform admin froze this business. Non-null = suspended: members '
    'may read but not write; a platform admin may still act. Distinct from '
    'archived_at, which is meant to be permanent.';

-- The chokepoint. 010 verbatim apart from the suspension clause on the member
-- branch; the platform-admin branch is untouched, so the platform keeps its
-- reach precisely when it is needed — to lift the suspension.
create or replace function can_write_org(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        exists(select 1 from profiles where id = auth.uid() and is_platform_admin)
        or (
            not exists (select 1 from orgs
                        where id = p_org_id and suspended_at is not null)
            and exists (
                select 1 from memberships m
                where m.user_id = auth.uid()
                  and m.org_id = p_org_id
                  and m.role <> 'observer'
            )
        );
$$;

-- Freeze or thaw. Platform admin only. Idempotent: suspending an already
-- suspended business keeps the original timestamp rather than resetting it.
create or replace function set_org_suspended(p_org_id uuid, p_suspend boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles
                   where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can suspend a business';
    end if;
    if not exists (select 1 from orgs where id = p_org_id) then
        raise exception 'No such business';
    end if;

    update orgs
       set suspended_at = case
               when p_suspend then coalesce(suspended_at, now())
               else null
           end
     where id = p_org_id;
end;
$$;

-- my_orgs carries the suspended flag so the app can show a read-only banner the
-- moment a business opens, offline included (the org list is cached). Return
-- type changes, so it is dropped and recreated — 022 verbatim plus the column.
drop function if exists my_orgs();

create or replace function my_orgs()
returns table (
    org_id           uuid,
    name             text,
    slug             text,
    profile          text,
    default_currency text,
    roles            text[],
    visibility       text,
    theme            text,
    suspended        boolean
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        o.id, o.name, o.slug, o.profile, o.default_currency,
        array['platform_admin'::text],
        'full'::text,
        o.theme,
        (o.suspended_at is not null)
    from orgs o
    where exists(select 1 from profiles where id = auth.uid() and is_platform_admin)

    union all

    select
        o.id, o.name, o.slug, o.profile, o.default_currency,
        array_agg(distinct m.role::text order by m.role::text),
        case when bool_or(m.visibility = 'full') then 'full' else 'summary' end,
        o.theme,
        (o.suspended_at is not null)
    from memberships m
    join orgs o on o.id = m.org_id
    where m.user_id = auth.uid()
      and o.archived_at is null
      and not exists(select 1 from profiles where id = auth.uid() and is_platform_admin)
    group by o.id, o.name, o.slug, o.profile, o.default_currency, o.theme,
             o.suspended_at

    order by name;
$$;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_org_suspended(uuid, boolean) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
