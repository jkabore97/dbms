-- ============================================================
-- 072_console_today.sql — the console opens on today.
--
-- The October audit: the platform console opened on a table of businesses
-- under nine unlabelled icons. What waited on the platform — a business
-- application, a "J'ai payé" for Kaj Pro or a spot, a courier asking to
-- carry, an order nobody had touched — was each behind its own icon, and
-- nothing said what the platform earned or whether it was growing.
--
--   1. platform_today(): one call, four blocks —
--        todo:   what waits on the platform, each a count the console
--                links to its screen; orders stuck (pending over 2 h,
--                on the road over 3 h) are counted here too.
--        money:  this month — Pro claimed and handled, spots sold, the
--                delivery cut (067), and what the shops sold through
--                their windows.
--        growth: businesses, windows open and windows with something on
--                them, orders this week against last, shoppers new this
--                month, from the street's counter (071) the windows
--                opened this week.
--        health: businesses gone silent 30 days, open windows with an
--                empty shelf, franc CFA shops pinned outside the zone,
--                published articles without a photo.
--      Platform admins only; anyone else gets null.
--   2. send_platform_message(): the platform writes to the people who
--      answer for a business — one, or every business — through the bell
--      (030). The console's "Écrire aux boutiques".
-- ============================================================

create or replace function platform_today()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_month timestamptz := date_trunc('month', now() at time zone 'Africa/Ouagadougou')
                           at time zone 'Africa/Ouagadougou';
    v_week  timestamptz := now() - interval '7 days';
begin
    if not exists (select 1 from profiles
                    where id = auth.uid() and is_platform_admin) then
        return null;
    end if;

    return jsonb_build_object(
        'todo', jsonb_build_object(
            'applications', (select count(*) from org_applications where status = 'pending'),
            'pro_requests', (select count(*) from plan_requests where handled_at is null),
            'spots',        (select count(*) from promotions
                              where status in ('requested', 'paid_claimed')),
            'spots_paid',   (select count(*) from promotions where status = 'paid_claimed'),
            'couriers',     (select count(*) from couriers where status = 'pending'),
            'orders_stuck', (select count(*) from orders
                              where (status = 'pending' and created_at < now() - interval '2 hours')
                                 or (status in ('in_transit', 'picked_up')
                                     and updated_at < now() - interval '3 hours'))
        ),
        'money', jsonb_build_object(
            'currency', 'XOF',
            'pro',      (select coalesce(sum(amount), 0) from plan_requests
                          where handled_at >= v_month),
            'spots',    (select coalesce(sum(price), 0) from promotions
                          where status = 'approved' and not free
                            and decided_at >= v_month),
            'delivery_cut', (select coalesce(sum(platform_fee), 0) from orders
                              where status = 'delivered' and updated_at >= v_month),
            'shops_sold',   (select coalesce(sum(total), 0) from orders
                              where status = 'delivered' and updated_at >= v_month
                                and currency = 'XOF')
        ),
        'growth', jsonb_build_object(
            'businesses',     (select count(*) from orgs where archived_at is null),
            'new_month',      (select count(*) from orgs
                                where archived_at is null and created_at >= v_month),
            'windows_open',   (select count(*) from orgs
                                where storefront_enabled and archived_at is null
                                  and suspended_at is null),
            'windows_stocked', (select count(*) from orgs o
                                 where o.storefront_enabled and o.archived_at is null
                                   and o.suspended_at is null
                                   and exists (select 1 from products p
                                                where p.org_id = o.id and p.is_active
                                                  and p.is_published)),
            'orders_week',    (select count(*) from orders where created_at >= v_week),
            'orders_last_week', (select count(*) from orders
                                  where created_at >= v_week - interval '7 days'
                                    and created_at <  v_week),
            'shoppers_new',   (select count(distinct customer_id) from orders o
                                where o.created_at >= v_month
                                  and not exists (select 1 from orders e
                                                   where e.customer_id = o.customer_id
                                                     and e.created_at < v_month)),
            'windows_opened_week', (select coalesce(sum(opened), 0) from storefront_visits
                                     where product_id is null
                                       and day >= current_date - 6)
        ),
        'health', jsonb_build_object(
            'silent_30',   (select count(*) from orgs
                             where archived_at is null and suspended_at is null
                               and coalesce(last_activity_at, created_at)
                                   < now() - interval '30 days'),
            'empty_windows', (select count(*) from orgs o
                               where o.storefront_enabled and o.archived_at is null
                                 and not exists (select 1 from products p
                                                  where p.org_id = o.id and p.is_active
                                                    and p.is_published)),
            'pins_far',    (select count(*) from orgs
                             where archived_at is null and lat is not null
                               and ((default_currency = 'XOF'
                                     and not (lat between 2 and 26 and lng between -19 and 17))
                                 or (default_currency = 'XAF'
                                     and not (lat between -6 and 24 and lng between 7 and 30)))),
            'published',   (select count(*) from products p
                             join orgs o on o.id = p.org_id
                            where o.storefront_enabled and p.is_active and p.is_published),
            'no_photo',    (select count(*) from products p
                             join orgs o on o.id = p.org_id
                            where o.storefront_enabled and p.is_active and p.is_published
                              and not exists (select 1 from documents d
                                               where d.product_id = p.id))
        )
    );
end;
$$;

-- The platform writes to the businesses. Null org: every live business.
-- Returns how many people it reached.
create or replace function send_platform_message(p_org_id uuid, p_message text)
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_text  text := nullif(btrim(coalesce(p_message, '')), '');
    v_count integer;
begin
    if not exists (select 1 from profiles
                    where id = auth.uid() and is_platform_admin) then
        raise exception 'Seule la plateforme écrit aux boutiques';
    end if;
    if v_text is null then
        raise exception 'Le message est vide';
    end if;
    if length(v_text) > 500 then
        raise exception 'Un message tient en 500 caractères';
    end if;
    insert into notifications (recipient_id, org_id, kind, message)
    select distinct m.user_id, m.org_id, 'platform_message', 'Kaj : ' || v_text
      from memberships m
      join orgs o on o.id = m.org_id
     where m.role in ('owner', 'super_admin', 'admin')
       and o.archived_at is null
       and (p_org_id is null or m.org_id = p_org_id);
    get diagnostics v_count = row_count;
    return v_count;
end;
$$;

revoke execute on function platform_today()                  from public;
revoke execute on function send_platform_message(uuid, text) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function platform_today()                  to authenticated;
        grant execute on function send_platform_message(uuid, text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
