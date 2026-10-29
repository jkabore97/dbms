-- ============================================================
-- test_batch151.sql — 151: the welcome gift of cauris.
--
-- The claims:
--   1. installed twice, the same: cauris_welcome_give and org_create_core
--      SECURITY DEFINER with their search path pinned and nobody's to call
--      (PUBLIC, anon, authenticated) — internal, as 142 left
--      org_create_core;
--   2. a new shop gets the gift as it is born (org_create_core, the door of
--      111's create_my_business and of create_org): a promotion of
--      5 000 cauris (left 5 000, until today + 120), its 'promo' ledger
--      line, the wallet at 5 000, « Mes cauris » showing the promotion and
--      its date, the owner's bell (« cauris_promo », « Marakaj Pro 3 mois »);
--   3. a farm and an association get it too, each for its own person;
--   4. once per person: the same person's second business gets nothing, and
--      deleting the first keeps the record (org_id null) so a third gets
--      nothing either;
--   5. no gift: a showcase vitrine, an owner added to an existing business
--      (a transfer), an employee joining, the platform's switch at 0;
--   6. the gift spends as cauris do: Mara Pro complet three times
--      (3 × 1 500, ninety days end to end), the promotion going down to
--      500, a fourth refused;
--   7. nothing for a business born before 151 (no row is backfilled).
-- Names: Ouagadougou, « Boutique Awa », « Ferme Kossi », « Association
-- Wend Panga ». Wrapped in one transaction rolled back: runs twice the same.
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
\i database/migrations/151_welcome_cauris.sql
\i database/migrations/151_welcome_cauris.sql

begin;

-- 1. installed twice, the same
do $$
declare
    f text;
begin
    foreach f in array array['cauris_welcome_give(uuid, uuid)', 'org_create_core(uuid, text, text, text, text)'] loop
        assert (select prosecdef from pg_proc where oid = to_regprocedure(f)), f || ' is SECURITY DEFINER';
        assert (select proconfig::text like '%search_path=public%' from pg_proc where oid = to_regprocedure(f)),
            f || ' pins its search path';
        assert not has_function_privilege('anon', f, 'execute'), 'anon cannot call ' || f;
        assert not has_function_privilege('authenticated', f, 'execute'), 'authenticated cannot call ' || f;
        assert not has_function_privilege('public', f, 'execute'), 'PUBLIC cannot call ' || f;
    end loop;
    assert (select value #>> '{}' from platform_settings where key = 'cauris_welcome_points') = '5000',
        'the gift is 5 000 by default';
    assert (select value #>> '{}' from platform_settings where key = 'cauris_welcome_days') = '120',
        'to spend within 120 days by default';
    assert (select relrowsecurity from pg_class where relname = 'cauris_welcomes'),
        'cauris_welcomes has row level security';
    assert not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                        where c.relname = 'memberships' and t.tgname like '%welcome%'),
        'no trigger: a membership written by hand gives nothing';
end $$;

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('15115115-0000-0000-0000-000000000001', '+22615110001', 'awa151@example.com',   '{"full_name": "Awa Traoré"}',     now() - interval '1 day'),
    ('15115115-0000-0000-0000-000000000002', '+22615110002', 'kossi151@example.com', '{"full_name": "Kossi Ouédraogo"}', now() - interval '1 day'),
    ('15115115-0000-0000-0000-000000000003', '+22615110003', 'wend151@example.com',  '{"full_name": "Salif Kaboré"}',   now() - interval '1 day'),
    ('15115115-0000-0000-0000-000000000004', '+22615110004', 'old151@example.com',   '{"full_name": "Ancien Gérant"}',  now() - interval '1 year'),
    ('15115115-0000-0000-0000-000000000005', '+22615110005', 'emp151@example.com',   '{"full_name": "La vendeuse"}',    now() - interval '1 day');

-- A business born before 151: an old shop, no gift backfilled.
insert into orgs (id, name, slug, profile, default_currency, created_at) values
    ('15151151-0000-0000-0000-000000000009', 'Vieille Boutique', 'vieille-boutique-151', 'retail', 'XOF', now() - interval '2 days');

-- 2. a new shop: its owner in, the gift
do $$
declare
    v_org uuid;
    p cauris_promos%rowtype;
    j jsonb;
begin
    v_org := org_create_core('15115115-0000-0000-0000-000000000001', 'Boutique Awa', 'boutique-awa-151', 'retail', 'XOF');
    select * into p from cauris_promos where org_id = v_org;
    assert found, 'a promotion for the new shop';
    assert p.points = 5000 and p.left_points = 5000, 'of 5 000 cauris, all left';
    assert p.expires_on = cauris_today() + 120, 'until today + 120';
    assert p.note = 'Cadeau de bienvenue', 'noted « Cadeau de bienvenue »';
    assert (select count(*) from cauris_ledger where org_id = v_org and reason = 'promo' and delta = 5000
              and ref = p.id::text) = 1, 'one promo ledger line of 5 000';
    assert cauris_balance(v_org) = 5000, 'the wallet holds 5 000';
    assert (select org_id from cauris_welcomes where user_id = '15115115-0000-0000-0000-000000000001') = v_org,
        'the person is recorded with the shop';
    assert exists (select 1 from notifications where recipient_id = '15115115-0000-0000-0000-000000000001'
                     and org_id = v_org and kind = 'cauris_promo'
                     and message like 'Bienvenue sur Marakaj ! Nous vous offrons 5000 cauris : de quoi ouvrir Marakaj Pro 3 mois, à utiliser avant le %'),
        'the owner''s bell says what the gift opens';
    perform set_config('request.jwt.claim.sub', '15115115-0000-0000-0000-000000000001', true);
    j := my_cauris(v_org);
    perform set_config('request.jwt.claim.sub', '', true);
    assert (j ->> 'balance')::int = 5000, '« Mes cauris » reads 5 000';
    assert j -> 'promo' is not null and j -> 'promo' <> 'null'::jsonb, '« Mes cauris » shows the promotion';
end $$;

-- 3. a farm and an association, each its own person
do $$
declare
    v_farm uuid;
    v_asso uuid;
begin
    v_farm := org_create_core('15115115-0000-0000-0000-000000000002', 'Ferme Kossi', 'ferme-kossi-151', 'farm', 'XOF');
    v_asso := org_create_core('15115115-0000-0000-0000-000000000003', 'Association Wend Panga', 'wend-panga-151', 'association', 'XOF');
    assert cauris_balance(v_farm) = 5000, 'the farm gets 5 000';
    assert cauris_balance(v_asso) = 5000, 'the association gets 5 000';
end $$;

-- 4. once per person
do $$
declare
    v_first  uuid := (select org_id from cauris_welcomes where user_id = '15115115-0000-0000-0000-000000000001');
    v_second uuid;
    v_third  uuid;
begin
    v_second := org_create_core('15115115-0000-0000-0000-000000000001', 'Boutique Awa 2', 'boutique-awa-2-151', 'retail', 'XOF');
    assert cauris_balance(v_second) = 0, 'a second business of the same person gets nothing';
    -- The record outlives the business: its link is « on delete set null »
    -- (a business's deletion is delete_org's, tested in test_org_lifecycle).
    assert (select confdeltype from pg_constraint
             where conrelid = 'cauris_welcomes'::regclass and contype = 'f'
               and confrelid = 'orgs'::regclass) = 'n',
        'the record stays when the business is deleted (org_id set null)';
    update cauris_welcomes set org_id = null where user_id = '15115115-0000-0000-0000-000000000001';
    v_third := org_create_core('15115115-0000-0000-0000-000000000001', 'Boutique Awa 3', 'boutique-awa-3-151', 'retail', 'XOF');
    assert cauris_balance(v_third) = 0, 'its business gone, a new one brings nothing';
    assert cauris_balance(v_first) = 5000, 'the first keeps its gift';
end $$;

-- 5. no gift
do $$
declare
    v_show uuid := '15151151-0000-0000-0000-000000000008';
    v_farm uuid := (select id from orgs where slug = 'ferme-kossi-151');
begin
    -- a showcase vitrine, even through the gift's own door
    insert into orgs (id, name, slug, profile, default_currency, showcase)
    values (v_show, 'Vitrine d''exemple', 'exemple-151', 'retail', 'XOF', true);
    assert cauris_welcome_give(v_show, '15115115-0000-0000-0000-000000000004') = 0, 'a showcase vitrine gets nothing';
    -- an owner added to an existing business (a transfer)
    insert into memberships (org_id, user_id, role, scope_kind, scope_id)
    values ('15151151-0000-0000-0000-000000000009', '15115115-0000-0000-0000-000000000005', 'owner', 'org',
            '15151151-0000-0000-0000-000000000009');
    -- an employee joining a new business
    insert into memberships (org_id, user_id, role, scope_kind, scope_id)
    values (v_farm, '15115115-0000-0000-0000-000000000004', 'employee', 'org', v_farm);
    assert cauris_balance(v_show) = 0, 'the showcase wallet stays at 0';
    assert cauris_balance('15151151-0000-0000-0000-000000000009') = 0, 'an owner added to an old business brings nothing';
    assert not exists (select 1 from cauris_welcomes where user_id in ('15115115-0000-0000-0000-000000000004',
                                                                      '15115115-0000-0000-0000-000000000005')),
        'nobody recorded for those';
    assert cauris_balance(v_farm) = 5000, 'an employee joining adds nothing';
end $$;

-- 5b. the platform's switch at 0
do $$
declare
    v_org uuid;
begin
    update platform_settings set value = '0' where key = 'cauris_welcome_points';
    v_org := org_create_core('15115115-0000-0000-0000-000000000004', 'Boutique Sans Cadeau', 'sans-cadeau-151', 'retail', 'XOF');
    assert cauris_balance(v_org) = 0, 'switched off: no gift';
    assert not exists (select 1 from cauris_welcomes where user_id = '15115115-0000-0000-0000-000000000004'),
        'switched off: nobody recorded';
    update platform_settings set value = '5000' where key = 'cauris_welcome_points';
end $$;

-- 6. spent as cauris are: Mara Pro complet three times
do $$
declare
    v_farm uuid := (select id from orgs where slug = 'ferme-kossi-151');
    ok boolean := false;
begin
    perform set_config('request.jwt.claim.sub', '15115115-0000-0000-0000-000000000002', true);
    perform spend_cauris(v_farm, 'pro_all');
    perform spend_cauris(v_farm, 'pro_all');
    perform spend_cauris(v_farm, 'pro_all');
    -- (a step of the path may add its own few cauris on the way: 097)
    assert cauris_balance(v_farm) between 500 and 600, '3 × 1 500 spent, about 500 left: ' || cauris_balance(v_farm);
    assert (select left_points from cauris_promos where org_id = v_farm) = 500, 'the promotion went down to 500';
    assert (select until from cauris_unlocks where org_id = v_farm and feature = 'pro_all') > now() + interval '89 days',
        'three months of Mara Pro complet, end to end';
    begin
        perform spend_cauris(v_farm, 'pro_all');
    exception when others then
        ok := true;
    end;
    perform set_config('request.jwt.claim.sub', '', true);
    assert ok, 'a fourth month is refused: 500 is not enough';
end $$;

-- 7. nothing backfilled
do $$ begin
    assert cauris_balance('15151151-0000-0000-0000-000000000009') = 0, 'a business born before 151 gets nothing';
end $$;

rollback;
\echo 'test_batch151: all claims hold'
