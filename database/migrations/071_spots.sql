-- ============================================================
-- 071_spots.sql — "Mettre en avant": a shop buys a place on the street.
--
-- The October audit: 054 built an "À la une" strip and a featured_until
-- date per article, but only the platform could set it, by hand, from the
-- console. An owner could not ask for a spot, there was no price, no way
-- to pay, and nothing counted what a spot earned — nothing counted visits
-- at all, so there was no figure to sell a spot with. This is the market
-- for those spots, and the counter under it.
--
--   1. storefront_visits: per day, per shop, per article (or the shop as a
--      whole), how often it was seen, opened, added to a basket, ordered.
--      record_visit() is the street's one write; orders count themselves.
--   2. promotions: a spot asked for — an article for À la une and the top
--      of search, or the whole shop for the top of the directory — for 7
--      or 30 days at the price the platform set. Paid by Wave to the
--      platform's number like Kaj Pro (066), "J'ai payé" from the owner,
--      approved by the platform; later the payment confirmation (M9).
--   3. A fixed number of article spots run at once (spots_max_live, 8), so
--      a spot is scarce and seen. An approved spot that finds the strip
--      full starts when the earliest running one ends.
--   4. Kaj Pro includes one free 7-day article spot a month; it skips the
--      payment and the approval — it is already paid for.
--   5. The rules a spot must meet: an article needs a photo, a price and
--      stock and must be on the vitrine; the shop's window must be open.
--   6. promotion_report(): what the spot earned, over its own days.
-- ============================================================

insert into platform_settings (key, value) values
    ('spot_price_article_7',  '1000'),
    ('spot_price_article_30', '3000'),
    ('spot_price_shop_7',     '2500'),
    ('spot_price_shop_30',    '8000'),
    ('spots_max_live',        '8'),
    ('pro_free_spots_month',  '1')
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- 1. The counter
-- ------------------------------------------------------------
create table if not exists storefront_visits (
    day        date not null default current_date,
    org_id     uuid not null references orgs(id) on delete cascade,
    -- Null: the shop as a whole (its window opened).
    product_id uuid references products(id) on delete cascade,
    seen       integer not null default 0,
    opened     integer not null default 0,
    added      integer not null default 0,
    ordered    integer not null default 0
);
create unique index if not exists storefront_visits_key
    on storefront_visits (day, org_id,
        coalesce(product_id, '00000000-0000-0000-0000-000000000000'::uuid));
alter table storefront_visits enable row level security;
-- No policies: written by record_visit() and the order trigger, read by
-- promotion_report() and the owner's analytics, all as their definer.

