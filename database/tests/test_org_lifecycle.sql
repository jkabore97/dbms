-- ============================================================
-- test_org_lifecycle.sql — proof that a business is hard to destroy and
-- impossible to destroy quietly.
--
-- Runs as `authenticated` throughout, never as postgres. Every assertion here
-- is either a platform-admin check inside a SECURITY DEFINER function or an
-- RLS policy, and a superuser sails straight through both.
--
-- This is the only place in the schema where data is destroyed on purpose, so
-- this suite is mostly about the ways that could go wrong:
--
--   1. An org's own owner deleting the business out from under the platform.
--   2. Deleting one by accident — a mis-click, a wrong row, a uuid nobody
--      read in a confirmation dialog.
--   3. Deleting one that holds books, without anybody saying so out loud.
--   4. The deletion erasing its own record, because audit_log.org_id
--      cascades with everything else.
--   5. Archiving being mistaken for deleting — an archived business must keep
--      every entry and be restorable.
--
-- Phone block 81, and slug suffix -81 for the same reason: every suite
-- commits into one database in CI, so a name or an address that looks
-- unremarkable here collides with test_retail's shop, which is already called
-- boutique-esperance.
--
-- Phone block 81. The others: 70 rls, 71 invitations, 72 reports,
-- 73 accounting, 74 audit, 75/76 farm, 77 platform admin, 78 retail,
-- 79 employees, 80 capture.
-- ============================================================
\set ON_ERROR_STOP on

\set admin '''81818181-0000-0000-0000-000000000001'''
\set owner '''81818181-0000-0000-0000-000000000002'''
\set clerk '''81818181-0000-0000-0000-000000000003'''

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
    (:admin, '+22681000001', '{"full_name": "Kaboré (plateforme)"}'),
    (:owner, '+22681000002', '{"full_name": "Propriétaire"}'),
    (:clerk, '+22681000003', '{"full_name": "Employé"}');

update profiles set is_platform_admin = true where id = :admin;

