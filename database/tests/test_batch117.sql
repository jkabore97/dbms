-- ============================================================
-- test_batch117.sql — the carnet's due date and the repayment by
-- customer (117), for a shop, a farm and an association alike.
--
-- The claims:
--   * P1: installed, every debt reads no date, debt_dates answers
--     nothing, and the carnet's two reads (104's, untouched) answer the
--     same rows, amounts and order as 104's own text;
--   * set_debt_due: a sum on credit dated by its debt id, a credit sale
--     by its client_uuid (the outbox's way), cleared with null; a sale
--     that is not there dates nothing and answers null; a debt that is
--     not there, another business's debt, the debt and the sale both or
--     neither, an observer, somebody else's name — each refused;
--   * debt_dates says them: each open debt that has a date, with its
--     customer, earliest first — paid off, it is no longer said;
--   * repay_customer: oldest debt first, slice by slice, the books
--     balanced; the same client_uuid twice moves nothing; never past what
--     is owed, never for a customer who owes nothing, never zero;
--   * the doors: signed-in people only, never the street; set_debt_due
--     DEFINER (no update policy on debts), repay_customer INVOKER (every
--     write is 024's record_debt_payment), both with a search_path.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
-- The roles exist now: 117 again, so its own grants are what is tested.
\i database/migrations/117_entry_flows.sql

\echo ''
\echo '--- TEST 1: the doors — signed-in people only, never the street ---'
do $$
declare
    f text;
begin
    foreach f in array array[
        'set_debt_due(uuid, date, uuid, uuid, uuid)',
        'repay_customer(uuid, uuid, numeric, text, uuid, uuid)',
        'debt_dates(uuid)']
    loop
        if has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: % is open to the street', f;
        end if;
        if not has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: % is closed to a signed-in person', f;
        end if;
        if not exists (select 1 from pg_proc where oid = f::regprocedure
                        and proconfig::text like '%search_path%') then
            raise exception 'FAIL: % has no search_path', f;
        end if;
    end loop;
    if not (select prosecdef from pg_proc where oid = 'set_debt_due(uuid, date, uuid, uuid, uuid)'::regprocedure)
       or (select prosecdef from pg_proc where oid = 'repay_customer(uuid, uuid, numeric, text, uuid, uuid)'::regprocedure)
       or (select prosecdef from pg_proc where oid = 'debt_dates(uuid)'::regprocedure) then
        raise exception 'FAIL: definer/invoker is not as designed';
    end if;
    raise notice 'PASS: 3 doors for signed-in people only, each with its search_path; set_debt_due DEFINER, the rest INVOKER';
end $$;

-- What follows is about behaviour: the app's role gets the tables and the
-- functions the carnet already uses, as the earlier suites do.
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- 089's earned locks are proven elsewhere; open them for these fixtures.
create temp table b117_saved as
    select key, value from platform_settings where key = 'path_gates_open';
update platform_settings set value = '1' where key = 'path_gates_open';

\set shopper  '''11711711-0000-0000-0000-000000000001'''
\set farmer   '''11711711-0000-0000-0000-000000000002'''
\set treas    '''11711711-0000-0000-0000-000000000003'''
\set watcher  '''11711711-0000-0000-0000-000000000004'''
\set outsider '''11711711-0000-0000-0000-000000000005'''
\set shop     '''11700000-0000-0000-0000-000000000001'''
\set farm     '''11700000-0000-0000-0000-000000000002'''
\set assoc    '''11700000-0000-0000-0000-000000000003'''
\set other    '''11700000-0000-0000-0000-000000000004'''

insert into auth.users (id, phone, raw_user_meta_data) values
    (:shopper,  '+22611701001', '{"full_name": "Boutiquière 117"}'),
    (:farmer,   '+22611701002', '{"full_name": "Fermier 117"}'),
    (:treas,    '+22611701003', '{"full_name": "Trésorière 117"}'),
    (:watcher,  '+22611701004', '{"full_name": "Observateur 117"}'),
    (:outsider, '+22611701005', '{"full_name": "Voisin 117"}');
insert into orgs (id, name, slug, profile, default_currency) values
    (:shop,  'Boutique 117', 'boutique-117', 'retail',      'XOF'),
    (:farm,  'Ferme 117',    'ferme-117',    'farm',        'XOF'),
    (:assoc, 'Entraide 117', 'entraide-117', 'association', 'XOF'),
    (:other, 'Ailleurs 117', 'ailleurs-117', 'retail',      'XOF');
insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:shop,  :shopper,  'owner',    'org', :shop),
    (:shop,  :watcher,  'observer', 'org', :shop),
    (:farm,  :farmer,   'owner',    'org', :farm),
    (:assoc, :treas,    'owner',    'org', :assoc),
    (:other, :outsider, 'owner',    'org', :other);
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active) values
    ('117aaaaa-0000-0000-0000-000000000001', :shop, 'Riz 117',   1000, 800, 10, true),
    ('117aaaaa-0000-0000-0000-000000000002', :farm, 'Œufs 117',  2500,   0, 10, true);

