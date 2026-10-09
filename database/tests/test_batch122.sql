-- ============================================================
-- test_batch122.sql — a delivery reaches the couriers around it (122),
-- and the store links of the web's « download the app » pop-up.
--
-- The claims, for a shop, a farm and an association alike:
--   * courier_radius_km is seeded 10, on the Réglages board, changed
--     through platform_set_setting — a whole number of km from 1 to 100,
--     anything else refused in French — and journaled;
--   * the street's couriers told of a delivery are those whose last known
--     position is within the radius of the shop's pin — a position wins
--     over the declared city both ways (near in another city: told; far
--     in the same city: not); with no position, 115's city rule; with
--     neither, nobody; the shop's own couriers always, wherever they are;
--     after the shop's own minutes the same rule (deliveries_waiting);
--     50 at most;
--   * a wider radius reaches further;
--   * the board: what the bell says — the near see the street's delivery,
--     the far do not, the own always; the board keeps the position it is
--     given and reads it back when the phone gives none;
--   * a shop with no pin: 115's city rule, as before;
--   * app_store_links(): the APK until play_store_live, then Google Play;
--     the App Store from app_store_url once set (an https address, or
--     nothing — refused otherwise); readable by the signed-out street;
--   * the doors: courier_near and tell_couriers are no one's to call,
--     delivery_board a signed-in courier's, app_store_links the street's.
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
-- Earlier suites hand the app's roles every function and put back older
-- definitions (test_batch115 reruns 115, test_batch121 reruns 121): 122
-- again, so what follows is 122's own.
\i database/migrations/122_courier_radius.sql

\set mara    '''12212212-0000-0000-0000-000000000001'''
\set sowner  '''12212212-0000-0000-0000-000000000002'''
\set fowner  '''12212212-0000-0000-0000-000000000003'''
\set aowner  '''12212212-0000-0000-0000-000000000004'''
\set awa     '''12212212-0000-0000-0000-000000000005'''
\set near    '''12212212-0000-0000-0000-000000000006'''
\set far     '''12212212-0000-0000-0000-000000000007'''
\set cityc   '''12212212-0000-0000-0000-000000000008'''
\set nowhere '''12212212-0000-0000-0000-000000000009'''
\set own     '''12212212-0000-0000-0000-000000000010'''
\set shop    '''12200000-0000-0000-0000-000000000001'''
\set farm    '''12200000-0000-0000-0000-000000000002'''
\set assoc   '''12200000-0000-0000-0000-000000000003'''
\set nopin   '''12200000-0000-0000-0000-000000000004'''

insert into auth.users (id, phone, raw_user_meta_data) values
    (:mara,    '+22612201001', '{"full_name": "Mara Cent-Vingt-Deux"}'),
    (:sowner,  '+22612201002', '{"full_name": "Patronne 122"}'),
    (:fowner,  '+22612201003', '{"full_name": "Fermier 122"}'),
    (:aowner,  '+22612201004', '{"full_name": "Trésorière 122"}'),
    (:awa,     '+22612201005', '{"full_name": "Awa Cliente 122"}'),
    (:near,    '+22612201006', '{"full_name": "Livreur Proche"}'),
    (:far,     '+22612201007', '{"full_name": "Livreur Loin"}'),
    (:cityc,   '+22612201008', '{"full_name": "Livreur Ville"}'),
    (:nowhere, '+22612201009', '{"full_name": "Livreur Nulle Part"}'),
    (:own,     '+22612201010', '{"full_name": "Livreur Maison 122"}');
update profiles set is_platform_admin = true where id = :mara;
-- Three businesses on the same pin in Ouagadougou (a shop, a farm, an
-- association), and a shop in Ouagadougou with no pin.
insert into orgs (id, name, slug, profile, default_currency, plan, plan_until, storefront_enabled, city, lat, lng) values
    (:shop,  'Boutique 122', 'boutique-122', 'retail',      'XOF', 'pro', current_date + 30, true, 'Ouagadougou', 12.3714, -1.5197),
    (:farm,  'Ferme 122',    'ferme-122',    'farm',        'XOF', 'pro', current_date + 30, true, 'Ouagadougou', 12.3714, -1.5197),
    (:assoc, 'Entraide 122', 'entraide-122', 'association', 'XOF', 'pro', current_date + 30, true, 'Ouagadougou', 12.3714, -1.5197),
    (:nopin, 'Sans Pin 122', 'sanspin-122',  'retail',      'XOF', 'pro', current_date + 30, true, 'Ouagadougou', null, null);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :sowner, 'owner', 'org', :shop,  'full'),
    (:farm,  :fowner, 'owner', 'org', :farm,  'full'),
    (:assoc, :aowner, 'owner', 'org', :assoc, 'full'),
    (:nopin, :sowner, 'owner', 'org', :nopin, 'full');
