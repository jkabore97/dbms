-- ============================================================
-- test_batch103.sql — the administration's doors (103). Phone block 10.
--
-- The claims, each for a shop, a farm and an association alike: no client
-- writes a business's row (its plan, its suspension, its address…) — every
-- change goes through a function that checks; nobody but the platform
-- names a super_admin, by a grant, a role change or an invitation, and an
-- invitation is for a role below the inviter's; nobody resets, signs out,
-- edits or removes the owner or the platform's people, and a removal
-- follows the ladder; the sign-in sweep claims only what the sign-in
-- proved, never a number typed on a profile; the console is the owner's
-- (and a super_admin's), the platform shows as « Mara »; a salary is never
-- one's own, the owner's to set for anyone else, shown to the owner and to
-- those above; a colleague who is not an admin reads no other profile, yet
-- still sees who sold; the payout, the Wave handle, the kind of business
-- and the invoice's identity are the owner's — an admin's save that leaves
-- them as they are still passes — and the owner hears when they change;
-- the team-access dial is the owner's; TRUNCATE belongs to nobody.
-- And the legitimate ways still work: the owner invites an admin, an admin
-- invites below, a role changed down the ladder, a member removed by
-- someone above, the platform naming a super_admin, a code claimed.
-- ============================================================
\set ON_ERROR_STOP on
-- The owner's numbers: earlier suites change them for their own fixtures.
update platform_settings set value = '1' where key = 'free_max_staff';
update platform_settings set value = '0' where key = 'path_gates_open';

\set owner   '''10101010-0000-0000-0000-000000000001'''
\set admin   '''10101010-0000-0000-0000-000000000002'''
\set emp     '''10101010-0000-0000-0000-000000000003'''
\set super   '''10101010-0000-0000-0000-000000000004'''
\set mara    '''10101010-0000-0000-0000-000000000005'''
\set farmer  '''10101010-0000-0000-0000-000000000006'''
\set fadmin  '''10101010-0000-0000-0000-000000000007'''
\set treas   '''10101010-0000-0000-0000-000000000008'''
\set aadmin  '''10101010-0000-0000-0000-000000000009'''
\set eve     '''10101010-0000-0000-0000-000000000010'''
\set newbie  '''10101010-0000-0000-0000-000000000011'''
\set unv     '''10101010-0000-0000-0000-000000000012'''
\set trainer '''10101010-0000-0000-0000-000000000013'''
\set shop    '''10000000-0000-0000-0000-000000000001'''
\set farm    '''10000000-0000-0000-0000-000000000002'''
\set assoc   '''10000000-0000-0000-0000-000000000003'''

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
-- profiles as it is live (032): a column grant, not the table's.
revoke update on profiles from authenticated;
grant update (full_name, first_name, middle_name, last_name, date_of_birth, title,
              phone, preferred_locale) on profiles to authenticated;
-- Earlier suites re-apply older migrations over 103's functions and hand the
-- app's roles every table: 103 again, so what follows tests its own.
\i database/migrations/103_admin_security.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,   '+22610000001', '{"full_name": "Patronne"}'),
    (:admin,   '+22610000002', '{"full_name": "Adjointe"}'),
    (:emp,     '+22610000003', '{"full_name": "Vendeuse"}'),
    (:super,   '+22610000004', '{"full_name": "Super"}'),
    (:mara,    '+22610000005', '{"full_name": "Mara"}'),
    (:farmer,  '+22610000006', '{"full_name": "Fermier"}'),
    (:fadmin,  '+22610000007', '{"full_name": "Chef de ferme"}'),
    (:treas,   '+22610000008', '{"full_name": "Trésorière"}'),
    (:aadmin,  '+22610000009', '{"full_name": "Secrétaire"}'),
    (:eve,     null,           '{"full_name": "Eve"}'),
    (:newbie,  '+22610000099', '{"full_name": "Nouvelle"}'),
    (:trainer, '+22610000013', '{"full_name": "Formatrice"}');
-- A number the sign-in never proved.
insert into auth.users (id, phone, phone_confirmed_at, raw_user_meta_data) values
    (:unv, '+22610000097', null, '{"full_name": "Pas vérifiée"}');
