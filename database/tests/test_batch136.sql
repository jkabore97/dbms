-- ============================================================
-- test_batch136.sql — batch 141 (136): descriptions, a service's duration,
-- and several photos per item.
--
-- The claims:
--   * the description holds 1,000 characters, not 1,001;
--   * the duration backfill reads what the service flow wrote (« 1 h »,
--     « une demi-journée », « 45 min » typed), empties the description only
--     when it is exactly « Durée : … », keeps what it cannot read and
--     every article's words; twice, the same;
--   * the photo limits: Basic the cover alone (the 2nd refused in French,
--     by the door and by a direct write); Mara Pro up to
--     max_item_photos_pro (5), the 6th refused; the setting 1 to 20, a
--     6th allowed at 6; a business back on Basic shows its cover alone and
--     keeps the rest;
--   * order and delete: « Mettre en premier » makes the cover of the
--     vitrine, the search, the previews and the Articles page; a wrong
--     order refused; a photo removed is unfiled and the next is the cover;
--     the last removed, no photo comes back; a photo filed by an older
--     path replaces the cover;
--   * the street: storefront_products' photo_keys in order (anon), only for
--     a published item, each served by the photo gate; an item with no
--     gallery reads as before (photo_keys its one photo);
--   * RLS and the cross-business guard: a stranger reads and writes
--     nothing, anon nothing at all; a photo of another business refused by
--     the door and by 127's guard;
--   * the three kinds: a shop, a farm (its units) and an association;
--   * grants: the doors invoker, the helpers pinned and closed to anon,
--     storefront_products open to anon; run twice, the same.
-- ============================================================
\set ON_ERROR_STOP on

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
grant usage on schema auth to authenticated;
-- Earlier suites re-apply older migrations (131's storefront functions,
-- 100's thumbnails) and hand the app's roles every function: 136 again.
\i database/migrations/136_item_photos.sql
revoke all on product_photos from anon;

update platform_settings set value = '5' where key = 'max_item_photos_pro';
update platform_settings set value = '1'
 where key in ('vitrine_min_items', 'vitrine_min_items_association');

insert into auth.users (id, phone, raw_user_meta_data) values
    ('13613613-0000-0000-0000-000000000001', '+22613600001', '{"full_name": "Gérante Maison Élégance 136"}'),
    ('13613613-0000-0000-0000-000000000002', '+22613600002', '{"full_name": "Gérant Le Comptoir Doré 136"}'),
    ('13613613-0000-0000-0000-000000000003', '+22613600003', '{"full_name": "Étranger 136"}'),
    ('13613613-0000-0000-0000-000000000004', '+22613600004', '{"full_name": "Trésorière Cercle des Bâtisseurs 136"}');

insert into orgs (id, name, slug, profile, default_currency, plan, plan_until, storefront_enabled, storefront_blurb, phone) values
    ('13600000-0000-0000-0000-0000000000a1', 'Maison Élégance', 'pro-136',      'retail',      'XOF', 'pro',  '2099-01-01', true, 'Bienvenue', '+22670136001'),
    ('13600000-0000-0000-0000-0000000000a2', 'Le Comptoir Doré', 'basic-136',    'retail',      'XOF', 'free', null,         true, 'Bienvenue', '+22670136002'),
    ('13600000-0000-0000-0000-0000000000a3', 'Ferme Horizon Vert', 'ferme-136',    'farm',        'XOF', 'pro',  '2099-01-01', true, 'Bienvenue', '+22670136003'),
    ('13600000-0000-0000-0000-0000000000a4', 'Cercle des Bâtisseurs', 'entraide-136', 'association', 'XOF', 'free', null,         true, 'Bienvenue', '+22670136004');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    ('13600000-0000-0000-0000-0000000000a1', '13613613-0000-0000-0000-000000000001', 'owner', 'org', '13600000-0000-0000-0000-0000000000a1', 'full'),
    ('13600000-0000-0000-0000-0000000000a3', '13613613-0000-0000-0000-000000000001', 'owner', 'org', '13600000-0000-0000-0000-0000000000a3', 'full'),
    ('13600000-0000-0000-0000-0000000000a2', '13613613-0000-0000-0000-000000000002', 'owner', 'org', '13600000-0000-0000-0000-0000000000a2', 'full'),
    ('13600000-0000-0000-0000-0000000000a4', '13613613-0000-0000-0000-000000000004', 'owner', 'org', '13600000-0000-0000-0000-0000000000a4', 'full');

insert into products (id, org_id, name, sale_price, cost_price, quantity, unit, is_active, is_published) values
    ('136aaaaa-0000-0000-0000-000000000001', '13600000-0000-0000-0000-0000000000a1', 'Pagne 136',     5000, 3000, 10, null,      true, true),
    ('136aaaaa-0000-0000-0000-000000000002', '13600000-0000-0000-0000-0000000000a2', 'Savon 136',      500,  300, 50, null,      true, true),
    ('136aaaaa-0000-0000-0000-000000000003', '13600000-0000-0000-0000-0000000000a3', 'Poulets 136',   3500,    0, 40, 'tête',    true, true),
    ('136aaaaa-0000-0000-0000-000000000004', '13600000-0000-0000-0000-0000000000a4', 'Livre 136',     2000,    0,  5, null,      true, true),
    -- On the Pro shop, not on the vitrine.
    ('136aaaaa-0000-0000-0000-000000000005', '13600000-0000-0000-0000-0000000000a1', 'Caché 136',     1000,  500,  5, null,      true, false),
    -- On the Pro shop, on the vitrine, never photographed twice.
    ('136aaaaa-0000-0000-0000-000000000006', '13600000-0000-0000-0000-0000000000a1', 'Sac 136',       2500, 1500,  5, null,      true, true);

-- The photographs (documents, as the uploads Worker records them), oldest
-- first: each item's own, and photos waiting in Photos (no item).
insert into documents (id, org_id, r2_key, kind, content_type, uploaded_by, product_id, captured_at)
select ('136d0000-0000-0000-0000-0000000000' || t)::uuid, o::uuid,
       'org/' || o || '/p136-' || t || '.jpg', 'product_photo', 'image/jpeg',
       u::uuid, p::uuid, now() - (100 - n) * interval '1 minute'
  from (values
    -- Pro shop: the Pagne's photo (its cover), five waiting.
    (1,  '01', '13600000-0000-0000-0000-0000000000a1', '13613613-0000-0000-0000-000000000001', '136aaaaa-0000-0000-0000-000000000001'),
    (2,  '02', '13600000-0000-0000-0000-0000000000a1', '13613613-0000-0000-0000-000000000001', null),
    (3,  '03', '13600000-0000-0000-0000-0000000000a1', '13613613-0000-0000-0000-000000000001', null),
    (4,  '04', '13600000-0000-0000-0000-0000000000a1', '13613613-0000-0000-0000-000000000001', null),
    (5,  '05', '13600000-0000-0000-0000-0000000000a1', '13613613-0000-0000-0000-000000000001', null),
    (6,  '06', '13600000-0000-0000-0000-0000000000a1', '13613613-0000-0000-0000-000000000001', null),
    -- Basic shop: the Savon's photo, one waiting.
    (7,  '07', '13600000-0000-0000-0000-0000000000a2', '13613613-0000-0000-0000-000000000002', '136aaaaa-0000-0000-0000-000000000002'),
    (8,  '08', '13600000-0000-0000-0000-0000000000a2', '13613613-0000-0000-0000-000000000002', null),
    -- Farm: the Poulets' photo, two waiting.
    (9,  '09', '13600000-0000-0000-0000-0000000000a3', '13613613-0000-0000-0000-000000000001', '136aaaaa-0000-0000-0000-000000000003'),
    (10, '10', '13600000-0000-0000-0000-0000000000a3', '13613613-0000-0000-0000-000000000001', null),
    (11, '11', '13600000-0000-0000-0000-0000000000a3', '13613613-0000-0000-0000-000000000001', null),
    -- Association: the Livre's photo, one waiting.
    (12, '12', '13600000-0000-0000-0000-0000000000a4', '13613613-0000-0000-0000-000000000004', '136aaaaa-0000-0000-0000-000000000004'),
    (13, '13', '13600000-0000-0000-0000-0000000000a4', '13613613-0000-0000-0000-000000000004', null),
    -- Pro shop: the hidden item's photo, one waiting for it, the Sac's photo.
    (14, '14', '13600000-0000-0000-0000-0000000000a1', '13613613-0000-0000-0000-000000000001', '136aaaaa-0000-0000-0000-000000000005'),
    (15, '15', '13600000-0000-0000-0000-0000000000a1', '13613613-0000-0000-0000-000000000001', null),
    (16, '16', '13600000-0000-0000-0000-0000000000a1', '13613613-0000-0000-0000-000000000001', '136aaaaa-0000-0000-0000-000000000006'),
    -- Pro shop: one more waiting (the 6th), one for the old path.
    (17, '17', '13600000-0000-0000-0000-0000000000a1', '13613613-0000-0000-0000-000000000001', null),
    (18, '18', '13600000-0000-0000-0000-0000000000a1', '13613613-0000-0000-0000-000000000001', null)
  ) v(n, t, o, u, p);

-- A call as a person, taken back: '(went through)' or the refusal's words.
create or replace function pg_temp.try136(p_who uuid, p_sql text, p_role text default 'authenticated')
returns text
language plpgsql
as $$
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true);
    begin
        execute format('set local role %I', p_role);
        execute p_sql;
        raise exception using errcode = 'P0136', message = 'taken back';
    exception
        when sqlstate 'P0136' then
            execute 'reset role';
            return '(went through)';
        when others then
            execute 'reset role';
            return sqlerrm;
    end;