-- Proche: 3 km away, declared in Bobo (the position wins). Loin: 30 km
-- away, declared in Ouagadougou (the position wins). Ville: no position,
-- Ouagadougou (115's rule). Nulle Part: neither. Maison: the shop's own,
-- 300 km away.
insert into couriers (user_id, phone, status, decided_at, last_lat, last_lng, last_seen_at) values
    (:near,    '+22612201006', 'approved', now() - interval '30 days', 12.3984, -1.5197, now()),
    (:far,     '+22612201007', 'approved', now() - interval '29 days', 12.6414, -1.5197, now()),
    (:cityc,   '+22612201008', 'approved', now() - interval '28 days', null, null, null),
    (:nowhere, '+22612201009', 'approved', now() - interval '27 days', null, null, null),
    (:own,     '+22612201010', 'approved', now() - interval '26 days', 11.1771, -4.2979, now());
insert into courier_applications (user_id, status, city) values
    (:near,  'approved', 'Bobo-Dioulasso'),
    (:far,   'approved', 'Ouagadougou'),
    (:cityc, 'approved', ' ouagadougou ');

create or replace function pg_temp.as122(p_who uuid)
returns void
language sql
as $$ select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true); $$;

create or replace function pg_temp.refused122(p_sql text)
returns text
language plpgsql
as $$
begin
    execute p_sql;
    return '(went through)';
exception when others then
    return sqlerrm;
end;
$$;

-- A delivery of Awa's at a business, made ready: the bell rings as 115's
-- trigger rings it.
create or replace function pg_temp.ready122(p_org uuid)
returns uuid
language plpgsql
as $$
declare v uuid;
begin
    insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency,
                        address, delivery_fee)
    values (p_org, '12212212-0000-0000-0000-000000000005', 'Awa Cliente 122', 'accepted', 'delivery',
            1500, 'XOF', 'Zogona', 500)
    returning id into v;
    update orders set status = 'ready' where id = v;
    return v;
end;
$$;

-- Who of the 122 couriers heard of an order, by name.
create or replace function pg_temp.told122(p_order uuid)
returns text
language sql
as $$
    select coalesce(string_agg(p.full_name, ', ' order by p.full_name), '')
      from notifications n join profiles p on p.id = n.recipient_id
     where n.kind = 'delivery_available' and n.params ->> 'order_id' = p_order::text
       and n.recipient_id::text like '12212212-%';
$$;

grant execute on function pg_temp.as122(uuid), pg_temp.refused122(text) to authenticated;

-- What the suites before this one left, put back at the end.
create temp table b122_kept as
    select key, value from platform_settings
     where key in ('courier_radius_km', 'play_store_live', 'app_store_url', 'own_courier_minutes');
update platform_settings set value = '10'    where key = 'courier_radius_km';
update platform_settings set value = 'false' where key = 'play_store_live';
update platform_settings set value = '""'    where key = 'app_store_url';
update platform_settings set value = '10'    where key = 'own_courier_minutes';

