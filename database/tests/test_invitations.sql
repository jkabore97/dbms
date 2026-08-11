-- ============================================================
-- test_invitations.sql — proof that an invitation grants exactly what it says
-- and never one grant more.
--
-- Same discipline as test_rls.sql: every assertion runs as the `authenticated`
-- role with request.jwt.claim.sub set, never as the superuser that owns the
-- tables. A superuser bypasses RLS, so a suite run as postgres would pass
-- against no policies at all.
--
-- Unlike test_rls.sql, several blocks here COMMIT rather than roll back: an
-- invitation is written by one person and claimed by another, and those are
-- two different transactions by definition. Impersonation is still `set local`
-- and still ends with the transaction.
--
-- Failures raise. A green run means every assertion below held.
-- ============================================================
\set ON_ERROR_STOP on

\set admin_a   '''cccccccc-0000-0000-0000-000000000001'''
\set admin_b   '''cccccccc-0000-0000-0000-000000000002'''
\set newcomer  '''cccccccc-0000-0000-0000-000000000003'''
\set bearer    '''cccccccc-0000-0000-0000-000000000004'''
\set imposter  '''cccccccc-0000-0000-0000-000000000005'''
\set employee  '''cccccccc-0000-0000-0000-000000000006'''

\set org_a '''dddddddd-0000-0000-0000-00000000000a'''
\set org_b '''dddddddd-0000-0000-0000-00000000000b'''

\set site_a '''eeeeeeee-0000-0000-0000-00000000000a'''
\set dept_a '''ffffffff-0000-0000-0000-00000000000a'''

-- ------------------------------------------------------------
-- The role the app actually connects as.
-- ------------------------------------------------------------
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
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
-- anon gets exactly what Supabase gives a caller holding only the publishable
-- key: table privileges, and policies that will deny them anyway.
grant select, insert, update, delete on all tables in schema public to anon;
grant execute on function invitation_preview(text) to anon;

-- ------------------------------------------------------------
-- Two businesses, and four people who are about to find out how little a code
-- is worth.
-- ------------------------------------------------------------
insert into auth.users (id, phone, email, raw_user_meta_data) values
    (:admin_a,  '+22671000001', 'admin.a@test.local',  '{"full_name": "Admin A"}'),
    (:admin_b,  '+22671000002', 'admin.b@test.local',  '{"full_name": "Admin B"}'),
    (:newcomer, '+22671000003', 'newcomer@test.local', '{"full_name": "Nouvelle recrue"}'),
    (:bearer,   '+22671000004', 'bearer@test.local',   '{"full_name": "Porteur"}'),
    (:imposter, '+22671000005', 'imposter@test.local', '{"full_name": "Imposteur"}'),
    (:employee, '+22671000006', 'employee@test.local', '{"full_name": "Employé"}');

insert into orgs (id, name, slug, profile) values
    (:org_a, 'Église Test A', 'test-a', 'church'),
    (:org_b, 'Ferme Test B',  'test-b', 'farm');

insert into entities (id, org_id, name, kind) values
    (:site_a, :org_a, 'Campus principal', 'campus');

insert into departments (id, entity_id, name) values
    (:dept_a, :site_a, 'Chorale');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:org_a, :admin_a,  'owner',    'org', :org_a),
    (:org_b, :admin_b,  'owner',    'org', :org_b),
    -- An ordinary member of A: holds a role, administers nothing.
    (:org_a, :employee, 'employee', 'org', :org_a);

-- Something in B that must stay invisible to anyone holding an A code.
insert into journal_entries (org_id, memo, created_by)
values (:org_b, 'Vente de volailles B', :admin_b);


\echo ''
\echo '--- TEST 1: an admin issues an invitation through RLS, and the invited user gets exactly that role at exactly that scope ---'

-- Written by the admin as the app writes it: authenticated, policy-checked,
-- created_by forced to themselves.
begin;
set local "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-000000000001';
set local role authenticated;
insert into pending_invitations
    (org_id, role, scope_kind, scope_id, code, phone, created_by)
