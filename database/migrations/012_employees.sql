-- ============================================================
-- 012_employees.sql — the people a business pays.
--
-- M5 asks for "employees: permanent and temporary, shifts, salary/wage,
-- payments". This is that, and it is deliberately not a payroll system.
--
-- The distinction that shapes everything below: an *employee* is a person the
-- business pays, and a *membership* is an account with access to the books.
-- They are different sets and conflating them is the mistake this schema
-- exists to avoid. Esperance's Sunday helper is paid and must never see the
-- takings; her accountant sees everything and is not on the payroll. So
-- `employees.user_id` is nullable and usually null — most people who get paid
-- never install the app at all.
--
-- Two kinds of person, one table:
--
--   'permanent' — paid a salary for a period. Hours are not counted.
--   'casual'    — paid a rate for time worked, so the shifts are the record
--                 and the money follows from them.
--
-- Every payment posts through `record_entry()` like everything else, so wages
-- appear in the income statement beside rent and stock without a second
-- ledger to reconcile.
--
-- What is not here, on purpose: tax, social contributions, and payslips.
-- Those are jurisdiction-specific, they are what an accountant is for, and
-- guessing at them would produce numbers that look official and are wrong.
-- ============================================================

create table if not exists employees (
    id           uuid primary key default gen_random_uuid(),
    org_id       uuid not null references orgs(id) on delete cascade,
    full_name    text not null,
    phone        text,
    role_title   text,
    -- 'permanent' | 'casual'
    kind         text not null default 'casual'
                 check (kind in ('permanent', 'casual')),
    -- A monthly salary for permanent staff; ignored for casuals.
    salary       numeric(14,2) not null default 0 check (salary >= 0),
    -- What a casual earns per hour. Ignored for permanent staff.
    hourly_rate  numeric(14,2) not null default 0 check (hourly_rate >= 0),
    -- Null when this person has no account, which is the common case: being
    -- paid and being able to open the books are different things.
    user_id      uuid references profiles(id),
    started_on   date not null default current_date,
    ended_on     date,
    is_active    boolean not null default true,
    created_at   timestamptz not null default now(),
    created_by   uuid references profiles(id)
);

create index if not exists employees_active on employees (org_id) where is_active;
create unique index if not exists employees_by_name
    on employees (org_id, lower(btrim(full_name)));

-- Time worked. Only meaningful for casuals, but recorded for anyone, because
-- "who was in the shop on the day the till was short" is a question worth
-- being able to answer about permanent staff too.
create table if not exists shifts (
    id           uuid primary key default gen_random_uuid(),
    org_id       uuid not null references orgs(id) on delete cascade,
    employee_id  uuid not null references employees(id) on delete cascade,
    worked_on    date not null default current_date,
    hours        numeric(6,2) not null check (hours > 0 and hours <= 24),
    note         text,
    -- Set when this shift has been included in a payment. Null means unpaid,
    -- which is what the "à payer" figure on screen counts.
    payment_id   uuid,
    recorded_by  uuid references profiles(id),
    client_uuid  uuid,
    created_at   timestamptz not null default now()
);

create unique index if not exists shifts_client_uuid_key
    on shifts (org_id, client_uuid) where client_uuid is not null;
create index if not exists shifts_by_employee
    on shifts (employee_id, worked_on desc);
create index if not exists shifts_unpaid
    on shifts (org_id) where payment_id is null;

create table if not exists staff_payments (
    id           uuid primary key default gen_random_uuid(),
    org_id       uuid not null references orgs(id) on delete cascade,
    employee_id  uuid not null references employees(id),
    amount       numeric(14,2) not null check (amount > 0),
    -- What the money was for, in the words a shopkeeper would use.
    label        text not null default 'Salaire',
    method       text not null default 'cash',
    paid_on      date not null default current_date,
    -- The ledger entry this payment posted.
    entry_id     uuid references journal_entries(id),
    paid_by      uuid references profiles(id),
    client_uuid  uuid,
    created_at   timestamptz not null default now()
);

create unique index if not exists staff_payments_client_uuid_key
    on staff_payments (org_id, client_uuid) where client_uuid is not null;
create index if not exists staff_payments_by_employee
    on staff_payments (employee_id, paid_on desc);

