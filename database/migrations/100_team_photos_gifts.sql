-- ============================================================
-- 100_team_photos_gifts.sql — the team in one place, a worker earned,
-- photos counted, cauris an association can spend, the platform's gifts,
-- the owner's name on the picker, and the stock rules audited.
--
-- The owner's requests, and what each does here, for shops (retail),
-- farms and associations (association, and the legacy church):
--
--   1. « Équipe »: the owner sees their people and records each one's
--      salary (an amount and a period: par mois, par semaine, par jour;
--      optional). There was a place for it: employees (012), the payroll's
--      own row, which can already point at an account (user_id, 018). So
--      set_member_salary(org, user, amount, period) writes the salary on
--      that person's employees row — finding it by the account, or by the
--      name of an unlinked one, or adding it — and employees.pay_period
--      says per what. Recording a salary is free; PAYING it (shifts,
--      staff_payments) keeps 066's Pro guard. team_overview(org) is what
--      the screen reads: the seats, the people with their salary, and the
--      invitations still out. Same for all three kinds.
--   2. Workers are earned. The owner plus ONE worker (any member who is
--      not an owner) is free once the first setup is done — 091's
--      setup_done_at; an association, a church or a generic business has
--      no walkthrough, so for them it is done. More needs Mara Pro or the
--      team unlocked with cauris ('team_access', 085: org_has()). 066's
--      cap on memberships (trg_cap_free_plan) is where every path that adds
--      a member passes — claim_invitation, claim_my_invitations, a direct
--      insert by an admin — so it is replaced: the free count is the
--      platform setting free_max_staff, moved once from 066's 3 to 1 (a
--      setting changed later by the platform is never touched again), and
--      it is 0 until the setup is done. A trainer (038), Mara's own admins,
--      an owner, and somebody already in the business (a second grant adds
--      nobody) never take the seat. Nobody already there is removed: only
--      adding is refused. An invitation is refused at its writing too when
--      the seat is already taken, so the owner hears it, not the invitee;
--      and the sign-in sweep (claim_my_invitations) now skips an invitation
--      the business has no seat for instead of failing the whole sweep.
--   3. Photos on Basic: at most free_photo_items (10) photographed
--      articles or services — an active product with at least one photo
--      document. The 11th needs Mara Pro or a photo slot bought with
--      cauris: cauris_costs 'photo_slot', 50, permanent (orgs.photo_slots;
--      the price the platform's, like every cost). Held where a photo
--      becomes an article's: documents insert, or update of product_id, for
--      a product that had none. Articles already photographed past the
--      limit keep their photos. Showcase vitrines (094) and Mara's admins
--      are exempt. 066's photo cap (free_max_photos, 50) now counts only
--      the documents that are not an article's photo (receipts, deliveries
--      captured): the articles have their own rule. No limit on the number
--      of articles. Same for all three kinds — an association's services
--      are photographed like a shop's articles.
--   4. Associations still earn nothing (084's cauris_award is untouched),
--      but they receive what the platform gives (5) and may now SPEND it:
--      spend_cauris no longer refuses them, and buy_photo_slot does not
--      either. my_cauris and feature_states never looked at the profile;
--      they now carry the promotional points too.
--   5. The platform's powers, for any business: platform_give_cauris
--      gives points (a 'gift' line) or, with a date, promotional points
--      ('promo') that must be spent before that day — spending takes them
--      first, soonest first (cauris_take), and what is left on the day is
--      removed by an 'expired' line written when the wallet is next read or
--      moves (cauris_expire), as 084's idle expiry is. platform_give_unlock
--      opens a Pro tool until a date, as a cauris_unlocks row noted
--      « Offert par Mara » with no cauris spent. Each is rung to the
--      business's admins with its params (099). A gift is not earned: it is
--      kept out of the week's score and the leagues (league_scores,
--      my_cauris' week, cauris_watch), and an unlock given is not the
--      business's « premier outil » on Le Chemin (path_progress). A
--      showcase vitrine is refused (its ledger drops every line, 094).
--   6. my_orgs() carries owner_name — the owner's name, for the picker.
--  10. The stock audit. Two corrections did not follow the stock:
--      update_production_run (034) changed a batch's output count and left
--      the shelf with the old one — « 20 » corrected to « 40 » kept 20
--      cakes in stock; now the shelf moves by the difference. And
--      update_flock_event (033) let a correction take more birds out of a
--      flock than are left (« 3 » typed as « 300 »), the very thing
--      record_flock_event (009) refuses; now it refuses it too.
--
-- Functions replaced, each from its latest definition: trg_cap_free_plan
-- (066), claim_my_invitations (017), plan_terms (082), cauris_expire
-- (084), spend_cauris (085), feature_states (091), my_cauris (097),
-- path_progress (097), league_scores (086), cauris_watch (084), my_orgs
-- (065, dropped and recreated: its columns grow), update_production_run
-- (034), update_flock_event (033).
--
-- Re-runnable (the bundle runs twice): columns and tables if not exists,
-- settings on conflict do nothing (the one move of free_max_staff guarded
-- by a marker), functions replaced, triggers dropped and recreated.
-- ============================================================

-- ------------------------------------------------------------
-- 0. Settings, columns, tables
-- ------------------------------------------------------------
insert into platform_settings (key, value) values
    ('free_photo_items', '10')
on conflict (key) do nothing;

-- 066 offered 3 accounts; the owner now offers one. Once: what the platform
-- sets afterwards stays.
do $$
begin
    if not exists (select 1 from platform_settings where key = 'team_seats_seeded') then
        update platform_settings set value = '1'
         where key = 'free_max_staff' and value #>> '{}' = '3';
        insert into platform_settings (key, value) values ('team_seats_seeded', to_jsonb(now()))
        on conflict (key) do nothing;
    end if;
end $$;

insert into cauris_costs (feature, cost, min_days, sort) values
    ('photo_slot', 50, 0, 100)
on conflict (feature) do nothing;

alter table orgs add column if not exists photo_slots integer not null default 0;
alter table orgs drop constraint if exists orgs_photo_slots_positive;
alter table orgs add constraint orgs_photo_slots_positive check (photo_slots >= 0);
comment on column orgs.photo_slots is
    'Photo slots bought with cauris (100): each lets one more article be photographed on Basic, for good.';

alter table employees add column if not exists pay_period text;
alter table employees drop constraint if exists employees_pay_period_kind;
alter table employees add constraint employees_pay_period_kind
    check (pay_period is null or pay_period in ('month', 'week', 'day'));
comment on column employees.pay_period is
    'What the salary is per (100): month, week or day. Null reads as month (012''s salary).';

alter table cauris_unlocks add column if not exists note text;
alter table cauris_unlocks add column if not exists gifted_by uuid references profiles(id) on delete set null;
comment on column cauris_unlocks.gifted_by is
    'Set when the platform opened the tool as a gift (100): no cauris were spent.';

create table if not exists cauris_promos (
    id          uuid primary key default gen_random_uuid(),
    org_id      uuid not null references orgs(id) on delete cascade,
    points      integer not null check (points > 0),
    left_points integer not null check (left_points >= 0),
    expires_on  date not null,
    note        text,
    given_by    uuid references profiles(id) on delete set null,
    created_at  timestamptz not null default now(),
    closed_at   timestamptz
);
create index if not exists cauris_promos_open
    on cauris_promos (org_id, expires_on) where left_points > 0;
alter table cauris_promos enable row level security;
-- No policies: read through my_cauris() and feature_states().
comment on table cauris_promos is
    'Promotional cauris the platform gave (100), to be spent before expires_on. '
    'left_points is what spending has not taken yet; the ledger holds the points.';

-- ------------------------------------------------------------
-- 1–2. The team
-- ------------------------------------------------------------
-- The first setup is behind the business: 091's mark, or a profile that has
-- no walkthrough (an association, a church, a generic business).
create or replace function org_setup_done(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((select o.setup_done_at is not null
                            or o.profile::text not in ('retail', 'farm')
                       from orgs o where o.id = p_org_id), false);
$$;

-- The workers: everyone in the business who is not one of its owners — a
-- trainer (038) and Mara's own admins aside.
create or replace function org_workers(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select count(distinct m.user_id)::int
      from memberships m
     where m.org_id = p_org_id
       and not m.is_trainer
       and not exists (select 1 from memberships o
                        where o.org_id = m.org_id and o.user_id = m.user_id
                          and o.role = 'owner')
       and not exists (select 1 from profiles p
                        where p.id = m.user_id and p.is_platform_admin);
$$;

-- How many workers come free: none before the setup, then the platform's
-- number (one).
create or replace function org_free_workers(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case when org_setup_done(p_org_id)
                then greatest(plan_limit('free_max_staff', 1), 0) else 0 end;
$$;

-- Where the business stands: what the app draws (« 1 personne offerte »,
-- or the lock with Pro and the cauris price).
create or replace function team_seats(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'free',       org_free_workers(p_org_id),
        'used',       org_workers(p_org_id),
        'unlimited',  org_has(p_org_id, 'team_access'),
        'setup_done', org_setup_done(p_org_id),
        'open',       org_has(p_org_id, 'team_access')
                      or org_workers(p_org_id) < org_free_workers(p_org_id),
        'cost',       (select c.cost from cauris_costs c where c.feature = 'team_access'),
        'until',      (select u.until from cauris_unlocks u
                        where u.org_id = p_org_id and u.feature = 'team_access'
                          and u.until > now())
    );
$$;

-- What the refusal says, to the owner or to the person invited. Fixed
-- words, so the app can say them in English.
create or replace function team_full_message(p_org_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select case when org_setup_done(p_org_id)
        then 'Kaj Pro : cette entreprise a déjà sa personne offerte en plus du propriétaire. '
             || 'Pour ajouter quelqu''un : Mara Pro, ou l''équipe débloquée avec des cauris.'
        else 'Kaj Pro : la personne offerte s''ouvre une fois la mise en route de l''entreprise terminée. '
             || 'Avant : Mara Pro, ou l''équipe débloquée avec des cauris.'
    end;
$$;

-- Would one more worker be refused right now?
create or replace function team_full(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select org_plan(p_org_id) = 'free'
       and not org_has(p_org_id, 'team_access')
       and org_workers(p_org_id) >= org_free_workers(p_org_id);
$$;

-- 066's caps, with the team counted as the owner asked and the articles'
-- photos left to their own rule (3).
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
        -- An owner, a trainer, Mara's own admin, or somebody already in the
        -- business (another grant to the same person) adds no worker.
        if new.role = 'owner' or coalesce(new.is_trainer, false)
           or exists (select 1 from profiles where id = new.user_id and is_platform_admin)
           or exists (select 1 from memberships m
                       where m.org_id = new.org_id and m.user_id = new.user_id) then
            return new;
        end if;
        if team_full(new.org_id) then
            raise exception '%', team_full_message(new.org_id);
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
        -- An article's photo is counted by article (trg_photo_items).
        if new.product_id is not null then
            return new;
        end if;
        v_cap := plan_limit('free_max_photos', 50);
        select count(*) into v_count from documents
         where org_id = new.org_id and product_id is null;
        if v_count >= v_cap then
            raise exception 'Kaj Pro : la formule gratuite garde % photos. Ouvrez Compte › Kaj Pro pour en ajouter.', v_cap;
        end if;
    end if;

    return new;
end;
$$;

-- An invitation written when the seat is already taken: said to the owner
-- now, rather than to the invitee later.
create or replace function trg_invitation_seat()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
       or new.role = 'owner' then
        return new;
    end if;
    if team_full(new.org_id) then
        raise exception '%', team_full_message(new.org_id);
    end if;
    return new;
end;
$$;

drop trigger if exists invitation_seat on pending_invitations;
create trigger invitation_seat
before insert on pending_invitations
for each row execute function trg_invitation_seat();

-- 017's sweep: an invitation the business has no seat for stays waiting
-- (it is claimed once a seat opens), and the others still go through.
create or replace function claim_my_invitations()
returns int
language plpgsql
volatile
security definer
set search_path = public, auth
as $$
declare
    v_uid   uuid := auth.uid();
    v_phone text;
    v_email text;
    v_alt   text;
    v_count int := 0;
    v_inv   pending_invitations%rowtype;
begin
    if v_uid is null then
        return 0;
    end if;

    if not exists (select 1 from profiles where id = v_uid) then
        return 0;
    end if;

    select u.phone, u.email into v_phone, v_email from auth.users u where u.id = v_uid;
    select p.phone into v_alt from profiles p where p.id = v_uid;

    for v_inv in
        select * from pending_invitations i
        where i.claimed_at is null
          and i.expires_at > now()
          and (
              (v_phone is not null and i.phone = v_phone)
              or (v_alt is not null and i.phone = v_alt)
              or (v_email is not null and lower(i.email) = lower(v_email))
          )
        for update
    loop
        begin
            insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
            values (v_inv.org_id, v_uid, v_inv.role, v_inv.scope_kind,
                    v_inv.scope_id, v_inv.visibility)
            on conflict (user_id, scope_kind, scope_id, role) do nothing;
        exception when raise_exception then
            continue;  -- no seat (100): left for later, the rest go on
        end;

        update pending_invitations
        set claimed_at = now(), claimed_by = v_uid
        where id = v_inv.id and claimed_at is null;

        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$$;

-- A person's name as the screens say it.
create or replace function person_name(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                    nullif(btrim(coalesce(p.full_name, '')), ''),
                    p.phone)
      from profiles p where p.id = p_user_id;
$$;

-- The Équipe screen, in one read: the seats, the people (owners first) with
-- their salary, the invitations still out. The business's admins only:
-- what a colleague earns is theirs to see (012).
create or replace function team_overview(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null or not is_org_admin(p_org_id) then
        return null;
    end if;
    return jsonb_build_object(
        'seats', team_seats(p_org_id),
        'members', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'user_id', u.user_id,
                       'name', person_name(u.user_id),
                       'phone', p.phone,
                       'roles', to_jsonb(u.roles),
                       'owner', 'owner' = any (u.roles),
                       'since', u.since,
                       'salary', case when e.salary > 0 then e.salary end,
                       'period', case when e.salary > 0 then coalesce(e.pay_period, 'month') end,
                       'employee_id', e.id)
                   order by ('owner' = any (u.roles)) desc, lower(person_name(u.user_id)))
              from (select m.user_id,
                           array_agg(distinct m.role::text order by m.role::text) as roles,
                           min(m.created_at) as since
                      from memberships m
                     where m.org_id = p_org_id and not m.is_trainer
                     group by m.user_id) u
              join profiles p on p.id = u.user_id
              left join lateral (
                  select x.id, x.salary, x.pay_period from employees x
                   where x.org_id = p_org_id and x.user_id = u.user_id and x.is_active
                   order by x.created_at limit 1) e on true), '[]'::jsonb),
        'invitations', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'id', i.id, 'code', i.code, 'phone', i.phone,
                       'name', i.full_name, 'role', i.role,
                       'expires_at', i.expires_at) order by i.created_at desc)
              from pending_invitations i
             where i.org_id = p_org_id and i.claimed_at is null
               and i.expires_at > now()), '[]'::jsonb)
    );