-- The street's one write. p_kind: 'seen' (in a list), 'opened' (the shop's
-- window, or an article's sheet), 'added' (to a basket). Anyone may count;
-- the numbers are indicative, never money.
create or replace function record_visit(
    p_slug       text,
    p_kind       text,
    p_product_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org uuid := storefront_open(p_slug);
begin
    if v_org is null or p_kind not in ('seen', 'opened', 'added') then
        return;
    end if;
    if p_product_id is not null and not exists (
        select 1 from products where id = p_product_id and org_id = v_org) then
        return;
    end if;
    insert into storefront_visits (day, org_id, product_id, seen, opened, added)
    values (current_date, v_org, p_product_id,
            (p_kind = 'seen')::int, (p_kind = 'opened')::int, (p_kind = 'added')::int)
    on conflict (day, org_id,
        (coalesce(product_id, '00000000-0000-0000-0000-000000000000'::uuid)))
    do update set
        seen   = storefront_visits.seen   + excluded.seen,
        opened = storefront_visits.opened + excluded.opened,
        added  = storefront_visits.added  + excluded.added;
end;
$$;

-- The welcome page's strip, counted in one call: each article shown, once.
-- Only articles of open windows count; the rest is ignored.
create or replace function record_seen(p_product_ids uuid[])
returns void
language sql
security definer
set search_path = public
as $$
    insert into storefront_visits (day, org_id, product_id, seen)
    select current_date, p.org_id, p.id, 1
      from products p
      join orgs o on o.id = p.org_id
     where p.id = any (p_product_ids[1:24])
       and o.id = storefront_open(o.slug)
    on conflict (day, org_id,
        (coalesce(product_id, '00000000-0000-0000-0000-000000000000'::uuid)))
    do update set seen = storefront_visits.seen + 1;
$$;

-- An order counts itself, per article.
create or replace function trg_count_ordered()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org uuid;
begin
    if new.product_id is null then
        return new;
    end if;
    select org_id into v_org from orders where id = new.order_id;
    if v_org is null then
        return new;
    end if;
    insert into storefront_visits (day, org_id, product_id, ordered)
    values (current_date, v_org, new.product_id, 1)
    on conflict (day, org_id,
        (coalesce(product_id, '00000000-0000-0000-0000-000000000000'::uuid)))
    do update set ordered = storefront_visits.ordered + 1;
    return new;
end;
$$;

create or replace trigger count_ordered
after insert on order_lines
for each row execute function trg_count_ordered();

-- ------------------------------------------------------------
-- 2. The spots
-- ------------------------------------------------------------
create table if not exists promotions (
    id           uuid primary key default gen_random_uuid(),
    org_id       uuid not null references orgs(id) on delete cascade,
    -- Null for a whole-shop spot.
    product_id   uuid references products(id) on delete cascade,
    kind         text not null check (kind in ('article', 'shop')),
    days         integer not null check (days in (7, 30)),
    price        numeric(14, 2) not null default 0,
    currency     text not null default 'XOF',
    free         boolean not null default false,
    status       text not null default 'requested'
                 check (status in ('requested', 'paid_claimed', 'approved', 'refused', 'cancelled')),
    starts_at    timestamptz,
    ends_at      timestamptz,
    requested_by uuid references profiles(id),
    decided_by   uuid references profiles(id),
    decided_at   timestamptz,
    note         text,
    created_at   timestamptz not null default now(),
    check ((kind = 'article') = (product_id is not null))
);
create index if not exists promotions_running
    on promotions (starts_at, ends_at) where status = 'approved';
create index if not exists promotions_open
    on promotions (created_at desc) where status in ('requested', 'paid_claimed');
alter table promotions enable row level security;
drop policy if exists "promotions readable by members" on promotions;
create policy "promotions readable by members"
on promotions for select using (is_org_member(org_id));

create or replace function spot_setting(p_key text, p_default numeric)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((select (value #>> '{}')::numeric
                       from platform_settings where key = p_key), p_default);
$$;

-- When an approved article spot can start: now if the strip has room,
-- else when the earliest running (or queued) spot ends.
create or replace function next_spot_start(p_kind text)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
    with booked as (
        select ends_at from promotions
         where status = 'approved' and kind = p_kind and ends_at > now()
    )
    select case
        when p_kind = 'shop' then now()
        when (select count(*) from booked) < spot_setting('spots_max_live', 8)
            then now()
        else (select ends_at from booked order by ends_at
               offset greatest(0, (select count(*) from booked)
                                   - spot_setting('spots_max_live', 8)::int)
               limit 1)
    end;
$$;

-- The platform's bell (030 rings it for applications; this is the same
-- fan-out, for spots).
create or replace function notify_platform_spot(p_kind text, p_message text)
returns void
language sql
security definer
set search_path = public
as $$
    insert into notifications (recipient_id, org_id, kind, message)
    select id, null, p_kind, p_message from profiles where is_platform_admin;
$$;

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
           and coalesce(p.sale_price, 0) > 0 and p.quantity > 0
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

-- "J'ai payé": the owner says the Wave transfer went.
create or replace function claim_promotion_paid(p_promotion_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v promotions%rowtype;
begin
    select * into v from promotions where id = p_promotion_id;
    if not found or not is_org_admin(v.org_id) then
        raise exception 'Mise en avant introuvable';
    end if;
    if v.status <> 'requested' then
        raise exception 'Cette mise en avant n''attend pas de paiement';
    end if;
    update promotions set status = 'paid_claimed',
           note = nullif(btrim(coalesce(p_note, '')), '')
     where id = p_promotion_id;
    perform notify_platform_spot('spot_paid',
        (select name from orgs where id = v.org_id)
        || ' dit avoir payé sa mise en avant.');
end;
$$;

-- The platform's yes or no.
create or replace function decide_promotion(p_promotion_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v promotions%rowtype;
    v_start timestamptz;
begin
    if not exists (select 1 from profiles
                    where id = auth.uid() and is_platform_admin) then
        raise exception 'Seule la plateforme valide une mise en avant';
    end if;
    select * into v from promotions where id = p_promotion_id;
    if not found or v.status not in ('requested', 'paid_claimed') then
        raise exception 'Cette demande n''est plus en attente';
    end if;
    if p_approve then
        v_start := next_spot_start(v.kind);
        update promotions
           set status = 'approved', starts_at = v_start,
               ends_at = v_start + make_interval(days => v.days),
               decided_by = auth.uid(), decided_at = now()
         where id = p_promotion_id;
    else
        update promotions
           set status = 'refused', decided_by = auth.uid(), decided_at = now()
         where id = p_promotion_id;
    end if;
    begin
        perform notify_org_admins(v.org_id, 'spot_' || case when p_approve then 'approved' else 'refused' end,
            case when p_approve
                 then 'Votre mise en avant est validée : elle commence le '
                      || to_char(v_start at time zone 'Africa/Ouagadougou', 'DD/MM à HH24:MI') || '.'
                 else 'Votre demande de mise en avant n''a pas été retenue.' end);
    exception when others then null;
    end;
end;
$$;

-- An owner's spots, newest first, with what each earned so far.
create or replace function my_promotions(p_org_id uuid)
returns table (
    id uuid, kind text, product_id uuid, product_name text, days integer,
    price numeric, currency text, free boolean, status text,
    starts_at timestamptz, ends_at timestamptz, created_at timestamptz,
    seen bigint, opened bigint, added bigint, ordered bigint
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select p.id, p.kind, p.product_id, pr.name, p.days, p.price, p.currency,
           p.free, p.status, p.starts_at, p.ends_at, p.created_at,
           coalesce(r.seen, 0), coalesce(r.opened, 0),
           coalesce(r.added, 0), coalesce(r.ordered, 0)
    from promotions p
    left join products pr on pr.id = p.product_id
    left join lateral (
        select sum(v.seen) seen, sum(v.opened) opened,
               sum(v.added) added, sum(v.ordered) ordered
          from storefront_visits v
         where v.org_id = p.org_id
           and (p.product_id is null or v.product_id = p.product_id)
           and p.starts_at is not null
           and v.day >= (p.starts_at at time zone 'Africa/Ouagadougou')::date
           and v.day <= (least(p.ends_at, now()) at time zone 'Africa/Ouagadougou')::date
    ) r on true
    where p.org_id = p_org_id and is_org_member(p_org_id)
    order by p.created_at desc;
$$;

-- The console's queue: what waits on the platform, and what runs.
create or replace function platform_promotions()
returns table (
    id uuid, org_id uuid, org_name text, kind text, product_name text,
    days integer, price numeric, currency text, free boolean, status text,
    starts_at timestamptz, ends_at timestamptz, created_at timestamptz,
    note text
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select p.id, p.org_id, o.name, p.kind, pr.name, p.days, p.price,
           p.currency, p.free, p.status, p.starts_at, p.ends_at,
           p.created_at, p.note
    from promotions p
    join orgs o on o.id = p.org_id
    left join products pr on pr.id = p.product_id
    where exists (select 1 from profiles
                   where id = auth.uid() and is_platform_admin)
      and (p.status in ('requested', 'paid_claimed')
           or (p.status = 'approved' and p.ends_at > now()))
    order by (p.status = 'paid_claimed') desc, (p.status = 'requested') desc,
             p.created_at desc;
$$;

-- What a spot costs, for the sheet that sells it.
create or replace function spot_terms()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'article_7',  spot_setting('spot_price_article_7', 1000),
        'article_30', spot_setting('spot_price_article_30', 3000),
        'shop_7',     spot_setting('spot_price_shop_7', 2500),
        'shop_30',    spot_setting('spot_price_shop_30', 8000),
        'max_live',   spot_setting('spots_max_live', 8),
        'wave',       (select value #>> '{}' from platform_settings where key = 'platform_wave'),
        'wave_name',  (select value #>> '{}' from platform_settings where key = 'platform_wave_name'),
        'currency',   coalesce((select value #>> '{}' from platform_settings where key = 'pro_currency'), 'XOF')
    );
$$;

-- ------------------------------------------------------------
-- 3. Where the spots show
-- ------------------------------------------------------------
-- À la une: the running article spots, then 054's hand-set ones. Same
-- return type as 054, so create or replace.
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
    select p.id, p.name, p.sale_price, (p.quantity > 0),
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

-- The shops paying for the top of the directory, right now.
create or replace function storefront_spotlights()
returns table (slug text)
language sql
stable
security definer
set search_path = public
as $$
    select distinct o.slug
    from promotions pm
    join orgs o on o.id = pm.org_id
    where pm.kind = 'shop' and pm.status = 'approved'
      and pm.starts_at <= now() and pm.ends_at > now()
      and o.id = storefront_open(o.slug);
$$;

-- ------------------------------------------------------------
-- 4. Grants
-- ------------------------------------------------------------
revoke execute on function record_visit(text, text, uuid)           from public;
revoke execute on function record_seen(uuid[])                      from public;
revoke execute on function request_promotion(uuid, uuid, integer)   from public;
revoke execute on function claim_promotion_paid(uuid, text)         from public;
revoke execute on function decide_promotion(uuid, boolean)          from public;
revoke execute on function my_promotions(uuid)                      from public;
revoke execute on function platform_promotions()                    from public;
revoke execute on function spot_terms()                             from public;
revoke execute on function storefront_spotlights()                  from public;
revoke execute on function storefront_featured()                    from public;
revoke execute on function spot_setting(text, numeric)              from public;
revoke execute on function next_spot_start(text)                    from public;
revoke execute on function notify_platform_spot(text, text)         from public;

do $$
begin
    -- The street counts and reads (063 rule: say it by name).
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function record_visit(text, text, uuid) to anon;
        grant execute on function record_seen(uuid[])            to anon;
        grant execute on function storefront_spotlights()        to anon;
        grant execute on function storefront_featured()          to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function record_visit(text, text, uuid)         to authenticated;
        grant execute on function record_seen(uuid[])                    to authenticated;
        grant execute on function storefront_spotlights()                to authenticated;
        grant execute on function storefront_featured()                  to authenticated;
        grant execute on function request_promotion(uuid, uuid, integer) to authenticated;
        grant execute on function claim_promotion_paid(uuid, text)       to authenticated;
        grant execute on function decide_promotion(uuid, boolean)        to authenticated;
        grant execute on function my_promotions(uuid)                    to authenticated;
        grant execute on function platform_promotions()                  to authenticated;
        grant execute on function spot_terms()                           to authenticated;
        grant select on promotions to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
