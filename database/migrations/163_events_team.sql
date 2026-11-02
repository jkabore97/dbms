-- ============================================================
-- 163 — An event's team, its accounts and its journal (ticket sales,
-- part 3, batch 163).
--
-- The owner: « équipe, rôles et accès, et redevabilité » — who sold, who
-- validated, who let in, and the money each one holds.
--
--   * event_staff: a member of the business given a role on one event —
--     billetterie (validates the payments, refunds, sells at the door),
--     controle (scans at the door, nothing else), lecture (reads the
--     figures). The business's admins keep everything. A team on an event
--     is Marakaj Pro's, as the sale itself.
--   * event_ticket_can() reads it; the team reads the requests and the
--     tickets of its event, never another's.
--   * event_ticket_log: the journal — each request validated, refused,
--     refunded, each ticket let in or cancelled, by whom and when; written
--     by triggers, so no door forgets it.
--   * event_ticket_refund: a paid request refunded, its tickets cancelled,
--     and a reversal in the books (« Billetterie », out).
--   * event_ticket_door_sale: a ticket sold at the door for cash — let in
--     at once, the money in the books, counted to the agent who took it.
--   * event_ticket_report: sold per type, expected and validated, refunded,
--     who validated what, the door's cash per agent, who let in how many.
--   * event_cancel: the event cancelled — its sale closed, off the street,
--     and the holders listed for the organiser to write to.
--   * my_event_staff: the events a member works on, for their home.
--
-- For a shop, a farm or an association: nothing — the team is an event's.
-- Applies twice.
-- ============================================================

do $$ begin
    if to_regprocedure('street_events()') is null then
        raise exception '163 needs 162 applied first';
    end if;
end $$;

-- An event cancelled (section 3), read from the start.
alter table events add column if not exists cancelled_at timestamptz;
alter table events add column if not exists cancel_reason text;
do $$ begin
    alter table events drop constraint if exists events_cancel_reason_check;
    alter table events add constraint events_cancel_reason_check check (cancel_reason is null or length(cancel_reason) <= 300);
end $$;

-- ------------------------------------------------------------
-- 1. The team
-- ------------------------------------------------------------
create table if not exists event_staff (
    event_id   uuid not null references events(id) on delete cascade,
    user_id    uuid not null references auth.users(id) on delete cascade,
    role       text not null check (role in ('billetterie', 'controle', 'lecture')),
    added_by   uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now(),
    primary key (event_id, user_id)
);
create index if not exists event_staff_user_idx on event_staff (user_id);
alter table event_staff enable row level security;

drop policy if exists "event team seen by the business's admins and by its members" on event_staff;
create policy "event team seen by the business's admins and by its members" on event_staff for select
using (user_id = auth.uid() or exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)));

-- Only a member of the business, only on a Pro sale, only by its admins.
create or replace function event_staff_set(p_event uuid, p_user uuid, p_role text)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    e events;
begin
    select * into e from events where id = p_event;
    if not found or auth.uid() is null or not is_org_admin(e.org_id) then
        raise exception 'Seuls les administrateurs composent l''équipe d''un événement.';
    end if;
    if not event_tickets_allowed(e.org_id) then
        raise exception 'Marakaj Pro : l''équipe d''un événement fait partie de Marakaj Pro. Ouvrez Compte › Marakaj Pro.';
    end if;
    if p_role is null then
        delete from event_staff where event_id = e.id and user_id = p_user;
        return true;
    end if;
    if p_role not in ('billetterie', 'controle', 'lecture') then
        raise exception 'Rôle inconnu.';
    end if;
    if not exists (select 1 from memberships m where m.org_id = e.org_id and m.user_id = p_user) then
        raise exception 'Cette personne n''est pas membre de l''activité : invitez-la d''abord dans l''équipe.';
    end if;
    insert into event_staff (event_id, user_id, role, added_by) values (e.id, p_user, p_role, auth.uid())
    on conflict (event_id, user_id) do update set role = excluded.role, added_by = excluded.added_by;
    return true;
