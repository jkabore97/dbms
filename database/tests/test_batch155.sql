-- ============================================================
-- test_batch155.sql — 155: Événementiel, piece 3 — the guests' album.
--
-- The claims:
--   1. installed twice, the same: a picture says whose it is and the
--      guest's name; a guest with the card's link gets a key (jpg, png,
--      webp only), none with a wrong link, none when the organiser
--      closed the album; the street may call the three album doors and
--      nothing else of 155;
--   2. nothing listed nor served before the bytes are in; confirmed only
--      with the card's link, then listed newest first with the name, and
--      served; a published card needs no link; the organiser's own limit
--      ignores the guests' pictures; three hundred guests' pictures at
--      most;
--   3. the business's admin removes a picture and it is gone from the
--      album and from the street; the employee removes nothing; the
--      street cannot call it nor read the table.
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
-- Supabase's default: a signed-in person may touch every table in public,
-- RLS deciding which rows (the earlier suites grant it too; alone, this
-- one needs it for event_create, which runs as the caller).
grant select, insert, update, delete on all tables in schema public to authenticated;
-- Installed twice, the same.
\i database/migrations/155_events_album.sql
\i database/migrations/156_events_published_open.sql
\i database/migrations/155_events_album.sql
\i database/migrations/156_events_published_open.sql

begin;

update platform_settings set value = 'true' where key = 'events_public';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('15515515-0000-0000-0000-000000000001', '+22615510001', 'awa155@example.com',    '{"full_name": "Awa Planner"}',  now()),
    ('15515515-0000-0000-0000-000000000002', '+22615510002', 'seller155@example.com', '{"full_name": "La vendeuse"}',  now());
insert into orgs (id, name, slug, profile, default_currency) values
    ('15515515-1111-0000-0000-000000000001', 'Awa Événements 155', 'awa-evenements-155', 'events', 'XOF');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('15515515-0000-0000-0000-000000000001', '15515515-1111-0000-0000-000000000001', 'owner',    'org', '15515515-1111-0000-0000-000000000001', 'full'),
    ('15515515-0000-0000-0000-000000000002', '15515515-1111-0000-0000-000000000001', 'employee', 'org', '15515515-1111-0000-0000-000000000001', 'full');

create temp table t155 (k text primary key, v text) on commit drop;
grant select, insert, update on t155 to authenticated, anon;

-- 1. the doors
do $$
declare
    r events;
    v_key text;
    v_msg text;
    f text;
begin
    assert (select count(*) from information_schema.columns
             where table_name = 'event_pictures' and column_name in ('source', 'guest')) = 2, 'whose, and the name';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15515515-0000-0000-0000-000000000001', true);
    r := event_create('15515515-1111-0000-0000-000000000001', 'Inès & Thomas', 'mariage', 'come', '2027-06-05 15:00+00', 'Villa Serena', null);
    insert into t155 values ('slug', r.slug), ('preview', r.preview_token), ('edit', r.edit_token), ('event', r.id::text);
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);

    set local role anon;
    begin v_key := event_album_slot((select v from t155 where k = 'slug'), 'ffffffffffffffffffffffff', 'jpg', 'Tanti Rose'); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Cette carte n''est pas ouverte.', 'a wrong link: ' || coalesce(v_msg, 'minted');
    begin v_key := event_album_slot((select v from t155 where k = 'slug'), null, 'jpg', 'Tanti Rose'); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Cette carte n''est pas ouverte.', 'unpublished, no link: ' || coalesce(v_msg, 'minted');
    begin v_key := event_album_slot((select v from t155 where k = 'slug'), (select v from t155 where k = 'preview'), 'gif', 'Tanti Rose'); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Photos uniquement (JPEG, PNG ou WebP).', 'a gif: ' || coalesce(v_msg, 'minted');
    reset role;

    update events set album_on = false where id = (select v from t155 where k = 'event')::uuid;
    set local role anon;
    begin v_key := event_album_slot((select v from t155 where k = 'slug'), (select v from t155 where k = 'preview'), 'jpg', 'Tanti Rose'); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'L''album est fermé pour cet événement.', 'album closed: ' || coalesce(v_msg, 'minted');
    reset role;
    update events set album_on = true where id = (select v from t155 where k = 'event')::uuid;

    set local role anon;
    v_key := event_album_slot((select v from t155 where k = 'slug'), (select v from t155 where k = 'preview'), 'JPG', '  Tanti Rose  ');
    assert v_key ~ ('^events/' || (select v from t155 where k = 'event') || '/[0-9a-f]{32}\.jpg$'), 'a key under the event: ' || v_key;
    insert into t155 values ('key', v_key);
    reset role;
    assert (select source = 'guest' and guest = 'Tanti Rose' and state = 'slot' from event_pictures where key = v_key), 'a guest''s slot, with the name trimmed';

    foreach f in array array['event_album_slot(text, text, text, text)', 'event_album_done(text, text, integer)', 'event_album(text, text)'] loop
        assert has_function_privilege('anon', f, 'execute'), 'the street may call ' || f;
        assert (select prosecdef from pg_proc where oid = to_regprocedure(f)), f || ' is SECURITY DEFINER';
    end loop;
    foreach f in array array['event_for_album(text, text)', 'event_picture_delete(text)'] loop
        assert not has_function_privilege('anon', f, 'execute'), 'the street cannot call ' || f;
        assert not has_function_privilege('public', f, 'execute'), 'PUBLIC cannot call ' || f;
    end loop;
    assert not (select prosecdef from pg_proc where oid = to_regprocedure('event_picture_delete(text)')), 'event_picture_delete runs as the caller';
end $$;

