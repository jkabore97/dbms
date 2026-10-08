-- ============================================================
-- test_batch118.sql — the salary said at the invitation (118).
--
-- The claims, for a shop, a farm and an association alike:
--   * P1: an invitation with no salary is claimed as before — no payroll
--     row appears;
--   * the owner says a salary on an invitation; claimed by its code, or by
--     the sign-in sweep, the person's payroll row carries it (permanent,
--     linked to the account, written as the inviter); an unlinked row of
--     the same name is the person's; a row paid by the hour is left alone;
--   * 103's rule: an admin says it for a responsibility below their own,
--     never for an owner's or an equal's invitation; a member who is not
--     an admin, a stranger, a claimed invitation, a negative amount, an
--     unknown period are refused; 0 clears it;
--   * the claim never fails for the salary;
--   * the doors: closed to the street, the trigger to everyone.
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
grant select, insert, update, delete on all tables in schema public to authenticated;
-- Earlier suites hand the app's roles every function: 118 again, so what
-- follows tests its own doors.
\i database/migrations/118_invitation_salary.sql

\set sowner  '''11811811-0000-0000-0000-000000000001'''
\set fowner  '''11811811-0000-0000-0000-000000000002'''
\set aowner  '''11811811-0000-0000-0000-000000000003'''
\set sadmin  '''11811811-0000-0000-0000-000000000004'''
\set clerk   '''11811811-0000-0000-0000-000000000005'''
\set awa     '''11811811-0000-0000-0000-000000000006'''
\set ali     '''11811811-0000-0000-0000-000000000007'''
\set fatou   '''11811811-0000-0000-0000-000000000008'''
\set issa    '''11811811-0000-0000-0000-000000000009'''
\set moussa  '''11811811-0000-0000-0000-00000000000a'''
\set shop    '''11800000-0000-0000-0000-000000000001'''
\set farm    '''11800000-0000-0000-0000-000000000002'''
\set assoc   '''11800000-0000-0000-0000-000000000003'''

insert into auth.users (id, phone, email, raw_user_meta_data, phone_confirmed_at) values
    (:sowner, '+22611801001', null, '{"full_name": "Patronne 118"}',  null),
    (:fowner, '+22611801002', null, '{"full_name": "Fermier 118"}',   null),
    (:aowner, '+22611801003', null, '{"full_name": "Trésorière 118"}', null),
    (:sadmin, '+22611801004', null, '{"full_name": "Admin 118"}',     null),
    (:clerk,  '+22611801005', null, '{"full_name": "Vendeuse 118"}',  null),
    (:awa,    '+22611801006', null, '{"full_name": "Awa 118"}',       null),
    (:ali,    '+22611801007', null, '{"full_name": "Ali 118"}',       now()),
    (:fatou,  '+22611801008', null, '{"full_name": "Fatou 118"}',     null),
    (:issa,   '+22611801009', null, '{"full_name": "Issa 118"}',      null),
    (:moussa, '+22611801010', null, '{"full_name": "Moussa 118"}',    null);
insert into orgs (id, name, slug, profile, default_currency, plan) values
    (:shop,  'Boutique 118', 'boutique-118', 'retail',      'XOF', 'pro'),
    (:farm,  'Ferme 118',    'ferme-118',    'farm',        'XOF', 'pro'),
    (:assoc, 'Entraide 118', 'entraide-118', 'association', 'XOF', 'pro');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :sowner, 'owner',    'org', :shop,  'full'),
    (:shop,  :sadmin, 'admin',    'org', :shop,  'full'),
    (:shop,  :clerk,  'employee', 'org', :shop,  'full'),
    (:farm,  :fowner, 'owner',    'org', :farm,  'full'),
    (:assoc, :aowner, 'owner',    'org', :assoc, 'full');

create or replace function pg_temp.as118(p_who uuid)
returns void
language sql
as $$ select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), false); $$;

create or replace function pg_temp.refused118(p_sql text)
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

-- An invitation written through the app's door, as p_who.
create or replace function pg_temp.invite118(p_who uuid, p_org uuid, p_role text, p_name text, p_phone text)
returns pending_invitations
language plpgsql
as $$
declare v_id uuid; v_row pending_invitations;
begin
    perform pg_temp.as118(p_who);
    select invitation_id into v_id
      from invite_employee(p_org, p_role::role_name, p_name, null, p_phone);
    select * into v_row from pending_invitations where id = v_id;
    return v_row;
