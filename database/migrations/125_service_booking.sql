-- ============================================================
-- 125_service_booking.sql — a service is booked, not basketed.
--
-- The owner: « A service should be booked and not like a simple item. »
-- Until now (098) a service went into the basket like a tin of tomatoes,
-- and a basket of services alone became a booking whose day and hour were
-- free words in the note. Now « Réserver » asks for a day and a time, and
-- the business confirms, proposes another time or refuses. The same for a
-- shop's, a farm's and an association's services.
--
-- A booking IS an order (055) — one line, a service — so everything that
-- already follows an order follows a booking: the bell, Commandes and « Mes
-- commandes », the timeline (073), the payment, « Terminée », the cauris
-- (084), the vitrine's switches (110), the showcase refusal (094). What
-- this adds:
--
--   1. orders.booked_for (the slot asked for, then the slot agreed) and
--      orders.proposed_for (the business's other time, while the customer
--      has not answered). The customer's words stay in orders.note (now
--      optional). The booking's state is not a third column: it is the
--      order's status, which every trigger already reads —
--        requested: pending, nothing proposed;  proposed: pending with a
--        proposed_for;  confirmed: accepted (then ready, picked_up =
--        « Terminée »);  declined: refused;  cancelled: cancelled.
--      A second column would have to be kept in step with the status by
--      every path that moves it (decide_order, cancel_order, 101's stock,
--      073's events) — and would drift the first time one forgot.
--   2. The slot rules, one function for placing and for proposing
--      (booking_check_slot): given, in the future, within the next 14
--      days, on :00 or :30, and inside the vitrine's opening hours that
--      day — the hours the street is shown (093's schedule, as storefront()
--      hands it). A vitrine with no hours set: every day, 08:00–20:00. A
--      close before the open is a night shop (093): its hours after
--      midnight belong to the day before.
--      The clock is Ouagadougou's (Africa/Ouagadougou, UTC+0 all year):
--      no business keeps a time zone, and every date the database already
--      reads (093's « Ouvert maintenant », 101's pre-orders, 084's cauris
--      day) is read there. booking_tz() names it once.
--   3. place_order (109's, the latest; same nine arguments — a tenth,
--      defaulted, would make every older call ambiguous wherever an earlier
--      migration is run again, as 115 says): a line that is a service
--      carries its slot (« booked_for ») and, for a service by the person
--      or by the hour, how many (1 to 20; any other service is 1). A
--      service is booked alone: with goods, or with another service, it is
--      refused in French. An order of goods is exactly what 109 made it.
--   4. book_service(slug, product, booked_for, quantity, note, phone): the
--      app's door for « Réserver » — the line written for place_order, and
--      place_order's every rule. Its absence (PGRST202) tells an app on an
--      older database that booking is not there yet.
--   5. The business answers (SECURITY DEFINER under can_write_org(), as
--      decide_order and refuse_order are): « Confirmer » is decide_order
--      'accepted', « Refuser » is refuse_order (115) — both kept, their
--      bells now saying « Votre rendez-vous … est confirmé : mardi 14
--      oct., 10:00 » (booking_confirmed) and booking_declined; « Proposer
--      une autre heure » is propose_booking_time(order, at), the same slot
--      rules, bell booking_proposed. Confirming while a proposal waits for
--      the customer is refused; so is confirming a time already past.
--   6. The customer answers: accept_booking_time(order) — the proposal
--      becomes the slot and the booking is confirmed, the business hears
--      booking_accepted; or cancel_order (099), unchanged.
--   7. The bell's switches (115): booking_* rows answer to the customer's
--      « Mes réservations » or the business's « Commandes de la vitrine ».
--   8. The lists: my_orders() and shop_orders() keep their columns (098's
--      would refuse to be re-run over a new return type); a booking's line
--      carries booked_for and proposed_for. The red number (home_counts,
--      shop_pending_orders) no longer counts a booking waiting for the
--      customer's answer: the business has answered.
--
-- LATER, not here: times already taken, a calendar, the reminder the day
-- before.
--
-- Re-runnable (the bundle runs twice): columns if not exists, the check
-- dropped and recreated, functions replaced with their own signatures.
-- ============================================================

do $$
begin
    if to_regprocedure('public.refuse_order(uuid, text)') is null
       or to_regprocedure('public.order_phone_required()') is null
       or to_regprocedure('public.vitrine_plus_on(uuid)') is null then
        raise exception '125 needs 109 (order_phone_required), 110 (vitrine_plus_on) and 115 (refuse_order) applied first';
    end if;
end $$;

-- ------------------------------------------------------------
-- 1. The slot, on the order
-- ------------------------------------------------------------
alter table orders add column if not exists booked_for timestamptz;
alter table orders add column if not exists proposed_for timestamptz;

comment on column orders.booked_for is
    'A booking''s slot (125): the time asked for, then the time agreed. Null on an order of goods.';
comment on column orders.proposed_for is
    'The business''s other time for a booking (125), until the customer accepts it (it becomes booked_for) or the booking ends.';

alter table orders drop constraint if exists orders_proposal_is_booking;
alter table orders add constraint orders_proposal_is_booking
    check (proposed_for is null or booked_for is not null);

-- ------------------------------------------------------------
-- 2. The clock and the hours
-- ------------------------------------------------------------
-- Every booking's time is read in Ouagadougou (UTC+0, no summer time): no
-- business keeps a time zone, and 093's « Ouvert maintenant » reads there.
create or replace function booking_tz()
returns text
language sql
immutable
set search_path = public
as $$
    select 'Africa/Ouagadougou'::text;
$$;

-- The hours a booking is held to: the vitrine's schedule as the street is
-- shown it (storefront(): with Vitrine Plus, or the free basics), else —
-- no hours set — every day, 08:00–20:00.
create or replace function booking_schedule(p_org uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((
        select s
          from orgs o
          cross join lateral (select o.storefront_style -> 'schedule' as s) x
         where o.id = p_org
           and (vitrine_plus_on(o.id) or cauris_param('vitrine_free_basics', 1) = 1)
           and jsonb_typeof(s) = 'object'
           and jsonb_typeof(s -> 'days') = 'array'
           and jsonb_array_length(s -> 'days') > 0
           and coalesce(s ->> 'open', '')  ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
           and coalesce(s ->> 'close', '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
           and s ->> 'open' <> s ->> 'close'),
        '{"days": [1, 2, 3, 4, 5, 6, 7], "open": "08:00", "close": "20:00"}'::jsonb);
$$;

-- Open at that local moment, by the schedule (093's vitrine_open_now, for
-- any moment): a close before the open runs past midnight, and its hours
-- after midnight belong to the day before.
create or replace function vitrine_open_at(p_schedule jsonb, p_local timestamp)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
    v_day   int := extract(isodow from p_local)::int;
    v_prev  int := case when extract(isodow from p_local)::int = 1 then 7
                        else extract(isodow from p_local)::int - 1 end;
    v_t     time := p_local::time;
    v_open  time;
    v_close time;
begin
    v_open  := (p_schedule ->> 'open')::time;
    v_close := (p_schedule ->> 'close')::time;
    if v_close > v_open then
        return (p_schedule -> 'days') @> to_jsonb(v_day)
           and v_t >= v_open and v_t < v_close;
    end if;
    return ((p_schedule -> 'days') @> to_jsonb(v_day) and v_t >= v_open)
        or ((p_schedule -> 'days') @> to_jsonb(v_prev) and v_t < v_close);
exception when others then
    return false;
end;
$$;

-- « mardi 14 oct., 10:00 »: a slot in the bell's French, Ouagadougou time.
create or replace function booking_when_fr(p_at timestamptz)
returns text
language sql
stable
set search_path = public
as $$
    select (array['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'])
               [extract(isodow from l)::int]
           || ' ' || extract(day from l)::int || ' '
           || (array['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
                     'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'])[extract(month from l)::int]
           || ', ' || to_char(l, 'HH24:MI')
      from (select p_at at time zone booking_tz() as l) x;
$$;

-- The slot rules, for placing and for proposing alike. Raises in French.
create or replace function booking_check_slot(p_org uuid, p_at timestamptz)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_local timestamp;
    v_sched jsonb;
begin
    if p_at is null then
        raise exception 'Choisissez le jour et l''heure du rendez-vous';
    end if;
    if p_at <= now() then
        raise exception 'Cette heure est déjà passée : choisissez-en une autre';
    end if;
    if p_at > now() + interval '14 days' then
        raise exception 'Un rendez-vous se prend dans les 14 prochains jours';
    end if;
    v_local := p_at at time zone booking_tz();
    if date_trunc('minute', v_local) <> v_local
       or extract(minute from v_local)::int not in (0, 30) then
        raise exception 'Un rendez-vous commence à l''heure pile ou à la demie';
    end if;
    v_sched := booking_schedule(p_org);
    if not vitrine_open_at(v_sched, v_local) then
        if not exists (select 1 from generate_series(0, 47) g
                        where vitrine_open_at(v_sched, v_local::date + g * interval '30 minutes')) then
            raise exception 'Fermé ce jour-là : choisissez un autre jour';
        end if;
        raise exception 'Fermé à cette heure : choisissez une heure d''ouverture';
    end if;
end;
$$;

-- ------------------------------------------------------------
-- 3. Placing: 109's order, a service booked alone with its slot
-- ------------------------------------------------------------
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
    -- 109: the switch, and the number it asks for.
    v_gate     boolean := order_phone_required();
    v_proved   text;
    -- 125: a booking's one line, its slot, its unit.
    v_svc      int;
    v_booked   timestamptz;
    v_unit     text;
begin
    if auth.uid() is null then
        raise exception 'Sign in to order';
    end if;
    -- 109: a proved number first, when the platform asks for one — before
    -- anything is read or written, an order or a booking alike.
    if v_gate then
        v_proved := my_verified_phone();
        if v_proved is null then
            raise exception 'Vérifiez d''abord votre numéro WhatsApp';
        end if;
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

    -- 125: a service is booked alone — never beside goods, never two at
    -- once. Said before the delivery rules, so the customer hears the
    -- reason that applies.
    select count(*) into v_svc
      from jsonb_array_elements(p_lines) l
      join products p
        on p.id = nullif(l ->> 'product_id', '')::uuid and p.org_id = v_org
     where p.is_service;
    v_services := v_svc > 0;
    if v_services then
        if jsonb_array_length(p_lines) > v_svc then
            raise exception 'Un service se réserve seul : il ne se mélange pas aux articles d''un panier';
        end if;
        if v_svc > 1 then
            raise exception 'Une réservation porte sur un seul service';
        end if;
        if p_fulfilment <> 'pickup' then
            raise exception 'Un service se réserve sur rendez-vous : pas de livraison';
        end if;
        v_line := p_lines -> 0;
        begin
            v_booked := nullif(btrim(coalesce(v_line ->> 'booked_for', '')), '')::timestamptz;
        exception when others then
            raise exception 'L''heure du rendez-vous est illisible';
        end;
        perform booking_check_slot(v_org, v_booked);
        -- How many: asked only of a service by the person or by the hour.
        select lower(btrim(coalesce(p.unit, ''))) into v_unit
          from products p
         where p.id = nullif(v_line ->> 'product_id', '')::uuid and p.org_id = v_org;
        v_qty := (v_line ->> 'quantity')::numeric;
        if v_unit in ('personne', 'heure') then
            if v_qty is null or v_qty <> trunc(v_qty) or v_qty < 1 or v_qty > 20 then
                raise exception '%', case when v_unit = 'personne'
                                          then 'De 1 à 20 personnes'
                                          else 'De 1 à 20 heures' end;
            end if;
        elsif v_qty is distinct from 1 then
            raise exception 'Ce service se réserve une fois : pas de quantité à choisir';
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
                        drop_lat, drop_lng, delivery_fee, booked_for)
    values (v_org, auth.uid(), v_name,
            -- 109: with the switch on, the number the shop calls is the
            -- one WhatsApp proved; off, as before.
            case when v_gate then v_proved
                 else coalesce(nullif(btrim(coalesce(p_phone, '')), ''), v_phone) end,
            p_fulfilment,
            v_note,
            v_address,
            coalesce(v_currency, 'XOF'),
            p_payment,
            case when p_fulfilment = 'delivery' then p_drop_lat end,
            case when p_fulfilment = 'delivery' then p_drop_lng end,
            v_fee,
            v_booked)
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
            -- 125: a booking says its slot, as Commandes shows it.
            case when v_services
                 then 'Rendez-vous demandé par ' || v_name || ' — ' || booking_when_fr(v_booked)
                      || ' : '
                 else 'Nouvelle commande de ' || v_name || ' : ' end
            || to_char(v_total, 'FM999G999G999D00') || ' '
            || coalesce(v_currency, 'XOF')
            || case when p_payment = 'wave' then ' (Wave)' else '' end
            || case when v_fee is not null
                    then ' + livraison ' || to_char(v_fee, 'FM999G999G999') else '' end,
            jsonb_build_object('to', 'shop', 'order_id', v_id, 'booking', v_services,
                               'name', v_name, 'total', v_total,
                               'currency', coalesce(v_currency, 'XOF'),
                               'wave', p_payment = 'wave', 'fee', v_fee)
            || case when v_services then jsonb_build_object('at', v_booked)
                    else '{}'::jsonb end);
    exception when others then
        null;
    end;

    return v_id;
end;
$$;

-- « Réserver »: the app's door. One service, its slot, how many, the
-- customer's words — written as place_order's line and held to its rules.
create or replace function book_service(
    p_slug       text,
    p_product_id uuid,
    p_booked_for timestamptz,
    p_quantity   integer default 1,
    p_note       text default null,
    p_phone      text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
    if p_product_id is null or not exists (
        select 1 from products p
         where p.id = p_product_id and p.is_service
           and p.org_id = storefront_open(p_slug)) then
        raise exception 'Ce service n''est pas sur cette vitrine';
    end if;
    return place_order(
        p_slug,
        jsonb_build_array(jsonb_build_object(
            'product_id', p_product_id,
            'quantity',   coalesce(p_quantity, 1),
            'booked_for', p_booked_for)),
        'pickup', p_note, null, p_phone, 'cash');
end;
$$;

-- ------------------------------------------------------------
-- 4. The business answers
-- ------------------------------------------------------------
-- 115's decide_order, the same two arguments. A booking (a slot on the
-- order): « Confirmer » is 'accepted' — refused while a proposal waits for
-- the customer, or once the slot has passed — and its bell, like a
-- refusal's, says the day and the time. Everything else as in 115.
create or replace function decide_order(p_order_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_order   orders%rowtype;
    v_ok      boolean;
    v_booking boolean;
    v_reason  text;
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
    -- 125: a slot is confirmed only as asked, and only while it is ahead.
    if p_status = 'accepted' and v_order.booked_for is not null then
        if v_order.proposed_for is not null then
            raise exception 'Une autre heure est proposée : attendez la réponse du client';
        end if;
        if v_order.booked_for <= now() then
            raise exception 'Cette heure est passée : proposez-en une autre';
        end if;
    end if;
    -- 115: the shop's words, when refuse_order() wrote them just before.
    v_reason := case when p_status = 'refused' then nullif(btrim(coalesce(v_order.refusal_reason, '')), '') end;
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

    v_booking := v_order.fulfilment = 'pickup'
        and exists (select 1 from order_lines l where l.order_id = p_order_id)
        and not exists (select 1 from order_lines l
                         where l.order_id = p_order_id and not l.is_service);

    begin
        if v_order.booked_for is not null and p_status in ('accepted', 'refused') then
            -- 125: the booking's answer, with its day and its time.
            insert into notifications (recipient_id, org_id, kind, message, params)
            select v_order.customer_id, v_order.org_id,
                   case when p_status = 'accepted' then 'booking_confirmed' else 'booking_declined' end,
                   case when p_status = 'accepted'
                        then 'Votre rendez-vous chez ' || o.name || ' est confirmé : '
                             || booking_when_fr(v_order.booked_for)
                        else 'Votre demande de rendez-vous chez ' || o.name || ' est refusée' end
                   || case when v_reason is null then '' else ' — ' || v_reason end,
                   jsonb_build_object('to', 'customer', 'order_id', v_order.id,
                                      'booking', true, 'shop', o.name,
                                      'status', p_status, 'at', v_order.booked_for)
                   || case when v_reason is null then '{}'::jsonb
                           else jsonb_build_object('reason', v_reason) end
              from orgs o where o.id = v_order.org_id;
            return;
        end if;
        insert into notifications (recipient_id, org_id, kind, message, params)
        select v_order.customer_id, v_order.org_id, 'order_' || p_status,
               case when v_booking then 'Votre réservation chez '
                    else 'Votre commande chez ' end
               || o.name || ' : '
               || case p_status
                    when 'accepted'  then 'acceptée'
                    when 'ready'     then 'prête'
                    when 'picked_up' then case when v_booking then 'terminée'
                                               else 'récupérée' end
                    when 'delivered' then 'livrée'
                    when 'refused'   then 'refusée'
                    else 'annulée' end
               || case when v_reason is null then '' else ' — ' || v_reason end,
               jsonb_build_object('to', 'customer', 'order_id', v_order.id,
                                  'booking', v_booking, 'shop', o.name,
                                  'status', p_status)
               || case when v_reason is null then '{}'::jsonb
                       else jsonb_build_object('reason', v_reason) end
          from orgs o where o.id = v_order.org_id;
        -- A courier who already took the job hears about a cancellation.
        if p_status = 'cancelled' and v_order.courier_id is not null then
            insert into notifications (recipient_id, org_id, kind, message, params)
            values (v_order.courier_id, v_order.org_id, 'delivery_cancelled',
                    'La livraison pour ' || v_order.customer_name
                    || ' a été annulée par la boutique',
                    jsonb_build_object('to', 'courier', 'order_id', v_order.id,
                                       'name', v_order.customer_name));
        end if;
    exception when others then
        null;
    end;
end;
$$;

-- « Proposer une autre heure »: the same slot rules as asking; the booking
-- waits for the customer, who hears it.
create or replace function propose_booking_time(p_order_id uuid, p_at timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_order orders%rowtype;
begin
    select * into v_order from orders where id = p_order_id for update;
    if not found then
        raise exception 'No such order';
    end if;
    if not can_write_org(v_order.org_id) then
        raise exception 'Only the shop can answer its orders';
    end if;
    if v_order.booked_for is null then
        raise exception 'Seul un rendez-vous peut changer d''heure';
    end if;
    if v_order.status <> 'pending' then
        raise exception 'Ce rendez-vous a déjà une réponse';
    end if;
    perform booking_check_slot(v_order.org_id, p_at);
    if p_at = v_order.booked_for then
        raise exception 'C''est l''heure demandée : confirmez-la plutôt';
    end if;
    update orders
       set proposed_for = p_at, updated_at = now()
     where id = p_order_id;
    begin
        insert into notifications (recipient_id, org_id, kind, message, params)
        select v_order.customer_id, v_order.org_id, 'booking_proposed',
               o.name || ' propose une autre heure pour votre rendez-vous : '
               || booking_when_fr(p_at) || '. Acceptez-la dans Mes commandes.',
               jsonb_build_object('to', 'customer', 'order_id', v_order.id,
                                  'booking', true, 'shop', o.name,
                                  'at', p_at, 'asked', v_order.booked_for)
          from orgs o where o.id = v_order.org_id;
    exception when others then
        null;
    end;
end;
$$;

-- ------------------------------------------------------------
-- 5. The customer answers a proposal
-- ------------------------------------------------------------
create or replace function accept_booking_time(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_order orders%rowtype;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    select * into v_order from orders
     where id = p_order_id and customer_id = auth.uid()
       for update;
    if not found then
        raise exception 'Rendez-vous introuvable';
    end if;
    if v_order.status <> 'pending' or v_order.proposed_for is null then
        raise exception 'Aucune autre heure n''est proposée pour ce rendez-vous';
    end if;
    if v_order.proposed_for <= now() then
        raise exception 'Cette heure est passée : demandez-en une autre';
    end if;
    update orders
       set booked_for   = v_order.proposed_for,
           proposed_for = null,
           status       = 'accepted',
           updated_at   = now(),
           decided_at   = coalesce(decided_at, now())
     where id = p_order_id;
    begin
        perform notify_org_admins(v_order.org_id, 'booking_accepted',
            v_order.customer_name || ' accepte le rendez-vous : '
            || booking_when_fr(v_order.proposed_for),
            jsonb_build_object('to', 'shop', 'order_id', v_order.id, 'booking', true,
                               'name', v_order.customer_name, 'at', v_order.proposed_for));
    exception when others then
        null;
    end;
end;
$$;

-- ------------------------------------------------------------
-- 6. The bell's switches (115): a booking's rows, under their own
-- ------------------------------------------------------------
create or replace function notification_type_of(p_kind text, p_params jsonb)
returns text
language sql
immutable
set search_path = public
as $$
    select case
        when p_kind = 'vitrine_news' then 'vitrine_news'
        when p_kind = 'report_handled' then 'reports'
        when p_kind = 'delivery_available' then 'delivery_nearby'
        when p_kind in ('delivery_cancelled', 'courier_shop_added') then 'delivery_updates'
        when p_kind = 'courier_cash_received' then 'courier_cash'
        when p_kind = 'courier_idle' then 'courier_idle'
        -- 125: confirmed, proposed, declined (the customer's); accepted
        -- (the business's).
        when p_kind like 'booking\_%'
            then case when p_params ->> 'to' = 'shop' then 'shop_orders' else 'bookings' end
        when p_params ->> 'to' = 'customer'
             and (p_kind like 'order\_%' or p_kind like 'delivery\_%')
            then case when p_params ->> 'booking' = 'true' then 'bookings'
                      else 'order_updates' end
        when p_params ->> 'to' = 'shop'
             and (p_kind = 'new_order' or p_kind like 'order\_%' or p_kind like 'delivery\_%')
            then 'shop_orders'
        when p_kind = 'low_stock' then 'shop_stock'
        when p_kind = 'member_joined' then 'shop_team'
        when p_kind in ('debt_settled', 'tontine_ready') then 'shop_money'
        when p_kind = 'cauris_board' then 'shop_league'
    end;
$$;

-- ------------------------------------------------------------
-- 7. The lists (098's columns; a booking's line says its slot)
-- ------------------------------------------------------------
create or replace function my_orders()
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
                       'quantity', l.quantity, 'is_service', l.is_service)
                       || case when o.booked_for is not null
                               then jsonb_build_object('booked_for', o.booked_for,
                                                       'proposed_for', o.proposed_for)
                               else '{}'::jsonb end
                       order by l.name), '[]'::jsonb)
              from order_lines l where l.order_id = o.id)
      from orders o
      join orgs g on g.id = o.org_id
     where o.customer_id = auth.uid()
     order by (o.status in ('pending', 'accepted', 'ready', 'in_transit')) desc,
              o.created_at desc;
$$;

create or replace function shop_orders(p_org_id uuid)
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
                       'quantity', l.quantity, 'is_service', l.is_service)
                       || case when o.booked_for is not null
                               then jsonb_build_object('booked_for', o.booked_for,
                                                       'proposed_for', o.proposed_for)
                               else '{}'::jsonb end
                       order by l.name), '[]'::jsonb)
              from order_lines l where l.order_id = o.id)
      from orders o
     where o.org_id = p_org_id
     order by (o.status in ('pending', 'accepted', 'ready', 'in_transit')) desc,
              o.created_at desc;
