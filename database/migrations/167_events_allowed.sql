-- ============================================================
-- 167 — An Événementiel allowed one by one (batch 167).
--
-- The owner: « Mariage Phanuel & Esperance » was made on Nov 1 while the
-- platform's switch (152, events_public) was on. With the switch off, its
-- admin could no longer change anything — every write refused by
-- events_open() (« Vous n'avez pas le droit de faire cela dans cette
-- entreprise »), while its two published cards stay open to the guests
-- (156). The owner chose to let such a business in without opening the
-- module to everyone.
--
--   * orgs.events_allowed: set by a platform admin only
--     (set_events_allowed), on an Événementiel only. orgs has no UPDATE
--     grant for the app's roles: the column cannot be set any other way.
--   * events_open(org): the switch, a platform admin, or this business
--     allowed. Every events policy now asks it of the row's own business,
--     so an allowed business opens itself and nothing else. events_open()
--     (no business) keeps its meaning: create_my_business still offers a
--     new Événementiel only with the switch on.
--   * my_events_allowed(): the caller's allowed businesses, for the app's
--     business list (session.dart shows them while the switch is off).
--   * events_allowed_orgs(): the console's list, a platform admin's only.
--
-- For a shop, a farm or an association: nothing — the flag is refused
-- anywhere but on an Événementiel, and only the events tables ask it.
-- Applies twice.
-- ============================================================

do $$ begin
    if to_regprocedure('events_open()') is null or to_regclass('event_ticket_lines') is null then
        raise exception '167 needs 152 and 161 applied first';
    end if;
end $$;

alter table orgs add column if not exists events_allowed boolean not null default false;

