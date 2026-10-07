-- ============================================================
-- test_le_chemin.sql — Le Chemin (097). Phone block 66.
--
-- The claims: what a business reached before 097 is recorded and not
-- paid; a new shop walks stage 1 to 4 and past it, each step recorded by
-- the triggers (nobody opening the app) and paid its reward once, a step
-- reached staying reached; path_state() returns the app's exact shape with
-- the words resolved ({min} said); the gates follow the steps live —
-- invoices with `articles` and `photos`, production with stage 2 complete,
-- the credit book with `three_orders` — and relock when the data falls
-- back; the league says « Bientôt » until three race; a farm walks the
-- same spine with its own words and checks; a showcase vitrine is paid
-- nothing; an association and a stranger get null; the Académie is gone;
-- and the engine is closed to anon and to the app.
-- ============================================================
\set ON_ERROR_STOP on
-- The owner's numbers: earlier suites change them for their own fixtures.
update platform_settings set value = '8' where key = 'vitrine_min_items';
update platform_settings set value = '0' where key = 'path_gates_open';
update platform_settings set value = '3' where key = 'progress_credit_orders';
update platform_settings set value = '3' where key = 'path_league_min';

\set owner  '''66666666-0000-0000-0000-000000000001'''
\set other  '''66666666-0000-0000-0000-000000000002'''
\set buyer1 '''66666666-0000-0000-0000-000000000003'''
\set buyer2 '''66666666-0000-0000-0000-000000000004'''
\set farmer '''66666666-0000-0000-0000-000000000005'''
\set treas  '''66666666-0000-0000-0000-000000000006'''
\set clerk  '''66666666-0000-0000-0000-000000000007'''
\set shop   '''66000000-0000-0000-0000-000000000001'''
\set farm   '''66000000-0000-0000-0000-000000000002'''
\set assoc  '''66000000-0000-0000-0000-000000000003'''
\set old    '''66000000-0000-0000-0000-000000000004'''
\set kid    '''66000000-0000-0000-0000-000000000005'''
\set show   '''66000000-0000-0000-0000-000000000006'''
\set rival1 '''66000000-0000-0000-0000-000000000007'''
\set rival2 '''66000000-0000-0000-0000-000000000008'''
\set rival3 '''66000000-0000-0000-0000-000000000009'''

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
    (:owner,  '+22666000001', '{"full_name": "Awa"}'),
    (:other,  '+22666000002', '{"full_name": "Voisin"}'),
    (:buyer1, '+22666000003', '{"full_name": "Client 1"}'),
    (:buyer2, '+22666000004', '{"full_name": "Client 2"}'),
    (:farmer, '+22666000005', '{"full_name": "Fermier"}'),
    (:treas,  '+22666000006', '{"full_name": "Trésorière"}'),
    (:clerk,  '+22666000007', '{"full_name": "Vendeuse"}');
-- A town of their own, so the league counts only this suite's businesses.
insert into orgs (id, name, slug, profile, default_currency, plan, city, showcase) values
    (:shop,   'Boutique 66', 'boutique-66', 'retail',      'XOF', 'free', 'Ville 66', false),
    (:farm,   'Ferme 66',    'ferme-66',    'farm',        'XOF', 'free', 'Ville 66', false),
    (:assoc,  'Asso 66',     'asso-66',     'association', 'XOF', 'free', 'Ville 66', false),
    (:old,    'Ancienne 66', 'ancienne-66', 'retail',      'XOF', 'free', 'Ville 66', false),
    (:kid,    'Filleule 66', 'filleule-66', 'retail',      'XOF', 'free', 'Ville 66', false),
    (:show,   'Exemple 66',  'exemple-66',  'retail',      'XOF', 'pro',  'Ville 66', true),
    (:rival1, 'Rivale 66 A', 'rivale-66-a', 'retail',      'XOF', 'free', 'Ville 66', false),
    (:rival2, 'Rivale 66 B', 'rivale-66-b', 'retail',      'XOF', 'free', 'Ville 66', false),
    (:rival3, 'Rivale 66 C', 'rivale-66-c', 'retail',      'XOF', 'free', 'Ville 66', false);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :owner,  'owner', 'org', :shop,  'full'),
    (:shop,  :clerk,  'employee', 'org', :shop, 'full'),
    (:old,   :owner,  'owner', 'org', :old,   'full'),
    (:farm,  :farmer, 'owner', 'org', :farm,  'full'),
    (:assoc, :treas,  'owner', 'org', :assoc, 'full');

