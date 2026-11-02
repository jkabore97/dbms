-- ============================================================
-- 161 — Ticket sales, the payment outside the app (batch 161).
--
-- The owner: an artist plays in a closed hall, people buy tickets; the
-- money goes from the buyer to the organiser by Orange Money, Moov or
-- Wave — never through Marakaj — and Marakaj carries the rest: the ticket
-- types and their places, the buyer's request with a reference, the
-- organiser's validation once the money has arrived on their own phone,
-- one QR per ticket, the door.
--
--   * events: tickets_on, pay_methods (where to pay), pay_whatsapp, the
--     hold (hours an unpaid request keeps its places, 72 by default, the
--     organiser's choice from 6 to 168), sales_close_at. A ticket sale is
--     Marakaj Pro's (« someone who makes money from an event pays ») and,
--     while the platform's switch events_tickets is off, a business with
--     one of Marakaj's admins among its members only — the owner tries it
--     on an event of their own first.
--   * event_ticket_types: a name, a price, a number of places (none: no
--     limit), sold out once paid tickets and unexpired holds reach it.
--   * event_ticket_requests and their lines: who asks (a name, a WhatsApp,
--     their account when they keep the tickets in Marakaj), a reference
--     MK-XXXXX, the total, the hold's end, the buyer's transaction number;
--     pending, paid, refused, expired, refunded.
--   * event_tickets: one per seat once paid — its id the QR's key, valid
--     until scanned once.
--   * The street's doors (DEFINER, the id or the card's link the key):
--     event_ticket_offer, event_ticket_request, event_ticket_status,
--     event_ticket_txn, event_ticket_view. The business's (DEFINER, asked
--     who the caller is): event_ticket_decide, event_ticket_scan,
--     event_tickets_door. The buyer's: event_ticket_claim,
--     my_event_tickets.
--
-- Marakaj is no party to the payment: the organiser answers for every
-- sale they validate. For a shop, a farm or an association: nothing — the
-- tickets are an Événementiel's. Applies twice.
-- ============================================================

do $$ begin
    if to_regprocedure('event_visible(events, text, text)') is null or to_regprocedure('org_plan(uuid)') is null
       or to_regclass('event_rsvps') is null then
        raise exception '161 needs 152–158 and 065 applied first';
    end if;
end $$;

-- ------------------------------------------------------------
-- 1. The switch, and who may sell
-- ------------------------------------------------------------
insert into platform_settings (key, value) values ('events_tickets', 'false')
on conflict (key) do nothing;