\echo ''
\echo '--- TEST 1: the radius is seeded 10, on Réglages, 1 to 100 km, journaled ---'
begin;
do $$
declare v_id uuid;
begin
    if (select value from b122_kept where key = 'courier_radius_km') is distinct from '10'::jsonb
       or (select value from b122_kept where key = 'play_store_live') is distinct from 'false'::jsonb
       or (select value from b122_kept where key = 'app_store_url') is distinct from '""'::jsonb then
        raise exception 'FAIL: 122 did not seed 10 km, Google Play off, no App Store';
    end if;
    perform pg_temp.as122('12212212-0000-0000-0000-000000000001');
    execute 'set local role authenticated';
    if not (platform_settings_board() ? 'courier_radius_km')
       or not (platform_settings_board() ? 'play_store_live')
       or not (platform_settings_board() ? 'app_store_url') then
        raise exception 'FAIL: the three 122 settings are not on the Réglages board';
    end if;
    if pg_temp.refused122($q$select platform_set_setting('courier_radius_km', '0')$q$)
           <> 'Un nombre de kilomètres de 1 à 100, s''il vous plaît.'
       or pg_temp.refused122($q$select platform_set_setting('courier_radius_km', '101')$q$)
           <> 'Un nombre de kilomètres de 1 à 100, s''il vous plaît.'
       or pg_temp.refused122($q$select platform_set_setting('courier_radius_km', '12.5')$q$)
           <> 'Un nombre entier, s''il vous plaît.'
       or pg_temp.refused122($q$select platform_set_setting('courier_radius_km', '"dix"')$q$)
           <> 'Ce réglage attend un nombre.' then
        raise exception 'FAIL: a radius out of 1–100, a decimal or a word went through';
    end if;
    v_id := platform_set_setting('courier_radius_km', '25');
    execute 'reset role';
    if v_id is null or (select value from platform_settings where key = 'courier_radius_km') <> '25'::jsonb then
        raise exception 'FAIL: 25 km was not kept and journaled';
    end if;
    raise notice 'PASS: courier_radius_km on Réglages; 0, 101, 12.5 and a word refused in French; 25 kept and journaled';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: the bell — the near (by position, any city), the city without position, the own always; a shop, a farm, an association ---'
begin;
do $$
declare v_org uuid; v_order uuid; v_told text;
begin
    insert into org_couriers (org_id, user_id)
    select o, '12212212-0000-0000-0000-000000000010'
      from unnest(array['12200000-0000-0000-0000-000000000001',
                        '12200000-0000-0000-0000-000000000002',
                        '12200000-0000-0000-0000-000000000003']::uuid[]) o;
    foreach v_org in array array['12200000-0000-0000-0000-000000000001',
                                 '12200000-0000-0000-0000-000000000002',
                                 '12200000-0000-0000-0000-000000000003']::uuid[] loop
        -- At ready: the shop's own courier, 300 km away, at once and alone.
        v_order := pg_temp.ready122(v_org);
        v_told := pg_temp.told122(v_order);
        if v_told <> 'Livreur Maison 122' then
            raise exception 'FAIL: % at ready told « % »', v_org, v_told;
        end if;
        -- The shop's minutes over: the street within 10 km — Proche (3 km,
        -- declared in Bobo) and Ville (no position, Ouagadougou); never
        -- Loin (30 km, declared in Ouagadougou), never Nulle Part.
        update order_events set at = now() - interval '11 minutes'
         where order_id = v_order and status = 'ready';
        perform deliveries_waiting();
        v_told := pg_temp.told122(v_order);
        if v_told <> 'Livreur Maison 122, Livreur Proche, Livreur Ville' then
            raise exception 'FAIL: % after the minutes told « % »', v_org, v_told;
        end if;
    end loop;
    raise notice 'PASS: own courier at once wherever he is; then the near by position (another city too), the city without position; never the far, never the one with neither — shop, farm, association';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: no own couriers — the street at once; a wider radius reaches further; a shop with no pin keeps 115''s city rule ---'
