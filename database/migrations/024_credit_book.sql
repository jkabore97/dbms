-- ============================================================
-- 024 — THE CREDIT BOOK (LE CARNET DE CRÉDIT)
-- ============================================================
-- The daily reality of a boutique here is the carnet: customers who take
-- goods and pay at month-end, the trader who takes eggs weekly and settles
-- monthly. Until now the app recorded sales as if everything were cash,
-- which means the most common transaction in the market could not be
-- written down — and books that cannot hold the normal case go quiet.
--
-- The shape: a **debt** is a sale whose payment is a promise. It posts to
-- the ledger immediately — debit "Créances clients" (an asset: money owed
-- to you is something you own), credit the income category — so the income
-- statement is honest about what was earned even before it is collected.
-- A **repayment** moves value from the receivable to a cash account. The
-- double entry underneath is exactly the machinery from 007; nothing new is
-- invented, which is the point.
--
-- Two deliberate limits:
--   * A repayment can never exceed what remains. An overpayment is not a
--     generosity to record silently — it is a typo, or a new deposit that
--     deserves its own entry.
--   * Debts are per named customer. "Somebody owes me 5000" is not a debt,
--     it is a loss waiting to be admitted.

-- ------------------------------------------------------------
-- 1. TABLES
-- ------------------------------------------------------------
create table if not exists debts (
    id               uuid primary key default gen_random_uuid(),
    org_id           uuid not null references orgs(id) on delete cascade,
    customer_id      uuid not null references customers(id) on delete restrict,
    journal_entry_id uuid not null references journal_entries(id),
    client_uuid      uuid unique,
    label            text not null,
    amount           numeric(14,2) not null check (amount > 0),
    occurred_at      timestamptz not null default now(),
    created_by       uuid not null references profiles(id),
    created_at       timestamptz not null default now()
);

create index if not exists debts_by_org      on debts (org_id, occurred_at);
create index if not exists debts_by_customer on debts (org_id, customer_id);

create table if not exists debt_payments (
    id               uuid primary key default gen_random_uuid(),
    debt_id          uuid not null references debts(id) on delete restrict,
    org_id           uuid not null references orgs(id) on delete cascade,
    journal_entry_id uuid not null references journal_entries(id),
    client_uuid      uuid unique,
    amount           numeric(14,2) not null check (amount > 0),
    method           text not null default 'cash',
    paid_at          timestamptz not null default now(),
    created_by       uuid not null references profiles(id)
);

create index if not exists debt_payments_by_debt on debt_payments (debt_id);

-- RLS: same posture as every other org table. Reads for members, writes only
-- through the functions below (which are DEFINER and check membership
-- themselves) — so no insert/update/delete policy at all, exactly like the
-- audit log. A direct write is refused by default-deny.
alter table debts enable row level security;
alter table debt_payments enable row level security;

drop policy if exists "debts readable within org" on debts;
create policy "debts readable within org"
on debts for select using (is_org_member(org_id));

drop policy if exists "debt payments readable within org" on debt_payments;
create policy "debt payments readable within org"
on debt_payments for select using (is_org_member(org_id));

