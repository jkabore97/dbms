-- ============================================================
-- test_batch150.sql — 150: an animal sold once, counted once.
--
-- The claims:
--   1. installed twice, the same: sell_animals, farm_animals_for_sale and
--      link_product_animals SECURITY INVOKER, the three triggers and the
--      two corrections SECURITY DEFINER, every one with its search path
--      pinned; the three doors authenticated's, never anon's or PUBLIC's;
--      the triggers and the helper nobody's;
--   2. the till sells a batch that has no article: ONE sale (its lines,
--      one journal entry, « Ventes » credited once), ONE 'sold' event on
--      the flock tagged with the article made for it (named after the
--      batch, « tête », off the vitrine, its price), the flock's alive
--      down once, the eggs in the same basket as before; the same
--      client_uuid again returns the same sale and moves nothing; the
--      till's list and 101's analyses count it once;
--   3. a linked article sold any way moves the group: at the till by id,
--      by its typed name, on credit (the carnet's debt too); a herd sold
--      lowers head_count;
--   4. guards: more than alive refused (MA001) for a flock and a herd,
--      through sell_animals and through record_sale; a closed group sells
--      nothing (MA001) and its article reads 0, reopened its count again;
--   5. the vitrine: a linked article ordered and accepted takes the birds
--      (one event), handed over it is a sale and takes nothing more; an
--      accepted order cancelled gives them back (a 'sold' of -n); more
--      than alive cannot be ordered;
--   6. a return gives the animals back; no more than the article took can
--      come back; a delivery into it is refused; a hand on its count
--      through the API moves no animal and is put back;
--   7. the group moves, the article follows: a death, a death corrected,
--      a birth, « sortis sans vente »; linking an article that had its
--      own count replaces it with the batch's; one article per group;
--      unlinked, the article counts nothing and the batch keeps its
--      birds; another business's herd is refused;
--   8. corrections: an event a sale wrote cannot be edited as a farm
--      entry; a herd's event corrected moves head_count by the
--      difference (the bug fixed), never below zero;
--   9. refused: an observer, another business, anon (at the door),
--      somebody on behalf of another; the list answers a stranger
--      nothing;
--  10. a shop: its till and its articles exactly as before.
-- Names: Ouagadougou, « Ferme Kossi », « Bande B-2026-07 ». Wrapped in one
-- transaction rolled back: runs twice the same.
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
grant usage on schema auth to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- As test_batch149: the app's role may call the sale's doors (record_sale,
-- record_return…); then 150 again, twice — what it grants and revokes is
-- what is tested.
grant execute on all functions in schema public to authenticated;
\i database/migrations/150_farm_animal_sales.sql
\i database/migrations/150_farm_animal_sales.sql

begin;

update platform_settings set value = '0' where key = 'vitrine_min_items';
update platform_settings set value = 'false' where key = 'order_phone_verified';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('15015015-0000-0000-0000-000000000001', '+22615150001', 'owner150@example.com', '{"full_name": "Kossi Ouédraogo"}',   now() - interval '1 year'),
    ('15015015-0000-0000-0000-000000000002', '+22615150002', 'emp150@example.com',   '{"full_name": "Le vacher"}',         now() - interval '1 year'),
    ('15015015-0000-0000-0000-000000000003', '+22615150003', 'obs150@example.com',   '{"full_name": "Regard Ferme Kossi"}', now() - interval '1 year'),
    ('15015015-0000-0000-0000-000000000004', '+22615150004', 'rival150@example.com', '{"full_name": "Gérance Ferme Zara"}', now() - interval '1 year'),
    ('15015015-0000-0000-0000-000000000005', '+22615150005', 'buyer150@example.com', '{"full_name": "Awa Traoré"}',        now() - interval '1 year');
update profiles p set phone = u.phone from auth.users u where u.id = p.id and p.phone is null;

insert into orgs (id, name, slug, profile, default_currency, plan, plan_until, city, storefront_enabled) values
    ('15050150-0000-0000-0000-000000000001', 'Ferme Kossi',   'ferme-kossi-150',   'farm',   'XOF', 'pro',  current_date + 30, 'Ouagadougou', true),
    ('15050150-0000-0000-0000-000000000002', 'Ferme Zara',    'ferme-zara-150',    'farm',   'XOF', 'free', null,              'Ouagadougou', false),
    ('15050150-0000-0000-0000-000000000003', 'Kiosque Nova',  'kiosque-nova-150',  'retail', 'XOF', 'free', null,              'Ouagadougou', false);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    ('15050150-0000-0000-0000-000000000001', '15015015-0000-0000-0000-000000000001', 'owner',    'org', '15050150-0000-0000-0000-000000000001', 'full'),
    ('15050150-0000-0000-0000-000000000001', '15015015-0000-0000-0000-000000000002', 'employee', 'org', '15050150-0000-0000-0000-000000000001', 'full'),
    ('15050150-0000-0000-0000-000000000001', '15015015-0000-0000-0000-000000000003', 'observer', 'org', '15050150-0000-0000-0000-000000000001', 'full'),
    ('15050150-0000-0000-0000-000000000002', '15015015-0000-0000-0000-000000000004', 'owner',    'org', '15050150-0000-0000-0000-000000000002', 'full'),
    ('15050150-0000-0000-0000-000000000003', '15015015-0000-0000-0000-000000000001', 'owner',    'org', '15050150-0000-0000-0000-000000000003', 'full');
select seed_farm_accounts('15050150-0000-0000-0000-000000000001') \gset zz_
select seed_farm_accounts('15050150-0000-0000-0000-000000000002') \gset zz_
select seed_retail_accounts('15050150-0000-0000-0000-000000000003') \gset zz_

-- The farm: a batch of 100 broilers, another of 40, twelve goats; eggs
-- for sale (a plain article) and « Poulet de chair », counted by hand.
insert into flocks (id, org_id, batch_code, breed, bird_count, arrived_on, created_by) values
    ('150f0000-0000-0000-0000-000000000001', '15050150-0000-0000-0000-000000000001', 'B-2026-07', 'Poulets de chair', 100, current_date - 40, '15015015-0000-0000-0000-000000000001'),
    ('150f0000-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000001', 'B-2026-08', 'Poulets de chair', 40,  current_date - 10, '15015015-0000-0000-0000-000000000001');
insert into herds (id, org_id, species, label, head_count, created_by) values
    ('150a0000-0000-0000-0000-000000000001', '15050150-0000-0000-0000-000000000001', 'caprin', 'Chèvres du bas-fond', 12, '15015015-0000-0000-0000-000000000001'),
    ('150a0000-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000002', 'ovin',   'Moutons de Zara',     8,  '15015015-0000-0000-0000-000000000004');
insert into products (id, org_id, name, sale_price, quantity, unit, is_active, is_published) values
    ('150b0000-0000-0000-0000-000000000001', '15050150-0000-0000-0000-000000000001', 'Œufs',            2500, 50, 'plateau', true, true),
    ('150b0000-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000001', 'Poulet de chair', 3500, 30, 'tête',    true, false),
    ('150b0000-0000-0000-0000-000000000003', '15050150-0000-0000-0000-000000000003', 'Savon',           500,  10, null,      true, false);

create temp table t150 (which text primary key, id uuid);
grant all on t150 to authenticated, anon;

-- As PostgREST names a caller.
create function pg_temp.as150(p_who uuid)
returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true),
           set_config('request.jwt.claims', case when p_who is null then '' else
                      json_build_object('sub', p_who, 'role', 'authenticated')::text end, true);
