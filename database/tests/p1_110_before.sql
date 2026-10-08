-- ============================================================
-- p1_110_before.sql — the first half of promise P1 for 110.
--
-- « Installing this batch changes nothing a store, farm, association or
-- vitrine shows. » Run on a database at 109 (every migration up to it,
-- nothing after): it seeds a business of every kind with every vitrine
-- feature 110 puts on the switchboard in use — a shop on Pro (its vitrine
-- dressed with Vitrine Plus, a cover and a logo, delivery rates, Wave
-- allowed with its numbers, a service, an article spot and a shop spot
-- running), a shop on Basic (delivery opened by Mara's gift, a colour of
-- its own, a spot asked for, an article Mara put « À la une »), a farm
-- (its « À vendre » by the tray, a pre-order, a service), an association
-- and a legacy church (services, Wave allowed), a shop not open yet — with
-- their owners and a shopper, and takes a photograph of the vitrine
-- features end to end: every answer the street is given (storefront_*, the
-- directory, the search, À la une, the spotlights, the previews, the
-- delivery quote and check, the photo gate), what each owner reads
-- (feature_states, wave_terms, spot_terms, my_promotions), and what each
-- door does — an order picked up, delivered, paid by Wave, a booking, a
-- farm's tray, a spot asked for and paid, a vitrine dressed (Basic and
-- Pro), delivery rates and the Wave payout changed, a service created —
-- each done and rolled back, its outcome kept. p1_110_after.sql takes the
-- same photograph once 110 and every later migration are applied, and
-- compares answer for answer.
--
-- Not a test_*.sql: it runs in its own database, in its own CI step.
-- ============================================================
\set ON_ERROR_STOP on

insert into auth.users (id, phone, raw_user_meta_data) values
    ('11100000-0000-0000-0000-000000000001', '+22611100001', '{"full_name": "Awa P110"}'),
    ('11100000-0000-0000-0000-000000000002', '+22611100002', '{"full_name": "Bintou P110"}'),
    ('11100000-0000-0000-0000-000000000003', '+22611100003', '{"full_name": "Fermier P110"}'),
    ('11100000-0000-0000-0000-000000000004', '+22611100004', '{"full_name": "Trésorière P110"}'),
    ('11100000-0000-0000-0000-000000000005', '+22611100005', '{"full_name": "Pasteur P110"}'),
    ('11100000-0000-0000-0000-000000000006', '+22611100006', '{"full_name": "Issa P110"}'),
    ('11100000-0000-0000-0000-000000000007', '+22611100007', '{"full_name": "Cliente P110"}'),
    ('11100000-0000-0000-0000-000000000008', '+22611100008', '{"full_name": "Mara P110"}');
update profiles set is_platform_admin = true where id = '11100000-0000-0000-0000-000000000008';

insert into orgs (id, name, slug, profile, default_currency, plan, plan_until,
                  storefront_enabled, storefront_blurb, phone, address, lat, lng) values
    ('11100000-0000-0000-0000-0000000000a1', 'Pro P110',      'pro-p110',      'retail',      'XOF', 'pro',  '2099-01-01',
     true, 'La boutique Pro',      '+22611100001', 'Dapoya',   12.37, -1.52),
    ('11100000-0000-0000-0000-0000000000a2', 'Basic P110',    'basic-p110',    'retail',      'XOF', 'free', null,
     true, 'Tout pour la maison',  '+22611100002', 'Gounghin', 12.36, -1.53),
    ('11100000-0000-0000-0000-0000000000a3', 'Ferme P110',    'ferme-p110',    'farm',        'XOF', 'free', null,
     true, 'Œufs et poulets',      '+22611100003', 'Saaba',    12.38, -1.42),
    ('11100000-0000-0000-0000-0000000000a4', 'Entraide P110', 'entraide-p110', 'association', 'XOF', 'free', null,
     true, 'Une tontine de quartier', '+22611100004', 'Tanghin', 12.40, -1.50),
    ('11100000-0000-0000-0000-0000000000a5', 'Chapelle P110', 'chapelle-p110', 'church',      'XOF', 'free', null,
     true, 'Le culte du dimanche', '+22611100005', 'Pissy',    12.33, -1.56),
    ('11100000-0000-0000-0000-0000000000a6', 'Début P110',    'debut-p110',    'retail',      'XOF', 'free', null,
     true, null, null, null, null, null);

insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    ('11100000-0000-0000-0000-0000000000a1', '11100000-0000-0000-0000-000000000001', 'owner', 'org', '11100000-0000-0000-0000-0000000000a1', 'full'),
    ('11100000-0000-0000-0000-0000000000a2', '11100000-0000-0000-0000-000000000002', 'owner', 'org', '11100000-0000-0000-0000-0000000000a2', 'full'),
    ('11100000-0000-0000-0000-0000000000a3', '11100000-0000-0000-0000-000000000003', 'owner', 'org', '11100000-0000-0000-0000-0000000000a3', 'full'),
    ('11100000-0000-0000-0000-0000000000a4', '11100000-0000-0000-0000-000000000004', 'owner', 'org', '11100000-0000-0000-0000-0000000000a4', 'full'),
    ('11100000-0000-0000-0000-0000000000a5', '11100000-0000-0000-0000-000000000005', 'owner', 'org', '11100000-0000-0000-0000-0000000000a5', 'full'),
    ('11100000-0000-0000-0000-0000000000a6', '11100000-0000-0000-0000-000000000006', 'owner', 'org', '11100000-0000-0000-0000-0000000000a6', 'full');

-- The shelves: eight articles on each open shop and on the farm (one sold
-- out, the farm's by the tray and one still growing), a service on the Pro
-- shop and on the farm, services for the association and the church, two
-- articles on the shop not open.
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_published, unit, description, available_from)
select ('11100000-0000-0000-' || o.tag || '-00000000000' || g)::uuid, o.id, o.prefix || ' ' || g, 100 * g, 50 * g,
       case when g = 3 then 0 when o.tag = '00f0' and g = 8 then 0 else 10 * g end,
       true,
       case when o.tag = '00f0' then 'plateau' end,
       case when g = 1 then 'La meilleure' end,
       case when o.tag = '00f0' and g = 8 then current_date + 20 end
  from (values ('11100000-0000-0000-0000-0000000000a1'::uuid, 'Pagne',  '00a0'),
               ('11100000-0000-0000-0000-0000000000a2'::uuid, 'Savon',  '00b0'),
               ('11100000-0000-0000-0000-0000000000a3'::uuid, 'Œufs',   '00f0')) o(id, prefix, tag)
 cross join generate_series(1, 8) g;
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_published, is_service, price_from, unit) values
    ('11100000-0000-0000-00a0-000000000009', '11100000-0000-0000-0000-0000000000a1', 'Retouche', 1500, 0, 0, true, true, true, 'séance'),
    ('11100000-0000-0000-00f0-000000000009', '11100000-0000-0000-0000-0000000000a3', 'Labour',   9000, 0, 0, true, true, false, 'hectare'),
    ('11100000-0000-0000-00c0-000000000001', '11100000-0000-0000-0000-0000000000a4', 'Location de bâches', 5000, 0, 0, true, true, true, 'jour'),
    ('11100000-0000-0000-00c0-000000000002', '11100000-0000-0000-0000-0000000000a4', 'Cours de couture', 2000, 0, 0, true, true, false, 'séance'),
    ('11100000-0000-0000-00d0-000000000001', '11100000-0000-0000-0000-0000000000a5', 'Cours d''alphabétisation', 1000, 0, 0, true, true, false, 'séance'),
    ('11100000-0000-0000-00e0-000000000001', '11100000-0000-0000-0000-0000000000a6', 'Riz', 500, 400, 5, true, false, false, null),
    ('11100000-0000-0000-00e0-000000000002', '11100000-0000-0000-0000-0000000000a6', 'Huile', 900, 700, 5, false, false, false, null);

