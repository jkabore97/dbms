-- ============================================================
-- test_batch131.sql — an association's Catalogue, « Vous êtes ici
-- pour… », and the old businesses given what a new one gets (131).
--
-- The claims:
--   * an association's articles, as its owner makes them in the app
--     (ensure_product, then the count by hand): kept beside its services,
--     on its vitrine for a stranger, ordered from it by a signed-in
--     customer as a shop's are; the order collected takes them out of the
--     count and books the sale on « Ventes » in the association's own
--     books; an article at zero is Catalogue's red number (home_counts)
--     for an association now — a service never — and a shop's and a
--     farm's counts are what they were;
--   * arrival_pending: true for a signed-in account with no business and
--     no answer; false once answered (the first answer's time kept), for
--     a member of a business, for Mara's own, for nobody signed in;
--     arrival_answer takes only the four answers, writes only the
--     caller's own row; anon may call neither;
--   * the backfill: an old-style shop, farm and association (made before
--     their kind's chart was seeded) get every missing account — the
--     account an owner switched off stays off, renamed as they named it —
--     an owner's dial stays as they set it; a step of Le Chemin reached
--     and never marked is marked; a showcase business is left alone; and
--     running 131 again adds nothing.
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
-- Earlier suites hand the app's roles every function (063's re-run among
-- them): 131 again, so what follows tests its own grants.
\i database/migrations/131_catalogue_backfill.sql
-- The owner's numbers: earlier suites change them for their own fixtures.
update platform_settings set value = '1' where key = 'vitrine_min_items_association';
update platform_settings set value = 'false' where key = 'order_phone_verified';

\set owner   '''13113113-0000-0000-0000-000000000001'''
\set buyer   '''13113113-0000-0000-0000-000000000002'''
\set mara    '''13113113-0000-0000-0000-000000000003'''
\set shopper '''13113113-0000-0000-0000-000000000004'''
\set boss    '''13113113-0000-0000-0000-000000000005'''
\set assoc   '''13100000-0000-0000-0000-000000000001'''
\set shop    '''13100000-0000-0000-0000-000000000002'''
\set farm    '''13100000-0000-0000-0000-000000000003'''
\set oldshop '''13100000-0000-0000-0000-000000000004'''
\set oldfarm '''13100000-0000-0000-0000-000000000005'''
\set oldasso '''13100000-0000-0000-0000-000000000006'''
\set demo    '''13100000-0000-0000-0000-000000000007'''

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,   '+22613100001', '{"full_name": "Trésorière 131"}'),
    (:buyer,   '+22613100002', '{"full_name": "Awa 131"}'),
    (:mara,    '+22613100003', '{"full_name": "Mara 131"}'),
    (:shopper, '+22613100004', '{"full_name": "Issa 131"}'),
    (:boss,    '+22613100005', '{"full_name": "Patron 131"}');
update profiles set is_platform_admin = true where id = :mara;

insert into orgs (id, name, slug, profile, default_currency, storefront_enabled) values
    (:assoc, 'Entraide 131', 'entraide-131', 'association', 'XOF', true),
    (:shop,  'Boutique 131', 'boutique-131', 'retail',      'XOF', false),
    (:farm,  'Ferme 131',    'ferme-131',    'farm',        'XOF', false);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:assoc, :owner, 'owner', 'org', :assoc, 'full'),
    (:shop,  :boss,  'owner', 'org', :shop,  'full'),
    (:farm,  :boss,  'owner', 'org', :farm,  'full');
-- The association's chart, as org_create_core seeds it; a service of 098.
select seed_church_accounts(:assoc);
insert into products (org_id, name, sale_price, quantity, is_active, is_published, is_service)
values (:assoc, 'Cours du soir 131', 2000, 0, true, true, true);
-- A shop's and a farm's article at zero: their counts, as before.
insert into products (org_id, name, sale_price, quantity, is_active, is_published) values
    (:shop, 'Savon 131', 500, 0, true, true),
    (:farm, 'Œufs 131',  2500, 0, true, true);

create temp table t131 (which text primary key, id uuid);
grant all on t131 to authenticated, anon;

\echo ''
\echo '--- TEST 1: an association makes its articles, beside its services ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '13113113-0000-0000-0000-000000000001';
do $$
declare
    v_id uuid;
    c jsonb;
