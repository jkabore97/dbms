-- ============================================================
-- 083_farm_vitrine.sql — a farm has a vitrine too.
--
-- The owner: "farms do not have a vitrine, fix it." The window was never
-- closed to them in the database — storefront_open() asks only that it is
-- switched on — but a farm had nothing to put in it: the vitrine shows the
-- business's articles (products), and a farm keeps flocks, herds and
-- harvests. A farm now lists what it sells as articles like a shop does
-- (« À vendre »), so the order, the basket, delivery and payment are the
-- street's own, unchanged. Two things a farm needs that a shop rarely
-- does:
--
--   1. A unit. Eggs go by the tray, maize by the sack or the kg, a guinea
--      fowl by the head: products.unit, free words (20 characters), shown
--      after the price (« 2 500 F / plateau »). Null is « l'unité ».
--   2. A date. A batch of broilers ready on the 15th, a harvest next
--      month: products.available_from. Until that day the article is on
--      the vitrine as a pre-order (« Disponible à partir du 15/11 »), and
--      it can be ordered even with nothing in stock yet — that is what a
--      pre-order is. After it, the stock decides as for any article.
--
-- storefront_products() grows two columns, so it is dropped and recreated;
-- since 063 a new function is born closed, so the street's grant is said
-- again explicitly.
-- ============================================================

alter table products add column if not exists unit text;
alter table products drop constraint if exists products_unit_length;
alter table products add constraint products_unit_length
    check (unit is null or char_length(btrim(unit)) between 1 and 20);

alter table products add column if not exists available_from date;

drop function if exists storefront_products(text);
create function storefront_products(p_slug text)
returns table (
    id             uuid,
    name           text,
    sale_price     numeric,
    in_stock       boolean,
    photo_key      text,
    description    text,
    unit           text,
    available_from date
)
language sql
stable
security definer
set search_path = public
as $$
    select p.id, p.name, p.sale_price,
           -- A pre-order is orderable before there is anything to count.
           (p.quantity > 0
            or p.available_from > (now() at time zone 'Africa/Ouagadougou')::date),
           (select d.r2_key from documents d
             where d.product_id = p.id
             order by coalesce(d.captured_at, d.created_at) desc
             limit 1),
           nullif(btrim(p.description), ''),
           nullif(btrim(p.unit), ''),
           case when p.available_from > (now() at time zone 'Africa/Ouagadougou')::date
                then p.available_from end
    from products p
    where p.org_id = storefront_open(p_slug)
      and p.is_active
      and p.is_published
    order by p.name;
$$;

revoke execute on function storefront_products(text) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function storefront_products(text) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function storefront_products(text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
