-- ============================================================
-- 026_production.sql — the transformation tool.
--
-- The cake lady's migration. She buys flour, oil and sugar at the market,
-- turns them into forty cakes, and sells the cakes. Until now the app could
-- say what she bought and what she sold, but the step in the middle — the
-- transformation — happened off the books, and she had to divide "what I
-- spent" by "how many came out" in her head to know what a cake costs her.
--
-- A production run is that middle step, recorded: *I used these products,
-- I made that product.* The run
--
--   * decrements each ingredient's count,
--   * increments the finished product's count,
--   * and moves the ingredients' cost onto the finished product, so
--     `products.cost_price` on the cake becomes what one cake actually
--     costs to make — which is the number every later sale snapshots into
--     its margin.
--
-- Two decisions worth knowing before reading the rest.
--
-- 1. **No journal entry.** The money left the business on the day the
--    ingredients were bought — receive_products() posted 'Achat de
--    marchandise' then, the same rule the farm applies to feed. Production
--    moves value from one shelf to another inside the business; nothing is
--    earned and nothing is spent. Writing an entry here would count the
--    same ingredients twice in the income statement.
--
-- 2. **Ingredients are ordinary products.** Flour is a product the shop
--    happens not to sell, received at its real price through the existing
--    delivery flow. No parallel "raw materials" table: the same count, the
--    same cost column, the same screens. A farm pressing shea nuts into
--    butter and a shop baking cakes use the identical mechanics.
--
-- Same posture as the carnet in 024: the tables are readable under RLS and
-- writable only through the function, because the whole value of the run is
-- that its cost arithmetic was done by the server, not typed.
-- ============================================================

-- ------------------------------------------------------------
-- 1. THE TABLES
-- ------------------------------------------------------------

create table if not exists production_runs (
    id           uuid primary key default gen_random_uuid(),
    org_id       uuid not null references orgs(id) on delete cascade,
    -- What came out of the transformation.
    product_id   uuid not null references products(id),
    -- The name as it was that day; a product renamed next month must not
    -- rewrite last month's history. Same rule as sale_lines.name.
    product_name text not null,
    quantity     numeric(14,3) not null check (quantity > 0),
    -- What the consumed ingredients cost, summed from the snapshots below.
    total_cost   numeric(14,2) not null default 0,
    -- total_cost / quantity: what one unit costs to make. Four decimals
    -- because a batch of 40 rarely divides evenly, and the rounding error
    -- multiplied back by the batch should stay under a franc.
    unit_cost    numeric(14,4) not null default 0,
    note         text,
    occurred_at  timestamptz not null default now(),
    recorded_by  uuid references profiles(id),
    device_id    text,
    -- Two phones retrying the same run must produce one run. Same contract
    -- as every other recording function since 002.
    client_uuid  uuid,
    created_at   timestamptz not null default now()
);

create unique index if not exists production_runs_client_uuid_key
    on production_runs (org_id, client_uuid) where client_uuid is not null;

create index if not exists production_runs_by_day
    on production_runs (org_id, occurred_at desc);

create table if not exists production_inputs (
    id         uuid primary key default gen_random_uuid(),
    run_id     uuid not null references production_runs(id) on delete cascade,
    product_id uuid not null references products(id),
    -- Snapshots, for the same reason sale_lines carries them: the run must
    -- keep saying what it consumed and at what cost, whatever happens to
    -- the product row afterwards.
    name       text not null,
    quantity   numeric(14,3) not null check (quantity > 0),
    unit_cost  numeric(14,4) not null default 0,
    line_total numeric(14,2) not null default 0
);

create index if not exists production_inputs_by_run
    on production_inputs (run_id);

comment on table production_runs is
    'One transformation: these ingredients became that product, at this cost.';
comment on table production_inputs is
    'What a run consumed, with name and cost as they were at the time.';

-- ------------------------------------------------------------
-- 2. RECORDING A RUN
-- ------------------------------------------------------------

