-- ============================================================
-- 126_support.sql — « Aide Mara »: how to reach the people who run Mara.
--
-- The owner: « a support system on the platform with the e-mail
-- hello@kaj-consulting.com plus WhatsApp 24/7 support with my number,
-- editable in admin ». The public page https://marakaj.com/aide (the App
-- Store's Support URL, served by workers/kaj-app without JavaScript), the
-- app's « Aide » (Compte › Aide, the shopper's profile) and every footer
-- read the same three things, from here:
--
--   1. support_email: a platform setting, default hello@kaj-consulting.com,
--      checked as an e-mail address by a trigger (113's style) — never
--      empty, the page always shows one.
--   2. support_hours: a platform setting, default « 24 h/24, 7 j/7 », a
--      few words (60 characters at most, never empty): the page's « Nous
--      répondons … ».
--   3. support_whatsapp (113) stays as it was — empty, no WhatsApp button
--      anywhere — but its check now takes out everything that is not a
--      letter or a digit before it counts the digits: a number copied
--      from WhatsApp or a phone's contacts comes wrapped in invisible
--      direction marks (U+202A … U+202C) and may carry a non-breaking
--      hyphen (U+2011); 113's check, which took out only spaces, « + »,
--      brackets, dots and dashes, refused « +1 862 335 4492 » pasted that
--      way. support_whatsapp() already reads the digits alone.
--   4. support_contacts(): {email, whatsapp (digits or null), hours} —
--      definer, search path pinned, for anon (the signed-out page, the
--      sign-in screen's help) and authenticated (the app). It reads three
--      settings and nothing else; nothing about any business.
--
-- All three are changed in Réglages › « Aide aux clients » through 105's
-- platform_set_setting (platform admin only, journaled, « Annuler »):
-- a string setting, at most 200 characters there, then the triggers here.
--
-- Shop, farm and association alike: the help is the platform's, the same
-- for every business and for a shopper or a courier; nothing a business,
-- a vitrine or the street shows changes (P1, test_batch126).
--
-- Re-runnable (the bundle runs twice): settings on conflict do nothing,
-- create or replace, drop trigger if exists.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The e-mail and the hours
-- ------------------------------------------------------------
insert into platform_settings (key, value) values
    ('support_email', '"hello@kaj-consulting.com"'),
    ('support_hours', '"24 h/24, 7 j/7"')
on conflict (key) do nothing;

-- An address someone can write to: one « @ », a dot after it, and nothing
-- that would break out of the page's mailto: link or an HTML attribute —
-- no space, no < > " ' ? & , ; (the app and the site check the same).
create or replace function trg_support_email()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    if jsonb_typeof(new.value) <> 'string'
       or (new.value #>> '{}') !~ '^[^@[:space:]<>"''?&,;]+@[^@[:space:]<>"''?&,;]+\.[^@[:space:]<>"''?&,;.]+$'
       or char_length(new.value #>> '{}') > 120 then
        raise exception 'L''e-mail de l''aide : une adresse comme hello@kaj-consulting.com.';
    end if;
    return new;
end;
$$;

drop trigger if exists support_email_check on platform_settings;
create trigger support_email_check
before insert or update on platform_settings
for each row when (new.key = 'support_email')
execute function trg_support_email();

-- A few words, read in a sentence: « Nous répondons 24 h/24, 7 j/7. »
create or replace function trg_support_hours()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    if jsonb_typeof(new.value) <> 'string'
       or btrim(new.value #>> '{}') = ''
       or char_length(new.value #>> '{}') > 60 then
        raise exception 'Les heures de l''aide : quelques mots, 60 caractères au plus (par exemple 24 h/24, 7 j/7).';
    end if;
    return new;
end;
$$;

drop trigger if exists support_hours_check on platform_settings;
create trigger support_hours_check
before insert or update on platform_settings
for each row when (new.key = 'support_hours')
execute function trg_support_hours();

-- ------------------------------------------------------------
-- 2. The WhatsApp number: what is not a letter or a digit is not counted
-- ------------------------------------------------------------
-- Letters stay, so a word is still refused (« le support »); everything
-- else — spaces, « + », brackets, any dash, the invisible direction marks
-- a copied number carries — is taken out before the 8 to 15 digits are
-- counted. « ; », « , » or « / » reads as two numbers (« 226 70 00 00 00 /
-- 226 76 00 00 00 »): refused, never run together into one wrong number.
-- The value is kept as typed (« Annuler » puts back exactly what
-- was there); support_whatsapp() reads its digits.
create or replace function trg_support_whatsapp()
returns trigger
language plpgsql
set search_path = public
as $$
declare
    v text := regexp_replace(coalesce(new.value #>> '{}', ''), '[^[:alnum:]]', '', 'g');
begin
    if jsonb_typeof(new.value) <> 'string'
       or (new.value #>> '{}') ~ '[;,/]'
       or (v <> '' and v !~ '^[0-9]{8,15}$') then
        raise exception 'Le numéro WhatsApp de l''aide : l''indicatif du pays puis le numéro, en chiffres (par exemple 22670000000).';
    end if;
    return new;
end;
$$;

-- ------------------------------------------------------------
-- 3. The three, for the page and the app
-- ------------------------------------------------------------
create or replace function support_contacts()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'email', coalesce(nullif(btrim((select value #>> '{}' from platform_settings
                                         where key = 'support_email')), ''),
                          'hello@kaj-consulting.com'),
        'whatsapp', support_whatsapp(),
        'hours', coalesce(nullif(btrim((select value #>> '{}' from platform_settings
                                         where key = 'support_hours')), ''),
                          '24 h/24, 7 j/7'));
$$;

-- ------------------------------------------------------------
-- Grants: born closed (063); each opened to whom it is for.
-- ------------------------------------------------------------
revoke execute on function trg_support_email()    from public;
revoke execute on function trg_support_hours()    from public;
revoke execute on function trg_support_whatsapp() from public;
revoke execute on function support_contacts()     from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function trg_support_email()    from anon;
        revoke execute on function trg_support_hours()    from anon;
        revoke execute on function trg_support_whatsapp() from anon;
        -- The street's: the signed-out page /aide and the sign-in's help.
        grant  execute on function support_contacts()     to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: the triggers.
        revoke execute on function trg_support_email()    from authenticated;
        revoke execute on function trg_support_hours()    from authenticated;
        revoke execute on function trg_support_whatsapp() from authenticated;
        grant  execute on function support_contacts()     to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
