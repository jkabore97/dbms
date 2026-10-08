-- ============================================================
-- 110_vitrine_switches.sql — the vitrine's features on Mara's switchboard.
--
-- The owner: « Add vitrine features as switches too. » 104's catalog
-- grows a « Vitrine » group, each key wired end to end — the app hides it
-- where it is set up and on the public vitrine, the server refuses it at
-- its doors — and, as in 104, every switch starts at « Par défaut », which
-- is today: with no rule written every vitrine answers exactly what it
-- answered (p1_110_before.sql / p1_110_after.sql photograph it), and a
-- feature the business paid for is never hidden (feature_paid).
--
--   key             label                       kinds          Pro tool
--   online_orders   Commandes en ligne          all three      —
--   services        Services et réservations    all three      —
--   delivery        Livraison                   shops, farms   delivery
--   online_payment  Paiement en ligne           all three      online_payment
--   vitrine_plus    Vitrine Plus                all three      vitrine_plus
--   spots           Mettre en avant             all three      — (paid spot by spot)
--   for_sale        À vendre sur la vitrine     farms          —
--
-- What each does once hidden (a legacy church counts as an association):
--   * online_orders — the vitrine is a showcase: the shelf, no basket,
--     « Commandes fermées pour le moment » (storefront().style carries
--     orders_closed, only then); an order is refused by a trigger on
--     orders, whoever writes it. Orders already sent go on as before.
--   * services — the services leave the vitrine (the shelf, the search,
--     the previews, À la une, the photo gate); a booking is refused (a
--     trigger on order_lines); no new service is created (a trigger on
--     products, feature_guard). « Mes services » is not drawn and its
--     address says « Pas disponible ».
--   * delivery — the vitrine offers pickup only (org_delivers false, no
--     fee from delivery_fee, so no quote either); a delivery order is
--     refused (orders trigger); the rates and the reach cannot be changed
--     (a trigger on orgs, feature_guard; an unchanged save passes). Orders
--     already on the road are delivered as before.
--   * online_payment — Wave is not offered on the vitrine (storefront()
--     keeps wave_merchant back), an order paid by Wave and a Wave checkout
--     for an order are refused (triggers on orders and wave_payments), the
--     shop is not « ready » (wave_terms), the number that receives the
--     money cannot be changed (orgs trigger). 090's wave_allowed stays
--     Mara's per-business tick: Wave reaches the vitrine only when BOTH
--     say yes (wave_allowed, and the switch not hidden) — and, as before,
--     the tool is paid (Pro or cauris). The switch only ever closes. The
--     till's own Wave (037's handle) is not a vitrine feature: untouched.
--   * vitrine_plus — the vitrine shows the free basics only (storefront,
--     vitrine_default_style, the cover's photo gate, through
--     vitrine_plus_on), set_storefront_style writes the basics and refuses
--     the Pro part (feature_guard), no Pro door is offered for it.
--   * spots — no spot asked for, paid or read (request_promotion,
--     claim_promotion_paid, my_promotions; a Wave payment for a spot);
--     Mara's hand-set « À la une » and the directory's top leave the
--     business. A spot paid for (« J'ai payé ») or running is paid: the
--     switch waits for it to end (feature_paid).
--   * for_sale (farms) — the farm's articles leave its vitrine (its
--     services stay, under their own switch) and an order for one is
--     refused (order_lines trigger). « À vendre » stays: it is where the
--     farm keeps what it sells at the farm, too.
--
-- Not switched: « Photos des articles ». A photo is not a vitrine feature
-- alone: the vitrine's minimum and score count photographed articles
-- (092/098), Le Chemin's « photos » step pays cauris for them (097/100),
-- photo slots are bought with cauris (100: paid, so never hidden for
-- whoever bought one), the cover and the logo are photographs. Hiding them
-- cleanly would reshape all of that; left for the owner to decide.
--
-- The shopper's refusals (vitrine_refuse) are said to anyone, in French,
-- plain (P0001): the vitrine shows them as they come. The owner's doors use
-- 104's feature_guard (MA002), which answers only inside the business.
-- place_order and the booking are not touched: the tables' triggers meet
-- every writer.
--
-- Functions replaced, each from its latest definition with its one change:
-- feature_paid (104), org_delivers and delivery_fee (085), wave_terms
-- (090), storefront and vitrine_default_style (107), set_storefront_style
-- (093), storefront_products, search_products, storefront_featured,
-- storefront_previews and storefront_photo_allowed (100), storefront_stock
-- (101), storefront_spotlights, request_promotion, claim_promotion_paid and
-- my_promotions (071). Same signatures: create or replace keeps their
-- grants (the street's stay the street's).
--
-- Re-runnable (the bundle runs twice): catalog rows upserted, triggers
-- dropped and recreated, functions replaced in place.
-- ============================================================