end;
$$;

\echo ''
\echo '--- TEST 1: P1 — an invitation with no salary is claimed as before ---'
do $$
declare v_inv pending_invitations;
begin
    v_inv := pg_temp.invite118('11811811-0000-0000-0000-000000000001',
        '11800000-0000-0000-0000-000000000001', 'employee', 'Awa 118', null);
    if v_inv.salary is not null or v_inv.salary_period is not null then
        raise exception 'FAIL: an invitation was born with a salary';
    end if;
    perform pg_temp.as118('11811811-0000-0000-0000-000000000006');
    perform claim_invitation(v_inv.code);
    if not exists (select 1 from memberships
                    where user_id = '11811811-0000-0000-0000-000000000006'
                      and org_id = '11800000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the claim did not let Awa in';
    end if;
    if exists (select 1 from employees
                where org_id = '11800000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: a claim with no salary wrote a payroll row';
    end if;
    raise notice 'PASS: shop — no salary said, the claim lets the person in and writes no payroll row';
end $$;

\echo ''
\echo '--- TEST 2: the owner says the salary; the claim by code writes it (shop, farm, association) ---'
do $$
declare
    v_inv pending_invitations;
    v_emp employees;
    r record;
begin
    for r in select * from (values
        ('11811811-0000-0000-0000-000000000001'::uuid, '11800000-0000-0000-0000-000000000001'::uuid, '11811811-0000-0000-0000-000000000008'::uuid, 'Fatou 118', 60000, 'month'),
        ('11811811-0000-0000-0000-000000000002'::uuid, '11800000-0000-0000-0000-000000000002'::uuid, '11811811-0000-0000-0000-000000000009'::uuid, 'Issa 118',  15000, 'week'),
        ('11811811-0000-0000-0000-000000000003'::uuid, '11800000-0000-0000-0000-000000000003'::uuid, '11811811-0000-0000-0000-00000000000a'::uuid, 'Moussa 118', 2500, 'day'))
        as t(owner, org, who, name, amount, period)
    loop
        v_inv := pg_temp.invite118(r.owner, r.org, 'employee', r.name, null);
        perform pg_temp.as118(r.owner);
        perform set_invitation_salary(v_inv.id, r.amount, r.period);
        select * into v_inv from pending_invitations where id = v_inv.id;
        if v_inv.salary <> r.amount or v_inv.salary_period <> r.period then
            raise exception 'FAIL: the invitation keeps % %', v_inv.salary, v_inv.salary_period;
        end if;
        perform pg_temp.as118(r.who);
        perform claim_invitation(v_inv.code);
        select * into v_emp from employees where org_id = r.org and user_id = r.who;
        if v_emp.id is null or v_emp.kind <> 'permanent' or v_emp.salary <> r.amount
           or v_emp.pay_period <> r.period or v_emp.created_by <> r.owner
           or not v_emp.is_active then
            raise exception 'FAIL: % — the payroll row reads %', r.name, to_jsonb(v_emp);
        end if;
    end loop;
    raise notice 'PASS: shop 60 000/month, farm 15 000/week, association 2 500/day — said on the invitation, written on the claim, linked, permanent, by the inviter';
end $$;

\echo ''
\echo '--- TEST 3: the sign-in sweep; an unlinked row of the same name; an hourly row left alone ---'
do $$
declare
    v_inv pending_invitations;
    v_emp employees;
    v_n   int;
begin
    -- Ali was on the farm's payroll before he had the app.
    insert into employees (org_id, full_name, kind, salary)
    values ('11800000-0000-0000-0000-000000000002', 'Ali 118', 'permanent', 1000);
    v_inv := pg_temp.invite118('11811811-0000-0000-0000-000000000002',
        '11800000-0000-0000-0000-000000000002', 'employee', 'Ali 118', '+22611801007');
    perform pg_temp.as118('11811811-0000-0000-0000-000000000002');
    perform set_invitation_salary(v_inv.id, 40000, 'month');
    perform pg_temp.as118('11811811-0000-0000-0000-000000000007');
    perform claim_my_invitations();
    select count(*) into v_n from employees
     where org_id = '11800000-0000-0000-0000-000000000002' and lower(full_name) like 'ali 118%';
    select * into v_emp from employees
     where org_id = '11800000-0000-0000-0000-000000000002'
       and user_id = '11811811-0000-0000-0000-000000000007';
    if v_n <> 1 or v_emp.salary <> 40000 or v_emp.pay_period <> 'month' then
        raise exception 'FAIL: the sweep: % rows, %', v_n, to_jsonb(v_emp);
    end if;

    -- A row paid by the hour keeps its rate.
    perform pg_temp.as118(null);
    delete from memberships where user_id = '11811811-0000-0000-0000-000000000006';
    insert into employees (org_id, full_name, kind, hourly_rate, user_id)
    values ('11800000-0000-0000-0000-000000000001', 'Awa 118', 'casual', 500,
            '11811811-0000-0000-0000-000000000006');
    v_inv := pg_temp.invite118('11811811-0000-0000-0000-000000000001',
        '11800000-0000-0000-0000-000000000001', 'employee', 'Awa 118', null);
    perform pg_temp.as118('11811811-0000-0000-0000-000000000001');
    perform set_invitation_salary(v_inv.id, 70000, 'month');
    perform pg_temp.as118('11811811-0000-0000-0000-000000000006');
    perform claim_invitation(v_inv.code);
    select * into v_emp from employees
     where org_id = '11800000-0000-0000-0000-000000000001'
       and user_id = '11811811-0000-0000-0000-000000000006';
    if v_emp.kind <> 'casual' or v_emp.hourly_rate <> 500 or v_emp.salary <> 0 then
        raise exception 'FAIL: the hourly row was rewritten: %', to_jsonb(v_emp);
    end if;
    raise notice 'PASS: farm — the sign-in sweep writes it on the row he already had (one row, 40 000/month); shop — a person paid by the hour keeps the rate';
end $$;

\echo ''
\echo '--- TEST 4: who may say it (103), and what ---'
do $$
declare
    v_emp pending_invitations;
    v_mgr pending_invitations;
    v_adm pending_invitations;
    v_msg text;
begin
    -- The shop's admin invites a manager (below them) and says the pay.
    v_mgr := pg_temp.invite118('11811811-0000-0000-0000-000000000004',
        '11800000-0000-0000-0000-000000000001', 'manager', 'Gérant 118', null);
    perform pg_temp.as118('11811811-0000-0000-0000-000000000004');
    perform set_invitation_salary(v_mgr.id, 90000, 'month');
    -- The owner's invitation for another admin: not the admin's to price.
    v_adm := pg_temp.invite118('11811811-0000-0000-0000-000000000001',
        '11800000-0000-0000-0000-000000000001', 'admin', 'Admin bis 118', null);
    perform pg_temp.as118('11811811-0000-0000-0000-000000000004');
    v_msg := pg_temp.refused118(format('select set_invitation_salary(%L, 1000, ''month'')', v_adm.id));
    if v_msg not like 'Seul le propriétaire%' then
        raise exception 'FAIL: an admin priced an equal: %', v_msg;
    end if;
    -- The owner may.
    perform pg_temp.as118('11811811-0000-0000-0000-000000000001');
    perform set_invitation_salary(v_adm.id, 120000, 'month');

    v_emp := pg_temp.invite118('11811811-0000-0000-0000-000000000001',
        '11800000-0000-0000-0000-000000000001', 'employee', 'Caissier 118', null);
    -- A cashier is not an admin; the farm's owner is not the shop's.
    perform pg_temp.as118('11811811-0000-0000-0000-000000000005');
    v_msg := pg_temp.refused118(format('select set_invitation_salary(%L, 1000, ''month'')', v_emp.id));
    if v_msg not like 'Seul un administrateur%' then
        raise exception 'FAIL: a cashier priced an invitation: %', v_msg;
    end if;
    perform pg_temp.as118('11811811-0000-0000-0000-000000000002');
    v_msg := pg_temp.refused118(format('select set_invitation_salary(%L, 1000, ''month'')', v_emp.id));
    if v_msg not like 'Seul un administrateur%' then
        raise exception 'FAIL: another business priced it: %', v_msg;
    end if;
    perform pg_temp.as118(null);
    v_msg := pg_temp.refused118(format('select set_invitation_salary(%L, 1000, ''month'')', v_emp.id));
    if v_msg not like 'Connectez-vous%' then
        raise exception 'FAIL: nobody priced it: %', v_msg;
    end if;
    -- The words.
    perform pg_temp.as118('11811811-0000-0000-0000-000000000001');
    v_msg := pg_temp.refused118(format('select set_invitation_salary(%L, -5, ''month'')', v_emp.id));
    if v_msg not like 'Le salaire doit%' then
        raise exception 'FAIL: a negative salary: %', v_msg;
    end if;
    v_msg := pg_temp.refused118(format('select set_invitation_salary(%L, 5, ''year'')', v_emp.id));
    if v_msg not like 'Période inconnue%' then
        raise exception 'FAIL: an unknown period: %', v_msg;
    end if;
    perform set_invitation_salary(v_emp.id, 30000, 'month');
    perform set_invitation_salary(v_emp.id, 0, 'month');
    if exists (select 1 from pending_invitations
                where id = v_emp.id and (salary is not null or salary_period is not null)) then
        raise exception 'FAIL: 0 did not clear it';
    end if;
    -- A claimed invitation is the team's now.
    v_msg := pg_temp.refused118(format('select set_invitation_salary(%L, 1000, ''month'')',
        (select id from pending_invitations where claimed_at is not null
          and org_id = '11800000-0000-0000-0000-000000000001' limit 1)));
    if v_msg not like 'Cette invitation a déjà été utilisée%' then
        raise exception 'FAIL: a claimed invitation was priced: %', v_msg;
    end if;
    perform pg_temp.as118(null);
    raise notice 'PASS: an admin prices a manager''s invitation, not an equal''s (the owner does); a cashier, another business, nobody refused; negative and unknown period refused; 0 clears; a claimed invitation is Équipe''s';
end $$;

\echo ''
\echo '--- TEST 5: the claim never fails for the salary ---'
begin;
do $$
declare v_inv pending_invitations;
begin
    insert into auth.users (id, phone, raw_user_meta_data)
    values ('11811811-0000-0000-0000-0000000000bb', '+22611801099', '{"full_name": "Kadi 118"}');
    v_inv := pg_temp.invite118('11811811-0000-0000-0000-000000000003',
        '11800000-0000-0000-0000-000000000003', 'employee', 'Kadi 118', null);
    perform pg_temp.as118('11811811-0000-0000-0000-000000000003');
    perform set_invitation_salary(v_inv.id, 10000, 'month');
    perform pg_temp.as118(null);
    alter table employees add constraint b118_broken check (salary < 1) not valid;
    perform pg_temp.as118('11811811-0000-0000-0000-0000000000bb');
    perform claim_invitation(v_inv.code);
    if not exists (select 1 from memberships
                    where user_id = '11811811-0000-0000-0000-0000000000bb') then
        raise exception 'FAIL: a broken payroll kept Kadi out';
    end if;
    if exists (select 1 from employees where user_id = '11811811-0000-0000-0000-0000000000bb') then
        raise exception 'FAIL: the broken write landed';
    end if;
    raise notice 'PASS: association — a payroll that cannot be written leaves the person in';
end $$;
rollback;
select pg_temp.as118(null);

\echo ''
\echo '--- TEST 6: the doors ---'
do $$
begin
    if has_function_privilege('anon', 'set_invitation_salary(uuid, numeric, text)', 'execute') then
        raise exception 'FAIL: the street may price an invitation';
    end if;
    if not has_function_privilege('authenticated', 'set_invitation_salary(uuid, numeric, text)', 'execute') then
        raise exception 'FAIL: the app cannot reach the door';
    end if;
    if has_function_privilege('authenticated', 'trg_invitation_salary()', 'execute')
       or has_function_privilege('anon', 'trg_invitation_salary()', 'execute') then
        raise exception 'FAIL: the trigger is a door';
    end if;
    raise notice 'PASS: set_invitation_salary for signed-in callers only (each checked inside), the trigger for nobody';
end $$;
