-- ============================================================
-- test_cash_only.sql — cash for now, Wave when Mara allows it (090).
-- Phone block 60.
--
-- The claims: a vitrine order paid by Wave is refused, and the vitrine
-- does not show the Wave number, until a platform admin allows Wave for
-- that business; the owner cannot allow it themselves; a cash order goes
-- through; feature_states() carries the tick.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''60606060-0000-0000-0000-000000000001'''
\set buyer '''60606060-0000-0000-0000-000000000002'''
\set admin '''60606060-0000-0000-0000-000000000003'''
\set shop  '''60000000-0000-0000-0000-000000000001'''

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
grant execute on all functions in schema public to authenticated;
\i database/migrations/090_cash_only.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22660000001', '{"full_name": "Awa"}'),
    (:buyer, '+22660000002', '{"full_name": "Client"}'),
    (:admin, '+22660000003', '{"full_name": "Mara"}');
update profiles set is_platform_admin = true where id = :admin;
insert into orgs (id, name, slug, profile, default_currency, progress_since,
                  storefront_enabled, wave_merchant) values
    (:shop, 'Boutique 60', 'boutique-60', 'retail', 'XOF', null, true, 'M-60');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop, :owner, 'owner', 'org', :shop, 'full');
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
values (:shop, 'Riz', 1000, 10, true, true);

\echo ''
\echo '--- TEST 1: Wave refused, the number kept back, cash goes through ---'
do $$ begin
    if (select wave_merchant from storefront('boutique-60')) is not null then
        raise exception 'FAIL: the vitrine shows the Wave number before Mara allows it';
    end if;
    begin
        insert into orders (org_id, customer_id, customer_name, status, fulfilment,
                            total, currency, payment_method)
        values ('60000000-0000-0000-0000-000000000001', '60606060-0000-0000-0000-000000000002',
                'Client', 'pending', 'pickup', 1000, 'XOF', 'wave');
        raise exception 'FAIL: a Wave order before Mara allows it';
    exception when others then
        if sqlerrm not like 'Paiement en espèces uniquement%' then raise; end if;
    end;
    insert into orders (org_id, customer_id, customer_name, status, fulfilment,
                        total, currency, payment_method)
    values ('60000000-0000-0000-0000-000000000001', '60606060-0000-0000-0000-000000000002',
            'Client', 'pending', 'pickup', 1000, 'XOF', 'cash');
    raise notice 'PASS: Wave refused and hidden, cash taken';
end $$;

\echo ''
\echo '--- TEST 2: only Mara allows it; then Wave is offered ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '60606060-0000-0000-0000-000000000001';
do $$ begin
    if (feature_states('60000000-0000-0000-0000-000000000001') ->> 'wave_allowed')::boolean then
        raise exception 'FAIL: the app is told Wave is allowed';
    end if;
    begin
        perform set_org_wave_allowed('60000000-0000-0000-0000-000000000001', true);
        raise exception 'FAIL: the owner allowed Wave';
    exception when others then
        if sqlerrm not like 'Seul Mara%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '60606060-0000-0000-0000-000000000003';
select set_org_wave_allowed('60000000-0000-0000-0000-000000000001', true);
commit;
do $$ begin
    if (select wave_merchant from storefront('boutique-60')) is distinct from 'M-60' then
        raise exception 'FAIL: the Wave number does not show once allowed';
    end if;
    insert into orders (org_id, customer_id, customer_name, status, fulfilment,
                        total, currency, payment_method)
    values ('60000000-0000-0000-0000-000000000001', '60606060-0000-0000-0000-000000000002',
            'Client', 'pending', 'pickup', 1000, 'XOF', 'wave');
    if has_function_privilege('anon', 'set_org_wave_allowed(uuid, boolean)', 'execute') then
        raise exception 'FAIL: anon can allow Wave';
    end if;
    raise notice 'PASS: refused to the owner, allowed by Mara, then offered';
end $$;

\echo ''
\echo 'test_cash_only: all passed'
