-- ============================================================
-- 101_stock_farm_analytics.sql — stock that never goes below zero, vitrine
-- orders that move it, a farm's analyses, and a second business asked for
-- without a word about the person.
--
-- The owner: « vitrine orders reduce stock. I never mention sale being
-- return, user will use correction for this. Stock cannot go below zero. »
-- « Vitrine orders should definitely reduce. » « build analyst for farm
-- and lock it. » « When requesting a new business, since the user is
-- already signed in, there is no reason to ask for more personal
-- information. »
--
--   1. Stock never goes below zero. Held where stock is written, not by
--      each function that writes it, so every path is caught — the till,
--      a credit sale, a vitrine order accepted, a production's
--      ingredients, a production corrected (100), a delivery reversed
--      (042), a direct write through the API:
--        * products.quantity (the shop's and the farm's « À vendre »): a
--          BEFORE trigger refuses any write that would leave it below
--          zero and lower than it was. Refused in French, naming the
--          article and what is left: « Il ne reste que 3 Savon », or
--          « Plus de Savon en stock » when nothing is left.
--        * stock_movements (the farm's feed, medicine, sawdust — 009): a
--          BEFORE INSERT trigger refuses a consumption, a loss or a
--          negative count that would take the item below zero, with the
--          same words. The item row is locked first, so two phones
--          syncing at once cannot both take the last sack.
--      Stock already below zero on the day this lands (029 allowed it on
--      purpose) is left as it is — no row is rewritten — but it cannot go
--      lower: any further decrease is refused, any increase (a delivery,
--      a return, a correction) is always allowed. A service (098) has no
--      stock and is never refused.
--      This reverses 029's « stock can go negative »: a till sale of an
--      article with nothing on the shelf, a typed name never received
--      included, is now refused until the stock is received.
--   2. A vitrine order moves stock (055 said it never did). When the
--      business accepts it, each article line (not a service, not a
--      pre-order — 083: nothing to count yet) leaves the shelf, recorded
--      in order_stock_moves against the order; accepting more than is
--      left is refused with the words above. Refusing a pending order
--      moves nothing. An order cancelled after it was accepted — by the
--      business, or a courier's failed delivery (073) — puts back exactly
--      what it took. Held by a trigger on orders, so every status path is
--      caught; idempotent by the table's unique key (an order takes once,
--      gives back once). No return of goods is added: a return is a
--      Correction (owner's word).
--      Handed over or delivered, the order is a sale: the trigger writes
--      it (sales.order_id, once per order) with the order's lines and its
--      money booked as record_sale books a cash or Wave sale — 'Ventes'
--      against the cash box or mobile money — without touching the shelf
--      again. Nobody rings a vitrine order at the till any more. An order
--      accepted before 101 (nothing taken) has its articles taken then, as
--      far as the shelf goes. Every kind: a shop's or a farm's order, and
--      an association's service booking (« terminée ») books its income
--      the same way. A finished order cannot be cancelled — no path ever
--      allowed it; the trigger now refuses it too.
--   3. The vitrine: place_order() refuses an article with nothing left
--      and a quantity above what is left (pre-orders and services aside),
--      and storefront_stock() tells the vitrine how many it may put in a
--      basket, so the stepper stops there. A new function rather than a
--      column on storefront_products(): 100 re-creates that one with its
--      own return type each time the bundle runs.
--   4. Analyses (Pro, or 'analytics' unlocked with cauris), held by the
--      server for a shop as for a farm: the five shop functions (043)
--      refuse without the tool, platform admins aside, as farm_analytics
--      does.
--      A farm's analyses:
--      farm_analytics() reads what the farm sold, what it spent, what its
--      flocks laid and lost and ate, this month against the last. Security
--      invoker: bound by the same RLS as the screens, and refused to
--      anyone without full visibility, to an association, and to a
--      business without the tool — the server holds the Pro line here,
--      not only the app.
--   5. apply_for_org() takes the applicant's name, phone and email from
--      their profile and their account: the app no longer asks a
--      signed-in person who they are to ask for another business.
--
-- Re-runnable (the bundle runs twice): tables and indexes if not exists,
-- triggers dropped and recreated, functions replaced in place with their
-- own signatures.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Stock never goes below zero
-- ------------------------------------------------------------

-- The one sentence, wherever the stock runs out. Numbers without trailing
-- zeros (3, not 3.000). The app reads it back (errors.dart) to say it in
-- the reader's language. Every refusal of stock is raised with SQLSTATE
-- MA001, so the till's outbox knows a refusal from a lost signal by its
-- code, not by its words.
create or replace function stock_short_message(p_name text, p_left numeric)
returns text
language sql
immutable
set search_path = public
as $$
    select case
        -- « Plus d'Aliment », « Plus d'huile »: de elides before a vowel or
        -- an h, as the app's own sentence does (stock_rule.dart).
        when coalesce(p_left, 0) <= 0
             and p_name ~ '^[AEIOUYHÀÂÄÉÈÊËÎÏÔÖÙÛÜŒÆaeiouyhàâäéèêëîïôöùûüœæ]'
            then format('Plus d''%s en stock', p_name)
        when coalesce(p_left, 0) <= 0 then format('Plus de %s en stock', p_name)
        else format('Il ne reste que %s %s', trim_scale(p_left)::text, p_name)
    end;
$$;

create or replace function trg_stock_not_below_zero()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_before numeric := case when tg_op = 'UPDATE' then old.quantity else 0 end;
begin
    if new.is_service then
        return new;
    end if;
    -- Below zero and lower than before: refused. An existing negative
    -- count may rise (a delivery, a return), never fall.
    if new.quantity < 0 and new.quantity < v_before then
        raise exception using message = stock_short_message(new.name, v_before),
                              errcode = 'MA001';
    end if;
    return new;
end;
$$;

-- After service_no_stock (098) in name order, so a service's count is
-- already back at zero when this reads it.
drop trigger if exists stock_not_below_zero on products;
create trigger stock_not_below_zero
before insert or update of quantity on products
for each row execute function trg_stock_not_below_zero();

-- The farm's consumables. Definer: the sum must see every movement of the
-- item, whoever records the sack (a worker without full visibility reads
-- none of them under 009's policy).
create or replace function trg_movement_not_below_zero()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_delta numeric := case new.kind
        when 'received' then new.quantity
        when 'consumed' then -new.quantity
        when 'wasted'   then -new.quantity
        else new.quantity end;
    v_name    text;
    v_on_hand numeric;
begin
    if v_delta >= 0 then
        return new;
    end if;
    select name into v_name from items where id = new.item_id for update;
    select coalesce(sum(case kind
                when 'received' then quantity
                when 'consumed' then -quantity
                when 'wasted'   then -quantity
                else quantity end), 0)
      into v_on_hand
      from stock_movements
     where item_id = new.item_id;
    if v_on_hand + v_delta < 0 then
        raise exception using message = stock_short_message(coalesce(v_name, 'cet article'), v_on_hand),
                              errcode = 'MA001';
    end if;
    return new;
end;
$$;

drop trigger if exists movement_not_below_zero on stock_movements;
create trigger movement_not_below_zero
before insert on stock_movements
for each row execute function trg_movement_not_below_zero();

-- ------------------------------------------------------------
-- 2. A vitrine order moves stock
-- ------------------------------------------------------------
create table if not exists order_stock_moves (
    id         uuid primary key default gen_random_uuid(),
    org_id     uuid not null references orgs(id) on delete cascade,
    order_id   uuid not null references orders(id) on delete cascade,
    product_id uuid not null references products(id) on delete cascade,
    -- 'out': left the shelf when the order was accepted. 'back': put back
    -- when the accepted order was cancelled. Always positive.
    direction  text not null check (direction in ('out', 'back')),
    quantity   numeric(14, 3) not null check (quantity > 0),
    created_at timestamptz not null default now(),
    unique (order_id, product_id, direction)
);

create index if not exists order_stock_moves_by_org
    on order_stock_moves (org_id, created_at desc);

comment on table order_stock_moves is
    'What a vitrine order took from the shelf when accepted, and gave back '
    'when cancelled (101). Written only by the orders trigger.';

alter table order_stock_moves enable row level security;
drop policy if exists "order stock moves readable within org" on order_stock_moves;
create policy "order stock moves readable within org"
on order_stock_moves for select using (is_org_member(org_id));

-- Read and written by the trigger alone: the app reads, nobody writes.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke insert, update, delete, truncate on order_stock_moves from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke insert, update, delete, truncate on order_stock_moves from anon;
    end if;
end $$;

-- A finished order is a sale (B1). Until now its money reached the books
-- only if someone rang it up again at the till — which, with the stock
-- already taken at acceptance, took the shelf twice (or was refused). The
-- order now records its own sale when it is handed over or delivered:
-- one sale per order, by this key, and no other.
alter table sales add column if not exists order_id uuid references orders(id);
create unique index if not exists sales_order_id_key on sales (order_id);

comment on column sales.order_id is
    'The vitrine order this sale is (101): written by the orders trigger '
    'when the order is picked up or delivered, never by the app.';

-- Staff may insert a sale under RLS (011). They may not claim an order's
-- sale: a row with that order's id would stop the order booking its own.
-- Invoker on purpose: the orders trigger writes as the table owner, the
-- API as authenticated.
create or replace function trg_sale_order_by_trigger()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
    if new.order_id is not null and current_user in ('authenticated', 'anon') then
        raise exception 'La vente d''une commande est enregistrée par la commande elle-même';
    end if;
    return new;
end;
$$;

drop trigger if exists sale_order_by_trigger on sales;
create trigger sale_order_by_trigger
before insert or update of order_id on sales
for each row execute function trg_sale_order_by_trigger();

create or replace function trg_order_moves_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    r          record;
    v_actor    uuid;
    v_sale     uuid;
    v_total    numeric := 0;
    v_entry    uuid;
    v_take     numeric;
begin
    -- Handed over or delivered cannot be cancelled: its sale is in the
    -- books and its goods are gone (decide_order has no way out of it, a
    -- courier fails only in transit). A return is a Correction.
    if old.status in ('picked_up', 'delivered') and new.status = 'cancelled' then
        raise exception 'Une commande remise ou livrée ne peut plus être annulée';
    end if;

    -- Accepted (or moved on from pending by any path): the articles leave.
    if old.status = 'pending'
       and new.status not in ('pending', 'refused', 'cancelled') then
        for r in
            select l.product_id, sum(l.quantity) as qty
              from order_lines l
              join products p on p.id = l.product_id
             where l.order_id = new.id
               and not l.is_service
               and not p.is_service
               -- A pre-order (083): nothing on the shelf to take yet.
               and not coalesce(p.available_from > (now() at time zone 'Africa/Ouagadougou')::date, false)
             group by l.product_id
        loop
            insert into order_stock_moves (org_id, order_id, product_id, direction, quantity)
            values (new.org_id, new.id, r.product_id, 'out', r.qty)
            on conflict (order_id, product_id, direction) do nothing;
            if found then
                update products set quantity = quantity - r.qty where id = r.product_id;
            end if;
        end loop;
    end if;

    -- Handed over or delivered: the order is a sale, booked once.
    if new.status in ('picked_up', 'delivered') then
        -- What did not leave at acceptance leaves now: an order accepted
        -- before 101, or a pre-order whose day has come. The goods are
        -- already in the customer's hands, so this takes what the shelf
        -- has and no more — a wrong count must not stop a courier at the
        -- door; the owner corrects it (Correction).
        for r in
            select l.product_id, sum(l.quantity) as qty
              from order_lines l
              join products p on p.id = l.product_id
             where l.order_id = new.id
               and not l.is_service
               and not p.is_service
               and not coalesce(p.available_from > (now() at time zone 'Africa/Ouagadougou')::date, false)
               and not exists (select 1 from order_stock_moves m
                                where m.order_id = new.id and m.product_id = l.product_id
                                  and m.direction = 'out')
             group by l.product_id
        loop
            select least(r.qty, greatest(quantity, 0)) into v_take
              from products where id = r.product_id for update;
            if v_take > 0 then
                insert into order_stock_moves (org_id, order_id, product_id, direction, quantity)
                values (new.org_id, new.id, r.product_id, 'out', v_take)
                on conflict (order_id, product_id, direction) do nothing;
                if found then
                    update products set quantity = quantity - v_take where id = r.product_id;
                end if;
            end if;
        end loop;

        -- Who closed it; a courier (073) or the platform is a profile too.
        -- A write with nobody signed in falls back to the owner.
        v_actor := coalesce(auth.uid(),
                            (select m.user_id from memberships m
                              where m.org_id = new.org_id and m.role = 'owner'
                              order by m.created_at limit 1),
                            new.customer_id);

        insert into sales (org_id, kind, occurred_at, method, note, recorded_by, order_id)
        values (new.org_id, 'sale', now(), coalesce(new.payment_method, 'cash'),
                'Commande de ' || new.customer_name, v_actor, new.id)
        on conflict (order_id) do nothing
        returning id into v_sale;

        if v_sale is not null then
            -- The lines as the customer was told them; the shelf is not
            -- touched here (it moved at acceptance, or just above).
            insert into sale_lines (sale_id, product_id, name, quantity,
                                    unit_price, unit_cost, line_total)
            select v_sale, l.product_id, l.name, l.quantity, l.unit_price,
                   coalesce(p.cost_price, 0), l.quantity * l.unit_price
              from order_lines l
              left join products p on p.id = l.product_id
             where l.order_id = new.id;
            select coalesce(sum(l.quantity * l.unit_price), 0) into v_total
              from order_lines l where l.order_id = new.id;

            -- The money, as record_sale books a cash or Wave sale: the cash
            -- box (or mobile money, 037) in, 'Ventes' credited. Written here
            -- rather than through record_entry, whose can_write_org a
            -- courier closing at the door does not pass.
            if v_total > 0 then
                insert into journal_entries (org_id, label, memo, details,
                                             created_by, created_at)
                values (new.org_id, 'Vente', 'Commande de ' || new.customer_name,
                        jsonb_build_object('sale_id', v_sale, 'order_id', new.id),
                        v_actor, now())
                returning id into v_entry;
                insert into journal_lines (journal_entry_id, account_id, debit, credit)
                values (v_entry, resolve_cash_account(new.org_id,
                                     coalesce(new.payment_method, 'cash'), v_actor),
                        v_total, 0),
                       (v_entry, ensure_account(new.org_id, 'Ventes', 'income', v_actor),
                        0, v_total);
            end if;
            update sales set total = v_total, entry_id = v_entry where id = v_sale;
        end if;
    end if;

    -- Cancelled after it took: exactly what it took comes back, once.
    if new.status = 'cancelled' and old.status <> 'cancelled' then
        for r in
            select m.product_id, m.quantity
              from order_stock_moves m
             where m.order_id = new.id and m.direction = 'out'
        loop
            insert into order_stock_moves (org_id, order_id, product_id, direction, quantity)
            values (new.org_id, new.id, r.product_id, 'back', r.quantity)
            on conflict (order_id, product_id, direction) do nothing;
            if found then
                update products set quantity = quantity + r.quantity where id = r.product_id;
            end if;
        end loop;
    end if;
    return new;
end;
$$;

drop trigger if exists order_moves_stock on orders;
create trigger order_moves_stock
after update of status on orders
for each row
when (old.status is distinct from new.status)
execute function trg_order_moves_stock();

-- ------------------------------------------------------------
-- 3. The vitrine: no more than what is left
-- ------------------------------------------------------------

-- How many of each article a basket may hold: what is on the shelf. Null
-- for what has no count to keep (a service, a pre-order) — no cap.
create or replace function storefront_stock(p_slug text)
returns table (id uuid, stock_left numeric)
language sql
stable
security definer
set search_path = public
as $$
    select p.id,
           case when p.is_service
                  or p.available_from > (now() at time zone 'Africa/Ouagadougou')::date
                then null
                else greatest(p.quantity, 0) end
    from products p
    where p.org_id = storefront_open(p_slug)
      and p.is_active
      and p.is_published;
$$;

-- 099's place_order, with one more rule: an article (not a service, not a
-- pre-order) is refused with nothing left or for more than is left. The
-- lines of one article are added up first, so splitting a basket into
-- two lines cannot get past it.
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
    v_note     text := nullif(btrim(coalesce(p_note, '')), '');
    v_services boolean;
    v_short    record;
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
    if p_lines is null or jsonb_typeof(p_lines) <> 'array'
       or jsonb_array_length(p_lines) = 0 then
        raise exception 'An order needs at least one article';
    end if;

    -- Services only: an appointment, not a parcel. Said before the
    -- delivery rules, so the customer hears the reason that applies.
    select coalesce(bool_and(coalesce(p.is_service, false)), false)
      into v_services
      from jsonb_array_elements(p_lines) l
      left join products p
        on p.id = nullif(l ->> 'product_id', '')::uuid and p.org_id = v_org;
    if v_services then
        if p_fulfilment <> 'pickup' then
            raise exception 'Un service se réserve sur rendez-vous : pas de livraison';
        end if;
        if v_note is null then
            raise exception 'Indiquez la date et l''heure souhaitées';
        end if;
    end if;

    -- 101: « Épuisé » cannot be ordered, nor more than is left.
    select p.name, p.quantity into v_short
      from jsonb_array_elements(p_lines) l
      join products p
        on p.id = nullif(l ->> 'product_id', '')::uuid and p.org_id = v_org
     where not p.is_service
       and not coalesce(p.available_from > (now() at time zone 'Africa/Ouagadougou')::date, false)
       and (l ->> 'quantity') is not null
     group by p.id, p.name, p.quantity
    having sum((l ->> 'quantity')::numeric) > greatest(p.quantity, 0)
     order by p.name
     limit 1;
    if found then
        raise exception using message = stock_short_message(v_short.name, v_short.quantity),
                              errcode = 'MA001';
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
            v_note,
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
        insert into order_lines (order_id, product_id, name, unit_price, quantity, is_service)
        values (v_id, v_product.id, v_product.name,
                coalesce(v_product.sale_price, 0), v_qty, v_product.is_service);
        v_total := v_total + coalesce(v_product.sale_price, 0) * v_qty;
    end loop;

    update orders set total = v_total where id = v_id;

    begin
        perform notify_org_admins(
            v_org, 'new_order',
            case when v_services then 'Nouvelle demande de ' else 'Nouvelle commande de ' end
            || v_name || ' : '
            || to_char(v_total, 'FM999G999G999D00') || ' '
            || coalesce(v_currency, 'XOF')
            || case when p_payment = 'wave' then ' (Wave)' else '' end
            || case when v_fee is not null
                    then ' + livraison ' || to_char(v_fee, 'FM999G999G999') else '' end,
            jsonb_build_object('to', 'shop', 'order_id', v_id, 'booking', v_services,
                               'name', v_name, 'total', v_total,
                               'currency', coalesce(v_currency, 'XOF'),
                               'wave', p_payment = 'wave', 'fee', v_fee));
    exception when others then
        null;
    end;

    return v_id;
end;
$$;

-- ------------------------------------------------------------
-- 4. A farm's analyses
-- ------------------------------------------------------------
-- One call, one jsonb: the screen draws it as it comes. p_since is the
-- window the owner picked (null: all of time); « month » is this calendar
-- month so far and « last_month » the one before, whatever the window.
create or replace function farm_analytics(
    p_org_id uuid,
    p_since  timestamptz default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
    v_tz      constant text := 'Africa/Ouagadougou';
    v_profile text;
    v_m0      timestamptz;
    v_m1      timestamptz;
    v_since   timestamptz := coalesce(p_since, '-infinity'::timestamptz);
    v_periods jsonb;
    v_out     jsonb;
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;
    select profile into v_profile from orgs where id = p_org_id;
    if v_profile in ('association', 'church') then
        raise exception 'Les analyses ne concernent pas une association';
    end if;
    if pro_locked(p_org_id, 'analytics') then
        raise exception 'Kaj Pro : les analyses font partie de Kaj Pro. Ouvrez Compte › Kaj Pro, ou débloquez-les avec vos cauris.';
    end if;

    v_m0 := date_trunc('month', now() at time zone v_tz) at time zone v_tz;
    v_m1 := (date_trunc('month', now() at time zone v_tz) - interval '1 month') at time zone v_tz;

    with periods(key, t0, t1) as (
        values ('month',      v_m0,    'infinity'::timestamptz),
               ('last_month', v_m1,    v_m0),
               ('window',     v_since, 'infinity'::timestamptz)
    ),
    money as (
        select je.created_at, a.type, a.name, jl.debit, jl.credit
          from journal_lines jl
          join journal_entries je on je.id = jl.journal_entry_id
          join accounts a on a.id = jl.account_id
         where je.org_id = p_org_id
           and a.type in ('income', 'expense')
    ),
    -- A finished order, dated when it was handed over or delivered: the
    -- sale written at that moment. Before 101 there is no such sale and
    -- the order's last change is the best date there is.
    done as (
        select o.total,
               coalesce((select s.occurred_at from sales s where s.order_id = o.id),
                        o.updated_at) as at
          from orders o
         where o.org_id = p_org_id and o.status in ('picked_up', 'delivered')
    )
    select jsonb_object_agg(pr.key, jsonb_build_object(
        'income', (select coalesce(sum(m.credit - m.debit), 0) from money m
                    where m.type = 'income' and m.created_at >= pr.t0 and m.created_at < pr.t1),
        'expenses', (select coalesce(sum(m.debit - m.credit), 0) from money m
                      where m.type = 'expense' and m.created_at >= pr.t0 and m.created_at < pr.t1),
        'eggs', (select coalesce(sum(ep.egg_count), 0) from egg_production ep
                  where ep.org_id = p_org_id
                    and ep.produced_on >= (pr.t0 at time zone v_tz)::date
                    and ep.produced_on <  (pr.t1 at time zone v_tz)::date),
        'deaths', (select trim_scale(coalesce(sum(fe.quantity), 0)) from flock_events fe
                    join flocks f on f.id = fe.flock_id
                   where f.org_id = p_org_id and fe.kind = 'mortality'
                     and fe.occurred_at >= pr.t0 and fe.occurred_at < pr.t1),
        'orders', (select count(*) from done d
                    where d.at >= pr.t0 and d.at < pr.t1),
        'orders_total', (select coalesce(sum(d.total), 0) from done d
                          where d.at >= pr.t0 and d.at < pr.t1),
        'production_cost', (select coalesce(sum(r.total_cost), 0) from production_runs r
                             where r.org_id = p_org_id
                               and r.occurred_at >= pr.t0 and r.occurred_at < pr.t1)
    ))
      into v_periods
      from periods pr;

    select jsonb_build_object(
        'periods', v_periods,
        -- What sold, best first: the sales' lines (a sale undone by a
        -- correction is out, as in 043). A finished vitrine order is a
        -- sale of its own since 101, so it is counted there, once.
        'products', coalesce((
            select jsonb_agg(jsonb_build_object('name', x.name, 'units', trim_scale(x.units),
                                                'revenue', x.revenue)
                             order by x.revenue desc, x.units desc, x.name)
              from (
                select min(s.name) as name, sum(s.quantity) as units,
                       sum(s.amount) as revenue
                  from (
                    select sl.name, sl.quantity, sl.line_total as amount
                      from sale_lines sl
                      join sales sa on sa.id = sl.sale_id
                     where sa.org_id = p_org_id and sa.kind = 'sale'
                       and not exists (select 1 from sales r where r.reverses_id = sa.id)
                       and sa.occurred_at >= v_since
                  ) s
                 group by lower(btrim(s.name))
                 limit 50
              ) x), '[]'::jsonb),
        -- Where the money went and came from, by the books' own accounts.
        'expenses', coalesce((
            select jsonb_agg(jsonb_build_object('name', y.name, 'amount', y.amount)
                             order by y.amount desc, y.name)
              from (select a.name, sum(jl.debit - jl.credit) as amount
                      from journal_lines jl
                      join journal_entries je on je.id = jl.journal_entry_id
                      join accounts a on a.id = jl.account_id
                     where je.org_id = p_org_id and a.type = 'expense'
                       and je.created_at >= v_since
                     group by a.name
                    having sum(jl.debit - jl.credit) > 0) y), '[]'::jsonb),
        'income', coalesce((
            select jsonb_agg(jsonb_build_object('name', y.name, 'amount', y.amount)
                             order by y.amount desc, y.name)
              from (select a.name, sum(jl.credit - jl.debit) as amount
                      from journal_lines jl
                      join journal_entries je on je.id = jl.journal_entry_id
                      join accounts a on a.id = jl.account_id
                     where je.org_id = p_org_id and a.type = 'income'
                       and je.created_at >= v_since
                     group by a.name
                    having sum(jl.credit - jl.debit) > 0) y), '[]'::jsonb),
        -- Each open flock: how many are left, how many died (in all and in
        -- the window), how well it lays.
        'flocks', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'batch_code', fs.batch_code, 'started', fs.started,
                       'alive', fs.alive, 'died', fs.died,
                       'died_window', (select trim_scale(coalesce(sum(fe.quantity), 0)) from flock_events fe
                                        where fe.flock_id = fs.flock_id and fe.kind = 'mortality'
                                          and fe.occurred_at >= v_since),
                       'eggs_7d', fs.eggs_7d, 'lay_rate', fs.lay_rate)
                   order by fs.batch_code)
              from flock_status(p_org_id) fs), '[]'::jsonb),
        -- What was eaten or used, item by item, this month against the last.
        'feed', coalesce((
            select jsonb_agg(jsonb_build_object('name', z.name, 'unit', z.unit,
                                                'month', trim_scale(z.month),
                                                'last_month', trim_scale(z.last_month),
                                                'window', trim_scale(z.win))
                             order by z.win desc, z.name)
              from (select i.name, i.unit,
                           coalesce(sum(sm.quantity) filter (where sm.occurred_at >= v_m0), 0) as month,
                           coalesce(sum(sm.quantity) filter (where sm.occurred_at >= v_m1
                                                               and sm.occurred_at < v_m0), 0) as last_month,
                           coalesce(sum(sm.quantity) filter (where sm.occurred_at >= v_since), 0) as win
                      from stock_movements sm
                      join items i on i.id = sm.item_id
                     where sm.org_id = p_org_id and sm.kind = 'consumed'
                     group by i.id, i.name, i.unit) z
             where z.win > 0 or z.month > 0 or z.last_month > 0), '[]'::jsonb),
        -- Money in and out by day, over the window.
        'daily', coalesce((
            select jsonb_agg(jsonb_build_object('day', d.day, 'income', d.income,
                                                'expenses', d.expenses) order by d.day)
              from (select (je.created_at at time zone v_tz)::date as day,
                           sum(case when a.type = 'income' then jl.credit - jl.debit else 0 end) as income,
                           sum(case when a.type = 'expense' then jl.debit - jl.credit else 0 end) as expenses
                      from journal_lines jl
                      join journal_entries je on je.id = jl.journal_entry_id
                      join accounts a on a.id = jl.account_id
                     where je.org_id = p_org_id and a.type in ('income', 'expense')
                       and je.created_at >= v_since
                     group by 1) d), '[]'::jsonb)
    ) into v_out;

    return v_out;
