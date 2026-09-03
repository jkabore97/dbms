-- ============================================================
-- 059_product_search.sql — one search across every shop window.
--
-- A shopper knows what they want ("savon", "riz 25kg") before they know
-- which shop has it. So the street gets one question that looks through
-- every open vitrine at once and answers with articles, each naming its
-- shop — the opposite of the directory (053), which lists shops and lets
-- the shopper walk in.
--
-- Same posture as every street read (052): a SECURITY DEFINER function that
-- names its columns and is granted to anon, returning only what a window
-- shows — name, price, in stock or not, a photo, the shop and where it is.
-- Never a cost, a count, an unpublished article, or a shop that is closed,
-- suspended or archived.
--
-- Matching is accent-blind on purpose: names are typed by shopkeepers in
-- French, with and without accents ("Café" and "cafe" are the same word to
-- a shopper). Folding is done here with translate() rather than the
-- unaccent extension so the function carries no dependency the database
-- might not have.
-- ============================================================

-- Lower-case and strip the accents French product names actually carry.
-- Immutable, so it could back an index later if catalogues grow.
create or replace function fold_search_text(p_text text)
returns text
language sql
immutable
set search_path = public
as $$
    select translate(lower(coalesce(p_text, '')),
                     'àâäáãéèêëíîïóôöõúùûüçñ',
                     'aaaaaeeeeiiiooooouuuucn');
$$;

-- The search. Two letters at least — one letter is browsing, and browsing
-- is the directory's job. Fifty rows at most: a longer answer is a
-- catalogue, and the query can always be narrowed. Matches that start the
-- name come before matches buried in it; in stock comes before out; then
-- nearest, when the shopper said where they are; then the name itself.
create or replace function search_products(
    p_query text,
    p_lat   double precision default null,
    p_lng   double precision default null
)
returns table (
    id          uuid,
    name        text,
    sale_price  numeric,
    in_stock    boolean,
    photo_key   text,
    shop_name   text,
    shop_slug   text,
    currency    text,
    shop_lat    double precision,
    shop_lng    double precision,
    distance_km double precision
)
language sql
stable
security definer
set search_path = public
as $$
    with q as (
        -- Escape the pattern characters so a shopper typing "%" or "_"
        -- searches for those characters instead of everything.
        select fold_search_text(btrim(coalesce(p_query, ''))) as folded
    ),
    hits as (
        select p.id, p.name, p.sale_price, (p.quantity > 0) as in_stock,
               (select d.r2_key from documents d
                 where d.product_id = p.id
                 order by coalesce(d.captured_at, d.created_at) desc
                 limit 1) as photo_key,
               o.name as shop_name, o.slug as shop_slug,
               o.default_currency as currency,
               o.lat as shop_lat, o.lng as shop_lng,
               case
                   when p_lat is null or p_lng is null
                     or o.lat is null or o.lng is null then null
                   else 6371.0 * 2 * asin(sqrt(
                            power(sin(radians(o.lat - p_lat) / 2), 2)
                          + cos(radians(p_lat)) * cos(radians(o.lat))
                          * power(sin(radians(o.lng - p_lng) / 2), 2)))
               end as distance_km,
               position((select folded from q) in fold_search_text(p.name))
                   as hit_at
        from products p
        join orgs o on o.id = p.org_id
        where length((select folded from q)) >= 2
          and fold_search_text(p.name) like
              '%' || replace(replace(replace((select folded from q),
                    '\', '\\'), '%', '\%'), '_', '\_') || '%'
          and p.is_active
          and p.is_published
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
    )
    select h.id, h.name, h.sale_price, h.in_stock, h.photo_key,
           h.shop_name, h.shop_slug, h.currency,
           h.shop_lat, h.shop_lng, h.distance_km
    from hits h
    order by (h.hit_at = 1) desc, h.in_stock desc,
             (h.distance_km is null), h.distance_km, h.name, h.shop_name
    limit 50;
$$;

-- ------------------------------------------------------------
-- Who may call what: the street asks, nobody writes
-- ------------------------------------------------------------
revoke execute on function fold_search_text(text) from public;
revoke execute on function search_products(text, double precision, double precision) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function search_products(text, double precision, double precision) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function search_products(text, double precision, double precision) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
