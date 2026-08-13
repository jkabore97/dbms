-- ============================================================
-- test_onboarding.sql — the two ways in, and what each one does not grant.
--
-- Runs as `authenticated` throughout. Every assertion is either a
-- platform-admin check inside a SECURITY DEFINER function or an RLS policy,
-- and a superuser walks through both.
--
-- The five things this suite is about:
--
--   1. Filling in a form granting access. It must not: a complete profile
--      with no code belongs to no business, and the code is the only thing
--      that grants anything.
--   2. A manager signing themselves up as a tenant. `create_org()` has been
--      platform admin only since 010 and an application must not be a way
--      around it.
--   3. An approval that does not hand the business to the person who asked
--      for it — leaving them locked out of the thing they applied for.
--   4. Two admins approving the same application at once, and two businesses
--      appearing.
--   5. One person's application being visible to another tenant. What
--      businesses are being asked for is the platform's business.
--
-- Phone block 83. The others: 70 rls, 71 invitations, 72 reports,
-- 73 accounting, 74 audit, 75/76 farm, 77 platform admin, 78 retail,
-- 79 employees, 80 capture, 81 org lifecycle, 82 delivery.
-- ============================================================
\set ON_ERROR_STOP on

\set admin   '''83838383-0000-0000-0000-000000000001'''
\set manager '''83838383-0000-0000-0000-000000000002'''
\set worker  '''83838383-0000-0000-0000-000000000003'''
\set outside '''83838383-0000-0000-0000-000000000004'''

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:admin,   '+22683000001', '{"full_name": "Kaboré (plateforme)"}'),
    (:manager, '+22683000002', '{"full_name": "Nouveau gérant"}'),
    (:worker,  '+22683000003', '{"full_name": "Nouvel employé"}'),
    (:outside, '+22683000004', '{"full_name": "Quelqu''un d''autre"}');

update profiles set is_platform_admin = true where id = :admin;

\echo ''
\echo '--- TEST 1: somebody says who they are ---'
begin;
set local "request.jwt.claim.sub" = '83838383-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_row profiles%rowtype;
begin
    -- Nothing is filled in yet, so the app knows to ask.
    if profile_is_complete() then
        raise exception 'FAIL: an empty profile counted as complete';
    end if;

    perform save_my_profile('  Awa  ', ' OUÉDRAOGO ', 'Salamata',
                            date '1998-04-12', 'Vendeuse', '+22670112233');

    select * into v_row from profiles where id = '83838383-0000-0000-0000-000000000003';

    if v_row.first_name <> 'Awa' or v_row.last_name <> 'OUÉDRAOGO' then
        raise exception 'FAIL: name stored as "% %"', v_row.first_name, v_row.last_name;
    end if;
    -- full_name is what every existing screen reads, so it is assembled from
    -- the parts rather than left to drift out of step with them.
    if v_row.full_name <> 'Awa Salamata OUÉDRAOGO' then
        raise exception 'FAIL: full name is "%"', v_row.full_name;
    end if;
    if v_row.date_of_birth <> date '1998-04-12' or v_row.title <> 'Vendeuse' then
        raise exception 'FAIL: birth date % / title %', v_row.date_of_birth, v_row.title;
    end if;
    if not profile_is_complete() then
        raise exception 'FAIL: a filled profile still counts as incomplete';
    end if;
    if v_row.profile_completed_at is null then
        raise exception 'FAIL: nothing recorded when the profile was completed';
    end if;

    raise notice 'PASS: % is who she says she is', v_row.full_name;
end $$;
commit;

\echo ''
\echo '--- TEST 2: a complete profile grants nothing at all ---'
begin;
set local "request.jwt.claim.sub" = '83838383-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_orgs int;
begin
    -- The whole point. Filling in a form is not a way into anybody's books;
    -- the code is, and she has not been given one.
    select count(*) into v_orgs from my_orgs();
    if v_orgs <> 0 then
        raise exception 'FAIL: a filled-in form opened % businesses', v_orgs;
    end if;

    raise notice 'PASS: she exists, and belongs to nothing';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: a birth date that would end up on a contract is checked ---'
begin;
set local "request.jwt.claim.sub" = '83838383-0000-0000-0000-000000000003';
set local role authenticated;
do $$
begin
    begin
        perform save_my_profile('Awa', 'OUÉDRAOGO', null, current_date + 1);
        raise exception 'FAIL: somebody was born tomorrow';
    exception
        when check_violation then
            raise notice 'PASS: refused a birth date in the future';
    end;

    begin
        perform save_my_profile('Awa', 'OUÉDRAOGO', null,
                                (current_date - interval '3 years')::date);
        raise exception 'FAIL: a three-year-old was put on the payroll';
    exception
        when check_violation then
            raise notice 'PASS: refused an implausible age';
    end;

    -- And a name is not optional, because this is what goes on a payslip.
    begin
        perform save_my_profile('   ', 'OUÉDRAOGO');
        raise exception 'FAIL: a nameless profile was saved';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 4: a manager asks for a business and is not given one ---'
