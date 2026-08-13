-- ============================================================
-- 014_org_lifecycle.sql — changing a business, putting it away, and the one
-- act in this schema that actually destroys something.
--
-- `create_org()` has existed since 010 and there has never been a way to
-- undo it. A platform admin could make a business and then had to live with
-- the name they typed, the profile they picked, and every test business they
-- ever created, forever.
--
-- Four decisions, and the third is the one that matters.
--
-- 1. **Editing is not a new power.** 004 already lets an org's own admins
--    update their `orgs` row, and 010 already counts a platform admin as an
--    admin of every org. `update_org()` adds validation, not access: it
--    refuses a slug that would not survive as a hostname, refuses a profile
--    this build has never heard of, and refuses to rename an archived
--    business. Doing it through a function also means one audit_log row that
--    says what changed instead of a bare UPDATE.
--
-- 2. **Archiving is the ordinary way to make a business go away.** It is
--    reversible, it keeps every entry, and it is what "delete" should mean
--    nine times out of ten — the business closed, nobody should see it in
--    their list, and the books still have to exist because a tax office may
--    still ask. An archived org disappears from `my_orgs()` for its members
--    and stays visible to a platform admin, who is the only person who can
--    bring it back.
--
-- 3. **Deleting is permanent, destroys the books, and is deliberately hard.**
--    Everything in this schema is append-only on purpose: undo is a reversing
--    entry, a document cannot be deleted, the audit log has no delete policy.
--    `delete_org()` is the one exception, and it exists because a platform
--    admin genuinely does need to remove the business they created twice by
--    accident. So it is fenced:
--
--      - platform admin only, never an org's own owner;
--      - the business must already be archived, so deletion is never the
--        first thing that happens to it;
--      - the exact name has to be typed back, because a business id in a
--        confirmation dialog is not something anybody reads;
--      - and it refuses outright if the books hold anything at all, unless
--        the caller passes `p_force` — a test business with no entries can
--        go quietly, a real one takes a second, deliberate act.
--
-- 4. **A deleted business leaves a tombstone.** `audit_log.org_id` cascades,
--    so an org's own audit trail dies with it and the deletion would be the
--    one event in this system that erases its own record. `deleted_orgs` is
--    not org-scoped and nothing cascades into it: it keeps the name, the
--    slug, who deleted it, when, and what was in the books at the time.
--    Readable by platform admins, writable by nobody.
-- ============================================================

-- ------------------------------------------------------------
-- 1. ARCHIVED, NOT GONE
-- ------------------------------------------------------------

alter table orgs add column if not exists archived_at timestamptz;
alter table orgs add column if not exists archived_by uuid;

do $$
begin
    if not exists (
        select 1 from pg_constraint where conname = 'orgs_archived_by_fkey'
    ) then
        alter table orgs
            add constraint orgs_archived_by_fkey
            foreign key (archived_by) references profiles(id) on delete set null;
    end if;
end $$;

comment on column orgs.archived_at is
    'Set when a business is put away. It keeps every entry and disappears from my_orgs() for its members; a platform admin can still see it and restore it.';

create index if not exists orgs_active on orgs (id) where archived_at is null;

-- ------------------------------------------------------------
-- 2. THE TOMBSTONE
-- ------------------------------------------------------------
-- Deliberately not referencing orgs: the row it describes is gone. Nothing
-- cascades into this table and nothing may delete from it, which is the whole
-- point — otherwise deleting a business would also delete the record that it
-- was deleted.

create table if not exists deleted_orgs (
    id            uuid primary key,
    name          text not null,
    slug          text not null,
    profile       text,
    deleted_at    timestamptz not null default now(),
    deleted_by    uuid references profiles(id) on delete set null,
    deleted_label text,
    -- What was destroyed, counted at the moment of destruction. Somebody will
    -- ask, and by then there is nothing left to count.
    entry_count   int not null default 0,
    member_count  int not null default 0,
    created_at    timestamptz
);

