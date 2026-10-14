-- ============================================================
-- test_batch133.sql — « Besoin d'aide », the training team behind Mara
-- Pro (133). Phone block 133.
--
-- The claims:
--   1. the settings as installed (7–21, 15 and 30 minutes, 5 a day,
--      aide_demande, admins told), each checked (hours in order, a
--      template name or nothing);
--   2. the hours' arithmetic: 20:55 + 15 open minutes is 7:10 the next
--      morning; open minutes across a night count the hours only;
--   3. the Pro gate and who may ask: a free business, a stranger, an
--      observer and a trainer are refused; shop, farm and association
--      each ask, with their own subjects;
--   4. routing: the assigned, on-duty trainer is rung (bell + WhatsApp
--      row), nobody else; the bell's words are plain (no tag, link or
--      control character);
--   5. limits: one active request per business, N a day — 133's own rule,
--      tested on 133 as this suite re-applies it; 138 lifts the first
--      (several at once) and keeps the second: test_batch138;
--   6. escalation after the open minutes: every on-duty trainer and the
--      admins (under admin_help_notify), an off-duty one never; no
--      assigned trainer: at once;
--   7. out of hours: queued, nobody rung, routed at the opening;
--   8. RLS: who reads a request and its journal; no direct write;
--      nothing for anon;
--   9. the first wins: one take, the other refused;
--  10. visit, resolve, « pas encore », close with a rating;
--  11. the temporary access: read during the grant (orgs, products,
--      members, my_orgs as an observer), every write refused, refused
--      after expiry and after the owner revokes; only an owner grants,
--      never to a member; closing ends it; journaled (events, audit_log);
--  12. WhatsApp: the template off writes no row, the Worker's two doors
--      are the service role's, a template failure is said in the console;
--  13. « Aujourd'hui »: late and open counted, null for a non-admin;
--  14. the doors: definer functions pinned, closed to anon, the internal
--      ones closed to authenticated;
--  15. run twice, nothing changes;
--  16. (review) one business per grant, the grantee a trainer, demotion,
--      the number to call, a member gone, plain first names.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated, service_role;
-- As the earlier suites do: every table to the app's role, so RLS — not a
-- missing grant — is what is tested.
grant select, insert, update, delete on all tables in schema public to authenticated;
-- And every function, as test_trainer.sql does (the app's role holds them
-- on Supabase) — then 133 again, twice, now that the roles exist, so its
-- own grants and revokes are what is tested.
grant execute on all functions in schema public to authenticated;
\i database/migrations/133_help_requests.sql
\i database/migrations/133_help_requests.sql
grant select, insert, update, delete on all tables in schema public to authenticated;

-- People: Mara (platform admin), three trainers (A assigned to the shop,
-- B not assigned, C off duty), the shop's owner and cashier, the farm's
-- and the association's owners, a free shop's owner, a stranger.
\set mara    '''13313313-0000-0000-0000-000000000001'''
\set ta      '''13313313-0000-0000-0000-000000000002'''
\set tb      '''13313313-0000-0000-0000-000000000003'''
\set tc      '''13313313-0000-0000-0000-000000000004'''
\set owner   '''13313313-0000-0000-0000-000000000005'''
\set cashier '''13313313-0000-0000-0000-000000000006'''
\set farmer  '''13313313-0000-0000-0000-000000000007'''
\set assoc   '''13313313-0000-0000-0000-000000000008'''
\set freeo   '''13313313-0000-0000-0000-000000000009'''
\set nobody  '''13313313-0000-0000-0000-000000000010'''
\set shop    '''13300000-0000-0000-0000-000000000001'''
\set farm    '''13300000-0000-0000-0000-000000000002'''
\set club    '''13300000-0000-0000-0000-000000000003'''
\set free    '''13300000-0000-0000-0000-000000000004'''

insert into auth.users (id, phone, raw_user_meta_data) values
    (:mara,    '+22613300001', '{"full_name": "Mara Admin"}'),
    (:ta,      '+22613300002', '{"full_name": "Awa Ouédraogo"}'),
    (:tb,      '+22613300003', '{"full_name": "Issa Kaboré"}'),
    (:tc,      '+22613300004', '{"full_name": "Mariam Traoré"}'),
    (:owner,   '+22613300005', '{"full_name": "Salimata Belle"}'),
    (:cashier, '+22613300006', '{"full_name": "Caissier"}'),
    (:farmer,  '+22613300007', '{"full_name": "Fermier"}'),
    (:assoc,   '+22613300008', '{"full_name": "Trésorière"}'),
    (:freeo,   '+22613300009', '{"full_name": "Gratuit"}'),
    (:nobody,  '+22613300010', '{"full_name": "Personne"}');
update profiles set is_platform_admin = true where id = :mara;
update profiles set is_trainer = true where id in (:ta, :tb, :tc);
-- Profiles take the number from the account (004); said here for a stub
-- that does not.
update profiles p set phone = u.phone from auth.users u
 where u.id = p.id and p.phone is null;
insert into help_trainer_status (user_id, on_duty) values (:tc, false);

insert into orgs (id, name, slug, profile, default_currency, plan, city) values
    (:shop, 'Salon <b>Belle</b> Vie', 'salon-133', 'retail', 'XOF', 'pro', 'Ouagadougou'),
    (:farm, 'Ferme Wendkouni', 'ferme-133', 'farm', 'XOF', 'pro', 'Koudougou'),
    (:club, 'Groupement Wend-Panga', 'club-133', 'association', 'XOF', 'pro', 'Ouahigouya'),
    (:free, 'Boutique Gratuite', 'gratuit-133', 'retail', 'XOF', 'free', 'Bobo');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility, is_trainer) values
    (:shop, :owner,   'owner',    'org', :shop, 'full', false),
    (:shop, :cashier, 'employee', 'org', :shop, 'summary', false),
    (:shop, :ta,      'observer', 'org', :shop, 'full', true),
    (:shop, :tc,      'observer', 'org', :shop, 'full', true),
    (:farm, :farmer,  'owner',    'org', :farm, 'full', false),
    (:club, :assoc,   'owner',    'org', :club, 'full', false),
    (:free, :freeo,   'owner',    'org', :free, 'full', false);
insert into products (org_id, name) values (:shop, 'Shampoing');
insert into church_members (org_id, full_name) values (:club, 'Membre Un');

-- The tests below run in the hours unless they say otherwise: 0–24.
update platform_settings set value = '0'  where key = 'help_hours_open';
update platform_settings set value = '24' where key = 'help_hours_close';