end;
$$;

-- The business's members, to choose from, with their role on this event.
create or replace function event_team(p_event uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    e events;
begin
    select * into e from events where id = p_event;
    if not found or auth.uid() is null or not is_org_admin(e.org_id) then
        raise exception 'Seuls les administrateurs composent l''équipe d''un événement.';
    end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object(
                   'user_id', m.user_id, 'name', coalesce(nullif(p.full_name, ''), p.phone, 'Membre'),
                   'phone', p.phone, 'org_role', m.role, 'event_role', s.role)
               order by s.role nulls last, p.full_name)
          from (select distinct on (user_id) user_id, role from memberships where org_id = e.org_id order by user_id, role) m
          left join profiles p on p.id = m.user_id
          left join event_staff s on s.event_id = e.id and s.user_id = m.user_id
         where m.user_id <> auth.uid()), '[]'::jsonb);
end;
$$;

-- Who may run an event's tickets: the business's admins, and its team —
-- 'sell' (validate, refuse, refund, sell at the door): billetterie;
-- 'door' (scan): billetterie and controle; 'read': the whole team.
create or replace function event_ticket_can(p_event events, p_what text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select auth.uid() is not null and (
        is_org_admin(p_event.org_id)
        or exists (select 1 from event_staff s
                    where s.event_id = p_event.id and s.user_id = auth.uid()
                      and (p_what = 'read'
                           or (p_what = 'door' and s.role in ('billetterie', 'controle'))
                           or (p_what = 'sell' and s.role = 'billetterie'))));
$$;
revoke execute on function event_ticket_can(events, text) from public;

-- The team reads its event's sale (a policy each, the admins' standing).
drop policy if exists "ticket types seen by the event's team" on event_ticket_types;
create policy "ticket types seen by the event's team" on event_ticket_types for select
using (exists (select 1 from event_staff s where s.event_id = event_ticket_types.event_id and s.user_id = auth.uid()));
drop policy if exists "ticket requests seen by the event's team" on event_ticket_requests;
create policy "ticket requests seen by the event's team" on event_ticket_requests for select
using (exists (select 1 from event_staff s where s.event_id = event_ticket_requests.event_id and s.user_id = auth.uid()
                  and s.role in ('billetterie', 'lecture')));
drop policy if exists "ticket lines seen by the event's team" on event_ticket_lines;
create policy "ticket lines seen by the event's team" on event_ticket_lines for select
using (exists (select 1 from event_ticket_requests r join event_staff s on s.event_id = r.event_id
                where r.id = event_ticket_lines.request_id and s.user_id = auth.uid() and s.role in ('billetterie', 'lecture')));

-- The events a member works on, for their home.
create or replace function my_event_staff()
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select coalesce(jsonb_agg(jsonb_build_object(
               'id', e.id, 'org_id', e.org_id, 'slug', e.slug, 'title', e.title, 'starts_at', e.starts_at,
               'place', e.place, 'role', s.role, 'cancelled', e.cancelled_at is not null)
             order by e.starts_at nulls last), '[]'::jsonb)
      from event_staff s join events e on e.id = s.event_id
     where s.user_id = auth.uid()
       and (e.starts_at is null or e.starts_at > now() - interval '2 days');
$$;

-- ------------------------------------------------------------
-- 2. The journal
-- ------------------------------------------------------------
create table if not exists event_ticket_log (
    id         bigint generated always as identity primary key,
    event_id   uuid not null references events(id) on delete cascade,
    actor      uuid references auth.users(id) on delete set null,
    action     text not null,
    request_id uuid,
    ticket_id  uuid,
    amount     numeric(14, 2),
    detail     text,
    at         timestamptz not null default now()
);
create index if not exists event_ticket_log_event_idx on event_ticket_log (event_id, at desc);
alter table event_ticket_log enable row level security;
drop policy if exists "ticket journal seen by the admins and the event's billetterie" on event_ticket_log;
create policy "ticket journal seen by the admins and the event's billetterie" on event_ticket_log for select
using (exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id))
       or exists (select 1 from event_staff s where s.event_id = event_ticket_log.event_id and s.user_id = auth.uid()
                     and s.role in ('billetterie', 'lecture')));

