-- ============================================================
-- test_first_setup.sql — the guided first steps (091). Phone block 61.
--
-- The claims: a new shop starts not set up; it cannot be finished without
-- an article; once an article is in, its admin finishes it, an employee
-- cannot; and feature_states() says where it stands.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''61616161-0000-0000-0000-000000000001'''
\set clerk '''61616161-0000-0000-0000-000000000002'''
\set shop  '''61000000-0000-0000-0000-000000000001'''

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
\i database/migrations/091_first_setup.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22661000001', '{"full_name": "Awa"}'),
    (:clerk, '+22661000002', '{"full_name": "Vendeur"}');
insert into orgs (id, name, slug, profile, default_currency) values
    (:shop, 'Boutique 61', 'boutique-61', 'retail', 'XOF');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop, :owner, 'owner',    'org', :shop, 'full'),
    (:shop, :clerk, 'employee', 'org', :shop, 'full');

\echo ''
\echo '--- TEST 1: not set up, and not without an article ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '61616161-0000-0000-0000-000000000001';
do $$ begin
    if (feature_states('61000000-0000-0000-0000-000000000001') ->> 'setup_done')::boolean then
        raise exception 'FAIL: a new shop is already set up';
    end if;
    begin
        perform finish_setup('61000000-0000-0000-0000-000000000001');
        raise exception 'FAIL: finished without an article';
    exception when others then
        if sqlerrm not like 'Ajoutez d''abord un article%' then raise; end if;
    end;
    raise notice 'PASS: not set up, and an article is required';
end $$;
commit;

\echo ''
\echo '--- TEST 2: the admin finishes it, an employee cannot ---'
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
values ('61000000-0000-0000-0000-000000000001', 'Riz', 1000, 10, true, true);
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '61616161-0000-0000-0000-000000000002';
do $$ begin
    begin
        perform finish_setup('61000000-0000-0000-0000-000000000001');
        raise exception 'FAIL: an employee finished the setup';
    exception when others then
        if sqlerrm not like 'Seul un administrateur%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '61616161-0000-0000-0000-000000000001';
select finish_setup('61000000-0000-0000-0000-000000000001');
do $$ begin
    if not (feature_states('61000000-0000-0000-0000-000000000001') ->> 'setup_done')::boolean then
        raise exception 'FAIL: the setup is not recorded';
    end if;
    raise notice 'PASS: refused to the employee, recorded for the owner';
end $$;
commit;
do $$ begin
    if has_function_privilege('anon', 'finish_setup(uuid)', 'execute') then
        raise exception 'FAIL: anon can finish a setup';
    end if;
end $$;

\echo ''
\echo 'test_first_setup: all passed'