-- 2. the picture, confirmed, listed, served; the limits
do $$
declare
    v_slug text := (select v from t155 where k = 'slug');
    v_preview text := (select v from t155 where k = 'preview');
    v_edit text := (select v from t155 where k = 'edit');
    v_event uuid := (select v from t155 where k = 'event')::uuid;
    v_key text := (select v from t155 where k = 'key');
    v_key2 text;
    v_msg text;
    j jsonb;
begin
    set local role anon;
    j := event_album(v_slug, v_preview);
    assert j = '[]'::jsonb, 'nothing listed before the bytes are in: ' || coalesce(j::text, 'null');
    assert event_album(v_slug, null) is null, 'no link, unpublished: nothing to tell';
    assert not event_picture_allowed(v_key), 'nothing served before the bytes are in';
    begin perform event_album_done(v_key, 'ffffffffffffffffffffffff', 1000); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Cette carte n''est pas ouverte.', 'confirmed only with the card''s link: ' || coalesce(v_msg, 'done');
    assert event_album_done(v_key, v_preview, 123456), 'confirmed';
    assert event_picture_allowed(v_key), 'then served';
    begin perform event_album_done(v_key, v_preview, 1); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Envoi inconnu.', 'confirmed once: ' || coalesce(v_msg, 'again');
    j := event_album(v_slug, v_preview);
    assert jsonb_array_length(j) = 1 and j -> 0 ->> 'key' = v_key and j -> 0 ->> 'guest' = 'Tanti Rose', 'listed with the name: ' || j::text;
    -- A second one, newest first, no name.
    v_key2 := event_album_slot(v_slug, v_preview, 'png', '');
    assert event_album_done(v_key2, v_preview, 10), 'the second confirmed';
    j := event_album(v_slug, v_preview);
    assert jsonb_array_length(j) = 2 and j -> 0 ->> 'key' = v_key2 and (j -> 0 -> 'guest') = 'null'::jsonb, 'newest first, no name: ' || j::text;
    -- The organiser's door does not confirm a guest's slot, nor the album a card's.
    v_key2 := event_album_slot(v_slug, v_preview, 'webp', 'Papa Jo');
    begin perform event_picture_done(v_key2, v_edit, 1); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Envoi inconnu.', 'a guest''s slot is not the organiser''s: ' || coalesce(v_msg, 'done');
    v_key2 := event_picture_slot(v_slug, v_edit, 'jpg');
    begin perform event_album_done(v_key2, v_preview, 1); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Envoi inconnu.', 'the organiser''s slot is not a guest''s: ' || coalesce(v_msg, 'done');
    reset role;

    -- Published: the short link alone opens the album.
    update events set published = true where id = v_event;
    set local role anon;
    v_key2 := event_album_slot(v_slug, null, 'jpg', 'Cousin Malik');
    assert v_key2 is not null, 'a published card takes a guest''s picture without a link';
    assert event_album_done(v_key2, null, 5), 'and confirms it';
    assert jsonb_array_length(event_album(v_slug, null)) = 3, 'and lists the album';
    reset role;

    -- The organiser's own limit (eighty) ignores the guests' pictures.
    insert into event_pictures (key, event_id, state, source, guest, done_at)
    select 'events/' || v_event || '/' || lpad(to_hex(g), 32, '0') || '.jpg', v_event, 'stored', 'guest', 'Invité ' || g, now()
      from generate_series(1, 100) g;
    set local role anon;
    v_key2 := event_picture_slot(v_slug, v_edit, 'jpg');
    assert v_key2 is not null, 'the organiser still has room with a hundred guests'' pictures in';
    reset role;
    -- Three hundred guests' pictures at most.
    insert into event_pictures (key, event_id, state, source, done_at)
    select 'events/' || v_event || '/' || lpad(to_hex(g), 32, '0') || '.png', v_event, 'stored', 'guest', now()
      from generate_series(101, 400) g
     where (select count(*) from event_pictures where event_id = v_event and source = 'guest') + (g - 100) <= 300;
    assert (select count(*) from event_pictures where event_id = v_event and source = 'guest') = 300, 'three hundred in';
    set local role anon;
    begin v_key2 := event_album_slot(v_slug, null, 'jpg', 'Encore'); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg like 'L''album est plein%', 'three hundred at most: ' || coalesce(v_msg, 'minted');
    -- Listed: the stored ones — three hundred rows, less Papa Jo's slot
    -- that never got its bytes.
    assert jsonb_array_length(event_album(v_slug, null)) = 299, 'the album lists every stored picture';
    reset role;
end $$;

-- 3. the organiser removes
do $$
declare
    v_slug text := (select v from t155 where k = 'slug');
    v_key text := (select v from t155 where k = 'key');
    v_event uuid := (select v from t155 where k = 'event')::uuid;
    n int;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15515515-0000-0000-0000-000000000002', true);
    assert not event_picture_delete(v_key), 'the employee removes nothing';
    perform set_config('request.jwt.claim.sub', '15515515-0000-0000-0000-000000000001', true);
    select count(*) into n from event_pictures where event_id = v_event and source = 'guest' and state = 'stored';
    assert n = 299, 'the owner reads the album''s stored rows: ' || n;
    assert event_picture_delete(v_key), 'the owner removes one';
    assert not event_picture_delete(v_key), 'once';
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    set local role anon;
    assert not event_picture_allowed(v_key), 'gone from the street';
    assert not exists (select 1 from jsonb_array_elements(event_album(v_slug, null)) x where x ->> 'key' = v_key), 'gone from the album';
    reset role;
    assert not has_table_privilege('anon', 'event_pictures', 'select'), 'the street cannot read the table';
    raise notice 'PASS: 155 — the guests'' album: a picture with the card''s link, named, listed and served once its bytes are in; removed by the business''s admins';
end $$;

rollback;
