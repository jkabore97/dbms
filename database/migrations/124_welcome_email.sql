-- ============================================================
-- 124_welcome_email.sql — Mara says hello, once, by e-mail.
--
-- The owner: a welcome e-mail through Resend, from
-- « Mara <bienvenue@marakaj.com> », replies to hello@kaj-consulting.com.
-- This migration is the database's half; workers/mail (kaj-mail) sends.
--
-- Wired exactly as the push bell is (115, README « Push notifications »):
-- the database writes a row, a Supabase Database Webhook created by the
-- owner in the dashboard (table welcome_emails, INSERT) posts it to the
-- Worker with « Authorization: Bearer <MAIL_WEBHOOK_SECRET> », and the
-- Worker answers through two functions granted to the service role
-- alone. No URL and no secret ever live in the database.
--
--   1. welcome_emails(user_id pk, status, lang, requested_at, sent_at, …):
--      one row per person, ever — the primary key is the « never twice ».
--      status: pending (asked) → sending (claimed by the Worker, before
--      Resend is called) → sent | failed; 'off' when the switch was turned
--      off between the ask and the send. A row that is not pending is
--      never sent again, even if the Worker is called again for it.
--   2. The ask: a trigger on auth.users (after insert, and after an update
--      of email or email_confirmed_at) inserts the pending row the first
--      time an account has a confirmed e-mail address:
--        * Google sign-in — the account is born with a confirmed address
--          (insert);
--        * e-mail and password — when the link is clicked (update of
--          email_confirmed_at), or at once if confirmation is off;
--        * a phone or WhatsApp account — when it first adds and confirms
--          an address (update of email), if it was created after 124.
--      The profile already exists then: 004's on_auth_user_created runs
--      first (triggers fire by name, « on_… » before « welcome_… »).
--   3. NO BACKFILL. The owner does not want to e-mail everybody already
--      signed up. The moment 124 first ran is kept
--      (platform_settings.welcome_email_since_marked, internal, never
--      rewritten by a second run) and an account created before it is
--      never asked for — not now, not when it later changes or confirms
--      its address. No row is written for existing accounts.
--   4. Non-blocking: the trigger swallows every error (as 115's bells do),
--      and the webhook is pg_net's asynchronous call — a missing webhook,
--      a Worker down or Resend refusing never stops a sign-up.
--   5. The switch: platform setting `welcome_email_on` (default true),
--      in Réglages › Comptes. Off, nothing is asked; a row asked before
--      it was turned off is marked 'off' by the Worker's claim, not sent.
--   6. welcome_email_claim(user) / welcome_email_done(user, ok, id, error):
--      the Worker's two calls (service role only). The claim moves
--      pending → sending under a row lock and hands back the address, the
--      first name and the language; a second claim gets « already ».
--
-- The language: the app's chosen language is kept per device (LocalDb,
-- core/l10n/locale_controller.dart), never on the server. The account's
-- own metadata may carry a locale (raw_user_meta_data locale/lang); en…
-- gives 'en', fr… 'fr', otherwise null — and the Worker writes French
-- with a short English line.
--
-- Shop, farm and association alike: the welcome is per person — an
-- account, before it has any business, of any kind, or none (a shopper,
-- a courier). Nothing a business, a vitrine or the street shows changes
-- (P1).
--
-- Re-runnable (the bundle runs twice): table if not exists, settings on
-- conflict do nothing, functions replaced with their arguments unchanged,
-- the trigger dropped and created.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The record of who was welcomed
-- ------------------------------------------------------------
create table if not exists welcome_emails (
    user_id      uuid primary key references profiles(id) on delete cascade,
    status       text not null default 'pending',
    lang         text,
    requested_at timestamptz not null default now(),
    claimed_at   timestamptz,
    sent_at      timestamptz,
    resend_id    text,
    error        text
);
alter table welcome_emails drop constraint if exists welcome_emails_status;
alter table welcome_emails add  constraint welcome_emails_status
    check (status in ('pending', 'sending', 'sent', 'failed', 'off'));
alter table welcome_emails drop constraint if exists welcome_emails_lang;
alter table welcome_emails add  constraint welcome_emails_lang
    check (lang is null or lang in ('fr', 'en'));
alter table welcome_emails enable row level security;
-- No policy: nobody reads or writes it from the app. The trigger and the
-- Worker's two functions are definers; the webhook reads the inserted row.
revoke all on welcome_emails from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on welcome_emails from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on welcome_emails from authenticated;
    end if;
end $$;

comment on table welcome_emails is
    'One welcome e-mail per person, ever (124). Written by the auth.users trigger, sent by workers/mail through a Database Webhook on INSERT.';

-- ------------------------------------------------------------
-- 3, 5. The switch, and when 124 first ran (no backfill)
-- ------------------------------------------------------------
insert into platform_settings (key, value) values
    ('welcome_email_on',           'true'),
    ('welcome_email_since_marked', to_jsonb(now()))
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- 2. The ask
-- ------------------------------------------------------------
create or replace function trg_welcome_email_request()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_since timestamptz;
    v_born  timestamptz;
    v_meta  text;