$$;

-- A value as somebody, under their role (anon when nobody): its text, or
-- « ERR: <sqlstate> <message> ».
create function pg_temp.v150(p_who uuid, p_sql text)
returns text language plpgsql as $$
declare v text;
begin
    perform pg_temp.as150(p_who);
    execute case when p_who is null then 'set local role anon' else 'set local role authenticated' end;
    execute p_sql into v;
    execute 'reset role';
    perform pg_temp.as150(null);
    return coalesce(v, '<null>');
exception when others then
    execute 'reset role';
    perform pg_temp.as150(null);
    return 'ERR: ' || sqlstate || ' ' || sqlerrm;
end;
$$;

create function pg_temp.must150(p_label text, p_got text, p_want text)
returns void language plpgsql as $$
begin
    if p_got is distinct from p_want then
        raise exception 'FAIL: % — got %, wanted %', p_label, p_got, p_want;
    end if;
    raise notice 'PASS: %', p_label;
end;
$$;

create function pg_temp.err150(p_label text, p_got text, p_like text)
returns void language plpgsql as $$
begin
    if p_got not like 'ERR:%' or p_got not like p_like then
        raise exception 'FAIL: % — got %', p_label, p_got;
    end if;
    raise notice 'PASS: % (%)', p_label, left(p_got, 100);
end;
$$;

-- sell_animals as somebody: the sale's id, or the error.
create function pg_temp.sell150(p_who uuid, p_org uuid, p_lines jsonb,
                                p_uuid uuid default null, p_method text default 'cash',
                                p_customer text default null)
returns text language sql as $$
    select pg_temp.v150(p_who, format(
        'select sell_animals(%L::uuid, %L::jsonb, %L, null, %L::uuid, null, now(), %L)::text',
        p_org, p_lines, p_method, p_uuid, p_customer));
$$;

-- record_sale as somebody.
create function pg_temp.till150(p_who uuid, p_org uuid, p_lines jsonb,
                                p_method text default 'cash', p_customer text default null)
returns text language sql as $$
    select pg_temp.v150(p_who, format(
        'select record_sale(%L::uuid, %L::jsonb, %L, null, null, null, now(), %L)::text',
        p_org, p_lines, p_method, p_customer));
$$;

create function pg_temp.alive150(p_flock uuid)
returns text language sql as $$
    select trim_scale(f.bird_count - coalesce(sum(e.quantity) filter (where e.kind in ('mortality', 'sold')), 0))::text
      from flocks f left join flock_events e on e.flock_id = f.id
     where f.id = p_flock group by f.bird_count;
$$;

