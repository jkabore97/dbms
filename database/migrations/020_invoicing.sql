-- ============================================================
-- 020 — INVOICING FOR EVERY BUSINESS
-- ============================================================
-- The invoice tables have existed since 009. They were built inside the farm
-- migration for Ignace selling trays to a hotel, and everything about the way
-- they were reached said "farm": the only screen that opened them was the
-- farm's, and `create_invoice()` defaulted its income category to
-- "Ventes d'œufs".
--
-- None of that was ever true of the tables themselves. `invoices` is org
-- scoped, `create_invoice()` checks `can_write_org()` and nothing else, and a
-- shop invoicing a wholesaler or a church invoicing a hall hire is the same
-- three rows. So this migration does not build invoicing — it stops invoicing
-- from being farm-shaped, and adds the three things a business needs before it
-- can send one of these to an actual customer.
--
-- 1. A BILLING HEADER. An invoice has to say who is billing, and `orgs` held
--    a name and nothing else. No address, no telephone, no tax number — which
--    in Burkina Faso means no IFU, and an invoice without an IFU is not a
--    document a business customer can put in their own books.
--
-- 2. A DOCUMENT TO SEND. `outstanding_invoices()` answers "who has not paid",
--    which is the collections question. Nothing answered "what does invoice
--    2026-0007 actually say", which is the question you need to answer to put
--    it in somebody's hand.
--
-- 3. NUMBERING THAT SURVIVES TWO PEOPLE. See section 3 — the old scheme was
--    `count(*) + 1`, and it has a race in it that produces a hard failure the
--    first time a business is busy enough to have two people invoicing at
--    once. That is a production bug, not a tidiness one, and it is fixed here.
--
-- Also added: cancelling. `invoices.cancelled_at` has existed since 009 and
-- nothing has ever set it, so an invoice raised for the wrong customer or the
-- wrong amount could be neither corrected nor withdrawn — the receivable
-- simply stayed on the books for ever.

-- ------------------------------------------------------------
-- 1. WHO IS BILLING
-- ------------------------------------------------------------
-- On `orgs` rather than a separate table: there is exactly one of these per
-- business, it is read on every invoice, and a second table would be a join
-- that is never optional.
--
-- Every column is nullable. A business that has not filled these in still
-- invoices — the header simply carries less — because refusing to invoice
-- until a form is complete is how an app stops somebody trading.
alter table orgs add column if not exists address     text;
alter table orgs add column if not exists phone       text;
alter table orgs add column if not exists email       text;

-- IFU in Burkina Faso, NIF elsewhere in the region, VAT number in Europe.
-- Deliberately one free-text field rather than a column per jurisdiction:
-- what goes on the invoice is a label and a number, and which label is
-- correct is the accountant's business, not the schema's.
alter table orgs add column if not exists tax_id      text;
alter table orgs add column if not exists tax_label   text;

-- What the business wants written at the bottom of every invoice: payment
-- terms, a mobile-money number, "merci de votre confiance".
alter table orgs add column if not exists invoice_footer text;

-- An invoice is addressed to somebody. 009 stored a customer's name and phone,
-- which is enough to chase a debt and not enough to head a document.
--
-- Added here rather than further down because a `language sql` function body
-- is parsed when it is created: invoice_header() selects c.address, so the
-- column has to exist before that definition is reached.
alter table customers add column if not exists address text;

