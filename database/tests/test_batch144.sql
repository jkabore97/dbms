-- ============================================================
-- test_batch144.sql — « Mettre en avant » by area (144, batch 148).
--
-- The claims, for a shop, a farm and an association alike:
--   * Dakar and Ouagadougou, 1 800 km apart, each hold spots_max_live (8)
--     running article spots at once, independently, through spot_settle;
--     the 9th in Dakar waits its turn (it starts when Dakar's first ends)
--     while Ouagadougou's 8th still starts at once; Ouagadougou's 9th,
--     approved by the platform (decide_promotion), waits too. The vitrine
--     spots are capped by area the same way (Dakar's 9th waits, Abidjan's
--     first does not). next_spot_start(kind, org) is what Wave's settle,
--     the weekly prize, the store and card settle and « Valider » call —
--     no function calls 071's one-argument door any more;
--   * a shopper near Dakar sees Dakar's spots only, in « À la une » and at
--     the top of the vitrines (storefront_featured, storefront_spotlights);
--     near Ouagadougou, Ouagadougou's only; in Abidjan, none of either; a
--     shopper with no location (signed out, or no saved pin, or a point
--     off the Earth) sees no spot at all; a signed-in shopper with no
--     point sent sees the spots around their saved delivery pin (« Maison »
--     first); the zero-argument doors an older app calls answer the same;
--     Mara's own pick stays for everyone;
--   * a business with no pin is refused, with « La position de ma
--     boutique » (de ma ferme, de mon association); spot_ineligible says
--     'position', so a payment that must make it a new spot is refused and
--     recorded; the sheet's spot_area_status says « not placed »;
--   * spot_area_status says the places free around a business this week,
--     and when the area is full the date the next one frees; the
--     business's admins' and the platform's alone;
--   * running and queued spots are untouched by installing 144 (run
--     again over them, every promotions row the same);
--   * spot_area_km in Réglages, 5 to 200 km, whole, journaled;
--   * the doors: the street's two new doors open to anon, the rest closed
--     to anon and PUBLIC, next_spot_start(text, uuid) and the helpers
--     closed to authenticated too; every search_path pinned; run twice.
--
-- Everything after the setup runs in one transaction rolled back, so the
-- spots the suites before this one left never count in an area here and
-- a second run is the same.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage on all sequences in schema public to authenticated;
-- The suites before this one re-ran older migrations: 144 again, twice.
\i database/migrations/144_spots_by_area.sql
\i database/migrations/144_spots_by_area.sql

begin;
update platform_settings set value = '0' where key in ('vitrine_min_items', 'vitrine_min_items_association');
update platform_settings set value = '8'  where key = 'spots_max_live';
update platform_settings set value = '30' where key = 'spot_area_km';
-- What the suites before left running elsewhere never counts here, nor
-- the picks they left « À la une ».
update promotions set status = 'cancelled' where status = 'approved' and ends_at > now();
update products set featured_until = null where featured_until > now();

create function pg_temp.as144(p_who uuid)
returns void
language sql
as $$
    select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true),
           set_config('request.jwt.claims',
                      case when p_who is null then '' else
                      json_build_object('sub', p_who, 'role', 'authenticated')::text end, true);
$$;

-- Asks a spot as the business's owner: the id, or the refusal's words.
create function pg_temp.ask144(p_owner uuid, p_org uuid, p_product uuid)
returns text
language plpgsql
as $$
declare v uuid;
begin
    perform pg_temp.as144(p_owner);
    execute 'set local role authenticated';
    v := request_promotion(p_org, p_product, 7);
    execute 'reset role';
    return v::text;
exception when others then
    execute 'reset role';
    return 'ERR: ' || sqlerrm;
end;
$$;

-- Asks and pays by card (the Worker's spot_settle): when it starts.
create function pg_temp.buy144(p_owner uuid, p_org uuid, p_product uuid, p_ref text)
returns timestamptz
language plpgsql
as $$
declare
    v_id text := pg_temp.ask144(p_owner, p_org, p_product);
    v_r  jsonb;
begin
    if v_id like 'ERR:%' then
        raise exception 'FAIL: % could not ask: %', p_ref, v_id;
    end if;
    v_r := spot_settle('stripe', 'cs_144_' || p_ref, v_id::uuid,
                       case when p_product is null then 'stripe:shop' else 'stripe:article' end,
                       5000, 'XOF', 'production');
    if not coalesce((v_r ->> 'granted')::boolean, false) then
        raise exception 'FAIL: % not programmed: %', p_ref, v_r;
    end if;
    return (v_r ->> 'starts_at')::timestamptz;
end;
$$;

-- The street as somebody sees it: the slugs of À la une and of the
-- spotlights, from a point, as anon or as a signed-in shopper.
create function pg_temp.featured144(p_who uuid, p_lat double precision, p_lng double precision,
                                    p_old boolean default false)
returns text
language plpgsql
as $$
declare v text;
begin
    perform pg_temp.as144(p_who);
    execute case when p_who is null then 'set local role anon' else 'set local role authenticated' end;
    if p_old then
        select coalesce(string_agg(shop_slug, ',' order by shop_slug), '') into v from storefront_featured();
    else
        select coalesce(string_agg(shop_slug, ',' order by shop_slug), '') into v
          from storefront_featured(p_lat, p_lng);
    end if;
    execute 'reset role';
    return v;
end;
$$;

create function pg_temp.lights144(p_who uuid, p_lat double precision, p_lng double precision,
                                  p_old boolean default false)
returns text
language plpgsql
as $$
declare v text;
begin
    perform pg_temp.as144(p_who);
    execute case when p_who is null then 'set local role anon' else 'set local role authenticated' end;
    if p_old then
        select coalesce(string_agg(slug, ',' order by slug), '') into v from storefront_spotlights();
    else
        select coalesce(string_agg(slug, ',' order by slug), '') into v
          from storefront_spotlights(p_lat, p_lng);
    end if;
    execute 'reset role';
    return v;
end;
$$;

create function pg_temp.status144(p_who uuid, p_org uuid, p_kind text)
returns jsonb
language plpgsql
as $$
declare v jsonb;
begin
    perform pg_temp.as144(p_who);
    execute 'set local role authenticated';
    v := spot_area_status(p_org, p_kind);
    execute 'reset role';
    return v;
exception when others then
    execute 'reset role';
    return jsonb_build_object('error', sqlerrm);
end;
$$;

grant execute on function pg_temp.as144(uuid) to anon, authenticated;

-- The people: one owner per city, a shopper with a pin in Dakar, a
-- shopper with an address but no pin, Mara.
insert into auth.users (id, phone, email, email_confirmed_at, raw_user_meta_data) values
    ('14414414-0000-0000-0000-000000000001', '+22114400001', 'dakar144@example.org',  now(), '{"full_name": "Boutiques Dakar 144"}'),
    ('14414414-0000-0000-0000-000000000002', '+22614400002', 'ouaga144@example.org',  now(), '{"full_name": "Boutiques Ouaga 144"}'),
    ('14414414-0000-0000-0000-000000000003', '+22514400003', 'abidjan144@example.org', now(), '{"full_name": "Vitrine Abidjan 144"}'),
    ('14414414-0000-0000-0000-000000000004', '+22314400004', 'bamako144@example.org', now(), '{"full_name": "Sans position 144"}'),
    ('14414414-0000-0000-0000-000000000005', '+22114400005', 'client144@example.org', now(), '{"full_name": "Cliente Dakar 144"}'),
    ('14414414-0000-0000-0000-000000000006', '+22614400006', 'nopin144@example.org',  now(), '{"full_name": "Client sans pin 144"}'),
    ('14414414-0000-0000-0000-000000000008', '+22614400008', 'mara144@example.org',   now(), '{"full_name": "Mara 144"}');
update profiles set is_platform_admin = true where id = '14414414-0000-0000-0000-000000000008';

-- Nine businesses in Dakar and nine in Ouagadougou, a few hundred metres
-- apart; one in Abidjan; three with no pin (Bamako: a shop, a farm, an
-- association). Shops, farms and associations mixed.
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, lat, lng)
select ('14400000-0000-0000-0001-' || lpad(i::text, 12, '0'))::uuid,
       'Dakar ' || i, 'dakar-144-' || i,
       (array['retail', 'farm', 'association'])[1 + i % 3], 'XOF', true,
       14.6928 + i * 0.004, -17.4467 + i * 0.003
  from generate_series(1, 9) i
