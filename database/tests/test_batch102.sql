-- ============================================================
-- test_batch102.sql — an association's first minutes (102). Phone block 57.
--
-- The claims: every association and church already there is set up (once:
-- one created later is not), so nobody is shown the walkthrough and no
-- worker is lost; a new association has no free worker until its
-- walkthrough is finished, then one; its kind and its line are an admin's
-- to write (a wrong kind, a non-admin, a shop refused); its members are
-- records — three added, the same phone twice is one member, none takes a
-- seat, an outsider adds nobody; it finishes with nothing else required,
-- while a shop still needs its first article; feature_states says the
-- setup as the team does, and whether money has come in (an income line,
-- a tontine payment; an entry undone is none) for an association only; a
-- generic business stays done; the new doors are closed to anon, the
-- engine to the app.
-- ============================================================
\set ON_ERROR_STOP on
-- The owner's numbers: earlier suites change them for their own fixtures.
update platform_settings set value = '1'  where key = 'free_max_staff';
update platform_settings set value = '0'  where key = 'path_gates_open';

\set treas   '''57575757-0000-0000-0000-000000000001'''
\set w1      '''57575757-0000-0000-0000-000000000002'''
\set w2      '''57575757-0000-0000-0000-000000000003'''
\set boss    '''57575757-0000-0000-0000-000000000004'''
\set stranger '''57575757-0000-0000-0000-000000000005'''
\set old     '''57000000-0000-0000-0000-000000000001'''
\set oldch   '''57000000-0000-0000-0000-000000000002'''
\set assoc   '''57000000-0000-0000-0000-000000000003'''
\set shop    '''57000000-0000-0000-0000-000000000004'''
\set gen     '''57000000-0000-0000-0000-000000000005'''

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
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:treas,    '+22657000001', '{"full_name": "Trésorière"}'),
    (:w1,       '+22657000002', '{"full_name": "Awa"}'),
    (:w2,       '+22657000003', '{"full_name": "Bintou"}'),
    (:boss,     '+22657000004', '{"full_name": "Patronne"}'),
    (:stranger, '+22657000005', '{"full_name": "Passante"}');

-- Two associations already there (a church among them) when 102 is first
-- applied: the marker is taken away so the re-application below is that
-- first time, for them.
insert into orgs (id, name, slug, profile, default_currency, plan) values
    (:old,   'Ancienne 57', 'ancienne-57', 'association', 'XOF', 'free'),
    (:oldch, 'Paroisse 57', 'paroisse-57', 'church',      'XOF', 'free');
update orgs set setup_done_at = null where id in (:old, :oldch);
delete from platform_settings where key = 'association_setup_marked';

-- Earlier suites re-apply older migrations over 102's functions, and 063
-- (test_least_privilege) re-grants every definer function: 102 again, so
-- what follows tests its own definitions and grants.
\i database/migrations/102_association_setup.sql

-- Created after: new businesses, with their walkthrough ahead of them.
insert into orgs (id, name, slug, profile, default_currency, plan) values
    (:assoc, 'Entraide 57', 'entraide-57', 'association', 'XOF', 'free'),
    (:shop,  'Boutique 57', 'boutique-57', 'retail',      'XOF', 'free'),
    (:gen,   'Autre 57',    'autre-57',    'generic',     'XOF', 'free');
update orgs set setup_done_at = null where id in (:assoc, :shop, :gen);
select seed_church_accounts(:assoc);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:old,   :treas, 'owner', 'org', :old,   'full'),
    (:assoc, :treas, 'owner', 'org', :assoc, 'full'),
    (:shop,  :boss,  'owner', 'org', :shop,  'full'),
    (:gen,   :boss,  'owner', 'org', :gen,   'full');

\echo ''
\echo '--- TEST 1: the associations already there are set up, once; a re-run marks no new one ---'
do $$ begin
    if exists (select 1 from orgs where id in ('57000000-0000-0000-0000-000000000001',
                                              '57000000-0000-0000-0000-000000000002')
                                    and setup_done_at is null) then
        raise exception 'FAIL: an existing association or church was left to its walkthrough';
    end if;
    if not org_setup_done('57000000-0000-0000-0000-000000000001')
       or not org_setup_done('57000000-0000-0000-0000-000000000002') then
        raise exception 'FAIL: an existing association is not set up for the team';
    end if;
end $$;
\i database/migrations/102_association_setup.sql
do $$ begin
    if (select setup_done_at from orgs where id = '57000000-0000-0000-0000-000000000003') is not null then
        raise exception 'FAIL: a re-run marked a new association as set up';
    end if;
    if not org_setup_done('57000000-0000-0000-0000-000000000005') then
        raise exception 'FAIL: a generic business has a walkthrough now';
    end if;
    raise notice 'PASS: existing associations and churches are set up, once; a generic business stays done';
end $$;

