-- ============================================================
-- test_batch127.sql — the security audit's fixes (127).
--
-- The claims, for a shop, a farm and an association alike:
--   * team: no business admin writes a membership for somebody else, or
--     moves one onto somebody else, or writes an invitation already
--     claimed, or a scope of another business — straight from the app;
--     the invitation claimed by its person still makes them a member;
--     manages_user (the password reset's question) is false for somebody
--     who also belongs to a business the caller does not administer, true
--     for one's own employee; never a platform admin; sign_out_member still
--     reaches a clerk who works in two shops; security_log is no app door;
--   * documents: no row of one business names a key under another's
--     folder (insert or update), record_document and set_org_logo still
--     take one's own; a forged row written before 127 serves nothing to
--     the street; a logo or a cover never names another business's key;
--   * ledger: no line joins a posted entry (an employee's or the owner's),
--     no line names another business's account, no line or entry changes;
--     record_entry, record_sale, reverse_entry, record_contribution still
--     post balanced books; one generic query finds no child → parent
--     reference that may cross businesses unguarded (and finds one when a
--     guard is taken away); a sale line of another business's product is
--     refused;
--   * the delivery code: four wrong codes counted (« n essais avant
--     blocage »), the fifth locks the order 15 minutes and tells the shop,
--     the right code is refused while locked and delivers after; the old
--     door courier_deliver counts a wrong code and leaves the order open;
--   * the doors: the new helpers and triggers are nobody's; courier_handover
--     is the app's (authenticated), not the street's;
--   * P1: the ordinary flows of the three kinds — inviting and claiming,
--     roles, photos and a logo, sales, a reversal, an invoice, a credit
--     sale and its payment, contributions and expenses, a delivery with its
--     code — give the same books and rows with 127's guards as without.
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
-- Supabase gives the app's role every table; RLS and the triggers are the
-- gates these claims are about.
grant select, insert, update, delete on pending_invitations, documents, journal_entries,
    journal_lines, sale_lines, products to authenticated;
grant select on memberships, accounts, entities, departments, orgs, profiles, sales, orders to authenticated;
\i database/migrations/127_security_fixes.sql

\set mara    '''12712712-0000-0000-0000-000000000001'''
\set sowner  '''12712712-0000-0000-0000-000000000002'''
\set fowner  '''12712712-0000-0000-0000-000000000003'''
\set aowner  '''12712712-0000-0000-0000-000000000004'''
\set clerk   '''12712712-0000-0000-0000-000000000005'''
\set victim  '''12712712-0000-0000-0000-000000000006'''
\set multi   '''12712712-0000-0000-0000-000000000007'''
\set courier '''12712712-0000-0000-0000-000000000008'''
\set buyer   '''12712712-0000-0000-0000-000000000009'''
\set cashier '''12712712-0000-0000-0000-000000000010'''
\set p1a     '''12712712-0000-0000-0000-000000000011'''
\set p1b     '''12712712-0000-0000-0000-000000000012'''
\set p1c     '''12712712-0000-0000-0000-000000000013'''
\set other   '''12712712-0000-0000-0000-000000000014'''
\set shop    '''12700000-0000-0000-0000-000000000001'''
\set farm    '''12700000-0000-0000-0000-000000000002'''
\set assoc   '''12700000-0000-0000-0000-000000000003'''
\set ent     '''12700000-0000-0000-00e0-000000000002'''
\set o1      '''127aaaaa-0000-0000-0000-000000000001'''
\set o2      '''127aaaaa-0000-0000-0000-000000000002'''

create or replace function pg_temp.as127(p_who uuid)
returns void
language sql
as $$
    select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true),
           set_config('request.jwt.claims',
                      json_build_object('sub', p_who, 'role', 'authenticated')::text, true);
$$;

-- The message of a refused statement, or « (went through) » — never null.
-- Run as p_who under the authenticated role (or p_role).
create or replace function pg_temp.try127(p_who uuid, p_sql text, p_role text default 'authenticated')
returns text
language plpgsql
as $$
begin
    perform pg_temp.as127(p_who);
    execute format('set local role %I', p_role);
    execute p_sql;
    execute 'reset role';
    return '(went through)';
exception when others then
    execute 'reset role';
    return sqlerrm;
end;
$$;

insert into auth.users (id, phone, email, email_confirmed_at, raw_user_meta_data) values
    (:mara,    '+22612701001', 'mara127@example.org',     now(), '{"full_name": "Mara 127"}'),
    (:sowner,  '+22612701002', 'boutique127@example.org', now(), '{"full_name": "Patronne 127"}'),
    (:fowner,  '+22612701003', 'ferme127@example.org',    now(), '{"full_name": "Fermier 127"}'),
    (:aowner,  '+22612701004', 'entraide127@example.org', now(), '{"full_name": "Trésorière 127"}'),
    (:clerk,   '+22612701005', 'vendeur127@example.org',  now(), '{"full_name": "Vendeur 127"}'),
    (:victim,  '+22612701006', 'cible127@example.org',    now(), '{"full_name": "Cliente Cible"}'),
    (:multi,   '+22612701007', 'double127@example.org',   now(), '{"full_name": "Double Emploi"}'),
    (:courier, '+22612701008', 'livreur127@example.org',  now(), '{"full_name": "Livreur 127"}'),
    (:buyer,   '+22612701009', 'acheteuse127@example.org',now(), '{"full_name": "Acheteuse 127"}'),
    (:cashier, '+22612701010', 'caisse127@example.org',   now(), '{"full_name": "Caissière 127"}'),
    (:p1a,     '+22612701011', 'p1a127@example.org',      now(), '{"full_name": "Nouvelle Boutique"}'),
    (:p1b,     '+22612701012', 'p1b127@example.org',      now(), '{"full_name": "Nouveau Ferme"}'),
    (:p1c,     '+22612701013', 'p1c127@example.org',      now(), '{"full_name": "Nouveau Membre"}'),
    (:other,   '+22612701014', 'autre127@example.org',    now(), '{"full_name": "Autre Livreur"}');
update profiles set is_platform_admin = true where id = :mara;
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, setup_done_at) values
    (:shop,  'Boutique 127', 'boutique-127', 'retail',      'XOF', true, now()),
    (:farm,  'Ferme 127',    'ferme-127',    'farm',        'XOF', true, now()),
    (:assoc, 'Entraide 127', 'entraide-127', 'association', 'XOF', true, now());
