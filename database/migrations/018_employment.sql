-- ============================================================
-- 018_employment.sql — staff management that a church and a farm can use too.
--
-- 012 built a payroll for a shop: a name, a rate, hours worked, money paid.
-- That is the right core and it is not staff management. Four things were
-- missing that any business with more than two people needs, and none of them
-- are shop things:
--
--   1. **Where somebody works.** A church with three campuses and a farm with
--      two sites both need to know which one a person belongs to. The scope
--      machinery for this has existed since 004 — entities and departments —
--      and `employees` did not use it.
--   2. **What kind of engagement it is.** 012 has `permanent | casual`, which
--      is a pay model rather than a contract. A volunteer at a church is
--      neither, and recording them as a casual on zero francs an hour makes
--      the payroll say something untrue about what the church owes.
--   3. **Why somebody left.** `ended_on` said when and never why, so a person
--      who resigned and a person who was dismissed read the same a year
--      later, which is exactly when it matters.
--   4. **The link to their account.** `user_id` existed and nothing ever set
--      it, so the person on the payroll and the person holding the phone were
--      two unconnected records with the same name.
--
-- One decision worth stating: **the directory is not the permission system.**
-- Adding somebody as an employee still grants nothing — that is `memberships`
-- and an invitation code, as it has always been — and linking an employee to
-- an account does not change what the account may do. A payroll that could
-- hand out access would make every bookkeeper an administrator.
-- ============================================================

-- ------------------------------------------------------------
-- 1. THE ENGAGEMENT
-- ------------------------------------------------------------

alter table employees add column if not exists entity_id     uuid;
alter table employees add column if not exists department_id uuid;
alter table employees add column if not exists employment    text;
alter table employees add column if not exists end_reason    text;
alter table employees add column if not exists national_id   text;
alter table employees add column if not exists emergency_contact text;
alter table employees add column if not exists emergency_phone   text;
alter table employees add column if not exists notes         text;

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'employees_entity_fkey') then
        alter table employees add constraint employees_entity_fkey
            foreign key (entity_id) references entities(id) on delete set null;
    end if;
    if not exists (select 1 from pg_constraint where conname = 'employees_department_fkey') then
        alter table employees add constraint employees_department_fkey
            foreign key (department_id) references departments(id) on delete set null;
    end if;

    -- The kinds of engagement a business here actually has. `volunteer` is
    -- the one that matters most for a church: somebody who works and is not
    -- paid is not a casual on zero francs, and the payroll must not imply a
    -- debt to them.
    if not exists (select 1 from pg_constraint where conname = 'employees_employment_kind') then
        alter table employees add constraint employees_employment_kind
            check (employment is null or employment in
                ('permanent', 'fixed_term', 'daily', 'apprentice', 'volunteer'));
    end if;

    if not exists (select 1 from pg_constraint where conname = 'employees_end_reason_kind') then
        alter table employees add constraint employees_end_reason_kind
            check (end_reason is null or end_reason in
                ('resigned', 'dismissed', 'contract_ended', 'retired', 'other'));
    end if;
end $$;

comment on column employees.employment is
    'The engagement: permanent, fixed_term, daily, apprentice, volunteer. Distinct from `kind`, which is how they are paid.';
comment on column employees.end_reason is
    'Why they left. ended_on alone makes a resignation and a dismissal read identically a year later.';
comment on column employees.national_id is
    'CNIB or passport number. Needed on a contract; nullable because most casual work here has no paperwork.';

-- Everything already recorded is a paid engagement of one of the two 012
-- shapes, so it can be filled in rather than left null.
update employees
   set employment = case when kind = 'permanent' then 'permanent' else 'daily' end
 where employment is null;

create index if not exists employees_by_entity
    on employees (org_id, entity_id) where entity_id is not null;

-- One account is one person. Without this, two employee rows can point at the
-- same profile and "who am I on this payroll" has two answers.
create unique index if not exists employees_one_per_account
    on employees (org_id, user_id) where user_id is not null;

-- ------------------------------------------------------------
-- 2. HIRING, MOVING, AND LEAVING
-- ------------------------------------------------------------