create or replace function event_ticket_log_request()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if new.status is distinct from old.status and new.status in ('paid', 'refused', 'refunded') then
        insert into event_ticket_log (event_id, actor, action, request_id, amount, detail)
        values (new.event_id, auth.uid(), new.status, new.id, new.total,
                new.ref || ' · ' || new.buyer_name || coalesce(' · ' || new.method, ''));
    end if;
    return new;
end;
$$;
revoke execute on function event_ticket_log_request() from public;
drop trigger if exists event_ticket_log_request on event_ticket_requests;
create trigger event_ticket_log_request after update of status on event_ticket_requests
    for each row execute function event_ticket_log_request();

create or replace function event_ticket_log_ticket()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if new.status is distinct from old.status and new.status in ('used', 'void') then
        insert into event_ticket_log (event_id, actor, action, request_id, ticket_id, detail)
        values (new.event_id, auth.uid(), case new.status when 'used' then 'entered' else 'void' end,
                new.request_id, new.id, new.holder);
    end if;
    return new;
end;
$$;
revoke execute on function event_ticket_log_ticket() from public;
drop trigger if exists event_ticket_log_ticket on event_tickets;
create trigger event_ticket_log_ticket after update of status on event_tickets
    for each row execute function event_ticket_log_ticket();

-- ------------------------------------------------------------
-- 3. Refund, the door's own sale, cancellation
-- ------------------------------------------------------------

