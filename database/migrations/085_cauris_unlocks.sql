-- ============================================================
-- 085_cauris_unlocks.sql — cauris buy Pro tools; Basic opens step by step.
--
-- Phase 2 of the owner's model (084 earns, this spends):
--
--   1. Unlock with cauris, 30 days. cauris_costs is the platform's price
--      list (set from the console: set_cauris_cost); spend_cauris() takes
--      the price from the wallet in one ledger line and opens the tool for
--      30 days from today, or 30 more from when it would have closed.
--      « pro_all » is Mara Pro complet: for 30 days the business IS Pro —
--      org_plan() says so — so every Pro rule (the free caps, delivery,
--      the dressed vitrine, the monthly spot) follows without a second
--      list to keep in step.
--   2. One question for every tool: org_has(business, tool) — Pro, or
--      unlocked. pro_locked() and feature_access() ask it instead of the
--      plan alone, and so do 081's delivery and online-payment doors and
--      068's dressed vitrine. Two tools also want time on Mara before
--      cauris can open them: accounting after 60 days (an empty book is
--      worth nothing), tontines after 90 (other people's money).
--   3. Basic, step by step, for businesses that start from now on
--      (orgs.progress_since; the ones already here keep everything they
--      have): the vitrine reaches the street at 60 %; invoices and
--      receipts, production and the credit book open at 90 %; a second
--      business after 10 finished orders. Seven days of trial first, so
--      nobody meets a wall in their first ten minutes. The numbers are
--      platform settings. The street's rule is the database's own (the
--      directory lists a new business once its vitrine is at 60 %); the
--      tools' rule is the app's to draw — they are free tools, and the
--      gate is a path, not a price.
--   4. feature_states(): everything the app needs to draw the grey badges
--      — each Pro tool's price, whether and until when it is unlocked,
--      what it still waits for — and the Basic path.
--
-- No destructive statement: every function is replaced in place with its
-- own signature, so the live database takes this without a hand on it.
-- ============================================================

insert into platform_settings (key, value) values
    ('progress_street_pct', '60'),
    ('progress_tools_pct',  '90'),
    ('progress_orders',     '10'),
    ('progress_trial_days',  '7'),
    ('cauris_unlock_days',  '30')
on conflict (key) do nothing;

-- Null for every business already here: they keep all they have.
alter table orgs add column if not exists progress_since timestamptz;
alter table orgs alter column progress_since set default now();

create table if not exists cauris_costs (
    feature   text primary key,
    cost      integer not null check (cost > 0),
    min_days  integer not null default 0 check (min_days >= 0),
    sort      integer not null default 0
);
alter table cauris_costs enable row level security;

insert into cauris_costs (feature, cost, min_days, sort) values
    ('analytics',       400,  0, 10),
    ('delivery',        600,  0, 20),
    ('online_payment',  500,  0, 30),
    ('vitrine_plus',    300,  0, 40),
    ('accounting',      500, 60, 50),
    ('team_access',     400,  0, 60),
    ('payroll',         400,  0, 70),
    ('currencies',      300,  0, 80),
    ('tontines',        500, 90, 90),
    ('pro_all',        1500,  0,  0)
on conflict (feature) do nothing;

create table if not exists cauris_unlocks (
    org_id     uuid not null references orgs(id) on delete cascade,
    feature    text not null,
    until      timestamptz not null,
    updated_at timestamptz not null default now(),
    primary key (org_id, feature)
);
alter table cauris_unlocks enable row level security;

-- ------------------------------------------------------------
-- 1. The plan, with Mara Pro complet bought in cauris
-- ------------------------------------------------------------
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

-- Pro, or this one tool unlocked.
create or replace function org_has(p_org_id uuid, p_feature text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select org_plan(p_org_id) = 'pro'
        or exists (select 1 from cauris_unlocks u
                    where u.org_id = p_org_id and u.feature = p_feature
                      and u.until > now());
$$;

-- ------------------------------------------------------------
-- 2. Every guard asks org_has()
-- ------------------------------------------------------------
create or replace function pro_locked(p_org_id uuid, p_feature text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select auth.uid() is not null
       and not exists (select 1 from profiles
                        where id = auth.uid() and is_platform_admin)
       and not org_has(p_org_id, p_feature)
       and coalesce(plan_setting('pro_features'), '[]'::jsonb) ? p_feature;
$$;

create or replace function feature_access(p_org_id uuid, p_feature text)
returns text
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_roles  text[];
    v_tier   text;
    v_access text;
begin
    if auth.uid() is null then
        return 'hidden';
    end if;
    if exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return 'edit';
    end if;

    select array_agg(distinct role) into v_roles
      from memberships
     where org_id = p_org_id and user_id = auth.uid();

    if v_roles is null then
        return 'hidden';
    end if;
    if v_roles && array['owner', 'super_admin', 'admin'] then
        v_access := 'edit';
    else
        v_tier := case
            when v_roles && array['manager', 'supervisor'] then 'supervisor'
            else 'employee'
        end;

        select access into v_access
          from org_feature_rules
         where org_id = p_org_id and tier = v_tier and feature = p_feature;

        v_access := coalesce(v_access,
            case when p_feature = 'reports' then 'view' else 'edit' end);
    end if;

    -- The plan layer (066), now with cauris (085): a Pro tool the business
    -- neither pays for nor unlocked is 'view', never 'hidden'.
    if v_access = 'edit'
       and not org_has(p_org_id, p_feature)
       and coalesce(plan_setting('pro_features'), '[]'::jsonb) ? p_feature then
        return 'view';
    end if;

    return v_access;
end;
$$;

-- 081's doors, asking for the one tool.
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
           and org_has(o.id, 'delivery'));
$$;

-- 081's fee: delivery quoted only when the business may deliver.
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

create or replace function trg_order_delivery_pro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.fulfilment = 'delivery' and not org_has(new.org_id, 'delivery') then
        raise exception 'Kaj Pro : la livraison est réservée aux boutiques Kaj Pro. Choisissez le retrait en boutique.';
    end if;
    return new;
end;
$$;

create or replace function trg_wave_order_pro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.kind = 'order' and not org_has(new.org_id, 'online_payment') then
        raise exception 'Kaj Pro : le paiement en ligne est réservé aux boutiques Kaj Pro';
    end if;
    return new;
end;
$$;

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
               and org_has(id, 'online_payment')),
        'card', coalesce((select (value #>> '{}')::boolean
                            from platform_settings where key = 'wave_card'), false),
        'commission_pct', coalesce((select (value #>> '{}')::numeric
                                      from platform_settings where key = 'wave_commission_pct'), 0)
    );
$$;

-- 081's window: the dressed vitrine is Pro, or unlocked.
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
           o.wave_merchant,
           (case when org_has(o.id, 'vitrine_plus') then o.storefront_style
                 else '{}'::jsonb end)
           || case when o.logo_key is not null
                   then jsonb_build_object('logo_key', o.logo_key)
                   else '{}'::jsonb end
           || jsonb_build_object('delivers', org_delivers(o.id))
    from orgs o
    where o.id = storefront_open(p_slug);
$$;

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
          and p.is_active
          and p.is_published
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
          and org_has(o.id, 'vitrine_plus')
    ) or exists (
        select 1
        from orgs o
        where o.logo_key = p_key
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
    );
$$;

-- ------------------------------------------------------------
-- 3. Basic, step by step
-- ------------------------------------------------------------
create or replace function org_progress(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'gated',       o.progress_since is not null,
        'trial_until', case when o.progress_since is not null
                            then o.progress_since + make_interval(days => cauris_param('progress_trial_days', 7)) end,
        'in_trial',    o.progress_since is not null
                       and now() < o.progress_since + make_interval(days => cauris_param('progress_trial_days', 7)),
        'score',       vitrine_score(o.id),
        'orders',      (select count(*) from orders x
                         where x.org_id = o.id and x.status in ('picked_up', 'delivered')),
        'street_pct',  cauris_param('progress_street_pct', 60),
        'tools_pct',   cauris_param('progress_tools_pct', 90),
        'orders_needed', cauris_param('progress_orders', 10),
        'on_street',   o.progress_since is null
                       or vitrine_score(o.id) >= cauris_param('progress_street_pct', 60)
    )
    from orgs o where o.id = p_org_id;
$$;

-- 070's street, now holding back a new business's vitrine until it is
-- worth a look (60 %): an empty window on the street is a bad street.
create or replace function storefront_directory(
    p_lat double precision default null,
    p_lng double precision default null
)
returns table (
    org_id      uuid,
    name        text,
    slug        text,
    profile     text,
    blurb       text,
    address     text,
    lat         double precision,
    lng         double precision,
    distance_km double precision
)
language sql
stable
security definer
set search_path = public
as $$
    select d.org_id, d.name, d.slug, d.profile, d.blurb, d.address,
           d.lat, d.lng, d.distance_km
    from (
        select o.id as org_id, o.name, o.slug, o.profile::text,
               o.storefront_blurb as blurb, o.address, o.lat, o.lng,
               case
                   when p_lat is null or p_lng is null
                     or o.lat is null or o.lng is null then null
                   else 6371.0 * 2 * asin(sqrt(
                            power(sin(radians(o.lat - p_lat) / 2), 2)
                          + cos(radians(p_lat)) * cos(radians(o.lat))
                          * power(sin(radians(o.lng - p_lng) / 2), 2)))
               end as distance_km
        from orgs o
        where o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
          and exists (select 1 from products p
                       where p.org_id = o.id
                         and p.is_active
                         and p.is_published)
          and (o.progress_since is null
               or vitrine_score(o.id) >= cauris_param('progress_street_pct', 60))
    ) d
    order by (d.distance_km is null), d.distance_km, d.name;
$$;

-- ------------------------------------------------------------
-- 4. Spending, and what the app draws
-- ------------------------------------------------------------
create or replace function spend_cauris(p_org_id uuid, p_feature text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_cost   cauris_costs%rowtype;
    v_org    orgs%rowtype;
    v_until  timestamptz;
    v_days   int := cauris_param('cauris_unlock_days', 30);
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur dépense les cauris de l''entreprise';
    end if;
    select * into v_cost from cauris_costs where feature = p_feature;
    if not found then
        raise exception 'Cet outil ne s''ouvre pas avec des cauris';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if v_org.profile in ('church', 'association') then
        raise exception 'Les cauris sont pour les boutiques et les fermes';
    end if;
    if v_cost.min_days > 0 and v_org.created_at > now() - make_interval(days => v_cost.min_days) then
        raise exception 'Cet outil s''ouvre avec des cauris après % jours sur Mara', v_cost.min_days;
    end if;
    perform cauris_expire(p_org_id);
    -- One spender at a time on this wallet.
    perform pg_advisory_xact_lock(hashtext('cauris:' || p_org_id::text));
    if cauris_balance(p_org_id) < v_cost.cost then
        raise exception 'Il vous manque % cauris', v_cost.cost - cauris_balance(p_org_id);
    end if;

    select greatest(coalesce(u.until, now()), now()) + make_interval(days => v_days)
      into v_until
      from (select 1) x left join cauris_unlocks u
        on u.org_id = p_org_id and u.feature = p_feature;

    insert into cauris_ledger (org_id, delta, reason, ref, note)
    values (p_org_id, -v_cost.cost, 'spent',
            p_feature || ':' || gen_random_uuid()::text,
            p_feature);
    insert into cauris_unlocks (org_id, feature, until)
    values (p_org_id, p_feature, v_until)
    on conflict (org_id, feature) do update set until = excluded.until, updated_at = now();

    return jsonb_build_object('feature', p_feature, 'until', v_until,
                              'balance', cauris_balance(p_org_id));
end;
$$;

create or replace function feature_states(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select case when not is_org_member(p_org_id) then null else
    jsonb_build_object(
        'plan', org_plan(p_org_id),
        'balance', cauris_balance(p_org_id),
        'tools', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'feature', c.feature,
                       'cost', c.cost,
                       'until', u.until,
                       'waits_days', case
                           when c.min_days > 0
                            and o.created_at > now() - make_interval(days => c.min_days)
                           then c.min_days - extract(day from now() - o.created_at)::int end
                   ) order by c.sort)
              from cauris_costs c
              cross join orgs o
              left join cauris_unlocks u
                on u.org_id = p_org_id and u.feature = c.feature and u.until > now()
             where o.id = p_org_id), '[]'::jsonb),
        'progress', org_progress(p_org_id)
    ) end;
