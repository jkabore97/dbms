-- ============================================================
-- 004_rls_policies.sql
--
-- Until now the app talked to Postgres as a trusted script and only
-- journal_entries and church_members were protected. M1 puts a real signed-in
-- user behind the publishable key, and a publishable key is public — anyone
-- who opens the web build has it. From here on, every table is closed by
-- default and each row is reachable only through a membership.
--
-- Two rules shape this whole file:
--
--   1. Scope resolution is centralised in the helper functions below. Policies
--      that inline `select ... from memberships` recurse the moment memberships
--      itself is protected; the helpers are SECURITY DEFINER so they read
--      memberships once, on the caller's behalf, without re-entering RLS.
--   2. The ledger has no update or delete policy anywhere. RLS denies what it
--      is not told to allow, so history cannot be rewritten even by an owner.
--      Undo stays what it always was: a new reversing entry.
-- ============================================================

-- ------------------------------------------------------------
-- 1. SCOPE HELPERS
-- ------------------------------------------------------------
-- SECURITY DEFINER on purpose: these are the one place that reads memberships
-- without RLS. Each filters on auth.uid() itself, so a caller can only ever
-- learn about their own grants. search_path is pinned so a caller cannot
-- shadow `memberships` with a table of their own.

create or replace function my_org_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public, auth
as $$
    select distinct m.org_id
    from memberships m
    where m.user_id = auth.uid();
$$;

