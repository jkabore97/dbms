-- ============================================================
-- test_academy.sql — Académie Mara (087). Phone block 57.
--
-- The claims: a business sees the lessons of its kind; a guide is done
-- when seen, a mission only once it is lived in the business's own data;
-- each lesson pays the business once, however many of its people take it;
-- each person climbs their own levels; an association's people learn but
-- earn no cauris; and a stranger can neither read nor finish a lesson.
-- ============================================================
\set ON_ERROR_STOP on
-- 092 hides a vitrine below 8 items (test_vitrine_minimum.sql); this
-- suite is about something else, so it keeps the old rule (no minimum).
update platform_settings set value = '0' where key = 'vitrine_min_items';

\set owner '''57575757-0000-0000-0000-000000000001'''
\set clerk '''57575757-0000-0000-0000-000000000002'''
\set other '''57575757-0000-0000-0000-000000000003'''
\set shop  '''57000000-0000-0000-0000-000000000001'''
\set farm  '''57000000-0000-0000-0000-000000000002'''
\set assoc '''57000000-0000-0000-0000-000000000003'''

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
-- Earlier files hand every function to everyone: 087 takes its own back.
\i database/migrations/087_academy.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22657000001', '{"full_name": "Awa"}'),
    (:clerk, '+22657000002', '{"full_name": "Vendeur"}'),
    (:other, '+22657000003', '{"full_name": "Autre"}');
insert into orgs (id, name, slug, profile, default_currency, progress_since) values
    (:shop,  'Boutique Académie', 'academie-57', 'retail',      'XOF', null),
    (:farm,  'Ferme Académie',    'ferme-57',    'farm',        'XOF', null),
    (:assoc, 'Association 57',    'assoc-57',    'association', 'XOF', null);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :owner, 'owner',    'org', :shop,  'full'),
    (:shop,  :clerk, 'employee', 'org', :shop,  'full'),
    (:farm,  :owner, 'owner',    'org', :farm,  'full'),
    (:assoc, :owner, 'owner',    'org', :assoc, 'full');

\echo ''
\echo '--- TEST 1: the lessons of its kind; a guide done when seen ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000001';
do $$
declare a jsonb := my_academy('57000000-0000-0000-0000-000000000001');
        f jsonb := my_academy('57000000-0000-0000-0000-000000000002');
        r jsonb;
begin
    if exists (select 1 from jsonb_array_elements(a -> 'lessons') x where x ->> 'key' = 'farm_log')
       or not exists (select 1 from jsonb_array_elements(f -> 'lessons') x where x ->> 'key' = 'farm_log')
       or exists (select 1 from jsonb_array_elements(f -> 'lessons') x where x ->> 'key' = 'first_sale') then
        raise exception 'FAIL: the lessons are not the business''s kind';
    end if;
    if a ->> 'level' <> 'Apprenti' or (a ->> 'done')::int <> 0 then
        raise exception 'FAIL: a beginner is not an Apprenti: %', a;
    end if;
    r := complete_lesson('57000000-0000-0000-0000-000000000001', 'welcome');
    if not (r ->> 'done')::boolean or (r ->> 'earned')::int <> 10 then
        raise exception 'FAIL: a seen guide is not done and paid: %', r;
    end if;
    raise notice 'PASS: % lessons for a shop, the guide done, +10', (a ->> 'total');
end $$;
commit;

\echo ''
\echo '--- TEST 2: a mission only once lived ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000001';
do $$
declare r jsonb;
begin
    r := complete_lesson('57000000-0000-0000-0000-000000000001', 'first_sale');
    if (r ->> 'done')::boolean then
        raise exception 'FAIL: a mission was done without a sale';
    end if;
end $$;
commit;
insert into sales (org_id, total) values ('57000000-0000-0000-0000-000000000001', 1000);
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000001';
do $$
declare a jsonb := my_academy('57000000-0000-0000-0000-000000000001');
        r jsonb;