update orgs set plan = 'pro' where id in (:shop, :farm, :assoc);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :sowner,  'owner',    'org', :shop,  'full'),
    (:farm,  :fowner,  'owner',    'org', :farm,  'full'),
    (:assoc, :aowner,  'owner',    'org', :assoc, 'full'),
    (:shop,  :clerk,   'employee', 'org', :shop,  'full'),
    (:shop,  :multi,   'employee', 'org', :shop,  'full'),
    (:farm,  :multi,   'employee', 'org', :farm,  'full'),
    (:farm,  :cashier, 'employee', 'org', :farm,  'full');
insert into entities (id, org_id, name) values (:ent, :farm, 'Parcelle Nord');
select seed_retail_accounts(:shop);
select seed_farm_accounts(:farm);
select seed_church_accounts(:assoc);
insert into couriers (user_id, phone, status) values
    (:courier, '+22612701008', 'approved'),
    (:other,   '+22612701014', 'approved');
insert into orders (id, org_id, customer_id, customer_name, status, fulfilment, address,
                    total, currency, delivery_fee) values
    (:o1, :shop, :buyer, 'Acheteuse 127', 'pending', 'delivery', 'Gounghin', 5000, 'XOF', 800),
    (:o2, :farm, :buyer, 'Acheteuse 127', 'pending', 'delivery', 'Pissy',    3000, 'XOF', 900);
update orders set status = 'accepted' where id in (:o1, :o2);
update orders set status = 'ready' where id in (:o1, :o2);
update orders set courier_id = :courier, status = 'in_transit' where id in (:o1, :o2);

-- A posted entry in each business's books (an earlier transaction).
begin;
select pg_temp.as127(:sowner);
set local role authenticated;
select record_entry(:shop, 10000, 'in', 'Vente du matin 127') is not null as shop_posted;
reset role;
select pg_temp.as127(:fowner);
set local role authenticated;
select record_entry(:farm, 7000, 'in', 'Vente d''œufs 127') is not null as farm_posted;
reset role;
select pg_temp.as127(:aowner);
set local role authenticated;
select record_entry(:assoc, 3000, 'in', 'Cotisation 127') is not null as assoc_posted;
reset role;
commit;

\echo ''
\echo '--- TEST 1: team — no membership for somebody else from the app; the invitation still makes one ---'
begin;
do $$
declare
    v_owner uuid; v_org uuid; v_r text; v_code text; v_m uuid;
    v_owners uuid[] := array['12712712-0000-0000-0000-000000000002', '12712712-0000-0000-0000-000000000003',
                             '12712712-0000-0000-0000-000000000004'];
    v_orgs   uuid[] := array['12700000-0000-0000-0000-000000000001', '12700000-0000-0000-0000-000000000002',
                             '12700000-0000-0000-0000-000000000003'];
    i int;
begin
    for i in 1 .. 3 loop
        v_owner := v_owners[i]; v_org := v_orgs[i];
        -- The audit's C1: a row for the victim, written straight.
        v_r := pg_temp.try127(v_owner, format(
            $q$insert into memberships (org_id, user_id, role, scope_kind, scope_id) values (%L, %L, 'employee', 'org', %L)$q$,
            v_org, '12712712-0000-0000-0000-000000000006', v_org));
        if v_r = '(went through)' then
            raise exception 'FAIL: the owner of % wrote a membership for the victim', v_org;
        end if;
        -- Moving one's employee's row onto the victim.
        v_r := pg_temp.try127(v_owner, format(
            $q$update memberships set user_id = %L where org_id = %L and role = 'employee'$q$,
            '12712712-0000-0000-0000-000000000006', v_org));
        -- An invitation written as already claimed by the victim.
        v_r := pg_temp.try127(v_owner, format(
            $q$insert into pending_invitations (org_id, role, scope_kind, scope_id, created_by, claimed_at, claimed_by)
               values (%L, 'employee', 'org', %L, %L, now(), %L)$q$,
            v_org, v_org, v_owner, '12712712-0000-0000-0000-000000000006'));
        if v_r = '(went through)' then
            raise exception 'FAIL: the owner of % wrote an invitation already claimed', v_org;
        end if;
        -- An open one, then marked claimed by hand.
        perform pg_temp.as127(v_owner);
        execute 'set local role authenticated';
        select code into v_code from invite_employee(v_org, 'employee', 'Invité 127');
        execute 'reset role';
        v_r := pg_temp.try127(v_owner, format(
            $q$update pending_invitations set claimed_at = now(), claimed_by = %L where code = %L$q$,
            '12712712-0000-0000-0000-000000000006', v_code));
        if exists (select 1 from pending_invitations where code = v_code and claimed_at is not null) then
            raise exception 'FAIL: the owner of % marked an invitation claimed by the victim', v_org;
        end if;
        -- The legitimate way: the victim claims it themselves.
        perform pg_temp.as127('12712712-0000-0000-0000-000000000006');
        execute 'set local role authenticated';
        if claim_invitation(v_code) <> v_org then
            raise exception 'FAIL: the claim did not answer the business';
        end if;
        execute 'reset role';
        if not exists (select 1 from memberships where org_id = v_org
                        and user_id = '12712712-0000-0000-0000-000000000006' and role = 'employee') then
            raise exception 'FAIL: the claimed invitation of % made no member', v_org;
        end if;
    end loop;
    -- The victim's place moved nowhere: three businesses, each by a claim.
    if (select count(*) from memberships where user_id = '12712712-0000-0000-0000-000000000006') <> 3 then
        raise exception 'FAIL: the victim holds % places', (select count(*) from memberships where user_id = '12712712-0000-0000-0000-000000000006');
    end if;
    -- A grant never moves, even past RLS (the trigger).
    begin
        update memberships set user_id = '12712712-0000-0000-0000-000000000006'
         where user_id = '12712712-0000-0000-0000-000000000005';
        raise exception 'FAIL: a grant moved to another person';
    exception when insufficient_privilege then
        if sqlerrm not like 'Un accès ne passe pas%' then raise; end if;
    end;
    -- A scope of another business, for an invitation or a membership.
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000002', format(
        $q$insert into pending_invitations (org_id, role, scope_kind, scope_id, created_by) values (%L, 'employee', 'entity', %L, %L)$q$,
        '12700000-0000-0000-0000-000000000001', '12700000-0000-0000-00e0-000000000002', '12712712-0000-0000-0000-000000000002'));
    if v_r is distinct from 'Cette portée appartient à une autre entreprise' then
        raise exception 'FAIL: an invitation scoped to another business''s entity gave « % »', v_r;
    end if;
    begin
        insert into memberships (org_id, user_id, role, scope_kind, scope_id)
        values ('12700000-0000-0000-0000-000000000001', '12712712-0000-0000-0000-000000000005',
                'supervisor', 'entity', '12700000-0000-0000-00e0-000000000002');
        raise exception 'FAIL: a membership scoped to another business''s entity';
    exception when check_violation then null;
    end;
    -- The farm's own entity is a scope it may give.
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000003', format(
        $q$insert into pending_invitations (org_id, role, scope_kind, scope_id, created_by) values (%L, 'supervisor', 'entity', %L, %L)$q$,
        '12700000-0000-0000-0000-000000000002', '12700000-0000-0000-00e0-000000000002', '12712712-0000-0000-0000-000000000003'));
    if v_r <> '(went through)' then
        raise exception 'FAIL: the farm could not invite to its own entity: %', v_r;
    end if;
    -- Roles and removals: the app's doors still work.
    select id into v_m from memberships where org_id = '12700000-0000-0000-0000-000000000001'
       and user_id = '12712712-0000-0000-0000-000000000005';
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000002', format('select set_membership_role(%L, %L)', v_m, 'supervisor'));
    if v_r <> '(went through)' or (select role from memberships where id = v_m) <> 'supervisor' then
        raise exception 'FAIL: set_membership_role gave %', v_r;
    end if;
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000002', format('select revoke_membership(%L)', v_m));
    if v_r <> '(went through)' or exists (select 1 from memberships where id = v_m) then
        raise exception 'FAIL: revoke_membership gave %', v_r;
    end if;
    raise notice 'PASS: the owners of a shop, a farm and an association write no membership for another, move none, pre-claim no invitation; the victim''s claim makes them a member; no scope of another business; roles and removals still go through';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: manages_user — never somebody who belongs elsewhere; the sign-out still reaches them ---'
