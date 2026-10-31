-- ============================================================
-- test_batch152.sql — 152: Événementiel, piece 1.
--
-- The claims:
--   1. installed twice, the same: the switch seeded off; the three tables
--      with row level security; the doors (events_options, event_public,
--      event_rsvp) SECURITY DEFINER, pinned, open to anon; event_create
--      SECURITY INVOKER, authenticated's, never anon's; events_open and
--      events_public_on closed to the street;
--   2. the switch off: a shop's admin cannot create an event (the policy
--      refuses), a platform admin can; the switch on: the admin creates one
--      — its address from its title, its preview token, the card's first
--      words seeded and escaped — the shop's seller sees none of it, the
--      admin sees it, and so does an association's;
--   3. the card for the street: nothing for an unpublished event, the card
--      with its preview token, the card once published and public, nothing
--      once published but the switch off — unless the token — and the
--      token never in the answer;
--   4. a guest's answer through event_rsvp: refused on a card the street
--      may not see, taken with the token or once public, each check in
--      French (the name, the answer, the people, the message), refused when
--      the event closed its answers; the admin reads it, the seller cannot;
--   5. events_options tells the street the switch;
--   0. before all that: the file installs and mints with pgcrypto where
--      Supabase keeps it — in `extensions`, out of every pinned search path.
--      The first live run died on « function gen_random_bytes(integer) does
--      not exist » while this test passed with pgcrypto in public.
-- Names: « Boutique Mariages d'Awa », « Association des Anciens ». Wrapped
-- in one transaction rolled back: runs twice the same.
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
-- As on Supabase, where auth.uid() is every role's to call.
grant usage on schema auth to anon, authenticated;

-- 0. pgcrypto where Supabase keeps it. Rolled back: the extension comes
--    back to public for every test after this one.
begin;
drop extension if exists pgcrypto;
create schema if not exists extensions;
create extension pgcrypto schema extensions;
-- 152, then 153 over it as the migrations run: 153 drops 152's
-- six-argument event_create for its seven-argument one, so a call names
-- one function.
\i database/migrations/152_events.sql
\i database/migrations/153_events_kind.sql
insert into orgs (id, name, slug, profile, default_currency) values
    ('15215215-1111-0000-0000-000000000009', 'Sans pgcrypto', 'sans-pgcrypto-152', 'events', 'XOF');
do $$
declare r events;
begin
    assert not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where p.proname = 'gen_random_bytes' and n.nspname = 'public'),
        'pgcrypto is out of public, as on Supabase';
    assert event_slug('Inès & Thomas') ~ '^ines-thomas-[0-9a-f]{4}$', 'the address minted without pgcrypto';
    r := event_create('15215215-1111-0000-0000-000000000009', 'Inès & Thomas', 'mariage', 'come', null, null);
    assert r.preview_token ~ '^[0-9a-f]{24}$', 'the preview token minted without pgcrypto: ' || r.preview_token;
    raise notice 'PASS: 152 and 153 install and mint with pgcrypto in `extensions`, as on Supabase';
end $$;
rollback;

\i database/migrations/152_events.sql
\i database/migrations/152_events.sql
-- 153 moved the cards to the Événementiel kind and gave event_create its
-- seventh argument: restored after 152's re-run, as the migrations run in
-- order. The claims below hold with the businesses being Événementiels.
\i database/migrations/153_events_kind.sql

begin;

-- 1. installed twice, the same
do $$
declare
    f text;
