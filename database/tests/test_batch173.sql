-- ============================================================
-- test_batch173.sql — 173: Studio, phases 2 and 3, the server's part.
--
-- The claims:
--   1. « Mes photos »: a picture of another card of the same business is
--      accepted in a document; one of another business is refused; the
--      editor's list (event_library) holds the business's pictures only;
--   2. a Premium scene (lx-…) is Marakaj Pro's: refused on a free plan,
--      kept by a card that had it when the plan lapsed; a free scene is
--      anyone's; event_public says « pro » to the editor, nothing to guests;
--   3. the answers: the organiser's questions answered (three at most, 300
--      characters each), the closing day held by the server and told by
--      event_public;
--   4. views and shares counted (published cards only), read by the
--      business (event_stats), nothing to another business or the street;
--   5. the assistant's allowance: Pro only, forty a day;
--   6. the doors.
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
\i database/migrations/171_studio_documents.sql
\i database/migrations/173_studio_phase2_3.sql
\i database/migrations/173_studio_phase2_3.sql

begin;
update platform_settings set value = 'true' where key = 'events_public';
insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('17317317-0000-0000-0000-000000000001', '+22617310001', 'awa173@example.com', '{"full_name": "Awa"}', now()),
    ('17317317-0000-0000-0000-000000000002', '+22617310002', 'bob173@example.com', '{"full_name": "Bob"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan) values
    ('17317317-1111-0000-0000-000000000001', 'Awa Événements 173', 'awa-evenements-173', 'events', 'XOF', 'pro'),
    ('17317317-1111-0000-0000-000000000002', 'Bob Fêtes 173', 'bob-fetes-173', 'events', 'XOF', 'free');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('17317317-0000-0000-0000-000000000001', '17317317-1111-0000-0000-000000000001', 'owner', 'org', '17317317-1111-0000-0000-000000000001', 'full'),
    ('17317317-0000-0000-0000-000000000002', '17317317-1111-0000-0000-000000000002', 'owner', 'org', '17317317-1111-0000-0000-000000000002', 'full');

create temp table t173 (k text primary key, v text) on commit drop;
grant select, insert, update on t173 to authenticated, anon;

-- three cards (two of Awa's, one of Bob's), a picture each
do $$
declare r events; v_key text; i int;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '17317317-0000-0000-0000-000000000001', true);
    r := event_create('17317317-1111-0000-0000-000000000001', 'Mariage A', 'mariage', 'come', '2027-04-17 10:00+00', 'Tanghin', null);
    insert into t173 values ('a1', r.slug), ('a1e', r.edit_token), ('a1id', r.id::text);
    r := event_create('17317317-1111-0000-0000-000000000001', 'Baptême A', 'bapteme', 'come', null, null, null);
    insert into t173 values ('a2', r.slug), ('a2e', r.edit_token), ('a2id', r.id::text);
    perform set_config('request.jwt.claim.sub', '17317317-0000-0000-0000-000000000002', true);
    r := event_create('17317317-1111-0000-0000-000000000002', 'Fête B', 'anniversaire', 'come', null, null, null);
    insert into t173 values ('b1', r.slug), ('b1e', r.edit_token), ('b1id', r.id::text);
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    set local role anon;
    foreach v_key in array array['a1', 'a2', 'b1'] loop
        i := 0;
        insert into t173 values ('pic_' || v_key,
            event_picture_slot((select v from t173 where k = v_key), (select v from t173 where k = v_key || 'e'), 'jpg'));
        perform event_picture_done((select v from t173 where k = 'pic_' || v_key), (select v from t173 where k = v_key || 'e'), 1000);
    end loop;
    reset role;
end $$;

-- 1. the business's library
do $$
declare
    a1 text := (select v from t173 where k = 'a1'); a1e text := (select v from t173 where k = 'a1e');
    doc jsonb; j jsonb; v_err text;
begin
    set local role anon;
    doc := jsonb_build_object('v', 2, 'theme', '{}'::jsonb, 'blocks', jsonb_build_array(
        jsonb_build_object('id', 'b1', 'type', 'photo', 'props', jsonb_build_object('photo', jsonb_build_object('key', (select v from t173 where k = 'pic_a2'))))));
    perform event_doc_save(a1, a1e, doc);
    begin
        perform event_doc_save(a1, a1e, jsonb_build_object('v', 2, 'blocks', jsonb_build_array(
            jsonb_build_object('id', 'b1', 'type', 'photo', 'props', jsonb_build_object('photo', jsonb_build_object('key', (select v from t173 where k = 'pic_b1')))))));
        raise exception 'another business''s picture accepted';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err = 'Cette image n''est pas celle de la carte.', 'another business: ' || v_err;
    end;
    j := event_library(a1, a1e);
    assert jsonb_array_length(j) = 2, 'the library holds the business''s two pictures: ' || j::text;
    assert not exists (select 1 from jsonb_array_elements(j) x where x ->> 'key' = (select v from t173 where k = 'pic_b1')), 'not Bob''s';
    assert exists (select 1 from jsonb_array_elements(j) x where x ->> 'key' = (select v from t173 where k = 'pic_a1') and (x ->> 'mine')::boolean), 'its own marked';
    assert exists (select 1 from jsonb_array_elements(j) x where x ->> 'title' = 'Baptême A'), 'the other card named';
    begin
        perform event_library(a1, 'wrongwrongwrongwrongwron');
        raise exception 'library without the key';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Cette carte ne peut pas être modifiée%', 'no key: ' || v_err;
    end;
    reset role;
    raise notice 'PASS: the business''s pictures are its cards'', the others refused; the library lists them';
