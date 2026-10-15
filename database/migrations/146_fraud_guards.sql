-- ============================================================
-- 146_fraud_guards.sql — batch 151 « Protections contre la fraude », for a
-- shop, a farm and an association as each says.
--
-- The owner approved the list. What the server holds:
--
--   1. ORDER LIMITS (shop, farm, association — every vitrine takes orders
--      and bookings through place_order / book_service). A trigger on
--      orders, as 142's orders_terms_check, so place_order (131's), the
--      booking door (125's book_service, which calls it) and any later
--      door meet the same rules without their bodies being copied again:
--        * a shopper holds at most `order_open_max_per_shop` open orders
--          (pending, accepted, ready, in transit — made in the last 7 days,
--          a booking whose slot passed a day ago not counted) at one
--          business — 3 as installed;
--        * an account with no finished order anywhere yet (nothing handed
--          over or delivered) holds at most `order_first_open_max` open
--          orders across every business — 2 as installed;
--        * 0 turns either rule off. Both in Réglages › Vitrines ›
--          Commandes, 0 to 50, checked by platform_set_setting.
--      Only the shopper's own insert is asked (customer_id = auth.uid()):
--      a business recording, a migration, a test seeding are not.
--      Refused in plain French the app translates (P0001).
--
--   2. « BLOQUER CE CLIENT » (shop, farm, association). blocked_customers,
--      one row per business and shopper, RLS on: the business's admins
--      read, add (only a shopper who ordered from it) and remove; nobody
--      else sees anything, the shopper included; anon nothing at all.
--      block_customer(order) and unblock_customer(org, customer) are
--      SECURITY INVOKER on purpose — bound by those same policies, as
--      record_* are. Journaled by 008's audit_row (the business's
--      Activité). The same trigger refuses a blocked shopper's order with
--      a sentence that does not say « bloqué »: « Cette boutique (ferme,
--      association) ne prend pas votre commande pour le moment. »
--
--   3. A COURIER'S CASH CAP (the couriers: every vitrine's deliveries).
--      Couriers are reviewed already (056 pending / approved / suspended,
--      decide_courier; 112's dossier, approve / refuse / ask again; the
--      console's « Livreurs à valider ») — nothing to add there. The gap
--      was the cash: take_delivery (099's) now refuses a cash order that
--      would put more than `courier_cash_cap` (50 000 as installed, 0 =
--      no cap) of shops' money in one courier's hands — the goods' price
--      of cash orders taken and not yet confirmed received by the shop
--      (ready with this courier, in transit, delivered and not handed
--      over). Per money (140's rule: never added across moneys): the cap
--      is in francs CFA and applies to XOF and XAF orders, each money
--      counted on its own; an order in another money is not capped (said
--      in BUILD_PLAN). The courier's row is locked while it is checked,
--      so two taps cannot both pass. courier_cash_status() says, money by
--      money, what the courier holds and the cap, for the courier page.
--
--   4. A RETURN NEEDS THE OWNER (shop; the farm records no return — its
--      Corrections are 033's in-place edits — and an association's sales
--      are not a till). record_return (104's) let any member who could
--      write give a sale's money back; it is now an owner's or an
--      administrator's alone, as reverse_receipt always was and as the
--      app has only ever offered Corrections to them. 104's body verbatim
--      otherwise, SECURITY DEFINER and grants unchanged.
--
--   5. « CLÔTURER LA CAISSE » (shop and farm: both sell at a till through
--      SaleFlow into `sales`; an association closes its day on the phone,
--      unchanged). till_closings, append-only: a closing writes the cash
--      counted (blind — the expected is computed and shown after), the
--      change the till started with, the day's cash sales and cash
--      returns, the expected, the gap. close_till() is SECURITY DEFINER
--      on purpose: the expected must be the server's sum, which no policy
--      can check on a row the client writes; it lets in a member who can
--      write the business (can_write_org — not an observer), refuses an
--      association. The business's admins read every closing, a cashier
--      their own (RLS); nobody writes the table. Journaled by audit_row.
--      The day is the phone's, from local midnight (145's offset).
--      Counter sales and pickup orders count; a delivered order's cash is
--      the courier's to hand over (073), not the till's.
--
--   6. MARA'S REVIEW QUEUE. review_todo_counts() adds one counter to
--      « À faire » (the businesses, couriers and closings below), as
--      help_todo_counts and spot_refunds_todo do; platform_review_queue()
--      lists them: businesses with 3 blocks in 30 days or 5 refused
--      orders in 7, couriers over the cap, closings in the last 7 days
--      whose gap reaches `till_gap_review` (5 000 FCFA as installed, XOF
--      and XAF), and — counted only, linked to where they already live —
--      the open reports (113's Signalements) and the couriers waiting for
--      review. The platform's alone.
--
-- Born closed (063): the internal helpers to everyone, the app's doors
-- granted to authenticated, nothing to anon. The tables' policies call
-- is_org_admin and can_write_org only (test_least_privilege's six).
--
-- Re-runnable: tables and columns if not exists, policies and triggers
-- dropped and made again, functions replaced, settings on conflict do
-- nothing, grants said again.
-- ============================================================

do $$
begin
    if to_regprocedure('public.trg_orders_terms()') is null
       or to_regprocedure('public.store_day(uuid, date, integer)') is null
       or to_regprocedure('public.audit_row()') is null
       or to_regprocedure('public.spot_setting(text, numeric)') is null then
        raise exception '146 needs 142 (trg_orders_terms), 145 (store_day by offset), 008 (audit_row) and 071 (spot_setting) applied first';
    end if;
end $$;

insert into platform_settings (key, value) values
    ('order_open_max_per_shop', '3'),
    ('order_first_open_max',    '2'),
    ('courier_cash_cap',        '50000'),
    ('till_gap_review',         '5000')
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- 2. Blocked shoppers, per business
-- ------------------------------------------------------------
create table if not exists blocked_customers (
    id          uuid not null default gen_random_uuid() unique,
    org_id      uuid not null references orgs(id) on delete cascade,
    customer_id uuid not null references profiles(id) on delete cascade,
    -- The name the orders carried when blocked: what the list and the
    -- business's Activité say (008's audit_row reads `name`).
    name        text,
    reason      text check (reason is null or char_length(reason) <= 200),
    order_id    uuid references orders(id) on delete set null,
    blocked_by  uuid references profiles(id) on delete set null default auth.uid(),
    created_at  timestamptz not null default now(),
    primary key (org_id, customer_id)
);

comment on table blocked_customers is
    'Shoppers a business no longer takes orders from (146). Read, added and '
    'removed by the business''s admins only (RLS); the shopper is told only '
    'that the business does not take the order for now.';

alter table blocked_customers enable row level security;

drop policy if exists "blocked customers read by the business admins" on blocked_customers;
create policy "blocked customers read by the business admins"
on blocked_customers for select
using (is_org_admin(org_id));

-- Only a shopper who ordered from this business, never oneself.
drop policy if exists "blocked customers added by the business admins" on blocked_customers;
create policy "blocked customers added by the business admins"
on blocked_customers for insert
with check (is_org_admin(org_id)
            and customer_id <> auth.uid()
            and exists (select 1 from orders o
                         where o.org_id = blocked_customers.org_id
                           and o.customer_id = blocked_customers.customer_id));

drop policy if exists "blocked customers removed by the business admins" on blocked_customers;
create policy "blocked customers removed by the business admins"
on blocked_customers for delete
using (is_org_admin(org_id));

-- No update policy: a block is made or undone, never edited.

-- 127's guard: the order a block names is the business's own.
drop trigger if exists same_org on blocked_customers;
create trigger same_org before insert or update on blocked_customers
for each row execute function trg_same_org('order_id:orders');

drop trigger if exists audit_blocked_customers on blocked_customers;
create trigger audit_blocked_customers
after insert or update or delete on blocked_customers
for each row execute function audit_row();

-- « Bloquer ce client », from one of the business's orders. INVOKER: the
-- order is read and the row written under the caller's own policies.
create or replace function block_customer(p_order_id uuid, p_reason text default null)
returns void
language plpgsql
security invoker
set search_path = public, auth
as $$
declare
    v_order record;
    v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    select o.org_id, o.customer_id, o.customer_name into v_order
      from orders o where o.id = p_order_id;
    if not found or not is_org_admin(v_order.org_id) then
        raise exception 'Seul le propriétaire ou un administrateur bloque un client';
    end if;
    if v_order.customer_id is null then
        raise exception 'Cette commande n''a pas de compte client à bloquer';
    end if;
    if v_order.customer_id = auth.uid() then
        raise exception 'Vous ne pouvez pas vous bloquer vous-même';
    end if;
    if v_reason is not null and char_length(v_reason) > 200 then
        v_reason := left(v_reason, 200);
    end if;
    insert into blocked_customers (org_id, customer_id, name, reason, order_id, blocked_by)
    values (v_order.org_id, v_order.customer_id, v_order.customer_name, v_reason,
            p_order_id, auth.uid())
    on conflict (org_id, customer_id) do nothing;
end;
$$;

create or replace function unblock_customer(p_org_id uuid, p_customer_id uuid)
returns void
language plpgsql
security invoker
set search_path = public, auth
as $$
begin
    if auth.uid() is null or not is_org_admin(p_org_id) then
        raise exception 'Seul le propriétaire ou un administrateur débloque un client';
    end if;
    delete from blocked_customers where org_id = p_org_id and customer_id = p_customer_id;
end;
$$;

-- ------------------------------------------------------------
-- 1 and 2. The door of every order
-- ------------------------------------------------------------
-- A shopper's open orders (the 7 days' window, a passed slot left out).
create or replace function shopper_open_orders(p_customer uuid, p_org uuid default null)
returns int
language sql
stable
security definer
set search_path = public
as $$
    select count(*)::int from orders o
     where o.customer_id = p_customer
       and (p_org is null or o.org_id = p_org)
       and o.status in ('pending', 'accepted', 'ready', 'in_transit')
       and o.created_at > now() - interval '7 days'
       and not coalesce(o.booked_for < now() - interval '1 day', false);
$$;

create or replace function trg_orders_guard()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_profile text;
    v_shop    int := spot_setting('order_open_max_per_shop', 3)::int;
    v_first   int := spot_setting('order_first_open_max', 2)::int;
begin
    -- The shopper's own order only: a business, a migration, a test
    -- seeding the table are not asked.
    if new.customer_id is null or new.customer_id is distinct from auth.uid() then
        return new;
    end if;
    if exists (select 1 from blocked_customers b
                where b.org_id = new.org_id and b.customer_id = new.customer_id) then
        select profile into v_profile from orgs where id = new.org_id;
        raise exception '%', case
            when v_profile = 'farm' then 'Cette ferme ne prend pas votre commande pour le moment.'
            when v_profile in ('association', 'church') then 'Cette association ne prend pas votre commande pour le moment.'
            else 'Cette boutique ne prend pas votre commande pour le moment.' end;
    end if;
    if v_shop > 0 and shopper_open_orders(new.customer_id, new.org_id) >= v_shop then
        raise exception 'Vous avez déjà plusieurs commandes en cours ici : attendez qu''une soit terminée pour en passer une autre.';
    end if;
    if v_first > 0
       and not exists (select 1 from orders o
                        where o.customer_id = new.customer_id
                          and o.status in ('picked_up', 'delivered'))
       and shopper_open_orders(new.customer_id) >= v_first then
        raise exception 'Un nouveau compte a peu de commandes en cours à la fois : attendez que l''une d''elles soit terminée.';
    end if;
    return new;
end;
$$;

-- After 142's orders_terms_check (triggers fire by name): the terms first.
drop trigger if exists orders_trust_guard on orders;
create trigger orders_trust_guard
before insert on orders
for each row execute function trg_orders_guard();

-- ------------------------------------------------------------
-- 3. A courier's cash
-- ------------------------------------------------------------
-- The cap for a money: francs CFA only; null = none.
create or replace function courier_cash_cap_for(p_currency text)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
    select case when upper(coalesce(p_currency, 'XOF')) in ('XOF', 'XAF')
                then nullif(spot_setting('courier_cash_cap', 50000), 0) end;
$$;

-- The shops' cash in a courier's hands, in one money.
create or replace function courier_cash_carried(p_courier uuid, p_currency text)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(sum(o.total), 0) from orders o
     where o.courier_id = p_courier
       and o.payment_method = 'cash'
       and o.paid_at is null and o.cash_received_at is null
       and o.status in ('ready', 'in_transit', 'delivered')
       and upper(coalesce(o.currency, 'XOF')) = upper(coalesce(p_currency, 'XOF'));
$$;

-- 099's take_delivery, with the cap (146).
create or replace function take_delivery(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_order orders%rowtype; v_shop text; v_cap numeric; v_held numeric; v_job orders%rowtype;
begin
    perform assert_approved_courier();
    if not courier_may_take(p_order_id, auth.uid()) then
        raise exception 'Cette boutique a ses livreurs : la course s''ouvre à tous dans quelques minutes';
    end if;
    -- 146: a cash order within the cap. The courier's row is held while
    -- it is counted, so two taps at once are counted one after the other.
    select * into v_job from orders where id = p_order_id;
    if found and v_job.payment_method = 'cash' and v_job.paid_at is null then
        v_cap := courier_cash_cap_for(v_job.currency);
        if v_cap is not null then
            perform 1 from couriers where user_id = auth.uid() for update;
            v_held := courier_cash_carried(auth.uid(), v_job.currency);
            if v_held + coalesce(v_job.total, 0) > v_cap then
                if v_held = 0 then
                    raise exception 'Cette course dépasse ce qu''un livreur peut porter en espèces : la boutique la livre elle-même.';
                end if;
                raise exception 'Vous portez déjà assez d''espèces : remettez l''argent aux boutiques avant de prendre une autre course payée en espèces.';
            end if;
        end if;
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
            'Un livreur prend la commande de ' || v_order.customer_name,
            jsonb_build_object('to', 'shop', 'order_id', v_order.id,
                               'name', v_order.customer_name));
        insert into notifications (recipient_id, org_id, kind, message, params)
        values (v_order.customer_id, v_order.org_id, 'order_courier',
                'Un livreur s''occupe de votre commande chez ' || v_shop,
                jsonb_build_object('to', 'customer', 'order_id', v_order.id,
                                   'shop', v_shop));
    exception when others then
        null;
    end;
end;
$$;

-- What the courier holds, money by money, and the cap: francs CFA always
-- (the cap is said even with nothing held), every other money held too.
create or replace function courier_cash_status()
returns table (currency text, held numeric, cap numeric)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    perform assert_approved_courier();
    return query
    with moneys as (
        select 'XOF'::text as c
        union
        select upper(coalesce(o.currency, 'XOF')) from orders o
         where o.courier_id = auth.uid()
           and o.payment_method = 'cash'
           and o.paid_at is null and o.cash_received_at is null
           and o.status in ('ready', 'in_transit', 'delivered')
    )
    select m.c, courier_cash_carried(auth.uid(), m.c), courier_cash_cap_for(m.c)
      from moneys m
     order by (m.c = 'XOF') desc, m.c;
end;
$$;

-- ------------------------------------------------------------
-- 4. A return, the owner's (104's record_return, guarded)
-- ------------------------------------------------------------
create or replace function record_return(
    p_sale_id     uuid,
    p_note        text default null,
    p_client_uuid uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_org      uuid;
    v_method   text;
    v_total    numeric;
    v_kind     text;
    v_return   uuid;
    v_existing uuid;
    v_line     record;
    v_entry    uuid;
begin
    select org_id, method, total, kind
      into v_org, v_method, v_total, v_kind
    from sales where id = p_sale_id;

    if v_org is null then
        raise exception 'No such sale';
    end if;

    -- SECURITY (032): a zero-total return posts no entry and so met no gate.
    if not can_write_org(v_org) then
        raise exception 'You cannot record a return for this business';
    end if;
    -- 146: money given back is the owner's or an administrator's call.
    if not is_org_admin(v_org) then
        raise exception 'Seul le propriétaire ou un administrateur fait un retour de vente.';
    end if;
    perform feature_guard(v_org, 'corrections');

    if v_kind = 'return' then
        raise exception 'That is already a return';
    end if;
    if v_method = 'credit' then
        raise exception 'A credit sale is settled in the carnet, not by a return';
    end if;
    if exists (select 1 from sales where reverses_id = p_sale_id) then
        raise exception 'That sale has already been returned';
    end if;

    if p_client_uuid is not null then
        select id into v_existing from sales
        where org_id = v_org and client_uuid = p_client_uuid;
        if v_existing is not null then
            return v_existing;
        end if;
    end if;

    insert into sales (org_id, kind, method, note, total, reverses_id,
                       recorded_by, client_uuid)
    values (v_org, 'return', v_method, p_note, v_total, p_sale_id,
            v_actor, p_client_uuid)
    returning id into v_return;

    for v_line in select * from sale_lines where sale_id = p_sale_id
    loop
        insert into sale_lines (sale_id, product_id, name, quantity,
                                unit_price, unit_cost, line_total)
        values (v_return, v_line.product_id, v_line.name, v_line.quantity,
                v_line.unit_price, v_line.unit_cost, v_line.line_total);

        update products set quantity = quantity + v_line.quantity
        where id = v_line.product_id;
    end loop;

    if v_total > 0 then
        v_entry := record_entry(
            p_org_id      => v_org,
            p_amount      => v_total,
            p_direction   => 'out',
            p_label       => 'Retour de vente',
            p_recorded_by => v_actor,
            p_category    => 'Ventes',
            p_method      => v_method,
            p_memo        => p_note,
            p_details     => jsonb_build_object('reverses', p_sale_id),
            p_client_uuid => p_client_uuid
        );
        update sales set entry_id = v_entry where id = v_return;
    end if;

    return v_return;
end;
$$;

-- ------------------------------------------------------------
-- 5. Closing the till
-- ------------------------------------------------------------
create table if not exists till_closings (
    id                 uuid primary key default gen_random_uuid(),
    org_id             uuid not null references orgs(id) on delete cascade,
    day                date not null,
    utc_offset_minutes int not null default 0,
    currency           text not null default 'XOF',
    opening_float      numeric(14,2) not null default 0,
    cash_sales         numeric(14,2) not null default 0,
    cash_returns       numeric(14,2) not null default 0,
    expected           numeric(14,2) not null default 0,
    counted            numeric(14,2) not null,
    gap                numeric(14,2) not null,
    note               text,
    -- What the business's Activité says (008's audit_row reads `label`).
    label              text,
    closed_by          uuid references profiles(id) on delete set null,
    closer_name        text,
    closed_at          timestamptz not null default now()
);

create index if not exists till_closings_by_org on till_closings (org_id, closed_at desc);

comment on table till_closings is
    'End-of-day till closings (146): cash counted against the server''s '
    'expected. Written only by close_till(); read by the business''s admins, '
    'a cashier their own.';

alter table till_closings enable row level security;

drop policy if exists "till closings read by admins and their closer" on till_closings;
create policy "till closings read by admins and their closer"
on till_closings for select
using (is_org_admin(org_id) or (closed_by = auth.uid() and can_write_org(org_id)));

-- No insert, update or delete policy: close_till alone writes, once per
-- closing; a closing done again is a new row, the first one kept.

drop trigger if exists audit_till_closings on till_closings;
create trigger audit_till_closings
after insert or update or delete on till_closings
for each row execute function audit_row();

create or replace function close_till(
    p_org_id             uuid,
    p_day                date,
    p_utc_offset_minutes int,
    p_counted            numeric,
    p_float              numeric default 0,
    p_note               text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org     orgs%rowtype;
    v_from    timestamptz;
    v_to      timestamptz;
    v_sales   numeric;
    v_returns numeric;
    v_float   numeric := coalesce(p_float, 0);
    v_expect  numeric;
    v_name    text;
    v_row     till_closings%rowtype;
    v_note    text := nullif(btrim(coalesce(p_note, '')), '');
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if not found or not can_write_org(p_org_id) then
        raise exception 'Vous ne pouvez pas clôturer la caisse de cette activité';
    end if;
    if v_org.profile in ('association', 'church') then
        raise exception 'Une association clôture sa journée, pas une caisse';
    end if;
    if p_day is null or p_day > current_date + 1 or p_day < current_date - 31 then
        raise exception 'Choisissez un jour des 31 derniers jours';
    end if;
    if p_utc_offset_minutes is null or p_utc_offset_minutes not between -840 and 840 then
        raise exception 'Décalage horaire invalide : %', p_utc_offset_minutes using errcode = '22023';
    end if;
    if p_counted is null or p_counted < 0 or v_float < 0
       or p_counted > 1000000000 or v_float > 1000000000 then
        raise exception 'Indiquez un montant positif';
    end if;
    if v_note is not null and char_length(v_note) > 300 then
        v_note := left(v_note, 300);
    end if;

    -- 145's local day.
    v_from := (p_day::timestamp - make_interval(mins => p_utc_offset_minutes)) at time zone 'UTC';
    v_to   := v_from + interval '1 day';

    -- The till's cash: counter sales and pickup orders paid in cash; a
    -- delivered order's cash comes back through its courier (073).
    select coalesce(sum(s.total) filter (where s.kind = 'sale'
                                          and not exists (select 1 from orders o
                                                           where o.id = s.order_id
                                                             and o.fulfilment = 'delivery')), 0),
           coalesce(sum(s.total) filter (where s.kind = 'return'), 0)
      into v_sales, v_returns
      from sales s
     where s.org_id = p_org_id
       and s.method = 'cash'
       and s.occurred_at >= v_from and s.occurred_at < v_to;
    v_expect := v_float + v_sales - v_returns;

    select coalesce(nullif(btrim(coalesce(full_name, '')), ''), 'Membre') into v_name
      from profiles where id = auth.uid();

    insert into till_closings (org_id, day, utc_offset_minutes, currency, opening_float,
                               cash_sales, cash_returns, expected, counted, gap, note,
                               label, closed_by, closer_name)
    values (p_org_id, p_day, p_utc_offset_minutes, coalesce(v_org.default_currency, 'XOF'),
            v_float, v_sales, v_returns, v_expect, p_counted, p_counted - v_expect, v_note,
            'Clôture de caisse du ' || to_char(p_day, 'DD/MM/YYYY'), auth.uid(), v_name)
    returning * into v_row;

    return jsonb_build_object(
        'id', v_row.id, 'day', v_row.day, 'currency', v_row.currency,
        'opening_float', v_row.opening_float, 'cash_sales', v_row.cash_sales,
        'cash_returns', v_row.cash_returns, 'expected', v_row.expected,
        'counted', v_row.counted, 'gap', v_row.gap, 'closed_at', v_row.closed_at);
end;
$$;

-- ------------------------------------------------------------
-- 6. Mara's review queue
-- ------------------------------------------------------------
create or replace function review_queue_rows()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'businesses', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'org_id', g.id, 'name', g.name, 'slug', g.slug, 'profile', g.profile,
                       'blocks_30', x.blocks, 'refused_7', x.refused)
                   order by x.blocks desc, x.refused desc, g.name)
              from (select o.id,
                           (select count(*) from blocked_customers b
                             where b.org_id = o.id and b.created_at > now() - interval '30 days') as blocks,
                           (select count(*) from orders r
                             where r.org_id = o.id and r.status = 'refused'
                               and r.updated_at > now() - interval '7 days') as refused
                      from orgs o) x
              join orgs g on g.id = x.id
             where x.blocks >= 3 or x.refused >= 5), '[]'::jsonb),
        'couriers', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'user_id', c.user_id, 'name', coalesce(p.full_name, ''),
                       'phone', coalesce(c.phone, p.phone), 'currency', m.currency,
                       'held', courier_cash_carried(c.user_id, m.currency),
                       'cap', courier_cash_cap_for(m.currency))
                   order by courier_cash_carried(c.user_id, m.currency) desc)
              from couriers c
              join profiles p on p.id = c.user_id
              cross join (values ('XOF'), ('XAF')) as m(currency)
             where courier_cash_cap_for(m.currency) is not null
               and courier_cash_carried(c.user_id, m.currency) > courier_cash_cap_for(m.currency)), '[]'::jsonb),
        'tills', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'id', t.id, 'org_id', t.org_id, 'name', g.name, 'day', t.day,
                       'gap', t.gap, 'expected', t.expected, 'counted', t.counted,
                       'currency', t.currency, 'closer', t.closer_name)
                   order by abs(t.gap) desc)
              from till_closings t join orgs g on g.id = t.org_id
             where t.closed_at > now() - interval '7 days'
               and upper(t.currency) in ('XOF', 'XAF')
               and spot_setting('till_gap_review', 5000) > 0
               and abs(t.gap) >= spot_setting('till_gap_review', 5000)), '[]'::jsonb));