\echo ''
\echo '--- TEST 1: the settings as installed, each checked ---'
do $$
declare v text;
begin
    -- As installed (the test moved the hours; the others are untouched).
    if help_setting_int('help_escalate_minutes') <> 15 or help_setting_int('help_late_minutes') <> 30
       or help_setting_int('help_daily_limit') <> 5
       or help_setting('help_whatsapp_template') <> '"aide_demande"'::jsonb
       or help_setting('admin_help_notify') <> 'true'::jsonb then
        raise exception 'FAIL: the settings are not as installed';
    end if;
    -- The hours' defaults (7, 21) when no row says otherwise.
    if (select (help_setting('help_hours_nope'))) is not null then
        raise exception 'FAIL: help_setting reads a key that is not the help''s';
    end if;
    begin
        update platform_settings set value = '24' where key = 'help_hours_open';
        raise exception 'FAIL: an opening at 24 h was taken';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    begin
        update platform_settings set value = '"Aide Demande!"' where key = 'help_whatsapp_template';
        raise exception 'FAIL: a template name with spaces was taken';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    begin
        update platform_settings set value = '0' where key = 'help_daily_limit';
        raise exception 'FAIL: a daily limit of 0 was taken';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    update platform_settings set value = '""' where key = 'help_whatsapp_template';
    update platform_settings set value = '"aide_demande"' where key = 'help_whatsapp_template';
    raise notice 'PASS: settings as installed; a bad opening, a bad template name and a zero limit refused; an empty template taken';
end $$;

\echo ''
\echo '--- TEST 2: the hours on Ouagadougou''s clock (7–21) ---'
begin;
update platform_settings set value = '7'  where key = 'help_hours_open';
update platform_settings set value = '21' where key = 'help_hours_close';
do $$
begin
    if help_add_open('2026-10-13 20:55+00', 15) <> '2026-10-14 07:10+00'::timestamptz then
        raise exception 'FAIL: 20:55 + 15 open minutes is %', help_add_open('2026-10-13 20:55+00', 15);
    end if;
    if help_add_open('2026-10-13 10:00+00', 15) <> '2026-10-13 10:15+00'::timestamptz then
        raise exception 'FAIL: 10:00 + 15 is not 10:15';
    end if;
    if help_next_open('2026-10-13 22:30+00') <> '2026-10-14 07:00+00'::timestamptz
       or help_next_open('2026-10-14 03:00+00') <> '2026-10-14 07:00+00'::timestamptz
       or help_next_open('2026-10-14 08:00+00') <> '2026-10-14 08:00+00'::timestamptz then
        raise exception 'FAIL: the next opening is wrong';
    end if;
    if help_in_hours('2026-10-14 06:59+00') or not help_in_hours('2026-10-14 07:00+00')
       or help_in_hours('2026-10-14 21:00+00') then
        raise exception 'FAIL: in the hours is wrong';
    end if;
    -- 20:40 → 7:20 next day: 20 minutes before closing, 20 after opening.
    if help_open_minutes('2026-10-13 20:40+00', '2026-10-14 07:20+00') <> 40 then
        raise exception 'FAIL: open minutes over a night: %',
            help_open_minutes('2026-10-13 20:40+00', '2026-10-14 07:20+00');
    end if;
    raise notice 'PASS: 20:55 + 15 open minutes = 7:10 next day; next opening and open minutes count the hours only';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: Pro only, the business''s own people only; each kind asks with its own subjects ---'
begin;
do $$
declare v jsonb;
begin
    -- The free business.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000009', true);
    set local role authenticated;
    begin
        perform help_request_create('13300000-0000-0000-0000-000000000004', 'ventes', null, 'call', null);
        raise exception 'FAIL: a free business asked a trainer';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like '%Mara Pro%' then raise exception 'FAIL: the free refusal said %', sqlerrm; end if;
    end;
    v := help_state('13300000-0000-0000-0000-000000000004');
    if v ->> 'pro' <> 'false' or v ->> 'available' <> 'true' then
        raise exception 'FAIL: the free business''s state is %', v;
    end if;
    -- A stranger, the assigned trainer (an observer) and Mara herself.
    foreach v in array array['"13313313-0000-0000-0000-000000000010"', '"13313313-0000-0000-0000-000000000002"',
                             '"13313313-0000-0000-0000-000000000001"']::jsonb[] loop
        reset role;
        perform set_config('request.jwt.claim.sub', v #>> '{}', true);
        set local role authenticated;
        begin
            perform help_request_create('13300000-0000-0000-0000-000000000001', 'ventes', null, 'call', null);
            raise exception 'FAIL: % asked for the shop', v;
        exception when others then
            if sqlerrm like 'FAIL:%' then raise; end if;
        end;
        if (help_state('13300000-0000-0000-0000-000000000001') ->> 'available') <> 'false' then
            raise exception 'FAIL: % may ask for the shop', v;
        end if;
    end loop;
    -- A farm asks about its bandes, an association about its contributions.
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000007', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000002', 'bandes', 'Une bande malade', 'visit', null);
    if v ->> 'status' <> 'open' then raise exception 'FAIL: the farm''s request is %', v; end if;
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000008', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000003', 'contributions', null, 'whatsapp', '226 70 00 00 08');
    if v ->> 'status' <> 'open' then raise exception 'FAIL: the association''s request is %', v; end if;
    begin
        perform help_request_create('13300000-0000-0000-0000-000000000003', 'licornes', null, 'call', null);
        raise exception 'FAIL: an unknown subject was taken';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    raise notice 'PASS: a free business, a stranger, an observer trainer and Mara refused; a farm (bandes) and an association (contributions) ask';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the assigned, on-duty trainer is rung — the bell in plain words and a WhatsApp row ---'
