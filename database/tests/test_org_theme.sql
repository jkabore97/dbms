-- ============================================================
-- test_org_theme.sql — a business picks its own colours.
--
-- Runs as `authenticated` throughout, because the whole question here is who
-- is allowed to repaint a business that other people are working in.
--
-- What this suite is about:
--
--   1. An ordinary employee cannot change what every colleague sees. The
--      colour is cosmetic; the permission is not, and it is the same bar as
--      renaming the business.
--   2. An owner can, and it survives in my_orgs() — which is what the app
--      actually reads and caches, so a theme that saves but never arrives is
--      the same as one that never saved.
--   3. One business's colour is not another's. The setter takes an org id,
--      and an admin of one business must not be able to aim it at another.
--   4. Clearing it puts the business back on its profile's colour rather
--      than leaving it blank-but-set.
--   5. The column refuses junk without freezing the palette list: a name the
--      server has never heard of is accepted (the app resolves names, and a
--      newer app must not be refused by an older database), but a sentence,
--      an injection attempt or an empty-ish string is not.
--
-- Phone block 87. The others: 70 rls, 71 invitations, 72 reports,
-- 73 accounting, 74 audit, 75/76 farm, 77 platform admin, 78 retail,
-- 79 employees, 80 capture, 81 org lifecycle, 82 delivery, 83 onboarding,
-- 84 farm_general, 85 invoicing, 86 console.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''87878787-0000-0000-0000-000000000001'''
\set clerk    '''87878787-0000-0000-0000-000000000002'''
\set stranger '''87878787-0000-0000-0000-000000000003'''

\set shop     '''87000000-0000-0000-0000-000000000001'''
\set other    '''87000000-0000-0000-0000-000000000002'''

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22687000001', '{"full_name": "Patronne"}'),
    (:clerk,    '+22687000002', '{"full_name": "Vendeur"}'),
    (:stranger, '+22687000003', '{"full_name": "Voisin"}');

insert into orgs (id, name, slug, profile, default_currency) values
    (:shop,  'Boutique Espérance', 'boutique-87', 'retail', 'XOF'),
    (:other, 'Ferme Ignace',       'ferme-87',    'farm',   'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:shop,  :owner,    'owner',    'org', :shop),
    (:shop,  :clerk,    'employee', 'org', :shop),
    -- The stranger owns a different business entirely. That is the point of
    -- test 3: being an owner somewhere is not being an owner here.
    (:other, :stranger, 'owner',    'org', :other);

\echo ''
\echo '--- TEST 1: an employee cannot repaint the business ---'
begin;
set local "request.jwt.claim.sub" = '87878787-0000-0000-0000-000000000002';
set local role authenticated;
do $$
begin
    begin
        perform set_org_theme('87000000-0000-0000-0000-000000000001'::uuid, 'prune');
        raise exception 'FAIL: an employee changed what every colleague sees';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
commit;

-- And it really did not happen. A function that raises after writing would
-- pass the check above and still have repainted the shop.
do $$
declare v_theme text;
begin
    select theme into v_theme from orgs
     where id = '87000000-0000-0000-0000-000000000001';
    if v_theme is not null then
        raise exception 'FAIL: refused but wrote anyway (theme = %)', v_theme;
    end if;
    raise notice 'PASS: nothing was written';
end $$;

\echo ''
\echo '--- TEST 2: the owner can, and the app is told ---'
begin;
set local "request.jwt.claim.sub" = '87878787-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_theme text;
    v_rows  int;
begin
    perform set_org_theme('87000000-0000-0000-0000-000000000001'::uuid, 'ocean');

    -- my_orgs() is what the app reads and caches. A theme that saves to the
    -- table but never reaches this function is invisible to every user.
    select count(*), max(o.theme) into v_rows, v_theme
      from my_orgs() o
     where o.org_id = '87000000-0000-0000-0000-000000000001';

    if v_rows <> 1 then
        raise exception 'FAIL: my_orgs() returned % rows for the shop', v_rows;
    end if;
    if v_theme is distinct from 'ocean' then
        raise exception 'FAIL: my_orgs() reported theme %, expected ocean',
            coalesce(v_theme, 'null');
    end if;

    raise notice 'PASS: owner set it and my_orgs() carries it';
end $$;
commit;

\echo ''
\echo '--- TEST 3: an owner elsewhere is nobody here ---'
begin;
set local "request.jwt.claim.sub" = '87878787-0000-0000-0000-000000000003';
set local role authenticated;
do $$
begin
    begin
        perform set_org_theme('87000000-0000-0000-0000-000000000001'::uuid, 'savane');
        raise exception 'FAIL: the owner of one business repainted another';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
commit;

do $$
declare v_theme text;
begin
    select theme into v_theme from orgs
     where id = '87000000-0000-0000-0000-000000000001';
    if v_theme is distinct from 'ocean' then
        raise exception 'FAIL: the shop is now %, expected ocean',
            coalesce(v_theme, 'null');
    end if;
    raise notice 'PASS: the shop is still its own colour';
end $$;

\echo ''
\echo '--- TEST 4: clearing it goes back to the profile colour ---'
begin;
set local "request.jwt.claim.sub" = '87878787-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_theme text;
begin
    -- Null and empty-string must mean the same thing. The app sends one or
    -- the other depending on how the picker was cleared, and "set to the
    -- empty string" is not a colour anybody can resolve.
    perform set_org_theme('87000000-0000-0000-0000-000000000001'::uuid, '   ');

    select max(o.theme) into v_theme from my_orgs() o
     where o.org_id = '87000000-0000-0000-0000-000000000001';

    if v_theme is not null then
        raise exception 'FAIL: clearing left theme = %', v_theme;
    end if;
    raise notice 'PASS: cleared back to the profile colour';
end $$;
commit;

\echo ''
\echo '--- TEST 5: shape is checked, the palette list is not frozen ---'
begin;
set local "request.jwt.claim.sub" = '87878787-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_theme text;
begin
    -- A name this database has never heard of is fine on purpose: the app
    -- resolves names to colours, so a newer build offering a new palette must
    -- not be refused by an older database. This is the forward-compatibility
    -- the migration deliberately chose over a check constraint listing today's
    -- palettes.
    perform set_org_theme('87000000-0000-0000-0000-000000000001'::uuid,
                          'couleur-inventee-demain');
    select theme into v_theme from orgs
     where id = '87000000-0000-0000-0000-000000000001';
    if v_theme is distinct from 'couleur-inventee-demain' then
        raise exception 'FAIL: a future palette name was refused';
    end if;
    raise notice 'PASS: an unknown palette name is accepted';

    -- Junk is not. Each of these is a different way of being wrong: a
    -- sentence, an injection attempt, something far too long, and a name
    -- that does not start with a letter.
    begin
        perform set_org_theme('87000000-0000-0000-0000-000000000001'::uuid,
                              'je veux du bleu clair');
        raise exception 'FAIL: a sentence was accepted as a colour';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: a sentence refused — %', sqlerrm;
    end;

    begin
        perform set_org_theme('87000000-0000-0000-0000-000000000001'::uuid,
                              'ocean''; drop table orgs; --');
        raise exception 'FAIL: an injection attempt was accepted';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: injection refused — %', sqlerrm;
    end;

    begin
        perform set_org_theme('87000000-0000-0000-0000-000000000001'::uuid,
                              repeat('a', 64));
        raise exception 'FAIL: a 64-character name was accepted';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: over-long refused — %', sqlerrm;
    end;

    begin
        perform set_org_theme('87000000-0000-0000-0000-000000000001'::uuid,
                              '9ocean');
        raise exception 'FAIL: a name starting with a digit was accepted';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: bad shape refused — %', sqlerrm;
    end;
end $$;
commit;

-- The table itself refuses junk too, not only the function. Belt and braces:
-- the constraint is what protects the column from a future writer that is not
-- set_org_theme().
\echo ''
\echo '--- TEST 6: the constraint holds even without the function ---'
do $$
begin
    begin
        update orgs set theme = 'PAS UN SLUG'
         where id = '87000000-0000-0000-0000-000000000001';
        raise exception 'FAIL: a direct write put junk in the column';
    exception when check_violation then
        raise notice 'PASS: the constraint refused a direct write';
    end;
end $$;

\echo ''
\echo '--- TEST 7: a business that never chose one is unaffected ---'
begin;
set local "request.jwt.claim.sub" = '87878787-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_theme   text;
    v_profile text;
begin
    select max(o.theme), max(o.profile) into v_theme, v_profile
      from my_orgs() o
     where o.org_id = '87000000-0000-0000-0000-000000000002';

    if v_theme is not null then
        raise exception 'FAIL: an untouched business has theme %', v_theme;
    end if;
    if v_profile is distinct from 'farm' then
        raise exception 'FAIL: the farm lost its profile (%)', v_profile;
    end if;
    raise notice 'PASS: untouched business still answers by its profile';
end $$;
commit;

\echo ''
\echo '=== test_org_theme.sql: all assertions passed ==='
