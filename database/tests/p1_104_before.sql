-- ============================================================
-- p1_104_before.sql — the first half of promise P1 (batch 104).
--
-- « Installing this batch changes nothing any store, farm or association,
-- or any vitrine, shows. » Run on a database at 103 (every migration up to
-- it, nothing after): it seeds a business of every kind — a shop on Basic
-- with its vitrine open, a shop on Pro with its vitrine dressed, a shop
-- whose vitrine is not open yet, a farm, an association, a legacy church —
-- with their owners and an employee the owner's dial narrowed, and takes a
-- photograph of everything they are shown: each member's access to every
-- tool (the dial, the plan, the Pro tools, the catalog's keys), each
-- business's feature_states, and the street's every answer (storefront_*,
-- the directory, the search, the featured, the previews), asked as the
-- street asks — anon. p1_104_after.sql takes the same photograph once
-- 104 and every later migration are applied, and compares.
--
-- Not a test_*.sql: it runs in its own database, in its own CI step.
-- ============================================================
\set ON_ERROR_STOP on

insert into auth.users (id, phone, raw_user_meta_data) values
    ('11040000-0000-0000-0000-000000000001', '+22611140001', '{"full_name": "Awa P1"}'),
    ('11040000-0000-0000-0000-000000000002', '+22611140002', '{"full_name": "Vendeuse P1"}'),
    ('11040000-0000-0000-0000-000000000003', '+22611140003', '{"full_name": "Bintou P1"}'),
    ('11040000-0000-0000-0000-000000000004', '+22611140004', '{"full_name": "Issa P1"}'),
    ('11040000-0000-0000-0000-000000000005', '+22611140005', '{"full_name": "Fermier P1"}'),
    ('11040000-0000-0000-0000-000000000006', '+22611140006', '{"full_name": "Trésorière P1"}'),
    ('11040000-0000-0000-0000-000000000007', '+22611140007', '{"full_name": "Pasteur P1"}');

insert into orgs (id, name, slug, profile, default_currency, plan, plan_until,
                  storefront_enabled, storefront_blurb, phone, address, lat, lng) values
    ('11040000-0000-0000-0000-0000000000a1', 'Boutique P1',   'boutique-p1',  'retail',      'XOF', 'free', null,
     true, 'Tout pour la maison', '+22611140001', 'Gounghin', 12.36, -1.53),
    ('11040000-0000-0000-0000-0000000000a2', 'Pro P1',        'pro-p1',       'retail',      'XOF', 'pro', '2099-01-01',
     true, 'La boutique Pro', '+22611140003', 'Dapoya', 12.37, -1.52),
    ('11040000-0000-0000-0000-0000000000a3', 'Débutante P1',  'debut-p1',     'retail',      'XOF', 'free', null,
     true, null, null, null, null, null),
    ('11040000-0000-0000-0000-0000000000a4', 'Ferme P1',      'ferme-p1',     'farm',        'XOF', 'free', null,
     true, 'Œufs et poulets', '+22611140005', 'Saaba', 12.38, -1.42),
    ('11040000-0000-0000-0000-0000000000a5', 'Entraide P1',   'entraide-p1',  'association', 'XOF', 'free', null,
     true, 'Une tontine de quartier', '+22611140006', 'Tanghin', 12.40, -1.50),
    ('11040000-0000-0000-0000-0000000000a6', 'Chapelle P1',   'chapelle-p1',  'church',      'XOF', 'free', null,
     true, 'Le culte du dimanche', '+22611140007', 'Pissy', 12.33, -1.56);

insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    ('11040000-0000-0000-0000-0000000000a1', '11040000-0000-0000-0000-000000000001', 'owner',    'org', '11040000-0000-0000-0000-0000000000a1', 'full'),
    ('11040000-0000-0000-0000-0000000000a1', '11040000-0000-0000-0000-000000000002', 'employee', 'org', '11040000-0000-0000-0000-0000000000a1', 'full'),
    ('11040000-0000-0000-0000-0000000000a2', '11040000-0000-0000-0000-000000000003', 'owner',    'org', '11040000-0000-0000-0000-0000000000a2', 'full'),
    ('11040000-0000-0000-0000-0000000000a3', '11040000-0000-0000-0000-000000000004', 'owner',    'org', '11040000-0000-0000-0000-0000000000a3', 'full'),
    ('11040000-0000-0000-0000-0000000000a4', '11040000-0000-0000-0000-000000000005', 'owner',    'org', '11040000-0000-0000-0000-0000000000a4', 'full'),
    ('11040000-0000-0000-0000-0000000000a5', '11040000-0000-0000-0000-000000000006', 'owner',    'org', '11040000-0000-0000-0000-0000000000a5', 'full'),
    ('11040000-0000-0000-0000-0000000000a6', '11040000-0000-0000-0000-000000000007', 'owner',    'org', '11040000-0000-0000-0000-0000000000a6', 'full');

-- Two vitrines dressed by their owners (093): the Basic one with the free
-- options and a presentation it may not show (stripped on Basic), the Pro
-- one with Vitrine+'s own. A kind's « vitrine par défaut » (107) must never
-- touch a vitrine its owner dressed.
update orgs set storefront_style = '{"accent": "#2E7D5B", "tagline": "Ouvert le dimanche", "layout": "list"}'
 where id = '11040000-0000-0000-0000-0000000000a1';
update orgs set storefront_style = '{"accent": "#7A4E2D", "tagline": "Pagnes et retouches", "layout": "large", "hide_out_of_stock": true}'
 where id = '11040000-0000-0000-0000-0000000000a2';

-- The owner's dial narrowed the employee (031): it must stay narrowed.
insert into org_feature_rules (org_id, tier, feature, access) values
    ('11040000-0000-0000-0000-0000000000a1', 'employee', 'credits', 'hidden'),
    ('11040000-0000-0000-0000-0000000000a1', 'employee', 'products', 'view');
-- Tontines bought with cauris, analyses given by Mara.
insert into cauris_unlocks (org_id, feature, until) values
    ('11040000-0000-0000-0000-0000000000a1', 'tontines', now() + interval '20 days');
insert into cauris_unlocks (org_id, feature, until, note, gifted_by) values
    ('11040000-0000-0000-0000-0000000000a4', 'analytics', now() + interval '20 days', 'Offert par Mara',
     '11040000-0000-0000-0000-000000000005');

-- The shelves: eight articles on each open shop and on the farm, a service
-- for the association and the church, two articles on the shop not open.
insert into products (org_id, name, sale_price, cost_price, quantity, is_published, is_service, price_from, unit, description)
select o.id, o.prefix || ' ' || g, 100 * g, 50 * g,
       case when g = 3 then 0 else 10 * g end,   -- one sold out
       true, false, false, null, case when g = 1 then 'La meilleure' end
  from (values ('11040000-0000-0000-0000-0000000000a1'::uuid, 'Savon'),
               ('11040000-0000-0000-0000-0000000000a2'::uuid, 'Pagne'),
               ('11040000-0000-0000-0000-0000000000a4'::uuid, 'Plateau d''œufs')) o(id, prefix)
 cross join generate_series(1, 8) g;
insert into products (org_id, name, sale_price, cost_price, quantity, is_published, is_service, price_from, unit) values
    ('11040000-0000-0000-0000-0000000000a2', 'Retouche', 1500, 0, 0, true, true, true, 'séance'),
    ('11040000-0000-0000-0000-0000000000a3', 'Riz', 500, 400, 5, true, false, false, null),
    ('11040000-0000-0000-0000-0000000000a3', 'Huile', 900, 700, 5, false, false, false, null),
    ('11040000-0000-0000-0000-0000000000a5', 'Location de bâches', 5000, 0, 0, true, true, true, 'jour'),
    ('11040000-0000-0000-0000-0000000000a6', 'Cours d''alphabétisation', 1000, 0, 0, true, true, false, 'séance');

-- ------------------------------------------------------------
-- The photograph
-- ------------------------------------------------------------
create table if not exists p1_snap (
    phase text not null,
    what  text not null,
    v     jsonb,
    primary key (phase, what)
);

-- Plain plpgsql, no definer: it changes role to ask as the app does, and
-- writes what it saw once it is itself again.
create or replace function p1_take(p_phase text)
returns int
language plpgsql
set search_path = public
as $$
declare
    m       record;
    v_keys  text[] := array['products', 'production', 'credits', 'tontines', 'invoices', 'photos',
                            'reports', 'staff', 'payroll', 'team_access', 'analytics', 'accounting',
                            'currencies', 'delivery', 'online_payment', 'vitrine_plus', 'orders',
                            'corrections'];
    v_slugs text[] := array['boutique-p1', 'pro-p1', 'debut-p1', 'ferme-p1', 'entraide-p1', 'chapelle-p1'];
    k       text;
    s       text;
    v       jsonb;
    acc     jsonb := '{}'::jsonb;
begin
    -- Each member: what every tool is to them, and their business's states.
    for m in select mb.user_id, mb.org_id, o.slug from memberships mb join orgs o on o.id = mb.org_id
              where mb.org_id::text like '11040000-%' order by 1, 2 loop
        perform set_config('request.jwt.claim.sub', m.user_id::text, true);
        execute 'set local role authenticated';
        v := '{}'::jsonb;
        foreach k in array v_keys loop
            v := v || jsonb_build_object(k, jsonb_build_object(
                     'access', feature_access(m.org_id, k),
                     'pro_locked', pro_locked(m.org_id, k)));
        end loop;
        acc := acc
            || jsonb_build_object('access ' || m.user_id || ' ' || m.org_id, v)
            || jsonb_build_object('states ' || m.user_id || ' ' || m.org_id,
                                  feature_states(m.org_id) - 'hidden')
            -- The paywall's numbers, as each member's app reads them.
            || jsonb_build_object('terms ' || m.user_id || ' ' || m.org_id, plan_terms())
            -- A member sees their own vitrine even below the minimum.
            || jsonb_build_object('own vitrine ' || m.user_id || ' ' || m.org_id,
                                  to_jsonb(storefront_open(m.slug)));
        execute 'reset role';
    end loop;

    -- The street, as the street asks.
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    foreach s in array v_slugs loop
        acc := acc
            || jsonb_build_object('storefront ' || s,
                   (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]') from storefront(s) x))
            || jsonb_build_object('storefront_products ' || s,
                   (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]') from storefront_products(s) x))
            || jsonb_build_object('storefront_open ' || s, to_jsonb(storefront_open(s)))
            || jsonb_build_object('storefront_stock ' || s,
                   (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]') from storefront_stock(s) x));
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
    foreach s in array array['savon', 'pagne', 'œufs', 'bâches', 'riz'] loop
        acc := acc || jsonb_build_object('search ' || s,
               (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]') from search_products(s) x));
    end loop;
    execute 'reset role';

    delete from p1_snap where phase = p_phase;
    insert into p1_snap (phase, what, v)
    select p_phase, e.key, e.value from jsonb_each(acc) e;
    return (select count(*) from p1_snap where phase = p_phase);
end;
$$;

do $$
declare n int;
begin
    n := p1_take('before');
    if n < 40 then
        raise exception 'FAIL: the photograph before is too thin (% answers)', n;
    end if;
    if (select v from p1_snap where phase = 'before' and what = 'storefront_open boutique-p1') = 'null'::jsonb
       or (select jsonb_array_length(v) from p1_snap where phase = 'before' and what = 'storefront_products entraide-p1') <> 1
       or (select jsonb_array_length(v) from p1_snap where phase = 'before' and what = 'directory') < 4 then
        raise exception 'FAIL: the vitrines meant to be open are not — the photograph would prove nothing';
    end if;
    if (select v->0->'style'->>'accent' from p1_snap where phase = 'before' and what = 'storefront boutique-p1')
           is distinct from '#2E7D5B'
       or (select v->0->'style'->>'layout' from p1_snap where phase = 'before' and what = 'storefront pro-p1')
           is distinct from 'large'
       or (select v->0->'style' ? 'layout' from p1_snap where phase = 'before' and what = 'storefront boutique-p1')
       or not exists (select 1 from p1_snap where phase = 'before' and what like 'terms %') then
        raise exception 'FAIL: the dressed vitrines or the terms are not in the photograph';
    end if;
    raise notice 'P1 before: % answers photographed at 103', n;
end $$;
