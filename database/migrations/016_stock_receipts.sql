-- ============================================================
-- 016_stock_receipts.sql — a delivery, recorded once.
--
-- Found by test_delivery.sql while building the photograph-to-stock flow, and
-- it is worse than an ordinary duplicate.
--
-- `receive_products()` already passed its `client_uuid` down to
-- `record_entry()`, so a retried delivery posted its money exactly once. But
-- the line above it —
--
--     update products set quantity = quantity + p_quantity
--
-- ran unconditionally. So pressing "add to stock" a second time after a
-- connection dropped added the goods again and the money not at all. The
-- count and the books then disagree by exactly one delivery, in the direction
-- that makes the shop look like it has stock it does not have, and nothing on
-- any screen says so. A plain double-entry would at least have been visible
-- in the ledger.
--
-- The confirm screen mints one client_uuid per line and keeps it across
-- retries precisely so this is safe. It was not.
--
-- The fix also closes something 011 claimed and did not do. Its own header
-- says of `products.quantity`: "Every movement is still recorded in
-- `sale_lines`, so the column can be rebuilt from history if it ever drifts."
-- That is true of sales and returns and was never true of deliveries — stock
-- arriving was recorded nowhere except as an expense in the ledger, which
-- does not carry a count. `stock_receipts` is what makes the sentence true.
-- ============================================================

create table if not exists stock_receipts (
    id           uuid primary key default gen_random_uuid(),
    org_id       uuid not null references orgs(id) on delete cascade,
    product_id   uuid not null references products(id) on delete cascade,
    quantity     numeric(14,3) not null check (quantity > 0),
    unit_cost    numeric(14,2) not null default 0 check (unit_cost >= 0),
    expires_on   date,
    -- The purchase this delivery posted, when it posted one. Null for stock
    -- received on credit or with no cost recorded, which still moves goods.
    entry_id     uuid references journal_entries(id),
    client_uuid  uuid,
    device_id    text,
    received_at  timestamptz not null default now(),
    received_by  uuid references profiles(id)
);

-- The whole point. One delivery per client_uuid per shop, however many times
-- the phone sends it.
create unique index if not exists stock_receipts_by_client_uuid
    on stock_receipts (org_id, client_uuid) where client_uuid is not null;

create index if not exists stock_receipts_by_product
    on stock_receipts (product_id, received_at desc);

comment on table stock_receipts is
    'Stock arriving, append-only. Makes products.quantity rebuildable and makes a retried delivery count once.';

-- ------------------------------------------------------------
-- receive_products, made re-runnable
-- ------------------------------------------------------------
-- Same signature and same behaviour for a first call. The only difference is
-- that a second call carrying a client_uuid this shop has already seen
-- returns the original entry and touches nothing.
create or replace function receive_products(
    p_org_id      uuid,
    p_product_id  uuid,
    p_quantity    numeric,
    p_unit_cost   numeric     default null,
    p_expires_on  date        default null,
    p_method      text        default 'cash',
    p_client_uuid uuid        default null,
    p_device_id   text        default null,
    p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_name     text;
    v_cost     numeric;
    v_entry    uuid;
    v_existing stock_receipts%rowtype;
begin
    if p_quantity is null or p_quantity <= 0 then
        raise exception 'A delivery needs a quantity';
    end if;

    -- Before anything is moved. Checked against stock_receipts rather than
    -- journal_entries because a delivery with no cost posts no entry, and
    -- half an idempotency guarantee is the kind of thing that is discovered
    -- by a shopkeeper rather than by a test.
    if p_client_uuid is not null then
        select * into v_existing from stock_receipts
        where org_id = p_org_id and client_uuid = p_client_uuid;
        if found then
            return v_existing.entry_id;
        end if;
    end if;

    select name, cost_price into v_name, v_cost
    from products where id = p_product_id and org_id = p_org_id;

    if v_name is null then
        raise exception 'No such product in this business';
    end if;

    v_cost := coalesce(p_unit_cost, v_cost, 0);

    update products set
        quantity   = quantity + p_quantity,
        cost_price = case when p_unit_cost is not null then p_unit_cost
                          else cost_price end,
        expires_on = coalesce(p_expires_on, expires_on)
    where id = p_product_id;

    -- Only money that actually moved gets a ledger entry. Stock received on
    -- credit, or with no cost recorded, still updates the count.
    if v_cost > 0 then
        v_entry := record_entry(
            p_org_id      => p_org_id,
            p_amount      => v_cost * p_quantity,
            p_direction   => 'out',
            p_label       => 'Achat de marchandise',
            p_recorded_by => v_actor,
            p_category    => 'Achats de marchandises',
            p_method      => p_method,
            p_memo        => v_name,
            p_details     => jsonb_build_object('product', v_name,
                                                'quantity', p_quantity),
            p_client_uuid => p_client_uuid,
            p_device_id   => p_device_id,
            p_occurred_at => p_occurred_at
        );
    end if;

    insert into stock_receipts (
        org_id, product_id, quantity, unit_cost, expires_on,
        entry_id, client_uuid, device_id, received_at, received_by
    )
    values (
        p_org_id, p_product_id, p_quantity, v_cost, p_expires_on,
        v_entry, p_client_uuid, p_device_id, p_occurred_at, v_actor
    );

    return v_entry;
end;
$$;

-- ------------------------------------------------------------
-- What arrived, and when
-- ------------------------------------------------------------
-- Security invoker: a delivery is a purchase, and 006 already decided that an
-- observer entitled to totals is not entitled to the line items behind them.
--
-- Dropped before creating so the bundle stays re-runnable: 042 later adds a
-- column to this function's return type, and on a second pass of the bundle
-- this create-or-replace would otherwise meet that wider shape and fail with
-- "cannot change return type". The drop makes the two definitions agree to
-- disagree in order.
drop function if exists recent_deliveries(uuid, int);
create or replace function recent_deliveries(
    p_org_id uuid,
    p_limit  int default 50
)
returns table (
    id           uuid,
    product_id   uuid,
    product_name text,
    quantity     numeric,
    unit_cost    numeric,
    line_total   numeric,
    received_at  timestamptz,
    received_by  text
)
language sql
stable
security invoker
set search_path = public
as $$
    select r.id, r.product_id, p.name, r.quantity, r.unit_cost,
           r.quantity * r.unit_cost, r.received_at, pr.full_name
    from stock_receipts r
    join products p on p.id = r.product_id
    left join profiles pr on pr.id = r.received_by
    where r.org_id = p_org_id
    order by r.received_at desc, r.id desc
    limit greatest(coalesce(p_limit, 50), 1);
$$;

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
alter table stock_receipts enable row level security;

-- Readable by anyone entitled to the entries behind it, written by anyone who
-- may record — the same pair as `sales` in 011. No update and no delete
-- policy at all: a delivery that can be edited is a count nobody can trust,
-- and correcting one is another movement rather than a rewrite.
drop policy if exists "deliveries readable with full visibility" on stock_receipts;
create policy "deliveries readable with full visibility"
on stock_receipts for select
using (has_full_visibility(org_id));

drop policy if exists "deliveries written by staff" on stock_receipts;
create policy "deliveries written by staff"
on stock_receipts for insert
with check (can_write_org(org_id));

-- ------------------------------------------------------------
-- GRANTS
-- ------------------------------------------------------------
revoke execute on function receive_products(uuid, uuid, numeric, numeric, date, text, uuid, text, timestamptz) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function receive_products(uuid, uuid, numeric, numeric, date, text, uuid, text, timestamptz) to authenticated;
        grant execute on function recent_deliveries(uuid, int) to authenticated;
        grant select, insert on stock_receipts to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
