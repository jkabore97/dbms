-- ============================================================
-- test_vitrine_minimum.sql — 8 items before the public sees a vitrine;
-- sponsoring pays on its own (092). Phone block 62.
--
-- The claims: with 7 items on sale a vitrine is hidden from the public and
-- from the street, but its own people still see it; the 8th opens it; one
-- item no longer makes the vitrine's first step; and a sponsor is paid the
-- moment the business it brought in finishes its 3rd order with a
-- complete vitrine — without anyone opening « Mes cauris » — and sees what
-- it earned.
-- ============================================================
\set ON_ERROR_STOP on

\set owner   '''62626262-0000-0000-0000-000000000001'''
\set sponsor '''62626262-0000-0000-0000-000000000002'''
\set buyer   '''62626262-0000-0000-0000-000000000003'''
\set shop    '''62000000-0000-0000-0000-000000000001'''
\set parrain '''62000000-0000-0000-0000-000000000002'''

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
\i database/migrations/092_vitrine_minimum_and_referrals.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,   '+22662000001', '{"full_name": "Awa"}'),
    (:sponsor, '+22662000002', '{"full_name": "Parrain"}'),
    (:buyer,   '+22662000003', '{"full_name": "Client"}');
insert into orgs (id, name, slug, profile, default_currency, progress_since,
                  storefront_enabled, storefront_blurb, phone, address, lat, lng, referred_by) values
    (:parrain, 'Parrain 62', 'parrain-62', 'retail', 'XOF', null, false, null, null, null, null, null, null),
    (:shop, 'Boutique 62', 'boutique-62', 'retail', 'XOF', null, true,
     'Le riz du quartier', '+22662000001', 'Gounghin', 12.37, -1.52, :parrain);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,    :owner,   'owner', 'org', :shop,    'full'),
    (:parrain, :sponsor, 'owner', 'org', :parrain, 'full');
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
select :shop, 'Article ' || i, 100, 5, true, true from generate_series(1, 7) i;
insert into documents (org_id, product_id, kind, r2_key, uploaded_by)
select org_id, id, 'product_photo', 'p/' || id, :owner from products where org_id = :shop;

\echo ''
\echo '--- TEST 1: 7 items: hidden from the public, seen by its own ---'
begin;
set local role anon;
do $$ begin
    if storefront_open('boutique-62') is not null then
        raise exception 'FAIL: a 7-item vitrine is public';
    end if;
    if exists (select 1 from storefront_directory() where slug = 'boutique-62') then
        raise exception 'FAIL: a 7-item vitrine is on the street';
    end if;
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '62626262-0000-0000-0000-000000000001';
do $$ begin
    if storefront_open('boutique-62') is null then
        raise exception 'FAIL: the owner cannot see their own vitrine';
    end if;
    if vitrine_score('62000000-0000-0000-0000-000000000001') >= 100 then
        raise exception 'FAIL: 7 items count as the first step';
    end if;
    if (vitrine_checklist('62000000-0000-0000-0000-000000000001') ->> 'min_items')::int <> 8 then
        raise exception 'FAIL: the checklist does not say the minimum';
    end if;
    raise notice 'PASS: hidden at 7, the owner still sees it';
end $$;
commit;

\echo ''
\echo '--- TEST 2: the 8th item opens it ---'
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
values ('62000000-0000-0000-0000-000000000001', 'Article 8', 100, 5, true, true);
begin;
set local role anon;
do $$ begin
    if storefront_open('boutique-62') is null then
        raise exception 'FAIL: 8 items do not open the vitrine';
    end if;
    if not exists (select 1 from storefront_directory() where slug = 'boutique-62') then
        raise exception 'FAIL: 8 items do not reach the street';
    end if;
    raise notice 'PASS: public with 8';
end $$;
commit;

\echo ''
\echo '--- TEST 3: the sponsor is paid at the 3rd finished order, unasked ---'
insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency)
select '62000000-0000-0000-0000-000000000001', '62626262-0000-0000-0000-000000000003',
       'Client', 'ready', 'pickup', 1000, 'XOF'
  from generate_series(1, 3);
update orders set status = 'picked_up'
 where org_id = '62000000-0000-0000-0000-000000000001'
   and id in (select id from orders where org_id = '62000000-0000-0000-0000-000000000001' limit 2);
do $$ begin
    if exists (select 1 from cauris_ledger where org_id = '62000000-0000-0000-0000-000000000002'
                and reason = 'referral') then
        raise exception 'FAIL: the sponsor was paid after 2 orders';
    end if;
end $$;
update orders set status = 'picked_up'
 where org_id = '62000000-0000-0000-0000-000000000001' and status = 'ready';
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '62626262-0000-0000-0000-000000000002';
do $$
declare w jsonb := my_cauris('62000000-0000-0000-0000-000000000002');
begin
    if (w ->> 'balance')::int <> 200 then
        raise exception 'FAIL: the sponsor has % cauris, not 200', w ->> 'balance';
    end if;
    if (w ->> 'referral_points')::int <> 200
       or (w -> 'referrals' -> 0 ->> 'paid')::boolean is not true
       or (w -> 'referrals' -> 0 ->> 'name') <> 'Boutique 62' then
        raise exception 'FAIL: the wallet does not say what sponsoring paid: %', w;
    end if;
    raise notice 'PASS: 200 cauris at the 3rd order, said in the wallet';
end $$;
commit;
do $$ begin
    if has_function_privilege('anon', 'referral_check(uuid)', 'execute')
       or has_function_privilege('authenticated', 'referral_check(uuid)', 'execute') then
        raise exception 'FAIL: anyone can trigger a referral check';
    end if;
end $$;

\echo ''
\echo 'test_vitrine_minimum: all passed'
