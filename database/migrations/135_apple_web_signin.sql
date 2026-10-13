-- ============================================================
-- 135_apple_web_signin.sql — « Continuer avec Apple » on the website
-- (batch 139), behind its switch.
--
-- The owner: « Sign in with Apple on the website too. » The iPhone signs
-- in with Apple's native sheet and hands Apple's identity token to
-- Supabase (125); the website does the same with Apple's JS popup for the
-- Services ID bf.kaj.app.web — an identity token, no OAuth redirect, so no
-- client secret and nothing that expires. What it needs here:
--
--   1. apple_web_signin (oui/non, seeded off): Réglages › Sécurité ›
--      Connexion, « Connexion Apple sur le site ». Off, the website draws
--      no Apple button — until the owner has made the Services ID and
--      added it to Supabase's Apple « Client IDs ». Changed through 105's
--      platform_set_setting like every switch (journaled, undoable).
--   2. sign_in_options(): {apple_web: boolean} — definer, search path
--      pinned, open to anon (the sign-in screen and the vitrine's
--      « Connectez-vous pour commander » are signed out) and
--      authenticated. It reads that one switch and nothing else.
--
-- Shop, farm and association alike: signing in is the person's, not a
-- business's; nothing any business, vitrine or the street shows changes.
-- With the switch off (as seeded) nothing anybody sees changes at all.
--
-- Re-runnable (the bundle runs twice): the setting on conflict do
-- nothing, create or replace.
-- ============================================================

insert into platform_settings (key, value) values
    ('apple_web_signin', 'false')
on conflict (key) do nothing;

create or replace function sign_in_options()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'apple_web', coalesce((select value from platform_settings
                                where key = 'apple_web_signin') = 'true'::jsonb, false));
$$;

-- ------------------------------------------------------------
-- Grants: born closed (063); opened to whom it is for.
-- ------------------------------------------------------------
revoke execute on function sign_in_options() from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        -- The street's: the sign-in screen is signed out.
        grant execute on function sign_in_options() to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function sign_in_options() to authenticated;
    end if;
end $$;