union all
select ('14400000-0000-0000-0002-' || lpad(i::text, 12, '0'))::uuid,
       'Ouaga ' || i, 'ouaga-144-' || i,
       (array['retail', 'farm', 'association'])[1 + i % 3], 'XOF', true,
       12.3714 + i * 0.004, -1.5197 + i * 0.003
  from generate_series(1, 9) i
union all
select '14400000-0000-0000-0003-000000000001', 'Abidjan 1', 'abidjan-144-1', 'retail', 'XOF', true, 5.3600, -4.0083
union all
select ('14400000-0000-0000-0004-' || lpad(i::text, 12, '0'))::uuid,
       'Bamako ' || i, 'bamako-144-' || i,
       (array['retail', 'farm', 'association'])[i], 'XOF', true, null, null
  from generate_series(1, 3) i;
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
select o.id,
       case substr(o.id::text, 20, 4)
           when '0001' then '14414414-0000-0000-0000-000000000001'::uuid
           when '0002' then '14414414-0000-0000-0000-000000000002'::uuid
           when '0003' then '14414414-0000-0000-0000-000000000003'::uuid
           else '14414414-0000-0000-0000-000000000004'::uuid end,
       'owner', 'org', o.id, 'full'
  from orgs o where o.slug like '%-144-%';
-- One article (or service) per business, on the vitrine, photographed.
insert into products (id, org_id, name, sale_price, quantity, is_active, is_published, is_service)
select ('144aaaaa-0000-0000-' || substr(o.id::text, 20))::uuid, o.id, 'Offre ' || o.name, 2500, 10, true, true,
       o.profile::text = 'association'
  from orgs o where o.slug like '%-144-%';
insert into documents (org_id, r2_key, kind, uploaded_by, product_id)
select p.org_id, 'org/' || p.org_id || '/' || p.id || '.jpg', 'photo',
       (select m.user_id from memberships m where m.org_id = p.org_id and m.role = 'owner' limit 1), p.id
  from products p where p.id::text like '144aaaaa-%';
-- The Dakar shopper's pins: « Travail » in Ouagadougou, « Maison » in
-- Dakar — the home wins. The other shopper's address has no pin.
insert into shopper_addresses (user_id, kind, address, lat, lng) values
    ('14414414-0000-0000-0000-000000000005', 'work', 'Ouaga 2000', 12.3300, -1.5000),
    ('14414414-0000-0000-0000-000000000005', 'home', 'Plateau, Dakar', 14.6950, -17.4440),
    ('14414414-0000-0000-0000-000000000006', 'home', 'Près du marché', null, null);
-- Mara's own pick, in Abidjan: shown to everyone, as before.
update products set featured_until = now() + interval '3 days'
 where id = '144aaaaa-0000-0000-0003-000000000001';

\echo ''
\echo '--- TEST 1: Dakar and Ouagadougou each hold 8 at once; the 9th in Dakar waits, Ouagadougou does not ---'
do $$
declare
    i      int;
    v_at   timestamptz;
    v_ten  timestamptz;
    v_id   text;
