-- ============================================================
-- test_batch141.sql — batch 146 (141): a Basic business keeps the Pro
-- choices of its vitrine; the street shows them only with Mara Pro.
-- Phone block 141.
--
-- The claims:
--   1. installed twice, the same: set_storefront_style still SECURITY
--      DEFINER with its path pinned, closed to anon and PUBLIC, open to
--      authenticated; storefront_style_keeps_pro() invoker, true, closed
--      to anon and PUBLIC, open to authenticated; vitrine_default_style
--      internal;
--   2. a Basic shop, farm and association each SAVE their Pro choices —
--      the layout, three articles en tête, « Masquer les épuisés » — and
--      read them back from their own row;
--   3. storefront() for anon strips them on Basic (no layout, no pinned,
--      no hide_out_of_stock, no open_now), the basics shown;
--   4. an older app's Basic save (none of the three keys sent) keeps
--      them; the keys sent as « grid », [] and false clear them;
--   5. the checks hold on Basic as on Pro: seven pinned, another
--      business's article, the same article twice, a malformed id and a
--      bad layout refused, and nothing written by a refused call;
--   6. the day vitrine_plus comes — the plan, or a cauris unlock — the
--      street shows the saved choices (and « Ouvert maintenant ») with no
--      further save; the day it goes, the street strips them and the row
--      keeps them;
--   7. Vitrine Plus hidden by Mara's switchboard (110): a Basic save
--      takes none of the Pro part, the old one carried over;
--   8. the kind's default look (107) stays on a Basic vitrine whose only
--      dressing is kept Pro choices; it goes once the basics are dressed;
--   9. only an admin of the business dresses it: an employee and a
--      stranger refused;
--  10. the console's « vitrines jamais habillées » (platform_kind_models)
--      reads the same rule: kept Pro choices alone still count, a basic
--      dressed does not; the platform's only.
-- Shop, farm and association throughout.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- As the other suites: every function to the app's role (Supabase's),
-- then 141 again — twice — so its own grants are what is tested (an
-- earlier suite re-applied 093 and 110 themselves).
grant execute on all functions in schema public to authenticated;
\i database/migrations/141_vitrine_pro_kept.sql
\i database/migrations/141_vitrine_pro_kept.sql

\set owner    '''14114114-0000-0000-0000-000000000001'''
\set cashier  '''14114114-0000-0000-0000-000000000002'''
\set farmer   '''14114114-0000-0000-0000-000000000003'''
\set assoc    '''14114114-0000-0000-0000-000000000004'''
\set stranger '''14114114-0000-0000-0000-000000000005'''
\set shop     '''14100000-0000-0000-0000-000000000001'''
\set farm     '''14100000-0000-0000-0000-000000000002'''
\set club     '''14100000-0000-0000-0000-000000000003'''
\set other    '''14100000-0000-0000-0000-000000000004'''

-- What the platform had, put back at the end.
create temp table b141_kept as
    select key, value from platform_settings
     where key in ('vitrine_min_items', 'vitrine_free_basics');
create temp table b141_kind as
    select kind, key, value from kind_settings
     where kind = 'association' and key = 'vitrine_default';
update platform_settings set value = '0' where key = 'vitrine_min_items';
update platform_settings set value = '1' where key = 'vitrine_free_basics';
grant select on b141_kept, b141_kind to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22614100001', '{"full_name": "Gérance Maison Élégance"}'),
    (:cashier,  '+22614100002', '{"full_name": "Caisse Maison Élégance"}'),
    (:farmer,   '+22614100003', '{"full_name": "Gérance Ferme Horizon Vert"}'),
    (:assoc,    '+22614100004', '{"full_name": "Bureau Fondation Espoir"}'),
    (:stranger, '+22614100005', '{"full_name": "Compte Étranger 141"}');
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, plan, plan_until, city) values
    (:shop,  'Maison Élégance',    'maison-elegance-141',  'retail',      'XOF', true, 'free', null, 'Ouagadougou'),
    (:farm,  'Ferme Horizon Vert', 'horizon-vert-141',     'farm',        'XOF', true, 'free', null, 'Ouagadougou'),
    (:club,  'Fondation Espoir',   'fondation-espoir-141', 'association', 'XOF', true, 'free', null, 'Ouagadougou'),
    (:other, 'Atelier Lumière',    'atelier-lumiere-141',  'retail',      'XOF', true, 'free', null, 'Ouagadougou');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :owner,    'owner',    'org', :shop,  'full'),
    (:shop,  :cashier,  'employee', 'org', :shop,  'summary'),
    (:farm,  :farmer,   'owner',    'org', :farm,  'full'),
    (:club,  :assoc,    'owner',    'org', :club,  'full'),
    (:other, :stranger, 'owner',    'org', :other, 'full');
