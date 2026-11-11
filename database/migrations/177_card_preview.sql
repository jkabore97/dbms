-- ============================================================
-- 177 — The street shows the card itself.
--
-- The owner: « I want the vitrine preview to be the actual card preview
-- image till the user want to change it to its own image or choose
-- between those that you generated ».
--
-- events.card_preview: the key of the card's own picture — its first
-- screen as a guest sees it, drawn by Studio in the organiser's browser
-- each time the card is saved (and once when Studio opens a card that has
-- none). A picture of its own kind, 'preview' (event_pictures.source): not
-- among the organiser's photos, not counted in their eighty, sixty a day
-- at most; each one replaces the last (event_preview_done names it, the
-- uploads Worker deletes its bytes).
--
-- street_event_picture: the organiser's choice (175) first; else the
-- card's own picture; else, as 174, the card's photo, its bank photo, the
-- picture of its kind.
--
-- For a shop, a farm and an association: nothing (an Événementiel's cards
-- only). Applies twice.
-- ============================================================

alter table event_pictures drop constraint if exists event_pictures_source_check;
alter table event_pictures add constraint event_pictures_source_check check (source in ('organiser', 'guest', 'preview'));

alter table events add column if not exists card_preview text;

-- The slot: the card's edit token is the key, as 154's pictures.
create or replace function event_preview_slot(p_slug text, p_edit text, p_ext text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    e events;
    v_ext text := lower(btrim(coalesce(p_ext, '')));
    v_key text;
begin
    e := event_for_edit(p_slug, p_edit);
    if v_ext not in ('jpg', 'png', 'webp') then
        raise exception 'Photos uniquement (JPEG, PNG ou WebP).';
    end if;
    if (select count(*) from event_pictures
         where event_id = e.id and source = 'preview' and created_at > now() - interval '1 day') >= 60 then
        raise exception 'Trop d''aperçus aujourd''hui. Réessayez demain.';
    end if;
    v_key := 'events/' || e.id || '/' || replace(gen_random_uuid()::text, '-', '') || '.' || v_ext;
    insert into event_pictures (key, event_id, state, source) values (v_key, e.id, 'slot', 'preview');
    return v_key;
end;
$$;

-- The bytes are in: the card's picture is this one; the one it replaces
-- (and any slot left behind) goes, its key answered for its bytes.
create or replace function event_preview_done(p_key text, p_edit text, p_bytes integer default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    p event_pictures;
    e events;
    v_old text;
begin
    select * into p from event_pictures
     where key = p_key and state = 'slot' and source = 'preview' and created_at > now() - interval '1 hour'
     for update;
    if not found then
        raise exception 'Envoi inconnu.';
    end if;
    select * into e from events where id = p.event_id for update;
    if p_edit is null or p_edit <> e.edit_token then
        raise exception 'Cette carte ne peut pas être modifiée d''ici.';
    end if;
    update event_pictures set state = 'stored', bytes = p_bytes, done_at = clock_timestamp() where key = p_key;
    v_old := e.card_preview;
    update events set card_preview = p_key where id = e.id;
    delete from event_pictures
     where event_id = e.id and source = 'preview' and key <> p_key
       and (key = v_old or state = 'slot' and created_at < now() - interval '1 hour');
    return case when v_old is distinct from p_key then v_old end;
end;
$$;

-- Studio asks whether the card has its picture yet (the edit token again).
create or replace function event_preview_of(p_slug text, p_edit text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    e events;
begin
    e := event_for_edit(p_slug, p_edit);
    return e.card_preview;
end;
$$;

create or replace function street_event_picture(p_event events)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_blocks jsonb;
    v_key text;
    v_stock text;
begin
    -- the organiser's choice (175)
    if p_event.street_picture like 'fete:%' then
        return jsonb_build_object('poster', null, 'poster_stock', null,
                                  'poster_fete', substr(p_event.street_picture, 6));
    end if;
    if p_event.street_picture is not null
       and exists (select 1 from event_pictures p
                    where p.key = p_event.street_picture and p.event_id = p_event.id and p.state = 'stored') then
        return jsonb_build_object('poster', p_event.street_picture, 'poster_stock', null, 'poster_fete', null);
    end if;
    -- the card itself (177)
    if p_event.card_preview is not null
       and exists (select 1 from event_pictures p
                    where p.key = p_event.card_preview and p.event_id = p_event.id and p.state = 'stored') then
        return jsonb_build_object('poster', p_event.card_preview, 'poster_stock', null, 'poster_fete', null);
    end if;
    -- a Studio card: its blocks as the guests see them, the cover first
    if jsonb_typeof(p_event.doc -> 'blocks') = 'array' then
        select coalesce(jsonb_agg(b order by (b ->> 'type') <> 'cover', n), '[]'::jsonb) into v_blocks
          from jsonb_array_elements(p_event.doc -> 'blocks') with ordinality as x(b, n)
         where coalesce(b ->> 'hidden', 'false') <> 'true';
        select k #>> '{}' into v_key
          from jsonb_path_query(v_blocks, 'lax $[*].**.key') with ordinality as y(k, n)
         where jsonb_typeof(k) = 'string'
           and exists (select 1 from event_pictures p where p.key = k #>> '{}' and p.state = 'stored')
         order by n
         limit 1;
        if v_key is null then
            select s #>> '{}' into v_stock
              from jsonb_path_query(v_blocks, 'lax $[*].**.stock') with ordinality as y(s, n)
             where jsonb_typeof(s) = 'string' and (s #>> '{}') ~ '^[a-z0-9-]{1,40}$'
             order by n
             limit 1;
        end if;
    end if;
    -- a classic or animated card: its photo slots, the hero first
    if v_key is null and v_stock is null and jsonb_typeof(p_event.content) = 'object' then
        select c.value ->> 'key' into v_key
          from jsonb_each(p_event.content) c
         where c.key like 'p:%' and jsonb_typeof(c.value) = 'object'
           and exists (select 1 from event_pictures p where p.key = c.value ->> 'key' and p.state = 'stored')
         order by c.key <> 'p:hero', c.key <> 'p:p1', c.key
         limit 1;
    end if;
    return jsonb_build_object('poster', v_key, 'poster_stock', v_stock, 'poster_fete', null);
end;
$$;

revoke execute on function event_preview_slot(text, text, text) from public;
revoke execute on function event_preview_done(text, text, integer) from public;
revoke execute on function event_preview_of(text, text) from public;
revoke execute on function street_event_picture(events) from public;
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function event_preview_slot(text, text, text) to anon;
        grant execute on function event_preview_done(text, text, integer) to anon;
        grant execute on function event_preview_of(text, text) to anon;
        revoke execute on function street_event_picture(events) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function event_preview_slot(text, text, text) to authenticated;
        grant execute on function event_preview_done(text, text, integer) to authenticated;
        grant execute on function event_preview_of(text, text) to authenticated;
        revoke execute on function street_event_picture(events) from authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
