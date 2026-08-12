-- ============================================================
-- test_farm.sql — the farm counts things, and the books still balance.
--
-- BUILD_PLAN.md asks for one thing from this suite: "add tests proving the
-- ledger stays balanced". That is the last assertion here and the reason for
-- most of the others, because the ways a module like this unbalances the
-- books are all specific and all plausible:
--
--   * counting feed twice — once when it arrives and again when it is eaten;
--   * counting eggs as income the morning they are collected, months before
--     anybody pays for them;
--   * counting an invoice as income when it is raised AND again when it is
--     paid, which doubles every credit sale a farm makes;
--   * recording a dead bird as an expense, when what it cost is already in
--     the books as the feed it ate.
--
-- Each of those has an assertion below, and each of them is a mistake that
-- makes the farm look more profitable than it is — which is the direction
-- these mistakes always go, and the reason to test for them specifically
-- rather than trusting the totals.
--
-- Run as `authenticated` with a JWT subject set, never as postgres: every
-- recording function here refuses a caller with no auth.uid(), and a
-- superuser would bypass the policies besides.
-- ============================================================
\set ON_ERROR_STOP on

\set ignace   '''f4f4f4f4-0000-0000-0000-000000000001'''
\set worker   '''f4f4f4f4-0000-0000-0000-000000000002'''
\set investor '''f4f4f4f4-0000-0000-0000-000000000003'''
\set rival    '''f4f4f4f4-0000-0000-0000-000000000004'''

\set farm  '''a4a4a4a4-0000-0000-0000-000000000001'''
\set other '''a4a4a4a4-0000-0000-0000-000000000002'''

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
end $$;

grant usage on schema public to authenticated, anon;
grant select, insert, update, delete on all tables in schema public to authenticated, anon;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:ignace,   '+22675000001', '{"full_name":"Ignace"}'),
    (:worker,   '+22675000002', '{"full_name":"Salam"}'),
    (:investor, '+22675000003', '{"full_name":"Bailleur"}'),
    (:rival,    '+22675000004', '{"full_name":"Voisin"}');

insert into orgs (id, name, slug, profile) values
    (:farm,  'Ferme Test',  'ferme-test',  'farm'),
    (:other, 'Ferme Rivale', 'rivale-test', 'farm');

select seed_farm_accounts(:farm);

insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:farm,  :ignace,   'owner',    'org', :farm,  'full'),
    (:farm,  :worker,   'employee', 'org', :farm,  'full'),
    -- The quieter investor from the schema comment: entitled to know the farm
    -- is sound, not to read how many birds died on Tuesday.
    (:farm,  :investor, 'observer', 'org', :farm,  'summary'),
    (:other, :rival,    'owner',    'org', :other, 'full');

\echo ''
\echo '--- TEST 1: feed arriving is a stock movement AND an expense ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_farm  uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_me    uuid := 'f4f4f4f4-0000-0000-0000-000000000002';
    v_move  uuid;
    v_entry uuid;
    v_spent numeric;
    v_qty   numeric;
begin
    v_move := receive_stock(
        p_org_id => v_farm, p_item_name => 'Aliment ponte',
        p_quantity => 20, p_unit_cost => 17500, p_unit => 'sac',
        p_recorded_by => v_me, p_memo => 'Livraison SODEPAL'
    );

    select quantity, journal_entry_id into v_qty, v_entry
      from stock_movements where id = v_move;

    if v_qty <> 20 then
        raise exception 'FAIL: recorded % sacks, expected 20', v_qty;
    end if;
    if v_entry is null then
        raise exception 'FAIL: 350000 of feed arrived and the books say nothing';
    end if;

    -- 20 x 17,500. The expense account is the one named in p_category, which
    -- defaults to Aliment and exists because seed_farm_accounts made it.
    select amount into v_spent
      from income_statement(v_farm) where name = 'Charges';
    if v_spent <> 350000 then
        raise exception 'FAIL: the feed cost % in the books, expected 350000', v_spent;
    end if;

    raise notice 'PASS: 20 sacks arrived, and 350000 left the books';
end $$;
commit;

\echo ''
\echo '--- TEST 2: feed eaten moves the count and not the money ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_farm   uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_before numeric;
    v_after  numeric;
    v_hand   numeric;