insert into products (id, org_id, name, sale_price, quantity, is_active, is_published) values
    ('141aaaaa-0000-0000-0000-000000000001', :shop, 'Pagne wax',        6000, 4, true, true),
    ('141aaaaa-0000-0000-0000-000000000002', :shop, 'Sac en cuir',      9000, 2, true, true),
    ('141aaaaa-0000-0000-0000-000000000003', :shop, 'Sandales',         4500, 0, true, true),
    ('141aaaaa-0000-0000-0000-000000000004', :shop, 'Foulard',          2500, 7, true, true),
    ('141aaaaa-0000-0000-0000-000000000005', :shop, 'Boubou',          15000, 1, true, true),
    ('141aaaaa-0000-0000-0000-000000000006', :shop, 'Ceinture',         3000, 3, true, true),
    ('141aaaaa-0000-0000-0000-000000000007', :shop, 'Bracelet',         1500, 9, true, true),
    ('141aaaaa-0000-0000-0000-000000000011', :farm, 'Poulet bicyclette', 3500, 20, true, true),
    ('141aaaaa-0000-0000-0000-000000000012', :farm, 'Plateau d''œufs',   2500, 10, true, true),
    ('141aaaaa-0000-0000-0000-000000000021', :club, 'Salle des fêtes',  15000, 0, true, true),
    ('141aaaaa-0000-0000-0000-000000000099', :other, 'Lampe',           5000, 5, true, true);
update products set is_service = true where id = '141aaaaa-0000-0000-0000-000000000021';

-- A call as someone, its answer as text (or the refusal's words).
create or replace function pg_temp.as141(p_who uuid, p_sql text)
returns text
language plpgsql
as $$
declare v text;
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true);
    begin
        set local role authenticated;
        execute p_sql into v;
        reset role;
        return coalesce(v, '(null)');
    exception when others then
        reset role;
        return 'ERR: ' || sqlerrm;
    end;
end;
$$;

-- What the street reads, signed out.
create or replace function pg_temp.street141(p_slug text)
returns jsonb
language plpgsql
as $$
declare v jsonb;
begin
    perform set_config('request.jwt.claim.sub', '', true);
    set local role anon;
    select style into v from storefront(p_slug);
    reset role;
    return v;
end;
$$;

create or replace function pg_temp.row141(p_org uuid)
returns jsonb
language sql
as $$ select storefront_style from orgs where id = p_org $$;