begin
    if new.email is null or btrim(new.email) = '' or new.email_confirmed_at is null then
        return new;
    end if;
    if tg_op = 'UPDATE' and old.email is not distinct from new.email
       and old.email_confirmed_at is not null then
        return new;  -- nothing about the address changed
    end if;
    if not coalesce((select value = 'true'::jsonb from platform_settings
                      where key = 'welcome_email_on'), true) then
        return new;
    end if;
    -- No backfill: an account older than 124 is never welcomed.
    select (value #>> '{}')::timestamptz into v_since
      from platform_settings where key = 'welcome_email_since_marked';
    v_born := coalesce((to_jsonb(new) ->> 'created_at')::timestamptz, now());
    if v_since is null or v_born < v_since then
        return new;
    end if;
    v_meta := lower(coalesce(new.raw_user_meta_data ->> 'locale',
                             new.raw_user_meta_data ->> 'lang', ''));
    insert into welcome_emails (user_id, lang)
    select p.id, case when v_meta like 'en%' then 'en'
                      when v_meta like 'fr%' then 'fr' end
      from profiles p where p.id = new.id
    on conflict (user_id) do nothing;
    return new;
exception when others then
    -- A welcome is never worth a failed sign-up.
    return new;
end;
$$;

drop trigger if exists welcome_email_request on auth.users;
create trigger welcome_email_request
after insert or update of email, email_confirmed_at on auth.users
for each row execute function trg_welcome_email_request();

-- ------------------------------------------------------------
-- 6. The Worker's two calls
-- ------------------------------------------------------------
-- pending → sending, under a lock, and what the e-mail needs. Anything
-- else answers send = false with the reason, and nothing changes but an
-- 'off' when the switch was turned off meanwhile.
create or replace function welcome_email_claim(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_row   welcome_emails;
    v_email text;
    v_first text;
begin
    select * into v_row from welcome_emails where user_id = p_user for update;
    if not found then
        return jsonb_build_object('send', false, 'reason', 'not asked');
    end if;
    if v_row.status <> 'pending' then
        return jsonb_build_object('send', false, 'reason', 'already ' || v_row.status);
    end if;
    if not coalesce((select value = 'true'::jsonb from platform_settings
                      where key = 'welcome_email_on'), true) then
        update welcome_emails set status = 'off' where user_id = p_user;
        return jsonb_build_object('send', false, 'reason', 'switched off');
    end if;
    select nullif(btrim(u.email), ''),
           nullif(btrim(coalesce(
               nullif(btrim(p.first_name), ''),
               split_part(nullif(btrim(p.full_name), ''), ' ', 1),
               nullif(btrim(u.raw_user_meta_data ->> 'given_name'), ''),
               split_part(nullif(btrim(coalesce(u.raw_user_meta_data ->> 'full_name',
                                                 u.raw_user_meta_data ->> 'name')), ''), ' ', 1))), '')
      into v_email, v_first
      from auth.users u left join profiles p on p.id = u.id
     where u.id = p_user;
    if v_email is null then
        update welcome_emails set status = 'failed', error = 'no e-mail address'
         where user_id = p_user;
        return jsonb_build_object('send', false, 'reason', 'no e-mail address');
    end if;
    update welcome_emails set status = 'sending', claimed_at = now()
     where user_id = p_user;
    return jsonb_build_object('send', true, 'email', v_email,
                              'first_name', left(coalesce(v_first, ''), 60),
                              'lang', v_row.lang);
end;
$$;

-- sending → sent (Resend's id) or failed (its words). Only from sending:
-- a row already sent stays sent.
create or replace function welcome_email_done(p_user uuid, p_ok boolean, p_id text, p_error text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
    update welcome_emails
       set status    = case when p_ok then 'sent' else 'failed' end,
           sent_at   = case when p_ok then now() end,
           resend_id = left(p_id, 200),
           error     = case when p_ok then null else left(coalesce(p_error, 'refused'), 500) end
     where user_id = p_user and status = 'sending';
    return found;
end;
$$;

-- ------------------------------------------------------------
-- Who may call what (063: a new function is born closed to anon and
-- PUBLIC, open to authenticated — taken back here: none is the app's)
-- ------------------------------------------------------------
revoke execute on function trg_welcome_email_request()                    from public;
revoke execute on function welcome_email_claim(uuid)                      from public;
revoke execute on function welcome_email_done(uuid, boolean, text, text)  from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function trg_welcome_email_request()                   from anon;
        revoke execute on function welcome_email_claim(uuid)                     from anon;
        revoke execute on function welcome_email_done(uuid, boolean, text, text) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function trg_welcome_email_request()                   from authenticated;
        revoke execute on function welcome_email_claim(uuid)                     from authenticated;
        revoke execute on function welcome_email_done(uuid, boolean, text, text) from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function welcome_email_claim(uuid)                     to service_role;
        grant execute on function welcome_email_done(uuid, boolean, text, text) to service_role;
    end if;
end $$;

notify pgrst, 'reload schema';
