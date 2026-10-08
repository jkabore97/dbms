-- ============================================================
-- test_reports.sql — who may read a number, and who may read the rows behind
-- it.
--
-- Two things are proved here, and the first is the reason this file exists:
--
--   1. `church_account_activity` is a view, and a view in Postgres 15+ runs as
--      its owner unless told otherwise. Every policy in 004 was intact and
--      none of them ran when the query went through the view. A caller with no
--      session at all could read every org's daily totals.
--
--      test_rls.sql could not have caught this. It tests tables, and this was
--      a view over them — which is exactly why the test lives here now.
--
--   2. `visibility = 'summary'` finally means something. The observer who is
--      entitled to know whether the business is sound is not thereby entitled
--      to read every transaction in it.
--
-- Same discipline as the other suites: every assertion runs as the
-- `authenticated` (or `anon`) role, never as the superuser that owns the
-- tables, because a superuser bypasses RLS and would pass against nothing.
-- ============================================================
\set ON_ERROR_STOP on

\set pastor   '''a1a1a1a1-0000-0000-0000-000000000001'''
\set treasurer '''a1a1a1a1-0000-0000-0000-000000000002'''
\set watcher  '''a1a1a1a1-0000-0000-0000-000000000003'''
\set rival    '''a1a1a1a1-0000-0000-0000-000000000004'''

\set church '''c1c1c1c1-0000-0000-0000-000000000001'''
\set other  '''c1c1c1c1-0000-0000-0000-000000000002'''
\set giver  '''d1d1d1d1-0000-0000-0000-000000000001'''

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

insert into auth.users (id, phone) values
    (:pastor,    '+22672000001'),
    (:treasurer, '+22672000002'),
    (:watcher,   '+22672000003'),
    (:rival,     '+22672000004');

insert into orgs (id, name, slug, profile) values
    (:church, 'Assemblée Test', 'assemblee-test', 'church'),
    (:other,  'Autre Assemblée', 'autre-test',    'church');

select seed_church_accounts(:church);
select seed_church_accounts(:other);

insert into church_members (id, org_id, full_name)
values (:giver, :church, 'Awa Sawadogo');

insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:church, :pastor,    'owner',    'org', :church, 'full'),
    (:church, :treasurer, 'admin',    'org', :church, 'full'),
    -- The quieter investor: entitled to the totals, nothing more.
    (:church, :watcher,   'observer', 'org', :church, 'summary'),
    (:other,  :rival,     'owner',    'org', :other,  'full');

-- Money in both churches, so "can they see the other one" is a real question.
select record_contribution(:church, 50000, 'tithe',    :pastor, 'cash', :giver);
select record_contribution(:church, 12500, 'offering', :pastor, 'mobile_money');
select record_expense(:church, 8000, '5000', :pastor, 'cash', 'Facture SONABEL');
select record_contribution(:other,  99000, 'offering', :rival,  'cash');


\echo ''
\echo '--- TEST 1: the view no longer leaks every org to anyone holding the publishable key ---'
begin;
set local role anon;   -- no session at all: exactly what the web build ships with
do $$
declare v_count int;
begin
    select count(*) into v_count from church_account_activity;
    if v_count <> 0 then
        raise exception 'FAIL: an anonymous caller read % rows of daily totals through the view', v_count;
    end if;
    raise notice 'PASS: no session, no rows — the view runs as its caller now';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: the view respects tenancy for a signed-in stranger ---'
begin;
set local "request.jwt.claim.sub" = 'a1a1a1a1-0000-0000-0000-000000000004';
set local role authenticated;
do $$
declare
    v_theirs int;
    v_mine   int;
begin
    select count(*) into v_theirs from church_account_activity
    where org_id = 'c1c1c1c1-0000-0000-0000-000000000001';
    if v_theirs <> 0 then
        raise exception 'FAIL: the rival read % rows of another church''s activity', v_theirs;
    end if;

    select count(*) into v_mine from church_account_activity
    where org_id = 'c1c1c1c1-0000-0000-0000-000000000002';
    if v_mine = 0 then
        raise exception 'FAIL: the rival cannot see their own activity — the view is now too tight';
    end if;

    raise notice 'PASS: the view shows a member their own books and nobody else''s';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: a summary observer gets the totals ---'
begin;
set local "request.jwt.claim.sub" = 'a1a1a1a1-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_in    numeric;
    v_out   numeric;
    v_lines int;
begin
    select amount into v_in from church_weekly_summary('c1c1c1c1-0000-0000-0000-000000000001')
    where category = 'total' and label = 'Total received';
    select amount into v_out from church_weekly_summary('c1c1c1c1-0000-0000-0000-000000000001')
    where category = 'total' and label = 'Total spent';

    if v_in <> 62500 then
        raise exception 'FAIL: observer sees % received, expected 62500', v_in;
    end if;
    if v_out <> 8000 then
        raise exception 'FAIL: observer sees % spent, expected 8000', v_out;
    end if;

    -- And not one line of the detail behind them.
    select count(*) into v_lines from church_weekly_summary('c1c1c1c1-0000-0000-0000-000000000001')
    where category in ('income', 'expense');
    if v_lines <> 0 then
        raise exception 'FAIL: a summary observer got % detail lines', v_lines;
    end if;

    raise notice 'PASS: totals yes, breakdown no — visibility means something now';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: a summary observer cannot go round the report to the rows ---'