begin
    assert (select value from platform_settings where key = 'events_public') = 'false'::jsonb,
        'the switch is seeded off';
    foreach f in array array['events', 'event_rsvps', 'event_guest_photos'] loop
        assert (select relrowsecurity from pg_class where relname = f), f || ' has row level security';
    end loop;
    foreach f in array array['events_options()', 'event_public(text, text)',
                             'event_rsvp(text, text, text, integer, text, text, jsonb)'] loop
        assert (select prosecdef from pg_proc where oid = to_regprocedure(f)), f || ' is SECURITY DEFINER';
        assert (select proconfig::text like '%search_path=public%' from pg_proc where oid = to_regprocedure(f)),
            f || ' pins its search path';
        assert has_function_privilege('anon', f, 'execute'), 'the street may call ' || f;
        assert has_function_privilege('authenticated', f, 'execute'), 'a member may call ' || f;
    end loop;
    assert not (select prosecdef from pg_proc where oid = to_regprocedure('event_create(uuid, text, text, text, timestamptz, text, text)')),
        'event_create is SECURITY INVOKER: bound by the policies';
    assert has_function_privilege('authenticated', 'event_create(uuid, text, text, text, timestamptz, text, text)', 'execute'),
        'a member may call event_create';
    foreach f in array array['event_create(uuid, text, text, text, timestamptz, text, text)', 'events_open()',
                             'events_public_on()', 'event_visible(events, text)'] loop
        assert not has_function_privilege('anon', f, 'execute'), 'the street cannot call ' || f;
        assert not has_function_privilege('public', f, 'execute'), 'PUBLIC cannot call ' || f;
    end loop;
    assert event_date_fr('2026-12-12 16:00+00') = 'Samedi 12 décembre 2026 · 16 h', 'the date in French: ' || event_date_fr('2026-12-12 16:00+00');
    assert event_date_fr('2027-02-13 18:30+00') = 'Samedi 13 février 2027 · 18 h 30', 'the half hour: ' || event_date_fr('2027-02-13 18:30+00');
    assert event_slug('Inès & Thomas') ~ '^ines-thomas-[0-9a-f]{4}$', 'the address from the title: ' || event_slug('Inès & Thomas');
    assert event_slug('   ') ~ '^evenement-[0-9a-f]{4}$', 'an empty title still has an address';
end $$;

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('15215215-0000-0000-0000-000000000001', '+22615210001', 'awa152@example.com',    '{"full_name": "Awa Planner"}',   now()),
    ('15215215-0000-0000-0000-000000000002', '+22615210002', 'seller152@example.com', '{"full_name": "La vendeuse"}',   now()),
    ('15215215-0000-0000-0000-000000000003', '+22615210003', 'admin152@example.com',  '{"full_name": "Mara Admin"}',    now()),
    ('15215215-0000-0000-0000-000000000004', '+22615210004', 'assoc152@example.com',  '{"full_name": "Salif Anciens"}', now());
update profiles set is_platform_admin = true where id = '15215215-0000-0000-0000-000000000003';

-- Two Événementiels (153): a planner's, and an association's own events
-- activity.
insert into orgs (id, name, slug, profile, default_currency) values
    ('15215215-1111-0000-0000-000000000001', 'Boutique Mariages d''Awa', 'mariages-awa-152', 'events', 'XOF'),
    ('15215215-1111-0000-0000-000000000002', 'Association des Anciens', 'anciens-152', 'events', 'XOF');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('15215215-0000-0000-0000-000000000001', '15215215-1111-0000-0000-000000000001', 'owner',    'org', '15215215-1111-0000-0000-000000000001', 'full'),
    ('15215215-0000-0000-0000-000000000002', '15215215-1111-0000-0000-000000000001', 'employee', 'org', '15215215-1111-0000-0000-000000000001', 'full'),
    ('15215215-0000-0000-0000-000000000004', '15215215-1111-0000-0000-000000000002', 'owner',    'org', '15215215-1111-0000-0000-000000000002', 'full');

-- 2. the switch off, then on
create temp table t152 (k text primary key, v text) on commit drop;
grant select, insert on t152 to authenticated;
do $$
declare
    r events;
    v_refused boolean := false;
