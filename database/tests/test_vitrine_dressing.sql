-- ============================================================
-- test_vitrine_dressing.sql — every vitrine dresses itself; Pro arranges
-- it (093). Phone block 63.
--
-- The claims: a Free owner sets a cover, one of the six colours, a
-- tagline and a schedule, and the street reads them; another colour is
-- the Pro door; the layout, the pins and the stock switch are not written
-- for Free (and a Free save keeps a lapsed Pro's arrangement); a Pro owner
-- writes the layout and the street reads it with the live banner; a bad
-- schedule and an unknown layout are refused; the banner follows the
-- clock, including a night shop past midnight.
-- ============================================================
\set ON_ERROR_STOP on

\set owner_f '''63636363-0000-0000-0000-000000000001'''
\set owner_p '''63636363-0000-0000-0000-000000000002'''
\set shop_f  '''63000000-0000-0000-0000-000000000001'''
\set shop_p  '''63000000-0000-0000-0000-000000000002'''
\set p_f     '''63aaaaaa-0000-0000-0000-000000000001'''
\set p_p     '''63aaaaaa-0000-0000-0000-000000000002'''

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
update platform_settings set value = '0' where key = 'vitrine_min_items';
update platform_settings set value = '1' where key = 'vitrine_free_basics';
\i database/migrations/093_vitrine_dressing.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner_f, '+22663000001', '{"full_name": "Libre"}'),
    (:owner_p, '+22663000002', '{"full_name": "Pro"}');
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, plan, plan_until) values
    (:shop_f, 'Boutique Libre 63', 'libre-63', 'retail', 'XOF', true, 'free', null),
    (:shop_p, 'Boutique Pro 63',   'pro-63',   'retail', 'XOF', true, 'pro',  current_date + 30);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop_f, :owner_f, 'owner', 'org', :shop_f, 'full'),
    (:shop_p, :owner_p, 'owner', 'org', :shop_p, 'full');
insert into products (id, org_id, name, sale_price, quantity, is_active, is_published) values
    (:p_f, :shop_f, 'Sucre', 750, 10, true, true),
    (:p_p, :shop_p, 'Pagne', 6000, 9, true, true);
insert into documents (org_id, r2_key, kind, uploaded_by) values
    (:shop_f, 'org/63f/devanture.jpg', 'photo', :owner_f);

\echo ''
\echo '--- TEST 1: a Free owner dresses the window with the basics ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '63636363-0000-0000-0000-000000000001';
select set_storefront_style('63000000-0000-0000-0000-000000000001', '{
    "tagline": "Le sucre du quartier",
    "hours": "Lun–Sam 8h–19h",
    "schedule": {"days": [6, 1, 2, 3, 4, 5], "open": "08:00", "close": "19:00"},
    "accent": "#2e7d5b",
    "cover_key": "org/63f/devanture.jpg",
    "layout": "list",
    "pinned": ["63aaaaaa-0000-0000-0000-000000000001"],
    "hide_out_of_stock": true
}');
do $$
declare v jsonb; s jsonb;
begin
    begin
        perform set_storefront_style('63000000-0000-0000-0000-000000000001',
                                     '{"accent": "#123456"}');
        raise exception 'FAIL: a Free owner took a colour outside the six';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like 'Kaj Pro :%' then
            raise exception 'FAIL: the colour refusal does not open the Pro door — %', sqlerrm;
        end if;
    end;
    select storefront_style into s from orgs where id = '63000000-0000-0000-0000-000000000001';
    if s ? 'layout' or s ? 'pinned' or s ? 'hide_out_of_stock' then
        raise exception 'FAIL: a Free owner wrote the arrangement: %', s;
    end if;
    if s -> 'schedule' <> '{"days": [1, 2, 3, 4, 5, 6], "open": "08:00", "close": "19:00"}'::jsonb then
        raise exception 'FAIL: the schedule is stored as %', s -> 'schedule';
    end if;
    raise notice 'PASS: basics written, arrangement not, other colours are Pro';
end $$;
commit;
begin;
set local role anon;
do $$
declare v jsonb;
begin
    select style into v from storefront('libre-63');
    if v ->> 'tagline' <> 'Le sucre du quartier' or v ->> 'accent' <> '#2E7D5B'
       or v ->> 'cover_key' <> 'org/63f/devanture.jpg' or not v ? 'schedule'
       or v ? 'open_now' or v ? 'layout' then
        raise exception 'FAIL: the street reads %', v;
    end if;
    if not storefront_photo_allowed('org/63f/devanture.jpg') then
        raise exception 'FAIL: a Free cover cannot be served';
    end if;
    raise notice 'PASS: the street reads the basics, no banner, the cover is served';
end $$;
commit;