-- Photographs: three Pro articles (one is the cover), a farm tray, an
-- association's service; the Pro shop's logo.
insert into documents (org_id, r2_key, kind, content_type, uploaded_by, product_id, captured_at) values
    ('11100000-0000-0000-0000-0000000000a1', 'p110/pro-1.jpg', 'product_photo', 'image/jpeg', '11100000-0000-0000-0000-000000000001', '11100000-0000-0000-00a0-000000000001', '2026-10-01 10:00+00'),
    ('11100000-0000-0000-0000-0000000000a1', 'p110/pro-2.jpg', 'product_photo', 'image/jpeg', '11100000-0000-0000-0000-000000000001', '11100000-0000-0000-00a0-000000000002', '2026-10-01 10:01+00'),
    ('11100000-0000-0000-0000-0000000000a1', 'p110/pro-9.jpg', 'product_photo', 'image/jpeg', '11100000-0000-0000-0000-000000000001', '11100000-0000-0000-00a0-000000000009', '2026-10-01 10:02+00'),
    ('11100000-0000-0000-0000-0000000000a3', 'p110/ferme-1.jpg', 'product_photo', 'image/jpeg', '11100000-0000-0000-0000-000000000003', '11100000-0000-0000-00f0-000000000001', '2026-10-01 10:03+00'),
    ('11100000-0000-0000-0000-0000000000a4', 'p110/asso-1.jpg', 'product_photo', 'image/jpeg', '11100000-0000-0000-0000-000000000004', '11100000-0000-0000-00c0-000000000001', '2026-10-01 10:04+00'),
    ('11100000-0000-0000-0000-0000000000a1', 'p110/pro-logo.png', 'logo', 'image/png', '11100000-0000-0000-0000-000000000001', null, '2026-10-01 10:05+00');

-- The Pro shop: dressed with Vitrine Plus (layout, an article on top, the
-- cover), its logo, its own delivery rates, Wave allowed with its numbers.
update orgs set storefront_style = jsonb_build_object(
                    'tagline', 'Pagnes et retouches', 'layout', 'large',
                    'pinned', jsonb_build_array('11100000-0000-0000-00a0-000000000002'),
                    'cover_key', 'p110/pro-1.jpg', 'accent', '#7A4E2D'),
                logo_key = 'p110/pro-logo.png',
                delivery_base = 500, delivery_per_km = 100, delivery_max_km = 20,
                delivery_included_km = 2,
                wave_allowed = true, wave_merchant = 'M110PRO', wave_payout_number = '+22670110001'
 where id = '11100000-0000-0000-0000-0000000000a1';
-- The Basic shop: a free colour; delivery opened by Mara's gift (not paid).
update orgs set storefront_style = '{"accent": "#2E7D5B", "layout": "list"}'
 where id = '11100000-0000-0000-0000-0000000000a2';
insert into cauris_unlocks (org_id, feature, until, note, gifted_by) values
    ('11100000-0000-0000-0000-0000000000a2', 'delivery', now() + interval '20 days', 'Offert par Mara',
     '11100000-0000-0000-0000-000000000008');
-- The association takes Wave (Mara allowed it).
update orgs set wave_allowed = true, wave_merchant = 'M110ASSO'
 where id = '11100000-0000-0000-0000-0000000000a4';

-- The spots: on the Pro shop an article spot and a shop spot running; on
-- the Basic shop a spot asked for, and an article Mara put « À la une ».
insert into promotions (id, org_id, product_id, kind, days, price, currency, free, status,
                        starts_at, ends_at, requested_by, decided_at, created_at) values
    ('11100000-0000-0000-0000-0000000000c1', '11100000-0000-0000-0000-0000000000a1', '11100000-0000-0000-00a0-000000000001',
     'article', 7, 0, 'XOF', true, 'approved', now() - interval '1 day', now() + interval '6 days',
     '11100000-0000-0000-0000-000000000001', now() - interval '1 day', '2026-10-01 09:00+00'),
    ('11100000-0000-0000-0000-0000000000c2', '11100000-0000-0000-0000-0000000000a1', null,
     'shop', 7, 2500, 'XOF', false, 'approved', now() - interval '1 day', now() + interval '6 days',
     '11100000-0000-0000-0000-000000000001', now() - interval '1 day', '2026-10-01 09:01+00'),
    ('11100000-0000-0000-0000-0000000000c3', '11100000-0000-0000-0000-0000000000a2', null,
     'shop', 7, 2500, 'XOF', false, 'requested', null, null,
     '11100000-0000-0000-0000-000000000002', null, '2026-10-01 09:02+00');
update products set featured_until = now() + interval '5 days'
 where id = '11100000-0000-0000-00b0-000000000002';

-- ------------------------------------------------------------
-- The photograph
-- ------------------------------------------------------------
create table if not exists p110_snap (
    phase text not null,
    what  text not null,
    v     jsonb,
    primary key (phase, what)
);