begin
    for i in 1..8 loop
        v_at := pg_temp.buy144('14414414-0000-0000-0000-000000000001',
                               ('14400000-0000-0000-0001-' || lpad(i::text, 12, '0'))::uuid,
                               ('144aaaaa-0000-0000-0001-' || lpad(i::text, 12, '0'))::uuid, 'dakar-a-' || i);
        if v_at > now() then
            raise exception 'FAIL: Dakar''s spot % waits (%) with % running', i, v_at, i - 1;
        end if;
    end loop;
    for i in 1..7 loop
        v_at := pg_temp.buy144('14414414-0000-0000-0000-000000000002',
                               ('14400000-0000-0000-0002-' || lpad(i::text, 12, '0'))::uuid,
                               ('144aaaaa-0000-0000-0002-' || lpad(i::text, 12, '0'))::uuid, 'ouaga-a-' || i);
        if v_at > now() then
            raise exception 'FAIL: Ouagadougou''s spot % waits behind a full Dakar (%)', i, v_at;
        end if;
    end loop;
    -- Dakar's 9th: full, it starts when Dakar's first ends.
    v_at := pg_temp.buy144('14414414-0000-0000-0000-000000000001',
                           '14400000-0000-0000-0001-000000000009', '144aaaaa-0000-0000-0001-000000000009', 'dakar-a-9');
    if v_at is distinct from (select min(ends_at) from promotions
                               where org_id::text like '14400000-0000-0000-0001-%' and kind = 'article'
                                 and status = 'approved' and starts_at <= now()) then
        raise exception 'FAIL: Dakar''s 9th starts % — not when Dakar''s first place frees', v_at;
    end if;
    if v_at < now() + interval '6 days' then
        raise exception 'FAIL: Dakar''s 9th does not wait (%)', v_at;
    end if;
    -- Ouagadougou's 8th, after a full Dakar: at once.
    v_at := pg_temp.buy144('14414414-0000-0000-0000-000000000002',
                           '14400000-0000-0000-0002-000000000008', '144aaaaa-0000-0000-0002-000000000008', 'ouaga-a-8');
    if v_at > now() then
        raise exception 'FAIL: Ouagadougou''s 8th waits (%) though Ouagadougou had 7', v_at;
    end if;
    -- Ouagadougou's 9th, « Valider » by the platform: it waits its turn there.
    v_id := pg_temp.ask144('14414414-0000-0000-0000-000000000002',
                           '14400000-0000-0000-0002-000000000009', '144aaaaa-0000-0000-0002-000000000009');
    perform pg_temp.as144('14414414-0000-0000-0000-000000000008');
    perform decide_promotion(v_id::uuid, true);
    perform pg_temp.as144(null);
    if (select starts_at from promotions where id = v_id::uuid) < now() + interval '6 days' then
        raise exception 'FAIL: Ouagadougou''s 9th, approved by the platform, does not wait';
    end if;
    -- 8 running in each city, 1 waiting in each.
    if (select count(*) from promotions where org_id::text like '14400000-0000-0000-0001-%'
           and kind = 'article' and status = 'approved' and starts_at <= now()) <> 8
       or (select count(*) from promotions where org_id::text like '14400000-0000-0000-0002-%'
           and kind = 'article' and status = 'approved' and starts_at <= now()) <> 8 then
        raise exception 'FAIL: not 8 running in each city';
    end if;
    -- Abidjan's queue, empty, by the door Wave and the prize call.
    v_ten := next_spot_start('article', '14400000-0000-0000-0003-000000000001');
    if v_ten > now() then
        raise exception 'FAIL: Abidjan waits behind Dakar or Ouagadougou (%)', v_ten;
    end if;
    raise notice 'PASS: 8 running in Dakar and 8 in Ouagadougou at once; Dakar''s 9th (card) and Ouagadougou''s 9th (Valider) wait their own city''s first end; Ouagadougou''s 8th, after a full Dakar, starts at once; Abidjan starts at once';
end $$;

\echo ''
\echo '--- TEST 2: the vitrines are capped by area too ---'
do $$
declare
    i    int;
    v_at timestamptz;
begin
    for i in 1..8 loop
        v_at := pg_temp.buy144('14414414-0000-0000-0000-000000000001',
                               ('14400000-0000-0000-0001-' || lpad(i::text, 12, '0'))::uuid, null, 'dakar-s-' || i);
        if v_at > now() then
            raise exception 'FAIL: Dakar''s vitrine % waits with % running', i, i - 1;
        end if;
    end loop;
    v_at := pg_temp.buy144('14414414-0000-0000-0000-000000000001',
                           '14400000-0000-0000-0001-000000000009', null, 'dakar-s-9');
    if v_at < now() + interval '6 days' then
        raise exception 'FAIL: Dakar''s 9th vitrine does not wait (%)', v_at;
    end if;
    v_at := pg_temp.buy144('14414414-0000-0000-0000-000000000002',
                           '14400000-0000-0000-0002-000000000001', null, 'ouaga-s-1');
    v_at := greatest(v_at, pg_temp.buy144('14414414-0000-0000-0000-000000000003',
                           '14400000-0000-0000-0003-000000000001', null, 'abidjan-s-1'));
    if v_at > now() then
        raise exception 'FAIL: a vitrine in Ouagadougou or Abidjan waits behind a full Dakar';
    end if;
    raise notice 'PASS: 8 vitrines at the top in Dakar, the 9th waits; Ouagadougou''s and Abidjan''s start at once';
end $$;

\echo ''
\echo '--- TEST 3: a shopper near Dakar sees Dakar only; near Ouagadougou, Ouagadougou only; with no location, none ---'
do $$
declare
    v_dakar text := (select string_agg('dakar-144-' || i, ',' order by 'dakar-144-' || i) from generate_series(1, 8) i);
    v_ouaga text := (select string_agg('ouaga-144-' || i, ',' order by 'ouaga-144-' || i) from generate_series(1, 8) i);
    v       text;
begin
    -- Mara's pick (Abidjan) is in every answer; the spots only in theirs.
    v := pg_temp.featured144(null, 14.6900, -17.4500);
    if v <> 'abidjan-144-1,' || v_dakar then
        raise exception 'FAIL: near Dakar, À la une shows %', v;
    end if;
    v := pg_temp.featured144(null, 12.3700, -1.5200);
    if v <> 'abidjan-144-1,' || v_ouaga then
        raise exception 'FAIL: near Ouagadougou, À la une shows %', v;
    end if;
    v := pg_temp.featured144(null, 5.3600, -4.0100);
    if v <> 'abidjan-144-1' then
        raise exception 'FAIL: in Abidjan, À la une shows another city''s spot: %', v;
    end if;
    -- No location: signed out, with no point; a point off the Earth; the
    -- door an older app calls.
    if pg_temp.featured144(null, null, null) <> 'abidjan-144-1'
       or pg_temp.featured144(null, 999, 999) <> 'abidjan-144-1'
       or pg_temp.featured144(null, null, null, true) <> 'abidjan-144-1'
       or pg_temp.featured144('14414414-0000-0000-0000-000000000006', null, null) <> 'abidjan-144-1' then
        raise exception 'FAIL: a shopper with no location sees a spot';
    end if;
    -- Signed in, no point sent: the saved « Maison » pin (Dakar), even
    -- through the older app's door; a point sent wins over the pin.
    if pg_temp.featured144('14414414-0000-0000-0000-000000000005', null, null) <> 'abidjan-144-1,' || v_dakar
       or pg_temp.featured144('14414414-0000-0000-0000-000000000005', null, null, true) <> 'abidjan-144-1,' || v_dakar
       or pg_temp.featured144('14414414-0000-0000-0000-000000000005', 12.3700, -1.5200) <> 'abidjan-144-1,' || v_ouaga then
        raise exception 'FAIL: the shopper''s saved pin or sent point is not the one used';
    end if;
    -- The vitrines at the top of the list.
    if pg_temp.lights144(null, 14.6900, -17.4500) <> v_dakar
       or pg_temp.lights144(null, 12.3700, -1.5200) <> 'ouaga-144-1'
       or pg_temp.lights144(null, 5.3600, -4.0100) <> 'abidjan-144-1'
       or pg_temp.lights144(null, null, null) <> ''
       or pg_temp.lights144(null, null, null, true) <> ''
       or pg_temp.lights144('14414414-0000-0000-0000-000000000006', null, null, true) <> ''
       or pg_temp.lights144('14414414-0000-0000-0000-000000000005', null, null, true) <> v_dakar then
        raise exception 'FAIL: the spotlights are not by area';
    end if;
    -- The radius is the setting's: at 5 km, from 2 km south of the centre,
    -- Ouagadougou's 1st (≈ 2,7 km) is in, its 8th (≈ 6,3 km) out.
    update platform_settings set value = '5' where key = 'spot_area_km';
    v := pg_temp.featured144(null, 12.3514, -1.5197);
    update platform_settings set value = '30' where key = 'spot_area_km';
    if v not like '%ouaga-144-1%' or v like '%ouaga-144-8%' then
        raise exception 'FAIL: the radius setting is not read: %', v;
    end if;
    raise notice 'PASS: near Dakar Dakar''s 8 spots, near Ouagadougou Ouagadougou''s 8, in Abidjan neither; no location (signed out, off the Earth, no pin, the older door) no spot; signed in, the home pin; the vitrines at the top the same; the radius read; Mara''s pick for all';
