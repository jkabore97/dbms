-- ============================================================
-- test_batch171.sql — 171: Studio, a card becomes a document.
--
-- The claims:
--   1. installed twice, the same; a card without a document is untouched
--      (event_public answers doc null and the content as before);
--   2. saved with the edit token only: the document kept, read back by the
--      street (event_public) — whole by the editor, without its hidden
--      blocks by the guests —, a version written;
--   3. each refusal, in French: not an object, a version unknown, a field
--      unknown (top, theme, block), a colour malformed, a font malformed,
--      41 blocks, a block type unknown, two blocks with one id, a key
--      malformed inside a block, nesting too deep, a text too long, a list
--      too long, a link in javascript:, a picture of another card, a
--      picture not stored, a stock name malformed, a colour in a block
--      malformed, a document too heavy;
--   4. versions: the last twenty kept, newest first; one version's
--      document read back; restored (itself a new version, « restore »);
--      another card's version refused;
--   5. cleared: back to the model's card, the versions kept;
--   6. the doors: anon may call the five; the checks are nobody's door;
--      the versions' table has row security, no policy and no grant;
--   7. read straight, the versions answer nothing — to anon, to the
--      business's owner signed in.
-- Wrapped in one transaction rolled back.
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
\i database/migrations/171_studio_documents.sql
\i database/migrations/171_studio_documents.sql

begin;

update platform_settings set value = 'true' where key = 'events_public';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('17117117-0000-0000-0000-000000000001', '+22617010001', 'awa171@example.com', '{"full_name": "Awa Studio"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan) values
    ('17117117-1111-0000-0000-000000000001', 'Awa Événements 171', 'awa-evenements-171', 'events', 'XOF', 'pro');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('17117117-0000-0000-0000-000000000001', '17117117-1111-0000-0000-000000000001', 'owner', 'org', '17117117-1111-0000-0000-000000000001', 'full');

create temp table t171 (k text primary key, v text) on commit drop;
grant select, insert, update on t171 to authenticated, anon;

-- 1. two cards, two pictures
do $$
declare
    r events;
    v_key text;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '17117117-0000-0000-0000-000000000001', true);
    r := event_create('17117117-1111-0000-0000-000000000001', 'Salimata & Boukary', 'dot', 'dot', '2027-04-17 10:00+00', 'Tanghin', null);
    insert into t171 values ('slug', r.slug), ('edit', r.edit_token), ('preview', r.preview_token), ('event', r.id::text);
    r := event_create('17117117-1111-0000-0000-000000000001', 'Autre carte', 'mariage', 'come', null, null, null);
    insert into t171 values ('slug2', r.slug), ('edit2', r.edit_token), ('event2', r.id::text);
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    set local role anon;
    v_key := event_picture_slot((select v from t171 where k = 'slug'), (select v from t171 where k = 'edit'), 'jpg');
    perform event_picture_done(v_key, (select v from t171 where k = 'edit'), 1000);
    insert into t171 values ('pic', v_key);
    v_key := event_picture_slot((select v from t171 where k = 'slug'), (select v from t171 where k = 'edit'), 'jpg');
    insert into t171 values ('slot', v_key);   -- minted, never confirmed
    v_key := event_picture_slot((select v from t171 where k = 'slug2'), (select v from t171 where k = 'edit2'), 'png');
    perform event_picture_done(v_key, (select v from t171 where k = 'edit2'), 1000);
    insert into t171 values ('pic2', v_key);
    reset role;
    assert (event_public((select v from t171 where k = 'slug'), (select v from t171 where k = 'preview')) -> 'doc') = 'null'::jsonb,
        'a card without a document answers doc null';
    raise notice 'PASS: two cards made; a card without a document is untouched';
end $$;

