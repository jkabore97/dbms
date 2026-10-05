-- ============================================================
-- test_org_logo.sql — a shop's own logo (080). Phone block 50.
--
-- The claims: only an administrator sets it, only to one of the shop's own
-- photographs (never a PDF, never another shop's), and null clears it; the
-- window carries it for a Free shop as for a Pro one, without the Free shop
-- gaining any Pro dressing; and the Worker may serve it to the street while
-- the vitrine is open — and not once it is closed.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''50505050-0000-0000-0000-000000000001'''
\set clerk '''50505050-0000-0000-0000-000000000002'''
\set other '''50505050-0000-0000-0000-000000000003'''
\set shop  '''50000000-0000-0000-0000-000000000001'''
\set far   '''50000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22650000001', '{"full_name": "Awa"}'),
    (:clerk, '+22650000002', '{"full_name": "Vendeuse"}'),
    (:other, '+22650000003', '{"full_name": "Voisine"}');
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled) values
    (:shop, 'Shop Style', 'style-50',    'retail', 'XOF', true),
    (:far,  'Ailleurs',   'ailleurs-50', 'retail', 'XOF', true);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop, :owner, 'owner',    'org', :shop, 'full'),
    (:shop, :clerk, 'employee', 'org', :shop, 'full'),
    (:far,  :other, 'owner',    'org', :far,  'full');
insert into documents (org_id, r2_key, kind, uploaded_by, content_type) values
    (:shop, 'org/50/logo.png', 'logo',    :owner, 'image/png'),
    (:shop, 'org/50/note.pdf', 'invoice', :owner, 'application/pdf'),
    (:far,  'org/50/far.png',  'logo',    :other, 'image/png');

\echo ''
\echo '--- TEST 1: an administrator, one of the shop''s own pictures ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '50505050-0000-0000-0000-000000000002';
do $$ begin
    perform set_org_logo('50000000-0000-0000-0000-000000000001', 'org/50/logo.png');
    raise exception 'FAIL: an employee set the logo';
exception when others then
    if sqlerrm not like 'Seul un administrateur%' then raise; end if;
end $$;
set local "request.jwt.claim.sub" = '50505050-0000-0000-0000-000000000001';
do $$ begin
    begin
        perform set_org_logo('50000000-0000-0000-0000-000000000001', 'org/50/far.png');
        raise exception 'FAIL: another shop''s picture became the logo';
    exception when others then
        if sqlerrm not like 'Le logo doit être une photo%' then raise; end if;
    end;
    begin
        perform set_org_logo('50000000-0000-0000-0000-000000000001', 'org/50/note.pdf');
        raise exception 'FAIL: a PDF became the logo';
    exception when others then
        if sqlerrm not like 'Le logo doit être une photo%' then raise; end if;
    end;
    perform set_org_logo('50000000-0000-0000-0000-000000000001', 'org/50/logo.png');
    raise notice 'PASS: the clerk refused, a stranger''s picture and a PDF refused';
end $$;
commit;

\echo ''
\echo '--- TEST 2: the window carries it, Free or Pro, and the street may see it ---'
do $$
declare st jsonb;
begin
    select style into st from storefront('style-50');
    if st - 'delivers' <> '{"logo_key": "org/50/logo.png"}'::jsonb then
        raise exception 'FAIL: a Free shop''s window style is %', st;
    end if;
    if not storefront_photo_allowed('org/50/logo.png') then
        raise exception 'FAIL: the street may not see an open vitrine''s logo';
    end if;
    if storefront_photo_allowed('org/50/note.pdf') then
        raise exception 'FAIL: a document that is no logo is served';
    end if;
    update orgs set storefront_enabled = false where id = '50000000-0000-0000-0000-000000000001';
    if storefront_photo_allowed('org/50/logo.png') then
        raise exception 'FAIL: a closed vitrine''s logo is still served';
    end if;
    update orgs set storefront_enabled = true where id = '50000000-0000-0000-0000-000000000001';
    raise notice 'PASS: logo only in the Free style, served while open, not when closed';
end $$;

\echo ''
\echo '--- TEST 3: null clears it ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '50505050-0000-0000-0000-000000000001';
select set_org_logo('50000000-0000-0000-0000-000000000001', null);
do $$ begin
    if (select logo_key from orgs where id = '50000000-0000-0000-0000-000000000001') is not null then
        raise exception 'FAIL: the logo did not clear';
    end if;
    raise notice 'PASS: Retirer clears the logo';
end $$;
rollback;

\echo ''
\echo 'test_org_logo: all passed'