values
    ('dddddddd-0000-0000-0000-00000000000a', 'supervisor', 'department',
     'ffffffff-0000-0000-0000-00000000000a', 'CHOR-2468', '+22671000003',
     'cccccccc-0000-0000-0000-000000000001');
commit;

begin;
set local "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_org     uuid;
    v_count   int;
    v_role    text;
    v_kind    text;
    v_scope   uuid;
    v_vis     text;
begin
    -- Typed by a human off a scrap of paper: lowercase, a space, no dash.
    v_org := claim_invitation('chor 2468');
    if v_org <> 'dddddddd-0000-0000-0000-00000000000a' then
        raise exception 'FAIL: claim returned org %, expected A', v_org;
    end if;

    select count(*) into v_count from memberships
    where user_id = 'cccccccc-0000-0000-0000-000000000003';
    if v_count <> 1 then
        raise exception 'FAIL: newcomer holds % memberships, expected 1', v_count;
    end if;

    select role::text, scope_kind::text, scope_id, visibility
      into v_role, v_kind, v_scope, v_vis
    from memberships where user_id = 'cccccccc-0000-0000-0000-000000000003';

    if v_role <> 'supervisor' then
        raise exception 'FAIL: granted role %, expected supervisor', v_role;
    end if;
    if v_kind <> 'department' then
        raise exception 'FAIL: granted scope_kind %, expected department', v_kind;
    end if;
    if v_scope <> 'ffffffff-0000-0000-0000-00000000000a' then
        raise exception 'FAIL: granted scope_id %, expected the Chorale department', v_scope;
    end if;
    if v_vis <> 'full' then
        raise exception 'FAIL: granted visibility %, expected full', v_vis;
    end if;

    raise notice 'PASS: supervisor at the Chorale department — the exact grant, and nothing wider';
end $$;
commit;

\echo ''
\echo '--- TEST 2: claiming twice yields one membership, and does not look like a failure ---'
begin;
set local "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_org   uuid;
    v_count int;
begin
    -- The second tap of a double-tap, or the user who was told "try again".
    v_org := claim_invitation('CHOR-2468');
    if v_org <> 'dddddddd-0000-0000-0000-00000000000a' then
        raise exception 'FAIL: re-claim returned %, expected the same org', v_org;
    end if;

    v_org := claim_invitation('CHOR-2468');

    select count(*) into v_count from memberships
    where user_id = 'cccccccc-0000-0000-0000-000000000003';
    if v_count <> 1 then
        raise exception 'FAIL: three claims produced % memberships', v_count;
    end if;

    raise notice 'PASS: claimed three times, one membership, no error';
end $$;
commit;

-- The invitation side of the same fact, checked as the superuser: the claimer
-- is a supervisor, not an admin, so RLS quite correctly shows them no
-- invitation row at all — including their own.
do $$
declare
    v_count int;
    v_by    uuid;
begin
    select count(*) into v_count from pending_invitations
    where normalize_invitation_code(code) = 'CHOR2468';
    if v_count <> 1 then
        raise exception 'FAIL: % rows carry the code, expected 1', v_count;
    end if;

    select claimed_by into v_by from pending_invitations
    where normalize_invitation_code(code) = 'CHOR2468';
    if v_by <> 'cccccccc-0000-0000-0000-000000000003' then
        raise exception 'FAIL: the invitation records % as the claimer', v_by;
    end if;

    raise notice 'PASS: one invitation row, stamped once, with who used it';
end $$;

\echo ''
\echo '--- TEST 3: a code for org A never grants anything in org B ---'
begin;
set local "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_count int;
    v_name  text;
