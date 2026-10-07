-- ============================================================
-- test_unlock_notices.sql — the bell when a tool opens (096). Phone block 65.
--
-- The claims: what was open before 096 is recorded as seen and rings
-- nothing; a Free shop filling its vitrine hears « Factures débloquées »
-- with its articles and three photos, « Production débloquée » once stage
-- 2 of Le Chemin (097) is complete, the credit book after its third
-- finished order — once each, even if the vitrine falls back and
-- climbs again; the home sees each unseen once, then nothing; Pro and an
-- association are never told; and none of it is open to anon or to
-- somebody outside the business.
-- ============================================================
\set ON_ERROR_STOP on
update platform_settings set value = '0' where key = 'vitrine_min_items';
update platform_settings set value = '0' where key = 'path_gates_open';
update platform_settings set value = '3' where key = 'progress_credit_orders';

\set owner '''65656565-0000-0000-0000-000000000001'''
\set prop  '''65656565-0000-0000-0000-000000000002'''
\set other '''65656565-0000-0000-0000-000000000003'''
\set shop  '''65000000-0000-0000-0000-000000000001'''
\set pro   '''65000000-0000-0000-0000-000000000002'''
\set assoc '''65000000-0000-0000-0000-000000000003'''
\set half  '''65000000-0000-0000-0000-000000000004'''

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

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22665000001', '{"full_name": "Awa"}'),
    (:prop,  '+22665000002', '{"full_name": "Pro"}'),
    (:other, '+22665000003', '{"full_name": "Voisin"}');
insert into orgs (id, name, slug, profile, default_currency, plan) values
    (:shop,  'Boutique 65', 'boutique-65', 'retail',      'XOF', 'free'),
    (:pro,   'Pro 65',      'pro-65',      'retail',      'XOF', 'pro'),
    (:assoc, 'Asso 65',     'asso-65',     'association', 'XOF', 'free'),
    (:half,  'Moitié 65',   'moitie-65',   'retail',      'XOF', 'free');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :owner, 'owner', 'org', :shop,  'full'),
    (:pro,   :prop,  'owner', 'org', :pro,   'full'),
    (:assoc, :owner, 'owner', 'org', :assoc, 'full'),
    (:half,  :owner, 'owner', 'org', :half,  'full');
-- Re-applied with the businesses there, for its grants and its seed: the
-- Pro shop and the association are open already, and recorded as seen.
-- Then 097, whose triggers and words replace 096's — in one transaction,
-- as the bundle runs them. « Moitié » had invoices open under 089's
-- percentages (a vitrine well filled, no photo): 096's seed recorded that
-- as seen. The steps still lock it, so 097 drops that row, and the bell
-- rings when the steps open it (TEST 6).
begin;
\i database/migrations/096_unlock_notices.sql
insert into org_unlocks (org_id, step, unlocked_at, seen_at)
values (:half, 'invoices', now(), now());
\i database/migrations/097_le_chemin.sql
commit;
do $$ begin
    if exists (select 1 from org_unlocks where org_id = '65000000-0000-0000-0000-000000000004') then
        raise exception 'FAIL: 097 kept 096''s seed row for a tool the steps still lock';
    end if;
    if (select count(*) from org_unlocks where org_id = '65000000-0000-0000-0000-000000000002') <> 3 then
        raise exception 'FAIL: 097 dropped the seed rows of a tool the steps leave open';
    end if;
end $$;

