-- ============================================================
-- test_platform_audit.sql — the platform-wide audit view (048). Phone block 23.
--
-- The claims: only a platform admin may read it; it spans every business and
-- carries each event's business name; and the org, action and keyset filters
-- narrow it correctly.
-- ============================================================
\set ON_ERROR_STOP on

\set plat  '''23232323-0000-0000-0000-000000000001'''
\set owner '''23232323-0000-0000-0000-000000000002'''
\set orgA  '''23000000-0000-0000-0000-000000000001'''
\set orgB  '''23000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:plat,  '+22623000001', '{"full_name": "Plateforme"}'),
    (:owner, '+22623000002', '{"full_name": "Patronne"}');
update profiles set is_platform_admin = true where id = :plat;

insert into orgs (id, name, slug, profile, default_currency) values
    (:orgA, 'Boutique A', 'boutique-a-23', 'retail', 'XOF'),
    (:orgB, 'Ferme B',    'ferme-b-23',    'farm',   'XOF');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
values (:orgA, :owner, 'owner', 'org', :orgA, 'full');

-- Deterministic events, written straight in (as the superuser running the
-- suite) so the read has known rows to find regardless of which tables the
-- trigger watches.
insert into audit_log (org_id, actor_id, actor_label, action, table_name, row_id, summary)
values
    (:orgA, :owner, 'Patronne', 'delete', 'products',    gen_random_uuid(), 'Savon retiré'),
    (:orgA, :owner, 'Patronne', 'update', 'orgs',        gen_random_uuid(), 'Nom modifié'),
    (:orgB, :owner, 'Patronne', 'insert', 'memberships', gen_random_uuid(), 'Membre ajouté');


\echo ''
\echo '--- TEST 1: a non-admin reads nothing ---'
begin;
set local "request.jwt.claim.sub" = '23232323-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v_n int;
begin
    select count(*) into v_n from platform_audit_page(50, null, null, null, null);
    if v_n <> 0 then
        raise exception 'FAIL: a non-admin read % audit rows', v_n;
    end if;
    raise notice 'PASS: the non-admin reads nothing';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: the platform admin sees every business, with filters ---'
begin;
set local "request.jwt.claim.sub" = '23232323-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_orgs  int;
    v_name  text;
    v_a_tot int; v_a_leak int;
    v_d_tot int; v_d_leak int;
begin
    -- Spans every business: both orgs appear (the trigger also logs the seed's
    -- own writes, so exact counts are not asserted — filter correctness is).
    select count(distinct org_id) into v_orgs
      from platform_audit_page(200, null, null, null, null);
    if v_orgs < 2 then
        raise exception 'FAIL: the platform view spans only % business(es)', v_orgs;
    end if;

    -- The business name rides along.
    select org_name into v_name
      from platform_audit_page(50, null, '23000000-0000-0000-0000-000000000002', null, null)
     limit 1;
    if v_name is distinct from 'Ferme B' then
        raise exception 'FAIL: the event did not carry its business name (%).', v_name;
    end if;

    -- Filter by business: rows come back, and none leak from another business.
    select count(*), count(*) filter (where org_id <> '23000000-0000-0000-0000-000000000001')
      into v_a_tot, v_a_leak
      from platform_audit_page(200, null, '23000000-0000-0000-0000-000000000001', null, null);
    if v_a_tot < 2 or v_a_leak <> 0 then
        raise exception 'FAIL: org filter — % rows, % from the wrong business', v_a_tot, v_a_leak;
    end if;

    -- Filter by action: our one delete is there, and nothing that is not a
    -- delete comes back.
    select count(*), count(*) filter (where action <> 'delete')
      into v_d_tot, v_d_leak
      from platform_audit_page(200, null, null, 'delete', null);
    if v_d_tot < 1 or v_d_leak <> 0 then
        raise exception 'FAIL: delete filter — % rows, % not deletes', v_d_tot, v_d_leak;
    end if;

    raise notice 'PASS: the whole platform, named, and the filters narrow it';
end $$;
rollback;

\echo ''
\echo '=== test_platform_audit.sql: all checks passed ==='
