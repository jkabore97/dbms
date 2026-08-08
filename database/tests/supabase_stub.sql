-- Minimal stub of what Supabase provides, so schema.sql can be tested locally.
create schema if not exists auth;
create table auth.users (id uuid primary key default gen_random_uuid());
create or replace function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;
