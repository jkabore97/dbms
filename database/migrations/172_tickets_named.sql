-- 172: a ticket is bought with a Marakaj account, one name per ticket.
--
-- The owner, testing the sale: « Every person buying a ticket should create
-- an account with Marakaj, since the tickets show on the welcome page, right
-- at the top, and a tap opens their QR codes with no internet. When one
-- account buys several tickets, let them write as many names: there is no
-- point in one person owning several tickets for the same event. »
--
--   * event_ticket_request asks for a signed-in person (auth.uid()): the
--     request is the account's from the start (my_event_tickets, the home's
--     bar). The street (anon) can no longer call it; the ticket page sends
--     the buyer to Marakaj to sign in and buy there.
--   * p_holders: one {type, name} per ticket — as many of each type as
--     asked, every name different. Kept on the request (holders).
--   * event_ticket_decide: each validated ticket carries its own person's
--     name, in the order given; a request made before 172 keeps the buyer's
--     name on every ticket, as before.
--   * A shop, a farm, an association: unchanged (tickets are an
--     Événementiel's); the door's own sale (163) is unchanged.

alter table event_ticket_requests add column if not exists holders jsonb
    check (holders is null or (jsonb_typeof(holders) = 'array' and jsonb_array_length(holders) between 1 and 20));

drop function if exists event_ticket_request(text, text, text, text, jsonb, text);

create or replace function event_ticket_request(
    p_slug text, p_preview text, p_name text, p_whatsapp text, p_lines jsonb, p_txn text default null, p_holders jsonb default null)
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
    h jsonb;
    v_hname text;
    v_seen text[] := '{}';
begin
    -- 172: a buyer has a Marakaj account — the tickets wait on its home,
    -- their QR codes open with no signal.
    if auth.uid() is null then
        raise exception 'Connectez-vous à Marakaj pour demander vos billets : ils s''afficheront sur votre accueil.';
    end if;
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
    -- 172: one name per ticket, each a different person, as many names as
    -- tickets of each kind.
    if p_holders is null or jsonb_typeof(p_holders) <> 'array' or jsonb_array_length(p_holders) <> v_count then
        raise exception 'Un nom par billet : % billet(s), % nom(s).', v_count, coalesce(jsonb_array_length(case when jsonb_typeof(p_holders) = 'array' then p_holders end), 0);
    end if;
    for h in select * from jsonb_array_elements(p_holders) loop
        v_hname := nullif(btrim(coalesce(h ->> 'name', '')), '');
        if jsonb_typeof(h) <> 'object' or v_hname is null or length(v_hname) > 80 then
            raise exception 'Le nom de chaque personne, en 80 caractères au plus.';
        end if;
        if lower(v_hname) = any (v_seen) then
            raise exception 'Chaque billet est pour une personne différente : « % » est écrit deux fois.', v_hname;
        end if;
        v_seen := v_seen || lower(v_hname);
    end loop;
    if exists (select 1 from jsonb_array_elements(p_lines) l
                where (select count(*) from jsonb_array_elements(p_holders) h2 where h2 ->> 'type' = l ->> 'type')
                      <> (select coalesce(sum((l2 ->> 'qty')::integer), 0) from jsonb_array_elements(p_lines) l2 where l2 ->> 'type' = l ->> 'type'))
       or exists (select 1 from jsonb_array_elements(p_holders) h2
                   where not exists (select 1 from jsonb_array_elements(p_lines) l where l ->> 'type' = h2 ->> 'type')) then
        raise exception 'Un nom par billet, pour chaque sorte de billet.';
    end if;
    select coalesce(default_currency, 'XOF') into v_currency from orgs where id = e.org_id;
    loop
        v_ref := 'MK-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 5));
        exit when not exists (select 1 from event_ticket_requests where event_id = e.id and ref = v_ref);
    end loop;
    v_hold := now() + make_interval(hours => e.hold_hours);
    insert into event_ticket_requests (event_id, ref, buyer_name, buyer_whatsapp, buyer_user_id, txn_ref, total, currency, hold_until, holders)
    values (e.id, v_ref, v_name, v_wa, auth.uid(), v_txn, v_total, v_currency, v_hold,
            (select jsonb_agg(jsonb_build_object('type', h2 ->> 'type', 'name', btrim(h2 ->> 'name')) order by n)
               from jsonb_array_elements(p_holders) with ordinality as x(h2, n)))
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
    -- 172: each ticket its own person, in the order they were named; a
    -- request made before 172 keeps the buyer's name on every ticket.
    if r.holders is not null and jsonb_typeof(r.holders) = 'array' and jsonb_array_length(r.holders) > 0 then
        for l in select (h ->> 'type')::uuid as type_id, h ->> 'name' as name
                   from jsonb_array_elements(r.holders) with ordinality as x(h, n) order by n loop
            insert into event_tickets (request_id, event_id, type_id, holder, created_at)
            values (r.id, r.event_id, l.type_id, l.name, clock_timestamp());
        end loop;
    else
        for l in select l2.type_id, l2.qty from event_ticket_lines l2 where l2.request_id = r.id loop
            for i in 1 .. l.qty loop
                insert into event_tickets (request_id, event_id, type_id, holder, created_at) values (r.id, r.event_id, l.type_id, r.buyer_name, clock_timestamp());
            end loop;
        end loop;
    end if;
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


revoke execute on function event_ticket_request(text, text, text, text, jsonb, text, jsonb) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function event_ticket_request(text, text, text, text, jsonb, text, jsonb) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function event_ticket_request(text, text, text, text, jsonb, text, jsonb) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