end $$;

\echo ''
\echo '--- TEST 4: a business with no position is refused, and told where to place it ---'
do $$
declare v text;
begin
    v := pg_temp.ask144('14414414-0000-0000-0000-000000000004', '14400000-0000-0000-0004-000000000001', null);
    if v not like 'ERR:%La position de ma boutique%' then
        raise exception 'FAIL: a shop with no pin asked: %', v;
    end if;
    v := pg_temp.ask144('14414414-0000-0000-0000-000000000004', '14400000-0000-0000-0004-000000000002',
                        '144aaaaa-0000-0000-0004-000000000002');
    if v not like 'ERR:%La position de ma ferme%' then
        raise exception 'FAIL: a farm with no pin asked: %', v;
    end if;
    v := pg_temp.ask144('14414414-0000-0000-0000-000000000004', '14400000-0000-0000-0004-000000000003',
                        '144aaaaa-0000-0000-0004-000000000003');
    if v not like 'ERR:%La position de mon association%' then
        raise exception 'FAIL: an association with no pin asked: %', v;
    end if;
    if spot_ineligible('14400000-0000-0000-0004-000000000001', null) is distinct from 'position' then
        raise exception 'FAIL: spot_ineligible says % for a business with no pin',
            spot_ineligible('14400000-0000-0000-0004-000000000001', null);
    end if;
    -- A payment that must make it a new spot (its old one ended): refused
    -- and recorded, as 139 does — never a spot shown nowhere.
    insert into promotions (id, org_id, kind, days, price, currency, status, starts_at, ends_at)
    values ('144bbbbb-0000-0000-0000-000000000001', '14400000-0000-0000-0004-000000000001', 'shop', 7,
            15000, 'XOF', 'approved', now() - interval '9 days', now() - interval '2 days');
    v := spot_settle('stripe', 'cs_144_nopin', '144bbbbb-0000-0000-0000-000000000001', 'stripe:shop',
                     15000, 'XOF', 'production') ->> 'reason';
    if v is distinct from 'position'
       or not exists (select 1 from spot_purchases where external_id = 'cs_144_nopin' and outcome = 'refused') then
        raise exception 'FAIL: a payment for a business with no pin programmed a spot (%)', v;
    end if;
    if pg_temp.status144('14414414-0000-0000-0000-000000000004', '14400000-0000-0000-0004-000000000001', 'shop')
           ->> 'positioned' <> 'false' then
        raise exception 'FAIL: the sheet is not told the business has no pin';
    end if;
    raise notice 'PASS: no pin, no spot — a shop, a farm and an association told « La position de ma boutique / ferme / association »; spot_ineligible ''position''; a payment for it refused and recorded; the sheet told';
end $$;

\echo ''
\echo '--- TEST 5: the places free around a business this week, and the date when full ---'
do $$
declare v jsonb;
begin
    v := pg_temp.status144('14414414-0000-0000-0000-000000000001', '14400000-0000-0000-0001-000000000001', 'article');
    if (v ->> 'free')::int <> 0 or (v ->> 'places')::int <> 8 or (v ->> 'taken')::int <> 9
       or (v ->> 'next_at') is null or (v ->> 'next_at')::timestamptz < now() + interval '6 days'
       or (v ->> 'area_km')::numeric <> 30 or v ->> 'positioned' <> 'true' then
        raise exception 'FAIL: full Dakar not said full with its date: %', v;
    end if;
    v := pg_temp.status144('14414414-0000-0000-0000-000000000002', '14400000-0000-0000-0002-000000000001', 'shop');
    if (v ->> 'free')::int <> 7 or (v ->> 'taken')::int <> 1 or v ? 'next_at' and v ->> 'next_at' is not null then
        raise exception 'FAIL: Ouagadougou''s vitrines not « 7 places libres sur 8 »: %', v;
    end if;
    v := pg_temp.status144('14414414-0000-0000-0000-000000000003', '14400000-0000-0000-0003-000000000001', 'article');
    if (v ->> 'free')::int <> 8 then
        raise exception 'FAIL: Abidjan not « 8 places libres sur 8 »: %', v;
    end if;
    -- Somebody else's business: refused. The platform: told.
    v := pg_temp.status144('14414414-0000-0000-0000-000000000002', '14400000-0000-0000-0001-000000000001', 'article');
    if not v ? 'error' then
        raise exception 'FAIL: an owner read another business''s area: %', v;
    end if;
    v := pg_temp.status144('14414414-0000-0000-0000-000000000008', '14400000-0000-0000-0001-000000000001', 'article');
    if (v ->> 'free')::int <> 0 then
        raise exception 'FAIL: the platform not told: %', v;
    end if;
    raise notice 'PASS: full Dakar « 0 sur 8 » with the date the next place frees; Ouagadougou''s vitrines 7 of 8; Abidjan 8 of 8; another owner refused, the platform told';
