-- ============================================================
-- 002_church_profile.sql
-- Israel's module: the church profile.
--
-- Design rule for this whole file: Israel never sees a debit or a credit.
-- He taps "Offering — 50,000" and the function underneath writes a balanced
-- journal entry. Every public function here takes plain-language inputs and
-- hides the accounting completely.
-- ============================================================

-- ------------------------------------------------------------
-- 1. MEMBERS
-- ------------------------------------------------------------
-- Church members. Not app users — most will never log in. This exists so
-- tithes can be attributed and giving statements produced at year end.
create table church_members (
    id uuid primary key default gen_random_uuid(),
    org_id uuid not null references orgs(id) on delete cascade,
    full_name text not null,
    phone text,
    joined_on date,
    is_active boolean not null default true,
    created_at timestamptz not null default now()
);

create index on church_members (org_id) where is_active;

-- ------------------------------------------------------------
-- 2. IDEMPOTENCY — the offline safety net
-- ------------------------------------------------------------
-- Every recording function accepts a client_uuid generated on the device.
-- If a phone loses signal mid-sync and retries, the retry hits this unique
-- constraint and returns the original entry instead of double-posting.
-- Without this, a bad connection silently doubles the offering count.
alter table journal_entries
    add column client_uuid uuid;

create unique index journal_entries_client_uuid_key
    on journal_entries (org_id, client_uuid)
    where client_uuid is not null;

-- ------------------------------------------------------------
-- 3. CHART OF ACCOUNTS — seeded, never blank
-- ------------------------------------------------------------
-- A new church starts with these already in place. Nobody should have to
-- invent an accounting structure to record their first offering.
create or replace function seed_church_accounts(p_org_id uuid)
returns void
language plpgsql
as $$
begin
    insert into accounts (org_id, code, name, type) values
        (p_org_id, '1000', 'Cash on Hand',        'asset'),
        (p_org_id, '1010', 'Bank Account',        'asset'),
        (p_org_id, '1020', 'Mobile Money',        'asset'),
        (p_org_id, '4000', 'Tithes',              'income'),
        (p_org_id, '4010', 'Offerings',           'income'),
        (p_org_id, '4020', 'Special Collections', 'income'),
        (p_org_id, '4030', 'Donations',           'income'),
        (p_org_id, '5000', 'Utilities',           'expense'),
        (p_org_id, '5010', 'Rent',                'expense'),
        (p_org_id, '5020', 'Salaries & Stipends', 'expense'),
        (p_org_id, '5030', 'Maintenance',         'expense'),
        (p_org_id, '5040', 'Outreach & Charity',  'expense'),
        (p_org_id, '5050', 'Supplies',            'expense'),
        (p_org_id, '5060', 'Events',              'expense')
    on conflict (org_id, code) do nothing;
end;
$$;

-- ------------------------------------------------------------
-- 4. RECORDING CONTRIBUTIONS
-- ------------------------------------------------------------

-- Links a contribution to the member who gave it — kept separate from the
-- ledger so the ledger stays purely financial and anonymous giving stays easy.
create table contribution_attributions (
    journal_entry_id uuid primary key references journal_entries(id) on delete cascade,
    member_id uuid not null references church_members(id) on delete cascade
);

create index on contribution_attributions (member_id);