comment on table deleted_orgs is
    'One row per business that was permanently deleted. Nothing cascades into it and nothing may delete from it: the record of a deletion must outlive the thing deleted.';

alter table deleted_orgs enable row level security;

-- Select only, and only for platform admins. No insert, update or delete
-- policy at all — the only writer is delete_org(), which is SECURITY DEFINER
-- and runs outside policy, exactly like the audit trigger in 008.
drop policy if exists "tombstones readable by platform admins" on deleted_orgs;
create policy "tombstones readable by platform admins"
on deleted_orgs for select
using (exists (select 1 from profiles where id = auth.uid() and is_platform_admin));

-- ------------------------------------------------------------
-- 2b. THE ONE TRIGGER THAT CANNOT COVER ITS OWN CASE
-- ------------------------------------------------------------
-- 008 puts a generic audit trigger on `orgs` for insert, update and delete.
-- The delete arm cannot work and never could: it fires AFTER the row is gone
-- and inserts `audit_log(org_id = <that id>)`, which fails the foreign key.
-- Nothing noticed because until now nothing deleted an org.
--
-- Making the column nullable for this one case would produce a log line that
-- belongs to no business, and `audit_log.org_id` cascades anyway — so even a
-- row that inserted cleanly would be deleted by the same statement that
-- created it. An audit trail cannot record its own erasure.
--
-- So `orgs` keeps its insert and update auditing and loses the delete arm,
-- and `deleted_orgs` above is where a deletion is recorded instead. That
-- table is not org-scoped and nothing cascades into it, which is the only
-- shape that survives.
drop trigger if exists audit_orgs on orgs;
create trigger audit_orgs
    after insert or update on orgs
    for each row execute function audit_row();

-- The same collision, one level down and worse: deleting an org cascades to
-- memberships, accounts, entities, departments, journal_entries,
-- church_members and pending_invitations — every one of them audited, every
-- one firing AFTER DELETE and inserting `audit_log(org_id = <the org just
-- deleted>)`. The cascade cannot complete.
--
-- The alternative to what follows was rewriting audit_row() here to skip a
-- vanishing org, which means carrying a hundred-line copy of 008's trigger in
-- this file and hoping the two never drift. Instead the foreign key is made
-- DEFERRABLE, and delete_org() defers it for its own transaction and sweeps
-- the doomed rows before committing. Nothing else in the schema changes
-- behaviour: the constraint is still INITIALLY IMMEDIATE, so every other
-- write is checked exactly when it was before.
do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'audit_log_org_id_fkey' and condeferrable
    ) then
        alter table audit_log drop constraint if exists audit_log_org_id_fkey;
        alter table audit_log
            add constraint audit_log_org_id_fkey
            foreign key (org_id) references orgs(id) on delete cascade
            deferrable initially immediate;
    end if;
end $$;

-- ------------------------------------------------------------
-- 3. WHAT A BUSINESS MAY BE CALLED
-- ------------------------------------------------------------
-- Shared by update_org() and worth having on its own: the app's Dart
-- `slugProblem()` makes the same checks so the button can be dead before
-- anything is sent, and two copies of a rule drift unless one of them is the
-- one that actually decides.

create or replace function org_slug_problem(p_slug text)
returns text
language sql
immutable
as $$
    select case
        when p_slug is null or btrim(p_slug) = ''
            then 'Une adresse est nécessaire.'
        when length(btrim(p_slug)) < 3
            then 'Trop court : au moins 3 caractères.'
        when length(btrim(p_slug)) > 63
            then 'Trop long : 63 caractères au maximum.'
        -- Lowercase letters, digits and single hyphens, not at either end.
        -- That is what survives as a subdomain, which is what a slug is for.
        when btrim(p_slug) !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
            then 'Lettres minuscules, chiffres et tirets seulement.'
        else null
    end;
$$;