end $$;

\echo ''
\echo '--- TEST 6: installing 144 over running and queued spots touches none ---'
-- A spot running before 144 for a business that has no pin: kept as is.
insert into promotions (id, org_id, kind, days, price, currency, status, starts_at, ends_at)
values ('144bbbbb-0000-0000-0000-000000000002', '14400000-0000-0000-0004-000000000002', 'shop', 7,
        15000, 'XOF', 'approved', now() - interval '1 day', now() + interval '6 days');
create temp table b144_before as
    select md5(string_agg(to_jsonb(p)::text, ',' order by p.id)) as h, count(*) as n from promotions p;
\i database/migrations/144_spots_by_area.sql
do $$
begin
    if (select h from b144_before) is distinct from
       (select md5(string_agg(to_jsonb(p)::text, ',' order by p.id)) from promotions p) then
        raise exception 'FAIL: installing 144 changed a spot';
    end if;
    if (select status from promotions where id = '144bbbbb-0000-0000-0000-000000000002') <> 'approved' then
        raise exception 'FAIL: a running spot of a business with no pin was cancelled';
    end if;
    raise notice 'PASS: installing 144 again over % spots (running, queued, one of a business with no pin) changes none', (select n from b144_before);
end $$;

\echo ''
\echo '--- TEST 7: spot_area_km in Réglages, 5 to 200 km, whole, journaled ---'
create function pg_temp.refused144(p_sql text)
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
grant execute on function pg_temp.refused144(text) to authenticated;
do $$
declare v_id uuid;
begin
    perform pg_temp.as144('14414414-0000-0000-0000-000000000008');
    execute 'set local role authenticated';
    if not (platform_settings_board() ? 'spot_area_km') then
        raise exception 'FAIL: spot_area_km is not on the Réglages board';
    end if;
    if pg_temp.refused144($q$select platform_set_setting('spot_area_km', '4')$q$)
           <> 'Un nombre de kilomètres de 5 à 200, s''il vous plaît.'
       or pg_temp.refused144($q$select platform_set_setting('spot_area_km', '201')$q$)
           <> 'Un nombre de kilomètres de 5 à 200, s''il vous plaît.'
       or pg_temp.refused144($q$select platform_set_setting('spot_area_km', '12.5')$q$)
           <> 'Un nombre entier, s''il vous plaît.' then
        raise exception 'FAIL: a radius out of 5–200 or a decimal went through';
    end if;
    v_id := platform_set_setting('spot_area_km', '50');
    execute 'reset role';
    if v_id is null or (select value from platform_settings where key = 'spot_area_km') <> '50'::jsonb then
        raise exception 'FAIL: 50 km was not kept and journaled';
    end if;
    raise notice 'PASS: spot_area_km on the board, 4, 201 and 12,5 refused in French, 50 kept and journaled';
end $$;

\echo ''
\echo '--- TEST 8: the doors, and no path left on the street-wide queue ---'
do $$
declare v text;
begin
    if not has_function_privilege('anon', 'storefront_featured(double precision, double precision)', 'execute')
       or not has_function_privilege('anon', 'storefront_spotlights(double precision, double precision)', 'execute')
       or not has_function_privilege('anon', 'storefront_featured()', 'execute')
       or not has_function_privilege('anon', 'storefront_spotlights()', 'execute') then
        raise exception 'FAIL: the street''s doors closed to a stranger';
    end if;
    if has_function_privilege('anon', 'spot_area_status(uuid, text)', 'execute')
       or has_function_privilege('anon', 'next_spot_start(text, uuid)', 'execute')
       or has_function_privilege('authenticated', 'next_spot_start(text, uuid)', 'execute')
       or has_function_privilege('anon', 'spot_in_area(double precision, double precision, double precision, double precision)', 'execute')
       or has_function_privilege('authenticated', 'spot_viewer_point(double precision, double precision)', 'execute')
       or has_function_privilege('authenticated', 'spot_area_queue(text, uuid)', 'execute')
       or has_function_privilege('anon', 'request_promotion(uuid, uuid, integer)', 'execute') then
        raise exception 'FAIL: a spot door or helper open where it should not be';
    end if;
    if not has_function_privilege('authenticated', 'spot_area_status(uuid, text)', 'execute') then
        raise exception 'FAIL: the sheet''s door closed to authenticated';
    end if;
    select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', ', ') into v
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('spot_in_area', 'spot_viewer_point', 'spot_area_queue', 'next_spot_start',
                         'spot_area_status', 'storefront_featured', 'storefront_spotlights',
                         'request_promotion', 'spot_ineligible', 'spot_settle', 'decide_promotion',
                         'wave_settle', 'cauris_week_close', 'platform_set_setting')
       and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%');
    if v is not null then
        raise exception 'FAIL: search_path not pinned: %', v;
    end if;
    -- Every path that programs a spot calls the area's door: no function
    -- but 071's own still calls next_spot_start with the kind alone.
    select string_agg(p.proname, ', ') into v
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname <> 'next_spot_start'
       and p.prosrc ~ 'next_spot_start\([^,()]*\)';
    if v is not null then
        raise exception 'FAIL: still on the street-wide queue: %', v;
    end if;
    if (select prosecdef from pg_proc where oid = 'spot_area_status(uuid, text)'::regprocedure) is not true
       or (select prosecdef from pg_proc where oid = 'next_spot_start(text, uuid)'::regprocedure) is not true
       or (select prosecdef from pg_proc where oid = 'spot_in_area(double precision, double precision, double precision, double precision)'::regprocedure)
       or (select prosecdef from pg_proc where oid = 'spot_area_queue(text, uuid)'::regprocedure) then
        raise exception 'FAIL: a door or a helper changed its SECURITY';
    end if;
    raise notice 'PASS: the street''s two new doors anon''s, the old ones too; the sheet''s authenticated''s; next_spot_start and the helpers nobody''s; every search_path pinned; no path on the street-wide queue';
end $$;

\echo ''
\echo '--- TEST 9: a business fixes its own spot — cancel, change once, stop; the platform any, journaled ---'
-- Bamako, placed this time: a shop, a farm and an association, three
-- items each (the third with no photo), and an owner from elsewhere.
insert into auth.users (id, phone, email, email_confirmed_at, raw_user_meta_data) values
    ('14414414-0000-0000-0000-000000000009', '+22314400009', 'fix144@example.org', now(), '{"full_name": "Corrige 144"}');
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, lat, lng)
select ('14400000-0000-0000-0005-' || lpad(i::text, 12, '0'))::uuid, 'Fix ' || i, 'fix-144-' || i,
       (array['retail', 'farm', 'association'])[i], 'XOF', true, 12.6392 + i * 0.002, -8.0029
  from generate_series(1, 3) i;
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
select o.id, '14414414-0000-0000-0000-000000000009', 'owner', 'org', o.id, 'full'
  from orgs o where o.slug like 'fix-144-%';
