-- ============================================================
-- test_production_edit.sql — correcting a production run (034).
--
-- Phone block 97. A batch is recorded the morning it is made; a wrong output
-- count must be correctable. What matters: fixing the count re-derives the
-- unit cost from the unchanged total (the ingredients did not change), the
-- name can be corrected, an observer cannot correct, and a run cannot be made
-- into zero.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''97979797-0000-0000-0000-000000000001'''
\set observer '''97979797-0000-0000-0000-000000000002'''
\set org      '''97000000-0000-0000-0000-000000000001'''
\set flour    '''97000000-0000-0000-0000-0000000000a1'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22697000001', '{"full_name": "Boulangère"}'),
    (:observer, '+22697000002', '{"full_name": "Témoin"}');

insert into orgs (id, name, slug, profile, default_currency) values
    (:org, 'Atelier 97', 'atelier-97', 'retail', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:org, :owner,    'owner',    'org', :org),
    (:org, :observer, 'observer', 'org', :org);

-- One ingredient with a real cost, so total_cost is non-zero.
insert into products (id, org_id, name, cost_price) values
    (:flour, :org, 'Farine', 100);


\echo ''
\echo '--- TEST 1: fixing the output count re-derives the unit cost ---'
begin;
set local "request.jwt.claim.sub" = '97979797-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_org   uuid := '97000000-0000-0000-0000-000000000001';
    v_flour uuid := '97000000-0000-0000-0000-0000000000a1';
    v_run uuid; v_qty numeric; v_total numeric; v_unit numeric; v_name text;
begin
    -- 20 cakes from 5 units of flour at 100 = 500 total, 25 each.
    v_run := record_production(
        v_org, 20,
        jsonb_build_array(jsonb_build_object('product_id', v_flour, 'quantity', 5)),
        p_product_name => 'Gâteau');

    select quantity, total_cost, unit_cost into v_qty, v_total, v_unit
      from production_runs where id = v_run;
    if v_qty <> 20 or v_total <> 500 or v_unit <> 25 then
        raise exception 'FAIL: run not recorded as expected (% % %)',
            v_qty, v_total, v_unit;
    end if;

    -- It was 40, not 20. Same flour, so total stays 500 and each cake now
    -- costs 12.5 to make.
    perform update_production_run(v_run, p_quantity => 40,
                                  p_product_name => 'Gâteau au miel');
    select quantity, total_cost, unit_cost, product_name
      into v_qty, v_total, v_unit, v_name
      from production_runs where id = v_run;
    if v_qty <> 40 then raise exception 'FAIL: quantity not corrected (%)', v_qty; end if;
    if v_total <> 500 then raise exception 'FAIL: total_cost changed (%)', v_total; end if;
    if v_unit <> 12.5 then raise exception 'FAIL: unit_cost not re-derived (%)', v_unit; end if;
    if v_name <> 'Gâteau au miel' then raise exception 'FAIL: name not corrected (%)', v_name; end if;

    raise notice 'PASS: count corrected, unit cost re-derived, name changed';
end $$;
rollback;


\echo ''
\echo '--- TEST 2: an observer cannot correct a run ---'
begin;
set local "request.jwt.claim.sub" = '97979797-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_org uuid := '97000000-0000-0000-0000-000000000001';
        v_flour uuid := '97000000-0000-0000-0000-0000000000a1'; v_run uuid;
begin
    v_run := record_production(v_org, 10,
        jsonb_build_array(jsonb_build_object('product_id', v_flour, 'quantity', 2)),
        p_product_name => 'Pain');
    perform set_config('test.run_id', v_run::text, true);
end $$;

set local "request.jwt.claim.sub" = '97979797-0000-0000-0000-000000000002';
do $$
declare v_run uuid := current_setting('test.run_id')::uuid;
begin
    perform update_production_run(v_run, p_quantity => 999);
    raise exception 'FAIL: an observer corrected a production run';
exception
    when others then
        if sqlerrm like '%cannot correct%' then
            raise notice 'PASS: observer refused — %', sqlerrm;
        else raise; end if;
end $$;
rollback;


\echo ''
\echo '--- TEST 3: a run cannot be corrected to zero ---'
begin;
set local "request.jwt.claim.sub" = '97979797-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_org uuid := '97000000-0000-0000-0000-000000000001';
        v_flour uuid := '97000000-0000-0000-0000-0000000000a1'; v_run uuid;
begin
    v_run := record_production(v_org, 12,
        jsonb_build_array(jsonb_build_object('product_id', v_flour, 'quantity', 3)),
        p_product_name => 'Beignet');
    begin
        perform update_production_run(v_run, p_quantity => 0);
        raise exception 'FAIL: a run was corrected to zero';
    exception
        when others then
            if sqlerrm like '%quantity that was made%' then
                raise notice 'PASS: zero run refused — %', sqlerrm;
            else raise; end if;
    end;
end $$;
rollback;

\echo ''
\echo '=== test_production_edit.sql: all checks passed ==='