begin;
do $$
declare v boolean; v_r text;
begin
    perform pg_temp.as127('12712712-0000-0000-0000-000000000002');
    execute 'set local role authenticated';
    if not manages_user('12712712-0000-0000-0000-000000000005') then
        raise exception 'FAIL: the shop owner does not manage their own clerk';
    end if;
    if manages_user('12712712-0000-0000-0000-000000000007') then
        raise exception 'FAIL: the shop owner manages somebody who also works at the farm';
    end if;
    if manages_user('12712712-0000-0000-0000-000000000006') or can_delete_user('12712712-0000-0000-0000-000000000006') then
        raise exception 'FAIL: the shop owner manages a shopper of no business';
    end if;
    if manages_user('12712712-0000-0000-0000-000000000001') then
        raise exception 'FAIL: a platform admin is managed from a business';
    end if;
    if can_delete_user('12712712-0000-0000-0000-000000000007') then
        raise exception 'FAIL: can_delete_user changed';
    end if;
    -- admin_save_member_profile asks manages_user: refused for the double.
    begin
        perform admin_save_member_profile('12712712-0000-0000-0000-000000000007', 'Pirate', 'Nom');
        raise exception 'FAIL: the shop owner renamed somebody of the farm';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    perform admin_save_member_profile('12712712-0000-0000-0000-000000000005', 'Vendeur', 'Cent-Vingt-Sept');
    execute 'reset role';
    perform pg_temp.as127('12712712-0000-0000-0000-000000000003');
    execute 'set local role authenticated';
    if manages_user('12712712-0000-0000-0000-000000000007') then
        raise exception 'FAIL: the farm owner manages somebody who also works at the shop';
    end if;
    if not manages_user('12712712-0000-0000-0000-000000000010') then
        raise exception 'FAIL: the farm owner does not manage their cashier';
    end if;
    execute 'reset role';
    perform pg_temp.as127('12712712-0000-0000-0000-000000000004');
    execute 'set local role authenticated';
    if manages_user('12712712-0000-0000-0000-000000000005') then
        raise exception 'FAIL: the association manages the shop''s clerk';
    end if;
    execute 'reset role';
    perform pg_temp.as127('12712712-0000-0000-0000-000000000001');
    execute 'set local role authenticated';
    if not manages_user('12712712-0000-0000-0000-000000000007') then
        raise exception 'FAIL: the platform does not manage a member of two businesses';
    end if;
    execute 'reset role';
    -- Signing out the double who lost their phone: the shop still may.
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000002', format('select sign_out_member(%L, %L)',
        '12700000-0000-0000-0000-000000000001', '12712712-0000-0000-0000-000000000007'));
    if v_r <> '(went through)' then
        raise exception 'FAIL: sign_out_member refused the double: %', v_r;
    end if;
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000005', format('select sign_out_member(%L, %L)',
        '12700000-0000-0000-0000-000000000001', '12712712-0000-0000-0000-000000000007'));
    if v_r = '(went through)' then
        raise exception 'FAIL: a clerk signed somebody out';
    end if;
    -- security_log is no app door.
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000002', format(
        $q$select security_log(%L, 'password_changed', 'faux')$q$, '12712712-0000-0000-0000-000000000006'));
    if v_r not like 'permission denied%' then
        raise exception 'FAIL: security_log for another person gave « % »', v_r;
    end if;
    raise notice 'PASS: manages_user — own clerk and cashier yes, a member of two businesses or a shopper or the platform no (shop, farm, association), the platform yes; the profile door follows; sign_out_member still reaches the double; security_log is permission denied';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: documents — a key under another business''s folder, never ---'