create function pg_temp.qty150(p_product uuid)
returns text language sql as $$
    select trim_scale(quantity)::text from products where id = p_product;
$$;

\echo ''
\echo '--- TEST 1: installed twice, the doors as said ---'
do $$
declare
    r record;
begin
    for r in select * from (values
        ('sell_animals',              false, true),
        ('farm_animals_for_sale',     false, true),
        ('link_product_animals',      false, true),
        ('animal_group_alive',        false, false),
        ('trg_stock_animals_hand',    false, false),
        ('trg_stock_follows_animals', true,  false),
        ('trg_animals_follow_group',  true,  false),
        ('trg_receipt_not_animals',   true,  false),
        ('update_flock_event',        true,  true),
        ('update_herd_event',         true,  true)
    ) t(fn, definer, open) loop
        if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = r.fn) <> 1 then
            raise exception 'FAIL: % is not exactly one function', r.fn;
        end if;
        if (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = r.fn) <> r.definer then
            raise exception 'FAIL: % is not %', r.fn, case when r.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
        end if;
        if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                        where n.nspname = 'public' and p.proname = r.fn
                          and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')) then
            raise exception 'FAIL: % has no pinned search path', r.fn;
        end if;
        if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
                          aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                    where n.nspname = 'public' and p.proname = r.fn and a.grantee = 0) then
            raise exception 'FAIL: % is open to PUBLIC', r.fn;
        end if;
        if has_function_privilege('anon', (select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                            where n.nspname = 'public' and p.proname = r.fn), 'execute') then
            raise exception 'FAIL: % is open to anon', r.fn;
        end if;
        if has_function_privilege('authenticated', (select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                                     where n.nspname = 'public' and p.proname = r.fn), 'execute') <> r.open then
            raise exception 'FAIL: % authenticated should be %', r.fn, r.open;
        end if;
    end loop;
    if (select count(*) from pg_trigger where tgname in ('stock_animals_hand', 'stock_follows_animals', 'animals_follow_group', 'receipt_not_animals')) <> 6 then
        raise exception 'FAIL: the six triggers are not each there once';
    end if;
    raise notice 'PASS: installed twice the same; three INVOKER doors authenticated''s alone, the triggers (the hand''s INVOKER) and the helper nobody''s, every search path pinned';
end $$;

\echo ''
\echo '--- TEST 2: the till sells a batch with no article — one sale, one count ---'
do $$
declare
    v_sale text;
    v_again text;
    v_art uuid;
    v_entry uuid;
    v_lines int;
    j jsonb;
