-- ============================================================
-- test_batch161.sql — 161: ticket sales, the payment outside the app.
--
-- The claims:
--   1. who may sell: Pro once the switch is on; before, a business one of
--      Marakaj's admins belongs to; a free business is refused the Pro way;
--   2. the buyer's request: places held, sold out refused, a reference,
--      the bell; the hold's end gives the places back;
--   3. the business validates: one ticket per seat, an income entry in its
--      books; refuses: the places back; another business cannot;
--   4. the door: a ticket valid once, then « used »; unknown to a stranger;
--      the offline list and its sync;
--   5. the buyer keeps the tickets in their account.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
\i database/migrations/161_events_tickets.sql
\i database/migrations/161_events_tickets.sql
-- The suites' blanket grant hides what 161 grants: back to it for these.
revoke insert, update, delete on event_ticket_requests, event_ticket_lines, event_tickets from authenticated;

begin;
update platform_settings set value = 'true' where key = 'events_public';
update platform_settings set value = 'false' where key = 'events_tickets';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('16116116-0000-0000-0000-000000000001', '+22616110001', 'awa161@example.com', '{"full_name": "Awa Pro"}', now()),
    ('16116116-0000-0000-0000-000000000002', '+22616110002', 'bob161@example.com', '{"full_name": "Bob Libre"}', now()),
    ('16116116-0000-0000-0000-000000000003', '+22616110003', 'fan161@example.com', '{"full_name": "Fan"}', now()),
    ('16116116-0000-0000-0000-000000000004', '+22616110004', 'mara161@example.com', '{"full_name": "Mara Admin"}', now());
insert into profiles (id, is_platform_admin) values ('16116116-0000-0000-0000-000000000004', true)
on conflict (id) do update set is_platform_admin = true;
insert into orgs (id, name, slug, profile, default_currency, plan) values
    ('16116116-1111-0000-0000-000000000001', 'Awa Concerts 161', 'awa-concerts-161', 'events', 'XOF', 'pro'),
    ('16116116-1111-0000-0000-000000000002', 'Bob Fêtes 161', 'bob-fetes-161', 'events', 'XOF', 'free'),
    ('16116116-1111-0000-0000-000000000003', 'Mara Essai 161', 'mara-essai-161', 'events', 'XOF', 'free');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('16116116-0000-0000-0000-000000000001', '16116116-1111-0000-0000-000000000001', 'owner', 'org', '16116116-1111-0000-0000-000000000001', 'full'),
    ('16116116-0000-0000-0000-000000000002', '16116116-1111-0000-0000-000000000002', 'owner', 'org', '16116116-1111-0000-0000-000000000002', 'full'),
    ('16116116-0000-0000-0000-000000000004', '16116116-1111-0000-0000-000000000003', 'owner', 'org', '16116116-1111-0000-0000-000000000003', 'full');
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, tz, published)
values
    ('16116116-2222-0000-0000-000000000001', '16116116-1111-0000-0000-000000000001', '16116116-0000-0000-0000-000000000001', 'gala', 'gala',
     'concert-fatim-161', 'aaaaaaaaaaaaaaaaaaaaaa61', 'bbbbbbbbbbbbbbbbbbbbbb61', 'Concert Fatim', now() + interval '10 days', 'Salle CENASA', '{}', 'Africa/Ouagadougou', true),
    ('16116116-2222-0000-0000-000000000002', '16116116-1111-0000-0000-000000000002', '16116116-0000-0000-0000-000000000002', 'gala', 'gala',
     'fete-bob-161', 'cccccccccccccccccccccc61', 'dddddddddddddddddddddd61', 'Fête Bob', now() + interval '10 days', null, '{}', 'Africa/Ouagadougou', true),
    ('16116116-2222-0000-0000-000000000003', '16116116-1111-0000-0000-000000000003', '16116116-0000-0000-0000-000000000004', 'gala', 'gala',
     'essai-mara-161', 'eeeeeeeeeeeeeeeeeeeeee61', 'ffffffffffffffffffffff61', 'Essai Mara', now() + interval '10 days', null, '{}', 'Africa/Ouagadougou', true);

create temp table t161 (k text primary key, v text);
grant all on t161 to anon, authenticated;