create or replace function events_open(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select events_open()
        or exists (select 1 from orgs o where o.id = p_org and o.events_allowed and o.profile = 'events');
$$;
revoke execute on function events_open(uuid) from public;

-- The events' policies: the row's business asked, not the platform alone.
alter policy "events seen by the business's admins" on events
    using (is_org_admin(org_id) and events_open(org_id)
           and exists (select 1 from orgs o where o.id = events.org_id and o.profile = 'events'));
alter policy "events written by the business's admins" on events
    with check (is_org_admin(org_id) and events_open(org_id)
                and exists (select 1 from orgs o where o.id = events.org_id and o.profile = 'events'));
alter policy "events changed by the business's admins" on events
    using (is_org_admin(org_id) and events_open(org_id)
           and exists (select 1 from orgs o where o.id = events.org_id and o.profile = 'events'))
    with check (is_org_admin(org_id) and events_open(org_id)
                and exists (select 1 from orgs o where o.id = events.org_id and o.profile = 'events'));
alter policy "events deleted by the business's admins" on events
    using (is_org_admin(org_id) and events_open(org_id)
           and exists (select 1 from orgs o where o.id = events.org_id and o.profile = 'events'));

alter policy "rsvps seen by the business's admins" on event_rsvps
    using (exists (select 1 from events e where e.id = event_rsvps.event_id
                    and is_org_admin(e.org_id) and events_open(e.org_id)));
alter policy "rsvps deleted by the business's admins" on event_rsvps
    using (exists (select 1 from events e where e.id = event_rsvps.event_id
                    and is_org_admin(e.org_id) and events_open(e.org_id)));
alter policy "rsvps marked arrived by the business's admins" on event_rsvps
    using (exists (select 1 from events e where e.id = event_rsvps.event_id
                    and is_org_admin(e.org_id) and events_open(e.org_id)))
    with check (exists (select 1 from events e where e.id = event_rsvps.event_id
                         and is_org_admin(e.org_id) and events_open(e.org_id)));

alter policy "pictures seen by the business's admins" on event_pictures
    using (exists (select 1 from events e where e.id = event_pictures.event_id
                    and is_org_admin(e.org_id) and events_open(e.org_id)));
alter policy "pictures removed by the business's admins" on event_pictures
    using (exists (select 1 from events e where e.id = event_pictures.event_id
                    and is_org_admin(e.org_id) and events_open(e.org_id)));

alter policy "guest photos seen by the business's admins" on event_guest_photos
    using (exists (select 1 from events e where e.id = event_guest_photos.event_id
                    and is_org_admin(e.org_id) and events_open(e.org_id)));
alter policy "guest photos judged by the business's admins" on event_guest_photos
    using (exists (select 1 from events e where e.id = event_guest_photos.event_id
                    and is_org_admin(e.org_id) and events_open(e.org_id)))
    with check (exists (select 1 from events e where e.id = event_guest_photos.event_id
                         and is_org_admin(e.org_id) and events_open(e.org_id)));
alter policy "guest photos removed by the business's admins" on event_guest_photos
    using (exists (select 1 from events e where e.id = event_guest_photos.event_id
                    and is_org_admin(e.org_id) and events_open(e.org_id)));

alter policy "ticket types seen by the business's admins" on event_ticket_types
    using (exists (select 1 from events e where e.id = event_ticket_types.event_id
                    and is_org_admin(e.org_id) and events_open(e.org_id)));
alter policy "ticket types written by the business's admins" on event_ticket_types
    using (exists (select 1 from events e where e.id = event_ticket_types.event_id
                    and is_org_admin(e.org_id) and events_open(e.org_id)))
    with check (exists (select 1 from events e where e.id = event_ticket_types.event_id
                         and is_org_admin(e.org_id) and events_open(e.org_id)));
alter policy "ticket requests seen by the business's admins" on event_ticket_requests
    using (exists (select 1 from events e where e.id = event_ticket_requests.event_id
                    and is_org_admin(e.org_id) and events_open(e.org_id)));
alter policy "ticket lines seen by the business's admins" on event_ticket_lines
    using (exists (select 1 from event_ticket_requests r join events e on e.id = r.event_id
                    where r.id = event_ticket_lines.request_id
                      and is_org_admin(e.org_id) and events_open(e.org_id)));
alter policy "tickets seen by the business's admins" on event_tickets
    using (exists (select 1 from events e where e.id = event_tickets.event_id
                    and is_org_admin(e.org_id) and events_open(e.org_id)));

-- A platform admin lets one Événementiel in, or takes it back.
create or replace function set_events_allowed(p_org uuid, p_on boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_profile text;
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Réservé aux administrateurs de Marakaj';
    end if;
    select profile::text into v_profile from orgs where id = p_org;
    if not found then
        raise exception 'Entreprise introuvable';
    end if;
    if v_profile <> 'events' and coalesce(p_on, false) then
        raise exception 'Seul un événementiel peut être autorisé';
    end if;
    update orgs set events_allowed = coalesce(p_on, false) where id = p_org;
end;
$$;
revoke execute on function set_events_allowed(uuid, boolean) from public;

-- The caller's own allowed businesses (the app's list).
create or replace function my_events_allowed()
returns uuid[]
language sql
stable
security definer
set search_path = public, auth
as $$
    select coalesce(array_agg(o.id order by o.id), '{}'::uuid[])
      from orgs o
     where o.events_allowed and o.profile = 'events'
       and exists (select 1 from memberships m where m.org_id = o.id and m.user_id = auth.uid());
$$;
revoke execute on function my_events_allowed() from public;

-- The console's list: every allowed business, for a platform admin.
create or replace function events_allowed_orgs()
returns uuid[]
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Réservé aux administrateurs de Marakaj';
    end if;
    return (select coalesce(array_agg(id order by id), '{}'::uuid[]) from orgs where events_allowed);
end;
$$;
revoke execute on function events_allowed_orgs() from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function events_open(uuid) from anon;
        revoke execute on function set_events_allowed(uuid, boolean) from anon;
        revoke execute on function my_events_allowed() from anon;
        revoke execute on function events_allowed_orgs() from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- The policies run it as the caller (CLAUDE.md): a member's door.
        grant execute on function events_open(uuid) to authenticated;
        grant execute on function set_events_allowed(uuid, boolean) to authenticated;
        grant execute on function my_events_allowed() to authenticated;
        grant execute on function events_allowed_orgs() to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