update profiles set is_platform_admin = true where id = :mara;
update profiles set is_trainer = true where id = :trainer;
insert into orgs (id, name, slug, profile, default_currency, plan, plan_note, wave_payout_number, tax_id) values
    (:shop,  'Boutique 10', 'boutique-10', 'retail',      'XOF', 'pro', 'note privée', '+22610000001', 'IFU-10'),
    (:farm,  'Ferme 10',    'ferme-10',    'farm',        'XOF', 'pro', null, null, null),
    (:assoc, 'Entraide 10', 'entraide-10', 'association', 'XOF', 'pro', null, null, 'IFU-A10');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility, is_trainer) values
    (:shop,  :owner,   'owner',       'org', :shop,  'full', false),
    (:shop,  :admin,   'admin',       'org', :shop,  'full', false),
    (:shop,  :emp,     'employee',    'org', :shop,  'full', false),
    (:shop,  :super,   'super_admin', 'org', :shop,  'full', false),
    -- A platform admin's row in a business, as the forced insert made it.
    (:shop,  :mara,    'employee',    'org', :shop,  'full', false),
    (:shop,  :trainer, 'observer',    'org', :shop,  'full', true),
    (:farm,  :farmer,  'owner',       'org', :farm,  'full', false),
    (:farm,  :fadmin,  'admin',       'org', :farm,  'full', false),
    (:assoc, :treas,   'owner',       'org', :assoc, 'full', false),
    (:assoc, :aadmin,  'admin',       'org', :assoc, 'full', false);
insert into auth.sessions (user_id) values (:emp), (:mara), (:owner);
-- A sale the owner rang up, for the colleague's list.
insert into sales (org_id, total, recorded_by) values (:shop, 500, :owner);
-- Three invitations addressed to numbers, none claimed.
insert into pending_invitations (org_id, role, scope_kind, scope_id, code, phone, created_by) values
    (:shop, 'employee', 'org', :shop, 'B103-0098', '+22610000098', :owner),
    (:shop, 'employee', 'org', :shop, 'B103-0099', '+22610000099', :owner),
    (:shop, 'employee', 'org', :shop, 'B103-0097', '+22610000097', :owner);

\echo ''
\echo '--- TEST 1: no client writes a business row — a shop, a farm, an association ---'
do $$
declare
    r record;
begin
    for r in select * from (values
        ('10101010-0000-0000-0000-000000000002'::uuid, '10000000-0000-0000-0000-000000000001'::uuid),
        ('10101010-0000-0000-0000-000000000007'::uuid, '10000000-0000-0000-0000-000000000002'::uuid),
        ('10101010-0000-0000-0000-000000000009'::uuid, '10000000-0000-0000-0000-000000000003'::uuid)) v(who, org)
    loop
        perform set_config('request.jwt.claim.sub', r.who::text, true);
        execute 'set local role authenticated';
        begin
            update orgs set plan = 'pro', plan_until = '2099-01-01', suspended_at = null,
                            showcase = true, photo_slots = 999, slug = 'x'
             where id = r.org;
            raise exception 'FAIL: an admin PATCHed their business row';
        exception when insufficient_privilege then null;
        end;
        begin
            delete from orgs where id = r.org;
            raise exception 'FAIL: an admin deleted their business row';
        exception when insufficient_privilege then null;
        end;
        begin
            insert into orgs (name, slug, profile) values ('Moi', 'moi-103', 'retail');
            raise exception 'FAIL: a business was created by a direct insert';
        exception when insufficient_privilege then null;
        end;
        -- The door still opens: a name changed through update_org.
        perform update_org(r.org, p_name => 'Renommée');
        execute 'reset role';
    end loop;
    if (select count(*) from orgs where name = 'Renommée'
          and id in ('10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002',
                     '10000000-0000-0000-0000-000000000003')) <> 3
       or exists (select 1 from orgs where id = '10000000-0000-0000-0000-000000000001'
                    and (plan_until is not null or showcase or photo_slots > 0 or slug <> 'boutique-10')) then
        raise exception 'FAIL: the rows moved, or the door did not open';
    end if;
    if has_table_privilege('anon', 'orgs', 'UPDATE') or has_table_privilege('authenticated', 'orgs', 'UPDATE')
       or exists (select 1 from pg_policies where tablename = 'orgs' and cmd = 'UPDATE') then
        raise exception 'FAIL: orgs is still writable by the app''s roles';
    end if;
    raise notice 'PASS: a shop, a farm and an association admin PATCH nothing; update_org still renames';
end $$;
update orgs set name = 'Boutique 10' where id = :shop;
update orgs set name = 'Ferme 10' where id = :farm;
update orgs set name = 'Entraide 10' where id = :assoc;