\echo ''
\echo '--- TEST 2: Pro writes the layout; the street reads it with the banner ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '63636363-0000-0000-0000-000000000002';
select set_storefront_style('63000000-0000-0000-0000-000000000002', '{
    "layout": "menu",
    "accent": "#123456",
    "pinned": ["63aaaaaa-0000-0000-0000-000000000002"],
    "schedule": {"days": [1,2,3,4,5,6,7], "open": "00:00", "close": "23:59"}
}');
do $$
declare v_case text; v_cases text[] := array[
    '{"layout": "mosaic"}',
    '{"schedule": {"days": [], "open": "08:00", "close": "19:00"}}',
    '{"schedule": {"days": [8], "open": "08:00", "close": "19:00"}}',
    '{"schedule": {"days": [1, 1], "open": "08:00", "close": "19:00"}}',
    '{"schedule": {"days": [1], "open": "8h", "close": "19:00"}}',
    '{"schedule": {"days": [1], "open": "08:00", "close": "08:00"}}'
];
begin
    foreach v_case in array v_cases loop
        begin
            perform set_storefront_style('63000000-0000-0000-0000-000000000002', v_case::jsonb);
            raise exception 'FAIL: accepted %', v_case;
        exception when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
        end;
    end loop;
    raise notice 'PASS: an unknown layout and five bad schedules refused';
end $$;
commit;
begin;
set local role anon;
do $$
declare v jsonb;
begin
    select style into v from storefront('pro-63');
    if v ->> 'layout' <> 'menu' or v ->> 'accent' <> '#123456'
       or v -> 'pinned' ->> 0 <> '63aaaaaa-0000-0000-0000-000000000002' then
        raise exception 'FAIL: the Pro street reads %', v;
    end if;
    if not v ? 'open_now' then
        raise exception 'FAIL: a Pro window with a schedule has no banner: %', v;
    end if;
    raise notice 'PASS: layout, any colour, pins and the banner on the Pro street';
end $$;
commit;

\echo ''
\echo '--- TEST 3: a lapsed Pro keeps its arrangement through a basics save ---'
update orgs set plan = 'free', plan_until = null
 where id = '63000000-0000-0000-0000-000000000002';
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '63636363-0000-0000-0000-000000000002';
select set_storefront_style('63000000-0000-0000-0000-000000000002',
    '{"tagline": "Toujours là", "layout": "grid"}');
do $$
declare s jsonb; v jsonb;
begin
    select storefront_style into s from orgs where id = '63000000-0000-0000-0000-000000000002';
    if s ->> 'layout' <> 'menu' or s -> 'pinned' is null or s ->> 'tagline' <> 'Toujours là' then
        raise exception 'FAIL: the arrangement was lost: %', s;
    end if;
    select style into v from storefront('pro-63');
    if v ? 'layout' or v ? 'pinned' or v ? 'open_now' then
        raise exception 'FAIL: a lapsed Pro still arranges the street: %', v;
    end if;
    raise notice 'PASS: kept, and the street shows only the basics';
end $$;
commit;

\echo ''
\echo '--- TEST 4: the banner follows the clock ---'
do $$
declare
    v_now time := (now() at time zone 'Africa/Ouagadougou')::time;
    v_day int  := extract(isodow from now() at time zone 'Africa/Ouagadougou')::int;
    v_other int := case when v_day = 7 then 1 else v_day + 1 end;
    v_prev  int := case when v_day = 1 then 7 else v_day - 1 end;
begin
    if vitrine_open_now(jsonb_build_object('days', jsonb_build_array(v_day),
           'open', left((v_now - interval '1 hour')::text, 5),
           'close', left((v_now + interval '1 hour')::text, 5))) is not true
       and v_now between '01:00' and '22:59' then
        raise exception 'FAIL: open now is not open';
    end if;
    if vitrine_open_now(jsonb_build_object('days', jsonb_build_array(v_other),
           'open', '00:00', 'close', '23:59')) is not false then
        raise exception 'FAIL: another day reads open';
    end if;
    -- A night shop opened yesterday evening, closing later today.
    if v_now < '22:00' and vitrine_open_now(jsonb_build_object(
           'days', jsonb_build_array(v_prev),
           'open', '23:00', 'close', left((v_now + interval '1 hour')::text, 5))) is not true
       and v_now < '22:30' then
        raise exception 'FAIL: the night shop past midnight reads closed';
    end if;
    if vitrine_open_now(null) is not null then
        raise exception 'FAIL: no schedule gives a banner';
    end if;
    if has_function_privilege('anon', 'vitrine_open_now(jsonb)', 'execute')
       or has_function_privilege('anon', 'set_storefront_style(uuid, jsonb)', 'execute') then
        raise exception 'FAIL: anon reaches an internal function';
    end if;
    raise notice 'PASS: open, another day, past midnight, none';
end $$;

\echo ''
\echo 'test_vitrine_dressing: all passed'
