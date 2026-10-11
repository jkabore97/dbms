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
--   5b. Order (review S1): every row keeps signed_at, when the store said
--      what it holds (Apple's signedDate on the JWS the Worker fetched
--      itself from the App Store Server API; for Google, the moment the
--      Worker read the purchase from the Play Developer API — a Pub/Sub
--      eventTime is only a wake-up, the content is always fetched).
--      store_settle() ignores anything older than what it already holds:
--      a notification Apple retries after a refund cannot turn Pro back
--      on.
--   5c. Sandbox purchases (review S2), decided: a sandbox (TestFlight,
--      App Review, Google licence tester) purchase counts ONLY for a
--      business owned by a platform admin or by the account named in the
--      platform setting store_review_account (default
--      review.mara@gmail.com, the account given to App Review). App
--      Review and the owner's own TestFlight work; nobody else gets a
--      free, renewable Pro from a test card. store_settle() refuses every
--      other sandbox purchase (reason 'sandbox', said in French by the
--      Worker), and store_pro_active() does not count one either, should
--      the business change hands.
--
-- B. ACCOUNT DELETION FOR REAL (« Supprimer mon compte », every account)
--
--   The owner: « if business owner ask for account deletion, Business
--   desapear and member become simple shoppers ». Until now (113) only a
--   shopper with nothing on any business's books could go; a member's
--   request went to Mara by hand. Now every account goes, from the app:
--
--   6. purge_org(): 014's delete_org body, moved out so that the
--      platform's « Supprimer » and an owner's account deletion are ONE
--      path (the leaf-first destruction, the tombstone in deleted_orgs,
--      the audit sweep). delete_org() keeps every one of its fences and
--      calls it. A bug found on the way and fixed there: the leaf list had
--      never been given the credit book, the tontines' contributions,
--      production or the delivery receipts, so a business holding any of
--      them could not be deleted at all (a foreign-key error). A business an owner's deletion takes is
--      archived first (archived_at, as 014's lifecycle always does), then
--      purged in the same transaction.
--   7. delete_my_account_plan(): what a deletion would do, read by the
--      app's confirmation (delete_my_account_preview) and by the deletion
--      itself — the businesses that disappear (those the person is the
--      only owner of: a business another owner holds stays, the person
--      just leaves it), how many members each has (they become plain
--      shoppers: their membership goes with the business), the open
--      orders that will be cancelled, the store or card subscription
--      that must be stopped; the businesses the person merely leaves; and
--      what refuses it:
--        * a platform account (as in 113);
--        * the person's own open order as a customer (113);
--        * a delivery the person is carrying (in transit);
--        * one of the doomed businesses' orders in transit (goods on the
--          road, a courier paid on delivery) or paid online and not yet
--          handed over (money Mara cannot give back by itself): the owner
--          finishes or refunds it first;
--        * a Wave payout Mara still owes one of them (pending or failed).
--      Each refusal has a code (blocked_code) the app translates. Every
--      other open order (pending, accepted, ready — nothing paid, nothing
--      moving) is cancelled, each customer told on their own bell (org_id
--      null: the notice outlives the business), with no charge to anybody.
--   8. delete_my_account(p_me, p_confirmed_orgs, p_stopped): the
--      deletion, the account Worker's alone (POST /v1/me/delete; service
--      role — the app's role calls none of section 8, review B1). The
--      Worker learns the person's id from GoTrue, from their own token,
--      signed in less than ten minutes ago (S8). Order (B1): the Worker
--      first asks delete_my_account_stops() what must be stopped outside
--      (every Stripe subscription and Google Play purchase of the
--      businesses that go; nothing changed), stops each, writes the ids
--      in account_deletion_log (account_deletion_note, before any purge,
--      in a log that outlives both), and only then calls the deletion,
--      which checks once more that nothing still running was left. One
--      cancellation that fails, or a key the Worker lacks, and nothing is
--      deleted. SECURITY DEFINER for the reason 014 gives delete_org (it
--      destroys rows RLS rightly refuses to anyone, an owner included).
--      An owner's businesses go only
--      if the list the app showed (p_confirmed_orgs) is the list that
--      would go — a business created since, or an older app that showed
--      none, is refused. Then, for the person, exactly what GoTrue's
--      delete cascades (and as GoTrue does it, with no caller), done here
--      first so that it holds even when the account must be kept as a
--      shell: rows that cascade are deleted, keys that let go are
--      cleared, nullable keys that would hold the account are cleared
--      too (a sale, a product, a run no longer names the person), the
--      orders the person placed read « Client supprimé » (113), the
--      profile is emptied. What still names the person after that (a
--      NOT NULL « written by » on a business's books, kept for the law,
--      which belongs to the business) makes the answer mode « soft »:
--      the Worker then soft-deletes the auth user (GoTrue's
--      should_soft_delete: e-mail, phone, password, identities and
--      metadata wiped, no sign-in ever again) instead of deleting the
--      row. Otherwise « hard ». The App Store subscriptions are counted:
--      Mara cannot cancel them, the app tells the owner where to.
--   9. Mara's own money (S5): wave_payments — what customers paid Mara and
--      Mara paid out, Mara Pro and the spots, Mara's revenue — no longer
--      cascades with a business: detached (org_id null, former_org_id
--      naming its tombstone), kept for Mara's accounts. A deletion is
--      refused while a Wave payout to a doomed business is pending or
--      failed.
--   113's delete_my_account_check() stays for the Worker deployed today,
--   until this batch's account Worker replaces it (BUILD_PLAN: dropped in
--   129).
-- ============================================================