create or replace function event_ticket_refund(p_id uuid, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    r event_ticket_requests;
    e events;
    v_entry uuid;
begin
    select * into r from event_ticket_requests where id = p_id for update;
    if not found then
        raise exception 'Demande inconnue.';
    end if;
    select * into e from events where id = r.event_id;
    if not event_ticket_can(e, 'sell') then
        raise exception 'Vous ne pouvez pas rembourser les billets de cet événement.';
    end if;
    if r.status <> 'paid' then
        raise exception 'Seule une demande payée se rembourse.';
    end if;
    if p_note is not null and length(p_note) > 300 then
        raise exception 'Une note de 300 caractères au plus.';
    end if;
    update event_tickets set status = 'void' where request_id = r.id and status <> 'void';
    update event_ticket_requests set status = 'refunded', note = coalesce(nullif(btrim(p_note), ''), note) where id = r.id;
    -- The books: the money given back, against the sale.
    if r.total > 0 then
        begin
            v_entry := record_entry(e.org_id, r.total, 'out', 'Remboursement billets ' || r.ref || ' · ' || e.title, auth.uid(),
                                    'Billetterie', coalesce(r.method, 'mobile_money'), null,
                                    r.buyer_name, jsonb_build_object('event_id', e.id, 'ticket_request', r.id, 'refund_of', r.entry_id),
                                    null, null, gen_random_uuid());
        exception when others then
            null;
        end;
    end if;
    return event_ticket_status(r.id);
end;
$$;

-- At the door, for cash: the tickets let in at once, counted to the agent.
create or replace function event_ticket_door_sale(p_event uuid, p_lines jsonb, p_name text default null,
                                                  p_whatsapp text default null, p_method text default 'cash')
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    e events;
    t event_ticket_types;
    v_line jsonb;
    v_qty integer;
    v_count integer := 0;
    v_total numeric := 0;
    v_id uuid;
    v_ref text;
    v_name text := coalesce(nullif(btrim(coalesce(p_name, '')), ''), 'Guichet');
    v_method text := coalesce(nullif(btrim(coalesce(p_method, '')), ''), 'cash');
    v_currency text;
    v_entry uuid;
    l record;
    i integer;
begin
    select * into e from events where id = p_event for update;
    if not found or not event_ticket_can(e, 'sell') then
        raise exception 'Vous ne vendez pas les billets de cet événement.';
    end if;
    if not e.tickets_on or not event_tickets_allowed(e.org_id) or e.cancelled_at is not null then
        raise exception 'Cet événement ne vend pas de billets.';
    end if;
    if length(v_name) > 80 or length(v_method) > 40 then
        raise exception 'Un nom de 80 caractères au plus.';
    end if;
    if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 or jsonb_array_length(p_lines) > 10 then
        raise exception 'Choisissez au moins un billet.';
    end if;
    update event_ticket_requests set status = 'expired'
     where event_id = e.id and status = 'pending' and hold_until <= now();
    for v_line in select * from jsonb_array_elements(p_lines) loop
        v_qty := coalesce((v_line ->> 'qty')::integer, 0);
        if v_qty < 1 or v_qty > 20 then
            raise exception 'Entre 1 et 20 billets par type.';
        end if;
        select * into t from event_ticket_types where id = (v_line ->> 'type')::uuid and event_id = e.id and active;
        if not found then
            raise exception 'Ce billet n''est plus en vente.';
        end if;
        if t.capacity is not null and event_ticket_taken(t.id) + v_qty > t.capacity then
            raise exception 'Plus assez de places en « % » : il en reste %.', t.name, greatest(t.capacity - event_ticket_taken(t.id), 0);
        end if;
        v_count := v_count + v_qty;
        v_total := v_total + v_qty * t.price;
    end loop;
    if v_count > 20 then
        raise exception 'Vingt billets au plus par vente.';
    end if;
    select coalesce(default_currency, 'XOF') into v_currency from orgs where id = e.org_id;
    loop
        v_ref := 'MK-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 5));
        exit when not exists (select 1 from event_ticket_requests where event_id = e.id and ref = v_ref);
    end loop;
    insert into event_ticket_requests (event_id, ref, buyer_name, buyer_whatsapp, total, currency, hold_until,
                                       status, method, decided_at, decided_by, note)
    values (e.id, v_ref, v_name, coalesce(nullif(btrim(coalesce(p_whatsapp, '')), ''), 'guichet'), v_total, v_currency, now(),
            'paid', v_method, now(), auth.uid(), 'Vente à l''entrée')
    returning id into v_id;
    insert into event_ticket_lines (request_id, type_id, qty, unit_price)
    select v_id, (x ->> 'type')::uuid, sum((x ->> 'qty')::integer), max(t2.price)
      from jsonb_array_elements(p_lines) x join event_ticket_types t2 on t2.id = (x ->> 'type')::uuid
     group by (x ->> 'type')::uuid;
    for l in select type_id, qty from event_ticket_lines where request_id = v_id loop
        for i in 1 .. l.qty loop
            insert into event_tickets (request_id, event_id, type_id, holder, status, used_at, used_by)
            values (v_id, e.id, l.type_id, v_name, 'used', now(), auth.uid());
        end loop;
    end loop;
    insert into event_ticket_log (event_id, actor, action, request_id, amount, detail)
    values (e.id, auth.uid(), 'door_sale', v_id, v_total, v_ref || ' · ' || v_count || ' · ' || v_method);
    if v_total > 0 then
        begin
            v_entry := record_entry(e.org_id, v_total, 'in', 'Billets à l''entrée ' || v_ref || ' · ' || e.title, auth.uid(),
                                    'Billetterie', v_method, null, v_name,
                                    jsonb_build_object('event_id', e.id, 'ticket_request', v_id, 'door', true), null, null, v_id);
            update event_ticket_requests set entry_id = v_entry where id = v_id;
        exception when others then
            null;
        end;
    end if;
    return jsonb_build_object('id', v_id, 'ref', v_ref, 'count', v_count, 'total', v_total, 'currency', v_currency);
end;
$$;

-- The figures of one event.
create or replace function event_ticket_report(p_event uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    e events;
begin
    select * into e from events where id = p_event;
    if not found or not event_ticket_can(e, 'read') then
        raise exception 'Vous ne voyez pas les chiffres de cet événement.';
    end if;
    return jsonb_build_object(
        'currency', (select coalesce(default_currency, 'XOF') from orgs where id = e.org_id),
        'types', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'name', t.name, 'price', t.price, 'capacity', t.capacity,
                       'sold', coalesce((select sum(l.qty) from event_ticket_lines l join event_ticket_requests r on r.id = l.request_id
                                          where l.type_id = t.id and r.status = 'paid'), 0),
                       'revenue', coalesce((select sum(l.qty * l.unit_price) from event_ticket_lines l join event_ticket_requests r on r.id = l.request_id
                                             where l.type_id = t.id and r.status = 'paid'), 0),
                       'entered', (select count(*) from event_tickets k where k.type_id = t.id and k.status = 'used'))
                   order by t.sort, t.created_at)
              from event_ticket_types t where t.event_id = e.id), '[]'::jsonb),
        'paid', (select jsonb_build_object('count', count(*), 'total', coalesce(sum(total), 0))
                   from event_ticket_requests where event_id = e.id and status = 'paid'),
        'pending', (select jsonb_build_object('count', count(*), 'total', coalesce(sum(total), 0))
                      from event_ticket_requests where event_id = e.id and status = 'pending' and hold_until > now()),
        'refunded', (select jsonb_build_object('count', count(*), 'total', coalesce(sum(total), 0))
                       from event_ticket_requests where event_id = e.id and status = 'refunded'),
        'tickets', (select count(*) from event_tickets where event_id = e.id and status <> 'void'),
        'entered', (select count(*) from event_tickets where event_id = e.id and status = 'used'),
        'agents', coalesce((
            select jsonb_agg(a order by a ->> 'name')
              from (select jsonb_build_object(
                           'user_id', u.id, 'name', coalesce(nullif(p.full_name, ''), p.phone, 'Membre'),
                           'validated', (select count(*) from event_ticket_requests r where r.event_id = e.id and r.decided_by = u.id
                                           and r.status in ('paid', 'refunded') and coalesce(r.note, '') <> 'Vente à l''entrée'),
                           'validated_total', (select coalesce(sum(total), 0) from event_ticket_requests r where r.event_id = e.id and r.decided_by = u.id
                                                 and r.status = 'paid' and coalesce(r.note, '') <> 'Vente à l''entrée'),
                           'door_sales', (select count(*) from event_ticket_requests r where r.event_id = e.id and r.decided_by = u.id
                                            and r.note = 'Vente à l''entrée' and r.status = 'paid'),
                           'door_cash', (select coalesce(sum(total), 0) from event_ticket_requests r where r.event_id = e.id and r.decided_by = u.id
                                           and r.note = 'Vente à l''entrée' and r.status = 'paid' and r.method = 'cash'),
                           'entered', (select count(*) from event_tickets k where k.event_id = e.id and k.used_by = u.id)) a
                      from (select decided_by id from event_ticket_requests where event_id = e.id and decided_by is not null
                            union select used_by from event_tickets where event_id = e.id and used_by is not null) u
                      left join profiles p on p.id = u.id) x), '[]'::jsonb)
    );