-- The caller, named the way PostgREST names them.
create or replace function pg_temp.as117(p_who uuid)
returns void
language sql
as $$ select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true); $$;

create or replace function pg_temp.refused117(p_sql text)
returns text
language plpgsql
as $$
begin
    execute p_sql;
    return '(went through)';
exception when others then
    return sqlerrm;
end;
$$;

-- 104's carnet read, word for word, to compare against (P1).
create or replace function pg_temp.carnet104(p_org_id uuid)
returns table (customer_id uuid, customer_name text, phone text,
               total_owed numeric, oldest_debt timestamptz, open_debts int)
language sql
as $$
    select c.id, c.name, c.phone,
           sum(d.amount - coalesce(p.paid, 0)) as total_owed,
           min(d.occurred_at) filter (where d.amount > coalesce(p.paid, 0)),
           count(*) filter (where d.amount > coalesce(p.paid, 0))::int
      from debts d
      join customers c on c.id = d.customer_id
      left join lateral (
          select sum(amount) as paid from debt_payments where debt_id = d.id
      ) p on true
     where d.org_id = p_org_id
     group by c.id, c.name, c.phone
    having sum(d.amount - coalesce(p.paid, 0)) > 0
     order by min(d.occurred_at) filter (where d.amount > coalesce(p.paid, 0));
$$;

-- The fixtures every test below starts from: for each kind, a sum on
-- credit (yesterday) and, for a shop and a farm, a credit sale (today),
-- the shop's customer part-paid already.
create or replace function pg_temp.fixtures117()
returns void
language plpgsql
as $$
begin
    perform pg_temp.as117('11711711-0000-0000-0000-000000000001');
    perform record_credit_sale('11700000-0000-0000-0000-000000000001', 'Awa 117', 3000, 'Prêt',
        p_client_uuid => 'b1170000-0000-0000-0000-000000000001', p_occurred_at => now() - interval '2 days');
    perform record_sale('11700000-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', '117aaaaa-0000-0000-0000-000000000001',
            'name', 'Riz 117', 'quantity', 2, 'unit_price', 1000)),
        p_method => 'credit', p_customer_name => 'Awa 117',
        p_client_uuid => 'c1170000-0000-0000-0000-000000000001');
    perform record_debt_payment(
        (select id from debts where client_uuid = 'b1170000-0000-0000-0000-000000000001'), 500,
        p_client_uuid => 'e1170000-0000-0000-0000-000000000001');

    perform pg_temp.as117('11711711-0000-0000-0000-000000000002');
    perform record_credit_sale('11700000-0000-0000-0000-000000000002', 'Hôtel 117', 4000, 'Aliment avancé',
        p_client_uuid => 'b1170000-0000-0000-0000-000000000002', p_occurred_at => now() - interval '1 day');
    perform record_sale('11700000-0000-0000-0000-000000000002',
        jsonb_build_array(jsonb_build_object('product_id', '117aaaaa-0000-0000-0000-000000000002',
            'name', 'Œufs 117', 'quantity', 1, 'unit_price', 2500)),
        p_method => 'credit', p_customer_name => 'Hôtel 117',
        p_client_uuid => 'c1170000-0000-0000-0000-000000000002');

    perform pg_temp.as117('11711711-0000-0000-0000-000000000003');
    perform record_credit_sale('11700000-0000-0000-0000-000000000003', 'Membre 117', 1500, 'Cotisation de mars',
        p_client_uuid => 'b1170000-0000-0000-0000-000000000003');
