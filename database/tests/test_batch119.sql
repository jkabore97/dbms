-- ============================================================
-- test_batch119.sql — a harvest that goes into what the farm sells (119).
--
-- The claims:
--   * P1: a harvest called as before (no p_to_stock, 019's positional
--     call and the app's named one) moves no article and books nothing;
--   * « Gardée en stock »: the farm's article of the crop's name gains
--     the quantity; none yet, it is made — the harvest's unit, price 0,
--     OFF the vitrine, an article not a service — and nobody following
--     the vitrine is rung for it; one put away comes back; its price and
--     vitrine switch are left as they were; no journal entry, ever;
--   * a retry (the same client uuid) counts the shelf once;
--   * an article counted in another unit, or a service of that name, is
--     refused in French and nothing is written — not the harvest either;
--   * someone who may not write for the farm (an observer, another farm)
--     is refused;
--   * the doors: 019's signature is gone, the new one closed to anon and
--     PUBLIC, open to authenticated.
-- Kinds: a farm only — crop cycles exist nowhere else.
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
-- Earlier suites hand the app's roles every function: 119 again, so its
-- own doors are what is tested.
\i database/migrations/119_farm_harvest_stock.sql

\set owner '''11911911-0000-0000-0000-000000000001'''
\set seer  '''11911911-0000-0000-0000-000000000002'''
\set rival '''11911911-0000-0000-0000-000000000003'''

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22611900001', '{"full_name": "Ignace"}'),
    (:seer,  '+22611900002', '{"full_name": "Observateur"}'),
    (:rival, '+22611900003', '{"full_name": "Voisin"}');

insert into orgs (id, name, slug, profile, default_currency) values
    ('11900000-0000-0000-0000-000000000001', 'Ferme 119',   'ferme-119',   'farm', 'XOF'),
    ('11900000-0000-0000-0000-000000000002', 'Voisine 119', 'voisine-119', 'farm', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    ('11900000-0000-0000-0000-000000000001', :owner, 'owner',    'org', '11900000-0000-0000-0000-000000000001'),
    ('11900000-0000-0000-0000-000000000001', :seer,  'observer', 'org', '11900000-0000-0000-0000-000000000001'),
    ('11900000-0000-0000-0000-000000000002', :rival, 'owner',    'org', '11900000-0000-0000-0000-000000000002');

select seed_farm_accounts('11900000-0000-0000-0000-000000000001');

insert into crop_cycles (id, org_id, crop, unit) values
    ('119cccc0-0000-0000-0000-000000000001', '11900000-0000-0000-0000-000000000001', 'Tomate', 'kg'),
    ('119cccc0-0000-0000-0000-000000000002', '11900000-0000-0000-0000-000000000001', 'Gombo',  'kg'),
    ('119cccc0-0000-0000-0000-000000000003', '11900000-0000-0000-0000-000000000001', 'Oignon', 'kg'),
    ('119cccc0-0000-0000-0000-000000000004', '11900000-0000-0000-0000-000000000001', 'Labour', 'kg'),
    ('119cccc0-0000-0000-0000-000000000005', '11900000-0000-0000-0000-000000000001', 'Piment', 'kg');

-- What the farm already sells: Gombo by the kg, priced and on the vitrine;
-- Oignon by the sac; Piment put away; « Labour » a service (098).
insert into products (id, org_id, name, sale_price, quantity, unit, is_published, is_service, is_active) values
    ('119aaaa0-0000-0000-0000-000000000002', '11900000-0000-0000-0000-000000000001', 'Gombo',  750, 4, 'kg',  true,  false, true),
    ('119aaaa0-0000-0000-0000-000000000003', '11900000-0000-0000-0000-000000000001', 'Oignon', 9000, 2, 'sac', true,  false, true),
    ('119aaaa0-0000-0000-0000-000000000004', '11900000-0000-0000-0000-000000000001', 'Labour', 15000, 0, null, true,  true,  true),
    ('119aaaa0-0000-0000-0000-000000000005', '11900000-0000-0000-0000-000000000001', 'Piment', 500, 0, 'kg',  false, false, false);

\echo ''
\echo '--- TEST 1 (P1): a harvest as before moves no article and books nothing ---'
begin;
set local "request.jwt.claim.sub" = '11911911-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_h1 uuid; v_h2 uuid;
    v_products text; v_after text;
    v_journal int;
begin
    select string_agg(id || ':' || quantity || ':' || is_active, ',' order by id) into v_products
    from products where org_id = '11900000-0000-0000-0000-000000000001';
    select count(*) into v_journal from journal_entries where org_id = '11900000-0000-0000-0000-000000000001';

    -- 019's positional call, and the app's named one without the new word.
    v_h1 := record_harvest('11900000-0000-0000-0000-000000000001', '119cccc0-0000-0000-0000-000000000002', 10);
    v_h2 := record_harvest(p_org_id => '11900000-0000-0000-0000-000000000001',
                           p_crop_cycle_id => '119cccc0-0000-0000-0000-000000000001',
                           p_quantity => 5, p_grade => 'second');

    select string_agg(id || ':' || quantity || ':' || is_active, ',' order by id) into v_after
    from products where org_id = '11900000-0000-0000-0000-000000000001';
    if v_after is distinct from v_products then
        raise exception 'FAIL: a harvest as before moved an article: % -> %', v_products, v_after;
    end if;
    if exists (select 1 from products where org_id = '11900000-0000-0000-0000-000000000001' and name = 'Tomate') then
        raise exception 'FAIL: a harvest as before made an article';
    end if;
    if exists (select 1 from harvests where id in (v_h1, v_h2) and product_id is not null) then
        raise exception 'FAIL: a harvest as before names an article';
    end if;
    if (select count(*) from journal_entries where org_id = '11900000-0000-0000-0000-000000000001') <> v_journal then
        raise exception 'FAIL: a harvest booked an entry';
    end if;
    raise notice 'PASS: 10 kg of gombo and 5 kg of tomatoes counted, no article moved, nothing booked';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: « Gardée en stock » — a new article, off the vitrine, nobody rung ---'
-- Somebody follows the farm's vitrine (113): a new article put on the street
-- rings them. This one is not on the street.
insert into vitrine_follows (user_id, org_id)
select :rival, '11900000-0000-0000-0000-000000000001'
where to_regclass('public.vitrine_follows') is not null;
begin;
set local "request.jwt.claim.sub" = '11911911-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_h uuid;
    v_p products%rowtype;
    v_journal int;
    v_bell int;
begin
    select count(*) into v_journal from journal_entries where org_id = '11900000-0000-0000-0000-000000000001';
    select count(*) into v_bell from notifications;

    v_h := record_harvest(p_org_id => '11900000-0000-0000-0000-000000000001',
                          p_crop_cycle_id => '119cccc0-0000-0000-0000-000000000001',
                          p_quantity => 30, p_to_stock => true);

    select * into v_p from products
    where org_id = '11900000-0000-0000-0000-000000000001' and name = 'Tomate';
    if not found then
        raise exception 'FAIL: no Tomate article';
    end if;
    if v_p.quantity <> 30 or v_p.unit <> 'kg' or v_p.sale_price <> 0
       or v_p.is_published or v_p.is_service or not v_p.is_active then
        raise exception 'FAIL: Tomate made as % % price % published % service %',
            v_p.quantity, v_p.unit, v_p.sale_price, v_p.is_published, v_p.is_service;
    end if;
    if (select product_id from harvests where id = v_h) is distinct from v_p.id then
        raise exception 'FAIL: the harvest does not name its article';
    end if;
    if (select count(*) from journal_entries where org_id = '11900000-0000-0000-0000-000000000001') <> v_journal then
        raise exception 'FAIL: stocking a harvest booked an entry';
    end if;
    if (select count(*) from notifications) <> v_bell then
        raise exception 'FAIL: an unpriced article off the vitrine rang somebody';
    end if;
    raise notice 'PASS: 30 kg of Tomate made, price 0, off the vitrine, nothing booked, nobody rung';
end $$;
commit;

\echo ''
\echo '--- TEST 3: an article already sold gains the harvest; its price and switch stay; a retry counts once ---'
begin;
set local "request.jwt.claim.sub" = '11911911-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_a uuid; v_b uuid;
    v_p products%rowtype;
    v_uuid uuid := '119eeee0-0000-0000-0000-000000000001';
begin
    v_a := record_harvest(p_org_id => '11900000-0000-0000-0000-000000000001',
                          p_crop_cycle_id => '119cccc0-0000-0000-0000-000000000002',
                          p_quantity => 12.5, p_client_uuid => v_uuid, p_to_stock => true);
    v_b := record_harvest(p_org_id => '11900000-0000-0000-0000-000000000001',
                          p_crop_cycle_id => '119cccc0-0000-0000-0000-000000000002',
                          p_quantity => 12.5, p_client_uuid => v_uuid, p_to_stock => true);
    if v_a is distinct from v_b then
        raise exception 'FAIL: the retry made a second harvest';
    end if;
    select * into v_p from products where id = '119aaaa0-0000-0000-0000-000000000002';
    if v_p.quantity <> 16.5 then
        raise exception 'FAIL: 4 kg + 12.5 kg (sent twice) came to %', v_p.quantity;
    end if;
    if v_p.sale_price <> 750 or not v_p.is_published then
        raise exception 'FAIL: the harvest changed the price (%) or the switch (%)', v_p.sale_price, v_p.is_published;
    end if;
    if (select count(*) from harvests where client_uuid = v_uuid) <> 1 then
        raise exception 'FAIL: the retry wrote a second row';
    end if;
    raise notice 'PASS: Gombo 4 + 12.5 = 16.5 kg, sent twice, counted once, price and vitrine as they were';
end $$;
commit;

\echo ''
\echo '--- TEST 4: an article put away comes back with the harvest ---'
begin;
set local "request.jwt.claim.sub" = '11911911-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_p products%rowtype;
begin
    perform record_harvest(p_org_id => '11900000-0000-0000-0000-000000000001',
                           p_crop_cycle_id => '119cccc0-0000-0000-0000-000000000005',
                           p_quantity => 3, p_to_stock => true);
    select * into v_p from products where id = '119aaaa0-0000-0000-0000-000000000005';
    if not v_p.is_active or v_p.quantity <> 3 or v_p.is_published or v_p.sale_price <> 500 then
        raise exception 'FAIL: Piment back as active % qty % published % price %',
            v_p.is_active, v_p.quantity, v_p.is_published, v_p.sale_price;
    end if;
    if (select count(*) from products where org_id = '11900000-0000-0000-0000-000000000001' and lower(name) = 'piment') <> 1 then
        raise exception 'FAIL: a second Piment was made';
    end if;
    raise notice 'PASS: Piment back with 3 kg, its price kept, still off the vitrine';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: kilos are not added to sacks, nor to a service; nothing written ---'
begin;
set local "request.jwt.claim.sub" = '11911911-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_count int;
begin
    select count(*) into v_count from harvests where org_id = '11900000-0000-0000-0000-000000000001';
    begin
        perform record_harvest(p_org_id => '11900000-0000-0000-0000-000000000001',
                               p_crop_cycle_id => '119cccc0-0000-0000-0000-000000000003',
                               p_quantity => 40, p_to_stock => true);
        raise exception 'FAIL: 40 kg added to sacks of Oignon';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like '« Oignon » se vend par sac%' then
            raise exception 'FAIL: refused in other words: %', sqlerrm;
        end if;
        raise notice 'PASS: refused — %', sqlerrm;
    end;
    -- The same harvest counted in sacks goes in.
    perform record_harvest(p_org_id => '11900000-0000-0000-0000-000000000001',
                           p_crop_cycle_id => '119cccc0-0000-0000-0000-000000000003',
                           p_quantity => 1, p_unit => 'sac', p_to_stock => true);
    if (select quantity from products where id = '119aaaa0-0000-0000-0000-000000000003') <> 3 then
        raise exception 'FAIL: 2 sacs + 1 sac came to something else';
    end if;
    begin
        perform record_harvest(p_org_id => '11900000-0000-0000-0000-000000000001',
                               p_crop_cycle_id => '119cccc0-0000-0000-0000-000000000004',
                               p_quantity => 1, p_to_stock => true);
        raise exception 'FAIL: a harvest stocked onto a service';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like 'Un service porte déjà le nom%' then
            raise exception 'FAIL: refused in other words: %', sqlerrm;
        end if;
        raise notice 'PASS: refused — %', sqlerrm;
    end;
    if (select count(*) from harvests where org_id = '11900000-0000-0000-0000-000000000001') <> v_count + 1 then
        raise exception 'FAIL: a refused harvest was written anyway';
    end if;
    raise notice 'PASS: only the harvest in sacks was written';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: an observer, and another farm, are refused ---'
begin;
set local "request.jwt.claim.sub" = '11911911-0000-0000-0000-000000000002';
set local role authenticated;
do $$
begin
    perform record_harvest(p_org_id => '11900000-0000-0000-0000-000000000001',
                           p_crop_cycle_id => '119cccc0-0000-0000-0000-000000000001',
                           p_quantity => 1, p_to_stock => true);
    raise exception 'FAIL: an observer stocked a harvest';
exception when raise_exception then
    if sqlerrm like 'FAIL:%' then raise; end if;
    raise notice 'PASS: observer refused — %', sqlerrm;
end $$;
rollback;
begin;
set local "request.jwt.claim.sub" = '11911911-0000-0000-0000-000000000003';
set local role authenticated;
do $$
begin
    perform record_harvest(p_org_id => '11900000-0000-0000-0000-000000000002',
                           p_crop_cycle_id => '119cccc0-0000-0000-0000-000000000001',
                           p_quantity => 1, p_to_stock => true);
    raise exception 'FAIL: another farm harvested our tomatoes';
exception when raise_exception then
    if sqlerrm like 'FAIL:%' then raise; end if;
    raise notice 'PASS: another farm refused — %', sqlerrm;
end $$;
rollback;

\echo ''
\echo '--- TEST 7: the doors ---'
do $$
begin
    if to_regprocedure('record_harvest(uuid, uuid, numeric, text, text, date, text, uuid, text)') is not null then
        raise exception 'FAIL: 019''s signature is still there beside the new one';
    end if;
    if has_function_privilege('anon', 'record_harvest(uuid, uuid, numeric, text, text, date, text, uuid, text, boolean)', 'execute') then
        raise exception 'FAIL: the street may record a harvest';
    end if;
    if has_function_privilege('public', 'record_harvest(uuid, uuid, numeric, text, text, date, text, uuid, text, boolean)', 'execute') then
        raise exception 'FAIL: PUBLIC may record a harvest';
    end if;
    if not has_function_privilege('authenticated', 'record_harvest(uuid, uuid, numeric, text, text, date, text, uuid, text, boolean)', 'execute') then
        raise exception 'FAIL: a signed-in farmer may not record a harvest';
    end if;
    if not (select prosecdef from pg_proc where oid = 'record_harvest(uuid, uuid, numeric, text, text, date, text, uuid, text, boolean)'::regprocedure) then
        raise exception 'FAIL: record_harvest is no longer security definer';
    end if;
    raise notice 'PASS: one record_harvest, closed to the street and PUBLIC, open to the farm';
end $$;

-- Leave nothing for the suites after this one.
delete from vitrine_follows where org_id in ('11900000-0000-0000-0000-000000000001', '11900000-0000-0000-0000-000000000002');
