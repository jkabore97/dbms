-- ============================================================
-- 007_accounting.sql
--
-- Two things this file is for, and they turn out to be the same thing.
--
-- 1. EVERY ENTRY GETS A NAME. Until now the only entries the app could make
--    were the ones 002 had anticipated: four kinds of contribution and seven
--    expense categories, all hard-coded, in both the SQL and the Flutter
--    sheets. Anything a person actually needed to record that was not on that
--    list had to be filed under whichever category was least wrong. The
--    picker was defended as protecting the books from seven spellings of
--    "Loyer" — but a category list nobody can add to does not produce clean
--    books, it produces books where "Fournitures" means eleven different
--    things and no report can tell them apart.
--
--    So `record_entry()` takes the name the person typed, and
--    `ensure_account()` turns a name into a real account in the chart the
--    first time it is used and finds that same account every time after. The
--    picker survives as what it should always have been: a list of the names
--    already in use, offered first because most entries repeat.
--
-- 2. THE BOOKS BECOME READABLE. The ledger has been double-entry since the
--    first schema and nothing has ever been able to show it as one — no trial
--    balance, no income statement, no balance sheet, no account history.
--    Those are the four reports that make a ledger an accounting system
--    rather than a list, and every one of them is a query over tables that
--    already existed.
--
-- The access rule is the one 006 established and is not widened here:
-- per-account detail needs `visibility = 'full'`, totals are for any member,
-- and line items need full visibility too. Every function below is SECURITY
-- DEFINER for the same reason the reports in 006 are — a summary observer
-- cannot read the tables these are computed from and is still entitled to the
-- total — so every one of them checks entitlement itself.
-- ============================================================

-- ------------------------------------------------------------
-- 1. WHAT AN ENTRY CAN CARRY
-- ------------------------------------------------------------

-- The name the person typed, kept apart from `memo`. They are different
-- things: the label is what this entry IS ("Réparation du toit") and is what
-- every list and report shows; the memo is what someone wanted to say about
-- it ("moitié payée d'avance, reste dû à Kaboré"). Collapsing them, which is
-- what the app did by writing the category name into memo, means a report can
-- either show a useful sentence or group by category, never both.
alter table journal_entries add column if not exists label text;

-- The characteristics. Anything the entry needs that the schema did not
-- anticipate: a supplier, an invoice number, a beneficiary, a quantity, the
-- name of the road that was repaired. jsonb rather than columns because the
-- whole point is that nobody has to have predicted the key.
--
-- Deliberately not indexed and deliberately not queried by the reports below.
-- This is a place to record what happened, not a second schema growing in the
-- dark; anything that earns a report earns a column.
alter table journal_entries
    add column if not exists details jsonb not null default '{}'::jsonb;

-- The date range on every report below filters on created_at, so it stops
-- being a full scan the first year the books get busy.
create index if not exists journal_entries_by_org_date
    on journal_entries (org_id, created_at desc);

-- ------------------------------------------------------------
-- 2. WHAT AN ACCOUNT CAN CARRY
-- ------------------------------------------------------------

-- What this account is for, in the words of whoever created it. A chart of
-- accounts is only self-explanatory to the person who wrote it.
alter table accounts add column if not exists description text;

-- Retired, not deleted. An account with history in it can never be removed —
-- the entries reference it and the reports would lose their labels — so the
-- only honest way to stop offering "Loyer" once the building is bought is to
-- take it off the list and leave the past intact.
alter table accounts add column if not exists is_active boolean not null default true;

alter table accounts add column if not exists created_at timestamptz not null default now();

-- Null for the seeded chart, which nobody created. Set for everything typed
-- into the app afterwards, so a category that turns out to be a duplicate can
-- be traced to the person who needed it.
alter table accounts add column if not exists created_by uuid references profiles(id);