begin
    select count(*) into v_count from my_orgs();
    if v_count <> 1 then
        raise exception 'FAIL: the A code resolved to % orgs', v_count;
    end if;
    select name into v_name from my_orgs();
    if v_name <> 'Église Test A' then
        raise exception 'FAIL: the A code opened %', v_name;
    end if;

    select count(*) into v_count from orgs
    where id = 'dddddddd-0000-0000-0000-00000000000b';
    if v_count <> 0 then
        raise exception 'FAIL: an A invitation exposed the org B row';
    end if;

    select count(*) into v_count from journal_entries
    where org_id = 'dddddddd-0000-0000-0000-00000000000b';
    if v_count <> 0 then
        raise exception 'FAIL: an A invitation exposed % of B''s entries', v_count;
    end if;

    select count(*) into v_count from memberships
    where org_id = 'dddddddd-0000-0000-0000-00000000000b';
    if v_count <> 0 then
        raise exception 'FAIL: an A invitation exposed B''s staff list';
    end if;

    raise notice 'PASS: org A only — B''s row, books and staff all stayed invisible';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: an expired code grants nothing ---'
insert into pending_invitations
    (org_id, role, scope_kind, scope_id, code, expires_at, created_by)
values
    (:org_a, 'admin', 'org', :org_a, 'DEAD-1111', now() - interval '1 day', :admin_a);

begin;
set local "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-000000000004';
set local role authenticated;
do $$
declare v_count int;
begin
    begin
        perform claim_invitation('DEAD-1111');
        raise exception 'FAIL: an expired code was accepted';
    exception
        when no_data_found then null;
    end;

    select count(*) into v_count from memberships
    where user_id = 'cccccccc-0000-0000-0000-000000000004';
    if v_count <> 0 then
        raise exception 'FAIL: an expired code left % memberships behind', v_count;
    end if;

    select count(*) into v_count from my_orgs();
    if v_count <> 0 then
        raise exception 'FAIL: an expired code resolved to % orgs', v_count;
    end if;

    raise notice 'PASS: expired code refused, nothing granted';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: an invitation addressed to one phone is refused to another ---'
insert into pending_invitations
    (org_id, role, scope_kind, scope_id, code, phone, created_by)
values
    (:org_a, 'admin', 'org', :org_a, 'MINE-9999', '+22671000004', :admin_a);

begin;
set local "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-000000000005';
set local role authenticated;
do $$
declare v_count int;
begin
    begin
        perform claim_invitation('MINE-9999');
        raise exception 'FAIL: a code addressed to another number was accepted';
    exception
        when insufficient_privilege then null;
    end;

    select count(*) into v_count from memberships
    where user_id = 'cccccccc-0000-0000-0000-000000000005';
    if v_count <> 0 then
        raise exception 'FAIL: the imposter came away with % memberships', v_count;
    end if;

    raise notice 'PASS: a code with a phone on it belongs to that phone only';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: the sign-in sweep claims what was addressed to you, and only that ---'
begin;
set local "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-000000000004';
set local role authenticated;
do $$
declare
    v_n     int;
    v_count int;
begin
    -- MINE-9999 is addressed to this phone; DEAD-1111 is a bearer code that is
    -- also expired. Neither the expired one nor anyone else's may be swept up.
    v_n := claim_my_invitations();
    if v_n <> 1 then
        raise exception 'FAIL: the sweep claimed % invitations, expected 1', v_n;
    end if;

    select count(*) into v_count from memberships
    where user_id = 'cccccccc-0000-0000-0000-000000000004';
    if v_count <> 1 then
        raise exception 'FAIL: the sweep left % memberships', v_count;
    end if;

    -- Idempotent: signing in again sweeps nothing, because there is nothing left.
    v_n := claim_my_invitations();
    if v_n <> 0 then
        raise exception 'FAIL: the second sweep re-claimed % invitations', v_n;
    end if;

    raise notice 'PASS: phone-addressed invitation claimed with nothing typed; second sign-in is a no-op';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: only admins may read or issue their org''s invitations ---'
