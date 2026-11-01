-- ============================================================
-- 159 — The reminder the day before.
--
-- The classic card's thanks promised « un rappel la veille » and nobody
-- sent one. Marakaj holds no guest's number by itself; the guests may
-- leave their WhatsApp with their answer now (extra.whatsapp, 152's
-- extra), and the organiser gets the reminder: the day before a
-- published card's event, its business's admins are told how many said
-- yes, how many people, how many left a number — and « Rappelez-les
-- depuis Invités », where each guest with a number has a WhatsApp button
-- with the reminder written. Once per event (events.reminded_at); a
-- card made for tomorrow after the morning's tick is caught by the
-- evening's. For a shop, a farm or an association: nothing — the cards
-- are an Événementiel's. Applies twice.
-- ============================================================

do $$ begin
    if to_regclass('event_rsvps') is null or to_regprocedure('notify_org_admins(uuid, text, text, jsonb, uuid)') is null then
        raise exception '159 needs 152 (events) and 099 (notify_org_admins) applied first';
    end if;
end $$;

alter table events add column if not exists reminded_at timestamptz;

-- The day of a moment on the event's clock: a zone's name, or the offset
-- the phone gave (153), or Ouagadougou's.
create or replace function event_local_date(p_at timestamptz, p_tz text)
returns date
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
        return (p_at + (v_tz || ':00')::interval)::date;
    end if;
    begin
        return (p_at at time zone coalesce(v_tz, 'Africa/Ouagadougou'))::date;
    exception when others then
        return (p_at at time zone 'Africa/Ouagadougou')::date;
    end;
end;
$$;

revoke execute on function event_local_date(timestamptz, text) from public;

-- The tick (pg_cron, twice a day): every published card whose event is
-- tomorrow on its own clock, not reminded yet, tells its admins. Returns
-- how many were told.
create or replace function events_tomorrow_tick()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    e events;
    v_n integer := 0;
    v_yes integer;
    v_people integer;
    v_wa integer;
begin
    for e in
        select ev.*
          from events ev
         where ev.published
           and ev.reminded_at is null
           and ev.starts_at is not null
           and event_local_date(ev.starts_at, ev.tz) = event_local_date(now(), ev.tz) + 1
         order by ev.starts_at
         for update skip locked
    loop
        select count(*) filter (where r.answer = 'oui'),
               coalesce(sum(r.people) filter (where r.answer = 'oui'), 0),
               count(*) filter (where r.answer = 'oui' and nullif(trim(r.extra ->> 'whatsapp'), '') is not null)
          into v_yes, v_people, v_wa
          from event_rsvps r
         where r.event_id = e.id;
        perform notify_org_admins(
            e.org_id,
            'event_tomorrow',
            'Demain : « ' || e.title || ' » — ' || v_yes || ' invité' || case when v_yes = 1 then '' else 's' end
                || ' ont dit oui (' || v_people || ' personne' || case when v_people = 1 then '' else 's' end || '). Rappelez-les depuis Invités.',
            jsonb_build_object('to', 'shop', 'event_id', e.id, 'slug', e.slug, 'title', e.title, 'yes', v_yes, 'people', v_people, 'whatsapp', v_wa),
            null);
        update events set reminded_at = now() where id = e.id;
        v_n := v_n + 1;
    end loop;
    return v_n;
end;
$$;

revoke execute on function events_tomorrow_tick() from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function events_tomorrow_tick() from anon;
        revoke execute on function event_local_date(timestamptz, text) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function events_tomorrow_tick() from authenticated;
    end if;
end $$;

-- ------------------------------------------------------------
-- The clock, morning and evening on Ouagadougou's time (where pg_cron is)
-- ------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
        begin
            create extension if not exists pg_cron;
            if not exists (select 1 from cron.job where jobname = 'events-tomorrow') then
                perform cron.schedule('events-tomorrow', '0 9,18 * * *', 'select public.events_tomorrow_tick()');
            end if;
        exception when others then
            raise notice 'pg_cron not scheduled here: %', sqlerrm;
        end;
    end if;
end $$;

notify pgrst, 'reload schema';
