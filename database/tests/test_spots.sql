-- ============================================================
-- test_spots.sql — a shop buys a place on the street (071).
-- Phone block 43.
--
-- The claims: the street counts views, and an order counts itself; a spot
-- is asked by an admin only, for an article on the vitrine with a photo,
-- a price and stock, never twice at once; it waits for "J'ai payé" and the
-- platform's yes, then shows in À la une ahead of the hand-set ones; a
-- full strip queues the next spot behind the earliest end; Kaj Pro's
-- monthly spot starts at once and free, once; a shop spot lists the shop
-- in the spotlights; the report counts the spot's own days; strangers see
-- no promotions.
-- ============================================================
\set ON_ERROR_STOP on

\set owner  '''43434343-0000-0000-0000-000000000001'''
\set clerk  '''43434343-0000-0000-0000-000000000002'''
\set other  '''43434343-0000-0000-0000-000000000003'''
\set plat   '''43434343-0000-0000-0000-000000000004'''
\set shop   '''43000000-0000-0000-0000-000000000001'''
\set pro    '''43000000-0000-0000-0000-000000000002'''
\set photo  '''43aaaaaa-0000-0000-0000-000000000001'''
\set bare   '''43aaaaaa-0000-0000-0000-000000000002'''
\set prop   '''43aaaaaa-0000-0000-0000-000000000003'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname='anon') then
        create role anon nologin;
    end if;
end $$;
grant usage on schema public to authenticated, anon;
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22643000001', '{"full_name": "Propriétaire"}'),
    (:clerk, '+22643000002', '{"full_name": "Vendeuse"}'),
    (:other, '+22643000003', '{"full_name": "Étrangère"}'),
    (:plat,  '+22643000004', '{"full_name": "Plateforme"}');
update profiles set is_platform_admin = true where id = :plat;
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, plan, plan_until) values
    (:shop, 'Boutique Vue', 'vue-43', 'retail', 'XOF', true, 'free', null),
    (:pro,  'Boutique Pro', 'pro-43', 'retail', 'XOF', true, 'pro', current_date + 30);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop, :owner, 'owner',    'org', :shop, 'full'),
    (:shop, :clerk, 'employee', 'org', :shop, 'full'),
    (:pro,  :owner, 'owner',    'org', :pro,  'full');
insert into products (id, org_id, name, sale_price, quantity, is_active) values
    (:photo, :shop, 'Pagne',  5000, 4, true),
    (:bare,  :shop, 'Savon',   450, 9, true),
    (:prop,  :pro,  'Bissap',  150, 30, true);
insert into documents (org_id, r2_key, kind, uploaded_by, product_id) values
    (:shop, 'org/43000000-0000-0000-0000-000000000001/p.jpg', 'photo', :owner, :photo),
    (:pro,  'org/43000000-0000-0000-0000-000000000002/b.jpg', 'photo', :owner, :prop);


\echo ''
\echo '--- TEST 1: the street counts; an order counts itself; junk is ignored ---'
begin;
set local role anon;
select record_visit('vue-43', 'opened');
select record_visit('vue-43', 'seen',  '43aaaaaa-0000-0000-0000-000000000001');
select record_visit('vue-43', 'seen',  '43aaaaaa-0000-0000-0000-000000000001');
select record_visit('vue-43', 'added', '43aaaaaa-0000-0000-0000-000000000001');
select record_visit('vue-43', 'stolen');                                       -- unknown kind
select record_visit('vue-43', 'seen',  '43aaaaaa-0000-0000-0000-000000000003'); -- another shop's
select record_visit('nowhere', 'opened');
select record_seen(array['43aaaaaa-0000-0000-0000-000000000001'::uuid]);
reset role;
insert into orders (id, org_id, customer_id, customer_name, status, fulfilment, total, currency) values
    ('43bbbbbb-0000-0000-0000-000000000001', :shop, :other, 'Awa', 'pending', 'pickup', 5000, 'XOF');
insert into order_lines (order_id, product_id, name, unit_price, quantity) values
    ('43bbbbbb-0000-0000-0000-000000000001', :photo, 'Pagne', 5000, 1);
do $$
declare r record;
begin
    select * into r from storefront_visits
     where org_id = '43000000-0000-0000-0000-000000000001'
       and product_id = '43aaaaaa-0000-0000-0000-000000000001';
    if r.seen <> 3 or r.added <> 1 or r.ordered <> 1 then
        raise exception 'FAIL: article counts seen=% added=% ordered=%', r.seen, r.added, r.ordered;
    end if;
    if (select opened from storefront_visits
         where org_id = '43000000-0000-0000-0000-000000000001' and product_id is null) <> 1 then
        raise exception 'FAIL: the shop''s window opening was not counted once';
    end if;
    if (select count(*) from storefront_visits
         where org_id in ('43000000-0000-0000-0000-000000000001',
                          '43000000-0000-0000-0000-000000000002')) <> 2 then
        raise exception 'FAIL: junk visits were counted';
    end if;
    raise notice 'PASS: views, basket adds and orders counted; junk ignored';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: only an admin asks; the article must be ready; never twice ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '43434343-0000-0000-0000-000000000002';
do $$ begin
    perform request_promotion('43000000-0000-0000-0000-000000000001',
                              '43aaaaaa-0000-0000-0000-000000000001', 7);
    raise exception 'FAIL: an employee bought a spot';
exception when others then
    if sqlerrm not like 'Seul un administrateur%' then raise; end if;
end $$;
set local "request.jwt.claim.sub" = '43434343-0000-0000-0000-000000000001';
do $$ begin
    perform request_promotion('43000000-0000-0000-0000-000000000001',
                              '43aaaaaa-0000-0000-0000-000000000002', 7);
    raise exception 'FAIL: an article with no photo got a spot';
exception when others then
    if sqlerrm not like 'Un article mis en avant%' then raise; end if;
end $$;
do $$
declare v_id uuid;
begin
    v_id := request_promotion('43000000-0000-0000-0000-000000000001',
                              '43aaaaaa-0000-0000-0000-000000000001', 7);
    if (select status || ':' || price::int from promotions where id = v_id) <> 'requested:1000' then
        raise exception 'FAIL: a free shop''s 7-day spot is not requested at 1000 F';
    end if;
    begin
        perform request_promotion('43000000-0000-0000-0000-000000000001',
                                  '43aaaaaa-0000-0000-0000-000000000001', 30);
        raise exception 'FAIL: the same article was asked twice';
    exception when others then
        if sqlerrm not like 'Cet emplacement%' then raise; end if;
    end;
    raise notice 'PASS: employee refused, bare article refused, duplicate refused';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: paid, approved, then first in À la une; a refusal shows nothing ---'
begin;
update products set featured_until = now() + interval '3 days'
 where id = '43aaaaaa-0000-0000-0000-000000000003';
set local role authenticated;
set local "request.jwt.claim.sub" = '43434343-0000-0000-0000-000000000001';
create temp table t_spot on commit drop as
select request_promotion('43000000-0000-0000-0000-000000000001',
                         '43aaaaaa-0000-0000-0000-000000000001', 7) as id;
do $$ begin
    if exists (select 1 from storefront_featured() where name = 'Pagne') then
        raise exception 'FAIL: an unpaid spot is on the street';
    end if;
    begin
        perform decide_promotion((select id from t_spot), true);
        raise exception 'FAIL: the owner approved their own spot';
    exception when others then
        if sqlerrm not like 'Seule la plateforme%' then raise; end if;
    end;
end $$;
select claim_promotion_paid((select id from t_spot), 'Wave 77 00 00 00');
set local "request.jwt.claim.sub" = '43434343-0000-0000-0000-000000000004';
do $$ begin
    if (select status from platform_promotions() where id = (select id from t_spot)) <> 'paid_claimed' then
        raise exception 'FAIL: the console does not see the paid claim';
    end if;
end $$;
select decide_promotion((select id from t_spot), true);
set local role anon;
do $$ begin
    if (select name from storefront_featured() limit 1) <> 'Pagne' then
        raise exception 'FAIL: the paid spot is not first in À la une';
    end if;
    if not exists (select 1 from storefront_featured() where name = 'Bissap') then
        raise exception 'FAIL: the hand-set article fell out of À la une';
    end if;
    raise notice 'PASS: paid + approved → first in À la une, hand-set kept';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: a full strip queues the next spot behind the earliest end ---'
begin;
-- Eight running spots, ending on days 1..8.
insert into promotions (org_id, product_id, kind, days, status, starts_at, ends_at)
select '43000000-0000-0000-0000-000000000002', '43aaaaaa-0000-0000-0000-000000000003',
       'article', 7, 'approved', now() - interval '1 day', now() + make_interval(days => g)
from generate_series(1, 8) g;
set local role authenticated;
set local "request.jwt.claim.sub" = '43434343-0000-0000-0000-000000000001';
create temp table t_q on commit drop as
select request_promotion('43000000-0000-0000-0000-000000000001',
                         '43aaaaaa-0000-0000-0000-000000000001', 7) as id;
set local "request.jwt.claim.sub" = '43434343-0000-0000-0000-000000000004';
select decide_promotion((select id from t_q), true);
do $$
declare v promotions%rowtype;
begin
    select * into v from promotions where id = (select id from t_q);
    if abs(extract(epoch from v.starts_at - (now() + interval '1 day'))) > 5 then
        raise exception 'FAIL: the queued spot starts at %, not when the first ends', v.starts_at;
    end if;
    if v.ends_at - v.starts_at <> interval '7 days' then
        raise exception 'FAIL: the queued spot lost days';
    end if;
    raise notice 'PASS: ninth spot starts when the first running one ends, keeps its 7 days';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: Kaj Pro''s monthly spot is free and immediate, once ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '43434343-0000-0000-0000-000000000001';
do $$
declare v promotions%rowtype;
begin
    select * into v from promotions
     where id = request_promotion('43000000-0000-0000-0000-000000000002',
                                  '43aaaaaa-0000-0000-0000-000000000003', 7);
    if not v.free or v.status <> 'approved' or v.price <> 0 or v.starts_at > now() then
        raise exception 'FAIL: Pro''s spot is % / % / % F', v.free, v.status, v.price;
    end if;
end $$;
reset role;
update promotions set status = 'cancelled' where org_id = :pro;  -- free the article
set local role authenticated;
do $$ begin
    if (select free from promotions
         where id = request_promotion('43000000-0000-0000-0000-000000000002',
                                      '43aaaaaa-0000-0000-0000-000000000003', 7)) then
        raise exception 'FAIL: a second free spot in one month';
    end if;
    raise notice 'PASS: one free 7-day spot a month for Pro';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: a shop spot lights the shop; the report counts its days ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '43434343-0000-0000-0000-000000000001';
create temp table t_s on commit drop as
select request_promotion('43000000-0000-0000-0000-000000000001', null, 30) as id;
do $$ begin
    if (select price from promotions where id = (select id from t_s)) <> 8000 then
        raise exception 'FAIL: a 30-day shop spot is not 8000 F';
    end if;
end $$;
set local "request.jwt.claim.sub" = '43434343-0000-0000-0000-000000000004';
select decide_promotion((select id from t_s), true);
reset role;
insert into storefront_visits (day, org_id, product_id, seen, opened) values
    (current_date - 3, '43000000-0000-0000-0000-000000000001', null, 50, 50),
    (current_date,     '43000000-0000-0000-0000-000000000001', null, 0, 12);
set local role anon;
do $$ begin
    if not exists (select 1 from storefront_spotlights() where slug = 'vue-43') then
        raise exception 'FAIL: the shop spot is not in the spotlights';
    end if;
end $$;
set local role authenticated;
set local "request.jwt.claim.sub" = '43434343-0000-0000-0000-000000000001';
do $$ begin
    if (select opened from my_promotions('43000000-0000-0000-0000-000000000001')) <> 12 then
        raise exception 'FAIL: the report counted days before the spot (% opened)',
            (select opened from my_promotions('43000000-0000-0000-0000-000000000001'));
    end if;
    raise notice 'PASS: shop spotlighted; report counts only the spot''s own days';
end $$;
set local "request.jwt.claim.sub" = '43434343-0000-0000-0000-000000000003';
do $$ begin
    if exists (select 1 from promotions) or exists (select 1 from my_promotions('43000000-0000-0000-0000-000000000001')) then
        raise exception 'FAIL: a stranger reads the shop''s promotions';
    end if;
    if exists (select 1 from platform_promotions()) then
        raise exception 'FAIL: a stranger reads the console''s queue';
    end if;
    raise notice 'PASS: strangers see no promotions';
end $$;
rollback;

\echo ''
\echo 'test_spots: all passed'
