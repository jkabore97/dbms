-- ============================================================
-- 185 — A cancelled event says so.
--
-- The owner: « canceling an event does not work ». event_cancel (163)
-- closed the sale and took the event off the street, and nothing else
-- showed it: the guests' card looked the same, its buyers' tickets and
-- its confirmed guests' invitations said nothing, nobody heard of it but
-- by the organiser's WhatsApp, one by one.
--
--   * event_public (173): `cancelled` and `cancel_reason` — the card
--     draws « Événement annulé » and its reason, and takes away its
--     « Confirmer ma présence » and « Réserver ». Everything else verbatim.
--   * event_ticket_status (161), read by « Mes billets »: the same two.
--   * my_event_invitations (184): the same two.
--   * event_cancel (163): the first time an event is cancelled, a bell to
--     each account that bought a ticket (`event_cancelled_buyer`, opens
--     « Mes billets ») and to each account that confirmed its presence
--     and bought none (`event_cancelled_guest`, opens « Mes
--     invitations ») — « « Mariage Awa » est annulé (raison). ». The
--     tickets stay as they are: the refund is the organiser's, as before.
--   * notification_type_of (183): both under « Mes réservations », every
--     mapping of before verbatim.
--
-- Shop, farm, association: none has events; nothing changes there.
-- ============================================================

