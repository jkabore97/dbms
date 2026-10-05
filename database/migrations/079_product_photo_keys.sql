-- ============================================================
-- 079_product_photo_keys.sql — every article's picture, in one call.
--
-- The Articles page showed names and numbers only. The owner wants each
-- article's photograph on it, as a list or as cards. An article's picture
-- is its most recent photograph — the rule the vitrine and the search have
-- used since 059 — and asking product_photos() once per article would be a
-- request per row on a market connection. This answers for the whole shop.
--
-- SECURITY INVOKER: documents' own policies decide what the caller may
-- see, exactly as for product_photos(). PDFs (a delivery note filed against
-- the article) are left out: they are not a picture of it.
-- ============================================================

create or replace function product_photo_keys(p_org_id uuid)
returns table (product_id uuid, photo_key text)
language sql
stable
security invoker
set search_path = public
as $$
    select distinct on (d.product_id) d.product_id, d.r2_key
    from documents d
    where d.org_id = p_org_id
      and d.product_id is not null
      and coalesce(d.content_type, '') not ilike '%pdf%'
    order by d.product_id, coalesce(d.captured_at, d.created_at) desc;
$$;

revoke execute on function product_photo_keys(uuid) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function product_photo_keys(uuid) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function product_photo_keys(uuid) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
