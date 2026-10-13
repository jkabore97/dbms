-- ============================================================
-- 131_catalogue_backfill.sql — batch 134: the folded bars' database side,
-- an association's Catalogue, « Vous êtes ici pour… », and the existing
-- businesses given what a new one gets.
--
--   1. An association's Catalogue (the owner: « associations need items
--      and service in their catalog. Not very similar to the shop »).
--      Nothing in the database ever stopped an association's articles:
--      products' row security is the business's members' (is_org_member,
--      can_write_org, feature_access 'products'), ensure_product and
--      place_order ask no kind, storefront_products shows every published
--      article (vitrine_shows: only Mara's switchboard hides), an order
--      collected books its sale on « Ventes » through ensure_account —
--      made the first time, an association's books included — and its
--      vitrine opens from one item (vitrine_min). What was missing was the
--      app's door (a tab) and one count: home_counts said « articles »
--      (at zero, or under their alert level) for a shop and a farm only.
--      It now says it for an association too — Catalogue's red number.
--      The rest of the counts are unchanged, for every kind.
--
--   2. « Vous êtes ici pour… » — one question after sign-up (Acheter /
--      Vendre ou gérer / Livrer / Je choisirai plus tard), asked once per
--      account and never of somebody who already has a business.
--      profiles.arrival_asked_at (when it was answered) and
--      profiles.arrival_intent ('buy', 'sell', 'deliver', 'later').
--        * arrival_pending(): true for a signed-in account that is new
--          here — no answer yet, no business, not Mara's own, not a
--          trainer, no order placed, no courier's application, no
--          invitation waiting for its number or e-mail — false for
--          everybody else, a stranger included (134's review: every
--          account from before 131 has no answer; a shopper who has
--          ordered, a courier, somebody invited must not be met with
--          « Bienvenue ! »);
--        * arrival_answer(intent): the answer, for the caller's own
--          account only; the first answer's time is kept (asked once).
--      Both SECURITY DEFINER with a pinned search path — they read and
--      write only what concerns auth.uid() (arrival_pending reads its
--      e-mail in auth.users, its orders, its courier rows, which the
--      caller's own RLS may not show), and the new columns are updatable
--      by nobody directly (profiles' UPDATE is granted column by column)
--      — closed to PUBLIC and anon (063), open to authenticated. An app with no 131 behind it asks nothing: the call
--      fails, the question is not shown.
--
--   3. « Suivre le stock » (134's review): products.stock_tracked, true
--      for every row there is. An article not followed — a ticket, a book
--      sold at the door, a shop that does not count — has no count: never
--      « épuisé » on the vitrine, ordered in any number, never « bas »,
--      moved by nothing. Section 3 below lists every function that reads
--      a count for the vitrine or for ordering.
--
--   4. The backfill (the owner: « if you find a business, an association
--      or a farm that do not have a feature that all new businesses are
--      supposed to have, just apply that to them directly »). What a new
--      business gets — org_create_core: its owner and its kind's chart of
--      accounts (seed_retail_accounts, seed_farm_accounts,
--      seed_church_accounts); over time: Le Chemin's steps reached
--      (path_sync, run by the triggers on what the business does) — was
--      compared with the live businesses (read only, October 12):
--        * the chart of accounts: every live business has its kind's
--          full seed (retail 8 codes, farm 16, association 14) — 0 rows
--          to add; the step below is kept, idempotent, for any database
--          that is behind (insert … on conflict do nothing: an account
--          the owner renamed or switched off — is_active = false — keeps
--          its code, so it is never touched);
--        * Le Chemin: one step reached and never marked (a shop whose
--          articles passed the goal before anything triggered path_sync
--          again): path_sync, for every live shop and farm. It marks what
--          is reached and pays the step's cauris once (on conflict do
--          nothing), exactly as the next sale would have; a step not
--          reached stays open. Associations have no Chemin (097).
--      Not touched, on purpose:
--        * showcase businesses (094): Mara's examples, not anybody's;
--        * orgs.progress_since NULL on the businesses from before 085:
--          that is « on the street » — they keep every tool they had —
--          not a missing feature; filling it would lock them;
--        * orgs.storefront_enabled false, orgs.association_kind NULL: an
--          owner's choice cannot be told from « never had it » there, so
--          nothing is decided for them;
--        * the owners' dial (org_feature_rules) and Mara's switchboard
--          (feature_rules): choices, never filled in.
--
-- Shop, farm and association (CLAUDE.md):
--   * shop: home_counts unchanged; the backfill's chart (none missing)
--     and Le Chemin (one step); « Suivre le stock » offered, on by default;
--   * farm: home_counts unchanged; the chart (none missing) and Le Chemin;
--     « Suivre le stock » offered, on by default;
--   * association: home_counts counts its articles (those followed); the
--     chart (none missing); no Chemin; « Suivre le stock » off by default;
--   * everybody without a business: the question, once.
-- Re-runnable: create or replace, add column if not exists, the backfill
-- idempotent.
-- ============================================================

-- ------------------------------------------------------------
-- 0. « Suivre le stock » (see 3): the column first — the functions below
--    read it.
-- ------------------------------------------------------------
alter table products add column if not exists stock_tracked boolean not null default true;

-- ------------------------------------------------------------
-- 1. Catalogue's red number for an association too
-- ------------------------------------------------------------
create or replace function home_counts(p_org uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
    v_kind      text;
    v_orders    int := 0;
    v_bookings  int := 0;
    v_articles  int := 0;
    v_invoices  int := 0;
    v_credit    int := 0;
    v_invites   int := 0;
    v_supplies  int := 0;
    v_livestock int := 0;
begin
    if p_org is null or not is_org_member(p_org) then
        return null;
    end if;
    select profile into v_kind from orgs where id = p_org;

    -- Orders not answered yet; a basket of services only is a booking.
    select count(*) filter (where not x.booking), count(*) filter (where x.booking)
      into v_orders, v_bookings
      from (select exists (select 1 from order_lines l where l.order_id = o.id)
                   and not exists (select 1 from order_lines l
                                    where l.order_id = o.id and not l.is_service) as booking
              from orders o
             where o.org_id = p_org and o.status = 'pending'
               and o.proposed_for is null) x;

    -- 131: an association's articles (its Catalogue) are counted too.
    if v_kind in ('retail', 'farm', 'association', 'church') then
        select count(*) into v_articles
          from products p
         where p.org_id = p_org and p.is_active and not p.is_service
           and p.stock_tracked
           and (p.quantity <= 0 or (p.low_stock_at is not null and p.quantity <= p.low_stock_at));
    end if;

    select count(*) into v_invoices
      from invoices i
     where i.org_id = p_org and i.cancelled_at is null
       and i.due_on is not null and i.due_on < current_date
       and i.total > coalesce((select sum(ip.amount) from invoice_payments ip
                                where ip.invoice_id = i.id), 0);

    -- A due date on a credit is 117's; before it, nothing is « overdue ».
    if exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'debts'
                  and column_name = 'due_on') then
        execute 'select count(*) from debts d
                  where d.org_id = $1 and d.due_on < current_date
                    and d.amount > coalesce((select sum(dp.amount) from debt_payments dp
                                              where dp.debt_id = d.id), 0)'
           into v_credit using p_org;
    end if;

    select count(*) into v_invites
      from pending_invitations pi
     where pi.org_id = p_org and pi.claimed_at is null and pi.expires_at > now();

    if v_kind = 'farm' then
        select count(*) into v_supplies from stock_on_hand(p_org) s where s.below_reorder;
        select count(*) into v_livestock
          from flocks f
         where f.org_id = p_org and f.closed_on is null
           and not exists (select 1 from flock_events e
                            where e.flock_id = f.id and e.occurred_at >= current_date)
           and not exists (select 1 from egg_production g
                            where g.flock_id = f.id and g.produced_on = current_date);
    end if;

    return jsonb_build_object(
        'orders', v_orders, 'bookings', v_bookings, 'articles', v_articles,
        'invoices', v_invoices, 'credit', v_credit, 'invitations', v_invites,
        'supplies', v_supplies, 'livestock', v_livestock);
end;
$$;

-- ------------------------------------------------------------
-- 2. « Vous êtes ici pour… », once per account
-- ------------------------------------------------------------
alter table profiles add column if not exists arrival_asked_at timestamptz;
alter table profiles add column if not exists arrival_intent text;

do $$ begin
    if not exists (select 1 from pg_constraint
                    where conname = 'profiles_arrival_intent_check') then
        alter table profiles add constraint profiles_arrival_intent_check
            check (arrival_intent is null
                   or arrival_intent in ('buy', 'sell', 'deliver', 'later'));
    end if;
end $$;

create or replace function arrival_pending()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    -- Only somebody who is new here: an account that has already done
    -- something on Mara — ordered from a vitrine, applied to deliver, is a
    -- trainer, or has an invitation waiting for its number or e-mail — knows
    -- why it came, and is not asked (134's review: every account before 131
    -- has no answer, and a shopper with orders must not be greeted with
    -- « Bienvenue ! »).
    select auth.uid() is not null
       and exists (select 1 from profiles p
                    where p.id = auth.uid()
                      and p.arrival_asked_at is null
                      and not coalesce(p.is_platform_admin, false)
                      and not coalesce(p.is_trainer, false)
                      and not exists (
                          select 1 from pending_invitations pi
                           where pi.claimed_at is null and pi.expires_at > now()
                             and ((p.phone is not null and pi.phone = p.phone)
                                  or (pi.email is not null and lower(pi.email) =
                                      (select lower(u.email) from auth.users u
                                        where u.id = auth.uid())))))
       and not exists (select 1 from memberships m where m.user_id = auth.uid())
       and not exists (select 1 from orders o where o.customer_id = auth.uid())
       and not exists (select 1 from couriers c where c.user_id = auth.uid())
       and not exists (select 1 from courier_applications a where a.user_id = auth.uid());
$$;

create or replace function arrival_answer(p_intent text)
returns void
language plpgsql
volatile
security definer
set search_path = public, auth
as $$
declare
    v_intent text := lower(btrim(coalesce(p_intent, '')));
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord.';
    end if;
    if v_intent not in ('buy', 'sell', 'deliver', 'later') then
        raise exception 'Réponse inconnue : %', p_intent;
    end if;
    update profiles
       set arrival_intent   = v_intent,
           arrival_asked_at = coalesce(arrival_asked_at, now())
     where id = auth.uid();
end;
$$;

revoke execute on function arrival_pending()     from public;
revoke execute on function arrival_answer(text)  from public;
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function arrival_pending()    from anon;
        revoke execute on function arrival_answer(text) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function arrival_pending()    to authenticated;
        grant execute on function arrival_answer(text) to authenticated;
    end if;
end $$;

-- ------------------------------------------------------------
-- 3. « Suivre le stock » (134's review): an article whose count is not
--    followed is never « épuisé »
-- ------------------------------------------------------------
-- products.stock_tracked (above), true for every row there is — nothing
-- changes for a shop, a farm or an association that has articles today —
-- and true for a new one unless the app says otherwise: the article form
-- asks « Suivre le stock », off by default for an association (a ticket,
-- a book sold at the door). Not followed:
--   * its count is zero and stays zero (trg_service_no_stock, below): a
--     till sale, an order accepted or delivered, a cancellation, a
--     delivery received all write `quantity ± n`, and land on zero; never
--     « bas », never Catalogue's red number (home_counts, above), never a
--     « Stock bas » ring (low_stock_at is cleared);
--   * the vitrine shows it « en stock » and lets it be ordered in any
--     number: storefront_products, storefront_stock (no cap: null, as for
--     a service), storefront_featured, storefront_previews,
--     search_products, my_order_basket (« Commander à nouveau ») and
--     place_order's « épuisé » check; trg_order_moves_stock moves nothing
--     for it; request_promotion asks no stock of it.
-- Every function below is its latest definition with only that added;
-- `create or replace` keeps each one's grants (063: the vitrine's are
-- anon's, place_order and my_order_basket the signed-in's).
-- Shop, farm, association: the same column and rules for all three; only
-- the form's default differs (association: off).

-- trg_service_no_stock: 098_services.sql's, with « not followed » (131).
create or replace function trg_service_no_stock()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    if new.is_service then
        if new.is_ingredient then
            raise exception 'Un service ne peut pas être un ingrédient';
        end if;
        -- An article that still has goods on the shelf does not quietly
        -- become a service: its count would be zeroed with no trace.
        if tg_op = 'UPDATE' and not old.is_service and old.quantity <> 0 then
            raise exception 'Cet article a du stock : il ne peut pas devenir un service';
        end if;
        new.quantity     := 0;
        new.low_stock_at := null;
        new.expires_on   := null;
    -- 131: an article whose stock is not followed (a ticket, a service-like
    -- article, a shop that does not count) has no count at all: zero, never
    -- « bas », and no sale, order or delivery moves it — every one of them
    -- writes `quantity - n`, which lands here first (this trigger fires
    -- before stock_not_below_zero). Stopping to count an article that still
    -- has goods would zero them with no trace: the count goes to zero in
    -- the same change (the app's sheet sends both), or it is refused.
    elsif not coalesce(new.stock_tracked, true) then
        if tg_op = 'UPDATE' and coalesce(old.stock_tracked, true)
           and old.quantity > 0 and new.quantity > 0 then
            raise exception 'Cet article a encore du stock : mettez-le à zéro avant de ne plus le suivre';
        end if;
        new.quantity     := 0;
        new.low_stock_at := null;
    end if;
    return new;
end;
$$;

-- storefront_stock: 110_vitrine_switches.sql's, with « not followed » (131).
create or replace function storefront_stock(p_slug text)
returns table (id uuid, stock_left numeric)
language sql
stable
security definer
set search_path = public
as $$
    select p.id,
           case when p.is_service
                  or not p.stock_tracked
                  or p.available_from > (now() at time zone 'Africa/Ouagadougou')::date
                then null
                else greatest(p.quantity, 0) end
    from products p
    where p.org_id = storefront_open(p_slug)
      and p.is_active
      and p.is_published
      and vitrine_shows(p.org_id, p.is_service);
$$;

-- storefront_products: 110_vitrine_switches.sql's, with « not followed » (131).
create or replace function storefront_products(p_slug text)
returns table (
    id             uuid,
    name           text,
    sale_price     numeric,
    in_stock       boolean,
    photo_key      text,
    description    text,
    unit           text,
    available_from date,
    is_service     boolean,
    price_from     boolean
)
language sql
stable
security definer
set search_path = public
as $$
    select p.id, p.name, p.sale_price,
           (p.is_service
            or p.quantity > 0
            or not p.stock_tracked
            or p.available_from > (now() at time zone 'Africa/Ouagadougou')::date),
           (select d.r2_key from documents d
             where d.product_id = p.id and doc_is_photo(d.kind, d.content_type)
             order by coalesce(d.captured_at, d.created_at) desc
             limit 1),
           nullif(btrim(p.description), ''),
           nullif(btrim(p.unit), ''),
           case when p.available_from > (now() at time zone 'Africa/Ouagadougou')::date
                then p.available_from end,
           p.is_service,
           p.price_from
    from products p
    where p.org_id = storefront_open(p_slug)
      and p.is_active
      and p.is_published
      and vitrine_shows(p.org_id, p.is_service)
    order by p.is_service, p.name;
$$;

-- storefront_featured: 110_vitrine_switches.sql's, with « not followed » (131).
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
    select p.id, p.name, p.sale_price, (p.is_service or p.quantity > 0 or not p.stock_tracked),
           (select d.r2_key from documents d
             where d.product_id = p.id and doc_is_photo(d.kind, d.content_type)
             order by coalesce(d.captured_at, d.created_at) desc
             limit 1),
           o.name, o.slug, o.default_currency
    from products p
    join orgs o on o.id = p.org_id
    left join lateral (
        select min(pm.starts_at) as since from promotions pm
         where pm.product_id = p.id and pm.status = 'approved'
           and pm.starts_at <= now() and pm.ends_at > now()
    ) spot on true
    where (spot.since is not null or p.featured_until > now())
      and p.is_active
      and p.is_published
      and vitrine_shows(p.org_id, p.is_service)
      -- « Mettre en avant » hidden: Mara's own picks go too (a spot paid
      -- for keeps the switch from hiding anything, feature_paid).
      and not feature_hidden(o.id, 'spots')
      and o.storefront_enabled
      and o.archived_at  is null
      and o.suspended_at is null
    order by (spot.since is null), spot.since, p.featured_until desc nulls last, p.name
    limit 12;
$$;

-- search_products: 110_vitrine_switches.sql's, with « not followed » (131).
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
        select fold_search_text(btrim(coalesce(p_query, ''))) as folded
    ),
    hits as (
        select p.id, p.name, p.sale_price,
               (p.is_service or p.quantity > 0 or not p.stock_tracked) as in_stock,
               (select d.r2_key from documents d
                 where d.product_id = p.id and doc_is_photo(d.kind, d.content_type)
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
          and vitrine_shows(p.org_id, p.is_service)
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

-- storefront_previews: 110_vitrine_switches.sql's, with « not followed » (131).
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
                   order by (ph.r2_key is null),
                            (not p.is_service and p.stock_tracked and p.quantity <= 0), p.name
               ) as n
        from orgs o
        join products p on p.org_id = o.id
        left join lateral (
            select d.r2_key from documents d
             where d.product_id = p.id and doc_is_photo(d.kind, d.content_type)
             order by coalesce(d.captured_at, d.created_at) desc
             limit 1
        ) ph on true
        where o.slug = any (coalesce(p_slugs, '{}'))
          and o.id = storefront_open(o.slug)
          and p.is_active
          and p.is_published
          and vitrine_shows(p.org_id, p.is_service)
    ) x
    where x.n <= 3
    order by x.slug, x.n;
$$;

-- my_order_basket: 113_shopper_profile.sql's, with « not followed » (131).
create or replace function my_order_basket(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_order orders%rowtype;
    v_slug  text;
    v_open  uuid;
    v_lines jsonb;
    v_total int;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    select * into v_order from orders where id = p_order_id and customer_id = auth.uid();
    if not found then
        raise exception 'Commande introuvable.';
    end if;
    select slug into v_slug from orgs where id = v_order.org_id;
    v_open := storefront_open(v_slug);
    select count(*) into v_total from order_lines where order_id = p_order_id;
    if v_open is null or feature_hidden(v_open, 'online_orders') then
        return jsonb_build_object('slug', v_slug, 'closed', true,
                                  'lines', '[]'::jsonb, 'missing', v_total);
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('product_id', x.product_id, 'quantity', x.quantity)
                              order by x.name), '[]'::jsonb)
      into v_lines
      from (
        select p.id as product_id, p.name,
               case when p.is_service
                      or not p.stock_tracked
                      or p.available_from > (now() at time zone 'Africa/Ouagadougou')::date
                    then sum(l.quantity)
                    -- What is left, as it is (0.5 kg is half a kilo to sell,
                    -- not nothing): 101's storefront_stock caps the basket
                    -- the same way, and place_order takes up to it.
                    else least(sum(l.quantity), p.quantity) end as quantity
          from order_lines l
          join products p on p.id = l.product_id
         where l.order_id = p_order_id
           and p.org_id = v_open
           and p.is_active and p.is_published
           and vitrine_shows(p.org_id, p.is_service)
           and (p.is_service or p.quantity > 0 or not p.stock_tracked
                or p.available_from > (now() at time zone 'Africa/Ouagadougou')::date)
         group by p.id, p.name, p.is_service, p.stock_tracked, p.available_from, p.quantity
      ) x
     where x.quantity > 0;
    return jsonb_build_object('slug', v_slug, 'closed', false, 'lines', v_lines,
                              'missing', v_total - jsonb_array_length(v_lines));
end;
$$;

-- request_promotion: 110_vitrine_switches.sql's, with « not followed » (131).
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
    v_price   numeric;
    v_free    boolean := false;
    v_id      uuid;
    v_start   timestamptz;
begin
    if auth.uid() is null then
        raise exception 'request_promotion() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur met la boutique en avant';
    end if;
    perform feature_guard(p_org_id, 'spots');
    if p_days not in (7, 30) then
        raise exception 'Une mise en avant dure 7 ou 30 jours';
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
           and (p.quantity > 0 or not p.stock_tracked)
           and exists (select 1 from documents d where d.product_id = p.id)) then
        raise exception 'Un article mis en avant doit être sur la vitrine, avec une photo, un prix et du stock';
    end if;
    if exists (select 1 from promotions
                where org_id = p_org_id
                  and coalesce(product_id, '00000000-0000-0000-0000-000000000000'::uuid)
                    = coalesce(p_product_id, '00000000-0000-0000-0000-000000000000'::uuid)
                  and (status in ('requested', 'paid_claimed')
                       or (status = 'approved' and ends_at > now()))) then
        raise exception 'Cet emplacement est déjà demandé ou en cours';
    end if;

    v_price := spot_setting('spot_price_' || v_kind || '_' || p_days, 0);

    -- Kaj Pro's included spot: one 7-day article spot per calendar month.
    if v_kind = 'article' and p_days = 7 and org_plan(p_org_id) = 'pro'
       and (select count(*) from promotions
             where org_id = p_org_id and free
               and created_at >= date_trunc('month', now()))
           < spot_setting('pro_free_spots_month', 1) then
        v_free := true;
    end if;

    if v_free then
        v_start := next_spot_start(v_kind);
        insert into promotions (org_id, product_id, kind, days, price, currency,
                                free, status, starts_at, ends_at, requested_by,
                                decided_at)
        values (p_org_id, p_product_id, v_kind, p_days, 0,
                coalesce(v_org.default_currency, 'XOF'), true, 'approved',
                v_start, v_start + make_interval(days => p_days), auth.uid(), now())
        returning id into v_id;
    else
        insert into promotions (org_id, product_id, kind, days, price, currency,
                                requested_by)
        values (p_org_id, p_product_id, v_kind, p_days, v_price,
                coalesce(v_org.default_currency, 'XOF'), auth.uid())
        returning id into v_id;
        perform notify_platform_spot('spot_requested',
            v_org.name || ' demande une mise en avant (' || p_days || ' jours).');
    end if;
    return v_id;
