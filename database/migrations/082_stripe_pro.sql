-- ============================================================
-- 082_stripe_pro.sql — Kaj Pro by card, as a subscription, through Stripe.
--
-- The owner: Stripe is for the subscription only (Wave stays the way to
-- pay an order); the platform chooses the prices, because the market moves.
--
--   1. One price, wherever it is paid: the month and year prices are 066's
--      pro_price_month / pro_price_year, which the platform already sets
--      from the Kaj Pro console, in pro_currency. Stripe charges what the
--      comparison page shows; a new price applies to the next subscription
--      (a running one renews at the price it was taken at, Stripe's rule).
--      stripe_on is the switch (off until the keys are in); plan_terms()
--      now says it, so the app shows the card button only when it works.
--   2. stripe_begin(): the Worker calls it with the owner's own token, so
--      under their identity. Only an administrator of the business; the
--      amount is the platform's, never the app's.
--   3. stripe_subscriptions: one row per business — Stripe's customer and
--      subscription, its status and the end of the paid period.
--   4. stripe_settle() (service role, the Worker alone): whatever Stripe
--      says about a subscription — first payment, renewal, cancellation —
--      is written down, and while it is active the business is Pro until
--      the end of the paid period (and one day of grace). A cancelled or
--      unpaid subscription is not cut short: Pro runs to what was paid.
--      Idempotent — Stripe delivers an event more than once.
--   5. my_stripe_subscription(): the owner reads where theirs stands.
-- ============================================================

insert into platform_settings (key, value) values ('stripe_on', 'false')
on conflict (key) do nothing;

create table if not exists stripe_subscriptions (
    org_id               uuid primary key references orgs(id) on delete cascade,
    customer_id          text,
    subscription_id      text unique,
    status               text,
    period               text check (period is null or period in ('month', 'year')),
    current_period_end   timestamptz,
    cancel_at_period_end boolean not null default false,
    updated_at           timestamptz not null default now()
);
alter table stripe_subscriptions enable row level security;
-- No policies: read through my_stripe_subscription(), written by the Worker.

create or replace function stripe_on()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((select (value #>> '{}')::boolean
                       from platform_settings where key = 'stripe_on'), false);
$$;

-- 067's terms, saying whether the card is open.
create or replace function plan_terms()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'pro_features',            coalesce(plan_setting('pro_features'), '[]'::jsonb),
        'free_max_staff',          plan_limit('free_max_staff', 3),
        'free_max_invoices_month', plan_limit('free_max_invoices_month', 20),
        'free_max_photos',         plan_limit('free_max_photos', 50),
        'free_history_months',     plan_limit('free_history_months', 12),
        'pro_price_month',         plan_limit('pro_price_month', 2500),
        'pro_price_year',          plan_limit('pro_price_year', 25000),
        'pro_currency',            coalesce(plan_setting('pro_currency') #>> '{}', 'XOF'),
        'platform_wave',           coalesce(plan_setting('platform_wave') #>> '{}', ''),
        'platform_wave_name',      coalesce(plan_setting('platform_wave_name') #>> '{}', ''),
        'delivery_share_pct',      plan_limit('delivery_share_pct', 10),
        'stripe_on',               stripe_on()
    );
$$;

create or replace function stripe_begin(p_org_id uuid, p_period text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_terms jsonb := plan_terms();
    v_org   orgs%rowtype;
    v_amount numeric;
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
    v_amount := (v_terms ->> case when p_period = 'year' then 'pro_price_year'
                                  else 'pro_price_month' end)::numeric;
    if coalesce(v_amount, 0) <= 0 then
        raise exception 'Le prix de Kaj Pro n''est pas fixé';
    end if;
    return jsonb_build_object(
        'org_id',      v_org.id,
        'org_name',    v_org.name,
        'period',      p_period,
        'amount',      v_amount,
        'currency',    lower(v_terms ->> 'pro_currency'),
        'customer_id', (select customer_id from stripe_subscriptions where org_id = p_org_id),
        'email',       (select email from auth.users where id = auth.uid())
    );
end;
$$;

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
                    || to_char(v_until, 'DD/MM/YYYY') || '.');
            exception when others then null;
            end;
        end if;
    end if;
    return jsonb_build_object('ok', true, 'active', v_active, 'until', v_until);
end;
$$;

create or replace function my_stripe_subscription(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select jsonb_build_object(
        'status', s.status,
        'period', s.period,
        'current_period_end', s.current_period_end,
        'cancel_at_period_end', s.cancel_at_period_end,
        'has_customer', s.customer_id is not null)
    from stripe_subscriptions s
    where s.org_id = p_org_id and is_org_admin(p_org_id);
$$;

-- The customer id, for the Worker opening Stripe's own page where the owner
-- changes the card or cancels — under the owner's identity, admins only.
create or replace function stripe_customer_of(p_org_id uuid)
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
    select s.customer_id from stripe_subscriptions s
     where s.org_id = p_org_id and is_org_admin(p_org_id);
$$;

revoke execute on function stripe_on()                                       from public;
revoke execute on function plan_terms()                                      from public;
revoke execute on function stripe_begin(uuid, text)                          from public;
revoke execute on function stripe_settle(uuid, text, text, text, text, timestamptz, boolean) from public;
revoke execute on function my_stripe_subscription(uuid)                      from public;
revoke execute on function stripe_customer_of(uuid)                          from public;

do $$
begin
    -- Supabase's default privileges give a new function to authenticated
    -- directly (063 closed only anon and PUBLIC): the Worker's own is taken
    -- back by name, as 076 learned.
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function stripe_settle(uuid, text, text, text, text, timestamptz, boolean) from anon;
        revoke execute on function stripe_begin(uuid, text)     from anon;
        revoke execute on function my_stripe_subscription(uuid) from anon;
        revoke execute on function stripe_customer_of(uuid)     from anon;
        revoke execute on function stripe_on()                  from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function stripe_settle(uuid, text, text, text, text, timestamptz, boolean) from authenticated;
        grant execute on function plan_terms()                  to authenticated;
        grant execute on function stripe_begin(uuid, text)      to authenticated;
        grant execute on function my_stripe_subscription(uuid)  to authenticated;
        grant execute on function stripe_customer_of(uuid)      to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function stripe_settle(uuid, text, text, text, text, timestamptz, boolean) to service_role;
    end if;
end $$;

notify pgrst, 'reload schema';
