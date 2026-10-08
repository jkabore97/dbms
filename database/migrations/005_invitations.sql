-- ============================================================
-- 005_invitations.sql
--
-- Until now a membership had to be inserted by hand. This is the layer that
-- lets an admin do it from inside the app.
--
-- The shape is decided by who these users are. Most of them have a phone and
-- no email address, some have neither on the day they are invited, and the
-- person doing the inviting is often standing next to them. So an invitation
-- is a short code that can be read aloud, written on paper, or scanned off a
-- screen as a QR — and the claim is idempotent, because a person told to
-- "try it again" will try it again.
--
-- Three rules shape this file:
--
--   1. An invitation is a *promise of a membership*, never a membership. It
--      grants nothing until a signed-in user claims it, and claiming is the
--      only path from one to the other.
--   2. The claim runs SECURITY DEFINER because the claimer is, by definition,
--      not yet a member of the org and every policy in 004 would deny them.
--      It therefore validates everything itself: unclaimed, unexpired, and
--      addressed to this caller.
--   3. Claiming twice is not an error. `memberships` already carries
--      `unique (user_id, scope_kind, scope_id, role)`; this file leans on that
--      rather than hoping the client only calls once.
--
-- Depends on 004: is_org_admin(), and the profiles row that
-- handle_new_auth_user() creates on sign-up. Neither is rebuilt here.
-- ============================================================

-- ------------------------------------------------------------
-- 1. WHAT A CODE IS, ONCE A HUMAN HAS TYPED IT
-- ------------------------------------------------------------
-- Codes are stored and displayed as XXXX-XXXX, but they are read aloud down a
-- bad line and copied off a whiteboard, so they arrive with spaces, in
-- lowercase, and with or without the dash. Every comparison in this file goes
-- through here, on both sides, and the unique index below is built on it — so
-- "chor 2468" and "CHOR-2468" are the same code everywhere, including to the
-- constraint that stops two invitations sharing one.
create or replace function normalize_invitation_code(p_code text)
returns text
language sql
immutable
as $$
    select upper(regexp_replace(coalesce(p_code, ''), '[^a-zA-Z0-9]', '', 'g'));
$$;

-- ------------------------------------------------------------
-- 2. THE TABLE
-- ------------------------------------------------------------

create table if not exists pending_invitations (
    id uuid primary key default gen_random_uuid(),
    org_id uuid not null references orgs(id) on delete cascade,

    -- Exactly the grant the membership will carry, decided when the invitation
    -- is written and not renegotiable at claim time.
    role role_name not null,
    scope_kind scope_kind not null,
    scope_id uuid not null,
    visibility text not null default 'full',

    -- Short, human-readable, unique. Read aloud down a phone line or scanned
    -- as a QR; see new_invitation_code() for the alphabet and why. Uniqueness
    -- is enforced on the normalized form by the index below, not inline here.
    code text not null,

    -- Who it is for. Both may be null: an admin who has neither can still
    -- generate a code and hand it over in person, and the claimer is then
    -- whoever types it. At most one of them normally set.
    phone text,
    email text,

    expires_at timestamptz not null default now() + interval '14 days',
    created_by uuid not null references profiles(id),
    created_at timestamptz not null default now(),

    claimed_at timestamptz,
    claimed_by uuid references profiles(id),

    -- An org-scoped grant must point at the org itself, or the membership it
    -- becomes would be unreachable by every scope check in 004.
    constraint invitation_org_scope_points_at_org
        check (scope_kind <> 'org' or scope_id = org_id),

    -- claimed_at and claimed_by are written together, by claim_invitation()
    -- and nothing else. Either both or neither.
    constraint invitation_claim_is_whole
        check ((claimed_at is null) = (claimed_by is null))
);

-- Uniqueness and the by-code lookup, both on the normalized form. Not partial
-- on claimed_at: a spent code must stay reserved, or it could be minted again
-- and the audit trail would have two rows claiming to be the same code.
create unique index if not exists pending_invitations_code_key
    on pending_invitations (normalize_invitation_code(code));

-- The other lookup that happens on every claim: who the caller turned out to
-- be. Partial on unclaimed rows — the sweep only ever asks about open ones.
create index if not exists pending_invitations_open_phone_idx
    on pending_invitations (phone) where claimed_at is null and phone is not null;

create index if not exists pending_invitations_open_email_idx
    on pending_invitations (lower(email)) where claimed_at is null and email is not null;

-- What the admin people-screen lists.
create index if not exists pending_invitations_org_idx on pending_invitations (org_id, created_at desc);

