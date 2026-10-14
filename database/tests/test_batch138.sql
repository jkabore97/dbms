-- ============================================================
-- test_batch138.sql — batch 143 (138): the help, Basic and Pro; several
-- requests per business; trainers chosen in the command center.
-- Phone block 138.
--
-- The claims:
--   1. installed twice, the same: 133's one-active index gone, preferred_at
--      there, the subjects' check the new list;
--   2. several requests at once: three open together for one business,
--      the day's limit (help_daily_limit) still refusing the one too many;
--   3. help_state: version 138, every request listed (active first),
--      « request » kept for an older app, can_upgrade for the owner and
--      not an employee, an employee reading their own requests alone, the reference (the id's first eight, capitals);
--   4. the subjects, per kind: a shop's catalogue and livraison, a farm's
--      bandes and stock, an association's evenements and contributions;
--      an unknown one refused;
--   5. « Quand ? »: a time chosen three hours ahead is queued (nobody
--      rung, not in the inbox) and routed by help_tick when its time
--      comes; a past time, one past 14 days and garbage refused; none:
--      routed now;
--   6. several requests through the trainer's side: each rings the
--      assigned trainer, both in the inbox, one taken leaves the other
--      open, the escalation takes the open one only, the console and
--      « Aujourd'hui » count both;
--   7. one access per request: closing one request leaves the other's
--      access reading, closing both ends it;
--   8. the command center's search finds a business by its reference,
--      capitals or not, six characters or eight; nobody else may search;
--   9. the trainer switch: a platform admin makes an account a trainer
--      (journaled in platform_actions), reads its number (digits, or
--      none), unmakes it (its live grant ends: 133's trigger; its 038
--      assignments go, journaled and counted); anybody
--      else is refused (null to read, an exception to write); the console
--      lists the trainer made this way;
--  10. the doors: definer, path pinned, closed to anon and PUBLIC, open to
--      authenticated where the app calls them, the internal ones closed;
--  11. RLS unchanged: a stranger reads no request.
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
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- As test_batch133 does: every function to the app's role (Supabase's),
-- then 133 and 138 again — twice — so their own grants are what is tested
-- (an earlier suite re-applied 133 itself).
grant execute on all functions in schema public to authenticated;
\i database/migrations/133_help_requests.sql
\i database/migrations/138_help_basic_pro.sql
\i database/migrations/138_help_basic_pro.sql
grant select, insert, update, delete on all tables in schema public to authenticated;

\set mara    '''13813813-0000-0000-0000-000000000001'''
\set ta      '''13813813-0000-0000-0000-000000000002'''
\set tb      '''13813813-0000-0000-0000-000000000003'''
\set owner   '''13813813-0000-0000-0000-000000000004'''
\set cashier '''13813813-0000-0000-0000-000000000005'''
\set farmer  '''13813813-0000-0000-0000-000000000006'''
\set assoc   '''13813813-0000-0000-0000-000000000007'''
\set nobody  '''13813813-0000-0000-0000-000000000008'''
\set newt    '''13813813-0000-0000-0000-000000000009'''
\set nophone '''13813813-0000-0000-0000-000000000010'''
\set shop    '''3f2a91c0-1380-0000-0000-000000000001'''
\set farm    '''13800000-0000-0000-0000-000000000002'''
\set club    '''13800000-0000-0000-0000-000000000003'''

insert into auth.users (id, phone, raw_user_meta_data) values
    (:mara,    '+22613800001', '{"full_name": "Équipe Mara 138"}'),
    (:ta,      '+22613800002', '{"full_name": "Formateur Un 138"}'),
    (:tb,      '+22613800003', '{"full_name": "Formateur Deux 138"}'),
    (:owner,   '+22613800004', '{"full_name": "Gérante Maison Élégance"}'),
    (:cashier, '+22613800005', '{"full_name": "Caisse Maison Élégance"}'),
    (:farmer,  '+22613800006', '{"full_name": "Gérant Ferme Horizon Vert"}'),
    (:assoc,   '+22613800007', '{"full_name": "Trésorerie Fondation Espoir"}'),
    (:nobody,  '+22613800008', '{"full_name": "Compte Étranger 138"}'),
    (:newt,    '+22613800009', '{"full_name": "Futur Formateur 138"}'),
    (:nophone, null,           '{"full_name": "Sans Numéro 138"}');