begin
    -- Off: the shop's owner is refused by the policy itself.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15215215-0000-0000-0000-000000000001', true);
    begin
        r := event_create('15215215-1111-0000-0000-000000000001', 'Inès & Thomas', 'mariage', 'come', '2027-06-05 15:00+00', 'Villa Serena');
    exception when insufficient_privilege or others then
        v_refused := sqlstate = '42501' or sqlerrm like '%row-level security%';
    end;
    assert v_refused, 'the switch off: a business''s admin cannot create an event';
    assert (select count(*) from events) = 0, 'and sees none';
    -- Off: a platform admin can, in that shop.
    perform set_config('request.jwt.claim.sub', '15215215-0000-0000-0000-000000000003', true);
    r := event_create('15215215-1111-0000-0000-000000000001', 'Essai de Mara', 'gala', 'gala', null, null);
    assert r.slug ~ '^essai-de-mara-[0-9a-f]{4}$', 'the platform admin''s event has its address';
    assert (select count(*) from events) = 1, 'the platform admin sees it';
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    delete from events where id = r.id;

    -- On: the shop's owner creates the wedding.
    update platform_settings set value = 'true' where key = 'events_public';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15215215-0000-0000-0000-000000000001', true);
    r := event_create('15215215-1111-0000-0000-000000000001', 'Inès & Thomas', 'mariage', 'come', '2027-06-05 15:00+00', 'Villa Serena <Côme>');
    assert r.slug ~ '^ines-thomas-[0-9a-f]{4}$', 'the address from the title';
    assert length(r.preview_token) = 24 and r.preview_token ~ '^[0-9a-f]+$', 'a preview token of 24 hex characters';
    assert r.created_by = '15215215-0000-0000-0000-000000000001', 'signed by its creator';
    assert r.content ->> 'type' = 'mariage', 'the card is set to the kind';
    assert r.content ->> 't:names' = 'Inès &amp; Thomas', 'the names seeded, escaped: ' || (r.content ->> 't:names');
    assert r.content ->> 't:date' = 'Samedi 5 juin 2027 · 15 h', 'the date seeded in French';
    assert r.content ->> 't:place' = 'Villa Serena &lt;Côme&gt;', 'the place seeded, escaped';
    assert not r.published, 'born unpublished';
    assert (select count(*) from events) = 1, 'the owner sees her event';
    insert into t152 values ('event', r.id::text), ('slug', r.slug), ('token', r.preview_token);
    -- The seller sees nothing of it.
    perform set_config('request.jwt.claim.sub', '15215215-0000-0000-0000-000000000002', true);
    assert (select count(*) from events) = 0, 'the seller sees no event';
    begin
        r := event_create('15215215-1111-0000-0000-000000000001', 'Du vendeur', 'mariage', 'come', null, null);
        v_refused := false;
    exception when others then
        v_refused := true;
    end;
    assert v_refused, 'and cannot create one';
    -- A second Événementiel's owner has the same door.
    perform set_config('request.jwt.claim.sub', '15215215-0000-0000-0000-000000000004', true);
    r := event_create('15215215-1111-0000-0000-000000000002', 'Gala des Anciens', 'gala', 'gala', '2027-03-11 18:30+00', 'Hôtel Bravia');
    assert r.kind = 'gala' and r.card = 'gala', 'the association''s gala';
    assert (select count(*) from events) = 1, 'the association sees its own event only';
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- 3. the card for the street
do $$
declare
    v_slug text := (select v from t152 where k = 'slug');
    v_token text := (select v from t152 where k = 'token');
    j jsonb;
begin
    set local role anon;
    perform set_config('request.jwt.claim.sub', '', true);
    assert event_public(v_slug) is null, 'unpublished: nothing for the street';
    j := event_public(v_slug, v_token);
    assert j is not null and j ->> 'title' = 'Inès & Thomas', 'the preview token opens it';
    assert j ->> 'card' = 'come' and j ->> 'kind' = 'mariage', 'the card and the kind';
    assert j -> 'content' ->> 't:names' = 'Inès &amp; Thomas', 'the content';
    assert (j ->> 'preview')::boolean, 'said to be a preview';
    assert j ->> 'org_name' = 'Boutique Mariages d''Awa', 'who is behind it';
    assert j::text not like '%' || v_token || '%', 'the token is never in the answer';
    assert j ? 'preview_token' = false and j ? 'id' = false, 'nor the id';
    assert event_public(v_slug, 'wrong-token-wrong-token-') is null, 'a wrong token opens nothing';
    assert event_public('no-such-card') is null, 'no such card';
    reset role;

    update events set published = true where slug = v_slug;
    set local role anon;
    j := event_public(v_slug);
    assert j is not null and not (j ->> 'preview')::boolean, 'published and public: the street sees it';
    reset role;

    update platform_settings set value = 'false' where key = 'events_public';
    set local role anon;
    assert event_public(v_slug) is null, 'the switch off: the street sees nothing, published or not';
    assert event_public(v_slug, v_token) is not null, 'but the preview link still does';
    reset role;
    -- The business's own admin sees the card signed in, switch off or on.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15215215-0000-0000-0000-000000000001', true);
    assert event_public(v_slug) is not null, 'the owner sees her card';
    perform set_config('request.jwt.claim.sub', '15215215-0000-0000-0000-000000000002', true);
    assert event_public(v_slug) is null, 'the seller does not';
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    update platform_settings set value = 'true' where key = 'events_public';
end $$;