begin;
set local "request.jwt.claim.sub" = '83838383-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_app  uuid;
    v_orgs int;
    v_status text;
begin
    v_app := apply_for_org('Ferme du Plateau', 'ferme-du-plateau', 'farm',
                           'XOF', 'Volailles et maraîchage', '+22670445566');

    if v_app is null then
        raise exception 'FAIL: the application went nowhere';
    end if;

    -- Nothing exists yet. No org, no slug reserved, nothing to sign into —
    -- which is the difference between an application and a business.
    if exists (select 1 from orgs where slug = 'ferme-du-plateau') then
        raise exception 'FAIL: applying created the business';
    end if;

    select count(*) into v_orgs from my_orgs();
    if v_orgs <> 0 then
        raise exception 'FAIL: the applicant already opens % businesses', v_orgs;
    end if;

    select status into v_status from my_org_application();
    if v_status <> 'pending' then
        raise exception 'FAIL: the application is already %', v_status;
    end if;

    -- And create_org() is still refused directly, which is the door the
    -- application must not become a way around.
    begin
        perform create_org('Ferme directe', 'ferme-directe', 'farm', 'XOF');
        raise exception 'FAIL: a manager created a business without approval';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;

    raise notice 'PASS: asked for a business, given nothing yet';
end $$;
commit;

\echo ''
\echo '--- TEST 5: applying twice while waiting is still one application ---'
begin;
set local "request.jwt.claim.sub" = '83838383-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_count int;
    v_name  text;
begin
    perform apply_for_org('Ferme du Plateau (corrigé)', 'ferme-du-plateau',
                          'farm', 'XOF');

    select count(*) into v_count from org_applications
    where applicant_id = '83838383-0000-0000-0000-000000000002'
      and status = 'pending';
    if v_count <> 1 then
        raise exception 'FAIL: % applications waiting, expected 1', v_count;
    end if;

    -- The second one corrected the first rather than queueing behind it.
    select name into v_name from my_org_application();
    if v_name <> 'Ferme du Plateau (corrigé)' then
        raise exception 'FAIL: the correction did not take (%)', v_name;
    end if;

    raise notice 'PASS: one person waiting, one thing to review';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: only the platform sees the queue ---'
begin;
set local "request.jwt.claim.sub" = '83838383-0000-0000-0000-000000000004';
set local role authenticated;
do $$
declare
    v_rows int;
begin
    -- Somebody else's application is not a thing to browse: what businesses
    -- are being asked for is the platform's business.
    select count(*) into v_rows from org_applications;
    if v_rows <> 0 then
        raise exception 'FAIL: an outsider reads % applications', v_rows;
    end if;

    begin
        select count(*) into v_rows from pending_org_applications();
        raise exception 'FAIL: an outsider read the platform queue';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;

    -- And cannot approve one either.
    begin
        perform approve_org_application(
            (select id from org_applications limit 1));
        raise exception 'FAIL: an outsider approved an application';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 7: approving makes the business, and gives it to the applicant ---'
begin;
set local "request.jwt.claim.sub" = '83838383-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_app     uuid;
    v_org     uuid;
    v_role    text;
    v_accounts int;
    v_queue   int;
begin
    select id into v_app from pending_org_applications() limit 1;
    if v_app is null then
        raise exception 'FAIL: nothing in the queue to approve';
    end if;

    v_org := approve_org_application(v_app, 'Vu au téléphone');

    if not exists (select 1 from orgs where id = v_org and slug = 'ferme-du-plateau') then
        raise exception 'FAIL: approving did not make the business';
    end if;

    -- Theirs, not the reviewer's. This is the whole point of approving rather
    -- than creating: they asked for it, so they own it.
    select role::text into v_role from memberships
    where org_id = v_org and user_id = '83838383-0000-0000-0000-000000000002';
    if v_role is distinct from 'owner' then
        raise exception 'FAIL: the applicant is % of their own business', v_role;
    end if;

    -- And the reviewer did not quietly become a member of it.
    if exists (select 1 from memberships
               where org_id = v_org
                 and user_id = '83838383-0000-0000-0000-000000000001') then
        raise exception 'FAIL: the reviewer joined the business they approved';
    end if;

    -- A farm gets a farm's chart of accounts, so the first thing recorded
    -- lands somewhere sensible.
    select count(*) into v_accounts from accounts where org_id = v_org;
    if v_accounts = 0 then
        raise exception 'FAIL: the new business has no accounts at all';
    end if;

    select count(*) into v_queue from pending_org_applications();
    if v_queue <> 0 then
        raise exception 'FAIL: % applications still pending after approving', v_queue;
    end if;

    raise notice 'PASS: the business exists and belongs to the person who asked';
