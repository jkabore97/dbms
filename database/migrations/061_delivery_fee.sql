-- ============================================================
-- 061_delivery_fee.sql — what a delivery costs, said before anyone commits.
--
-- A customer chose "livraison" without knowing the price; a courier took a
-- run without knowing what it paid. Ambiguity at the moment of commitment
-- is where orders die, so the fee is now a number, computed the way every
-- delivery market here settles on: a base for mounting the moto at all,
-- plus a rate per kilometre from the shop's pin to the customer's pin —
-- rounded to 25 F so cash changes hands cleanly.
--
--   * The platform sets the defaults (platform_settings); a shop may
--     override both numbers for itself (set_delivery_rates).
--   * delivery_fee() answers null, not a guess, when there is no pin on
--     either side or no rate for the shop's currency — the app then says
--     "à discuter" instead of inventing a price.
--   * The fee is fixed on the order at order time (orders.delivery_fee),
--     shown to the buyer inside the total before they send it, and to the
--     courier before they take it. It is paid to the courier in cash on
--     delivery, whatever the goods were paid with.
-- ============================================================

-- ------------------------------------------------------------
-- Platform defaults
-- ------------------------------------------------------------
create table if not exists platform_settings (
    key        text primary key,
    value      jsonb not null,
    updated_at timestamptz not null default now()
);
alter table platform_settings enable row level security;
-- No policies on purpose: read and written only through the functions
-- below, which run as their definer.

insert into platform_settings (key, value) values
    ('delivery_base',     '500'),
    ('delivery_per_km',   '150'),
    ('delivery_currency', '"XOF"')
on conflict (key) do nothing;

