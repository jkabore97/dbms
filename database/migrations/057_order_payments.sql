-- ============================================================
-- 057_order_payments.sql — how an order is paid, and who says it was.
--
-- Step 3 of the marketplace (orders → delivery → payments). Two methods,
-- which is what the street here actually uses:
--
--   cash — at the counter or at the door, as réservations have worked
--          since 055. The courier's card says how much to collect.
--   wave — the customer pays the shop's own Wave merchant link from
--          their phone, once the shop has accepted the order.
--
-- What this deliberately is NOT: a payment processor. Wave has no
-- webhook wired here, so the app cannot *know* the money arrived — only
-- the shop can, in its Wave app. So the truth stays where it lives: the
-- customer says "I pay by Wave" at order time, pays after acceptance,
-- and the SHOP confirms "paiement reçu" (and can unsay it — a mis-tap
-- must not be forever). The courier's card then says "déjà payé — rien
-- à encaisser" instead of an amount. When Wave hands out API keys, a
-- webhook can start setting paid_at instead of a thumb; nothing else
-- will have to move.
--
-- Wave is offered only by shops that set their merchant link (037): a
-- wave order to a shop with no Wave would be a promise nobody can keep.
-- ============================================================

alter table orders add column if not exists payment_method text not null default 'cash';
alter table orders drop constraint if exists orders_payment_method_check;
alter table orders add constraint orders_payment_method_check
    check (payment_method in ('cash', 'wave'));

-- Set by the shop's confirmation, never by the customer's claim.
alter table orders add column if not exists paid_at timestamptz;

-- ------------------------------------------------------------
-- Ordering says how it will be paid
-- ------------------------------------------------------------
-- The 055 signature must go first: two place_order overloads whose extra
-- arguments all have defaults would make every short call ambiguous.
drop function if exists place_order(text, jsonb, text, text, text, text);
create or replace function place_order(
    p_slug       text,
    p_lines      jsonb,
    p_fulfilment text default 'pickup',
    p_note       text default null,
    p_address    text default null,
    p_phone      text default null,
    p_payment    text default 'cash'
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
                        fulfilment, note, address, currency, payment_method)
    values (v_org, auth.uid(), v_name,
            coalesce(nullif(btrim(coalesce(p_phone, '')), ''), v_phone),
            p_fulfilment,
            nullif(btrim(coalesce(p_note, '')), ''),
            v_address,
            coalesce(v_currency, 'XOF'),
            p_payment)
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
-- The shop says the money arrived (and can unsay a mis-tap)
-- ------------------------------------------------------------
create or replace function set_order_paid(p_order_id uuid, p_paid boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_order orders%rowtype;
begin
    select * into v_order from orders where id = p_order_id;
    if not found then
        raise exception 'No such order';
    end if;
    if not can_write_org(v_order.org_id) then
        raise exception 'Only the shop says what was paid';
    end if;
    update orders
       set paid_at = case when p_paid then coalesce(paid_at, now()) end,
           updated_at = now()
     where id = p_order_id;
    if p_paid and v_order.paid_at is null then
        begin
            insert into notifications (recipient_id, org_id, kind, message)
            select v_order.customer_id, v_order.org_id, 'order_paid',
                   'Votre paiement chez ' || o.name || ' est confirmé'
              from orgs o where o.id = v_order.org_id;
        exception when others then
            null;
        end;
    end if;
end;
$$;

-- ------------------------------------------------------------
-- Every reader learns how the order is paid. Return types change, so
-- each is dropped, recreated and re-granted.
-- ------------------------------------------------------------
drop function if exists storefront(text);
create function storefront(p_slug text)
returns table (
    org_id        uuid,
    name          text,
    slug          text,
    profile       text,
    blurb         text,
    phone         text,
    address       text,
    theme         text,
    currency      text,
    lat           double precision,
    lng           double precision,
    wave_merchant text
)
language sql
stable
security definer
set search_path = public
as $$
    select o.id, o.name, o.slug, o.profile::text, o.storefront_blurb,
           o.phone, o.address, o.theme, o.default_currency, o.lat, o.lng,
           o.wave_merchant
    from orgs o
    where o.id = storefront_open(p_slug);
$$;

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
           o.payment_method, o.paid_at, g.wave_merchant,
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
           o.note, o.address, o.total, o.currency, o.created_at,
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

drop function if exists available_deliveries();
create function available_deliveries()
returns table (
    order_id       uuid,
    shop_name      text,
    shop_address   text,
    shop_lat       double precision,
    shop_lng       double precision,
    drop_address   text,
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
           o.address, o.total, o.currency, o.created_at,
           o.payment_method, o.paid_at
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
           o.customer_name, o.phone, o.address, o.status,
           o.total, o.currency, o.created_at,
           o.payment_method, o.paid_at
      from orders o
      join orgs g on g.id = o.org_id
     where o.courier_id = auth.uid()
     order by (o.status in ('ready', 'in_transit')) desc, o.created_at desc;
end;
$$;

-- ------------------------------------------------------------
-- Grants
-- ------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function storefront(text) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function storefront(text)                to authenticated;
        grant execute on function place_order(text, jsonb, text, text, text, text, text) to authenticated;
        grant execute on function set_order_paid(uuid, boolean)   to authenticated;
        grant execute on function my_orders()                     to authenticated;
        grant execute on function shop_orders(uuid)               to authenticated;
        grant execute on function available_deliveries()          to authenticated;
        grant execute on function courier_deliveries()            to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
