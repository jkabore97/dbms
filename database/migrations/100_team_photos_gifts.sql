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
--      name of an unlinked one, or adding it as a permanent's — and
--      employees.pay_period says per what. The payroll reads the period: a
--      permanent's salary is what one payment pays (a month's, a week's, a
--      day's) and « Paie et journées » says « / mois », « / semaine »,
--      « / jour ». A row's kind is never changed (somebody paid by the hour
--      keeps their rate, changed in the payroll), and clearing a salary
--      touches the amount only — an ended employment stays ended. Recording
--      is free; PAYING (shifts, staff_payments) keeps 066's Pro guard.
--      team_overview(org) is what the screen reads: the seats, the people
--      with their pay and their grants (to remove one), and the invitations
--      still out, each saying whether it can still come in. Same for all
--      three kinds.
--   2. Workers are earned. The owner plus ONE worker (any member who is
--      not an owner) is free once the first setup is done — 091's
--      setup_done_at; an association, a church or a generic business has
--      no walkthrough, so for them it is done. More needs Mara Pro or the
--      team unlocked with cauris ('team_access', 085: org_has()). 066's
--      cap on memberships (trg_cap_free_plan) is where every path that adds
--      a member passes — claim_invitation, claim_my_invitations, a direct
--      insert by an admin — so it is replaced, and it now runs on an update
--      too (a row turned from an owner's or a trainer's into a worker's, or
--      moved onto somebody else, is somebody new), one claim at a time per
--      business. The free count is the platform setting free_max_staff,
--      moved once from 066's 3 to 1 (a setting changed later by the platform
--      is never touched again), and it is 0 until the setup is done. A
--      trainer (038), Mara's own admins, an owner, and somebody already in
--      the business (a second grant adds nobody) never take the seat.
--      Nobody already there is removed: only adding is refused. An
--      invitation is refused at its writing too when the seat is already
--      taken (unless it is for somebody already in), so the owner hears it,
--      not the invitee; and the sign-in sweep skips an invitation the
--      business has no seat for instead of failing the whole sweep.
--      The back doors (security): 004 let a business's admins write any
--      membership, so an admin could add a trainer's grant (no seat, hidden
--      from the team), invite or insert an owner, or move or demote the
--      owner's row. Only the platform names a trainer or an owner now
--      (trg_membership_roles, 004's policies narrowed, owners' invitations
--      refused — invite_employee's included); the functions that open a
--      business write its first owner as before.
--   3. Photos on Basic: at most free_photo_items (10) photographed
--      articles or services — an active product with at least one
--      picture. The 11th needs Mara Pro or a photo slot bought with
--      cauris: cauris_costs 'photo_slot', 50, permanent (orgs.photo_slots;
--      the price the platform's, like every cost; refused to Pro and a
--      showcase, which have no limit). Held where a picture becomes an
--      article's — a document inserted on it, moved onto it, or re-filed
--      into a photo — and where an archived article comes back with one;
--      one at a time per business. Articles already photographed past the
--      limit keep their photos. Showcase vitrines (094) and Mara's admins
--      are exempt. No limit on the number of articles. Same for all three
--      kinds — an association's services are photographed like a shop's.
--      A picture is not paperwork (doc_is_photo): a delivery note filed on
--      the first article delivered (kind 'invoice') or a receipt takes no
--      photo place and stays under 066's general cap (free_max_photos).
--      Security: the vitrine took an article's newest DOCUMENT as its
--      picture, and the photo gate served any document of a published
--      article to the street — a supplier's delivery note could be the
--      public picture. storefront_products, search_products,
--      storefront_featured, storefront_previews and storefront_photo_allowed
--      now take pictures only (as do vitrine_score, vitrine_checklist,
--      path_progress and the Articles page's product_photo_keys).
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
--      « Offert par Mara » with no cauris spent — or lengthens a tool the
--      business bought, which stays its own. Each is rung to the business's
--      admins with its params (099). A gift is not earned: it is kept out
--      of the week's score and the leagues (league_scores, my_cauris' week,
--      path_state's week, cauris_watch), and an unlock given is not the
--      business's « premier outil » on Le Chemin (path_progress). A
--      showcase vitrine is refused (its ledger drops every line, 094).
--   6. my_orgs() carries owner_name — the owner's name, for the picker.
--  10. The stock audit. Two corrections did not follow the stock:
--      update_production_run (034) changed a batch's output count and left
--      the shelf with the old one — « 20 » corrected to « 40 » kept 20
--      cakes in stock; now the shelf moves by the difference, and the
--      article's cost price (026: the latest batch's unit cost) follows
--      while it is still this batch's. And update_flock_event (033) let a
--      correction take more birds out of a flock than are left (« 3 »
--      typed as « 300 »), the very thing record_flock_event (009) refuses;
--      now it refuses it too.
--
-- Functions replaced, each from its latest definition: trg_cap_free_plan
-- (066), claim_my_invitations (017), plan_terms (082), cauris_expire
-- (084), spend_cauris (085), feature_states (091), my_cauris (097),
-- path_progress and path_state (097), league_scores (086), cauris_watch
-- (084), my_orgs (065, dropped and recreated: its columns grow),
-- update_production_run (034), update_flock_event (033),
-- storefront_photo_allowed (093), storefront_products, search_products,
-- storefront_featured, storefront_previews, vitrine_score and
-- vitrine_checklist (098), product_photo_keys (079); 004's insert, update
-- and delete policies on memberships.
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

comment on column employees.salary is
    'A permanent''s salary for one pay_period (100; null period = a month, as 012 had it). '
    'Ignored for casuals, who are paid hourly_rate for their shifts.';

-- A picture of an article, as against the paperwork filed on it. The app
-- writes 'photo' (record_document's default, « Autre » in the gallery),
-- 'product_photo' (the article's sheet, À vendre, a service), 'receipt' and
-- 'invoice' (a receipt; a delivery note, which confirm_products_screen files
-- on the first article delivered), and 'logo' (080, never an article's);
-- null reads as a photo. A PDF is never a picture (079). The photo count,
-- the vitrine and the photo gate (storefront_photo_allowed, read by anon)
-- take only pictures: a supplier's delivery note filed on an article is not
-- its public picture.
create or replace function doc_is_photo(p_kind text, p_content_type text default null)
returns boolean
language sql
immutable
set search_path = public
as $$
    select coalesce(p_kind, 'photo') not in ('invoice', 'receipt', 'logo')
       and coalesce(p_content_type, '') not ilike '%pdf%';
$$;

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
                          and u.until > now()),
        -- Opened by Mara (platform_give_unlock), not bought: « Offert par Mara ».
        'gift',       coalesce((select u.gifted_by is not null from cauris_unlocks u
                                 where u.org_id = p_org_id and u.feature = 'team_access'
                                   and u.until > now()), false)
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
        -- What the row makes of its person. An owner, a trainer (only the
        -- platform names one: trg_membership_roles) or Mara's own admin is
        -- no worker.
        if new.role = 'owner' or coalesce(new.is_trainer, false)
           or exists (select 1 from profiles where id = new.user_id and is_platform_admin) then
            return new;
        end if;
        -- A worker's row that stays a worker's — another role between
        -- workers, the same person, the same business — adds nobody. A row
        -- that stops being an owner's or a trainer's, or that changes hands
        -- or business, is somebody new: it takes the seat like an insert.
        if tg_op = 'UPDATE'
           and old.user_id = new.user_id and old.org_id = new.org_id
           and old.role <> 'owner' and not coalesce(old.is_trainer, false) then
            return new;
        end if;
        -- Somebody already there by another grant — a worker, or still its
        -- owner — adds nobody either. A trainer's grant does not count: a
        -- trainer given a second role becomes a worker.
        if exists (select 1 from memberships m
                    where m.org_id = new.org_id and m.user_id = new.user_id
                      and m.id <> new.id and not m.is_trainer) then
            return new;
        end if;
        -- One at a time per business: two codes claimed at once cannot both
        -- take the last seat.
        perform pg_advisory_xact_lock(hashtext('team:' || new.org_id::text));
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
        -- An article's picture is counted by article (trg_photo_items); the
        -- paperwork filed on an article (a delivery note, a receipt) is
        -- counted here, with every capture that is about no article.
        if new.product_id is not null and doc_is_photo(new.kind, new.content_type) then
            return new;
        end if;
        v_cap := plan_limit('free_max_photos', 50);
        select count(*) into v_count from documents
         where org_id = new.org_id
           and (product_id is null or not doc_is_photo(kind, content_type));
        if v_count >= v_cap then
            raise exception 'Kaj Pro : la formule gratuite garde % photos. Ouvrez Compte › Kaj Pro pour en ajouter.', v_cap;
        end if;
    end if;

    return new;
end;
$$;

-- 066's cap ran on an insert only: a row edited by an admin (004 lets them)
-- from an owner's or a trainer's into a worker's, or onto somebody else,
-- walked past it. Now on an update too.
drop trigger if exists cap_free_staff on memberships;
create trigger cap_free_staff
before insert or update on memberships
for each row execute function trg_cap_free_plan();

-- Who may make an owner or a trainer. 004 lets a business's admins write
-- memberships directly, so an admin could insert a trainer's grant (038: a
-- trainer takes no seat and is hidden from the team), or an owner's, or
-- move the owner's own row onto themselves. The platform names trainers
-- (assign_trainer) and owners. The functions that open a business
-- (create_org, approve_org_application, 094's showcases) write its first
-- owner: an owner's grant is taken only while the business has none, and a
-- written-straight-from-the-app one never (004's policies, below). No
-- transfer of ownership exists yet (044 says it comes first); when it does,
-- it is the platform's act or a definer function of its own.
create or replace function trg_membership_roles()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return new;
    end if;
    if (tg_op = 'INSERT' and coalesce(new.is_trainer, false))
       or (tg_op = 'UPDATE' and new.is_trainer is distinct from old.is_trainer) then
        raise exception 'Seule la plateforme nomme une formatrice ou un formateur'
            using errcode = 'insufficient_privilege';
    end if;
    -- 044 refuses it in set_membership_role; any other write too.
    if tg_op = 'UPDATE' and old.role = 'owner'
       and (new.role is distinct from old.role
            or new.user_id is distinct from old.user_id
            or new.org_id is distinct from old.org_id) then
        raise exception 'Le propriétaire ne se change pas ici'
            using errcode = 'insufficient_privilege';
    end if;
    if new.role = 'owner' and (tg_op = 'INSERT' or old.role is distinct from 'owner')
       and exists (select 1 from memberships m
                    where m.org_id = new.org_id and m.role = 'owner' and m.id <> new.id) then
        raise exception 'Seule la plateforme nomme un propriétaire'
            using errcode = 'insufficient_privilege';
    end if;
    return new;
end;
$$;

drop trigger if exists membership_roles on memberships;
create trigger membership_roles
before insert or update on memberships
for each row execute function trg_membership_roles();

-- 004's door for an admin's own writes, narrowed: no owner's grant and no
-- trainer's is written, changed or (for the owner's) removed straight from
-- the app, except by Mara's admins — the owner leaving their own business
-- aside. The definer functions above do not pass through a policy; the
-- trigger holds them. Everything else an admin did, they still do.
drop policy if exists "memberships granted by org admins" on memberships;
create policy "memberships granted by org admins"
on memberships for insert
with check (
    is_org_admin(org_id)
    and ((role <> 'owner' and not is_trainer)
         or exists (select 1 from profiles where id = auth.uid() and is_platform_admin))
);

drop policy if exists "memberships amended by org admins" on memberships;
create policy "memberships amended by org admins"
on memberships for update
using (
    is_org_admin(org_id)
    and ((role <> 'owner' and not is_trainer)
         or exists (select 1 from profiles where id = auth.uid() and is_platform_admin))
)
with check (
    is_org_admin(org_id)
    and ((role <> 'owner' and not is_trainer)
         or exists (select 1 from profiles where id = auth.uid() and is_platform_admin))
);

drop policy if exists "memberships revoked by org admins" on memberships;
create policy "memberships revoked by org admins"
on memberships for delete
using (
    is_org_admin(org_id)
    and (role <> 'owner' or user_id = auth.uid()
         or exists (select 1 from profiles where id = auth.uid() and is_platform_admin))
);

-- An invitation: never for an owner (the platform's to name — an invitation
-- claimed becomes a membership through a definer function, so it is held
-- here, at its writing, invite_employee's included); and, when the seat is
-- already taken, said to the owner now rather than to the invitee later —
-- unless it is for somebody already in the business (by their number), who
-- takes no new seat.
create or replace function trg_invitation_seat()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return new;
    end if;
    if new.role = 'owner' then
        raise exception 'Seule la plateforme nomme un propriétaire'
            using errcode = 'insufficient_privilege';
    end if;
    if tg_op = 'UPDATE' then
        return new;
    end if;
    if team_full(new.org_id)
       and not (new.phone is not null and exists (
                select 1 from memberships m
                  join profiles p on p.id = m.user_id
                  left join auth.users u on u.id = m.user_id
                 where m.org_id = new.org_id
                   and (p.phone = new.phone or u.phone = new.phone))) then
        raise exception '%', team_full_message(new.org_id);
    end if;
    return new;
end;
$$;

drop trigger if exists invitation_seat on pending_invitations;
create trigger invitation_seat
before insert or update of role on pending_invitations
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
        exception when raise_exception or insufficient_privilege then
            continue;  -- no seat, or a grant only the platform makes (100):
                       -- left for later, the rest go on
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
--
-- A member's pay is their payroll row's: a permanent's salary for its
-- period, or — for somebody paid by the hour in « Paie et journées » — the
-- hourly rate, which is changed there. Each member carries their grants
-- (to remove them from the team), and each invitation says whether it can
-- still come in: not when the seat is taken, unless it is for somebody
-- already in the business.
create or replace function team_overview(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_full boolean;
begin
    if auth.uid() is null or not is_org_admin(p_org_id) then
        return null;
    end if;
    v_full := team_full(p_org_id);
    return jsonb_build_object(
        'seats', team_seats(p_org_id),
        'members', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'user_id', u.user_id,
                       'name', person_name(u.user_id),
                       'phone', p.phone,
                       'roles', to_jsonb(u.roles),
                       'owner', 'owner' = any (u.roles),
                       'me', u.user_id = auth.uid(),
                       'since', u.since,
                       'memberships', to_jsonb(u.ids),
                       'salary', case when e.kind = 'permanent' and e.salary > 0 then e.salary end,
                       'period', case when e.kind = 'permanent' and e.salary > 0
                                      then coalesce(e.pay_period, 'month') end,
                       'hourly', case when e.kind = 'casual' and e.hourly_rate > 0
                                      then e.hourly_rate end,
                       'employee_id', e.id)
                   order by ('owner' = any (u.roles)) desc, lower(person_name(u.user_id)))
              from (select m.user_id,
                           array_agg(distinct m.role::text order by m.role::text) as roles,
                           array_agg(m.id order by m.created_at) as ids,
                           min(m.created_at) as since
                      from memberships m
                     where m.org_id = p_org_id and not m.is_trainer
                     group by m.user_id) u
              join profiles p on p.id = u.user_id
              left join lateral (
                  select x.id, x.kind, x.salary, x.hourly_rate, x.pay_period from employees x
                   where x.org_id = p_org_id and x.user_id = u.user_id and x.is_active
                   order by x.created_at limit 1) e on true), '[]'::jsonb),
        'invitations', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'id', i.id, 'code', i.code, 'phone', i.phone,
                       'name', i.full_name, 'role', i.role,
                       'expires_at', i.expires_at,
                       'blocked', v_full and not (i.phone is not null and exists (
                           select 1 from memberships m
                             join profiles q on q.id = m.user_id
                             left join auth.users a on a.id = m.user_id
                            where m.org_id = p_org_id
                              and (q.phone = i.phone or a.phone = i.phone))))
                   order by i.created_at desc)
              from pending_invitations i
             where i.org_id = p_org_id and i.claimed_at is null
               and i.expires_at > now()), '[]'::jsonb),
        'org_name', (select name from orgs where id = p_org_id)
    );