create or replace function is_org_member(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select exists (
        select 1 from memberships m
        where m.user_id = auth.uid() and m.org_id = p_org_id
    );
$$;

-- Owners, super admins and admins administer the org itself: who belongs to
-- it, what its locations are, what the chart of accounts looks like.
create or replace function is_org_admin(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select exists (
        select 1 from memberships m
        where m.user_id = auth.uid()
          and m.org_id = p_org_id
          and m.role in ('owner', 'super_admin', 'admin')
    );
$$;

-- Anyone holding a role other than observer may record work. An observer is
-- the quiet investor: they read the books, they never touch them.
create or replace function can_write_org(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select exists (
        select 1 from memberships m
        where m.user_id = auth.uid()
          and m.org_id = p_org_id
          and m.role <> 'observer'
    );
$$;

-- ------------------------------------------------------------
-- 2. PROFILES ARRIVE WITH THEIR USER
-- ------------------------------------------------------------
-- memberships.user_id references profiles(id), so a freshly verified phone
-- number with no profile row cannot be invited into anything. Supabase writes
-- auth.users on OTP verification; this mirrors it into profiles immediately,
-- before any human gets a chance to forget.
create or replace function handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    insert into profiles (id, full_name, phone)
    values (
        new.id,
        nullif(new.raw_user_meta_data ->> 'full_name', ''),
        nullif(new.phone, '')
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function handle_new_auth_user();

-- ------------------------------------------------------------
-- 3. WHAT THE APP ASKS FIRST
-- ------------------------------------------------------------
-- The single call the app makes after sign-in. One row per org, never one per
-- membership: a supervisor who also holds an org-wide observer grant is still
-- one business on their screen. `profile` is what the client routes on.
--
-- Returned in name order so a picker is stable between launches.
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
        o.id,
        o.name,
        o.slug,
        o.profile,
        o.default_currency,
        array_agg(distinct m.role::text order by m.role::text),
        -- 'full' wins over 'summary': the widest grant the person holds is the
        -- one that should decide what they see.
        case when bool_or(m.visibility = 'full') then 'full' else 'summary' end
    from memberships m
    join orgs o on o.id = m.org_id
    where m.user_id = auth.uid()
    group by o.id, o.name, o.slug, o.profile, o.default_currency
    order by o.name;
$$;

-- ------------------------------------------------------------
-- 4. TENANCY
-- ------------------------------------------------------------

alter table orgs enable row level security;

drop policy if exists "orgs readable by their members" on orgs;
create policy "orgs readable by their members"
on orgs for select
using (is_org_member(id));

drop policy if exists "orgs editable by their admins" on orgs;
create policy "orgs editable by their admins"
on orgs for update
using (is_org_admin(id))
with check (is_org_admin(id));

alter table entities enable row level security;

drop policy if exists "entities readable within org" on entities;
create policy "entities readable within org"
on entities for select
using (is_org_member(org_id));

drop policy if exists "entities managed by org admins" on entities;
create policy "entities managed by org admins"
on entities for all
using (is_org_admin(org_id))
with check (is_org_admin(org_id));

alter table departments enable row level security;

drop policy if exists "departments readable within org" on departments;
create policy "departments readable within org"
on departments for select
using (
    exists (
        select 1 from entities e
        where e.id = departments.entity_id and is_org_member(e.org_id)
    )
);

drop policy if exists "departments managed by org admins" on departments;
create policy "departments managed by org admins"
on departments for all
using (
    exists (
        select 1 from entities e
        where e.id = departments.entity_id and is_org_admin(e.org_id)
    )
)
with check (
    exists (
        select 1 from entities e
        where e.id = departments.entity_id and is_org_admin(e.org_id)
    )
);

-- ------------------------------------------------------------
-- 5. PEOPLE
-- ------------------------------------------------------------

alter table profiles enable row level security;

-- You can always see yourself. You can also see the people you share an org
-- with — an entry list that says "recorded by 7f3a…" helps nobody.
drop policy if exists "profiles readable to self and colleagues" on profiles;
create policy "profiles readable to self and colleagues"
on profiles for select
using (
    id = auth.uid()
    or exists (
        select 1 from memberships m
        where m.user_id = profiles.id
          and m.org_id in (select my_org_ids())
    )
);

drop policy if exists "profiles editable by their owner" on profiles;
create policy "profiles editable by their owner"
on profiles for update
using (id = auth.uid())
with check (id = auth.uid());

alter table memberships enable row level security;

-- Your own grants, plus every grant in an org you administer. This is what the
-- login flow reads, and it is the reason Israel's phone cannot enumerate
-- Ignace's staff.
drop policy if exists "memberships readable to holder and org admins" on memberships;
create policy "memberships readable to holder and org admins"
on memberships for select
using (user_id = auth.uid() or is_org_admin(org_id));

drop policy if exists "memberships granted by org admins" on memberships;
create policy "memberships granted by org admins"
on memberships for insert
with check (is_org_admin(org_id));

drop policy if exists "memberships amended by org admins" on memberships;
create policy "memberships amended by org admins"
on memberships for update
using (is_org_admin(org_id))
with check (is_org_admin(org_id));

drop policy if exists "memberships revoked by org admins" on memberships;
create policy "memberships revoked by org admins"
on memberships for delete
using (is_org_admin(org_id));

-- ------------------------------------------------------------
-- 6. LEDGER
-- ------------------------------------------------------------
-- journal_entries already carries its select and insert policies from
-- schema.sql. Nothing here grants update or delete on any ledger table, and
-- that omission is the audit trail.

alter table accounts enable row level security;

drop policy if exists "accounts readable within org" on accounts;
create policy "accounts readable within org"
on accounts for select
using (is_org_member(org_id));

-- The chart of accounts is seeded server-side; only an admin ever adds to it.
drop policy if exists "accounts managed by org admins" on accounts;
create policy "accounts managed by org admins"
on accounts for insert
with check (is_org_admin(org_id));

drop policy if exists "accounts renamed by org admins" on accounts;
create policy "accounts renamed by org admins"
on accounts for update
using (is_org_admin(org_id))
with check (is_org_admin(org_id));

alter table journal_lines enable row level security;

drop policy if exists "lines readable with their entry" on journal_lines;
create policy "lines readable with their entry"
on journal_lines for select
using (
    exists (
        select 1 from journal_entries je
        where je.id = journal_lines.journal_entry_id
          and is_org_member(je.org_id)
    )
);

-- The parent entry is inserted first in the same transaction, so this sees it.
drop policy if exists "lines writable with their entry" on journal_lines;
create policy "lines writable with their entry"
on journal_lines for insert
with check (
    exists (
        select 1 from journal_entries je
        where je.id = journal_lines.journal_entry_id
          and can_write_org(je.org_id)
    )
);

alter table contribution_attributions enable row level security;

drop policy if exists "attributions readable with their entry" on contribution_attributions;
create policy "attributions readable with their entry"
on contribution_attributions for select
using (
    exists (
        select 1 from journal_entries je
        where je.id = contribution_attributions.journal_entry_id
          and is_org_member(je.org_id)
    )
);

drop policy if exists "attributions writable with their entry" on contribution_attributions;
create policy "attributions writable with their entry"
on contribution_attributions for insert
with check (
    exists (
        select 1 from journal_entries je
        where je.id = contribution_attributions.journal_entry_id
          and can_write_org(je.org_id)
    )
);

-- ------------------------------------------------------------
-- 7. DOCUMENTS
-- ------------------------------------------------------------

alter table documents enable row level security;

drop policy if exists "documents readable within org" on documents;
create policy "documents readable within org"
on documents for select
using (is_org_member(org_id));

drop policy if exists "documents uploadable by non-observers" on documents;
create policy "documents uploadable by non-observers"
on documents for insert
with check (can_write_org(org_id));

-- A photo can be re-linked to an entry or re-OCR'd; it cannot be deleted,
-- because a receipt that vanishes is indistinguishable from one that never
-- existed.
drop policy if exists "documents amendable by non-observers" on documents;
create policy "documents amendable by non-observers"
on documents for update
using (can_write_org(org_id))
with check (can_write_org(org_id));