begin
    select amount into v_before from income_statement(v_farm) where name = 'Charges';

    perform move_stock(
        p_org_id => v_farm, p_item_name => 'Aliment ponte',
        p_quantity => 3, p_kind => 'consumed',
        p_recorded_by => 'f4f4f4f4-0000-0000-0000-000000000002'
    );

    select amount into v_after from income_statement(v_farm) where name = 'Charges';

    -- This is the "counted twice" failure. Feed was expensed when it arrived;
    -- expensing it again as it is eaten would double the single largest cost
    -- on the farm.
    if v_after <> v_before then
        raise exception
            'FAIL: eating feed changed the charges from % to %', v_before, v_after;
    end if;

    select on_hand into v_hand from stock_on_hand(v_farm) where name = 'Aliment ponte';
    if v_hand <> 17 then
        raise exception 'FAIL: % sacks on hand, expected 17', v_hand;
    end if;

    raise notice 'PASS: 3 sacks eaten, 17 left, and no second expense';
end $$;
commit;

\echo ''
\echo '--- TEST 3: the reorder warning fires on the count, not the guess ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_farm uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_low  boolean;
begin
    update items set reorder_level = 5
     where org_id = v_farm and lower(name) = 'aliment ponte';

    select below_reorder into v_low
      from stock_on_hand(v_farm) where name = 'Aliment ponte';
    if v_low then
        raise exception 'FAIL: 17 sacks with a threshold of 5 is not low';
    end if;

    -- Two weeks of feeding.
    perform move_stock(
        p_org_id => v_farm, p_item_name => 'Aliment ponte',
        p_quantity => 13, p_kind => 'consumed',
        p_recorded_by => 'f4f4f4f4-0000-0000-0000-000000000001'
    );

    select below_reorder into v_low
      from stock_on_hand(v_farm) where name = 'Aliment ponte';
    if not v_low then
        raise exception 'FAIL: 4 sacks with a threshold of 5 is not flagged';
    end if;

    raise notice 'PASS: the warning follows the count down past the threshold';
end $$;
commit;

\echo ''
\echo '--- TEST 4: a retried sync cannot double-count a delivery ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_farm uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_me   uuid := 'f4f4f4f4-0000-0000-0000-000000000002';
    v_uuid uuid := '88888888-0000-0000-0000-000000000001';
    v_a    uuid;
    v_b    uuid;
    v_n    int;
begin
    v_a := receive_stock(
        p_org_id => v_farm, p_item_name => 'Vaccin Newcastle',
        p_quantity => 500, p_unit_cost => 40, p_unit => 'dose',
        p_category => 'Vétérinaire', p_recorded_by => v_me,
        p_client_uuid => v_uuid
    );
    -- The phone lost signal after the server committed and retries.
    v_b := receive_stock(
        p_org_id => v_farm, p_item_name => 'Vaccin Newcastle',
        p_quantity => 500, p_unit_cost => 40, p_unit => 'dose',
        p_category => 'Vétérinaire', p_recorded_by => v_me,
        p_client_uuid => v_uuid
    );

    if v_a <> v_b then
        raise exception 'FAIL: the retry created a second delivery';
    end if;

    select count(*) into v_n
      from stock_movements where org_id = v_farm and client_uuid = v_uuid;
    if v_n <> 1 then
        raise exception 'FAIL: % movements share one client_uuid', v_n;
    end if;

    -- And no second journal entry either, which is the expensive half.
    select count(*) into v_n
      from journal_entries where org_id = v_farm and client_uuid = v_uuid;
    if v_n <> 1 then
        raise exception 'FAIL: % journal entries share one client_uuid', v_n;
    end if;

    raise notice 'PASS: the retry returned the original delivery';
end $$;
commit;

\echo ''
\echo '--- TEST 5: birds die, the flock shrinks, and nothing is expensed ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_farm   uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_me     uuid := 'f4f4f4f4-0000-0000-0000-000000000001';
    v_flock  uuid;
    v_alive  int;
    v_before numeric;
    v_after  numeric;
begin
    v_flock := open_flock(v_farm, 'B-2026-01', 500, 'Isa Brown');

    select amount into v_before from income_statement(v_farm) where name = 'Charges';

    perform record_flock_event(v_flock, 'mortality', 7, v_me, 'Chaleur');
    perform record_flock_event(v_flock, 'mortality', 3, v_me);
    perform record_flock_event(v_flock, 'vaccination', 490, v_me, 'Newcastle');

    select alive into v_alive from flock_status(v_farm) where batch_code = 'B-2026-01';
    if v_alive <> 490 then
        raise exception 'FAIL: % birds alive, expected 490', v_alive;
    end if;

    select amount into v_after from income_statement(v_farm) where name = 'Charges';

    -- A dead bird costs what it cost to raise, and that is already in the
    -- books as the feed it ate. Posting an expense for the death would count
    -- the same loss twice.
    if v_after <> v_before then
        raise exception 'FAIL: 10 deaths changed the charges from % to %', v_before, v_after;
    end if;

    raise notice 'PASS: 500 arrived, 10 died, 490 alive, and the books did not move';