begin;
do $$
declare
    v_shop uuid := '12700000-0000-0000-0000-000000000001';
    v_farm uuid := '12700000-0000-0000-0000-000000000002';
    v_foreign text := 'org/12700000-0000-0000-0000-000000000002/2026/10/aaaaaaaa-1111-2222-3333-444444444444.jpg';
    v_own text := 'org/12700000-0000-0000-0000-000000000001/2026/10/bbbbbbbb-1111-2222-3333-444444444444.jpg';
    v_r text; v_doc uuid; v_product uuid;
begin
    -- The audit's repro: straight into documents.
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000002', format(
        $q$insert into documents (org_id, uploaded_by, r2_key, kind, content_type) values (%L, %L, %L, 'photo', 'image/jpeg')$q$,
        v_shop, '12712712-0000-0000-0000-000000000002', v_foreign));
    if v_r is distinct from 'Cette photo n''est pas un fichier de cette entreprise' then
        raise exception 'FAIL: a foreign key straight into documents gave « % »', v_r;
    end if;
    -- record_document takes one's own; an update cannot point it away.
    perform pg_temp.as127('12712712-0000-0000-0000-000000000002');
    execute 'set local role authenticated';
    v_product := ensure_product(v_shop, 'Savon 127', 500, 300);
    update products set is_published = true where id = v_product;
    v_doc := record_document(v_shop, v_own, 'product_photo', null, 'image/jpeg', 1000, null, null, null, null, v_product);
    execute 'reset role';
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000002', format(
        $q$update documents set r2_key = %L where id = %L$q$, v_foreign, v_doc));
    if (select r2_key from documents where id = v_doc) <> v_own then
        raise exception 'FAIL: an update pointed the photo at the farm''s key';
    end if;
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000002', format(
        $q$select set_org_logo(%L, %L)$q$, v_shop, v_own));
    if v_r <> '(went through)' or (select logo_key from orgs where id = v_shop) <> v_own then
        raise exception 'FAIL: set_org_logo refused one''s own photo: %', v_r;
    end if;
    if not storefront_photo_allowed(v_own) then
        raise exception 'FAIL: the street does not see the published article''s own photo';
    end if;
    -- A forged row written before 127 (past the trigger): the street never
    -- serves it, the logo and the cover never take it.
    alter table documents disable trigger document_key;
    insert into documents (org_id, uploaded_by, r2_key, kind, content_type, product_id)
    values (v_shop, '12712712-0000-0000-0000-000000000002', v_foreign, 'product_photo', 'image/jpeg', v_product);
    alter table documents enable trigger document_key;
    if storefront_photo_allowed(v_foreign) then
        raise exception 'FAIL: the street serves the farm''s object through the shop''s forged row';
    end if;
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000002', format(
        $q$select set_org_logo(%L, %L)$q$, v_shop, v_foreign));
    if v_r is distinct from 'Le logo doit être une photo de cette entreprise' then
        raise exception 'FAIL: the forged logo gave « % »', v_r;
    end if;
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000002', format(
        $q$select set_storefront_style(%L, %L::jsonb)$q$, v_shop, jsonb_build_object('cover_key', v_foreign)));
    if v_r is distinct from 'La photo de couverture doit être une photo de cette entreprise' then
        raise exception 'FAIL: the forged cover gave « % »', v_r;
    end if;
    -- The farm and the association: the same rule.
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000003', format(
        $q$insert into documents (org_id, uploaded_by, r2_key, kind) values (%L, %L, %L, 'receipt')$q$,
        v_farm, '12712712-0000-0000-0000-000000000003', v_own));
    if v_r is distinct from 'Cette photo n''est pas un fichier de cette entreprise' then
        raise exception 'FAIL: the farm''s row naming the shop''s key gave « % »', v_r;
    end if;
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000004', format(
        $q$select record_document(%L, %L, 'receipt')$q$, '12700000-0000-0000-0000-000000000003',
        'org/12700000-0000-0000-0000-000000000003/2026/10/cccccccc-1111-2222-3333-444444444444.jpg'));
    if v_r <> '(went through)' then
        raise exception 'FAIL: the association''s own receipt was refused: %', v_r;
    end if;
    if not exists (select 1 from pg_constraint where conname = 'courier_file_key_is_theirs' and convalidated) then
        raise exception 'FAIL: a courier''s file is not held to their own folder';
    end if;
    raise notice 'PASS: no row of a shop, a farm or an association names another''s key (insert or update); one''s own photo, logo and receipt still taken; a forged older row serves nothing and makes no logo or cover; a courier file stays in its folder';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: ledger — a posted entry is closed; an account of another business never ---'
begin;
do $$
declare
    v_shop uuid := '12700000-0000-0000-0000-000000000001';
    v_farm uuid := '12700000-0000-0000-0000-000000000002';
    v_assoc uuid := '12700000-0000-0000-0000-000000000003';
    v_entry uuid; v_caisse uuid; v_shop_caisse uuid; v_r text; v_new uuid; v_rev uuid; v_sale uuid; v_product uuid;
    v_line uuid;
