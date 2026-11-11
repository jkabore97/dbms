-- ============================================================
-- 174 — The street's events show the card's own picture.
--
-- The owner, looking at the street's « Événements »: « you really need to
-- find and put a nice preview for events ». The tile read one slot only
-- (content p:hero, the first classic cards'), so a card made in Studio, or
-- whose photo sits in another slot, showed a grey party icon.
--
-- street_event_row: 'poster' is now the card's own photo, wherever it is —
-- a Studio card's cover first, then its other blocks (the guests' view:
-- hidden blocks left out), then the classic card's p:hero, p:p1 and any
-- other p:<slot> — a stored picture only (154). 'poster_stock' is a photo
-- of the bank when that is all the card has. With neither, the app draws
-- the card's design (its preview, softened) with the event's own day.
--
-- For a shop, a farm and an association: nothing (an Événementiel's public
-- events only). Applies twice.
-- ============================================================

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
    return jsonb_build_object('poster', v_key, 'poster_stock', v_stock);
end;
$$;

create or replace function street_event_row(e events)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'slug', e.slug,
        'title', e.title,
        'kind', e.kind,
        'card', e.card,
        'starts_at', e.starts_at,
        'date_fr', event_date_fr(e.starts_at, e.tz),
        'place', e.place,
        'org_name', o.name,
        'tickets', e.tickets_on and event_tickets_allowed(e.org_id),
        'from_price', case when e.tickets_on and event_tickets_allowed(e.org_id)
                           then (select min(t.price) from event_ticket_types t where t.event_id = e.id and t.active) end,
        'currency', coalesce(o.default_currency, 'XOF'),
        'sponsored', event_sponsored(e.org_id)) || street_event_picture(e)
      from orgs o where o.id = e.org_id;
$$;

revoke execute on function street_event_picture(events) from public;
revoke execute on function street_event_row(events) from public;
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function street_event_picture(events) from anon;
        revoke execute on function street_event_row(events) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function street_event_picture(events) from authenticated;
        revoke execute on function street_event_row(events) from authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