end $$;

-- 2. Premium scenes
do $$
declare
    a1 text := (select v from t173 where k = 'a1'); a1e text := (select v from t173 where k = 'a1e');
    b1 text := (select v from t173 where k = 'b1'); b1e text := (select v from t173 where k = 'b1e');
    lx jsonb := jsonb_build_object('v', 2, 'theme', jsonb_build_object('scene', 'lx-lotus'), 'blocks', jsonb_build_array(
        jsonb_build_object('id', 'c1', 'type', 'cover', 'style', jsonb_build_object('bg', 'scene', 'scene', 'lx-lotus'))));
    free2d jsonb := jsonb_build_object('v', 2, 'theme', jsonb_build_object('scene', 'confetti'), 'blocks', jsonb_build_array(
        jsonb_build_object('id', 'c1', 'type', 'cover', 'style', jsonb_build_object('bg', 'scene', 'scene', 'confetti'))));
    v_err text;
begin
    set local role anon;
    perform event_doc_save(b1, b1e, free2d);
    begin
        perform event_doc_save(b1, b1e, lx);
        raise exception 'a Premium scene on a free plan';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Ce décor animé est Premium%', 'free plan: ' || v_err;
    end;
    perform event_doc_save(a1, a1e, lx);
    assert (event_public(a1, null, a1e) ->> 'pro')::boolean, 'the editor of a Pro business: pro';
    assert (event_public(b1, null, b1e) ->> 'pro')::boolean is false, 'the editor of a free business: not pro';
    reset role;
    update events set published = true where slug in (a1, b1);
    set local role anon;
    assert (event_public(a1) -> 'pro') = 'null'::jsonb, 'nothing to the guests';
    reset role;
    -- the plan lapses: the card keeps its scene, gets no new one
    update orgs set plan = 'free' where id = '17317317-1111-0000-0000-000000000001';
    set local role anon;
    perform event_doc_save(a1, a1e, jsonb_set(lx, '{blocks,0,props}', '{"names": "Awa & Paul"}'));
    begin
        perform event_doc_save(a1, a1e, jsonb_set(lx, '{blocks,0,style,scene}', '"lx-aurore"'));
        raise exception 'a new Premium scene after the lapse';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Ce décor animé est Premium%', 'lapsed: ' || v_err;
    end;
    reset role;
    update orgs set plan = 'pro' where id = '17317317-1111-0000-0000-000000000001';
    raise notice 'PASS: Premium scenes are Pro''s, kept after a lapse; « pro » to the editor only';
end $$;

-- 3. the answers: questions and the closing day
do $$
declare
    b1 text := (select v from t173 where k = 'b1'); b1e text := (select v from t173 where k = 'b1e');
    doc jsonb; v_err text; v_id uuid;
begin
    set local role anon;
    doc := jsonb_build_object('v', 2, 'blocks', jsonb_build_array(
        jsonb_build_object('id', 'r1', 'type', 'rsvp', 'props', jsonb_build_object(
            'questions', jsonb_build_array(jsonb_build_object('q', 'Plat préféré ?')),
            'closes', to_char(current_date + 10, 'YYYY-MM-DD')))));
    perform event_doc_save(b1, b1e, doc);
    assert (event_public(b1) ->> 'rsvp_closes')::date = current_date + 10, 'the closing day told';
    v_id := event_rsvp(b1, null, 'Fati', 2, 'oui', null, '{"answers": ["Riz gras"]}');
    reset role;
    assert (select extra -> 'answers' ->> 0 from event_rsvps where id = v_id) = 'Riz gras', 'the answer kept';
    set local role anon;
    begin
        perform event_rsvp(b1, null, 'Moussa', 1, 'oui', null, '{"answers": ["a", "b", "c", "d"]}');
        raise exception 'four answers';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Trois réponses au plus%', 'four: ' || v_err;
    end;
    begin
        perform event_rsvp(b1, null, 'Moussa', 1, 'oui', null, jsonb_build_object('answers', jsonb_build_array(repeat('x', 301))));
        raise exception 'a long answer';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Trois réponses au plus%', 'long: ' || v_err;
    end;
    perform event_doc_save(b1, b1e, jsonb_set(doc, '{blocks,0,props,closes}', to_jsonb(to_char(current_date - 2, 'YYYY-MM-DD'))));
    begin
        perform event_rsvp(b1, null, 'Moussa', 1, 'oui', null, '{}');
        raise exception 'answered after the closing day';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Les réponses sont closes depuis le%', 'closed: ' || v_err;
    end;
    -- a hidden « Réponse » block closes nothing
    perform event_doc_save(b1, b1e, jsonb_set(jsonb_set(doc, '{blocks,0,props,closes}', to_jsonb(to_char(current_date - 2, 'YYYY-MM-DD'))), '{blocks,0,hidden}', 'true'));
    perform event_rsvp(b1, null, 'Moussa', 1, 'non', null, '{}');
    reset role;
    raise notice 'PASS: questions answered (three, 300 characters), the closing day held and told';
