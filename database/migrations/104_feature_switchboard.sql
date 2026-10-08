-- ============================================================
-- 104_feature_switchboard.sql — Mara's switchboard: what a store, a farm
-- or an association is shown, set by the platform, kept by the server.
--
-- The owner: « As an admin I need to be able to edit a store or a type of
-- business. To make features, options and setting visible or invisible for
-- a store or type of business. » And: « The new admin setup will not
-- modify anything to the stores and vitrine until I make the change
-- myself? » — so every switch starts at « Par défaut », which is today.
-- No paid feature is ever hidden.
--
--   1. feature_catalog: one row per tool that can be shown or hidden, with
--      the kinds of business that have it (an association has no
--      Production, no Analyses, no Corrections: the board does not offer
--      them there), its group, and the Pro tool (066) it is, if any. Only
--      what is wired end to end is in it: the app hides it where it is
--      drawn (homes, Compte, menus, its address) and the server refuses it
--      at its doors (section 4). See the list in section 2.
--   2. feature_rules: a kind's rule (every shop, every farm, every
--      association — a legacy church counts as an association) or one
--      business's rule, 'visible' or 'hidden', until a date if said. No
--      client writes it; members read only their own business's result,
--      through feature_states().
--   3. feature_hidden(org, key): the business's own rule (unexpired) over
--      its kind's (unexpired) over the catalog's default — and never for
--      a feature the business has PAID for: a Pro tool on a paid Mara Pro
--      (orgs.plan, until its date), or opened with the business's own
--      cauris (a cauris_unlocks row for it or for « pro_all » with no
--      gifted_by). A gift from Mara is not a payment.
--      feature_guard(org, key) refuses a hidden feature in French
--      (errcode MA002). Mara's own people meet it too inside a business —
--      they see what the business sees; only the command center's own
--      functions (platform_*) pass by it.
--   4. The doors: a trigger on each feature's tables (every writer, the
--      app's functions and a direct write alike) and the feature's reading
--      functions, rebuilt from their latest definitions with one guard.
--   5. platform_actions: the command center's journal — who, when, which
--      business, what it was and what it became, and how to undo it.
--      platform_undo(action) runs the undo only through a whitelist
--      (platform_undo_fns), once. platform_log_action() is what the other
--      platform functions (105–107) write it with.
--   6. platform_feature_board / platform_set_feature_rule /
--      platform_feature_impact: the switchboard itself, for a kind or a
--      business, the platform's only. A business's owner is told when
--      Mara changes one of its switches.
--   7. feature_states (102) gains 'hidden': the keys hidden for this
--      business — the app's one read.
--
-- Shops, farms and associations alike: the catalog says per feature which
-- kinds have it. Nothing changes for any of them until a rule is written.
--
-- Re-runnable (the bundle runs twice): tables and indexes if not exists,
-- catalog rows upserted, triggers dropped and recreated, functions
-- replaced in place.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Tables
-- ------------------------------------------------------------
create table if not exists feature_catalog (
    key                  text primary key,
    label                text not null,
    grp                  text not null,
    kinds                text[] not null,
    pro_tool             text,
    default_hidden_kinds text[] not null default '{}',
    sort                 int not null default 0
);
alter table feature_catalog enable row level security;
comment on table feature_catalog is
    'What the platform can show or hide (104), per kind of business. Read through platform_feature_board().';

create table if not exists feature_rules (
    id      uuid primary key default gen_random_uuid(),
    scope   text not null check (scope in ('kind', 'org')),
    kind    text,
    org_id  uuid references orgs(id) on delete cascade,
    feature text not null references feature_catalog(key) on delete cascade,
    state   text not null check (state in ('visible', 'hidden')),
    until   timestamptz,
    note    text,
    set_by  uuid references profiles(id) on delete set null,
    set_at  timestamptz not null default now(),
    constraint feature_rules_scope_shape check (
        (scope = 'kind' and kind in ('retail', 'farm', 'association') and org_id is null)
        or (scope = 'org' and org_id is not null and kind is null))
);
create unique index if not exists feature_rules_one_per_kind
    on feature_rules (kind, feature) where scope = 'kind';
create unique index if not exists feature_rules_one_per_org
    on feature_rules (org_id, feature) where scope = 'org';
alter table feature_rules enable row level security;
comment on table feature_rules is
    'A kind''s or one business''s switch (104). Written by platform_set_feature_rule() only.';

create table if not exists platform_actions (
    id        uuid primary key default gen_random_uuid(),
    at        timestamptz not null default now(),
    actor     uuid references profiles(id) on delete set null,
    org_id    uuid references orgs(id) on delete set null,
    kind      text not null,
    summary   text not null,
    before    jsonb,
    after     jsonb,
    undo_fn   text,
    undo_args jsonb,
    undone_at timestamptz,
    undone_by uuid references profiles(id) on delete set null
);
create index if not exists platform_actions_by_time on platform_actions (at desc);
create index if not exists platform_actions_by_org  on platform_actions (org_id, at desc);
alter table platform_actions enable row level security;
comment on table platform_actions is
    'The command center''s journal (104): every platform change, with its undo. Read through platform_actions_page().';

-- The functions platform_undo() may call. Each one takes the action's
-- undo_args (jsonb) and returns void; each migration adds its own.
create table if not exists platform_undo_fns (
    fn text primary key
);
alter table platform_undo_fns enable row level security;

-- No policies: read and written through the functions below only.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on feature_catalog, feature_rules, platform_actions, platform_undo_fns
            from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on feature_catalog, feature_rules, platform_actions, platform_undo_fns
            from anon;
    end if;
end $$;

-- ------------------------------------------------------------
-- 2. The catalog: only what is wired in the app and at the server
-- ------------------------------------------------------------
-- Keys are the app's own (031's dial and 066's Pro tools), so one key
-- means one tool everywhere.
insert into feature_catalog (key, label, grp, kinds, pro_tool, sort) values
    ('invoices',    'Factures',                          'Ventes et clients', '{retail,farm,association}', null,         10),
    ('credits',     'Carnet de crédit',                  'Ventes et clients', '{retail,farm,association}', null,         20),
    ('corrections', 'Corrections des ventes et livraisons', 'Ventes et clients', '{retail}',               null,         30),
    ('production',  'Production',                        'Fabrication',       '{retail,farm}',             null,         40),
    ('tontines',    'Tontines',                          'Épargne',           '{retail,farm,association}', 'tontines',   50),
    ('payroll',     'Paie et journées',                  'Équipe',            '{retail,farm,association}', 'payroll',    60),
    ('analytics',   'Analyses',                          'Rapports',          '{retail,farm}',             'analytics',  70),
    ('accounting',  'Comptabilité',                      'Rapports',          '{retail,farm,association}', 'accounting', 80)
on conflict (key) do update
    set label    = excluded.label,
        grp      = excluded.grp,
        kinds    = excluded.kinds,
        pro_tool = excluded.pro_tool,
        sort     = excluded.sort;

-- ------------------------------------------------------------
-- 3. Who sees what
-- ------------------------------------------------------------
-- The kind a business's rules are read under: a legacy church is an
-- association.
create or replace function org_kind(p_org uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select case when o.profile::text = 'church' then 'association' else o.profile::text end
      from orgs o where o.id = p_org;
$$;

-- A Pro tool the business paid for: a paid Mara Pro (the plan, until its
-- date), or the tool — or Mara Pro complet — opened with its own cauris.
-- What Mara gave (gifted_by) is not a payment.
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
          from feature_catalog c where c.key = p_key), false);
$$;