begin;
set local "request.jwt.claim.sub" = 'a1a1a1a1-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_count int;
begin
    select count(*) into v_count from journal_entries;
    if v_count <> 0 then
        raise exception 'FAIL: a summary observer read % individual entries', v_count;
    end if;

    select count(*) into v_count from journal_lines;
    if v_count <> 0 then
        raise exception 'FAIL: a summary observer read % ledger lines', v_count;
    end if;

    select count(*) into v_count from contribution_attributions;
    if v_count <> 0 then
        raise exception 'FAIL: a summary observer read % records of who gave what', v_count;
    end if;

    select count(*) into v_count from church_account_activity;
    if v_count <> 0 then
        raise exception 'FAIL: a summary observer read % rows through the view', v_count;
    end if;

    raise notice 'PASS: the API tells a summary observer exactly what the screen does';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: full visibility still sees everything it always did ---'
begin;
set local "request.jwt.claim.sub" = 'a1a1a1a1-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_income  int;
    v_expense int;
    v_entries int;
    v_in      numeric;
begin
    select count(*) into v_income from church_weekly_summary('c1c1c1c1-0000-0000-0000-000000000001')
    where category = 'income';
    select count(*) into v_expense from church_weekly_summary('c1c1c1c1-0000-0000-0000-000000000001')
    where category = 'expense';

    if v_income < 2 then
        raise exception 'FAIL: treasurer sees % income lines, expected tithes and offerings', v_income;
    end if;
    if v_expense < 1 then
        raise exception 'FAIL: treasurer sees no expense lines';
    end if;

    select amount into v_in from church_weekly_summary('c1c1c1c1-0000-0000-0000-000000000001')
    where category = 'total' and label = 'Total received';
    if v_in <> 62500 then
        raise exception 'FAIL: treasurer sees % received', v_in;
    end if;

    select count(*) into v_entries from journal_entries;
    if v_entries = 0 then
        raise exception 'FAIL: full visibility cannot read the entries — 006 is too tight';
    end if;

    raise notice 'PASS: the people who keep the books still see all of them';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: balances are a total, so every member gets them ---'
begin;
set local "request.jwt.claim.sub" = 'a1a1a1a1-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_total numeric;
begin
    select sum(balance) into v_total from church_balances('c1c1c1c1-0000-0000-0000-000000000001');
    -- 50000 cash in, 12500 mobile money in, 8000 cash out.
    if v_total <> 54500 then
        raise exception 'FAIL: observer sees a cash position of %, expected 54500', v_total;
    end if;
    raise notice 'PASS: the observer knows what is in the bank without reading the cheques';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: a stranger gets nothing from any report, for any org ---'
begin;
set local "request.jwt.claim.sub" = 'a1a1a1a1-0000-0000-0000-000000000004';
set local role authenticated;
do $$
declare
    v_count int;
    v_in    numeric;
begin
    select coalesce(sum(balance), 0) into v_count
    from church_balances('c1c1c1c1-0000-0000-0000-000000000001');
    if v_count <> 0 then
        raise exception 'FAIL: the rival read a balance of % from another church', v_count;
    end if;

    select amount into v_in from church_weekly_summary('c1c1c1c1-0000-0000-0000-000000000001')
    where category = 'total' and label = 'Total received';
    if coalesce(v_in, 0) <> 0 then
        raise exception 'FAIL: the rival read % of another church''s income', v_in;
    end if;

    select count(*) into v_count from member_giving_statement('d1d1d1d1-0000-0000-0000-000000000001');
    if v_count <> 0 then
        raise exception 'FAIL: the rival read % lines of a stranger''s giving', v_count;
    end if;

    raise notice 'PASS: the reports are as closed as the tables under them';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: a giving statement needs full visibility, not just membership ---'
begin;
set local "request.jwt.claim.sub" = 'a1a1a1a1-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_count int;
begin
    select count(*) into v_count
    from member_giving_statement('d1d1d1d1-0000-0000-0000-000000000001');
    if v_count <> 0 then
        raise exception 'FAIL: a summary observer read % lines of what one member gave', v_count;
    end if;
    raise notice 'PASS: what one named person gave is not part of "read the books"';
end $$;
rollback;

\echo ''
\echo '--- TEST 9: the pastor can produce the statement the member asks for ---'
begin;
set local "request.jwt.claim.sub" = 'a1a1a1a1-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_count int;
    v_total numeric;
begin
    select count(*), coalesce(sum(amount), 0) into v_count, v_total
    from member_giving_statement('d1d1d1d1-0000-0000-0000-000000000001');
    if v_count <> 1 then
        raise exception 'FAIL: the statement has % lines, expected 1', v_count;
    end if;
    if v_total <> 50000 then
        raise exception 'FAIL: the statement totals %, expected 50000', v_total;
    end if;
    raise notice 'PASS: Awa gets her year-end statement, from her own church only';
end $$;
rollback;

\echo ''
\echo '=== REPORT ACCESS SUITE COMPLETE — all assertions held ==='
