-- ============================================================
-- 144_spots_by_area.sql — batch 148: « Mettre en avant » by area.
--
-- The owner: « A promotion is seen based on where you are. Someone in
-- Dakar can't see promotions from Ouagadougou, and in Ouagadougou they
-- can't see promotions from Abidjan. So there are spots for everyone, and
-- I get paid. » Until now one global cap (spots_max_live, 8) held for the
-- whole street, and every shopper saw every spot wherever they were.
--
-- THE AREA RULE. One new platform setting, spot_area_km (seeded 30, 5 to
-- 200 in Réglages › Rue). Two places are « in the same area » when both
-- have a pin and the great-circle distance between them (061's
-- distance_km, the haversine the directory and the delivery fee use) is
-- at most spot_area_km. A place with no pin is in nobody's area.
--
--   1. WHO SEES A SPOT. A running spot (approved, started, not ended) of a
--      business is shown to a shopper only when the business is in the
--      shopper's area:
--        * the article / service spots of « À la une » (136's
--          storefront_featured), and
--        * the vitrine spots that lead the list of vitrines and wear
--          « Sponsorisé » (110's storefront_spotlights; the app orders the
--          directory by it, the directory itself has no sponsored order).
--      The shopper's point: the one the app sends (« près de moi », new
--      optional p_lat / p_lng, two-argument doors beside the old ones);
--      else, for a signed-in shopper, the pin of a saved delivery address
--      (113's shopper_addresses: « Maison » first, then « Travail », then
--      the newest other); else none — and with no point, no spot at all:
--      the street as it is, never a spot from another city or country.
--      An older app calls the zero-argument doors: they answer the same
--      rule with no point sent (the saved pin, or nothing) — never every
--      city's spots.
--      Mara's own picks in « À la une » (054's featured_until, chosen by
--      the platform by hand, never paid) are not spots and stay as they
--      were, for everyone.
--   2. CAPACITY. Instead of 8 for the street: at most spots_max_live
--      approved, not ended spots (running or queued) of the same kind —
--      'article' (an article or a service in « À la une ») or 'shop' (the
--      whole vitrine) — among the businesses in the new spot's
--      business's area. Full, the new spot waits its turn: 071's queue,
--      counted in that area only (spot_area_queue), so a full Ouagadougou
--      never delays a Dakar spot. The vitrine spots, uncapped before
--      (next_spot_start('shop') answered now), are now capped the same
--      way, as the owner asked (« at most spots_max_live live spots of
--      the same kind »).
--      next_spot_start(kind, org) is the new door every path that
--      programs a spot calls — spot_settle (139), the platform's
--      « Valider » (decide_promotion, 139), Wave's settle (wave_settle,
--      140) and the weekly prize (cauris_week_close, 134). It still takes
--      139's one lock for the queue (spot_settle:queue) before it counts,
--      so two payments never both take an area's last place: one lock
--      for every area (areas overlap — a business between two cities is
--      in both — so no lock per area could be sound), which serializes
--      the few transactions that program a spot and changes no start
--      date. 071's next_spot_start(kind) is left as 139 wrote it: nothing
--      calls it any more (test_batch144 checks), and an older test that
--      re-runs a migration calling it still finds it.
--   3. A BUSINESS WITH NO PIN can no longer ask for a spot: there is no
--      area to show it in. request_promotion (143's) refuses it with the
--      way out — « La position de ma boutique » (de ma ferme, de mon
--      association) in its settings —, and spot_ineligible (143's) says
--      'position', so a payment that must make a new spot for it is
--      written 'refused' and refunded as 139 does for every other reason.
--      The sheet says so before any payment.
--   4. THE SHEET. spot_area_status(org, kind), the business's admins'
--      (and the platform's): whether the business has a pin, the radius,
--      the places (spots_max_live), how many are taken in its area, how
--      many are free this week, and — when none is — the date the next
--      one frees (the queue's own answer). « 3 places libres sur 8 autour
--      de vous cette semaine ».
--   5. Réglages: platform_set_setting (139's) takes spot_area_km from 5
--      to 200 km, whole.
--   6. A BUSINESS FIXES ITS OWN SPOT (the owner's addition, section 9):
--      cancel_promotion (asked, not paid), change_promotion_product (once:
--      asked, paid and waiting, or in the first 24 h of a running one —
--      the same row, its dates and price carried over), stop_promotion
--      (running, now, no refund); promotion_options says which, and the
--      items it may change to. The platform: platform_change_promotion_
--      product and platform_stop_promotion, any spot, journaled in
--      platform_actions, the business told. Each one written in
--      promotion_fixes (old and new item, when, who).
--
-- Running and queued spots stay valid: no row of promotions is touched,
-- nothing paid is cancelled. A spot already running for a business with
-- no pin keeps its row and its dates, but is shown in no area until the
-- business places itself on the map (scratchpad's check counts them).
-- Showcase vitrines (094) and the platform's own businesses had no spot
-- exemption and get none: a showcase has no pin, so it is never in an
-- area — it was never put first in the list either (the app keeps the
-- showcases last).
--
-- Shop, farm and association alike: the same two spots, the same rule.
--
-- Every function below is its latest version copied, changed only where
-- said, its signature kept (create or replace keeps its grants), but for
-- the new doors: storefront_featured(double, double) and
-- storefront_spotlights(double, double), open to anon like every door of
-- the street; next_spot_start(text, uuid) and spot_area_status(uuid,
-- text), definers; spot_in_area, spot_viewer_point and spot_area_queue,
-- invoker helpers called only from those definers, closed to anon,
-- PUBLIC and authenticated. Every search_path pinned. No view. No
-- extension. Re-runnable.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The radius
-- ------------------------------------------------------------
insert into platform_settings (key, value) values ('spot_area_km', '30')
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- 2. The helpers
-- ------------------------------------------------------------
-- Two pins in the same area: both placed, at most spot_area_km apart.
create or replace function spot_in_area(
    p_lat1 double precision, p_lng1 double precision,
    p_lat2 double precision, p_lng2 double precision
)
returns boolean
language sql
stable
set search_path = public
as $$
    select coalesce(
        p_lat1 is not null and p_lng1 is not null
        and p_lat2 is not null and p_lng2 is not null
        and distance_km(p_lat1, p_lng1, p_lat2, p_lng2)
            <= spot_setting('spot_area_km', 30)::double precision,
        false);
$$;

-- Where the shopper looking at the street is: the point sent (when it is
-- a point on Earth), else the signed-in shopper's saved delivery pin
-- (« Maison », then « Travail », then the newest), else no row.
create or replace function spot_viewer_point(p_lat double precision, p_lng double precision)
returns table (lat double precision, lng double precision)
language sql
stable
set search_path = public, auth
as $$
    select x.lat, x.lng from (
        select p_lat as lat, p_lng as lng, 0 as rank, null::timestamptz as at
         where p_lat between -90 and 90 and p_lng between -180 and 180
        union all
        select a.lat, a.lng,
               case a.kind when 'home' then 1 when 'work' then 2 else 3 end,
               a.updated_at
          from shopper_addresses a
         where auth.uid() is not null and a.user_id = auth.uid()
           and a.lat is not null and a.lng is not null
    ) x
    order by x.rank, x.at desc nulls last
    limit 1;
$$;

-- The queue of one kind in one business's area: how many places are taken
-- (approved, not ended — running or waiting their turn) among the
-- businesses in its area, the places there are, and when a new spot of
-- that kind could start (071's rule, counted in the area alone). A
-- business with no pin is in no area: nothing is taken, it starts now —
-- but request_promotion refuses to ask for it.
create or replace function spot_area_queue(p_kind text, p_org_id uuid)
returns table (taken integer, places integer, starts_at timestamptz)
language sql
stable
set search_path = public
as $$
    with b as (
        select o.lat, o.lng from orgs o where o.id = p_org_id
    ), live as (
        select pm.ends_at
          from promotions pm
          join orgs o on o.id = pm.org_id
          cross join b
         where pm.status = 'approved' and pm.kind = p_kind and pm.ends_at > now()
           and spot_in_area(b.lat, b.lng, o.lat, o.lng)
    ), n as (
        select (select count(*) from live)::int as taken,
               spot_setting('spots_max_live', 8)::int as places
    )
    select n.taken, n.places,
           case when n.taken < n.places then now()
                else (select l.ends_at from live l
                       order by l.ends_at
                       offset greatest(0, n.taken - n.places)
                       limit 1) end
      from n;
$$;

-- ------------------------------------------------------------
-- 3. The queue's door: one lock, the area's count
-- ------------------------------------------------------------
-- 139's next_spot_start, but for the business's area and for both kinds:
-- the same lock (every path that programs a spot waits for the one
-- before), then the area's queue. VOLATILE so the count is read after
-- the lock.
create or replace function next_spot_start(p_kind text, p_org_id uuid)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
    perform pg_advisory_xact_lock(hashtext('spot_settle:queue'));
    return coalesce((select q.starts_at from spot_area_queue(p_kind, p_org_id) q), now());
end;
$$;

-- ------------------------------------------------------------
-- 4. The street: a spot only in its area
-- ------------------------------------------------------------
-- 136's storefront_featured, but a spot counts only when its business is
-- in the shopper's area (Mara's own picks as before).
create or replace function storefront_featured(p_lat double precision, p_lng double precision)
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
set search_path = public, auth
as $$
    with here as (select * from spot_viewer_point(p_lat, p_lng))
    select p.id, p.name, p.sale_price, (p.is_service or p.quantity > 0 or not p.stock_tracked),
           product_cover_key(p.id),
           o.name, o.slug, o.default_currency
    from products p
    join orgs o on o.id = p.org_id
    left join here on true
    left join lateral (
        select min(pm.starts_at) as since from promotions pm
         where pm.product_id = p.id and pm.status = 'approved'
           and pm.starts_at <= now() and pm.ends_at > now()
           -- 144: in the shopper's area only.
           and spot_in_area(o.lat, o.lng, here.lat, here.lng)
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

-- The door an app before 148 calls: the same rule with no point sent —
-- the signed-in shopper's saved pin, or no spot.
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
    select * from storefront_featured(null::double precision, null::double precision);
$$;

-- 110's storefront_spotlights, but in the shopper's area only.
create or replace function storefront_spotlights(p_lat double precision, p_lng double precision)
returns table (slug text)
language sql
stable
security definer
set search_path = public, auth
as $$
    with here as (select * from spot_viewer_point(p_lat, p_lng))
    select distinct o.slug
    from promotions pm
    join orgs o on o.id = pm.org_id
    cross join here
    where pm.kind = 'shop' and pm.status = 'approved'
      and pm.starts_at <= now() and pm.ends_at > now()
      and o.id = storefront_open(o.slug)
      and not feature_hidden(o.id, 'spots')
      -- 144: in the shopper's area only.
      and spot_in_area(o.lat, o.lng, here.lat, here.lng);
$$;

create or replace function storefront_spotlights()
returns table (slug text)
language sql
stable
security definer
set search_path = public
as $$
    select * from storefront_spotlights(null::double precision, null::double precision);
$$;

-- ------------------------------------------------------------
-- 5. The sheet: the places free around the business this week
-- ------------------------------------------------------------
create or replace function spot_area_status(p_org_id uuid, p_kind text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_kind  text := case when p_kind = 'shop' then 'shop' else 'article' end;
    v_org   orgs%rowtype;
    v_q     record;
begin
    if auth.uid() is null then
        raise exception 'spot_area_status() needs a signed-in caller';
    end if;
    if not (is_org_admin(p_org_id)
            or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)) then
        raise exception 'Seul un administrateur met la boutique en avant';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if not found then
        raise exception 'Entreprise introuvable';
    end if;
    if v_org.lat is null or v_org.lng is null then
        return jsonb_build_object(
            'positioned', false,
            'kind',       v_kind,
            'area_km',    spot_setting('spot_area_km', 30),
            'places',     spot_setting('spots_max_live', 8)::int);
    end if;
    select * into v_q from spot_area_queue(v_kind, p_org_id);
    return jsonb_build_object(
        'positioned', true,
        'kind',       v_kind,
        'area_km',    spot_setting('spot_area_km', 30),
        'places',     v_q.places,
        'taken',      v_q.taken,
        'free',       greatest(0, v_q.places - v_q.taken),
        -- Full: when the next place frees (the queue's own date).
        'next_at',    case when v_q.taken >= v_q.places then v_q.starts_at end);
end;
$$;

-- ------------------------------------------------------------
-- 6. Asking: a business placed on the map
-- ------------------------------------------------------------
-- 143's request_promotion, but a business with no pin is refused, with
-- where to place it.
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
    v_id      uuid;
begin
    if auth.uid() is null then
        raise exception 'request_promotion() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur met la boutique en avant';
    end if;
    perform feature_guard(p_org_id, 'spots');
    -- Two taps at once ask once: the second waits, then sees the first.
    perform pg_advisory_xact_lock(hashtext('request_promotion:' || p_org_id::text));
    if p_days is distinct from 7 then
        raise exception 'Une mise en avant dure 7 jours';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if not v_org.storefront_enabled then
        raise exception 'Ouvrez d''abord la vitrine';
    end if;
    -- 144: a spot is shown around the business — it needs its pin.
    if v_org.lat is null or v_org.lng is null then
        raise exception '%', case
            when v_org.profile::text in ('association', 'church')
                then 'Placez d''abord votre association sur la carte (« La position de mon association », dans les réglages) : une mise en avant se montre autour d''elle.'
            when v_org.profile::text = 'farm'
                then 'Placez d''abord votre ferme sur la carte (« La position de ma ferme », dans les réglages) : une mise en avant se montre autour d''elle.'
            else 'Placez d''abord votre boutique sur la carte (« La position de ma boutique », dans les réglages) : une mise en avant se montre autour d''elle.' end;
    end if;
    if v_kind = 'article' and not exists (
        select 1 from products p
         where p.id = p_product_id and p.org_id = p_org_id
           and p.is_active and p.is_published
           and coalesce(p.sale_price, 0) > 0
           and (p.is_service or p.quantity > 0 or not p.stock_tracked)
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

    insert into promotions (org_id, product_id, kind, days, price, currency, requested_by)
    values (p_org_id, p_product_id, v_kind, 7,
            spot_zone_price(price_zone(v_org.default_currency), v_kind),
            zone_currency(v_org.default_currency), auth.uid())
    returning id into v_id;
    perform notify_platform_spot('spot_requested',
        v_org.name || ' demande une mise en avant (7 jours).');
    return v_id;
end;
$$;

-- 143's spot_ineligible, and 'position' for a business with no pin.
create or replace function spot_ineligible(p_org uuid, p_product uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select case
        when not coalesce((select storefront_enabled from orgs where id = p_org), false) then 'vitrine'
        when feature_hidden(p_org, 'spots') then 'feature'
        -- 144: no pin, no area to be shown in.
        when not coalesce((select lat is not null and lng is not null from orgs where id = p_org), false)
            then 'position'
        when p_product is not null and not exists (
            select 1 from products p
             where p.id = p_product and p.org_id = p_org
               and p.is_active and p.is_published
               and coalesce(p.sale_price, 0) > 0
               and (p.is_service or p.quantity > 0 or not p.stock_tracked)
               and exists (select 1 from documents d where d.product_id = p.id)) then 'article'
    end;
$$;

-- ------------------------------------------------------------
-- 7. Every path that programs a spot: the area's queue
-- ------------------------------------------------------------
-- 139's spot_settle, but next_spot_start(kind, org).
create or replace function spot_settle(
    p_channel       text,
    p_external_id   text,
    p_promotion_id  uuid,
    p_product_id    text,
    p_amount        numeric,
    p_currency      text,
    p_environment   text,
    p_bought_by     uuid default null,
    p_raw           jsonb default null,
    -- Kept for the Worker's call; the source is decided here (the store's
    -- amount, or Mara's price when it sends none).
    p_amount_source text default 'store',
    -- The business the purchase itself names (Google's
    -- obfuscatedAccountId), when there is one: it must be the spot's.
    p_org_id        uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_kind   text;
    v_was    spot_purchases%rowtype;
    v        promotions%rowtype;
    v_org    orgs%rowtype;
    v_start  timestamptz;
    v_after  timestamptz;
    v_id     uuid;
    v_days   integer;
    v_why    text;
    v_amount numeric := p_amount;
    v_cur    text := upper(nullif(btrim(coalesce(p_currency, '')), ''));
    v_source text := 'store';
    v_env    text := case when p_environment = 'sandbox' then 'sandbox' else 'production' end;
    v_pi     text := nullif(p_raw ->> 'payment_intent', '');
    v_via    text := case p_channel when 'google' then 'Google Play'
                                    when 'apple'  then 'l''App Store'
                                    else 'carte' end;
begin
    if p_channel not in ('google', 'apple', 'stripe') or coalesce(btrim(p_external_id), '') = '' then
        return jsonb_build_object('ok', false, 'reason', 'channel');
    end if;
    -- The same payment, twice at once: one after the other.
    perform pg_advisory_xact_lock(hashtext('spot_settle:' || p_channel || ':' || p_external_id));

    v_kind := case
        when p_channel = 'google' and p_product_id = 'mara_spot_article_7'       then 'article'
        when p_channel = 'google' and p_product_id = 'mara_spot_shop_7'          then 'shop'
        when p_channel = 'apple'  and p_product_id = 'bf.kaj.app.spot.article7'  then 'article'
        when p_channel = 'apple'  and p_product_id = 'bf.kaj.app.spot.shop7'     then 'shop'
        when p_channel = 'stripe' and p_product_id = 'stripe:article'            then 'article'
        when p_channel = 'stripe' and p_product_id = 'stripe:shop'               then 'shop'
    end;
    if v_kind is null then
        return jsonb_build_object('ok', false, 'reason', 'product');
    end if;

    -- Taken back before it was settled (a refund or a dispute that came
    -- first left its mark, spot_refund): never programmed.
    if exists (select 1 from spot_purchases
                where channel = p_channel and refunded_at is not null
                  and (external_id = p_external_id
                       or (p_channel = 'stripe' and v_pi is not null
                           and (external_id = v_pi or raw ->> 'payment_intent' = v_pi)))) then
        return jsonb_build_object('ok', false, 'reason', 'refunded');
    end if;

    select * into v_was from spot_purchases
     where channel = p_channel and external_id = p_external_id;
    if found then
        -- Refused before: refused again, the same way.
        if v_was.outcome = 'refused' then
            return jsonb_build_object('ok', false, 'reason', coalesce(v_was.raw ->> 'refused', 'refused'),
                                      'recorded', true);
        end if;
        -- Shown again: the spot it already programmed, nothing more.
        -- (the spot it programmed is the one asked, or the 7 days made
        -- after it when the one asked was no longer waiting)
        if v_was.promotion_id is distinct from p_promotion_id
           and (v_was.raw ->> 'asked') is distinct from p_promotion_id::text then
            return jsonb_build_object('ok', false, 'reason', 'another spot');
        end if;
        select * into v from promotions where id = v_was.promotion_id;
        return jsonb_build_object('ok', true, 'granted', false, 'promotion_id', v_was.promotion_id,
                                  'org_id', v_was.org_id, 'starts_at', v.starts_at, 'ends_at', v.ends_at);
    end if;

    select * into v from promotions where id = p_promotion_id for update;
    if found then
        select * into v_org from orgs where id = v.org_id;
        -- The purchase names another business than the spot's: refused
        -- before anything is written (a forged or mixed-up purchase).
        if p_org_id is not null and p_org_id <> v.org_id then
            return jsonb_build_object('ok', false, 'reason', 'wrong_org');
        end if;
    end if;

    -- The store said nothing of the amount: Mara's own zone price for this
    -- business — never the app's word.
    if v_amount is null or v_cur is null then
        v_amount := case when v.id is null then null
                         else spot_zone_price(price_zone(v_org.default_currency), v.kind) end;
        v_cur := case when v.id is null then null else zone_currency(v_org.default_currency) end;
        v_source := 'mara';
    end if;

    -- Why this payment programs nothing, if it does not.
    v_why := case
        when v.id is null then 'no spot'
        when v.kind <> v_kind then 'product'
        -- 128 5c: a test payment counts only for Mara's own businesses and
        -- the App Review account's.
        when v_env = 'sandbox' and not store_sandbox_allowed(v.org_id) then 'sandbox'
        -- The platform said no: paying does not overturn it.
        when v.status = 'refused' then 'refused'
        when v.status not in ('requested', 'paid_claimed') then spot_ineligible(v.org_id, v.product_id)
    end;
    if v_why is not null then
        -- Written, so the money is seen: Stripe's is refunded by the Worker
        -- at once; Google's and Apple's wait in the platform's « À faire »
        -- (« Paiements de mise en avant à rembourser ») — a test payment
        -- and a wrong product never reach a real person's money there.
        insert into spot_purchases (channel, external_id, product_id, promotion_id, org_id, org_name,
                                    kind, amount, currency, amount_source, environment, bought_by,
                                    raw, outcome)
        values (p_channel, p_external_id, p_product_id, v.id, v.org_id, v_org.name, v_kind,
                v_amount, v_cur, v_source, v_env, p_bought_by,
                coalesce(p_raw, '{}'::jsonb) || jsonb_build_object('asked', p_promotion_id, 'refused', v_why),
                'refused');
        if v_why not in ('sandbox') then
            begin
                perform notify_platform_spot('spot_paid',
                    coalesce(v_org.name, 'Une entreprise') || ' : paiement de mise en avant ('
                    || case p_channel when 'google' then 'Google Play' when 'apple' then 'App Store'
                                      else 'carte' end
                    || ') refusé (' || v_why || ')'
                    || case when p_channel = 'stripe' then ', remboursé par carte.'
                            else ', à rembourser.' end);
            exception when others then null;
            end;
        end if;
        return jsonb_build_object('ok', false, 'reason', v_why, 'recorded', true);
    end if;

    -- One payment at a time takes a place in « À la une »'s queue
    -- (spots_max_live): two settled at once never both take the last one.
    perform pg_advisory_xact_lock(hashtext('spot_settle:queue'));

    -- After whatever already runs or waits for the same place.
    select max(ends_at) into v_after from promotions
     where org_id = v.org_id and status = 'approved' and ends_at > now()
       and id <> v.id
       and coalesce(product_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = coalesce(v.product_id, '00000000-0000-0000-0000-000000000000'::uuid);
    -- 144: the queue of the business's own area.
    v_start := greatest(next_spot_start(v.kind, v.org_id), coalesce(v_after, now()));

    if v.status in ('requested', 'paid_claimed') then
        -- A spot asked for 30 days before 139 keeps its 30 days: it was
        -- priced (and, by card, charged) for them.
        v_days := case when v.days = 30 then 30 else 7 end;
        update promotions
           set status = 'approved', days = v_days, starts_at = v_start,
               ends_at = v_start + make_interval(days => v_days),
               price = v_amount, currency = v_cur,
               decided_at = now(), note = 'Payé sur ' || v_via
         where id = v.id;
        v_id := v.id;
    else
        -- Already paid another way or cancelled meanwhile, still eligible:
        -- the payment buys its 7 days, after the one running.
        v_days := 7;
        insert into promotions (org_id, product_id, kind, days, price, currency, status,
                                starts_at, ends_at, requested_by, decided_at, note)
        values (v.org_id, v.product_id, v.kind, 7,
                v_amount, v_cur, 'approved',
                v_start, v_start + interval '7 days', coalesce(p_bought_by, v.requested_by),
                now(), 'Payé sur ' || v_via)
        returning id into v_id;
    end if;

    insert into spot_purchases (channel, external_id, product_id, promotion_id, org_id, org_name,
                                kind, amount, currency, amount_source, environment, bought_by, raw)
    values (p_channel, p_external_id, p_product_id, v_id, v.org_id, v_org.name, v.kind,
            v_amount, v_cur, v_source, v_env, p_bought_by,
            coalesce(p_raw, '{}'::jsonb) || jsonb_build_object('asked', p_promotion_id));

    begin
        perform notify_org_admins(v.org_id, 'spot_approved',
            'Mise en avant payée : elle commence le '
            || to_char(v_start at time zone 'Africa/Ouagadougou', 'DD/MM à HH24:MI') || '.',
            jsonb_build_object('to', 'shop', 'promotion_id', v_id, 'store', p_channel,
                               'starts_at', v_start));
    exception when others then null;
    end;
    return jsonb_build_object('ok', true, 'granted', true, 'promotion_id', v_id,
                              'org_id', v.org_id, 'starts_at', v_start,
                              'ends_at', v_start + make_interval(days => v_days));
end;
$$;

-- 139's decide_promotion, but next_spot_start(kind, org).
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
    select * into v from promotions where id = p_promotion_id for update;
    if not found or v.status not in ('requested', 'paid_claimed') then
        raise exception 'Cette demande n''est plus en attente';
    end if;
    if p_approve then
        -- 144: the queue of the business's own area.
        v_start := next_spot_start(v.kind, v.org_id);
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

-- 140's wave_settle, but a spot takes its place in its own area's queue,
-- the vitrine's too (capped by area since 144, as the article's).
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
        -- 144: the queue of the business's own area, for its kind.
        v_start := next_spot_start(
            coalesce((select pm.kind from promotions pm where pm.id = v.promotion_id), 'article'),
            v.org_id);
        update promotions
           set status = 'approved',
               starts_at = v_start,
               ends_at = v_start + make_interval(days => days),
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

-- 134's cauris_week_close, but the week's winner's vitrine takes its
-- place in its own area's queue.
create or replace function cauris_week_close(p_week_start date default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_from   timestamptz := coalesce(p_week_start::timestamp at time zone 'Africa/Ouagadougou',
                                     cauris_week_start() - interval '7 days');
    v_to     timestamptz := v_from + interval '7 days';
    v_week   date := (v_from at time zone 'Africa/Ouagadougou')::date;
    v_n      int := 0;
    r        record;
    v_pts    int;
    v_notify boolean := cauris_param('cauris_prize_notify', 0) = 1;
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
                    next_spot_start('shop', r.org_id), next_spot_start('shop', r.org_id) + interval '7 days',
                    now(), 'Premier de la semaine (cauris)');
        end if;
        if v_notify then
            begin
                perform notify_org_admins(r.org_id, 'cauris_prize',
                    '🏆 ' || r.rank || 'e de la semaine en ' || league_label(r.league)
                    || ' ! +' || v_pts || ' cauris'
                    || case when r.rank = 1 then ', et votre vitrine mise en avant 7 jours.' else '.' end,
                    jsonb_build_object('to', 'shop', 'league', r.league, 'rank', r.rank,
                                       'points', v_pts, 'spot', r.rank = 1));
            exception when others then null;
            end;
        end if;
        v_n := v_n + 1;
    end loop;
    return v_n;
end;
$$;

-- ------------------------------------------------------------
-- 8. Réglages: 139's platform_set_setting, the radius 5 to 200 km
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
-- 9. A business fixes its own spot (the owner's addition to batch 148)
-- ------------------------------------------------------------
-- What the business's admin may do with its own spot, and the platform
-- with any (Console › À la une), a shop, a farm and an association alike:
--
--   asked, not paid ('requested')   Annuler, or change the article/service
--   paid, waiting its turn          change the article/service, once, free
--   running                         change it once, in the first 24 h; or
--                                   Arrêter now — no refund (the Conditions:
--                                   a spot already shown is not refunded)
--
-- A change goes to another item of the same business that may be « à la
-- une » (143's test: on the vitrine, photographed, priced, and in stock
-- for an article — a service always), within the same kind: the whole
-- vitrine's spot has no item to change. The spot stays the same row:
-- spot_settle, spot_refund and the store purchases name it by its id
-- (spot_purchases.promotion_id), so a payment in flight still lands on
-- it and programs the new item; its dates and price carry over. The same
-- business, so the same area: its place in the area's queue is unchanged.
-- One change per spot for the business (the platform's own corrections
-- are not counted), each written in promotion_fixes with the old and new
-- item, when and by whom.
-- A cancel waits while a Wave payment for the spot is open (less than an
-- hour old): wave_settle programs only a spot still asked, and the money
-- would find none. A store or card payment that arrives after a cancel
-- buys its 7 days anyway (139's spot_settle). Refunds stay 139's path.
create table if not exists promotion_fixes (
    id            uuid primary key default gen_random_uuid(),
    promotion_id  uuid not null references promotions(id) on delete cascade,
    org_id        uuid not null references orgs(id) on delete cascade,
    action        text not null check (action in ('change', 'cancel', 'stop')),
    from_product  uuid references products(id) on delete set null,
    to_product    uuid references products(id) on delete set null,
    by_user       uuid references profiles(id) on delete set null,
    by_platform   boolean not null default false,
    created_at    timestamptz not null default now()
);
-- One change per spot by its business.
create unique index if not exists promotion_fixes_one_change
    on promotion_fixes (promotion_id) where action = 'change' and not by_platform;
create index if not exists promotion_fixes_org on promotion_fixes (org_id);
alter table promotion_fixes enable row level security;
-- No policy: written and read through the functions below alone.
-- 127's guard: the spot and both items are the row's own business's.
drop trigger if exists same_org on promotion_fixes;
create trigger same_org before insert or update on promotion_fixes
for each row execute function trg_same_org('promotion_id:promotions', 'from_product:products', 'to_product:products');
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on promotion_fixes from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on promotion_fixes from anon;
    end if;
end $$;

-- An item of the business that may be « à la une » (143's test).
create or replace function spot_item_ready(p_org uuid, p_product uuid)
returns boolean
language sql
stable
set search_path = public
as $$
    select exists (
        select 1 from products p
         where p.id = p_product and p.org_id = p_org
           and p.is_active and p.is_published
           and coalesce(p.sale_price, 0) > 0
           and (p.is_service or p.quantity > 0 or not p.stock_tracked)
           and exists (select 1 from documents d where d.product_id = p.id));
$$;

-- What may be done with a spot now, and the items it may change to: the
-- business's admins' and the platform's.
create or replace function promotion_options(p_promotion_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v          promotions%rowtype;
    v_platform boolean := exists (select 1 from profiles where id = auth.uid() and is_platform_admin);
    v_changed  boolean;
    v_running  boolean;
    v_queued   boolean;
begin
    if auth.uid() is null then
        raise exception 'promotion_options() needs a signed-in caller';
    end if;
    select * into v from promotions where id = p_promotion_id;
    if not found or not (v_platform or is_org_admin(v.org_id)) then
        raise exception 'Mise en avant introuvable';
    end if;
    v_changed := exists (select 1 from promotion_fixes f
                          where f.promotion_id = v.id and f.action = 'change' and not f.by_platform);
    v_running := v.status = 'approved' and v.starts_at <= now() and v.ends_at > now();
    v_queued  := v.status = 'approved' and v.starts_at > now();
    return jsonb_build_object(
        'id',           v.id,
        'kind',         v.kind,
        'status',       v.status,
        'changed',      v_changed,
        'can_cancel',   v.status = 'requested',
        -- The business's rules (the platform's console corrects any spot
        -- not over, and reads the items here).
        'can_change',   v.kind = 'article' and not v_changed
                        and (v.status in ('requested', 'paid_claimed') or v_queued
                             or (v_running and now() <= v.starts_at + interval '24 hours')),
        'change_until', case when v_running then v.starts_at + interval '24 hours' end,
        'can_stop',     v_running,
        'items',        case when v.kind = 'article' then coalesce((
            select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'service', p.is_service)
                             order by lower(p.name))
              from products p
             where p.org_id = v.org_id and p.id <> v.product_id
               and spot_item_ready(v.org_id, p.id)), '[]'::jsonb) else '[]'::jsonb end);
end;
$$;

-- The change itself, for the business or the platform: the same row, its
-- dates and price kept.
create or replace function promotion_change_item(p_promotion_id uuid, p_product_id uuid, p_platform boolean)
returns void
language plpgsql
set search_path = public, auth
as $$
declare
    v promotions%rowtype;
begin
    select * into v from promotions where id = p_promotion_id for update;
    if not found then
        raise exception 'Mise en avant introuvable';
    end if;
    if v.kind <> 'article' then
        raise exception 'La vitrine entière n''a pas d''article à changer';
    end if;
    if not (v.status in ('requested', 'paid_claimed') or (v.status = 'approved' and v.ends_at > now())) then
        raise exception 'Cette mise en avant est terminée';
    end if;
    if not p_platform then
        if exists (select 1 from promotion_fixes f
                    where f.promotion_id = v.id and f.action = 'change' and not f.by_platform) then
            raise exception 'L''article ou le service ne se change qu''une fois';
        end if;
        if v.status = 'approved' and v.starts_at <= now() and now() > v.starts_at + interval '24 hours' then
            raise exception 'L''article ou le service se change seulement dans les 24 h après le début';
        end if;
    end if;
    if p_product_id is not distinct from v.product_id then
        raise exception 'C''est déjà cet article ou ce service';
    end if;
    if not spot_item_ready(v.org_id, p_product_id) then
        raise exception 'Un article mis en avant doit être sur la vitrine, avec une photo, un prix et du stock';
    end if;
    if exists (select 1 from promotions
                where org_id = v.org_id and product_id = p_product_id and id <> v.id
                  and (status in ('requested', 'paid_claimed')
                       or (status = 'approved' and ends_at > now()))) then
        raise exception 'Cet emplacement est déjà demandé ou en cours';
    end if;
    update promotions set product_id = p_product_id where id = v.id;
    insert into promotion_fixes (promotion_id, org_id, action, from_product, to_product, by_user, by_platform)
    values (v.id, v.org_id, 'change', v.product_id, p_product_id, auth.uid(), p_platform);
end;
$$;

create or replace function change_promotion_product(p_promotion_id uuid, p_product_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_org uuid;
begin
    if auth.uid() is null then
        raise exception 'change_promotion_product() needs a signed-in caller';
    end if;
    select org_id into v_org from promotions where id = p_promotion_id;
    if v_org is null or not is_org_admin(v_org) then
        raise exception 'Mise en avant introuvable';
    end if;
    perform promotion_change_item(p_promotion_id, p_product_id, false);
end;
$$;

-- Asked, not paid: withdrawn.
create or replace function cancel_promotion(p_promotion_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v promotions%rowtype;
begin
    if auth.uid() is null then
        raise exception 'cancel_promotion() needs a signed-in caller';
    end if;
    select * into v from promotions where id = p_promotion_id for update;
    if not found or not is_org_admin(v.org_id) then
        raise exception 'Mise en avant introuvable';
    end if;
    if v.status = 'paid_claimed' then
        raise exception 'Paiement signalé : Mara le vérifie, la demande ne s''annule plus';
    end if;
    if v.status <> 'requested' then
        raise exception 'Seule une demande pas encore payée s''annule';
    end if;
    if exists (select 1 from wave_payments w
                where w.promotion_id = v.id and w.status in ('created', 'open')
                  and w.created_at > now() - interval '1 hour') then
        raise exception 'Un paiement Wave est en cours pour cette demande : réessayez dans une heure';
    end if;
    update promotions set status = 'cancelled', note = 'Annulée par l''entreprise' where id = v.id;
    insert into promotion_fixes (promotion_id, org_id, action, from_product, by_user)
    values (v.id, v.org_id, 'cancel', v.product_id, auth.uid());
end;
$$;

-- Running: stopped now, no refund.
create or replace function stop_promotion(p_promotion_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v promotions%rowtype;
begin
    if auth.uid() is null then
        raise exception 'stop_promotion() needs a signed-in caller';
    end if;
    select * into v from promotions where id = p_promotion_id for update;
    if not found or not is_org_admin(v.org_id) then
        raise exception 'Mise en avant introuvable';
    end if;
    if not (v.status = 'approved' and v.starts_at <= now() and v.ends_at > now()) then
        raise exception 'Seule une mise en avant en cours s''arrête';
    end if;
    update promotions set ends_at = now(), note = 'Arrêtée par l''entreprise' where id = v.id;
    insert into promotion_fixes (promotion_id, org_id, action, from_product, by_user)
    values (v.id, v.org_id, 'stop', v.product_id, auth.uid());
end;
$$;

-- The platform's hand (Console › À la une): any spot, journaled; the
-- business told in its bell.
create or replace function platform_change_promotion_product(p_promotion_id uuid, p_product_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v      promotions%rowtype;
    v_name text;
begin
    perform platform_only();
    select * into v from promotions where id = p_promotion_id;
    if not found then
        raise exception 'Mise en avant introuvable';
    end if;
    perform promotion_change_item(p_promotion_id, p_product_id, true);
    select name into v_name from products where id = p_product_id;
    begin
        perform notify_org_admins(v.org_id, 'spot_changed',
            'Mara a changé l''article de votre mise en avant : ' || coalesce(v_name, '') || '.',
            jsonb_build_object('to', 'shop', 'promotion_id', v.id, 'name', v_name));
    exception when others then null;
    end;
    return platform_log_action(v.org_id, 'spot_change',
        'Mise en avant : article changé pour « ' || coalesce(v_name, '?') || ' »',
        jsonb_build_object('promotion_id', v.id, 'product_id', v.product_id),
        jsonb_build_object('promotion_id', v.id, 'product_id', p_product_id),
        null, null);
end;
$$;

create or replace function platform_stop_promotion(p_promotion_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare v promotions%rowtype;
begin
    perform platform_only();
    select * into v from promotions where id = p_promotion_id for update;
    if not found then
        raise exception 'Mise en avant introuvable';
    end if;
    if not (v.status = 'approved' and v.ends_at > now()) then
        raise exception 'Seule une mise en avant en cours ou programmée s''arrête';
    end if;
    if v.starts_at > now() then
        -- Waiting its turn: never shown.
        update promotions set status = 'cancelled', note = 'Arrêtée par Mara' where id = v.id;
    else
        update promotions set ends_at = now(), note = 'Arrêtée par Mara' where id = v.id;
    end if;
    insert into promotion_fixes (promotion_id, org_id, action, from_product, by_user, by_platform)
    values (v.id, v.org_id, 'stop', v.product_id, auth.uid(), true);
    begin
        perform notify_org_admins(v.org_id, 'spot_stopped',
            'Mara a arrêté votre mise en avant.',
            jsonb_build_object('to', 'shop', 'promotion_id', v.id));
    exception when others then null;
    end;
    return platform_log_action(v.org_id, 'spot_stop', 'Mise en avant arrêtée',
        jsonb_build_object('promotion_id', v.id, 'status', v.status, 'ends_at', v.ends_at),
        jsonb_build_object('promotion_id', v.id, 'stopped_at', now()),
        null, null);
end;
$$;

-- ------------------------------------------------------------
-- The doors
-- ------------------------------------------------------------
revoke execute on function spot_item_ready(uuid, uuid)                       from public;
revoke execute on function promotion_change_item(uuid, uuid, boolean)        from public;
revoke execute on function promotion_options(uuid)                           from public;
revoke execute on function change_promotion_product(uuid, uuid)              from public;
revoke execute on function cancel_promotion(uuid)                            from public;
revoke execute on function stop_promotion(uuid)                              from public;
revoke execute on function platform_change_promotion_product(uuid, uuid)     from public;
revoke execute on function platform_stop_promotion(uuid)                     from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function spot_item_ready(uuid, uuid)                   from anon;
        revoke execute on function promotion_change_item(uuid, uuid, boolean)    from anon;
        revoke execute on function promotion_options(uuid)                       from anon;
        revoke execute on function change_promotion_product(uuid, uuid)          from anon;
        revoke execute on function cancel_promotion(uuid)                        from anon;
        revoke execute on function stop_promotion(uuid)                          from anon;
        revoke execute on function platform_change_promotion_product(uuid, uuid) from anon;
        revoke execute on function platform_stop_promotion(uuid)                 from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Helpers: the definers' alone.
        revoke execute on function spot_item_ready(uuid, uuid)                   from authenticated;
        revoke execute on function promotion_change_item(uuid, uuid, boolean)    from authenticated;
        -- Each checks the business's admin, or the platform.
        grant execute on function promotion_options(uuid)                       to authenticated;
        grant execute on function change_promotion_product(uuid, uuid)          to authenticated;
        grant execute on function cancel_promotion(uuid)                        to authenticated;
        grant execute on function stop_promotion(uuid)                          to authenticated;
        grant execute on function platform_change_promotion_product(uuid, uuid) to authenticated;
        grant execute on function platform_stop_promotion(uuid)                 to authenticated;
    end if;
end $$;
-- The helpers: called only from the definers above.
revoke execute on function spot_in_area(double precision, double precision, double precision, double precision) from public;
revoke execute on function spot_viewer_point(double precision, double precision) from public;
revoke execute on function spot_area_queue(text, uuid)                            from public;
revoke execute on function next_spot_start(text, uuid)                            from public;
revoke execute on function spot_area_status(uuid, text)                           from public;
revoke execute on function storefront_featured(double precision, double precision)   from public;
revoke execute on function storefront_spotlights(double precision, double precision) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function spot_in_area(double precision, double precision, double precision, double precision) from anon;
        revoke execute on function spot_viewer_point(double precision, double precision) from anon;
        revoke execute on function spot_area_queue(text, uuid)                            from anon;
        revoke execute on function next_spot_start(text, uuid)                            from anon;
        revoke execute on function spot_area_status(uuid, text)                           from anon;
        -- The street's, signed out too (the old doors as 071 opened them).
        grant execute on function storefront_featured(double precision, double precision)   to anon;
        grant execute on function storefront_spotlights(double precision, double precision) to anon;
        grant execute on function storefront_featured()                                     to anon;
        grant execute on function storefront_spotlights()                                   to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function spot_in_area(double precision, double precision, double precision, double precision) from authenticated;
        revoke execute on function spot_viewer_point(double precision, double precision) from authenticated;
        revoke execute on function spot_area_queue(text, uuid)                            from authenticated;
        -- Only the definers that program a spot call it.
        revoke execute on function next_spot_start(text, uuid)                            from authenticated;
        -- The business's admins' (and the platform's): it checks them.
        grant execute on function spot_area_status(uuid, text)                           to authenticated;
        grant execute on function storefront_featured(double precision, double precision)   to authenticated;
        grant execute on function storefront_spotlights(double precision, double precision) to authenticated;
        grant execute on function storefront_featured()                                     to authenticated;
        grant execute on function storefront_spotlights()                                   to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