do $$
begin
    if to_regclass('public.feature_catalog') is null
       or to_regprocedure('public.feature_hidden(uuid, text)') is null
       or to_regprocedure('public.feature_guard(uuid, text)') is null
       or to_regprocedure('public.vitrine_default_style(uuid)') is null then
        raise exception '110 needs 104 (the switchboard) and 107 (vitrine_default_style) applied first';
    end if;
end $$;

-- ------------------------------------------------------------
-- 1. The catalog: the vitrine's group
-- ------------------------------------------------------------
-- Keys are the app's own (066's Pro tools where there is one), so one key
-- means one tool everywhere. An association does not deliver (099); « À
-- vendre » is the farm's.
insert into feature_catalog (key, label, grp, kinds, pro_tool, sort) values
    ('online_orders',  'Commandes en ligne',       'Vitrine', '{retail,farm,association}', null,             110),
    ('services',       'Services et réservations', 'Vitrine', '{retail,farm,association}', null,             120),
    ('delivery',       'Livraison',                'Vitrine', '{retail,farm}',             'delivery',       130),
    ('online_payment', 'Paiement en ligne',        'Vitrine', '{retail,farm,association}', 'online_payment', 140),
    ('vitrine_plus',   'Vitrine Plus',             'Vitrine', '{retail,farm,association}', 'vitrine_plus',   150),
    ('spots',          'Mettre en avant',          'Vitrine', '{retail,farm,association}', null,             160),
    ('for_sale',       'À vendre sur la vitrine',  'Vitrine', '{farm}',                    null,             170)
on conflict (key) do update
    set label    = excluded.label,
        grp      = excluded.grp,
        kinds    = excluded.kinds,
        pro_tool = excluded.pro_tool,
        sort     = excluded.sort;

