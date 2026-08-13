-- ============================================================
-- test_capture.sql — proof that a photograph costs nothing to take and
-- cannot be taken from somebody else.
--
-- Runs as `authenticated` throughout, never as postgres. Half of what is
-- asserted below is an RLS policy and the rest is a SECURITY DEFINER
-- function's own membership check; a superuser sails through both and would
-- report a clean pass against no protection at all.
--
-- The five things this suite is actually about:
--
--   1. A capture with no fields filled in. If this ever starts requiring
--      something, the module has lost the only property M5 asks it to have.
--   2. A phone in a market retrying an upload, and the gallery growing by
--      two.
--   3. One shop recording another shop's object key and reading the picture
--      back through it — the whole reason the key is checked against the org
--      id rather than trusted.
--   4. OCR quietly becoming authoritative. A misread expiry date that lands
--      in products.expires_on is the exact loss this module exists to
--      prevent, with the app's name on it.
--   5. A receipt disappearing. There is no delete policy on documents and
--      this suite is what notices if one is ever added.
--
-- Phone block 80. The others: 70 rls, 71 invitations, 72 reports,
-- 73 accounting, 74 audit, 75/76 farm, 77 platform admin, 78 retail,
-- 79 employees.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''80808080-0000-0000-0000-000000000001'''
\set clerk '''80808080-0000-0000-0000-000000000002'''
\set rival '''80808080-0000-0000-0000-000000000003'''
\set watch '''80808080-0000-0000-0000-000000000004'''

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
    (:owner, '+22680000001', '{"full_name": "Esperance"}'),
    (:clerk, '+22680000002', '{"full_name": "Vendeuse"}'),
    (:rival, '+22680000003', '{"full_name": "Un autre commerçant"}'),
    (:watch, '+22680000004', '{"full_name": "Observateur"}');

-- Two shops, because most of this file is one of them reaching for the
-- other's photographs.
insert into orgs (id, name, slug, profile, default_currency) values
    ('80000000-0000-0000-0000-000000000001', 'Boutique Photo',  'boutique-photo',  'retail', 'XOF'),
    ('80000000-0000-0000-0000-000000000002', 'Boutique Voisine', 'boutique-voisine', 'retail', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    ('80000000-0000-0000-0000-000000000001', :owner, 'owner',    'org', '80000000-0000-0000-0000-000000000001', 'full'),
    ('80000000-0000-0000-0000-000000000001', :clerk, 'employee', 'org', '80000000-0000-0000-0000-000000000001', 'full'),
    ('80000000-0000-0000-0000-000000000001', :watch, 'observer', 'org', '80000000-0000-0000-0000-000000000001', 'summary'),
    ('80000000-0000-0000-0000-000000000002', :rival, 'owner',    'org', '80000000-0000-0000-0000-000000000002', 'full');

select seed_retail_accounts('80000000-0000-0000-0000-000000000001');
select seed_retail_accounts('80000000-0000-0000-0000-000000000002');

-- The neighbour's product, created here as the table owner rather than
-- inside a test: Esperance cannot insert into his shop and that refusal is
-- test_rls.sql's assertion, not this suite's. What TEST 8 needs is a real
-- product id belonging to somebody else to aim a document at.
insert into products (id, org_id, name, sale_price)
values ('80000000-0000-0000-0000-0000000000f1',
        '80000000-0000-0000-0000-000000000002', 'Article du voisin', 500);

\echo ''
\echo '--- TEST 1: a capture with nothing filled in ---'
begin;
set local "request.jwt.claim.sub" = '80808080-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_doc uuid;
    v_row documents%rowtype;
    v_unfiled int;
begin
    -- Everything but the org and the key left out. This is the call the
    -- camera button makes, and it is the whole design of the module.
    v_doc := record_document('80000000-0000-0000-0000-000000000001',
                             'org/80000000-0000-0000-0000-000000000001/2026/photo-un.jpg');

    select * into v_row from documents where id = v_doc;

    if v_row.caption is not null or v_row.product_id is not null
       or v_row.linked_journal_entry_id is not null then
        raise exception 'FAIL: a bare capture came out with fields filled in';
    end if;
    if v_row.ocr_status <> 'pending' then
        raise exception 'FAIL: ocr_status is %, expected pending', v_row.ocr_status;
    end if;
    if v_row.captured_at is null then
        raise exception 'FAIL: nothing recorded when the photo was taken';
    end if;
    if v_row.uploaded_by <> '80808080-0000-0000-0000-000000000001' then
        raise exception 'FAIL: the photo was filed under %', v_row.uploaded_by;
    end if;

    -- And it lands in the pile on the counter rather than nowhere.
    select count(*) into v_unfiled
    from unfiled_documents('80000000-0000-0000-0000-000000000001');
    if v_unfiled <> 1 then
        raise exception 'FAIL: % documents waiting to be filed, expected 1', v_unfiled;
    end if;

    raise notice 'PASS: a photograph with no fields at all is a complete record';
end $$;
commit;

\echo ''
\echo '--- TEST 2: a retried upload is one photograph ---'
begin;
set local "request.jwt.claim.sub" = '80808080-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_first  uuid;
    v_second uuid;
    v_third  uuid;
    v_count  int;
    v_uuid   uuid := 'cccccccc-0000-0000-0000-000000000080';
    v_key    text := 'org/80000000-0000-0000-0000-000000000001/2026/retry.jpg';
begin
    v_first  := record_document('80000000-0000-0000-0000-000000000001', v_key,
                                'receipt', null, 'image/jpeg', 91234,
                                now(), v_uuid);
    v_second := record_document('80000000-0000-0000-0000-000000000001', v_key,
                                'receipt', null, 'image/jpeg', 91234,
                                now(), v_uuid);
    if v_first is distinct from v_second then
        raise exception 'FAIL: the retry made a second document (% and %)',
            v_first, v_second;
    end if;

    -- And the same key sent by a phone that lost its client_uuid — a
    -- reinstall — is still the same photograph, because the object it points
    -- at is the same bytes.
    v_third := record_document('80000000-0000-0000-0000-000000000001', v_key);
    if v_third is distinct from v_first then
        raise exception 'FAIL: the same object was recorded twice';
    end if;

    select count(*) into v_count from documents
    where org_id = '80000000-0000-0000-0000-000000000001' and r2_key = v_key;
    if v_count <> 1 then
        raise exception 'FAIL: % rows point at one object', v_count;
    end if;

    raise notice 'PASS: three uploads of one photograph are one document';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: a shop cannot record another shop''s object ---'
begin;
set local "request.jwt.claim.sub" = '80808080-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_doc uuid;
begin
    -- The neighbour knows the key — it was in a URL, or a log. Recording it
    -- against his own org would put Esperance's picture in his gallery and
    -- let him fetch it back through the download route, which authorises on
    -- the document row.
    begin
        v_doc := record_document(
            '80000000-0000-0000-0000-000000000002',
            'org/80000000-0000-0000-0000-000000000001/2026/photo-un.jpg');
        raise exception 'FAIL: he recorded a neighbour''s photograph as his own';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;

    -- And recording one directly against the shop he is not in is refused
    -- too, by the membership check rather than the key check.
    begin
        v_doc := record_document(
            '80000000-0000-0000-0000-000000000001',
            'org/80000000-0000-0000-0000-000000000001/2026/photo-deux.jpg');
        raise exception 'FAIL: he captured into a business he is not a member of';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 4: details arrive later, and do not erase each other ---'
begin;
set local "request.jwt.claim.sub" = '80808080-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_doc     uuid;
    v_product uuid;
    v_row     documents%rowtype;
    v_unfiled int;
begin
    select id into v_doc from documents
    where org_id = '80000000-0000-0000-0000-000000000001'
      and r2_key = 'org/80000000-0000-0000-0000-000000000001/2026/photo-un.jpg';

    v_product := ensure_product('80000000-0000-0000-0000-000000000001',
                                'Lait concentré', 500, 400,
                                '80808080-0000-0000-0000-000000000001');

    perform file_document(v_doc, null, null, null, v_product);
    -- A second visit, weeks later, giving it a name and nothing else. This is
    -- the call that would erase the product link if file_document() wrote
    -- nulls over what it was not given.
    perform file_document(v_doc, 'Livraison du 12 août');

    select * into v_row from documents where id = v_doc;
    if v_row.product_id is distinct from v_product then
        raise exception 'FAIL: naming the photo unlinked the product';
    end if;
    if v_row.caption <> 'Livraison du 12 août' then
        raise exception 'FAIL: caption is %', v_row.caption;
    end if;

    select count(*) into v_unfiled
    from unfiled_documents('80000000-0000-0000-0000-000000000001');
    if v_unfiled <> 0 then
        raise exception 'FAIL: % still waiting to be filed after filing it', v_unfiled;
    end if;

    raise notice 'PASS: filed once as a product, once as a name, both kept';
end $$;
commit;

\echo ''
\echo '--- TEST 5: OCR is advisory and changes nothing on its own ---'
begin;
set local "request.jwt.claim.sub" = '80808080-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_doc     uuid;
    v_product uuid;
    v_before  date;
    v_after   date;
    v_row     documents%rowtype;
begin
    select id, product_id into v_doc, v_product from documents
    where org_id = '80000000-0000-0000-0000-000000000001'
      and r2_key = 'org/80000000-0000-0000-0000-000000000001/2026/photo-un.jpg';

    select expires_on into v_before from products where id = v_product;

    -- A phone reading a date badly off a crumpled label. If this ever moves
    -- a product's expiry on its own, the app has invented an expiry date and
    -- put its own name on the loss.
    perform set_document_ocr(v_doc,
        E'LAIT CONCENTRE SUCRE\nEXP 01/01/2019\nPRIX 500',
        '6001234567890');

    select expires_on into v_after from products where id = v_product;
    if v_after is distinct from v_before then
        raise exception 'FAIL: OCR moved a product expiry from % to %', v_before, v_after;
    end if;

    select * into v_row from documents where id = v_doc;
    if v_row.ocr_status <> 'done' or v_row.ocr_text is null then
        raise exception 'FAIL: the reading was not kept (status %)', v_row.ocr_status;
    end if;
    if v_row.barcode <> '6001234567890' then
        raise exception 'FAIL: barcode stored as %', v_row.barcode;
    end if;

    raise notice 'PASS: the phone''s reading is stored and authoritative over nothing';
end $$;
commit;

\echo ''
\echo '--- TEST 6: a barcode finds this shop''s product and no other shop''s ---'
begin;
set local "request.jwt.claim.sub" = '80808080-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_product uuid;
    v_found   uuid;
    v_name    text;
begin
    select id into v_product from products
    where org_id = '80000000-0000-0000-0000-000000000001' and name = 'Lait concentré';

    update products set barcode = '6001234567890' where id = v_product;

    select id, name into v_found, v_name
    from product_by_barcode('80000000-0000-0000-0000-000000000001', '6001234567890');
    if v_found is distinct from v_product then
        raise exception 'FAIL: the scan found % instead of the product', v_found;
    end if;

    -- The neighbour's shop sells the same tin. Scanning it there must find
    -- nothing rather than reach across.
    if exists (select 1 from product_by_barcode(
                   '80000000-0000-0000-0000-000000000002', '6001234567890')) then
        raise exception 'FAIL: a scan reached into another business';
    end if;

    raise notice 'PASS: % found by barcode, and only in its own shop', v_name;
end $$;
rollback;

\echo ''
\echo '--- TEST 7: a summary observer sees no photographs ---'
begin;
set local "request.jwt.claim.sub" = '80808080-0000-0000-0000-000000000004';
set local role authenticated;
do $$
declare
    v_docs int;
begin
    -- 006 made a receipt a transaction with a picture attached: reading one
    -- requires full visibility, not mere membership. An observer entitled to
    -- totals is not entitled to the invoice they were computed from.
    select count(*) into v_docs from documents;
    if v_docs <> 0 then
        raise exception 'FAIL: a summary observer sees % photographs', v_docs;
    end if;

    select count(*) into v_docs
    from org_documents('80000000-0000-0000-0000-000000000001');
    if v_docs <> 0 then
        raise exception 'FAIL: the gallery handed a summary observer % rows', v_docs;
    end if;

    raise notice 'PASS: the totals, not the paperwork behind them';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: a photograph cannot be deleted, or pointed at a stranger ---'
begin;
set local "request.jwt.claim.sub" = '80808080-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_before  int;
    v_after   int;
    v_doc     uuid;
    v_foreign uuid;
begin
    select count(*) into v_before from documents
    where org_id = '80000000-0000-0000-0000-000000000001';

    -- No delete policy exists on documents, and a missing policy denies
    -- rather than errors: the statement succeeds and removes nothing.
    delete from documents where org_id = '80000000-0000-0000-0000-000000000001';

    select count(*) into v_after from documents
    where org_id = '80000000-0000-0000-0000-000000000001';
    if v_after <> v_before then
        raise exception 'FAIL: % receipts were deleted', v_before - v_after;
    end if;

    -- A direct write, bypassing file_document() and its checks. The policy is
    -- what holds here, which is the entire reason it exists as well as the
    -- function check.
    select id into v_doc from documents
    where org_id = '80000000-0000-0000-0000-000000000001' limit 1;

    v_foreign := '80000000-0000-0000-0000-0000000000f1';

    begin
        update documents set product_id = v_foreign where id = v_doc;
        -- An RLS check violation raises; reaching here means it did not.
        if (select product_id from documents where id = v_doc) = v_foreign then
            raise exception 'FAIL: a document now points at another shop''s product';
        end if;
        raise notice 'PASS: the update matched no row';
    exception
        when insufficient_privilege or check_violation then
            raise notice 'PASS: refused — %', sqlerrm;
    end;

    raise notice 'PASS: % receipts still there', v_after;
end $$;
rollback;

\echo ''
\echo 'test_capture.sql: all assertions held.'
