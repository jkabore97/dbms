-- ============================================================
-- 019_farm_general.sql — a farm that is not only chickens.
--
-- 009 built one farm: Ignace's, which is poultry. `flocks` counts birds,
-- `egg_production` counts eggs, and the home screen leads with both. Every
-- other farm in the country is at best half-served — a herd of goats has no
-- table, a field of onions has no table, and a farmer with both is expected
-- to record their harvest as "other income" and their animals as a flock with
-- a batch code.
--
-- What is added, and what is deliberately not.
--
-- **Herds, not just flocks.** `herds` is what `flocks` should have been: a
-- group of animals of any species, counted, with the same arrival and closing
-- shape. `flocks` is not touched and not migrated — Ignace's history is in
-- it, `flock_status()` reads it, and rewriting a working module to make a
-- name tidier is how live data gets lost. A poultry farm keeps using flocks;
-- everyone else uses herds; the home screen shows whichever a farm has.
--
-- **Crop cycles, because a field is a period and not a thing.** The same plot
-- grows onions from October and maize from June, and asking what a plot
-- produced without asking when is a question with no answer. So the unit of
-- record is one planting: a crop, a plot, a date in, a date expected out.
--
-- **Harvests, weighed and then sold separately.** Bringing a crop in and
-- selling it are two events that happen days apart, and a module that
-- conflates them either books income the farmer has not received or loses the
-- harvest entirely when it is eaten at home. So `harvests` records what came
-- off the field, and selling is `record_farm_sale()` from 009 as it already
-- was.
--
-- **Animal events, reusing the shape that works.** 009's `flock_events`
-- handles mortality, weight and vaccination for birds. `herd_events` is the
-- same three things for anything else, plus births — which poultry does not
-- have and every other animal does.
--
-- What is not here: feed rations per species, milk yields per animal,
-- veterinary schedules, and anything that needs a farmer to tell us how they
-- actually work. Those are the next conversation, not a guess.
-- ============================================================

-- ------------------------------------------------------------
-- 1. ANIMALS OF ANY KIND
-- ------------------------------------------------------------

create table if not exists herds (
    id          uuid primary key default gen_random_uuid(),
    org_id      uuid not null references orgs(id) on delete cascade,
    entity_id   uuid references entities(id) on delete set null,

    -- Free text, on purpose. A list of species compiled into this file is a
    -- list that is wrong for the first farmer with guinea fowl, and the same
    -- argument that opened up account names in 007 applies here.
    species     text not null,
    label       text not null,
    breed       text,

    head_count  int not null check (head_count >= 0),
    arrived_on  date not null default current_date,
    closed_on   date,

    -- What this group is for. Drives nothing in the schema and is worth
    -- recording anyway: a dairy herd and a herd being fattened for Tabaski
    -- are managed differently and the farmer knows which is which.
    purpose     text,

    created_at  timestamptz not null default now(),
    created_by  uuid references profiles(id),
    unique (org_id, label)
);

comment on table herds is
    'A group of animals of any species. `flocks` (009) is the poultry-specific ancestor and is left alone: Ignace''s history is in it.';

create index if not exists herds_open on herds (org_id) where closed_on is null;

create table if not exists herd_events (
    id          uuid primary key default gen_random_uuid(),
    org_id      uuid not null references orgs(id) on delete cascade,
    herd_id     uuid not null references herds(id) on delete cascade,

    -- birth is the one 009 has no equivalent for: a flock arrives and never
    -- grows by itself, and a herd does.
    kind        text not null check (kind in
                ('mortality', 'birth', 'weight', 'vaccination', 'treatment', 'sold')),
    occurred_on date not null default current_date,

    -- Head for mortality, birth and sold; kilograms for a weight sample;
    -- ignored for a vaccination.
    quantity    numeric(14,3) not null default 0 check (quantity >= 0),
    note        text,

    created_at  timestamptz not null default now(),
    created_by  uuid references profiles(id),
    device_id   text,
    client_uuid uuid
);