-- [p_inputs] is a json array of {product_id?, name?, quantity}. An input may
-- arrive by id (the screen's dropdown) or by name (typed, matched the way
-- every name is matched here: case-insensitively, on trimmed text). An input
-- that names a product this business has never received is refused rather
-- than minted at cost zero — a silent zero-cost ingredient would make every
-- later margin a lie.
--
-- The output may arrive by id or by name, and *is* created if absent,
-- because "Gâteau" legitimately begins to exist at the first baking.
--
-- SECURITY DEFINER for the same reasons record_credit_sale() is: it may mint
-- the output product and it writes rows no policy allows directly. It makes
-- the same membership check the policies would have made.
create or replace function record_production(
    p_org_id       uuid,
    p_quantity     numeric,
    p_inputs       jsonb,
    p_product_id   uuid        default null,
    p_product_name text        default null,
    p_note         text        default null,
    p_recorded_by  uuid        default null,
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
    v_actor    uuid := auth.uid();
    v_run      uuid;
    v_output   uuid;
    v_out_name text;
    v_line     jsonb;
    v_input    uuid;
    v_in_name  text;
    v_qty      numeric;
    v_cost     numeric;
    v_total    numeric := 0;
    v_unit     numeric;
begin
    if v_actor is null then
        raise exception 'record_production() needs a signed-in caller';
    end if;
    if p_recorded_by is not null and p_recorded_by <> v_actor then
        raise exception 'record_production() cannot record on behalf of another user';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record entries for this business';
    end if;
    if p_quantity is null or p_quantity <= 0 then
        raise exception 'A production needs the quantity that was made';
    end if;
    if p_inputs is null or jsonb_typeof(p_inputs) <> 'array'
       or jsonb_array_length(p_inputs) = 0 then
        raise exception 'A production needs at least one ingredient';
    end if;

    -- The outbox may deliver twice; the second delivery must find the first
    -- rather than bake the same forty cakes again.
    if p_client_uuid is not null then
        select id into v_run from production_runs
        where org_id = p_org_id and client_uuid = p_client_uuid;
        if found then
            return v_run;
        end if;
    end if;

    -- The output: by id, or by name — created at the first baking.
    v_output := p_product_id;
    if v_output is null then
        if btrim(coalesce(p_product_name, '')) = '' then
            raise exception 'A production needs the product that was made';
        end if;
        v_output := ensure_product(p_org_id, p_product_name,
                                   p_actor => v_actor);
    end if;

    select name into v_out_name
    from products where id = v_output and org_id = p_org_id;
    if v_out_name is null then
        raise exception 'No such product in this business';
    end if;

    insert into production_runs (org_id, product_id, product_name, quantity,
                                 note, occurred_at, recorded_by, device_id,
                                 client_uuid)
    values (p_org_id, v_output, v_out_name, p_quantity,
            nullif(btrim(coalesce(p_note, '')), ''), p_occurred_at, v_actor,
            p_device_id, p_client_uuid)
    returning id into v_run;

    for v_line in select * from jsonb_array_elements(p_inputs)
    loop
        v_qty := coalesce((v_line ->> 'quantity')::numeric, 0);
        if v_qty <= 0 then
            raise exception 'Every ingredient needs a quantity greater than zero';
        end if;

        v_input := nullif(v_line ->> 'product_id', '')::uuid;
        if v_input is null then
            v_in_name := btrim(coalesce(v_line ->> 'name', ''));
            if v_in_name = '' then
                raise exception 'Every ingredient needs a product or a name';
            end if;
            select id into v_input from products
            where org_id = p_org_id
              and lower(btrim(name)) = lower(v_in_name);
        end if;

        select name, cost_price into v_in_name, v_cost
        from products where id = v_input and org_id = p_org_id;
        if v_in_name is null then
            raise exception 'Unknown ingredient: % — receive it into stock first',
                coalesce(btrim(v_line ->> 'name'), v_line ->> 'product_id');
        end if;
        if v_input = v_output then
            raise exception 'A product cannot be its own ingredient';
        end if;

        insert into production_inputs (run_id, product_id, name, quantity,
                                       unit_cost, line_total)
        values (v_run, v_input, v_in_name, v_qty,
                coalesce(v_cost, 0), round(v_qty * coalesce(v_cost, 0), 2));

        -- The count can go negative, deliberately — the same rule as a sale.
        -- The cakes exist; refusing to record them because the flour count
        -- was wrong would make the count more important than the cakes, and
        -- the count is the thing more likely to be wrong.
        update products set quantity = quantity - v_qty where id = v_input;

        v_total := v_total + round(v_qty * coalesce(v_cost, 0), 2);
    end loop;

    v_unit := round(v_total / p_quantity, 4);

    update production_runs
       set total_cost = v_total, unit_cost = v_unit
     where id = v_run;

    -- The finished product: more on the shelf, at what this batch cost per
    -- unit. Overwriting cost_price with the latest batch is the same rule
    -- receive_products() applies to a delivery with a new unit cost, and it
    -- is what every later sale line snapshots as its margin base.
    update products
       set quantity   = quantity + p_quantity,
           cost_price = case when v_total > 0 then round(v_unit, 2)
                             else cost_price end
     where id = v_output;

    return v_run;
end;
$$;

-- ------------------------------------------------------------
-- 3. WHAT THE MAKER LOOKS AT
-- ------------------------------------------------------------

-- Recent runs, newest first, each carrying its ingredient list as one json
-- value so the screen renders a run without a second round trip.
create or replace function production_history(
    p_org_id uuid,
    p_limit  int default 50
)
returns table (
    run_id       uuid,
    product_name text,
    quantity     numeric,
    total_cost   numeric,
    unit_cost    numeric,
    occurred_at  timestamptz,
    inputs       jsonb
)
language sql
stable
security invoker
as $$
    select r.id, r.product_name, r.quantity, r.total_cost, r.unit_cost,
           r.occurred_at,
           coalesce((
               select jsonb_agg(jsonb_build_object(
                          'name', i.name, 'quantity', i.quantity)
                      order by i.name)
               from production_inputs i
               where i.run_id = r.id
           ), '[]'::jsonb)
      from production_runs r
     where r.org_id = p_org_id
     order by r.occurred_at desc
     limit p_limit;
$$;

-- ------------------------------------------------------------
-- 4. ROW LEVEL SECURITY
-- ------------------------------------------------------------

alter table production_runs   enable row level security;
alter table production_inputs enable row level security;

drop policy if exists "production readable within org" on production_runs;
create policy "production readable within org"
on production_runs for select using (is_org_member(org_id));

drop policy if exists "production inputs readable with their run" on production_inputs;
create policy "production inputs readable with their run"
on production_inputs for select using (
    exists (select 1 from production_runs r
            where r.id = run_id and is_org_member(r.org_id))
);

-- No insert, update or delete policies, on purpose. A run's arithmetic —
-- the snapshots, the decrements, the cost moved onto the product — is done
-- by record_production() or not at all; a hand-written row would be a run
-- whose numbers nobody computed.

-- ------------------------------------------------------------
-- 5. GRANTS
-- ------------------------------------------------------------

revoke execute on function record_production(uuid, numeric, jsonb, uuid, text, text, uuid, uuid, text, timestamptz) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant select on production_runs, production_inputs to authenticated;
        grant execute on function record_production(uuid, numeric, jsonb, uuid, text, text, uuid, uuid, text, timestamptz) to authenticated;
        grant execute on function production_history(uuid, int) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
