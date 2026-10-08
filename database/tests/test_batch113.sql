-- ============================================================
-- test_batch113.sql — the shopper's page (113).
--
-- The claims, for a shop, a farm and an association alike:
--   * P1: installed, with nobody following, the owners' writes ring
--     nobody and the help number is empty (its row not drawn);
--   * following: an open vitrine only, by a signed-in person, each its
--     own news switch, let go by the business's id;
--   * the news: one bell row per vitrine per follower per day, the next
--     novelties of the day said in that same row; a new article or
--     service, or a lower price; never the business's own people, never
--     with a switch off (per vitrine, or all), never what the street
--     cannot see (the vitrine shut or under its minimum, a farm's « À
--     vendre » or anyone's services hidden by 110), and never in the way
--     of the owner's write;
--   * addresses: Maison and Travail once each, ten in all, the words
--     required, a pin whole or none, the caller's own only;
--   * the choices: Wave a choice only while the platform allows it, and
--     read back as cash once it no longer does (RULE M);
--   * « Recommander »: what of the caller's own order the vitrine still
--     has, at most what is left; nothing when the vitrine takes no orders;
--   * reports: a few words, five a day, the order the caller's own; the
--     platform lists them, closes one (journaled, the person told) and
--     « Annuler » opens it again;
--   * the help number: digits only, the platform's to set;
--   * « Mes données »: the caller's own, every part;
--   * « Supprimer mon compte »: the account Worker's question answers
--     the caller's own id or refuses in French; the deletion it then does
--     takes the person's rows with it;
--   * the doors: closed to the street, the internals to everyone, the
--     platform's to the platform.
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
-- Earlier suites hand the app's roles every function: 113 again, so what
-- follows tests its own doors.
\i database/migrations/113_shopper_profile.sql

\set mara    '''11311311-0000-0000-0000-000000000001'''
\set sowner  '''11311311-0000-0000-0000-000000000002'''
\set fowner  '''11311311-0000-0000-0000-000000000003'''
\set aowner  '''11311311-0000-0000-0000-000000000004'''
\set awa     '''11311311-0000-0000-0000-000000000005'''
\set ali     '''11311311-0000-0000-0000-000000000006'''
\set livreur '''11311311-0000-0000-0000-000000000007'''
\set clerk   '''11311311-0000-0000-0000-000000000008'''
\set lea     '''11311311-0000-0000-0000-000000000009'''
\set shop    '''11300000-0000-0000-0000-000000000001'''
\set farm    '''11300000-0000-0000-0000-000000000002'''
\set assoc   '''11300000-0000-0000-0000-000000000003'''
\set shut    '''11300000-0000-0000-0000-000000000004'''

-- The settings this suite moves, put back at its end.
create temp table b113_saved as
    select key, value from platform_settings
     where key in ('vitrine_min_items', 'vitrine_min_items_association',
                   'order_phone_verified', 'wave_checkout', 'support_whatsapp');
update platform_settings set value = '1'
 where key in ('vitrine_min_items', 'vitrine_min_items_association');
update platform_settings set value = 'false' where key in ('order_phone_verified', 'wave_checkout');

insert into auth.users (id, phone, email, raw_user_meta_data, phone_confirmed_at) values
    (:mara,    '+22611301001', 'mara113@example.com',  '{"full_name": "Mara Cent-Treize"}',   null),
    (:sowner,  '+22611301002', 'awa.b113@example.com', '{"full_name": "Patronne 113"}',       null),
    (:fowner,  '+22611301003', null,                   '{"full_name": "Fermier 113"}',        null),
    (:aowner,  '+22611301004', null,                   '{"full_name": "Trésorière 113"}',     null),
    (:awa,     '22670113005',  'awa113@example.com',   '{"full_name": "Awa Cliente"}',        now()),
    (:ali,     null,           'ali113@example.com',   '{"full_name": "Ali Client"}',         null),
    (:livreur, '+22611301007', null,                   '{"full_name": "Livreur 113"}',        null),
    (:clerk,   '+22611301008', null,                   '{"full_name": "Vendeuse 113"}',       null),
    (:lea,     '+22611301009', 'lea113@example.com',   '{"full_name": "Léa Cliente"}',        null);
update profiles set is_platform_admin = true where id = :mara;
update profiles set first_name = 'Awa', last_name = 'Ouédraogo' where id = :awa;
insert into orgs (id, name, slug, profile, default_currency, plan, storefront_enabled, storefront_blurb) values
    (:shop,  'Boutique 113', 'boutique-113', 'retail',      'XOF', 'free', true,  'Bienvenue'),
    (:farm,  'Ferme 113',    'ferme-113',    'farm',        'XOF', 'free', true,  'Bienvenue'),
    (:assoc, 'Entraide 113', 'entraide-113', 'association', 'XOF', 'free', true,  'Bienvenue'),
    (:shut,  'Fermée 113',   'fermee-113',   'retail',      'XOF', 'free', false, 'Bientôt');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :sowner, 'owner',    'org', :shop,  'full'),
    (:shop,  :clerk,  'employee', 'org', :shop,  'summary'),
    (:farm,  :fowner, 'owner',    'org', :farm,  'full'),
    (:assoc, :aowner, 'owner',    'org', :assoc, 'full'),
    (:shut,  :sowner, 'owner',    'org', :shut,  'full');
insert into couriers (user_id, phone, status) values (:livreur, '+22611301007', 'approved');
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published, is_service) values
    ('113aaaaa-0000-0000-0000-000000000001', :shop,  'Savon 113',  500, 300, 5,  true, true, false),
    ('113aaaaa-0000-0000-0000-000000000002', :shop,  'Riz 113',   1000, 800, 2,  true, true, false),
    ('113aaaaa-0000-0000-0000-000000000003', :shop,  'Coupe 113', 1500,   0, 0,  true, true, true),
    ('113aaaaa-0000-0000-0000-000000000004', :farm,  'Œufs 113',  2500,   0, 10, true, true, false),
    ('113aaaaa-0000-0000-0000-000000000005', :assoc, 'Bâches 113', 5000,  0, 0,  true, true, true),
    ('113aaaaa-0000-0000-0000-000000000006', :shut,  'Pagne 113', 3000, 2000, 4, true, true, false);

-- The caller, named the way PostgREST names them.
create or replace function pg_temp.as113(p_who uuid)
returns void
language sql
as $$ select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true); $$;

-- The message of a refused call, or « (went through) » — never null, so
-- a call that should have been refused fails the comparison.
create or replace function pg_temp.refused113(p_sql text)
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

-- The follower's bell rows about one vitrine.
create or replace function pg_temp.news113(p_who uuid, p_org uuid)
returns table (message text, params jsonb, read_at timestamptz)
language sql
as $$
    select n.message, n.params, n.read_at from notifications n
     where n.recipient_id = p_who and n.org_id = p_org and n.kind = 'vitrine_news'
     order by n.created_at, n.message;
$$;