end;
$$;

-- A member's salary, on their payroll row. Null or 0 clears it. Free: the
-- payroll's Pro guard is on paying (shifts, staff_payments), not here.
create or replace function set_member_salary(
    p_org_id  uuid,
    p_user_id uuid,
    p_amount  numeric,
    p_period  text default 'month'
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_id     uuid;
    v_name   text;
    v_phone  text;
    v_amount numeric := coalesce(p_amount, 0);
    v_period text := coalesce(nullif(btrim(coalesce(p_period, '')), ''), 'month');
begin
    if auth.uid() is null or not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur note le salaire de l''équipe';
    end if;
    if not exists (select 1 from memberships
                    where org_id = p_org_id and user_id = p_user_id) then
        raise exception 'Cette personne n''est pas dans l''équipe';
    end if;
    if v_amount < 0 or v_amount > 1000000000 then
        raise exception 'Le salaire doit être un montant positif';
    end if;
    if v_period not in ('month', 'week', 'day') then
        raise exception 'Période inconnue : %', v_period;
    end if;

    select person_name(p_user_id), phone into v_name, v_phone
      from profiles where id = p_user_id;
    v_name := coalesce(v_name, 'Membre');

    -- Their row: by the account, else an unlinked one of the same name
    -- (somebody already on the payroll before they had the app).
    select id into v_id from employees
     where org_id = p_org_id and user_id = p_user_id
     order by is_active desc, created_at limit 1;
    if v_id is null then
        select id into v_id from employees
         where org_id = p_org_id and user_id is null
           and lower(btrim(full_name)) = lower(btrim(v_name))
         order by is_active desc, created_at limit 1;
    end if;
    if v_id is null then
        if v_amount = 0 then
            return null;  -- nothing to clear
        end if;
        -- The name is unique in the business (012): another person's row
        -- of the same name keeps it, this one takes the phone beside it.
        if exists (select 1 from employees
                    where org_id = p_org_id
                      and lower(btrim(full_name)) = lower(btrim(v_name))) then
            v_name := v_name || ' (' || coalesce(v_phone, left(p_user_id::text, 8)) || ')';
        end if;
        insert into employees (org_id, full_name, phone, kind, salary, pay_period,
                               user_id, created_by)
        values (p_org_id, v_name, v_phone, 'permanent', v_amount, v_period,
                p_user_id, auth.uid())
        returning id into v_id;
        return v_id;
    end if;

    update employees
       set user_id    = p_user_id,
           is_active  = true,
           ended_on   = null,
           end_reason = null,
           kind       = case when v_amount > 0 then 'permanent' else kind end,
           salary     = v_amount,
           pay_period = case when v_amount > 0 then v_period end
     where id = v_id;
    return v_id;
end;
$$;

-- ------------------------------------------------------------
-- 3. Photos on Basic
-- ------------------------------------------------------------
-- The articles (and services) photographed: active, with a photo.
create or replace function org_photo_items(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select count(*)::int from products p
     where p.org_id = p_org_id and p.is_active
       and exists (select 1 from documents d where d.product_id = p.id);
$$;

-- How many may be: null when there is no limit (Mara Pro, a showcase).
create or replace function org_photo_limit(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case
        when org_plan(o.id) = 'pro' or o.showcase then null
        else greatest(plan_limit('free_photo_items', 10), 0) + o.photo_slots
    end
    from orgs o where o.id = p_org_id;
$$;

create or replace function photo_state(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'used',      org_photo_items(p_org_id),
        'limit',     org_photo_limit(p_org_id),
        'slots',     (select photo_slots from orgs where id = p_org_id),
        'slot_cost', (select cost from cauris_costs where feature = 'photo_slot')
    );
$$;

create or replace function trg_photo_items()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_limit int;
begin
    if new.product_id is null
       or (tg_op = 'UPDATE' and old.product_id is not distinct from new.product_id)
       or auth.uid() is null
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return new;
    end if;
    -- Another photo of an article already photographed takes no new place.
    if exists (select 1 from documents d
                where d.product_id = new.product_id and d.id <> new.id) then
        return new;
    end if;
    v_limit := org_photo_limit(new.org_id);
    if v_limit is not null and org_photo_items(new.org_id) >= v_limit then
        raise exception 'Kaj Pro : toutes vos places photo sont prises. '
            'Pour photographier un article de plus : Mara Pro, ou une place photo achetée avec des cauris.';
    end if;
    return new;
end;
$$;

drop trigger if exists photo_items_limit on documents;
create trigger photo_items_limit
before insert or update of product_id on documents
for each row execute function trg_photo_items();

-- ------------------------------------------------------------
-- 4–5. Cauris: promotional points, spending, gifts
-- ------------------------------------------------------------
-- 084's expiry, with the promotional points: an idle wallet still empties
-- itself (and its promotional points with it); otherwise what is left of a
-- promotion on its day is taken out, never below zero. A promotion's own
-- expiry line is not « a movement » that keeps a wallet alive.
create or replace function cauris_expire(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_last    timestamptz;
    v_balance int;
    v_take    int;
    r         record;
begin
    select max(created_at) into v_last from cauris_ledger
     where org_id = p_org_id
       and not (reason = 'expired' and ref like 'promo:%');
    if v_last is not null
       and v_last <= now() - make_interval(days => cauris_param('cauris_expire_days', 180)) then
        v_balance := cauris_balance(p_org_id);
        if v_balance > 0 then
            insert into cauris_ledger (org_id, delta, reason, ref, note)
            values (p_org_id, -v_balance, 'expired', cauris_today()::text,
                    'Cauris non utilisés depuis ' || cauris_param('cauris_expire_days', 180) || ' jours')
            on conflict do nothing;
        end if;
        update cauris_promos set left_points = 0, closed_at = now()
         where org_id = p_org_id and left_points > 0;
        return;
    end if;

    for r in select * from cauris_promos
              where org_id = p_org_id and left_points > 0
                and expires_on <= cauris_today()
              order by expires_on, created_at
              for update
    loop
        v_take := least(r.left_points, greatest(cauris_balance(p_org_id), 0));
        if v_take > 0 then
            insert into cauris_ledger (org_id, delta, reason, ref, note)
            values (p_org_id, -v_take, 'expired', 'promo:' || r.id,
                    'Cauris offerts à utiliser avant le ' || to_char(r.expires_on, 'DD/MM/YYYY'))
            on conflict do nothing;
        end if;
        update cauris_promos set left_points = 0, closed_at = now() where id = r.id;
    end loop;
end;
$$;

-- What is left of the promotions, soonest first, never more than the
-- wallet holds (a lost cauri — an order cancelled — comes out of them too).
create or replace function cauris_promo_left(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(jsonb_agg(jsonb_build_object('points', x.pts, 'until', x.expires_on)
                              order by x.expires_on, x.created_at), '[]'::jsonb)
      from (
        select c.expires_on, c.created_at,
               least(c.left_points,
                     greatest(cauris_balance(p_org_id)
                              - coalesce(sum(c.left_points) over (
                                    order by c.expires_on, c.created_at
                                    rows between unbounded preceding and 1 preceding), 0), 0))::int as pts
          from cauris_promos c
         where c.org_id = p_org_id and c.left_points > 0
           and c.expires_on > cauris_today()
      ) x
     where x.pts > 0;
$$;

-- The one way cauris are spent: one spender at a time, the price in one
-- 'spent' line, the promotional points used first, soonest first.
-- Returns the balance after.
create or replace function cauris_take(p_org_id uuid, p_cost int, p_ref text, p_note text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_balance int;
    v_left    int := p_cost;
    v_take    int;
    r         record;
begin
    perform pg_advisory_xact_lock(hashtext('cauris:' || p_org_id::text));
    perform cauris_expire(p_org_id);
    v_balance := cauris_balance(p_org_id);
    if v_balance < p_cost then
        raise exception 'Il vous manque % cauris', p_cost - v_balance;
    end if;
    insert into cauris_ledger (org_id, delta, reason, ref, note)
    values (p_org_id, -p_cost, 'spent', p_ref, p_note);
    for r in select id, left_points from cauris_promos
              where org_id = p_org_id and left_points > 0
                and expires_on > cauris_today()
              order by expires_on, created_at
              for update
    loop
        exit when v_left <= 0;
        v_take := least(r.left_points, v_left);
        update cauris_promos
           set left_points = left_points - v_take,
               closed_at = case when left_points - v_take = 0 then now() end
         where id = r.id;
        v_left := v_left - v_take;
    end loop;
    return v_balance - p_cost;
end;
$$;

-- 085's spending: for an association too now (it earns nothing, but what
-- the platform gives it, it may spend); through cauris_take; a tool bought
-- after it was given is the business's own again.
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

-- A photo slot: 50 cauris (the platform's price), for good.
create or replace function buy_photo_slot(p_org_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_cost  int;
    v_after int;
    v_slots int;
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur dépense les cauris de l''entreprise';
    end if;
    select cost into v_cost from cauris_costs where feature = 'photo_slot';
    if v_cost is null then
        raise exception 'Les places photo ne s''achètent pas avec des cauris';
    end if;
    v_after := cauris_take(p_org_id, v_cost, 'photo_slot:' || gen_random_uuid()::text,
                           'photo_slot');
    update orgs set photo_slots = photo_slots + 1 where id = p_org_id
    returning photo_slots into v_slots;
    return jsonb_build_object('slots', v_slots, 'balance', v_after,
                              'photos', photo_state(p_org_id));
end;
$$;

-- A Pro tool, in the words of the bell.
create or replace function cauris_feature_label(p_feature text)
returns text
language sql
immutable
set search_path = public
as $$
    select case p_feature
        when 'pro_all'        then 'Mara Pro complet'
        when 'analytics'      then 'les analyses'
        when 'delivery'       then 'la livraison'
        when 'online_payment' then 'le paiement en ligne'
        when 'vitrine_plus'   then 'la vitrine personnalisée'
        when 'accounting'     then 'la comptabilité'
        when 'team_access'    then 'l''équipe'
        when 'payroll'        then 'la paie'
        when 'currencies'     then 'les devises'
        when 'tontines'       then 'les tontines'
        else p_feature
    end;
$$;

-- The platform gives points: a gift, or — with a date — promotional points
-- to be spent before that day.
create or replace function platform_give_cauris(
    p_org_id     uuid,
    p_points     integer,
    p_note       text default null,
    p_expires_on date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org   orgs%rowtype;
    v_note  text := nullif(btrim(coalesce(p_note, '')), '');
    v_ref   text := gen_random_uuid()::text;
    v_promo uuid;
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Seule la plateforme offre des cauris';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if not found then
        raise exception 'Entreprise inconnue';
    end if;
    if v_org.showcase then
        raise exception 'Une vitrine d''exemple ne reçoit pas de cauris';
    end if;
    if p_points is null or p_points <= 0 or p_points > 100000 then
        raise exception 'Le nombre de cauris doit être entre 1 et 100 000';
    end if;
    if p_expires_on is not null and p_expires_on <= cauris_today() then
        raise exception 'La date doit être après aujourd''hui';
    end if;

    perform pg_advisory_xact_lock(hashtext('cauris:' || p_org_id::text));
    perform cauris_expire(p_org_id);
    if p_expires_on is null then
        insert into cauris_ledger (org_id, delta, reason, ref, note)
        values (p_org_id, p_points, 'gift', v_ref, coalesce(v_note, 'Offert par Mara'));
    else
        insert into cauris_promos (org_id, points, left_points, expires_on, note, given_by)
        values (p_org_id, p_points, p_points, p_expires_on, v_note, auth.uid())
        returning id into v_promo;
        insert into cauris_ledger (org_id, delta, reason, ref, note)
        values (p_org_id, p_points, 'promo', v_promo::text,
                coalesce(v_note, 'Offert par Mara') || ' · avant le '
                || to_char(p_expires_on, 'DD/MM/YYYY'));
    end if;

    begin
        perform notify_org_admins(p_org_id,
            case when p_expires_on is null then 'cauris_gift' else 'cauris_promo' end,
            'Mara vous offre ' || p_points || ' cauris'
            || case when p_expires_on is not null
                    then ', à utiliser avant le ' || to_char(p_expires_on, 'DD/MM/YYYY') else '' end
            || case when v_note is not null then ' : ' || v_note else '' end || '.',
            jsonb_build_object('to', 'shop', 'points', p_points, 'note', v_note,
                               'until', p_expires_on));
    exception when others then
        null;  -- a bell never costs the gift
    end;

    return jsonb_build_object('balance', cauris_balance(p_org_id),
                              'promo', cauris_promo_left(p_org_id));
end;
$$;

-- The platform opens a Pro tool until a date (that day included). No
-- cauris move; the row says who gave it.
create or replace function platform_give_unlock(
    p_org_id  uuid,
    p_feature text,
    p_until   date,
    p_note    text default null
)
returns timestamptz
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org   orgs%rowtype;
    v_until timestamptz;
    v_note  text := coalesce(nullif(btrim(coalesce(p_note, '')), ''), 'Offert par Mara');
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Seule la plateforme offre un outil';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if not found then
        raise exception 'Entreprise inconnue';
    end if;
    if p_feature is null or p_feature = 'photo_slot'
       or not (coalesce(plan_setting('pro_features'), '[]'::jsonb) ? p_feature
               or exists (select 1 from cauris_costs where feature = p_feature)) then
        raise exception 'Outil inconnu : %', coalesce(p_feature, '');
    end if;
    if p_until is null or p_until < cauris_today() then
        raise exception 'La date doit être aujourd''hui ou plus tard';
    end if;
    v_until := (p_until + 1)::timestamp at time zone 'Africa/Ouagadougou';

    insert into cauris_unlocks (org_id, feature, until, note, gifted_by)
    values (p_org_id, p_feature, v_until, v_note, auth.uid())
    on conflict (org_id, feature) do update
        set until = greatest(cauris_unlocks.until, excluded.until),
            note = excluded.note, gifted_by = excluded.gifted_by, updated_at = now()
    returning until into v_until;

    begin
        perform notify_org_admins(p_org_id, 'feature_gift',
            'Mara vous offre ' || cauris_feature_label(p_feature) || ' jusqu''au '
            || to_char(p_until, 'DD/MM/YYYY') || '.',
            jsonb_build_object('to', 'shop', 'feature', p_feature, 'until', p_until,
                               'note', v_note));
    exception when others then
        null;
    end;
    return v_until;
end;
$$;

-- 091's states, with the promotions, the photos and the team. Reading may
-- write a promotion's expiry line, so it is volatile now (as my_cauris is).
-- A photo slot is not a tool opened for 30 days: it is left out of 'tools'.
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
        'setup_done', coalesce((select setup_done_at is not null from orgs where id = p_org_id), true),
        'promo', cauris_promo_left(p_org_id),
        'photos', photo_state(p_org_id),
        'team', team_seats(p_org_id)
    );
end;
$$;

-- 097's wallet, with the promotions, and gifts kept out of the week's score.
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
                  where org_id = p_org_id and delta > 0
                    and reason not in ('expired', 'gift', 'promo')
                    and created_at >= date_trunc('week', now() at time zone 'Africa/Ouagadougou')
                                      at time zone 'Africa/Ouagadougou'),
        'expires_on', case when v_last is null then null
                           else ((v_last at time zone 'Africa/Ouagadougou')::date
                                 + cauris_param('cauris_expire_days', 180)) end,
        'promo', cauris_promo_left(p_org_id),
        'referral_code', (select slug from orgs where id = p_org_id),
        'referred', (select referred_by is not null from orgs where id = p_org_id),
        'referral_points', coalesce((select points from cauris_rules where key = 'referral'), 0),
        'referrals', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'name', r.name,
                       'score', vitrine_score(r.id),
                       'orders', (select count(*) from orders o
                                   where o.org_id = r.id and o.status in ('picked_up', 'delivered')),
                       'paid', exists (select 1 from cauris_ledger l
                                        where l.org_id = p_org_id and l.reason = 'referral'
                                          and l.ref = r.id::text)
                   ) order by r.created_at desc)
              from orgs r where r.referred_by = p_org_id), '[]'::jsonb),
        'history', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'delta', l.delta,
                       'reason', l.reason,
                       'label', coalesce(r.label, case l.reason
                                    when 'expired'   then 'Cauris expirés'
                                    when 'spent'     then 'Dépensés'
                                    when 'path_step' then 'Étape du chemin'
                                    when 'prize'     then 'Podium de la semaine'
                                    when 'lesson'    then 'Leçon de l''Académie Mara'
                                    when 'gift'      then 'Cadeau de Mara'
                                    when 'promo'     then 'Cauris offerts par Mara'
                                    else l.reason end),
                       'note', case when l.reason in ('expired', 'spent', 'prize', 'referral',
                                                      'path_step', 'gift', 'promo')
                                    then l.note end,
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

-- 086's scores: a gift is not earned.
create or replace function league_scores(p_from timestamptz, p_to timestamptz)
returns table (org_id uuid, name text, hidden boolean, league text, score integer)
language sql
stable
security definer
set search_path = public
as $$
    select o.id, o.name, o.board_hidden, league_key(o.id),
           coalesce((select sum(l.delta) from cauris_ledger l
                      where l.org_id = o.id and l.delta > 0
                        and l.reason not in ('prize', 'expired', 'spent', 'gift', 'promo')
                        and l.created_at >= p_from and l.created_at < p_to), 0)::int
      from orgs o
     where o.profile not in ('church', 'association')
       and o.archived_at is null and o.suspended_at is null
       and exists (select 1 from cauris_ledger l where l.org_id = o.id);
$$;

-- 084's watch: the week's earners, not the platform's own gifts.
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
           and l.reason not in ('gift', 'promo')
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

-- 097's steps, verbatim but one: « Mon premier outil avec mes cauris » is
-- a tool the business opened itself, not one Mara gave it.
create or replace function path_progress(p_org uuid, p_step text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select (case p_step
        when 'first_article' then
            (select count(*) from products p
              where p.org_id = p_org and p.is_active and p.is_published)
        when 'articles' then
            (select count(*) from products p
              where p.org_id = p_org and p.is_active and p.is_published)
        when 'vitrine_open' then
            (select count(*) from orgs o where o.id = p_org and o.storefront_enabled)
        when 'contact' then
            (select (nullif(btrim(coalesce(o.phone, '')), '') is not null)::int
                  + (nullif(btrim(coalesce(o.address, '')), '') is not null)::int
               from orgs o where o.id = p_org)
        when 'photos' then
            (select count(*) from products p
              where p.org_id = p_org and p.is_active and p.is_published
                and exists (select 1 from documents d where d.product_id = p.id))
        when 'blurb' then
            (select count(*) from orgs o
              where o.id = p_org and nullif(btrim(coalesce(o.storefront_blurb, '')), '') is not null)
        when 'pin' then
            (select count(*) from orgs o
              where o.id = p_org and o.lat is not null and o.lng is not null)
        when 'first_sale' then
            (select count(*) from (select 1 from sales s
                                    where s.org_id = p_org and s.kind = 'sale' limit 1) x)
        when 'farm_log' then
            (select count(*) from (select 1 from flock_events e join flocks f on f.id = e.flock_id
                                    where f.org_id = p_org limit 1) x)
        when 'first_order' then
            (select count(*) from (select 1 from orders x
                                    where x.org_id = p_org
                                      and x.status in ('accepted', 'ready', 'picked_up', 'delivered')
                                    limit 1) y)
        when 'three_orders' then
            (select count(*) from orders x
              where x.org_id = p_org and x.status in ('picked_up', 'delivered'))
        when 'returning' then
            (select count(*) from (select 1 from orders x
                                    where x.org_id = p_org and x.customer_id is not null
                                      and x.status in ('picked_up', 'delivered')
                                    group by x.customer_id having count(*) >= 2 limit 1) y)
        when 'till_week' then
            (select count(distinct (s.occurred_at at time zone 'Africa/Ouagadougou')::date)
               from sales s where s.org_id = p_org and s.kind = 'sale')
        when 'log_week' then
            (select count(distinct (e.occurred_at at time zone 'Africa/Ouagadougou')::date)
               from flock_events e join flocks f on f.id = e.flock_id
              where f.org_id = p_org)
        when 'first_unlock' then
            (select count(*) from (select 1 from cauris_unlocks u
                                    where u.org_id = p_org and u.gifted_by is null
                                    limit 1) x)
        when 'referral' then
            (select count(*) from (select 1 from orgs r
                                    where r.referred_by = p_org limit 1) x)
        when 'podium' then
            (select count(*) from (select 1 from cauris_week_results w
                                    where w.org_id = p_org and w.rank <= 3
                                      and (select count(*)
                                             from league_scores(
                                                    w.week_start::timestamp at time zone 'Africa/Ouagadougou',
                                                    (w.week_start + 7)::timestamp at time zone 'Africa/Ouagadougou') l
                                            where l.league = w.league and l.score > 0)
                                          >= cauris_param('path_league_min', 3)
                                    limit 1) x)
        else 0
    end)::int;
$$;

-- 082's terms, with the photographed articles a Basic business keeps.
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
        'stripe_on',               stripe_on()
    );
$$;

-- ------------------------------------------------------------
-- 6. The owner's name on the picker
-- ------------------------------------------------------------
-- 065's my_orgs, plus owner_name: who owns each business (the first owner
-- by date), so a platform admin choosing among hundreds knows which is
-- whose. The columns grow, so it is dropped and recreated.
drop function if exists my_orgs();

create function my_orgs()
returns table (
    org_id           uuid,
    name             text,
    slug             text,
    profile          text,
    default_currency text,
    roles            text[],
    visibility       text,
    theme            text,
    suspended        boolean,
    plan             text,
    owner_name       text
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        o.id, o.name, o.slug, o.profile, o.default_currency,
        array['platform_admin'::text],
        'full'::text,
        o.theme,
        (o.suspended_at is not null),
        org_plan(o.id),
        (select person_name(m.user_id) from memberships m
          where m.org_id = o.id and m.role = 'owner'
          order by m.created_at limit 1)
    from orgs o
    where exists(select 1 from profiles where id = auth.uid() and is_platform_admin)

    union all

    select
        o.id, o.name, o.slug, o.profile, o.default_currency,
        array_agg(distinct m.role::text order by m.role::text),
        case when bool_or(m.visibility = 'full') then 'full' else 'summary' end,
        o.theme,
        (o.suspended_at is not null),
        org_plan(o.id),
        (select person_name(w.user_id) from memberships w
          where w.org_id = o.id and w.role = 'owner'
          order by w.created_at limit 1)
    from memberships m
    join orgs o on o.id = m.org_id
    where m.user_id = auth.uid()
      and o.archived_at is null
      and not exists(select 1 from profiles where id = auth.uid() and is_platform_admin)
    group by o.id, o.name, o.slug, o.profile, o.default_currency, o.theme,
             o.suspended_at

    order by name;
$$;

-- ------------------------------------------------------------
-- 10. The stock follows its corrections
-- ------------------------------------------------------------
-- 034's correction of a batch, and now the shelf with it: the output
-- product moves by what the count changed (« 20 » corrected to « 40 » puts
-- 20 more cakes on the shelf). The ingredients stay as consumed (034).
create or replace function update_production_run(
    p_run_id       uuid,
    p_quantity     numeric     default null,
    p_product_name text        default null,
    p_note         text        default null,
    p_occurred_at  timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_run production_runs%rowtype;
begin
    if auth.uid() is null then
        raise exception 'update_production_run() needs a signed-in caller';
    end if;

    select * into v_run from production_runs where id = p_run_id for update;

    if v_run.id is null then
        raise exception 'No such production run';
    end if;
    if not can_write_org(v_run.org_id) then
        raise exception 'You cannot correct entries for this business';
    end if;
    if p_quantity is not null and p_quantity <= 0 then
        raise exception 'A production needs the quantity that was made (got %)',
            p_quantity;
    end if;

    update production_runs set
        quantity     = coalesce(p_quantity, quantity),
        product_name = coalesce(nullif(btrim(coalesce(p_product_name, '')), ''),
                                product_name),
        note         = coalesce(p_note, note),
        occurred_at  = coalesce(p_occurred_at, occurred_at),
        unit_cost    = case
                         when p_quantity is not null and p_quantity > 0
                         then round(total_cost / p_quantity, 4)
                         else unit_cost
                       end
    where id = p_run_id;

    if p_quantity is not null and p_quantity <> v_run.quantity
       and v_run.product_id is not null then
        update products
           set quantity = quantity + (p_quantity - v_run.quantity)
         where id = v_run.product_id;
    end if;

    return p_run_id;
end;
$$;

-- 033's correction of a flock event, held to 009's rule: no more birds out
-- than the flock has.
create or replace function update_flock_event(
    p_event_id    uuid,
    p_quantity    numeric     default null,
    p_kind        text        default null,
    p_note        text        default null,
    p_occurred_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org   uuid;
    v_flock uuid;
    v_ev    flock_events%rowtype;
    v_kind  text;
    v_qty   numeric;
    v_alive numeric;
begin
    if auth.uid() is null then
        raise exception 'update_flock_event() needs a signed-in caller';
    end if;

    select e.* into v_ev from flock_events e where e.id = p_event_id;
    select f.org_id, f.id into v_org, v_flock from flocks f where f.id = v_ev.flock_id;

    if v_org is null then
        raise exception 'No such flock event';
    end if;
    if not can_write_org(v_org) then
        raise exception 'You cannot correct entries for this business';
    end if;
    if p_quantity is not null and p_quantity < 0 then
        raise exception 'A count cannot be negative (got %)', p_quantity;
    end if;

    v_kind := coalesce(nullif(btrim(coalesce(p_kind, '')), ''), v_ev.kind);
    v_qty  := coalesce(p_quantity, v_ev.quantity);
    if v_kind in ('mortality', 'sold') then
        select f.bird_count - coalesce(sum(e.quantity) filter (
                   where e.kind in ('mortality', 'sold') and e.id <> p_event_id), 0)
          into v_alive
          from flocks f
          left join flock_events e on e.flock_id = f.id
         where f.id = v_flock
         group by f.bird_count;
        if v_qty > v_alive then
            raise exception
                'Only % birds left in this flock, cannot record % as %',
                v_alive, v_qty, v_kind;
        end if;
    end if;

    update flock_events set
        quantity    = v_qty,
        kind        = v_kind,
        note        = coalesce(p_note, note),
        occurred_at = coalesce(p_occurred_at, occurred_at)
    where id = p_event_id;

    return p_event_id;
end;
$$;

-- ------------------------------------------------------------
-- Grants (063: a new function is born closed to anon and PUBLIC; Supabase
-- hands it to authenticated, which the internal ones must not keep)
-- ------------------------------------------------------------
revoke execute on function org_setup_done(uuid)                         from public;
revoke execute on function org_workers(uuid)                            from public;
revoke execute on function org_free_workers(uuid)                       from public;
revoke execute on function team_seats(uuid)                             from public;
revoke execute on function team_full_message(uuid)                      from public;
revoke execute on function team_full(uuid)                              from public;
revoke execute on function trg_cap_free_plan()                          from public;
revoke execute on function trg_invitation_seat()                        from public;
revoke execute on function claim_my_invitations()                       from public;
revoke execute on function person_name(uuid)                            from public;
revoke execute on function team_overview(uuid)                          from public;
revoke execute on function set_member_salary(uuid, uuid, numeric, text) from public;
revoke execute on function org_photo_items(uuid)                        from public;
revoke execute on function org_photo_limit(uuid)                        from public;
revoke execute on function photo_state(uuid)                            from public;
revoke execute on function trg_photo_items()                            from public;
revoke execute on function cauris_expire(uuid)                          from public;
revoke execute on function cauris_promo_left(uuid)                      from public;
revoke execute on function cauris_take(uuid, int, text, text)           from public;
revoke execute on function spend_cauris(uuid, text)                     from public;
revoke execute on function buy_photo_slot(uuid)                         from public;
revoke execute on function cauris_feature_label(text)                   from public;
revoke execute on function platform_give_cauris(uuid, int, text, date)  from public;
revoke execute on function platform_give_unlock(uuid, text, date, text) from public;
revoke execute on function feature_states(uuid)                         from public;
revoke execute on function my_cauris(uuid)                              from public;
revoke execute on function league_scores(timestamptz, timestamptz)      from public;
revoke execute on function cauris_watch()                               from public;
revoke execute on function path_progress(uuid, text)                    from public;
revoke execute on function plan_terms()                                 from public;
revoke execute on function my_orgs()                                    from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function org_setup_done(uuid)                         from anon;
        revoke execute on function org_workers(uuid)                            from anon;
        revoke execute on function org_free_workers(uuid)                       from anon;
        revoke execute on function team_seats(uuid)                             from anon;
        revoke execute on function team_full_message(uuid)                      from anon;
        revoke execute on function team_full(uuid)                              from anon;
        revoke execute on function trg_cap_free_plan()                          from anon;
        revoke execute on function trg_invitation_seat()                        from anon;
        revoke execute on function claim_my_invitations()                       from anon;
        revoke execute on function person_name(uuid)                            from anon;
        revoke execute on function team_overview(uuid)                          from anon;
        revoke execute on function set_member_salary(uuid, uuid, numeric, text) from anon;
        revoke execute on function org_photo_items(uuid)                        from anon;
        revoke execute on function org_photo_limit(uuid)                        from anon;
        revoke execute on function photo_state(uuid)                            from anon;
        revoke execute on function trg_photo_items()                            from anon;
        revoke execute on function cauris_expire(uuid)                          from anon;
        revoke execute on function cauris_promo_left(uuid)                      from anon;
        revoke execute on function cauris_take(uuid, int, text, text)           from anon;
        revoke execute on function spend_cauris(uuid, text)                     from anon;
        revoke execute on function buy_photo_slot(uuid)                         from anon;
        revoke execute on function cauris_feature_label(text)                   from anon;
        revoke execute on function platform_give_cauris(uuid, int, text, date)  from anon;
        revoke execute on function platform_give_unlock(uuid, text, date, text) from anon;
        revoke execute on function feature_states(uuid)                         from anon;
        revoke execute on function my_cauris(uuid)                              from anon;
        revoke execute on function league_scores(timestamptz, timestamptz)      from anon;
        revoke execute on function cauris_watch()                               from anon;
        revoke execute on function path_progress(uuid, text)                    from anon;
        revoke execute on function my_orgs()                                    from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- The engine: read inside the triggers and the readers, as their
        -- owner. Nobody calls it from an app.
        revoke execute on function org_setup_done(uuid)                         from authenticated;
        revoke execute on function org_workers(uuid)                            from authenticated;
        revoke execute on function org_free_workers(uuid)                       from authenticated;
        revoke execute on function team_seats(uuid)                             from authenticated;
        revoke execute on function team_full_message(uuid)                      from authenticated;
        revoke execute on function team_full(uuid)                              from authenticated;
        revoke execute on function trg_cap_free_plan()                          from authenticated;
        revoke execute on function trg_invitation_seat()                        from authenticated;
        revoke execute on function person_name(uuid)                            from authenticated;
        revoke execute on function org_photo_items(uuid)                        from authenticated;
        revoke execute on function org_photo_limit(uuid)                        from authenticated;
        revoke execute on function photo_state(uuid)                            from authenticated;
        revoke execute on function trg_photo_items()                            from authenticated;
        revoke execute on function cauris_expire(uuid)                          from authenticated;
        revoke execute on function cauris_promo_left(uuid)                      from authenticated;
        revoke execute on function cauris_take(uuid, int, text, text)           from authenticated;
        revoke execute on function cauris_feature_label(text)                   from authenticated;
        revoke execute on function league_scores(timestamptz, timestamptz)      from authenticated;
        revoke execute on function path_progress(uuid, text)                    from authenticated;
        -- The app's doors; each checks who is asking.
        grant execute on function claim_my_invitations()                       to authenticated;
        grant execute on function team_overview(uuid)                          to authenticated;
        grant execute on function set_member_salary(uuid, uuid, numeric, text) to authenticated;
        grant execute on function spend_cauris(uuid, text)                     to authenticated;
        grant execute on function buy_photo_slot(uuid)                         to authenticated;
        grant execute on function platform_give_cauris(uuid, int, text, date)  to authenticated;
        grant execute on function platform_give_unlock(uuid, text, date, text) to authenticated;
        grant execute on function feature_states(uuid)                         to authenticated;
        grant execute on function my_cauris(uuid)                              to authenticated;
        grant execute on function cauris_watch()                               to authenticated;
        grant execute on function plan_terms()                                 to authenticated;
        grant execute on function my_orgs()                                    to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