end;
$$;

-- 055's badge: what waits for the business's answer — not a booking whose
-- other time waits for the customer's.
create or replace function shop_pending_orders(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case when is_org_member(p_org_id)
                then (select count(*)::int from orders
                       where org_id = p_org_id and status = 'pending'
                         and proposed_for is null)
                else 0 end;
$$;

-- 115's bar, the same numbers, a booking waiting for the customer's answer
-- left out of « to answer ».
create or replace function home_counts(p_org uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
    v_kind      text;
    v_orders    int := 0;
    v_bookings  int := 0;
    v_articles  int := 0;
    v_invoices  int := 0;
    v_credit    int := 0;
    v_invites   int := 0;
    v_supplies  int := 0;
    v_livestock int := 0;
begin
    if p_org is null or not is_org_member(p_org) then
        return null;
    end if;
    select profile into v_kind from orgs where id = p_org;

    -- Orders not answered yet; a basket of services only is a booking.
    select count(*) filter (where not x.booking), count(*) filter (where x.booking)
      into v_orders, v_bookings
      from (select exists (select 1 from order_lines l where l.order_id = o.id)
                   and not exists (select 1 from order_lines l
                                    where l.order_id = o.id and not l.is_service) as booking
              from orders o
             where o.org_id = p_org and o.status = 'pending'
               and o.proposed_for is null) x;

    if v_kind in ('retail', 'farm') then
        select count(*) into v_articles
          from products p
         where p.org_id = p_org and p.is_active and not p.is_service
           and (p.quantity <= 0 or (p.low_stock_at is not null and p.quantity <= p.low_stock_at));
    end if;

    select count(*) into v_invoices
      from invoices i
     where i.org_id = p_org and i.cancelled_at is null
       and i.due_on is not null and i.due_on < current_date
       and i.total > coalesce((select sum(ip.amount) from invoice_payments ip
                                where ip.invoice_id = i.id), 0);

    -- A due date on a credit is 117's; before it, nothing is « overdue ».
    if exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'debts'
                  and column_name = 'due_on') then
        execute 'select count(*) from debts d
                  where d.org_id = $1 and d.due_on < current_date
                    and d.amount > coalesce((select sum(dp.amount) from debt_payments dp
                                              where dp.debt_id = d.id), 0)'
           into v_credit using p_org;
    end if;

    select count(*) into v_invites
      from pending_invitations pi
     where pi.org_id = p_org and pi.claimed_at is null and pi.expires_at > now();

    if v_kind = 'farm' then
        select count(*) into v_supplies from stock_on_hand(p_org) s where s.below_reorder;
        select count(*) into v_livestock
          from flocks f
         where f.org_id = p_org and f.closed_on is null
           and not exists (select 1 from flock_events e
                            where e.flock_id = f.id and e.occurred_at >= current_date)
           and not exists (select 1 from egg_production g
                            where g.flock_id = f.id and g.produced_on = current_date);
    end if;

    return jsonb_build_object(
        'orders', v_orders, 'bookings', v_bookings, 'articles', v_articles,
        'invoices', v_invoices, 'credit', v_credit, 'invitations', v_invites,
        'supplies', v_supplies, 'livestock', v_livestock);
end;
$$;

-- ------------------------------------------------------------
-- Who may call what (063: a new function is born closed to anon and
-- PUBLIC, open to authenticated — the helpers taken back from it)
-- ------------------------------------------------------------
revoke execute on function booking_tz()                                 from public;
revoke execute on function booking_schedule(uuid)                       from public;
revoke execute on function vitrine_open_at(jsonb, timestamp)            from public;
revoke execute on function booking_when_fr(timestamptz)                 from public;
revoke execute on function booking_check_slot(uuid, timestamptz)        from public;
revoke execute on function book_service(text, uuid, timestamptz, integer, text, text) from public;
revoke execute on function propose_booking_time(uuid, timestamptz)      from public;
revoke execute on function accept_booking_time(uuid)                    from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function booking_tz()                          from anon;
        revoke execute on function booking_schedule(uuid)                from anon;
        revoke execute on function vitrine_open_at(jsonb, timestamp)     from anon;
        revoke execute on function booking_when_fr(timestamptz)          from anon;
        revoke execute on function booking_check_slot(uuid, timestamptz) from anon;
        revoke execute on function book_service(text, uuid, timestamptz, integer, text, text) from anon;
        revoke execute on function propose_booking_time(uuid, timestamptz) from anon;
        revoke execute on function accept_booking_time(uuid)             from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: read inside the doors below, as their owner.
        revoke execute on function booking_tz()                          from authenticated;
        revoke execute on function booking_schedule(uuid)                from authenticated;
        revoke execute on function vitrine_open_at(jsonb, timestamp)     from authenticated;
        revoke execute on function booking_when_fr(timestamptz)          from authenticated;
        revoke execute on function booking_check_slot(uuid, timestamptz) from authenticated;
        -- The doors: a signed-in shopper booking and answering a proposal;
        -- a business member proposing (can_write_org() decides inside).
        grant execute on function book_service(text, uuid, timestamptz, integer, text, text) to authenticated;
        grant execute on function propose_booking_time(uuid, timestamptz) to authenticated;
        grant execute on function accept_booking_time(uuid)             to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
