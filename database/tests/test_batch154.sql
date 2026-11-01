-- ============================================================
-- test_batch154.sql — 154: Événementiel, piece 2 — the card edited from
-- Marakaj: the edit token, the draft saved, the organiser's pictures.
--
-- The claims:
--   1. installed twice, the same: every event carries a 24-character edit
--      token beside its preview token, minted by event_create, never in
--      event_public's answer; with it the unpublished card opens and says
--      « editor », with the preview token it does not say so, with a wrong
--      one nothing opens; the editor's doors are the street's, the helpers
--      are not;
--   2. event_content_save: refused without the token; the page's draft kept
--      as it is (type, texts with a few inline tags, the animated page's
--      fields); each refusal in French — an unknown field, a text too long,
--      a colour unknown, a picture as a data URL, a picture not the card's,
--      a framing malformed; the street reads the content back;
--   3. the pictures: a key minted under the event (jpg, png, webp only;
--      wrong token refused), nothing served before the bytes are in,
--      confirmed only with the token, then served and allowed in the
--      content; eighty at most; an unknown confirmation refused; the
--      business's admins read the rows, the street cannot;
--   4. a guest's answer still comes through the preview link (the
--      two-argument event_visible).
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
-- Earlier suites re-apply older migrations over these functions: 154 again,
-- twice — installed twice, the same.
\i database/migrations/154_events_editor.sql
\i database/migrations/155_events_album.sql
\i database/migrations/156_events_published_open.sql
\i database/migrations/154_events_editor.sql
\i database/migrations/155_events_album.sql
\i database/migrations/156_events_published_open.sql

begin;

update platform_settings set value = 'true' where key = 'events_public';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('15415415-0000-0000-0000-000000000001', '+22615410001', 'awa154@example.com',    '{"full_name": "Awa Planner"}',  now()),
    ('15415415-0000-0000-0000-000000000002', '+22615410002', 'seller154@example.com', '{"full_name": "La vendeuse"}',  now());
-- Pro: their cards are made with Premium designs (157 holds that door).
insert into orgs (id, name, slug, profile, default_currency, plan) values
    ('15415415-1111-0000-0000-000000000001', 'Awa Événements 154', 'awa-evenements-154', 'events', 'XOF', 'pro'),
    ('15415415-1111-0000-0000-000000000002', 'Autre Événementiel 154', 'autre-154', 'events', 'XOF', 'pro');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('15415415-0000-0000-0000-000000000001', '15415415-1111-0000-0000-000000000001', 'owner',    'org', '15415415-1111-0000-0000-000000000001', 'full'),
    ('15415415-0000-0000-0000-000000000002', '15415415-1111-0000-0000-000000000001', 'employee', 'org', '15415415-1111-0000-0000-000000000001', 'full'),
    ('15415415-0000-0000-0000-000000000001', '15415415-1111-0000-0000-000000000002', 'owner',    'org', '15415415-1111-0000-0000-000000000002', 'full');

create temp table t154 (k text primary key, v text) on commit drop;
grant select, insert, update on t154 to authenticated, anon;

-- 1. the token
do $$
declare
    r events;
    j jsonb;
    f text;
