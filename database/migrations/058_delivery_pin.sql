-- ============================================================
-- 058_delivery_pin.sql — the customer's door, as a pin.
--
-- "Dassasgho, en face de la pharmacie" gets a courier to the quartier;
-- the pin gets them to the door. A customer ordering a livraison can now
-- attach their position — the phone's fix, or the coordinates out of a
-- Google Maps link — and the courier's card turns it into an itinerary,
-- the same way the shop's own pin already does (054).
--
-- The rules are the shop-pin's rules: both numbers or neither (half a
-- position is no position), on the world, and only a delivery carries
-- one — a pickup's destination is the shop. Who sees it is who already
-- sees the address: the shop, the courier who took the job, the board a
-- vetted courier reads, and the customer themself. Nothing new leaks.
-- ============================================================

alter table orders add column if not exists drop_lat double precision;
alter table orders add column if not exists drop_lng double precision;
alter table orders drop constraint if exists orders_drop_lat_range;
alter table orders add  constraint orders_drop_lat_range
    check (drop_lat is null or drop_lat between -90 and 90);
alter table orders drop constraint if exists orders_drop_lng_range;
alter table orders add  constraint orders_drop_lng_range
    check (drop_lng is null or drop_lng between -180 and 180);
alter table orders drop constraint if exists orders_drop_pin_pair;
alter table orders add  constraint orders_drop_pin_pair
    check ((drop_lat is null) = (drop_lng is null));

