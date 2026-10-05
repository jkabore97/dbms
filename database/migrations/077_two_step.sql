-- ============================================================
-- 077_two_step.sql — a platform admin signs in with two steps.
--
-- The platform admin can suspend any business, read every business's
-- numbers, approve applications, set what Wave takes, and enter the
-- console's people pages. Until now all of that stood behind one password.
-- A password typed on a shared laptop, or guessed, was the whole platform.
--
-- Supabase Auth already knows a second step: an authenticator app (TOTP)
-- enrolled on the account. Passing it raises the token's `aal` claim from
-- aal1 to aal2. This migration makes the database insist on it:
--
--   1. two_step_gate() runs before every Data API request (PostgREST's
--      pre-request hook). A platform admin whose token is below aal2 is
--      refused — every table, every function, their own shops included —
--      except my_two_step(), which the app needs to know what to ask.
--      Fifty-three functions and three policies read is_platform_admin
--      inline; one gate in front of all of them cannot be forgotten by the
--      next one, which a check added to each would be.
--   2. my_two_step(): is this account held to it, has it a verified
--      factor, and has this token passed it.
--
-- Nobody else is touched: a shopkeeper, a courier or a shopper is waved
-- through on the first line. The worker's service-role calls carry no
-- user, and are waved through too.
--
-- Not covered by the hook (Supabase says so): Realtime and Storage. No
-- Realtime table and no Storage policy reads is_platform_admin, so there is
-- nothing behind them for an aal1 admin token to reach.
--
-- A lost phone: in the Supabase dashboard, Authentication › Users › the
-- account › delete its factor. The app then asks to enrol a new one.
-- ============================================================

create or replace function my_two_step()
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select jsonb_build_object(
        'required', coalesce((select is_platform_admin from profiles
                               where id = auth.uid()), false),
        'enrolled', exists (select 1 from auth.mfa_factors f
                             where f.user_id = auth.uid()
                               and f.status::text = 'verified'),
        'passed',   coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
    );
$$;

create or replace function two_step_gate()
returns void
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    -- The street, the worker, and anyone who has passed: through.
    if auth.uid() is null or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2' then
        return;
    end if;
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return;
    end if;
    -- The one door left open: what to ask. PostgREST names it with or
    -- without the leading slash depending on its version.
    if ltrim(coalesce(current_setting('request.path', true), ''), '/') = 'rpc/my_two_step' then
        return;
    end if;
    raise exception 'Validation en deux étapes requise'
        using errcode = '42501',
              hint = 'two_step_required';
end;
$$;

-- The account's history (075) learns the event.
create or replace function log_security_event(p_kind text, p_detail text default null)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'log_security_event() needs a signed-in caller';
    end if;
    if p_kind not in ('password_changed', 'pin_changed', 'lock_changed',
                      'two_step_enabled') then
        raise exception 'Événement inconnu : %', p_kind;
    end if;
    perform security_log(auth.uid(), p_kind, left(p_detail, 120));
end;
$$;

revoke execute on function my_two_step()   from public;
revoke execute on function two_step_gate() from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function my_two_step()   to authenticated;
        grant execute on function two_step_gate() to authenticated;
    end if;
    -- PostgREST runs the hook as the request's role, the street's too. A
    -- hook anon cannot execute would refuse every vitrine.
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function two_step_gate() to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function two_step_gate() to service_role;
    end if;
    -- Only on Supabase, where PostgREST connects as authenticator.
    if exists (select 1 from pg_roles where rolname = 'authenticator') then
        alter role authenticator set pgrst.db_pre_request = 'public.two_step_gate';
    end if;
end $$;

notify pgrst, 'reload config';
notify pgrst, 'reload schema';
