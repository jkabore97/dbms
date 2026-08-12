-- ============================================================
-- 009_farm_profile.sql
-- Ignace's module: the farm profile.
--
-- BUILD_PLAN.md numbers this 005; that slot went to invitations while the
-- farm waited, so it lands here. Nothing else about the plan changes.
--
-- Same design rule as 002: Ignace never sees a debit or a credit. He taps
-- "20 sacs d'aliment reçus" and the function underneath writes a stock
-- movement and a balanced journal entry. Every public function here takes
-- plain-language inputs and hides the accounting completely.
--
-- Two things this module does that the church module did not have to.
--
--   1. IT COUNTS THINGS AS WELL AS MONEY. A sack of feed is an event in two
--      ledgers at once — the money one and the physical one — and they are
--      not the same ledger. Feed bought is an expense AND stock arriving;
--      feed eaten is stock leaving and no money at all; a bird dying is
--      neither, and is the single most important number on the farm. So
--      `stock_movements` and `flock_events` are append-only in exactly the
--      way `journal_entries` is, for exactly the same reason: a count you can
--      edit is a count nobody can audit.
--
--   2. IT SELLS ON CREDIT. A church is paid when it is paid. A farm delivers
--      thirty trays to a hotel and gets paid in three weeks, and the money
--      is real income the day it is invoiced. That needs a receivable, which
--      is the first thing in this project that is neither cash nor an
--      expense, and it is why `post_ledger_pair()` exists below.
--
-- ONE ACCOUNTING DECISION WORTH STATING. Feed is expensed when it is bought,
-- not when it is eaten. The strictly correct treatment capitalises it as
-- inventory and expenses it on consumption, which would make the income
-- statement smoother and the stock account meaningful. It is not done here
-- because BUILD_PLAN.md says "feed purchased is both a stock movement and an
-- expense", and because it matches how the money actually feels to the person
-- paying for it: the day twenty sacks arrive is the day the money is gone.
-- `stock_on_hand()` still counts the sacks. If this farm ever needs a real
-- inventory valuation, that is a later migration and a conversation with an
-- accountant, not a thing to guess at now.
-- ============================================================

-- ------------------------------------------------------------
-- 1. A SHARED WAY TO POST TWO SIDES
-- ------------------------------------------------------------
-- `record_entry()` in 007 covers everything whose other side is cash, which
-- is every entry the church module can produce. An invoice is the first thing
-- here whose other side is a customer who has not paid yet, and a payment is
-- the first thing whose other side is that same customer settling up.
--
-- So: the general form, taking two account ids. Not exposed to any caller —
-- it makes no permission check of its own, and every function that uses it
-- has already made one.
create or replace function post_ledger_pair(
    p_org_id       uuid,
    p_debit_acct   uuid,
    p_credit_acct  uuid,
    p_amount       numeric,
    p_label        text,
    p_actor        uuid,
    p_memo         text        default null,
    p_details      jsonb       default '{}'::jsonb,
    p_client_uuid  uuid        default null,
    p_device_id    text        default null,
    p_occurred_at  timestamptz default now()
)
returns uuid
language plpgsql
as $$
declare
    v_entry_id uuid;
begin
    if p_amount is null or p_amount <= 0 then
        raise exception 'Amount must be greater than zero (got %)', p_amount;
    end if;
    if p_debit_acct = p_credit_acct then
        raise exception 'An entry needs two different accounts';
    end if;

    insert into journal_entries (
        org_id, label, memo, details, created_by, created_at, device_id, client_uuid
    )
    values (
        p_org_id, p_label, p_memo, coalesce(p_details, '{}'::jsonb),
        p_actor, p_occurred_at, p_device_id, p_client_uuid
    )
    returning id into v_entry_id;

    insert into journal_lines (journal_entry_id, account_id, debit, credit) values
        (v_entry_id, p_debit_acct,  p_amount, 0),
        (v_entry_id, p_credit_acct, 0,        p_amount);

    return v_entry_id;
end;
$$;

-- The chart a farm starts with. Continues the bands 007 established, and
-- leaves the church's 4000s and 5000s alone so one org can run both.
create or replace function seed_farm_accounts(p_org_id uuid)
returns void
language plpgsql
as $$
begin
    insert into accounts (org_id, code, name, type) values
        (p_org_id, '1000', 'Cash on Hand',        'asset'),
        (p_org_id, '1010', 'Bank Account',        'asset'),
        (p_org_id, '1020', 'Mobile Money',        'asset'),
        -- What customers owe. The first asset in this project that is not
        -- money you can hold.
        (p_org_id, '1300', 'Créances clients',    'asset'),
        (p_org_id, '4100', 'Ventes d''œufs',      'income'),
        (p_org_id, '4110', 'Ventes de volailles', 'income'),
        (p_org_id, '4120', 'Autres ventes',       'income'),
        (p_org_id, '5100', 'Aliment',             'expense'),
        (p_org_id, '5110', 'Vétérinaire',         'expense'),
        (p_org_id, '5120', 'Main-d''œuvre',       'expense'),
        (p_org_id, '5130', 'Fournitures ferme',   'expense')
    on conflict (org_id, code) do nothing;
end;
$$;

-- ------------------------------------------------------------
-- 2. WHAT THE FARM CONSUMES
-- ------------------------------------------------------------
-- Things bought to be used up: feed, medicine, sawdust, gas. Not the same as
-- the `products` M5 will add for Esperance, which are things bought to be
-- sold and carry a barcode, an expiry and a selling price. Consumables have
-- none of that and need a reorder level, which products do not.
create table if not exists items (
    id            uuid primary key default gen_random_uuid(),
    org_id        uuid not null references orgs(id) on delete cascade,
    name          text not null,
    unit          text not null default 'sac',   -- sac | kg | litre | dose | unité
    -- Below this, the home screen says so. Null means nobody has decided yet,
    -- which is most items on the day they are created and is not a problem
    -- worth a required field.
    reorder_level numeric(14,2),
    is_active     boolean not null default true,
    created_at    timestamptz not null default now(),
    created_by    uuid references profiles(id)
);