begin
    select je.id into v_entry from journal_entries je where je.org_id = v_farm and je.label = 'Vente d''œufs 127';
    select id into v_caisse from accounts where org_id = v_farm and code = '1000';
    select id into v_shop_caisse from accounts where org_id = v_shop and code = '1000';
    -- The audit's repro: the cashier appends a line to the owner's entry.
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000010', format(
        $q$insert into journal_lines (journal_entry_id, account_id, debit, credit) values (%L, %L, 0, 500000)$q$,
        v_entry, v_caisse));
    if v_r not like 'Une écriture passée ne se complète pas%' then
        raise exception 'FAIL: the cashier''s line on a posted entry gave « % »', v_r;
    end if;
    -- Nor the owner.
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000003', format(
        $q$insert into journal_lines (journal_entry_id, account_id, debit, credit) values (%L, %L, 1, 0)$q$,
        v_entry, v_caisse));
    if v_r not like 'Une écriture passée ne se complète pas%' then
        raise exception 'FAIL: the owner''s line on a posted entry gave « % »', v_r;
    end if;
    -- The audit's cross-business line: the shop's new entry, the farm's
    -- Caisse, in the entry's own transaction.
    perform pg_temp.as127('12712712-0000-0000-0000-000000000002');
    execute 'set local role authenticated';
    insert into journal_entries (org_id, created_by, memo)
    values (v_shop, '12712712-0000-0000-0000-000000000002', 'x') returning id into v_new;
    begin
        insert into journal_lines (journal_entry_id, account_id, debit, credit) values (v_new, v_caisse, 9999999, 0);
        raise exception 'FAIL: a line on the farm''s account from the shop';
    exception when check_violation then
        if sqlerrm <> 'Cette fiche renvoie à une autre entreprise' then raise; end if;
    end;
    execute 'reset role';
    -- A new entry and its lines, in one transaction, are still the shop's
    -- to write (as an invoker function such as record_expense does).
    perform pg_temp.as127('12712712-0000-0000-0000-000000000002');
    execute 'set local role authenticated';
    insert into journal_entries (org_id, created_by, memo)
    values (v_shop, '12712712-0000-0000-0000-000000000002', 'à la main') returning id into v_new;
    insert into journal_lines (journal_entry_id, account_id, debit, credit) values
        (v_new, v_shop_caisse, 100, 0),
        (v_new, (select id from accounts where org_id = v_shop and code = '4000'), 0, 100);
    execute 'reset role';
    -- An entry of the shop on the farm's entity.
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000002', format(
        $q$insert into journal_entries (org_id, created_by, entity_id, memo) values (%L, %L, %L, 'x')$q$,
        v_shop, '12712712-0000-0000-0000-000000000002', '12700000-0000-0000-00e0-000000000002'));
    if v_r = '(went through)' then
        raise exception 'FAIL: the shop wrote an entry on the farm''s entity';
    end if;
    -- A line or an entry never changes, even for the owner through SQL
    -- that RLS would let through (definer-like, past RLS).
    perform pg_temp.as127('12712712-0000-0000-0000-000000000003');
    select id into v_line from journal_lines where journal_entry_id = v_entry limit 1;
    begin
        update journal_lines set debit = debit + 1 where id = v_line;
        raise exception 'FAIL: a posted line changed';
    exception when insufficient_privilege then null;
    end;
    begin
        update journal_entries set memo = 'réécrit' where id = v_entry;
        raise exception 'FAIL: a posted entry changed';
    exception when insufficient_privilege then null;
    end;
    perform pg_temp.as127(null);
    -- The legitimate paths, in each kind.
    perform pg_temp.as127('12712712-0000-0000-0000-000000000002');
    execute 'set local role authenticated';
    v_new := record_entry(v_shop, 2500, 'out', 'Transport 127');
    v_rev := reverse_entry(v_new, '12712712-0000-0000-0000-000000000002', 'erreur');
    v_product := ensure_product(v_shop, 'Riz 127', 1000, 700);
    execute 'reset role';
    update products set quantity = 10 where id = v_product;
    execute 'set local role authenticated';
    v_sale := record_sale(v_shop, jsonb_build_array(jsonb_build_object('product_id', v_product, 'quantity', 2)));
    execute 'reset role';
    perform pg_temp.as127('12712712-0000-0000-0000-000000000010');
    execute 'set local role authenticated';
    perform record_entry(v_farm, 1500, 'in', 'Vente au marché 127');
    execute 'reset role';
    perform pg_temp.as127('12712712-0000-0000-0000-000000000004');
    execute 'set local role authenticated';
    perform record_contribution(v_assoc, 2000, 'offering', '12712712-0000-0000-0000-000000000004');
    execute 'reset role';
    if v_rev is null or v_sale is null then
        raise exception 'FAIL: a reversal or a sale did not post';
    end if;
    if exists (select je.org_id from journal_entries je join journal_lines jl on jl.journal_entry_id = je.id
                where je.org_id in (v_shop, v_farm, v_assoc)
                group by je.id, je.org_id having sum(jl.debit) <> sum(jl.credit)) then
        raise exception 'FAIL: an entry is out of balance';
    end if;
    if exists (select 1 from journal_lines jl join journal_entries je on je.id = jl.journal_entry_id
                join accounts a on a.id = jl.account_id where a.org_id <> je.org_id) then
        raise exception 'FAIL: a line names another business''s account';
    end if;
    -- A sale line of the farm's product on the shop's sale.
    insert into products (org_id, name, sale_price, quantity, created_by)
    values (v_farm, 'Œufs 127', 100, 50, '12712712-0000-0000-0000-000000000003');
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000002', format(
        $q$insert into sale_lines (sale_id, product_id, quantity, unit_price) values (%L, %L, 1, 1)$q$,
        v_sale, (select id from products where org_id = v_farm and name = 'Œufs 127')));
    if v_r is distinct from 'Cette fiche renvoie à une autre entreprise' then
        raise exception 'FAIL: the farm''s product on the shop''s sale gave « % »', v_r;
    end if;
    raise notice 'PASS: no line on a posted entry (the cashier''s or the owner''s), none on another business''s account, no entry on another''s entity, no line or entry rewritten, no sale line of the farm''s product on the shop''s sale; record_entry, reverse_entry, record_sale (shop), record_entry by the cashier (farm), record_contribution (association) post balanced books';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: the generic query — no child → parent reference may cross businesses unguarded ---'
begin;
create temp table b127_fk on commit drop as
with orgish as (
    select c.oid from pg_class c
     where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
       and (exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'org_id' and not a.attisdropped)
            or c.relname = 'departments')
), fk as (
    select c.conrelid as child, a.attname::text as col, c.confrelid as parent
      from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f' and c.connamespace = 'public'::regnamespace
       and array_length(c.conkey, 1) = 1
       and c.confrelid in (select oid from orgish) and c.confrelid <> 'orgs'::regclass
), at_risk as (
    -- a child with its own business, or one with two business-owned parents
    select * from fk f
     where f.child in (select oid from orgish where oid <> 'departments'::regclass)
        or (select count(*) from fk g where g.child = f.child) >= 2
), covered as (
    select t.tgrelid as child, x
      from pg_trigger t, unnest(string_to_array(encode(t.tgargs, 'escape'), '\000')) x
     where t.tgname = 'same_org' and t.tgenabled <> 'D' and x <> ''
)
select r.child::regclass::text as child, r.col, r.parent::regclass::text as parent
  from at_risk r
 where not exists (select 1 from covered c where c.child = r.child and c.x = r.col || ':' || r.parent::regclass::text);