end;
$$;

\echo ''
\echo '--- TEST 2: installed, every debt reads no date and the carnet reads as 104 (P1, each kind) ---'
begin;
select pg_temp.fixtures117();
do $$
declare
    o uuid;
    v_new int;
    v_old int;
begin
    if exists (select 1 from debts where due_on is not null) then
        raise exception 'FAIL: a debt has a date nobody gave';
    end if;
    foreach o in array array['11700000-0000-0000-0000-000000000001',
                             '11700000-0000-0000-0000-000000000002',
                             '11700000-0000-0000-0000-000000000003']::uuid[]
    loop
        select count(*) into v_old from pg_temp.carnet104(o);
        select count(*) into v_new from customer_debts(o);
        if v_old = 0 or v_old <> v_new or exists (
            (select row_number() over (), * from customer_debts(o))
            except
            (select row_number() over (), * from pg_temp.carnet104(o))) then
            raise exception 'FAIL: the carnet of % reads differently from 104', o;
        end if;
        if exists (select 1 from debt_dates(o)) then
            raise exception 'FAIL: a date appeared in the carnet of %', o;
        end if;
    end loop;
    if (select count(*) from debts_of_customer('11700000-0000-0000-0000-000000000001',
            (select id from customers where org_id = '11700000-0000-0000-0000-000000000001' and name = 'Awa 117'))
         where due_on is null) <> 2 then
        raise exception 'FAIL: one customer''s page lost a debt or gained a date';
    end if;
    raise notice 'PASS: shop, farm and association — no date anywhere, the carnet the same rows, amounts and order as 104';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: a sum dated by its debt, a credit sale by its client_uuid, cleared with null ---'
begin;
select pg_temp.fixtures117();
do $$
declare
    v_debt uuid;
    v_got  uuid;
    v_cust uuid;
