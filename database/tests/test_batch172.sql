-- ============================================================
-- test_batch172.sql — 172: tickets bought with an account, a name each.
--
-- The claims:
--   1. the street cannot ask for tickets: a buyer is signed in, and the
--      request is the account's from the start (my_event_tickets);
--   2. as many names as tickets of each kind, every name different —
--      too few, too many, the same twice, a name on the wrong kind: refused;
--   3. validated, each ticket carries its own person's name, in order.
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
\i database/migrations/172_tickets_named.sql
\i database/migrations/172_tickets_named.sql
revoke insert, update, delete on event_ticket_requests, event_ticket_lines, event_tickets from authenticated;

begin;
update platform_settings set value = 'true' where key = 'events_public';
update platform_settings set value = 'true' where key = 'events_tickets';
insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('17217217-0000-0000-0000-000000000001', '+22617210001', 'awa172@example.com', '{"full_name": "Awa"}', now()),
    ('17217217-0000-0000-0000-000000000002', '+22617210002', 'fan172@example.com', '{"full_name": "Wendtoin"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan) values
    ('17217217-1111-0000-0000-000000000001', 'Awa Concerts 172', 'awa-concerts-172', 'events', 'XOF', 'pro');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('17217217-0000-0000-0000-000000000001', '17217217-1111-0000-0000-000000000001', 'owner', 'org', '17217217-1111-0000-0000-000000000001', 'full');
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, tz, published)
values ('17217217-2222-0000-0000-000000000001', '17217217-1111-0000-0000-000000000001', '17217217-0000-0000-0000-000000000001', 'anniversaire', 'anniv',
        'anniv-172', 'aaaaaaaaaaaaaaaaaaaaa172', 'bbbbbbbbbbbbbbbbbbbbb172', 'Anniversaire 172', now() + interval '10 days', 'Ouagadougou', '{}', 'Africa/Ouagadougou', true);
update events set tickets_on = true, pay_methods = '[{"kind": "orange", "number": "70 00 00 01", "name": "Awa"}]', pay_whatsapp = '+22670000001'
 where id = '17217217-2222-0000-0000-000000000001';
insert into event_ticket_types (id, event_id, name, price, capacity, sort) values
    ('17217217-3333-0000-0000-000000000001', '17217217-2222-0000-0000-000000000001', 'VIP', 10000, null, 1),
    ('17217217-3333-0000-0000-000000000002', '17217217-2222-0000-0000-000000000001', 'Simple', 2000, null, 2);

create temp table t172 (k text primary key, v text);
grant all on t172 to anon, authenticated;

do $$
declare j jsonb; v_err text;
    L constant jsonb := '[{"type": "17217217-3333-0000-0000-000000000001", "qty": 2}, {"type": "17217217-3333-0000-0000-000000000002", "qty": 1}]';
    VV constant text := '17217217-3333-0000-0000-000000000001';
    S constant text := '17217217-3333-0000-0000-000000000002';
begin
    -- 1. the street: refused, and cannot even call it
    assert not has_function_privilege('anon', 'event_ticket_request(text, text, text, text, jsonb, text, jsonb)', 'execute'), 'the street cannot ask for tickets';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '', true);
    begin
        perform event_ticket_request('anniv-172', null, 'Wendtoin', '70123456', L, null,
            jsonb_build_array(jsonb_build_object('type', VV, 'name', 'A'), jsonb_build_object('type', VV, 'name', 'B'), jsonb_build_object('type', S, 'name', 'C')));
        raise exception 'bought with no account';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Connectez-vous à Marakaj%', 'no account: ' || v_err;
    end;
    perform set_config('request.jwt.claim.sub', '17217217-0000-0000-0000-000000000002', true);
    -- 2. the names
    foreach j in array array[
        null::jsonb,
        jsonb_build_array(jsonb_build_object('type', VV, 'name', 'Wendtoin'), jsonb_build_object('type', VV, 'name', 'Awa')),
        jsonb_build_array(jsonb_build_object('type', VV, 'name', 'Wendtoin'), jsonb_build_object('type', VV, 'name', 'wendtoin '), jsonb_build_object('type', S, 'name', 'Paul')),
        jsonb_build_array(jsonb_build_object('type', VV, 'name', 'Wendtoin'), jsonb_build_object('type', S, 'name', 'Awa'), jsonb_build_object('type', S, 'name', 'Paul')),
        jsonb_build_array(jsonb_build_object('type', VV, 'name', 'Wendtoin'), jsonb_build_object('type', VV, 'name', ''), jsonb_build_object('type', S, 'name', 'Paul'))
    ] loop
        begin
            perform event_ticket_request('anniv-172', null, 'Wendtoin', '70123456', L, null, j);
            raise exception 'names accepted: %', j;
        exception when others then
            get stacked diagnostics v_err = message_text;
            assert v_err ~ '^(Un nom par billet|Chaque billet est pour une personne différente|Le nom de chaque personne)', 'refused, said plainly: ' || v_err;
        end;
    end loop;
    j := event_ticket_request('anniv-172', null, 'Wendtoin Kabore', '70123456', L, null,
        jsonb_build_array(jsonb_build_object('type', VV, 'name', 'Wendtoin Kabore'), jsonb_build_object('type', VV, 'name', 'Awa'), jsonb_build_object('type', S, 'name', 'Petit Paul')));
    insert into t172 values ('req', j ->> 'id');
    assert jsonb_array_length(my_event_tickets()) = 1, 'the account''s from the start: on its home at once';
    -- 3. validated: a ticket per person
    perform set_config('request.jwt.claim.sub', '17217217-0000-0000-0000-000000000001', true);
    j := event_ticket_decide((select v from t172 where k = 'req')::uuid, true, null, 'orange');
    assert jsonb_array_length(j -> 'tickets') = 3, 'three tickets: ' || j::text;
    assert (select array_agg(t ->> 'holder' order by n) from jsonb_array_elements(j -> 'tickets') with ordinality as x(t, n)) = array['Wendtoin Kabore', 'Awa', 'Petit Paul'],
        'each ticket its own person, in order: ' || (j -> 'tickets')::text;
    perform set_config('request.jwt.claim.sub', '17217217-0000-0000-0000-000000000002', true);
    j := my_event_tickets();
    assert jsonb_array_length(j -> 0 -> 'tickets') = 3 and j -> 0 -> 'tickets' -> 2 ->> 'holder' = 'Petit Paul', 'the buyer sees the three, named: ' || j::text;
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    raise notice 'PASS: 172 — tickets bought with an account, one different name per ticket, each validated ticket its own person';
end $$;

rollback;
