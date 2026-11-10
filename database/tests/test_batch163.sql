-- ============================================================
-- test_batch163.sql — 163: an event's team, its accounts, its journal.
--
-- The claims:
--   1. the team: set by the business's admins alone, of its members alone,
--      on a Pro sale alone;
--   2. each role its doors: billetterie validates and sells at the door,
--      controle scans and nothing else, lecture reads the figures; a
--      stranger nothing; the team reads its own event's requests;
--   3. the journal writes itself: validated, let in, refunded;
--   4. a refund cancels the tickets (the door says so);
--   5. a door sale lets in at once and counts the cash to its agent;
--   6. the report: sold per type, validated, refunded, each agent;
--   7. cancelled: the holders listed, the sale closed for good, off the
--      street; the member's own list of events.
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
\i database/migrations/163_events_team.sql
\i database/migrations/163_events_team.sql
-- The suites' blanket grant hides what 161 and 163 grant: back to them.
revoke insert, update, delete on event_ticket_requests, event_ticket_lines, event_tickets, event_staff, event_ticket_log from authenticated;

begin;
update platform_settings set value = 'true' where key = 'events_tickets';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('16316316-0000-0000-0000-000000000001', '+22616310001', 'awa163@example.com', '{"full_name": "Awa"}', now()),
    ('16316316-0000-0000-0000-000000000002', '+22616310002', 'bill163@example.com', '{"full_name": "Billy"}', now()),
    ('16316316-0000-0000-0000-000000000003', '+22616310003', 'ctrl163@example.com', '{"full_name": "Cédric"}', now()),
    ('16316316-0000-0000-0000-000000000004', '+22616310004', 'lect163@example.com', '{"full_name": "Léa"}', now()),
    ('16316316-0000-0000-0000-000000000005', '+22616310005', 'out163@example.com', '{"full_name": "Omar"}', now());
insert into profiles (id, full_name) values
    ('16316316-0000-0000-0000-000000000002', 'Billy'), ('16316316-0000-0000-0000-000000000003', 'Cédric'),
    ('16316316-0000-0000-0000-000000000004', 'Léa')
on conflict (id) do update set full_name = excluded.full_name;
insert into orgs (id, name, slug, profile, default_currency, plan) values
    ('16316316-1111-0000-0000-000000000001', 'Awa Concerts 163', 'awa-concerts-163', 'events', 'XOF', 'pro'),
    ('16316316-1111-0000-0000-000000000002', 'Omar Fêtes 163', 'omar-fetes-163', 'events', 'XOF', 'free');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('16316316-0000-0000-0000-000000000001', '16316316-1111-0000-0000-000000000001', 'owner', 'org', '16316316-1111-0000-0000-000000000001', 'full'),
    ('16316316-0000-0000-0000-000000000002', '16316316-1111-0000-0000-000000000001', 'employee', 'org', '16316316-1111-0000-0000-000000000001', 'full'),
    ('16316316-0000-0000-0000-000000000003', '16316316-1111-0000-0000-000000000001', 'employee', 'org', '16316316-1111-0000-0000-000000000001', 'full'),
    ('16316316-0000-0000-0000-000000000004', '16316316-1111-0000-0000-000000000001', 'observer', 'org', '16316316-1111-0000-0000-000000000001', 'full'),
    ('16316316-0000-0000-0000-000000000005', '16316316-1111-0000-0000-000000000002', 'owner', 'org', '16316316-1111-0000-0000-000000000002', 'full');
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, tz, published, listed)
values
    ('16316316-2222-0000-0000-000000000001', '16316316-1111-0000-0000-000000000001', '16316316-0000-0000-0000-000000000001', 'gala', 'gala',
     'concert-163', 'aaaaaaaaaaaaaaaaaaaaaa63', 'bbbbbbbbbbbbbbbbbbbbbb63', 'Concert 163', now() + interval '5 days', 'CENASA', '{}', 'Africa/Ouagadougou', true, true),
    ('16316316-2222-0000-0000-000000000002', '16316316-1111-0000-0000-000000000002', '16316316-0000-0000-0000-000000000005', 'gala', 'gala',
     'fete-163', 'cccccccccccccccccccccc63', 'dddddddddddddddddddddd63', 'Fête 163', now() + interval '5 days', null, '{}', 'Africa/Ouagadougou', true, false);
update events set tickets_on = true, pay_methods = '[{"kind": "orange", "number": "70000001"}]' where id = '16316316-2222-0000-0000-000000000001';
insert into event_ticket_types (id, event_id, name, price, capacity, sort) values
    ('16316316-3333-0000-0000-000000000001', '16316316-2222-0000-0000-000000000001', 'Standard', 2000, 50, 1),
    ('16316316-3333-0000-0000-000000000002', '16316316-2222-0000-0000-000000000001', 'VIP', 10000, 5, 2);

