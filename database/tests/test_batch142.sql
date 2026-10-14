-- ============================================================
-- test_batch142.sql — batch 147 (142): Mara's new Conditions
-- d'utilisation, accepted by everyone, enforced by the server.
-- Phone block 142.
--
-- The claims:
--   1. installed twice, the same: the table (RLS on, one read policy, no
--      write), the setting (terms 2, privacy 2, seller 1, courier 2, a
--      30-day grace), the two triggers, courier_rules' charter version 2,
--      112's charter acceptances kept as courier version 1;
--   2. my_terms_state(): a new account must accept the terms and the
--      privacy policy; a business owner also the seller's commitments, an
--      approved courier the courier's; accept_terms() writes once, the
--      current version only, a known document only; the platform and the
--      app version kept; the gate empties;
--   3. RLS: each person reads their own rows only, writes none (no insert,
--      update or delete, even of their own); anon reads nothing and calls
--      nothing (42501 at the door);
--   4. an order is refused without the terms (shop, farm, association) and
--      taken once they are accepted; the business's own staff recording
--      nothing through place_order is not asked;
--   5. creating a business is refused without the seller's commitments —
--      create_my_business for a shop, a farm and an association, and
--      create_org for a platform admin — and goes through once accepted;
--   6. sending a courier's application is refused without the courier's
--      charter acceptance, and the charter step is itself the acceptance;
--      a dossier sent back with an older charter reopens its charter step
--      (else it could never be sent again); the courier who carries an
--      order no longer reads its row — nor its delivery code;
--   7. existing people: an account made before the version is let through
--      by the server while its grace lasts (an order, a creation), and
--      refused after it; existing businesses and approved couriers keep
--      working (an owner records a sale, a courier's board answers);
--      internal paths (no caller) are never asked;
--   8. a new version (platform_terms_bump): the platform's alone, journaled,
--      the version up, « what changed » said, everyone asked again, the old
--      acceptance no longer enough after its grace; the board counts; a
--      person's fiche lists their acceptances;
--   9. the doors: definers, search_path pinned, closed to anon and PUBLIC,
--      the app's open to authenticated, the internal ones closed.
-- Shop, farm and association throughout.
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
grant usage on schema auth to anon, authenticated;
-- As the other suites: every table to the app's role, so RLS is the wall.
grant select, insert, update, delete on all tables in schema public to authenticated;
-- 142 twice: what it grants and revokes is what is tested, and it is
-- re-runnable. (An earlier suite may have re-applied 111, 112 or 122.)
\i database/migrations/142_terms_acceptance.sql
\i database/migrations/142_terms_acceptance.sql
grant select, insert, update, delete on all tables in schema public to authenticated;
revoke insert, update, delete, truncate on table terms_acceptances from authenticated;

-- The accounts below have accepted nothing: the rig's stub (supabase_stub)
-- accepts for every other suite's people; not for these.
set test.terms_stub = 'off';

\set mara    '''14214214-0000-0000-0000-000000000001'''
\set newt    '''14214214-0000-0000-0000-000000000002'''
\set old     '''14214214-0000-0000-0000-000000000003'''
\set sowner  '''14214214-0000-0000-0000-000000000004'''
\set fowner  '''14214214-0000-0000-0000-000000000005'''
\set aowner  '''14214214-0000-0000-0000-000000000006'''
\set maker   '''14214214-0000-0000-0000-000000000007'''
\set rider   '''14214214-0000-0000-0000-000000000008'''
\set vet     '''14214214-0000-0000-0000-000000000009'''
\set other   '''14214214-0000-0000-0000-000000000010'''
\set shop    '''14200000-0000-0000-0000-000000000001'''
\set farm    '''14200000-0000-0000-0000-000000000002'''
\set assoc   '''14200000-0000-0000-0000-000000000003'''

update platform_settings set value = '1'
 where key in ('vitrine_min_items', 'vitrine_min_items_association');
update platform_settings set value = 'false'
 where key in ('order_phone_verified', 'create_phone_verified', 'courier_phone_verified', 'courier_licence_required');

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    (:mara,   '+22614200001', 'mara142@example.com',   '{"full_name": "Équipe Mara 142"}',        now()),
    (:newt,   '+22614200002', 'client142@example.com', '{"full_name": "Client Nouveau 142"}',     now()),
    -- Here before 142: its grace applies.
    (:old,    '+22614200003', 'ancien142@example.com', '{"full_name": "Client Ancien 142"}',      now() - interval '1 year'),
    (:sowner, '+22614200004', 'shop142@example.com',   '{"full_name": "Gérance Maison Élégance"}', now() - interval '1 year'),
    (:fowner, '+22614200005', 'farm142@example.com',   '{"full_name": "Gérance Ferme Horizon"}',  now() - interval '1 year'),
    (:aowner, '+22614200006', 'asso142@example.com',   '{"full_name": "Trésorerie Fondation Espoir"}', now() - interval '1 year'),
    (:maker,  '+22614200007', 'maker142@example.com',  '{"full_name": "Créatrice 142"}',          now()),
    (:rider,  '+22614200008', 'rider142@example.com',  '{"full_name": "Livreur Candidat 142"}',   now()),
    (:vet,    '+22614200009', 'vet142@example.com',    '{"full_name": "Livreur Confirmé 142"}',   now() - interval '1 year'),
    (:other,  '+22614200010', 'other142@example.com',  '{"full_name": "Compte Étranger 142"}',    now());
update profiles set is_platform_admin = true where id = :mara;
update profiles p set phone = u.phone from auth.users u where u.id = p.id and p.phone is null;

insert into orgs (id, name, slug, profile, default_currency, plan, storefront_enabled, storefront_blurb, city) values
    (:shop,  'Maison Élégance',   'maison-elegance-142', 'retail',      'XOF', 'free', true, 'Bienvenue', 'Ouagadougou'),
    (:farm,  'Ferme Horizon',     'ferme-horizon-142',   'farm',        'XOF', 'free', true, 'Bienvenue', 'Ouagadougou'),
    (:assoc, 'Fondation Espoir',  'fondation-espoir-142', 'association', 'XOF', 'free', true, 'Bienvenue', 'Ouagadougou');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :sowner, 'owner', 'org', :shop,  'full'),
    (:farm,  :fowner, 'owner', 'org', :farm,  'full'),
    (:assoc, :aowner, 'owner', 'org', :assoc, 'full');
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published) values
    ('142aaaaa-0000-0000-0000-000000000001', :shop, 'Pagne Wax 142', 5000, 3000, 50, true, true),
    ('142aaaaa-0000-0000-0000-000000000002', :farm, 'Plateau d''œufs 142', 2500, 0, 50, true, true);