-- A door, knocked on and rolled back: what it answered (the call's own
-- result, or what it left behind, read by p_read), or the refusal said.
-- Plain plpgsql, no definer: it asks as the app does.
create or replace function p110_knock(p_who uuid, p_role text, p_call text, p_read text)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
    v_res text;
    v     jsonb;
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true);
    begin
        execute format('set local role %I', p_role);
        execute p_call into v_res;
        execute 'reset role';
        execute p_read into v using v_res;
        raise exception 'p110 rollback';
    exception when others then
        if sqlerrm <> 'p110 rollback' then
            v := jsonb_build_object('refused', sqlerrm);
        end if;
    end;
    execute 'reset role';
    return v;
end;
$$;

create or replace function p110_take(p_phase text)
returns int
language plpgsql
set search_path = public
as $$
declare
    m       record;
    s       text;
    k       text;
    v_slugs text[] := array['pro-p110', 'basic-p110', 'ferme-p110', 'entraide-p110', 'chapelle-p110', 'debut-p110'];
    v_shop  constant uuid := '11100000-0000-0000-0000-000000000007';
    v_order constant text :=
        $r$select jsonb_build_object(
               'order', (select to_jsonb(o) - 'id' - 'created_at' - 'updated_at' - 'handover_code'
                                - 'customer_id' - 'number' - 'ref'
                           from orders o where o.id = $1::uuid),
               'lines', (select jsonb_agg(to_jsonb(l) - 'id' - 'order_id' order by l.name)
                           from order_lines l where l.order_id = $1::uuid))$r$;
    acc     jsonb := '{}'::jsonb;
