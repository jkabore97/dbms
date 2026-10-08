-- ============================================================
-- test_trainer.sql — trainer accounts of 038.
--
-- Phone block 16. What matters:
--   1. Only a platform admin marks a trainer and assigns them; nobody else.
--   2. A business can only be assigned an account that is a trainer.
--   3. An assigned trainer reads everything (full visibility) and writes and
--      administers nothing — the whole safety of the feature.
--   4. trainer_orgs and org_trainers see the assignment from both ends, and
--      unassign_trainer removes it.
-- ============================================================
\set ON_ERROR_STOP on

\set admin   '''16161616-0000-0000-0000-000000000001'''
\set trainer '''16161616-0000-0000-0000-000000000002'''
\set owner   '''16161616-0000-0000-0000-000000000003'''
\set org     '''16000000-0000-0000-0000-000000000001'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:admin,   '+22616000001', '{"full_name": "Plateforme"}'),
    (:trainer, '+22616000002', '{"full_name": "Formateur"}'),
    (:owner,   '+22616000003', '{"full_name": "Patronne"}');
update profiles set is_platform_admin = true where id = :admin;

insert into orgs (id, name, slug, profile, default_currency)
values (:org, 'Boutique Client', 'boutique-client-16', 'retail', 'XOF');
select seed_retail_accounts(:org);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:org, :owner, 'owner', 'org', :org, 'full');


\echo ''
\echo '--- TEST 1: only a platform admin marks a trainer ---'
begin;
set local "request.jwt.claim.sub" = '16161616-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_raised boolean := false;
begin
    begin
        perform set_trainer_by_phone('+22616000002', true);
    exception when others then v_raised := true;
    end;
    if not v_raised then
        raise exception 'FAIL: a non-admin marked a trainer';
    end if;
    raise notice 'PASS: a non-admin cannot mark a trainer';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: the admin marks the trainer, then assigns the business ---'
begin;
set local "request.jwt.claim.sub" = '16161616-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_user uuid; v_ok boolean;
begin
    v_user := set_trainer_by_phone('+22616000002', true);
    if v_user <> '16161616-0000-0000-0000-000000000002'::uuid then
        raise exception 'FAIL: set_trainer returned % ', v_user;
    end if;

    -- A non-trainer cannot be assigned.
    begin
        perform assign_trainer('16000000-0000-0000-0000-000000000001',
                               '16161616-0000-0000-0000-000000000003');
        raise exception 'FAIL: assigned a non-trainer (the owner)';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;

    perform assign_trainer('16000000-0000-0000-0000-000000000001',
                           '16161616-0000-0000-0000-000000000002');
    select exists (
        select 1 from memberships
        where org_id = '16000000-0000-0000-0000-000000000001'
          and user_id = '16161616-0000-0000-0000-000000000002'
          and role = 'observer' and visibility = 'full' and is_trainer
    ) into v_ok;
    if not v_ok then
        raise exception 'FAIL: the trainer assignment was not written correctly';
    end if;

    -- Idempotent: a second assign does not double the grant.
    perform assign_trainer('16000000-0000-0000-0000-000000000001',
                           '16161616-0000-0000-0000-000000000002');
    if (select count(*) from memberships
        where org_id = '16000000-0000-0000-0000-000000000001'
          and user_id = '16161616-0000-0000-0000-000000000002') <> 1 then
        raise exception 'FAIL: re-assigning doubled the grant';
    end if;

    raise notice 'PASS: trainer marked, non-trainer refused, assignment idempotent';
end $$;
commit;

\echo ''
\echo '--- TEST 3: the trainer reads all, writes nothing, administers nothing ---'
begin;
set local "request.jwt.claim.sub" = '16161616-0000-0000-0000-000000000002';
set local role authenticated;
do $$
begin
    if not has_full_visibility('16000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the trainer lacks full visibility to advise';
    end if;
    if can_write_org('16000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the trainer can write to the business';
    end if;
    if is_org_admin('16000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the trainer can administer the business';
    end if;
    raise notice 'PASS: trainer reads all, writes none, administers none';
end $$;

do $$
declare v_here boolean;
begin
    -- The trainer sees the business in their own list.
    select exists (
        select 1 from trainer_orgs()
        where org_id = '16000000-0000-0000-0000-000000000001'
    ) into v_here;
    if not v_here then
        raise exception 'FAIL: trainer_orgs did not list the assigned business';
    end if;
    raise notice 'PASS: trainer_orgs lists the assigned business';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: both ends see it; the admin can unassign ---'
begin;
set local "request.jwt.claim.sub" = '16161616-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_here boolean; v_count int;
begin
    select exists (
        select 1 from org_trainers('16000000-0000-0000-0000-000000000001')
        where user_id = '16161616-0000-0000-0000-000000000002'
    ) into v_here;
    if not v_here then
        raise exception 'FAIL: org_trainers did not list the trainer';
    end if;

    select count(*) into v_count from list_trainers()
    where user_id = '16161616-0000-0000-0000-000000000002';
    if v_count <> 1 then
        raise exception 'FAIL: list_trainers did not include the trainer (got %)', v_count;
    end if;

    perform unassign_trainer('16000000-0000-0000-0000-000000000001',
                             '16161616-0000-0000-0000-000000000002');
    if exists (
        select 1 from memberships
        where org_id = '16000000-0000-0000-0000-000000000001'
          and user_id = '16161616-0000-0000-0000-000000000002' and is_trainer
    ) then
        raise exception 'FAIL: unassign_trainer did not remove the grant';
    end if;

    raise notice 'PASS: both ends saw it, unassign removed it';
end $$;
rollback;

\echo ''
\echo '=== test_trainer.sql: all checks passed ==='