do $$
declare v_n int; v_risk int;
begin
    if exists (select 1 from b127_fk) then
        raise exception 'FAIL: references that may cross businesses: %', (select string_agg(child || '.' || col || ' → ' || parent, ', ') from b127_fk);
    end if;
    select count(*) into v_n from pg_trigger where tgname = 'same_org';
    if v_n < 30 then
        raise exception 'FAIL: only % tables carry the same-business guard', v_n;
    end if;
    raise notice 'PASS: every child → parent reference between business-owned tables is guarded (% tables)', v_n;
end $$;
-- The query is not blind: one guard taken away shows.
alter table order_lines disable trigger same_org;
do $$
declare v text;
begin
    with orgish as (
        select c.oid from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
           and (exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'org_id' and not a.attisdropped)
                or c.relname = 'departments')
    ), fk as (
        select c.conrelid as child, a.attname::text as col, c.confrelid as parent
          from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
         where c.contype = 'f' and c.connamespace = 'public'::regnamespace and array_length(c.conkey, 1) = 1
           and c.confrelid in (select oid from orgish) and c.confrelid <> 'orgs'::regclass
    ), at_risk as (
        select * from fk f where f.child in (select oid from orgish where oid <> 'departments'::regclass)
            or (select count(*) from fk g where g.child = f.child) >= 2
    ), covered as (
        select t.tgrelid as child, x from pg_trigger t, unnest(string_to_array(encode(t.tgargs, 'escape'), '\000')) x
         where t.tgname = 'same_org' and t.tgenabled <> 'D' and x <> ''
    )
    select string_agg(r.child::regclass::text || '.' || r.col, ', ' order by r.col) into v from at_risk r
     where not exists (select 1 from covered c where c.child = r.child and c.x = r.col || ':' || r.parent::regclass::text);
    if v is distinct from 'order_lines.order_id, order_lines.product_id' then
        raise exception 'FAIL: with order_lines unguarded the query says %', v;
    end if;
    raise notice 'PASS: with order_lines'' guard off, the query names order_lines.order_id and .product_id';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: the delivery code — five wrong codes lock the order 15 minutes, the shop is told ---'
begin;
do $$
declare
    v_o uuid := '127aaaaa-0000-0000-0000-000000000001';
    v_code text := (select handover_code from orders where id = '127aaaaa-0000-0000-0000-000000000001');
    v_wrong text;
    v jsonb; i int; v_r text;
begin
    v_wrong := lpad(((v_code::int + 1) % 10000)::text, 4, '0');
    perform pg_temp.as127('12712712-0000-0000-0000-000000000008');
    execute 'set local role authenticated';
    for i in 1 .. 4 loop
        v := courier_handover(v_o, v_wrong);
        if v ->> 'reason' <> 'wrong_code' or (v ->> 'left')::int <> 5 - i
           or v ->> 'message' not like 'Code incorrect%' then
            raise exception 'FAIL: wrong code % gave %', i, v;
        end if;
    end loop;
    if (courier_handover(v_o, v_wrong) ->> 'message') <> 'Trop de codes faux : cette livraison est bloquée 15 min. La boutique est prévenue.' then
        raise exception 'FAIL: the fifth wrong code did not lock';
    end if;
    v := courier_handover(v_o, v_code);
    if v ->> 'reason' <> 'locked' or (v ->> 'minutes')::int not between 14 and 15 then
        raise exception 'FAIL: the right code while locked gave %', v;
    end if;
    -- The old door says it, as a refusal.
    begin
        perform courier_deliver(v_o, v_code);
        raise exception 'FAIL: courier_deliver delivered while locked';
    exception when raise_exception then
        if sqlerrm not like 'Trop de codes faux%' then raise; end if;
    end;
    execute 'reset role';
    if (select status from orders where id = v_o) <> 'in_transit' then
        raise exception 'FAIL: the order moved while locked';
    end if;
    if not exists (select 1 from notifications where recipient_id = '12712712-0000-0000-0000-000000000002'
                    and kind = 'delivery_code_locked' and params ->> 'order_id' = v_o::text) then
        raise exception 'FAIL: the shop was not told of the lock';
    end if;
    if notification_type_of('delivery_code_locked', jsonb_build_object('to', 'shop')) <> 'shop_orders' then
        raise exception 'FAIL: the lock is not a shop order notice';
    end if;
    -- Fifteen minutes later.
    update handover_guards set locked_until = now() - interval '1 second' where order_id = v_o;
    perform pg_temp.as127('12712712-0000-0000-0000-000000000008');
    execute 'set local role authenticated';
    v := courier_handover(v_o, v_wrong);
    if (v ->> 'left')::int <> 4 then
        raise exception 'FAIL: after the lock the count did not start again: %', v;
    end if;
    v := courier_handover(v_o, v_code);
    execute 'reset role';
    if v is distinct from '{"ok": true}'::jsonb or (select status from orders where id = v_o) <> 'delivered'
       or exists (select 1 from handover_guards where order_id = v_o) then
        raise exception 'FAIL: the right code after the lock gave %', v;
    end if;
    if not exists (select 1 from notifications where recipient_id = '12712712-0000-0000-0000-000000000009'
                    and kind = 'order_delivered') then
        raise exception 'FAIL: the customer was not told';
    end if;
    -- The farm's delivery, through the old door: a wrong code counted, the
    -- order left open, then the right one delivers.
    v_o := '127aaaaa-0000-0000-0000-000000000002';
    v_code := (select handover_code from orders where id = v_o);
    v_wrong := lpad(((v_code::int + 1) % 10000)::text, 4, '0');
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000014', format('select courier_handover(%L, %L)', v_o, v_code));
    if v_r is distinct from 'Cette livraison n''est pas la vôtre' then
        raise exception 'FAIL: another courier''s try gave « % »', v_r;
    end if;
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000008', format('select courier_deliver(%L, %L)', v_o, v_wrong));
    if v_r <> '(went through)' or (select status from orders where id = v_o) <> 'in_transit'
       or (select failures from handover_guards where order_id = v_o) <> 1 then
        raise exception 'FAIL: the old door with a wrong code gave « % »', v_r;
    end if;
    v_r := pg_temp.try127('12712712-0000-0000-0000-000000000008', format('select courier_deliver(%L, %L)', v_o, v_code));
    if v_r <> '(went through)' or (select status from orders where id = v_o) <> 'delivered' then
        raise exception 'FAIL: the old door with the right code gave « % »', v_r;
    end if;
    raise notice 'PASS: four wrong codes counted (4…1 left), the fifth locks 15 min and tells the shop (shop_orders), the right code refused while locked (both doors), the count starts again after, the right code delivers and tells the customer; the farm''s delivery through the old door: a wrong code counted and left open, another courier refused';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: the doors ---'