create unique index if not exists herd_events_by_client_uuid
    on herd_events (org_id, client_uuid) where client_uuid is not null;

create index if not exists herd_events_by_date
    on herd_events (org_id, occurred_on desc);

-- ------------------------------------------------------------
-- 2. WHAT GROWS IN THE GROUND
-- ------------------------------------------------------------

create table if not exists plots (
    id         uuid primary key default gen_random_uuid(),
    org_id     uuid not null references orgs(id) on delete cascade,
    entity_id  uuid references entities(id) on delete set null,
    name       text not null,
    area       numeric(12,3),
    -- 'ha' | 'm2' — recorded rather than assumed, because a market gardener
    -- thinks in square metres and a maize farmer in hectares.
    area_unit  text not null default 'ha',
    note       text,
    created_at timestamptz not null default now(),
    created_by uuid references profiles(id),
    unique (org_id, name)
);

-- One planting. The unit of record is a period on a plot, not the plot
-- itself: the same field grows onions from October and maize from June, and
-- "what did this field produce" is unanswerable without a when.
create table if not exists crop_cycles (
    id            uuid primary key default gen_random_uuid(),
    org_id        uuid not null references orgs(id) on delete cascade,
    plot_id       uuid references plots(id) on delete set null,

    crop          text not null,
    variety       text,
    planted_on    date not null default current_date,
    expected_on   date,
    closed_on     date,

    -- What the farmer hopes for, in the unit they will actually harvest in.
    expected_yield numeric(14,3),
    unit          text not null default 'kg',

    note          text,
    created_at    timestamptz not null default now(),
    created_by    uuid references profiles(id)
);

create index if not exists crop_cycles_open
    on crop_cycles (org_id, expected_on) where closed_on is null;

-- What actually came off the field. Separate from selling it, which happens
-- days later and sometimes never — a sack eaten at home is still a harvest,
-- and a module that only counts what was sold cannot tell a farmer their
-- yield.
create table if not exists harvests (
    id            uuid primary key default gen_random_uuid(),
    org_id        uuid not null references orgs(id) on delete cascade,
    crop_cycle_id uuid references crop_cycles(id) on delete set null,

    harvested_on  date not null default current_date,
    quantity      numeric(14,3) not null check (quantity > 0),
    unit          text not null default 'kg',
    -- 'first' | 'second' | 'damaged' — the same grading idea as eggs, and for
    -- the same reason: what is sold at full price and what is not.
    grade         text not null default 'first',
    note          text,

    created_at    timestamptz not null default now(),
    created_by    uuid references profiles(id),
    device_id     text,
    client_uuid   uuid
);

create unique index if not exists harvests_by_client_uuid
    on harvests (org_id, client_uuid) where client_uuid is not null;

create index if not exists harvests_by_date
    on harvests (org_id, harvested_on desc);

-- ------------------------------------------------------------
-- 3. RECORDING
-- ------------------------------------------------------------
-- All idempotent by client_uuid, like every other field-recorded thing in
-- this project: a phone at the far end of a field retries.

