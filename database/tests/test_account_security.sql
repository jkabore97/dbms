-- ============================================================
-- test_account_security.sql — the Sécurité page's server side (075).
-- Phone block 46.
--
-- The claims: a new device rings the account's bell only when the account
-- already had one; each person sees and closes their own sessions only,
-- never this one by mistake; the history is the person's own; an owner's
-- lock rule binds the team and the strictest rule wins; an admin signs a
-- lost phone's member out, never an owner and never themselves.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''46464646-0000-0000-0000-000000000001'''
\set clerk '''46464646-0000-0000-0000-000000000002'''
\set other '''46464646-0000-0000-0000-000000000003'''
\set shop  '''46000000-0000-0000-0000-000000000001'''
\set shop2 '''46000000-0000-0000-0000-000000000002'''
\set s1    '''46aaaaaa-0000-0000-0000-000000000001'''
\set s2    '''46aaaaaa-0000-0000-0000-000000000002'''
\set s3    '''46aaaaaa-0000-0000-0000-000000000003'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22646000001', '{"full_name": "Propriétaire"}'),
    (:clerk, '+22646000002', '{"full_name": "Vendeuse"}'),
    (:other, '+22646000003', '{"full_name": "Étrangère"}');
insert into orgs (id, name, slug, profile, default_currency) values
    (:shop,  'Boutique Sûre',  'sure-46',  'retail', 'XOF'),
    (:shop2, 'Boutique Deux',  'deux-46',  'retail', 'XOF');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :owner, 'owner',    'org', :shop,  'full'),
    (:shop,  :clerk, 'employee', 'org', :shop,  'full'),
    (:shop2, :clerk, 'employee', 'org', :shop2, 'full');
insert into auth.sessions (id, user_id, user_agent, ip) values
    (:s1, :clerk, 'Mozilla/5.0 (Linux; Android 14) Chrome/141', '41.78.1.2'),
    (:s2, :clerk, 'Mozilla/5.0 (Windows NT 10.0) Chrome/141',   '41.78.1.3'),
    (:s3, :owner, 'Mozilla/5.0 (Linux; Android 13) Chrome/141', '41.78.1.4');


\echo ''
\echo '--- TEST 1: a new device rings the bell, but not the very first one ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '46464646-0000-0000-0000-000000000002';
do $$ begin
    if not register_device('device-aaaa-1111', 'Android · Chrome') then
        raise exception 'FAIL: the first device was not new';
    end if;
    if register_device('device-aaaa-1111', 'Android · Chrome') then
        raise exception 'FAIL: the same device was new twice';
    end if;
    if exists (select 1 from notifications where kind = 'new_device'
                and recipient_id = '46464646-0000-0000-0000-000000000002') then
        raise exception 'FAIL: the first device rang the bell';
    end if;
    perform register_device('device-bbbb-2222', 'Windows · Chrome');
    if (select count(*) from notifications where kind = 'new_device'
         and recipient_id = '46464646-0000-0000-0000-000000000002') <> 1 then
        raise exception 'FAIL: a second device did not ring the bell once';
    end if;
    if (select count(*) from my_devices()) <> 2 then
        raise exception 'FAIL: my_devices does not list both';
    end if;
    raise notice 'PASS: first device quiet, second rings once, both listed';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: my sessions only; this one cannot be closed by mistake ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '46464646-0000-0000-0000-000000000002';
set local "request.jwt.claims" = '{"session_id": "46aaaaaa-0000-0000-0000-000000000001"}';
do $$ begin
    if (select count(*) from my_sessions()) <> 2 then
        raise exception 'FAIL: the clerk sees % sessions', (select count(*) from my_sessions());
    end if;
    if not (select current from my_sessions() limit 1) then
        raise exception 'FAIL: this session is not first and marked current';
    end if;
    begin
        perform close_my_session('46aaaaaa-0000-0000-0000-000000000001');
        raise exception 'FAIL: this very session was closed';
    exception when others then
        if sqlerrm not like 'C''est cet appareil%' then raise; end if;
    end;
    begin
        perform close_my_session('46aaaaaa-0000-0000-0000-000000000003');
        raise exception 'FAIL: the owner''s session was closed by the clerk';
    exception when others then
        if sqlerrm not like 'Session introuvable%' then raise; end if;
    end;
    if close_my_other_sessions() <> 1 then
        raise exception 'FAIL: closing the others did not close exactly one';
    end if;
    if (select count(*) from my_sessions()) <> 1 then
        raise exception 'FAIL: other sessions remain';
    end if;
    if (select kind from my_security_events() limit 1) <> 'signed_out_others' then
        raise exception 'FAIL: the history did not record it';
    end if;
    raise notice 'PASS: own sessions only, current kept, others closed and logged';
end $$;
reset role;
do $$ begin
    if not exists (select 1 from auth.sessions where id = '46aaaaaa-0000-0000-0000-000000000003') then
        raise exception 'FAIL: the owner lost a session';
    end if;
end $$;
rollback;

\echo ''
\echo '--- TEST 3: the history is the person''s own; unknown events refused ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '46464646-0000-0000-0000-000000000002';
select log_security_event('password_changed');
do $$ begin
    begin
        perform log_security_event('i_am_admin_now');
        raise exception 'FAIL: an invented event was logged';
    exception when others then
        if sqlerrm not like 'Événement inconnu%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '46464646-0000-0000-0000-000000000003';
do $$ begin
    if exists (select 1 from my_security_events()) then
        raise exception 'FAIL: a stranger reads another''s history';
    end if;
    raise notice 'PASS: history private; invented events refused';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the owner''s lock rule binds the team; the strictest wins ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '46464646-0000-0000-0000-000000000002';
do $$ begin
    perform set_lock_policy('46000000-0000-0000-0000-000000000001', 1);
    raise exception 'FAIL: an employee set the rule';
exception when others then
    if sqlerrm not like 'Seul un administrateur%' then raise; end if;
end $$;
set local "request.jwt.claim.sub" = '46464646-0000-0000-0000-000000000001';
select set_lock_policy(:shop, 10);
reset role;
update orgs set lock_max_minutes = 3 where id = :shop2;
set local role authenticated;
set local "request.jwt.claim.sub" = '46464646-0000-0000-0000-000000000002';
do $$ begin
    if my_lock_policy() <> 3 then
        raise exception 'FAIL: the clerk''s rule is %, not the strictest 3', my_lock_policy();
    end if;
end $$;
set local "request.jwt.claim.sub" = '46464646-0000-0000-0000-000000000003';
do $$ begin
    if my_lock_policy() is not null then
        raise exception 'FAIL: a stranger has a rule';
    end if;
    raise notice 'PASS: admin sets, team bound, strictest wins';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: a lost phone: the admin signs a member out, never the owner ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '46464646-0000-0000-0000-000000000001';
do $$ begin
    if sign_out_member('46000000-0000-0000-0000-000000000001',
                       '46464646-0000-0000-0000-000000000002') <> 2 then
        raise exception 'FAIL: the clerk''s two sessions were not closed';
    end if;
    begin
        perform sign_out_member('46000000-0000-0000-0000-000000000001',
                                '46464646-0000-0000-0000-000000000001');
        raise exception 'FAIL: the owner signed themselves out this way';
    exception when others then
        if sqlerrm not like 'Pour vous-même%' then raise; end if;
    end;
    begin
        perform sign_out_member('46000000-0000-0000-0000-000000000001',
                                '46464646-0000-0000-0000-000000000003');
        raise exception 'FAIL: a stranger to the shop was signed out';
    exception when others then
        if sqlerrm not like 'Cette personne n''est pas membre%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '46464646-0000-0000-0000-000000000002';
do $$ begin
    if (select kind || ':' || detail from my_security_events() limit 1)
       <> 'signed_out_by_admin:Boutique Sûre' then
        raise exception 'FAIL: the clerk''s history does not say who signed them out';
    end if;
    begin
        perform sign_out_member('46000000-0000-0000-0000-000000000001',
                                '46464646-0000-0000-0000-000000000001');
        raise exception 'FAIL: an employee signed the owner out';
    exception when others then
        if sqlerrm not like 'Seul un administrateur%' then raise; end if;
    end;
    raise notice 'PASS: member signed out and told; owner, self and strangers refused';
end $$;
rollback;

\echo ''
\echo 'test_account_security: all passed'