begin;
do $$
declare v_order uuid; v_told text;
begin
    v_order := pg_temp.ready122('12200000-0000-0000-0000-000000000001');
    v_told := pg_temp.told122(v_order);
    if v_told <> 'Livreur Proche, Livreur Ville' then
        raise exception 'FAIL: 10 km told « % »', v_told;
    end if;
    update platform_settings set value = '40' where key = 'courier_radius_km';
    v_order := pg_temp.ready122('12200000-0000-0000-0000-000000000002');
    v_told := pg_temp.told122(v_order);
    if v_told <> 'Livreur Loin, Livreur Proche, Livreur Ville' then
        raise exception 'FAIL: 40 km told « % »', v_told;
    end if;
    -- No pin: the cities (Loin and Ville declared Ouagadougou), as in 115.
    v_order := pg_temp.ready122('12200000-0000-0000-0000-000000000004');
    v_told := pg_temp.told122(v_order);
    if v_told <> 'Livreur Loin, Livreur Ville' then
        raise exception 'FAIL: a shop with no pin told « % »', v_told;
    end if;
    -- A stored radius out of range (written behind the setter) is read 1–100.
    update platform_settings set value = '0' where key = 'courier_radius_km';
    if not courier_near('12212212-0000-0000-0000-000000000006', '12200000-0000-0000-0000-000000000003', 12.3714, -1.5197)
       or courier_near('12212212-0000-0000-0000-000000000006', '12200000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: a radius of 0 is not read as 1 km';
    end if;
    raise notice 'PASS: the street at once when the shop has no couriers (10 km); 40 km reaches Loin; no pin, the city rule; a stored 0 read as 1 km';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the board — the near see it, the far do not, the own always; the position kept and read back ---'
begin;
do $$
declare v_order uuid; v_own uuid;
begin
    v_order := pg_temp.ready122('12200000-0000-0000-0000-000000000003');
    insert into org_couriers (org_id, user_id)
    values ('12200000-0000-0000-0000-000000000002', '12212212-0000-0000-0000-000000000010');
    v_own := pg_temp.ready122('12200000-0000-0000-0000-000000000002');
    execute 'set local role authenticated';
    -- Loin, 30 km away by his stored position: nothing of the street.
    perform pg_temp.as122('12212212-0000-0000-0000-000000000007');
    if exists (select 1 from delivery_board() where order_id = v_order) then
        raise exception 'FAIL: Loin sees a delivery 30 km away';
    end if;
    -- Loin opens the board standing 2 km from the shop: he sees it, and
    -- the position is kept — the next board without one reads it.
    if not exists (select 1 from delivery_board(12.3894, -1.5197) where order_id = v_order) then
        raise exception 'FAIL: Loin standing near does not see it';
    end if;
    if not exists (select 1 from delivery_board() where order_id = v_order) then
        raise exception 'FAIL: the position given was not kept';
    end if;
    -- Nulle Part: no position, no city — nothing of the street.
    perform pg_temp.as122('12212212-0000-0000-0000-000000000009');
    if exists (select 1 from delivery_board() where order_id = v_order) then
        raise exception 'FAIL: a courier with neither position nor city sees the street';
    end if;
    -- Ville: no position, the shop's city.
    perform pg_temp.as122('12212212-0000-0000-0000-000000000008');
    if not exists (select 1 from delivery_board() where order_id = v_order) then
        raise exception 'FAIL: Ville (same city, no position) does not see it';
    end if;
    -- Maison, 300 km away: the farm's own delivery, first.
    perform pg_temp.as122('12212212-0000-0000-0000-000000000010');
    if (select order_id from delivery_board() limit 1) is distinct from v_own
       or exists (select 1 from delivery_board() where order_id = v_order) then
        raise exception 'FAIL: the own courier does not see his shop''s delivery first, or sees the far street';
    end if;
    execute 'reset role';
    if (select round(last_lat::numeric, 4) from couriers where user_id = '12212212-0000-0000-0000-000000000007') <> 12.3894
       or (select last_seen_at from couriers where user_id = '12212212-0000-0000-0000-000000000007') <> now() then
        raise exception 'FAIL: Loin''s position not stored';
    end if;
    raise notice 'PASS: the board — far hidden, near shown, neither hidden, city shown, own always and first; the position kept and read back';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: 50 at most, the near ---'
begin;
do $$
declare v_order uuid; i int; v_u uuid;
begin
    for i in 1..60 loop
        v_u := ('12212299-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid;
        insert into auth.users (id, phone, raw_user_meta_data)
        values (v_u, '+2261229' || lpad(i::text, 4, '0'), '{"full_name": "Livreur Foule 122"}');
        insert into couriers (user_id, phone, status, decided_at, last_lat, last_lng)
        values (v_u, '+2261229' || lpad(i::text, 4, '0'), 'approved', now(), 12.38, -1.52);
    end loop;
    v_order := pg_temp.ready122('12200000-0000-0000-0000-000000000001');
    if (select count(*) from notifications where kind = 'delivery_available'
                                             and params ->> 'order_id' = v_order::text) <> 50 then
        raise exception 'FAIL: % told, not 50', (select count(*) from notifications where kind = 'delivery_available'
                                                   and params ->> 'order_id' = v_order::text);
    end if;
    raise notice 'PASS: sixty near, fifty told';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: the store links — the APK, then Google Play; the App Store once set; the street reads them ---'
begin;
do $$
declare r jsonb;
begin
    execute 'set local role anon';
    r := app_store_links();
    execute 'reset role';
    if r ->> 'android' <> 'https://github.com/jkabore97/dbms/releases/latest/download/kaj-arm64-v8a.apk'
       or (r ->> 'android_store')::boolean or r ->> 'ios' is not null then
        raise exception 'FAIL: before the stores the links are %', r;
    end if;
    perform pg_temp.as122('12212212-0000-0000-0000-000000000001');
    execute 'set local role authenticated';
    perform platform_set_setting('play_store_live', 'true');
    if pg_temp.refused122($q$select platform_set_setting('app_store_url', '"http://apps.apple.com/app/id1"')$q$)
           <> 'Une adresse qui commence par https://, ou rien.'
       or pg_temp.refused122($q$select platform_set_setting('app_store_url', '"Mara"')$q$)
           <> 'Une adresse qui commence par https://, ou rien.' then
        raise exception 'FAIL: an App Store address that is not https went through';
    end if;
    perform platform_set_setting('app_store_url', '"  https://apps.apple.com/app/mara/id1234567890 "');
    execute 'reset role';
    execute 'set local role anon';
    r := app_store_links();
    execute 'reset role';
    if r ->> 'android' <> 'https://play.google.com/store/apps/details?id=bf.kaj.app'
       or not (r ->> 'android_store')::boolean
       or r ->> 'ios' <> 'https://apps.apple.com/app/mara/id1234567890' then
        raise exception 'FAIL: with the stores the links are %', r;
    end if;
    -- Emptied again: no App Store link.
    execute 'set local role authenticated';
    perform platform_set_setting('app_store_url', '""');
    execute 'reset role';
    if app_store_links() ->> 'ios' is not null then
        raise exception 'FAIL: an emptied App Store address still links';
    end if;
    raise notice 'PASS: the APK, then Google Play once live; the App Store from an https address (trimmed), nothing else accepted; the street reads them';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: the doors ---'
do $$
declare v_bad text;
begin
    select string_agg(f || ' ' || r, ', ') into v_bad
      from (values
              ('courier_near(uuid,uuid,double precision,double precision)', 'anon', false),
              ('courier_near(uuid,uuid,double precision,double precision)', 'authenticated', false),
              ('tell_couriers(uuid,boolean)', 'anon', false),
              ('tell_couriers(uuid,boolean)', 'authenticated', false),
              ('delivery_board(double precision,double precision)', 'anon', false),
              ('delivery_board(double precision,double precision)', 'authenticated', true),
              ('app_store_links()', 'anon', true),
              ('app_store_links()', 'authenticated', true),
              ('platform_set_setting(text,jsonb)', 'anon', false),
              ('platform_set_setting(text,jsonb)', 'authenticated', true)) t(f, r, ok)
     where has_function_privilege(r, f, 'execute') <> ok;
    if v_bad is not null then
        raise exception 'FAIL: the doors are wrong for %', v_bad;
    end if;
    if has_function_privilege('public', 'courier_near(uuid,uuid,double precision,double precision)', 'execute')
       or has_function_privilege('public', 'app_store_links()', 'execute') then
        raise exception 'FAIL: PUBLIC may call a 122 function';
    end if;
    -- A courier reads only their own position (056's policy).
    if not exists (select 1 from pg_policy where polrelid = 'couriers'::regclass
                                             and polname = 'a courier sees their own file') then
        raise exception 'FAIL: the couriers'' own-file policy is gone';
    end if;
    raise notice 'PASS: courier_near and tell_couriers closed; the board a signed-in courier''s; the links the street''s; the setter a signed-in caller''s (it checks the platform)';
end $$;

update platform_settings s set value = k.value from b122_kept k where k.key = s.key;
revoke usage on schema auth from authenticated;
