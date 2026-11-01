-- ============================================================
-- test_batch157.sql — 157: a Premium design is Marakaj Pro's.
--
-- The claims:
--   1. installed twice, the same: a free business's owner makes a card
--      with a classic design, is refused a Premium one — at creation and
--      at a change of design — with « Marakaj Pro : … »; a Pro business
--      is not; a Pro past its day is refused again; a card already made
--      with a Premium design keeps it and takes its other changes;
--   2. the guard is a trigger's, callable by nobody on the street.
-- Wrapped in one transaction rolled back: runs twice the same.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- Installed twice, the same.
\i database/migrations/157_events_premium.sql
\i database/migrations/157_events_premium.sql

begin;

update platform_settings set value = 'true' where key = 'events_public';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('15715715-0000-0000-0000-000000000001', '+22615710001', 'awa157@example.com', '{"full_name": "Awa Planner"}', now()),
    ('15715715-0000-0000-0000-000000000002', '+22615710002', 'bea157@example.com', '{"full_name": "Béa Pro"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan) values
    ('15715715-1111-0000-0000-000000000001', 'Awa Événements 157', 'awa-evenements-157', 'events', 'XOF', 'free'),
    ('15715715-1111-0000-0000-000000000002', 'Béa Événements 157', 'bea-evenements-157', 'events', 'XOF', 'pro');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('15715715-0000-0000-0000-000000000001', '15715715-1111-0000-0000-000000000001', 'owner', 'org', '15715715-1111-0000-0000-000000000001', 'full'),
    ('15715715-0000-0000-0000-000000000002', '15715715-1111-0000-0000-000000000002', 'owner', 'org', '15715715-1111-0000-0000-000000000002', 'full');

-- 1. the door: free refused, Pro let through, expired refused, made kept
do $$
declare
    e events;
    v_err text;
begin
    assert (select premium from event_templates where key = 'anime_lotus_p'), 'the Lotus is a Premium design';
    assert not (select premium from event_templates where key = 'come'), 'Côme is not';

    -- Awa, free.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15715715-0000-0000-0000-000000000001', true);
    e := event_create('15715715-1111-0000-0000-000000000001', 'Inès & Thomas', 'mariage', 'come', '2027-06-05 15:00+00', 'Villa Serena', '+00:00');
    assert e.card = 'come', 'a classic design, made';
    begin
        perform event_create('15715715-1111-0000-0000-000000000001', 'Awa & Issa', 'mariage', 'anime_lotus_p', '2027-06-05 15:00+00', null, '+00:00');
        raise exception 'a free business made a card with a Premium design';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Marakaj Pro : %', 'refused the Pro way at creation: ' || v_err;
    end;
    begin
        update events set card = 'anime_lotus_p' where id = e.id;
        raise exception 'a free business switched its card to a Premium design';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Marakaj Pro : %', 'refused the Pro way at a change of design: ' || v_err;
    end;
    assert (select card from events where id = e.id) = 'come', 'the card keeps its classic design';
    update events set card = 'anime_lettre' where id = e.id;
    assert (select card from events where id = e.id) = 'anime_lettre', 'an animated design that is not Premium: taken';
    reset role;

    -- Béa, Pro.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15715715-0000-0000-0000-000000000002', true);
    e := event_create('15715715-1111-0000-0000-000000000002', 'Béa & Karim', 'mariage', 'anime_lotus_p', '2027-06-05 15:00+00', null, '+00:00');
    assert e.card = 'anime_lotus_p', 'a Pro business makes its card with a Premium design';
    reset role;

    -- Béa's Pro past its day: a new Premium card refused, the made one kept.
    update orgs set plan_until = (now() at time zone 'Africa/Ouagadougou')::date - 1 where id = '15715715-1111-0000-0000-000000000002';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15715715-0000-0000-0000-000000000002', true);
    begin
        perform event_create('15715715-1111-0000-0000-000000000002', 'Encore', 'mariage', 'anime_sahel_p', '2027-06-05 15:00+00', null, '+00:00');
        raise exception 'a Pro past its day made a card with a Premium design';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Marakaj Pro : %', 'refused once Pro is past: ' || v_err;
    end;
    update events set title = 'Béa & Karim, enfin', place = 'Koudougou' where id = e.id;
    assert (select title from events where id = e.id) = 'Béa & Karim, enfin', 'the card made with a Premium design keeps it and takes its other changes';
    assert (select card from events where id = e.id) = 'anime_lotus_p', 'its design kept';
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- 2. the guard is a trigger's
do $$
begin
    assert exists (select 1 from pg_trigger where tgname = 'events_premium_guard' and tgrelid = 'events'::regclass and not tgisinternal),
        'the guard is on events';
    assert (select prosecdef from pg_proc where oid = 'events_premium_guard()'::regprocedure), 'DEFINER: it reads the templates and the plan whoever writes';
    assert not has_function_privilege('anon', 'events_premium_guard()', 'execute'), 'the street cannot call it';
    assert not has_function_privilege('public', 'events_premium_guard()', 'execute'), 'PUBLIC cannot call it';
    raise notice 'PASS: 157 — a Premium design is Marakaj Pro''s: refused to a free business at creation and at a change of design, taken by a Pro one, a made card kept';
end $$;

rollback;
