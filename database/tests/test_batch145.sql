-- ============================================================
-- test_batch145.sql — a shop's day by its index and on its own clock,
-- an item's newest photo by an index (145, batch 149).
--
-- The claims:
--   1. documents_by_product exists, on (product_id, coalesce(captured_at,
--      created_at) desc) where product_id is not null — the expression
--      136's product_cover_key / item_gallery_keys / product_gallery and
--      100's vitrine_score order by — and, with enough rows that it
--      matters, the planner takes it for « this item's newest photo » and
--      product_cover_key reads a handful of documents, not the table;
--   2. store_day reads a day off sales_by_day: its plan names the index
--      with occurred_at in the index condition, and calling it reads about
--      a day's sales, where 011's text read every sale of the shop;
--   3. store_day(org, day) answers exactly what 011's text answered, day
--      by day over a year of sales with some at 00:00:00 and 23:59:59.999
--      UTC, and so does store_day(org, day, 0);
--   4. a shop at UTC+1 sees a sale made at 23:30 local on that day and one
--      made at 00:30 local on the next (the UTC door puts that one on the
--      day before); at UTC−1 a sale at 23:30 local stays on its day; an
--      offset past ±14 h is refused;
--   5. still SECURITY INVOKER, both doors: a stranger to the shop adds up
--      nothing, a member the day;
--   6. the doors: store_day(uuid, date) keeps its signature, its default,
--      its columns, its pinned search_path and its grants (re-running 145
--      changes no ACL); store_day(uuid, date, int) is authenticated's and
--      closed to anon and PUBLIC;
--   7. re-runnable: 145 applied twice above; everything after the setup
--      runs in one transaction rolled back, so the file runs twice the
--      same.
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

-- The ACL of 011's door before 145 runs again (whatever the suites
-- before this one granted it). The new door's are 145's to set.
create temp table b145_acl as
    select p.oid::regprocedure::text as sig, p.proacl::text as acl
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'store_day' and p.pronargs = 2;

\i database/migrations/145_day_ranges.sql
\i database/migrations/145_day_ranges.sql

begin;

-- 011's store_day, word for word, to compare with.
create function pg_temp.store_day_011(p_org_id uuid, p_on date default current_date)
returns table (sales_total numeric, returns_total numeric, net_sales numeric,
               sale_count int, items_sold numeric)
language sql stable
as $$
    select
        coalesce(sum(s.total) filter (where s.kind = 'sale'), 0),
        coalesce(sum(s.total) filter (where s.kind = 'return'), 0),
        coalesce(sum(s.total) filter (where s.kind = 'sale'), 0)
          - coalesce(sum(s.total) filter (where s.kind = 'return'), 0),
        count(*) filter (where s.kind = 'sale')::int,
        coalesce((
            select sum(l.quantity)
            from sale_lines l
            join sales s2 on s2.id = l.sale_id
            where s2.org_id = p_org_id
              and s2.kind = 'sale'
              and (s2.occurred_at at time zone 'UTC')::date = p_on
        ), 0)
    from sales s
    where s.org_id = p_org_id
      and (s.occurred_at at time zone 'UTC')::date = p_on;
$$;

-- Tuples a call read from a table, this transaction: its sequential reads
-- and the rows its index scans fetched.
create function pg_temp.b145_read(p_table text) returns bigint
language sql volatile as $$
    select coalesce(seq_tup_read, 0) + coalesce(idx_tup_fetch, 0)
      from pg_stat_xact_all_tables
     where schemaname = 'public' and relname = p_table;
$$;

create function pg_temp.b145_plan(p_sql text) returns text
language plpgsql volatile as $$
declare r record; v text := '';
begin
    for r in execute 'explain (costs off) ' || p_sql loop
        v := v || r."QUERY PLAN" || E'\n';
    end loop;
    return v;
end $$;

insert into auth.users (id, phone, raw_user_meta_data) values
    ('14514514-0000-0000-0000-000000000001', '+22614500001', '{"full_name": "Awa"}'),
    ('14514514-0000-0000-0000-000000000002', '+22614500002', '{"full_name": "Un autre"}');
