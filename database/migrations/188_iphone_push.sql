-- ============================================================
-- 188 — The iPhone takes notifications.
--
-- Found while making the owner's update message reach everyone (187): the
-- iPhone app took no push at all — the address book knew browsers and
-- Android phones only (115). Apple's side is now ready (Push Notifications
-- on bf.kaj.app, the APNs key in Firebase); an iPhone's ring goes through
-- Firebase Cloud Messaging like an Android phone's, its token the same kind
-- of address.
--
--   * push_subscriptions.platform: 'ios' beside 'web' and 'android'; an
--     iPhone has its token, as a phone does.
--   * save_fcm_token (115): the same call, the same two arguments — every
--     Android build of before unchanged; a phone that names itself an
--     iPhone (its label, « iPhone… ») is written 'ios'.
--   * The Worker sends to 'ios' as to 'android', with Apple's part of the
--     message (workers/push).
--
-- Shop, farm, association: their people on an iPhone hear their bells as
-- on Android; nothing else changes.
-- ============================================================

alter table push_subscriptions drop constraint if exists push_subscriptions_platform_check;
alter table push_subscriptions add constraint push_subscriptions_platform_check
    check (platform in ('web', 'android', 'ios'));
alter table push_subscriptions drop constraint if exists push_subscriptions_shape;
alter table push_subscriptions add constraint push_subscriptions_shape
    check ((platform = 'web' and p256dh is not null and auth is not null)
        or (platform in ('android', 'ios') and fcm_token is not null));

create or replace function save_fcm_token(p_token text, p_label text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_token text := btrim(coalesce(p_token, ''));
    -- 188: the iPhone app says so in its label; everything else is Android
    v_platform text := case when coalesce(p_label, '') ~* '^(iphone|ipad|ios)' then 'ios' else 'android' end;
begin
    if auth.uid() is null then
        raise exception 'save_fcm_token() needs a signed-in caller';
    end if;
    if v_token = '' or length(v_token) > 4096 then
        raise exception 'A phone''s push token is missing';
    end if;
    insert into push_subscriptions (endpoint, user_id, platform, fcm_token, user_agent)
    values ('fcm:' || v_token, auth.uid(), v_platform, v_token, left(p_label, 200))
    on conflict (endpoint) do update
        set user_id = excluded.user_id,
            platform = excluded.platform,
            fcm_token = excluded.fcm_token,
            user_agent = excluded.user_agent,
            last_seen = now();
end;
$$;

revoke execute on function save_fcm_token(text, text) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function save_fcm_token(text, text) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function save_fcm_token(text, text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
