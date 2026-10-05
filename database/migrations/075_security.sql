-- ============================================================
-- 075_security.sql — what the Sécurité page reads and does.
--
-- Before this, a person could change their password, and that was all:
-- no list of where the account was signed in, no way to close a phone that
-- was lost, no word when the account appeared on a new device, and nothing
-- an owner could require of the phones holding the shop's books.
--
--   1. user_devices: each phone or browser this account opened Kaj on,
--      named by the app (a local id, never a hardware one). register_device()
--      is called once per launch; a device seen for the first time, on an
--      account that already had one, rings that account's bell everywhere:
--      « Nouvelle connexion … ce n'était pas vous ? ».
--   2. my_sessions() / close_my_session() / close_my_other_sessions(): the
--      account's sign-in sessions (auth.sessions), its own and nobody
--      else's. Closing one ends its refresh; an access token already issued
--      lives out its hour, and the page says so.
--   3. security_events: the account's own security history — new devices,
--      password and code changes, sessions closed, an admin's sign-out —
--      read by my_security_events().
--   4. orgs.lock_max_minutes: an owner's rule for the team's phones — the
--      app locks with the code after at most this many minutes away.
--      my_lock_policy() gives the strictest rule across the person's
--      businesses; set_lock_policy() is the owner's.
--   5. sign_out_member(): a lost phone. An admin closes every session of a
--      member of their business (never an owner's, never their own).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Devices
-- ------------------------------------------------------------
create table if not exists user_devices (
    user_id    uuid not null references profiles(id) on delete cascade,
    device_id  text not null check (length(device_id) between 8 and 64),
    label      text not null default 'Appareil',
    first_seen timestamptz not null default now(),
    last_seen  timestamptz not null default now(),
    primary key (user_id, device_id)
);
alter table user_devices enable row level security;
-- No policies: read and written through the functions below.

create table if not exists security_events (
    id      bigint generated always as identity primary key,
    user_id uuid not null references profiles(id) on delete cascade,
    kind    text not null,
    detail  text,
    at      timestamptz not null default now()
);
create index if not exists security_events_by_user on security_events (user_id, at desc);
alter table security_events enable row level security;

create or replace function security_log(p_user uuid, p_kind text, p_detail text)
returns void
language sql
security definer
set search_path = public
as $$
    insert into security_events (user_id, kind, detail) values (p_user, p_kind, p_detail);
$$;

-- Called once per launch. Returns true when this device is new to the
-- account.
create or replace function register_device(p_device_id text, p_label text)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_me    uuid := auth.uid();
    v_label text := left(coalesce(nullif(btrim(p_label), ''), 'Appareil'), 80);
    v_new   boolean;
    v_had   boolean;
begin
    if v_me is null then
        raise exception 'register_device() needs a signed-in caller';
    end if;
    select exists (select 1 from user_devices where user_id = v_me) into v_had;
    insert into user_devices (user_id, device_id, label)
    values (v_me, p_device_id, v_label)
    on conflict (user_id, device_id)
    do update set last_seen = now(), label = excluded.label
    returning (xmax = 0) into v_new;
    if v_new then
        perform security_log(v_me, 'new_device', v_label);
        if v_had then
            begin
                insert into notifications (recipient_id, org_id, kind, message)
                values (v_me, null, 'new_device',
                        'Nouvelle connexion à votre compte sur ' || v_label
                        || '. Ce n''était pas vous ? Ouvrez Compte › Sécurité '
                        || 'et fermez les autres appareils.');
            exception when others then null;
            end;
        end if;
    end if;
    return v_new;
end;
$$;

-- ------------------------------------------------------------
-- 2. Sessions
-- ------------------------------------------------------------
create or replace function my_sessions()
returns table (
    id         uuid,
    created_at timestamptz,
    last_used  timestamptz,
    user_agent text,
    ip         text,
    current    boolean
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select s.id, s.created_at,
           coalesce(s.refreshed_at at time zone 'UTC', s.updated_at),
           s.user_agent, host(s.ip),
           s.id::text = (auth.jwt() ->> 'session_id')
    from auth.sessions s
    where s.user_id = auth.uid()
    order by (s.id::text = (auth.jwt() ->> 'session_id')) desc,
             coalesce(s.refreshed_at at time zone 'UTC', s.updated_at) desc;
$$;

create or replace function close_my_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_rows int;
begin
    if auth.uid() is null then
        raise exception 'close_my_session() needs a signed-in caller';
    end if;
    if p_session_id::text = (auth.jwt() ->> 'session_id') then
        raise exception 'C''est cet appareil : utilisez « Se déconnecter »';
    end if;
    delete from auth.sessions where id = p_session_id and user_id = auth.uid();
    get diagnostics v_rows = row_count;
    if v_rows = 0 then
        raise exception 'Session introuvable';
    end if;
    perform security_log(auth.uid(), 'session_closed', null);
end;
$$;

create or replace function close_my_other_sessions()
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_rows int;
begin
    if auth.uid() is null then
        raise exception 'close_my_other_sessions() needs a signed-in caller';
    end if;
    delete from auth.sessions
     where user_id = auth.uid()
       and id::text is distinct from (auth.jwt() ->> 'session_id');
    get diagnostics v_rows = row_count;
    perform security_log(auth.uid(), 'signed_out_others', v_rows::text);
    return v_rows;
end;
$$;

-- ------------------------------------------------------------
-- 3. The account's history
-- ------------------------------------------------------------
-- What the app itself reports: a password or a code changed.
create or replace function log_security_event(p_kind text, p_detail text default null)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'log_security_event() needs a signed-in caller';
    end if;
    if p_kind not in ('password_changed', 'pin_changed', 'lock_changed') then
        raise exception 'Événement inconnu : %', p_kind;
    end if;
    perform security_log(auth.uid(), p_kind, left(p_detail, 120));
end;
$$;

create or replace function my_security_events(p_limit integer default 20)
returns table (kind text, detail text, at timestamptz)
language sql
stable
security definer
set search_path = public, auth
as $$
    select e.kind, e.detail, e.at
    from security_events e
    where e.user_id = auth.uid()
    order by e.at desc
    limit least(greatest(coalesce(p_limit, 20), 1), 100);
$$;

create or replace function my_devices()
returns table (device_id text, label text, first_seen timestamptz, last_seen timestamptz)
language sql
stable
security definer
set search_path = public, auth
as $$
    select d.device_id, d.label, d.first_seen, d.last_seen
    from user_devices d
    where d.user_id = auth.uid()
    order by d.last_seen desc;
$$;

-- ------------------------------------------------------------
-- 4. The team's lock rule
-- ------------------------------------------------------------
alter table orgs add column if not exists lock_max_minutes integer;
do $$ begin
    if not exists (select 1 from pg_constraint where conname = 'orgs_lock_max_minutes_range') then
        alter table orgs add constraint orgs_lock_max_minutes_range
            check (lock_max_minutes is null or lock_max_minutes between 1 and 60);
    end if;
end $$;

create or replace function set_lock_policy(p_org_id uuid, p_minutes integer)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur fixe la règle de verrouillage';
    end if;
    if p_minutes is not null and (p_minutes < 1 or p_minutes > 60) then
        raise exception 'Entre 1 et 60 minutes';
    end if;
    update orgs set lock_max_minutes = p_minutes where id = p_org_id;
end;
$$;

-- The strictest rule among the person's businesses; null when none has one.
create or replace function my_lock_policy()
returns integer
language sql
stable
security definer
set search_path = public, auth
as $$
    select min(o.lock_max_minutes)
    from memberships m
    join orgs o on o.id = m.org_id
    where m.user_id = auth.uid() and o.archived_at is null;
$$;

create or replace function org_lock_policy(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public, auth
as $$
    select lock_max_minutes from orgs
     where id = p_org_id and is_org_member(p_org_id);
$$;

-- ------------------------------------------------------------
-- 5. A lost phone
-- ------------------------------------------------------------
create or replace function sign_out_member(p_org_id uuid, p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_rows int;
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur peut déconnecter un membre';
    end if;
    if p_user_id = auth.uid() then
        raise exception 'Pour vous-même : Compte › Sécurité';
    end if;
    if not exists (select 1 from memberships
                    where org_id = p_org_id and user_id = p_user_id) then
        raise exception 'Cette personne n''est pas membre de l''entreprise';
    end if;
    if exists (select 1 from memberships
                where user_id = p_user_id and org_id = p_org_id
                  and role in ('owner', 'super_admin')) then
        raise exception 'Le propriétaire ne peut pas être déconnecté par un autre';
    end if;
    delete from auth.sessions where user_id = p_user_id;
    get diagnostics v_rows = row_count;
    perform security_log(p_user_id, 'signed_out_by_admin',
        (select name from orgs where id = p_org_id));
    return v_rows;
end;
$$;

-- ------------------------------------------------------------
-- Grants
-- ------------------------------------------------------------
revoke execute on function security_log(uuid, text, text)        from public;
revoke execute on function register_device(text, text)           from public;
revoke execute on function my_sessions()                         from public;
revoke execute on function close_my_session(uuid)                from public;
revoke execute on function close_my_other_sessions()             from public;
revoke execute on function log_security_event(text, text)        from public;
revoke execute on function my_security_events(integer)           from public;
revoke execute on function my_devices()                          from public;
revoke execute on function set_lock_policy(uuid, integer)        from public;
revoke execute on function my_lock_policy()                      from public;
revoke execute on function org_lock_policy(uuid)                 from public;
revoke execute on function sign_out_member(uuid, uuid)           from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function register_device(text, text)       to authenticated;
        grant execute on function my_sessions()                     to authenticated;
        grant execute on function close_my_session(uuid)            to authenticated;
        grant execute on function close_my_other_sessions()         to authenticated;
        grant execute on function log_security_event(text, text)    to authenticated;
        grant execute on function my_security_events(integer)       to authenticated;
        grant execute on function my_devices()                      to authenticated;
        grant execute on function set_lock_policy(uuid, integer)    to authenticated;
        grant execute on function my_lock_policy()                  to authenticated;
        grant execute on function org_lock_policy(uuid)             to authenticated;
        grant execute on function sign_out_member(uuid, uuid)       to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
