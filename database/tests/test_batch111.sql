-- ============================================================
-- test_batch111.sql — a person creates their business, at once (111).
--
-- The claims, for a shop, a farm and an association (a legacy church is
-- created as an association) alike:
--   P1. Installed, nothing an existing business shows moves: the switch
--       create_phone_verified is off; create_org makes, for a shop and an
--       association, exactly what 035's create_org made (035's put back in
--       the same transaction and compared, row for row) — and for a farm
--       the farm chart a farm approved from a request always had, where
--       035 gave it the generic one (the fix).
--   2. create_my_business makes the business at once, by create_org's own
--      path: the person its owner, the kind's chart, its town, area, phone
--      and sentence where the business keeps them (an association's kind
--      too), the walkthrough still ahead (setup not done), the creation
--      kept for Mara and written in the platform's journal.
--   3. Every answer is checked on the server: the kind, the name, the
--      address (its problem, taken — and business_address_check says so
--      with a free one), the line of trade of that kind, the town, the
--      phone, the currency.
--   4. One free business per person: a second is refused without Mara Pro
--      (099's rule) and made with it; my_business_start says so first.
--   5. The platform's switch: on, no proved WhatsApp number, no business;
--      a proved one is used as the business's phone when none is typed.
--      Réglages lists it; only the platform turns it, journaled, undone.
--   6. The creation page (107's form): only the kinds it offers, its
--      questions answered as 107 checks them, the answers kept as asked.
--   7. The old path still works for an older app (apply_for_org, approve);
--      a request still waiting is closed by a direct creation, with the
--      business it became.
--   8. A new vitrine reaches the street only with its minimum (unchanged).
--   9. À faire: « Nouvelles activités (7 j) » and its list, the vitrines
--      d'exemple and the archived aside; 'applications' kept for an older
--      app; 'reports_open' 113's count, 0 without its table.
--  10. « Activités créées »: the created businesses with their answers and
--      the requests of before, approved or refused — the platform's alone.
--  P3. The doors are a signed-in person's or the platform's; the internals
--      nobody's; the street (anon) reaches none; the history table is read
--      through its function only.
-- ============================================================
\set ON_ERROR_STOP on

\set mara     '''11111111-0000-0000-0000-000000000001'''
\set awa      '''11111111-0000-0000-0000-000000000002'''
\set ignace   '''11111111-0000-0000-0000-000000000003'''
\set treso    '''11111111-0000-0000-0000-000000000004'''
\set pasteur  '''11111111-0000-0000-0000-000000000005'''
\set freeo    '''11111111-0000-0000-0000-000000000006'''
\set proo     '''11111111-0000-0000-0000-000000000007'''
\set proved   '''11111111-0000-0000-0000-000000000008'''
\set nophone  '''11111111-0000-0000-0000-000000000009'''
\set oldapp   '''11111111-0000-0000-0000-000000000010'''
\set oldapp2  '''11111111-0000-0000-0000-000000000011'''
\set formp    '''11111111-0000-0000-0000-000000000012'''
\set freeshop '''11100000-0000-0000-0000-000000000001'''
\set proshop  '''11100000-0000-0000-0000-000000000002'''
\set show1    '''11100000-0000-0000-0000-000000000003'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
-- Earlier suites re-apply older migrations over 111's functions (035's
-- create_org, 105's platform_todo) and hand the app's roles every
-- function: 111 again, so what follows tests its own definitions and
-- its own doors.
\i database/migrations/111_create_my_business.sql

update platform_settings set value = '8' where key = 'vitrine_min_items';
update platform_settings set value = 'false' where key = 'create_phone_verified';
delete from platform_settings where key = 'application_form';

insert into auth.users (id, phone, email, raw_user_meta_data, phone_confirmed_at) values
    (:mara,    '+22611110001', 'mara111@example.com', '{"full_name": "Mara Cent-Onze"}', null),
    (:awa,     '+22611110002', null, '{"full_name": "Awa Boutique111"}',     null),
    (:ignace,  '+22611110003', null, '{"full_name": "Ignace Ferme111"}',     null),
    (:treso,   '+22611110004', null, '{"full_name": "Trésorière111"}',       null),
    (:pasteur, '+22611110005', null, '{"full_name": "Pasteur111"}',          null),
    (:freeo,   '+22611110006', null, '{"full_name": "Bintou Gratuite111"}',  null),
    (:proo,    '+22611110007', null, '{"full_name": "Issa Pro111"}',         null),
    -- A number proved on WhatsApp (109's way): phone_confirmed_at set.
    (:proved,  '22611110008',  null, '{"full_name": "Prouvée111"}',          now()),
    -- Signed in with Google: an e-mail, no number.
    (:nophone, null, 'google111@example.com', '{"full_name": "Google111"}',  null),
    (:oldapp,  '+22611110010', null, '{"full_name": "Ancienne Appli111"}',   null),
    (:oldapp2, '+22611110011', null, '{"full_name": "Ancienne Deux111"}',    null),
    (:formp,   '+22611110012', null, '{"full_name": "Formulaire111"}',       null);
update profiles set is_platform_admin = true where id = :mara;
update profiles set first_name = 'Awa', last_name = 'Ouédraogo' where id = :awa;

insert into orgs (id, name, slug, profile, default_currency, plan, plan_until, showcase, created_at) values
    (:freeshop, 'Gratuite B111', 'gratuite-b111', 'retail', 'XOF', 'free', null,         false, now() - interval '30 days'),
    (:proshop,  'Pro B111',      'pro-b111',      'retail', 'XOF', 'pro',  '2099-01-01', false, now() - interval '30 days'),
    (:show1,    'Exemple B111',  'exemple-b111',  'retail', 'XOF', 'pro',  '2099-01-01', true,  now());
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:freeshop, :freeo, 'owner', 'org', :freeshop, 'full'),
    (:proshop,  :proo,  'owner', 'org', :proshop,  'full');

-- Signed in as somebody, or as nobody.
create function pg_temp.as_user(p uuid) returns void
language sql as $$ select set_config('request.jwt.claim.sub', coalesce(p::text, ''), true) $$;

-- What a creation refuses, in its words (null when it went through).
create function pg_temp.refusal(p_user uuid, p_profile text, p_name text, p_slug text,
                                p_activity text, p_city text, p_phone text,
                                p_currency text default 'XOF', p_answers jsonb default null,
                                p_about text default null)
returns text
language plpgsql as $$
declare msg text;
begin
    perform pg_temp.as_user(p_user);
    begin
        perform create_my_business(p_profile, p_name, p_slug, p_activity, p_about,
                                   p_city, null, p_phone, p_currency, p_answers);
        raise exception 'went through';
    exception when others then
        msg := sqlerrm;
    end;
    perform pg_temp.as_user(null);
    return nullif(msg, 'went through');
end;
$$;

-- A business's starting rows, without ids and times: its kind, its
-- currency, its owner and the chart.
create function pg_temp.made(p_org uuid) returns jsonb
language sql as $$
    select jsonb_build_object(
        'org', (select jsonb_build_object('name', name, 'slug', slug, 'profile', profile,
                                          'currency', default_currency, 'plan', plan,
                                          'storefront', storefront_enabled,
                                          'setup_done', setup_done_at is not null)
                  from orgs where id = p_org),
        'members', (select jsonb_agg(jsonb_build_object('user', user_id, 'role', role,
                                                        'scope', scope_kind,
                                                        'scope_is_org', scope_id = p_org)
                                     order by user_id)
                      from memberships where org_id = p_org),
        'accounts', (select jsonb_agg(jsonb_build_array(code, name, type) order by code)
                       from accounts where org_id = p_org));
$$;

\echo ''
\echo '--- TEST P1: installed, the switch is off and create_org makes what 035 made (the farm its own chart) ---'
do $$
begin
    if (select value from platform_settings where key = 'create_phone_verified') is distinct from 'false'::jsonb then
        raise exception 'FAIL: create_phone_verified is not off as installed';
    end if;
    if create_phone_required() then
        raise exception 'FAIL: a proved number is asked as installed';
    end if;
    raise notice 'PASS: installed, create_phone_verified is off — creating asks no proved number';
end $$;

-- 111's create_org, for each kind, made and rolled back; then 035's put
-- back in the same way and the same businesses made again — the answers
-- kept in variables across each rollback.
do $$
declare
    v_111  jsonb;
    v_035  jsonb;
    k      text;
    v_farm jsonb;
begin
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000001');
    begin
        select jsonb_object_agg(x, pg_temp.made(create_org('P1 ' || x, 'p1-b111-' || x, x, 'XOF')))
          into v_111
          from unnest(array['retail', 'association', 'church', 'generic', 'farm']) x;
        raise exception 'roll back';
    exception when others then
        if sqlerrm <> 'roll back' then raise; end if;
    end;
    begin
        execute $f$
        create or replace function create_org(
            p_name     text,
            p_slug     text,
            p_profile  text default 'generic',
            p_currency text default 'XOF'
        )
        returns uuid
        language plpgsql
        security definer
        set search_path = public, auth
        as $b$
        declare
            v_org_id uuid;
        begin
            if not exists(select 1 from profiles where id = auth.uid() and is_platform_admin) then
                raise exception 'Only a platform admin can create a new business';
            end if;

            insert into orgs (name, slug, profile, default_currency)
            values (p_name, p_slug, p_profile, p_currency)
            returning id into v_org_id;

            insert into memberships (org_id, user_id, role, scope_kind, scope_id)
            values (v_org_id, auth.uid(), 'owner', 'org', v_org_id);

            if p_profile in ('church', 'association') then
                perform seed_church_accounts(v_org_id);
            elsif p_profile = 'retail' then
                perform seed_retail_accounts(v_org_id);
            else
                insert into accounts (org_id, code, name, type) values
                    (v_org_id, '1000', 'Cash on Hand',        'asset'),
                    (v_org_id, '1010', 'Bank Account',        'asset'),
                    (v_org_id, '1020', 'Mobile Money',        'asset'),
                    (v_org_id, '4000', 'Sales',                'income'),
                    (v_org_id, '5000', 'Purchases',            'expense'),
                    (v_org_id, '5010', 'Operating Expenses',   'expense')
                on conflict (org_id, code) do nothing;
            end if;

            return v_org_id;
        end;
        $b$
        $f$;
        select jsonb_object_agg(x, pg_temp.made(create_org('P1 ' || x, 'p1-b111-' || x, x, 'XOF')))
          into v_035
          from unnest(array['retail', 'association', 'church', 'generic', 'farm']) x;
        raise exception 'roll back';
    exception when others then
        if sqlerrm <> 'roll back' then raise; end if;
    end;
    perform pg_temp.as_user(null);
    -- Both made what they made, and 111's create_org is back in place.
    if v_111 is null or v_035 is null
       or (select prosrc from pg_proc where proname = 'create_org') not like '%org_create_core%' then
        raise exception 'FAIL: the comparison did not run as written';
    end if;
    foreach k in array array['retail', 'association', 'church', 'generic'] loop
        if v_111 -> k is distinct from v_035 -> k then
            raise exception 'FAIL: create_org made a % differently from 035: % vs %', k, v_111 -> k, v_035 -> k;
        end if;
    end loop;
    -- The farm: the same business and owner; the farm chart, not 035's generic one.
    if (v_111 -> 'farm') - 'accounts' is distinct from (v_035 -> 'farm') - 'accounts' then
        raise exception 'FAIL: a farm is made differently beyond its chart';
    end if;
    v_farm := v_111 -> 'farm' -> 'accounts';
    if not v_farm @> '[["4100", "Ventes d''œufs", "income"], ["5100", "Aliment", "expense"]]'::jsonb
       or v_farm @> '[["4000", "Sales", "income"]]'::jsonb then
        raise exception 'FAIL: a farm made by create_org lacks the farm chart: %', v_farm;
    end if;
    if not (v_035 -> 'farm' -> 'accounts') @> '[["4000", "Sales", "income"]]'::jsonb then
        raise exception 'FAIL: the comparison lost 035''s generic farm chart';
    end if;
    raise notice 'PASS: create_org makes a shop, an association, a church and a generic business row for row as 035 did (business, owner, chart)';
    raise notice 'PASS: create_org now gives a farm the farm chart (019) — 035 gave it the generic one';
end $$;
select pg_temp.as_user(null);

\echo ''
\echo '--- TEST 2: a shop, a farm and an association created at once, by create_org''s path ---'
do $$
declare
    v_shop  uuid;
    v_farm  uuid;
    v_asso  uuid;
    v_church uuid;
    m       jsonb;
    o       orgs%rowtype;
    c       business_creations%rowtype;
    a       platform_actions%rowtype;
    f       jsonb;
begin
    -- Awa's shop.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000002');
    if (my_business_start() ->> 'locked')::boolean then
        raise exception 'FAIL: a first business is locked';
    end if;
    v_shop := create_my_business('retail', '  Chez Awa 111 ', 'chez-awa-b111', 'Alimentation',
                                 'Riz, huile et savon au détail', 'Ouagadougou', 'Dapoya',
                                 '+226 70 11 11 02', 'XOF', null);
    m := pg_temp.made(v_shop);
    if m -> 'org' is distinct from '{"name": "Chez Awa 111", "slug": "chez-awa-b111", "profile": "retail", "currency": "XOF", "plan": "free", "storefront": false, "setup_done": false}'::jsonb then
        raise exception 'FAIL: the shop is not as created: %', m -> 'org';
    end if;
    if m -> 'members' is distinct from '[{"user": "11111111-0000-0000-0000-000000000002", "role": "owner", "scope": "org", "scope_is_org": true}]'::jsonb then
        raise exception 'FAIL: the shop''s owner is not Awa alone: %', m -> 'members';
    end if;
    if (select jsonb_agg(jsonb_build_array(code, name, type) order by code) from accounts where org_id = v_shop)
       is distinct from m -> 'accounts'
       or not (m -> 'accounts') @> '[["1000", "Caisse", "asset"], ["5000", "Achats de marchandises", "expense"]]'::jsonb then
        raise exception 'FAIL: the shop lacks the retail chart: %', m -> 'accounts';
    end if;
    select * into o from orgs where id = v_shop;
    if o.city is distinct from 'Ouagadougou' or o.address is distinct from 'Dapoya' or o.phone is distinct from '+22670111102'
       or o.storefront_blurb is distinct from 'Riz, huile et savon au détail' or o.association_kind is not null then
        raise exception 'FAIL: the shop''s place, phone or sentence are not where it keeps them: % % % %',
            o.city, o.address, o.phone, o.storefront_blurb;
    end if;
    -- Its walkthrough is still ahead: its owner reads « not set up ».
    f := feature_states(v_shop);
    if (f ->> 'setup_done')::boolean then
        raise exception 'FAIL: a new shop reads as set up — the walkthrough would be skipped';
    end if;
    select * into c from business_creations where org_id = v_shop;
    if not found or c.created_by is distinct from '11111111-0000-0000-0000-000000000002' or c.activity is distinct from 'alimentation'
       or c.city is distinct from 'Ouagadougou' or c.area is distinct from 'Dapoya' or c.contact_name is distinct from 'Awa Ouédraogo'
       or c.contact_phone is distinct from '+22611110002' or c.answers is not null then
        raise exception 'FAIL: the creation is not kept as made: %', to_jsonb(c);
    end if;
    select * into a from platform_actions where org_id = v_shop and kind = 'business_created';
    if not found or a.actor is distinct from '11111111-0000-0000-0000-000000000002'
       or a.summary is distinct from 'Activité créée : Chez Awa 111 (chez-awa-b111) — boutique, Ouagadougou'
       or a.undo_fn is not null or a.after ->> 'activity' is distinct from 'alimentation' then
        raise exception 'FAIL: the journal does not say the creation: % %', a.summary, a.after;
    end if;
    raise notice 'PASS: a shop created at once — Awa its only owner, the retail chart, Ouagadougou · Dapoya · +22670111102 and its sentence on the business, the walkthrough ahead, kept and journaled';

    -- Ignace's farm.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000003');
    v_farm := create_my_business('farm', 'Ferme Ignace 111', 'ferme-ignace-b111', 'volaille',
                                 null, 'Koudougou', null, '+22670111103', 'XOF', null);
    m := pg_temp.made(v_farm);
    if m -> 'org' ->> 'profile' is distinct from 'farm'
       or not (m -> 'accounts') @> '[["4100", "Ventes d''œufs", "income"], ["5100", "Aliment", "expense"]]'::jsonb
       or (m -> 'members' -> 0 ->> 'role') is distinct from 'owner' then
        raise exception 'FAIL: the farm is not made with its chart and its owner: %', m;
    end if;
    if (feature_states(v_farm) ->> 'setup_done')::boolean then
        raise exception 'FAIL: a new farm reads as set up';
    end if;
    raise notice 'PASS: a farm created at once — the farm chart (œufs, aliment), Ignace its owner, its walkthrough ahead';

    -- The treasurer's association: its kind (102) on the business.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000004');
    v_asso := create_my_business('association', 'Entraide 111', 'entraide-b111', 'tontine',
                                 'Une tontine de quartier', 'Bobo-Dioulasso', 'Accart-Ville',
                                 '+22670111104', 'XOF', null);
    select * into o from orgs where id = v_asso;
    m := pg_temp.made(v_asso);
    if o.profile is distinct from 'association' or o.association_kind is distinct from 'tontine'
       or o.storefront_blurb is distinct from 'Une tontine de quartier'
       or not (m -> 'accounts') @> '[["4000", "Tithes", "income"]]'::jsonb then
        raise exception 'FAIL: the association is not made as 102 keeps one: % % %',
            o.profile, o.association_kind, m -> 'accounts';
    end if;
    if (feature_states(v_asso) ->> 'setup_done')::boolean then
        raise exception 'FAIL: a new association reads as set up';
    end if;
    -- A legacy word: a church is created as an association.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000005');
    v_church := create_my_business('church', 'Chapelle 111', 'chapelle-b111', 'eglise',
                                   null, 'Ouagadougou', null, '+22670111105', 'XOF', null);
    if (select profile from orgs where id = v_church) is distinct from 'association'
       or (select association_kind from orgs where id = v_church) is distinct from 'eglise' then
        raise exception 'FAIL: a church was not created as an association';
    end if;
    perform pg_temp.as_user(null);
    raise notice 'PASS: an association created at once — its kind (tontine) and sentence as 102 keeps them, the association chart; a church is created as an association (eglise)';
end $$;

\echo ''
\echo '--- TEST 3: every answer checked on the server, in words a person can act on ---'
do $$
declare
    r text;
    v jsonb;
begin
    -- A signed-in person only.
    r := pg_temp.refusal(null, 'retail', 'Personne', 'personne-b111', 'autre', 'Ouaga', '+22670000000');
    if r is distinct from 'Connectez-vous pour créer votre activité.' then
        raise exception 'FAIL: a signed-out caller was not refused: %', r;
    end if;
    begin
        perform my_business_start();
        raise exception 'FAIL: my_business_start answered the street';
    exception when others then
        if sqlerrm not like 'Connectez-vous%' then raise; end if;
    end;
    begin
        perform business_address_check('chez-awa-b111');
        raise exception 'FAIL: business_address_check answered the street';
    exception when others then
        if sqlerrm not like 'Connectez-vous%' then raise; end if;
    end;
    -- The kind.
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000009', 'generic', 'Autre 111', 'autre-b111', 'autre', 'Ouaga', '+22670000000');
    if r is distinct from 'Choisissez boutique, ferme ou association.' then
        raise exception 'FAIL: a generic business was made: %', r;
    end if;
    -- The name.
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000009', 'retail', '   ', 'vide-b111', 'autre', 'Ouaga', '+22670000000');
    if r is distinct from 'Le nom de votre activité, s''il vous plaît.' then
        raise exception 'FAIL: an empty name: %', r;
    end if;
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000009', 'retail', repeat('a', 81), 'long-b111', 'autre', 'Ouaga', '+22670000000');
    if r is distinct from 'Un nom de 80 caractères au plus.' then
        raise exception 'FAIL: a name too long: %', r;
    end if;
    -- The address: its problem, and taken.
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000009', 'retail', 'Bad 111', 'Bad Slug!', 'autre', 'Ouaga', '+22670000000');
    if r is distinct from 'Lettres minuscules, chiffres et tirets seulement.' then
        raise exception 'FAIL: a bad address: %', r;
    end if;
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000009', 'retail', 'Chez Awa bis', 'chez-awa-b111', 'autre', 'Ouaga', '+22670000000');
    if r is distinct from 'Cette adresse est déjà prise : choisissez-en une autre.' then
        raise exception 'FAIL: a taken address: %', r;
    end if;
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000009');
    v := business_address_check('Chez-Awa-b111 ');
    if v is distinct from '{"slug": "chez-awa-b111", "problem": null, "taken": true, "suggestion": "chez-awa-b111-2"}'::jsonb then
        raise exception 'FAIL: a taken address is not said with a free one: %', v;
    end if;
    v := business_address_check('libre-b111');
    if v is distinct from '{"slug": "libre-b111", "problem": null, "taken": false, "suggestion": null}'::jsonb then
        raise exception 'FAIL: a free address is not said free: %', v;
    end if;
    v := business_address_check('ab');
    if v ->> 'problem' is distinct from 'Trop court : au moins 3 caractères.' or (v ->> 'taken')::boolean then
        raise exception 'FAIL: a short address is not said: %', v;
    end if;
    perform pg_temp.as_user(null);
    -- What the business does: required, and of its kind.
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000009', 'retail', 'Sans 111', 'sans-b111', null, 'Ouaga', '+22670000000');
    if r is distinct from 'Dites ce que fait votre activité.' then
        raise exception 'FAIL: no line of trade: %', r;
    end if;
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000009', 'retail', 'Poule 111', 'poule-b111', 'volaille', 'Ouaga', '+22670000000');
    if r is distinct from 'Choisissez ce que fait votre activité dans la liste.' then
        raise exception 'FAIL: a farm''s line of trade for a shop: %', r;
    end if;
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000009', 'farm', 'Tontine 111', 'tontine-b111', 'tontine', 'Ouaga', '+22670000000');
    if r is distinct from 'Choisissez ce que fait votre activité dans la liste.' then
        raise exception 'FAIL: an association''s kind for a farm: %', r;
    end if;
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000009', 'retail', 'Phrase 111', 'phrase-b111', 'autre', 'Ouaga', '+22670000000',
                         'XOF', null, repeat('x', 161));
    if r is distinct from 'Une phrase de 160 caractères au plus.' then
        raise exception 'FAIL: a sentence too long: %', r;
    end if;
    -- The town.
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000009', 'retail', 'Ville 111', 'ville-b111', 'autre', ' ', '+22670000000');
    if r is distinct from 'La ville, s''il vous plaît.' then
        raise exception 'FAIL: no town: %', r;
    end if;
    -- The phone: required (none proved here), and a number.
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000009', 'retail', 'Tel 111', 'tel-b111', 'autre', 'Ouaga', null);
    if r is distinct from 'Le numéro de votre activité, s''il vous plaît.' then
        raise exception 'FAIL: no phone: %', r;
    end if;
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000009', 'retail', 'Tel 111', 'tel-b111', 'autre', 'Ouaga', '70 11 22');
    if r is distinct from 'Ce numéro n''est pas valide : l''indicatif du pays, puis le numéro.' then
        raise exception 'FAIL: a phone without its country: %', r;
    end if;
    -- The currency.
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000009', 'retail', 'Monnaie 111', 'monnaie-b111', 'autre', 'Ouaga', '+22670000000', 'FRANCS');
    if r is distinct from 'Une monnaie s''écrit en trois lettres (XOF, GHS…).' then
        raise exception 'FAIL: a currency not of three letters: %', r;
    end if;
    if exists (select 1 from memberships where user_id = '11111111-0000-0000-0000-000000000009') then
        raise exception 'FAIL: a refused creation left a business behind';
    end if;
    raise notice 'PASS: refused, in French, with nothing written: signed out, a generic kind, no name or one too long, a bad or taken address, no line of trade or one of another kind, a sentence too long, no town, no phone or one without its country, a currency not of three letters';
    raise notice 'PASS: business_address_check says an address taken with the first free one (chez-awa-b111-2), a free one free, a short one its problem — signed-in only';
end $$;

\echo ''
\echo '--- TEST 4: one free business per person — a second needs Mara Pro ---'
do $$
declare
    r text;
    v jsonb;
    v_second uuid;
begin
    -- Awa owns one free shop now.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000002');
    v := my_business_start();
    if not (v ->> 'locked')::boolean or v ->> 'lock_message' is distinct from 'Une deuxième entreprise : avec Mara Pro.'
       or (v ->> 'owns')::int is distinct from 1 then
        raise exception 'FAIL: my_business_start does not say a second needs Pro: %', v;
    end if;
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000002', 'farm', 'Ferme Awa 111', 'ferme-awa-b111', 'mixte', 'Ouaga', '+22670111102');
    if r is distinct from 'Une deuxième entreprise : avec Mara Pro.' then
        raise exception 'FAIL: a second free business was made: %', r;
    end if;
    -- An owner of a Free shop made before 111.
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000006', 'association', 'Asso Bintou', 'asso-bintou-b111', 'autre', 'Ouaga', '+22670111106');
    if r is distinct from 'Une deuxième entreprise : avec Mara Pro.' then
        raise exception 'FAIL: the owner of a Free shop made a second: %', r;
    end if;
    -- An owner on Pro opens a second.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000007');
    if (my_business_start() ->> 'locked')::boolean then
        raise exception 'FAIL: an owner on Pro is told a second is locked';
    end if;
    v_second := create_my_business('farm', 'Ferme Issa 111', 'ferme-issa-b111', 'elevage', null,
                                   'Kaya', null, '+22670111107', 'XOF', null);
    if not exists (select 1 from memberships where org_id = v_second and user_id = '11111111-0000-0000-0000-000000000007' and role = 'owner') then
        raise exception 'FAIL: the Pro owner''s second business is not theirs';
    end if;
    perform pg_temp.as_user(null);
    raise notice 'PASS: a person who owns a Free business is refused a second (« Une deuxième entreprise : avec Mara Pro. »), told first by my_business_start; an owner on Pro creates a second';
end $$;

\echo ''
\echo '--- TEST 5: the platform''s switch — a number proved on WhatsApp first ---'
do $$
declare
    v_action uuid;
    v jsonb;
    r text;
    v_org uuid;
begin
    -- Réglages lists it; only the platform turns it, oui or non only.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000001');
    if platform_settings_board() -> 'create_phone_verified' ->> 'value' is distinct from 'false' then
        raise exception 'FAIL: Réglages does not list create_phone_verified, off';
    end if;
    begin
        perform platform_set_setting('create_phone_verified', '1');
        raise exception 'FAIL: the switch took a number';
    exception when others then
        if sqlerrm <> 'Ce réglage attend oui ou non.' then raise; end if;
    end;
    v_action := platform_set_setting('create_phone_verified', 'true');
    if v_action is null or not create_phone_required() then
        raise exception 'FAIL: the platform could not turn the switch on';
    end if;
    if not exists (select 1 from platform_actions where id = v_action and kind = 'setting') then
        raise exception 'FAIL: the switch is not in the journal';
    end if;
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000002');
    begin
        perform platform_set_setting('create_phone_verified', 'false');
        raise exception 'FAIL: a business owner turned the platform''s switch';
    exception when others then
        if sqlerrm <> 'Réservé à la plateforme' then raise; end if;
    end;
    -- On: no proved number (Google, or a number typed never proved), no business.
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000009', 'retail', 'Google 111', 'google-b111', 'autre', 'Ouaga', '+22670111109');
    if r is distinct from 'Vérifiez d''abord votre numéro WhatsApp' then
        raise exception 'FAIL: an account with no proved number created a business: %', r;
    end if;
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000010', 'retail', 'Non prouvé 111', 'non-prouve-b111', 'autre', 'Ouaga', '+22611110010');
    if r is distinct from 'Vérifiez d''abord votre numéro WhatsApp' then
        raise exception 'FAIL: a number never proved was taken as proved: %', r;
    end if;
    -- A proved number: told first, used when none is typed.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000008');
    v := my_business_start();
    if not (v ->> 'phone_required')::boolean or v ->> 'verified_phone' is distinct from '+22611110008' then
        raise exception 'FAIL: my_business_start does not say the switch and the proved number: %', v;
    end if;
    v_org := create_my_business('retail', 'Prouvée 111', 'prouvee-b111', 'beaute', null,
                                'Ouagadougou', 'Gounghin', null, 'XOF', null);
    if (select phone from orgs where id = v_org) is distinct from '+22611110008' then
        raise exception 'FAIL: the proved number is not the business''s phone';
    end if;
    -- Back off, through the journal.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000001');
    perform platform_undo(v_action);
    if create_phone_required() then
        raise exception 'FAIL: « Annuler » left the switch on';
    end if;
    perform pg_temp.as_user(null);
    raise notice 'PASS: Réglages lists create_phone_verified; only the platform turns it (oui/non), journaled, « Annuler » puts it back off';
    raise notice 'PASS: on, an account with no proved number — Google, or a number never proved — is refused « Vérifiez d''abord votre numéro WhatsApp. »; a proved one creates, its proved number the business''s phone';
end $$;

\echo ''
\echo '--- TEST 6: the creation page — its kinds, its questions, the answers kept as asked ---'
do $$
declare
    r text;
    v_org uuid;
    q_years text;
    q_where text;
    q_yes text;
begin
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000001');
    perform platform_set_application_form(jsonb_build_object(
        'welcome', 'Bienvenue sur Mara !',
        'kinds', jsonb_build_array('retail', 'association'),
        'questions', jsonb_build_array(
            jsonb_build_object('label', 'Depuis combien d''années ?', 'type', 'number', 'required', true),
            jsonb_build_object('label', 'Où vendez-vous ?', 'type', 'choice',
                               'options', jsonb_build_array('Au marché', 'En boutique'), 'required', true),
            jsonb_build_object('label', 'Livrez-vous ?', 'type', 'yesno'))));
    select (application_form() -> 'questions' -> 0 ->> 'id'),
           (application_form() -> 'questions' -> 1 ->> 'id'),
           (application_form() -> 'questions' -> 2 ->> 'id')
      into q_years, q_where, q_yes;
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000012');
    if my_business_start() -> 'form' ->> 'welcome' is distinct from 'Bienvenue sur Mara !' then
        raise exception 'FAIL: the creation page is not handed to the flow';
    end if;
    -- A kind the page does not offer.
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000012', 'farm', 'Ferme 111 form', 'ferme-form-b111', 'mixte', 'Ouaga', '+22611110012');
    if r is distinct from 'Ce type d''activité ne peut pas être créé pour l''instant.' then
        raise exception 'FAIL: a kind the page does not offer was created: %', r;
    end if;
    -- A required question left empty, an answer of the wrong type.
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000012', 'retail', 'Form 111', 'form-b111', 'vetements', 'Ouaga', '+22611110012',
                         'XOF', jsonb_build_object(q_where, 'Au marché'));
    if r is distinct from 'Réponse obligatoire : Depuis combien d''années ?' then
        raise exception 'FAIL: a required question left empty: %', r;
    end if;
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000012', 'retail', 'Form 111', 'form-b111', 'vetements', 'Ouaga', '+22611110012',
                         'XOF', jsonb_build_object(q_years, 'trois', q_where, 'Au marché'));
    if r is distinct from 'Répondez en chiffres : Depuis combien d''années ?' then
        raise exception 'FAIL: a word for a number: %', r;
    end if;
    r := pg_temp.refusal('11111111-0000-0000-0000-000000000012', 'retail', 'Form 111', 'form-b111', 'vetements', 'Ouaga', '+22611110012',
                         'XOF', jsonb_build_object(q_years, '3', q_where, 'Au bord de la route'));
    if r is distinct from 'Choisissez une des réponses proposées : Où vendez-vous ?' then
        raise exception 'FAIL: an answer not offered: %', r;
    end if;
    -- Answered: created, the answers kept as asked.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000012');
    v_org := create_my_business('retail', 'Form 111', 'form-b111', 'vetements', null, 'Ouaga', null,
                                '+22611110012', 'XOF',
                                jsonb_build_object(q_years, '3,5', q_where, 'Au marché', q_yes, 'oui'));
    if (select answers from business_creations where org_id = v_org) is distinct from jsonb_build_array(
            jsonb_build_object('id', q_years, 'label', 'Depuis combien d''années ?', 'type', 'number', 'value', 3.5),
            jsonb_build_object('id', q_where, 'label', 'Où vendez-vous ?', 'type', 'choice', 'value', 'Au marché'),
            jsonb_build_object('id', q_yes, 'label', 'Livrez-vous ?', 'type', 'yesno', 'value', true)) then
        raise exception 'FAIL: the answers are not kept as asked: %',
            (select answers from business_creations where org_id = v_org);
    end if;
    if (select after -> 'answers' from platform_actions where org_id = v_org and kind = 'business_created')
       is distinct from (select answers from business_creations where org_id = v_org) then
        raise exception 'FAIL: the journal does not carry the answers';
    end if;
    -- The page back to today's.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000001');
    perform platform_set_application_form(null);
    perform pg_temp.as_user(null);
    raise notice 'PASS: the creation page shapes the flow — a kind it does not offer refused, a required question or an answer of the wrong type refused as 107 says it, the answers kept as asked (3.5, « Au marché », oui) and journaled';
end $$;

\echo ''
\echo '--- TEST 7: the old path for an older app; a waiting request closed by a direct creation ---'
do $$
declare
    v_app uuid;
    v_app2 uuid;
    v_org uuid;
    v_org2 uuid;
    a org_applications%rowtype;
begin
    -- An older app asks (101's seven arguments), as before.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000010');
    v_app := apply_for_org('Ancienne 111', 'ancienne-b111', 'retail', 'XOF', 'Une demande d''avant', null, null);
    -- The new app creates directly: the waiting request is closed with it.
    v_org := create_my_business('retail', 'Directe 111', 'directe-b111', 'telephonie', null,
                                'Ouagadougou', null, '+22611110010', 'XOF', null);
    select * into a from org_applications where id = v_app;
    if a.status is distinct from 'approved' or a.org_id is distinct from v_org or a.name is distinct from 'Directe 111'
       or a.decision_note is distinct from 'Créée directement par la personne' then
        raise exception 'FAIL: the waiting request was not closed with the business: %', to_jsonb(a);
    end if;
    if not exists (select 1 from notifications
                    where recipient_id = '11111111-0000-0000-0000-000000000010'
                      and kind = 'application_approved' and org_id = v_org) then
        raise exception 'FAIL: the person is not told their request became their business';
    end if;
    -- Another older app's request, approved by Mara: still works.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000011');
    v_app2 := apply_for_org('Validée 111', 'validee-b111', 'farm', 'XOF', 'Des poules', null, null);
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000001');
    v_org2 := approve_org_application(v_app2, null);
    if not exists (select 1 from memberships where org_id = v_org2
                      and user_id = '11111111-0000-0000-0000-000000000011' and role = 'owner') then
        raise exception 'FAIL: approving an older app''s request no longer works';
    end if;
    perform pg_temp.as_user(null);
    raise notice 'PASS: apply_for_org and approve_org_application still work for an older app; a request still waiting is closed « approved » with the business the person created directly (the person told), so it can never become a second';
end $$;

\echo ''
\echo '--- TEST 8: a new vitrine reaches the street only with its minimum (unchanged) ---'
do $$
declare v_shop uuid := (select id from orgs where slug = 'chez-awa-b111');
begin
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000002');
    perform set_storefront(v_shop, true, null);
    perform pg_temp.as_user(null);
    if storefront_open('chez-awa-b111') is not null
       or exists (select 1 from storefront_directory() d where d.slug = 'chez-awa-b111') then
        raise exception 'FAIL: a new vitrine with no article reached the street';
    end if;
    insert into products (org_id, name, sale_price, quantity, is_active, is_published)
    select v_shop, 'Article ' || g, 500, 5, true, true from generate_series(1, 7) g;
    if storefront_open('chez-awa-b111') is not null then
        raise exception 'FAIL: a new vitrine with 7 articles reached the street';
    end if;
    insert into products (org_id, name, sale_price, quantity, is_active, is_published)
    values (v_shop, 'Article 8', 500, 5, true, true);
    if storefront_open('chez-awa-b111') is distinct from v_shop then
        raise exception 'FAIL: a vitrine with its 8 articles is not on the street';
    end if;
    -- Its owner sees it all along (092).
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000002');
    if storefront_open('chez-awa-b111') is distinct from v_shop then
        raise exception 'FAIL: the owner cannot see their own vitrine';
    end if;
    perform pg_temp.as_user(null);
    raise notice 'PASS: a vitrine created through 111 and switched on stays off the street until its 8 articles (092''s minimum, unchanged), its owner seeing it all along';
end $$;

\echo ''
\echo '--- TEST 9: À faire — « Nouvelles activités (7 j) », its list, and 113''s reports ---'
do $$
declare
    v jsonb;
    v_list jsonb;
    n int;
begin
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000001');
    v := platform_todo();
    n := (select count(*) from orgs where archived_at is null and not showcase
                                      and created_at > now() - interval '7 days');
    if (v ->> 'new_7')::int is distinct from n or n < 9 then
        raise exception 'FAIL: new_7 is % for % new businesses', v ->> 'new_7', n;
    end if;
    if not v ? 'applications' then
        raise exception 'FAIL: an older app''s « Demandes » count is gone';
    end if;
    if to_regclass('public.problem_reports') is null and (v ->> 'reports_open')::int is distinct from 0 then
        raise exception 'FAIL: reports_open is not 0 without 113''s table: %', v ->> 'reports_open';
    end if;
    -- The list shows the 200 newest (the suites before this one made many).
    v_list := platform_todo_list('new_7');
    if jsonb_array_length(v_list) is distinct from least(n, 200)
       or exists (select 1 from jsonb_array_elements(v_list) e
                   where e ->> 'org_name' in ('Exemple B111', 'Gratuite B111', 'Pro B111')) then
        raise exception 'FAIL: the list behind new_7 is not the new businesses: %', v_list;
    end if;
    if not exists (select 1 from jsonb_array_elements(v_list) e
                    where e ->> 'org_name' = 'Chez Awa 111' and e ->> 'owner' = 'Awa Ouédraogo'
                      and e ->> 'city' = 'Ouagadougou' and (e ->> 'by_person')::boolean) then
        raise exception 'FAIL: Awa''s shop is not listed with its owner, town and maker: %', v_list;
    end if;
    -- An archived one leaves the count.
    update orgs set archived_at = now() where slug = 'chapelle-b111';
    if (platform_todo() ->> 'new_7')::int is distinct from n - 1 then
        raise exception 'FAIL: an archived business is still counted new';
    end if;
    update orgs set archived_at = null where slug = 'chapelle-b111';
    perform pg_temp.as_user(null);
    raise notice 'PASS: À faire counts the % businesses created in 7 days (a vitrine d''exemple, the older ones and an archived one aside), lists them with owner, town and who made them; « applications » kept for an older app', n;
end $$;

-- 113's count, read only when its table exists: proved with a stand-in
-- table, removed again (when 113 is applied its own table is read).
begin;
do $$
begin
    if to_regclass('public.problem_reports') is null then
        execute 'create table public.problem_reports (status text)';
        execute 'insert into public.problem_reports values (''open''), (''open''), (''closed'')';
        perform pg_temp.as_user('11111111-0000-0000-0000-000000000001');
        if (platform_todo() ->> 'reports_open')::int is distinct from 2 then
            raise exception 'FAIL: reports_open does not count the open reports';
        end if;
        perform pg_temp.as_user(null);
        raise notice 'PASS: reports_open counts problem_reports still open (2) when the table is there, and is 0 without it';
    else
        perform pg_temp.as_user('11111111-0000-0000-0000-000000000001');
        if (platform_todo() ->> 'reports_open')::int
           is distinct from (select count(*) from problem_reports where status = 'open') then
            raise exception 'FAIL: reports_open does not count 113''s open reports';
        end if;
        perform pg_temp.as_user(null);
        raise notice 'PASS: reports_open counts 113''s problem_reports still open';
    end if;
end $$;
rollback;

\echo ''
\echo '--- TEST 10: « Activités créées » — the businesses people created, and the requests of before ---'
do $$
declare
    v jsonb;
    items jsonb;
    e jsonb;
begin
    -- A request refused before 111: still readable with its reason.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000009');
    perform apply_for_org('Refusée 111', 'refusee-b111', 'retail', 'XOF', null, null, null);
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000001');
    perform reject_org_application((select id from org_applications where slug = 'refusee-b111'),
                                   'Informations manquantes');
    v := platform_created_businesses(500);
    items := v -> 'items';
    select x into e from jsonb_array_elements(items) x where x ->> 'slug' = 'form-b111';
    if e ->> 'how' is distinct from 'created' or e ->> 'activity' is distinct from 'vetements' or jsonb_array_length(e -> 'answers') is distinct from 3
       or e ->> 'person' is distinct from 'Formulaire111' then
        raise exception 'FAIL: a created business is not listed with its answers: %', e;
    end if;
    select x into e from jsonb_array_elements(items) x where x ->> 'slug' = 'validee-b111';
    if e ->> 'how' is distinct from 'approved' or e ->> 'about' is distinct from 'Des poules' then
        raise exception 'FAIL: a request approved by Mara is not kept readable: %', e;
    end if;
    select x into e from jsonb_array_elements(items) x where x ->> 'slug' = 'refusee-b111';
    if e ->> 'how' is distinct from 'rejected' or e ->> 'note' is distinct from 'Informations manquantes' then
        raise exception 'FAIL: a refused request is not kept readable: %', e;
    end if;
    -- The request closed by a direct creation is listed once, as created.
    if (select count(*) from jsonb_array_elements(items) x where x ->> 'slug' = 'directe-b111') is distinct from 1
       or (select x ->> 'how' from jsonb_array_elements(items) x where x ->> 'slug' = 'directe-b111') is distinct from 'created' then
        raise exception 'FAIL: a business made directly over a waiting request is listed twice or as approved';
    end if;
    if (v ->> 'old_requests')::int is distinct from (select count(*) from org_applications where status = 'pending') then
        raise exception 'FAIL: the waiting requests of an older app are not counted';
    end if;
    -- Newest first.
    if (select bool_or((items -> i ->> 'at') < (items -> (i + 1) ->> 'at'))
          from generate_series(0, jsonb_array_length(items) - 2) i) then
        raise exception 'FAIL: « Activités créées » is not newest first';
    end if;
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000002');
    begin
        perform platform_created_businesses(10);
        raise exception 'FAIL: a business owner read « Activités créées »';
    exception when others then
        if sqlerrm <> 'Réservé à la plateforme' then raise; end if;
    end;
    begin
        perform platform_todo_list('new_7');
        raise exception 'FAIL: a business owner read the new businesses';
    exception when others then
        if sqlerrm <> 'Réservé à la plateforme' then raise; end if;
    end;
    begin
        perform platform_todo();
        raise exception 'FAIL: a business owner read À faire';
    exception when others then
        if sqlerrm <> 'Réservé à la plateforme' then raise; end if;
    end;
    perform pg_temp.as_user(null);
    raise notice 'PASS: « Activités créées » lists the businesses people created (their line of trade, answers, who) and keeps the requests of before readable — approved, refused with the reason — once each, newest first; « Activités créées », À faire and its lists the platform''s alone';
end $$;

\echo ''
\echo '--- TEST P3: the doors and the internals ---'
do $$
declare
    f text;
begin
    foreach f in array array['my_business_start()', 'business_address_check(text)',
                             'create_my_business(text, text, text, text, text, text, text, text, text, jsonb)',
                             'platform_created_businesses(integer)', 'platform_todo()',
                             'platform_todo_list(text)', 'create_org(text, text, text, text)'] loop
        if not has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: % is not a signed-in door', f;
        end if;
        if has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: the street can call %', f;
        end if;
    end loop;
    foreach f in array array['org_create_core(uuid, text, text, text, text)',
                             'business_answers(jsonb, jsonb)', 'create_phone_required()',
                             'business_activities(text)'] loop
        if has_function_privilege('authenticated', f, 'execute')
           or has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: the internal % is callable by the app', f;
        end if;
    end loop;
    if has_table_privilege('authenticated', 'business_creations', 'select')
       or has_table_privilege('authenticated', 'business_creations', 'insert')
       or has_table_privilege('anon', 'business_creations', 'select') then
        raise exception 'FAIL: business_creations is open to the app';
    end if;
    -- create_org keeps its door: a person is refused it.
    perform pg_temp.as_user('11111111-0000-0000-0000-000000000009');
    begin
        perform create_org('Moi 111', 'moi-b111', 'retail', 'XOF');
        raise exception 'FAIL: a person used the platform''s create_org';
    exception when others then
        if sqlerrm <> 'Only a platform admin can create a new business' then raise; end if;
    end;
    perform pg_temp.as_user(null);
    raise notice 'PASS: the doors are the signed-in person''s or the platform''s (each checks), none the street''s; org_create_core, business_answers and the two helpers nobody''s; business_creations read through its function only; create_org still the platform''s';
end $$;

-- Leave the platform as the next suite expects it.
update platform_settings set value = 'false' where key = 'create_phone_verified';
delete from platform_settings where key = 'application_form';
