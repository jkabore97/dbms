-- ============================================================
-- 031_team_access.sql — the owner decides who sees what.
--
-- Until now the app had two speeds: admins could do everything, and
-- everybody else who wasn't an observer could do nearly everything —
-- including changing prices and renaming products, which is fine while
-- the owner is the only user and wrong the day a vendeuse is hired.
--
-- This migration gives the owner a dial per tool, per tier:
--
--   * **Tiers**: 'employee' (the employee role) and 'supervisor' (the
--     manager and supervisor roles). Owners and admins are never dialled
--     down — somebody must always be able to see everything — and the
--     observer keeps the read-only contract it has had since 004.
--   * **Features**: stable keys — products, production, credits,
--     tontines, invoices, photos, reports, staff.
--   * **Access**: 'hidden' (the tool is not offered), 'view' (look,
--     never change), 'edit' (today's behaviour).
--
-- **Defaults preserve today.** A business that never opens the screen
-- behaves exactly as before: every feature defaults to 'edit' except
-- reports, which defaults to 'view' because its screens were always
-- read-only. Rules only ever tighten.
--
-- **Where the server enforces, and where it defers.** Hiding a button is
-- courtesy; the server is the contract. Enforced here:
--
--   * product edits — the RLS update policy now demands 'edit' on
--     products, closing the price-tampering gap;
--   * the carnet — BEFORE INSERT triggers on debts and debt_payments
--     catch *every* path that grants credit or records a repayment,
--     including record_sale's credit branch and any function added
--     later, without redefining any of them;
--   * production — the same trigger on production_runs.
--
-- Deliberately not server-enforced in this round: selling (a vendeuse
-- who cannot sell is not an employee, and hiding the sale screen would
-- be configuration error, not protection), receiving stock (restocking
-- is counter work; at 'view' the UI hides the buttons), and the reports,
-- whose line-level privacy has been enforced by 006 since it shipped.
-- ============================================================

-- ------------------------------------------------------------
-- 1. THE RULES
-- ------------------------------------------------------------

create table if not exists org_feature_rules (
    org_id     uuid not null references orgs(id) on delete cascade,
    tier       text not null check (tier in ('employee', 'supervisor')),
    feature    text not null,
    access     text not null check (access in ('hidden', 'view', 'edit')),
    updated_by uuid references profiles(id),
    updated_at timestamptz not null default now(),
    primary key (org_id, tier, feature)
);

comment on table org_feature_rules is
    'The owner''s dial: per tier, per tool, hidden / view / edit. Absence means today''s default.';

alter table org_feature_rules enable row level security;

-- Everybody in the business reads the rules — the app needs them to know
-- what to draw. Only admins write them.
drop policy if exists "feature rules readable within org" on org_feature_rules;
create policy "feature rules readable within org"
on org_feature_rules for select using (is_org_member(org_id));

drop policy if exists "feature rules written by admins" on org_feature_rules;
create policy "feature rules written by admins"
on org_feature_rules for all using (is_org_admin(org_id))
with check (is_org_admin(org_id));

-- ------------------------------------------------------------
-- 2. THE QUESTION EVERY GUARD ASKS
-- ------------------------------------------------------------

-- What may the current caller do with this feature in this business?
-- 'edit' for admins always; the tier's rule otherwise; the preserving
-- default when no rule exists; 'hidden' for a stranger. A null auth.uid()
-- (a suite running as postgres, a server-side job) gets 'edit': those
-- contexts are gated elsewhere, and a guard that broke them would be
-- enforcing against the furniture.
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
        return 'edit';
    end if;

    select array_agg(distinct role) into v_roles
      from memberships
     where org_id = p_org_id and user_id = auth.uid();

    if v_roles is null then
        return 'hidden';
    end if;
    if v_roles && array['owner', 'super_admin', 'admin'] then
        return 'edit';
    end if;

    v_tier := case
        when v_roles && array['manager', 'supervisor'] then 'supervisor'
        else 'employee'
    end;

    select access into v_access
      from org_feature_rules
     where org_id = p_org_id and tier = v_tier and feature = p_feature;

    return coalesce(v_access,
        case when p_feature = 'reports' then 'view' else 'edit' end);
end;
$$;

-- ------------------------------------------------------------
-- 3. ENFORCEMENT
-- ------------------------------------------------------------

-- Prices and names: the update policy itself now demands the dial. The
-- DEFINER functions that move stock (record_sale, receive_products,
-- record_production) bypass RLS and keep working — the counter never
-- stops — but a direct edit of price, name or threshold needs 'edit'.
drop policy if exists "products updatable by staff" on products;
create policy "products updatable by staff"
on products for update
using (can_write_org(org_id) and feature_access(org_id, 'products') = 'edit')
with check (can_write_org(org_id) and feature_access(org_id, 'products') = 'edit');

-- One guard per money table, catching every writer present and future.
create or replace function trg_guard_feature_edit()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if feature_access(new.org_id, tg_argv[0]) <> 'edit' then
        raise exception '%', tg_argv[1];
    end if;
    return new;
end;
$$;

drop trigger if exists guard_credits on debts;
create trigger guard_credits
before insert on debts
for each row execute function trg_guard_feature_edit(
    'credits', 'Le carnet de crédit vous est fermé. Voyez le propriétaire.');

drop trigger if exists guard_production on production_runs;
create trigger guard_production
before insert on production_runs
for each row execute function trg_guard_feature_edit(
    'production', 'La production vous est fermée. Voyez le propriétaire.');

-- debt_payments carries no org_id; the debt knows it.
create or replace function trg_guard_repayment()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org uuid;
begin
    select org_id into v_org from debts where id = new.debt_id;
    if v_org is not null and feature_access(v_org, 'credits') <> 'edit' then
        raise exception 'Le carnet de crédit vous est fermé. Voyez le propriétaire.';
    end if;
    return new;
end;
$$;

drop trigger if exists guard_repayments on debt_payments;
create trigger guard_repayments
before insert on debt_payments
for each row execute function trg_guard_repayment();

-- ------------------------------------------------------------
-- 4. GRANTS
-- ------------------------------------------------------------

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant select, insert, update, delete on org_feature_rules to authenticated;
        grant execute on function feature_access(uuid, text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