-- The business's rule (unexpired) over its kind's (unexpired) over the
-- catalog; a paid feature is never hidden.
create or replace function feature_hidden(p_org uuid, p_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_kind  text := org_kind(p_org);
    v_state text;
    c       feature_catalog%rowtype;
begin
    select * into c from feature_catalog where key = p_key;
    if not found or v_kind is null then
        return false;
    end if;
    select r.state into v_state from feature_rules r
     where r.scope = 'org' and r.org_id = p_org and r.feature = p_key
       and (r.until is null or r.until > now());
    if v_state is null then
        select r.state into v_state from feature_rules r
         where r.scope = 'kind' and r.kind = v_kind and r.feature = p_key
           and (r.until is null or r.until > now());
    end if;
    if coalesce(v_state, case when v_kind = any (c.default_hidden_kinds)
                              then 'hidden' else 'visible' end) <> 'hidden' then
        return false;
    end if;
    return not feature_paid(p_org, p_key);
end;
$$;

-- The door: a hidden feature is refused, in French, with its own code.
-- Called by INVOKER reads too, so it is the app's to execute; it answers
-- only for a member of the business (Mara's people included), and a
-- stranger learns nothing from it.
create or replace function feature_guard(p_org uuid, p_key text)
returns void
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if p_org is not null and is_org_member(p_org) and feature_hidden(p_org, p_key) then
        raise exception 'Cette fonction n''est pas disponible pour votre activité.'
            using errcode = 'MA002';
    end if;
end;
$$;

-- Every key hidden for this business, in the catalog's order.
create or replace function features_hidden_for(p_org uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(jsonb_agg(c.key order by c.sort, c.key), '[]'::jsonb)
      from feature_catalog c
     where feature_hidden(p_org, c.key);
$$;

-- ------------------------------------------------------------
-- 4. The doors
-- ------------------------------------------------------------
-- a) Every write: one trigger per table of each feature, as 031 and 066
--    guard theirs — the app's functions and a direct write alike. A job
--    with no signed-in caller passes (feature_guard answers only for a
--    member of the business).
create or replace function trg_feature_hidden()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org uuid;
begin
    if tg_nargs >= 3 then
        -- The row names its parent (an invoice's payment names the invoice).
        execute format('select org_id from %I where id = $1', tg_argv[1])
           into v_org using (to_jsonb(new) ->> tg_argv[2])::uuid;
    else
        v_org := (to_jsonb(new) ->> 'org_id')::uuid;
    end if;
    perform feature_guard(v_org, tg_argv[0]);
    return new;
end;
$$;

drop trigger if exists feature_hidden_invoices on invoices;
create trigger feature_hidden_invoices
before insert or update on invoices
for each row execute function trg_feature_hidden('invoices');

drop trigger if exists feature_hidden_invoice_payments on invoice_payments;
create trigger feature_hidden_invoice_payments
before insert on invoice_payments
for each row execute function trg_feature_hidden('invoices', 'invoices', 'invoice_id');

drop trigger if exists feature_hidden_debts on debts;
create trigger feature_hidden_debts
before insert on debts
for each row execute function trg_feature_hidden('credits');

drop trigger if exists feature_hidden_debt_payments on debt_payments;
create trigger feature_hidden_debt_payments
before insert on debt_payments
for each row execute function trg_feature_hidden('credits');

drop trigger if exists feature_hidden_tontines on tontines;
create trigger feature_hidden_tontines
before insert on tontines
for each row execute function trg_feature_hidden('tontines');

drop trigger if exists feature_hidden_tontine_members on tontine_members;
create trigger feature_hidden_tontine_members
before insert on tontine_members
for each row execute function trg_feature_hidden('tontines');

drop trigger if exists feature_hidden_tontine_contributions on tontine_contributions;
create trigger feature_hidden_tontine_contributions
before insert on tontine_contributions
for each row execute function trg_feature_hidden('tontines');

drop trigger if exists feature_hidden_production_runs on production_runs;
create trigger feature_hidden_production_runs
before insert or update on production_runs
for each row execute function trg_feature_hidden('production');

drop trigger if exists feature_hidden_shifts on shifts;
create trigger feature_hidden_shifts
before insert on shifts
for each row execute function trg_feature_hidden('payroll');

drop trigger if exists feature_hidden_staff_payments on staff_payments;
create trigger feature_hidden_staff_payments
before insert on staff_payments
for each row execute function trg_feature_hidden('payroll');

-- b) Every read, and the writes no table trigger can tell apart (a return
--    is a sale; a corrected delivery is a receipt): each function rebuilt
--    from its latest definition with one line, feature_guard. Grants are
--    kept by create or replace.
-- list_invoices (020): the list, guarded
create or replace function list_invoices(
    p_org_id       uuid,
    p_include_paid boolean default true,
    p_limit        int     default 200
)
returns table (
    invoice_id    uuid,
    number        text,
    customer_name text,
    issued_on     date,
    due_on        date,
    total         numeric,
    paid          numeric,
    outstanding   numeric,
    cancelled     boolean,
    days_overdue  int
)
language sql
stable
security invoker
set search_path = public
as $$
    select feature_guard(p_org_id, 'invoices');
    select
        i.id, i.number, c.name, i.issued_on, i.due_on, i.total,
        coalesce(p.paid, 0),
        i.total - coalesce(p.paid, 0),
        i.cancelled_at is not null,
        case
            when i.due_on is null or i.cancelled_at is not null then 0
            when i.total - coalesce(p.paid, 0) <= 0 then 0
            else greatest((current_date - i.due_on)::int, 0)
        end
    from invoices i
    join customers c on c.id = i.customer_id
    left join (
        select invoice_id, sum(amount) as paid
          from invoice_payments group by invoice_id
    ) p on p.invoice_id = i.id
    where i.org_id = p_org_id
      and (p_include_paid or i.total - coalesce(p.paid, 0) > 0)
    order by i.issued_on desc, i.number desc
    limit greatest(coalesce(p_limit, 200), 1);
$$;

-- invoice_header (020): one invoice, guarded
create or replace function invoice_header(p_invoice_id uuid)
returns table (
    invoice_id      uuid,
    number          text,
    issued_on       date,
    due_on          date,
    total           numeric,
    paid            numeric,
    outstanding     numeric,
    cancelled_at    timestamptz,
    customer_name   text,
    customer_phone  text,
    customer_address text,
    org_name        text,
    org_address     text,
    org_phone       text,
    org_email       text,
    org_tax_id      text,
    org_tax_label   text,
    org_currency    text,
    invoice_footer  text
)
language sql
stable
security invoker
set search_path = public
as $$
    select feature_guard((select i.org_id from invoices i where i.id = p_invoice_id), 'invoices');
    select
        i.id, i.number, i.issued_on, i.due_on, i.total,
        coalesce(p.paid, 0),
        i.total - coalesce(p.paid, 0),
        i.cancelled_at,
        c.name, c.phone, c.address,
        o.name, o.address, o.phone, o.email, o.tax_id, o.tax_label,
        o.default_currency, o.invoice_footer
    from invoices i
    join customers c on c.id = i.customer_id
    join orgs o      on o.id = i.org_id
    left join (
        select invoice_id, sum(amount) as paid
          from invoice_payments group by invoice_id
    ) p on p.invoice_id = i.id
    where i.id = p_invoice_id;
$$;

-- invoice_lines_of (020): its lines, guarded
create or replace function invoice_lines_of(p_invoice_id uuid)
returns table (
    description text,
    quantity    numeric,
    unit_price  numeric,
    amount      numeric
)
language sql
stable
security invoker
set search_path = public
as $$
    select feature_guard((select i.org_id from invoices i where i.id = p_invoice_id), 'invoices');
    -- The join to invoices is what makes RLS apply: invoice_lines is keyed by
    -- invoice_id and its own policy is written against the parent, so reading
    -- through the parent is how the tenant check happens.
    select l.description, l.quantity, l.unit_price, l.amount
      from invoice_lines l
      join invoices i on i.id = l.invoice_id
     where l.invoice_id = p_invoice_id
     order by l.id;
$$;

-- customer_debts (024): the carnet, guarded
create or replace function customer_debts(p_org_id uuid)
returns table (
    customer_id   uuid,
    customer_name text,
    phone         text,
    total_owed    numeric,
    oldest_debt   timestamptz,
    open_debts    int
)
language sql
stable
security invoker
set search_path = public
as $$
    select feature_guard(p_org_id, 'credits');
    select c.id, c.name, c.phone,
           sum(d.amount - coalesce(p.paid, 0)) as total_owed,
           min(d.occurred_at) filter (where d.amount > coalesce(p.paid, 0)),
           count(*) filter (where d.amount > coalesce(p.paid, 0))::int
      from debts d
      join customers c on c.id = d.customer_id
      left join lateral (
          select sum(amount) as paid from debt_payments where debt_id = d.id
      ) p on true
     where d.org_id = p_org_id
     group by c.id, c.name, c.phone
    having sum(d.amount - coalesce(p.paid, 0)) > 0
     order by min(d.occurred_at) filter (where d.amount > coalesce(p.paid, 0));
$$;

-- debts_of_customer (024): one customer's debts, guarded
create or replace function debts_of_customer(p_org_id uuid, p_customer_id uuid)
returns table (
    debt_id     uuid,
    label       text,
    amount      numeric,
    paid        numeric,
    remaining   numeric,
    occurred_at timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
    select feature_guard(p_org_id, 'credits');
    select d.id, d.label, d.amount, coalesce(p.paid, 0),
           d.amount - coalesce(p.paid, 0), d.occurred_at
      from debts d
      left join lateral (
          select sum(amount) as paid from debt_payments where debt_id = d.id
      ) p on true
     where d.org_id = p_org_id and d.customer_id = p_customer_id
     order by d.occurred_at;
$$;

-- tontine_round_status (025): a round, guarded
create or replace function tontine_round_status(p_tontine_id uuid)
returns table (
    member_id     uuid,
    member_name   text,
    phone         text,
    turn_position int,
    has_paid      boolean,
    is_taker      boolean
)
language sql
stable
security invoker
set search_path = public
as $$
    select feature_guard((select t.org_id from tontines t where t.id = p_tontine_id), 'tontines');
    select m.id, m.name, m.phone, m.position,
           exists (
               select 1 from tontine_contributions c
                where c.tontine_id = t.id
                  and c.member_id = m.id
                  and c.round = t.current_round),
           -- The pot rotates: position N takes round N, then N + count.
           ((t.current_round - 1) % (select count(*) from tontine_members
                                      where tontine_id = t.id)) + 1 = m.position
      from tontines t
      join tontine_members m on m.tontine_id = t.id
     where t.id = p_tontine_id
     order by m.position;
$$;

-- advance_tontine_round (025): closing a round, guarded
create or replace function advance_tontine_round(p_tontine_id uuid)
returns int
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org     uuid;
    v_round   int;
    v_unpaid  int;
begin
    select org_id, current_round into v_org, v_round
      from tontines where id = p_tontine_id and is_active;
    if not found then
        raise exception 'No such tontine';
    end if;
    if not can_write_org(v_org) then
        raise exception 'You cannot manage this tontine';
    end if;
    perform feature_guard(v_org, 'tontines');

    select count(*) into v_unpaid
      from tontine_members m
     where m.tontine_id = p_tontine_id
       and not exists (
           select 1 from tontine_contributions c
            where c.tontine_id = p_tontine_id
              and c.member_id = m.id and c.round = v_round);
    if v_unpaid > 0 then
        raise exception
            'Impossible de clore le tour : % membre(s) n''ont pas encore payé',
            v_unpaid;
    end if;

    update tontines set current_round = current_round + 1
     where id = p_tontine_id
    returning current_round into v_round;
    return v_round;
end;
$$;

-- production_history (026): the batches, guarded
create or replace function production_history(
    p_org_id uuid,
    p_limit  int default 50
)
returns table (
    run_id       uuid,
    product_name text,
    quantity     numeric,
    total_cost   numeric,
    unit_cost    numeric,
    occurred_at  timestamptz,
    inputs       jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
    select feature_guard(p_org_id, 'production');
    select r.id, r.product_name, r.quantity, r.total_cost, r.unit_cost,
           r.occurred_at,
           coalesce((
               select jsonb_agg(jsonb_build_object(
                          'name', i.name, 'quantity', i.quantity)
                      order by i.name)
               from production_inputs i
               where i.run_id = r.id
           ), '[]'::jsonb)
      from production_runs r
     where r.org_id = p_org_id
     order by r.occurred_at desc
     limit p_limit;
$$;

-- unpaid_shifts (012): what is owed, guarded
create or replace function unpaid_shifts(p_org_id uuid)
returns table (
    employee_id uuid,
    full_name   text,
    hours       numeric,
    shifts      int,
    owed        numeric
)
language sql
stable
security invoker
set search_path = public, auth
as $$
    select feature_guard(p_org_id, 'payroll');
    select
        e.id, e.full_name,
        coalesce(sum(s.hours), 0),
        count(s.id)::int,
        round(coalesce(sum(s.hours), 0) * e.hourly_rate, 2)
    from employees e
    join shifts s on s.employee_id = e.id and s.payment_id is null
    where e.org_id = p_org_id
    group by e.id, e.full_name, e.hourly_rate
    having coalesce(sum(s.hours), 0) > 0
    order by e.full_name;
$$;

-- farm_analytics (101): guarded before the Pro lock
create or replace function farm_analytics(
    p_org_id uuid,
    p_since  timestamptz default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
    v_tz      constant text := 'Africa/Ouagadougou';
    v_profile text;
    v_m0      timestamptz;
    v_m1      timestamptz;
    v_since   timestamptz := coalesce(p_since, '-infinity'::timestamptz);
    v_periods jsonb;
    v_out     jsonb;
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;
    select profile into v_profile from orgs where id = p_org_id;
    if v_profile in ('association', 'church') then
        raise exception 'Les analyses ne concernent pas une association';
    end if;
    perform feature_guard(p_org_id, 'analytics');
    if pro_locked(p_org_id, 'analytics') then
        raise exception 'Kaj Pro : les analyses font partie de Kaj Pro. Ouvrez Compte › Kaj Pro, ou débloquez-les avec vos cauris.';
    end if;

    v_m0 := date_trunc('month', now() at time zone v_tz) at time zone v_tz;
    v_m1 := (date_trunc('month', now() at time zone v_tz) - interval '1 month') at time zone v_tz;

    with periods(key, t0, t1) as (
        values ('month',      v_m0,    'infinity'::timestamptz),
               ('last_month', v_m1,    v_m0),
               ('window',     v_since, 'infinity'::timestamptz)
    ),
    money as (
        select je.created_at, a.type, a.name, jl.debit, jl.credit
          from journal_lines jl
          join journal_entries je on je.id = jl.journal_entry_id
          join accounts a on a.id = jl.account_id
         where je.org_id = p_org_id
           and a.type in ('income', 'expense')
    ),
    -- A finished order, dated when it was handed over or delivered: the
    -- sale written at that moment. Before 101 there is no such sale and
    -- the order's last change is the best date there is.
    done as (
        select o.total,
               coalesce((select s.occurred_at from sales s where s.order_id = o.id),
                        o.updated_at) as at
          from orders o
         where o.org_id = p_org_id and o.status in ('picked_up', 'delivered')
    )
    select jsonb_object_agg(pr.key, jsonb_build_object(
        'income', (select coalesce(sum(m.credit - m.debit), 0) from money m
                    where m.type = 'income' and m.created_at >= pr.t0 and m.created_at < pr.t1),
        'expenses', (select coalesce(sum(m.debit - m.credit), 0) from money m
                      where m.type = 'expense' and m.created_at >= pr.t0 and m.created_at < pr.t1),
        'eggs', (select coalesce(sum(ep.egg_count), 0) from egg_production ep
                  where ep.org_id = p_org_id
                    and ep.produced_on >= (pr.t0 at time zone v_tz)::date
                    and ep.produced_on <  (pr.t1 at time zone v_tz)::date),
        'deaths', (select trim_scale(coalesce(sum(fe.quantity), 0)) from flock_events fe
                    join flocks f on f.id = fe.flock_id
                   where f.org_id = p_org_id and fe.kind = 'mortality'
                     and fe.occurred_at >= pr.t0 and fe.occurred_at < pr.t1),
        'orders', (select count(*) from done d
                    where d.at >= pr.t0 and d.at < pr.t1),
        'orders_total', (select coalesce(sum(d.total), 0) from done d
                          where d.at >= pr.t0 and d.at < pr.t1),
        'production_cost', (select coalesce(sum(r.total_cost), 0) from production_runs r
                             where r.org_id = p_org_id
                               and r.occurred_at >= pr.t0 and r.occurred_at < pr.t1)
    ))
      into v_periods
      from periods pr;

    select jsonb_build_object(
        'periods', v_periods,
        -- What sold, best first: the sales' lines (a sale undone by a
        -- correction is out, as in 043). A finished vitrine order is a
        -- sale of its own since 101, so it is counted there, once.
        'products', coalesce((
            select jsonb_agg(jsonb_build_object('name', x.name, 'units', trim_scale(x.units),
                                                'revenue', x.revenue)
                             order by x.revenue desc, x.units desc, x.name)
              from (
                select min(s.name) as name, sum(s.quantity) as units,
                       sum(s.amount) as revenue
                  from (
                    select sl.name, sl.quantity, sl.line_total as amount
                      from sale_lines sl
                      join sales sa on sa.id = sl.sale_id
                     where sa.org_id = p_org_id and sa.kind = 'sale'
                       and not exists (select 1 from sales r where r.reverses_id = sa.id)
                       and sa.occurred_at >= v_since
                  ) s
                 group by lower(btrim(s.name))
                 limit 50
              ) x), '[]'::jsonb),
        -- Where the money went and came from, by the books' own accounts.
        'expenses', coalesce((
            select jsonb_agg(jsonb_build_object('name', y.name, 'amount', y.amount)
                             order by y.amount desc, y.name)
              from (select a.name, sum(jl.debit - jl.credit) as amount
                      from journal_lines jl
                      join journal_entries je on je.id = jl.journal_entry_id
                      join accounts a on a.id = jl.account_id
                     where je.org_id = p_org_id and a.type = 'expense'
                       and je.created_at >= v_since
                     group by a.name
                    having sum(jl.debit - jl.credit) > 0) y), '[]'::jsonb),
        'income', coalesce((
            select jsonb_agg(jsonb_build_object('name', y.name, 'amount', y.amount)
                             order by y.amount desc, y.name)
              from (select a.name, sum(jl.credit - jl.debit) as amount
                      from journal_lines jl
                      join journal_entries je on je.id = jl.journal_entry_id
                      join accounts a on a.id = jl.account_id
                     where je.org_id = p_org_id and a.type = 'income'
                       and je.created_at >= v_since
                     group by a.name
                    having sum(jl.credit - jl.debit) > 0) y), '[]'::jsonb),
        -- Each open flock: how many are left, how many died (in all and in
        -- the window), how well it lays.
        'flocks', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'batch_code', fs.batch_code, 'started', fs.started,
                       'alive', fs.alive, 'died', fs.died,
                       'died_window', (select trim_scale(coalesce(sum(fe.quantity), 0)) from flock_events fe
                                        where fe.flock_id = fs.flock_id and fe.kind = 'mortality'
                                          and fe.occurred_at >= v_since),
                       'eggs_7d', fs.eggs_7d, 'lay_rate', fs.lay_rate)
                   order by fs.batch_code)
              from flock_status(p_org_id) fs), '[]'::jsonb),
        -- What was eaten or used, item by item, this month against the last.
        'feed', coalesce((
            select jsonb_agg(jsonb_build_object('name', z.name, 'unit', z.unit,
                                                'month', trim_scale(z.month),
                                                'last_month', trim_scale(z.last_month),
                                                'window', trim_scale(z.win))
                             order by z.win desc, z.name)
              from (select i.name, i.unit,
                           coalesce(sum(sm.quantity) filter (where sm.occurred_at >= v_m0), 0) as month,
                           coalesce(sum(sm.quantity) filter (where sm.occurred_at >= v_m1
                                                               and sm.occurred_at < v_m0), 0) as last_month,
                           coalesce(sum(sm.quantity) filter (where sm.occurred_at >= v_since), 0) as win
                      from stock_movements sm
                      join items i on i.id = sm.item_id
                     where sm.org_id = p_org_id and sm.kind = 'consumed'
                     group by i.id, i.name, i.unit) z
             where z.win > 0 or z.month > 0 or z.last_month > 0), '[]'::jsonb),
        -- Money in and out by day, over the window.
        'daily', coalesce((
            select jsonb_agg(jsonb_build_object('day', d.day, 'income', d.income,
                                                'expenses', d.expenses) order by d.day)
              from (select (je.created_at at time zone v_tz)::date as day,
                           sum(case when a.type = 'income' then jl.credit - jl.debit else 0 end) as income,
                           sum(case when a.type = 'expense' then jl.debit - jl.credit else 0 end) as expenses
                      from journal_lines jl
                      join journal_entries je on je.id = jl.journal_entry_id
                      join accounts a on a.id = jl.account_id
                     where je.org_id = p_org_id and a.type in ('income', 'expense')
                       and je.created_at >= v_since
                     group by 1) d), '[]'::jsonb)
    ) into v_out;

    return v_out;