update profiles set is_platform_admin = true where id = :mara;
update profiles set is_trainer = true where id in (:ta, :tb);
update profiles p set phone = u.phone from auth.users u
 where u.id = p.id and p.phone is null and u.phone is not null;

insert into orgs (id, name, slug, profile, default_currency, plan, city) values
    (:shop, 'Maison Élégance',     'maison-elegance-138', 'retail',      'XOF', 'pro', 'Ouagadougou'),
    (:farm, 'Ferme Horizon Vert',  'horizon-vert-138',    'farm',        'XOF', 'pro', 'Ouagadougou'),
    (:club, 'Fondation Espoir',    'fondation-espoir-138', 'association', 'XOF', 'pro', 'Ouagadougou');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility, is_trainer) values
    (:shop, :owner,   'owner',    'org', :shop, 'full', false),
    (:shop, :cashier, 'employee', 'org', :shop, 'summary', false),
    (:shop, :ta,      'observer', 'org', :shop, 'full', true),
    (:farm, :farmer,  'owner',    'org', :farm, 'full', false),
    (:club, :assoc,   'owner',    'org', :club, 'full', false);
insert into products (org_id, name) values (:shop, 'Pagne 138');

-- In the hours unless a test says otherwise: 0–24.
update platform_settings set value = '0'  where key = 'help_hours_open';
update platform_settings set value = '24' where key = 'help_hours_close';
update platform_settings set value = '5'  where key = 'help_daily_limit';

-- A call as someone, its answer as text (or the refusal's words).
create or replace function pg_temp.as138(p_who uuid, p_sql text)
returns text
language plpgsql
as $$
declare v text;
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true);
    begin
        set local role authenticated;
        execute p_sql into v;
        reset role;
        return coalesce(v, '(null)');
    exception when others then
        reset role;
        return 'ERR: ' || sqlerrm;
    end;
end;
$$;

\echo ''
\echo '--- TEST 1: installed twice, the same ---'
do $$
begin
    if exists (select 1 from pg_indexes where indexname = 'help_requests_one_active') then
        raise exception 'FAIL: 133''s one-active index is still there';
    end if;
    if not exists (select 1 from information_schema.columns
                    where table_name = 'help_requests' and column_name = 'preferred_at') then
        raise exception 'FAIL: no preferred_at';
    end if;
    if (select count(*) from pg_constraint where conname = 'help_requests_subject_check') <> 1
       or pg_get_constraintdef((select oid from pg_constraint where conname = 'help_requests_subject_check'))
          not like '%evenements%' then
        raise exception 'FAIL: the subjects'' check is not 138''s';
    end if;
    if (select count(*) from pg_proc where proname = 'help_request_create') <> 1 then
        raise exception 'FAIL: help_request_create has an overload';
    end if;
    raise notice 'PASS: no one-active index, preferred_at, the new subjects'' check, one help_request_create — twice over';
end $$;

\echo ''
\echo '--- TEST 2: several requests at once; the day''s limit holds ---'
begin;
update platform_settings set value = '3' where key = 'help_daily_limit';
do $$
declare v text; n int;
begin
    v := pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'catalogue', 'Un', 'whatsapp')::text$q$);
    if v like 'ERR:%' then raise exception 'FAIL: the first: %', v; end if;
    v := pg_temp.as138('13813813-0000-0000-0000-000000000005',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'ventes', 'Deux', 'call')::text$q$);
    if v like 'ERR:%' then raise exception 'FAIL: a second while the first is open: %', v; end if;
    v := pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'livraison', 'Trois', 'visit')::text$q$);
    if v like 'ERR:%' then raise exception 'FAIL: a third while two are open: %', v; end if;
    select count(*) into n from help_requests
     where org_id = '3f2a91c0-1380-0000-0000-000000000001' and status = 'open';
    if n <> 3 then raise exception 'FAIL: % open, not 3', n; end if;
    v := pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'factures', 'Quatre', 'call')::text$q$);
    if v not like 'ERR:%24 heures%' then raise exception 'FAIL: the fourth at a limit of 3: %', v; end if;
    raise notice 'PASS: three open at once for one business (owner and employee); the fourth of the day refused at a limit of 3';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: help_state — every request, version, can_upgrade, the reference ---'
