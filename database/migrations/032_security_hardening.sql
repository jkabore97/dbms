-- ============================================================
-- 032_security_hardening.sql — closing the holes a full audit found.
--
-- One migration, several unrelated fixes, bundled because they share a
-- single theme: a SECURITY DEFINER function or a permissive grant that let a
-- caller do something the table's own RLS would have refused. Each is small;
-- together they are the difference between "RLS is the security model" being
-- true and being nearly true.
--
-- The headline is the first one. The rest are the same shape, found while
-- looking for more of it.
-- ============================================================

-- ------------------------------------------------------------
-- 1. profiles.is_platform_admin — the one that mattered
--
-- THE HOLE. `is_platform_admin` is a column on `profiles`, and the profiles
-- UPDATE policy is `with check (id = auth.uid())`. RLS gates rows, never
-- columns, so that policy — correctly — lets a person edit their own row, and
-- therefore lets them set ANY column on it, this flag included. One line from
-- any signed-in account:
--
--     update profiles set is_platform_admin = true where id = auth.uid();
--
-- and `is_org_member`, `is_org_admin`, `can_write_org` and `my_org_ids` all
-- start returning true for every org on the platform (see 010). Total
-- multi-tenant compromise from a free sign-up.
--
-- TWO LAYERS, because either alone is not enough on Supabase:
--
--   Layer 1 — column privileges. A table-wide GRANT UPDATE (which is what
--   Supabase hands `authenticated` by default) covers every column, so a bare
--   REVOKE of one column does nothing against it. The fix is to drop the
--   table-wide UPDATE and re-grant only the personal columns a person owns.
--   After this the attack statement fails with "permission denied for column
--   is_platform_admin" before RLS is even consulted, and — the reason to
--   prefer a column list over a blocklist — any column added later is
--   non-writable until someone deliberately adds it here. Fail-closed.
--
--   Layer 2 — a guard trigger. Several Supabase dashboard actions re-run
--   GRANT ALL and would silently undo Layer 1. A trigger survives that: it
--   refuses to let the flag change unless the caller is already a platform
--   admin, or there is no JWT at all (the trusted server / SQL-editor context
--   that seeds the very first admin, and the only place the flag is ever
--   legitimately set — nothing in the app writes it).
-- ------------------------------------------------------------

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Drop the table-wide UPDATE so the column grant below is the whole of
        -- what `authenticated` may write.
        execute 'revoke update on profiles from authenticated';
        execute 'grant update (full_name, first_name, middle_name, last_name, '
             || 'date_of_birth, title, phone, preferred_locale) '
             || 'on profiles to authenticated';
    end if;
    -- anon can never satisfy id = auth.uid() (auth.uid() is null for it), so
    -- this only removes a privilege it could not use — but leaving it granted
    -- is the kind of thing a future policy change turns into a hole.
    if exists (select 1 from pg_roles where rolname = 'anon') then
        execute 'revoke update on profiles from anon';
    end if;
end $$;

create or replace function guard_is_platform_admin()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_caller uuid := auth.uid();
    v_becoming boolean;
begin
    -- Did this statement try to grant or change platform access?
    if tg_op = 'INSERT' then
        v_becoming := coalesce(new.is_platform_admin, false);
    else
        v_becoming := new.is_platform_admin is distinct from old.is_platform_admin;
    end if;

    if v_becoming then
        -- No JWT: the trusted context that seeds the first admin. A signed-in
        -- caller must already hold the flag to touch it — so nobody can hand
        -- it to themselves.
        if v_caller is not null
           and not exists (select 1 from profiles
                           where id = v_caller and is_platform_admin) then
            raise exception 'Only a platform administrator can change platform access'
                using errcode = 'insufficient_privilege';
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_guard_is_platform_admin on profiles;
create trigger trg_guard_is_platform_admin
    before insert or update on profiles
    for each row execute function guard_is_platform_admin();

-- ------------------------------------------------------------
-- 2. receive_products — the membership check on the zero-cost path
--
-- The only authorisation was inside record_entry(), which this function calls
-- ONLY when the delivery has a cost (`if v_cost > 0`). A delivery with no cost
-- recorded — a normal thing, stock arriving on credit — skipped it and updated
-- another business's product counts and wrote a stock_receipts row with no
-- gate, bypassing that table's own `can_write_org` insert policy. Assert it
-- up front, on every path. Everything else is 016 verbatim.
-- ------------------------------------------------------------

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
    v_actor    uuid := auth.uid();
    v_name     text;
    v_cost     numeric;
    v_entry    uuid;
    v_existing stock_receipts%rowtype;