end $$;
commit;

\echo ''
\echo '--- TEST 6: a flock cannot lose more birds than it has ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_farm  uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_flock uuid;
begin
    select flock_id into v_flock from flock_status(v_farm) where batch_code = 'B-2026-01';

    begin
        -- 3000 instead of 300: the typo that would leave every report for the
        -- rest of the batch's life carrying a flock of -2510 birds.
        perform record_flock_event(
            v_flock, 'mortality', 3000, 'f4f4f4f4-0000-0000-0000-000000000001'
        );
        raise exception 'FAIL: a flock of 490 birds lost 3000 of them';
    exception
        when sqlstate 'P0001' then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: the impossible mortality was refused (%)', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 7: eggs collected are production, not income ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_farm   uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_me     uuid := 'f4f4f4f4-0000-0000-0000-000000000002';
    v_flock  uuid;
    v_before numeric;
    v_after  numeric;
    v_eggs   bigint;
begin
    select flock_id into v_flock from flock_status(v_farm) where batch_code = 'B-2026-01';

    select amount into v_before from income_statement(v_farm) where name = 'Produits';

    perform record_eggs(
        p_org_id => v_farm, p_egg_count => 380, p_flock_id => v_flock,
        p_recorded_by => v_me
    );
    perform record_eggs(
        p_org_id => v_farm, p_egg_count => 24, p_flock_id => v_flock,
        p_grade => 'fêlé', p_recorded_by => v_me
    );

    select amount into v_after from income_statement(v_farm) where name = 'Produits';

    -- Recording production as revenue is how a farm convinces itself it is
    -- profitable months before anybody pays for anything.
    if v_after <> v_before then
        raise exception
            'FAIL: collecting eggs changed the produits from % to %', v_before, v_after;
    end if;

    select eggs into v_eggs from farm_daily_summary(v_farm);
    if v_eggs <> 404 then
        raise exception 'FAIL: the day shows % eggs, expected 404', v_eggs;
    end if;

    raise notice 'PASS: 404 eggs collected and not one franc of income';
end $$;
commit;

\echo ''
\echo '--- TEST 8: the lay rate is what tells the farmer something is wrong ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_farm uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_rate numeric;
    v_eggs bigint;
begin
    select eggs_7d, lay_rate into v_eggs, v_rate
      from flock_status(v_farm) where batch_code = 'B-2026-01';

    if v_eggs <> 404 then
        raise exception 'FAIL: % eggs in seven days, expected 404', v_eggs;
    end if;

    -- 404 eggs from 490 birds over a seven-day window. One day's collection
    -- inside a week-long denominator, so the rate is deliberately low; what
    -- matters is that it is computed from birds alive rather than from birds
    -- delivered, which is the number that drifts.
    if round(v_rate, 3) <> round(404::numeric / (490 * 7), 3) then
        raise exception 'FAIL: lay rate is %, which is not 404/(490x7)', v_rate;
    end if;

    raise notice 'PASS: lay rate %, computed on the birds still alive', v_rate;
end $$;
rollback;

\echo ''
\echo '--- TEST 9: a cash sale is income the moment it happens ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_farm   uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_before numeric;
    v_after  numeric;
begin
    select amount into v_before from income_statement(v_farm) where name = 'Produits';

    perform record_farm_sale(
        p_org_id => v_farm, p_amount => 45000,
        p_label => '15 plateaux au marché',
        p_recorded_by => 'f4f4f4f4-0000-0000-0000-000000000002',
        p_customer_name => 'Marché de Bobo'
    );

    select amount into v_after from income_statement(v_farm) where name = 'Produits';
    if v_after - v_before <> 45000 then
        raise exception 'FAIL: a 45000 sale moved the produits by %', v_after - v_before;
    end if;

    raise notice 'PASS: cash in the hand is income in the books';
end $$;
commit;

\echo ''
\echo '--- TEST 10: an invoice is income now and cash later ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_farm     uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_invoice  uuid;
    v_income   numeric;
    v_income2  numeric;
    v_cash     numeric;
    v_cash2    numeric;
    v_recv     numeric;
    v_total    numeric;
    v_number   text;
