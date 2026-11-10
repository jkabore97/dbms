-- ============================================================
-- 173 — Studio, phases 2 and 3: everything the server needs, at once.
--
-- The owner: « please complete phase 2 and 3 ». One database update for
-- all of it, so it is run live once; the pages and the app come on top.
--
--   * studio_doc_check: a picture may be any stored picture of the same
--     business's cards (« Mes photos », the business's library), and a
--     Premium animated scene (lx-…) is Marakaj Pro's — a card that already
--     had one when the plan lapsed keeps it.
--   * event_library(slug, edit): the editor's list of those pictures.
--   * event_public: tells the editor whether Premium is open (« pro »), and
--     everyone the answers' closing day (« rsvp_closes »).
--   * event_rsvp: the guests' answers to the organiser's questions
--     (extra.answers, three at most) and the closing day, both from the
--     card's « Réponse » block, held by the server, not only by the page.
--   * event_views + event_count(slug, what): how many people opened the
--     card, how many shared it — counted by the Worker (one a day per
--     visitor, robots left out); event_stats(event) for the business.
--   * event_assist_use(slug, edit): the writing assistant's allowance
--     (Marakaj Pro, forty a day per card), asked by the Worker.
--
-- For a shop, a farm and an association: nothing — an Événementiel's cards
-- only. Applies twice.
-- ============================================================

-- The answers' closing day: the « Réponse » block's « closes »
-- (YYYY-MM-DD), the first one the guests see; null when none.
create or replace function event_rsvp_closes(p_event events)
returns date
language sql
stable
security definer
set search_path = public
as $$
    select (b -> 'props' ->> 'closes')::date
      from jsonb_array_elements(case when jsonb_typeof(p_event.doc -> 'blocks') = 'array'
                                     then p_event.doc -> 'blocks' else '[]'::jsonb end) with ordinality as x(b, n)
     where b ->> 'type' = 'rsvp' and coalesce(b ->> 'hidden', 'false') <> 'true'
       and coalesce(b -> 'props' ->> 'closes', '') ~ '^\d{4}-\d{2}-\d{2}$'
     order by n
     limit 1;
$$;