insert into products (id, org_id, name, sale_price, is_service, is_active, is_published) values
    ('142aaaaa-0000-0000-0000-000000000003', :assoc, 'Adhésion 142', 1000, true, true, true);

-- An approved courier from before 142, who ticked 112's charter (version 1).
insert into couriers (user_id, phone, status, decided_at) values (:vet, '+22614200009', 'approved', now() - interval '6 months');
insert into courier_applications (user_id, status, city, zones, charter_version, charter_at, sent_at, phone)
values (:vet, 'approved', 'Ouagadougou', array['Gounghin'], 1, now() - interval '7 months', now() - interval '7 months', '+22614200009')
on conflict (user_id) do update set charter_version = 1, charter_at = excluded.charter_at;
-- As 142's backfill keeps it (this row came after 142 was applied).
insert into terms_acceptances (user_id, document, version, accepted_at)
values (:vet, 'courier', 1, now() - interval '7 months') on conflict do nothing;

-- As PostgREST names a caller.
create or replace function pg_temp.as_(p_who uuid)
returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true);
$$;

-- The refusal of a call, in its words; null when it went through.
create or replace function pg_temp.refusal(p_sql text)
returns text language plpgsql as $$
begin
    execute p_sql;
    return null;
exception when others then
    return sqlerrm;
end;
$$;

-- An order as someone, taken back: its id, or the refusal.
create or replace function pg_temp.order_as(p_who uuid, p_slug text, p_product uuid)
returns text language plpgsql as $$
declare v_id uuid;
begin
    perform pg_temp.as_(p_who);
    begin
        v_id := place_order(p_slug, jsonb_build_array(jsonb_build_object('product_id', p_product, 'quantity', 1)),
                            'pickup', 'Samedi 10 h', null, '+22670000000');
        raise exception using errcode = 'P0142', message = 'taken back';
    exception
        when sqlstate 'P0142' then return 'ordered';
        when others then return sqlerrm;
    end;
end;
$$;

-- A business created as someone, taken back.
create or replace function pg_temp.create_as(p_who uuid, p_profile text, p_slug text)
returns text language plpgsql as $$
declare v_id uuid;
begin
    perform pg_temp.as_(p_who);
    begin
        v_id := create_my_business(p_profile, 'Activité ' || p_slug, p_slug,
                                   case p_profile when 'retail' then 'alimentation'
                                                  when 'farm' then 'volaille'
                                                  else (select (business_activities('association'))[1]) end,
                                   null, 'Ouagadougou', 'Gounghin', '+22670142000', 'XOF', null);
        raise exception using errcode = 'P0142', message = 'taken back';
    exception
        when sqlstate 'P0142' then return 'created';
        when others then return sqlerrm;
    end;
end;
$$;

\set refuse_order '''Acceptez d''''abord les Conditions d''''utilisation de Mara pour commander (mettez l''''application à jour si elle ne vous les montre pas).'''
\set refuse_seller '''Acceptez d''''abord les engagements du vendeur pour créer une activité (mettez l''''application à jour si elle ne vous les montre pas).'''