begin;
do $$
declare v jsonb; v_id uuid; n record;
begin
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000006', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000001', 'ventes',
        E'Je n''arrive pas <script>x</script> à annuler https://evil.example​ une vente', 'whatsapp', null,
        null, '{"screen": "Vente", "version": "1.36.0", "platform": "android"}');
    v_id := (v ->> 'id')::uuid;
    reset role;
    -- Awa (assigned, on duty) is rung; Mariam (assigned, off duty) and Issa (not assigned) are not.
    if (select count(*) from notifications where kind = 'help_request' and recipient_id = '13313313-0000-0000-0000-000000000002') <> 1 then
        raise exception 'FAIL: the assigned trainer was not rung once';
    end if;
    if exists (select 1 from notifications where kind = 'help_request'
                and recipient_id in ('13313313-0000-0000-0000-000000000003', '13313313-0000-0000-0000-000000000004')) then
        raise exception 'FAIL: an unassigned or off-duty trainer was rung';
    end if;
    select * into n from notifications where kind = 'help_request' limit 1;
    if n.message ~ '[<>]' or n.message like '%://%' or n.message ~ '[[:cntrl:]]' or n.message ~ '​' then
        raise exception 'FAIL: the bell is not plain: %', n.message;
    end if;
    if n.params ->> 'to' <> 'me' or n.scope <> 'me' or (n.params ->> 'request_id')::uuid <> v_id then
        raise exception 'FAIL: the bell''s facts are %', n.params;
    end if;
    -- WhatsApp: one row for Awa, the template and its four values, plain.
    if (select count(*) from help_whatsapp_outbox where request_id = v_id) <> 1
       or (select phone from help_whatsapp_outbox where request_id = v_id) <> '22613300002'
       or (select template from help_whatsapp_outbox where request_id = v_id) <> 'aide_demande'
       or (select params ->> 'kind' from help_whatsapp_outbox where request_id = v_id) <> 'Boutique'
       or (select params ->> 'name' from help_whatsapp_outbox where request_id = v_id) ~ '[<>]' then
        raise exception 'FAIL: the WhatsApp row is wrong: %', (select to_jsonb(o) from help_whatsapp_outbox o where request_id = v_id);
    end if;
    -- The context, cut and plain; the number from the profile.
    if (select context ->> 'screen' from help_requests where id = v_id) <> 'Vente'
       or (select contact_phone from help_requests where id = v_id) <> '22613300006' then
        raise exception 'FAIL: the context or the number is wrong';
    end if;
    -- The admins are not told yet (only an escalation tells them).
    if exists (select 1 from notifications where kind = 'help_escalated') then
        raise exception 'FAIL: the admins were told before the escalation';
    end if;
    raise notice 'PASS: Awa rung once (bell to: me, plain words, a WhatsApp row with the template); Mariam off duty and Issa unassigned not; the admins not yet';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: one active request per business, and the day''s limit ---'
begin;
update platform_settings set value = '2' where key = 'help_daily_limit';
do $$
declare v jsonb;
begin
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000005', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000001', 'stock', null, 'call', null);
    begin
        perform help_request_create('13300000-0000-0000-0000-000000000001', 'ventes', null, 'call', null);
        raise exception 'FAIL: a second active request was made';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like '%déjà en cours%' then raise exception 'FAIL: the refusal said %', sqlerrm; end if;
    end;
    perform help_close((v ->> 'id')::uuid, null);
    v := help_request_create('13300000-0000-0000-0000-000000000001', 'ventes', null, 'call', null);
    perform help_close((v ->> 'id')::uuid, null);
    begin
        perform help_request_create('13300000-0000-0000-0000-000000000001', 'factures', null, 'call', null);
        raise exception 'FAIL: a third request in 24 hours was made with a limit of 2';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like '%24 heures%' then raise exception 'FAIL: the limit said %', sqlerrm; end if;
    end;
    if (help_state('13300000-0000-0000-0000-000000000001') ->> 'left')::int <> 0 then
        raise exception 'FAIL: help_state says requests are left';
    end if;
    raise notice 'PASS: one active request at a time; the third of the day refused at a limit of 2, help_state says none left';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: escalation — every on-duty trainer and the admins; at once without an assigned trainer ---'
begin;
do $$
declare v jsonb; v_id uuid; v_farm uuid;
begin
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000005', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000001', 'vitrine', null, 'call', null);
    v_id := (v ->> 'id')::uuid;
    reset role;
    -- Issa (not assigned) does not see it yet.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000003', true);
    set local role authenticated;
    if exists (select 1 from help_requests where id = v_id) then
        raise exception 'FAIL: an unassigned trainer saw the request before the escalation';
    end if;
    reset role;
    -- Fifteen minutes pass with nobody.
    perform help_tick();
    if (select escalated_at from help_requests where id = v_id) is not null then
        raise exception 'FAIL: escalated before its time';
    end if;
    update help_requests set escalate_at = now() - interval '1 minute' where id = v_id;
    perform help_tick();
    if (select escalated_at from help_requests where id = v_id) is null then
        raise exception 'FAIL: not escalated after its time';
    end if;
    -- Issa rung; Awa not rung twice; Mariam (off duty) never; Mara told.
    if (select count(*) from notifications where kind = 'help_request' and recipient_id = '13313313-0000-0000-0000-000000000003') <> 1
       or (select count(*) from notifications where kind = 'help_request' and recipient_id = '13313313-0000-0000-0000-000000000002') <> 1
       or exists (select 1 from notifications where recipient_id = '13313313-0000-0000-0000-000000000004')
       or (select count(*) from notifications where kind = 'help_escalated' and recipient_id = '13313313-0000-0000-0000-000000000001') <> 1
       or (select scope from notifications where kind = 'help_escalated' limit 1) <> 'platform' then
        raise exception 'FAIL: the escalation rang the wrong people';
    end if;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000003', true);
    set local role authenticated;
    if not exists (select 1 from help_requests where id = v_id) then
        raise exception 'FAIL: the unassigned trainer does not see the escalated request';
    end if;
    if jsonb_array_length(help_inbox() -> 'requests') <> 1 then
        raise exception 'FAIL: the escalated request is not in Issa''s inbox';
    end if;
    reset role;
    -- The farm has no assigned trainer: at once, to everyone on duty — and,
    -- with admin_help_notify off, never to the admins.
    update platform_settings set value = 'false' where key = 'admin_help_notify';
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000007', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000002', 'stock', null, 'call', null);
    v_farm := (v ->> 'id')::uuid;
    reset role;
    -- (Counted among this file's people: an earlier suite may have left
    -- trainers and admins of its own.)
    if (select escalated_at from help_requests where id = v_farm) is null
       or (select count(*) from notifications where kind = 'help_request'
            and (params ->> 'request_id')::uuid = v_farm
            and recipient_id in ('13313313-0000-0000-0000-000000000002', '13313313-0000-0000-0000-000000000003')) <> 2
       or exists (select 1 from notifications where kind = 'help_request'
                   and (params ->> 'request_id')::uuid = v_farm
                   and recipient_id = '13313313-0000-0000-0000-000000000004')
       or exists (select 1 from notifications where kind = 'help_escalated'
                   and (params ->> 'request_id')::uuid = v_farm) then
        raise exception 'FAIL: without an assigned trainer the farm''s request did not go to everyone at once (or the switch rang the admins)';
    end if;
    raise notice 'PASS: escalated only after its time; Issa rung and sees it, Awa once, Mariam (off duty) never, Mara told; the farm without a trainer to all at once; the admins'' switch off rings none';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: out of the hours — accepted, queued, rung at the opening ---'
begin;
-- Hours that are over for today (or not begun): whatever the clock says.
do $$
declare h int := extract(hour from now() at time zone 'Africa/Ouagadougou');
begin
    if h >= 1 then
        update platform_settings set value = '0' where key = 'help_hours_open';
        update platform_settings set value = to_jsonb(h) where key = 'help_hours_close';
    else
        update platform_settings set value = '23' where key = 'help_hours_close';
        update platform_settings set value = '22' where key = 'help_hours_open';
    end if;
