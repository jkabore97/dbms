-- ============================================================
-- 015_product_serial.sql — the field M5 asked for and 011 did not build.
--
-- The plan's product list is "name, serial, barcode, expiry, cost, price,
-- quantity, photos". 011 built `sku` and called that close enough. It is not:
-- a SKU is the shop's own code for a *kind* of thing and there is one per
-- product, while a serial number identifies *one physical unit* and matters
-- for exactly the goods Esperance sells at the top of her range — a phone, a
-- radio, a solar panel. It is what a customer's warranty claim is looked up
-- by, and what a theft is reported with.
--
-- Kept as a nullable column beside `sku` rather than replacing it, because
-- most of what a shop sells has neither and both are already true of the rows
-- that exist.
--
-- Not made unique. Two units of the same model can arrive with the same
-- number printed badly, OCR reads a 0 as an 8, and a shopkeeper typing at a
-- counter should not be stopped by a constraint over a field nobody is
-- required to fill in. The index exists so it can be searched, which is the
-- thing it is actually for.
-- ============================================================

alter table products add column if not exists serial text;

comment on column products.serial is
    'The serial number of one physical unit — a phone, a radio, a panel. Not unique on purpose: a mistyped duplicate must not block a sale.';

create index if not exists products_by_serial
    on products (org_id, serial) where serial is not null;

-- Finding a unit by the number on its back, which is how a warranty claim
-- arrives: somebody at the counter holding the thing. Matches on a trimmed,
-- case-insensitive prefix, the same way a person reads one out.
create or replace function product_by_serial(p_org_id uuid, p_serial text)
returns table (
    id         uuid,
    name       text,
    serial     text,
    sale_price numeric,
    quantity   numeric
)
language sql
stable
security invoker
set search_path = public
as $$
    select p.id, p.name, p.serial, p.sale_price, p.quantity
    from products p
    where p.org_id = p_org_id
      and p.serial is not null
      and lower(btrim(p.serial)) like lower(btrim(coalesce(p_serial, ''))) || '%'
    order by p.name
    limit 20;
$$;

-- ------------------------------------------------------------
-- The photographs of a product
-- ------------------------------------------------------------
-- `documents.product_id` has existed since 013 and nothing read it back the
-- other way round. The plan's product list ends with "photos", and this is
-- what makes that true: the delivery note a thing arrived on, and the picture
-- of the thing itself, reachable from the product rather than only from the
-- gallery.
--
-- Security invoker, like every other read here: 006 decides who may see a
-- document, and an observer entitled to totals is not entitled to the
-- paperwork behind them. A definer would hand it to them.
create or replace function product_photos(p_product_id uuid, p_limit int default 20)
returns table (
    id           uuid,
    r2_key       text,
    kind         text,
    caption      text,
    content_type text,
    captured_at  timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
    select d.id, d.r2_key, d.kind, d.caption, d.content_type,
           coalesce(d.captured_at, d.created_at)
    from documents d
    where d.product_id = p_product_id
    order by coalesce(d.captured_at, d.created_at) desc
    limit greatest(coalesce(p_limit, 20), 1);
$$;

-- ------------------------------------------------------------
-- Setting it
-- ------------------------------------------------------------
-- `update_product` in the app writes sale_price, cost_price, expiry and the
-- reorder point straight through RLS. The serial goes the same way and needs
-- no function of its own — the update policy from 011 already says who may
-- change a product. This exists only so `ensure_product` can carry one in
-- from a scan or a reading, which is the moment it is actually known.
create or replace function set_product_serial(
    p_product_id uuid,
    p_serial     text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor  uuid := auth.uid();
    v_org_id uuid;
begin
    if v_actor is null then
        raise exception 'set_product_serial() needs a signed-in caller';
    end if;

    select org_id into v_org_id from products where id = p_product_id;
    if not found then
        raise exception 'No such product';
    end if;

    if not can_write_org(v_org_id) then
        raise exception 'You cannot change products in this business';
    end if;

    update products
       set serial = nullif(btrim(coalesce(p_serial, '')), '')
     where id = p_product_id;

    return p_product_id;
end;
$$;

-- ------------------------------------------------------------
-- GRANTS
-- ------------------------------------------------------------
revoke execute on function set_product_serial(uuid, text) from public;

-- `authenticated` is a Supabase role and does not exist on a bare Postgres.
-- Roles are cluster-wide, so a developer whose cluster has ever run a suite
-- already has it and cannot reproduce the failure by making a fresh database
-- — which is how 013 shipped this wrong once.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_product_serial(uuid, text) to authenticated;
        grant execute on function product_by_serial(uuid, text) to authenticated;
        grant execute on function product_photos(uuid, int) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