-- ------------------------------------------------------------
-- 3. MINTING A CODE
-- ------------------------------------------------------------
-- Eight characters from a 32-symbol alphabet with 0/O and 1/I stripped out,
-- because these codes get read over a bad line and copied off a whiteboard.
-- Formatted XXXX-XXXX for the same reason. 32^8 is about 10^12: a code cannot
-- usefully be guessed, which matters because invitation_preview() below
-- answers to anyone.
create or replace function new_invitation_code()
returns text
language plpgsql
volatile
as $$
declare
    alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    v_code text;
    v_try  int := 0;
begin
    loop
        v_code := '';
        for i in 1..8 loop
            -- get_byte over pgcrypto's CSPRNG, not random(): a predictable
            -- invitation code is a predictable way into someone's books.
            v_code := v_code || substr(alphabet, (get_byte(gen_random_bytes(1), 0) % 32) + 1, 1);
        end loop;
        v_code := substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4);

        exit when not exists (
            select 1 from pending_invitations
            where normalize_invitation_code(code) = normalize_invitation_code(v_code)
        );

        v_try := v_try + 1;
        if v_try > 20 then
            raise exception 'could not allocate an unused invitation code';
        end if;
    end loop;
    return v_code;
end;
$$;

alter table pending_invitations alter column code set default new_invitation_code();

-- ------------------------------------------------------------
-- 4. CLAIMING
-- ------------------------------------------------------------
-- The one path from an invitation to a membership.
--
-- SECURITY DEFINER is not a convenience here, it is the whole point: the
-- caller is not a member of the org yet, so every policy in 004 denies them
-- both the invitation row and the membership insert. This function is
-- therefore the only code that may cross that line, and it re-checks by hand
-- everything RLS would otherwise have checked.
--
-- Idempotent in both halves:
--   * the invitation is won with a conditional UPDATE, so two racing calls
--     produce one winner and the loser falls through to the same membership;
--   * the membership insert is ON CONFLICT DO NOTHING against the existing
--     unique (user_id, scope_kind, scope_id, role).
--
-- Returns the org id on success. Raises on anything else, with a message the
-- app shows verbatim — these are read by the person holding the phone.
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
    v_inv    pending_invitations%rowtype;
    v_code   text := normalize_invitation_code(p_code);
begin
    if v_uid is null then
        raise exception 'Connectez-vous avant d''utiliser un code d''invitation.'
            using errcode = 'invalid_authorization_specification';
    end if;

    -- profiles is written by handle_new_auth_user() on sign-up (004). Without
    -- it there is nothing for memberships.user_id to point at.
    if not exists (select 1 from profiles where id = v_uid) then
        raise exception 'Ce compte n''est pas encore prêt. Réessayez dans un instant.';
    end if;

    select u.phone, u.email into v_phone, v_email from auth.users u where u.id = v_uid;

    select * into v_inv
    from pending_invitations i
    where normalize_invitation_code(i.code) = v_code
    for update;

    if not found then
        raise exception 'Code inconnu. Vérifiez les caractères saisis.'
            using errcode = 'no_data_found';
    end if;

    -- Already used. If this caller is the one who used it, say so quietly and
    -- hand back the same org — the second tap of a double-tap must not look
    -- like a failure. If it was someone else, it is spent.
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

    -- An invitation addressed to a phone or an email belongs to that person
    -- and to nobody else, however they came by the code. An invitation
    -- addressed to neither is a bearer token by design: that is the
    -- hand-it-over-in-person case, and the short code is the whole secret.
    if v_inv.phone is not null and v_inv.phone is distinct from v_phone then
        raise exception 'Ce code a été émis pour un autre numéro de téléphone.'
            using errcode = 'insufficient_privilege';
    end if;

    if v_inv.email is not null and lower(v_inv.email) is distinct from lower(v_email) then
        raise exception 'Ce code a été émis pour une autre adresse e-mail.'
            using errcode = 'insufficient_privilege';
    end if;

    -- The grant. ON CONFLICT covers the person who already holds exactly this
    -- role at exactly this scope — invited twice, or invited into something
    -- they were already given by hand.
    insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
    values (v_inv.org_id, v_uid, v_inv.role, v_inv.scope_kind, v_inv.scope_id, v_inv.visibility)
    on conflict (user_id, scope_kind, scope_id, role) do nothing;

    update pending_invitations
    set claimed_at = now(), claimed_by = v_uid
    where id = v_inv.id and claimed_at is null;

    return v_inv.org_id;
end;
$$;

