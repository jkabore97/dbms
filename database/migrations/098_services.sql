-- ============================================================
-- 098_services.sql — services in the vitrine, for shops, farms and
-- associations.
--
-- The owner: « Is it possible to post services with pricing in vitrine? …
-- Build all steps for all 3 types including associations. » Until now a
-- service could only be faked as an article with stock: at 0 it read
-- « Épuisé » and could not be ordered, and every till sale counted it down.
--
--   1. A service is a products row with is_service = true. price_from is
--      « à partir de » (the price is where it starts). The unit (083,
--      « heure », « séance », « personne ») serves services of every
--      profile. A name belongs to one kind: ensure_product takes
--      p_is_service, so adding a service never revives or converts an
--      article (retired or not) and adding an article never takes back a
--      service; a rename onto a name already held is refused in French;
--      an article with stock is never turned into a service.
--   2. A service has no stock, and that is held by the table itself, not
--      by each function that writes a count: a trigger keeps a service's
--      quantity at 0 and its low-stock threshold and expiry empty whatever
--      writes the row — record_sale() (029) and record_return() (032)
--      subtract and add as they always did and the count does not move, so
--      no « Stock bas » ever rings for it and it is in no stock value (the
--      reports read quantity > 0). A check constraint says the same, in
--      case the trigger is ever disabled. What has no sense for a service
--      is refused with a clear French word: a delivery received into stock
--      (receive_products, 016/032), being made by a production or being an
--      ingredient of one (026, 034). A service is never an ingredient.
--   3. The street: storefront_products() returns is_service and price_from
--      (the return type grows, so it is dropped and recreated and granted
--      again, as 083 did); a service is always « en stock » there, in the
--      search (059), in « À la une » (071) and on the directory cards (070).
--   4. The basket: place_order() (061) with one more rule — a basket of
--      services only is « sur rendez-vous »: fulfilment 'pickup' (no new
--      value), no delivery fee, and a note saying the date and time wanted.
--      A mixed basket is today's basket. Each order line remembers whether
--      it was a service (order_lines.is_service), and the shop's and the
--      customer's order lists (061) say so on each line. The customer's
--      notice (056's decide_order) says « Votre réservation … : terminée »
--      for such a booking, not « commande … récupérée ».
--   5. Associations get a vitrine. Nothing refused them one in the
--      database; the minimum did (092: 8 items). An association's vitrine
--      is public from 1 published item (platform setting
--      vitrine_min_items_association), the 092 minimum staying for shops
--      and farms: vitrine_min(org) says which, and storefront_open,
--      storefront_directory, vitrine_score and vitrine_checklist (092) read
--      it. For an association the photo step of the score is met without
--      a photo (its settings call one optional). Associations stay off Le
--      Chemin (097) and earn no cauris (084): untouched.
--   6. A finished order, service or not, does what it did: it moves the
--      order's status, and nothing in the books or the stock — the till
--      records the sale when the customer pays (055's comment on orders).
--      An association has no till; its treasurer records the money the way
--      its books already take it. Nothing is invented for it here.
--
-- Re-runnable (the bundle runs twice): columns if not exists, constraints
-- and triggers dropped and recreated, functions replaced, the one whose
-- return type changes dropped first.
-- ============================================================

-- ------------------------------------------------------------
-- 0. Settings
-- ------------------------------------------------------------
insert into platform_settings (key, value) values ('vitrine_min_items_association', '1')
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- 1. Columns
-- ------------------------------------------------------------
alter table products add column if not exists is_service boolean not null default false;
alter table products add column if not exists price_from boolean not null default false;

comment on column products.is_service is
    'A service (098): no stock, never « Épuisé », booked « sur rendez-vous » when alone in a basket.';
comment on column products.price_from is
    '« à partir de » (098): the sale price is where the price starts.';

alter table order_lines add column if not exists is_service boolean not null default false;

-- ------------------------------------------------------------
-- 2. A service has no stock
-- ------------------------------------------------------------
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
    end if;
    return new;
end;
$$;

drop trigger if exists service_no_stock on products;
create trigger service_no_stock
before insert or update on products
for each row execute function trg_service_no_stock();

alter table products drop constraint if exists products_service_no_stock;
alter table products add constraint products_service_no_stock
    check (not is_service or (quantity = 0 and not is_ingredient));

-- A delivery into stock, a batch made, an ingredient used: none is a service.
create or replace function trg_service_not_stocked()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if exists (select 1 from products p where p.id = new.product_id and p.is_service) then
        raise exception '%', case tg_table_name
            when 'stock_receipts'    then 'Un service n''a pas de stock : rien à réceptionner'
            when 'production_runs'   then 'Un service ne se fabrique pas'
            else 'Un service ne peut pas être un ingrédient' end;
    end if;
    return new;
end;
$$;

drop trigger if exists service_not_received on stock_receipts;
create trigger service_not_received
before insert on stock_receipts
for each row execute function trg_service_not_stocked();

drop trigger if exists service_not_made on production_runs;
create trigger service_not_made
before insert or update of product_id on production_runs
for each row execute function trg_service_not_stocked();

drop trigger if exists service_not_ingredient on production_inputs;
create trigger service_not_ingredient
before insert or update of product_id on production_inputs
for each row execute function trg_service_not_stocked();

-- ------------------------------------------------------------
-- 2b. One name, one kind
-- ------------------------------------------------------------
-- A name is claimed by one row of the business, retired or not (011's
-- products_by_name), and ensure_product (051) brings back whatever row
-- holds it. Without a word about the kind, adding the service « Lavage »
-- would revive a retired article « Lavage » and turn it into a service
-- (its count zeroed, its sales moved under the service), and a farm
-- adding « Lavage » for sale would get the service back. p_is_service says
-- which kind the caller is creating: true for « Mes services », false for
-- every article path; null (the till's and the production's lines typed
-- by name) keeps 051's behaviour, so a service can still be rung up by its
-- name. A retired row of the same kind comes back, as in 051; the other
-- kind, or an active service already there, is refused in French.
--
-- The signature grows, so the 051 one is dropped: two would make every
-- call with fewer arguments ambiguous.
drop function if exists ensure_product(uuid, text, numeric, numeric, text, date, uuid);
create or replace function ensure_product(
    p_org_id     uuid,
    p_name       text,
    p_sale_price numeric default null,
    p_cost_price numeric default null,
    p_barcode    text    default null,
    p_expires_on date    default null,
    p_actor      uuid    default null,
    p_is_service boolean default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
    v_name    text := btrim(coalesce(p_name, ''));
    v_id      uuid;
    v_service boolean;
    v_active  boolean;
begin
    if v_name = '' then
        raise exception 'A product needs a name';
    end if;

    select id, is_service, is_active into v_id, v_service, v_active
      from products
     where org_id = p_org_id and lower(btrim(name)) = lower(v_name);

    if v_id is not null and p_is_service is not null then
        if p_is_service and not v_service then
            raise exception 'Un article porte déjà ce nom';
        end if;
        if not p_is_service and v_service then
            raise exception 'Un service porte déjà ce nom';
        end if;
        if p_is_service and v_active then
            raise exception 'Un service porte déjà ce nom';
        end if;
    end if;

    if v_id is null then
        -- p_actor rather than auth.uid(): this runs as the caller (051).
        insert into products (org_id, name, sale_price, cost_price, barcode,
                              expires_on, created_by, is_service)
        values (p_org_id, v_name,
                coalesce(p_sale_price, 0), coalesce(p_cost_price, 0),
                p_barcode, p_expires_on, p_actor,
                coalesce(p_is_service, false))
        returning id into v_id;
    else
        -- 051: re-adding a name brings the row back, filling only what was
        -- missing.
        update products set
            is_active  = true,
            sale_price = case when sale_price = 0 and p_sale_price is not null
                              then p_sale_price else sale_price end,
            cost_price = case when cost_price = 0 and p_cost_price is not null
                              then p_cost_price else cost_price end,
            barcode    = coalesce(barcode, p_barcode),
            expires_on = coalesce(expires_on, p_expires_on)
        where id = v_id;
    end if;

    return v_id;
end;
$$;

-- A rename onto a name another row holds: said in French, with the kind
-- that holds it, rather than as the raw unique violation of 011's index.
create or replace function trg_product_name_free()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_service boolean;
begin
    if lower(btrim(new.name)) is distinct from lower(btrim(old.name)) then
        select p.is_service into v_service
          from products p
         where p.org_id = new.org_id
           and p.id <> new.id
           and lower(btrim(p.name)) = lower(btrim(new.name));
        if found then
            raise exception '%', case when v_service
                then 'Un service porte déjà ce nom'
                else 'Un article porte déjà ce nom' end;
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists product_name_free on products;
create trigger product_name_free
before update of name on products
for each row execute function trg_product_name_free();

-- ------------------------------------------------------------
-- 3. The minimum, by profile
-- ------------------------------------------------------------
-- What opens a vitrine: 092's minimum for a shop or a farm, one item for
-- an association (and a legacy 'church').
create or replace function vitrine_min(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case when o.profile in ('church', 'association')
                then greatest(cauris_param('vitrine_min_items_association', 1), 1)
                else cauris_param('vitrine_min_items', 8) end
      from orgs o where o.id = p_org_id;
$$;

-- 092's door, with the minimum by profile.
create or replace function storefront_open(p_slug text)
returns uuid
language sql
stable
security definer
set search_path = public, auth
as $$
    select o.id
    from orgs o
    where o.slug = lower(btrim(coalesce(p_slug, '')))
      and o.storefront_enabled
      and o.archived_at  is null
      and o.suspended_at is null
      and (vitrine_items(o.id) >= vitrine_min(o.id)
           or exists (select 1 from memberships m
                       where m.org_id = o.id and m.user_id = auth.uid()));
$$;

-- 092's score: the first step is the minimum of this business's profile.
-- An association's photo step is met without a photo: its settings say a
-- photo is optional (« Facultative : la salle, l'atelier… »), and a service
-- is read, not looked at — so one service, a blurb and a phone put it on
-- the street (4 of 6, over 085's 60 %), as the settings promise.
create or replace function vitrine_score(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select (100 * (
        (published >= greatest(vitrine_min(o_id), 1))::int
      + (association or with_photo >= 3
         or (published > 0 and with_photo >= published))::int
      + blurb::int + phone::int + address::int + pin::int) / 6.0)::int
    from (
        select
            o.id as o_id,
            o.profile in ('church', 'association') as association,
            (select count(*) from products p
              where p.org_id = o.id and p.is_active and p.is_published) as published,
            (select count(*) from products p
              where p.org_id = o.id and p.is_active and p.is_published
                and exists (select 1 from documents d where d.product_id = p.id)) as with_photo,
            nullif(btrim(coalesce(o.storefront_blurb, '')), '') is not null as blurb,
            nullif(btrim(coalesce(o.phone, '')), '') is not null as phone,
            nullif(btrim(coalesce(o.address, '')), '') is not null as address,
            (o.lat is not null and o.lng is not null) as pin
        from orgs o where o.id = p_org_id
    ) x;
$$;

-- 092's checklist: the minimum by profile, and how many services are on.
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
        'min_items',   vitrine_min(o.id),
        'active',      (select count(*) from products p
                         where p.org_id = o.id and p.is_active and not p.is_ingredient),
        'published',   (select count(*) from products p
                         where p.org_id = o.id and p.is_active and p.is_published),
        'services',    (select count(*) from products p
                         where p.org_id = o.id and p.is_active and p.is_published
                           and p.is_service),
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

-- 092's street, with the minimum by profile.
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
          and vitrine_items(o.id) >= greatest(vitrine_min(o.id), 1)
          and (o.progress_since is null
               or vitrine_score(o.id) >= cauris_param('progress_street_pct', 60))
    ) d
    order by (d.distance_km is null), d.distance_km, d.name;
$$;

-- ------------------------------------------------------------
-- 4. The street
-- ------------------------------------------------------------
-- 083's window, with is_service and price_from. A service is always
-- orderable; the articles come first, then the services.
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
           -- A service has no count; a pre-order is orderable before there
           -- is anything to count.
           (p.is_service
            or p.quantity > 0
            or p.available_from > (now() at time zone 'Africa/Ouagadougou')::date),
           (select d.r2_key from documents d
             where d.product_id = p.id
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
    order by p.is_service, p.name;
$$;

-- 059's search: a service is never « épuisé ».
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
        select p.id, p.name, p.sale_price,
               (p.is_service or p.quantity > 0) as in_stock,
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

-- 071's « À la une »: a service is never « épuisé ».
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
    select p.id, p.name, p.sale_price, (p.is_service or p.quantity > 0),
           (select d.r2_key from documents d
             where d.product_id = p.id
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
      and o.storefront_enabled
      and o.archived_at  is null
      and o.suspended_at is null
    order by (spot.since is null), spot.since, p.featured_until desc nulls last, p.name
    limit 12;
$$;

-- 070's cards: a service is not pushed back as if it were sold out.
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
                            (not p.is_service and p.quantity <= 0), p.name
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
-- 5. The basket
-- ------------------------------------------------------------
-- 061's order, plus: a basket of services only is « sur rendez-vous » —
-- picked up, never delivered, with the date and time wanted in the note.
-- Each line remembers whether it was a service.
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
begin
    if auth.uid() is null then
        raise exception 'Sign in to order';
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

    -- Services only: an appointment, not a parcel. Said before the
    -- delivery rules, so the customer hears the reason that applies.
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
                        drop_lat, drop_lng, delivery_fee)
    values (v_org, auth.uid(), v_name,
            coalesce(nullif(btrim(coalesce(p_phone, '')), ''), v_phone),
            p_fulfilment,
            v_note,
            v_address,
            coalesce(v_currency, 'XOF'),
            p_payment,
            case when p_fulfilment = 'delivery' then p_drop_lat end,
            case when p_fulfilment = 'delivery' then p_drop_lng end,
            v_fee)
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
            case when v_services then 'Nouvelle demande de ' else 'Nouvelle commande de ' end
            || v_name || ' : '
            || to_char(v_total, 'FM999G999G999D00') || ' '
            || coalesce(v_currency, 'XOF')
            || case when p_payment = 'wave' then ' (Wave)' else '' end
            || case when v_fee is not null
                    then ' + livraison ' || to_char(v_fee, 'FM999G999G999') else '' end);
    exception when others then
        null;
    end;

    return v_id;
end;
$$;

-- 061's lists, each line saying whether it is a service. Same return
-- types (the lines are jsonb), so replaced in place.
create or replace function my_orders()
returns table (
    id             uuid,
    org_id         uuid,
    shop_name      text,
    shop_slug      text,
    status         text,
    fulfilment     text,
    note           text,
    address        text,
    phone          text,
    total          numeric,
    currency       text,
    created_at     timestamptz,
    courier_name   text,
    payment_method text,
    paid_at        timestamptz,
    shop_wave      text,
    delivery_fee   numeric,
    lines          jsonb
)
language sql
stable
security definer
set search_path = public
as $$
    select o.id, o.org_id, g.name, g.slug, o.status, o.fulfilment,
           o.note, o.address, o.phone, o.total, o.currency, o.created_at,
           (select coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                            nullif(btrim(coalesce(p.full_name, '')), ''))
              from profiles p where p.id = o.courier_id),
           o.payment_method, o.paid_at, g.wave_merchant, o.delivery_fee,
           (select coalesce(jsonb_agg(jsonb_build_object(
                       'name', l.name, 'unit_price', l.unit_price,
                       'quantity', l.quantity, 'is_service', l.is_service)
                       order by l.name), '[]'::jsonb)
              from order_lines l where l.order_id = o.id)
      from orders o
      join orgs g on g.id = o.org_id
     where o.customer_id = auth.uid()
     order by (o.status in ('pending', 'accepted', 'ready', 'in_transit')) desc,
              o.created_at desc;
$$;

create or replace function shop_orders(p_org_id uuid)
returns table (
    id             uuid,
    customer_name  text,
    phone          text,
    status         text,
    fulfilment     text,
    note           text,
    address        text,
    drop_lat       double precision,
    drop_lng       double precision,
    total          numeric,
    currency       text,
    created_at     timestamptz,
    courier_name   text,
    payment_method text,
    paid_at        timestamptz,
    delivery_fee   numeric,
    lines          jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if not is_org_member(p_org_id) then
        raise exception 'Only the shop sees its orders';
    end if;
    return query
    select o.id, o.customer_name, o.phone, o.status, o.fulfilment,
           o.note, o.address, o.drop_lat, o.drop_lng,
           o.total, o.currency, o.created_at,
           (select coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                            nullif(btrim(coalesce(p.full_name, '')), ''))
              from profiles p where p.id = o.courier_id),
           o.payment_method, o.paid_at, o.delivery_fee,
           (select coalesce(jsonb_agg(jsonb_build_object(
                       'name', l.name, 'unit_price', l.unit_price,
                       'quantity', l.quantity, 'is_service', l.is_service)
                       order by l.name), '[]'::jsonb)
              from order_lines l where l.order_id = o.id)
      from orders o
     where o.org_id = p_org_id
     order by (o.status in ('pending', 'accepted', 'ready', 'in_transit')) desc,
              o.created_at desc;
end;
$$;

-- 056's answer, in a booking's words: a basket of services only (picked
-- up, every line a service) is « Votre réservation », and its end is
-- « terminée » — nobody collects a haircut. Everything else as in 056.
create or replace function decide_order(p_order_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_order   orders%rowtype;
    v_ok      boolean;
    v_booking boolean;
begin
    select * into v_order from orders where id = p_order_id;
    if not found then
        raise exception 'No such order';
    end if;
    if not can_write_org(v_order.org_id) then
        raise exception 'Only the shop can answer its orders';
    end if;

    v_ok := case v_order.status
        when 'pending'    then p_status in ('accepted', 'refused')
        when 'accepted'   then p_status in ('ready', 'picked_up', 'delivered', 'cancelled')
        when 'ready'      then p_status in ('picked_up', 'delivered', 'cancelled')
        -- Once the parcel is on a motorbike the shop can only confirm the
        -- end of the journey, not rewrite it.
        when 'in_transit' then p_status = 'delivered'
        else false
    end;
    if not v_ok then
        raise exception 'An order cannot go from % to %', v_order.status, p_status;
    end if;
    if p_status = 'picked_up' and v_order.fulfilment = 'delivery' then
        raise exception 'A delivery is delivered, not picked up';
    end if;
    if p_status = 'delivered' and v_order.fulfilment = 'pickup' then
        raise exception 'A pickup is picked up, not delivered';
    end if;

    update orders
       set status     = p_status,
           updated_at = now(),
           decided_at = coalesce(decided_at, now())
     where id = p_order_id;

    v_booking := v_order.fulfilment = 'pickup'
        and exists (select 1 from order_lines l where l.order_id = p_order_id)
        and not exists (select 1 from order_lines l
                         where l.order_id = p_order_id and not l.is_service);

    begin
        insert into notifications (recipient_id, org_id, kind, message)
        select v_order.customer_id, v_order.org_id, 'order_' || p_status,
               case when v_booking then 'Votre réservation chez '
                    else 'Votre commande chez ' end
               || o.name || ' : '
               || case p_status
                    when 'accepted'  then 'acceptée'
                    when 'ready'     then 'prête'
                    when 'picked_up' then case when v_booking then 'terminée'
                                               else 'récupérée' end
                    when 'delivered' then 'livrée'
                    when 'refused'   then 'refusée'
                    else 'annulée' end
          from orgs o where o.id = v_order.org_id;
        -- A courier who already took the job hears about a cancellation.
        if p_status = 'cancelled' and v_order.courier_id is not null then
            insert into notifications (recipient_id, org_id, kind, message)
            values (v_order.courier_id, v_order.org_id, 'delivery_cancelled',
                    'La livraison pour ' || v_order.customer_name
                    || ' a été annulée par la boutique');
        end if;
    exception when others then
        null;
    end;
end;
$$;

-- ------------------------------------------------------------
-- 6. Grants (063: a new function is born closed to anon and PUBLIC)
-- ------------------------------------------------------------
-- vitrine_min is read only inside the SECURITY DEFINER functions above
-- (as their owner); no client calls it, so nobody else may.
revoke execute on function trg_service_no_stock()           from public;
revoke execute on function trg_service_not_stocked()        from public;
revoke execute on function trg_product_name_free()          from public;
revoke execute on function vitrine_min(uuid)                from public;
revoke execute on function storefront_products(text)        from public;
revoke execute on function ensure_product(uuid, text, numeric, numeric, text, date, uuid, boolean) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function trg_service_no_stock()    from anon;
        revoke execute on function trg_service_not_stocked() from anon;
        revoke execute on function trg_product_name_free()   from anon;
        revoke execute on function vitrine_min(uuid)         from anon;
        revoke execute on function ensure_product(uuid, text, numeric, numeric, text, date, uuid, boolean) from anon;
        grant execute on function storefront_products(text)  to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function trg_service_no_stock()    from authenticated;
        revoke execute on function trg_service_not_stocked() from authenticated;
        revoke execute on function trg_product_name_free()   from authenticated;
        revoke execute on function vitrine_min(uuid)         from authenticated;
        grant execute on function ensure_product(uuid, text, numeric, numeric, text, date, uuid, boolean) to authenticated;
        grant execute on function storefront_products(text)  to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function ensure_product(uuid, text, numeric, numeric, text, date, uuid, boolean) to service_role;
    end if;
end $$;

notify pgrst, 'reload schema';