-- 1. who may sell
do $$
declare v_err text;
begin
    -- The switch off: the Pro business waits, the admin's own trial may.
    begin
        update events set tickets_on = true where id = '16116116-2222-0000-0000-000000000001';
        raise exception 'a Pro business sold before the switch';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Marakaj Pro : %', 'refused while the switch is off: ' || v_err;
    end;
    update events set tickets_on = true where id = '16116116-2222-0000-0000-000000000003';
    assert (select tickets_on from events where id = '16116116-2222-0000-0000-000000000003'), 'Mara''s own trial sells, free plan or not';
    -- The switch on: Pro sells, free does not.
    update platform_settings set value = 'true' where key = 'events_tickets';
    update events set tickets_on = true, pay_methods = '[{"kind": "orange", "number": "70 00 00 01", "name": "Awa K."}]',
           pay_whatsapp = '+22670000001', hold_hours = 72 where id = '16116116-2222-0000-0000-000000000001';
    begin
        update events set tickets_on = true where id = '16116116-2222-0000-0000-000000000002';
        raise exception 'a free business sold tickets';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Marakaj Pro : %', 'a free business is refused the Pro way: ' || v_err;
    end;
    insert into event_ticket_types (id, event_id, name, price, capacity, sort) values
        ('16116116-3333-0000-0000-000000000001', '16116116-2222-0000-0000-000000000001', 'Standard', 2000, 3, 1),
        ('16116116-3333-0000-0000-000000000002', '16116116-2222-0000-0000-000000000001', 'VIP', 5000, null, 2);
end $$;

-- 2. the buyer's request
do $$
declare j jsonb; o jsonb; v_err text;
begin
    set local role anon;
    o := event_ticket_offer('concert-fatim-161');
    assert (o ->> 'on')::boolean and (o ->> 'open')::boolean and jsonb_array_length(o -> 'types') = 2, 'the offer: ' || o::text;
    assert (o -> 'types' -> 0 ->> 'left')::int = 3 and o -> 'types' -> 1 -> 'left' = 'null'::jsonb, 'places left, no limit on VIP';
    assert o -> 'pay_methods' -> 0 ->> 'number' = '70 00 00 01', 'where to pay';
    assert event_ticket_offer('fete-bob-161') ->> 'on' = 'false', 'Bob sells nothing';
    j := event_ticket_request('concert-fatim-161', null, 'Tanti Rose', '+226 70 12 34 56',
                              '[{"type": "16116116-3333-0000-0000-000000000001", "qty": 2}, {"type": "16116116-3333-0000-0000-000000000002", "qty": 1}]');
    assert j ->> 'ref' ~ '^MK-[0-9A-F]{5}$' and (j ->> 'total')::numeric = 9000, 'a reference and the total: ' || j::text;
    insert into t161 values ('rose', j ->> 'id');
    assert (event_ticket_offer('concert-fatim-161') -> 'types' -> 0 ->> 'left')::int = 1, 'two Standard places held';
    begin
        perform event_ticket_request('concert-fatim-161', null, 'Oncle Sam', '70000002', '[{"type": "16116116-3333-0000-0000-000000000001", "qty": 2}]');
        raise exception 'sold beyond the places';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Plus assez de places en « Standard » : il en reste 1.%', 'sold out said plainly: ' || v_err;
    end;
    j := event_ticket_request('concert-fatim-161', null, 'Oncle Sam', '70000002', '[{"type": "16116116-3333-0000-0000-000000000001", "qty": 1}]', 'PP2611.0101');
    insert into t161 values ('sam', j ->> 'id');
    assert event_ticket_status((j ->> 'id')::uuid) ->> 'txn_ref' = 'PP2611.0101', 'the transaction number kept';
    assert event_ticket_status((j ->> 'id')::uuid) ->> 'status' = 'pending', 'pending';
    assert jsonb_array_length(event_ticket_status((j ->> 'id')::uuid) -> 'pay_methods') = 1, 'where to pay, while it waits';
    reset role;
    assert exists (select 1 from notifications where kind = 'ticket_request' and recipient_id = '16116116-0000-0000-0000-000000000001'
                    and params ->> 'ref' = j ->> 'ref'), 'the organiser hears of it';
    -- Sam's hold runs out: the place comes back.
    update event_ticket_requests set hold_until = now() - interval '1 minute' where id = (select v from t161 where k = 'sam')::uuid;
    set local role anon;
    assert event_ticket_status((select v from t161 where k = 'sam')::uuid) ->> 'status' = 'expired', 'expired once past its hold';
    assert (event_ticket_offer('concert-fatim-161') -> 'types' -> 0 ->> 'left')::int = 1, 'its place back on sale';
    reset role;
end $$;