-- ------------------------------------------------------------
-- 4. CHANGING ONE
-- ------------------------------------------------------------
-- Security definer for the same reason as record_entry(): so the refusal is
-- a sentence rather than "0 rows updated", which is what an RLS-blocked
-- UPDATE looks like from the app and is indistinguishable from success.
--
-- Null means "leave it alone" for every field. Passing one thing must not
-- blank the other four.
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
begin
    if v_actor is null then
        raise exception 'update_org() needs a signed-in caller';
    end if;

    -- is_org_admin() is true for an org's own owner/super_admin/admin and,
    -- since 010, for a platform admin of every org. Both are intended here:
    -- a business owner renaming their own shop is not an escalation.
    if not is_org_admin(p_org_id) then
        raise exception 'You cannot change this business';
    end if;

    if not exists (select 1 from orgs where id = p_org_id) then
        raise exception 'No such business';
    end if;

    -- An archived business is a closed one. Editing it would put a name on
    -- something nobody is looking at, and the restore is one call away.
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

    -- The profile decides which home screen opens. An unknown one lands
    -- everybody on the pending screen with no way back, so it is refused
    -- here rather than discovered by the person it happened to.
    if v_profile is not null and v_profile not in ('church', 'farm', 'retail', 'generic') then
        raise exception 'Unknown profile: %', v_profile;
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

-- ------------------------------------------------------------
-- 5. PUTTING ONE AWAY, AND GETTING IT BACK
-- ------------------------------------------------------------