\echo ''
\echo '--- TEST 1: installed, nobody follows — the owners'' writes ring nobody, the help number is empty (P1) ---'
begin;
do $$
begin
    if (select value from platform_settings where key = 'support_whatsapp') is distinct from '""'::jsonb
       or support_whatsapp() is not null then
        raise exception 'FAIL: the help number is not installed empty';
    end if;
    -- A shop, a farm and an association: new, republished, cheaper.
    insert into products (org_id, name, sale_price, quantity, is_published)
    values ('11300000-0000-0000-0000-000000000001', 'Huile P1', 900, 3, true),
           ('11300000-0000-0000-0000-000000000002', 'Poulet P1', 4000, 2, true);
    insert into products (org_id, name, sale_price, is_service, is_published)
    values ('11300000-0000-0000-0000-000000000003', 'Salle P1', 10000, true, true);
    update products set sale_price = 400 where id = '113aaaaa-0000-0000-0000-000000000001';
    update products set is_published = false where id = '113aaaaa-0000-0000-0000-000000000004';
    update products set is_published = true  where id = '113aaaaa-0000-0000-0000-000000000004';
    if exists (select 1 from notifications where kind = 'vitrine_news') then
        raise exception 'FAIL: nobody follows, and a bell rang';
    end if;
    -- Another setting is written as before: the check is the help number's.
    update platform_settings set value = '2' where key = 'vitrine_min_items';
    raise notice 'PASS: off as installed — the shop''s, the farm''s and the association''s writes go through and ring nobody; the help number is empty; other settings untouched by its check';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: following — an open vitrine, a signed-in person, a news switch each, let go by the business ---'
begin;
do $$
declare
    v_org uuid;
    v jsonb;
begin
    perform pg_temp.as113('11311311-0000-0000-0000-000000000005');
    v_org := follow_vitrine('Boutique-113 ');
    if v_org is distinct from '11300000-0000-0000-0000-000000000001' then
        raise exception 'FAIL: follow answered %', v_org;
    end if;
    perform follow_vitrine('boutique-113');   -- twice is once
    perform follow_vitrine('ferme-113');
    perform follow_vitrine('entraide-113');
    v := my_follows();
    if jsonb_array_length(v) is distinct from 3
       or v -> 0 ->> 'name' is distinct from 'Boutique 113' or (v -> 0 ->> 'news')::boolean is not true
       or (v -> 0 ->> 'open')::boolean is not true or v -> 0 ->> 'slug' is distinct from 'boutique-113'
       or v -> 1 ->> 'profile' is distinct from 'association' or v -> 2 ->> 'profile' is distinct from 'farm' then
        raise exception 'FAIL: my_follows reads %', v;
    end if;
    if pg_temp.refused113($q$select follow_vitrine('fermee-113')$q$) is distinct from 'Cette vitrine n''est pas ouverte.'
       or pg_temp.refused113($q$select follow_vitrine('nulle-part-113')$q$) is distinct from 'Cette vitrine n''est pas ouverte.' then
        raise exception 'FAIL: a shut or unknown vitrine was followed';
    end if;
    perform set_follow_news('11300000-0000-0000-0000-000000000002', false);
    if (my_follows() -> 2 ->> 'news')::boolean is not false then
        raise exception 'FAIL: the farm''s news is still on';
    end if;
    perform unfollow_vitrine('11300000-0000-0000-0000-000000000003');
    if jsonb_array_length(my_follows()) is distinct from 2 then
        raise exception 'FAIL: the association was not let go';
    end if;
    if pg_temp.refused113($q$select set_follow_news('11300000-0000-0000-0000-000000000003', true)$q$)
       is distinct from 'Vous ne suivez pas cette vitrine.' then
        raise exception 'FAIL: news switched on a vitrine not followed';
    end if;
    -- Somebody else reads their own (none), and the street cannot follow.
    perform pg_temp.as113('11311311-0000-0000-0000-000000000006');
    if jsonb_array_length(my_follows()) is distinct from 0 then
        raise exception 'FAIL: Ali reads Awa''s follows';
    end if;
    perform pg_temp.as113(null);
    if pg_temp.refused113($q$select follow_vitrine('boutique-113')$q$) is distinct from 'Connectez-vous d''abord' then
        raise exception 'FAIL: a stranger followed';
    end if;
    raise notice 'PASS: Awa follows the shop, the farm and the association (twice is once, the address read loosely), not a shut or unknown vitrine; one vitrine''s news off; let go by id; Ali reads his own; a stranger is asked to sign in';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: the news — one row per vitrine per day, said again in that row; never the business''s own, never switched off, never unseen ---'
begin;
insert into vitrine_follows (user_id, org_id, news) values
    (:awa,     :shop,  true),
    (:awa,     :farm,  true),
    (:awa,     :assoc, true),
    (:ali,     :shop,  false),   -- this vitrine's news off
    (:livreur, :shop,  true),    -- all news off, below
    (:clerk,   :shop,  true),    -- of the business itself
    (:lea,     :shop,  true);    -- told once, then all news off
insert into shopper_settings (user_id, vitrine_news) values (:livreur, false);
do $$
declare
    v_shop constant uuid := '11300000-0000-0000-0000-000000000001';
    v_farm constant uuid := '11300000-0000-0000-0000-000000000002';
    v_asso constant uuid := '11300000-0000-0000-0000-000000000003';
    v_awa  constant uuid := '11311311-0000-0000-0000-000000000005';
    v_msg  text;