-- 4. a guest's answer
do $$
declare
    v_slug text := (select v from t152 where k = 'slug');
    v_token text := (select v from t152 where k = 'token');
    v_id uuid;
    v_msg text;
begin
    update events set published = false where slug = v_slug;
    set local role anon;
    perform set_config('request.jwt.claim.sub', '', true);
    begin
        v_id := event_rsvp(v_slug, null, 'Tanti Rose', 2, 'oui', null, '{}');
        v_msg := null;
    exception when others then v_msg := sqlerrm;
    end;
    assert v_msg = 'Cette carte n''est pas ouverte.', 'unpublished: the answer is refused: ' || coalesce(v_msg, 'taken');
    v_id := event_rsvp(v_slug, v_token, 'Tanti Rose', 2, 'oui', 'Avec joie !', '{"diet": "sans porc"}');
    assert v_id is not null, 'with the token, taken';
    reset role;
    update events set published = true where slug = v_slug;
    set local role anon;
    v_id := event_rsvp(v_slug, null, 'Cousin Malik', 1, 'non', null, null);
    assert v_id is not null, 'published and public, taken without the token';
    v_id := event_rsvp(v_slug, null, 'Un ancien élève', 0, 'mot', 'Un mot pour la famille.', null);
    assert v_id is not null, 'a word alone, taken';
    begin v_id := event_rsvp(v_slug, null, '', 1, 'oui', null, null); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Votre nom, en 80 caractères au plus.', 'no name: ' || coalesce(v_msg, 'taken');
    begin v_id := event_rsvp(v_slug, null, repeat('a', 81), 1, 'oui', null, null); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Votre nom, en 80 caractères au plus.', 'a name too long: ' || coalesce(v_msg, 'taken');
    begin v_id := event_rsvp(v_slug, null, 'X', 1, 'peut-être', null, null); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Réponse inconnue.', 'an unknown answer: ' || coalesce(v_msg, 'taken');
    begin v_id := event_rsvp(v_slug, null, 'X', 21, 'oui', null, null); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Entre 0 et 20 personnes.', 'too many people: ' || coalesce(v_msg, 'taken');
    begin v_id := event_rsvp(v_slug, null, 'X', 1, 'oui', repeat('m', 1001), null); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Un mot de 1 000 caractères au plus.', 'a message too long: ' || coalesce(v_msg, 'taken');
    begin v_id := event_rsvp(v_slug, null, 'X', 1, 'oui', null, '[1, 2]'); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Réponse mal formée.', 'extra must be an object: ' || coalesce(v_msg, 'taken');
    reset role;
    update events set rsvp_on = false where slug = v_slug;
    set local role anon;
    begin v_id := event_rsvp(v_slug, null, 'Tard', 1, 'oui', null, null); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Les réponses sont fermées pour cet événement.', 'answers closed: ' || coalesce(v_msg, 'taken');
    reset role;
    update events set rsvp_on = true where slug = v_slug;

    -- The admin reads the three answers; the seller none.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15215215-0000-0000-0000-000000000001', true);
    assert (select count(*) from event_rsvps) = 3, 'the owner reads the three answers';
    assert (select extra ->> 'diet' from event_rsvps where name = 'Tanti Rose') = 'sans porc', 'with what the guest added';
    perform set_config('request.jwt.claim.sub', '15215215-0000-0000-0000-000000000002', true);
    assert (select count(*) from event_rsvps) = 0, 'the seller reads none';
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- 5. the switch, told to the street
do $$
begin
    set local role anon;
    assert (events_options() ->> 'public')::boolean, 'the street is told the module is public';
    reset role;
    update platform_settings set value = 'false' where key = 'events_public';
    set local role anon;
    assert not (events_options() ->> 'public')::boolean, 'and told when it is not';
    reset role;
    raise notice 'PASS: 152 — the switch off keeps events to Marakaj''s admins, on opens them to every business''s admins; the card and the answers reach the street through their doors only; the preview link works before everything';
end $$;

rollback;