begin
    -- Each kind's sum on credit, by its id.
    perform pg_temp.as117('11711711-0000-0000-0000-000000000003');
    select id into v_debt from debts where client_uuid = 'b1170000-0000-0000-0000-000000000003';
    v_got := set_debt_due('11700000-0000-0000-0000-000000000003', current_date + 30, p_debt_id => v_debt);
    if v_got is distinct from v_debt
       or (select due_on from debts where id = v_debt) <> current_date + 30 then
        raise exception 'FAIL: the association''s sum was not dated';
    end if;

    -- A shop's and a farm's credit sale, by the sale's client_uuid, the
    -- way the outbox sends it (p_recorded_by added).
    perform pg_temp.as117('11711711-0000-0000-0000-000000000001');
    v_got := set_debt_due('11700000-0000-0000-0000-000000000001', current_date + 7,
        p_sale_client_uuid => 'c1170000-0000-0000-0000-000000000001',
        p_recorded_by => '11711711-0000-0000-0000-000000000001');
    if v_got is null or (select due_on from debts where id = v_got) <> current_date + 7
       or (select sale_id from debts where id = v_got) is null then
        raise exception 'FAIL: the shop''s credit sale was not dated';
    end if;
    perform pg_temp.as117('11711711-0000-0000-0000-000000000002');
    v_got := set_debt_due('11700000-0000-0000-0000-000000000002', current_date - 3,
        p_sale_client_uuid => 'c1170000-0000-0000-0000-000000000002');
    if v_got is null or (select due_on from debts where id = v_got) <> current_date - 3 then
        raise exception 'FAIL: the farm''s credit sale was not dated';
    end if;
    v_debt := (select id from debts where client_uuid = 'b1170000-0000-0000-0000-000000000002');
    perform set_debt_due('11700000-0000-0000-0000-000000000002', current_date + 10, p_debt_id => v_debt);

    -- debt_dates says them, earliest first, with the customer.
    select customer_id into v_cust from customer_debts('11700000-0000-0000-0000-000000000002');
    if (select array_agg(due_on) from debt_dates('11700000-0000-0000-0000-000000000002'))
       <> array[current_date - 3, current_date + 10]
       or exists (select 1 from debt_dates('11700000-0000-0000-0000-000000000002') where customer_id <> v_cust) then
        raise exception 'FAIL: debt_dates does not say each date, earliest first, with its customer';
    end if;
    if (select count(*) from debt_dates('11700000-0000-0000-0000-000000000001')) <> 1
       or (select count(*) from debt_dates('11700000-0000-0000-0000-000000000003')) <> 1 then
        raise exception 'FAIL: one business reads another''s dates, or loses its own';
    end if;

    -- Cleared with null.
    perform set_debt_due('11700000-0000-0000-0000-000000000002', null, p_debt_id => v_debt);
    if (select due_on from debts where id = v_debt) is not null then
        raise exception 'FAIL: null did not clear the date';
    end if;

    -- A sale that is not there (refused by 101, or never sent): nothing
    -- dated, null answered, no error for the outbox to retry for ever.
    if set_debt_due('11700000-0000-0000-0000-000000000002', current_date,
           p_sale_client_uuid => 'c1170000-0000-0000-0000-0000000000ff') is not null then
        raise exception 'FAIL: a missing sale dated something';
    end if;
    raise notice 'PASS: shop and farm credit sales dated by client_uuid, each kind''s sum by its id; debt_dates says them; null clears; a missing sale answers null';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: dating refused where it must be ---'
begin;
select pg_temp.fixtures117();
do $$
declare
    v_shop_debt uuid := (select id from debts where client_uuid = 'b1170000-0000-0000-0000-000000000001');
    m text;
begin
    perform pg_temp.as117('11711711-0000-0000-0000-000000000005');
    m := pg_temp.refused117(format($q$select set_debt_due('11700000-0000-0000-0000-000000000001', current_date, p_debt_id => %L)$q$, v_shop_debt));
    if m not like 'You cannot record entries%' then
        raise exception 'FAIL: an outsider dated a shop''s debt (%)', m;
    end if;
    m := pg_temp.refused117(format($q$select set_debt_due('11700000-0000-0000-0000-000000000004', current_date, p_debt_id => %L)$q$, v_shop_debt));
    if m <> 'Ce crédit est introuvable.' then
        raise exception 'FAIL: another business''s debt was dated through its own org (%)', m;
    end if;
    perform pg_temp.as117('11711711-0000-0000-0000-000000000004');
    m := pg_temp.refused117(format($q$select set_debt_due('11700000-0000-0000-0000-000000000001', current_date, p_debt_id => %L)$q$, v_shop_debt));
    if m not like 'You cannot record entries%' then
        raise exception 'FAIL: an observer dated a debt (%)', m;
    end if;
    perform pg_temp.as117('11711711-0000-0000-0000-000000000001');
    m := pg_temp.refused117($q$select set_debt_due('11700000-0000-0000-0000-000000000001', current_date)$q$);
    if m not like '%one of the two%' then
        raise exception 'FAIL: neither debt nor sale was accepted (%)', m;
    end if;
    m := pg_temp.refused117(format($q$select set_debt_due('11700000-0000-0000-0000-000000000001', current_date, p_debt_id => %L, p_sale_client_uuid => 'c1170000-0000-0000-0000-000000000001')$q$, v_shop_debt));
    if m not like '%one of the two%' then
        raise exception 'FAIL: both debt and sale were accepted (%)', m;
    end if;
    m := pg_temp.refused117(format($q$select set_debt_due('11700000-0000-0000-0000-000000000001', current_date, p_debt_id => %L)$q$, gen_random_uuid()));
    if m <> 'Ce crédit est introuvable.' then
        raise exception 'FAIL: a debt that is not there was accepted (%)', m;
    end if;
    m := pg_temp.refused117(format($q$select set_debt_due('11700000-0000-0000-0000-000000000001', current_date, p_debt_id => %L, p_recorded_by => '11711711-0000-0000-0000-000000000002')$q$, v_shop_debt));
    if m not like '%on behalf of another user%' then
        raise exception 'FAIL: dated in somebody else''s name (%)', m;
    end if;
    perform pg_temp.as117(null);
    m := pg_temp.refused117(format($q$select set_debt_due('11700000-0000-0000-0000-000000000001', current_date, p_debt_id => %L)$q$, v_shop_debt));
    if m not like '%signed-in caller%' then
        raise exception 'FAIL: nobody dated a debt (%)', m;
    end if;
    if exists (select 1 from debts where due_on is not null) then
        raise exception 'FAIL: a refused call left a date';
    end if;
    raise notice 'PASS: an outsider, another business''s debt, an observer, neither or both, a missing debt, another''s name, nobody — each refused, nothing dated';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: a repayment by customer — oldest first, books balanced, once ---'