end;
$$;

-- The journal, newest first.
create or replace function event_ticket_journal(p_event uuid, p_limit integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    e events;
begin
    select * into e from events where id = p_event;
    if not found or not event_ticket_can(e, 'read') then
        raise exception 'Vous ne voyez pas le journal de cet événement.';
    end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object('at', g.at, 'action', g.action, 'amount', g.amount, 'detail', g.detail,
                                            'who', coalesce(nullif(p.full_name, ''), p.phone, '—')) order by g.at desc, g.id desc)
          from (select * from event_ticket_log where event_id = e.id order by at desc, id desc
                limit least(greatest(coalesce(p_limit, 200), 1), 1000)) g
          left join profiles p on p.id = g.actor), '[]'::jsonb);
end;
$$;

-- The event cancelled: the sale closed, off the street; the holders.
create or replace function event_ticket_holders(p_event uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    e events;
begin
    select * into e from events where id = p_event;
    if not found or not event_ticket_can(e, 'sell') then
        raise exception 'Vous ne voyez pas les acheteurs de cet événement.';
    end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'ref', r.ref, 'name', r.buyer_name, 'whatsapp', r.buyer_whatsapp,
                                            'total', r.total, 'status', event_ticket_status_of(r)) order by r.created_at)
          from event_ticket_requests r
         where r.event_id = e.id and (r.status = 'paid' or (r.status = 'pending' and r.hold_until > now()))
           and r.buyer_whatsapp <> 'guichet'), '[]'::jsonb);
