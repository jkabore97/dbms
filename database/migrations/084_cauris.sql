-- ============================================================
-- 084_cauris.sql — cauris: Mara's points, earned by doing well.
--
-- The owner's model: a business that does well earns « cauris » and spends
-- them on what Mara Pro gives (085); a weekly score ranks it in its league
-- (086). This file is the earning side only, as decided: run it with real
-- shops, tune the numbers from the console, then let cauris buy things.
--
--   1. cauris_rules: what each act earns, and its daily cap — the
--      platform's numbers, changed from the console (set_cauris_rule),
--      never a deploy. A few parameters sit in platform_settings: the
--      smallest order that counts, how many orders per customer per day,
--      the minutes for a quick acceptance, the days before an idle wallet
--      expires.
--   2. cauris_ledger: every gain and loss, written once, never edited.
--      (org, reason, ref) is unique, so an event delivered twice — a
--      status set again, a page reloaded — earns once. The balance is
--      the sum; there is no other place it is kept.
--   3. Earned by what is hard to fake, from the events themselves:
--      an order picked up or delivered (not from the business's own people,
--      not under the smallest amount, at most N per customer a day); a
--      customer who comes back within 30 days; a pending order accepted
--      within 15 minutes; a distinct visitor on the vitrine (capped, signed
--      members of the business never count); the till used 7 days running;
--      a farm's daily log; the vitrine complete; a business it brought in
--      that took off. Lost: an accepted order the business cancels.
--   4. Expiry: a wallet with no movement for 180 days (the parameter) is
--      emptied by an « expired » line, written when it is next read or
--      next earns — no scheduler needed.
--   5. Reading: my_cauris() for the business's admins (balance, this
--      week's score, the history, when it would expire); cauris_watch()
--      for the platform — the top earners of the week and how much of
--      their orders came from one customer, the shape of an abuse.
--
-- Every function here is born closed (063) and Supabase's default
-- privileges hand new functions to authenticated: the internal ones are
-- revoked from it by name, the readers granted by name.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The rules and their parameters
-- ------------------------------------------------------------
create table if not exists cauris_rules (
    key       text primary key,
    points    integer not null,
    daily_cap integer check (daily_cap is null or daily_cap > 0),
    label     text not null,
    sort      integer not null default 0
);
alter table cauris_rules enable row level security;

insert into cauris_rules (key, points, daily_cap, label, sort) values
    ('order_done',         10, null, 'Commande terminée',                      10),
    ('returning_customer', 15, null, 'Un client revenu',                       20),
    ('quick_accept',        3, null, 'Commande acceptée en moins de 15 min',   30),
    ('visitor',             1,   30, 'Un visiteur sur la vitrine',             40),
    ('till_streak',        20, null, 'Caisse tenue 7 jours de suite',          50),
    ('farm_log',            5,    1, 'Cahier de la ferme tenu',                60),
    ('vitrine_complete',   50, null, 'Vitrine complète',                       70),
    ('referral',          200, null, 'Une entreprise parrainée a décollé',     80),
    ('lesson',             10, null, 'Leçon de l''Académie Mara',              90),
    ('shop_cancel',       -10, null, 'Commande acceptée puis annulée',        100)
on conflict (key) do nothing;

insert into platform_settings (key, value) values
    ('cauris_order_min',          '500'),
    ('cauris_orders_per_customer', '2'),
    ('cauris_quick_minutes',      '15'),
    ('cauris_expire_days',       '180')
on conflict (key) do nothing;

-- Who brought a business in (a referral), set once by its admin.
alter table orgs add column if not exists referred_by uuid references orgs(id) on delete set null;

-- ------------------------------------------------------------
-- 2. The ledger
-- ------------------------------------------------------------
create table if not exists cauris_ledger (
    id         bigserial primary key,
    org_id     uuid not null references orgs(id) on delete cascade,
    delta      integer not null check (delta <> 0),
    reason     text not null,
    ref        text not null,
    note       text,
    created_at timestamptz not null default now(),
    unique (org_id, reason, ref)
);
create index if not exists cauris_ledger_by_org on cauris_ledger (org_id, created_at desc);
alter table cauris_ledger enable row level security;
-- No policies: read through my_cauris(), written by the functions below.

