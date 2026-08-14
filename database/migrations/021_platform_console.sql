-- ============================================================
-- 021 — A PLATFORM CONSOLE THAT SURVIVES A THOUSAND BUSINESSES
-- ============================================================
-- `all_orgs()` from 014 was written when the platform had three businesses on
-- it, and it shows. It returns *every* row, and for each row it runs two
-- correlated subqueries:
--
--     (select count(*) from memberships     where org_id = o.id),
--     (select count(*) from journal_entries where org_id = o.id)
--
-- At a thousand businesses that is two thousand subqueries per page load, one
-- of them counting every accounting entry the platform has ever recorded. The
-- app then puts all thousand rows into a single ListView. Neither half of that
-- survives the scale this migration is named for, and the failure is the worst
-- kind: it degrades smoothly, so nobody notices until the console takes eleven
-- seconds and the person running the platform quietly stops opening it.
--
-- Three changes fix it.
--
-- 1. ACTIVITY BECOMES A COLUMN, NOT A SCAN. `orgs.last_activity_at` is
--    maintained by a trigger. Sorting and filtering by "which businesses have
--    gone quiet" is then an indexed read instead of an aggregate over the
--    whole ledger — and "gone quiet" is the single most useful question the
--    platform admin has, because it predicts churn weeks before it happens.
--
-- 2. THE EXPENSIVE COUNTS ARE COMPUTED FOR ONE PAGE, NOT ALL ROWS. The
--    filtering and ordering happen on indexed columns of `orgs`; only the
--    fifty rows actually being returned pay for a member count. That is the
--    whole trick, and it keeps the query flat as the platform grows.
--
-- 3. THE AGGREGATES COME BACK IN ONE ROW. `platform_overview()` answers "how
--    many, how healthy" without returning a single business — so the console
--    can lead with the shape of the platform rather than with page one of an
--    alphabetical list, which is not information.
--
-- `all_orgs()` is deliberately left in place. It is what the current screen
-- calls, and a migration that breaks the app already deployed is how this
-- project has hurt itself before.

-- ------------------------------------------------------------
-- 1. WHEN DID THIS BUSINESS LAST DO ANYTHING
-- ------------------------------------------------------------
alter table orgs add column if not exists last_activity_at timestamptz;

comment on column orgs.last_activity_at is
    'When this business last posted a journal entry. Maintained by trigger so '
    'the platform console can sort and filter on activity without scanning '
    'the ledger. Approximate by design: it is a health signal, not an audit '
    'record — journal_entries remains the source of truth.';

-- One extra UPDATE per journal entry. Journal entries are a handful per
-- business per day, so this is cheap on the write side and turns the console's
-- most important question into an index scan on the read side.
--
-- Guarded on the value actually moving forward: a backdated entry must not
-- drag a business's activity date backwards and make a live business look
-- abandoned.
create or replace function touch_org_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    update orgs
       set last_activity_at = greatest(
             coalesce(last_activity_at, new.created_at), new.created_at)
     where id = new.org_id
       and (last_activity_at is null or last_activity_at < new.created_at);
    return null;
end;
$$;

drop trigger if exists journal_entries_touch_org on journal_entries;
create trigger journal_entries_touch_org
    after insert on journal_entries
    for each row execute function touch_org_activity();

-- Existing businesses get their real figure rather than starting blank, so
-- the console is correct the moment this migration lands.
update orgs o
   set last_activity_at = j.last_at
  from (select org_id, max(created_at) as last_at
          from journal_entries group by org_id) j
 where j.org_id = o.id
   and (o.last_activity_at is null or o.last_activity_at < j.last_at);

-- ------------------------------------------------------------
-- 2. INDEXES THE CONSOLE ACTUALLY USES
-- ------------------------------------------------------------
-- Search is on lower(name) because a person hunting for a business types it
-- in whatever case they please. This is a prefix/equality index; substring
-- search still falls back to a scan, which is acceptable while a scan of
-- `orgs` alone is cheap and a trigram extension is not guaranteed present.
create index if not exists orgs_by_lower_name on orgs (lower(name));
create index if not exists orgs_by_activity   on orgs (last_activity_at desc nulls last);
create index if not exists orgs_by_created    on orgs (created_at desc);
create index if not exists orgs_by_profile    on orgs (profile);

-- ------------------------------------------------------------
-- 3. THE SHAPE OF THE PLATFORM, IN ONE ROW
-- ------------------------------------------------------------
-- What the console leads with. None of these return a business; they answer
-- "is anything wrong today" in a single round trip.
create or replace function platform_overview()
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
    never_active   int
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
            where o.archived_at is null and o.last_activity_at is null)::int
    from orgs o;
end;
$$;

-- ------------------------------------------------------------
-- 4. FINDING ONE BUSINESS AMONG THOUSANDS
-- ------------------------------------------------------------
-- Search, filter, sort and paginate — all server side. The client never holds
-- more than one page.
--
-- `total_count` rides along on every row via a window function so the pager
-- knows how many pages there are without a second round trip. It is the same
-- number on every row of the page; the client reads it from the first.
create or replace function search_orgs(
    p_query    text    default null,
    p_profile  text    default null,   -- 'farm' | 'retail' | 'church' | null
    p_status   text    default 'active', -- 'active' | 'archived' | 'all'
    p_activity text    default null,   -- 'active7' | 'silent30' | 'never'
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
             or (p_activity = 'never' and o.last_activity_at is null))
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

-- ------------------------------------------------------------
-- 5. GRANTS
-- ------------------------------------------------------------
-- Both functions make their own platform-admin check, which is why they are
-- DEFINER: they read across every tenant on purpose, and RLS would correctly
-- refuse them.
revoke execute on function platform_overview() from public;
revoke execute on function search_orgs(text, text, text, text, text, int, int) from public;
revoke execute on function touch_org_activity() from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function platform_overview() to authenticated;
        grant execute on function search_orgs(text, text, text, text, text, int, int) to authenticated;
        -- touch_org_activity() is a trigger function and is never called
        -- directly; it is deliberately not granted.
    end if;
end $$;

notify pgrst, 'reload schema';
