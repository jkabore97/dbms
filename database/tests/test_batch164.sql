-- ============================================================
-- test_batch164.sql — 164: the guests' album, a Pro option.
--
-- The claims:
--   1. the switch off: nothing changes, a free business opens its album;
--   2. the switch on: a free business's new card starts closed and may
--      not open it; an album already open stays open; Pro may;
--   3. « 5 photos par invité »: no pass, refused; a guest's answer brings
--      five, a ticket request five per ticket; another event's pass,
--      refused; the old door is held to the same rule;
--   4. « visibles après validation »: a picture waits for the organiser's
--      yes; the yes is the admins' alone;
--   5. the card reads its album's rules.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
-- 179's album door taken off while 164 is installed again over a newer database
drop function if exists event_album_add(text, text, text, text, uuid, text);
\i database/migrations/164_events_album_pro.sql
\i database/migrations/164_events_album_pro.sql
-- 179 replaced event_album_add (a phone's identifier added): back to it
\i database/migrations/179_album_open_quota.sql

begin;
update platform_settings set value = 'false' where key = 'events_tickets';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('16416416-0000-0000-0000-000000000001', '+22616410001', 'awa164@example.com', '{"full_name": "Awa"}', now()),
    ('16416416-0000-0000-0000-000000000002', '+22616410002', 'bob164@example.com', '{"full_name": "Bob"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan) values
    ('16416416-1111-0000-0000-000000000001', 'Awa Pro 164', 'awa-pro-164', 'events', 'XOF', 'pro'),
    ('16416416-1111-0000-0000-000000000002', 'Bob Libre 164', 'bob-libre-164', 'events', 'XOF', 'free');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('16416416-0000-0000-0000-000000000001', '16416416-1111-0000-0000-000000000001', 'owner', 'org', '16416416-1111-0000-0000-000000000001', 'full'),
    ('16416416-0000-0000-0000-000000000002', '16416416-1111-0000-0000-000000000002', 'owner', 'org', '16416416-1111-0000-0000-000000000002', 'full');

create temp table t164 (k text primary key, v text);
grant all on t164 to anon, authenticated;

-- 1–2. who may open an album
do $$
declare v_err text;
begin
    -- The switch off: Bob's card opens its album as before.
    insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, content, tz, published, album_on)
    values ('16416416-2222-0000-0000-000000000001', '16416416-1111-0000-0000-000000000002', '16416416-0000-0000-0000-000000000002',
            'anniversaire', 'gala', 'fete-avant-164', 'aaaaaaaaaaaaaaaaaaaaaa64', 'bbbbbbbbbbbbbbbbbbbbbb64', 'Avant', now() + interval '3 days', '{}', 'Africa/Ouagadougou', true, true);
    assert (select album_on from events where id = '16416416-2222-0000-0000-000000000001'), 'before the switch: open';

    update platform_settings set value = 'true' where key = 'events_tickets';
    insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, content, tz, published, album_on)
    values ('16416416-2222-0000-0000-000000000002', '16416416-1111-0000-0000-000000000002', '16416416-0000-0000-0000-000000000002',
            'anniversaire', 'gala', 'fete-apres-164', 'cccccccccccccccccccccc64', 'dddddddddddddddddddddd64', 'Après', now() + interval '3 days', '{}', 'Africa/Ouagadougou', true, true);
    assert not (select album_on from events where id = '16416416-2222-0000-0000-000000000002'), 'a free new card starts closed';
    begin
        update events set album_on = true where id = '16416416-2222-0000-0000-000000000002';
        raise exception 'a free business opened its album';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Marakaj Pro : %', 'the Pro way: ' || v_err;
    end;
    assert (select album_on from events where id = '16416416-2222-0000-0000-000000000001'), 'the album already open stays open';
    update events set title = 'Avant, toujours' where id = '16416416-2222-0000-0000-000000000001';

    insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, content, tz, published, album_on, album_limit, album_review)
    values ('16416416-2222-0000-0000-000000000003', '16416416-1111-0000-0000-000000000001', '16416416-0000-0000-0000-000000000001',
            'gala', 'gala', 'gala-164', 'eeeeeeeeeeeeeeeeeeeeee64', 'ffffffffffffffffffffff64', 'Gala', now() + interval '3 days', '{}', 'Africa/Ouagadougou', true, true, true, false);
    assert (select album_on and album_limit from events where id = '16416416-2222-0000-0000-000000000003'), 'Pro opens and limits';
    insert into event_rsvps (id, event_id, name, answer) values
        ('16416416-4444-0000-0000-000000000001', '16416416-2222-0000-0000-000000000003', 'Tanti Rose', 'oui'),
        ('16416416-4444-0000-0000-000000000002', '16416416-2222-0000-0000-000000000001', 'Ailleurs', 'oui');
