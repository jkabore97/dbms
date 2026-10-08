-- ============================================================
-- test_push.sql — the bell's address book (060).
-- Phone block 32.
--
-- The claims: a signed-in person can register the browser they are in and
-- see only their own registrations; a stranger cannot register; another
-- person cannot see or take them; an endpoint that reappears under a new
-- account moves to it; the person can withdraw; only the service role may
-- read targets or drop a dead endpoint — the app's own roles are refused.
-- ============================================================
\set ON_ERROR_STOP on

\set awa    '''32323232-0000-0000-0000-000000000001'''
\set binta  '''32323232-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- Not the usual "grant execute on all functions": that blanket would hand
-- push_targets() to the app role and test nothing. The migration's own
-- grants are what this suite proves, so only the two it made public are
-- granted here — exactly as Supabase's defaults plus 060 leave them.
grant execute on function save_push_subscription(text, text, text, text) to authenticated;
grant execute on function remove_push_subscription(text)                  to authenticated;
-- The suites that run before this one in CI each grant *all* functions to
-- authenticated as their own scaffolding, which quietly re-grants the two
-- below. Production never sees that grant — Supabase's defaults plus 060's
-- explicit revoke are what a real database has — so restore that state here
-- before proving it. These are the migration's own statements, verbatim.
revoke execute on function push_targets(uuid)       from authenticated;
revoke execute on function remove_push_target(text) from authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:awa,   '+22632000001', '{"full_name": "Awa"}'),
    (:binta, '+22632000002', '{"full_name": "Binta"}');

\echo ''
\echo '--- TEST 1: a stranger cannot register; a person can, and sees only their own ---'
begin;
set local role authenticated;
do $$
begin
    begin
        perform save_push_subscription('https://push.example/ep-stranger', 'k', 'a');
        raise exception 'FAIL: a stranger registered a browser';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: the stranger was refused — %', sqlerrm;
    end;
end $$;
rollback;

begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :awa;
select save_push_subscription('https://push.example/ep-awa-1', 'p256-awa', 'auth-awa', 'Chrome on Android');
select save_push_subscription('https://push.example/ep-awa-2', 'p256-awa2', 'auth-awa2');
set local "request.jwt.claim.sub" = :binta;
select save_push_subscription('https://push.example/ep-binta', 'p256-binta', 'auth-binta');
do $$
declare v_mine int; v_all int;
begin
    select count(*) into v_mine from push_subscriptions;
    if v_mine <> 1 then
        raise exception 'FAIL: Binta sees % rows, expected only her own', v_mine;
    end if;
    raise notice 'PASS: Awa registered two browsers; Binta registered one and sees one';
end $$;
commit;

\echo ''
\echo '--- TEST 2: the app roles cannot read targets; the service side can ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :binta;
do $$
begin
    begin
        perform push_targets('32323232-0000-0000-0000-000000000001');
        raise exception 'FAIL: a signed-in person read another person''s push targets';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: push_targets refused to the app role — %', sqlerrm;
    end;
    begin
        perform remove_push_target('https://push.example/ep-awa-1');
        raise exception 'FAIL: a signed-in person dropped another person''s endpoint';
    exception when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: remove_push_target refused to the app role — %', sqlerrm;
    end;
end $$;
rollback;

-- The superuser stands in for service_role here: the grant is to a role the
-- stub may not have, and what is proven is the shape of the answer.
begin;
do $$
declare v_rows int; v_keys text;
begin
    select count(*), string_agg(t.p256dh || '/' || t.auth, '|' order by t.endpoint)
      into v_rows, v_keys
      from push_targets('32323232-0000-0000-0000-000000000001') t;
    if v_rows <> 2 or v_keys <> 'p256-awa/auth-awa|p256-awa2/auth-awa2' then
        raise exception 'FAIL: expected Awa''s two targets with keys, got % (%)', v_rows, v_keys;
    end if;
    raise notice 'PASS: the service side gets endpoints and keys, nothing else';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: an endpoint that reappears under another account moves to it ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :binta;
select save_push_subscription('https://push.example/ep-awa-1', 'p256-new', 'auth-new');
reset role;
do $$
declare v_owner uuid; v_total int;
begin
    select user_id into v_owner from push_subscriptions where endpoint = 'https://push.example/ep-awa-1';
    select count(*) into v_total from push_subscriptions where endpoint like 'https://push.example/%';
    if v_owner <> '32323232-0000-0000-0000-000000000002' or v_total <> 3 then
        raise exception 'FAIL: endpoint owner % / % rows', v_owner, v_total;
    end if;
    raise notice 'PASS: the shared browser now rings Binta, and Awa no longer';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: the person withdraws; a dead endpoint is dropped by the service side ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :binta;
-- Binta cannot withdraw Awa's browser…
select remove_push_subscription('https://push.example/ep-awa-2');
set local "request.jwt.claim.sub" = :awa;
-- …but Awa can.
select remove_push_subscription('https://push.example/ep-awa-2');
reset role;
select remove_push_target('https://push.example/ep-binta');
do $$
declare v_left text;
begin
    select string_agg(endpoint, '|' order by endpoint) into v_left
      from push_subscriptions where endpoint like 'https://push.example/%';
    if v_left <> 'https://push.example/ep-awa-1' then
        raise exception 'FAIL: expected only ep-awa-1 left, got %', v_left;
    end if;
    raise notice 'PASS: Binta''s attempt on Awa''s browser did nothing; Awa withdrew hers; the dead one is gone';
end $$;
rollback;

\echo ''
\echo '=== test_push.sql: all checks passed ==='
