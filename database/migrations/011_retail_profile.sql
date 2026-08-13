-- ============================================================
-- 011_retail_profile.sql — Esperance's store.
--
-- The retail profile: products that expire, sales that decrement them, and
-- returns that put them back. Everything money-shaped goes through
-- `record_entry()` from 007 rather than writing journal lines here, so a sale
-- in a shop and an offering in a church land in the same ledger and the same
-- income statement reads both.
--
-- Three decisions worth knowing before reading the rest.
--
-- 1. **Stock is a column, not a derived total.** `products.quantity` is
--    written by the functions below. The farm does the opposite — it derives
--    counts from append-only `stock_movements` — and that is the better model
--    for a place where mortality and waste have to stay visible. A shop
--    counts differently: Esperance needs "how many do I have right now" on a
--    screen in a market with no signal, and a running sum over every sale
--    ever made is not that. Every movement is still recorded in `sale_lines`,
--    so the column can be rebuilt from history if it ever drifts.
--
-- 2. **A return is a sale with kind = 'return'.** Not a deletion, not an
--    edit, and not a negative row hidden inside the same kind. It posts its
--    own reversing ledger entry, so the books show both the sale and the
--    return rather than a number that quietly shrank.
--
-- 3. **Cost is snapshotted onto the line.** `sale_lines.unit_cost` copies
--    `products.cost_price` at the moment of sale. Without it, changing a
--    product's cost price would silently rewrite the margin on every sale
--    already made.
--
-- Not here, and deliberately: the camera, the R2 upload, the on-device OCR
-- and the barcode scanner that M5 also asks for. `products.barcode` and the
-- existing `documents` table are the seams they attach to; none of them can
-- be built or tested without a device in a hand.
-- ============================================================

-- ------------------------------------------------------------
-- What is on the shelves
-- ------------------------------------------------------------

create table if not exists products (
    id            uuid primary key default gen_random_uuid(),
    org_id        uuid not null references orgs(id) on delete cascade,
    name          text not null,
    -- Scanned, not typed. Null until a barcode is read, which is most of them.
    barcode       text,
    -- The shop's own reference, when it has one.
    sku           text,
    -- What it cost to buy. Drives margin and the value at risk on expiry.
    cost_price    numeric(14,2) not null default 0 check (cost_price >= 0),
    sale_price    numeric(14,2) not null default 0 check (sale_price >= 0),
    quantity      numeric(14,3) not null default 0,
    -- The whole point of the module for Esperance: stock that dies on a date.
    expires_on    date,
    -- Below this, the home screen says so. Null means never mention it.
    low_stock_at  numeric(14,3),
    is_active     boolean not null default true,
    created_at    timestamptz not null default now(),
    created_by    uuid references profiles(id)
);

-- One product per name per shop, matched the way a name arrives from a phone
-- keyboard: case-insensitively, on trimmed text. Same rule as ensure_account()
-- in 007 and ensure_item() in 009.
create unique index if not exists products_by_name
    on products (org_id, lower(btrim(name)));

-- A barcode identifies exactly one product within a shop. Partial, because
-- most products never get one and null is not a duplicate.
create unique index if not exists products_by_barcode
    on products (org_id, barcode) where barcode is not null;

create index if not exists products_active
    on products (org_id) where is_active;

-- The expiry alert query, which runs on every home screen open.
create index if not exists products_by_expiry
    on products (org_id, expires_on)
    where expires_on is not null and is_active;

-- ------------------------------------------------------------
-- What was sold
-- ------------------------------------------------------------

create table if not exists sales (
    id           uuid primary key default gen_random_uuid(),
    org_id       uuid not null references orgs(id) on delete cascade,
    kind         text not null default 'sale' check (kind in ('sale', 'return')),
    occurred_at  timestamptz not null default now(),
    total        numeric(14,2) not null default 0,
    -- 'cash' | 'bank' | 'mobile_money', or any account name. Passed straight
    -- to record_entry(), which resolves it to a cash account.
    method       text not null default 'cash',
    note         text,
    -- The ledger entry this sale posted. Null only for a sale recorded
    -- against a shop with no accounts, which cannot happen through the
    -- functions below.
    entry_id     uuid references journal_entries(id),
    -- The sale being undone, for kind = 'return'.
    reverses_id  uuid references sales(id),
    recorded_by  uuid references profiles(id),
    device_id    text,
    -- Two phones in a market both retrying the same sale must produce one
    -- sale. Same contract as record_contribution() in 002.
    client_uuid  uuid,
    created_at   timestamptz not null default now()
);