begin
    assert (select count(*) from events where edit_token is null or length(edit_token) <> 24) = 0, 'every event has its edit token';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15415415-0000-0000-0000-000000000001', true);
    r := event_create('15415415-1111-0000-0000-000000000001', 'Inès & Thomas', 'mariage', 'come', '2027-06-05 15:00+00', 'Villa Serena', null);
    assert r.edit_token ~ '^[0-9a-f]{24}$' and r.preview_token ~ '^[0-9a-f]{24}$' and r.edit_token <> r.preview_token,
        'two tokens, minted, distinct';
    insert into t154 values ('slug', r.slug), ('preview', r.preview_token), ('edit', r.edit_token), ('event', r.id::text);
    r := event_create('15415415-1111-0000-0000-000000000002', 'Gala des Anciens', 'gala', 'anime_lotus_p', null, null, null);
    insert into t154 values ('slug2', r.slug), ('edit2', r.edit_token), ('event2', r.id::text);
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);

    set local role anon;
    j := event_public((select v from t154 where k = 'slug'), null, (select v from t154 where k = 'edit'));
    assert j is not null and (j ->> 'editor')::boolean and not (j ->> 'preview')::boolean, 'the edit token opens the card, as editor: ' || coalesce(j::text, 'nothing');
    assert j::text not like '%' || (select v from t154 where k = 'edit') || '%', 'the edit token is never in the answer';
    assert j::text not like '%' || (select v from t154 where k = 'preview') || '%', 'nor the preview token';
    j := event_public((select v from t154 where k = 'slug'), (select v from t154 where k = 'preview'));
    assert j is not null and not (j ->> 'editor')::boolean and (j ->> 'preview')::boolean, 'the preview token opens it, not as editor';
    assert event_public((select v from t154 where k = 'slug'), null, 'ffffffffffffffffffffffff') is null, 'a wrong edit token opens nothing';
    assert event_public((select v from t154 where k = 'slug')) is null, 'unpublished: nothing for the street';
    reset role;

    foreach f in array array['event_content_save(text, text, jsonb)', 'event_picture_slot(text, text, text)',
                             'event_picture_done(text, text, integer)', 'event_picture_allowed(text)',
                             'event_public(text, text, text)'] loop
        assert has_function_privilege('anon', f, 'execute'), 'the street may call ' || f;
        assert (select prosecdef from pg_proc where oid = to_regprocedure(f)), f || ' is SECURITY DEFINER';
    end loop;
    foreach f in array array['event_for_edit(text, text)', 'event_hex24()', 'event_visible(events, text, text)'] loop
        assert not has_function_privilege('anon', f, 'execute'), 'the street cannot call ' || f;
        assert not has_function_privilege('public', f, 'execute'), 'PUBLIC cannot call ' || f;
    end loop;
    assert to_regprocedure('event_public(text, text)') is null, 'the two-argument event_public is gone';
end $$;

-- 2. the draft saved
do $$
declare
    v_slug text := (select v from t154 where k = 'slug');
    v_edit text := (select v from t154 where k = 'edit');
    v_msg text;
    j jsonb;
begin
    set local role anon;
    begin
        perform event_content_save(v_slug, null, '{"type": "mariage"}'::jsonb);
        v_msg := null;
    exception when others then v_msg := sqlerrm;
    end;
    assert v_msg = 'Cette carte ne peut pas être modifiée d''ici.', 'no token: ' || coalesce(v_msg, 'saved');
    begin
        perform event_content_save(v_slug, 'ffffffffffffffffffffffff', '{"type": "mariage"}'::jsonb);
        v_msg := null;
    exception when others then v_msg := sqlerrm;
    end;
    assert v_msg = 'Cette carte ne peut pas être modifiée d''ici.', 'a wrong token: ' || coalesce(v_msg, 'saved');

    assert event_content_save(v_slug, v_edit,
        '{"type": "anniversaire", "t:names": "Inès &amp; Thomas", "t:word": "Venez <b>nombreux</b>", "t:prog-intro": "Dès 14 h",
          "a": "Inès", "b": "Thomas", "date": "2027-06-05", "time": "15:00", "place": "Villa Serena", "custom": "", "pal": 2, "font": "classique"}'::jsonb),
        'the draft kept';
    j := event_public(v_slug, null, v_edit);
    assert j -> 'content' ->> 't:word' = 'Venez <b>nombreux</b>' and (j -> 'content' ->> 'pal')::int = 2 and j -> 'content' ->> 'type' = 'anniversaire',
        'read back as saved: ' || (j -> 'content')::text;

    begin perform event_content_save(v_slug, v_edit, '{"x": 1}'::jsonb); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Champ inconnu : x', 'an unknown field: ' || coalesce(v_msg, 'saved');
    begin perform event_content_save(v_slug, v_edit, jsonb_build_object('t:names', repeat('a', 4001))); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg like 'Un texte de 4 000 caractères au plus%', 'a text too long: ' || coalesce(v_msg, 'saved');
    begin perform event_content_save(v_slug, v_edit, '{"pal": 12}'::jsonb); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Couleur inconnue.', 'a colour unknown: ' || coalesce(v_msg, 'saved');
    begin perform event_content_save(v_slug, v_edit, '{"p:hero": {"src": "data:image/jpeg;base64,AAAA"}}'::jsonb); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg like 'Image mal formée%', 'a data URL: ' || coalesce(v_msg, 'saved');
    begin perform event_content_save(v_slug, v_edit, '{"p:hero": {"key": "events/00000000-0000-0000-0000-000000000000/00000000000000000000000000000000.jpg"}}'::jsonb); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Cette image n''est pas celle de la carte.', 'a picture not the card''s: ' || coalesce(v_msg, 'saved');
    begin perform event_content_save(v_slug, v_edit, '{"p:hero": {"pos": "left top"}}'::jsonb); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Cadrage mal formé.', 'a framing malformed: ' || coalesce(v_msg, 'saved');
    begin perform event_content_save(v_slug, v_edit, '[1, 2]'::jsonb); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Contenu mal formé.', 'not an object: ' || coalesce(v_msg, 'saved');
    assert event_content_save(v_slug, v_edit, '{"p:hero": {"pos": "50% 30.5%"}}'::jsonb), 'a framing alone, kept';
    reset role;
