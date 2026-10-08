-- ============================================================
-- test_security.sql — the holes 032 closed, each proven shut.
--
-- Phone block 96. Every refusal here is checked as the `authenticated` role
-- with a real JWT subject, never as postgres — a superuser bypasses both RLS
-- and column privileges, so this suite would pass against none of the fixes
-- if it ran as one.
--
-- The suite restores the production grant state for profiles and notifications
-- at the top, because an earlier suite in the same database may have run the
-- blanket `grant update on all tables`, which is exactly the re-grant Layer 2
-- exists to survive — and which would otherwise mask Layer 1 here.
-- ============================================================
\set ON_ERROR_STOP on

\set padmin   '''96959596-0000-0000-0000-000000000001'''
\set owner    '''96959596-0000-0000-0000-000000000002'''
\set clerk    '''96959596-0000-0000-0000-000000000003'''
\set outsider '''96959596-0000-0000-0000-000000000004'''
\set shop     '''96000000-0000-0000-0000-000000000001'''
\set prod     '''96000000-0000-0000-0000-0000000000a1'''
\set emp      '''96000000-0000-0000-0000-0000000000b1'''
\set sale     '''96000000-0000-0000-0000-0000000000c1'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- Restore the production grant state that 032 establishes, undoing any blanket
-- grant an earlier suite left behind.
revoke update on profiles from authenticated;
grant update (full_name, first_name, middle_name, last_name,
              date_of_birth, title, phone, preferred_locale)
    on profiles to authenticated;
revoke update on notifications from authenticated;
grant update (read_at) on notifications to authenticated;

-- Fixtures. Inserting auth.users fires handle_new_auth_user, which creates the
-- profiles rows; padmin is then promoted the only way production ever promotes
-- anyone — as the trusted no-JWT caller (here, postgres).
insert into auth.users (id, phone, raw_user_meta_data) values
    (:padmin,   '+22696000001', '{"full_name": "Plateforme"}'),
    (:owner,    '+22696000002', '{"full_name": "Patron"}'),
    (:clerk,    '+22696000003', '{"full_name": "Vendeur"}'),
    (:outsider, '+22696000004', '{"full_name": "Etranger"}');

update profiles set is_platform_admin = true where id = :padmin;

insert into orgs (id, name, slug, profile, default_currency) values
    (:shop, 'Boutique 96', 'boutique-96', 'retail', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:shop, :owner, 'owner',    'org', :shop),
    (:shop, :clerk, 'employee', 'org', :shop);

insert into products (id, org_id, name, sale_price, cost_price)
    values (:prod, :shop, 'Savon', 300, 200);

insert into employees (id, org_id, full_name, kind, hourly_rate)
    values (:emp, :shop, 'Journalier', 'casual', 500);

insert into sales (id, org_id, kind, method, total, recorded_by)
    values (:sale, :shop, 'sale', 'cash', 1000, :owner);


\echo ''
\echo '--- TEST 1: Layer 1 — a member cannot set is_platform_admin on themselves ---'
begin;
set local "request.jwt.claim.sub" = '96959596-0000-0000-0000-000000000003';
set local role authenticated;
do $$
begin
    update profiles set is_platform_admin = true
    where id = '96959596-0000-0000-0000-000000000003';
    raise exception 'FAIL: the column update was allowed';
exception
    when insufficient_privilege then
        -- Postgres words this "permission denied for table" when the sole SET
        -- column is ungranted, "for column" when the SET list mixes granted
        -- and ungranted columns. Either is the column-privilege layer, and
        -- neither is the trigger (whose message names the administrator).
        if sqlerrm like '%permission denied%' then
            raise notice 'PASS: refused at the column privilege — %', sqlerrm;
        else
            raise exception 'FAIL: refused, but not by the column grant: %', sqlerrm;
        end if;
end $$;
rollback;


\echo ''
\echo '--- TEST 2: Layer 2 — even with table UPDATE re-granted, the flag is trigger-locked ---'
-- Simulate the Supabase "GRANT ALL" that would undo Layer 1.
grant update on profiles to authenticated;
begin;
set local "request.jwt.claim.sub" = '96959596-0000-0000-0000-000000000003';
set local role authenticated;
do $$
begin
    update profiles set is_platform_admin = true
    where id = '96959596-0000-0000-0000-000000000003';
    raise exception 'FAIL: the trigger let a non-admin self-promote';
exception
    when insufficient_privilege then
        if sqlerrm like '%platform administrator%' then
            raise notice 'PASS: refused by the guard trigger — %', sqlerrm;
        else
            raise exception 'FAIL: refused, but not by the trigger: %', sqlerrm;
        end if;
end $$;
rollback;


\echo ''
\echo '--- TEST 3: the trigger''s admin branch — an admin may change the flag ---'
-- Still inside the re-granted window, so column privilege is not what is under
-- test; the trigger''s "caller is already an admin" path is. Note what the
-- previous test taught us: RLS (id = auth.uid()) means even a platform admin
-- cannot touch ANOTHER user''s row through the API — promotion of others is a
-- server-side act. So the reachable admin case is an admin changing their own
-- flag, here demoting themselves, which the trigger must allow.
begin;
set local "request.jwt.claim.sub" = '96959596-0000-0000-0000-000000000001';
set local role authenticated;
do $$
begin
    update profiles set is_platform_admin = false
    where id = '96959596-0000-0000-0000-000000000001';
    if exists (select 1 from profiles
               where id = '96959596-0000-0000-0000-000000000001'
                 and is_platform_admin) then
        raise exception 'FAIL: an admin''s own change to the flag did not take';
    end if;
    raise notice 'PASS: an existing admin may change the flag';
end $$;
rollback;
-- Back to the production grant state.
revoke update on profiles from authenticated;
grant update (full_name, first_name, middle_name, last_name,
              date_of_birth, title, phone, preferred_locale)
    on profiles to authenticated;


\echo ''
\echo '--- TEST 4: a member can still edit their own name ---'
begin;
set local "request.jwt.claim.sub" = '96959596-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_name text;
begin
    update profiles set full_name = 'Vendeur Modifié'
    where id = '96959596-0000-0000-0000-000000000003';
    select full_name into v_name from profiles
    where id = '96959596-0000-0000-0000-000000000003';
    if v_name <> 'Vendeur Modifié' then
        raise exception 'FAIL: the ordinary name edit did not take';
    end if;
    raise notice 'PASS: the personal columns are still writable';
end $$;
rollback;


\echo ''
\echo '--- TEST 5: receive_products refuses a non-member, cost or no cost ---'
begin;
set local "request.jwt.claim.sub" = '96959596-0000-0000-0000-000000000004';
set local role authenticated;
do $$
begin
    -- The zero-cost path: the one that used to skip every check.
    perform receive_products('96000000-0000-0000-0000-000000000001'::uuid,
        '96000000-0000-0000-0000-0000000000a1'::uuid, 10, p_unit_cost => 0);
    raise exception 'FAIL: an outsider added stock to a business';
exception
    when others then
        if sqlerrm like '%cannot receive stock%' then
            raise notice 'PASS: refused — %', sqlerrm;
        else raise; end if;
end $$;
rollback;


\echo ''
\echo '--- TEST 6: pay_employee refuses a non-admin member ---'
begin;
set local "request.jwt.claim.sub" = '96959596-0000-0000-0000-000000000003';
set local role authenticated;
do $$
begin
    perform pay_employee('96000000-0000-0000-0000-000000000001'::uuid,
        '96000000-0000-0000-0000-0000000000b1'::uuid, 5000);
    raise exception 'FAIL: a clerk paid an employee';
exception
    when others then
        if sqlerrm like '%administrator can record staff payments%' then
            raise notice 'PASS: refused — %', sqlerrm;
        else raise; end if;
end $$;
rollback;


\echo ''
\echo '--- TEST 7: record_shift refuses a non-member ---'
begin;
set local "request.jwt.claim.sub" = '96959596-0000-0000-0000-000000000004';
set local role authenticated;
do $$
begin
    perform record_shift('96000000-0000-0000-0000-000000000001'::uuid,
        '96000000-0000-0000-0000-0000000000b1'::uuid, 8);
    raise exception 'FAIL: an outsider logged a shift';
exception
    when others then
        if sqlerrm like '%cannot record shifts%' then
            raise notice 'PASS: refused — %', sqlerrm;
        else raise; end if;
end $$;
rollback;


\echo ''
\echo '--- TEST 8: record_return refuses a non-member ---'
begin;
set local "request.jwt.claim.sub" = '96959596-0000-0000-0000-000000000004';
set local role authenticated;
do $$
begin
    perform record_return('96000000-0000-0000-0000-0000000000c1'::uuid);
    raise exception 'FAIL: an outsider recorded a return';
exception
    when others then
        if sqlerrm like '%cannot record a return%' then
            raise notice 'PASS: refused — %', sqlerrm;
        else raise; end if;
end $$;
rollback;


\echo ''
\echo '--- TEST 9: a recipient may mark read but not rewrite a notification ---'
insert into notifications (recipient_id, org_id, kind, message)
    values (:clerk, :shop, 'test', 'original');
begin;
set local "request.jwt.claim.sub" = '96959596-0000-0000-0000-000000000003';
set local role authenticated;
do $$
begin
    -- Allowed: the read timestamp.
    update notifications set read_at = now()
    where recipient_id = '96959596-0000-0000-0000-000000000003';
    if not exists (select 1 from notifications
                   where recipient_id = '96959596-0000-0000-0000-000000000003'
                     and read_at is not null) then
        raise exception 'FAIL: marking read did not take';
    end if;
    -- Refused: the message.
    begin
        update notifications set message = 'tampered'
        where recipient_id = '96959596-0000-0000-0000-000000000003';
        raise exception 'FAIL: a recipient rewrote a notification';
    exception
        when insufficient_privilege then
            if sqlerrm like '%permission denied%' then
                raise notice 'PASS: read yes, rewrite no — %', sqlerrm;
            else raise exception 'FAIL: refused, but not by the column grant: %', sqlerrm;
            end if;
    end;
end $$;
rollback;


\echo ''
\echo '--- TEST 10: feature_access fails closed for an anonymous caller ---'
do $$
declare v_access text;
begin
    -- No role set, no JWT: auth.uid() is null here.
    select feature_access('96000000-0000-0000-0000-000000000001'::uuid, 'products')
      into v_access;
    if v_access <> 'hidden' then
        raise exception 'FAIL: anonymous feature_access returned %, expected hidden', v_access;
    end if;
    raise notice 'PASS: an anonymous caller sees hidden, not edit';
end $$;

\echo ''
\echo '=== test_security.sql: all checks passed ==='