\echo ''
\echo '--- TEST 1: installed twice, the same ---'
do $$
declare v jsonb := (select value from platform_settings where key = 'terms_versions');
begin
    if not (select relrowsecurity from pg_class where oid = 'public.terms_acceptances'::regclass) then
        raise exception 'FAIL: RLS is off on terms_acceptances';
    end if;
    if (select count(*) from pg_policy where polrelid = 'public.terms_acceptances'::regclass) <> 1
       or (select polcmd from pg_policy where polrelid = 'public.terms_acceptances'::regclass) <> 'r' then
        raise exception 'FAIL: terms_acceptances has a policy other than its one read policy';
    end if;
    if (v -> 'terms' ->> 'version')::int <> 2 or (v -> 'privacy' ->> 'version')::int <> 2
       or (v -> 'seller' ->> 'version')::int <> 1 or (v -> 'courier' ->> 'version')::int <> 2
       or (v -> 'terms' ->> 'grace_until')::timestamptz - (v -> 'terms' ->> 'since')::timestamptz <> interval '30 days'
       or v ->> 'changes' is null or v ->> 'changes_en' is null or v ->> 'date' <> '2026-10-14' then
        raise exception 'FAIL: terms_versions reads %', v;
    end if;
    if (select count(*) from platform_settings where key = 'terms_versions') <> 1 then
        raise exception 'FAIL: the setting twice';
    end if;
    if not exists (select 1 from pg_trigger where tgname = 'orders_terms_check' and tgrelid = 'public.orders'::regclass)
       or not exists (select 1 from pg_trigger where tgname = 'courier_applications_terms'
                       and tgrelid = 'public.courier_applications'::regclass) then
        raise exception 'FAIL: a trigger is missing';
    end if;
    if (courier_rules() ->> 'charter_version')::int <> 2 then
        raise exception 'FAIL: the charter''s version is not the courier document''s';
    end if;
    -- 105's board never lists it (an object, as application_form).
    perform pg_temp.as_('14214214-0000-0000-0000-000000000001');
    if platform_settings_board() ? 'terms_versions' then
        raise exception 'FAIL: the settings board lists terms_versions';
    end if;
    raise notice 'PASS: the table (RLS, one read policy), the setting (2/2/1/2, 30 days of grace), the triggers, the charter version 2; 105''s board leaves it out';
end $$;

\echo ''
\echo '--- TEST 2: my_terms_state and accept_terms ---'
do $$
declare v jsonb;
begin
    perform pg_temp.as_('14214214-0000-0000-0000-000000000002');
    v := my_terms_state();
    if v -> 'gate' <> '["terms", "privacy"]'::jsonb
       or (v -> 'documents' -> 'terms' ->> 'current')::int <> 2
       or v -> 'documents' -> 'terms' -> 'accepted' <> 'null'::jsonb
       or not (v -> 'documents' -> 'seller' ->> 'pending')::boolean
       or (v ->> 'changed')::boolean or (v ->> 'version')::int <> 142 then
        raise exception 'FAIL: a new account reads %', v;
    end if;
    if pg_temp.refusal('select accept_terms(''terms'', 1)') is distinct from
       'Ces conditions ont changé entre-temps : relisez-les, puis acceptez-les à nouveau.'
       or pg_temp.refusal('select accept_terms(''terms'', 3)') is distinct from
       'Ces conditions ont changé entre-temps : relisez-les, puis acceptez-les à nouveau.'
       or pg_temp.refusal('select accept_terms(''cgv'', 2)') is distinct from 'Document inconnu.'
       or pg_temp.refusal('select accept_terms(null, 2)') is distinct from 'Document inconnu.' then
        raise exception 'FAIL: an old, a future or an unknown document was accepted';
    end if;
    perform accept_terms('terms', 2, 'android', '1.0.0+abc1234');
    perform accept_terms('terms', 2, 'android', '1.0.0+abc1234');
    v := accept_terms('privacy', 2, 'telephone', repeat('x', 60));
    if v -> 'gate' <> '[]'::jsonb or (v -> 'documents' -> 'terms' ->> 'accepted')::int <> 2 then
        raise exception 'FAIL: accepted, the state reads %', v;
    end if;
    if (select count(*) from terms_acceptances where user_id = '14214214-0000-0000-0000-000000000002') <> 2
       or (select platform from terms_acceptances where user_id = '14214214-0000-0000-0000-000000000002' and document = 'terms') <> 'android'
       or (select app_version from terms_acceptances where user_id = '14214214-0000-0000-0000-000000000002' and document = 'terms') <> '1.0.0+abc1234'
       or (select platform from terms_acceptances where user_id = '14214214-0000-0000-0000-000000000002' and document = 'privacy') is not null
       or (select char_length(app_version) from terms_acceptances where user_id = '14214214-0000-0000-0000-000000000002' and document = 'privacy') <> 40 then
        raise exception 'FAIL: the rows are not one per document, with what the app said';
    end if;
    -- An owner (shop, farm, association): the seller's commitments too.
    perform pg_temp.as_('14214214-0000-0000-0000-000000000004');
    if my_terms_state() -> 'gate' <> '["terms", "privacy", "seller"]'::jsonb
       or not (my_terms_state() ->> 'owner')::boolean then
        raise exception 'FAIL: a shop owner reads %', my_terms_state();
    end if;
    perform pg_temp.as_('14214214-0000-0000-0000-000000000005');
    if my_terms_state() -> 'gate' <> '["terms", "privacy", "seller"]'::jsonb then
        raise exception 'FAIL: a farm owner reads %', my_terms_state();
    end if;
    perform pg_temp.as_('14214214-0000-0000-0000-000000000006');
    if my_terms_state() -> 'gate' <> '["terms", "privacy", "seller"]'::jsonb then
        raise exception 'FAIL: an association owner reads %', my_terms_state();
    end if;
    -- An approved courier who accepted 112's charter (1): the new one (2).
    perform pg_temp.as_('14214214-0000-0000-0000-000000000009');
    v := my_terms_state();
    if v -> 'gate' <> '["terms", "privacy", "courier"]'::jsonb
       or (v -> 'documents' -> 'courier' ->> 'accepted')::int <> 1 then
        raise exception 'FAIL: an approved courier reads %', v;
    end if;
    perform pg_temp.as_(null);
    if pg_temp.refusal('select my_terms_state()') is distinct from 'Connectez-vous pour accepter les conditions.'
       or pg_temp.refusal('select accept_terms(''terms'', 2)') is distinct from 'Connectez-vous pour accepter les conditions.' then
        raise exception 'FAIL: nobody signed in was answered';
    end if;
    raise notice 'PASS: a new account must accept the terms and the privacy policy; an owner (shop, farm, association) the seller''s too, an approved courier the courier''s; the current version only, once, with its platform and app version';
