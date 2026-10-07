-- ============================================================
-- 103_admin_security.sql — the administration's doors, closed (a hotfix).
--
-- An audit of the live database at 100 found that a business's own admin
-- could write what only the platform writes, make themself rank above the
-- owner, and from there reset anybody's password. This closes it. It stands
-- on 100 alone (it needs nothing from 101 or 102) and keeps today's app
-- working: the app never writes orgs, memberships (but a delete) or
-- pending_invitations (but a delete) directly — each of those writes is a
-- SECURITY DEFINER function, which a revoked table privilege does not touch
-- (the one invoker function writing these tables, add_employee, writes
-- employees, not revoked here).
--
-- The owner's decisions: super_admin is a role a business can no longer
-- hand out — only the platform names one. The owner is the top of a
-- business for every business-side decision: where the money is paid, the
-- kind of business, the billing identity, the console, the salaries of
-- others, the team-access dial.
--
--   1. orgs: no client writes it directly any more (UPDATE, INSERT, DELETE
--      revoked; the admins' UPDATE policy dropped). Every change goes
--      through its function, which checks who asks: plan, suspension,
--      archive, Wave allowed, showcase, photo slots, verification,
--      referral, setup, lock policy and the address (org_slug_problem)
--      can no longer be PATCHed.
--   2. memberships: INSERT and UPDATE revoked from clients (only the claims,
--      create_org, an application approved, assign_trainer, a showcase
--      joined and set_membership_role write them, all definer). The roles
--      trigger refuses, for anyone but the platform, a super_admin named or
--      unnamed and a row moved to another person or business. A delete
--      (kept for today's app) is checked by a new trigger: never an owner,
--      never a trainer, never someone the caller does not outrank (their
--      own grant aside). revoke_membership(id) is the app's door from now.
--   3. pending_invitations: INSERT and UPDATE revoked (invite_employee is
--      the door). An invitation is for a role below the inviter's, never
--      super_admin — in invite_employee and in the seat trigger, so a
--      direct write refuses it too.
--   4. manages_user (the Worker's password reset, admin_save_member_profile,
--      can_delete_user): never a platform admin, never an owner anywhere
--      (the platform excepted), never a trainer; the shared business must
--      be one the target belongs to as a real member. can_delete_user never
--      a platform admin either.
--   5. revoke_membership(id): see 2.
--   6. sign_out_member: the caller must manage the person (manages_user).
--   7. claim_my_invitations (the sign-in sweep, no code): a number or an
--      address counts only when the sign-in has verified it
--      (auth.users.phone_confirmed_at / email_confirmed_at) — profiles.phone
--      is something anybody types, so it no longer claims an invitation by
--      itself. With a code, claim_invitation still accepts the profile's
--      number (the code is the secret). A client can no longer write
--      profiles.phone directly (save_my_profile, which checks, still does).
--   8. The console (audit_log_page, audit_log_actors, org_database_overview,
--      org_table_columns, the audit_log policy): the owner or a super_admin
--      (the platform). The platform's own people show as « Mara », never by
--      id. audit_log is read through those functions only.
--   9. Salaries: set_member_salary — never one's own; the owner sets anyone
--      else's, another admin only someone they outrank (never an owner's).
--      team_overview shows a salary to the owner, to the platform, to the
--      person themself, or to someone who outranks them.
--  10. profiles: one's own row, or — for an admin of a business the person
--      belongs to — theirs. A colleague who is not an admin no longer reads
--      another's phone, birth date or platform flag. The three lists that
--      named a colleague by joining profiles as the caller (recent_sales,
--      recent_deliveries, org_documents_core) name them through
--      colleague_name(), so a cashier still sees who sold.
--  11. admin_save_member_profile: through manages_user (4) — never an
--      owner's profile.
--  12. Money and kind: set_wave_payout_number, set_org_wave (the payment
--      handle), update_org's profile (the kind of business) and the billing
--      identity in set_org_billing (e-mail, tax id and label, footer) are
--      the owner's (and the platform's). A save that leaves them as they
--      are still passes for an admin — today's settings form sends them
--      back unchanged with the rest. The owner is told when somebody else
--      changes the payout or the kind.
--  13. org_private_details(org): the payout number and the platform's Wave
--      id (to the owner and the platform) and the plan with its note (the
--      note to the platform only), for the app to read instead of the
--      columns. The columns themselves stay readable to members for now:
--      narrowing orgs to column grants would break today's settings screen
--      and hide every column a later migration adds (102 adds one) until it
--      grants it. That narrowing follows once the new app reads this.
--  14. The team-access dial (org_feature_rules): written by the owner (or
--      the platform) only.
--  15. set_membership_role: answers in French, refuses super_admin (the
--      platform's) and a trainer's grant.
--  Hardening: TRUNCATE (which no policy governs) revoked from the app's
--  roles on every table, now and for tables created later.
--
-- Every kind of business — shop, farm, association (and legacy church) —
-- has a team, a console, settings and invitations, so every item applies
-- to all three alike.
--
-- Re-runnable: functions replaced in place, policies and triggers dropped
-- and recreated, grants idempotent.
-- ============================================================

-- ------------------------------------------------------------
-- 0. Helpers (internal: called by the functions and triggers below)
-- ------------------------------------------------------------

-- The caller's highest rank in one business, trainers' grants aside.
create or replace function org_rank_of(p_org_id uuid, p_user_id uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(max(role_rank(m.role)), 0)
      from memberships m
     where m.org_id = p_org_id and m.user_id = p_user_id and not m.is_trainer;
$$;

create or replace function caller_is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select exists (select 1 from profiles where id = auth.uid() and is_platform_admin);
$$;

-- The owner of this business, or the platform.
create or replace function is_org_owner(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select caller_is_platform_admin()
        or exists (select 1 from memberships m
                    where m.org_id = p_org_id and m.user_id = auth.uid()
                      and m.role = 'owner');
$$;

-- The owner, a super_admin, or the platform: the console's readers.
create or replace function is_org_head(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select caller_is_platform_admin()
        or exists (select 1 from memberships m
                    where m.org_id = p_org_id and m.user_id = auth.uid()
                      and m.role in ('owner', 'super_admin'));
$$;

-- The owners of a business told something, the one who did it excepted.
create or replace function notify_org_owners(
    p_org_id uuid, p_kind text, p_message text, p_params jsonb default '{}'::jsonb)
returns void
language sql
security definer
set search_path = public, auth
as $$
    insert into notifications (recipient_id, org_id, kind, message, params)
    select distinct m.user_id, p_org_id, p_kind, p_message,
           jsonb_build_object('to', 'shop') || coalesce(p_params, '{}'::jsonb)
      from memberships m
     where m.org_id = p_org_id and m.role = 'owner'
       and m.user_id is distinct from auth.uid();
$$;

-- ------------------------------------------------------------
-- 1. orgs: written only through its functions
-- ------------------------------------------------------------
drop policy if exists "orgs editable by their admins" on orgs;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke insert, update, delete, truncate on orgs from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke insert, update, delete, truncate on orgs from anon;
    end if;
end $$;

-- ------------------------------------------------------------
-- 2. memberships: no direct grant, no promotion, a checked removal
-- ------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke insert, update, truncate on memberships from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke insert, update, delete, truncate on memberships from anon;
    end if;
end $$;

-- 100's trigger, and: super_admin is named and unnamed by the platform
-- only; a grant never moves to another person or business.
create or replace function trg_membership_roles()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return new;
    end if;
    if (tg_op = 'INSERT' and coalesce(new.is_trainer, false))
       or (tg_op = 'UPDATE' and new.is_trainer is distinct from old.is_trainer) then
        raise exception 'Seule la plateforme nomme une formatrice ou un formateur'
            using errcode = 'insufficient_privilege';
    end if;
    if tg_op = 'UPDATE'
       and (new.user_id is distinct from old.user_id
            or new.org_id is distinct from old.org_id) then
        raise exception 'Un accès ne passe pas à une autre personne ni à une autre entreprise'
            using errcode = 'insufficient_privilege';
    end if;
    if tg_op = 'UPDATE' and old.role = 'owner'
       and new.role is distinct from old.role then
        raise exception 'Le propriétaire ne se change pas ici'
            using errcode = 'insufficient_privilege';
    end if;
    if (new.role = 'super_admin' and (tg_op = 'INSERT' or old.role is distinct from 'super_admin'))
       or (tg_op = 'UPDATE' and old.role = 'super_admin' and new.role is distinct from old.role) then
        raise exception 'Seule la plateforme nomme ou retire un super administrateur'
            using errcode = 'insufficient_privilege';
    end if;
    if new.role = 'owner' and (tg_op = 'INSERT' or old.role is distinct from 'owner')
       and exists (select 1 from memberships m
                    where m.org_id = new.org_id and m.role = 'owner' and m.id <> new.id) then
        raise exception 'Seule la plateforme nomme un propriétaire'
            using errcode = 'insufficient_privilege';
    end if;
    return new;
end;
$$;

-- A removal: never the owner, never a trainer (the platform's), never
-- someone the caller does not outrank in that business — their own grant
-- aside. The platform, a business being deleted (the cascade finds its
-- row already gone) and an account deleted by the service (no caller) pass.
create or replace function trg_membership_revoke()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
       or not exists (select 1 from orgs where id = old.org_id) then
        return old;
    end if;
    if old.is_trainer then
        raise exception 'Seule la plateforme retire une formatrice ou un formateur'
            using errcode = 'insufficient_privilege';
    end if;
    if old.role = 'owner' then
        raise exception 'Le propriétaire ne se retire pas de son entreprise'
            using errcode = 'insufficient_privilege';
    end if;
    if old.user_id = auth.uid() then
        return old;
    end if;
    if org_rank_of(old.org_id, auth.uid()) <= role_rank(old.role) then
        raise exception 'Vous ne pouvez retirer que quelqu''un en dessous de vous'
            using errcode = 'insufficient_privilege';
    end if;
    return old;
end;
$$;

drop trigger if exists membership_revoke on memberships;
create trigger membership_revoke
    before delete on memberships
    for each row execute function trg_membership_revoke();

-- The app's door for a removal (today's app deletes the row; the trigger
-- above holds either way). Revoking a grant, not deleting a person.
create or replace function revoke_membership(p_membership_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org uuid;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    select org_id into v_org from memberships where id = p_membership_id;
    if v_org is null then
        raise exception 'Cet accès n''existe plus';
    end if;
    if not is_org_admin(v_org) then
        raise exception 'Seul un administrateur retire un accès';
    end if;
    delete from memberships where id = p_membership_id;
end;
$$;

-- 044/045's set_membership_role, in French, and never super_admin or a
-- trainer's grant (the platform's).
create or replace function set_membership_role(p_membership_id uuid, p_role role_name)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org      uuid;
    v_role     role_name;
    v_trainer  boolean;
    v_user     uuid;
    v_platform boolean := caller_is_platform_admin();
    v_rank     int;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;

    select org_id, role, is_trainer, user_id into v_org, v_role, v_trainer, v_user
      from memberships where id = p_membership_id;
    if v_org is null then
        raise exception 'Cet accès n''existe plus';
    end if;

    if not is_org_admin(v_org) then
        raise exception 'Seul un administrateur change une responsabilité';
    end if;
    if v_role = 'owner' then
        raise exception 'La responsabilité du propriétaire ne se change pas ici';
    end if;
    if p_role = 'owner' then
        raise exception 'Le propriétaire se transmet par la plateforme, pas par un changement de responsabilité';
    end if;
    if not v_platform then
        if v_trainer then
            raise exception 'L''accès d''une formatrice ou d''un formateur est celui de la plateforme';
        end if;
        if p_role = 'super_admin' or v_role = 'super_admin' then
            raise exception 'Seule la plateforme nomme ou retire un super administrateur';
        end if;
        if v_user = auth.uid() then
            raise exception 'Votre propre responsabilité se change par quelqu''un au-dessus de vous';
        end if;
        v_rank := org_rank_of(v_org, auth.uid());
        if v_rank <= role_rank(v_role) or v_rank <= role_rank(p_role) then
            raise exception 'Vous ne pouvez donner qu''une responsabilité en dessous de la vôtre';
        end if;
    end if;

    update memberships set role = p_role where id = p_membership_id;
end;
$$;

-- ------------------------------------------------------------
-- 3. pending_invitations: through invite_employee, for a lower role
-- ------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke insert, update, truncate on pending_invitations from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke insert, update, delete, truncate on pending_invitations from anon;
    end if;
end $$;

-- 100's seat trigger, and: never super_admin, and a role below the
-- inviter's (an invitation made or re-roled; a claim moves no role).
create or replace function trg_invitation_seat()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return new;
    end if;
    if new.role = 'owner' then
        raise exception 'Seule la plateforme nomme un propriétaire'
            using errcode = 'insufficient_privilege';
    end if;
    if tg_op = 'INSERT' or new.role is distinct from old.role then
        if new.role = 'super_admin' then
            raise exception 'Seule la plateforme nomme un super administrateur'
                using errcode = 'insufficient_privilege';
        end if;
        if org_rank_of(new.org_id, auth.uid()) <= role_rank(new.role) then
            raise exception 'Vous ne pouvez inviter que pour une responsabilité en dessous de la vôtre'
                using errcode = 'insufficient_privilege';
        end if;
    end if;
    if tg_op = 'UPDATE' then
        return new;
    end if;
    if team_full(new.org_id)
       and not (new.phone is not null and exists (
                select 1 from memberships m
                  join profiles p on p.id = m.user_id
                  left join auth.users u on u.id = m.user_id
                 where m.org_id = new.org_id
                   and (p.phone = new.phone or u.phone = new.phone))) then
        raise exception '%', team_full_message(new.org_id);
    end if;
    return new;
end;
$$;

-- 017's invite_employee, in French, with the rank rule said before the
-- insert (the trigger holds it too). super_admin is refused even to the
-- platform here: the platform names one from the team (set_membership_role).
create or replace function invite_employee(
    p_org_id     uuid,
    p_role       role_name default 'employee',
    p_full_name  text default null,
    p_title      text default null,
    p_phone      text default null,
    p_visibility text default 'full',
    p_valid_days integer default 14,
    p_note       text default null
)
returns table (invitation_id uuid, code text, org_name text, expires_at timestamptz)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
    v_id    uuid;
begin
    if v_actor is null then
        raise exception 'Connectez-vous d''abord';
    end if;

    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur invite dans cette entreprise';
    end if;
    if p_role in ('owner', 'super_admin') then
        raise exception 'Cette responsabilité ne se donne pas par une invitation';
    end if;
    if not caller_is_platform_admin()
       and org_rank_of(p_org_id, v_actor) <= role_rank(p_role) then
        raise exception 'Vous ne pouvez inviter que pour une responsabilité en dessous de la vôtre';
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
-- 4. Who manages whom: never the platform, never an owner, never a trainer
-- ------------------------------------------------------------
create or replace function manages_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select case
        when auth.uid() is null or p_user_id is null or p_user_id = auth.uid() then false
        -- The platform's own people are managed by nobody from here.
        when exists (select 1 from profiles where id = p_user_id and is_platform_admin) then false
        when caller_is_platform_admin() then true
        -- The owner is the top of a business, and an owner anywhere is
        -- nobody's to reset from another business either.
        when exists (select 1 from memberships where user_id = p_user_id and role = 'owner') then false
        when exists (select 1 from profiles where id = p_user_id and is_trainer) then false
        else exists (
            select 1
              from memberships me
             where me.user_id = auth.uid()
               and not me.is_trainer
               and me.role in ('owner', 'super_admin', 'admin')
               and me.org_id in (select t.org_id from memberships t
                                  where t.user_id = p_user_id and not t.is_trainer)
               and role_rank(me.role) > (
                   select coalesce(max(role_rank(t.role)), 0)
                     from memberships t where t.user_id = p_user_id))
    end;
$$;

-- 044's, and never a platform admin.
create or replace function can_delete_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        p_user_id <> auth.uid()
        and not exists (select 1 from profiles where id = p_user_id and is_platform_admin)
        and not exists (
            select 1 from memberships where user_id = p_user_id and role = 'owner'
        )
        and (
            caller_is_platform_admin()
            or (
                manages_user(p_user_id)
                and not exists (
                    select 1 from memberships t
                    where t.user_id = p_user_id
                      and not is_org_admin(t.org_id)
                )
            )
        );
$$;

-- ------------------------------------------------------------
-- 6. Signing a member out: someone the caller manages
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
                    where org_id = p_org_id and user_id = p_user_id and not is_trainer) then
        raise exception 'Cette personne n''est pas membre de l''entreprise';
    end if;
    if exists (select 1 from memberships
                where user_id = p_user_id and org_id = p_org_id
                  and role in ('owner', 'super_admin')) then
        raise exception 'Le propriétaire ne peut pas être déconnecté par un autre';
    end if;
    if not manages_user(p_user_id) then
        raise exception 'Vous ne pouvez déconnecter que quelqu''un en dessous de vous';
    end if;
    execute 'de' || 'lete from auth.sessions where user_id = $1' using p_user_id;
    get diagnostics v_rows = row_count;
    perform security_log(p_user_id, 'signed_out_by_admin',
        (select name from orgs where id = p_org_id));
    return v_rows;
end;
$$;

-- ------------------------------------------------------------
-- 7. The sign-in sweep: only what the sign-in verified
-- ------------------------------------------------------------
create or replace function claim_my_invitations()
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_uid   uuid := auth.uid();
    v_phone text;
    v_email text;
    v_count int := 0;
    v_inv   pending_invitations%rowtype;
begin
    if v_uid is null then
        return 0;
    end if;

    if not exists (select 1 from profiles where id = v_uid) then
        return 0;
    end if;

    -- A number or an address the sign-in proved. profiles.phone is typed
    -- by the person and proves nothing; with a code, claim_invitation
    -- still takes it.
    select case when u.phone_confirmed_at is not null then u.phone end,
           case when u.email_confirmed_at is not null then u.email end
      into v_phone, v_email
      from auth.users u where u.id = v_uid;

    for v_inv in
        select * from pending_invitations i
        where i.claimed_at is null
          and i.expires_at > now()
          and (
              (v_phone is not null and i.phone = v_phone)
              or (v_email is not null and lower(i.email) = lower(v_email))
          )
        for update
    loop
        begin
            insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
            values (v_inv.org_id, v_uid, v_inv.role, v_inv.scope_kind,
                    v_inv.scope_id, v_inv.visibility)
            on conflict (user_id, scope_kind, scope_id, role) do nothing;
        exception when raise_exception or insufficient_privilege then
            continue;  -- no seat, or a grant only the platform makes (100)
        end;

        update pending_invitations
        set claimed_at = now(), claimed_by = v_uid
        where id = v_inv.id and claimed_at is null;

        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$$;

-- The number on one's profile is set through save_my_profile (which
-- checks it), not by a direct write: it opens a code locked to a number.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke update (phone) on profiles from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke update (phone) on profiles from anon;
    end if;
end $$;

-- ------------------------------------------------------------
-- 8. The console: the owner, a super_admin, the platform
-- ------------------------------------------------------------
drop policy if exists "audit log readable by org admins" on audit_log;
drop policy if exists "audit log readable by the owner" on audit_log;
create policy "audit log readable by the owner"
on audit_log for select
using (exists (select 1 from memberships m
                where m.org_id = audit_log.org_id and m.user_id = auth.uid()
                  and m.role in ('owner', 'super_admin'))
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin));

-- Read through the functions below, which name the platform's people
-- « Mara »; never as rows.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on audit_log from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on audit_log from anon;
    end if;
end $$;

create or replace function audit_log_page(
    p_org_id  uuid,
    p_limit   int    default 50,
    p_before  bigint default null,
    p_table   text   default null,
    p_actor   uuid   default null,
    p_action  text   default null
)
returns table (
    id          bigint,
    at          timestamptz,
    actor_id    uuid,
    actor_label text,
    action      text,
    table_name  text,
    row_id      uuid,
    summary     text,
    changed     jsonb
)
language sql
stable
security definer
set search_path = public, auth
as $$
    with me as (select caller_is_platform_admin() as platform)
    select l.id, l.at,
           case when pa.id is not null and not me.platform then null else l.actor_id end,
           case when pa.id is not null and not me.platform then 'Mara' else l.actor_label end,
           l.action, l.table_name, l.row_id, l.summary, l.changed
    from audit_log l
    cross join me
    left join profiles pa on pa.id = l.actor_id and pa.is_platform_admin
    where l.org_id = p_org_id
      and is_org_head(p_org_id)
      and (p_before is null or l.id < p_before)
      and (p_table  is null or l.table_name = p_table)
      and (p_actor  is null or l.actor_id = p_actor)
      and (p_action is null or l.action = p_action)
    order by l.id desc
    limit greatest(coalesce(p_limit, 50), 1);
$$;

create or replace function audit_log_actors(p_org_id uuid)
returns table (actor_id uuid, actor_label text, events bigint, last_seen timestamptz)
language sql
stable
security definer
set search_path = public, auth
as $$
    with me as (select caller_is_platform_admin() as platform),
    rows as (
        select case when pa.id is not null and not me.platform then null else l.actor_id end as actor_id,
               case when pa.id is not null and not me.platform then 'Mara' else l.actor_label end as actor_label,
               l.at
          from audit_log l
          cross join me
          left join profiles pa on pa.id = l.actor_id and pa.is_platform_admin
         where l.org_id = p_org_id
           and is_org_head(p_org_id)
    )
    select r.actor_id, max(r.actor_label), count(*), max(r.at)
      from rows r
     group by r.actor_id
     order by 4 desc;
$$;

create or replace function org_database_overview(p_org_id uuid)
returns table (
    table_name  text,
    label       text,
    purpose     text,
    row_count   bigint,
    last_change timestamptz
)
language sql
stable
security definer
set search_path = public, auth
as $$
    with allowed as (select is_org_head(p_org_id) as ok),
    counts(table_name, label, purpose, row_count) as (
        select 'orgs', 'Activité', 'La fiche de l''activité elle-même',
               (select count(*) from orgs o where o.id = p_org_id)
        union all
        select 'entities', 'Sites', 'Campus, fermes, boutiques',
               (select count(*) from entities e where e.org_id = p_org_id)
        union all
        select 'departments', 'Départements', 'Sous-unités d''un site',
               (select count(*) from departments d
                 join entities e on e.id = d.entity_id where e.org_id = p_org_id)
        union all
        select 'memberships', 'Accès', 'Qui détient quel rôle, et sur quoi',
               (select count(*) from memberships m where m.org_id = p_org_id)
        union all
        select 'pending_invitations', 'Invitations', 'Codes émis, utilisés ou expirés',
               (select count(*) from pending_invitations i where i.org_id = p_org_id)
        union all
        select 'accounts', 'Plan comptable', 'Les catégories dans lesquelles l''argent tombe',
               (select count(*) from accounts a where a.org_id = p_org_id)
        union all
        select 'journal_entries', 'Écritures', 'Chaque enregistrement, jamais modifié',
               (select count(*) from journal_entries je where je.org_id = p_org_id)
        union all
        select 'journal_lines', 'Lignes d''écriture', 'Les débits et crédits sous chaque écriture',
               (select count(*) from journal_lines jl
                 join journal_entries je on je.id = jl.journal_entry_id
                where je.org_id = p_org_id)
        union all
        select 'church_members', 'Fidèles', 'Les personnes à qui une offrande peut être attribuée',
               (select count(*) from church_members cm where cm.org_id = p_org_id)
        union all
        select 'contribution_attributions', 'Attributions', 'Quelle écriture appartient à quel fidèle',
               (select count(*) from contribution_attributions ca
                 join journal_entries je on je.id = ca.journal_entry_id
                where je.org_id = p_org_id)
        union all
        select 'documents', 'Pièces jointes', 'Photos et factures liées aux écritures',
               (select count(*) from documents doc where doc.org_id = p_org_id)
        union all
        select 'audit_log', 'Journal d''activité', 'Ce que chacun a modifié, et quand',
               (select count(*) from audit_log al where al.org_id = p_org_id)
    )
    select c.table_name, c.label, c.purpose, c.row_count,
           (select max(l.at) from audit_log l
             where l.org_id = p_org_id and l.table_name = c.table_name)
    from counts c cross join allowed a
    where a.ok
    order by c.table_name;
$$;

create or replace function org_table_columns(p_org_id uuid, p_table text)
returns table (
    column_name  text,
    data_type    text,
    is_nullable  boolean,
    has_default  boolean,
    is_key       boolean,
    references_table text
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        c.column_name::text,
        c.data_type::text,
        c.is_nullable = 'YES',
        c.column_default is not null,
        exists (
            select 1
            from information_schema.key_column_usage k
            join information_schema.table_constraints tc
              on tc.constraint_name = k.constraint_name
             and tc.constraint_schema = k.constraint_schema
            where tc.constraint_type = 'PRIMARY KEY'
              and k.table_schema = 'public'
              and k.table_name = c.table_name
              and k.column_name = c.column_name
        ),
        (
            select ccu.table_name::text
            from information_schema.key_column_usage k
            join information_schema.table_constraints tc
              on tc.constraint_name = k.constraint_name
             and tc.constraint_schema = k.constraint_schema
            join information_schema.constraint_column_usage ccu
              on ccu.constraint_name = tc.constraint_name
             and ccu.constraint_schema = tc.constraint_schema
            where tc.constraint_type = 'FOREIGN KEY'
              and k.table_schema = 'public'
              and k.table_name = c.table_name
              and k.column_name = c.column_name
            limit 1
        )
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = p_table
      and is_inspectable_table(p_table)
      and is_org_head(p_org_id)
    order by c.ordinal_position;
$$;

-- ------------------------------------------------------------
-- 9. Salaries: the owner's, and the ladder's below
-- ------------------------------------------------------------
create or replace function set_member_salary(
    p_org_id  uuid,
    p_user_id uuid,
    p_amount  numeric,
    p_period  text default 'month'
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_row    employees%rowtype;
    v_id     uuid;
    v_name   text;
    v_phone  text;
    v_amount numeric := coalesce(p_amount, 0);
    v_period text := coalesce(nullif(btrim(coalesce(p_period, '')), ''), 'month');
begin
    if auth.uid() is null or not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur note le salaire de l''équipe';
    end if;
    if not exists (select 1 from memberships
                    where org_id = p_org_id and user_id = p_user_id) then
        raise exception 'Cette personne n''est pas dans l''équipe';
    end if;
    -- Never one's own pay; the owner sets anyone else's; another admin only
    -- someone below them, and never an owner's.
    if p_user_id = auth.uid() then
        raise exception 'Votre propre salaire ne se note pas ici';
    end if;
    if not is_org_owner(p_org_id)
       and (exists (select 1 from memberships
                     where org_id = p_org_id and user_id = p_user_id and role = 'owner')
            or org_rank_of(p_org_id, auth.uid()) <= org_rank_of(p_org_id, p_user_id)) then
        raise exception 'Seul le propriétaire, ou quelqu''un au-dessus de cette personne, note son salaire';
    end if;
    if v_amount < 0 or v_amount > 1000000000 then
        raise exception 'Le salaire doit être un montant positif';
    end if;
    if v_period not in ('month', 'week', 'day') then
        raise exception 'Période inconnue : %', v_period;
    end if;

    select person_name(p_user_id), phone into v_name, v_phone
      from profiles where id = p_user_id;
    v_name := coalesce(v_name, 'Membre');

    select * into v_row from employees
     where org_id = p_org_id and user_id = p_user_id
     order by is_active desc, created_at limit 1;
    if v_row.id is null then
        select * into v_row from employees
         where org_id = p_org_id and user_id is null
           and lower(btrim(full_name)) = lower(btrim(v_name))
         order by is_active desc, created_at limit 1;
    end if;

    if v_row.id is null then
        if v_amount = 0 then
            return null;  -- nothing to clear
        end if;
        if exists (select 1 from employees
                    where org_id = p_org_id
                      and lower(btrim(full_name)) = lower(btrim(v_name))) then
            v_name := v_name || ' (' || coalesce(v_phone, left(p_user_id::text, 8)) || ')';
        end if;
        insert into employees (org_id, full_name, phone, kind, salary, pay_period,
                               user_id, created_by)
        values (p_org_id, v_name, v_phone, 'permanent', v_amount, v_period,
                p_user_id, auth.uid())
        returning id into v_id;
        return v_id;
    end if;

    if v_amount = 0 then
        if v_row.user_id is null then
            return null;
        end if;
        update employees
           set salary     = case when kind = 'permanent' then 0 else salary end,
               pay_period = case when kind = 'permanent' then null else pay_period end
         where id = v_row.id;
        return v_row.id;
    end if;

    if v_row.kind <> 'permanent' then
        raise exception 'Cette personne est payée à l''heure dans « Paie et journées » : son taux se change là-bas.';
    end if;

    update employees
       set user_id    = p_user_id,
           is_active  = true,
           ended_on   = null,
           end_reason = null,
           salary     = v_amount,
           pay_period = v_period
     where id = v_row.id;
    return v_row.id;
end;
$$;

-- 100's Équipe read; a salary is shown to the owner (and the platform), to
-- the person themself, and to someone above them — not to every admin.
create or replace function team_overview(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_full  boolean;
    v_owner boolean;
    v_rank  int;
begin
    if auth.uid() is null or not is_org_admin(p_org_id) then
        return null;
    end if;
    v_full  := team_full(p_org_id);
    v_owner := is_org_owner(p_org_id);
    v_rank  := org_rank_of(p_org_id, auth.uid());
    return jsonb_build_object(
        'seats', team_seats(p_org_id),
        'members', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'user_id', u.user_id,
                       'name', person_name(u.user_id),
                       'phone', p.phone,
                       'roles', to_jsonb(u.roles),
                       'owner', 'owner' = any (u.roles),
                       'me', u.user_id = auth.uid(),
                       'since', u.since,
                       'memberships', to_jsonb(u.ids),
                       'salary', case when s.ok and e.kind = 'permanent' and e.salary > 0 then e.salary end,
                       'period', case when s.ok and e.kind = 'permanent' and e.salary > 0
                                      then coalesce(e.pay_period, 'month') end,
                       'hourly', case when s.ok and e.kind = 'casual' and e.hourly_rate > 0
                                      then e.hourly_rate end,
                       'employee_id', case when s.ok then e.id end)
                   order by ('owner' = any (u.roles)) desc, lower(person_name(u.user_id)))
              from (select m.user_id,
                           array_agg(distinct m.role::text order by m.role::text) as roles,
                           array_agg(m.id order by m.created_at) as ids,
                           min(m.created_at) as since,
                           max(role_rank(m.role)) as rank
                      from memberships m
                     where m.org_id = p_org_id and not m.is_trainer
                     group by m.user_id) u
              join profiles p on p.id = u.user_id
              cross join lateral (
                  select v_owner
                      or u.user_id = auth.uid()
                      or (v_rank > u.rank and not ('owner' = any (u.roles))) as ok) s
              left join lateral (
                  select x.id, x.kind, x.salary, x.hourly_rate, x.pay_period from employees x
                   where x.org_id = p_org_id and x.user_id = u.user_id and x.is_active
                   order by x.created_at limit 1) e on true), '[]'::jsonb),
        'invitations', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'id', i.id, 'code', i.code, 'phone', i.phone,
                       'name', i.full_name, 'role', i.role,
                       'expires_at', i.expires_at,
                       'blocked', v_full and not (i.phone is not null and exists (
                           select 1 from memberships m
                             join profiles q on q.id = m.user_id
                             left join auth.users a on a.id = m.user_id
                            where m.org_id = p_org_id
                              and (q.phone = i.phone or a.phone = i.phone))))
                   order by i.created_at desc)
              from pending_invitations i
             where i.org_id = p_org_id and i.claimed_at is null
               and i.expires_at > now()), '[]'::jsonb),
        'org_name', (select name from orgs where id = p_org_id)
    );