do $$
declare v_f text;
begin
    foreach v_f in array array['scope_in_org(scope_kind, uuid, uuid)', 'outranks_member(uuid)', 'trg_membership_holder()',
                               'trg_invitation_scope()', 'key_is_orgs(text, uuid)', 'key_names_other_org(text, uuid)',
                               'trg_document_key()', 'trg_org_keys()', 'row_is_this_transactions(xid)',
                               'trg_journal_line_closed()', 'trg_journal_entry_closed()', 'org_of_row(text, uuid)',
                               'trg_same_org()', 'security_log(uuid, text, text)'] loop
        if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute')
           or has_function_privilege('public', v_f, 'execute') then
            raise exception 'FAIL: % is callable from the app or the street', v_f;
        end if;
    end loop;
    if not has_function_privilege('authenticated', 'courier_handover(uuid, text)', 'execute')
       or has_function_privilege('anon', 'courier_handover(uuid, text)', 'execute')
       or not has_function_privilege('authenticated', 'courier_deliver(uuid, text)', 'execute')
       or not has_function_privilege('authenticated', 'manages_user(uuid)', 'execute')
       or not has_function_privilege('anon', 'storefront_photo_allowed(text)', 'execute') then
        raise exception 'FAIL: an app or street door moved';
    end if;
    if has_table_privilege('authenticated', 'handover_guards', 'select')
       or has_table_privilege('anon', 'handover_guards', 'select') then
        raise exception 'FAIL: the wrong codes are readable';
    end if;
    if exists (select 1 from pg_policy where polrelid = 'memberships'::regclass and polcmd in ('a', 'w')) then
        raise exception 'FAIL: memberships still has an insert or update policy';
    end if;
    if exists (select 1 from pg_proc where proname in ('courier_handover', 'scope_in_org', 'outranks_member', 'key_is_orgs',
                    'trg_same_org', 'org_of_row', 'row_is_this_transactions', 'trg_journal_line_closed')
                and not coalesce((select true from unnest(proconfig) c where c like 'search_path=%'), false)) then
        raise exception 'FAIL: a 127 function has no search path';
    end if;
    raise notice 'PASS: the helpers and triggers are nobody''s, security_log too; courier_handover is the app''s, not the street''s; the wrong codes unreadable; memberships has no insert or update policy; search paths pinned';
end $$;

\echo ''
\echo '--- TEST 8: P1 — the ordinary flows give the same books and rows with 127''s guards as without ---'
-- The flows of the three kinds, as their people do them; what they leave.
create or replace function pg_temp.flows127()
returns jsonb
language plpgsql
as $$
declare
    v_shop  uuid := '12700000-0000-0000-0000-000000000001';
    v_farm  uuid := '12700000-0000-0000-0000-000000000002';
    v_assoc uuid := '12700000-0000-0000-0000-000000000003';
    v_code text; v_m uuid; v_p uuid; v_e uuid; v_d uuid; v_debt uuid; v_o uuid := '127aaaaa-0000-0000-0000-000000000001';
    v_out jsonb;