begin
    select balance into v_cash from chart_of_accounts(v_farm) where code = '1000';
    select amount into v_income from income_statement(v_farm) where name = 'Produits';

    v_invoice := create_invoice(
        p_org_id => v_farm,
        p_customer_name => 'Hôtel Indépendance',
        p_lines => '[{"description":"Plateaux d''œufs","quantity":30,"unit_price":2500}]'::jsonb,
        p_recorded_by => 'f4f4f4f4-0000-0000-0000-000000000001',
        p_customer_phone => '+22676000001',
        p_due_on => current_date + 21
    );

    select total, number into v_total, v_number from invoices where id = v_invoice;
    if v_total <> 75000 then
        raise exception 'FAIL: 30 x 2500 came to %, expected 75000', v_total;
    end if;
    if v_number !~ '^\d{4}-\d{4}$' then
        raise exception 'FAIL: invoice number % is not YYYY-NNNN', v_number;
    end if;

    -- The income is real the day it is invoiced.
    select amount into v_income2 from income_statement(v_farm) where name = 'Produits';
    if v_income2 - v_income <> 75000 then
        raise exception 'FAIL: the invoice moved the produits by %', v_income2 - v_income;
    end if;

    -- The cash is not.
    select balance into v_cash2 from chart_of_accounts(v_farm) where code = '1000';
    if v_cash2 <> v_cash then
        raise exception 'FAIL: an unpaid invoice moved the cash from % to %', v_cash, v_cash2;
    end if;

    -- What is missing sits in the receivable, which is the whole point.
    select balance into v_recv from chart_of_accounts(v_farm) where code = '1300';
    if v_recv <> 75000 then
        raise exception 'FAIL: créances clients is %, expected 75000', v_recv;
    end if;

    raise notice 'PASS: invoice % — income now, 75000 owed, no cash moved', v_number;
end $$;
commit;

\echo ''
\echo '--- TEST 11: paying an invoice moves cash and earns nothing new ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_farm    uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_invoice uuid;
    v_income  numeric;
    v_income2 numeric;
    v_recv    numeric;
    v_out     numeric;
begin
    select invoice_id into v_invoice
      from outstanding_invoices(v_farm) where customer_name = 'Hôtel Indépendance';

    select amount into v_income from income_statement(v_farm) where name = 'Produits';

    -- A third now, the rest later — the normal case, and the one a
    -- paid/unpaid boolean cannot describe.
    perform record_invoice_payment(
        v_invoice, 25000, 'mobile_money', 'f4f4f4f4-0000-0000-0000-000000000001'
    );

    select amount into v_income2 from income_statement(v_farm) where name = 'Produits';

    -- This is the "counted twice" failure for credit sales: recognising the
    -- income again on payment would double every invoice the farm ever raises.
    if v_income2 <> v_income then
        raise exception
            'FAIL: a payment changed the produits from % to %', v_income, v_income2;
    end if;

    select balance into v_recv from chart_of_accounts(v_farm) where code = '1300';
    if v_recv <> 50000 then
        raise exception 'FAIL: créances clients is % after 25000 paid, expected 50000', v_recv;
    end if;

    select outstanding into v_out
      from outstanding_invoices(v_farm) where customer_name = 'Hôtel Indépendance';
    if v_out <> 50000 then
        raise exception 'FAIL: the invoice shows % outstanding, expected 50000', v_out;
    end if;

    raise notice 'PASS: 25000 arrived, 50000 still owed, no new income';
end $$;
commit;

\echo ''
\echo '--- TEST 12: a customer cannot overpay an invoice into the void ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_farm    uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_invoice uuid;
begin
    select invoice_id into v_invoice
      from outstanding_invoices(v_farm) where customer_name = 'Hôtel Indépendance';

    begin
        -- 50,000 is outstanding on a 75,000 invoice.
        perform record_invoice_payment(
            v_invoice, 60000, 'cash', 'f4f4f4f4-0000-0000-0000-000000000001'
        );
        raise exception 'FAIL: an invoice was overpaid';
    exception
        when sqlstate 'P0001' then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: the overpayment was refused (%)', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 13: after all of it, debits still equal credits ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_farm   uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_d      numeric;
    v_c      numeric;
    v_assets numeric;
    v_claims numeric;
begin
    select sum(total_debit), sum(total_credit) into v_d, v_c from trial_balance(v_farm);

    if v_d is null or v_d = 0 then
        raise exception 'FAIL: the trial balance is empty';
    end if;
    if v_d <> v_c then
        raise exception
            'FAIL: debits % <> credits % — the farm module unbalanced the books', v_d, v_c;
    end if;

    -- And the balance sheet agrees, which is the same claim read the other
    -- way round and would catch a receivable posted to the wrong side.
    select amount into v_assets from balance_sheet(v_farm) where name = 'Total actif';
    select amount into v_claims from balance_sheet(v_farm) where name = 'Total passif';
    if v_assets <> v_claims then
        raise exception 'FAIL: actif % <> passif %', v_assets, v_claims;
    end if;

    raise notice 'PASS: debits = credits = %, actif = passif = %', v_d, v_assets;