\echo ''
\echo '--- TEST 2: nobody but the platform names a super_admin; a row never moves ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000002';
do $$
declare v_mine uuid;
begin
    select id into v_mine from memberships
     where user_id = '10101010-0000-0000-0000-000000000002'
       and org_id = '10000000-0000-0000-0000-000000000001';
    begin
        update memberships set role = 'super_admin' where id = v_mine;
        raise exception 'FAIL: an admin promoted themself by a PATCH';
    exception when insufficient_privilege then null;
    end;
    begin
        insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
        values ('10000000-0000-0000-0000-000000000001', '10101010-0000-0000-0000-000000000002',
                'super_admin', 'org', '10000000-0000-0000-0000-000000000001', 'full');
        raise exception 'FAIL: an admin granted themself super_admin';
    exception when insufficient_privilege then null;
    end;
    begin
        perform set_membership_role(v_mine, 'super_admin');
        raise exception 'FAIL: set_membership_role named a super_admin';
    exception when raise_exception then
        if sqlerrm <> 'Seule la plateforme nomme ou retire un super administrateur' then raise; end if;
    end;
end $$;
-- The owner may not either, and an employee is changed down the ladder.
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000001';
do $$
declare v_emp uuid;
begin
    select id into v_emp from memberships
     where user_id = '10101010-0000-0000-0000-000000000003'
       and org_id = '10000000-0000-0000-0000-000000000001';
    begin
        perform set_membership_role(v_emp, 'super_admin');
        raise exception 'FAIL: the owner named a super_admin';
    exception when raise_exception then
        if sqlerrm not like 'Seule la plateforme%' then raise; end if;
    end;
    perform set_membership_role(v_emp, 'manager');
    if (select role from memberships where id = v_emp) <> 'manager' then
        raise exception 'FAIL: the owner could not change an employee''s role';
    end if;
end $$;
-- The platform names one.
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000005';
do $$
declare v_emp uuid;
begin
    select id into v_emp from memberships
     where user_id = '10101010-0000-0000-0000-000000000003'
       and org_id = '10000000-0000-0000-0000-000000000001';
    perform set_membership_role(v_emp, 'super_admin');
    if (select role from memberships where id = v_emp) <> 'super_admin' then
        raise exception 'FAIL: the platform could not name a super_admin';
    end if;
    raise notice 'PASS: an admin and the owner name no super_admin (PATCH, insert, role change); the platform does; down the ladder works';
end $$;
rollback;

-- The trigger holds even where a table grant is handed back.
begin;
grant insert, update on memberships to authenticated;
set local role authenticated;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000002';
do $$ begin
    begin
        insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
        values ('10000000-0000-0000-0000-000000000001', '10101010-0000-0000-0000-000000000002',
                'super_admin', 'org', '10000000-0000-0000-0000-000000000001', 'full');
        raise exception 'FAIL: the trigger let a super_admin in';
    exception when insufficient_privilege then
        if sqlerrm not like 'Seule la plateforme%' then raise; end if;
    end;
    begin
        update memberships set user_id = '10101010-0000-0000-0000-000000000010'
         where user_id = '10101010-0000-0000-0000-000000000003'
           and org_id = '10000000-0000-0000-0000-000000000001';
        raise exception 'FAIL: a grant was moved to another person';
    exception when insufficient_privilege then
        if sqlerrm not like 'Un accès ne passe pas%' then raise; end if;
    end;
    raise notice 'PASS: with a grant handed back, the trigger still refuses super_admin and a moved row';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: an invitation is for a role below the inviter''s, never super_admin ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000002';
do $$ begin
    begin
        perform invite_employee('10000000-0000-0000-0000-000000000001', 'super_admin');
        raise exception 'FAIL: an admin invited a super_admin';
    exception when raise_exception then
        if sqlerrm <> 'Cette responsabilité ne se donne pas par une invitation' then raise; end if;
    end;
    begin
        perform invite_employee('10000000-0000-0000-0000-000000000001', 'admin');
        raise exception 'FAIL: an admin invited a peer admin';
    exception when raise_exception then
        if sqlerrm not like 'Vous ne pouvez inviter que%' then raise; end if;
    end;
    begin
        insert into pending_invitations (org_id, role, scope_kind, scope_id, code, created_by)
        values ('10000000-0000-0000-0000-000000000001', 'super_admin', 'org',
                '10000000-0000-0000-0000-000000000001', 'B103-SUPR',
                '10101010-0000-0000-0000-000000000002');
        raise exception 'FAIL: an invitation was written directly';
    exception when insufficient_privilege then null;
    end;
    -- Below: a manager.
    perform invite_employee('10000000-0000-0000-0000-000000000001', 'manager');