-- A business that was already here: an article, its vitrine open, its
-- phone and address — written with the triggers off, as before 097.
set session_replication_role = replica;
update orgs set storefront_enabled = true, phone = '+22666000001', address = 'Gounghin'
 where id = :old;
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
values (:old, 'Riz', 500, 5, true, true);
set session_replication_role = default;
-- The seed runs once per database; let it run again over this one.
delete from platform_settings where key = 'path_seeded';
\i database/migrations/097_le_chemin.sql

\echo ''
\echo '--- TEST 1: what was reached before 097 is recorded, not paid ---'
do $$ begin
    if (select array_agg(step order by step) from org_path_done
         where org_id = '66000000-0000-0000-0000-000000000004')
       <> array['contact', 'first_article', 'vitrine_open']
       or exists (select 1 from org_path_done
                   where org_id = '66000000-0000-0000-0000-000000000004' and paid <> 0)
       or exists (select 1 from cauris_ledger
                   where org_id = '66000000-0000-0000-0000-000000000004') then
        raise exception 'FAIL: the seed is wrong: %',
            (select jsonb_agg(d) from org_path_done d
              where org_id = '66000000-0000-0000-0000-000000000004');
    end if;
    if not exists (select 1 from platform_settings where key = 'path_seeded') then
        raise exception 'FAIL: the seed did not mark itself done';
    end if;
end $$;
-- Reading it pays nothing either.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-0000-0000-0000-000000000001';
do $$
declare s jsonb := path_state('66000000-0000-0000-0000-000000000004');
begin
    if (s ->> 'stage')::int <> 2 or s ->> 'next' <> 'articles' or (s ->> 'balance')::int <> 0 then
        raise exception 'FAIL: the old shop reads %', s;
    end if;
    raise notice 'PASS: reached before 097, recorded unpaid; read, still unpaid';
end $$;
commit;

\echo ''
\echo '--- TEST 2: a new shop: the exact shape, everything ahead ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-0000-0000-0000-000000000001';
do $$
declare
    s jsonb := path_state('66000000-0000-0000-0000-000000000001');
    st jsonb;
