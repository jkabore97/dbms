-- ============================================================
-- test_batch160.sql — 160: three classic cards after the owner's pictures.
-- Installed twice, the same: the three are designs a card may take,
-- classic, free, for a wedding; a business makes its card with one.
-- ============================================================
\set ON_ERROR_STOP on
do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to authenticated;
grant usage on schema auth to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
\i database/migrations/160_events_three_cards.sql
\i database/migrations/160_events_three_cards.sql

begin;
update platform_settings set value = 'true' where key = 'events_public';
insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('16016016-0000-0000-0000-000000000001', '+22616010001', 'awa160@example.com', '{"full_name": "Awa Planner"}', now());
insert into orgs (id, name, slug, profile, default_currency) values
    ('16016016-1111-0000-0000-000000000001', 'Awa Événements 160', 'awa-evenements-160', 'events', 'XOF');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('16016016-0000-0000-0000-000000000001', '16016016-1111-0000-0000-000000000001', 'owner', 'org', '16016016-1111-0000-0000-000000000001', 'full');
do $$
declare e events; k text;
begin
    assert (select count(*) from event_templates where key in ('cimbrone', 'bouquet', 'rivage')
              and family = 'classique' and not premium and kinds = array['mariage']) = 3, 'the three designs, classic, free, for a wedding';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '16016016-0000-0000-0000-000000000001', true);
    foreach k in array array['cimbrone', 'bouquet', 'rivage'] loop
        e := event_create('16016016-1111-0000-0000-000000000001', 'Ava & Marc', 'mariage', k, '2027-09-20 15:00+00', 'Ravello', '+00:00');
        assert e.card = k, 'a free business makes its card with ' || k;
    end loop;
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    raise notice 'PASS: 160 — Cimbrone, Bouquet and Rivage are classic designs any business may take';
end $$;
rollback;
