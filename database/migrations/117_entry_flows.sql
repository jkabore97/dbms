-- ============================================================
-- 117_entry_flows.sql — the carnet's due date and the repayment by
-- customer, for the one-entry-at-a-time flows (batch 115, W2).
--
-- « Facture », « Recette » and « Dépense » write through the existing
-- functions (create_invoice / revise_invoice, record_entry) and need
-- nothing here. The carnet needed two things the 024 model did not have:
--
--   1. A due date. `debts.due_on` (nullable: every debt of before has
--      none, and none means « no date », never « overdue »). Set after
--      the debt exists by set_debt_due(), so neither record_credit_sale
--      (024) nor record_sale (029) is touched: a sum on credit is dated
--      by its debt id at once; a credit sale is dated by the sale's own
--      client_uuid, through the outbox when the sale itself was kept on
--      the phone (the queued sale goes first, the date after it).
--   2. A repayment by customer: « the customer → the amount →
--      Enregistrer ». repay_customer() spreads the amount over that
--      customer's open debts, oldest first, through 024's own
--      record_debt_payment (one transaction, idempotent by client_uuid,
--      never past what is owed).
--
-- The carnet reads the dates through debt_dates() (each open debt that
-- has one); 104's customer_debts and debts_of_customer are unchanged.
--
-- P1: nothing a business shows changes until somebody gives a date —
-- every existing debt reads `due_on` null and the lists are the same
-- rows in the same order. Same for a shop, a farm and an association
-- (the carnet is the same tool for all three; an association's debts are
-- sums, never sales).
-- ============================================================

alter table debts add column if not exists due_on date;

comment on column debts.due_on is
    'When the customer said they would pay (117). Null: no date given — never counted as overdue.';

-- ------------------------------------------------------------
-- 1. Dating a debt
-- ------------------------------------------------------------
-- By the debt's id (a sum on credit, online: record_credit_sale returned
-- it) or by the credit sale's client_uuid (the app always has it, even
-- for a sale still on the phone). p_recorded_by is what the outbox sends
-- with every action; p_due_on null clears the date.
--
-- A sale that is not there (the outbox sends the sale first: if it is
-- missing now, the server refused it — 101's stock rule — or it never
-- left) dates nothing and answers null rather than failing for ever in
-- the phone's outbox. A debt id that is not there is an error: that call
-- is made online, right after the debt was written.
create or replace function set_debt_due(
    p_org_id           uuid,
    p_due_on           date,
    p_debt_id          uuid default null,
    p_sale_client_uuid uuid default null,
    p_recorded_by      uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
    v_debt  uuid;
begin
    if v_actor is null then
        raise exception 'set_debt_due() needs a signed-in caller';
    end if;
    if p_recorded_by is not null and p_recorded_by <> v_actor then
        raise exception 'set_debt_due() cannot record on behalf of another user';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record entries for this business';
    end if;
    perform feature_guard(p_org_id, 'credits');
    if (p_debt_id is null) = (p_sale_client_uuid is null) then
        raise exception 'set_debt_due() needs the debt or the sale, one of the two';
    end if;

    if p_debt_id is not null then
        select id into v_debt from debts
         where id = p_debt_id and org_id = p_org_id
           for update;
        if v_debt is null then
            raise exception 'Ce crédit est introuvable.';
        end if;
    else
        select d.id into v_debt
          from debts d
          join sales s on s.id = d.sale_id
         where s.org_id = p_org_id and s.client_uuid = p_sale_client_uuid
           and d.org_id = p_org_id
           for update of d;
        if v_debt is null then
            return null;
        end if;
    end if;

    update debts set due_on = p_due_on where id = v_debt;
    return v_debt;
end;
$$;

-- ------------------------------------------------------------
-- 2. A repayment by customer
-- ------------------------------------------------------------
-- SECURITY INVOKER: every write is record_debt_payment's own (024,
-- DEFINER, its checks), so this function adds no power — it only picks
-- the debts, oldest first, and the slice of each. The first slice
-- carries p_client_uuid itself and is the whole call's idempotency: sent
-- twice, the second finds it and changes nothing. The others carry a
-- uuid derived from it and the debt, so a slice is never paid twice
-- either. Answers what the customer still owes afterwards.
create or replace function repay_customer(
    p_org_id      uuid,
    p_customer_id uuid,
    p_amount      numeric,
    p_method      text default 'cash',
    p_recorded_by uuid default null,
    p_client_uuid uuid default null
)
returns numeric
language plpgsql
security invoker
set search_path = public
as $$
declare
    v_uuid  uuid := coalesce(p_client_uuid, gen_random_uuid());
    v_owed  numeric;
    v_left  numeric := p_amount;
    v_slice numeric;
    v_first boolean := true;
    r       record;