begin
    if (select array_agg(k order by k) from jsonb_object_keys(s) k)
       <> array['balance', 'league_open', 'next', 'stage', 'stages', 'steps', 'tools', 'week'] then
        raise exception 'FAIL: the keys are %', (select array_agg(k) from jsonb_object_keys(s) k);
    end if;
    if jsonb_typeof(s -> 'stage') <> 'number' or jsonb_typeof(s -> 'balance') <> 'number'
       or jsonb_typeof(s -> 'week') <> 'number' or jsonb_typeof(s -> 'league_open') <> 'boolean'
       or jsonb_typeof(s -> 'next') <> 'string' then
        raise exception 'FAIL: the types are wrong: %', s;
    end if;
    if s -> 'stages' <> '[{"n": 1, "done": false, "title": "Ouvrir"},
                         {"n": 2, "done": false, "title": "Remplir"},
                         {"n": 3, "done": false, "title": "Vendre"},
                         {"n": 4, "done": false, "title": "Grandir"}]'::jsonb then
        raise exception 'FAIL: the stages are %', s -> 'stages';
    end if;
    if s -> 'tools' <> '{"invoices": false, "production": false, "credits": false,
                        "second_business": false}'::jsonb then
        raise exception 'FAIL: the tools are %', s -> 'tools';
    end if;
    if (s ->> 'stage')::int <> 1 or s ->> 'next' <> 'first_article'
       or (s ->> 'balance')::int <> 0 or (s ->> 'league_open')::boolean then
        raise exception 'FAIL: a new shop reads %', s;
    end if;
    -- A shop's 15 steps, in order, the farm's own left out.
    if (select array_agg(e ->> 'key' order by i)
          from jsonb_array_elements(s -> 'steps') with ordinality x(e, i))
       <> array['first_article', 'vitrine_open', 'contact',
                'articles', 'photos', 'blurb', 'pin', 'first_sale',
                'first_order', 'three_orders', 'returning', 'till_week',
                'first_unlock', 'referral', 'podium'] then
        raise exception 'FAIL: the steps are %', s -> 'steps';
    end if;
    select e into st from jsonb_array_elements(s -> 'steps') e where e ->> 'key' = 'first_article';
    if (select array_agg(k order by k) from jsonb_object_keys(st) k)
       <> array['done', 'go', 'goal', 'key', 'line', 'live', 'opens', 'progress', 'reward', 'stage', 'title']
       or st <> jsonb_build_object('key', 'first_article', 'stage', 1, 'title', 'Mon premier article',
                  'line', 'Un article en vente, et votre boutique existe pour vos clients.',
                  'go', 'produits', 'progress', 0, 'live', 0, 'goal', 1, 'done', false,
                  'reward', 5, 'opens', null) then
        raise exception 'FAIL: the first step reads %', st;
    end if;
    select e into st from jsonb_array_elements(s -> 'steps') e where e ->> 'key' = 'articles';
    if st ->> 'title' <> '8 articles en vente' or (st ->> 'goal')::int <> 8
       or st ->> 'line' not like 'Avec 8 articles%' then
        raise exception 'FAIL: {min} is not said: %', st;
    end if;
    select e into st from jsonb_array_elements(s -> 'steps') e where e ->> 'key' = 'photos';
    if st ->> 'opens' <> 'invoices' or (st ->> 'goal')::int <> 3 then
        raise exception 'FAIL: photos reads %', st;
    end if;
    select e into st from jsonb_array_elements(s -> 'steps') e where e ->> 'key' = 'referral';
    if st ->> 'line' <> 'Une entreprise vous nomme parrain. Quand elle décolle, +'
                        || (select points from cauris_rules where key = 'referral')
                        || ' cauris de plus.' then
        raise exception 'FAIL: {referral} is not said: %', st ->> 'line';
    end if;
    select e into st from jsonb_array_elements(s -> 'steps') e where e ->> 'key' = 'pin';
    if st ->> 'go' <> 'administration/parametres?partie=position' then
        raise exception 'FAIL: pin goes to %', st ->> 'go';
    end if;
    select e into st from jsonb_array_elements(s -> 'steps') e where e ->> 'key' = 'first_sale';
    if st ->> 'go' <> '' or st ->> 'opens' <> 'production' then
        raise exception 'FAIL: first_sale reads %', st;
    end if;
    raise notice 'PASS: the exact shape; a new shop at stage 1, every tool locked';
end $$;
commit;

\echo ''
\echo '--- TEST 3: stage 1 by the triggers alone, 5 cauris a step ---'
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
values (:shop, 'Article 1', 100, 5, true, true);
update orgs set storefront_enabled = true where id = :shop;
update orgs set phone = '+22666000001' where id = :shop;
do $$ begin
    if exists (select 1 from org_path_done
                where org_id = '66000000-0000-0000-0000-000000000001' and step = 'contact') then
        raise exception 'FAIL: contact done with the phone alone';
    end if;
end $$;
update orgs set address = 'Gounghin' where id = :shop;
do $$ begin
    if (select array_agg(step || ':' || paid order by step) from org_path_done
         where org_id = '66000000-0000-0000-0000-000000000001')
       <> array['contact:5', 'first_article:5', 'vitrine_open:5']
       or (select sum(delta) from cauris_ledger
            where org_id = '66000000-0000-0000-0000-000000000001' and reason = 'path_step') <> 15 then
        raise exception 'FAIL: stage 1 by the triggers: %',
            (select array_agg(step || ':' || paid) from org_path_done
              where org_id = '66000000-0000-0000-0000-000000000001');
    end if;
