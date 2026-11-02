-- ============================================================
-- 165 — « Mettre en avant » for an Événementiel (batch 165).
--
-- The owner: « give them the promotion option too ». An Événementiel has
-- no vitrine and no pin; its spot (« L'événement à la une, 7 jours », the
-- same product and price as « La boutique à la une ») puts its public
-- events first in the street's « Événements », marked « Sponsorisé ».
--
--   * spot_area_queue: an Événementiel's spots queue among themselves,
--     the whole country (no pin to make an area of), the same number of
--     places (spots_max_live).
--   * spot_area_status: an Événementiel is « placed ».
--   * request_promotion, spot_ineligible: an Événementiel needs neither a
--     vitrine nor a pin — a public event to come instead ('event').
--   * street_events / street_event_row: 'sponsored', and sponsored first.
--
-- For a shop, a farm or an association: nothing changes — every branch
-- below is the Événementiel's alone, the rest 144's word for word.
-- Applies twice.
-- ============================================================

do $$ begin
    if to_regprocedure('street_events()') is null or to_regprocedure('request_promotion(uuid, uuid, integer)') is null then
        raise exception '165 needs 144 and 162 applied first';
    end if;
end $$;

-- An Événementiel with a public event to come: what its spot shows.
create or replace function events_spot_ready(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (select 1 from events e
                    where e.org_id = p_org and e.listed and e.published and e.starts_at is not null
                      and e.starts_at > now() - interval '6 hours' and e.cancelled_at is null);
$$;
revoke execute on function events_spot_ready(uuid) from public;

create or replace function spot_area_queue(p_kind text, p_org_id uuid)
returns table (taken integer, places integer, starts_at timestamptz)
language sql
stable
set search_path = public
as $$
    with me as (
        select o.lat, o.lng, o.profile::text = 'events' as events from orgs o where o.id = p_org_id
    ), live as (
        select pm.ends_at
          from promotions pm
          join orgs o on o.id = pm.org_id
          cross join me
         where pm.status = 'approved' and pm.kind = p_kind and pm.ends_at > now()
           and case when me.events then o.profile::text = 'events'
                    else o.profile::text <> 'events' and spot_in_area(me.lat, me.lng, o.lat, o.lng) end
    ), n as (
        select (select count(*) from live)::int as taken,
               spot_setting('spots_max_live', 8)::int as places
    )
    select n.taken, n.places,
           case when n.taken < n.places then now()
                else (select l.ends_at from live l
                       order by l.ends_at
                       offset greatest(0, n.taken - n.places)
                       limit 1) end
      from n;
$$;

create or replace function spot_area_status(p_org_id uuid, p_kind text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_kind  text := case when p_kind = 'shop' then 'shop' else 'article' end;
    v_org   orgs%rowtype;
    v_q     record;
begin
    if auth.uid() is null then
        raise exception 'spot_area_status() needs a signed-in caller';
    end if;
    if not (is_org_admin(p_org_id)
            or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)) then
        raise exception 'Seul un administrateur met la boutique en avant';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if not found then
        raise exception 'Entreprise introuvable';
    end if;
    -- 165: an Événementiel is shown all over the street, no pin needed.
    if (v_org.lat is null or v_org.lng is null) and v_org.profile::text <> 'events' then
        return jsonb_build_object(
            'positioned', false,
            'kind',       v_kind,
            'area_km',    spot_setting('spot_area_km', 30),
            'places',     spot_setting('spots_max_live', 8)::int);
    end if;
    select * into v_q from spot_area_queue(v_kind, p_org_id);
    return jsonb_build_object(
        'positioned', true,
        'kind',       v_kind,
        'area_km',    spot_setting('spot_area_km', 30),
        'places',     v_q.places,
        'taken',      v_q.taken,
        'free',       greatest(0, v_q.places - v_q.taken),
        'next_at',    case when v_q.taken >= v_q.places then v_q.starts_at end);
end;
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
    v_id      uuid;
begin
    if auth.uid() is null then
        raise exception 'request_promotion() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur met la boutique en avant';
    end if;
    perform feature_guard(p_org_id, 'spots');
    perform pg_advisory_xact_lock(hashtext('request_promotion:' || p_org_id::text));
    if p_days is distinct from 7 then
        raise exception 'Une mise en avant dure 7 jours';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if v_org.profile::text = 'events' then
        -- 165: an Événementiel's spot is its public events, not a vitrine.
        if p_product_id is not null then
            raise exception 'Un événementiel met en avant ses événements, pas un article';
        end if;
        if not events_spot_ready(p_org_id) then
            raise exception 'Rendez d''abord un événement public (« Événement public » sur sa carte) : une mise en avant le montre en tête de « Événements ».';
        end if;
    else
        if not v_org.storefront_enabled then
            raise exception 'Ouvrez d''abord la vitrine';
        end if;
        if v_org.lat is null or v_org.lng is null then
            raise exception '%', case
                when v_org.profile::text in ('association', 'church')
                    then 'Placez d''abord votre association sur la carte (« La position de mon association », dans les réglages) : une mise en avant se montre autour d''elle.'
                when v_org.profile::text = 'farm'
                    then 'Placez d''abord votre ferme sur la carte (« La position de ma ferme », dans les réglages) : une mise en avant se montre autour d''elle.'
                else 'Placez d''abord votre boutique sur la carte (« La position de ma boutique », dans les réglages) : une mise en avant se montre autour d''elle.' end;
        end if;
        if v_kind = 'article' and not exists (
            select 1 from products p
             where p.id = p_product_id and p.org_id = p_org_id
               and p.is_active and p.is_published
               and coalesce(p.sale_price, 0) > 0
               and (p.is_service or p.quantity > 0 or not p.stock_tracked)
               and exists (select 1 from documents d where d.product_id = p.id)) then
            raise exception 'Un article mis en avant doit être sur la vitrine, avec une photo, un prix et du stock';
        end if;
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
        -- 165: an Événementiel needs a public event to come, nothing else.
        when (select profile::text from orgs where id = p_org) = 'events' then
            case when feature_hidden(p_org, 'spots') then 'feature'
                 when p_product is not null then 'article'
                 when not events_spot_ready(p_org) then 'event' end
        when not coalesce((select storefront_enabled from orgs where id = p_org), false) then 'vitrine'
        when feature_hidden(p_org, 'spots') then 'feature'
        when not coalesce((select lat is not null and lng is not null from orgs where id = p_org), false)
            then 'position'
        when p_product is not null and not exists (
            select 1 from products p
             where p.id = p_product and p.org_id = p_org
               and p.is_active and p.is_published
               and coalesce(p.sale_price, 0) > 0
               and (p.is_service or p.quantity > 0 or not p.stock_tracked)
               and exists (select 1 from documents d where d.product_id = p.id)) then 'article'
    end;
$$;

-- The street: sponsored events first, said so.
create or replace function event_sponsored(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (select 1 from promotions pm
                    where pm.org_id = p_org and pm.kind = 'shop' and pm.status = 'approved'
                      and pm.starts_at <= now() and pm.ends_at > now())
       and not feature_hidden(p_org, 'spots');
$$;
revoke execute on function event_sponsored(uuid) from public;

create or replace function street_event_row(e events)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'slug', e.slug,
        'title', e.title,
        'kind', e.kind,
        'card', e.card,
        'starts_at', e.starts_at,
        'date_fr', event_date_fr(e.starts_at, e.tz),
        'place', e.place,
        'org_name', o.name,
        'poster', nullif(e.content -> 'p:hero' ->> 'key', ''),
        'tickets', e.tickets_on and event_tickets_allowed(e.org_id),
        'from_price', case when e.tickets_on and event_tickets_allowed(e.org_id)
                           then (select min(t.price) from event_ticket_types t where t.event_id = e.id and t.active) end,
        'currency', coalesce(o.default_currency, 'XOF'),
        'sponsored', event_sponsored(e.org_id))
      from orgs o where o.id = e.org_id;
$$;
revoke execute on function street_event_row(events) from public;

create or replace function street_events()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(jsonb_agg(street_event_row(x.ev) order by x.sponsored desc, x.starts_at), '[]'::jsonb)
      from (select e as ev, event_sponsored(e.org_id) as sponsored, e.starts_at
              from events e join orgs o on o.id = e.org_id
             where e.listed and e.published and e.starts_at is not null
               and e.starts_at > now() - interval '6 hours'
               and o.suspended_at is null
             order by 2 desc, e.starts_at
             limit 60) x;
$$;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function events_spot_ready(uuid) from anon;
        revoke execute on function event_sponsored(uuid) from anon;
        revoke execute on function street_event_row(events) from anon;
        revoke execute on function spot_area_queue(text, uuid) from anon;
        revoke execute on function spot_area_status(uuid, text) from anon;
        grant execute on function street_events() to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function spot_area_queue(text, uuid) from authenticated;
        grant execute on function spot_area_status(uuid, text) to authenticated;
        grant execute on function street_events() to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