end;
$$;

-- A member's salary, on their payroll row (012), for a period: par mois,
-- par semaine, par jour. Null or 0 clears it. Free: the payroll's Pro guard
-- is on paying (shifts, staff_payments), not here.
--
-- The payroll reads the period (100): a permanent's salary is what one
-- pay_employee() pays — a month's, a week's or a day's — and « Paie et
-- journées » writes « / mois », « / semaine », « / jour » beside it. A row's
-- kind is never changed here: somebody paid by the hour (a casual, whose
-- shifts are the record) keeps their rate, changed in « Paie et journées »;
-- a new row is a permanent's. Clearing touches the amount only — an ended
-- employment stays ended; recording a salary for a member whose row had
-- ended brings it back, as re-adding them in the payroll does (012).
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
    v_row    employees%rowtype;
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
    select * into v_row from employees
     where org_id = p_org_id and user_id = p_user_id
     order by is_active desc, created_at limit 1;
    if v_row.id is null then
        select * into v_row from employees
         where org_id = p_org_id and user_id is null
           and lower(btrim(full_name)) = lower(btrim(v_name))
         order by is_active desc, created_at limit 1;
    end if;

    if v_row.id is null then
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

    if v_amount = 0 then
        -- The amount only: nothing comes back to life, no kind changes, and
        -- a row of the same name not linked to this account is somebody
        -- else's, left alone (the screen reads only a linked row).
        if v_row.user_id is null then
            return null;
        end if;
        update employees
           set salary     = case when kind = 'permanent' then 0 else salary end,
               pay_period = case when kind = 'permanent' then null else pay_period end
         where id = v_row.id;
        return v_row.id;
    end if;

    if v_row.kind <> 'permanent' then
        raise exception 'Cette personne est payée à l''heure dans « Paie et journées » : son taux se change là-bas.';
    end if;

    update employees
       set user_id    = p_user_id,
           is_active  = true,
           ended_on   = null,
           end_reason = null,
           salary     = v_amount,
           pay_period = v_period
     where id = v_row.id;
    return v_row.id;