end $$;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-0000-0000-0000-000000000001';
do $$
declare s jsonb := path_state('66000000-0000-0000-0000-000000000001');
begin
    if (s ->> 'stage')::int <> 2 or s ->> 'next' <> 'articles'
       or not (s -> 'stages' -> 0 ->> 'done')::boolean
       or (s -> 'stages' -> 1 ->> 'done')::boolean
       or (s ->> 'balance')::int <> 15 or (s ->> 'week')::int <> 15 then
        raise exception 'FAIL: after stage 1 path_state reads %', s;
    end if;
    raise notice 'PASS: stage 1 recorded and paid by the triggers; stage 2 next';
end $$;
commit;
-- A member who is not an admin walks the same path, without the wallet.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-0000-0000-0000-000000000007';
do $$
declare s jsonb := path_state('66000000-0000-0000-0000-000000000001');
begin
    if s is null or (s ->> 'stage')::int <> 2
       or s -> 'balance' <> 'null'::jsonb or s -> 'week' <> 'null'::jsonb
       or not (s ? 'balance') or not (s ? 'week') then
        raise exception 'FAIL: a member who is not an admin reads %', s;
    end if;
    raise notice 'PASS: the wallet is the admins'': null balance and week for a member';
end $$;
commit;

\echo ''
\echo '--- TEST 4: paid once; a step reached stays reached ---'
update products set is_published = false where org_id = :shop;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-0000-0000-0000-000000000001';
do $$
declare s jsonb;
begin
    perform path_state('66000000-0000-0000-0000-000000000001');
    s := path_state('66000000-0000-0000-0000-000000000001');
    if not exists (select 1 from jsonb_array_elements(s -> 'steps') e
                    where e ->> 'key' = 'first_article' and (e ->> 'done')::boolean
                      and (e ->> 'progress')::int = 1) then
        raise exception 'FAIL: the first article is no longer done: %', s -> 'steps' -> 0;
    end if;
    -- What the data says now is « live »: the gates read it.
    if not exists (select 1 from jsonb_array_elements(s -> 'steps') e
                    where e ->> 'key' = 'first_article' and (e ->> 'live')::int = 0) then
        raise exception 'FAIL: live does not say the article went: %', s -> 'steps' -> 0;
    end if;
end $$;
commit;
update products set is_published = true where org_id = :shop;
do $$ begin
    if (select count(*) from cauris_ledger
         where org_id = '66000000-0000-0000-0000-000000000001' and reason = 'path_step') <> 3 then
        raise exception 'FAIL: a step was paid twice';
    end if;
    -- Recording again by hand pays nothing more.
    if path_sync('66000000-0000-0000-0000-000000000001') <> 0 then
        raise exception 'FAIL: path_sync recorded a step twice';
    end if;
    raise notice 'PASS: once each, and done stays done';
end $$;

\echo ''
\echo '--- TEST 5: invoices with articles and photos; production with stage 2 ---'
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
select :shop, 'Article ' || i, 100, 5, true, true from generate_series(2, 8) i;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-0000-0000-0000-000000000001';
do $$
declare s jsonb := path_state('66000000-0000-0000-0000-000000000001');
begin
    if s ->> 'next' <> 'photos' or (s -> 'tools' ->> 'invoices')::boolean then
        raise exception 'FAIL: 8 articles, no photo: %', s;
    end if;
    begin
        perform create_invoice('66000000-0000-0000-0000-000000000001', 'Awa',
            '[{"description": "Riz", "quantity": 1, "unit_price": 1000}]'::jsonb);
        raise exception 'FAIL: an invoice before the photos';
    exception when others then
        if sqlerrm <> 'Factures : 8 articles en vente et 3 en photo pour les débloquer.' then raise; end if;
    end;