begin
    if not (select (x ->> 'ready')::boolean from jsonb_array_elements(a -> 'lessons') x
             where x ->> 'key' = 'first_sale') then
        raise exception 'FAIL: a lived mission is not ready to collect';
    end if;
    r := complete_lesson('57000000-0000-0000-0000-000000000001', 'first_sale');
    if not (r ->> 'done')::boolean or (r ->> 'earned')::int <> 10 then
        raise exception 'FAIL: the lived mission did not pay: %', r;
    end if;
    raise notice 'PASS: refused before the sale, paid after it';
end $$;
commit;

\echo ''
\echo '--- TEST 3: once per business in cauris; each person climbs alone ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000002';
do $$
declare r jsonb;
begin
    r := complete_lesson('57000000-0000-0000-0000-000000000001', 'welcome');
    if not (r ->> 'done')::boolean or (r ->> 'earned')::int <> 0 then
        raise exception 'FAIL: a second person was paid again for the same lesson: %', r;
    end if;
    if (my_academy('57000000-0000-0000-0000-000000000001') ->> 'done')::int <> 1 then
        raise exception 'FAIL: the clerk''s own progress is not their own';
    end if;
end $$;
commit;
do $$ begin
    if cauris_balance('57000000-0000-0000-0000-000000000001') <> 20 then
        raise exception 'FAIL: the shop was paid % for two lessons',
            cauris_balance('57000000-0000-0000-0000-000000000001');
    end if;
    raise notice 'PASS: 20 cauris for two lessons, whoever took them';
end $$;

\echo ''
\echo '--- TEST 4: the levels; an association learns without cauris; strangers out ---'
-- Everything lived, then every lesson taken.
update orgs set storefront_enabled = true where id = '57000000-0000-0000-0000-000000000001';
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
select '57000000-0000-0000-0000-000000000001', 'Article ' || i, 100, 1, true, true
  from generate_series(1, 3) i;
insert into documents (org_id, product_id, kind, r2_key, uploaded_by)
select '57000000-0000-0000-0000-000000000001', id, 'product_photo', 'a/' || id,
       '57575757-0000-0000-0000-000000000001'
  from products where org_id = '57000000-0000-0000-0000-000000000001';
insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency)
values ('57000000-0000-0000-0000-000000000001', '57575757-0000-0000-0000-000000000003',
        'Autre', 'accepted', 'pickup', 1000, 'XOF');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000001';
do $$
declare k text; a jsonb;
begin
    for k in select x ->> 'key' from jsonb_array_elements(
                 my_academy('57000000-0000-0000-0000-000000000001') -> 'lessons') x loop
        perform complete_lesson('57000000-0000-0000-0000-000000000001', k);
    end loop;
    a := my_academy('57000000-0000-0000-0000-000000000001');
    if a ->> 'level' <> 'Maître' or (a ->> 'done')::int <> (a ->> 'total')::int then
        raise exception 'FAIL: every lesson done is not Maître: %', a;
    end if;
    perform complete_lesson('57000000-0000-0000-0000-000000000003', 'welcome');
    if (my_academy('57000000-0000-0000-0000-000000000003') ->> 'done')::int <> 1 then
        raise exception 'FAIL: an association''s people cannot learn';
    end if;
    raise notice 'PASS: Maître with all %; the association learned', a ->> 'total';
end $$;
set local "request.jwt.claim.sub" = '57575757-0000-0000-0000-000000000003';
do $$ begin
    if my_academy('57000000-0000-0000-0000-000000000001') is not null then
        raise exception 'FAIL: a stranger reads the academy';
    end if;
    begin
        perform complete_lesson('57000000-0000-0000-0000-000000000001', 'welcome');
        raise exception 'FAIL: a stranger finished a lesson';
    exception when others then
        if sqlerrm not like 'Leçon réservée%' then raise; end if;
    end;
end $$;
commit;
do $$ begin
    if cauris_balance('57000000-0000-0000-0000-000000000003') <> 0 then
        raise exception 'FAIL: an association earned cauris from a lesson';
    end if;
    if has_function_privilege('authenticated', 'academy_mission_met(uuid, text)', 'execute')
       or has_function_privilege('anon', 'complete_lesson(uuid, text)', 'execute') then
        raise exception 'FAIL: the grants are not as drawn';
    end if;
end $$;

\echo ''
\echo 'test_academy: all passed'
