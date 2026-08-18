-- ============================================================
-- 039_currency_rates.sql — a customer pays in their currency; the books stay
-- in the shop's.
--
-- The user's ask: goods are sometimes bought in one currency and customers
-- sometimes hold another, and the person at the till must never do mental
-- arithmetic. The design that keeps everyone unlost: the business's own
-- currency remains the ONLY currency in the ledger, reports and analytics —
-- mixing currencies inside double-entry books produces totals that add francs
-- to dollars — and conversion happens at exactly two moments: when goods come
-- in, and when a customer pays.
--
-- RATES ARE THE OWNER'S, NOT AN API'S. The rate a shop in Ouaga actually gets
-- is the street or bank rate the owner knows, not the internet's mid-market
-- number — and a till in a market with two bars of signal cannot wait on a
-- rate service. So rates live in a per-business table the owner edits in
-- Paramètres, and the till only ever reads them. (EUR↔XOF is a fixed peg the
-- app pre-fills; nothing here hard-codes it, because the owner may still
-- prefer their bank's effective rate.)
--
-- WHAT A FOREIGN-CURRENCY SALE IS. An ordinary sale, booked in the home
-- currency from its lines exactly as before. The only new facts are what cash
-- physically crossed the counter — currency, amount, and the rate used — and
-- they are stamped onto the sale afterwards, the same seam Wave uses (037).
-- They are metadata for the receipt and any later dispute; the ledger amount
-- comes from the lines and can never be steered by them.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The owner's rate table. One row per foreign currency:
--    1 <currency> = <rate> in the business's home currency.
-- ------------------------------------------------------------
create table if not exists org_currency_rates (
    org_id     uuid not null references orgs(id) on delete cascade,
    -- ISO code, stored normalized so 'usd ' can never sit beside 'USD'.
    currency   text not null check (currency ~ '^[A-Z]{3}$'),
    rate       numeric(18,6) not null check (rate > 0),
    updated_by uuid references profiles(id),
    updated_at timestamptz not null default now(),
    primary key (org_id, currency)
);

alter table org_currency_rates enable row level security;

-- Everybody in the business reads the rates — the till needs them to offer the
-- chips. Only admins write them: a cashier must never set the rate they are
-- about to be measured against. Same shape as the feature rules in 031.
drop policy if exists "currency rates readable within org" on org_currency_rates;
create policy "currency rates readable within org"
on org_currency_rates for select using (is_org_member(org_id));

drop policy if exists "currency rates written by admins" on org_currency_rates;
create policy "currency rates written by admins"
on org_currency_rates for all using (is_org_admin(org_id))
with check (is_org_admin(org_id));

-- ------------------------------------------------------------
-- 2. What cash actually crossed the counter, when it was not the home
--    currency. Null on every other sale, so nothing existing changes.
-- ------------------------------------------------------------
alter table sales add column if not exists tendered_currency text
    check (tendered_currency is null or tendered_currency ~ '^[A-Z]{3}$');
alter table sales add column if not exists tendered_amount numeric(14,2)
    check (tendered_amount is null or tendered_amount > 0);
alter table sales add column if not exists tendered_rate numeric(18,6)
    check (tendered_rate is null or tendered_rate > 0);

-- ------------------------------------------------------------
-- 3. Stamp the tender onto a sale — called by the app right after record_sale
--    when the customer paid in a foreign currency. Idempotent; gated by
--    can_write_org on the sale's own org, so whoever may record the sale may
--    describe how it was paid, and nobody may touch another business's sale.
--    record_sale itself is deliberately not rewritten (same reasoning as 037):
--    these three columns are receipt facts, not ledger inputs.
-- ------------------------------------------------------------
create or replace function attach_sale_tender(
    p_sale_id  uuid,
    p_currency text,
    p_amount   numeric,
    p_rate     numeric
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org uuid;
    v_cur text := upper(btrim(coalesce(p_currency, '')));
begin
    if auth.uid() is null then
        raise exception 'attach_sale_tender() needs a signed-in caller';
    end if;

    select org_id into v_org from sales where id = p_sale_id;
    if v_org is null then
        raise exception 'No such sale';
    end if;
    if not can_write_org(v_org) then
        raise exception 'You cannot describe payment for this business';
    end if;
    if v_cur !~ '^[A-Z]{3}$' then
        raise exception 'Unknown currency: %', p_currency;
    end if;
    if coalesce(p_amount, 0) <= 0 or coalesce(p_rate, 0) <= 0 then
        raise exception 'A tender needs a positive amount and rate';
    end if;

    update sales set
        tendered_currency = v_cur,
        tendered_amount   = p_amount,
        tendered_rate     = p_rate
    where id = p_sale_id;
end;
$$;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant select, insert, update, delete on org_currency_rates to authenticated;
        grant execute on function attach_sale_tender(uuid, text, numeric, numeric) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
