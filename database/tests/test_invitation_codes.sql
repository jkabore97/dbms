-- ============================================================
-- test_invitation_codes.sql — the function that mints a code.
--
-- This suite exists because of a bug that reached a real user: pressing
-- "Générer le code" failed with `function gen_random_bytes(integer) does not
-- exist`, and nobody could invite an employee.
--
-- The reason it got that far is the whole point of this file. There is a
-- large invitation suite already — test_invitations.sql, fifteen assertions
-- about who may claim what — and **every one of its rows supplies an explicit
-- `code`**. So `new_invitation_code()`, the one function in the schema that
-- depended on pgcrypto, was never once called by a test. It was the only
-- unexercised line between an admin and a new employee, and that is exactly
-- where the failure was.
--
-- So this suite calls it, repeatedly, and asserts what a person actually
-- depends on:
--
--   1. It runs at all, with no extension installed beyond plpgsql. This is
--      the regression: the assertion that would have caught the original.
--   2. The column default works, which is the path the app really takes —
--      the app inserts a row and lets the database mint the code.
--   3. The shape is what gets read down a bad phone line: XXXX-XXXX, and
--      never a character from the ambiguous set 0/O/1/I.
--   4. It does not repeat. A collision hands one person another person's
--      invitation, which is a stranger inside somebody's books.
--   5. It is not predictable in the cheap way — the codes are spread across
--      the alphabet rather than clustered, which is what a broken or biased
--      random source looks like from the outside.
--
-- Phone block 88. The others: 70 rls, 71 invitations, 72 reports,
-- 73 accounting, 74 audit, 75/76 farm, 77 platform admin, 78 retail,
-- 79 employees, 80 capture, 81 org lifecycle, 82 delivery, 83 onboarding,
-- 84 farm_general, 85 invoicing, 86 console, 87 org theme.
-- ============================================================
\set ON_ERROR_STOP on

\set boss '''88888888-0000-0000-0000-000000000001'''
\set shop '''88000000-0000-0000-0000-000000000001'''

insert into auth.users (id, phone, raw_user_meta_data) values
    (:boss, '+22688000001', '{"full_name": "Patronne"}');

insert into orgs (id, name, slug, profile, default_currency) values
    (:shop, 'Boutique 88', 'boutique-88', 'retail', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:shop, :boss, 'owner', 'org', :shop);

\echo ''
\echo '--- TEST 1: the code minter runs without pgcrypto ---'
-- The regression. Written so it fails loudly with the original symptom
-- rather than with a bare "function does not exist" nobody can place.
do $$
declare v_code text;
begin
    begin
        v_code := new_invitation_code();
    exception when undefined_function then
        raise exception
            'FAIL: new_invitation_code() needs an extension that is not '
            'installed (%). This is the bug that stopped an owner inviting '
            'an employee in production.', sqlerrm;
    end;

    if v_code is null or v_code = '' then
        raise exception 'FAIL: the code minter returned nothing';
    end if;
    raise notice 'PASS: minted % with no extension beyond plpgsql', v_code;
end $$;

\echo ''
\echo '--- TEST 2: the column default is what the app actually uses ---'
-- The app inserts a row without a code and lets the database fill it in.
-- Test 1 passing while this failed would mean a working function nobody
-- reaches.
do $$
declare v_code text;
begin
    insert into pending_invitations (org_id, role, scope_kind, scope_id, created_by)
    values ('88000000-0000-0000-0000-000000000001', 'employee', 'org',
            '88000000-0000-0000-0000-000000000001',
            '88888888-0000-0000-0000-000000000001')
    returning code into v_code;

    if v_code is null then
        raise exception 'FAIL: the default left the code null';
    end if;
    raise notice 'PASS: an insert with no code got %', v_code;
end $$;

\echo ''
\echo '--- TEST 3: the shape a person has to read down a phone line ---'
do $$
declare
    v_code text;
    i      int;
begin
    for i in 1..50 loop
        v_code := new_invitation_code();

        if v_code !~ '^[23456789A-HJ-NP-Z]{4}-[23456789A-HJ-NP-Z]{4}$' then
            raise exception 'FAIL: % is not XXXX-XXXX in the safe alphabet',
                v_code;
        end if;

        -- The ambiguous characters, spelled out rather than trusted to the
        -- regex above: these are the ones that get misheard and mistyped,
        -- and the alphabet exists to exclude them.
        if v_code ~ '[01OI]' then
            raise exception 'FAIL: % contains an ambiguous character', v_code;
        end if;
    end loop;
    raise notice 'PASS: 50 codes, all XXXX-XXXX, none ambiguous';
end $$;

\echo ''
\echo '--- TEST 4: codes do not repeat ---'
do $$
declare
    v_codes text[] := '{}';
    i       int;
begin
    for i in 1..200 loop
        v_codes := v_codes || new_invitation_code();
    end loop;

    -- A duplicate here would mean handing one person another person's
    -- invitation. At 32^8 this should never fire; if it does, the random
    -- source is broken rather than unlucky.
    if (select count(distinct x) from unnest(v_codes) x) <> 200 then
        raise exception 'FAIL: % distinct codes out of 200',
            (select count(distinct x) from unnest(v_codes) x);
    end if;
    raise notice 'PASS: 200 codes, all distinct';
end $$;

\echo ''
\echo '--- TEST 5: the randomness is spread, not clustered ---'
-- What a broken random source looks like from outside: codes that are all
-- alike, or that only ever use a corner of the alphabet. Deliberately a
-- loose bound -- this is here to catch a source that has stopped being
-- random, not to grade the distribution.
do $$
declare
    v_all     text := '';
    i         int;
    v_symbols int;
begin
    for i in 1..100 loop
        v_all := v_all || replace(new_invitation_code(), '-', '');
    end loop;

    -- 800 characters drawn from 32 symbols. Seeing fewer than 25 of them
    -- means something is badly wrong; a healthy source hits all 32 almost
    -- every time.
    select count(distinct substr(v_all, g, 1)) into v_symbols
      from generate_series(1, length(v_all)) g;

    if v_symbols < 25 then
        raise exception
            'FAIL: 800 characters used only % of 32 symbols -- the random '
            'source looks broken or biased', v_symbols;
    end if;
    raise notice 'PASS: % of 32 symbols seen across 800 characters', v_symbols;
end $$;

\echo ''
\echo '=== test_invitation_codes.sql: all assertions passed ==='
