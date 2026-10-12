-- ============================================================
-- 129_new_user_notify.sql — Mara hears of every new account; the
-- ranking's bell stays off.
--
-- The owner: « Enable notification for new user for admin », and earlier
-- « disable the ranking notification ».
--
--   1. A new account (004's on_auth_user_created writes its profile on
--      the auth.users insert) rings every platform admin
--      (profiles.is_platform_admin): one bell row each, kind `new_user`,
--      written as 111's org_application and 112's courier_application
--      are — recipient the admin, org_id null, params « to: platform »
--      (so 115's notification_scope puts it in the platform's list and
--      notification_counts counts it there). The row is the push too:
--      115's pipeline (notifications INSERT → Database Webhook → the push
--      Worker) sends every bell row, nothing to add.
--        message: « Nouveau compte : <nom, ou e-mail, ou téléphone>
--                   (<Google | Apple | e-mail | téléphone>) »
--        params:  to, user_id, name, method (google | apple | email |
--                 phone | the provider's own word), contact (the e-mail
--                 or the number — what the console's « Personnes »
--                 searches by, so a tap opens the person's fiche).
--      The e-mail and the number go to platform admins only: the bell
--      row's recipient is the admin (030's policy: a row is read by its
--      recipient alone), the push reaches the admin's devices alone.
--      No password, no token: only auth.users' id, email, phone,
--      raw_user_meta_data (the name) and raw_app_meta_data ->> 'provider'
--      (the method) are read.
--   2. The method is auth.users.raw_app_meta_data ->> 'provider' (Supabase
--      writes it on sign-up: google, apple, email, phone — WhatsApp's OTP
--      is a phone sign-in); read through to_jsonb(new), so a database
--      whose auth.users lacks the column (a local stub) still works: no
--      provider, an address gives « e-mail », a number « téléphone ».
--   3. The switch: platform setting `admin_new_user_notify` (boolean,
--      default true), Réglages › Nouveaux comptes. Off, no row is written.
--   4. The new account is never told about itself: a person whose profile
--      is a platform admin from birth (none today: is_platform_admin starts
--      false, 032 guards it) is skipped among the recipients.
--   5. No showcase or system account to skip: 094's example vitrines are
--      businesses (orgs.showcase), never accounts — nothing is created in
--      auth.users for them. The store reviewers' account (128's
--      store_review_account) is a real sign-up and is announced.
--   6. Non-blocking: the trigger function swallows every error (as 111's
--      and 124's do) — a new account is never refused or held up by its
--      announcement. It runs after 004's (triggers fire by name:
--      « on_auth_user_created » before « platform_new_user »), so the
--      profile exists and its name is read.
--   7. The ranking's bell (086's pg_cron job 'cauris-board',
--      cauris_board_notify, Sun/Mon/Wed/Fri 19:00) was paused live by
--      hand, cron.alter_job(active := false). 129 keeps it paused: where
--      the job exists, it is set inactive — on every run, so the bundle
--      (whose 086 schedules it again) leaves it paused too.
--      'cauris-week-close' (the weekly prizes) is not touched.
--      TO TURN THE RANKING'S BELL BACK ON (the SQL editor, as postgres):
--          select cron.alter_job(jobid, active := true)
--            from cron.job where jobname = 'cauris-board';
--      and remove section 7 from this file before the bundle is run
--      again — or the next run of 129 pauses it once more.
--
-- Platform-level, not per business: the same for a shop, a farm and an
-- association — an account is announced before it has any business, of
-- any kind, or none (a shopper, a courier). Nothing a business, a vitrine
-- or the street shows changes (P1).
--
-- Re-runnable (the bundle runs twice): setting on conflict do nothing,
-- functions replaced with their arguments unchanged, the trigger dropped
-- and created, the job's pause idempotent.
-- ============================================================

