-- ============================================================
-- test_vitrine_plus.sql — a Pro business dresses its window; a Free one is shown the door (068).
-- Phone block 40.
--
-- The claims: a Free owner is refused with the sentence that opens the
-- door to pay, and the street sees the common design; a Pro owner sets a
-- tagline, hours, a colour, a cover, pinned articles and the stock switch,
-- the street reads exactly that, unknown keys are dropped, and the cover
-- becomes servable; what is not the business's own — a cover from another
-- shop, a pinned article from another shop — is refused, as are a long
-- tagline, a bad colour and a seventh pin; a lapsed Pro keeps what it
-- wrote and the street stops showing it; and the tool is on the Pro list.
-- ============================================================
\set ON_ERROR_STOP on

\set plat      '''40404040-0000-0000-0000-000000000001'''
\set owner_f   '''40404040-0000-0000-0000-000000000002'''
\set owner_p   '''40404040-0000-0000-0000-000000000003'''
\set shop_f    '''40000000-0000-0000-0000-000000000001'''
\set shop_p    '''40000000-0000-0000-0000-000000000002'''
\set p_free    '''40aaaaaa-0000-0000-0000-000000000001'''
\set p_pro1    '''40aaaaaa-0000-0000-0000-000000000002'''
\set p_pro2    '''40aaaaaa-0000-0000-0000-000000000003'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:plat,    '+22640000001', '{"full_name": "Plateforme"}'),
    (:owner_f, '+22640000002', '{"full_name": "Libre"}'),
    (:owner_p, '+22640000003', '{"full_name": "Pro"}');
update profiles set is_platform_admin = true where id = :plat;
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, plan, plan_until) values
    (:shop_f, 'Boutique Libre', 'libre-40', 'retail', 'XOF', true, 'free', null),
    (:shop_p, 'Boutique Pro',   'pro-40',   'retail', 'XOF', true, 'pro',  current_date + 30);
select seed_retail_accounts(:shop_f);
select seed_retail_accounts(:shop_p);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop_f, :owner_f, 'owner', 'org', :shop_f, 'full'),
    (:shop_p, :owner_p, 'owner', 'org', :shop_p, 'full');
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published, created_by) values
    (:p_free, :shop_f, 'Sucre', 750,  450, 10, true, true, :owner_f),
    (:p_pro1, :shop_p, 'Pagne', 6000, 4000, 9, true, true, :owner_p),
    (:p_pro2, :shop_p, 'Gâteau', 2500, 1200, 0, true, true, :owner_p);
insert into documents (org_id, r2_key, kind, uploaded_by) values
    (:shop_p, 'org/40p/devanture.jpg', 'photo', :owner_p),
    (:shop_f, 'org/40f/devanture.jpg', 'photo', :owner_f);


\echo ''
\echo '--- TEST 1: a Free owner is shown the door; the street sees the common design ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '40404040-0000-0000-0000-000000000002';
do $$
declare v jsonb;
begin
    begin
        perform set_storefront_style('40000000-0000-0000-0000-000000000001',
                                     '{"tagline": "Le meilleur sucre"}');
        raise exception 'FAIL: a Free owner dressed the window';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like 'Kaj Pro :%' then
            raise exception 'FAIL: the refusal does not open the door to pay — %', sqlerrm;
        end if;
    end;
    select style into v from storefront('libre-40');
    if v <> '{}'::jsonb then
        raise exception 'FAIL: the Free window carries a style: %', v;
    end if;
    if not (plan_terms() -> 'pro_features') ? 'vitrine_plus' then
        raise exception 'FAIL: vitrine_plus is not on the Pro list';
    end if;
    raise notice 'PASS: Free refused with the Kaj Pro sentence; the street sees {}; the tool is on the list';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: a Pro owner dresses the window and the street reads exactly that ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '40404040-0000-0000-0000-000000000003';
select set_storefront_style('40000000-0000-0000-0000-000000000002', '{
    "tagline": "  Pagnes et gâteaux depuis 1998  ",
    "hours": "Lun–Sam 8h–19h",
    "accent": "#b1541a",
    "cover_key": "org/40p/devanture.jpg",
    "pinned": ["40aaaaaa-0000-0000-0000-000000000003", "40aaaaaa-0000-0000-0000-000000000002"],
    "hide_out_of_stock": true,
    "font": "comic sans",
    "evil": "<script>"
}');
set local "request.jwt.claim.sub" = '';
do $$
declare v jsonb;
begin
    select style into v from storefront('pro-40');
    if v ->> 'tagline' <> 'Pagnes et gâteaux depuis 1998'
       or v ->> 'hours' <> 'Lun–Sam 8h–19h'
       or v ->> 'accent' <> '#B1541A'
       or v ->> 'cover_key' <> 'org/40p/devanture.jpg'
       or v -> 'pinned' <> '["40aaaaaa-0000-0000-0000-000000000003", "40aaaaaa-0000-0000-0000-000000000002"]'::jsonb
       or (v -> 'hide_out_of_stock') <> 'true'::jsonb then
        raise exception 'FAIL: the street reads %', v;
    end if;
    if v ? 'font' or v ? 'evil' then
        raise exception 'FAIL: an unknown key was kept: %', v;
    end if;
    if not storefront_photo_allowed('org/40p/devanture.jpg') then
        raise exception 'FAIL: the cover cannot be served to the street';
    end if;
    raise notice 'PASS: tagline trimmed, hours, colour upper-cased, cover, pins, switch; unknown keys dropped; cover servable';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: what is not the business''s own, or not within the design, is refused ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '40404040-0000-0000-0000-000000000003';
do $$
declare v_cases text[] := array[
    '{"cover_key": "org/40f/devanture.jpg"}',
    '{"pinned": ["40aaaaaa-0000-0000-0000-000000000001"]}',
    '{"pinned": ["40aaaaaa-0000-0000-0000-000000000002", "40aaaaaa-0000-0000-0000-000000000002"]}',
    '{"pinned": ["a","b","c","d","e","f","g"]}',
    '{"accent": "orange"}',
    '{"tagline": "' || repeat('x', 81) || '"}'
];
    v_case text; v_style jsonb;
begin
    foreach v_case in array v_cases loop
        begin
            perform set_storefront_style('40000000-0000-0000-0000-000000000002', v_case::jsonb);
            raise exception 'FAIL: accepted %', v_case;
        exception when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
        end;
    end loop;
    select storefront_style into v_style from orgs
     where id = '40000000-0000-0000-0000-000000000002';
    if v_style <> '{}'::jsonb then
        raise exception 'FAIL: a refused style was stored: %', v_style;
    end if;
    -- Null clears everything, without a word.
    perform set_storefront_style('40000000-0000-0000-0000-000000000002', '{"tagline": "x"}');
    perform set_storefront_style('40000000-0000-0000-0000-000000000002', null);
    select storefront_style into v_style from orgs
     where id = '40000000-0000-0000-0000-000000000002';
    if v_style <> '{}'::jsonb then
        raise exception 'FAIL: null did not clear the style: %', v_style;
    end if;
    raise notice 'PASS: another shop''s cover and article, a double pin, seven pins, a bad colour and a long tagline refused; null clears';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: a lapsed Pro keeps what it wrote; the street stops showing it ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '40404040-0000-0000-0000-000000000003';
select set_storefront_style('40000000-0000-0000-0000-000000000002',
    '{"tagline": "Depuis 1998", "cover_key": "org/40p/devanture.jpg"}');
set local "request.jwt.claim.sub" = '40404040-0000-0000-0000-000000000001';
select set_org_plan('40000000-0000-0000-0000-000000000002', 'pro', current_date - 1, 'échu');
set local "request.jwt.claim.sub" = '';
do $$
declare v jsonb; v_kept jsonb;
begin
    select style into v from storefront('pro-40');
    if v <> '{}'::jsonb then
        raise exception 'FAIL: a lapsed Pro still dresses the street: %', v;
    end if;
    select storefront_style into v_kept from orgs
     where id = '40000000-0000-0000-0000-000000000002';
    if v_kept ->> 'tagline' <> 'Depuis 1998' then
        raise exception 'FAIL: lapsing lost what was written: %', v_kept;
    end if;
    if storefront_photo_allowed('org/40p/devanture.jpg') then
        raise exception 'FAIL: a lapsed Pro''s cover is still served';
    end if;
    raise notice 'PASS: the street reads {}, the words are kept, the cover is no longer served';
end $$;
rollback;

\echo ''
\echo 'test_vitrine_plus.sql: all tests passed'