end $$;
do $$
declare v jsonb; v_id uuid;
begin
    if help_in_hours(now()) then raise exception 'FAIL: the test could not leave the hours'; end if;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000005', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000001', 'commandes', null, 'call', null);
    v_id := (v ->> 'id')::uuid;
    if (v ->> 'queued')::boolean is not true or (v ->> 'routed_at')::timestamptz <= now() then
        raise exception 'FAIL: the request out of hours is not queued: %', v;
    end if;
    if (help_state('13300000-0000-0000-0000-000000000001') -> 'hours' ->> 'in_hours')::boolean then
        raise exception 'FAIL: help_state says in the hours';
    end if;
    reset role;
    perform help_tick();
    if exists (select 1 from notifications where kind = 'help_request') then
        raise exception 'FAIL: a trainer was rung out of the hours';
    end if;
    -- Awa does not see it in her inbox before the opening.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000002', true);
    set local role authenticated;
    if jsonb_array_length(help_inbox() -> 'requests') <> 0 then
        raise exception 'FAIL: a queued request is in the inbox before the opening';
    end if;
    reset role;
    -- The opening comes.
    update help_requests set routed_at = now() - interval '1 minute' where id = v_id;
    perform help_tick();
    if (select count(*) from notifications where kind = 'help_request') <> 1
       or (select routed_rung_at from help_requests where id = v_id) is null
       or not exists (select 1 from help_request_events where request_id = v_id and event = 'queued')
       or not exists (select 1 from help_request_events where request_id = v_id and event = 'routed') then
        raise exception 'FAIL: the queued request was not routed at the opening';
    end if;
    raise notice 'PASS: out of the hours the request is accepted and queued (nobody rung, not in the inbox), then routed at the opening';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: who reads a request; no direct write; nothing for anon ---'
begin;
do $$
declare v jsonb; v_id uuid; v_n int;
begin
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000006', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000001', 'equipe', null, 'call', null);
    v_id := (v ->> 'id')::uuid;
    -- Readers: the cashier (who asked), the owner, Awa (assigned), Mara.
    foreach v in array array['"13313313-0000-0000-0000-000000000006"', '"13313313-0000-0000-0000-000000000005"',
                             '"13313313-0000-0000-0000-000000000002"', '"13313313-0000-0000-0000-000000000001"']::jsonb[] loop
        reset role;
        perform set_config('request.jwt.claim.sub', v #>> '{}', true);
        set local role authenticated;
        if not exists (select 1 from help_requests where id = v_id)
           or not exists (select 1 from help_request_events where request_id = v_id) then
            raise exception 'FAIL: % cannot read the request or its journal', v;
        end if;
    end loop;
    -- Not: Issa (not assigned, not escalated), the farmer, a stranger.
    foreach v in array array['"13313313-0000-0000-0000-000000000003"', '"13313313-0000-0000-0000-000000000007"',
                             '"13313313-0000-0000-0000-000000000010"']::jsonb[] loop
        reset role;
        perform set_config('request.jwt.claim.sub', v #>> '{}', true);
        set local role authenticated;
        if exists (select 1 from help_requests where id = v_id)
           or exists (select 1 from help_request_events where request_id = v_id) then
            raise exception 'FAIL: % reads a request that is not theirs', v;
        end if;
    end loop;
    -- No direct write, even for the owner holding every table grant.
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000005', true);
    set local role authenticated;
    update help_requests set status = 'closed' where id = v_id;
    get diagnostics v_n = row_count;
    if v_n <> 0 then raise exception 'FAIL: the owner updated a request directly'; end if;
    begin
        insert into help_requests (org_id, subject, contact) values ('13300000-0000-0000-0000-000000000001', 'autre', 'call');
        raise exception 'FAIL: a request was inserted directly';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    begin
        insert into help_access_grants (request_id, org_id, trainer_id, expires_at)
        values (v_id, '13300000-0000-0000-0000-000000000001', '13313313-0000-0000-0000-000000000003', now() + interval '1 hour');
        raise exception 'FAIL: a grant was inserted directly';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    begin
        perform 1 from help_whatsapp_outbox;
        if exists (select 1 from help_whatsapp_outbox) then
            raise exception 'FAIL: the app reads the WhatsApp outbox';
        end if;
    exception when insufficient_privilege then null;
    end;
    reset role;
    -- Anon: no table, no door.
    set local role anon;
    begin
        perform 1 from help_requests limit 1;
        raise exception 'FAIL: anon reads help_requests';
    exception when insufficient_privilege then null;
    end;
    begin
        perform help_state('13300000-0000-0000-0000-000000000001');
        raise exception 'FAIL: anon calls help_state';
    exception when insufficient_privilege then null;
    end;
    reset role;
    raise notice 'PASS: the asker, the owner, the assigned trainer and Mara read it and its journal; an unassigned trainer, another business and a stranger do not; no direct write; anon reads and calls nothing';
end $$;
rollback;

\echo ''
\echo '--- TEST 9: « Je m''en occupe » — the first wins ---'
begin;
do $$
declare v jsonb; v_id uuid;
begin
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000005', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000001', 'ventes', null, 'whatsapp', null);
    v_id := (v ->> 'id')::uuid;
    reset role;
    update help_requests set escalate_at = now() - interval '1 minute' where id = v_id;
    perform help_tick();
    -- Issa (escalated to him) takes first; Awa second is refused.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000003', true);
    set local role authenticated;
    v := help_take(v_id);
    if (v ->> 'mine')::boolean is not true or v ->> 'phone' <> '22613300005' then
        raise exception 'FAIL: the take did not give Issa the request and its number: %', v;
    end if;
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000002', true);
    set local role authenticated;
    begin
        perform help_take(v_id);
        raise exception 'FAIL: a second trainer took a taken request';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        if sqlerrm not like '%déjà%' then raise exception 'FAIL: the refusal said %', sqlerrm; end if;
    end;
    -- Awa (assigned) still sees it, without the number.
    select r into v from jsonb_array_elements(help_inbox() -> 'requests') r where r ->> 'id' = v_id::text;
    if v is null or v ->> 'phone' is not null or v ->> 'taken_by' <> 'Issa' then
        raise exception 'FAIL: a trainer who did not take it reads %', v;
    end if;
    reset role;
    -- The owner was told, by Issa's first name; the owner sees the name.
    if not exists (select 1 from notifications where kind = 'help_taken'
                    and recipient_id = '13313313-0000-0000-0000-000000000005' and message like 'Issa%') then
        raise exception 'FAIL: the owner was not told who took it';
    end if;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000005', true);
    set local role authenticated;
    v := help_state('13300000-0000-0000-0000-000000000001') -> 'request';
    if v -> 'trainer' ->> 'first_name' <> 'Issa' or (v -> 'trainer' ->> 'member')::boolean
       or v -> 'trainer' ->> 'phone' <> '22613300003' then
        raise exception 'FAIL: the owner''s status is %', v;
    end if;
    reset role;
    raise notice 'PASS: Issa takes it first, Awa is told someone else has it and does not read the number; the owner is told « Issa … » and sees him, his number, not a member';
end $$;
rollback;

\echo ''
\echo '--- TEST 10: a visit, the resolution, « pas encore », the close and its rating ---'
begin;
do $$
declare v jsonb; v_id uuid;
begin
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000005', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000001', 'stock', null, 'visit', null);
    v_id := (v ->> 'id')::uuid;
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000002', true);
    set local role authenticated;
    begin
        perform help_resolve(v_id, 'x');
        raise exception 'FAIL: resolved before being taken';
    exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    perform help_take(v_id);
    v := help_visit_answer(v_id, 'call_instead', 'Je vous appelle à 15 h');
    if v ->> 'visit_answer' <> 'call_instead' then raise exception 'FAIL: the visit answer is %', v; end if;
    v := help_resolve(v_id, 'Stock corrigé ensemble');
    if v ->> 'status' <> 'resolved' then raise exception 'FAIL: not resolved'; end if;
    reset role;
    if not exists (select 1 from notifications where kind = 'help_visit' and recipient_id = '13313313-0000-0000-0000-000000000005')
       or not exists (select 1 from notifications where kind = 'help_resolved' and recipient_id = '13313313-0000-0000-0000-000000000005') then
        raise exception 'FAIL: the owner was not told of the call or the resolution';
    end if;
    -- « Pas encore »: back to Awa, who is told.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000005', true);
    set local role authenticated;
    v := help_reopen(v_id);
    if v ->> 'status' <> 'taken' then raise exception 'FAIL: not reopened'; end if;
    reset role;
    if not exists (select 1 from notifications where kind = 'help_reopened' and recipient_id = '13313313-0000-0000-0000-000000000002') then
        raise exception 'FAIL: the trainer was not told it was reopened';
    end if;
    -- Another member cannot close it; the cashier is not the asker nor an admin.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000006', true);
    set local role authenticated;
    begin
        perform help_close(v_id, 1);
        raise exception 'FAIL: the cashier closed the owner''s request';
    exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000005', true);
    set local role authenticated;
    begin
        perform help_close(v_id, 5);
        raise exception 'FAIL: a rating of 5 was taken';
    exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    v := help_close(v_id, 1);
    if v ->> 'status' <> 'closed' or (v ->> 'rating')::int <> 1 then raise exception 'FAIL: the close is %', v; end if;
    if (select string_agg(e ->> 'event', ',') from jsonb_array_elements(v -> 'events') e)
       <> 'created,taken,call_instead,resolved,reopened,closed' then
        raise exception 'FAIL: the journal says %', (select string_agg(e ->> 'event', ',') from jsonb_array_elements(v -> 'events') e);
    end if;
    reset role;
    raise notice 'PASS: a call proposed for a visit, resolved with a note, « pas encore » back to the trainer, closed 👍 by the owner only; the journal in order';
