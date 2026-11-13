-- ============================================================
-- test_batch182.sql — 182: the Événementiel free, with limits.
--
-- The claims:
--   1. tickets: a free business sells its card's first N (the console's
--      number), the buyer then told the online tickets are gone, the
--      organiser at the door told the Pro way; a Pro card sells on;
--      event_tickets_free_left counts;
--   2. the guests' album: Pro's — a free business's card says it is
--      closed and takes no photo, a Pro card takes them;
--   3. designs: the console makes a Premium design free, and its animated
--      scene with it; another stays Pro; only Marakaj's admins switch;
--   4. the writing assistant: free so many a day, Pro forty;
--   5. the console's numbers: read and set by Marakaj's admins only,
--      within bounds; the doors.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
\i database/migrations/182_events_free_limits.sql
\i database/migrations/182_events_free_limits.sql
revoke insert, update, delete on event_ticket_requests, event_ticket_lines, event_tickets from authenticated;

begin;
update platform_settings set value = 'true' where key = 'events_public';
update platform_settings set value = 'true' where key = 'events_tickets';
update platform_settings set value = '3' where key = 'events_free_tickets';
update platform_settings set value = '2' where key = 'events_assist_free_day';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('18218218-0000-0000-0000-000000000001', '+22618210001', 'awa182@example.com', '{"full_name": "Awa Pro"}', now()),
    ('18218218-0000-0000-0000-000000000002', '+22618210002', 'bob182@example.com', '{"full_name": "Bob Libre"}', now()),
    ('18218218-0000-0000-0000-000000000004', '+22618210004', 'mara182@example.com', '{"full_name": "Mara Admin"}', now()),
    ('18218218-0000-0000-0000-000000000005', '+22618210005', 'fan182@example.com', '{"full_name": "Fan"}', now());
insert into profiles (id, is_platform_admin) values ('18218218-0000-0000-0000-000000000004', true)
on conflict (id) do update set is_platform_admin = true;
insert into orgs (id, name, slug, profile, default_currency, plan, events_allowed) values
    ('18218218-1111-0000-0000-000000000001', 'Awa Concerts 182', 'awa-concerts-182', 'events', 'XOF', 'pro', true),
    ('18218218-1111-0000-0000-000000000002', 'Bob Fêtes 182', 'bob-fetes-182', 'events', 'XOF', 'free', true);
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('18218218-0000-0000-0000-000000000001', '18218218-1111-0000-0000-000000000001', 'owner', 'org', '18218218-1111-0000-0000-000000000001', 'full'),
    ('18218218-0000-0000-0000-000000000002', '18218218-1111-0000-0000-000000000002', 'owner', 'org', '18218218-1111-0000-0000-000000000002', 'full');
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, tz, published)
values
    ('18218218-2222-0000-0000-000000000001', '18218218-1111-0000-0000-000000000001', '18218218-0000-0000-0000-000000000001', 'gala', 'gala',
     'concert-awa-182', 'aaaaaaaaaaaaaaaaaaaaa182', 'bbbbbbbbbbbbbbbbbbbbb182', 'Concert Awa', now() + interval '10 days', 'CENASA', '{}', 'Africa/Ouagadougou', true),
    ('18218218-2222-0000-0000-000000000002', '18218218-1111-0000-0000-000000000002', '18218218-0000-0000-0000-000000000002', 'gala', 'gala',
     'fete-bob-182', 'ccccccccccccccccccccc182', 'ddddddddddddddddddddd182', 'Fête Bob', now() + interval '10 days', 'Bazoulé', '{}', 'Africa/Ouagadougou', true);
update events set tickets_on = true, pay_methods = '[{"kind": "orange", "number": "70 00 00 01", "name": "K."}]', pay_whatsapp = '+22670000001', hold_hours = 72
 where id in ('18218218-2222-0000-0000-000000000001', '18218218-2222-0000-0000-000000000002');
insert into event_ticket_types (id, event_id, name, price, capacity, sort) values
    ('18218218-3333-0000-0000-000000000001', '18218218-2222-0000-0000-000000000001', 'Standard', 2000, null, 1),
    ('18218218-3333-0000-0000-000000000002', '18218218-2222-0000-0000-000000000002', 'Entrée', 1000, null, 1);

create temp table t182 (k text primary key, v text);
grant all on t182 to anon, authenticated;

