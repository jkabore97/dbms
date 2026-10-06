-- ============================================================
-- test_showcase.sql — the vitrines d'exemple (094). Phone block 64.
--
-- The claims: a platform admin makes the seven, each with 10 to 15
-- articles on sale, owned by that admin, Pro, off the map; the street
-- opens them to anyone and lists them, and showcase_slugs() names them; a
-- second seed makes nothing and keeps the admin's edits; nobody can order
-- from one, by any path; they earn no cauris; another platform admin
-- takes the keys with showcase_join(); hiding one takes it off the street;
-- and none of this is open to a shopkeeper or to anon.
-- ============================================================
\set ON_ERROR_STOP on

\set plat   '''64646464-0000-0000-0000-000000000001'''
\set plat2  '''64646464-0000-0000-0000-000000000002'''
\set shop   '''64646464-0000-0000-0000-000000000003'''

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
update platform_settings set value = '8' where key = 'vitrine_min_items';

insert into auth.users (id, phone, raw_user_meta_data) values
    (:plat,  '+22664000001', '{"full_name": "Plateforme"}'),
    (:plat2, '+22664000002', '{"full_name": "Plateforme 2"}'),
    (:shop,  '+22664000003', '{"full_name": "Commerçant"}');
update profiles set is_platform_admin = true where id in (:plat, :plat2);
-- Re-applied once the roles exist, for its grants; its own seed then makes
-- the seven for the oldest platform admin on this database.
\i database/migrations/094_showcase_vitrines.sql

\echo ''
\echo '--- TEST 1: the seven exist, full and dressed ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '64646464-0000-0000-0000-000000000001';
do $$
declare v_made int; r record;
begin
    v_made := showcase_seed();
    if v_made <> 0 then
        raise exception 'FAIL: % stores made twice', v_made;
    end if;
    for r in select * from showcase_list() loop
        if r.items < 10 or r.items > 15 then
            raise exception 'FAIL: % has % articles', r.slug, r.items;
        end if;
        if not r.visible then
            raise exception 'FAIL: % is not on the street', r.slug;
        end if;
    end loop;
    if exists (select 1 from orgs o where o.showcase and not exists (
                 select 1 from memberships m where m.org_id = o.id and m.role = 'owner')) then
        raise exception 'FAIL: a showcase has no owner';
    end if;
    if (select count(*) from showcase_list()) <> 7 then
        raise exception 'FAIL: the list does not hold seven';
    end if;
    if (select photos from showcase_list() where slug = 'rowan-bike-shop') <> 15
       or (select photos from showcase_list() where slug = 'bob-electronics') <> 0 then
        raise exception 'FAIL: the photos are not where they should be';
    end if;
    if exists (select 1 from orgs where showcase
                and (plan <> 'pro' or lat is not null or setup_done_at is null)) then
        raise exception 'FAIL: a showcase is not Pro, is on the map, or wants a first setup';
    end if;
    if (select storefront_style ->> 'cover_key' from orgs where slug = 'tony-pizza')
       <> 'showcase/tony-pizza/pizza-pepperoni.jpg' then
        raise exception 'FAIL: the cover is not the shop''s photo';
    end if;
    raise notice 'PASS: seven, 10 to 15 articles each, owned, Pro, off the map, dressed';
end $$;
commit;

\echo ''
\echo '--- TEST 2: the street opens and lists them; a second seed keeps edits ---'
update products set sale_price = 7000
 where name = 'Pizza pepperoni'
   and org_id = (select id from orgs where slug = 'tony-pizza');