create unique index if not exists sales_client_uuid_key
    on sales (org_id, client_uuid) where client_uuid is not null;

create index if not exists sales_by_day
    on sales (org_id, occurred_at desc);

create table if not exists sale_lines (
    id          uuid primary key default gen_random_uuid(),
    sale_id     uuid not null references sales(id) on delete cascade,
    product_id  uuid references products(id),
    -- The name as it was at the time of sale. A product renamed next month
    -- must not rewrite last month's receipt.
    name        text not null,
    quantity    numeric(14,3) not null check (quantity > 0),
    unit_price  numeric(14,2) not null check (unit_price >= 0),
    -- Snapshotted; see the header.
    unit_cost   numeric(14,2) not null default 0,
    line_total  numeric(14,2) not null
);

create index if not exists sale_lines_by_sale on sale_lines (sale_id);
create index if not exists sale_lines_by_product on sale_lines (product_id);

-- ------------------------------------------------------------
-- Putting a product on the shelf
-- ------------------------------------------------------------

-- Finds the product by name the first time and every time after, so a shop
-- that types "Sucre 1kg" twice has one product with two sales rather than two
-- products with one each.
create or replace function ensure_product(
    p_org_id     uuid,
    p_name       text,
    p_sale_price numeric default null,
    p_cost_price numeric default null,
    p_barcode    text    default null,
    p_expires_on date    default null,
    p_actor      uuid    default null
)
returns uuid
language plpgsql
as $$
declare
    v_name text := btrim(coalesce(p_name, ''));
    v_id   uuid;
begin
    if v_name = '' then
        raise exception 'A product needs a name';
    end if;

    select id into v_id from products
    where org_id = p_org_id and lower(btrim(name)) = lower(v_name);

    if v_id is null then
        -- p_actor rather than auth.uid(): this runs as the caller, and the
        -- `authenticated` role has no rights in the auth schema. Every
        -- SECURITY DEFINER function that calls this passes the actor down,
        -- the same way ensure_item() works in 009.
        insert into products (org_id, name, sale_price, cost_price, barcode,
                              expires_on, created_by)
        values (p_org_id, v_name,
                coalesce(p_sale_price, 0), coalesce(p_cost_price, 0),
                p_barcode, p_expires_on, p_actor)
        returning id into v_id;
    else
        -- Only fill in what was missing. A price passed on a later sale must
        -- not silently rewrite the shelf price somebody set on purpose.
        update products set
            sale_price = case when sale_price = 0 and p_sale_price is not null
                              then p_sale_price else sale_price end,
            cost_price = case when cost_price = 0 and p_cost_price is not null
                              then p_cost_price else cost_price end,
            barcode    = coalesce(barcode, p_barcode),
            expires_on = coalesce(expires_on, p_expires_on)
        where id = v_id;
    end if;

    return v_id;
end;
$$;