create or replace function event_public(p_slug text, p_preview text default null, p_edit text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    e events;
    t event_templates;
    v_editor boolean;
begin
    select * into e from events where slug = lower(trim(coalesce(p_slug, '')));
    if not found or not event_visible(e, p_preview, p_edit) then
        return null;
    end if;
    v_editor := p_edit is not null and p_edit = e.edit_token;
    if e.doc is not null and not v_editor and jsonb_typeof(e.doc -> 'blocks') = 'array' then
        e.doc := jsonb_set(e.doc, '{blocks}', coalesce(
            (select jsonb_agg(b order by n)
               from jsonb_array_elements(e.doc -> 'blocks') with ordinality as x(b, n)
              where coalesce(b ->> 'hidden', 'false') <> 'true'),
            '[]'::jsonb));
    end if;
    select * into t from event_templates where key = e.card;
    return jsonb_build_object(
        'slug', e.slug,
        'kind', e.kind,
        'card', e.card,
        'family', coalesce(t.family, 'classique'),
        'premium', coalesce(t.premium, false),
        'title', e.title,
        'starts_at', e.starts_at,
        'tz', e.tz,
        'place', e.place,
        'content', e.content,
        'doc', e.doc,
        'doc_saved_at', e.doc_saved_at,
        'rsvp_on', e.rsvp_on,
        'album_on', e.album_on,
        'published', e.published,
        'org_name', (select name from orgs where id = e.org_id),
        'preview', p_preview is not null and p_preview = e.preview_token,
        'editor', v_editor,
        -- the editor's: whether Premium is open to it (173); null to the guests
        'pro', case when v_editor then org_plan(e.org_id) = 'pro' end,
        -- the answers' closing day (173), for the guests' form
        'rsvp_closes', event_rsvp_closes(e),
        -- 185: cancelled, the card says so (and its reason)
        'cancelled', e.cancelled_at is not null,
        'cancel_reason', case when e.cancelled_at is not null then e.cancel_reason end);
end;
$$;

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
        'place', e.place,
        -- 185: the event cancelled, the ticket says so
        'cancelled', e.cancelled_at is not null,
        'cancel_reason', case when e.cancelled_at is not null then e.cancel_reason end,
        'org_name', (select o.name from orgs o where o.id = e.org_id),
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

create or replace function my_event_invitations()
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select coalesce(jsonb_agg(jsonb_build_object(
        'id', e.id,
        'slug', e.slug,
        -- a draft's link, only the one this guest confirmed through and still the card's
        'preview', case when not e.published and r.extra ->> 'preview' = e.preview_token then e.preview_token end,
        'title', e.title,
        'kind', e.kind,
        'starts_at', e.starts_at,
        'tz', e.tz,
        'place', e.place,
        'card_preview', e.card_preview,
        'org_name', (select name from orgs where id = e.org_id),
        'people', r.people,
        'message', r.message,
        -- 185: the event cancelled
        'cancelled', e.cancelled_at is not null,
        'cancel_reason', case when e.cancelled_at is not null then e.cancel_reason end,
        'album_on', e.album_on,
        'album_allowed', event_album_allowed(e.org_id),
        'album_review', e.album_review,
        'photos_from', event_album_opens(e),
        'photos_until', event_album_closes(e),
        'photos_open', event_album_today(e),
        'photos_used', (select count(*) from event_pictures p
                         where p.event_id = e.id and p.user_id = r.user_id and p.source = 'guest'
                           and (p.state = 'stored' or p.created_at > now() - interval '10 minutes')),
        'photos_limit', 5,
        'photos', coalesce((select jsonb_agg(jsonb_build_object('key', p.key, 'approved', p.approved) order by p.done_at desc)
                              from event_pictures p
                             where p.event_id = e.id and p.user_id = r.user_id and p.source = 'guest' and p.state = 'stored'), '[]'::jsonb),
        'confirmed_at', r.created_at)
        order by e.starts_at desc nulls first), '[]'::jsonb)
      from event_rsvps r join events e on e.id = r.event_id
     where r.user_id = auth.uid() and r.answer = 'oui';
$$;

create or replace function event_cancel(p_event uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    e events;
    v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
    v_text text;
begin
    select * into e from events where id = p_event for update;
    if not found or auth.uid() is null or not is_org_admin(e.org_id) then
        raise exception 'Seuls les administrateurs annulent un événement.';
    end if;
    if p_reason is not null and length(p_reason) > 300 then
        raise exception 'Une raison de 300 caractères au plus.';
    end if;
    update events set cancelled_at = coalesce(cancelled_at, now()), cancel_reason = v_reason,
                      tickets_on = false, listed = false
     where id = e.id;
    insert into event_ticket_log (event_id, actor, action, detail) values (e.id, auth.uid(), 'cancelled', v_reason);
    -- 185: the first time, those who hold a ticket or confirmed hear it
    if e.cancelled_at is null then
        v_text := '« ' || e.title || ' » est annulé' || coalesce(' (' || v_reason || ')', '') || '.';
        insert into notifications (recipient_id, org_id, kind, message, params)
        select distinct r.buyer_user_id, null::uuid, 'event_cancelled_buyer', v_text,
               jsonb_build_object('to', 'customer', 'event_id', e.id, 'slug', e.slug, 'title', e.title, 'reason', v_reason)
          from event_ticket_requests r
         where r.event_id = e.id and r.buyer_user_id is not null and r.status in ('pending', 'paid')
           and exists (select 1 from profiles p where p.id = r.buyer_user_id);
        insert into notifications (recipient_id, org_id, kind, message, params)
        select distinct g.user_id, null::uuid, 'event_cancelled_guest', v_text,
               jsonb_build_object('to', 'customer', 'event_id', e.id, 'slug', e.slug, 'title', e.title, 'reason', v_reason)
          from event_rsvps g
         where g.event_id = e.id and g.user_id is not null and g.answer = 'oui'
           and exists (select 1 from profiles p where p.id = g.user_id)
           and not exists (select 1 from event_ticket_requests r
                            where r.event_id = e.id and r.buyer_user_id = g.user_id and r.status in ('pending', 'paid'));
    end if;
    return event_ticket_holders(e.id);
end;
$$;

create or replace function notification_type_of(p_kind text, p_params jsonb)
returns text
language sql
immutable
set search_path = public
as $$
    select case
        -- 183: a guest's confirmation, the organiser's (a guest who comes is
        -- the organiser's order) and the guest's own (their reservation).
        when p_kind = 'event_presence' then 'shop_orders'
        when p_kind = 'event_presence_guest' then 'bookings'
        -- 185: an event cancelled, its buyers' and its confirmed guests'
        -- (their reservation, as the confirmation).
        when p_kind in ('event_cancelled_buyer', 'event_cancelled_guest') then 'bookings'
        when p_kind = 'vitrine_news' then 'vitrine_news'
        when p_kind = 'report_handled' then 'reports'
        when p_kind = 'delivery_available' then 'delivery_nearby'
        when p_kind in ('delivery_cancelled', 'courier_shop_added') then 'delivery_updates'
        when p_kind = 'courier_cash_received' then 'courier_cash'
        when p_kind = 'courier_idle' then 'courier_idle'
        -- 125: confirmed, proposed, declined (the customer's); accepted
        -- (the business's).
        when p_kind like 'booking\_%'
            then case when p_params ->> 'to' = 'shop' then 'shop_orders' else 'bookings' end
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

-- ------------------------------------------------------------
-- The doors (063): the same functions, the same doors as before
-- ------------------------------------------------------------
revoke execute on function event_cancel(uuid, text) from public;
revoke execute on function my_event_invitations() from public;
revoke execute on function event_ticket_status(uuid) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function event_cancel(uuid, text) from anon;
        revoke execute on function my_event_invitations() from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function event_cancel(uuid, text) to authenticated;
        grant execute on function my_event_invitations() to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
