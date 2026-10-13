-- ============================================================
-- 134_caisse_booking_cancel.sql — batch 138: the owner's « yes to all 3 »,
-- and the weekly prize's bell taken off.
--
--   1. Expiry dates: one per article, as today. Nothing here.
--
--   2. « La caisse et la cotisation » — an association's books given the
--      money already in its box, and its usual cotisation.
--
--      THE OPENING BALANCE. The ledger has never modelled one: no
--      equity account exists in any chart (002, 009, 011 seed assets,
--      income and expenses only; 007's balance sheet adds the accumulated
--      result as a computed line, not an account). So an opening balance
--      is what every chart of accounts makes of it — a balanced journal
--      entry between the box and an equity account of its own:
--          debit  1000 Cash on Hand (or 1010 / 1020, the method)  amount
--          credit 3xxx « Solde de départ » (equity, minted the first
--                  time, in 007's 3000s band)                     amount
--      labelled « Solde de départ », details {"kind": "opening_balance"}.
--      It is not income (the income statement does not move, no « first
--      cotisation » is ticked — 102's first_income reads income credits);
--      the balance sheet shows the cash on one side and « Solde de
--      départ » under equity on the other; trial_balance, church_balances
--      and the journal show it as they show any entry.
--
--      What makes it THE opening balance is one row in books_opening
--      (org_id primary key: once). Zero is a real answer — « la caisse
--      est vide » — and writes the row with no entry (a zero entry would
--      be a line in the journal saying nothing).
--
--      set_opening_balance(org, amount, method, client_uuid) is SECURITY
--      INVOKER, as record_contribution is: the entry, its lines, the
--      equity account and the books_opening row are written under the
--      caller's own RLS — a non-member writes nothing, an observer
--      writes no entry, and only an administrator may add an account or
--      a books_opening row. The guards hold on the TABLE, not only in the
--      function, so a direct write through PostgREST meets them too
--      (trg_books_opening_guard, SECURITY DEFINER so that it sees every
--      entry of the business whatever the caller may read):
--        * an owner, super_admin or admin of an association (a platform
--          admin is not a member: RLS refuses the entry anyway);
--        * an amount of 0 or more; > 0 ⇔ an entry, written in this very
--          transaction (127's row_is_this_transactions), of this
--          business, flagged opening_balance, balanced, debiting an asset
--          and crediting an equity account by exactly the amount;
--        * once: the primary key; a second call refuses (« déjà
--          enregistré »), the same call retried (its client_uuid) answers
--          what it answered — a no-op;
--        * never over books with movements: any other journal entry of
--          the business refuses it — UNLESS it is a correction through
--          the existing correction path: the opening entry reversed by
--          reverse_entry (002, the « Annuler » of every entry) frees the
--          row to be written again (an UPDATE, the new entry dated at the
--          first one's moment, so it still comes before every movement).
--          A zero opening has nothing to reverse and stays as it is.
--
--      THE COTISATION. contribution_defaults (org_id primary key): an
--      amount > 0 and a period (week, month, year), written by an
--      administrator (set_contribution_default, INVOKER, under RLS) and
--      read by every member through books_start(): the app's « Recette »
--      › « Cotisation » fills its amount with it, still editable.
--
--      books_start(org) → jsonb — what the setup step and the home's card
--      need: whether 134 is there at all (an app on an older database
--      gets PGRST202 and shows neither), the opening (set, amount, when),
--      whether the books have movements, whether this caller may set it,
--      whether the card was put away, and the cotisation. SECURITY
--      DEFINER (a summary observer may not read the entries it counts),
--      members only, null otherwise; closed to anon.
--
--      dismiss_books_start(org): « Plus tard » on the home's card, for
--      every administrator of the business (books_start_dismissals).
--
--      association_trust (088) leaves the opening entry and its reversal
--      out of « Régulière » and « Propre »: setting the box is not keeping
--      the books, and correcting it is not a mistake.
--
--      kind_setup_steps (107): the association's walkthrough gains the
--      optional « caisse » step between the members and the vitrine, so
--      Mara can turn it off as the other two (setup_off).
--
--      Shops and farms: nothing — the tables refuse any business that is
--      not an association (or a legacy church).
--
--   3. A customer cancels a booking up to 2 hours before its slot.
--      cancel_order (099's, the customer's own door) is redefined — no
--      second door, no new status: a booking (orders.booked_for, 125)
--      that is requested (pending, nothing proposed) or confirmed
--      (accepted) is cancelled until booked_for minus
--      booking_cancel_hours() hours — a platform setting
--      (booking_cancel_hours, default 2, 0 to 168, journaled by 105's
--      platform_set_setting, its range held by a trigger here); later it
--      is refused in French (« Trop tard pour annuler : appelez la
--      boutique. ») — except a request nobody answered whose time has
--      passed (it can no longer be accepted), which is withdrawn as 099
--      let it. An order already paid — online (Wave, a card) or marked
--      paid by the business (a deposit) — is not cancelled by the
--      customer (the money is the business's to give back): refused, call
--      the business; so is one with a Wave payment opened in the last
--      30 minutes (it may still land). A proposal waiting for the customer is
--      declined by cancelling it at any time, as 099 let it (it is not an
--      agreed time). An order of goods: 099's rule, pending only.
--      The business hears a cancelled booking as booking_cancelled
--      (to: shop, 125's « Commandes de la vitrine » switch): « Rendez-vous
--      annulé par le client — mardi 14 oct., 10:00 »; a pending order or
--      a declined proposal keeps 099's order_withdrawn word for word.
--      125 holds no slot (times already taken were left for later), so
--      there is nothing to free.
--      booking_cancel_terms(order) → jsonb for its customer: the hours,
--      the moment it stops, whether it can still be cancelled, the
--      business's phone (to call or WhatsApp after the cutoff); null for
--      anybody else or an order with no slot.
--
--   4. The weekly prize's bell. cauris_week_close (086, last 099) still
--      awards the prizes — the result row, the cauris, the winner's free
--      spot and so the vitrine's badge — and rings nobody unless the new
--      platform setting cauris_prize_notify (default 0) is 1. No bell
--      row, so no push (115's webhook sends bell rows); this function
--      never sent WhatsApp. 'cauris-board' is untouched (129 keeps it
--      paused); the 'cauris-week-close' job keeps calling the same
--      function. Associations earn no cauris (084).
--
-- Re-runnable: tables and columns if not exists, policies and triggers
-- dropped and recreated, functions replaced with their own signatures,
-- settings on conflict do nothing.
-- ============================================================

do $$
begin
    if to_regprocedure('public.row_is_this_transactions(xid)') is null
       or to_regprocedure('public.booking_when_fr(timestamptz)') is null
       or to_regprocedure('public.kind_setup_steps(text)') is null
       or to_regprocedure('public.cauris_week_close(date)') is null then
        raise exception '134 needs 107 (kind_setup_steps), 125 (booking_when_fr) and 127 (row_is_this_transactions) applied first';
    end if;
end $$;

-- ------------------------------------------------------------
-- 1. The opening balance
-- ------------------------------------------------------------
create table if not exists books_opening (
    org_id      uuid primary key references orgs(id) on delete cascade,
    amount      numeric(14,2) not null check (amount >= 0),
    method      text not null default 'cash',
    entry_id    uuid references journal_entries(id),
    client_uuid uuid,
    set_by      uuid references profiles(id),
    set_at      timestamptz not null default now(),
    check ((amount > 0) = (entry_id is not null))
);

-- The opening entries it replaced (each reversed first): the trust level
-- and books_start tell the opening from the books by this, not by an
-- entry's details, which record_entry lets anybody write.
alter table books_opening add column if not exists replaced_entry_ids uuid[] not null default '{}';

comment on table books_opening is
    'An association''s opening balance (134): once, by an administrator, over books with no movement; '
    'the entry (cash debit, « Solde de départ » equity credit) when above zero.';

alter table books_opening enable row level security;

drop policy if exists "opening readable by members" on books_opening;
create policy "opening readable by members"
on books_opening for select
using (is_org_member(org_id));

drop policy if exists "opening written by admins" on books_opening;
create policy "opening written by admins"
on books_opening for insert
with check (is_org_admin(org_id));

-- Only the correction path updates it (the guard says when).
drop policy if exists "opening corrected by admins" on books_opening;
create policy "opening corrected by admins"
on books_opening for update
using (is_org_admin(org_id))
with check (is_org_admin(org_id));

-- The rules, on the table: whatever the path, the same answer.
create or replace function trg_books_opening_guard()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor   uuid := auth.uid();
    v_entry   journal_entries%rowtype;
    v_xmin    xid;
    v_debit   numeric;
    v_credit  numeric;
    v_asset   numeric;
    v_equity  numeric;
begin
    if not exists (select 1 from orgs o where o.id = new.org_id
                    and o.profile in ('association', 'church')) then
        raise exception 'Le solde de départ est celui d''une association.';
    end if;
    -- A person: an administrator of this business (the database's own
    -- writes — a migration, the platform's SQL — have no caller).
    if v_actor is not null and not exists (
        select 1 from memberships m
         where m.org_id = new.org_id and m.user_id = v_actor
           and m.role in ('owner', 'super_admin', 'admin')) then
        raise exception 'Seul un responsable de l''association peut indiquer la caisse de départ.';
    end if;
    if new.amount is null or new.amount < 0 then
        raise exception 'Un montant de 0 ou plus, s''il vous plaît.';
    end if;

    if tg_op = 'UPDATE' then
        -- The correction path: the opening entry was reversed (002's
        -- reverse_entry), and only then.
        if new.org_id <> old.org_id then
            raise exception 'Le solde de départ reste celui de son association.';
        end if;
        if old.entry_id is null or not exists (
            select 1 from journal_entries r where r.reverses_entry_id = old.entry_id) then
            raise exception 'Le solde de départ est déjà enregistré.';
        end if;
        if new.entry_id is not distinct from old.entry_id then
            raise exception 'Le solde de départ est déjà enregistré.';
        end if;
        new.replaced_entry_ids := old.replaced_entry_ids || old.entry_id;
    else
        new.replaced_entry_ids := '{}';
        -- Books with no movement: no entry but this one.
        if exists (select 1 from journal_entries je
                    where je.org_id = new.org_id
                      and je.id is distinct from new.entry_id) then
            raise exception 'Vos comptes ont déjà des mouvements : le solde de départ ne s''indique plus.';
        end if;
    end if;

    if new.entry_id is not null then
        select * into v_entry from journal_entries where id = new.entry_id;
        select xmin into v_xmin from journal_entries where id = new.entry_id;
        if not found or v_entry.org_id <> new.org_id
           or not row_is_this_transactions(v_xmin)
           or coalesce(v_entry.details ->> 'kind', '') <> 'opening_balance'
           or v_entry.reverses_entry_id is not null then
            raise exception 'Le solde de départ s''écrit avec son écriture.';
        end if;
        select coalesce(sum(jl.debit), 0), coalesce(sum(jl.credit), 0),
               coalesce(sum(jl.debit) filter (where a.type = 'asset'), 0),
               coalesce(sum(jl.credit) filter (where a.type = 'equity'), 0)
          into v_debit, v_credit, v_asset, v_equity
          from journal_lines jl join accounts a on a.id = jl.account_id
         where jl.journal_entry_id = new.entry_id;
        if v_debit <> new.amount or v_credit <> new.amount
           or v_asset <> new.amount or v_equity <> new.amount then
            raise exception 'Le solde de départ s''écrit avec son écriture.';
        end if;
        if tg_op = 'UPDATE' and old.entry_id is not null
           and v_entry.created_at <> (select created_at from journal_entries where id = old.entry_id) then
            raise exception 'Le solde de départ corrigé garde sa date.';
        end if;
    end if;

    new.set_by := coalesce(v_actor, new.set_by);
    new.set_at := now();
    return new;
end;
$$;

drop trigger if exists books_opening_guard on books_opening;
create trigger books_opening_guard
before insert or update on books_opening
for each row execute function trg_books_opening_guard();

-- 127's generic guard as on every business-owned child: the entry is this
-- business's (the guard above says it too; test_batch127 asks for this one).
drop trigger if exists same_org on books_opening;
create trigger same_org
before insert or update on books_opening
for each row execute function trg_same_org('entry_id:journal_entries');

-- The app's door. SECURITY INVOKER on purpose (as record_contribution):
-- every write below is the caller's own, under RLS.
create or replace function set_opening_balance(
    p_org_id      uuid,
    p_amount      numeric,
    p_method      text default 'cash',
    p_client_uuid uuid default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public, auth
as $$
declare
    v_actor  uuid := auth.uid();
    v_row    books_opening%rowtype;
    v_method text := lower(btrim(coalesce(p_method, 'cash')));
    v_code   text;
    v_cash   uuid;
    v_equity uuid;
    v_entry  uuid;
    v_at     timestamptz := now();
    v_fix    boolean := false;
begin
    if v_actor is null then
        raise exception 'Connectez-vous d''abord.';
    end if;
    if not exists (select 1 from memberships m
                    where m.org_id = p_org_id and m.user_id = v_actor
                      and m.role in ('owner', 'super_admin', 'admin')) then
        raise exception 'Seul un responsable de l''association peut indiquer la caisse de départ.';
    end if;
    if not exists (select 1 from orgs o where o.id = p_org_id
                    and o.profile in ('association', 'church')) then
        raise exception 'Le solde de départ est celui d''une association.';
    end if;
    if p_amount is null or p_amount < 0 then
        raise exception 'Un montant de 0 ou plus, s''il vous plaît.';
    end if;
    v_code := case v_method when 'cash' then '1000' when 'bank' then '1010'
                            when 'mobile_money' then '1020' end;
    if v_code is null then
        raise exception 'La caisse, la banque ou le Mobile Money, s''il vous plaît.';
    end if;

    -- Two taps at once: one waits for the other.
    perform pg_advisory_xact_lock(hashtext('books_opening:' || p_org_id::text));

    select * into v_row from books_opening where org_id = p_org_id;
    if found then
        -- The same call again (a phone retrying): what it said the first time.
        if p_client_uuid is not null and v_row.client_uuid = p_client_uuid then
            return jsonb_build_object('amount', v_row.amount, 'entry_id', v_row.entry_id,
                                      'set_at', v_row.set_at, 'again', true);
        end if;
        if v_row.entry_id is not null and exists (
            select 1 from journal_entries r where r.reverses_entry_id = v_row.entry_id) then
            v_fix := true;
            select created_at into v_at from journal_entries where id = v_row.entry_id;
        else
            raise exception 'Le solde de départ est déjà enregistré.';
        end if;
    elsif exists (select 1 from journal_entries je where je.org_id = p_org_id) then
        raise exception 'Vos comptes ont déjà des mouvements : le solde de départ ne s''indique plus.';
    end if;

    if p_amount > 0 then
        select id into v_cash from accounts where org_id = p_org_id and code = v_code;
        if v_cash is null then
            insert into accounts (org_id, code, name, type, created_by)
            values (p_org_id, v_code,
                    case v_code when '1000' then 'Cash on Hand' when '1010' then 'Bank Account'
                                else 'Mobile Money' end,
                    'asset', v_actor)
            returning id into v_cash;
        end if;
        select id into v_equity from accounts
         where org_id = p_org_id and type = 'equity'
           and lower(btrim(name)) = 'solde de départ'
         order by created_at, code limit 1;
        if v_equity is null then
            insert into accounts (org_id, code, name, type, description, created_by)
            values (p_org_id,
                    -- The cast only for a code of digits (a CASE: the
                    -- planner may test the range before the pattern).
                    (select (coalesce(max(c.n), 2990) + 10)::text
                       from (select case when a.code ~ '^[0-9]{1,9}$' then a.code::int end as n
                               from accounts a where a.org_id = p_org_id) c
                      where c.n between 3000 and 3989),
                    'Solde de départ', 'equity',
                    'L''argent qui était dans la caisse au début (134).', v_actor)
            returning id into v_equity;
        end if;

        insert into journal_entries (org_id, label, memo, details, created_by, created_at, client_uuid)
        values (p_org_id, 'Solde de départ',
                case when v_fix then 'Solde de départ corrigé' end,
                jsonb_build_object('kind', 'opening_balance'),
                v_actor, v_at, p_client_uuid)
        returning id into v_entry;
        insert into journal_lines (journal_entry_id, account_id, debit, credit) values
            (v_entry, v_cash,   p_amount, 0),
            (v_entry, v_equity, 0,        p_amount);
    end if;

    if v_fix then
        update books_opening
           set amount = p_amount, method = v_method, entry_id = v_entry,
               client_uuid = p_client_uuid
         where org_id = p_org_id
        returning * into v_row;
    else
        insert into books_opening (org_id, amount, method, entry_id, client_uuid, set_by)
        values (p_org_id, p_amount, v_method, v_entry, p_client_uuid, v_actor)
        returning * into v_row;
    end if;

    return jsonb_build_object('amount', v_row.amount, 'entry_id', v_row.entry_id,
                              'set_at', v_row.set_at, 'again', false);
end;
$$;

-- ------------------------------------------------------------
-- 2. The usual cotisation
-- ------------------------------------------------------------
create table if not exists contribution_defaults (
    org_id     uuid primary key references orgs(id) on delete cascade,
    amount     numeric(14,2) not null check (amount > 0),
    period     text not null check (period in ('week', 'month', 'year')),
    updated_by uuid references profiles(id),
    updated_at timestamptz not null default now()
);

comment on table contribution_defaults is
    'An association''s usual cotisation (134): pre-filled, still editable, when a cotisation is recorded.';

alter table contribution_defaults enable row level security;

drop policy if exists "cotisation readable by members" on contribution_defaults;
create policy "cotisation readable by members"
on contribution_defaults for select
using (is_org_member(org_id));

drop policy if exists "cotisation written by admins" on contribution_defaults;
create policy "cotisation written by admins"
on contribution_defaults for insert
with check (is_org_admin(org_id));

drop policy if exists "cotisation changed by admins" on contribution_defaults;
create policy "cotisation changed by admins"
on contribution_defaults for update
using (is_org_admin(org_id))
with check (is_org_admin(org_id));

drop policy if exists "cotisation removed by admins" on contribution_defaults;
create policy "cotisation removed by admins"
on contribution_defaults for delete
using (is_org_admin(org_id));

create or replace function trg_contribution_default_guard()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from orgs o where o.id = new.org_id
                    and o.profile in ('association', 'church')) then
        raise exception 'La cotisation habituelle est celle d''une association.';
    end if;
    new.updated_by := coalesce(auth.uid(), new.updated_by);
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists contribution_default_guard on contribution_defaults;
create trigger contribution_default_guard
before insert or update on contribution_defaults
for each row execute function trg_contribution_default_guard();

-- INVOKER, under RLS: an administrator's. No amount: none any more.
create or replace function set_contribution_default(
    p_org_id uuid,
    p_amount numeric,
    p_period text default 'month'
)
returns void
language plpgsql
security invoker
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord.';
    end if;
    if not exists (select 1 from memberships m
                    where m.org_id = p_org_id and m.user_id = auth.uid()
                      and m.role in ('owner', 'super_admin', 'admin')) then
        raise exception 'Seul un responsable de l''association peut fixer la cotisation.';
    end if;
    if p_amount is null then
        delete from contribution_defaults where org_id = p_org_id;
        return;
    end if;
    if p_amount <= 0 then
        raise exception 'Une cotisation de plus de zéro, s''il vous plaît.';
    end if;
    if coalesce(p_period, '') not in ('week', 'month', 'year') then
        raise exception 'Par semaine, par mois ou par an, s''il vous plaît.';
    end if;
    insert into contribution_defaults (org_id, amount, period)
    values (p_org_id, p_amount, p_period)
    on conflict (org_id) do update
       set amount = excluded.amount, period = excluded.period;
end;
$$;

-- ------------------------------------------------------------
-- 3. The home's card: put away, and what it reads
-- ------------------------------------------------------------
create table if not exists books_start_dismissals (
    org_id       uuid primary key references orgs(id) on delete cascade,
    dismissed_by uuid references profiles(id) default auth.uid(),
    dismissed_at timestamptz not null default now()
);

alter table books_start_dismissals enable row level security;

drop policy if exists "dismissal readable by members" on books_start_dismissals;
create policy "dismissal readable by members"
on books_start_dismissals for select
using (is_org_member(org_id));

drop policy if exists "dismissal written by admins" on books_start_dismissals;
create policy "dismissal written by admins"
on books_start_dismissals for insert
with check (is_org_admin(org_id));

create or replace function dismiss_books_start(p_org_id uuid)
returns void
language plpgsql
security invoker
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord.';
    end if;
    insert into books_start_dismissals (org_id) values (p_org_id)
    on conflict (org_id) do nothing;
end;
$$;

create or replace function books_start(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_o   orgs%rowtype;
    v_b   books_opening%rowtype;
    v_c   contribution_defaults%rowtype;
    v_mov boolean;
    v_adm boolean;
    v_fix boolean;
    v_ids uuid[];
begin
    if auth.uid() is null or not exists (
        select 1 from memberships m where m.org_id = p_org_id and m.user_id = auth.uid()) then
        return null;
    end if;
    select * into v_o from orgs where id = p_org_id;
    if not found then
        return null;
    end if;
    select * into v_b from books_opening where org_id = p_org_id;
    select * into v_c from contribution_defaults where org_id = p_org_id;
    -- An opening entry reversed (002's reverse_entry, the correction path)
    -- may be written again, as set_opening_balance allows: neither the
    -- reversed opening nor its reversal is a movement of the books.
    v_fix := v_b.entry_id is not null and exists (
        select 1 from journal_entries r where r.reverses_entry_id = v_b.entry_id);
    v_ids := case when v_b.org_id is null then '{}'::uuid[]
                  else array_append(v_b.replaced_entry_ids, v_b.entry_id) end;
    v_mov := exists (select 1 from journal_entries je
                      where je.org_id = p_org_id
                        and not coalesce(je.id = any (v_ids), false)
                        and not coalesce(je.reverses_entry_id = any (v_ids), false));
    v_adm := exists (select 1 from memberships m
                      where m.org_id = p_org_id and m.user_id = auth.uid()
                        and m.role in ('owner', 'super_admin', 'admin'));
    return jsonb_build_object(
        'association',    v_o.profile in ('association', 'church'),
        'opening_set',    v_b.org_id is not null and not v_fix,
        'opening_amount', case when v_fix then null else v_b.amount end,
        'opening_at',     case when v_fix then null else v_b.set_at end,
        'movements',      v_mov,
        'can_set',        v_adm and v_o.profile in ('association', 'church')
                          and ((v_b.org_id is null and not v_mov) or v_fix),
        'dismissed',      exists (select 1 from books_start_dismissals d where d.org_id = p_org_id),
        'contribution',   case when v_c.org_id is null then null
                               else jsonb_build_object('amount', v_c.amount, 'period', v_c.period) end);
end;
$$;

-- ------------------------------------------------------------
-- 4. The association's walkthrough: « La caisse et la cotisation »
-- ------------------------------------------------------------
create or replace function kind_setup_steps(p_kind text)
returns jsonb
language sql
immutable
set search_path = public
as $$
    select case when p_kind in ('association', 'church') then
        '[{"key": "identity", "label": "Le nom et ce qu''elle est", "required": true},
          {"key": "members",  "label": "Les premiers membres",     "required": false},
          {"key": "caisse",   "label": "La caisse et la cotisation", "required": false},
          {"key": "vitrine",  "label": "La vitrine",               "required": false}]'::jsonb
    when p_kind in ('retail', 'farm') then
        '[{"key": "identity", "label": "Le nom",                   "required": true},
          {"key": "article",  "label": "Le premier article",       "required": true},
          {"key": "vitrine",  "label": "La vitrine",               "required": false},
          {"key": "position", "label": "La position sur la carte", "required": false}]'::jsonb
    else '[]'::jsonb end;
$$;

-- ------------------------------------------------------------
-- 5. The settings: booking_cancel_hours, cauris_prize_notify
-- ------------------------------------------------------------
insert into platform_settings (key, value) values
    ('booking_cancel_hours', '2'),
    ('cauris_prize_notify',  '0')
on conflict (key) do nothing;

-- Their ranges, whatever writes them (105's platform_set_setting checks
-- a number is whole and 0 or more; these say the rest).
create or replace function trg_settings_134()
returns trigger
language plpgsql
set search_path = public
as $$
declare v numeric;
begin
    if jsonb_typeof(new.value) <> 'number' then
        raise exception 'Ce réglage attend un nombre.';
    end if;
    v := (new.value #>> '{}')::numeric;
    if new.key = 'booking_cancel_hours' and (v < 0 or v > 168 or v <> trunc(v)) then
        raise exception 'Un nombre d''heures de 0 à 168, s''il vous plaît.';
    end if;
    if new.key = 'cauris_prize_notify' and v not in (0, 1) then
        raise exception 'Ce réglage vaut 0 (non) ou 1 (oui).';
    end if;
    return new;
end;
$$;

drop trigger if exists settings_134_check on platform_settings;
create trigger settings_134_check
before insert or update on platform_settings
for each row when (new.key in ('booking_cancel_hours', 'cauris_prize_notify'))
execute function trg_settings_134();

-- How long before its slot a booking can still be cancelled by its customer.
create or replace function booking_cancel_hours()
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select least(greatest(coalesce(
        (select (value #>> '{}')::int from platform_settings
          where key = 'booking_cancel_hours' and jsonb_typeof(value) = 'number'), 2), 0), 168);
$$;

-- ------------------------------------------------------------
-- 6. The customer cancels (099's door, the booking's rule added)
-- ------------------------------------------------------------
create or replace function cancel_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_order   orders%rowtype;
    v_booking boolean;
    v_slot    boolean;
    v_hours   int := booking_cancel_hours();
begin
    if auth.uid() is null then
        raise exception 'Sign in first';
    end if;
    select * into v_order from orders
     where id = p_order_id and customer_id = auth.uid()
     for update;
    if not found then
        raise exception 'This order can no longer be cancelled';
    end if;
    -- 125's booking with its slot: requested or confirmed, until the
    -- slot minus the hours; a proposal waiting is declined at any time.
    v_slot := v_order.booked_for is not null;
    if v_slot and v_order.status in ('pending', 'accepted') then
        if not (v_order.status = 'pending' and v_order.proposed_for is not null) then
            -- A request nobody answered whose time has gone can no longer
            -- be accepted (125's decide_order refuses it): withdrawing it
            -- costs the business nothing, so its customer still may.
            if now() > v_order.booked_for - make_interval(hours => v_hours)
               and not (v_order.status = 'pending' and now() >= v_order.booked_for) then
                raise exception 'Trop tard pour annuler : appelez la boutique.';
            end if;
        end if;
    elsif v_order.status <> 'pending' then
        raise exception 'This order can no longer be cancelled';
    end if;
    -- Paid — online (Wave or a card, 076's wave_settle), or marked paid by
    -- the business (099's set_order_paid: a deposit in cash or Mobile
    -- Money): the money is the business's to give back, so the customer
    -- calls. Any order, not only a booking: 099 let a paid pending order
    -- be withdrawn and the money stayed with the business.
    if v_order.paid_at is not null then
        raise exception '%', case when v_slot
            then 'Ce rendez-vous est déjà payé : appelez la boutique pour l''annuler.'
            else 'Cette commande est déjà payée : appelez la boutique pour l''annuler.' end;
    end if;
    -- A Wave payment opened for it in the last half hour may still land
    -- (wave_settle marks the order paid whatever its status).
    if exists (select 1 from wave_payments w
                where w.order_id = p_order_id and w.kind = 'order'
                  and w.status in ('created', 'open') and w.created_at > now() - interval '30 minutes') then
        raise exception 'Un paiement Wave est en cours : attendez quelques minutes ou appelez la boutique.';
    end if;

    update orders
       set status = 'cancelled', updated_at = now(), decided_at = coalesce(decided_at, now())
     where id = p_order_id
    returning * into v_order;

    v_booking := v_order.fulfilment = 'pickup'
        and exists (select 1 from order_lines l where l.order_id = p_order_id)
        and not exists (select 1 from order_lines l
                         where l.order_id = p_order_id and not l.is_service);
    begin
        if v_slot and v_order.proposed_for is null then
            perform notify_org_admins(v_order.org_id, 'booking_cancelled',
                'Rendez-vous annulé par le client — ' || booking_when_fr(v_order.booked_for),
                jsonb_build_object('to', 'shop', 'order_id', v_order.id, 'booking', true,
                                   'name', v_order.customer_name, 'at', v_order.booked_for));
        else
            perform notify_org_admins(v_order.org_id, 'order_withdrawn',
                v_order.customer_name || ' a annulé sa '
                || case when v_booking then 'demande' else 'commande' end,
                jsonb_build_object('to', 'shop', 'order_id', v_order.id,
                                   'booking', v_booking, 'name', v_order.customer_name));
        end if;
    exception when others then
        null;
    end;
end;
$$;

-- What the customer's card needs to say it: until when, and whom to call.
create or replace function booking_cancel_terms(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_order orders%rowtype;
    v_hours int := booking_cancel_hours();
    v_until timestamptz;
    v_phone text;
begin
    select * into v_order from orders
     where id = p_order_id and customer_id = auth.uid() and auth.uid() is not null;
    if not found or v_order.booked_for is null then
        return null;
    end if;
    v_until := v_order.booked_for - make_interval(hours => v_hours);
    select phone into v_phone from orgs where id = v_order.org_id;
    -- cancel_order's rules, said ahead ('paid_online' keeps its name for
    -- the app; since the review it is « paid », however it was).
    return jsonb_build_object(
        'hours', v_hours,
        'until', v_until,
        'paid_online', v_order.paid_at is not null,
        'can_cancel', v_order.status in ('pending', 'accepted')
                      and v_order.paid_at is null
                      and ((v_order.status = 'pending' and v_order.proposed_for is not null)
                           or now() <= v_until
                           or (v_order.status = 'pending' and now() >= v_order.booked_for)),
        'phone', nullif(btrim(coalesce(v_phone, '')), ''));
end;
$$;

-- ------------------------------------------------------------
-- 7. The week's close: the prizes, and the bell only when Mara says
-- ------------------------------------------------------------
-- 099's body, the notification gated by cauris_prize_notify (default 0).
create or replace function cauris_week_close(p_week_start date default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_from   timestamptz := coalesce(p_week_start::timestamp at time zone 'Africa/Ouagadougou',
                                     cauris_week_start() - interval '7 days');
    v_to     timestamptz := v_from + interval '7 days';
    v_week   date := (v_from at time zone 'Africa/Ouagadougou')::date;
    v_n      int := 0;
    r        record;
    v_pts    int;
    v_notify boolean := cauris_param('cauris_prize_notify', 0) = 1;
begin
    for r in
        select x.* from (
            select s.org_id, s.league, s.score,
                   (rank() over (partition by s.league order by s.score desc, s.name))::int as rank
              from league_scores(v_from, v_to) s
             where s.score > 0
        ) x where x.rank <= 3
    loop
        insert into cauris_week_results (week_start, org_id, league, rank, score)
        values (v_week, r.org_id, r.league, r.rank, r.score)
        on conflict (week_start, org_id) do nothing;
        if not found then
            continue;  -- already closed: once per week
        end if;
        v_pts := cauris_param('cauris_prize_' || r.rank, 0);
        if v_pts > 0 then
            insert into cauris_ledger (org_id, delta, reason, ref, note)
            values (r.org_id, v_pts, 'prize', v_week::text,
                    r.rank || 'e de la semaine · ' || league_label(r.league))
            on conflict do nothing;
        end if;
        if r.rank = 1 then
            insert into promotions (org_id, kind, days, price, currency, free, status,
                                    starts_at, ends_at, decided_at, note)
            values (r.org_id, 'shop', 7, 0, 'XOF', true, 'approved',
                    next_spot_start('shop'), next_spot_start('shop') + interval '7 days',
                    now(), 'Premier de la semaine (cauris)');
        end if;
        if v_notify then
            begin
                perform notify_org_admins(r.org_id, 'cauris_prize',
                    '🏆 ' || r.rank || 'e de la semaine en ' || league_label(r.league)
                    || ' ! +' || v_pts || ' cauris'
                    || case when r.rank = 1 then ', et votre vitrine mise en avant 7 jours.' else '.' end,
                    jsonb_build_object('to', 'shop', 'league', r.league, 'rank', r.rank,
                                       'points', v_pts, 'spot', r.rank = 1));
            exception when others then null;
            end;
        end if;
        v_n := v_n + 1;
    end loop;
    return v_n;
end;
$$;

-- ------------------------------------------------------------
-- 7b. The trust level (088) leaves the opening out
-- ------------------------------------------------------------
-- 088's body word for word, but for one thing: the opening entry and the
-- reversal of one are not the books being kept. Without this the opening
-- ticked one of « Régulière »'s six weeks and one of « Propre »'s five
-- entries, and correcting it (reverse_entry) counted as a mistake.
create or replace function association_trust(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    o           orgs%rowtype;
    v_weeks     int;
    v_expenses  int;
    v_receipts  int;
    v_entries   int;
    v_reversals int;
    v_age_days  int;
    p_verified  boolean;
    p_regular   boolean;
    p_justified boolean;
    p_clean     boolean;
    p_lasting   boolean;
    v_met       int;
    v_open      uuid[];
begin
    select * into o from orgs where id = p_org_id;
    if not found or o.profile not in ('church', 'association') then
        return null;
    end if;
    if not (is_org_member(p_org_id)
            or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)) then
        return null;
    end if;
    -- The opening entries (134), the one standing and those it replaced.
    v_open := coalesce((select array_append(b.replaced_entry_ids, b.entry_id)
                          from books_opening b where b.org_id = p_org_id), '{}');

    select count(distinct date_trunc('week', je.created_at)) into v_weeks
      from journal_entries je
     where je.org_id = p_org_id and je.reverses_entry_id is null
       and not coalesce(je.id = any (v_open), false)
       and je.created_at >= date_trunc('week', now()) - interval '7 weeks';

    select count(*), count(*) filter (where exists (
               select 1 from documents d where d.linked_journal_entry_id = je.id))
      into v_expenses, v_receipts
      from journal_entries je
     where je.org_id = p_org_id and je.reverses_entry_id is null
       and je.created_at >= now() - interval '90 days'
       and not exists (select 1 from journal_entries r where r.reverses_entry_id = je.id)
       and exists (select 1 from journal_lines jl join accounts a on a.id = jl.account_id
                    where jl.journal_entry_id = je.id and jl.debit > 0 and a.code like '5%');

    select count(*) filter (where je.reverses_entry_id is null),
           count(*) filter (where je.reverses_entry_id is not null)
      into v_entries, v_reversals
      from journal_entries je
     where je.org_id = p_org_id and je.created_at >= now() - interval '90 days'
       and not coalesce(je.id = any (v_open), false)
       and not coalesce(je.reverses_entry_id = any (v_open), false);

    v_age_days := extract(day from now() - o.created_at)::int;

    p_verified  := o.verified_at is not null;
    p_regular   := v_weeks >= 6;
    p_justified := v_expenses >= 3 and v_receipts * 100 >= v_expenses * 80;
    p_clean     := v_entries >= 5 and v_reversals * 100 < v_entries * 10;
    p_lasting   := v_age_days >= 182;
    v_met := p_verified::int + p_regular::int + p_justified::int + p_clean::int + p_lasting::int;

    return jsonb_build_object(
        'level', case when v_met = 5 then 'Exemplaire'
                      when v_met = 4 then 'Fiable'
                      when v_met >= 2 then 'Régulière'
                      else 'Nouvelle' end,
        'met', v_met,
        'verified_at', o.verified_at,
        'pillars', jsonb_build_array(
            jsonb_build_object('key', 'verified', 'met', p_verified),
            jsonb_build_object('key', 'regular', 'met', p_regular,
                               'value', v_weeks, 'target', 6),
            jsonb_build_object('key', 'justified', 'met', p_justified,
                               'value', v_receipts, 'of', v_expenses),
            jsonb_build_object('key', 'clean', 'met', p_clean,
                               'value', v_reversals, 'of', v_entries),
            jsonb_build_object('key', 'lasting', 'met', p_lasting,
                               'value', v_age_days, 'target', 182)));
end;
$$;

-- ------------------------------------------------------------
-- 8. Who may call what (063: born closed to PUBLIC and anon; each door
-- said again)
-- ------------------------------------------------------------
revoke all on books_opening, contribution_defaults, books_start_dismissals from public;

revoke execute on function trg_books_opening_guard()                         from public;
revoke execute on function trg_contribution_default_guard()                  from public;
revoke execute on function trg_settings_134()                                from public;
revoke execute on function set_opening_balance(uuid, numeric, text, uuid)    from public;
revoke execute on function set_contribution_default(uuid, numeric, text)     from public;
revoke execute on function dismiss_books_start(uuid)                         from public;
revoke execute on function books_start(uuid)                                 from public;
revoke execute on function booking_cancel_hours()                            from public;
revoke execute on function cancel_order(uuid)                                from public;
revoke execute on function booking_cancel_terms(uuid)                        from public;
revoke execute on function cauris_week_close(date)                           from public;
revoke execute on function kind_setup_steps(text)                            from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on books_opening, contribution_defaults, books_start_dismissals from anon;
        revoke execute on function trg_books_opening_guard()                      from anon;
        revoke execute on function trg_contribution_default_guard()               from anon;
        revoke execute on function trg_settings_134()                             from anon;
        revoke execute on function set_opening_balance(uuid, numeric, text, uuid) from anon;
        revoke execute on function set_contribution_default(uuid, numeric, text)  from anon;
        revoke execute on function dismiss_books_start(uuid)                      from anon;
        revoke execute on function books_start(uuid)                              from anon;
        revoke execute on function booking_cancel_hours()                         from anon;
        revoke execute on function cancel_order(uuid)                             from anon;
        revoke execute on function booking_cancel_terms(uuid)                     from anon;
        revoke execute on function cauris_week_close(date)                        from anon;
        revoke execute on function kind_setup_steps(text)                         from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- The INVOKER doors write as the caller: the tables' rights, RLS
        -- deciding the rows — and nothing more than they use (Supabase's
        -- default privileges hand authenticated DELETE, REFERENCES, TRIGGER
        -- and MAINTAIN on every new table; taken back first, as 128 and 133).
        revoke all on books_opening, contribution_defaults, books_start_dismissals from authenticated;
        grant select, insert, update on books_opening          to authenticated;
        grant select, insert, update, delete on contribution_defaults to authenticated;
        grant select, insert on books_start_dismissals         to authenticated;
        -- Internal: the triggers, the hours (cancel_order and the terms
        -- read them as their owner), the week's close (the schedule's).
        revoke execute on function trg_books_opening_guard()                      from authenticated;
        revoke execute on function trg_contribution_default_guard()               from authenticated;
        revoke execute on function trg_settings_134()                             from authenticated;
        revoke execute on function booking_cancel_hours()                         from authenticated;
        revoke execute on function cauris_week_close(date)                        from authenticated;
        revoke execute on function kind_setup_steps(text)                         from authenticated;
        grant execute on function set_opening_balance(uuid, numeric, text, uuid)  to authenticated;
        grant execute on function set_contribution_default(uuid, numeric, text)   to authenticated;
        grant execute on function dismiss_books_start(uuid)                       to authenticated;
        grant execute on function books_start(uuid)                               to authenticated;
        grant execute on function cancel_order(uuid)                              to authenticated;
        grant execute on function booking_cancel_terms(uuid)                      to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