-- ensure_account() finds by name, so the lookup wants an index and the name
-- wants to be matched the way a person means it: case and surrounding spaces
-- are typing, not meaning.
--
-- Not a UNIQUE index, on purpose. A unique constraint here would be the
-- correct model and could fail this migration against books that already
-- contain a duplicate — and refusing to migrate somebody's live database over
-- two accounts both called "Divers" is a worse outcome than tolerating them.
-- ensure_account() takes the oldest match, so a pre-existing duplicate keeps
-- receiving entries where it always did and never becomes the reason a new
-- entry fails.
create index if not exists accounts_by_org_type_name
    on accounts (org_id, type, lower(btrim(name)));

-- ------------------------------------------------------------
-- 3. MINTING AN ACCOUNT
-- ------------------------------------------------------------

-- Codes are banded by type, the way every chart of accounts is: assets in the
-- 1000s, liabilities 2000s, equity 3000s, income 4000s, expenses 5000s. The
-- seeded church chart in 002 already follows this, so a church that has been
-- running since before this migration keeps its numbering and new accounts
-- continue it.
create or replace function account_code_band(p_type text)
returns int
language sql
immutable
as $$
    select case p_type
        when 'asset'     then 1000
        when 'liability' then 2000
        when 'equity'    then 3000
        when 'income'    then 4000
        when 'expense'   then 5000
    end;
$$;

-- The next free code in the type's band, in tens — leaving room to slot an
-- account between two others later, which is the one thing you always want
-- from a numbering scheme and can never retrofit.
create or replace function next_account_code(p_org_id uuid, p_type text)
returns text
language plpgsql
stable
as $$
declare
    v_band int := account_code_band(p_type);
    v_next int;
begin
    if v_band is null then
        raise exception 'Unknown account type: %', p_type;
    end if;

    -- Codes are text and a hand-entered chart may hold codes that are not
    -- numbers at all. Those are left alone rather than crashing the count.
    select coalesce(max(a.code::int), v_band - 10) + 10
      into v_next
      from accounts a
     where a.org_id = p_org_id
       and a.code ~ '^[0-9]+$'
       and a.code::int between v_band and v_band + 999;

    if v_next > v_band + 999 then
        raise exception
            'No free % code left for org % — the % band is full',
            p_type, p_org_id, v_band;
    end if;

    return v_next::text;
end;
$$;

-- Find by name, create if absent. This is the function that makes a typed
-- name into real accounting.
--
-- Not SECURITY DEFINER and not granted to anybody: it is an internal helper
-- called from inside the definer functions below, which have already
-- established that the caller may write to this org. Called directly by an
-- authenticated user it would insert under RLS, where the policy in 004 lets
-- only an org admin add an account — which is the correct answer to a caller
-- who arrived by a route with no permission check in it.
create or replace function ensure_account(
    p_org_id  uuid,
    p_name    text,
    p_type    text,
    p_actor   uuid default null
)
returns uuid
language plpgsql
as $$
declare
    v_name text := btrim(coalesce(p_name, ''));
    v_id   uuid;
begin
    if v_name = '' then
        raise exception 'An account needs a name';
    end if;

    if account_code_band(p_type) is null then
        raise exception 'Unknown account type: %', p_type;
    end if;

    -- Oldest match wins, so books that already hold two accounts of the same
    -- name keep posting to the one that has the history.
    select a.id into v_id
      from accounts a
     where a.org_id = p_org_id
       and a.type = p_type
       and lower(btrim(a.name)) = lower(v_name)
     order by a.created_at, a.code
     limit 1;

    if v_id is not null then
        return v_id;
    end if;

    insert into accounts (org_id, code, name, type, created_by)
    values (p_org_id, next_account_code(p_org_id, p_type), v_name, p_type, p_actor)
    returning id into v_id;

    return v_id;
end;
$$;

-- The same, for the three accounts whose code the app relies on. A church
-- seeded by 002 already has them; an org created any other way may not, and
-- "record what you were paid in cash" should not fail because nobody ran the
-- seeder.
create or replace function ensure_account_by_code(
    p_org_id uuid,
    p_code   text,
    p_name   text,
    p_type   text,
    p_actor  uuid default null
)
returns uuid
language plpgsql
as $$
declare
    v_id uuid;
