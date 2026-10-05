-- ============================================================
-- 073_delivery_runs.sql — a delivery that runs itself, and says where it is.
--
-- The October audit, "the delivery side is trash": a shopper who ordered
-- saw a status word and nothing else — no time, no courier, no way to know
-- it was stuck; a ready order nobody took sat there with nothing telling
-- the shop, and nothing the shop could do but wait; the courier marked an
-- order delivered with one tap, at any door; a door that did not open had
-- no outcome but "delivered"; the cash a courier collected was nobody's
-- ledger; a shop with its own boy on a moto could not hand him its orders;
-- and the board listed deliveries oldest first, wherever they were.
--
--   1. order_events: every status an order passes through, with its time.
--      Written by trigger, so every path — shop, courier, cancel — records.
--      The state clocks, the shopper's timeline and "stuck" read it.
--   2. A handover code: four digits drawn at a delivery order's birth,
--      shown to the shopper only. courier_deliver(order, code) is the way
--      a courier closes a delivery; courier_mark(…, 'delivered') now asks
--      for it. The shop can still mark it delivered (its word, its order).
--   3. courier_fail(order, reason): the door did not open — absent,
--      refused, unreachable, other. The order is cancelled with the reason
--      (orders.outcome), the goods go back to the shop, everyone is told.
--   4. shop_deliver_self(order): a ready delivery nobody has taken — the
--      shop carries it itself. No courier, no platform share.
--   5. The cash: a cash order a courier delivered is owed to the shop until
--      the shop says it was handed over (confirm_cash_received). The
--      courier sees what they hold; the shop sees what it is owed.
--   6. org_couriers: a shop names its own couriers. Its ready orders are
--      theirs alone for the first ten minutes, then the street's.
--   7. delivery_board(lat, lng): the board, nearest shop first, the shop's
--      own orders flagged and first; take_delivery honours the ten minutes.
--   8. order_tracking(order): the shopper's page — the timeline, the
--      courier's name and phone once on the road, the shop's phone, the
--      code; for the shop, the same without the code.
-- ============================================================

insert into platform_settings (key, value) values
    ('own_courier_minutes', '10'),
    ('stuck_ready_minutes', '20')
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- 1. The timeline
-- ------------------------------------------------------------
create table if not exists order_events (
    id       bigserial primary key,
    order_id uuid not null references orders(id) on delete cascade,
    status   text not null,
    at       timestamptz not null default now(),
    by_user  uuid
);
create index if not exists order_events_by_order on order_events (order_id, at);
alter table order_events enable row level security;
-- No policies: read through order_tracking() as its definer.

create or replace function trg_order_event()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if tg_op = 'INSERT' or new.status is distinct from old.status then
        insert into order_events (order_id, status, by_user)
        values (new.id, new.status, auth.uid());
    end if;
    return new;
end;
$$;

create or replace trigger order_event
after insert or update of status on orders
for each row execute function trg_order_event();

-- Orders placed before 073 get their birth and their present state, so a
-- clock can still be read on them.
insert into order_events (order_id, status, at)
select o.id, 'pending', o.created_at from orders o
 where not exists (select 1 from order_events e where e.order_id = o.id);
insert into order_events (order_id, status, at)
select o.id, o.status, o.updated_at from orders o
 where o.status <> 'pending'
   and not exists (select 1 from order_events e
                    where e.order_id = o.id and e.status = o.status);

-- When an order entered the state it is in.
create or replace function order_status_since(p_order_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        (select max(e.at) from order_events e
          join orders o on o.id = e.order_id
         where e.order_id = p_order_id and e.status = o.status),
        (select updated_at from orders where id = p_order_id));
$$;

-- ------------------------------------------------------------
-- 2. The handover code
-- ------------------------------------------------------------
alter table orders add column if not exists handover_code text;
alter table orders add column if not exists outcome text;
alter table orders add column if not exists self_delivered boolean not null default false;
alter table orders add column if not exists cash_received_at timestamptz;

create or replace function trg_order_handover_code()
returns trigger
language plpgsql
as $$
begin
    if new.fulfilment = 'delivery' and new.handover_code is null then
        new.handover_code := lpad((floor(random() * 10000))::int::text, 4, '0');
    end if;
    return new;
end;
$$;

create or replace trigger order_handover_code
before insert on orders
for each row execute function trg_order_handover_code();