create or replace function archive_org(p_org_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
begin
    if v_actor is null then
        raise exception 'archive_org() needs a signed-in caller';
    end if;

    -- Deliberately stricter than update_org(): archiving takes a business off
    -- every member's home screen at once, including people who are still
    -- using it. That is a platform-level act, not a shop-floor one.
    if not exists (select 1 from profiles where id = v_actor and is_platform_admin) then
        raise exception 'Only a platform admin can archive a business';
    end if;

    if not exists (select 1 from orgs where id = p_org_id) then
        raise exception 'No such business';
    end if;

    update orgs
       set archived_at = coalesce(archived_at, now()),
           archived_by = coalesce(archived_by, v_actor)
     where id = p_org_id;

    return p_org_id;
end;
$$;

create or replace function restore_org(p_org_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
begin
    if v_actor is null then
        raise exception 'restore_org() needs a signed-in caller';
    end if;

    if not exists (select 1 from profiles where id = v_actor and is_platform_admin) then
        raise exception 'Only a platform admin can restore a business';
    end if;

    update orgs set archived_at = null, archived_by = null where id = p_org_id;
    return p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- 6. DESTROYING ONE
-- ------------------------------------------------------------
-- The only call in this schema that loses data on purpose. Everything about
-- it is arranged so that it cannot happen by accident, and so that the fact
-- it happened survives it.

create or replace function delete_org(
    p_org_id       uuid,
    p_confirm_name text,
    p_force        boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor   uuid := auth.uid();
    v_org     orgs%rowtype;
    v_label   text;
    v_entries int;
    v_members int;
begin
    if v_actor is null then
        raise exception 'delete_org() needs a signed-in caller';
    end if;

    if not exists (select 1 from profiles where id = v_actor and is_platform_admin) then
        raise exception 'Only a platform admin can delete a business';
    end if;

    select * into v_org from orgs where id = p_org_id;
    if not found then
        raise exception 'No such business';
    end if;

    -- Never the first thing that happens to a business. Archiving is
    -- reversible and takes it off everyone's screen already, so anyone who
    -- reaches here has had a chance to change their mind.
    if v_org.archived_at is null then
        raise exception
            'Archive % first. Deleting is permanent and archiving is not.',
            v_org.name;
    end if;

    -- The name, typed back. A uuid in a confirmation dialog is not read by
    -- anybody; a name that has to be copied out is.
    if lower(btrim(coalesce(p_confirm_name, ''))) <> lower(btrim(v_org.name)) then
        raise exception
            'Type the name exactly to confirm: %', v_org.name;
    end if;

    select count(*) into v_entries from journal_entries where org_id = p_org_id;
    select count(*) into v_members from memberships    where org_id = p_org_id;

    -- A business nobody ever recorded anything in is a mistake to be swept
    -- up. A business with books is somebody's history, and destroying it
    -- takes a second, explicit act rather than the same click.
    if v_entries > 0 and not coalesce(p_force, false) then
        raise exception
            '% has % entries in its books. Deleting destroys them permanently.',
            v_org.name, v_entries;
    end if;

    select full_name into v_label from profiles where id = v_actor;

    -- Written before the delete, and outside the org's own scope, because
    -- audit_log.org_id cascades and would take this record with it.
    insert into deleted_orgs (
        id, name, slug, profile, deleted_by, deleted_label,
        entry_count, member_count, created_at
    )
    values (
        v_org.id, v_org.name, v_org.slug, v_org.profile, v_actor, v_label,
        v_entries, v_members, v_org.created_at
    )
    on conflict (id) do nothing;

    -- Every audited child table fires AFTER DELETE during the cascade below
    -- and writes an audit_log row pointing at an org that no longer exists.
    -- Deferring the key lets the cascade finish; the sweep afterwards removes
    -- those rows, so the check at commit finds nothing dangling. See the note
    -- beside the constraint above for why this is here rather than inside
    -- audit_row().
    set constraints audit_log_org_id_fkey deferred;

    -- Leaf-first, by hand, and this is not paranoia. Most org-scoped tables
    -- cascade from `orgs`, but plenty of the references *between* them are
    -- NO ACTION — journal_lines.account_id, sales.entry_id,
    -- staff_payments.employee_id, invoices.customer_id — and a cascade does
    -- not order itself by dependency, so it aborts halfway with a foreign key
    -- error and the business survives its own deletion.
    --
    -- The tempting fix is to make those keys cascade too. That would mean
    -- deleting an account silently destroys every ledger line posted to it,
    -- which is the guard those keys exist to provide and is worth far more
    -- than the convenience here. So the destruction is spelled out instead.
    --
    -- A new module with a new table belongs on this list. `test_org_lifecycle`
    -- deletes a business holding one of everything, so forgetting shows up as
    -- a failing suite rather than as a platform admin who cannot delete.
    delete from journal_lines jl using journal_entries je
        where jl.journal_entry_id = je.id and je.org_id = p_org_id;
    delete from contribution_attributions ca using journal_entries je
        where ca.journal_entry_id = je.id and je.org_id = p_org_id;
    delete from sale_lines sl using sales s
        where sl.sale_id = s.id and s.org_id = p_org_id;

    delete from staff_payments  where org_id = p_org_id;
    delete from shifts          where org_id = p_org_id;
    delete from employees       where org_id = p_org_id;

    -- invoice_payments, invoice_lines, flock_events and sale_lines carry no
    -- org_id of their own: they are reached through their parent, which is
    -- how they were written and is not worth changing here.
    delete from invoice_payments ip using invoices i
        where ip.invoice_id = i.id and i.org_id = p_org_id;
    delete from invoice_lines il using invoices i
        where il.invoice_id = i.id and i.org_id = p_org_id;
    delete from invoices        where org_id = p_org_id;
    delete from customers       where org_id = p_org_id;

    delete from egg_production  where org_id = p_org_id;
    delete from flock_events fe using flocks f
        where fe.flock_id = f.id and f.org_id = p_org_id;
    delete from flocks          where org_id = p_org_id;
    delete from stock_movements where org_id = p_org_id;
    delete from items           where org_id = p_org_id;

    delete from documents       where org_id = p_org_id;

    -- Self-referencing: a return points at the sale it reverses, and a
    -- reversing entry at the entry it reverses. Broken before the rows go,
    -- because a delete cannot order a table against itself either.
    update sales set reverses_id = null where org_id = p_org_id;
    delete from sales           where org_id = p_org_id;
    delete from products        where org_id = p_org_id;

    update journal_entries set reverses_entry_id = null where org_id = p_org_id;
    delete from journal_entries where org_id = p_org_id;
    delete from accounts        where org_id = p_org_id;
    delete from church_members  where org_id = p_org_id;

    -- What is left cascades cleanly: memberships, entities, departments,
    -- pending_invitations, audit_log.
    delete from orgs where id = p_org_id;

    -- The org's own audit trail was already cascaded away by the same
    -- statement; this clears what the cascade's own triggers wrote on the way
    -- out. Both are gone either way — which is the argument for the tombstone
    -- and not a shortcut around it.
    delete from audit_log where org_id = p_org_id;

    return p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- 7. WHAT A PLATFORM ADMIN SEES
-- ------------------------------------------------------------
-- my_orgs() answers "which businesses do I open"; this answers "what exists
-- on this platform, and how big is it". Separate because the second one has
-- to include archived businesses, and my_orgs() must not.

create or replace function all_orgs(p_include_archived boolean default true)
returns table (
    org_id       uuid,
    name         text,
    slug         text,
    profile      text,
    currency     text,
    archived_at  timestamptz,
    member_count int,
    entry_count  int,
    created_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can list every business';
    end if;

    return query
    select o.id, o.name, o.slug, o.profile, o.default_currency, o.archived_at,
           (select count(*)::int from memberships m    where m.org_id = o.id),
           (select count(*)::int from journal_entries j where j.org_id = o.id),
           o.created_at
    from orgs o
    where coalesce(p_include_archived, true) or o.archived_at is null
    order by o.archived_at nulls first, o.name;
end;
$$;

-- ------------------------------------------------------------
-- 8. ARCHIVED BUSINESSES LEAVE THE LIST
-- ------------------------------------------------------------
-- Redefined rather than patched: my_orgs() is what the app calls after
-- sign-in to decide which businesses a person can open, and an archived one
-- must not be among them. A platform admin still sees archived businesses,
-- because somebody has to be able to find one to restore it.

create or replace function my_orgs()
returns table (
    org_id           uuid,
    name             text,
    slug             text,
    profile          text,
    default_currency text,
    roles            text[],
    visibility       text
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        o.id, o.name, o.slug, o.profile, o.default_currency,
        array['platform_admin'::text],
        'full'::text
    from orgs o
    where exists(select 1 from profiles where id = auth.uid() and is_platform_admin)

    union all

    select
        o.id, o.name, o.slug, o.profile, o.default_currency,
        array_agg(distinct m.role::text order by m.role::text),
        case when bool_or(m.visibility = 'full') then 'full' else 'summary' end
    from memberships m
    join orgs o on o.id = m.org_id
    where m.user_id = auth.uid()
      and o.archived_at is null
      and not exists(select 1 from profiles where id = auth.uid() and is_platform_admin)
    group by o.id, o.name, o.slug, o.profile, o.default_currency

    order by name;
$$;

-- ------------------------------------------------------------
-- 9. GRANTS
-- ------------------------------------------------------------
-- Every SECURITY DEFINER function above starts life executable by PUBLIC,
-- which includes anon. Each refuses a caller with no session already; the
-- revoke makes it deliberate rather than inherited, as in 005-007 and 013.
revoke execute on function update_org(uuid, text, text, text, text) from public;
revoke execute on function archive_org(uuid) from public;
revoke execute on function restore_org(uuid) from public;
revoke execute on function delete_org(uuid, text, boolean) from public;
revoke execute on function all_orgs(boolean) from public;

-- `authenticated` is a Supabase role and does not exist on a bare Postgres,
-- which is what CI starts from. Roles are cluster-wide, so a developer whose
-- cluster has ever run a suite already has it and cannot reproduce the
-- failure by creating a fresh database — which is exactly how 013 shipped
-- this wrong once.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function update_org(uuid, text, text, text, text) to authenticated;
        grant execute on function archive_org(uuid) to authenticated;
        grant execute on function restore_org(uuid) to authenticated;
        grant execute on function delete_org(uuid, text, boolean) to authenticated;
        grant execute on function all_orgs(boolean) to authenticated;
        grant execute on function org_slug_problem(text) to authenticated;
        grant select on deleted_orgs to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
