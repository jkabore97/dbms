-- ============================================================
-- test_batch187.sql — 187: Mara's message to everyone.
--
-- The claims:
--   1. 'everyone': every account once — a shopper with no business, a
--      courier, a business's owner and its employee — in its own bell
--      (scope 'me', no business), « Marakaj : … »; the reach says so;
--   2. the two audiences of before as they were (the owner, or the team);
--   3. only the platform; an admin given « La rue » only cannot; an empty
--      or unknown audience refused;
--   4. the doors.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
\i database/migrations/187_message_everyone.sql
\i database/migrations/187_message_everyone.sql

begin;
-- only this test's accounts count
delete from notifications;
delete from push_subscriptions;
create temp table keep187 as select id from auth.users;

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('18718718-0000-0000-0000-000000000001', '22618710001', 'jo187@example.com', '{"full_name": "Jo Plateforme"}', now()),
    ('18718718-0000-0000-0000-000000000002', '22618710002', 'awa187@example.com', '{"full_name": "Awa Patronne"}', now()),
    ('18718718-0000-0000-0000-000000000003', '22618710003', 'ali187@example.com', '{"full_name": "Ali Employé"}', now()),
    ('18718718-0000-0000-0000-000000000004', '22618710004', 'zoe187@example.com', '{"full_name": "Zoé Cliente"}', now()),
    ('18718718-0000-0000-0000-000000000005', '22618710005', 'max187@example.com', '{"full_name": "Max La Rue"}', now());
insert into profiles (id, full_name) values
    ('18718718-0000-0000-0000-000000000001', 'Jo'), ('18718718-0000-0000-0000-000000000002', 'Awa'),
    ('18718718-0000-0000-0000-000000000003', 'Ali'), ('18718718-0000-0000-0000-000000000004', 'Zoé'),
    ('18718718-0000-0000-0000-000000000005', 'Max')
on conflict (id) do update set full_name = excluded.full_name;
update profiles set is_platform_admin = true, platform_access = null where id = '18718718-0000-0000-0000-000000000001';
update profiles set is_platform_admin = true, platform_access = '{street}' where id = '18718718-0000-0000-0000-000000000005';
insert into orgs (id, name, slug, profile, default_currency) values
    ('18718718-1111-0000-0000-000000000001', 'Boutique Awa 187', 'boutique-awa-187', 'shop', 'XOF');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('18718718-0000-0000-0000-000000000002', '18718718-1111-0000-0000-000000000001', 'owner', 'org', '18718718-1111-0000-0000-000000000001', 'full'),
    ('18718718-0000-0000-0000-000000000003', '18718718-1111-0000-0000-000000000001', 'employee', 'org', '18718718-1111-0000-0000-000000000001', 'own');
insert into push_subscriptions (endpoint, user_id, p256dh, auth, platform)
values ('https://push.example/zoe187', '18718718-0000-0000-0000-000000000004', 'k', 'a', 'web');

create or replace function pg_temp.as_(p_user text, p_path text) returns void
language sql as $$
    select set_config('request.jwt.claim.sub', p_user, true),
           set_config('request.jwt.claims', jsonb_build_object('sub', p_user, 'aal', 'aal2')::text, true),
           set_config('request.path', p_path, true);
$$;

-- 1. everyone
do $$
declare n int; r jsonb; v_all int := (select count(*) from profiles p join auth.users u on u.id = p.id);
begin
    perform pg_temp.as_('18718718-0000-0000-0000-000000000001', '/rpc/platform_message_reach');
    r := platform_message_reach();
    assert (r ->> 'everyone')::int = v_all and (r ->> 'everyone_push')::int = 1
       and (r ->> 'admins')::int >= 1 and (r ->> 'team')::int >= 2, 'the reach: ' || r::text;
    perform pg_temp.as_('18718718-0000-0000-0000-000000000001', '/rpc/platform_message_send');
    n := platform_message_send(null, '  Mettez à jour Marakaj  ', 'everyone');
    assert n = v_all, 'every account: ' || n || ' of ' || v_all;
    assert (select count(*) from notifications where kind = 'platform_message'
             and recipient_id::text like '18718718-%') = 5, 'each of the five, once';
    assert (select bool_and(org_id is null and scope = 'me' and message = 'Marakaj : Mettez à jour Marakaj'
                            and params ->> 'audience' = 'everyone')
              from notifications where kind = 'platform_message'), 'in each one''s own bell';
    assert exists (select 1 from notifications where recipient_id = '18718718-0000-0000-0000-000000000004'), 'the shopper with no business';
    raise notice 'PASS: everyone — every account once, in its own bell; the reach says so';
end $$;

-- 2. the audiences of before
do $$
declare n int;
begin
    delete from notifications;
    perform pg_temp.as_('18718718-0000-0000-0000-000000000001', '/rpc/platform_message_send');
    n := platform_message_send('18718718-1111-0000-0000-000000000001', 'Bonjour', 'admins');
    assert n = 1 and (select recipient_id from notifications) = '18718718-0000-0000-0000-000000000002', 'the owner';
    n := platform_message_send('18718718-1111-0000-0000-000000000001', 'Bonjour', 'team');
    assert n = 2, 'the team';
    assert (select bool_and(message = 'Kaj : Bonjour' and scope = 'shop') from notifications), 'as before';
    n := send_platform_message('18718718-1111-0000-0000-000000000001', 'Encore');
    assert n = 1, '072''s door';
    raise notice 'PASS: the owners, the teams — as before';
end $$;

-- 3. only the platform
do $$
declare v_err text;
begin
    perform pg_temp.as_('18718718-0000-0000-0000-000000000002', '/rpc/platform_message_send');
    begin perform platform_message_send(null, 'x', 'everyone'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Seule la plateforme écrit aux boutiques', 'a shop owner: ' || v_err;
    perform pg_temp.as_('18718718-0000-0000-0000-000000000005', '/rpc/platform_message_send');
    begin perform platform_message_send(null, 'x', 'everyone'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Seule la plateforme écrit aux boutiques', 'an admin of « La rue » only: ' || v_err;
    perform pg_temp.as_('18718718-0000-0000-0000-000000000001', '/rpc/platform_message_send');
    begin perform platform_message_send(null, '   ', 'everyone'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Le message est vide', 'empty: ' || v_err;
    begin perform platform_message_send(null, 'x', 'nobody'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Destinataires inconnus : nobody', 'unknown: ' || v_err;
    raise notice 'PASS: only the platform';
end $$;

-- 4. the doors
do $$ begin
    assert not has_function_privilege('anon', 'platform_message_reach()', 'execute')
       and not has_function_privilege('anon', 'platform_message_send(uuid, text, text)', 'execute'), 'closed to anon';
    assert has_function_privilege('authenticated', 'platform_message_reach()', 'execute')
       and has_function_privilege('authenticated', 'platform_message_send(uuid, text, text)', 'execute'), 'the signed-in''s';
    raise notice 'PASS: the doors';
end $$;
rollback;