update orders set handover_code = lpad((floor(random() * 10000))::int::text, 4, '0')
 where fulfilment = 'delivery' and handover_code is null
   and status in ('pending', 'accepted', 'ready', 'in_transit');

-- The courier closes a delivery at the door, with the shopper's code.
create or replace function courier_deliver(p_order_id uuid, p_code text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v orders%rowtype; v_shop text;
begin
    select * into v from orders where id = p_order_id;
    if not found or v.courier_id is distinct from auth.uid() then
        raise exception 'Cette livraison n''est pas la vôtre';
    end if;
    if v.status <> 'in_transit' then
        raise exception 'Cette livraison n''est pas en route';
    end if;
    if v.handover_code is not null
       and btrim(coalesce(p_code, '')) <> v.handover_code then
        raise exception 'Code incorrect : demandez au client les 4 chiffres de sa commande';
    end if;
    update orders set status = 'delivered', updated_at = now() where id = p_order_id;
    select name into v_shop from orgs where id = v.org_id;
    begin
        insert into notifications (recipient_id, org_id, kind, message)
        values (v.customer_id, v.org_id, 'order_delivered',
                'Votre commande chez ' || v_shop || ' est livrée');
        perform notify_org_admins(v.org_id, 'order_delivered',
            'La commande de ' || v.customer_name || ' est livrée');
    exception when others then null;
    end;
end;
$$;

-- 056's courier_mark, same signature: the road is still one tap, the door
-- now needs the code (courier_deliver).
create or replace function courier_mark(p_order_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_order orders%rowtype; v_shop text;
begin
    select * into v_order from orders where id = p_order_id;
    if not found or v_order.courier_id is distinct from auth.uid() then
        raise exception 'This delivery is not yours';
    end if;
    if p_status = 'delivered' then
        if v_order.status <> 'in_transit' then
            raise exception 'A delivery cannot go from % to %', v_order.status, p_status;
        end if;
        if v_order.handover_code is not null then
            raise exception 'Demandez au client le code de sa commande pour la clore';
        end if;
        perform courier_deliver(p_order_id, null);
        return;
    end if;
    if not (v_order.status = 'ready' and p_status = 'in_transit') then
        raise exception 'A delivery cannot go from % to %', v_order.status, p_status;
    end if;
    update orders set status = p_status, updated_at = now() where id = p_order_id;
    select name into v_shop from orgs where id = v_order.org_id;
    begin
        insert into notifications (recipient_id, org_id, kind, message)
        values (v_order.customer_id, v_order.org_id, 'order_in_transit',
                'Votre commande chez ' || v_shop || ' est en route');
    exception when others then null;
    end;
end;
$$;

-- ------------------------------------------------------------
-- 3. When the door does not open
-- ------------------------------------------------------------
create or replace function courier_fail(p_order_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v orders%rowtype; v_shop text; v_words text;
begin
    select * into v from orders where id = p_order_id;
    if not found or v.courier_id is distinct from auth.uid() then
        raise exception 'Cette livraison n''est pas la vôtre';
    end if;
    if v.status <> 'in_transit' then
        raise exception 'Seule une livraison en route peut échouer';
    end if;
    if p_reason not in ('absent', 'refused', 'unreachable', 'other') then
        raise exception 'Raison inconnue : %', p_reason;
    end if;
    v_words := case p_reason
        when 'absent'      then 'client absent'
        when 'refused'     then 'refusée par le client'
        when 'unreachable' then 'client injoignable'
        else 'autre raison' end;
    update orders set status = 'cancelled', outcome = p_reason, updated_at = now()
     where id = p_order_id;
    select name into v_shop from orgs where id = v.org_id;
    begin
        perform notify_org_admins(v.org_id, 'delivery_failed',
            'Livraison de ' || v.customer_name || ' échouée (' || v_words
            || ') : le livreur rapporte la commande.');
        insert into notifications (recipient_id, org_id, kind, message)
        values (v.customer_id, v.org_id, 'delivery_failed',
                'La livraison de votre commande chez ' || v_shop
                || ' n''a pas pu se faire (' || v_words || ').');
    exception when others then null;
    end;
end;
$$;

-- ------------------------------------------------------------
-- 4. "Je livre moi-même"
-- ------------------------------------------------------------
create or replace function shop_deliver_self(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v orders%rowtype; v_shop text;
begin
    select * into v from orders where id = p_order_id;
    if not found or not can_write_org(v.org_id) then
        raise exception 'Seule la boutique livre ses commandes';
    end if;
    if v.fulfilment <> 'delivery' or v.status not in ('accepted', 'ready')
       or v.courier_id is not null then
        raise exception 'Cette commande a déjà un livreur, ou n''est pas à livrer';
    end if;
    update orders
       set status = 'in_transit', self_delivered = true, platform_fee = 0,
           updated_at = now()
     where id = p_order_id;
    select name into v_shop from orgs where id = v.org_id;
    begin
        insert into notifications (recipient_id, org_id, kind, message)
        values (v.customer_id, v.org_id, 'order_in_transit',
                v_shop || ' vous livre lui-même : votre commande est en route');
    exception when others then null;
    end;
end;
$$;

-- decide_order (056) lets the shop take in_transit → delivered already.

-- ------------------------------------------------------------
-- 5. The cash
-- ------------------------------------------------------------
-- What a courier holds: cash orders they delivered that the shop has not
-- said it received, newest first.
create or replace function courier_cash()
returns table (
    order_id      uuid,
    shop_name     text,
    shop_phone    text,
    customer_name text,
    total         numeric,
    delivery_fee  numeric,
    currency      text,
    delivered_at  timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    perform assert_approved_courier();
    return query
    select o.id, g.name, g.phone, o.customer_name, o.total, o.delivery_fee,
           o.currency, o.updated_at
      from orders o join orgs g on g.id = o.org_id
     where o.courier_id = auth.uid()
       and o.status = 'delivered' and o.payment_method = 'cash'
       and o.paid_at is null and o.cash_received_at is null
     order by o.updated_at desc;
end;
$$;

-- What the shop is owed, courier by courier.
create or replace function shop_cash_owed(p_org_id uuid)
returns table (
    order_id      uuid,
    courier_name  text,
    courier_phone text,
    customer_name text,
    total         numeric,
    currency      text,
    delivered_at  timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not is_org_member(p_org_id) then
        raise exception 'Only the shop sees its orders';
    end if;
    return query
    select o.id,
           coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                    nullif(btrim(coalesce(p.full_name, '')), ''), 'Livreur'),
           c.phone, o.customer_name, o.total, o.currency, o.updated_at
      from orders o
      join profiles p on p.id = o.courier_id
      left join couriers c on c.user_id = o.courier_id
     where o.org_id = p_org_id
       and o.status = 'delivered' and o.payment_method = 'cash'
       and o.paid_at is null and o.cash_received_at is null
     order by o.updated_at;
end;
$$;

create or replace function confirm_cash_received(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v orders%rowtype;
begin
    select * into v from orders where id = p_order_id;
    if not found or not can_write_org(v.org_id) then
        raise exception 'Seule la boutique confirme l''argent reçu';
    end if;
    if v.status <> 'delivered' or v.payment_method <> 'cash' then
        raise exception 'Cette commande n''attend pas d''argent du livreur';
    end if;
    update orders set cash_received_at = now(), paid_at = coalesce(paid_at, now())
     where id = p_order_id;
end;
$$;

-- ------------------------------------------------------------
-- 6. A shop's own couriers
-- ------------------------------------------------------------
create table if not exists org_couriers (
    org_id     uuid not null references orgs(id) on delete cascade,
    user_id    uuid not null references profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (org_id, user_id)
);
alter table org_couriers enable row level security;
do $$ begin
    if not exists (select 1 from pg_policies where tablename = 'org_couriers'
                    and policyname = 'org couriers readable by members') then
        create policy "org couriers readable by members"
        on org_couriers for select using (is_org_member(org_id));
    end if;
end $$;

-- Adds an approved courier to the shop by phone; returns their name.
create or replace function add_org_courier(p_org_id uuid, p_phone text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_user uuid; v_name text;
    v_digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur choisit les livreurs de la boutique';
    end if;
    select c.user_id into v_user from couriers c
      left join profiles p on p.id = c.user_id
     where c.status = 'approved'
       and length(v_digits) >= 8
       and (right(regexp_replace(coalesce(c.phone, ''), '\D', '', 'g'), 8) = right(v_digits, 8)
            or right(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g'), 8) = right(v_digits, 8))
     limit 1;
    if v_user is null then
        raise exception 'Aucun livreur validé avec ce numéro. Il doit d''abord s''inscrire comme livreur dans Kaj.';
    end if;
    insert into org_couriers (org_id, user_id) values (p_org_id, v_user)
    on conflict do nothing;
    select coalesce(nullif(btrim(concat_ws(' ', first_name, last_name)), ''),
                    nullif(btrim(coalesce(full_name, '')), ''), 'Livreur')
      into v_name from profiles where id = v_user;
    return v_name;
end;
$$;

create or replace function remove_org_courier(p_org_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur choisit les livreurs de la boutique';
    end if;
    delete from org_couriers where org_id = p_org_id and user_id = p_user_id;
end;
$$;

create or replace function org_courier_list(p_org_id uuid)
returns table (user_id uuid, name text, phone text)
language sql
stable
security definer
set search_path = public, auth
as $$
    select oc.user_id,
           coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                    nullif(btrim(coalesce(p.full_name, '')), ''), 'Livreur'),
           coalesce(c.phone, p.phone)
      from org_couriers oc
      join profiles p on p.id = oc.user_id
      left join couriers c on c.user_id = oc.user_id
     where oc.org_id = p_org_id and is_org_member(p_org_id)
     order by oc.created_at;
$$;

-- Whether this courier may take this ready order now: the shop's own
-- couriers at once, everyone else after own_courier_minutes.
create or replace function courier_may_take(p_order_id uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select not exists (select 1 from org_couriers oc
                        join orders o on o.org_id = oc.org_id
                       where o.id = p_order_id)
        or exists (select 1 from org_couriers oc
                    join orders o on o.org_id = oc.org_id
                   where o.id = p_order_id and oc.user_id = p_user)
        or order_status_since(p_order_id)
           < now() - make_interval(mins => plan_limit('own_courier_minutes', 10)::int);
$$;

-- 056's take_delivery, same signature, with the shop's ten minutes.
create or replace function take_delivery(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_order orders%rowtype; v_shop text;
begin
    perform assert_approved_courier();
    if not courier_may_take(p_order_id, auth.uid()) then
        raise exception 'Cette boutique a ses livreurs : la course s''ouvre à tous dans quelques minutes';
    end if;
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

-- ------------------------------------------------------------
-- 7. The board, nearest first
-- ------------------------------------------------------------
create or replace function delivery_board(
    p_lat double precision default null,
    p_lng double precision default null
)
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
    distance_km    double precision,
    to_shop_km     double precision,
    own_shop       boolean,
    ready_since    timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    perform assert_approved_courier();
    return query
    select x.* from (
        select o.id, g.name, g.address, g.lat, g.lng,
               o.address, o.drop_lat, o.drop_lng, o.total, o.currency,
               o.created_at, o.payment_method, o.paid_at, o.delivery_fee,
               case when g.lat is null or o.drop_lat is null then null
                    else distance_km(g.lat, g.lng, o.drop_lat, o.drop_lng) end,
               case when p_lat is null or p_lng is null or g.lat is null then null
                    else distance_km(p_lat, p_lng, g.lat, g.lng) end,
               exists (select 1 from org_couriers oc
                        where oc.org_id = o.org_id and oc.user_id = auth.uid()),
               order_status_since(o.id)
          from orders o
          join orgs g on g.id = o.org_id
         where o.status = 'ready'
           and o.fulfilment = 'delivery'
           and o.courier_id is null
           and g.archived_at  is null
           and g.suspended_at is null
           and courier_may_take(o.id, auth.uid())
    ) x (order_id, shop_name, shop_address, shop_lat, shop_lng, drop_address,
         drop_lat, drop_lng, total, currency, created_at, payment_method,
         paid_at, delivery_fee, distance_km, to_shop_km, own_shop, ready_since)
    order by x.own_shop desc, (x.to_shop_km is null), x.to_shop_km, x.created_at;
end;
$$;

-- ------------------------------------------------------------
-- 8. Where is my order
-- ------------------------------------------------------------
create or replace function order_tracking(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare v orders%rowtype; g orgs%rowtype; v_customer boolean; v_courier jsonb;
begin
    select * into v from orders where id = p_order_id;
    if not found then
        return null;
    end if;
    v_customer := v.customer_id = auth.uid();
    if not v_customer and not is_org_member(v.org_id)
       and v.courier_id is distinct from auth.uid() then
        return null;
    end if;
    select * into g from orgs where id = v.org_id;
    if v.courier_id is not null then
        select jsonb_build_object(
                   'name', coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                                    nullif(btrim(coalesce(p.full_name, '')), ''), 'Livreur'),
                   -- A phone to call once the courier is on the road.
                   'phone', case when v.status = 'in_transit' or not v_customer
                                 then coalesce(c.phone, p.phone) end)
          into v_courier
          from profiles p left join couriers c on c.user_id = p.id
         where p.id = v.courier_id;
    end if;
    return jsonb_build_object(
        'status',     v.status,
        'fulfilment', v.fulfilment,
        'outcome',    v.outcome,
        'self',       v.self_delivered,
        'since',      order_status_since(v.id),
        'shop',       jsonb_build_object('name', g.name, 'phone', g.phone,
                                         'address', g.address),
        'courier',    v_courier,
        'code',       case when v_customer and v.status in ('ready', 'in_transit', 'accepted', 'pending')
                           then v.handover_code end,
        'events',     (select coalesce(jsonb_agg(jsonb_build_object(
                                 'status', e.status, 'at', e.at) order by e.at), '[]'::jsonb)
                         from order_events e where e.order_id = v.id)
    );
end;
$$;

-- The shop's open orders and how long each has sat in its state; the
-- shop's orders screen reads it beside shop_orders.
create or replace function shop_order_clocks(p_org_id uuid)
returns table (order_id uuid, status text, since timestamptz, stuck boolean,
               self_delivered boolean, outcome text)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not is_org_member(p_org_id) then
        raise exception 'Only the shop sees its orders';
    end if;
    return query
    select o.id, o.status, order_status_since(o.id),
           (o.status = 'pending' and order_status_since(o.id) < now() - interval '30 minutes')
        or (o.status = 'ready' and o.fulfilment = 'delivery' and o.courier_id is null
            and order_status_since(o.id)
                < now() - make_interval(mins => plan_limit('stuck_ready_minutes', 20)::int))
        or (o.status = 'in_transit' and order_status_since(o.id) < now() - interval '2 hours'),
           o.self_delivered, o.outcome
      from orders o
     where o.org_id = p_org_id
       and (o.status in ('pending', 'accepted', 'ready', 'in_transit')
            or (o.outcome is not null and o.updated_at > now() - interval '2 days'));
end;
$$;

-- ------------------------------------------------------------
-- Grants
-- ------------------------------------------------------------
revoke execute on function courier_deliver(uuid, text)                    from public;
revoke execute on function courier_fail(uuid, text)                       from public;
revoke execute on function shop_deliver_self(uuid)                        from public;
revoke execute on function courier_cash()                                 from public;
revoke execute on function shop_cash_owed(uuid)                           from public;
revoke execute on function confirm_cash_received(uuid)                    from public;
revoke execute on function add_org_courier(uuid, text)                    from public;
revoke execute on function remove_org_courier(uuid, uuid)                 from public;
revoke execute on function org_courier_list(uuid)                         from public;
revoke execute on function courier_may_take(uuid, uuid)                   from public;
revoke execute on function delivery_board(double precision, double precision) from public;
revoke execute on function order_tracking(uuid)                           from public;
revoke execute on function shop_order_clocks(uuid)                        from public;
revoke execute on function order_status_since(uuid)                       from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function courier_deliver(uuid, text)         to authenticated;
        grant execute on function courier_fail(uuid, text)            to authenticated;
        grant execute on function shop_deliver_self(uuid)             to authenticated;
        grant execute on function courier_cash()                      to authenticated;
        grant execute on function shop_cash_owed(uuid)                to authenticated;
        grant execute on function confirm_cash_received(uuid)         to authenticated;
        grant execute on function add_org_courier(uuid, text)         to authenticated;
        grant execute on function remove_org_courier(uuid, uuid)      to authenticated;
        grant execute on function org_courier_list(uuid)              to authenticated;
        grant execute on function delivery_board(double precision, double precision) to authenticated;
        grant execute on function order_tracking(uuid)                to authenticated;
        grant execute on function shop_order_clocks(uuid)             to authenticated;
        grant select on org_couriers to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