end $$;
-- The farm's admin likewise; the association's owner invites an admin.
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000007';
do $$ begin
    begin
        perform invite_employee('10000000-0000-0000-0000-000000000002', 'super_admin');
        raise exception 'FAIL: a farm admin invited a super_admin';
    exception when raise_exception then null;
    end;
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000008';
do $$ begin
    perform invite_employee('10000000-0000-0000-0000-000000000003', 'admin');
    if not exists (select 1 from pending_invitations
                    where org_id = '10000000-0000-0000-0000-000000000003' and role = 'admin') then
        raise exception 'FAIL: the owner could not invite an admin';
    end if;
    raise notice 'PASS: super_admin and a peer refused (function and table); below, and the owner''s admin, invited';
end $$;
rollback;

begin;
grant insert, update on pending_invitations to authenticated;
set local role authenticated;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000002';
do $$ begin
    begin
        insert into pending_invitations (org_id, role, scope_kind, scope_id, code, created_by)
        values ('10000000-0000-0000-0000-000000000001', 'admin', 'org',
                '10000000-0000-0000-0000-000000000001', 'B103-PEER',
                '10101010-0000-0000-0000-000000000002');
        raise exception 'FAIL: the seat trigger let a peer invitation in';
    exception when insufficient_privilege then
        if sqlerrm not like 'Vous ne pouvez inviter que%' then raise; end if;
    end;
    raise notice 'PASS: with a grant handed back, the trigger still refuses a peer invitation';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: nobody manages the owner, the platform''s people or a trainer ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000004';
