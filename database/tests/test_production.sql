-- ============================================================
-- test_production.sql — the transformation tool.
--
-- Phone block 91. The story under test is the cake lady's: flour and oil
-- come in at a real price, a run turns them into cakes, and from then on
-- the app knows what one cake costs to make. What matters, in cost order:
-- the ingredient cost lands on the finished product and nowhere else (no
-- double-counted expense); the counts move the right way; a replayed run
-- is one run; a sale of the product snapshots the computed cost into its
-- margin; and none of it is visible from next door.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''91919191-0000-0000-0000-000000000001'''
\set clerk    '''91919191-0000-0000-0000-000000000002'''
\set stranger '''91919191-0000-0000-0000-000000000003'''
\set shop     '''91000000-0000-0000-0000-000000000001'''
\set other    '''91000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22691000001', '{"full_name": "Patissiere"}'),
    (:clerk,    '+22691000002', '{"full_name": "Aide"}'),
    (:stranger, '+22691000003', '{"full_name": "Voisin"}');

insert into orgs (id, name, slug, profile, default_currency) values
    (:shop,  'Patisserie 91', 'patisserie-91', 'retail', 'XOF'),
    (:other, 'Boutique 91b', 'boutique-91b', 'retail', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:shop,  :owner,    'owner',    'org', :shop),
    (:shop,  :clerk,    'employee', 'org', :shop),
    (:other, :stranger, 'owner',    'org', :other);

\echo ''
\echo '--- TEST 1: ingredients in, cakes out, cost moved — books untouched ---'
begin;
set local "request.jwt.claim.sub" = '91919191-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_flour uuid; v_oil uuid;
    v_entries_before int; v_entries_after int;
    v_run uuid;
    v_qty numeric; v_cost numeric;
    v_total numeric; v_unit numeric;
begin
    -- The market trip: 10 kg flour at 500, 5 L oil at 1000. These post
    -- their purchase entries the day the goods arrive, as always.
    v_flour := ensure_product('91000000-0000-0000-0000-000000000001'::uuid, 'Farine');
    v_oil   := ensure_product('91000000-0000-0000-0000-000000000001'::uuid, 'Huile');
    perform receive_products('91000000-0000-0000-0000-000000000001'::uuid,
        v_flour, 10, 500);
    perform receive_products('91000000-0000-0000-0000-000000000001'::uuid,
        v_oil, 5, 1000);

    select count(*) into v_entries_before from journal_entries
     where org_id = '91000000-0000-0000-0000-000000000001';

    -- The baking: 5 kg flour + 2 L oil -> 40 cakes.
    v_run := record_production(
        '91000000-0000-0000-0000-000000000001'::uuid,
        40,
        jsonb_build_array(
            jsonb_build_object('product_id', v_flour, 'quantity', 5),
            jsonb_build_object('product_id', v_oil,   'quantity', 2)),
        p_product_name => 'Gâteau',
        p_client_uuid  => 'c1000000-0000-0000-0000-000000000001'::uuid);

    -- The counts moved the right way.
    select quantity into v_qty from products where id = v_flour;
    if v_qty <> 5 then
        raise exception 'FAIL: flour at % after using 5 of 10', v_qty;
    end if;
    select quantity into v_qty from products where id = v_oil;
    if v_qty <> 3 then
        raise exception 'FAIL: oil at % after using 2 of 5', v_qty;
    end if;
    select quantity, cost_price into v_qty, v_cost from products
     where org_id = '91000000-0000-0000-0000-000000000001'
       and lower(btrim(name)) = 'gâteau';
    if v_qty <> 40 then
        raise exception 'FAIL: % cakes on the shelf, expected 40', v_qty;
    end if;

    -- The arithmetic: (5*500 + 2*1000) / 40 = 112.50 per cake.
    if v_cost <> 112.50 then
        raise exception 'FAIL: a cake costs %, expected 112.50', v_cost;
    end if;
    select total_cost, unit_cost into v_total, v_unit
      from production_runs where id = v_run;
    if v_total <> 4500 or v_unit <> 112.5 then
        raise exception 'FAIL: run says % total, % per unit', v_total, v_unit;
    end if;

    -- And the books did not move: the money left at the market, not in the
    -- kitchen. A journal entry here would count the flour twice.
    select count(*) into v_entries_after from journal_entries
     where org_id = '91000000-0000-0000-0000-000000000001';
    if v_entries_after <> v_entries_before then
        raise exception 'FAIL: production posted a journal entry';
    end if;

    raise notice 'PASS: 40 cakes at 112.50 each, ledger untouched';
end $$;
commit;

\echo ''
\echo '--- TEST 2: the second delivery of the same run is one run ---'
begin;
set local "request.jwt.claim.sub" = '91919191-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v1 uuid; v2 uuid; v_qty numeric;
begin
    select id into v1 from production_runs
     where client_uuid = 'c1000000-0000-0000-0000-000000000001';
    v2 := record_production(
        '91000000-0000-0000-0000-000000000001'::uuid,
        40,
        jsonb_build_array(jsonb_build_object('name', 'Farine', 'quantity', 5)),
        p_product_name => 'Gâteau',
        p_client_uuid  => 'c1000000-0000-0000-0000-000000000001'::uuid);
    if v1 <> v2 then
        raise exception 'FAIL: replay created a second run';
    end if;
    select quantity into v_qty from products
     where org_id = '91000000-0000-0000-0000-000000000001'
       and lower(btrim(name)) = 'gâteau';
    if v_qty <> 40 then
        raise exception 'FAIL: replay changed the shelf to %', v_qty;
    end if;
    raise notice 'PASS: replay returned the same run, still 40 cakes';
