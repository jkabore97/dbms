-- ============================================================
-- test_accounting.sql — the books add up, and only for the people entitled
-- to read them.
--
-- Two claims are under test and the first one is the reason the file exists.
--
--   1. A name typed by a person becomes a real account, the same account
--      every time it is typed again, and the entries posted against it leave
--      the ledger balanced. "Type whatever you like" is only safe if the
--      thing underneath it is still double-entry, and the trial balance is
--      the assertion that proves it.
--
--   2. The access rule 006 established survives the four new reports. A
--      summary observer reads totals and no line items; a stranger reads
--      nothing; an observer of any kind writes nothing.
--
-- Same discipline as the other suites: every assertion runs as the
-- `authenticated` role with a JWT subject set, never as the superuser that
-- owns the tables, because a superuser bypasses RLS and would pass against no
-- policies at all. record_entry() additionally refuses a caller with no
-- auth.uid(), so a suite run as postgres could not even record anything.
-- ============================================================
\set ON_ERROR_STOP on

\set owner     '''b2b2b2b2-0000-0000-0000-000000000001'''
\set treasurer '''b2b2b2b2-0000-0000-0000-000000000002'''
\set watcher   '''b2b2b2b2-0000-0000-0000-000000000003'''
\set stranger  '''b2b2b2b2-0000-0000-0000-000000000004'''

\set org   '''c2c2c2c2-0000-0000-0000-000000000001'''
\set other '''c2c2c2c2-0000-0000-0000-000000000002'''

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
    (:owner,     '+22673000001', '{"full_name":"Salif"}'),
    (:treasurer, '+22673000002', '{"full_name":"Aminata"}'),
    (:watcher,   '+22673000003', '{"full_name":"Bailleur"}'),
    (:stranger,  '+22673000004', '{"full_name":"Personne"}');

insert into orgs (id, name, slug, profile) values
    (:org,   'Atelier Test',  'atelier-test',  'generic'),
    (:other, 'Ailleurs Test', 'ailleurs-test', 'generic');

-- Only the first org gets a seeded chart. The second is left bare on purpose:
-- record_entry() has to work for a business nobody ran the seeder for.
select seed_church_accounts(:org);

insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:org,   :owner,     'owner',    'org', :org,   'full'),
    (:org,   :treasurer, 'employee', 'org', :org,   'full'),
    -- The quiet investor: entitled to know the business is sound, not to read
    -- every transaction in it.
    (:org,   :watcher,   'observer', 'org', :org,   'summary'),
    (:other, :stranger,  'owner',    'org', :other, 'full');

\echo ''
\echo '--- TEST 1: a typed name becomes an account, and the same one twice ---'
begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_org   uuid := 'c2c2c2c2-0000-0000-0000-000000000001';
    v_me    uuid := 'b2b2b2b2-0000-0000-0000-000000000002';
    v_first uuid;
    v_again uuid;
    v_count int;
    v_code  text;
begin
    -- Nothing in the seeded chart is called this. It is the case the whole
    -- migration exists for: a real expense nobody anticipated.
    perform record_entry(
        p_org_id => v_org, p_amount => 45000, p_direction => 'out',
        p_label => 'Réparation du toit', p_recorded_by => v_me,
        p_method => 'cash',
        p_details => '{"artisan":"Kaboré","garantie_mois":6}'::jsonb
    );

    select count(*) into v_count
      from accounts
     where org_id = v_org and lower(name) = 'réparation du toit';
    if v_count <> 1 then
        raise exception 'FAIL: typing a name created % accounts, expected 1', v_count;
    end if;

    select id, code into v_first, v_code
      from accounts where org_id = v_org and lower(name) = 'réparation du toit';

    -- 002 seeded expenses up to 5060, so the first minted one lands on 5070.
    if v_code <> '5070' then
        raise exception 'FAIL: new expense account got code %, expected 5070', v_code;
    end if;

    -- Typed again — spelled with different case and stray spaces, which is
    -- how it will actually arrive from a phone keyboard.
    perform record_entry(
        p_org_id => v_org, p_amount => 12000, p_direction => 'out',
        p_label => '  réparation du TOIT ', p_recorded_by => v_me
    );

    select count(*) into v_count
      from accounts
     where org_id = v_org and lower(btrim(name)) = 'réparation du toit';
    if v_count <> 1 then
        raise exception
            'FAIL: the same name typed twice made % accounts, expected 1', v_count;
    end if;

    select id into v_again
      from accounts where org_id = v_org and lower(btrim(name)) = 'réparation du toit';
    if v_again <> v_first then
        raise exception 'FAIL: the second entry posted to a different account';
    end if;

    raise notice 'PASS: a typed name is an account, and typing it again finds it';