-- 1. tickets
do $$
declare v_err text;
begin
    -- a buyer, signed in (as 172 asks)
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18218218-0000-0000-0000-000000000005', true);
    perform event_ticket_request('fete-bob-182', null, 'Tanti', '70000011', '[{"type": "18218218-3333-0000-0000-000000000002", "qty": 2}]', null, '[{"type": "18218218-3333-0000-0000-000000000002", "name": "Tanti 1"}, {"type": "18218218-3333-0000-0000-000000000002", "name": "Tanti 2"}]');
    perform event_ticket_request('fete-bob-182', null, 'Oncle', '70000012', '[{"type": "18218218-3333-0000-0000-000000000002", "qty": 1}]', null, '[{"type": "18218218-3333-0000-0000-000000000002", "name": "Oncle 1"}]');
    begin
        perform event_ticket_request('fete-bob-182', null, 'Cousin', '70000013', '[{"type": "18218218-3333-0000-0000-000000000002", "qty": 1}]', null, '[{"type": "18218218-3333-0000-0000-000000000002", "name": "Cousin 1"}]');
        v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    insert into t182 values ('buyer', v_err);
    perform event_ticket_request('concert-awa-182', null, 'Fan', '70000021', '[{"type": "18218218-3333-0000-0000-000000000001", "qty": 5}]', null, '[{"type": "18218218-3333-0000-0000-000000000001", "name": "Fan 1"}, {"type": "18218218-3333-0000-0000-000000000001", "name": "Fan 2"}, {"type": "18218218-3333-0000-0000-000000000001", "name": "Fan 3"}, {"type": "18218218-3333-0000-0000-000000000001", "name": "Fan 4"}, {"type": "18218218-3333-0000-0000-000000000001", "name": "Fan 5"}]');
    perform event_ticket_request('concert-awa-182', null, 'Fan2', '70000022', '[{"type": "18218218-3333-0000-0000-000000000001", "qty": 4}]', null, '[{"type": "18218218-3333-0000-0000-000000000001", "name": "Fan2 1"}, {"type": "18218218-3333-0000-0000-000000000001", "name": "Fan2 2"}, {"type": "18218218-3333-0000-0000-000000000001", "name": "Fan2 3"}, {"type": "18218218-3333-0000-0000-000000000001", "name": "Fan2 4"}]');
    perform set_config('request.jwt.claim.sub', '18218218-0000-0000-0000-000000000002', true);
    insert into t182 values ('bob_left', event_tickets_free_left('18218218-2222-0000-0000-000000000002')::text);
    begin
        perform event_ticket_door_sale('18218218-2222-0000-0000-000000000002', '[{"type": "18218218-3333-0000-0000-000000000002", "qty": 1}]', 'Porte', null, 'cash');
        v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    insert into t182 values ('door', v_err);
    perform set_config('request.jwt.claim.sub', '18218218-0000-0000-0000-000000000001', true);
    insert into t182 values ('awa_left', event_tickets_free_left('18218218-2222-0000-0000-000000000001')::text);
    reset role;
end $$;
do $$ begin
    assert (select v from t182 where k = 'buyer') like 'Il ne reste plus de billets en ligne%', 'the buyer told: ' || (select v from t182 where k = 'buyer');
    assert (select v::jsonb from t182 where k = 'bob_left') = '{"cap": 3, "used": 3, "pro": false}'::jsonb, 'Bob counted: ' || (select v from t182 where k = 'bob_left');
    assert (select v from t182 where k = 'door') like 'Marakaj Pro : cette carte a vendu ses 3 billets gratuits%', 'the organiser told the Pro way: ' || (select v from t182 where k = 'door');
    assert (select (v::jsonb ->> 'pro')::boolean and (v::jsonb ->> 'used')::int = 9 from t182 where k = 'awa_left'), 'a Pro card sells on: ' || (select v from t182 where k = 'awa_left');
    raise notice 'PASS: a free card sells its first N tickets, the buyer and the organiser told; Pro sells on';
end $$;

-- 2. the album
update events set album_on = true where id = '18218218-2222-0000-0000-000000000001';
do $$
declare v_err text;
begin
    -- a free business's card opened before 182 (as Kaj's own were): the column set directly
    alter table events disable trigger events_album_guard;
    update events set album_on = true where id = '18218218-2222-0000-0000-000000000002';
    alter table events enable trigger events_album_guard;
    begin
        update events set album_limit = true where id = '18218218-2222-0000-0000-000000000002';
        v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err like 'Marakaj Pro : %', 'a free business cannot set the album''s controls: ' || v_err;
end $$;
set role anon;
do $$
declare v_err text;
begin
    insert into t182 values ('bob_rules', event_album_rules('fete-bob-182', null)::text);
    insert into t182 values ('awa_rules', event_album_rules('concert-awa-182', null)::text);
    begin
        perform event_album_add('fete-bob-182', null, 'jpg', 'Nora', null, 'phone-aaaaaaaaaaaaaaaa');
        v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    insert into t182 values ('bob_photo', v_err);
    insert into t182 values ('awa_photo', event_album_add('concert-awa-182', null, 'jpg', 'Nora', null, 'phone-aaaaaaaaaaaaaaaa'));
end $$;
reset role;
do $$ begin
    assert (select v::jsonb ->> 'on' from t182 where k = 'bob_rules') = 'false', 'the free card says its album is closed';
    assert (select v::jsonb ->> 'on' from t182 where k = 'awa_rules') = 'true', 'the Pro card''s album open';
    assert (select v from t182 where k = 'bob_photo') = 'L''album de cette carte est fermé.', 'no photo into a free album: ' || (select v from t182 where k = 'bob_photo');
    assert (select v from t182 where k = 'awa_photo') like 'events/%', 'a Pro card takes a photo';
    raise notice 'PASS: the guests'' album is Pro''s — a free card''s closed, a Pro card''s open';
