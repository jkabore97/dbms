-- ============================================================
-- 065_org_plan.sql — which plan a business is on, and until when.
--
-- M10 block 1. Two plans, not three: 'free' (Kaj, forever) and 'pro' (Kaj
-- Pro, paid). This migration is only the flag and who may set it — no tool
-- is gated yet (that is 066), no money moves (that is by hand, then M9).
-- Shipping the flag alone first means the console can already record who
-- paid before anyone is asked to.
--
-- The rules, all of them here:
--   * plan_until is the paid-until date. Null means no end (a gift, a
--     partner, a test business). A Pro business past its date reads as
--     'free' — org_plan() is the one place that decides — and nothing else
--     happens to it: no cliff, no read-only, nothing deleted. Lapsing Pro
--     is Free, exactly as it was before it paid.
--   * Only the platform sets a plan. SECURITY DEFINER like set_org_suspended
--     (049), and for the same reason: it writes a column RLS would rightly
--     refuse to a non-member, and the platform admin is a member of nothing.
--   * The change is in the activity log for free: orgs carries the 008
--     audit trigger, so the row's diff (plan, plan_until, plan_note) lands
--     in audit_log with the platform admin as actor. Nothing to add.
--   * my_orgs() carries the effective plan so the app knows it offline,
--     from the cached org list, the way it knows a suspension.
--   * platform_overview() counts the Pro businesses, and search_orgs()
--     lists them behind a tile — the console's first revenue number.
--
-- Since 063 a new function is born closed to anon; both of these are for
-- signed-in callers only, so the grant to authenticated is all they need.
-- ============================================================

alter table orgs add column if not exists plan text not null default 'free';
alter table orgs add column if not exists plan_until date;
alter table orgs add column if not exists plan_note text;

alter table orgs drop constraint if exists orgs_plan_known;
alter table orgs add constraint orgs_plan_known check (plan in ('free', 'pro'));

comment on column orgs.plan is
    'The plan the platform set: free or pro. Read through org_plan(), which '
    'also applies plan_until; never read raw for a gate.';
comment on column orgs.plan_until is
    'Paid until, inclusive. Null = no end. Past this date a pro business '
    'reads as free — nothing else changes.';
comment on column orgs.plan_note is
    'Why, for the platform: "Wave 25 000 F le 12/09", "partenaire", "test".';