end $$;
commit;

\echo ''
\echo '--- TEST 2: the characteristics typed with it are kept ---'
begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v_artisan text;
begin
    select details ->> 'artisan' into v_artisan
      from journal_entries
     where org_id = 'c2c2c2c2-0000-0000-0000-000000000001'
       and label = 'Réparation du toit'
     order by created_at
     limit 1;

    if v_artisan is distinct from 'Kaboré' then
        raise exception 'FAIL: the details typed with the entry were lost (got %)', v_artisan;
    end if;
    raise notice 'PASS: label and details survive the round trip';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: an org with no seeded chart can still record ---'
begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000004';
set local role authenticated;
do $$
declare
    v_org uuid := 'c2c2c2c2-0000-0000-0000-000000000002';
    v_n   int;
begin
    perform record_entry(
        p_org_id => v_org, p_amount => 8000, p_direction => 'in',
        p_label => 'Vente du samedi',
        p_recorded_by => 'b2b2b2b2-0000-0000-0000-000000000004',
        p_method => 'mobile_money'
    );

    -- One income account for the sale, one asset account for the float the
    -- money landed in. Neither existed a moment ago.
    select count(*) into v_n from accounts where org_id = v_org;
    if v_n <> 2 then
        raise exception 'FAIL: bare org ended up with % accounts, expected 2', v_n;
    end if;

    if not exists (
        select 1 from accounts
        where org_id = v_org and code = '1020' and type = 'asset'
    ) then
        raise exception 'FAIL: mobile money account was not created on its canonical code';
    end if;

    raise notice 'PASS: a business nobody seeded records its first sale';
end $$;
commit;

\echo ''
\echo '--- TEST 4: a retried sync cannot double-post ---'
begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_org  uuid := 'c2c2c2c2-0000-0000-0000-000000000001';
    v_me   uuid := 'b2b2b2b2-0000-0000-0000-000000000002';
    v_uuid uuid := '99999999-0000-0000-0000-000000000001';
    v_a    uuid;
    v_b    uuid;
    v_n    int;
begin
    v_a := record_entry(
        p_org_id => v_org, p_amount => 25000, p_direction => 'in',
        p_label => 'Offrande du dimanche', p_recorded_by => v_me,
        p_client_uuid => v_uuid
    );
    -- The phone lost signal after the server committed and before the reply
    -- arrived, so it sends the identical payload again.
    v_b := record_entry(
        p_org_id => v_org, p_amount => 25000, p_direction => 'in',
        p_label => 'Offrande du dimanche', p_recorded_by => v_me,
        p_client_uuid => v_uuid
    );

    if v_a <> v_b then
        raise exception 'FAIL: the retry created a second entry';
    end if;

    select count(*) into v_n
      from journal_entries where org_id = v_org and client_uuid = v_uuid;
    if v_n <> 1 then
        raise exception 'FAIL: % entries share one client_uuid', v_n;
    end if;

    raise notice 'PASS: the same client_uuid returns the original entry';
end $$;
commit;

\echo ''
\echo '--- TEST 5: a transfer moves money without earning any ---'
begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_org    uuid := 'c2c2c2c2-0000-0000-0000-000000000001';
    v_before numeric;
    v_after  numeric;
    v_cash   numeric;
    v_bank   numeric;
begin
    select amount into v_before
      from income_statement(v_org) where section = 'total' and name = 'Résultat';

    perform record_transfer(
        p_org_id => v_org, p_amount => 20000,
        p_from_method => 'cash', p_to_method => 'bank',
        p_recorded_by => 'b2b2b2b2-0000-0000-0000-000000000002',
        p_label => 'Dépôt en banque'
    );

    select amount into v_after
      from income_statement(v_org) where section = 'total' and name = 'Résultat';

    if v_after <> v_before then
        raise exception
            'FAIL: banking cash changed the result from % to %', v_before, v_after;
    end if;

    select balance into v_bank from chart_of_accounts(v_org) where code = '1010';
    if v_bank <> 20000 then
        raise exception 'FAIL: bank balance is % after a 20000 deposit', v_bank;
    end if;

    -- 25,000 received in cash, 45,000 + 12,000 spent from cash, 20,000 banked.
    select balance into v_cash from chart_of_accounts(v_org) where code = '1000';
    if v_cash <> -52000 then
        raise exception 'FAIL: cash balance is %, expected -52000', v_cash;
    end if;

    raise notice 'PASS: a transfer moves the money and earns nothing';
end $$;
commit;