create index if not exists items_by_org on items (org_id) where is_active;

-- Matched the way ensure_account() matches, and for the same reason: "Aliment
-- ponte", "aliment ponte" and " Aliment Ponte " are one thing to the person
-- typing them.
create index if not exists items_by_name on items (org_id, lower(btrim(name)));

-- Append-only, exactly like journal_lines. A stock count that can be edited
-- after the fact is a stock count that cannot be reconciled against anything.
-- A miscount is corrected the way a miscounted offering is: by a further
-- movement that says so, not by rewriting the first one.
create table if not exists stock_movements (
    id          uuid primary key default gen_random_uuid(),
    org_id      uuid not null references orgs(id) on delete cascade,
    item_id     uuid not null references items(id) on delete cascade,

    -- received: arrived and was paid for.   consumed: used as intended.
    -- wasted:   spoiled, spilled, stolen.   adjusted: a physical count
    --           disagreed with the running total and the count wins.
    kind        text not null check (kind in ('received', 'consumed', 'wasted', 'adjusted')),

    -- Signed for 'adjusted' and positive for everything else; the direction
    -- of the other three is carried by `kind`. stock_on_hand() below is the
    -- one place that turns them into a running total.
    quantity    numeric(14,3) not null,
    unit_cost   numeric(14,2),

    -- Set for 'received', which is the only kind that moves money.
    journal_entry_id uuid references journal_entries(id),

    memo        text,
    occurred_at timestamptz not null default now(),
    created_by  uuid not null references profiles(id),
    device_id   text,
    client_uuid uuid
);

create index if not exists stock_movements_by_item
    on stock_movements (org_id, item_id, occurred_at desc);

-- The offline safety net, identical to journal_entries: a phone that retries
-- a sync must not double-count twenty sacks of feed.
create unique index if not exists stock_movements_client_uuid_key
    on stock_movements (org_id, client_uuid)
    where client_uuid is not null;

-- ------------------------------------------------------------
-- 3. THE BIRDS
-- ------------------------------------------------------------
-- A flock is a batch that arrived together and is managed together. Its bird
-- count is the number that ARRIVED and is never edited; how many are alive is
-- that number minus the mortality events, which is what flock_status()
-- computes. Storing a mutable "current count" instead would lose the one
-- piece of information the farm actually runs on, which is how fast birds are
-- dying and when that changed.
create table if not exists flocks (
    id          uuid primary key default gen_random_uuid(),
    org_id      uuid not null references orgs(id) on delete cascade,
    entity_id   uuid references entities(id) on delete set null,  -- which site
    batch_code  text not null,
    breed       text,
    bird_count  int not null check (bird_count > 0),
    arrived_on  date not null default current_date,
    -- Set when the batch is sold off or cleared out. A closed flock stops
    -- appearing on the home screen and keeps all its history.
    closed_on   date,
    created_at  timestamptz not null default now(),
    created_by  uuid references profiles(id),
    unique (org_id, batch_code)
);

create index if not exists flocks_open on flocks (org_id) where closed_on is null;

create table if not exists flock_events (
    id          uuid primary key default gen_random_uuid(),
    flock_id    uuid not null references flocks(id) on delete cascade,

    -- mortality: birds died.  weight: a sample weighing, in grams.
    -- vaccination: a dose given.  sold: birds left the flock alive.
    kind        text not null check (kind in ('mortality', 'weight', 'vaccination', 'sold')),

    -- Birds for mortality and sold, grams for weight, doses for vaccination.
    -- One column because the unit is decided by `kind` and a column per kind
    -- would be three nulls on every row.
    quantity    numeric(14,3) not null,

    note        text,
    occurred_at timestamptz not null default now(),
    created_by  uuid not null references profiles(id),
    device_id   text,
    client_uuid uuid
);

create index if not exists flock_events_by_flock
    on flock_events (flock_id, occurred_at desc);

create unique index if not exists flock_events_client_uuid_key
    on flock_events (flock_id, client_uuid)
    where client_uuid is not null;

-- What the birds produced. Not money: eggs become income when they are sold,
-- and a great many of them are eaten, given away or broken first. Recording
-- production as revenue is how a farm convinces itself it is profitable.
create table if not exists egg_production (
    id          uuid primary key default gen_random_uuid(),
    org_id      uuid not null references orgs(id) on delete cascade,
    flock_id    uuid references flocks(id) on delete set null,
    produced_on date not null default current_date,
    grade       text not null default 'normal',   -- normal | petit | fêlé
    egg_count   int not null check (egg_count >= 0),
    created_at  timestamptz not null default now(),
    created_by  uuid not null references profiles(id),
    device_id   text,
    client_uuid uuid
);

create index if not exists egg_production_by_day
    on egg_production (org_id, produced_on desc);

create unique index if not exists egg_production_client_uuid_key
    on egg_production (org_id, client_uuid)
    where client_uuid is not null;

-- ------------------------------------------------------------
-- 4. WHO BUYS, AND WHO HAS NOT PAID
-- ------------------------------------------------------------
create table if not exists customers (
    id         uuid primary key default gen_random_uuid(),
    org_id     uuid not null references orgs(id) on delete cascade,
    name       text not null,
    phone      text,
    note       text,
    is_active  boolean not null default true,
    created_at timestamptz not null default now(),
    created_by uuid references profiles(id)
);

create index if not exists customers_by_org on customers (org_id) where is_active;
create index if not exists customers_by_name on customers (org_id, lower(btrim(name)));

create table if not exists invoices (
    id          uuid primary key default gen_random_uuid(),
    org_id      uuid not null references orgs(id) on delete cascade,
    customer_id uuid not null references customers(id) on delete restrict,
    number      text not null,
    issued_on   date not null default current_date,
    due_on      date,
    total       numeric(14,2) not null check (total > 0),

    -- The entry that recognised the income and created the receivable. An
    -- invoice without one would be a promise the books know nothing about.
    journal_entry_id uuid references journal_entries(id),

    -- Withdrawn rather than deleted, like everything else here: a cancelled
    -- invoice is a fact about the relationship with that customer.
    cancelled_at timestamptz,

    created_at  timestamptz not null default now(),
    created_by  uuid not null references profiles(id),
    client_uuid uuid,
    unique (org_id, number)
);

