-- ============================================================
-- test_platform_people.sql — the platform admin's global people directory
-- (047). Phone block 22.
--
-- The claims: only a platform admin may search people or read a person's
-- businesses; the search matches on name, phone and email; the footprint lists
-- every business a person belongs to with their role; and platform access can
-- be granted and revoked, but never on oneself and never by anyone else.
-- ============================================================
\set ON_ERROR_STOP on

\set plat  '''22222222-0000-0000-0000-000000000001'''
\set awa   '''22222222-0000-0000-0000-000000000002'''
\set boro  '''22222222-0000-0000-0000-000000000003'''
\set orgA  '''22000000-0000-0000-0000-000000000001'''
\set orgB  '''22000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, email, raw_user_meta_data) values
    (:plat, '+22622000001', 'kaj@example.com',  '{"full_name": "Plateforme"}'),
    (:awa,  '+22622000002', 'awa@example.com',  '{"full_name": "Awa Traoré"}'),
    (:boro, '+22622000003', 'boro@example.com', '{"full_name": "Boro Sana"}');
update profiles set is_platform_admin = true where id = :plat;

insert into orgs (id, name, slug, profile, default_currency) values
    (:orgA, 'Boutique A', 'boutique-a-22', 'retail', 'XOF'),
    (:orgB, 'Ferme B',    'ferme-b-22',    'farm',   'XOF');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:orgA, :awa,  'owner',    'org', :orgA, 'full'),
    (:orgB, :awa,  'employee', 'org', :orgB, 'full'),
    (:orgA, :boro, 'employee', 'org', :orgA, 'full');


\echo ''
\echo '--- TEST 1: only a platform admin may search people ---'
begin;
set local "request.jwt.claim.sub" = '22222222-0000-0000-0000-000000000002';
set local role authenticated;
do $$ begin
    begin
        perform * from platform_people(null, 50, 0);
        raise exception 'FAIL: a non-admin listed people';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the non-admin was refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 2: the platform admin searches by name, phone and email ---'
begin;
set local "request.jwt.claim.sub" = '22222222-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_all   int;
    v_awa   int;
    v_biz   bigint;
    v_email text;
begin
    select count(*) into v_all from platform_people(null, 200, 0);
    if v_all < 3 then
        raise exception 'FAIL: directory shows only % accounts', v_all;
    end if;

    -- By name.
    select count(*) into v_awa from platform_people('traor', 50, 0);
    if v_awa <> 1 then
        raise exception 'FAIL: name search returned % rows, expected 1', v_awa;
    end if;
    -- By email, and the row carries the footprint count and the email.
    select business_count, email into v_biz, v_email
      from platform_people('awa@example', 50, 0);
    if v_biz <> 2 then
        raise exception 'FAIL: Awa should count 2 businesses, got %', v_biz;
    end if;
    if v_email <> 'awa@example.com' then
        raise exception 'FAIL: the email did not come back (%).', v_email;
    end if;
    -- By phone.
    if (select count(*) from platform_people('22000003', 50, 0)) <> 1 then
        raise exception 'FAIL: phone search did not find Boro';
    end if;

    raise notice 'PASS: search matches name, email and phone; footprint counted';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: a person''s businesses and roles ---'
begin;
set local "request.jwt.claim.sub" = '22222222-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_owner int; v_emp int;
begin
    select count(*) filter (where role = 'owner'),
           count(*) filter (where role = 'employee')
      into v_owner, v_emp
      from platform_user_orgs('22222222-0000-0000-0000-000000000002');
    if v_owner <> 1 or v_emp <> 1 then
        raise exception 'FAIL: Awa should own one and staff one (% / %)', v_owner, v_emp;
    end if;
    raise notice 'PASS: the footprint lists both businesses and their roles';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: granting and revoking platform access ---'
begin;
set local "request.jwt.claim.sub" = '22222222-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_flag boolean;
begin
    -- Grant Boro platform access, then take it back.
    perform set_platform_admin('22222222-0000-0000-0000-000000000003', true);
    select is_platform_admin into v_flag from profiles
     where id = '22222222-0000-0000-0000-000000000003';
    if not v_flag then
        raise exception 'FAIL: the grant did not land';
    end if;

    perform set_platform_admin('22222222-0000-0000-0000-000000000003', false);
    select is_platform_admin into v_flag from profiles
     where id = '22222222-0000-0000-0000-000000000003';
    if v_flag then
        raise exception 'FAIL: the revoke did not land';
    end if;

    -- Never on oneself.
    begin
        perform set_platform_admin('22222222-0000-0000-0000-000000000001', false);
        raise exception 'FAIL: the admin revoked their own access';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;

    raise notice 'PASS: access granted and revoked, never on oneself';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: a non-admin cannot grant themselves platform access ---'
begin;
set local "request.jwt.claim.sub" = '22222222-0000-0000-0000-000000000003';
set local role authenticated;
do $$ begin
    begin
        perform set_platform_admin('22222222-0000-0000-0000-000000000003', true);
        raise exception 'FAIL: a non-admin granted themselves platform access';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the self-grant was refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '=== test_platform_people.sql: all checks passed ==='
