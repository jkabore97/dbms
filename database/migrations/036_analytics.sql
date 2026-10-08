-- ============================================================
-- 036_analytics.sql — the numbers a business owner and the platform actually
-- want to see, computed on the server where the rows live.
--
-- The user asked, in their words, to know "what sells more or less, when, how
-- fast, and other smart things" for a business owner, and the same across every
-- business for the platform. That is five owner-facing read functions and two
-- platform-wide ones. All of them read the sales the retail/church/farm modules
-- already write (sales + sale_lines from 011); none of them stores a derived
-- number, because a cached analytic shown without a date is a lie waiting to
-- happen (the same reason the reports in 006 cache nothing).
--
-- WHO MAY READ WHAT. The five owner functions raise unless the caller has full
-- visibility of that one business — an employee restricted to the till never
-- computes the owner's margins — and they read as the caller so RLS still
-- covers every table underneath (006 already limits sale_lines to full
-- visibility). The two platform functions are SECURITY DEFINER and raise unless
-- the caller is a platform admin; they cross every org on purpose, which is
-- exactly what RLS would stop, so the is_platform_admin gate is the whole guard
-- and is checked first.
--
-- WHY FUNCTIONS, NOT VIEWS. A view added to this schema must carry
-- security_invoker = on or it reads as its owner and leaks (the standing rule).
-- Aggregates that must branch on the caller's role are clearer and safer as
-- functions with an explicit gate, so there are no views here.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Owner: the headline. One row of the numbers that go on the cards at the
--    top — revenue, margin, how many sales, the average basket, units moved —
--    over a window ending now. p_since null means "all of time".
-- ------------------------------------------------------------
create or replace function org_sales_headline(
    p_org_id uuid,
    p_since  timestamptz default null
)
returns table (
    sale_count      bigint,
    revenue         numeric,
    cost            numeric,
    margin          numeric,
    units           numeric,
    avg_basket      numeric,
    products_sold   bigint
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;

    return query
    with s as (
        select sa.id, sa.total
        from sales sa
        where sa.org_id = p_org_id
          and sa.kind = 'sale'
          and (p_since is null or sa.occurred_at >= p_since)
    ),
    lines as (
        select sl.quantity, sl.unit_cost, sl.line_total, sl.name
        from sale_lines sl
        join s on s.id = sl.sale_id
    )
    select
        (select count(*) from s),
        coalesce((select sum(total) from s), 0),
        coalesce((select sum(quantity * unit_cost) from lines), 0),
        coalesce((select sum(line_total) from lines), 0)
            - coalesce((select sum(quantity * unit_cost) from lines), 0),
        coalesce((select sum(quantity) from lines), 0),
        case when (select count(*) from s) = 0 then 0
             else round(coalesce((select sum(total) from s), 0)
                  / (select count(*) from s), 2) end,
        (select count(distinct lower(btrim(name))) from lines);
end;
$$;

-- ------------------------------------------------------------
-- 2. Owner: what sells more or less, and how fast. One row per product name
--    sold in the window, ranked by revenue: units, revenue, margin, and a
--    velocity — units per day across the span it actually sold on, which is
--    the "how fast" the user asked for.
-- ------------------------------------------------------------
create or replace function org_product_performance(
    p_org_id uuid,
    p_since  timestamptz default null,
    p_limit  int default 100
)
returns table (
    name          text,
    units         numeric,
    revenue       numeric,
    margin        numeric,
    sale_count    bigint,
    first_sold    timestamptz,
    last_sold     timestamptz,
    per_day       numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;

    return query
    with lines as (
        select lower(btrim(sl.name)) as key,
               sl.name as raw_name,
               sl.quantity, sl.unit_cost, sl.line_total, sa.occurred_at
        from sale_lines sl
        join sales sa on sa.id = sl.sale_id
        where sa.org_id = p_org_id
          and sa.kind = 'sale'
          and (p_since is null or sa.occurred_at >= p_since)
    )
    select
        min(raw_name),
        sum(quantity),
        sum(line_total),
        sum(line_total) - sum(quantity * unit_cost),
        count(*),
        min(occurred_at),
        max(occurred_at),
        -- Units per day over the span it sold on; a product that sold within a
        -- single day counts its run as one day rather than dividing by zero.
        round(
            sum(quantity)
            / greatest(1, extract(epoch from (max(occurred_at) - min(occurred_at))) / 86400.0),
            2
        )
    from lines
    group by key
    order by 3 desc
    limit greatest(1, p_limit);
end;
$$;

-- ------------------------------------------------------------
-- 3. Owner: when. Revenue and count by hour of the day (0-23), so the owner
--    sees the hours the shop actually earns in.
-- ------------------------------------------------------------
create or replace function org_sales_by_hour(
    p_org_id uuid,
    p_since  timestamptz default null
)
returns table (
    hour        int,
    sale_count  bigint,
    revenue     numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;

    return query
    select
        extract(hour from sa.occurred_at)::int,
        count(*),
        coalesce(sum(sa.total), 0)
    from sales sa
    where sa.org_id = p_org_id
      and sa.kind = 'sale'
      and (p_since is null or sa.occurred_at >= p_since)
    group by 1
    order by 1;
end;
$$;

-- ------------------------------------------------------------
-- 4. Owner: when, the other axis. Revenue and count by day of week
--    (0 = Sunday .. 6 = Saturday, Postgres dow).
-- ------------------------------------------------------------
create or replace function org_sales_by_weekday(
    p_org_id uuid,
    p_since  timestamptz default null
)
returns table (
    dow         int,
    sale_count  bigint,
    revenue     numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;

    return query
    select
        extract(dow from sa.occurred_at)::int,
        count(*),
        coalesce(sum(sa.total), 0)
    from sales sa
    where sa.org_id = p_org_id
      and sa.kind = 'sale'
      and (p_since is null or sa.occurred_at >= p_since)
    group by 1
    order by 1;
end;
$$;

-- ------------------------------------------------------------
-- 5. Owner: the trend. Revenue and count per calendar day, for the line the
--    owner watches go up or down.
-- ------------------------------------------------------------
create or replace function org_sales_daily(
    p_org_id uuid,
    p_since  timestamptz default null
)
returns table (
    day         date,
    sale_count  bigint,
    revenue     numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;

    return query
    select
        (sa.occurred_at at time zone 'UTC')::date,
        count(*),
        coalesce(sum(sa.total), 0)
    from sales sa
    where sa.org_id = p_org_id
      and sa.kind = 'sale'
      and (p_since is null or sa.occurred_at >= p_since)
    group by 1
    order by 1;
end;
$$;

-- ------------------------------------------------------------
-- 6. Platform: every business, side by side. One row per org — its name,
--    profile, revenue, margin, sale count, last sale — for the console.
--    SECURITY DEFINER, platform admin only, crosses RLS on purpose.
-- ------------------------------------------------------------
create or replace function platform_business_performance(
    p_since timestamptz default null
)
returns table (
    org_id      uuid,
    org_name    text,
    profile     text,
    sale_count  bigint,
    revenue     numeric,
    margin      numeric,
    units       numeric,
    last_sale   timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles
                   where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can read cross-business analytics';
    end if;

    return query
    with line_agg as (
        select sa.org_id,
               sum(sl.line_total)              as revenue_lines,
               sum(sl.quantity * sl.unit_cost) as cost_lines,
               sum(sl.quantity)                as units
        from sales sa
        join sale_lines sl on sl.sale_id = sa.id
        where sa.kind = 'sale'
          and (p_since is null or sa.occurred_at >= p_since)
        group by sa.org_id
    ),
    sale_agg as (
        select sa.org_id,
               count(*)            as sale_count,
               sum(sa.total)       as revenue,
               max(sa.occurred_at) as last_sale
        from sales sa
        where sa.kind = 'sale'
          and (p_since is null or sa.occurred_at >= p_since)
        group by sa.org_id
    )
    select
        o.id,
        o.name,
        o.profile,
        coalesce(sag.sale_count, 0),
        coalesce(sag.revenue, 0),
        coalesce(lag.revenue_lines, 0) - coalesce(lag.cost_lines, 0),
        coalesce(lag.units, 0),
        sag.last_sale
    from orgs o
    left join sale_agg sag on sag.org_id = o.id
    left join line_agg lag on lag.org_id = o.id
    where o.archived_at is null
    order by coalesce(sag.revenue, 0) desc;
end;
$$;

-- ------------------------------------------------------------
-- 7. Platform: the one-line total across the whole platform.
-- ------------------------------------------------------------
create or replace function platform_analytics_headline(
    p_since timestamptz default null
)
returns table (
    businesses        bigint,
    active_businesses bigint,
    sale_count        bigint,
    revenue           numeric,
    margin            numeric
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles
                   where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can read platform analytics';
    end if;

    return query
    with s as (
        select sa.id, sa.org_id, sa.total
        from sales sa
        where sa.kind = 'sale'
          and (p_since is null or sa.occurred_at >= p_since)
    ),
    lines as (
        select sl.quantity, sl.unit_cost, sl.line_total
        from sale_lines sl
        join s on s.id = sl.sale_id
    )
    select
        (select count(*) from orgs where archived_at is null),
        (select count(distinct org_id) from s),
        (select count(*) from s),
        coalesce((select sum(total) from s), 0),
        coalesce((select sum(line_total) from lines), 0)
            - coalesce((select sum(quantity * unit_cost) from lines), 0);
end;
$$;

-- Guarded because the migration runs before any test creates the role, and on
-- a fresh cluster `authenticated` (a Supabase-managed role) does not exist yet
-- — every grant in this schema is wrapped this way for the same reason.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function org_sales_headline(uuid, timestamptz)           to authenticated;
        grant execute on function org_product_performance(uuid, timestamptz, int) to authenticated;
        grant execute on function org_sales_by_hour(uuid, timestamptz)            to authenticated;
        grant execute on function org_sales_by_weekday(uuid, timestamptz)         to authenticated;
        grant execute on function org_sales_daily(uuid, timestamptz)              to authenticated;
        grant execute on function platform_business_performance(timestamptz)      to authenticated;
        grant execute on function platform_analytics_headline(timestamptz)        to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