begin;
do $$
declare v jsonb; w jsonb; first_id uuid;
begin
    perform pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'catalogue', 'Un', 'whatsapp')::text$q$);
    first_id := (select id from help_requests where message = 'Un');
    perform pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'vitrine', 'Deux', 'call')::text$q$);
    -- The first closed: still listed, after the active one.
    perform pg_temp.as138('13813813-0000-0000-0000-000000000004',
        format('select help_close(%L, null)::text', first_id));
    v := pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_state('3f2a91c0-1380-0000-0000-000000000001')::text$q$)::jsonb;
    if (v ->> 'version')::int <> 138 or v ->> 'ref' <> '3F2A91C0'
       or (v ->> 'can_upgrade')::boolean is not true then
        raise exception 'FAIL: version / ref / can_upgrade: %', v - 'requests' - 'request';
    end if;
    if jsonb_array_length(v -> 'requests') <> 2
       or v -> 'requests' -> 0 ->> 'status' <> 'open'
       or v -> 'requests' -> 1 ->> 'status' <> 'closed' then
        raise exception 'FAIL: the list: %', v -> 'requests';
    end if;
    if v -> 'request' ->> 'message' <> 'Deux' then
        raise exception 'FAIL: « request » (for an older app) is not the active one';
    end if;
    -- An employee reads none of the owner's requests (« Je soupçonne ma
    -- caissière… »): not in the list, not as « request »; their own, yes.
    w := pg_temp.as138('13813813-0000-0000-0000-000000000005',
        $q$select help_state('3f2a91c0-1380-0000-0000-000000000001')::text$q$)::jsonb;
    if (w ->> 'can_upgrade')::boolean is not false or jsonb_array_length(w -> 'requests') <> 0
       or w -> 'request' <> 'null'::jsonb then
        raise exception 'FAIL: the employee reads the owner''s requests: %', w;
    end if;
    perform pg_temp.as138('13813813-0000-0000-0000-000000000005',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'ventes', 'Trois', 'call')::text$q$);
    w := pg_temp.as138('13813813-0000-0000-0000-000000000005',
        $q$select help_state('3f2a91c0-1380-0000-0000-000000000001')::text$q$)::jsonb;
    if jsonb_array_length(w -> 'requests') <> 1 or w -> 'requests' -> 0 ->> 'message' <> 'Trois'
       or w -> 'request' ->> 'message' <> 'Trois' then
        raise exception 'FAIL: the employee''s own: %', w -> 'requests';
    end if;
    -- The owner reads the employee's too.
    v := pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_state('3f2a91c0-1380-0000-0000-000000000001')::text$q$)::jsonb;
    if jsonb_array_length(v -> 'requests') <> 3 then
        raise exception 'FAIL: the owner does not read every request: %', v -> 'requests';
    end if;
    -- A stranger, an observer trainer: not available, nothing listed.
    w := pg_temp.as138('13813813-0000-0000-0000-000000000008',
        $q$select help_state('3f2a91c0-1380-0000-0000-000000000001')::text$q$)::jsonb;
    if (w ->> 'available')::boolean or w ? 'requests' then
        raise exception 'FAIL: a stranger read %', w;
    end if;
    w := pg_temp.as138('13813813-0000-0000-0000-000000000001',
        $q$select help_state('3f2a91c0-1380-0000-0000-000000000001')::text$q$)::jsonb;
    if (w ->> 'available')::boolean then
        raise exception 'FAIL: a platform admin who is no member is « available »';
    end if;
    raise notice 'PASS: version 138, ref 3F2A91C0, two requests (open first, the closed one after), « request » the active one; owner can_upgrade, employee not; the employee reads their own request alone, never the owner''s, the owner every one; a stranger and Mara not available';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the subjects, per kind ---'