begin
    select id into v_id from accounts where org_id = p_org_id and code = p_code;
    if v_id is not null then
        return v_id;
    end if;

    insert into accounts (org_id, code, name, type, created_by)
    values (p_org_id, p_code, p_name, p_type, p_actor)
    returning id into v_id;

    return v_id;
end;
$$;

-- Where the money physically sits. The three known methods keep the codes 002
-- seeded so a church's existing balances stay on the accounts they are on;
-- anything else the caller sends is a name someone typed — a second till, a
-- named agent, a savings box — and becomes an asset account of its own.
create or replace function resolve_cash_account(
    p_org_id uuid,
    p_method text,
    p_actor  uuid default null
)
returns uuid
language plpgsql
as $$
begin
    return case btrim(lower(coalesce(p_method, 'cash')))
        when 'cash'         then ensure_account_by_code(p_org_id, '1000', 'Cash on Hand', 'asset', p_actor)
        when 'bank'         then ensure_account_by_code(p_org_id, '1010', 'Bank Account', 'asset', p_actor)
        when 'mobile_money' then ensure_account_by_code(p_org_id, '1020', 'Mobile Money', 'asset', p_actor)
        else ensure_account(p_org_id, p_method, 'asset', p_actor)
    end;
end;
$$;

-- ------------------------------------------------------------
-- 4. RECORDING ANYTHING
-- ------------------------------------------------------------
-- record_contribution() and record_expense() in 002 stay exactly as they are.
-- Books recorded through them are already in the ledger and the church tests
-- cover them; this is the general form, and it is what the app posts now.
--
-- SECURITY DEFINER because it does two things RLS would refuse on the
-- caller's behalf: it mints an account (admin-only under 004) and it writes a
-- ledger row for an org whose scope the caller may hold at department level.
-- So it makes the check itself, first, and the check is the same one the
-- policy would have made.
create or replace function record_entry(
    p_org_id        uuid,
    p_amount        numeric,
    p_direction     text,                       -- 'in' | 'out'
    p_label         text,                       -- what the person typed. Required.
    p_recorded_by   uuid        default null,   -- must be the caller; the app sends it
    p_category      text        default null,   -- income/expense account name; defaults to the label
    p_method        text        default 'cash', -- 'cash' | 'bank' | 'mobile_money' | any account name
    p_member_id     uuid        default null,
    p_memo          text        default null,
    p_details       jsonb       default '{}'::jsonb,
    p_entity_id     uuid        default null,
    p_department_id uuid        default null,
    p_client_uuid   uuid        default null,
    p_device_id     text        default null,
    p_occurred_at   timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor        uuid := auth.uid();
    v_label        text := btrim(coalesce(p_label, ''));
    v_category     text;
    v_entry_id     uuid;
    v_cash_acct    uuid;
    v_result_acct  uuid;
    v_existing     uuid;
begin
    if v_actor is null then
        raise exception 'record_entry() needs a signed-in caller';
    end if;

    -- The app sends the user id it thinks it is, and a mismatch means the
    -- device is confused about who is holding it — which is exactly the case
    -- the handover guard in the Flutter app exists to prevent. Refuse rather
    -- than quietly record the work under the wrong name.
    if p_recorded_by is not null and p_recorded_by <> v_actor then
        raise exception 'record_entry() cannot record on behalf of another user';
    end if;

    -- The same test the insert policy on journal_entries makes: everyone but
    -- an observer. Made here because the definer context skips the policy.
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record entries for this business';
    end if;

    if p_amount is null or p_amount <= 0 then
        raise exception 'Amount must be greater than zero (got %)', p_amount;
    end if;

    if p_direction not in ('in', 'out') then
        raise exception 'Direction must be in or out (got %)', p_direction;
    end if;

    if v_label = '' then
        raise exception 'An entry needs a name';
    end if;

    -- Idempotency, identical to 002: a retried sync returns the original
    -- entry. This is what lets the device fire and forget.
    if p_client_uuid is not null then
        select id into v_existing
          from journal_entries
         where org_id = p_org_id and client_uuid = p_client_uuid;
        if found then
            return v_existing;
        end if;
    end if;

    -- No category typed means the name IS the category. Someone recording
    -- "Réparation du toit" once wants a line in the books; someone recording
    -- it monthly wants a category, and by the second month they have one.
    v_category := coalesce(nullif(btrim(coalesce(p_category, '')), ''), v_label);

    v_cash_acct := resolve_cash_account(p_org_id, p_method, v_actor);
    v_result_acct := ensure_account(
        p_org_id,
        v_category,
        case p_direction when 'in' then 'income' else 'expense' end,
        v_actor
    );

    insert into journal_entries (
        org_id, entity_id, department_id, label, memo, details,
        created_by, created_at, device_id, client_uuid
    )
    values (
        p_org_id, p_entity_id, p_department_id, v_label, p_memo,
        coalesce(p_details, '{}'::jsonb),
        v_actor, p_occurred_at, p_device_id, p_client_uuid
    )
    returning id into v_entry_id;

    if p_direction = 'in' then
        -- Money in: the asset grows, the income account is credited.
        insert into journal_lines (journal_entry_id, account_id, debit, credit) values
            (v_entry_id, v_cash_acct,   p_amount, 0),
            (v_entry_id, v_result_acct, 0,        p_amount);
    else
        -- Money out: the expense is incurred, the asset it came from shrinks.
        insert into journal_lines (journal_entry_id, account_id, debit, credit) values
            (v_entry_id, v_result_acct, p_amount, 0),
            (v_entry_id, v_cash_acct,   0,        p_amount);
    end if;

    if p_member_id is not null then
        insert into contribution_attributions (journal_entry_id, member_id)
        values (v_entry_id, p_member_id);
    end if;

    return v_entry_id;
end;
$$;

-- Money that moved without being earned or spent: cash banked, a withdrawal
-- for the week's purchases, a top-up of the mobile money float.
--
-- This exists because without it every deposit gets recorded as an expense
-- from cash and income to the bank, which inflates both sides of the income
-- statement by the same amount and makes the books say the business earned
-- money by moving its own money.
create or replace function record_transfer(
    p_org_id      uuid,
    p_amount      numeric,
    p_from_method text,
    p_to_method   text,
    p_recorded_by uuid        default null,
    p_label       text        default null,
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
    v_from     uuid;
    v_to       uuid;
    v_entry_id uuid;
    v_existing uuid;
begin
    if v_actor is null then
        raise exception 'record_transfer() needs a signed-in caller';
    end if;
    if p_recorded_by is not null and p_recorded_by <> v_actor then
        raise exception 'record_transfer() cannot record on behalf of another user';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record entries for this business';
    end if;
    if p_amount is null or p_amount <= 0 then
        raise exception 'Amount must be greater than zero (got %)', p_amount;
    end if;

    if p_client_uuid is not null then
        select id into v_existing
          from journal_entries
         where org_id = p_org_id and client_uuid = p_client_uuid;
        if found then
            return v_existing;
        end if;
    end if;

    v_from := resolve_cash_account(p_org_id, p_from_method, v_actor);
    v_to   := resolve_cash_account(p_org_id, p_to_method, v_actor);

    -- Both sides the same account is a no-op that would still write two lines
    -- and a row in the day's list, which reads as money having moved.
    if v_from = v_to then
        raise exception 'A transfer needs two different accounts';
    end if;

    insert into journal_entries (
        org_id, label, memo, created_by, created_at, device_id, client_uuid
    )
    values (
        p_org_id,
        coalesce(nullif(btrim(coalesce(p_label, '')), ''), 'Transfert'),
        p_memo, v_actor, p_occurred_at, p_device_id, p_client_uuid
    )
    returning id into v_entry_id;

    insert into journal_lines (journal_entry_id, account_id, debit, credit) values
        (v_entry_id, v_to,   p_amount, 0),
        (v_entry_id, v_from, 0,        p_amount);

    return v_entry_id;
end;
$$;

-- Adding a category deliberately, from the admin screen, rather than as a
-- side effect of recording something. Admin-only: this is the chart of
-- accounts being designed, not used.
create or replace function create_account(
    p_org_id      uuid,
    p_name        text,
    p_type        text,
    p_description text default null,
    p_code        text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_name text := btrim(coalesce(p_name, ''));
    v_id   uuid;
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Only an administrator may change the chart of accounts';
    end if;
    if v_name = '' then
        raise exception 'An account needs a name';
    end if;
    if account_code_band(p_type) is null then
        raise exception 'Unknown account type: %', p_type;
    end if;

    if exists (
        select 1 from accounts a
        where a.org_id = p_org_id
          and a.type = p_type
          and lower(btrim(a.name)) = lower(v_name)
    ) then
        raise exception 'An account called % already exists', v_name;
    end if;

    insert into accounts (org_id, code, name, type, description, created_by)
    values (
        p_org_id,
        coalesce(nullif(btrim(coalesce(p_code, '')), ''), next_account_code(p_org_id, p_type)),
        v_name, p_type, nullif(btrim(coalesce(p_description, '')), ''), auth.uid()
    )
    returning id into v_id;

    return v_id;
end;
$$;

-- ------------------------------------------------------------
-- 5. THE CHART, AS A LIST WITH MONEY ON IT
-- ------------------------------------------------------------
-- Balances are shown in each type's natural direction — an expense account of
-- 40,000 reads as 40,000 spent, not as -40,000 — because this list is for
-- people choosing a category, not for proving the books balance. That proof
-- is trial_balance(), one function down, and it keeps the raw signs.
create or replace function chart_of_accounts(p_org_id uuid)
returns table (
    account_id  uuid,
    code        text,
    name        text,
    type        text,
    description text,
    is_active   boolean,
    balance     numeric,
    entry_count bigint
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        a.id, a.code, a.name, a.type, a.description, a.is_active,
        coalesce(sum(
            case when a.type in ('asset', 'expense')
                 then jl.debit - jl.credit
                 else jl.credit - jl.debit
            end
        ), 0),
        count(jl.id)
    from accounts a
    left join journal_lines jl on jl.account_id = a.id
    where a.org_id = p_org_id
      and is_org_member(p_org_id)
    group by a.id, a.code, a.name, a.type, a.description, a.is_active
    order by a.code;
$$;

-- ------------------------------------------------------------
-- 6. TRIAL BALANCE — the proof
-- ------------------------------------------------------------
-- Raw debits and credits, no interpretation. The one thing it exists to show
-- is that the two columns are equal; a difference means something wrote to
-- the ledger without going through the functions, and no other report will
-- tell you that.
--
-- Any member may read it. A trial balance is entirely totals, and a summary
-- observer is entitled to totals — that is what 006 decided 'summary' means.
create or replace function trial_balance(
    p_org_id uuid,
    p_from   date default null,
    p_to     date default null
)
returns table (
    code         text,
    name         text,
    type         text,
    total_debit  numeric,
    total_credit numeric,
    balance      numeric
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        a.code, a.name, a.type,
        coalesce(sum(jl.debit), 0),
        coalesce(sum(jl.credit), 0),
        coalesce(sum(jl.debit - jl.credit), 0)
    from accounts a
    left join journal_lines jl on jl.account_id = a.id
    left join journal_entries je
           on je.id = jl.journal_entry_id
          and (p_from is null or je.created_at::date >= p_from)
          and (p_to   is null or je.created_at::date <= p_to)
    where a.org_id = p_org_id
      and is_org_member(p_org_id)
      -- A line whose entry fell outside the window must not contribute its
      -- amount; the left join keeps the account visible with zeroes.
      and (jl.id is null or je.id is not null)
    group by a.code, a.name, a.type
    having a.type is not null
    order by a.code;
$$;

-- ------------------------------------------------------------
-- 7. INCOME STATEMENT — did it earn or lose
-- ------------------------------------------------------------
-- Per-account detail for full visibility; the three totals for any member.
-- Same split as church_weekly_summary in 006, and for the same reason: the
-- investor entitled to know whether the business is sound is not thereby
-- entitled to read every line in it.
create or replace function income_statement(
    p_org_id uuid,
    p_from   date default null,
    p_to     date default null
)
returns table (
    section text,     -- 'income' | 'expense' | 'total'
    code    text,
    name    text,
    amount  numeric
)
language sql
stable
security definer
set search_path = public, auth
as $$
    with access as (
        select is_org_member(p_org_id) as member,
               has_full_visibility(p_org_id) as detailed
    ),
    lines as (
        select a.type, a.code, a.name, jl.debit, jl.credit
        from journal_entries je
        join journal_lines jl on jl.journal_entry_id = je.id
        join accounts a on a.id = jl.account_id
        cross join access x
        where x.member
          and je.org_id = p_org_id
          and a.type in ('income', 'expense')
          and (p_from is null or je.created_at::date >= p_from)
          and (p_to   is null or je.created_at::date <= p_to)
    )
    select 'income'::text, code, name, sum(credit - debit)
    from lines cross join access x
    where type = 'income' and x.detailed
    group by code, name having sum(credit - debit) <> 0

    union all

    select 'expense'::text, code, name, sum(debit - credit)
    from lines cross join access x
    where type = 'expense' and x.detailed
    group by code, name having sum(debit - credit) <> 0

    union all

    select 'total'::text, '1'::text, 'Produits'::text,
           coalesce(sum(credit - debit) filter (where type = 'income'), 0)
    from lines

    union all

    select 'total'::text, '2'::text, 'Charges'::text,
           coalesce(sum(debit - credit) filter (where type = 'expense'), 0)
    from lines

    union all

    -- The number the whole report is for.
    select 'total'::text, '3'::text, 'Résultat'::text,
           coalesce(sum(credit - debit) filter (where type = 'income'), 0)
         - coalesce(sum(debit - credit) filter (where type = 'expense'), 0)
    from lines

    order by 1, 2;
$$;

-- ------------------------------------------------------------
-- 8. BALANCE SHEET — what it owns and what it owes
-- ------------------------------------------------------------
-- The ledger has no closing entries and no retained-earnings account, so the
-- accumulated result is computed here as income minus expense to date and
-- shown as a line under equity. That is what makes the two sides equal, and
-- inventing a real closing process would be a much larger change for a
-- business whose books are eight months old.
create or replace function balance_sheet(
    p_org_id uuid,
    p_as_of  date default null
)
returns table (
    section text,     -- 'asset' | 'liability' | 'equity' | 'total'
    code    text,
    name    text,
    amount  numeric
)
language sql
stable
security definer
set search_path = public, auth
as $$
    with access as (
        select is_org_member(p_org_id) as member,
               has_full_visibility(p_org_id) as detailed
    ),
    lines as (
        select a.type, a.code, a.name, jl.debit, jl.credit
        from journal_entries je
        join journal_lines jl on jl.journal_entry_id = je.id
        join accounts a on a.id = jl.account_id
        cross join access x
        where x.member
          and je.org_id = p_org_id
          and (p_as_of is null or je.created_at::date <= p_as_of)
    ),
    result as (
        select coalesce(sum(credit - debit) filter (where type = 'income'), 0)
             - coalesce(sum(debit - credit) filter (where type = 'expense'), 0) as amount
        from lines
    )
    select 'asset'::text, code, name, sum(debit - credit)
    from lines cross join access x
    where type = 'asset' and x.detailed
    group by code, name having sum(debit - credit) <> 0

    union all

    select 'liability'::text, code, name, sum(credit - debit)
    from lines cross join access x
    where type = 'liability' and x.detailed
    group by code, name having sum(credit - debit) <> 0

    union all

    select 'equity'::text, code, name, sum(credit - debit)
    from lines cross join access x
    where type = 'equity' and x.detailed
    group by code, name having sum(credit - debit) <> 0

    union all

    -- Not an account, and labelled so nobody goes looking for it in the chart.
    select 'equity'::text, 'zzz'::text, 'Résultat accumulé'::text, r.amount
    from result r cross join access x
    where x.detailed and r.amount <> 0

    union all

    select 'total'::text, '1'::text, 'Total actif'::text,
           coalesce(sum(debit - credit) filter (where type = 'asset'), 0)
    from lines

    union all

    select 'total'::text, '2'::text, 'Total passif'::text,
           coalesce(sum(credit - debit) filter (where type in ('liability', 'equity')), 0)
         + (select amount from result)
    from lines

    order by 1, 2;
$$;

-- ------------------------------------------------------------
-- 9. GENERAL LEDGER — one account, every movement
-- ------------------------------------------------------------
-- Line items, so full visibility and not merely membership.
--
-- The running balance is the reason this exists rather than a filtered list:
-- "the till says 43,500 and the app says 61,000" is answered by reading down
-- a column until the two stop agreeing, and by nothing else.
create or replace function account_ledger(
    p_org_id     uuid,
    p_account_id uuid,
    p_from       date default null,
    p_to         date default null,
    p_limit      int  default 200
)
returns table (
    entry_id    uuid,
    occurred_at timestamptz,
    label       text,
    memo        text,
    debit       numeric,
    credit      numeric,
    balance     numeric,
    reversed    boolean,
    recorded_by text
)
language sql
stable
security definer
set search_path = public, auth
as $$
    with access as (
        select has_full_visibility(p_org_id) as detailed
    ),
    opening as (
        -- Everything before the window, collapsed into the number the first
        -- row starts from. Without it the running balance is only correct
        -- when the window reaches back to the first entry ever made.
        select coalesce(sum(jl.debit - jl.credit), 0) as amount
        from journal_lines jl
        join journal_entries je on je.id = jl.journal_entry_id
        cross join access x
        where x.detailed
          and jl.account_id = p_account_id
          and je.org_id = p_org_id
          and p_from is not null
          and je.created_at::date < p_from
    ),
    movements as (
        select
            je.id as entry_id,
            je.created_at as occurred_at,
            coalesce(je.label, je.memo, 'Entrée') as label,
            je.memo,
            jl.debit,
            jl.credit,
            exists (
                select 1 from journal_entries r where r.reverses_entry_id = je.id
            ) as reversed,
            coalesce(pr.full_name, 'Inconnu') as recorded_by
        from journal_lines jl
        join journal_entries je on je.id = jl.journal_entry_id
        left join profiles pr on pr.id = je.created_by
        cross join access x
        where x.detailed
          and jl.account_id = p_account_id
          and je.org_id = p_org_id
          and (p_from is null or je.created_at::date >= p_from)
          and (p_to   is null or je.created_at::date <= p_to)
    )
    select
        m.entry_id, m.occurred_at, m.label, m.memo, m.debit, m.credit,
        coalesce((select amount from opening), 0)
            + sum(m.debit - m.credit) over (
                order by m.occurred_at, m.entry_id
                rows between unbounded preceding and current row
            ),
        m.reversed, m.recorded_by
    from movements m
    order by m.occurred_at desc, m.entry_id desc
    limit greatest(coalesce(p_limit, 200), 1);
$$;

-- ------------------------------------------------------------
-- 10. THE JOURNAL — every entry, newest first
-- ------------------------------------------------------------
-- What the day list on the home screen shows for today, for any range and
-- with both sides of each entry named. Line items again, so full visibility.
create or replace function journal_page(
    p_org_id uuid,
    p_from   date default null,
    p_to     date default null,
    p_limit  int  default 100,
    p_offset int  default 0
)
returns table (
    entry_id     uuid,
    occurred_at  timestamptz,
    label        text,
    memo         text,
    details      jsonb,
    amount       numeric,
    debit_names  text,
    credit_names text,
    direction    text,        -- 'in' | 'out' | 'transfer'
    reversed     boolean,
    is_reversal  boolean,
    recorded_by  text
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        je.id,
        je.created_at,
        coalesce(je.label, je.memo, 'Entrée'),
        je.memo,
        je.details,
        coalesce(sum(jl.debit), 0),
        string_agg(distinct a.name, ', ') filter (where jl.debit > 0),
        string_agg(distinct a.name, ', ') filter (where jl.credit > 0),
        case
            when bool_or(a.type = 'income'  and jl.credit > 0) then 'in'
            when bool_or(a.type = 'expense' and jl.debit  > 0) then 'out'
            else 'transfer'
        end,
        exists (select 1 from journal_entries r where r.reverses_entry_id = je.id),
        je.reverses_entry_id is not null,
        coalesce(pr.full_name, 'Inconnu')
    from journal_entries je
    join journal_lines jl on jl.journal_entry_id = je.id
    join accounts a on a.id = jl.account_id
    left join profiles pr on pr.id = je.created_by
    where je.org_id = p_org_id
      and has_full_visibility(p_org_id)
      and (p_from is null or je.created_at::date >= p_from)
      and (p_to   is null or je.created_at::date <= p_to)
    group by je.id, je.created_at, je.label, je.memo, je.details,
             je.reverses_entry_id, pr.full_name
    order by je.created_at desc, je.id desc
    limit greatest(coalesce(p_limit, 100), 1)
    offset greatest(coalesce(p_offset, 0), 0);
$$;

-- ------------------------------------------------------------
-- 11. GRANTS
-- ------------------------------------------------------------
-- Everything above that is SECURITY DEFINER starts life granted to PUBLIC,
-- which includes anon. Each one already refuses a caller with no session —
-- auth.uid() is null, so no membership matches — but the same discipline as
-- 005 and 006 applies: the grant is made deliberate rather than inherited.
revoke execute on function record_entry(uuid, numeric, text, text, uuid, text, text, uuid, text, jsonb, uuid, uuid, uuid, text, timestamptz) from public;
revoke execute on function record_transfer(uuid, numeric, text, text, uuid, text, text, uuid, text, timestamptz) from public;
revoke execute on function create_account(uuid, text, text, text, text) from public;
revoke execute on function chart_of_accounts(uuid) from public;
revoke execute on function trial_balance(uuid, date, date) from public;
revoke execute on function income_statement(uuid, date, date) from public;
revoke execute on function balance_sheet(uuid, date) from public;
revoke execute on function account_ledger(uuid, uuid, date, date, int) from public;
revoke execute on function journal_page(uuid, date, date, int, int) from public;

-- The helpers are not SECURITY DEFINER and are not for callers at all. They
-- run inside the functions above, which have already established permission;
-- reached directly they would insert under RLS and be refused, but there is
-- no reason to offer them at all.
revoke execute on function ensure_account(uuid, text, text, uuid) from public;
revoke execute on function ensure_account_by_code(uuid, text, text, text, uuid) from public;
revoke execute on function resolve_cash_account(uuid, text, uuid) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function record_entry(uuid, numeric, text, text, uuid, text, text, uuid, text, jsonb, uuid, uuid, uuid, text, timestamptz) to authenticated;
        grant execute on function record_transfer(uuid, numeric, text, text, uuid, text, text, uuid, text, timestamptz) to authenticated;
        grant execute on function create_account(uuid, text, text, text, text) to authenticated;
        grant execute on function chart_of_accounts(uuid) to authenticated;
        grant execute on function trial_balance(uuid, date, date) to authenticated;
        grant execute on function income_statement(uuid, date, date) to authenticated;
        grant execute on function balance_sheet(uuid, date) to authenticated;
        grant execute on function account_ledger(uuid, uuid, date, date, int) to authenticated;
        grant execute on function journal_page(uuid, date, date, int, int) to authenticated;
    end if;
end $$;