end $$;
rollback;

\echo ''
\echo '--- TEST 14: the investor sees the money and not the birds ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_farm uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_n    int;
    v_res  numeric;
begin
    -- Entitled to know the farm is sound.
    select amount into v_res from income_statement(v_farm) where name = 'Résultat';
    if v_res is null then
        raise exception 'FAIL: the investor cannot see the result they are entitled to';
    end if;

    -- Not entitled to run it. How many birds died on Tuesday, how much feed
    -- is left and which hotel is late paying are operational detail.
    select count(*) into v_n from stock_on_hand(v_farm);
    if v_n <> 0 then
        raise exception 'FAIL: a summary observer read % stock lines', v_n;
    end if;

    select count(*) into v_n from flock_status(v_farm);
    if v_n <> 0 then
        raise exception 'FAIL: a summary observer read % flocks', v_n;
    end if;

    select count(*) into v_n from outstanding_invoices(v_farm);
    if v_n <> 0 then
        raise exception 'FAIL: a summary observer read % unpaid invoices', v_n;
    end if;

    select count(*) into v_n from stock_movements where org_id = v_farm;
    if v_n <> 0 then
        raise exception 'FAIL: a summary observer read % stock movements directly', v_n;
    end if;

    raise notice 'PASS: the investor reads the result and none of the operations';
end $$;
rollback;

\echo ''
\echo '--- TEST 15: an observer cannot record anything at all ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_farm uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
begin
    begin
        perform record_eggs(p_org_id => v_farm, p_egg_count => 999);
        raise exception 'FAIL: an observer recorded egg production';
    exception
        when sqlstate 'P0001' then
            if sqlerrm like 'FAIL:%' then raise; end if;
    end;

    begin
        perform receive_stock(v_farm, 'Aliment ponte', 1);
        raise exception 'FAIL: an observer recorded a delivery';
    exception
        when sqlstate 'P0001' then
            if sqlerrm like 'FAIL:%' then raise; end if;
    end;

    raise notice 'PASS: the observer reads and never writes';
end $$;
rollback;

\echo ''
\echo '--- TEST 16: the neighbouring farm sees none of it ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000004';
set local role authenticated;
do $$
declare
    v_farm uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_n    int;
begin
    select count(*) into v_n from stock_on_hand(v_farm);
    if v_n <> 0 then
        raise exception 'FAIL: a rival read % stock lines', v_n;
    end if;

    select count(*) into v_n from flock_status(v_farm);
    if v_n <> 0 then
        raise exception 'FAIL: a rival read another farm''s flocks';
    end if;

    select count(*) into v_n from customers where org_id = v_farm;
    if v_n <> 0 then
        raise exception 'FAIL: a rival read another farm''s customer list';
    end if;

    select count(*) into v_n from invoices where org_id = v_farm;
    if v_n <> 0 then
        raise exception 'FAIL: a rival read another farm''s invoices';
    end if;

    begin
        perform receive_stock(v_farm, 'Aliment', 1);
        raise exception 'FAIL: a rival wrote to another farm''s stock';
    exception
        when sqlstate 'P0001' then
            if sqlerrm like 'FAIL:%' then raise; end if;
    end;

    raise notice 'PASS: the farm next door is invisible and unwritable';
end $$;
rollback;

\echo ''
\echo '--- TEST 17: opening a flock is in the activity log ---'
begin;
set local "request.jwt.claim.sub" = 'f4f4f4f4-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_farm uuid := 'a4a4a4a4-0000-0000-0000-000000000001';
    v_who  text;
begin
    select actor_label into v_who
      from audit_log_page(v_farm, 100)
     where table_name = 'flocks' and summary = 'B-2026-01'
     order by id desc limit 1;

    if v_who is null then
        raise exception 'FAIL: opening a flock left no trace in the log';
    end if;
    if v_who <> 'Ignace' then
        raise exception 'FAIL: the log credits % rather than Ignace', v_who;
    end if;

    -- The customer created by the invoice, too — who the farm sells to is
    -- structural, and belongs in the same trail as the chart of accounts.
    if not exists (
        select 1 from audit_log_page(v_farm, 100)
        where table_name = 'customers' and summary = 'Hôtel Indépendance'
    ) then
        raise exception 'FAIL: a new customer left no trace in the log';
    end if;

    raise notice 'PASS: the farm''s structural changes reach the log';
end $$;
rollback;

\echo ''
\echo '============================================'
\echo ' All farm assertions passed.'
\echo '============================================'
