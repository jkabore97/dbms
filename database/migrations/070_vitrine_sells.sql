-- ============================================================
-- 070_vitrine_sells.sql — a vitrine that is never empty, and says so.
--
-- The October audit, from the live data: ELIM SHOP opened its vitrine with
-- 57 articles and published none, so a shopper who followed the directory
-- found "Aucun article affiché". Publishing was one switch per article,
-- off by default, and nobody flips 57 switches. Across the platform one
-- article in seventy had a photo, no shop had a description, an address or
-- a phone, and nothing told an owner what their window was missing.
--
--   1. An article is published unless the owner hides it: the column's
--      default turns to true for new articles. Ingredients (028) are the
--      exception — the production flour is not for sale on the street.
--      Existing articles are not touched: what an owner decided stays.
--   2. publish_all_products(): the one tap for the 57 — every active,
--      priced, non-ingredient article, by somebody the articles dial lets
--      edit them.
--   3. The directory lists an open vitrine only once it has something to
--      show: an open window with an empty shelf is a dead end, not a shop.
--      The link itself keeps working; only the listing waits.
--   4. storefront_previews(): three articles per shop for the directory's
--      cards, photographed ones first — the card shows what is sold
--      instead of the shop's initial on a beige square.
--   5. vitrine_checklist(): what this window has and lacks, for its own
--      members — the meter on the vitrine settings.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Published unless hidden
-- ------------------------------------------------------------
alter table products alter column is_published set default true;

create or replace function trg_ingredient_unpublished()
returns trigger
language plpgsql
as $$
begin
    if new.is_ingredient then
        new.is_published := false;
    end if;
    return new;
end;
$$;

create or replace trigger ingredient_unpublished
before insert on products
for each row execute function trg_ingredient_unpublished();

-- ------------------------------------------------------------
-- 2. Tout publier
-- ------------------------------------------------------------
create or replace function publish_all_products(p_org_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_count integer;
begin
    if auth.uid() is null then
        raise exception 'publish_all_products() needs a signed-in caller';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'Vous ne pouvez pas modifier les articles de cette entreprise';
    end if;
    if feature_access(p_org_id, 'products') <> 'edit' then
        raise exception 'Les articles vous sont fermés. Voyez le propriétaire.';
    end if;
    update products
       set is_published = true
     where org_id = p_org_id
       and is_active
       and not is_ingredient
       and not is_published
       and coalesce(sale_price, 0) > 0;
    get diagnostics v_count = row_count;
    return v_count;
end;
$$;

-- ------------------------------------------------------------
-- 3. The directory lists a window with something in it
-- ------------------------------------------------------------
-- 053 verbatim, plus the shelf test. Same signature, so create or replace.
create or replace function storefront_directory(
    p_lat double precision default null,
    p_lng double precision default null
)
returns table (
    org_id      uuid,
    name        text,
    slug        text,
    profile     text,
    blurb       text,
    address     text,
    lat         double precision,
    lng         double precision,
    distance_km double precision
)
language sql
stable
security definer
set search_path = public
as $$
    select d.org_id, d.name, d.slug, d.profile, d.blurb, d.address,
           d.lat, d.lng, d.distance_km
    from (
        select o.id as org_id, o.name, o.slug, o.profile::text,
               o.storefront_blurb as blurb, o.address, o.lat, o.lng,
               case
                   when p_lat is null or p_lng is null
                     or o.lat is null or o.lng is null then null
                   else 6371.0 * 2 * asin(sqrt(
                            power(sin(radians(o.lat - p_lat) / 2), 2)
                          + cos(radians(p_lat)) * cos(radians(o.lat))
                          * power(sin(radians(o.lng - p_lng) / 2), 2)))
               end as distance_km
        from orgs o
        where o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
          and exists (select 1 from products p
                       where p.org_id = o.id
                         and p.is_active
                         and p.is_published)
    ) d
    order by (d.distance_km is null), d.distance_km, d.name;
$$;

-- ------------------------------------------------------------
-- 4. What each card shows
-- ------------------------------------------------------------
create or replace function storefront_previews(p_slugs text[])
returns table (
    slug       text,
    product_id uuid,
    name       text,
    sale_price numeric,
    photo_key  text
)
language sql
stable
security definer
set search_path = public
as $$
    select x.slug, x.id, x.name, x.sale_price, x.photo_key
    from (
        select o.slug, p.id, p.name, p.sale_price, ph.r2_key as photo_key,
               row_number() over (
                   partition by o.id
                   order by (ph.r2_key is null), (p.quantity <= 0), p.name
               ) as n
        from orgs o
        join products p on p.org_id = o.id
        left join lateral (
            select d.r2_key from documents d
             where d.product_id = p.id
             order by coalesce(d.captured_at, d.created_at) desc
             limit 1
        ) ph on true
        where o.slug = any (coalesce(p_slugs, '{}'))
          and o.id = storefront_open(o.slug)
          and p.is_active
          and p.is_published
    ) x
    where x.n <= 3
    order by x.slug, x.n;
$$;

-- ------------------------------------------------------------
-- 5. The checklist behind the meter
-- ------------------------------------------------------------
create or replace function vitrine_checklist(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select case when not is_org_member(p_org_id) then null else
    jsonb_build_object(
        'open',        o.storefront_enabled,
        'active',      (select count(*) from products p
                         where p.org_id = o.id and p.is_active and not p.is_ingredient),
        'published',   (select count(*) from products p
                         where p.org_id = o.id and p.is_active and p.is_published),
        'unpublished', (select count(*) from products p
                         where p.org_id = o.id and p.is_active and not p.is_published
                           and not p.is_ingredient and coalesce(p.sale_price, 0) > 0),
        'with_photo',  (select count(*) from products p
                         where p.org_id = o.id and p.is_active and p.is_published
                           and exists (select 1 from documents d where d.product_id = p.id)),
        'blurb',       nullif(btrim(coalesce(o.storefront_blurb, '')), '') is not null,
        'address',     nullif(btrim(coalesce(o.address, '')), '') is not null,
        'phone',       nullif(btrim(coalesce(o.phone, '')), '') is not null,
        'pin',         o.lat is not null and o.lng is not null
    ) end
    from orgs o where o.id = p_org_id;
$$;

-- ------------------------------------------------------------
-- 6. Grants
-- ------------------------------------------------------------
revoke execute on function publish_all_products(uuid)      from public;
revoke execute on function storefront_previews(text[])     from public;
revoke execute on function vitrine_checklist(uuid)         from public;
revoke execute on function storefront_directory(double precision, double precision) from public;

do $$
begin
    -- The street reads the cards (063 rule: say it by name).
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function storefront_previews(text[]) to anon;
        grant execute on function storefront_directory(double precision, double precision) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function storefront_previews(text[])  to authenticated;
        grant execute on function storefront_directory(double precision, double precision) to authenticated;
        grant execute on function publish_all_products(uuid)   to authenticated;
        grant execute on function vitrine_checklist(uuid)      to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