begin
    v_sale := pg_temp.sell150('15015015-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000001',
        jsonb_build_array(
            jsonb_build_object('flock_id', '150f0000-0000-0000-0000-000000000001', 'quantity', 10, 'unit_price', 3500),
            jsonb_build_object('product_id', '150b0000-0000-0000-0000-000000000001', 'name', 'Œufs', 'quantity', 2, 'unit_price', 2500)),
        '150c0000-0000-0000-0000-000000000001');
    if v_sale like 'ERR:%' then raise exception 'FAIL: the sale was refused: %', v_sale; end if;
    insert into t150 values ('sale1', v_sale::uuid);

    select id into v_art from products where flock_id = '150f0000-0000-0000-0000-000000000001';
    insert into t150 values ('flock_article', v_art);
    perform pg_temp.must150('the batch got its article', (select name || ' · ' || unit || ' · ' || is_published::text || ' · ' || trim_scale(sale_price)
                                                           from products where id = v_art),
                            'Poulets de chair — B-2026-07 · tête · false · 3500');
    perform pg_temp.must150('one sale for the client uuid', (select count(*)::text from sales where client_uuid = '150c0000-0000-0000-0000-000000000001'), '1');
    perform pg_temp.must150('its total', (select trim_scale(total)::text from sales where id = v_sale::uuid), '40000');
    select count(*) into v_lines from sale_lines where sale_id = v_sale::uuid;
    perform pg_temp.must150('two lines', v_lines::text, '2');
    select entry_id into v_entry from sales where id = v_sale::uuid;
    perform pg_temp.must150('one journal entry, « Ventes » credited 40 000 once',
        (select string_agg(a.name || '=' || trim_scale(jl.credit), ',') from journal_lines jl join accounts a on a.id = jl.account_id
          where jl.journal_entry_id = v_entry and a.type = 'income'), 'Ventes=40000');
    perform pg_temp.must150('one sold event, tagged', (select count(*) || ' · ' || trim_scale(sum(quantity)) from flock_events
                                                        where flock_id = '150f0000-0000-0000-0000-000000000001' and kind = 'sold' and product_id = v_art), '1 · 10');
    perform pg_temp.must150('alive down once', pg_temp.alive150('150f0000-0000-0000-0000-000000000001'), '90');
    perform pg_temp.must150('the article reads the batch', pg_temp.qty150(v_art), '90');
    perform pg_temp.must150('the eggs as before', pg_temp.qty150('150b0000-0000-0000-0000-000000000001'), '48');
    perform pg_temp.must150('no event for eggs', (select count(*)::text from flock_events where product_id = '150b0000-0000-0000-0000-000000000001'), '0');

    -- The outbox tries again.
    v_again := pg_temp.sell150('15015015-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('flock_id', '150f0000-0000-0000-0000-000000000001', 'quantity', 10, 'unit_price', 3500)),
        '150c0000-0000-0000-0000-000000000001');
    perform pg_temp.must150('the retry returns the first sale', v_again, v_sale);
    perform pg_temp.must150('the retry moved nothing', pg_temp.alive150('150f0000-0000-0000-0000-000000000001'), '90');
    perform pg_temp.must150('still one article for the batch', (select count(*)::text from products where flock_id = '150f0000-0000-0000-0000-000000000001'), '1');

    -- The till's list.
    perform pg_temp.must150('the till''s list', pg_temp.v150('15015015-0000-0000-0000-000000000002',
        $q$select string_agg(kind || ':' || label || ':' || alive || ':' || (product_id is not null), ' | ' order by kind, label)
             from farm_animals_for_sale('15050150-0000-0000-0000-000000000001')$q$),
        'flock:B-2026-07:90:true | flock:B-2026-08:40:false | herd:Chèvres du bas-fond:12:false');

    -- 101's analyses: income once, the batch's alive.
    j := pg_temp.v150('15015015-0000-0000-0000-000000000001',
        $q$select farm_analytics('15050150-0000-0000-0000-000000000001')::text$q$)::jsonb;
    perform pg_temp.must150('the analyses count the money once', trim_scale((j #>> '{periods,month,income}')::numeric)::text, '40000');
    perform pg_temp.must150('the analyses'' batch', (select f ->> 'alive' from jsonb_array_elements(j -> 'flocks') f where f ->> 'batch_code' = 'B-2026-07'), '90');
end $$;

\echo ''
\echo '--- TEST 3: a linked article sold any way moves the group ---'
do $$
declare
    v_art uuid := (select id from t150 where which = 'flock_article');
    v text;
    v_goat uuid;
begin
    v := pg_temp.till150('15015015-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', v_art, 'name', 'x', 'quantity', 5, 'unit_price', 3500)));
    if v like 'ERR:%' then raise exception 'FAIL: the till refused the article: %', v; end if;
    insert into t150 values ('sale_cash5', v::uuid);
    perform pg_temp.must150('the till by id', pg_temp.alive150('150f0000-0000-0000-0000-000000000001'), '85');

    v := pg_temp.till150('15015015-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('name', 'poulets de chair — b-2026-07', 'quantity', 2, 'unit_price', 3500)));
    if v like 'ERR:%' then raise exception 'FAIL: the till refused the typed name: %', v; end if;
    perform pg_temp.must150('the till by its typed name', pg_temp.alive150('150f0000-0000-0000-0000-000000000001'), '83');

    v := pg_temp.till150('15015015-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', v_art, 'name', 'x', 'quantity', 3, 'unit_price', 3500)),
        'credit', 'Hôtel Sahel');
    if v like 'ERR:%' then raise exception 'FAIL: the credit sale was refused: %', v; end if;
    perform pg_temp.must150('on credit', pg_temp.alive150('150f0000-0000-0000-0000-000000000001'), '80');
    perform pg_temp.must150('the carnet''s debt', (select trim_scale(amount)::text from debts where sale_id = v::uuid), '10500');
    perform pg_temp.must150('four sold events in all', (select count(*)::text from flock_events where product_id = v_art), '4');

    -- A herd, sold as a group from the till.
    v := pg_temp.sell150('15015015-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('herd_id', '150a0000-0000-0000-0000-000000000001', 'quantity', 2, 'unit_price', 45000)));
    if v like 'ERR:%' then raise exception 'FAIL: the herd sale was refused: %', v; end if;
    select id into v_goat from products where herd_id = '150a0000-0000-0000-0000-000000000001';
    insert into t150 values ('herd_article', v_goat);
    perform pg_temp.must150('the herd''s count', (select head_count::text from herds where id = '150a0000-0000-0000-0000-000000000001'), '10');
    perform pg_temp.must150('the herd''s article', (select name || ' · ' || trim_scale(quantity) from products where id = v_goat), 'Chèvres du bas-fond · 10');
    perform pg_temp.must150('the herd''s event', (select kind || ' ' || trim_scale(quantity) from herd_events where product_id = v_goat), 'sold 2');
    perform pg_temp.must150('the herd''s sale', (select trim_scale(total)::text from sales where id = v::uuid), '90000');
end $$;

\echo ''
\echo '--- TEST 4: no more than alive, and a closed group sells nothing ---'
do $$
declare
    v_art uuid := (select id from t150 where which = 'flock_article');
    v_goat uuid := (select id from t150 where which = 'herd_article');
begin
    perform pg_temp.err150('a flock: 81 of 80 refused', pg_temp.sell150('15015015-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('flock_id', '150f0000-0000-0000-0000-000000000001', 'quantity', 81, 'unit_price', 3500))),
        'ERR: MA001 Il ne reste que 80 Poulets de chair — B-2026-07');
    perform pg_temp.err150('a herd: 11 of 10 refused', pg_temp.sell150('15015015-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('herd_id', '150a0000-0000-0000-0000-000000000001', 'quantity', 11, 'unit_price', 45000))),
        'ERR: MA001 Il ne reste que 10 Chèvres du bas-fond');
    perform pg_temp.err150('the till: 81 of 80 refused', pg_temp.till150('15015015-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', v_art, 'name', 'x', 'quantity', 81, 'unit_price', 3500))),
        'ERR: MA001 %');
    perform pg_temp.must150('nothing moved', pg_temp.alive150('150f0000-0000-0000-0000-000000000001') || '/' ||
                                             (select head_count from herds where id = '150a0000-0000-0000-0000-000000000001'), '80/10');

    update herds set closed_on = current_date where id = '150a0000-0000-0000-0000-000000000001';
    perform pg_temp.must150('a closed herd''s article reads 0', pg_temp.qty150(v_goat), '0');
    perform pg_temp.err150('a closed herd sells nothing', pg_temp.sell150('15015015-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('herd_id', '150a0000-0000-0000-0000-000000000001', 'quantity', 1, 'unit_price', 45000))),
        'ERR: MA001 « Chèvres du bas-fond » est clôturé%');
    perform pg_temp.err150('nor its article at the till', pg_temp.till150('15015015-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', v_goat, 'name', 'x', 'quantity', 1, 'unit_price', 45000))),
        'ERR: MA001 « Chèvres du bas-fond » est clôturé%');
    perform pg_temp.must150('closed, it kept its animals', (select head_count::text from herds where id = '150a0000-0000-0000-0000-000000000001'), '10');
    update herds set closed_on = null where id = '150a0000-0000-0000-0000-000000000001';
    perform pg_temp.must150('reopened, its count again', pg_temp.qty150(v_goat), '10');
