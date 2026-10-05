-- ============================================================
-- 078_two_step_optional.sql — the second step becomes a choice.
--
-- 077 made the authenticator code compulsory for every platform admin.
-- The owner's call: not now. Sign-in is to stay the password once and the
-- device PIN after, for everybody, and Google sign-in is coming. The
-- second step stays built, but asleep until switched on in Compte ›
-- Sécurité (platform_settings.admin_two_step, off by default).
--
-- The hook stays registered: with the switch off it waves everybody
-- through, and switching it on needs no change to the authenticator role.
-- Switching it back off needs the code, which is right — otherwise the
-- switch would be the way round it — and is automatic: the gate refuses an
-- admin below aal2 every call, set_platform_setting included.
-- ============================================================

insert into platform_settings (key, value) values ('admin_two_step', 'false')
on conflict (key) do nothing;

-- Whether the platform has switched it on.
create or replace function two_step_on()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((select (value #>> '{}')::boolean
                       from platform_settings where key = 'admin_two_step'), false);
$$;

create or replace function my_two_step()
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select jsonb_build_object(
        'required', two_step_on() and coalesce((select is_platform_admin from profiles
                                                 where id = auth.uid()), false),
        'enrolled', exists (select 1 from auth.mfa_factors f
                             where f.user_id = auth.uid()
                               and f.status::text = 'verified'),
        'passed',   coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2',
        'on',       two_step_on()
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
    if auth.uid() is null or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2' then
        return;
    end if;
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return;
    end if;
    if not two_step_on() then
        return;
    end if;
    if ltrim(coalesce(current_setting('request.path', true), ''), '/') = 'rpc/my_two_step' then
        return;
    end if;
    raise exception 'Validation en deux étapes requise'
        using errcode = '42501',
              hint = 'two_step_required';
end;
$$;

revoke execute on function two_step_on() from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function two_step_on() from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function two_step_on() to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