end $$;
commit;
insert into documents (org_id, product_id, kind, r2_key, uploaded_by)
select org_id, id, 'product_photo', 'p/' || id, :owner
  from products where org_id = :shop order by name limit 3;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-0000-0000-0000-000000000001';
do $$
declare s jsonb := path_state('66000000-0000-0000-0000-000000000001');
begin
    if not (s -> 'tools' ->> 'invoices')::boolean or (s -> 'tools' ->> 'production')::boolean
       or s ->> 'next' <> 'blurb' then
        raise exception 'FAIL: with the photos: %', s;
    end if;
    perform create_invoice('66000000-0000-0000-0000-000000000001', 'Awa',
        '[{"description": "Riz", "quantity": 1, "unit_price": 1000}]'::jsonb);
end $$;
commit;
-- The gate is live: a photo taken off closes it, the step stays done.
delete from documents where org_id = :shop
   and id = (select id from documents where org_id = :shop limit 1);
do $$ begin
    if not path_locked('66000000-0000-0000-0000-000000000001', 'invoices')
       or not exists (select 1 from org_path_done
                       where org_id = '66000000-0000-0000-0000-000000000001' and step = 'photos') then
        raise exception 'FAIL: two photos left, invoices still open or the step undone';
    end if;
end $$;
insert into documents (org_id, product_id, kind, r2_key, uploaded_by)
select org_id, id, 'product_photo', 'p2/' || id, :owner
  from products p where org_id = :shop
   and not exists (select 1 from documents d where d.product_id = p.id)
 order by name limit 1;
update orgs set storefront_blurb = 'Le riz du quartier', lat = 12.37, lng = -1.52 where id = :shop;
do $$ begin
    if not path_locked('66000000-0000-0000-0000-000000000001', 'production') then
        raise exception 'FAIL: production open before the first sale';
    end if;
end $$;
insert into sales (org_id, total) values (:shop, 1000);
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-0000-0000-0000-000000000001';
do $$
declare s jsonb := path_state('66000000-0000-0000-0000-000000000001');
begin
    if not (s -> 'tools' ->> 'production')::boolean or (s ->> 'stage')::int <> 3
       or s ->> 'next' <> 'first_order' or (s -> 'tools' ->> 'credits')::boolean
       or not (s -> 'stages' -> 1 ->> 'done')::boolean then
        raise exception 'FAIL: stage 2 complete reads %', s;
    end if;
    raise notice 'PASS: invoices with articles and photos (live), production with stage 2';
end $$;
commit;

\echo ''
\echo '--- TEST 6: stage 3 — orders, a customer back, the till kept; credits open ---'
insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency)
values (:shop, :buyer1, 'Client 1', 'accepted', 'pickup', 1000, 'XOF');
insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency)
values (:shop, :buyer2, 'Client 2', 'delivered', 'pickup', 1000, 'XOF'),
       (:shop, :buyer1, 'Client 1', 'picked_up', 'pickup', 1000, 'XOF');
do $$ begin
    if not exists (select 1 from org_path_done
                    where org_id = '66000000-0000-0000-0000-000000000001' and step = 'first_order')
       or exists (select 1 from org_path_done
                   where org_id = '66000000-0000-0000-0000-000000000001'
                     and step in ('three_orders', 'returning'))
       or not path_locked('66000000-0000-0000-0000-000000000001', 'credits') then
        raise exception 'FAIL: after one accepted and two finished orders';
    end if;
end $$;
update orders set status = 'picked_up' where org_id = :shop and status = 'accepted';
do $$
declare i int;
begin
    for i in 1..6 loop
        insert into sales (org_id, total, occurred_at)
        values ('66000000-0000-0000-0000-000000000001', 1000, now() - make_interval(days => i));
    end loop;
end $$;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-0000-0000-0000-000000000001';
do $$
declare s jsonb := path_state('66000000-0000-0000-0000-000000000001');
begin
    if not (s -> 'tools' ->> 'credits')::boolean or (s ->> 'stage')::int <> 4
       or s ->> 'next' <> 'first_unlock' or (s ->> 'league_open')::boolean then
        raise exception 'FAIL: stage 3 complete reads %', s;
    end if;
    perform record_credit_sale('66000000-0000-0000-0000-000000000001', 'Awa', 2000, 'Riz');
    raise notice 'path_state at stage 4: %', s;
    raise notice 'PASS: stage 3 recorded, the credit book open, the league « Bientôt » alone';
