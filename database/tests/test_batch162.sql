-- ============================================================
-- test_batch162.sql — 162: public events on the street.
--
-- The claims:
--   1. only a published, listed, dated event not yet over is on the street;
--      unpublishing takes it off; a suspended business's leaves;
--   2. what the street shows: the poster, the date, the business, and the
--      lowest price when it sells (a Pro business);
--   3. one event's page: its ticket offer; an unlisted card is nothing;
--   4. the street reaches the two functions and nothing else; the
--      business's own admins alone list a card.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
\i database/migrations/162_events_listed.sql
\i database/migrations/162_events_listed.sql

begin;
update platform_settings set value = 'true' where key = 'events_tickets';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('16216216-0000-0000-0000-000000000001', '+22616210001', 'awa162@example.com', '{"full_name": "Awa Pro"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan) values
    ('16216216-1111-0000-0000-000000000001', 'Awa Concerts 162', 'awa-concerts-162', 'events', 'XOF', 'pro'),
    ('16216216-1111-0000-0000-000000000002', 'Bob Fêtes 162', 'bob-fetes-162', 'events', 'XOF', 'free');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('16216216-0000-0000-0000-000000000001', '16216216-1111-0000-0000-000000000001', 'owner', 'org', '16216216-1111-0000-0000-000000000001', 'full');
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, tz, published, listed)
values
    -- Awa's concert: published, listed, sells.
    ('16216216-2222-0000-0000-000000000001', '16216216-1111-0000-0000-000000000001', '16216216-0000-0000-0000-000000000001', 'gala', 'gala',
     'concert-162', 'aaaaaaaaaaaaaaaaaaaaaa62', 'bbbbbbbbbbbbbbbbbbbbbb62', 'Concert 162', now() + interval '3 days', 'CENASA',
     '{"p:hero": {"key": "org/x/hero.jpg"}}', 'Africa/Ouagadougou', true, true),
    -- Bob's party: free, listed.
    ('16216216-2222-0000-0000-000000000002', '16216216-1111-0000-0000-000000000002', '16216216-0000-0000-0000-000000000001', 'gala', 'gala',
     'fete-162', 'cccccccccccccccccccccc62', 'dddddddddddddddddddddd62', 'Fête 162', now() + interval '1 day', null,
     '{}', 'Africa/Ouagadougou', true, true),
    -- A wedding kept private.
    ('16216216-2222-0000-0000-000000000003', '16216216-1111-0000-0000-000000000002', '16216216-0000-0000-0000-000000000001', 'mariage', 'gala',
     'mariage-162', 'eeeeeeeeeeeeeeeeeeeeee62', 'ffffffffffffffffffffff62', 'Mariage 162', now() + interval '2 days', null,
     '{}', 'Africa/Ouagadougou', true, false),
    -- Last week's: over.
    ('16216216-2222-0000-0000-000000000004', '16216216-1111-0000-0000-000000000002', '16216216-0000-0000-0000-000000000001', 'gala', 'gala',
     'passe-162', 'gggggggggggggggggggggg62', 'hhhhhhhhhhhhhhhhhhhhhh62', 'Passé 162', now() - interval '7 days', null,
     '{}', 'Africa/Ouagadougou', true, true),
    -- Listed but a draft: the guard keeps it off.
    ('16216216-2222-0000-0000-000000000005', '16216216-1111-0000-0000-000000000002', '16216216-0000-0000-0000-000000000001', 'gala', 'gala',
     'brouillon-162', 'iiiiiiiiiiiiiiiiiiiiii62', 'jjjjjjjjjjjjjjjjjjjjjj62', 'Brouillon 162', now() + interval '2 days', null,
     '{}', 'Africa/Ouagadougou', false, true);
update events set tickets_on = true, pay_methods = '[{"kind": "orange", "number": "70000001"}]', pay_whatsapp = '+22670000001'
 where id = '16216216-2222-0000-0000-000000000001';
insert into event_ticket_types (event_id, name, price, capacity, sort) values
    ('16216216-2222-0000-0000-000000000001', 'Standard', 2000, 100, 1),
    ('16216216-2222-0000-0000-000000000001', 'VIP', 10000, 10, 2);

do $$
declare j jsonb; mine jsonb;
begin
    assert not (select listed from events where id = '16216216-2222-0000-0000-000000000005'), 'a draft is never listed';
    set local role anon;
    j := street_events();
    select jsonb_agg(x) into mine from jsonb_array_elements(j) x where x ->> 'slug' like '%-162';
    assert jsonb_array_length(mine) = 2, 'two on the street: ' || mine::text;
    assert mine -> 0 ->> 'slug' = 'fete-162' and mine -> 1 ->> 'slug' = 'concert-162', 'soonest first';
    assert mine -> 1 ->> 'poster' = 'org/x/hero.jpg' and mine -> 1 ->> 'org_name' = 'Awa Concerts 162', 'the poster and the business';
    assert (mine -> 1 ->> 'tickets')::boolean and (mine -> 1 ->> 'from_price')::numeric = 2000, 'sells, from 2 000';
    assert not (mine -> 0 ->> 'tickets')::boolean and mine -> 0 -> 'from_price' = 'null'::jsonb, 'free entry';
    assert mine -> 1 ->> 'date_fr' is not null, 'the date in French';
    j := street_event('concert-162');
    assert jsonb_array_length(j -> 'offer' -> 'types') = 2 and j ->> 'pay_whatsapp' = '+22670000001', 'its page: ' || j::text;
    assert street_event('mariage-162') is null, 'a private card is nothing on the street';
    assert street_event('passe-162') is null, 'nor one already over';
    reset role;

    -- Unpublished: off the street, and off for good until listed again.
    update events set published = false where id = '16216216-2222-0000-0000-000000000002';
    update events set published = true where id = '16216216-2222-0000-0000-000000000002';
    assert not (select listed from events where id = '16216216-2222-0000-0000-000000000002'), 'unpublishing unlists';
    -- A suspended business leaves.
    update orgs set suspended_at = now() where id = '16216216-1111-0000-0000-000000000001';
    assert not exists (select 1 from jsonb_array_elements(street_events()) x where x ->> 'slug' like '%-162'), 'nobody left: ' || street_events()::text;

    assert has_function_privilege('anon', 'street_events()', 'execute') and has_function_privilege('anon', 'street_event(text)', 'execute'), 'the street asks';
    assert not has_function_privilege('anon', 'street_event_row(events)', 'execute'), 'not the inner piece';
    assert has_column_privilege('authenticated', 'events', 'listed', 'update'), 'the organiser lists (RLS: its admins)';
    raise notice 'PASS: 162 — public events on the street: published, listed, dated, not over; poster, date, from what price; one event''s page with its offer';
end $$;

rollback;
