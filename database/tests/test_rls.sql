-- ============================================================
-- test_rls.sql — proof that a tenant cannot reach another tenant's books.
--
-- Every test here runs as the `authenticated` role, never as the superuser
-- that owns the tables: superusers bypass RLS entirely, so a suite run as
-- postgres would pass no matter how wrong the policies were.
--
-- Impersonation works exactly as it does in production. PostgREST puts the
-- signed-in user's id in request.jwt.claim.sub and auth.uid() reads it; here
-- the tests set the same GUC by hand.
--
-- Failures raise. A green run means every assertion below held.
-- ============================================================
\set ON_ERROR_STOP on

\set israel   '''11111111-1111-1111-1111-111111111111'''
\set ignace   '''aaaaaaaa-0000-0000-0000-000000000001'''
\set investor '''aaaaaaaa-0000-0000-0000-000000000002'''
\set esther   '''aaaaaaaa-0000-0000-0000-000000000003'''
\set nobody   '''aaaaaaaa-0000-0000-0000-000000000009'''

\set church '''22222222-2222-2222-2222-222222222222'''
\set farm   '''bbbbbbbb-0000-0000-0000-000000000001'''

-- ------------------------------------------------------------
-- The role the app actually connects as.
-- ------------------------------------------------------------
-- Supabase ships this role; on a bare Postgres we create it, with exactly the
-- table privileges PostgREST grants. Privileges say "you may query this
-- table"; the policies decide which rows come back.
do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- ------------------------------------------------------------
-- Two businesses that must never see each other.
-- ------------------------------------------------------------
insert into auth.users (id, phone, raw_user_meta_data) values
    (:ignace,   '+22670000001', '{"full_name": "Ignace"}'),
    (:investor, '+22670000002', '{"full_name": "Investisseur"}'),
    (:esther,   '+22670000003', '{"full_name": "Esther"}'),
    (:nobody,   '+22670000009', '{"full_name": "Personne"}');

insert into orgs (id, name, slug, profile) values
    (:farm, 'Ferme Ignace', 'ferme', 'farm');

select seed_church_accounts(:farm);   -- stands in for a farm chart of accounts

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:church, :israel,   'owner',    'org', :church),
    (:farm,   :ignace,   'owner',    'org', :farm),
    (:farm,   :investor, 'observer', 'org', :farm),
    -- Esther keeps the books for both businesses: the multi-org path.
    (:church, :esther,   'admin',    'org', :church),
    (:farm,   :esther,   'admin',    'org', :farm);

-- One entry in each org, written as superuser so the tests below have
-- something they are supposed to be denied.
select record_contribution(:farm, 30000, 'offering', :ignace, 'cash', null, 'Vente de volailles');

\echo ''
\echo '--- TEST 1: the profiles trigger fires on sign-up ---'
do $$
declare v_name text;
begin
    select full_name into v_name from profiles where id = 'aaaaaaaa-0000-0000-0000-000000000001';
    if v_name is distinct from 'Ignace' then
        raise exception 'FAIL: profile not created from auth.users (got %)', v_name;
    end if;
    raise notice 'PASS: auth.users insert created the profile row';
end $$;

\echo ''
\echo '--- TEST 2: Israel signs in and sees exactly his church ---'
begin;
set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';
set local role authenticated;
do $$
declare
    v_count int;
    v_name  text;
    v_prof  text;
begin
    select count(*) into v_count from my_orgs();
    if v_count <> 1 then
        raise exception 'FAIL: Israel sees % orgs, expected 1', v_count;
    end if;
    select name, profile into v_name, v_prof from my_orgs();
    if v_name <> 'Grace Chapel' or v_prof <> 'church' then
        raise exception 'FAIL: Israel resolved to % (%)', v_name, v_prof;
    end if;
    raise notice 'PASS: Israel -> Grace Chapel, profile=church (routes to the church home screen)';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: Ignace signs in on the same build and sees his farm ---'
begin;
set local "request.jwt.claim.sub" = 'aaaaaaaa-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_name text;
    v_prof text;
    v_count int;
begin
    select count(*) into v_count from my_orgs();
    if v_count <> 1 then
        raise exception 'FAIL: Ignace sees % orgs, expected 1', v_count;
    end if;
    select name, profile into v_name, v_prof from my_orgs();
    if v_name <> 'Ferme Ignace' or v_prof <> 'farm' then
        raise exception 'FAIL: Ignace resolved to % (%)', v_name, v_prof;
    end if;
    raise notice 'PASS: Ignace -> Ferme Ignace, profile=farm (routes to the farm home screen)';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: Israel cannot read the farm — not its org row, not its books ---'
begin;
set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';
set local role authenticated;
do $$
declare v_count int;
begin
    select count(*) into v_count from orgs where id = 'bbbbbbbb-0000-0000-0000-000000000001';
    if v_count <> 0 then
        raise exception 'FAIL: Israel can see the farm org row';
    end if;

    select count(*) into v_count from journal_entries
    where org_id = 'bbbbbbbb-0000-0000-0000-000000000001';
    if v_count <> 0 then
        raise exception 'FAIL: Israel can see % farm entries', v_count;
    end if;

    select count(*) into v_count from journal_lines;
    if v_count = 0 then
        raise exception 'FAIL: Israel cannot see his own lines either — policy too tight';
    end if;

    select count(*) into v_count from accounts
    where org_id = 'bbbbbbbb-0000-0000-0000-000000000001';
    if v_count <> 0 then
        raise exception 'FAIL: Israel can see the farm chart of accounts';
    end if;

    select count(*) into v_count from memberships
    where org_id = 'bbbbbbbb-0000-0000-0000-000000000001';
    if v_count <> 0 then
        raise exception 'FAIL: Israel can enumerate farm staff';
    end if;

    raise notice 'PASS: the farm is invisible to Israel — org, entries, accounts, staff';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: Israel cannot write into the farm even knowing its id ---'
