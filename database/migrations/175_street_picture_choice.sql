-- ============================================================
-- 175 — The organiser chooses the event's picture on the street.
--
-- The owner, after 174's pictures: « might be a good idea to allow them to
-- put their own image or choose between those you generated ».
--
-- events.street_picture: null — automatic, as 174 (the card's own photo,
-- else its bank photo, else the picture of its kind); 'fete:<name>' — a
-- picture of Marakaj's gallery (/cartes/fetes/<name>.jpg); or the key of
-- one of the card's own stored pictures. Written by the business's admins
-- under events' own policy (the column's update granted, as 162's
-- 'listed'). street_event_picture reads it first: a gallery picture comes
-- back as 'poster_fete'; a key counts only while it is a stored picture of
-- this very event — else the automatic choice, so a picture removed later
-- never leaves the tile empty.
--
-- For a shop, a farm and an association: nothing (an Événementiel's public
-- events only). Applies twice.
-- ============================================================

alter table events add column if not exists street_picture text;
alter table events drop constraint if exists events_street_picture_check;
alter table events add constraint events_street_picture_check check (
    street_picture is null
    or street_picture ~ '^fete:[a-z0-9-]{1,40}$'
    or street_picture ~ '^events/[0-9a-f-]{36}/[0-9a-f]{32}\.[a-z0-9]{2,5}$');

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

revoke execute on function street_event_picture(events) from public;
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function street_event_picture(events) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function street_event_picture(events) from authenticated;
        grant update (street_picture) on events to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
