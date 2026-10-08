-- ============================================================
-- 060_push_subscriptions.sql — where the bell can reach, when the app is closed.
--
-- The bell (030) writes one notifications row per recipient at the moments
-- worth interrupting somebody for — an order in, a delivery taken, a job on
-- the board. It rings only inside the app. A shopkeeper serving the counter
-- and a courier on a moto in traffic do not have the app open, so the ring
-- has to travel: Web Push, carried by the browser, delivered by a Worker
-- (workers/push) that a database webhook wakes on each notifications insert.
--
-- This migration is the address book that Worker reads: which browsers a
-- person has said "yes" in. One row per browser endpoint, owned by the
-- person, written only through save_push_subscription() as themselves.
--
-- Who reads it is the point. A push endpoint plus its keys lets anyone send
-- that browser notifications, so the rows are visible to their owner alone
-- under RLS, and the one function that hands them out (push_targets) is
-- executable by the service role only — the Worker's key, never the app's.
-- ============================================================

create table if not exists push_subscriptions (
    endpoint    text primary key,
    user_id     uuid not null references profiles(id) on delete cascade,
    p256dh      text not null,
    auth        text not null,
    user_agent  text,
    created_at  timestamptz not null default now(),
    last_seen   timestamptz not null default now()
);

create index if not exists push_subscriptions_by_user
    on push_subscriptions (user_id);

comment on table push_subscriptions is
    'Browsers that agreed to carry the bell. One row per endpoint, owned by '
    'the person; read out only by the push Worker through push_targets().';

alter table push_subscriptions enable row level security;

drop policy if exists push_subscriptions_own_select on push_subscriptions;
create policy push_subscriptions_own_select on push_subscriptions
    for select using (user_id = auth.uid());

drop policy if exists push_subscriptions_own_delete on push_subscriptions;
create policy push_subscriptions_own_delete on push_subscriptions
    for delete using (user_id = auth.uid());

-- ------------------------------------------------------------
-- The person says yes in this browser
-- ------------------------------------------------------------
-- An endpoint is unique to a browser profile and an origin; if one ever
-- reappears under another account (a shared phone, a sign-out and in) it
-- moves to the new owner rather than ringing the old one.
create or replace function save_push_subscription(
    p_endpoint   text,
    p_p256dh     text,
    p_auth       text,
    p_user_agent text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is null then
        raise exception 'save_push_subscription() needs a signed-in caller';
    end if;
    if coalesce(p_endpoint, '') = '' or coalesce(p_p256dh, '') = ''
       or coalesce(p_auth, '') = '' then
        raise exception 'A push subscription needs an endpoint and both keys';
    end if;
    insert into push_subscriptions (endpoint, user_id, p256dh, auth, user_agent)
    values (p_endpoint, auth.uid(), p_p256dh, p_auth, left(p_user_agent, 200))
    on conflict (endpoint) do update
        set user_id = excluded.user_id,
            p256dh = excluded.p256dh,
            auth = excluded.auth,
            user_agent = excluded.user_agent,
            last_seen = now();
end;
$$;

-- The person says no again, in this browser.
create or replace function remove_push_subscription(p_endpoint text)
returns void
language sql
security definer
set search_path = public
as $$
    delete from push_subscriptions
     where endpoint = p_endpoint and user_id = auth.uid();
$$;

-- ------------------------------------------------------------
-- What the Worker reads, and what it cleans up
-- ------------------------------------------------------------
-- Service role only (see grants): the Worker asks "where can I reach this
-- person?" and gets endpoints and keys, nothing else about them.
create or replace function push_targets(p_recipient uuid)
returns table (endpoint text, p256dh text, auth text)
language sql
stable
security definer
set search_path = public
as $$
    select s.endpoint, s.p256dh, s.auth
      from push_subscriptions s
     where s.user_id = p_recipient;
$$;

-- A browser that answered 404 or 410 has unsubscribed behind our back;
-- the Worker drops it so the next ring does not knock on a closed door.
create or replace function remove_push_target(p_endpoint text)
returns void
language sql
security definer
set search_path = public
as $$
    delete from push_subscriptions where endpoint = p_endpoint;
$$;

-- ------------------------------------------------------------
-- Who may call what
-- ------------------------------------------------------------
revoke execute on function save_push_subscription(text, text, text, text) from public;
revoke execute on function remove_push_subscription(text)                  from public;
revoke execute on function push_targets(uuid)                              from public;
revoke execute on function remove_push_target(text)                        from public;

do $$
begin
    -- Supabase's default privileges grant every new function to anon and
    -- authenticated directly, not through public — so "revoke from public"
    -- alone would leave the address book readable by any signed-in person.
    -- Named, explicitly, for the two functions that must never reach them.
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function push_targets(uuid)       from anon;
        revoke execute on function remove_push_target(text) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function push_targets(uuid)       from authenticated;
        revoke execute on function remove_push_target(text) from authenticated;
        grant execute on function save_push_subscription(text, text, text, text) to authenticated;
        grant execute on function remove_push_subscription(text)                  to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function push_targets(uuid)       to service_role;
        grant execute on function remove_push_target(text) to service_role;
    end if;
end $$;

notify pgrst, 'reload schema';