begin;
set local role anon;
do $$ begin
    if storefront_open('chinese-fu-restaurant') is null then
        raise exception 'FAIL: a showcase is closed to the public';
    end if;
    if not exists (select 1 from storefront_directory() where slug = 'ghana-restaurant') then
        raise exception 'FAIL: a showcase is not on the street';
    end if;
    if (select count(*) from showcase_slugs()) <> 7 then
        raise exception 'FAIL: showcase_slugs() does not name the seven';
    end if;
    if (select count(*) from storefront_products('rowan-bike-shop') where photo_key like 'showcase/%') <> 15 then
        raise exception 'FAIL: the bikes do not carry their photos';
    end if;
    raise notice 'PASS: open, on the street, named';
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '64646464-0000-0000-0000-000000000001';
do $$ begin
    if showcase_seed() <> 0 then
        raise exception 'FAIL: a second seed made stores again';
    end if;
    if (select sale_price from products where name = 'Pizza pepperoni'
          and org_id = (select id from orgs where slug = 'tony-pizza')) <> 7000 then
        raise exception 'FAIL: the second seed undid an edit';
    end if;
    raise notice 'PASS: a second seed makes nothing and keeps edits';
end $$;
commit;

\echo ''
\echo '--- TEST 3: nobody orders; no cauris ---'
-- As the database itself: the trigger stands whatever the path, the
-- storefront's place_order() or a direct insert.
do $$ begin
    begin
        insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency)
        values ((select id from orgs where slug = 'tony-pizza'),
                '64646464-0000-0000-0000-000000000003', 'Client', 'pending', 'pickup', 6500, 'XOF');
        raise exception 'FAIL: an order reached a showcase';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like 'Pas à proximité%' then
            raise exception 'FAIL: the refusal does not say « Pas à proximité » — %', sqlerrm;
        end if;
    end;
    raise notice 'PASS: the order is refused, « Pas à proximité »';
end $$;
insert into cauris_ledger (org_id, delta, reason, ref)
values ((select id from orgs where slug = 'jersey-bakery'), 50, 'order', 'x');
do $$ begin
    if exists (select 1 from cauris_ledger l join orgs o on o.id = l.org_id where o.showcase) then
        raise exception 'FAIL: a showcase earned cauris';
    end if;
    raise notice 'PASS: no cauris for a showcase';
end $$;

\echo ''
\echo '--- TEST 4: another admin takes the keys; hiding takes it off the street ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '64646464-0000-0000-0000-000000000002';
do $$
declare v_org uuid := (select id from orgs where slug = 'bob-electronics');
begin
    if (select managing from showcase_list() where slug = 'bob-electronics') then
        raise exception 'FAIL: the second admin already manages it';
    end if;
    perform showcase_join(v_org);
    perform showcase_join(v_org);
    if (select count(*) from memberships where org_id = v_org
          and user_id = '64646464-0000-0000-0000-000000000002') <> 1 then
        raise exception 'FAIL: joining did not make exactly one membership';
    end if;
    perform set_showcase_visible(v_org, false);
    raise notice 'PASS: joined once, hidden';
end $$;
commit;
begin;
set local role anon;
do $$ begin
    if storefront_open('bob-electronics') is not null
       or exists (select 1 from showcase_slugs() s where s = 'bob-electronics') then
        raise exception 'FAIL: a hidden showcase is still on the street';
    end if;
    raise notice 'PASS: off the street';
end $$;
commit;

\echo ''
\echo '--- TEST 5: closed to a shopkeeper and to anon ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '64646464-0000-0000-0000-000000000003';
do $$
declare v_case text;
begin
    foreach v_case in array array[
        'select showcase_seed()',
        'select * from showcase_list()',
        'select showcase_join((select id from orgs where slug = ''tony-pizza''))',
        'select set_showcase_visible((select id from orgs where slug = ''tony-pizza''), false)'
    ] loop
        begin
            execute v_case;
            raise exception 'FAIL: a shopkeeper ran %', v_case;
        exception when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
        end;
    end loop;
    raise notice 'PASS: four refusals for a shopkeeper';
end $$;
commit;
do $$ begin
    if has_function_privilege('anon', 'showcase_seed()', 'execute')
       or has_function_privilege('anon', 'showcase_list()', 'execute')
       or has_function_privilege('anon', 'showcase_join(uuid)', 'execute')
       or not has_function_privilege('anon', 'showcase_slugs()', 'execute') then
        raise exception 'FAIL: anon''s grants are wrong';
    end if;
    raise notice 'PASS: anon may only read the slugs';
end $$;

\echo ''
\echo 'test_showcase: all passed'