create index if not exists invoices_by_customer
    on invoices (org_id, customer_id, issued_on desc);

create table if not exists invoice_lines (
    id          uuid primary key default gen_random_uuid(),
    invoice_id  uuid not null references invoices(id) on delete cascade,
    description text not null,
    quantity    numeric(14,3) not null default 1,
    unit_price  numeric(14,2) not null,
    amount      numeric(14,2) not null
);

create index if not exists invoice_lines_by_invoice on invoice_lines (invoice_id);

-- Payments are rows, not a status column. A hotel that pays a third now and
-- the rest next month is the normal case, and "paid: true/false" cannot
-- describe it. What is outstanding is the invoice total minus the sum of
-- these, which is what outstanding_invoices() computes.
create table if not exists invoice_payments (
    id          uuid primary key default gen_random_uuid(),
    invoice_id  uuid not null references invoices(id) on delete cascade,
    amount      numeric(14,2) not null check (amount > 0),
    method      text not null default 'cash',
    paid_on     date not null default current_date,
    journal_entry_id uuid references journal_entries(id),
    created_at  timestamptz not null default now(),
    created_by  uuid not null references profiles(id),
    client_uuid uuid
);

create index if not exists invoice_payments_by_invoice
    on invoice_payments (invoice_id, paid_on);

-- ------------------------------------------------------------
-- 5. FINDING OR CREATING THE THINGS PEOPLE NAME
-- ------------------------------------------------------------
-- Same rule as ensure_account() in 007, applied to the two other things a
-- farmer types the name of. An item list nobody can add to has exactly the
-- problem the category list had.
create or replace function ensure_item(
    p_org_id uuid,
    p_name   text,
    p_unit   text default 'sac',
    p_actor  uuid default null
)
returns uuid
language plpgsql
as $$
declare
    v_name text := btrim(coalesce(p_name, ''));
    v_id   uuid;
begin
    if v_name = '' then
        raise exception 'An item needs a name';
    end if;

    select id into v_id
      from items
     where org_id = p_org_id and lower(btrim(name)) = lower(v_name)
     order by created_at
     limit 1;

    if v_id is not null then
        return v_id;
    end if;

    insert into items (org_id, name, unit, created_by)
    values (p_org_id, v_name, coalesce(nullif(btrim(p_unit), ''), 'sac'), p_actor)
    returning id into v_id;

    return v_id;
end;
$$;

create or replace function ensure_customer(
    p_org_id uuid,
    p_name   text,
    p_phone  text default null,
    p_actor  uuid default null
)
returns uuid
language plpgsql
as $$
declare
    v_name text := btrim(coalesce(p_name, ''));
    v_id   uuid;
begin
    if v_name = '' then
        raise exception 'A customer needs a name';
    end if;

    select id into v_id
      from customers
     where org_id = p_org_id and lower(btrim(name)) = lower(v_name)
     order by created_at
     limit 1;

    if v_id is not null then
        return v_id;
    end if;

    insert into customers (org_id, name, phone, created_by)
    values (p_org_id, v_name, nullif(btrim(coalesce(p_phone, '')), ''), p_actor)
    returning id into v_id;

    return v_id;
end;
$$;

-- ------------------------------------------------------------
-- 6. WHAT IGNACE TAPS
-- ------------------------------------------------------------
-- All SECURITY DEFINER, all checking `can_write_org()` themselves first, all
-- idempotent on a device-generated client_uuid — the same three properties
-- every recording function in this project has, for the same three reasons.