-- What Israel actually taps. Returns the journal entry id.
--
--   p_kind:      'tithe' | 'offering' | 'special' | 'donation'
--   p_method:    'cash' | 'bank' | 'mobile_money'
--   p_member_id: optional — offerings are usually anonymous, tithes usually aren't
-- p_recorded_by is required, not optional: an entry nobody is named on
-- defeats the audit trail the pastor and the investors depend on.
create or replace function record_contribution(
    p_org_id      uuid,
    p_amount      numeric,
    p_kind        text,
    p_recorded_by uuid,
    p_method      text        default 'cash',
    p_member_id   uuid        default null,
    p_memo        text        default null,
    p_client_uuid uuid        default null,
    p_device_id   text        default null,
    p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
as $$
declare
    v_entry_id     uuid;
    v_debit_code   text;
    v_credit_code  text;
    v_debit_acct   uuid;
    v_credit_acct  uuid;
    v_existing     uuid;
begin
    if p_amount <= 0 then
        raise exception 'Amount must be greater than zero (got %)', p_amount;
    end if;

    -- Idempotency: a retried sync returns the original entry, never a duplicate.
    if p_client_uuid is not null then
        select id into v_existing
        from journal_entries
        where org_id = p_org_id and client_uuid = p_client_uuid;

        if found then
            return v_existing;
        end if;
    end if;

    v_debit_code := case p_method
        when 'cash'         then '1000'
        when 'bank'         then '1010'
        when 'mobile_money' then '1020'
        else null
    end;

    if v_debit_code is null then
        raise exception 'Unknown payment method: %', p_method;
    end if;

    v_credit_code := case p_kind
        when 'tithe'    then '4000'
        when 'offering' then '4010'
        when 'special'  then '4020'
        when 'donation' then '4030'
        else null
    end;

    if v_credit_code is null then
        raise exception 'Unknown contribution kind: %', p_kind;
    end if;

    select id into v_debit_acct  from accounts where org_id = p_org_id and code = v_debit_code;
    select id into v_credit_acct from accounts where org_id = p_org_id and code = v_credit_code;

    if v_debit_acct is null or v_credit_acct is null then
        raise exception 'Chart of accounts not seeded for org % — call seed_church_accounts() first', p_org_id;
    end if;

    insert into journal_entries (org_id, memo, created_by, created_at, device_id, client_uuid)
    values (
        p_org_id,
        coalesce(p_memo, initcap(p_kind) || ' received'),
        p_recorded_by,
        p_occurred_at,
        p_device_id,
        p_client_uuid
    )
    returning id into v_entry_id;

    -- Money in: debit the asset, credit the income account.
    insert into journal_lines (journal_entry_id, account_id, debit, credit) values
        (v_entry_id, v_debit_acct,  p_amount, 0),
        (v_entry_id, v_credit_acct, 0,        p_amount);

    if p_member_id is not null then
        insert into contribution_attributions (journal_entry_id, member_id)
        values (v_entry_id, p_member_id);
    end if;

    return v_entry_id;
end;
$$;

-- ------------------------------------------------------------
-- 5. RECORDING EXPENSES
-- ------------------------------------------------------------
create or replace function record_expense(
    p_org_id       uuid,
    p_amount       numeric,
    p_expense_code text,                    -- '5000'..'5060' from the seeded chart
    p_recorded_by  uuid,
    p_method       text        default 'cash',
    p_memo         text        default null,
    p_client_uuid  uuid        default null,
    p_device_id    text        default null,
    p_occurred_at  timestamptz default now()
)
returns uuid
language plpgsql
as $$
declare
    v_entry_id    uuid;
    v_credit_code text;
    v_debit_acct  uuid;
    v_credit_acct uuid;
    v_existing    uuid;
begin
    if p_amount <= 0 then
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

    v_credit_code := case p_method
        when 'cash'         then '1000'
        when 'bank'         then '1010'
        when 'mobile_money' then '1020'
        else null
    end;

    if v_credit_code is null then
        raise exception 'Unknown payment method: %', p_method;
    end if;

    select id into v_debit_acct  from accounts where org_id = p_org_id and code = p_expense_code;
    select id into v_credit_acct from accounts where org_id = p_org_id and code = v_credit_code;

    if v_debit_acct is null then
        raise exception 'No expense account with code % for org %', p_expense_code, p_org_id;
    end if;

    insert into journal_entries (org_id, memo, created_by, created_at, device_id, client_uuid)
    values (p_org_id, coalesce(p_memo, 'Expense paid'), p_recorded_by, p_occurred_at, p_device_id, p_client_uuid)
    returning id into v_entry_id;

    -- Money out: debit the expense, credit the asset it came from.
    insert into journal_lines (journal_entry_id, account_id, debit, credit) values
        (v_entry_id, v_debit_acct,  p_amount, 0),
        (v_entry_id, v_credit_acct, 0,        p_amount);

    return v_entry_id;
end;
$$;

-- ------------------------------------------------------------
-- 6. UNDO — a reversing entry, never a delete
-- ------------------------------------------------------------
-- Israel taps "Undo". Nothing is destroyed; a mirror-image entry cancels it
-- out. Both remain visible, so the pastor can see what was corrected and when.
create or replace function reverse_entry(
    p_entry_id    uuid,
    p_reversed_by uuid,
    p_reason      text default null
)
returns uuid
language plpgsql
as $$
declare
    v_new_id uuid;
    v_org_id uuid;
begin
    select org_id into v_org_id from journal_entries where id = p_entry_id;
    if v_org_id is null then
        raise exception 'No such entry: %', p_entry_id;
    end if;

    if exists (select 1 from journal_entries where reverses_entry_id = p_entry_id) then
        raise exception 'Entry % has already been reversed', p_entry_id;
    end if;

    insert into journal_entries (org_id, memo, created_by, reverses_entry_id)
    values (v_org_id, coalesce(p_reason, 'Correction'), p_reversed_by, p_entry_id)
    returning id into v_new_id;

    -- Swap every debit and credit from the original.
    insert into journal_lines (journal_entry_id, account_id, debit, credit)
    select v_new_id, account_id, credit, debit
    from journal_lines
    where journal_entry_id = p_entry_id;

    return v_new_id;
end;
$$;

-- ------------------------------------------------------------
-- 7. THE PASTOR'S VIEW
-- ------------------------------------------------------------
-- Reversed entries and their reversals cancel out arithmetically, so totals
-- are correct without excluding anything — the full history stays intact.

create or replace view church_account_activity as
select
    je.org_id,
    je.created_at::date as activity_date,
    a.code,
    a.name as account_name,
    a.type as account_type,
    sum(jl.debit)  as total_debit,
    sum(jl.credit) as total_credit
from journal_entries je
join journal_lines jl on jl.journal_entry_id = je.id
join accounts a on a.id = jl.account_id
group by je.org_id, je.created_at::date, a.code, a.name, a.type;

-- What actually gets sent to the pastor every Sunday evening.
create or replace function church_weekly_summary(
    p_org_id uuid,
    p_week_ending date default current_date
)
returns table (
    category text,
    label    text,
    amount   numeric
)
language sql
stable
as $$
    with window_bounds as (
        select (p_week_ending - interval '6 days')::date as start_date,
               p_week_ending as end_date
    ),
    lines as (
        select a.type, a.name, jl.debit, jl.credit
        from journal_entries je
        join journal_lines jl on jl.journal_entry_id = je.id
        join accounts a on a.id = jl.account_id
        cross join window_bounds w
        where je.org_id = p_org_id
          and je.created_at::date between w.start_date and w.end_date
    )
    select 'income'::text, name, sum(credit - debit)
    from lines where type = 'income'
    group by name having sum(credit - debit) <> 0

    union all

    select 'expense'::text, name, sum(debit - credit)
    from lines where type = 'expense'
    group by name having sum(debit - credit) <> 0

    union all

    select 'total'::text, 'Total received', coalesce(sum(credit - debit), 0)
    from lines where type = 'income'

    union all

    select 'total'::text, 'Total spent', coalesce(sum(debit - credit), 0)
    from lines where type = 'expense'

    order by 1, 2;
$$;

-- Current cash position across all three holding accounts.
create or replace function church_balances(p_org_id uuid)
returns table (account_name text, balance numeric)
language sql
stable
as $$
    select a.name, coalesce(sum(jl.debit - jl.credit), 0)
    from accounts a
    left join journal_lines jl on jl.account_id = a.id
    where a.org_id = p_org_id and a.type = 'asset'
    group by a.name
    order by a.name;
$$;

-- Year-end giving statement for one member.
create or replace function member_giving_statement(
    p_member_id uuid,
    p_year      int default extract(year from current_date)::int
)
returns table (contribution_date date, kind text, amount numeric)
language sql
stable
as $$
    select je.created_at::date, a.name, jl.credit
    from contribution_attributions ca
    join journal_entries je on je.id = ca.journal_entry_id
    join journal_lines jl on jl.journal_entry_id = je.id
    join accounts a on a.id = jl.account_id
    where ca.member_id = p_member_id
      and a.type = 'income'
      and jl.credit > 0
      and extract(year from je.created_at) = p_year
    order by 1;
$$;

-- ------------------------------------------------------------
-- 8. RLS on the new tables
-- ------------------------------------------------------------
alter table church_members enable row level security;

create policy "members readable within org"
on church_members for select
using (
    exists (
        select 1 from memberships m
        where m.user_id = auth.uid() and m.org_id = church_members.org_id
    )
);

create policy "members writable by non-observers"
on church_members for all
using (
    exists (
        select 1 from memberships m
        where m.user_id = auth.uid()
          and m.org_id = church_members.org_id
          and m.role not in ('observer', 'approver')
    )
);
