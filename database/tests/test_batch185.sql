-- ============================================================
-- test_batch185.sql — 185: a cancelled event says so.
--
-- The claims:
--   1. before: the card, the ticket and the invitation say « not
--      cancelled »;
--   2. event_cancel: the card says cancelled and its reason; the buyer's
--      ticket and the confirmed guest's invitation too;
--   3. the bells, the first time only: the buyer one (« Mes billets »),
--      the guest who bought nothing one (« Mes invitations »), the guest
--      who also bought only the buyer's; nobody else; under « Mes
--      réservations »;
--   4. cancelled again: no second bell; the tickets untouched (the refund
--      stays the organiser's);
--   5. only the business's admins cancel (as 163); the doors.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
\i database/migrations/185_event_cancelled_shown.sql
\i database/migrations/185_event_cancelled_shown.sql

begin;
update platform_settings set value = 'true' where key = 'events_public';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('18518518-0000-0000-0000-000000000001', '22618510001', 'awa185@example.com', '{"full_name": "Awa Organisatrice"}', now()),
    ('18518518-0000-0000-0000-000000000002', '22618510002', 'bob185@example.com', '{"full_name": "Bob Acheteur"}', now()),
    ('18518518-0000-0000-0000-000000000003', '22618510003', 'nora185@example.com', '{"full_name": "Nora Invitée"}', now()),
    ('18518518-0000-0000-0000-000000000004', '22618510004', 'ali185@example.com', '{"full_name": "Ali Les Deux"}', now()),
    ('18518518-0000-0000-0000-000000000005', '22618510005', 'zoe185@example.com', '{"full_name": "Zoé Ailleurs"}', now());
insert into profiles (id, full_name) values
    ('18518518-0000-0000-0000-000000000001', 'Awa'), ('18518518-0000-0000-0000-000000000002', 'Bob'),
    ('18518518-0000-0000-0000-000000000003', 'Nora'), ('18518518-0000-0000-0000-000000000004', 'Ali'),
    ('18518518-0000-0000-0000-000000000005', 'Zoé')
on conflict (id) do update set full_name = excluded.full_name;
insert into orgs (id, name, slug, profile, default_currency, plan, events_allowed) values
    ('18518518-1111-0000-0000-000000000001', 'Awa Fêtes 185', 'awa-fetes-185', 'events', 'XOF', 'pro', true);
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('18518518-0000-0000-0000-000000000001', '18518518-1111-0000-0000-000000000001', 'owner', 'org', '18518518-1111-0000-0000-000000000001', 'full');
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, tz, published, listed)
values
    ('18518518-2222-0000-0000-000000000001', '18518518-1111-0000-0000-000000000001', '18518518-0000-0000-0000-000000000001', 'gala', 'gala',
     'gala-185', 'aaaaaaaaaaaaaaaaaaaaa185', 'bbbbbbbbbbbbbbbbbbbbb185', 'Gala 185', now() + interval '10 days', 'Ouaga', '{}', 'Africa/Ouagadougou', true, true),
    ('18518518-2222-0000-0000-000000000002', '18518518-1111-0000-0000-000000000001', '18518518-0000-0000-0000-000000000001', 'gala', 'gala',
     'autre-185', 'ccccccccccccccccccccc185', 'ddddddddddddddddddddd185', 'Autre 185', now() + interval '10 days', 'Ouaga', '{}', 'Africa/Ouagadougou', true, false);
-- Bob and Ali bought (Ali also confirmed); a counter sale with no account; Zoé on another card
insert into event_ticket_requests (id, event_id, ref, buyer_name, buyer_whatsapp, buyer_user_id, status, total, hold_until) values
    ('18518518-4444-0000-0000-000000000001', '18518518-2222-0000-0000-000000000001', 'MK-18501', 'Bob', '+22618510002', '18518518-0000-0000-0000-000000000002', 'paid', 5000, now() + interval '1 day'),
    ('18518518-4444-0000-0000-000000000002', '18518518-2222-0000-0000-000000000001', 'MK-18502', 'Ali', '+22618510004', '18518518-0000-0000-0000-000000000004', 'pending', 5000, now() + interval '1 day'),
    ('18518518-4444-0000-0000-000000000003', '18518518-2222-0000-0000-000000000001', 'MK-18503', 'Guichet', 'guichet', null, 'paid', 5000, now() + interval '1 day'),
    ('18518518-4444-0000-0000-000000000004', '18518518-2222-0000-0000-000000000002', 'MK-18504', 'Zoé', '+22618510005', '18518518-0000-0000-0000-000000000005', 'paid', 5000, now() + interval '1 day');
insert into event_rsvps (event_id, user_id, name, people, answer) values
    ('18518518-2222-0000-0000-000000000001', '18518518-0000-0000-0000-000000000003', 'Nora', 2, 'oui'),
    ('18518518-2222-0000-0000-000000000001', '18518518-0000-0000-0000-000000000004', 'Ali', 1, 'oui');