-- ------------------------------------------------------------
-- 2. RECORDING A SALE ON CREDIT
-- ------------------------------------------------------------
-- The customer arrives as a name (and optionally a phone), not an id: the
-- person at the counter types "Awa" while the queue waits. Matching is by
-- lowered, trimmed name within the org — the same rule ensure_account()
-- uses, for the same reason: the second "awa " must not become a second
-- customer holding half the history.
--
-- SECURITY DEFINER for the same reasons record_entry() is: it may mint a
-- customer and an account, and it writes ledger rows. It makes the same
-- membership check the policies would have made.
create or replace function record_credit_sale(
    p_org_id         uuid,
    p_customer_name  text,
    p_amount         numeric,
    p_label          text,
    p_customer_phone text        default null,
    p_category       text        default null,   -- income account; defaults to the label
    p_recorded_by    uuid        default null,
    p_client_uuid    uuid        default null,
    p_device_id      text        default null,
    p_occurred_at    timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor       uuid := auth.uid();
    v_name        text := btrim(coalesce(p_customer_name, ''));
    v_label       text := btrim(coalesce(p_label, ''));
    v_customer    uuid;
    v_entry       uuid;
    v_receivable  uuid;
    v_income      uuid;
    v_debt        uuid;
begin
    if v_actor is null then
        raise exception 'record_credit_sale() needs a signed-in caller';
    end if;
    if p_recorded_by is not null and p_recorded_by <> v_actor then
        raise exception 'record_credit_sale() cannot record on behalf of another user';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record entries for this business';
    end if;
    if p_amount is null or p_amount <= 0 then
        raise exception 'Amount must be greater than zero (got %)', p_amount;
    end if;
    if v_name = '' then
        raise exception 'A credit sale needs the customer''s name';
    end if;
    if v_label = '' then
        raise exception 'A credit sale needs a label';
    end if;

    -- Same idempotency as record_entry(): the outbox may deliver twice, and
    -- the second delivery must find the first rather than double the debt.
    if p_client_uuid is not null then
        select id into v_debt from debts where client_uuid = p_client_uuid;
        if found then
            return v_debt;
        end if;
    end if;

    select id into v_customer
      from customers
     where org_id = p_org_id
       and lower(btrim(name)) = lower(v_name)
     order by created_at
     limit 1;
    if v_customer is null then
        insert into customers (org_id, name, phone, created_by)
        values (p_org_id, v_name, nullif(btrim(coalesce(p_customer_phone, '')), ''), v_actor)
        returning id into v_customer;
    end if;

    -- Money owed to the business is an asset. One account carries every
    -- customer; the per-customer breakdown lives in `debts`, which is what
    -- the screen reads. 1100 sits in the asset band beside the cash codes.
    v_receivable := ensure_account_by_code(
        p_org_id, '1100', 'Créances clients', 'asset', v_actor);
    v_income := ensure_account(
        p_org_id, coalesce(nullif(btrim(coalesce(p_category, '')), ''), v_label),
        'income', v_actor);

    insert into journal_entries
        (org_id, memo, created_by, device_id, client_uuid, created_at)
    values
        (p_org_id, v_label || ' — crédit ' || v_name, v_actor, p_device_id,
         p_client_uuid, p_occurred_at)
    returning id into v_entry;

    insert into journal_lines (journal_entry_id, account_id, debit, credit) values
        (v_entry, v_receivable, p_amount, 0),
        (v_entry, v_income, 0, p_amount);

    insert into debts (org_id, customer_id, journal_entry_id, client_uuid,
                       label, amount, occurred_at, created_by)
    values (p_org_id, v_customer, v_entry, p_client_uuid,
            v_label, p_amount, p_occurred_at, v_actor)
    returning id into v_debt;

    return v_debt;
end;
$$;

-- ------------------------------------------------------------
-- 3. A REPAYMENT
-- ------------------------------------------------------------
create or replace function record_debt_payment(
    p_debt_id     uuid,
    p_amount      numeric,
    p_method      text        default 'cash',
    p_recorded_by uuid        default null,
    p_client_uuid uuid        default null,
    p_device_id   text        default null,
    p_paid_at     timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor      uuid := auth.uid();
    v_debt       debts%rowtype;
    v_remaining  numeric;
    v_entry      uuid;
    v_cash       uuid;
    v_receivable uuid;
    v_payment    uuid;
    v_name       text;
begin
    if v_actor is null then
        raise exception 'record_debt_payment() needs a signed-in caller';
    end if;
    if p_recorded_by is not null and p_recorded_by <> v_actor then
        raise exception 'record_debt_payment() cannot record on behalf of another user';
    end if;
    if p_amount is null or p_amount <= 0 then
        raise exception 'Amount must be greater than zero (got %)', p_amount;
    end if;

    if p_client_uuid is not null then
        select id into v_payment from debt_payments where client_uuid = p_client_uuid;
        if found then
            return v_payment;
        end if;
    end if;

    select * into v_debt from debts where id = p_debt_id;
    if not found then
        raise exception 'No such debt';
    end if;
    if not can_write_org(v_debt.org_id) then
        raise exception 'You cannot record entries for this business';
    end if;

    -- The rule that keeps the screen truthful: what remains can reach zero
    -- and never cross it. Locked against a racing second device by taking
    -- the debt's row lock before summing.
    perform 1 from debts where id = p_debt_id for update;
    select v_debt.amount - coalesce(sum(amount), 0) into v_remaining
      from debt_payments where debt_id = p_debt_id;
    if p_amount > v_remaining then
        raise exception
            'Ce paiement (%) dépasse ce qui reste dû (%)', p_amount, v_remaining;
    end if;

    select name into v_name from customers where id = v_debt.customer_id;
    v_cash := resolve_cash_account(v_debt.org_id, p_method, v_actor);
    v_receivable := ensure_account_by_code(
        v_debt.org_id, '1100', 'Créances clients', 'asset', v_actor);

    insert into journal_entries
        (org_id, memo, created_by, device_id, client_uuid, created_at)
    values
        (v_debt.org_id, 'Remboursement — ' || coalesce(v_name, ''), v_actor,
         p_device_id, p_client_uuid, p_paid_at)
    returning id into v_entry;

    insert into journal_lines (journal_entry_id, account_id, debit, credit) values
        (v_entry, v_cash, p_amount, 0),
        (v_entry, v_receivable, 0, p_amount);

    insert into debt_payments (debt_id, org_id, journal_entry_id, client_uuid,
                               amount, method, paid_at, created_by)
    values (p_debt_id, v_debt.org_id, v_entry, p_client_uuid,
            p_amount, coalesce(p_method, 'cash'), p_paid_at, v_actor)
    returning id into v_payment;

    return v_payment;
end;
$$;

-- ------------------------------------------------------------
-- 4. WHO OWES WHAT
-- ------------------------------------------------------------
-- SECURITY INVOKER on purpose: these are reads, and RLS on debts/payments is
-- exactly the right gate — a member sees their business's carnet, nobody
-- else sees anything, and no check needs writing twice.
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
as $$
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
as $$
    select d.id, d.label, d.amount, coalesce(p.paid, 0),
           d.amount - coalesce(p.paid, 0), d.occurred_at
      from debts d
      left join lateral (
          select sum(amount) as paid from debt_payments where debt_id = d.id
      ) p on true
     where d.org_id = p_org_id and d.customer_id = p_customer_id
     order by d.occurred_at;
$$;

-- ------------------------------------------------------------
-- 5. GRANTS
-- ------------------------------------------------------------
revoke execute on function record_credit_sale(uuid, text, numeric, text, text, text, uuid, uuid, text, timestamptz) from public;
revoke execute on function record_debt_payment(uuid, numeric, text, uuid, uuid, text, timestamptz) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant select on debts, debt_payments to authenticated;
        grant execute on function record_credit_sale(uuid, text, numeric, text, text, text, uuid, uuid, text, timestamptz) to authenticated;
        grant execute on function record_debt_payment(uuid, numeric, text, uuid, uuid, text, timestamptz) to authenticated;
        grant execute on function customer_debts(uuid) to authenticated;
        grant execute on function debts_of_customer(uuid, uuid) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
