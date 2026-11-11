-- ============================================================
-- test_batch176.sql — 176: the ticket screens speak the business's money.
--
-- The claims:
--   1. the business's admin reads its currency (USD, XOF);
--   2. a member of the event's team reads it too;
--   3. anyone else: null, nothing learnt; anon cannot call it.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
grant select on all tables in schema public to authenticated;
\i database/migrations/176_event_currency.sql
\i database/migrations/176_event_currency.sql

begin;
insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('17617617-0000-0000-0000-000000000001', '+12025550176', 'owner176@example.com', '{"full_name": "Owner"}', now()),
    ('17617617-0000-0000-0000-000000000002', '+22617610002', 'door176@example.com', '{"full_name": "Door"}', now()),
    ('17617617-0000-0000-0000-000000000003', '+22617610003', 'other176@example.com', '{"full_name": "Other"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan, events_allowed) values
    ('17617617-1111-0000-0000-000000000001', 'Fêtes 176', 'fetes-176', 'events', 'USD', 'pro', true),
    ('17617617-1111-0000-0000-000000000002', 'Fêtes CFA 176', 'fetes-cfa-176', 'events', 'XOF', 'pro', true);
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('17617617-0000-0000-0000-000000000001', '17617617-1111-0000-0000-000000000001', 'owner', 'org', '17617617-1111-0000-0000-000000000001', 'full'),
    ('17617617-0000-0000-0000-000000000001', '17617617-1111-0000-0000-000000000002', 'owner', 'org', '17617617-1111-0000-0000-000000000002', 'full'),
    ('17617617-0000-0000-0000-000000000002', '17617617-1111-0000-0000-000000000001', 'employee', 'org', '17617617-1111-0000-0000-000000000001', 'full');
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, tz, published) values
    ('17617617-2222-0000-0000-000000000001', '17617617-1111-0000-0000-000000000001', '17617617-0000-0000-0000-000000000001',
     'gala', 'gala', 'gala-176', 'aaaaaaaaaaaaaaaaaaaa1761', 'bbbbbbbbbbbbbbbbbbbb1761', 'Gala', now() + interval '5 days', 'Ouagadougou', 'Africa/Ouagadougou', true),
    ('17617617-2222-0000-0000-000000000002', '17617617-1111-0000-0000-000000000002', '17617617-0000-0000-0000-000000000001',
     'concert', 'gala', 'concert-176', 'aaaaaaaaaaaaaaaaaaaa1762', 'bbbbbbbbbbbbbbbbbbbb1762', 'Concert', now() + interval '6 days', 'Ouagadougou', 'Africa/Ouagadougou', true);
insert into event_staff (event_id, user_id, role) values
    ('17617617-2222-0000-0000-000000000001', '17617617-0000-0000-0000-000000000002', 'billetterie');

create temp table seen (who text, ev text, cur text) on commit drop;
grant insert on seen to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '17617617-0000-0000-0000-000000000001', true);
insert into seen values ('owner', 'usd', event_currency('17617617-2222-0000-0000-000000000001')),
                        ('owner', 'cfa', event_currency('17617617-2222-0000-0000-000000000002'));
select set_config('request.jwt.claim.sub', '17617617-0000-0000-0000-000000000002', true);
insert into seen values ('door', 'usd', event_currency('17617617-2222-0000-0000-000000000001')),
                        ('door', 'cfa', event_currency('17617617-2222-0000-0000-000000000002'));
select set_config('request.jwt.claim.sub', '17617617-0000-0000-0000-000000000003', true);
insert into seen values ('other', 'usd', event_currency('17617617-2222-0000-0000-000000000001'));
reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$ begin
    assert (select cur from seen where who = 'owner' and ev = 'usd') = 'USD', 'the admin reads USD';
    assert (select cur from seen where who = 'owner' and ev = 'cfa') = 'XOF', 'the CFA business: XOF';
    raise notice 'PASS: the business''s admin reads its currency (USD for one, XOF for the other)';
    assert (select cur from seen where who = 'door' and ev = 'usd') = 'USD', 'the event''s team reads it';
    assert (select cur from seen where who = 'door' and ev = 'cfa') is null, 'not on that event''s team: nothing';
    raise notice 'PASS: the event''s team reads it, for its own event only';
    assert (select cur from seen where who = 'other') is null, 'a stranger learns nothing';
    assert not has_function_privilege('anon', 'event_currency(uuid)', 'execute'), 'not anon''s';
    raise notice 'PASS: anyone else learns nothing; anon cannot ask';
end $$;

rollback;