begin;
set local "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-000000000006';
set local role authenticated;
do $$
declare v_count int;
begin
    -- An employee of A: a real member, with no business seeing who else is
    -- being invited or minting codes of their own.
    select count(*) into v_count from pending_invitations;
    if v_count <> 0 then
        raise exception 'FAIL: a non-admin member read % invitations', v_count;
    end if;

    begin
        insert into pending_invitations
            (org_id, role, scope_kind, scope_id, code, created_by)
        values ('dddddddd-0000-0000-0000-00000000000a', 'owner', 'org',
                'dddddddd-0000-0000-0000-00000000000a', 'SELF-0001',
                'cccccccc-0000-0000-0000-000000000006');
        raise exception 'FAIL: a non-admin issued an invitation';
    exception
        when insufficient_privilege then null;
    end;

    raise notice 'PASS: an employee can neither read nor issue invitations';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: an admin of B cannot issue an invitation into A, nor read A''s ---'
begin;
set local "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v_count int;
begin
    select count(*) into v_count from pending_invitations
    where org_id = 'dddddddd-0000-0000-0000-00000000000a';
    if v_count <> 0 then
        raise exception 'FAIL: B''s admin read % of A''s invitations', v_count;
    end if;

    begin
        insert into pending_invitations
            (org_id, role, scope_kind, scope_id, code, created_by)
        values ('dddddddd-0000-0000-0000-00000000000a', 'owner', 'org',
                'dddddddd-0000-0000-0000-00000000000a', 'CROS-0001',
                'cccccccc-0000-0000-0000-000000000002');
        raise exception 'FAIL: B''s admin wrote an invitation into A';
    exception
        when insufficient_privilege then null;
    end;

    raise notice 'PASS: administering B grants nothing over A';
end $$;
rollback;

\echo ''
\echo '--- TEST 9: an admin cannot forge an invitation from someone else ---'
begin;
set local "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-000000000001';
set local role authenticated;
do $$
begin
    begin
        insert into pending_invitations
            (org_id, role, scope_kind, scope_id, code, created_by)
        values ('dddddddd-0000-0000-0000-00000000000a', 'admin', 'org',
                'dddddddd-0000-0000-0000-00000000000a', 'FORG-0001',
                'cccccccc-0000-0000-0000-000000000006');
        raise exception 'FAIL: created_by was accepted as someone else';
    exception
        when insufficient_privilege then null;
    end;
    raise notice 'PASS: an invitation always records who really issued it';
end $$;
rollback;

\echo ''
\echo '--- TEST 10: a stranger holding a code learns the business name and nothing else ---'
insert into pending_invitations
    (org_id, role, scope_kind, scope_id, code, created_by)
values
    (:org_a, 'employee', 'org', :org_a, 'OPEN-7777', :admin_a);

begin;
set local role anon;   -- no session at all: the publishable key and a code
do $$
declare
    v_name  text;
    v_count int;
begin
    v_name := invitation_preview('open 7777');
    if v_name is distinct from 'Église Test A' then
        raise exception 'FAIL: preview returned % for a live code', v_name;
    end if;

    -- That is the entire surface. The row itself stays closed.
    select count(*) into v_count from pending_invitations;
    if v_count <> 0 then
        raise exception 'FAIL: an anonymous caller read % invitation rows', v_count;
    end if;
    select count(*) into v_count from orgs;
    if v_count <> 0 then
        raise exception 'FAIL: an anonymous caller listed % orgs', v_count;
    end if;

    -- An expired code and a claimed one preview nothing: a stranger cannot use
    -- the preview to sweep for which codes are live.
    if invitation_preview('DEAD-1111') is not null then
        raise exception 'FAIL: an expired code still previews';
    end if;
    if invitation_preview('CHOR-2468') is not null then
        raise exception 'FAIL: a claimed code still previews';
    end if;
    if invitation_preview('ZZZZ-0000') is not null then
        raise exception 'FAIL: a nonexistent code previewed something';
    end if;

    raise notice 'PASS: the name of the business, and not one field more';
end $$;
rollback;

\echo ''
\echo '--- TEST 11: an anonymous caller cannot claim anything ---'
begin;
set local role authenticated;   -- authenticated role, but auth.uid() is null
do $$
begin
    begin
        perform claim_invitation('OPEN-7777');
        raise exception 'FAIL: a caller with no session claimed an invitation';
    exception
        when invalid_authorization_specification then null;
    end;
    raise notice 'PASS: no session, no claim';