-- 3. the business decides
do $$
declare j jsonb; v_err text; v_rose uuid := (select v from t161 where k = 'rose')::uuid;
begin
    -- Bob, another business, cannot; the street cannot.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '16116116-0000-0000-0000-000000000002', true);
    begin
        perform event_ticket_decide(v_rose, true);
        raise exception 'another business validated';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Vous ne pouvez pas valider%', v_err;
    end;
    reset role;
    assert not has_function_privilege('anon', 'event_ticket_decide(uuid, boolean, text, text)', 'execute'), 'the street cannot validate';
    -- Awa validates Rose: three tickets, the money in the books.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '16116116-0000-0000-0000-000000000001', true);
    j := event_ticket_decide(v_rose, true, null, 'orange');
    assert j ->> 'status' = 'paid' and jsonb_array_length(j -> 'tickets') = 3, 'one ticket per seat: ' || j::text;
    insert into t161 values ('ticket', j -> 'tickets' -> 0 ->> 'id');
    begin
        perform event_ticket_decide(v_rose, true);
        raise exception 'validated twice';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Cette demande est déjà traitée.%', v_err;
    end;
    reset role;
    assert (select entry_id from event_ticket_requests where id = v_rose) is not null, 'an income entry in the books';
    -- Sam, expired, refused: nothing more.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '16116116-0000-0000-0000-000000000001', true);
    j := event_ticket_decide((select v from t161 where k = 'sam')::uuid, false, 'Pas de paiement reçu');
    assert j ->> 'status' = 'refused', 'refused';
    reset role;
end $$;

-- 4. the door
do $$
declare j jsonb; v_t uuid := (select v from t161 where k = 'ticket')::uuid;
begin
    set local role anon;
    assert event_ticket_view('concert-fatim-161', v_t) ->> 'status' = 'valid', 'the QR opens the ticket for anyone holding it';
    reset role;
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '16116116-0000-0000-0000-000000000002', true);
    assert event_ticket_scan(v_t) ->> 'result' = 'unknown', 'a stranger''s scanner knows nothing';
    perform set_config('request.jwt.claim.sub', '16116116-0000-0000-0000-000000000001', true);
    j := event_ticket_scan(v_t);
    assert j ->> 'result' = 'valid' and j ->> 'holder' = 'Tanti Rose' and j ->> 'type' = 'Standard', 'valid once: ' || j::text;
    assert event_ticket_scan(v_t) ->> 'result' = 'used', 'then used';
    assert event_ticket_scan('00000000-0000-4000-8000-000000000000') ->> 'result' = 'unknown', 'an unknown code';
    j := event_tickets_door('16116116-2222-0000-0000-000000000001');
    assert jsonb_array_length(j) = 3, 'the offline list: ' || j::text;
    j := event_tickets_door_sync('16116116-2222-0000-0000-000000000001',
            jsonb_build_array(jsonb_build_object('id', (select id from event_tickets where status = 'valid' and event_id = '16116116-2222-0000-0000-000000000001' limit 1), 'at', now()),
                              jsonb_build_object('id', v_t, 'at', now())));
    assert (j -> 0 ->> 'applied')::boolean and not (j -> 1 ->> 'applied')::boolean, 'scans synced, the used one reported: ' || j::text;
    reset role;
end $$;

-- 5. the buyer keeps them
do $$
declare j jsonb;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '16116116-0000-0000-0000-000000000003', true);
    assert event_ticket_claim((select v from t161 where k = 'rose')::uuid), 'kept in the account';
    j := my_event_tickets();
    assert jsonb_array_length(j) = 1 and j -> 0 ->> 'title' = 'Concert Fatim' and jsonb_array_length(j -> 0 -> 'tickets') = 3, 'the account''s tickets: ' || j::text;
    perform set_config('request.jwt.claim.sub', '16116116-0000-0000-0000-000000000002', true);
    assert not event_ticket_claim((select v from t161 where k = 'rose')::uuid), 'another account cannot take them';
    -- The app's question: its own admins alone hear the answer.
    assert not event_tickets_ready('16116116-1111-0000-0000-000000000001'), 'Bob cannot ask about Awa''s business';
    assert not event_tickets_ready('16116116-1111-0000-0000-000000000002'), 'Bob''s free business does not sell';
    perform set_config('request.jwt.claim.sub', '16116116-0000-0000-0000-000000000001', true);
    assert event_tickets_ready('16116116-1111-0000-0000-000000000001'), 'Awa''s Pro business sells';
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    assert not has_function_privilege('anon', 'event_tickets_allowed(uuid)', 'execute'), 'the street cannot ask who sells';
    raise notice 'PASS: 161 — ticket sales: Pro or Mara''s trial, places held and given back, one ticket per seat validated into the books, the door once, the offline list, the buyer''s account';
end $$;

rollback;