insert into orgs (id, name, slug, profile, default_currency) values
    ('14500000-0000-0000-0000-000000000001', 'Boutique Awa',   'b145-boutique-awa',  'retail', 'XOF'),
    ('14500000-0000-0000-0000-000000000002', 'Boutique Niamey','b145-boutique-niamey','retail', 'XOF'),
    ('14500000-0000-0000-0000-000000000003', 'Boutique Autre', 'b145-boutique-autre', 'retail', 'XOF');
insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    ('14500000-0000-0000-0000-000000000001', '14514514-0000-0000-0000-000000000001', 'owner', 'org', '14500000-0000-0000-0000-000000000001'),
    ('14500000-0000-0000-0000-000000000003', '14514514-0000-0000-0000-000000000002', 'owner', 'org', '14500000-0000-0000-0000-000000000003');

-- A year and more of a busy shop: 50 sales a day for 400 days, every
-- seventh a return, each with a line; and at every UTC midnight one at
-- 00:00:00 and one at 23:59:59.999. Written as rows, not through
-- record_sale (now() is its clock), with the after-insert bookkeeping
-- (cauris, Le Chemin) off for the bulk.
set local session_replication_role = replica;
insert into products (id, org_id, name, quantity)
select ('14500000-0000-0000-0001-' || lpad(i::text, 12, '0'))::uuid,
       '14500000-0000-0000-0000-000000000001', 'Article ' || i, 10
  from generate_series(1, 200) i;
insert into sales (id, org_id, kind, occurred_at, total)
select ('14500000-0000-0000-0002-' || lpad((d * 100 + j)::text, 12, '0'))::uuid,
       '14500000-0000-0000-0000-000000000001',
       case when j % 7 = 0 then 'return' else 'sale' end,
       timestamptz '2025-09-01 00:00:00+00' + d * interval '1 day'
         + case j when 0 then interval '0'
                  when 1 then interval '1 day' - interval '1 millisecond'
                  else j * interval '29 minutes' end,
       100 + j
  from generate_series(0, 399) d, generate_series(0, 49) j;
insert into sale_lines (sale_id, product_id, name, quantity, unit_price, line_total)
select s.id, ('14500000-0000-0000-0001-' || lpad((1 + (row_number() over (order by s.id)) % 200)::text, 12, '0'))::uuid,
       'Article', 1 + (extract(minute from s.occurred_at)::int % 3), s.total, s.total
  from sales s where s.org_id = '14500000-0000-0000-0000-000000000001';
-- 50 photos an item, a few receipts about no item.
insert into documents (org_id, r2_key, kind, content_type, uploaded_by, product_id, captured_at, created_at)
select '14500000-0000-0000-0000-000000000001', 'b145/' || p || '/' || k, 'product_photo', 'image/jpeg',
       '14514514-0000-0000-0000-000000000001',
       ('14500000-0000-0000-0001-' || lpad(p::text, 12, '0'))::uuid,
       case when k % 5 = 0 then null else timestamptz '2026-01-01 00:00+00' + k * interval '1 hour' end,
       timestamptz '2026-01-01 00:00+00' + k * interval '1 hour' + interval '30 minutes'
  from generate_series(1, 200) p, generate_series(1, 50) k;
insert into documents (org_id, r2_key, kind, uploaded_by, created_at)
select '14500000-0000-0000-0000-000000000001', 'b145/receipt/' || k, 'receipt',
       '14514514-0000-0000-0000-000000000001', now()
  from generate_series(1, 500) k;
set local session_replication_role = origin;
analyze sales;
analyze sale_lines;
analyze documents;

\echo ''
\echo '--- 1. an item''s newest photo, by documents_by_product ---'
do $$
declare
    v_def  text;
    v_plan text;
    v_key  text;
    v_read bigint;