end;
$$;

-- ------------------------------------------------------------
-- 4b. A shop's analyses, held by the server too
-- ------------------------------------------------------------
-- Until now only the app kept a free shop out of its Analyses: the five
-- functions behind the screen (043) answered anyone with full visibility.
-- They now refuse without the 'analytics' tool (Pro, or unlocked with
-- cauris), with the farm's words; pro_locked() lets a platform admin
-- through. Bodies are 043's verbatim apart from that check; return types
-- unchanged, so create or replace keeps their grants.
create or replace function org_sales_headline(
    p_org_id uuid,
    p_since  timestamptz default null
)
returns table (
    sale_count      bigint,
    revenue         numeric,
    cost            numeric,
    margin          numeric,
    units           numeric,
    avg_basket      numeric,
    products_sold   bigint
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;
    if pro_locked(p_org_id, 'analytics') then
        raise exception 'Kaj Pro : les analyses font partie de Kaj Pro. Ouvrez Compte › Kaj Pro, ou débloquez-les avec vos cauris.';
    end if;

    return query
    with s as (
        select sa.id, sa.total
        from sales sa
        where sa.org_id = p_org_id
          and sa.kind = 'sale'
          and not exists (select 1 from sales r where r.reverses_id = sa.id)
          and (p_since is null or sa.occurred_at >= p_since)
    ),
    lines as (
        select sl.quantity, sl.unit_cost, sl.line_total, sl.name
        from sale_lines sl
        join s on s.id = sl.sale_id
    )
    select
        (select count(*) from s),
        coalesce((select sum(total) from s), 0),
        coalesce((select sum(quantity * unit_cost) from lines), 0),
        coalesce((select sum(line_total) from lines), 0)
            - coalesce((select sum(quantity * unit_cost) from lines), 0),
        coalesce((select sum(quantity) from lines), 0),
        case when (select count(*) from s) = 0 then 0
             else round(coalesce((select sum(total) from s), 0)
                  / (select count(*) from s), 2) end,
        (select count(distinct lower(btrim(name))) from lines);
end;
$$;

create or replace function org_product_performance(
    p_org_id uuid,
    p_since  timestamptz default null,
    p_limit  int default 100
)
returns table (
    name          text,
    units         numeric,
    revenue       numeric,
    margin        numeric,
    sale_count    bigint,
    first_sold    timestamptz,
    last_sold     timestamptz,
    per_day       numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;
    if pro_locked(p_org_id, 'analytics') then
        raise exception 'Kaj Pro : les analyses font partie de Kaj Pro. Ouvrez Compte › Kaj Pro, ou débloquez-les avec vos cauris.';
    end if;

    return query
    with lines as (
        select lower(btrim(sl.name)) as key,
               sl.name as raw_name,
               sl.quantity, sl.unit_cost, sl.line_total, sa.occurred_at
        from sale_lines sl
        join sales sa on sa.id = sl.sale_id
        where sa.org_id = p_org_id
          and sa.kind = 'sale'
          and not exists (select 1 from sales r where r.reverses_id = sa.id)
          and (p_since is null or sa.occurred_at >= p_since)
    )
    select
        min(raw_name),
        sum(quantity),
        sum(line_total),
        sum(line_total) - sum(quantity * unit_cost),
        count(*),
        min(occurred_at),
        max(occurred_at),
        round(
            sum(quantity)
            / greatest(1, extract(epoch from (max(occurred_at) - min(occurred_at))) / 86400.0),
            2
        )
    from lines
    group by key
    order by 3 desc
    limit greatest(1, p_limit);
end;
$$;

create or replace function org_sales_by_hour(
    p_org_id uuid,
    p_since  timestamptz default null
)
returns table (
    hour        int,
    sale_count  bigint,
    revenue     numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;
    if pro_locked(p_org_id, 'analytics') then
        raise exception 'Kaj Pro : les analyses font partie de Kaj Pro. Ouvrez Compte › Kaj Pro, ou débloquez-les avec vos cauris.';
    end if;

    return query
    select
        extract(hour from sa.occurred_at)::int,
        count(*),
        coalesce(sum(sa.total), 0)
    from sales sa
    where sa.org_id = p_org_id
      and sa.kind = 'sale'
      and not exists (select 1 from sales r where r.reverses_id = sa.id)
      and (p_since is null or sa.occurred_at >= p_since)
    group by 1
    order by 1;
end;
$$;

create or replace function org_sales_by_weekday(
    p_org_id uuid,
    p_since  timestamptz default null
)
returns table (
    dow         int,
    sale_count  bigint,
    revenue     numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;
    if pro_locked(p_org_id, 'analytics') then
        raise exception 'Kaj Pro : les analyses font partie de Kaj Pro. Ouvrez Compte › Kaj Pro, ou débloquez-les avec vos cauris.';
    end if;

    return query
    select
        extract(dow from sa.occurred_at)::int,
        count(*),
        coalesce(sum(sa.total), 0)
    from sales sa
    where sa.org_id = p_org_id
      and sa.kind = 'sale'
      and not exists (select 1 from sales r where r.reverses_id = sa.id)
      and (p_since is null or sa.occurred_at >= p_since)
    group by 1
    order by 1;
end;
$$;

create or replace function org_sales_daily(
    p_org_id uuid,
    p_since  timestamptz default null
)
returns table (
    day         date,
    sale_count  bigint,
    revenue     numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;
    if pro_locked(p_org_id, 'analytics') then
        raise exception 'Kaj Pro : les analyses font partie de Kaj Pro. Ouvrez Compte › Kaj Pro, ou débloquez-les avec vos cauris.';
    end if;

    return query
    select
        (sa.occurred_at at time zone 'UTC')::date,
        count(*),
        coalesce(sum(sa.total), 0)
    from sales sa
    where sa.org_id = p_org_id
      and sa.kind = 'sale'
      and not exists (select 1 from sales r where r.reverses_id = sa.id)
      and (p_since is null or sa.occurred_at >= p_since)
    group by 1
    order by 1;
end;
$$;

-- ------------------------------------------------------------
-- 5. A second business, asked for by who is signed in
-- ------------------------------------------------------------
-- 017's apply_for_org, its signature kept (an older build still sends a
-- phone or an email; they are used only when the account has none). The
-- person's name, phone and email come from their profile and their
-- account.
create or replace function apply_for_org(
    p_name        text,
    p_slug        text,
    p_profile     text default 'generic',
    p_currency    text default 'XOF',
    p_description text default null,
    p_phone       text default null,
    p_email       text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor   uuid := auth.uid();
    v_name    text := nullif(btrim(coalesce(p_name, '')), '');
    v_slug    text := nullif(lower(btrim(coalesce(p_slug, ''))), '');
    v_problem text;
    v_id      uuid;
    v_full    text;
    v_phone   text;
    v_email   text;
begin
    if v_actor is null then
        raise exception 'apply_for_org() needs a signed-in caller';
    end if;

    if v_name is null then
        raise exception 'A business needs a name';
    end if;

    v_problem := org_slug_problem(v_slug);
    if v_problem is not null then
        raise exception '%', v_problem;
    end if;

    if exists (select 1 from orgs where slug = v_slug) then
        raise exception 'That address is already taken.';
    end if;

    -- Who this is, as the platform will see it in the queue: the profile
    -- first, then the account, then what an older build sent.
    select coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                    nullif(btrim(coalesce(p.full_name, '')), ''),
                    nullif(btrim(coalesce(u.raw_user_meta_data ->> 'full_name', '')), '')),
           coalesce(nullif(btrim(coalesce(p.phone, '')), ''),
                    nullif(btrim(coalesce(u.phone, '')), '')),
           nullif(btrim(coalesce(u.email, '')), '')
      into v_full, v_phone, v_email
      from auth.users u
      left join profiles p on p.id = u.id
     where u.id = v_actor;

    insert into org_applications (
        applicant_id, name, slug, profile, currency,
        contact_name, contact_phone, contact_email, description
    )
    values (
        v_actor, v_name, v_slug,
        coalesce(nullif(btrim(coalesce(p_profile, '')), ''), 'generic'),
        coalesce(nullif(btrim(coalesce(p_currency, '')), ''), 'XOF'),
        v_full,
        coalesce(v_phone, nullif(btrim(coalesce(p_phone, '')), '')),
        coalesce(v_email, nullif(btrim(coalesce(p_email, '')), '')),
        nullif(btrim(coalesce(p_description, '')), '')
    )
    on conflict (applicant_id) where status = 'pending'
    do update set
        name          = excluded.name,
        slug          = excluded.slug,
        profile       = excluded.profile,
        currency      = excluded.currency,
        description   = excluded.description,
        contact_name  = excluded.contact_name,
        contact_phone = excluded.contact_phone,
        contact_email = excluded.contact_email,
        created_at    = now()
    returning id into v_id;

    return v_id;
end;
$$;

-- ------------------------------------------------------------
-- Grants (063: born closed to anon and PUBLIC; Supabase hands new
-- functions to authenticated, which the internal ones must not keep)
-- ------------------------------------------------------------
revoke execute on function stock_short_message(text, numeric)   from public;
revoke execute on function trg_stock_not_below_zero()           from public;
revoke execute on function trg_movement_not_below_zero()        from public;
revoke execute on function trg_order_moves_stock()              from public;
revoke execute on function trg_sale_order_by_trigger()          from public;
revoke execute on function storefront_stock(text)               from public;
revoke execute on function farm_analytics(uuid, timestamptz)    from public;
revoke execute on function place_order(text, jsonb, text, text, text, text, text, double precision, double precision) from public;
revoke execute on function apply_for_org(text, text, text, text, text, text, text) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function stock_short_message(text, numeric)   from anon;
        revoke execute on function trg_stock_not_below_zero()           from anon;
        revoke execute on function trg_movement_not_below_zero()        from anon;
        revoke execute on function trg_order_moves_stock()              from anon;
        revoke execute on function trg_sale_order_by_trigger()          from anon;
        revoke execute on function farm_analytics(uuid, timestamptz)    from anon;
        revoke execute on function place_order(text, jsonb, text, text, text, text, text, double precision, double precision) from anon;
        revoke execute on function apply_for_org(text, text, text, text, text, text, text) from anon;
        -- The street reads how many it may put in a basket, signed in or not.
        grant execute on function storefront_stock(text)                to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Triggers and the sentence: nobody calls them by hand (the
        -- triggers are definers, so the sentence runs as their owner).
        revoke execute on function stock_short_message(text, numeric)   from authenticated;
        revoke execute on function trg_movement_not_below_zero()        from authenticated;
        revoke execute on function trg_order_moves_stock()              from authenticated;
        revoke execute on function trg_sale_order_by_trigger()          from authenticated;
        revoke execute on function trg_stock_not_below_zero()           from authenticated;
        grant execute on function storefront_stock(text)                to authenticated;
        grant execute on function farm_analytics(uuid, timestamptz)    to authenticated;
        grant execute on function place_order(text, jsonb, text, text, text, text, text, double precision, double precision) to authenticated;
        grant execute on function apply_for_org(text, text, text, text, text, text, text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
