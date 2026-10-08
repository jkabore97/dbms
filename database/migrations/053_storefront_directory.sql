-- ============================================================
-- 053_storefront_directory.sql — where the shops are, and which are near.
--
-- Phase two of the vitrine: discovery. A shop can put itself on the map, and
-- anyone can ask for the open vitrines — nearest first when they say where
-- they are. Burkina has no street addresses to speak of, which is exactly why
-- a pin matters more here than it would elsewhere: "près du rond-point" is a
-- direction, not a place a stranger can find.
--
-- Same posture as 052: every public read is a SECURITY DEFINER function that
-- names its columns and is granted to anon, and it returns the shop window —
-- name, blurb, address, pin — never anything behind the counter. Distance is
-- computed here rather than on the phone so a shopper's "près de moi" is one
-- call and the list arrives already in order.
-- ============================================================

alter table orgs add column if not exists lat double precision;
alter table orgs add column if not exists lng double precision;
comment on column orgs.lat is
    'Where the shop is, for the vitrine map. Null = not placed. Set only with '
    'lng, by an administrator, through set_storefront_location().';

alter table orgs drop constraint if exists orgs_lat_range;
alter table orgs add  constraint orgs_lat_range check (lat is null or lat between -90 and 90);
alter table orgs drop constraint if exists orgs_lng_range;
alter table orgs add  constraint orgs_lng_range check (lng is null or lng between -180 and 180);

-- ------------------------------------------------------------
-- The pin: an administrator places the shop, or lifts it off the map
-- ------------------------------------------------------------
create or replace function set_storefront_location(
    p_org_id uuid,
    p_lat    double precision,
    p_lng    double precision
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'set_storefront_location() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Only an administrator can place the shop on the map';
    end if;
    -- Both or neither: half a position is not a place.
    if (p_lat is null) <> (p_lng is null) then
        raise exception 'A position needs both a latitude and a longitude';
    end if;

    update orgs set lat = p_lat, lng = p_lng where id = p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- The directory, for anyone — nearest first when they say where they are
-- ------------------------------------------------------------
-- distance_km is the great-circle distance (haversine) from the caller's
-- position to the shop's pin; null when either side has no position. Shops
-- with a distance come first, nearest first; the rest follow by name.
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
    ) d
    order by (d.distance_km is null), d.distance_km, d.name;
$$;

-- ------------------------------------------------------------
-- Who may call what
-- ------------------------------------------------------------
revoke execute on function set_storefront_location(uuid, double precision, double precision) from public;
revoke execute on function storefront_directory(double precision, double precision)          from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function storefront_directory(double precision, double precision) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_storefront_location(uuid, double precision, double precision) to authenticated;
        grant execute on function storefront_directory(double precision, double precision)          to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
