-- 143_spots_services.sql — « Mettre en avant » for a service too.
--
-- The owner: « mettre en avant exists for articles but not for services ».
-- 139's doors asked an article spot for stock (quantity > 0, or stock not
-- followed). A service has no stock, so a service was always refused —
-- though « À la une » (136's storefront_featured) already shows a service
-- as available (p.is_service). The same test is used here: a service is
-- always « in stock ». A shop, a farm and an association alike.
--
-- request_promotion and spot_ineligible are 139's, copied verbatim but for
-- that one test (and request_promotion's refusal sentence). Same
-- signatures, so create or replace keeps 139's grants. Re-runnable.

create or replace function request_promotion(
    p_org_id     uuid,
    p_product_id uuid,
    p_days       integer
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_kind    text := case when p_product_id is null then 'shop' else 'article' end;
    v_org     orgs%rowtype;
    v_id      uuid;
begin
    if auth.uid() is null then
        raise exception 'request_promotion() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur met la boutique en avant';
    end if;
    perform feature_guard(p_org_id, 'spots');
    -- Two taps at once ask once: the second waits, then sees the first.
    perform pg_advisory_xact_lock(hashtext('request_promotion:' || p_org_id::text));
    if p_days is distinct from 7 then
        raise exception 'Une mise en avant dure 7 jours';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if not v_org.storefront_enabled then
        raise exception 'Ouvrez d''abord la vitrine';
    end if;
    if v_kind = 'article' and not exists (
        select 1 from products p
         where p.id = p_product_id and p.org_id = p_org_id
           and p.is_active and p.is_published
           and coalesce(p.sale_price, 0) > 0
           and (p.is_service or p.quantity > 0 or not p.stock_tracked)
           and exists (select 1 from documents d where d.product_id = p.id)) then
        raise exception 'Un article ou un service mis en avant doit être sur la vitrine, avec une photo et un prix (et du stock pour un article)';
    end if;
    if exists (select 1 from promotions
                where org_id = p_org_id
                  and coalesce(product_id, '00000000-0000-0000-0000-000000000000'::uuid)
                    = coalesce(p_product_id, '00000000-0000-0000-0000-000000000000'::uuid)
                  and (status in ('requested', 'paid_claimed')
                       or (status = 'approved' and ends_at > now()))) then
        raise exception 'Cet emplacement est déjà demandé ou en cours';
    end if;

    insert into promotions (org_id, product_id, kind, days, price, currency, requested_by)
    values (p_org_id, p_product_id, v_kind, 7,
            spot_zone_price(price_zone(v_org.default_currency), v_kind),
            zone_currency(v_org.default_currency), auth.uid())
    returning id into v_id;
    perform notify_platform_spot('spot_requested',
        v_org.name || ' demande une mise en avant (7 jours).');
    return v_id;
end;
$$;

create or replace function spot_ineligible(p_org uuid, p_product uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select case
        when not coalesce((select storefront_enabled from orgs where id = p_org), false) then 'vitrine'
        when feature_hidden(p_org, 'spots') then 'feature'
        when p_product is not null and not exists (
            select 1 from products p
             where p.id = p_product and p.org_id = p_org
               and p.is_active and p.is_published
               and coalesce(p.sale_price, 0) > 0
               and (p.is_service or p.quantity > 0 or not p.stock_tracked)
               and exists (select 1 from documents d where d.product_id = p.id)) then 'article'
    end;
$$;
