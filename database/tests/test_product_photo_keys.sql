-- ============================================================
-- test_product_photo_keys.sql — every article's picture in one call (079).
-- Phone block 49.
--
-- The claims: one row per article that has a photograph, the newest; a
-- PDF filed against an article is not its picture; an article with none
-- has no row; and another shop's member gets nothing — documents' own
-- policy decides, the function adds no reach.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''49494949-0000-0000-0000-000000000001'''
\set other '''49494949-0000-0000-0000-000000000002'''
\set shop  '''49000000-0000-0000-0000-000000000001'''
\set far   '''49000000-0000-0000-0000-000000000002'''
\set cake  '''49aaaaaa-0000-0000-0000-000000000001'''
\set sugar '''49aaaaaa-0000-0000-0000-000000000002'''
\set eggs  '''49aaaaaa-0000-0000-0000-000000000003'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22649000001', '{"full_name": "Awa"}'),
    (:other, '+22649000002', '{"full_name": "Voisine"}');
insert into orgs (id, name, slug, profile, default_currency) values
    (:shop, 'Shop Style', 'style-49', 'retail', 'XOF'),
    (:far,  'Ailleurs',   'ailleurs-49', 'retail', 'XOF');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop, :owner, 'owner', 'org', :shop, 'full'),
    (:far,  :other, 'owner', 'org', :far,  'full');
insert into products (id, org_id, name, sale_price, quantity, created_by) values
    (:cake,  :shop, 'Gateau', 200, 30, :owner),
    (:sugar, :shop, 'Sucre',  0,   1,  :owner),
    (:eggs,  :shop, 'Oeuf',   0,   1,  :owner);
insert into documents (org_id, r2_key, kind, uploaded_by, product_id, content_type, captured_at) values
    (:shop, 'org/49/cake-old.jpg', 'product_photo', :owner, :cake,  'image/jpeg', now() - interval '2 days'),
    (:shop, 'org/49/cake-new.jpg', 'product_photo', :owner, :cake,  'image/jpeg', now() - interval '1 day'),
    (:shop, 'org/49/sugar.jpg',    'product_photo', :owner, :sugar, 'image/jpeg', now() - interval '3 days'),
    -- The newest thing filed against sugar is its delivery note, a PDF.
    (:shop, 'org/49/sugar-bl.pdf', 'invoice',       :owner, :sugar, 'application/pdf', now());

\echo ''
\echo '--- TEST 1: one picture per article, the newest, never a PDF ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '49494949-0000-0000-0000-000000000001';
do $$
declare got jsonb;
begin
    select jsonb_object_agg(product_id, photo_key) into got
      from product_photo_keys('49000000-0000-0000-0000-000000000001');
    if got <> jsonb_build_object(
            '49aaaaaa-0000-0000-0000-000000000001', 'org/49/cake-new.jpg',
            '49aaaaaa-0000-0000-0000-000000000002', 'org/49/sugar.jpg') then
        raise exception 'FAIL: the shop''s pictures are %', got;
    end if;
    raise notice 'PASS: Gateau''s newest photo, Sucre''s photo not its PDF, Oeuf none';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: another shop''s member sees none of them ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '49494949-0000-0000-0000-000000000002';
do $$ begin
    if exists (select 1 from product_photo_keys('49000000-0000-0000-0000-000000000001')) then
        raise exception 'FAIL: a stranger read another shop''s photo keys';
    end if;
    raise notice 'PASS: documents'' policy holds through the function';
end $$;
rollback;

\echo ''
\echo 'test_product_photo_keys: all passed'
