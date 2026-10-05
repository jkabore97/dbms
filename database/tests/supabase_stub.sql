-- Minimal stub of what Supabase provides, so schema.sql can be tested locally.
-- Never run this against a real Supabase database.
create schema if not exists auth;

-- Only the columns this project actually reads. `phone` and `raw_user_meta_data`
-- are what the profiles trigger in 004 mirrors across on sign-up.
create table auth.users (
    id                 uuid primary key default gen_random_uuid(),
    phone              text unique,
    email              varchar(255) unique,
    raw_user_meta_data jsonb not null default '{}'::jsonb
);

-- Supabase resolves the current user from the JWT it puts on the request.
-- Tests impersonate someone the same way PostgREST does:
--
--   set local "request.jwt.claim.sub" = '<user uuid>';
--
-- With nothing set this returns null, which is exactly what an anonymous
-- caller gets — every policy in the project then denies.
create or replace function auth.uid() returns uuid
language sql
stable
as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

-- The sign-in sessions (075 reads its own, closes them). Only the columns
-- this project reads.
create table auth.sessions (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null references auth.users(id) on delete cascade,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),
    refreshed_at timestamp,
    user_agent   text,
    ip           inet
);

-- The token's claims. Tests name the session as PostgREST would:
--   set local "request.jwt.claims" = '{"session_id": "<uuid>"}';
create or replace function auth.jwt() returns jsonb
language sql
stable
as $$
    select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
$$;