end $$;
commit;

\echo ''
\echo '--- TEST 7: stage 4 — a tool bought, a sponsored business, the podium; past it ---'
insert into cauris_unlocks (org_id, feature, until)
values (:shop, 'analytics', now() + interval '30 days');
update orgs set referred_by = :shop where id = :kid;
-- A podium in a week the shop raced alone is not a podium.
insert into cauris_week_results (week_start, org_id, league, rank, score)
values ((cauris_week_start() - interval '14 days')::date, :shop, league_key(:shop), 1, 30);
do $$ begin
    if exists (select 1 from org_path_done
                where org_id = '66000000-0000-0000-0000-000000000001' and step = 'podium') then
        raise exception 'FAIL: a podium with nobody else racing counted';
    end if;
end $$;
-- Last week, three earned in the league: that podium counts.
insert into cauris_ledger (org_id, delta, reason, ref, created_at) values
    (:shop,   5, 'visitor', 't66-last', cauris_week_start() - interval '3 days'),
    (:rival1, 3, 'visitor', 't66-last', cauris_week_start() - interval '3 days'),
    (:rival2, 1, 'visitor', 't66-last', cauris_week_start() - interval '3 days');
insert into cauris_week_results (week_start, org_id, league, rank, score)
values ((cauris_week_start() - interval '7 days')::date, :shop, league_key(:shop), 2, 40);
-- This week: a rival earning, and one on the board at 0 (it earned once,
-- long ago) — two racing, not three.
insert into cauris_ledger (org_id, delta, reason, ref, created_at) values
    (:rival1, 1, 'visitor', 't66', now()),
    (:rival3, 1, 'visitor', 't66-old', now() - interval '40 days');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-0000-0000-0000-000000000001';
do $$
declare s jsonb := path_state('66000000-0000-0000-0000-000000000001');
begin
    if (s ->> 'league_open')::boolean then
        raise exception 'FAIL: the league is open with a rival at 0: %', s;
    end if;
    raise notice 'PASS: a rival at 0 this week does not make a race';
end $$;
commit;
-- The second rival earns: three race.
insert into cauris_ledger (org_id, delta, reason, ref) values (:rival2, 1, 'visitor', 't66');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-0000-0000-0000-000000000001';
do $$
declare s jsonb := path_state('66000000-0000-0000-0000-000000000001');
begin
    if (s ->> 'stage')::int <> 5 or s -> 'next' <> 'null'::jsonb
       or exists (select 1 from jsonb_array_elements(s -> 'stages') e where not (e ->> 'done')::boolean)
       or exists (select 1 from jsonb_array_elements(s -> 'steps') e where not (e ->> 'done')::boolean)
       or not (s ->> 'league_open')::boolean then
        raise exception 'FAIL: past stage 4 reads %', s;
    end if;
    if (select sum(delta) from cauris_ledger
         where org_id = '66000000-0000-0000-0000-000000000001' and reason = 'path_step') <> 190
       or (select sum(reward) from path_steps where 'retail' = any (profiles)) <> 190
       or exists (select 1 from org_path_done d join path_steps p on p.key = d.step
                   where d.org_id = '66000000-0000-0000-0000-000000000001' and d.paid <> p.reward) then
        raise exception 'FAIL: the path did not pay each step its reward once';
    end if;
    if (s ->> 'balance')::int <> cauris_balance('66000000-0000-0000-0000-000000000001')
       or (s ->> 'balance')::int <> (my_cauris('66000000-0000-0000-0000-000000000001') ->> 'balance')::int then
        raise exception 'FAIL: the balance is not the wallet''s';
    end if;
    if not exists (select 1 from jsonb_array_elements(
                       my_cauris('66000000-0000-0000-0000-000000000001') -> 'history') h
                    where h ->> 'reason' = 'path_step' and h ->> 'label' = 'Étape du chemin'
                      and h ->> 'note' is not null) then
        raise exception 'FAIL: the history does not say « Étape du chemin »';
    end if;
    raise notice 'path_state past stage 4: %', s;
    raise notice 'PASS: stage 4 walked, 190 cauris in all, the league open with three racing';
