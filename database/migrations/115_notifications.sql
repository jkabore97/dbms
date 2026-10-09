-- ============================================================
-- 115_notifications.sql — the bell that rings, everywhere, for everyone.
--
-- The investigation: the push Worker was never deployed and the database
-- never woke it; the bell's count was read once and never again; opening
-- one business's list marked every row read — the other businesses', the
-- shopper's, the courier's; shoppers and couriers had no bell; Android had
-- no closed-app ring at all; and the shopper and the courier heard about
-- only part of what happens to them. This migration is the database's
-- half of the fix (the app and workers/push are the rest):
--
--   1. Live: notifications joins the supabase_realtime publication. Realtime
--      applies the table's row-level security to every subscriber, so a
--      phone receives only rows whose recipient it is (030's policy).
--   2. Each row says whose list it belongs to — `scope`, computed from the
--      row itself: 'shop' (a business's, with its org_id), 'customer' (my
--      purchases), 'courier' (my deliveries), 'platform' (Mara's own), 'me'
--      (the account: a new device, a test). notification_counts() gives
--      the unread number of each, so each bell counts its own and the list
--      it opens marks only the rows it showed (the app, by id).
--   3. Android: push_subscriptions gains `platform` ('web' | 'android') and
--      `fcm_token`; save_fcm_token() stores a phone's token as its owner;
--      push_devices() hands both kinds to the Worker (service role only);
--      push_targets() (060) keeps answering browsers only, for an older
--      Worker.
--   4. « M'envoyer une notification test »: send_test_notification() rings
--      the caller's own devices and says how many there are — and, to the
--      platform, whether the database webhook that wakes the Worker exists.
--   5. Per-type switches: notification_prefs (the person's own) and the
--      catalog notification_types(). Every path that writes a bell row
--      meets them, because they are read by a BEFORE INSERT trigger on the
--      table: a type switched off writes nothing — no bell row and so no
--      push. Account, security and decision messages have no switch.
--   6. The shopper hears: an order refused with its reason (refuse_order;
--      orders.refusal_reason, said by decide_order), their phone verified. Already
--      written before (kept): accepted, ready, on its way, delivered,
--      booking confirmed, report answered (113), a new device (075).
--      Not done: a booking reminder the day before — a booking's date is
--      free text in its note (098), there is no date to count from.
--   7. The courier hears: their dossier received (the applicant, 112 told
--      only the platform), a new delivery near them (the shop's own
--      couriers at once, the city's couriers at once or after the shop's
--      own minutes), a shop adding them to its couriers, the shop confirming
--      the cash they handed over, and — only when they switch it on — a
--      nudge after 7 days without a delivery. Already written (kept):
--      approved / refused / new photo (112), a delivery cancelled (099).
--   8. Mara's message to businesses (072 send_platform_message, 105
--      platform_bulk) reaches « Responsables » (owners and admins, as
--      before, the default) or « Toute l'équipe » (every member), and says
--      its facts in params (099) like every other bell.
--   9. home_counts(org): the bar's numbers, what asks for action — orders
--      to answer, articles at zero or under their alert level, invoices
--      past due, credits past their due date (117's debts.due_on, read when
--      it exists), invitations not claimed, bookings to confirm, a farm's
--      supplies under their level and its open batches with nothing
--      written today. Security invoker: each person counts what their own
--      access shows them.
--
-- P1: installed, every bell row that was written is still written (no
-- switch is off but the courier's 7-day nudge, which never existed), every
-- message keeps its words, decide_order and send_platform_message keep
-- their arguments and answer as before, platform_bulk's message reaches the
-- same people. New rows are only the new events above.
--
-- Re-runnable (the bundle runs twice): columns and tables if not exists,
-- policies and triggers dropped and recreated, functions replaced; no
-- function changes its arguments (an extra defaulted one would make every
-- older call ambiguous wherever an earlier migration is run again).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Whose list a row belongs to
-- ------------------------------------------------------------
create or replace function notification_scope(p_kind text, p_org uuid, p_params jsonb)
returns text
language sql
immutable
set search_path = public
as $$
    select case
        when p_params ->> 'to' = 'platform' then 'platform'
        when p_org is null and (p_kind in ('org_application', 'courier_application')
                                or p_kind like 'spot\_%') then 'platform'
        when p_params ->> 'to' = 'courier' then 'courier'
        when p_params ->> 'to' is null
             and (p_kind like 'courier\_%'
                  or p_kind in ('delivery_available', 'delivery_cancelled')) then 'courier'
        when p_params ->> 'to' = 'customer' then 'customer'
        -- Rows written before 099 said nothing of whom: these kinds were
        -- only ever the customer's.
        when p_params ->> 'to' is null
             and p_kind in ('order_accepted', 'order_ready', 'order_picked_up',
                            'order_refused', 'order_cancelled', 'order_courier',
                            'order_in_transit') then 'customer'
        when p_params ->> 'to' = 'me' then 'me'
        when p_org is not null then 'shop'
        else 'me'
    end;
$$;

comment on function notification_scope(text, uuid, jsonb) is
    'Whose list a bell row belongs to (115): shop (with org_id), customer, '
    'courier, platform or me (the account itself, shown in every list).';

alter table notifications add column if not exists scope text
    generated always as (notification_scope(kind, org_id, params)) stored;

create index if not exists notifications_unread_by_scope
    on notifications (recipient_id, scope, org_id) where read_at is null;

-- The unread number of each list, for the signed-in person. As the caller,
-- under 030's policy: nobody counts anybody else's.
create or replace function notification_counts()
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
    with mine as (
        select n.scope, n.org_id
          from notifications n
         where n.recipient_id = auth.uid() and n.read_at is null
    )
    select jsonb_build_object(
        'orgs', coalesce((select jsonb_object_agg(x.org_id, x.n)
                            from (select org_id, count(*) as n from mine
                                   where scope = 'shop' group by org_id) x), '{}'::jsonb),
        'customer', (select count(*) from mine where scope = 'customer'),
        'courier',  (select count(*) from mine where scope = 'courier'),
        'platform', (select count(*) from mine where scope = 'platform'),
        'me',       (select count(*) from mine where scope = 'me'));
$$;

-- ------------------------------------------------------------
-- 2. Live, under the row's own security
-- ------------------------------------------------------------
-- Only on Supabase; elsewhere (CI, a local Postgres) this does nothing.
do $$
begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (select 1 from pg_publication_tables
                        where pubname = 'supabase_realtime'
                          and schemaname = 'public' and tablename = 'notifications') then
        execute 'alter publication supabase_realtime add table public.notifications';
    end if;
end $$;

-- ------------------------------------------------------------
-- 3. Android phones in the address book
-- ------------------------------------------------------------
alter table push_subscriptions add column if not exists platform text not null default 'web';
alter table push_subscriptions add column if not exists fcm_token text;
alter table push_subscriptions alter column p256dh drop not null;
alter table push_subscriptions alter column auth drop not null;
alter table push_subscriptions drop constraint if exists push_subscriptions_platform_check;
alter table push_subscriptions add constraint push_subscriptions_platform_check
    check (platform in ('web', 'android'));
-- A browser has its keys; a phone has its token.
alter table push_subscriptions drop constraint if exists push_subscriptions_shape;
alter table push_subscriptions add constraint push_subscriptions_shape
    check ((platform = 'web' and p256dh is not null and auth is not null)
        or (platform = 'android' and fcm_token is not null));

comment on column push_subscriptions.fcm_token is
    'An Android phone''s Firebase Cloud Messaging token (115); its endpoint is '
    '''fcm:'' || token, so one phone is one row.';

-- The phone says yes (Android, firebase_messaging): its token goes under the
-- signed-in account. A token that reappears under another account moves.
create or replace function save_fcm_token(p_token text, p_label text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_token text := btrim(coalesce(p_token, ''));
begin
    if auth.uid() is null then
        raise exception 'save_fcm_token() needs a signed-in caller';
    end if;
    if v_token = '' or length(v_token) > 4096 then
        raise exception 'A phone''s push token is missing';
    end if;
    insert into push_subscriptions (endpoint, user_id, platform, fcm_token, user_agent)
    values ('fcm:' || v_token, auth.uid(), 'android', v_token, left(p_label, 200))
    on conflict (endpoint) do update
        set user_id = excluded.user_id,
            platform = 'android',
            fcm_token = excluded.fcm_token,
            user_agent = excluded.user_agent,
            last_seen = now();
end;
$$;

-- 060's answer, browsers only: an older Worker never tries to Web-Push a
-- phone's token.
create or replace function push_targets(p_recipient uuid)
returns table (endpoint text, p256dh text, auth text)
language sql
stable
security definer
set search_path = public
as $$
    select s.endpoint, s.p256dh, s.auth
      from push_subscriptions s
     where s.user_id = p_recipient and s.platform = 'web';
$$;

-- Every device of a person, for the Worker (service role only).
create or replace function push_devices(p_recipient uuid)
returns table (endpoint text, platform text, p256dh text, auth text, fcm_token text)
language sql
stable
security definer
set search_path = public
as $$
    select s.endpoint, s.platform, s.p256dh, s.auth, s.fcm_token
      from push_subscriptions s
     where s.user_id = p_recipient;
$$;

-- ------------------------------------------------------------
-- 4. Per-type switches
-- ------------------------------------------------------------
-- The catalog: what a person may switch off, for whom, and how it starts.
-- Account, security and decision messages are not in it: they always ring.
create or replace function notification_types()
returns table (type text, audience text, label text, default_on boolean)
language sql
immutable
set search_path = public
as $$
    values
        ('order_updates',    'customer', 'Mes commandes',                         true),
        ('bookings',         'customer', 'Mes réservations',                      true),
        ('vitrine_news',     'customer', 'Nouveautés des vitrines suivies',       true),
        ('reports',          'customer', 'Réponses à mes signalements',           true),
        ('delivery_nearby',  'courier',  'Nouvelles livraisons près de moi',      true),
        ('delivery_updates', 'courier',  'Mes courses : annulées, boutiques',     true),
        ('courier_cash',     'courier',  'Argent remis à la boutique',            true),
        ('courier_idle',     'courier',  'Rappel après 7 jours sans livraison',   false),
        ('shop_orders',      'shop',     'Commandes de la vitrine',               true),
        ('shop_stock',       'shop',     'Stock bas',                             true),
        ('shop_team',        'shop',     'Nouveaux membres de l''équipe',         true),
        ('shop_money',       'shop',     'Crédits soldés et tontines',            true),
        ('shop_league',      'shop',     'Classement des cauris',                 true)
$$;

-- Which switch a bell row answers to; null: none (it always rings).
create or replace function notification_type_of(p_kind text, p_params jsonb)
returns text
language sql
immutable
set search_path = public
as $$
    select case
        when p_kind = 'vitrine_news' then 'vitrine_news'
        when p_kind = 'report_handled' then 'reports'
        when p_kind = 'delivery_available' then 'delivery_nearby'
        when p_kind in ('delivery_cancelled', 'courier_shop_added') then 'delivery_updates'
        when p_kind = 'courier_cash_received' then 'courier_cash'
        when p_kind = 'courier_idle' then 'courier_idle'
        when p_params ->> 'to' = 'customer'
             and (p_kind like 'order\_%' or p_kind like 'delivery\_%')
            then case when p_params ->> 'booking' = 'true' then 'bookings'
                      else 'order_updates' end
        when p_params ->> 'to' = 'shop'
             and (p_kind = 'new_order' or p_kind like 'order\_%' or p_kind like 'delivery\_%')
            then 'shop_orders'
        when p_kind = 'low_stock' then 'shop_stock'
        when p_kind = 'member_joined' then 'shop_team'
        when p_kind in ('debt_settled', 'tontine_ready') then 'shop_money'
        when p_kind = 'cauris_board' then 'shop_league'
    end;
$$;

create table if not exists notification_prefs (
    user_id    uuid not null references profiles(id) on delete cascade,
    type       text not null,
    enabled    boolean not null,
    updated_at timestamptz not null default now(),
    primary key (user_id, type)
);

comment on table notification_prefs is
    'A person''s switches (115), one row per type they moved; no row = the '
    'type''s default (notification_types). Read by the bell''s insert trigger.';

alter table notification_prefs enable row level security;

drop policy if exists notification_prefs_own on notification_prefs;
create policy notification_prefs_own on notification_prefs
    for select using (user_id = auth.uid());

-- The person's switches, every type of the catalog with its state.
create or replace function my_notification_prefs()
returns table (type text, audience text, label text, enabled boolean)
language sql
stable
security invoker
set search_path = public
as $$
    select t.type, t.audience, t.label, coalesce(p.enabled, t.default_on)
      from notification_types() t
      left join notification_prefs p on p.type = t.type and p.user_id = auth.uid();
$$;

create or replace function set_notification_pref(p_type text, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    if p_enabled is null or not exists (select 1 from notification_types() t where t.type = p_type) then
        raise exception 'Type de notification inconnu : %', coalesce(p_type, '');
    end if;
    insert into notification_prefs (user_id, type, enabled)
    values (auth.uid(), p_type, p_enabled)
    on conflict (user_id, type) do update
        set enabled = excluded.enabled, updated_at = now();
end;
$$;

-- The gate every writer meets: a type switched off writes no row, so the
-- bell stays quiet and the Worker is never woken. A failure here never
-- stops the row (030: a bell must never block the work, nor be lost to a
-- bug in a switch).
create or replace function trg_notification_prefs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_type text;
    v_on   boolean;
begin
    v_type := notification_type_of(new.kind, new.params);
    if v_type is null then
        return new;
    end if;
    select p.enabled into v_on from notification_prefs p
     where p.user_id = new.recipient_id and p.type = v_type;
    if v_on is null then
        select t.default_on into v_on from notification_types() t where t.type = v_type;
    end if;
    if v_on is false then
        return null;
    end if;
    return new;
exception when others then
    return new;
end;
$$;

drop trigger if exists notification_prefs_gate on notifications;
create trigger notification_prefs_gate
before insert on notifications
for each row execute function trg_notification_prefs();

-- ------------------------------------------------------------
-- 5. « M'envoyer une notification test »
-- ------------------------------------------------------------
create or replace function send_test_notification()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_me      uuid := auth.uid();
    v_web     int;
    v_android int;
    v_hook    boolean;
begin
    if v_me is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    if (select count(*) from notifications
         where recipient_id = v_me and kind = 'test_push'
           and created_at > now() - interval '10 minutes') >= 5 then
        raise exception 'Cinq essais en dix minutes : attendez un peu.';
    end if;
    select count(*) filter (where platform = 'web'),
           count(*) filter (where platform = 'android')
      into v_web, v_android
      from push_subscriptions where user_id = v_me;
    insert into notifications (recipient_id, org_id, kind, message, params)
    values (v_me, null, 'test_push',
            'Mara : ceci est une notification test. Si elle s''affiche sur votre téléphone, tout marche.',
            jsonb_build_object('to', 'me', 'web', v_web, 'android', v_android));
    if not exists (select 1 from profiles where id = v_me and is_platform_admin) then
        return jsonb_build_object('web', v_web, 'android', v_android);
    end if;
    -- The platform also hears whether anything wakes the Worker: a
    -- Supabase Database Webhook is a trigger on this table calling
    -- supabase_functions (or pg_net).
    select exists (
        select 1 from pg_trigger t
          join pg_proc p on p.oid = t.tgfoid
          join pg_namespace n on n.oid = p.pronamespace
         where t.tgrelid = 'public.notifications'::regclass
           and not t.tgisinternal
           and (n.nspname in ('supabase_functions', 'net') or p.proname like '%http%'))
      into v_hook;
    return jsonb_build_object('web', v_web, 'android', v_android, 'webhook', v_hook);
end;
$$;

-- ------------------------------------------------------------
-- 6. The shopper
-- ------------------------------------------------------------
alter table orders add column if not exists refusal_reason text;

comment on column orders.refusal_reason is
    'The shop''s words to the customer when it refused the order (115), ≤ 200.';

-- 099's decide_order, the same two arguments (a third, defaulted, would be
-- ambiguous wherever 099 is run again); a refusal's reason is the order's
-- own, written by refuse_order() just before.
create or replace function decide_order(p_order_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_order   orders%rowtype;
    v_ok      boolean;
    v_booking boolean;
    v_reason  text;
begin
    select * into v_order from orders where id = p_order_id;
    if not found then
        raise exception 'No such order';
    end if;
    if not can_write_org(v_order.org_id) then
        raise exception 'Only the shop can answer its orders';
    end if;

    v_ok := case v_order.status
        when 'pending'    then p_status in ('accepted', 'refused')
        when 'accepted'   then p_status in ('ready', 'picked_up', 'delivered', 'cancelled')
        when 'ready'      then p_status in ('picked_up', 'delivered', 'cancelled')
        -- Once the parcel is on a motorbike the shop can only confirm the
        -- end of the journey, not rewrite it.
        when 'in_transit' then p_status = 'delivered'
        else false
    end;
    if not v_ok then
        raise exception 'An order cannot go from % to %', v_order.status, p_status;
    end if;
    -- 115: the shop's words, when refuse_order() wrote them just before.
    v_reason := case when p_status = 'refused' then nullif(btrim(coalesce(v_order.refusal_reason, '')), '') end;
    if p_status = 'picked_up' and v_order.fulfilment = 'delivery' then
        raise exception 'A delivery is delivered, not picked up';
    end if;
    if p_status = 'delivered' and v_order.fulfilment = 'pickup' then
        raise exception 'A pickup is picked up, not delivered';
    end if;

    update orders
       set status     = p_status,
           updated_at = now(),
           decided_at = coalesce(decided_at, now())
     where id = p_order_id;

    v_booking := v_order.fulfilment = 'pickup'
        and exists (select 1 from order_lines l where l.order_id = p_order_id)
        and not exists (select 1 from order_lines l
                         where l.order_id = p_order_id and not l.is_service);

    begin
        insert into notifications (recipient_id, org_id, kind, message, params)
        select v_order.customer_id, v_order.org_id, 'order_' || p_status,
               case when v_booking then 'Votre réservation chez '
                    else 'Votre commande chez ' end
               || o.name || ' : '
               || case p_status
                    when 'accepted'  then 'acceptée'
                    when 'ready'     then 'prête'
                    when 'picked_up' then case when v_booking then 'terminée'
                                               else 'récupérée' end
                    when 'delivered' then 'livrée'
                    when 'refused'   then 'refusée'
                    else 'annulée' end
               || case when v_reason is null then '' else ' — ' || v_reason end,
               jsonb_build_object('to', 'customer', 'order_id', v_order.id,
                                  'booking', v_booking, 'shop', o.name,
                                  'status', p_status)
               || case when v_reason is null then '{}'::jsonb
                       else jsonb_build_object('reason', v_reason) end
          from orgs o where o.id = v_order.org_id;
        -- A courier who already took the job hears about a cancellation.
        if p_status = 'cancelled' and v_order.courier_id is not null then
            insert into notifications (recipient_id, org_id, kind, message, params)
            values (v_order.courier_id, v_order.org_id, 'delivery_cancelled',
                    'La livraison pour ' || v_order.customer_name
                    || ' a été annulée par la boutique',
                    jsonb_build_object('to', 'courier', 'order_id', v_order.id,
                                       'name', v_order.customer_name));
        end if;
    exception when others then
        null;
    end;
end;
$$;


-- « Refuser » with the reason the customer reads: kept on the order, then
-- the refusal itself through decide_order (its checks, its bells).
create or replace function refuse_order(p_order_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_order  orders%rowtype;
    v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 200), '');
begin
    select * into v_order from orders where id = p_order_id;
    if not found then
        raise exception 'No such order';
    end if;
    if not can_write_org(v_order.org_id) then
        raise exception 'Only the shop can answer its orders';
    end if;
    if v_order.status <> 'pending' then
        raise exception 'An order cannot go from % to %', v_order.status, 'refused';
    end if;
    update orders set refusal_reason = v_reason where id = p_order_id;
    perform decide_order(p_order_id, 'refused');
end;
$$;

-- The number proved (109's WhatsApp code, Supabase's phone change): the
-- person hears it on every device — and a number changed behind their back
-- is seen.
create or replace function trg_notify_phone_verified()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if new.phone_confirmed_at is not null
       and (old.phone_confirmed_at is null or new.phone is distinct from old.phone) then
        insert into notifications (recipient_id, org_id, kind, message, params)
        select p.id, null, 'phone_verified',
               'Votre numéro ' || coalesce('+' || ltrim(new.phone, '+'), '') || ' est vérifié.',
               jsonb_build_object('to', 'me', 'phone', new.phone)
          from profiles p where p.id = new.id;
    end if;
    return new;
exception when others then
    return new;
end;
$$;

drop trigger if exists notify_phone_verified on auth.users;
create trigger notify_phone_verified
after update of phone_confirmed_at, phone on auth.users
for each row execute function trg_notify_phone_verified();

-- ------------------------------------------------------------
-- 7. The courier
-- ------------------------------------------------------------
-- The dossier sent (or sent again after a correction): the applicant hears
-- that it arrived. 112 told only the platform.
create or replace function trg_notify_courier_received()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.status = 'pending' and new.sent_at is not null
       and (old.status is distinct from 'pending' or old.sent_at is null) then
        insert into notifications (recipient_id, org_id, kind, message, params)
        values (new.user_id, null, 'courier_received',
                'Votre demande de livreur est bien arrivée : Mara l''examine et vous répond ici.',
                jsonb_build_object('to', 'courier', 'status', 'pending'));
    end if;
    return new;
exception when others then
    return new;
end;
$$;

drop trigger if exists notify_courier_received on courier_applications;
create trigger notify_courier_received
after update of status, sent_at on courier_applications
for each row execute function trg_notify_courier_received();

-- Who is told about a delivery waiting: the shop's own approved couriers;
-- the street's approved couriers only when they are « near » — the shop's
-- city (086's orgs.city) and the courier's (112's application city) both
-- known and the same; nobody of the street when either is not (no fan-out
-- to every courier). Never the customer, never one already told, at most
-- 50 at a time, the shop's own first.
alter table orders add column if not exists couriers_told_at timestamptz;

comment on column orders.couriers_told_at is
    'When the street''s couriers were told this delivery waits (115); the '
    'shop''s own couriers are told as it becomes ready.';

create or replace function tell_couriers(p_order_id uuid, p_own_only boolean)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v      orders%rowtype;
    v_shop orgs%rowtype;
    v_city text;
    v_n    integer;
begin
    select * into v from orders where id = p_order_id;
    select * into v_shop from orgs where id = v.org_id;
    v_city := nullif(lower(btrim(coalesce(v_shop.city, ''))), '');
    insert into notifications (recipient_id, org_id, kind, message, params)
    select c.user_id, v.org_id, 'delivery_available',
           'Nouvelle livraison près de vous : ' || v_shop.name
           || case when v.delivery_fee is null then ''
                   else ' (' || to_char(v.delivery_fee, 'FM999G999G999') || ' F)' end,
           jsonb_build_object('to', 'courier', 'order_id', v.id, 'shop', v_shop.name,
                              'fee', v.delivery_fee, 'currency', v.currency,
                              'own', exists (select 1 from org_couriers oc
                                              where oc.org_id = v.org_id and oc.user_id = c.user_id))
      from couriers c
     where c.status = 'approved'
       and c.user_id is distinct from v.customer_id
       and (case when p_own_only
                 then exists (select 1 from org_couriers oc
                               where oc.org_id = v.org_id and oc.user_id = c.user_id)
                 else not exists (select 1 from org_couriers oc
                                   where oc.org_id = v.org_id and oc.user_id = c.user_id)
                      and v_city is not null
                      and (select nullif(lower(btrim(coalesce(a.city, ''))), '')
                             from courier_applications a
                            where a.user_id = c.user_id) = v_city
            end)
     order by c.decided_at desc nulls last, c.user_id
     limit 50;
    get diagnostics v_n = row_count;
    if not p_own_only then
        update orders set couriers_told_at = now() where id = p_order_id;
    end if;
    return v_n;
end;
$$;

-- A delivery becomes ready with nobody carrying it: the shop's own couriers
-- hear it at once; the street's couriers too when the shop has none —
-- otherwise after the shop's own minutes (073), by deliveries_waiting().
-- « Has own couriers » is 073's courier_may_take rule: any org_couriers row,
-- approved or not — the street may not take it before the minutes either.
create or replace function trg_notify_delivery_ready()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_has_own boolean;
begin
    if new.status = 'ready' and old.status is distinct from 'ready'
       and new.fulfilment = 'delivery' and new.courier_id is null
       and not coalesce(new.self_delivered, false) then
        v_has_own := exists (select 1 from org_couriers oc
                             where oc.org_id = new.org_id);
        if v_has_own then
            perform tell_couriers(new.id, true);
        else
            perform tell_couriers(new.id, false);
        end if;
    end if;
    return new;
exception when others then
    return new;
end;
$$;

drop trigger if exists notify_delivery_ready on orders;
create trigger notify_delivery_ready
after update of status on orders
for each row execute function trg_notify_delivery_ready();

-- The shop's own minutes are over and nobody took it: the street hears.
-- The minutes are counted as 073's courier_may_take counts them — from
-- order_status_since(), with plan_limit('own_courier_minutes', 10) — so the
-- street is told exactly when it may take the delivery.
-- Called by pg_cron every five minutes where it exists.
create or replace function deliveries_waiting()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id  uuid;
    v_n   integer := 0;
    v_min integer := plan_limit('own_courier_minutes', 10);
begin
    for v_id in
        select o.id from orders o
         where o.status = 'ready' and o.fulfilment = 'delivery'
           and o.courier_id is null and not coalesce(o.self_delivered, false)
           and o.couriers_told_at is null
           and order_status_since(o.id) < now() - make_interval(mins => v_min)
           and order_status_since(o.id) > now() - interval '1 day'
    loop
        begin
            v_n := v_n + tell_couriers(v_id, false);
        exception when others then
            null;
        end;
    end loop;
    return v_n;
end;
$$;

-- A shop names the courier as one of its own (073's add_org_courier).
create or replace function trg_notify_courier_shop_added()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into notifications (recipient_id, org_id, kind, message, params)
    select new.user_id, new.org_id, 'courier_shop_added',
           o.name || ' vous a ajouté à ses livreurs : ses livraisons vous arrivent en premier.',
           jsonb_build_object('to', 'courier', 'shop', o.name)
      from orgs o where o.id = new.org_id;
    return new;
exception when others then
    return new;
end;
$$;

drop trigger if exists notify_courier_shop_added on org_couriers;
create trigger notify_courier_shop_added
after insert on org_couriers
for each row execute function trg_notify_courier_shop_added();

-- The shop confirms the cash the courier collected was handed over (073's
-- confirm_cash_received): the courier's money settled with the shop.
create or replace function trg_notify_courier_cash()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.cash_received_at is not null and old.cash_received_at is null
       and new.courier_id is not null then
        insert into notifications (recipient_id, org_id, kind, message, params)
        select new.courier_id, new.org_id, 'courier_cash_received',
               o.name || ' confirme avoir reçu l''argent de la livraison pour '
               || new.customer_name || ' : ' || to_char(new.total, 'FM999G999G999') || ' F.',
               jsonb_build_object('to', 'courier', 'order_id', new.id, 'shop', o.name,
                                  'name', new.customer_name, 'amount', new.total,
                                  'currency', new.currency)
          from orgs o where o.id = new.org_id;
    end if;
    return new;
exception when others then
    return new;
end;
$$;

drop trigger if exists notify_courier_cash on orders;
create trigger notify_courier_cash
after update of cash_received_at on orders
for each row execute function trg_notify_courier_cash();

-- Seven days without a delivery: a nudge, only for a courier who switched
-- it on (off by default), at most once a week. Called daily by pg_cron.
create or replace function courier_idle_nudge()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_n integer;
begin
    insert into notifications (recipient_id, org_id, kind, message, params)
    select c.user_id, null, 'courier_idle',
           'Cela fait 7 jours sans livraison : des courses vous attendent sur Mara.',
           jsonb_build_object('to', 'courier', 'days', 7)
      from couriers c
      join notification_prefs p on p.user_id = c.user_id
                               and p.type = 'courier_idle' and p.enabled
     where c.status = 'approved'
       and c.decided_at < now() - interval '7 days'
       and not exists (select 1 from orders o
                        where o.courier_id = c.user_id
                          and o.updated_at > now() - interval '7 days')
       and not exists (select 1 from notifications n
                        where n.recipient_id = c.user_id and n.kind = 'courier_idle'
                          and n.created_at > now() - interval '7 days');
    get diagnostics v_n = row_count;
    return v_n;
end;
$$;

-- ------------------------------------------------------------
-- 8. Mara's message: to the responsables, or to the whole team
-- ------------------------------------------------------------
-- The message to one business (or all), to its responsables (as 072) or
-- its whole team, with its facts in params (099).
create or replace function platform_message_send(
    p_org_id   uuid,
    p_message  text,
    p_audience text
)
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_text     text := nullif(btrim(coalesce(p_message, '')), '');
    v_audience text := coalesce(nullif(btrim(coalesce(p_audience, '')), ''), 'admins');
    v_count    integer;
begin
    if not exists (select 1 from profiles
                    where id = auth.uid() and is_platform_admin) then
        raise exception 'Seule la plateforme écrit aux boutiques';
    end if;
    if v_text is null then
        raise exception 'Le message est vide';
    end if;
    if length(v_text) > 500 then
        raise exception 'Un message tient en 500 caractères';
    end if;
    if v_audience not in ('admins', 'team') then
        raise exception 'Destinataires inconnus : %', v_audience;
    end if;
    insert into notifications (recipient_id, org_id, kind, message, params)
    select distinct m.user_id, m.org_id, 'platform_message', 'Kaj : ' || v_text,
           jsonb_build_object('to', 'shop', 'text', v_text, 'audience', v_audience)
      from memberships m
      join orgs o on o.id = m.org_id
     where (v_audience = 'team' or m.role in ('owner', 'super_admin', 'admin'))
       and o.archived_at is null
       and (p_org_id is null or m.org_id = p_org_id);
    get diagnostics v_count = row_count;
    return v_count;
end;
$$;

-- 072's door, unchanged for its callers: the responsables.
create or replace function send_platform_message(p_org_id uuid, p_message text)
returns integer
language sql
security definer
set search_path = public, auth
as $$
    select platform_message_send(p_org_id, p_message, 'admins');
$$;

-- 105's platform_bulk, the message's audience passed through (args
-- 'audience': 'admins' — the default — or 'team').
create or replace function platform_bulk(p_action text, p_orgs uuid[], p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_args    jsonb := coalesce(p_args, '{}'::jsonb);
    v_points  int;
    v_expires date;
    v_feature text;
    v_until   date;
    v_note    text := nullif(btrim(coalesce(v_args->>'note', '')), '');
    v_message text := nullif(btrim(coalesce(v_args->>'message', '')), '');
    -- 115: whom a message reaches — « Responsables » (as before) or
    -- « Toute l'équipe ».
    v_audience text := coalesce(nullif(btrim(coalesce(v_args->>'audience', '')), ''), 'admins');
    v_org     uuid;
    v_name    text;
    v_archived timestamptz;
    v_by      uuid;
    v_kind    text;
    v_ref     uuid;
    v_promo   uuid;
    v_mark    bigint;
    v_line    bigint;
    v_before  jsonb;
    v_after   jsonb;
    v_res     jsonb;
    v_open    timestamptz;
    v_sent    int;
    v_action  uuid;
    v_done    int := 0;
    v_actions jsonb := '[]'::jsonb;
    v_failed  jsonb := '[]'::jsonb;
    v_last    jsonb;
begin
    perform platform_only();
    if p_action is null or p_action not in ('cauris', 'unlock', 'message', 'archive', 'restore') then
        raise exception 'Action inconnue : %', coalesce(p_action, '');
    end if;
    if p_orgs is null or cardinality(p_orgs) = 0 then
        raise exception 'Choisissez au moins une entreprise.';
    end if;
    if cardinality(p_orgs) > 500 then
        raise exception 'Pas plus de 500 entreprises à la fois.';
    end if;

    -- What is asked is checked once, before any business: a wrong number
    -- refuses the whole act rather than each business in turn.
    if p_action = 'cauris' then
        begin
            v_points := (v_args->>'points')::int;
            v_expires := nullif(v_args->>'expires_on', '')::date;
        exception when others then
            raise exception 'Le nombre de cauris doit être entre 1 et 100 000';
        end;
        if v_points is null or v_points <= 0 or v_points > 100000 then
            raise exception 'Le nombre de cauris doit être entre 1 et 100 000';
        end if;
        if v_expires is not null and v_expires <= cauris_today() then
            raise exception 'La date doit être après aujourd''hui';
        end if;
    elsif p_action = 'unlock' then
        v_feature := nullif(btrim(coalesce(v_args->>'feature', '')), '');
        begin
            v_until := (v_args->>'until')::date;
        exception when others then
            raise exception 'La date doit être aujourd''hui ou plus tard';
        end;
        -- The same list 100's platform_give_unlock accepts.
        if v_feature is null or v_feature = 'photo_slot'
           or not (coalesce(plan_setting('pro_features'), '[]'::jsonb) ? v_feature
                   or exists (select 1 from cauris_costs where feature = v_feature)) then
            raise exception 'Outil inconnu : %', coalesce(v_feature, '');
        end if;
        if v_until is null or v_until < cauris_today() then
            raise exception 'La date doit être aujourd''hui ou plus tard';
        end if;
    elsif p_action = 'message' then
        if v_message is null then
            raise exception 'Le message est vide';
        end if;
        if length(v_message) > 500 then
            raise exception 'Un message tient en 500 caractères';
        end if;
        if v_audience not in ('admins', 'team') then
            raise exception 'Destinataires inconnus : %', v_audience;
        end if;
    end if;

    for v_org in select distinct u from unnest(p_orgs) u loop
        select name, archived_at, archived_by, profile into v_name, v_archived, v_by, v_kind
          from orgs where id = v_org;
        if not found then
            v_failed := v_failed || jsonb_build_object('org_id', v_org, 'name', null,
                                                       'error', 'Entreprise inconnue');
            continue;
        end if;
        begin
            v_ref := gen_random_uuid();
            if p_action = 'cauris' then
                -- The wallet's own lock (100's), held across the gift: the
                -- one gift line written after the mark is this gift's.
                -- 100's platform_give_cauris returns the balance, not its
                -- line, so the line is found by what it wrote — the ledger
                -- row (and, for promotional cauris, the lot it names) —
                -- never by « the newest gift ».
                perform pg_advisory_xact_lock(hashtext('cauris:' || v_org::text));
                select coalesce(max(id), 0) into v_mark from cauris_ledger where org_id = v_org;
                v_before := jsonb_build_object('balance', cauris_balance(v_org));
                v_res := platform_give_cauris(v_org, v_points, v_note, v_expires);
                select l.id, case when l.reason = 'promo' then l.ref::uuid end
                  into v_line, v_promo
                  from cauris_ledger l
                 where l.org_id = v_org and l.id > v_mark and l.delta = v_points
                   and l.reason = case when v_expires is null then 'gift' else 'promo' end
                 order by l.id limit 1;
                if v_line is null then
                    raise exception 'Le cadeau n''a pas été écrit';
                end if;
                v_after := jsonb_build_object('balance', v_res->'balance', 'points', v_points,
                                              'expires_on', v_expires, 'note', v_note,
                                              'promo_id', v_promo);
                v_action := platform_log_action(
                    v_org, 'cauris_gift',
                    'Cauris offerts à ' || v_name || ' : ' || v_points
                    || case when v_expires is null then ''
                            else ', à utiliser avant le ' || to_char(v_expires, 'DD/MM/YYYY') end,
                    v_before, v_after, 'platform_undo_cauris',
                    jsonb_build_object('org_id', v_org, 'points', v_points,
                                       'promo_id', v_promo, 'ledger_id', v_line,
                                       'ref', v_ref));
            elsif p_action = 'unlock' then
                -- A tool the kind does not have is not opened (099: an
                -- association has no analyses and no delivery).
                if (v_feature = 'analytics' and v_kind not in ('retail', 'farm'))
                   or (v_feature = 'delivery' and v_kind in ('association', 'church')) then
                    raise exception 'Cet outil n''existe pas pour ce type d''activité';
                end if;
                select jsonb_build_object('until', u.until, 'note', u.note, 'gifted_by', u.gifted_by)
                  into v_before
                  from cauris_unlocks u where u.org_id = v_org and u.feature = v_feature;
                v_open := platform_give_unlock(v_org, v_feature, v_until, v_note);
                v_res := jsonb_build_object('until', v_open);
                v_after := jsonb_build_object('feature', v_feature, 'until', v_open, 'note', v_note);
                v_action := platform_log_action(
                    v_org, 'unlock_gift',
                    'Outil ouvert pour ' || v_name || ' : ' || cauris_feature_label(v_feature)
                    || ' jusqu''au ' || to_char(v_until, 'DD/MM/YYYY'),
                    jsonb_build_object('feature', v_feature, 'unlock', v_before), v_after,
                    'platform_undo_unlock',
                    jsonb_build_object('org_id', v_org, 'feature', v_feature,
                                       'before', v_before, 'until', v_open));
            elsif p_action = 'message' then
                v_sent := platform_message_send(v_org, v_message, v_audience);
                v_res := jsonb_build_object('sent', v_sent);
                v_action := platform_log_action(
                    v_org, 'message',
                    'Message à ' || v_name
                    || case when v_audience = 'team' then ' (toute l''équipe)' else '' end
                    || ' : « ' || left(v_message, 120) || ' »',
                    null, jsonb_build_object('message', v_message, 'sent', v_sent)
                          || case when v_audience = 'team'
                                  then jsonb_build_object('audience', 'team') else '{}'::jsonb end,
                    null, null);
            elsif p_action = 'archive' then
                if v_archived is not null then
                    raise exception 'Déjà archivée';
                end if;
                perform archive_org(v_org);
                select archived_at into v_archived from orgs where id = v_org;
                v_res := jsonb_build_object('archived_at', v_archived);
                v_action := platform_log_action(
                    v_org, 'archive', 'Entreprise archivée : ' || v_name,
                    jsonb_build_object('archived_at', null),
                    jsonb_build_object('archived_at', v_archived),
                    'platform_undo_archive',
                    jsonb_build_object('org_id', v_org, 'archived_at', v_archived));
            else -- restore
                if v_archived is null then
                    raise exception 'Cette entreprise n''est pas archivée';
                end if;
                perform restore_org(v_org);
                v_res := jsonb_build_object('archived_at', null);
                v_action := platform_log_action(
                    v_org, 'restore', 'Entreprise restaurée : ' || v_name,
                    jsonb_build_object('archived_at', v_archived, 'archived_by', v_by),
                    jsonb_build_object('archived_at', null),
                    'platform_undo_restore',
                    jsonb_build_object('org_id', v_org, 'archived_at', v_archived,
                                       'archived_by', v_by));
            end if;
            v_done := v_done + 1;
            v_actions := v_actions || to_jsonb(v_action);
            v_last := v_res;
        exception when others then
            v_failed := v_failed || jsonb_build_object('org_id', v_org, 'name', v_name,
                                                       'error', sqlerrm);
        end;
    end loop;

    return jsonb_build_object('done', v_done, 'actions', v_actions, 'failed', v_failed,
                              'result', v_last);
end;
$$;

-- ------------------------------------------------------------
-- 9. The bar's numbers
-- ------------------------------------------------------------
-- What asks for action in one business, for its bar (and the bell's poll).
-- As the caller: an employee counts what their own access shows them (an
-- invitation only an admin reads counts 0 for them). Null for a stranger.
create or replace function home_counts(p_org uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
    v_kind      text;
    v_orders    int := 0;
    v_bookings  int := 0;
    v_articles  int := 0;
    v_invoices  int := 0;
    v_credit    int := 0;
    v_invites   int := 0;
    v_supplies  int := 0;
    v_livestock int := 0;
begin
    if p_org is null or not is_org_member(p_org) then
        return null;
    end if;
    select profile into v_kind from orgs where id = p_org;

    -- Orders not answered yet; a basket of services only is a booking.
    select count(*) filter (where not x.booking), count(*) filter (where x.booking)
      into v_orders, v_bookings
      from (select exists (select 1 from order_lines l where l.order_id = o.id)
                   and not exists (select 1 from order_lines l
                                    where l.order_id = o.id and not l.is_service) as booking
              from orders o
             where o.org_id = p_org and o.status = 'pending') x;

    if v_kind in ('retail', 'farm') then
        select count(*) into v_articles
          from products p
         where p.org_id = p_org and p.is_active and not p.is_service
           and (p.quantity <= 0 or (p.low_stock_at is not null and p.quantity <= p.low_stock_at));
    end if;

    select count(*) into v_invoices
      from invoices i
     where i.org_id = p_org and i.cancelled_at is null
       and i.due_on is not null and i.due_on < current_date
       and i.total > coalesce((select sum(ip.amount) from invoice_payments ip
                                where ip.invoice_id = i.id), 0);

    -- A due date on a credit is 117's; before it, nothing is « overdue ».
    if exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'debts'
                  and column_name = 'due_on') then
        execute 'select count(*) from debts d
                  where d.org_id = $1 and d.due_on < current_date
                    and d.amount > coalesce((select sum(dp.amount) from debt_payments dp
                                              where dp.debt_id = d.id), 0)'
           into v_credit using p_org;
    end if;

    select count(*) into v_invites
      from pending_invitations pi
     where pi.org_id = p_org and pi.claimed_at is null and pi.expires_at > now();

    if v_kind = 'farm' then
        select count(*) into v_supplies from stock_on_hand(p_org) s where s.below_reorder;
        select count(*) into v_livestock
          from flocks f
         where f.org_id = p_org and f.closed_on is null
           and not exists (select 1 from flock_events e
                            where e.flock_id = f.id and e.occurred_at >= current_date)
           and not exists (select 1 from egg_production g
                            where g.flock_id = f.id and g.produced_on = current_date);
    end if;

    return jsonb_build_object(
        'orders', v_orders, 'bookings', v_bookings, 'articles', v_articles,
        'invoices', v_invoices, 'credit', v_credit, 'invitations', v_invites,
        'supplies', v_supplies, 'livestock', v_livestock);
end;
$$;

-- ------------------------------------------------------------
-- 10. The clock (pg_cron, where it exists — Supabase; not in CI)
-- ------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
        begin
            create extension if not exists pg_cron;
            perform cron.schedule('deliveries-waiting', '*/5 * * * *',
                                  'select public.deliveries_waiting()');
            -- 09:00 in Ouagadougou (UTC all year).
            perform cron.schedule('courier-idle', '0 9 * * *',
                                  'select public.courier_idle_nudge()');
        exception when others then
            raise notice 'pg_cron not scheduled here: %', sqlerrm;
        end;
    end if;
end $$;

-- ------------------------------------------------------------
-- 11. Who may call what
-- ------------------------------------------------------------
-- Since 063 a new function is born closed to anon and public and open to
-- authenticated; what the app must not call is taken back here.
revoke execute on function notification_scope(text, uuid, jsonb)           from public;
revoke execute on function notification_counts()                           from public;
revoke execute on function save_fcm_token(text, text)                      from public;
revoke execute on function push_targets(uuid)                              from public;
revoke execute on function push_devices(uuid)                              from public;
revoke execute on function notification_types()                            from public;
revoke execute on function notification_type_of(text, jsonb)               from public;
revoke execute on function my_notification_prefs()                         from public;
revoke execute on function set_notification_pref(text, boolean)            from public;
revoke execute on function trg_notification_prefs()                        from public;
revoke execute on function send_test_notification()                        from public;
revoke execute on function decide_order(uuid, text)                  from public;
revoke execute on function refuse_order(uuid, text)                  from public;
revoke execute on function platform_message_send(uuid, text, text)   from public;
revoke execute on function trg_notify_phone_verified()                     from public;
revoke execute on function trg_notify_courier_received()                   from public;
revoke execute on function tell_couriers(uuid, boolean)                    from public;
revoke execute on function trg_notify_delivery_ready()                     from public;
revoke execute on function deliveries_waiting()                            from public;
revoke execute on function trg_notify_courier_shop_added()                 from public;
revoke execute on function trg_notify_courier_cash()                       from public;
revoke execute on function courier_idle_nudge()                            from public;
revoke execute on function send_platform_message(uuid, text)         from public;
revoke execute on function platform_bulk(text, uuid[], jsonb)              from public;
revoke execute on function home_counts(uuid)                               from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function notification_counts()                   from anon;
        revoke execute on function save_fcm_token(text, text)              from anon;
        revoke execute on function push_targets(uuid)                      from anon;
        revoke execute on function push_devices(uuid)                      from anon;
        revoke execute on function my_notification_prefs()                 from anon;
        revoke execute on function set_notification_pref(text, boolean)    from anon;
        revoke execute on function trg_notification_prefs()                from anon;
        revoke execute on function send_test_notification()                from anon;
        revoke execute on function decide_order(uuid, text)          from anon;
        revoke execute on function refuse_order(uuid, text)          from anon;
        revoke execute on function platform_message_send(uuid, text, text) from anon;
        revoke execute on function trg_notify_phone_verified()             from anon;
        revoke execute on function trg_notify_courier_received()           from anon;
        revoke execute on function tell_couriers(uuid, boolean)            from anon;
        revoke execute on function trg_notify_delivery_ready()             from anon;
        revoke execute on function deliveries_waiting()                    from anon;
        revoke execute on function trg_notify_courier_shop_added()         from anon;
        revoke execute on function trg_notify_courier_cash()               from anon;
        revoke execute on function courier_idle_nudge()                    from anon;
        revoke execute on function send_platform_message(uuid, text) from anon;
        revoke execute on function platform_bulk(text, uuid[], jsonb)      from anon;
        revoke execute on function home_counts(uuid)                       from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- The internals: the Worker's book, the triggers, the clock's jobs
        -- and the courier fan-out are nobody's to call from the app.
        revoke execute on function push_targets(uuid)                      from authenticated;
        revoke execute on function push_devices(uuid)                      from authenticated;
        revoke execute on function trg_notification_prefs()                from authenticated;
        revoke execute on function trg_notify_phone_verified()             from authenticated;
        revoke execute on function trg_notify_courier_received()           from authenticated;
        revoke execute on function tell_couriers(uuid, boolean)            from authenticated;
        revoke execute on function trg_notify_delivery_ready()             from authenticated;
        revoke execute on function deliveries_waiting()                    from authenticated;
        revoke execute on function trg_notify_courier_shop_added()         from authenticated;
        revoke execute on function trg_notify_courier_cash()               from authenticated;
        revoke execute on function courier_idle_nudge()                    from authenticated;
        -- The generated column and the gate read these as the table's
        -- owner; the app reads the catalog through my_notification_prefs.
        grant  execute on function notification_scope(text, uuid, jsonb)   to authenticated;
        grant  execute on function notification_types()                    to authenticated;
        grant  execute on function notification_type_of(text, jsonb)       to authenticated;
        grant  execute on function notification_counts()                   to authenticated;
        grant  execute on function save_fcm_token(text, text)              to authenticated;
        grant  execute on function my_notification_prefs()                 to authenticated;
        grant  execute on function set_notification_pref(text, boolean)    to authenticated;
        grant  execute on function send_test_notification()                to authenticated;
        grant  execute on function decide_order(uuid, text)          to authenticated;
        grant  execute on function refuse_order(uuid, text)          to authenticated;
        grant  execute on function platform_message_send(uuid, text, text) to authenticated;
        grant  execute on function send_platform_message(uuid, text) to authenticated;
        grant  execute on function platform_bulk(text, uuid[], jsonb)      to authenticated;
        grant  execute on function home_counts(uuid)                       to authenticated;
        grant  select on notification_prefs                                 to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function push_targets(uuid) to service_role;
        grant execute on function push_devices(uuid) to service_role;
    end if;
end $$;

notify pgrst, 'reload schema';