begin
    -- A shop: a new article.
    insert into products (org_id, name, sale_price, quantity) values (v_shop, 'Huile 113', 900, 3);
    if (select count(*) from pg_temp.news113(v_awa, v_shop)) is distinct from 1
       or (select message from pg_temp.news113(v_awa, v_shop)) is distinct from 'Nouveau chez Boutique 113 : Huile 113'
       or (select params ->> 'slug' from pg_temp.news113(v_awa, v_shop)) is distinct from 'boutique-113' then
        raise exception 'FAIL: the first novelty: %', (select jsonb_agg(x) from pg_temp.news113(v_awa, v_shop) x);
    end if;
    if exists (select 1 from notifications where kind = 'vitrine_news'
                and recipient_id in ('11311311-0000-0000-0000-000000000006',
                                     '11311311-0000-0000-0000-000000000007',
                                     '11311311-0000-0000-0000-000000000008',
                                     '11311311-0000-0000-0000-000000000002')) then
        raise exception 'FAIL: a switched-off follower or the business''s own people were told';
    end if;
    -- Léa was told too, then switches all her news off: her row of the
    -- day is not rewritten any more.
    if (select message from pg_temp.news113('11311311-0000-0000-0000-000000000009', v_shop))
       is distinct from 'Nouveau chez Boutique 113 : Huile 113' then
        raise exception 'FAIL: Léa was not told the first novelty';
    end if;
    insert into shopper_settings (user_id, vitrine_news) values ('11311311-0000-0000-0000-000000000009', false);
    -- Read; then more the same day: the same row, unread again.
    update notifications set read_at = now() where recipient_id = v_awa and kind = 'vitrine_news';
    insert into products (org_id, name, sale_price, quantity) values (v_shop, 'Sucre 113', 700, 3);
    if (select count(*) from pg_temp.news113(v_awa, v_shop)) is distinct from 1
       or (select message from pg_temp.news113(v_awa, v_shop)) is distinct from '2 nouveautés chez Boutique 113 : Huile 113, Sucre 113'
       or (select read_at from pg_temp.news113(v_awa, v_shop)) is not null then
        raise exception 'FAIL: the second novelty of the day: %', (select jsonb_agg(x) from pg_temp.news113(v_awa, v_shop) x);
    end if;
    insert into products (org_id, name, sale_price, quantity) values
        (v_shop, 'Thé 113', 300, 3), (v_shop, 'Café 113', 600, 3);
    -- The same article again (cheaper now): already said today.
    update products set sale_price = 800 where org_id = v_shop and name = 'Huile 113';
    v_msg := (select message from pg_temp.news113(v_awa, v_shop));
    if (select count(*) from pg_temp.news113(v_awa, v_shop)) is distinct from 1
       or v_msg is distinct from '4 nouveautés chez Boutique 113 : Huile 113, Sucre 113, Thé 113…'
       or (select (params ->> 'count')::int from pg_temp.news113(v_awa, v_shop)) is distinct from 4 then
        raise exception 'FAIL: four novelties: %', v_msg;
    end if;
    -- Not on the vitrine (unpublished), dearer, or untouched: nothing.
    insert into products (org_id, name, sale_price, quantity, is_published) values (v_shop, 'Caché 113', 100, 1, false);
    update products set sale_price = 600 where id = '113aaaaa-0000-0000-0000-000000000001';
    update products set quantity = 4 where id = '113aaaaa-0000-0000-0000-000000000002';
    if (select (params ->> 'count')::int from pg_temp.news113(v_awa, v_shop)) is distinct from 4 then
        raise exception 'FAIL: something unseen or dearer was said';
    end if;
    if (select count(*) from pg_temp.news113('11311311-0000-0000-0000-000000000009', v_shop)) is distinct from 1
       or (select message from pg_temp.news113('11311311-0000-0000-0000-000000000009', v_shop))
          is distinct from 'Nouveau chez Boutique 113 : Huile 113' then
        raise exception 'FAIL: a follower who switched all news off was still told: %',
            (select jsonb_agg(x) from pg_temp.news113('11311311-0000-0000-0000-000000000009', v_shop) x);
    end if;
    -- The next day: an offer is a new row of its own.
    update vitrine_follows set told_on = told_on - 1 where user_id = v_awa and org_id = v_shop;
    update products set sale_price = 450 where id = '113aaaaa-0000-0000-0000-000000000001';
    if (select count(*) from pg_temp.news113(v_awa, v_shop)) is distinct from 2
       or not exists (select 1 from pg_temp.news113(v_awa, v_shop)
                       where message = 'Prix en baisse chez Boutique 113 : Savon 113 à 450 XOF'
                         and (params ->> 'offer')::boolean) then
        raise exception 'FAIL: the next day''s offer: %', (select jsonb_agg(x) from pg_temp.news113(v_awa, v_shop) x);
    end if;
    -- Republished: back on the vitrine, said as new (the same day: one more).
    update products set is_published = false where id = '113aaaaa-0000-0000-0000-000000000002';
    update products set is_published = true  where id = '113aaaaa-0000-0000-0000-000000000002';
    if not exists (select 1 from pg_temp.news113(v_awa, v_shop)
                    where message = '2 nouveautés chez Boutique 113 : Savon 113, Riz 113') then
        raise exception 'FAIL: a republished article: %', (select jsonb_agg(x) from pg_temp.news113(v_awa, v_shop) x);
    end if;

    -- A farm: an article, then « À vendre sur la vitrine » hidden — its
    -- articles leave the news, its services stay.
    insert into products (org_id, name, sale_price, quantity) values (v_farm, 'Poulets 113', 3500, 6);
    insert into feature_rules (scope, org_id, feature, state)
    values ('org', v_farm, 'for_sale', 'hidden');
    insert into products (org_id, name, sale_price, quantity) values (v_farm, 'Pintades 113', 4000, 6);
    insert into products (org_id, name, sale_price, is_service) values (v_farm, 'Battage 113', 7000, true);
    if (select count(*) from pg_temp.news113(v_awa, v_farm)) is distinct from 1
       or (select message from pg_temp.news113(v_awa, v_farm)) is distinct from '2 nouveautés chez Ferme 113 : Poulets 113, Battage 113' then
        raise exception 'FAIL: the farm: %', (select jsonb_agg(x) from pg_temp.news113(v_awa, v_farm) x);
    end if;

    -- An association: a service, then « Services et réservations » hidden
    -- (110 then refuses a new one): a service made cheaper is not said.
    insert into products (org_id, name, sale_price, is_service) values (v_asso, 'Chaises 113', 2000, true);
    insert into feature_rules (scope, org_id, feature, state)
    values ('org', v_asso, 'services', 'hidden');
    update products set sale_price = 4000 where id = '113aaaaa-0000-0000-0000-000000000005';
    if (select count(*) from pg_temp.news113(v_awa, v_asso)) is distinct from 1
       or (select message from pg_temp.news113(v_awa, v_asso)) is distinct from 'Nouveau chez Entraide 113 : Chaises 113' then
        raise exception 'FAIL: the association: %', (select jsonb_agg(x) from pg_temp.news113(v_awa, v_asso) x);
    end if;

    -- The vitrine under its minimum, or shut: the street sees nothing, nor
    -- does the follower.
    update vitrine_follows set told_on = null, told_id = null where user_id = v_awa;
    delete from notifications where recipient_id = v_awa and kind = 'vitrine_news';
    update platform_settings set value = '99' where key = 'vitrine_min_items';
    insert into products (org_id, name, sale_price, quantity) values (v_shop, 'Lait 113', 500, 3);
    update platform_settings set value = '1' where key = 'vitrine_min_items';
    update orgs set storefront_enabled = false where id = v_shop;
    insert into products (org_id, name, sale_price, quantity) values (v_shop, 'Miel 113', 500, 3);
    update orgs set storefront_enabled = true where id = v_shop;
    if exists (select 1 from pg_temp.news113(v_awa, v_shop)) then
        raise exception 'FAIL: a vitrine the street cannot see rang';
    end if;
    raise notice 'PASS: a shop — one row of the day, said again in it (2, then 4 « … », unread again), the same article once, nothing unpublished or dearer, the next day''s offer a row of its own, a republished article new; a farm — its articles out with « À vendre » hidden, its service in; an association — its service, no offer said once services are hidden; nothing under the minimum or shut; nobody switched off nor of the business told';
end $$;
-- Never in the way of the owner's write.
alter table notifications add constraint b113_no_news check (kind is distinct from 'vitrine_news') not valid;
insert into products (org_id, name, sale_price, quantity) values (:shop, 'Beurre 113', 500, 3);
do $$
begin
    if not exists (select 1 from products where name = 'Beurre 113') then
        raise exception 'FAIL: the bell stopped the owner''s write';
    end if;
    raise notice 'PASS: a bell that cannot be written leaves the article saved';
end $$;
rollback;

