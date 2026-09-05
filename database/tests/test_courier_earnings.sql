-- ============================================================
-- test_courier_earnings.sql — what today paid (062).
-- Phone block 34.
--
-- The claims: an approved courier reads three rows about themselves —
-- today, this week, this month — counting only courses they delivered,
-- on the day they finished them; another courier's courses and their own
-- undelivered ones do not count; the fee and the kilometres add up; and a
-- person who is not an approved courier is refused.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''34343434-0000-0000-0000-000000000001'''
\set customer '''34343434-0000-0000-0000-000000000002'''
\set moussa   '''34343434-0000-0000-0000-000000000003'''
\set other    '''34343434-0000-0000-0000-000000000004'''
\set shop     '''34000000-0000-0000-0000-000000000001'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22634000001', '{"full_name": "Esperance"}'),
    (:customer, '+22634000002', '{"full_name": "Awa Client"}'),
    (:moussa,   '+22634000003', '{"full_name": "Moussa"}'),
    (:other,    '+22634000004', '{"full_name": "Autre"}');
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, lat, lng) values
    (:shop, 'Boutique Esperance', 'gains-34', 'retail', 'XOF', true, 12.3714, -1.5197);
select seed_retail_accounts(:shop);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop, :owner, 'owner', 'org', :shop, 'full');
insert into couriers (user_id, phone, status) values
    (:moussa, '+22634000003', 'approved'),
    (:other,  '+22634000004', 'approved');

-- Seeded as the server would leave them: delivered courses stamped when
-- they were finished. Two today (2 km each, 800 F), one ten days ago
-- (10 km, 2000 F), one delivered by somebody else today, and one of
-- Moussa's still on the road.
insert into orders (org_id, customer_id, customer_name, status, fulfilment, address,
                    total, currency, courier_id, drop_lat, drop_lng, delivery_fee, updated_at) values
    (:shop, :customer, 'Awa', 'delivered',  'delivery', 'Dassasgho', 17500, 'XOF', :moussa, 12.3894, -1.5197,  800, now()),
    (:shop, :customer, 'Awa', 'delivered',  'delivery', 'Dassasgho',   450, 'XOF', :moussa, 12.3894, -1.5197,  800, now() - interval '1 hour'),
    (:shop, :customer, 'Awa', 'delivered',  'delivery', 'Loin',       3200, 'XOF', :moussa, 12.4614, -1.5197, 2000, now() - interval '10 days'),
    (:shop, :customer, 'Awa', 'delivered',  'delivery', 'Dassasgho',   450, 'XOF', :other,  12.3894, -1.5197,  800, now()),
    (:shop, :customer, 'Awa', 'in_transit', 'delivery', 'Dassasgho',   450, 'XOF', :moussa, 12.3894, -1.5197,  800, now());

\echo ''
\echo '--- TEST 1: a stranger and a customer are refused ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :customer;
do $$
begin
    begin
        perform courier_earnings();
        raise exception 'FAIL: a customer read courier earnings';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: a non-courier was refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 2: today counts today, the month counts the ten-day-old one too ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :moussa;
do $$
declare v_today record; v_month record; v_rows int;
begin
    select count(*) into v_rows from courier_earnings();
    if v_rows <> 3 then
        raise exception 'FAIL: expected three periods, got %', v_rows;
    end if;
    select * into v_today from courier_earnings() e where e.period = 'today';
    if v_today.courses <> 2 or v_today.fees <> 1600 or abs(v_today.km - 4.0032) > 0.01 then
        raise exception 'FAIL: today = % courses, % F, % km', v_today.courses, v_today.fees, v_today.km;
    end if;
    select * into v_month from courier_earnings() e where e.period = 'month';
    -- The ten-day-old course is this month only if the month is at least
    -- eleven days old; either way it is never today's, and the other
    -- courier's and the undelivered one never count.
    if v_month.courses < 2 or v_month.courses > 3 or v_month.fees < 1600 then
        raise exception 'FAIL: month = % courses, % F', v_month.courses, v_month.fees;
    end if;
    if v_month.courses = 3 and (v_month.fees <> 3600 or abs(v_month.km - 14.0112) > 0.02) then
        raise exception 'FAIL: month with the old course = % F, % km', v_month.fees, v_month.km;
    end if;
    raise notice 'PASS: today 2 courses / 1600 F / 4.0 km; month % courses / % F', v_month.courses, v_month.fees;
end $$;
rollback;

\echo ''
\echo '--- TEST 3: the other courier sees only their own ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :other;
do $$
declare v_today record;
begin
    select * into v_today from courier_earnings() e where e.period = 'today';
    if v_today.courses <> 1 or v_today.fees <> 800 then
        raise exception 'FAIL: the other courier sees % courses / % F', v_today.courses, v_today.fees;
    end if;
    raise notice 'PASS: the other courier sees their one course and nothing of Moussa''s';
end $$;
rollback;

\echo ''
\echo '=== test_courier_earnings.sql: all checks passed ==='