end $$;

\echo ''
\echo '--- TEST 5: the vitrine takes the birds once, and gives them back ---'
update products set is_published = true where id = (select id from t150 where which = 'flock_article');
do $$
declare
    v_art uuid := (select id from t150 where which = 'flock_article');
    v text;
    v_events int;
begin
    v := pg_temp.v150('15015015-0000-0000-0000-000000000005', format(
        'select place_order(%L, %L::jsonb, %L, %L, null, null, %L)::text', 'ferme-kossi-150',
        jsonb_build_array(jsonb_build_object('product_id', v_art, 'quantity', 4)), 'pickup', 'Samedi', 'cash'));
    if v like 'ERR:%' then raise exception 'FAIL: the order was refused: %', v; end if;
    insert into t150 values ('order1', v::uuid);
    perform pg_temp.err150('the vitrine: 81 of 80 refused', pg_temp.v150('15015015-0000-0000-0000-000000000005', format(
        'select place_order(%L, %L::jsonb, %L, %L, null, null, %L)::text', 'ferme-kossi-150',
        jsonb_build_array(jsonb_build_object('product_id', v_art, 'quantity', 81)), 'pickup', 'Samedi', 'cash')),
        'ERR: MA001 %');
end $$;
update orders set status = 'accepted' where id = (select id from t150 where which = 'order1');
do $$
begin
    perform pg_temp.must150('accepted: the birds are taken', pg_temp.alive150('150f0000-0000-0000-0000-000000000001'), '76');
    perform pg_temp.must150('accepted: one event', (select count(*)::text from flock_events where product_id = (select id from t150 where which = 'flock_article')), '5');
end $$;
update orders set status = 'picked_up' where id = (select id from t150 where which = 'order1');
do $$
begin
    perform pg_temp.must150('handed over: a sale', (select trim_scale(total)::text from sales where order_id = (select id from t150 where which = 'order1')), '14000');
    perform pg_temp.must150('handed over: nothing taken again', pg_temp.alive150('150f0000-0000-0000-0000-000000000001') || '/' ||
        (select count(*) from flock_events where product_id = (select id from t150 where which = 'flock_article')), '76/5');
end $$;
do $$
declare v text;
begin
    v := pg_temp.v150('15015015-0000-0000-0000-000000000005', format(
        'select place_order(%L, %L::jsonb, %L, %L, null, null, %L)::text', 'ferme-kossi-150',
        jsonb_build_array(jsonb_build_object('product_id', (select id from t150 where which = 'flock_article'), 'quantity', 3)), 'pickup', 'Dimanche', 'cash'));
    if v like 'ERR:%' then raise exception 'FAIL: the second order was refused: %', v; end if;
    insert into t150 values ('order2', v::uuid);
end $$;
update orders set status = 'accepted' where id = (select id from t150 where which = 'order2');
update orders set status = 'cancelled' where id = (select id from t150 where which = 'order2');
do $$
begin
    perform pg_temp.must150('cancelled: given back', pg_temp.alive150('150f0000-0000-0000-0000-000000000001'), '76');
    perform pg_temp.must150('as a sold of -3', (select string_agg(trim_scale(quantity)::text, ',' order by quantity)
                                                  from flock_events where product_id = (select id from t150 where which = 'flock_article') and quantity < 0), '-3');
    perform pg_temp.must150('flock_status: net sold', pg_temp.v150('15015015-0000-0000-0000-000000000001',
        $q$select alive || '/' || sold from flock_status('15050150-0000-0000-0000-000000000001') where batch_code = 'B-2026-07'$q$), '76/24');
