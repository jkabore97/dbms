-- ============================================================
-- test_delivery.sql — M5's demo, end to end, on the database side.
--
-- The plan's sentence: *she photographs a delivery invoice and the products
-- are in the system without typing.* Reading the paper is pure Dart and is
-- covered by app/test/invoice_reading_test.dart. What this suite proves is
-- the other half — that what the reading produces can actually be written,
-- and that writing it leaves the books correct.
--
-- Four things a delivery module gets wrong, and each is a case below:
--
--   1. Stock arrives but the money does not. The count goes up, no expense is
--      recorded, and the shop looks more profitable every time it buys
--      something.
--   2. The delivery is entered twice, because the confirm screen was pressed
--      again after a connection dropped halfway through nine lines.
--   3. A supplier's price is written into the shelf price, zeroing the margin
--      on everything that arrived.
--   4. The photograph and the goods come apart, so the evidence for a
--      delivery cannot be found from the delivery.
--
-- Phone block 82. The others: 70 rls, 71 invitations, 72 reports,
-- 73 accounting, 74 audit, 75/76 farm, 77 platform admin, 78 retail,
-- 79 employees, 80 capture, 81 org lifecycle.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''82828282-0000-0000-0000-000000000001'''

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22682000001', '{"full_name": "Esperance"}');

insert into orgs (id, name, slug, profile, default_currency) values
    ('82000000-0000-0000-0000-000000000001', 'Boutique Livraison', 'boutique-livraison', 'retail', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    ('82000000-0000-0000-0000-000000000001', :owner, 'owner', 'org', '82000000-0000-0000-0000-000000000001');

select seed_retail_accounts('82000000-0000-0000-0000-000000000001');

\echo ''
\echo '--- TEST 1: five lines of paper become five products and one purchase ---'
begin;
set local "request.jwt.claim.sub" = '82828282-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    -- Exactly what InvoiceReading.parse() returns for the delivery note in
    -- app/test/invoice_reading_test.dart: name, quantity, unit cost.
    v_lines jsonb := '[
        {"name": "Savon de Marseille", "qty": 12, "cost": 500},
        {"name": "Riz parfumé",        "qty": 2,  "cost": 9000},
        {"name": "Huile",              "qty": 24, "cost": 750},
        {"name": "Sucre en poudre",    "qty": 6,  "cost": 650},
        {"name": "Lait concentré",     "qty": 48, "cost": 350}
    ]'::jsonb;
    v_line     jsonb;
    v_product  uuid;
    v_count    int;
    v_spent    numeric;
    v_quantity numeric;
begin
    for v_line in select * from jsonb_array_elements(v_lines) loop
        v_product := ensure_product(
            '82000000-0000-0000-0000-000000000001',
            v_line ->> 'name',
            null,                                   -- no shelf price: see TEST 3
            (v_line ->> 'cost')::numeric,
            null, null,
            '82828282-0000-0000-0000-000000000001');

        perform receive_products(
            '82000000-0000-0000-0000-000000000001',
            v_product,
            (v_line ->> 'qty')::numeric,
            (v_line ->> 'cost')::numeric);
    end loop;

    select count(*) into v_count from products
    where org_id = '82000000-0000-0000-0000-000000000001';
    if v_count <> 5 then
        raise exception 'FAIL: % products, expected 5', v_count;
    end if;

    select quantity into v_quantity from products
    where org_id = '82000000-0000-0000-0000-000000000001'
      and name = 'Lait concentré';
    if v_quantity <> 48 then
        raise exception 'FAIL: 48 tins arrived, % on the shelf', v_quantity;
    end if;

    -- The money. 12×500 + 2×9000 + 24×750 + 6×650 + 48×350 = 62 700, which is
    -- the total printed on the paper — and the first way a delivery module
    -- lies is by moving the goods and not the money.
    select coalesce(sum(jl.debit), 0) into v_spent
    from journal_lines jl
    join accounts a on a.id = jl.account_id
    where a.org_id = '82000000-0000-0000-0000-000000000001'
      and a.type = 'expense';

    if v_spent <> 62700 then
        raise exception 'FAIL: the books show % spent, the invoice says 62700',
            v_spent;
    end if;

    raise notice 'PASS: 5 articles on the shelves, 62 700 out of the till';
end $$;
commit;

\echo ''
\echo '--- TEST 2: pressing the button twice does not double the delivery ---'
begin;
set local "request.jwt.claim.sub" = '82828282-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_product uuid;
    v_before  numeric;
    v_after   numeric;
    v_uuid    uuid := 'dddddddd-0000-0000-0000-000000000082';
begin
    select id, quantity into v_product, v_before from products
    where org_id = '82000000-0000-0000-0000-000000000001' and name = 'Huile';

    -- The confirm screen mints one client_uuid per line and keeps it across
    -- retries, precisely so a loop that failed on line four can be pressed
    -- again without the first three arriving twice.
    perform receive_products('82000000-0000-0000-0000-000000000001',
                             v_product, 10, 750, null, 'cash', v_uuid);
    perform receive_products('82000000-0000-0000-0000-000000000001',
                             v_product, 10, 750, null, 'cash', v_uuid);

    select quantity into v_after from products where id = v_product;
    if v_after <> v_before + 10 then
        raise exception 'FAIL: 10 received twice became % (was %)',
            v_after, v_before;
    end if;

    raise notice 'PASS: the retry added 10, not 20';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: a supplier''s price is not a shelf price ---'
begin;
set local "request.jwt.claim.sub" = '82828282-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_cost  numeric;
    v_price numeric;
begin
    select cost_price, sale_price into v_cost, v_price from products
    where org_id = '82000000-0000-0000-0000-000000000001'
      and name = 'Savon de Marseille';

    if v_cost <> 500 then
        raise exception 'FAIL: cost recorded as %, expected 500', v_cost;
    end if;

    -- The delivery note says what she paid, and says nothing about what she
    -- will charge. Writing 500 into sale_price would put the margin at zero
    -- on everything that arrived, and no screen would ever mention it.
    if v_price <> 0 then
        raise exception
            'FAIL: the supplier''s price became the shelf price (%)', v_price;
    end if;

    raise notice 'PASS: 500 paid, nothing assumed about what it sells for';
end $$;
commit;

\echo ''
\echo '--- TEST 4: the paper stays attached to what arrived on it ---'
begin;
set local "request.jwt.claim.sub" = '82828282-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_doc     uuid;
    v_product uuid;
    v_photos  int;
    v_kind    text;
begin
    select id into v_product from products
    where org_id = '82000000-0000-0000-0000-000000000001'
      and name = 'Savon de Marseille';

    v_doc := record_document(
        '82000000-0000-0000-0000-000000000001',
        'org/82000000-0000-0000-0000-000000000001/2026/bon-de-livraison.jpg',
        'photo');

    -- What the confirm screen does once the stock is in.
    perform file_document(v_doc, null, 'invoice', null, v_product);

    select kind into v_kind from documents where id = v_doc;
    if v_kind <> 'invoice' then
        raise exception 'FAIL: the delivery note is filed as %', v_kind;
    end if;

    -- And it is findable from the product, which is how somebody asks
    -- "where did these come from, and what did we pay".
    select count(*) into v_photos from product_photos(v_product);
    if v_photos <> 1 then
        raise exception 'FAIL: the product has % photographs, expected 1',
            v_photos;
    end if;

    raise notice 'PASS: the delivery note is reachable from the goods';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: the books still balance ---'
do $$
declare
    v_debits  numeric;
    v_credits numeric;
begin
    select coalesce(sum(jl.debit), 0), coalesce(sum(jl.credit), 0)
      into v_debits, v_credits
    from journal_lines jl
    join accounts a on a.id = jl.account_id
    where a.org_id = '82000000-0000-0000-0000-000000000001';

    if v_debits <> v_credits then
        raise exception 'FAIL: debits % <> credits %', v_debits, v_credits;
    end if;
    if v_debits = 0 then
        raise exception 'FAIL: nothing was posted at all';
    end if;
    raise notice 'PASS: debits = credits = %', v_debits;
end $$;

\echo ''
\echo 'test_delivery.sql: all assertions held.'
