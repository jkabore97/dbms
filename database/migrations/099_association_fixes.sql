-- ============================================================
-- 099_association_fixes.sql — an association's second business, and a
-- bell that says what it is about.
--
-- The owner, about associations: « Association will also have 2 business
-- locked, only accessible with pro », and « Make sure the notification
-- system covers the user needs. »
--
--   1. A second business needs Mara Pro, whatever the first one is.
--      089's door (trg_second_business_lock) counted owners of shops and
--      farms only, so the owner of a Free association could open a second
--      business freely. Now an owner of any business needs Pro on one they
--      own (Mara's own admins pass, as before). The rule is the person's,
--      so second_business_locked(user) says it once, for the door and for
--      path_locked(org, 'second_business') — which org_progress() hands to
--      the app's « 2e entreprise » row. It answers for the signed-in
--      caller: an employee who owns nothing is not shown a lock the door
--      would not hold (it was, under 089, for every member of a Free
--      shop), and an owner whose other business is Pro is not either.
--      With no caller (a server job) it answers for the business itself:
--      locked unless it is Pro, whatever its profile (nothing asks it so
--      today). Only that step changes for an association:
--      invoices, production and credits still answer false for it, so the
--      triggers of 089 (trg_path_lock), check_unlocks (096) and path_state
--      (097, which returns null for an association) are untouched.
--   2. The bell carries what it is about. notifications.params (jsonb)
--      holds the event's facts — which order, which customer, how much,
--      for whom (to: shop | customer | courier) — so the app opens the
--      right screen on a tap and writes the line in the phone's language.
--      message stays, in French, as before: the push Worker (060) sends it,
--      and it is what older rows and older apps read. Every function that
--      rings the bell is replaced from its latest definition with the same
--      words and its params beside them:
--        030 low stock, a member joined, a credit settled, a tontine ready;
--        098 place_order (a new order or demande), decide_order (each
--        status to the customer, a cancellation to the courier);
--        073 take_delivery, courier_deliver, courier_mark, courier_fail,
--        shop_deliver_self; 057 set_order_paid; 056 decide_courier;
--        071 decide_promotion; 075 register_device; 076 wave_settle;
--        082 stripe_settle; 086 cauris_board_notify, cauris_week_close;
--        096 check_unlocks.
--      The platform's own bells (a business application, a spot to
--      approve, a message the platform typed) stay French text: they are
--      written for Mara's admins, or typed by them.
--   3. A customer who cancels is heard. cancel_order (055) changed the
--      order and told nobody: the shop's or the association's admins now
--      hear « Awa a annulé sa commande » (or « sa demande », a booking).
--   4. Nobody may ring somebody else's bell. 063 granted EXECUTE on every
--      SECURITY DEFINER function to authenticated, notify_org_admins (030)
--      and notify_platform_spot (071) included: any signed-in person could
--      write any text to any business's admins, or to Mara's — and push
--      carries it to their phones. Both are internal: revoked from
--      authenticated (and anon and PUBLIC), like 060's push functions.
--
-- notify_org_admins gains a params argument as a new signature, the 4th
-- argument a jsonb: (org, kind, message, params, except). 030's
-- (org, kind, message, except) stays for any caller not yet passing
-- params, so a three-argument or named call is never ambiguous and the
-- bundle re-runs clean. A 4th POSITIONAL argument must be cast
-- (null::jsonb, '{}'::jsonb or null::uuid): uncast, it matches both.
--
-- Re-runnable (the bundle runs twice): a column if not exists, functions
-- replaced in place, no destructive statement.
-- ============================================================