begin;
select pg_temp.fixtures117();
do $$
declare
    v_awa   uuid := (select id from customers where org_id = '11700000-0000-0000-0000-000000000001' and name = 'Awa 117');
    v_left  numeric;
    v_paid  numeric[];
    v_d numeric; v_c numeric;
    v_n int;
begin
    perform pg_temp.as117('11711711-0000-0000-0000-000000000001');
    -- The loan has a date; paid off below, it is no longer said.
    perform set_debt_due('11700000-0000-0000-0000-000000000001', current_date,
        p_debt_id => (select id from debts where client_uuid = 'b1170000-0000-0000-0000-000000000001'));
    -- Awa owes 2500 on the loan (3000 − 500) and 2000 on the rice: 3000
    -- pays the loan off and 500 of the rice.
    v_left := repay_customer('11700000-0000-0000-0000-000000000001', v_awa, 3000,
        p_client_uuid => 'f1170000-0000-0000-0000-000000000001');
    if v_left <> 1500 then
        raise exception 'FAIL: % left instead of 1500', v_left;
    end if;
    select array_agg(paid order by occurred_at) into v_paid
      from debts_of_customer('11700000-0000-0000-0000-000000000001', v_awa);
    if v_paid <> array[3000, 500]::numeric[] then
        raise exception 'FAIL: not oldest first (%)', v_paid;
    end if;
    if exists (select 1 from debt_dates('11700000-0000-0000-0000-000000000001')) then
        raise exception 'FAIL: a paid-off debt''s date is still said';
    end if;
    select sum(l.debit), sum(l.credit) into v_d, v_c
      from journal_lines l join journal_entries e on e.id = l.journal_entry_id
     where e.org_id = '11700000-0000-0000-0000-000000000001';
    if v_d <> v_c then
        raise exception 'FAIL: unbalanced books (% / %)', v_d, v_c;
    end if;

    -- The same uuid again (a retried call): nothing moves.
    select count(*) into v_n from debt_payments where org_id = '11700000-0000-0000-0000-000000000001';
    v_left := repay_customer('11700000-0000-0000-0000-000000000001', v_awa, 3000,
        p_client_uuid => 'f1170000-0000-0000-0000-000000000001');
    if v_left <> 1500 or (select count(*) from debt_payments
                           where org_id = '11700000-0000-0000-0000-000000000001') <> v_n then
        raise exception 'FAIL: the same repayment counted twice';
    end if;

    -- Never past what is owed; never zero.
    if pg_temp.refused117(format($q$select repay_customer('11700000-0000-0000-0000-000000000001', %L, 1501)$q$, v_awa))
       not like 'Ce paiement (1501) dépasse ce qui reste dû (1500)' then
        raise exception 'FAIL: paid past what is owed';
    end if;
    if pg_temp.refused117(format($q$select repay_customer('11700000-0000-0000-0000-000000000001', %L, 0)$q$, v_awa))
       not like 'Amount must be greater than zero%' then
        raise exception 'FAIL: zero was accepted';
    end if;
    -- The rest, and then nothing is owed.
    if repay_customer('11700000-0000-0000-0000-000000000001', v_awa, 1500) <> 0 then
        raise exception 'FAIL: the rest did not clear the customer';
    end if;
    if pg_temp.refused117(format($q$select repay_customer('11700000-0000-0000-0000-000000000001', %L, 100)$q$, v_awa))
       <> 'Ce client ne doit rien.' then
        raise exception 'FAIL: a customer who owes nothing was paid';
    end if;
    if exists (select 1 from customer_debts('11700000-0000-0000-0000-000000000001')) then
        raise exception 'FAIL: the customer is still in the carnet';
    end if;

    -- The farm and the association, one call each.
    perform pg_temp.as117('11711711-0000-0000-0000-000000000002');
    if repay_customer('11700000-0000-0000-0000-000000000002',
           (select id from customers where org_id = '11700000-0000-0000-0000-000000000002' and name = 'Hôtel 117'),
           5000, 'mobile_money') <> 1500 then
        raise exception 'FAIL: the farm''s repayment';
    end if;
    if (select count(*) from debt_payments where org_id = '11700000-0000-0000-0000-000000000002' and method = 'mobile_money') <> 2 then
        raise exception 'FAIL: the farm''s method was not kept on each slice';
    end if;
    perform pg_temp.as117('11711711-0000-0000-0000-000000000003');
    if repay_customer('11700000-0000-0000-0000-000000000003',
           (select id from customers where org_id = '11700000-0000-0000-0000-000000000003' and name = 'Membre 117'),
           1500) <> 0 then
        raise exception 'FAIL: the association''s repayment';
    end if;
    raise notice 'PASS: shop 3000 → the loan then 500 of the rice, books balanced, once only; past it, zero, nothing owed refused; farm (mobile money, two slices) and association too';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: repayment refused where it must be ---'