end;
$$;

-- The same call, kept: its answer as text.
create or replace function pg_temp.do136(p_who uuid, p_sql text, p_role text default 'authenticated')
returns text
language plpgsql
as $$
declare v text;
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true);
    execute format('set local role %I', p_role);
    execute p_sql into v;
    execute 'reset role';
    return v;
end;
$$;

-- The key of photo n.
create or replace function pg_temp.k136(n int) returns text language sql as $$
    select r2_key from documents where id = ('136d0000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid;
$$;
create or replace function pg_temp.d136(n int) returns uuid language sql as $$
    select ('136d0000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid;
$$;

-- The street's photos of an item, as anon reads them.
create or replace function pg_temp.street136(p_slug text, p_item uuid) returns text[]
language plpgsql as $$
declare v text[];
begin
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    select x.photo_keys into v from storefront_products(p_slug) x where x.id = p_item;
    execute 'reset role';
    return v;
end;
$$;

\echo ''
\echo '--- TEST 1: the description holds 1,000 characters ---'
do $$
begin
    update products set description = repeat('a', 1000) where id = '136aaaaa-0000-0000-0000-000000000006';
    begin
        update products set description = repeat('a', 1001) where id = '136aaaaa-0000-0000-0000-000000000006';
        raise exception 'FAIL: 1,001 characters taken';
    exception when check_violation then null;
    end;
    update products set description = null where id = '136aaaaa-0000-0000-0000-000000000006';
    raise notice 'PASS: 1,000 characters kept, 1,001 refused';
end $$;

\echo ''
\echo '--- TEST 2: the duration backfill reads what the service flow wrote ---'
insert into products (id, org_id, name, sale_price, is_service, is_active, is_published, description) values
    ('136bbbbb-0000-0000-0000-000000000001', '13600000-0000-0000-0000-0000000000a1', 'Coupe 136',     3000, true, true, true, 'Durée : 1 h'),
    ('136bbbbb-0000-0000-0000-000000000002', '13600000-0000-0000-0000-0000000000a1', 'Tresses 136',   8000, true, true, true, 'Durée : une demi-journée'),
    ('136bbbbb-0000-0000-0000-000000000003', '13600000-0000-0000-0000-0000000000a1', 'Coiffage 136',  2000, true, true, true, E'Durée : 45 min\nShampoing compris'),
    ('136bbbbb-0000-0000-0000-000000000004', '13600000-0000-0000-0000-0000000000a1', 'Cours 136',     5000, true, true, true, 'Durée : 3 séances'),
    ('136bbbbb-0000-0000-0000-000000000005', '13600000-0000-0000-0000-0000000000a3', 'Visite 136',    1000, true, true, true, 'Durée : 1 h 30'),
    ('136bbbbb-0000-0000-0000-000000000006', '13600000-0000-0000-0000-0000000000a4', 'Salle 136',    10000, true, true, true, 'Durée : une journée'),
    ('136bbbbb-0000-0000-0000-000000000007', '13600000-0000-0000-0000-0000000000a4', 'Atelier 136',   1500, true, true, true, 'Durée : 30 min');
-- An article that says it, untouched: the flow wrote it for services only.
update products set description = 'Durée : 1 h' where id = '136aaaaa-0000-0000-0000-000000000004';
\i database/migrations/136_item_photos.sql
revoke all on product_photos from anon;
do $$
declare r record; v_want jsonb := '{
    "136bbbbb-0000-0000-0000-000000000001": [60, null],
    "136bbbbb-0000-0000-0000-000000000002": [240, null],
    "136bbbbb-0000-0000-0000-000000000003": [45, "Durée : 45 min\nShampoing compris"],
    "136bbbbb-0000-0000-0000-000000000004": [null, "Durée : 3 séances"],
    "136bbbbb-0000-0000-0000-000000000005": [90, null],
    "136bbbbb-0000-0000-0000-000000000006": [480, null],
    "136bbbbb-0000-0000-0000-000000000007": [30, null],
    "136aaaaa-0000-0000-0000-000000000004": [null, "Durée : 1 h"]}';
begin
    for r in select id, duration_minutes, description from products
              where v_want ? id::text loop
        if coalesce(to_jsonb(r.duration_minutes), 'null') is distinct from v_want -> r.id::text -> 0
           or coalesce(to_jsonb(r.description), 'null') is distinct from v_want -> r.id::text -> 1 then
            raise exception 'FAIL: % reads % / %', r.id, r.duration_minutes, r.description;
        end if;
    end loop;
    if (select count(*) from products where v_want ? id::text) <> 8 then
        raise exception 'FAIL: rows missing';
    end if;
    raise notice 'PASS: « 1 h » 60, « une demi-journée » 240, « 1 h 30 » 90, « une journée » 480, « 30 min » 30 — the description emptied when it was exactly that; « 45 min » + words keeps the words; « 3 séances » kept as written; an article untouched (shop, farm, association)';
end $$;
-- The street reads the duration.
do $$
declare v int;
begin
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    select x.duration_minutes into v from storefront_products('pro-136') x
     where x.id = '136bbbbb-0000-0000-0000-000000000001';
    execute 'reset role';
    if v is distinct from 60 then
        raise exception 'FAIL: the street reads % minutes', v;
    end if;
    raise notice 'PASS: storefront_products gives anon the duration (60)';
end $$;

\echo ''
\echo '--- TEST 3: Basic — the cover alone ---'
do $$
declare v text; g jsonb;
begin
    v := pg_temp.try136('13613613-0000-0000-0000-000000000002',
        format('select product_photo_add(%L, %L)', '136aaaaa-0000-0000-0000-000000000002', pg_temp.d136(8)));
    if v not like 'Mara Pro : plusieurs photos par article%' then
        raise exception 'FAIL: a 2nd photo on Basic: %', v;
    end if;
    -- A direct write, past the door: the table's own limit.
    v := pg_temp.try136('13613613-0000-0000-0000-000000000002', format(
        'insert into product_photos (org_id, product_id, document_id, photo_key, position) values (%L, %L, %L, ''x'', 0), (%L, %L, %L, ''x'', 1)',
        '13600000-0000-0000-0000-0000000000a2', '136aaaaa-0000-0000-0000-000000000002', pg_temp.d136(7),
        '13600000-0000-0000-0000-0000000000a2', '136aaaaa-0000-0000-0000-000000000002', pg_temp.d136(7)));
    if v not like 'Mara Pro : plusieurs photos par article%' then
        raise exception 'FAIL: a direct 2nd row on Basic: %', v;
    end if;
    g := pg_temp.do136('13613613-0000-0000-0000-000000000002',
        format('select product_gallery(%L)::text', '136aaaaa-0000-0000-0000-000000000002'))::jsonb;
    if (g ->> 'limit')::int <> 1 or jsonb_array_length(g -> 'photos') <> 1
       or g -> 'photos' -> 0 ->> 'photo_key' <> pg_temp.k136(7) then
        raise exception 'FAIL: Basic gallery %', g;
    end if;
    if (select product_id from documents where id = pg_temp.d136(8)) is not null then
        raise exception 'FAIL: the refused photo was filed';
    end if;
    -- The association on Basic: the same.
    v := pg_temp.try136('13613613-0000-0000-0000-000000000004',
        format('select product_photo_add(%L, %L)', '136aaaaa-0000-0000-0000-000000000004', pg_temp.d136(13)));
    if v not like 'Mara Pro : plusieurs photos par article%' then
        raise exception 'FAIL: an association on Basic: %', v;
    end if;
    if pg_temp.street136('basic-136', '136aaaaa-0000-0000-0000-000000000002') <> array[pg_temp.k136(7)] then
        raise exception 'FAIL: the Basic item on the street';
    end if;
    raise notice 'PASS: Basic (a shop, an association) keeps one photo: the 2nd refused in French by the door and by a direct write, nothing filed; the gallery says 1';
end $$;

\echo ''
\echo '--- TEST 4: Mara Pro — up to max_item_photos_pro (5), the setting ---'
do $$
declare v text; g jsonb; i int;
begin
    for i in 2 .. 5 loop
        g := pg_temp.do136('13613613-0000-0000-0000-000000000001',
            format('select product_photo_add(%L, %L)::text', '136aaaaa-0000-0000-0000-000000000001', pg_temp.d136(i)))::jsonb;
    end loop;
    if (g ->> 'limit')::int <> 5 or jsonb_array_length(g -> 'photos') <> 5
       or g -> 'photos' -> 0 ->> 'photo_key' <> pg_temp.k136(1)
       or g -> 'photos' -> 4 ->> 'photo_key' <> pg_temp.k136(5) then
        raise exception 'FAIL: Pro gallery %', g;
    end if;
    -- The same photo again: answered, not doubled.
    g := pg_temp.do136('13613613-0000-0000-0000-000000000001',
        format('select product_photo_add(%L, %L)::text', '136aaaaa-0000-0000-0000-000000000001', pg_temp.d136(5)))::jsonb;
    if jsonb_array_length(g -> 'photos') <> 5 then
        raise exception 'FAIL: a retry doubled a photo';
    end if;
    v := pg_temp.try136('13613613-0000-0000-0000-000000000001',
        format('select product_photo_add(%L, %L)', '136aaaaa-0000-0000-0000-000000000001', pg_temp.d136(6)));
    if v <> 'Pas plus de 5 photos par article.' then
        raise exception 'FAIL: a 6th: %', v;
    end if;
    -- The setting: 1 to 20, whole.
    foreach v in array array['0', '21', '2.5', '"cinq"'] loop
        begin
            update platform_settings set value = v::jsonb where key = 'max_item_photos_pro';
            raise exception 'FAIL: max_item_photos_pro took %', v;
        exception when raise_exception then
            if sqlerrm like 'FAIL%' then raise; end if;
        end;
    end loop;
    update platform_settings set value = '6' where key = 'max_item_photos_pro';
    v := pg_temp.try136('13613613-0000-0000-0000-000000000001',
        format('select product_photo_add(%L, %L)', '136aaaaa-0000-0000-0000-000000000001', pg_temp.d136(6)));
    if v <> '(went through)' then
        raise exception 'FAIL: a 6th at 6: %', v;
    end if;
    update platform_settings set value = '5' where key = 'max_item_photos_pro';
    if pg_temp.street136('pro-136', '136aaaaa-0000-0000-0000-000000000001')
       <> array[pg_temp.k136(1), pg_temp.k136(2), pg_temp.k136(3), pg_temp.k136(4), pg_temp.k136(5)] then
        raise exception 'FAIL: the street''s photos %', pg_temp.street136('pro-136', '136aaaaa-0000-0000-0000-000000000001');
    end if;
    -- Every one served by the photo gate (the uploads Worker's question).
    for i in 1 .. 5 loop
        if not storefront_photo_allowed(pg_temp.k136(i)) then
            raise exception 'FAIL: photo % not served', i;
        end if;
    end loop;
    raise notice 'PASS: Pro holds 5 photos, the cover first, the street reads them in order and the gate serves each; a retry is not doubled; the 6th refused; the setting refuses 0, 21, 2.5 and words, and at 6 a 6th goes in (taken back)';
end $$;

\echo ''
\echo '--- TEST 5: the order — « Mettre en premier » is the cover everywhere ---'
do $$
declare v text; g jsonb; c text; covers text[];
begin
    g := pg_temp.do136('13613613-0000-0000-0000-000000000001', format(
        'select product_photos_order(%L, array[%L, %L, %L, %L, %L]::uuid[])::text',
        '136aaaaa-0000-0000-0000-000000000001',
        pg_temp.d136(3), pg_temp.d136(1), pg_temp.d136(2), pg_temp.d136(4), pg_temp.d136(5)))::jsonb;
    if g -> 'photos' -> 0 ->> 'photo_key' <> pg_temp.k136(3)
       or g -> 'photos' -> 1 ->> 'photo_key' <> pg_temp.k136(1) then
        raise exception 'FAIL: reordered %', g;
    end if;
    if pg_temp.street136('pro-136', '136aaaaa-0000-0000-0000-000000000001')
       <> array[pg_temp.k136(3), pg_temp.k136(1), pg_temp.k136(2), pg_temp.k136(4), pg_temp.k136(5)] then
        raise exception 'FAIL: the street''s order';
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    select array[
        (select x.photo_key from storefront_products('pro-136') x where x.id = '136aaaaa-0000-0000-0000-000000000001'),
        (select x.photo_key from search_products('pagne 136') x where x.id = '136aaaaa-0000-0000-0000-000000000001'),
        (select x.photo_key from storefront_previews(array['pro-136']) x where x.product_id = '136aaaaa-0000-0000-0000-000000000001')]
      into covers;
    execute 'reset role';
    if covers <> array[pg_temp.k136(3), pg_temp.k136(3), pg_temp.k136(3)] then
        raise exception 'FAIL: the street''s covers %', covers;
    end if;
    update products set featured_until = now() + interval '1 day' where id = '136aaaaa-0000-0000-0000-000000000001';
    select x.photo_key into c from storefront_featured() x where x.id = '136aaaaa-0000-0000-0000-000000000001';
    if c <> pg_temp.k136(3) then raise exception 'FAIL: À la une''s cover %', c; end if;
    update products set featured_until = null where id = '136aaaaa-0000-0000-0000-000000000001';
    c := pg_temp.do136('13613613-0000-0000-0000-000000000001', format(
        'select photo_key from product_photo_keys(%L) where product_id = %L',
        '13600000-0000-0000-0000-0000000000a1', '136aaaaa-0000-0000-0000-000000000001'));
    if c <> pg_temp.k136(3) then raise exception 'FAIL: the Articles page''s cover %', c; end if;
    -- An order that is not every photo once.
    foreach v in array array[
        format('array[%L, %L]::uuid[]', pg_temp.d136(1), pg_temp.d136(2)),
        format('array[%L, %L, %L, %L, %L]::uuid[]', pg_temp.d136(1), pg_temp.d136(1), pg_temp.d136(2), pg_temp.d136(4), pg_temp.d136(5)),
        format('array[%L, %L, %L, %L, %L]::uuid[]', pg_temp.d136(1), pg_temp.d136(7), pg_temp.d136(2), pg_temp.d136(4), pg_temp.d136(5))] loop
        if pg_temp.try136('13613613-0000-0000-0000-000000000001', format(
               'select product_photos_order(%L, %s)', '136aaaaa-0000-0000-0000-000000000001', v))
           <> 'L''ordre ne correspond pas aux photos de l''article.' then
            raise exception 'FAIL: a wrong order taken: %', v;
        end if;
    end loop;
    -- Basic: a single photo is already first.
    if pg_temp.try136('13613613-0000-0000-0000-000000000002', format(
           'select product_photos_order(%L, array[%L]::uuid[])', '136aaaaa-0000-0000-0000-000000000002', pg_temp.d136(7)))
       <> '(went through)' then
        raise exception 'FAIL: one photo''s order';
    end if;
    raise notice 'PASS: the 3rd photo put first is the cover of storefront_products, the search, the previews, À la une and the Articles page; the street reads the new order; an order missing, doubling or naming another photo refused';
end $$;

\echo ''
\echo '--- TEST 6: an older path replaces the cover; delete ---'
do $$
declare g jsonb;
begin
    -- « Changer la photo » in an app before 136: the photo filed on the item.
    perform pg_temp.do136('13613613-0000-0000-0000-000000000001', format(
        'select file_document(%L, null, null, null, %L)::text', pg_temp.d136(18), '136aaaaa-0000-0000-0000-000000000001'));
    g := pg_temp.do136('13613613-0000-0000-0000-000000000001',
        format('select product_gallery(%L)::text', '136aaaaa-0000-0000-0000-000000000001'))::jsonb;
    if g -> 'photos' -> 0 ->> 'photo_key' <> pg_temp.k136(18)
       or jsonb_array_length(g -> 'photos') <> 5
       or g -> 'photos' -> 1 ->> 'photo_key' <> pg_temp.k136(1) then
        raise exception 'FAIL: the older path %', g;
    end if;
    -- Delete the cover: the next is the cover, the photo stays, unfiled.
    g := pg_temp.do136('13613613-0000-0000-0000-000000000001', format(
        'select product_photo_remove(%L, %L)::text', '136aaaaa-0000-0000-0000-000000000001', pg_temp.d136(18)))::jsonb;
    if jsonb_array_length(g -> 'photos') <> 4 or g -> 'photos' -> 0 ->> 'photo_key' <> pg_temp.k136(1) then
        raise exception 'FAIL: after the delete %', g;
    end if;
    if (select product_id from documents where id = pg_temp.d136(18)) is not null
       or not exists (select 1 from documents where id = pg_temp.d136(18)) then
        raise exception 'FAIL: the removed photo is not in Photos, unfiled';
    end if;
    if (select array_agg(position order by position) from product_photos
         where product_id = '136aaaaa-0000-0000-0000-000000000001') <> array[0, 1, 2, 3] then
        raise exception 'FAIL: positions not from 0';
    end if;
    if pg_temp.street136('pro-136', '136aaaaa-0000-0000-0000-000000000001')
       <> array[pg_temp.k136(1), pg_temp.k136(2), pg_temp.k136(4), pg_temp.k136(5)] then
        raise exception 'FAIL: the street after the delete';
    end if;
    raise notice 'PASS: a photo filed by an older app replaces the cover in place; removed, it is unfiled (kept in Photos), the next is the cover, positions from 0';
end $$;

\echo ''
\echo '--- TEST 7: back on Basic — the cover alone on the street, the rest kept ---'
do $$
begin
    update orgs set plan = 'free', plan_until = null where id = '13600000-0000-0000-0000-0000000000a1';
    if pg_temp.street136('pro-136', '136aaaaa-0000-0000-0000-000000000001') <> array[pg_temp.k136(1)] then
        raise exception 'FAIL: Basic shows %', pg_temp.street136('pro-136', '136aaaaa-0000-0000-0000-000000000001');
    end if;
    if (select count(*) from product_photos where product_id = '136aaaaa-0000-0000-0000-000000000001') <> 4 then
        raise exception 'FAIL: photos lost on Basic';
    end if;
    update orgs set plan = 'pro', plan_until = '2099-01-01' where id = '13600000-0000-0000-0000-0000000000a1';
    if array_length(pg_temp.street136('pro-136', '136aaaaa-0000-0000-0000-000000000001'), 1) <> 4 then
        raise exception 'FAIL: Pro again';
    end if;
    raise notice 'PASS: on Basic the street shows the cover alone, the four kept; back on Pro, the four again';
end $$;

\echo ''
\echo '--- TEST 8: the street — a published item only; an item without a gallery reads as before ---'
do $$
declare g jsonb; v text[];
begin
    g := pg_temp.do136('13613613-0000-0000-0000-000000000001',
        format('select product_photo_add(%L, %L)::text', '136aaaaa-0000-0000-0000-000000000005', pg_temp.d136(15)))::jsonb;
    if jsonb_array_length(g -> 'photos') <> 2 then raise exception 'FAIL: hidden item gallery %', g; end if;
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    if exists (select 1 from storefront_products('pro-136') x where x.id = '136aaaaa-0000-0000-0000-000000000005') then
        raise exception 'FAIL: an unpublished item on the street';
    end if;
    execute 'reset role';
    if storefront_photo_allowed(pg_temp.k136(15)) then
        raise exception 'FAIL: an unpublished item''s photo served';
    end if;
    -- Published: served; unpublished again: not.
    update products set is_published = true where id = '136aaaaa-0000-0000-0000-000000000005';
    if not storefront_photo_allowed(pg_temp.k136(15))
       or pg_temp.street136('pro-136', '136aaaaa-0000-0000-0000-000000000005') <> array[pg_temp.k136(14), pg_temp.k136(15)] then
        raise exception 'FAIL: published, the photos';
    end if;
    update products set is_published = false where id = '136aaaaa-0000-0000-0000-000000000005';
    -- The Sac: one photo, no gallery — photo_key as before, photo_keys its one.
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    select array[x.photo_key] || x.photo_keys into v from storefront_products('pro-136') x
     where x.id = '136aaaaa-0000-0000-0000-000000000006';
    execute 'reset role';
    if v <> array[pg_temp.k136(16), pg_temp.k136(16)] then
        raise exception 'FAIL: an item without a gallery reads %', v;
    end if;
    if exists (select 1 from product_photos where product_id = '136aaaaa-0000-0000-0000-000000000006') then
        raise exception 'FAIL: a gallery made by reading';
    end if;
    raise notice 'PASS: an unpublished item''s photos are neither listed nor served, published they are; an item with one photo reads its newest photo, photo_keys that one, no row written';
end $$;

\echo ''
\echo '--- TEST 9: RLS — a stranger, anon ---'
do $$
declare v text; n int;
begin
    n := pg_temp.do136('13613613-0000-0000-0000-000000000003', 'select count(*)::text from product_photos')::int;
    if n <> 0 then raise exception 'FAIL: a stranger reads % rows', n; end if;
    n := pg_temp.do136('13613613-0000-0000-0000-000000000002', 'select count(*)::text from product_photos where org_id = ''13600000-0000-0000-0000-0000000000a1''')::int;
    if n <> 0 then raise exception 'FAIL: another owner reads % rows', n; end if;
    n := pg_temp.do136('13613613-0000-0000-0000-000000000001', 'select count(*)::text from product_photos where org_id = ''13600000-0000-0000-0000-0000000000a1''')::int;
    if n < 4 then raise exception 'FAIL: the owner reads % rows', n; end if;
    v := pg_temp.try136('13613613-0000-0000-0000-000000000003',
        format('select product_photo_add(%L, %L)', '136aaaaa-0000-0000-0000-000000000001', pg_temp.d136(6)));
    if v <> 'Article introuvable.' then raise exception 'FAIL: a stranger adds: %', v; end if;
    v := pg_temp.try136('13613613-0000-0000-0000-000000000003',
        format('select product_photo_remove(%L, %L)', '136aaaaa-0000-0000-0000-000000000001', pg_temp.d136(1)));
    if v <> 'Article introuvable.' then raise exception 'FAIL: a stranger removes: %', v; end if;
    v := pg_temp.try136('13613613-0000-0000-0000-000000000003',
        'delete from product_photos where org_id = ''13600000-0000-0000-0000-0000000000a1''');
    if (select count(*) from product_photos where org_id = '13600000-0000-0000-0000-0000000000a1') < 4 then
        raise exception 'FAIL: a stranger deleted rows';
    end if;
    v := pg_temp.try136('13613613-0000-0000-0000-000000000003', format(
        'update product_photos set position = 9 where product_id = %L', '136aaaaa-0000-0000-0000-000000000001'));
    if exists (select 1 from product_photos where position = 9) then
        raise exception 'FAIL: a stranger moved a photo';
    end if;
    v := pg_temp.try136(null, 'select count(*) from product_photos', 'anon');
    if v not like 'permission denied%' then raise exception 'FAIL: anon reads the table: %', v; end if;
    foreach v in array array['product_gallery(uuid)', 'product_photo_add(uuid, uuid)',
                             'product_photos_order(uuid, uuid[])', 'product_photo_remove(uuid, uuid)',
                             'item_photo_limit(uuid)', 'item_gallery_keys(uuid, uuid)', 'product_cover_key(uuid)',
                             'duration_minutes_of(text)'] loop
        if has_function_privilege('anon', v, 'execute') then
            raise exception 'FAIL: anon may run %', v;
        end if;
    end loop;
    if not has_function_privilege('anon', 'storefront_products(text)', 'execute') then
        raise exception 'FAIL: the street cannot read the shelf';
    end if;
    raise notice 'PASS: a stranger and another business read no row and add, remove, move or delete nothing; anon has neither the table nor a door, only storefront_products';
end $$;

\echo ''
\echo '--- TEST 10: the cross-business guard (127) ---'
do $$
declare v text;
begin
    -- The first owner owns the Pro shop and the farm: a shop's photo onto a farm item.
    v := pg_temp.try136('13613613-0000-0000-0000-000000000001',
        format('select product_photo_add(%L, %L)', '136aaaaa-0000-0000-0000-000000000003', pg_temp.d136(6)));
    if v <> 'Photo introuvable.' then raise exception 'FAIL: another business''s photo by the door: %', v; end if;
    -- Past the door: a row naming the shop's business, the farm's item.
    v := pg_temp.try136('13613613-0000-0000-0000-000000000001', format(
        'insert into product_photos (org_id, product_id, document_id, photo_key, position) values (%L, %L, %L, ''x'', 3)',
        '13600000-0000-0000-0000-0000000000a1', '136aaaaa-0000-0000-0000-000000000003', pg_temp.d136(9)));
    if v not in ('Cette fiche renvoie à une autre entreprise', 'Cette photo n''est pas une photo de cet article.') then
        raise exception 'FAIL: a row across businesses: %', v;
    end if;
    -- A row naming a photo that is not the item's.
    v := pg_temp.try136('13613613-0000-0000-0000-000000000001', format(
        'insert into product_photos (org_id, product_id, document_id, photo_key, position) values (%L, %L, %L, ''x'', 3)',
        '13600000-0000-0000-0000-0000000000a1', '136aaaaa-0000-0000-0000-000000000001', pg_temp.d136(6)));
    if v <> 'Cette photo n''est pas une photo de cet article.' then
        raise exception 'FAIL: an unfiled photo by a direct write: %', v;
    end if;
    -- A photo another item wears.
    v := pg_temp.try136('13613613-0000-0000-0000-000000000001',
        format('select product_photo_add(%L, %L)', '136aaaaa-0000-0000-0000-000000000001', pg_temp.d136(16)));
    if v <> 'Cette photo est déjà sur un autre article.' then
        raise exception 'FAIL: another item''s photo: %', v;
    end if;
    if not exists (select 1 from pg_trigger where tgrelid = 'product_photos'::regclass and tgname = 'same_org') then
        raise exception 'FAIL: no same_org guard';
    end if;
    raise notice 'PASS: another business''s photo refused by the door and a row across businesses by the table; a photo not the item''s or another item''s refused';
end $$;

\echo ''
\echo '--- TEST 11: the farm (its units) and the last photo removed ---'
do $$
declare g jsonb; r record;
begin
    g := pg_temp.do136('13613613-0000-0000-0000-000000000001',
        format('select product_photo_add(%L, %L)::text', '136aaaaa-0000-0000-0000-000000000003', pg_temp.d136(10)))::jsonb;
    g := pg_temp.do136('13613613-0000-0000-0000-000000000001',
        format('select product_photo_add(%L, %L)::text', '136aaaaa-0000-0000-0000-000000000003', pg_temp.d136(11)))::jsonb;
    if jsonb_array_length(g -> 'photos') <> 3 then raise exception 'FAIL: the farm %', g; end if;
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    select * into r from storefront_products('ferme-136') x where x.id = '136aaaaa-0000-0000-0000-000000000003';
    execute 'reset role';
    if r.unit <> 'tête' or r.photo_keys <> array[pg_temp.k136(9), pg_temp.k136(10), pg_temp.k136(11)] then
        raise exception 'FAIL: the farm on the street %', to_jsonb(r);
    end if;
    -- Every photo removed: no photo, none comes back.
    perform pg_temp.do136('13613613-0000-0000-0000-000000000001', format(
        'select product_photo_remove(%L, %L)::text', '136aaaaa-0000-0000-0000-000000000003', pg_temp.d136(9)));
    perform pg_temp.do136('13613613-0000-0000-0000-000000000001', format(
        'select product_photo_remove(%L, %L)::text', '136aaaaa-0000-0000-0000-000000000003', pg_temp.d136(10)));
    g := pg_temp.do136('13613613-0000-0000-0000-000000000001', format(
        'select product_photo_remove(%L, %L)::text', '136aaaaa-0000-0000-0000-000000000003', pg_temp.d136(11)))::jsonb;
    if jsonb_array_length(g -> 'photos') <> 0
       or pg_temp.street136('ferme-136', '136aaaaa-0000-0000-0000-000000000003') is not null then
        raise exception 'FAIL: the last photo removed %', g;
    end if;
    -- Removing a single photo with no gallery (Basic): the item has none.
    g := pg_temp.do136('13613613-0000-0000-0000-000000000004', format(
        'select product_photo_remove(%L, %L)::text', '136aaaaa-0000-0000-0000-000000000004', pg_temp.d136(12)))::jsonb;
    if jsonb_array_length(g -> 'photos') <> 0
       or pg_temp.street136('entraide-136', '136aaaaa-0000-0000-0000-000000000004') is not null then
        raise exception 'FAIL: the association''s single photo removed %', g;
    end if;
    raise notice 'PASS: the farm''s item by the head holds 3 photos and the street reads them with its unit; every photo removed, the item has none (the association''s single photo too)';
end $$;

\echo ''
\echo '--- TEST 12: the doors invoker, the helpers pinned and closed ---'
do $$
declare f text;
begin
    foreach f in array array['product_gallery(uuid)', 'product_photo_add(uuid, uuid)',
                             'product_photos_order(uuid, uuid[])', 'product_photo_remove(uuid, uuid)'] loop
        if (select prosecdef from pg_proc where oid = f::regprocedure) then
            raise exception 'FAIL: % is a definer', f;
        end if;
        if not has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: the app cannot run %', f;
        end if;
    end loop;
    foreach f in array array['item_photo_limit(uuid)', 'item_gallery_keys(uuid, uuid)', 'product_cover_key(uuid)',
                             'trg_product_photos_check()', 'trg_product_photos_limit()', 'trg_documents_gallery()',
                             'storefront_products(text)'] loop
        if not (select prosecdef and proconfig is not null from pg_proc where oid = f::regprocedure) then
            raise exception 'FAIL: % is not a pinned definer', f;
        end if;
    end loop;
    foreach f in array array['item_gallery_keys(uuid, uuid)', 'product_cover_key(uuid)',
                             'trg_product_photos_check()', 'trg_product_photos_limit()', 'trg_documents_gallery()'] loop
        if has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: the app may run %', f;
        end if;
    end loop;
    if not (select relrowsecurity from pg_class where oid = 'product_photos'::regclass) then
        raise exception 'FAIL: no row security';
    end if;
    raise notice 'PASS: the four doors invoker and the app''s; the helpers and triggers pinned definers, the internal ones nobody''s; row security on';
end $$;

\echo ''
\echo '--- TEST 12b: a row moved onto another item counts there; paperwork is not a photo to remove ---'
do $$
declare v text; g jsonb;
begin
    begin
        -- The Basic shop: a 2nd item with its own gallery row, and the Savon
        -- with a gallery and an older photo filed on it, outside it.
        insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published) values
            ('136aaaaa-0000-0000-0000-000000000009', '13600000-0000-0000-0000-0000000000a2', 'Bougie 136', 800, 400, 5, true, true);
        insert into documents (id, org_id, r2_key, kind, content_type, uploaded_by, product_id, captured_at) values
            ('136d0000-0000-0000-0000-000000000091', '13600000-0000-0000-0000-0000000000a2', 'org/13600000-0000-0000-0000-0000000000a2/p136-91.jpg',
             'product_photo', 'image/jpeg', '13613613-0000-0000-0000-000000000002', '136aaaaa-0000-0000-0000-000000000009', now()),
            ('136d0000-0000-0000-0000-000000000092', '13600000-0000-0000-0000-0000000000a2', 'org/13600000-0000-0000-0000-0000000000a2/p136-92.jpg',
             'product_photo', 'image/jpeg', '13613613-0000-0000-0000-000000000002', '136aaaaa-0000-0000-0000-000000000002', now());
        insert into product_photos (org_id, product_id, document_id, photo_key, position) values
            ('13600000-0000-0000-0000-0000000000a2', '136aaaaa-0000-0000-0000-000000000009', '136d0000-0000-0000-0000-000000000091', 'x', 0),
            ('13600000-0000-0000-0000-0000000000a2', '136aaaaa-0000-0000-0000-000000000002', '136d0000-0000-0000-0000-000000000092', 'x', 0);
        -- A direct update moving the Bougie's row onto the Savon, past the door.
        v := pg_temp.try136('13613613-0000-0000-0000-000000000002', format(
            'update product_photos set product_id = %L, document_id = %L, position = 1 where product_id = %L',
            '136aaaaa-0000-0000-0000-000000000002', pg_temp.d136(7), '136aaaaa-0000-0000-0000-000000000009'));
        if v not like 'Mara Pro : plusieurs photos par article%' then
            raise exception 'FAIL: a row moved onto a Basic item that has its cover: %', v;
        end if;

        -- An invoice filed on the Bougie: not a photo to remove; nothing unfiled.
        insert into documents (id, org_id, r2_key, kind, content_type, uploaded_by, product_id) values
            ('136d0000-0000-0000-0000-000000000093', '13600000-0000-0000-0000-0000000000a2', 'org/13600000-0000-0000-0000-0000000000a2/f136-93.pdf',
             'invoice', 'application/pdf', '13613613-0000-0000-0000-000000000002', '136aaaaa-0000-0000-0000-000000000009');
        v := pg_temp.try136('13613613-0000-0000-0000-000000000002', format(
            'select product_photo_remove(%L, %L)', '136aaaaa-0000-0000-0000-000000000009', '136d0000-0000-0000-0000-000000000093'));
        if v <> 'Photo introuvable.' then
            raise exception 'FAIL: paperwork removed as a photo: %', v;
        end if;
        if (select count(*) from documents where product_id = '136aaaaa-0000-0000-0000-000000000009') <> 2 then
            raise exception 'FAIL: the invoice or the photo was unfiled';
        end if;

        -- An item without a gallery: an older photo off it leaves the one shown.
        delete from product_photos where product_id = '136aaaaa-0000-0000-0000-000000000009';
        insert into documents (id, org_id, r2_key, kind, content_type, uploaded_by, product_id, captured_at) values
            ('136d0000-0000-0000-0000-000000000094', '13600000-0000-0000-0000-0000000000a2', 'org/13600000-0000-0000-0000-0000000000a2/p136-94.jpg',
             'product_photo', 'image/jpeg', '13613613-0000-0000-0000-000000000002', '136aaaaa-0000-0000-0000-000000000009', now() - interval '1 day');
        g := pg_temp.do136('13613613-0000-0000-0000-000000000002', format(
            'select product_photo_remove(%L, %L)::text', '136aaaaa-0000-0000-0000-000000000009', '136d0000-0000-0000-0000-000000000094'))::jsonb;
        if g -> 'photos' -> 0 ->> 'document_id' <> '136d0000-0000-0000-0000-000000000091'
           or (select product_id from documents where id = '136d0000-0000-0000-0000-000000000091') is null then
            raise exception 'FAIL: an older photo removed took the cover with it: %', g;
        end if;
        -- The one shown removed: the item has no photo, the older ones too.
        insert into documents (id, org_id, r2_key, kind, content_type, uploaded_by, product_id, captured_at) values
            ('136d0000-0000-0000-0000-000000000095', '13600000-0000-0000-0000-0000000000a2', 'org/13600000-0000-0000-0000-0000000000a2/p136-95.jpg',
             'product_photo', 'image/jpeg', '13613613-0000-0000-0000-000000000002', '136aaaaa-0000-0000-0000-000000000009', now() - interval '2 days');
        g := pg_temp.do136('13613613-0000-0000-0000-000000000002', format(
            'select product_photo_remove(%L, %L)::text', '136aaaaa-0000-0000-0000-000000000009', '136d0000-0000-0000-0000-000000000091'))::jsonb;
        if jsonb_array_length(g -> 'photos') <> 0
           or (select count(*) from documents where product_id = '136aaaaa-0000-0000-0000-000000000009') <> 1 then
            raise exception 'FAIL: the cover removed, an older photo came back or the invoice went: %', g;
        end if;
        raise exception using errcode = 'P0137', message = 'taken back';
    exception when sqlstate 'P0137' then
        null;
    end;
    raise notice 'PASS: a row moved by a direct update onto a Basic item that has its cover refused; an invoice filed on an item is not a photo to remove (nothing unfiled); without a gallery an older photo off leaves the cover, the cover off leaves no photo and the paperwork';
end $$;

\echo ''
\echo '--- TEST 13: run twice, 136 changes nothing ---'
create temp table b136_seen as
    select 'photo ' || id as k, to_jsonb(p) as v from product_photos p
    union all select 'item ' || id, jsonb_build_array(duration_minutes, description) from products where id::text like '136%'
    union all select 'setting', value from platform_settings where key = 'max_item_photos_pro';
\i database/migrations/136_item_photos.sql
revoke all on product_photos from anon;
do $$ begin
    if exists (
        (select 'photo ' || id as k, to_jsonb(p) as v from product_photos p
         union all select 'item ' || id, jsonb_build_array(duration_minutes, description) from products where id::text like '136%'
         union all select 'setting', value from platform_settings where key = 'max_item_photos_pro')
        except select k, v from b136_seen)
       or (select count(*) from b136_seen) <> (select count(*) from product_photos)
            + (select count(*) from products where id::text like '136%') + 1 then
        raise exception 'FAIL: 136 again changed something';
    end if;
    raise notice 'PASS: run twice, the same';
end $$;

revoke usage on schema auth from authenticated;

\echo ''
\echo '=== test_batch136.sql: all claims hold ==='