begin
    -- The street, as the street asks.
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    foreach s in array v_slugs loop
        acc := acc
            || jsonb_build_object('storefront ' || s,
                   (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]') from storefront(s) x))
            || jsonb_build_object('storefront_products ' || s,
                   (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]') from storefront_products(s) x))
            || jsonb_build_object('storefront_stock ' || s,
                   (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]') from storefront_stock(s) x))
            || jsonb_build_object('storefront_open ' || s, to_jsonb(storefront_open(s)))
            || jsonb_build_object('delivery_quote ' || s, to_jsonb(delivery_quote(s, 12.375, -1.515)))
            || jsonb_build_object('delivery_check near ' || s,
                   (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from delivery_check(s, 12.375, -1.515) x))
            || jsonb_build_object('delivery_check far ' || s,
                   (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from delivery_check(s, 13.5, -2.5) x));
    end loop;
    acc := acc
        || jsonb_build_object('directory',
               (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from storefront_directory() x))
        || jsonb_build_object('directory near',
               (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from storefront_directory(12.36, -1.53) x))
        || jsonb_build_object('featured',
               (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]') from storefront_featured() x))
        || jsonb_build_object('previews',
               (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]') from storefront_previews(v_slugs) x))
        || jsonb_build_object('spotlights',
               (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]') from storefront_spotlights() x));
    foreach s in array array['pagne', 'savon', 'œufs', 'labour', 'bâches', 'cours', 'retouche', 'riz'] loop
        acc := acc || jsonb_build_object('search ' || s,
               (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]') from search_products(s) x))
                   || jsonb_build_object('search near ' || s,
               (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]') from search_products(s, 12.36, -1.53) x));
    end loop;
    foreach k in array array['p110/pro-1.jpg', 'p110/pro-2.jpg', 'p110/pro-9.jpg', 'p110/ferme-1.jpg',
                             'p110/asso-1.jpg', 'p110/pro-logo.png', 'p110/nowhere.jpg'] loop
        acc := acc || jsonb_build_object('photo ' || k, to_jsonb(storefront_photo_allowed(k)));
    end loop;
    execute 'reset role';

    -- Each owner: their business's states, its Wave terms, the spots.
    for m in select mb.user_id, mb.org_id, o.slug from memberships mb join orgs o on o.id = mb.org_id
              where mb.org_id::text like '11100000-%' order by 1, 2 loop
        perform set_config('request.jwt.claim.sub', m.user_id::text, true);
        execute 'set local role authenticated';
        acc := acc
            || jsonb_build_object('states ' || m.org_id, feature_states(m.org_id) - 'hidden')
            || jsonb_build_object('hidden ' || m.org_id, feature_states(m.org_id) -> 'hidden')
            || jsonb_build_object('wave_terms ' || m.org_id, wave_terms(m.org_id))
            || jsonb_build_object('my_promotions ' || m.org_id,
                   (select coalesce(jsonb_agg(to_jsonb(x) - 'starts_at' - 'ends_at' order by x.id), '[]')
                      from my_promotions(m.org_id) x))
            || jsonb_build_object('own storefront ' || m.org_id,
                   (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from storefront(m.slug) x))
            || jsonb_build_object('own products ' || m.org_id,
                   (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]') from storefront_products(m.slug) x));
        execute 'reset role';
    end loop;
    perform set_config('request.jwt.claim.sub', v_shop::text, true);
    execute 'set local role authenticated';
    acc := acc || jsonb_build_object('spot_terms', spot_terms())
               || jsonb_build_object('wave_terms none', wave_terms(null));
    execute 'reset role';

    -- The doors, each knocked on and rolled back.
    acc := acc
        -- A shopper's order, picked up, at the Pro shop.
        || jsonb_build_object('order pickup', p110_knock(v_shop, 'authenticated',
               $q$select place_order('pro-p110', '[{"product_id": "11100000-0000-0000-00a0-000000000001", "quantity": 2},
                                                  {"product_id": "11100000-0000-0000-00a0-000000000004", "quantity": 1}]'::jsonb)$q$, v_order))
        -- Delivered to a pin, priced by the shop's rates.
        || jsonb_build_object('order delivery', p110_knock(v_shop, 'authenticated',
               $q$select place_order('pro-p110', '[{"product_id": "11100000-0000-0000-00a0-000000000002", "quantity": 1}]'::jsonb,
                                     'delivery', null, 'Kalgondé, porte bleue', '+22670000007', 'cash', 12.375, -1.515)$q$, v_order))
        -- Paid by Wave.
        || jsonb_build_object('order wave', p110_knock(v_shop, 'authenticated',
               $q$select place_order('pro-p110', '[{"product_id": "11100000-0000-0000-00a0-000000000005", "quantity": 1}]'::jsonb,
                                     'pickup', null, null, null, 'wave')$q$, v_order))
        -- A booking (a service alone), at the Pro shop and at the association.
        || jsonb_build_object('booking shop', p110_knock(v_shop, 'authenticated',
               $q$select place_order('pro-p110', '[{"product_id": "11100000-0000-0000-00a0-000000000009", "quantity": 1}]'::jsonb,
                                     'pickup', 'Samedi 10 h')$q$, v_order))
        || jsonb_build_object('booking association', p110_knock(v_shop, 'authenticated',
               $q$select place_order('entraide-p110', '[{"product_id": "11100000-0000-0000-00c0-000000000001", "quantity": 2}]'::jsonb,
                                     'pickup', 'Le 20, pour un mariage')$q$, v_order))
        || jsonb_build_object('booking church', p110_knock(v_shop, 'authenticated',
               $q$select place_order('chapelle-p110', '[{"product_id": "11100000-0000-0000-00d0-000000000001", "quantity": 1}]'::jsonb,
                                     'pickup', 'Lundi soir')$q$, v_order))
        -- Wave at the association.
        || jsonb_build_object('association wave', p110_knock(v_shop, 'authenticated',
               $q$select place_order('entraide-p110', '[{"product_id": "11100000-0000-0000-00c0-000000000002", "quantity": 1}]'::jsonb,
                                     'pickup', 'Mardi', null, null, 'wave')$q$, v_order))
        -- The farm's trays, one still growing (a pre-order), and its service.
        || jsonb_build_object('order farm', p110_knock(v_shop, 'authenticated',
               $q$select place_order('ferme-p110', '[{"product_id": "11100000-0000-0000-00f0-000000000001", "quantity": 3},
                                                    {"product_id": "11100000-0000-0000-00f0-000000000008", "quantity": 1}]'::jsonb)$q$, v_order))
        || jsonb_build_object('booking farm', p110_knock(v_shop, 'authenticated',
               $q$select place_order('ferme-p110', '[{"product_id": "11100000-0000-0000-00f0-000000000009", "quantity": 1}]'::jsonb,
                                     'pickup', 'Après la pluie')$q$, v_order))
        -- Delivery at the Basic shop (Mara's gift), and at the farm (none).
        || jsonb_build_object('order delivery basic', p110_knock(v_shop, 'authenticated',
               $q$select place_order('basic-p110', '[{"product_id": "11100000-0000-0000-00b0-000000000001", "quantity": 1}]'::jsonb,
                                     'delivery', null, 'Gounghin', null, 'cash', 12.361, -1.531)$q$, v_order))
        || jsonb_build_object('order delivery farm', p110_knock(v_shop, 'authenticated',
               $q$select place_order('ferme-p110', '[{"product_id": "11100000-0000-0000-00f0-000000000002", "quantity": 1}]'::jsonb,
                                     'delivery', null, 'Saaba', null, 'cash', 12.381, -1.421)$q$, v_order))
        -- The owners' doors: a spot asked for, a spot said paid, a vitrine
        -- dressed (Pro and Basic), the delivery rates, the Wave payout, a
        -- service created.
        || jsonb_build_object('spot asked', p110_knock('11100000-0000-0000-0000-000000000001', 'authenticated',
               $q$select request_promotion('11100000-0000-0000-0000-0000000000a1', '11100000-0000-0000-00a0-000000000002', 7)$q$,
               $r$select to_jsonb(p) - 'id' - 'starts_at' - 'ends_at' - 'decided_at' - 'created_at'
                    from promotions p where p.id = $1::uuid$r$))
        || jsonb_build_object('spot paid', p110_knock('11100000-0000-0000-0000-000000000002', 'authenticated',
               $q$select claim_promotion_paid('11100000-0000-0000-0000-0000000000c3', 'Wave 2 500 F')$q$,
               $r$select to_jsonb(p) - 'created_at' from promotions p where p.id = '11100000-0000-0000-0000-0000000000c3'$r$))
        || jsonb_build_object('dress pro', p110_knock('11100000-0000-0000-0000-000000000001', 'authenticated',
               $q$select set_storefront_style('11100000-0000-0000-0000-0000000000a1',
                      '{"tagline": "Nouveau", "layout": "menu", "hide_out_of_stock": true, "accent": "#123456"}'::jsonb)$q$,
               $r$select storefront_style from orgs where id = '11100000-0000-0000-0000-0000000000a1'$r$))
        || jsonb_build_object('dress basic', p110_knock('11100000-0000-0000-0000-000000000002', 'authenticated',
               $q$select set_storefront_style('11100000-0000-0000-0000-0000000000a2',
                      '{"tagline": "Moins cher", "layout": "menu", "accent": "#1F5FA8"}'::jsonb)$q$,
               $r$select storefront_style from orgs where id = '11100000-0000-0000-0000-0000000000a2'$r$))
        || jsonb_build_object('dress basic pro colour', p110_knock('11100000-0000-0000-0000-000000000002', 'authenticated',
               $q$select set_storefront_style('11100000-0000-0000-0000-0000000000a2', '{"accent": "#123456"}'::jsonb)$q$,
               $r$select storefront_style from orgs where id = '11100000-0000-0000-0000-0000000000a2'$r$))
        || jsonb_build_object('delivery rates', p110_knock('11100000-0000-0000-0000-000000000001', 'authenticated',
               $q$select set_delivery_rates('11100000-0000-0000-0000-0000000000a1', 700, 150)$q$,
               $r$select jsonb_build_object('base', delivery_base, 'per_km', delivery_per_km)
                    from orgs where id = '11100000-0000-0000-0000-0000000000a1'$r$))
        || jsonb_build_object('delivery reach', p110_knock('11100000-0000-0000-0000-000000000002', 'authenticated',
               $q$select set_delivery_reach('11100000-0000-0000-0000-0000000000a2', 8)$q$,
               $r$select jsonb_build_object('reach', delivery_max_km) from orgs where id = '11100000-0000-0000-0000-0000000000a2'$r$))
        || jsonb_build_object('delivery included', p110_knock('11100000-0000-0000-0000-000000000001', 'authenticated',
               $q$select set_delivery_included_km('11100000-0000-0000-0000-0000000000a1', 3)$q$,
               $r$select jsonb_build_object('included', delivery_included_km) from orgs where id = '11100000-0000-0000-0000-0000000000a1'$r$))
        || jsonb_build_object('wave payout', p110_knock('11100000-0000-0000-0000-000000000001', 'authenticated',
               $q$select set_wave_payout_number('11100000-0000-0000-0000-0000000000a1', '70110002')$q$,
               $r$select jsonb_build_object('payout', wave_payout_number) from orgs where id = '11100000-0000-0000-0000-0000000000a1'$r$))
        || jsonb_build_object('service created', p110_knock('11100000-0000-0000-0000-000000000002', 'authenticated',
               $q$select ensure_product('11100000-0000-0000-0000-0000000000a2', 'Livraison de gaz', 1000,
                                        p_is_service => true)$q$,
               $r$select to_jsonb(p) - 'id' - 'created_at' - 'updated_at' from products p where p.id = $1::uuid$r$))
        || jsonb_build_object('service created association', p110_knock('11100000-0000-0000-0000-000000000004', 'authenticated',
               $q$select ensure_product('11100000-0000-0000-0000-0000000000a4', 'Salle des fêtes', 15000,
                                        p_is_service => true)$q$,
               $r$select to_jsonb(p) - 'id' - 'created_at' - 'updated_at' from products p where p.id = $1::uuid$r$))
        || jsonb_build_object('publish all', p110_knock('11100000-0000-0000-0000-000000000003', 'authenticated',
               $q$select publish_all_products('11100000-0000-0000-0000-0000000000a3')$q$,
               $r$select to_jsonb($1::int)$r$));

    delete from p110_snap where phase = p_phase;
    insert into p110_snap (phase, what, v)
    select p_phase, e.key, e.value from jsonb_each(acc) e;
    return (select count(*) from p110_snap where phase = p_phase);
end;
$$;

do $$
declare
    n int;
    b record;
begin
    n := p110_take('before');
    if n < 100 then
        raise exception 'FAIL: the photograph before is too thin (% answers)', n;
    end if;
    -- It proves something only if the features are really in use.
    select
        (select v from p110_snap where phase = 'before' and what = 'storefront_open pro-p110') <> 'null'::jsonb as pro_open,
        (select v->0->'style'->>'layout' from p110_snap where phase = 'before' and what = 'storefront pro-p110') = 'large' as plus,
        (select (v->0->'style'->>'delivers')::boolean from p110_snap where phase = 'before' and what = 'storefront pro-p110') as delivers,
        (select (v->0->'style'->>'delivers')::boolean from p110_snap where phase = 'before' and what = 'storefront basic-p110') as gift_delivers,
        (select v->0->>'wave_merchant' from p110_snap where phase = 'before' and what = 'storefront pro-p110') = 'M110PRO' as wave,
        (select v->'order'->>'status' from p110_snap where phase = 'before' and what = 'order pickup') = 'pending' as ordered,
        (select (v->'order'->>'delivery_fee')::numeric from p110_snap where phase = 'before' and what = 'order delivery') > 0 as fee,
        (select v->'order'->>'payment_method' from p110_snap where phase = 'before' and what = 'order wave') = 'wave' as paid_wave,
        (select (v->'lines'->0->>'is_service')::boolean from p110_snap where phase = 'before' and what = 'booking association') as booked,
        (select jsonb_array_length(v) from p110_snap where phase = 'before' and what = 'spotlights') = 1 as spot,
        (select jsonb_array_length(v) from p110_snap where phase = 'before' and what = 'featured') = 2 as featured,
        (select v->>'status' from p110_snap where phase = 'before' and what = 'spot asked') is not null as asked,
        (select v->>'is_service' from p110_snap where phase = 'before' and what = 'service created') = 'true' as service,
        (select v->'order'->>'status' from p110_snap where phase = 'before' and what = 'order farm') = 'pending' as farm,
        (select (v->>'payout') from p110_snap where phase = 'before' and what = 'wave payout') = '+22670110002' as payout
      into b;
    if not (b.pro_open and b.plus and b.delivers and b.gift_delivers and b.wave and b.ordered and b.fee
            and b.paid_wave and b.booked and b.spot and b.featured and b.asked and b.service and b.farm
            and b.payout) then
        raise exception 'FAIL: a vitrine feature meant to be in use is not — the photograph would prove nothing: %', row_to_json(b);
    end if;
    raise notice 'P1 before: % answers photographed before 110', n;
end $$;