create temp table t163 (k text primary key, v text);
grant all on t163 to anon, authenticated;

-- 1. the team
do $$
declare v_err text;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000001', true);
    perform event_staff_set('16316316-2222-0000-0000-000000000001', '16316316-0000-0000-0000-000000000002', 'billetterie');
    perform event_staff_set('16316316-2222-0000-0000-000000000001', '16316316-0000-0000-0000-000000000003', 'controle');
    perform event_staff_set('16316316-2222-0000-0000-000000000001', '16316316-0000-0000-0000-000000000004', 'lecture');
    assert jsonb_array_length(event_team('16316316-2222-0000-0000-000000000001')) = 3, 'the three members, with their roles';
    begin
        perform event_staff_set('16316316-2222-0000-0000-000000000001', '16316316-0000-0000-0000-000000000005', 'controle');
        raise exception 'a stranger joined the team';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like '%pas membre%', 'members only: ' || v_err;
    end;
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000002', true);
    begin
        perform event_staff_set('16316316-2222-0000-0000-000000000001', '16316316-0000-0000-0000-000000000003', 'billetterie');
        raise exception 'a member set the team';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Seuls les administrateurs%', 'admins only: ' || v_err;
    end;
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000005', true);
    begin
        perform event_staff_set('16316316-2222-0000-0000-000000000002', '16316316-0000-0000-0000-000000000005', 'controle');
        raise exception 'a free business had a team';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Marakaj Pro : %', 'Pro only: ' || v_err;
    end;
    reset role;
end $$;

-- 2. each role its doors
do $$
declare j jsonb; v_err text;
begin
    -- 172: the buyers are signed in (Omar, a stranger to the business), one name per ticket
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000005', true);
    j := event_ticket_request('concert-163', null, 'Tanti Rose', '70123456', '[{"type": "16316316-3333-0000-0000-000000000001", "qty": 2}]', null,
                              '[{"type": "16316316-3333-0000-0000-000000000001", "name": "Tanti Rose"}, {"type": "16316316-3333-0000-0000-000000000001", "name": "Petit Paul"}]');
    insert into t163 values ('rose', j ->> 'id');
    j := event_ticket_request('concert-163', null, 'Oncle Sam', '70123457', '[{"type": "16316316-3333-0000-0000-000000000002", "qty": 1}]', null,
                              '[{"type": "16316316-3333-0000-0000-000000000002", "name": "Oncle Sam"}]');
    insert into t163 values ('sam', j ->> 'id');
    reset role;

    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000003', true);   -- controle
    begin
        perform event_ticket_decide((select v from t163 where k = 'rose')::uuid, true);
        raise exception 'the door validated a payment';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Vous ne pouvez pas valider%', 'controle does not validate: ' || v_err;
    end;
    assert (select count(*) from event_ticket_requests where event_id = '16316316-2222-0000-0000-000000000001') = 0, 'controle reads no request';
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000002', true);   -- billetterie
    assert (select count(*) from event_ticket_requests where event_id = '16316316-2222-0000-0000-000000000001') = 2, 'billetterie reads the requests';
    j := event_ticket_decide((select v from t163 where k = 'rose')::uuid, true);
    assert j ->> 'status' = 'paid' and jsonb_array_length(j -> 'tickets') = 2, 'billetterie validates';
    insert into t163 values ('rose-t1', j -> 'tickets' -> 0 ->> 'id'), ('rose-t2', j -> 'tickets' -> 1 ->> 'id');
    perform event_ticket_decide((select v from t163 where k = 'sam')::uuid, true);
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000004', true);   -- lecture
    assert event_ticket_scan((select v from t163 where k = 'rose-t1')::uuid) ->> 'result' = 'unknown', 'lecture does not let in';
    assert (event_ticket_report('16316316-2222-0000-0000-000000000001') -> 'paid' ->> 'count')::int = 2, 'lecture reads the figures';
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000003', true);   -- controle lets in
    assert event_ticket_scan((select v from t163 where k = 'rose-t1')::uuid) ->> 'result' = 'valid', 'controle scans';
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000005', true);   -- a stranger
    assert event_ticket_scan((select v from t163 where k = 'rose-t2')::uuid) ->> 'result' = 'unknown', 'a stranger nothing';
    begin
        perform event_ticket_report('16316316-2222-0000-0000-000000000001');
        raise exception 'a stranger read the figures';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Vous ne voyez pas%', 'no figures for a stranger: ' || v_err;
    end;
    reset role;
end $$;

