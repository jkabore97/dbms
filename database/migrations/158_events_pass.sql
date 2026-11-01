-- ============================================================
-- 158 — A real guest pass.
--
-- The animated card drew a QR code after « Je viens » that said nothing
-- the door could check (« MARAKAJ-EVENT|demo|name »); the classic cards
-- drew none. The answer's own row is the pass now: its id (unguessable)
-- opens /e/<slug>/invite/<id> on the site — the guest's name, how many
-- they come with, the event, the day, the place, and whether they have
-- arrived — through event_pass, which the street calls with the id as
-- the key. The organiser marks an arrival from the app (event_rsvps.
-- arrived_at, written by the business's admins only, the module open),
-- by scanning the guest's QR or by a tap on the guest's line. For a
-- shop, a farm or an association: nothing — the passes are an
-- Événementiel's. Applies twice.
-- ============================================================

do $$ begin
    if to_regclass('event_rsvps') is null or to_regprocedure('event_date_fr(timestamptz, text)') is null then
        raise exception '158 needs 152 (event_rsvps) and 153 (event_date_fr) applied first';
    end if;
end $$;

alter table event_rsvps add column if not exists arrived_at timestamptz;

-- The pass, read by whoever holds its id: no token, no session. DEFINER on
-- purpose — the street reads no table of the module directly; the id is
-- the key, as the preview token is a card's.
create or replace function event_pass(p_slug text, p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'id', r.id,
        'name', r.name,
        'people', r.people,
        'answer', r.answer,
        'arrived_at', r.arrived_at,
        'title', e.title,
        'date_fr', case when e.starts_at is null then null else event_date_fr(e.starts_at, e.tz) end,
        'starts_at', e.starts_at,
        'place', e.place,
        'tz', e.tz,
        'org_name', (select o.name from orgs o where o.id = e.org_id)
    )
    from event_rsvps r
    join events e on e.id = r.event_id
    where r.id = p_id
      and e.slug = lower(trim(coalesce(p_slug, '')));
$$;

revoke execute on function event_pass(text, uuid) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function event_pass(text, uuid) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function event_pass(text, uuid) to authenticated;
        -- The arrival mark, and nothing else of the answer, from the app.
        grant update (arrived_at) on event_rsvps to authenticated;
    end if;
end $$;

drop policy if exists "rsvps marked arrived by the business's admins" on event_rsvps;
create policy "rsvps marked arrived by the business's admins"
on event_rsvps for update
using (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)))
with check (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)));

notify pgrst, 'reload schema';