begin
    if auth.uid() is null then
        raise exception 'repay_customer() needs a signed-in caller';
    end if;
    if p_recorded_by is not null and p_recorded_by <> auth.uid() then
        raise exception 'repay_customer() cannot record on behalf of another user';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record entries for this business';
    end if;
    perform feature_guard(p_org_id, 'credits');

    select coalesce(sum(d.amount - coalesce(p.paid, 0)), 0) into v_owed
      from debts d
      left join lateral (
          select sum(amount) as paid from debt_payments where debt_id = d.id
      ) p on true
     where d.org_id = p_org_id and d.customer_id = p_customer_id;

    -- Already recorded (the same uuid came back): nothing moves.
    if exists (select 1 from debt_payments where client_uuid = v_uuid) then
        return v_owed;
    end if;

    if p_amount is null or p_amount <= 0 then
        raise exception 'Amount must be greater than zero (got %)', p_amount;
    end if;
    if v_owed <= 0 then
        raise exception 'Ce client ne doit rien.';
    end if;
    if p_amount > v_owed then
        raise exception 'Ce paiement (%) dépasse ce qui reste dû (%)',
            trim_scale(p_amount), trim_scale(v_owed);
    end if;

    for r in
        select d.id, d.amount - coalesce(p.paid, 0) as remaining
          from debts d
          left join lateral (
              select sum(amount) as paid from debt_payments where debt_id = d.id
          ) p on true
         where d.org_id = p_org_id and d.customer_id = p_customer_id
           and d.amount > coalesce(p.paid, 0)
         order by d.occurred_at, d.id
    loop
        exit when v_left <= 0;
        v_slice := least(v_left, r.remaining);
        perform record_debt_payment(
            p_debt_id     => r.id,
            p_amount      => v_slice,
            p_method      => coalesce(p_method, 'cash'),
            p_recorded_by => p_recorded_by,
            p_client_uuid => case when v_first then v_uuid
                                  else md5(v_uuid::text || r.id::text)::uuid end
        );
        v_first := false;
        v_left := v_left - v_slice;
    end loop;

    return v_owed - p_amount;
end;
$$;

-- ------------------------------------------------------------
-- 3. The carnet's dates
-- ------------------------------------------------------------
-- 104's customer_debts and debts_of_customer stay exactly as they are
-- (every earlier suite and the bundle re-run 104, and a new column would
-- change their return type). The dates are their own read: each open
-- debt that has one, with its customer — the list shows the customer's
-- earliest, the customer's page each debt's. Guarded like 104's reads,
-- SECURITY INVOKER (RLS on debts decides).
create or replace function debt_dates(p_org_id uuid)
returns table (
    debt_id     uuid,
    customer_id uuid,
    due_on      date
)
language sql
stable
security invoker
set search_path = public
as $$
    select feature_guard(p_org_id, 'credits');
    select d.id, d.customer_id, d.due_on
      from debts d
      left join lateral (
          select sum(amount) as paid from debt_payments where debt_id = d.id
      ) p on true
     where d.org_id = p_org_id
       and d.due_on is not null
       and d.amount > coalesce(p.paid, 0)
     order by d.due_on, d.occurred_at;
$$;

-- ------------------------------------------------------------
-- 4. The doors: signed-in people only (063 makes them born closed).
-- ------------------------------------------------------------
revoke execute on function set_debt_due(uuid, date, uuid, uuid, uuid)            from public;
revoke execute on function repay_customer(uuid, uuid, numeric, text, uuid, uuid) from public;
revoke execute on function debt_dates(uuid)                                      from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function set_debt_due(uuid, date, uuid, uuid, uuid)            from anon;
        revoke execute on function repay_customer(uuid, uuid, numeric, text, uuid, uuid) from anon;
        revoke execute on function debt_dates(uuid)                                      from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_debt_due(uuid, date, uuid, uuid, uuid)            to authenticated;
        grant execute on function repay_customer(uuid, uuid, numeric, text, uuid, uuid) to authenticated;
        grant execute on function debt_dates(uuid)                                      to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