-- The one place the effective plan is decided. Unknown business: free.
create or replace function org_plan(p_org_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select case
        when o.plan = 'pro'
         and (o.plan_until is null
              or o.plan_until >= (now() at time zone 'Africa/Ouagadougou')::date)
        then 'pro'
        else 'free'
    end
    from orgs o
    where o.id = p_org_id
    union all
    select 'free'
    where not exists (select 1 from orgs where id = p_org_id)
    limit 1;
$$;

-- Set or change a plan. Platform admin only. Re-runnable: setting the same
-- plan again with the same date is a no-op the audit trigger also ignores.
create or replace function set_org_plan(
    p_org_id uuid,
    p_plan   text,
    p_until  date default null,
    p_note   text default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles
                   where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can set a business''s plan';
    end if;
    if not exists (select 1 from orgs where id = p_org_id) then
        raise exception 'No such business';
    end if;
    if p_plan not in ('free', 'pro') then
        raise exception 'Unknown plan: %', p_plan;
    end if;

    update orgs
       set plan       = p_plan,
           -- A date on a free plan means nothing; do not keep one.
           plan_until = case when p_plan = 'pro' then p_until else null end,
           plan_note  = nullif(btrim(coalesce(p_note, '')), '')
     where id = p_org_id;
end;
$$;

-- my_orgs() carries the effective plan. 049 verbatim plus the column; the
-- return type changes, so it is dropped and recreated.
drop function if exists my_orgs();

create function my_orgs()
returns table (
    org_id           uuid,
    name             text,
    slug             text,
    profile          text,
    default_currency text,
    roles            text[],
    visibility       text,
    theme            text,
    suspended        boolean,
    plan             text
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
        (o.suspended_at is not null),
        org_plan(o.id)
    from orgs o
    where exists(select 1 from profiles where id = auth.uid() and is_platform_admin)

    union all

    select
        o.id, o.name, o.slug, o.profile, o.default_currency,
        array_agg(distinct m.role::text order by m.role::text),
        case when bool_or(m.visibility = 'full') then 'full' else 'summary' end,
        o.theme,
        (o.suspended_at is not null),
        org_plan(o.id)
    from memberships m
    join orgs o on o.id = m.org_id
    where m.user_id = auth.uid()
      and o.archived_at is null
      and not exists(select 1 from profiles where id = auth.uid() and is_platform_admin)
    group by o.id, o.name, o.slug, o.profile, o.default_currency, o.theme,
             o.suspended_at

    order by name;
$$;

-- platform_overview() gains the Pro count. 021 verbatim plus the column;
-- the return type changes, so it is dropped and recreated.
drop function if exists platform_overview();

create function platform_overview()
returns table (
    total          int,
    active         int,
    archived       int,
    farms          int,
    shops          int,
    churches       int,
    other_profiles int,
    new_this_week  int,
    active_7d      int,
    silent_30d     int,
    never_active   int,
    pro            int
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (
        select 1 from profiles where id = auth.uid() and is_platform_admin
    ) then
        raise exception 'Only a platform admin can read the platform overview';
    end if;

    return query
    select
        count(*)::int,
        count(*) filter (where o.archived_at is null)::int,
        count(*) filter (where o.archived_at is not null)::int,
        count(*) filter (where o.profile = 'farm')::int,
        count(*) filter (where o.profile = 'retail')::int,
        count(*) filter (where o.profile = 'church')::int,
        count(*) filter (where o.profile not in ('farm','retail','church'))::int,
        count(*) filter (where o.created_at > now() - interval '7 days')::int,
        count(*) filter (where o.last_activity_at > now() - interval '7 days')::int,
        -- The churn signal: alive once, silent for a month.
        count(*) filter (
            where o.archived_at is null
              and o.last_activity_at is not null
              and o.last_activity_at < now() - interval '30 days')::int,
        -- Onboarded and never used. A different failure, and a different fix:
        -- this one belongs to whoever signed them up.
        count(*) filter (
            where o.archived_at is null and o.last_activity_at is null)::int,
        -- Paying today: the effective plan, so a lapsed Pro is not counted.
        count(*) filter (
            where o.archived_at is null and org_plan(o.id) = 'pro')::int
    from orgs o;
end;
$$;

-- search_orgs() learns one more activity filter, 'pro', so the console's
-- Pro tile opens onto the businesses behind the number. 021 verbatim plus
-- that one branch; same return type, so replaced in place.
create or replace function search_orgs(
    p_query    text    default null,
    p_profile  text    default null,   -- 'farm' | 'retail' | 'church' | null
    p_status   text    default 'active', -- 'active' | 'archived' | 'all'
    p_activity text    default null,   -- 'active7' | 'silent30' | 'never' | 'pro'
    p_sort     text    default 'activity', -- 'activity' | 'name' | 'newest'
    p_limit    int     default 50,
    p_offset   int     default 0
)
returns table (
    org_id           uuid,
    name             text,
    slug             text,
    profile          text,
    currency         text,
    archived_at      timestamptz,
    created_at       timestamptz,
    last_activity_at timestamptz,
    member_count     int,
    total_count      int
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_limit  int := least(greatest(coalesce(p_limit, 50), 1), 200);
    v_offset int := greatest(coalesce(p_offset, 0), 0);
    v_query  text := nullif(btrim(coalesce(p_query, '')), '');
begin
    if not exists (
        select 1 from profiles where id = auth.uid() and is_platform_admin
    ) then
        raise exception 'Only a platform admin can search every business';
    end if;

    return query
    with filtered as (
        select o.id, o.name, o.slug, o.profile, o.default_currency,
               o.archived_at, o.created_at, o.last_activity_at,
               count(*) over () as total
        from orgs o
        where
            -- Status
            (   coalesce(p_status, 'active') = 'all'
             or (p_status = 'archived' and o.archived_at is not null)
             or (coalesce(p_status, 'active') = 'active' and o.archived_at is null))
            -- Profile
        and (p_profile is null or o.profile = p_profile)
            -- Activity
        and (   p_activity is null
             or (p_activity = 'active7'
                 and o.last_activity_at > now() - interval '7 days')
             or (p_activity = 'silent30'
                 and o.last_activity_at is not null
                 and o.last_activity_at < now() - interval '30 days')
             or (p_activity = 'never' and o.last_activity_at is null)
             or (p_activity = 'pro' and org_plan(o.id) = 'pro'))
            -- Text: name or slug. Both lowered, so case never matters.
        and (   v_query is null
             or lower(o.name) like '%' || lower(v_query) || '%'
             or lower(o.slug) like '%' || lower(v_query) || '%')
        order by
            case when p_sort = 'name'   then lower(o.name) end asc,
            case when p_sort = 'newest' then o.created_at  end desc,
            -- Default: the businesses that have done something most recently,
            -- with the never-active ones last rather than first — a null is
            -- not "the most recent".
            case when coalesce(p_sort, 'activity') = 'activity'
                 then o.last_activity_at end desc nulls last,
            lower(o.name) asc
        limit v_limit offset v_offset
    )
    -- Only the page pays for this. That is the whole point of the CTE.
    select f.id, f.name, f.slug, f.profile, f.default_currency,
           f.archived_at, f.created_at, f.last_activity_at,
           (select count(*)::int from memberships m where m.org_id = f.id),
           f.total::int
    from filtered f;
end;
$$;

revoke execute on function org_plan(uuid)                          from public;
revoke execute on function set_org_plan(uuid, text, date, text)    from public;
revoke execute on function my_orgs()                               from public;
revoke execute on function platform_overview()                     from public;
revoke execute on function search_orgs(text, text, text, text, text, int, int) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function org_plan(uuid)                       to authenticated;
        grant execute on function set_org_plan(uuid, text, date, text) to authenticated;
        grant execute on function my_orgs()                            to authenticated;
        grant execute on function platform_overview()                  to authenticated;
        grant execute on function search_orgs(text, text, text, text, text, int, int)
            to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
