-- ============================================================
-- test_console_today.sql — the console opens on today (072).
-- Phone block 44.
--
-- The claims: platform_today() counts what waits on the platform, what it
-- earned this month and what is unwell, and answers nobody but the
-- platform; send_platform_message() reaches the people who answer for a
-- business — one or every live one — and nobody else may send it.
-- ============================================================
\set ON_ERROR_STOP on

\set plat   '''44444444-0000-0000-0000-000000000001'''
\set owner  '''44444444-0000-0000-0000-000000000002'''
\set clerk  '''44444444-0000-0000-0000-000000000003'''
\set buyer  '''44444444-0000-0000-0000-000000000004'''
\set shop   '''44000000-0000-0000-0000-000000000001'''
\set jersey '''44000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:plat,  '+22644000001', '{"full_name": "Plateforme"}'),
    (:owner, '+22644000002', '{"full_name": "Propriétaire"}'),
    (:clerk, '+22644000003', '{"full_name": "Vendeuse"}'),
    (:buyer, '+22644000004', '{"full_name": "Cliente"}');
update profiles set is_platform_admin = true where id = :plat;
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, lat, lng) values
    (:shop,   'Boutique Aujourd''hui', 'auj-44',    'retail', 'XOF', true, 12.37, -1.52),
    (:jersey, 'Boutique Newark',       'newark-44', 'retail', 'XOF', true, 40.75, -74.19);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,   :owner, 'owner',    'org', :shop,   'full'),
    (:shop,   :clerk, 'employee', 'org', :shop,   'full'),
    (:jersey, :owner, 'owner',    'org', :jersey, 'full');
insert into products (org_id, name, sale_price, quantity, is_active) values
    (:shop, 'Savon', 450, 9, true);


\echo ''
\echo '--- TEST 1: today counts what waits, what came in, and what is unwell ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '44444444-0000-0000-0000-000000000001';
create temp table t0 on commit drop as select platform_today() as v;
reset role;
insert into org_applications (applicant_id, name, slug) values (:buyer, 'Demande', 'demande-44');
insert into couriers (user_id, phone) values (:buyer, '+22644000004')
    on conflict (user_id) do update set status = 'pending';
insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency, created_at, updated_at) values
    (:shop, :buyer, 'Awa', 'pending',   'pickup', 450, 'XOF', now() - interval '3 hours', now() - interval '3 hours'),
    (:shop, :buyer, 'Awa', 'delivered', 'pickup', 900, 'XOF', now(), now());
insert into promotions (org_id, kind, days, price, status, decided_at, starts_at, ends_at) values
    (:shop, 'shop', 7, 2500, 'approved', now(), now(), now() + interval '7 days');
set local role authenticated;
set local "request.jwt.claim.sub" = '44444444-0000-0000-0000-000000000001';
do $$
declare a jsonb := (select v from t0); b jsonb := platform_today();
begin
    if (b #>> '{todo,applications}')::int - (a #>> '{todo,applications}')::int <> 1 then
        raise exception 'FAIL: the application is not waiting';
    end if;
    if (b #>> '{todo,couriers}')::int - (a #>> '{todo,couriers}')::int <> 1 then
        raise exception 'FAIL: the courier is not waiting';
    end if;
    if (b #>> '{todo,orders_stuck}')::int - (a #>> '{todo,orders_stuck}')::int <> 1 then
        raise exception 'FAIL: the three-hour-old order is not stuck';
    end if;
    if (b #>> '{money,spots}')::numeric - (a #>> '{money,spots}')::numeric <> 2500 then
        raise exception 'FAIL: the spot sold is not in the month''s money';
    end if;
    if (b #>> '{money,shops_sold}')::numeric - (a #>> '{money,shops_sold}')::numeric <> 900 then
        raise exception 'FAIL: the delivered order is not in what the shops sold';
    end if;
    if (b #>> '{health,pins_far}')::int < 1 then
        raise exception 'FAIL: the Newark pin is not called far';
    end if;
    if (b #>> '{health,empty_windows}')::int < 1 then
        raise exception 'FAIL: the empty open window is not counted';
    end if;
    raise notice 'PASS: todo, money and health move with the platform';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: today is the platform''s only ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '44444444-0000-0000-0000-000000000002';
do $$ begin
    if platform_today() is not null then
        raise exception 'FAIL: an owner reads the platform''s day';
    end if;
    raise notice 'PASS: an owner gets nothing';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: a message reaches the admins of one business, or all ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '44444444-0000-0000-0000-000000000002';
do $$ begin
    perform send_platform_message(null, 'Bonjour');
    raise exception 'FAIL: an owner wrote to every business';
exception when others then
    if sqlerrm not like 'Seule la plateforme%' then raise; end if;
end $$;
set local "request.jwt.claim.sub" = '44444444-0000-0000-0000-000000000001';
do $$
declare n int;
begin
    n := send_platform_message('44000000-0000-0000-0000-000000000001', 'Ajoutez une photo à vos articles.');
    if n <> 1 then
        raise exception 'FAIL: one business reached % people (only its owner answers for it)', n;
    end if;
    if exists (select 1 from notifications
                where recipient_id = '44444444-0000-0000-0000-000000000003'
                  and kind = 'platform_message') then
        raise exception 'FAIL: the employee was written to';
    end if;
    n := send_platform_message(null, 'Nouveau : mettez un article en avant.');
    if n < 2 then
        raise exception 'FAIL: "every business" reached only %', n;
    end if;
    begin
        perform send_platform_message(null, '   ');
        raise exception 'FAIL: an empty message was sent';
    exception when others then
        if sqlerrm not like 'Le message est vide%' then raise; end if;
    end;
    raise notice 'PASS: one business, every business, never the empty message';
end $$;
rollback;

\echo ''
\echo 'test_console_today: all passed'