-- 2. saved
create temp table d171 (k text primary key, doc jsonb) on commit drop;
grant select on d171 to anon, authenticated;
insert into d171 values ('ok', jsonb_build_object(
    'v', 2,
    'theme', jsonb_build_object('colors', jsonb_build_object('back', '#0f6b4f', 'paper', '#FBF5E8', 'ink', '#1f2a23', 'accent', '#c2185b'),
                                'fonts', jsonb_build_object('display', 'yeseva', 'body', 'mulish', 'script', 'great-vibes'),
                                'motif', jsonb_build_object('id', 'wax-emerald', 'density', 2), 'motion', 'douce', 'corners', 'doux', 'preset', 'dot'),
    'blocks', jsonb_build_array(
        jsonb_build_object('id', 'b1', 'type', 'cover', 'variant', 'framed', 'props', jsonb_build_object(
            'kicker', 'Cérémonie de dot', 'names', 'Salimata & Boukary', 'photo', jsonb_build_object('key', (select v from t171 where k = 'pic'), 'pos', jsonb_build_array(50, 40), 'zoom', 1.1))),
        jsonb_build_object('id', 'b2', 'type', 'programme', 'props', jsonb_build_object('title', 'Le déroulement',
            'items', jsonb_build_array(jsonb_build_object('time', null, 'title', 'Accueil', 'detail', 'Les familles se saluent')))),
        jsonb_build_object('id', 'b3', 'type', 'text', 'hidden', false, 'props', jsonb_build_object('title', 'Un mot', 'body', 'Bienvenue <b>à tous</b>'),
            'style', jsonb_build_object('bg', 'accent', 'align', 'center', 'size', 'L', 'color', '#aabbcc')),
        jsonb_build_object('id', 'b4', 'type', 'gallery', 'props', jsonb_build_object('photos', jsonb_build_array(jsonb_build_object('stock', 'wed-lake')))),
        jsonb_build_object('id', 'b5', 'type', 'place', 'props', jsonb_build_object('name', 'Tanghin', 'href', 'https://www.google.com/maps/search/?api=1&query=Tanghin')),
        jsonb_build_object('id', 'b6', 'type', 'contribution', 'props', jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('label', 'Orange Money', 'value', '70 00 00 00', 'href', 'tel:+22670000000')))),
        jsonb_build_object('id', 'b7', 'type', 'text', 'hidden', true, 'props', jsonb_build_object('title', 'Brouillon', 'body', 'Wave : 76 00 00 00 (pas encore sûr)'))),
    'meta', jsonb_build_object('from', 'dot', 'converted', true)));

do $$
declare
    j jsonb;
    s text := (select v from t171 where k = 'slug');
    ed text := (select v from t171 where k = 'edit');
    d jsonb := (select doc from d171 where k = 'ok');
    v_msg text;
