-- ============================================================
-- 067_delivery_share.sql — the platform's part of a delivery fee.
--
-- M10 block 4. The second revenue stream, and the one that fits the market
-- better than any subscription: pay when you earned. Every delivery carries
-- a fee fixed at order time (061); from now on a share of that fee is the
-- platform's, also fixed at order time, stored beside it. Nothing moves
-- here — the customer still pays the courier at the door — so the share is
-- a debt the courier settles monthly, by Wave, from a report the console
-- prints. Once money moves through the platform (M9), the same column is
-- what gets kept before the rest is paid out.
--
-- The rules:
--   * The share is a percentage in platform_settings (delivery_share_pct,
--     10 to start). Changing it changes the next order, never an order
--     already placed: what was agreed is what is owed.
--   * Computed by a trigger on orders, so every path that sets a fee —
--     place_order today, whatever comes later — carries the share without
--     being rewritten. A pickup has no fee and no share.
--   * Orders placed before this migration keep a share of zero. The
--     couriers were paid in full for them; a cut invented after the fact
--     would be a cut nobody agreed to.
--   * The courier's tally (062) shows the share and the net beside the
--     fees, so what they keep is never a surprise on settlement day.
--   * The settlement is one platform-only read, per courier, per month.
-- ============================================================

insert into platform_settings (key, value) values
    ('delivery_share_pct', '10')
on conflict (key) do nothing;

alter table orders add column if not exists platform_fee numeric(12, 2) not null default 0;
alter table orders drop constraint if exists orders_platform_fee_nonneg;
alter table orders add constraint orders_platform_fee_nonneg check (platform_fee >= 0);

comment on column orders.platform_fee is
    'The platform''s share of delivery_fee, fixed when the fee was (067). '
    'Zero for a pickup and for orders placed before 067. Settled monthly by '
    'the courier until money moves through the platform.';

-- Fixed with the fee, whole francs. Only when the fee itself is set or
-- changed: a status move, a courier taking the job, a payment landing —
-- none of those touch the share.
create or replace function trg_order_platform_fee()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    new.platform_fee := case
        when new.delivery_fee is null or new.delivery_fee <= 0 then 0
        else round(new.delivery_fee * plan_limit('delivery_share_pct', 10) / 100.0)
    end;
    return new;
end;
$$;

drop trigger if exists order_platform_fee on orders;
create trigger order_platform_fee
before insert or update of delivery_fee on orders
for each row execute function trg_order_platform_fee();

-- The courier's tally grows two columns: the platform's share of those
-- fees, and what is left. 062 verbatim otherwise; the return type changes,
-- so it is dropped and recreated.
drop function if exists courier_earnings();

create function courier_earnings()
returns table (
    period   text,
    courses  int,
    fees     numeric,
    km       double precision,
    share    numeric,
    net      numeric
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
        select o.delivery_fee, o.platform_fee,
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
           coalesce(sum(d.km), 0)::double precision,
           coalesce(sum(d.platform_fee), 0)::numeric,
           (coalesce(sum(d.delivery_fee), 0) - coalesce(sum(d.platform_fee), 0))::numeric
      from spans s
      left join done d on d.day >= s.since and d.day <= v_today
     group by s.period, s.since
     order by s.since desc;
end;
$$;

-- What each courier owes for one month: the courses they delivered in it
-- (on the day they finished them, Ouagadougou days), the fees those
-- carried, the platform's share of them, and what they kept. Platform
-- only. Null month = the current one.
create or replace function platform_delivery_settlement(p_month date default null)
returns table (
    courier_id uuid,
    name       text,
    phone      text,
    courses    int,
    fees       numeric,
    share      numeric,
    net        numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_from date := date_trunc('month',
        coalesce(p_month, (now() at time zone 'Africa/Ouagadougou')::date))::date;
    v_to   date := (v_from + interval '1 month')::date;
begin
    if not exists (select 1 from profiles
                    where profiles.id = auth.uid() and profiles.is_platform_admin) then
        raise exception 'Only the platform reads the settlement';
    end if;
    return query
    select c.user_id,
           coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                    nullif(btrim(coalesce(p.full_name, '')), ''),
                    'Sans nom'),
           c.phone,
           count(o.id)::int,
           coalesce(sum(o.delivery_fee), 0)::numeric,
           coalesce(sum(o.platform_fee), 0)::numeric,
           (coalesce(sum(o.delivery_fee), 0) - coalesce(sum(o.platform_fee), 0))::numeric
      from couriers c
      join profiles p on p.id = c.user_id
      join orders o on o.courier_id = c.user_id
                   and o.status = 'delivered'
                   and (o.updated_at at time zone 'Africa/Ouagadougou')::date >= v_from
                   and (o.updated_at at time zone 'Africa/Ouagadougou')::date <  v_to
     group by c.user_id, p.first_name, p.last_name, p.full_name, c.phone
    having coalesce(sum(o.delivery_fee), 0) > 0
     order by 6 desc, 2;
end;
$$;

-- plan_terms() says the share too, so the console field and the courier
-- screen read the same number. 066 verbatim plus one key; same return
-- type, so replaced in place.
create or replace function plan_terms()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'pro_features',            coalesce(plan_setting('pro_features'), '[]'::jsonb),
        'free_max_staff',          plan_limit('free_max_staff', 3),
        'free_max_invoices_month', plan_limit('free_max_invoices_month', 20),
        'free_max_photos',         plan_limit('free_max_photos', 50),
        'free_history_months',     plan_limit('free_history_months', 12),
        'pro_price_month',         plan_limit('pro_price_month', 2500),
        'pro_price_year',          plan_limit('pro_price_year', 25000),
        'pro_currency',            coalesce(plan_setting('pro_currency') #>> '{}', 'XOF'),
        'platform_wave',           coalesce(plan_setting('platform_wave') #>> '{}', ''),
        'platform_wave_name',      coalesce(plan_setting('platform_wave_name') #>> '{}', ''),
        'delivery_share_pct',      plan_limit('delivery_share_pct', 10)
    );
$$;

revoke execute on function courier_earnings()                    from public;
revoke execute on function platform_delivery_settlement(date)    from public;
revoke execute on function trg_order_platform_fee()              from public;
revoke execute on function plan_terms()                          from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function courier_earnings()                 to authenticated;
        grant execute on function platform_delivery_settlement(date) to authenticated;
        grant execute on function plan_terms()                       to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