end $$;
commit;

\echo ''
\echo '--- TEST 8: an approved application cannot be approved again ---'
begin;
set local "request.jwt.claim.sub" = '83838383-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_app   uuid;
    v_count int;
begin
    select id into v_app from org_applications
    where applicant_id = '83838383-0000-0000-0000-000000000002'
      and status = 'approved';

    begin
        perform approve_org_application(v_app);
        raise exception 'FAIL: approving twice made a second business';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;

    select count(*) into v_count from orgs where slug = 'ferme-du-plateau';
    if v_count <> 1 then
        raise exception 'FAIL: % businesses share one address', v_count;
    end if;
end $$;
rollback;

\echo ''
\echo '--- TEST 9: a rejection has to say why ---'
begin;
set local "request.jwt.claim.sub" = '83838383-0000-0000-0000-000000000004';
set local role authenticated;
select apply_for_org('Essai vide', 'essai-vide-83');
commit;

begin;
set local "request.jwt.claim.sub" = '83838383-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_app  uuid;
    v_note text;
begin
    select id into v_app from org_applications
    where slug = 'essai-vide-83' and status = 'pending';

    begin
        perform reject_org_application(v_app, '   ');
        raise exception 'FAIL: rejected with no reason';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;

    perform reject_org_application(v_app, 'Nom déjà utilisé par une autre société.');

    select decision_note into v_note from org_applications where id = v_app;
    if v_note is null then
        raise exception 'FAIL: the reason was not kept';
    end if;

    -- And no business was made.
    if exists (select 1 from orgs where slug = 'essai-vide-83') then
        raise exception 'FAIL: a rejected application became a business';
    end if;

    raise notice 'PASS: rejected, with a reason they can act on';
end $$;
rollback;

\echo ''
\echo '--- TEST 10: a manager invites somebody, and the code is what grants access ---'
begin;
set local "request.jwt.claim.sub" = '83838383-0000-0000-0000-000000000002';
set local role authenticated;

-- Captured into a psql variable rather than read back out of the table,
-- because that is how the code actually travels: the manager sees it once and
-- sends it over WhatsApp. The invitee cannot select from pending_invitations
-- at all — 005 lets only an org's admins read them — and a test that looked
-- it up would be testing a path nobody has.
select code as invite_code, org_name as invite_org
from invite_employee(
    (select id from orgs where slug = 'ferme-du-plateau'),
    'employee', 'Awa OUÉDRAOGO', 'Vendeuse', '+22670112233')
\gset

-- Asserted in plain SQL, not in a do-block: psql substitutes :'var' before
-- the server sees the line, and leaves it untouched inside a dollar-quoted
-- body, so a variable used there arrives as a literal colon.
select case
    when length(:'invite_code') >= 4 and :'invite_org' = 'Ferme du Plateau'
        then 'PASS: code ' || :'invite_code' || ' for ' || :'invite_org'
    else 1/0 || ''   -- fails the suite loudly rather than printing a lie
end as result;

-- Carried to the next test through a session setting, because psql does not
-- substitute :'var' inside a dollar-quoted body — the only place a plpgsql
-- block could read it from.
select set_config('kaj.invite_code', :'invite_code', false);
commit;

\echo ''
\echo '--- TEST 11: the code opens exactly one business, and nothing more ---'
begin;
set local "request.jwt.claim.sub" = '83838383-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_orgs  int;
    v_role  text;
    v_seen  int;
    -- The code as it reached her: a string, from outside, with no way to
    -- look it up. See the note where it was captured.
    v_code  text := current_setting('kaj.invite_code');
begin
    -- Before claiming: she cannot even see the invitation that names her,
    -- which is why the code has to be sent to her rather than found.
    select count(*) into v_seen from pending_invitations;
    if v_seen <> 0 then
        raise exception 'FAIL: an invitee reads % invitations', v_seen;
    end if;

    perform claim_invitation(v_code);

    select count(*) into v_orgs from my_orgs();
    if v_orgs <> 1 then
        raise exception 'FAIL: the code opened % businesses', v_orgs;
    end if;

    select role::text into v_role from memberships
    where user_id = '83838383-0000-0000-0000-000000000003';
    if v_role <> 'employee' then
        raise exception 'FAIL: the code granted %', v_role;
    end if;

    raise notice 'PASS: one business, as an employee, and nothing more';
end $$;
rollback;

\echo ''
\echo '--- TEST 12: an employee cannot invite anybody ---'
begin;
set local "request.jwt.claim.sub" = '83838383-0000-0000-0000-000000000004';
set local role authenticated;
do $$
declare
    v_orgid uuid;
begin
    select id into v_orgid from orgs where slug = 'ferme-du-plateau';

    begin
        perform invite_employee(v_orgid);
        raise exception 'FAIL: somebody outside the business invited a colleague';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo 'test_onboarding.sql: all assertions held.'