\echo ''
\echo '--- TEST 1: installed twice, the doors ---'
do $$
declare v_conf text;
begin
    if not (select prosecdef from pg_proc where oid = 'set_storefront_style(uuid, jsonb)'::regprocedure) then
        raise exception 'FAIL: set_storefront_style is no longer SECURITY DEFINER';
    end if;
    select array_to_string(proconfig, ',') into v_conf
      from pg_proc where oid = 'set_storefront_style(uuid, jsonb)'::regprocedure;
    if v_conf not like 'search_path=%' then
        raise exception 'FAIL: set_storefront_style without a pinned path: %', v_conf;
    end if;
    if (select prosecdef from pg_proc where oid = 'storefront_style_keeps_pro()'::regprocedure) then
        raise exception 'FAIL: the sign is SECURITY DEFINER';
    end if;
    if has_function_privilege('anon', 'set_storefront_style(uuid, jsonb)', 'execute')
       or has_function_privilege('anon', 'storefront_style_keeps_pro()', 'execute')
       or has_function_privilege('anon', 'vitrine_default_style(uuid)', 'execute') then
        raise exception 'FAIL: anon reaches a dressing door';
    end if;
    if exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                where p.oid in ('set_storefront_style(uuid, jsonb)'::regprocedure,
                                'storefront_style_keeps_pro()'::regprocedure,
                                'vitrine_default_style(uuid)'::regprocedure)
                  and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
        raise exception 'FAIL: PUBLIC may execute a dressing door';
    end if;
    if not has_function_privilege('authenticated', 'set_storefront_style(uuid, jsonb)', 'execute')
       or not has_function_privilege('authenticated', 'storefront_style_keeps_pro()', 'execute') then
        raise exception 'FAIL: the app cannot call its doors';
    end if;
    if has_function_privilege('authenticated', 'vitrine_default_style(uuid)', 'execute') then
        raise exception 'FAIL: the app may call the internal vitrine_default_style';
    end if;
    if not has_function_privilege('anon', 'storefront(text)', 'execute') then
        raise exception 'FAIL: the street lost storefront()';
    end if;
    if pg_temp.as141('14114114-0000-0000-0000-000000000001',
                     'select storefront_style_keeps_pro()::text') <> 'true' then
        raise exception 'FAIL: the sign does not say true';
    end if;
    raise notice 'PASS: definer and pinned, closed to anon and PUBLIC, the sign true for the app';
end $$;

