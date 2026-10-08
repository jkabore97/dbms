-- ============================================================
-- 064_product_description.sql — a few words under the article, for the street.
--
-- The owner, looking at the vitrine: "there is no description of the
-- product." A name and a price sell sugar; they do not sell a cake, a
-- pagne or a phone — the shopper needs the two lines a shopkeeper would
-- say across the counter: what size, what taste, where from. One optional
-- text on the article, written by the shop, shown on the vitrine under the
-- name. Short by constraint: 300 characters is two honest sentences, and
-- a tile that scrolls is a tile nobody reads.
--
-- storefront_products() grows a column, so it is dropped and recreated
-- (a `create or replace` cannot change a function's return table — the
-- 42P13 every reader here has met once). Since 063 a new function is born
-- closed to the street, so the grant to anon is said again, explicitly.
-- ============================================================

alter table products add column if not exists description text;

alter table products drop constraint if exists products_description_length;
alter table products add constraint products_description_length
    check (description is null or char_length(description) <= 300);

drop function if exists storefront_products(text);
create function storefront_products(p_slug text)
returns table (
    id          uuid,
    name        text,
    sale_price  numeric,
    in_stock    boolean,
    photo_key   text,
    description text
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
           nullif(btrim(p.description), '')
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
