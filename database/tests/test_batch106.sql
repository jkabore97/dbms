-- ============================================================
-- test_batch106.sql — the fiche entreprise (106).
--
-- The claims, for a shop, a farm and an association alike:
--   * the Aperçu answers the platform only, and says the owner, the kind,
--     the plan, the cauris, the members and what wants attention;
--   * the Identité is changed by the platform only; the kind only with the
--     business's name typed back (and the new kind finds its accounts);
--     each change is one journal line, before and after, with its undo,
--     and the owner is told « Mara a modifié … »;
--   * the undo puts back exactly what Mara changed, once, and never over
--     a change somebody made since; the owner is told it was taken back;
--   * Mara's hand on a vitrine, through the owner's own functions, is
--     logged and undoable, and the owner told once per editing session —
--     not when the owner edits, not when Mara is a member, not when
--     nothing moved; a plan the platform sets is logged and undoable;
--   * P3: nobody but the platform reads the fiche or runs its undo, and
--     no client writes the journal;
--   * P1: installing 106 again changes nothing a business or its vitrine
--     shows.
-- ============================================================
\set ON_ERROR_STOP on

\set o_shop  '''10606060-0000-0000-0000-000000000001'''
\set o_farm  '''10606060-0000-0000-0000-000000000002'''
\set o_assoc '''10606060-0000-0000-0000-000000000003'''
\set s_admin '''10606060-0000-0000-0000-000000000004'''
\set mara    '''10606060-0000-0000-0000-000000000005'''
\set mara_m  '''10606060-0000-0000-0000-000000000006'''
\set shop    '''10600000-0000-0000-0000-000000000001'''
\set farm    '''10600000-0000-0000-0000-000000000002'''
\set assoc   '''10600000-0000-0000-0000-000000000003'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
-- Earlier suites hand the app's roles every function and table: 106 again,
-- so what follows tests its own doors.
\i database/migrations/106_business_fiche.sql

insert into auth.users (id, phone, email, raw_user_meta_data) values
    (:o_shop,  '+22610600001', 'awa106@example.com', '{"full_name": "Awa Boutique"}'),
    (:o_farm,  '+22610600002', null,                 '{"full_name": "Issa Ferme"}'),
    (:o_assoc, '+22610600003', null,                 '{"full_name": "Mariam Entraide"}'),
    (:s_admin, '+22610600004', null,                 '{"full_name": "Adjoint"}'),
    (:mara,    '+22610600005', null,                 '{"full_name": "Mara Une"}'),
    (:mara_m,  '+22610600006', null,                 '{"full_name": "Mara Membre"}');
update profiles set is_platform_admin = true where id in (:mara, :mara_m);
insert into orgs (id, name, slug, profile, default_currency, phone, address) values
    (:shop,  'Boutique 106', 'boutique-106', 'retail',      'XOF', '+22670000106', 'Marché central'),
    (:farm,  'Ferme 106',    'ferme-106',    'farm',        'XOF', null, null),
    (:assoc, 'Entraide 106', 'entraide-106', 'association', 'XOF', null, null);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :o_shop,  'owner',    'org', :shop,  'full'),
    (:shop,  :s_admin, 'admin',    'org', :shop,  'full'),
    -- A platform admin who is also a member of the shop.
    (:shop,  :mara_m,  'employee', 'org', :shop,  'full'),
    (:farm,  :o_farm,  'owner',    'org', :farm,  'full'),
    (:assoc, :o_assoc, 'owner',    'org', :assoc, 'full');
insert into auth.sessions (user_id) values (:mara), (:mara_m), (:o_shop);
-- « J'ai payé » waiting for the shop.
insert into plan_requests (org_id, user_id, amount, note) values (:shop, :o_shop, 5000, 'Wave');

\echo ''
\echo '--- TEST 1: the Aperçu is the platform''s, and says who, what, how much, what waits ---'
begin;
set local role authenticated;
do $$
begin
    perform set_config('request.jwt.claim.sub', '10606060-0000-0000-0000-000000000001', true);
    begin
        perform platform_org_overview('10600000-0000-0000-0000-000000000001');
        raise exception 'FAIL: an owner read the platform''s fiche';
    exception when raise_exception then
        if sqlerrm <> 'Réservé à l''équipe Mara' then raise; end if;
    end;
    perform set_config('request.jwt.claim.sub', '10606060-0000-0000-0000-000000000004', true);
    begin
        perform platform_org_overview('10600000-0000-0000-0000-000000000001');
        raise exception 'FAIL: an admin of the shop read the platform''s fiche';
    exception when raise_exception then
        if sqlerrm <> 'Réservé à l''équipe Mara' then raise; end if;
    end;
end $$;
do $$
declare
    r  record;
    v  jsonb;
begin
    perform set_config('request.jwt.claim.sub', '10606060-0000-0000-0000-000000000005', true);
    for r in select * from (values
        ('10600000-0000-0000-0000-000000000001'::uuid, 'retail',      'Awa Boutique',    3),
        ('10600000-0000-0000-0000-000000000002'::uuid, 'farm',        'Issa Ferme',      1),
        ('10600000-0000-0000-0000-000000000003'::uuid, 'association', 'Mariam Entraide', 1)) x(org, kind, owner, members)
    loop
        v := platform_org_overview(r.org);
        if v->>'profile' <> r.kind or v->'owner'->>'name' <> r.owner
           or (v->>'members')::int <> r.members
           or v->>'plan' <> 'free' or (v->>'cauris')::int <> 0
           or v->>'health' <> 'never'
           or jsonb_typeof(v->'alerts') <> 'array' or jsonb_typeof(v->'unlocks') <> 'array' then
            raise exception 'FAIL: the Aperçu of a % reads %', r.kind, v;
        end if;
    end loop;
    v := platform_org_overview('10600000-0000-0000-0000-000000000001');
    if v->'owner'->>'phone' <> '+22610600001' or v->'owner'->>'email' <> 'awa106@example.com'
       or v->>'phone' <> '+22670000106'
       or not exists (select 1 from jsonb_array_elements(v->'alerts') a
                       where a->>'kind' = 'paid_claim' and (a->>'n')::int = 1)
       or not exists (select 1 from jsonb_array_elements(v->'alerts') a where a->>'kind' = 'never') then
        raise exception 'FAIL: the shop''s owner line or its alerts: %', v;
    end if;
    raise notice 'PASS: the Aperçu refuses an owner and an admin; for a shop, a farm and an association it says the owner, the kind, the plan, the cauris, the members, « J''ai payé » waiting';
end $$;
rollback;
do $$ begin
    if has_function_privilege('anon', 'platform_org_overview(uuid)', 'EXECUTE')
       or has_function_privilege('anon', 'platform_update_org_identity(uuid, text, text, text, text, text, text, boolean, text)', 'EXECUTE') then
        raise exception 'FAIL: the street may call the fiche';
    end if;
    raise notice 'PASS: the street calls neither the Aperçu nor the Identité';
end $$;

\echo ''
\echo '--- TEST 2: the Identité — the platform''s, the kind with the name typed, each change logged, the owner told ---'
set role authenticated;
select set_config('request.jwt.claim.sub', :o_shop, false);
do $$ begin
    begin
        perform platform_update_org_identity('10600000-0000-0000-0000-000000000001', p_name => 'À moi');
        raise exception 'FAIL: an owner used the platform''s Identité';
    exception when raise_exception then
        if sqlerrm <> 'Réservé à l''équipe Mara' then raise; end if;
    end;
    raise notice 'PASS: an owner cannot use the platform''s Identité';
end $$;
select set_config('request.jwt.claim.sub', :mara, false);
do $$ begin
    begin
        perform platform_update_org_identity('10600000-0000-0000-0000-000000000001', p_profile => 'farm');
        raise exception 'FAIL: the kind changed without the name typed';
    exception when raise_exception then
        if sqlerrm <> 'Pour changer le type d''activité, tapez le nom de l''activité : Boutique 106' then raise; end if;
    end;
    begin
        perform platform_update_org_identity('10600000-0000-0000-0000-000000000001',
            p_profile => 'farm', p_confirm => 'Boutique 10');
        raise exception 'FAIL: the kind changed with the wrong name';
    exception when raise_exception then
        if sqlerrm not like 'Pour changer le type d''activité%' then raise; end if;
    end;
    begin
        perform platform_update_org_identity('10600000-0000-0000-0000-000000000001', p_slug => 'ferme-106');
        raise exception 'FAIL: another business''s address was taken';
    exception when raise_exception then
        if sqlerrm <> 'Cette adresse est déjà prise' then raise; end if;
    end;
    begin
        perform platform_update_org_identity('10600000-0000-0000-0000-000000000001', p_verified => true);
        raise exception 'FAIL: a shop was verified';
    exception when raise_exception then
        if sqlerrm <> 'La vérification par Mara concerne les associations' then raise; end if;
    end;
    begin
        perform platform_update_org_identity('10600000-0000-0000-0000-000000000001', p_name => '  ');
        raise exception 'FAIL: the name was emptied';
    exception when raise_exception then
        if sqlerrm <> 'Le nom de l''activité ne peut pas être vide' then raise; end if;
    end;
    raise notice 'PASS: the kind needs the name typed back; a taken address, a shop verified, an empty name are refused';
end $$;
-- The shop becomes a farm (the name typed in any case), its phone cleared.
select platform_update_org_identity(:shop, p_profile => 'farm', p_phone => '',
                                    p_confirm => '  boutique 106 ') as kind_action \gset
-- Nothing moved: no line.
select platform_update_org_identity(:farm, p_name => 'Ferme 106', p_currency => 'xof') is null as nothing \gset
-- The association verified, and its address set.
select platform_update_org_identity(:assoc, p_verified => true, p_address => 'Quartier 106') as assoc_action \gset
reset role;
select id as assoc_identity from platform_actions where org_id = :assoc and kind = 'identity' \gset
do $$
declare
    a platform_actions%rowtype;
    n int;
begin
    if (select profile from orgs where id = '10600000-0000-0000-0000-000000000001') <> 'farm'
       or (select phone from orgs where id = '10600000-0000-0000-0000-000000000001') is not null then
        raise exception 'FAIL: the shop''s kind or phone did not change';
    end if;
    -- The new kind's chart of accounts is there; the old one is kept.
    if (select count(*) from accounts where org_id = '10600000-0000-0000-0000-000000000001') = 0 then
        raise exception 'FAIL: the new kind found no accounts';
    end if;
    select * into a from platform_actions
     where org_id = '10600000-0000-0000-0000-000000000001' and kind = 'identity';
    if a.actor <> '10606060-0000-0000-0000-000000000005'
       or a.before <> '{"profile": "retail", "phone": "+22670000106"}'::jsonb
       or a.after  <> '{"profile": "farm", "phone": null}'::jsonb
       or a.undo_fn <> 'platform_undo_org_columns'
       or a.summary <> 'Identité : type d''activité, téléphone' then
        raise exception 'FAIL: the kind''s line reads % / % / % / %', a.before, a.after, a.undo_fn, a.summary;
    end if;
    select count(*) into n from notifications
     where recipient_id = '10606060-0000-0000-0000-000000000001' and kind = 'mara_edited'
       and params->>'what' = 'identity' and params->>'action' = a.id::text
       and message = 'Mara a modifié l''identité de votre activité : type d''activité, téléphone';
    if n <> 1 then
        raise exception 'FAIL: the owner was told % times', n;
    end if;
    -- Neither the admin nor Mara's member hears it: the owner is told.
    if exists (select 1 from notifications where kind = 'mara_edited'
                 and recipient_id in ('10606060-0000-0000-0000-000000000004',
                                      '10606060-0000-0000-0000-000000000006')) then
        raise exception 'FAIL: somebody other than the owner was told';
    end if;
    if (select count(*) from platform_actions where org_id = '10600000-0000-0000-0000-000000000002') <> 0 then
        raise exception 'FAIL: a change that moved nothing was logged';
    end if;
    if (select verified_at from orgs where id = '10600000-0000-0000-0000-000000000003') is null
       or (select verified_by from orgs where id = '10600000-0000-0000-0000-000000000003')
          <> '10606060-0000-0000-0000-000000000005' then
        raise exception 'FAIL: the association is not verified by Mara';
    end if;
    raise notice 'PASS: a shop made a farm with its name typed (its accounts seeded), its phone cleared, one line before/after, the owner told once; nothing moved, nothing logged; an association verified';
end $$;
\if :nothing
\else
    \echo 'FAIL: a change that moved nothing returned a line'
    select 1/0;
\endif

\echo ''
\echo '--- TEST 3: « Annuler » puts back what Mara changed, once, never over a later change ---'
set role authenticated;
select set_config('request.jwt.claim.sub', :o_shop, false);
select set_config('fiche.action', :'kind_action', false);
do $$ begin
    begin
        perform platform_undo(current_setting('fiche.action')::uuid);
        raise exception 'FAIL: an owner undid Mara''s line';
    exception when raise_exception then
        if sqlerrm <> 'Réservé à la plateforme' then raise; end if;
    end;
    raise notice 'PASS: an owner cannot run the journal''s undo';
end $$;
select set_config('request.jwt.claim.sub', :mara, false);
select platform_undo(:'kind_action');
do $$ begin
    begin
        perform platform_undo(current_setting('fiche.action')::uuid);
        raise exception 'FAIL: one line undone twice';
    exception when raise_exception then
        if sqlerrm <> 'Cette action a déjà été annulée.' then raise; end if;
    end;
end $$;
-- The association's address, changed since by its owner: the undo is refused.
reset role;
select set_config('request.jwt.claim.sub', :o_assoc, false);
update orgs set address = 'Chez la trésorière' where id = :assoc;
select set_config('request.jwt.claim.sub', :mara, false);
set role authenticated;
select set_config('fiche.action', :'assoc_identity', false);
do $$ begin
    begin
        perform platform_undo(current_setting('fiche.action')::uuid);
        raise exception 'FAIL: the undo overwrote the owner''s later change';
    exception when raise_exception then
        if sqlerrm <> 'Annulation impossible : « adresse » a été modifié depuis' then raise; end if;
    end;
end $$;
reset role;
do $$ begin
    if (select profile from orgs where id = '10600000-0000-0000-0000-000000000001') <> 'retail'
       or (select phone from orgs where id = '10600000-0000-0000-0000-000000000001') <> '+22670000106' then
        raise exception 'FAIL: the undo did not put the kind and the phone back';
    end if;
    if (select undone_by from platform_actions
         where org_id = '10600000-0000-0000-0000-000000000001' and kind = 'identity')
       <> '10606060-0000-0000-0000-000000000005' then
        raise exception 'FAIL: the line is not marked undone';
    end if;
    -- The undo itself is no new line (the trigger stood aside).
    if (select count(*) from platform_actions where org_id = '10600000-0000-0000-0000-000000000001') <> 1 then
        raise exception 'FAIL: the undo wrote a line of its own';
    end if;
    if (select count(*) from notifications
         where recipient_id = '10606060-0000-0000-0000-000000000001' and kind = 'mara_undone'
           and message = 'Mara a annulé sa modification de l''identité de votre activité') <> 1 then
        raise exception 'FAIL: the owner was not told of the undo';
    end if;
    if (select address from orgs where id = '10600000-0000-0000-0000-000000000003') <> 'Chez la trésorière'
       or (select undone_at from platform_actions
            where org_id = '10600000-0000-0000-0000-000000000003' and kind = 'identity') is not null then
        raise exception 'FAIL: a refused undo moved something';
    end if;
    raise notice 'PASS: the undo puts the kind and phone back, once, writes no line of its own, tells the owner; refused over an owner''s later change';
end $$;
select set_config('request.jwt.claim.sub', '', false);
update orgs set address = 'Quartier 106' where id = :assoc;

\echo ''
\echo '--- TEST 4: Mara''s hand on a vitrine — logged, one line per session, the owner told once, undoable ---'
-- Each statement its own transaction, as the app's calls are.
set role authenticated;
select set_config('request.jwt.claim.sub', :mara, false);
select set_storefront(:shop, true, 'Bienvenue chez Awa');
select set_storefront_location(:shop, 12.3714, -1.5197);
select set_org_theme(:shop, 'indigo');
-- Saved again as it is (the settings form sends everything back): nothing.
select set_storefront_location(:shop, 12.3714, -1.5197);
select set_delivery_rates(:shop, null, null);
-- The farm and the association, through the owner's own doors too.
select set_storefront(:farm, true, 'Œufs frais');
select set_storefront(:assoc, true, 'Entraide du quartier');
reset role;
do $$
declare
    a platform_actions%rowtype;
    r record;
begin
    if (select count(*) from platform_actions
         where org_id = '10600000-0000-0000-0000-000000000001' and kind = 'vitrine') <> 1 then
        raise exception 'FAIL: one editing session made % lines',
            (select count(*) from platform_actions
              where org_id = '10600000-0000-0000-0000-000000000001' and kind = 'vitrine');
    end if;
    select * into a from platform_actions
     where org_id = '10600000-0000-0000-0000-000000000001' and kind = 'vitrine';
    if a.before <> '{"storefront_enabled": false, "storefront_blurb": null, "lat": null, "lng": null, "theme": null}'::jsonb
       or a.after <> '{"storefront_enabled": true, "storefront_blurb": "Bienvenue chez Awa", "lat": 12.3714, "lng": -1.5197, "theme": "indigo"}'::jsonb
       or a.summary <> 'Vitrine : ouverture, présentation, couleurs, position' then
        raise exception 'FAIL: the session''s line reads % → % (%)', a.before, a.after, a.summary;
    end if;
    if (select count(*) from notifications
         where recipient_id = '10606060-0000-0000-0000-000000000001' and kind = 'mara_edited'
           and params->>'what' = 'vitrine' and message = 'Mara a modifié votre vitrine') <> 1 then
        raise exception 'FAIL: the owner was not told exactly once';
    end if;
    for r in select * from (values
        ('10600000-0000-0000-0000-000000000002'::uuid, '10606060-0000-0000-0000-000000000002'::uuid),
        ('10600000-0000-0000-0000-000000000003'::uuid, '10606060-0000-0000-0000-000000000003'::uuid)) x(org, owner)
    loop
        if (select count(*) from platform_actions where org_id = r.org and kind = 'vitrine'
              and after ? 'storefront_blurb') <> 1
           or (select count(*) from notifications where recipient_id = r.owner
                 and kind = 'mara_edited' and params->>'what' = 'vitrine') <> 1 then
            raise exception 'FAIL: the vitrine of % was not logged and told', r.org;
        end if;
    end loop;
    raise notice 'PASS: Mara''s vitrine edits of a shop, a farm, an association are logged; one session is one line (before kept, after brought forward), the owner told once; a save that moves nothing writes nothing';
end $$;
-- The owner edits, and Mara's member edits: neither is Mara's hand on a stranger's vitrine.
set role authenticated;
select set_config('request.jwt.claim.sub', :o_shop, false);
select set_storefront(:shop, true, 'Bienvenue chez Awa !');
select set_config('request.jwt.claim.sub', :mara_m, false);
select set_storefront(:shop, true, 'Bienvenue chez Awa, encore');
reset role;
do $$ begin
    if (select count(*) from platform_actions
         where org_id = '10600000-0000-0000-0000-000000000001' and kind = 'vitrine') <> 1 then
        raise exception 'FAIL: an owner''s or a member''s edit was logged as Mara''s';
    end if;
    raise notice 'PASS: the owner''s own edit and a member of Mara''s team inside the shop are not logged';
end $$;
-- The farm's undo: back as it was.
select id as farm_vitrine from platform_actions where org_id = :farm and kind = 'vitrine' \gset
select id as shop_vitrine from platform_actions where org_id = :shop and kind = 'vitrine' \gset
set role authenticated;
select set_config('request.jwt.claim.sub', :mara, false);
select platform_undo(:'farm_vitrine');
-- After an undo, a new edit opens a new line.
select set_storefront(:farm, false, 'Œufs frais');
-- The shop's line is refused: the owner changed the text since.
select set_config('fiche.action', :'shop_vitrine', false);
do $$ begin
    begin
        perform platform_undo(current_setting('fiche.action')::uuid);
        raise exception 'FAIL: the vitrine''s undo overwrote the owner''s text';
    exception when raise_exception then
        if sqlerrm <> 'Annulation impossible : « présentation » a été modifié depuis' then raise; end if;
    end;
end $$;
reset role;
do $$ begin
    -- Put back to closed and blank: the new line starts from there.
    if (select storefront_enabled from orgs where id = '10600000-0000-0000-0000-000000000002')
       or (select before from platform_actions
            where org_id = '10600000-0000-0000-0000-000000000002' and kind = 'vitrine'
              and undone_at is null) <> '{"storefront_blurb": null}'::jsonb then
        raise exception 'FAIL: the farm''s vitrine was not put back';
    end if;
    if (select count(*) from platform_actions
         where org_id = '10600000-0000-0000-0000-000000000002' and kind = 'vitrine') <> 2
       or (select count(*) from platform_actions
            where org_id = '10600000-0000-0000-0000-000000000002' and kind = 'vitrine'
              and undone_at is null) <> 1 then
        raise exception 'FAIL: after an undo, a new edit did not open a new line';
    end if;
    if (select count(*) from notifications where recipient_id = '10606060-0000-0000-0000-000000000002'
          and kind = 'mara_undone' and message = 'Mara a annulé sa modification de votre vitrine') <> 1 then
        raise exception 'FAIL: the farmer was not told of the undo';
    end if;
    raise notice 'PASS: the farm''s vitrine put back and its owner told; a new edit after an undo is a new line; the shop''s undo refused over the owner''s text';
end $$;

\echo ''
\echo '--- TEST 5: the old doors — update_org and set_org_plan by Mara are logged, undoable ---'
set role authenticated;
select set_config('request.jwt.claim.sub', :mara, false);
select update_org(:farm, p_name => 'Ferme 106 bis');
select set_org_plan(:farm, 'pro', '2099-12-31', 'Offert');
reset role;
do $$
declare a platform_actions%rowtype;
begin
    select * into a from platform_actions
     where org_id = '10600000-0000-0000-0000-000000000002' and kind = 'identity';
    if a.after <> '{"name": "Ferme 106 bis"}'::jsonb or a.undo_fn <> 'platform_undo_org_columns' then
        raise exception 'FAIL: update_org by Mara reads %', a.after;
    end if;
    select * into a from platform_actions
     where org_id = '10600000-0000-0000-0000-000000000002' and kind = 'plan';
    if a.summary <> 'Formule : Mara Pro jusqu''au 31/12/2099'
       or a.before <> '{"plan": "free", "plan_until": null, "plan_note": null}'::jsonb then
        raise exception 'FAIL: the plan''s line reads % (%)', a.summary, a.before;
    end if;
    -- The plan is the platform's: no bell for it.
    if exists (select 1 from notifications where recipient_id = '10606060-0000-0000-0000-000000000002'
                 and kind = 'mara_edited' and params->>'what' = 'plan') then
        raise exception 'FAIL: a plan rang the owner''s bell';
    end if;
end $$;
select id as farm_plan from platform_actions where org_id = :farm and kind = 'plan' \gset
select id as farm_name from platform_actions where org_id = :farm and kind = 'identity' \gset
set role authenticated;
select platform_undo(:'farm_plan');
select platform_undo(:'farm_name');
reset role;
do $$ begin
    if (select plan from orgs where id = '10600000-0000-0000-0000-000000000002') <> 'free'
       or (select plan_until from orgs where id = '10600000-0000-0000-0000-000000000002') is not null
       or (select name from orgs where id = '10600000-0000-0000-0000-000000000002') <> 'Ferme 106' then
        raise exception 'FAIL: the plan or the name was not put back';
    end if;
    raise notice 'PASS: the old console''s rename and set_org_plan by Mara are logged and undone; the plan rings no bell';
end $$;

\echo ''
\echo '--- TEST 5b: an editing session the owner broke into is two lines; a kind changed through update_org rings one bell ---'
-- Mara A→B (the association's open line), the owner B→C, Mara C→D.
set role authenticated;
select set_config('request.jwt.claim.sub', :mara, false);
select set_storefront(:assoc, true, 'Texte B');
select set_config('request.jwt.claim.sub', :o_assoc, false);
select set_storefront(:assoc, true, 'Texte C');
select set_config('request.jwt.claim.sub', :mara, false);
select set_storefront(:assoc, true, 'Texte D');
reset role;
do $$
declare a platform_actions%rowtype;
begin
    if (select count(*) from platform_actions
         where org_id = '10600000-0000-0000-0000-000000000003' and kind = 'vitrine' and undone_at is null) <> 2 then
        raise exception 'FAIL: Mara''s edit after the owner''s was folded into the line before it';
    end if;
    select * into a from platform_actions
     where org_id = '10600000-0000-0000-0000-000000000003' and kind = 'vitrine'
     order by at desc, id desc limit 1;
    if a.before <> '{"storefront_blurb": "Texte C"}'::jsonb or a.after <> '{"storefront_blurb": "Texte D"}'::jsonb then
        raise exception 'FAIL: the new line reads % → %', a.before, a.after;
    end if;
    perform set_config('fiche.action', a.id::text, false);
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', :mara, false);
select platform_undo(current_setting('fiche.action')::uuid);
reset role;
do $$ begin
    if (select storefront_blurb from orgs where id = '10600000-0000-0000-0000-000000000003') <> 'Texte C' then
        raise exception 'FAIL: the undo did not give back the owner''s text: %',
            (select storefront_blurb from orgs where id = '10600000-0000-0000-0000-000000000003');
    end if;
    raise notice 'PASS: Mara A→B, the owner B→C, Mara C→D: two lines; the last undone gives the owner''s C';
end $$;
-- The kind, through 103's update_org (the owner's settings opened as Mara).
select set_config('fiche.bells', count(*)::text, false) from notifications
 where recipient_id = :o_farm and kind in ('org_kind_changed', 'mara_edited');
set role authenticated;
select set_config('request.jwt.claim.sub', :mara, false);
select update_org(:farm, p_profile => 'retail');
reset role;
do $$ begin
    if (select count(*) from notifications
         where recipient_id = '10606060-0000-0000-0000-000000000002'
           and kind in ('org_kind_changed', 'mara_edited')) <> current_setting('fiche.bells')::int + 1
       or not exists (select 1 from notifications
                       where recipient_id = '10606060-0000-0000-0000-000000000002'
                         and kind = 'org_kind_changed' and params->>'profile' = 'retail') then
        raise exception 'FAIL: a kind changed through update_org rang % bells',
            (select count(*) from notifications
              where recipient_id = '10606060-0000-0000-0000-000000000002'
                and kind in ('org_kind_changed', 'mara_edited')) - current_setting('fiche.bells')::int;
    end if;
    if not exists (select 1 from platform_actions
                    where org_id = '10600000-0000-0000-0000-000000000002' and kind = 'identity'
                      and undone_at is null and after = '{"profile": "retail"}'::jsonb) then
        raise exception 'FAIL: the kind change is not in the journal';
    end if;
    raise notice 'PASS: Mara changing a kind through update_org: one bell (103''s), the journal line still written';
end $$;
select id as farm_kind from platform_actions where org_id = :farm and kind = 'identity' and undone_at is null \gset
set role authenticated;
select set_config('request.jwt.claim.sub', :mara, false);
select platform_undo(:'farm_kind');
reset role;

\echo ''
\echo '--- TEST 6: P3 — the undo and the trigger are nobody''s to call; nobody writes the journal ---'
do $$ begin
    if has_function_privilege('authenticated', 'platform_undo_org_columns(jsonb)', 'EXECUTE')
       or has_function_privilege('anon', 'platform_undo_org_columns(jsonb)', 'EXECUTE')
       or has_function_privilege('authenticated', 'trg_orgs_mara_edit()', 'EXECUTE') then
        raise exception 'FAIL: the undo or the trigger is callable by the app''s roles';
    end if;
    if not exists (select 1 from platform_undo_fns where fn = 'platform_undo_org_columns') then
        raise exception 'FAIL: the undo is not on platform_undo''s list';
    end if;
end $$;
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :o_shop, true);
do $$ begin
    begin
        insert into platform_actions (actor, org_id, kind, summary, undo_fn, undo_args)
        values ('10606060-0000-0000-0000-000000000001', '10600000-0000-0000-0000-000000000001',
                'vitrine', 'faux', 'platform_undo_org_columns', '{}'::jsonb);
        raise exception 'FAIL: an owner wrote the journal';
    exception when insufficient_privilege then null;
    end;
    begin
        if exists (select 1 from platform_actions) then
            raise exception 'FAIL: an owner reads the journal';
        end if;
    exception when insufficient_privilege then null;
    end;
    raise notice 'PASS: the undo and the trigger are closed to the app''s roles; an owner neither writes nor reads the journal';
end $$;
rollback;
-- Even Mara, calling the undo with made-up arguments, moves only the fiche's columns.
begin;
select set_config('request.jwt.claim.sub', :mara, true);
do $$ begin
    begin
        perform platform_undo_org_columns(jsonb_build_object(
            'org', '10600000-0000-0000-0000-000000000001', 'what', 'vitrine',
            'before', '{"plan": "pro"}'::jsonb, 'after', '{"plan": "free"}'::jsonb));
        raise exception 'FAIL: the undo wrote a column outside its part';
    exception when raise_exception then
        if sqlerrm <> 'Rien à annuler' then raise; end if;
    end;
    raise notice 'PASS: the undo touches only the columns of its own part';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: P1 — installing 106 again changes nothing a business or a vitrine shows ---'
create temp table p1_mid as
select o.id, to_jsonb(o) - 'last_activity_at' as row,
       (select jsonb_agg(to_jsonb(v)) from storefront(o.slug) v) as vitrine,
       (select jsonb_agg(to_jsonb(p)) from storefront_products(o.slug) p) as shelf,
       feature_states(o.id) as states
  from orgs o where o.id in (:shop, :farm, :assoc);
\i database/migrations/106_business_fiche.sql
do $$ begin
    if exists (
        select 1 from p1_mid m join orgs o on o.id = m.id
         where (to_jsonb(o) - 'last_activity_at') is distinct from m.row
            or (select jsonb_agg(to_jsonb(v)) from storefront(o.slug) v) is distinct from m.vitrine
            or (select jsonb_agg(to_jsonb(p)) from storefront_products(o.slug) p) is distinct from m.shelf
            or feature_states(o.id) is distinct from m.states) then
        raise exception 'FAIL: installing 106 changed what a business shows';
    end if;
    raise notice 'PASS: for a shop, a farm and an association, installing 106 leaves the row, the vitrine and the feature states as they were';
end $$;

-- Leave the shared database as later suites expect it.
delete from notifications where org_id in (:shop, :farm, :assoc);
delete from platform_actions where org_id in (:shop, :farm, :assoc);
delete from plan_requests where org_id = :shop;
