-- ============================================================
-- 109_shopper_order_gate.sql — a shopper's number, proved on WhatsApp,
-- before an order (the owner's words: « make sure their phone number is
-- added and verified through WhatsApp before they can order »).
--
-- How a number is proved: the app asks Supabase to change the account's
-- phone (auth.updateUser(phone)); Supabase makes a six-digit code and,
-- through its « Send SMS » auth hook, hands it to the whatsapp-otp Worker,
-- which sends it with Mara's approved WhatsApp « authentication » template;
-- the shopper types it (verifyOTP, type phone_change) and Supabase sets
-- auth.users.phone and phone_confirmed_at. Nothing of that is here: this
-- file is the server's side of the rule.
--
--   1. platform_settings.order_phone_verified, OFF (false). Réglages shows
--      it (105's board lists every key), changed through 105's
--      platform_set_setting — oui/non only, journaled, undoable. It is
--      switched on only once the Worker, the template and the hook are set
--      up (BUILD_PLAN.md, « Numéros vérifiés par WhatsApp »): until then a
--      code could not reach anybody, and nobody could order.
--   2. order_phone_gate(): the app's question before it opens the order
--      sheet — is a proved number asked (the switch), is this account's
--      number proved, and which. The signed-in caller's own number only.
--   3. place_order (101's, which 099 and 098 built; nothing after 101
--      replaced it): with the switch on, an account with no proved number
--      is refused « Vérifiez d'abord votre numéro WhatsApp » before
--      anything is written, and the order carries the proved number (the
--      number typed on the sheet is not proved; with the switch on the app
--      no longer asks for one). A booking (098: services only) is an order
--      here, so it is gated the same. With the switch off — as installed —
--      every line of 101 runs as it did: P1, ordering unchanged.
--
-- For all three kinds alike — a shop's vitrine, a farm's « À vendre », an
-- association's services: the rule is the shopper's, never the business's;
-- no business reads or changes anything here. No vitrine shows anything
-- new: the street is read by anyone, and the gate stands only at the
-- order, after sign-in.
--
-- Born closed (063): the two helpers are internal (place_order and the
-- gate call them as their owner); order_phone_gate and place_order are for
-- a signed-in person. Re-runnable: functions replaced with their own
-- signatures, the setting inserted « on conflict do nothing » (a value the
-- platform set is never put back).
-- ============================================================

do $$
begin
    if to_regclass('public.platform_settings') is null
       or to_regprocedure('public.stock_short_message(text, numeric)') is null
       or to_regprocedure('public.platform_set_setting(text, jsonb)') is null then
        raise exception '109 needs 101 (stock_short_message) and 105 (platform_set_setting) applied first';
    end if;
end $$;

-- ------------------------------------------------------------
-- 1. The switch, off
-- ------------------------------------------------------------
insert into platform_settings (key, value) values ('order_phone_verified', 'false')
on conflict (key) do nothing;

-- On, only when the platform said oui. Anything else — no row, a value
-- that is not true — is off.
create or replace function order_phone_required()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((select value = 'true'::jsonb from platform_settings
                      where key = 'order_phone_verified'), false);
$$;

-- The caller's proved number, written the way orders keep a number
-- (« +226… »: Supabase keeps it without the +), or null when the account
-- has none proved.
create or replace function my_verified_phone()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
    select case when left(btrim(u.phone), 1) = '+' then btrim(u.phone)
                else '+' || btrim(u.phone) end
      from auth.users u
     where u.id = auth.uid()
       and u.phone_confirmed_at is not null
       and nullif(btrim(coalesce(u.phone, '')), '') is not null;
$$;

-- ------------------------------------------------------------
-- 2. The app's question
-- ------------------------------------------------------------
create or replace function order_phone_gate()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_phone text;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous pour commander';
    end if;
    v_phone := my_verified_phone();
    return jsonb_build_object(
        'required', order_phone_required(),
        'verified', v_phone is not null,
        'phone',    v_phone);
end;
$$;

-- ------------------------------------------------------------
-- 3. place_order: 101's, with the gate
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
-- Grants: born closed (063); each opened to whom it is for.
-- ------------------------------------------------------------
revoke execute on function order_phone_required() from public;
revoke execute on function my_verified_phone()    from public;
revoke execute on function order_phone_gate()     from public;
revoke execute on function place_order(text, jsonb, text, text, text, text, text, double precision, double precision) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function order_phone_required() from anon;
        revoke execute on function my_verified_phone()    from anon;
        revoke execute on function order_phone_gate()     from anon;
        revoke execute on function place_order(text, jsonb, text, text, text, text, text, double precision, double precision) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: read by the two doors below, as their owner.
        revoke execute on function order_phone_required() from authenticated;
        revoke execute on function my_verified_phone()    from authenticated;
        -- The doors: a signed-in person, asking about their own number and
        -- placing their own order.
        grant execute on function order_phone_gate()      to authenticated;
        grant execute on function place_order(text, jsonb, text, text, text, text, text, double precision, double precision) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
