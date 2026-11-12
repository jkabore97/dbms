-- ============================================================
-- 181 — An album's counts hold when photos are sent together.
--
-- The owner, on « Phanuel & Espérance » (two photos per phone, 179): « I
-- was able to add 3 pictures while the limit should be 2 ». The three
-- were chosen at once; the card page sent them together and each request
-- counted the phone's photos at the same instant — none yet — so all
-- three passed. The same held for 164's five per pass and the album's 300.
--
-- event_album_add takes the card's row first (for update): a card's photos
-- are counted one request after the other, each seeing those before it.
-- The page now also sends them one after the other (its words then say
-- which were refused). Otherwise as 179.
--
-- Also, a card's theme may say `fall` (« petales »): petals of several
-- colours falling over the whole card (the owner: « at least the flowers
-- falling down to the bottom and not only 1 type of color »). Studio's
-- check of a saved card (173) takes it; otherwise as 173.
--
-- For a shop, a farm and an association: nothing. Applies twice.
-- ============================================================

create or replace function event_album_add(p_slug text, p_preview text, p_ext text, p_guest text default null,
                                           p_pass uuid default null, p_device text default null)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    e events;
    v_ext text := lower(btrim(coalesce(p_ext, '')));
    v_guest text := nullif(left(btrim(coalesce(p_guest, '')), 60), '');
    v_device text := nullif(btrim(coalesce(p_device, '')), '');
    v_key text;
    v_quota integer;
begin
    e := event_for_album(p_slug, p_preview);
    -- one photo of this card at a time (181): photos sent together each
    -- counted the others before them — three got past « two per phone »
    perform 1 from events where id = e.id for update;
    if v_ext not in ('jpg', 'png', 'webp') then
        raise exception 'Photos uniquement (JPEG, PNG ou WebP).';
    end if;
    if v_device is not null and v_device !~ '^[a-zA-Z0-9-]{16,64}$' then
        v_device := null;
    end if;
    if e.album_limit then
        if p_pass is null then
            raise exception 'L''album est réservé aux invités : répondez d''abord à l''invitation, ou réservez votre billet, sur ce téléphone.';
        end if;
        v_quota := event_album_pass_quota(e.id, p_pass);
        if v_quota is null then
            raise exception 'L''album est réservé aux invités : cette carte d''invité ou ce billet n''est pas de cet événement.';
        end if;
        if (select count(*) from event_pictures where event_id = e.id and pass_id = p_pass and source = 'guest') >= v_quota then
            raise exception 'Vous avez déposé vos % photos : c''est le maximum par invité.', v_quota;
        end if;
    elsif e.album_open_quota is not null then
        if v_device is null then
            raise exception 'Rechargez la carte pour ajouter vos photos.';
        end if;
        if (select count(*) from event_pictures where event_id = e.id and device = v_device and source = 'guest') >= e.album_open_quota then
            raise exception 'Vous avez déposé vos % photo(s) : c''est le maximum par personne.', e.album_open_quota;
        end if;
    end if;
    if (select count(*) from event_pictures where event_id = e.id and source = 'guest') >= 300 then
        raise exception 'L''album est plein : 300 photos au plus.';
    end if;
    if (select count(*) from event_pictures
         where event_id = e.id and source = 'guest' and created_at > now() - interval '1 day') >= 200 then
        raise exception 'Trop de photos envoyées aujourd''hui. Réessayez demain.';
    end if;
    v_key := 'events/' || e.id || '/' || replace(gen_random_uuid()::text, '-', '') || '.' || v_ext;
    insert into event_pictures (key, event_id, state, source, guest, pass_id, approved, device)
    values (v_key, e.id, 'slot', 'guest', v_guest, p_pass, not e.album_review, v_device);
    return v_key;
end;
$$;

revoke execute on function event_album_add(text, text, text, text, uuid, text) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function event_album_add(text, text, text, text, uuid, text) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function event_album_add(text, text, text, text, uuid, text) to authenticated;
    end if;
end $$;

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
        elsif k in ('motion', 'corners', 'scene', 'preset', 'decor', 'fall') then
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

notify pgrst, 'reload schema';
