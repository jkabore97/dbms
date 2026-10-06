-- ============================================================
-- test_cauris_leagues.sql — the weekly competition (086). Phone block 56.
--
-- The claims: a league is the kind of business, its city (set, or the
-- nearest town to its pin) and its size; the board shows the top 3, the
-- business's own rank and the gap to the place above, and a hidden name
-- stays hidden to others; spending never costs a place; the four-a-week
-- notification reaches every business that earned in its league, says the
-- top 3 and the gap, and not those who turned it off; the week's close pays
-- the top 3 once, gives the winner a free spot, and puts the badge on
-- their vitrine; and the board answers members only.
-- ============================================================
\set ON_ERROR_STOP on
-- 092 hides a vitrine below 8 items (test_vitrine_minimum.sql); this
-- suite is about something else, so it keeps the old rule (no minimum).
update platform_settings set value = '0' where key = 'vitrine_min_items';

\set owner '''56565656-0000-0000-0000-000000000001'''
\set other '''56565656-0000-0000-0000-000000000002'''
\set a     '''56000000-0000-0000-0000-00000000000a'''
\set b     '''56000000-0000-0000-0000-00000000000b'''
\set c     '''56000000-0000-0000-0000-00000000000c'''
\set d     '''56000000-0000-0000-0000-00000000000d'''
\set e     '''56000000-0000-0000-0000-00000000000e'''
\set bobo  '''56000000-0000-0000-0000-0000000000b0'''
\set farm  '''56000000-0000-0000-0000-0000000000f0'''

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
-- Earlier files re-run 081, whose window knows no badge: run 085 and 086
-- again so this file tests 086's own.
\i database/migrations/085_cauris_unlocks.sql
\i database/migrations/086_cauris_leagues.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22656000001', '{"full_name": "Awa"}'),
    (:other, '+22656000002', '{"full_name": "Autre"}');
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, lat, lng,
                  progress_since, city, board_hidden, board_notify) values
    -- A city of their own, so other files' shops in this cluster are not
    -- in their race.
    (:a,    'Alpha',      'alpha-56',  'retail', 'XOF', true, 12.37, -1.52, null, 'Ville 56', false, true),
    (:b,    'Bravo',      'bravo-56',  'retail', 'XOF', true, 12.38, -1.50, null, 'Ville 56', true,  true),
    (:c,    'Charlie',    'charlie-56','retail', 'XOF', true, 12.36, -1.53, null, 'Ville 56', false, false),
    (:d,    'Delta',      'delta-56',  'retail', 'XOF', true, 12.37, -1.51, null, 'Ville 56', false, true),
    (:e,    'Écho',       'echo-56',   'retail', 'XOF', true, null,  null,  null, 'Ville 56', false, true),
    ('56000000-0000-0000-0000-0000000000a9', 'Pin seul', 'pin-56', 'retail', 'XOF', true,
        12.40, -1.49, null, null, false, true),
    (:bobo, 'Bobo Shop',  'bobo-56',   'retail', 'XOF', true, 11.18, -4.29, null, null, false, true),
    (:farm, 'Ferme 56',   'ferme-56',  'farm',   'XOF', true, 12.37, -1.52, null, null, false, true);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
select id, '56565656-0000-0000-0000-000000000001', 'owner', 'org', id, 'full'
  from orgs where slug like '%-56';

-- This week's earnings (Alpha 120, Bravo 90, Charlie 60, Delta 30, Écho 0
-- but has earned before), the farm and Bobo in their own leagues.
insert into cauris_ledger (org_id, delta, reason, ref, created_at) values
    (:a, 120, 'order_done', 't56-a', cauris_week_start() + interval '1 hour'),
    (:b,  90, 'order_done', 't56-b', cauris_week_start() + interval '1 hour'),
    (:c,  60, 'order_done', 't56-c', cauris_week_start() + interval '1 hour'),
    (:d,  30, 'order_done', 't56-d', cauris_week_start() + interval '1 hour'),
    (:e,  10, 'order_done', 't56-e', cauris_week_start() - interval '20 days'),
    (:bobo, 500, 'order_done', 't56-bo', cauris_week_start() + interval '1 hour'),
    (:farm,  40, 'farm_log',  't56-f', cauris_week_start() + interval '1 hour'),
    -- Prizes and spending are not the race.
    (:d, 1000, 'prize', 't56-dp', cauris_week_start() + interval '2 hours'),
    (:a, -100, 'spent', 't56-as', cauris_week_start() + interval '2 hours');

\echo ''
\echo '--- TEST 1: leagues — kind, city, size ---'
do $$ begin
    if league_key('56000000-0000-0000-0000-00000000000a') <> 'retail|Ville 56|petites'
       or league_key('56000000-0000-0000-0000-00000000000e') <> 'retail|Ville 56|petites'
       or league_city('56000000-0000-0000-0000-0000000000a9') <> 'Ouagadougou'
       or league_key('56000000-0000-0000-0000-0000000000b0') <> 'retail|Bobo-Dioulasso|petites'
       or league_key('56000000-0000-0000-0000-0000000000f0') <> 'farm|Ouagadougou|petites' then
        raise exception 'FAIL: the leagues are not as drawn: % / % / % / %',
            league_key('56000000-0000-0000-0000-00000000000a'),
            league_key('56000000-0000-0000-0000-00000000000e'),
            league_key('56000000-0000-0000-0000-0000000000b0'),
            league_key('56000000-0000-0000-0000-0000000000f0');
    end if;
    raise notice 'PASS: %', league_label(league_key('56000000-0000-0000-0000-00000000000a'));
end $$;