-- ------------------------------------------------------------
-- Recording
-- ------------------------------------------------------------

create or replace function add_employee(
    p_org_id      uuid,
    p_full_name   text,
    p_kind        text    default 'casual',
    p_hourly_rate numeric default null,
    p_salary      numeric default null,
    p_phone       text    default null,
    p_role_title  text    default null,
    p_actor       uuid    default null
)
returns uuid
language plpgsql
as $$
declare
    v_name text := btrim(coalesce(p_full_name, ''));
    v_id   uuid;
begin
    if v_name = '' then
        raise exception 'An employee needs a name';
    end if;

    select id into v_id from employees
    where org_id = p_org_id and lower(btrim(full_name)) = lower(v_name);

    if v_id is not null then
        -- Re-adding somebody who left brings them back rather than making a
        -- second row: the shifts they worked last season are theirs.
        update employees set
            is_active   = true,
            ended_on    = null,
            kind        = coalesce(nullif(p_kind, ''), kind),
            hourly_rate = coalesce(p_hourly_rate, hourly_rate),
            salary      = coalesce(p_salary, salary),
            phone       = coalesce(p_phone, phone),
            role_title  = coalesce(p_role_title, role_title)
        where id = v_id;
        return v_id;
    end if;

    insert into employees (org_id, full_name, kind, hourly_rate, salary,
                           phone, role_title, created_by)
    values (p_org_id, v_name, coalesce(nullif(p_kind, ''), 'casual'),
            coalesce(p_hourly_rate, 0), coalesce(p_salary, 0),
            p_phone, p_role_title, p_actor)
    returning id into v_id;

    return v_id;
end;
$$;