begin
    set local role anon;
    begin perform event_doc_save(s, 'ffffffffffffffffffffffff', d); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg like 'Cette carte ne peut pas être modifiée%', 'a wrong token: ' || coalesce(v_msg, 'accepted');
    begin perform event_doc_save(s, (select v from t171 where k = 'preview'), d); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg like 'Cette carte ne peut pas être modifiée%', 'the preview token is not the edit token';
    j := event_doc_save(s, ed, d);
    assert j ? 'version' and j ? 'saved_at', 'saved: ' || j::text;
    j := event_public(s, null, ed);
    assert (j -> 'doc') = d and (j ->> 'doc_saved_at') is not null, 'the editor reads the document back, whole';
    j := event_public(s, (select v from t171 where k = 'preview'));
    assert jsonb_array_length(j #> '{doc,blocks}') = 6 and (j #>> '{doc,blocks,5,id}') = 'b6' and (j #>> '{doc,blocks,0,id}') = 'b1'
        and position('76 00 00 00' in (j -> 'doc')::text) = 0 and (j #>> '{doc,theme,preset}') = 'dot',
        'the guests read it without the hidden block, the rest in order: ' || (j -> 'doc')::text;
    reset role;
    assert (select count(*) from event_doc_versions where event_id = (select v from t171 where k = 'event')::uuid) = 1, 'one version';
    raise notice 'PASS: saved with the edit token only, read back whole by the editor, without its hidden block by the guests, one version';
end $$;

-- 3. refusals, each in French
do $$
declare
    s text := (select v from t171 where k = 'slug');
    ed text := (select v from t171 where k = 'edit');
    d jsonb := (select doc from d171 where k = 'ok');
    blk jsonb := '{"id":"x1","type":"text","props":{"title":"t"}}';
    many jsonb := '[]';
    deep jsonb := '"bas"';
    i int;
    c record;
    v_msg text;
begin
    for i in 1..41 loop many := many || jsonb_build_object('id', 'b' || i, 'type', 'spacer'); end loop;
    for i in 1..7 loop deep := jsonb_build_object('n', deep); end loop;
    for c in select * from (values
        ('not an object',      '[1,2]'::jsonb,                                                     'La carte est mal formée.'),
        ('version',            jsonb_set(d, '{v}', '3'),                                           'Version de carte inconnue.'),
        ('top field',          d || '{"script":"x"}',                                              'Champ inconnu : script'),
        ('theme field',        jsonb_set(d, '{theme,css}', '"body{}"'),                            'Thème : champ inconnu (css).'),
        ('theme colour',       jsonb_set(d, '{theme,colors,ink}', '"red"'),                        'Une couleur s''écrit #rrggbb.'),
        ('theme font',         jsonb_set(d, '{theme,fonts,body}', '"Comic Sans"'),                 'Les polices sont mal formées.'),
        ('41 blocks',          jsonb_set(d, '{blocks}', many),                                     'Quarante blocs au plus par carte.'),
        ('block type',         jsonb_set(d, '{blocks,0,type}', '"iframe"'),                        'Bloc 1 : type inconnu (iframe).'),
        ('block field',        jsonb_set(d, '{blocks,0,onclick}', '"x"'),                          'Bloc 1 : champ inconnu (onclick).'),
        ('same id',            jsonb_set(d, '{blocks,1,id}', '"b1"'),                              'Deux blocs portent le même identifiant (b1).'),
        ('key in props',       jsonb_set(d, '{blocks,0,props}', '{"on-click":"x"}'),               'Bloc 1 : champ mal nommé (on-click).'),
        ('too deep',           jsonb_set(d, '{blocks,0,props}', jsonb_build_object('a', deep)),    'Bloc 1 : trop de niveaux imbriqués.'),
        ('text too long',      jsonb_set(d, '{blocks,2,props,body}', to_jsonb(repeat('a', 4001))), 'Bloc 3 : un texte de 4 000 caractères au plus.'),
        ('list too long',      jsonb_set(d, '{blocks,1,props,items}', (select jsonb_agg(g) from generate_series(1, 61) g)), 'Bloc 2 : liste trop longue.'),
        ('javascript link',    jsonb_set(d, '{blocks,4,props,href}', '"javascript:alert(1)"'),     'Un lien doit commencer par https://, tel: ou mailto:.'),
        ('another card pic',   jsonb_set(d, '{blocks,0,props,photo,key}', to_jsonb((select v from t171 where k = 'pic2'))), 'Cette image n''est pas celle de la carte.'),
        ('a pic not stored',   jsonb_set(d, '{blocks,0,props,photo,key}', to_jsonb((select v from t171 where k = 'slot'))), 'Cette image n''est pas celle de la carte.'),
        ('stock name',         jsonb_set(d, '{blocks,3,props,photos,0,stock}', '"../secret"'),     'Photo de la banque inconnue.'),
        ('block colour',       jsonb_set(d, '{blocks,2,style,color}', '"url(x)"'),                 'Une couleur s''écrit #rrggbb.'),
        ('too heavy',          jsonb_set(d, '{meta,pad}', (select jsonb_agg(repeat('x', 3999)) from generate_series(1, 55) g)), 'La carte est trop lourde : moins de texte ou moins de blocs, s''il vous plaît.')
    ) as x(what, doc, expect) loop
        set local role anon;
        begin perform event_doc_save(s, ed, c.doc); v_msg := null;
        exception when others then v_msg := sqlerrm; end;
        reset role;
        assert v_msg = c.expect, c.what || ': ' || coalesce(v_msg, 'accepted') || ' (expected ' || c.expect || ')';
    end loop;
    assert (select count(*) from event_doc_versions where event_id = (select v from t171 where k = 'event')::uuid) = 1, 'no version from a refusal';
    raise notice 'PASS: twenty refusals, each in French, none kept';
end $$;

-- 4. versions
do $$
declare
    s text := (select v from t171 where k = 'slug');
    ed text := (select v from t171 where k = 'edit');
    d jsonb := (select doc from d171 where k = 'ok');
    j jsonb;
    l jsonb;
    i int;
    v_first uuid;
    v_msg text;
begin
    set local role anon;
    for i in 1..22 loop
        perform event_doc_save(s, ed, jsonb_set(d, '{blocks,2,props,title}', to_jsonb('Mot n° ' || i)));
    end loop;
    l := event_doc_versions(s, ed);
    assert jsonb_array_length(l) = 20, 'the last twenty kept: ' || jsonb_array_length(l);
    assert (event_doc_version(s, ed, (l -> 0 ->> 'id')::uuid) #>> '{blocks,2,props,title}') = 'Mot n° 22', 'newest first';
    v_first := (l -> 19 ->> 'id')::uuid;
    assert (event_doc_version(s, ed, v_first) #>> '{blocks,2,props,title}') = 'Mot n° 3', 'the oldest kept is the 3rd save';
    j := event_doc_restore(s, ed, v_first);
    assert (j #>> '{doc,blocks,2,props,title}') = 'Mot n° 3', 'restored';
    assert (event_public(s, null, ed) #>> '{doc,blocks,2,props,title}') = 'Mot n° 3', 'the street reads the restored document';
    l := event_doc_versions(s, ed);
    assert jsonb_array_length(l) = 20 and (l -> 0 ->> 'note') = 'restore', 'a restore is a version of its own';
    begin perform event_doc_version((select v from t171 where k = 'slug2'), (select v from t171 where k = 'edit2'), v_first); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Cette version n''existe plus.', 'another card''s version: ' || coalesce(v_msg, 'served');
    begin perform event_doc_restore((select v from t171 where k = 'slug2'), (select v from t171 where k = 'edit2'), v_first); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Cette version n''existe plus.', 'another card''s version restored: ' || coalesce(v_msg, 'restored');
    begin perform event_doc_save(s, ed, d, 'restore'); v_msg := null;
    exception when others then v_msg := sqlerrm; end;
    assert v_msg = 'Enregistrement inconnu.', 'a save cannot call itself a restore';
    reset role;
    raise notice 'PASS: twenty versions kept, newest first, one read back, restored as a version of its own, another card''s refused';
end $$;

-- 5. cleared
do $$
declare
    s text := (select v from t171 where k = 'slug');
    ed text := (select v from t171 where k = 'edit');
begin
    set local role anon;
    assert event_doc_clear(s, ed), 'cleared';
    assert (event_public(s, null, ed) -> 'doc') = 'null'::jsonb, 'back to the model''s card';
    assert jsonb_array_length(event_doc_versions(s, ed)) = 20, 'the versions stay';
    reset role;
    raise notice 'PASS: cleared back to the model''s card, the versions kept';
end $$;

-- 6. the doors
do $$
declare
    f text;
begin
    foreach f in array array['event_doc_save(text, text, jsonb, text)', 'event_doc_versions(text, text)', 'event_doc_version(text, text, uuid)',
                             'event_doc_restore(text, text, uuid)', 'event_doc_clear(text, text)', 'event_public(text, text, text)'] loop
        assert has_function_privilege('anon', f, 'execute'), f || ' is the editor''s door';
    end loop;
    foreach f in array array['studio_doc_check(uuid, jsonb)', 'studio_value_problem(jsonb, integer)'] loop
        assert not has_function_privilege('anon', f, 'execute') and not has_function_privilege('authenticated', f, 'execute'), f || ' is nobody''s door';
    end loop;
    assert (select relrowsecurity from pg_class where oid = 'event_doc_versions'::regclass), 'row security on the versions';
    assert not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'event_doc_versions'), 'no policy on the versions';
    assert not has_table_privilege('anon', 'event_doc_versions', 'select') and not has_table_privilege('authenticated', 'event_doc_versions', 'select'),
        'the versions are granted to nobody';
    raise notice 'PASS: the five doors open to the editor, the checks to nobody, the versions to nobody';
end $$;

-- 7. the versions, read straight: nothing, whatever the grants
do $$
declare
    n int;
begin
    assert (select count(*) from event_doc_versions) > 0, 'versions exist to be hidden';
    set local role anon;
    begin select count(*) into n from event_doc_versions;
    exception when insufficient_privilege then n := 0; end;
    reset role;
    assert n = 0, 'anon reads no version: ' || n;
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '17117117-0000-0000-0000-000000000001', true);
    begin select count(*) into n from event_doc_versions;
    exception when insufficient_privilege then n := 0; end;
    reset role;
    assert n = 0, 'not even the business''s owner, signed in: ' || n;
    raise notice 'PASS: a version is read through its door only — not by anon, not by the owner signed in';
end $$;

rollback;
