-- ============================================================
-- test_batch188.sql — 188: the iPhone takes notifications.
--
-- The claims:
--   1. an iPhone's token (« iPhone » in its label) is written 'ios', an
--      Android phone's 'android' as before (no label too);
--   2. push_devices hands both to the Worker; a token that moves to another
--      account and another kind moves whole;
--   3. an iPhone without a token is refused (the shape); the doors.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
\i database/migrations/188_iphone_push.sql
\i database/migrations/188_iphone_push.sql

begin;
insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('18818818-0000-0000-0000-000000000001', '22618810001', 'ivy188@example.com', '{"full_name": "Ivy iPhone"}', now()),
    ('18818818-0000-0000-0000-000000000002', '22618810002', 'ali188@example.com', '{"full_name": "Ali Android"}', now());
insert into profiles (id, full_name) values
    ('18818818-0000-0000-0000-000000000001', 'Ivy'), ('18818818-0000-0000-0000-000000000002', 'Ali')
on conflict (id) do update set full_name = excluded.full_name;

do $$
declare v_err text;
begin
    perform set_config('request.jwt.claim.sub', '18818818-0000-0000-0000-000000000001', true);
    perform save_fcm_token('tok-ivy-188', 'iPhone');
    perform set_config('request.jwt.claim.sub', '18818818-0000-0000-0000-000000000002', true);
    perform save_fcm_token('tok-ali-188', 'Android');
    perform save_fcm_token('tok-ali2-188', null);
    assert (select platform from push_subscriptions where endpoint = 'fcm:tok-ivy-188') = 'ios', 'the iPhone';
    assert (select platform from push_subscriptions where endpoint = 'fcm:tok-ali-188') = 'android'
       and (select platform from push_subscriptions where endpoint = 'fcm:tok-ali2-188') = 'android', 'Android as before';
    raise notice 'PASS: an iPhone is written ios, Android as before';

    assert (select platform from push_devices('18818818-0000-0000-0000-000000000001')) = 'ios'
       and (select fcm_token from push_devices('18818818-0000-0000-0000-000000000001')) = 'tok-ivy-188', 'the Worker reads the iPhone';
    -- the same token, now an iPhone under Ali (a phone handed over, reinstalled)
    perform save_fcm_token('tok-ali-188', 'iPhone 15');
    assert (select platform from push_subscriptions where endpoint = 'fcm:tok-ali-188') = 'ios', 'moved whole';
    raise notice 'PASS: push_devices gives both to the Worker; a token moves whole';

    begin
        insert into push_subscriptions (endpoint, user_id, platform) values ('fcm:x', '18818818-0000-0000-0000-000000000001', 'ios');
        v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err like '%push_subscriptions_shape%', 'an iPhone without its token: ' || v_err;
    assert not has_function_privilege('anon', 'save_fcm_token(text, text)', 'execute')
       and has_function_privilege('authenticated', 'save_fcm_token(text, text)', 'execute'), 'the doors';
    raise notice 'PASS: the shape and the doors';
end $$;
rollback;
