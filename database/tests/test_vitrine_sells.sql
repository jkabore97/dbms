-- ============================================================
-- test_vitrine_sells.sql — a vitrine that is never empty, and says so (070).
-- Phone block 42.
--
-- The claims: a new article is on the vitrine unless hidden, an ingredient
-- never is, and an existing decision is not overturned; "Tout publier"
-- publishes every priced, active, non-ingredient article for somebody the
-- articles dial lets edit, and is refused to anyone else; an open window
-- with an empty shelf is not listed until it has an article; the cards'
-- previews are three per shop, photographed first, only from open
-- windows; the checklist answers the shop's members and nobody else.
-- ============================================================
\set ON_ERROR_STOP on
-- 092 hides a vitrine below 8 items (test_vitrine_minimum.sql); this
-- suite is about something else, so it keeps the old rule (no minimum).
update platform_settings set value = '0' where key = 'vitrine_min_items';

\set owner  '''42424242-0000-0000-0000-000000000001'''
\set clerk  '''42424242-0000-0000-0000-000000000002'''
\set other  '''42424242-0000-0000-0000-000000000003'''
\set shop   '''42000000-0000-0000-0000-000000000001'''
\set closed '''42000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname='anon') then
        create role anon nologin;
    end if;
end $$;
grant usage on schema public to authenticated, anon;
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22642000001', '{"full_name": "Propriétaire"}'),
    (:clerk, '+22642000002', '{"full_name": "Vendeuse"}'),
    (:other, '+22642000003', '{"full_name": "Étrangère"}');
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled) values
    (:shop,   'Boutique Pleine', 'pleine-42', 'retail', 'XOF', true),
    (:closed, 'Boutique Fermée', 'fermee-42', 'retail', 'XOF', false);
-- Businesses already on the street: 085's path to it (60 %) is for the
-- ones that start from now on, and this file is about the street itself.
update orgs set progress_since = null where progress_since is not null;
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop, :owner, 'owner',    'org', :shop, 'full'),
    (:shop, :clerk, 'employee', 'org', :shop, 'full');


\echo ''
\echo '--- TEST 1: an open window with an empty shelf is not listed; one article lists it ---'
begin;
set local role anon;
do $$ begin
    if exists (select 1 from storefront_directory() where slug = 'pleine-42') then
        raise exception 'FAIL: an empty window is in the directory';
    end if;
end $$;
reset role;
insert into products (org_id, name, sale_price, quantity, is_active)
values (:shop, 'Savon', 450, 10, true);
set local role anon;
do $$ begin
    if not exists (select 1 from storefront_directory() where slug = 'pleine-42') then
        raise exception 'FAIL: a window with an article is missing from the directory';
    end if;
    raise notice 'PASS: empty window unlisted; listed once one article is on it';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: published unless hidden; an ingredient never; old decisions kept ---'
begin;
insert into products (id, org_id, name, sale_price, quantity, is_active) values
    ('42aaaaaa-0000-0000-0000-000000000001', :shop, 'Sucre', 750, 5, true);
insert into products (id, org_id, name, sale_price, quantity, is_active, is_ingredient) values
    ('42aaaaaa-0000-0000-0000-000000000002', :shop, 'Farine', 300, 50, true, true);
insert into products (id, org_id, name, sale_price, quantity, is_active, is_published) values
    ('42aaaaaa-0000-0000-0000-000000000003', :shop, 'Caché', 900, 5, true, false);
do $$ begin
    if not (select is_published from products where id = '42aaaaaa-0000-0000-0000-000000000001') then
        raise exception 'FAIL: a new article was not published by default';
    end if;
    if (select is_published from products where id = '42aaaaaa-0000-0000-0000-000000000002') then
        raise exception 'FAIL: an ingredient reached the street';
    end if;
    if (select is_published from products where id = '42aaaaaa-0000-0000-0000-000000000003') then
        raise exception 'FAIL: an article the owner hid was published';
    end if;
    raise notice 'PASS: default published, ingredient hidden, an explicit hide kept';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: Tout publier — the priced, active, non-ingredient ones, by the right person ---'
begin;
insert into products (org_id, name, sale_price, quantity, is_active, is_published, is_ingredient) values
    (:shop, 'A', 100, 1, true,  false, false),
    (:shop, 'B', 200, 1, true,  false, false),
    (:shop, 'Sans prix', 0, 1, true, false, false),
    (:shop, 'Archivé', 300, 1, false, false, false),
    (:shop, 'Farine', 300, 1, true, false, true);
insert into org_feature_rules (org_id, tier, feature, access)
values (:shop, 'employee', 'products', 'view');
set local role authenticated;
set local "request.jwt.claim.sub" = '42424242-0000-0000-0000-000000000002';
do $$ begin
    begin
        perform publish_all_products('42000000-0000-0000-0000-000000000001');
        raise exception 'FAIL: a view-only employee published everything';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '42424242-0000-0000-0000-000000000003';
do $$ begin
    begin
        perform publish_all_products('42000000-0000-0000-0000-000000000001');
        raise exception 'FAIL: a stranger published another shop';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '42424242-0000-0000-0000-000000000001';
do $$
declare n int;
begin
    n := publish_all_products('42000000-0000-0000-0000-000000000001');
    if n <> 2 then
        raise exception 'FAIL: published % articles, expected A and B only', n;
    end if;
    raise notice 'PASS: view-only and stranger refused; the owner published the 2 priced, active, non-ingredient ones';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: three previews per open shop, photographed first ---'
begin;
insert into products (id, org_id, name, sale_price, quantity, is_active) values
    ('42bbbbbb-0000-0000-0000-000000000001', :shop, 'Aaa', 100, 1, true),
    ('42bbbbbb-0000-0000-0000-000000000002', :shop, 'Bbb', 100, 1, true),
    ('42bbbbbb-0000-0000-0000-000000000003', :shop, 'Ccc', 100, 1, true),
    ('42bbbbbb-0000-0000-0000-000000000004', :shop, 'Zzz photo', 100, 1, true);
insert into documents (org_id, r2_key, kind, uploaded_by, product_id) values
    (:shop, 'org/42000000-0000-0000-0000-000000000001/z.jpg', 'photo', :owner,
     '42bbbbbb-0000-0000-0000-000000000004');
insert into products (org_id, name, sale_price, quantity, is_active) values
    (:closed, 'Fermé', 100, 1, true);
set local role anon;
do $$
declare v_names text[];
begin
    select array_agg(name order by name) into v_names
      from storefront_previews(array['pleine-42']);
    if array_length(v_names, 1) <> 3 then
        raise exception 'FAIL: % previews, expected 3', array_length(v_names, 1);
    end if;
    if not ('Zzz photo' = any (v_names)) then
        raise exception 'FAIL: the photographed article is not among the previews: %', v_names;
    end if;
    if (select name from storefront_previews(array['pleine-42']) limit 1) <> 'Zzz photo' then
        raise exception 'FAIL: the photographed article is not first';
    end if;
    if exists (select 1 from storefront_previews(array['fermee-42'])) then
        raise exception 'FAIL: a closed window gave previews';
    end if;
    raise notice 'PASS: three previews, the photographed one first; nothing from a closed window';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: the checklist answers members and nobody else ---'
begin;
insert into products (org_id, name, sale_price, quantity, is_active, is_published) values
    (:shop, 'Publié', 100, 1, true, true),
    (:shop, 'Pas publié', 100, 1, true, false);
update orgs set storefront_blurb = 'Le quartier', phone = '+22670000000' where id = :shop;
set local role authenticated;
set local "request.jwt.claim.sub" = '42424242-0000-0000-0000-000000000002';
do $$
declare v jsonb;
begin
    v := vitrine_checklist('42000000-0000-0000-0000-000000000001');
    if (v ->> 'published')::int <> 1 or (v ->> 'unpublished')::int <> 1
       or not (v ->> 'blurb')::boolean or not (v ->> 'phone')::boolean
       or (v ->> 'address')::boolean or (v ->> 'pin')::boolean then
        raise exception 'FAIL: the checklist reads %', v;
    end if;
end $$;
set local "request.jwt.claim.sub" = '42424242-0000-0000-0000-000000000003';
do $$ begin
    if vitrine_checklist('42000000-0000-0000-0000-000000000001') is not null then
        raise exception 'FAIL: a stranger read the checklist';
    end if;
    raise notice 'PASS: a member reads published, unpublished, blurb, phone; a stranger reads nothing';
end $$;
rollback;