$$;

-- The one counter of « À faire » (null for anybody but the platform).
create or replace function review_todo_counts()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare v jsonb;
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return null;
    end if;
    v := review_queue_rows();
    return jsonb_build_object('review',
        jsonb_array_length(v -> 'businesses') + jsonb_array_length(v -> 'couriers')
        + jsonb_array_length(v -> 'tills'));
end;
$$;

create or replace function platform_review_queue()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Réservé à la plateforme';
    end if;
    return review_queue_rows() || jsonb_build_object(
        'reports_open', (select count(*) from problem_reports where status = 'open'),
        'couriers_pending', (select count(*) from couriers where status = 'pending'),
        'cash_cap', spot_setting('courier_cash_cap', 50000),
        'till_gap_review', spot_setting('till_gap_review', 5000));
end;
$$;

-- ------------------------------------------------------------
-- Réglages: 144's platform_set_setting, with the four new ranges
-- ------------------------------------------------------------
create or replace function platform_set_setting(p_key text, p_value jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_before jsonb;
    v_type   text;
    v_num    numeric;
begin
    perform platform_only();
    select value into v_before from platform_settings where key = p_key for update;
    if not found or platform_setting_internal(p_key) then
        raise exception 'Réglage inconnu : %', coalesce(p_key, '');
    end if;
    v_type := jsonb_typeof(v_before);
    -- A whole object is a page's, never a single setting.
    if v_type = 'object' then
        raise exception 'Réglage inconnu : %', p_key;
    end if;
    if p_value is null or jsonb_typeof(p_value) <> v_type then
        raise exception '%', case v_type
            when 'number'  then 'Ce réglage attend un nombre.'
            when 'boolean' then 'Ce réglage attend oui ou non.'
            when 'string'  then 'Ce réglage attend un texte.'
            when 'array'   then 'Ce réglage attend une liste.'
            else 'Ce réglage n''accepte pas cette valeur.' end;
    end if;
    if v_type = 'number' then
        v_num := (p_value #>> '{}')::numeric;
        if v_num < 0 then
            raise exception 'Un nombre positif, s''il vous plaît.';
        end if;
        if v_num > 1000000000 then
            raise exception 'Un nombre d''un milliard au plus.';
        end if;
        if p_key like '%\_pct' and v_num > 100 then
            raise exception 'Un pourcentage ne dépasse pas 100.';
        end if;
        -- A whole number, but for the five every reader takes as numeric
        -- (061/069/081/085's delivery fee and reach, 076's commission)
        -- and, since 139, the euro and dollar prices (read as numeric by
        -- spot_zone_price and pro_zone_price), to the cent.
        if v_num <> trunc(v_num)
           and p_key not in ('delivery_base', 'delivery_per_km', 'delivery_max_km',
                             'delivery_included_km', 'wave_commission_pct',
                             'spot_price_article_7_eur', 'spot_price_shop_7_eur',
                             'spot_price_article_7_usd', 'spot_price_shop_7_usd',
                             'pro_price_month_eur', 'pro_price_year_eur',
                             'pro_price_month_usd', 'pro_price_year_usd') then
            raise exception 'Un nombre entier, s''il vous plaît.';
        end if;
        if p_key like '%\_eur' or p_key like '%\_usd' then
            if v_num * 100 <> trunc(v_num * 100) then
                raise exception 'Deux chiffres après la virgule au plus, s''il vous plaît.';
            end if;
        end if;
        -- 139: Mara's prices the card charges — never below what Stripe
        -- takes (about 0,50 $: 300 FCFA, 0,50 € or $0.50).
        if p_key in ('spot_price_article_7', 'spot_price_shop_7', 'pro_price_month', 'pro_price_year')
           and v_num < 300 then
            raise exception 'Au moins 300 FCFA : le paiement par carte (Stripe) ne prend pas moins.';
        end if;
        if (p_key like 'spot\_price\_%\_7\_eur' or p_key like 'spot\_price\_%\_7\_usd'
            or p_key like 'pro\_price\_%\_eur' or p_key like 'pro\_price\_%\_usd')
           and v_num < 0.5 then
            raise exception 'Au moins 0,50 : le paiement par carte (Stripe) ne prend pas moins.';
        end if;
        -- 121: the card's rate divides a price — never zero.
        if p_key = 'stripe_xof_per_usd' and v_num <= 0 then
            raise exception 'Un nombre entier plus grand que zéro, s''il vous plaît.';
        end if;
        -- 122: the couriers' radius, 1 to 100 km.
        if p_key = 'courier_radius_km' and (v_num < 1 or v_num > 100) then
            raise exception 'Un nombre de kilomètres de 1 à 100, s''il vous plaît.';
        end if;
        -- 144: the spots' area, 5 to 200 km.
        if p_key = 'spot_area_km' and (v_num < 5 or v_num > 200) then
            raise exception 'Un nombre de kilomètres de 5 à 200, s''il vous plaît.';
        end if;
        -- 146: the order limits, 0 (off) to 50.
        if p_key in ('order_open_max_per_shop', 'order_first_open_max') and v_num > 50 then
            raise exception 'De 0 (sans limite) à 50 commandes, s''il vous plaît.';
        end if;
        -- 146: the courier's cash cap and the till gap Mara looks at, 0
        -- (none) or at least 1 000 FCFA, 10 000 000 at most.
        if p_key in ('courier_cash_cap', 'till_gap_review')
           and v_num <> 0 and (v_num < 1000 or v_num > 10000000) then
            raise exception 'De 1 000 à 10 000 000 FCFA, ou 0 pour aucun, s''il vous plaît.';
        end if;
        -- Two switches kept as numbers (093, 097): read as « = 1 ».
        if p_key in ('vitrine_free_basics', 'path_gates_open') and v_num not in (0, 1) then
            raise exception 'Ce réglage vaut 0 (non) ou 1 (oui).';
        end if;
        -- Written the way an integer reader reads it: « 12 », never « 12.0 ».
        p_value := case when v_num = trunc(v_num) then to_jsonb(v_num::bigint) else to_jsonb(v_num) end;
    elsif v_type = 'string' then
        if length(p_value #>> '{}') > 200 then
            raise exception 'Un texte de 200 caractères au plus.';
        end if;
        -- 122: the App Store's address is an address, or nothing.
        if p_key = 'app_store_url' then
            p_value := to_jsonb(btrim(p_value #>> '{}'));
            if p_value #>> '{}' <> '' and p_value #>> '{}' !~ '^https://[^\s]+$' then
                raise exception 'Une adresse qui commence par https://, ou rien.';
            end if;
        end if;
    elsif v_type = 'array' then
        if exists (select 1 from jsonb_array_elements(p_value) e
                    where jsonb_typeof(e) <> 'string') then
            raise exception 'Ce réglage attend une liste de mots.';
        end if;
    end if;
    if p_value = v_before then
        return null;  -- nothing changed, nothing to write in the journal
    end if;

    update platform_settings set value = p_value, updated_at = now() where key = p_key;
    return platform_log_action(
        null, 'setting',
        'Réglage ' || p_key || ' : ' || v_before::text || ' → ' || p_value::text,
        jsonb_build_object('key', p_key, 'value', v_before),
        jsonb_build_object('key', p_key, 'value', p_value),
        'platform_undo_setting',
        jsonb_build_object('key', p_key, 'before', v_before, 'after', p_value));
end;
$$;

-- ------------------------------------------------------------
-- Grants
-- ------------------------------------------------------------
revoke execute on function block_customer(uuid, text)                         from public;
revoke execute on function unblock_customer(uuid, uuid)                       from public;
revoke execute on function shopper_open_orders(uuid, uuid)                    from public;
revoke execute on function trg_orders_guard()                                 from public;
revoke execute on function courier_cash_cap_for(text)                         from public;
revoke execute on function courier_cash_carried(uuid, text)                   from public;
revoke execute on function take_delivery(uuid)                                from public;
revoke execute on function courier_cash_status()                              from public;
revoke execute on function record_return(uuid, text, uuid)                    from public;
revoke execute on function close_till(uuid, date, integer, numeric, numeric, text) from public;
revoke execute on function review_queue_rows()                                from public;
revoke execute on function review_todo_counts()                               from public;
revoke execute on function platform_review_queue()                            from public;
revoke execute on function platform_set_setting(text, jsonb)                  from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function block_customer(uuid, text)                         from anon;
        revoke execute on function unblock_customer(uuid, uuid)                       from anon;
        revoke execute on function shopper_open_orders(uuid, uuid)                    from anon;
        revoke execute on function trg_orders_guard()                                 from anon;
        revoke execute on function courier_cash_cap_for(text)                         from anon;
        revoke execute on function courier_cash_carried(uuid, text)                   from anon;
        revoke execute on function take_delivery(uuid)                                from anon;
        revoke execute on function courier_cash_status()                              from anon;
        revoke execute on function record_return(uuid, text, uuid)                    from anon;
        revoke execute on function close_till(uuid, date, integer, numeric, numeric, text) from anon;
        revoke execute on function review_queue_rows()                                from anon;
        revoke execute on function review_todo_counts()                               from anon;
        revoke execute on function platform_review_queue()                            from anon;
        revoke execute on function platform_set_setting(text, jsonb)                  from anon;
        revoke all on table blocked_customers from anon;
        revoke all on table till_closings     from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: the trigger and the helpers run as their owner.
        revoke execute on function shopper_open_orders(uuid, uuid)                    from authenticated;
        revoke execute on function trg_orders_guard()                                 from authenticated;
        revoke execute on function courier_cash_cap_for(text)                         from authenticated;
        revoke execute on function courier_cash_carried(uuid, text)                   from authenticated;
        revoke execute on function review_queue_rows()                                from authenticated;
        -- The business's doors (invoker: RLS decides), the courier's, the
        -- till's, the platform's (each checks its caller).
        grant execute on function block_customer(uuid, text)                         to authenticated;
        grant execute on function unblock_customer(uuid, uuid)                       to authenticated;
        grant execute on function take_delivery(uuid)                                to authenticated;
        grant execute on function courier_cash_status()                              to authenticated;
        grant execute on function record_return(uuid, text, uuid)                    to authenticated;
        grant execute on function close_till(uuid, date, integer, numeric, numeric, text) to authenticated;
        grant execute on function review_todo_counts()                               to authenticated;
        grant execute on function platform_review_queue()                            to authenticated;
        grant execute on function platform_set_setting(text, jsonb)                  to authenticated;
        -- The tables: what the policies allow, no more.
        grant select, insert, delete on table blocked_customers to authenticated;
        revoke update, truncate on table blocked_customers from authenticated;
        grant select on table till_closings to authenticated;
        revoke insert, update, delete, truncate on table till_closings from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant select on table blocked_customers to service_role;
        grant select on table till_closings     to service_role;
    end if;
end $$;

notify pgrst, 'reload schema';