end $$;

-- 3. five per pass
do $$
declare v_err text; i integer;
begin
    set local role anon;
    begin
        perform event_album_add('gala-164', null, 'jpg', 'Sans carte', null);
        raise exception 'a picture with no pass';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'L''album est réservé aux invités%', 'no pass: ' || v_err;
    end;
    begin
        perform event_album_slot('gala-164', null, 'jpg', 'Ancienne carte');
        raise exception 'the old door let a picture in';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'L''album est réservé aux invités%', 'the old door, the same rule: ' || v_err;
    end;
    begin
        perform event_album_add('gala-164', null, 'jpg', 'Ailleurs', '16416416-4444-0000-0000-000000000002');
        raise exception 'another event''s pass';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like '%n''est pas de cet événement%', 'another event: ' || v_err;
    end;
    for i in 1 .. 5 loop
        perform event_album_add('gala-164', null, 'jpg', 'Tanti Rose', '16416416-4444-0000-0000-000000000001');
    end loop;
    begin
        perform event_album_add('gala-164', null, 'jpg', 'Tanti Rose', '16416416-4444-0000-0000-000000000001');
        raise exception 'a sixth picture';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Vous avez déposé vos 5 photos%', 'five, no more: ' || v_err;
    end;
    -- Bob's album, open before the switch and not limited: as before.
    perform event_album_add('fete-avant-164', null, 'jpg', 'Cousin', null);
    reset role;
end $$;

-- 4. the organiser's yes
do $$
declare v_key text; v_err text; j jsonb;
begin
    update events set album_limit = false, album_review = true where id = '16416416-2222-0000-0000-000000000003';
    set local role anon;
    v_key := event_album_add('gala-164', null, 'jpg', 'Papa Jo', null);
    insert into t164 values ('key', v_key);
    perform event_album_done(v_key, null, 1000);
    j := event_album('gala-164');
    assert not exists (select 1 from jsonb_array_elements(j) x where x ->> 'key' = v_key), 'waiting for the yes';
    j := event_album_rules('gala-164');
    assert (j ->> 'review')::boolean and not (j ->> 'limit')::boolean and (j ->> 'per_pass')::int = 5, 'the rules: ' || j::text;
    begin
        perform event_picture_approve(v_key);
        raise exception 'the street approved';
    exception when insufficient_privilege then null;
    end;
    reset role;
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '16416416-0000-0000-0000-000000000002', true);
    begin
        perform event_picture_approve((select v from t164 where k = 'key'));
        raise exception 'another business approved';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Seuls les administrateurs%', 'admins only: ' || v_err;
    end;
    perform set_config('request.jwt.claim.sub', '16416416-0000-0000-0000-000000000001', true);
    perform event_picture_approve((select v from t164 where k = 'key'));
    reset role;
    set local role anon;
    assert exists (select 1 from jsonb_array_elements(event_album('gala-164')) x where x ->> 'key' = (select v from t164 where k = 'key')), 'in the album once approved';
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    raise notice 'PASS: 164 — the album a Pro option once the switch is on (open albums kept), five photos per pass or ticket, photos after the organiser''s yes';
end $$;

rollback;