do $$ begin
    if manages_user('10101010-0000-0000-0000-000000000001') then
        raise exception 'FAIL: a super_admin manages the owner (password reset)';
    end if;
    if manages_user('10101010-0000-0000-0000-000000000005') then
        raise exception 'FAIL: a super_admin manages the platform admin';
    end if;
    if not manages_user('10101010-0000-0000-0000-000000000002') then
        raise exception 'FAIL: a super_admin no longer manages an admin';
    end if;
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000001';
do $$ begin
    if manages_user('10101010-0000-0000-0000-000000000005') then
        raise exception 'FAIL: the owner manages a platform admin seated as employee';
    end if;
    if manages_user('10101010-0000-0000-0000-000000000013') then
        raise exception 'FAIL: the owner manages the platform''s trainer';
    end if;
    if not manages_user('10101010-0000-0000-0000-000000000003') then
        raise exception 'FAIL: the owner no longer manages an employee';
    end if;
    if can_delete_user('10101010-0000-0000-0000-000000000005') then
        raise exception 'FAIL: the owner may delete a platform admin';
    end if;
    begin
        perform admin_save_member_profile('10101010-0000-0000-0000-000000000005', 'X', 'Y');
        raise exception 'FAIL: the owner rewrote a platform admin''s profile';
    exception when raise_exception then null;
    end;
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000004';
do $$ begin
    begin
        perform admin_save_member_profile('10101010-0000-0000-0000-000000000001', 'X', 'Y', p_phone => '+22610000098');
        raise exception 'FAIL: a super_admin rewrote the owner''s profile';
    exception when raise_exception then
        if sqlerrm not like 'Vous ne pouvez pas modifier%' then raise; end if;
    end;
    perform admin_save_member_profile('10101010-0000-0000-0000-000000000002', 'Ada', 'Adjointe');
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000005';
do $$ begin
    if not manages_user('10101010-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the platform no longer helps an owner';
    end if;
    raise notice 'PASS: owner, platform admin and trainer out of reach; the ladder below, and the platform, still reach';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: a removal follows the ladder, and never takes the owner ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000002';
do $$
declare v_n int;
begin
    begin
        delete from memberships where user_id = '10101010-0000-0000-0000-000000000004'
           and org_id = '10000000-0000-0000-0000-000000000001';
        raise exception 'FAIL: an admin removed the super_admin';
    exception when insufficient_privilege then null;
    end;
    begin
        delete from memberships where user_id = '10101010-0000-0000-0000-000000000001'
           and org_id = '10000000-0000-0000-0000-000000000001';
        get diagnostics v_n = row_count;
        if v_n > 0 then raise exception 'FAIL: an admin removed the owner'; end if;
    exception when insufficient_privilege then null;
    end;
    begin
        perform revoke_membership((select id from memberships
                                    where user_id = '10101010-0000-0000-0000-000000000013'));
        raise exception 'FAIL: an admin removed the platform''s trainer';
    exception when insufficient_privilege then null;
    end;
    -- Below: the employee, by today's app's delete.
    delete from memberships where user_id = '10101010-0000-0000-0000-000000000003'
       and org_id = '10000000-0000-0000-0000-000000000001';
    if exists (select 1 from memberships where user_id = '10101010-0000-0000-0000-000000000003') then
        raise exception 'FAIL: the admin could not remove an employee';
    end if;
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000001';
do $$ begin
    begin
        delete from memberships where user_id = '10101010-0000-0000-0000-000000000001'
           and org_id = '10000000-0000-0000-0000-000000000001';
        raise exception 'FAIL: the owner left the business ownerless';
    exception when insufficient_privilege then
        if sqlerrm not like 'Le propriétaire ne se retire pas%' then raise; end if;
    end;
    -- The new door: the owner removes the admin.
    perform revoke_membership((select id from memberships
                                where user_id = '10101010-0000-0000-0000-000000000002'));
    if exists (select 1 from memberships where user_id = '10101010-0000-0000-0000-000000000002') then
        raise exception 'FAIL: revoke_membership did not remove the admin';
    end if;
end $$;
-- The farm admin leaves their own grant.
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000007';
do $$ begin
    perform revoke_membership((select id from memberships
                                where user_id = '10101010-0000-0000-0000-000000000007'));
    if exists (select 1 from memberships where user_id = '10101010-0000-0000-0000-000000000007') then
        raise exception 'FAIL: an admin could not leave';
    end if;
    raise notice 'PASS: no super_admin, owner or trainer removed from below; the employee, the admin and one''s own grant are';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: a member signed out only by someone above them ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000002';
do $$ begin
    begin
        perform sign_out_member('10000000-0000-0000-0000-000000000001', '10101010-0000-0000-0000-000000000005');
        raise exception 'FAIL: an admin signed the platform admin out everywhere';
    exception when raise_exception then
        if sqlerrm not like 'Vous ne pouvez déconnecter%' then raise; end if;
    end;
    if sign_out_member('10000000-0000-0000-0000-000000000001', '10101010-0000-0000-0000-000000000003') <> 1 then
        raise exception 'FAIL: the admin could not sign the employee out';
    end if;
    raise notice 'PASS: the platform admin out of reach; the employee signed out';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: the sweep claims what the sign-in proved, not a typed number ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000010';
do $$ begin
    begin
        update profiles set phone = '+22610000098' where id = '10101010-0000-0000-0000-000000000010';
        raise exception 'FAIL: a number was typed onto a profile directly';
    exception when insufficient_privilege then null;
    end;
end $$;
reset role;
-- As if typed before 103 (or through save_my_profile): it still proves nothing.
update profiles set phone = '+22610000098' where id = :eve;
set local role authenticated;
do $$ begin
    if claim_my_invitations() <> 0 then
        raise exception 'FAIL: a typed number swept an invitation';
    end if;
    -- With the code, the number on the profile still counts (the code is the secret).
    perform claim_invitation('B103-0098');
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000012';
do $$ begin
    if claim_my_invitations() <> 0 then
        raise exception 'FAIL: an unproved number swept an invitation';
    end if;
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000011';
do $$ begin
    if claim_my_invitations() <> 1 then
        raise exception 'FAIL: the proved number did not sweep its invitation';
    end if;
end $$;
reset role;
do $$ begin
    if not exists (select 1 from memberships where user_id = '10101010-0000-0000-0000-000000000011')
       or not exists (select 1 from memberships where user_id = '10101010-0000-0000-0000-000000000010')
       or exists (select 1 from memberships where user_id = '10101010-0000-0000-0000-000000000012') then
        raise exception 'FAIL: the memberships do not match the proofs';
    end if;
    raise notice 'PASS: a typed number and an unproved one sweep nothing; a proved one does; a code still claims';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: the console is the owner''s; the platform shows as « Mara » ---'
-- The platform renames the shop: a log line by a platform admin.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000005';
select update_org('10000000-0000-0000-0000-000000000001', p_name => 'Boutique Dix') is not null as renamed;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000002';
do $$ begin
    if exists (select 1 from audit_log_page('10000000-0000-0000-0000-000000000001'))
       or exists (select 1 from audit_log_actors('10000000-0000-0000-0000-000000000001'))
       or exists (select 1 from org_database_overview('10000000-0000-0000-0000-000000000001'))
       or exists (select 1 from org_table_columns('10000000-0000-0000-0000-000000000001', 'orgs')) then
        raise exception 'FAIL: a plain admin reads the console';
    end if;
    begin
        perform 1 from audit_log limit 1;
        raise exception 'FAIL: the log is readable as rows';
    exception when insufficient_privilege then null;
    end;
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000001';
do $$
declare r record;
begin
    select * into r from audit_log_page('10000000-0000-0000-0000-000000000001', p_table => 'orgs') limit 1;
    if r.id is null then
        raise exception 'FAIL: the owner reads no console';
    end if;
    if exists (select 1 from audit_log_page('10000000-0000-0000-0000-000000000001', 500) p
                where p.actor_id = '10101010-0000-0000-0000-000000000005')
       or exists (select 1 from audit_log_actors('10000000-0000-0000-0000-000000000001') a
                   where a.actor_id = '10101010-0000-0000-0000-000000000005')
       or not exists (select 1 from audit_log_page('10000000-0000-0000-0000-000000000001', 500) p
                       where p.actor_label = 'Mara' and p.actor_id is null) then
        raise exception 'FAIL: the platform admin is named by id to the owner';
    end if;
    if not exists (select 1 from org_database_overview('10000000-0000-0000-0000-000000000001')) then
        raise exception 'FAIL: the owner reads no database overview';
    end if;
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000004';
do $$ begin
    if not exists (select 1 from audit_log_page('10000000-0000-0000-0000-000000000001')) then
        raise exception 'FAIL: the super_admin reads no console';
    end if;
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000005';
do $$ begin
    if not exists (select 1 from audit_log_page('10000000-0000-0000-0000-000000000001', 500) p
                    where p.actor_id = '10101010-0000-0000-0000-000000000005') then
        raise exception 'FAIL: the platform does not see its own';
    end if;
    raise notice 'PASS: a plain admin reads nothing; the owner and the super_admin read « Mara »; the platform its own id';
end $$;
rollback;
update orgs set name = 'Boutique 10' where id = :shop;

\echo ''
\echo '--- TEST 9: a salary — never one''s own, the owner''s to set, shown to those above ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000005';
select set_member_salary('10000000-0000-0000-0000-000000000001', '10101010-0000-0000-0000-000000000001', 90000) is not null as owner_paid;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000002';
do $$ begin
    begin
        perform set_member_salary('10000000-0000-0000-0000-000000000001', '10101010-0000-0000-0000-000000000002', 500000);
        raise exception 'FAIL: an admin set their own salary';
    exception when raise_exception then
        if sqlerrm <> 'Votre propre salaire ne se note pas ici' then raise; end if;
    end;
    begin
        perform set_member_salary('10000000-0000-0000-0000-000000000001', '10101010-0000-0000-0000-000000000001', 1);
        raise exception 'FAIL: an admin set the owner''s salary';
    exception when raise_exception then
        if sqlerrm not like 'Seul le propriétaire%' then raise; end if;
    end;
    begin
        perform set_member_salary('10000000-0000-0000-0000-000000000001', '10101010-0000-0000-0000-000000000004', 1);
        raise exception 'FAIL: an admin set the super_admin''s salary';
    exception when raise_exception then null;
    end;
    perform set_member_salary('10000000-0000-0000-0000-000000000001', '10101010-0000-0000-0000-000000000003', 40000);
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000001';
do $$ begin
    begin
        perform set_member_salary('10000000-0000-0000-0000-000000000001', '10101010-0000-0000-0000-000000000001', 1);
        raise exception 'FAIL: the owner set their own salary';
    exception when raise_exception then null;
    end;
    perform set_member_salary('10000000-0000-0000-0000-000000000001', '10101010-0000-0000-0000-000000000002', 60000);
    perform set_member_salary('10000000-0000-0000-0000-000000000001', '10101010-0000-0000-0000-000000000004', 70000);
end $$;
do $$
declare s jsonb := team_overview('10000000-0000-0000-0000-000000000001');
begin
    if (select count(*) from jsonb_array_elements(s -> 'members') m where m ->> 'salary' is not null) <> 4 then
        raise exception 'FAIL: the owner does not see every salary: %', s -> 'members';
    end if;
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000002';
do $$
declare s jsonb := team_overview('10000000-0000-0000-0000-000000000001');
        v_seen text;
begin
    select string_agg(m ->> 'user_id', ',' order by m ->> 'user_id') into v_seen
      from jsonb_array_elements(s -> 'members') m where m ->> 'salary' is not null;
    -- Their own and the employee's; not the owner's, not the super_admin's.
    if v_seen <> '10101010-0000-0000-0000-000000000002,10101010-0000-0000-0000-000000000003' then
        raise exception 'FAIL: the admin sees the salaries of %', v_seen;
    end if;
    raise notice 'PASS: never one''s own; the owner sets anyone''s and sees all; an admin sets and sees only below (and their own)';
end $$;
rollback;

\echo ''
\echo '--- TEST 10: a colleague reads no other profile, yet sees who sold ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000003';
do $$ begin
    if exists (select 1 from profiles where id <> '10101010-0000-0000-0000-000000000003') then
        raise exception 'FAIL: an employee reads a colleague''s profile (phone, birth date, platform flag)';
    end if;
    if not exists (select 1 from profiles where id = '10101010-0000-0000-0000-000000000003') then
        raise exception 'FAIL: an employee cannot read their own profile';
    end if;
    if (select sold_by from recent_sales('10000000-0000-0000-0000-000000000001') limit 1) is distinct from 'Patronne' then
        raise exception 'FAIL: the list no longer says who sold';
    end if;
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000002';
do $$ begin
    if not exists (select 1 from profiles where id = '10101010-0000-0000-0000-000000000003') then
        raise exception 'FAIL: an admin cannot read the team''s profiles';
    end if;
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000010';
do $$ begin
    if colleague_name('10101010-0000-0000-0000-000000000001') is not null then
        raise exception 'FAIL: an outsider reads a name';
    end if;
    raise notice 'PASS: own row only for an employee, the team for an admin, the seller named, nobody else''s name';
end $$;
rollback;

\echo ''
\echo '--- TEST 12: the money, the kind, the invoice — the owner''s; an unchanged save passes ---'
begin;
set local role authenticated;
-- The shop: the payout number and the Wave handle.
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000002';
do $$ begin
    begin
        perform set_wave_payout_number('10000000-0000-0000-0000-000000000001', '+22610000002');
        raise exception 'FAIL: an admin redirected the payout';
    exception when raise_exception then
        if sqlerrm not like 'Seul le propriétaire%' then raise; end if;
    end;
    begin
        perform set_org_wave('10000000-0000-0000-0000-000000000001', 'moi-wave');
        raise exception 'FAIL: an admin changed the Wave handle';
    exception when raise_exception then null;
    end;
    -- Today's settings form sends them back unchanged with every save.
    perform set_wave_payout_number('10000000-0000-0000-0000-000000000001', '+22610000001');
    perform set_org_wave('10000000-0000-0000-0000-000000000001', null);
    if (select org_private_details('10000000-0000-0000-0000-000000000001') ->> 'wave_payout_number') is not null then
        raise exception 'FAIL: an admin reads the payout number through the door';
    end if;
end $$;
-- The farm: its kind.
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000007';
do $$ begin
    begin
        perform update_org('10000000-0000-0000-0000-000000000002', p_profile => 'retail');
        raise exception 'FAIL: a farm admin changed the kind of business';
    exception when raise_exception then
        if sqlerrm not like 'Seul le propriétaire%' then raise; end if;
    end;
    perform update_org('10000000-0000-0000-0000-000000000002', p_profile => 'farm', p_name => 'Ferme Dix');
end $$;
-- The association: the invoice's identity (the contact lines stay an admin's).
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000009';
do $$ begin
    begin
        perform set_org_billing('10000000-0000-0000-0000-000000000003', p_tax_id => 'IFU-FAUX');
        raise exception 'FAIL: an association admin changed the tax id';
    exception when raise_exception then
        if sqlerrm not like 'Seul le propriétaire%' then raise; end if;
    end;
    perform set_org_billing('10000000-0000-0000-0000-000000000003',
        p_phone => '+22610000009', p_address => 'Ouaga', p_tax_id => 'IFU-A10');