\echo ''
\echo '--- TEST 2: a Basic shop, farm and association save their Pro choices ---'
do $$
declare r text; s jsonb;
begin
    r := pg_temp.as141('14114114-0000-0000-0000-000000000001', $q$
        select set_storefront_style('14100000-0000-0000-0000-000000000001', '{
            "tagline": "Le chic du quartier",
            "accent": "#2E7D5B",
            "schedule": {"days": [1, 2, 3, 4, 5, 6], "open": "08:00", "close": "19:00"},
            "layout": "list",
            "pinned": ["141aaaaa-0000-0000-0000-000000000002",
                       "141aaaaa-0000-0000-0000-000000000001",
                       "141aaaaa-0000-0000-0000-000000000005"],
            "hide_out_of_stock": true}')::text$q$);
    if r like 'ERR:%' then raise exception 'FAIL: the Basic shop was refused: %', r; end if;
    s := pg_temp.row141('14100000-0000-0000-0000-000000000001');
    if s ->> 'layout' <> 'list'
       or s -> 'pinned' <> '["141aaaaa-0000-0000-0000-000000000002", "141aaaaa-0000-0000-0000-000000000001", "141aaaaa-0000-0000-0000-000000000005"]'::jsonb
       or s -> 'hide_out_of_stock' <> 'true'::jsonb
       or s ->> 'tagline' <> 'Le chic du quartier' then
        raise exception 'FAIL: the shop''s choices were not kept: %', s;
    end if;

    r := pg_temp.as141('14114114-0000-0000-0000-000000000003', $q$
        select set_storefront_style('14100000-0000-0000-0000-000000000002', '{
            "layout": "large",
            "pinned": ["141aaaaa-0000-0000-0000-000000000012"]}')::text$q$);
    if r like 'ERR:%' then raise exception 'FAIL: the Basic farm was refused: %', r; end if;
    s := pg_temp.row141('14100000-0000-0000-0000-000000000002');
    if s <> '{"layout": "large", "pinned": ["141aaaaa-0000-0000-0000-000000000012"]}'::jsonb then
        raise exception 'FAIL: the farm''s choices: %', s;
    end if;

    r := pg_temp.as141('14114114-0000-0000-0000-000000000004', $q$
        select set_storefront_style('14100000-0000-0000-0000-000000000003', '{
            "tagline": "Ensemble",
            "layout": "menu",
            "hide_out_of_stock": true}')::text$q$);
    if r like 'ERR:%' then raise exception 'FAIL: the Basic association was refused: %', r; end if;
    s := pg_temp.row141('14100000-0000-0000-0000-000000000003');
    if s <> '{"tagline": "Ensemble", "layout": "menu", "hide_out_of_stock": true}'::jsonb then
        raise exception 'FAIL: the association''s choices: %', s;
    end if;
    raise notice 'PASS: shop, farm and association on Basic keep the layout, the pins and « Masquer les épuisés »';
end $$;

\echo ''
\echo '--- TEST 3: the street strips them on Basic ---'
do $$
declare v jsonb; slug text;
begin
    foreach slug in array array['maison-elegance-141', 'horizon-vert-141', 'fondation-espoir-141'] loop
        v := pg_temp.street141(slug);
        if v is null then raise exception 'FAIL: % is not on the street', slug; end if;
        if v ? 'layout' or v ? 'pinned' or v ? 'hide_out_of_stock' or v ? 'open_now' then
            raise exception 'FAIL: the street reads a Basic % arranged: %', slug, v;
        end if;
    end loop;
    v := pg_temp.street141('maison-elegance-141');
    if v ->> 'tagline' <> 'Le chic du quartier' or v ->> 'accent' <> '#2E7D5B' or not v ? 'schedule' then
        raise exception 'FAIL: the basics are gone from the street: %', v;
    end if;
    raise notice 'PASS: anon reads the basics, never the kept Pro choices nor « Ouvert maintenant »';
end $$;

\echo ''
\echo '--- TEST 4: an older app keeps them; the keys sent clear them ---'
begin;
do $$
declare r text; s jsonb;
begin
    -- An app before batch 146 on Basic: the three keys never sent.
    r := pg_temp.as141('14114114-0000-0000-0000-000000000001', $q$
        select set_storefront_style('14100000-0000-0000-0000-000000000001',
            '{"tagline": "Nouvelle phrase", "accent": "#1F5FA8"}')::text$q$);
    if r like 'ERR:%' then raise exception 'FAIL: %', r; end if;
    s := pg_temp.row141('14100000-0000-0000-0000-000000000001');
    if s ->> 'layout' <> 'list' or jsonb_array_length(s -> 'pinned') <> 3
       or s -> 'hide_out_of_stock' <> 'true'::jsonb or s ->> 'tagline' <> 'Nouvelle phrase'
       or s ? 'schedule' then
        raise exception 'FAIL: an older app''s save lost the choices (or kept a basic it cleared): %', s;
    end if;
    -- Batch 146's app: every key said, grille, none en tête, épuisés shown.
    r := pg_temp.as141('14114114-0000-0000-0000-000000000001', $q$
        select set_storefront_style('14100000-0000-0000-0000-000000000001',
            '{"tagline": "Nouvelle phrase", "layout": "grid", "pinned": [], "hide_out_of_stock": false}')::text$q$);
    if r like 'ERR:%' then raise exception 'FAIL: %', r; end if;
    s := pg_temp.row141('14100000-0000-0000-0000-000000000001');
    if s <> '{"tagline": "Nouvelle phrase"}'::jsonb then
        raise exception 'FAIL: grid, [] and false did not clear: %', s;
    end if;
    raise notice 'PASS: absent keys carried over, sent keys written — « grid », [] and false clear';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: the checks, on Basic as on Pro ---'
do $$
declare
    v_case text;
    r text;
    v_before jsonb := pg_temp.row141('14100000-0000-0000-0000-000000000001');
    v_cases text[] := array[
        -- seven en tête
        '{"pinned": ["141aaaaa-0000-0000-0000-000000000001", "141aaaaa-0000-0000-0000-000000000002",
                     "141aaaaa-0000-0000-0000-000000000003", "141aaaaa-0000-0000-0000-000000000004",
                     "141aaaaa-0000-0000-0000-000000000005", "141aaaaa-0000-0000-0000-000000000006",
                     "141aaaaa-0000-0000-0000-000000000007"]}',
        -- another business's article
        '{"pinned": ["141aaaaa-0000-0000-0000-000000000099"]}',
        -- the same twice
        '{"pinned": ["141aaaaa-0000-0000-0000-000000000001", "141aaaaa-0000-0000-0000-000000000001"]}',
        -- not an id
        '{"pinned": ["pagne"]}',
        -- an unknown layout
        '{"layout": "mosaic"}'
    ];
    v_plan text;
begin
    foreach v_plan in array array['free', 'pro'] loop
        update orgs set plan = v_plan, plan_until = case when v_plan = 'pro' then current_date + 30 end
         where id = '14100000-0000-0000-0000-000000000001';
        foreach v_case in array v_cases loop
            r := pg_temp.as141('14114114-0000-0000-0000-000000000001',
                format('select set_storefront_style(%L, %L::jsonb)::text',
                       '14100000-0000-0000-0000-000000000001', v_case));
            if r not like 'ERR:%' then
                raise exception 'FAIL: on % accepted %', v_plan, v_case;
            end if;
            if r not like 'ERR: Six articles%' and r not like 'ERR: Un article%'
               and r not like 'ERR: La présentation%' then
                raise exception 'FAIL: on % the refusal of % is not the check''s own: %', v_plan, v_case, r;
            end if;
        end loop;
    end loop;
    update orgs set plan = 'free', plan_until = null where id = '14100000-0000-0000-0000-000000000001';
    if pg_temp.row141('14100000-0000-0000-0000-000000000001') <> v_before then
        raise exception 'FAIL: a refused call wrote something';
    end if;
    -- Six is the most, and allowed on Basic.
    r := pg_temp.as141('14114114-0000-0000-0000-000000000001', $q$
        select set_storefront_style('14100000-0000-0000-0000-000000000001', '{
            "pinned": ["141aaaaa-0000-0000-0000-000000000001", "141aaaaa-0000-0000-0000-000000000002",
                       "141aaaaa-0000-0000-0000-000000000003", "141aaaaa-0000-0000-0000-000000000004",
                       "141aaaaa-0000-0000-0000-000000000005", "141aaaaa-0000-0000-0000-000000000006"]}')::text$q$);
    if r like 'ERR:%' then raise exception 'FAIL: six en tête refused on Basic: %', r; end if;
    -- Put the shop's choices back for what follows.
    update orgs set storefront_style = v_before where id = '14100000-0000-0000-0000-000000000001';
    raise notice 'PASS: seven, another''s article, twice, not an id and « mosaic » refused on Basic and on Pro, nothing written; six kept';
end $$;

\echo ''
\echo '--- TEST 6: vitrine_plus comes — the street shows them; it goes — stripped, kept ---'
do $$
declare v jsonb; s jsonb;
begin
    -- The plan.
    update orgs set plan = 'pro', plan_until = current_date + 30
     where id = '14100000-0000-0000-0000-000000000001';
    v := pg_temp.street141('maison-elegance-141');
    if v ->> 'layout' <> 'list' or jsonb_array_length(v -> 'pinned') <> 3
       or v -> 'pinned' ->> 0 <> '141aaaaa-0000-0000-0000-000000000002'
       or v -> 'hide_out_of_stock' <> 'true'::jsonb or not v ? 'open_now' then
        raise exception 'FAIL: Pro came and the street does not show the saved choices: %', v;
    end if;
    -- It goes: the street strips them, the row keeps them.
    update orgs set plan = 'free', plan_until = null
     where id = '14100000-0000-0000-0000-000000000001';
    v := pg_temp.street141('maison-elegance-141');
    if v ? 'layout' or v ? 'pinned' or v ? 'hide_out_of_stock' or v ? 'open_now' then
        raise exception 'FAIL: Pro gone and the street still arranged: %', v;
    end if;
    s := pg_temp.row141('14100000-0000-0000-0000-000000000001');
    if s ->> 'layout' <> 'list' or jsonb_array_length(s -> 'pinned') <> 3 then
        raise exception 'FAIL: Pro gone and the choices with it: %', s;
    end if;

    -- A cauris unlock of Vitrine Plus (085), for the farm.
    insert into cauris_unlocks (org_id, feature, until)
    values ('14100000-0000-0000-0000-000000000002', 'vitrine_plus', now() + interval '7 days')
    on conflict (org_id, feature) do update set until = excluded.until;
    v := pg_temp.street141('horizon-vert-141');
    if v ->> 'layout' <> 'large' or v -> 'pinned' ->> 0 <> '141aaaaa-0000-0000-0000-000000000012' then
        raise exception 'FAIL: the farm''s unlock does not show its saved choices: %', v;
    end if;
    update cauris_unlocks set until = now() - interval '1 minute'
     where org_id = '14100000-0000-0000-0000-000000000002' and feature = 'vitrine_plus';
    v := pg_temp.street141('horizon-vert-141');
    if v ? 'layout' or v ? 'pinned' then
        raise exception 'FAIL: the unlock ended and the farm is still arranged: %', v;
    end if;

    -- The association, by the plan.
    update orgs set plan = 'pro', plan_until = current_date + 30
     where id = '14100000-0000-0000-0000-000000000003';
    v := pg_temp.street141('fondation-espoir-141');
    if v ->> 'layout' <> 'menu' or v -> 'hide_out_of_stock' <> 'true'::jsonb then
        raise exception 'FAIL: the association on Pro: %', v;
    end if;
    update orgs set plan = 'free', plan_until = null
     where id = '14100000-0000-0000-0000-000000000003';
    raise notice 'PASS: by the plan or by cauris, the saved choices show with no save; Pro gone, stripped and kept — shop, farm, association';
end $$;

\echo ''
\echo '--- TEST 7: Vitrine Plus hidden by Mara — a Basic save takes none of it ---'
begin;
do $$
declare r text; s jsonb;
begin
    insert into feature_rules (scope, org_id, feature, state)
    values ('org', '14100000-0000-0000-0000-000000000001', 'vitrine_plus', 'hidden');
    r := pg_temp.as141('14114114-0000-0000-0000-000000000001', $q$
        select set_storefront_style('14100000-0000-0000-0000-000000000001',
            '{"tagline": "Cachée", "layout": "menu", "pinned": [], "hide_out_of_stock": false}')::text$q$);
    if r like 'ERR:%' then raise exception 'FAIL: %', r; end if;
    s := pg_temp.row141('14100000-0000-0000-0000-000000000001');
    if s ->> 'layout' <> 'list' or jsonb_array_length(s -> 'pinned') <> 3
       or s -> 'hide_out_of_stock' <> 'true'::jsonb or s ->> 'tagline' <> 'Cachée' then
        raise exception 'FAIL: a hidden Vitrine Plus took the Pro part: %', s;
    end if;
    raise notice 'PASS: hidden by Mara, the basics written, the arrangement carried over';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: the kind''s default look stays under kept Pro choices ---'
begin;
do $$
declare r text; v jsonb;
begin
    insert into kind_settings (kind, key, value)
    values ('association', 'vitrine_default', '{"accent": "#8E3B6B", "layout": "list"}')
    on conflict (kind, key) do update set value = excluded.value;
    -- Only Pro choices: the street still sees the default colour.
    update orgs set storefront_style = '{}'::jsonb where id = '14100000-0000-0000-0000-000000000003';
    r := pg_temp.as141('14114114-0000-0000-0000-000000000004', $q$
        select set_storefront_style('14100000-0000-0000-0000-000000000003',
            '{"layout": "large", "hide_out_of_stock": true}')::text$q$);
    if r like 'ERR:%' then raise exception 'FAIL: %', r; end if;
    v := pg_temp.street141('fondation-espoir-141');
    if v ->> 'accent' is distinct from '#8E3B6B' or v ? 'layout' or v ? 'hide_out_of_stock' then
        raise exception 'FAIL: the default look went for choices the street cannot see: %', v;
    end if;
    -- With Pro, its own choices — not the kind's default layout.
    update orgs set plan = 'pro', plan_until = current_date + 30
     where id = '14100000-0000-0000-0000-000000000003';
    v := pg_temp.street141('fondation-espoir-141');
    if v ->> 'layout' <> 'large' or v ? 'accent' then
        raise exception 'FAIL: on Pro the saved choices are not what shows: %', v;
    end if;
    update orgs set plan = 'free', plan_until = null
     where id = '14100000-0000-0000-0000-000000000003';
    -- Dressed with a basic: the default is gone, as before 141.
    r := pg_temp.as141('14114114-0000-0000-0000-000000000004', $q$
        select set_storefront_style('14100000-0000-0000-0000-000000000003',
            '{"tagline": "Ensemble"}')::text$q$);
    v := pg_temp.street141('fondation-espoir-141');
    if v ? 'accent' or v ->> 'tagline' <> 'Ensemble' then
        raise exception 'FAIL: a dressed Basic vitrine still reads the default: %', v;
    end if;
    raise notice 'PASS: kept Pro choices do not end the kind''s default; Pro shows its own; a basic does';
end $$;
rollback;

\echo ''
\echo '--- TEST 9: only an admin of the business dresses it ---'
do $$
declare r text;
begin
    r := pg_temp.as141('14114114-0000-0000-0000-000000000002', $q$
        select set_storefront_style('14100000-0000-0000-0000-000000000001', '{"layout": "menu"}')::text$q$);
    if r not like 'ERR: Seul un administrateur%' then
        raise exception 'FAIL: an employee dressed the vitrine: %', r;
    end if;
    r := pg_temp.as141('14114114-0000-0000-0000-000000000005', $q$
        select set_storefront_style('14100000-0000-0000-0000-000000000001', '{"layout": "menu"}')::text$q$);
    if r not like 'ERR: Seul un administrateur%' then
        raise exception 'FAIL: a stranger dressed the vitrine: %', r;
    end if;
    if pg_temp.row141('14100000-0000-0000-0000-000000000001') ->> 'layout' <> 'list' then
        raise exception 'FAIL: a refused caller changed the layout';
    end if;
    raise notice 'PASS: an employee and a stranger refused, nothing written';
end $$;

\echo ''
\echo '--- TEST 10: the console counts « jamais habillées » as the street reads it ---'
begin;
insert into auth.users (id, phone, raw_user_meta_data) values
    ('14114114-0000-0000-0000-000000000006', '+22614100006', '{"full_name": "Console Mara 141"}');
update profiles set is_platform_admin = true where id = '14114114-0000-0000-0000-000000000006';
do $$
declare
    r  text;
    n0 int;
    n  int;
begin
    -- The association on Basic, undressed: the baseline.
    r := pg_temp.as141('14114114-0000-0000-0000-000000000004', $q$
        select set_storefront_style('14100000-0000-0000-0000-000000000003',
            '{"layout": "grid", "pinned": [], "hide_out_of_stock": false}')::text$q$);
    if r like 'ERR:%' then raise exception 'FAIL: the undressed save: %', r; end if;
    n0 := pg_temp.as141('14114114-0000-0000-0000-000000000006',
        $q$select platform_kind_models('association') ->> 'never_dressed'$q$)::int;
    -- Only Pro choices kept: still never dressed for the street, and so counted.
    r := pg_temp.as141('14114114-0000-0000-0000-000000000004', $q$
        select set_storefront_style('14100000-0000-0000-0000-000000000003',
            '{"layout": "list", "hide_out_of_stock": true}')::text$q$);
    if r like 'ERR:%' then raise exception 'FAIL: the Pro-only save: %', r; end if;
    n := pg_temp.as141('14114114-0000-0000-0000-000000000006',
        $q$select platform_kind_models('association') ->> 'never_dressed'$q$)::int;
    if n <> n0 then
        raise exception 'FAIL: kept Pro choices took a vitrine out of « jamais habillées » (% then %)', n0, n;
    end if;
    -- A basic dressed: one fewer.
    r := pg_temp.as141('14114114-0000-0000-0000-000000000004', $q$
        select set_storefront_style('14100000-0000-0000-0000-000000000003',
            '{"tagline": "Ensemble", "layout": "list"}')::text$q$);
    n := pg_temp.as141('14114114-0000-0000-0000-000000000006',
        $q$select platform_kind_models('association') ->> 'never_dressed'$q$)::int;
    if n <> n0 - 1 then
        raise exception 'FAIL: a dressed vitrine still counted as never dressed (% then %)', n0, n;
    end if;
    -- The platform's only.
    r := pg_temp.as141('14114114-0000-0000-0000-000000000004',
        $q$select platform_kind_models('association')::text$q$);
    if r not like 'ERR:%' then
        raise exception 'FAIL: a business owner read the console''s kinds';
    end if;
    raise notice 'PASS: kept Pro choices stay « jamais habillées » in the console; a basic dressed leaves it; the platform''s only';
end $$;
rollback;

-- The platform as it was.
update platform_settings p set value = k.value from b141_kept k where k.key = p.key;
delete from kind_settings where kind = 'association' and key = 'vitrine_default'
   and not exists (select 1 from b141_kind);

\echo ''
\echo 'test_batch141: all passed'