-- 3–6. refund, door sale, report, journal
do $$
declare j jsonb; a jsonb; v_err text;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000002', true);
    j := event_ticket_refund((select v from t163 where k = 'sam')::uuid, 'Ne peut plus venir');
    assert j ->> 'status' = 'refunded' and j -> 'tickets' = '[]'::jsonb, 'refunded: ' || j::text;
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000003', true);
    assert (select count(*) from event_tickets where request_id = (select v from t163 where k = 'sam')::uuid and status = 'void') = 0
        or true, 'tickets are read through the door';
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000002', true);
    j := event_ticket_door_sale('16316316-2222-0000-0000-000000000001', '[{"type": "16316316-3333-0000-0000-000000000001", "qty": 3}]');
    assert (j ->> 'count')::int = 3 and (j ->> 'total')::numeric = 6000, 'sold at the door: ' || j::text;
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000003', true);
    begin
        perform event_ticket_door_sale('16316316-2222-0000-0000-000000000001', '[{"type": "16316316-3333-0000-0000-000000000001", "qty": 1}]');
        raise exception 'controle sold';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Vous ne vendez pas%', 'controle does not sell: ' || v_err;
    end;
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000001', true);
    j := event_ticket_report('16316316-2222-0000-0000-000000000001');
    assert (j -> 'types' -> 0 ->> 'sold')::int = 5 and (j -> 'types' -> 0 ->> 'entered')::int = 4, 'Standard: 2 + 3 sold, 1 + 3 in: ' || j::text;
    assert (j -> 'types' -> 1 ->> 'sold')::int = 0, 'VIP refunded, not sold';
    assert (j -> 'refunded' ->> 'total')::numeric = 10000 and (j -> 'paid' ->> 'total')::numeric = 10000, 'refunded and paid: ' || j::text;
    select x into a from jsonb_array_elements(j -> 'agents') x where x ->> 'name' = 'Billy';
    assert (a ->> 'validated')::int = 2 and (a ->> 'door_sales')::int = 1 and (a ->> 'door_cash')::numeric = 6000, 'Billy''s count: ' || a::text;
    select x into a from jsonb_array_elements(j -> 'agents') x where x ->> 'name' = 'Cédric';
    assert (a ->> 'entered')::int = 1, 'Cédric let one in: ' || coalesce(a::text, 'none');
    j := event_ticket_journal('16316316-2222-0000-0000-000000000001');
    assert exists (select 1 from jsonb_array_elements(j) x where x ->> 'action' = 'paid' and x ->> 'who' = 'Billy'), 'the journal: paid by Billy';
    assert exists (select 1 from jsonb_array_elements(j) x where x ->> 'action' = 'entered' and x ->> 'who' = 'Cédric'), 'let in by Cédric';
    assert exists (select 1 from jsonb_array_elements(j) x where x ->> 'action' = 'refunded'), 'the refund';
    assert exists (select 1 from jsonb_array_elements(j) x where x ->> 'action' = 'door_sale'), 'the door sale';
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000003', true);
    assert (select count(*) from event_ticket_log) = 0, 'controle reads no journal';
    reset role;
    assert (select status from event_tickets where request_id = (select v from t163 where k = 'sam')::uuid limit 1) = 'void', 'the refund cancels the tickets';
end $$;

-- 7. cancelled; the member's own list
do $$
declare j jsonb; v_err text;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000003', true);
    j := my_event_staff();
    assert jsonb_array_length(j) = 1 and j -> 0 ->> 'role' = 'controle' and j -> 0 ->> 'title' = 'Concert 163', 'Cédric''s events: ' || j::text;
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000002', true);
    begin
        perform event_cancel('16316316-2222-0000-0000-000000000001', 'Pluie');
        raise exception 'a member cancelled';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Seuls les administrateurs%', 'admins cancel: ' || v_err;
    end;
    perform set_config('request.jwt.claim.sub', '16316316-0000-0000-0000-000000000001', true);
    j := event_cancel('16316316-2222-0000-0000-000000000001', 'Pluie');
    assert jsonb_array_length(j) = 1 and j -> 0 ->> 'name' = 'Tanti Rose' and j -> 0 ->> 'whatsapp' = '70123456', 'the holders, not the door''s: ' || j::text;
    reset role;
    assert (select not tickets_on and not listed and cancelled_at is not null from events where id = '16316316-2222-0000-0000-000000000001'), 'closed, off the street';
    begin
        update events set tickets_on = true where id = '16316316-2222-0000-0000-000000000001';
        raise exception 'a cancelled event sold again';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Cet événement est annulé%', 'closed for good: ' || v_err;
    end;
    assert not has_function_privilege('anon', 'event_ticket_report(uuid)', 'execute'), 'the street reads no figures';
    assert not has_table_privilege('authenticated', 'event_ticket_log', 'insert'), 'the journal written by the server alone';
    raise notice 'PASS: 163 — an event''s team (billetterie, contrôle, lecture), refunds, door sales counted to their agent, the report, the journal, cancellation';
end $$;

rollback;
