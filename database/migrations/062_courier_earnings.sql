-- ============================================================
-- 062_courier_earnings.sql — what the courier has earned, at a glance.
--
-- The single most motivating screen in every courier app is the one that
-- says what today paid. Three rows — today, this week, this month — each
-- with the courses delivered, the fees they carried (061) and the
-- kilometres ridden (shop pin to door pin, the distance the fee was
-- priced on). Read by the courier about themselves alone: the function
-- runs as its definer but filters on auth.uid(), and refuses anyone who
-- is not an approved courier, like every other courier read (056).
--
-- "Delivered" is the status the courier set, and updated_at is when they
-- set it (056 stamps it on every status move), so a course counts on the
-- day it was finished, not the day it was ordered. Days are Ouagadougou
-- days, not UTC ones: a course at 23:30 belongs to the evening it was
-- ridden.
-- ============================================================

create or replace function courier_earnings()
returns table (
    period   text,
    courses  int,
    fees     numeric,
    km       double precision
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_now   timestamptz := now();
    v_today date := (v_now at time zone 'Africa/Ouagadougou')::date;
begin
    perform assert_approved_courier();
    return query
    with done as (
        select o.delivery_fee,
               case when g.lat is null or o.drop_lat is null then null
                    else distance_km(g.lat, g.lng, o.drop_lat, o.drop_lng) end as km,
               (o.updated_at at time zone 'Africa/Ouagadougou')::date as day
          from orders o
          join orgs g on g.id = o.org_id
         where o.courier_id = auth.uid()
           and o.status = 'delivered'
    ),
    spans as (
        select 'today' as period, v_today as since
        union all select 'week',  v_today - ((extract(isodow from v_today)::int) - 1)
        union all select 'month', date_trunc('month', v_today)::date
    )
    select s.period,
           count(d.day)::int,
           coalesce(sum(d.delivery_fee), 0)::numeric,
           coalesce(sum(d.km), 0)::double precision
      from spans s
      left join done d on d.day >= s.since and d.day <= v_today
     group by s.period, s.since
     order by s.since desc;
end;
$$;

revoke execute on function courier_earnings() from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function courier_earnings() to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
