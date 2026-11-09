-- ============================================================
-- 171 — Studio: a card becomes a document.
--
-- The owner (plans/studio_cartes.md, « start working on the whole plan »):
-- the card editor must work like Canva — add, remove, move, style anything.
-- Until now a card was a model with holes (events.content: t:<word>,
-- p:<picture>, checked key by key by event_content_save, 154). Studio
-- writes a document instead: a theme and a list of blocks, drawn by one
-- renderer (app/web/cartes/studio/).
--
--   * events.doc — the card's document, or null: a card without one is
--     drawn as before, from its model and its content (nothing changes
--     under anyone's feet until its organiser saves in Studio).
--   * event_doc_save(slug, edit, doc, note): with the card's edit token
--     (as 154), the document checked by studio_doc_check and kept; each
--     save is a version, the last twenty kept per card.
--   * event_doc_versions / event_doc_version / event_doc_restore: the list,
--     one version's document, and a version made current again (itself a
--     new version, so a restore can be undone).
--   * event_doc_clear: back to the model's card (the versions stay).
--   * event_public answers the document too: whole to the editor, without
--     its hidden blocks to the guests.
--
-- studio_doc_check — what a document may hold:
--   { "v": 2, "theme": {…}, "blocks": [ … ], "meta": {…} }, 200 kB at most;
--   theme: colours as #rrggbb, ids (fonts, motif, scene, preset) as
--   [a-z0-9-_] words — the renderer keeps the lists and draws an unknown
--   id as its default; 40 blocks at most, each { id, type, variant,
--   hidden, props, style } with a type from the list below and an id
--   unique in the card; inside props and style: plain values only (the
--   renderer writes every text as text, never as markup), keys as words,
--   six levels deep at most, 60 members per object or list, 4 000
--   characters per text; a picture ({"key": …}) must be one of the card's
--   own stored pictures (154); a link (href, url) must be https, tel or
--   mailto; a colour (color, bg, fg, ink, tint) a #rrggbb or a theme role.
--
-- For a shop, a farm and an association: nothing — an Événementiel's cards
-- only. Applies twice.
-- ============================================================

alter table events add column if not exists doc jsonb;
alter table events add column if not exists doc_saved_at timestamptz;

create table if not exists event_doc_versions (
    id        uuid primary key default gen_random_uuid(),
    event_id  uuid not null references events(id) on delete cascade,
    doc       jsonb not null,
    bytes     integer not null check (bytes >= 0),
    blocks    smallint not null check (blocks >= 0),
    note      text not null default 'save' check (note in ('save', 'convert', 'restore')),
    saved_at  timestamptz not null default clock_timestamp()
);
create index if not exists event_doc_versions_event_idx on event_doc_versions (event_id, saved_at desc);
-- Read and written only through the functions below (the edit token is
-- the key, as for the card itself): no policy, nobody reads it directly.
alter table event_doc_versions enable row level security;

-- A value inside a block, checked all the way down.
create or replace function studio_value_problem(p_v jsonb, p_depth int)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
    k text;
    x jsonb;
    r text;
