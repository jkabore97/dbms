-- ============================================================
-- test_batch158.sql — 158: a real guest pass.
--
-- The claims:
--   1. installed twice, the same: a guest's answer is a pass — its id
--      opens event_pass for the street (name, how many, the event, the
--      day, the place, arrived or not; never the message), on a card
--      published or not; a wrong id or a wrong card: nothing;
--   2. the arrival mark is the business's admins' alone: the owner marks
--      it and the pass says so; another business's owner changes nothing;
--      the street cannot write; the admin cannot touch the rest of the
--      answer through it.
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
\i database/migrations/158_events_pass.sql
\i database/migrations/158_events_pass.sql
-- 152's grant on the answers is select and delete; 158 adds the arrival
-- column alone. The blanket grant above (the suites' preamble) would hide
-- that: taken back here to what the migrations give.
revoke update on event_rsvps from authenticated;
grant update (arrived_at) on event_rsvps to authenticated;

begin;

update platform_settings set value = 'true' where key = 'events_public';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('15815815-0000-0000-0000-000000000001', '+22615810001', 'awa158@example.com', '{"full_name": "Awa Planner"}', now()),
    ('15815815-0000-0000-0000-000000000002', '+22615810002', 'bob158@example.com', '{"full_name": "Bob Autre"}', now());
insert into orgs (id, name, slug, profile, default_currency) values
    ('15815815-1111-0000-0000-000000000001', 'Awa Événements 158', 'awa-evenements-158', 'events', 'XOF'),
    ('15815815-1111-0000-0000-000000000002', 'Autre Événementiel 158', 'autre-158', 'events', 'XOF');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('15815815-0000-0000-0000-000000000001', '15815815-1111-0000-0000-000000000001', 'owner', 'org', '15815815-1111-0000-0000-000000000001', 'full'),
    ('15815815-0000-0000-0000-000000000002', '15815815-1111-0000-0000-000000000002', 'owner', 'org', '15815815-1111-0000-0000-000000000002', 'full');
insert into events (org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, tz, published)
values ('15815815-1111-0000-0000-000000000001', '15815815-0000-0000-0000-000000000001', 'mariage', 'come',
        'ines-thomas-158', 'aaaaaaaaaaaaaaaaaaaaaaa8', 'bbbbbbbbbbbbbbbbbbbbbbb8', 'Inès & Thomas',
        '2027-06-05 15:00+00', 'Villa Serena', '{}', 'Africa/Ouagadougou', true);

create temp table t158 (k text primary key, v text);
grant all on t158 to anon, authenticated;

-- 1. the answer is a pass
do $$
declare
    v_id uuid;
    j jsonb;
begin
    set local role anon;
    v_id := event_rsvp('ines-thomas-158', null, 'Tanti Rose', 2, 'oui', 'Avec joie !', '{}');
    insert into t158 values ('pass', v_id::text);
    j := event_pass('ines-thomas-158', v_id);
    assert j is not null and j ->> 'name' = 'Tanti Rose' and (j ->> 'people')::int = 2 and j ->> 'answer' = 'oui',
        'the street reads the pass by its id: ' || coalesce(j::text, 'nothing');
    assert j ->> 'title' = 'Inès & Thomas' and j ->> 'place' = 'Villa Serena' and j ->> 'date_fr' like '%2027%' and j ->> 'org_name' = 'Awa Événements 158',
        'the event, the day, the place, the business: ' || j::text;
    assert j -> 'arrived_at' = 'null'::jsonb, 'not arrived yet';
    assert not (j ? 'message') and not (j ? 'extra') and not (j ? 'edit_token') and not (j ? 'preview_token'), 'the message and the tokens never on the pass';
    assert event_pass('autre-carte', v_id) is null, 'a wrong card: nothing';
    assert event_pass('ines-thomas-158', '00000000-0000-4000-8000-000000000000') is null, 'a wrong id: nothing';
    reset role;
    update events set published = false where slug = 'ines-thomas-158';
    set local role anon;
    assert event_pass('ines-thomas-158', v_id) is not null, 'the pass holds on a card taken off: the id is the key';
    reset role;
    update events set published = true where slug = 'ines-thomas-158';
    assert has_function_privilege('anon', 'event_pass(text, uuid)', 'execute'), 'the street may read a pass';
    assert not has_function_privilege('public', 'event_pass(text, uuid)', 'execute'), 'PUBLIC may not';
end $$;

-- 2. the arrival mark
do $$
declare
    v_id uuid := (select v from t158 where k = 'pass')::uuid;
    v_n integer;
    j jsonb;
begin
    -- Another business's owner: nothing changes.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15815815-0000-0000-0000-000000000002', true);
    update event_rsvps set arrived_at = now() where id = v_id;
    get diagnostics v_n = row_count;
    assert v_n = 0, 'another business''s owner marks nothing';
    reset role;

    -- The street cannot write.
    set local role anon;
    begin
        update event_rsvps set arrived_at = now() where id = v_id;
        raise exception 'the street marked an arrival';
    exception when insufficient_privilege then
        null;
    end;
    reset role;

    -- The owner marks the arrival; the pass says so; nothing else of the answer is theirs to write.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15815815-0000-0000-0000-000000000001', true);
    update event_rsvps set arrived_at = '2027-06-05 18:05+00' where id = v_id;
    get diagnostics v_n = row_count;
    assert v_n = 1, 'the owner marks the arrival';
    begin
        update event_rsvps set name = 'Quelqu''un d''autre' where id = v_id;
        raise exception 'the owner rewrote a guest''s name';
    exception when insufficient_privilege then
        null;
    end;
    reset role;
    set local role anon;
    j := event_pass('ines-thomas-158', v_id);
    assert (j ->> 'arrived_at')::timestamptz = '2027-06-05 18:05+00', 'the pass says when they arrived: ' || j::text;
    reset role;
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15815815-0000-0000-0000-000000000001', true);
    update event_rsvps set arrived_at = null where id = v_id;
    get diagnostics v_n = row_count;
    assert v_n = 1, 'and takes it back';
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    raise notice 'PASS: 158 — a guest''s answer is a pass the street reads by its id; the arrival is the business''s admins'' mark alone';
end $$;

rollback;
