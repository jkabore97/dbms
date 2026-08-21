-- ============================================================
-- 051_revive_product_on_readd.sql — re-adding a removed article brings it back.
--
-- Removing an article from the shop is a retire, not a delete: archive_product
-- (027) sets is_active = false and the row stays, because a hard delete would
-- orphan every past sale that references it. But the name stays claimed — the
-- products_by_name unique index (011) covers retired rows too — and
-- ensure_product, when it found the retired row by name, returned it without
-- reactivating it. So adding the same name again reappeared nowhere: the shelf
-- filters on is_active, and the product was still retired. To the shopkeeper it
-- looked like the name was permanently unusable.
--
-- The fix: when ensure_product lands on an existing row, reactivate it. For an
-- already-active product that is a no-op; for a retired one it is exactly the
-- intent — "add it again" brings the article back, with its history intact.
-- Nothing else about the function changes.
-- ============================================================

create or replace function ensure_product(
    p_org_id     uuid,
    p_name       text,
    p_sale_price numeric default null,
    p_cost_price numeric default null,
    p_barcode    text    default null,
    p_expires_on date    default null,
    p_actor      uuid    default null
)
returns uuid
language plpgsql
as $$
declare
    v_name text := btrim(coalesce(p_name, ''));
    v_id   uuid;
begin
    if v_name = '' then
        raise exception 'A product needs a name';
    end if;

    select id into v_id from products
    where org_id = p_org_id and lower(btrim(name)) = lower(v_name);

    if v_id is null then
        -- p_actor rather than auth.uid(): this runs as the caller, and the
        -- `authenticated` role has no rights in the auth schema. Every
        -- SECURITY DEFINER function that calls this passes the actor down,
        -- the same way ensure_item() works in 009.
        insert into products (org_id, name, sale_price, cost_price, barcode,
                              expires_on, created_by)
        values (p_org_id, v_name,
                coalesce(p_sale_price, 0), coalesce(p_cost_price, 0),
                p_barcode, p_expires_on, p_actor)
        returning id into v_id;
    else
        -- Only fill in what was missing. A price passed on a later sale must
        -- not silently rewrite the shelf price somebody set on purpose.
        --
        -- is_active is set to true unconditionally: re-adding a name is how a
        -- shopkeeper brings back an article they removed, and reviving the same
        -- row keeps its sales history rather than starting a second product
        -- with the same name. For a product that was never retired this
        -- changes nothing.
        update products set
            is_active  = true,
            sale_price = case when sale_price = 0 and p_sale_price is not null
                              then p_sale_price else sale_price end,
            cost_price = case when cost_price = 0 and p_cost_price is not null
                              then p_cost_price else cost_price end,
            barcode    = coalesce(barcode, p_barcode),
            expires_on = coalesce(expires_on, p_expires_on)
        where id = v_id;
    end if;

    return v_id;
end;
$$;

notify pgrst, 'reload schema';