begin
    if p_depth > 6 then
        return 'trop de niveaux imbriqués';
    end if;
    case jsonb_typeof(p_v)
        when 'object' then
            if (select count(*) from jsonb_object_keys(p_v)) > 60 then
                return 'trop de champs dans un bloc';
            end if;
            for k, x in select * from jsonb_each(p_v) loop
                if k !~ '^[a-zA-Z][a-zA-Z0-9_]{0,31}$' then
                    return format('champ mal nommé (%s)', left(k, 40));
                end if;
                r := studio_value_problem(x, p_depth + 1);
                if r is not null then return r; end if;
            end loop;
        when 'array' then
            if jsonb_array_length(p_v) > 60 then
                return 'liste trop longue';
            end if;
            for x in select * from jsonb_array_elements(p_v) loop
                r := studio_value_problem(x, p_depth + 1);
                if r is not null then return r; end if;
            end loop;
        when 'string' then
            if length(p_v #>> '{}') > 4000 then
                return 'un texte de 4 000 caractères au plus';
            end if;
        when 'number' then
            if abs((p_v #>> '{}')::numeric) > 1000000000 then
                return 'nombre hors limites';
            end if;
        else
            null;   -- boolean, null
    end case;
    return null;
end;
$$;

create or replace function studio_doc_check(p_event uuid, p_doc jsonb)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    k text;
    v jsonb;
    b jsonb;
    t jsonb;
    r text;
    n int := 0;
    ids text[] := '{}';
    types constant text[] := array['cover', 'text', 'photo', 'gallery', 'families', 'programme', 'infos',
        'countdown', 'place', 'calendar', 'contribution', 'quote', 'rsvp', 'tickets', 'album', 'pass',
        'video', 'music', 'divider', 'footer', 'free', 'spacer', 'button', 'faq', 'menu', 'story', 'dresscode'];
begin
    if p_doc is null or jsonb_typeof(p_doc) <> 'object' then
        raise exception 'La carte est mal formée.';
    end if;
    if octet_length(p_doc::text) > 200000 then
        raise exception 'La carte est trop lourde : moins de texte ou moins de blocs, s''il vous plaît.';
    end if;
    for k in select jsonb_object_keys(p_doc) loop
        if k not in ('v', 'theme', 'blocks', 'meta') then
            raise exception 'Champ inconnu : %', left(k, 40);
        end if;
    end loop;
    if p_doc -> 'v' is distinct from '2'::jsonb then
        raise exception 'Version de carte inconnue.';
    end if;

    -- the theme
    t := coalesce(p_doc -> 'theme', '{}'::jsonb);
    if jsonb_typeof(t) <> 'object' then
        raise exception 'Le thème est mal formé.';
    end if;
    for k, v in select * from jsonb_each(t) loop
        if k = 'colors' then
            if jsonb_typeof(v) <> 'object' or (select count(*) from jsonb_object_keys(v)) > 12 then
                raise exception 'Les couleurs sont mal formées.';
            end if;
            if exists (select 1 from jsonb_each(v) c
                        where c.key !~ '^[a-zA-Z]{1,16}$' or jsonb_typeof(c.value) <> 'string'
                           or (c.value #>> '{}') !~ '^#[0-9a-fA-F]{6}$') then
                raise exception 'Une couleur s''écrit #rrggbb.';
            end if;
        elsif k = 'fonts' then
            if jsonb_typeof(v) <> 'object' or exists (select 1 from jsonb_each(v) f
                        where f.key not in ('display', 'body', 'script') or jsonb_typeof(f.value) <> 'string'
                           or (f.value #>> '{}') !~ '^[a-z0-9_-]{1,32}$') then
                raise exception 'Les polices sont mal formées.';
            end if;
        elsif k in ('motion', 'corners', 'scene', 'preset', 'decor') then
            if v <> 'null'::jsonb and (jsonb_typeof(v) <> 'string' or (v #>> '{}') !~ '^[a-z0-9_-]{0,40}$') then
                raise exception 'Thème mal formé (%).', k;
            end if;
        elsif k = 'motif' then
            if v <> 'null'::jsonb and (jsonb_typeof(v) <> 'object' or studio_value_problem(v, 2) is not null
                    or coalesce(v ->> 'id', '') !~ '^[a-z0-9_-]{0,40}$') then
                raise exception 'Le motif est mal formé.';
            end if;
        else
            raise exception 'Thème : champ inconnu (%).', left(k, 40);
        end if;
    end loop;

    -- the blocks
    if p_doc -> 'blocks' is null or jsonb_typeof(p_doc -> 'blocks') <> 'array' then
        raise exception 'La carte n''a pas de blocs.';
    end if;
    if jsonb_array_length(p_doc -> 'blocks') > 40 then
        raise exception 'Quarante blocs au plus par carte.';
    end if;
    for b in select * from jsonb_array_elements(p_doc -> 'blocks') loop
        n := n + 1;
        if jsonb_typeof(b) <> 'object' then
            raise exception 'Le bloc % est mal formé.', n;
        end if;
        for k in select jsonb_object_keys(b) loop
            if k not in ('id', 'type', 'variant', 'hidden', 'props', 'style') then
                raise exception 'Bloc % : champ inconnu (%).', n, left(k, 40);
            end if;
        end loop;
        if coalesce(b ->> 'id', '') !~ '^[a-z0-9]{1,16}$' then
            raise exception 'Bloc % : identifiant mal formé.', n;
        end if;
        if (b ->> 'id') = any (ids) then
            raise exception 'Deux blocs portent le même identifiant (%).', b ->> 'id';
        end if;
        ids := ids || (b ->> 'id');
        if jsonb_typeof(b -> 'type') is distinct from 'string' or not ((b ->> 'type') = any (types)) then
            raise exception 'Bloc % : type inconnu (%).', n, left(coalesce(b ->> 'type', ''), 40);
        end if;
        if b ? 'variant' and b -> 'variant' <> 'null'::jsonb
           and (jsonb_typeof(b -> 'variant') <> 'string' or (b ->> 'variant') !~ '^[a-z0-9-]{0,24}$') then
            raise exception 'Bloc % : variante mal formée.', n;
        end if;
        if b ? 'hidden' and jsonb_typeof(b -> 'hidden') not in ('boolean', 'null') then
            raise exception 'Bloc % : « masqué » mal formé.', n;
        end if;
        foreach k in array array['props', 'style'] loop
            if b ? k and b -> k <> 'null'::jsonb then
                if jsonb_typeof(b -> k) <> 'object' then
                    raise exception 'Bloc % : % mal formé.', n, k;
                end if;
                r := studio_value_problem(b -> k, 1);
                if r is not null then
                    raise exception 'Bloc % : %.', n, r;
                end if;
            end if;
        end loop;
    end loop;
    if p_doc ? 'meta' and p_doc -> 'meta' <> 'null'::jsonb then
        if jsonb_typeof(p_doc -> 'meta') <> 'object' then
            raise exception 'Les informations de la carte sont mal formées.';
        end if;
        r := studio_value_problem(p_doc -> 'meta', 2);
        if r is not null then
            raise exception 'Informations de la carte : %.', r;
        end if;
    end if;

    -- the pictures: the card's own, stored (154); 150 at most
    if (select count(distinct x #>> '{}') from jsonb_path_query(p_doc, 'lax $.**.key') x) > 150 then
        raise exception 'Cent cinquante photos au plus par carte.';
    end if;
    if exists (select 1 from jsonb_path_query(p_doc, 'lax $.**.key') x
                where jsonb_typeof(x) <> 'string'
                   or not exists (select 1 from event_pictures p
                                   where p.key = x #>> '{}' and p.event_id = p_event and p.state = 'stored')) then
        raise exception 'Cette image n''est pas celle de la carte.';
    end if;
    -- the links: https, tel, mailto (or nothing), 600 characters at most
    if exists (select 1 from (select x from jsonb_path_query(p_doc, 'lax $.**.href') x
                               union all select x from jsonb_path_query(p_doc, 'lax $.**.url') x) l
                where jsonb_typeof(l.x) <> 'string'
                   or ((l.x #>> '{}') <> '' and (length(l.x #>> '{}') > 600 or (l.x #>> '{}') !~ '^(https://|tel:|mailto:)[^\s<>"''`]+$'))) then
        raise exception 'Un lien doit commencer par https://, tel: ou mailto:.';
    end if;
    -- a stock picture: a name of the card bank
    if exists (select 1 from jsonb_path_query(p_doc, 'lax $.**.stock') x
                where jsonb_typeof(x) <> 'string' or (x #>> '{}') !~ '^[a-z0-9-]{1,40}$') then
        raise exception 'Photo de la banque inconnue.';
    end if;
    -- the colours inside blocks: #rrggbb or a theme role
    if exists (select 1 from jsonb_path_query(p_doc, 'lax $.blocks[*].** ? (@.type() == "object")') o,
                             jsonb_each(o) c
                where c.key in ('color', 'bg', 'fg', 'ink', 'tint')
                  and (jsonb_typeof(c.value) <> 'string' or (c.value #>> '{}') !~ '^(#[0-9a-fA-F]{6}|[a-z]{1,16})?$')) then
        raise exception 'Une couleur s''écrit #rrggbb.';
    end if;
end;
$$;

-- Saved by the organiser (the card's edit token, as 154).
create or replace function event_doc_save(p_slug text, p_edit text, p_doc jsonb, p_note text default 'save')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    e events;
    v_id uuid;
    v_now timestamptz := clock_timestamp();   -- the real time: two saves in one request stay in order
begin
    e := event_for_edit(p_slug, p_edit);
    if coalesce(p_note, 'save') not in ('save', 'convert') then
        raise exception 'Enregistrement inconnu.';
    end if;
    perform studio_doc_check(e.id, p_doc);
    update events set doc = p_doc, doc_saved_at = v_now where id = e.id;
    insert into event_doc_versions (event_id, doc, bytes, blocks, note, saved_at)
    values (e.id, p_doc, octet_length(p_doc::text), jsonb_array_length(p_doc -> 'blocks'), coalesce(p_note, 'save'), v_now)
    returning id into v_id;
    -- the last twenty
    delete from event_doc_versions
     where event_id = e.id
       and id not in (select id from event_doc_versions where event_id = e.id order by saved_at desc, id desc limit 20);
    return jsonb_build_object('saved_at', v_now, 'version', v_id);
end;
$$;

create or replace function event_doc_versions(p_slug text, p_edit text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    e events;
begin
    e := event_for_edit(p_slug, p_edit);
    return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'saved_at', saved_at, 'bytes', bytes, 'blocks', blocks, 'note', note)
                                      order by saved_at desc, id desc)
                       from event_doc_versions where event_id = e.id), '[]'::jsonb);
end;
$$;

create or replace function event_doc_version(p_slug text, p_edit text, p_version uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    e events;
    d jsonb;
begin
    e := event_for_edit(p_slug, p_edit);
    select doc into d from event_doc_versions where id = p_version and event_id = e.id;
    if not found then
        raise exception 'Cette version n''existe plus.';
    end if;
    return d;
end;
$$;

create or replace function event_doc_restore(p_slug text, p_edit text, p_version uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    e events;
    d jsonb;
    v_id uuid;
    v_now timestamptz := clock_timestamp();   -- the real time: two saves in one request stay in order
begin
    e := event_for_edit(p_slug, p_edit);
    select doc into d from event_doc_versions where id = p_version and event_id = e.id;
    if not found then
        raise exception 'Cette version n''existe plus.';
    end if;
    -- a picture removed since that version is no longer the card's
    perform studio_doc_check(e.id, d);
    update events set doc = d, doc_saved_at = v_now where id = e.id;
    insert into event_doc_versions (event_id, doc, bytes, blocks, note, saved_at)
    values (e.id, d, octet_length(d::text), jsonb_array_length(d -> 'blocks'), 'restore', v_now)
    returning id into v_id;
    delete from event_doc_versions
     where event_id = e.id
       and id not in (select id from event_doc_versions where event_id = e.id order by saved_at desc, id desc limit 20);
    return jsonb_build_object('saved_at', v_now, 'version', v_id, 'doc', d);
end;
$$;

create or replace function event_doc_clear(p_slug text, p_edit text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    e events;
begin
    e := event_for_edit(p_slug, p_edit);
    update events set doc = null, doc_saved_at = null where id = e.id;
    return true;
end;
$$;

-- The street's answer (154) with the document. A block the organiser hid
-- (« Masqué pour les invités ») goes to the editor only: the guests'
-- answer leaves it out, so what is hidden is not merely undrawn.
create or replace function event_public(p_slug text, p_preview text default null, p_edit text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    e events;
    t event_templates;
    v_editor boolean;
begin
    select * into e from events where slug = lower(trim(coalesce(p_slug, '')));
    if not found or not event_visible(e, p_preview, p_edit) then
        return null;
    end if;
    v_editor := p_edit is not null and p_edit = e.edit_token;
    if e.doc is not null and not v_editor and jsonb_typeof(e.doc -> 'blocks') = 'array' then
        e.doc := jsonb_set(e.doc, '{blocks}', coalesce(
            (select jsonb_agg(b order by n)
               from jsonb_array_elements(e.doc -> 'blocks') with ordinality as x(b, n)
              where coalesce(b ->> 'hidden', 'false') <> 'true'),
            '[]'::jsonb));
    end if;
    select * into t from event_templates where key = e.card;
    return jsonb_build_object(
        'slug', e.slug,
        'kind', e.kind,
        'card', e.card,
        'family', coalesce(t.family, 'classique'),
        'premium', coalesce(t.premium, false),
        'title', e.title,
        'starts_at', e.starts_at,
        'tz', e.tz,
        'place', e.place,
        'content', e.content,
        'doc', e.doc,
        'doc_saved_at', e.doc_saved_at,
        'rsvp_on', e.rsvp_on,
        'album_on', e.album_on,
        'published', e.published,
        'org_name', (select name from orgs where id = e.org_id),
        'preview', p_preview is not null and p_preview = e.preview_token,
        'editor', v_editor);
end;
$$;

-- The doors: the editor is a signed-out page with the edit token as its
-- key (as 154's event_content_save); the checks are not doors.
revoke execute on function studio_value_problem(jsonb, int) from public;
revoke execute on function studio_doc_check(uuid, jsonb) from public;
revoke execute on function event_doc_save(text, text, jsonb, text) from public;
revoke execute on function event_doc_versions(text, text) from public;
revoke execute on function event_doc_version(text, text, uuid) from public;
revoke execute on function event_doc_restore(text, text, uuid) from public;
revoke execute on function event_doc_clear(text, text) from public;
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function studio_value_problem(jsonb, int) from anon;
        revoke execute on function studio_doc_check(uuid, jsonb) from anon;
        grant execute on function event_doc_save(text, text, jsonb, text) to anon;
        grant execute on function event_doc_versions(text, text) to anon;
        grant execute on function event_doc_version(text, text, uuid) to anon;
        grant execute on function event_doc_restore(text, text, uuid) to anon;
        grant execute on function event_doc_clear(text, text) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function studio_value_problem(jsonb, int) from authenticated;
        revoke execute on function studio_doc_check(uuid, jsonb) from authenticated;
        grant execute on function event_doc_save(text, text, jsonb, text) to authenticated;
        grant execute on function event_doc_versions(text, text) to authenticated;
        grant execute on function event_doc_version(text, text, uuid) to authenticated;
        grant execute on function event_doc_restore(text, text, uuid) to authenticated;
        grant execute on function event_doc_clear(text, text) to authenticated;
    end if;
end $$;
