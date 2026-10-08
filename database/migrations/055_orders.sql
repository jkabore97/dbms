-- ============================================================
-- 055_orders.sql — a customer's réservation at a shop.
--
-- The street can look in the window (052) and find the shop (053). Now a
-- signed-in customer can say "I want these, I'll come for them" — or "bring
-- them" — and the shop can answer. That is an order.
--
-- What an order is *not*: a sale. The goods and the money change hands
-- when the customer collects or the shop delivers, and that moment is
-- recorded in the till exactly as it is today. Nothing here moves stock or
-- touches the books, on purpose: a réservation the customer never comes
-- for must leave no trace in either. The order is a list of who wants
-- what, and where it stands.
--
-- Where it stands:
--
--   pending  → accepted → ready → picked_up | delivered     (the shop)
--   pending  → refused                                       (the shop)
--   pending  → cancelled                                     (the customer)
--   accepted | ready → cancelled                             (the shop)
--
-- Who may do what is decided here, in functions, and nowhere else: the
-- tables have no insert or update policy at all. The customer's writes go
-- through place_order() and cancel_order(); the shop's through
-- decide_order(), which is gated by can_write_org() — the same chokepoint
-- as every other write in a business, so a suspended shop (049) can take
-- no orders and answer none.
--
-- The lines are snapshots: the name and the price as they were when the
-- customer pressed the button. A price changed on the shelf tomorrow does
-- not rewrite what a customer was told today.
-- ============================================================

create table if not exists orders (
    id            uuid primary key default gen_random_uuid(),
    org_id        uuid not null references orgs(id) on delete cascade,
    customer_id   uuid not null references profiles(id) on delete cascade,
    customer_name text not null,
    phone         text,
    status        text not null default 'pending'
                  check (status in ('pending', 'accepted', 'ready',
                                    'picked_up', 'delivered',
                                    'refused', 'cancelled')),
    fulfilment    text not null default 'pickup'
                  check (fulfilment in ('pickup', 'delivery')),
    note          text,
    address       text,
    total         numeric(14, 2) not null default 0,
    currency      text not null default 'XOF',
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    decided_at    timestamptz
);

create index if not exists orders_by_org      on orders (org_id, created_at desc);
create index if not exists orders_by_customer on orders (customer_id, created_at desc);
create index if not exists orders_open        on orders (org_id)
    where status in ('pending', 'accepted', 'ready');

create table if not exists order_lines (
    id         uuid primary key default gen_random_uuid(),
    order_id   uuid not null references orders(id) on delete cascade,
    product_id uuid references products(id) on delete set null,
    name       text not null,
    unit_price numeric(14, 2) not null,
    quantity   numeric(12, 3) not null check (quantity > 0)
);

create index if not exists order_lines_by_order on order_lines (order_id);

comment on table orders is
    'A customer''s réservation at a shop (055). Not a sale: the till '
    'records the sale when the goods change hands. Written only through '
    'place_order / cancel_order (the customer) and decide_order (the shop).';

-- ------------------------------------------------------------
-- Reading: the customer sees their own; the shop's members see the shop's.
-- Nobody writes these tables directly.
-- ------------------------------------------------------------
alter table orders      enable row level security;
alter table order_lines enable row level security;

drop policy if exists "orders readable by their customer and the shop" on orders;
create policy "orders readable by their customer and the shop"
on orders for select
using (customer_id = auth.uid() or is_org_member(org_id));

drop policy if exists "order lines readable with their order" on order_lines;
create policy "order lines readable with their order"
on order_lines for select
using (exists (select 1 from orders o
                where o.id = order_id
                  and (o.customer_id = auth.uid() or is_org_member(o.org_id))));