begin;
do $$
declare v text;
begin
    foreach v in array array[
        pg_temp.as138('13813813-0000-0000-0000-000000000004',
            $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'livraison', 'x', 'call') ->> 'subject'$q$),
        pg_temp.as138('13813813-0000-0000-0000-000000000006',
            $q$select help_request_create('13800000-0000-0000-0000-000000000002', 'bandes', 'x', 'call') ->> 'subject'$q$),
        pg_temp.as138('13813813-0000-0000-0000-000000000006',
            $q$select help_request_create('13800000-0000-0000-0000-000000000002', 'stock', 'x', 'call') ->> 'subject'$q$),
        pg_temp.as138('13813813-0000-0000-0000-000000000007',
            $q$select help_request_create('13800000-0000-0000-0000-000000000003', 'evenements', 'x', 'call') ->> 'subject'$q$),
        pg_temp.as138('13813813-0000-0000-0000-000000000007',
            $q$select help_request_create('13800000-0000-0000-0000-000000000003', 'contributions', 'x', 'call') ->> 'subject'$q$)]
    loop
        if v like 'ERR:%' then raise exception 'FAIL: %', v; end if;
    end loop;
    v := pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'catalogue', 'x', 'call') ->> 'subject'$q$);
    if v <> 'catalogue' then raise exception 'FAIL: catalogue gave %', v; end if;
    v := pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'impots', 'x', 'call')::text$q$);
    if v not like 'ERR:%Choisissez de quoi%' then raise exception 'FAIL: an unknown subject: %', v; end if;
    if help_subject_label('evenements') <> 'Événements' or help_subject_label('catalogue') <> 'Articles' then
        raise exception 'FAIL: the words';
    end if;
    raise notice 'PASS: a shop''s livraison and catalogue, a farm''s bandes and stock, an association''s evenements and contributions; « impots » refused';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: « Quand ? » — a chosen time queued and routed then; wrong times refused ---'
begin;
do $$
declare v jsonb; t text; v_id uuid; v_when timestamptz := date_trunc('hour', now()) + interval '3 hours';
begin
    v := pg_temp.as138('13813813-0000-0000-0000-000000000004',
        format($q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'factures', 'Plus tard',
                    'call', null, null, jsonb_build_object('preferred_at', %L::text, 'screen', 'Aide'))::text$q$,
               v_when))::jsonb;
    v_id := (v ->> 'id')::uuid;
    if (select preferred_at from help_requests where id = v_id) <> v_when
       or (select routed_at from help_requests where id = v_id) <> v_when - interval '30 minutes'
       or (v ->> 'preferred_at')::timestamptz <> v_when or (v ->> 'queued')::boolean is not true then
        raise exception 'FAIL: the chosen time: %', v;
    end if;
    if exists (select 1 from notifications where kind = 'help_request' and (params ->> 'request_id')::uuid = v_id) then
        raise exception 'FAIL: rung before its time';
    end if;
    -- Not in the assigned trainer's inbox before its time.
    t := pg_temp.as138('13813813-0000-0000-0000-000000000002', 'select help_inbox()::text');
    if t like '%Plus tard%' then raise exception 'FAIL: in the inbox before its time'; end if;
    -- Its time comes: the clock routes it, the assigned trainer is rung.
    update help_requests set routed_at = now() - interval '1 second' where id = v_id;
    perform help_tick();
    if not exists (select 1 from notifications where kind = 'help_request'
                    and recipient_id = '13813813-0000-0000-0000-000000000002'
                    and (params ->> 'request_id')::uuid = v_id) then
        raise exception 'FAIL: not routed when its time came';
    end if;
    t := pg_temp.as138('13813813-0000-0000-0000-000000000002', 'select help_inbox()::text');
    if t not like '%preferred_at%' or t not like '%Plus tard%' then
        raise exception 'FAIL: the inbox does not say the time: %', left(t, 300);
    end if;
    -- Wrong times.
    t := pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'factures', 'x', 'call', null, null,
               jsonb_build_object('preferred_at', (now() - interval '1 day')::text))::text$q$);
    if t not like 'ERR:%14 jours%' then raise exception 'FAIL: a past time: %', t; end if;
    t := pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'factures', 'x', 'call', null, null,
               jsonb_build_object('preferred_at', (now() + interval '20 days')::text))::text$q$);
    if t not like 'ERR:%14 jours%' then raise exception 'FAIL: 20 days ahead: %', t; end if;
    t := pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'factures', 'x', 'call', null, null,
               '{"preferred_at": "demain matin"}')::text$q$);
    if t not like 'ERR:%jour et une heure%' then raise exception 'FAIL: garbage: %', t; end if;
    -- None: routed now.
    v := pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'factures', 'Tout de suite', 'call')::text$q$)::jsonb;
    if (v ->> 'queued')::boolean or v ->> 'preferred_at' is not null then
        raise exception 'FAIL: « maintenant » was queued: %', v;
    end if;
    raise notice 'PASS: three hours ahead routed 30 minutes before, nobody rung nor in the inbox until then, then rung with its time; a past time, 20 days and « demain matin » refused; « maintenant » routed now';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: several requests through the trainer''s side ---'