$$;

create or replace function set_cauris_cost(p_feature text, p_cost int)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Only the platform sets the cauris prices';
    end if;
    if p_cost is null or p_cost <= 0 or p_cost > 1000000 then
        raise exception 'Prix hors limites';
    end if;
    update cauris_costs set cost = p_cost where feature = p_feature;
    if not found then
        raise exception 'Outil inconnu : %', p_feature;
    end if;
end;
$$;

create or replace function cauris_costs_list()
returns setof cauris_costs
language sql
stable
security definer
set search_path = public, auth
as $$
    select * from cauris_costs
     where exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
     order by sort;
$$;

-- ------------------------------------------------------------
-- 5. Grants
-- ------------------------------------------------------------
revoke execute on function org_has(uuid, text)          from public;
revoke execute on function org_progress(uuid)           from public;
revoke execute on function spend_cauris(uuid, text)     from public;
revoke execute on function feature_states(uuid)         from public;
revoke execute on function set_cauris_cost(text, int)   from public;
revoke execute on function cauris_costs_list()          from public;
revoke execute on function storefront(text)             from public;
revoke execute on function storefront_photo_allowed(text) from public;
revoke execute on function storefront_directory(double precision, double precision) from public;
revoke execute on function wave_terms(uuid)             from public;
revoke execute on function org_delivers(uuid)           from public;
revoke execute on function trg_order_delivery_pro()     from public;
revoke execute on function trg_wave_order_pro()         from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function storefront(text)               to anon;
        grant execute on function storefront_photo_allowed(text) to anon;
        grant execute on function storefront_directory(double precision, double precision) to anon;
        revoke execute on function org_has(uuid, text)        from anon;
        revoke execute on function org_progress(uuid)         from anon;
        revoke execute on function spend_cauris(uuid, text)   from anon;
        revoke execute on function feature_states(uuid)       from anon;
        revoke execute on function set_cauris_cost(text, int) from anon;
        revoke execute on function cauris_costs_list()        from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function storefront(text)               to authenticated;
        grant execute on function storefront_photo_allowed(text) to authenticated;
        grant execute on function storefront_directory(double precision, double precision) to authenticated;
        grant execute on function wave_terms(uuid)               to authenticated;
        -- org_has is asked by RLS-adjacent guards as the caller: keep it
        -- callable, it says nothing a member cannot already see.
        grant execute on function org_has(uuid, text)            to authenticated;
        revoke execute on function org_progress(uuid)            from authenticated;
        grant execute on function spend_cauris(uuid, text)       to authenticated;
        grant execute on function feature_states(uuid)           to authenticated;
        grant execute on function set_cauris_cost(text, int)     to authenticated;
        grant execute on function cauris_costs_list()            to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