end $$;

\echo ''
\echo '--- TEST 3: RLS — one''s own rows, no writes, nothing for anon ---'
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '14214214-0000-0000-0000-000000000002', true);
do $$
declare v_state text;
begin
    if (select count(*) from terms_acceptances) <> 2
       or exists (select 1 from terms_acceptances where user_id <> auth.uid()) then
        raise exception 'FAIL: a person reads somebody else''s acceptances';
    end if;
    begin
        insert into terms_acceptances (user_id, document, version) values (auth.uid(), 'seller', 1);
        raise exception 'FAIL: a person wrote an acceptance directly';
    exception when insufficient_privilege then null;
    end;
    begin
        update terms_acceptances set version = 9;
        raise exception 'FAIL: a person changed an acceptance';
    exception when insufficient_privilege then null;
    end;
    begin
        delete from terms_acceptances;
        raise exception 'FAIL: a person deleted an acceptance';
    exception when insufficient_privilege then null;
    end;
    raise notice 'PASS: authenticated reads its own two rows, and inserts, updates and deletes nothing';
end $$;
select set_config('request.jwt.claim.sub', '14214214-0000-0000-0000-000000000010', true);
do $$
begin
    if exists (select 1 from terms_acceptances) then
        raise exception 'FAIL: a stranger reads acceptances';
    end if;
    raise notice 'PASS: a stranger reads none';
end $$;
rollback;

begin;
set local role anon;
do $$
declare v_state text; f text;
begin
    begin
        perform 1 from terms_acceptances limit 1;
        raise exception 'FAIL: anon read terms_acceptances';
    exception when insufficient_privilege then null;
    end;
    foreach f in array array['select my_terms_state()', 'select accept_terms(''terms'', 2)',
                             'select platform_terms_board()',
                             'select platform_terms_of(''14214214-0000-0000-0000-000000000002'')',
                             'select platform_terms_bump(array[''terms''], ''x'')'] loop
        begin
            execute f;
            raise exception 'FAIL: anon ran %', f;
        exception when others then
            if sqlerrm like 'FAIL:%' then raise; end if;
            get stacked diagnostics v_state = returned_sqlstate;
            if v_state <> '42501' then
                raise exception 'FAIL: % failed inside (%) instead of at the door', f, v_state;
            end if;
        end;
    end loop;
    raise notice 'PASS: anon reads no acceptance and is refused at every door (42501)';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: an order needs the terms — shop, farm, association ---'
do $$
declare v text;
begin
    -- A new account that accepted nothing: refused in the three.
    delete from terms_acceptances where user_id = '14214214-0000-0000-0000-000000000010';
    foreach v in array array[
        pg_temp.order_as('14214214-0000-0000-0000-000000000010', 'maison-elegance-142', '142aaaaa-0000-0000-0000-000000000001'),
        pg_temp.order_as('14214214-0000-0000-0000-000000000010', 'ferme-horizon-142',   '142aaaaa-0000-0000-0000-000000000002'),
        pg_temp.order_as('14214214-0000-0000-0000-000000000010', 'fondation-espoir-142', '142aaaaa-0000-0000-0000-000000000003')] loop
        if v is distinct from 'Acceptez d''abord les Conditions d''utilisation de Mara pour commander (mettez l''application à jour si elle ne vous les montre pas).' then
            raise exception 'FAIL: an order without the terms: %', v;
        end if;
    end loop;
    if exists (select 1 from orders where customer_id = '14214214-0000-0000-0000-000000000010') then
        raise exception 'FAIL: a refused order was kept';
    end if;
    -- The privacy policy alone is not the terms.
    perform pg_temp.as_('14214214-0000-0000-0000-000000000010');
    perform accept_terms('privacy', 2);
    if pg_temp.order_as('14214214-0000-0000-0000-000000000010', 'maison-elegance-142', '142aaaaa-0000-0000-0000-000000000001') = 'ordered' then
        raise exception 'FAIL: the privacy policy let an order through';
    end if;
    perform pg_temp.as_('14214214-0000-0000-0000-000000000010');
    perform accept_terms('terms', 2);
    foreach v in array array[
        pg_temp.order_as('14214214-0000-0000-0000-000000000010', 'maison-elegance-142', '142aaaaa-0000-0000-0000-000000000001'),
        pg_temp.order_as('14214214-0000-0000-0000-000000000010', 'ferme-horizon-142',   '142aaaaa-0000-0000-0000-000000000002'),
        pg_temp.order_as('14214214-0000-0000-0000-000000000010', 'fondation-espoir-142', '142aaaaa-0000-0000-0000-000000000003')] loop
        if v is distinct from 'ordered' then
            raise exception 'FAIL: accepted, the order is still refused: %', v;
        end if;
    end loop;
    -- The one who accepted in TEST 2 orders too.
    if pg_temp.order_as('14214214-0000-0000-0000-000000000002', 'maison-elegance-142', '142aaaaa-0000-0000-0000-000000000001') <> 'ordered' then
        raise exception 'FAIL: the new account that accepted cannot order';
    end if;
    raise notice 'PASS: no terms, no order (shop, farm, association), nothing kept; the privacy policy alone is not enough; accepted, the three orders go through';
