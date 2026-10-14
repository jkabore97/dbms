-- ============================================================
-- 139_spots_stores_zones.sql — « Mettre en avant » for 7 days, paid in
-- the store apps and by card on the website, at a price per zone; and
-- Mara Pro by card at the zone's own price (batch 142).
--
-- The owner decided:
--   * 7 days only. Two products: « Un article à la une, 7 jours » (the
--     smaller price) and « La boutique à la une, 7 jours » (the bigger).
--     The 30-day settings stay in platform_settings, inert; a spot asked
--     or running for 30 days before this is untouched.
--   * Pro pays too: pro_free_spots_month is 0 live, and the free path is
--     gone from request_promotion (the setting stays, inert).
--   * Each platform its own payment, and a spot is programmed only after
--     the server verified it: Google Play Billing (a one-time consumable)
--     in the Android app, Apple's In-App Purchase (a consumable) in the
--     iPhone app, Stripe Checkout (one payment, by card) on the website.
--     Wave and « J'ai payé » stay as they were, on the website only.
--   * Three price zones, typed by the owner in Réglages: XOF — the CFA
--     franc (an XAF business pays the same number, said FCFA); EUR —
--     the euro area; USD — everywhere else. The zone is the business's
--     currency (orgs.default_currency).
--
--   1. Settings: spot_price_article_7 / spot_price_shop_7 stay the XOF
--      prices, now 5 000 / 15 000 F (moved from 071's 1 000 / 2 500 only
--      if still at that seed); spot_price_{article,shop}_7_{eur,usd} and
--      pro_price_{month,year}_{eur,usd} are new, to the cent (seeded
--      14.99 / 39.99 for a spot, 4.99 / 49.99 for Pro).
--      platform_set_setting (122's) takes a decimal for those eight, two
--      at most; every other rule as before.
--   2. price_zone(currency) and zone_currency(currency): the zone, and
--      the currency it is charged in (an XAF business in XAF, the same
--      number). spot_zone_price(zone, kind) and pro_zone_price(zone,
--      period) read the settings by name.
--   3. spot_terms() (071's) keeps every key an older app reads, and adds
--      days (7), zones ({XOF: {article, shop}, EUR: …, USD: …}),
--      stripe_on and version 139 — the app's sign that the stores and
--      the card may sell a spot.
--   4. request_promotion() (131's): 7 days only (« Une mise en avant dure
--      7 jours »), no free spot for Pro, priced at the business's zone in
--      the zone's currency (before, a business in euros was asked « 1 000 »
--      in its own currency: the XOF number with the wrong unit).
--   5. spot_purchases: one row per store or card payment of a spot —
--      the channel (google, apple, stripe), the store's own id (Google's
--      purchase token, Apple's transaction id, Stripe's Checkout Session),
--      unique per channel: a payment programs exactly one spot, and the
--      same payment shown again is that spot, never a second; the amount
--      and currency paid and where they were read (the store, or the
--      app's own price when the store does not say); production or
--      sandbox; who bought it. RLS: the business's admins read their own;
--      nobody writes but spot_settle(). The business's name is kept, so
--      Mara's revenue still reads when the business is gone (org_id and
--      promotion_id let go: Mara's money outlives a business, 128 S5).
--      127's same-business guard on promotion_id.
--   6. spot_verify_begin(promotion) — as the caller, an administrator of
--      the spot's business: what the Worker may verify for whom.
--   7. spot_settle() — the Worker's alone (service role): checks the
--      product is the spot's kind and a sandbox payment is a test
--      account's (128 5c's rule, store_sandbox_allowed), then programs
--      the spot: the one asked (requested or paid_claimed) is approved
--      for 7 days — an article from next_spot_start, the whole vitrine
--      now — or, when that one is no longer waiting (already paid another
--      way, refused, cancelled), a new 7-day spot for the same place is
--      made after the one running, so a payment always buys its spot.
--      The business's admins are rung (spot_approved, with the store).
--   8. spot_stripe_begin(promotion) — as the caller: the Checkout
--      Session's amount, from the database: the zone's 7-day price in
--      the zone's currency, in Stripe's minor units (XOF and XAF are
--      zero-decimal: 1 000 F is 1000; 1,99 € is 199).
--   9. stripe_begin() (121's) — Mara Pro by card at the zone's own price
--      and currency (pro_price_month in FCFA for the XOF zone,
--      pro_price_month_eur in euros, pro_price_month_usd in dollars), no
--      longer the FCFA price converted to dollars at stripe_xof_per_usd
--      (left in place, inert). A running subscription renews at the
--      price Stripe took it at; stripe_settle is unchanged.
--  10. plan_terms() (128's): pro_zones ({XOF: {month, year}, EUR: …,
--      USD: …}); stripe_usd_month / stripe_usd_year now null — no build
--      says « ≈ $… payé en dollars » any more.
--  12. spot_refund() — the Worker's alone (service role): a payment the
--      store or Stripe took back (Google's voided purchase, Apple's
--      REFUND, Stripe's charge.refunded / charge.dispute.created) is
--      written on its spot_purchases row (refunded_at, refund_reason),
--      once, and the spot it bought ends: a running one now, one still
--      waiting its turn is cancelled.
--
--      A refund heard before its payment was settled leaves a mark
--      (outcome 'tombstone'): that payment never programs a spot.
--  13. A payment that can program nothing — the spot refused by the
--      platform or gone, the wrong product, a test payment, or (for a new
--      7-day spot after one no longer waiting) the vitrine closed, the
--      feature hidden, the article off the vitrine (spot_ineligible) — is
--      written outcome 'refused': the Worker refunds Stripe's at once;
--      Google's and Apple's wait in the platform's « Aujourd'hui »
--      (spot_refunds_todo, platform_spot_refunds,
--      platform_spot_refund_done, journaled). A spot asked for 30 days
--      before 139 keeps its 30 days when paid. spot_settle takes the
--      business the purchase names (Google) and refuses another one.
--      spot_verify_begin says « missing » for a spot gone, so that
--      payment is written too. decide_promotion (099's) locks its row.
--      platform_set_setting refuses a card price under 300 FCFA / 0,50.
--
-- Capacity: spots_max_live caps the articles « À la une » at once. A
-- payment made when the strip is full is never refused nor refunded: its
-- 7 days start when a place frees (next_spot_start, 071's queue — the
-- sheet says so before the tap). next_spot_start (071's, now VOLATILE)
-- takes one lock for that queue, so no two of the paths that program an
-- article (this settle, « Valider », Wave's settle, the weekly prize)
-- ever both take the last place.
--
-- Shop, farm and association alike: the three kinds buy the same two
-- spots (an association, holding no stock, buys the whole vitrine's),
-- at their zone's price; Mara Pro is the same for the three.
--
-- SECURITY: spot_verify_begin, spot_stripe_begin, request_promotion and
-- stripe_begin are DEFINER as before (they read the platform's settings
-- and write promotions, which no policy lets an owner write), checking
-- the caller themselves; spot_settle is DEFINER and the service role's
-- alone (taken back from authenticated by name, as 076 learned), and
-- so is spot_refund;
-- price_zone, zone_currency, spot_zone_price and pro_zone_price are
-- INVOKER helpers. Every one has its search_path pinned, none is open to
-- anon, no view.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The zone prices
-- ------------------------------------------------------------
insert into platform_settings (key, value) values
    ('spot_price_article_7_eur', '14.99'),
    ('spot_price_shop_7_eur',    '39.99'),
    ('spot_price_article_7_usd', '14.99'),
    ('spot_price_shop_7_usd',    '39.99'),
    ('pro_price_month_eur',      '4.99'),
    ('pro_price_year_eur',       '49.99'),
    ('pro_price_month_usd',      '4.99'),
    ('pro_price_year_usd',       '49.99')
on conflict (key) do nothing;

-- The owner's promotion prices (batch 142): 5 000 F an article, 15 000 F
-- the shop, 7 days. 071 seeded 1 000 / 2 500; a price still at 071's seed
-- moves, one the owner already set in Réglages stays his.
update platform_settings set value = '5000'
 where key = 'spot_price_article_7' and value #>> '{}' = '1000';
update platform_settings set value = '15000'
 where key = 'spot_price_shop_7' and value #>> '{}' = '2500';
insert into platform_settings (key, value) values
    ('spot_price_article_7', '5000'),
    ('spot_price_shop_7',    '15000')
on conflict (key) do nothing;
-- Pro pays too (the owner's decision): 0, as live — read by nothing since
-- this request_promotion, kept so an older reader finds the same answer.
update platform_settings set value = '0' where key = 'pro_free_spots_month';

-- ------------------------------------------------------------
-- 2. The zone of a business, and its prices
-- ------------------------------------------------------------
create or replace function price_zone(p_currency text)
returns text
language sql
immutable
set search_path = public
as $$
    select case
        when upper(btrim(coalesce(p_currency, ''))) in ('', 'XOF', 'XAF') then 'XOF'
        when upper(btrim(p_currency)) = 'EUR' then 'EUR'
        else 'USD' end;
$$;

-- What the zone is charged in: the business's own CFA franc (XOF, or XAF
-- at the same number), the euro, or the dollar.
create or replace function zone_currency(p_currency text)
returns text
language sql
immutable
set search_path = public
as $$
    select case price_zone(p_currency)
        when 'XOF' then case when upper(btrim(coalesce(p_currency, ''))) = 'XAF' then 'XAF' else 'XOF' end
        else price_zone(p_currency) end;
$$;

create or replace function spot_zone_price(p_zone text, p_kind text)
returns numeric
language sql
stable
set search_path = public
as $$
    select case
        when p_zone = 'EUR' and p_kind = 'shop' then spot_setting('spot_price_shop_7_eur', 39.99)
        when p_zone = 'EUR'                     then spot_setting('spot_price_article_7_eur', 14.99)
        when p_zone = 'USD' and p_kind = 'shop' then spot_setting('spot_price_shop_7_usd', 39.99)
        when p_zone = 'USD'                     then spot_setting('spot_price_article_7_usd', 14.99)
        when p_kind = 'shop'                    then spot_setting('spot_price_shop_7', 15000)
        else                                         spot_setting('spot_price_article_7', 5000) end;
$$;

create or replace function pro_zone_price(p_zone text, p_period text)
returns numeric
language sql
stable
set search_path = public
as $$
    select case
        when p_zone = 'EUR' and p_period = 'year' then spot_setting('pro_price_year_eur', 49.99)
        when p_zone = 'EUR'                       then spot_setting('pro_price_month_eur', 4.99)
        when p_zone = 'USD' and p_period = 'year' then spot_setting('pro_price_year_usd', 49.99)
        when p_zone = 'USD'                       then spot_setting('pro_price_month_usd', 4.99)
        when p_period = 'year'                    then plan_limit('pro_price_year', 25000)::numeric
        else                                           plan_limit('pro_price_month', 2500)::numeric end;
$$;

-- Stripe's minor units: the CFA francs are zero-decimal, the euro and
-- the dollar count cents.
create or replace function stripe_minor_units(p_amount numeric, p_currency text)
returns numeric
language sql
immutable
set search_path = public
as $$
    select case when upper(coalesce(p_currency, '')) in ('XOF', 'XAF')
                then round(p_amount)
                else round(p_amount * 100) end;
$$;

-- ------------------------------------------------------------
-- 3. The terms
-- ------------------------------------------------------------
create or replace function spot_terms()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'article_7',  spot_setting('spot_price_article_7', 5000),
        'article_30', spot_setting('spot_price_article_30', 3000),
        'shop_7',     spot_setting('spot_price_shop_7', 15000),
        'shop_30',    spot_setting('spot_price_shop_30', 8000),
        'max_live',   spot_setting('spots_max_live', 8),
        'wave',       (select value #>> '{}' from platform_settings where key = 'platform_wave'),
        'wave_name',  (select value #>> '{}' from platform_settings where key = 'platform_wave_name'),
        'currency',   coalesce((select value #>> '{}' from platform_settings where key = 'pro_currency'), 'XOF'),
        -- 139
        'days',       7,
        'zones',      jsonb_build_object(
                          'XOF', jsonb_build_object('article', spot_zone_price('XOF', 'article'),
                                                    'shop',    spot_zone_price('XOF', 'shop')),
                          'EUR', jsonb_build_object('article', spot_zone_price('EUR', 'article'),
                                                    'shop',    spot_zone_price('EUR', 'shop')),
                          'USD', jsonb_build_object('article', spot_zone_price('USD', 'article'),
                                                    'shop',    spot_zone_price('USD', 'shop'))),
        'stripe_on',  stripe_on(),
        'version',    139
    );
$$;

-- ------------------------------------------------------------
-- 4. Asking for a spot: 7 days, the zone's price, Pro pays too
-- ------------------------------------------------------------
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
    if v_kind = 'article' and not exists (
        select 1 from products p
         where p.id = p_product_id and p.org_id = p_org_id
           and p.is_active and p.is_published
           and coalesce(p.sale_price, 0) > 0
           and (p.quantity > 0 or not p.stock_tracked)
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

-- ------------------------------------------------------------
-- 5. The payments that programmed a spot
-- ------------------------------------------------------------
create table if not exists spot_purchases (
    id            uuid primary key default gen_random_uuid(),
    channel       text not null check (channel in ('google', 'apple', 'stripe')),
    -- Google: the purchase token. Apple: the transaction id. Stripe: the
    -- Checkout Session's id.
    external_id   text not null,
    product_id    text not null,
    promotion_id  uuid references promotions(id) on delete set null,
    org_id        uuid references orgs(id) on delete set null,
    org_name      text,
    -- Null only on a refund's mark (outcome 'tombstone').
    kind          text check (kind in ('article', 'shop')),
    amount        numeric(14, 2),
    currency      text,
    -- Where the amount was read: the store's (or Stripe's) own answer, or
    -- Mara's own zone price when the store does not say (Google Play's
    -- purchase carries none, and its order is read only with the
    -- financial-data permission). Never the app's word.
    amount_source text not null default 'store' check (amount_source in ('store', 'mara')),
    environment   text not null default 'production'
                  check (environment in ('production', 'sandbox')),
    bought_by     uuid references profiles(id) on delete set null,
    raw           jsonb,
    created_at    timestamptz not null default now(),
    -- Taken back by the store or Stripe (spot_refund): the spot then ends.
    refunded_at   timestamptz,
    refund_reason text,
    -- programmed: it bought its spot. refused: verified, but it programs
    -- nothing (the spot gone or refused, the article no longer eligible,
    -- a test payment, the wrong product) — Stripe's refunded at once, the
    -- stores' in the platform's « À faire ». tombstone: a refund heard
    -- before its payment was settled.
    outcome       text not null default 'programmed'
                  check (outcome in ('programmed', 'refused', 'tombstone')),
    unique (channel, external_id)
);
-- A database where an earlier draft of 139 made the table: the same shape.
alter table spot_purchases add column if not exists refunded_at timestamptz;
alter table spot_purchases add column if not exists refund_reason text;
alter table spot_purchases add column if not exists outcome text not null default 'programmed';
alter table spot_purchases alter column kind drop not null;
alter table spot_purchases drop constraint if exists spot_purchases_outcome_check;
alter table spot_purchases add constraint spot_purchases_outcome_check
    check (outcome in ('programmed', 'refused', 'tombstone')) not valid;
alter table spot_purchases drop constraint if exists spot_purchases_amount_source_check;
alter table spot_purchases add constraint spot_purchases_amount_source_check
    check (amount_source in ('store', 'mara')) not valid;
create index if not exists spot_purchases_org on spot_purchases (org_id);
create index if not exists spot_purchases_promotion on spot_purchases (promotion_id);

alter table spot_purchases enable row level security;
drop policy if exists "spot purchases read by the business's admins" on spot_purchases;
create policy "spot purchases read by the business's admins" on spot_purchases
    for select using (is_org_admin(org_id));
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on spot_purchases from authenticated;
        grant select on spot_purchases to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on spot_purchases from anon;
    end if;
end $$;

-- 127's guard: a payment names a spot of its own business.
drop trigger if exists same_org on spot_purchases;
create trigger same_org before insert or update on spot_purchases
for each row execute function trg_same_org('promotion_id:promotions');

-- ------------------------------------------------------------
-- 6. Who may have a store payment verified
-- ------------------------------------------------------------
create or replace function spot_verify_begin(p_promotion_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v promotions%rowtype;
begin
    if auth.uid() is null then
        raise exception 'spot_verify_begin() needs a signed-in caller';
    end if;
    select * into v from promotions where id = p_promotion_id;
    -- Gone (its business deleted): the Worker still records the payment
    -- the store verified, for the platform to refund (spot_settle's
    -- « no spot »). Nothing of anybody's is told.
    if not found then
        return jsonb_build_object('promotion_id', p_promotion_id, 'missing', true,
                                  'user_id', auth.uid());
    end if;
    if not is_org_admin(v.org_id) then
        raise exception 'Mise en avant introuvable';
    end if;
    return jsonb_build_object('promotion_id', v.id, 'org_id', v.org_id, 'kind', v.kind,
                              'status', v.status, 'user_id', auth.uid());
end;
$$;

-- ------------------------------------------------------------
-- 7. A verified payment programs its spot — once
-- ------------------------------------------------------------
-- The queue of « À la une » (071's next_spot_start), now taking one lock
-- for the articles' places: every path that programs an article — this
-- settle, the platform's « Valider », Wave's settle, the weekly prize —
-- waits for the one before, so two never both take the last place
-- (spots_max_live). VOLATILE so the count it reads is taken after the
-- lock.
create or replace function next_spot_start(p_kind text)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    v_max   integer := spot_setting('spots_max_live', 8)::int;
    v_count integer;
begin
    if p_kind = 'shop' then
        return now();
    end if;
    perform pg_advisory_xact_lock(hashtext('spot_settle:queue'));
    select count(*) into v_count from promotions
     where status = 'approved' and kind = p_kind and ends_at > now();
    if v_count < v_max then
        return now();
    end if;
    return (select ends_at from promotions
             where status = 'approved' and kind = p_kind and ends_at > now()
             order by ends_at
             offset greatest(0, v_count - v_max)
             limit 1);
end;
$$;

-- What request_promotion() asks of a spot, asked again when a payment
-- must make a new one (the spot it was bought for is no longer waiting):
-- the vitrine open, « Mettre en avant » not hidden for the business, an
-- article on the vitrine with a photo, a price and stock. Null when it
-- may run, else why not.
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
        when p_product is not null and not exists (
            select 1 from products p
             where p.id = p_product and p.org_id = p_org
               and p.is_active and p.is_published
               and coalesce(p.sale_price, 0) > 0
               and (p.quantity > 0 or not p.stock_tracked)
               and exists (select 1 from documents d where d.product_id = p.id)) then 'article'
    end;
$$;

-- An earlier draft of 139 had one argument fewer.
drop function if exists spot_settle(text, text, uuid, text, numeric, text, text, uuid, jsonb, text);

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
    v_start := greatest(next_spot_start(v.kind), coalesce(v_after, now()));

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

-- The platform's « Valider » / « Refuser » (099's), the row locked: a
-- store or card payment settled at the same moment is seen, never
-- overwritten; the queue's lock is next_spot_start's.
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

-- ------------------------------------------------------------
-- 12. A payment taken back: recorded once, and its spot ends
-- ------------------------------------------------------------
-- [p_external_id] is the purchase's own id (Google's token, Apple's
-- transaction id, Stripe's Checkout Session) — or, for Stripe, the
-- PaymentIntent a refund or a dispute names. A refund that arrives before
-- its payment was settled leaves a mark (outcome 'tombstone'), which
-- spot_settle honours: that payment never programs a spot.
create or replace function spot_refund(
    p_channel     text,
    p_external_id text,
    p_reason      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_buy spot_purchases%rowtype;
    v     promotions%rowtype;
    v_end text := 'none';
begin
    if p_channel not in ('google', 'apple', 'stripe') or coalesce(btrim(p_external_id), '') = '' then
        return jsonb_build_object('ok', false, 'reason', 'channel');
    end if;
    -- The settle of the same payment, if it runs now, first.
    perform pg_advisory_xact_lock(hashtext('spot_settle:' || p_channel || ':' || p_external_id));
    select * into v_buy from spot_purchases
     where channel = p_channel
       and (external_id = p_external_id
            or (p_channel = 'stripe' and raw ->> 'payment_intent' = p_external_id))
     order by created_at
     limit 1
     for update;
    if not found then
        -- Not settled (yet): its mark, so it never will be. A payment that
        -- is not a spot's (Mara Pro's) leaves a mark nothing ever reads.
        insert into spot_purchases (channel, external_id, product_id, kind, environment,
                                    raw, outcome, refunded_at, refund_reason)
        values (p_channel, p_external_id, '', null, 'production',
                jsonb_build_object('tombstone', true), 'tombstone', now(),
                left(coalesce(p_reason, 'refund'), 200))
        on conflict (channel, external_id) do nothing;
        return jsonb_build_object('ok', true, 'already', false, 'tombstone', true, 'spot', 'none');
    end if;
    if v_buy.refunded_at is not null then
        return jsonb_build_object('ok', true, 'already', true, 'promotion_id', v_buy.promotion_id);
    end if;
    update spot_purchases
       set refunded_at = now(), refund_reason = left(coalesce(p_reason, 'refund'), 200)
     where id = v_buy.id;

    if v_buy.outcome = 'programmed' then
        select * into v from promotions where id = v_buy.promotion_id for update;
        if found and v.status = 'approved' and v.ends_at > now() then
            if v.starts_at > now() then
                -- Still waiting its turn: never shown.
                update promotions set status = 'cancelled', note = 'Paiement remboursé'
                 where id = v.id;
                v_end := 'cancelled';
            else
                update promotions set ends_at = now(), note = 'Paiement remboursé'
                 where id = v.id;
                v_end := 'ended';
            end if;
        end if;
        begin
            perform notify_platform_spot('spot_paid',
                coalesce(v_buy.org_name, '?') || ' : mise en avant remboursée ('
                || case p_channel when 'google' then 'Google Play' when 'apple' then 'App Store'
                                  else 'carte' end || ').');
        exception when others then null;
        end;
    end if;
    return jsonb_build_object('ok', true, 'already', false, 'promotion_id', v_buy.promotion_id,
                              'spot', v_end);
end;
$$;

-- ------------------------------------------------------------
-- 13. The platform's « À faire »: store payments refused for good, to
--     refund by hand (Google and Apple refund only from their consoles)
-- ------------------------------------------------------------
create or replace function spot_refunds_todo()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return null;
    end if;
    return jsonb_build_object('spot_refunds',
        (select count(*) from spot_purchases
          where outcome = 'refused' and refunded_at is null and environment = 'production'
            and channel in ('google', 'apple')));
end;
$$;

create or replace function platform_spot_refunds()
returns table (id uuid, channel text, external_id text, org_id uuid, org_name text, kind text,
               amount numeric, currency text, reason text, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles p where p.id = auth.uid() and p.is_platform_admin) then
        raise exception 'Réservé à la plateforme';
    end if;
    return query
    select s.id, s.channel, s.external_id, s.org_id, s.org_name, s.kind, s.amount, s.currency,
           s.raw ->> 'refused', s.created_at
      from spot_purchases s
     where s.outcome = 'refused' and s.refunded_at is null and s.environment = 'production'
       and s.channel in ('google', 'apple')
     order by s.created_at;
end;
$$;

-- Refunded in Play Console or by Apple: said done (journaled).
create or replace function platform_spot_refund_done(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v spot_purchases%rowtype;
begin
    perform platform_only();
    select * into v from spot_purchases where id = p_id and outcome = 'refused' for update;
    if not found then
        raise exception 'Paiement introuvable';
    end if;
    if v.refunded_at is not null then
        return;
    end if;
    update spot_purchases set refunded_at = now(), refund_reason = 'remboursé par la plateforme'
     where id = p_id;
    perform platform_log_action(v.org_id, 'spot_refund',
        'Paiement de mise en avant remboursé (' || v.channel || ', '
        || coalesce(v.amount::text, '?') || ' ' || coalesce(v.currency, '') || ')',
        null, null, null, null);
end;
$$;

-- ------------------------------------------------------------
-- 8. A spot by card on the website: the Checkout Session's amount
-- ------------------------------------------------------------
create or replace function spot_stripe_begin(p_promotion_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v       promotions%rowtype;
    v_org   orgs%rowtype;
    v_zone  text;
    v_cur   text;
    v_price numeric;
    v_minor numeric;
begin
    if auth.uid() is null then
        raise exception 'spot_stripe_begin() needs a signed-in caller';
    end if;
    if not stripe_on() then
        raise exception 'Le paiement par carte n''est pas encore ouvert';
    end if;
    select * into v from promotions where id = p_promotion_id for update;
    if not found or not is_org_admin(v.org_id) then
        raise exception 'Mise en avant introuvable';
    end if;
    if v.status not in ('requested', 'paid_claimed') then
        raise exception 'Cette mise en avant n''attend pas de paiement';
    end if;
    select * into v_org from orgs where id = v.org_id;
    v_zone := price_zone(v_org.default_currency);
    v_cur := zone_currency(v_org.default_currency);
    if v.days = 7 then
        v_price := spot_zone_price(v_zone, v.kind);
        -- What is asked now is what the spot says it costs.
        update promotions set price = v_price, currency = v_cur where id = v.id;
    elsif v_zone = 'XOF' then
        -- A 30-day spot asked before 139: its own price, in francs.
        v_price := v.price;
    else
        raise exception 'Cette ancienne demande de 30 jours ne se paie pas par carte';
    end if;
    v_minor := stripe_minor_units(v_price, v_cur);
    if coalesce(v_minor, 0) <= 0 then
        raise exception 'Le prix de la mise en avant n''est pas fixé';
    end if;
    if v_cur in ('EUR', 'USD') and v_minor < 50 then
        raise exception 'Le prix est trop petit pour la carte (0,50 au moins)';
    end if;
    if v_minor > 99999999 then
        raise exception 'Le prix est trop grand pour la carte';
    end if;
    return jsonb_build_object(
        'promotion_id', v.id,
        'org_id',       v.org_id,
        'org_name',     v_org.name,
        'kind',         v.kind,
        'days',         v.days,
        'label',        case when v.kind = 'article'
                             then (select name from products where id = v.product_id) end,
        'amount',       v_minor::bigint,
        'currency',     lower(v_cur),
        'price',        v_price,
        'price_currency', v_cur,
        'email',        (select email from auth.users where id = auth.uid())
    );
end;
$$;

-- ------------------------------------------------------------
-- 9. Mara Pro by card, at the zone's own price
-- ------------------------------------------------------------
create or replace function stripe_begin(p_org_id uuid, p_period text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org    orgs%rowtype;
    v_cur    text;
    v_amount numeric;
    v_minor  numeric;
begin
    if auth.uid() is null then
        raise exception 'stripe_begin() needs a signed-in caller';
    end if;
    if not stripe_on() then
        raise exception 'Le paiement par carte n''est pas encore ouvert';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur abonne l''entreprise à Kaj Pro';
    end if;
    if p_period not in ('month', 'year') then
        raise exception 'Période inconnue : %', p_period;
    end if;
    select * into v_org from orgs where id = p_org_id;
    v_cur := zone_currency(v_org.default_currency);
    v_amount := pro_zone_price(price_zone(v_org.default_currency), p_period);
    if coalesce(v_amount, 0) <= 0 then
        raise exception 'Le prix de Kaj Pro n''est pas fixé';
    end if;
    v_minor := stripe_minor_units(v_amount, v_cur);
    if v_cur in ('EUR', 'USD') and v_minor < 50 then
        raise exception 'Le prix est trop petit pour la carte (0,50 au moins)';
    end if;
    if v_minor > 99999999 then
        raise exception 'Le prix est trop grand pour la carte';
    end if;
    return jsonb_build_object(
        'org_id',         v_org.id,
        'org_name',       v_org.name,
        'period',         p_period,
        'amount',         v_minor::bigint,
        'currency',       lower(v_cur),
        'price',          v_amount,
        'price_currency', v_cur,
        'customer_id',    (select customer_id from stripe_subscriptions where org_id = p_org_id),
        'email',          (select email from auth.users where id = auth.uid())
    );
end;
$$;

-- ------------------------------------------------------------
-- 10. The terms, with the zones' Pro prices
-- ------------------------------------------------------------
create or replace function plan_terms()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'pro_features',            coalesce(plan_setting('pro_features'), '[]'::jsonb),
        'free_max_staff',          plan_limit('free_max_staff', 1),
        'free_max_invoices_month', plan_limit('free_max_invoices_month', 20),
        'free_max_photos',         plan_limit('free_max_photos', 50),
        'free_photo_items',        plan_limit('free_photo_items', 10),
        'free_history_months',     plan_limit('free_history_months', 12),
        'pro_price_month',         plan_limit('pro_price_month', 2500),
        'pro_price_year',          plan_limit('pro_price_year', 25000),
        'pro_currency',            coalesce(plan_setting('pro_currency') #>> '{}', 'XOF'),
        'platform_wave',           coalesce(plan_setting('platform_wave') #>> '{}', ''),
        'platform_wave_name',      coalesce(plan_setting('platform_wave_name') #>> '{}', ''),
        'delivery_share_pct',      plan_limit('delivery_share_pct', 10),
        'stripe_on',               stripe_on(),
        -- 139: the card charges the zone's own price, never dollars
        -- converted from francs.
        'stripe_usd_month',        null,
        'stripe_usd_year',         null,
        'store_billing_on',        store_billing_on(),
        'pro_zones',               jsonb_build_object(
            'XOF', jsonb_build_object('month', pro_zone_price('XOF', 'month'), 'year', pro_zone_price('XOF', 'year')),
            'EUR', jsonb_build_object('month', pro_zone_price('EUR', 'month'), 'year', pro_zone_price('EUR', 'year')),
            'USD', jsonb_build_object('month', pro_zone_price('USD', 'month'), 'year', pro_zone_price('USD', 'year')))
    )
    || coalesce((
        select jsonb_build_object('kinds', jsonb_object_agg(k.kind, k.vals))
          from (select s.kind, jsonb_object_agg(s.key, s.value) as vals
                  from kind_settings s
                 where s.key in (select c.key from kind_setting_catalog() c)
                 group by s.kind) k
        having count(*) > 0), '{}'::jsonb);
$$;

-- ------------------------------------------------------------
-- 11. Réglages: 122's platform_set_setting, a euro or dollar price to
--     the cent
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
-- The doors
-- ------------------------------------------------------------
revoke execute on function price_zone(text)                       from public;
revoke execute on function zone_currency(text)                    from public;
revoke execute on function spot_zone_price(text, text)            from public;
revoke execute on function pro_zone_price(text, text)             from public;
revoke execute on function stripe_minor_units(numeric, text)      from public;
revoke execute on function spot_terms()                           from public;
revoke execute on function request_promotion(uuid, uuid, integer) from public;
revoke execute on function spot_verify_begin(uuid)                from public;
revoke execute on function spot_settle(text, text, uuid, text, numeric, text, text, uuid, jsonb, text, uuid) from public;
revoke execute on function spot_stripe_begin(uuid)                from public;
revoke execute on function spot_refund(text, text, text)          from public;
revoke execute on function spot_ineligible(uuid, uuid)            from public;
revoke execute on function next_spot_start(text)                  from public;
revoke execute on function decide_promotion(uuid, boolean)        from public;
revoke execute on function spot_refunds_todo()                    from public;
revoke execute on function platform_spot_refunds()                from public;
revoke execute on function platform_spot_refund_done(uuid)        from public;
revoke execute on function stripe_begin(uuid, text)               from public;
revoke execute on function plan_terms()                           from public;
revoke execute on function platform_set_setting(text, jsonb)      from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function price_zone(text)                       from anon;
        revoke execute on function zone_currency(text)                    from anon;
        revoke execute on function spot_zone_price(text, text)            from anon;
        revoke execute on function pro_zone_price(text, text)             from anon;
        revoke execute on function stripe_minor_units(numeric, text)      from anon;
        revoke execute on function spot_terms()                           from anon;
        revoke execute on function request_promotion(uuid, uuid, integer) from anon;
        revoke execute on function spot_verify_begin(uuid)                from anon;
        revoke execute on function spot_settle(text, text, uuid, text, numeric, text, text, uuid, jsonb, text, uuid) from anon;
        revoke execute on function spot_stripe_begin(uuid)                from anon;
        revoke execute on function spot_refund(text, text, text)          from anon;
        revoke execute on function spot_ineligible(uuid, uuid)            from anon;
        revoke execute on function next_spot_start(text)                  from anon;
        revoke execute on function decide_promotion(uuid, boolean)        from anon;
        revoke execute on function spot_refunds_todo()                    from anon;
        revoke execute on function platform_spot_refunds()                from anon;
        revoke execute on function platform_spot_refund_done(uuid)        from anon;
        revoke execute on function stripe_begin(uuid, text)               from anon;
        revoke execute on function plan_terms()                           from anon;
        revoke execute on function platform_set_setting(text, jsonb)      from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- The Worker's alone: Supabase's default privileges hand every new
        -- function to authenticated directly (076's lesson).
        revoke execute on function spot_settle(text, text, uuid, text, numeric, text, text, uuid, jsonb, text, uuid) from authenticated;
        revoke execute on function spot_refund(text, text, text)          from authenticated;
        revoke execute on function spot_ineligible(uuid, uuid)            from authenticated;
        -- The platform's: each checks is_platform_admin itself.
        grant execute on function decide_promotion(uuid, boolean)        to authenticated;
        grant execute on function spot_refunds_todo()                    to authenticated;
        grant execute on function platform_spot_refunds()                to authenticated;
        grant execute on function platform_spot_refund_done(uuid)        to authenticated;
        -- The caller's own: each checks the business's administrator.
        grant execute on function spot_terms()                           to authenticated;
        grant execute on function request_promotion(uuid, uuid, integer) to authenticated;
        grant execute on function spot_verify_begin(uuid)                to authenticated;
        grant execute on function spot_stripe_begin(uuid)                to authenticated;
        grant execute on function stripe_begin(uuid, text)               to authenticated;
        grant execute on function plan_terms()                           to authenticated;
        grant execute on function platform_set_setting(text, jsonb)      to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function spot_settle(text, text, uuid, text, numeric, text, text, uuid, jsonb, text, uuid) to service_role;
        grant execute on function spot_refund(text, text, text)          to service_role;
        grant select on spot_purchases to service_role;
    end if;
end $$;

notify pgrst, 'reload schema';