-- Pro once the switch is on; before, a business one of Marakaj's admins
-- belongs to (the owner's own trial), Pro or not.
create or replace function event_tickets_allowed(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select (coalesce((select value from platform_settings where key = 'events_tickets') = 'true'::jsonb, false)
            and org_plan(p_org) = 'pro')
        or exists (select 1 from memberships m join profiles p on p.id = m.user_id
                    where m.org_id = p_org and p.is_platform_admin);
$$;
revoke execute on function event_tickets_allowed(uuid) from public;

-- Who may run an event's tickets: the business's admins (163 adds the
-- event's own team). p_what: 'sell' (validate, refuse), 'door' (scan),
-- 'read'.
create or replace function event_ticket_can(p_event events, p_what text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select auth.uid() is not null and is_org_admin(p_event.org_id);
$$;
revoke execute on function event_ticket_can(events, text) from public;

-- The app's question: may this business, which the caller runs, sell
-- tickets? Its own admins alone hear the answer.
create or replace function event_tickets_ready(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select auth.uid() is not null and is_org_admin(p_org) and event_tickets_allowed(p_org);
$$;
revoke execute on function event_tickets_ready(uuid) from public;

-- ------------------------------------------------------------
-- 2. The event's sale
-- ------------------------------------------------------------
alter table events add column if not exists tickets_on boolean not null default false;
alter table events add column if not exists pay_methods jsonb not null default '[]'::jsonb;
alter table events add column if not exists pay_whatsapp text;
alter table events add column if not exists hold_hours integer not null default 72;
alter table events add column if not exists sales_close_at timestamptz;
do $$ begin
    alter table events drop constraint if exists events_pay_methods_check;
    alter table events add constraint events_pay_methods_check
        check (jsonb_typeof(pay_methods) = 'array' and jsonb_array_length(pay_methods) <= 4 and length(pay_methods::text) <= 1200);
    alter table events drop constraint if exists events_pay_whatsapp_check;
    alter table events add constraint events_pay_whatsapp_check check (pay_whatsapp is null or length(pay_whatsapp) <= 24);
    alter table events drop constraint if exists events_hold_hours_check;
    alter table events add constraint events_hold_hours_check check (hold_hours between 6 and 168);
end $$;

create or replace function events_tickets_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.tickets_on and (tg_op = 'INSERT' or not old.tickets_on) and not event_tickets_allowed(new.org_id) then
        raise exception 'Marakaj Pro : la billetterie fait partie de Marakaj Pro. Ouvrez Compte › Marakaj Pro.';
    end if;
    return new;
end;
$$;
revoke execute on function events_tickets_guard() from public;
drop trigger if exists events_tickets_guard on events;
create trigger events_tickets_guard before insert or update of tickets_on on events
    for each row execute function events_tickets_guard();

create table if not exists event_ticket_types (
    id         uuid primary key default gen_random_uuid(),
    event_id   uuid not null references events(id) on delete cascade,
    name       text not null check (length(btrim(name)) between 1 and 60),
    price      numeric(14, 2) not null check (price >= 0 and price <= 100000000),
    capacity   integer check (capacity is null or capacity between 1 and 100000),
    sort       integer not null default 0,
    active     boolean not null default true,
    created_at timestamptz not null default now()
);
create index if not exists event_ticket_types_event_idx on event_ticket_types (event_id, sort);

create table if not exists event_ticket_requests (
    id             uuid primary key default gen_random_uuid(),
    event_id       uuid not null references events(id) on delete cascade,
    ref            text not null check (ref ~ '^MK-[0-9A-F]{5}$'),
    buyer_name     text not null check (length(buyer_name) between 1 and 80),
    buyer_whatsapp text not null check (length(buyer_whatsapp) between 6 and 24),
    buyer_user_id  uuid references auth.users(id) on delete set null,
    txn_ref        text check (txn_ref is null or length(txn_ref) <= 40),
    status         text not null default 'pending'
                   check (status in ('pending', 'paid', 'refused', 'expired', 'refunded')),
    total          numeric(14, 2) not null check (total >= 0),
    currency       text not null default 'XOF',
    method         text check (method is null or length(method) <= 40),
    hold_until     timestamptz not null,
    note           text check (note is null or length(note) <= 300),
    decided_at     timestamptz,
    decided_by     uuid references auth.users(id) on delete set null,
    entry_id       uuid,
    created_at     timestamptz not null default now(),
    unique (event_id, ref)
);
create index if not exists event_ticket_requests_event_idx on event_ticket_requests (event_id, created_at desc);
create index if not exists event_ticket_requests_buyer_idx on event_ticket_requests (buyer_user_id) where buyer_user_id is not null;

create table if not exists event_ticket_lines (
    request_id uuid not null references event_ticket_requests(id) on delete cascade,
    type_id    uuid not null references event_ticket_types(id) on delete restrict,
    qty        integer not null check (qty between 1 and 20),
    unit_price numeric(14, 2) not null check (unit_price >= 0),
    primary key (request_id, type_id)
);
create index if not exists event_ticket_lines_type_idx on event_ticket_lines (type_id);

create table if not exists event_tickets (
    id         uuid primary key default gen_random_uuid(),
    request_id uuid not null references event_ticket_requests(id) on delete cascade,
    event_id   uuid not null references events(id) on delete cascade,
    type_id    uuid not null references event_ticket_types(id) on delete restrict,
    holder     text not null,
    status     text not null default 'valid' check (status in ('valid', 'used', 'void')),
    used_at    timestamptz,
    used_by    uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now()
);
create index if not exists event_tickets_event_idx on event_tickets (event_id);
create index if not exists event_tickets_request_idx on event_tickets (request_id);

alter table event_ticket_types enable row level security;
alter table event_ticket_requests enable row level security;
alter table event_ticket_lines enable row level security;
alter table event_tickets enable row level security;

drop policy if exists "ticket types seen by the business's admins" on event_ticket_types;
create policy "ticket types seen by the business's admins" on event_ticket_types for select
using (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)));
drop policy if exists "ticket types written by the business's admins" on event_ticket_types;
create policy "ticket types written by the business's admins" on event_ticket_types for all
using (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)))
with check (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)));

