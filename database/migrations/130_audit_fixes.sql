-- ============================================================
-- 130_audit_fixes.sql — the second security audit's database fixes
-- (SEC_AUDIT_2, before iPhone build 5 and the Android production
-- promotion).
--
--   M1. The migrations' ledger is nobody's but the owner's. kaj_migrations
--       (scripts/apply-migrations.sh makes it; migrate.yml trusts it to know
--       what is applied) had, on a database where the table was born before
--       the script enabled RLS, no row security and Supabase's default
--       INSERT, UPDATE and DELETE for `authenticated`: any signed-in account
--       could pre-insert « 131_….sql » (migrate.yml then skips a future
--       security migration) or delete a row (an old migration runs again).
--       Here, wherever the table exists: row security on (no policy: the
--       app's roles read and write nothing) and every privilege taken back
--       from PUBLIC, anon and authenticated. The script does the same for a
--       database it creates the ledger in. The live database was already
--       fixed by hand (owner, October): this makes the repository say so.
--   M2. The new account's bell (129) carries only plain words. The name a
--       sign-up gives (profiles.full_name, raw_user_meta_data) is chosen by
--       whoever signs up with the public key, unconfirmed — and 129 put it,
--       as given, in every platform admin's bell and push. notify_plain():
--       control characters, line breaks and invisible / direction marks
--       become spaces; « < » and « > » go; « :// » and « www. » are cut,
--       and a dot between two letters or digits becomes a space
--       (« mara-login.example » → « mara-login example »), so no phone or
--       browser makes a link of it; spaces collapsed; at most 60
--       characters. The contact (the account's e-mail or number — what the
--       console's « Personnes » searches by) is cleaned of the same marks
--       and cut to 60, its dots kept (it must still find the person; an
--       address is not a web link); it is shown only when the account gave
--       no name. The bells 129 already wrote are rewritten the same way.
--       The push Worker shows the row's message as plain text (Web Push
--       body, FCM notification body), the app as a plain Text: no HTML
--       anywhere.
--   M4. A sandbox purchase (TestFlight, Play test tracks) turns Pro on
--       only for a business owned by the App Review account when that
--       account's address is CONFIRMED (auth.users.email_confirmed_at): an
--       unconfirmed sign-up with the address — or a squatted one — no
--       longer counts. And, when the platform setting store_review_orgs
--       names businesses (their ids, separated by commas or spaces), only
--       those: the review account's other businesses do not. Empty (the
--       default), any business that account owns. Platform admins' own
--       businesses as before.
--   M6. The WhatsApp code (109's Send SMS hook, workers/whatsapp-otp) is
--       rationed: otp_send_allow(phone, user), called by the Worker with
--       the service role before each message. At most 3 codes per number
--       per 10 minutes and 10 per day; 5 per account per 10 minutes and
--       20 per day. Over: refused, nothing sent, nothing said of which
--       limit. The number is kept only as a hash (md5 of its digits), for
--       two days, then forgotten; the account's rows go with the account.
--
-- Platform-level: the same for a shop, a farm and an association — the
-- ledger, the admins' bell, the store's sandbox rule and the WhatsApp code
-- are nobody's business in particular. Nothing a business, a vitrine or
-- the street shows changes (P1).
--
-- Re-runnable (the bundle runs twice): settings on conflict do nothing,
-- functions replaced with their arguments unchanged, the table if not
-- exists, the rewrite of old bells idempotent (a clean text stays clean).
-- ============================================================

-- ------------------------------------------------------------
-- M1. The ledger
-- ------------------------------------------------------------
do $$
begin
    if to_regclass('public.kaj_migrations') is null then
        return;   -- CI, a fresh database: the script makes it, locked.
    end if;
    alter table kaj_migrations enable row level security;
    revoke all on kaj_migrations from public;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on kaj_migrations from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on kaj_migrations from authenticated;
    end if;
end $$;

-- ------------------------------------------------------------
-- M2. Plain words for a bell
-- ------------------------------------------------------------
-- What a stranger typed, made safe to show anybody: no control or
-- invisible character, no line, no tag, no link; p_max characters at most.
-- p_keep_dots: a contact (e-mail) keeps its dots, so it still finds the
-- person — its scheme and « www. » are cut all the same.
create or replace function notify_plain(p_text text, p_max integer default 60,
                                        p_keep_dots boolean default false)
returns text
language sql
immutable
set search_path = public
as $$
    select nullif(left(btrim(regexp_replace(
        case when p_keep_dots then s
             else regexp_replace(s, '(?<=[[:alnum:]])\.(?=[[:alnum:]])', ' ', 'g') end,
        '\s+', ' ', 'g')), greatest(coalesce(p_max, 60), 1)), '')
      from (select regexp_replace(regexp_replace(regexp_replace(regexp_replace(
                coalesce(p_text, ''),
                -- C0/C1 controls, line and paragraph separators, zero-width
                -- and direction marks, the byte-order mark
                '[[:cntrl:]\u0085   ​-‏‪-‮⁠-⁤⁦-⁩﻿]',
                ' ', 'g'),
                '[<>]', '', 'g'),
                '://', ' ', 'g'),
                '(^|[^[:alnum:]])www\.', '\1', 'gi') as s) t;
$$;

-- 129's announcement, with its name and contact made plain. Otherwise as
-- 129 wrote it (its header): the switch, the method, every platform admin
-- but the account itself, never a failed sign-up.
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
    v_contact := notify_plain(coalesce(v_email, v_phone), 60, true);
    v_name := coalesce(
        notify_plain((select p.full_name from profiles p where p.id = new.id)),
        notify_plain(v_user #>> '{raw_user_meta_data,full_name}'),
        notify_plain(v_user #>> '{raw_user_meta_data,name}'),
        v_contact,
        'sans nom');

    insert into notifications (recipient_id, org_id, kind, message, params)
    select p.id, null::uuid, 'new_user',
           format('Nouveau compte : %s (%s)', v_name,
                  notify_plain(new_user_method_label(v_method), 20)),
           -- 099's rule: every bell says whom it is for, with its facts.
           jsonb_strip_nulls(jsonb_build_object('to', 'platform',
               'user_id', new.id, 'name', v_name,
               'method', notify_plain(v_method, 20, true), 'contact', v_contact))
      from profiles p
     where p.is_platform_admin
       and p.id <> new.id;
    return new;
exception when others then
    -- An announcement is never worth a failed sign-up.
    return new;
end;
$$;

-- The bells 129 already wrote, made plain the same way (a name that was
-- the contact stays the contact, its dots kept).
update notifications n
   set params = jsonb_strip_nulls(n.params || jsonb_build_object(
           'name', c.name, 'contact', c.contact, 'method', c.method)),
       message = format('Nouveau compte : %s (%s)', c.name,
           notify_plain(new_user_method_label(coalesce(c.method, 'email')), 20))
  from (select x.id,
               coalesce(case when x.params ->> 'name' = x.params ->> 'contact'
                             then notify_plain(x.params ->> 'name', 60, true)
                             else notify_plain(x.params ->> 'name') end, 'sans nom') as name,
               notify_plain(x.params ->> 'contact', 60, true) as contact,
               notify_plain(x.params ->> 'method', 20, true) as method
          from notifications x
         where x.kind = 'new_user') c
 where n.id = c.id
   and (n.params ->> 'name' is distinct from c.name
        or n.params ->> 'contact' is distinct from c.contact
        or n.params ->> 'method' is distinct from c.method);

-- ------------------------------------------------------------
-- M4. Whose sandbox purchases count
-- ------------------------------------------------------------
-- Empty: any business the review account owns. Ids: only those.
insert into platform_settings (key, value) values ('store_review_orgs', '""')
on conflict (key) do nothing;

create or replace function store_sandbox_allowed(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    with s as (
        select lower(btrim(coalesce(
                   (select value #>> '{}' from platform_settings
                     where key = 'store_review_account'), 'review.mara@gmail.com'))) as account,
               array_remove(regexp_split_to_array(lower(btrim(coalesce(
                   (select value #>> '{}' from platform_settings
                     where key = 'store_review_orgs'), ''))), '[\s,;]+'), '') as orgs
    )
    select exists (
        select 1 from memberships m
          join profiles p on p.id = m.user_id
          left join auth.users u on u.id = m.user_id
          cross join s
         where m.org_id = p_org_id and m.role = 'owner'
           and (p.is_platform_admin
                or (s.account <> ''
                    and lower(btrim(coalesce(u.email, ''))) = s.account
                    -- the address proved, never a sign-up that only typed it
                    and u.email_confirmed_at is not null
                    and (cardinality(s.orgs) = 0 or p_org_id::text = any (s.orgs)))));
$$;

-- ------------------------------------------------------------
-- M6. The WhatsApp code, rationed
-- ------------------------------------------------------------
create table if not exists otp_sends (
    id        bigint generated always as identity primary key,
    -- md5 of the number's digits: which number, never the number.
    phone_key text not null,
    user_id   uuid references auth.users(id) on delete cascade,
    sent_at   timestamptz not null default now()
);
create index if not exists otp_sends_phone on otp_sends (phone_key, sent_at);
create index if not exists otp_sends_user  on otp_sends (user_id, sent_at);
create index if not exists otp_sends_age   on otp_sends (sent_at);

alter table otp_sends enable row level security;
revoke all on otp_sends from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on otp_sends from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on otp_sends from authenticated;
    end if;
    -- The Worker asks otp_send_allow(); it reads and writes no row itself.
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        revoke all on otp_sends from service_role;
    end if;
end $$;

-- May a code go to this number for this account now? Yes: counted, and
-- { ok: true }. No: { ok: false, reason } — the reason is for the Worker's
-- log, never for the person (the Worker says only « too many codes »).
create or replace function otp_send_allow(p_phone text, p_user uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
    v_key    text;
    v_user   uuid;
begin
    if length(v_digits) < 8 or length(v_digits) > 15 then
        return jsonb_build_object('ok', false, 'reason', 'phone');
    end if;
    v_key := md5('otp:' || v_digits);
    v_user := (select u.id from auth.users u where u.id = p_user);
    -- One decision at a time per number and per account: two codes asked
    -- at the same moment cannot both pass the last free place.
    perform pg_advisory_xact_lock(hashtext('otp-phone:' || v_key));
    if v_user is not null then
        perform pg_advisory_xact_lock(hashtext('otp-user:' || v_user::text));
    end if;
    delete from otp_sends where sent_at < now() - interval '2 days';

    if (select count(*) from otp_sends
         where phone_key = v_key and sent_at > now() - interval '10 minutes') >= 3 then
        return jsonb_build_object('ok', false, 'reason', 'phone_10_minutes');
    end if;
    if (select count(*) from otp_sends
         where phone_key = v_key and sent_at > now() - interval '1 day') >= 10 then
        return jsonb_build_object('ok', false, 'reason', 'phone_day');
    end if;
    if v_user is not null then
        if (select count(*) from otp_sends
             where user_id = v_user and sent_at > now() - interval '10 minutes') >= 5 then
            return jsonb_build_object('ok', false, 'reason', 'account_10_minutes');
        end if;
        if (select count(*) from otp_sends
             where user_id = v_user and sent_at > now() - interval '1 day') >= 20 then
            return jsonb_build_object('ok', false, 'reason', 'account_day');
        end if;
    end if;

    insert into otp_sends (phone_key, user_id) values (v_key, v_user);
    return jsonb_build_object('ok', true);
end;
$$;

-- ------------------------------------------------------------
-- Who may call what (063: born closed to anon and PUBLIC; taken back from
-- authenticated here — none of it is the app's)
-- ------------------------------------------------------------
revoke execute on function notify_plain(text, integer, boolean) from public;
revoke execute on function otp_send_allow(text, uuid)           from public;
revoke execute on function store_sandbox_allowed(uuid)          from public;
revoke execute on function trg_notify_new_user()                from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function notify_plain(text, integer, boolean) from anon;
        revoke execute on function otp_send_allow(text, uuid)           from anon;
        revoke execute on function store_sandbox_allowed(uuid)          from anon;
        revoke execute on function trg_notify_new_user()                from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function notify_plain(text, integer, boolean) from authenticated;
        revoke execute on function otp_send_allow(text, uuid)           from authenticated;
        revoke execute on function store_sandbox_allowed(uuid)          from authenticated;
        revoke execute on function trg_notify_new_user()                from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        -- The WhatsApp Worker's, alone.
        grant execute on function otp_send_allow(text, uuid) to service_role;
    end if;
end $$;

notify pgrst, 'reload schema';
