-- ============================================================
-- 140_prices_by_area.sql — batch 144: a business's money follows where it
-- is, everywhere, for a shop, a farm and an association alike.
--
-- The app does most of it (144): a new business starts in its country's
-- money (Brazil BRL, France EUR, the United States USD, Cameroon XAF…,
-- never XOF by accident), every screen writes amounts with that money's
-- own decimals, the settings keep a business's money whatever it is. Each
-- business already keeps its money in orgs.default_currency (001), and
-- every order, invoice and notification already carries it. What the
-- server must hold:
--
-- 1. THE STREET'S CARDS. A directory card with no photograph shows three
--    articles and their prices, like a menu board (070's
--    storefront_previews) — and the app wrote « F » after every price,
--    whatever the shop's money: a Paris shop read « 12 F ». The previews
--    say no money, and storefront_directory neither. A new door,
--    storefront_currencies(p_slugs), says the money of each open vitrine
--    asked for (the same vitrines storefront_previews answers for, by
--    storefront_open, nothing else about them): additive, so 070's two
--    doors — and what 104 and 110's P1 compare — are unchanged. Open to
--    anon, like every door of the street; a definer with its path pinned.
--
-- 2. A DELIVERY'S PRICE. delivery_fee (061, last 110) rounds every fee to
--    25: right for the franc CFA, whose smallest coin is 25 F, but a Paris
--    shop at 2,50 € + 0,80 €/km had every run at 0 € or 25 €. Now the
--    franc CFA (XOF, XAF) still rounds to 25 — identical answer for
--    answer —, and any other money rounds to its own decimals (2 for the
--    euro, the dollar, the real; 0 for the yen).
--    110's function verbatim otherwise. currency_decimals(code) is ISO
--    4217's minor units, as the app's currencies.dart says them.
--
-- 3. « PRIX EN BAISSE » (113's trg_vitrine_news): the bell a follower gets
--    wrote the new price with no decimals — « à 13 EUR » for 12,50 € —
--    and now writes it as the app does (money_text): « à 12,50 EUR »,
--    « à 450 FCFA ». 113's function verbatim otherwise.
--
-- 4. EVERY OTHER BELL WITH AN AMOUNT. The server wrote amounts with
--    to_char's G and D, which follow the database's lc_numeric: on an
--    en_US database a new order read « 12,000.00 XOF », a Paris
--    shop's « 12.50 EUR », and the couriers' and Wave's bells said « F »
--    whatever the money. money_text(amount, currency) writes them as the
--    app's moneyFormat does — fr_FR grouping, a decimal comma, the
--    money's own decimals, « FCFA » for both francs CFA (XOF, XAF), every
--    other money its code: « 12 000 FCFA », « 12,50 EUR ». place_order's
--    « Nouvelle commande », tell_couriers' « Nouvelle livraison »,
--    trg_notify_courier_cash, wave_settle's « Commande payée par Wave »
--    and trg_notify_debt_settled's « Crédit soldé » (which said no money
--    at all): each its last version verbatim but those words, its
--    signature, its SECURITY DEFINER and its grants unchanged. The
--    params beside each message (what the English line is written from)
--    are unchanged.
--
-- 5. TOTALS ACROSS BUSINESSES. A courier's tally, the courier settlement,
--    the platform's analytics and « Revenus de Mara » summed fees, parts
--    and sales over every order whatever its money: a euro delivery's
--    4,10 added to francs. New doors say them per money —
--    courier_earnings_by_currency, platform_delivery_settlement_by_currency,
--    platform_analytics_by_currency, platform_business_currencies — beside
--    the old ones, which stay word for word for the app before 144; and
--    platform_today (same signature) says delivery_cut in francs CFA only,
--    as its 'currency' and its shops_sold already did, the other moneys
--    beside it ('other'). The prices themselves (Pro, the spots, the
--    platform's share and tariff) are the platform's (batch 142).

-- Nothing else changes, and no row is written: every business keeps the
-- money it has (live: the businesses keep theirs; this migration reads and
-- writes no business's data). Mara's own prices — Pro, the spots, the
-- platform's delivery tariff and its share — stay the platform's (batch
-- 142), in their own money.
--
-- Re-runnable: create or replace everywhere, the grants said again.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Minor units (ISO 4217)
-- ------------------------------------------------------------
create or replace function currency_decimals(p_code text)
returns int
language sql
immutable
set search_path = public
as $$
    select case upper(btrim(coalesce(p_code, '')))
        -- No minor unit: the francs CFA, the Guinean, Burundian, Rwandan,
        -- Comorian and Djiboutian francs, the Ugandan shilling, the yen,
        -- the won, the Chilean peso, the Icelandic króna, the đồng.
        when 'XOF' then 0 when 'XAF' then 0 when 'GNF' then 0
        when 'BIF' then 0 when 'RWF' then 0 when 'KMF' then 0
        when 'DJF' then 0 when 'UGX' then 0 when 'JPY' then 0
        when 'KRW' then 0 when 'CLP' then 0 when 'ISK' then 0
        when 'VND' then 0 when 'PYG' then 0 when 'VUV' then 0
        when 'XPF' then 0
        -- Every other two — the dinars of Tunisia, Libya, Kuwait, Bahrain,
        -- Jordan and Iraq and the Omani rial too: ISO 4217 gives them
        -- three, but every money column is numeric(14,2)/(12,2) and would
        -- cut a third on save; the app (currencies.dart) says two as well.
        else 2
    end;
$$;

-- An amount as the app writes it (money.dart's moneyFormat, intl's
-- fr_FR): grouped by a narrow no-break space, a decimal comma, its money's
-- own decimals — « 12 000 » for the franc CFA, « 12,50 » for the euro. Never the server's locale: to_char's
-- G and D follow lc_numeric, and an en_US database wrote « 12,000.00 ».
create or replace function amount_text(p_amount numeric, p_currency text)
returns text
language sql
immutable
set search_path = public
as $$
    with x as (
        select currency_decimals(coalesce(p_currency, 'XOF')) as d,
               round(abs(p_amount), currency_decimals(coalesce(p_currency, 'XOF'))) as a,
               p_amount < 0 as neg
         where p_amount is not null  -- no amount, no text
    ), parts as (
        select d, neg,
               trunc(a)::text as whole,
               case when d > 0
                    then lpad(((a - trunc(a)) * power(10, d))::numeric(30, 0)::text, d, '0')
               end as cents
          from x
    )
    select case when neg and (whole <> '0' or coalesce(cents, '') ~ '[1-9]') then '-' else '' end
           || regexp_replace(whole, '(\d)(?=(\d{3})+$)', '\1' || U&'\202F', 'g')
           || case when d > 0 then ',' || cents else '' end
      from parts;
$$;

-- What the app writes after an amount (money.dart's currencySymbol): the
-- two francs CFA as « FCFA », every other money its code.
create or replace function currency_symbol(p_currency text)
returns text
language sql
immutable
set search_path = public
as $$
    select case when c in ('XOF', 'XAF') then 'FCFA' else c end
      from (select upper(coalesce(nullif(btrim(p_currency), ''), 'XOF')) as c) x;
$$;

-- An amount and its money, as the app writes it: « 12 000 FCFA »,
-- « 12,50 EUR » — the bells' one way (a no-break space before the money,
-- so a push never breaks « 12 000 » from « FCFA »).
create or replace function money_text(p_amount numeric, p_currency text)
returns text
language sql
immutable
set search_path = public
as $$
    select amount_text(p_amount, coalesce(p_currency, 'XOF')) || U&'\00A0'
           || currency_symbol(coalesce(p_currency, 'XOF'));
$$;

-- ------------------------------------------------------------
-- 2. The street's cards: each open vitrine's money
-- ------------------------------------------------------------
create or replace function storefront_currencies(p_slugs text[])
returns table (
    slug     text,
    currency text
)
language sql
stable
security definer
set search_path = public
as $$
    select o.slug, coalesce(o.default_currency, 'XOF')
      from orgs o
     where o.slug = any (coalesce(p_slugs, '{}'))
       and o.id = storefront_open(o.slug)
     order by o.slug;
$$;

-- ------------------------------------------------------------
-- 3. A delivery's price, rounded in its own money (110's, verbatim but
--    the last line)
-- ------------------------------------------------------------
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
    v_included numeric;
    v_currency text;
    v_fee      numeric;
    v_km       double precision;
begin
    if p_lat is null or p_lng is null then
        return null;
    end if;
    select * into v_org from orgs where id = p_org_id;
    if not found or v_org.lat is null or v_org.lng is null then
        return null;
    end if;
    if not org_has(p_org_id, 'delivery') then
        return null; -- delivery is Pro, or unlocked with cauris (085)
    end if;
    if feature_hidden(p_org_id, 'delivery') then
        return null; -- 110: Mara's switchboard hid « Livraison » here
    end if;
    v_km := distance_km(v_org.lat, v_org.lng, p_lat, p_lng);
    if v_km > delivery_reach_km(p_org_id) then
        return null; -- out of reach: there is no price for an impossible run
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
    v_included := coalesce(
        v_org.delivery_included_km,
        (select (value #>> '{}')::numeric from platform_settings
          where key = 'delivery_included_km'),
        0);
    v_fee := v_base + v_per_km * greatest(0, v_km - v_included);
    -- 140: the franc CFA's smallest coin is 25 F; any other money keeps
    -- its own decimals (a Paris shop's 4,10 € stays 4,10 €).
    if coalesce(v_org.default_currency, 'XOF') in ('XOF', 'XAF') then
        return round(v_fee / 25) * 25;
    end if;
    return round(v_fee, currency_decimals(v_org.default_currency));
end;
$$;

-- ------------------------------------------------------------
-- 4. « Prix en baisse » with its money's decimals (113's, verbatim but
--    the price)
-- ------------------------------------------------------------
create or replace function trg_vitrine_news()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_day   date := (now() at time zone 'Africa/Ouagadougou')::date;
    v_offer boolean;
    v_org   orgs%rowtype;
    v_line  text;
    v_rows  uuid[];
    v_users uuid[];
begin
    if not (new.is_active and new.is_published) then
        return new;
    end if;
    if tg_op = 'INSERT' or not (old.is_active and old.is_published) then
        v_offer := false;
    elsif new.sale_price < old.sale_price then
        v_offer := true;
    else
        return new;
    end if;
    -- Nobody follows this business with news on: nothing to read further.
    if not exists (select 1 from vitrine_follows f where f.org_id = new.org_id and f.news) then
        return new;
    end if;
    begin
        select * into v_org from orgs where id = new.org_id;
        -- What the street sees, and only that.
        if not (v_org.storefront_enabled and v_org.archived_at is null
                and v_org.suspended_at is null
                and vitrine_items(v_org.id) >= vitrine_min(v_org.id)
                and vitrine_shows(v_org.id, new.is_service)) then
            return new;
        end if;
        v_line := case when v_offer
            then format('Prix en baisse chez %s : %s à %s', v_org.name, new.name,
                        -- 140: as the app writes it (« 12,50 EUR », « 450 FCFA »).
                        money_text(new.sale_price, coalesce(v_org.default_currency, 'XOF')))
            else format('Nouveau chez %s : %s', v_org.name, new.name) end;

        -- Told already today: the day's row says one more — every such
        -- follower in ONE statement (a vitrine with thousands of followers
        -- must not cost the owner a write per follower). After 20
        -- novelties the row is left as it is (« 20 nouveautés chez … :
        -- A, B, C… »): the vitrine shows the rest, and the owner's next
        -- articles of the day cost no rewrite at all.
        update notifications n
           set message = format('%s nouveautés chez %s : %s%s', x.n, v_org.name,
                                (select string_agg(e, ', ') from jsonb_array_elements_text(x.names) e),
                                case when x.n > jsonb_array_length(x.names) then '…' else '' end),
               params  = jsonb_build_object('to', 'customer', 'shop', v_org.name,
                                            'slug', v_org.slug, 'count', x.n,
                                            'names', x.names, 'ids', x.ids || to_jsonb(new.id::text)),
               read_at = null
          from vitrine_follows f
          cross join lateral (
              select coalesce((nn.params ->> 'count')::int, 1) + 1 as n,
                     coalesce(nn.params -> 'ids', '[]'::jsonb) as ids,
                     case when jsonb_array_length(coalesce(nn.params -> 'names', '[]'::jsonb)) < 3
                               and not coalesce(nn.params -> 'names', '[]'::jsonb) ? new.name
                          then coalesce(nn.params -> 'names', '[]'::jsonb) || to_jsonb(new.name)
                          else coalesce(nn.params -> 'names', '[]'::jsonb) end as names
                from notifications nn where nn.id = f.told_id
          ) x
         where f.org_id = new.org_id and f.news and f.told_on = v_day
           and n.id = f.told_id
           and not exists (select 1 from shopper_settings s
                            where s.user_id = f.user_id and not s.vitrine_news)
           -- At most 20; the same article twice the same day is said once.
           and coalesce((n.params ->> 'count')::int, 1) < 20
           and not coalesce(n.params -> 'ids', '[]'::jsonb) ? new.id::text;

        -- Not told today: one row each (060's webhook pushes it once). The
        -- day is claimed first, row by row, so two writes at once never
        -- tell the same follower twice.
        with fresh as (
            update vitrine_follows f
               set told_on = v_day, told_id = null
             where f.org_id = new.org_id and f.news
               and f.told_on is distinct from v_day
               and not exists (select 1 from shopper_settings s
                                where s.user_id = f.user_id and not s.vitrine_news)
               and not exists (select 1 from memberships m
                                where m.org_id = f.org_id and m.user_id = f.user_id)
            returning f.user_id
        ), told as (
            insert into notifications (recipient_id, org_id, kind, message, params)
            select fresh.user_id, new.org_id, 'vitrine_news', v_line,
                   jsonb_build_object('to', 'customer', 'shop', v_org.name, 'slug', v_org.slug,
                                      'count', 1, 'names', jsonb_build_array(new.name),
                                      'ids', jsonb_build_array(new.id::text),
                                      'offer', v_offer, 'price', new.sale_price,
                                      'currency', coalesce(v_org.default_currency, 'XOF'))
              from fresh
            returning id, recipient_id
        )
        select coalesce(array_agg(told.id), '{}'), coalesce(array_agg(told.recipient_id), '{}')
          into v_rows, v_users
          from told;
        -- The day's row, for the next novelty of the day (a statement of
        -- its own: a row is changed once per statement).
        update vitrine_follows f set told_id = t.nid
          from unnest(v_rows, v_users) as t(nid, uid)
         where f.user_id = t.uid and f.org_id = new.org_id;
    exception when others then
        -- Books beat bells (030): the article is saved whatever happens here.
        null;
    end;
    return new;
end;
$$;

-- ------------------------------------------------------------
-- 5. The other bells with an amount, as the app writes it. Each is its
--    last version verbatim but the amount's words, its signature and its
--    SECURITY DEFINER unchanged: on a database whose lc_numeric is
--    en_US, a Paris shop's « Nouvelle commande » read « 12,000.00 EUR »
--    and a courier's « (1500 F) » said francs whatever the money.
--    « 12 000 FCFA », « 12,50 EUR » now, as the app shows them (and as
--    notification_text.dart writes the English line from params, which
--    are unchanged).
-- ------------------------------------------------------------

-- place_order: 131_catalogue_backfill.sql's, but the bell's amounts.
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
    -- 125: a booking (a slot given), its one line, its slot, its unit.
    v_booking  boolean;
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

    -- 125: a line that carries a slot (« booked_for », even empty — the
    -- key is what book_service always writes) is a booking, held to every
    -- rule below. A call with no slot is 109's, word for word: the app
    -- installed before 125 (an Android or iPhone build not yet updated)
    -- still sends a basket of services with its day in the note, and it
    -- must keep working — booked_for stays null on it, and the new app
    -- shows it as it always did.
    v_booking := exists (select 1 from jsonb_array_elements(p_lines) l
                          where jsonb_typeof(l) = 'object' and l ? 'booked_for');
    if not v_booking then
        -- 109: services only is an appointment, not a parcel.
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
    end if;

    -- 125: a booking is one service alone — never beside goods, never two
    -- at once. Said before the delivery rules, so the customer hears the
    -- reason that applies.
    if v_booking then
        select count(*) into v_svc
          from jsonb_array_elements(p_lines) l
          join products p
            on p.id = nullif(l ->> 'product_id', '')::uuid and p.org_id = v_org
         where p.is_service;
        if v_svc = 0 then
            raise exception 'Seul un service se réserve à une heure';
        end if;
        v_services := true;
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
       and p.stock_tracked
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
            -- 125: a booking says its slot, as Commandes shows it; a basket
            -- of services with no slot (an older app) is 109's « demande ».
            case when v_booking
                 then 'Rendez-vous demandé par ' || v_name || ' — ' || booking_when_fr(v_booked)
                      || ' : '
                 when v_services then 'Nouvelle demande de ' || v_name || ' : '
                 else 'Nouvelle commande de ' || v_name || ' : ' end
            -- 140: as the app writes it (« 12 000 FCFA », « 12,50 EUR »).
            || money_text(v_total, coalesce(v_currency, 'XOF'))
            || case when p_payment = 'wave' then ' (Wave)' else '' end
            || case when v_fee is not null
                    then ' + livraison ' || money_text(v_fee, coalesce(v_currency, 'XOF')) else '' end,
            jsonb_build_object('to', 'shop', 'order_id', v_id, 'booking', v_services,
                               'name', v_name, 'total', v_total,
                               'currency', coalesce(v_currency, 'XOF'),
                               'wave', p_payment = 'wave', 'fee', v_fee)
            || case when v_booking then jsonb_build_object('at', v_booked)
                    else '{}'::jsonb end);
    exception when others then
        null;
    end;

    return v_id;
end;
$$;


-- tell_couriers: 122_courier_radius.sql's, but the fee's words.
create or replace function tell_couriers(p_order_id uuid, p_own_only boolean)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v      orders%rowtype;
    v_shop orgs%rowtype;
    v_n    integer;
begin
    select * into v from orders where id = p_order_id;
    select * into v_shop from orgs where id = v.org_id;
    insert into notifications (recipient_id, org_id, kind, message, params)
    select c.user_id, v.org_id, 'delivery_available',
           'Nouvelle livraison près de vous : ' || v_shop.name
           || case when v.delivery_fee is null then ''
                   -- 140: in the order's money (« 1 500 FCFA », « 4,10 EUR »).
                   else ' (' || money_text(v.delivery_fee, v.currency) || ')' end,
           jsonb_build_object('to', 'courier', 'order_id', v.id, 'shop', v_shop.name,
                              'fee', v.delivery_fee, 'currency', v.currency,
                              'own', exists (select 1 from org_couriers oc
                                              where oc.org_id = v.org_id and oc.user_id = c.user_id))
      from couriers c
     where c.status = 'approved'
       and c.user_id is distinct from v.customer_id
       and (case when p_own_only
                 then exists (select 1 from org_couriers oc
                               where oc.org_id = v.org_id and oc.user_id = c.user_id)
                 else not exists (select 1 from org_couriers oc
                                   where oc.org_id = v.org_id and oc.user_id = c.user_id)
                      and courier_reach(c.user_id, v.org_id) in ('near', 'city')
            end)
     order by c.decided_at desc nulls last, c.user_id
     limit 50;
    get diagnostics v_n = row_count;
    if not p_own_only then
        update orders set couriers_told_at = now() where id = p_order_id;
    end if;
    return v_n;
end;
$$;


-- trg_notify_courier_cash: 115_notifications.sql's, but the amount's words.
create or replace function trg_notify_courier_cash()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.cash_received_at is not null and old.cash_received_at is null
       and new.courier_id is not null then
        insert into notifications (recipient_id, org_id, kind, message, params)
        select new.courier_id, new.org_id, 'courier_cash_received',
               o.name || ' confirme avoir reçu l''argent de la livraison pour '
               -- 140: in the order's money.
               || new.customer_name || ' : ' || money_text(new.total, new.currency) || '.',
               jsonb_build_object('to', 'courier', 'order_id', new.id, 'shop', o.name,
                                  'name', new.customer_name, 'amount', new.total,
                                  'currency', new.currency)
          from orgs o where o.id = new.org_id;
    end if;
    return new;
exception when others then
    return new;
end;
$$;


-- wave_settle: 099_association_fixes.sql's, but the order's amount's words.
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
                -- 140: in the payment's money.
                'Commande payée par Wave : ' || money_text(v.amount, v.currency)
                || '. L''argent part sur votre numéro Wave.',
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


-- trg_notify_debt_settled: 099_association_fixes.sql's, but the amount's
-- words (and its money, which it never said).
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
            -- 140: the amount with its money (it said « 15000 », no money).
            format('Crédit soldé : %s a fini de payer %s',
                   coalesce(v_customer, 'un client'),
                   money_text(v_debt.amount, (select default_currency from orgs
                                               where id = v_debt.org_id))),
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

-- ------------------------------------------------------------
-- 6. Totals across businesses, never one money added to another
-- ------------------------------------------------------------
-- A courier carries for any shop, Mara's console reads every business:
-- a sum over orders or sales of two moneys (francs CFA and euros) is a
-- number that means nothing. The totals below are said per money. Each
-- is a new door beside the old one (which stays, word for word, for the
-- app before 144); platform_today keeps its signature and only stops
-- adding a euro delivery's part to francs.

-- The courier's tally (067's courier_earnings), one row per period and
-- per money: « 2 400 FCFA » and « 4,10 EUR », never « 2 404 ».
create or replace function courier_earnings_by_currency()
returns table (
    period   text,
    currency text,
    courses  int,
    fees     numeric,
    km       double precision,
    share    numeric,
    net      numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_now   timestamptz := now();
    v_today date := (v_now at time zone 'Africa/Ouagadougou')::date;
begin
    perform assert_approved_courier();
    return query
    with done as (
        select coalesce(o.currency, 'XOF') as currency, o.delivery_fee, o.platform_fee,
               case when g.lat is null or o.drop_lat is null then null
                    else distance_km(g.lat, g.lng, o.drop_lat, o.drop_lng) end as km,
               (o.updated_at at time zone 'Africa/Ouagadougou')::date as day
          from orders o
          join orgs g on g.id = o.org_id
         where o.courier_id = auth.uid()
           and o.status = 'delivered'
    ),
    spans as (
        select 'today' as period, v_today as since
        union all select 'week',  v_today - ((extract(isodow from v_today)::int) - 1)
        union all select 'month', date_trunc('month', v_today)::date
    ),
    -- Every money the courier ever carried in, so each period says each
    -- (a zero today in euros beside the francs of the week).
    moneys as (
        select distinct d.currency from done d
    )
    select s.period,
           m.currency,
           count(d.day)::int,
           coalesce(sum(d.delivery_fee), 0)::numeric,
           coalesce(sum(d.km), 0)::double precision,
           coalesce(sum(d.platform_fee), 0)::numeric,
           (coalesce(sum(d.delivery_fee), 0) - coalesce(sum(d.platform_fee), 0))::numeric
      from spans s
      cross join moneys m
      left join done d on d.currency = m.currency and d.day >= s.since and d.day <= v_today
     group by s.period, s.since, m.currency
     order by s.since desc, m.currency;
end;
$$;

-- What each courier owes for a month (067's platform_delivery_settlement),
-- one row per courier and per money.
create or replace function platform_delivery_settlement_by_currency(p_month date default null)
returns table (
    courier_id uuid,
    name       text,
    phone      text,
    currency   text,
    courses    int,
    fees       numeric,
    share      numeric,
    net        numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_from date := date_trunc('month',
        coalesce(p_month, (now() at time zone 'Africa/Ouagadougou')::date))::date;
    v_to   date := (v_from + interval '1 month')::date;
begin
    if not exists (select 1 from profiles
                    where profiles.id = auth.uid() and profiles.is_platform_admin) then
        raise exception 'Only the platform reads the settlement';
    end if;
    return query
    select c.user_id,
           coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                    nullif(btrim(coalesce(p.full_name, '')), ''),
                    'Sans nom'),
           c.phone,
           coalesce(o.currency, 'XOF'),
           count(o.id)::int,
           coalesce(sum(o.delivery_fee), 0)::numeric,
           coalesce(sum(o.platform_fee), 0)::numeric,
           (coalesce(sum(o.delivery_fee), 0) - coalesce(sum(o.platform_fee), 0))::numeric
      from couriers c
      join profiles p on p.id = c.user_id
      join orders o on o.courier_id = c.user_id
                   and o.status = 'delivered'
                   and (o.updated_at at time zone 'Africa/Ouagadougou')::date >= v_from
                   and (o.updated_at at time zone 'Africa/Ouagadougou')::date <  v_to
     group by c.user_id, p.first_name, p.last_name, p.full_name, c.phone, coalesce(o.currency, 'XOF')
    having coalesce(sum(o.delivery_fee), 0) > 0
     order by 4, 7 desc, 2;
end;
$$;

-- The platform's analytics (043's platform_analytics_headline), one row
-- per money the businesses keep their books in.
create or replace function platform_analytics_by_currency(p_since timestamptz default null)
returns table (
    currency          text,
    businesses        bigint,
    active_businesses bigint,
    sale_count        bigint,
    revenue           numeric,
    margin            numeric
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles
                   where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can read platform analytics';
    end if;

    return query
    with s as (
        select sa.id, sa.org_id, sa.total, coalesce(g.default_currency, 'XOF') as currency
        from sales sa
        join orgs g on g.id = sa.org_id
        where sa.kind = 'sale'
          and not exists (select 1 from sales r where r.reverses_id = sa.id)
          and (p_since is null or sa.occurred_at >= p_since)
    ),
    lines as (
        select s.currency, sl.quantity, sl.unit_cost, sl.line_total
        from sale_lines sl
        join s on s.id = sl.sale_id
    ),
    moneys as (
        select coalesce(default_currency, 'XOF') as currency, count(*) as businesses
          from orgs where archived_at is null
         group by 1
        union
        select distinct s.currency, 0 from s
          where not exists (select 1 from orgs g where g.archived_at is null
                             and coalesce(g.default_currency, 'XOF') = s.currency)
    )
    select m.currency,
           m.businesses::bigint,
           (select count(distinct s.org_id) from s where s.currency = m.currency),
           (select count(*) from s where s.currency = m.currency),
           coalesce((select sum(s.total) from s where s.currency = m.currency), 0),
           coalesce((select sum(l.line_total) from lines l where l.currency = m.currency), 0)
               - coalesce((select sum(l.quantity * l.unit_cost) from lines l where l.currency = m.currency), 0)
      from moneys m
     order by (m.currency <> 'XOF'), m.currency;
end;
$$;

-- Each business's money, for the console's per-business rows (043's
-- platform_business_performance says no money).
create or replace function platform_business_currencies()
returns table (
    org_id   uuid,
    currency text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles
                   where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can read cross-business analytics';
    end if;
    return query
    select o.id, coalesce(o.default_currency, 'XOF') from orgs o order by o.id;
end;
$$;

-- platform_today: 072_console_today.sql's, but delivery_cut in francs CFA
-- only and the other moneys beside it.
create or replace function platform_today()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_month timestamptz := date_trunc('month', now() at time zone 'Africa/Ouagadougou')
                           at time zone 'Africa/Ouagadougou';
    v_week  timestamptz := now() - interval '7 days';
begin
    if not exists (select 1 from profiles
                    where id = auth.uid() and is_platform_admin) then
        return null;
    end if;

    return jsonb_build_object(
        'todo', jsonb_build_object(
            'applications', (select count(*) from org_applications where status = 'pending'),
            'pro_requests', (select count(*) from plan_requests where handled_at is null),
            'spots',        (select count(*) from promotions
                              where status in ('requested', 'paid_claimed')),
            'spots_paid',   (select count(*) from promotions where status = 'paid_claimed'),
            'couriers',     (select count(*) from couriers where status = 'pending'),
            'orders_stuck', (select count(*) from orders
                              where (status = 'pending' and created_at < now() - interval '2 hours')
                                 or (status in ('in_transit', 'picked_up')
                                     and updated_at < now() - interval '3 hours'))
        ),
        'money', jsonb_build_object(
            'currency', 'XOF',
            'pro',      (select coalesce(sum(amount), 0) from plan_requests
                          where handled_at >= v_month),
            'spots',    (select coalesce(sum(price), 0) from promotions
                          where status = 'approved' and not free
                            and decided_at >= v_month),
            -- 140: in francs CFA only, as 'currency' says and shops_sold
            -- already was — a euro delivery's part is not added to francs.
            'delivery_cut', (select coalesce(sum(platform_fee), 0) from orders
                              where status = 'delivered' and updated_at >= v_month
                                and currency = 'XOF'),
            'shops_sold',   (select coalesce(sum(total), 0) from orders
                              where status = 'delivered' and updated_at >= v_month
                                and currency = 'XOF'),
            -- 140: the same two in every other money, each its own sum
            -- ({"EUR": 12.5}); empty while every order is in francs CFA.
            'other', (select coalesce(jsonb_object_agg(x.currency, jsonb_build_object(
                                  'delivery_cut', x.cut, 'shops_sold', x.sold)), '{}'::jsonb)
                        from (select o.currency,
                                     coalesce(sum(o.platform_fee), 0) as cut,
                                     coalesce(sum(o.total), 0)        as sold
                                from orders o
                               where o.status = 'delivered' and o.updated_at >= v_month
                                 and o.currency is distinct from 'XOF'
                               group by o.currency) x
                       where x.currency is not null)
        ),
        'growth', jsonb_build_object(
            'businesses',     (select count(*) from orgs where archived_at is null),
            'new_month',      (select count(*) from orgs
                                where archived_at is null and created_at >= v_month),
            'windows_open',   (select count(*) from orgs
                                where storefront_enabled and archived_at is null
                                  and suspended_at is null),
            'windows_stocked', (select count(*) from orgs o
                                 where o.storefront_enabled and o.archived_at is null
                                   and o.suspended_at is null
                                   and exists (select 1 from products p
                                                where p.org_id = o.id and p.is_active
                                                  and p.is_published)),
            'orders_week',    (select count(*) from orders where created_at >= v_week),
            'orders_last_week', (select count(*) from orders
                                  where created_at >= v_week - interval '7 days'
                                    and created_at <  v_week),
            'shoppers_new',   (select count(distinct customer_id) from orders o
                                where o.created_at >= v_month
                                  and not exists (select 1 from orders e
                                                   where e.customer_id = o.customer_id
                                                     and e.created_at < v_month)),
            'windows_opened_week', (select coalesce(sum(opened), 0) from storefront_visits
                                     where product_id is null
                                       and day >= current_date - 6)
        ),
        'health', jsonb_build_object(
            'silent_30',   (select count(*) from orgs
                             where archived_at is null and suspended_at is null
                               and coalesce(last_activity_at, created_at)
                                   < now() - interval '30 days'),
            'empty_windows', (select count(*) from orgs o
                               where o.storefront_enabled and o.archived_at is null
                                 and not exists (select 1 from products p
                                                  where p.org_id = o.id and p.is_active
                                                    and p.is_published)),
            'pins_far',    (select count(*) from orgs
                             where archived_at is null and lat is not null
                               and ((default_currency = 'XOF'
                                     and not (lat between 2 and 26 and lng between -19 and 17))
                                 or (default_currency = 'XAF'
                                     and not (lat between -6 and 24 and lng between 7 and 30)))),
            'published',   (select count(*) from products p
                             join orgs o on o.id = p.org_id
                            where o.storefront_enabled and p.is_active and p.is_published),
            'no_photo',    (select count(*) from products p
                             join orgs o on o.id = p.org_id
                            where o.storefront_enabled and p.is_active and p.is_published
                              and not exists (select 1 from documents d
                                               where d.product_id = p.id))
        )
    );
end;
$$;

-- ------------------------------------------------------------
-- 7. Grants
-- ------------------------------------------------------------
-- The four helpers are SECURITY INVOKER and touch no table; the definers
-- that call them (delivery_fee, the bells) run them as their owner. The
-- bells' functions keep the grants they had (create or replace keeps
-- them; said again so a re-run is the same): place_order the signed-in's,
-- wave_settle the Worker's (service_role), the rest nobody's.
revoke execute on function currency_decimals(text)                         from public;
revoke execute on function amount_text(numeric, text)                      from public;
revoke execute on function currency_symbol(text)                           from public;
revoke execute on function money_text(numeric, text)                       from public;
revoke execute on function place_order(text, jsonb, text, text, text, text, text, double precision, double precision) from public;
revoke execute on function tell_couriers(uuid, boolean)                    from public;
revoke execute on function trg_notify_courier_cash()                       from public;
revoke execute on function wave_settle(uuid, text, boolean, text)          from public;
revoke execute on function trg_notify_debt_settled()                       from public;
revoke execute on function courier_earnings_by_currency()                          from public;
revoke execute on function platform_delivery_settlement_by_currency(date)          from public;
revoke execute on function platform_analytics_by_currency(timestamptz)             from public;
revoke execute on function platform_business_currencies()                          from public;
revoke execute on function platform_today()                                        from public;
revoke execute on function storefront_currencies(text[])                   from public;
revoke execute on function delivery_fee(uuid, double precision, double precision) from public;
revoke execute on function trg_vitrine_news()                              from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function currency_decimals(text)                 from anon;
        revoke execute on function amount_text(numeric, text)              from anon;
        revoke execute on function delivery_fee(uuid, double precision, double precision) from anon;
        revoke execute on function trg_vitrine_news()                      from anon;
        revoke execute on function currency_symbol(text)                   from anon;
        revoke execute on function money_text(numeric, text)               from anon;
        revoke execute on function place_order(text, jsonb, text, text, text, text, text, double precision, double precision) from anon;
        revoke execute on function tell_couriers(uuid, boolean)            from anon;
        revoke execute on function trg_notify_courier_cash()               from anon;
        revoke execute on function wave_settle(uuid, text, boolean, text)  from anon;
        revoke execute on function trg_notify_debt_settled()               from anon;
        revoke execute on function courier_earnings_by_currency()                  from anon;
        revoke execute on function platform_delivery_settlement_by_currency(date)  from anon;
        revoke execute on function platform_analytics_by_currency(timestamptz)     from anon;
        revoke execute on function platform_business_currencies()                  from anon;
        revoke execute on function platform_today()                                from anon;
        -- The signed-out street reads each card's money.
        grant execute on function storefront_currencies(text[])            to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function currency_decimals(text)                 from authenticated;
        revoke execute on function amount_text(numeric, text)              from authenticated;
        revoke execute on function trg_vitrine_news()                      from authenticated;
        revoke execute on function currency_symbol(text)                   from authenticated;
        revoke execute on function money_text(numeric, text)               from authenticated;
        revoke execute on function tell_couriers(uuid, boolean)            from authenticated;
        revoke execute on function trg_notify_courier_cash()               from authenticated;
        revoke execute on function wave_settle(uuid, text, boolean, text)  from authenticated;
        revoke execute on function trg_notify_debt_settled()               from authenticated;
        grant execute on function storefront_currencies(text[])            to authenticated;
        grant execute on function place_order(text, jsonb, text, text, text, text, text, double precision, double precision) to authenticated;
        grant execute on function courier_earnings_by_currency()                   to authenticated;
        grant execute on function platform_delivery_settlement_by_currency(date)   to authenticated;
        grant execute on function platform_analytics_by_currency(timestamptz)      to authenticated;
        grant execute on function platform_business_currencies()                   to authenticated;
        grant execute on function platform_today()                                 to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function wave_settle(uuid, text, boolean, text)   to service_role;
    end if;
end $$;

notify pgrst, 'reload schema';
