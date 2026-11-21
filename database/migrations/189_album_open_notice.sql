-- ============================================================
-- 189 — The guests hear that the album is open.
--
-- The owner, on « Phanuel & Espérance »: « What time will people of this
-- event receive notification that they can add pictures? » — none did.
-- The album opens on its first day (184), the button in « Mes
-- invitations » turns on, and nobody is told; only the organiser had a
-- message, the day before (159).
--
--   * events.album_announced_at: told once, per card.
--   * events_album_tick() (pg_cron, every hour): a published card, not
--     cancelled, with its album on, whose album is open today on its own
--     clock and it is 9 h there or later, not told yet — each guest who
--     confirmed with an account gets one bell: « L'album de « … » est
--     ouvert : ajoutez vos photos jusqu'au samedi 28 novembre. »
--   * The bell is the guest's confirmation's kind (183,
--     event_presence_guest): every phone already installed opens « Mes
--     invitations » on a tap, and a guest's « bookings » switch governs
--     it, as the confirmation. No app update.
--   * On install, the cards whose album opened before today are counted
--     told (no late bells for past events), and those already told by
--     hand (params.album = 'open').
--
-- Shop, farm, association: none of them has cards; nothing changes there.
-- Applies twice.
-- ============================================================

do $$ begin
    if to_regprocedure('event_album_opens(events)') is null or to_regprocedure('event_local_date(timestamp with time zone, text)') is null then
        raise exception '189 needs 159 and 184 applied first';
    end if;
end $$;

alter table events add column if not exists album_announced_at timestamptz;

-- The hour on the card's clock, as 159's day: an offset, a zone, Ouagadougou.
create or replace function event_local_time(p_at timestamptz, p_tz text)
returns timestamp
language plpgsql
immutable
set search_path = public
as $$
declare
    v_tz text := nullif(trim(coalesce(p_tz, '')), '');
begin
    if p_at is null then
        return null;
    end if;
    if v_tz ~ '^[+-][0-9]{2}:[0-9]{2}$' then
        return (p_at + (v_tz || ':00')::interval) at time zone 'UTC';
    end if;
    begin
        return p_at at time zone coalesce(v_tz, 'Africa/Ouagadougou');
    exception when others then
        return p_at at time zone 'Africa/Ouagadougou';
    end;
end;
$$;

-- « samedi 28 novembre »
create or replace function fr_day_month(p_day date)
returns text
language sql
immutable
set search_path = public
as $$
    select (array['dimanche','lundi','mardi','mercredi','jeudi','vendredi','samedi'])[extract(dow from p_day)::int + 1]
        || ' ' || extract(day from p_day)::int
        || ' ' || (array['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'])[extract(month from p_day)::int];
$$;

create or replace function events_album_tick()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    e events;
    v_n integer := 0;
    v_today date;
begin
    for e in
        select ev.*
          from events ev
         where ev.published
           and ev.album_on
           and ev.cancelled_at is null
           and ev.album_announced_at is null
           and event_album_opens(ev) is not null
           and event_album_allowed(ev.org_id)   -- 182: a free business's album is shut
         order by ev.starts_at
         for update skip locked
    loop
        v_today := event_local_date(now(), e.tz);
        continue when v_today < event_album_opens(e) or v_today > event_album_closes(e);
        continue when extract(hour from event_local_time(now(), e.tz)) < 9;

        insert into notifications (recipient_id, org_id, kind, message, params)
        select distinct r.user_id, null::uuid, 'event_presence_guest',
               'L''album de « ' || e.title || ' » est ouvert : ajoutez vos photos jusqu''au '
                   || fr_day_month(event_album_closes(e)) || '.',
               jsonb_build_object('to', 'customer', 'event_id', e.id, 'slug', e.slug, 'title', e.title,
                                  'album', 'open', 'until', event_album_closes(e))
          from event_rsvps r
         where r.event_id = e.id
           and r.answer = 'oui'
           and r.user_id is not null
           and exists (select 1 from profiles p where p.id = r.user_id);

        update events set album_announced_at = now() where id = e.id;
        v_n := v_n + 1;
    end loop;
    return v_n;
end;
$$;

-- On install: past albums, and those told by hand, count as told.
update events ev
   set album_announced_at = coalesce(
           (select min(n.created_at) from notifications n
             where n.kind = 'event_presence_guest' and n.params ->> 'album' = 'open'
               and n.params ->> 'event_id' = ev.id::text),
           now())
 where ev.album_announced_at is null
   and (event_album_opens(ev) < event_local_date(now(), ev.tz)
        or exists (select 1 from notifications n
                    where n.kind = 'event_presence_guest' and n.params ->> 'album' = 'open'
                      and n.params ->> 'event_id' = ev.id::text));

revoke execute on function events_album_tick() from public;
revoke execute on function event_local_time(timestamptz, text) from public;
revoke execute on function fr_day_month(date) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function events_album_tick() from anon;
        revoke execute on function event_local_time(timestamptz, text) from anon;
        revoke execute on function fr_day_month(date) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function events_album_tick() from authenticated;
    end if;
end $$;

-- Every hour (each card's 9 h comes on its own clock)
do $$
begin
    if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
        begin
            create extension if not exists pg_cron;
            if not exists (select 1 from cron.job where jobname = 'events-album-open') then
                perform cron.schedule('events-album-open', '7 * * * *', 'select public.events_album_tick()');
            end if;
        exception when others then
            raise notice 'pg_cron not scheduled here: %', sqlerrm;
        end;
    end if;
end $$;

notify pgrst, 'reload schema';