begin;
do $$
declare a uuid; b uuid; t text; c jsonb;
begin
    a := (pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'catalogue', 'Première', 'call') ->> 'id'$q$))::uuid;
    b := (pg_temp.as138('13813813-0000-0000-0000-000000000005',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'ventes', 'Seconde', 'call') ->> 'id'$q$))::uuid;
    if (select count(*) from notifications where kind = 'help_request'
         and recipient_id = '13813813-0000-0000-0000-000000000002') <> 2 then
        raise exception 'FAIL: the assigned trainer was not rung once per request';
    end if;
    t := pg_temp.as138('13813813-0000-0000-0000-000000000002', 'select help_inbox()::text');
    if t not like '%Première%' or t not like '%Seconde%' then raise exception 'FAIL: the inbox lacks one'; end if;
    t := pg_temp.as138('13813813-0000-0000-0000-000000000002', format('select help_take(%L)::text', a));
    if t like 'ERR:%' then raise exception 'FAIL: take: %', t; end if;
    if (select status from help_requests where id = b) <> 'open' then
        raise exception 'FAIL: taking one took the other';
    end if;
    -- Nobody took the second in time: escalated alone.
    update help_requests set escalate_at = now() - interval '1 minute' where id in (a, b);
    perform help_tick();
    if (select escalated_at from help_requests where id = b) is null then
        raise exception 'FAIL: the open one was not escalated';
    end if;
    if (select escalated_at from help_requests where id = a) is not null then
        raise exception 'FAIL: the taken one was escalated';
    end if;
    -- The unassigned trainer, now that it is escalated, sees the second.
    t := pg_temp.as138('13813813-0000-0000-0000-000000000003', 'select help_inbox()::text');
    if t not like '%Seconde%' or t like '%Première%' then
        raise exception 'FAIL: the escalated inbox: %', left(t, 300);
    end if;
    c := pg_temp.as138('13813813-0000-0000-0000-000000000001', 'select help_console()::text')::jsonb;
    if (c ->> 'open')::int <> 2
       or (select count(*) from jsonb_array_elements(c -> 'waiting') w
            where w ->> 'org_id' = '3f2a91c0-1380-0000-0000-000000000001') <> 2 then
        raise exception 'FAIL: the console: %', c -> 'waiting';
    end if;
    c := pg_temp.as138('13813813-0000-0000-0000-000000000001', 'select help_todo_counts()::text')::jsonb;
    if (c ->> 'help_late')::int + (c ->> 'help_open')::int <> 2 then
        raise exception 'FAIL: « Aujourd''hui »: %', c;
    end if;
    raise notice 'PASS: two requests of one business: rung twice, both in the inbox, one taken and the other open, the open one escalated alone, the console and « Aujourd''hui » count two';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: one access per request ---'
