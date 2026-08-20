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
