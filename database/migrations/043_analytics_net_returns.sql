-- ============================================================
-- 043_analytics_net_returns.sql — a corrected sale leaves the analytics.
--
-- The report: an owner reversed a sale in the corrections screen and the
-- analytics did not move — "they are not connected". They were not: every
-- function in 036 filters `kind = 'sale'` and stops there, so it counts the
-- original sale and ignores the `kind = 'return'` row that cancels it. The
-- ledger nets a reversal (reverse_entry posts a compensating entry) and the
-- day total nets it (store_day subtracts returns), but the analytics — what
-- sells, the revenue, the trend, the busy hours — did not.
--
-- record_return reverses a sale in full (it copies every line and sets
-- reverses_id), so there is no partial return to reason about: a reversed sale
-- is entirely cancelled. The fix is therefore one predicate, added to each
-- function's `kind = 'sale'` filter — drop any sale that has a reversal:
--
--     and not exists (select 1 from sales r where r.reverses_id = sa.id)
--
-- Bodies are 036 verbatim apart from that one added line. No return type
-- changes, so a plain create-or-replace stands.
-- ============================================================

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
          and not exists (select 1 from sales r where r.reverses_id = sa.id)
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
          and not exists (select 1 from sales r where r.reverses_id = sa.id)
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
      and not exists (select 1 from sales r where r.reverses_id = sa.id)
      and (p_since is null or sa.occurred_at >= p_since)
    group by 1
    order by 1;
end;
$$;

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
      and not exists (select 1 from sales r where r.reverses_id = sa.id)
      and (p_since is null or sa.occurred_at >= p_since)
    group by 1
    order by 1;
end;
$$;

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
      and not exists (select 1 from sales r where r.reverses_id = sa.id)
      and (p_since is null or sa.occurred_at >= p_since)
    group by 1
    order by 1;
end;
$$;

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
          and not exists (select 1 from sales r where r.reverses_id = sa.id)
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
          and not exists (select 1 from sales r where r.reverses_id = sa.id)
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
          and not exists (select 1 from sales r where r.reverses_id = sa.id)
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

notify pgrst, 'reload schema';