insert into platform_settings (key, value) values ('store_billing_on', 'false')
on conflict (key) do nothing;
-- 5c: the one account (besides the platform's admins) whose businesses a
-- sandbox purchase may turn Pro — the account given to App Review.
insert into platform_settings (key, value) values ('store_review_account', '"review.mara@gmail.com"')
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
    -- 5b: when the store signed what this row holds; older news is ignored.
    signed_at        timestamptz,
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
-- 5c. Whose sandbox purchases count
-- ------------------------------------------------------------
create or replace function store_sandbox_allowed(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select exists (
        select 1 from memberships m
          join profiles p on p.id = m.user_id
          left join auth.users u on u.id = m.user_id
         where m.org_id = p_org_id and m.role = 'owner'
           and (p.is_platform_admin
                or lower(btrim(coalesce(u.email, ''))) = lower(btrim(coalesce(
                       (select value #>> '{}' from platform_settings
                         where key = 'store_review_account'), 'review.mara@gmail.com')))));
$$;

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
           and s.expires_at > now()
           -- 5c: a test purchase is Pro only for Mara's own and App Review.
           and (s.environment = 'production' or store_sandbox_allowed(s.org_id)));
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

-- The WIP signature (no p_signed_at), on a copy that had it.
drop function if exists store_settle(text, uuid, text, text, text, timestamptz, boolean, text, jsonb, uuid, text);
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
    p_replaces    text default null,
    p_signed_at   timestamptz default null
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
    -- 5c: a test purchase, for Mara's own businesses and App Review's only.
    if p_environment = 'sandbox' and not store_sandbox_allowed(p_org_id) then
        return jsonb_build_object('ok', false, 'reason', 'sandbox');
    end if;
    -- 5b: older news than what is held changes nothing (a notification
    -- retried after a refund, two answers crossing).
    if found and v_row.signed_at is not null and p_signed_at is not null
       and p_signed_at < v_row.signed_at then
        return jsonb_build_object('ok', true, 'stale', true,
                                  'pro', org_plan(p_org_id) = 'pro',
                                  'state', v_row.state, 'expires_at', v_row.expires_at);
    end if;
    v_was := store_pro_active(p_org_id) or org_plan(p_org_id) = 'pro';

    insert into store_subscriptions (org_id, platform, product_id, original_id, state,
                                     expires_at, auto_renew, environment, bought_by,
                                     last_verified_at, signed_at, raw)
    values (p_org_id, p_platform, p_product_id, p_original_id, p_state,
            p_expires_at, coalesce(p_auto_renew, false),
            case when p_environment = 'sandbox' then 'sandbox' else 'production' end,
            p_bought_by, now(), p_signed_at, p_raw)
    on conflict (platform, original_id) do update set
        product_id       = excluded.product_id,
        state            = excluded.state,
        expires_at       = excluded.expires_at,
        auto_renew       = excluded.auto_renew,
        environment      = excluded.environment,
        bought_by        = coalesce(store_subscriptions.bought_by, excluded.bought_by),
        last_verified_at = now(),
        signed_at        = coalesce(excluded.signed_at, store_subscriptions.signed_at),
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
                     then 'Mara Pro est actif, payé sur l''App Store, jusqu''au '
                     else 'Mara Pro est actif, payé sur Google Play, jusqu''au ' end
                || to_char((p_expires_at at time zone 'Africa/Ouagadougou')::date, 'DD/MM/YYYY') || '.',
                jsonb_build_object('to', 'shop', 'store', p_platform,
                                   'until', (p_expires_at at time zone 'Africa/Ouagadougou')::date));
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
       -- 5c: a test purchase no longer counted is not asked about daily.
       and (s.environment = 'production' or store_sandbox_allowed(s.org_id))
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
revoke execute on function store_sandbox_allowed(uuid) from public;
revoke execute on function store_billing_on()        from public;
revoke execute on function store_verify_begin(uuid)  from public;
revoke execute on function store_settle(text, uuid, text, text, text, timestamptz, boolean, text, jsonb, uuid, text, timestamptz) from public;
revoke execute on function store_org_of(text, text)  from public;
revoke execute on function store_due()               from public;
revoke execute on function my_store_subscription(uuid) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function store_pro_active(uuid)    from anon;
        revoke execute on function store_sandbox_allowed(uuid) from anon;
        revoke execute on function store_billing_on()        from anon;
        revoke execute on function store_verify_begin(uuid)  from anon;
        revoke execute on function store_settle(text, uuid, text, text, text, timestamptz, boolean, text, jsonb, uuid, text, timestamptz) from anon;
        revoke execute on function store_org_of(text, text)  from anon;
        revoke execute on function store_due()               from anon;
        revoke execute on function my_store_subscription(uuid) from anon;
        -- The terms are the signed-in app's (born closed since 063; said
        -- again now that they carry the store switch).
        revoke execute on function plan_terms()              from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Read inside org_plan() / feature_paid() / plan_terms(), as their
        -- owner: nobody's to call.
        revoke execute on function store_pro_active(uuid)    from authenticated;
        revoke execute on function store_sandbox_allowed(uuid) from authenticated;
        revoke execute on function store_billing_on()        from authenticated;
        -- The Worker's alone.
        revoke execute on function store_settle(text, uuid, text, text, text, timestamptz, boolean, text, jsonb, uuid, text, timestamptz) from authenticated;
        revoke execute on function store_org_of(text, text)  from authenticated;
        revoke execute on function store_due()               from authenticated;
        -- The caller's own.
        grant execute on function store_verify_begin(uuid)   to authenticated;
        grant execute on function my_store_subscription(uuid) to authenticated;
        grant execute on function plan_terms()               to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function store_settle(text, uuid, text, text, text, timestamptz, boolean, text, jsonb, uuid, text, timestamptz) to service_role;
        grant execute on function store_org_of(text, text)   to service_role;
        grant execute on function store_due()                to service_role;
        grant select on store_subscriptions to service_role;
    end if;