-- Everything about somebody that an admin may change. Null leaves a field
-- alone: a screen that saves one field must not blank the other ten.
create or replace function update_employee(
    p_employee_id  uuid,
    p_full_name    text default null,
    p_phone        text default null,
    p_role_title   text default null,
    p_employment   text default null,
    p_kind         text default null,
    p_salary       numeric default null,
    p_hourly_rate  numeric default null,
    p_entity_id    uuid default null,
    p_department_id uuid default null,
    p_national_id  text default null,
    p_emergency_contact text default null,
    p_emergency_phone   text default null,
    p_notes        text default null,
    p_started_on   date default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor  uuid := auth.uid();
    v_org_id uuid;
begin
    if v_actor is null then
        raise exception 'update_employee() needs a signed-in caller';
    end if;

    select org_id into v_org_id from employees where id = p_employee_id;
    if not found then
        raise exception 'No such employee';
    end if;

    -- Org admin, like everything else about wages: what a colleague earns is
    -- the most sensitive number in a small business.
    if not is_org_admin(v_org_id) then
        raise exception 'You cannot change staff records in this business';
    end if;

    -- A site or a department belonging to another business would put somebody
    -- on a payroll in one org and a location in another.
    if p_entity_id is not null and not exists (
        select 1 from entities where id = p_entity_id and org_id = v_org_id
    ) then
        raise exception 'That site belongs to another business';
    end if;

    if p_department_id is not null and not exists (
        select 1 from departments d
        join entities e on e.id = d.entity_id
        where d.id = p_department_id and e.org_id = v_org_id
    ) then
        raise exception 'That department belongs to another business';
    end if;

    update employees set
        full_name     = coalesce(nullif(btrim(coalesce(p_full_name, '')), ''), full_name),
        phone         = coalesce(nullif(btrim(coalesce(p_phone, '')), ''), phone),
        role_title    = coalesce(nullif(btrim(coalesce(p_role_title, '')), ''), role_title),
        employment    = coalesce(nullif(btrim(coalesce(p_employment, '')), ''), employment),
        kind          = coalesce(nullif(btrim(coalesce(p_kind, '')), ''), kind),
        salary        = coalesce(p_salary, salary),
        hourly_rate   = coalesce(p_hourly_rate, hourly_rate),
        entity_id     = coalesce(p_entity_id, entity_id),
        department_id = coalesce(p_department_id, department_id),
        national_id   = coalesce(nullif(btrim(coalesce(p_national_id, '')), ''), national_id),
        emergency_contact = coalesce(nullif(btrim(coalesce(p_emergency_contact, '')), ''), emergency_contact),
        emergency_phone   = coalesce(nullif(btrim(coalesce(p_emergency_phone, '')), ''), emergency_phone),
        notes         = coalesce(nullif(btrim(coalesce(p_notes, '')), ''), notes),
        started_on    = coalesce(p_started_on, started_on)
    where id = p_employee_id;

    return p_employee_id;
end;
$$;

-- Somebody leaving. Not a deletion: they worked here, they were paid, and
-- both of those are history. `unpaid_shifts` still owes them what it owed
-- them, which is the point of ending an engagement rather than removing it.
create or replace function end_employment(
    p_employee_id uuid,
    p_reason      text,
    p_ended_on    date default current_date,
    p_note        text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor  uuid := auth.uid();
    v_org_id uuid;
    v_owed   numeric;
begin
    if v_actor is null then
        raise exception 'end_employment() needs a signed-in caller';
    end if;

    select org_id into v_org_id from employees where id = p_employee_id;
    if not found then
        raise exception 'No such employee';
    end if;

    if not is_org_admin(v_org_id) then
        raise exception 'You cannot change staff records in this business';
    end if;

    if p_reason is null or p_reason not in
       ('resigned', 'dismissed', 'contract_ended', 'retired', 'other') then
        raise exception 'Say why they left: resigned, dismissed, contract_ended, retired or other';
    end if;

    -- Refused while money is owed, and this is the assertion that earns the
    -- function. Marking somebody inactive takes them off the payroll screen,
    -- and unpaid hours that vanish from the screen are unpaid hours nobody
    -- pays. Pay them, then close it.
    select coalesce(sum(owed), 0) into v_owed
    from unpaid_shifts(v_org_id) where employee_id = p_employee_id;

    if v_owed > 0 then
        raise exception
            'Pay what is owed first: % remains unpaid', v_owed;
    end if;

    update employees set
        ended_on   = coalesce(p_ended_on, current_date),
        end_reason = p_reason,
        is_active  = false,
        notes      = coalesce(nullif(btrim(coalesce(p_note, '')), ''), notes)
    where id = p_employee_id;

    return p_employee_id;
end;
$$;

-- Connecting somebody on the payroll to the account they sign in with.
--
-- Deliberately one-directional and deliberately grants nothing: this says
-- "the Awa on the payroll is the Awa holding this phone", and says nothing
-- about what she may do. Access is `memberships`, and it comes from an
-- invitation code as it always has.
create or replace function link_employee_account(
    p_employee_id uuid,
    p_user_id     uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor  uuid := auth.uid();
    v_org_id uuid;
begin
    if v_actor is null then
        raise exception 'link_employee_account() needs a signed-in caller';
    end if;

    select org_id into v_org_id from employees where id = p_employee_id;
    if not found then
        raise exception 'No such employee';
    end if;

    if not is_org_admin(v_org_id) then
        raise exception 'You cannot change staff records in this business';
    end if;

    -- Only somebody who is already a member. Linking an arbitrary account
    -- would let an admin attach a stranger's profile to their payroll and
    -- read their name and number out of it.
    if p_user_id is not null and not exists (
        select 1 from memberships where org_id = v_org_id and user_id = p_user_id
    ) then
        raise exception 'That person is not a member of this business';
    end if;

    update employees set user_id = p_user_id where id = p_employee_id;
    return p_employee_id;
end;
$$;

-- ------------------------------------------------------------
-- 3. THE DIRECTORY
-- ------------------------------------------------------------
-- One read for the staff screen: who is here, where they work, what they are
-- owed, and whether they hold an account.
--
-- Security definer with an explicit admin check, matching 012's policies:
-- reading a payroll needs an org admin, not mere membership.
create or replace function staff_directory(
    p_org_id      uuid,
    p_include_past boolean default false
)
returns table (
    id            uuid,
    full_name     text,
    phone         text,
    role_title    text,
    employment    text,
    kind          text,
    salary        numeric,
    hourly_rate   numeric,
    entity_id     uuid,
    entity_name   text,
    department_id uuid,
    department_name text,
    started_on    date,
    ended_on      date,
    end_reason    text,
    is_active     boolean,
    user_id       uuid,
    account_name  text,
    unpaid_hours  numeric,
    owed          numeric
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not is_org_admin(p_org_id) then
        raise exception 'You cannot read the staff of this business';
    end if;

    return query
    select e.id, e.full_name, e.phone, e.role_title, e.employment, e.kind,
           e.salary, e.hourly_rate,
           e.entity_id, en.name, e.department_id, d.name,
           e.started_on, e.ended_on, e.end_reason, e.is_active,
           e.user_id, pr.full_name,
           coalesce(u.hours, 0), coalesce(u.owed, 0)
    from employees e
    left join entities    en on en.id = e.entity_id
    left join departments d  on d.id  = e.department_id
    left join profiles    pr on pr.id = e.user_id
    left join (
        select s.employee_id,
               sum(s.hours) as hours,
               sum(s.hours * emp.hourly_rate) as owed
        from shifts s
        join employees emp on emp.id = s.employee_id
        where s.org_id = p_org_id and s.payment_id is null
        group by s.employee_id
    ) u on u.employee_id = e.id
    where e.org_id = p_org_id
      and (coalesce(p_include_past, false) or e.is_active)
    order by e.is_active desc, e.full_name;
end;
$$;

-- What the business owes and pays, per month, for a payroll register — the
-- one report an accountant asks for and 012 had no answer to.
create or replace function payroll_summary(
    p_org_id uuid,
    p_from   date default null,
    p_to     date default null
)
returns table (
    employee_id  uuid,
    full_name    text,
    employment   text,
    payments     int,
    paid         numeric,
    hours        numeric
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not is_org_admin(p_org_id) then
        raise exception 'You cannot read the payroll of this business';
    end if;

    return query
    select e.id, e.full_name, e.employment,
           count(sp.id)::int,
           coalesce(sum(sp.amount), 0),
           coalesce((
               select sum(s.hours) from shifts s
               where s.employee_id = e.id
                 and (p_from is null or s.worked_on >= p_from)
                 and (p_to   is null or s.worked_on <= p_to)
           ), 0)
    from employees e
    left join staff_payments sp
           on sp.employee_id = e.id
          and (p_from is null or sp.paid_on >= p_from)
          and (p_to   is null or sp.paid_on <= p_to)
    where e.org_id = p_org_id
    group by e.id, e.full_name, e.employment
    order by e.full_name;
end;
$$;

-- ------------------------------------------------------------
-- 4. GRANTS
-- ------------------------------------------------------------
revoke execute on function update_employee(uuid, text, text, text, text, text, numeric, numeric, uuid, uuid, text, text, text, text, date) from public;
revoke execute on function end_employment(uuid, text, date, text) from public;
revoke execute on function link_employee_account(uuid, uuid) from public;
revoke execute on function staff_directory(uuid, boolean) from public;
revoke execute on function payroll_summary(uuid, date, date) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function update_employee(uuid, text, text, text, text, text, numeric, numeric, uuid, uuid, text, text, text, text, date) to authenticated;
        grant execute on function end_employment(uuid, text, date, text) to authenticated;
        grant execute on function link_employee_account(uuid, uuid) to authenticated;
        grant execute on function staff_directory(uuid, boolean) to authenticated;
        grant execute on function payroll_summary(uuid, date, date) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
