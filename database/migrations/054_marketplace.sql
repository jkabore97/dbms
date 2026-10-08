-- ============================================================
-- 054_marketplace.sql — the welcome page: where a shop is, and what is à la une.
--
-- The street side is becoming the front door of the app, so two more things
-- have to be true of it:
--
--   1. A shop's window says where the shop is. storefront(slug) now returns
--      the pin (053) so the window — and the directory's map — can hand a
--      shopper an itinerary. The return type changes, so the function is
--      dropped and recreated, and its grants re-issued.
--
--   2. Some articles are "à la une": shown on the welcome page, across every
--      shop, because the shop paid the platform for the spot. That is a
--      *platform* decision, never the shop's own — products.featured_until
--      is set by set_product_featured(), which only a platform admin may
--      call — and it ends by itself when the date passes, so nobody has to
--      remember to take a paid spot down.
--
-- Everything the street reads stays a SECURITY DEFINER function that names
-- its columns and is granted to anon (052): the featured row carries a name,
-- a price, in stock or not, a photo and the shop's name and slug — never a
-- cost, a count, or a phone.
-- ============================================================

-- ------------------------------------------------------------
-- The window says where the shop is
-- ------------------------------------------------------------
drop function if exists storefront(text);
create function storefront(p_slug text)
returns table (
    org_id   uuid,
    name     text,
    slug     text,
    profile  text,
    blurb    text,
    phone    text,
    address  text,
    theme    text,
    currency text,
    lat      double precision,
    lng      double precision
)
language sql
stable
security definer
set search_path = public
as $$
    select o.id, o.name, o.slug, o.profile::text, o.storefront_blurb,
           o.phone, o.address, o.theme, o.default_currency, o.lat, o.lng
    from orgs o
    where o.id = storefront_open(p_slug);
$$;

-- ------------------------------------------------------------
-- À la une
-- ------------------------------------------------------------
alter table products add column if not exists featured_until timestamptz;

comment on column products.featured_until is
    'Until when this article is shown à la une on the welcome page. Set by '
    'the platform only (set_product_featured), because the spot is paid for; '
    'null or past means not featured.';

create index if not exists products_featured_idx
    on products (featured_until) where featured_until is not null;

-- Platform only. `p_until` null clears the spot; a past date has the same
-- effect and is how a spot is ended early without losing the record.
create or replace function set_product_featured(p_product_id uuid, p_until timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not exists (select 1 from profiles
                    where id = auth.uid() and is_platform_admin) then
        raise exception 'Only the platform can put an article à la une';
    end if;
    update products set featured_until = p_until where id = p_product_id;
    if not found then
        raise exception 'No such article';
    end if;
end;
$$;

-- The welcome page, for anyone: the featured articles of open vitrines, the
-- same gate as the window itself (published, active, on an open vitrine of a
-- business that still exists). Newest spot first; a dozen at most, because
-- a strip of forty is a catalogue, not an advertisement.
create or replace function storefront_featured()
returns table (
    id         uuid,
    name       text,
    sale_price numeric,
    in_stock   boolean,
    photo_key  text,
    shop_name  text,
    shop_slug  text,
    currency   text
)
language sql
stable
security definer
set search_path = public
as $$
    select p.id, p.name, p.sale_price, (p.quantity > 0),
           (select d.r2_key from documents d
             where d.product_id = p.id
             order by coalesce(d.captured_at, d.created_at) desc
             limit 1),
           o.name, o.slug, o.default_currency
    from products p
    join orgs o on o.id = p.org_id
    where p.featured_until > now()
      and p.is_active
      and p.is_published
      and o.storefront_enabled
      and o.archived_at  is null
      and o.suspended_at is null
    order by p.featured_until desc, p.name
    limit 12;
$$;

-- What the platform chooses from: every article currently in a window, with
-- its shop and its spot's end date if it has one. Featured spots first so
-- what is running is seen before what could be.
create or replace function platform_featured_candidates()
returns table (
    product_id     uuid,
    name           text,
    sale_price     numeric,
    shop_name      text,
    shop_slug      text,
    currency       text,
    featured_until timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if not exists (select 1 from profiles
                    where profiles.id = auth.uid() and profiles.is_platform_admin) then
        raise exception 'Only the platform can see the candidates';
    end if;
    return query
    select p.id, p.name, p.sale_price, o.name, o.slug, o.default_currency,
           p.featured_until
    from products p
    join orgs o on o.id = p.org_id
    where p.is_active
      and p.is_published
      and o.storefront_enabled
      and o.archived_at  is null
      and o.suspended_at is null
    order by (p.featured_until > now()) desc nulls last, o.name, p.name;
end;
$$;

-- ------------------------------------------------------------
-- Grants: the street reads, the platform writes
-- ------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function storefront(text)      to anon;
        grant execute on function storefront_featured() to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function storefront(text)                              to authenticated;
        grant execute on function storefront_featured()                         to authenticated;
        grant execute on function set_product_featured(uuid, timestamptz)       to authenticated;
        grant execute on function platform_featured_candidates()                to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