end $$;
commit;

\echo ''
\echo '--- TEST 3: a sale of the product carries the computed cost ---'
begin;
set local "request.jwt.claim.sub" = '91919191-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_cake uuid; v_sale uuid;
    v_cost numeric;
    v_debit numeric; v_credit numeric;
begin
    select id into v_cake from products
     where org_id = '91000000-0000-0000-0000-000000000001'
       and lower(btrim(name)) = 'gâteau';

    v_sale := record_sale('91000000-0000-0000-0000-000000000001'::uuid,
        jsonb_build_array(jsonb_build_object(
            'product_id', v_cake, 'name', 'Gâteau',
            'quantity', 2, 'unit_price', 250)));

    select unit_cost into v_cost from sale_lines where sale_id = v_sale;
    if v_cost <> 112.50 then
        raise exception 'FAIL: sale snapshotted cost %, expected 112.50', v_cost;
    end if;

    select sum(l.debit), sum(l.credit) into v_debit, v_credit
      from journal_lines l
      join journal_entries e on e.id = l.journal_entry_id
     where e.org_id = '91000000-0000-0000-0000-000000000001';
    if v_debit <> v_credit then
        raise exception 'FAIL: books unbalanced (% / %)', v_debit, v_credit;
    end if;
    raise notice 'PASS: margin base is 112.50, books balance at % = %',
        v_debit, v_credit;
end $$;
commit;

\echo ''
\echo '--- TEST 4: "  farine " with stray case and space is the same flour ---'
begin;
set local "request.jwt.claim.sub" = '91919191-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_qty numeric;
begin
    perform record_production(
        '91000000-0000-0000-0000-000000000001'::uuid,
        10,
        jsonb_build_array(jsonb_build_object('name', '  farine ', 'quantity', 1)),
        p_product_name => 'Gâteau');
    select quantity into v_qty from products
     where org_id = '91000000-0000-0000-0000-000000000001'
       and lower(btrim(name)) = 'farine';
    if v_qty <> 4 then
        raise exception 'FAIL: flour at % after one more kilo used', v_qty;
    end if;
    raise notice 'PASS: one Farine, now at 4';
end $$;
commit;

\echo ''
\echo '--- TEST 5: an ingredient never received is refused, not minted ---'
begin;
set local "request.jwt.claim.sub" = '91919191-0000-0000-0000-000000000001';
set local role authenticated;
do $$
begin
    begin
        perform record_production(
            '91000000-0000-0000-0000-000000000001'::uuid,
            10,
            jsonb_build_array(jsonb_build_object('name', 'Levure', 'quantity', 1)),
            p_product_name => 'Gâteau');
        raise exception 'FAIL: an unknown ingredient was accepted at cost zero';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: unknown ingredient refused — %', sqlerrm;
    end;

    begin
        perform record_production(
            '91000000-0000-0000-0000-000000000001'::uuid,
            10,
            jsonb_build_array(jsonb_build_object('name', 'Gâteau', 'quantity', 1)),
            p_product_name => 'Gâteau');
        raise exception 'FAIL: a product fed itself';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: self-ingredient refused — %', sqlerrm;
    end;
end $$;
commit;

\echo ''
\echo '--- TEST 6: the neighbour sees nothing and makes nothing ---'
begin;
set local "request.jwt.claim.sub" = '91919191-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare v_run uuid;
begin
    if exists (
        select 1 from production_history('91000000-0000-0000-0000-000000000001'::uuid)) then
        raise exception 'FAIL: a stranger read the production history';
    end if;

    select id into v_run from production_runs limit 1;
    if v_run is not null then
        raise exception 'FAIL: RLS let a stranger select production rows';
    end if;

    begin
        perform record_production(
            '91000000-0000-0000-0000-000000000001'::uuid,
            5,
            jsonb_build_array(jsonb_build_object('name', 'Farine', 'quantity', 1)),
            p_product_name => 'Intrusion');
        raise exception 'FAIL: a stranger recorded a production run';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: stranger''s run refused — %', sqlerrm;
    end;
    raise notice 'PASS: the kitchen is invisible from next door';
end $$;
commit;

\echo ''
\echo '--- TEST 7: an employee can record; history reads back with inputs ---'
begin;
set local "request.jwt.claim.sub" = '91919191-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare
    v_count int;
    v_inputs jsonb;
begin
    perform record_production(
        '91000000-0000-0000-0000-000000000001'::uuid,
        20,
        jsonb_build_array(jsonb_build_object('name', 'Huile', 'quantity', 1)),
        p_product_name => 'Beignet');

    select count(*)::int into v_count
      from production_history('91000000-0000-0000-0000-000000000001'::uuid);
    if v_count <> 3 then
        raise exception 'FAIL: % runs in history, expected 3', v_count;
    end if;

    select inputs into v_inputs
      from production_history('91000000-0000-0000-0000-000000000001'::uuid)
     where product_name = 'Beignet';
    if v_inputs -> 0 ->> 'name' is distinct from 'Huile' then
        raise exception 'FAIL: history inputs say %', v_inputs;
    end if;
    raise notice 'PASS: employee recorded, history carries the recipe';
end $$;
commit;

\echo ''
\echo '=== test_production.sql: all assertions passed ==='
