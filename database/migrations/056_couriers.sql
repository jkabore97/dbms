-- ============================================================
-- 056_couriers.sql — the livreur: who carries a delivery, and how.
--
-- 055 let a customer ask for a livraison and the shop answer. This gives
-- the parcel legs. A signed-in person registers as a courier; the platform
-- approves them (a stranger is being handed someone's goods, their address
-- and their phone number — that is not a self-serve power); an approved
-- courier sees the board of ready deliveries, takes one, and walks it
-- through two steps the customer watches: récupérée (in_transit) and
-- livrée.
--
-- The money is unchanged: the courier collects the total in cash at the
-- door and settles with the shop, outside the app, exactly as réservations
-- already work. The app's job is who/what/where and the state — never the
-- purse.
--
-- The order's path grows one station, for deliveries only:
--
--   pending → accepted → ready → in_transit → delivered
--                          │         └ the assigned courier (or the shop)
--                          └ taken by a courier while still 'ready'
--
-- The shop keeps every power it had (self-delivery: ready → delivered
-- stays), and cancelling a ready delivery a courier already took tells
-- the courier. Once in transit, the only way forward is delivered.
-- ============================================================

-- ------------------------------------------------------------
-- Who may carry
-- ------------------------------------------------------------
create table if not exists couriers (
    user_id    uuid primary key references profiles(id) on delete cascade,
    phone      text,
    status     text not null default 'pending'
               check (status in ('pending', 'approved', 'suspended')),
    created_at timestamptz not null default now(),
    decided_at timestamptz
);

comment on table couriers is
    'Who may carry deliveries (056). Registration is open; approval is the '
    'platform''s, because a courier is handed goods, addresses and phone '
    'numbers. Written only through register_courier / decide_courier.';

alter table couriers enable row level security;

drop policy if exists "a courier sees their own file" on couriers;
create policy "a courier sees their own file"
on couriers for select using (user_id = auth.uid());

-- The order remembers who carries it.
alter table orders add column if not exists courier_id uuid references profiles(id);

-- One more station on the path.
alter table orders drop constraint if exists orders_status_check;
alter table orders add constraint orders_status_check
    check (status in ('pending', 'accepted', 'ready', 'in_transit',
                      'picked_up', 'delivered', 'refused', 'cancelled'));

create index if not exists orders_board
    on orders (status) where status = 'ready' and courier_id is null;

-- The courier reads the orders they carry.
drop policy if exists "orders readable by their customer and the shop" on orders;
create policy "orders readable by their customer and the shop"
on orders for select
using (customer_id = auth.uid()
       or courier_id = auth.uid()
       or is_org_member(org_id));

drop policy if exists "order lines readable with their order" on order_lines;
create policy "order lines readable with their order"
on order_lines for select
using (exists (select 1 from orders o
                where o.id = order_id
                  and (o.customer_id = auth.uid()
                       or o.courier_id = auth.uid()
                       or is_org_member(o.org_id))));

