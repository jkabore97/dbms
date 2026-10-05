-- ============================================================
-- 080_org_logo.sql — a shop's own logo.
--
-- The owner's words: enable logo adding to the stores. Every business,
-- Free or Pro — a logo is who the shop is, not a dressing — may hang one of
-- its own photographs as its logo. The vitrine shows it beside the name.
--
--   1. orgs.logo_key: the r2 key of one of the business's own documents.
--   2. set_org_logo(): an administrator sets it, or clears it with null.
--   3. storefront() carries it, inside the `style` it already returns —
--      added for every plan, so the signature (and every caller) stands.
--   4. storefront_photo_allowed(): the uploads Worker may now serve an
--      open vitrine's logo to the street, as it does its articles' photos.
-- ============================================================

alter table orgs add column if not exists logo_key text;

create or replace function set_org_logo(p_org_id uuid, p_key text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_key text := nullif(btrim(coalesce(p_key, '')), '');
begin
    if auth.uid() is null then
        raise exception 'set_org_logo() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur choisit le logo de la boutique';
    end if;
    if v_key is not null and not exists (
        select 1 from documents d
         where d.org_id = p_org_id and d.r2_key = v_key
           and coalesce(d.content_type, '') not ilike '%pdf%') then
        raise exception 'Le logo doit être une photo de cette entreprise';
    end if;
    update orgs set logo_key = v_key where id = p_org_id;
end;
$$;

-- 068's window, with the logo in the style for every plan.
create or replace function storefront(p_slug text)
returns table (
    org_id        uuid,
    name          text,
    slug          text,
    profile       text,
    blurb         text,
    phone         text,
    address       text,
    theme         text,
    currency      text,
    lat           double precision,
    lng           double precision,
    wave_merchant text,
    style         jsonb
)
language sql
stable
security definer
set search_path = public
as $$
    select o.id, o.name, o.slug, o.profile::text, o.storefront_blurb,
           o.phone, o.address, o.theme, o.default_currency, o.lat, o.lng,
           o.wave_merchant,
           (case when org_plan(o.id) = 'pro' then o.storefront_style
                 else '{}'::jsonb end)
           || case when o.logo_key is not null
                   then jsonb_build_object('logo_key', o.logo_key)
                   else '{}'::jsonb end
    from orgs o
    where o.id = storefront_open(p_slug);
$$;

-- The photos the Worker may serve to the street: the published articles'
-- (052), a Pro business's cover (068), and now any open vitrine's logo.
create or replace function storefront_photo_allowed(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from documents d
        join products p on p.id = d.product_id
        join orgs     o on o.id = p.org_id
        where d.r2_key = p_key
          and p.is_active
          and p.is_published
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
    ) or exists (
        select 1
        from orgs o
        where o.storefront_style ->> 'cover_key' = p_key
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
          and org_plan(o.id) = 'pro'
    ) or exists (
        select 1
        from orgs o
        where o.logo_key = p_key
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
    );
$$;

revoke execute on function set_org_logo(uuid, text)       from public;
revoke execute on function storefront(text)               from public;
revoke execute on function storefront_photo_allowed(text) from public;

do $$
begin
    -- The street reads the window and its photos (063: a recreated street
    -- function says its grant again, by name).
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function storefront(text)               to anon;
        grant execute on function storefront_photo_allowed(text) to anon;
        revoke execute on function set_org_logo(uuid, text)      from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function storefront(text)               to authenticated;
        grant execute on function storefront_photo_allowed(text) to authenticated;
        grant execute on function set_org_logo(uuid, text)       to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
