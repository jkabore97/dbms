-- ============================================================
-- test_batch143.sql — « Mettre en avant » for a service too (143).
--
-- The claims, for a shop, a farm and an association alike:
--   * a service on the vitrine with a photo and a price is asked « à la
--     une » though it has no stock (quantity 0, stock followed), and
--     spot_ineligible finds nothing wrong with it;
--   * an article still needs its stock: one at 0, followed, is refused,
--     and spot_ineligible says why;
--   * a service needs its photo and its price like an article;
--   * request_promotion stays authenticated's, spot_ineligible nobody's
--     but the definer doors'; run twice the same.
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
grant usage on all sequences in schema public to authenticated;
\i database/migrations/143_spots_services.sql
\i database/migrations/143_spots_services.sql
update platform_settings set value = '0' where key in ('vitrine_min_items', 'vitrine_min_items_association');

\set sowner '''14314314-0000-0000-0000-000000000001'''
\set aowner '''14314314-0000-0000-0000-000000000002'''
\set fowner '''14314314-0000-0000-0000-000000000003'''
\set shop   '''14300000-0000-0000-0000-000000000001'''
\set assoc  '''14300000-0000-0000-0000-000000000002'''
\set farm   '''14300000-0000-0000-0000-000000000003'''

create or replace function pg_temp.ask143(p_owner uuid, p_org uuid, p_product uuid)
returns text
language plpgsql
as $$
declare v uuid;
begin
    perform set_config('request.jwt.claim.sub', p_owner::text, true),
            set_config('request.jwt.claims',
                       json_build_object('sub', p_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v := request_promotion(p_org, p_product, 7);
    execute 'reset role';
    return coalesce(v::text, '(null)');
exception when others then
    execute 'reset role';
    return 'ERR: ' || sqlerrm;
end;
$$;

insert into auth.users (id, phone, email, email_confirmed_at, raw_user_meta_data) values
    (:sowner, '+22614301001', 'salon143@example.org',   now(), '{"full_name": "Salon Prestige"}'),
    (:aowner, '+22614301002', 'espoir143@example.org',  now(), '{"full_name": "Fondation Espoir"}'),
    (:fowner, '+22614301003', 'horizon143@example.org', now(), '{"full_name": "Ferme Horizon Vert"}');
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled) values
    (:shop,  'Salon Prestige',     'salon-prestige-143',   'retail',      'XOF', true),
    (:assoc, 'Fondation Espoir',   'fondation-espoir-143', 'association', 'XOF', true),
    (:farm,  'Ferme Horizon Vert', 'horizon-vert-143',     'farm',        'XOF', true);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :sowner, 'owner', 'org', :shop,  'full'),
    (:assoc, :aowner, 'owner', 'org', :assoc, 'full'),
    (:farm,  :fowner, 'owner', 'org', :farm,  'full');
-- Services and articles at 0, stock followed (131's default).
insert into products (id, org_id, name, sale_price, quantity, is_active, is_published, is_service) values
    ('143aaaaa-0000-0000-0000-000000000001', :shop,  'Coupe et coiffage',   5000, 0, true, true, true),
    ('143aaaaa-0000-0000-0000-000000000002', :assoc, 'Location de salle',  25000, 0, true, true, true),
    ('143aaaaa-0000-0000-0000-000000000003', :farm,  'Visite de la ferme',  2000, 0, true, true, true),
    ('143aaaaa-0000-0000-0000-000000000004', :shop,  'Shampoing épuisé',    3000, 0, true, true, false),
    ('143aaaaa-0000-0000-0000-000000000005', :shop,  'Manucure sans photo', 4000, 0, true, true, true);
update products set stock_tracked = true where id::text like '143aaaaa-%';
insert into documents (org_id, r2_key, kind, uploaded_by, product_id)
select p.org_id, 'org/' || p.org_id || '/' || p.id || '.jpg', 'photo',
       (select user_id from memberships m where m.org_id = p.org_id and m.role = 'owner' limit 1), p.id
  from products p where p.id::text like '143aaaaa-%' and p.name <> 'Manucure sans photo';

\echo ''
\echo '--- TEST 1: a service is asked « à la une » though it has no stock ---'
do $$
declare v text;
begin
    v := pg_temp.ask143('14314314-0000-0000-0000-000000000001', '14300000-0000-0000-0000-000000000001', '143aaaaa-0000-0000-0000-000000000001');
    if v like 'ERR:%' then raise exception 'FAIL: a shop''s service refused: %', v; end if;
    v := pg_temp.ask143('14314314-0000-0000-0000-000000000002', '14300000-0000-0000-0000-000000000002', '143aaaaa-0000-0000-0000-000000000002');
    if v like 'ERR:%' then raise exception 'FAIL: an association''s service refused: %', v; end if;
    v := pg_temp.ask143('14314314-0000-0000-0000-000000000003', '14300000-0000-0000-0000-000000000003', '143aaaaa-0000-0000-0000-000000000003');
    if v like 'ERR:%' then raise exception 'FAIL: a farm''s service refused: %', v; end if;
    if spot_ineligible('14300000-0000-0000-0000-000000000001', '143aaaaa-0000-0000-0000-000000000001') is not null then
        raise exception 'FAIL: spot_ineligible finds fault with a service: %',
            spot_ineligible('14300000-0000-0000-0000-000000000001', '143aaaaa-0000-0000-0000-000000000001');
    end if;
    raise notice 'PASS: a service of a shop, an association and a farm is asked « à la une »';
end $$;

\echo ''
\echo '--- TEST 2: an article still needs its stock, a service its photo ---'
do $$
declare v text;
begin
    v := pg_temp.ask143('14314314-0000-0000-0000-000000000001', '14300000-0000-0000-0000-000000000001', '143aaaaa-0000-0000-0000-000000000004');
    if v not like 'ERR:%' then raise exception 'FAIL: an article out of stock was asked'; end if;
    if spot_ineligible('14300000-0000-0000-0000-000000000001', '143aaaaa-0000-0000-0000-000000000004') is null then
        raise exception 'FAIL: spot_ineligible lets an article out of stock through';
    end if;
    v := pg_temp.ask143('14314314-0000-0000-0000-000000000001', '14300000-0000-0000-0000-000000000001', '143aaaaa-0000-0000-0000-000000000005');
    if v not like 'ERR:%' then raise exception 'FAIL: a service with no photo was asked'; end if;
    raise notice 'PASS: an article out of stock and a service with no photo are refused';
end $$;

\echo ''
\echo '--- TEST 3: the doors ---'
do $$
begin
    if not has_function_privilege('authenticated', 'request_promotion(uuid, uuid, integer)', 'execute') then
        raise exception 'FAIL: request_promotion closed to authenticated';
    end if;
    if has_function_privilege('anon', 'request_promotion(uuid, uuid, integer)', 'execute')
       or has_function_privilege('anon', 'spot_ineligible(uuid, uuid)', 'execute') then
        raise exception 'FAIL: a spot door open to anon';
    end if;
    raise notice 'PASS: request_promotion authenticated''s, nothing for anon';
end $$;

\echo ''
\echo 'test_batch143: all claims passed'
