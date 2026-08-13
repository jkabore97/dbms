-- ============================================================
-- test_audit.sql — the log records what happened, and nobody can edit it.
--
-- The claim being tested is narrow and load-bearing: an admin can change who
-- may see a business's books, and every such change leaves a mark that the
-- admin themselves cannot remove. An audit log an administrator can quietly
-- clear is decoration, so most of what follows is not "does it record" but
-- "can the most privileged person in the org get rid of it".
--
-- Run as `authenticated` with a JWT subject set, never as postgres: RLS is
-- the entire mechanism here, and a superuser bypasses it.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''d3d3d3d3-0000-0000-0000-000000000001'''
\set clerk    '''d3d3d3d3-0000-0000-0000-000000000002'''
\set outsider '''d3d3d3d3-0000-0000-0000-000000000003'''

\set org   '''e3e3e3e3-0000-0000-0000-000000000001'''
\set other '''e3e3e3e3-0000-0000-0000-000000000002'''

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
    (:owner,    '+22674000001', '{"full_name":"Esperance"}'),
    (:clerk,    '+22674000002', '{"full_name":"Moussa"}'),
    (:outsider, '+22674000003', '{"full_name":"Voisin"}');

insert into orgs (id, name, slug, profile) values
    (:org,   'Boutique Test', 'boutique-test', 'retail'),
    (:other, 'Voisine Test',  'voisine-test',  'retail');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:org,   :owner,    'owner', 'org', :org),
    (:other, :outsider, 'owner', 'org', :other);

\echo ''
\echo '--- TEST 1: granting access is recorded, with the name of who granted it ---'
begin;
set local "request.jwt.claim.sub" = 'd3d3d3d3-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_org uuid := 'e3e3e3e3-0000-0000-0000-000000000001';
    v_row record;
begin
    insert into memberships (org_id, user_id, role, scope_kind, scope_id)
    values (v_org, 'd3d3d3d3-0000-0000-0000-000000000002', 'employee', 'org', v_org);

    select * into v_row
      from audit_log_page(v_org, 10)
     where table_name = 'memberships' and action = 'insert'
     order by id desc limit 1;

    if v_row is null then
        raise exception 'FAIL: granting a role left no trace';
    end if;
    if v_row.actor_label <> 'Esperance' then
        raise exception 'FAIL: the log credits % rather than Esperance', v_row.actor_label;
    end if;
    if v_row.summary <> 'employee' then
        raise exception 'FAIL: the log does not say what was granted (got %)', v_row.summary;
    end if;
    if (v_row.changed -> 'user_id') ->> 0 is null then
        raise exception 'FAIL: the log did not keep the row it wrote';
    end if;

    raise notice 'PASS: "% granted %" is in the log', v_row.actor_label, v_row.summary;
end $$;
commit;

\echo ''
\echo '--- TEST 2: an update keeps both the before and the after ---'
begin;
set local "request.jwt.claim.sub" = 'd3d3d3d3-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_org  uuid := 'e3e3e3e3-0000-0000-0000-000000000001';
    v_diff jsonb;
begin
    update orgs set name = 'Boutique Esperance' where id = v_org;

    select changed into v_diff
      from audit_log_page(v_org, 10)
     where table_name = 'orgs' and action = 'update'
     order by id desc limit 1;

    if v_diff is null then
        raise exception 'FAIL: renaming the business left no trace';
    end if;
    if (v_diff -> 'name') ->> 0 <> 'Boutique Test' then
        raise exception 'FAIL: the log lost the old name (got %)', (v_diff -> 'name') ->> 0;
    end if;
    if (v_diff -> 'name') ->> 1 <> 'Boutique Esperance' then
        raise exception 'FAIL: the log lost the new name (got %)', (v_diff -> 'name') ->> 1;
    end if;
    -- Only what moved. A diff of every column is a diff nobody reads.
    if v_diff ? 'slug' then
        raise exception 'FAIL: the diff lists columns that did not change';
    end if;

    raise notice 'PASS: the rename is logged as "Boutique Test" -> "Boutique Esperance"';
end $$;
commit;

\echo ''
\echo '--- TEST 3: revoking access is recorded too ---'
begin;
set local "request.jwt.claim.sub" = 'd3d3d3d3-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_org uuid := 'e3e3e3e3-0000-0000-0000-000000000001';
    v_n   int;
begin
    delete from memberships
     where org_id = v_org and user_id = 'd3d3d3d3-0000-0000-0000-000000000002';

    select count(*) into v_n
      from audit_log_page(v_org, 20)
     where table_name = 'memberships' and action = 'delete';

    if v_n <> 1 then
        raise exception 'FAIL: revoking a role produced % delete rows, expected 1', v_n;
    end if;
    raise notice 'PASS: the revocation is in the log as well as the grant';
end $$;
commit;

\echo ''
\echo '--- TEST 4: the owner cannot erase the log ---'
begin;
set local "request.jwt.claim.sub" = 'd3d3d3d3-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_org    uuid := 'e3e3e3e3-0000-0000-0000-000000000001';
    v_before int;
    v_after  int;
begin
    select count(*) into v_before from audit_log where org_id = v_org;
    if v_before = 0 then
        raise exception 'FAIL: nothing in the log to try to erase';
    end if;

    -- No delete policy exists, so this matches no rows rather than raising.
    -- Silence is the correct behaviour and the reason it is asserted rather
    -- than assumed.
    delete from audit_log where org_id = v_org;
    select count(*) into v_after from audit_log where org_id = v_org;
    if v_after <> v_before then
        raise exception 'FAIL: the owner deleted % log rows', v_before - v_after;
    end if;

    update audit_log set summary = 'rien' where org_id = v_org;
    if exists (select 1 from audit_log where org_id = v_org and summary = 'rien') then
        raise exception 'FAIL: the owner rewrote the log';
    end if;

    raise notice 'PASS: % log rows survived the owner trying to delete and rewrite them', v_before;
end $$;
rollback;

\echo ''
\echo '--- TEST 5: nobody can forge a log entry ---'
begin;
set local "request.jwt.claim.sub" = 'd3d3d3d3-0000-0000-0000-000000000001';
set local role authenticated;
do $$
begin
    begin
        insert into audit_log (org_id, action, table_name, summary)
        values ('e3e3e3e3-0000-0000-0000-000000000001', 'insert', 'memberships', 'inventé');
        raise exception 'FAIL: a forged log entry was accepted';
    exception
        when insufficient_privilege then
            raise notice 'PASS: the insert was refused by RLS';
        when sqlstate 'P0001' then
            if sqlerrm like 'FAIL:%' then raise; end if;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 6: an employee cannot read the log at all ---'
begin;
set local "request.jwt.claim.sub" = 'd3d3d3d3-0000-0000-0000-000000000001';
set local role authenticated;
insert into memberships (org_id, user_id, role, scope_kind, scope_id)
values (
    'e3e3e3e3-0000-0000-0000-000000000001',
    'd3d3d3d3-0000-0000-0000-000000000002',
    'employee', 'org', 'e3e3e3e3-0000-0000-0000-000000000001'
);
commit;

begin;
set local "request.jwt.claim.sub" = 'd3d3d3d3-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_org uuid := 'e3e3e3e3-0000-0000-0000-000000000001';
    v_n   int;
begin
    select count(*) into v_n from audit_log where org_id = v_org;
    if v_n <> 0 then
        raise exception 'FAIL: an employee read % rows of their colleagues'' history', v_n;
    end if;

    select count(*) into v_n from audit_log_page(v_org, 50);
    if v_n <> 0 then
        raise exception 'FAIL: audit_log_page() answered a non-admin';
    end if;

    select count(*) into v_n from org_database_overview(v_org);
    if v_n <> 0 then
        raise exception 'FAIL: a non-admin read the database overview';
    end if;

    raise notice 'PASS: the log and the overview need admin, not merely membership';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: a neighbouring business sees none of it ---'
begin;
set local "request.jwt.claim.sub" = 'd3d3d3d3-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_org uuid := 'e3e3e3e3-0000-0000-0000-000000000001';
    v_n   int;
begin
    select count(*) into v_n from audit_log_page(v_org, 50);
    if v_n <> 0 then
        raise exception 'FAIL: a rival owner read % rows of another business''s log', v_n;
    end if;

    select count(*) into v_n from org_table_columns(v_org, 'memberships');
    if v_n <> 0 then
        raise exception 'FAIL: a rival owner inspected another business''s schema';
    end if;

    raise notice 'PASS: the log stops at the edge of the business';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: the overview counts this business and no other ---'
begin;
set local "request.jwt.claim.sub" = 'd3d3d3d3-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_org    uuid := 'e3e3e3e3-0000-0000-0000-000000000001';
    v_orgs   bigint;
    v_people bigint;
    v_tables int;
begin
    select count(*) into v_tables from org_database_overview(v_org);
    if v_tables < 10 then
        raise exception 'FAIL: the overview lists only % tables', v_tables;
    end if;

    -- One business, not the two that exist.
    select row_count into v_orgs
      from org_database_overview(v_org) where table_name = 'orgs';
    if v_orgs <> 1 then
        raise exception 'FAIL: the overview counts % businesses, expected 1', v_orgs;
    end if;

    -- The owner and the clerk, not the neighbour's owner.
    select row_count into v_people
      from org_database_overview(v_org) where table_name = 'memberships';
    if v_people <> 2 then
        raise exception 'FAIL: the overview counts % memberships, expected 2', v_people;
    end if;

    raise notice 'PASS: the overview is scoped to one business';
end $$;
rollback;

\echo ''
\echo '--- TEST 9: the schema browser describes only the tables it should ---'
begin;
set local "request.jwt.claim.sub" = 'd3d3d3d3-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_org uuid := 'e3e3e3e3-0000-0000-0000-000000000001';
    v_n   int;
    v_ref text;
begin
    select count(*) into v_n from org_table_columns(v_org, 'memberships');
    if v_n < 5 then
        raise exception 'FAIL: memberships described in % columns', v_n;
    end if;

    select references_table into v_ref
      from org_table_columns(v_org, 'memberships') where column_name = 'org_id';
    if v_ref <> 'orgs' then
        raise exception 'FAIL: org_id is not shown as pointing at orgs (got %)', v_ref;
    end if;

    -- Not on the list, at any privilege level.
    select count(*) into v_n from org_table_columns(v_org, 'users');
    if v_n <> 0 then
        raise exception 'FAIL: a table outside the whitelist was described';
    end if;

    raise notice 'PASS: the browser describes the app''s tables and nothing else';
end $$;
rollback;

\echo ''
\echo '--- TEST 10: recording money is logged, and its author is the one who did it ---'
begin;
set local "request.jwt.claim.sub" = 'd3d3d3d3-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_org uuid := 'e3e3e3e3-0000-0000-0000-000000000001';
    v_who text;
begin
    perform record_entry(
        p_org_id => v_org, p_amount => 7500, p_direction => 'in',
        p_label => 'Vente de savon',
        p_recorded_by => 'd3d3d3d3-0000-0000-0000-000000000002'
    );

    -- Read back as the owner: the clerk cannot read the log, which is TEST 6.
    set local "request.jwt.claim.sub" = 'd3d3d3d3-0000-0000-0000-000000000001';

    select actor_label into v_who
      from audit_log_page(v_org, 20)
     where table_name = 'journal_entries' and summary = 'Vente de savon'
     order by id desc limit 1;

    if v_who is null then
        raise exception 'FAIL: the entry was not logged';
    end if;
    -- record_entry() is SECURITY DEFINER and runs as the table owner. The log
    -- must still name the human, not the role the function borrowed.
    if v_who <> 'Moussa' then
        raise exception 'FAIL: the log credits % rather than Moussa', v_who;
    end if;

    raise notice 'PASS: a definer function does not launder who made the entry';
end $$;
rollback;

\echo ''
\echo '============================================'
\echo ' All audit assertions passed.'
\echo '============================================'