-- Sign-in sweep: an invitation written to a phone number or an email address
-- is claimed the moment its owner appears, with nothing to type. The code
-- path above is for everyone else.
--
-- Returns the number of orgs newly joined, so the app knows whether to
-- re-run my_orgs().
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
    v_code  text;
    v_n     int := 0;
begin
    if v_uid is null then
        return 0;
    end if;

    if not exists (select 1 from profiles where id = v_uid) then
        return 0;
    end if;

    select u.phone, u.email into v_phone, v_email from auth.users u where u.id = v_uid;

    -- Deliberately narrow: a null phone must never match an invitation with a
    -- null phone, or every bearer code in the database would be swept up by
    -- the next person to sign in.
    for v_code in
        select i.code
        from pending_invitations i
        where i.claimed_at is null
          and i.expires_at > now()
          and (
                (v_phone is not null and i.phone = v_phone)
             or (v_email is not null and lower(i.email) = lower(v_email))
          )
    loop
        perform claim_invitation(v_code);
        v_n := v_n + 1;
    end loop;

    return v_n;
end;
$$;

-- ------------------------------------------------------------
-- 5. WHAT A STRANGER MAY SEE
-- ------------------------------------------------------------
-- Someone holding a code has not joined anything yet, so no policy on
-- pending_invitations will show them their own invitation. They still need to
-- see which business they are about to join, or "join" is a blind tap.
--
-- RLS is row-level and cannot hand back a subset of columns, so the narrowing
-- happens here instead: this returns the org's name and nothing else. Not the
-- org id, not the role, not who invited them, not whether the code has been
-- used — an unauthenticated caller learns only that some code names some
-- business.
create or replace function invitation_preview(p_code text)
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
    select o.name
    from pending_invitations i
    join orgs o on o.id = i.org_id
    where normalize_invitation_code(i.code) = normalize_invitation_code(p_code)
      and i.claimed_at is null
      and i.expires_at > now();
$$;

-- ------------------------------------------------------------
-- 6. RLS
-- ------------------------------------------------------------
-- Only an org's admins ever see or write its invitations. Everyone else goes
-- through the two SECURITY DEFINER functions above, which is why they check
-- what they check.

alter table pending_invitations enable row level security;

drop policy if exists "invitations readable by org admins" on pending_invitations;
create policy "invitations readable by org admins"
on pending_invitations for select
using (is_org_admin(org_id));

-- created_by is forced to the caller: an admin may not write an invitation
-- that appears to have come from someone else.
drop policy if exists "invitations issued by org admins" on pending_invitations;
create policy "invitations issued by org admins"
on pending_invitations for insert
with check (is_org_admin(org_id) and created_by = auth.uid());

-- Revoking. An admin may shorten the life of an unclaimed invitation or
-- delete it outright; a claimed one is a record of how somebody got in, and
-- the WHERE clause keeps it.
drop policy if exists "unclaimed invitations amended by org admins" on pending_invitations;
create policy "unclaimed invitations amended by org admins"
on pending_invitations for update
using (is_org_admin(org_id) and claimed_at is null)
with check (is_org_admin(org_id));

drop policy if exists "unclaimed invitations withdrawn by org admins" on pending_invitations;
create policy "unclaimed invitations withdrawn by org admins"
on pending_invitations for delete
using (is_org_admin(org_id) and claimed_at is null);

-- ------------------------------------------------------------
-- 7. GRANTS
-- ------------------------------------------------------------
-- Postgres grants EXECUTE on a new function to PUBLIC by default, which for a
-- SECURITY DEFINER function means "anyone with a connection", anon included.
-- That default is wrong for everything here except the preview, so it is
-- revoked first and handed back deliberately.
revoke execute on function claim_invitation(text) from public;
revoke execute on function claim_my_invitations() from public;
revoke execute on function new_invitation_code() from public;

-- invitation_preview() is the one thing an anonymous caller may run: the
-- claim screen names the business before asking anyone to sign in.
--
-- On plain Postgres these roles do not exist, so the grants are conditional
-- and CI stays green.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function invitation_preview(text) to anon;
    end if;

    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function invitation_preview(text) to authenticated;
        grant execute on function claim_invitation(text) to authenticated;
        grant execute on function claim_my_invitations() to authenticated;
        -- new_invitation_code() is the column default, so it runs as whoever
        -- is inserting: an admin issuing an invitation needs it.
        grant execute on function new_invitation_code() to authenticated;
        grant select, insert, update, delete on pending_invitations to authenticated;
    end if;
end $$;