\echo ''
\echo '--- TEST 2: a new association has no free worker before its walkthrough ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000001';
do $$
declare f jsonb := feature_states('57000000-0000-0000-0000-000000000003');
begin
    if (f ->> 'setup_done')::boolean or (f -> 'team' ->> 'setup_done')::boolean
       or (f -> 'team' ->> 'free')::int <> 0 then
        raise exception 'FAIL: a new association is shown set up: %', f;
    end if;
    begin
        insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
        values ('57000000-0000-0000-0000-000000000003', '57575757-0000-0000-0000-000000000002',
                'employee', 'org', '57000000-0000-0000-0000-000000000003', 'full');
        raise exception 'FAIL: a worker joined an association not set up';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : la personne offerte s''ouvre une fois la mise en route%' then raise; end if;
    end;
    -- The old one keeps its free worker.
    insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
    values ('57000000-0000-0000-0000-000000000001', '57575757-0000-0000-0000-000000000002',
            'employee', 'org', '57000000-0000-0000-0000-000000000001', 'full');
    raise notice 'PASS: no seat before the walkthrough; an association already there keeps its worker';
end $$;
commit;

\echo ''
\echo '--- TEST 3: its kind and its line, an admin''s, for an association only ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000001';
select set_association_kind('57000000-0000-0000-0000-000000000003', 'Tontine', '  On cotise, chacun reçoit à son tour.  ');
do $$ begin
    if (select association_kind from orgs where id = '57000000-0000-0000-0000-000000000003') <> 'tontine'
       or (select storefront_blurb from orgs where id = '57000000-0000-0000-0000-000000000003')
          <> 'On cotise, chacun reçoit à son tour.' then
        raise exception 'FAIL: the kind or the line was not kept';
    end if;
    perform set_association_kind('57000000-0000-0000-0000-000000000003', null, null);
    if (select association_kind from orgs where id = '57000000-0000-0000-0000-000000000003') <> 'tontine'
       or (select storefront_blurb from orgs where id = '57000000-0000-0000-0000-000000000003') is null then
        raise exception 'FAIL: null cleared what was said';
    end if;
    begin
        perform set_association_kind('57000000-0000-0000-0000-000000000003', 'secte', null);
        raise exception 'FAIL: an unknown kind was kept';
    exception when raise_exception then
        if sqlerrm <> 'Type d''association inconnu' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000004';
do $$ begin
    begin
        perform set_association_kind('57000000-0000-0000-0000-000000000004', 'autre', null);
        raise exception 'FAIL: a shop was given an association''s kind';
    exception when raise_exception then
        if sqlerrm <> 'Réservé aux associations' then raise; end if;
    end;
    begin
        perform set_association_kind('57000000-0000-0000-0000-000000000003', 'autre', null);
        raise exception 'FAIL: somebody outside wrote an association''s kind';
    exception when raise_exception then
        if sqlerrm <> 'Seul un administrateur termine la mise en route' then raise; end if;
    end;
    raise notice 'PASS: the kind and the line kept, null leaves them, a wrong kind, a shop and an outsider refused';
end $$;
commit;

\echo ''
\echo '--- TEST 4: three members, records not accounts; the same phone is one member ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000001';
do $$
declare a uuid; b uuid;
begin
    a := add_association_member('57000000-0000-0000-0000-000000000003', ' Awa Ouédraogo ', '+226 57 11 00 01');
    perform add_association_member('57000000-0000-0000-0000-000000000003', 'Bintou', '+22657110002');
    perform add_association_member('57000000-0000-0000-0000-000000000003', 'Coumba', null);
    -- Tapped twice: the same member, its name as typed the second time.
    b := add_association_member('57000000-0000-0000-0000-000000000003', 'Awa O.', '+22657110001');
    if a <> b then
        raise exception 'FAIL: the same phone made a second member';
    end if;
    if (select count(*) from church_members where org_id = '57000000-0000-0000-0000-000000000003') <> 3 then
        raise exception 'FAIL: % members, not 3',
            (select count(*) from church_members where org_id = '57000000-0000-0000-0000-000000000003');
    end if;
    if (select full_name from church_members where id = a) <> 'Awa O.'
       or (select phone from church_members where id = a) <> '+22657110001' then
        raise exception 'FAIL: the member was not kept as typed';
    end if;
    if (feature_states('57000000-0000-0000-0000-000000000003') -> 'team' ->> 'used')::int <> 0 then
        raise exception 'FAIL: a member record took a worker''s seat';
    end if;
    begin
        perform add_association_member('57000000-0000-0000-0000-000000000003', '  ', null);
        raise exception 'FAIL: a member with no name';
    exception when raise_exception then
        if sqlerrm <> 'Le nom du membre, s''il vous plaît.' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000005';
do $$ begin
    begin
        perform add_association_member('57000000-0000-0000-0000-000000000003', 'Intrus', null);
        raise exception 'FAIL: an outsider added a member';
    exception when raise_exception then
        if sqlerrm <> 'Réservé aux membres de l''association' then raise; end if;
    end;
    raise notice 'PASS: three members kept, one phone one member, no seat taken, no name and an outsider refused';
end $$;
commit;