-- ------------------------------------------------------------
-- The customer places an order
-- ------------------------------------------------------------
-- p_lines is a JSON array of {product_id, quantity}. Every article must be
-- in this shop's window right now — published, active, on an open vitrine
-- — or the whole order is refused: a shopper cannot order what the street
-- cannot see. The total is computed here from the shelf prices, never
-- trusted from the phone.
create or replace function place_order(
    p_slug       text,
    p_lines      jsonb,
    p_fulfilment text default 'pickup',
    p_note       text default null,
    p_address    text default null,
    p_phone      text default null
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
    select default_currency into v_currency from orgs where id = v_org;

    insert into orders (org_id, customer_id, customer_name, phone,
                        fulfilment, note, address, currency)
    values (v_org, auth.uid(), v_name,
            coalesce(nullif(btrim(coalesce(p_phone, '')), ''), v_phone),
            p_fulfilment,
            nullif(btrim(coalesce(p_note, '')), ''),
            v_address,
            coalesce(v_currency, 'XOF'))
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

    -- The shop's bell rings (030). Failing to ring must not fail the order.
    begin
        perform notify_org_admins(
            v_org, 'new_order',
            'Nouvelle commande de ' || v_name || ' : '
            || to_char(v_total, 'FM999G999G999D00') || ' '
            || coalesce(v_currency, 'XOF'));
    exception when others then
        null;
    end;

    return v_id;
end;
$$;

-- The customer changes their mind — only while the shop has not answered.
create or replace function cancel_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_rows int;
begin
    if auth.uid() is null then
        raise exception 'Sign in first';
    end if;
    update orders
       set status = 'cancelled', updated_at = now(), decided_at = now()
     where id = p_order_id
       and customer_id = auth.uid()
       and status = 'pending';
    get diagnostics v_rows = row_count;
    if v_rows = 0 then
        raise exception 'This order can no longer be cancelled';
    end if;
end;
$$;

-- ------------------------------------------------------------
-- The shop answers
-- ------------------------------------------------------------
-- Gated by can_write_org(): any writer of the shop may answer, a viewer
-- may not, a stranger may not, and a suspended shop may not. Only the
-- transitions drawn in the header are allowed; a final state is final.
create or replace function decide_order(p_order_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_order orders%rowtype;
    v_ok    boolean;
begin
    select * into v_order from orders where id = p_order_id;
    if not found then
        raise exception 'No such order';
    end if;
    if not can_write_org(v_order.org_id) then
        raise exception 'Only the shop can answer its orders';
    end if;

    v_ok := case v_order.status
        when 'pending'  then p_status in ('accepted', 'refused')
        when 'accepted' then p_status in ('ready', 'picked_up', 'delivered', 'cancelled')
        when 'ready'    then p_status in ('picked_up', 'delivered', 'cancelled')
        else false
    end;
    if not v_ok then
        raise exception 'An order cannot go from % to %', v_order.status, p_status;
    end if;
    if p_status = 'picked_up' and v_order.fulfilment = 'delivery' then
        raise exception 'A delivery is delivered, not picked up';
    end if;
    if p_status = 'delivered' and v_order.fulfilment = 'pickup' then
        raise exception 'A pickup is picked up, not delivered';
    end if;

    update orders
       set status     = p_status,
           updated_at = now(),
           decided_at = coalesce(decided_at, now())
     where id = p_order_id;

    -- The customer's bell rings too.
    begin
        insert into notifications (recipient_id, org_id, kind, message)
        select v_order.customer_id, v_order.org_id, 'order_' || p_status,
               'Votre commande chez ' || o.name || ' : '
               || case p_status
                    when 'accepted'  then 'acceptée'
                    when 'ready'     then 'prête'
                    when 'picked_up' then 'récupérée'
                    when 'delivered' then 'livrée'
                    when 'refused'   then 'refusée'
                    else 'annulée' end
          from orgs o where o.id = v_order.org_id;
    exception when others then
        null;
    end;
end;
$$;

-- ------------------------------------------------------------
-- Reading, with the lines folded in
-- ------------------------------------------------------------
drop function if exists my_orders();
create function my_orders()
returns table (
    id         uuid,
    org_id     uuid,
    shop_name  text,
    shop_slug  text,
    status     text,
    fulfilment text,
    note       text,
    address    text,
    phone      text,
    total      numeric,
    currency   text,
    created_at timestamptz,
    lines      jsonb
)
language sql
stable
security definer
set search_path = public
as $$
    select o.id, o.org_id, g.name, g.slug, o.status, o.fulfilment,
           o.note, o.address, o.phone, o.total, o.currency, o.created_at,
           (select coalesce(jsonb_agg(jsonb_build_object(
                       'name', l.name, 'unit_price', l.unit_price,
                       'quantity', l.quantity) order by l.name), '[]'::jsonb)
              from order_lines l where l.order_id = o.id)
      from orders o
      join orgs g on g.id = o.org_id
     where o.customer_id = auth.uid()
     order by (o.status in ('pending', 'accepted', 'ready')) desc,
              o.created_at desc;
$$;

drop function if exists shop_orders(uuid);
create function shop_orders(p_org_id uuid)
returns table (
    id            uuid,
    customer_name text,
    phone         text,
    status        text,
    fulfilment    text,
    note          text,
    address       text,
    total         numeric,
    currency      text,
    created_at    timestamptz,
    lines         jsonb
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
           (select coalesce(jsonb_agg(jsonb_build_object(
                       'name', l.name, 'unit_price', l.unit_price,
                       'quantity', l.quantity) order by l.name), '[]'::jsonb)
              from order_lines l where l.order_id = o.id)
      from orders o
     where o.org_id = p_org_id
     order by (o.status in ('pending', 'accepted', 'ready')) desc,
              o.created_at desc;
end;
$$;

-- What the till's badge shows: how many are waiting for an answer.
create or replace function shop_pending_orders(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case when is_org_member(p_org_id)
                then (select count(*)::int from orders
                       where org_id = p_org_id and status = 'pending')
                else 0 end;
$$;

-- ------------------------------------------------------------
-- Grants: the signed-in only. The street reads windows, not orders.
-- ------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant select on orders, order_lines to authenticated;
        grant execute on function place_order(text, jsonb, text, text, text, text) to authenticated;
        grant execute on function cancel_order(uuid)                            to authenticated;
        grant execute on function decide_order(uuid, text)                      to authenticated;
        grant execute on function my_orders()                                   to authenticated;
        grant execute on function shop_orders(uuid)                             to authenticated;
        grant execute on function shop_pending_orders(uuid)                     to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