-- ------------------------------------------------------------
-- Becoming one
-- ------------------------------------------------------------
create or replace function register_courier(p_phone text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is null then
        raise exception 'Sign in first';
    end if;
    insert into couriers (user_id, phone)
    values (auth.uid(),
            coalesce(nullif(btrim(coalesce(p_phone, '')), ''),
                     (select phone from profiles where id = auth.uid())))
    on conflict (user_id) do nothing;
end;
$$;

-- 'pending', 'approved', 'suspended' — or null for "never registered".
create or replace function courier_status()
returns text
language sql
stable
security definer
set search_path = public
as $$
    select status from couriers where user_id = auth.uid();
$$;

-- The platform's list, newest application first.
create or replace function platform_couriers()
returns table (
    user_id    uuid,
    name       text,
    phone      text,
    status     text,
    created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if not exists (select 1 from profiles
                    where profiles.id = auth.uid() and profiles.is_platform_admin) then
        raise exception 'Only the platform sees the couriers';
    end if;
    return query
    select c.user_id,
           coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                    nullif(btrim(coalesce(p.full_name, '')), ''),
                    'Sans nom'),
           c.phone, c.status, c.created_at
      from couriers c
      join profiles p on p.id = c.user_id
     order by (c.status = 'pending') desc, c.created_at desc;
end;
$$;

create or replace function decide_courier(p_user_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not exists (select 1 from profiles
                    where id = auth.uid() and is_platform_admin) then
        raise exception 'Only the platform decides who carries';
    end if;
    if p_status not in ('approved', 'suspended', 'pending') then
        raise exception 'Unknown courier status: %', p_status;
    end if;
    update couriers
       set status = p_status, decided_at = now()
     where user_id = p_user_id;
    if not found then
        raise exception 'No such courier';
    end if;
    -- Their bell rings; a failed bell never fails the decision.
    begin
        insert into notifications (recipient_id, kind, message)
        values (p_user_id, 'courier_' || p_status,
                case p_status
                    when 'approved' then
                        'Vous êtes livreur Kaj : les livraisons vous attendent.'
                    when 'suspended' then
                        'Votre accès livreur est suspendu.'
                    else 'Votre inscription livreur est à l''étude.' end);
    exception when others then
        null;
    end;
end;
$$;

-- ------------------------------------------------------------
-- The board, and taking from it
-- ------------------------------------------------------------
create or replace function assert_approved_courier()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if not exists (select 1 from couriers
                    where user_id = auth.uid() and status = 'approved') then
        raise exception 'Only an approved courier may do this';
    end if;
end;
$$;

-- Ready deliveries nobody carries yet, of shops that still stand. The
-- customer's door is on the card because a courier decides by distance;
-- couriers are vetted by the platform before they can see this at all.
drop function if exists available_deliveries();
create function available_deliveries()
returns table (
    order_id     uuid,
    shop_name    text,
    shop_address text,
    shop_lat     double precision,
    shop_lng     double precision,
    drop_address text,
    total        numeric,
    currency     text,
    created_at   timestamptz
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
           o.address, o.total, o.currency, o.created_at
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

create or replace function take_delivery(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_order orders%rowtype; v_shop text;
begin
    perform assert_approved_courier();
    update orders
       set courier_id = auth.uid(), updated_at = now()
     where id = p_order_id
       and status = 'ready'
       and fulfilment = 'delivery'
       and courier_id is null
    returning * into v_order;
    if not found then
        raise exception 'This delivery is no longer available';
    end if;
    select name into v_shop from orgs where id = v_order.org_id;
    begin
        perform notify_org_admins(v_order.org_id, 'delivery_taken',
            'Un livreur prend la commande de ' || v_order.customer_name);
        insert into notifications (recipient_id, org_id, kind, message)
        values (v_order.customer_id, v_order.org_id, 'order_courier',
                'Un livreur s''occupe de votre commande chez ' || v_shop);
    exception when others then
        null;
    end;
end;
$$;

-- Changed their mind before collecting: the job goes back on the board.
create or replace function release_delivery(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_rows int;
begin
    update orders
       set courier_id = null, updated_at = now()
     where id = p_order_id
       and courier_id = auth.uid()
       and status = 'ready';
    get diagnostics v_rows = row_count;
    if v_rows = 0 then
        raise exception 'This delivery can no longer be put back';
    end if;
end;
$$;

-- The two steps the courier walks: récupérée, then livrée.
create or replace function courier_mark(p_order_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_order orders%rowtype; v_shop text; v_ok boolean;
begin
    select * into v_order from orders where id = p_order_id;
    if not found or v_order.courier_id is distinct from auth.uid() then
        raise exception 'This delivery is not yours';
    end if;
    v_ok := case v_order.status
        when 'ready'      then p_status = 'in_transit'
        when 'in_transit' then p_status = 'delivered'
        else false
    end;
    if not v_ok then
        raise exception 'A delivery cannot go from % to %', v_order.status, p_status;
    end if;
    update orders
       set status = p_status, updated_at = now()
     where id = p_order_id;
    select name into v_shop from orgs where id = v_order.org_id;
    begin
        insert into notifications (recipient_id, org_id, kind, message)
        values (v_order.customer_id, v_order.org_id, 'order_' || p_status,
                case p_status
                    when 'in_transit' then
                        'Votre commande chez ' || v_shop || ' est en route'
                    else 'Votre commande chez ' || v_shop || ' est livrée' end);
        if p_status = 'delivered' then
            perform notify_org_admins(v_order.org_id, 'order_delivered',
                'La commande de ' || v_order.customer_name || ' est livrée');
        end if;
    exception when others then
        null;
    end;
end;
$$;

-- The courier's own jobs, running first.
drop function if exists courier_deliveries();
create function courier_deliveries()
returns table (
    order_id      uuid,
    shop_name     text,
    shop_address  text,
    shop_lat      double precision,
    shop_lng      double precision,
    customer_name text,
    phone         text,
    drop_address  text,
    status        text,
    total         numeric,
    currency      text,
    created_at    timestamptz
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
           o.total, o.currency, o.created_at
      from orders o
      join orgs g on g.id = o.org_id
     where o.courier_id = auth.uid()
     order by (o.status in ('ready', 'in_transit')) desc, o.created_at desc;
end;
$$;

-- ------------------------------------------------------------
-- The shop and the customer see who carries, and the new station
-- ------------------------------------------------------------
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
        when 'pending'    then p_status in ('accepted', 'refused')
        when 'accepted'   then p_status in ('ready', 'picked_up', 'delivered', 'cancelled')
        when 'ready'      then p_status in ('picked_up', 'delivered', 'cancelled')
        -- Once the parcel is on a motorbike the shop can only confirm the
        -- end of the journey, not rewrite it.
        when 'in_transit' then p_status = 'delivered'
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
        -- A courier who already took the job hears about a cancellation.
        if p_status = 'cancelled' and v_order.courier_id is not null then
            insert into notifications (recipient_id, org_id, kind, message)
            values (v_order.courier_id, v_order.org_id, 'delivery_cancelled',
                    'La livraison pour ' || v_order.customer_name
                    || ' a été annulée par la boutique');
        end if;
    exception when others then
        null;
    end;
end;
$$;

-- Both read functions grow the courier's name and the new station, so the
-- return type changes: drop and recreate, grants re-issued below.
drop function if exists my_orders();
create function my_orders()
returns table (
    id           uuid,
    org_id       uuid,
    shop_name    text,
    shop_slug    text,
    status       text,
    fulfilment   text,
    note         text,
    address      text,
    phone        text,
    total        numeric,
    currency     text,
    created_at   timestamptz,
    courier_name text,
    lines        jsonb
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
    courier_name  text,
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
           (select coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                            nullif(btrim(coalesce(p.full_name, '')), ''))
              from profiles p where p.id = o.courier_id),
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

-- ------------------------------------------------------------
-- Grants
-- ------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant select on couriers to authenticated;
        grant execute on function register_courier(text)      to authenticated;
        grant execute on function courier_status()            to authenticated;
        grant execute on function platform_couriers()         to authenticated;
        grant execute on function decide_courier(uuid, text)  to authenticated;
        grant execute on function available_deliveries()      to authenticated;
        grant execute on function take_delivery(uuid)         to authenticated;
        grant execute on function release_delivery(uuid)      to authenticated;
        grant execute on function courier_mark(uuid, text)    to authenticated;
        grant execute on function courier_deliveries()        to authenticated;
        grant execute on function decide_order(uuid, text)    to authenticated;
        grant execute on function my_orders()                 to authenticated;
        grant execute on function shop_orders(uuid)           to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