end $$;

-- 3. the pictures
do $$
declare
    v_slug text := (select v from t154 where k = 'slug');
    v_edit text := (select v from t154 where k = 'edit');
    v_edit2 text := (select v from t154 where k = 'edit2');
    v_event uuid := (select v from t154 where k = 'event')::uuid;
    v_key text;
    v_msg text;
    i int;
begin
    set local role anon;
    begin v_key := event_picture_slot(v_slug, 'ffffffffffffffffffffffff', 'jpg'); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Cette carte ne peut pas être modifiée d''ici.', 'a slot with a wrong token: ' || coalesce(v_msg, 'minted');
    begin v_key := event_picture_slot(v_slug, v_edit, 'gif'); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Photos uniquement (JPEG, PNG ou WebP).', 'a gif: ' || coalesce(v_msg, 'minted');

    v_key := event_picture_slot(v_slug, v_edit, 'JPG');
    assert v_key ~ ('^events/' || v_event || '/[0-9a-f]{32}\.jpg$'), 'a key under the event: ' || v_key;
    assert not event_picture_allowed(v_key), 'nothing served before the bytes are in';
    begin perform event_picture_done(v_key, v_edit2, 1000); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Cette carte ne peut pas être modifiée d''ici.', 'confirmed only with its card''s token: ' || coalesce(v_msg, 'done');
    assert event_picture_done(v_key, v_edit, 123456), 'confirmed';
    assert event_picture_allowed(v_key), 'then served';
    begin perform event_picture_done(v_key, v_edit, 1); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Envoi inconnu.', 'confirmed once: ' || coalesce(v_msg, 'again');
    begin perform event_picture_done('events/' || v_event || '/' || repeat('0', 32) || '.jpg', v_edit, 1); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Envoi inconnu.', 'an unknown key: ' || coalesce(v_msg, 'done');
    assert not event_picture_allowed('events/' || v_event || '/' || repeat('0', 32) || '.jpg'), 'an unknown key is not served';
    -- In the content now, as the card's own picture.
    assert event_content_save(v_slug, v_edit, jsonb_build_object('p:hero', jsonb_build_object('key', v_key, 'pos', '50% 40%'))), 'the picture in the content';
    -- Another card's token cannot claim it.
    begin perform event_content_save((select v from t154 where k = 'slug2'), v_edit2, jsonb_build_object('p:hero', jsonb_build_object('key', v_key))); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Cette image n''est pas celle de la carte.', 'another card: ' || coalesce(v_msg, 'saved');
    -- Eighty at most.
    for i in 1..79 loop
        perform event_picture_slot(v_slug, v_edit, 'png');
    end loop;
    begin v_key := event_picture_slot(v_slug, v_edit, 'webp'); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg like 'Trop d''images pour cette carte%', 'eighty at most: ' || coalesce(v_msg, 'minted');
    reset role;

    -- The business's admin reads the rows, the employee none, the street cannot.
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15415415-0000-0000-0000-000000000001', true);
    assert (select count(*) from event_pictures where event_id = v_event) = 80, 'the owner reads the pictures';
    perform set_config('request.jwt.claim.sub', '15415415-0000-0000-0000-000000000002', true);
    assert (select count(*) from event_pictures) = 0, 'the employee reads none';
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    assert not has_table_privilege('anon', 'event_pictures', 'select'), 'the street cannot read the table';
end $$;

-- 4. a guest's answer through the preview link, as before
do $$
declare
    v_id uuid;
begin
    set local role anon;
    v_id := event_rsvp((select v from t154 where k = 'slug'), (select v from t154 where k = 'preview'), 'Tanti Rose', 2, 'oui', null, '{}');
    assert v_id is not null, 'the answer taken';
    reset role;
    raise notice 'PASS: 154 — the card is edited with its edit token: the draft checked and kept, the pictures minted, confirmed and served by key, the tokens never told';
end $$;

rollback;
