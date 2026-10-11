-- ============================================================
-- 128_store_billing.sql — Mara Pro sold in the store apps, and an account
-- that can really be deleted.
--
-- The owner: « If it does not cost anything if no subscriber I will
-- subscribe to both. » Mara Pro is sold through Apple's In-App Purchase in
-- the iPhone app and Google Play Billing in the Android app; the website
-- keeps Stripe (082) and Wave (076). « go direct »: Mara's own Worker
-- (workers/pay, /store/verify) asks Apple and Google, with no RevenueCat.
--
-- A. STORE BILLING
--
--   1. store_subscriptions: one row per store subscription — the business
--      (Pro is per business, never per person), the store, the product,
--      Apple's original transaction id or Google's purchase token (unique
--      per store: a token is one subscription, never two businesses'),
--      its state, the end of what was paid, whether it renews, production
--      or sandbox, when it was last checked with the store, and the store's
--      last answer as it came. RLS: a business's admins read their own;
--      nobody writes — no policy, no grant — but store_settle(), granted
--      to the service role alone (the Worker, after Apple or Google said
--      so). Same posture as 082's stripe_subscriptions.
--   2. store_settle(): what the store said, written down. Idempotent (a
--      notification comes twice, the app sends the same purchase again
--      after a restore). A token already written for one business is
--      refused for another — the « replayed token »: a purchase is the
--      business it was bought for (the org id travels inside it, as
--      Google's obfuscatedExternalAccountId and Apple's appAccountToken,
--      and the Worker checks that first; this is the second lock).
--   3. Pro is on when Stripe or Wave said so (orgs.plan / plan_until, as
--      since 065) OR a store subscription is active, in grace, or
--      cancelled-but-paid (Google's CANCELED: renewal off, the period
--      already paid still runs) and its paid end is still ahead. Nothing
--      is written into orgs.plan: an Apple refund (revoked) or an expiry
--      turns Pro off at once, which a plan_until « never shorter » rule
--      (082) could not do, and a Stripe or Wave Pro is untouched by a
--      store row. Two functions decide « Pro, paid » and both read the
--      store through store_pro_active():
--        * org_plan() (065, last defined in 085) — the effective plan,
--          read by my_orgs(), every gate (pro_locked, 066/085), the
--          vitrine and the console;
--        * feature_paid() (104, last defined in 110) — « a Pro tool the
--          business paid for », which reads orgs.plan raw.
--      Each redefined once, on its latest definition, with only the store
--      branch added. Every other raw reader of orgs.plan is about the
--      Stripe/Wave date itself (106's « Pro ends soon » alert on
--      plan_until, 105/111's revenue counts of dated Pro, 108's « Pro is
--      paid, keep your cauris », which a store-Pro business never reaches
--      because org_plan() says Pro and the app draws no cauris unlock) and
--      stays as it is.
--   4. store_billing_on (platform setting, false): until the owner turns it
--      on, the store apps keep today's behaviour — the iPhone app sells no
--      Pro (125), the Play app sells it by card and Wave. plan_terms()
--      carries it (last defined in 121, redefined once with only that key
--      added); the console's Réglages show it. A purchase the store
--      already took is verified whatever the switch says: a paid Pro is
--      never refused.
--   5. The Worker's doors: store_verify_begin() as the caller (admins of
--      the business only, like stripe_begin), store_due() (the daily
--      re-check of what is close to its end, service role), and
--      store_org_of() (a notification names a token or a transaction, the
--      Worker finds its business, service role).
--
-- B. ACCOUNT DELETION — further below.
-- ============================================================

insert into platform_settings (key, value) values ('store_billing_on', 'false')
on conflict (key) do nothing;

create table if not exists store_subscriptions (
    id               uuid primary key default gen_random_uuid(),
    org_id           uuid not null references orgs(id) on delete cascade,
    platform         text not null check (platform in ('apple', 'google')),
    product_id       text not null,
    -- Apple: originalTransactionId. Google: the purchase token.
    original_id      text not null,
    state            text not null check (state in
                        ('active', 'grace', 'on_hold', 'paused', 'cancelled',
                         'expired', 'revoked', 'pending')),
    expires_at       timestamptz,
    auto_renew       boolean not null default false,
    environment      text not null default 'production'
                        check (environment in ('production', 'sandbox')),
    -- Who bought it, for « this store account already pays for … ».
    bought_by        uuid references profiles(id) on delete set null,
    last_verified_at timestamptz not null default now(),
    raw              jsonb,
    created_at       timestamptz not null default now(),
    unique (platform, original_id)
);
create index if not exists store_subscriptions_org on store_subscriptions (org_id);
create index if not exists store_subscriptions_due on store_subscriptions (expires_at)
    where state not in ('expired', 'revoked');