end $$;

-- 3. designs
do $$
declare v_err text; d jsonb;
begin
    d := event_premium_designs();
    assert d -> 'designs' ? 'anime_sahel_p' and d -> 'scenes' ? 'lx-savane' and d -> 'scenes' ? 'lx-lotus', 'Premium at first: ' || d::text;
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18218218-0000-0000-0000-000000000002', true);
    begin
        perform admin_event_template_premium('anime_sahel_p', false);
        v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Réservé aux administrateurs de Marakaj.', 'only Marakaj''s admins switch: ' || v_err;
    perform set_config('request.jwt.claim.sub', '18218218-0000-0000-0000-000000000004', true);
    perform admin_event_template_premium('anime_sahel_p', false);
    reset role;
    d := event_premium_designs();
    assert not (d -> 'designs' ? 'anime_sahel_p') and not (d -> 'scenes' ? 'lx-savane') and d -> 'scenes' ? 'lx-lotus', 'made free, its scene too: ' || d::text;
    -- Studio's check for a free business: the freed scene passes, a Premium one does not
    perform studio_doc_check('18218218-2222-0000-0000-000000000002', '{"v": 2, "theme": {"scene": "lx-savane"}, "blocks": [{"id": "b1", "type": "cover"}]}');
    begin
        perform studio_doc_check('18218218-2222-0000-0000-000000000002', '{"v": 2, "theme": {"scene": "lx-lotus"}, "blocks": [{"id": "b1", "type": "cover", "style": {"bg": "scene", "scene": "lx-lotus"}}]}');
        v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err like '%Premium%', 'a Premium scene still Pro''s: ' || v_err;
    -- the card's own design: the freed one may be chosen, a Premium one not
    update events set card = 'anime_sahel_p' where id = '18218218-2222-0000-0000-000000000002';
    begin
        update events set card = 'anime_lotus_p' where id = '18218218-2222-0000-0000-000000000002';
        v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err like 'Marakaj Pro : %', 'a Premium design refused: ' || v_err;
    raise notice 'PASS: the console makes a design free, its scene with it; the others stay Pro; admins only';
end $$;

-- 4. the writing assistant
do $$
declare j jsonb; v_err text;
begin
    set local role anon;
    j := event_assist_use('fete-bob-182', 'ddddddddddddddddddddd182');
    assert j = '{"pro": false, "ok": true, "left": 1}'::jsonb, 'the first free text: ' || j::text;
    perform event_assist_use('fete-bob-182', 'ddddddddddddddddddddd182');
    begin
        perform event_assist_use('fete-bob-182', 'ddddddddddddddddddddd182');
        v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err like 'L''assistant a écrit ses 2 textes gratuits du jour%', 'the third refused: ' || v_err;
    j := event_assist_use('concert-awa-182', 'bbbbbbbbbbbbbbbbbbbbb182');
    assert j = '{"pro": true, "ok": true, "left": 39}'::jsonb, 'Pro has forty: ' || j::text;
    reset role;
    raise notice 'PASS: the assistant free so many a day, Pro forty';
end $$;

-- 5. the console's numbers; the doors
do $$
declare j jsonb; v_err text;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18218218-0000-0000-0000-000000000002', true);
    begin perform admin_events_settings(); v_err := 'TAKEN'; exception when others then v_err := sqlerrm; end;
    assert v_err = 'Réservé aux administrateurs de Marakaj.', 'a business may not read the console';
    perform set_config('request.jwt.claim.sub', '18218218-0000-0000-0000-000000000004', true);
    j := admin_events_set(30, 4);
    assert events_plan_numbers() = '{"free_tickets": 30, "assist_free_day": 4}'::jsonb, 'the Free / Pro page reads them: ' || events_plan_numbers()::text;
    assert (j ->> 'free_tickets')::int = 30 and (j ->> 'assist_free_day')::int = 4 and jsonb_array_length(j -> 'templates') > 0, 'set and read back: ' || left(j::text, 200);
    begin perform admin_events_set(-1, 4); v_err := 'TAKEN'; exception when others then v_err := sqlerrm; end;
    assert v_err like 'Billets gratuits par carte%', 'bounds: ' || v_err;
    begin perform admin_events_set(30, 41); v_err := 'TAKEN'; exception when others then v_err := sqlerrm; end;
    assert v_err like 'Textes gratuits par jour%', 'bounds: ' || v_err;
    reset role;
    assert has_function_privilege('anon', 'event_premium_designs()', 'execute')
       and has_function_privilege('anon', 'event_album_rules(text, text)', 'execute')
       and not has_function_privilege('anon', 'admin_events_set(integer, integer)', 'execute')
       and not has_function_privilege('anon', 'event_tickets_free_left(uuid)', 'execute')
       and not has_function_privilege('anon', 'event_org_unlimited(uuid)', 'execute'), 'the doors';
    raise notice 'PASS: the console''s numbers, Marakaj''s admins only, within bounds; the doors';
end $$;

rollback;