-- Two businesses: one to keep and one to destroy.
insert into orgs (id, name, slug, profile, default_currency) values
    ('81000000-0000-0000-0000-000000000001', 'Boutique à garder',  'boutique-a-garder',  'retail', 'XOF'),
    ('81000000-0000-0000-0000-000000000002', 'Essai à supprimer',  'essai-a-supprimer',  'generic', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    ('81000000-0000-0000-0000-000000000001', :owner, 'owner',    'org', '81000000-0000-0000-0000-000000000001'),
    ('81000000-0000-0000-0000-000000000001', :clerk, 'employee', 'org', '81000000-0000-0000-0000-000000000001'),
    ('81000000-0000-0000-0000-000000000002', :owner, 'owner',    'org', '81000000-0000-0000-0000-000000000002');

select seed_retail_accounts('81000000-0000-0000-0000-000000000001');

\echo ''
\echo '--- TEST 1: an owner may rename their own business ---'
begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_name    text;
    v_slug    text;
    v_profile text;
begin
    perform update_org('81000000-0000-0000-0000-000000000001',
                       'Boutique Espérance 81', 'boutique-esperance-81');

    select name, slug, profile into v_name, v_slug, v_profile
    from orgs where id = '81000000-0000-0000-0000-000000000001';

    if v_name <> 'Boutique Espérance 81' or v_slug <> 'boutique-esperance-81' then
        raise exception 'FAIL: renamed to % / %', v_name, v_slug;
    end if;
    -- Nulls left the other fields alone rather than blanking them.
    if v_profile <> 'retail' then
        raise exception 'FAIL: renaming changed the profile to %', v_profile;
    end if;

    raise notice 'PASS: an owner renamed their shop and changed nothing else';
end $$;
commit;

\echo ''
\echo '--- TEST 2: an address that would not survive as a hostname is refused ---'
begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000002';
set local role authenticated;
do $$
begin
    begin
        perform update_org('81000000-0000-0000-0000-000000000001', null, 'Pas Valide!');
        raise exception 'FAIL: an invalid address was accepted';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;

    -- And one that belongs to somebody else.
    begin
        perform update_org('81000000-0000-0000-0000-000000000001', null, 'essai-a-supprimer');
        raise exception 'FAIL: two businesses now share one address';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;

    -- And a profile that would land everyone on the pending screen with no
    -- way back.
    begin
        perform update_org('81000000-0000-0000-0000-000000000001', null, null, 'boulangerie');
        raise exception 'FAIL: an unknown profile was accepted';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 3: an employee cannot rename the business ---'
begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000003';
set local role authenticated;
do $$
begin
    begin
        perform update_org('81000000-0000-0000-0000-000000000001', 'Chez moi maintenant');
        raise exception 'FAIL: an employee renamed the business';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 4: only a platform admin archives, and archiving keeps everything ---'
begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000002';
set local role authenticated;
do $$
begin
    -- The owner of the business is not enough: archiving takes it off every
    -- member's screen at once, including people still using it.
    begin
        perform archive_org('81000000-0000-0000-0000-000000000002');
        raise exception 'FAIL: an org owner archived a business';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
rollback;

begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_when timestamptz;
    v_rows int;
begin
    perform archive_org('81000000-0000-0000-0000-000000000002');

    select archived_at into v_when from orgs
    where id = '81000000-0000-0000-0000-000000000002';
    if v_when is null then
        raise exception 'FAIL: archiving recorded nothing';
    end if;

    -- Still there, with its memberships intact. Archiving is not deleting.
    select count(*) into v_rows from memberships
    where org_id = '81000000-0000-0000-0000-000000000002';
    if v_rows <> 1 then
        raise exception 'FAIL: archiving removed % memberships', 1 - v_rows;
    end if;

    raise notice 'PASS: archived, and every row still there';
end $$;
commit;

\echo ''
\echo '--- TEST 5: an archived business leaves its members'' list ---'
begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_ids uuid[];
begin
    select array_agg(org_id) into v_ids from my_orgs();

    if '81000000-0000-0000-0000-000000000002' = any(v_ids) then
        raise exception 'FAIL: an archived business is still on the owner''s home screen';
    end if;
    if not ('81000000-0000-0000-0000-000000000001' = any(v_ids)) then
        raise exception 'FAIL: archiving one business hid another';
    end if;

    raise notice 'PASS: the archived one is gone, the live one is not';
end $$;
rollback;

begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_ids uuid[];
    v_all int;
begin
    -- A platform admin still sees it, because somebody has to be able to
    -- find an archived business in order to restore it.
    select array_agg(org_id) into v_ids from my_orgs();
    if not ('81000000-0000-0000-0000-000000000002' = any(v_ids)) then
        raise exception 'FAIL: nobody can see the archived business any more';
    end if;

    select count(*) into v_all from all_orgs();
    if v_all < 2 then
        raise exception 'FAIL: all_orgs() returned % businesses', v_all;
    end if;

    raise notice 'PASS: a platform admin can still find it';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: an ordinary user cannot list the platform ---'
begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_count int;
begin
    begin
        select count(*) into v_count from all_orgs();
        raise exception 'FAIL: an owner listed every business on the platform';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 7: deleting is fenced four ways ---'
begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000002';
set local role authenticated;
do $$
begin
    -- 1. Not the org's own owner, ever.
    begin
        perform delete_org('81000000-0000-0000-0000-000000000002', 'Essai à supprimer');
        raise exception 'FAIL: an org owner deleted a business';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
rollback;

begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000001';
set local role authenticated;
do $$
begin
    -- 2. Not before it has been archived. The live one has not been.
    begin
        perform delete_org('81000000-0000-0000-0000-000000000001', 'Boutique Espérance 81');
        raise exception 'FAIL: a live business was deleted without being archived';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;

    -- 3. Not without typing the name back. A uuid in a dialog is not read.
    begin
        perform delete_org('81000000-0000-0000-0000-000000000002', 'essai');
        raise exception 'FAIL: deleted without the name being confirmed';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 8: a business with books does not go quietly ---'
begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_entry uuid;
begin
    -- Give the archived business something in its books, then try to delete
    -- it the ordinary way.
    insert into memberships (org_id, user_id, role, scope_kind, scope_id)
    values ('81000000-0000-0000-0000-000000000002',
            '81818181-0000-0000-0000-000000000001', 'owner', 'org',
            '81000000-0000-0000-0000-000000000002')
    on conflict do nothing;

    v_entry := record_entry('81000000-0000-0000-0000-000000000002', 5000, 'in',
                            'Vente d''essai');

    begin
        perform delete_org('81000000-0000-0000-0000-000000000002',
                           'Essai à supprimer');
        raise exception 'FAIL: a business with books was deleted without a word';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 9: deleting works, and leaves a record that outlives it ---'
begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_left  int;
    v_stone deleted_orgs%rowtype;
begin
    -- Archived, name typed exactly, no books: the ordinary case.
    perform delete_org('81000000-0000-0000-0000-000000000002',
                       'Essai à supprimer');

    select count(*) into v_left from orgs
    where id = '81000000-0000-0000-0000-000000000002';
    if v_left <> 0 then
        raise exception 'FAIL: the business is still there';
    end if;

    -- Its memberships went with it.
    select count(*) into v_left from memberships
    where org_id = '81000000-0000-0000-0000-000000000002';
    if v_left <> 0 then
        raise exception 'FAIL: % memberships outlived their business', v_left;
    end if;

    -- And the record of the deletion did not, which is the whole reason
    -- deleted_orgs is not org-scoped: audit_log.org_id cascades.
    select * into v_stone from deleted_orgs
    where id = '81000000-0000-0000-0000-000000000002';
    if not found then
        raise exception 'FAIL: a business was deleted with no record of it';
    end if;
    if v_stone.name <> 'Essai à supprimer'
       or v_stone.deleted_by <> '81818181-0000-0000-0000-000000000001' then
        raise exception 'FAIL: the tombstone says % deleted by %',
            v_stone.name, v_stone.deleted_by;
    end if;

    raise notice 'PASS: deleted, and the tombstone survived it';
end $$;
rollback;

\echo ''
\echo '--- TEST 10: nobody can erase the record of a deletion ---'
begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_before int;
    v_after  int;
begin
    perform delete_org('81000000-0000-0000-0000-000000000002',
                       'Essai à supprimer');

    select count(*) into v_before from deleted_orgs;

    -- deleted_orgs has a select policy and nothing else. A missing policy
    -- denies rather than errors, so both statements succeed and change
    -- nothing — the same shape as the audit log in 008.
    delete from deleted_orgs;
    update deleted_orgs set name = 'jamais existé';

    select count(*) into v_after from deleted_orgs;
    if v_after <> v_before then
        raise exception 'FAIL: % tombstones were erased', v_before - v_after;
    end if;
    if exists (select 1 from deleted_orgs where name = 'jamais existé') then
        raise exception 'FAIL: a tombstone was rewritten';
    end if;

    raise notice 'PASS: % tombstone(s), unerasable even by the admin who wrote them',
        v_after;
end $$;
rollback;

\echo ''
\echo '--- TEST 11: an ordinary user cannot read the tombstones ---'
begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count from deleted_orgs;
    if v_count <> 0 then
        raise exception 'FAIL: an owner reads % platform tombstones', v_count;
    end if;
    raise notice 'PASS: the tombstones are the platform''s business, not a tenant''s';
end $$;
rollback;

\echo ''
\echo '--- TEST 12: forcing it destroys the books, and counts them first ---'
begin;
set local "request.jwt.claim.sub" = '81818181-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_entries  int;
    v_left     int;
    v_stone    deleted_orgs%rowtype;
    v_product  uuid;
    v_sale     uuid;
    v_employee uuid;
begin
    insert into memberships (org_id, user_id, role, scope_kind, scope_id)
    values ('81000000-0000-0000-0000-000000000002',
            '81818181-0000-0000-0000-000000000001', 'owner', 'org',
            '81000000-0000-0000-0000-000000000002')
    on conflict do nothing;

    -- One of everything, on purpose. Most of the danger in delete_org() is
    -- not the deleting, it is a table nobody remembered: the references
    -- *between* org-scoped tables are NO ACTION, so a forgotten one aborts
    -- the whole delete with a foreign key error. A business holding a sale, a
    -- return, an employee who has been paid, a flock, an invoice and a
    -- photograph is what turns that into a failing suite instead of a
    -- platform admin who cannot delete anything.
    perform seed_retail_accounts('81000000-0000-0000-0000-000000000002');

    perform record_entry('81000000-0000-0000-0000-000000000002', 5000, 'in',
                         'Vente d''essai');
    perform record_entry('81000000-0000-0000-0000-000000000002', 1200, 'out',
                         'Transport');

    -- Retail: a product, a sale, and a return that points back at that sale.
    v_product := ensure_product('81000000-0000-0000-0000-000000000002',
                                'Savon', 500, 300,
                                '81818181-0000-0000-0000-000000000001');
    v_sale := record_sale('81000000-0000-0000-0000-000000000002',
                          jsonb_build_array(
                              jsonb_build_object('product_id', v_product,
                                                 'quantity', 2)));
    perform record_return(v_sale);

    -- Payroll: somebody who has worked and been paid.
    v_employee := add_employee('81000000-0000-0000-0000-000000000002',
                               'Aide du samedi', 'casual', 500);
    perform record_shift('81000000-0000-0000-0000-000000000002', v_employee, 4);
    perform pay_employee('81000000-0000-0000-0000-000000000002', v_employee);

    -- A photograph, which points at both a product and the bucket.
    perform record_document(
        '81000000-0000-0000-0000-000000000002',
        'org/81000000-0000-0000-0000-000000000002/2026/livraison.jpg',
        'receipt', null, 'image/jpeg', 1234, now(), null, null, null,
        v_product);

    select count(*) into v_entries from journal_entries
    where org_id = '81000000-0000-0000-0000-000000000002';
    if v_entries < 2 then
        raise exception 'FAIL: set up % entries, expected at least 2', v_entries;
    end if;

    -- The second, deliberate act. This is the one call in the schema that
    -- destroys a business's history, and it happens only when somebody has
    -- already been told what it will cost.
    perform delete_org('81000000-0000-0000-0000-000000000002',
                       'Essai à supprimer', true);

    select count(*) into v_left from journal_entries
    where org_id = '81000000-0000-0000-0000-000000000002';
    if v_left <> 0 then
        raise exception 'FAIL: % entries survived a forced delete', v_left;
    end if;

    -- The lines under those entries went too, rather than being orphaned.
    select count(*) into v_left from journal_lines jl
    where not exists (select 1 from journal_entries je where je.id = jl.journal_entry_id);
    if v_left <> 0 then
        raise exception 'FAIL: % journal lines are orphaned', v_left;
    end if;

    -- And the tombstone says how much was destroyed, because by the time
    -- anybody asks there is nothing left to count.
    select * into v_stone from deleted_orgs
    where id = '81000000-0000-0000-0000-000000000002';
    if v_stone.entry_count <> v_entries then
        raise exception 'FAIL: the tombstone records % entries, expected %',
            v_stone.entry_count, v_entries;
    end if;

    -- And nothing anywhere still points at the business that is gone.
    select count(*) into v_left from products where org_id = '81000000-0000-0000-0000-000000000002';
    if v_left <> 0 then raise exception 'FAIL: % products survived', v_left; end if;
    select count(*) into v_left from employees where org_id = '81000000-0000-0000-0000-000000000002';
    if v_left <> 0 then raise exception 'FAIL: % employees survived', v_left; end if;
    select count(*) into v_left from documents where org_id = '81000000-0000-0000-0000-000000000002';
    if v_left <> 0 then raise exception 'FAIL: % documents survived', v_left; end if;

    raise notice 'PASS: forced — % entries and everything under them destroyed',
        v_stone.entry_count;
end $$;
rollback;

\echo ''
\echo '--- TEST 13: the live business is untouched by all of the above ---'
do $$
declare
    v_name text;
begin
    select name into v_name from orgs
    where id = '81000000-0000-0000-0000-000000000001';
    if v_name is null then
        raise exception 'FAIL: the business that was never deleted is gone';
    end if;
    raise notice 'PASS: % is still here', v_name;
end $$;

\echo ''
\echo 'test_org_lifecycle.sql: all assertions held.'