end;
$$;

-- place_order: 125_service_booking.sql's, with « not followed » (131).
create or replace function place_order(
    p_slug       text,
    p_lines      jsonb,
    p_fulfilment text default 'pickup',
    p_note       text default null,
    p_address    text default null,
    p_phone      text default null,
    p_payment    text default 'cash',
    p_drop_lat   double precision default null,
    p_drop_lng   double precision default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org      uuid;
    v_id       uuid;
    v_line     jsonb;
    v_product  products%rowtype;
    v_qty      numeric;
    v_total    numeric := 0;
    v_name     text;
    v_phone    text;
    v_currency text;
    v_wave     text;
    v_fee      numeric;
    v_address  text := nullif(btrim(coalesce(p_address, '')), '');
    v_note     text := nullif(btrim(coalesce(p_note, '')), '');
    v_services boolean;
    v_short    record;
    -- 109: the switch, and the number it asks for.
    v_gate     boolean := order_phone_required();
    v_proved   text;
    -- 125: a booking (a slot given), its one line, its slot, its unit.
    v_booking  boolean;
    v_svc      int;
    v_booked   timestamptz;
    v_unit     text;
begin
    if auth.uid() is null then
        raise exception 'Sign in to order';
    end if;
    -- 109: a proved number first, when the platform asks for one — before
    -- anything is read or written, an order or a booking alike.
    if v_gate then
        v_proved := my_verified_phone();
        if v_proved is null then
            raise exception 'Vérifiez d''abord votre numéro WhatsApp';
        end if;
    end if;
    v_org := storefront_open(p_slug);
    if v_org is null then
        raise exception 'This shop is not taking orders';
    end if;
    if p_fulfilment not in ('pickup', 'delivery') then
        raise exception 'Unknown fulfilment: %', p_fulfilment;
    end if;
    if p_lines is null or jsonb_typeof(p_lines) <> 'array'
       or jsonb_array_length(p_lines) = 0 then
        raise exception 'An order needs at least one article';
    end if;

    -- 125: a line that carries a slot (« booked_for », even empty — the
    -- key is what book_service always writes) is a booking, held to every
    -- rule below. A call with no slot is 109's, word for word: the app
    -- installed before 125 (an Android or iPhone build not yet updated)
    -- still sends a basket of services with its day in the note, and it
    -- must keep working — booked_for stays null on it, and the new app
    -- shows it as it always did.
    v_booking := exists (select 1 from jsonb_array_elements(p_lines) l
                          where jsonb_typeof(l) = 'object' and l ? 'booked_for');
    if not v_booking then
        -- 109: services only is an appointment, not a parcel.
        select coalesce(bool_and(coalesce(p.is_service, false)), false)
          into v_services
          from jsonb_array_elements(p_lines) l
          left join products p
            on p.id = nullif(l ->> 'product_id', '')::uuid and p.org_id = v_org;
        if v_services then
            if p_fulfilment <> 'pickup' then
                raise exception 'Un service se réserve sur rendez-vous : pas de livraison';
            end if;
            if v_note is null then
                raise exception 'Indiquez la date et l''heure souhaitées';
            end if;
        end if;
    end if;

    -- 125: a booking is one service alone — never beside goods, never two
    -- at once. Said before the delivery rules, so the customer hears the
    -- reason that applies.
    if v_booking then
        select count(*) into v_svc
          from jsonb_array_elements(p_lines) l
          join products p
            on p.id = nullif(l ->> 'product_id', '')::uuid and p.org_id = v_org
         where p.is_service;
        if v_svc = 0 then
            raise exception 'Seul un service se réserve à une heure';
        end if;
        v_services := true;
        if jsonb_array_length(p_lines) > v_svc then
            raise exception 'Un service se réserve seul : il ne se mélange pas aux articles d''un panier';
        end if;
        if v_svc > 1 then
            raise exception 'Une réservation porte sur un seul service';
        end if;
        if p_fulfilment <> 'pickup' then
            raise exception 'Un service se réserve sur rendez-vous : pas de livraison';
        end if;
        v_line := p_lines -> 0;
        begin
            v_booked := nullif(btrim(coalesce(v_line ->> 'booked_for', '')), '')::timestamptz;
        exception when others then
            raise exception 'L''heure du rendez-vous est illisible';
        end;
        perform booking_check_slot(v_org, v_booked);
        -- How many: asked only of a service by the person or by the hour.
        select lower(btrim(coalesce(p.unit, ''))) into v_unit
          from products p
         where p.id = nullif(v_line ->> 'product_id', '')::uuid and p.org_id = v_org;
        v_qty := (v_line ->> 'quantity')::numeric;
        if v_unit in ('personne', 'heure') then
            if v_qty is null or v_qty <> trunc(v_qty) or v_qty < 1 or v_qty > 20 then
                raise exception '%', case when v_unit = 'personne'
                                          then 'De 1 à 20 personnes'
                                          else 'De 1 à 20 heures' end;
            end if;
        elsif v_qty is distinct from 1 then
            raise exception 'Ce service se réserve une fois : pas de quantité à choisir';
        end if;
    end if;

    -- 101: « Épuisé » cannot be ordered, nor more than is left.
    select p.name, p.quantity into v_short
      from jsonb_array_elements(p_lines) l
      join products p
        on p.id = nullif(l ->> 'product_id', '')::uuid and p.org_id = v_org
     where not p.is_service
       and p.stock_tracked
       and not coalesce(p.available_from > (now() at time zone 'Africa/Ouagadougou')::date, false)
       and (l ->> 'quantity') is not null
     group by p.id, p.name, p.quantity
    having sum((l ->> 'quantity')::numeric) > greatest(p.quantity, 0)
     order by p.name
     limit 1;
    if found then
        raise exception using message = stock_short_message(v_short.name, v_short.quantity),
                              errcode = 'MA001';
    end if;

    if p_fulfilment = 'delivery' and v_address is null then
        raise exception 'A delivery needs an address';
    end if;
    if (p_drop_lat is null) <> (p_drop_lng is null) then
        raise exception 'A delivery pin needs both a latitude and a longitude';
    end if;
    if p_payment not in ('cash', 'wave') then
        raise exception 'Unknown payment method: %', p_payment;
    end if;
    select wave_merchant, default_currency into v_wave, v_currency
      from orgs where id = v_org;
    if p_payment = 'wave' and v_wave is null then
        raise exception 'This shop does not take Wave';
    end if;

    select coalesce(nullif(btrim(concat_ws(' ', first_name, last_name)), ''),
                    nullif(btrim(coalesce(full_name, '')), ''),
                    'Client'),
           phone
      into v_name, v_phone
      from profiles where id = auth.uid();

    -- The fee is fixed now, from the pin the customer gave: a rate
    -- changed tomorrow does not change what was agreed today.
    if p_fulfilment = 'delivery' then
        v_fee := delivery_fee(v_org, p_drop_lat, p_drop_lng);
    end if;

    insert into orders (org_id, customer_id, customer_name, phone,
                        fulfilment, note, address, currency, payment_method,
                        drop_lat, drop_lng, delivery_fee, booked_for)
    values (v_org, auth.uid(), v_name,
            -- 109: with the switch on, the number the shop calls is the
            -- one WhatsApp proved; off, as before.
            case when v_gate then v_proved
                 else coalesce(nullif(btrim(coalesce(p_phone, '')), ''), v_phone) end,
            p_fulfilment,
            v_note,
            v_address,
            coalesce(v_currency, 'XOF'),
            p_payment,
            case when p_fulfilment = 'delivery' then p_drop_lat end,
            case when p_fulfilment = 'delivery' then p_drop_lng end,
            v_fee,
            v_booked)
    returning id into v_id;

    for v_line in select * from jsonb_array_elements(p_lines) loop
        v_qty := (v_line->>'quantity')::numeric;
        if v_qty is null or v_qty <= 0 then
            raise exception 'A quantity must be positive';
        end if;
        select * into v_product
          from products
         where id = (v_line->>'product_id')::uuid
           and org_id = v_org
           and is_active
           and is_published;
        if not found then
            raise exception 'An article is not in this shop''s window';
        end if;
        insert into order_lines (order_id, product_id, name, unit_price, quantity, is_service)
        values (v_id, v_product.id, v_product.name,
                coalesce(v_product.sale_price, 0), v_qty, v_product.is_service);
        v_total := v_total + coalesce(v_product.sale_price, 0) * v_qty;
    end loop;

    update orders set total = v_total where id = v_id;

    begin
        perform notify_org_admins(
            v_org, 'new_order',
            -- 125: a booking says its slot, as Commandes shows it; a basket
            -- of services with no slot (an older app) is 109's « demande ».
            case when v_booking
                 then 'Rendez-vous demandé par ' || v_name || ' — ' || booking_when_fr(v_booked)
                      || ' : '
                 when v_services then 'Nouvelle demande de ' || v_name || ' : '
                 else 'Nouvelle commande de ' || v_name || ' : ' end
            || to_char(v_total, 'FM999G999G999D00') || ' '
            || coalesce(v_currency, 'XOF')
            || case when p_payment = 'wave' then ' (Wave)' else '' end
            || case when v_fee is not null
                    then ' + livraison ' || to_char(v_fee, 'FM999G999G999') else '' end,
            jsonb_build_object('to', 'shop', 'order_id', v_id, 'booking', v_services,
                               'name', v_name, 'total', v_total,
                               'currency', coalesce(v_currency, 'XOF'),
                               'wave', p_payment = 'wave', 'fee', v_fee)
            || case when v_booking then jsonb_build_object('at', v_booked)
                    else '{}'::jsonb end);
    exception when others then
        null;
    end;

    return v_id;
end;
$$;

-- trg_order_moves_stock: 101_stock_farm_analytics.sql's, with « not followed » (131).
create or replace function trg_order_moves_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    r          record;
    v_actor    uuid;
    v_sale     uuid;
    v_total    numeric := 0;
    v_entry    uuid;
    v_take     numeric;
begin
    -- Handed over or delivered cannot be cancelled: its sale is in the
    -- books and its goods are gone (decide_order has no way out of it, a
    -- courier fails only in transit). A return is a Correction.
    if old.status in ('picked_up', 'delivered') and new.status = 'cancelled' then
        raise exception 'Une commande remise ou livrée ne peut plus être annulée';
    end if;

    -- Accepted (or moved on from pending by any path): the articles leave.
    if old.status = 'pending'
       and new.status not in ('pending', 'refused', 'cancelled') then
        for r in
            select l.product_id, sum(l.quantity) as qty
              from order_lines l
              join products p on p.id = l.product_id
             where l.order_id = new.id
               and not l.is_service
               and not p.is_service
               and p.stock_tracked
               -- A pre-order (083): nothing on the shelf to take yet.
               and not coalesce(p.available_from > (now() at time zone 'Africa/Ouagadougou')::date, false)
             group by l.product_id
        loop
            insert into order_stock_moves (org_id, order_id, product_id, direction, quantity)
            values (new.org_id, new.id, r.product_id, 'out', r.qty)
            on conflict (order_id, product_id, direction) do nothing;
            if found then
                update products set quantity = quantity - r.qty where id = r.product_id;
            end if;
        end loop;
    end if;

    -- Handed over or delivered: the order is a sale, booked once.
    if new.status in ('picked_up', 'delivered') then
        -- What did not leave at acceptance leaves now: an order accepted
        -- before 101, or a pre-order whose day has come. The goods are
        -- already in the customer's hands, so this takes what the shelf
        -- has and no more — a wrong count must not stop a courier at the
        -- door; the owner corrects it (Correction).
        for r in
            select l.product_id, sum(l.quantity) as qty
              from order_lines l
              join products p on p.id = l.product_id
             where l.order_id = new.id
               and not l.is_service
               and not p.is_service
               and p.stock_tracked
               and not coalesce(p.available_from > (now() at time zone 'Africa/Ouagadougou')::date, false)
               and not exists (select 1 from order_stock_moves m
                                where m.order_id = new.id and m.product_id = l.product_id
                                  and m.direction = 'out')
             group by l.product_id
        loop
            select least(r.qty, greatest(quantity, 0)) into v_take
              from products where id = r.product_id for update;
            if v_take > 0 then
                insert into order_stock_moves (org_id, order_id, product_id, direction, quantity)
                values (new.org_id, new.id, r.product_id, 'out', v_take)
                on conflict (order_id, product_id, direction) do nothing;
                if found then
                    update products set quantity = quantity - v_take where id = r.product_id;
                end if;
            end if;
        end loop;

        -- Who closed it; a courier (073) or the platform is a profile too.
        -- A write with nobody signed in falls back to the owner.
        v_actor := coalesce(auth.uid(),
                            (select m.user_id from memberships m
                              where m.org_id = new.org_id and m.role = 'owner'
                              order by m.created_at limit 1),
                            new.customer_id);

        insert into sales (org_id, kind, occurred_at, method, note, recorded_by, order_id)
        values (new.org_id, 'sale', now(), coalesce(new.payment_method, 'cash'),
                'Commande de ' || new.customer_name, v_actor, new.id)
        on conflict (order_id) do nothing
        returning id into v_sale;

        if v_sale is not null then
            -- The lines as the customer was told them; the shelf is not
            -- touched here (it moved at acceptance, or just above).
            insert into sale_lines (sale_id, product_id, name, quantity,
                                    unit_price, unit_cost, line_total)
            select v_sale, l.product_id, l.name, l.quantity, l.unit_price,
                   coalesce(p.cost_price, 0), l.quantity * l.unit_price
              from order_lines l
              left join products p on p.id = l.product_id
             where l.order_id = new.id;
            select coalesce(sum(l.quantity * l.unit_price), 0) into v_total
              from order_lines l where l.order_id = new.id;

            -- The money, as record_sale books a cash or Wave sale: the cash
            -- box (or mobile money, 037) in, 'Ventes' credited. Written here
            -- rather than through record_entry, whose can_write_org a
            -- courier closing at the door does not pass.
            if v_total > 0 then
                insert into journal_entries (org_id, label, memo, details,
                                             created_by, created_at)
                values (new.org_id, 'Vente', 'Commande de ' || new.customer_name,
                        jsonb_build_object('sale_id', v_sale, 'order_id', new.id),
                        v_actor, now())
                returning id into v_entry;
                insert into journal_lines (journal_entry_id, account_id, debit, credit)
                values (v_entry, resolve_cash_account(new.org_id,
                                     coalesce(new.payment_method, 'cash'), v_actor),
                        v_total, 0),
                       (v_entry, ensure_account(new.org_id, 'Ventes', 'income', v_actor),
                        0, v_total);
            end if;
            update sales set total = v_total, entry_id = v_entry where id = v_sale;
        end if;
    end if;

    -- Cancelled after it took: exactly what it took comes back, once.
    if new.status = 'cancelled' and old.status <> 'cancelled' then
        for r in
            select m.product_id, m.quantity
              from order_stock_moves m
             where m.order_id = new.id and m.direction = 'out'
        loop
            insert into order_stock_moves (org_id, order_id, product_id, direction, quantity)
            values (new.org_id, new.id, r.product_id, 'back', r.quantity)
            on conflict (order_id, product_id, direction) do nothing;
            if found then
                update products set quantity = quantity + r.quantity where id = r.product_id;
            end if;
        end loop;
    end if;
    return new;
end;
$$;


-- ------------------------------------------------------------
-- 4. The backfill: what every new business gets, for the old ones
-- ------------------------------------------------------------
do $$
declare
    o record;
begin
    -- The kind's chart of accounts: a missing code only (never had it).
    for o in
        select id, profile::text as kind from orgs where not showcase
    loop
        if o.kind in ('association', 'church') then
            perform seed_church_accounts(o.id);
        elsif o.kind = 'retail' then
            perform seed_retail_accounts(o.id);
        elsif o.kind = 'farm' then
            perform seed_farm_accounts(o.id);
        end if;
    end loop;

    -- Le Chemin's steps reached and never marked (097), shops and farms
    -- open today. Best-effort per business, as the triggers run it.
    for o in
        select id from orgs
         where not showcase and archived_at is null
           and profile::text in ('retail', 'farm')
    loop
        begin
            perform path_sync(o.id);
        exception when others then
            raise notice '131: Le Chemin not synced for % (%)', o.id, sqlerrm;
        end;
    end loop;
end $$;