create or replace function open_herd(
    p_org_id     uuid,
    p_species    text,
    p_label      text,
    p_head_count int,
    p_breed      text default null,
    p_purpose    text default null,
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
    v_label text := nullif(btrim(coalesce(p_label, '')), '');
begin
    if v_actor is null then
        raise exception 'open_herd() needs a signed-in caller';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record for this business';
    end if;
    if v_label is null then
        raise exception 'A group of animals needs a name';
    end if;
    if p_head_count is null or p_head_count <= 0 then
        raise exception 'How many animals?';
    end if;

    -- Same rule as a flock's batch code: opening a group is one of the two
    -- things on a farm that needs the server, because two phones inventing
    -- the same name would split a season's figures in half.
    select id into v_id from herds
    where org_id = p_org_id and lower(btrim(label)) = lower(v_label);
    if found then
        raise exception 'A group called % already exists', v_label;
    end if;

    insert into herds (org_id, entity_id, species, label, breed, head_count,
                       purpose, arrived_on, created_by)
    values (p_org_id, p_entity_id,
            coalesce(nullif(btrim(coalesce(p_species, '')), ''), 'autre'),
            v_label,
            nullif(btrim(coalesce(p_breed, '')), ''),
            p_head_count,
            nullif(btrim(coalesce(p_purpose, '')), ''),
            coalesce(p_arrived_on, current_date), v_actor)
    returning id into v_id;

    return v_id;
end;
$$;

-- A death, a birth, a weighing, a vaccination. The head count moves for the
-- first two and stays put for the rest.
create or replace function record_herd_event(
    p_org_id      uuid,
    p_herd_id     uuid,
    p_kind        text,
    p_quantity    numeric default 0,
    p_occurred_on date default current_date,
    p_note        text default null,
    p_client_uuid uuid default null,
    p_device_id   text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_org      uuid;
    v_head     int;
    v_existing uuid;
    v_id       uuid;
begin
    if v_actor is null then
        raise exception 'record_herd_event() needs a signed-in caller';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record for this business';
    end if;

    if p_kind not in ('mortality', 'birth', 'weight', 'vaccination',
                      'treatment', 'sold') then
        raise exception 'Unknown event: %', p_kind;
    end if;

    if p_client_uuid is not null then
        select id into v_existing from herd_events
        where org_id = p_org_id and client_uuid = p_client_uuid;
        if found then
            return v_existing;
        end if;
    end if;

    select org_id, head_count into v_org, v_head from herds where id = p_herd_id;
    if v_org is null or v_org <> p_org_id then
        raise exception 'No such group in this business';
    end if;

    -- More animals dead or sold than there are is a typo, and left in it
    -- makes a herd's count negative and every figure after it wrong.
    if p_kind in ('mortality', 'sold') and coalesce(p_quantity, 0) > v_head then
        raise exception
            'There are only % animals in this group', v_head;
    end if;

    insert into herd_events (org_id, herd_id, kind, occurred_on, quantity,
                             note, created_by, device_id, client_uuid)
    values (p_org_id, p_herd_id, p_kind,
            coalesce(p_occurred_on, current_date),
            greatest(coalesce(p_quantity, 0), 0),
            nullif(btrim(coalesce(p_note, '')), ''),
            v_actor, p_device_id, p_client_uuid)
    returning id into v_id;

    if p_kind in ('mortality', 'sold') then
        update herds set head_count = head_count - coalesce(p_quantity, 0)
        where id = p_herd_id;
    elsif p_kind = 'birth' then
        update herds set head_count = head_count + coalesce(p_quantity, 0)
        where id = p_herd_id;
    end if;

    return v_id;
end;
$$;

create or replace function open_crop_cycle(
    p_org_id      uuid,
    p_crop        text,
    p_plot_name   text default null,
    p_variety     text default null,
    p_planted_on  date default current_date,
    p_expected_on date default null,
    p_expected_yield numeric default null,
    p_unit        text default 'kg',
    p_entity_id   uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
    v_crop  text := nullif(btrim(coalesce(p_crop, '')), '');
    v_plot  text := nullif(btrim(coalesce(p_plot_name, '')), '');
    v_plot_id uuid;
    v_id    uuid;
begin
    if v_actor is null then
        raise exception 'open_crop_cycle() needs a signed-in caller';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record for this business';
    end if;
    if v_crop is null then
        raise exception 'What is being planted?';
    end if;

    -- The plot is found or made from its name, the same bargain
    -- `ensure_account()` makes: a farmer types "Bas-fond 2" and gets the same
    -- plot every time without having had to define it first.
    if v_plot is not null then
        select id into v_plot_id from plots
        where org_id = p_org_id and lower(btrim(name)) = lower(v_plot);
        if v_plot_id is null then
            insert into plots (org_id, entity_id, name, created_by)
            values (p_org_id, p_entity_id, v_plot, v_actor)
            returning id into v_plot_id;
        end if;
    end if;

    insert into crop_cycles (org_id, plot_id, crop, variety, planted_on,
                             expected_on, expected_yield, unit, created_by)
    values (p_org_id, v_plot_id, v_crop,
            nullif(btrim(coalesce(p_variety, '')), ''),
            coalesce(p_planted_on, current_date),
            p_expected_on, p_expected_yield,
            coalesce(nullif(btrim(coalesce(p_unit, '')), ''), 'kg'),
            v_actor)
    returning id into v_id;

    return v_id;
end;
$$;

create or replace function record_harvest(
    p_org_id      uuid,
    p_crop_cycle_id uuid,
    p_quantity    numeric,
    p_unit        text default null,
    p_grade       text default 'first',
    p_harvested_on date default current_date,
    p_note        text default null,
    p_client_uuid uuid default null,
    p_device_id   text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_org      uuid;
    v_unit     text;
    v_existing uuid;
    v_id       uuid;
begin
    if v_actor is null then
        raise exception 'record_harvest() needs a signed-in caller';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record for this business';
    end if;
    if p_quantity is null or p_quantity <= 0 then
        raise exception 'How much was harvested?';
    end if;

    if p_client_uuid is not null then
        select id into v_existing from harvests
        where org_id = p_org_id and client_uuid = p_client_uuid;
        if found then
            return v_existing;
        end if;
    end if;

    select org_id, unit into v_org, v_unit from crop_cycles
    where id = p_crop_cycle_id;
    if v_org is null or v_org <> p_org_id then
        raise exception 'No such planting in this business';
    end if;

    -- No ledger entry. Bringing a crop in is not earning money — it is earning
    -- money later, or eating it — and booking income here would inflate the
    -- income statement by every sack that never reached a market. Selling it
    -- goes through record_farm_sale() as it already did.
    insert into harvests (org_id, crop_cycle_id, harvested_on, quantity, unit,
                          grade, note, created_by, device_id, client_uuid)
    values (p_org_id, p_crop_cycle_id,
            coalesce(p_harvested_on, current_date),
            p_quantity,
            coalesce(nullif(btrim(coalesce(p_unit, '')), ''), v_unit, 'kg'),
            coalesce(nullif(btrim(coalesce(p_grade, '')), ''), 'first'),
            nullif(btrim(coalesce(p_note, '')), ''),
            v_actor, p_device_id, p_client_uuid)
    returning id into v_id;

    return v_id;
end;
$$;

-- ------------------------------------------------------------
-- 4. READING IT BACK
-- ------------------------------------------------------------

create or replace function herd_status(p_org_id uuid, p_include_closed boolean default false)
returns table (
    id          uuid,
    species     text,
    label       text,
    breed       text,
    purpose     text,
    head_count  int,
    arrived_on  date,
    closed_on   date,
    losses      numeric,
    births      numeric,
    last_event  date
)
language sql
stable
security invoker
set search_path = public
as $$
    select h.id, h.species, h.label, h.breed, h.purpose, h.head_count,
           h.arrived_on, h.closed_on,
           coalesce((select sum(e.quantity) from herd_events e
                     where e.herd_id = h.id and e.kind = 'mortality'), 0),
           coalesce((select sum(e.quantity) from herd_events e
                     where e.herd_id = h.id and e.kind = 'birth'), 0),
           (select max(e.occurred_on) from herd_events e where e.herd_id = h.id)
    from herds h
    where h.org_id = p_org_id
      and (coalesce(p_include_closed, false) or h.closed_on is null)
    order by h.closed_on nulls first, h.label;
$$;

create or replace function crop_status(p_org_id uuid, p_include_closed boolean default false)
returns table (
    id             uuid,
    crop           text,
    variety        text,
    plot_name      text,
    planted_on     date,
    expected_on    date,
    closed_on      date,
    expected_yield numeric,
    unit           text,
    harvested      numeric,
    days_to_harvest int
)
language sql
stable
security invoker
set search_path = public
as $$
    select c.id, c.crop, c.variety, p.name, c.planted_on, c.expected_on,
           c.closed_on, c.expected_yield, c.unit,
           coalesce((select sum(h.quantity) from harvests h
                     where h.crop_cycle_id = c.id), 0),
           case when c.expected_on is null then null
                else (c.expected_on - current_date) end
    from crop_cycles c
    left join plots p on p.id = c.plot_id
    where c.org_id = p_org_id
      and (coalesce(p_include_closed, false) or c.closed_on is null)
    order by c.closed_on nulls first, c.expected_on nulls last, c.crop;
$$;

-- What this farm is, as a farm rather than as a set of tables. The home
-- screen asks this first and shows whichever sections have anything in them,
-- so a poultry farm still opens on birds and eggs and a market gardener does
-- not have to look at an empty flock panel.
create or replace function farm_profile_summary(p_org_id uuid)
returns table (
    flocks        int,
    birds         int,
    herds         int,
    animals       int,
    crop_cycles   int,
    plots         int,
    eggs_today    int,
    harvest_7days numeric
)
language sql
stable
security invoker
set search_path = public
as $$
    select
        (select count(*)::int from flocks f
          where f.org_id = p_org_id and f.closed_on is null),
        (select coalesce(sum(f.bird_count), 0)::int from flocks f
          where f.org_id = p_org_id and f.closed_on is null),
        (select count(*)::int from herds h
          where h.org_id = p_org_id and h.closed_on is null),
        (select coalesce(sum(h.head_count), 0)::int from herds h
          where h.org_id = p_org_id and h.closed_on is null),
        (select count(*)::int from crop_cycles c
          where c.org_id = p_org_id and c.closed_on is null),
        (select count(*)::int from plots p where p.org_id = p_org_id),
        (select coalesce(sum(e.egg_count), 0)::int from egg_production e
          where e.org_id = p_org_id and e.produced_on = current_date),
        (select coalesce(sum(h.quantity), 0) from harvests h
          where h.org_id = p_org_id
            and h.harvested_on >= current_date - 7);
$$;

-- ------------------------------------------------------------
-- 5. RLS
-- ------------------------------------------------------------
-- The same shape 009 gives its own tables: counts are readable to members,
-- the events behind them need full visibility, and writing needs a
-- non-observer.

alter table herds        enable row level security;
alter table herd_events  enable row level security;
alter table plots        enable row level security;
alter table crop_cycles  enable row level security;
alter table harvests     enable row level security;

drop policy if exists "herds readable within org" on herds;
create policy "herds readable within org"
on herds for select using (is_org_member(org_id));

drop policy if exists "herds managed by non-observers" on herds;
create policy "herds managed by non-observers"
on herds for insert with check (can_write_org(org_id));

drop policy if exists "herds amended by non-observers" on herds;
create policy "herds amended by non-observers"
on herds for update using (can_write_org(org_id)) with check (can_write_org(org_id));

drop policy if exists "herd events readable with full visibility" on herd_events;
create policy "herd events readable with full visibility"
on herd_events for select using (has_full_visibility(org_id));

drop policy if exists "herd events written by non-observers" on herd_events;
create policy "herd events written by non-observers"
on herd_events for insert with check (can_write_org(org_id));

drop policy if exists "plots readable within org" on plots;
create policy "plots readable within org"
on plots for select using (is_org_member(org_id));

drop policy if exists "plots managed by non-observers" on plots;
create policy "plots managed by non-observers"
on plots for insert with check (can_write_org(org_id));

drop policy if exists "plots amended by non-observers" on plots;
create policy "plots amended by non-observers"
on plots for update using (can_write_org(org_id)) with check (can_write_org(org_id));

drop policy if exists "crop cycles readable within org" on crop_cycles;
create policy "crop cycles readable within org"
on crop_cycles for select using (is_org_member(org_id));

drop policy if exists "crop cycles managed by non-observers" on crop_cycles;
create policy "crop cycles managed by non-observers"
on crop_cycles for insert with check (can_write_org(org_id));

drop policy if exists "crop cycles amended by non-observers" on crop_cycles;
create policy "crop cycles amended by non-observers"
on crop_cycles for update using (can_write_org(org_id)) with check (can_write_org(org_id));

drop policy if exists "harvests readable with full visibility" on harvests;
create policy "harvests readable with full visibility"
on harvests for select using (has_full_visibility(org_id));

drop policy if exists "harvests written by non-observers" on harvests;
create policy "harvests written by non-observers"
on harvests for insert with check (can_write_org(org_id));

-- ------------------------------------------------------------
-- 6. A FARM'S CHART, WIDENED
-- ------------------------------------------------------------
-- 009 seeds "Ventes d'œufs" and "Ventes de volailles" and stops. A farm with
-- goats and onions has nowhere sensible to post either, so it posts to
-- "Autres ventes" and the income statement says nothing useful.
create or replace function seed_farm_accounts(p_org_id uuid)
returns void
language plpgsql
as $$
begin
    insert into accounts (org_id, code, name, type) values
        (p_org_id, '1000', 'Cash on Hand',        'asset'),
        (p_org_id, '1010', 'Bank Account',        'asset'),
        (p_org_id, '1020', 'Mobile Money',        'asset'),
        (p_org_id, '1300', 'Créances clients',    'asset'),
        (p_org_id, '4100', 'Ventes d''œufs',      'income'),
        (p_org_id, '4110', 'Ventes de volailles', 'income'),
        (p_org_id, '4130', 'Ventes de bétail',    'income'),
        (p_org_id, '4140', 'Ventes de récoltes',  'income'),
        (p_org_id, '4150', 'Ventes de lait',      'income'),
        (p_org_id, '4120', 'Autres ventes',       'income'),
        (p_org_id, '5100', 'Aliment',             'expense'),
        (p_org_id, '5110', 'Vétérinaire',         'expense'),
        (p_org_id, '5120', 'Main-d''œuvre',       'expense'),
        (p_org_id, '5140', 'Semences',            'expense'),
        (p_org_id, '5150', 'Engrais et traitements', 'expense'),
        (p_org_id, '5130', 'Fournitures ferme',   'expense')
    on conflict (org_id, code) do nothing;
end;
$$;

-- Existing farms get the new accounts too, rather than only farms created
-- from now on. Idempotent, so a farm that already has them is untouched.
do $$
declare
    v_org uuid;
begin
    for v_org in select id from orgs where profile = 'farm' loop
        perform seed_farm_accounts(v_org);
    end loop;
end $$;

-- ------------------------------------------------------------
-- 7. GRANTS
-- ------------------------------------------------------------
revoke execute on function open_herd(uuid, text, text, int, text, text, uuid, date) from public;
revoke execute on function record_herd_event(uuid, uuid, text, numeric, date, text, uuid, text) from public;
revoke execute on function open_crop_cycle(uuid, text, text, text, date, date, numeric, text, uuid) from public;
revoke execute on function record_harvest(uuid, uuid, numeric, text, text, date, text, uuid, text) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function open_herd(uuid, text, text, int, text, text, uuid, date) to authenticated;
        grant execute on function record_herd_event(uuid, uuid, text, numeric, date, text, uuid, text) to authenticated;
        grant execute on function open_crop_cycle(uuid, text, text, text, date, date, numeric, text, uuid) to authenticated;
        grant execute on function record_harvest(uuid, uuid, numeric, text, text, date, text, uuid, text) to authenticated;
        grant execute on function herd_status(uuid, boolean) to authenticated;
        grant execute on function crop_status(uuid, boolean) to authenticated;
        grant execute on function farm_profile_summary(uuid) to authenticated;
        grant select, insert, update on herds to authenticated;
        grant select, insert on herd_events to authenticated;
        grant select, insert, update on plots to authenticated;
        grant select, insert, update on crop_cycles to authenticated;
        grant select, insert on harvests to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