insert into products (id, org_id, name, sale_price, quantity, is_active, is_published, is_service)
select ('144ccccc-0000-0000-000' || i || '-' || lpad(j::text, 12, '0'))::uuid,
       ('14400000-0000-0000-0005-' || lpad(i::text, 12, '0'))::uuid,
       'Choix ' || i || '-' || j, 3000, case when i = 3 then 0 else 5 end, true, true, i = 3
  from generate_series(1, 3) i, generate_series(1, 3) j;
insert into documents (org_id, r2_key, kind, uploaded_by, product_id)
select p.org_id, 'org/' || p.org_id || '/' || p.id || '.jpg', 'photo', '14414414-0000-0000-0000-000000000009', p.id
  from products p where p.id::text like '144ccccc-%'
   and p.id not in ('144ccccc-0000-0000-0001-000000000003', '144ccccc-0000-0000-0003-000000000003');

-- A call as somebody: 'ok', or the refusal's words.
create function pg_temp.fix144(p_who uuid, p_sql text)
returns text
language plpgsql
as $$
begin
    perform pg_temp.as144(p_who);
    execute 'set local role ' || case when p_who is null then 'anon' else 'authenticated' end;
    execute p_sql;
    execute 'reset role';
    return 'ok';
exception when others then
    execute 'reset role';
    return sqlerrm;
end;
$$;
grant execute on function pg_temp.fix144(uuid, text) to anon, authenticated;

-- The spots, set as each case needs: an article spot of each business,
-- asked (a1), claimed paid (a2), paid and waiting (q1), running for 2 h
-- (r1), running for 30 h (r2); a running vitrine spot (s1).
insert into promotions (id, org_id, product_id, kind, days, price, currency, status, starts_at, ends_at, requested_by) values
    ('144ddddd-0000-0000-0000-0000000000a1', '14400000-0000-0000-0005-000000000001', '144ccccc-0000-0000-0001-000000000001',
     'article', 7, 5000, 'XOF', 'requested', null, null, '14414414-0000-0000-0000-000000000009'),
    ('144ddddd-0000-0000-0000-0000000000a2', '14400000-0000-0000-0005-000000000002', '144ccccc-0000-0000-0002-000000000001',
     'article', 7, 5000, 'XOF', 'paid_claimed', null, null, '14414414-0000-0000-0000-000000000009'),
    ('144ddddd-0000-0000-0000-0000000000b1', '14400000-0000-0000-0005-000000000003', '144ccccc-0000-0000-0003-000000000001',
     'article', 7, 5000, 'XOF', 'requested', null, null, '14414414-0000-0000-0000-000000000009'),
    ('144ddddd-0000-0000-0000-0000000000e1', '14400000-0000-0000-0005-000000000003', '144ccccc-0000-0000-0003-000000000002',
     'article', 7, 5000, 'XOF', 'approved', now() + interval '3 days', now() + interval '10 days', '14414414-0000-0000-0000-000000000009'),
    ('144ddddd-0000-0000-0000-0000000000c1', '14400000-0000-0000-0005-000000000002', '144ccccc-0000-0000-0002-000000000002',
     'article', 7, 5000, 'XOF', 'approved', now() - interval '2 hours', now() + interval '7 days' - interval '2 hours', '14414414-0000-0000-0000-000000000009'),
    ('144ddddd-0000-0000-0000-0000000000c2', '14400000-0000-0000-0005-000000000001', '144ccccc-0000-0000-0001-000000000002',
     'article', 7, 5000, 'XOF', 'approved', now() - interval '30 hours', now() + interval '7 days' - interval '30 hours', '14414414-0000-0000-0000-000000000009'),
    ('144ddddd-0000-0000-0000-0000000000f1', '14400000-0000-0000-0005-000000000001', null,
     'shop', 7, 15000, 'XOF', 'approved', now() - interval '1 hour', now() + interval '6 days', '14414414-0000-0000-0000-000000000009');

do $$
declare
    me    uuid := '14414414-0000-0000-0000-000000000009';
    other uuid := '14414414-0000-0000-0000-000000000001';
    mara  uuid := '14414414-0000-0000-0000-000000000008';
    v     text;
    o     jsonb;
    r     jsonb;
    v_before promotions%rowtype;