-- Stock arriving. Increases the count and posts the purchase as an expense,
-- the same treatment the farm gives feed: the day the goods arrive is the day
-- the money is gone.
create or replace function receive_products(
    p_org_id      uuid,
    p_product_id  uuid,
    p_quantity    numeric,
    p_unit_cost   numeric     default null,
    p_expires_on  date        default null,
    p_method      text        default 'cash',
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
    v_actor   uuid := auth.uid();
    v_name    text;
    v_cost    numeric;
    v_entry   uuid;
begin
    if p_quantity is null or p_quantity <= 0 then
        raise exception 'A delivery needs a quantity';
    end if;

    select name, cost_price into v_name, v_cost
    from products where id = p_product_id and org_id = p_org_id;

    if v_name is null then
        raise exception 'No such product in this business';
    end if;

    v_cost := coalesce(p_unit_cost, v_cost, 0);

    update products set
        quantity   = quantity + p_quantity,
        cost_price = case when p_unit_cost is not null then p_unit_cost
                          else cost_price end,
        expires_on = coalesce(p_expires_on, expires_on)
    where id = p_product_id;

    -- Only money that actually moved gets a ledger entry. Stock received on
    -- credit, or with no cost recorded, still updates the count.
    if v_cost > 0 then
        v_entry := record_entry(
            p_org_id      => p_org_id,
            p_amount      => v_cost * p_quantity,
            p_direction   => 'out',
            p_label       => 'Achat de marchandise',
            p_recorded_by => v_actor,
            p_category    => 'Achats de marchandises',
            p_method      => p_method,
            p_memo        => v_name,
            p_details     => jsonb_build_object('product', v_name,
                                                'quantity', p_quantity),
            p_client_uuid => p_client_uuid,
            p_device_id   => p_device_id,
            p_occurred_at => p_occurred_at
        );
    end if;

    return v_entry;
end;
$$;

-- ------------------------------------------------------------
-- Selling
-- ------------------------------------------------------------

-- One sale, one or more lines, one ledger entry.
--
-- [p_lines] is a json array of {product_id?, name, quantity, unit_price}.
-- A line with no product_id and a name creates the product, so somebody can
-- sell a thing that was never entered without stopping to enter it first —
-- the capture-first rule M5 is built around.
create or replace function record_sale(
    p_org_id      uuid,
    p_lines       jsonb,
    p_method      text        default 'cash',
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
    v_sale_id  uuid;
    v_existing uuid;
    v_line     jsonb;
    v_product  uuid;
    v_name     text;
    v_qty      numeric;
    v_price    numeric;
    v_cost     numeric;
    v_total    numeric := 0;
    v_entry    uuid;
begin
    if p_lines is null or jsonb_typeof(p_lines) <> 'array'
       or jsonb_array_length(p_lines) = 0 then
        raise exception 'A sale needs at least one line';
    end if;

    -- A retried sale returns the original rather than selling twice. The
    -- phone in a market retries whenever signal returns, which is often.
    if p_client_uuid is not null then
        select id into v_existing from sales
        where org_id = p_org_id and client_uuid = p_client_uuid;
        if v_existing is not null then
            return v_existing;
        end if;
    end if;

    insert into sales (org_id, kind, occurred_at, method, note, recorded_by,
                       device_id, client_uuid)
    values (p_org_id, 'sale', p_occurred_at, p_method, p_note, v_actor,
            p_device_id, p_client_uuid)
    returning id into v_sale_id;

    for v_line in select * from jsonb_array_elements(p_lines)
    loop
        v_name  := btrim(coalesce(v_line ->> 'name', ''));
        v_qty   := coalesce((v_line ->> 'quantity')::numeric, 0);
        v_price := coalesce((v_line ->> 'unit_price')::numeric, 0);

        if v_qty <= 0 then
            raise exception 'Every line needs a quantity greater than zero';
        end if;

        v_product := nullif(v_line ->> 'product_id', '')::uuid;

        if v_product is null then
            if v_name = '' then
                raise exception 'Every line needs a product or a name';
            end if;
            v_product := ensure_product(p_org_id, v_name,
                                        p_sale_price => v_price,
                                        p_actor      => v_actor);
        end if;

        select name, cost_price into v_name, v_cost
        from products where id = v_product and org_id = p_org_id;

        if v_name is null then
            raise exception 'No such product in this business';
        end if;

        insert into sale_lines (sale_id, product_id, name, quantity,
                                unit_price, unit_cost, line_total)
        values (v_sale_id, v_product, v_name, v_qty, v_price,
                coalesce(v_cost, 0), v_qty * v_price);

        -- Stock can go negative. That is deliberate: refusing the sale
        -- because the count is wrong would make the count more important than
        -- the customer standing there, and the count is the thing more likely
        -- to be wrong.
        update products set quantity = quantity - v_qty where id = v_product;

        v_total := v_total + (v_qty * v_price);
    end loop;

    if v_total > 0 then
        v_entry := record_entry(
            p_org_id      => p_org_id,
            p_amount      => v_total,
            p_direction   => 'in',
            p_label       => 'Vente',
            p_recorded_by => v_actor,
            p_category    => 'Ventes',
            p_method      => p_method,
            p_memo        => p_note,
            p_details     => jsonb_build_object('sale_id', v_sale_id),
            p_client_uuid => p_client_uuid,
            p_device_id   => p_device_id,
            p_occurred_at => p_occurred_at
        );
    end if;

    update sales set total = v_total, entry_id = v_entry where id = v_sale_id;

    return v_sale_id;
end;
$$;

-- Undoing a sale, by writing another one rather than erasing it.
create or replace function record_return(
    p_sale_id     uuid,
    p_note        text default null,
    p_client_uuid uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_org      uuid;
    v_method   text;
    v_total    numeric;
    v_kind     text;
    v_return   uuid;
    v_existing uuid;
    v_line     record;
    v_entry    uuid;
begin
    select org_id, method, total, kind
      into v_org, v_method, v_total, v_kind
    from sales where id = p_sale_id;

    if v_org is null then
        raise exception 'No such sale';
    end if;
    if v_kind = 'return' then
        raise exception 'That is already a return';
    end if;
    if exists (select 1 from sales where reverses_id = p_sale_id) then
        raise exception 'That sale has already been returned';
    end if;

    if p_client_uuid is not null then
        select id into v_existing from sales
        where org_id = v_org and client_uuid = p_client_uuid;
        if v_existing is not null then
            return v_existing;
        end if;
    end if;

    insert into sales (org_id, kind, method, note, total, reverses_id,
                       recorded_by, client_uuid)
    values (v_org, 'return', v_method, p_note, v_total, p_sale_id,
            v_actor, p_client_uuid)
    returning id into v_return;

    -- The goods come back onto the shelf, and the lines are copied so the
    -- return says what was returned rather than only how much money moved.
    for v_line in select * from sale_lines where sale_id = p_sale_id
    loop
        insert into sale_lines (sale_id, product_id, name, quantity,
                                unit_price, unit_cost, line_total)
        values (v_return, v_line.product_id, v_line.name, v_line.quantity,
                v_line.unit_price, v_line.unit_cost, v_line.line_total);

        update products set quantity = quantity + v_line.quantity
        where id = v_line.product_id;
    end loop;

    if v_total > 0 then
        v_entry := record_entry(
            p_org_id      => v_org,
            p_amount      => v_total,
            p_direction   => 'out',
            p_label       => 'Retour de vente',
            p_recorded_by => v_actor,
            p_category    => 'Ventes',
            p_method      => v_method,
            p_memo        => p_note,
            p_details     => jsonb_build_object('reverses', p_sale_id),
            p_client_uuid => p_client_uuid
        );
        update sales set entry_id = v_entry where id = v_return;
    end if;

    return v_return;
end;
$$;

-- ------------------------------------------------------------
-- What the shopkeeper looks at
-- ------------------------------------------------------------

-- Stock that dies soon, and what it cost. The second number is the one that
-- makes anybody act: "3 articles, 82 000 en jeu" beats a list of dates.
create or replace function expiring_products(
    p_org_id uuid,
    p_within int default 14
)
returns table (
    product_id  uuid,
    name        text,
    quantity    numeric,
    expires_on  date,
    days_left   int,
    value_at_risk numeric
)
language sql
stable
security invoker
set search_path = public, auth
as $$
    select
        p.id, p.name, p.quantity, p.expires_on,
        (p.expires_on - current_date)::int,
        round(p.quantity * p.cost_price, 2)
    from products p
    where p.org_id = p_org_id
      and p.is_active
      and p.expires_on is not null
      and p.quantity > 0
      and p.expires_on <= current_date + p_within
    order by p.expires_on, p.name;
$$;

-- The day, as one row: what came in, what went out, how many sales.
create or replace function store_day(
    p_org_id uuid,
    p_on     date default current_date
)
returns table (
    sales_total   numeric,
    returns_total numeric,
    net_sales     numeric,
    sale_count    int,
    items_sold    numeric
)
language sql
stable
security invoker
set search_path = public, auth
as $$
    select
        coalesce(sum(s.total) filter (where s.kind = 'sale'), 0),
        coalesce(sum(s.total) filter (where s.kind = 'return'), 0),
        coalesce(sum(s.total) filter (where s.kind = 'sale'), 0)
          - coalesce(sum(s.total) filter (where s.kind = 'return'), 0),
        count(*) filter (where s.kind = 'sale')::int,
        coalesce((
            select sum(l.quantity)
            from sale_lines l
            join sales s2 on s2.id = l.sale_id
            where s2.org_id = p_org_id
              and s2.kind = 'sale'
              and (s2.occurred_at at time zone 'UTC')::date = p_on
        ), 0)
    from sales s
    where s.org_id = p_org_id
      and (s.occurred_at at time zone 'UTC')::date = p_on;
$$;

-- The number that renews the subscription: cost value of stock that was sold
-- while it was within the expiry window rather than thrown away.
--
-- This is a definition, not a measurement, and it is deliberately the modest
-- one: it counts only goods sold in the last [p_within] days of their life,
-- which is stock that was at real risk of becoming waste. It cannot know what
-- would have happened without the app, and does not pretend to.
create or replace function losses_avoided(
    p_org_id uuid,
    p_within int default 14
)
returns numeric
language sql
stable
security invoker
set search_path = public, auth
as $$
    select coalesce(round(sum(l.quantity * l.unit_cost), 2), 0)
    from sale_lines l
    join sales s   on s.id = l.sale_id and s.kind = 'sale'
    join products p on p.id = l.product_id
    where s.org_id = p_org_id
      and p.expires_on is not null
      and (s.occurred_at at time zone 'UTC')::date
            between p.expires_on - p_within and p.expires_on;
$$;

-- ------------------------------------------------------------
-- Seeding a new shop
-- ------------------------------------------------------------

-- Called by create_org() for profile = 'retail'. The generic six accounts do
-- not name what a shop actually does with money.
create or replace function seed_retail_accounts(p_org_id uuid)
returns void
language plpgsql
as $$
begin
    insert into accounts (org_id, code, name, type) values
        (p_org_id, '1000', 'Caisse',                 'asset'),
        (p_org_id, '1010', 'Banque',                 'asset'),
        (p_org_id, '1020', 'Mobile Money',           'asset'),
        (p_org_id, '4000', 'Ventes',                 'income'),
        (p_org_id, '5000', 'Achats de marchandises', 'expense'),
        (p_org_id, '5010', 'Loyer',                  'expense'),
        (p_org_id, '5020', 'Transport',              'expense'),
        (p_org_id, '5030', 'Salaires',               'expense')
    on conflict (org_id, code) do nothing;
end;
$$;

-- create_org() seeds the church chart for a church and a generic one for
-- everything else. A shop now gets its own, without touching the platform
-- admin migration: same body, one more branch.
create or replace function create_org(
    p_name     text,
    p_slug     text,
    p_profile  text default 'generic',
    p_currency text default 'XOF'
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org_id uuid;
begin
    if not exists(select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can create a new business';
    end if;

    insert into orgs (name, slug, profile, default_currency)
    values (p_name, p_slug, p_profile, p_currency)
    returning id into v_org_id;

    insert into memberships (org_id, user_id, role, scope_kind, scope_id)
    values (v_org_id, auth.uid(), 'owner', 'org', v_org_id);

    if p_profile = 'church' then
        perform seed_church_accounts(v_org_id);
    elsif p_profile = 'retail' then
        perform seed_retail_accounts(v_org_id);
    else
        insert into accounts (org_id, code, name, type) values
            (v_org_id, '1000', 'Cash on Hand',        'asset'),
            (v_org_id, '1010', 'Bank Account',        'asset'),
            (v_org_id, '1020', 'Mobile Money',        'asset'),
            (v_org_id, '4000', 'Sales',                'income'),
            (v_org_id, '5000', 'Purchases',            'expense'),
            (v_org_id, '5010', 'Operating Expenses',   'expense')
        on conflict (org_id, code) do nothing;
    end if;

    return v_org_id;
end;
$$;

-- ------------------------------------------------------------
-- Row level security
--
-- Same shape as every other module: reading needs membership, writing needs a
-- role that is not observer, and neither is decided by the client.
-- ------------------------------------------------------------

alter table products   enable row level security;
alter table sales      enable row level security;
alter table sale_lines enable row level security;

drop policy if exists "products readable within org" on products;
create policy "products readable within org"
on products for select using (is_org_member(org_id));

drop policy if exists "products writable by staff" on products;
create policy "products writable by staff"
on products for insert with check (can_write_org(org_id));

drop policy if exists "products updatable by staff" on products;
create policy "products updatable by staff"
on products for update using (can_write_org(org_id))
with check (can_write_org(org_id));

drop policy if exists "sales readable within org" on sales;
create policy "sales readable within org"
on sales for select using (is_org_member(org_id));

drop policy if exists "sales writable by staff" on sales;
create policy "sales writable by staff"
on sales for insert with check (can_write_org(org_id));

-- No update and no delete policy on sales, on purpose. A sale that was wrong
-- is corrected by a return, which leaves both rows visible. This is the same
-- rule the ledger has had since the first schema.

drop policy if exists "sale lines readable with their sale" on sale_lines;
create policy "sale lines readable with their sale"
on sale_lines for select using (
    exists (select 1 from sales s where s.id = sale_id and is_org_member(s.org_id))
);

drop policy if exists "sale lines writable with their sale" on sale_lines;
create policy "sale lines writable with their sale"
on sale_lines for insert with check (
    exists (select 1 from sales s where s.id = sale_id and can_write_org(s.org_id))
);

comment on table products is
    'What a shop sells: prices, count on hand, and the date stock dies.';
comment on table sales is
    'One sale or one return. Never edited; a mistake is corrected by a return.';
comment on table sale_lines is
    'The products on a sale, with the name and cost as they were at the time.';