\echo ''
\echo '--- TEST 5: finishing: nothing more for an association, the first article for a shop ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000004';
do $$ begin
    begin
        perform finish_setup('57000000-0000-0000-0000-000000000004');
        raise exception 'FAIL: a shop finished without an article';
    exception when raise_exception then
        if sqlerrm <> 'Ajoutez d''abord un article.' then raise; end if;
    end;
    begin
        perform finish_setup('57000000-0000-0000-0000-000000000003');
        raise exception 'FAIL: an outsider finished an association''s setup';
    exception when raise_exception then
        if sqlerrm <> 'Seul un administrateur termine la mise en route' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000001';
select finish_setup('57000000-0000-0000-0000-000000000003');
do $$
declare f jsonb := feature_states('57000000-0000-0000-0000-000000000003');
begin
    if not (f ->> 'setup_done')::boolean or not (f -> 'team' ->> 'setup_done')::boolean
       or (f -> 'team' ->> 'free')::int <> 1 or not (f -> 'team' ->> 'open')::boolean then
        raise exception 'FAIL: the finished association has no free worker: %', f -> 'team';
    end if;
    insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
    values ('57000000-0000-0000-0000-000000000003', '57575757-0000-0000-0000-000000000002',
            'employee', 'org', '57000000-0000-0000-0000-000000000003', 'full');
    begin
        insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
        values ('57000000-0000-0000-0000-000000000003', '57575757-0000-0000-0000-000000000003',
                'employee', 'org', '57000000-0000-0000-0000-000000000003', 'full');
        raise exception 'FAIL: a second worker joined a Basic association';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : cette entreprise a déjà sa personne offerte%' then raise; end if;
    end;
    raise notice 'PASS: the shop needs its article; the association finishes, earns its one worker, then the refusal';
end $$;
commit;

\echo ''
\echo '--- TEST 6: the first income, for an association only ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000001';
do $$
declare e uuid;
begin
    if (feature_states('57000000-0000-0000-0000-000000000003') ->> 'first_income')::boolean then
        raise exception 'FAIL: money came in before any was recorded';
    end if;
    -- An expense is no income.
    perform record_entry('57000000-0000-0000-0000-000000000003', 2000, 'out', 'Loyer',
                         '57575757-0000-0000-0000-000000000001');
    e := record_entry('57000000-0000-0000-0000-000000000003', 5000, 'in', 'Cotisation',
                      '57575757-0000-0000-0000-000000000001');
    if not (feature_states('57000000-0000-0000-0000-000000000003') ->> 'first_income')::boolean then
        raise exception 'FAIL: the first contribution was not seen';
    end if;
end $$;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000004';
do $$ begin
    if feature_states('57000000-0000-0000-0000-000000000004') ? 'first_income'
       and feature_states('57000000-0000-0000-0000-000000000004') ->> 'first_income' is not null then
        raise exception 'FAIL: a shop is told about its first contribution';
    end if;
    raise notice 'PASS: an expense is none, a contribution is the first income; a shop is not asked';
end $$;
commit;

-- An entry undone is not an income (as the owner, past RLS).
do $$
declare e uuid;
begin
    select je.id into e from journal_entries je
     where je.org_id = '57000000-0000-0000-0000-000000000003' and je.memo is distinct from 'x'
       and exists (select 1 from journal_lines jl join accounts a on a.id = jl.account_id
                    where jl.journal_entry_id = je.id and a.type = 'income')
     limit 1;
    insert into journal_entries (org_id, memo, created_by, reverses_entry_id)
    values ('57000000-0000-0000-0000-000000000003', 'Correction',
            '57575757-0000-0000-0000-000000000001', e);
    if org_first_income('57000000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: an income undone still counts';
    end if;
    raise notice 'PASS: an income undone is no income';
end $$;

\echo ''
\echo '--- TEST 7: the doors ---'
do $$ begin
    if has_function_privilege('anon', 'set_association_kind(uuid, text, text)', 'execute')
       or has_function_privilege('anon', 'add_association_member(uuid, text, text)', 'execute')
       or has_function_privilege('anon', 'finish_setup(uuid)', 'execute')
       or has_function_privilege('anon', 'feature_states(uuid)', 'execute')
       or has_function_privilege('anon', 'org_first_income(uuid)', 'execute')
       or has_function_privilege('anon', 'org_setup_done(uuid)', 'execute') then
        raise exception 'FAIL: a new door is open to anon';
    end if;
    if has_function_privilege('authenticated', 'org_first_income(uuid)', 'execute')
       or has_function_privilege('authenticated', 'org_setup_done(uuid)', 'execute') then
        raise exception 'FAIL: the engine is open to the app';
    end if;
    if not has_function_privilege('authenticated', 'set_association_kind(uuid, text, text)', 'execute')
       or not has_function_privilege('authenticated', 'add_association_member(uuid, text, text)', 'execute')
       or not has_function_privilege('authenticated', 'finish_setup(uuid)', 'execute')
       or not has_function_privilege('authenticated', 'feature_states(uuid)', 'execute') then
        raise exception 'FAIL: the app cannot reach its doors';
    end if;
    if (select prosecdef from pg_proc where proname = 'add_association_member') then
        raise exception 'FAIL: add_association_member must run as the caller (RLS-bound)';
    end if;
    raise notice 'PASS: anon reaches none, the app its doors only, members written as the caller';
end $$;