begin
    -- Asked, not paid: the options say so; changed once, the second
    -- refused; to an item with no photo, or the same item, refused.
    perform pg_temp.as144(me);
    o := promotion_options('144ddddd-0000-0000-0000-0000000000a1');
    if not (o ->> 'can_cancel')::boolean or not (o ->> 'can_change')::boolean or (o ->> 'can_stop')::boolean
       or jsonb_array_length(o -> 'items') <> 1
       or o -> 'items' -> 0 ->> 'id' <> '144ccccc-0000-0000-0001-000000000002' then
        raise exception 'FAIL: the options of an asked spot: %', o;
    end if;
    if pg_temp.fix144(me, $q$select change_promotion_product('144ddddd-0000-0000-0000-0000000000a1', '144ccccc-0000-0000-0001-000000000003')$q$)
           not like 'Un article mis en avant doit être%'
       or pg_temp.fix144(me, $q$select change_promotion_product('144ddddd-0000-0000-0000-0000000000a1', '144ccccc-0000-0000-0001-000000000001')$q$)
           <> 'C''est déjà cet article ou ce service' then
        raise exception 'FAIL: a change to an item with no photo, or to the same, went through';
    end if;
    -- c2 runs Fix 1's item 2: the asked spot may not take it.
    if pg_temp.fix144(me, $q$select change_promotion_product('144ddddd-0000-0000-0000-0000000000a1', '144ccccc-0000-0000-0001-000000000002')$q$)
           <> 'Cet emplacement est déjà demandé ou en cours' then
        raise exception 'FAIL: a change onto an item already « à la une » went through';
    end if;
    update promotions set status = 'cancelled' where id = '144ddddd-0000-0000-0000-0000000000c2';
    v := pg_temp.fix144(me, $q$select change_promotion_product('144ddddd-0000-0000-0000-0000000000a1', '144ccccc-0000-0000-0001-000000000002')$q$);
    update promotions set status = 'approved' where id = '144ddddd-0000-0000-0000-0000000000c2';
    if v <> 'ok' or (select product_id from promotions where id = '144ddddd-0000-0000-0000-0000000000a1')
                    <> '144ccccc-0000-0000-0001-000000000002' then
        raise exception 'FAIL: an asked spot''s item not changed: %', v;
    end if;
    if pg_temp.fix144(me, $q$select change_promotion_product('144ddddd-0000-0000-0000-0000000000a1', '144ccccc-0000-0000-0001-000000000001')$q$)
           <> 'L''article ou le service ne se change qu''une fois' then
        raise exception 'FAIL: a second change went through';
    end if;
    if not exists (select 1 from promotion_fixes where promotion_id = '144ddddd-0000-0000-0000-0000000000a1'
                      and action = 'change' and from_product = '144ccccc-0000-0000-0001-000000000001'
                      and to_product = '144ccccc-0000-0000-0001-000000000002' and by_user = me
                      and created_at is not null) then
        raise exception 'FAIL: the change is not recorded with the old and new item';
    end if;
    -- Another business's owner and a stranger: refused at the door.
    if pg_temp.fix144(other, $q$select cancel_promotion('144ddddd-0000-0000-0000-0000000000a1')$q$) <> 'Mise en avant introuvable'
       or pg_temp.fix144(other, $q$select stop_promotion('144ddddd-0000-0000-0000-0000000000c1')$q$) <> 'Mise en avant introuvable'
       or pg_temp.fix144(other, $q$select change_promotion_product('144ddddd-0000-0000-0000-0000000000e1', '144ccccc-0000-0000-0003-000000000003')$q$) <> 'Mise en avant introuvable'
       or pg_temp.fix144(other, $q$select promotion_options('144ddddd-0000-0000-0000-0000000000a1')$q$) <> 'Mise en avant introuvable'
       or pg_temp.fix144(null, $q$select cancel_promotion('144ddddd-0000-0000-0000-0000000000a1')$q$) not like 'permission denied%'
       or pg_temp.fix144(null, $q$select stop_promotion('144ddddd-0000-0000-0000-0000000000c1')$q$) not like 'permission denied%'
       or pg_temp.fix144(null, $q$select change_promotion_product('144ddddd-0000-0000-0000-0000000000a1', '144ccccc-0000-0000-0001-000000000001')$q$) not like 'permission denied%' then
        raise exception 'FAIL: another business or a stranger fixed somebody''s spot';
    end if;
    -- Annuler: the asked one; the claimed paid one refused; one with an
    -- open Wave payment refused.
    if pg_temp.fix144(me, $q$select cancel_promotion('144ddddd-0000-0000-0000-0000000000a2')$q$)
           <> 'Paiement signalé : Mara le vérifie, la demande ne s''annule plus' then
        raise exception 'FAIL: a spot said paid was cancelled';
    end if;
    insert into wave_payments (kind, org_id, promotion_id, payer_id, method, amount, currency, status)
    values ('spot', '14400000-0000-0000-0005-000000000003', '144ddddd-0000-0000-0000-0000000000b1', me,
            'wave', 5000, 'XOF', 'open');
    if pg_temp.fix144(me, $q$select cancel_promotion('144ddddd-0000-0000-0000-0000000000b1')$q$)
           not like 'Un paiement Wave est en cours%' then
        raise exception 'FAIL: a spot with an open Wave payment was cancelled';
    end if;
    v := pg_temp.fix144(me, $q$select cancel_promotion('144ddddd-0000-0000-0000-0000000000a1')$q$);
    if v <> 'ok'
       or (select status from promotions where id = '144ddddd-0000-0000-0000-0000000000a1') <> 'cancelled'
       or pg_temp.fix144(me, $q$select cancel_promotion('144ddddd-0000-0000-0000-0000000000a1')$q$)
           <> 'Seule une demande pas encore payée s''annule' then
        raise exception 'FAIL: an asked spot not cancelled once: %', v;
    end if;
    -- Paid, waiting its turn (the association's service): changed, its
    -- dates and price kept; not stopped.
    select * into v_before from promotions where id = '144ddddd-0000-0000-0000-0000000000e1';
    if pg_temp.fix144(me, $q$select change_promotion_product('144ddddd-0000-0000-0000-0000000000e1', '144ccccc-0000-0000-0003-000000000003')$q$)
           not like 'Un article mis en avant%' then
        raise exception 'FAIL: a service with no photo was taken';
    end if;
    update promotions set status = 'cancelled' where id = '144ddddd-0000-0000-0000-0000000000b1';
    v := pg_temp.fix144(me, $q$select change_promotion_product('144ddddd-0000-0000-0000-0000000000e1', '144ccccc-0000-0000-0003-000000000001')$q$);
    if v <> 'ok'
       or (select row(starts_at, ends_at, price, currency, status) from promotions where id = v_before.id)
          is distinct from row(v_before.starts_at, v_before.ends_at, v_before.price, v_before.currency, v_before.status) then
        raise exception 'FAIL: a waiting spot''s change moved its dates or price';
    end if;
    if pg_temp.fix144(me, $q$select stop_promotion('144ddddd-0000-0000-0000-0000000000e1')$q$)
           <> 'Seule une mise en avant en cours s''arrête' then
        raise exception 'FAIL: a waiting spot was stopped';
    end if;
    -- Running for 2 h (the farm's): changed within 24 h, then stopped now.
    if pg_temp.fix144(me, $q$select change_promotion_product('144ddddd-0000-0000-0000-0000000000c1', '144ccccc-0000-0000-0002-000000000003')$q$) <> 'ok' then
        raise exception 'FAIL: a running spot not changed in its first 24 h';
    end if;
    perform pg_temp.as144(me);
    o := promotion_options('144ddddd-0000-0000-0000-0000000000c1');
    if (o ->> 'can_change')::boolean or not (o ->> 'can_stop')::boolean or (o ->> 'change_until') is null then
        raise exception 'FAIL: the options of a running spot changed once: %', o;
    end if;
    v := pg_temp.fix144(me, $q$select stop_promotion('144ddddd-0000-0000-0000-0000000000c1')$q$);
    if v <> 'ok'
       or (select ends_at from promotions where id = '144ddddd-0000-0000-0000-0000000000c1') > now()
       or not exists (select 1 from promotion_fixes where promotion_id = '144ddddd-0000-0000-0000-0000000000c1' and action = 'stop') then
        raise exception 'FAIL: a running spot not stopped now';
    end if;
    -- Running for 30 h: the 24 h are over. The vitrine's spot: no item.
    if pg_temp.fix144(me, $q$select change_promotion_product('144ddddd-0000-0000-0000-0000000000c2', '144ccccc-0000-0000-0001-000000000001')$q$)
           <> 'L''article ou le service se change seulement dans les 24 h après le début'
       or pg_temp.fix144(me, $q$select change_promotion_product('144ddddd-0000-0000-0000-0000000000f1', '144ccccc-0000-0000-0001-000000000001')$q$)
           <> 'La vitrine entière n''a pas d''article à changer' then
        raise exception 'FAIL: a change after 24 h, or of a vitrine spot, went through';
    end if;
    -- The platform: the 30-hour one changed anyway, the vitrine one
    -- stopped, both journaled; an owner may not use the platform's doors.
    v := pg_temp.fix144(me, $q$select platform_change_promotion_product('144ddddd-0000-0000-0000-0000000000c2', '144ccccc-0000-0000-0001-000000000001')$q$)
         || ' / ' || pg_temp.fix144(me, $q$select platform_stop_promotion('144ddddd-0000-0000-0000-0000000000f1')$q$);
    if v like '%ok%' then
        raise exception 'FAIL: an owner used the platform''s doors';
    end if;
    v := pg_temp.fix144(mara, $q$select platform_change_promotion_product('144ddddd-0000-0000-0000-0000000000c2', '144ccccc-0000-0000-0001-000000000001')$q$)
         || ' / ' || pg_temp.fix144(mara, $q$select platform_stop_promotion('144ddddd-0000-0000-0000-0000000000f1')$q$);
    if v <> 'ok / ok'
       or (select product_id from promotions where id = '144ddddd-0000-0000-0000-0000000000c2') <> '144ccccc-0000-0000-0001-000000000001'
       or (select ends_at from promotions where id = '144ddddd-0000-0000-0000-0000000000f1') > now()
       or (select count(*) from platform_actions where org_id = '14400000-0000-0000-0005-000000000001'
              and kind in ('spot_change', 'spot_stop')) <> 2 then
        raise exception 'FAIL: the platform''s change and stop not done and journaled: %', v;
    end if;
    -- A store payment of a spot whose item was changed: the same row,
    -- programmed with the new item; its refund ends that row.
    perform pg_temp.as144(me);
    v := pg_temp.ask144(me, '14400000-0000-0000-0005-000000000002', '144ccccc-0000-0000-0002-000000000001');
    if v like 'ERR:%' then
        update promotions set status = 'cancelled' where id = '144ddddd-0000-0000-0000-0000000000a2';
        v := pg_temp.ask144(me, '14400000-0000-0000-0005-000000000002', '144ccccc-0000-0000-0002-000000000001');
    end if;
    if pg_temp.fix144(me, format('select change_promotion_product(%L, %L)', v, '144ccccc-0000-0000-0002-000000000002')) <> 'ok' then
        raise exception 'FAIL: a spot asked in the app not changed before its payment';
    end if;
    r := spot_settle('google', 'gp-144-changed', v::uuid, 'mara_spot_article_7', 5000, 'XOF', 'production');
    if not (r ->> 'granted')::boolean or r ->> 'promotion_id' <> v
       or (select product_id from promotions where id = v::uuid) <> '144ccccc-0000-0000-0002-000000000002'
       or (select promotion_id from spot_purchases where external_id = 'gp-144-changed') <> v::uuid then
        raise exception 'FAIL: the store payment did not program the changed spot: %', r;
    end if;
    r := spot_refund('google', 'gp-144-changed', 'test');
    if r ->> 'promotion_id' <> v or (select ends_at from promotions where id = v::uuid) > now() + interval '1 second'
          and (select status from promotions where id = v::uuid) <> 'cancelled' then
        raise exception 'FAIL: the refund did not end the changed spot: %', r;
    end if;
    raise notice 'PASS: a shop, a farm and an association fix their own spot — asked: cancelled, changed once (the second, the same item, one with no photo, one already « à la une » refused); said paid or with an open Wave payment: never cancelled; paid and waiting: changed, dates and price kept, not stopped; running: changed in its first 24 h and stopped now, after 24 h refused; the vitrine''s spot has no item; another owner and a stranger refused; the platform changes and stops any, journaled; a store payment programs the changed row, its refund ends it';
end $$;

do $$
begin
    if has_function_privilege('anon', 'promotion_options(uuid)', 'execute')
       or has_function_privilege('anon', 'cancel_promotion(uuid)', 'execute')
       or has_function_privilege('anon', 'platform_stop_promotion(uuid)', 'execute')
       or has_function_privilege('authenticated', 'promotion_change_item(uuid, uuid, boolean)', 'execute')
       or has_function_privilege('authenticated', 'spot_item_ready(uuid, uuid)', 'execute')
       or not has_function_privilege('authenticated', 'change_promotion_product(uuid, uuid)', 'execute')
       or not has_function_privilege('authenticated', 'stop_promotion(uuid)', 'execute')
       or not has_function_privilege('authenticated', 'platform_change_promotion_product(uuid, uuid)', 'execute') then
        raise exception 'FAIL: a fix door open to anon, or closed to authenticated';
    end if;
    if exists (select 1 from pg_proc p
                where p.proname in ('promotion_options', 'change_promotion_product', 'cancel_promotion',
                                    'stop_promotion', 'platform_change_promotion_product',
                                    'platform_stop_promotion', 'promotion_change_item', 'spot_item_ready')
                  and (not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')
                       or (p.prosecdef <> (p.proname not in ('promotion_change_item', 'spot_item_ready'))))) then
        raise exception 'FAIL: a fix function unpinned, or its SECURITY not as meant';
    end if;
    if not (select relrowsecurity from pg_class where oid = 'promotion_fixes'::regclass)
       or has_table_privilege('authenticated', 'promotion_fixes', 'select')
       or has_table_privilege('anon', 'promotion_fixes', 'select') then
        raise exception 'FAIL: promotion_fixes readable outside its functions';
    end if;
    raise notice 'PASS: the fix doors authenticated''s, never anon''s; the helpers the definers'' alone; pinned; promotion_fixes under RLS, written by its functions alone';
end $$;

rollback;

\echo ''
\echo 'test_batch144: all claims passed'
