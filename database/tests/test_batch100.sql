-- ============================================================
-- test_batch100.sql — the team, the photos, the platform's gifts and the
-- stock rules (100). Phone block 69.
--
-- The claims: a Basic shop or farm adds no worker before its first setup
-- and one after it, an association one at once; the second is refused in
-- French, at the invitation and at the door (a direct insert, a code
-- claimed), with no one already there removed; a second grant, a trainer
-- and Mara's admins never take the seat; the team unlocked with cauris, or
-- Pro, opens it; the sign-in sweep skips what has no seat and claims the
-- rest. A member's salary is recorded free on their payroll row, read
-- back on the Équipe screen, refused to an employee; paying stays Pro.
-- A Basic business photographs 10 articles, the 11th refused unless a
-- slot is bought (50 cauris, permanent) — a second photo of an article
-- never counts, a capture with no article is not counted, Pro and a
-- showcase have no limit. An association spends what the platform gives
-- it and still earns nothing. A gift is a 'gift' line, promotional points
-- are spent first and taken out on their day, neither counts in the week
-- or the leagues; a tool given until a date opens with no cauris spent and
-- is not « mon premier outil »; each gift rings the admins with its facts,
-- and only the platform gives. my_orgs() names each business's owner.
-- A production corrected moves its output on the shelf, and its cost price
-- while it is still that batch's; a flock corrected cannot lose more birds
-- than it has; the till, a credit sale, a return, a delivery and its
-- reversal, a service and the low-stock bell move the stock as they always
-- have.
-- The corrections (12–17): paperwork filed on an article (a delivery note,
-- a receipt, a PDF) is no photo — not counted, never the vitrine's picture
-- nor served to the street, and under the general cap; an archived
-- photographed article coming back takes a place again; Pro buys no slot;
-- a salary is never a kind changed, a week's salary pays a week, clearing
-- revives nobody; no trainer, no owner and no moved row by the back door,
-- while the platform's own ways (assign_trainer, create_org, an application
-- approved, a showcase joined) still grant; gifts are out of Le Chemin's
-- week, a bought tool stays bought, and the team given says so.
-- ============================================================
\set ON_ERROR_STOP on
-- The owner's numbers: earlier suites change them for their own fixtures.
update platform_settings set value = '1'  where key = 'free_max_staff';
update platform_settings set value = '10' where key = 'free_photo_items';
update platform_settings set value = '50' where key = 'free_max_photos';
update platform_settings set value = '0'  where key = 'path_gates_open';
update platform_settings set value = '180' where key = 'cauris_expire_days';
update platform_settings set value = '30' where key = 'cauris_unlock_days';
update cauris_costs set cost = 400 where feature = 'team_access';
update cauris_costs set cost = 400 where feature = 'analytics';

\set boss    '''69696969-0000-0000-0000-000000000001'''
\set w1      '''69696969-0000-0000-0000-000000000002'''
\set w2      '''69696969-0000-0000-0000-000000000003'''
\set w3      '''69696969-0000-0000-0000-000000000004'''
\set treas   '''69696969-0000-0000-0000-000000000005'''
\set mara    '''69696969-0000-0000-0000-000000000006'''
\set farmer  '''69696969-0000-0000-0000-000000000007'''
\set trainer '''69696969-0000-0000-0000-000000000008'''
\set proboss '''69696969-0000-0000-0000-000000000009'''
\set shop    '''69000000-0000-0000-0000-000000000001'''
\set assoc   '''69000000-0000-0000-0000-000000000002'''
\set farm    '''69000000-0000-0000-0000-000000000003'''
\set prosh   '''69000000-0000-0000-0000-000000000004'''
\set show    '''69000000-0000-0000-0000-000000000005'''

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
-- Earlier suites re-apply older migrations over 100's functions, and 063
-- (test_least_privilege) re-grants every definer function: 100 again, so
-- what follows tests its own definitions and grants.
\i database/migrations/100_team_photos_gifts.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:boss,    '+22669000001', '{"full_name": "Patronne"}'),
    (:w1,      '+22669000002', '{"full_name": "Awa"}'),
    (:w2,      '+22669000003', '{"full_name": "Bintou"}'),
    (:w3,      '+22669000004', '{"full_name": "Coumba"}'),
    (:treas,   '+22669000005', '{"full_name": "Trésorière"}'),
    (:mara,    '+22669000006', '{"full_name": "Mara"}'),
    (:farmer,  '+22669000007', '{"full_name": "Fermier"}'),
    (:trainer, '+22669000008', '{"full_name": "Formatrice"}'),
    (:proboss, '+22669000009', '{"full_name": "Patron Pro"}');
update profiles set is_platform_admin = true where id = :mara;
update profiles set is_trainer = true where id = :trainer;
insert into orgs (id, name, slug, profile, default_currency, plan, progress_since, showcase) values
    (:shop,  'Boutique 69', 'boutique-69', 'retail',      'XOF', 'free', null, false),
    (:assoc, 'Entraide 69', 'entraide-69', 'association', 'XOF', 'free', null, false),
    (:farm,  'Ferme 69',    'ferme-69',    'farm',        'XOF', 'free', null, false),
    (:prosh, 'Pro 69',      'pro-69',      'retail',      'XOF', 'pro',  null, false),
    (:show,  'Vitrine 69',  'vitrine-69',  'retail',      'XOF', 'pro',  null, true);
-- A fixture's orgs carry no setup mark (091 marked only those already there).
update orgs set setup_done_at = null where id in (:shop, :farm, :prosh, :show);
select seed_retail_accounts(:prosh);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :boss,    'owner', 'org', :shop,  'full'),
    (:assoc, :treas,   'owner', 'org', :assoc, 'full'),
    (:farm,  :farmer,  'owner', 'org', :farm,  'full'),
    (:prosh, :proboss, 'owner', 'org', :prosh, 'full');

\echo ''
\echo '--- TEST 1: a shop and a farm add nobody before their setup; an association one person at once ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000001';
do $$
declare s jsonb := team_overview('69000000-0000-0000-0000-000000000001');
begin
    if (s -> 'seats' ->> 'free')::int <> 0 or (s -> 'seats' ->> 'open')::boolean
       or (s -> 'seats' ->> 'setup_done')::boolean then
        raise exception 'FAIL: a shop not set up is shown a free seat: %', s -> 'seats';
    end if;
    begin
        insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
        values ('69000000-0000-0000-0000-000000000001', '69696969-0000-0000-0000-000000000002',
                'employee', 'org', '69000000-0000-0000-0000-000000000001', 'full');
        raise exception 'FAIL: a worker joined a shop not set up';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : la personne offerte s''ouvre une fois la mise en route%' then raise; end if;
    end;
    begin
        insert into pending_invitations (org_id, role, scope_kind, scope_id, code, created_by)
        values ('69000000-0000-0000-0000-000000000001', 'employee', 'org',
                '69000000-0000-0000-0000-000000000001', 'TEAM-6900',
                '69696969-0000-0000-0000-000000000001');
        raise exception 'FAIL: an invitation was written with no seat';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : la personne offerte%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000007';
do $$ begin
    begin
        insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
        values ('69000000-0000-0000-0000-000000000003', '69696969-0000-0000-0000-000000000002',
                'employee', 'org', '69000000-0000-0000-0000-000000000003', 'full');
        raise exception 'FAIL: a worker joined a farm not set up';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : la personne offerte%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000005';
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
values ('69000000-0000-0000-0000-000000000002', '69696969-0000-0000-0000-000000000002',
        'employee', 'org', '69000000-0000-0000-0000-000000000002', 'full');
do $$ begin
    begin
        insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
        values ('69000000-0000-0000-0000-000000000002', '69696969-0000-0000-0000-000000000003',
                'admin', 'org', '69000000-0000-0000-0000-000000000002', 'full');
        raise exception 'FAIL: a second worker joined a Basic association';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : cette entreprise a déjà sa personne offerte%' then raise; end if;
    end;
    raise notice 'PASS: no seat before the setup (shop, farm); an association''s one seat, then the refusal';
end $$;
commit;