end $$;

\echo ''
\echo '--- TEST 6: a return gives back; nothing else adds animals ---'
do $$
declare
    v_art uuid := (select id from t150 where which = 'flock_article');
    v text;
begin
    v := pg_temp.v150('15015015-0000-0000-0000-000000000001', format(
        'select record_return(%L::uuid, %L)::text', (select id from t150 where which = 'sale_cash5'), 'Rendus par le client'));
    if v like 'ERR:%' then raise exception 'FAIL: the return was refused: %', v; end if;
    perform pg_temp.must150('the return gives five back', pg_temp.alive150('150f0000-0000-0000-0000-000000000001'), '81');
    perform pg_temp.must150('the article follows', pg_temp.qty150(v_art), '81');

    -- 1 000 « back » through a function: only what the article took (19)
    -- comes back, never a bird from nowhere — and nothing is refused (a
    -- return, a cancelled order must always go through).
    update products set quantity = quantity + 1000 where id = v_art;
    perform pg_temp.must150('no more back than it took', pg_temp.alive150('150f0000-0000-0000-0000-000000000001'), '100');
    perform pg_temp.must150('… the article still the batch''s', pg_temp.qty150(v_art), '100');
    perform pg_temp.must150('… and nothing more to give back', (select trim_scale(sum(quantity))::text from flock_events where product_id = v_art), '0');
    update products set quantity = quantity + 5 where id = v_art;
    perform pg_temp.must150('… then nothing at all', pg_temp.alive150('150f0000-0000-0000-0000-000000000001'), '100');
    -- Sold again, as before the test's detour: 19 take the batch back to 81.
    perform pg_temp.till150('15015015-0000-0000-0000-000000000002', '15050150-0000-0000-0000-000000000001',
        jsonb_build_array(jsonb_build_object('product_id', v_art, 'name', 'x', 'quantity', 19, 'unit_price', 3500)));
    perform pg_temp.must150('sold again', pg_temp.alive150('150f0000-0000-0000-0000-000000000001'), '81');
    perform pg_temp.err150('a delivery into it refused', pg_temp.v150('15015015-0000-0000-0000-000000000001', format(
        'select receive_products(%L::uuid, %L::uuid, 5)::text', '15050150-0000-0000-0000-000000000001', v_art)),
        'ERR: % suit %');
    perform pg_temp.must150('a hand on the count is put back', pg_temp.v150('15015015-0000-0000-0000-000000000001', format(
        'update products set quantity = 5 where id = %L returning trim_scale(quantity)::text', v_art)), '81');
    perform pg_temp.must150('and moved no bird', pg_temp.alive150('150f0000-0000-0000-0000-000000000001'), '81');
end $$;

\echo ''
\echo '--- TEST 7: the group moves, the article follows ---'
do $$
declare
    v_art uuid := (select id from t150 where which = 'flock_article');
    v_goat uuid := (select id from t150 where which = 'herd_article');
    v text;
    v_ev uuid;