\echo ''
\echo '--- TEST 3b: the news at scale — 2,000 followers, 30 new articles in a day: one row each, 20 said, well under 8 s ---'
begin;
insert into auth.users (id, email, raw_user_meta_data)
select ('11399999-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
       'fan' || g || '.b113@example.com', jsonb_build_object('full_name', 'Fan ' || g)
  from generate_series(1, 2000) g;
insert into vitrine_follows (user_id, org_id)
select ('11399999-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, :shop
  from generate_series(1, 2000) g;
do $$
declare
    v_shop constant uuid := '11300000-0000-0000-0000-000000000001';
    t0     timestamptz := clock_timestamp();
    v_ms   numeric;
    v_bad  int;
begin
    for i in 1..30 loop
        insert into products (org_id, name, sale_price, quantity)
        values (v_shop, 'Article ' || i || ' 113', 100 + i, 3);
    end loop;
    v_ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
    -- One row each, saying 20 (the cap), the first three named.
    select count(*) into v_bad
      from vitrine_follows f
     where f.org_id = v_shop and f.user_id::text like '11399999-%'
       and (select count(*) from notifications n
             where n.recipient_id = f.user_id and n.org_id = v_shop and n.kind = 'vitrine_news') <> 1;
    if v_bad <> 0 then
        raise exception 'FAIL: % followers without exactly one row of the day', v_bad;
    end if;
    select count(*) into v_bad
      from notifications n
     where n.org_id = v_shop and n.kind = 'vitrine_news' and n.recipient_id::text like '11399999-%'
       and (n.message is distinct from '20 nouveautés chez Boutique 113 : Article 1 113, Article 2 113, Article 3 113…'
            or (n.params ->> 'count')::int is distinct from 20
            or jsonb_array_length(n.params -> 'ids') is distinct from 20);
    if v_bad <> 0 then
        raise exception 'FAIL: % rows do not say the 20 of the day', v_bad;
    end if;
    if v_ms >= 8000 then
        raise exception 'FAIL: 30 articles for 2,000 followers took % ms', v_ms;
    end if;
    raise notice 'PASS: 2,000 followers × 30 new articles: one row each, « 20 nouveautés … » (no rewrite past 20), in % ms (limit 8,000)', v_ms;
end $$;
rollback;

\echo ''
\echo '--- TEST 4: addresses — Maison and Travail once each, ten in all, the words required, a whole pin, the caller''s own ---'
begin;
do $$
declare
    v_home uuid;
    v_id   uuid;
    v      jsonb;
begin
    perform pg_temp.as113('11311311-0000-0000-0000-000000000005');
    v_home := save_my_address(null, 'home', 'ignoré', '  Ouaga 2000, près de l''école ', 'Portail bleu', 12.33, -1.51);
    perform save_my_address(null, 'work', null, 'Zone du bois', null, null, null);
    perform save_my_address(null, 'other', 'Chez maman', 'Tanghin', 'Derrière le marché', 12.40, -1.50);
    v := my_addresses();
    if jsonb_array_length(v) is distinct from 3
       or v -> 0 ->> 'kind' is distinct from 'home' or v -> 0 ->> 'address' is distinct from 'Ouaga 2000, près de l''école'
       or v -> 0 ->> 'label' is not null or v -> 0 ->> 'note' is distinct from 'Portail bleu'
       or (v -> 0 ->> 'lat')::float is distinct from 12.33
       or v -> 1 ->> 'kind' is distinct from 'work' or v -> 2 ->> 'label' is distinct from 'Chez maman' then
        raise exception 'FAIL: the addresses read %', v;
    end if;
    if pg_temp.refused113($q$select save_my_address(null, 'home', null, 'Pissy', null, null, null)$q$)
       is distinct from 'Vous avez déjà une adresse « Maison » : modifiez-la.'
       or pg_temp.refused113($q$select save_my_address(null, 'work', null, 'Pissy', null, null, null)$q$)
       is distinct from 'Vous avez déjà une adresse « Travail » : modifiez-la.'
       or pg_temp.refused113($q$select save_my_address(null, 'other', null, ' ', null, null, null)$q$)
       is distinct from 'Dites où livrer : le quartier, un repère.'
       or pg_temp.refused113($q$select save_my_address(null, 'bureau', null, 'Pissy', null, null, null)$q$)
       is distinct from 'Maison, travail ou autre.'
       or pg_temp.refused113($q$select save_my_address(null, 'other', null, 'Pissy', null, 12.3, null)$q$)
       is distinct from 'Cette position n''est pas valable.'
       or pg_temp.refused113($q$select save_my_address(null, 'other', null, 'Pissy', null, 95, 1)$q$)
       is distinct from 'Cette position n''est pas valable.' then
        raise exception 'FAIL: a wrong address was taken';
    end if;
    -- The home changed in place: the same id, the new words.
    v_id := save_my_address(v_home, 'home', null, 'Ouaga 2000', null, null, null);
    if v_id is distinct from v_home or my_addresses() -> 0 ->> 'address' is distinct from 'Ouaga 2000'
       or my_addresses() -> 0 ->> 'lat' is not null then
        raise exception 'FAIL: the home was not changed in place';
    end if;
    for i in 1..7 loop
        perform save_my_address(null, 'other', null, 'Autre ' || i, null, null, null);
    end loop;
    if pg_temp.refused113($q$select save_my_address(null, 'other', null, 'Onzième', null, null, null)$q$)
       is distinct from 'Dix adresses au plus : retirez-en une d''abord.' then
        raise exception 'FAIL: an eleventh address was taken';
    end if;
    -- Ali can neither read, change nor delete Awa's.
    perform pg_temp.as113('11311311-0000-0000-0000-000000000006');
    if jsonb_array_length(my_addresses()) is distinct from 0
       or pg_temp.refused113(format('select save_my_address(%L, ''home'', null, ''Volé'', null, null, null)', v_home))
          is distinct from 'Adresse introuvable.' then
        raise exception 'FAIL: Ali reached Awa''s addresses';
    end if;
    perform delete_my_address(v_home);
    perform pg_temp.as113('11311311-0000-0000-0000-000000000005');
    if jsonb_array_length(my_addresses()) is distinct from 10 then
        raise exception 'FAIL: Ali deleted Awa''s home';
    end if;
    perform delete_my_address(v_home);
    if jsonb_array_length(my_addresses()) is distinct from 9 or my_addresses() -> 0 ->> 'kind' is distinct from 'work' then
        raise exception 'FAIL: Awa''s home was not deleted';
    end if;
    raise notice 'PASS: Maison (trimmed, no name), Travail, Autre named; Maison and Travail once each; the words, the kind and a whole pin required; changed in place; ten at most; nobody else''s to read, change or delete';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: the page and the choices — Wave a choice only while the platform allows it (RULE M) ---'
begin;
do $$
declare v jsonb;
begin
    perform pg_temp.as113('11311311-0000-0000-0000-000000000005');
    v := my_shopper_profile();
    if v ->> 'name' is distinct from 'Awa Ouédraogo' or v ->> 'verified_phone' is distinct from '+22670113005'
       or (v ->> 'verify_on')::boolean or (v ->> 'wave')::boolean
       or v ->> 'payment' is distinct from 'cash' or (v ->> 'news')::boolean is not true
       or v ->> 'city' is not null or v ->> 'support_whatsapp' is not null
       or v ->> 'courier' is not null or (v ->> 'member')::boolean
       or jsonb_array_length(v -> 'addresses') is distinct from 0 or (v ->> 'follows')::int is distinct from 0
       or (v ->> 'orders_open')::int is distinct from 0 then
        raise exception 'FAIL: Awa''s page reads %', v;
    end if;
    -- Cash only while the platform has not opened Wave.
    if pg_temp.refused113($q$select set_my_shopper_settings('{"payment": "wave"}')$q$)
       is distinct from 'Paiement en espèces uniquement pour le moment.'
       or pg_temp.refused113($q$select set_my_shopper_settings('{"payment": "orange"}')$q$) is distinct from 'Espèces ou Wave.'
       or pg_temp.refused113($q$select set_my_shopper_settings('{"news": "oui"}')$q$) is distinct from 'Oui ou non.'
       or pg_temp.refused113(format('select set_my_shopper_settings(%L)', jsonb_build_object('city', repeat('x', 61))))
          is distinct from 'Une ville de 60 caractères au plus.' then
        raise exception 'FAIL: a wrong choice was taken';
    end if;
    perform set_my_shopper_settings('{"city": "  Bobo-Dioulasso "}');
    perform set_my_shopper_settings('{"news": false}');
    v := my_shopper_profile();
    if v ->> 'city' is distinct from 'Bobo-Dioulasso' or (v ->> 'news')::boolean then
        raise exception 'FAIL: the city and the news switch: %', v;
    end if;
end $$;
-- The platform opens Wave: a choice, and kept.
update platform_settings set value = 'true' where key = 'wave_checkout';
do $$
declare v jsonb;
begin
    perform pg_temp.as113('11311311-0000-0000-0000-000000000005');
    perform set_my_shopper_settings('{"payment": "wave"}');
    v := my_shopper_profile();
    if not (v ->> 'wave')::boolean or v ->> 'payment' is distinct from 'wave' or v ->> 'city' is distinct from 'Bobo-Dioulasso' then
        raise exception 'FAIL: Wave allowed, Awa''s choice reads %', v;
    end if;
end $$;
-- And closes it again: read as cash, the choice kept for later.
update platform_settings set value = 'false' where key = 'wave_checkout';
do $$
declare v jsonb;
begin
    perform pg_temp.as113('11311311-0000-0000-0000-000000000005');
    v := my_shopper_profile();
    if (v ->> 'wave')::boolean or v ->> 'payment' is distinct from 'cash'
       or (select payment from shopper_settings where user_id = '11311311-0000-0000-0000-000000000005') is distinct from 'wave' then
        raise exception 'FAIL: Wave closed, Awa''s choice reads %', v;
    end if;
    -- The courier and the business's employee say so.
    perform pg_temp.as113('11311311-0000-0000-0000-000000000007');
    if my_shopper_profile() ->> 'courier' is distinct from 'approved' then
        raise exception 'FAIL: the courier is not said';
    end if;
    perform pg_temp.as113('11311311-0000-0000-0000-000000000008');
    if not (my_shopper_profile() ->> 'member')::boolean then
        raise exception 'FAIL: the employee is not said';
    end if;
    perform pg_temp.as113(null);
    if pg_temp.refused113('select my_shopper_profile()') is distinct from 'Connectez-vous d''abord' then
        raise exception 'FAIL: a stranger read a page';
    end if;
    raise notice 'PASS: Awa''s page (her name, her proved number, cash, news on); Wave refused while the platform has not opened it, taken once it has, read as cash once it closes (kept for later); the city trimmed, the news switch; the courier and the employee said; a stranger asked to sign in';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: « Recommander » — what the vitrine still has of the caller''s own order, at most what is left ---'
begin;
do $$
declare
    v_order uuid;
    v_book  uuid;
    v_farm  uuid;
    v jsonb;
begin
    perform pg_temp.as113('11311311-0000-0000-0000-000000000005');
    v_order := place_order('boutique-113',
        '[{"product_id":"113aaaaa-0000-0000-0000-000000000001","quantity":3},
          {"product_id":"113aaaaa-0000-0000-0000-000000000002","quantity":2}]');
    v_book := place_order('entraide-113',
        '[{"product_id":"113aaaaa-0000-0000-0000-000000000005","quantity":1}]', 'pickup', 'Samedi 10 h');
    update orders set status = 'picked_up' where id in (v_order, v_book);
    -- Since then: one Savon left, the Riz off the vitrine.
    update products set quantity = 1 where id = '113aaaaa-0000-0000-0000-000000000001';
    update products set is_published = false where id = '113aaaaa-0000-0000-0000-000000000002';
    v := my_order_basket(v_order);
    if v ->> 'slug' is distinct from 'boutique-113' or (v ->> 'closed')::boolean
       or v -> 'lines' is distinct from '[{"product_id": "113aaaaa-0000-0000-0000-000000000001", "quantity": 1}]'::jsonb
       or (v ->> 'missing')::int is distinct from 1 then
        raise exception 'FAIL: the shop''s order again: %', v;
    end if;
    v := my_order_basket(v_book);
    if v -> 'lines' is distinct from '[{"product_id": "113aaaaa-0000-0000-0000-000000000005", "quantity": 1}]'::jsonb
       or (v ->> 'missing')::int is distinct from 0 then
        raise exception 'FAIL: the association''s booking again: %', v;
    end if;
    -- A farm's eggs sold by weight: half a kilo left is half a kilo to put
    -- back (at most what is left, never cut to a whole one); none left,
    -- missing.
    v_farm := place_order('ferme-113', '[{"product_id":"113aaaaa-0000-0000-0000-000000000004","quantity":2}]');
    update orders set status = 'picked_up' where id = v_farm;
    update products set quantity = 0.5 where id = '113aaaaa-0000-0000-0000-000000000004';
    v := my_order_basket(v_farm);
    if v -> 'lines' is distinct from '[{"product_id": "113aaaaa-0000-0000-0000-000000000004", "quantity": 0.5}]'::jsonb
       or (v ->> 'missing')::int is distinct from 0 then
        raise exception 'FAIL: the farm''s half kilo left: %', v;
    end if;
    update products set quantity = 0 where id = '113aaaaa-0000-0000-0000-000000000004';
    v := my_order_basket(v_farm);
    if jsonb_array_length(v -> 'lines') is distinct from 0 or (v ->> 'missing')::int is distinct from 1 then
        raise exception 'FAIL: the farm''s eggs, none left: %', v;
    end if;
    -- « Commandes en ligne » hidden (110): nothing to put back.
    insert into feature_rules (scope, org_id, feature, state)
    values ('org', '11300000-0000-0000-0000-000000000001', 'online_orders', 'hidden');
    v := my_order_basket(v_order);
    if not (v ->> 'closed')::boolean or jsonb_array_length(v -> 'lines') is distinct from 0 or (v ->> 'missing')::int is distinct from 2 then
        raise exception 'FAIL: a closed vitrine: %', v;
    end if;
    perform pg_temp.as113('11311311-0000-0000-0000-000000000006');
    if pg_temp.refused113(format('select my_order_basket(%L)', v_order)) is distinct from 'Commande introuvable.' then
        raise exception 'FAIL: Ali read Awa''s order';
    end if;
    raise notice 'PASS: the shop''s order again — the Savon at the one left, the Riz off the vitrine counted missing; the association''s booking again; the farm''s half kilo left put back as 0.5, none left missing; nothing from a vitrine that takes no orders; nobody else''s order';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: reports — a few words, five a day, the caller''s own order; the platform reads, closes (journaled, told) and undoes ---'
begin;
do $$
declare
    v_order  uuid;
    v_report uuid;
    v_action uuid;
    v jsonb;
begin
    perform pg_temp.as113('11311311-0000-0000-0000-000000000005');
    v_order := place_order('ferme-113',
        '[{"product_id":"113aaaaa-0000-0000-0000-000000000004","quantity":1}]');
    if pg_temp.refused113($q$select report_problem('order', 'court')$q$)
       is distinct from 'Dites en quelques mots ce qui ne va pas (10 caractères au moins).'
       or pg_temp.refused113($q$select report_problem('météo', 'Il pleut beaucoup trop')$q$)
       is distinct from 'Choisissez de quoi il s''agit.' then
        raise exception 'FAIL: a wrong report was taken';
    end if;
    v_report := report_problem('order', '  Les œufs sont arrivés cassés.  ', null, v_order);
    perform report_problem('vitrine', 'La photo ne montre pas le bon article.', 'Boutique-113');
    perform report_problem('app', 'L''application se ferme toute seule.');
    perform report_problem('payment', 'Je n''arrive pas à payer en espèces.');
    perform report_problem('other', 'Merci pour l''application !');
    if pg_temp.refused113($q$select report_problem('other', 'Encore une chose à dire.')$q$)
       is distinct from 'Vous avez déjà envoyé 5 signalements aujourd''hui : Mara les lit et vous répond.' then
        raise exception 'FAIL: a sixth report the same day was taken';
    end if;
    if (select org_id from problem_reports where id = v_report) is distinct from '11300000-0000-0000-0000-000000000002'
       or (select contact from problem_reports where id = v_report) is distinct from '+22670113005'
       or (select message from problem_reports where id = v_report) is distinct from 'Les œufs sont arrivés cassés.'
       or (select org_id from problem_reports where topic = 'vitrine'
             and reporter_id = '11311311-0000-0000-0000-000000000005') is distinct from '11300000-0000-0000-0000-000000000001' then
        raise exception 'FAIL: the report did not keep its order, vitrine and contact';
    end if;
    perform pg_temp.as113('11311311-0000-0000-0000-000000000006');
    if pg_temp.refused113(format('select report_problem(''order'', ''Ce n''''est pas ma commande.'', null, %L)', v_order))
       is distinct from 'Commande introuvable.' then
        raise exception 'FAIL: Ali reported on Awa''s order';
    end if;
    -- Ali, with only an e-mail, is answered there.
    perform report_problem('delivery', 'Le livreur ne trouve pas ma maison.');
    if (select contact from problem_reports where reporter_id = '11311311-0000-0000-0000-000000000006')
       is distinct from 'ali113@example.com' then
        raise exception 'FAIL: Ali''s contact is not his e-mail';
    end if;
    -- Not the platform: refused.
    if pg_temp.refused113($q$select platform_reports()$q$) is distinct from 'Réservé à la plateforme'
       or pg_temp.refused113(format('select platform_handle_report(%L)', v_report)) is distinct from 'Réservé à la plateforme' then
        raise exception 'FAIL: a shopper read or closed the reports';
    end if;
    perform pg_temp.as113('11311311-0000-0000-0000-000000000001');
    v := platform_reports();
    if jsonb_array_length(v) is distinct from 6 or v -> 0 ->> 'id' is distinct from v_report::text
       or v -> 0 ->> 'reporter' is distinct from 'Awa Ouédraogo' or v -> 0 ->> 'org_name' is distinct from 'Ferme 113'
       or v -> 0 ->> 'order_id' is distinct from v_order::text then
        raise exception 'FAIL: the platform''s list reads %', v;
    end if;
    -- 111's À faire count, when 111 is here.
    if to_regprocedure('public.platform_todo()') is not null and platform_todo() ? 'reports_open'
       and (platform_todo() ->> 'reports_open')::int is distinct from 6 then
        raise exception 'FAIL: À faire « Signalements » says %', platform_todo() ->> 'reports_open';
    end if;
    v_action := platform_handle_report(v_report, 'Remboursé par la ferme.');
    if (select status from problem_reports where id = v_report) is distinct from 'handled'
       or jsonb_array_length(platform_reports()) is distinct from 5
       or platform_reports('handled') -> 0 ->> 'answer' is distinct from 'Remboursé par la ferme.'
       or not exists (select 1 from platform_actions where id = v_action and kind = 'report'
                        and undo_fn = 'platform_undo_report')
       or not exists (select 1 from notifications where recipient_id = '11311311-0000-0000-0000-000000000005'
                        and kind = 'report_handled'
                        and message = 'Mara a traité votre signalement : Remboursé par la ferme.'
                        and params ->> 'to' = 'customer'
                        and params ->> 'answer' = 'Remboursé par la ferme.') then
        raise exception 'FAIL: closing a report';
    end if;
    if pg_temp.refused113(format('select platform_handle_report(%L)', v_report)) is distinct from 'Ce signalement est déjà traité.' then
        raise exception 'FAIL: a report closed twice';
    end if;
    perform platform_undo(v_action);
    if (select status from problem_reports where id = v_report) is distinct from 'open'
       or jsonb_array_length(platform_reports()) is distinct from 6 then
        raise exception 'FAIL: « Annuler » did not open the report again';
    end if;
    if pg_temp.refused113($q$select platform_reports('tous')$q$) is distinct from 'Liste inconnue : tous' then
        raise exception 'FAIL: an unknown list was read';
    end if;
    raise notice 'PASS: a report needs its topic and ten letters, keeps its order (the farm), vitrine (the shop) and how to answer (the proved number, else the e-mail); five a day; nobody else''s order; the platform reads them oldest first, closes one (journaled, Awa told) and « Annuler » opens it again; À faire counts them when 111 is here';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: the help number — digits only, the platform''s to set, read by the page ---'
begin;
do $$
declare v_action uuid;
begin
    perform pg_temp.as113('11311311-0000-0000-0000-000000000002');
    if pg_temp.refused113($q$select platform_set_setting('support_whatsapp', '"22670000000"')$q$)
       is distinct from 'Réservé à la plateforme' then
        raise exception 'FAIL: a shop owner set the help number';
    end if;
    perform pg_temp.as113('11311311-0000-0000-0000-000000000001');
    if pg_temp.refused113($q$select platform_set_setting('support_whatsapp', '"le support"')$q$)
       is distinct from 'Le numéro WhatsApp de l''aide : l''indicatif du pays puis le numéro, en chiffres (par exemple 22670000000).'
       or pg_temp.refused113($q$select platform_set_setting('support_whatsapp', '"7000"')$q$)
       is distinct from 'Le numéro WhatsApp de l''aide : l''indicatif du pays puis le numéro, en chiffres (par exemple 22670000000).' then
        raise exception 'FAIL: a wrong help number was taken';
    end if;
    v_action := platform_set_setting('support_whatsapp', '"+226 70 11 30 00"');
    if support_whatsapp() is distinct from '22670113000' then
        raise exception 'FAIL: the help number reads %', support_whatsapp();
    end if;
    perform pg_temp.as113('11311311-0000-0000-0000-000000000005');
    if my_shopper_profile() ->> 'support_whatsapp' is distinct from '22670113000' then
        raise exception 'FAIL: the page does not carry the help number';
    end if;
    perform pg_temp.as113('11311311-0000-0000-0000-000000000001');
    perform platform_undo(v_action);
    if support_whatsapp() is not null then
        raise exception 'FAIL: « Annuler » did not empty the help number';
    end if;
    -- Emptied by hand too: the row hidden again.
    perform platform_set_setting('support_whatsapp', '"+226 70 11 30 00"');
    perform platform_set_setting('support_whatsapp', '""');
    if support_whatsapp() is not null then
        raise exception 'FAIL: an emptied number still reads';
    end if;
    raise notice 'PASS: only the platform sets it, digits (8 to 15) once spaces and « + » are out, journaled and undone; the page reads « 22670113000 »; empty, nothing';
end $$;
rollback;

\echo ''
\echo '--- TEST 9: « Mes données » — the caller''s own, every part ---'
begin;
do $$
declare v jsonb;
begin
    perform pg_temp.as113('11311311-0000-0000-0000-000000000006');
    perform place_order('boutique-113', '[{"product_id":"113aaaaa-0000-0000-0000-000000000001","quantity":1}]');
    perform pg_temp.as113('11311311-0000-0000-0000-000000000005');
    perform place_order('ferme-113', '[{"product_id":"113aaaaa-0000-0000-0000-000000000004","quantity":2}]',
                        'pickup', 'Vers midi');
    perform follow_vitrine('entraide-113');
    perform save_my_address(null, 'home', null, 'Ouaga 2000', 'Portail bleu', null, null);
    perform set_my_shopper_settings('{"city": "Ouagadougou"}');
    perform report_problem('app', 'Le bouton ne répond pas toujours.');
    v := my_data_export();
    if v #>> '{profile,first_name}' is distinct from 'Awa' or v #>> '{profile,email}' is distinct from 'awa113@example.com'
       or v #>> '{profile,verified_phone}' is distinct from '+22670113005'
       or v #>> '{settings,city}' is distinct from 'Ouagadougou'
       or v #>> '{addresses,0,note}' is distinct from 'Portail bleu'
       or v #>> '{favourites,0,address}' is distinct from 'marakaj.com/s/entraide-113'
       or jsonb_array_length(v -> 'orders') is distinct from 1
       or v #>> '{orders,0,vitrine}' is distinct from 'Ferme 113' or v #>> '{orders,0,note}' is distinct from 'Vers midi'
       or v #>> '{orders,0,lines,0,name}' is distinct from 'Œufs 113'
       or jsonb_array_length(v -> 'reports') is distinct from 1 then
        raise exception 'FAIL: Awa''s data reads %', v;
    end if;
    perform pg_temp.as113(null);
    if pg_temp.refused113('select my_data_export()') is distinct from 'Connectez-vous d''abord' then
        raise exception 'FAIL: a stranger downloaded data';
    end if;
    raise notice 'PASS: Awa''s profile (e-mail, proved number), city, address, favourite, her one order with its lines, her report — not Ali''s order; a stranger gets nothing';
end $$;
rollback;

\echo ''
\echo '--- TEST 10: « Supprimer mon compte » — the Worker''s question, and the deletion it then does ---'
begin;
do $$
declare v_order uuid;
begin
    perform pg_temp.as113('11311311-0000-0000-0000-000000000005');
    if delete_my_account_check() is distinct from '11311311-0000-0000-0000-000000000005' then
        raise exception 'FAIL: a shopper with nothing open may not go';
    end if;
    v_order := place_order('boutique-113', '[{"product_id":"113aaaaa-0000-0000-0000-000000000001","quantity":1}]');
    if pg_temp.refused113('select delete_my_account_check()')
       is distinct from 'Une commande est en cours : attendez qu''elle soit terminée, ou annulez-la, puis supprimez votre compte.' then
        raise exception 'FAIL: an open order did not hold the account';
    end if;
    update orders set status = 'cancelled' where id = v_order;
    perform delete_my_account_check();
    perform pg_temp.as113('11311311-0000-0000-0000-000000000008');
    if pg_temp.refused113('select delete_my_account_check()')
       is distinct from 'Vous faites partie d''une activité sur Mara : votre compte se supprime une fois que vous n''en faites plus partie.' then
        raise exception 'FAIL: a business''s employee may go from here';
    end if;
    perform pg_temp.as113('11311311-0000-0000-0000-000000000002');
    if pg_temp.refused113('select delete_my_account_check()')
       is distinct from 'Vous faites partie d''une activité sur Mara : votre compte se supprime une fois que vous n''en faites plus partie.' then
        raise exception 'FAIL: an owner may go from here';
    end if;
    perform pg_temp.as113('11311311-0000-0000-0000-000000000007');
    if pg_temp.refused113('select delete_my_account_check()')
       is distinct from 'Vous êtes livreur sur Mara : écrivez à Mara pour fermer votre compte livreur.' then
        raise exception 'FAIL: a courier may go from here';
    end if;
    perform pg_temp.as113('11311311-0000-0000-0000-000000000001');
    if pg_temp.refused113('select delete_my_account_check()') is distinct from 'Un compte de la plateforme ne se supprime pas ici.' then
        raise exception 'FAIL: a platform account may go from here';
    end if;
    perform pg_temp.as113(null);
    if pg_temp.refused113('select delete_my_account_check()') is distinct from 'Connectez-vous d''abord' then
        raise exception 'FAIL: a stranger was answered';
    end if;
end $$;
-- A former employee: no longer a member, but an article she put on the
-- shelf still names her (products.created_by, « no action »). GoTrue's
-- delete would fail on it, so the check says so first, in words.
do $$
declare v_lea constant uuid := '11311311-0000-0000-0000-000000000009';
begin
    update products set created_by = v_lea where id = '113aaaaa-0000-0000-0000-000000000002';
    perform pg_temp.as113(v_lea);
    if pg_temp.refused113('select delete_my_account_check()')
       is distinct from 'Votre nom reste sur ce que vous avez inscrit pour une activité sur Mara (ventes, stock, factures…) : écrivez à Mara pour fermer votre compte.' then
        raise exception 'FAIL: a former employee''s work did not hold the account';
    end if;
    perform pg_temp.as113(null);
    begin
        delete from auth.users where id = v_lea;
        raise exception 'FAIL: the deletion went through past a « no action » key — the check guards nothing';
    exception when foreign_key_violation then
        null;
    end;
    update products set created_by = null where id = '113aaaaa-0000-0000-0000-000000000002';
    perform pg_temp.as113(v_lea);
    if delete_my_account_check() is distinct from v_lea then
        raise exception 'FAIL: once nothing names her, Léa may still not go';
    end if;
    raise notice 'PASS: a former employee''s article holds her account, said in words (the delete itself would fail on that key); let go, she may go';
end $$;
-- What the Worker then does with the answer: GoTrue deletes auth.users.
-- Awa's orders stay the shop's — one cancelled, one handed over with its
-- sale, its events and its stock move — under « Client supprimé ».
do $$
declare
    v_awa   constant uuid := '11311311-0000-0000-0000-000000000005';
    v_done  uuid;
    v_sale  uuid;
begin
    perform pg_temp.as113(v_awa);
    perform follow_vitrine('boutique-113');
    perform save_my_address(null, 'home', null, 'Ouaga 2000', null, null, null);
    perform set_my_shopper_settings('{"city": "Ouagadougou"}');
    perform report_problem('app', 'Je pars, merci pour tout.');
    v_done := place_order('boutique-113', '[{"product_id":"113aaaaa-0000-0000-0000-000000000001","quantity":2}]');
    perform pg_temp.as113(null);
    update orders set address = 'Ouaga 2000, portail bleu', drop_lat = 12.33, drop_lng = -1.52
     where id = v_done;
    update orders set status = 'accepted' where id = v_done;
    update orders set status = 'picked_up' where id = v_done;
    select id into v_sale from sales where order_id = v_done;
    if v_sale is null then
        raise exception 'FAIL: the handed-over order made no sale (setup)';
    end if;
end $$;
do $$
declare
    v_awa constant uuid := '11311311-0000-0000-0000-000000000005';
    v_n   int;
begin
    perform pg_temp.as113(v_awa);
    if delete_my_account_check() is distinct from v_awa then
        raise exception 'FAIL: a shopper with only finished orders may not go';
    end if;
    perform pg_temp.as113(null);
    delete from auth.users where id = v_awa;
    if exists (select 1 from profiles where id = v_awa)
       or exists (select 1 from orders where customer_id = v_awa)
       or exists (select 1 from vitrine_follows where user_id = v_awa)
       or exists (select 1 from shopper_addresses where user_id = v_awa)
       or exists (select 1 from shopper_settings where user_id = v_awa)
       or exists (select 1 from problem_reports where reporter_id = v_awa) then
        raise exception 'FAIL: the deletion left the person''s rows';
    end if;
    -- Both orders kept, the person gone from them.
    select count(*) into v_n from orders
     where org_id = '11300000-0000-0000-0000-000000000001' and customer_id is null
       and customer_name = 'Client supprimé' and phone is null and address is null
       and drop_lat is null and drop_lng is null;
    if v_n <> 2 or exists (select 1 from orders where org_id = '11300000-0000-0000-0000-000000000001'
                                                  and customer_name like 'Awa%') then
        raise exception 'FAIL: the orders were not kept anonymised (% of 2)', v_n;
    end if;
    if not exists (select 1 from orders o
                    join sales s on s.order_id = o.id
                    join order_lines l on l.order_id = o.id
                    join order_stock_moves m on m.order_id = o.id and m.direction = 'out'
                   where o.customer_name = 'Client supprimé' and o.status = 'picked_up')
       or (select count(*) from order_events e join orders o on o.id = e.order_id
            where o.customer_name = 'Client supprimé') < 4 then
        raise exception 'FAIL: the handed-over order lost its sale, lines, stock move or events';
    end if;
    raise notice 'PASS: a shopper may go (her own id answered), not with an order open; not an employee, an owner, a courier, a platform account, a stranger; the deletion takes her profile, follows, addresses, settings and reports, and leaves her two orders (one handed over, with its sale, lines, stock move and events) to the shop as « Client supprimé », no phone, address or pin';
end $$;
rollback;

\echo ''
\echo '--- TEST 11: the doors — closed to the street, the internals to everyone, the platform''s its own ---'
do $$
declare
    v_doors text[] := array[
        'support_whatsapp()', 'my_shopper_profile()', 'set_my_shopper_settings(jsonb)',
        'follow_vitrine(text)', 'unfollow_vitrine(uuid)', 'set_follow_news(uuid, boolean)',
        'my_follows()', 'save_my_address(uuid, text, text, text, text, double precision, double precision)',
        'delete_my_address(uuid)', 'my_order_basket(uuid)', 'report_problem(text, text, text, uuid)',
        'my_data_export()', 'delete_my_account_check()',
        'platform_reports(text)', 'platform_handle_report(uuid, text)'];
    v_inside text[] := array['trg_support_whatsapp()', 'trg_vitrine_news()', 'my_addresses()',
                             'platform_undo_report(jsonb)', 'trg_profile_gone_orders()'];
    f text;
begin
    foreach f in array v_doors || v_inside loop
        if has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: % is open to the street', f;
        end if;
        if not exists (select 1 from pg_proc where oid = f::regprocedure and proconfig is not null) then
            raise exception 'FAIL: % has no search_path', f;
        end if;
    end loop;
    foreach f in array v_doors loop
        if not has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: % is closed to a signed-in person', f;
        end if;
    end loop;
    foreach f in array v_inside loop
        if has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: % is open to a signed-in person', f;
        end if;
    end loop;
    -- The tables are read through the doors only.
    if exists (select 1 from pg_class c
                where c.relname in ('shopper_settings', 'vitrine_follows', 'shopper_addresses', 'problem_reports')
                  and (not c.relrowsecurity
                       or exists (select 1 from pg_policy p where p.polrelid = c.oid))) then
        raise exception 'FAIL: a table of 113 is readable past its doors';
    end if;
    if not exists (select 1 from platform_undo_fns where fn = 'platform_undo_report') then
        raise exception 'FAIL: the report''s undo is not known to the journal';
    end if;
    raise notice 'PASS: % doors for a signed-in person, % internals closed, none open to the street, every one with its search_path; the four tables RLS on with no policy', cardinality(v_doors), cardinality(v_inside);
end $$;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '11311311-0000-0000-0000-000000000005';
do $$
begin
    if exists (select 1 from shopper_addresses) or exists (select 1 from vitrine_follows)
       or exists (select 1 from problem_reports) or exists (select 1 from shopper_settings) then
        raise exception 'FAIL: the app''s role reads the tables directly';
    end if;
    begin
        insert into vitrine_follows (user_id, org_id)
        values ('11311311-0000-0000-0000-000000000005', '11300000-0000-0000-0000-000000000004');
        raise exception 'FAIL: the app''s role wrote a follow past the door';
    exception when insufficient_privilege then
        null;
    end;
    raise notice 'PASS: as the app, the tables answer nothing and take nothing directly';
end $$;
rollback;

-- The settings put back.
update platform_settings s set value = b.value from b113_saved b where s.key = b.key;
