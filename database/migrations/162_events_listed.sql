-- ============================================================
-- 162 — Public events on the street (batch 162).
--
-- The owner: an event shown « privé » keeps its link for its guests; one
-- shown « public » stands on Marakaj's street, in its own « Événements »
-- section — not mixed with the shops — and leaves it once past. No
-- approval by Marakaj: the organiser chooses; « Signaler » stays.
--
--   * events.listed: the organiser's choice, only for a published card.
--   * street_events(): the street's list, for anybody — published, listed,
--     dated, not yet over (six hours after its start), its business not
--     suspended; the poster (the card's main picture), the date in
--     French, the place, the business, and whether it sells tickets and
--     from what price.
--   * street_event(slug): one, for its page on the street — the same, with
--     the ticket types and places left when it sells.
--
-- Free and paid alike may be listed: selling tickets is Marakaj Pro's
-- already (161). For a shop, a farm or an association: nothing — the
-- list is of events. Applies twice.
-- ============================================================

do $$ begin
    if to_regprocedure('event_ticket_offer(text, text)') is null then
        raise exception '162 needs 161 applied first';
    end if;
end $$;

alter table events add column if not exists listed boolean not null default false;
create index if not exists events_listed_idx on events (starts_at) where listed and published;

-- A card unpublished leaves the street with it.
create or replace function events_listed_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    if not new.published then
        new.listed := false;
    end if;
    return new;
end;
$$;
revoke execute on function events_listed_guard() from public;
drop trigger if exists events_listed_guard on events;
create trigger events_listed_guard before insert or update of published, listed on events
    for each row execute function events_listed_guard();

-- What the street shows of one event.
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
        'poster', nullif(e.content -> 'p:hero' ->> 'key', ''),
        'tickets', e.tickets_on and event_tickets_allowed(e.org_id),
        'from_price', case when e.tickets_on and event_tickets_allowed(e.org_id)
                           then (select min(t.price) from event_ticket_types t where t.event_id = e.id and t.active) end,
        'currency', coalesce(o.default_currency, 'XOF'))
      from orgs o where o.id = e.org_id;
$$;
revoke execute on function street_event_row(events) from public;

create or replace function street_events()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(jsonb_agg(street_event_row(e) order by e.starts_at), '[]'::jsonb)
      from (select e.* from events e join orgs o on o.id = e.org_id
             where e.listed and e.published and e.starts_at is not null
               and e.starts_at > now() - interval '6 hours'
               and o.suspended_at is null
             order by e.starts_at
             limit 60) e;
$$;

create or replace function street_event(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select street_event_row(e) || jsonb_build_object(
               'pay_whatsapp', e.pay_whatsapp,
               'offer', case when e.tickets_on and event_tickets_allowed(e.org_id)
                             then event_ticket_offer(e.slug, null) end)
      from events e join orgs o on o.id = e.org_id
     where e.slug = lower(trim(coalesce(p_slug, '')))
       and e.listed and e.published and e.starts_at is not null
       and e.starts_at > now() - interval '6 hours'
       and o.suspended_at is null;
$$;

revoke execute on function street_events() from public;
revoke execute on function street_event(text) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function street_event_row(events) from anon;
        revoke execute on function events_listed_guard() from anon;
        grant execute on function street_events() to anon;
        grant execute on function street_event(text) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function street_events() to authenticated;
        grant execute on function street_event(text) to authenticated;
        grant update (listed) on events to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