begin;
select pg_temp.fixtures117();
do $$
declare
    v_awa uuid := (select id from customers where org_id = '11700000-0000-0000-0000-000000000001' and name = 'Awa 117');
    m text;
begin
    perform pg_temp.as117('11711711-0000-0000-0000-000000000005');
    m := pg_temp.refused117(format($q$select repay_customer('11700000-0000-0000-0000-000000000001', %L, 100)$q$, v_awa));
    if m not like 'You cannot record entries%' then
        raise exception 'FAIL: an outsider repaid (%)', m;
    end if;
    -- Through its own business, another business's customer owes nothing.
    m := pg_temp.refused117(format($q$select repay_customer('11700000-0000-0000-0000-000000000004', %L, 100)$q$, v_awa));
    if m <> 'Ce client ne doit rien.' then
        raise exception 'FAIL: another business''s customer was repaid (%)', m;
    end if;
    perform pg_temp.as117('11711711-0000-0000-0000-000000000004');
    m := pg_temp.refused117(format($q$select repay_customer('11700000-0000-0000-0000-000000000001', %L, 100)$q$, v_awa));
    if m not like 'You cannot record entries%' then
        raise exception 'FAIL: an observer repaid (%)', m;
    end if;
    perform pg_temp.as117('11711711-0000-0000-0000-000000000001');
    m := pg_temp.refused117(format($q$select repay_customer('11700000-0000-0000-0000-000000000001', %L, 100, p_recorded_by => '11711711-0000-0000-0000-000000000002')$q$, v_awa));
    if m not like '%on behalf of another user%' then
        raise exception 'FAIL: repaid in somebody else''s name (%)', m;
    end if;
    if (select count(*) from debt_payments where org_id = '11700000-0000-0000-0000-000000000001') <> 1 then
        raise exception 'FAIL: a refused repayment left a payment';
    end if;
    raise notice 'PASS: an outsider, another business, an observer, another''s name — refused, nothing paid';
end $$;
rollback;

update platform_settings s set value = b.value from b117_saved b where s.key = b.key;
