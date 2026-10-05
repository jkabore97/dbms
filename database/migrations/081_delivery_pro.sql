-- ============================================================
-- 081_delivery_pro.sql — delivery, and Kaj's online payment, are Kaj Pro;
-- a delivery may cost a minimum for the first kilometres.
--
-- The owner's split (Free runs a small shop, Pro grows it):
--
--   1. Delivery on the vitrine is Pro. delivery_fee() quotes nothing for a
--      shop that is not Pro, the window says so (style.delivers), and an
--      order for delivery is refused at the door of the orders table —
--      whichever path it comes by, an app built before this included.
--      Pickup stays free for everyone.
--   2. Paying online through Kaj's Wave checkout (076) is Pro: wave_terms()
--      says a Free shop is not ready, and a payment for its order is
--      refused at the door of wave_payments. A shop's own Wave link (057),
--      which costs Kaj nothing, stays free.
--   3. The fee may include kilometres: fee = base + per_km × max(0, km −
--      included_km), rounded to 25 F. Included 0 is the old « base + per
--      km » from the shop's door; included 3 makes the base the minimum for
--      any door within 3 km, each kilometre beyond adding per_km. A shop
--      sets its own (set_delivery_included_km), or keeps the platform's
--      (platform_settings.delivery_included_km, 0 to start).
--
-- The Pro list (066) gains 'delivery' and 'online_payment', so the badges
-- and the comparison page read the same line the database draws.
-- ============================================================

insert into platform_settings (key, value) values ('delivery_included_km', '0')
on conflict (key) do nothing;

update platform_settings
   set value = value || '["delivery"]'::jsonb
 where key = 'pro_features' and not (value ? 'delivery');
update platform_settings
   set value = value || '["online_payment"]'::jsonb
 where key = 'pro_features' and not (value ? 'online_payment');

alter table orgs add column if not exists delivery_included_km numeric(6, 2);
do $$ begin
    if not exists (select 1 from pg_constraint where conname = 'orgs_delivery_included_km_range') then
        alter table orgs add constraint orgs_delivery_included_km_range
            check (delivery_included_km is null
                   or (delivery_included_km >= 0 and delivery_included_km <= 50));
    end if;
end $$;

-- Whether this business may deliver: Pro, and pinned on the map.
create or replace function org_delivers(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from orgs o
         where o.id = p_org_id
           and o.lat is not null and o.lng is not null
           and org_plan(o.id) = 'pro');
$$;

create or replace function set_delivery_included_km(p_org_id uuid, p_km numeric)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'set_delivery_included_km() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Only an administrator sets the delivery rates';
    end if;
    if p_km is not null and (p_km < 0 or p_km > 50) then
        raise exception 'Les kilomètres inclus vont de 0 à 50';
    end if;
    update orgs set delivery_included_km = p_km where id = p_org_id;
end;
$$;