begin
    -- The shop: an invitation claimed, a role, a photo, the logo, a sale,
    -- a reversal, an invoice, a delivery with its code.
    perform pg_temp.as127('12712712-0000-0000-0000-000000000002');
    execute 'set local role authenticated';
    select code into v_code from invite_employee(v_shop, 'employee', 'Nouvelle Boutique');
    v_p := ensure_product(v_shop, 'Huile P1', 1500, 1000);
    perform record_document(v_shop, 'org/12700000-0000-0000-0000-000000000001/p1/huile.jpg', 'product_photo',
                            null, 'image/jpeg', 100, null, null, null, null, v_p);
    perform record_document(v_shop, 'org/12700000-0000-0000-0000-000000000001/p1/logo.png', 'photo');
    perform set_org_logo(v_shop, 'org/12700000-0000-0000-0000-000000000001/p1/logo.png');
    v_e := record_entry(v_shop, 4000, 'out', 'Loyer P1');
    perform reverse_entry(v_e, '12712712-0000-0000-0000-000000000002', 'erreur P1');
    perform create_invoice(v_shop, 'Client P1', '[{"description": "Huile", "quantity": 2, "unit_price": 1500}]'::jsonb);
    execute 'reset role';
    update products set quantity = 20 where id = v_p;
    perform pg_temp.as127('12712712-0000-0000-0000-000000000002');
    execute 'set local role authenticated';
    perform record_sale(v_shop, jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 3)));
    execute 'reset role';
    perform pg_temp.as127('12712712-0000-0000-0000-000000000011');
    execute 'set local role authenticated';
    perform claim_invitation(v_code);
    execute 'reset role';
    select id into v_m from memberships where org_id = v_shop and user_id = '12712712-0000-0000-0000-000000000011';
    perform pg_temp.as127('12712712-0000-0000-0000-000000000002');
    execute 'set local role authenticated';
    perform set_membership_role(v_m, 'supervisor');
    execute 'reset role';
    perform pg_temp.as127('12712712-0000-0000-0000-000000000008');
    execute 'set local role authenticated';
    perform courier_deliver(v_o, (select handover_code from orders where id = v_o));
    execute 'reset role';
    -- The farm: an invitation claimed, a sale at the market, a receipt on
    -- it, a sale on credit and its payment, the cashier's entry.
    perform pg_temp.as127('12712712-0000-0000-0000-000000000003');
    execute 'set local role authenticated';
    select code into v_code from invite_employee(v_farm, 'employee', 'Nouveau Ferme');
    v_e := record_entry(v_farm, 6000, 'in', 'Marché P1');
    perform record_document(v_farm, 'org/12700000-0000-0000-0000-000000000002/p1/recu.jpg', 'receipt',
                            null, 'image/jpeg', 100, null, null, null, v_e);
    v_d := record_credit_sale(v_farm, 'Voisin P1', 2500, 'Œufs à crédit');
    select id into v_debt from debts where org_id = v_farm and customer_id in
        (select id from customers where org_id = v_farm and name = 'Voisin P1') limit 1;
    perform record_debt_payment(v_debt, 1000);
    execute 'reset role';
    perform pg_temp.as127('12712712-0000-0000-0000-000000000012');
    execute 'set local role authenticated';
    perform claim_invitation(v_code);
    execute 'reset role';
    perform pg_temp.as127('12712712-0000-0000-0000-000000000010');
    execute 'set local role authenticated';
    perform record_entry(v_farm, 800, 'out', 'Aliment P1');
    execute 'reset role';
    -- The association: a contribution, an expense, a member invited.
    perform pg_temp.as127('12712712-0000-0000-0000-000000000004');
    execute 'set local role authenticated';
    select code into v_code from invite_employee(v_assoc, 'employee', 'Nouveau Membre');
    perform record_contribution(v_assoc, 5000, 'offering', '12712712-0000-0000-0000-000000000004');
    perform record_expense(v_assoc, 1200, '5000', '12712712-0000-0000-0000-000000000004');
    perform record_document(v_assoc, 'org/12700000-0000-0000-0000-000000000003/p1/facture.jpg', 'receipt');
    execute 'reset role';
    perform pg_temp.as127('12712712-0000-0000-0000-000000000013');
    execute 'set local role authenticated';
    perform claim_invitation(v_code);
    execute 'reset role';
    perform pg_temp.as127(null);

    select jsonb_build_object(
        'books', (select jsonb_object_agg(o.slug || ' ' || a.code, b.bal order by o.slug, a.code)
                    from (select je.org_id, jl.account_id, sum(jl.debit - jl.credit) as bal
                            from journal_entries je join journal_lines jl on jl.journal_entry_id = je.id
                           where je.org_id in (v_shop, v_farm, v_assoc) group by 1, 2) b
                    join accounts a on a.id = b.account_id join orgs o on o.id = b.org_id),
        'entries', (select count(*) from journal_entries where org_id in (v_shop, v_farm, v_assoc)),
        'team', (select jsonb_agg(o.slug || ' ' || p.full_name || ' ' || m.role order by o.slug, p.full_name, m.role)
                   from memberships m join orgs o on o.id = m.org_id join profiles p on p.id = m.user_id
                  where m.org_id in (v_shop, v_farm, v_assoc)),
        'invitations', (select count(*) from pending_invitations where org_id in (v_shop, v_farm, v_assoc) and claimed_at is not null),
        'documents', (select jsonb_agg(r2_key || ' ' || coalesce(kind, '') order by r2_key) from documents where org_id in (v_shop, v_farm, v_assoc)),
        'logo', (select logo_key from orgs where id = v_shop),
        'street', storefront_photo_allowed('org/12700000-0000-0000-0000-000000000001/p1/logo.png'),
        'orders', (select jsonb_agg(id || ' ' || status order by id) from orders where org_id in (v_shop, v_farm)),
        'debts', (select jsonb_agg(amount || ' ' || coalesce(paid, 0) order by amount) from (
                    select d.amount, (select sum(amount) from debt_payments where debt_id = d.id) as paid
                      from debts d where d.org_id = v_farm) x),
        'invoices', (select count(*) from invoices where org_id = v_shop),
        'sales', (select count(*) from sales where org_id = v_shop),
        'stock', (select quantity from products where org_id = v_shop and name = 'Huile P1'),
        'notices', (select jsonb_agg(kind order by kind) from notifications
                     where recipient_id in ('12712712-0000-0000-0000-000000000002', '12712712-0000-0000-0000-000000000003',
                                            '12712712-0000-0000-0000-000000000004', '12712712-0000-0000-0000-000000000009')))
      into v_out;
    return v_out;
end;
$$;
-- With 127's guards (kept in a psql variable, the flows rolled back).
begin;
select pg_temp.flows127() as with127 \gset
rollback;
-- Without them: the triggers off, 126's two policies back.
begin;
do $$
declare r record;
begin
    for r in select tgrelid::regclass as t, tgname from pg_trigger
              where tgname in ('same_org', 'membership_holder', 'invitation_scope', 'document_key', 'org_keys',
                               'journal_line_closed', 'journal_entry_closed') loop
        execute format('alter table %s disable trigger %I', r.t, r.tgname);
    end loop;
end $$;
create policy "memberships granted by org admins" on memberships for insert
with check (is_org_admin(org_id) and ((role <> 'owner' and not is_trainer)
            or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)));
create policy "memberships amended by org admins" on memberships for update
using (is_org_admin(org_id) and ((role <> 'owner' and not is_trainer)
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)))
with check (is_org_admin(org_id) and ((role <> 'owner' and not is_trainer)
            or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)));
create temp table b127_with on commit drop as select :'with127'::jsonb as v;
create temp table b127_without on commit drop as select pg_temp.flows127() as v;
do $$
declare v_with jsonb := (select v from b127_with); v_without jsonb := (select v from b127_without); k text;
begin
    if v_with is null or v_with -> 'books' is null or jsonb_typeof(v_with -> 'books') <> 'object' then
        raise exception 'FAIL: the flows left no books: %', v_with;
    end if;
    for k in select jsonb_object_keys(v_with) union select jsonb_object_keys(v_without) loop
        if (v_with -> k) is distinct from (v_without -> k) then
            raise exception 'FAIL: P1 — % differs: with 127 % / without %', k, v_with -> k, v_without -> k;
        end if;
    end loop;
    if (v_with ->> 'invitations')::int < 3 or v_with ->> 'street' <> 'true'
       or v_with -> 'orders' ->> 0 not like '% delivered' then
        raise exception 'FAIL: the flows did not all go through: %', v_with;
    end if;
    raise notice 'PASS: P1 — % answers identical with and without 127''s guards (books of a shop, a farm and an association, the team, the invitations claimed, photos, logo, the street, orders, debts, invoices, sales, stock, notices)',
        (select count(*) from jsonb_object_keys(v_with));
end $$;
rollback;

\echo '=== test_batch127.sql: all claims hold ==='