begin
    select indexdef into v_def from pg_indexes
     where schemaname = 'public' and indexname = 'documents_by_product';
    if v_def is null
       or v_def not like '%ON public.documents USING btree (product_id, COALESCE(captured_at, created_at) DESC) WHERE (product_id IS NOT NULL)' then
        raise exception 'FAIL: documents_by_product is %', v_def;
    end if;

    v_plan := pg_temp.b145_plan($q$
        select d.r2_key from documents d
         where d.product_id = '14500000-0000-0000-0001-000000000007'
           and doc_is_photo(d.kind, d.content_type)
         order by coalesce(d.captured_at, d.created_at) desc
         limit 1 $q$);
    if v_plan not like '%documents_by_product%' then
        raise exception 'FAIL: the newest photo is not read by the index:%', E'\n' || v_plan;
    end if;

    -- product_cover_key (136), the street's and the search's cover.
    v_read := pg_temp.b145_read('documents');
    v_key := product_cover_key('14500000-0000-0000-0001-000000000007');
    v_read := pg_temp.b145_read('documents') - v_read;
    -- k = 50 has no capture date, so its created_at (50 h 30) stands in
    -- and is the newest of all.
    if v_key is distinct from 'b145/7/50' then
        raise exception 'FAIL: the cover is %, not the newest photo b145/7/50', v_key;
    end if;
    if v_read > 10 then
        raise exception 'FAIL: product_cover_key read % documents for one item', v_read;
    end if;
    raise notice 'PASS: documents_by_product as 136 orders photos; the planner takes it; a cover reads % document(s) of 10 500', v_read;
end $$;

\echo ''
\echo '--- 2. store_day reads its day off sales_by_day ---'
do $$
declare
    v_plan text;
    v_new  bigint;
    v_old  bigint;
    v_two  bigint;
    r record;