end $$;

\echo ''
\echo '--- TEST 5: a business needs the seller''s commitments — create_my_business (shop, farm, association) and create_org ---'
do $$
declare v text;
begin
    -- Its terms accepted, not the seller's.
    perform pg_temp.as_('14214214-0000-0000-0000-000000000007');
    perform accept_terms('terms', 2);
    perform accept_terms('privacy', 2);
    foreach v in array array[
        pg_temp.create_as('14214214-0000-0000-0000-000000000007', 'retail', 'boutique-neuve-142'),
        pg_temp.create_as('14214214-0000-0000-0000-000000000007', 'farm', 'ferme-neuve-142'),
        pg_temp.create_as('14214214-0000-0000-0000-000000000007', 'association', 'tontine-neuve-142')] loop
        if v is distinct from 'Acceptez d''abord les engagements du vendeur pour créer une activité (mettez l''application à jour si elle ne vous les montre pas).' then
            raise exception 'FAIL: a creation without the seller''s commitments: %', v;
        end if;
    end loop;
    if exists (select 1 from orgs where slug in ('boutique-neuve-142', 'ferme-neuve-142', 'tontine-neuve-142'))
       or exists (select 1 from platform_actions where actor = '14214214-0000-0000-0000-000000000007') then
        raise exception 'FAIL: a refused creation left a business or a journal line';
    end if;
    perform pg_temp.as_('14214214-0000-0000-0000-000000000007');
    perform accept_terms('seller', 1);
    foreach v in array array[
        pg_temp.create_as('14214214-0000-0000-0000-000000000007', 'retail', 'boutique-neuve-142'),
        pg_temp.create_as('14214214-0000-0000-0000-000000000007', 'farm', 'ferme-neuve-142'),
        pg_temp.create_as('14214214-0000-0000-0000-000000000007', 'association', 'tontine-neuve-142')] loop
        if v is distinct from 'created' then
            raise exception 'FAIL: accepted, the creation is still refused: %', v;
        end if;
    end loop;
    -- The platform's « Nouvelle entreprise » (create_org): its admin is the owner.
    perform pg_temp.as_('14214214-0000-0000-0000-000000000001');
    if pg_temp.refusal('select create_org(''Maison Test 142'', ''maison-test-142'', ''retail'', ''XOF'')')
       is distinct from 'Acceptez d''abord les engagements du vendeur pour créer une activité (mettez l''application à jour si elle ne vous les montre pas).' then
        raise exception 'FAIL: create_org without the seller''s commitments';
    end if;
    perform accept_terms('seller', 1);
    v := pg_temp.refusal('select create_org(''Maison Test 142'', ''maison-test-142'', ''retail'', ''XOF'')');
    if v is not null or not exists (select 1 from orgs where slug = 'maison-test-142') then
        raise exception 'FAIL: create_org refused after the seller''s commitments: %', v;
    end if;
    -- create_org keeps its door: nobody but the platform.
    perform pg_temp.as_('14214214-0000-0000-0000-000000000007');
    if pg_temp.refusal('select create_org(''Hors Porte 142'', ''hors-porte-142'', ''farm'', ''XOF'')')
       is distinct from 'Only a platform admin can create a new business' then
        raise exception 'FAIL: create_org opened to a person';
    end if;
    raise notice 'PASS: no seller''s commitments, no business (shop, farm, association; create_org too), nothing left behind; accepted, each is created; create_org stays the platform''s';
end $$;