-- ------------------------------------------------------------
-- Ordering carries the pin. The 057 signature goes first: overloads whose
-- extra arguments all have defaults make every short call ambiguous.
-- ------------------------------------------------------------
drop function if exists place_order(text, jsonb, text, text, text, text, text);
create or replace function place_order(
    p_slug       text,
    p_lines      jsonb,
    p_fulfilment text default 'pickup',
    p_note       text default null,
    p_address    text default null,
    p_phone      text default null,
    p_payment    text default 'cash',
    p_drop_lat   double precision default null,
    p_drop_lng   double precision default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org      uuid;
    v_id       uuid;
    v_line     jsonb;
    v_product  products%rowtype;
    v_qty      numeric;
    v_total    numeric := 0;
    v_name     text;
    v_phone    text;
    v_currency text;
    v_wave     text;
    v_address  text := nullif(btrim(coalesce(p_address, '')), '');
begin
    if auth.uid() is null then
        raise exception 'Sign in to order';
    end if;
    v_org := storefront_open(p_slug);
    if v_org is null then
        raise exception 'This shop is not taking orders';
    end if;
    if p_fulfilment not in ('pickup', 'delivery') then
        raise exception 'Unknown fulfilment: %', p_fulfilment;
    end if;
    if p_fulfilment = 'delivery' and v_address is null then
        raise exception 'A delivery needs an address';
    end if;
    if (p_drop_lat is null) <> (p_drop_lng is null) then
        raise exception 'A delivery pin needs both a latitude and a longitude';
    end if;
    if p_payment not in ('cash', 'wave') then
        raise exception 'Unknown payment method: %', p_payment;
    end if;
    select wave_merchant, default_currency into v_wave, v_currency
      from orgs where id = v_org;
    if p_payment = 'wave' and v_wave is null then
        raise exception 'This shop does not take Wave';
    end if;
    if p_lines is null or jsonb_typeof(p_lines) <> 'array'
       or jsonb_array_length(p_lines) = 0 then
        raise exception 'An order needs at least one article';
    end if;

    select coalesce(nullif(btrim(concat_ws(' ', first_name, last_name)), ''),
                    nullif(btrim(coalesce(full_name, '')), ''),
                    'Client'),
           phone
      into v_name, v_phone
      from profiles where id = auth.uid();

    insert into orders (org_id, customer_id, customer_name, phone,
                        fulfilment, note, address, currency, payment_method,
                        drop_lat, drop_lng)
    values (v_org, auth.uid(), v_name,
            coalesce(nullif(btrim(coalesce(p_phone, '')), ''), v_phone),
            p_fulfilment,
            nullif(btrim(coalesce(p_note, '')), ''),
            v_address,
            coalesce(v_currency, 'XOF'),
            p_payment,
            -- A pickup's destination is the shop; a pin on it is noise.
            case when p_fulfilment = 'delivery' then p_drop_lat end,
            case when p_fulfilment = 'delivery' then p_drop_lng end)
    returning id into v_id;

    for v_line in select * from jsonb_array_elements(p_lines) loop
        v_qty := (v_line->>'quantity')::numeric;
        if v_qty is null or v_qty <= 0 then
            raise exception 'A quantity must be positive';
        end if;
        select * into v_product
          from products
         where id = (v_line->>'product_id')::uuid
           and org_id = v_org
           and is_active
           and is_published;
        if not found then
            raise exception 'An article is not in this shop''s window';
        end if;
        insert into order_lines (order_id, product_id, name, unit_price, quantity)
        values (v_id, v_product.id, v_product.name,
                coalesce(v_product.sale_price, 0), v_qty);
        v_total := v_total + coalesce(v_product.sale_price, 0) * v_qty;
    end loop;

    update orders set total = v_total where id = v_id;

    begin
        perform notify_org_admins(
            v_org, 'new_order',
            'Nouvelle commande de ' || v_name || ' : '
            || to_char(v_total, 'FM999G999G999D00') || ' '
            || coalesce(v_currency, 'XOF')
            || case when p_payment = 'wave' then ' (Wave)' else '' end);
    exception when others then
        null;
    end;

    return v_id;
end;
$$;

-- ------------------------------------------------------------
-- Whoever sees the address sees the pin. Return types change: dropped,
-- recreated, re-granted — and drop-before-create keeps the bundle safe
-- to re-run over a database that is already ahead (the 052 lesson).
-- ------------------------------------------------------------
drop function if exists available_deliveries();
create function available_deliveries()
returns table (
    order_id       uuid,
    shop_name      text,
    shop_address   text,
    shop_lat       double precision,
    shop_lng       double precision,
    drop_address   text,
    drop_lat       double precision,
    drop_lng       double precision,
    total          numeric,
    currency       text,
    created_at     timestamptz,
    payment_method text,
    paid_at        timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    perform assert_approved_courier();
    return query
    select o.id, g.name, g.address, g.lat, g.lng,
           o.address, o.drop_lat, o.drop_lng, o.total, o.currency,
           o.created_at, o.payment_method, o.paid_at
      from orders o
      join orgs g on g.id = o.org_id
     where o.status = 'ready'
       and o.fulfilment = 'delivery'
       and o.courier_id is null
       and g.archived_at  is null
       and g.suspended_at is null
     order by o.created_at;
end;
$$;

drop function if exists courier_deliveries();
create function courier_deliveries()
returns table (
    order_id       uuid,
    shop_name      text,
    shop_address   text,
    shop_lat       double precision,
    shop_lng       double precision,
    customer_name  text,
    phone          text,
    drop_address   text,
    drop_lat       double precision,
    drop_lng       double precision,
    status         text,
    total          numeric,
    currency       text,
    created_at     timestamptz,
    payment_method text,
    paid_at        timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    perform assert_approved_courier();
    return query
    select o.id, g.name, g.address, g.lat, g.lng,
           o.customer_name, o.phone, o.address, o.drop_lat, o.drop_lng,
           o.status, o.total, o.currency, o.created_at,
           o.payment_method, o.paid_at
      from orders o
      join orgs g on g.id = o.org_id
     where o.courier_id = auth.uid()
     order by (o.status in ('ready', 'in_transit')) desc, o.created_at desc;
end;
$$;

drop function if exists shop_orders(uuid);
create function shop_orders(p_org_id uuid)
returns table (
    id             uuid,
    customer_name  text,
    phone          text,
    status         text,
    fulfilment     text,
    note           text,
    address        text,
    drop_lat       double precision,
    drop_lng       double precision,
    total          numeric,
    currency       text,
    created_at     timestamptz,
    courier_name   text,
    payment_method text,
    paid_at        timestamptz,
    lines          jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if not is_org_member(p_org_id) then
        raise exception 'Only the shop sees its orders';
    end if;
    return query
    select o.id, o.customer_name, o.phone, o.status, o.fulfilment,
           o.note, o.address, o.drop_lat, o.drop_lng,
           o.total, o.currency, o.created_at,
           (select coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                            nullif(btrim(coalesce(p.full_name, '')), ''))
              from profiles p where p.id = o.courier_id),
           o.payment_method, o.paid_at,
           (select coalesce(jsonb_agg(jsonb_build_object(
                       'name', l.name, 'unit_price', l.unit_price,
                       'quantity', l.quantity) order by l.name), '[]'::jsonb)
              from order_lines l where l.order_id = o.id)
      from orders o
     where o.org_id = p_org_id
     order by (o.status in ('pending', 'accepted', 'ready', 'in_transit')) desc,
              o.created_at desc;
end;
$$;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function place_order(text, jsonb, text, text, text, text, text, double precision, double precision) to authenticated;
        grant execute on function available_deliveries() to authenticated;
        grant execute on function courier_deliveries()   to authenticated;
        grant execute on function shop_orders(uuid)      to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