end;
$$;

-- org_sales_headline (101): guarded before the Pro lock
create or replace function org_sales_headline(
    p_org_id uuid,
    p_since  timestamptz default null
)
returns table (
    sale_count      bigint,
    revenue         numeric,
    cost            numeric,
    margin          numeric,
    units           numeric,
    avg_basket      numeric,
    products_sold   bigint
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;
    perform feature_guard(p_org_id, 'analytics');
    if pro_locked(p_org_id, 'analytics') then
        raise exception 'Kaj Pro : les analyses font partie de Kaj Pro. Ouvrez Compte › Kaj Pro, ou débloquez-les avec vos cauris.';
    end if;

    return query
    with s as (
        select sa.id, sa.total
        from sales sa
        where sa.org_id = p_org_id
          and sa.kind = 'sale'
          and not exists (select 1 from sales r where r.reverses_id = sa.id)
          and (p_since is null or sa.occurred_at >= p_since)
    ),
    lines as (
        select sl.quantity, sl.unit_cost, sl.line_total, sl.name
        from sale_lines sl
        join s on s.id = sl.sale_id
    )
    select
        (select count(*) from s),
        coalesce((select sum(total) from s), 0),
        coalesce((select sum(quantity * unit_cost) from lines), 0),
        coalesce((select sum(line_total) from lines), 0)
            - coalesce((select sum(quantity * unit_cost) from lines), 0),
        coalesce((select sum(quantity) from lines), 0),
        case when (select count(*) from s) = 0 then 0
             else round(coalesce((select sum(total) from s), 0)
                  / (select count(*) from s), 2) end,
        (select count(distinct lower(btrim(name))) from lines);
end;
$$;

-- org_product_performance (101): guarded before the Pro lock
create or replace function org_product_performance(
    p_org_id uuid,
    p_since  timestamptz default null,
    p_limit  int default 100
)
returns table (
    name          text,
    units         numeric,
    revenue       numeric,
    margin        numeric,
    sale_count    bigint,
    first_sold    timestamptz,
    last_sold     timestamptz,
    per_day       numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;
    perform feature_guard(p_org_id, 'analytics');
    if pro_locked(p_org_id, 'analytics') then
        raise exception 'Kaj Pro : les analyses font partie de Kaj Pro. Ouvrez Compte › Kaj Pro, ou débloquez-les avec vos cauris.';
    end if;

    return query
    with lines as (
        select lower(btrim(sl.name)) as key,
               sl.name as raw_name,
               sl.quantity, sl.unit_cost, sl.line_total, sa.occurred_at
        from sale_lines sl
        join sales sa on sa.id = sl.sale_id
        where sa.org_id = p_org_id
          and sa.kind = 'sale'
          and not exists (select 1 from sales r where r.reverses_id = sa.id)
          and (p_since is null or sa.occurred_at >= p_since)
    )
    select
        min(raw_name),
        sum(quantity),
        sum(line_total),
        sum(line_total) - sum(quantity * unit_cost),
        count(*),
        min(occurred_at),
        max(occurred_at),
        round(
            sum(quantity)
            / greatest(1, extract(epoch from (max(occurred_at) - min(occurred_at))) / 86400.0),
            2
        )
    from lines
    group by key
    order by 3 desc
    limit greatest(1, p_limit);
end;
$$;

-- org_sales_by_hour (101): guarded before the Pro lock
create or replace function org_sales_by_hour(
    p_org_id uuid,
    p_since  timestamptz default null
)
returns table (
    hour        int,
    sale_count  bigint,
    revenue     numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;
    perform feature_guard(p_org_id, 'analytics');
    if pro_locked(p_org_id, 'analytics') then
        raise exception 'Kaj Pro : les analyses font partie de Kaj Pro. Ouvrez Compte › Kaj Pro, ou débloquez-les avec vos cauris.';
    end if;

    return query
    select
        extract(hour from sa.occurred_at)::int,
        count(*),
        coalesce(sum(sa.total), 0)
    from sales sa
    where sa.org_id = p_org_id
      and sa.kind = 'sale'
      and not exists (select 1 from sales r where r.reverses_id = sa.id)
      and (p_since is null or sa.occurred_at >= p_since)
    group by 1
    order by 1;
end;
$$;

-- org_sales_by_weekday (101): guarded before the Pro lock
create or replace function org_sales_by_weekday(
    p_org_id uuid,
    p_since  timestamptz default null
)
returns table (
    dow         int,
    sale_count  bigint,
    revenue     numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;
    perform feature_guard(p_org_id, 'analytics');
    if pro_locked(p_org_id, 'analytics') then
        raise exception 'Kaj Pro : les analyses font partie de Kaj Pro. Ouvrez Compte › Kaj Pro, ou débloquez-les avec vos cauris.';
    end if;

    return query
    select
        extract(dow from sa.occurred_at)::int,
        count(*),
        coalesce(sum(sa.total), 0)
    from sales sa
    where sa.org_id = p_org_id
      and sa.kind = 'sale'
      and not exists (select 1 from sales r where r.reverses_id = sa.id)
      and (p_since is null or sa.occurred_at >= p_since)
    group by 1
    order by 1;
end;
$$;

-- org_sales_daily (101): guarded before the Pro lock
create or replace function org_sales_daily(
    p_org_id uuid,
    p_since  timestamptz default null
)
returns table (
    day         date,
    sale_count  bigint,
    revenue     numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
    if not has_full_visibility(p_org_id) then
        raise exception 'You cannot read this business''s analytics';
    end if;
    perform feature_guard(p_org_id, 'analytics');
    if pro_locked(p_org_id, 'analytics') then
        raise exception 'Kaj Pro : les analyses font partie de Kaj Pro. Ouvrez Compte › Kaj Pro, ou débloquez-les avec vos cauris.';
    end if;

    return query
    select
        (sa.occurred_at at time zone 'UTC')::date,
        count(*),
        coalesce(sum(sa.total), 0)
    from sales sa
    where sa.org_id = p_org_id
      and sa.kind = 'sale'
      and not exists (select 1 from sales r where r.reverses_id = sa.id)
      and (p_since is null or sa.occurred_at >= p_since)
    group by 1
    order by 1;
end;
$$;

-- chart_of_accounts (007): the chart, guarded
create or replace function chart_of_accounts(p_org_id uuid)
returns table (
    account_id  uuid,
    code        text,
    name        text,
    type        text,
    description text,
    is_active   boolean,
    balance     numeric,
    entry_count bigint
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select feature_guard(p_org_id, 'accounting');
    select
        a.id, a.code, a.name, a.type, a.description, a.is_active,
        coalesce(sum(
            case when a.type in ('asset', 'expense')
                 then jl.debit - jl.credit
                 else jl.credit - jl.debit
            end
        ), 0),
        count(jl.id)
    from accounts a
    left join journal_lines jl on jl.account_id = a.id
    where a.org_id = p_org_id
      and is_org_member(p_org_id)
    group by a.id, a.code, a.name, a.type, a.description, a.is_active
    order by a.code;
$$;

-- create_account (007): a new account, guarded
create or replace function create_account(
    p_org_id      uuid,
    p_name        text,
    p_type        text,
    p_description text default null,
    p_code        text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_name text := btrim(coalesce(p_name, ''));
    v_id   uuid;
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Only an administrator may change the chart of accounts';
    end if;
    perform feature_guard(p_org_id, 'accounting');
    if v_name = '' then
        raise exception 'An account needs a name';
    end if;
    if account_code_band(p_type) is null then
        raise exception 'Unknown account type: %', p_type;
    end if;

    if exists (
        select 1 from accounts a
        where a.org_id = p_org_id
          and a.type = p_type
          and lower(btrim(a.name)) = lower(v_name)
    ) then
        raise exception 'An account called % already exists', v_name;
    end if;

    insert into accounts (org_id, code, name, type, description, created_by)
    values (
        p_org_id,
        coalesce(nullif(btrim(coalesce(p_code, '')), ''), next_account_code(p_org_id, p_type)),
        v_name, p_type, nullif(btrim(coalesce(p_description, '')), ''), auth.uid()
    )
    returning id into v_id;

    return v_id;
end;
$$;

-- trial_balance (069): guarded after the dial
create or replace function trial_balance(
    p_org_id uuid, p_from date default null, p_to date default null)
returns table (code text, name text, type text,
               total_debit numeric, total_credit numeric, balance numeric)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
    perform require_feature(p_org_id, 'reports');
    perform feature_guard(p_org_id, 'accounting');
    return query select * from trial_balance_core(p_org_id, p_from, p_to);
end;
$$;

-- income_statement (069): guarded after the dial
create or replace function income_statement(
    p_org_id uuid, p_from date default null, p_to date default null)
returns table (section text, code text, name text, amount numeric)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
    perform require_feature(p_org_id, 'reports');
    perform feature_guard(p_org_id, 'accounting');
    return query select * from income_statement_core(p_org_id, p_from, p_to);
end;
$$;

-- balance_sheet (069): guarded after the dial
create or replace function balance_sheet(
    p_org_id uuid, p_as_of date default null)
returns table (section text, code text, name text, amount numeric)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
    perform require_feature(p_org_id, 'reports');
    perform feature_guard(p_org_id, 'accounting');
    return query select * from balance_sheet_core(p_org_id, p_as_of);
end;
$$;

-- account_ledger (069): guarded after the dial
create or replace function account_ledger(
    p_org_id uuid, p_account_id uuid,
    p_from date default null, p_to date default null, p_limit int default 200)
returns table (entry_id uuid, occurred_at timestamptz, label text, memo text,
               debit numeric, credit numeric, balance numeric,
               reversed boolean, recorded_by text)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
    perform require_feature(p_org_id, 'reports');
    perform feature_guard(p_org_id, 'accounting');
    return query select * from account_ledger_core(
        p_org_id, p_account_id, p_from, p_to, p_limit);
end;
$$;

-- reverse_receipt (042): a delivery undone, guarded
create or replace function reverse_receipt(
    p_receipt_id uuid,
    p_reason     text default null
)
returns uuid  -- the reversing ledger entry, or null when the delivery booked none
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
    v_rec   stock_receipts%rowtype;
    v_rev   uuid;
begin
    if v_actor is null then
        raise exception 'reverse_receipt() needs a signed-in caller';
    end if;

    select * into v_rec from stock_receipts where id = p_receipt_id;
    if v_rec.id is null then
        raise exception 'No such delivery';
    end if;

    if not is_org_admin(v_rec.org_id) then
        raise exception 'Only an owner or admin can reverse a delivery';
    end if;
    perform feature_guard(v_rec.org_id, 'corrections');

    if v_rec.reversed_at is not null then
        raise exception 'That delivery has already been reversed';
    end if;

    -- Take back exactly what this delivery added. Stock may go negative, as it
    -- may on a sale (011): a reversal that drives the count below zero is the
    -- true statement that the goods have since moved, not a reason to refuse.
    update products set quantity = quantity - v_rec.quantity
     where id = v_rec.product_id;

    -- Unwind the purchase in the books, if it posted one. reverse_entry swaps
    -- the debits and credits into a new entry dated now, so the correction
    -- lands in the current period and every report built on the ledger nets
    -- to zero without excluding anything.
    if v_rec.entry_id is not null then
        v_rev := reverse_entry(v_rec.entry_id, v_actor,
                               coalesce(p_reason, 'Correction'));
    end if;

    update stock_receipts
       set reversed_at = now(), reversed_by = v_actor
     where id = p_receipt_id;

    return v_rev;
end;
$$;

-- record_return (032): a sale undone, guarded
create or replace function record_return(
    p_sale_id     uuid,
    p_note        text default null,
    p_client_uuid uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_org      uuid;
    v_method   text;
    v_total    numeric;
    v_kind     text;
    v_return   uuid;
    v_existing uuid;
    v_line     record;
    v_entry    uuid;
begin
    select org_id, method, total, kind
      into v_org, v_method, v_total, v_kind
    from sales where id = p_sale_id;

    if v_org is null then
        raise exception 'No such sale';
    end if;

    -- SECURITY (032): a zero-total return posts no entry and so met no gate.
    if not can_write_org(v_org) then
        raise exception 'You cannot record a return for this business';
    end if;
    perform feature_guard(v_org, 'corrections');

    if v_kind = 'return' then
        raise exception 'That is already a return';
    end if;
    if v_method = 'credit' then
        raise exception 'A credit sale is settled in the carnet, not by a return';
    end if;
    if exists (select 1 from sales where reverses_id = p_sale_id) then
        raise exception 'That sale has already been returned';
    end if;

    if p_client_uuid is not null then
        select id into v_existing from sales
        where org_id = v_org and client_uuid = p_client_uuid;
        if v_existing is not null then
            return v_existing;
        end if;
    end if;

    insert into sales (org_id, kind, method, note, total, reverses_id,
                       recorded_by, client_uuid)
    values (v_org, 'return', v_method, p_note, v_total, p_sale_id,
            v_actor, p_client_uuid)
    returning id into v_return;

    for v_line in select * from sale_lines where sale_id = p_sale_id
    loop
        insert into sale_lines (sale_id, product_id, name, quantity,
                                unit_price, unit_cost, line_total)
        values (v_return, v_line.product_id, v_line.name, v_line.quantity,
                v_line.unit_price, v_line.unit_cost, v_line.line_total);

        update products set quantity = quantity + v_line.quantity
        where id = v_line.product_id;
    end loop;

    if v_total > 0 then
        v_entry := record_entry(
            p_org_id      => v_org,
            p_amount      => v_total,
            p_direction   => 'out',
            p_label       => 'Retour de vente',
            p_recorded_by => v_actor,
            p_category    => 'Ventes',
            p_method      => v_method,
            p_memo        => p_note,
            p_details     => jsonb_build_object('reverses', p_sale_id),
            p_client_uuid => p_client_uuid
        );
        update sales set entry_id = v_entry where id = v_return;
    end if;

    return v_return;
end;
$$;

-- spend_cauris (100): no unlock sold for a hidden tool
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
    v_after  int;
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur dépense les cauris de l''entreprise';
    end if;
    -- No cauris for a tool the platform hid here (104).
    perform feature_guard(p_org_id, c.key) from feature_catalog c where c.pro_tool = p_feature;
    select * into v_cost from cauris_costs where feature = p_feature;
    if not found or p_feature = 'photo_slot' then
        raise exception 'Cet outil ne s''ouvre pas avec des cauris';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if v_cost.min_days > 0 and v_org.created_at > now() - make_interval(days => v_cost.min_days) then
        raise exception 'Cet outil s''ouvre avec des cauris après % jours sur Mara', v_cost.min_days;
    end if;

    v_after := cauris_take(p_org_id, v_cost.cost,
                           p_feature || ':' || gen_random_uuid()::text, p_feature);

    select greatest(coalesce(u.until, now()), now()) + make_interval(days => v_days)
      into v_until
      from (select 1) x left join cauris_unlocks u
        on u.org_id = p_org_id and u.feature = p_feature;

    insert into cauris_unlocks (org_id, feature, until)
    values (p_org_id, p_feature, v_until)
    on conflict (org_id, feature) do update
        set until = excluded.until, updated_at = now(), note = null, gifted_by = null;

    return jsonb_build_object('feature', p_feature, 'until', v_until,
                              'balance', v_after);
end;
$$;

-- ------------------------------------------------------------
-- 5. The journal and its undo
-- ------------------------------------------------------------
-- Internal: the platform's functions write their line with it.
create or replace function platform_log_action(
    p_org       uuid,
    p_kind      text,
    p_summary   text,
    p_before    jsonb,
    p_after     jsonb,
    p_undo_fn   text,
    p_undo_args jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_id uuid;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    if p_undo_fn is not null
       and not exists (select 1 from platform_undo_fns where fn = p_undo_fn) then
        raise exception 'Annulation inconnue : %', p_undo_fn;
    end if;
    -- clock_timestamp(), not now(): the lines one call writes for many
    -- businesses (105's bulk) each have their own moment, in order.
    insert into platform_actions (at, actor, org_id, kind, summary, before, after, undo_fn, undo_args)
    values (clock_timestamp(), auth.uid(), p_org, coalesce(nullif(btrim(p_kind), ''), 'other'),
            coalesce(nullif(btrim(p_summary), ''), p_kind), p_before, p_after,
            p_undo_fn, case when p_undo_fn is null then null else p_undo_args end)
    returning id into v_id;
    return v_id;
end;
$$;

-- « Annuler »: the action's undo, through the whitelist, once.
create or replace function platform_undo(p_action uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    a platform_actions%rowtype;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    select * into a from platform_actions where id = p_action for update;
    if not found then
        raise exception 'Action introuvable';
    end if;
    if a.undone_at is not null then
        raise exception 'Cette action a déjà été annulée.';
    end if;
    if a.undo_fn is null then
        raise exception 'Cette action ne s''annule pas.';
    end if;
    if not exists (select 1 from platform_undo_fns where fn = a.undo_fn) then
        raise exception 'Annulation inconnue : %', a.undo_fn;
    end if;
    execute format('select %I($1)', a.undo_fn) using coalesce(a.undo_args, '{}'::jsonb);
    update platform_actions set undone_at = now(), undone_by = auth.uid() where id = p_action;
end;
$$;

-- The journal: newest first, for one business or all of them. Paged by
-- (at, id): the next page is p_before = the last line's at and
-- p_before_id = its id, so lines that share a moment are never skipped.
drop function if exists platform_actions_page(uuid, int, timestamptz);
create or replace function platform_actions_page(
    p_org       uuid        default null,
    p_limit     int         default 50,
    p_before    timestamptz default null,
    p_before_id uuid        default null
)
returns table (
    id              uuid,
    at              timestamptz,
    actor_id        uuid,
    actor_label     text,
    org_id          uuid,
    org_name        text,
    kind            text,
    summary         text,
    before          jsonb,
    after           jsonb,
    undoable        boolean,
    undone_at       timestamptz,
    undone_by_label text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    return query
    select a.id, a.at, a.actor,
           coalesce(nullif(btrim(pa.full_name), ''), 'Mara'),
           a.org_id, o.name, a.kind, a.summary, a.before, a.after,
           a.undo_fn is not null and a.undone_at is null
               and exists (select 1 from platform_undo_fns f where f.fn = a.undo_fn),
           a.undone_at,
           case when a.undone_at is not null
                then coalesce(nullif(btrim(pu.full_name), ''), 'Mara') end
      from platform_actions a
      left join orgs o      on o.id  = a.org_id
      left join profiles pa on pa.id = a.actor
      left join profiles pu on pu.id = a.undone_by
     where (p_org is null or a.org_id = p_org)
       and (p_before is null
            or a.at < p_before
            or (a.at = p_before and p_before_id is not null and a.id < p_before_id))
     order by a.at desc, a.id desc
     limit greatest(1, least(coalesce(p_limit, 50), 200));
end;
$$;

-- ------------------------------------------------------------
-- 6. The switchboard
-- ------------------------------------------------------------
-- One rule as the journal keeps it (null: « Par défaut »).
create or replace function feature_rule_json(p_scope text, p_kind text, p_org uuid, p_feature text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object('state', r.state, 'until', r.until, 'note', r.note)
      from feature_rules r
     where r.feature = p_feature
       and ((p_scope = 'kind' and r.scope = 'kind' and r.kind = p_kind)
            or (p_scope = 'org' and r.scope = 'org' and r.org_id = p_org));
$$;

-- For a kind (p_kind) or one business (p_org): each feature it has, the
-- switch at that level, what it comes to, and why.
create or replace function platform_feature_board(p_kind text default null, p_org uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_kind text;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    if p_org is not null then
        v_kind := org_kind(p_org);
        if v_kind is null then
            raise exception 'Entreprise inconnue';
        end if;
    else
        v_kind := case when p_kind = 'church' then 'association' else p_kind end;
        if v_kind is null or v_kind not in ('retail', 'farm', 'association') then
            raise exception 'Genre d''activité inconnu : %', coalesce(p_kind, '');
        end if;
    end if;

    return coalesce((
        select jsonb_agg(jsonb_build_object(
                   'key', c.key,
                   'label', c.label,
                   'grp', c.grp,
                   'kinds', to_jsonb(c.kinds),
                   'pro_tool', c.pro_tool,
                   'state', coalesce(own.state, 'default'),
                   'until', own.until,
                   'note', own.note,
                   'effective', case
                       when p_org is not null then
                           case when feature_hidden(p_org, c.key) then 'hidden' else 'visible' end
                       else coalesce(kr.state,
                                     case when v_kind = any (c.default_hidden_kinds)
                                          then 'hidden' else 'visible' end)
                   end,
                   'source', case
                       when own.state is not null then case when p_org is null then 'kind' else 'org' end
                       when p_org is not null and kr.state is not null then 'kind'
                       else 'catalog'
                   end,
                   'paid', p_org is not null and feature_paid(p_org, c.key)
               ) order by c.sort, c.key)
          from feature_catalog c
          left join lateral (
              select r.state, r.until, r.note from feature_rules r
               where r.feature = c.key and (r.until is null or r.until > now())
                 and ((p_org is null and r.scope = 'kind' and r.kind = v_kind)
                      or (p_org is not null and r.scope = 'org' and r.org_id = p_org))
          ) own on true
          left join lateral (
              select r.state from feature_rules r
               where r.feature = c.key and r.scope = 'kind' and r.kind = v_kind
                 and (r.until is null or r.until > now())
          ) kr on true
         where v_kind = any (c.kinds)), '[]'::jsonb);
end;
$$;

-- What a kind's switch would touch: the businesses of that kind, how many
-- keep a switch of their own, how many paid for it (they keep it).
create or replace function platform_feature_impact(p_kind text, p_feature text, p_state text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_kind text := case when p_kind = 'church' then 'association' else p_kind end;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    if not exists (select 1 from feature_catalog where key = p_feature) then
        raise exception 'Fonction inconnue : %', coalesce(p_feature, '');
    end if;
    return (
        with o as (
            select o.id from orgs o
             where o.archived_at is null and org_kind(o.id) = v_kind
        )
        select jsonb_build_object(
            'orgs', (select count(*) from o),
            'overridden', (select count(*) from o
                            where exists (select 1 from feature_rules r
                                           where r.scope = 'org' and r.org_id = o.id
                                             and r.feature = p_feature
                                             and (r.until is null or r.until > now()))),
            'paid', case when p_state = 'hidden'
                         then (select count(*) from o where feature_paid(o.id, p_feature))
                         else 0 end)
    );
end;
$$;

-- The switch itself. 'default' clears it. A business's paid feature is
-- never hidden; at the kind's level a paying business simply keeps it.
-- Logged with its undo; a business's owner is told.
create or replace function platform_set_feature_rule(
    p_scope   text,
    p_kind    text,
    p_org     uuid,
    p_feature text,
    p_state   text,
    p_until   timestamptz default null,
    p_note    text        default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_kind   text := case when p_kind = 'church' then 'association' else p_kind end;
    v_note   text := nullif(btrim(coalesce(p_note, '')), '');
    v_before jsonb;
    v_after  jsonb;
    v_name   text;
    v_label  text;
    c        feature_catalog%rowtype;
    v_action uuid;
    v_what   text;
    v_org    uuid := case when p_scope = 'org' then p_org end;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    select * into c from feature_catalog where key = p_feature;
    if not found then
        raise exception 'Fonction inconnue : %', coalesce(p_feature, '');
    end if;
    if p_state is null or p_state not in ('default', 'visible', 'hidden') then
        raise exception 'Réglage inconnu : %', coalesce(p_state, '');
    end if;
    if p_until is not null and p_until <= now() then
        raise exception 'La date de fin doit être dans le futur';
    end if;

    if p_scope = 'kind' then
        if v_kind is null or v_kind not in ('retail', 'farm', 'association') then
            raise exception 'Genre d''activité inconnu : %', coalesce(p_kind, '');
        end if;
    elsif p_scope = 'org' then
        select name into v_name from orgs where id = p_org;
        if not found then
            raise exception 'Entreprise inconnue';
        end if;
        v_kind := org_kind(p_org);
    else
        raise exception 'Portée inconnue : %', coalesce(p_scope, '');
    end if;
    if not (v_kind = any (c.kinds)) then
        raise exception 'Cette fonction n''existe pas pour ce genre d''activité.';
    end if;
    if p_scope = 'org' and p_state = 'hidden' and feature_paid(p_org, p_feature) then
        raise exception 'Fonction payée par l''activité : elle ne peut pas être masquée.';
    end if;

    v_before := feature_rule_json(p_scope, v_kind, p_org, p_feature);
    if p_state = 'default' then
        delete from feature_rules r
         where r.feature = p_feature
           and ((p_scope = 'kind' and r.scope = 'kind' and r.kind = v_kind)
                or (p_scope = 'org' and r.scope = 'org' and r.org_id = p_org));
    elsif p_scope = 'kind' then
        insert into feature_rules (scope, kind, feature, state, until, note, set_by)
        values ('kind', v_kind, p_feature, p_state, p_until, v_note, auth.uid())
        on conflict (kind, feature) where scope = 'kind' do update
            set state = excluded.state, until = excluded.until, note = excluded.note,
                set_by = excluded.set_by, set_at = now();
    else
        insert into feature_rules (scope, org_id, feature, state, until, note, set_by)
        values ('org', p_org, p_feature, p_state, p_until, v_note, auth.uid())
        on conflict (org_id, feature) where scope = 'org' do update
            set state = excluded.state, until = excluded.until, note = excluded.note,
                set_by = excluded.set_by, set_at = now();
    end if;
    v_after := feature_rule_json(p_scope, v_kind, p_org, p_feature);

    -- Nothing moved: nothing to log, nobody to tell.
    if v_before is not distinct from v_after then
        return null;
    end if;

    v_label := c.label;
    v_what := case p_state
        when 'hidden'  then 'masqué'
        when 'visible' then 'rendu visible'
        else 'remis par défaut' end;
    v_action := platform_log_action(
        v_org,
        'feature_rule',
        '« ' || v_label || ' » ' || v_what || ' — '
            || case when p_scope = 'kind'
                    then case v_kind when 'retail' then 'toutes les boutiques'
                                     when 'farm' then 'toutes les fermes'
                                     else 'toutes les associations' end
                    else v_name end
            || case when p_until is not null
                    then ' (jusqu''au ' || to_char(p_until at time zone 'Africa/Ouagadougou', 'DD/MM/YYYY') || ')'
                    else '' end,
        v_before,
        v_after,
        'platform_restore_feature_rule',
        jsonb_build_object('scope', p_scope, 'kind', case when p_scope = 'kind' then v_kind end,
                           'org_id', v_org, 'feature', p_feature,
                           'rule', v_before, 'expect', v_after));

    if p_scope = 'org' then
        perform notify_org_owners(p_org, 'feature_rule',
            case p_state
                when 'hidden'  then 'Mara a masqué « ' || v_label || ' » pour votre activité.'
                when 'visible' then 'Mara a rendu « ' || v_label || ' » visible pour votre activité.'
                else 'Mara a remis « ' || v_label || ' » comme par défaut pour votre activité.' end,
            jsonb_build_object('feature', p_feature, 'label', v_label, 'state', p_state,
                               'until', p_until));
    end if;
    return v_action;
end;
$$;

-- The undo of a switch: the rule as it was — unless it changed since, in
-- which case the newer action is undone first.
create or replace function platform_restore_feature_rule(p_args jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_scope   text  := p_args->>'scope';
    v_kind    text  := p_args->>'kind';
    v_org     uuid  := nullif(p_args->>'org_id', '')::uuid;
    v_feature text  := p_args->>'feature';
    v_rule    jsonb := nullif(p_args->'rule', 'null'::jsonb);
    v_label   text;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    if feature_rule_json(v_scope, v_kind, v_org, v_feature)
       is distinct from nullif(p_args->'expect', 'null'::jsonb) then
        raise exception 'Ce réglage a changé depuis : annulez d''abord le changement plus récent.';
    end if;
    delete from feature_rules r
     where r.feature = v_feature
       and ((v_scope = 'kind' and r.scope = 'kind' and r.kind = v_kind)
            or (v_scope = 'org' and r.scope = 'org' and r.org_id = v_org));
    if v_rule is not null then
        insert into feature_rules (scope, kind, org_id, feature, state, until, note, set_by)
        values (v_scope, case when v_scope = 'kind' then v_kind end,
                case when v_scope = 'org' then v_org end, v_feature,
                v_rule->>'state', nullif(v_rule->>'until', '')::timestamptz,
                v_rule->>'note', auth.uid());
    end if;
    if v_scope = 'org' then
        select label into v_label from feature_catalog where key = v_feature;
        perform notify_org_owners(v_org, 'feature_rule',
            case coalesce(v_rule->>'state', 'default')
                when 'hidden'  then 'Mara a masqué « ' || v_label || ' » pour votre activité.'
                when 'visible' then 'Mara a rendu « ' || v_label || ' » visible pour votre activité.'
                else 'Mara a remis « ' || v_label || ' » comme par défaut pour votre activité.' end,
            jsonb_build_object('feature', v_feature, 'label', v_label,
                               'state', coalesce(v_rule->>'state', 'default')));
    end if;
end;
$$;

insert into platform_undo_fns (fn) values ('platform_restore_feature_rule')
on conflict (fn) do nothing;

-- ------------------------------------------------------------
-- 7. feature_states: 102's, with what the platform hid
-- ------------------------------------------------------------
create or replace function feature_states(p_org_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not is_org_member(p_org_id) then
        return null;
    end if;
    perform cauris_expire(p_org_id);
    return jsonb_build_object(
        'plan', org_plan(p_org_id),
        'balance', cauris_balance(p_org_id),
        'tools', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'feature', c.feature,
                       'cost', c.cost,
                       'until', u.until,
                       'gift', u.gifted_by is not null,
                       'waits_days', case
                           when c.min_days > 0
                            and o.created_at > now() - make_interval(days => c.min_days)
                           then c.min_days - extract(day from now() - o.created_at)::int end
                   ) order by c.sort)
              from cauris_costs c
              cross join orgs o
              left join cauris_unlocks u
                on u.org_id = p_org_id and u.feature = c.feature and u.until > now()
             where o.id = p_org_id and c.feature <> 'photo_slot'), '[]'::jsonb),
        'progress', org_progress(p_org_id),
        'wave_allowed', coalesce((select wave_allowed from orgs where id = p_org_id), false),
        'setup_done', org_setup_done(p_org_id),
        'first_income', (select case when o.profile::text in ('association', 'church')
                                     then org_first_income(p_org_id) end
                           from orgs o where o.id = p_org_id),
        'promo', cauris_promo_left(p_org_id),
        'photos', photo_state(p_org_id),
        'team', team_seats(p_org_id),
        'hidden', features_hidden_for(p_org_id)
    );
end;
$$;

-- ------------------------------------------------------------
-- Grants: born closed (063); each opened to whom it is for.
-- ------------------------------------------------------------
revoke execute on function org_kind(uuid)                                   from public;
revoke execute on function feature_paid(uuid, text)                         from public;
revoke execute on function feature_hidden(uuid, text)                       from public;
revoke execute on function feature_guard(uuid, text)                        from public;
revoke execute on function features_hidden_for(uuid)                        from public;
revoke execute on function trg_feature_hidden()                             from public;
revoke execute on function platform_log_action(uuid, text, text, jsonb, jsonb, text, jsonb) from public;
revoke execute on function platform_undo(uuid)                              from public;
revoke execute on function platform_actions_page(uuid, int, timestamptz, uuid)    from public;
revoke execute on function feature_rule_json(text, text, uuid, text)        from public;
revoke execute on function platform_feature_board(text, uuid)               from public;
revoke execute on function platform_feature_impact(text, text, text)        from public;
revoke execute on function platform_set_feature_rule(text, text, uuid, text, text, timestamptz, text) from public;
revoke execute on function platform_restore_feature_rule(jsonb)             from public;
revoke execute on function feature_states(uuid)                             from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function org_kind(uuid)                                   from anon;
        revoke execute on function feature_paid(uuid, text)                         from anon;
        revoke execute on function feature_hidden(uuid, text)                       from anon;
        revoke execute on function feature_guard(uuid, text)                        from anon;
        revoke execute on function features_hidden_for(uuid)                        from anon;
        revoke execute on function trg_feature_hidden()                             from anon;
        revoke execute on function platform_log_action(uuid, text, text, jsonb, jsonb, text, jsonb) from anon;
        revoke execute on function platform_undo(uuid)                              from anon;
        revoke execute on function platform_actions_page(uuid, int, timestamptz, uuid)    from anon;
        revoke execute on function feature_rule_json(text, text, uuid, text)        from anon;
        revoke execute on function platform_feature_board(text, uuid)               from anon;
        revoke execute on function platform_feature_impact(text, text, text)        from anon;
        revoke execute on function platform_set_feature_rule(text, text, uuid, text, text, timestamptz, text) from anon;
        revoke execute on function platform_restore_feature_rule(jsonb)             from anon;
        revoke execute on function feature_states(uuid)                             from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: read by the functions and triggers above, as their owner.
        revoke execute on function org_kind(uuid)                                   from authenticated;
        revoke execute on function feature_paid(uuid, text)                         from authenticated;
        revoke execute on function feature_hidden(uuid, text)                       from authenticated;
        revoke execute on function features_hidden_for(uuid)                        from authenticated;
        revoke execute on function trg_feature_hidden()                             from authenticated;
        revoke execute on function platform_log_action(uuid, text, text, jsonb, jsonb, text, jsonb) from authenticated;
        revoke execute on function feature_rule_json(text, text, uuid, text)        from authenticated;
        revoke execute on function platform_restore_feature_rule(jsonb)             from authenticated;
        -- The doors; each checks who is asking (the platform's, or a member's).
        grant execute on function platform_undo(uuid)                              to authenticated;
        grant execute on function platform_actions_page(uuid, int, timestamptz, uuid)    to authenticated;
        grant execute on function platform_feature_board(text, uuid)               to authenticated;
        grant execute on function platform_feature_impact(text, text, text)        to authenticated;
        grant execute on function platform_set_feature_rule(text, text, uuid, text, text, timestamptz, text) to authenticated;
        grant execute on function feature_states(uuid)                             to authenticated;
        -- The INVOKER reads above call it as their caller.
        grant execute on function feature_guard(uuid, text)                        to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