drop policy if exists "ticket requests seen by the business's admins" on event_ticket_requests;
create policy "ticket requests seen by the business's admins" on event_ticket_requests for select
using (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)));
drop policy if exists "ticket lines seen by the business's admins" on event_ticket_lines;
create policy "ticket lines seen by the business's admins" on event_ticket_lines for select
using (events_open() and exists (select 1 from event_ticket_requests r join events e on e.id = r.event_id
                                  where r.id = request_id and is_org_admin(e.org_id)));
drop policy if exists "tickets seen by the business's admins" on event_tickets;
create policy "tickets seen by the business's admins" on event_tickets for select
using (events_open() and exists (select 1 from events e where e.id = event_id and is_org_admin(e.org_id)));

-- Places taken from a type: paid seats and unexpired holds.
create or replace function event_ticket_taken(p_type uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(sum(l.qty), 0)::integer
      from event_ticket_lines l join event_ticket_requests r on r.id = l.request_id
     where l.type_id = p_type
       and (r.status = 'paid' or (r.status = 'pending' and r.hold_until > now()));
$$;
revoke execute on function event_ticket_taken(uuid) from public;

-- An unpaid request past its hold: expired, its places back on sale.
create or replace function event_ticket_status_of(r event_ticket_requests)
returns text
language sql
stable
set search_path = public
as $$
    select case when r.status = 'pending' and r.hold_until <= now() then 'expired' else r.status end;
$$;
revoke execute on function event_ticket_status_of(event_ticket_requests) from public;

-- ------------------------------------------------------------
-- 3. The street's doors
-- ------------------------------------------------------------
create or replace function event_ticket_offer(p_slug text, p_preview text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    e events;
begin
    select * into e from events where slug = lower(trim(coalesce(p_slug, '')));
    if not found or not event_visible(e, p_preview, null) then
        return null;
    end if;
    if not e.tickets_on or not event_tickets_allowed(e.org_id) then
        return jsonb_build_object('on', false);
    end if;
    return jsonb_build_object(
        'on', true,
        'open', now() < coalesce(e.sales_close_at, e.starts_at, 'infinity'::timestamptz),
        'slug', e.slug,
        'title', e.title,
        'starts_at', e.starts_at,
        'date_fr', case when e.starts_at is null then null else event_date_fr(e.starts_at, e.tz) end,
        'place', e.place,
        'tz', e.tz,
        'card', e.card,
        'org_name', (select o.name from orgs o where o.id = e.org_id),
        'currency', (select coalesce(o.default_currency, 'XOF') from orgs o where o.id = e.org_id),
        'hold_hours', e.hold_hours,
        'pay_methods', e.pay_methods,
        'pay_whatsapp', e.pay_whatsapp,
        'types', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'id', t.id, 'name', t.name, 'price', t.price, 'capacity', t.capacity,
                       'left', case when t.capacity is null then null else greatest(t.capacity - event_ticket_taken(t.id), 0) end)
                   order by t.sort, t.created_at)
              from event_ticket_types t where t.event_id = e.id and t.active), '[]'::jsonb)
    );
end;
$$;

