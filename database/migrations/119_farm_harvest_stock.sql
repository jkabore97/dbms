-- ============================================================
-- 119_farm_harvest_stock.sql — a harvest that goes into what the farm
-- sells (batch 115, builder W4: the farm's one-entry-at-a-time flows).
--
-- The owner's « Récolte »: crop, quantity, quality, « to stock or sold ».
-- 019's record_harvest() counts what came off the field and stops there
-- — on purpose, harvesting is not earning. But a farm's « À vendre »
-- articles (083) carry their own stock, and since 101 that stock never
-- goes below zero: tomatoes harvested and never counted onto the shelf
-- cannot be sold at the till or accepted from the vitrine. So the
-- harvest may now say where it goes.
--
--   record_harvest(…, p_to_stock boolean default false)
--     false (the default, and every older app): exactly 019 — the harvest
--       is counted, nothing else moves.
--     true: in the same transaction, the farm's article of that crop's
--       name (an article, never a service — a service of that name is
--       refused in French) gains the quantity. None yet: it is created
--       with the harvest's unit, price 0 and OFF the vitrine (P1: a
--       harvest never puts an unpriced article in front of the street —
--       the farmer prices it in « À vendre » and puts it on). An article
--       put away (archived) comes back, as ensure_product brings one back
--       (051); its price, photo and vitrine switch are left as they were.
--       An article counted in another unit is refused (« Tomate se vend
--       par plateau… ») rather than adding kilos to trays; the app asks
--       the quantity in the article's unit.
--     Still no ledger entry either way: no purchase is booked (a harvest
--       is not bought — receive_products would book one from the cost
--       price, which is why this does not go through it), and no income
--       (that is the sale's).
--     Idempotent by p_client_uuid as before: a phone that retries gets the
--       first harvest back and the shelf is not counted twice.
--   harvests.product_id: which article the harvest went to (null when it
--     did not), so a correction can find it.
--
-- Same signature plus one defaulted parameter, so 019's is dropped first
-- (two overloads would make every named call ambiguous). Security
-- definer as 019 — can_write_org() checked first, as before. Closed to
-- anon and PUBLIC (063), open to authenticated.
--
-- Kinds: a farm only (crop cycles exist only there). A shop and an
-- association never call it; nothing of theirs changes.
-- Re-runnable: the column if not exists, the old signature dropped if it
-- exists, the function replaced in place.
-- ============================================================

alter table harvests
    add column if not exists product_id uuid references products(id) on delete set null;

drop function if exists record_harvest(uuid, uuid, numeric, text, text, date, text, uuid, text);

create or replace function record_harvest(
    p_org_id        uuid,
    p_crop_cycle_id uuid,
    p_quantity      numeric,
    p_unit          text    default null,
    p_grade         text    default 'first',
    p_harvested_on  date    default current_date,
    p_note          text    default null,
    p_client_uuid   uuid    default null,
    p_device_id     text    default null,
    p_to_stock      boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_org      uuid;
    v_unit     text;
    v_crop     text;
    v_existing uuid;
    v_id       uuid;
    v_product  products%rowtype;
    v_product_id uuid;
begin
    if v_actor is null then
        raise exception 'record_harvest() needs a signed-in caller';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record for this business';
    end if;
    if p_quantity is null or p_quantity <= 0 then
        raise exception 'How much was harvested?';
    end if;

    if p_client_uuid is not null then
        select id into v_existing from harvests
        where org_id = p_org_id and client_uuid = p_client_uuid;
        if found then
            return v_existing;
        end if;
    end if;

    select org_id, unit, btrim(crop) into v_org, v_unit, v_crop from crop_cycles
    where id = p_crop_cycle_id;
    if v_org is null or v_org <> p_org_id then
        raise exception 'No such planting in this business';
    end if;

    v_unit := coalesce(nullif(btrim(coalesce(p_unit, '')), ''), v_unit, 'kg');

    if coalesce(p_to_stock, false) then
        -- The farm's article of that name: the live one first, else the
        -- oldest put away.
        select * into v_product from products
        where org_id = p_org_id and lower(btrim(name)) = lower(v_crop)
        order by is_active desc, created_at
        limit 1
        for update;

        if found and v_product.is_service then
            raise exception 'Un service porte déjà le nom « % » : la récolte ne peut pas aller en stock sous ce nom.', v_crop;
        end if;

        if found then
            if nullif(btrim(coalesce(v_product.unit, '')), '') is not null
               and lower(btrim(v_product.unit)) <> lower(v_unit) then
                raise exception '« % » se vend par %, la récolte est comptée en % : comptez-la en %.',
                    v_product.name, v_product.unit, v_unit, v_product.unit;
            end if;
            update products set
                quantity  = quantity + p_quantity,
                is_active = true,
                unit      = coalesce(nullif(btrim(coalesce(unit, '')), ''), v_unit)
            where id = v_product.id;
            v_product_id := v_product.id;
        else
            insert into products (org_id, name, sale_price, cost_price, quantity,
                                  unit, is_published, created_by)
            values (p_org_id, v_crop, 0, 0, p_quantity, v_unit, false, v_actor)
            returning id into v_product_id;
        end if;
    end if;

    -- No ledger entry. Bringing a crop in is not earning money — it is earning
    -- money later, or eating it — and booking income here would inflate the
    -- income statement by every sack that never reached a market. Selling it
    -- goes through the sale, as it always did.
    insert into harvests (org_id, crop_cycle_id, harvested_on, quantity, unit,
                          grade, note, created_by, device_id, client_uuid,
                          product_id)
    values (p_org_id, p_crop_cycle_id,
            coalesce(p_harvested_on, current_date),
            p_quantity,
            v_unit,
            coalesce(nullif(btrim(coalesce(p_grade, '')), ''), 'first'),
            nullif(btrim(coalesce(p_note, '')), ''),
            v_actor, p_device_id, p_client_uuid,
            v_product_id)
    returning id into v_id;

    return v_id;
end;
$$;

revoke execute on function record_harvest(uuid, uuid, numeric, text, text, date, text, uuid, text, boolean) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function record_harvest(uuid, uuid, numeric, text, text, date, text, uuid, text, boolean) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function record_harvest(uuid, uuid, numeric, text, text, date, text, uuid, text, boolean) to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function record_harvest(uuid, uuid, numeric, text, text, date, text, uuid, text, boolean) to service_role;
    end if;
end $$;

notify pgrst, 'reload schema';