end $$;
rollback;

\echo ''
\echo '--- TEST 12: a bearer code (no phone, no email) works for whoever holds it ---'
begin;
set local "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-000000000005';
set local role authenticated;
do $$
declare
    v_org  uuid;
    v_role text;
begin
    v_org := claim_invitation('OPEN-7777');
    if v_org <> 'dddddddd-0000-0000-0000-00000000000a' then
        raise exception 'FAIL: bearer claim returned %', v_org;
    end if;
    select role::text into v_role from memberships
    where user_id = 'cccccccc-0000-0000-0000-000000000005';
    if v_role <> 'employee' then
        raise exception 'FAIL: bearer code granted %, expected employee', v_role;
    end if;
    raise notice 'PASS: the hand-it-over-in-person case — the code is the whole secret, and it grants only what it says';
end $$;
rollback;

\echo ''
\echo '--- TEST 13: a spent code is spent, even for the right phone ---'
begin;
set local "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-000000000006';
set local role authenticated;
do $$
begin
    -- CHOR-2468 was claimed by the newcomer in TEST 1 and committed.
    begin
        perform claim_invitation('CHOR-2468');
        raise exception 'FAIL: a claimed code was reused by a second person';
    exception
        when no_data_found then null;
    end;
    raise notice 'PASS: one code, one membership, one person';
end $$;
rollback;

\echo ''
\echo '--- TEST 14: a code left to the default is well-formed, unambiguous and unique ---'
begin;
set local "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_code   text;
    v_codes  text[] := '{}';
    v_n      int;
begin
    -- This is how the app issues one: no code column at all.
    for i in 1..50 loop
        insert into pending_invitations
            (org_id, role, scope_kind, scope_id, created_by)
        values ('dddddddd-0000-0000-0000-00000000000a', 'employee', 'org',
                'dddddddd-0000-0000-0000-00000000000a',
                'cccccccc-0000-0000-0000-000000000001')
        returning code into v_code;

        if v_code !~ '^[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}$' then
            raise exception 'FAIL: generated code % is not XXXX-XXXX over the safe alphabet', v_code;
        end if;
        -- 0/O and 1/I are the pairs people mishear and mistype. Neither may
        -- ever appear, or a code read down a phone line becomes a coin toss.
        if v_code ~ '[01IO]' then
            raise exception 'FAIL: generated code % contains an ambiguous character', v_code;
        end if;

        v_codes := v_codes || v_code;
    end loop;

    select count(distinct c) into v_n from unnest(v_codes) c;
    if v_n <> 50 then
        raise exception 'FAIL: 50 generated codes contained only % distinct values', v_n;
    end if;

    raise notice 'PASS: 50 codes minted by the default, all well-formed and all distinct';
end $$;
rollback;

\echo ''
\echo '--- TEST 15: two invitations cannot share a code, however it is punctuated ---'
begin;
set local "request.jwt.claim.sub" = 'cccccccc-0000-0000-0000-000000000001';
set local role authenticated;
do $$
begin
    -- OPEN-7777 already exists. The same code without its dash is the same
    -- code, and claim_invitation() would otherwise have two rows to choose
    -- between for one spoken secret.
    begin
        insert into pending_invitations
            (org_id, role, scope_kind, scope_id, code, created_by)
        values ('dddddddd-0000-0000-0000-00000000000a', 'owner', 'org',
                'dddddddd-0000-0000-0000-00000000000a', 'open7777',
                'cccccccc-0000-0000-0000-000000000001');
        raise exception 'FAIL: a duplicate code was accepted in different punctuation';
    exception
        when unique_violation then null;
    end;
    raise notice 'PASS: uniqueness is on what the code means, not how it is written';
end $$;
rollback;

\echo ''
\echo '=== INVITATION SUITE COMPLETE — all assertions held ==='