end $$;
-- The owners can; the platform can, and the owner hears it.
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000001';
do $$ begin
    perform set_wave_payout_number('10000000-0000-0000-0000-000000000001', '+22610000011');
    if (select org_private_details('10000000-0000-0000-0000-000000000001') ->> 'wave_payout_number') <> '+22610000011'
       or (select org_private_details('10000000-0000-0000-0000-000000000001') ->> 'plan_note') is not null then
        raise exception 'FAIL: the owner''s door reads wrong';
    end if;
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000006';
select update_org('10000000-0000-0000-0000-000000000002', p_profile => 'retail') is not null as farmer_changed_kind;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000008';
select set_org_billing('10000000-0000-0000-0000-000000000003', p_tax_id => 'IFU-NOUVEAU') is null as treasurer_changed_tax;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000005';
do $$ begin
    perform set_wave_payout_number('10000000-0000-0000-0000-000000000001', '+22610000012');
    if (select org_private_details('10000000-0000-0000-0000-000000000001') ->> 'plan_note') <> 'note privée' then
        raise exception 'FAIL: the platform does not read its note';
    end if;
end $$;
reset role;
do $$ begin
    if (select wave_payout_number from orgs where id = '10000000-0000-0000-0000-000000000001') <> '+22610000012'
       or (select profile from orgs where id = '10000000-0000-0000-0000-000000000002') <> 'retail'
       or (select tax_id from orgs where id = '10000000-0000-0000-0000-000000000003') <> 'IFU-NOUVEAU'
       or (select phone from orgs where id = '10000000-0000-0000-0000-000000000003') <> '+22610000009' then
        raise exception 'FAIL: the legitimate changes did not land';
    end if;
    if (select count(*) from notifications
         where recipient_id = '10101010-0000-0000-0000-000000000001' and kind = 'payout_changed'
           and params ->> 'to' = 'shop') <> 1 then
        raise exception 'FAIL: the owner was not told (once) that the platform changed the payout';
    end if;
    raise notice 'PASS: shop payout, farm kind, association tax id refused to admins; unchanged saves pass; owners and the platform change them; the owner hears it';