create or replace function set_org_billing(
    p_org_id         uuid,
    p_address        text default null,
    p_phone          text default null,
    p_email          text default null,
    p_tax_id         text default null,
    p_tax_label      text default null,
    p_invoice_footer text default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
begin
    if v_actor is null then
        raise exception 'set_org_billing() needs a signed-in caller';
    end if;
    -- An admin, not merely a writer. What is on the header is what the
    -- business is claiming about itself to a customer and to a tax office;
    -- that is not a thing for whoever happens to be raising the invoice.
    if not is_org_admin(p_org_id) then
        raise exception 'Only an administrator can change the billing details';
    end if;

    update orgs
       set address        = nullif(btrim(coalesce(p_address, address, '')), ''),
           phone          = nullif(btrim(coalesce(p_phone, phone, '')), ''),
           email          = nullif(btrim(coalesce(p_email, email, '')), ''),
           tax_id         = nullif(btrim(coalesce(p_tax_id, tax_id, '')), ''),
           tax_label      = nullif(btrim(coalesce(p_tax_label, tax_label, '')), ''),
           invoice_footer = nullif(btrim(coalesce(p_invoice_footer, invoice_footer, '')), '')
     where id = p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- 2. WHAT AN INVOICE EARNS, PER PROFILE
-- ------------------------------------------------------------
-- `create_invoice()` posts the credit side to an income account chosen by
-- name, and its default was 'Ventes d''œufs'. For a shop that is wrong, for a
-- church it is absurd, and the caller should not have to know the right
-- answer for a business it is merely displaying.
--
-- Resolved from the profile instead, and only when the caller said nothing.
create or replace function default_invoice_category(p_org_id uuid)
returns text
language sql
stable
as $$
    select case (select profile from orgs where id = p_org_id)
        when 'farm'   then 'Ventes de la ferme'
        when 'retail' then 'Ventes'
        when 'church' then 'Produits divers'
        else 'Ventes'
    end;
$$;

-- ------------------------------------------------------------
-- 3. NUMBERING THAT SURVIVES TWO PEOPLE INVOICING AT ONCE
-- ------------------------------------------------------------
-- What 009 did:
--
--     select to_char(...) || lpad((count(*) + 1)::text, 4, '0')
--       from invoices where org_id = ... and year = ...
--
-- Read the count, add one, insert. Two sessions that read before either
-- inserts both compute the same number, and `unique (org_id, number)` turns
-- the loser into a raised exception — so the second person to press the
-- button on a busy morning is simply told the invoice failed.
--
-- A sequence cannot fix it: sequences are global to the database, and two
-- businesses sharing this one would interleave their invoice numbers, which
-- is exactly what an auditor asks about. So the counter is a row per org per
-- year, and the bump is a single atomic upsert whose RETURNING is the number.
-- Concurrent callers serialise on that row and get consecutive values.
create table if not exists invoice_counters (
    org_id uuid not null references orgs(id) on delete cascade,
    year   int  not null,
    -- The last number issued. Next is this plus one, taken and stored in the
    -- same statement.
    issued int  not null default 0,
    primary key (org_id, year)
);

alter table invoice_counters enable row level security;

-- No policy grants direct access, and none should: the counter is only ever
-- touched by next_invoice_number(), which is SECURITY DEFINER. A client that
-- could write here could renumber a business's invoices.
drop policy if exists "invoice counters readable within org" on invoice_counters;
create policy "invoice counters readable within org"
    on invoice_counters for select
    using (is_org_member(org_id));

create or replace function next_invoice_number(p_org_id uuid, p_issued_on date)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_year int := extract(year from p_issued_on)::int;
    v_next int;
begin
    -- Not granted to `authenticated` — create_invoice() is the only caller and
    -- it is DEFINER, so it reaches this regardless. The check is here anyway,
    -- because the cost is one line and the failure it prevents is silent:
    -- anybody who could advance another business's counter would put gaps in
    -- that business's invoice sequence, and a gap in a numbered sequence is
    -- precisely what an auditor asks a business to explain. A future migration
    -- adding a blanket grant must not turn that on by accident.
    if not can_write_org(p_org_id) then
        raise exception 'You cannot issue invoice numbers for this business';
    end if;

    -- The whole point: read, increment and write are one statement, so two
    -- callers cannot both see the same "before" value.
    insert into invoice_counters (org_id, year, issued)
    values (p_org_id, v_year, 1)
    on conflict (org_id, year)
    do update set issued = invoice_counters.issued + 1
    returning issued into v_next;

    return v_year::text || '-' || lpad(v_next::text, 4, '0');
end;
$$;

-- Businesses that already have invoices start their counter above the highest
-- number they have used, so this migration cannot hand out a number that
-- collides with one already issued. Only numbers of the shape this function
-- produces are considered; a hand-typed number is not part of the sequence.
insert into invoice_counters (org_id, year, issued)
select i.org_id,
       extract(year from i.issued_on)::int,
       max((split_part(i.number, '-', 2))::int)
  from invoices i
 where i.number ~ '^\d{4}-\d+$'
   and split_part(i.number, '-', 1) = extract(year from i.issued_on)::text
 group by 1, 2
on conflict (org_id, year) do update
    set issued = greatest(invoice_counters.issued, excluded.issued);

-- ------------------------------------------------------------
-- 4. CREATING ONE
-- ------------------------------------------------------------
-- Same function as 009 with three changes: the category default is resolved
-- from the profile instead of being a farm string, the number comes from the
-- atomic counter instead of a count, and a due date can be expressed as a
-- number of days because that is how anybody actually says it.
--
-- The signature keeps every parameter 009 had, in the same order, so calls
-- already in the wild keep working.
-- The 009 signature took eleven arguments; this one takes thirteen, and
-- `create or replace` on a different argument list makes a second overload
-- rather than replacing the first. Two candidates is worse than either:
-- PostgREST cannot choose, and callers get "function is not unique". So the
-- old one is dropped by its exact signature first.
drop function if exists create_invoice(
    uuid, text, jsonb, uuid, text, text, date, text, text, uuid, date);

create or replace function create_invoice(
    p_org_id        uuid,
    p_customer_name text,
    p_lines         jsonb,
    p_recorded_by   uuid        default null,
    p_category      text        default null,
    p_customer_phone text       default null,
    p_due_on        date        default null,
    p_number        text        default null,
    p_memo          text        default null,
    p_client_uuid   uuid        default null,
    p_issued_on     date        default current_date,
    p_due_days      int         default null,
    p_customer_address text     default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor      uuid := auth.uid();
    v_customer   uuid;
    v_invoice    uuid;
    v_entry      uuid;
    v_total      numeric := 0;
    v_number     text;
    v_line       jsonb;
    v_qty        numeric;
    v_price      numeric;
    v_amount     numeric;
    v_desc       text;
    v_recv_acct  uuid;
    v_inc_acct   uuid;
    v_existing   uuid;
    v_due        date;
begin
    if v_actor is null then
        raise exception 'create_invoice() needs a signed-in caller';
    end if;
    if p_recorded_by is not null and p_recorded_by <> v_actor then
        raise exception 'create_invoice() cannot record on behalf of another user';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot invoice for this business';
    end if;
    if nullif(btrim(coalesce(p_customer_name, '')), '') is null then
        raise exception 'An invoice needs a customer';
    end if;
    if p_lines is null or jsonb_array_length(p_lines) = 0 then
        raise exception 'An invoice needs at least one line';
    end if;

    -- Idempotent by client_uuid, like every other write in this schema: a
    -- phone that retries must not raise the same invoice twice.
    if p_client_uuid is not null then
        select id into v_existing
          from invoices where org_id = p_org_id and client_uuid = p_client_uuid;
        if found then
            return v_existing;
        end if;
    end if;

    for v_line in select * from jsonb_array_elements(p_lines) loop
        v_qty   := coalesce((v_line ->> 'quantity')::numeric, 1);
        v_price := coalesce((v_line ->> 'unit_price')::numeric, 0);
        v_desc  := nullif(btrim(coalesce(v_line ->> 'description', '')), '');
        if v_desc is null then
            raise exception 'Every invoice line needs a description';
        end if;
        if v_qty <= 0 or v_price <= 0 then
            raise exception 'Every invoice line needs a quantity and a price';
        end if;
        v_total := v_total + (v_qty * v_price);
    end loop;

    if v_total <= 0 then
        raise exception 'An invoice cannot be for nothing';
    end if;

    -- "Payable in 30 days" is how the terms are agreed; a date is what the
    -- table stores. Explicit p_due_on wins if both are given.
    v_due := p_due_on;
    if v_due is null and p_due_days is not null and p_due_days > 0 then
        v_due := p_issued_on + p_due_days;
    end if;

    v_number := nullif(btrim(coalesce(p_number, '')), '');
    if v_number is null then
        v_number := next_invoice_number(p_org_id, p_issued_on);
    end if;

    v_customer := ensure_customer(p_org_id, p_customer_name, p_customer_phone, v_actor);
    if nullif(btrim(coalesce(p_customer_address, '')), '') is not null then
        update customers
           set address = btrim(p_customer_address)
         where id = v_customer
           and coalesce(btrim(address), '') = '';
    end if;

    v_recv_acct := ensure_account_by_code(
        p_org_id, '1300', 'Créances clients', 'asset', v_actor
    );
    v_inc_acct := ensure_account(
        p_org_id,
        coalesce(nullif(btrim(coalesce(p_category, '')), ''),
                 default_invoice_category(p_org_id)),
        'income',
        v_actor
    );

    -- The customer owes us (asset up), and we have earned it (income up).
    -- No cash account is touched, which is the whole point of an invoice.
    v_entry := post_ledger_pair(
        p_org_id      => p_org_id,
        p_debit_acct  => v_recv_acct,
        p_credit_acct => v_inc_acct,
        p_amount      => v_total,
        p_label       => 'Facture ' || v_number || ' — ' || btrim(p_customer_name),
        p_actor       => v_actor,
        p_memo        => p_memo,
        p_details     => jsonb_build_object('facture', v_number,
                                            'client', btrim(p_customer_name)),
        p_occurred_at => p_issued_on::timestamptz
    );

    insert into invoices (
        org_id, customer_id, number, issued_on, due_on, total,
        journal_entry_id, created_by, client_uuid
    )
    values (
        p_org_id, v_customer, v_number, p_issued_on, v_due, v_total,
        v_entry, v_actor, p_client_uuid
    )
    returning id into v_invoice;

    for v_line in select * from jsonb_array_elements(p_lines) loop
        v_qty    := coalesce((v_line ->> 'quantity')::numeric, 1);
        v_price  := coalesce((v_line ->> 'unit_price')::numeric, 0);
        v_amount := v_qty * v_price;
        insert into invoice_lines (invoice_id, description, quantity, unit_price, amount)
        values (v_invoice, btrim(v_line ->> 'description'), v_qty, v_price, v_amount);
    end loop;

    return v_invoice;
end;
$$;

-- ------------------------------------------------------------
-- 5. WITHDRAWING ONE
-- ------------------------------------------------------------
-- `cancelled_at` has been on the table since 009 with nothing to set it, so an
-- invoice raised for the wrong customer or the wrong amount stayed on the
-- books as a receivable that would never be collected and could never be
-- removed.
--
-- Cancelling reverses the journal entry rather than deleting it. Same rule as
-- everywhere else here: what happened, happened, and the correction is its own
-- fact. A paid invoice cannot be cancelled — the money arrived, and pretending
-- otherwise would leave the payment posted against nothing.
create or replace function cancel_invoice(
    p_invoice_id uuid,
    p_reason     text default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor  uuid := auth.uid();
    v_org    uuid;
    v_entry  uuid;
    v_paid   numeric;
    v_cancelled timestamptz;
begin
    if v_actor is null then
        raise exception 'cancel_invoice() needs a signed-in caller';
    end if;

    select org_id, journal_entry_id, cancelled_at
      into v_org, v_entry, v_cancelled
      from invoices where id = p_invoice_id;

    if v_org is null then
        raise exception 'No such invoice';
    end if;
    if not can_write_org(v_org) then
        raise exception 'You cannot change invoices for this business';
    end if;
    if v_cancelled is not null then
        -- Not an error worth failing over: two taps on a slow connection
        -- should not produce a scary message.
        return;
    end if;

    select coalesce(sum(amount), 0) into v_paid
      from invoice_payments where invoice_id = p_invoice_id;

    if v_paid > 0 then
        raise exception
            'This invoice has already been paid in part. Record a refund or a credit note instead.';
    end if;

    if v_entry is not null then
        perform reverse_entry(v_entry, v_actor,
                              coalesce(nullif(btrim(coalesce(p_reason, '')), ''),
                                       'Facture annulée'));
    end if;

    update invoices set cancelled_at = now() where id = p_invoice_id;
end;
$$;

-- ------------------------------------------------------------
-- 6. READING ONE BACK
-- ------------------------------------------------------------
-- `outstanding_invoices()` answers "who has not paid". These two answer "what
-- does this invoice say" and "what have we issued", which is what you need to
-- put a document in somebody's hand and to find one again afterwards.
--
-- SECURITY INVOKER, deliberately, unlike the writes above. These read
-- org-scoped tables that carry RLS, so the caller's own policies decide what
-- comes back — exactly the reasoning in the project notes for
-- record_contribution. A DEFINER read here would hand every org's invoices to
-- anyone holding the publishable key.
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
    -- The join to invoices is what makes RLS apply: invoice_lines is keyed by
    -- invoice_id and its own policy is written against the parent, so reading
    -- through the parent is how the tenant check happens.
    select l.description, l.quantity, l.unit_price, l.amount
      from invoice_lines l
      join invoices i on i.id = l.invoice_id
     where l.invoice_id = p_invoice_id
     order by l.id;
$$;

-- Everything issued, not only what is unpaid — you cannot re-send a receipt
-- for an invoice the collections list has already dropped.
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

-- ------------------------------------------------------------
-- 7. GRANTS
-- ------------------------------------------------------------
-- Wrapped in a role check because a bare Postgres — which is what CI runs —
-- has no `authenticated` role, and roles are cluster-wide, so a development
-- machine that has ever run the Supabase stub would hide the failure.
revoke execute on function set_org_billing(uuid, text, text, text, text, text, text) from public;
revoke execute on function next_invoice_number(uuid, date) from public;
revoke execute on function cancel_invoice(uuid, text) from public;
revoke execute on function create_invoice(uuid, text, jsonb, uuid, text, text, date, text, text, uuid, date, int, text) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_org_billing(uuid, text, text, text, text, text, text) to authenticated;
        grant execute on function cancel_invoice(uuid, text) to authenticated;
        grant execute on function create_invoice(uuid, text, jsonb, uuid, text, text, date, text, text, uuid, date, int, text) to authenticated;
        grant execute on function invoice_header(uuid) to authenticated;
        grant execute on function invoice_lines_of(uuid) to authenticated;
        grant execute on function list_invoices(uuid, boolean, int) to authenticated;
        grant execute on function default_invoice_category(uuid) to authenticated;
        -- Deliberately NOT next_invoice_number: it mutates the counter, and
        -- nothing outside create_invoice() has any business advancing it.
        grant select on invoice_counters to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
