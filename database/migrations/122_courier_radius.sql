-- ============================================================
-- 122_courier_radius.sql — a delivery reaches the couriers around it.
--
-- The owner: « Delivery guys receive requests around 10 km. » Until now
-- (115) the street's couriers heard of a delivery only when the shop's
-- city and the courier's declared city were both known and spelt the
-- same; the board (073) showed every delivery of the street, wherever it
-- was, nearest first.
--
--   1. courier_radius_km: a platform setting (seeded 10), changed in the
--      command center's Réglages — a whole number of km, 1 to 100 (the
--      lines added to 121's platform_set_setting).
--   2. couriers.last_lat / last_lng / last_seen_at: the courier's last
--      known position. Nothing stored one before: the board received the
--      phone's fix at each opening (073's p_lat, p_lng) and forgot it.
--      delivery_board now keeps it, for the courier alone (056's policy:
--      a courier reads only their own row).
--   3. courier_reach(courier, shop, lat, lng): the one rule — 'near' or
--      'far' when a position and the shop's pin both measure (the radius),
--      else 'city' (115's rule: both cities known and the same), else
--      'unknown'. The position is the one given, else the one kept if
--      seen within 24 hours (an older one is ignored). A declared city or
--      quartier has no coordinates anywhere in the schema (112 keeps
--      words), so there is no « centre of the zone » to measure from.
--   4. tell_couriers (115's): the bell rings for the street known near —
--      'near' or 'city'; the shop's own couriers are always told; the cap
--      stays 50. deliveries_waiting() calls it and is unchanged.
--   5. delivery_board (073's): every street delivery as before, except
--      the known 'far'; the own first, then near (nearest), city,
--      unknown; to_shop_km from the fresh position (« à X km », or
--      nothing). Live, both approved couriers have neither a city nor a
--      position: a board by the bell's rule would be empty for them.
--      Each read forgets the positions older than 30 days. 112's
--      courier_rules() carries the radius for the app's one line.
--   6. app_store_links() (S2): the store links the web's « download the
--      app » pop-up offers, readable by the signed-out street — Google
--      Play once play_store_live is on (seeded off: the APK of the latest
--      release until then), the App Store's address from app_store_url
--      (seeded empty: the pop-up then says how to add Mara to the home
--      screen). Both settings in Réglages.
--
-- P1: a shop with no pin, or a courier with no fresh position, is heard
-- exactly as in 115 (the city rule); the shop's own couriers, the minutes,
-- the cap and every message are unchanged; take_delivery is unchanged. The
-- board loses only the deliveries known beyond the radius. Shop, farm and
-- association alike — a delivery is an order of any kind with a vitrine.
--
-- Re-runnable (the bundle runs twice): settings on conflict do nothing,
-- columns if not exists, constraints dropped and added, functions
-- replaced with their arguments unchanged.
-- ============================================================

insert into platform_settings (key, value) values
    ('courier_radius_km', '10'),
    ('play_store_live',   'false'),
    ('app_store_url',     '""')
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- 2. The courier's last known position
-- ------------------------------------------------------------
alter table couriers add column if not exists last_lat     double precision;
alter table couriers add column if not exists last_lng     double precision;
alter table couriers add column if not exists last_seen_at timestamptz;

alter table couriers drop constraint if exists couriers_last_position;
alter table couriers add  constraint couriers_last_position check (
    (last_lat is null and last_lng is null)
    or (last_lat between -90 and 90 and last_lng between -180 and 180));

comment on column couriers.last_lat is
    'The courier''s last known position (122), kept by delivery_board when '
    'the phone gives one; read by courier_reach for the radius when seen '
    'within 24 hours; forgotten after 30 days (delivery_board).';

-- ------------------------------------------------------------
-- 3. Reach: near, far, the same city, or unknown
-- ------------------------------------------------------------
-- The position measured from: the one given (the phone's, now), else the
-- one kept if it is fresh — seen within 24 hours; an older one says
-- nothing of where the courier is today and is ignored.
--   'near'    a position and the shop's pin, within the radius;
--   'far'     a position and the shop's pin, beyond it;
--   'city'    no position or no pin to measure, both cities known and the
--             same (115's rule);
--   'unknown' nothing to tell.
create or replace function courier_reach(
    p_user uuid,
    p_org  uuid,
    p_lat  double precision default null,
    p_lng  double precision default null
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_shop orgs%rowtype;
    v_lat  double precision := p_lat;
    v_lng  double precision := p_lng;
    v_km   integer := least(100, greatest(1, plan_limit('courier_radius_km', 10)));
begin
    select * into v_shop from orgs where id = p_org;
    if not found then
        return 'unknown';
    end if;
    if v_lat is null or v_lng is null then
        select c.last_lat, c.last_lng into v_lat, v_lng
          from couriers c
         where c.user_id = p_user
           and c.last_seen_at >= now() - interval '24 hours';
    end if;
    if v_shop.lat is not null and v_shop.lng is not null
       and v_lat is not null and v_lng is not null then
        return case when distance_km(v_shop.lat, v_shop.lng, v_lat, v_lng) <= v_km
                    then 'near' else 'far' end;
    end if;
    if coalesce(
        nullif(lower(btrim(coalesce(v_shop.city, ''))), '')
          = (select nullif(lower(btrim(coalesce(a.city, ''))), '')
               from courier_applications a where a.user_id = p_user),
        false) then
        return 'city';
    end if;
    return 'unknown';
end;
$$;

-- ------------------------------------------------------------
-- 4. The bell (115's tell_couriers): the street known near — by a fresh
--    position, or by the same declared city when nothing measures
-- ------------------------------------------------------------
-- Never the far, never the unknown: a bell is a promise the delivery is
-- for them. The board (5) is wider.
-- ------------------------------------------------------------
create or replace function tell_couriers(p_order_id uuid, p_own_only boolean)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v      orders%rowtype;
    v_shop orgs%rowtype;
    v_n    integer;
begin
    select * into v from orders where id = p_order_id;
    select * into v_shop from orgs where id = v.org_id;
    insert into notifications (recipient_id, org_id, kind, message, params)
    select c.user_id, v.org_id, 'delivery_available',
           'Nouvelle livraison près de vous : ' || v_shop.name
           || case when v.delivery_fee is null then ''
                   else ' (' || to_char(v.delivery_fee, 'FM999G999G999') || ' F)' end,
           jsonb_build_object('to', 'courier', 'order_id', v.id, 'shop', v_shop.name,
                              'fee', v.delivery_fee, 'currency', v.currency,
                              'own', exists (select 1 from org_couriers oc
                                              where oc.org_id = v.org_id and oc.user_id = c.user_id))
      from couriers c
     where c.status = 'approved'
       and c.user_id is distinct from v.customer_id
       and (case when p_own_only
                 then exists (select 1 from org_couriers oc
                               where oc.org_id = v.org_id and oc.user_id = c.user_id)
                 else not exists (select 1 from org_couriers oc
                                   where oc.org_id = v.org_id and oc.user_id = c.user_id)
                      and courier_reach(c.user_id, v.org_id) in ('near', 'city')
            end)
     order by c.decided_at desc nulls last, c.user_id
     limit 50;
    get diagnostics v_n = row_count;
    if not p_own_only then
        update orders set couriers_told_at = now() where id = p_order_id;
    end if;
    return v_n;
end;
$$;

-- ------------------------------------------------------------
-- 5. The board (073's): every street delivery but the known far
-- ------------------------------------------------------------
-- What a courier sees: the shop's own deliveries always; of the street,
-- everything except what a fresh position and the shop's pin say is
-- beyond the radius. Most couriers have neither a city nor a position
-- kept, and the board must not go empty for them. Order: the own first,
-- then the near (nearest first), the same city, the unknown. The tag is
-- to_shop_km — a number for « à X km » (measured from the fresh
-- position), null when nothing measures.
-- Each read also forgets every position older than 30 days (the privacy
-- text's promise; there is no scheduler).
-- No longer « stable »: it keeps the position it is given.
create or replace function delivery_board(
    p_lat double precision default null,
    p_lng double precision default null
)
returns table (
    order_id       uuid,
    shop_name      text,
    shop_address   text,
    shop_lat       double precision,
    shop_lng       double precision,
    drop_address   text,
    drop_lat       double precision,
    drop_lng       double precision,
    total          numeric,
    currency       text,
    created_at     timestamptz,
    payment_method text,
    paid_at        timestamptz,
    delivery_fee   numeric,
    distance_km    double precision,
    to_shop_km     double precision,
    own_shop       boolean,
    ready_since    timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_lat double precision;
    v_lng double precision;
begin
    perform assert_approved_courier();
    update couriers
       set last_lat = null, last_lng = null, last_seen_at = null
     where (last_lat is not null or last_seen_at is not null)
       and (last_seen_at is null or last_seen_at < now() - interval '30 days');
    if p_lat is not null and p_lng is not null
       and p_lat between -90 and 90 and p_lng between -180 and 180 then
        update couriers
           set last_lat = p_lat, last_lng = p_lng, last_seen_at = now()
         where user_id = auth.uid();
        v_lat := p_lat;
        v_lng := p_lng;
    else
        select c.last_lat, c.last_lng into v_lat, v_lng
          from couriers c
         where c.user_id = auth.uid()
           and c.last_seen_at >= now() - interval '24 hours';
    end if;
    return query
    select x.order_id, x.shop_name, x.shop_address, x.shop_lat, x.shop_lng,
           x.drop_address, x.drop_lat, x.drop_lng, x.total, x.currency,
           x.created_at, x.payment_method, x.paid_at, x.delivery_fee,
           x.distance_km, x.to_shop_km, x.own_shop, x.ready_since
      from (
        select o.id, g.name, g.address, g.lat, g.lng,
               o.address, o.drop_lat, o.drop_lng, o.total, o.currency,
               o.created_at, o.payment_method, o.paid_at, o.delivery_fee,
               case when g.lat is null or o.drop_lat is null then null
                    else distance_km(g.lat, g.lng, o.drop_lat, o.drop_lng) end,
               case when v_lat is null or v_lng is null or g.lat is null or g.lng is null then null
                    else distance_km(v_lat, v_lng, g.lat, g.lng) end,
               exists (select 1 from org_couriers oc
                        where oc.org_id = o.org_id and oc.user_id = auth.uid()),
               order_status_since(o.id),
               courier_reach(auth.uid(), o.org_id, v_lat, v_lng)
          from orders o
          join orgs g on g.id = o.org_id
         where o.status = 'ready'
           and o.fulfilment = 'delivery'
           and o.courier_id is null
           and g.archived_at  is null
           and g.suspended_at is null
           and courier_may_take(o.id, auth.uid())
    ) x (order_id, shop_name, shop_address, shop_lat, shop_lng, drop_address,
         drop_lat, drop_lng, total, currency, created_at, payment_method,
         paid_at, delivery_fee, distance_km, to_shop_km, own_shop, ready_since, reach)
     where x.own_shop or x.reach <> 'far'
    order by x.own_shop desc,
             case x.reach when 'near' then 0 when 'city' then 1 when 'far' then 1 else 2 end,
             x.to_shop_km nulls last, x.created_at;
end;
$$;

-- ------------------------------------------------------------
-- 5b. The courier's rules (112's courier_rules) carry the radius, so the
--     board can say « Pour voir les livraisons à moins de N km » when it
--     asks for the phone's position (my_courier_application reads them)
-- ------------------------------------------------------------
create or replace function courier_rules()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'licence_required', coalesce((select value = 'true'::jsonb from platform_settings
                                       where key = 'courier_licence_required'), false),
        'phone_verified',   coalesce((select value = 'true'::jsonb from platform_settings
                                       where key = 'courier_phone_verified'), false),
        -- RULE M: a mobile-money payout only while Mara takes mobile payment.
        'mobile_money',     wave_on(),
        'charter_version',  1,
        'radius_km',        least(100, greatest(1, plan_limit('courier_radius_km', 10))));
$$;

-- ------------------------------------------------------------
-- 6. The store links, for the web's « download the app »
-- ------------------------------------------------------------
create or replace function app_store_links()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'android', case when coalesce((select value from platform_settings
                                        where key = 'play_store_live') = 'true'::jsonb, false)
                        then 'https://play.google.com/store/apps/details?id=bf.kaj.app'
                        else 'https://github.com/jkabore97/dbms/releases/latest/download/kaj-arm64-v8a.apk' end,
        'android_store', coalesce((select value from platform_settings
                                    where key = 'play_store_live') = 'true'::jsonb, false),
        'ios', nullif(btrim(coalesce((select value #>> '{}' from platform_settings
                                       where key = 'app_store_url'), '')), ''));
$$;

-- ------------------------------------------------------------
-- 1. Réglages: 121's platform_set_setting, the radius 1–100, the App
--    Store an address
-- ------------------------------------------------------------
create or replace function platform_set_setting(p_key text, p_value jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_before jsonb;
    v_type   text;
    v_num    numeric;
begin
    perform platform_only();
    select value into v_before from platform_settings where key = p_key for update;
    if not found or platform_setting_internal(p_key) then
        raise exception 'Réglage inconnu : %', coalesce(p_key, '');
    end if;
    v_type := jsonb_typeof(v_before);
    -- A whole object is a page's, never a single setting.
    if v_type = 'object' then
        raise exception 'Réglage inconnu : %', p_key;
    end if;
    if p_value is null or jsonb_typeof(p_value) <> v_type then
        raise exception '%', case v_type
            when 'number'  then 'Ce réglage attend un nombre.'
            when 'boolean' then 'Ce réglage attend oui ou non.'
            when 'string'  then 'Ce réglage attend un texte.'
            when 'array'   then 'Ce réglage attend une liste.'
            else 'Ce réglage n''accepte pas cette valeur.' end;
    end if;
    if v_type = 'number' then
        v_num := (p_value #>> '{}')::numeric;
        if v_num < 0 then
            raise exception 'Un nombre positif, s''il vous plaît.';
        end if;
        if v_num > 1000000000 then
            raise exception 'Un nombre d''un milliard au plus.';
        end if;
        if p_key like '%\_pct' and v_num > 100 then
            raise exception 'Un pourcentage ne dépasse pas 100.';
        end if;
        -- A whole number, but for the five every reader takes as numeric
        -- (061/069/081/085's delivery fee and reach, 076's commission).
        -- Every other number is read as an integer (plan_limit,
        -- cauris_param, a ::int cast: « 12.5 » would break plan_terms(), the
        -- caps and the leagues), or is a count or a price in francs read
        -- through 071's spot_setting, where a decimal means nothing.
        if v_num <> trunc(v_num)
           and p_key not in ('delivery_base', 'delivery_per_km', 'delivery_max_km',
                             'delivery_included_km', 'wave_commission_pct') then
            raise exception 'Un nombre entier, s''il vous plaît.';
        end if;
        -- 121: the card's rate divides a price — never zero.
        if p_key = 'stripe_xof_per_usd' and v_num <= 0 then
            raise exception 'Un nombre entier plus grand que zéro, s''il vous plaît.';
        end if;
        -- 122: the couriers' radius, 1 to 100 km.
        if p_key = 'courier_radius_km' and (v_num < 1 or v_num > 100) then
            raise exception 'Un nombre de kilomètres de 1 à 100, s''il vous plaît.';
        end if;
        -- Two switches kept as numbers (093, 097): read as « = 1 ».
        if p_key in ('vitrine_free_basics', 'path_gates_open') and v_num not in (0, 1) then
            raise exception 'Ce réglage vaut 0 (non) ou 1 (oui).';
        end if;
        -- Written the way an integer reader reads it: « 12 », never « 12.0 ».
        p_value := case when v_num = trunc(v_num) then to_jsonb(v_num::bigint) else to_jsonb(v_num) end;
    elsif v_type = 'string' then
        if length(p_value #>> '{}') > 200 then
            raise exception 'Un texte de 200 caractères au plus.';
        end if;
        -- 122: the App Store's address is an address, or nothing.
        if p_key = 'app_store_url' then
            p_value := to_jsonb(btrim(p_value #>> '{}'));
            if p_value #>> '{}' <> '' and p_value #>> '{}' !~ '^https://[^\s]+$' then
                raise exception 'Une adresse qui commence par https://, ou rien.';
            end if;
        end if;
    elsif v_type = 'array' then
        if exists (select 1 from jsonb_array_elements(p_value) e
                    where jsonb_typeof(e) <> 'string') then
            raise exception 'Ce réglage attend une liste de mots.';
        end if;
    end if;
    if p_value = v_before then
        return null;  -- nothing changed, nothing to write in the journal
    end if;

    update platform_settings set value = p_value, updated_at = now() where key = p_key;
    return platform_log_action(
        null, 'setting',
        'Réglage ' || p_key || ' : ' || v_before::text || ' → ' || p_value::text,
        jsonb_build_object('key', p_key, 'value', v_before),
        jsonb_build_object('key', p_key, 'value', p_value),
        'platform_undo_setting',
        jsonb_build_object('key', p_key, 'before', v_before, 'after', p_value));
end;
$$;

-- ------------------------------------------------------------
-- Who may call what (063: a new function is born closed to anon and
-- PUBLIC; each door said again)
-- ------------------------------------------------------------
revoke execute on function courier_reach(uuid, uuid, double precision, double precision) from public;
revoke execute on function tell_couriers(uuid, boolean)                                  from public;
revoke execute on function courier_rules()                                               from public;
revoke execute on function delivery_board(double precision, double precision)          from public;
revoke execute on function app_store_links()                                             from public;
revoke execute on function platform_set_setting(text, jsonb)                             from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function courier_reach(uuid, uuid, double precision, double precision) from anon;
        revoke execute on function tell_couriers(uuid, boolean)                    from anon;
        revoke execute on function courier_rules()                                 from anon;
        revoke execute on function delivery_board(double precision, double precision) from anon;
        revoke execute on function platform_set_setting(text, jsonb)               from anon;
        -- The street's: the pop-up is shown to a signed-out shopper.
        grant  execute on function app_store_links()                               to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: only tell_couriers and delivery_board ask it, as their owner.
        revoke execute on function courier_reach(uuid, uuid, double precision, double precision) from authenticated;
        revoke execute on function tell_couriers(uuid, boolean)                    from authenticated;
        revoke execute on function courier_rules()                                 from authenticated;
        grant  execute on function delivery_board(double precision, double precision) to authenticated;
        grant  execute on function app_store_links()                               to authenticated;
        grant  execute on function platform_set_setting(text, jsonb)               to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