end $$;

-- 4. views and shares
do $$
declare
    a1 text := (select v from t173 where k = 'a1'); a2 text := (select v from t173 where k = 'a2');
    a1id uuid := (select v from t173 where k = 'a1id')::uuid; j jsonb;
begin
    set local role anon;
    perform event_count(a1, 'view'); perform event_count(a1, 'view'); perform event_count(a1, 'share');
    perform event_count(a1, 'nonsense'); perform event_count(a2, 'view');   -- a2: not published
    reset role;
    assert (select views from event_views where event_id = a1id) = 2, 'two views';
    assert (select shares from event_views where event_id = a1id) = 1, 'one share';
    assert not exists (select 1 from event_views where event_id = (select v from t173 where k = 'a2id')::uuid), 'an unpublished card is not counted';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '17317317-0000-0000-0000-000000000001', true);
    j := event_stats(a1id);
    assert (j ->> 'views')::int = 2 and (j ->> 'shares')::int = 1 and jsonb_array_length(j -> 'days') = 1, 'the business sees: ' || j::text;
    perform set_config('request.jwt.claim.sub', '17317317-0000-0000-0000-000000000002', true);
    assert event_stats(a1id) is null, 'another business sees nothing';
    assert (select count(*) from event_views where event_id = a1id) = 0, 'nor the rows';
    j := event_stats((select v from t173 where k = 'b1id')::uuid);
    assert (j ->> 'oui')::int = 1 and (j ->> 'non')::int = 1 and (j ->> 'people')::int = 2, 'the answers counted: ' || j::text;
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    raise notice 'PASS: views and shares counted for published cards, read by the business only';
end $$;

-- 5. the assistant
do $$
declare
    a1 text := (select v from t173 where k = 'a1'); a1e text := (select v from t173 where k = 'a1e');
    b1 text := (select v from t173 where k = 'b1'); b1e text := (select v from t173 where k = 'b1e');
    j jsonb; v_err text; i int;
begin
    set local role anon;
    j := event_assist_use(b1, b1e);
    assert (j ->> 'pro')::boolean is false, 'a free business: no assistant';
    for i in 1..40 loop j := event_assist_use(a1, a1e); end loop;
    assert (j ->> 'left')::int = 0, 'forty used: ' || j::text;
    begin
        perform event_assist_use(a1, a1e);
        raise exception 'the forty-first';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'L''assistant a assez écrit%', 'forty-one: ' || v_err;
    end;
    reset role;
    raise notice 'PASS: the assistant is Pro''s, forty a day per card';
end $$;

-- 6. the doors
do $$ begin
    assert has_function_privilege('anon', 'event_library(text, text)', 'execute'), 'anon: library (the editor)';
    assert has_function_privilege('anon', 'event_count(text, text)', 'execute'), 'anon: count (the Worker)';
    assert has_function_privilege('anon', 'event_assist_use(text, text)', 'execute'), 'anon: assistant (the Worker)';
    assert not has_function_privilege('anon', 'event_stats(uuid)', 'execute'), 'anon: no stats';
    assert not has_function_privilege('anon', 'event_rsvp_closes(events)', 'execute'), 'the helper is nobody''s door';
    assert not has_function_privilege('authenticated', 'event_rsvp_closes(events)', 'execute'), 'nobody''s';
    assert has_function_privilege('authenticated', 'event_stats(uuid)', 'execute'), 'the business: stats';
    assert not has_table_privilege('anon', 'event_views', 'select'), 'views: not the street''s';
    assert not has_table_privilege('authenticated', 'event_views', 'insert'), 'views: written by the counter only';
    assert not has_table_privilege('anon', 'event_assist_uses', 'select') and not has_table_privilege('authenticated', 'event_assist_uses', 'select'), 'the allowance: nobody reads it';
    raise notice 'PASS: the doors';
end $$;

rollback;
