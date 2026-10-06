-- ============================================================
-- 095_showcase_order.sql — the vitrines d'exemple with the most photos
-- first.
--
-- The owner, looking at the street: « Please prioritize items you have
-- the pictures of. » showcase_slugs() (094) now names the vitrines
-- d'exemple in order of how many of their articles carry a photo, so the
-- street shows the full shelves first (Rowan Bike Shop, the university
-- restaurant, Tony Pizza…) and Bob Electronics, with none yet, last. The
-- app keeps that order; inside a vitrine d'exemple it puts the
-- photographed articles first.
--
-- No destructive statement: one function replaced with its own signature.
-- ============================================================

create or replace function showcase_slugs()
returns setof text
language sql
stable
security definer
set search_path = public
as $$
    select o.slug from orgs o
     where o.showcase and o.storefront_enabled
       and o.archived_at is null and o.suspended_at is null
     order by (select count(distinct d.product_id) from documents d
                 join products p on p.id = d.product_id
                where p.org_id = o.id and p.is_active and p.is_published) desc,
              o.name;
$$;

revoke execute on function showcase_slugs() from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function showcase_slugs() to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function showcase_slugs() to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