\echo ''
\echo '--- TEST 6: a courier''s application needs the charter — the charter step is the acceptance ---'
do $$
declare v jsonb;
begin
    perform pg_temp.as_('14214214-0000-0000-0000-000000000008');
    perform courier_application_open();
    -- Everything but the charter, written as the steps would; the photos
    -- as the uploads Worker does them (the slot, then done).
    update courier_applications
       set city = 'Ouagadougou', zones = array['Gounghin'], days = array['lun'],
           hours_from = '08:00', hours_to = '12:00', vehicle = 'velo', id_kind = 'passeport',
           phone = '+22614200008'
     where user_id = '14214214-0000-0000-0000-000000000008';
    perform courier_upload_done(courier_upload_slot('selfie', 'jpg'));
    perform courier_upload_done(courier_upload_slot('id_front', 'jpg'));
    perform courier_upload_done(courier_upload_slot('id_back', 'jpg'));
    -- 112's own refusal first (the charter not ticked).
    if pg_temp.refusal('select courier_application_send()') is distinct from 'Acceptez la charte du livreur' then
        raise exception 'FAIL: before the charter: %', pg_temp.refusal('select courier_application_send()');
    end if;
    -- An older charter version is not the current one.
    if pg_temp.refusal($q$select courier_application_save('charter', '{"charter_version": 1}')$q$) is distinct from 'Acceptez la charte du livreur' then
        raise exception 'FAIL: charter version 1 taken';
    end if;
    -- Ticked as the app does (the server's version): accepted, written.
    v := courier_application_save('charter', jsonb_build_object('charter_version', (courier_rules() ->> 'charter_version')::int));
    if not exists (select 1 from terms_acceptances where user_id = '14214214-0000-0000-0000-000000000008'
                    and document = 'courier' and version = 2) then
        raise exception 'FAIL: the charter ticked is not the courier''s acceptance';
    end if;
    -- Now the acceptance itself taken away (a direct write, as only a bug
    -- could): the send is refused by 142.
    delete from terms_acceptances where user_id = '14214214-0000-0000-0000-000000000008';
    if pg_temp.refusal('select courier_application_send()') is distinct from
       'Acceptez d''abord la charte du livreur pour envoyer votre demande (mettez l''application à jour si elle ne vous la montre pas).' then
        raise exception 'FAIL: sent without the courier''s acceptance: %', pg_temp.refusal('select courier_application_send()');
    end if;
    if (select status from courier_applications where user_id = '14214214-0000-0000-0000-000000000008') = 'pending' then
        raise exception 'FAIL: a refused application is pending';
    end if;
    perform accept_terms('courier', 2);
    v := courier_application_send();
    if v ->> 'status' <> 'pending' then
        raise exception 'FAIL: accepted, the application is not sent: %', v;
    end if;
    raise notice 'PASS: the charter''s version 2 ticked is the courier''s acceptance; without it the application is refused; with it, sent';
end $$;

\echo ''
\echo '--- TEST 6b: a dossier sent back with an older charter accepts the new one and is sent again ---'
-- The platform asks a new selfie of the application TEST 6 sent; then, as
-- for a dossier from before 142, its charter is 112's version 1.
do $$
begin
    perform pg_temp.as_('14214214-0000-0000-0000-000000000001');
    perform platform_decide_courier_application('14214214-0000-0000-0000-000000000008', 'new_photo', 'selfie');
    perform pg_temp.as_(null);
    update courier_applications set charter_version = 1
     where user_id = '14214214-0000-0000-0000-000000000008';
    delete from terms_acceptances where user_id = '14214214-0000-0000-0000-000000000008' and document = 'courier';
end $$;
do $$
declare v jsonb;
begin
    perform pg_temp.as_('14214214-0000-0000-0000-000000000008');
    v := my_courier_application();
    if v ->> 'status' <> 'refused' or not (v -> 'open_steps') ? 'charter' or not (v -> 'open_steps') ? 'selfie' then
        raise exception 'FAIL: a dossier sent back with charter 1 cannot reach the charter step: %', v -> 'open_steps';
    end if;
    perform courier_upload_done(courier_upload_slot('selfie', 'jpg'));
    if pg_temp.refusal('select courier_application_send()') is distinct from 'Acceptez la charte du livreur' then
        raise exception 'FAIL: sent again with charter 1: %', pg_temp.refusal('select courier_application_send()');
    end if;
    perform courier_application_save('charter', jsonb_build_object('charter_version', (courier_rules() ->> 'charter_version')::int));
    v := courier_application_send();
    if v ->> 'status' <> 'pending'
       or not exists (select 1 from terms_acceptances where user_id = '14214214-0000-0000-0000-000000000008'
                       and document = 'courier' and version = 2) then
        raise exception 'FAIL: the new charter accepted, the dossier is not sent again: %', v;
    end if;
    raise notice 'PASS: a dossier sent back with the old charter opens its charter step, takes version 2 (the acceptance) and is sent again';
end $$;
-- With the current charter, a dossier sent back does not reopen it.
do $$
begin
    perform pg_temp.as_('14214214-0000-0000-0000-000000000001');
    perform platform_decide_courier_application('14214214-0000-0000-0000-000000000008', 'new_photo', 'id');
end $$;
do $$
begin
    if 'charter' = any(courier_open_steps('14214214-0000-0000-0000-000000000008'))
       or not ('id' = any(courier_open_steps('14214214-0000-0000-0000-000000000008'))) then
        raise exception 'FAIL: the steps of a dossier sent back with the current charter: %',
            courier_open_steps('14214214-0000-0000-0000-000000000008');
    end if;
    raise notice 'PASS: with the current charter, only the photo asked is reopened';
end $$;

\echo ''
\echo '--- TEST 6c: the delivery code stays the customer''s — the courier who carries the order cannot read it ---'
do $$
begin
    perform pg_temp.as_(null);
    update orgs set plan = 'pro' where id = '14200000-0000-0000-0000-000000000001';
    insert into orders (id, org_id, customer_id, customer_name, phone, fulfilment, status, total, address, courier_id)
    values ('142bbbbb-0000-0000-0000-000000000001', '14200000-0000-0000-0000-000000000001',
            '14214214-0000-0000-0000-000000000002', 'Client Nouveau 142', '+22614200002', 'delivery', 'ready',
            5000, 'Gounghin, près du marché', '14214214-0000-0000-0000-000000000009');
    if (select handover_code from orders where id = '142bbbbb-0000-0000-0000-000000000001') is null then
        raise exception 'FAIL: the delivery has no code';
    end if;
end $$;
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '14214214-0000-0000-0000-000000000009', true);
do $$
begin
    if exists (select 1 from orders where id = '142bbbbb-0000-0000-0000-000000000001')
       or exists (select 1 from order_lines where order_id = '142bbbbb-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the courier reads the order''s row, its code with it';
    end if;
    -- Their own door still gives them what they need to deliver.
    if not exists (select 1 from courier_deliveries() d
                    where d.order_id = '142bbbbb-0000-0000-0000-000000000001'
                      and d.customer_name = 'Client Nouveau 142' and d.phone = '+22614200002') then
        raise exception 'FAIL: the courier lost the delivery from their own list';
    end if;
    raise notice 'PASS: the courier reads neither the order''s row nor its code; courier_deliveries still lists it, name and number';
end $$;
select set_config('request.jwt.claim.sub', '14214214-0000-0000-0000-000000000002', true);
do $$
begin
    if (select handover_code from orders where id = '142bbbbb-0000-0000-0000-000000000001') is null then
        raise exception 'FAIL: the customer lost their own order';
    end if;
    raise notice 'PASS: the customer reads their order and its code';
end $$;
select set_config('request.jwt.claim.sub', '14214214-0000-0000-0000-000000000004', true);
do $$
begin
    if not exists (select 1 from orders where id = '142bbbbb-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the shop lost its order';
    end if;
    raise notice 'PASS: the shop reads its order';
end $$;
rollback;
delete from orders where id = '142bbbbb-0000-0000-0000-000000000001';
update orgs set plan = 'free' where id = '14200000-0000-0000-0000-000000000001';

\echo ''
\echo '--- TEST 7: existing people, businesses and couriers keep working; internal paths are not asked ---'
do $$
declare v text;
begin
    -- An account from before 142, nothing accepted, in the grace: through.
    if pg_temp.order_as('14214214-0000-0000-0000-000000000003', 'ferme-horizon-142', '142aaaaa-0000-0000-0000-000000000002') <> 'ordered' then
        raise exception 'FAIL: an existing account was refused an order in the grace';
    end if;
    if pg_temp.create_as('14214214-0000-0000-0000-000000000003', 'farm', 'ferme-ancienne-142') <> 'created' then
        raise exception 'FAIL: an existing account was refused a creation in the grace';
    end if;
    -- The app still asks them (the gate), whatever the grace.
    perform pg_temp.as_('14214214-0000-0000-0000-000000000003');
    if my_terms_state() -> 'gate' <> '["terms", "privacy"]'::jsonb then
        raise exception 'FAIL: the grace hid the gate: %', my_terms_state();
    end if;
    -- Existing businesses: their owner records and sells as before (an
    -- order to them was taken in TEST 4); the approved courier's board
    -- answers.
    perform pg_temp.as_('14214214-0000-0000-0000-000000000004');
    perform my_orgs();
    perform pg_temp.as_('14214214-0000-0000-0000-000000000009');
    perform courier_status();
    perform courier_rules();
    -- Internal paths: no caller (a seed, a SQL run) is never asked.
    perform pg_temp.as_(null);
    perform org_create_core('14214214-0000-0000-0000-000000000010', 'Vitrine Exemple 142', 'vitrine-exemple-142', 'retail', 'XOF');
    -- The grace over: the existing account is asked by the server too.
    update platform_settings
       set value = jsonb_set(jsonb_set(value, '{terms,grace_until}', to_jsonb(now() - interval '1 second')),
                             '{seller,grace_until}', to_jsonb(now() - interval '1 second'))
     where key = 'terms_versions';
    if pg_temp.order_as('14214214-0000-0000-0000-000000000003', 'ferme-horizon-142', '142aaaaa-0000-0000-0000-000000000002') = 'ordered' then
        raise exception 'FAIL: after the grace, an existing account ordered without the terms';
    end if;
    if pg_temp.create_as('14214214-0000-0000-0000-000000000003', 'retail', 'boutique-ancienne-142') = 'created' then
        raise exception 'FAIL: after the grace, an existing account created without the seller''s commitments';
    end if;
    -- Those who accepted are not touched by the grace's end.
    if pg_temp.order_as('14214214-0000-0000-0000-000000000002', 'fondation-espoir-142', '142aaaaa-0000-0000-0000-000000000003') <> 'ordered' then
        raise exception 'FAIL: the grace''s end stopped someone who accepted';
    end if;
    raise notice 'PASS: in the grace an existing account orders and creates (and is still asked by the app); owners and approved couriers keep working; no caller, no question; after the grace, refused';
end $$;

\echo ''
\echo '--- TEST 8: a new version — the platform''s, journaled, everyone asked again ---'
do $$
declare v jsonb; v_board jsonb;
begin
    perform pg_temp.as_('14214214-0000-0000-0000-000000000002');
    if pg_temp.refusal('select platform_terms_bump(array[''terms''], ''Nouveau'')') is distinct from 'Réservé à la plateforme'
       or pg_temp.refusal('select platform_terms_board()') is distinct from 'Réservé à la plateforme'
       or pg_temp.refusal('select platform_terms_of(''14214214-0000-0000-0000-000000000002'')') is distinct from 'Réservé à la plateforme' then
        raise exception 'FAIL: a person reached the platform''s doors';
    end if;
    perform pg_temp.as_('14214214-0000-0000-0000-000000000001');
    v_board := platform_terms_board();
    if (v_board -> 'documents' -> 'terms' ->> 'version')::int <> 2
       or (v_board -> 'documents' -> 'terms' ->> 'accepted')::int < 3 then
        raise exception 'FAIL: the board reads %', v_board;
    end if;
    if pg_temp.refusal('select platform_terms_bump(array[]::text[], ''x'')') is distinct from 'Choisissez au moins un document.'
       or pg_temp.refusal('select platform_terms_bump(array[''cgv''], ''x'')') is distinct from 'Document inconnu.'
       or pg_temp.refusal('select platform_terms_bump(array[''terms''], ''  '')') is distinct from 'Dites en une phrase ce qui a changé.'
       or pg_temp.refusal('select platform_terms_bump(array[''terms''], ''x'', null, 91)') is distinct from 'Un délai de 0 à 90 jours.' then
        raise exception 'FAIL: a bad bump was taken';
    end if;
    v_board := platform_terms_bump(array['terms', 'privacy'], 'Les remboursements des mises en avant.',
                                   'Refunds of promotions.', 0);
    if (v_board -> 'documents' -> 'terms' ->> 'version')::int <> 3
       or (v_board -> 'documents' -> 'privacy' ->> 'version')::int <> 3
       or (v_board -> 'documents' -> 'seller' ->> 'version')::int <> 1
       or (v_board -> 'documents' -> 'terms' ->> 'accepted')::int <> 0
       or v_board ->> 'changes' <> 'Les remboursements des mises en avant.'
       or v_board ->> 'changes_en' <> 'Refunds of promotions.' then
        raise exception 'FAIL: bumped, the board reads %', v_board;
    end if;
    if not exists (select 1 from platform_actions where kind = 'terms_version'
                    and actor = '14214214-0000-0000-0000-000000000001'
                    and summary = 'Nouvelle version : terms, privacy — Les remboursements des mises en avant.') then
        raise exception 'FAIL: the bump is not journaled';
    end if;
    -- The one who accepted 2: asked again, with what changed.
    perform pg_temp.as_('14214214-0000-0000-0000-000000000002');
    v := my_terms_state();
    if v -> 'gate' <> '["terms", "privacy"]'::jsonb or not (v ->> 'changed')::boolean
       or v ->> 'changes' <> 'Les remboursements des mises en avant.'
       or (v -> 'documents' -> 'terms' ->> 'accepted')::int <> 2 then
        raise exception 'FAIL: after a bump, the state reads %', v;
    end if;
    -- No grace (0 days): the old acceptance is no longer enough.
    if pg_temp.order_as('14214214-0000-0000-0000-000000000002', 'maison-elegance-142', '142aaaaa-0000-0000-0000-000000000001') = 'ordered' then
        raise exception 'FAIL: version 2 still orders after version 3 with no grace';
    end if;
    perform pg_temp.as_('14214214-0000-0000-0000-000000000002');
    perform accept_terms('terms', 3, 'web');
    perform accept_terms('privacy', 3, 'web');
    if pg_temp.order_as('14214214-0000-0000-0000-000000000002', 'maison-elegance-142', '142aaaaa-0000-0000-0000-000000000001') <> 'ordered' then
        raise exception 'FAIL: version 3 accepted, still refused';
    end if;
    -- The fiche: newest first, the current ones marked.
    perform pg_temp.as_('14214214-0000-0000-0000-000000000001');
    v := platform_terms_of('14214214-0000-0000-0000-000000000002');
    if jsonb_array_length(v) <> 4
       or v -> 0 ->> 'platform' <> 'web' or not (v -> 0 ->> 'current')::boolean
       or (select count(*) from jsonb_array_elements(v) e where not (e ->> 'current')::boolean) <> 2 then
        raise exception 'FAIL: the fiche reads %', v;
    end if;
    raise notice 'PASS: the platform alone bumps (journaled, checked), everyone is asked again with what changed, the old acceptance is not enough after the grace; the board counts, the fiche lists';
end $$;

\echo ''
\echo '--- TEST 9: the doors ---'
do $$
declare
    f text;
    v_app text[] := array['my_terms_state()', 'accept_terms(text, integer, text, text)',
                          'platform_terms_board()', 'platform_terms_of(uuid)',
                          'platform_terms_bump(text[], text, text, integer)'];
    v_internal text[] := array['terms_setting()', 'terms_version(text)',
                               'terms_accepted_version(uuid, text)', 'terms_ok(uuid, text)',
                               'trg_orders_terms()', 'trg_courier_terms()',
                               'org_create_core(uuid, text, text, text, text)'];
begin
    foreach f in array v_app || v_internal loop
        if not (select prosecdef from pg_proc where oid = f::regprocedure) then
            raise exception 'FAIL: % is not a definer', f;
        end if;
        if not exists (select 1 from pg_proc p, unnest(p.proconfig) c
                        where p.oid = f::regprocedure and c like 'search_path=%') then
            raise exception 'FAIL: % has no pinned search_path', f;
        end if;
        if has_function_privilege('anon', f, 'execute') or has_function_privilege('public', f, 'execute') then
            raise exception 'FAIL: % is open to anon or PUBLIC', f;
        end if;
    end loop;
    foreach f in array v_app loop
        if not has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: % is closed to authenticated', f;
        end if;
    end loop;
    foreach f in array v_internal loop
        if has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: % is open to authenticated', f;
        end if;
    end loop;
    if has_function_privilege('anon', 'courier_rules()', 'execute')
       or has_function_privilege('authenticated', 'courier_rules()', 'execute') then
        raise exception 'FAIL: courier_rules opened (122 keeps it internal)';
    end if;
    raise notice 'PASS: definers with a pinned path, closed to anon and PUBLIC; the app''s open to authenticated, the internal ones closed';
end $$;

\echo ''
\echo '=== test_batch142.sql: all checks passed ==='