begin
    if p_quantity is null or p_quantity <= 0 then
        raise exception 'A delivery needs a quantity';
    end if;

    -- SECURITY (032): the gate that used to exist only for priced deliveries.
    if not can_write_org(p_org_id) then
        raise exception 'You cannot receive stock for this business';
    end if;

    if p_client_uuid is not null then
        select * into v_existing from stock_receipts
        where org_id = p_org_id and client_uuid = p_client_uuid;
        if found then
            return v_existing.entry_id;
        end if;
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

    insert into stock_receipts (
        org_id, product_id, quantity, unit_cost, expires_on,
        entry_id, client_uuid, device_id, received_at, received_by
    )
    values (
        p_org_id, p_product_id, p_quantity, v_cost, p_expires_on,
        v_entry, p_client_uuid, p_device_id, p_occurred_at, v_actor
    );

    return v_entry;
end;
$$;

-- ------------------------------------------------------------
-- 3. pay_employee — wages are admin-only
--
-- staff_payments' insert policy is is_org_admin, deliberately stricter than
-- can_write_org because "wages are the most sensitive numbers in a small
-- business" (012). But this definer function was gated only by record_entry's
-- can_write_org, so any non-observer — a cashier, an employee — could record
-- staff payments and post the salary entry, including paying themselves.
-- Assert the table's own rule. Otherwise 012 verbatim.
-- ------------------------------------------------------------

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

    -- SECURITY (032): match staff_payments' own is_org_admin insert policy.
    if not is_org_admin(p_org_id) then
        raise exception 'Only an administrator can record staff payments';
    end if;

    if p_client_uuid is not null then
        select id into v_existing from staff_payments
        where org_id = p_org_id and client_uuid = p_client_uuid;
        if v_existing is not null then
            return v_existing;
        end if;
    end if;

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
-- 4. record_shift — a privileged write with no membership check
--
-- Definer, and it checked only that the employee belonged to the org, never
-- that the CALLER did. Anyone who knew an employee id could log shifts into a
-- business they have no part in, bypassing the shifts insert policy. Assert
-- membership. Otherwise 012 verbatim.
-- ------------------------------------------------------------

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

    -- SECURITY (032): the shifts insert policy is can_write_org; assert it.
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record shifts for this business';
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

-- ------------------------------------------------------------
-- 5. record_return — assert membership up front
--
-- record_entry() enforces can_write_org for a return that posts money, but a
-- zero-total return posts none and reached no check while still updating
-- stock. Same shape as receive_products. Rather than restate the whole of
-- 029, the guard is added by CREATE OR REPLACE with the body carried over.
-- ------------------------------------------------------------

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

    -- SECURITY (032): a zero-total return posts no entry and so met no gate.
    if not can_write_org(v_org) then
        raise exception 'You cannot record a return for this business';
    end if;

    if v_kind = 'return' then
        raise exception 'That is already a return';
    end if;
    if v_method = 'credit' then
        raise exception 'A credit sale is settled in the carnet, not by a return';
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
-- 6. notifications — a recipient may mark read, nothing more
--
-- The UPDATE policy checks `recipient_id = auth.uid()`, which — being row
-- level — let a recipient rewrite the message, kind or org_id of their own
-- notifications, not merely the read timestamp the feature intends. Same
-- column-grant treatment as profiles: read_at only.
-- ------------------------------------------------------------

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        execute 'revoke update on notifications from authenticated';
        execute 'grant update (read_at) on notifications to authenticated';
    end if;
end $$;

-- ------------------------------------------------------------
-- 7. feature_access — fail closed for an anonymous caller
--
-- It returned 'edit' when auth.uid() is null. Nothing reachable depends on
-- that (every caller pairs it with can_write_org, which an anon fails), but a
-- permission function whose most-open answer is its answer for "nobody signed
-- in" is a landmine for the next policy that forgets the pairing. 'hidden'.
-- Otherwise 031 verbatim.
-- ------------------------------------------------------------

create or replace function feature_access(p_org_id uuid, p_feature text)
returns text
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_roles  text[];
    v_tier   text;
    v_access text;
begin
    if auth.uid() is null then
        return 'hidden';
    end if;

    select array_agg(distinct role) into v_roles
      from memberships
     where org_id = p_org_id and user_id = auth.uid();

    if v_roles is null then
        return 'hidden';
    end if;
    if v_roles && array['owner', 'super_admin', 'admin'] then
        return 'edit';
    end if;

    v_tier := case
        when v_roles && array['manager', 'supervisor'] then 'supervisor'
        else 'employee'
    end;

    select access into v_access
      from org_feature_rules
     where org_id = p_org_id and tier = v_tier and feature = p_feature;

    return coalesce(v_access,
        case when p_feature = 'reports' then 'view' else 'edit' end);
end;
$$;

notify pgrst, 'reload schema';
