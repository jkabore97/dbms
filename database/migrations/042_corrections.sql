-- ============================================================
-- 042_corrections.sql — undo a transaction the honest way: a reversal, not a
-- deletion.
--
-- The report: a shop was tested with a few sales and purchases; deleting the
-- article afterwards left the money in the books, because deleting a product
-- (archive_product) only takes it off the shelf and never touches the ledger.
-- That is correct — history is permanent here — but it left no sanctioned way
-- to undo a transaction, so the only tool reached for was the wrong one.
--
-- The right tool is a reversal: a compensating movement, dated now, that
-- cancels the original in both places it lives — the stock count AND the
-- ledger — so accounting, analysis and reports all correct themselves from
-- today rather than rewriting the past. A sale already has one (record_return,
-- 011). A manual entry already has one (reverse_entry, 002). The gap is a
-- delivery: stock_receipts is append-only with no reversal at all. This adds
-- it, and the two read functions the corrections screen lists from.
-- ============================================================

-- A delivery can now carry the mark of its own reversal. Not an edit of the
-- delivery — the quantity and cost it recorded stay exactly as they were — a
-- stamp that says "a compensating movement has cancelled this", so it cannot
-- be reversed twice and the screen can show it struck through.
alter table stock_receipts
    add column if not exists reversed_at timestamptz;
alter table stock_receipts
    add column if not exists reversed_by uuid references profiles(id);

-- reverse_receipt: put a delivery back the way it came in.
--
-- Owner/admin only — the same posture as archiving a product. A clerk records
-- deliveries and returns at the counter; unwinding a purchase after the fact
-- is a correction, and corrections belong to whoever answers for the books.
create or replace function reverse_receipt(
    p_receipt_id uuid,
    p_reason     text default null
)
returns uuid  -- the reversing ledger entry, or null when the delivery booked none
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
    v_rec   stock_receipts%rowtype;
    v_rev   uuid;
begin
    if v_actor is null then
        raise exception 'reverse_receipt() needs a signed-in caller';
    end if;

    select * into v_rec from stock_receipts where id = p_receipt_id;
    if v_rec.id is null then
        raise exception 'No such delivery';
    end if;

    if not is_org_admin(v_rec.org_id) then
        raise exception 'Only an owner or admin can reverse a delivery';
    end if;

    if v_rec.reversed_at is not null then
        raise exception 'That delivery has already been reversed';
    end if;

    -- Take back exactly what this delivery added. Stock may go negative, as it
    -- may on a sale (011): a reversal that drives the count below zero is the
    -- true statement that the goods have since moved, not a reason to refuse.
    update products set quantity = quantity - v_rec.quantity
     where id = v_rec.product_id;

    -- Unwind the purchase in the books, if it posted one. reverse_entry swaps
    -- the debits and credits into a new entry dated now, so the correction
    -- lands in the current period and every report built on the ledger nets
    -- to zero without excluding anything.
    if v_rec.entry_id is not null then
        v_rev := reverse_entry(v_rec.entry_id, v_actor,
                               coalesce(p_reason, 'Correction'));
    end if;

    update stock_receipts
       set reversed_at = now(), reversed_by = v_actor
     where id = p_receipt_id;

    return v_rev;
end;
$$;

-- recent_deliveries, now carrying whether each has been reversed, so the
-- corrections screen can strike the undone ones through and hide their button.
-- Otherwise 016 verbatim. Dropped first: adding a column to the returned table
-- changes the return type, which `create or replace` cannot do.
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
    received_by  text,
    reversed     boolean
)
language sql
stable
security invoker
set search_path = public
as $$
    select r.id, r.product_id, p.name, r.quantity, r.unit_cost,
           r.quantity * r.unit_cost, r.received_at, pr.full_name,
           r.reversed_at is not null
    from stock_receipts r
    join products p on p.id = r.product_id
    left join profiles pr on pr.id = r.received_by
    where r.org_id = p_org_id
    order by r.received_at desc, r.id desc
    limit greatest(coalesce(p_limit, 50), 1);
$$;

-- recent_sales: the other half of the corrections screen. One row per sale,
-- newest first, carrying what a person needs to recognise it and whether it
-- has already been returned. Security invoker and gated on full visibility,
-- the same rule sales themselves read under (011): the money is a line item,
-- not a total.
create or replace function recent_sales(
    p_org_id uuid,
    p_limit  int default 50
)
returns table (
    id          uuid,
    kind        text,
    method      text,
    total       numeric,
    note        text,
    occurred_at timestamptz,
    sold_by     text,
    reversed    boolean
)
language sql
stable
security invoker
set search_path = public
as $$
    select s.id, s.kind, s.method, s.total, s.note, s.occurred_at, pr.full_name,
           exists (select 1 from sales r where r.reverses_id = s.id)
    from sales s
    left join profiles pr on pr.id = s.recorded_by
    where s.org_id = p_org_id
      and s.kind <> 'return'
    order by s.occurred_at desc, s.id desc
    limit greatest(coalesce(p_limit, 50), 1);
$$;

-- ------------------------------------------------------------
-- GRANTS
-- ------------------------------------------------------------
revoke execute on function reverse_receipt(uuid, text) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function reverse_receipt(uuid, text) to authenticated;
        grant execute on function recent_sales(uuid, int) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