-- A day worked. Idempotent by client_uuid like every other recording call, so
-- a phone that retries does not pay somebody twice for one afternoon.
create or replace function record_shift(
    p_org_id      uuid,
    p_employee_id uuid,
    p_hours       numeric,
    p_worked_on   date default current_date,
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
    v_id       uuid;
    v_existing uuid;
begin
    if not exists (select 1 from employees
                   where id = p_employee_id and org_id = p_org_id) then
        raise exception 'No such employee in this business';
    end if;

    if p_client_uuid is not null then
        select id into v_existing from shifts
        where org_id = p_org_id and client_uuid = p_client_uuid;
        if v_existing is not null then
            return v_existing;
        end if;
    end if;

    insert into shifts (org_id, employee_id, worked_on, hours, note,
                        recorded_by, client_uuid)
    values (p_org_id, p_employee_id, p_worked_on, p_hours, p_note,
            v_actor, p_client_uuid)
    returning id into v_id;

    return v_id;
end;
$$;

-- What is owed to a casual for shifts nobody has paid for yet.
create or replace function unpaid_shifts(p_org_id uuid)
returns table (
    employee_id uuid,
    full_name   text,
    hours       numeric,
    shifts      int,
    owed        numeric
)
language sql
stable
security invoker
set search_path = public, auth
as $$
    select
        e.id, e.full_name,
        coalesce(sum(s.hours), 0),
        count(s.id)::int,
        round(coalesce(sum(s.hours), 0) * e.hourly_rate, 2)
    from employees e
    join shifts s on s.employee_id = e.id and s.payment_id is null
    where e.org_id = p_org_id
    group by e.id, e.full_name, e.hourly_rate
    having coalesce(sum(s.hours), 0) > 0
    order by e.full_name;
$$;

-- Paying somebody. Posts the money and, for a casual, marks the shifts it
-- covers so the same hours cannot be paid a second time.
--
-- [p_cover_shifts] settles every unpaid shift for that employee. It is the
-- default because the alternative — paying a casual and leaving their shifts
-- marked unpaid — produces a figure on screen that says they are still owed
-- money they have just been handed.
create or replace function pay_employee(
    p_org_id       uuid,
    p_employee_id  uuid,
    p_amount       numeric default null,
    p_label        text    default null,
    p_method       text    default 'cash',
    p_paid_on      date    default current_date,
    p_cover_shifts boolean default true,
    p_client_uuid  uuid    default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_name     text;
    v_kind     text;
    v_rate     numeric;
    v_salary   numeric;
    v_amount   numeric;
    v_payment  uuid;
    v_existing uuid;
    v_entry    uuid;
begin
    select full_name, kind, hourly_rate, salary
      into v_name, v_kind, v_rate, v_salary
    from employees where id = p_employee_id and org_id = p_org_id;

    if v_name is null then
        raise exception 'No such employee in this business';
    end if;

    if p_client_uuid is not null then
        select id into v_existing from staff_payments
        where org_id = p_org_id and client_uuid = p_client_uuid;
        if v_existing is not null then
            return v_existing;
        end if;
    end if;

    -- Work out what is owed when the caller did not say. A casual is paid for
    -- the hours nobody has paid for yet; a permanent employee is paid their
    -- salary.
    v_amount := p_amount;
    if v_amount is null then
        if v_kind = 'casual' then
            select round(coalesce(sum(s.hours), 0) * v_rate, 2) into v_amount
            from shifts s
            where s.employee_id = p_employee_id and s.payment_id is null;
        else
            v_amount := v_salary;
        end if;
    end if;

    if v_amount is null or v_amount <= 0 then
        raise exception 'There is nothing to pay %', v_name;
    end if;

    insert into staff_payments (org_id, employee_id, amount, label, method,
                                paid_on, paid_by, client_uuid)
    values (p_org_id, p_employee_id, v_amount,
            coalesce(nullif(btrim(coalesce(p_label, '')), ''),
                     case when v_kind = 'casual' then 'Journées' else 'Salaire' end),
            p_method, p_paid_on, v_actor, p_client_uuid)
    returning id into v_payment;

    if p_cover_shifts then
        update shifts set payment_id = v_payment
        where employee_id = p_employee_id and payment_id is null;
    end if;

    v_entry := record_entry(
        p_org_id      => p_org_id,
        p_amount      => v_amount,
        p_direction   => 'out',
        p_label       => 'Salaires',
        p_recorded_by => v_actor,
        p_category    => 'Salaires',
        p_method      => p_method,
        p_memo        => v_name,
        p_details     => jsonb_build_object('employee', v_name,
                                            'payment_id', v_payment),
        p_client_uuid => p_client_uuid,
        p_occurred_at => p_paid_on::timestamptz
    );

    update staff_payments set entry_id = v_entry where id = v_payment;

    return v_payment;
end;
$$;

-- ------------------------------------------------------------
-- Row level security
--
-- Wages are the most sensitive numbers in a small business — more than the
-- takings, because everybody in the shop knows what the takings look like and
-- nobody is supposed to know what anybody else earns. So reading these three
-- tables needs an admin, not merely membership. That is stricter than every
-- other module here, and deliberately so.
-- ------------------------------------------------------------

alter table employees      enable row level security;
alter table shifts         enable row level security;
alter table staff_payments enable row level security;

drop policy if exists "employees readable by org admins" on employees;
create policy "employees readable by org admins"
on employees for select using (is_org_admin(org_id));

drop policy if exists "employees managed by org admins" on employees;
create policy "employees managed by org admins"
on employees for insert with check (is_org_admin(org_id));

drop policy if exists "employees amended by org admins" on employees;
create policy "employees amended by org admins"
on employees for update using (is_org_admin(org_id))
with check (is_org_admin(org_id));

drop policy if exists "shifts readable by org admins" on shifts;
create policy "shifts readable by org admins"
on shifts for select using (is_org_admin(org_id));

drop policy if exists "shifts recorded by staff" on shifts;
create policy "shifts recorded by staff"
on shifts for insert with check (can_write_org(org_id));

drop policy if exists "payments readable by org admins" on staff_payments;
create policy "payments readable by org admins"
on staff_payments for select using (is_org_admin(org_id));

drop policy if exists "payments made by org admins" on staff_payments;
create policy "payments made by org admins"
on staff_payments for insert with check (is_org_admin(org_id));

-- No update or delete on staff_payments. A payment made in error is corrected
-- the way every other mistake in this schema is: by recording the correction,
-- not by erasing the record.

comment on table employees is
    'People the business pays. Not the same set as the people who can open '
    'its books — user_id is null for most of them.';
comment on table shifts is
    'Time worked, and the basis for what a casual is owed.';
comment on table staff_payments is
    'Wages and salaries paid, each posting its own ledger entry.';
