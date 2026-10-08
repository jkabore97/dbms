-- ============================================================
-- 022 — A BUSINESS PICKS ITS OWN COLOURS
-- ============================================================
-- Since 019 the colour of the app has been decided by `orgs.profile`: green
-- for a farm, indigo for a church, terracotta for a shop. That is a good
-- default and a bad ceiling. A tailor's shop and a hardware shop are both
-- `retail` and have no reason to look identical, and the one thing a business
-- owner asks for after "does it add up" is that it looks like *theirs*.
--
-- So the palette becomes a setting. Three decisions in it are worth stating,
-- because each had a plausible alternative:
--
-- 1. IT BELONGS TO THE BUSINESS, NOT TO THE DEVICE. A per-phone preference
--    would be easier — no migration at all — but it means two people in the
--    same shop describing different screens to each other down the phone, and
--    it means the owner cannot make the app look like their business for the
--    staff who actually use it. This is branding, and branding is not a
--    personal preference.
--
-- 2. IT IS SET BY AN ADMIN, VIA `is_org_admin()`. The same bar as renaming
--    the business, and for the same reason: it changes what every member
--    sees. An employee repainting the shop is not a catastrophe, but it is
--    also not theirs to do.
--
-- 3. THE COLUMN IS NOT AN ENUM. A check constraint listing today's palettes
--    would mean a database migration every time a colour is added, and worse,
--    it would mean the server refusing a palette that a newer app already
--    offers. The constraint here is on the *shape* of the name — a short
--    lowercase slug — so junk is still refused but the list of colours stays
--    where it belongs, in the app. An app that meets a name it does not know
--    falls back to the profile's colour, which is exactly what it did before
--    this migration existed.
--
-- Null means "never chose one", which is every business the moment this runs.

-- ------------------------------------------------------------
-- 1. THE COLUMN
-- ------------------------------------------------------------
alter table orgs add column if not exists theme text;

comment on column orgs.theme is
    'The palette this business chose, as a short slug the app resolves to '
    'colours (''ocean'', ''prune'', …). Null means the profile decides, which '
    'is the default and what every business had before 022. Deliberately not '
    'an enum: the list of palettes lives in the app, and the server must not '
    'refuse one that a newer build already offers.';

-- Shape, not membership. Lowercase slug, 2-32 characters, which is enough to
-- refuse a stray sentence or a colour code pasted in by hand without freezing
-- the palette list into the schema.
alter table orgs drop constraint if exists orgs_theme_is_a_slug;
alter table orgs add constraint orgs_theme_is_a_slug
    check (theme is null or theme ~ '^[a-z][a-z0-9-]{1,31}$');

-- ------------------------------------------------------------
-- 2. SETTING IT
-- ------------------------------------------------------------
-- A separate function rather than another argument on update_org(), because
-- the two are used by different people at different moments: update_org() is
-- the settings form an admin fills in once, and this is a picker that fires on
-- every tap while somebody tries colours out. Folding it in would mean the
-- colour picker having to send the name and the currency to change a hue.
--
-- SECURITY DEFINER for the same reason update_org() is: `orgs` has no update
-- policy for members, and the gate is is_org_admin(), which is also true for
-- a platform admin of every business.
create or replace function set_org_theme(
    p_org_id uuid,
    p_theme  text default null   -- null clears it, back to the profile colour
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
    v_theme text := nullif(btrim(lower(coalesce(p_theme, ''))), '');
begin
    if v_actor is null then
        raise exception 'set_org_theme() needs a signed-in caller';
    end if;

    if not is_org_admin(p_org_id) then
        raise exception 'You cannot change this business';
    end if;

    if not exists (select 1 from orgs where id = p_org_id) then
        raise exception 'No such business';
    end if;

    -- Same rule as update_org(): an archived business is a closed one, and
    -- repainting it puts a colour on something nobody is looking at.
    if exists (select 1 from orgs where id = p_org_id and archived_at is not null) then
        raise exception 'This business is archived. Restore it before changing it.';
    end if;

    -- Checked here as well as by the constraint so the caller gets a sentence
    -- rather than a constraint violation.
    if v_theme is not null and v_theme !~ '^[a-z][a-z0-9-]{1,31}$' then
        raise exception 'Unknown colour: %', p_theme;
    end if;

    update orgs set theme = v_theme where id = p_org_id;

    return p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- 3. THE APP HAS TO BE TOLD
-- ------------------------------------------------------------
-- my_orgs() is what the app calls after sign-in, and the result is cached on
-- the device — which is the whole reason the theme rides along here rather
-- than being fetched per screen. A phone that has been out of range since
-- Tuesday still opens in the right colour, and no home screen flashes its old
-- palette before correcting itself.
--
-- Dropped and recreated rather than replaced: `create or replace` cannot
-- change a function's return type, and this adds a column to it.
drop function if exists my_orgs();

create or replace function my_orgs()
returns table (
    org_id           uuid,
    name             text,
    slug             text,
    profile          text,
    default_currency text,
    roles            text[],
    visibility       text,
    theme            text
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        o.id, o.name, o.slug, o.profile, o.default_currency,
        array['platform_admin'::text],
        'full'::text,
        o.theme
    from orgs o
    where exists(select 1 from profiles where id = auth.uid() and is_platform_admin)

    union all

    select
        o.id, o.name, o.slug, o.profile, o.default_currency,
        array_agg(distinct m.role::text order by m.role::text),
        case when bool_or(m.visibility = 'full') then 'full' else 'summary' end,
        o.theme
    from memberships m
    join orgs o on o.id = m.org_id
    where m.user_id = auth.uid()
      and o.archived_at is null
      and not exists(select 1 from profiles where id = auth.uid() and is_platform_admin)
    group by o.id, o.name, o.slug, o.profile, o.default_currency, o.theme

    order by name;
$$;

-- ------------------------------------------------------------
-- 4. GRANTS
-- ------------------------------------------------------------
-- set_org_theme() starts life executable by PUBLIC, which includes anon. It
-- refuses a caller with no session already; the revoke makes that deliberate
-- rather than inherited, as in 005-007, 013 and 014.
revoke execute on function set_org_theme(uuid, text) from public;

-- my_orgs() is deliberately *not* revoked. It never was before, and a freshly
-- created function gets PUBLIC execute back by default — so recreating it
-- above already restored exactly the grants it had. Tightening it here would
-- be an unrelated change smuggled into a colour migration, and it would take
-- every signed-in user's business list with it on any deployment where
-- `authenticated` happens not to exist. The function returns nothing to a
-- caller with no session anyway: every branch is keyed on auth.uid().

-- `authenticated` is a Supabase role and does not exist on a bare Postgres,
-- which is what CI starts from. Roles are cluster-wide, so a developer whose
-- cluster has ever run a suite already has it and cannot reproduce the
-- failure on a fresh database — which is how 013 shipped this wrong once.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_org_theme(uuid, text) to authenticated;
        grant execute on function my_orgs() to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