\echo ''
\echo '--- TEST 2: the board — top 3, my rank, the gap; a hidden name stays hidden ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '56565656-0000-0000-0000-000000000001';
do $$
declare bd jsonb := league_board('56000000-0000-0000-0000-00000000000d');
begin
    if (bd ->> 'rank')::int <> 4 or (bd ->> 'score')::int <> 30
       or (bd ->> 'gap')::int <> 31
       or jsonb_array_length(bd -> 'top') <> 3
       or bd -> 'top' -> 0 ->> 'name' <> 'Alpha'
       or (bd -> 'top' -> 0 ->> 'score')::int <> 120
       or bd -> 'top' -> 1 ->> 'name' <> 'Une boutique de Ville 56'
       or (bd ->> 'size')::int <> 5 then
        raise exception 'FAIL: the board is not as drawn: %', bd;
    end if;
    raise notice 'PASS: 4th of %, 31 cauris from 3rd; Bravo shown as « %»',
        bd ->> 'size', bd -> 'top' -> 1 ->> 'name';
end $$;
-- Bravo sees its own name.
do $$ begin
    if league_board('56000000-0000-0000-0000-00000000000b') -> 'top' -> 1 ->> 'name' <> 'Bravo' then
        raise exception 'FAIL: a hidden business does not see its own name';
    end if;
end $$;
set local "request.jwt.claim.sub" = '56565656-0000-0000-0000-000000000002';
do $$ begin
    if league_board('56000000-0000-0000-0000-00000000000a') is not null then
        raise exception 'FAIL: a stranger reads the board';
    end if;
end $$;
commit;

\echo ''
\echo '--- TEST 3: four a week — the top 3 and the gap, not to those who opted out ---'
do $$
declare n int; msg text;
begin
    n := cauris_board_notify();
    select message into msg from notifications
     where org_id = '56000000-0000-0000-0000-00000000000d' and kind = 'cauris_board';
    if msg not like '🏆 Boutiques · Ville 56 · petites : 1. Alpha 120 · 2. une boutique 90 · 3. Charlie 60.%'
       or msg not like '%Vous êtes 4e : encore 31 cauris%' then
        raise exception 'FAIL: the message is not as drawn: %', msg;
    end if;
    if exists (select 1 from notifications
                where org_id = '56000000-0000-0000-0000-00000000000c' and kind = 'cauris_board') then
        raise exception 'FAIL: a business that opted out was told';
    end if;
    if (select message from notifications
         where org_id = '56000000-0000-0000-0000-00000000000a' and kind = 'cauris_board')
       not like '%Vous êtes 1er, bravo !%' then
        raise exception 'FAIL: the leader is not told it leads';
    end if;
    raise notice 'PASS: % told; Delta reads « % »', n, msg;
end $$;

\echo ''
\echo '--- TEST 4: the week closes once — prizes, a spot for the winner, the badge ---'
insert into cauris_ledger (org_id, delta, reason, ref, created_at) values
    ('56000000-0000-0000-0000-00000000000c', 300, 'order_done', 't56-cl',
     cauris_week_start() - interval '3 days'),
    ('56000000-0000-0000-0000-00000000000d', 200, 'order_done', 't56-dl',
     cauris_week_start() - interval '3 days'),
    ('56000000-0000-0000-0000-00000000000a', 100, 'order_done', 't56-al',
     cauris_week_start() - interval '3 days'),
    ('56000000-0000-0000-0000-00000000000b',  50, 'order_done', 't56-bl',
     cauris_week_start() - interval '3 days');
do $$
declare before_c int := cauris_balance('56000000-0000-0000-0000-00000000000c');
        before_b int := cauris_balance('56000000-0000-0000-0000-00000000000b');
        st jsonb;
begin
    perform cauris_week_close();
    perform cauris_week_close();   -- again: nothing more
    if cauris_balance('56000000-0000-0000-0000-00000000000c') <> before_c + 100
       or cauris_balance('56000000-0000-0000-0000-00000000000b') <> before_b then
        raise exception 'FAIL: prizes are not 100 for the winner, once, nothing for 4th';
    end if;
    if (select count(*) from cauris_ledger where reason = 'prize'
          and org_id = '56000000-0000-0000-0000-00000000000a') <> 1 then
        raise exception 'FAIL: the 3rd was not paid, or paid twice';
    end if;
    if not exists (select 1 from promotions where org_id = '56000000-0000-0000-0000-00000000000c'
                    and kind = 'shop' and free and status = 'approved') then
        raise exception 'FAIL: the winner has no free spot';
    end if;
    select style into st from storefront('charlie-56');
    if (st -> 'top_week' ->> 'rank')::int <> 1 then
        raise exception 'FAIL: the winner''s vitrine has no badge: %', st;
    end if;
    raise notice 'PASS: Charlie 1st (+100, a spot, the badge), once';
end $$;

\echo ''
\echo '--- TEST 5: the owner hides the name, stops the messages ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '56565656-0000-0000-0000-000000000001';
select set_board_prefs('56000000-0000-0000-0000-00000000000a', true, false);
commit;
do $$ begin
    if not (select board_hidden and not board_notify from orgs
             where id = '56000000-0000-0000-0000-00000000000a') then
        raise exception 'FAIL: the preferences were not kept';
    end if;
    if has_function_privilege('authenticated', 'cauris_week_close(date)', 'execute')
       or has_function_privilege('authenticated', 'cauris_board_notify()', 'execute')
       or has_function_privilege('anon', 'league_board(uuid)', 'execute') then
        raise exception 'FAIL: the schedule''s functions answer an app';
    end if;
    raise notice 'PASS: kept; the schedule is the database''s own';
end $$;

\echo ''
\echo 'test_cauris_leagues: all passed'