begin;
do $$
declare a uuid; b uuid; t text;
begin
    a := (pg_temp.as138('13813813-0000-0000-0000-000000000006',
        $q$select help_request_create('13800000-0000-0000-0000-000000000002', 'bandes', 'A', 'call') ->> 'id'$q$))::uuid;
    b := (pg_temp.as138('13813813-0000-0000-0000-000000000006',
        $q$select help_request_create('13800000-0000-0000-0000-000000000002', 'stock', 'B', 'call') ->> 'id'$q$))::uuid;
    -- No assigned trainer: escalated at once, the unassigned one takes both.
    perform pg_temp.as138('13813813-0000-0000-0000-000000000003', format('select help_take(%L)::text', a));
    perform pg_temp.as138('13813813-0000-0000-0000-000000000003', format('select help_take(%L)::text', b));
    perform pg_temp.as138('13813813-0000-0000-0000-000000000006', format('select help_access_grant(%L)::text', a));
    perform pg_temp.as138('13813813-0000-0000-0000-000000000006', format('select help_access_grant(%L)::text', b));
    t := pg_temp.as138('13813813-0000-0000-0000-000000000003',
        $q$select is_org_member('13800000-0000-0000-0000-000000000002')::text$q$);
    if t <> 'true' then raise exception 'FAIL: the grants do not read: %', t; end if;
    perform pg_temp.as138('13813813-0000-0000-0000-000000000006', format('select help_close(%L, 1)::text', a));
    t := pg_temp.as138('13813813-0000-0000-0000-000000000003',
        $q$select is_org_member('13800000-0000-0000-0000-000000000002')::text$q$);
    if t <> 'true' then raise exception 'FAIL: closing one ended the other''s access'; end if;
    perform pg_temp.as138('13813813-0000-0000-0000-000000000006', format('select help_close(%L, 1)::text', b));
    t := pg_temp.as138('13813813-0000-0000-0000-000000000003',
        $q$select is_org_member('13800000-0000-0000-0000-000000000002')::text$q$);
    if t <> 'false' then raise exception 'FAIL: both closed and it still reads'; end if;
    raise notice 'PASS: two grants to one trainer on one farm: one closed, the other still reads; both closed, nothing';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: the command center''s search finds the reference ---'
do $$
declare v text;
begin
    foreach v in array array['3F2A91C0', '3f2a91c0', '3F2A91'] loop
        if (pg_temp.as138('13813813-0000-0000-0000-000000000001',
                format('select platform_search(%L)::text', v))::jsonb
              -> 'businesses' -> 0 ->> 'id') is distinct from '3f2a91c0-1380-0000-0000-000000000001' then
            raise exception 'FAIL: « % » did not find Maison Élégance first', v;
        end if;
    end loop;
    -- The slug and the name still find it.
    if (pg_temp.as138('13813813-0000-0000-0000-000000000001',
            $q$select platform_search('maison-elegance-138')::text$q$)::jsonb -> 'businesses' -> 0 ->> 'name') <> 'Maison Élégance' then
        raise exception 'FAIL: the slug';
    end if;
    v := pg_temp.as138('13813813-0000-0000-0000-000000000004', $q$select platform_search('3F2A91C0')::text$q$);
    if v not like 'ERR:%' then raise exception 'FAIL: an owner searched the platform: %', v; end if;
    raise notice 'PASS: 3F2A91C0, 3f2a91c0 and 3F2A91 find Maison Élégance first; the slug still does; an owner is refused';
end $$;

