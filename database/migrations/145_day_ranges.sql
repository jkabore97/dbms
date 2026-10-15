-- ============================================================
-- 145_day_ranges.sql — batch 149: a shop's day read by its index, on its
-- own clock; an item's newest photo found by an index.
--
--   1. AN ITEM'S PHOTOS. product_cover_key, item_gallery_keys and
--      product_gallery (136), search_products, storefront_products and
--      storefront_previews (136, through product_cover_key) and
--      vitrine_score (100) all ask « this item's newest photo »:
--          where d.product_id = $1 … order by coalesce(d.captured_at,
--          d.created_at) desc limit 1
--      and documents had no index on product_id at all (013's are by org,
--      by capture date, by the unfiled queue): every card of the street
--      read every document of the business, or of the whole table. The
--      new index is that expression, partial on product_id is not null
--      (most documents — receipts, invoices — are about no item).
--
--   2. store_day READ BY ITS INDEX. 011's store_day kept a day with
--          (s.occurred_at at time zone 'UTC')::date = p_on
--      on sales and again in its sale_lines subquery: an expression the
--      sales_by_day index (org_id, occurred_at desc) cannot serve, so the
--      shop's home read every sale the shop ever made, twice, to add up
--      one day. The day is now a range on occurred_at itself —
--          occurred_at >= start of day and occurred_at < start of next day
--      — the same rows, read from the index. The two-argument
--      store_day(uuid, date) keeps its signature, its SECURITY INVOKER (the
--      policies on sales still decide what is added up), its pinned
--      search_path, its grants (create or replace keeps them) and its
--      answer: the UTC calendar day, as before (test_batch145 compares it,
--      day by day, with 011's text).
--
--   3. WHOSE « TODAY ». The app sends the phone's own date (« today » where
--      the shop is), and store_day counted the UTC day of that date: a shop
--      at UTC+1 (Niamey, Douala, Kinshasa) saw a sale made at 00:30 on
--      yesterday's figures, and its last half hour of the evening… fine,
--      but its first hour after midnight on the wrong day. orgs has no time
--      zone, and the phone already knows its own; so a new door
--          store_day(p_org_id uuid, p_on date, p_utc_offset_minutes int)
--      takes the phone's UTC offset (DateTime.timeZoneOffset, minutes east
--      of UTC, −14 h to +14 h) and counts p_on from local midnight to local
--      midnight. An older app keeps calling the two-argument door and gets
--      the UTC day exactly as before; the app falls back to it while 145 is
--      not live (RetailRepository.day). No argument has a default, so a
--      call naming two arguments can only mean the old door.
--      Born closed to anon and PUBLIC (063), granted to authenticated —
--      the till's home, signed in.
--
--   The farm and the association: their homes count the day on the phone
--   itself (LocalDb.farmDay / dayTotals / entriesForDay, local dates) and
--   call no server « day » function, so they have nothing to fix here.
--   farm_daily_summary (009) has the same UTC-date shape but nothing in
--   the app calls it; it is left as it is.
--
-- Re-runnable: create index if not exists, create or replace, grants
-- repeated.
-- ============================================================

-- ------------------------------------------------------------
-- 1. An item's newest photo
-- ------------------------------------------------------------
create index if not exists documents_by_product
    on documents (product_id, (coalesce(captured_at, created_at)) desc)
    where product_id is not null;

-- ------------------------------------------------------------
-- 2 and 3. The day of a shop
-- ------------------------------------------------------------
-- The local day p_on, at p_utc_offset_minutes east of UTC, from its
-- midnight to the next one, read off sales_by_day.
create or replace function store_day(
    p_org_id             uuid,
    p_on                 date,
    p_utc_offset_minutes int
)
returns table (
    sales_total   numeric,
    returns_total numeric,
    net_sales     numeric,
    sale_count    int,
    items_sold    numeric
)
language plpgsql
stable
security invoker
set search_path = public, auth
as $$
declare
    v_from timestamptz;
    v_to   timestamptz;
begin
    if p_utc_offset_minutes is null
       or p_utc_offset_minutes not between -840 and 840 then
        raise exception 'Décalage horaire invalide : %', p_utc_offset_minutes
            using errcode = '22023';
    end if;
    -- Local midnight is UTC midnight minus the offset (UTC+1: 23:00 UTC
    -- the day before).
    v_from := (p_on::timestamp - make_interval(mins => p_utc_offset_minutes))
                  at time zone 'UTC';
    v_to   := v_from + interval '1 day';

    return query
    select
        coalesce(sum(s.total) filter (where s.kind = 'sale'), 0),
        coalesce(sum(s.total) filter (where s.kind = 'return'), 0),
        coalesce(sum(s.total) filter (where s.kind = 'sale'), 0)
          - coalesce(sum(s.total) filter (where s.kind = 'return'), 0),
        (count(*) filter (where s.kind = 'sale'))::int,
        coalesce((
            select sum(l.quantity)
            from sales s2
            join sale_lines l on l.sale_id = s2.id
            where s2.org_id = p_org_id
              and s2.kind = 'sale'
              and s2.occurred_at >= v_from
              and s2.occurred_at <  v_to
        ), 0)
    from sales s
    where s.org_id = p_org_id
      and s.occurred_at >= v_from
      and s.occurred_at <  v_to;
end;
$$;

-- 011's door: the UTC day, as before, now by the range. Its own body
-- rather than a call to the door above: that one is closed to anon and
-- PUBLIC, this one keeps whatever it was granted (an anonymous caller
-- still gets zeros through the policies, never « permission denied »).
create or replace function store_day(
    p_org_id uuid,
    p_on     date default current_date
)
returns table (
    sales_total   numeric,
    returns_total numeric,
    net_sales     numeric,
    sale_count    int,
    items_sold    numeric
)
language sql
stable
security invoker
set search_path = public, auth
as $$
    select
        coalesce(sum(s.total) filter (where s.kind = 'sale'), 0),
        coalesce(sum(s.total) filter (where s.kind = 'return'), 0),
        coalesce(sum(s.total) filter (where s.kind = 'sale'), 0)
          - coalesce(sum(s.total) filter (where s.kind = 'return'), 0),
        (count(*) filter (where s.kind = 'sale'))::int,
        coalesce((
            select sum(l.quantity)
            from sales s2
            join sale_lines l on l.sale_id = s2.id
            where s2.org_id = p_org_id
              and s2.kind = 'sale'
              and s2.occurred_at >= (p_on::timestamp at time zone 'UTC')
              and s2.occurred_at <  ((p_on + 1)::timestamp at time zone 'UTC')
        ), 0)
    from sales s
    where s.org_id = p_org_id
      and s.occurred_at >= (p_on::timestamp at time zone 'UTC')
      and s.occurred_at <  ((p_on + 1)::timestamp at time zone 'UTC');
$$;

revoke execute on function store_day(uuid, date, int) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function store_day(uuid, date, int) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function store_day(uuid, date, int) to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function store_day(uuid, date, int) to service_role;
    end if;
end $$;