end $$;
rollback;

\echo ''
\echo '--- TEST 11: the temporary access — read during it, never a write, gone after expiry or revoke ---'
begin;
do $$
declare v jsonb; v_id uuid; v_n int; v_audit int;
begin
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000008', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000003', 'membres', null, 'call', null);
    v_id := (v ->> 'id')::uuid;
    reset role;
    -- Before any grant Issa reads nothing of the association.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000003', true);
    set local role authenticated;
    if exists (select 1 from orgs where id = '13300000-0000-0000-0000-000000000003')
       or exists (select 1 from church_members where org_id = '13300000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: the trainer reads the association before any grant';
    end if;
    -- He cannot grant himself anything.
    perform help_take(v_id);
    begin
        perform help_access_grant(v_id);
        raise exception 'FAIL: the trainer granted himself access';
    exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    reset role;
    -- The owner grants: 48 h.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000008', true);
    set local role authenticated;
    if (help_state('13300000-0000-0000-0000-000000000003') -> 'request' -> 'trainer' ->> 'member')::boolean then
        raise exception 'FAIL: Issa reads as a member';
    end if;
    v := help_access_grant(v_id);
    if (v -> 'access' ->> 'expires_at')::timestamptz > now() + interval '48 hours'
       or (v -> 'access' ->> 'expires_at')::timestamptz < now() + interval '47 hours' then
        raise exception 'FAIL: the grant is not 48 hours: %', v -> 'access';
    end if;
    reset role;
    -- During: Issa reads the business, its members, lists it as an observer.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000003', true);
    set local role authenticated;
    if not exists (select 1 from orgs where id = '13300000-0000-0000-0000-000000000003')
       or not exists (select 1 from church_members where org_id = '13300000-0000-0000-0000-000000000003')
       or not is_org_member('13300000-0000-0000-0000-000000000003')
       or not has_full_visibility('13300000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: the trainer cannot read during the grant';
    end if;
    if (select roles from my_orgs() where org_id = '13300000-0000-0000-0000-000000000003') <> array['observer'] then
        raise exception 'FAIL: my_orgs does not list the association as an observer''s';
    end if;
    if help_access_opened(v_id) <> '13300000-0000-0000-0000-000000000003'::uuid then
        raise exception 'FAIL: opening the access did not answer the business';
    end if;
    -- Never a write.
    if can_write_org('13300000-0000-0000-0000-000000000003') or is_org_admin('13300000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: the grant writes or administers';
    end if;
    begin
        insert into church_members (org_id, full_name) values ('13300000-0000-0000-0000-000000000003', 'Intrus');
        raise exception 'FAIL: the trainer added a member';
    exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    update church_members set full_name = 'Changé' where org_id = '13300000-0000-0000-0000-000000000003';
    get diagnostics v_n = row_count;
    if v_n <> 0 then raise exception 'FAIL: the trainer changed a member'; end if;
    delete from church_members where org_id = '13300000-0000-0000-0000-000000000003';
    get diagnostics v_n = row_count;
    if v_n <> 0 then raise exception 'FAIL: the trainer deleted a member'; end if;
    update orgs set name = 'Piraté' where id = '13300000-0000-0000-0000-000000000003';
    get diagnostics v_n = row_count;
    if v_n <> 0 then raise exception 'FAIL: the trainer renamed the business'; end if;
    begin
        insert into products (org_id, name) values ('13300000-0000-0000-0000-000000000003', 'Intrus');
        raise exception 'FAIL: the trainer added an article';
    exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    -- Another business stays closed to him.
    if exists (select 1 from orgs where id = '13300000-0000-0000-0000-000000000002') then
        raise exception 'FAIL: the grant opened another business';
    end if;
    reset role;
    -- Journaled: the request's journal and the business's audit log.
    select count(*) into v_audit from audit_log where table_name = 'help_access_grants'
       and org_id = '13300000-0000-0000-0000-000000000003';
    if v_audit < 2 or not exists (select 1 from help_request_events where request_id = v_id and event = 'access_granted')
       or not exists (select 1 from help_request_events where request_id = v_id and event = 'access_opened')
       or not exists (select 1 from notifications where kind = 'help_access' and recipient_id = '13313313-0000-0000-0000-000000000003') then
        raise exception 'FAIL: the grant is not journaled (% audit rows)', v_audit;
    end if;

    -- After the 48 h (moved back in time): nothing, at once — before any tick.
    update help_access_grants set granted_at = now() - interval '49 hours',
                                  expires_at = now() - interval '1 hour' where request_id = v_id;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000003', true);
    set local role authenticated;
    if exists (select 1 from orgs where id = '13300000-0000-0000-0000-000000000003')
       or exists (select 1 from church_members where org_id = '13300000-0000-0000-0000-000000000003')
       or exists (select 1 from my_orgs() where org_id = '13300000-0000-0000-0000-000000000003')
       or is_org_member('13300000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: the trainer still reads after the expiry';
    end if;
    begin
        perform help_access_opened(v_id);
        raise exception 'FAIL: an expired access opened';
    exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    reset role;
    perform help_tick();
    if not exists (select 1 from help_request_events where request_id = v_id and event = 'access_expired') then
        raise exception 'FAIL: the expiry is not in the journal';
    end if;

    -- Granted again, then revoked by the owner: nothing, at once.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000008', true);
    set local role authenticated;
    perform help_access_grant(v_id);
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000003', true);
    set local role authenticated;
    if not exists (select 1 from orgs where id = '13300000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: the second grant does not read';
    end if;
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000008', true);
    set local role authenticated;
    perform help_access_revoke(v_id);
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000003', true);
    set local role authenticated;
    if exists (select 1 from orgs where id = '13300000-0000-0000-0000-000000000003')
       or exists (select 1 from church_members where org_id = '13300000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: the trainer still reads after the owner revoked';
    end if;
    reset role;

    -- Granted once more, the request closed: the access ends with it.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000008', true);
    set local role authenticated;
    perform help_access_grant(v_id);
    perform help_close(v_id, -1);
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000003', true);
    set local role authenticated;
    if is_org_member('13300000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: closing the request did not end the access';
    end if;
    reset role;
    raise notice 'PASS: read during the grant (business, members, my_orgs as observer); every write refused; nothing after expiry (before any tick), after the owner revokes, after the close; the trainer cannot grant himself; journaled (events + % audit rows)', v_audit;
end $$;
rollback;

\echo ''
\echo '--- TEST 11b: no access for a trainer who already belongs, nor from a member who is not an admin ---'
begin;
do $$
declare v jsonb; v_id uuid;
begin
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000006', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000001', 'ventes', null, 'call', null);
    v_id := (v ->> 'id')::uuid;
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000002', true);
    set local role authenticated;
    perform help_take(v_id);
    reset role;
    -- The cashier (who asked) is not an admin: refused.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000006', true);
    set local role authenticated;
    begin
        perform help_access_grant(v_id);
        raise exception 'FAIL: a cashier granted access';
    exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    reset role;
    -- Awa is assigned (a member already): nothing to grant.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000005', true);
    set local role authenticated;
    if not (help_state('13300000-0000-0000-0000-000000000001') -> 'request' -> 'trainer' ->> 'member')::boolean then
        raise exception 'FAIL: the assigned trainer does not read as a member';
    end if;
    begin
        perform help_access_grant(v_id);
        raise exception 'FAIL: access granted to a trainer who belongs already';
    exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    reset role;
    raise notice 'PASS: a cashier cannot grant; a trainer who belongs already is never granted';
end $$;
rollback;

\echo ''
\echo '--- TEST 12: WhatsApp — off writes no row; the Worker''s doors; the console says how it goes ---'
begin;
do $$
declare v jsonb; v_id uuid; v_rows jsonb;
begin
    -- Off: the bell alone.
    update platform_settings set value = '""' where key = 'help_whatsapp_template';
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000005', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000001', 'ventes', null, 'call', null);
    v_id := (v ->> 'id')::uuid;
    reset role;
    if exists (select 1 from help_whatsapp_outbox where request_id = v_id)
       or not exists (select 1 from notifications where kind = 'help_request' and (params ->> 'request_id')::uuid = v_id) then
        raise exception 'FAIL: with the template off, a WhatsApp row was written (or no bell)';
    end if;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000001', true);
    set local role authenticated;
    if help_console() -> 'whatsapp' ->> 'state' <> 'off' then
        raise exception 'FAIL: the console does not say WhatsApp is off: %', help_console() -> 'whatsapp';
    end if;
    -- The Worker's doors are not the app's.
    begin
        perform help_whatsapp_claim(5);
        raise exception 'FAIL: the app claimed WhatsApp rows';
    exception when insufficient_privilege then null;
    end;
    begin
        perform help_tick();
        raise exception 'FAIL: the app ran the clock';
    exception when insufficient_privilege then null;
    end;
    reset role;
    -- On: escalated to Issa, a row for him; the service role claims both.
    update platform_settings set value = '"aide_demande"' where key = 'help_whatsapp_template';
    update help_requests set escalate_at = now() - interval '1 minute' where id = v_id;
    set local role service_role;
    v_rows := help_whatsapp_claim(50);
    -- Issa's row (an earlier suite's trainers may have rows of their own).
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_rows
      from jsonb_array_elements(v_rows) x where x ->> 'to' = '22613300003';
    if jsonb_array_length(v_rows) <> 1 or v_rows -> 0 ->> 'to' <> '22613300003'
       or v_rows -> 0 ->> 'template' <> 'aide_demande'
       or v_rows -> 0 -> 'params' ->> 'request_id' <> v_id::text then
        raise exception 'FAIL: the claim gave %', v_rows;
    end if;
    -- Claimed once: a second claim gives nothing.
    if jsonb_array_length(help_whatsapp_claim(10)) <> 0 then
        raise exception 'FAIL: a row was claimed twice';
    end if;
    -- Meta refused the template: the console says so.
    perform help_whatsapp_done((v_rows -> 0 ->> 'id')::uuid, false, 'template');
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000001', true);
    set local role authenticated;
    if help_console() -> 'whatsapp' ->> 'state' <> 'template' then
        raise exception 'FAIL: the console does not say the template is refused';
    end if;
    reset role;
    -- And sent, once approved.
    update help_whatsapp_outbox set state = 'sending' where id = (v_rows -> 0 ->> 'id')::uuid;
    set local role service_role;
    perform help_whatsapp_done((v_rows -> 0 ->> 'id')::uuid, true, null);
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000001', true);
    set local role authenticated;
    if help_console() -> 'whatsapp' ->> 'state' <> 'on' then
        raise exception 'FAIL: the console does not say WhatsApp is on';
    end if;
    -- A non-admin reads no console.
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000005', true);
    set local role authenticated;
    if help_console() is not null or help_todo_counts() is not null then
        raise exception 'FAIL: an owner reads the console';
    end if;
    reset role;
    raise notice 'PASS: template off → no row, the bell, console « off »; claim and the clock the service role''s; claimed once; « template » then « on » said in the console; an owner reads none';
end $$;
rollback;

\echo ''
\echo '--- TEST 13: « Aujourd''hui » — late after 30 open minutes, the rest open ---'
begin;
do $$
declare v jsonb; v_id uuid; c jsonb;
begin
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000005', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000001', 'ventes', null, 'call', null);
    v_id := (v ->> 'id')::uuid;
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000007', true);
    set local role authenticated;
    perform help_request_create('13300000-0000-0000-0000-000000000002', 'stock', null, 'call', null);
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000001', true);
    set local role authenticated;
    c := help_todo_counts();
    if (c ->> 'help_late')::int <> 0 or (c ->> 'help_open')::int <> 2 then
        raise exception 'FAIL: the counts are %', c;
    end if;
    reset role;
    update help_requests set routed_at = now() - interval '40 minutes', created_at = now() - interval '40 minutes'
     where id = v_id;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000001', true);
    set local role authenticated;
    c := help_todo_counts();
    if (c ->> 'help_late')::int <> 1 or (c ->> 'help_open')::int <> 1 then
        raise exception 'FAIL: after 40 minutes the counts are %', c;
    end if;
    if not (select bool_or((w ->> 'late')::boolean) from jsonb_array_elements(help_console() -> 'waiting') w) then
        raise exception 'FAIL: the console does not mark the late request';
    end if;
    reset role;
    raise notice 'PASS: two open, none late; 40 minutes later one late, one open; the console marks it';
end $$;
rollback;

\echo ''
\echo '--- TEST 14: the doors — pinned, closed to anon, the internal ones closed to the app ---'
do $$
declare v text;
begin
    select string_agg(p.oid::regprocedure::text, ', ') into v
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and (p.proname like 'help\_%' or p.proname = 'trg_help_settings')
       and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
    if v is not null then raise exception 'FAIL: no pinned search path: %', v; end if;
    select string_agg(p.oid::regprocedure::text, ', ') into v
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and (p.proname like 'help\_%' or p.proname = 'trg_help_settings')
       and (has_function_privilege('anon', p.oid, 'execute')
            or has_function_privilege('public', p.oid, 'execute'));
    if v is not null then raise exception 'FAIL: open to anon or PUBLIC: %', v; end if;
    select string_agg(f, ', ') into v
      from unnest(array['help_tick()', 'help_whatsapp_claim(integer)', 'help_whatsapp_done(uuid,boolean,text)',
                        'trg_help_trainer_demoted()', 'help_ring(uuid,boolean)', 'help_bell(uuid,uuid,text,text,text)',
                        'help_setting(text)', 'help_inbox_row(uuid)', 'help_request_json(uuid)']) f
     where has_function_privilege('authenticated', f::regprocedure, 'execute');
    if v is not null then raise exception 'FAIL: internal doors open to the app: %', v; end if;
    select string_agg(f, ', ') into v
      from unnest(array['help_tick()', 'help_whatsapp_claim(integer)', 'help_whatsapp_done(uuid,boolean,text)']) f
     where not has_function_privilege('service_role', f::regprocedure, 'execute');
    if v is not null then raise exception 'FAIL: the service role cannot call: %', v; end if;
    select string_agg(c.relname, ', ') into v
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname like 'help\_%' and c.relkind = 'r' and not c.relrowsecurity;
    if v is not null then raise exception 'FAIL: tables without RLS: %', v; end if;
    -- The definers, each said in the migration's header (8).
    if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname like 'help\_%' and p.prosecdef) < 20 then
        raise exception 'FAIL: fewer definer doors than expected';
    end if;
    raise notice 'PASS: every help function pinned, none open to anon or PUBLIC, the internal and service ones closed to the app, the service ones the service role''s, RLS on every table';
end $$;

\echo ''
\echo '--- TEST 15: run twice, the same; nothing changes for a business without a request ---'
do $$
declare v_before text; v_after text;
begin
    select string_agg(key || '=' || value::text, ',' order by key) into v_before
      from platform_settings where key like 'help\_%' or key = 'admin_help_notify';
    perform 1;
    select string_agg(key || '=' || value::text, ',' order by key) into v_after
      from platform_settings where key like 'help\_%' or key = 'admin_help_notify';
    if v_before is distinct from v_after then raise exception 'FAIL: settings moved'; end if;
end $$;
\i database/migrations/133_help_requests.sql
do $$
begin
    -- The settings the test moved are kept (on conflict do nothing).
    if help_setting_int('help_hours_close') <> 24 then
        raise exception 'FAIL: running 133 again reset a setting';
    end if;
    if (select count(*) from pg_policies where tablename like 'help\_%') <> 4 then
        raise exception 'FAIL: the policies are %', (select count(*) from pg_policies where tablename like 'help\_%');
    end if;
    -- P1: an owner's reach in their business is unchanged; a stranger's none.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000005', false);
    set role authenticated;
    if not is_org_member('13300000-0000-0000-0000-000000000001') or is_org_member('13300000-0000-0000-0000-000000000002')
       or (select count(*) from my_orgs()) <> 1 then
        raise exception 'FAIL: the owner''s reach changed';
    end if;
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000010', false);
    set role authenticated;
    if (select count(*) from my_orgs()) <> 0 or exists (select 1 from my_org_ids()) then
        raise exception 'FAIL: a stranger reaches a business';
    end if;
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);
    raise notice 'PASS: 133 run again keeps the settings and the four policies; an owner''s and a stranger''s reach unchanged';
end $$;

\echo ''
\echo '--- TEST 16 (review of 136): the grant opens one business and nothing else, for its trainer only; a demoted trainer, a member gone, the number to call ---'
begin;
do $$
declare v jsonb; v_id uuid; v_n int;
begin
    -- Something of every kind in the two other businesses to leak.
    insert into products (org_id, name) values ('13300000-0000-0000-0000-000000000002', 'Œufs'),
                                               ('13300000-0000-0000-0000-000000000003', 'Pagne');
    insert into church_members (org_id, full_name) values ('13300000-0000-0000-0000-000000000003', 'Membre Deux');
    -- The association asks; Issa (no business of his) takes; the owner grants.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000008', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000003', 'membres', 'Aidez-moi', 'call', '22670000001');
    v_id := (v ->> 'id')::uuid;
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000003', true);
    set local role authenticated;
    perform help_take(v_id);
    reset role;
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000008', true);
    set local role authenticated;
    perform help_access_grant(v_id);
    reset role;

    -- Issa: the association, and nothing of the farm or the shop — no row
    -- of theirs in any table a read helper guards.
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000003', true);
    set local role authenticated;
    if not exists (select 1 from products where org_id = '13300000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: the grant does not read its own business';
    end if;
    if exists (select 1 from products where org_id <> '13300000-0000-0000-0000-000000000003')
       or exists (select 1 from orgs where id <> '13300000-0000-0000-0000-000000000003')
       or exists (select 1 from church_members where org_id <> '13300000-0000-0000-0000-000000000003')
       or exists (select 1 from my_org_ids() x where x <> '13300000-0000-0000-0000-000000000003')
       or exists (select 1 from my_orgs() x where x.org_id <> '13300000-0000-0000-0000-000000000003')
       or is_org_member('13300000-0000-0000-0000-000000000002') or has_full_visibility('13300000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: a grant on the association reads another business';
    end if;
    -- The number to call is not a column the app's role reads (the doors say it).
    begin
        perform contact_phone from help_requests where id = v_id;
        raise exception 'FAIL: a trainer reads contact_phone from the table';
    exception when insufficient_privilege then null;
    end;
    if not exists (select 1 from help_requests where id = v_id and status = 'taken') then
        raise exception 'FAIL: the other columns are not readable';
    end if;
    reset role;

    -- Another trainer (Awa, assigned to the shop), the farmer, the shop's
    -- owner and a stranger: nothing of the association through Issa's grant.
    foreach v in array array['"13313313-0000-0000-0000-000000000002"', '"13313313-0000-0000-0000-000000000007"',
                             '"13313313-0000-0000-0000-000000000005"', '"13313313-0000-0000-0000-000000000010"']::jsonb[] loop
        perform set_config('request.jwt.claim.sub', v #>> '{}', true);
        set local role authenticated;
        if is_org_member('13300000-0000-0000-0000-000000000003')
           or exists (select 1 from products where org_id = '13300000-0000-0000-0000-000000000003')
           or exists (select 1 from church_members where org_id = '13300000-0000-0000-0000-000000000003')
           or exists (select 1 from my_org_ids() x where x = '13300000-0000-0000-0000-000000000003') then
            raise exception 'FAIL: % reads the association through another''s grant', v;
        end if;
        reset role;
    end loop;
    -- A grant row naming somebody who is no trainer (written by hand,
    -- never by a door): it opens nothing.
    insert into help_requests (id, org_id, requested_by, subject, contact)
    values ('13300000-0000-0000-0000-0000000000f1', '13300000-0000-0000-0000-000000000002',
            '13313313-0000-0000-0000-000000000007', 'bandes', 'call');
    insert into help_access_grants (request_id, org_id, trainer_id, expires_at)
    values ('13300000-0000-0000-0000-0000000000f1', '13300000-0000-0000-0000-000000000002',
            '13313313-0000-0000-0000-000000000010', now() + interval '1 hour');
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000010', true);
    set local role authenticated;
    if is_org_member('13300000-0000-0000-0000-000000000002') or has_full_visibility('13300000-0000-0000-0000-000000000002')
       or exists (select 1 from my_org_ids()) or exists (select 1 from my_orgs())
       or exists (select 1 from products where org_id = '13300000-0000-0000-0000-000000000002') then
        raise exception 'FAIL: a grant row reads for somebody who is no trainer';
    end if;
    reset role;
    delete from help_requests where id = '13300000-0000-0000-0000-0000000000f1';
    -- Anon: no helper answers yes.
    perform set_config('request.jwt.claim.sub', '', true);
    set local role anon;
    if is_org_member('13300000-0000-0000-0000-000000000003') or has_full_visibility('13300000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: anon is a member';
    end if;
    reset role;

    -- Issa is no longer a trainer: his access ends that second, journaled.
    update profiles set is_trainer = false where id = '13313313-0000-0000-0000-000000000003';
    if exists (select 1 from help_access_grants where request_id = v_id and revoked_at is null)
       or not exists (select 1 from help_request_events where request_id = v_id and event = 'access_revoked') then
        raise exception 'FAIL: demoting the trainer did not end the grant';
    end if;
    update profiles set is_trainer = true where id = '13313313-0000-0000-0000-000000000003';
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000003', true);
    set local role authenticated;
    if is_org_member('13300000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: a trainer made one again got the old grant back';
    end if;
    reset role;

    -- A cashier who asked and then left the shop: their request is no
    -- longer theirs to close or read (the trainer's number least of all).
    perform set_config('request.jwt.claim.sub', '13313313-0000-0000-0000-000000000006', true);
    set local role authenticated;
    v := help_request_create('13300000-0000-0000-0000-000000000001', 'ventes', null, 'call', null);
    reset role;
    delete from memberships where user_id = '13313313-0000-0000-0000-000000000006';
    set local role authenticated;
    begin
        perform help_close((v ->> 'id')::uuid, 1);
        raise exception 'FAIL: a member gone closed the request';
    exception when others then if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    reset role;

    -- A first name is plain words in other people's bells.
    update profiles set first_name = E'Awa\nwww.evil.com <b>' where id = '13313313-0000-0000-0000-000000000002';
    if help_first_name('13313313-0000-0000-0000-000000000002') ~ E'[\\n<>]|www\\.|\\.com' then
        raise exception 'FAIL: the first name is not plain: %', help_first_name('13313313-0000-0000-0000-000000000002');
    end if;
    raise notice 'PASS: a grant reads its one business, nothing of another (articles, members, businesses, my_org_ids, my_orgs); nothing for another trainer, another business''s people, a stranger, a non-trainer holding a grant row, or anon; a demoted trainer''s access ends at once, journaled, and stays ended; contact_phone not readable from the table; a member gone cannot close; first names plain';
end $$;
rollback;

-- Put the hours back as installed for any suite after this one.
update platform_settings set value = '7'  where key = 'help_hours_open';
update platform_settings set value = '21' where key = 'help_hours_close';