begin
    v := pg_temp.v150('15015015-0000-0000-0000-000000000002', format(
        'select record_flock_event(%L::uuid, %L, 1)::text', '150f0000-0000-0000-0000-000000000001', 'mortality'));
    v_ev := v::uuid;
    perform pg_temp.must150('a death', pg_temp.qty150(v_art), '80');
    v := pg_temp.v150('15015015-0000-0000-0000-000000000002', format(
        'select update_flock_event(%L::uuid, 3)::text', v_ev));
    perform pg_temp.must150('the death corrected to 3', pg_temp.qty150(v_art), '78');
    v := pg_temp.v150('15015015-0000-0000-0000-000000000002', format(
        'select record_herd_event(%L::uuid, %L::uuid, %L, 3)::text', '15050150-0000-0000-0000-000000000001', '150a0000-0000-0000-0000-000000000001', 'birth'));
    perform pg_temp.must150('a birth', pg_temp.qty150(v_goat), '13');
    v := pg_temp.v150('15015015-0000-0000-0000-000000000002', format(
        'select record_flock_event(%L::uuid, %L, 2, null, %L)::text', '150f0000-0000-0000-0000-000000000001', 'sold', 'Sans vente — mangés à la maison'));
    perform pg_temp.must150('« sortis sans vente »', pg_temp.qty150(v_art), '76');
    perform pg_temp.must150('… an event of the farm''s, no sale', (select count(*)::text from flock_events
        where flock_id = '150f0000-0000-0000-0000-000000000001' and kind = 'sold' and product_id is null), '1');

    -- An order of « Poulet de chair » accepted while it still counted its
    -- own 30 (2 taken), then the article follows B-2026-08 (40)…
    update products set is_published = true where id = '150b0000-0000-0000-0000-000000000002';
    v := pg_temp.v150('15015015-0000-0000-0000-000000000005', format(
        'select place_order(%L, %L::jsonb, %L, %L, null, null, %L)::text', 'ferme-kossi-150',
        jsonb_build_array(jsonb_build_object('product_id', '150b0000-0000-0000-0000-000000000002', 'quantity', 2)), 'pickup', 'Lundi', 'cash'));
    if v like 'ERR:%' then raise exception 'FAIL: the order before the link was refused: %', v; end if;
    update orders set status = 'accepted' where id = v::uuid;
    perform pg_temp.must150('accepted before the link: its own count', pg_temp.qty150('150b0000-0000-0000-0000-000000000002'), '28');
    perform pg_temp.must150('linked: the batch''s count replaces its own', pg_temp.v150('15015015-0000-0000-0000-000000000001', format(
        'select trim_scale(link_product_animals(%L::uuid, %L::uuid))::text', '150b0000-0000-0000-0000-000000000002', '150f0000-0000-0000-0000-000000000002')), '40');
    -- … cancelled after: never refused, and the batch gains no bird it never gave.
    update orders set status = 'cancelled' where id = v::uuid;
    perform pg_temp.must150('cancelled after the link: the batch as it was', pg_temp.alive150('150f0000-0000-0000-0000-000000000002') || '/' ||
        pg_temp.qty150('150b0000-0000-0000-0000-000000000002'), '40/40');
    perform pg_temp.err150('one article per group', pg_temp.v150('15015015-0000-0000-0000-000000000001', format(
        'select link_product_animals(%L::uuid, %L::uuid)::text', '150b0000-0000-0000-0000-000000000002', '150f0000-0000-0000-0000-000000000001')),
        'ERR: % « B-2026-07 » est déjà suivi par l''article « Poulets de chair — B-2026-07 »');
    perform pg_temp.err150('another business''s herd refused', pg_temp.v150('15015015-0000-0000-0000-000000000001', format(
        'select link_product_animals(%L::uuid, null, %L::uuid)::text', '150b0000-0000-0000-0000-000000000002', '150a0000-0000-0000-0000-000000000002')),
        'ERR: % Ces animaux ne sont pas dans cette ferme');
    perform pg_temp.err150('a direct link to another business''s herd refused', pg_temp.v150('15015015-0000-0000-0000-000000000001', format(
        'update products set flock_id = null, herd_id = %L where id = %L returning id::text', '150a0000-0000-0000-0000-000000000002', '150b0000-0000-0000-0000-000000000002')),
        'ERR: % Cette fiche renvoie à une autre entreprise');
    perform pg_temp.must150('unlinked: it counts nothing', pg_temp.v150('15015015-0000-0000-0000-000000000001', format(
        'select trim_scale(link_product_animals(%L::uuid))::text', '150b0000-0000-0000-0000-000000000002')), '0');
    perform pg_temp.must150('… and the batch keeps its birds', pg_temp.alive150('150f0000-0000-0000-0000-000000000002'), '40');
    update flocks set closed_on = current_date where id = '150f0000-0000-0000-0000-000000000002';
    perform pg_temp.err150('a closed batch cannot be linked', pg_temp.v150('15015015-0000-0000-0000-000000000001', format(
        'select link_product_animals(%L::uuid, %L::uuid)::text', '150b0000-0000-0000-0000-000000000002', '150f0000-0000-0000-0000-000000000002')),
        'ERR: % « B-2026-08 » est clôturé%');
end $$;

\echo ''
\echo '--- TEST 8: corrections — a sale''s event is the sale''s; a herd''s count follows its correction ---'
do $$
declare
    v_goat uuid := (select id from t150 where which = 'herd_article');
    v text;
    v_ev uuid;
begin
    perform pg_temp.err150('a sale''s flock event cannot be edited', pg_temp.v150('15015015-0000-0000-0000-000000000001', format(
        'select update_flock_event(%L::uuid, 1)::text',
        (select id from flock_events where product_id = (select id from t150 where which = 'flock_article') limit 1))),
        'ERR: % Ce mouvement vient d''une vente%');
    perform pg_temp.err150('nor a herd''s', pg_temp.v150('15015015-0000-0000-0000-000000000001', format(
        'select update_herd_event(%L::uuid, 1)::text', (select id from herd_events where product_id = v_goat limit 1))),
        'ERR: % Ce mouvement vient d''une vente%');

    v := pg_temp.v150('15015015-0000-0000-0000-000000000002', format(
        'select record_herd_event(%L::uuid, %L::uuid, %L, 4)::text', '15050150-0000-0000-0000-000000000001', '150a0000-0000-0000-0000-000000000001', 'mortality'));
    v_ev := v::uuid;
    perform pg_temp.must150('four lost', (select head_count::text from herds where id = '150a0000-0000-0000-0000-000000000001'), '9');
    v := pg_temp.v150('15015015-0000-0000-0000-000000000002', format('select update_herd_event(%L::uuid, 1)::text', v_ev));
    perform pg_temp.must150('corrected to one: three come back (the bug)', (select head_count::text from herds where id = '150a0000-0000-0000-0000-000000000001'), '12');
    perform pg_temp.must150('… and the article with them', pg_temp.qty150(v_goat), '12');
    perform pg_temp.err150('a correction below zero refused', pg_temp.v150('15015015-0000-0000-0000-000000000002', format(
        'select update_herd_event(%L::uuid, 50)::text', v_ev)), 'ERR: % There are only 13 animals in this group');
    v := pg_temp.v150('15015015-0000-0000-0000-000000000002', format('select update_herd_event(%L::uuid, null, %L)::text', v_ev, 'vaccination'));
    perform pg_temp.must150('a loss made a vaccination gives it back', (select head_count::text from herds where id = '150a0000-0000-0000-0000-000000000001'), '13');