-- ------------------------------------------------------------
-- 1. A second business: Pro on one already owned
-- ------------------------------------------------------------
-- The person's rule: a platform admin is never held; somebody who owns no
-- live business opens a first one freely (an archived one does not
-- count); an owner needs Pro on a live one they own.
create or replace function second_business_locked(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select not exists (select 1 from profiles
                        where id = p_user_id and is_platform_admin)
       and exists (select 1 from memberships m join orgs o on o.id = m.org_id
                    where m.user_id = p_user_id and m.role = 'owner'
                      and o.archived_at is null)
       and not exists (select 1 from memberships m join orgs o on o.id = m.org_id
                        where m.user_id = p_user_id and m.role = 'owner'
                          and o.archived_at is null
                          and org_plan(m.org_id) = 'pro');
$$;

-- 089's door, for every profile.
create or replace function trg_second_business_lock()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if second_business_locked(new.applicant_id) then
        raise exception '%', path_lock_message('second_business');
    end if;
    return new;
end;
$$;

-- 097's rule. Only the second_business branch moves: it is asked before
-- the profile, and for the caller. Every other step reads as in 097.
create or replace function path_locked(p_org_id uuid, p_step text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select case
        when p_step = 'second_business' then
            case when auth.uid() is null then org_plan(o.id) <> 'pro'
                 else second_business_locked(auth.uid()) end
        when o.profile not in ('retail', 'farm') then false
        when org_plan(o.id) = 'pro' then false
        when cauris_param('path_gates_open', 0) = 1 then false
        when p_step = 'invoices'
            then path_progress(o.id, 'articles') < path_goal(o.id, 'articles')
              or path_progress(o.id, 'photos')   < path_goal(o.id, 'photos')
        when p_step = 'production'
            then exists (select 1 from path_steps s
                          where s.stage = 2 and o.profile = any (s.profiles)
                            and path_progress(o.id, s.key) < path_goal(o.id, s.key))
        when p_step = 'credits'
            then path_progress(o.id, 'three_orders') < path_goal(o.id, 'three_orders')
        else false
    end
    from orgs o where o.id = p_org_id;
$$;

-- ------------------------------------------------------------
-- 2. The bell's facts
-- ------------------------------------------------------------
alter table notifications add column if not exists params jsonb;

comment on column notifications.params is
    'The event''s facts (099): ids, names, amounts and to (shop | customer | '
    'courier), for the app to open the right screen and say the line in the '
    'phone''s language. Null on rows written before 099 and on the '
    'platform''s own messages; message (French) is always there.';

-- The fan-out with the facts: the fourth argument is the params.
create or replace function notify_org_admins(
    p_org_id  uuid,
    p_kind    text,
    p_message text,
    p_params  jsonb,
    p_except  uuid default null
)
returns void
language sql
security definer
set search_path = public
as $$
    insert into notifications (recipient_id, org_id, kind, message, params)
    select distinct m.user_id, p_org_id, p_kind, p_message, p_params
      from memberships m
     where m.org_id = p_org_id
       and m.role in ('owner', 'super_admin', 'admin')
       and (p_except is null or m.user_id <> p_except);
$$;

-- 030: stock crossing below its threshold.
create or replace function trg_notify_low_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.low_stock_at is not null
       and new.is_active
       and new.quantity <= new.low_stock_at
       and old.quantity > new.low_stock_at then
        perform notify_org_admins(new.org_id, 'low_stock',
            format('Stock bas : %s (%s restant)',
                   new.name, trim_scale(new.quantity)),
            jsonb_build_object('to', 'shop', 'product_id', new.id,
                               'name', new.name, 'quantity', trim_scale(new.quantity)));
    end if;
    return new;
exception when others then
    return new;
end;
$$;

-- 030: somebody joined the business.
create or replace function trg_notify_member_joined()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_who text;
    v_org text;
begin
    select coalesce(nullif(btrim(coalesce(full_name, '')), ''), 'Quelqu''un')
      into v_who from profiles where id = new.user_id;
    select name into v_org from orgs where id = new.org_id;
    perform notify_org_admins(new.org_id, 'member_joined',
        format('%s a rejoint %s', coalesce(v_who, 'Quelqu''un'),
               coalesce(v_org, 'votre activité')),
        jsonb_build_object('to', 'shop', 'who', v_who, 'org', v_org),
        p_except => new.user_id);
    return new;
exception when others then
    return new;
end;
$$;

-- 030: a credit fully repaid.
create or replace function trg_notify_debt_settled()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_debt debts%rowtype;
    v_paid numeric;
    v_customer text;
begin
    select * into v_debt from debts where id = new.debt_id;
    select coalesce(sum(amount), 0) into v_paid
      from debt_payments where debt_id = new.debt_id;
    if v_paid >= v_debt.amount then
        select name into v_customer from customers where id = v_debt.customer_id;
        perform notify_org_admins(v_debt.org_id, 'debt_settled',
            format('Crédit soldé : %s a fini de payer %s',
                   coalesce(v_customer, 'un client'),
                   trim_scale(v_debt.amount)),
            jsonb_build_object('to', 'shop', 'customer_id', v_debt.customer_id,
                               'customer', v_customer,
                               'amount', trim_scale(v_debt.amount),
                               'currency', (select default_currency from orgs
                                             where id = v_debt.org_id)));
    end if;
    return new;
exception when others then
    return new;
end;
$$;

-- 030: a tontine round where everyone has paid.
create or replace function trg_notify_tontine_ready()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_t tontines%rowtype;
    v_members int;
    v_paid int;
begin
    select * into v_t from tontines where id = new.tontine_id;
    if new.round <> v_t.current_round then
        return new;
    end if;
    select count(*) into v_members
      from tontine_members where tontine_id = new.tontine_id;
    select count(*) into v_paid
      from tontine_contributions
     where tontine_id = new.tontine_id and round = v_t.current_round;
    if v_members > 0 and v_paid >= v_members then
        perform notify_org_admins(v_t.org_id, 'tontine_ready',
            format('Tontine %s : tour %s prêt à clore, tout le monde a payé',
                   v_t.name, v_t.current_round),
            jsonb_build_object('to', 'shop', 'tontine_id', v_t.id,
                               'name', v_t.name, 'round', v_t.current_round));
    end if;
    return new;
exception when others then
    return new;
end;
$$;

-- 098: an order (or, all services, a demande) placed from the vitrine.
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

-- 055: the customer changes their mind — and now the business hears it.
create or replace function cancel_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_order   orders%rowtype;
    v_booking boolean;
begin
    if auth.uid() is null then
        raise exception 'Sign in first';
    end if;
    update orders
       set status = 'cancelled', updated_at = now(), decided_at = now()
     where id = p_order_id
       and customer_id = auth.uid()
       and status = 'pending'
    returning * into v_order;
    if not found then
        raise exception 'This order can no longer be cancelled';
    end if;
    v_booking := v_order.fulfilment = 'pickup'
        and exists (select 1 from order_lines l where l.order_id = p_order_id)
        and not exists (select 1 from order_lines l
                         where l.order_id = p_order_id and not l.is_service);
    begin
        perform notify_org_admins(v_order.org_id, 'order_withdrawn',
            v_order.customer_name || ' a annulé sa '
            || case when v_booking then 'demande' else 'commande' end,
            jsonb_build_object('to', 'shop', 'order_id', v_order.id,
                               'booking', v_booking, 'name', v_order.customer_name));
    exception when others then
        null;
    end;
end;
$$;

-- 098: the shop answers; the customer hears each status.
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

    v_booking := v_order.fulfilment = 'pickup'
        and exists (select 1 from order_lines l where l.order_id = p_order_id)
        and not exists (select 1 from order_lines l
                         where l.order_id = p_order_id and not l.is_service);

    begin
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
                    else 'annulée' end,
               jsonb_build_object('to', 'customer', 'order_id', v_order.id,
                                  'booking', v_booking, 'shop', o.name,
                                  'status', p_status)
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

-- 056: the platform decides who carries; the courier hears it.
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
        insert into notifications (recipient_id, kind, message, params)
        values (p_user_id, 'courier_' || p_status,
                case p_status
                    when 'approved' then
                        'Vous êtes livreur Kaj : les livraisons vous attendent.'
                    when 'suspended' then
                        'Votre accès livreur est suspendu.'
                    else 'Votre inscription livreur est à l''étude.' end,
                jsonb_build_object('to', 'courier', 'status', p_status));
    exception when others then
        null;
    end;
end;
$$;

-- 073: a courier takes the job.
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

-- 073: the door, with the code.
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
        insert into notifications (recipient_id, org_id, kind, message, params)
        values (v.customer_id, v.org_id, 'order_delivered',
                'Votre commande chez ' || v_shop || ' est livrée',
                jsonb_build_object('to', 'customer', 'order_id', v.id, 'shop', v_shop));
        perform notify_org_admins(v.org_id, 'order_delivered',
            'La commande de ' || v.customer_name || ' est livrée',
            jsonb_build_object('to', 'shop', 'order_id', v.id, 'name', v.customer_name));
    exception when others then null;
    end;
end;
$$;

-- 073: the road is one tap; the door needs the code (courier_deliver).
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
        insert into notifications (recipient_id, org_id, kind, message, params)
        values (v_order.customer_id, v_order.org_id, 'order_in_transit',
                'Votre commande chez ' || v_shop || ' est en route',
                jsonb_build_object('to', 'customer', 'order_id', v_order.id,
                                   'shop', v_shop, 'self', false));
    exception when others then null;
    end;
end;
$$;

-- 073: when the door does not open.
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
            || ') : le livreur rapporte la commande.',
            jsonb_build_object('to', 'shop', 'order_id', v.id,
                               'name', v.customer_name, 'reason', p_reason));
        insert into notifications (recipient_id, org_id, kind, message, params)
        values (v.customer_id, v.org_id, 'delivery_failed',
                'La livraison de votre commande chez ' || v_shop
                || ' n''a pas pu se faire (' || v_words || ').',
                jsonb_build_object('to', 'customer', 'order_id', v.id,
                                   'shop', v_shop, 'reason', p_reason));
    exception when others then null;
    end;
end;
$$;

-- 073: « Je livre moi-même ».
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
        insert into notifications (recipient_id, org_id, kind, message, params)
        values (v.customer_id, v.org_id, 'order_in_transit',
                v_shop || ' vous livre lui-même : votre commande est en route',
                jsonb_build_object('to', 'customer', 'order_id', v.id,
                                   'shop', v_shop, 'self', true));
    exception when others then null;
    end;
end;
$$;

-- 057: the shop says it was paid; the customer hears it.
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
            insert into notifications (recipient_id, org_id, kind, message, params)
            select v_order.customer_id, v_order.org_id, 'order_paid',
                   'Votre paiement chez ' || o.name || ' est confirmé',
                   jsonb_build_object('to', 'customer', 'order_id', v_order.id,
                                      'shop', o.name, 'wave', false)
              from orgs o where o.id = v_order.org_id;
        exception when others then
            null;
        end;
    end if;
end;
$$;

-- 071: the platform answers a spot.
create or replace function decide_promotion(p_promotion_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v promotions%rowtype;
    v_start timestamptz;
begin
    if not exists (select 1 from profiles
                    where id = auth.uid() and is_platform_admin) then
        raise exception 'Seule la plateforme valide une mise en avant';
    end if;
    select * into v from promotions where id = p_promotion_id;
    if not found or v.status not in ('requested', 'paid_claimed') then
        raise exception 'Cette demande n''est plus en attente';
    end if;
    if p_approve then
        v_start := next_spot_start(v.kind);
        update promotions
           set status = 'approved', starts_at = v_start,
               ends_at = v_start + make_interval(days => v.days),
               decided_by = auth.uid(), decided_at = now()
         where id = p_promotion_id;
    else
        update promotions
           set status = 'refused', decided_by = auth.uid(), decided_at = now()
         where id = p_promotion_id;
    end if;
    begin
        perform notify_org_admins(v.org_id, 'spot_' || case when p_approve then 'approved' else 'refused' end,
            case when p_approve
                 then 'Votre mise en avant est validée : elle commence le '
                      || to_char(v_start at time zone 'Africa/Ouagadougou', 'DD/MM à HH24:MI') || '.'
                 else 'Votre demande de mise en avant n''a pas été retenue.' end,
            jsonb_build_object('to', 'shop', 'promotion_id', v.id,
                               'starts_at', v_start, 'wave', false));
    exception when others then null;
    end;
end;
$$;

-- 075: a new device on the account.
create or replace function register_device(p_device_id text, p_label text)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_me    uuid := auth.uid();
    v_label text := left(coalesce(nullif(btrim(p_label), ''), 'Appareil'), 80);
    v_new   boolean;
    v_had   boolean;
begin
    if v_me is null then
        raise exception 'register_device() needs a signed-in caller';
    end if;
    select exists (select 1 from user_devices where user_id = v_me) into v_had;
    insert into user_devices (user_id, device_id, label)
    values (v_me, p_device_id, v_label)
    on conflict (user_id, device_id)
    do update set last_seen = now(), label = excluded.label
    returning (xmax = 0) into v_new;
    if v_new then
        perform security_log(v_me, 'new_device', v_label);
        if v_had then
            begin
                insert into notifications (recipient_id, org_id, kind, message, params)
                values (v_me, null, 'new_device',
                        'Nouvelle connexion à votre compte sur ' || v_label
                        || '. Ce n''était pas vous ? Ouvrez Compte › Sécurité '
                        || 'et fermez les autres appareils.',
                        jsonb_build_object('device', v_label));
            exception when others then null;
            end;
        end if;
    end if;
    return v_new;
end;
$$;

-- 076: Wave says a session ended.
create or replace function wave_settle(
    p_client_reference uuid,
    p_session_id       text,
    p_succeeded        boolean,
    p_transaction_id   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v     wave_payments%rowtype;
    v_org orgs%rowtype;
    v_start timestamptz;
    v_until date;
begin
    select * into v from wave_payments where id = p_client_reference for update;
    if not found then
        return null;
    end if;
    if v.session_id is not null and p_session_id is not null and v.session_id <> p_session_id then
        return null;
    end if;
    if v.status = 'succeeded' then
        return null;  -- delivered twice
    end if;
    if not p_succeeded then
        update wave_payments set status = 'failed' where id = v.id;
        return null;
    end if;

    update wave_payments
       set status = 'succeeded', paid_at = now(),
           transaction_id = p_transaction_id,
           session_id = coalesce(session_id, p_session_id)
     where id = v.id;
    select * into v_org from orgs where id = v.org_id;

    if v.kind = 'order' then
        update orders set paid_at = coalesce(paid_at, now()), payment_method = 'wave'
         where id = v.order_id;
        update wave_payments
           set payout_status = 'pending',
               payout_to = v_org.wave_payout_number,
               payout_amount = v.amount - v.commission
         where id = v.id;
        begin
            perform notify_org_admins(v.org_id, 'order_paid',
                'Commande payée par Wave : ' || to_char(v.amount, 'FM999G999G999')
                || ' F. L''argent part sur votre numéro Wave.',
                jsonb_build_object('to', 'shop', 'order_id', v.order_id,
                                   'amount', v.amount, 'currency', v.currency,
                                   'wave', true));
            insert into notifications (recipient_id, org_id, kind, message, params)
            select o.customer_id, o.org_id, 'order_paid',
                   'Paiement reçu par ' || v_org.name || ' : merci !',
                   jsonb_build_object('to', 'customer', 'order_id', o.id,
                                      'shop', v_org.name, 'wave', true)
              from orders o where o.id = v.order_id;
        exception when others then null;
        end;
        return jsonb_build_object(
            'payment_id', v.id,
            'amount', v.amount - v.commission,
            'currency', v.currency,
            'mobile', v_org.wave_payout_number,
            'name', v_org.name);
    elsif v.kind = 'pro' then
        v_until := greatest(coalesce(case when v_org.plan = 'pro' then v_org.plan_until end,
                                     current_date), current_date)
                   + case when v.period = 'year' then interval '1 year' else interval '1 month' end;
        update orgs set plan = 'pro', plan_until = v_until,
                        plan_note = 'Wave ' || coalesce(p_transaction_id, '')
         where id = v.org_id;
        insert into plan_requests (org_id, user_id, amount, note, handled_at)
        values (v.org_id, v.payer_id, v.amount, 'Payé par Wave', now());
        begin
            perform notify_org_admins(v.org_id, 'pro_active',
                'Kaj Pro est actif jusqu''au ' || to_char(v_until, 'DD/MM/YYYY') || '.',
                jsonb_build_object('to', 'shop', 'until', v_until, 'card', false));
        exception when others then null;
        end;
    elsif v.kind = 'spot' then
        v_start := next_spot_start('article');
        update promotions
           set status = 'approved',
               starts_at = case when kind = 'shop' then now() else v_start end,
               ends_at = case when kind = 'shop' then now() else v_start end
                         + make_interval(days => days),
               decided_at = now(),
               note = 'Payé par Wave'
         where id = v.promotion_id and status in ('requested', 'paid_claimed');
        begin
            perform notify_org_admins(v.org_id, 'spot_approved',
                'Mise en avant payée par Wave : elle est programmée.',
                jsonb_build_object('to', 'shop', 'promotion_id', v.promotion_id,
                                   'wave', true));
        exception when others then null;
        end;
    end if;
    return null;
end;
$$;

-- 082: Stripe says a subscription moved.
create or replace function stripe_settle(
    p_org_id          uuid,
    p_subscription_id text,
    p_customer_id     text,
    p_status          text,
    p_period          text,
    p_period_end      timestamptz,
    p_cancel_at_end   boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_was  text;
    v_org  orgs%rowtype;
    v_until date;
    v_active boolean := p_status in ('active', 'trialing');
begin
    select * into v_org from orgs where id = p_org_id;
    if not found then
        return jsonb_build_object('ok', false, 'reason', 'no such business');
    end if;
    select status into v_was from stripe_subscriptions where org_id = p_org_id;

    insert into stripe_subscriptions (org_id, customer_id, subscription_id, status,
                                      period, current_period_end, cancel_at_period_end,
                                      updated_at)
    values (p_org_id, p_customer_id, p_subscription_id, p_status,
            case when p_period in ('month', 'year') then p_period end,
            p_period_end, coalesce(p_cancel_at_end, false), now())
    on conflict (org_id) do update set
        customer_id          = coalesce(excluded.customer_id, stripe_subscriptions.customer_id),
        subscription_id      = coalesce(excluded.subscription_id, stripe_subscriptions.subscription_id),
        status               = excluded.status,
        period               = coalesce(excluded.period, stripe_subscriptions.period),
        current_period_end   = coalesce(excluded.current_period_end,
                                        stripe_subscriptions.current_period_end),
        cancel_at_period_end = excluded.cancel_at_period_end,
        updated_at           = now();

    if v_active and p_period_end is not null then
        v_until := (p_period_end at time zone 'Africa/Ouagadougou')::date + 1;
        -- Never shorter than what the business already has: a later date
        -- paid by Wave stays, and a Pro with no end (a gift) keeps none.
        update orgs
           set plan_until = case
                   when plan = 'pro' and plan_until is null then null
                   when plan = 'pro' then greatest(plan_until, v_until)
                   else v_until end,
               plan = 'pro',
               plan_note = 'Stripe ' || coalesce(p_subscription_id, '')
         where id = p_org_id;
        if v_was is distinct from p_status and v_was is distinct from 'active' then
            begin
                perform notify_org_admins(p_org_id, 'pro_active',
                    'Kaj Pro est actif, payé par carte, jusqu''au '
                    || to_char(v_until, 'DD/MM/YYYY') || '.',
                    jsonb_build_object('to', 'shop', 'until', v_until, 'card', true));
            exception when others then null;
            end;
        end if;
    end if;
    return jsonb_build_object('ok', true, 'active', v_active, 'until', v_until);
end;
$$;

-- 086: the board, four times a week.
create or replace function cauris_board_notify()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_from timestamptz := cauris_week_start();
    v_n    int := 0;
    r      record;
    v_top  text;
    v_top_j jsonb;
    v_me   record;
    v_gap  int;
begin
    create temporary table if not exists _all (
        org_id uuid, name text, hidden boolean, league text, score int, rank int) on commit drop;
    truncate _all;
    insert into _all
    select s.org_id, s.name, s.hidden, s.league, s.score,
           (rank() over (partition by s.league order by s.score desc, s.name))::int
      from league_scores(v_from, now()) s;

    for r in select a.* from _all a join orgs o on o.id = a.org_id where o.board_notify loop
        select string_agg(t.rank || '. ' ||
                   case when t.hidden then 'une ' ||
                        case when split_part(r.league, '|', 1) = 'farm' then 'ferme' else 'boutique' end
                        else t.name end
                   || ' ' || t.score, ' · ' order by t.rank, t.name),
               jsonb_agg(jsonb_build_object(
                   'rank', t.rank,
                   'name', case when t.hidden then null else t.name end,
                   'score', t.score) order by t.rank, t.name)
          into v_top, v_top_j
          from (select * from _all where league = r.league and score > 0
                 order by rank, name limit 3) t;
        if v_top is null then
            continue;  -- nobody has earned yet in this league this week
        end if;
        select min(score) into v_gap from _all
         where league = r.league and score > r.score;
        perform notify_org_admins(r.org_id, 'cauris_board',
            '🏆 ' || league_label(r.league) || ' : ' || v_top || '. '
            || case
                 when r.rank = 1 and r.score > 0 then 'Vous êtes 1er, bravo ! Gardez la tête.'
                 when v_gap is not null then 'Vous êtes ' || r.rank || 'e : encore '
                      || (v_gap - r.score + 1) || ' cauris pour la place devant.'
                 else 'Vous êtes ' || r.rank || 'e.'
               end,
            jsonb_build_object('to', 'shop', 'league', r.league, 'top', v_top_j,
                               'rank', r.rank, 'score', r.score,
                               'first', r.rank = 1 and r.score > 0,
                               'gap', case when v_gap is not null
                                           then v_gap - r.score + 1 end));
        v_n := v_n + 1;
    end loop;
    return v_n;
end;
$$;

-- 086: the week's close and its prizes.
create or replace function cauris_week_close(p_week_start date default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_from timestamptz := coalesce(p_week_start::timestamp at time zone 'Africa/Ouagadougou',
                                   cauris_week_start() - interval '7 days');
    v_to   timestamptz := v_from + interval '7 days';
    v_week date := (v_from at time zone 'Africa/Ouagadougou')::date;
    v_n    int := 0;
    r      record;
    v_pts  int;
begin
    for r in
        select x.* from (
            select s.org_id, s.league, s.score,
                   (rank() over (partition by s.league order by s.score desc, s.name))::int as rank
              from league_scores(v_from, v_to) s
             where s.score > 0
        ) x where x.rank <= 3
    loop
        insert into cauris_week_results (week_start, org_id, league, rank, score)
        values (v_week, r.org_id, r.league, r.rank, r.score)
        on conflict (week_start, org_id) do nothing;
        if not found then
            continue;  -- already closed: once per week
        end if;
        v_pts := cauris_param('cauris_prize_' || r.rank, 0);
        if v_pts > 0 then
            insert into cauris_ledger (org_id, delta, reason, ref, note)
            values (r.org_id, v_pts, 'prize', v_week::text,
                    r.rank || 'e de la semaine · ' || league_label(r.league))
            on conflict do nothing;
        end if;
        if r.rank = 1 then
            insert into promotions (org_id, kind, days, price, currency, free, status,
                                    starts_at, ends_at, decided_at, note)
            values (r.org_id, 'shop', 7, 0, 'XOF', true, 'approved',
                    next_spot_start('shop'), next_spot_start('shop') + interval '7 days',
                    now(), 'Premier de la semaine (cauris)');
        end if;
        begin
            perform notify_org_admins(r.org_id, 'cauris_prize',
                '🏆 ' || r.rank || 'e de la semaine en ' || league_label(r.league)
                || ' ! +' || v_pts || ' cauris'
                || case when r.rank = 1 then ', et votre vitrine mise en avant 7 jours.' else '.' end,
                jsonb_build_object('to', 'shop', 'league', r.league, 'rank', r.rank,
                                   'points', v_pts, 'spot', r.rank = 1));
        exception when others then null;
        end;
        v_n := v_n + 1;
    end loop;
    return v_n;
end;
$$;

-- 096: the steps open now and not before, recorded and told.
create or replace function check_unlocks(p_org_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_profile text;
    v_step    text;
    v_made    integer := 0;
begin
    select o.profile::text into v_profile from orgs o where o.id = p_org_id;
    if v_profile is null or v_profile not in ('retail', 'farm')
       or org_plan(p_org_id) = 'pro' then
        return 0;
    end if;
    -- All three already open: one index lookup, the common case.
    if (select count(*) from org_unlocks u where u.org_id = p_org_id) >= 3 then
        return 0;
    end if;
    foreach v_step in array array['invoices', 'production', 'credits'] loop
        if not exists (select 1 from org_unlocks u
                        where u.org_id = p_org_id and u.step = v_step)
           and not path_locked(p_org_id, v_step) then
            insert into org_unlocks (org_id, step) values (p_org_id, v_step)
                on conflict do nothing;
            if found then
                v_made := v_made + 1;
                perform notify_org_admins(p_org_id, 'unlock', unlock_message(v_step),
                    jsonb_build_object('to', 'shop', 'step', v_step,
                                       'articles', path_goal(null, 'articles'),
                                       'photos', path_goal(null, 'photos'),
                                       'orders', path_goal(null, 'three_orders')));
            end if;
        end if;
    end loop;
    return v_made;
end;
$$;

-- ------------------------------------------------------------
-- 3. Grants (063: a new function is born closed to anon and PUBLIC, and
--    open to authenticated — which these must not be)
-- ------------------------------------------------------------
revoke execute on function second_business_locked(uuid)                    from public;
revoke execute on function notify_org_admins(uuid, text, text, jsonb, uuid) from public;
revoke execute on function notify_org_admins(uuid, text, text, uuid)        from public;
revoke execute on function notify_platform_spot(text, text)                 from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function second_business_locked(uuid)                    from anon;
        revoke execute on function notify_org_admins(uuid, text, text, jsonb, uuid) from anon;
        revoke execute on function notify_org_admins(uuid, text, text, uuid)        from anon;
        revoke execute on function notify_platform_spot(text, text)                 from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Read inside path_locked and the door, as their owner.
        revoke execute on function second_business_locked(uuid)                    from authenticated;
        -- Rung by the server's own functions only: nobody writes to another
        -- person's bell, or to their phone.
        revoke execute on function notify_org_admins(uuid, text, text, jsonb, uuid) from authenticated;
        revoke execute on function notify_org_admins(uuid, text, text, uuid)        from authenticated;
        revoke execute on function notify_platform_spot(text, text)                 from authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
