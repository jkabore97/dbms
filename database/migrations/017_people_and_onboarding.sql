-- ============================================================
-- 017_people_and_onboarding.sql — who a person is, and the two ways in.
--
-- Until now a `profiles` row held a `full_name` and a phone number, and both
-- came from whatever the auth provider happened to have. That is enough to
-- greet somebody by name and not enough for anything a business does with a
-- person: a payslip needs a legal name, a contract needs a date of birth, and
-- a directory that cannot tell two Ouédraogos apart is a directory nobody
-- uses twice.
--
-- Two routes in, and they are deliberately different shapes.
--
-- **An employee joins a business that already exists.** They make an account,
-- say who they are, and enter a code their manager sent them. The code is
-- what grants access — nothing about filling in a form does — so a stranger
-- who completes the whole profile still belongs to no business.
--
-- **A manager asks for a business to exist.** They make an account, say who
-- they are, describe the business, and wait. `create_org()` has been platform
-- admin only since 010 and stays that way: the thing that decides whether a
-- new tenant appears on this platform is a person at Kaj-consulting, not a
-- sign-up form. What changes is that there is now a queue for them to look
-- at instead of an email nobody sent.
--
-- Three decisions worth knowing.
--
-- 1. **A profile is never half-written by the server.** Everything added here
--    is nullable, and `profile_is_complete()` is a question rather than a
--    constraint. Somebody signed up before this migration existed and must
--    keep working; somebody who abandons the form halfway must not be locked
--    out of an account they already have.
--
-- 2. **The phone typed twice is checked in the app, not here.** Two identical
--    strings arriving in one call prove nothing about what was typed. The
--    confirmation exists to catch a mistyped digit at the keyboard, which is
--    where it has to be caught.
--
-- 3. **An application is not a business.** `org_applications` holds what
--    somebody asked for. Approving one calls `create_org()` and makes the
--    applicant its owner in the same transaction; until then there is no org,
--    no slug reserved, and nothing for them to sign into.
-- ============================================================

-- ------------------------------------------------------------
-- 1. WHO SOMEBODY IS
-- ------------------------------------------------------------
-- Split names rather than one field, because the parts get used separately:
-- a payslip wants "OUÉDRAOGO Awa", a greeting wants "Awa", and a directory
-- sorts on the family name. `full_name` stays and stays authoritative for
-- display — every screen in the app already reads it — and is kept in step by
-- the function below rather than by a trigger, so importing a row never
-- silently rewrites what somebody typed.

alter table profiles add column if not exists first_name    text;
alter table profiles add column if not exists middle_name   text;
alter table profiles add column if not exists last_name     text;
alter table profiles add column if not exists date_of_birth date;
alter table profiles add column if not exists title         text;
alter table profiles add column if not exists profile_completed_at timestamptz;

comment on column profiles.title is
    'What they do — "Vendeuse", "Gérant", "Comptable". Their own words, not a role in the permission sense.';
comment on column profiles.date_of_birth is
    'Needed by a contract and a payslip. Nullable: an account that predates this must keep working.';

-- A date of birth that is in the future or implies a 12-year-old is a typo,
-- and a typo in this field ends up on a contract. Checked as a constraint
-- because unlike the rest of the form there is a right answer.
do $$
begin
    if not exists (
        select 1 from pg_constraint where conname = 'profiles_dob_is_plausible'
    ) then
        alter table profiles add constraint profiles_dob_is_plausible
            check (
                date_of_birth is null
                or (date_of_birth > current_date - interval '120 years'
                    and date_of_birth < current_date - interval '14 years')
            );
    end if;
end $$;

-- Sorting a directory by family name, which is how a list of people is read.
create index if not exists profiles_by_last_name
    on profiles (lower(last_name)) where last_name is not null;