end $$;
commit;

\echo ''
\echo '--- TEST 8: a farm walks the same spine, in its own words ---'
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
select :farm, 'Poulet ' || i, 2500, 5, true, true from generate_series(1, 8) i;
insert into documents (org_id, product_id, kind, r2_key, uploaded_by)
select org_id, id, 'product_photo', 'f/' || id, :farmer
  from products where org_id = :farm order by name limit 3;
update orgs set storefront_enabled = true, storefront_blurb = 'Poulets bicyclette',
               phone = '+22666000005', address = 'Saaba', lat = 12.38, lng = -1.43
 where id = :farm;
-- A sale at the till is not the farm's step.
insert into sales (org_id, total) values (:farm, 2500);
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-0000-0000-0000-000000000005';
do $$
declare s jsonb := path_state('66000000-0000-0000-0000-000000000002');
begin
    if (select array_agg(e ->> 'key' order by i)
          from jsonb_array_elements(s -> 'steps') with ordinality x(e, i))
       <> array['first_article', 'vitrine_open', 'contact',
                'articles', 'photos', 'blurb', 'pin', 'farm_log',
                'first_order', 'three_orders', 'returning', 'log_week',
                'first_unlock', 'referral', 'podium'] then
        raise exception 'FAIL: the farm''s steps are %', s -> 'steps';
    end if;
    if s -> 'steps' -> 0 ->> 'title' <> 'Mon premier produit en vente'
       or s -> 'steps' -> 0 ->> 'go' <> 'a-vendre'
       or s -> 'steps' -> 3 ->> 'title' <> '8 produits en vente'
       or s -> 'steps' -> 7 ->> 'go' <> 'bandes'
       or s -> 'steps' -> 1 ->> 'line' not like '%votre ferme%' then
        raise exception 'FAIL: the farm''s words: %', s -> 'steps';
    end if;
    if s ->> 'next' <> 'farm_log' or (s -> 'tools' ->> 'production')::boolean
       or not (s -> 'tools' ->> 'invoices')::boolean then
        raise exception 'FAIL: the farm before its log reads %', s;
    end if;
end $$;
commit;
do $$
declare f uuid;
begin
    insert into flocks (org_id, batch_code, bird_count)
    values ('66000000-0000-0000-0000-000000000002', 'B-66', 200) returning id into f;
    insert into flock_events (flock_id, kind, quantity, created_by)
    values (f, 'weight', 1200, '66666666-0000-0000-0000-000000000005');
    if not exists (select 1 from org_path_done
                    where org_id = '66000000-0000-0000-0000-000000000002'
                      and step = 'farm_log' and paid = 10)
       or path_locked('66000000-0000-0000-0000-000000000002', 'production') then
        raise exception 'FAIL: the farm''s log did not complete stage 2';
    end if;
    raise notice 'PASS: a farm: its words, its log, its production gate';
end $$;

\echo ''
\echo '--- TEST 9: a showcase vitrine records, earns nothing ---'
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
values (:show, 'Exemple', 100, 5, true, true);
do $$ begin
    if not exists (select 1 from org_path_done
                    where org_id = '66000000-0000-0000-0000-000000000006'
                      and step = 'first_article' and paid = 0)
       or exists (select 1 from cauris_ledger where org_id = '66000000-0000-0000-0000-000000000006') then
        raise exception 'FAIL: a showcase vitrine was paid';
    end if;
    raise notice 'PASS: a showcase vitrine walks for nothing';
end $$;