\echo ''
\echo '--- TEST 9: the trainer switch ---'
begin;
do $$
declare v jsonb; t text; g uuid; r uuid;
begin
    -- Anybody but a platform admin: nothing to read, refused to write.
    t := pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select platform_trainer_state('13813813-0000-0000-0000-000000000009')::text$q$);
    if t <> '(null)' then raise exception 'FAIL: an owner read %', t; end if;
    t := pg_temp.as138('13813813-0000-0000-0000-000000000002',
        $q$select platform_set_trainer('13813813-0000-0000-0000-000000000009', true)::text$q$);
    if t not like 'ERR:%équipe Mara%' then raise exception 'FAIL: a trainer made a trainer: %', t; end if;
    if (select is_trainer from profiles where id = '13813813-0000-0000-0000-000000000009') then
        raise exception 'FAIL: written anyway';
    end if;
    -- Mara makes one, with a number.
    v := pg_temp.as138('13813813-0000-0000-0000-000000000001',
        $q$select platform_set_trainer('13813813-0000-0000-0000-000000000009', true)::text$q$)::jsonb;
    if (v ->> 'is_trainer')::boolean is not true or v ->> 'phone' <> '22613800009'
       or not (select is_trainer from profiles where id = '13813813-0000-0000-0000-000000000009') then
        raise exception 'FAIL: made: %', v;
    end if;
    if not exists (select 1 from platform_actions where kind = 'trainer'
                    and after ->> 'user_id' = '13813813-0000-0000-0000-000000000009'
                    and summary like '%devient formateur%') then
        raise exception 'FAIL: not journaled';
    end if;
    -- Twice: nothing more written.
    perform pg_temp.as138('13813813-0000-0000-0000-000000000001',
        $q$select platform_set_trainer('13813813-0000-0000-0000-000000000009', true)::text$q$);
    if (select count(*) from platform_actions where kind = 'trainer'
         and after ->> 'user_id' = '13813813-0000-0000-0000-000000000009') <> 1 then
        raise exception 'FAIL: a second line for no change';
    end if;
    -- The console's Formateurs lists them.
    v := pg_temp.as138('13813813-0000-0000-0000-000000000001', 'select help_console()::text')::jsonb;
    if not exists (select 1 from jsonb_array_elements(v -> 'trainers') x
                    where x ->> 'user_id' = '13813813-0000-0000-0000-000000000009') then
        raise exception 'FAIL: not in the console''s Formateurs';
    end if;
    -- An account with no number: made, and its state says none.
    v := pg_temp.as138('13813813-0000-0000-0000-000000000001',
        $q$select platform_set_trainer('13813813-0000-0000-0000-000000000010', true)::text$q$)::jsonb;
    if (v ->> 'is_trainer')::boolean is not true or v ? 'phone' and v ->> 'phone' is not null then
        raise exception 'FAIL: no number: %', v;
    end if;
    -- Unmade: its live grant ends (133's trigger).
    r := (pg_temp.as138('13813813-0000-0000-0000-000000000006',
        $q$select help_request_create('13800000-0000-0000-0000-000000000002', 'bandes', 'C', 'call') ->> 'id'$q$))::uuid;
    perform pg_temp.as138('13813813-0000-0000-0000-000000000009', format('select help_take(%L)::text', r));
    perform pg_temp.as138('13813813-0000-0000-0000-000000000006', format('select help_access_grant(%L)::text', r));
    g := (select id from help_access_grants where request_id = r and revoked_at is null);
    if g is null then raise exception 'FAIL: no grant to end'; end if;
    -- Assigned (038) to two businesses: the switch off ends those too.
    perform pg_temp.as138('13813813-0000-0000-0000-000000000001',
        $q$select assign_trainer('3f2a91c0-1380-0000-0000-000000000001', '13813813-0000-0000-0000-000000000009')::text$q$);
    perform pg_temp.as138('13813813-0000-0000-0000-000000000001',
        $q$select assign_trainer('13800000-0000-0000-0000-000000000003', '13813813-0000-0000-0000-000000000009')::text$q$);
    if (select count(*) from memberships where user_id = '13813813-0000-0000-0000-000000000009'
         and role = 'observer' and is_trainer) <> 2 then
        raise exception 'FAIL: not assigned to two';
    end if;
    v := pg_temp.as138('13813813-0000-0000-0000-000000000001',
        $q$select platform_set_trainer('13813813-0000-0000-0000-000000000009', false)::text$q$)::jsonb;
    if (v ->> 'is_trainer')::boolean is not false
       or (select revoked_at from help_access_grants where id = g) is null then
        raise exception 'FAIL: unmade, or its grant lives: %', v;
    end if;
    if exists (select 1 from memberships where user_id = '13813813-0000-0000-0000-000000000009'
                and role = 'observer' and is_trainer)
       or (v ->> 'unassigned')::int <> 2 or (v ->> 'assigned')::int <> 0 then
        raise exception 'FAIL: unmade, its assignments still read the businesses: %', v;
    end if;
    if pg_temp.as138('13813813-0000-0000-0000-000000000009',
        $q$select count(*)::text from orgs where id = '13800000-0000-0000-0000-000000000003'$q$) <> '0' then
        raise exception 'FAIL: the former trainer still reads an assigned business';
    end if;
    if not exists (select 1 from platform_actions where kind = 'trainer'
                    and summary like '%n''est plus formateur%2 entreprise%'
                    and jsonb_array_length(before -> 'assigned_orgs') = 2) then
        raise exception 'FAIL: the businesses lost not journaled';
    end if;
    if not exists (select 1 from platform_actions where kind = 'trainer' and summary like '%n''est plus formateur%') then
        raise exception 'FAIL: the end not journaled';
    end if;
    t := pg_temp.as138('13813813-0000-0000-0000-000000000001',
        $q$select platform_set_trainer('13813813-0000-0000-0000-0000000000ff', true)::text$q$);
    if t not like 'ERR:%n''existe pas%' then raise exception 'FAIL: an unknown account: %', t; end if;
    raise notice 'PASS: refused to an owner and a trainer; Mara makes a trainer (journaled once), reads its number, the console lists it; no number said; unmade, its grant ends and its two assignments go (journaled, counted); an unknown account refused';
end $$;
rollback;

\echo ''
\echo '--- TEST 10: the doors ---'
do $$
declare f text;
begin
    foreach f in array array[
        'help_state(uuid)', 'help_request_create(uuid,text,text,text,text,uuid,jsonb)',
        'platform_search(text)', 'platform_trainer_state(uuid)', 'platform_set_trainer(uuid,boolean)',
        'help_request_json(uuid)', 'help_inbox_row(uuid)'] loop
        if not (select prosecdef from pg_proc where oid = f::regprocedure) then
            raise exception 'FAIL: % is not a definer', f;
        end if;
        if not exists (select 1 from pg_proc where oid = f::regprocedure
                        and array_to_string(proconfig, ',') like 'search_path=%') then
            raise exception 'FAIL: % has no pinned path', f;
        end if;
        if has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: anon may call %', f;
        end if;
        if exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                    where p.oid = f::regprocedure and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
            raise exception 'FAIL: PUBLIC may call %', f;
        end if;
    end loop;
    foreach f in array array['help_state(uuid)', 'help_request_create(uuid,text,text,text,text,uuid,jsonb)',
                             'platform_search(text)', 'platform_trainer_state(uuid)',
                             'platform_set_trainer(uuid,boolean)'] loop
        if not has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: the app cannot call %', f;
        end if;
    end loop;
    foreach f in array array['help_request_json(uuid)', 'help_inbox_row(uuid)', 'org_ref(uuid)',
                             'help_subject_label(text)'] loop
        if has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: the app may call the internal %', f;
        end if;
    end loop;
    if exists (select 1 from pg_proc where proname in ('org_ref', 'help_subject_label')
                and not array_to_string(proconfig, ',') like 'search_path=%') then
        raise exception 'FAIL: a helper without a pinned path';
    end if;
    raise notice 'PASS: the doors definer and pinned, closed to anon and PUBLIC, open to the app where it calls them; the internal ones closed';
end $$;

\echo ''
\echo '--- TEST 11: RLS unchanged — a stranger reads no request ---'
begin;
do $$
declare n text;
begin
    perform pg_temp.as138('13813813-0000-0000-0000-000000000004',
        $q$select help_request_create('3f2a91c0-1380-0000-0000-000000000001', 'catalogue', 'Privé', 'call')::text$q$);
    n := pg_temp.as138('13813813-0000-0000-0000-000000000008', 'select count(*)::text from help_requests');
    if n <> '0' then raise exception 'FAIL: a stranger read % requests', n; end if;
    n := pg_temp.as138('13813813-0000-0000-0000-000000000005',
        $q$select count(*)::text from help_requests where org_id = '3f2a91c0-1380-0000-0000-000000000001'$q$);
    if n <> '0' then raise exception 'FAIL: the employee reads the owner''s request from the table: %', n; end if;
    raise notice 'PASS: a stranger reads no request; an employee never reads another''s from the table (nor through help_state: TEST 3)';
end $$;
rollback;

\echo ''
\echo 'test_batch138: all passed'