-- What a document may hold (171), with the business's library and the
-- Premium scenes (173).
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
    v_org uuid := (select org_id from events where id = p_event);
    v_old jsonb := (select doc from events where id = p_event);
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

    -- the pictures: stored (154), the card's own or one of the same
    -- business's other cards (173: « Mes photos »); 150 at most
    if (select count(distinct x #>> '{}') from jsonb_path_query(p_doc, 'lax $.**.key') x) > 150 then
        raise exception 'Cent cinquante photos au plus par carte.';
    end if;
    if exists (select 1 from jsonb_path_query(p_doc, 'lax $.**.key') x
                where jsonb_typeof(x) <> 'string'
                   or not exists (select 1 from event_pictures p join events pe on pe.id = p.event_id
                                   where p.key = x #>> '{}' and p.state = 'stored' and pe.org_id = v_org)) then
        raise exception 'Cette image n''est pas celle de la carte.';
    end if;
    -- a Premium animated scene (lx-…, drawn on the graphics card): Marakaj
    -- Pro (173), unless the card already had it when the plan lapsed —
    -- its saved card keeps what it was given, nothing new is added.
    if org_plan(v_org) <> 'pro' and exists (
            select 1 from jsonb_path_query(p_doc, 'lax $.**.scene') s
             where jsonb_typeof(s) = 'string' and (s #>> '{}') like 'lx-%'
               and not exists (select 1 from jsonb_path_query(coalesce(v_old, '{}'::jsonb), 'lax $.**.scene') o
                                where (o #>> '{}') = (s #>> '{}'))) then
        raise exception 'Ce décor animé est Premium : passez à Marakaj Pro pour l''utiliser.';
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

-- The street's answer (171) with « pro » and « rsvp_closes » (173).
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
        'editor', v_editor,
        -- the editor's: whether Premium is open to it (173); null to the guests
        'pro', case when v_editor then org_plan(e.org_id) = 'pro' end,
        -- the answers' closing day (173), for the guests' form
        'rsvp_closes', event_rsvp_closes(e));
end;
$$;


-- « Mes photos »: every stored picture of the business's cards, newest
-- first, for the editor (the card's edit token, as 154).
create or replace function event_library(p_slug text, p_edit text)
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
    return coalesce((
        select jsonb_agg(jsonb_build_object('key', x.key, 'title', x.title, 'mine', x.mine) order by x.at desc)
          from (select p.key, pe.title, pe.id = e.id as mine, coalesce(p.done_at, p.created_at) as at
                  from event_pictures p join events pe on pe.id = p.event_id
                 where pe.org_id = e.org_id and p.state = 'stored'
                 order by coalesce(p.done_at, p.created_at) desc
                 limit 300) x), '[]'::jsonb);
end;
$$;


-- The guests' answer (152), with the organiser's questions and the
-- closing day (173).
create or replace function event_rsvp(
    p_slug text, p_preview text, p_name text, p_people integer, p_answer text, p_message text, p_extra jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    e events;
    v_name text := nullif(trim(coalesce(p_name, '')), '');
    v_message text := nullif(trim(coalesce(p_message, '')), '');
    v_closes date;
    v_id uuid;
begin
    select * into e from events where slug = lower(trim(coalesce(p_slug, '')));
    if not found or not event_visible(e, p_preview) then
        raise exception 'Cette carte n''est pas ouverte.';
    end if;
    if not e.rsvp_on then
        raise exception 'Les réponses sont fermées pour cet événement.';
    end if;
    v_closes := event_rsvp_closes(e);
    if v_closes is not null and (now() at time zone coalesce(e.tz, 'Africa/Ouagadougou'))::date > v_closes then
        raise exception 'Les réponses sont closes depuis le %.', to_char(v_closes, 'DD/MM/YYYY');
    end if;
    if v_name is null or length(v_name) > 80 then
        raise exception 'Votre nom, en 80 caractères au plus.';
    end if;
    if p_answer not in ('oui', 'non', 'mot') then
        raise exception 'Réponse inconnue.';
    end if;
    if p_people is not null and (p_people < 0 or p_people > 20) then
        raise exception 'Entre 0 et 20 personnes.';
    end if;
    if v_message is not null and length(v_message) > 1000 then
        raise exception 'Un mot de 1 000 caractères au plus.';
    end if;
    if p_extra is not null and (jsonb_typeof(p_extra) <> 'object' or length(p_extra::text) > 2000) then
        raise exception 'Réponse mal formée.';
    end if;
    -- the answers to the organiser's questions: three texts at most
    if p_extra ? 'answers' and (jsonb_typeof(p_extra -> 'answers') <> 'array'
            or jsonb_array_length(p_extra -> 'answers') > 3
            or exists (select 1 from jsonb_array_elements(p_extra -> 'answers') a
                        where jsonb_typeof(a) <> 'string' or length(a #>> '{}') > 300)) then
        raise exception 'Trois réponses au plus, de 300 caractères chacune.';
    end if;
    if (select count(*) from event_rsvps where event_id = e.id) >= 2000 then
        raise exception 'Cet événement a reçu toutes les réponses qu''il peut tenir.';
    end if;
    insert into event_rsvps (event_id, name, people, answer, message, extra)
    values (e.id, v_name, coalesce(p_people, 1), p_answer, v_message, coalesce(p_extra, '{}'::jsonb))
    returning id into v_id;
    return v_id;
end;
$$;

-- ------------------------------------------------------------
-- Views and shares
-- ------------------------------------------------------------
create table if not exists event_views (
    event_id uuid not null references events(id) on delete cascade,
    day      date not null,
    views    integer not null default 0 check (views >= 0),
    shares   integer not null default 0 check (shares >= 0),
    primary key (event_id, day)
);
alter table event_views enable row level security;
drop policy if exists "views seen by the business's admins" on event_views;
create policy "views seen by the business's admins"
on event_views for select
using (exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)));

-- Counted by the Worker: a guest's opening ('view') or a share ('share')
-- of a published card. The Worker counts one a day per visitor and leaves
-- robots out; here only a ceiling, so a loop cannot fill a table.
create or replace function event_count(p_slug text, p_what text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    e events;
    v_day date;
begin
    if p_what not in ('view', 'share') then
        return;
    end if;
    select * into e from events where slug = lower(trim(coalesce(p_slug, '')));
    if not found or not e.published then
        return;
    end if;
    v_day := (now() at time zone coalesce(e.tz, 'Africa/Ouagadougou'))::date;
    insert into event_views as w (event_id, day, views, shares)
    values (e.id, v_day, case when p_what = 'view' then 1 else 0 end, case when p_what = 'share' then 1 else 0 end)
    on conflict (event_id, day) do update
       set views  = least(w.views  + case when p_what = 'view'  then 1 else 0 end, 1000000),
           shares = least(w.shares + case when p_what = 'share' then 1 else 0 end, 1000000);
end;
$$;

-- The business's « Tableau de bord » for one card: opened and shared, in
-- all and day by day (the last thirty), and the answers. Security invoker:
-- the policies decide (a card of another business answers nothing).
create or replace function event_stats(p_event uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
    select case when not exists (select 1 from events where id = p_event and is_org_admin(org_id)) then null else
    jsonb_build_object(
        'views',  coalesce((select sum(views)  from event_views where event_id = p_event), 0),
        'shares', coalesce((select sum(shares) from event_views where event_id = p_event), 0),
        'days', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'views', views, 'shares', shares) order by day)
                            from (select * from event_views where event_id = p_event order by day desc limit 30) d), '[]'::jsonb),
        'oui',    (select count(*) from event_rsvps where event_id = p_event and answer = 'oui'),
        'non',    (select count(*) from event_rsvps where event_id = p_event and answer = 'non'),
        'mot',    (select count(*) from event_rsvps where event_id = p_event and answer = 'mot'),
        'people', coalesce((select sum(people) from event_rsvps where event_id = p_event and answer = 'oui'), 0))
    end;
$$;

-- ------------------------------------------------------------
-- The writing assistant (Marakaj Pro): forty a day per card
-- ------------------------------------------------------------
create table if not exists event_assist_uses (
    event_id uuid not null references events(id) on delete cascade,
    day      date not null,
    uses     integer not null default 0,
    primary key (event_id, day)
);
alter table event_assist_uses enable row level security;
-- no policy and no grant: only the function below reads and writes it

create or replace function event_assist_use(p_slug text, p_edit text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    e events;
    v_uses integer;
begin
    e := event_for_edit(p_slug, p_edit);
    if org_plan(e.org_id) <> 'pro' then
        return jsonb_build_object('pro', false, 'left', 0);
    end if;
    insert into event_assist_uses as u (event_id, day, uses) values (e.id, current_date, 1)
    on conflict (event_id, day) do update set uses = u.uses + 1
    returning uses into v_uses;
    if v_uses > 40 then
        raise exception 'L''assistant a assez écrit pour aujourd''hui : il revient demain.';
    end if;
    return jsonb_build_object('pro', true, 'left', 40 - v_uses);
end;
$$;

-- ------------------------------------------------------------
-- The doors (063)
-- ------------------------------------------------------------
revoke execute on function event_rsvp_closes(events)  from public;
revoke execute on function event_library(text, text)  from public;
revoke execute on function event_count(text, text)    from public;
revoke execute on function event_stats(uuid)          from public;
revoke execute on function event_assist_use(text, text) from public;
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function event_rsvp_closes(events)    from anon;
        revoke execute on function event_stats(uuid)            from anon;
        grant  execute on function event_library(text, text)    to anon;
        grant  execute on function event_count(text, text)     to anon;
        grant  execute on function event_assist_use(text, text) to anon;
        revoke all on event_views, event_assist_uses from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function event_rsvp_closes(events)    from authenticated;
        grant  execute on function event_stats(uuid)            to authenticated;
        grant  execute on function event_library(text, text)    to authenticated;
        grant  execute on function event_count(text, text)     to authenticated;
        grant  execute on function event_assist_use(text, text) to authenticated;
        revoke all on event_views, event_assist_uses from authenticated;
        grant select on event_views to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