-- Whether there is enough here to put on a contract. A question, never a gate
-- on signing in: an incomplete profile is a prompt, not a lockout.
create or replace function profile_is_complete(p_user_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select coalesce(
        (select first_name is not null and btrim(first_name) <> ''
            and last_name is not null and btrim(last_name) <> ''
            and date_of_birth is not null
            and phone is not null and btrim(phone) <> ''
         from profiles
         where id = coalesce(p_user_id, auth.uid())),
        false);
$$;

-- What somebody tells us about themselves, in one call.
--
-- Security definer and self-only: the 004 policy already lets a person edit
-- their own profile, and this adds the name assembly and the refusal to write
-- somebody else's. A manager correcting a colleague's spelling is a different
-- act and is not this one.
create or replace function save_my_profile(
    p_first_name    text,
    p_last_name     text,
    p_middle_name   text default null,
    p_date_of_birth date default null,
    p_title         text default null,
    p_phone         text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
    v_first text := nullif(btrim(coalesce(p_first_name, '')), '');
    v_last  text := nullif(btrim(coalesce(p_last_name, '')), '');
    v_mid   text := nullif(btrim(coalesce(p_middle_name, '')), '');
    v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
    v_full  text;
begin
    if v_actor is null then
        raise exception 'save_my_profile() needs a signed-in caller';
    end if;

    if v_first is null or v_last is null then
        raise exception 'A first name and a family name are needed';
    end if;

    -- The family name last, which is how a name is written on screen here.
    -- `full_name` stays the one field every existing screen reads, so it is
    -- assembled rather than left to drift out of step with its parts.
    v_full := btrim(concat_ws(' ', v_first, v_mid, v_last));

    -- A number already on somebody else's account is a mistyped digit far
    -- more often than it is a genuine collision, and the unique index would
    -- otherwise answer with a constraint name.
    if v_phone is not null and exists (
        select 1 from profiles where phone = v_phone and id <> v_actor
    ) then
        raise exception 'Ce numéro est déjà utilisé par un autre compte.';
    end if;

    update profiles set
        first_name    = v_first,
        middle_name   = v_mid,
        last_name     = v_last,
        full_name     = v_full,
        date_of_birth = coalesce(p_date_of_birth, date_of_birth),
        title         = coalesce(nullif(btrim(coalesce(p_title, '')), ''), title),
        phone         = coalesce(v_phone, phone)
    where id = v_actor;

    update profiles
       set profile_completed_at = coalesce(profile_completed_at, now())
     where id = v_actor and profile_is_complete(v_actor);

    return v_actor;
end;
$$;

-- ------------------------------------------------------------
-- 2. THE CODE A MANAGER SENDS
-- ------------------------------------------------------------
-- 005 built invitations and the app made the *invitee* find them: a menu
-- entry called "J'ai un code" that assumed somebody had already been given
-- one, by some means the app knew nothing about. That is backwards. The
-- person with the app open is the manager, and the person without it is the
-- one who needs to be reached.
--
-- So the generating side gets a function that returns everything needed to
-- send an invitation over WhatsApp — which is where these conversations
-- actually happen — and the app builds a message around it.

alter table pending_invitations add column if not exists title text;
alter table pending_invitations add column if not exists full_name text;
alter table pending_invitations add column if not exists note text;

comment on column pending_invitations.full_name is
    'Who the manager thinks they are inviting. Pre-fills the sign-up form; never overrides what the person then types about themselves.';

-- Issues an invitation and hands back the code plus the name of the business,
-- so the app can compose the message without a second round trip.
--
-- Security definer because it writes on behalf of the caller and checks the
-- same thing 005's insert policy checks. The refusal is a sentence rather
-- than a policy violation, which is what the sharing sheet shows.
create or replace function invite_employee(
    p_org_id     uuid,
    p_role       role_name default 'employee',
    p_full_name  text default null,
    p_title      text default null,
    p_phone      text default null,
    p_visibility text default 'full',
    p_valid_days int  default 14,
    p_note       text default null
)
returns table (
    invitation_id uuid,
    code          text,
    org_name      text,
    expires_at    timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
    v_id    uuid;
begin
    if v_actor is null then
        raise exception 'invite_employee() needs a signed-in caller';
    end if;

    if not is_org_admin(p_org_id) then
        raise exception 'You cannot invite people to this business';
    end if;

    insert into pending_invitations (
        org_id, role, scope_kind, scope_id, visibility,
        code, phone, full_name, title, note, expires_at, created_by
    )
    values (
        p_org_id, p_role, 'org', p_org_id, coalesce(p_visibility, 'full'),
        new_invitation_code(),
        nullif(btrim(coalesce(p_phone, '')), ''),
        nullif(btrim(coalesce(p_full_name, '')), ''),
        nullif(btrim(coalesce(p_title, '')), ''),
        nullif(btrim(coalesce(p_note, '')), ''),
        now() + make_interval(days => greatest(coalesce(p_valid_days, 14), 1)),
        v_actor
    )
    returning id into v_id;

    return query
    select i.id, i.code, o.name, i.expires_at
    from pending_invitations i
    join orgs o on o.id = i.org_id
    where i.id = v_id;
end;
$$;

-- ------------------------------------------------------------
-- 2b. THE NUMBER SOMEBODY GAVE, AND THE NUMBER THEY SIGNED IN WITH
-- ------------------------------------------------------------
-- 005 pins an invitation to `auth.users.phone` — the number the account was
-- created with. That was the only number there was.
--
-- It is not any more. `save_my_profile()` above lets somebody set the number
-- they actually want to be reached on, and those two legitimately differ: an
-- account made with an email has no auth phone at all, and a second SIM is
-- normal here. A manager types the number their new employee gave them,
-- which is the profile one, and 005 then refuses the claim with "ce code a
-- été émis pour un autre numéro" — an error the employee cannot act on and
-- the manager cannot see.
--
-- So the check widens by exactly one number: an invitation pinned to a phone
-- is claimable by somebody for whom that is *either* their sign-in number or
-- the number on their profile. It stays a pin — a stranger holding the code
-- is still refused — and the only thing that changes is which of a person's
-- own numbers counts as theirs.
--
-- Everything else in both functions is 005's, unchanged.
create or replace function claim_invitation(p_code text)
returns uuid
language plpgsql
volatile
security definer
set search_path = public, auth
as $$
declare
    v_uid    uuid := auth.uid();
    v_phone  text;
    v_email  text;
    v_alt    text;
    v_inv    pending_invitations%rowtype;
    v_code   text := normalize_invitation_code(p_code);
begin
    if v_uid is null then
        raise exception 'Connectez-vous avant d''utiliser un code d''invitation.'
            using errcode = 'invalid_authorization_specification';
    end if;

    if not exists (select 1 from profiles where id = v_uid) then
        raise exception 'Ce compte n''est pas encore prêt. Réessayez dans un instant.';
    end if;

    select u.phone, u.email into v_phone, v_email from auth.users u where u.id = v_uid;
    select p.phone into v_alt from profiles p where p.id = v_uid;

    select * into v_inv
    from pending_invitations i
    where normalize_invitation_code(i.code) = v_code
    for update;

    if not found then
        raise exception 'Code inconnu. Vérifiez les caractères saisis.'
            using errcode = 'no_data_found';
    end if;

    if v_inv.claimed_at is not null then
        if v_inv.claimed_by = v_uid then
            return v_inv.org_id;
        end if;
        raise exception 'Ce code a déjà été utilisé.'
            using errcode = 'no_data_found';
    end if;

    if v_inv.expires_at <= now() then
        raise exception 'Ce code a expiré. Demandez-en un nouveau.'
            using errcode = 'no_data_found';
    end if;

    -- Either of their own numbers. See the note above.
    if v_inv.phone is not null
       and v_inv.phone is distinct from v_phone
       and v_inv.phone is distinct from v_alt then
        raise exception 'Ce code a été émis pour un autre numéro de téléphone.'
            using errcode = 'insufficient_privilege';
    end if;

    if v_inv.email is not null and lower(v_inv.email) is distinct from lower(v_email) then
        raise exception 'Ce code a été émis pour une autre adresse e-mail.'
            using errcode = 'insufficient_privilege';
    end if;

    insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
    values (v_inv.org_id, v_uid, v_inv.role, v_inv.scope_kind, v_inv.scope_id, v_inv.visibility)
    on conflict (user_id, scope_kind, scope_id, role) do nothing;

    update pending_invitations
    set claimed_at = now(), claimed_by = v_uid
    where id = v_inv.id and claimed_at is null;

    return v_inv.org_id;
end;
$$;

-- The sign-in sweep, widened the same way and for the same reason: an
-- invitation written to the number somebody gave their manager should find
-- them when they appear, with nothing to type.
create or replace function claim_my_invitations()
returns int
language plpgsql
volatile
security definer
set search_path = public, auth
as $$
declare
    v_uid   uuid := auth.uid();
    v_phone text;
    v_email text;
    v_alt   text;
    v_count int := 0;
    v_inv   pending_invitations%rowtype;
begin
    if v_uid is null then
        return 0;
    end if;

    if not exists (select 1 from profiles where id = v_uid) then
        return 0;
    end if;

    select u.phone, u.email into v_phone, v_email from auth.users u where u.id = v_uid;
    select p.phone into v_alt from profiles p where p.id = v_uid;

    for v_inv in
        select * from pending_invitations i
        where i.claimed_at is null
          and i.expires_at > now()
          and (
              (v_phone is not null and i.phone = v_phone)
              or (v_alt is not null and i.phone = v_alt)
              or (v_email is not null and lower(i.email) = lower(v_email))
          )
        for update
    loop
        insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
        values (v_inv.org_id, v_uid, v_inv.role, v_inv.scope_kind,
                v_inv.scope_id, v_inv.visibility)
        on conflict (user_id, scope_kind, scope_id, role) do nothing;

        update pending_invitations
        set claimed_at = now(), claimed_by = v_uid
        where id = v_inv.id and claimed_at is null;

        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$$;

-- ------------------------------------------------------------
-- 3. A MANAGER ASKING FOR A BUSINESS
-- ------------------------------------------------------------
-- The other route in. `create_org()` stays platform admin only — whether a
-- new tenant appears on this platform is a decision, not a form submission —
-- and this is the queue that decision is made from.

create table if not exists org_applications (
    id            uuid primary key default gen_random_uuid(),
    applicant_id  uuid not null references profiles(id) on delete cascade,

    -- What they are asking for. Held here rather than in `orgs`, because
    -- until somebody approves it there is no business: no slug reserved, no
    -- books, nothing to sign into.
    name          text not null,
    slug          text not null,
    profile       text not null default 'generic',
    currency      text not null default 'XOF',

    -- Who they are and how to reach them, as they told it. Kept on the
    -- application rather than read from the profile at review time, so the
    -- reviewer sees what was actually submitted.
    contact_name  text,
    contact_phone text,
    contact_email text,
    description   text,

    status        text not null default 'pending'
                  check (status in ('pending', 'approved', 'rejected')),
    -- Filled by the reviewer. A rejection with no reason is one the applicant
    -- cannot act on, and they will simply apply again.
    decision_note text,
    reviewed_by   uuid references profiles(id) on delete set null,
    reviewed_at   timestamptz,

    -- Set on approval. The one link between an application and the business
    -- it became.
    org_id        uuid references orgs(id) on delete set null,

    created_at    timestamptz not null default now()
);

comment on table org_applications is
    'Somebody asking for a business to exist. Approving one calls create_org() and makes the applicant its owner.';

-- One open application per person. Somebody who applies four times while
-- waiting produces four things to review and one business.
create unique index if not exists org_applications_one_pending
    on org_applications (applicant_id) where status = 'pending';

create index if not exists org_applications_pending
    on org_applications (created_at desc) where status = 'pending';

alter table org_applications enable row level security;

-- An applicant sees their own; a platform admin sees all. Nobody else sees
-- anything: what businesses are being asked for is not a tenant's business.
drop policy if exists "applications readable by applicant and platform" on org_applications;
create policy "applications readable by applicant and platform"
on org_applications for select
using (
    applicant_id = auth.uid()
    or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
);

-- Written through apply_for_org() only, which is definer — but the policy is
-- what holds if somebody posts to the table directly, and it must not let
-- them file an application in somebody else's name or pre-approve it.
drop policy if exists "applications written by their applicant" on org_applications;
create policy "applications written by their applicant"
on org_applications for insert
with check (applicant_id = auth.uid() and status = 'pending');

-- Deciding is a platform act. No delete policy at all: a rejected
-- application is the record of a decision somebody made.
drop policy if exists "applications decided by platform admins" on org_applications;
create policy "applications decided by platform admins"
on org_applications for update
using (exists (select 1 from profiles where id = auth.uid() and is_platform_admin))
with check (exists (select 1 from profiles where id = auth.uid() and is_platform_admin));

create or replace function apply_for_org(
    p_name        text,
    p_slug        text,
    p_profile     text default 'generic',
    p_currency    text default 'XOF',
    p_description text default null,
    p_phone       text default null,
    p_email       text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor   uuid := auth.uid();
    v_name    text := nullif(btrim(coalesce(p_name, '')), '');
    v_slug    text := nullif(lower(btrim(coalesce(p_slug, ''))), '');
    v_problem text;
    v_id      uuid;
    v_full    text;
    v_phone   text;
begin
    if v_actor is null then
        raise exception 'apply_for_org() needs a signed-in caller';
    end if;

    if v_name is null then
        raise exception 'A business needs a name';
    end if;

    v_problem := org_slug_problem(v_slug);
    if v_problem is not null then
        raise exception '%', v_problem;
    end if;

    -- Checked now as well as at approval. Telling somebody their address is
    -- taken while they are filling the form in is worth far more than telling
    -- them a week later.
    if exists (select 1 from orgs where slug = v_slug) then
        raise exception 'That address is already taken.';
    end if;

    -- Who this is, as the platform will see it in the queue.
    select full_name, phone into v_full, v_phone from profiles where id = v_actor;

    insert into org_applications (
        applicant_id, name, slug, profile, currency,
        contact_name, contact_phone, contact_email, description
    )
    values (
        v_actor, v_name, v_slug,
        coalesce(nullif(btrim(coalesce(p_profile, '')), ''), 'generic'),
        coalesce(nullif(btrim(coalesce(p_currency, '')), ''), 'XOF'),
        v_full,
        coalesce(nullif(btrim(coalesce(p_phone, '')), ''), v_phone),
        nullif(btrim(coalesce(p_email, '')), ''),
        nullif(btrim(coalesce(p_description, '')), '')
    )
    -- Applying twice while waiting is a person pressing a button again, not a
    -- second business. The partial unique index makes it one row; this makes
    -- it one row without an error.
    on conflict (applicant_id) where status = 'pending'
    do update set
        name        = excluded.name,
        slug        = excluded.slug,
        profile     = excluded.profile,
        currency    = excluded.currency,
        description = excluded.description,
        created_at  = now()
    returning id into v_id;

    return v_id;
end;
$$;

-- Approving one: the business is created and the applicant owns it, in one
-- transaction. Nothing here trusts the application's own status column —
-- `for update` takes the row so two admins pressing approve at the same
-- moment cannot make two businesses.
create or replace function approve_org_application(
    p_application_id uuid,
    p_note           text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
    v_app   org_applications%rowtype;
    v_org   uuid;
begin
    if v_actor is null then
        raise exception 'approve_org_application() needs a signed-in caller';
    end if;

    if not exists (select 1 from profiles where id = v_actor and is_platform_admin) then
        raise exception 'Only a platform admin can approve a business';
    end if;

    select * into v_app from org_applications
    where id = p_application_id for update;
    if not found then
        raise exception 'No such application';
    end if;
    if v_app.status <> 'pending' then
        raise exception 'This application has already been %', v_app.status;
    end if;

    if exists (select 1 from orgs where slug = v_app.slug) then
        raise exception
            'The address % was taken while this was waiting. Ask them for another.',
            v_app.slug;
    end if;

    insert into orgs (name, slug, profile, default_currency)
    values (v_app.name, v_app.slug, v_app.profile, v_app.currency)
    returning id into v_org;

    -- The applicant owns it. This is the whole point of approving rather than
    -- creating: the business exists because they asked for it, so it is
    -- theirs and not the reviewer's.
    insert into memberships (org_id, user_id, role, scope_kind, scope_id)
    values (v_org, v_app.applicant_id, 'owner', 'org', v_org)
    on conflict do nothing;

    -- The same starter chart create_org() lays down, chosen by profile.
    if v_app.profile = 'church' then
        perform seed_church_accounts(v_org);
    elsif v_app.profile = 'retail' then
        perform seed_retail_accounts(v_org);
    elsif v_app.profile = 'farm' then
        perform seed_farm_accounts(v_org);
    else
        insert into accounts (org_id, code, name, type) values
            (v_org, '1000', 'Cash on Hand',      'asset'),
            (v_org, '1010', 'Bank Account',      'asset'),
            (v_org, '1020', 'Mobile Money',      'asset'),
            (v_org, '4000', 'Sales',             'income'),
            (v_org, '5000', 'Purchases',         'expense'),
            (v_org, '5010', 'Operating Expenses','expense')
        on conflict (org_id, code) do nothing;
    end if;

    update org_applications set
        status        = 'approved',
        decision_note = nullif(btrim(coalesce(p_note, '')), ''),
        reviewed_by   = v_actor,
        reviewed_at   = now(),
        org_id        = v_org
    where id = p_application_id;

    return v_org;
end;
$$;

create or replace function reject_org_application(
    p_application_id uuid,
    p_note           text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
begin
    if v_actor is null then
        raise exception 'reject_org_application() needs a signed-in caller';
    end if;

    if not exists (select 1 from profiles where id = v_actor and is_platform_admin) then
        raise exception 'Only a platform admin can decide an application';
    end if;

    -- A rejection with no reason is one the applicant cannot act on, so they
    -- apply again with the same details and the queue grows.
    if nullif(btrim(coalesce(p_note, '')), '') is null then
        raise exception 'Say why, so they can fix it and apply again';
    end if;

    update org_applications set
        status        = 'rejected',
        decision_note = btrim(p_note),
        reviewed_by   = v_actor,
        reviewed_at   = now()
    where id = p_application_id and status = 'pending';

    if not found then
        raise exception 'No pending application with that id';
    end if;

    return p_application_id;
end;
$$;

-- The queue, and one person's own application. Security definer with an
-- explicit check, because a summary observer of some unrelated business must
-- not be able to read the platform's pipeline through a policy gap.
create or replace function pending_org_applications()
returns table (
    id            uuid,
    applicant_id  uuid,
    applicant     text,
    name          text,
    slug          text,
    profile       text,
    currency      text,
    contact_phone text,
    contact_email text,
    description   text,
    created_at    timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    -- `pr.id`, not `id`: this function has an OUT column called `id`, and an
    -- unqualified one inside the body is the variable rather than the column.
    -- Postgres says so — "It could refer to either a PL/pgSQL variable or a
    -- table column" — but only at call time, so an unqualified reference here
    -- ships and fails in front of somebody.
    if not exists (
        select 1 from profiles pr where pr.id = auth.uid() and pr.is_platform_admin
    ) then
        raise exception 'Only a platform admin can read the applications';
    end if;

    return query
    select a.id, a.applicant_id, coalesce(a.contact_name, p.full_name),
           a.name, a.slug, a.profile, a.currency,
           a.contact_phone, a.contact_email, a.description, a.created_at
    from org_applications a
    left join profiles p on p.id = a.applicant_id
    where a.status = 'pending'
    order by a.created_at;
end;
$$;

-- What the applicant sees while they wait, and after. Their own row only.
--
-- Security definer, and not for reach: the `authenticated` role has no rights
-- in the auth schema, so an invoker function calling `auth.uid()` in its own
-- body fails with "permission denied for schema auth". (A policy may do it —
-- the quals are evaluated differently — which is why the select policy above
-- can.) The filter is the same one the policy makes, so definer grants
-- nothing the policy would not.
create or replace function my_org_application()
returns table (
    id            uuid,
    name          text,
    slug          text,
    profile       text,
    status        text,
    decision_note text,
    created_at    timestamptz,
    reviewed_at   timestamptz,
    org_id        uuid
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select a.id, a.name, a.slug, a.profile, a.status, a.decision_note,
           a.created_at, a.reviewed_at, a.org_id
    from org_applications a
    where a.applicant_id = auth.uid()
    order by a.created_at desc
    limit 1;
$$;

-- ------------------------------------------------------------
-- 4. GRANTS
-- ------------------------------------------------------------
revoke execute on function save_my_profile(text, text, text, date, text, text) from public;
revoke execute on function invite_employee(uuid, role_name, text, text, text, text, int, text) from public;
revoke execute on function apply_for_org(text, text, text, text, text, text, text) from public;
revoke execute on function approve_org_application(uuid, text) from public;
revoke execute on function reject_org_application(uuid, text) from public;
revoke execute on function pending_org_applications() from public;

-- `authenticated` is a Supabase role and does not exist on a bare Postgres,
-- which is what CI starts from. Roles are cluster-wide, so a developer whose
-- cluster has ever run a suite already has it and cannot reproduce the
-- failure by making a fresh database — which is how 013 shipped this wrong.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function save_my_profile(text, text, text, date, text, text) to authenticated;
        grant execute on function profile_is_complete(uuid) to authenticated;
        grant execute on function invite_employee(uuid, role_name, text, text, text, text, int, text) to authenticated;
        grant execute on function apply_for_org(text, text, text, text, text, text, text) to authenticated;
        grant execute on function approve_org_application(uuid, text) to authenticated;
        grant execute on function reject_org_application(uuid, text) to authenticated;
        grant execute on function pending_org_applications() to authenticated;
        grant execute on function my_org_application() to authenticated;
        grant select, insert on org_applications to authenticated;
        grant update on org_applications to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