-- ------------------------------------------------------------
-- 2. The engine's vitrine words (internal)
-- ------------------------------------------------------------
-- The shopper's refusal: said to anyone (a shopper is no member, so 104's
-- feature_guard would let them through), plain French, nothing about the
-- business beyond what its vitrine already shows.
create or replace function vitrine_refuse(p_org uuid, p_key text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if p_org is not null and feature_hidden(p_org, p_key) then
        raise exception '%', case p_key
            when 'online_orders'  then 'Commandes fermées pour le moment.'
            when 'services'       then 'Les réservations sont fermées pour le moment.'
            when 'delivery'       then 'La livraison n''est pas proposée pour le moment. Choisissez le retrait.'
            when 'online_payment' then 'Paiement en espèces uniquement pour le moment.'
            when 'for_sale'       then 'Cette ferme ne vend pas ses produits en ligne pour le moment.'
            else 'Pas disponible pour le moment.'
        end;
    end if;
end;
$$;

-- Whether an article (or a service) of this business is on its vitrine,
-- as far as the switches go. No rule for either key anywhere: true, read
-- once — the street's lists ask it for every row.
create or replace function vitrine_shows(p_org uuid, p_is_service boolean)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select case
        when not exists (select 1 from feature_rules r where r.feature in ('services', 'for_sale'))
         and not exists (select 1 from feature_catalog c
                          where c.key in ('services', 'for_sale') and c.default_hidden_kinds <> '{}')
            then true
        when coalesce(p_is_service, false) then not feature_hidden(p_org, 'services')
        -- An article: only a farm's « À vendre » takes it off (a shop's and
        -- an association's kind has no such key: never hidden).
        else not feature_hidden(p_org, 'for_sale')
    end;
$$;

-- Vitrine Plus as the street draws it: on the plan (or unlocked), and not
-- hidden by the switchboard.
create or replace function vitrine_plus_on(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select org_has(p_org, 'vitrine_plus') and not feature_hidden(p_org, 'vitrine_plus');
$$;

-- ------------------------------------------------------------
-- 3. The doors: triggers, for every writer
-- ------------------------------------------------------------
-- An order: the vitrine closed, a delivery it does not offer, Wave it does
-- not take. Named to run before 081's Pro door, so a hidden tool is never
-- answered with an offer to buy it.
create or replace function trg_order_closed_switch()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    perform vitrine_refuse(new.org_id, 'online_orders');
    if new.fulfilment = 'delivery' then
        perform vitrine_refuse(new.org_id, 'delivery');
    end if;
    if new.payment_method = 'wave' then
        perform vitrine_refuse(new.org_id, 'online_payment');
    end if;
    return new;
end;
$$;

drop trigger if exists order_closed_switch on orders;
create trigger order_closed_switch
before insert on orders
for each row execute function trg_order_closed_switch();

-- A line of it: a booking (a service), or a farm's article.
create or replace function trg_order_line_closed_switch()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org uuid;
begin
    select o.org_id into v_org from orders o where o.id = new.order_id;
    if coalesce(new.is_service, false) then
        perform vitrine_refuse(v_org, 'services');
    else
        perform vitrine_refuse(v_org, 'for_sale');
    end if;
    return new;
end;
$$;

drop trigger if exists order_line_closed_switch on order_lines;
create trigger order_line_closed_switch
before insert on order_lines
for each row execute function trg_order_line_closed_switch();

-- A Wave payment: for an order (the shopper pays — said to anyone), for a
-- spot (the business pays Mara — its own door). Named to run before 081's.
create or replace function trg_wave_order_closed_switch()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if new.kind = 'order' then
        perform vitrine_refuse(new.org_id, 'online_payment');
    elsif new.kind = 'spot' then
        perform feature_guard(new.org_id, 'spots');
    end if;
    return new;
end;
$$;

drop trigger if exists wave_order_closed_switch on wave_payments;
create trigger wave_order_closed_switch
before insert on wave_payments
for each row execute function trg_wave_order_closed_switch();

-- A new service (created, or an article turned into one). Putting an
-- existing one on the vitrine is not refused — it stays off the shelf
-- while hidden, and 070's « tout mettre en vente » must not fail for it.
create or replace function trg_products_services_switch()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if coalesce(new.is_service, false)
       and (tg_op = 'INSERT' or not coalesce(old.is_service, false)) then
        perform feature_guard(new.org_id, 'services');
    end if;
    return new;
end;
$$;

drop trigger if exists products_services_switch on products;
create trigger products_services_switch
before insert or update of is_service on products
for each row execute function trg_products_services_switch();

-- The business's delivery numbers and the number Wave pays out to: a change
-- refused once hidden. The settings form sends them back with every save,
-- so only a real change knocks (an included distance never set reads 0,
-- as the form sends it).
create or replace function trg_orgs_vitrine_switch()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if old.delivery_base is distinct from new.delivery_base
       or old.delivery_per_km is distinct from new.delivery_per_km
       or old.delivery_max_km is distinct from new.delivery_max_km
       or coalesce(old.delivery_included_km, 0) is distinct from coalesce(new.delivery_included_km, 0) then
        perform feature_guard(new.id, 'delivery');
    end if;
    if old.wave_payout_number is distinct from new.wave_payout_number then
        perform feature_guard(new.id, 'online_payment');
    end if;
    return new;
end;
$$;

drop trigger if exists orgs_vitrine_switch on orgs;
create trigger orgs_vitrine_switch
before update of delivery_base, delivery_per_km, delivery_max_km, delivery_included_km,
                 wave_payout_number on orgs
for each row execute function trg_orgs_vitrine_switch();

-- ------------------------------------------------------------
-- 4. What the street is served, and the owner's doors: each function
--    rebuilt from its latest definition with its one change.
-- ------------------------------------------------------------
-- feature_paid (104): a spot paid for, or running, is paid
create or replace function feature_paid(p_org uuid, p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((
        select c.pro_tool is not null
           and (exists (select 1 from orgs o
                         where o.id = p_org and o.plan = 'pro'
                           and (o.plan_until is null
                                or o.plan_until >= (now() at time zone 'Africa/Ouagadougou')::date))
                or exists (select 1 from cauris_unlocks u
                            where u.org_id = p_org
                              and u.feature in (c.pro_tool, 'pro_all')
                              and u.until > now()
                              and u.gifted_by is null))
          from feature_catalog c where c.key = p_key), false)
        -- 110: « Mettre en avant » is paid spot by spot (071), to Mara: a
        -- spot the business said it paid for, or one running (Mara Pro's
        -- free one included — Mara Pro is paid), is never taken away.
        or (p_key = 'spots' and exists (
                select 1 from promotions pm
                 where pm.org_id = p_org
                   and (pm.status = 'paid_claimed'
                        or (pm.status = 'approved' and pm.ends_at > now()))));
$$;

-- org_delivers (085): not when « Livraison » is hidden
create or replace function org_delivers(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from orgs o
         where o.id = p_org_id
           and o.lat is not null and o.lng is not null
           and org_has(o.id, 'delivery')
           and not feature_hidden(o.id, 'delivery'));
$$;

-- delivery_fee (085): no price for a delivery the vitrine does not offer
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
    return round(v_fee / 25) * 25;
end;
$$;

-- wave_terms (090): a shop whose « Paiement en ligne » is hidden is not ready
create or replace function wave_terms(p_org_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'on', wave_on(),
        'shop_ready', p_org_id is not null and exists (
            select 1 from orgs where id = p_org_id and wave_payout_number is not null
               and wave_allowed and org_has(id, 'online_payment')
               and not feature_hidden(id, 'online_payment')),
        'card', coalesce((select (value #>> '{}')::boolean
                            from platform_settings where key = 'wave_card'), false),
        'commission_pct', coalesce((select (value #>> '{}')::numeric
                                      from platform_settings where key = 'wave_commission_pct'), 0)
    );
$$;

-- storefront (107): Vitrine Plus, Wave and « Commandes fermées » under the switches
create or replace function storefront(p_slug text)
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
    wave_merchant text,
    style         jsonb
)
language sql
stable
security definer
set search_path = public
as $$
    select o.id, o.name, o.slug, o.profile::text, o.storefront_blurb,
           o.phone, o.address, o.theme, o.default_currency, o.lat, o.lng,
           -- Wave on the vitrine (090's tick, and 110's switch: both open).
           case when o.wave_allowed and not feature_hidden(o.id, 'online_payment')
                then o.wave_merchant end,
           (case when vitrine_plus_on(o.id) then
                     o.storefront_style
                     || case when o.storefront_style ? 'schedule'
                             then jsonb_strip_nulls(jsonb_build_object('open_now',
                                      vitrine_open_now(o.storefront_style -> 'schedule')))
                             else '{}'::jsonb end
                 when cauris_param('vitrine_free_basics', 1) = 1 then
                     o.storefront_style - 'pinned' - 'hide_out_of_stock' - 'layout'
                 else '{}'::jsonb end)
           || vitrine_default_style(o.id)
           || case when o.logo_key is not null
                   then jsonb_build_object('logo_key', o.logo_key)
                   else '{}'::jsonb end
           || jsonb_build_object('delivers', org_delivers(o.id))
           || coalesce((
                select jsonb_build_object('top_week', jsonb_build_object(
                           'rank', r.rank, 'league', league_label(r.league)))
                  from cauris_week_results r
                 where r.org_id = o.id
                   and r.week_start = (cauris_week_start() - interval '7 days')::date),
              '{}'::jsonb)
           -- « Commandes en ligne » hidden (110): a showcase — the shelf, no
           -- basket. Said only then, so a vitrine no switch touches is the
           -- same answer, key for key.
           || case when feature_hidden(o.id, 'online_orders')
                   then '{"orders_closed": true}'::jsonb
                   else '{}'::jsonb end
    from orgs o
    where o.id = storefront_open(p_slug);
$$;

-- vitrine_default_style (107): the layout only on a Vitrine Plus not hidden
create or replace function vitrine_default_style(p_org uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((
        select jsonb_strip_nulls(jsonb_build_object(
                   'accent', d.v ->> 'accent',
                   'layout', nullif(d.v ->> 'layout', 'grid'),
                   'cover_key', case when d.v ->> 'cover' = 'first_photo' then (
                       select (select doc.r2_key from documents doc
                                where doc.product_id = p.id
                                  and doc_is_photo(doc.kind, doc.content_type)
                                order by coalesce(doc.captured_at, doc.created_at) desc
                                limit 1)
                         from products p
                        where p.org_id = o.id and p.is_active and p.is_published
                          and exists (select 1 from documents doc
                                       where doc.product_id = p.id
                                         and doc_is_photo(doc.kind, doc.content_type))
                        order by p.is_service, p.name
                        limit 1) end))
               - case when vitrine_plus_on(o.id) then '{}'::text[]
                      else array['layout'] end
          from orgs o
          cross join lateral (select kind_setting(o.profile::text, 'vitrine_default') as v) d
         where o.id = p_org
           and o.storefront_style = '{}'::jsonb
           and not o.showcase
           and jsonb_typeof(d.v) = 'object'
           and (vitrine_plus_on(o.id) or cauris_param('vitrine_free_basics', 1) = 1)),
        '{}'::jsonb);
$$;

-- set_storefront_style (093): the Vitrine Plus part refused once hidden
create or replace function set_storefront_style(p_org_id uuid, p_style jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_in       jsonb := coalesce(p_style, '{}'::jsonb);
    v_out      jsonb := '{}'::jsonb;
    v_old      jsonb;
    v_plus     boolean;
    v_text     text;
    v_pinned   jsonb;
    v_sched    jsonb;
    v_id       text;
    v_count    int;
begin
    if auth.uid() is null then
        raise exception 'set_storefront_style() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur peut habiller la vitrine';
    end if;
    v_plus := feature_access(p_org_id, 'vitrine_plus') = 'edit';
    -- 110: Vitrine Plus hidden by Mara's switchboard — the free basics
    -- only, and no door to Pro offered for it.
    if v_plus and feature_hidden(p_org_id, 'vitrine_plus') then
        v_plus := false;
    end if;
    if not v_plus and cauris_param('vitrine_free_basics', 1) = 0 then
        perform feature_guard(p_org_id, 'vitrine_plus');
        if pro_locked(p_org_id, 'vitrine_plus') then
            raise exception 'Kaj Pro : la vitrine personnalisée fait partie de Kaj Pro. Ouvrez Compte › Kaj Pro pour passer à la formule payante.';
        end if;
        raise exception 'La vitrine personnalisée vous est fermée. Voyez le propriétaire.';
    end if;
    if jsonb_typeof(v_in) <> 'object' then
        raise exception 'Le style de la vitrine doit être un objet';
    end if;
    select storefront_style into v_old from orgs where id = p_org_id;

    -- The basics.
    v_text := nullif(btrim(coalesce(v_in ->> 'tagline', '')), '');
    if v_text is not null then
        if char_length(v_text) > 80 then
            raise exception 'La phrase d''accroche fait 80 caractères au plus';
        end if;
        v_out := v_out || jsonb_build_object('tagline', v_text);
    end if;

    v_text := nullif(btrim(coalesce(v_in ->> 'hours', '')), '');
    if v_text is not null then
        if char_length(v_text) > 120 then
            raise exception 'Les horaires font 120 caractères au plus';
        end if;
        v_out := v_out || jsonb_build_object('hours', v_text);
    end if;

    v_sched := v_in -> 'schedule';
    if v_sched is not null and v_sched <> 'null'::jsonb then
        if jsonb_typeof(v_sched) <> 'object'
           or jsonb_typeof(v_sched -> 'days') <> 'array'
           or jsonb_array_length(v_sched -> 'days') = 0
           or coalesce(v_sched ->> 'open', '')  !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
           or coalesce(v_sched ->> 'close', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
           or v_sched ->> 'open' = v_sched ->> 'close'
           or exists (select 1 from jsonb_array_elements(v_sched -> 'days') d
                       where jsonb_typeof(d) <> 'number'
                          or d::text not in ('1','2','3','4','5','6','7'))
           or (select count(distinct d) from jsonb_array_elements(v_sched -> 'days') d)
              <> jsonb_array_length(v_sched -> 'days') then
            raise exception 'Les horaires : choisissez les jours, puis une heure d''ouverture et une de fermeture';
        end if;
        v_out := v_out || jsonb_build_object('schedule', jsonb_build_object(
            'days', (select jsonb_agg(d order by d::text::int)
                       from jsonb_array_elements(v_sched -> 'days') d),
            'open', v_sched ->> 'open',
            'close', v_sched ->> 'close'));
    end if;

    v_text := nullif(btrim(coalesce(v_in ->> 'accent', '')), '');
    if v_text is not null then
        if v_text !~ '^#[0-9A-Fa-f]{6}$' then
            raise exception 'La couleur doit s''écrire #RRGGBB';
        end if;
        if not v_plus and not upper(v_text) = any (vitrine_free_accents()) then
            perform feature_guard(p_org_id, 'vitrine_plus');
            raise exception 'Kaj Pro : les autres couleurs font partie de Kaj Pro. Choisissez l''une des six couleurs proposées.';
        end if;
        v_out := v_out || jsonb_build_object('accent', upper(v_text));
    end if;

    v_text := nullif(btrim(coalesce(v_in ->> 'cover_key', '')), '');
    if v_text is not null then
        if not exists (select 1 from documents d
                        where d.org_id = p_org_id and d.r2_key = v_text) then
            raise exception 'La photo de couverture doit être une photo de cette entreprise';
        end if;
        v_out := v_out || jsonb_build_object('cover_key', v_text);
    end if;

    -- The arrangement: written by vitrine_plus, carried over otherwise.
    if not v_plus then
        update orgs
           set storefront_style = v_out
               || jsonb_strip_nulls(jsonb_build_object(
                      'pinned', v_old -> 'pinned',
                      'hide_out_of_stock', v_old -> 'hide_out_of_stock',
                      'layout', v_old -> 'layout'))
         where id = p_org_id;
        return;
    end if;

    v_pinned := v_in -> 'pinned';
    if v_pinned is not null and jsonb_typeof(v_pinned) = 'array'
       and jsonb_array_length(v_pinned) > 0 then
        if jsonb_array_length(v_pinned) > 6 then
            raise exception 'Six articles épinglés au plus';
        end if;
        for v_id in select jsonb_array_elements_text(v_pinned) loop
            if v_id !~ '^[0-9a-fA-F-]{36}$' or not exists (
                select 1 from products p
                 where p.id = v_id::uuid and p.org_id = p_org_id) then
                raise exception 'Un article épinglé doit être un article de cette entreprise';
            end if;
        end loop;
        select count(distinct e) into v_count
          from jsonb_array_elements_text(v_pinned) e;
        if v_count <> jsonb_array_length(v_pinned) then
            raise exception 'Un article ne s''épingle qu''une fois';
        end if;
        v_out := v_out || jsonb_build_object('pinned', v_pinned);
    end if;

    if (v_in -> 'hide_out_of_stock') = 'true'::jsonb then
        v_out := v_out || '{"hide_out_of_stock": true}'::jsonb;
    end if;

    v_text := nullif(btrim(coalesce(v_in ->> 'layout', '')), '');
    if v_text is not null and v_text <> 'grid' then
        if v_text not in ('large', 'list', 'menu') then
            raise exception 'La présentation est grille, grandes photos, liste ou menu';
        end if;
        v_out := v_out || jsonb_build_object('layout', v_text);
    end if;

    update orgs set storefront_style = v_out where id = p_org_id;
end;
$$;

-- storefront_products (100): what the switches keep on the shelf
create or replace function storefront_products(p_slug text)
returns table (
    id             uuid,
    name           text,
    sale_price     numeric,
    in_stock       boolean,
    photo_key      text,
    description    text,
    unit           text,
    available_from date,
    is_service     boolean,
    price_from     boolean
)
language sql
stable
security definer
set search_path = public
as $$
    select p.id, p.name, p.sale_price,
           (p.is_service
            or p.quantity > 0
            or p.available_from > (now() at time zone 'Africa/Ouagadougou')::date),
           (select d.r2_key from documents d
             where d.product_id = p.id and doc_is_photo(d.kind, d.content_type)
             order by coalesce(d.captured_at, d.created_at) desc
             limit 1),
           nullif(btrim(p.description), ''),
           nullif(btrim(p.unit), ''),
           case when p.available_from > (now() at time zone 'Africa/Ouagadougou')::date
                then p.available_from end,
           p.is_service,
           p.price_from
    from products p
    where p.org_id = storefront_open(p_slug)
      and p.is_active
      and p.is_published
      and vitrine_shows(p.org_id, p.is_service)
    order by p.is_service, p.name;
$$;

-- storefront_stock (101): the same shelf
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
      and p.is_published
      and vitrine_shows(p.org_id, p.is_service);
$$;

-- search_products (100): the street's search, the same shelf
create or replace function search_products(
    p_query text,
    p_lat   double precision default null,
    p_lng   double precision default null
)
returns table (
    id          uuid,
    name        text,
    sale_price  numeric,
    in_stock    boolean,
    photo_key   text,
    shop_name   text,
    shop_slug   text,
    currency    text,
    shop_lat    double precision,
    shop_lng    double precision,
    distance_km double precision
)
language sql
stable
security definer
set search_path = public
as $$
    with q as (
        select fold_search_text(btrim(coalesce(p_query, ''))) as folded
    ),
    hits as (
        select p.id, p.name, p.sale_price,
               (p.is_service or p.quantity > 0) as in_stock,
               (select d.r2_key from documents d
                 where d.product_id = p.id and doc_is_photo(d.kind, d.content_type)
                 order by coalesce(d.captured_at, d.created_at) desc
                 limit 1) as photo_key,
               o.name as shop_name, o.slug as shop_slug,
               o.default_currency as currency,
               o.lat as shop_lat, o.lng as shop_lng,
               case
                   when p_lat is null or p_lng is null
                     or o.lat is null or o.lng is null then null
                   else 6371.0 * 2 * asin(sqrt(
                            power(sin(radians(o.lat - p_lat) / 2), 2)
                          + cos(radians(p_lat)) * cos(radians(o.lat))
                          * power(sin(radians(o.lng - p_lng) / 2), 2)))
               end as distance_km,
               position((select folded from q) in fold_search_text(p.name))
                   as hit_at
        from products p
        join orgs o on o.id = p.org_id
        where length((select folded from q)) >= 2
          and fold_search_text(p.name) like
              '%' || replace(replace(replace((select folded from q),
                    '\', '\\'), '%', '\%'), '_', '\_') || '%'
          and p.is_active
          and p.is_published
          and vitrine_shows(p.org_id, p.is_service)
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
    )
    select h.id, h.name, h.sale_price, h.in_stock, h.photo_key,
           h.shop_name, h.shop_slug, h.currency,
           h.shop_lat, h.shop_lng, h.distance_km
    from hits h
    order by (h.hit_at = 1) desc, h.in_stock desc,
             (h.distance_km is null), h.distance_km, h.name, h.shop_name
    limit 50;
$$;

-- storefront_featured (100): À la une, under the switches
create or replace function storefront_featured()
returns table (
    id         uuid,
    name       text,
    sale_price numeric,
    in_stock   boolean,
    photo_key  text,
    shop_name  text,
    shop_slug  text,
    currency   text
)
language sql
stable
security definer
set search_path = public
as $$
    select p.id, p.name, p.sale_price, (p.is_service or p.quantity > 0),
           (select d.r2_key from documents d
             where d.product_id = p.id and doc_is_photo(d.kind, d.content_type)
             order by coalesce(d.captured_at, d.created_at) desc
             limit 1),
           o.name, o.slug, o.default_currency
    from products p
    join orgs o on o.id = p.org_id
    left join lateral (
        select min(pm.starts_at) as since from promotions pm
         where pm.product_id = p.id and pm.status = 'approved'
           and pm.starts_at <= now() and pm.ends_at > now()
    ) spot on true
    where (spot.since is not null or p.featured_until > now())
      and p.is_active
      and p.is_published
      and vitrine_shows(p.org_id, p.is_service)
      -- « Mettre en avant » hidden: Mara's own picks go too (a spot paid
      -- for keeps the switch from hiding anything, feature_paid).
      and not feature_hidden(o.id, 'spots')
      and o.storefront_enabled
      and o.archived_at  is null
      and o.suspended_at is null
    order by (spot.since is null), spot.since, p.featured_until desc nulls last, p.name
    limit 12;
$$;

-- storefront_previews (100): the directory's cards, the same shelf
create or replace function storefront_previews(p_slugs text[])
returns table (
    slug       text,
    product_id uuid,
    name       text,
    sale_price numeric,
    photo_key  text
)
language sql
stable
security definer
set search_path = public
as $$
    select x.slug, x.id, x.name, x.sale_price, x.photo_key
    from (
        select o.slug, p.id, p.name, p.sale_price, ph.r2_key as photo_key,
               row_number() over (
                   partition by o.id
                   order by (ph.r2_key is null),
                            (not p.is_service and p.quantity <= 0), p.name
               ) as n
        from orgs o
        join products p on p.org_id = o.id
        left join lateral (
            select d.r2_key from documents d
             where d.product_id = p.id and doc_is_photo(d.kind, d.content_type)
             order by coalesce(d.captured_at, d.created_at) desc
             limit 1
        ) ph on true
        where o.slug = any (coalesce(p_slugs, '{}'))
          and o.id = storefront_open(o.slug)
          and p.is_active
          and p.is_published
          and vitrine_shows(p.org_id, p.is_service)
    ) x
    where x.n <= 3
    order by x.slug, x.n;
$$;

-- storefront_spotlights (071): the top of the directory, under « Mettre en avant »
create or replace function storefront_spotlights()
returns table (slug text)
language sql
stable
security definer
set search_path = public
as $$
    select distinct o.slug
    from promotions pm
    join orgs o on o.id = pm.org_id
    where pm.kind = 'shop' and pm.status = 'approved'
      and pm.starts_at <= now() and pm.ends_at > now()
      and o.id = storefront_open(o.slug)
      and not feature_hidden(o.id, 'spots');
$$;

-- storefront_photo_allowed (100): no picture served for what the shelf does not show
create or replace function storefront_photo_allowed(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from documents d
        join products p on p.id = d.product_id
        join orgs     o on o.id = p.org_id
        where d.r2_key = p_key
          and doc_is_photo(d.kind, d.content_type)
          and p.is_active
          and p.is_published
          and vitrine_shows(p.org_id, p.is_service)
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
    ) or exists (
        select 1
        from orgs o
        where o.storefront_style ->> 'cover_key' = p_key
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
          and (vitrine_plus_on(o.id)
               or cauris_param('vitrine_free_basics', 1) = 1)
    ) or exists (
        select 1
        from orgs o
        where o.logo_key = p_key
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
    );
$$;

-- request_promotion (071): no spot asked for once « Mettre en avant » is hidden
create or replace function request_promotion(
    p_org_id     uuid,
    p_product_id uuid,
    p_days       integer
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_kind    text := case when p_product_id is null then 'shop' else 'article' end;
    v_org     orgs%rowtype;
    v_price   numeric;
    v_free    boolean := false;
    v_id      uuid;
    v_start   timestamptz;
begin
    if auth.uid() is null then
        raise exception 'request_promotion() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur met la boutique en avant';
    end if;
    perform feature_guard(p_org_id, 'spots');
    if p_days not in (7, 30) then
        raise exception 'Une mise en avant dure 7 ou 30 jours';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if not v_org.storefront_enabled then
        raise exception 'Ouvrez d''abord la vitrine';
    end if;
    if v_kind = 'article' and not exists (
        select 1 from products p
         where p.id = p_product_id and p.org_id = p_org_id
           and p.is_active and p.is_published
           and coalesce(p.sale_price, 0) > 0 and p.quantity > 0
           and exists (select 1 from documents d where d.product_id = p.id)) then
        raise exception 'Un article mis en avant doit être sur la vitrine, avec une photo, un prix et du stock';
    end if;
    if exists (select 1 from promotions
                where org_id = p_org_id
                  and coalesce(product_id, '00000000-0000-0000-0000-000000000000'::uuid)
                    = coalesce(p_product_id, '00000000-0000-0000-0000-000000000000'::uuid)
                  and (status in ('requested', 'paid_claimed')
                       or (status = 'approved' and ends_at > now()))) then
        raise exception 'Cet emplacement est déjà demandé ou en cours';
    end if;

    v_price := spot_setting('spot_price_' || v_kind || '_' || p_days, 0);

    -- Kaj Pro's included spot: one 7-day article spot per calendar month.
    if v_kind = 'article' and p_days = 7 and org_plan(p_org_id) = 'pro'
       and (select count(*) from promotions
             where org_id = p_org_id and free
               and created_at >= date_trunc('month', now()))
           < spot_setting('pro_free_spots_month', 1) then
        v_free := true;
    end if;

    if v_free then
        v_start := next_spot_start(v_kind);
        insert into promotions (org_id, product_id, kind, days, price, currency,
                                free, status, starts_at, ends_at, requested_by,
                                decided_at)
        values (p_org_id, p_product_id, v_kind, p_days, 0,
                coalesce(v_org.default_currency, 'XOF'), true, 'approved',
                v_start, v_start + make_interval(days => p_days), auth.uid(), now())
        returning id into v_id;
    else
        insert into promotions (org_id, product_id, kind, days, price, currency,
                                requested_by)
        values (p_org_id, p_product_id, v_kind, p_days, v_price,
                coalesce(v_org.default_currency, 'XOF'), auth.uid())
        returning id into v_id;
        perform notify_platform_spot('spot_requested',
            v_org.name || ' demande une mise en avant (' || p_days || ' jours).');
    end if;
    return v_id;
end;
$$;

-- claim_promotion_paid (071): nor paid for
create or replace function claim_promotion_paid(p_promotion_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v promotions%rowtype;
begin
    select * into v from promotions where id = p_promotion_id;
    if not found or not is_org_admin(v.org_id) then
        raise exception 'Mise en avant introuvable';
    end if;
    perform feature_guard(v.org_id, 'spots');
    if v.status <> 'requested' then
        raise exception 'Cette mise en avant n''attend pas de paiement';
    end if;
    update promotions set status = 'paid_claimed',
           note = nullif(btrim(coalesce(p_note, '')), '')
     where id = p_promotion_id;
    perform notify_platform_spot('spot_paid',
        (select name from orgs where id = v.org_id)
        || ' dit avoir payé sa mise en avant.');
end;
$$;

-- my_promotions (071): nor read
create or replace function my_promotions(p_org_id uuid)
returns table (
    id uuid, kind text, product_id uuid, product_name text, days integer,
    price numeric, currency text, free boolean, status text,
    starts_at timestamptz, ends_at timestamptz, created_at timestamptz,
    seen bigint, opened bigint, added bigint, ordered bigint
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select feature_guard(p_org_id, 'spots');
    select p.id, p.kind, p.product_id, pr.name, p.days, p.price, p.currency,
           p.free, p.status, p.starts_at, p.ends_at, p.created_at,
           coalesce(r.seen, 0), coalesce(r.opened, 0),
           coalesce(r.added, 0), coalesce(r.ordered, 0)
    from promotions p
    left join products pr on pr.id = p.product_id
    left join lateral (
        select sum(v.seen) seen, sum(v.opened) opened,
               sum(v.added) added, sum(v.ordered) ordered
          from storefront_visits v
         where v.org_id = p.org_id
           and (p.product_id is null or v.product_id = p.product_id)
           and p.starts_at is not null
           and v.day >= (p.starts_at at time zone 'Africa/Ouagadougou')::date
           and v.day <= (least(p.ends_at, now()) at time zone 'Africa/Ouagadougou')::date
    ) r on true
    where p.org_id = p_org_id and is_org_member(p_org_id)
    order by p.created_at desc;
$$;

-- ------------------------------------------------------------
-- Grants: born closed (063); the new ones are internal — read by the
-- functions and triggers above, as their owner. The replaced functions
-- keep theirs (create or replace).
-- ------------------------------------------------------------
revoke execute on function vitrine_refuse(uuid, text)          from public;
revoke execute on function vitrine_shows(uuid, boolean)        from public;
revoke execute on function vitrine_plus_on(uuid)               from public;
revoke execute on function trg_order_closed_switch()           from public;
revoke execute on function trg_order_line_closed_switch()      from public;
revoke execute on function trg_wave_order_closed_switch()      from public;
revoke execute on function trg_products_services_switch()      from public;
revoke execute on function trg_orgs_vitrine_switch()           from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function vitrine_refuse(uuid, text)          from anon;
        revoke execute on function vitrine_shows(uuid, boolean)        from anon;
        revoke execute on function vitrine_plus_on(uuid)               from anon;
        revoke execute on function trg_order_closed_switch()           from anon;
        revoke execute on function trg_order_line_closed_switch()      from anon;
        revoke execute on function trg_wave_order_closed_switch()      from anon;
        revoke execute on function trg_products_services_switch()      from anon;
        revoke execute on function trg_orgs_vitrine_switch()           from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function vitrine_refuse(uuid, text)          from authenticated;
        revoke execute on function vitrine_shows(uuid, boolean)        from authenticated;
        revoke execute on function vitrine_plus_on(uuid)               from authenticated;
        revoke execute on function trg_order_closed_switch()           from authenticated;
        revoke execute on function trg_order_line_closed_switch()      from authenticated;
        revoke execute on function trg_wave_order_closed_switch()      from authenticated;
        revoke execute on function trg_products_services_switch()      from authenticated;
        revoke execute on function trg_orgs_vitrine_switch()           from authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