\echo ''
\echo '--- TEST 2: the setup done, one worker by a code; the second refused at the code and at the door ---'
update orgs set setup_done_at = now() where id in ('69000000-0000-0000-0000-000000000001',
                                                  '69000000-0000-0000-0000-000000000003');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000001';
insert into pending_invitations (org_id, role, scope_kind, scope_id, code, created_by)
values ('69000000-0000-0000-0000-000000000001', 'employee', 'org',
        '69000000-0000-0000-0000-000000000001', 'TEAM-6901',
        '69696969-0000-0000-0000-000000000001');
-- A second code while the seat is still free: written (the seat is taken
-- at the claim, not at the writing).
insert into pending_invitations (org_id, role, scope_kind, scope_id, code, created_by)
values ('69000000-0000-0000-0000-000000000001', 'employee', 'org',
        '69000000-0000-0000-0000-000000000001', 'TEAM-6902',
        '69696969-0000-0000-0000-000000000001');
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000002';
select claim_invitation('TEAM-6901');
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000003';
do $$ begin
    begin
        perform claim_invitation('TEAM-6902');
        raise exception 'FAIL: a second worker claimed a code';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : cette entreprise a déjà sa personne offerte%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000001';
do $$
declare s jsonb := team_overview('69000000-0000-0000-0000-000000000001');
begin
    if (s -> 'seats' ->> 'used')::int <> 1 or (s -> 'seats' ->> 'open')::boolean
       or jsonb_array_length(s -> 'members') <> 2
       or not (s -> 'members' -> 0 ->> 'owner')::boolean
       or jsonb_array_length(s -> 'invitations') <> 1 then
        raise exception 'FAIL: the Équipe screen does not read the team: %', s;
    end if;
    begin
        insert into pending_invitations (org_id, role, scope_kind, scope_id, code, created_by)
        values ('69000000-0000-0000-0000-000000000001', 'employee', 'org',
                '69000000-0000-0000-0000-000000000001', 'TEAM-6903',
                '69696969-0000-0000-0000-000000000001');
        raise exception 'FAIL: an invitation was written with the seat taken';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : cette entreprise a déjà%' then raise; end if;
    end;
    begin
        insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
        values ('69000000-0000-0000-0000-000000000001', '69696969-0000-0000-0000-000000000004',
                'employee', 'org', '69000000-0000-0000-0000-000000000001', 'full');
        raise exception 'FAIL: a second worker was added directly';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : cette entreprise a déjà%' then raise; end if;
    end;
    -- The same person, a second grant: nobody new.
    insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
    values ('69000000-0000-0000-0000-000000000001', '69696969-0000-0000-0000-000000000002',
            'admin', 'org', '69000000-0000-0000-0000-000000000001', 'full');
    raise notice 'PASS: one worker by a code; the second refused at the claim, the invitation and the insert; a second grant passes';
end $$;
commit;

\echo ''
\echo '--- TEST 3: a trainer and Mara''s admin take no seat; nobody is removed; the team unlocked opens it ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000006';
select assign_trainer('69000000-0000-0000-0000-000000000001', '69696969-0000-0000-0000-000000000008');
-- Over the limit by the platform's hand (or before 100): kept.
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
values ('69000000-0000-0000-0000-000000000001', '69696969-0000-0000-0000-000000000004',
        'employee', 'org', '69000000-0000-0000-0000-000000000001', 'full');
commit;
do $$ begin
    if org_workers('69000000-0000-0000-0000-000000000001') <> 2 then
        raise exception 'FAIL: the trainer counted, or a worker went: %',
            org_workers('69000000-0000-0000-0000-000000000001');
    end if;
end $$;
insert into cauris_unlocks (org_id, feature, until)
values ('69000000-0000-0000-0000-000000000001', 'team_access', now() + interval '30 days');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000003';
select claim_invitation('TEAM-6902');
commit;
do $$ begin
    if org_workers('69000000-0000-0000-0000-000000000001') <> 3 then
        raise exception 'FAIL: the team unlocked did not open a third seat';
    end if;
    raise notice 'PASS: a trainer and Mara''s admin take no seat, nobody is removed, team_access opens it';
end $$;

\echo ''
\echo '--- TEST 4: the sign-in sweep skips what has no seat and claims the rest ---'
update auth.users set phone = '+22669000099' where id = '69696969-0000-0000-0000-000000000004';
update profiles set phone = '+22669000099' where id = '69696969-0000-0000-0000-000000000004';
insert into pending_invitations (org_id, role, scope_kind, scope_id, code, phone, created_by)
values ('69000000-0000-0000-0000-000000000002', 'employee', 'org',
        '69000000-0000-0000-0000-000000000002', 'TEAM-6904', '+22669000099',
        '69696969-0000-0000-0000-000000000005'),
       ('69000000-0000-0000-0000-000000000004', 'employee', 'org',
        '69000000-0000-0000-0000-000000000004', 'TEAM-6905', '+22669000099',
        '69696969-0000-0000-0000-000000000009');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000004';
do $$
declare n int := claim_my_invitations();
begin
    if n <> 1
       or not exists (select 1 from memberships where org_id = '69000000-0000-0000-0000-000000000004'
                       and user_id = '69696969-0000-0000-0000-000000000004')
       or exists (select 1 from memberships where org_id = '69000000-0000-0000-0000-000000000002'
                   and user_id = '69696969-0000-0000-0000-000000000004') then
        raise exception 'FAIL: the sweep claimed % (the association''s should wait, the Pro shop''s go)', n;
    end if;
    raise notice 'PASS: the full association''s invitation waits, the Pro shop''s is claimed';
end $$;
commit;

\echo ''
\echo '--- TEST 5: a salary is recorded free, per month, week or day; paying stays Pro ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000001';
do $$
declare
    v_id uuid;
    s    jsonb;
    m    jsonb;
begin
    v_id := set_member_salary('69000000-0000-0000-0000-000000000001',
                              '69696969-0000-0000-0000-000000000002', 45000, 'month');
    perform set_member_salary('69000000-0000-0000-0000-000000000001',
                              '69696969-0000-0000-0000-000000000003', 2500, 'day');
    s := team_overview('69000000-0000-0000-0000-000000000001');
    select x into m from jsonb_array_elements(s -> 'members') x
     where x ->> 'user_id' = '69696969-0000-0000-0000-000000000002';
    if (m ->> 'salary')::numeric <> 45000 or m ->> 'period' <> 'month'
       or (m ->> 'employee_id')::uuid <> v_id then
        raise exception 'FAIL: Awa''s salary is not on the screen: %', m;
    end if;
    if (select user_id from employees where id = v_id) <> '69696969-0000-0000-0000-000000000002'
       or (select kind from employees where id = v_id) <> 'permanent' then
        raise exception 'FAIL: the salary is not on Awa''s payroll row';
    end if;
    -- Changed, then cleared: the same row.
    if set_member_salary('69000000-0000-0000-0000-000000000001',
                         '69696969-0000-0000-0000-000000000002', 12000, 'week') <> v_id then
        raise exception 'FAIL: changing the salary made a second row';
    end if;
    if (select pay_period from employees where id = v_id) <> 'week' then
        raise exception 'FAIL: changing the salary made a second row';
    end if;
    perform set_member_salary('69000000-0000-0000-0000-000000000001',
                              '69696969-0000-0000-0000-000000000002', null);
    s := team_overview('69000000-0000-0000-0000-000000000001');
    select x into m from jsonb_array_elements(s -> 'members') x
     where x ->> 'user_id' = '69696969-0000-0000-0000-000000000002';
    if m ->> 'salary' is not null then
        raise exception 'FAIL: a cleared salary still reads %', m;
    end if;
    begin
        perform set_member_salary('69000000-0000-0000-0000-000000000001',
                                  '69696969-0000-0000-0000-000000000002', 100, 'year');
        raise exception 'FAIL: an unknown period was taken';
    exception when raise_exception then
        if sqlerrm not like 'Période inconnue%' then raise; end if;
    end;
    begin
        perform set_member_salary('69000000-0000-0000-0000-000000000001',
                                  '69696969-0000-0000-0000-000000000005', 100, 'month');
        raise exception 'FAIL: a salary for somebody outside the team';
    exception when raise_exception then
        if sqlerrm not like 'Cette personne n''est pas dans l''équipe%' then raise; end if;
    end;
    -- Paying is the payroll's, and Pro (066) — the Basic shop is refused.
    begin
        perform pay_employee('69000000-0000-0000-0000-000000000001',
            (select id from employees where user_id = '69696969-0000-0000-0000-000000000003'));
        raise exception 'FAIL: a Basic shop paid a salary through the payroll';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro :%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000003';