begin
    -- « ＋ › Un article »: the app's ensure_product, then the count by hand
    -- (an association buys nothing: no purchase is booked).
    v_id := ensure_product('13100000-0000-0000-0000-000000000001', 'T-shirt 131', 3000,
                           null, null, null, '13113113-0000-0000-0000-000000000001', false);
    update products set quantity = 5, unit = 'pièce', is_published = true where id = v_id;
    insert into t131 values ('tshirt', v_id);
    -- A ticket not counted yet: on the shelf at zero.
    v_id := ensure_product('13100000-0000-0000-0000-000000000001', 'Billet soirée 131', 1000,
                           null, null, null, '13113113-0000-0000-0000-000000000001', false);
    insert into t131 values ('ticket', v_id);
    if (select count(*) from products where org_id = '13100000-0000-0000-0000-000000000001'
                                       and not is_service) <> 2
       or (select count(*) from products where org_id = '13100000-0000-0000-0000-000000000001'
                                          and is_service) <> 1 then
        raise exception 'FAIL: the association''s catalogue is not two articles and a service';
    end if;
    -- Catalogue's red number: the ticket at zero, never the service.
    c := home_counts('13100000-0000-0000-0000-000000000001');
    if (c ->> 'articles')::int <> 1 then
        raise exception 'FAIL: the association counts % articles to see (want 1): %', c ->> 'articles', c;
    end if;
    if exists (select 1 from stock_receipts where org_id = '13100000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: an association''s article booked a purchase';
    end if;
end $$;
-- The shop's and the farm's counts are what they were.
set local "request.jwt.claim.sub" = '13113113-0000-0000-0000-000000000005';
do $$
declare s jsonb := home_counts('13100000-0000-0000-0000-000000000002');
        f jsonb := home_counts('13100000-0000-0000-0000-000000000003');
begin
    if s <> jsonb_build_object('orders', 0, 'bookings', 0, 'articles', 1, 'invoices', 0,
                               'credit', 0, 'invitations', 0, 'supplies', 0, 'livestock', 0) then
        raise exception 'FAIL: the shop counts %', s;
    end if;
    if (f ->> 'articles')::int <> 1 then
        raise exception 'FAIL: the farm counts %', f;
    end if;
end $$;
commit;
do $$ begin
    raise notice 'PASS: an association''s two articles beside its service, made as the app makes them, no purchase booked; Catalogue counts the one at zero (not the service); the shop''s and the farm''s counts unchanged';
end $$;

\echo ''
\echo '--- TEST 2: its vitrine shows them; a customer orders one as from a shop ---'
begin;
set local role anon;
do $$
declare n int;
begin
    select count(*) into n from storefront_products('entraide-131') where not is_service;
    if n <> 2 then raise exception 'FAIL: the vitrine shows % articles to a stranger', n; end if;
    select count(*) into n from storefront_products('entraide-131') where is_service;
    if n <> 1 then raise exception 'FAIL: the vitrine lost the service'; end if;
    if (select in_stock from storefront_products('entraide-131') where name = 'T-shirt 131') is not true
       -- (null, not false, for an article at zero with no date: 110's)
       or (select in_stock from storefront_products('entraide-131') where name = 'Billet soirée 131') is true then
        raise exception 'FAIL: what can be ordered is not said';
    end if;
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '13113113-0000-0000-0000-000000000002';
do $$ begin
    insert into t131 values ('order', place_order('entraide-131',
        jsonb_build_array(jsonb_build_object(
            'product_id', (select id from t131 where which = 'tshirt'), 'quantity', 2)),
        'pickup', 'Samedi', null, null, 'cash'));
    -- The ticket has no count: refused, as a shop's article at zero is.
    begin
        perform place_order('entraide-131',
            jsonb_build_array(jsonb_build_object(
                'product_id', (select id from t131 where which = 'ticket'), 'quantity', 1)),
            'pickup', null, null, null, 'cash');
        raise exception 'FAIL: an article at zero was ordered';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
end $$;
commit;
-- The treasurer accepts it and hands it over.
update orders set status = 'accepted' where id = (select id from t131 where which = 'order');
update orders set status = 'picked_up' where id = (select id from t131 where which = 'order');
do $$
declare
    v_entry uuid;
begin
    if (select quantity from products where id = (select id from t131 where which = 'tshirt')) <> 3 then
        raise exception 'FAIL: the order did not take its two t-shirts out of the count';
    end if;
    select entry_id into v_entry from sales
     where order_id = (select id from t131 where which = 'order');
    if v_entry is null then raise exception 'FAIL: the collected order booked no sale'; end if;
    if not exists (select 1 from journal_lines jl join accounts a on a.id = jl.account_id
                    where jl.journal_entry_id = v_entry and a.type = 'income'
                      and a.name = 'Ventes' and jl.credit = 6000
                      and a.org_id = '13100000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the sale is not on « Ventes » in the association''s books';
    end if;
    if exists (select 1 from notifications where org_id = '13100000-0000-0000-0000-000000000001'
                                             and kind = 'new_order')
       is not true then
        raise exception 'FAIL: the treasurer was not told of the order';
    end if;
    raise notice 'PASS: the vitrine shows the association''s articles and service to a stranger, in stock or not; a customer orders a t-shirt (a ticket at zero refused); collected: out of the count, 6 000 on « Ventes » in its books, the treasurer told';
end $$;

\echo ''
\echo '--- TEST 3: « Vous êtes ici pour… » once, never for a business''s people ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '13113113-0000-0000-0000-000000000004';
do $$
declare
    v_at timestamptz;
begin
    if not arrival_pending() then
        raise exception 'FAIL: a new account with no business is not asked';
    end if;
    begin
        perform arrival_answer('acheter tout');
        raise exception 'FAIL: an unknown answer was taken';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    perform arrival_answer('sell');
    if arrival_pending() then raise exception 'FAIL: asked again after an answer'; end if;
    select arrival_asked_at into v_at from profiles where id = '13113113-0000-0000-0000-000000000004';
    perform arrival_answer('later');
    if (select arrival_asked_at from profiles where id = '13113113-0000-0000-0000-000000000004') <> v_at
       or (select arrival_intent from profiles where id = '13113113-0000-0000-0000-000000000004') <> 'later' then
        raise exception 'FAIL: the first answer''s time was not kept';
    end if;
    -- Nobody else's row was written.
    if (select arrival_asked_at from profiles where id = '13113113-0000-0000-0000-000000000002') is not null then
        raise exception 'FAIL: another account was answered for';
    end if;
end $$;
set local "request.jwt.claim.sub" = '13113113-0000-0000-0000-000000000001';
do $$ begin
    if arrival_pending() then raise exception 'FAIL: a business''s owner is asked'; end if;
end $$;
set local "request.jwt.claim.sub" = '13113113-0000-0000-0000-000000000003';
do $$ begin
    if arrival_pending() then raise exception 'FAIL: Mara''s own is asked'; end if;
end $$;
set local "request.jwt.claim.sub" = '';
do $$ begin
    if arrival_pending() then raise exception 'FAIL: nobody signed in is asked'; end if;
    begin
        perform arrival_answer('buy');
        raise exception 'FAIL: nobody answered for nobody';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
end $$;
commit;
begin;
set local role anon;
do $$ begin
    begin
        perform arrival_pending();
        raise exception 'FAIL: the public key may ask';
    exception when insufficient_privilege then null;
    end;
    begin
        perform arrival_answer('buy');
        raise exception 'FAIL: the public key may answer';
    exception when insufficient_privilege then null;
    end;
end $$;
commit;
do $$
declare v_loose int;
begin
    select count(*) into v_loose from pg_proc
     where proname in ('arrival_pending', 'arrival_answer') and prosecdef
       and not coalesce((select true from unnest(proconfig) c where c like 'search_path=%'), false);
    if v_loose > 0 then raise exception 'FAIL: a definer without its search path'; end if;
    raise notice 'PASS: asked once (an unknown answer refused, the first answer''s time kept, nobody else''s row); never a business''s owner, Mara''s own or nobody; anon may neither ask nor answer; search path pinned';
end $$;

\echo ''
\echo '--- TEST 4: the backfill — old businesses get what new ones get, choices kept ---'
-- Three businesses made the old way (no seeded chart), and a showcase one.
insert into orgs (id, name, slug, profile, default_currency) values
    (:oldshop, 'Vieille boutique 131', 'vieille-boutique-131', 'retail',      'XOF'),
    (:oldfarm, 'Vieille ferme 131',    'vieille-ferme-131',    'farm',        'XOF'),
    (:oldasso, 'Vieille entraide 131', 'vieille-entraide-131', 'association', 'XOF');
insert into orgs (id, name, slug, profile, default_currency, showcase) values
    (:demo, 'Exemple 131', 'exemple-131', 'retail', 'XOF', true);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:oldshop, :boss, 'owner', 'org', :oldshop, 'full'),
    (:oldfarm, :boss, 'owner', 'org', :oldfarm, 'full'),
    (:oldasso, :boss, 'owner', 'org', :oldasso, 'full');
-- The shop's owner had one account already, renamed and switched off — a
-- choice — and closed the articles to the employees on the dial.
insert into accounts (org_id, code, name, type, is_active) values
    (:oldshop, '5020', 'Transport (plus utilisé)', 'expense', false);
insert into org_feature_rules (org_id, tier, feature, access) values
    (:oldshop, 'employee', 'products', 'hidden');
-- An article on each shop; Le Chemin's « premier article » forgotten, as on
-- a business whose step was reached before anything synced it.
insert into products (org_id, name, sale_price, quantity, is_active, is_published) values
    (:oldshop, 'Riz 131', 1000, 4, true, true),
    (:demo,    'Riz exemple 131', 1000, 4, true, true);
delete from org_path_done where org_id in (:oldshop, :demo);

\i database/migrations/131_catalogue_backfill.sql

do $$
declare
    n int;
    a accounts%rowtype;
begin
    select count(*) into n from accounts
     where org_id = '13100000-0000-0000-0000-000000000004'
       and code in ('1000', '1010', '1020', '4000', '5000', '5010', '5020', '5030');
    if n <> 8 then raise exception 'FAIL: the old shop has % of its 8 accounts', n; end if;
    select * into a from accounts
     where org_id = '13100000-0000-0000-0000-000000000004' and code = '5020';
    if a.is_active or a.name <> 'Transport (plus utilisé)' then
        raise exception 'FAIL: the owner''s switched-off account was touched: % %', a.name, a.is_active;
    end if;
    if (select access from org_feature_rules
         where org_id = '13100000-0000-0000-0000-000000000004'
           and tier = 'employee' and feature = 'products') <> 'hidden' then
        raise exception 'FAIL: the owner''s dial was touched';
    end if;
    select count(*) into n from accounts where org_id = '13100000-0000-0000-0000-000000000005';
    if n <> 16 then raise exception 'FAIL: the old farm has % of its 16 accounts', n; end if;
    select count(*) into n from accounts where org_id = '13100000-0000-0000-0000-000000000006';
    if n <> 14 then raise exception 'FAIL: the old association has % of its 14 accounts', n; end if;
    if exists (select 1 from accounts where org_id = '13100000-0000-0000-0000-000000000007') then
        raise exception 'FAIL: the showcase business was given a chart';
    end if;
    if not exists (select 1 from org_path_done
                    where org_id = '13100000-0000-0000-0000-000000000004' and step = 'first_article') then
        raise exception 'FAIL: the old shop''s first article is still not on its Chemin';
    end if;
    if exists (select 1 from org_path_done where org_id = '13100000-0000-0000-0000-000000000007') then
        raise exception 'FAIL: the showcase business was walked down Le Chemin';
    end if;
    -- The association's numbers of the earlier tests are what they were.
    if (select count(*) from accounts where org_id = '13100000-0000-0000-0000-000000000001'
                                       and code like '40%') < 4 then
        raise exception 'FAIL: the association''s chart lost an account';
    end if;
end $$;

-- Again: nothing more.
create temp table t131_before as
    select (select count(*) from accounts) as accounts,
           (select count(*) from org_path_done) as steps,
           (select count(*) from cauris_ledger) as cauris;
\i database/migrations/131_catalogue_backfill.sql
do $$ begin
    if (select accounts from t131_before) <> (select count(*) from accounts)
       or (select steps from t131_before) <> (select count(*) from org_path_done)
       or (select cauris from t131_before) <> (select count(*) from cauris_ledger) then
        raise exception 'FAIL: 131 run twice added something';
    end if;
    raise notice 'PASS: old shop, farm and association get their kind''s whole chart (8, 16, 14); the account the owner renamed and switched off kept as it was; the owner''s dial kept; « premier article » marked on Le Chemin; the showcase left alone; run again, nothing more';
end $$;

-- Tidy: the profiles' answers and the fixtures go with the run's database.