begin;
set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';
set local role authenticated;
do $$
begin
    insert into journal_entries (org_id, memo, created_by)
    values ('bbbbbbbb-0000-0000-0000-000000000001', 'Injected',
            '11111111-1111-1111-1111-111111111111');
    raise exception 'FAIL: Israel wrote an entry into the farm ledger';
exception
    when insufficient_privilege then
        raise notice 'PASS: cross-tenant insert refused';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: the observer reads the farm books but cannot touch them ---'
begin;
set local "request.jwt.claim.sub" = 'aaaaaaaa-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v_count int;
begin
    select count(*) into v_count from journal_entries
    where org_id = 'bbbbbbbb-0000-0000-0000-000000000001';
    if v_count = 0 then
        raise exception 'FAIL: the investor cannot read the books they invested in';
    end if;

    begin
        insert into journal_entries (org_id, memo, created_by)
        values ('bbbbbbbb-0000-0000-0000-000000000001', 'Observer entry',
                'aaaaaaaa-0000-0000-0000-000000000002');
        raise exception 'FAIL: an observer recorded a transaction';
    exception
        when insufficient_privilege then null;
    end;

    begin
        insert into memberships (org_id, user_id, role, scope_kind, scope_id)
        values ('bbbbbbbb-0000-0000-0000-000000000001',
                'aaaaaaaa-0000-0000-0000-000000000002', 'owner', 'org',
                'bbbbbbbb-0000-0000-0000-000000000001');
        raise exception 'FAIL: an observer promoted themselves to owner';
    exception
        when insufficient_privilege then null;
    end;

    raise notice 'PASS: observer reads everything, writes nothing, cannot self-promote';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: Esther keeps two sets of books and gets a picker ---'
begin;
set local "request.jwt.claim.sub" = 'aaaaaaaa-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_count int;
    v_profiles text;
begin
    select count(*) into v_count from my_orgs();
    if v_count <> 2 then
        raise exception 'FAIL: Esther sees % orgs, expected 2', v_count;
    end if;
    select string_agg(profile, ',' order by profile) into v_profiles from my_orgs();
    if v_profiles <> 'church,farm' then
        raise exception 'FAIL: Esther resolved to profiles [%]', v_profiles;
    end if;
    raise notice 'PASS: Esther -> 2 orgs (church, farm) — the app shows a picker';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: a verified phone with no invitation sees nothing at all ---'
begin;
set local "request.jwt.claim.sub" = 'aaaaaaaa-0000-0000-0000-000000000009';
set local role authenticated;
do $$
declare v_count int;
begin
    select count(*) into v_count from my_orgs();
    if v_count <> 0 then
        raise exception 'FAIL: an uninvited user resolved to % orgs', v_count;
    end if;
    select count(*) into v_count from orgs;
    if v_count <> 0 then
        raise exception 'FAIL: an uninvited user can list % orgs', v_count;
    end if;
    select count(*) into v_count from journal_entries;
    if v_count <> 0 then
        raise exception 'FAIL: an uninvited user can read % entries', v_count;
    end if;
    raise notice 'PASS: no membership, no data — the app shows "waiting for invitation"';
end $$;
rollback;

\echo ''
\echo '--- TEST 9: an anonymous caller (publishable key, no session) gets nothing ---'
begin;
set local role authenticated;   -- authenticated role, but auth.uid() is null
do $$
declare v_count int;
begin
    select count(*) into v_count from orgs;
    if v_count <> 0 then
        raise exception 'FAIL: a caller with no session read % orgs', v_count;
    end if;
    select count(*) into v_count from journal_entries;
    if v_count <> 0 then
        raise exception 'FAIL: a caller with no session read % entries', v_count;
    end if;
    raise notice 'PASS: no session, no rows';
end $$;
rollback;

\echo ''
\echo '--- TEST 10: history cannot be rewritten, not even by the owner ---'
begin;
set local "request.jwt.claim.sub" = 'aaaaaaaa-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_updated int;
    v_deleted int;
    v_still   int;
begin
    update journal_entries set memo = 'Rewritten'
    where org_id = 'bbbbbbbb-0000-0000-0000-000000000001';
    get diagnostics v_updated = row_count;

    delete from journal_lines;
    get diagnostics v_deleted = row_count;

    if v_updated <> 0 or v_deleted <> 0 then
        raise exception 'FAIL: owner rewrote % entries and deleted % lines',
            v_updated, v_deleted;
    end if;

    select count(*) into v_still from journal_entries
    where org_id = 'bbbbbbbb-0000-0000-0000-000000000001'
      and memo = 'Vente de volailles';
    if v_still <> 1 then
        raise exception 'FAIL: the original entry did not survive';
    end if;

    raise notice 'PASS: the ledger is append-only to everyone — undo stays a reversing entry';
end $$;
rollback;

\echo ''
\echo '--- TEST 11: Ignace records a sale through the normal path ---'
begin;
set local "request.jwt.claim.sub" = 'aaaaaaaa-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_entry uuid;
    v_lines int;
begin
    v_entry := record_contribution(
        'bbbbbbbb-0000-0000-0000-000000000001', 15000, 'offering',
        'aaaaaaaa-0000-0000-0000-000000000001', 'mobile_money'
    );
    select count(*) into v_lines from journal_lines where journal_entry_id = v_entry;
    if v_lines <> 2 then
        raise exception 'FAIL: entry wrote % lines through RLS, expected 2', v_lines;
    end if;
    raise notice 'PASS: a member records normally — policies do not block real work';
end $$;
rollback;

\echo ''
\echo '=== RLS SUITE COMPLETE — all assertions held ==='