end;
$$;

-- ------------------------------------------------------------
-- 10. profiles: one's own, or for an admin of a business they share
-- ------------------------------------------------------------
drop policy if exists "profiles readable to self and colleagues" on profiles;
drop policy if exists "profiles readable to self and their admins" on profiles;
create policy "profiles readable to self and their admins"
on profiles for select
using (id = auth.uid()
       or exists (select 1 from memberships m
                   where m.user_id = profiles.id
                     and m.org_id in (select my_org_ids())
                     and is_org_admin(m.org_id)));

-- A colleague's name and nothing else: what a list shows of who did it.
create or replace function colleague_name(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
    select p.full_name
      from profiles p
     where p.id = p_user_id
       and (p_user_id = auth.uid()
            or caller_is_platform_admin()
            or exists (select 1 from memberships a
                         join memberships b on b.org_id = a.org_id
                        where a.user_id = auth.uid() and b.user_id = p_user_id));
$$;

-- 042's, naming the seller through colleague_name().
create or replace function recent_sales(
    p_org_id uuid,
    p_limit  int default 50
)
returns table (
    id          uuid,
    kind        text,
    method      text,
    total       numeric,
    note        text,
    occurred_at timestamptz,
    sold_by     text,
    reversed    boolean
)
language sql
stable
security invoker
set search_path = public
as $$
    select s.id, s.kind, s.method, s.total, s.note, s.occurred_at,
           colleague_name(s.recorded_by),
           exists (select 1 from sales r where r.reverses_id = s.id)
    from sales s
    where s.org_id = p_org_id
      and s.kind <> 'return'
    order by s.occurred_at desc, s.id desc
    limit greatest(coalesce(p_limit, 50), 1);
$$;

create or replace function recent_deliveries(
    p_org_id uuid,
    p_limit  int default 50
)
returns table (
    id           uuid,
    product_id   uuid,
    product_name text,
    quantity     numeric,
    unit_cost    numeric,
    line_total   numeric,
    received_at  timestamptz,
    received_by  text,
    reversed     boolean
)
language sql
stable
security invoker
set search_path = public
as $$
    select r.id, r.product_id, p.name, r.quantity, r.unit_cost,
           r.quantity * r.unit_cost, r.received_at, colleague_name(r.received_by),
           r.reversed_at is not null
    from stock_receipts r
    join products p on p.id = r.product_id
    where r.org_id = p_org_id
    order by r.received_at desc, r.id desc
    limit greatest(coalesce(p_limit, 50), 1);
$$;

create or replace function org_documents_core(
    p_org_id uuid, p_kind text default null,
    p_limit int default 60, p_offset int default 0)
returns table (id uuid, r2_key text, kind text, caption text,
               content_type text, byte_size bigint, captured_at timestamptz,
               ocr_status text, ocr_text text, barcode text, product_id uuid,
               product_name text, entry_id uuid, entry_label text,
               uploaded_by uuid, uploaded_name text)
language sql
stable
security invoker
set search_path = public
as $$
    select d.id, d.r2_key, d.kind, d.caption, d.content_type, d.byte_size,
           coalesce(d.captured_at, d.created_at), d.ocr_status, d.ocr_text,
           d.barcode, d.product_id, p.name, d.linked_journal_entry_id, je.label,
           d.uploaded_by, colleague_name(d.uploaded_by)
    from documents d
    left join products p        on p.id  = d.product_id
    left join journal_entries je on je.id = d.linked_journal_entry_id
    where d.org_id = p_org_id
      and (p_kind is null or d.kind = p_kind)
    order by coalesce(d.captured_at, d.created_at) desc, d.id desc
    limit greatest(coalesce(p_limit, 60), 1)
    offset greatest(coalesce(p_offset, 0), 0);
$$;

-- ------------------------------------------------------------
-- 12. Where the money goes, and the kind of business: the owner's
-- ------------------------------------------------------------
create or replace function set_wave_payout_number(p_org_id uuid, p_number text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v   text := nullif(regexp_replace(coalesce(p_number, ''), '[^0-9+]', '', 'g'), '');
    v_old text;
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul le propriétaire choisit le numéro qui reçoit l''argent';
    end if;
    if v is not null and length(regexp_replace(v, '\D', '', 'g')) < 8 then
        raise exception 'Numéro Wave trop court';
    end if;
    if v is not null and left(v, 1) <> '+' then
        v := '+226' || right(v, 8);
    end if;
    select wave_payout_number into v_old from orgs where id = p_org_id;
    if v is not distinct from v_old then
        return;
    end if;
    if not is_org_owner(p_org_id) then
        raise exception 'Seul le propriétaire choisit le numéro qui reçoit l''argent';
    end if;
    update orgs set wave_payout_number = v where id = p_org_id;
    perform notify_org_owners(p_org_id, 'payout_changed',
        'Le numéro qui reçoit l''argent de vos ventes a été changé',
        jsonb_build_object('what', 'number'));
end;
$$;

create or replace function set_org_wave(
    p_org_id   uuid,
    p_merchant text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v     text := nullif(btrim(coalesce(p_merchant, '')), '');
    v_old text;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul le propriétaire change le compte Wave';
    end if;
    select wave_merchant into v_old from orgs where id = p_org_id;
    -- Today's settings form sends the handle back with every save.
    if v is not distinct from v_old then
        return;
    end if;
    if not is_org_owner(p_org_id) then
        raise exception 'Seul le propriétaire change le compte Wave';
    end if;
    update orgs set wave_merchant = v where id = p_org_id;
    perform notify_org_owners(p_org_id, 'payout_changed',
        'Le compte Wave de vos ventes a été changé',
        jsonb_build_object('what', 'wave'));
end;
$$;

-- 035's update_org; the kind of business is the owner's.
create or replace function update_org(
    p_org_id   uuid,
    p_name     text default null,
    p_slug     text default null,
    p_profile  text default null,
    p_currency text default null
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
    v_profile text := nullif(btrim(coalesce(p_profile, '')), '');
    v_problem text;
    v_old     text;
begin
    if v_actor is null then
        raise exception 'update_org() needs a signed-in caller';
    end if;

    if not is_org_admin(p_org_id) then
        raise exception 'You cannot change this business';
    end if;

    select profile::text into v_old from orgs where id = p_org_id;
    if not found then
        raise exception 'No such business';
    end if;

    if exists (select 1 from orgs where id = p_org_id and archived_at is not null) then
        raise exception 'This business is archived. Restore it before changing it.';
    end if;

    if v_slug is not null then
        v_problem := org_slug_problem(v_slug);
        if v_problem is not null then
            raise exception '%', v_problem;
        end if;
        if exists (select 1 from orgs where slug = v_slug and id <> p_org_id) then
            raise exception 'That address is already taken.';
        end if;
    end if;

    if v_profile is not null
       and v_profile not in ('church', 'association', 'farm', 'retail', 'generic') then
        raise exception 'Unknown profile: %', v_profile;
    end if;
    if v_profile is not null and v_profile is distinct from v_old then
        if not is_org_owner(p_org_id) then
            raise exception 'Seul le propriétaire change le genre d''activité';
        end if;
        perform notify_org_owners(p_org_id, 'org_kind_changed',
            'Le genre de votre activité a été changé',
            jsonb_build_object('profile', v_profile));
    end if;

    update orgs set
        name             = coalesce(v_name, name),
        slug             = coalesce(v_slug, slug),
        profile          = coalesce(v_profile, profile),
        default_currency = coalesce(nullif(btrim(coalesce(p_currency, '')), ''),
                                    default_currency)
    where id = p_org_id;

    return p_org_id;
end;
$$;

-- 020's set_org_billing; the phone and the address stay an admin's (the
-- vitrine's contact lines); the identity on the invoice is the owner's.
create or replace function set_org_billing(
    p_org_id         uuid,
    p_address        text default null,
    p_phone          text default null,
    p_email          text default null,
    p_tax_id         text default null,
    p_tax_label      text default null,
    p_invoice_footer text default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
    o       orgs%rowtype;
begin
    if v_actor is null then
        raise exception 'set_org_billing() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Only an administrator can change the billing details';
    end if;

    select * into o from orgs where id = p_org_id;
    if (nullif(btrim(coalesce(p_email, o.email, '')), '')                  is distinct from o.email
        or nullif(btrim(coalesce(p_tax_id, o.tax_id, '')), '')             is distinct from o.tax_id
        or nullif(btrim(coalesce(p_tax_label, o.tax_label, '')), '')       is distinct from o.tax_label
        or nullif(btrim(coalesce(p_invoice_footer, o.invoice_footer, '')), '') is distinct from o.invoice_footer)
       and not is_org_owner(p_org_id) then
        raise exception 'Seul le propriétaire change l''identité des factures (e-mail, numéro fiscal, pied de page)';
    end if;

    update orgs
       set address        = nullif(btrim(coalesce(p_address, address, '')), ''),
           phone          = nullif(btrim(coalesce(p_phone, phone, '')), ''),
           email          = nullif(btrim(coalesce(p_email, email, '')), ''),
           tax_id         = nullif(btrim(coalesce(p_tax_id, tax_id, '')), ''),
           tax_label      = nullif(btrim(coalesce(p_tax_label, tax_label, '')), ''),
           invoice_footer = nullif(btrim(coalesce(p_invoice_footer, invoice_footer, '')), '')
     where id = p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- 13. What a business keeps from its members
-- ------------------------------------------------------------
create or replace function org_private_details(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_owner    boolean;
    v_platform boolean := caller_is_platform_admin();
    o          orgs%rowtype;
begin
    if auth.uid() is null or not is_org_member(p_org_id) then
        return null;
    end if;
    v_owner := is_org_owner(p_org_id);
    select * into o from orgs where id = p_org_id;
    return jsonb_build_object(
        'wave_payout_number', case when v_owner then o.wave_payout_number end,
        'wave_merchant_ref',  case when v_owner then o.wave_merchant_ref end,
        'plan',               o.plan,
        'plan_until',         o.plan_until,
        'plan_note',          case when v_platform then o.plan_note end);
end;
$$;

-- ------------------------------------------------------------
-- 14. The team-access dial: the owner's
-- ------------------------------------------------------------
drop policy if exists "feature rules written by admins" on org_feature_rules;
drop policy if exists "feature rules written by the owner" on org_feature_rules;
create policy "feature rules written by the owner"
on org_feature_rules for all
using ((exists (select 1 from memberships m
                 where m.org_id = org_feature_rules.org_id and m.user_id = auth.uid()
                   and m.role = 'owner')
        or exists (select 1 from profiles where id = auth.uid() and is_platform_admin))
       and feature_access(org_id, 'team_access') = 'edit')
with check ((exists (select 1 from memberships m
                      where m.org_id = org_feature_rules.org_id and m.user_id = auth.uid()
                        and m.role = 'owner')
             or exists (select 1 from profiles where id = auth.uid() and is_platform_admin))
            and feature_access(org_id, 'team_access') = 'edit');

-- ------------------------------------------------------------
-- Hardening: TRUNCATE, which no policy governs
-- ------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke truncate on all tables in schema public from authenticated;
        alter default privileges in schema public revoke truncate on tables from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke truncate on all tables in schema public from anon;
        alter default privileges in schema public revoke truncate on tables from anon;
    end if;
end $$;

-- ------------------------------------------------------------
-- Grants (063: born closed to anon; said by name)
-- ------------------------------------------------------------
revoke execute on function org_rank_of(uuid, uuid)                 from public;
revoke execute on function caller_is_platform_admin()              from public;
revoke execute on function is_org_owner(uuid)                      from public;
revoke execute on function is_org_head(uuid)                       from public;
revoke execute on function notify_org_owners(uuid, text, text, jsonb)     from public;
revoke execute on function trg_membership_roles()                  from public;
revoke execute on function trg_membership_revoke()                 from public;
revoke execute on function trg_invitation_seat()                   from public;
revoke execute on function revoke_membership(uuid)                 from public;
revoke execute on function set_membership_role(uuid, role_name)    from public;
revoke execute on function invite_employee(uuid, role_name, text, text, text, text, integer, text) from public;
revoke execute on function manages_user(uuid)                      from public;
revoke execute on function can_delete_user(uuid)                   from public;
revoke execute on function sign_out_member(uuid, uuid)             from public;
revoke execute on function claim_my_invitations()                  from public;
revoke execute on function audit_log_page(uuid, int, bigint, text, uuid, text) from public;
revoke execute on function audit_log_actors(uuid)                  from public;
revoke execute on function org_database_overview(uuid)             from public;
revoke execute on function org_table_columns(uuid, text)           from public;
revoke execute on function set_member_salary(uuid, uuid, numeric, text) from public;
revoke execute on function team_overview(uuid)                     from public;
revoke execute on function colleague_name(uuid)                    from public;
revoke execute on function recent_sales(uuid, int)                 from public;
revoke execute on function recent_deliveries(uuid, int)            from public;
revoke execute on function org_documents_core(uuid, text, integer, integer) from public;
revoke execute on function set_wave_payout_number(uuid, text)      from public;
revoke execute on function set_org_wave(uuid, text)                from public;
revoke execute on function update_org(uuid, text, text, text, text) from public;
revoke execute on function set_org_billing(uuid, text, text, text, text, text, text) from public;
revoke execute on function org_private_details(uuid)               from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function org_rank_of(uuid, uuid)                 from anon;
        revoke execute on function caller_is_platform_admin()              from anon;
        revoke execute on function is_org_owner(uuid)                      from anon;
        revoke execute on function is_org_head(uuid)                       from anon;
        revoke execute on function notify_org_owners(uuid, text, text, jsonb)     from anon;
        revoke execute on function trg_membership_roles()                  from anon;
        revoke execute on function trg_membership_revoke()                 from anon;
        revoke execute on function trg_invitation_seat()                   from anon;
        revoke execute on function revoke_membership(uuid)                 from anon;
        revoke execute on function set_membership_role(uuid, role_name)    from anon;
        revoke execute on function invite_employee(uuid, role_name, text, text, text, text, integer, text) from anon;
        revoke execute on function manages_user(uuid)                      from anon;
        revoke execute on function can_delete_user(uuid)                   from anon;
        revoke execute on function sign_out_member(uuid, uuid)             from anon;
        revoke execute on function claim_my_invitations()                  from anon;
        revoke execute on function audit_log_page(uuid, int, bigint, text, uuid, text) from anon;
        revoke execute on function audit_log_actors(uuid)                  from anon;
        revoke execute on function org_database_overview(uuid)             from anon;
        revoke execute on function org_table_columns(uuid, text)           from anon;
        revoke execute on function set_member_salary(uuid, uuid, numeric, text) from anon;
        revoke execute on function team_overview(uuid)                     from anon;
        revoke execute on function colleague_name(uuid)                    from anon;
        revoke execute on function recent_sales(uuid, int)                 from anon;
        revoke execute on function recent_deliveries(uuid, int)            from anon;
        revoke execute on function org_documents_core(uuid, text, integer, integer) from anon;
        revoke execute on function set_wave_payout_number(uuid, text)      from anon;
        revoke execute on function set_org_wave(uuid, text)                from anon;
        revoke execute on function update_org(uuid, text, text, text, text) from anon;
        revoke execute on function set_org_billing(uuid, text, text, text, text, text, text) from anon;
        revoke execute on function org_private_details(uuid)               from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: called by the functions and triggers above, as their owner.
        revoke execute on function org_rank_of(uuid, uuid)                 from authenticated;
        revoke execute on function caller_is_platform_admin()              from authenticated;
        revoke execute on function is_org_owner(uuid)                      from authenticated;
        revoke execute on function is_org_head(uuid)                       from authenticated;
        revoke execute on function notify_org_owners(uuid, text, text, jsonb)     from authenticated;
        revoke execute on function trg_membership_roles()                  from authenticated;
        revoke execute on function trg_membership_revoke()                 from authenticated;
        revoke execute on function trg_invitation_seat()                   from authenticated;
        -- The app's doors; each checks who is asking. colleague_name is
        -- called as the caller by the three invoker lists.
        grant execute on function revoke_membership(uuid)                 to authenticated;
        grant execute on function set_membership_role(uuid, role_name)    to authenticated;
        grant execute on function invite_employee(uuid, role_name, text, text, text, text, integer, text) to authenticated;
        grant execute on function manages_user(uuid)                      to authenticated;
        grant execute on function can_delete_user(uuid)                   to authenticated;
        grant execute on function sign_out_member(uuid, uuid)             to authenticated;
        grant execute on function claim_my_invitations()                  to authenticated;
        grant execute on function audit_log_page(uuid, int, bigint, text, uuid, text) to authenticated;
        grant execute on function audit_log_actors(uuid)                  to authenticated;
        grant execute on function org_database_overview(uuid)             to authenticated;
        grant execute on function org_table_columns(uuid, text)           to authenticated;
        grant execute on function set_member_salary(uuid, uuid, numeric, text) to authenticated;
        grant execute on function team_overview(uuid)                     to authenticated;
        grant execute on function colleague_name(uuid)                    to authenticated;
        grant execute on function recent_sales(uuid, int)                 to authenticated;
        grant execute on function recent_deliveries(uuid, int)            to authenticated;
        grant execute on function org_documents_core(uuid, text, integer, integer) to authenticated;
        grant execute on function set_wave_payout_number(uuid, text)      to authenticated;
        grant execute on function set_org_wave(uuid, text)                to authenticated;
        grant execute on function update_org(uuid, text, text, text, text) to authenticated;
        grant execute on function set_org_billing(uuid, text, text, text, text, text, text) to authenticated;
        grant execute on function org_private_details(uuid)               to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