do $$ begin
    if team_overview('69000000-0000-0000-0000-000000000001') is not null then
        raise exception 'FAIL: an employee read the team''s salaries';
    end if;
    begin
        perform set_member_salary('69000000-0000-0000-0000-000000000001',
                                  '69696969-0000-0000-0000-000000000003', 999999, 'month');
        raise exception 'FAIL: an employee set their own salary';
    exception when raise_exception then
        if sqlerrm not like 'Seul un administrateur%' then raise; end if;
    end;
    raise notice 'PASS: recorded, changed, cleared, by an admin only; paying stays Pro';
end $$;
commit;

\echo ''
\echo '--- TEST 6: ten articles photographed on Basic, the eleventh refused, a slot bought opens it ---'
insert into products (id, org_id, name, sale_price, quantity, is_active, is_published)
select ('69aaaaaa-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid,
       '69000000-0000-0000-0000-000000000001', 'Article ' || g, 500, 5, true, true
  from generate_series(1, 12) g;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000001';
do $$
declare
    v_org uuid := '69000000-0000-0000-0000-000000000001';
    g int;
    s jsonb;
begin
    for g in 1..10 loop
        perform record_document(v_org, 'org/' || v_org || '/p' || g || '.jpg', 'photo',
            p_product_id => ('69aaaaaa-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid);
    end loop;
    -- A second photo of an article already photographed takes no place.
    perform record_document(v_org, 'org/' || v_org || '/p1b.jpg', 'photo',
        p_product_id => '69aaaaaa-0000-0000-0000-000000000001');
    -- A receipt captured with no article is not an article's photo.
    perform record_document(v_org, 'org/' || v_org || '/recu.jpg', 'receipt');
    s := feature_states(v_org) -> 'photos';
    if (s ->> 'used')::int <> 10 or (s ->> 'limit')::int <> 10 or (s ->> 'slot_cost')::int <> 50 then
        raise exception 'FAIL: the counter reads %', s;
    end if;
    begin
        perform record_document(v_org, 'org/' || v_org || '/p11.jpg', 'photo',
            p_product_id => '69aaaaaa-0000-0000-0000-000000000011');
        raise exception 'FAIL: an eleventh article was photographed on Basic';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : toutes vos places photo sont prises%' then raise; end if;
    end;
    -- Filing the receipt onto an eleventh article is paperwork, not its
    -- picture: no place taken (B1).
    update documents set product_id = '69aaaaaa-0000-0000-0000-000000000011'
     where r2_key = 'org/' || v_org || '/recu.jpg';
    if (feature_states(v_org) -> 'photos' ->> 'used')::int <> 10 then
        raise exception 'FAIL: a receipt filed on an article took a photo place';
    end if;
    -- Re-filed as its photo, it would be one: refused, and it stays a
    -- document (the message says so).
    begin
        update documents set kind = 'product_photo'
         where r2_key = 'org/' || v_org || '/recu.jpg';
        raise exception 'FAIL: a capture was re-filed as an eleventh article''s photo';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : toutes vos places photo sont prises. La photo reste dans vos documents%' then raise; end if;
    end;
end $$;
commit;
-- The path paid its steps on the way (097): the wallet emptied for the test.
insert into cauris_ledger (org_id, delta, reason, ref)
select '69000000-0000-0000-0000-000000000001', -cauris_balance('69000000-0000-0000-0000-000000000001'),
       'spent', 't69-empty'
 where cauris_balance('69000000-0000-0000-0000-000000000001') > 0;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000001';
do $$ begin
    begin
        perform buy_photo_slot('69000000-0000-0000-0000-000000000001');
        raise exception 'FAIL: a slot bought with no cauris';
    exception when raise_exception then
        if sqlerrm not like 'Il vous manque 50 cauris%' then raise; end if;
    end;
end $$;
commit;
insert into cauris_ledger (org_id, delta, reason, ref) values
    ('69000000-0000-0000-0000-000000000001', 60, 'prize', 't69-photo');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000001';
do $$
declare
    v_org uuid := '69000000-0000-0000-0000-000000000001';
    r jsonb;
begin
    r := buy_photo_slot(v_org);
    if (r ->> 'slots')::int <> 1 or (r ->> 'balance')::int <> 10
       or (r -> 'photos' ->> 'limit')::int <> 11 then
        raise exception 'FAIL: the slot bought reads %', r;
    end if;
    perform record_document(v_org, 'org/' || v_org || '/p11.jpg', 'photo',
        p_product_id => '69aaaaaa-0000-0000-0000-000000000011');
    begin
        perform record_document(v_org, 'org/' || v_org || '/p12.jpg', 'photo',
            p_product_id => '69aaaaaa-0000-0000-0000-000000000012');
        raise exception 'FAIL: a twelfth article with one slot';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : toutes vos places photo%' then raise; end if;
    end;
    begin
        perform spend_cauris(v_org, 'photo_slot');
        raise exception 'FAIL: a photo slot was opened for 30 days';
    exception when raise_exception then
        if sqlerrm not like 'Cet outil ne s''ouvre pas avec des cauris%' then raise; end if;
    end;
    if exists (select 1 from jsonb_array_elements(feature_states(v_org) -> 'tools') t
                where t ->> 'feature' = 'photo_slot') then
        raise exception 'FAIL: a photo slot is listed among the 30-day tools';
    end if;
end $$;
commit;
-- Over the limit already (the platform's hand, or before 100): kept, and
-- another photo of one of them still goes in.
update orgs set photo_slots = 0 where id = '69000000-0000-0000-0000-000000000001';
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000001';
select record_document('69000000-0000-0000-0000-000000000001',
    'org/69000000-0000-0000-0000-000000000001/p11b.jpg', 'photo',
    p_product_id => '69aaaaaa-0000-0000-0000-000000000011') is not null as kept;
commit;
-- Pro, and a showcase: no limit.
insert into products (id, org_id, name, sale_price, quantity, is_active, is_published)
select ('69bbbbbb-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid,
       '69000000-0000-0000-0000-000000000004', 'Pro ' || g, 500, 5, true, true
  from generate_series(1, 11) g;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000009';
do $$
declare v_org uuid := '69000000-0000-0000-0000-000000000004'; g int;
begin
    for g in 1..11 loop
        perform record_document(v_org, 'org/' || v_org || '/p' || g || '.jpg', 'photo',
            p_product_id => ('69bbbbbb-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid);
    end loop;
    if (feature_states(v_org) -> 'photos' ->> 'limit') is not null then
        raise exception 'FAIL: Pro is shown a photo limit';
    end if;
end $$;
commit;
do $$ begin
    if org_photo_limit('69000000-0000-0000-0000-000000000005') is not null then
        raise exception 'FAIL: a showcase vitrine has a photo limit';
    end if;
    raise notice 'PASS: 10 + a bought slot, the next refused, a second photo and a capture free, Pro and showcase unlimited';
end $$;

\echo ''
\echo '--- TEST 7: only the platform gives; a gift, promotional points spent first and taken out on their day ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000005';
do $$ begin
    begin
        perform platform_give_cauris('69000000-0000-0000-0000-000000000002', 500, 'moi');
        raise exception 'FAIL: a business gave itself cauris';
    exception when raise_exception then
        if sqlerrm not like 'Seule la plateforme offre des cauris%' then raise; end if;
    end;
    begin
        perform platform_give_unlock('69000000-0000-0000-0000-000000000002', 'analytics', current_date + 5);
        raise exception 'FAIL: a business gave itself a tool';
    exception when raise_exception then
        if sqlerrm not like 'Seule la plateforme offre un outil%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000006';
do $$
declare
    v_org uuid := '69000000-0000-0000-0000-000000000002';
    r jsonb;
begin
    perform platform_give_cauris(v_org, 300, 'Bienvenue');
    r := platform_give_cauris(v_org, 200, 'Fête', cauris_today() + 20);
    if (r ->> 'balance')::int <> 500 or (r -> 'promo' -> 0 ->> 'points')::int <> 200
       or (r -> 'promo' -> 0 ->> 'until')::date <> cauris_today() + 20 then
        raise exception 'FAIL: the gifts read %', r;
    end if;
    begin
        perform platform_give_cauris(v_org, 10, null, cauris_today());
        raise exception 'FAIL: promotional points that expire today';
    exception when raise_exception then
        if sqlerrm not like 'La date doit être après aujourd''hui%' then raise; end if;
    end;
    begin
        perform platform_give_cauris(v_org, 0);
        raise exception 'FAIL: a gift of nothing';
    exception when raise_exception then
        if sqlerrm not like 'Le nombre de cauris%' then raise; end if;
    end;
    begin
        perform platform_give_cauris('69000000-0000-0000-0000-000000000005', 10);
        raise exception 'FAIL: cauris given to a showcase';
    exception when raise_exception then
        if sqlerrm not like 'Une vitrine d''exemple%' then raise; end if;
    end;
end $$;
commit;
-- The association spends (084 never let it), the promotion first.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000005';
do $$
declare
    v_org uuid := '69000000-0000-0000-0000-000000000002';
    w jsonb;
begin
    perform spend_cauris(v_org, 'analytics');          -- 400: the 200 promo, then 200
    if not org_has(v_org, 'analytics') then
        raise exception 'FAIL: the association''s unlock did not open the tool';
    end if;
    w := my_cauris(v_org);
    if (w ->> 'balance')::int <> 100 or jsonb_array_length(w -> 'promo') <> 0 then
        raise exception 'FAIL: the promotion was not spent first: %', w;
    end if;
    if (w ->> 'week')::int <> 0 then
        raise exception 'FAIL: a gift counts in the week''s score: %', w ->> 'week';
    end if;
    if not exists (select 1 from jsonb_array_elements(w -> 'history') h
                    where h ->> 'reason' = 'gift' and h ->> 'label' = 'Cadeau de Mara'
                      and h ->> 'note' = 'Bienvenue') then
        raise exception 'FAIL: the gift is not in the history: %', w -> 'history';
    end if;
    -- It still earns nothing (084).
    if cauris_award(v_org, 'visitor', 't69') <> 0 then
        raise exception 'FAIL: an association earned';
    end if;
    raise notice 'PASS: only the platform gives; the association spends, the promotion first; a gift is not the week''s';
end $$;
commit;
-- A promotion's day: what is left is taken out, once, never below zero.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000006';
select platform_give_cauris('69000000-0000-0000-0000-000000000003', 100, 'Été', cauris_today() + 3) is not null;
select platform_give_cauris('69000000-0000-0000-0000-000000000003', 50) is not null;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000007';
do $$
declare w jsonb := my_cauris('69000000-0000-0000-0000-000000000003');
begin
    if (w ->> 'balance')::int <> 150 or (w -> 'promo' -> 0 ->> 'points')::int <> 100 then
        raise exception 'FAIL: the farm''s wallet reads %', w;
    end if;
end $$;
commit;
update cauris_promos set expires_on = cauris_today()
 where org_id = '69000000-0000-0000-0000-000000000003';
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000007';
do $$
declare
    s jsonb := feature_states('69000000-0000-0000-0000-000000000003');
    w jsonb := my_cauris('69000000-0000-0000-0000-000000000003');
begin
    if (s ->> 'balance')::int <> 50 or (w ->> 'balance')::int <> 50
       or jsonb_array_length(w -> 'promo') <> 0
       or (select count(*) from jsonb_array_elements(w -> 'history') h
            where h ->> 'reason' = 'expired' and (h ->> 'delta')::int = -100) <> 1 then
        raise exception 'FAIL: the promotion was not taken out once on its day: %', w;
    end if;
    raise notice 'PASS: on its day, the 100 left are taken out by one line; the gift stays';
end $$;
commit;
-- A loss eaten into the promotion first: the expiry never goes below zero.
insert into cauris_ledger (org_id, delta, reason, ref) values
    ('69000000-0000-0000-0000-000000000001', -10, 'shop_cancel', 't69-loss');
insert into cauris_promos (org_id, points, left_points, expires_on)
values ('69000000-0000-0000-0000-000000000001', 30, 30, cauris_today());
select cauris_expire('69000000-0000-0000-0000-000000000001');
do $$ begin
    if cauris_balance('69000000-0000-0000-0000-000000000001') <> 0 then
        raise exception 'FAIL: an expiry took the wallet to %',
            cauris_balance('69000000-0000-0000-0000-000000000001');
    end if;
end $$;

\echo ''
\echo '--- TEST 8: a tool given until a date: open, no cauris, not « mon premier outil », the bell rings ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000006';
do $$
declare
    v_org   uuid := '69000000-0000-0000-0000-000000000003';
    v_until timestamptz;
    v_bal   int := cauris_balance('69000000-0000-0000-0000-000000000003');
begin
    v_until := platform_give_unlock(v_org, 'accounting', cauris_today() + 10, null);
    if v_until <> (cauris_today() + 11)::timestamp at time zone 'Africa/Ouagadougou' then
        raise exception 'FAIL: the tool is open until % (the day itself included)', v_until;
    end if;
    if not org_has(v_org, 'accounting') or cauris_balance(v_org) <> v_bal then
        raise exception 'FAIL: the gift did not open the tool, or cost cauris';
    end if;
    if (select note from cauris_unlocks where org_id = v_org and feature = 'accounting')
       <> 'Offert par Mara' then
        raise exception 'FAIL: the unlock is not noted as given';
    end if;
    begin
        perform platform_give_unlock(v_org, 'photo_slot', cauris_today() + 10);
        raise exception 'FAIL: a photo slot given as a tool';
    exception when raise_exception then
        if sqlerrm not like 'Outil inconnu%' then raise; end if;
    end;
    begin
        perform platform_give_unlock(v_org, 'accounting', cauris_today() - 1);
        raise exception 'FAIL: a tool given until yesterday';
    exception when raise_exception then
        if sqlerrm not like 'La date doit être%' then raise; end if;
    end;
end $$;
commit;
do $$
declare n record;
begin
    if path_progress('69000000-0000-0000-0000-000000000003', 'first_unlock') <> 0 then
        raise exception 'FAIL: a tool given counts as the business''s first unlock';
    end if;
    select * into n from notifications
     where org_id = '69000000-0000-0000-0000-000000000003' and kind = 'feature_gift';
    if n.recipient_id <> '69696969-0000-0000-0000-000000000007'
       or n.params ->> 'feature' <> 'accounting'
       or (n.params ->> 'until')::date <> cauris_today() + 10
       or n.message not like 'Mara vous offre la comptabilité jusqu''au %' then
        raise exception 'FAIL: the farmer''s bell for the tool reads %', row_to_json(n);
    end if;
    select * into n from notifications
     where org_id = '69000000-0000-0000-0000-000000000003' and kind = 'cauris_promo';
    if (n.params ->> 'points')::int <> 100 or n.params ->> 'note' <> 'Été'
       or n.message not like 'Mara vous offre 100 cauris, à utiliser avant le %' then
        raise exception 'FAIL: the promotion''s bell reads %', row_to_json(n);
    end if;
    if not exists (select 1 from notifications
                    where org_id = '69000000-0000-0000-0000-000000000002' and kind = 'cauris_gift'
                      and recipient_id = '69696969-0000-0000-0000-000000000005'
                      and (params ->> 'points')::int = 300) then
        raise exception 'FAIL: the association''s treasurer did not hear of the gift';
    end if;
    -- A gift is not earned: not in a league's score.
    if exists (select 1 from league_scores(now() - interval '1 day', now() + interval '1 day') s
                where s.org_id = '69000000-0000-0000-0000-000000000003' and s.score > 0) then
        raise exception 'FAIL: a gift counts in the league';
    end if;
    raise notice 'PASS: open until the day, no cauris, noted, not the first unlock, rung with its facts, out of the leagues';
end $$;
-- A tool bought after it was given is the business's own.
insert into cauris_ledger (org_id, delta, reason, ref) values
    ('69000000-0000-0000-0000-000000000003', 600, 'prize', 't69-buy');
update orgs set created_at = now() - interval '90 days' where id = '69000000-0000-0000-0000-000000000003';
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000007';
select spend_cauris('69000000-0000-0000-0000-000000000003', 'accounting') is not null;
commit;
do $$ begin
    if (select gifted_by from cauris_unlocks
         where org_id = '69000000-0000-0000-0000-000000000003' and feature = 'accounting') is not null
       or path_progress('69000000-0000-0000-0000-000000000003', 'first_unlock') <> 1 then
        raise exception 'FAIL: the tool bought is still marked as given';
    end if;
    raise notice 'PASS: bought after it was given, the tool is the farm''s own';
end $$;

\echo ''
\echo '--- TEST 9: my_orgs() names the owner ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000002';
do $$ begin
    if (select owner_name from my_orgs() where org_id = '69000000-0000-0000-0000-000000000001')
       <> 'Patronne'
       or (select owner_name from my_orgs() where org_id = '69000000-0000-0000-0000-000000000002')
       <> 'Trésorière' then
        raise exception 'FAIL: the picker does not name the owners';
    end if;
end $$;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000006';
do $$ begin
    if (select owner_name from my_orgs() where org_id = '69000000-0000-0000-0000-000000000003')
       <> 'Fermier'
       or (select owner_name from my_orgs() where org_id = '69000000-0000-0000-0000-000000000005')
       is not null then
        raise exception 'FAIL: Mara''s admin is not told whose business it is';
    end if;
    raise notice 'PASS: each business''s owner, for its members and for Mara''s admin (none: null)';
end $$;
commit;

\echo ''
\echo '--- TEST 10: the stock — a production and a flock corrected; the till, credit, returns, deliveries ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000009';
do $$
declare
    v_org    uuid := '69000000-0000-0000-0000-000000000004';
    v_flour  uuid;
    v_cake   uuid;
    v_lav    uuid;
    v_run    uuid;
    v_sale   uuid;
    v_rec    uuid;
    q        numeric;
begin
    insert into products (org_id, name, cost_price, sale_price, quantity, low_stock_at)
    values (v_org, 'Farine 69', 100, 0, 50, null) returning id into v_flour;
    insert into products (org_id, name, sale_price, quantity, low_stock_at)
    values (v_org, 'Gâteau 69', 300, 0, 5) returning id into v_cake;
    insert into products (org_id, name, sale_price, is_service)
    values (v_org, 'Lavage 69', 1000, true) returning id into v_lav;

    -- 20 made from 10 of flour; corrected to 40: the shelf says 40.
    v_run := record_production(v_org, 20,
        jsonb_build_array(jsonb_build_object('product_id', v_flour, 'quantity', 10)),
        p_product_id => v_cake);
    if (select cost_price from products where id = v_cake) <> 50 then
        raise exception 'FAIL: the batch did not price the cake at 50 (026)';
    end if;
    perform update_production_run(v_run, p_quantity => 40);
    select quantity into q from products where id = v_cake;
    if q <> 40 then raise exception 'FAIL: corrected to 40, the shelf holds %', q; end if;
    -- The same 1 000 F of flour over 40 cakes: 25 each, on the article too.
    if (select cost_price from products where id = v_cake) <> 25 then
        raise exception 'FAIL: corrected to 40, the cake costs % (25 expected)',
            (select cost_price from products where id = v_cake);
    end if;
    perform update_production_run(v_run, p_quantity => 30);
    select quantity into q from products where id = v_cake;
    if q <> 30 then raise exception 'FAIL: corrected to 30, the shelf holds %', q; end if;
    if (select cost_price from products where id = v_cake) <> 33.33 then
        raise exception 'FAIL: corrected to 30, the cake costs %',
            (select cost_price from products where id = v_cake);
    end if;
    select quantity into q from products where id = v_flour;
    if q <> 40 then raise exception 'FAIL: the flour moved on a correction (%)', q; end if;
    perform update_production_run(v_run, p_note => 'four du matin');
    select quantity into q from products where id = v_cake;
    if q <> 30 then raise exception 'FAIL: a note moved the shelf (%)', q; end if;

    -- The till: 28 sold; past the shelf refused (101); the bell rings once.
    v_sale := record_sale(v_org, jsonb_build_array(
        jsonb_build_object('product_id', v_cake, 'quantity', 28, 'unit_price', 300),
        jsonb_build_object('product_id', v_lav, 'quantity', 2, 'unit_price', 1000)));
    select quantity into q from products where id = v_cake;
    if q <> 2 then raise exception 'FAIL: the till left % cakes', q; end if;
    if (select quantity from products where id = v_lav) <> 0 then
        raise exception 'FAIL: a service has stock after a sale';
    end if;
    -- 101: past the shelf is refused now, in French, and nothing moves.
    begin
        perform record_sale(v_org, jsonb_build_array(
            jsonb_build_object('product_id', v_cake, 'quantity', 4, 'unit_price', 300)));
        raise exception 'FAIL: the till sold past the shelf';
    exception when sqlstate 'MA001' then
        if sqlerrm <> 'Il ne reste que 2 Gâteau 69' then raise; end if;
    end;
    if (select quantity from products where id = v_cake) <> 2 then
        raise exception 'FAIL: a refused sale moved the shelf';
    end if;
    if (select count(*) from notifications
         where org_id = v_org and kind = 'low_stock'
           and params ->> 'product_id' = v_cake::text) <> 1 then
        raise exception 'FAIL: the low-stock bell did not ring exactly once';
    end if;
    -- A return puts them back, the service stays at none.
    perform record_return(v_sale);
    if (select quantity from products where id = v_cake) <> 30
       or (select quantity from products where id = v_lav) <> 0 then
        raise exception 'FAIL: the return did not restore the shelf';
    end if;
    -- On credit, the goods leave the same way.
    perform record_sale(v_org, jsonb_build_array(
        jsonb_build_object('product_id', v_cake, 'quantity', 6, 'unit_price', 300)),
        p_method => 'credit', p_customer_name => 'Awa');
    if (select quantity from products where id = v_cake) <> 24 then
        raise exception 'FAIL: a credit sale did not move the stock';
    end if;
    -- A delivery received and reversed.
    perform receive_products(v_org, v_flour, 25, p_unit_cost => 100);
    select id into v_rec from stock_receipts where product_id = v_flour order by received_at desc limit 1;
    if (select quantity from products where id = v_flour) <> 65 then
        raise exception 'FAIL: the delivery did not arrive';
    end if;
    perform reverse_receipt(v_rec, 'Erreur');
    if (select quantity from products where id = v_flour) <> 40 then
        raise exception 'FAIL: the reversal did not take the delivery back';
    end if;
    begin
        perform receive_products(v_org, v_lav, 3);
        raise exception 'FAIL: a service received into stock';
    exception when raise_exception then
        if sqlerrm not like 'Un service n''a pas de stock%' then raise; end if;
    end;
    raise notice 'PASS: production corrected on the shelf; till, past the shelf refused, the bell, a return, credit, a delivery and its reversal';
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000007';
do $$
declare
    v_flock uuid := open_flock('69000000-0000-0000-0000-000000000003', 'B-69', 100);
    v_ev    uuid;
begin
    v_ev := record_flock_event(v_flock, 'mortality', 3);
    perform record_flock_event(v_flock, 'sold', 90);
    begin
        perform update_flock_event(v_ev, p_quantity => 300);
        raise exception 'FAIL: a correction took 300 birds out of 100';
    exception when raise_exception then
        if sqlerrm not like 'Only 10% birds left in this flock%' then raise; end if;
    end;
    perform update_flock_event(v_ev, p_quantity => 8);
    begin
        perform update_flock_event(v_ev, p_quantity => 11);
        raise exception 'FAIL: a correction past the birds left';
    exception when raise_exception then
        if sqlerrm not like 'Only 10% birds left%' then raise; end if;
    end;
    -- A weighing is no bird out.
    perform update_flock_event(v_ev, p_kind => 'weight', p_quantity => 1500);
    raise notice 'PASS: a flock corrected loses no more birds than it has';
end $$;
commit;

\echo ''
\echo '--- TEST 11: the doors — the street reaches none of it, the engine is the database''s own ---'
do $$
declare
    f text;
begin
    foreach f in array array[
        'team_overview(uuid)', 'set_member_salary(uuid, uuid, numeric, text)',
        'buy_photo_slot(uuid)', 'platform_give_cauris(uuid, integer, text, date)',
        'platform_give_unlock(uuid, text, date, text)', 'feature_states(uuid)',
        'my_cauris(uuid)', 'spend_cauris(uuid, text)', 'my_orgs()'] loop
        if has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: the street may call %', f;
        end if;
        if not has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: the app may not call %', f;
        end if;
    end loop;
    foreach f in array array[
        'cauris_take(uuid, integer, text, text)', 'cauris_expire(uuid)',
        'cauris_promo_left(uuid)', 'team_full(uuid)', 'team_seats(uuid)',
        'org_workers(uuid)', 'org_photo_items(uuid)', 'photo_state(uuid)',
        'person_name(uuid)', 'trg_photo_items()', 'trg_invitation_seat()',
        'trg_membership_roles()', 'trg_photo_revive()'] loop
        if has_function_privilege('authenticated', f, 'execute')
           or has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: % is open to an app role', f;
        end if;
    end loop;
    -- The street still reads its window and its pictures (B1 replaced them).
    foreach f in array array[
        'storefront_photo_allowed(text)', 'storefront_products(text)',
        'search_products(text, double precision, double precision)',
        'storefront_featured()', 'storefront_previews(text[])'] loop
        if not has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: the street lost %', f;
        end if;
    end loop;
    if has_function_privilege('anon', 'doc_is_photo(text, text)', 'execute') then
        raise exception 'FAIL: doc_is_photo is open to the street';
    end if;
    raise notice 'PASS: the app''s doors for the signed-in only; the engine closed; the street keeps its window';
end $$;

\echo ''
\echo '--- TEST 12: paperwork on an article is no photo — not counted, never the vitrine''s picture, never served to the street (B1) ---'
update orgs set storefront_enabled = true where id = '69000000-0000-0000-0000-000000000004';
insert into products (id, org_id, name, sale_price, quantity, is_active, is_published)
values ('69cccccc-0000-0000-0000-000000000001', '69000000-0000-0000-0000-000000000004',
        'Facture Soixante-Neuf', 700, 5, true, true),
       ('69cccccc-0000-0000-0000-000000000002', '69000000-0000-0000-0000-000000000001',
        'Livraison 69', 700, 5, true, true);
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000009';
-- A delivery note filed on the article (confirm_products_screen's 'invoice').
select record_document('69000000-0000-0000-0000-000000000004', 'org/69000000-0000-0000-0000-000000000004/bl-1.jpg', 'invoice',
    p_product_id => '69cccccc-0000-0000-0000-000000000001') is not null;
commit;
begin;
set local role anon;
do $$ begin
    if (select photo_key from storefront_products('pro-69')
         where id = '69cccccc-0000-0000-0000-000000000001') is not null then
        raise exception 'FAIL: a delivery note is the vitrine''s picture of the article';
    end if;
    if storefront_photo_allowed('org/69000000-0000-0000-0000-000000000004/bl-1.jpg') then
        raise exception 'FAIL: the street is served a supplier''s delivery note';
    end if;
end $$;
commit;
-- Then its real photo (older), and a second delivery note (newer).
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000009';
select record_document('69000000-0000-0000-0000-000000000004', 'org/69000000-0000-0000-0000-000000000004/facture-photo.jpg',
    'product_photo', p_captured_at => now() - interval '2 days',
    p_product_id => '69cccccc-0000-0000-0000-000000000001') is not null;
select record_document('69000000-0000-0000-0000-000000000004', 'org/69000000-0000-0000-0000-000000000004/bl-2.jpg', 'receipt',
    p_product_id => '69cccccc-0000-0000-0000-000000000001') is not null;
select record_document('69000000-0000-0000-0000-000000000004', 'org/69000000-0000-0000-0000-000000000004/bl-3.pdf', 'photo',
    p_content_type => 'application/pdf',
    p_product_id => '69cccccc-0000-0000-0000-000000000001') is not null;
do $$ begin
    if (select photo_key from product_photo_keys('69000000-0000-0000-0000-000000000004')
         where product_id = '69cccccc-0000-0000-0000-000000000001') <> 'org/69000000-0000-0000-0000-000000000004/facture-photo.jpg' then
        raise exception 'FAIL: the Articles page shows paperwork as the picture';
    end if;
end $$;
commit;
update products set featured_until = now() + interval '1 day'
 where id = '69cccccc-0000-0000-0000-000000000001';
begin;
set local role anon;
do $$ begin
    if (select photo_key from storefront_products('pro-69')
         where id = '69cccccc-0000-0000-0000-000000000001') <> 'org/69000000-0000-0000-0000-000000000004/facture-photo.jpg'
       or (select photo_key from search_products('Facture Soixante')
            where id = '69cccccc-0000-0000-0000-000000000001') <> 'org/69000000-0000-0000-0000-000000000004/facture-photo.jpg'
       or (select photo_key from storefront_featured()
            where id = '69cccccc-0000-0000-0000-000000000001') <> 'org/69000000-0000-0000-0000-000000000004/facture-photo.jpg' then
        raise exception 'FAIL: the newest document, not the newest photo, is the picture';
    end if;
    if exists (select 1 from storefront_previews(array['pro-69'])
                where photo_key in ('org/69000000-0000-0000-0000-000000000004/bl-1.jpg', 'org/69000000-0000-0000-0000-000000000004/bl-2.jpg', 'org/69000000-0000-0000-0000-000000000004/bl-3.pdf')) then
        raise exception 'FAIL: a street card shows paperwork';
    end if;
    if not storefront_photo_allowed('org/69000000-0000-0000-0000-000000000004/facture-photo.jpg')
       or storefront_photo_allowed('org/69000000-0000-0000-0000-000000000004/bl-2.jpg')
       or storefront_photo_allowed('org/69000000-0000-0000-0000-000000000004/bl-3.pdf') then
        raise exception 'FAIL: the photo gate serves paperwork, or not the photo';
    end if;
end $$;
commit;
-- On Basic: the shop is full (11 kept, limit 10). A delivery note still
-- files on a new article; a photo of it does not — paperwork does not make
-- it « already photographed ».
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000001';
do $$
declare
    v_org  uuid := '69000000-0000-0000-0000-000000000001';
    v_used int := (feature_states('69000000-0000-0000-0000-000000000001') -> 'photos' ->> 'used')::int;
begin
    perform record_document(v_org, 'org/69000000-0000-0000-0000-000000000001/livraison-bl.jpg', 'invoice',
        p_product_id => '69cccccc-0000-0000-0000-000000000002');
    if (feature_states(v_org) -> 'photos' ->> 'used')::int <> v_used then
        raise exception 'FAIL: a delivery note took a photo place';
    end if;
    begin
        perform record_document(v_org, 'org/69000000-0000-0000-0000-000000000001/livraison.jpg', 'product_photo',
            p_product_id => '69cccccc-0000-0000-0000-000000000002');
        raise exception 'FAIL: an article with only paperwork was photographed past the limit';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : toutes vos places photo sont prises. Pour photographier%' then raise; end if;
    end;
end $$;
commit;
-- Paperwork is under the general cap (066): at the cap, refused there.
update platform_settings set value = to_jsonb((
    select count(*) from documents where org_id = '69000000-0000-0000-0000-000000000001'
       and (product_id is null or not doc_is_photo(kind, content_type))))
 where key = 'free_max_photos';
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000001';
do $$ begin
    begin
        perform record_document('69000000-0000-0000-0000-000000000001',
            'org/69000000-0000-0000-0000-000000000001/livraison-bl2.jpg', 'receipt',
            p_product_id => '69cccccc-0000-0000-0000-000000000002');
        raise exception 'FAIL: paperwork on an article escaped the general cap';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : la formule gratuite garde%' then raise; end if;
    end;
    raise notice 'PASS: paperwork is not a picture — not counted, not on the vitrine, not served; under the general cap';
end $$;
commit;
update platform_settings set value = '50' where key = 'free_max_photos';

\echo ''
\echo '--- TEST 13: an article brought back with its photo takes a place again; a slot is not sold to Pro ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000001';
do $$
declare v_org uuid := '69000000-0000-0000-0000-000000000001';
begin
    -- 11 kept, limit 10: archiving two leaves 9, one comes back, not the second.
    perform archive_product('69aaaaaa-0000-0000-0000-000000000005');
    perform archive_product('69aaaaaa-0000-0000-0000-000000000006');
    if (feature_states(v_org) -> 'photos' ->> 'used')::int <> 9 then
        raise exception 'FAIL: archived articles still take places (%)', (feature_states(v_org) -> 'photos' ->> 'used')::int;
    end if;
    perform archive_product('69aaaaaa-0000-0000-0000-000000000005', false);
    begin
        perform archive_product('69aaaaaa-0000-0000-0000-000000000006', false);
        raise exception 'FAIL: an archived photographed article came back past the limit';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : cet article a une photo et toutes vos places photo sont prises%' then raise; end if;
    end;
    -- Re-added by its name (051) is the same return.
    begin
        perform ensure_product(v_org, 'Article 6');
        raise exception 'FAIL: re-adding a photographed article by its name passed the limit';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : cet article a une photo%' then raise; end if;
    end;
    -- An article with no photo comes back freely.
    update products set is_active = false where id = '69aaaaaa-0000-0000-0000-000000000012';
    update products set is_active = true where id = '69aaaaaa-0000-0000-0000-000000000012';
end $$;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000009';
do $$ begin
    begin
        perform buy_photo_slot('69000000-0000-0000-0000-000000000004');
        raise exception 'FAIL: a Pro business bought a photo slot';
    exception when raise_exception then
        if sqlerrm not like 'Cette entreprise a déjà ses photos sans limite%' then raise; end if;
    end;
    raise notice 'PASS: archive frees a place, coming back takes one (or is refused); Pro buys no slot';
end $$;
commit;

\echo ''
\echo '--- TEST 14: a salary for a period the payroll reads; never a kind changed; clearing brings nobody back (B2) ---'
-- Coumba (w3) works at the Pro shop, already on its payroll by the hour.
insert into employees (org_id, full_name, kind, hourly_rate, user_id)
values ('69000000-0000-0000-0000-000000000004', 'Coumba', 'casual', 500,
        '69696969-0000-0000-0000-000000000004');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000009';
do $$
declare
    v_org uuid := '69000000-0000-0000-0000-000000000004';
    m     jsonb;
begin
    begin
        perform set_member_salary(v_org, '69696969-0000-0000-0000-000000000004', 3000, 'week');
        raise exception 'FAIL: a salary turned an hourly worker into a permanent';
    exception when raise_exception then
        if sqlerrm not like 'Cette personne est payée à l''heure%' then raise; end if;
    end;
    if (select kind from employees where org_id = v_org
          and user_id = '69696969-0000-0000-0000-000000000004') <> 'casual' then
        raise exception 'FAIL: the kind changed';
    end if;
    select x into m from jsonb_array_elements(team_overview(v_org) -> 'members') x
     where x ->> 'user_id' = '69696969-0000-0000-0000-000000000004';
    if (m ->> 'hourly')::numeric <> 500 or m ->> 'salary' is not null then
        raise exception 'FAIL: Équipe does not say she is paid by the hour: %', m;
    end if;
end $$;
commit;
-- A permanent paid by the week: one payment is one week.
update employees set kind = 'permanent', hourly_rate = 0
 where org_id = '69000000-0000-0000-0000-000000000004'
   and user_id = '69696969-0000-0000-0000-000000000004';
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000009';
do $$
declare
    v_org uuid := '69000000-0000-0000-0000-000000000004';
    v_emp uuid;
    v_pay uuid;
begin
    v_emp := set_member_salary(v_org, '69696969-0000-0000-0000-000000000004', 3000, 'week');
    if (select pay_period from employees where id = v_emp) <> 'week'
       or (select salary from employees where id = v_emp) <> 3000 then
        raise exception 'FAIL: the week''s salary is not on the payroll row';
    end if;
    v_pay := pay_employee(v_org, v_emp);
    if (select amount from staff_payments where id = v_pay) <> 3000 then
        raise exception 'FAIL: the payroll paid % for a week''s salary of 3000',
            (select amount from staff_payments where id = v_pay);
    end if;
end $$;
commit;
-- Awa's row at the Basic shop ends; clearing her salary does not revive it.
update employees set is_active = false, ended_on = current_date, end_reason = 'resigned',
       salary = 45000, pay_period = 'month'
 where org_id = '69000000-0000-0000-0000-000000000001'
   and user_id = '69696969-0000-0000-0000-000000000002';
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000001';
select set_member_salary('69000000-0000-0000-0000-000000000001',
                         '69696969-0000-0000-0000-000000000002', null) is not null;
commit;
do $$ begin
    if (select is_active or ended_on is null or salary <> 0
          from employees where org_id = '69000000-0000-0000-0000-000000000001'
           and user_id = '69696969-0000-0000-0000-000000000002') then
        raise exception 'FAIL: clearing a salary brought an ended employee back';
    end if;
    raise notice 'PASS: an hourly worker keeps her kind; a week''s salary pays a week; clearing revives nobody';
end $$;

\echo ''
\echo '--- TEST 15: no seat by the back door — a trainer, an owner, a row moved (S1) ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000007';
-- A code written while the farm's seat is free, then the seat taken.
insert into pending_invitations (org_id, role, scope_kind, scope_id, code, created_by)
values ('69000000-0000-0000-0000-000000000003', 'employee', 'org',
        '69000000-0000-0000-0000-000000000003', 'TEAM-6910',
        '69696969-0000-0000-0000-000000000007');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
values ('69000000-0000-0000-0000-000000000003', '69696969-0000-0000-0000-000000000002',
        'employee', 'org', '69000000-0000-0000-0000-000000000003', 'full');
do $$
declare
    v_org uuid := '69000000-0000-0000-0000-000000000003';
    s     jsonb;
    n     int;
begin
    s := team_overview(v_org);
    if not (s -> 'invitations' -> 0 ->> 'blocked')::boolean then
        raise exception 'FAIL: the code waiting for a taken seat is not said blocked: %', s -> 'invitations';
    end if;
    -- (a) A trainer's grant, written by the business: the platform's only.
    begin
        insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility, is_trainer)
        values (v_org, '69696969-0000-0000-0000-000000000003', 'observer', 'org', v_org, 'full', true);
        raise exception 'FAIL: an admin wrote a trainer''s grant (no seat, hidden from Équipe)';
    exception when insufficient_privilege then
        if sqlerrm not like 'Seule la plateforme nomme une formatrice%' then raise; end if;
    end;
    begin
        update memberships set is_trainer = true
         where org_id = v_org and user_id = '69696969-0000-0000-0000-000000000002';
        raise exception 'FAIL: an admin turned a worker into a trainer';
    exception when insufficient_privilege then null;
    end;
    -- (b) An owner: not by invitation, not by a direct grant.
    begin
        perform invite_employee(v_org, 'owner');
        raise exception 'FAIL: invite_employee wrote an owner''s invitation';
    exception when insufficient_privilege then
        if sqlerrm not like 'Seule la plateforme nomme un propriétaire%' then raise; end if;
    end;
    begin
        insert into pending_invitations (org_id, role, scope_kind, scope_id, code, created_by)
        values (v_org, 'owner', 'org', v_org, 'OWNR-6911', '69696969-0000-0000-0000-000000000007');
        raise exception 'FAIL: an owner''s invitation was written';
    exception when insufficient_privilege then null;
    end;
    begin
        update pending_invitations set role = 'owner' where code = 'TEAM-6910';
        raise exception 'FAIL: an invitation was turned into an owner''s';
    exception when insufficient_privilege then null;
    end;
    begin
        insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
        values (v_org, '69696969-0000-0000-0000-000000000003', 'owner', 'org', v_org, 'full');
        raise exception 'FAIL: an admin made a second owner';
    exception when insufficient_privilege then null;
    end;
    -- The owner's row is not moved nor demoted from the app.
    update memberships set role = 'admin'
     where org_id = v_org and user_id = '69696969-0000-0000-0000-000000000007';
    update memberships set user_id = '69696969-0000-0000-0000-000000000002'
     where org_id = v_org and role = 'owner';
    if not exists (select 1 from memberships where org_id = v_org and role = 'owner'
                    and user_id = '69696969-0000-0000-0000-000000000007') then
        raise exception 'FAIL: the owner''s row was changed from the app';
    end if;
    -- (c) A worker's row moved onto somebody new is a new worker: the seat.
    begin
        update memberships set user_id = '69696969-0000-0000-0000-000000000003'
         where org_id = v_org and user_id = '69696969-0000-0000-0000-000000000002';
        raise exception 'FAIL: a row moved onto a new person dodged the seat';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : cette entreprise a déjà sa personne offerte%' then raise; end if;
    end;
    -- A role between workers is no new seat.
    update memberships set role = 'admin'
     where org_id = v_org and user_id = '69696969-0000-0000-0000-000000000002';
    -- An invitation for somebody already in (by number) is written; a
    -- bearer code with the seat taken is not.
    insert into pending_invitations (org_id, role, scope_kind, scope_id, code, phone, created_by)
    values (v_org, 'manager', 'org', v_org, 'TEAM-6912', '+22669000002',
            '69696969-0000-0000-0000-000000000007');
    begin
        insert into pending_invitations (org_id, role, scope_kind, scope_id, code, created_by)
        values (v_org, 'employee', 'org', v_org, 'TEAM-6913', '69696969-0000-0000-0000-000000000007');
        raise exception 'FAIL: a bearer code was written with the seat taken';
    exception when raise_exception then
        if sqlerrm not like 'Kaj Pro : cette entreprise a déjà%' then raise; end if;
    end;
    if (select (x ->> 'blocked')::boolean from jsonb_array_elements(team_overview(v_org) -> 'invitations') x
         where x ->> 'code' = 'TEAM-6912') then
        raise exception 'FAIL: an invitation for somebody already in is said blocked';
    end if;
end $$;
commit;
-- The new admin (Awa) cannot remove the owner either.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000002';
delete from memberships where org_id = '69000000-0000-0000-0000-000000000003' and role = 'owner';
do $$ begin
    if not exists (select 1 from memberships where org_id = '69000000-0000-0000-0000-000000000003'
                    and role = 'owner') then
        raise exception 'FAIL: an admin removed the owner';
    end if;
end $$;
commit;
-- An owner's invitation from before 100 (written by the database's hand):
-- claimed, it makes no owner; swept, it is skipped and the sweep goes on.
insert into pending_invitations (org_id, role, scope_kind, scope_id, code, phone, created_by)
values ('69000000-0000-0000-0000-000000000003', 'owner', 'org',
        '69000000-0000-0000-0000-000000000003', 'OWNR-6914', null,
        '69696969-0000-0000-0000-000000000007'),
       ('69000000-0000-0000-0000-000000000003', 'owner', 'org',
        '69000000-0000-0000-0000-000000000003', 'OWNR-6915', '+22669000003',
        '69696969-0000-0000-0000-000000000007');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000003';
do $$ begin
    begin
        perform claim_invitation('OWNR-6914');
        raise exception 'FAIL: an owner''s code made a second owner';
    exception when insufficient_privilege then null;
    end;
    perform claim_my_invitations();
    if exists (select 1 from memberships where org_id = '69000000-0000-0000-0000-000000000003'
                and user_id = '69696969-0000-0000-0000-000000000003') then
        raise exception 'FAIL: the sweep made an owner';
    end if;
    raise notice 'PASS: no trainer, no owner, no moved row past the seat; the owner stays; an old owner''s code makes nobody';
end $$;
commit;

\echo ''
\echo '--- TEST 16: the platform''s own ways still work — trainers, a business opened, a showcase joined ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000006';
select assign_trainer('69000000-0000-0000-0000-000000000003', '69696969-0000-0000-0000-000000000008');
select create_org('Mara 69', 'mara-69', 'retail') is not null;
select showcase_join('69000000-0000-0000-0000-000000000005');
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000004';
select apply_for_org('Coumba 69', 'coumba-69', 'farm') is not null;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000006';
select approve_org_application((select id from org_applications where slug = 'coumba-69')) is not null;
commit;
do $$ begin
    if org_workers('69000000-0000-0000-0000-000000000003') <> 1
       or not exists (select 1 from memberships where org_id = '69000000-0000-0000-0000-000000000003'
                       and user_id = '69696969-0000-0000-0000-000000000008' and is_trainer) then
        raise exception 'FAIL: the platform''s trainer did not join, or took the seat';
    end if;
    if not exists (select 1 from memberships m join orgs o on o.id = m.org_id
                    where o.slug = 'mara-69' and m.role = 'owner'
                      and m.user_id = '69696969-0000-0000-0000-000000000006')
       or not exists (select 1 from memberships m join orgs o on o.id = m.org_id
                       where o.slug = 'coumba-69' and m.role = 'owner'
                         and m.user_id = '69696969-0000-0000-0000-000000000004')
       or not exists (select 1 from memberships
                       where org_id = '69000000-0000-0000-0000-000000000005' and role = 'owner'
                         and user_id = '69696969-0000-0000-0000-000000000006') then
        raise exception 'FAIL: a business opened (create_org, an application approved, a showcase) has no owner';
    end if;
    raise notice 'PASS: assign_trainer, create_org, approve_org_application and showcase_join still make their grants';
end $$;

\echo ''
\echo '--- TEST 17: gifts are not the week''s on Le Chemin; a bought tool stays bought; « Offert par Mara » on the team ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000006';
select platform_give_cauris('69000000-0000-0000-0000-000000000003', 40, 'Encore') is not null;
select platform_give_unlock('69000000-0000-0000-0000-000000000003', 'accounting', cauris_today() + 60) is not null;
select platform_give_unlock('69000000-0000-0000-0000-000000000003', 'team_access', cauris_today() + 5) is not null;
commit;
-- Read as the farmer (the claim), by the database's own role: the ledger
-- has no policy for the app, and the test sums it beside path_state.
begin;
set local "request.jwt.claim.sub" = '69696969-0000-0000-0000-000000000007';
do $$
declare
    v_org  uuid := '69000000-0000-0000-0000-000000000003';
    v_old  int;
    v_gift int;
    p      jsonb := path_state('69000000-0000-0000-0000-000000000003');
begin
    -- 097's sum, and what Mara gave this week.
    select coalesce(sum(delta), 0) into v_old from cauris_ledger
     where org_id = v_org and delta > 0
       and reason not in ('prize', 'expired', 'spent')
       and created_at >= cauris_week_start();
    select coalesce(sum(delta), 0) into v_gift from cauris_ledger
     where org_id = v_org and delta > 0 and reason in ('gift', 'promo')
       and created_at >= cauris_week_start();
    if v_gift < 40 or (p ->> 'week')::int <> v_old - v_gift then
        raise exception 'FAIL: Le Chemin''s week reads % (gifts % of %)', p ->> 'week', v_gift, v_old;
    end if;
    if (select gifted_by from cauris_unlocks where org_id = v_org and feature = 'accounting') is not null
       or (select until from cauris_unlocks where org_id = v_org and feature = 'accounting')
          < (cauris_today() + 61)::timestamp at time zone 'Africa/Ouagadougou' then
        raise exception 'FAIL: the tool the farm bought was relabelled, or not lengthened';
    end if;
    if not (feature_states(v_org) -> 'team' ->> 'gift')::boolean then
        raise exception 'FAIL: the team given by Mara does not say so';
    end if;
    raise notice 'PASS: gifts out of the week; a bought tool lengthened, still bought; the team says « Offert par Mara »';
end $$;
commit;