end;
$$;

create or replace function event_cancel(p_event uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    e events;
begin
    select * into e from events where id = p_event for update;
    if not found or auth.uid() is null or not is_org_admin(e.org_id) then
        raise exception 'Seuls les administrateurs annulent un événement.';
    end if;
    if p_reason is not null and length(p_reason) > 300 then
        raise exception 'Une raison de 300 caractères au plus.';
    end if;
    update events set cancelled_at = coalesce(cancelled_at, now()), cancel_reason = nullif(btrim(coalesce(p_reason, '')), ''),
                      tickets_on = false, listed = false
     where id = e.id;
    insert into event_ticket_log (event_id, actor, action, detail) values (e.id, auth.uid(), 'cancelled', nullif(btrim(coalesce(p_reason, '')), ''));
    return event_ticket_holders(e.id);
end;
$$;

-- A cancelled event sells nothing more: the guard says so.
create or replace function events_tickets_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.tickets_on and (tg_op = 'INSERT' or not old.tickets_on) then
        if new.cancelled_at is not null then
            raise exception 'Cet événement est annulé : sa vente reste fermée.';
        end if;
        if not event_tickets_allowed(new.org_id) then
            raise exception 'Marakaj Pro : la billetterie fait partie de Marakaj Pro. Ouvrez Compte › Marakaj Pro.';
        end if;
    end if;
    return new;
end;
$$;
revoke execute on function events_tickets_guard() from public;

-- ------------------------------------------------------------
-- 4. Grants
-- ------------------------------------------------------------
revoke execute on function event_staff_set(uuid, uuid, text) from public;
revoke execute on function event_team(uuid) from public;
revoke execute on function my_event_staff() from public;
revoke execute on function event_ticket_refund(uuid, text) from public;
revoke execute on function event_ticket_door_sale(uuid, jsonb, text, text, text) from public;
revoke execute on function event_ticket_report(uuid) from public;
revoke execute on function event_ticket_journal(uuid, integer) from public;
revoke execute on function event_ticket_holders(uuid) from public;
revoke execute on function event_cancel(uuid, text) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function event_ticket_can(events, text) from anon;
        revoke execute on function event_ticket_log_request() from anon;
        revoke execute on function event_ticket_log_ticket() from anon;
        revoke execute on function events_tickets_guard() from anon;
        revoke all on event_staff, event_ticket_log from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function event_staff_set(uuid, uuid, text) to authenticated;
        grant execute on function event_team(uuid) to authenticated;
        grant execute on function my_event_staff() to authenticated;
        grant execute on function event_ticket_refund(uuid, text) to authenticated;
        grant execute on function event_ticket_door_sale(uuid, jsonb, text, text, text) to authenticated;
        grant execute on function event_ticket_report(uuid) to authenticated;
        grant execute on function event_ticket_journal(uuid, integer) to authenticated;
        grant execute on function event_ticket_holders(uuid) to authenticated;
        grant execute on function event_cancel(uuid, text) to authenticated;
        -- Written by the functions and the triggers alone.
        revoke all on event_staff, event_ticket_log from authenticated;
        grant select on event_staff, event_ticket_log to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