create temp table t185 (k text primary key, v text);
grant all on t185 to anon, authenticated;

-- 1. before
do $$
declare j jsonb;
begin
    j := event_public('gala-185', null);
    assert (j ->> 'cancelled')::boolean = false and j -> 'cancel_reason' = 'null'::jsonb, 'the card, not cancelled: ' || j::text;
    j := event_ticket_status('18518518-4444-0000-0000-000000000001');
    assert (j ->> 'cancelled')::boolean = false, 'the ticket, not cancelled';
    raise notice 'PASS: before, the card and the ticket say « not cancelled »';
end $$;

-- 5a. only the admins
do $$
declare v_err text;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18518518-0000-0000-0000-000000000002', true);
    begin perform event_cancel('18518518-2222-0000-0000-000000000001', 'non'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Seuls les administrateurs annulent un événement.', 'a buyer cancels nothing: ' || v_err;
    reset role;
end $$;

-- 2 and 3. cancelled
do $$
declare j jsonb;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18518518-0000-0000-0000-000000000001', true);
    j := event_cancel('18518518-2222-0000-0000-000000000001', 'la salle est fermée');
    insert into t185 values ('holders', j::text);
    reset role;
end $$;
do $$
declare j jsonb; c jsonb;
begin
    assert jsonb_array_length((select v::jsonb from t185 where k = 'holders')) = 2, 'the holders to write to, as before: ' || (select v from t185 where k = 'holders');
    j := event_public('gala-185', null);
    assert (j ->> 'cancelled')::boolean and j ->> 'cancel_reason' = 'la salle est fermée', 'the card says it: ' || j::text;
    assert (event_public('autre-185', null) ->> 'cancelled')::boolean = false, 'another card untouched';
    j := event_ticket_status('18518518-4444-0000-0000-000000000001');
    assert (j ->> 'cancelled')::boolean and j ->> 'cancel_reason' = 'la salle est fermée', 'the ticket says it';
    perform set_config('request.jwt.claim.sub', '18518518-0000-0000-0000-000000000003', true);
    select x into c from jsonb_array_elements(my_event_invitations()) x where x ->> 'slug' = 'gala-185';
    assert (c ->> 'cancelled')::boolean and c ->> 'cancel_reason' = 'la salle est fermée', 'the invitation says it: ' || c::text;

    assert (select count(*) from notifications where kind = 'event_cancelled_buyer'
             and recipient_id = '18518518-0000-0000-0000-000000000002'
             and message = '« Gala 185 » est annulé (la salle est fermée).') = 1, 'Bob, the buyer';
    assert (select count(*) from notifications where kind = 'event_cancelled_buyer'
             and recipient_id = '18518518-0000-0000-0000-000000000004') = 1, 'Ali, a buyer (pending)';
    assert (select count(*) from notifications where kind = 'event_cancelled_guest'
             and recipient_id = '18518518-0000-0000-0000-000000000003'
             and params ->> 'slug' = 'gala-185') = 1, 'Nora, the guest';
    assert (select count(*) from notifications where kind = 'event_cancelled_guest'
             and recipient_id = '18518518-0000-0000-0000-000000000004') = 0, 'Ali once, as a buyer';
    assert (select count(*) from notifications where kind like 'event_cancelled%'
             and recipient_id in ('18518518-0000-0000-0000-000000000005', '18518518-0000-0000-0000-000000000001')) = 0, 'nobody else';
    assert notification_type_of('event_cancelled_buyer', '{}') = 'bookings'
       and notification_type_of('event_cancelled_guest', '{}') = 'bookings'
       and notification_type_of('event_presence', '{}') = 'shop_orders', 'under « Mes réservations », the others as before';
    raise notice 'PASS: cancelled — the card, the ticket and the invitation say it; the buyers and the guest hear it, once each';
end $$;

-- 4. again
do $$
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18518518-0000-0000-0000-000000000001', true);
    perform event_cancel('18518518-2222-0000-0000-000000000001', 'la salle est fermée');
    reset role;
    assert (select count(*) from notifications where kind like 'event_cancelled%' and params ->> 'slug' = 'gala-185') = 3, 'no second bell';
    assert (select status from event_ticket_requests where id = '18518518-4444-0000-0000-000000000001') = 'paid', 'the tickets as they were';
    raise notice 'PASS: cancelled again — no second bell; the tickets untouched';
end $$;

-- 5b. the doors
do $$ begin
    assert not has_function_privilege('anon', 'event_cancel(uuid, text)', 'execute')
       and not has_function_privilege('anon', 'my_event_invitations()', 'execute'), 'closed to anon';
    assert has_function_privilege('authenticated', 'event_cancel(uuid, text)', 'execute')
       and has_function_privilege('anon', 'event_public(text, text, text)', 'execute')
       and has_function_privilege('anon', 'event_ticket_status(uuid)', 'execute'), 'the street''s doors as before';
    raise notice 'PASS: the doors';
end $$;
rollback;