-- 069's fee, with the included kilometres and the Pro gate.
create or replace function delivery_fee(
    p_org_id uuid,
    p_lat    double precision,
    p_lng    double precision
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_org      orgs%rowtype;
    v_base     numeric;
    v_per_km   numeric;
    v_included numeric;
    v_currency text;
    v_fee      numeric;
    v_km       double precision;
begin
    if p_lat is null or p_lng is null then
        return null;
    end if;
    select * into v_org from orgs where id = p_org_id;
    if not found or v_org.lat is null or v_org.lng is null then
        return null;
    end if;
    if org_plan(p_org_id) <> 'pro' then
        return null; -- delivery is Kaj Pro (081)
    end if;
    v_km := distance_km(v_org.lat, v_org.lng, p_lat, p_lng);
    if v_km > delivery_reach_km(p_org_id) then
        return null; -- out of reach: there is no price for an impossible run
    end if;
    if v_org.delivery_base is not null then
        v_base   := v_org.delivery_base;
        v_per_km := v_org.delivery_per_km;
    else
        select (value #>> '{}')::text into v_currency
          from platform_settings where key = 'delivery_currency';
        if coalesce(v_org.default_currency, 'XOF') <> coalesce(v_currency, 'XOF') then
            return null; -- the platform's numbers are in another money
        end if;
        select (value #>> '{}')::numeric into v_base
          from platform_settings where key = 'delivery_base';
        select (value #>> '{}')::numeric into v_per_km
          from platform_settings where key = 'delivery_per_km';
        if v_base is null or v_per_km is null then
            return null;
        end if;
    end if;
    v_included := coalesce(
        v_org.delivery_included_km,
        (select (value #>> '{}')::numeric from platform_settings
          where key = 'delivery_included_km'),
        0);
    v_fee := v_base + v_per_km * greatest(0, v_km - v_included);
    return round(v_fee / 25) * 25;
end;
$$;

-- The door of the orders table: a delivery for a shop that is not Pro is
-- refused, whatever path the order came by.
create or replace function trg_order_delivery_pro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.fulfilment = 'delivery' and org_plan(new.org_id) <> 'pro' then
        raise exception 'Kaj Pro : la livraison est réservée aux boutiques Kaj Pro. Choisissez le retrait en boutique.';
    end if;
    return new;
end;
$$;

create or replace trigger order_delivery_pro
    before insert on orders
    for each row execute function trg_order_delivery_pro();

-- The door of wave_payments: Kaj's checkout for an order is Pro.
create or replace function trg_wave_order_pro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.kind = 'order' and org_plan(new.org_id) <> 'pro' then
        raise exception 'Kaj Pro : le paiement en ligne est réservé aux boutiques Kaj Pro';
    end if;
    return new;
end;
$$;

create or replace trigger wave_order_pro
    before insert on wave_payments
    for each row execute function trg_wave_order_pro();

-- 076's terms: a Free shop is not ready for Kaj's checkout.
create or replace function wave_terms(p_org_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'on', wave_on(),
        'shop_ready', p_org_id is not null and exists (
            select 1 from orgs where id = p_org_id and wave_payout_number is not null
               and org_plan(id) = 'pro'),
        'card', coalesce((select (value #>> '{}')::boolean
                            from platform_settings where key = 'wave_card'), false),
        'commission_pct', coalesce((select (value #>> '{}')::numeric
                                      from platform_settings where key = 'wave_commission_pct'), 0)
    );
$$;

-- 080's window, saying whether the shop delivers.
create or replace function storefront(p_slug text)
returns table (
    org_id        uuid,
    name          text,
    slug          text,
    profile       text,
    blurb         text,
    phone         text,
    address       text,
    theme         text,
    currency      text,
    lat           double precision,
    lng           double precision,
    wave_merchant text,
    style         jsonb
)
language sql
stable
security definer
set search_path = public
as $$
    select o.id, o.name, o.slug, o.profile::text, o.storefront_blurb,
           o.phone, o.address, o.theme, o.default_currency, o.lat, o.lng,
           o.wave_merchant,
           (case when org_plan(o.id) = 'pro' then o.storefront_style
                 else '{}'::jsonb end)
           || case when o.logo_key is not null
                   then jsonb_build_object('logo_key', o.logo_key)
                   else '{}'::jsonb end
           || jsonb_build_object('delivers', org_delivers(o.id))
    from orgs o
    where o.id = storefront_open(p_slug);
$$;

revoke execute on function org_delivers(uuid)                       from public;
revoke execute on function set_delivery_included_km(uuid, numeric)  from public;
revoke execute on function trg_order_delivery_pro()                 from public;
revoke execute on function trg_wave_order_pro()                     from public;
revoke execute on function storefront(text)                         from public;
revoke execute on function wave_terms(uuid)                         from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function storefront(text) to anon;
        revoke execute on function org_delivers(uuid) from anon;
        revoke execute on function set_delivery_included_km(uuid, numeric) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function storefront(text)                        to authenticated;
        grant execute on function wave_terms(uuid)                        to authenticated;
        grant execute on function set_delivery_included_km(uuid, numeric) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