create or replace function event_ticket_request(
    p_slug text, p_preview text, p_name text, p_whatsapp text, p_lines jsonb, p_txn text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    e events;
    t event_ticket_types;
    v_name text := nullif(btrim(coalesce(p_name, '')), '');
    v_wa text := nullif(btrim(coalesce(p_whatsapp, '')), '');
    v_digits text := regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g');
    v_txn text := nullif(btrim(coalesce(p_txn, '')), '');
    v_line jsonb;
    v_qty integer;
    v_count integer := 0;
    v_total numeric := 0;
    v_id uuid;
    v_ref text;
    v_hold timestamptz;
    v_currency text;
begin
    select * into e from events where slug = lower(trim(coalesce(p_slug, ''))) for update;
    if not found or not event_visible(e, p_preview, null) then
        raise exception 'Cet événement n''est pas ouvert.';
    end if;
    if not e.tickets_on or not event_tickets_allowed(e.org_id) then
        raise exception 'Cet événement ne vend pas de billets.';
    end if;
    if now() >= coalesce(e.sales_close_at, e.starts_at, 'infinity'::timestamptz) then
        raise exception 'La vente des billets est terminée.';
    end if;
    if v_name is null or length(v_name) > 80 then
        raise exception 'Votre nom, en 80 caractères au plus.';
    end if;
    if v_wa is null or length(v_wa) > 24 or length(v_digits) < 6 then
        raise exception 'Votre numéro WhatsApp, pour que l''organisateur vous réponde.';
    end if;
    if v_txn is not null and length(v_txn) > 40 then
        raise exception 'Le numéro de transaction, en 40 caractères au plus.';
    end if;
    if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 or jsonb_array_length(p_lines) > 10 then
        raise exception 'Choisissez au moins un billet.';
    end if;
    -- Unpaid requests past their hold give their places back.
    update event_ticket_requests set status = 'expired'
     where event_id = e.id and status = 'pending' and hold_until <= now();
    if (select count(*) from event_ticket_requests where event_id = e.id) >= 5000 then
        raise exception 'Cet événement a reçu toutes les demandes qu''il peut tenir.';
    end if;
    if (select count(*) from event_ticket_requests
         where event_id = e.id and status = 'pending'
           and regexp_replace(buyer_whatsapp, '\D', '', 'g') = v_digits) >= 3 then
        raise exception 'Vous avez déjà trois demandes en attente : payez-les ou attendez la réponse de l''organisateur.';
    end if;
    for v_line in select * from jsonb_array_elements(p_lines) loop
        v_qty := coalesce((v_line ->> 'qty')::integer, 0);
        if v_qty < 1 or v_qty > 20 then
            raise exception 'Entre 1 et 20 billets par type.';
        end if;
        select * into t from event_ticket_types
         where id = (v_line ->> 'type')::uuid and event_id = e.id and active;
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
        raise exception 'Vingt billets au plus par demande.';
    end if;
    select coalesce(default_currency, 'XOF') into v_currency from orgs where id = e.org_id;
    loop
        v_ref := 'MK-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 5));
        exit when not exists (select 1 from event_ticket_requests where event_id = e.id and ref = v_ref);
    end loop;
    v_hold := now() + make_interval(hours => e.hold_hours);
    insert into event_ticket_requests (event_id, ref, buyer_name, buyer_whatsapp, buyer_user_id, txn_ref, total, currency, hold_until)
    values (e.id, v_ref, v_name, v_wa, auth.uid(), v_txn, v_total, v_currency, v_hold)
    returning id into v_id;
    insert into event_ticket_lines (request_id, type_id, qty, unit_price)
    select v_id, (l ->> 'type')::uuid, sum((l ->> 'qty')::integer), max(t2.price)
      from jsonb_array_elements(p_lines) l join event_ticket_types t2 on t2.id = (l ->> 'type')::uuid
     group by (l ->> 'type')::uuid;
    -- The organiser hears of it (115's bell).
    perform notify_org_admins(e.org_id, 'ticket_request',
        'Demande de billets ' || v_ref || ' : ' || v_name || ', ' || v_count || ' billet' || case when v_count > 1 then 's' else '' end || ' pour « ' || e.title || ' ».',
        jsonb_build_object('to', 'shop', 'event_id', e.id, 'request_id', v_id, 'ref', v_ref, 'name', v_name,
                           'count', v_count, 'total', v_total, 'currency', v_currency, 'title', e.title), null);
    return jsonb_build_object('id', v_id, 'ref', v_ref, 'total', v_total, 'currency', v_currency, 'hold_until', v_hold);
end;
$$;

-- The buyer's page: what they asked, where to pay while it waits, their
-- tickets once paid. The request's id is the key.
create or replace function event_ticket_status(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'id', r.id, 'ref', r.ref, 'status', event_ticket_status_of(r), 'name', r.buyer_name,
        'total', r.total, 'currency', r.currency, 'hold_until', r.hold_until, 'txn_ref', r.txn_ref,
        'slug', e.slug, 'title', e.title, 'starts_at', e.starts_at, 'tz', e.tz,
        'date_fr', case when e.starts_at is null then null else event_date_fr(e.starts_at, e.tz) end,
        'place', e.place, 'org_name', (select o.name from orgs o where o.id = e.org_id),
        'pay_methods', case when event_ticket_status_of(r) = 'pending' then e.pay_methods else '[]'::jsonb end,
        'pay_whatsapp', e.pay_whatsapp,
        'lines', coalesce((select jsonb_agg(jsonb_build_object('name', t.name, 'qty', l.qty, 'price', l.unit_price) order by t.sort)
                             from event_ticket_lines l join event_ticket_types t on t.id = l.type_id
                            where l.request_id = r.id), '[]'::jsonb),
        'tickets', case when r.status = 'paid' then coalesce((
                     select jsonb_agg(jsonb_build_object('id', k.id, 'type', t.name, 'holder', k.holder, 'status', k.status)
                                      order by t.sort, k.created_at)
                       from event_tickets k join event_ticket_types t on t.id = k.type_id
                      where k.request_id = r.id), '[]'::jsonb) else '[]'::jsonb end)
      from event_ticket_requests r join events e on e.id = r.event_id
     where r.id = p_id;
$$;

create or replace function event_ticket_txn(p_id uuid, p_txn text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_txn text := nullif(btrim(coalesce(p_txn, '')), '');
    v_n integer;
begin
    if v_txn is null or length(v_txn) > 40 then
        raise exception 'Le numéro de transaction, en 40 caractères au plus.';
    end if;
    update event_ticket_requests set txn_ref = v_txn
     where id = p_id and status = 'pending' and hold_until > now();
    get diagnostics v_n = row_count;
    if v_n = 0 then
        raise exception 'Cette demande n''attend plus de paiement.';
    end if;
    return true;
end;
$$;

-- One ticket, as its QR opens it: whose, which, valid or used.
create or replace function event_ticket_view(p_slug text, p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object('id', k.id, 'holder', k.holder, 'type', t.name, 'status', k.status, 'used_at', k.used_at,
                              'title', e.title, 'place', e.place, 'tz', e.tz,
                              'date_fr', case when e.starts_at is null then null else event_date_fr(e.starts_at, e.tz) end,
                              'ref', r.ref, 'request_id', r.id)
      from event_tickets k join event_ticket_types t on t.id = k.type_id
      join events e on e.id = k.event_id join event_ticket_requests r on r.id = k.request_id
     where k.id = p_id and e.slug = lower(trim(coalesce(p_slug, '')));
$$;

-- ------------------------------------------------------------
-- 4. The business's side
-- ------------------------------------------------------------
-- Paid: one ticket per seat, the money in the books (Billetterie). The
-- organiser has seen it arrive on their own phone: Marakaj never says so
-- by itself. Refused: the places go back on sale.
create or replace function event_ticket_decide(p_id uuid, p_paid boolean, p_note text default null, p_method text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    r event_ticket_requests;
    e events;
    l record;
    i integer;
    v_entry uuid;
    v_status text;
    v_method text := nullif(btrim(coalesce(p_method, '')), '');
begin
    select * into r from event_ticket_requests where id = p_id;
    if not found then
        raise exception 'Demande inconnue.';
    end if;
    select * into e from events where id = r.event_id for update;
    if not event_ticket_can(e, 'sell') then
        raise exception 'Vous ne pouvez pas valider les billets de cet événement.';
    end if;
    select * into r from event_ticket_requests where id = p_id for update;
    v_status := event_ticket_status_of(r);
    if v_status not in ('pending', 'expired') then
        raise exception 'Cette demande est déjà traitée.';
    end if;
    if p_note is not null and length(p_note) > 300 then
        raise exception 'Une note de 300 caractères au plus.';
    end if;
    if not p_paid then
        update event_ticket_requests set status = 'refused', note = nullif(btrim(p_note), ''),
               decided_at = now(), decided_by = auth.uid() where id = r.id;
        return event_ticket_status(r.id);
    end if;
    -- Paid late, after the hold: only while the places are still there.
    if v_status = 'expired' then
        for l in select l2.qty, t.capacity, t.id, t.name from event_ticket_lines l2 join event_ticket_types t on t.id = l2.type_id
                  where l2.request_id = r.id loop
            if l.capacity is not null and event_ticket_taken(l.id) + l.qty > l.capacity then
                raise exception 'Plus assez de places en « % » pour valider cette demande expirée.', l.name;
            end if;
        end loop;
    end if;
    update event_ticket_requests set status = 'paid', note = nullif(btrim(p_note), ''),
           method = coalesce(v_method, 'mobile_money'), decided_at = now(), decided_by = auth.uid()
     where id = r.id;
    for l in select l2.type_id, l2.qty from event_ticket_lines l2 where l2.request_id = r.id loop
        for i in 1 .. l.qty loop
            insert into event_tickets (request_id, event_id, type_id, holder) values (r.id, r.event_id, l.type_id, r.buyer_name);
        end loop;
    end loop;
    -- The books: an entry the business can count. A business whose books
    -- the caller may not write keeps the sale here, booked later.
    if r.total > 0 then
        begin
            v_entry := record_entry(e.org_id, r.total, 'in', 'Billets ' || r.ref || ' · ' || e.title, auth.uid(),
                                    'Billetterie', coalesce(v_method, 'mobile_money'), null,
                                    r.buyer_name || coalesce(' · ' || r.txn_ref, ''),
                                    jsonb_build_object('event_id', e.id, 'ticket_request', r.id), null, null, r.id);
            update event_ticket_requests set entry_id = v_entry where id = r.id;
        exception when others then
            null;
        end;
    end if;
    return event_ticket_status(r.id);
end;
$$;

-- The door: a ticket scanned once.
create or replace function event_ticket_scan(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    k event_tickets;
    e events;
    v_type text;
begin
    select * into k from event_tickets where id = p_id for update;
    if not found then
        return jsonb_build_object('result', 'unknown');
    end if;
    select * into e from events where id = k.event_id;
    if not event_ticket_can(e, 'door') then
        return jsonb_build_object('result', 'unknown');
    end if;
    select name into v_type from event_ticket_types where id = k.type_id;
    if k.status = 'void' then
        return jsonb_build_object('result', 'void', 'holder', k.holder, 'type', v_type, 'title', e.title);
    end if;
    if k.status = 'used' then
        return jsonb_build_object('result', 'used', 'holder', k.holder, 'type', v_type, 'used_at', k.used_at, 'title', e.title);
    end if;
    update event_tickets set status = 'used', used_at = now(), used_by = auth.uid() where id = k.id;
    return jsonb_build_object('result', 'valid', 'holder', k.holder, 'type', v_type, 'title', e.title, 'event_id', e.id);
end;
$$;

-- The door's list, for a hall with no signal: every ticket of the event,
-- downloaded before the doors open.
create or replace function event_tickets_door(p_event uuid)
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
    if not found or not event_ticket_can(e, 'door') then
        raise exception 'Vous ne contrôlez pas l''entrée de cet événement.';
    end if;
    return coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'holder', k.holder, 'type', t.name, 'status', k.status, 'used_at', k.used_at))
                       from event_tickets k join event_ticket_types t on t.id = k.type_id where k.event_id = e.id), '[]'::jsonb);
end;
$$;

-- Scans made with no signal, sent once back online: each applied as if
-- scanned then; a ticket used twice in the hall is reported.
create or replace function event_tickets_door_sync(p_event uuid, p_scans jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    e events;
    s jsonb;
    v_out jsonb := '[]'::jsonb;
    v_n integer;
begin
    select * into e from events where id = p_event;
    if not found or not event_ticket_can(e, 'door') then
        raise exception 'Vous ne contrôlez pas l''entrée de cet événement.';
    end if;
    if p_scans is null or jsonb_typeof(p_scans) <> 'array' or jsonb_array_length(p_scans) > 5000 then
        raise exception 'Scans mal formés.';
    end if;
    for s in select * from jsonb_array_elements(p_scans) loop
        update event_tickets set status = 'used',
               used_at = coalesce((s ->> 'at')::timestamptz, now()), used_by = auth.uid()
         where id = (s ->> 'id')::uuid and event_id = e.id and status = 'valid';
        get diagnostics v_n = row_count;
        v_out := v_out || jsonb_build_object('id', s ->> 'id', 'applied', v_n = 1);
    end loop;
    return v_out;
end;
$$;

-- ------------------------------------------------------------
-- 5. The buyer's own
-- ------------------------------------------------------------
-- « Garder mes billets dans Marakaj »: the request joins the signed-in
-- person's account, unless someone else's account holds it already.
create or replace function event_ticket_claim(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_n integer;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous pour garder vos billets.';
    end if;
    update event_ticket_requests set buyer_user_id = auth.uid()
     where id = p_id and (buyer_user_id is null or buyer_user_id = auth.uid());
    get diagnostics v_n = row_count;
    return v_n = 1;
end;
$$;

-- The person's tickets for events still to come (and the day just past).
create or replace function my_event_tickets()
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select coalesce(jsonb_agg(event_ticket_status(r.id) order by e.starts_at nulls last), '[]'::jsonb)
      from event_ticket_requests r join events e on e.id = r.event_id
     where r.buyer_user_id = auth.uid()
       and r.status in ('pending', 'paid')
       and (e.starts_at is null or e.starts_at > now() - interval '1 day');
$$;

-- ------------------------------------------------------------
-- 6. Grants
-- ------------------------------------------------------------
revoke execute on function event_ticket_offer(text, text) from public;
revoke execute on function event_ticket_request(text, text, text, text, jsonb, text) from public;
revoke execute on function event_ticket_status(uuid) from public;
revoke execute on function event_ticket_txn(uuid, text) from public;
revoke execute on function event_ticket_view(text, uuid) from public;
revoke execute on function event_ticket_decide(uuid, boolean, text, text) from public;
revoke execute on function event_ticket_scan(uuid) from public;
revoke execute on function event_tickets_door(uuid) from public;
revoke execute on function event_tickets_door_sync(uuid, jsonb) from public;
revoke execute on function event_ticket_claim(uuid) from public;
revoke execute on function my_event_tickets() from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function event_tickets_allowed(uuid) from anon;
        revoke execute on function event_ticket_can(events, text) from anon;
        revoke execute on function event_tickets_ready(uuid) from anon;
        revoke execute on function event_ticket_taken(uuid) from anon;
        revoke execute on function events_tickets_guard() from anon;
        revoke execute on function event_ticket_status_of(event_ticket_requests) from anon;
        -- Supabase's default rights on a new table are wide: the street
        -- reaches tickets only through the functions above.
        revoke all on event_ticket_types, event_ticket_requests, event_ticket_lines, event_tickets from anon;
        grant execute on function event_ticket_offer(text, text) to anon;
        grant execute on function event_ticket_request(text, text, text, text, jsonb, text) to anon;
        grant execute on function event_ticket_status(uuid) to anon;
        grant execute on function event_ticket_txn(uuid, text) to anon;
        grant execute on function event_ticket_view(text, uuid) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function event_ticket_offer(text, text) to authenticated;
        grant execute on function event_ticket_request(text, text, text, text, jsonb, text) to authenticated;
        grant execute on function event_ticket_status(uuid) to authenticated;
        grant execute on function event_ticket_txn(uuid, text) to authenticated;
        grant execute on function event_ticket_view(text, uuid) to authenticated;
        grant execute on function event_ticket_decide(uuid, boolean, text, text) to authenticated;
        grant execute on function event_ticket_scan(uuid) to authenticated;
        grant execute on function event_tickets_door(uuid) to authenticated;
        grant execute on function event_tickets_door_sync(uuid, jsonb) to authenticated;
        grant execute on function event_ticket_claim(uuid) to authenticated;
        grant execute on function my_event_tickets() to authenticated;
        grant execute on function event_tickets_ready(uuid) to authenticated;
        -- Requests and tickets are written by the functions alone.
        revoke all on event_ticket_requests, event_ticket_lines, event_tickets from authenticated;
        -- The organiser lays out the sale from the app (RLS: its admins).
        grant select, insert, update, delete on event_ticket_types to authenticated;
        grant select on event_ticket_requests, event_ticket_lines, event_tickets to authenticated;
        grant update (tickets_on, pay_methods, pay_whatsapp, hold_hours, sales_close_at) on events to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