end;
$$;

-- ------------------------------------------------------------
-- 3. Photos on Basic
-- ------------------------------------------------------------
-- The articles (and services) photographed: active, with a picture — the
-- paperwork filed on an article (doc_is_photo) is not one.
create or replace function org_photo_items(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select count(*)::int from products p
     where p.org_id = p_org_id and p.is_active
       and exists (select 1 from documents d
                    where d.product_id = p.id and doc_is_photo(d.kind, d.content_type));
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

-- Where a picture becomes an article's: a document inserted on it, or one
-- moved onto it, or one on it re-filed from paperwork into a photo. One at
-- a time per business (an advisory lock), so two photos at once cannot both
-- take the last place. Refused at a filing, the capture stays in Documents,
-- with no article: the message says so (the app sends the bytes first and
-- files them after, so a photo taken offline is never lost).
create or replace function trg_photo_items()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_limit int;
begin
    if new.product_id is null or not doc_is_photo(new.kind, new.content_type) then
        return new;  -- no article, or paperwork: 066's general cap
    end if;
    if tg_op = 'UPDATE' and old.product_id is not distinct from new.product_id
       and doc_is_photo(old.kind, old.content_type) then
        return new;  -- already this article's picture
    end if;
    if auth.uid() is null
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return new;
    end if;
    v_limit := org_photo_limit(new.org_id);
    if v_limit is null then
        return new;
    end if;
    perform pg_advisory_xact_lock(hashtext('photos:' || new.org_id::text));
    -- Another picture of an article already photographed takes no new
    -- place; an article out of the shop is counted when it comes back
    -- (trg_photo_revive).
    if exists (select 1 from documents d
                where d.product_id = new.product_id and d.id <> new.id
                  and doc_is_photo(d.kind, d.content_type))
       or not exists (select 1 from products p
                       where p.id = new.product_id and p.is_active) then
        return new;
    end if;
    if org_photo_items(new.org_id) >= v_limit then
        if tg_op = 'UPDATE' then
            raise exception 'Kaj Pro : toutes vos places photo sont prises. '
                'La photo reste dans vos documents, sans article. Pour la mettre sur l''article : '
                'Mara Pro, ou une place photo achetée avec des cauris.';
        end if;
        raise exception 'Kaj Pro : toutes vos places photo sont prises. '
            'Pour photographier un article de plus : Mara Pro, ou une place photo achetée avec des cauris.';
    end if;
    return new;
end;
$$;

drop trigger if exists photo_items_limit on documents;
create trigger photo_items_limit
before insert or update of product_id, kind, content_type on documents
for each row execute function trg_photo_items();

-- An article out of the shop (027's archive) gives its place back; brought
-- back with its picture — archive_product(…, false), or 051's re-add by its
-- name — it takes one again, and is refused when none is left.
create or replace function trg_photo_revive()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_limit int;
begin
    if old.is_active or not new.is_active
       or auth.uid() is null
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
       or not exists (select 1 from documents d
                       where d.product_id = new.id and doc_is_photo(d.kind, d.content_type)) then
        return new;
    end if;
    v_limit := org_photo_limit(new.org_id);
    if v_limit is null then
        return new;
    end if;
    perform pg_advisory_xact_lock(hashtext('photos:' || new.org_id::text));
    if org_photo_items(new.org_id) >= v_limit then
        raise exception 'Kaj Pro : cet article a une photo et toutes vos places photo sont prises. '
            'Pour le remettre : Mara Pro, une place photo achetée avec des cauris, '
            'ou un autre article photographié retiré.';
    end if;
    return new;
end;
$$;

drop trigger if exists photo_revive_limit on products;
create trigger photo_revive_limit
before update of is_active on products
for each row execute function trg_photo_revive();

-- 093's photo gate, read by the uploads Worker for anon: an article's
-- picture only — a delivery note or a receipt filed on a published article
-- is not served to the street. The cover and the logo as 093.
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
          and doc_is_photo(d.kind, d.content_type)
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
          and (org_has(o.id, 'vitrine_plus')
               or cauris_param('vitrine_free_basics', 1) = 1)
    ) or exists (
        select 1
        from orgs o
        where o.logo_key = p_key
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
    );
$$;

-- 098's window, its picture the article's newest photo (not the newest
-- document: a delivery note filed on it is not its picture).
create or replace function storefront_products(p_slug text)
returns table (
    id             uuid,
    name           text,
    sale_price     numeric,
    in_stock       boolean,
    photo_key      text,
    description    text,
    unit           text,
    available_from date,
    is_service     boolean,
    price_from     boolean
)
language sql
stable
security definer
set search_path = public
as $$
    select p.id, p.name, p.sale_price,
           (p.is_service
            or p.quantity > 0
            or p.available_from > (now() at time zone 'Africa/Ouagadougou')::date),
           (select d.r2_key from documents d
             where d.product_id = p.id and doc_is_photo(d.kind, d.content_type)
             order by coalesce(d.captured_at, d.created_at) desc
             limit 1),
           nullif(btrim(p.description), ''),
           nullif(btrim(p.unit), ''),
           case when p.available_from > (now() at time zone 'Africa/Ouagadougou')::date
                then p.available_from end,
           p.is_service,
           p.price_from
    from products p
    where p.org_id = storefront_open(p_slug)
      and p.is_active
      and p.is_published
    order by p.is_service, p.name;
$$;

-- 098's search, the same picture.
create or replace function search_products(
    p_query text,
    p_lat   double precision default null,
    p_lng   double precision default null
)
returns table (
    id          uuid,
    name        text,
    sale_price  numeric,
    in_stock    boolean,
    photo_key   text,
    shop_name   text,
    shop_slug   text,
    currency    text,
    shop_lat    double precision,
    shop_lng    double precision,
    distance_km double precision
)
language sql
stable
security definer
set search_path = public
as $$
    with q as (
        select fold_search_text(btrim(coalesce(p_query, ''))) as folded
    ),
    hits as (
        select p.id, p.name, p.sale_price,
               (p.is_service or p.quantity > 0) as in_stock,
               (select d.r2_key from documents d
                 where d.product_id = p.id and doc_is_photo(d.kind, d.content_type)
                 order by coalesce(d.captured_at, d.created_at) desc
                 limit 1) as photo_key,
               o.name as shop_name, o.slug as shop_slug,
               o.default_currency as currency,
               o.lat as shop_lat, o.lng as shop_lng,
               case
                   when p_lat is null or p_lng is null
                     or o.lat is null or o.lng is null then null
                   else 6371.0 * 2 * asin(sqrt(
                            power(sin(radians(o.lat - p_lat) / 2), 2)
                          + cos(radians(p_lat)) * cos(radians(o.lat))
                          * power(sin(radians(o.lng - p_lng) / 2), 2)))
               end as distance_km,
               position((select folded from q) in fold_search_text(p.name))
                   as hit_at
        from products p
        join orgs o on o.id = p.org_id
        where length((select folded from q)) >= 2
          and fold_search_text(p.name) like
              '%' || replace(replace(replace((select folded from q),
                    '\', '\\'), '%', '\%'), '_', '\_') || '%'
          and p.is_active
          and p.is_published
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
    )
    select h.id, h.name, h.sale_price, h.in_stock, h.photo_key,
           h.shop_name, h.shop_slug, h.currency,
           h.shop_lat, h.shop_lng, h.distance_km
    from hits h
    order by (h.hit_at = 1) desc, h.in_stock desc,
             (h.distance_km is null), h.distance_km, h.name, h.shop_name
    limit 50;
$$;

-- 098's « À la une », the same picture.
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
    select p.id, p.name, p.sale_price, (p.is_service or p.quantity > 0),
           (select d.r2_key from documents d
             where d.product_id = p.id and doc_is_photo(d.kind, d.content_type)
             order by coalesce(d.captured_at, d.created_at) desc
             limit 1),
           o.name, o.slug, o.default_currency
    from products p
    join orgs o on o.id = p.org_id
    left join lateral (
        select min(pm.starts_at) as since from promotions pm
         where pm.product_id = p.id and pm.status = 'approved'
           and pm.starts_at <= now() and pm.ends_at > now()
    ) spot on true
    where (spot.since is not null or p.featured_until > now())
      and p.is_active
      and p.is_published
      and o.storefront_enabled
      and o.archived_at  is null
      and o.suspended_at is null
    order by (spot.since is null), spot.since, p.featured_until desc nulls last, p.name
    limit 12;
$$;

-- 098's street cards, the same picture.
create or replace function storefront_previews(p_slugs text[])
returns table (
    slug       text,
    product_id uuid,
    name       text,
    sale_price numeric,
    photo_key  text
)
language sql
stable
security definer
set search_path = public
as $$
    select x.slug, x.id, x.name, x.sale_price, x.photo_key
    from (
        select o.slug, p.id, p.name, p.sale_price, ph.r2_key as photo_key,
               row_number() over (
                   partition by o.id
                   order by (ph.r2_key is null),
                            (not p.is_service and p.quantity <= 0), p.name
               ) as n
        from orgs o
        join products p on p.org_id = o.id
        left join lateral (
            select d.r2_key from documents d
             where d.product_id = p.id and doc_is_photo(d.kind, d.content_type)
             order by coalesce(d.captured_at, d.created_at) desc
             limit 1
        ) ph on true
        where o.slug = any (coalesce(p_slugs, '{}'))
          and o.id = storefront_open(o.slug)
          and p.is_active
          and p.is_published
    ) x
    where x.n <= 3
    order by x.slug, x.n;
$$;

-- 098's score and checklist: « en photo » counts pictures, not paperwork.
create or replace function vitrine_score(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select (100 * (
        (published >= greatest(vitrine_min(o_id), 1))::int
      + (association or with_photo >= 3
         or (published > 0 and with_photo >= published))::int
      + blurb::int + phone::int + address::int + pin::int) / 6.0)::int
    from (
        select
            o.id as o_id,
            o.profile in ('church', 'association') as association,
            (select count(*) from products p
              where p.org_id = o.id and p.is_active and p.is_published) as published,
            (select count(*) from products p
              where p.org_id = o.id and p.is_active and p.is_published
                and exists (select 1 from documents d
                             where d.product_id = p.id
                               and doc_is_photo(d.kind, d.content_type))) as with_photo,
            nullif(btrim(coalesce(o.storefront_blurb, '')), '') is not null as blurb,
            nullif(btrim(coalesce(o.phone, '')), '') is not null as phone,
            nullif(btrim(coalesce(o.address, '')), '') is not null as address,
            (o.lat is not null and o.lng is not null) as pin
        from orgs o where o.id = p_org_id
    ) x;
$$;

create or replace function vitrine_checklist(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select case when not is_org_member(p_org_id) then null else
    jsonb_build_object(
        'open',        o.storefront_enabled,
        'min_items',   vitrine_min(o.id),
        'active',      (select count(*) from products p
                         where p.org_id = o.id and p.is_active and not p.is_ingredient),
        'published',   (select count(*) from products p
                         where p.org_id = o.id and p.is_active and p.is_published),
        'services',    (select count(*) from products p
                         where p.org_id = o.id and p.is_active and p.is_published
                           and p.is_service),
        'unpublished', (select count(*) from products p
                         where p.org_id = o.id and p.is_active and not p.is_published
                           and not p.is_ingredient and coalesce(p.sale_price, 0) > 0),
        'with_photo',  (select count(*) from products p
                         where p.org_id = o.id and p.is_active and p.is_published
                           and exists (select 1 from documents d
                                        where d.product_id = p.id
                                          and doc_is_photo(d.kind, d.content_type))),
        'blurb',       nullif(btrim(coalesce(o.storefront_blurb, '')), '') is not null,
        'address',     nullif(btrim(coalesce(o.address, '')), '') is not null,
        'phone',       nullif(btrim(coalesce(o.phone, '')), '') is not null,
        'pin',         o.lat is not null and o.lng is not null
    ) end
    from orgs o where o.id = p_org_id;
$$;

-- 079's thumbnails on the Articles page: the same picture as the vitrine.
create or replace function product_photo_keys(p_org_id uuid)
returns table (product_id uuid, photo_key text)
language sql
stable
security invoker
set search_path = public
as $$
    select distinct on (d.product_id) d.product_id, d.r2_key
    from documents d
    where d.org_id = p_org_id
      and d.product_id is not null
      and doc_is_photo(d.kind, d.content_type)
    order by d.product_id, coalesce(d.captured_at, d.created_at) desc;
$$;

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
    -- Mara Pro and a showcase have no limit: a slot would buy nothing.
    if org_photo_limit(p_org_id) is null then
        raise exception 'Cette entreprise a déjà ses photos sans limite';
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

    -- A tool the business bought and still has open stays its own: the gift
    -- only lengthens it, and never relabels it « Offert par Mara » (nor takes
    -- it off Le Chemin's « premier outil »).
    insert into cauris_unlocks (org_id, feature, until, note, gifted_by)
    values (p_org_id, p_feature, v_until, v_note, auth.uid())
    on conflict (org_id, feature) do update
        set until = greatest(cauris_unlocks.until, excluded.until),
            note = case when cauris_unlocks.gifted_by is null and cauris_unlocks.until > now()
                        then cauris_unlocks.note else excluded.note end,
            gifted_by = case when cauris_unlocks.gifted_by is null and cauris_unlocks.until > now()
                             then null else excluded.gifted_by end,
            updated_at = now()
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

-- 097's steps, verbatim but two: « Mon premier outil avec mes cauris » is
-- a tool the business opened itself, not one Mara gave it; and « en photo »
-- counts pictures, not a delivery note filed on an article.
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
                and exists (select 1 from documents d
                             where d.product_id = p.id
                               and doc_is_photo(d.kind, d.content_type)))
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

-- 097's path, its « cette semaine » as the leagues count it now: a gift
-- or promotional points from Mara are not earned (as my_cauris, league_scores).
create or replace function path_state(p_org uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth
as $$
declare
    v_profile text;
    v_stage   integer;
    v_steps   jsonb;
    v_stages  jsonb;
    v_next    text;
    v_league  boolean := false;
    v_admin   boolean;
begin
    if p_org is null or not is_org_member(p_org) then
        return null;
    end if;
    v_admin := is_org_admin(p_org);
    select o.profile::text into v_profile from orgs o where o.id = p_org;
    if v_profile is null or v_profile not in ('retail', 'farm') then
        return null;
    end if;
    perform path_sync(p_org);
    perform cauris_expire(p_org);

    select coalesce(jsonb_agg(jsonb_build_object(
               'key', r.key, 'stage', r.stage, 'title', r.title, 'line', r.line,
               'go', r.go,
               -- A step reached stays reached: it shows its goal met, even
               -- if the data fell back since.
               'progress', case when r.done then r.goal else least(r.live, r.goal) end,
               -- What the data says right now, for the gates (live).
               'live', least(r.live, r.goal),
               'goal', r.goal, 'done', r.done, 'reward', r.reward, 'opens', r.opens)
               order by r.stage, r.sort), '[]'::jsonb)
      into v_steps
      from (select s.key, s.stage, s.sort, s.reward, s.opens,
                   path_text(s.title, s.title_farm, v_profile) as title,
                   path_text(s.line, s.line_farm, v_profile) as line,
                   case when v_profile = 'farm' and s.go_farm is not null
                        then s.go_farm else s.go end as go,
                   path_progress(p_org, s.key) as live,
                   path_goal(p_org, s.key) as goal,
                   exists (select 1 from org_path_done d
                            where d.org_id = p_org and d.step = s.key) as done
              from path_steps s
             where v_profile = any (s.profiles)) r;

    select coalesce(min((e ->> 'stage')::int), 5) into v_stage
      from jsonb_array_elements(v_steps) e where not (e ->> 'done')::boolean;
    select e ->> 'key' into v_next
      from jsonb_array_elements(v_steps) with ordinality x(e, i)
     where not (e ->> 'done')::boolean order by i limit 1;

    select jsonb_agg(jsonb_build_object(
               'n', n.n,
               'title', (array['Ouvrir', 'Remplir', 'Vendre', 'Grandir'])[n.n],
               'done', not exists (select 1 from jsonb_array_elements(v_steps) e
                                    where (e ->> 'stage')::int = n.n
                                      and not (e ->> 'done')::boolean))
               order by n.n)
      into v_stages from generate_series(1, 4) n(n);

    if v_stage >= 4 then
        -- A race is businesses earning this week: one that earned once,
        -- long ago, is on the board at 0 and does not make it one.
        v_league := (select count(*) from league_scores(cauris_week_start(),
                                                        now() + interval '1 second') l
                      where l.league = league_key(p_org) and l.score > 0)
                    >= cauris_param('path_league_min', 3);
    end if;

    return jsonb_build_object(
        'stage', v_stage,
        'stages', v_stages,
        'next', v_next,
        'steps', coalesce(v_steps, '[]'::jsonb),
        'tools', jsonb_build_object(
            'invoices',        not path_locked(p_org, 'invoices'),
            'production',      not path_locked(p_org, 'production'),
            'credits',         not path_locked(p_org, 'credits'),
            'second_business', not path_locked(p_org, 'second_business')),
        -- The wallet is the admins' (as my_cauris): null for the others.
        'balance', case when v_admin then cauris_balance(p_org) end,
        -- This week's score, as the league counts it (086): Mara's gifts
        -- and promotional points (100) are not earned.
        'week', case when v_admin then
                    (select coalesce(sum(l.delta), 0)::int from cauris_ledger l
                      where l.org_id = p_org and l.delta > 0
                        and l.reason not in ('prize', 'expired', 'spent', 'gift', 'promo')
                        and l.created_at >= cauris_week_start()) end,
        'league_open', v_league
    );
end;
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
        -- 026 set the article's cost price to this batch's unit cost (the
        -- latest batch's, as receive_products does for a delivery). While
        -- it still is this batch's — no later batch, no delivery since at
        -- another cost — it follows the corrected count.
        update products
           set quantity   = quantity + (p_quantity - v_run.quantity),
               cost_price = case
                   when v_run.total_cost > 0
                    and cost_price = round(v_run.unit_cost, 2)
                    and not exists (select 1 from production_runs r
                                     where r.product_id = v_run.product_id
                                       and r.id <> v_run.id
                                       and r.created_at > v_run.created_at)
                   then round(v_run.total_cost / p_quantity, 2)
                   else cost_price end
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
revoke execute on function doc_is_photo(text, text)                     from public;
revoke execute on function trg_membership_roles()                       from public;
revoke execute on function trg_photo_revive()                           from public;
revoke execute on function path_state(uuid)                             from public;
revoke execute on function product_photo_keys(uuid)                     from public;
revoke execute on function vitrine_checklist(uuid)                      from public;
revoke execute on function vitrine_score(uuid)                          from public;
revoke execute on function storefront_photo_allowed(text)               from public;
revoke execute on function storefront_products(text)                    from public;
revoke execute on function search_products(text, double precision, double precision) from public;
revoke execute on function storefront_featured()                        from public;
revoke execute on function storefront_previews(text[])                  from public;
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
        revoke execute on function doc_is_photo(text, text)                     from anon;
        revoke execute on function trg_membership_roles()                       from anon;
        revoke execute on function trg_photo_revive()                           from anon;
        revoke execute on function path_state(uuid)                             from anon;
        revoke execute on function product_photo_keys(uuid)                     from anon;
        revoke execute on function vitrine_checklist(uuid)                      from anon;
        -- The street (052, 059, 070, 071, 098): the signed-out vitrine reads them.
        grant execute on function storefront_photo_allowed(text)                to anon;
        grant execute on function storefront_products(text)                     to anon;
        grant execute on function search_products(text, double precision, double precision) to anon;
        grant execute on function storefront_featured()                         to anon;
        grant execute on function storefront_previews(text[])                   to anon;
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
        revoke execute on function trg_membership_roles()                       from authenticated;
        revoke execute on function trg_photo_revive()                           from authenticated;
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
        -- Read inside product_photo_keys (079), which runs as the caller.
        grant execute on function doc_is_photo(text, text)                     to authenticated;
        grant execute on function path_state(uuid)                             to authenticated;
        grant execute on function product_photo_keys(uuid)                     to authenticated;
        grant execute on function vitrine_checklist(uuid)                      to authenticated;
        grant execute on function storefront_photo_allowed(text)               to authenticated;
        grant execute on function storefront_products(text)                    to authenticated;
        grant execute on function search_products(text, double precision, double precision) to authenticated;
        grant execute on function storefront_featured()                        to authenticated;
        grant execute on function storefront_previews(text[])                  to authenticated;
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