-- Feed, medicine, sawdust arriving. One tap; two ledgers.
create or replace function receive_stock(
    p_org_id      uuid,
    p_item_name   text,
    p_quantity    numeric,
    p_unit_cost   numeric     default null,
    p_unit        text        default 'sac',
    p_category    text        default 'Aliment',   -- the expense account
    p_method      text        default 'cash',
    p_recorded_by uuid        default null,
    p_memo        text        default null,
    p_client_uuid uuid        default null,
    p_device_id   text        default null,
    p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_item     uuid;
    v_entry    uuid;
    v_total    numeric;
    v_id       uuid;
    v_existing uuid;
begin
    if v_actor is null then
        raise exception 'receive_stock() needs a signed-in caller';
    end if;
    if p_recorded_by is not null and p_recorded_by <> v_actor then
        raise exception 'receive_stock() cannot record on behalf of another user';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record stock for this business';
    end if;
    if p_quantity is null or p_quantity <= 0 then
        raise exception 'Quantity must be greater than zero (got %)', p_quantity;
    end if;

    if p_client_uuid is not null then
        select id into v_existing
          from stock_movements
         where org_id = p_org_id and client_uuid = p_client_uuid;
        if found then
            return v_existing;
        end if;
    end if;

    v_item := ensure_item(p_org_id, p_item_name, p_unit, v_actor);
    v_total := p_quantity * coalesce(p_unit_cost, 0);

    -- Money only moves if somebody said what it cost. A delivery logged
    -- without a price is still a delivery, and refusing it would mean the
    -- sacks go uncounted because the invoice is in the truck.
    if v_total > 0 then
        v_entry := record_entry(
            p_org_id      => p_org_id,
            p_amount      => v_total,
            p_direction   => 'out',
            p_label       => btrim(p_item_name) || ' — ' || p_quantity || ' ' ||
                             coalesce(nullif(btrim(p_unit), ''), 'sac'),
            p_recorded_by => v_actor,
            p_category    => p_category,
            p_method      => p_method,
            p_memo        => p_memo,
            p_details     => jsonb_build_object(
                'quantité', p_quantity,
                'unité', coalesce(nullif(btrim(p_unit), ''), 'sac'),
                'prix unitaire', p_unit_cost
            ),
            p_client_uuid => p_client_uuid,
            p_device_id   => p_device_id,
            p_occurred_at => p_occurred_at
        );
    end if;

    insert into stock_movements (
        org_id, item_id, kind, quantity, unit_cost, journal_entry_id,
        memo, occurred_at, created_by, device_id, client_uuid
    )
    values (
        p_org_id, v_item, 'received', p_quantity, p_unit_cost, v_entry,
        p_memo, p_occurred_at, v_actor, p_device_id, p_client_uuid
    )
    returning id into v_id;

    return v_id;
end;
$$;

-- Feed eaten, medicine given, sawdust spread — and the same function for
-- what spoiled, because the only difference is which word is true.
--
-- No ledger entry: the money left when the sacks arrived. What this moves is
-- the count, and the count is what tells you the feed is running out on
-- Thursday rather than on the Thursday you run out.
create or replace function move_stock(
    p_org_id      uuid,
    p_item_name   text,
    p_quantity    numeric,
    p_kind        text        default 'consumed',  -- consumed | wasted | adjusted
    p_unit        text        default 'sac',
    p_recorded_by uuid        default null,
    p_memo        text        default null,
    p_client_uuid uuid        default null,
    p_device_id   text        default null,
    p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_item     uuid;
    v_id       uuid;
    v_existing uuid;
begin
    if v_actor is null then
        raise exception 'move_stock() needs a signed-in caller';
    end if;
    if p_recorded_by is not null and p_recorded_by <> v_actor then
        raise exception 'move_stock() cannot record on behalf of another user';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record stock for this business';
    end if;
    if p_kind not in ('consumed', 'wasted', 'adjusted') then
        raise exception 'Use receive_stock() for arrivals (got kind %)', p_kind;
    end if;
    -- An adjustment may be negative: it is the difference between what the
    -- running total said and what counting the sacks found, and that
    -- difference goes both ways.
    if p_quantity is null or (p_kind <> 'adjusted' and p_quantity <= 0) then
        raise exception 'Quantity must be greater than zero (got %)', p_quantity;
    end if;

    if p_client_uuid is not null then
        select id into v_existing
          from stock_movements
         where org_id = p_org_id and client_uuid = p_client_uuid;
        if found then
            return v_existing;
        end if;
    end if;

    v_item := ensure_item(p_org_id, p_item_name, p_unit, v_actor);

    insert into stock_movements (
        org_id, item_id, kind, quantity, memo, occurred_at,
        created_by, device_id, client_uuid
    )
    values (
        p_org_id, v_item, p_kind, p_quantity, p_memo, p_occurred_at,
        v_actor, p_device_id, p_client_uuid
    )
    returning id into v_id;

    return v_id;
end;
$$;

-- A batch of birds arriving.
create or replace function open_flock(
    p_org_id     uuid,
    p_batch_code text,
    p_bird_count int,
    p_breed      text default null,
    p_entity_id  uuid default null,
    p_arrived_on date default current_date
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
    v_id    uuid;
begin
    if v_actor is null then
        raise exception 'open_flock() needs a signed-in caller';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot manage flocks for this business';
    end if;
    if p_bird_count is null or p_bird_count <= 0 then
        raise exception 'A flock needs at least one bird (got %)', p_bird_count;
    end if;
    if btrim(coalesce(p_batch_code, '')) = '' then
        raise exception 'A flock needs a batch name';
    end if;

    insert into flocks (org_id, entity_id, batch_code, breed, bird_count, arrived_on, created_by)
    values (
        p_org_id, p_entity_id, btrim(p_batch_code),
        nullif(btrim(coalesce(p_breed, '')), ''), p_bird_count, p_arrived_on, v_actor
    )
    returning id into v_id;

    return v_id;
end;
$$;

-- Mortality, a weighing, a vaccination, birds sold off.
--
-- Mortality is the reason this function is used every day and the reason it
-- takes no money: a dead bird costs what it cost to raise, which is already
-- in the books as feed, and posting a second expense for it would count the
-- same loss twice.
create or replace function record_flock_event(
    p_flock_id    uuid,
    p_kind        text,
    p_quantity    numeric,
    p_recorded_by uuid        default null,
    p_note        text        default null,
    p_client_uuid uuid        default null,
    p_device_id   text        default null,
    p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_org      uuid;
    v_alive    numeric;
    v_id       uuid;
    v_existing uuid;
begin
    if v_actor is null then
        raise exception 'record_flock_event() needs a signed-in caller';
    end if;
    if p_recorded_by is not null and p_recorded_by <> v_actor then
        raise exception 'record_flock_event() cannot record on behalf of another user';
    end if;

    select org_id into v_org from flocks where id = p_flock_id;
    if v_org is null then
        raise exception 'No such flock';
    end if;
    if not can_write_org(v_org) then
        raise exception 'You cannot record events for this business';
    end if;
    if p_kind not in ('mortality', 'weight', 'vaccination', 'sold') then
        raise exception 'Unknown flock event: %', p_kind;
    end if;
    if p_quantity is null or p_quantity <= 0 then
        raise exception 'Quantity must be greater than zero (got %)', p_quantity;
    end if;

    if p_client_uuid is not null then
        select id into v_existing
          from flock_events
         where flock_id = p_flock_id and client_uuid = p_client_uuid;
        if found then
            return v_existing;
        end if;
    end if;

    -- More birds leaving than ever arrived means somebody has typed 300
    -- instead of 3, and a flock of -297 birds is a number every report
    -- downstream will carry for the rest of the batch's life.
    if p_kind in ('mortality', 'sold') then
        select f.bird_count - coalesce(sum(e.quantity) filter (
                   where e.kind in ('mortality', 'sold')
               ), 0)
          into v_alive
          from flocks f
          left join flock_events e on e.flock_id = f.id
         where f.id = p_flock_id
         group by f.bird_count;

        if p_quantity > v_alive then
            raise exception
                'Only % birds left in this flock, cannot record % as %',
                v_alive, p_quantity, p_kind;
        end if;
    end if;

    insert into flock_events (
        flock_id, kind, quantity, note, occurred_at, created_by, device_id, client_uuid
    )
    values (
        p_flock_id, p_kind, p_quantity, p_note, p_occurred_at,
        v_actor, p_device_id, p_client_uuid
    )
    returning id into v_id;

    return v_id;
end;
$$;

-- The morning collection. No money: eggs are income when they are sold, and
-- plenty are eaten, given away or broken first.
create or replace function record_eggs(
    p_org_id      uuid,
    p_egg_count   int,
    p_flock_id    uuid        default null,
    p_grade       text        default 'normal',
    p_recorded_by uuid        default null,
    p_produced_on date        default current_date,
    p_client_uuid uuid        default null,
    p_device_id   text        default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_id       uuid;
    v_existing uuid;
begin
    if v_actor is null then
        raise exception 'record_eggs() needs a signed-in caller';
    end if;
    if p_recorded_by is not null and p_recorded_by <> v_actor then
        raise exception 'record_eggs() cannot record on behalf of another user';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record production for this business';
    end if;
    if p_egg_count is null or p_egg_count < 0 then
        raise exception 'Egg count cannot be negative (got %)', p_egg_count;
    end if;

    if p_client_uuid is not null then
        select id into v_existing
          from egg_production
         where org_id = p_org_id and client_uuid = p_client_uuid;
        if found then
            return v_existing;
        end if;
    end if;

    insert into egg_production (
        org_id, flock_id, produced_on, grade, egg_count,
        created_by, device_id, client_uuid
    )
    values (
        p_org_id, p_flock_id, p_produced_on,
        coalesce(nullif(btrim(coalesce(p_grade, '')), ''), 'normal'),
        p_egg_count, v_actor, p_device_id, p_client_uuid
    )
    returning id into v_id;

    return v_id;
end;
$$;

-- ------------------------------------------------------------
-- 7. SELLING
-- ------------------------------------------------------------
-- Paid on the spot: this is just record_entry() with the farm's income
-- account, and exists so the app has one obvious call rather than making the
-- screen know which account name to send.
create or replace function record_farm_sale(
    p_org_id       uuid,
    p_amount       numeric,
    p_label        text,
    p_recorded_by  uuid        default null,
    p_category     text        default 'Ventes d''œufs',
    p_method       text        default 'cash',
    p_customer_name text       default null,
    p_memo         text        default null,
    p_client_uuid  uuid        default null,
    p_device_id    text        default null,
    p_occurred_at  timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
    v_name  text := nullif(btrim(coalesce(p_customer_name, '')), '');
begin
    if v_actor is null then
        raise exception 'record_farm_sale() needs a signed-in caller';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record sales for this business';
    end if;

    -- The buyer's name, when there is one, rides along as a characteristic
    -- rather than as a customer row. A cash sale at the gate does not need a
    -- customer record, and creating one for every passer-by would bury the
    -- three hotels that actually matter.
    return record_entry(
        p_org_id      => p_org_id,
        p_amount      => p_amount,
        p_direction   => 'in',
        p_label       => p_label,
        p_recorded_by => v_actor,
        p_category    => p_category,
        p_method      => p_method,
        p_memo        => p_memo,
        p_details     => case when v_name is null then '{}'::jsonb
                              else jsonb_build_object('client', v_name) end,
        p_client_uuid => p_client_uuid,
        p_device_id   => p_device_id,
        p_occurred_at => p_occurred_at
    );
end;
$$;

-- Delivered now, paid later. The income is real the day it is invoiced; what
-- is missing is the cash, and that gap is the receivable.
--
-- Lines arrive as jsonb — [{"description": "...", "quantity": 30,
-- "unit_price": 2500}] — because an invoice has an unknown number of them and
-- a function signature cannot hold a list.
create or replace function create_invoice(
    p_org_id        uuid,
    p_customer_name text,
    p_lines         jsonb,
    p_recorded_by   uuid        default null,
    p_category      text        default 'Ventes d''œufs',
    p_customer_phone text       default null,
    p_due_on        date        default null,
    p_number        text        default null,
    p_memo          text        default null,
    p_client_uuid   uuid        default null,
    p_issued_on     date        default current_date
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
    v_recv_acct  uuid;
    v_inc_acct   uuid;
    v_existing   uuid;
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
    if p_lines is null or jsonb_array_length(p_lines) = 0 then
        raise exception 'An invoice needs at least one line';
    end if;

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
        if v_qty <= 0 or v_price <= 0 then
            raise exception 'Every invoice line needs a quantity and a price';
        end if;
        v_total := v_total + (v_qty * v_price);
    end loop;

    if v_total <= 0 then
        raise exception 'An invoice cannot be for nothing';
    end if;

    -- Numbering is per org and gapless-ish: the count of invoices already
    -- issued, plus one. Not a sequence, because a sequence is global and two
    -- businesses sharing this database would interleave their invoice
    -- numbers, which is the sort of thing an auditor asks about.
    v_number := nullif(btrim(coalesce(p_number, '')), '');
    if v_number is null then
        select to_char(p_issued_on, 'YYYY') || '-' ||
               lpad((count(*) + 1)::text, 4, '0')
          into v_number
          from invoices
         where org_id = p_org_id
           and extract(year from issued_on) = extract(year from p_issued_on);
    end if;

    v_customer := ensure_customer(p_org_id, p_customer_name, p_customer_phone, v_actor);

    v_recv_acct := ensure_account_by_code(
        p_org_id, '1300', 'Créances clients', 'asset', v_actor
    );
    v_inc_acct := ensure_account(p_org_id, p_category, 'income', v_actor);

    -- The customer owes us (asset up), and we have earned it (income up).
    -- No cash account is touched, which is the whole point.
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
        p_org_id, v_customer, v_number, p_issued_on, p_due_on, v_total,
        v_entry, v_actor, p_client_uuid
    )
    returning id into v_invoice;

    for v_line in select * from jsonb_array_elements(p_lines) loop
        v_qty    := coalesce((v_line ->> 'quantity')::numeric, 1);
        v_price  := coalesce((v_line ->> 'unit_price')::numeric, 0);
        v_amount := v_qty * v_price;
        insert into invoice_lines (invoice_id, description, quantity, unit_price, amount)
        values (
            v_invoice,
            coalesce(nullif(btrim(coalesce(v_line ->> 'description', '')), ''), 'Article'),
            v_qty, v_price, v_amount
        );
    end loop;

    return v_invoice;
end;
$$;

-- The hotel settles up, in full or in part.
create or replace function record_invoice_payment(
    p_invoice_id  uuid,
    p_amount      numeric,
    p_method      text        default 'cash',
    p_recorded_by uuid        default null,
    p_paid_on     date        default current_date,
    p_client_uuid uuid        default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor      uuid := auth.uid();
    v_org        uuid;
    v_number     text;
    v_total      numeric;
    v_paid       numeric;
    v_cash_acct  uuid;
    v_recv_acct  uuid;
    v_entry      uuid;
    v_id         uuid;
    v_existing   uuid;
begin
    if v_actor is null then
        raise exception 'record_invoice_payment() needs a signed-in caller';
    end if;
    if p_recorded_by is not null and p_recorded_by <> v_actor then
        raise exception 'record_invoice_payment() cannot record on behalf of another user';
    end if;

    select org_id, number, total into v_org, v_number, v_total
      from invoices where id = p_invoice_id and cancelled_at is null;
    if v_org is null then
        raise exception 'No such invoice, or it has been cancelled';
    end if;
    if not can_write_org(v_org) then
        raise exception 'You cannot record payments for this business';
    end if;
    if p_amount is null or p_amount <= 0 then
        raise exception 'Amount must be greater than zero (got %)', p_amount;
    end if;

    if p_client_uuid is not null then
        select id into v_existing
          from invoice_payments
         where invoice_id = p_invoice_id and client_uuid = p_client_uuid;
        if found then
            return v_existing;
        end if;
    end if;

    select coalesce(sum(amount), 0) into v_paid
      from invoice_payments where invoice_id = p_invoice_id;

    -- Overpaying is a real thing that happens and it is not a payment against
    -- this invoice. Refusing it keeps the receivable account honest; the
    -- extra is a separate conversation and, for now, a separate entry.
    if v_paid + p_amount > v_total then
        raise exception
            'Invoice % is for % and % has already been paid; % is too much',
            v_number, v_total, v_paid, p_amount;
    end if;

    v_cash_acct := resolve_cash_account(v_org, p_method, v_actor);
    v_recv_acct := ensure_account_by_code(
        v_org, '1300', 'Créances clients', 'asset', v_actor
    );

    -- Cash arrives, and the customer stops owing it. No income: that was
    -- recognised the day the invoice was raised, and recognising it again
    -- here would double every credit sale in the books.
    v_entry := post_ledger_pair(
        p_org_id      => v_org,
        p_debit_acct  => v_cash_acct,
        p_credit_acct => v_recv_acct,
        p_amount      => p_amount,
        p_label       => 'Règlement facture ' || v_number,
        p_actor       => v_actor,
        p_details     => jsonb_build_object('facture', v_number),
        p_occurred_at => p_paid_on::timestamptz
    );

    insert into invoice_payments (
        invoice_id, amount, method, paid_on, journal_entry_id, created_by, client_uuid
    )
    values (
        p_invoice_id, p_amount, p_method, p_paid_on, v_entry, v_actor, p_client_uuid
    )
    returning id into v_id;

    return v_id;
end;
$$;

-- ------------------------------------------------------------
-- 8. WHAT THE FARM LOOKS LIKE
-- ------------------------------------------------------------
-- Line-item detail, so these need full visibility — the same rule 006
-- established. An investor granted 'summary' gets the money reports and not
-- the operational ones, which is the correct reading: how many birds died on
-- Tuesday is running the farm, not overseeing it.

create or replace function stock_on_hand(p_org_id uuid)
returns table (
    item_id       uuid,
    name          text,
    unit          text,
    on_hand       numeric,
    reorder_level numeric,
    below_reorder boolean,
    last_movement timestamptz
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        i.id, i.name, i.unit,
        coalesce(sum(
            case sm.kind
                when 'received' then sm.quantity
                when 'consumed' then -sm.quantity
                when 'wasted'   then -sm.quantity
                -- Signed already: a count that found fewer sacks than the
                -- running total is a negative adjustment.
                when 'adjusted' then sm.quantity
            end
        ), 0),
        i.reorder_level,
        i.reorder_level is not null and coalesce(sum(
            case sm.kind
                when 'received' then sm.quantity
                when 'consumed' then -sm.quantity
                when 'wasted'   then -sm.quantity
                when 'adjusted' then sm.quantity
            end
        ), 0) <= i.reorder_level,
        max(sm.occurred_at)
    from items i
    left join stock_movements sm on sm.item_id = i.id
    where i.org_id = p_org_id
      and i.is_active
      and has_full_visibility(p_org_id)
    group by i.id, i.name, i.unit, i.reorder_level
    order by 6 desc nulls last, i.name;
$$;

-- Birds alive, how old, and whether they are laying as they should.
--
-- `lay_rate` is eggs in the last seven days divided by (birds alive × 7). It
-- is the number that tells a farmer something is wrong days before the money
-- does, which is the entire argument for making somebody count eggs every
-- morning.
create or replace function flock_status(p_org_id uuid, p_include_closed boolean default false)
returns table (
    flock_id    uuid,
    batch_code  text,
    breed       text,
    arrived_on  date,
    age_days    int,
    started     int,
    alive       int,
    died        int,
    sold        int,
    eggs_7d     bigint,
    lay_rate    numeric,
    closed_on   date
)
language sql
stable
security definer
set search_path = public, auth
as $$
    with counts as (
        select
            f.id,
            coalesce(sum(e.quantity) filter (where e.kind = 'mortality'), 0) as died,
            coalesce(sum(e.quantity) filter (where e.kind = 'sold'), 0) as sold
        from flocks f
        left join flock_events e on e.flock_id = f.id
        where f.org_id = p_org_id
        group by f.id
    ),
    eggs as (
        select ep.flock_id, sum(ep.egg_count) as n
        from egg_production ep
        where ep.org_id = p_org_id
          and ep.produced_on > current_date - 7
        group by ep.flock_id
    )
    select
        f.id, f.batch_code, f.breed, f.arrived_on,
        (current_date - f.arrived_on)::int,
        f.bird_count,
        (f.bird_count - c.died - c.sold)::int,
        c.died::int,
        c.sold::int,
        coalesce(e.n, 0),
        case
            when (f.bird_count - c.died - c.sold) > 0
            then round(coalesce(e.n, 0)::numeric
                       / ((f.bird_count - c.died - c.sold) * 7), 3)
            else 0
        end,
        f.closed_on
    from flocks f
    join counts c on c.id = f.id
    left join eggs e on e.flock_id = f.id
    where f.org_id = p_org_id
      and has_full_visibility(p_org_id)
      and (p_include_closed or f.closed_on is null)
    order by f.closed_on nulls first, f.arrived_on desc;
$$;

-- The home screen's day.
create or replace function farm_daily_summary(
    p_org_id uuid,
    p_day    date default current_date
)
returns table (
    eggs        bigint,
    deaths      numeric,
    feed_used   numeric,
    money_in    numeric,
    money_out   numeric
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        (select coalesce(sum(ep.egg_count), 0)
           from egg_production ep
          where ep.org_id = p_org_id and ep.produced_on = p_day),

        (select coalesce(sum(fe.quantity), 0)
           from flock_events fe
           join flocks f on f.id = fe.flock_id
          where f.org_id = p_org_id
            and fe.kind = 'mortality'
            and fe.occurred_at::date = p_day),

        (select coalesce(sum(sm.quantity), 0)
           from stock_movements sm
          where sm.org_id = p_org_id
            and sm.kind = 'consumed'
            and sm.occurred_at::date = p_day),

        (select coalesce(sum(jl.credit - jl.debit), 0)
           from journal_entries je
           join journal_lines jl on jl.journal_entry_id = je.id
           join accounts a on a.id = jl.account_id
          where je.org_id = p_org_id
            and a.type = 'income'
            and je.created_at::date = p_day),

        (select coalesce(sum(jl.debit - jl.credit), 0)
           from journal_entries je
           join journal_lines jl on jl.journal_entry_id = je.id
           join accounts a on a.id = jl.account_id
          where je.org_id = p_org_id
            and a.type = 'expense'
            and je.created_at::date = p_day)
    where has_full_visibility(p_org_id);
$$;

-- Who has not paid, and how late they are.
create or replace function outstanding_invoices(p_org_id uuid)
returns table (
    invoice_id    uuid,
    number        text,
    customer_name text,
    customer_phone text,
    issued_on     date,
    due_on        date,
    total         numeric,
    paid          numeric,
    outstanding   numeric,
    days_overdue  int
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        i.id, i.number, c.name, c.phone, i.issued_on, i.due_on, i.total,
        coalesce(p.paid, 0),
        i.total - coalesce(p.paid, 0),
        case
            when i.due_on is null then 0
            else greatest((current_date - i.due_on)::int, 0)
        end
    from invoices i
    join customers c on c.id = i.customer_id
    left join (
        select invoice_id, sum(amount) as paid
        from invoice_payments group by invoice_id
    ) p on p.invoice_id = i.id
    where i.org_id = p_org_id
      and i.cancelled_at is null
      and has_full_visibility(p_org_id)
      and i.total - coalesce(p.paid, 0) > 0
    order by 10 desc, i.issued_on;
$$;

-- ------------------------------------------------------------
-- 9. RLS
-- ------------------------------------------------------------
-- The same shape as everything else: readable within the org, writable by
-- anyone who is not an observer, and — for the two append-only tables —
-- carrying no update or delete policy at all. That omission is what makes
-- them append-only, exactly as it does for journal_entries.

alter table items enable row level security;
alter table stock_movements enable row level security;
alter table flocks enable row level security;
alter table flock_events enable row level security;
alter table egg_production enable row level security;
alter table customers enable row level security;
alter table invoices enable row level security;
alter table invoice_lines enable row level security;
alter table invoice_payments enable row level security;

drop policy if exists "items readable within org" on items;
create policy "items readable within org"
on items for select using (is_org_member(org_id));

-- Renaming an item and setting its reorder level are ordinary work, not
-- administration: the person who notices the feed runs out early is the
-- person feeding the birds.
drop policy if exists "items managed by non-observers" on items;
create policy "items managed by non-observers"
on items for all using (can_write_org(org_id)) with check (can_write_org(org_id));

-- Operational detail, not a total: the same visibility test the reports use.
drop policy if exists "stock movements readable with full visibility" on stock_movements;
create policy "stock movements readable with full visibility"
on stock_movements for select using (has_full_visibility(org_id));

drop policy if exists "stock movements written by non-observers" on stock_movements;
create policy "stock movements written by non-observers"
on stock_movements for insert with check (can_write_org(org_id));
-- No update, no delete. A miscount is corrected by an 'adjusted' movement.

drop policy if exists "flocks readable within org" on flocks;
create policy "flocks readable within org"
on flocks for select using (is_org_member(org_id));

drop policy if exists "flocks managed by non-observers" on flocks;
create policy "flocks managed by non-observers"
on flocks for all using (can_write_org(org_id)) with check (can_write_org(org_id));

drop policy if exists "flock events readable with full visibility" on flock_events;
create policy "flock events readable with full visibility"
on flock_events for select
using (
    exists (
        select 1 from flocks f
        where f.id = flock_events.flock_id and has_full_visibility(f.org_id)
    )
);

drop policy if exists "flock events written by non-observers" on flock_events;
create policy "flock events written by non-observers"
on flock_events for insert
with check (
    exists (
        select 1 from flocks f
        where f.id = flock_events.flock_id and can_write_org(f.org_id)
    )
);
-- No update, no delete: how many birds died is not a number anybody edits.

drop policy if exists "egg production readable with full visibility" on egg_production;
create policy "egg production readable with full visibility"
on egg_production for select using (has_full_visibility(org_id));

drop policy if exists "egg production written by non-observers" on egg_production;
create policy "egg production written by non-observers"
on egg_production for insert with check (can_write_org(org_id));

drop policy if exists "customers readable within org" on customers;
create policy "customers readable within org"
on customers for select using (is_org_member(org_id));

drop policy if exists "customers managed by non-observers" on customers;
create policy "customers managed by non-observers"
on customers for all using (can_write_org(org_id)) with check (can_write_org(org_id));

drop policy if exists "invoices readable with full visibility" on invoices;
create policy "invoices readable with full visibility"
on invoices for select using (has_full_visibility(org_id));

drop policy if exists "invoices written by non-observers" on invoices;
create policy "invoices written by non-observers"
on invoices for insert with check (can_write_org(org_id));

-- Cancelling is an update, and it is the only one. There is no delete
-- policy: a cancelled invoice is a fact about a customer relationship.
drop policy if exists "invoices cancelled by non-observers" on invoices;
create policy "invoices cancelled by non-observers"
on invoices for update using (can_write_org(org_id)) with check (can_write_org(org_id));

drop policy if exists "invoice lines readable with their invoice" on invoice_lines;
create policy "invoice lines readable with their invoice"
on invoice_lines for select
using (
    exists (
        select 1 from invoices i
        where i.id = invoice_lines.invoice_id and has_full_visibility(i.org_id)
    )
);

drop policy if exists "invoice lines written with their invoice" on invoice_lines;
create policy "invoice lines written with their invoice"
on invoice_lines for insert
with check (
    exists (
        select 1 from invoices i
        where i.id = invoice_lines.invoice_id and can_write_org(i.org_id)
    )
);

drop policy if exists "payments readable with their invoice" on invoice_payments;
create policy "payments readable with their invoice"
on invoice_payments for select
using (
    exists (
        select 1 from invoices i
        where i.id = invoice_payments.invoice_id and has_full_visibility(i.org_id)
    )
);

drop policy if exists "payments written with their invoice" on invoice_payments;
create policy "payments written with their invoice"
on invoice_payments for insert
with check (
    exists (
        select 1 from invoices i
        where i.id = invoice_payments.invoice_id and can_write_org(i.org_id)
    )
);
-- No update, no delete: a payment received is not a thing to un-receive.

-- ------------------------------------------------------------
-- 10. THE LOG WATCHES THIS TOO
-- ------------------------------------------------------------
-- 008 attached its trigger to a fixed list of tables, which by definition
-- could not include tables that did not exist yet. Flocks and customers are
-- structural — who the farm sells to, and what it is raising — and belong in
-- the same trail as the chart of accounts.
--
-- The two high-volume append-only tables are left out for the same reason
-- journal_lines is: they are already unmodifiable, so a log of them would
-- record only that they were written, which they say themselves.
do $$
declare
    v_table text;
begin
    foreach v_table in array array['items', 'flocks', 'customers', 'invoices']
    loop
        execute format('drop trigger if exists audit_%1$s on %1$I', v_table);
        execute format(
            'create trigger audit_%1$s after insert or update or delete on %1$I
             for each row execute function audit_row()',
            v_table
        );
    end loop;
end $$;

-- invoices reaches its org through org_id, items and customers likewise, and
-- flocks likewise — so audit_row() resolves all four without changes.

-- ------------------------------------------------------------
-- 11. GRANTS
-- ------------------------------------------------------------
revoke execute on function post_ledger_pair(uuid, uuid, uuid, numeric, text, uuid, text, jsonb, uuid, text, timestamptz) from public;
revoke execute on function ensure_item(uuid, text, text, uuid) from public;
revoke execute on function ensure_customer(uuid, text, text, uuid) from public;

revoke execute on function receive_stock(uuid, text, numeric, numeric, text, text, text, uuid, text, uuid, text, timestamptz) from public;
revoke execute on function move_stock(uuid, text, numeric, text, text, uuid, text, uuid, text, timestamptz) from public;
revoke execute on function open_flock(uuid, text, int, text, uuid, date) from public;
revoke execute on function record_flock_event(uuid, text, numeric, uuid, text, uuid, text, timestamptz) from public;
revoke execute on function record_eggs(uuid, int, uuid, text, uuid, date, uuid, text) from public;
revoke execute on function record_farm_sale(uuid, numeric, text, uuid, text, text, text, text, uuid, text, timestamptz) from public;
revoke execute on function create_invoice(uuid, text, jsonb, uuid, text, text, date, text, text, uuid, date) from public;
revoke execute on function record_invoice_payment(uuid, numeric, text, uuid, date, uuid) from public;
revoke execute on function stock_on_hand(uuid) from public;
revoke execute on function flock_status(uuid, boolean) from public;
revoke execute on function farm_daily_summary(uuid, date) from public;
revoke execute on function outstanding_invoices(uuid) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function receive_stock(uuid, text, numeric, numeric, text, text, text, uuid, text, uuid, text, timestamptz) to authenticated;
        grant execute on function move_stock(uuid, text, numeric, text, text, uuid, text, uuid, text, timestamptz) to authenticated;
        grant execute on function open_flock(uuid, text, int, text, uuid, date) to authenticated;
        grant execute on function record_flock_event(uuid, text, numeric, uuid, text, uuid, text, timestamptz) to authenticated;
        grant execute on function record_eggs(uuid, int, uuid, text, uuid, date, uuid, text) to authenticated;
        grant execute on function record_farm_sale(uuid, numeric, text, uuid, text, text, text, text, uuid, text, timestamptz) to authenticated;
        grant execute on function create_invoice(uuid, text, jsonb, uuid, text, text, date, text, text, uuid, date) to authenticated;
        grant execute on function record_invoice_payment(uuid, numeric, text, uuid, date, uuid) to authenticated;
        grant execute on function stock_on_hand(uuid) to authenticated;
        grant execute on function flock_status(uuid, boolean) to authenticated;
        grant execute on function farm_daily_summary(uuid, date) to authenticated;
        grant execute on function outstanding_invoices(uuid) to authenticated;
        grant execute on function seed_farm_accounts(uuid) to authenticated;

        grant select, insert, update, delete on
            items, stock_movements, flocks, flock_events, egg_production,
            customers, invoices, invoice_lines, invoice_payments
            to authenticated;
    end if;
end $$;