-- ------------------------------------------------------------
-- 3. The switch
-- ------------------------------------------------------------
insert into platform_settings (key, value) values
    ('admin_new_user_notify', 'true')
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- 2. How the account was made, in the console's words
-- ------------------------------------------------------------
-- The provider's word (google, apple, email, phone…) from raw_app_meta_data,
-- or, without one, what the account carries.
create or replace function new_user_method(p_user jsonb)
returns text
language sql
immutable
set search_path = public
as $$
    select coalesce(
        nullif(lower(btrim(p_user #>> '{raw_app_meta_data,provider}')), ''),
        case when nullif(btrim(p_user ->> 'email'), '') is not null then 'email'
             when nullif(btrim(p_user ->> 'phone'), '') is not null then 'phone' end,
        'email');
$$;

create or replace function new_user_method_label(p_method text)
returns text
language sql
immutable
set search_path = public
as $$
    select case p_method
        when 'google' then 'Google'
        when 'apple'  then 'Apple'
        when 'email'  then 'e-mail'
        when 'phone'  then 'téléphone'
        else coalesce(nullif(btrim(p_method), ''), 'e-mail')
    end;
$$;

-- ------------------------------------------------------------
-- 1, 4, 6. The announcement
-- ------------------------------------------------------------
create or replace function trg_notify_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_user    jsonb := to_jsonb(new);
    v_method  text;
    v_email   text;
    v_phone   text;
    v_name    text;
    v_contact text;
begin
    if not coalesce((select value = 'true'::jsonb from platform_settings
                      where key = 'admin_new_user_notify'), true) then
        return new;
    end if;
    v_method := new_user_method(v_user);
    v_email  := nullif(btrim(v_user ->> 'email'), '');
    v_phone  := nullif(btrim(v_user ->> 'phone'), '');
    if v_phone is not null and v_phone !~ '^\+' then
        v_phone := '+' || v_phone;  -- GoTrue keeps the number without its +
    end if;
    v_contact := coalesce(v_email, v_phone);
    v_name := left(coalesce(
        (select nullif(btrim(p.full_name), '') from profiles p where p.id = new.id),
        nullif(btrim(v_user #>> '{raw_user_meta_data,full_name}'), ''),
        nullif(btrim(v_user #>> '{raw_user_meta_data,name}'), ''),
        v_contact,
        'sans nom'), 120);

    insert into notifications (recipient_id, org_id, kind, message, params)
    select p.id, null::uuid, 'new_user',
           format('Nouveau compte : %s (%s)', v_name, new_user_method_label(v_method)),
           -- 099's rule: every bell says whom it is for, with its facts.
           jsonb_strip_nulls(jsonb_build_object('to', 'platform',
               'user_id', new.id, 'name', v_name,
               'method', v_method, 'contact', v_contact))
      from profiles p
     where p.is_platform_admin
       and p.id <> new.id;
    return new;
exception when others then
    -- An announcement is never worth a failed sign-up.
    return new;
end;
$$;

drop trigger if exists platform_new_user on auth.users;
create trigger platform_new_user
after insert on auth.users
for each row execute function trg_notify_new_user();

-- ------------------------------------------------------------
-- 7. The ranking's bell stays paused (to turn it back on: the header)
-- ------------------------------------------------------------
-- Where pg_cron is installed and the job exists: inactive. Elsewhere (CI,
-- a local Postgres) it says so and does nothing. Answers what it did.
create or replace function cauris_board_keep_paused()
returns text
language plpgsql
set search_path = public
as $$
declare
    v_job bigint;
begin
    if to_regclass('cron.job') is null then
        return 'no pg_cron';
    end if;
    execute $q$select jobid from cron.job where jobname = 'cauris-board' limit 1$q$
       into v_job;
    if v_job is null then
        return 'no job';
    end if;
    execute 'select cron.alter_job(job_id := $1, active := false)' using v_job;
    return 'paused';
exception when others then
    return 'not paused: ' || sqlerrm;
end;
$$;

do $$
declare
    v_said text;
begin
    v_said := cauris_board_keep_paused();
    raise notice 'cauris-board: %', v_said;
end $$;

-- ------------------------------------------------------------
-- Who may call what (063: a new function is born closed to anon and
-- PUBLIC, open to authenticated — taken back here: none is the app's)
-- ------------------------------------------------------------
revoke execute on function new_user_method(jsonb)        from public;
revoke execute on function new_user_method_label(text)   from public;
revoke execute on function trg_notify_new_user()         from public;
revoke execute on function cauris_board_keep_paused()    from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function new_user_method(jsonb)      from anon;
        revoke execute on function new_user_method_label(text) from anon;
        revoke execute on function trg_notify_new_user()       from anon;
        revoke execute on function cauris_board_keep_paused()  from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function new_user_method(jsonb)      from authenticated;
        revoke execute on function new_user_method_label(text) from authenticated;
        revoke execute on function trg_notify_new_user()       from authenticated;
        revoke execute on function cauris_board_keep_paused()  from authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