alter table store_subscriptions enable row level security;
drop policy if exists "store subscriptions read by the business's admins" on store_subscriptions;
create policy "store subscriptions read by the business's admins" on store_subscriptions
    for select using (is_org_admin(org_id));
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on store_subscriptions from authenticated;
        grant select on store_subscriptions to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on store_subscriptions from anon;
    end if;
end $$;

-- ------------------------------------------------------------
-- The store's half of « is this business on Pro »
-- ------------------------------------------------------------
create or replace function store_pro_active(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from store_subscriptions s
         where s.org_id = p_org_id
           and s.state in ('active', 'grace', 'cancelled')
           and s.expires_at > now());
$$;

-- 085's org_plan, with the store added.
create or replace function org_plan(p_org_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select case
        when o.plan = 'pro'
         and (o.plan_until is null
              or o.plan_until >= (now() at time zone 'Africa/Ouagadougou')::date)
        then 'pro'
        -- 128: Mara Pro bought in the App Store or on Google Play.
        when store_pro_active(o.id)
        then 'pro'
        when exists (select 1 from cauris_unlocks u
                      where u.org_id = o.id and u.feature = 'pro_all' and u.until > now())
        then 'pro'
        else 'free'
    end
    from orgs o
    where o.id = p_org_id
    union all
    select 'free'
    where not exists (select 1 from orgs where id = p_org_id)
    limit 1;
$$;

-- 110's feature_paid, with the store added: a store subscription is paid.
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
                or store_pro_active(p_org)
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

create or replace function store_billing_on()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((select (value #>> '{}')::boolean
                       from platform_settings where key = 'store_billing_on'), false);
$$;

-- 121's terms, saying whether the store apps sell Pro through the store.
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
        'stripe_usd_month',        stripe_usd_cents(plan_limit('pro_price_month', 2500)),
        'stripe_usd_year',         stripe_usd_cents(plan_limit('pro_price_year', 25000)),
        'store_billing_on',        store_billing_on()
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
-- The Worker's doors
-- ------------------------------------------------------------

-- As the caller, before the Worker asks the store anything: only an
-- administrator of the business (owner, super admin, admin — or the
-- platform) has a purchase verified for it.
create or replace function store_verify_begin(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'store_verify_begin() needs a signed-in caller';
    end if;
    if p_org_id is null or not exists (select 1 from orgs where id = p_org_id
                                                          and archived_at is null) then
        raise exception 'Entreprise introuvable';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur abonne l''entreprise à Mara Pro';
    end if;
    return jsonb_build_object('org_id', p_org_id, 'user_id', auth.uid(),
                              'store_billing_on', store_billing_on());
end;
$$;

create or replace function store_settle(
    p_platform    text,
    p_org_id      uuid,
    p_product_id  text,
    p_original_id text,
    p_state       text,
    p_expires_at  timestamptz,
    p_auto_renew  boolean,
    p_environment text,
    p_raw         jsonb default null,
    p_bought_by   uuid default null,
    p_replaces    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_row   store_subscriptions%rowtype;
    v_was   boolean;
    v_now   boolean;
begin
    if p_platform not in ('apple', 'google') then
        return jsonb_build_object('ok', false, 'reason', 'unknown store');
    end if;
    if coalesce(p_original_id, '') = '' or coalesce(p_product_id, '') = '' then
        return jsonb_build_object('ok', false, 'reason', 'no purchase');
    end if;
    if not exists (select 1 from orgs where id = p_org_id) then
        return jsonb_build_object('ok', false, 'reason', 'no such business');
    end if;
    select * into v_row from store_subscriptions
     where platform = p_platform and original_id = p_original_id
       for update;
    if found and v_row.org_id <> p_org_id then
        -- A purchase is the business it was bought for.
        return jsonb_build_object('ok', false, 'reason', 'another business');
    end if;
    v_was := store_pro_active(p_org_id) or org_plan(p_org_id) = 'pro';

    insert into store_subscriptions (org_id, platform, product_id, original_id, state,
                                     expires_at, auto_renew, environment, bought_by,
                                     last_verified_at, raw)
    values (p_org_id, p_platform, p_product_id, p_original_id, p_state,
            p_expires_at, coalesce(p_auto_renew, false),
            case when p_environment = 'sandbox' then 'sandbox' else 'production' end,
            p_bought_by, now(), p_raw)
    on conflict (platform, original_id) do update set
        product_id       = excluded.product_id,
        state            = excluded.state,
        expires_at       = excluded.expires_at,
        auto_renew       = excluded.auto_renew,
        environment      = excluded.environment,
        bought_by        = coalesce(store_subscriptions.bought_by, excluded.bought_by),
        last_verified_at = now(),
        raw              = excluded.raw;

    -- Google: an upgrade or a re-subscription is a new token naming the old
    -- one (linkedPurchaseToken); the old one is over.
    if p_replaces is not null and p_replaces <> p_original_id then
        update store_subscriptions
           set state = 'expired', last_verified_at = now()
         where platform = p_platform and original_id = p_replaces and org_id = p_org_id
           and state not in ('expired', 'revoked');
    end if;

    v_now := org_plan(p_org_id) = 'pro';
    if v_now and not v_was then
        begin
            perform notify_org_admins(p_org_id, 'pro_active',
                case when p_platform = 'apple'
                     then 'Mara Pro est actif, payé sur l''App Store.'
                     else 'Mara Pro est actif, payé sur Google Play.' end);
        exception when others then null;
        end;
    end if;
    return jsonb_build_object('ok', true, 'pro', v_now, 'state', p_state,
                              'expires_at', p_expires_at);
end;
$$;

-- Whose is this purchase (a notification names only the store's id).
create or replace function store_org_of(p_platform text, p_original_id text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
    select org_id from store_subscriptions
     where platform = p_platform and original_id = p_original_id;
$$;

-- The daily re-check: every subscription still counted as running whose
-- paid end is within two days or already behind, or that nobody checked
-- for a week. org_plan() already stops at expires_at whatever happens
-- here; this is for the renewals and refunds a notification missed.
create or replace function store_due()
returns table (platform text, org_id uuid, product_id text, original_id text,
               expires_at timestamptz, environment text)
language sql
stable
security definer
set search_path = public
as $$
    select s.platform, s.org_id, s.product_id, s.original_id, s.expires_at, s.environment
      from store_subscriptions s
     where s.state not in ('expired', 'revoked')
       and (s.expires_at is null
            or s.expires_at < now() + interval '2 days'
            or s.last_verified_at < now() - interval '7 days')
     order by s.expires_at nulls first
     limit 500;
$$;

-- For the Pro page: where this business's store subscription stands, and
-- whether the caller's own store purchase already pays for another one.
create or replace function my_store_subscription(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select case when not is_org_admin(p_org_id) then null else jsonb_build_object(
        'this', (select jsonb_build_object('platform', s.platform, 'product_id', s.product_id,
                                           'state', s.state, 'expires_at', s.expires_at,
                                           'auto_renew', s.auto_renew)
                   from store_subscriptions s
                  where s.org_id = p_org_id
                  order by (s.state in ('active', 'grace', 'cancelled') and s.expires_at > now()) desc,
                           s.expires_at desc nulls last
                  limit 1),
        'elsewhere', (select jsonb_build_object('org_id', o.id, 'name', o.name,
                                                'platform', s.platform)
                        from store_subscriptions s join orgs o on o.id = s.org_id
                       where s.bought_by = auth.uid() and s.org_id <> p_org_id
                         and s.state in ('active', 'grace', 'cancelled')
                         and s.expires_at > now()
                       order by s.expires_at desc
                       limit 1)) end;
$$;

revoke execute on function store_pro_active(uuid)    from public;
revoke execute on function store_billing_on()        from public;
revoke execute on function store_verify_begin(uuid)  from public;
revoke execute on function store_settle(text, uuid, text, text, text, timestamptz, boolean, text, jsonb, uuid, text) from public;
revoke execute on function store_org_of(text, text)  from public;
revoke execute on function store_due()               from public;
revoke execute on function my_store_subscription(uuid) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function store_pro_active(uuid)    from anon;
        revoke execute on function store_billing_on()        from anon;
        revoke execute on function store_verify_begin(uuid)  from anon;
        revoke execute on function store_settle(text, uuid, text, text, text, timestamptz, boolean, text, jsonb, uuid, text) from anon;
        revoke execute on function store_org_of(text, text)  from anon;
        revoke execute on function store_due()               from anon;
        revoke execute on function my_store_subscription(uuid) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Read inside org_plan() / feature_paid() / plan_terms(), as their
        -- owner: nobody's to call.
        revoke execute on function store_pro_active(uuid)    from authenticated;
        revoke execute on function store_billing_on()        from authenticated;
        -- The Worker's alone.
        revoke execute on function store_settle(text, uuid, text, text, text, timestamptz, boolean, text, jsonb, uuid, text) from authenticated;
        revoke execute on function store_org_of(text, text)  from authenticated;
        revoke execute on function store_due()               from authenticated;
        -- The caller's own.
        grant execute on function store_verify_begin(uuid)   to authenticated;
        grant execute on function my_store_subscription(uuid) to authenticated;
        grant execute on function plan_terms()               to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function store_settle(text, uuid, text, text, text, timestamptz, boolean, text, jsonb, uuid, text) to service_role;
        grant execute on function store_org_of(text, text)   to service_role;
        grant execute on function store_due()                to service_role;
        grant select on store_subscriptions to service_role;
    end if;
end $$;

notify pgrst, 'reload schema';