\echo ''
\echo '--- TEST 6: the trial balance balances ---'
begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_org uuid := 'c2c2c2c2-0000-0000-0000-000000000001';
    v_d   numeric;
    v_c   numeric;
begin
    select sum(total_debit), sum(total_credit) into v_d, v_c from trial_balance(v_org);

    if v_d is null or v_d = 0 then
        raise exception 'FAIL: the trial balance is empty';
    end if;
    if v_d <> v_c then
        raise exception 'FAIL: debits % <> credits % — something bypassed the ledger', v_d, v_c;
    end if;

    raise notice 'PASS: debits = credits = % across the whole chart', v_d;
end $$;
rollback;

\echo ''
\echo '--- TEST 7: the balance sheet balances, and agrees with the result ---'
begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_org    uuid := 'c2c2c2c2-0000-0000-0000-000000000001';
    v_assets numeric;
    v_claims numeric;
    v_result numeric;
    v_income numeric;
    v_spent  numeric;
begin
    select amount into v_assets from balance_sheet(v_org) where name = 'Total actif';
    select amount into v_claims from balance_sheet(v_org) where name = 'Total passif';

    if v_assets <> v_claims then
        raise exception 'FAIL: actif % <> passif %', v_assets, v_claims;
    end if;

    select amount into v_income from income_statement(v_org) where name = 'Produits';
    select amount into v_spent  from income_statement(v_org) where name = 'Charges';
    select amount into v_result from income_statement(v_org) where name = 'Résultat';

    if v_result <> v_income - v_spent then
        raise exception 'FAIL: résultat % <> produits % - charges %', v_result, v_income, v_spent;
    end if;

    -- 25,000 in, 57,000 out.
    if v_result <> -32000 then
        raise exception 'FAIL: résultat is %, expected -32000', v_result;
    end if;

    raise notice 'PASS: actif = passif = %, résultat = %', v_assets, v_result;
end $$;
rollback;

\echo ''
\echo '--- TEST 8: the ledger of one account runs a correct balance ---'
begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_org  uuid := 'c2c2c2c2-0000-0000-0000-000000000001';
    v_acct uuid;
    v_rows int;
    v_last numeric;
begin
    select id into v_acct
      from accounts
     where org_id = v_org and lower(btrim(name)) = 'réparation du toit';

    select count(*) into v_rows from account_ledger(v_org, v_acct);
    if v_rows <> 2 then
        raise exception 'FAIL: the roof account shows % movements, expected 2', v_rows;
    end if;

    -- account_ledger returns newest first, so the running balance on the top
    -- row is the closing one: 45,000 + 12,000.
    select balance into v_last from account_ledger(v_org, v_acct) limit 1;
    if v_last <> 57000 then
        raise exception 'FAIL: closing balance is %, expected 57000', v_last;
    end if;

    raise notice 'PASS: the account history totals what was spent on it';
end $$;
rollback;

\echo ''
\echo '--- TEST 9: the journal shows what people typed, not a category name ---'
begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_org uuid := 'c2c2c2c2-0000-0000-0000-000000000001';
    v_dir text;
begin
    if not exists (
        select 1 from journal_page(v_org) where label = 'Réparation du toit'
    ) then
        raise exception 'FAIL: the journal lost the name the person typed';
    end if;

    select direction into v_dir
      from journal_page(v_org) where label = 'Dépôt en banque';
    if v_dir <> 'transfer' then
        raise exception 'FAIL: a deposit reads as %, expected transfer', v_dir;
    end if;

    select direction into v_dir
      from journal_page(v_org) where label = 'Offrande du dimanche';
    if v_dir <> 'in' then
        raise exception 'FAIL: an offering reads as %, expected in', v_dir;
    end if;

    raise notice 'PASS: the journal reads back in the words it was written in';
end $$;
rollback;

\echo ''
\echo '--- TEST 10: the summary observer gets totals and no line items ---'
begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_org    uuid := 'c2c2c2c2-0000-0000-0000-000000000001';
    v_detail int;
    v_total  numeric;
    v_rows   int;
begin
    select count(*) into v_detail
      from income_statement(v_org) where section in ('income', 'expense');
    if v_detail <> 0 then
        raise exception
            'FAIL: a summary observer read % per-account rows of the income statement', v_detail;
    end if;

    select amount into v_total from income_statement(v_org) where name = 'Résultat';
    if v_total is null or v_total <> -32000 then
        raise exception 'FAIL: the observer cannot see the result they are entitled to (got %)', v_total;
    end if;

    select count(*) into v_detail from balance_sheet(v_org) where section <> 'total';
    if v_detail <> 0 then
        raise exception 'FAIL: a summary observer read % balance sheet lines', v_detail;
    end if;

    -- Line items, both of them, are the thing 'summary' withholds.
    select count(*) into v_rows from journal_page(v_org);
    if v_rows <> 0 then
        raise exception 'FAIL: a summary observer read % journal rows', v_rows;
    end if;

    raise notice 'PASS: summary means the totals and nothing underneath them';