end $$;

-- ============================================================
-- B. ACCOUNT DELETION
-- ============================================================

-- ------------------------------------------------------------
-- 6a. Mara's money outlives a business (review S5)
-- ------------------------------------------------------------
-- wave_payments is Mara's own ledger, not the business's books: what a
-- customer paid Mara for an order and what Mara paid out to the shop,
-- and every Mara Pro and « Mettre en avant » payment — Mara's revenue,
-- which Mara must account for whatever becomes of the business. Until
-- now it cascaded away with the business. Now a business that goes
-- (purge_org: the platform's « Supprimer » and an owner's account
-- deletion alike) leaves its payments in place, detached: org_id null
-- (no business's admin reads them any more; the platform's console
-- still does), former_org_id naming the business, whose tombstone
-- (deleted_orgs: name, slug, kind, when, by whom) says which it was;
-- the order and the spot they paid for, gone with the business, are
-- unlinked. Amounts, commission, payout, Wave's ids and dates stay as
-- they were: an audit reads them as on the day. A detached row is
-- never paid out again: a deletion is refused while a payout to the
-- business is pending or failed (delete_my_account_plan).
alter table wave_payments add column if not exists former_org_id uuid;
alter table wave_payments alter column org_id drop not null;
do $$
begin
    if exists (select 1 from pg_constraint
                where conname = 'wave_payments_org_id_fkey' and confdeltype = 'c') then
        alter table wave_payments drop constraint wave_payments_org_id_fkey;
        alter table wave_payments add constraint wave_payments_org_id_fkey
            foreign key (org_id) references orgs(id) on delete set null;
    end if;
end $$;
create index if not exists wave_payments_former_org on wave_payments (former_org_id)
    where former_org_id is not null;