create or replace function set_platform_setting(p_key text, p_value jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not exists (select 1 from profiles
                    where id = auth.uid() and is_platform_admin) then
        raise exception 'Only the platform can change its settings';
    end if;
    insert into platform_settings (key, value) values (p_key, p_value)
    on conflict (key) do update set value = excluded.value, updated_at = now();
end;
$$;

-- ------------------------------------------------------------
-- A shop's own rates, when it has them
-- ------------------------------------------------------------
alter table orgs add column if not exists delivery_base   numeric(12, 2);
alter table orgs add column if not exists delivery_per_km numeric(12, 2);
alter table orgs drop constraint if exists orgs_delivery_rates_positive;
alter table orgs add constraint orgs_delivery_rates_positive
    check ((delivery_base is null or delivery_base >= 0)
       and (delivery_per_km is null or delivery_per_km >= 0));
alter table orgs drop constraint if exists orgs_delivery_rates_pair;
alter table orgs add constraint orgs_delivery_rates_pair
    check ((delivery_base is null) = (delivery_per_km is null));

-- Both numbers or neither: null-null returns the shop to the platform's
-- defaults, which is what "I never thought about it" should mean.
create or replace function set_delivery_rates(
    p_org_id uuid,
    p_base   numeric,
    p_per_km numeric
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'set_delivery_rates() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Only an administrator sets the delivery rates';
    end if;
    if (p_base is null) <> (p_per_km is null) then
        raise exception 'Delivery rates need both a base and a per-km amount';
    end if;
    if p_base < 0 or p_per_km < 0 then
        raise exception 'A delivery rate cannot be negative';
    end if;
    update orgs set delivery_base = p_base, delivery_per_km = p_per_km
     where id = p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- The fee
-- ------------------------------------------------------------
-- Great-circle distance in km. The same haversine the directory uses,
-- named once so the fee and the courier's board agree to the metre.
create or replace function distance_km(
    lat1 double precision, lng1 double precision,
    lat2 double precision, lng2 double precision
)
returns double precision
language sql
immutable
as $$
    select 6371.0 * 2 * asin(sqrt(
               power(sin(radians(lat2 - lat1) / 2), 2)
             + cos(radians(lat1)) * cos(radians(lat2))
             * power(sin(radians(lng2 - lng1) / 2), 2)));
$$;

create or replace function delivery_fee(
    p_org_id uuid,
    p_lat    double precision,
    p_lng    double precision
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_org      orgs%rowtype;
    v_base     numeric;
    v_per_km   numeric;
    v_currency text;
    v_fee      numeric;
begin
    if p_lat is null or p_lng is null then
        return null;
    end if;
    select * into v_org from orgs where id = p_org_id;
    if not found or v_org.lat is null or v_org.lng is null then
        return null;
    end if;
    if v_org.delivery_base is not null then
        v_base   := v_org.delivery_base;
        v_per_km := v_org.delivery_per_km;
    else
        select (value #>> '{}')::text into v_currency
          from platform_settings where key = 'delivery_currency';
        if coalesce(v_org.default_currency, 'XOF') <> coalesce(v_currency, 'XOF') then
            return null; -- the platform's numbers are in another money
        end if;
        select (value #>> '{}')::numeric into v_base
          from platform_settings where key = 'delivery_base';
        select (value #>> '{}')::numeric into v_per_km
          from platform_settings where key = 'delivery_per_km';
        if v_base is null or v_per_km is null then
            return null;
        end if;
    end if;
    v_fee := v_base + v_per_km * distance_km(v_org.lat, v_org.lng, p_lat, p_lng);
    return round(v_fee / 25) * 25;
end;
$$;

-- The street's question, before ordering: "what would it cost to bring
-- this here?" Anyone may ask; the answer is a number or nothing.
create or replace function delivery_quote(
    p_slug text,
    p_lat  double precision,
    p_lng  double precision
)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
    select delivery_fee(storefront_open(p_slug), p_lat, p_lng);
$$;

-- ------------------------------------------------------------
-- The fee on the order, fixed when it is placed
-- ------------------------------------------------------------
alter table orders add column if not exists delivery_fee numeric(12, 2);

-- Same signature as 058 (the return type does not change), so create or
-- replace is right here; the body gains the fee.
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
    v_fee      numeric;
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

    -- The fee is fixed now, from the pin the customer gave: a rate
    -- changed tomorrow does not change what was agreed today.
    if p_fulfilment = 'delivery' then
        v_fee := delivery_fee(v_org, p_drop_lat, p_drop_lng);
    end if;

    insert into orders (org_id, customer_id, customer_name, phone,
                        fulfilment, note, address, currency, payment_method,
                        drop_lat, drop_lng, delivery_fee)
    values (v_org, auth.uid(), v_name,
            coalesce(nullif(btrim(coalesce(p_phone, '')), ''), v_phone),
            p_fulfilment,
            nullif(btrim(coalesce(p_note, '')), ''),
            v_address,
            coalesce(v_currency, 'XOF'),
            p_payment,
            case when p_fulfilment = 'delivery' then p_drop_lat end,
            case when p_fulfilment = 'delivery' then p_drop_lng end,
            v_fee)
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
            || case when p_payment = 'wave' then ' (Wave)' else '' end
            || case when v_fee is not null
                    then ' + livraison ' || to_char(v_fee, 'FM999G999G999') else '' end);
    exception when others then
        null;
    end;

    return v_id;
end;
$$;

-- ------------------------------------------------------------
-- Everyone who sees an order sees its fee. Return types grow: dropped,
-- recreated, re-granted (the 052 lesson).
-- ------------------------------------------------------------
drop function if exists my_orders();
create function my_orders()
returns table (
    id             uuid,
    org_id         uuid,
    shop_name      text,
    shop_slug      text,
    status         text,
    fulfilment     text,
    note           text,
    address        text,
    phone          text,
    total          numeric,
    currency       text,
    created_at     timestamptz,
    courier_name   text,
    payment_method text,
    paid_at        timestamptz,
    shop_wave      text,
    delivery_fee   numeric,
    lines          jsonb
)
language sql
stable
security definer
set search_path = public
as $$
    select o.id, o.org_id, g.name, g.slug, o.status, o.fulfilment,
           o.note, o.address, o.phone, o.total, o.currency, o.created_at,
           (select coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                            nullif(btrim(coalesce(p.full_name, '')), ''))
              from profiles p where p.id = o.courier_id),
           o.payment_method, o.paid_at, g.wave_merchant, o.delivery_fee,
           (select coalesce(jsonb_agg(jsonb_build_object(
                       'name', l.name, 'unit_price', l.unit_price,
                       'quantity', l.quantity) order by l.name), '[]'::jsonb)
              from order_lines l where l.order_id = o.id)
      from orders o
      join orgs g on g.id = o.org_id
     where o.customer_id = auth.uid()
     order by (o.status in ('pending', 'accepted', 'ready', 'in_transit')) desc,
              o.created_at desc;
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
    delivery_fee   numeric,
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
           o.payment_method, o.paid_at, o.delivery_fee,
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
    paid_at        timestamptz,
    delivery_fee   numeric,
    distance_km    double precision
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
           o.created_at, o.payment_method, o.paid_at, o.delivery_fee,
           case when g.lat is null or o.drop_lat is null then null
                else distance_km(g.lat, g.lng, o.drop_lat, o.drop_lng) end
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
    paid_at        timestamptz,
    delivery_fee   numeric,
    distance_km    double precision
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
           o.payment_method, o.paid_at, o.delivery_fee,
           case when g.lat is null or o.drop_lat is null then null
                else distance_km(g.lat, g.lng, o.drop_lat, o.drop_lng) end
      from orders o
      join orgs g on g.id = o.org_id
     where o.courier_id = auth.uid()
     order by (o.status in ('ready', 'in_transit')) desc, o.created_at desc;
end;
$$;

-- ------------------------------------------------------------
-- Who may call what
-- ------------------------------------------------------------
revoke execute on function set_platform_setting(text, jsonb)                 from public;
revoke execute on function set_delivery_rates(uuid, numeric, numeric)        from public;
revoke execute on function delivery_fee(uuid, double precision, double precision)   from public;
revoke execute on function delivery_quote(text, double precision, double precision) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function delivery_quote(text, double precision, double precision) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_platform_setting(text, jsonb)                 to authenticated;
        grant execute on function set_delivery_rates(uuid, numeric, numeric)        to authenticated;
        grant execute on function delivery_quote(text, double precision, double precision) to authenticated;
        grant execute on function place_order(text, jsonb, text, text, text, text, text, double precision, double precision) to authenticated;
        grant execute on function my_orders()            to authenticated;
        grant execute on function shop_orders(uuid)      to authenticated;
        grant execute on function available_deliveries() to authenticated;
        grant execute on function courier_deliveries()   to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