end $$;
rollback;

\echo ''
\echo '--- TEST 11: an observer cannot record anything ---'
begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000003';
set local role authenticated;
do $$
begin
    begin
        perform record_entry(
            p_org_id => 'c2c2c2c2-0000-0000-0000-000000000001',
            p_amount => 1000, p_direction => 'in', p_label => 'Cadeau'
        );
        raise exception 'FAIL: an observer recorded an entry';
    exception
        when sqlstate 'P0001' then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: the observer was refused (%)', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 12: nobody outside the business reads or writes it ---'
begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000004';
set local role authenticated;
do $$
declare
    v_org uuid := 'c2c2c2c2-0000-0000-0000-000000000001';
    v_n   int;
begin
    select count(*) into v_n from chart_of_accounts(v_org);
    if v_n <> 0 then
        raise exception 'FAIL: a stranger read % accounts of another business', v_n;
    end if;

    select count(*) into v_n from trial_balance(v_org);
    if v_n <> 0 then
        raise exception 'FAIL: a stranger read another business trial balance';
    end if;

    select count(*) into v_n from journal_page(v_org);
    if v_n <> 0 then
        raise exception 'FAIL: a stranger read another business journal';
    end if;

    begin
        perform record_entry(
            p_org_id => v_org, p_amount => 1, p_direction => 'out', p_label => 'Vol'
        );
        raise exception 'FAIL: a stranger wrote to another business ledger';
    exception
        when sqlstate 'P0001' then
            if sqlerrm like 'FAIL:%' then raise; end if;
    end;

    raise notice 'PASS: another business is invisible and unwritable';
end $$;
rollback;

\echo ''
\echo '--- TEST 13: an entry cannot be recorded in someone else''s name ---'
begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000002';
set local role authenticated;
do $$
begin
    begin
        perform record_entry(
            p_org_id => 'c2c2c2c2-0000-0000-0000-000000000001',
            p_amount => 5000, p_direction => 'out', p_label => 'Achat',
            -- The treasurer's device, claiming the owner made the entry.
            p_recorded_by => 'b2b2b2b2-0000-0000-0000-000000000001'
        );
        raise exception 'FAIL: an entry was recorded under another user''s name';
    exception
        when sqlstate 'P0001' then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: the impersonated entry was refused (%)', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 14: only an admin designs the chart of accounts ---'
begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000002';
set local role authenticated;
do $$
begin
    begin
        perform create_account(
            'c2c2c2c2-0000-0000-0000-000000000001', 'Emprunt bancaire', 'liability'
        );
        raise exception 'FAIL: an employee created an account from the admin path';
    exception
        when sqlstate 'P0001' then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: create_account() refused a non-admin (%)', sqlerrm;
    end;
end $$;
rollback;

begin;
set local "request.jwt.claim.sub" = 'b2b2b2b2-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_org  uuid := 'c2c2c2c2-0000-0000-0000-000000000001';
    v_id   uuid;
    v_code text;
begin
    v_id := create_account(v_org, 'Emprunt bancaire', 'liability', 'Prêt du fonds mutuel');
    select code into v_code from accounts where id = v_id;
    if v_code <> '2000' then
        raise exception 'FAIL: the first liability got code %, expected 2000', v_code;
    end if;
    raise notice 'PASS: the owner adds a liability and it lands in the 2000 band';
end $$;
rollback;

\echo ''
\echo '--- TEST 15: an anonymous caller cannot reach any of it ---'
begin;
set local role anon;
do $$
declare v_org uuid := 'c2c2c2c2-0000-0000-0000-000000000001';
begin
    begin
        perform trial_balance(v_org);
        raise exception 'FAIL: anon executed trial_balance()';
    exception
        when insufficient_privilege then null;
        when sqlstate 'P0001' then
            if sqlerrm like 'FAIL:%' then raise; end if;
    end;

    begin
        perform record_entry(v_org, 1000, 'in', 'Rien');
        raise exception 'FAIL: anon executed record_entry()';
    exception
        when insufficient_privilege then null;
        when sqlstate 'P0001' then
            if sqlerrm like 'FAIL:%' then raise; end if;
    end;

    raise notice 'PASS: anon is refused execute on the accounting functions';
end $$;
rollback;

\echo ''
\echo '============================================'
\echo ' All accounting assertions passed.'
\echo '============================================'