begin
    -- The body's two reads, as 145 writes them.
    v_plan := pg_temp.b145_plan($q$
        select count(*) from sales s
         where s.org_id = '14500000-0000-0000-0000-000000000001'
           and s.occurred_at >= timestamptz '2026-03-10 00:00+00'
           and s.occurred_at <  timestamptz '2026-03-11 00:00+00' $q$);
    if v_plan not like '%sales_by_day%' or v_plan not like '%occurred_at >=%' then
        raise exception 'FAIL: the day is not a range on sales_by_day:%', E'\n' || v_plan;
    end if;
    v_plan := pg_temp.b145_plan($q$
        select sum(l.quantity) from sales s2 join sale_lines l on l.sale_id = s2.id
         where s2.org_id = '14500000-0000-0000-0000-000000000001' and s2.kind = 'sale'
           and s2.occurred_at >= timestamptz '2026-03-10 00:00+00'
           and s2.occurred_at <  timestamptz '2026-03-11 00:00+00' $q$);
    if v_plan not like '%sales_by_day%' then
        raise exception 'FAIL: the lines'' subquery does not use sales_by_day:%', E'\n' || v_plan;
    end if;

    v_new := pg_temp.b145_read('sales');
    select * into r from store_day('14500000-0000-0000-0000-000000000001', date '2026-03-10', 0);
    v_new := pg_temp.b145_read('sales') - v_new;
    v_old := pg_temp.b145_read('sales');
    select * into r from pg_temp.store_day_011('14500000-0000-0000-0000-000000000001', date '2026-03-10');
    v_old := pg_temp.b145_read('sales') - v_old;
    -- Two reads of a 50-sale day (and the day's neighbours at most).
    if v_new > 300 then
        raise exception 'FAIL: store_day read % sales for one day', v_new;
    end if;
    if v_old < 20000 then
        raise exception 'FAIL: 011''s text read only % sales — the comparison proves nothing', v_old;
    end if;
    v_two := pg_temp.b145_read('sales');
    select * into r from store_day('14500000-0000-0000-0000-000000000001', date '2026-03-10');
    v_two := pg_temp.b145_read('sales') - v_two;
    if v_two > 300 then
        raise exception 'FAIL: the two-argument store_day read % sales for one day', v_two;
    end if;
    raise notice 'PASS: one day read off sales_by_day: % sales read (% by the old door), where 011''s text read %', v_new, v_two, v_old;
end $$;

\echo ''
\echo '--- 3. a UTC shop: the same answer as 011, day by day ---'
do $$
declare
    d date;
    a text;
    b text;
    c text;
    v_days int := 0;
    v_some int := 0;
    r record;
begin
    for d in select g::date from generate_series(date '2025-08-30', date '2026-10-06', interval '1 day') g loop
        select x::text into a from pg_temp.store_day_011('14500000-0000-0000-0000-000000000001', d) x;
        select x::text into b from store_day('14500000-0000-0000-0000-000000000001', d) x;
        select x::text into c from store_day('14500000-0000-0000-0000-000000000001', d, 0) x;
        if a is distinct from b or a is distinct from c then
            raise exception 'FAIL: % — 011 says %, store_day says %, at offset 0 %', d, a, b, c;
        end if;
        v_days := v_days + 1;
        if a <> '(0,0,0,0,0)' then v_some := v_some + 1; end if;
    end loop;
    if v_some <> 400 then
        raise exception 'FAIL: % days had sales, not 400', v_some;
    end if;
    -- A day's 00:00:00 sale and its 23:59:59.999 one are its own.
    select * into r from store_day('14500000-0000-0000-0000-000000000001', date '2025-09-01');
    if r.sale_count <> 42 or r.returns_total <> 100 + 107 + 114 + 121 + 128 + 135 + 142 + 149 then
        raise exception 'FAIL: the first day reads % sales, % returned', r.sale_count, r.returns_total;
    end if;
    -- No date: today, as before, and nothing sold today here.
    select x::text into a from store_day('14500000-0000-0000-0000-000000000003') x;
    if a <> '(0,0,0,0,0)' then
        raise exception 'FAIL: an empty day reads %', a;
    end if;
    raise notice 'PASS: % days compared with 011''s text, every one the same (with and without the offset 0)', v_days;
end $$;

\echo ''
\echo '--- 4. a shop at UTC+1 (and UTC-1) counts its own day ---'
do $$
declare
    a record;
begin
    set local session_replication_role = replica;
    insert into sales (org_id, kind, occurred_at, total) values
        -- 23:30 in Niamey on 14 October.
        ('14500000-0000-0000-0000-000000000002', 'sale', timestamptz '2026-10-14 22:30:00+00', 1000),
        -- 00:30 in Niamey on 15 October: still the 14th in UTC.
        ('14500000-0000-0000-0000-000000000002', 'sale', timestamptz '2026-10-14 23:30:00+00', 2000),
        -- 00:30 UTC on the 15th: 23:30 on the 14th at UTC-1.
        ('14500000-0000-0000-0000-000000000002', 'sale', timestamptz '2026-10-15 00:30:00+00', 4000);
    set local session_replication_role = origin;

    select * into a from store_day('14500000-0000-0000-0000-000000000002', date '2026-10-14', 60);
    if a.sales_total <> 1000 or a.sale_count <> 1 then
        raise exception 'FAIL: at UTC+1 the 14th reads % sold, % sales (expected the 23:30 sale alone)', a.sales_total, a.sale_count;
    end if;
    select * into a from store_day('14500000-0000-0000-0000-000000000002', date '2026-10-15', 60);
    if a.sales_total <> 6000 or a.sale_count <> 2 then
        raise exception 'FAIL: at UTC+1 the 15th reads % sold, % sales (expected 00:30 and 01:30 local)', a.sales_total, a.sale_count;
    end if;
    -- The UTC door, as an older app sees it: the 00:30 sale on the 14th.
    select * into a from store_day('14500000-0000-0000-0000-000000000002', date '2026-10-14');
    if a.sales_total <> 3000 then
        raise exception 'FAIL: the UTC door reads % for the 14th', a.sales_total;
    end if;
    select * into a from store_day('14500000-0000-0000-0000-000000000002', date '2026-10-14', -60);
    if a.sales_total <> 7000 or a.sale_count <> 3 then
        raise exception 'FAIL: at UTC-1 the 14th reads % sold, % sales', a.sales_total, a.sale_count;
    end if;
    begin
        perform store_day('14500000-0000-0000-0000-000000000002', date '2026-10-14', 900);
        raise exception 'FAIL: an offset of 15 h was accepted';
    exception when invalid_parameter_value then null;
    end;
    begin
        perform store_day('14500000-0000-0000-0000-000000000002', date '2026-10-14', null);
        raise exception 'FAIL: a null offset was accepted';
    exception when invalid_parameter_value then null;
    end;
    raise notice 'PASS: at UTC+1 the 23:30 sale on its day, the 00:30 one on the next; UTC-1 too; past ±14 h refused';
end $$;

\echo ''
\echo '--- 5. still the policies that decide ---'
set local role authenticated;
set local "request.jwt.claim.sub" = '14514514-0000-0000-0000-000000000002';
do $$
declare a record;
begin
    select * into a from store_day('14500000-0000-0000-0000-000000000001', date '2026-03-10', 0);
    if a.sale_count <> 0 or a.sales_total <> 0 then
        raise exception 'FAIL: a stranger to the shop added up % sales', a.sale_count;
    end if;
    select * into a from store_day('14500000-0000-0000-0000-000000000001', date '2026-03-10');
    if a.sale_count <> 0 then
        raise exception 'FAIL: a stranger to the shop added up % sales (two-argument door)', a.sale_count;
    end if;
end $$;
set local "request.jwt.claim.sub" = '14514514-0000-0000-0000-000000000001';
do $$
declare a record;
begin
    select * into a from store_day('14500000-0000-0000-0000-000000000001', date '2026-03-10', 0);
    if a.sale_count <> 42 then
        raise exception 'FAIL: the owner reads % sales', a.sale_count;
    end if;
    raise notice 'PASS: SECURITY INVOKER — a stranger adds up nothing, the owner the day (% sales)', a.sale_count;
end $$;
reset role;

\echo ''
\echo '--- 6. the doors ---'
do $$
declare
    v_old oid := 'store_day(uuid, date)'::regprocedure;
    v_new oid := 'store_day(uuid, date, integer)'::regprocedure;
    v_changed text;
begin
    select string_agg(b.sig, ', ') into v_changed
      from b145_acl b
      join pg_proc p on p.oid::regprocedure::text = b.sig
     where p.proacl::text is distinct from b.acl;
    if v_changed is not null then
        raise exception 'FAIL: re-running 145 changed the grants of %', v_changed;
    end if;
    if (select prosecdef from pg_proc where oid = v_old) or (select prosecdef from pg_proc where oid = v_new) then
        raise exception 'FAIL: store_day became SECURITY DEFINER';
    end if;
    if (select pronargdefaults from pg_proc where oid = v_old) <> 1
       or (select pronargdefaults from pg_proc where oid = v_new) <> 0 then
        raise exception 'FAIL: the defaults moved (two-argument door must keep p_on''s, the new one has none)';
    end if;
    if pg_get_function_result(v_old) <> 'TABLE(sales_total numeric, returns_total numeric, net_sales numeric, sale_count integer, items_sold numeric)'
       or pg_get_function_result(v_new) <> pg_get_function_result(v_old) then
        raise exception 'FAIL: the columns are % / %', pg_get_function_result(v_old), pg_get_function_result(v_new);
    end if;
    if exists (select 1 from pg_proc where oid in (v_old, v_new)
                and not (coalesce(proconfig, '{}') @> array['search_path=public, auth'])) then
        raise exception 'FAIL: a store_day without its pinned search_path';
    end if;
    if not has_function_privilege('authenticated', v_new, 'execute') then
        raise exception 'FAIL: the till''s home cannot call store_day(uuid, date, int)';
    end if;
    if has_function_privilege('anon', v_new, 'execute') then
        raise exception 'FAIL: anon can call store_day(uuid, date, int)';
    end if;
    if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                where p.oid = v_new and a.grantee = 0) then
        raise exception 'FAIL: PUBLIC can call store_day(uuid, date, int)';
    end if;
    if not has_function_privilege('authenticated', v_old, 'execute') then
        raise exception 'FAIL: an older app cannot call store_day(uuid, date)';
    end if;
    raise notice 'PASS: store_day(uuid, date) as it was (signature, default, columns, search_path, grants); the new door authenticated''s alone';
end $$;

rollback;

drop table b145_acl;
\echo ''
\echo 'test_batch145: all claims held'
