-- ============================================================
-- 052_storefront.sql — la vitrine: a shop's articles, visible to anyone.
--
-- Every marketplace's catalogue rots — prices go stale, "in stock" is a lie —
-- because keeping it current is extra work. Kaj's is not: the shop already
-- keeps its stock and prices current every day, for its own books. So the
-- vitrine is a switch on data that is already true, not a second catalogue.
--
-- Phase one is deliberately thin: a shop opts in, chooses which articles to
-- show, and anyone with the link can look. Nothing is bought, paid or
-- delivered here — a shopper *contacts* the shop. What is exposed is exactly
-- the shop window and nothing behind the counter: name, price, whether it is
-- in stock, a photo. Never the cost price, never the count, never a shop that
-- did not opt in, never one the platform has suspended or archived.
--
-- Read by anonymous callers, so every read is a SECURITY DEFINER function
-- that names its columns — the same shape as invitation_preview() (005), the
-- one other thing an anonymous caller may ask this database.
-- ============================================================

alter table orgs add column if not exists storefront_enabled boolean not null default false;
alter table orgs add column if not exists storefront_blurb   text;
comment on column orgs.storefront_enabled is
    'The shop chose to show a public vitrine. Off by default: nothing about a '
    'business is public until its administrator says so.';

alter table products add column if not exists is_published boolean not null default false;
comment on column products.is_published is
    'Shown on the vitrine, when the shop has one. Off by default; the shop '
    'picks each article. Reads also require is_active — a retired article is '
    'never shown whatever this says.';

-- ------------------------------------------------------------
-- The switch: an administrator opens or closes the vitrine
-- ------------------------------------------------------------
create or replace function set_storefront(
    p_org_id  uuid,
    p_enabled boolean,
    p_blurb   text default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'set_storefront() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Only an administrator can open or close the vitrine';
    end if;

    update orgs
       set storefront_enabled = coalesce(p_enabled, storefront_enabled),
           -- Null leaves the text alone; an empty string clears it.
           storefront_blurb   = case
               when p_blurb is null then storefront_blurb
               else nullif(btrim(p_blurb), '')
           end
     where id = p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- The window, for anyone
-- ------------------------------------------------------------
-- One gate, written once: an open vitrine on a business that still exists.
-- Suspended (049) and archived (014) businesses vanish from the street even
-- if the switch was left on.
create or replace function storefront_open(p_slug text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
    select o.id
    from orgs o
    where o.slug = lower(btrim(coalesce(p_slug, '')))
      and o.storefront_enabled
      and o.archived_at  is null
      and o.suspended_at is null;
$$;

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
    currency text
)
language sql
stable
security definer
set search_path = public
as $$
    select o.id, o.name, o.slug, o.profile::text, o.storefront_blurb,
           o.phone, o.address, o.theme, o.default_currency
    from orgs o
    where o.id = storefront_open(p_slug);
$$;

-- The articles. `in_stock` is a yes/no on purpose: a shopper is told whether
-- to come, not how many are on the shelf. The photo is the newest one the
-- shop took of that article, by its R2 key; the uploads Worker serves it
-- publicly only after asking storefront_photo_allowed() below.
create or replace function storefront_products(p_slug text)
returns table (
    id         uuid,
    name       text,
    sale_price numeric,
    in_stock   boolean,
    photo_key  text
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
             limit 1)
    from products p
    where p.org_id = storefront_open(p_slug)
      and p.is_active
      and p.is_published
    order by p.name;
$$;

-- Asked by the uploads Worker before it serves a photo to somebody with no
-- token: is this key a picture of a published article on an open vitrine?
-- The Worker performs; Postgres decides — the rule every Worker here keeps.
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
    );
$$;

-- ------------------------------------------------------------
-- Who may call what
-- ------------------------------------------------------------
revoke execute on function set_storefront(uuid, boolean, text) from public;
revoke execute on function storefront_open(text)              from public;
revoke execute on function storefront(text)                   from public;
revoke execute on function storefront_products(text)          from public;
revoke execute on function storefront_photo_allowed(text)     from public;

do $$
begin
    -- The window is for the street: anonymous callers may look.
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function storefront(text)               to anon;
        grant execute on function storefront_products(text)      to anon;
        grant execute on function storefront_photo_allowed(text) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_storefront(uuid, boolean, text) to authenticated;
        grant execute on function storefront(text)                    to authenticated;
        grant execute on function storefront_products(text)           to authenticated;
        grant execute on function storefront_photo_allowed(text)      to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