-- Distinct visitors of a vitrine, a day (the device's own random id).
create table if not exists storefront_visitors (
    day     date not null,
    org_id  uuid not null references orgs(id) on delete cascade,
    visitor text not null,
    primary key (day, org_id, visitor)
);
alter table storefront_visitors enable row level security;

create or replace function cauris_param(p_key text, p_default int)
returns int
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((select (value #>> '{}')::int
                       from platform_settings where key = p_key), p_default);
$$;

create or replace function cauris_today()
returns date
language sql
stable
as $$ select (now() at time zone 'Africa/Ouagadougou')::date $$;

create or replace function cauris_balance(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(sum(delta), 0)::int from cauris_ledger where org_id = p_org_id;
$$;

-- An idle wallet empties itself: one « expired » line, the day it is seen.
create or replace function cauris_expire(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_last    timestamptz;
    v_balance int;
begin
    select max(created_at) into v_last from cauris_ledger where org_id = p_org_id;
    if v_last is null
       or v_last > now() - make_interval(days => cauris_param('cauris_expire_days', 180)) then
        return;
    end if;
    v_balance := cauris_balance(p_org_id);
    if v_balance > 0 then
        insert into cauris_ledger (org_id, delta, reason, ref, note)
        values (p_org_id, -v_balance, 'expired', cauris_today()::text,
                'Cauris non utilisés depuis ' || cauris_param('cauris_expire_days', 180) || ' jours')
        on conflict do nothing;
    end if;
end;
$$;

-- The one way cauris are earned or lost: by rule, capped, once per ref.
-- Returns what was written (0 when nothing was).
create or replace function cauris_award(
    p_org_id uuid,
    p_reason text,
    p_ref    text,
    p_note   text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_rule  cauris_rules%rowtype;
    v_today int;
    v_n     int;
begin
    select * into v_rule from cauris_rules where key = p_reason;
    if not found or v_rule.points = 0 or p_org_id is null then
        return 0;
    end if;
    -- An association does not compete (the owner's call): no cauris.
    if exists (select 1 from orgs where id = p_org_id
                and profile in ('church', 'association')) then
        return 0;
    end if;
    perform cauris_expire(p_org_id);
    if v_rule.daily_cap is not null then
        select count(*) into v_today from cauris_ledger
         where org_id = p_org_id and reason = p_reason
           and (created_at at time zone 'Africa/Ouagadougou')::date = cauris_today();
        if v_today >= v_rule.daily_cap then
            return 0;
        end if;
    end if;
    insert into cauris_ledger (org_id, delta, reason, ref, note)
    values (p_org_id, v_rule.points, p_reason, p_ref, p_note)
    on conflict (org_id, reason, ref) do nothing;
    get diagnostics v_n = row_count;
    return case when v_n > 0 then v_rule.points else 0 end;
end;
$$;

-- ------------------------------------------------------------
-- 3. Earned from the events themselves
-- ------------------------------------------------------------
create or replace function trg_cauris_order()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_inside boolean;
    v_today  int;
begin
    if new.status is not distinct from old.status then
        return new;
    end if;
    -- The business's own people ordering from it earn nothing.
    v_inside := exists (select 1 from memberships m
                         where m.org_id = new.org_id and m.user_id = new.customer_id);

    if new.status in ('picked_up', 'delivered') and not v_inside
       and coalesce(new.total, 0) >= cauris_param('cauris_order_min', 500) then
        select count(*) into v_today from cauris_ledger
         where org_id = new.org_id and reason = 'order_done'
           and note = new.customer_id::text
           and (created_at at time zone 'Africa/Ouagadougou')::date = cauris_today();
        if v_today < cauris_param('cauris_orders_per_customer', 2) then
            perform cauris_award(new.org_id, 'order_done', new.id::text, new.customer_id::text);
            -- Came back: another finished order from the same person in the
            -- 30 days before this one.
            if exists (select 1 from orders o
                        where o.org_id = new.org_id and o.customer_id = new.customer_id
                          and o.id <> new.id
                          and o.status in ('picked_up', 'delivered')
                          and o.created_at >= new.created_at - interval '30 days'
                          and o.created_at <  new.created_at) then
                perform cauris_award(new.org_id, 'returning_customer', new.id::text,
                                     new.customer_id::text);
            end if;
        end if;
    elsif old.status = 'pending' and new.status = 'accepted' and not v_inside
          and now() - new.created_at
              <= make_interval(mins => cauris_param('cauris_quick_minutes', 15)) then
        perform cauris_award(new.org_id, 'quick_accept', new.id::text);
    elsif new.status = 'cancelled' and old.status in ('accepted', 'ready')
          and auth.uid() is distinct from new.customer_id then
        -- Accepted, then dropped by the business (the customer's own
        -- cancellation costs it nothing).
        perform cauris_award(new.org_id, 'shop_cancel', new.id::text);
    end if;
    return new;
end;
$$;

-- Created once, never dropped: the live database applies only what
-- destroys nothing without the owner's say.
do $$ begin
    if not exists (select 1 from pg_trigger where tgname = 'cauris_order') then
        create trigger cauris_order
            after update of status on orders
            for each row execute function trg_cauris_order();
    end if;
end $$;

-- The till used every one of the last 7 days: once per 7 days.
create or replace function trg_cauris_sale()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_today date := cauris_today();
    v_days  int;
begin
    if exists (select 1 from cauris_ledger
                where org_id = new.org_id and reason = 'till_streak'
                  and (created_at at time zone 'Africa/Ouagadougou')::date > v_today - 7) then
        return new;
    end if;
    select count(distinct (s.occurred_at at time zone 'Africa/Ouagadougou')::date) into v_days
      from sales s
     where s.org_id = new.org_id
       and (s.occurred_at at time zone 'Africa/Ouagadougou')::date between v_today - 6 and v_today;
    if v_days >= 7 then
        perform cauris_award(new.org_id, 'till_streak', v_today::text);
    end if;
    return new;
end;
$$;

-- Created once, never dropped: the live database applies only what
-- destroys nothing without the owner's say.
do $$ begin
    if not exists (select 1 from pg_trigger where tgname = 'cauris_sale') then
        create trigger cauris_sale
            after insert on sales
            for each row execute function trg_cauris_sale();
    end if;
end $$;

-- A farm that keeps its log: once a day.
create or replace function trg_cauris_flock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    perform cauris_award((select f.org_id from flocks f where f.id = new.flock_id),
                         'farm_log', cauris_today()::text);
    return new;
end;
$$;

-- Created once, never dropped: the live database applies only what
-- destroys nothing without the owner's say.
do $$ begin
    if not exists (select 1 from pg_trigger where tgname = 'cauris_flock') then
        create trigger cauris_flock
            after insert on flock_events
            for each row execute function trg_cauris_flock();
    end if;
end $$;

-- A distinct visitor opening the vitrine. The device sends its own random
-- id; the business's signed-in members never count.
create or replace function record_visitor(p_slug text, p_visitor text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org uuid := storefront_open(p_slug);
    v_id  text := btrim(coalesce(p_visitor, ''));
    v_n   int;
begin
    if v_org is null or char_length(v_id) not between 8 and 64 then
        return;
    end if;
    if auth.uid() is not null and exists (
        select 1 from memberships where org_id = v_org and user_id = auth.uid()) then
        return;
    end if;
    insert into storefront_visitors (day, org_id, visitor)
    values (cauris_today(), v_org, v_id)
    on conflict do nothing;
    get diagnostics v_n = row_count;
    if v_n > 0 then
        perform cauris_award(v_org, 'visitor', cauris_today()::text || ':' || v_id);
    end if;
end;
$$;

-- The vitrine's own score, as the app counts it (070's six steps).
create or replace function vitrine_score(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select (100 * (
        (published > 0)::int
      + (with_photo >= 3 or (published > 0 and with_photo >= published))::int
      + blurb::int + phone::int + address::int + pin::int) / 6.0)::int
    from (
        select
            (select count(*) from products p
              where p.org_id = o.id and p.is_active and p.is_published) as published,
            (select count(*) from products p
              where p.org_id = o.id and p.is_active and p.is_published
                and exists (select 1 from documents d where d.product_id = p.id)) as with_photo,
            nullif(btrim(coalesce(o.storefront_blurb, '')), '') is not null as blurb,
            nullif(btrim(coalesce(o.phone, '')), '') is not null as phone,
            nullif(btrim(coalesce(o.address, '')), '') is not null as address,
            (o.lat is not null and o.lng is not null) as pin
        from orgs o where o.id = p_org_id
    ) x;
$$;

-- Milestones read on the business's own screens: the vitrine complete,
-- and — for whoever brought this business in — that it took off.
create or replace function cauris_milestones(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org orgs%rowtype;
begin
    if not is_org_member(p_org_id) then
        return;
    end if;
    select * into v_org from orgs where id = p_org_id;
    if v_org.storefront_enabled and vitrine_score(p_org_id) >= 100 then
        perform cauris_award(p_org_id, 'vitrine_complete', 'once');
    end if;
    if v_org.referred_by is not null
       and vitrine_score(p_org_id) >= 90
       and (select count(*) from orders o
             where o.org_id = p_org_id and o.status in ('picked_up', 'delivered')) >= 3 then
        perform cauris_award(v_org.referred_by, 'referral', p_org_id::text, v_org.name);
    end if;
end;
$$;

-- Who brought this business in: its admin says it once, in the first 30
-- days, by the other business's address (its slug). Never itself.
create or replace function set_referral(p_org_id uuid, p_code text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org orgs%rowtype;
    v_ref orgs%rowtype;
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur dit qui l''a parrainé';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if v_org.referred_by is not null then
        raise exception 'Le parrain est déjà enregistré';
    end if;
    if v_org.created_at < now() - interval '30 days' then
        raise exception 'Le parrainage se dit dans les 30 premiers jours';
    end if;
    select * into v_ref from orgs
     where slug = lower(btrim(coalesce(p_code, ''))) and archived_at is null;
    if not found or v_ref.id = p_org_id then
        raise exception 'Code de parrainage inconnu';
    end if;
    -- The same people on both sides is not a referral.
    if exists (select 1 from memberships a join memberships b on a.user_id = b.user_id
                where a.org_id = p_org_id and b.org_id = v_ref.id) then
        raise exception 'Une entreprise ne se parraine pas elle-même';
    end if;
    update orgs set referred_by = v_ref.id where id = p_org_id;
    return v_ref.name;
end;
$$;

-- ------------------------------------------------------------
-- 4. Reading
-- ------------------------------------------------------------
-- The business's wallet, for its admins. Volatile: reading it may write the
-- expiry line.
create or replace function my_cauris(p_org_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_last timestamptz;
begin
    if not is_org_admin(p_org_id) then
        return null;
    end if;
    perform cauris_expire(p_org_id);
    select max(created_at) into v_last from cauris_ledger
     where org_id = p_org_id and reason <> 'expired';
    return jsonb_build_object(
        'balance', cauris_balance(p_org_id),
        'week', (select coalesce(sum(delta), 0) from cauris_ledger
                  where org_id = p_org_id and delta > 0 and reason <> 'expired'
                    and created_at >= date_trunc('week', now() at time zone 'Africa/Ouagadougou')
                                      at time zone 'Africa/Ouagadougou'),
        'expires_on', case when v_last is null then null
                           else ((v_last at time zone 'Africa/Ouagadougou')::date
                                 + cauris_param('cauris_expire_days', 180)) end,
        'referral_code', (select slug from orgs where id = p_org_id),
        'referred', (select referred_by is not null from orgs where id = p_org_id),
        'history', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'delta', l.delta,
                       'reason', l.reason,
                       'label', coalesce(r.label, case l.reason
                                    when 'expired' then 'Cauris expirés'
                                    when 'spent' then 'Dépensés'
                                    else l.reason end),
                       'note', case when l.reason in ('expired', 'spent', 'prize') then l.note end,
                       'at', l.created_at) order by l.created_at desc)
              from (select * from cauris_ledger where org_id = p_org_id
                     order by created_at desc limit 60) l
              left join cauris_rules r on r.key = l.reason), '[]'::jsonb),
        'rules', coalesce((
            select jsonb_agg(jsonb_build_object('key', key, 'points', points,
                       'daily_cap', daily_cap, 'label', label) order by sort)
              from cauris_rules where points > 0), '[]'::jsonb)
    );
end;
$$;

-- The rules, for the console.
create or replace function cauris_rules_list()
returns setof cauris_rules
language sql
stable
security definer
set search_path = public, auth
as $$
    select * from cauris_rules
     where exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
     order by sort;
$$;

create or replace function set_cauris_rule(p_key text, p_points int, p_daily_cap int default null)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Only the platform sets the cauris rules';
    end if;
    if p_points is null or abs(p_points) > 10000 then
        raise exception 'Points hors limites';
    end if;
    update cauris_rules
       set points = p_points,
           daily_cap = case when coalesce(p_daily_cap, 0) > 0 then p_daily_cap end
     where key = p_key;
    if not found then
        raise exception 'Règle inconnue : %', p_key;
    end if;
end;
$$;

-- The week's top earners, and the share of their orders from one customer.
create or replace function cauris_watch()
returns table (
    org_id        uuid,
    org_name      text,
    week          integer,
    balance       integer,
    orders        integer,
    top_customer_share numeric
)
language sql
stable
security definer
set search_path = public, auth
as $$
    with w as (
        select l.org_id, sum(l.delta)::int as week
          from cauris_ledger l
         where l.delta > 0 and l.created_at >= now() - interval '7 days'
         group by l.org_id
    ), c as (
        select l.org_id, l.note as customer, count(*) as n
          from cauris_ledger l
         where l.reason = 'order_done' and l.created_at >= now() - interval '7 days'
         group by l.org_id, l.note
    )
    select w.org_id, o.name, w.week, cauris_balance(w.org_id),
           coalesce((select sum(n) from c where c.org_id = w.org_id), 0)::int,
           coalesce(round((select max(n) from c where c.org_id = w.org_id)::numeric
                 / nullif((select sum(n) from c where c.org_id = w.org_id), 0), 2), 0)
      from w join orgs o on o.id = w.org_id
     where exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
     order by w.week desc
     limit 50;
$$;

-- ------------------------------------------------------------
-- 5. Grants
-- ------------------------------------------------------------
revoke execute on function cauris_param(text, int)               from public;
revoke execute on function cauris_today()                        from public;
revoke execute on function cauris_balance(uuid)                  from public;
revoke execute on function cauris_expire(uuid)                   from public;
revoke execute on function cauris_award(uuid, text, text, text)  from public;
revoke execute on function trg_cauris_order()                    from public;
revoke execute on function trg_cauris_sale()                     from public;
revoke execute on function trg_cauris_flock()                    from public;
revoke execute on function record_visitor(text, text)            from public;
revoke execute on function vitrine_score(uuid)                   from public;
revoke execute on function cauris_milestones(uuid)               from public;
revoke execute on function set_referral(uuid, text)              from public;
revoke execute on function my_cauris(uuid)                       from public;
revoke execute on function cauris_rules_list()                   from public;
revoke execute on function set_cauris_rule(text, int, int)       from public;
revoke execute on function cauris_watch()                        from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function cauris_award(uuid, text, text, text) from anon;
        revoke execute on function cauris_expire(uuid)                  from anon;
        revoke execute on function cauris_balance(uuid)                 from anon;
        revoke execute on function cauris_param(text, int)              from anon;
        revoke execute on function vitrine_score(uuid)                  from anon;
        revoke execute on function trg_cauris_order()                   from anon;
        revoke execute on function trg_cauris_sale()                    from anon;
        revoke execute on function trg_cauris_flock()                   from anon;
        revoke execute on function cauris_milestones(uuid)              from anon;
        revoke execute on function set_referral(uuid, text)             from anon;
        revoke execute on function my_cauris(uuid)                      from anon;
        revoke execute on function cauris_rules_list()                  from anon;
        revoke execute on function set_cauris_rule(text, int, int)      from anon;
        revoke execute on function cauris_watch()                       from anon;
        grant execute on function record_visitor(text, text)            to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- The engine is the database's own: nobody calls it from an app.
        revoke execute on function cauris_award(uuid, text, text, text) from authenticated;
        revoke execute on function cauris_expire(uuid)                  from authenticated;
        revoke execute on function cauris_balance(uuid)                 from authenticated;
        revoke execute on function cauris_param(text, int)              from authenticated;
        revoke execute on function trg_cauris_order()                   from authenticated;
        revoke execute on function trg_cauris_sale()                    from authenticated;
        revoke execute on function trg_cauris_flock()                   from authenticated;
        grant execute on function cauris_today()                        to authenticated;
        grant execute on function vitrine_score(uuid)                   to authenticated;
        grant execute on function record_visitor(text, text)            to authenticated;
        grant execute on function cauris_milestones(uuid)               to authenticated;
        grant execute on function set_referral(uuid, text)              to authenticated;
        grant execute on function my_cauris(uuid)                       to authenticated;
        grant execute on function cauris_rules_list()                   to authenticated;
        grant execute on function set_cauris_rule(text, int, int)       to authenticated;
        grant execute on function cauris_watch()                        to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
