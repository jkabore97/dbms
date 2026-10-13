-- ============================================================
-- 133_help_requests.sql — batch 136: « Besoin d'aide », Mara's training
-- team behind a Pro business.
--
-- The owner: « a strong system for the training team set up earlier. I
-- need that to come with Pro. They will be notified through WhatsApp and
-- the app. I need an easy "Please help" button for Pro members and a very
-- basic one for regular users. »
--
-- WHAT IT IS BUILT ON. Trainers are 038's: an account marked
-- profiles.is_trainer, assigned to businesses by an observer membership
-- with full visibility and memberships.is_trainer (read everything, write
-- nothing). Mara Pro is 065's org_plan(). The bell is 030/115's
-- notifications row (the push Worker carries every row); 129's « Nouveau
-- compte » is how the platform admins hear of things; notify_plain (130)
-- makes typed words safe for a bell or a message.
--
-- 1. help_requests — one per « Besoin d'aide ». A Pro business's member
--    (any role but observer, never a trainer's assignment) asks:
--      subject  ventes stock factures vitrine commandes equipe autre
--               (a shop), bandes … (a farm), contributions rapports
--               membres … (an association) — one list, checked here; the
--               app shows each kind its own seven chips;
--      message  optional, 500 characters at most, kept as typed — every
--               bell and WhatsApp says it through notify_plain (60);
--      photo    optional: a document of the same business (the app's
--               existing picker and capture, kind « help »);
--      contact  call | whatsapp | visit (« Venir me voir »), and the
--               number to reach the person on (8 to 15 digits; the
--               profile's by default);
--      context  the screen, the app's version and platform — 60, 40, 20
--               characters, plain.
--    Status: open → taken (« Je m'en occupe ») → resolved (with a note)
--    → closed by the business (👍 / 👎 as rating 1 / -1, or none). « Pas
--    encore » takes a resolved request back to taken. Closing an open one
--    is allowed (nobody needed after all).
--
-- 2. LIMITS, all enforced here, never only by the app:
--      * Pro only: org_plan(org) = 'pro', else « Mara Pro ». A free
--        business has no trainer queue at all (the app shows it the
--        guides and support_contacts(), 126);
--      * one active request (open or taken) per business — a partial
--        unique index, so two taps at once cannot make two;
--      * help_daily_limit (default 5) requests per business in 24 hours;
--      * the words: subject and contact from their lists, the message
--        and context cut and stripped as above.
--
-- 3. ROUTING AND ESCALATION. Pro help hours: help_hours_open (7) to
--    help_hours_close (21), every day, on Ouagadougou's clock (UTC, no
--    summer time), platform settings changed in Réglages (105's
--    platform_set_setting, journaled; a trigger keeps 0 ≤ open < close
--    ≤ 24). A request made in the hours is routed at once; outside them it
--    is accepted and queued: routed_at is the next opening, and the app
--    says « Un formateur vous répondra demain à partir de 7 h ».
--      * routed_at: the business's assigned trainers (memberships.
--        is_trainer) who are on duty (help_trainer_status, default on)
--        are rung — the bell, its push, and WhatsApp when it is on;
--      * escalate_at = routed_at + help_escalate_minutes (15) of OPEN
--        time (a request routed at 20:55 escalates at 7:10 the next
--        morning, never at night). If nobody took it by then — or the
--        business has no on-duty assigned trainer at all, in which case
--        escalate_at = routed_at — escalated_at is set: every on-duty
--        trainer is rung (and sees it in their inbox), and every platform
--        admin gets a bell under admin_help_notify (default true, as 129's
--        admin_new_user_notify);
--      * « late » for « Aujourd'hui »: open (not taken) for more than
--        help_late_minutes (30) of open time since routed_at.
--    help_tick() does the routing at opening, the escalation and the
--    access-expiry journal line; pg_cron runs it every minute
--    ('help-tick'), the WhatsApp Worker's cron calls it too, and the
--    inbox and console run it before they answer — so nothing waits on
--    one clock alone.
--
-- 4. WHO SEES A REQUEST (RLS, select only — no direct write anywhere):
--      * the person who asked; the business's admins (is_org_admin, which
--        includes the platform admins);
--      * a trainer: the requests of the businesses they are assigned to,
--        every OPEN request once escalated, and the ones they took;
--      * nobody else; nothing for anon (every rule needs auth.uid(),
--        and the tables are not granted to anon at all).
--    The policies call only is_org_admin, already one of 063's six policy
--    helpers, and read profiles / memberships under their own RLS (a
--    person reads their own rows) — no new helper joins the six.
--    help_request_events (the request's journal) is readable exactly when
--    its request is.
--
-- 5. THE FIRST WINS. help_take() is one UPDATE … WHERE status = 'open':
--    of two trainers tapping at once, one row is updated, the other is
--    told « Un autre formateur s'en occupe déjà ». A platform admin may
--    take one too (the escalation reaches them).
--
-- 6. TEMPORARY ACCESS (help_access_grants). When the trainer who took the
--    request is not a member of the business, its owner or admin may tap
--    « Autoriser l'accès 48 h »: a grant (request, business, trainer,
--    granted_at, expires_at ≤ granted_at + 48 h, revoked_at). It is
--    READ-ONLY by construction, enforced by the database:
--      * it is read by exactly four functions: is_org_member,
--        has_full_visibility and my_org_ids (the read side of every
--        policy) and my_orgs (so the app lists the business, as an
--        observer); each checks expires_at > now(), revoked_at is null
--        and that the grantee is still a trainer itself, on every call —
--        the grant ends at its second, with no job to wait for. They ask
--        it inline, of a trainer only, so nobody else's checks cost more
--        (measured: see section 3); An association's members list, the one read
--        policy that asked memberships itself, gains is_org_member;
--      * it is not a membership: can_write_org, is_org_admin and every
--        write policy and function (which read memberships) never see it
--        — no write policy in the schema uses a read helper (checked live
--        before 133), so nothing can be written through it;
--      * the owner ends it at any time (help_access_revoke), closing the
--        request ends it, 48 h ends it, and so does the grantee ceasing to
--        be a trainer (trg_help_trainer_demoted).
--    Journaled three ways: the request's journal (granted, opened,
--    revoked, expired), 008's audit_log (audit_row on the grants table:
--    the business's own Activité shows each grant, each opening — counted
--    on the row — and each end), and a bell to the trainer.
--
-- 7. WHATSAPP. help_whatsapp_template (default 'aide_demande') names the
--    Meta template. Each trainer rung who has a phone gets an outbox row
--    (help_whatsapp_outbox) with the template and its four values (the
--    business's name, its kind, the subject, the request's id for the
--    link) — unless the setting is empty: then no row, the bell alone,
--    and the console says WhatsApp is off. The whatsapp-otp Worker
--    (workers/whatsapp-otp, its existing WHATSAPP_TOKEN, WHATSAPP_PHONE_ID
--    and 130's SUPABASE_SERVICE_ROLE_KEY) claims the rows every minute
--    (help_whatsapp_claim, service role only) and says how each went
--    (help_whatsapp_done). A template not approved yet fails at Meta;
--    the row says « template », the console says so. Never part of the
--    request: a request is made, routed and rung whatever WhatsApp does.
--    Rows older than an hour are not sent (a stale alert helps nobody).
--
-- 8. SECURITY DEFINER, each one: the doors write rows the caller may not
--    write directly (other people's bells, the outbox, a request's status
--    for a trainer who is not of the business) or read what RLS keeps
--    from them (the trainer's first name and number for the owner, the
--    business's name for a trainer who is not its member). Every one
--    checks auth.uid() and the caller's place first, pins its search path,
--    is closed to PUBLIC and anon (063), and is open to authenticated only
--    when the app calls it. help_tick and the two WhatsApp functions are
--    the service role's (and the cron's, which runs as postgres).
--
-- PER KIND. Shop, farm and association alike: the same tables, routing,
-- access and limits. The subjects differ (the app's chips): a shop Ventes
-- Stock Factures Vitrine Commandes Équipe Autre; a farm Bandes Stock
-- Ventes Factures Vitrine Équipe Autre; an association Contributions
-- Rapports Membres Factures Vitrine Équipe Autre. The WhatsApp kind word
-- is Boutique, Ferme or Association. Nothing a business, a vitrine or the
-- street shows changes for anybody without a grant (P1).
--
-- Re-runnable (the bundle runs twice): create table if not exists, settings
-- on conflict do nothing, create or replace, drop policy / trigger if
-- exists, the cron job scheduled once.
-- ============================================================

-- ------------------------------------------------------------
-- 0. The settings
-- ------------------------------------------------------------
insert into platform_settings (key, value) values
    ('help_hours_open',        '7'),
    ('help_hours_close',       '21'),
    ('help_escalate_minutes',  '15'),
    ('help_late_minutes',      '30'),
    ('help_daily_limit',       '5'),
    ('help_whatsapp_template', '"aide_demande"'),
    ('admin_help_notify',      'true')
on conflict (key) do nothing;

-- The numbers in their ranges, the template a name Meta accepts (or
-- nothing: WhatsApp off). Hours are whole: open 0–23, close 1–24, open
-- before close — checked against the other one as it stands.
create or replace function trg_help_settings()
returns trigger
language plpgsql
set search_path = public
as $$
declare
    v_n     numeric;
    v_other numeric;
begin
    if new.key = 'help_whatsapp_template' then
        if jsonb_typeof(new.value) <> 'string'
           or (new.value #>> '{}') !~ '^([a-z0-9_]{1,250})?$' then
            raise exception 'Le modèle WhatsApp : son nom chez Meta, en minuscules, chiffres et _ (par exemple aide_demande), ou rien pour ne pas envoyer de WhatsApp.';
        end if;
        return new;
    end if;
    if jsonb_typeof(new.value) <> 'number' then
        raise exception 'Ce réglage attend un nombre.';
    end if;
    v_n := (new.value #>> '{}')::numeric;
    if v_n <> trunc(v_n) then
        raise exception 'Un nombre entier, s''il vous plaît.';
    end if;
    if new.key = 'help_hours_open' then
        select (value #>> '{}')::numeric into v_other from platform_settings where key = 'help_hours_close';
        if v_n < 0 or v_n > 23 or v_n >= coalesce(v_other, 24) then
            raise exception 'L''heure d''ouverture de l''aide Pro : de 0 à 23, avant l''heure de fermeture.';
        end if;
    elsif new.key = 'help_hours_close' then
        select (value #>> '{}')::numeric into v_other from platform_settings where key = 'help_hours_open';
        if v_n < 1 or v_n > 24 or v_n <= coalesce(v_other, 0) then
            raise exception 'L''heure de fermeture de l''aide Pro : de 1 à 24, après l''heure d''ouverture.';
        end if;
    elsif new.key in ('help_escalate_minutes', 'help_late_minutes') then
        if v_n < 1 or v_n > 1440 then
            raise exception 'Un nombre de minutes de 1 à 1440, s''il vous plaît.';
        end if;
    elsif new.key = 'help_daily_limit' then
        if v_n < 1 or v_n > 50 then
            raise exception 'Un nombre de demandes de 1 à 50 par jour, s''il vous plaît.';
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists help_settings_check on platform_settings;
create trigger help_settings_check
before insert or update on platform_settings
for each row when (new.key in ('help_hours_open', 'help_hours_close', 'help_escalate_minutes',
                               'help_late_minutes', 'help_daily_limit', 'help_whatsapp_template'))
execute function trg_help_settings();

-- A number setting of the help, or its default. Definer: platform_settings
-- is the platform's; this reads the six help keys and nothing else.
create or replace function help_setting(p_key text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        (select value from platform_settings
          where key = p_key
            and p_key in ('help_hours_open', 'help_hours_close', 'help_escalate_minutes',
                          'help_late_minutes', 'help_daily_limit', 'help_whatsapp_template',
                          'admin_help_notify')),
        case p_key
            when 'help_hours_open'        then '7'::jsonb
            when 'help_hours_close'       then '21'::jsonb
            when 'help_escalate_minutes'  then '15'::jsonb
            when 'help_late_minutes'      then '30'::jsonb
            when 'help_daily_limit'       then '5'::jsonb
            when 'help_whatsapp_template' then '""'::jsonb
            when 'admin_help_notify'      then 'true'::jsonb
        end);
$$;

create or replace function help_setting_int(p_key text)
returns int
language sql
stable
set search_path = public
as $$
    select (help_setting(p_key) #>> '{}')::numeric::int;
$$;

-- ------------------------------------------------------------
-- 1. The hours, on Ouagadougou's clock
-- ------------------------------------------------------------
-- Whether an instant is inside the help hours.
create or replace function help_in_hours(p_at timestamptz default now())
returns boolean
language sql
stable
set search_path = public
as $$
    select extract(hour from p_at at time zone 'Africa/Ouagadougou')
             + extract(minute from p_at at time zone 'Africa/Ouagadougou') / 60.0
             + extract(second from p_at at time zone 'Africa/Ouagadougou') / 3600.0
           >= help_setting_int('help_hours_open')
       and extract(hour from p_at at time zone 'Africa/Ouagadougou')
             + extract(minute from p_at at time zone 'Africa/Ouagadougou') / 60.0
             + extract(second from p_at at time zone 'Africa/Ouagadougou') / 3600.0
           < help_setting_int('help_hours_close');
$$;

-- The instant itself if it is in the hours, else the next opening.
create or replace function help_next_open(p_at timestamptz default now())
returns timestamptz
language plpgsql
stable
set search_path = public
as $$
declare
    v_local timestamp := p_at at time zone 'Africa/Ouagadougou';
    v_day   date := v_local::date;
    v_open  int := help_setting_int('help_hours_open');
    v_close int := help_setting_int('help_hours_close');
begin
    if v_local < v_day + make_interval(hours => v_open) then
        return (v_day + make_interval(hours => v_open)) at time zone 'Africa/Ouagadougou';
    elsif v_local < v_day + make_interval(hours => v_close) then
        return p_at;
    end if;
    return (v_day + 1 + make_interval(hours => v_open)) at time zone 'Africa/Ouagadougou';
end;
$$;

-- [p_minutes] of open time after [p_at]: 20:55 + 15 min with 7–21 hours
-- is 7:10 the next morning.
create or replace function help_add_open(p_at timestamptz, p_minutes int)
returns timestamptz
language plpgsql
stable
set search_path = public
as $$
declare
    v_t     timestamptz := help_next_open(p_at);
    v_left  interval := make_interval(mins => greatest(coalesce(p_minutes, 0), 0));
    v_close int := help_setting_int('help_hours_close');
    v_end   timestamptz;
begin
    for i in 1..30 loop
        v_end := ((v_t at time zone 'Africa/Ouagadougou')::date + make_interval(hours => v_close))
                 at time zone 'Africa/Ouagadougou';
        if v_t + v_left <= v_end then
            return v_t + v_left;
        end if;
        v_left := v_left - (v_end - v_t);
        v_t := help_next_open(v_end);
    end loop;
    return v_t + v_left;
end;
$$;

-- The open minutes between two instants (a month at most is counted).
create or replace function help_open_minutes(p_from timestamptz, p_to timestamptz default now())
returns int
language plpgsql
stable
set search_path = public
as $$
declare
    v_open  int := help_setting_int('help_hours_open');
    v_close int := help_setting_int('help_hours_close');
    v_day   date;
    v_last  date;
    v_a     timestamptz;
    v_b     timestamptz;
    v_sum   interval := interval '0';
begin
    if p_from is null or p_to is null or p_to <= p_from then
        return 0;
    end if;
    v_day  := greatest((p_from at time zone 'Africa/Ouagadougou')::date,
                       (p_to at time zone 'Africa/Ouagadougou')::date - 31);
    v_last := (p_to at time zone 'Africa/Ouagadougou')::date;
    while v_day <= v_last loop
        v_a := greatest(p_from, (v_day + make_interval(hours => v_open)) at time zone 'Africa/Ouagadougou');
        v_b := least(p_to, (v_day + make_interval(hours => v_close)) at time zone 'Africa/Ouagadougou');
        if v_b > v_a then
            v_sum := v_sum + (v_b - v_a);
        end if;
        v_day := v_day + 1;
    end loop;
    return floor(extract(epoch from v_sum) / 60)::int;
end;
$$;

-- ------------------------------------------------------------
-- 2. The tables
-- ------------------------------------------------------------
create table if not exists help_requests (
    id              uuid primary key default gen_random_uuid(),
    org_id          uuid not null references orgs(id) on delete cascade,
    requested_by    uuid references profiles(id) on delete set null,
    subject         text not null check (subject in (
                        'ventes', 'stock', 'factures', 'vitrine', 'commandes', 'equipe', 'autre',
                        'bandes', 'contributions', 'rapports', 'membres')),
    message         text check (message is null or char_length(message) <= 500),
    photo_document_id uuid,
    contact         text not null check (contact in ('call', 'whatsapp', 'visit')),
    contact_phone   text check (contact_phone is null or contact_phone ~ '^[0-9]{8,15}$'),
    context         jsonb not null default '{}'::jsonb,
    status          text not null default 'open'
                        check (status in ('open', 'taken', 'resolved', 'closed')),
    created_at      timestamptz not null default now(),
    routed_at       timestamptz not null default now(),
    routed_rung_at  timestamptz,
    escalate_at     timestamptz not null default now(),
    escalated_at    timestamptz,
    taken_by        uuid references profiles(id) on delete set null,
    taken_at        timestamptz,
    visit_answer    text check (visit_answer in ('accepted', 'call_instead')),
    visit_note      text check (visit_note is null or char_length(visit_note) <= 200),
    resolved_at     timestamptz,
    resolution_note text check (resolution_note is null or char_length(resolution_note) <= 500),
    closed_at       timestamptz,
    closed_by       uuid references profiles(id) on delete set null,
    rating          smallint check (rating in (-1, 1))
);

-- One active request per business: two taps at once make one.
create unique index if not exists help_requests_one_active
    on help_requests (org_id) where status in ('open', 'taken');
create index if not exists help_requests_org_created on help_requests (org_id, created_at desc);
create index if not exists help_requests_open on help_requests (status, escalate_at)
    where status = 'open';
create index if not exists help_requests_taken_by on help_requests (taken_by)
    where taken_by is not null;

-- The request's journal: what happened, by whom, when.
create table if not exists help_request_events (
    id          bigint generated always as identity primary key,
    request_id  uuid not null references help_requests(id) on delete cascade,
    at          timestamptz not null default now(),
    actor_id    uuid references profiles(id) on delete set null,
    event       text not null check (event in (
                    'created', 'queued', 'routed', 'escalated', 'taken', 'visit_accepted',
                    'call_instead', 'resolved', 'reopened', 'closed', 'access_granted',
                    'access_opened', 'access_revoked', 'access_expired')),
    note        text check (note is null or char_length(note) <= 500)
);
create index if not exists help_request_events_request on help_request_events (request_id, at);

-- The temporary, read-only access (6).
create table if not exists help_access_grants (
    id              uuid primary key default gen_random_uuid(),
    request_id      uuid not null references help_requests(id) on delete cascade,
    org_id          uuid not null references orgs(id) on delete cascade,
    trainer_id      uuid not null references profiles(id) on delete cascade,
    granted_by      uuid references profiles(id) on delete set null,
    granted_at      timestamptz not null default now(),
    expires_at      timestamptz not null,
    revoked_at      timestamptz,
    revoked_by      uuid references profiles(id) on delete set null,
    expiry_logged_at timestamptz,
    opened_count    int not null default 0,
    last_opened_at  timestamptz,
    -- What 008's audit log names the row by.
    label           text,
    constraint help_access_48h check (expires_at > granted_at
                                      and expires_at <= granted_at + interval '48 hours')
);
create unique index if not exists help_access_one_per_request
    on help_access_grants (request_id) where revoked_at is null;
create index if not exists help_access_live
    on help_access_grants (trainer_id, org_id) where revoked_at is null;

-- WhatsApp's outbox (7): written here, carried by the Worker.
create table if not exists help_whatsapp_outbox (
    id          uuid primary key default gen_random_uuid(),
    request_id  uuid not null references help_requests(id) on delete cascade,
    trainer_id  uuid references profiles(id) on delete set null,
    phone       text not null check (phone ~ '^[0-9]{8,15}$'),
    template    text not null,
    params      jsonb not null,
    state       text not null default 'pending'
                    check (state in ('pending', 'sending', 'sent', 'failed', 'stale')),
    error       text,
    created_at  timestamptz not null default now(),
    claimed_at  timestamptz,
    done_at     timestamptz
);
create index if not exists help_whatsapp_pending on help_whatsapp_outbox (state, created_at);

-- A trainer's « en service » (the inbox's switch): off-duty trainers are
-- not rung for new requests (they still see them in their inbox).
create table if not exists help_trainer_status (
    user_id     uuid primary key references profiles(id) on delete cascade,
    on_duty     boolean not null default true,
    updated_at  timestamptz not null default now()
);

alter table help_requests         enable row level security;
alter table help_request_events   enable row level security;
alter table help_access_grants    enable row level security;
alter table help_whatsapp_outbox  enable row level security;
alter table help_trainer_status   enable row level security;

-- Who reads what (4). Writes: none — every change goes through a door.
drop policy if exists "help requests read by their people" on help_requests;
create policy "help requests read by their people" on help_requests
for select
using (
    requested_by = auth.uid()
    or taken_by = auth.uid()
    or is_org_admin(org_id)
    or (exists (select 1 from profiles p where p.id = auth.uid() and p.is_trainer)
        and ((escalated_at is not null and status = 'open')
             or exists (select 1 from memberships m
                         where m.user_id = auth.uid()
                           and m.org_id = help_requests.org_id
                           and m.is_trainer)))
);

drop policy if exists "help events read with their request" on help_request_events;
create policy "help events read with their request" on help_request_events
for select
using (exists (select 1 from help_requests r where r.id = help_request_events.request_id));

drop policy if exists "help access read by its two sides" on help_access_grants;
create policy "help access read by its two sides" on help_access_grants
for select
using (trainer_id = auth.uid() or is_org_admin(org_id));

drop policy if exists "help duty read by its trainer" on help_trainer_status;
create policy "help duty read by its trainer" on help_trainer_status
for select
using (user_id = auth.uid());
-- help_whatsapp_outbox: no policy at all — the doors and the service role.

-- An association's members list is the one read policy that asks
-- memberships itself rather than a read helper (004's « members readable
-- within org »): a trainer helping an association reads it too while the
-- grant lives, as an assigned trainer does. Through is_org_member — one
-- of 063's six policy helpers already, and now carrying the grant — so no
-- new function joins them (and a signed-out reader is answered nothing,
-- never refused by a table it may not read). is_org_member also lets a
-- platform admin read the list, as they read every other table of a
-- business through it. Read only: the members' write policy (« writable
-- by non-observers ») still asks memberships alone.
drop policy if exists "members readable with help access" on church_members;
create policy "members readable with help access" on church_members
for select
using (is_org_member(org_id));

revoke all on help_requests, help_request_events, help_access_grants,
              help_whatsapp_outbox, help_trainer_status from public;
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on help_requests, help_request_events, help_access_grants,
                      help_whatsapp_outbox, help_trainer_status from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on help_requests, help_request_events, help_access_grants,
                      help_whatsapp_outbox, help_trainer_status from authenticated;
        grant select on help_request_events, help_access_grants,
                        help_trainer_status to authenticated;
        -- Every column of a request but the number to call (review of
        -- 136): the policy lets every trainer read an escalated request,
        -- and the number is only for the one who takes it — the doors
        -- (help_inbox_row, help_request_json) say it to whom it is for.
        -- The app reads the table through the doors only.
        grant select (id, org_id, requested_by, subject, message, photo_document_id, contact,
                      context, status, created_at, routed_at, routed_rung_at, escalate_at,
                      escalated_at, taken_by, taken_at, visit_answer, visit_note, resolved_at,
                      resolution_note, closed_at, closed_by, rating)
            on help_requests to authenticated;
    end if;
end $$;

-- 127's guard: a grant's business is its request's business, always.
drop trigger if exists same_org on help_access_grants;
create trigger same_org before insert or update on help_access_grants
for each row execute function trg_same_org('request_id:help_requests');

-- 008's journal on the grants: each grant, each opening, each end is in
-- the business's own Activité.
drop trigger if exists audit_help_access_grants on help_access_grants;
create trigger audit_help_access_grants
after insert or update or delete on help_access_grants
for each row execute function audit_row();

-- ------------------------------------------------------------
-- 3. The temporary access in the read helpers (6)
-- ------------------------------------------------------------
-- The cost (review of 136). is_org_member and has_full_visibility run on
-- every row of every policy that calls them. A first draft asked the
-- grant through a nested definer function: Postgres cannot inline one
-- and sets its search path on every call, so every row a caller does not
-- belong to cost seven times more (250 000 articles read by a member of
-- one business: 2.1 s before 133, 14.6 s with it). Here the grant is one
-- more EXISTS in the same statement, asked only of a trainer: the
-- caller's profile is read once for both « platform admin » and
-- « trainer » (it was read once for the first already), so a person who
-- is no trainer pays exactly what they paid before 133, and a trainer one
-- probe of the index below. Measured on a rig of 5 000 businesses: 2.3 s,
-- within noise of before.
--
-- Asked of a trainer only: a grant is made to the trainer who took the
-- request (help_take checks it), and a trainer no longer one reads
-- nothing through it from that second (their live grants are also ended,
-- trg_help_trainer_demoted below). A membership needs its profile (004's
-- foreign key), so reading the profile first loses nobody.
create index if not exists help_access_live_until
    on help_access_grants (trainer_id, org_id, expires_at) where revoked_at is null;
drop index if exists help_access_live;
drop function if exists help_grant_active(uuid);

-- 010, and the grant (read side only).
create or replace function my_org_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public, auth
as $$
    select id from orgs
    where exists(select 1 from profiles where id = auth.uid() and is_platform_admin)
    union
    select distinct m.org_id
    from memberships m
    where m.user_id = auth.uid()
    union
    -- 133: a trainer's temporary, read-only access, while it lasts.
    select g.org_id
    from help_access_grants g
    join profiles p on p.id = g.trainer_id and p.is_trainer
    where g.trainer_id = auth.uid()
      and g.revoked_at is null
      and g.expires_at > now();
$$;

-- 010, and the grant: the same answer for everyone else, at the same cost.
create or replace function is_org_member(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select coalesce((
        select p.is_platform_admin
            or exists (select 1 from memberships m
                        where m.user_id = p.id and m.org_id = p_org_id)
            -- 133: a trainer's temporary, read-only access, while it lasts.
            or (p.is_trainer and exists (
                    select 1 from help_access_grants g
                     where g.trainer_id = p.id and g.org_id = p_org_id
                       and g.revoked_at is null and g.expires_at > now()))
          from profiles p
         where p.id = auth.uid()), false);
$$;

-- 041, and the grant: a trainer helping reads what an assigned trainer
-- (full visibility) reads.
create or replace function has_full_visibility(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select coalesce((
        select p.is_platform_admin
            or exists (select 1 from memberships m
                        where m.user_id = p.id and m.org_id = p_org_id
                          and m.visibility = 'full')
            -- 133: a trainer's temporary, read-only access, while it lasts.
            or (p.is_trainer and exists (
                    select 1 from help_access_grants g
                     where g.trainer_id = p.id and g.org_id = p_org_id
                       and g.revoked_at is null and g.expires_at > now()))
          from profiles p
         where p.id = auth.uid()), false);
$$;

-- A trainer no longer one (038's set_trainer_by_phone, or by hand): their
-- live grants end now, journaled as a revoke — the helpers above already
-- read nothing for them, and a trainer made one again gets nothing back.
create or replace function trg_help_trainer_demoted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    g record;
begin
    for g in
        update help_access_grants set revoked_at = now(), revoked_by = auth.uid()
         where trainer_id = new.id and revoked_at is null
        returning request_id
    loop
        insert into help_request_events (request_id, actor_id, event, note)
        values (g.request_id, auth.uid(), 'access_revoked', 'formateur retiré');
    end loop;
    return new;
end;
$$;

drop trigger if exists help_trainer_demoted on profiles;
create trigger help_trainer_demoted
after update of is_trainer on profiles
for each row when (old.is_trainer and not coalesce(new.is_trainer, false))
execute function trg_help_trainer_demoted();

-- 100 verbatim (live checked), and a third part: a business a trainer may read for the
-- time of a request, listed as an observer's (the app then opens it read-
-- only, as it opens an assigned trainer's). Never for a business the
-- trainer already belongs to, never for a platform admin (who sees all).
create or replace function my_orgs()
returns table (
    org_id           uuid,
    name             text,
    slug             text,
    profile          text,
    default_currency text,
    roles            text[],
    visibility       text,
    theme            text,
    suspended        boolean,
    plan             text,
    owner_name       text
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        o.id, o.name, o.slug, o.profile, o.default_currency,
        array['platform_admin'::text],
        'full'::text,
        o.theme,
        (o.suspended_at is not null),
        org_plan(o.id),
        (select person_name(m.user_id) from memberships m
          where m.org_id = o.id and m.role = 'owner'
          order by m.created_at limit 1)
    from orgs o
    where exists(select 1 from profiles where id = auth.uid() and is_platform_admin)

    union all

    select
        o.id, o.name, o.slug, o.profile, o.default_currency,
        array_agg(distinct m.role::text order by m.role::text),
        case when bool_or(m.visibility = 'full') then 'full' else 'summary' end,
        o.theme,
        (o.suspended_at is not null),
        org_plan(o.id),
        (select person_name(w.user_id) from memberships w
          where w.org_id = o.id and w.role = 'owner'
          order by w.created_at limit 1)
    from memberships m
    join orgs o on o.id = m.org_id
    where m.user_id = auth.uid()
      and o.archived_at is null
      and not exists(select 1 from profiles where id = auth.uid() and is_platform_admin)
    group by o.id, o.name, o.slug, o.profile, o.default_currency, o.theme,
             o.suspended_at

    union all

    select distinct
        o.id, o.name, o.slug, o.profile, o.default_currency,
        array['observer'::text],
        'full'::text,
        o.theme,
        (o.suspended_at is not null),
        org_plan(o.id),
        (select person_name(w.user_id) from memberships w
          where w.org_id = o.id and w.role = 'owner'
          order by w.created_at limit 1)
    from help_access_grants g
    join orgs o on o.id = g.org_id
    join profiles tp on tp.id = g.trainer_id and tp.is_trainer
    where g.trainer_id = auth.uid()
      and g.revoked_at is null
      and g.expires_at > now()
      and o.archived_at is null
      and not exists (select 1 from memberships m
                       where m.user_id = auth.uid() and m.org_id = o.id)
      and not exists(select 1 from profiles where id = auth.uid() and is_platform_admin)

    order by name;
$$;

-- ------------------------------------------------------------
-- 4. Words
-- ------------------------------------------------------------
create or replace function help_subject_label(p_subject text)
returns text
language sql
immutable
set search_path = public
as $$
    select case p_subject
        when 'ventes'        then 'Ventes'
        when 'stock'         then 'Stock'
        when 'factures'      then 'Factures'
        when 'vitrine'       then 'Vitrine'
        when 'commandes'     then 'Commandes'
        when 'equipe'        then 'Équipe'
        when 'bandes'        then 'Bandes'
        when 'contributions' then 'Contributions'
        when 'rapports'      then 'Rapports'
        when 'membres'       then 'Membres'
        else 'Autre'
    end;
$$;

create or replace function help_kind_label(p_profile text)
returns text
language sql
immutable
set search_path = public
as $$
    select case
        when p_profile = 'farm' then 'Ferme'
        when p_profile in ('association', 'church') then 'Association'
        else 'Boutique'
    end;
$$;

-- A person's first name, for « Prise en charge par Awa ». Typed by that
-- person, and said in other people's bells and pushes: plain words on
-- one line, 40 characters (notify_plain, 130), as every other typed word.
create or replace function help_first_name(p_user uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        notify_plain(nullif(btrim(p.first_name), ''), 40),
        notify_plain(nullif(split_part(btrim(coalesce(p.full_name, '')), ' ', 1), ''), 40),
        'Mara')
      from profiles p where p.id = p_user;
$$;

-- ------------------------------------------------------------
-- 5. Ringing (internal)
-- ------------------------------------------------------------
-- The trainers to ring for a request: escalated, every on-duty trainer;
-- else the business's assigned ones on duty.
create or replace function help_ring_list(p_request uuid, p_escalated boolean)
returns table (user_id uuid, phone text)
language sql
stable
security definer
set search_path = public
as $$
    select p.id, nullif(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), '')
      from help_requests r
      join profiles p on p.is_trainer
     where r.id = p_request
       and coalesce((select s.on_duty from help_trainer_status s where s.user_id = p.id), true)
       and p.id is distinct from r.requested_by
       and (p_escalated
            or exists (select 1 from memberships m
                        where m.org_id = r.org_id and m.user_id = p.id and m.is_trainer));
$$;

-- Bells (and WhatsApp rows) for the trainers of [p_request]. Escalated:
-- every on-duty trainer not rung before, and the platform admins.
-- Never fails the caller: a bell that cannot be written is skipped.
create or replace function help_ring(p_request uuid, p_escalated boolean)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
    r          help_requests;
    v_org      orgs;
    v_template text := btrim(coalesce(help_setting('help_whatsapp_template') #>> '{}', ''));
    v_name     text;
    v_subject  text;
    v_msg      text;
    v_n        int := 0;
    t          record;
begin
    select * into r from help_requests where id = p_request;
    if not found or r.status <> 'open' then
        return 0;
    end if;
    select * into v_org from orgs where id = r.org_id;
    v_name    := coalesce(notify_plain(v_org.name, 60), 'Une entreprise');
    v_subject := help_subject_label(r.subject);
    v_msg := format('Demande d''aide — %s (%s) : %s%s',
                    v_name, help_kind_label(v_org.profile), v_subject,
                    coalesce(' « ' || notify_plain(r.message, 60) || ' »', ''));

    for t in select * from help_ring_list(p_request, p_escalated) loop
        -- Escalation rings the ones not rung yet (the assigned were).
        if p_escalated and exists (
            select 1 from memberships m
             where m.org_id = r.org_id and m.user_id = t.user_id and m.is_trainer)
           and r.routed_rung_at is not null then
            continue;
        end if;
        begin
            insert into notifications (recipient_id, org_id, kind, message, params)
            values (t.user_id, r.org_id, 'help_request', left(v_msg, 200),
                    jsonb_strip_nulls(jsonb_build_object(
                        'to', 'me', 'request_id', r.id, 'org', v_name,
                        'kind', help_kind_label(v_org.profile), 'subject', r.subject,
                        'escalated', p_escalated)));
            v_n := v_n + 1;
        exception when others then
            null;
        end;
        if v_template <> '' and t.phone is not null and t.phone ~ '^[0-9]{8,15}$' then
            begin
                insert into help_whatsapp_outbox (request_id, trainer_id, phone, template, params)
                values (r.id, t.user_id, t.phone, v_template,
                        jsonb_build_object('name', v_name,
                                           'kind', help_kind_label(v_org.profile),
                                           'subject', v_subject,
                                           'request_id', r.id));
            exception when others then
                null;
            end;
        end if;
    end loop;

    if p_escalated and coalesce((help_setting('admin_help_notify') #>> '{}')::boolean, true) then
        begin
            insert into notifications (recipient_id, org_id, kind, message, params)
            select p.id, null::uuid, 'help_escalated',
                   left(format('Demande d''aide sans réponse — %s (%s) : %s',
                               v_name, help_kind_label(v_org.profile), v_subject), 200),
                   jsonb_build_object('to', 'platform', 'request_id', r.id, 'org_id', r.org_id,
                                      'org', v_name, 'subject', r.subject)
              from profiles p
             where p.is_platform_admin
               and p.id is distinct from r.requested_by;
        exception when others then
            null;
        end;
    end if;
    return v_n;
end;
$$;

-- A bell to one person about a request (the business's side or the
-- trainer's). Never fails the caller.
create or replace function help_bell(p_to uuid, p_request uuid, p_kind text,
                                     p_message text, p_for text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    r help_requests;
begin
    if p_to is null or p_to = auth.uid() then
        return;
    end if;
    select * into r from help_requests where id = p_request;
    insert into notifications (recipient_id, org_id, kind, message, params)
    values (p_to, r.org_id, p_kind, left(p_message, 200),
            jsonb_strip_nulls(jsonb_build_object('to', p_for,
                'request_id', p_request,
                'who', help_first_name(auth.uid()),
                'org', notify_plain((select name from orgs where id = r.org_id), 60),
                'subject', r.subject,
                'visit_answer', r.visit_answer)));
exception when others then
    null;
end;
$$;

create or replace function help_log(p_request uuid, p_event text, p_note text default null)
returns void
language sql
security definer
set search_path = public
as $$
    insert into help_request_events (request_id, actor_id, event, note)
    values (p_request, auth.uid(), p_event, left(p_note, 500));
$$;

-- ------------------------------------------------------------
-- 6. The clock (3): routing at opening, escalation, the end of a grant
-- ------------------------------------------------------------
create or replace function help_tick()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    r       record;
    v_rout  int := 0;
    v_esc   int := 0;
    v_exp   int := 0;
begin
    -- Routed now (made out of hours, the hours have come): the assigned.
    for r in
        select id from help_requests
         where status = 'open' and routed_rung_at is null and routed_at <= now()
         order by created_at
         for update skip locked
    loop
        perform help_ring(r.id, false);
        update help_requests set routed_rung_at = now() where id = r.id;
        insert into help_request_events (request_id, event) values (r.id, 'routed');
        v_rout := v_rout + 1;
    end loop;

    -- Nobody took it in time: everyone on duty, and the admins.
    for r in
        select id from help_requests
         where status = 'open' and escalated_at is null and escalate_at <= now()
           and routed_rung_at is not null
         order by created_at
         for update skip locked
    loop
        update help_requests set escalated_at = now() where id = r.id;
        perform help_ring(r.id, true);
        insert into help_request_events (request_id, event) values (r.id, 'escalated');
        v_esc := v_esc + 1;
    end loop;

    -- A grant past its 48 h: said once in the journal (the read helpers
    -- stopped it at its second already).
    for r in
        select id, request_id from help_access_grants
         where revoked_at is null and expires_at <= now() and expiry_logged_at is null
         for update skip locked
    loop
        update help_access_grants set expiry_logged_at = now() where id = r.id;
        insert into help_request_events (request_id, event) values (r.request_id, 'access_expired');
        v_exp := v_exp + 1;
    end loop;

    -- WhatsApp rows nobody carried within the hour: not sent any more.
    update help_whatsapp_outbox set state = 'stale', done_at = now()
     where state in ('pending', 'sending') and created_at < now() - interval '1 hour';

    return jsonb_build_object('routed', v_rout, 'escalated', v_esc, 'expired', v_exp);
end;
$$;

-- ------------------------------------------------------------
-- 7. The business's side
-- ------------------------------------------------------------
-- The caller's own place in a business, for asking: a member who is not an
-- observer and not a trainer's assignment.
create or replace function help_can_ask(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select auth.uid() is not null and exists (
        select 1 from memberships m
         where m.org_id = p_org_id and m.user_id = auth.uid()
           and m.role <> 'observer' and not m.is_trainer);
$$;

-- One request as its business reads it.
create or replace function help_request_json(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'id', r.id, 'org_id', r.org_id, 'subject', r.subject, 'message', r.message,
        'photo_document_id', r.photo_document_id,
        'contact', r.contact, 'status', r.status,
        -- The caller asked it (else: one of the business's admins reads it).
        'mine', r.requested_by = auth.uid(),
        'created_at', r.created_at, 'routed_at', r.routed_at,
        'queued', r.routed_at > r.created_at + interval '1 second',
        'escalated', r.escalated_at is not null,
        'taken_at', r.taken_at,
        'trainer', case when r.taken_by is not null then jsonb_build_object(
            'first_name', help_first_name(r.taken_by),
            'phone', (select nullif(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), '')
                        from profiles p where p.id = r.taken_by),
            'member', exists (select 1 from memberships m
                               where m.org_id = r.org_id and m.user_id = r.taken_by)) end,
        'visit_answer', r.visit_answer, 'visit_note', r.visit_note,
        'resolved_at', r.resolved_at, 'resolution_note', r.resolution_note,
        'closed_at', r.closed_at, 'rating', r.rating,
        'access', (select jsonb_build_object('granted_at', g.granted_at, 'expires_at', g.expires_at,
                                             'live', g.expires_at > now(),
                                             'opened', g.opened_count)
                     from help_access_grants g
                    where g.request_id = r.id and g.revoked_at is null
                    order by g.granted_at desc limit 1),
        'events', coalesce((select jsonb_agg(jsonb_build_object(
                                'event', e.event, 'at', e.at,
                                'who', case when e.actor_id is not null
                                            then help_first_name(e.actor_id) end)
                                order by e.at, e.id)
                              from help_request_events e where e.request_id = r.id), '[]'::jsonb))
    from help_requests r where r.id = p_id;
$$;

-- What the « Besoin d'aide » button needs (the app, every home):
--   available  this person may ask here (a member, not an observer)
--   pro        the business is on Mara Pro (else: the basic Aide)
--   hours      {open, close, in_hours, next_open}
--   request    the active request (open or taken), else the last one
--              resolved and not closed, else null
--   left       requests left today
create or replace function help_state(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_id uuid;
begin
    if not help_can_ask(p_org_id) then
        return jsonb_build_object('available', false);
    end if;
    select id into v_id from help_requests
     where org_id = p_org_id and status in ('open', 'taken', 'resolved')
     order by (status in ('open', 'taken')) desc, created_at desc
     limit 1;
    return jsonb_build_object(
        'available', true,
        'pro', org_plan(p_org_id) = 'pro',
        'hours', jsonb_build_object(
            'open', help_setting_int('help_hours_open'),
            'close', help_setting_int('help_hours_close'),
            'in_hours', help_in_hours(now()),
            'next_open', help_next_open(now())),
        'request', case when v_id is null then null else help_request_json(v_id) end,
        'left', greatest(help_setting_int('help_daily_limit') - (
            select count(*) from help_requests
             where org_id = p_org_id and created_at > now() - interval '24 hours'), 0));
end;
$$;

-- « Envoyer la demande ».
create or replace function help_request_create(
    p_org_id   uuid,
    p_subject  text,
    p_message  text default null,
    p_contact  text default 'whatsapp',
    p_phone    text default null,
    p_photo    uuid default null,
    p_context  jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_me      uuid := auth.uid();
    v_phone   text;
    v_message text;
    v_routed  timestamptz;
    v_esc     timestamptz;
    v_id      uuid;
    v_assigned boolean;
    v_context jsonb;
begin
    if v_me is null then
        raise exception 'Connectez-vous pour demander de l''aide.';
    end if;
    if not help_can_ask(p_org_id) then
        raise exception 'Seule l''équipe de l''entreprise peut demander de l''aide ici.';
    end if;
    if org_plan(p_org_id) <> 'pro' then
        raise exception 'L''aide d''un formateur vient avec Mara Pro.';
    end if;
    if p_subject is null or p_subject not in ('ventes', 'stock', 'factures', 'vitrine', 'commandes',
            'equipe', 'autre', 'bandes', 'contributions', 'rapports', 'membres') then
        raise exception 'Choisissez de quoi il s''agit.';
    end if;
    if p_contact is null or p_contact not in ('call', 'whatsapp', 'visit') then
        raise exception 'Choisissez comment être aidé : appel, WhatsApp ou visite.';
    end if;
    v_message := nullif(btrim(regexp_replace(coalesce(p_message, ''), '[[:cntrl:]]', ' ', 'g')), '');
    if char_length(v_message) > 500 then
        raise exception 'Un message de 500 caractères au plus, s''il vous plaît.';
    end if;
    v_phone := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');
    if v_phone is null then
        select nullif(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g'), '')
          into v_phone from profiles where id = v_me;
    end if;
    if v_phone is null or v_phone !~ '^[0-9]{8,15}$' then
        raise exception 'Un numéro où vous joindre, avec l''indicatif (par exemple 22670000000).';
    end if;
    if p_photo is not null and not exists (
            select 1 from documents d where d.id = p_photo and d.org_id = p_org_id) then
        raise exception 'Cette photo n''est pas de cette entreprise.';
    end if;
    if exists (select 1 from help_requests where org_id = p_org_id and status in ('open', 'taken')) then
        raise exception 'Une demande d''aide est déjà en cours pour cette entreprise.';
    end if;
    if (select count(*) from help_requests
         where org_id = p_org_id and created_at > now() - interval '24 hours')
       >= help_setting_int('help_daily_limit') then
        raise exception 'Les demandes d''aide de ces 24 heures sont toutes faites. Réessayez demain, ou écrivez à Mara.';
    end if;

    v_context := jsonb_strip_nulls(jsonb_build_object(
        'screen',   notify_plain(p_context ->> 'screen', 60),
        'version',  notify_plain(p_context ->> 'version', 40, true),
        'platform', notify_plain(p_context ->> 'platform', 20)));

    v_routed := help_next_open(now());
    select exists (
        select 1 from memberships m join profiles p on p.id = m.user_id
         where m.org_id = p_org_id and m.is_trainer and p.is_trainer
           and coalesce((select s.on_duty from help_trainer_status s where s.user_id = p.id), true))
      into v_assigned;
    -- No assigned trainer on duty: everyone, at once.
    v_esc := case when v_assigned
                  then help_add_open(v_routed, help_setting_int('help_escalate_minutes'))
                  else v_routed end;

    begin
        insert into help_requests (org_id, requested_by, subject, message, photo_document_id,
                                   contact, contact_phone, context, routed_at, escalate_at)
        values (p_org_id, v_me, p_subject, v_message, p_photo, p_contact, v_phone,
                v_context, v_routed, v_esc)
        returning id into v_id;
    exception when unique_violation then
        raise exception 'Une demande d''aide est déjà en cours pour cette entreprise.';
    end;
    perform help_log(v_id, 'created', null);
    if v_routed > now() then
        perform help_log(v_id, 'queued', null);
    else
        -- In the hours: the assigned now, everyone at once without them.
        perform help_ring(v_id, false);
        update help_requests set routed_rung_at = now() where id = v_id;
        if not v_assigned then
            update help_requests set escalated_at = now() where id = v_id;
            perform help_ring(v_id, true);
            insert into help_request_events (request_id, event) values (v_id, 'escalated');
        end if;
    end if;
    return help_request_json(v_id);
end;
$$;

-- The request's own people: who asked, while still of the business (one
-- who left reads nothing of it, the trainer's number least of all), or
-- the business's admins (a real membership — a platform admin closes
-- nothing for a business).
create or replace function help_is_owner_side(p_request uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from help_requests r
         where r.id = p_request
           and ((r.requested_by = auth.uid() and help_can_ask(r.org_id))
                or exists (select 1 from memberships m
                            where m.org_id = r.org_id and m.user_id = auth.uid()
                              and m.role in ('owner', 'super_admin', 'admin'))));
$$;

-- « Pas encore » — a resolved request back to its trainer.
create or replace function help_reopen(p_request uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    r help_requests;
begin
    if not help_is_owner_side(p_request) then
        raise exception 'Cette demande n''est pas la vôtre.';
    end if;
    select * into r from help_requests where id = p_request for update;
    if r.status <> 'resolved' then
        raise exception 'Seule une demande marquée résolue peut être rouverte.';
    end if;
    begin
        update help_requests set status = 'taken', resolved_at = null where id = p_request;
    exception when unique_violation then
        raise exception 'Une autre demande d''aide est déjà en cours pour cette entreprise.';
    end;
    perform help_log(p_request, 'reopened', null);
    perform help_bell(r.taken_by, p_request, 'help_reopened',
        format('%s : « pas encore réglé » — la demande vous revient.',
               coalesce(notify_plain((select name from orgs where id = r.org_id), 60), 'Une entreprise')),
        'me');
    return help_request_json(p_request);
end;
$$;

-- « Oui, merci » / « Fermer » — the request ends, rated 1 or -1 (or not),
-- and its access with it.
create or replace function help_close(p_request uuid, p_rating int default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    r help_requests;
begin
    if not help_is_owner_side(p_request) then
        raise exception 'Cette demande n''est pas la vôtre.';
    end if;
    if p_rating is not null and p_rating not in (-1, 1) then
        raise exception 'Une note : pouce levé ou pouce baissé.';
    end if;
    select * into r from help_requests where id = p_request for update;
    if r.status = 'closed' then
        return help_request_json(p_request);
    end if;
    update help_requests
       set status = 'closed', closed_at = now(), closed_by = auth.uid(),
           rating = case when r.taken_by is null then null else p_rating end
     where id = p_request;
    perform help_log(p_request, 'closed',
        case p_rating when 1 then 'up' when -1 then 'down' end);
    update help_access_grants set revoked_at = now(), revoked_by = auth.uid()
     where request_id = p_request and revoked_at is null;
    perform help_bell(r.taken_by, p_request, 'help_closed',
        format('%s a fermé la demande%s',
               coalesce(notify_plain((select name from orgs where id = r.org_id), 60), 'L''entreprise'),
               case p_rating when 1 then ' — merci !' when -1 then ' — pas satisfait' else '' end),
        'me');
    return help_request_json(p_request);
end;
$$;

-- « Autoriser l'accès 48 h » (6): the business's owner or admin, for the
-- trainer who took the request and is not of the business.
create or replace function help_access_grant(p_request uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    r     help_requests;
    v_exp timestamptz := now() + interval '48 hours';
begin
    select * into r from help_requests where id = p_request for update;
    if not found or not exists (
        select 1 from memberships m
         where m.org_id = r.org_id and m.user_id = auth.uid()
           and m.role in ('owner', 'super_admin', 'admin')) then
        raise exception 'Seul le propriétaire ou un administrateur de l''entreprise autorise l''accès.';
    end if;
    if r.status not in ('taken', 'resolved') or r.taken_by is null then
        raise exception 'L''accès s''autorise une fois la demande prise en charge.';
    end if;
    if exists (select 1 from memberships m where m.org_id = r.org_id and m.user_id = r.taken_by) then
        raise exception 'Ce formateur voit déjà votre entreprise.';
    end if;
    if exists (select 1 from help_access_grants g
                where g.request_id = p_request and g.revoked_at is null and g.expires_at > now()) then
        return help_request_json(p_request);
    end if;
    -- An earlier grant of this request, past its 48 h: closed for good.
    update help_access_grants set revoked_at = coalesce(revoked_at, expires_at)
     where request_id = p_request and revoked_at is null;
    insert into help_access_grants (request_id, org_id, trainer_id, granted_by, expires_at, label)
    values (p_request, r.org_id, r.taken_by, auth.uid(), v_exp,
            format('Accès en lecture seule de %s (formation), 48 h', help_first_name(r.taken_by)));
    perform help_log(p_request, 'access_granted', null);
    perform help_bell(r.taken_by, p_request, 'help_access',
        format('%s vous ouvre son activité en lecture seule pour 48 h.',
               coalesce(notify_plain((select name from orgs where id = r.org_id), 60), 'L''entreprise')),
        'me');
    return help_request_json(p_request);
end;
$$;

-- « Retirer l'accès »: the business's owner or admin, the trainer
-- themselves, or a platform admin.
create or replace function help_access_revoke(p_request uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    r help_requests;
    v_n int;
begin
    select * into r from help_requests where id = p_request;
    if not found or not (
        r.taken_by = auth.uid()
        or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
        or exists (select 1 from memberships m
                    where m.org_id = r.org_id and m.user_id = auth.uid()
                      and m.role in ('owner', 'super_admin', 'admin'))) then
        raise exception 'Vous ne pouvez pas retirer cet accès.';
    end if;
    update help_access_grants set revoked_at = now(), revoked_by = auth.uid()
     where request_id = p_request and revoked_at is null;
    get diagnostics v_n = row_count;
    if v_n > 0 then
        perform help_log(p_request, 'access_revoked', null);
        if r.taken_by is distinct from auth.uid() then
            perform help_bell(r.taken_by, p_request, 'help_access_ended',
                format('%s a retiré votre accès en lecture seule.',
                       coalesce(notify_plain((select name from orgs where id = r.org_id), 60), 'L''entreprise')),
                'me');
        end if;
    end if;
    return help_request_json(p_request);
end;
$$;

-- ------------------------------------------------------------
-- 8. The trainer's side
-- ------------------------------------------------------------
create or replace function help_is_trainer()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (select 1 from profiles where id = auth.uid() and (is_trainer or is_platform_admin));
$$;

-- Whether the caller may see this request as a helper (the policy's rule).
create or replace function help_helper_sees(p_request uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from help_requests r
         where r.id = p_request
           and (r.taken_by = auth.uid()
                or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
                or (exists (select 1 from profiles where id = auth.uid() and is_trainer)
                    and ((r.escalated_at is not null and r.status = 'open')
                         or exists (select 1 from memberships m
                                     where m.user_id = auth.uid() and m.org_id = r.org_id
                                       and m.is_trainer)))));
$$;

-- One request as a helper reads it: the business, the subject, the words;
-- the person's number only for the one who took it (or an admin).
create or replace function help_inbox_row(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'id', r.id, 'org_id', r.org_id, 'org', o.name, 'profile', o.profile, 'city', o.city,
        'subject', r.subject, 'message', r.message, 'contact', r.contact,
        'has_photo', r.photo_document_id is not null,
        'context', r.context, 'status', r.status,
        'created_at', r.created_at, 'routed_at', r.routed_at,
        'escalated', r.escalated_at is not null,
        'mine', r.taken_by = auth.uid(),
        'taken_by', case when r.taken_by is not null then help_first_name(r.taken_by) end,
        'assigned', exists (select 1 from memberships m
                             where m.user_id = auth.uid() and m.org_id = r.org_id and m.is_trainer),
        'member', exists (select 1 from memberships m
                           where m.user_id = auth.uid() and m.org_id = r.org_id),
        'requester', help_first_name(r.requested_by),
        'phone', case when r.taken_by = auth.uid()
                        or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
                      then r.contact_phone end,
        'visit_answer', r.visit_answer, 'visit_note', r.visit_note,
        'resolved_at', r.resolved_at, 'resolution_note', r.resolution_note,
        'closed_at', r.closed_at, 'rating', r.rating,
        'access', (select jsonb_build_object('granted_at', g.granted_at, 'expires_at', g.expires_at,
                                             'live', g.expires_at > now())
                     from help_access_grants g
                    where g.request_id = r.id and g.trainer_id = auth.uid()
                      and g.revoked_at is null and g.expires_at > now()
                    order by g.granted_at desc limit 1))
    from help_requests r join orgs o on o.id = r.org_id
    where r.id = p_id;
$$;

-- The trainer's inbox: open requests oldest first, then the caller's own
-- in progress, then the last week's done. {trainer:false} for anybody
-- else (the app then draws no inbox).
create or replace function help_inbox()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_rows jsonb;
begin
    if not help_is_trainer() then
        return jsonb_build_object('trainer', false);
    end if;
    perform help_tick();
    select coalesce(jsonb_agg(help_inbox_row(x.id) order by x.ord, x.at), '[]'::jsonb)
      into v_rows
      from (
        select r.id,
               case when r.status = 'open' then 0
                    when r.status in ('taken', 'resolved') and r.taken_by = auth.uid() then 1
                    else 2 end as ord,
               case when r.status = 'open' then extract(epoch from r.created_at)
                    else -extract(epoch from coalesce(r.closed_at, r.resolved_at, r.taken_at, r.created_at)) end as at
          from help_requests r
         where help_helper_sees(r.id)
           and (r.status in ('open', 'taken', 'resolved')
                or coalesce(r.closed_at, r.created_at) > now() - interval '7 days')
           -- Not yet routed (made out of hours): nobody is asked before the hours.
           and (r.routed_at <= now() or r.taken_by = auth.uid())
         order by 2, 3
         limit 100) x;
    return jsonb_build_object(
        'trainer', true,
        'admin', exists (select 1 from profiles where id = auth.uid() and is_platform_admin),
        'on_duty', coalesce((select on_duty from help_trainer_status where user_id = auth.uid()), true),
        'in_hours', help_in_hours(now()),
        'hours', jsonb_build_object('open', help_setting_int('help_hours_open'),
                                    'close', help_setting_int('help_hours_close')),
        'requests', v_rows);
end;
$$;

-- « En service » / « Hors service ».
create or replace function help_set_on_duty(p_on boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_trainer) then
        raise exception 'Réservé aux formateurs de Mara.';
    end if;
    insert into help_trainer_status (user_id, on_duty, updated_at)
    values (auth.uid(), coalesce(p_on, true), now())
    on conflict (user_id) do update set on_duty = excluded.on_duty, updated_at = now();
    return coalesce(p_on, true);
end;
$$;

-- « Je m'en occupe » (5): the first wins.
create or replace function help_take(p_request uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org uuid;
    v_by  uuid;
    v_who text := help_first_name(auth.uid());
begin
    if not help_is_trainer() or not help_helper_sees(p_request) then
        raise exception 'Cette demande ne vous est pas adressée.';
    end if;
    update help_requests
       set status = 'taken', taken_by = auth.uid(), taken_at = now()
     where id = p_request and status = 'open'
     returning org_id, requested_by into v_org, v_by;
    if v_org is null then
        if exists (select 1 from help_requests where id = p_request and taken_by = auth.uid()) then
            return help_inbox_row(p_request);
        end if;
        raise exception 'Un autre formateur s''occupe déjà de cette demande.';
    end if;
    perform help_log(p_request, 'taken', null);
    perform help_bell(v_by, p_request, 'help_taken',
        format('%s (formation Mara) s''occupe de votre demande d''aide.', v_who), 'shop');
    return help_inbox_row(p_request);
end;
$$;

-- A visit asked for: accepted, or a call proposed instead.
create or replace function help_visit_answer(p_request uuid, p_answer text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    r help_requests;
    v_note text := nullif(btrim(regexp_replace(coalesce(p_note, ''), '[[:cntrl:]]', ' ', 'g')), '');
begin
    select * into r from help_requests where id = p_request for update;
    if not found or r.taken_by is distinct from auth.uid() then
        raise exception 'Prenez d''abord la demande en charge.';
    end if;
    if r.contact <> 'visit' then
        raise exception 'Cette demande ne demande pas de visite.';
    end if;
    if p_answer not in ('accepted', 'call_instead') then
        raise exception 'Acceptez la visite, ou proposez un appel.';
    end if;
    if char_length(v_note) > 200 then
        raise exception 'Un mot de 200 caractères au plus.';
    end if;
    update help_requests set visit_answer = p_answer, visit_note = v_note where id = p_request;
    perform help_log(p_request, case p_answer when 'accepted' then 'visit_accepted' else 'call_instead' end,
                     v_note);
    perform help_bell(r.requested_by, p_request, 'help_visit',
        case p_answer
            when 'accepted' then format('%s viendra vous voir%s', help_first_name(auth.uid()),
                                        coalesce(' : ' || notify_plain(v_note, 60), '.'))
            else format('%s vous propose plutôt un appel%s', help_first_name(auth.uid()),
                        coalesce(' : ' || notify_plain(v_note, 60), '.'))
        end, 'shop');
    return help_inbox_row(p_request);
end;
$$;

-- « Marquer résolue », with a note.
create or replace function help_resolve(p_request uuid, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    r help_requests;
    v_note text := nullif(btrim(regexp_replace(coalesce(p_note, ''), '[[:cntrl:]]', ' ', 'g')), '');
begin
    select * into r from help_requests where id = p_request for update;
    if not found or not (r.taken_by = auth.uid()
            or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)) then
        raise exception 'Seul le formateur qui a pris la demande la marque résolue.';
    end if;
    if r.status <> 'taken' then
        raise exception 'Cette demande n''est pas en cours.';
    end if;
    if char_length(v_note) > 500 then
        raise exception 'Une note de 500 caractères au plus.';
    end if;
    update help_requests set status = 'resolved', resolved_at = now(), resolution_note = v_note
     where id = p_request;
    perform help_log(p_request, 'resolved', v_note);
    perform help_bell(r.requested_by, p_request, 'help_resolved',
        format('%s a marqué votre demande résolue. C''est réglé ?', help_first_name(auth.uid())), 'shop');
    return help_inbox_row(p_request);
end;
$$;

-- « Ouvrir l'activité (lecture seule) »: the grantee says they open it —
-- counted on the grant (so 008's journal shows each opening) and in the
-- request's journal. Answers the business's id while the grant lives.
create or replace function help_access_opened(p_request uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org uuid;
begin
    update help_access_grants
       set opened_count = opened_count + 1, last_opened_at = now()
     where request_id = p_request and trainer_id = auth.uid()
       and revoked_at is null and expires_at > now()
     returning org_id into v_org;
    if v_org is null then
        raise exception 'Cet accès est terminé.';
    end if;
    perform help_log(p_request, 'access_opened', null);
    return v_org;
end;
$$;

-- ------------------------------------------------------------
-- 9. The platform's side (« Aujourd'hui » and the console)
-- ------------------------------------------------------------
-- « VOUS ATTEND »: help_late (open, more than help_late_minutes of open
-- time since routed) and help_open (the other active ones). Null for
-- anybody but a platform admin.
create or replace function help_todo_counts()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_late int;
    v_open int;
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return null;
    end if;
    perform help_tick();
    select count(*) filter (where status = 'open' and routed_at <= now()
                              and help_open_minutes(routed_at, now()) >= help_setting_int('help_late_minutes')),
           count(*) filter (where not (status = 'open' and routed_at <= now()
                              and help_open_minutes(routed_at, now()) >= help_setting_int('help_late_minutes')))
      into v_late, v_open
      from help_requests where status in ('open', 'taken');
    return jsonb_build_object('help_late', v_late, 'help_open', v_open);
end;
$$;

-- The console (mockup 6): the numbers, each trainer, what waits, WhatsApp.
create or replace function help_console()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_template text := btrim(coalesce(help_setting('help_whatsapp_template') #>> '{}', ''));
    v_last     help_whatsapp_outbox;
    v_wa       text;
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return null;
    end if;
    perform help_tick();
    select * into v_last from help_whatsapp_outbox
     where state in ('sent', 'failed') order by done_at desc nulls last limit 1;
    v_wa := case
        when v_template = '' then 'off'
        when v_last.id is not null and v_last.state = 'failed' and v_last.error = 'template' then 'template'
        when v_last.id is not null and v_last.state = 'failed' then 'failing'
        when exists (select 1 from help_whatsapp_outbox
                      where state = 'pending' and created_at < now() - interval '5 minutes') then 'waiting'
        when v_last.id is not null and v_last.state = 'sent' then 'on'
        else 'unknown' end;
    return jsonb_build_object(
        'open', (select count(*) from help_requests where status in ('open', 'taken')),
        'avg_minutes', (select round(avg(help_open_minutes(routed_at, taken_at)))
                          from help_requests
                         where taken_at is not null and taken_at > now() - interval '7 days'),
        'resolved_7', (select count(*) from help_requests
                        where resolved_at > now() - interval '7 days'),
        'up', (select count(*) from help_requests where rating = 1 and closed_at > now() - interval '30 days'),
        'down', (select count(*) from help_requests where rating = -1 and closed_at > now() - interval '30 days'),
        'in_hours', help_in_hours(now()),
        'hours', jsonb_build_object('open', help_setting_int('help_hours_open'),
                                    'close', help_setting_int('help_hours_close')),
        'whatsapp', jsonb_build_object('state', v_wa, 'template', v_template,
                                       'last_error', case when v_last.state = 'failed' then v_last.error end,
                                       'last_at', v_last.done_at),
        'trainers', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'user_id', p.id, 'name', coalesce(person_name(p.id), 'Formateur'),
                       'on_duty', coalesce(s.on_duty, true),
                       'assigned', (select count(*) from memberships m where m.user_id = p.id and m.is_trainer),
                       'taken', (select count(*) from help_requests r
                                  where r.taken_by = p.id and r.status = 'taken'),
                       'resolved_7', (select count(*) from help_requests r
                                       where r.taken_by = p.id and r.resolved_at > now() - interval '7 days'),
                       'phone', p.phone is not null)
                   order by coalesce(s.on_duty, true) desc, person_name(p.id))
              from profiles p left join help_trainer_status s on s.user_id = p.id
             where p.is_trainer), '[]'::jsonb),
        'waiting', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'id', r.id, 'org', o.name, 'org_id', r.org_id, 'profile', o.profile,
                       'subject', r.subject, 'status', r.status,
                       'created_at', r.created_at, 'routed_at', r.routed_at,
                       'escalated', r.escalated_at is not null,
                       'minutes', help_open_minutes(r.routed_at, now()),
                       'late', r.status = 'open' and r.routed_at <= now()
                               and help_open_minutes(r.routed_at, now()) >= help_setting_int('help_late_minutes'),
                       'taken_by', case when r.taken_by is not null then help_first_name(r.taken_by) end)
                   order by r.created_at)
              from help_requests r join orgs o on o.id = r.org_id
             where r.status in ('open', 'taken')), '[]'::jsonb));
end;
$$;

-- ------------------------------------------------------------
-- 10. WhatsApp's carrier (the Worker, service role only)
-- ------------------------------------------------------------
-- Up to [p_limit] rows to send now, each marked « sending » (claimed once:
-- skip locked). The clock runs first, so the Worker's minute is a tick too.
create or replace function help_whatsapp_claim(p_limit int default 20)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v jsonb;
begin
    perform help_tick();
    with c as (
        select id from help_whatsapp_outbox
         where state = 'pending' and created_at > now() - interval '1 hour'
         order by created_at
         limit greatest(least(coalesce(p_limit, 20), 100), 1)
         for update skip locked
    ), u as (
        update help_whatsapp_outbox o set state = 'sending', claimed_at = now()
          from c where o.id = c.id
        returning o.id, o.phone, o.template, o.params
    )
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'to', phone, 'template', template,
                                                 'params', params)), '[]'::jsonb)
      into v from u;
    return v;
end;
$$;

-- How one went: sent, or failed with a word (template | not_whatsapp |
-- rate | meta | network).
create or replace function help_whatsapp_done(p_id uuid, p_ok boolean, p_error text default null)
returns void
language sql
security definer
set search_path = public
as $$
    update help_whatsapp_outbox
       set state = case when p_ok then 'sent' else 'failed' end,
           error = case when p_ok then null else left(coalesce(nullif(p_error, ''), 'meta'), 40) end,
           done_at = now()
     where id = p_id and state = 'sending';
$$;

-- ------------------------------------------------------------
-- 11. The clock, every minute (where pg_cron is)
-- ------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
        begin
            create extension if not exists pg_cron;
            if not exists (select 1 from cron.job where jobname = 'help-tick') then
                perform cron.schedule('help-tick', '* * * * *', 'select public.help_tick()');
            end if;
        exception when others then
            raise notice 'pg_cron not scheduled here: %', sqlerrm;
        end;
    end if;
end $$;

-- ------------------------------------------------------------
-- 12. Who may call what (063: born closed to PUBLIC and anon)
-- ------------------------------------------------------------
do $$
declare
    -- The app's doors: authenticated.
    v_app text[] := array[
        'help_state(uuid)',
        'help_request_create(uuid, text, text, text, text, uuid, jsonb)',
        'help_reopen(uuid)',
        'help_close(uuid, integer)',
        'help_access_grant(uuid)',
        'help_access_revoke(uuid)',
        'help_inbox()',
        'help_set_on_duty(boolean)',
        'help_take(uuid)',
        'help_visit_answer(uuid, text, text)',
        'help_resolve(uuid, text)',
        'help_access_opened(uuid)',
        'help_todo_counts()',
        'help_console()'];
    -- Internal: the definer doors and the policies' helpers call them.
    v_internal text[] := array[
        'trg_help_settings()',
        'help_setting(text)',
        'help_setting_int(text)',
        'help_in_hours(timestamptz)',
        'help_next_open(timestamptz)',
        'help_add_open(timestamptz, integer)',
        'help_open_minutes(timestamptz, timestamptz)',
        'trg_help_trainer_demoted()',
        'help_subject_label(text)',
        'help_kind_label(text)',
        'help_first_name(uuid)',
        'help_ring_list(uuid, boolean)',
        'help_ring(uuid, boolean)',
        'help_bell(uuid, uuid, text, text, text)',
        'help_log(uuid, text, text)',
        'help_can_ask(uuid)',
        'help_request_json(uuid)',
        'help_is_owner_side(uuid)',
        'help_is_trainer()',
        'help_helper_sees(uuid)',
        'help_inbox_row(uuid)'];
    -- The service role's (the Worker) and the cron's (postgres).
    v_service text[] := array[
        'help_tick()',
        'help_whatsapp_claim(integer)',
        'help_whatsapp_done(uuid, boolean, text)'];
    v_has_anon boolean := exists (select 1 from pg_roles where rolname = 'anon');
    v_has_auth boolean := exists (select 1 from pg_roles where rolname = 'authenticated');
    v_has_svc  boolean := exists (select 1 from pg_roles where rolname = 'service_role');
    f text;
begin
    foreach f in array v_app || v_internal || v_service loop
        execute format('revoke execute on function %s from public', f);
        if v_has_anon then execute format('revoke execute on function %s from anon', f); end if;
    end loop;
    foreach f in array v_app loop
        if v_has_auth then execute format('grant execute on function %s to authenticated', f); end if;
    end loop;
    foreach f in array v_internal || v_service loop
        if v_has_auth then execute format('revoke execute on function %s from authenticated', f); end if;
    end loop;
    foreach f in array v_service loop
        if v_has_svc then execute format('grant execute on function %s to service_role', f); end if;
    end loop;
end $$;

notify pgrst, 'reload schema';