end $$;
rollback;

\echo ''
\echo '--- TEST 14: the team-access dial is the owner''s ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000002';
do $$ begin
    begin
        insert into org_feature_rules (org_id, tier, feature, access)
        values ('10000000-0000-0000-0000-000000000001', 'employee', 'reports', 'hidden');
        raise exception 'FAIL: an admin turned the owner''s dial';
    exception when insufficient_privilege then null;
    end;
end $$;
set local "request.jwt.claim.sub" = '10101010-0000-0000-0000-000000000001';
insert into org_feature_rules (org_id, tier, feature, access)
values ('10000000-0000-0000-0000-000000000001', 'employee', 'reports', 'hidden');
do $$ begin
    if not exists (select 1 from org_feature_rules where org_id = '10000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the owner could not turn the dial';
    end if;
    raise notice 'PASS: the admin refused, the owner sets the dial';
end $$;
rollback;

\echo ''
\echo '--- TEST 16: TRUNCATE is nobody''s; the new doors are closed to the street ---'
do $$
declare v text;
begin
    select string_agg(c.relname, ', ') into v
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r'
       and (has_table_privilege('anon', c.oid, 'TRUNCATE')
            or has_table_privilege('authenticated', c.oid, 'TRUNCATE'));
    if v is not null then
        raise exception 'FAIL: TRUNCATE still held on %', v;
    end if;
    if has_function_privilege('anon', 'revoke_membership(uuid)', 'execute')
       or has_function_privilege('anon', 'org_private_details(uuid)', 'execute')
       or has_function_privilege('anon', 'colleague_name(uuid)', 'execute')
       or has_function_privilege('authenticated', 'org_rank_of(uuid, uuid)', 'execute')
       or has_function_privilege('authenticated', 'is_org_owner(uuid)', 'execute')
       or has_function_privilege('authenticated', 'notify_org_owners(uuid, text, text, jsonb)', 'execute')
       or not has_function_privilege('authenticated', 'revoke_membership(uuid)', 'execute')
       or not has_function_privilege('authenticated', 'org_private_details(uuid)', 'execute') then
        raise exception 'FAIL: a new function has the wrong grant';
    end if;
    raise notice 'PASS: no TRUNCATE for the app''s roles; the doors open to the signed-in, the helpers to nobody';
end $$;
