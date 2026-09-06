-- ============================================================
-- 066_pro_gates.sql — where the line between Kaj and Kaj Pro is drawn, and held.
--
-- M10 block 2. 065 said which plan a business is on; this says what that
-- changes. The line itself lives in platform_settings, not in code, so it
-- moves without a migration: which tools are Pro, how many staff, invoices
-- a month and photos a Free business gets, and what Pro costs.
--
-- The rules:
--   * A Pro tool on a Free business answers 'view', never 'hidden'. The
--     owner keeps seeing the tool, greyed, with what it would give them.
--     The layer sits AFTER the owner's dial (031) and only ever lowers
--     'edit' to 'view' — a dial that says 'hidden' still wins below it.
--   * The platform admin is never gated: they run the platform.
--   * Enforced where it is cheap and matters: writes. Payroll (shifts,
--     staff_payments) and tontines get the 031 guard trigger with a Pro
--     message; the owner's dial (org_feature_rules) and the currency rates
--     demand 'edit' in their write policies; the three caps are BEFORE
--     INSERT triggers on memberships, invoices and documents, catching
--     every path that writes those rows without redefining any function.
--   * Read-only Pro tools (analytics, the accounting hub) are gated in the
--     app in this block. A signed-in owner who calls those functions by
--     hand reads their own figures; nobody reads anyone else's. Block 5
--     revisits this once money moves through the platform.
--   * Every refusal for the plan's reason starts with "Kaj Pro :" — the
--     app reads that prefix and opens the door to pay instead of an error.
--   * "J'ai payé" is a row in plan_requests the console lists; the platform
--     checks its Wave app and sets the plan (065). No money moves here.
--
-- Since 063 a new function is born closed to anon; the grants below say
-- exactly who may call what. feature_access() is a policy helper and keeps
-- the grants it has — `create or replace` preserves them.
-- ============================================================

-- ------------------------------------------------------------
-- 1. THE LINE, AS SETTINGS
-- ------------------------------------------------------------
insert into platform_settings (key, value) values
    ('pro_features',            '["payroll","team_access","analytics","accounting","currencies","tontines"]'),
    ('free_max_staff',          '3'),
    ('free_max_invoices_month', '20'),
    ('free_max_photos',         '50'),
    ('free_history_months',     '12'),
    ('pro_price_month',         '2500'),
    ('pro_price_year',          '25000'),
    ('pro_currency',            '"XOF"'),
    -- The number the owner pays to. Empty until the platform sets it from
    -- the console: a paywall with no number says "contact us" instead.
    ('platform_wave',           '""'),
    ('platform_wave_name',      '""')
on conflict (key) do nothing;