\echo ''
\echo '--- TEST 1: what was open is seen; nothing rang ---'
do $$ begin
    if (select count(*) from org_unlocks where org_id = '65000000-0000-0000-0000-000000000002') <> 3
       or exists (select 1 from org_unlocks where seen_at is null
                   and org_id = '65000000-0000-0000-0000-000000000002') then
        raise exception 'FAIL: the seed did not record what was open as seen';
    end if;
    if exists (select 1 from org_unlocks where org_id = '65000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the new shop has a step open already';
    end if;
    if exists (select 1 from notifications where kind = 'unlock'
                and org_id in ('65000000-0000-0000-0000-000000000001',
                               '65000000-0000-0000-0000-000000000002')) then
        raise exception 'FAIL: the seed rang a bell';
    end if;
    raise notice 'PASS: the doors open before 096 are seen, nobody told';
end $$;

\echo ''
\echo '--- TEST 2: invoices with the photos, production with stage 2, each rung once ---'
-- Articles, blurb, phone, address; the photos next; the pin and the first
-- sale complete stage 2.
update orgs set storefront_enabled = true, storefront_blurb = 'Le riz du quartier',
               phone = '+22665000001', address = 'Gounghin'
 where id = :shop;
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
select :shop, 'Article ' || i, 100, 5, true, true from generate_series(1, 3) i;
do $$ begin
    if exists (select 1 from org_unlocks where org_id = '65000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: a step opened before the photos';
    end if;
end $$;
insert into documents (org_id, product_id, kind, r2_key, uploaded_by)
select org_id, id, 'product_photo', 'p/' || id, :owner from products where org_id = :shop;
do $$ begin
    if (select array_agg(step) from org_unlocks
         where org_id = '65000000-0000-0000-0000-000000000001') <> array['invoices'] then
        raise exception 'FAIL: with the photos the open steps are %',
            (select array_agg(step) from org_unlocks where org_id = '65000000-0000-0000-0000-000000000001');
    end if;
    if (select count(*) from notifications
         where kind = 'unlock' and recipient_id = '65656565-0000-0000-0000-000000000001'
           and message like 'Factures débloquées%') <> 1 then
        raise exception 'FAIL: the owner was not told once about invoices';
    end if;
end $$;
update orgs set lat = 12.37, lng = -1.52 where id = :shop;
do $$ begin
    if exists (select 1 from org_unlocks where org_id = '65000000-0000-0000-0000-000000000001'
                and step = 'production') then
        raise exception 'FAIL: production opened before the first sale';
    end if;
end $$;
insert into sales (org_id, total) values (:shop, 1000);
-- Falls back, climbs again: not news twice.
update products set is_published = false where org_id = :shop;
update products set is_published = true where org_id = :shop;
do $$ begin
    if (select count(*) from notifications where kind = 'unlock'
         and org_id = '65000000-0000-0000-0000-000000000001') <> 2
       or not exists (select 1 from notifications where kind = 'unlock'
                       and org_id = '65000000-0000-0000-0000-000000000001'
                       and message like 'Production débloquée%') then
        raise exception 'FAIL: the bell rang % times, not twice',
            (select count(*) from notifications where kind = 'unlock'
              and org_id = '65000000-0000-0000-0000-000000000001');
    end if;
    raise notice 'PASS: invoices with the photos, production with stage 2, once each';
end $$;

\echo ''
\echo '--- TEST 3: the credit book on the third finished order ---'
insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency)
select :shop, :other, 'Client', 'accepted', 'pickup', 1000, 'XOF' from generate_series(1, 3);
update orders set status = 'picked_up'
 where id in (select id from orders where org_id = :shop order by id limit 2);
do $$ begin
    if exists (select 1 from org_unlocks where org_id = '65000000-0000-0000-0000-000000000001'
                and step = 'credits') then
        raise exception 'FAIL: the credit book opened after two orders';
    end if;
end $$;
update orders set status = 'delivered' where org_id = :shop and status = 'accepted';
do $$ begin
    if not exists (select 1 from notifications where kind = 'unlock'
                    and org_id = '65000000-0000-0000-0000-000000000001'
                    and message like 'Carnet de crédit débloqué%') then
        raise exception 'FAIL: the third order did not ring';
    end if;
    raise notice 'PASS: the third finished order opens the credit book, and says so';
end $$;

\echo ''
\echo '--- TEST 4: the home sees each once; the neighbour sees nothing ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '65656565-0000-0000-0000-000000000003';
do $$ begin
    if exists (select 1 from unseen_unlocks('65000000-0000-0000-0000-000000000001')) then
        raise exception 'FAIL: a stranger sees the unlocks';
    end if;
    begin
        perform mark_unlocks_seen('65000000-0000-0000-0000-000000000001');
        raise exception 'FAIL: a stranger marked them seen';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    if exists (select 1 from org_unlocks where org_id = '65000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: a stranger reads org_unlocks';
    end if;
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '65656565-0000-0000-0000-000000000001';
do $$ begin
    if (select array_agg(s order by s) from unseen_unlocks('65000000-0000-0000-0000-000000000001') s)
       <> array['credits', 'invoices', 'production'] then
        raise exception 'FAIL: the owner does not see the three';
    end if;
    perform mark_unlocks_seen('65000000-0000-0000-0000-000000000001');
    if exists (select 1 from unseen_unlocks('65000000-0000-0000-0000-000000000001')) then
        raise exception 'FAIL: seen, and still shown';
    end if;
    raise notice 'PASS: shown once to the owner, never to a stranger';
end $$;
commit;

\echo ''
\echo '--- TEST 5: Pro and an association are never told; anon has nothing ---'
update orgs set storefront_enabled = true, storefront_blurb = 'x', phone = '1', address = 'y'
 where id in (:pro, :assoc);
do $$ begin
    if exists (select 1 from notifications where kind = 'unlock'
                and org_id in ('65000000-0000-0000-0000-000000000002',
                               '65000000-0000-0000-0000-000000000003')) then
        raise exception 'FAIL: Pro or an association heard of an unlock';
    end if;
    if has_function_privilege('anon', 'unseen_unlocks(uuid)', 'execute')
       or has_function_privilege('anon', 'mark_unlocks_seen(uuid)', 'execute')
       or has_function_privilege('authenticated', 'check_unlocks(uuid)', 'execute')
       or has_table_privilege('anon', 'org_unlocks', 'select')
       or has_table_privilege('authenticated', 'org_unlocks', 'insert') then
        raise exception 'FAIL: the grants are wrong';
    end if;
    raise notice 'PASS: no bell for Pro or an association; closed to anon';
end $$;

\echo ''
\echo '--- TEST 6: open under the percentages, locked by the steps: the bell still rings ---'
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
select :half, 'Article ' || i, 100, 5, true, true from generate_series(1, 3) i;
do $$ begin
    if exists (select 1 from notifications where kind = 'unlock'
                and org_id = '65000000-0000-0000-0000-000000000004') then
        raise exception 'FAIL: the bell rang before the photos';
    end if;
end $$;
insert into documents (org_id, product_id, kind, r2_key, uploaded_by)
select org_id, id, 'product_photo', 'h/' || id, :owner from products where org_id = :half;
do $$ begin
    if (select count(*) from notifications where kind = 'unlock'
         and org_id = '65000000-0000-0000-0000-000000000004'
         and message like 'Factures débloquées%') <> 1
       or not exists (select 1 from org_unlocks
                       where org_id = '65000000-0000-0000-0000-000000000004'
                         and step = 'invoices' and seen_at is null) then
        raise exception 'FAIL: the shop seeded under the percentages never heard of its invoices';
    end if;
    raise notice 'PASS: a tool seeded under the percentages rings when the steps open it';
end $$;

\echo ''
\echo 'test_unlock_notices: all passed'
