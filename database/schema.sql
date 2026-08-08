-- Kaj-consulting multi-tenant business platform
-- Core schema v0: tenancy, scoped roles, double-entry ledger, event trail, RLS
-- Target: Postgres 15+ (written for Supabase — assumes the built-in auth.users table)
--
-- This is a starting point, not a finished product. It covers the three
-- structural decisions everything else depends on:
--   1. orgs -> entities -> departments (one engine, many businesses)
--   2. memberships are (user, role, SCOPE) — never a flat global role
--   3. money moves through journal_entries/journal_lines, never a raw balance column

create extension if not exists "pgcrypto";

-- ============================================================
-- 1. TENANCY: org -> entity -> department
-- ============================================================

-- One row per client business: Israel's church, Ignace's farm, Esperance's store.
create table orgs (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    slug text unique not null,                 -- subdomain: {slug}.kajapp.com
    profile text not null default 'generic',   -- 'church' | 'farm' | 'retail' | 'generic'
    custom_domain text unique,                 -- optional: app.theirbusiness.com
    email_domain text unique,                  -- optional: claimed @theirbusiness.com for auto-join
    default_currency text not null default 'XOF',
    created_at timestamptz not null default now()
);

-- A location or logical unit within an org: a farm site, a church campus, a store branch.
create table entities (
    id uuid primary key default gen_random_uuid(),
    org_id uuid not null references orgs(id) on delete cascade,
    name text not null,
    kind text,                                 -- profile-defined: 'farm_site' | 'branch' | 'campus'
    created_at timestamptz not null default now()
);

-- A sub-unit within an entity: the poultry department, the retail floor, the choir.
create table departments (
    id uuid primary key default gen_random_uuid(),
    entity_id uuid not null references entities(id) on delete cascade,
    name text not null,
    created_at timestamptz not null default now()
);

-- ============================================================
-- 2. PEOPLE & SCOPED ROLES
-- ============================================================

-- auth.users (Supabase) holds login identity; this is the app-facing profile.
create table profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    full_name text,
    phone text unique,
    preferred_locale text not null default 'fr',
    created_at timestamptz not null default now()
);

create type role_name as enum (
    'owner', 'super_admin', 'admin', 'manager', 'supervisor', 'employee',
    'observer', 'approver'
);

create type scope_kind as enum ('org', 'entity', 'department');

-- A single grant: this person holds this role at this exact scope.
-- Example — Ignace's quieter investor: role='observer', scope_kind='org', visibility='summary'.
-- Example — a poultry supervisor: role='supervisor', scope_kind='department', scope_id=<poultry dept>.
create table memberships (
    id uuid primary key default gen_random_uuid(),
    org_id uuid not null references orgs(id) on delete cascade,   -- denormalized for fast RLS checks
    user_id uuid not null references profiles(id) on delete cascade,
    role role_name not null,
    scope_kind scope_kind not null,
    scope_id uuid not null,          -- points at orgs.id, entities.id, or departments.id per scope_kind
    visibility text not null default 'full',  -- 'full' | 'summary' — observer granularity
    created_at timestamptz not null default now(),
    unique (user_id, scope_kind, scope_id, role)
);

-- ============================================================
-- 3. LEDGER — double-entry underneath every simple button tap
-- ============================================================

create table accounts (
    id uuid primary key default gen_random_uuid(),
    org_id uuid not null references orgs(id) on delete cascade,
    code text not null,              -- '1000', '4000' — chart-of-accounts style
    name text not null,              -- 'Cash', 'Offering Income', 'Feed Expense'
    type text not null check (type in ('asset','liability','equity','income','expense')),
    unique (org_id, code)
);

-- Never edited, never deleted. Undo = a new entry that reverses this one.
create table journal_entries (
    id uuid primary key default gen_random_uuid(),
    org_id uuid not null references orgs(id) on delete cascade,
    entity_id uuid references entities(id),
    department_id uuid references departments(id),
    memo text,
    created_by uuid not null references profiles(id),
    created_at timestamptz not null default now(),
    device_id text,                              -- which offline device wrote this — dedupes sync conflicts
    reverses_entry_id uuid references journal_entries(id)
);

create table journal_lines (
    id uuid primary key default gen_random_uuid(),
    journal_entry_id uuid not null references journal_entries(id) on delete cascade,
    account_id uuid not null references accounts(id),
    debit numeric(14,2) not null default 0,
    credit numeric(14,2) not null default 0,
    check (debit = 0 or credit = 0)
);

-- ============================================================
-- 4. DOCUMENTS — what Esperance photographs, what Israel scans
-- ============================================================

create table documents (
    id uuid primary key default gen_random_uuid(),
    org_id uuid not null references orgs(id) on delete cascade,
    r2_key text not null,                        -- object path in Cloudflare R2
    kind text,                                   -- 'invoice' | 'product_photo' | 'receipt'
    ocr_status text not null default 'pending',
    linked_journal_entry_id uuid references journal_entries(id),
    uploaded_by uuid not null references profiles(id),
    created_at timestamptz not null default now()
);

-- ============================================================
-- 5. ROW LEVEL SECURITY — scope resolves org -> entity -> department
-- ============================================================
-- Pattern shown on journal_entries; accounts, documents, and memberships
-- follow the same shape once we're past scaffolding.

alter table journal_entries enable row level security;

create policy "read within your org"
on journal_entries for select
using (
    exists (
        select 1 from memberships m
        where m.user_id = auth.uid()
          and m.org_id = journal_entries.org_id
    )
);

create policy "write within your granted scope"
on journal_entries for insert
with check (
    exists (
        select 1 from memberships m
        where m.user_id = auth.uid()
          and m.org_id = journal_entries.org_id
          and m.role <> 'observer'
          and (
              (m.scope_kind = 'org' and m.scope_id = journal_entries.org_id)
              or (m.scope_kind = 'entity' and m.scope_id = journal_entries.entity_id)
              or (m.scope_kind = 'department' and m.scope_id = journal_entries.department_id)
          )
    )
);