-- 076's console list, with the payments of a business that is gone named
-- by its tombstone (an inner join on orgs would hide them).
create or replace function platform_wave_payments(p_limit integer default 50)
returns table (
    id uuid, kind text, org_name text, amount numeric, commission numeric,
    method text, status text, payout_status text, payout_to text,
    payout_error text, created_at timestamptz, paid_at timestamptz
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select p.id, p.kind, coalesce(o.name, d.name || ' (supprimée)', '—'), p.amount, p.commission,
           p.method, p.status, p.payout_status, p.payout_to, p.payout_error, p.created_at, p.paid_at
    from wave_payments p
    left join orgs o on o.id = p.org_id
    left join deleted_orgs d on d.id = p.former_org_id
    where exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
      and (o.id is not null or p.former_org_id is not null)
    order by (p.payout_status = 'failed') desc, p.created_at desc
    limit least(greatest(coalesce(p_limit, 50), 1), 200);
$$;

-- ------------------------------------------------------------
-- 6. One path to destroy a business: 014's, moved out unchanged
-- ------------------------------------------------------------
create or replace function purge_org(p_org_id uuid, p_actor uuid, p_label text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org     orgs%rowtype;
    v_entries int;
    v_members int;
begin
    select * into v_org from orgs where id = p_org_id;
    if not found then
        return;
    end if;
    select count(*) into v_entries from journal_entries where org_id = p_org_id;
    select count(*) into v_members from memberships    where org_id = p_org_id;

    -- Written before the delete, and outside the org's own scope, because
    -- audit_log.org_id cascades and would take this record with it.
    insert into deleted_orgs (
        id, name, slug, profile, deleted_by, deleted_label,
        entry_count, member_count, created_at
    )
    values (
        v_org.id, v_org.name, v_org.slug, v_org.profile, p_actor, p_label,
        v_entries, v_members, v_org.created_at
    )
    on conflict (id) do nothing;

    -- Every audited child table fires AFTER DELETE during the cascade below
    -- and writes an audit_log row pointing at an org that no longer exists.
    -- Deferring the key lets the cascade finish; the sweep afterwards removes
    -- those rows, so the check at commit finds nothing dangling. See the note
    -- beside the constraint above for why this is here rather than inside
    -- audit_row().
    set constraints audit_log_org_id_fkey deferred;

    -- Leaf-first, by hand, and this is not paranoia. Most org-scoped tables
    -- cascade from `orgs`, but plenty of the references *between* them are
    -- NO ACTION — journal_lines.account_id, sales.entry_id,
    -- staff_payments.employee_id, invoices.customer_id — and a cascade does
    -- not order itself by dependency, so it aborts halfway with a foreign key
    -- error and the business survives its own deletion.
    --
    -- The tempting fix is to make those keys cascade too. That would mean
    -- deleting an account silently destroys every ledger line posted to it,
    -- which is the guard those keys exist to provide and is worth far more
    -- than the convenience here. So the destruction is spelled out instead.
    --
    -- A new module with a new table belongs on this list. `test_org_lifecycle`
    -- deletes a business holding one of everything, so forgetting shows up as
    -- a failing suite rather than as a platform admin who cannot delete.
    delete from journal_lines jl using journal_entries je
        where jl.journal_entry_id = je.id and je.org_id = p_org_id;
    delete from contribution_attributions ca using journal_entries je
        where ca.journal_entry_id = je.id and je.org_id = p_org_id;
    delete from sale_lines sl using sales s
        where sl.sale_id = s.id and s.org_id = p_org_id;

    -- 128: the modules since 014 whose keys between them hold, and that
    -- were never put on this list — the credit book (024: a debt names its
    -- customer, its sale and its entry), the tontines (a contribution
    -- names its member), production (a run and its inputs name products)
    -- and the delivery receipts (an entry). Until now any business with
    -- one of them survived its own deletion with a foreign-key error —
    -- the platform's « Supprimer » included. test_batch128 deletes a shop,
    -- a farm and an association with books, a credit sale and its payment.
    delete from debt_payments         where org_id = p_org_id;
    delete from debts                 where org_id = p_org_id;
    delete from tontine_contributions where org_id = p_org_id;
    delete from production_inputs pi using production_runs pr
        where pi.run_id = pr.id and pr.org_id = p_org_id;
    delete from production_runs       where org_id = p_org_id;
    delete from stock_receipts        where org_id = p_org_id;

    delete from staff_payments  where org_id = p_org_id;
    delete from shifts          where org_id = p_org_id;
    delete from employees       where org_id = p_org_id;

    -- invoice_payments, invoice_lines, flock_events and sale_lines carry no
    -- org_id of their own: they are reached through their parent, which is
    -- how they were written and is not worth changing here.
    delete from invoice_payments ip using invoices i
        where ip.invoice_id = i.id and i.org_id = p_org_id;
    delete from invoice_lines il using invoices i
        where il.invoice_id = i.id and i.org_id = p_org_id;
    delete from invoices        where org_id = p_org_id;
    delete from customers       where org_id = p_org_id;

    delete from egg_production  where org_id = p_org_id;
    delete from flock_events fe using flocks f
        where fe.flock_id = f.id and f.org_id = p_org_id;
    delete from flocks          where org_id = p_org_id;
    delete from stock_movements where org_id = p_org_id;
    delete from items           where org_id = p_org_id;

    delete from documents       where org_id = p_org_id;

    -- Self-referencing: a return points at the sale it reverses, and a
    -- reversing entry at the entry it reverses. Broken before the rows go,
    -- because a delete cannot order a table against itself either.
    update sales set reverses_id = null where org_id = p_org_id;
    delete from sales           where org_id = p_org_id;
    delete from products        where org_id = p_org_id;

    update journal_entries set reverses_entry_id = null where org_id = p_org_id;
    delete from journal_entries where org_id = p_org_id;
    delete from accounts        where org_id = p_org_id;
    delete from church_members  where org_id = p_org_id;

    -- 6a: Mara's own payments stay, detached from the business.
    update wave_payments
       set former_org_id = org_id, org_id = null, order_id = null, promotion_id = null
     where org_id = p_org_id;

    -- What is left cascades cleanly: memberships, entities, departments,
    -- pending_invitations, audit_log.
    delete from orgs where id = p_org_id;

    -- The org's own audit trail was already cascaded away by the same
    -- statement; this clears what the cascade's own triggers wrote on the way
    -- out. Both are gone either way — which is the argument for the tombstone
    -- and not a shortcut around it.
    delete from audit_log where org_id = p_org_id;

end;
$$;

-- 014's delete_org: every fence as it was, then the one path.
create or replace function delete_org(
    p_org_id       uuid,
    p_confirm_name text,
    p_force        boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor   uuid := auth.uid();
    v_org     orgs%rowtype;
    v_label   text;
    v_entries int;
begin
    if v_actor is null then
        raise exception 'delete_org() needs a signed-in caller';
    end if;

    if not exists (select 1 from profiles where id = v_actor and is_platform_admin) then
        raise exception 'Only a platform admin can delete a business';
    end if;

    select * into v_org from orgs where id = p_org_id;
    if not found then
        raise exception 'No such business';
    end if;

    -- Never the first thing that happens to a business. Archiving is
    -- reversible and takes it off everyone's screen already, so anyone who
    -- reaches here has had a chance to change their mind.
    if v_org.archived_at is null then
        raise exception
            'Archive % first. Deleting is permanent and archiving is not.',
            v_org.name;
    end if;

    -- The name, typed back. A uuid in a confirmation dialog is not read by
    -- anybody; a name that has to be copied out is.
    if lower(btrim(coalesce(p_confirm_name, ''))) <> lower(btrim(v_org.name)) then
        raise exception
            'Type the name exactly to confirm: %', v_org.name;
    end if;

    select count(*) into v_entries from journal_entries where org_id = p_org_id;

    -- A business nobody ever recorded anything in is a mistake to be swept
    -- up. A business with books is somebody's history, and destroying it
    -- takes a second, explicit act rather than the same click.
    if v_entries > 0 and not coalesce(p_force, false) then
        raise exception
            '% has % entries in its books. Deleting destroys them permanently.',
            v_org.name, v_entries;
    end if;

    select full_name into v_label from profiles where id = v_actor;
    perform purge_org(p_org_id, v_actor, v_label);
    return p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- 7. What a deletion would do
-- ------------------------------------------------------------
create or replace function delete_my_account_plan(p_me uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_blocked    text;
    v_code       text;
    v_shop       text;
    v_businesses jsonb;
    v_leaves     jsonb;
    v_name       text;
begin
    if p_me is null then
        return jsonb_build_object('blocked', 'Connectez-vous d''abord', 'blocked_code', 'signed_out');
    end if;

    -- The businesses that disappear: those the person is the only owner of.
    select coalesce(jsonb_agg(jsonb_build_object(
               'id', o.id, 'name', o.name, 'profile', o.profile,
               'members', (select count(*) from memberships x
                            where x.org_id = o.id and x.user_id <> p_me),
               'orders', (select count(*) from orders d
                           where d.org_id = o.id and d.status in ('pending', 'accepted', 'ready')),
               'store', coalesce((select jsonb_agg(jsonb_build_object('platform', s.platform,
                                     'state', s.state, 'auto_renew', s.auto_renew,
                                     'expires_at', s.expires_at))
                           from store_subscriptions s
                          where s.org_id = o.id
                            and s.state in ('active', 'grace', 'cancelled', 'on_hold', 'paused', 'pending')
                            and (s.expires_at is null or s.expires_at > now())), '[]'::jsonb),
               'stripe', exists (select 1 from stripe_subscriptions t
                                  where t.org_id = o.id and t.subscription_id is not null
                                    and t.status in ('active', 'trialing', 'past_due', 'unpaid', 'incomplete')))
               order by o.name), '[]'::jsonb)
      into v_businesses
      from orgs o
     where exists (select 1 from memberships m
                    where m.org_id = o.id and m.user_id = p_me and m.role = 'owner')
       and not exists (select 1 from memberships m
                        where m.org_id = o.id and m.user_id <> p_me and m.role = 'owner');

    -- The businesses the person only leaves.
    select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name) order by o.name), '[]'::jsonb)
      into v_leaves
      from orgs o
     where exists (select 1 from memberships m where m.org_id = o.id and m.user_id = p_me)
       and o.id not in (select (b ->> 'id')::uuid from jsonb_array_elements(v_businesses) b);

    -- Each refusal has a code (the app says it in the reader's language)
    -- and, where it names one, the business (blocked_shop).
    if exists (select 1 from profiles where id = p_me and is_platform_admin) then
        v_code := 'platform';
        v_blocked := 'Un compte de la plateforme ne se supprime pas ici.';
    elsif exists (select 1 from orders where customer_id = p_me
                    and status in ('pending', 'accepted', 'ready', 'in_transit')) then
        v_code := 'own_order';
        v_blocked := 'Une commande est en cours : attendez qu''elle soit terminée, ou annulez-la, puis supprimez votre compte.';
    elsif exists (select 1 from orders where courier_id = p_me and status in ('ready', 'in_transit')) then
        v_code := 'delivering';
        v_blocked := 'Une livraison est en cours : terminez-la, puis supprimez votre compte.';
    else
        select o.name into v_name
          from orders d join orgs o on o.id = d.org_id
         where d.org_id in (select (b ->> 'id')::uuid from jsonb_array_elements(v_businesses) b)
           and (d.status = 'in_transit'
                or (d.status in ('pending', 'accepted', 'ready')
                    and d.payment_method = 'wave' and d.paid_at is not null))
         order by o.name
         limit 1;
        if v_name is not null then
            v_code := 'business_order';
            v_shop := v_name;
            v_blocked := format('Une commande de « %s » est en route ou déjà payée en ligne : livrez-la ou remboursez-la, puis supprimez votre compte.', v_name);
        else
            -- S5: money Mara still owes the business (a Wave payout
            -- pending, or failed and to be retried) is never lost with it.
            select o.name into v_name
              from wave_payments w join orgs o on o.id = w.org_id
             where w.org_id in (select (b ->> 'id')::uuid from jsonb_array_elements(v_businesses) b)
               and w.payout_status in ('pending', 'failed')
             order by o.name
             limit 1;
            if v_name is not null then
                v_code := 'payout';
                v_shop := v_name;
                v_blocked := format('Mara doit encore verser à « %s » l''argent d''une commande payée par Wave (versement en attente ou en échec) : attendez qu''il arrive, ou écrivez à l''aide Mara, puis supprimez votre compte.', v_name);
            end if;
        end if;
    end if;

    return jsonb_build_object(
        'blocked',      v_blocked,
        'blocked_code', v_code,
        'blocked_shop', v_shop,
        'businesses',   v_businesses,
        'leaves',       v_leaves,
        'courier',      exists (select 1 from couriers where user_id = p_me),
        'apple_store',  (select count(*) from jsonb_array_elements(v_businesses) b,
                                jsonb_array_elements(b -> 'store') s
                          where s ->> 'platform' = 'apple' and (s ->> 'auto_renew')::boolean));
end;
$$;

-- The app's confirmation: the same plan, for the caller.
create or replace function delete_my_account_preview()
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select case when auth.uid() is null then null
                else delete_my_account_plan(auth.uid()) end;
$$;

-- ------------------------------------------------------------
-- 8. The deletion — the account Worker's alone (review B1)
-- ------------------------------------------------------------
-- The order, which holds whatever fails:
--   1. delete_my_account_stops(me, shown list): the plan's refusals and
--      the list check, then every Stripe subscription and Google Play
--      purchase of the businesses that will go — nothing is changed.
--   2. The Worker cancels each Stripe subscription and revokes each
--      Google Play purchase. One failure, or a key it needs that is not
--      set: it stops there and nothing is deleted (« Nous n'avons pas pu
--      arrêter l'abonnement … »).
--   3. account_deletion_note(me, 'stopped', what was stopped): the ids,
--      written down in account_deletion_log before anything is purged —
--      the log outlives the account and the businesses (no foreign key),
--      so what Mara stopped is known even if step 4 then fails.
--   4. delete_my_account(me, shown list, what was stopped): checks once
--      more that every subscription still to stop was stopped (one
--      started between 1 and 4 refuses it), then the deletion.
-- All four are the service role's (the Worker's): the app's role calls
-- none of them, so the Worker can never be skipped — the Worker learns
-- the person's id from GoTrue, from the person's own token, and a
-- recent sign-in is required there (review S8). The caller's own
-- delete_my_account(uuid[]) of the first draft of this file is gone.
drop function if exists delete_my_account(uuid[]);

create table if not exists account_deletion_log (
    id         bigint generated always as identity primary key,
    -- No foreign key: the record outlives the account it is about.
    user_id    uuid not null,
    stage      text not null check (stage in ('stopped', 'deleted')),
    businesses jsonb not null default '[]'::jsonb,
    stopped    jsonb not null default '{}'::jsonb,
    at         timestamptz not null default now()
);
create index if not exists account_deletion_log_by_user on account_deletion_log (user_id, at desc);
alter table account_deletion_log enable row level security;
comment on table account_deletion_log is
    'Every account deletion (128): the businesses that went with it and the '
    'Stripe subscriptions and Google Play purchases the account Worker stopped '
    'before the purge (stage stopped), then the deletion itself (stage deleted). '
    'No policy, no grant: the service role writes it, the platform reads it in SQL.';
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on account_deletion_log from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on account_deletion_log from authenticated;
    end if;
end $$;

-- 1. What will go and what must be stopped first; refuses as the plan does.
create or replace function delete_my_account_stops(p_me uuid, p_confirmed_orgs uuid[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_plan    jsonb;
    v_doomed  uuid[];
    v_names   text[];
    v_google  jsonb;
    v_stripe  jsonb;
begin
    if p_me is null or not exists (select 1 from profiles where id = p_me) then
        raise exception 'Connectez-vous d''abord';
    end if;
    v_plan := delete_my_account_plan(p_me);
    if v_plan ->> 'blocked' is not null then
        raise exception '%', v_plan ->> 'blocked'
            using detail = coalesce(v_plan ->> 'blocked_code', ''),
                  hint = coalesce(v_plan ->> 'blocked_shop', '');
    end if;
    select coalesce(array_agg((b ->> 'id')::uuid order by (b ->> 'id')), '{}'),
           coalesce(array_agg(b ->> 'name' order by b ->> 'name'), '{}')
      into v_doomed, v_names
      from jsonb_array_elements(v_plan -> 'businesses') b;
    if cardinality(v_doomed) > 0 then
        if p_confirmed_orgs is null then
            raise exception 'Mettez Mara à jour : la suppression d''un compte qui tient une activité se confirme dans la dernière version de l''application.'
                using detail = 'old_app';
        end if;
        if (select coalesce(array_agg(distinct x order by x), '{}') from unnest(p_confirmed_orgs) x)
           is distinct from v_doomed then
            raise exception 'La liste de vos activités a changé : relisez-la avant de supprimer votre compte.'
                using detail = 'list_changed';
        end if;
    end if;

    select coalesce(jsonb_agg(jsonb_build_object('token', s.original_id, 'org_id', o.id, 'org', o.name)
                              order by s.original_id), '[]'::jsonb)
      into v_google
      from store_subscriptions s join orgs o on o.id = s.org_id
     where s.org_id = any (v_doomed) and s.platform = 'google'
       and s.state in ('active', 'grace', 'cancelled', 'on_hold', 'paused', 'pending');
    select coalesce(jsonb_agg(jsonb_build_object('id', t.subscription_id, 'org_id', o.id, 'org', o.name)
                              order by t.subscription_id), '[]'::jsonb)
      into v_stripe
      from stripe_subscriptions t join orgs o on o.id = t.org_id
     where t.org_id = any (v_doomed) and t.subscription_id is not null
       and t.status in ('active', 'trialing', 'past_due', 'unpaid', 'incomplete');

    return jsonb_build_object(
        'user_id',     p_me,
        'orgs',        to_jsonb(v_doomed),
        'businesses',  to_jsonb(v_names),
        'google',      v_google,
        'stripe',      v_stripe,
        'apple_store', coalesce((v_plan ->> 'apple_store')::int, 0));
end;
$$;

-- 3. What the Worker stopped, written down before the purge.
create or replace function account_deletion_note(p_me uuid, p_businesses jsonb, p_stopped jsonb)
returns void
language sql
security definer
set search_path = public
as $$
    insert into account_deletion_log (user_id, stage, businesses, stopped)
    values (p_me, 'stopped', coalesce(p_businesses, '[]'::jsonb), coalesce(p_stopped, '{}'::jsonb));
$$;

-- 4. The deletion.
create or replace function delete_my_account(
    p_me             uuid,
    p_confirmed_orgs uuid[] default null,
    p_stopped        jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_stops   jsonb;
    v_doomed  uuid[];
    v_mode    text := 'hard';
    v_held    boolean;
    v_left    text;
    r         record;
    v_o       record;
begin
    -- Its refusals, the list check, and what had to be stopped — again,
    -- now, under the deletion's own transaction.
    v_stops := delete_my_account_stops(p_me, p_confirmed_orgs);
    select coalesce(array_agg(x::uuid), '{}') into v_doomed
      from jsonb_array_elements_text(v_stops -> 'orgs') x;

    -- Every subscription still running on a business that goes was
    -- stopped by the Worker (one started since step 1 refuses it all).
    select string_agg(g ->> 'org', ', ') into v_left
      from jsonb_array_elements(v_stops -> 'google') g
     where not coalesce(p_stopped -> 'google', '[]'::jsonb) ? (g ->> 'token');
    if v_left is null then
        select string_agg(t ->> 'org', ', ') into v_left
          from jsonb_array_elements(v_stops -> 'stripe') t
         where not coalesce(p_stopped -> 'stripe', '[]'::jsonb) ? (t ->> 'id');
    end if;
    if v_left is not null then
        raise exception 'Nous n''avons pas pu arrêter l''abonnement de « % » : rien n''a été supprimé. Réessayez dans un moment ou écrivez à l''aide.', v_left
            using detail = 'not_stopped';
    end if;

    insert into account_deletion_log (user_id, stage, businesses, stopped)
    values (p_me, 'deleted', v_stops -> 'businesses',
            jsonb_build_object('google', v_stops -> 'google', 'stripe', v_stops -> 'stripe',
                               'apple_store', v_stops -> 'apple_store'));

    -- Each business the person alone owns: its customers and members told
    -- on their own bell (no business: the notice outlives it), then
    -- archived and purged — 014's lifecycle, in one transaction.
    for v_o in select * from orgs where id = any (v_doomed) loop
        insert into notifications (recipient_id, org_id, kind, message, params)
        select distinct d.customer_id, null::uuid, 'order_cancelled',
               format('Votre commande chez %s est annulée : l''activité a fermé sur Mara.', v_o.name),
               jsonb_build_object('to', 'customer', 'status', 'cancelled', 'shop', v_o.name,
                                  'booking', d.booked_for is not null)
          from orders d
         where d.org_id = v_o.id and d.status in ('pending', 'accepted', 'ready')
           and d.customer_id is not null and d.customer_id <> p_me;
        insert into notifications (recipient_id, org_id, kind, message, params)
        select distinct m.user_id, null::uuid, 'org_closed',
               format('« %s » a fermé sur Mara : vous n''en faites plus partie. Votre compte reste le vôtre.', v_o.name),
               jsonb_build_object('to', 'me', 'shop', v_o.name)
          from memberships m
         where m.org_id = v_o.id and m.user_id <> p_me;
        update orgs set archived_at = coalesce(archived_at, now()),
                        archived_by = coalesce(archived_by, p_me)
         where id = v_o.id;
        perform purge_org(v_o.id, p_me, 'Compte du propriétaire supprimé');
    end loop;

    -- The person: what GoTrue's delete cascades, done as it does it — with
    -- no caller (the triggers that guard a member's removal by somebody
    -- else stand aside, as for GoTrue).
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{}', true);

    update orders
       set customer_name = 'Client supprimé', phone = null, address = null,
           drop_lat = null, drop_lng = null
     where customer_id = p_me;

    -- One statement per foreign key to profiles, each on its own column
    -- (not every one is indexed: a full scan per key, fine at Mara's size;
    -- an index belongs beside any of these tables that grows large).
    for r in
        select c.conrelid::regclass as tbl, a.attname as col, c.confdeltype as act,
               not a.attnotnull as nullable
          from pg_constraint c
          join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
         where c.contype = 'f'
           and c.confrelid = 'public.profiles'::regclass
           and cardinality(c.conkey) = 1
         order by 1, 2
    loop
        begin
            if r.act = 'c' then
                execute format('delete from %s where %I = $1', r.tbl, r.col) using p_me;
            elsif r.act = 'n' or (r.act in ('a', 'r') and r.nullable) then
                execute format('update %s set %I = null where %I = $1', r.tbl, r.col, r.col) using p_me;
            end if;
        exception when others then
            -- Left as it is: the row then holds the account (soft below).
            raise notice 'delete_my_account: %.% kept (%)', r.tbl, r.col, sqlerrm;
        end;
    end loop;

    update profiles
       set full_name = 'Compte supprimé', first_name = null, middle_name = null,
           last_name = null, phone = null, date_of_birth = null, title = null,
           profile_completed_at = null, preferred_locale = 'fr'
     where id = p_me;

    -- Whatever still names the person is the businesses' books (NOT NULL
    -- « written by »): the account stays as an empty shell.
    for r in
        select c.conrelid::regclass as tbl, a.attname as col
          from pg_constraint c
          join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
         where c.contype = 'f'
           and c.confrelid = 'public.profiles'::regclass
           and c.confdeltype in ('a', 'r')
           and cardinality(c.conkey) = 1
    loop
        execute format('select exists (select 1 from %s where %I = $1)', r.tbl, r.col)
           into v_held using p_me;
        if v_held then
            v_mode := 'soft';
            exit;
        end if;
    end loop;

    return jsonb_build_object(
        'user_id',     p_me,
        'mode',        v_mode,
        'businesses',  v_stops -> 'businesses',
        'google',      v_stops -> 'google',
        'stripe',      v_stops -> 'stripe',
        'apple_store', coalesce((v_stops ->> 'apple_store')::int, 0));
end;
$$;

revoke execute on function purge_org(uuid, uuid, text)                 from public;
revoke execute on function delete_org(uuid, text, boolean)             from public;
revoke execute on function delete_my_account_plan(uuid)                from public;
revoke execute on function delete_my_account_preview()                 from public;
revoke execute on function delete_my_account_stops(uuid, uuid[])       from public;
revoke execute on function account_deletion_note(uuid, jsonb, jsonb)   from public;
revoke execute on function delete_my_account(uuid, uuid[], jsonb)      from public;
revoke execute on function platform_wave_payments(integer)             from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function purge_org(uuid, uuid, text)               from anon;
        revoke execute on function delete_org(uuid, text, boolean)           from anon;
        revoke execute on function delete_my_account_plan(uuid)              from anon;
        revoke execute on function delete_my_account_preview()              from anon;
        revoke execute on function delete_my_account_stops(uuid, uuid[])     from anon;
        revoke execute on function account_deletion_note(uuid, jsonb, jsonb) from anon;
        revoke execute on function delete_my_account(uuid, uuid[], jsonb)    from anon;
        revoke execute on function platform_wave_payments(integer)           from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: called by delete_org and delete_my_account as their owner.
        revoke execute on function purge_org(uuid, uuid, text)               from authenticated;
        revoke execute on function delete_my_account_plan(uuid)              from authenticated;
        -- B1: the deletion is the account Worker's (service role) alone.
        revoke execute on function delete_my_account_stops(uuid, uuid[])     from authenticated;
        revoke execute on function account_deletion_note(uuid, jsonb, jsonb) from authenticated;
        revoke execute on function delete_my_account(uuid, uuid[], jsonb)    from authenticated;
        -- The doors, each about the caller (delete_org: the platform's).
        grant execute on function delete_org(uuid, text, boolean)            to authenticated;
        grant execute on function delete_my_account_preview()                to authenticated;
        grant execute on function platform_wave_payments(integer)            to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function delete_my_account_stops(uuid, uuid[])      to service_role;
        grant execute on function account_deletion_note(uuid, jsonb, jsonb)  to service_role;
        grant execute on function delete_my_account(uuid, uuid[], jsonb)     to service_role;
    end if;
end $$;

notify pgrst, 'reload schema';