end $$;

\echo ''
\echo '--- TEST 9: refused — an observer, another business, anon, on behalf of another ---'
do $$
declare
    v_line jsonb := jsonb_build_array(jsonb_build_object('flock_id', '150f0000-0000-0000-0000-000000000001', 'quantity', 1, 'unit_price', 3500));
begin
    perform pg_temp.err150('an observer sells nothing', pg_temp.sell150('15015015-0000-0000-0000-000000000003', '15050150-0000-0000-0000-000000000001', v_line),
        'ERR: % You cannot record sales for this business');
    perform pg_temp.err150('another business sells nothing of ours', pg_temp.sell150('15015015-0000-0000-0000-000000000004', '15050150-0000-0000-0000-000000000001', v_line),
        'ERR: % You cannot record sales for this business');
    perform pg_temp.err150('… nor our batch through its own', pg_temp.sell150('15015015-0000-0000-0000-000000000004', '15050150-0000-0000-0000-000000000002', v_line),
        'ERR: % Ces animaux ne sont pas dans cette ferme');
    perform pg_temp.err150('anon is refused at the door', pg_temp.sell150(null, '15050150-0000-0000-0000-000000000001', v_line), 'ERR: 42501 %');
    perform pg_temp.err150('anon reads no list', pg_temp.v150(null,
        $q$select count(*)::text from farm_animals_for_sale('15050150-0000-0000-0000-000000000001')$q$), 'ERR: 42501 %');
    perform pg_temp.err150('anon links nothing', pg_temp.v150(null, format(
        'select link_product_animals(%L::uuid)::text', '150b0000-0000-0000-0000-000000000002')), 'ERR: 42501 %');
    perform pg_temp.err150('nobody on behalf of another', pg_temp.v150('15015015-0000-0000-0000-000000000002', format(
        'select sell_animals(%L::uuid, %L::jsonb, p_recorded_by => %L::uuid)::text', '15050150-0000-0000-0000-000000000001', v_line, '15015015-0000-0000-0000-000000000001')),
        'ERR: % on behalf of another user');
    perform pg_temp.must150('a stranger reads no group', pg_temp.v150('15015015-0000-0000-0000-000000000004',
        $q$select count(*)::text from farm_animals_for_sale('15050150-0000-0000-0000-000000000001')$q$), '0');
    perform pg_temp.err150('an observer links nothing', pg_temp.v150('15015015-0000-0000-0000-000000000003', format(
        'select link_product_animals(%L::uuid, %L::uuid)::text', '150b0000-0000-0000-0000-000000000002', '150f0000-0000-0000-0000-000000000001')),
        'ERR: %');
    perform pg_temp.must150('nothing moved', pg_temp.alive150('150f0000-0000-0000-0000-000000000001'), '76');
end $$;

\echo ''
\echo '--- TEST 10: a shop, exactly as before ---'
do $$
declare v text;
begin
    v := pg_temp.till150('15015015-0000-0000-0000-000000000001', '15050150-0000-0000-0000-000000000003',
        jsonb_build_array(jsonb_build_object('product_id', '150b0000-0000-0000-0000-000000000003', 'name', 'Savon', 'quantity', 2, 'unit_price', 500)));
    if v like 'ERR:%' then raise exception 'FAIL: the shop''s sale was refused: %', v; end if;
    perform pg_temp.must150('the shop''s shelf', pg_temp.qty150('150b0000-0000-0000-0000-000000000003'), '8');
    perform pg_temp.must150('a shop''s hand on its count stands', pg_temp.v150('15015015-0000-0000-0000-000000000001', format(
        'update products set quantity = 20 where id = %L returning trim_scale(quantity)::text', '150b0000-0000-0000-0000-000000000003')), '20');
    perform pg_temp.must150('no animal anywhere', (select count(*)::text from products
        where org_id = '15050150-0000-0000-0000-000000000003' and (flock_id is not null or herd_id is not null)), '0');
    v := pg_temp.sell150('15015015-0000-0000-0000-000000000001', '15050150-0000-0000-0000-000000000003',
            jsonb_build_array(jsonb_build_object('product_id', '150b0000-0000-0000-0000-000000000003', 'name', 'Savon', 'quantity', 1, 'unit_price', 500)));
    perform pg_temp.must150('sell_animals with articles only is record_sale',
        (select trim_scale(total)::text || ' · ' || pg_temp.qty150('150b0000-0000-0000-0000-000000000003') from sales where id = v::uuid), '500 · 19');
end $$;

rollback;
