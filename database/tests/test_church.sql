\set ON_ERROR_STOP on
\set israel '''11111111-1111-1111-1111-111111111111'''
\set org '''22222222-2222-2222-2222-222222222222'''
\set marie '''33333333-3333-3333-3333-333333333333'''

insert into auth.users (id) values (:israel);
insert into profiles (id, full_name) values (:israel, 'Israel');
insert into orgs (id, name, slug, profile) values (:org, 'Grace Chapel', 'grace', 'church');
select seed_church_accounts(:org);
insert into church_members (id, org_id, full_name) values (:marie, :org, 'Marie Ouedraogo');

\echo ''
\echo '--- TEST 1: tithe 50000 cash, attributed to Marie ---'
select record_contribution(:org, 50000, 'tithe', :israel, 'cash', :marie) as entry_id;

\echo '--- TEST 2: offering 12500 mobile money, anonymous ---'
select record_contribution(:org, 12500, 'offering', :israel, 'mobile_money') as entry_id;

\echo '--- TEST 3: expense 8000 electricity ---'
select record_expense(:org, 8000, '5000', :israel, 'cash', 'Electricity bill') as entry_id;

\echo ''
\echo '--- TEST 4: LEDGER BALANCED? (debits - credits must be 0.00) ---'
select sum(debit) - sum(credit) as must_be_zero from journal_lines;

\echo ''
\echo '--- TEST 5: IDEMPOTENCY (bad signal, phone retries same entry) ---'
select record_contribution(:org, 9999, 'offering', :israel, 'cash', null, null,
    '44444444-4444-4444-4444-444444444444') as first_call;
select record_contribution(:org, 9999, 'offering', :israel, 'cash', null, null,
    '44444444-4444-4444-4444-444444444444') as retry_returns_same_id;
select count(*) as should_be_1 from journal_entries where client_uuid = '44444444-4444-4444-4444-444444444444';

\echo ''
\echo '--- TEST 6: UNDO a mistake (reversing entry, nothing deleted) ---'
select record_contribution(:org, 999999, 'offering', :israel, 'cash', null, 'TYPO - too many zeros') as mistake_id \gset
select reverse_entry(:'mistake_id', :israel, 'Entered wrong amount') as correction_id;
select count(*) as entries_still_on_record from journal_entries where id = :'mistake_id';
select sum(debit) - sum(credit) as still_balanced from journal_lines;

\echo ''
\echo '--- TEST 7: CASH BALANCES ---'
select * from church_balances(:org);

\echo ''
\echo '--- TEST 8: THE PASTOR REPORT ---'
select * from church_weekly_summary(:org);

\echo ''
\echo '--- TEST 9: MARIE GIVING STATEMENT ---'
select * from member_giving_statement(:marie);

\echo ''
\echo '--- TEST 10: GUARDRAILS (each should raise an error) ---'
\set ON_ERROR_STOP off
select record_contribution(:org, -500, 'tithe', :israel);
select record_contribution(:org, 500, 'bitcoin', :israel);
select reverse_entry(:'mistake_id', :israel, 'double reversal');
