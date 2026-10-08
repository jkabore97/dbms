-- ============================================================
-- 030_notifications.sql — the bell.
--
-- One table, one row per recipient, written by the server at the few
-- moments worth interrupting somebody for, read under RLS by the person
-- it names. The design rules, in order:
--
--   * **Notify only what the recipient can act on.** An employee's bell
--     is nearly silent by design; an owner hears about money and stock;
--     the platform admin hears about the platform. Fan-out picks the
--     audience at write time, one row each, so read/unread is personal.
--
--   * **A notification must never block the work.** Every trigger body
--     is wrapped: if writing the bell row fails for any reason, the sale
--     (or the payment, or the join) goes through and the bell stays
--     silent. Books beat bells.
--
--   * **No schedulers.** Everything here fires synchronously off writes
--     that already happen. The events that want a clock — "credit older
--     than 30 days", the end-of-day digest — are deliberately absent
--     until there is a job runner to fire them; a fake cron bolted onto
--     reads would ring at random times.
--
-- Phase 1 events: stock crossing below its threshold, somebody joining
-- the business, a credit fully repaid, a tontine round ready to close,
-- and (platform-level) a new business application.
-- ============================================================

create table if not exists notifications (
    id           uuid primary key default gen_random_uuid(),
    recipient_id uuid not null references profiles(id) on delete cascade,
    -- Null for platform-level notifications, which belong to no business.
    org_id       uuid references orgs(id) on delete cascade,
    kind         text not null,
    message      text not null,
    created_at   timestamptz not null default now(),
    read_at      timestamptz
);

create index if not exists notifications_by_recipient
    on notifications (recipient_id, created_at desc);
create index if not exists notifications_unread
    on notifications (recipient_id) where read_at is null;

comment on table notifications is
    'One row per recipient per event. Written by triggers, read by the bell.';

-- ------------------------------------------------------------
-- FAN-OUT
-- ------------------------------------------------------------

-- The audience for business events: the people who answer for the
-- business. Employees are deliberately not in it — their bell stays
-- quiet unless an event is truly theirs.
create or replace function notify_org_admins(
    p_org_id  uuid,
    p_kind    text,
    p_message text,
    p_except  uuid default null
)
returns void
language sql
security definer
set search_path = public
as $$
    insert into notifications (recipient_id, org_id, kind, message)
    select distinct m.user_id, p_org_id, p_kind, p_message
      from memberships m
     where m.org_id = p_org_id
       and m.role in ('owner', 'super_admin', 'admin')
       and (p_except is null or m.user_id <> p_except);
$$;

revoke execute on function notify_org_admins(uuid, text, text, uuid) from public;

-- ------------------------------------------------------------
-- THE EVENTS
--
-- All SECURITY DEFINER (an RLS table with no insert policy needs it) and
-- all swallowing their own failures — see the header.
-- ------------------------------------------------------------

-- Stock crossing below its threshold. On the crossing only, not on every
-- sale below it: a shelf at 3 of 5 must not ring the bell ten times a day.
create or replace function trg_notify_low_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.low_stock_at is not null
       and new.is_active
       and new.quantity <= new.low_stock_at
       and old.quantity > new.low_stock_at then
        perform notify_org_admins(new.org_id, 'low_stock',
            format('Stock bas : %s (%s restant)',
                   new.name, trim_scale(new.quantity)));
    end if;
    return new;
exception when others then
    return new;
end;
$$;

drop trigger if exists notify_low_stock on products;
create trigger notify_low_stock
after update of quantity on products
for each row execute function trg_notify_low_stock();

-- Somebody joined the business. The new member is excluded from their own
-- announcement; the first owner of a fresh org notifies nobody, since
-- there is nobody yet.
create or replace function trg_notify_member_joined()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_who text;
    v_org text;
begin
    select coalesce(nullif(btrim(coalesce(full_name, '')), ''), 'Quelqu''un')
      into v_who from profiles where id = new.user_id;
    select name into v_org from orgs where id = new.org_id;
    perform notify_org_admins(new.org_id, 'member_joined',
        format('%s a rejoint %s', coalesce(v_who, 'Quelqu''un'),
               coalesce(v_org, 'votre activité')),
        p_except => new.user_id);
    return new;
exception when others then
    return new;
end;
$$;

drop trigger if exists notify_member_joined on memberships;
create trigger notify_member_joined
after insert on memberships
for each row execute function trg_notify_member_joined();

-- A credit fully repaid — the carnet's good news.
create or replace function trg_notify_debt_settled()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_debt debts%rowtype;
    v_paid numeric;
    v_customer text;
begin
    select * into v_debt from debts where id = new.debt_id;
    select coalesce(sum(amount), 0) into v_paid
      from debt_payments where debt_id = new.debt_id;
    if v_paid >= v_debt.amount then
        select name into v_customer from customers where id = v_debt.customer_id;
        perform notify_org_admins(v_debt.org_id, 'debt_settled',
            format('Crédit soldé : %s a fini de payer %s',
                   coalesce(v_customer, 'un client'),
                   trim_scale(v_debt.amount)));
    end if;
    return new;
exception when others then
    return new;
end;
$$;

drop trigger if exists notify_debt_settled on debt_payments;
create trigger notify_debt_settled
after insert on debt_payments
for each row execute function trg_notify_debt_settled();

-- A tontine round where everyone has paid: ready to close, pot ready to
-- hand over.
create or replace function trg_notify_tontine_ready()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_t tontines%rowtype;
    v_members int;
    v_paid int;
begin
    select * into v_t from tontines where id = new.tontine_id;
    if new.round <> v_t.current_round then
        return new;
    end if;
    select count(*) into v_members
      from tontine_members where tontine_id = new.tontine_id;
    select count(*) into v_paid
      from tontine_contributions
     where tontine_id = new.tontine_id and round = v_t.current_round;
    if v_members > 0 and v_paid >= v_members then
        perform notify_org_admins(v_t.org_id, 'tontine_ready',
            format('Tontine %s : tour %s prêt à clore, tout le monde a payé',
                   v_t.name, v_t.current_round));
    end if;
    return new;
exception when others then
    return new;
end;
$$;

drop trigger if exists notify_tontine_ready on tontine_contributions;
create trigger notify_tontine_ready
after insert on tontine_contributions
for each row execute function trg_notify_tontine_ready();

-- Platform level: a new business application, for the people who approve
-- them. org_id stays null — this belongs to the platform, not a business.
create or replace function trg_notify_org_application()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into notifications (recipient_id, org_id, kind, message)
    select p.id, null, 'org_application',
           format('Nouvelle demande d''entreprise : %s', new.name)
      from profiles p
     where p.is_platform_admin;
    return new;
exception when others then
    return new;
end;
$$;

drop trigger if exists notify_org_application on org_applications;
create trigger notify_org_application
after insert on org_applications
for each row execute function trg_notify_org_application();

-- ------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ------------------------------------------------------------

alter table notifications enable row level security;

drop policy if exists "own notifications readable" on notifications;
create policy "own notifications readable"
on notifications for select using (recipient_id = auth.uid());

-- Marking read is the only write a recipient makes, and only on their own.
drop policy if exists "own notifications markable" on notifications;
create policy "own notifications markable"
on notifications for update using (recipient_id = auth.uid())
with check (recipient_id = auth.uid());

-- No insert or delete policies: rows are written by the triggers above
-- and age out of relevance rather than being erased.

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant select, update on notifications to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