\echo ''
\echo '--- TEST 10: an association and a stranger get null; RLS on the records ---'
update orgs set storefront_enabled = true, phone = '1', address = 'y' where id = :assoc;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-0000-0000-0000-000000000006';
do $$ begin
    if path_state('66000000-0000-0000-0000-000000000003') is not null then
        raise exception 'FAIL: an association is on the path';
    end if;
end $$;
set local "request.jwt.claim.sub" = '66666666-0000-0000-0000-000000000002';
do $$ begin
    if path_state('66000000-0000-0000-0000-000000000001') is not null then
        raise exception 'FAIL: a stranger reads the path';
    end if;
    if exists (select 1 from org_path_done where org_id = '66000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: a stranger reads org_path_done';
    end if;
    if not exists (select 1 from path_steps) then
        raise exception 'FAIL: the steps are not readable when signed in';
    end if;
end $$;
commit;
do $$ begin
    if exists (select 1 from org_path_done where org_id = '66000000-0000-0000-0000-000000000003')
       or exists (select 1 from cauris_ledger
                   where org_id = '66000000-0000-0000-0000-000000000003' and reason = 'path_step') then
        raise exception 'FAIL: an association recorded or earned a step';
    end if;
    raise notice 'PASS: null for an association and a stranger, the records members-only';
end $$;

\echo ''
\echo '--- TEST 11: the Académie is gone; the words; the grants ---'
do $$ begin
    if to_regclass('public.academy_lessons') is not null
       or to_regclass('public.academy_done') is not null
       or to_regprocedure('complete_lesson(uuid, text)') is not null
       or to_regprocedure('my_academy(uuid)') is not null
       or to_regprocedure('academy_mission_met(uuid, text)') is not null
       or exists (select 1 from cauris_rules where key = 'lesson')
       or exists (select 1 from platform_settings
                   where key in ('progress_invoices_pct', 'progress_production_pct')) then
        raise exception 'FAIL: the Académie or the vitrine percentages are still there';
    end if;
    if unlock_message('invoices') <> 'Factures débloquées : 8 articles en vente et 3 en photo.'
       or unlock_message('production') <> 'Production débloquée : l''étape Remplir est terminée.'
       or path_lock_message('credits') <> 'Carnet de crédit : 3 commandes terminées pour le débloquer.' then
        raise exception 'FAIL: the words are %, %', unlock_message('invoices'), unlock_message('production');
    end if;
    if org_progress('66000000-0000-0000-0000-000000000001') ?| array['invoices_pct', 'production_pct', 'tools_pct']
       or (org_progress('66000000-0000-0000-0000-000000000001') -> 'locks')
          <> '{"invoices": false, "production": false, "credits": false, "second_business": true}'::jsonb then
        raise exception 'FAIL: org_progress reads %', org_progress('66000000-0000-0000-0000-000000000001');
    end if;
    if has_function_privilege('anon', 'path_state(uuid)', 'execute')
       or not has_function_privilege('authenticated', 'path_state(uuid)', 'execute')
       or has_function_privilege('authenticated', 'path_sync(uuid)', 'execute')
       or has_function_privilege('authenticated', 'path_progress(uuid, text)', 'execute')
       or has_function_privilege('authenticated', 'path_goal(uuid, text)', 'execute')
       or has_function_privilege('anon', 'path_sync(uuid)', 'execute')
       or has_table_privilege('anon', 'path_steps', 'select')
       or has_table_privilege('anon', 'org_path_done', 'select')
       or has_table_privilege('authenticated', 'org_path_done', 'insert')
       or has_table_privilege('authenticated', 'path_steps', 'update') then
        raise exception 'FAIL: the grants are wrong';
    end if;
    raise notice 'PASS: no Académie left, the step words, closed to anon and to the app';
end $$;
begin;
set local role anon;
do $$ begin
    begin
        perform path_state('66000000-0000-0000-0000-000000000001');
        raise exception 'FAIL: anon called path_state';
    exception when insufficient_privilege then null;
    end;
    raise notice 'PASS: anon is refused path_state (42501)';
end $$;
commit;

\echo ''
\echo 'test_le_chemin: all passed'