create or replace function plan_setting(p_key text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select value from platform_settings where key = p_key;
$$;

create or replace function plan_limit(p_key text, p_default int)
returns int
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        nullif(plan_setting(p_key) #>> '{}', '')::int,
        p_default);
$$;

-- Everything the paywall and the badges need, in one round trip. The prices
-- and the Wave number are public by nature — they are what the owner is
-- asked to pay and where — so any signed-in caller may read them.
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
        'platform_wave_name',      coalesce(plan_setting('platform_wave_name') #>> '{}', '')
    );
$$;

-- Is this tool behind the plan for this business right now? True only when
-- the business is Free and the tool is on the Pro list. The platform admin
-- and a caller with no session (a suite as postgres, a server job) are
-- never gated, exactly as feature_access() treats them.
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
       and org_plan(p_org_id) = 'free'
       and coalesce(plan_setting('pro_features'), '[]'::jsonb) ? p_feature;
$$;

-- ------------------------------------------------------------
-- 2. THE QUESTION EVERY GUARD ASKS, WITH ONE MORE LAYER
-- ------------------------------------------------------------
-- 041 verbatim, with the admin branch falling through to the plan layer
-- instead of returning at once, and the plan layer at the end: on a Free
-- business a Pro tool is 'view'. 'hidden' stays 'hidden' — the dial wins
-- below the plan.
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
    -- No session: fail closed, as 032 made it. A permission function's answer
    -- for "nobody signed in" must never be its most-open one.
    if auth.uid() is null then
        return 'hidden';
    end if;

    -- The platform runs the platform: every tool, on every plan.
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

        -- No rule set: full access by default, so a business that never
        -- touched the dial works exactly as before 031 — except reports,
        -- which 032 defaults to 'view'. Keep both.
        v_access := coalesce(v_access,
            case when p_feature = 'reports' then 'view' else 'edit' end);
    end if;

    -- The plan layer (066): a Pro tool on a Free business is 'view', never
    -- 'hidden'. Only ever lowers 'edit'; whatever the dial hid stays hidden.
    if v_access = 'edit'
       and org_plan(p_org_id) = 'free'
       and coalesce(plan_setting('pro_features'), '[]'::jsonb) ? p_feature then
        return 'view';
    end if;

    return v_access;
end;
$$;

-- ------------------------------------------------------------
-- 3. THE GUARDS
-- ------------------------------------------------------------
-- 031's guard, saying why. When the plan is the reason the message opens
-- the door to pay; otherwise it is the dial's own sentence, as before.
create or replace function trg_guard_feature_edit()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if feature_access(new.org_id, tg_argv[0]) <> 'edit' then
        if pro_locked(new.org_id, tg_argv[0]) then
            raise exception 'Kaj Pro : cet outil fait partie de Kaj Pro. Ouvrez Compte › Kaj Pro pour passer à la formule payante.';
        end if;
        raise exception '%', tg_argv[1];
    end if;
    return new;
end;
$$;

-- Payroll: a day worked and a wage paid. The 032 functions still make their
-- own membership checks; this adds the plan on top, on every path.
drop trigger if exists guard_payroll_shifts on shifts;
create trigger guard_payroll_shifts
before insert on shifts
for each row execute function trg_guard_feature_edit(
    'payroll', 'Les pointages vous sont fermés. Voyez le propriétaire.');

drop trigger if exists guard_payroll_payments on staff_payments;
create trigger guard_payroll_payments
before insert on staff_payments
for each row execute function trg_guard_feature_edit(
    'payroll', 'La paie vous est fermée. Voyez le propriétaire.');

-- Tontines: opening a new one. Rounds and contributions of an existing
-- tontine go on — a lapsed Pro loses nothing it started.
drop trigger if exists guard_tontines on tontines;
create trigger guard_tontines
before insert on tontines
for each row execute function trg_guard_feature_edit(
    'tontines', 'Les tontines vous sont fermées. Voyez le propriétaire.');

-- The owner's dial and the currency rates: their write policies demand
-- 'edit' on the Pro tool. Reading stays as it was, so a lapsed Pro's rules
-- and rates keep applying; they just cannot be changed until it pays.
drop policy if exists "feature rules written by admins" on org_feature_rules;
create policy "feature rules written by admins"
on org_feature_rules for all
using (is_org_admin(org_id) and feature_access(org_id, 'team_access') = 'edit')
with check (is_org_admin(org_id) and feature_access(org_id, 'team_access') = 'edit');

drop policy if exists "currency rates written by admins" on org_currency_rates;
create policy "currency rates written by admins"
on org_currency_rates for all
using (is_org_admin(org_id) and feature_access(org_id, 'currencies') = 'edit')
with check (is_org_admin(org_id) and feature_access(org_id, 'currencies') = 'edit');

-- ------------------------------------------------------------
-- 4. THE CAPS
-- ------------------------------------------------------------
-- One trigger function, three tables. Counts only when the business is
-- Free and the caller is neither the platform nor the furniture.
create or replace function trg_cap_free_plan()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_cap   int;
    v_count int;
begin
    if auth.uid() is null
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
       or org_plan(new.org_id) <> 'free' then
        return new;
    end if;

    if tg_table_name = 'memberships' then
        -- The owner is not staff. Everyone else with an account is.
        if new.role = 'owner' then return new; end if;
        v_cap := plan_limit('free_max_staff', 3);
        select count(*) into v_count from memberships
         where org_id = new.org_id and role <> 'owner';
        if v_count >= v_cap then
            raise exception 'Kaj Pro : la formule gratuite compte % comptes en plus du propriétaire. Ouvrez Compte › Kaj Pro pour en ajouter.', v_cap;
        end if;

    elsif tg_table_name = 'invoices' then
        v_cap := plan_limit('free_max_invoices_month', 20);
        select count(*) into v_count from invoices
         where org_id = new.org_id
           and issued_on >= date_trunc('month', coalesce(new.issued_on, current_date))::date
           and issued_on <  (date_trunc('month', coalesce(new.issued_on, current_date)) + interval '1 month')::date;
        if v_count >= v_cap then
            raise exception 'Kaj Pro : la formule gratuite permet % factures par mois. Ouvrez Compte › Kaj Pro pour continuer ce mois-ci.', v_cap;
        end if;

    elsif tg_table_name = 'documents' then
        v_cap := plan_limit('free_max_photos', 50);
        select count(*) into v_count from documents where org_id = new.org_id;
        if v_count >= v_cap then
            raise exception 'Kaj Pro : la formule gratuite garde % photos. Ouvrez Compte › Kaj Pro pour en ajouter.', v_cap;
        end if;
    end if;

    return new;
end;
$$;

drop trigger if exists cap_free_staff on memberships;
create trigger cap_free_staff
before insert on memberships
for each row execute function trg_cap_free_plan();

drop trigger if exists cap_free_invoices on invoices;
create trigger cap_free_invoices
before insert on invoices
for each row execute function trg_cap_free_plan();

drop trigger if exists cap_free_photos on documents;
create trigger cap_free_photos
before insert on documents
for each row execute function trg_cap_free_plan();

-- ------------------------------------------------------------
-- 5. "J'AI PAYÉ"
-- ------------------------------------------------------------
create table if not exists plan_requests (
    id          uuid primary key default gen_random_uuid(),
    org_id      uuid not null references orgs(id) on delete cascade,
    user_id     uuid not null references profiles(id),
    -- What the owner says they paid, in the platform's currency. Null when
    -- they did not say.
    amount      numeric(14, 2) check (amount is null or amount > 0),
    note        text,
    created_at  timestamptz not null default now(),
    handled_at  timestamptz,
    handled_by  uuid references profiles(id)
);

create index if not exists plan_requests_open
    on plan_requests (created_at desc) where handled_at is null;

comment on table plan_requests is
    'An owner tapped "J''ai payé". The platform checks its Wave app and sets '
    'the plan (set_org_plan), then marks the request handled. No money moves here.';

alter table plan_requests enable row level security;

-- The business's admins see their own requests; the platform sees all.
drop policy if exists "plan requests readable by org admins" on plan_requests;
create policy "plan requests readable by org admins"
on plan_requests for select using (is_org_admin(org_id));
-- No insert/update/delete policy: written only through the functions below.

-- An admin of the business says they paid. One open request per business:
-- tapping twice does not queue two.
create or replace function request_pro(
    p_org_id uuid,
    p_amount numeric default null,
    p_note   text    default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_id uuid;
begin
    if auth.uid() is null then
        raise exception 'request_pro() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur de l''entreprise peut demander Kaj Pro';
    end if;
    if p_amount is not null and p_amount <= 0 then
        raise exception 'Le montant doit être supérieur à zéro';
    end if;

    select id into v_id from plan_requests
     where org_id = p_org_id and handled_at is null
     order by created_at desc limit 1;
    if v_id is not null then
        update plan_requests
           set amount = coalesce(p_amount, amount),
               note   = coalesce(nullif(btrim(coalesce(p_note, '')), ''), note),
               user_id = auth.uid()
         where id = v_id;
        return v_id;
    end if;

    insert into plan_requests (org_id, user_id, amount, note)
    values (p_org_id, auth.uid(), p_amount,
            nullif(btrim(coalesce(p_note, '')), ''))
    returning id into v_id;
    return v_id;
end;
$$;

-- What the platform has to look at. Open requests, oldest first, with the
-- business and the person, legible without opening either.
create or replace function plan_requests_open()
returns table (
    id           uuid,
    org_id       uuid,
    org_name     text,
    org_plan     text,
    requested_by text,
    amount       numeric,
    note         text,
    created_at   timestamptz
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select r.id, r.org_id, o.name, org_plan(o.id),
           coalesce(p.full_name, p.phone, 'Inconnu'),
           r.amount, r.note, r.created_at
    from plan_requests r
    join orgs o on o.id = r.org_id
    left join profiles p on p.id = r.user_id
    where exists (select 1 from profiles
                  where id = auth.uid() and is_platform_admin)
      and r.handled_at is null
    order by r.created_at asc;
$$;

create or replace function handle_plan_request(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles
                   where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can handle a plan request';
    end if;
    update plan_requests
       set handled_at = now(), handled_by = auth.uid()
     where id = p_id and handled_at is null;
end;
$$;

-- ------------------------------------------------------------
-- 6. GRANTS
-- ------------------------------------------------------------
revoke execute on function plan_setting(text)                    from public;
revoke execute on function plan_limit(text, int)                 from public;
revoke execute on function plan_terms()                          from public;
revoke execute on function pro_locked(uuid, text)                from public;
revoke execute on function request_pro(uuid, numeric, text)      from public;
revoke execute on function plan_requests_open()                  from public;
revoke execute on function handle_plan_request(uuid)             from public;
revoke execute on function trg_cap_free_plan()                   from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant select on plan_requests to authenticated;
        grant execute on function plan_terms()                     to authenticated;
        grant execute on function pro_locked(uuid, text)           to authenticated;
        grant execute on function request_pro(uuid, numeric, text) to authenticated;
        grant execute on function plan_requests_open()             to authenticated;
        grant execute on function handle_plan_request(uuid)        to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
