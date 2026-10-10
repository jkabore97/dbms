-- ============================================================
-- test_batch125.sql — a service is booked, not basketed (125).
--
-- The claims, for a shop, a farm and an association alike:
--   * the slot: given, in the future, within the next 14 days, on :00 or
--     :30, on a day the vitrine opens and inside its hours that day — each
--     refused in French otherwise; a vitrine with no hours takes every day
--     08:00–20:00; a night shop's hours after midnight belong to the day
--     before;
--   * a service is booked alone: beside goods, or two services, refused;
--   * how many only for a service by the person or by the hour (1 to 20);
--     any other service is booked once;
--   * the business confirms (decide_order), proposes another time
--     (propose_booking_time, the same slot rules) or refuses
--     (refuse_order); the customer accepts the proposal
--     (accept_booking_time) — confirmed at the new time — or cancels;
--   * each step rings the other side: booking_confirmed, booking_proposed,
--     booking_declined (the customer), booking_accepted and the request
--     itself (the business), with the day and the time;
--   * nobody but the business answers; nobody but the customer accepts;
--     the street (anon) calls none of the doors; the helpers are nobody's;
--   * the lists say the slot; the red number leaves out a booking waiting
--     for the customer;
--   * an app installed before 125 still books as 109 let it: a basket of
--     services with no slot, its day in the note — booked_for null, 109's
--     rules, bells and answers;
--   * booking_hours hands the business the hours its proposals are held to;
--   * P1: an order of goods, and that slot-less basket of services, are
--     exactly what 109 and 115 made them — the order, its lines, its bells,
--     each answer, each refusal.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- Earlier suites re-apply older migrations over 125's functions (098's,
-- 099's, 101's, 109's place_order; 115's decide_order) and hand the app's
-- roles every function: 125 again, so what follows is 125's own.
\i database/migrations/125_service_booking.sql

update platform_settings set value = '1'
 where key in ('vitrine_min_items', 'vitrine_min_items_association');

insert into auth.users (id, phone, email, raw_user_meta_data) values
    ('12512512-0000-0000-0000-000000000001', '+22612500001', null, '{"full_name": "Awa Boutique125"}'),
    ('12512512-0000-0000-0000-000000000002', '+22612500002', null, '{"full_name": "Ignace Ferme125"}'),
    ('12512512-0000-0000-0000-000000000003', '+22612500003', null, '{"full_name": "Israël Entraide125"}'),
    ('12512512-0000-0000-0000-000000000004', null, 'cliente125@example.com', '{"full_name": "Cliente Cent-Vingt-Cinq"}'),
    ('12512512-0000-0000-0000-000000000005', null, 'autre125@example.com',   '{"full_name": "Autre Personne"}');
insert into orgs (id, name, slug, profile, default_currency, plan, storefront_enabled, storefront_blurb, storefront_style) values
    -- Monday to Saturday, 08:00–18:00.
    ('12500000-0000-0000-0000-000000000001', 'Boutique Cent-Vingt-Cinq', 'boutique-125', 'retail', 'XOF', 'free', true, 'Bienvenue',
     '{"schedule": {"days": [1, 2, 3, 4, 5, 6], "open": "08:00", "close": "18:00"}}'),
    -- No hours set.
    ('12500000-0000-0000-0000-000000000002', 'Ferme Cent-Vingt-Cinq', 'ferme-125', 'farm', 'XOF', 'free', true, 'Bienvenue', '{}'),
    -- Friday night, 20:00 to 02:00.
    ('12500000-0000-0000-0000-000000000003', 'Entraide Cent-Vingt-Cinq', 'entraide-125', 'association', 'XOF', 'free', true, 'Bienvenue',
     '{"schedule": {"days": [5], "open": "20:00", "close": "02:00"}}');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    ('12500000-0000-0000-0000-000000000001', '12512512-0000-0000-0000-000000000001', 'owner', 'org', '12500000-0000-0000-0000-000000000001', 'full'),
    ('12500000-0000-0000-0000-000000000002', '12512512-0000-0000-0000-000000000002', 'owner', 'org', '12500000-0000-0000-0000-000000000002', 'full'),
    ('12500000-0000-0000-0000-000000000003', '12512512-0000-0000-0000-000000000003', 'owner', 'org', '12500000-0000-0000-0000-000000000003', 'full');
insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published) values
    ('125aaaaa-0000-0000-0000-000000000001', '12500000-0000-0000-0000-000000000001', 'Savon 125', 500, 300, 5, true, true),
    ('125aaaaa-0000-0000-0000-000000000004', '12500000-0000-0000-0000-000000000002', 'Œufs 125', 2500, 0, 10, true, true);
insert into products (id, org_id, name, sale_price, unit, is_service, is_active, is_published) values
    ('125aaaaa-0000-0000-0000-000000000002', '12500000-0000-0000-0000-000000000001', 'Coupe 125', 3000, 'séance', true, true, true),
    ('125aaaaa-0000-0000-0000-000000000003', '12500000-0000-0000-0000-000000000001', 'Cours 125', 2000, 'heure', true, true, true),
    ('125aaaaa-0000-0000-0000-000000000005', '12500000-0000-0000-0000-000000000002', 'Visite 125', 1000, 'personne', true, true, true),
    ('125aaaaa-0000-0000-0000-000000000006', '12500000-0000-0000-0000-000000000003', 'Consultation 125', 1000, null, true, true, true);

-- The first day at least p_ahead days from today (Ouagadougou) that is
-- weekday p_dow (1 = lundi), at p_time there.
create or replace function pg_temp.slot(p_ahead int, p_dow int, p_time time)
returns timestamptz
language sql
as $$
    select ((g::date + p_time) at time zone 'Africa/Ouagadougou')
      from generate_series((now() at time zone 'Africa/Ouagadougou')::date + p_ahead,
                           (now() at time zone 'Africa/Ouagadougou')::date + p_ahead + 6,
                           interval '1 day') g
     where extract(isodow from g)::int = p_dow
     order by g
     limit 1;
$$;

-- A call as a person (PostgREST's way: the role, the subject), taken back:
-- '(went through)' or the refusal's words.
create or replace function pg_temp.try125(p_who uuid, p_sql text, p_role text default 'authenticated')
returns text
language plpgsql
as $$
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true);
    begin
        execute format('set local role %I', p_role);
        execute p_sql;
        raise exception using errcode = 'P0125', message = 'taken back';
    exception
        when sqlstate 'P0125' then
            execute 'reset role';
            return '(went through)';
        when others then
            execute 'reset role';
            return sqlerrm;
    end;
end;
$$;

-- The same call, kept: its answer as text.
create or replace function pg_temp.do125(p_who uuid, p_sql text)
returns text
language plpgsql
as $$
declare
    v text;
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true);
    execute 'set local role authenticated';
    execute p_sql into v;
    execute 'reset role';
    return v;
end;
$$;

create or replace function pg_temp.book125(p_slug text, p_product text, p_at timestamptz, p_qty int default 1)
returns text
language sql
as $$
    select format('select book_service(%L, %L::uuid, %L::timestamptz, %s, %L)',
                  p_slug, p_product, p_at, p_qty, 'Pour ma fille');
$$;

\echo ''
\echo '--- TEST 1: the slot — past, beyond 14 days, a closed day, outside the hours, not on :00/:30, missing ---'
do $$
declare
    v_buyer constant uuid := '12512512-0000-0000-0000-000000000004';
    v_tue   timestamptz := pg_temp.slot(2, 2, '10:00');
    r       record;
begin
    for r in select * from (values
        ('past',            pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002',
                                date_trunc('hour', now()) - interval '1 hour'),
                            'Cette heure est déjà passée : choisissez-en une autre'),
        ('beyond 14 days',  pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002',
                                pg_temp.slot(15, 2, '10:00')),
                            'Un rendez-vous se prend dans les 14 prochains jours'),
        ('a closed day',    pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002',
                                pg_temp.slot(2, 7, '10:00')),
                            'Fermé ce jour-là : choisissez un autre jour'),
        ('outside hours',   pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002',
                                pg_temp.slot(2, 2, '18:00')),
                            'Fermé à cette heure : choisissez une heure d''ouverture'),
        ('before opening',  pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002',
                                pg_temp.slot(2, 2, '07:30')),
                            'Fermé à cette heure : choisissez une heure d''ouverture'),
        ('not on :00/:30',  pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002',
                                v_tue + interval '15 minutes'),
                            'Un rendez-vous commence à l''heure pile ou à la demie'),
        ('missing',         format('select book_service(%L, %L::uuid, null)', 'boutique-125',
                                   '125aaaaa-0000-0000-0000-000000000002'),
                            'Choisissez le jour et l''heure du rendez-vous'),
        ('missing, through place_order',
                            format('select place_order(%L, %L::jsonb, %L, %L)', 'boutique-125',
                                   '[{"product_id": "125aaaaa-0000-0000-0000-000000000002", "quantity": 1, "booked_for": null}]',
                                   'pickup', 'Samedi 10 h'),
                            'Choisissez le jour et l''heure du rendez-vous'),
        ('a slot on goods', format('select place_order(%L, %L::jsonb)', 'boutique-125',
                                   jsonb_build_array(jsonb_build_object('product_id', '125aaaaa-0000-0000-0000-000000000001',
                                                                        'quantity', 1, 'booked_for', v_tue))),
                            'Seul un service se réserve à une heure'),
        ('unreadable',      format('select place_order(%L, %L::jsonb)', 'boutique-125',
                                   '[{"product_id": "125aaaaa-0000-0000-0000-000000000002", "quantity": 1, "booked_for": "demain"}]'),
                            'L''heure du rendez-vous est illisible')
    ) c(label, call, want) loop
        if pg_temp.try125(v_buyer, r.call) <> r.want then
            raise exception 'FAIL: « % » answered « % », not « % »', r.label, pg_temp.try125(v_buyer, r.call), r.want;
        end if;
    end loop;
    -- In the hours, on :00 and on :30, the last half-hour before closing.
    if pg_temp.try125(v_buyer, pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002', v_tue)) <> '(went through)'
       or pg_temp.try125(v_buyer, pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002',
                                                  pg_temp.slot(2, 2, '17:30'))) <> '(went through)'
       or pg_temp.try125(v_buyer, pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002',
                                                  pg_temp.slot(2, 6, '08:00'))) <> '(went through)' then
        raise exception 'FAIL: a slot inside the hours was refused';
    end if;
    -- No hours set (the farm): every day, 08:00–20:00.
    if pg_temp.try125(v_buyer, pg_temp.book125('ferme-125', '125aaaaa-0000-0000-0000-000000000005',
                                               pg_temp.slot(2, 7, '19:30'), 3)) <> '(went through)'
       or pg_temp.try125(v_buyer, pg_temp.book125('ferme-125', '125aaaaa-0000-0000-0000-000000000005',
                                                  pg_temp.slot(2, 7, '20:00'), 3))
          <> 'Fermé à cette heure : choisissez une heure d''ouverture'
       or pg_temp.try125(v_buyer, pg_temp.book125('ferme-125', '125aaaaa-0000-0000-0000-000000000005',
                                                  pg_temp.slot(2, 3, '07:30'), 3))
          <> 'Fermé à cette heure : choisissez une heure d''ouverture' then
        raise exception 'FAIL: a vitrine with no hours is not every day 08:00–20:00';
    end if;
    -- A night (the association, Friday 20:00–02:00): Saturday 01:30 is
    -- Friday's; Friday 19:30 is not yet open; Saturday from 02:00 is a day
    -- the vitrine does not open, said as such (the night before is no
    -- reason to say « à cette heure »); Thursday is closed.
    if pg_temp.try125(v_buyer, pg_temp.book125('entraide-125', '125aaaaa-0000-0000-0000-000000000006',
                                               pg_temp.slot(2, 6, '01:30'))) <> '(went through)'
       or pg_temp.try125(v_buyer, pg_temp.book125('entraide-125', '125aaaaa-0000-0000-0000-000000000006',
                                                  pg_temp.slot(2, 5, '23:30'))) <> '(went through)'
       or pg_temp.try125(v_buyer, pg_temp.book125('entraide-125', '125aaaaa-0000-0000-0000-000000000006',
                                                  pg_temp.slot(2, 6, '02:00')))
          <> 'Fermé ce jour-là : choisissez un autre jour'
       or pg_temp.try125(v_buyer, pg_temp.book125('entraide-125', '125aaaaa-0000-0000-0000-000000000006',
                                                  pg_temp.slot(2, 6, '10:00')))
          <> 'Fermé ce jour-là : choisissez un autre jour'
       or pg_temp.try125(v_buyer, pg_temp.book125('entraide-125', '125aaaaa-0000-0000-0000-000000000006',
                                                  pg_temp.slot(2, 5, '19:30')))
          <> 'Fermé à cette heure : choisissez une heure d''ouverture'
       or pg_temp.try125(v_buyer, pg_temp.book125('entraide-125', '125aaaaa-0000-0000-0000-000000000006',
                                                  pg_temp.slot(2, 4, '21:00')))
          <> 'Fermé ce jour-là : choisissez un autre jour' then
        raise exception 'FAIL: a night shop''s hours';
    end if;
    raise notice 'PASS: the slot — past, beyond 14 days, a closed day (also the day after an open night), outside the hours, not on :00/:30, missing, unreadable, on goods — each refused in French; inside the hours taken; no hours = every day 08:00–20:00; a night''s hours after midnight are the day before''s (shop, farm, association)';
end $$;

\echo ''
\echo '--- TEST 2: a service is booked alone — never with goods, never two ---'
do $$
declare
    v_buyer constant uuid := '12512512-0000-0000-0000-000000000004';
    v_at    text := pg_temp.slot(2, 2, '10:00')::text;
    v       text;
begin
    v := pg_temp.try125(v_buyer, format('select place_order(%L, %L::jsonb)', 'boutique-125',
            jsonb_build_array(
                jsonb_build_object('product_id', '125aaaaa-0000-0000-0000-000000000002', 'quantity', 1, 'booked_for', v_at),
                jsonb_build_object('product_id', '125aaaaa-0000-0000-0000-000000000001', 'quantity', 1))));
    if v <> 'Un service se réserve seul : il ne se mélange pas aux articles d''un panier' then
        raise exception 'FAIL: a service with goods gave « % »', v;
    end if;
    v := pg_temp.try125(v_buyer, format('select place_order(%L, %L::jsonb)', 'boutique-125',
            jsonb_build_array(
                jsonb_build_object('product_id', '125aaaaa-0000-0000-0000-000000000002', 'quantity', 1, 'booked_for', v_at),
                jsonb_build_object('product_id', '125aaaaa-0000-0000-0000-000000000003', 'quantity', 1, 'booked_for', v_at))));
    if v <> 'Une réservation porte sur un seul service' then
        raise exception 'FAIL: two services gave « % »', v;
    end if;
    v := pg_temp.try125(v_buyer, format('select place_order(%L, %L::jsonb, %L, null, %L)', 'boutique-125',
            jsonb_build_array(jsonb_build_object('product_id', '125aaaaa-0000-0000-0000-000000000002',
                                                 'quantity', 1, 'booked_for', v_at)),
            'delivery', 'Gounghin'));
    if v <> 'Un service se réserve sur rendez-vous : pas de livraison' then
        raise exception 'FAIL: a service delivered gave « % »', v;
    end if;
    v := pg_temp.try125(v_buyer, format('select book_service(%L, %L::uuid, %L::timestamptz)', 'boutique-125',
            '125aaaaa-0000-0000-0000-000000000001', v_at));
    if v <> 'Ce service n''est pas sur cette vitrine' then
        raise exception 'FAIL: booking an article gave « % »', v;
    end if;
    v := pg_temp.try125(v_buyer, format('select book_service(%L, %L::uuid, %L::timestamptz)', 'ferme-125',
            '125aaaaa-0000-0000-0000-000000000002', v_at));
    if v <> 'Ce service n''est pas sur cette vitrine' then
        raise exception 'FAIL: booking another vitrine''s service gave « % »', v;
    end if;
    raise notice 'PASS: a service beside goods, two services, a service delivered, an article or another vitrine''s service through « Réserver » — each refused in French';
end $$;

\echo ''
\echo '--- TEST 3: how many — only for a service by the person or by the hour ---'
do $$
declare
    v_buyer constant uuid := '12512512-0000-0000-0000-000000000004';
    v_tue   timestamptz := pg_temp.slot(2, 2, '10:00');
begin
    if pg_temp.try125(v_buyer, pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000003', v_tue, 3)) <> '(went through)'
       or pg_temp.try125(v_buyer, pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000003', v_tue, 20)) <> '(went through)'
       or pg_temp.try125(v_buyer, pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000003', v_tue, 21)) <> 'De 1 à 20 heures'
       or pg_temp.try125(v_buyer, pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000003', v_tue, 0)) <> 'De 1 à 20 heures'
       or pg_temp.try125(v_buyer, pg_temp.book125('ferme-125', '125aaaaa-0000-0000-0000-000000000005', v_tue, 4)) <> '(went through)'
       or pg_temp.try125(v_buyer, pg_temp.book125('ferme-125', '125aaaaa-0000-0000-0000-000000000005', v_tue, 25)) <> 'De 1 à 20 personnes'
       or pg_temp.try125(v_buyer, pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002', v_tue, 2))
          <> 'Ce service se réserve une fois : pas de quantité à choisir'
       or pg_temp.try125(v_buyer, pg_temp.book125('entraide-125', '125aaaaa-0000-0000-0000-000000000006',
                                                  pg_temp.slot(2, 5, '21:00'), 2))
          <> 'Ce service se réserve une fois : pas de quantité à choisir'
       or pg_temp.try125(v_buyer, format('select place_order(%L, %L::jsonb)', 'boutique-125',
              jsonb_build_array(jsonb_build_object('product_id', '125aaaaa-0000-0000-0000-000000000003',
                                                   'quantity', 1.5, 'booked_for', v_tue)))) <> 'De 1 à 20 heures' then
        raise exception 'FAIL: the quantity rules';
    end if;
    raise notice 'PASS: by the hour and by the person, 1 to 20 (whole); a « séance » or a service with no unit, once (shop, farm, association)';
end $$;

-- The bookings answered below, kept.
create temporary table t125 (label text primary key, id uuid);
insert into t125 values
    ('shop',  pg_temp.do125('12512512-0000-0000-0000-000000000004',
                pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002', pg_temp.slot(2, 2, '10:00')))::uuid),
    ('farm',  pg_temp.do125('12512512-0000-0000-0000-000000000004',
                pg_temp.book125('ferme-125', '125aaaaa-0000-0000-0000-000000000005', pg_temp.slot(2, 3, '09:30'), 4))::uuid),
    ('assoc', pg_temp.do125('12512512-0000-0000-0000-000000000004',
                pg_temp.book125('entraide-125', '125aaaaa-0000-0000-0000-000000000006', pg_temp.slot(2, 5, '21:00')))::uuid),
    ('decline', pg_temp.do125('12512512-0000-0000-0000-000000000004',
                pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000003', pg_temp.slot(2, 4, '15:00'), 2))::uuid);

\echo ''
\echo '--- TEST 4: a booking is an order: its slot, its note, one line, « sur rendez-vous », the business rung with the day and the time ---'
do $$
declare
    o orders;
    n notifications;
begin
    select * into o from orders where id = (select id from t125 where label = 'shop');
    if o.booked_for is distinct from pg_temp.slot(2, 2, '10:00') or o.proposed_for is not null
       or o.status <> 'pending' or o.fulfilment <> 'pickup' or o.note <> 'Pour ma fille'
       or o.payment_method <> 'cash' or o.total <> 3000 or o.delivery_fee is not null
       or (select count(*) from order_lines l where l.order_id = o.id and l.is_service and l.quantity = 1) <> 1
       or (select count(*) from order_lines l where l.order_id = o.id) <> 1 then
        raise exception 'FAIL: the booking written was %', to_jsonb(o);
    end if;
    if (select quantity from order_lines where order_id = (select id from t125 where label = 'farm')) <> 4 then
        raise exception 'FAIL: the farm''s visit for 4 kept another count';
    end if;
    select * into n from notifications
     where kind = 'new_order' and (params ->> 'order_id')::uuid = o.id;
    if n.recipient_id <> '12512512-0000-0000-0000-000000000001'
       or n.message <> 'Rendez-vous demandé par Cliente Cent-Vingt-Cinq — '
                       || booking_when_fr(o.booked_for) || ' : '
                       || to_char(3000::numeric, 'FM999G999G999D00') || ' XOF'
       or n.message not like '% mardi %, 10:00 : %'
       or (n.params ->> 'booking')::boolean is not true
       or (n.params ->> 'at')::timestamptz <> o.booked_for
       or n.scope <> 'shop' then
        raise exception 'FAIL: the business''s bell was %', to_jsonb(n);
    end if;
    raise notice 'PASS: the booking is a pending order of one service line, with its slot and its note; the business hears « % »', n.message;
end $$;

\echo ''
\echo '--- TEST 5: the lists say the slot; the goods'' lines say nothing new ---'
do $$
declare
    v jsonb;
begin
    perform set_config('request.jwt.claim.sub', '12512512-0000-0000-0000-000000000004', true);
    select lines into v from my_orders() where id = (select id from t125 where label = 'shop');
    if (v -> 0 ->> 'booked_for')::timestamptz <> pg_temp.slot(2, 2, '10:00')
       or not (v -> 0 ? 'proposed_for') or v -> 0 -> 'proposed_for' <> 'null'::jsonb then
        raise exception 'FAIL: my_orders() said %', v;
    end if;
    perform set_config('request.jwt.claim.sub', '12512512-0000-0000-0000-000000000001', true);
    select lines into v from shop_orders('12500000-0000-0000-0000-000000000001')
     where id = (select id from t125 where label = 'shop');
    if (v -> 0 ->> 'booked_for')::timestamptz <> pg_temp.slot(2, 2, '10:00') then
        raise exception 'FAIL: shop_orders() said %', v;
    end if;
    raise notice 'PASS: my_orders() and shop_orders() carry booked_for and proposed_for on a booking''s line';
end $$;

\echo ''
\echo '--- TEST 6: nobody but the business answers; nobody but the customer accepts ---'
do $$
declare
    v_shop  constant uuid := (select id from t125 where label = 'shop');
    v_at    timestamptz := pg_temp.slot(2, 2, '11:00');
    v       text;
begin
    foreach v in array array[
        pg_temp.try125('12512512-0000-0000-0000-000000000005', format('select decide_order(%L, %L)', v_shop, 'accepted')),
        pg_temp.try125('12512512-0000-0000-0000-000000000004', format('select decide_order(%L, %L)', v_shop, 'accepted')),
        pg_temp.try125('12512512-0000-0000-0000-000000000002', format('select propose_booking_time(%L, %L)', v_shop, v_at)),
        pg_temp.try125('12512512-0000-0000-0000-000000000004', format('select propose_booking_time(%L, %L)', v_shop, v_at)),
        pg_temp.try125('12512512-0000-0000-0000-000000000005', format('select refuse_order(%L, %L)', v_shop, 'Non'))] loop
        if v <> 'Only the shop can answer its orders' then
            raise exception 'FAIL: a stranger''s answer gave « % »', v;
        end if;
    end loop;
    v := pg_temp.try125('12512512-0000-0000-0000-000000000005', format('select accept_booking_time(%L)', v_shop));
    if v <> 'Rendez-vous introuvable' then
        raise exception 'FAIL: another person accepting gave « % »', v;
    end if;
    v := pg_temp.try125('12512512-0000-0000-0000-000000000004', format('select accept_booking_time(%L)', v_shop));
    if v <> 'Aucune autre heure n''est proposée pour ce rendez-vous' then
        raise exception 'FAIL: accepting with nothing proposed gave « % »', v;
    end if;
    raise notice 'PASS: a stranger, the customer, another business cannot confirm, propose or refuse; nobody accepts another''s booking, nor one with nothing proposed';
end $$;

\echo ''
\echo '--- TEST 7: confirm (the shop), propose then accept (the farm), propose then refuse (the association), refuse (the shop''s lesson) ---'
do $$
declare
    v_shop  constant uuid := (select id from t125 where label = 'shop');
    v_farm  constant uuid := (select id from t125 where label = 'farm');
    v_assoc constant uuid := (select id from t125 where label = 'assoc');
    v_dec   constant uuid := (select id from t125 where label = 'decline');
    v_new   timestamptz := pg_temp.slot(2, 3, '14:00');
    v       text;
    o       orders;
    n       notifications;
begin
    -- The shop confirms.
    perform pg_temp.do125('12512512-0000-0000-0000-000000000001',
                          format('select decide_order(%L, %L)::text', v_shop, 'accepted'));
    select * into o from orders where id = v_shop;
    select * into n from notifications where kind = 'booking_confirmed' and (params ->> 'order_id')::uuid = v_shop;
    if o.status <> 'accepted' or o.booked_for <> pg_temp.slot(2, 2, '10:00')
       or n.recipient_id <> '12512512-0000-0000-0000-000000000004'
       or n.message <> 'Votre rendez-vous chez Boutique Cent-Vingt-Cinq est confirmé : ' || booking_when_fr(o.booked_for)
       or n.scope <> 'customer' or (n.params ->> 'at')::timestamptz <> o.booked_for then
        raise exception 'FAIL: confirming gave % and %', to_jsonb(o), to_jsonb(n);
    end if;
    if exists (select 1 from notifications where kind = 'order_accepted' and (params ->> 'order_id')::uuid = v_shop) then
        raise exception 'FAIL: a confirmed booking also rang « acceptée »';
    end if;
    -- Proposing on a confirmed booking: already answered.
    v := pg_temp.try125('12512512-0000-0000-0000-000000000001',
                        format('select propose_booking_time(%L, %L)', v_shop, pg_temp.slot(2, 2, '11:00')));
    if v <> 'Ce rendez-vous a déjà une réponse' then
        raise exception 'FAIL: proposing on a confirmed booking gave « % »', v;
    end if;

    -- The farm proposes another time: the same slot rules.
    v := pg_temp.try125('12512512-0000-0000-0000-000000000002',
                        format('select propose_booking_time(%L, %L)', v_farm, pg_temp.slot(2, 3, '20:30')));
    if v <> 'Fermé à cette heure : choisissez une heure d''ouverture' then
        raise exception 'FAIL: proposing outside the hours gave « % »', v;
    end if;
    v := pg_temp.try125('12512512-0000-0000-0000-000000000002',
                        format('select propose_booking_time(%L, %L)', v_farm, pg_temp.slot(2, 3, '09:30')));
    if v <> 'C''est l''heure demandée : confirmez-la plutôt' then
        raise exception 'FAIL: proposing the time asked gave « % »', v;
    end if;
    perform pg_temp.do125('12512512-0000-0000-0000-000000000002',
                          format('select propose_booking_time(%L, %L)::text', v_farm, v_new));
    select * into o from orders where id = v_farm;
    select * into n from notifications where kind = 'booking_proposed' and (params ->> 'order_id')::uuid = v_farm;
    if o.status <> 'pending' or o.proposed_for <> v_new or o.booked_for <> pg_temp.slot(2, 3, '09:30')
       or n.recipient_id <> '12512512-0000-0000-0000-000000000004'
       or n.message <> 'Ferme Cent-Vingt-Cinq propose une autre heure pour votre rendez-vous : '
                       || booking_when_fr(v_new) || '. Acceptez-la dans Mes commandes.'
       or n.message not like '% mercredi %, 14:00. %' then
        raise exception 'FAIL: proposing gave % and %', to_jsonb(o), to_jsonb(n);
    end if;
    -- While it waits for the customer, the farm cannot confirm the old time,
    -- and its red number does not count it.
    v := pg_temp.try125('12512512-0000-0000-0000-000000000002', format('select decide_order(%L, %L)', v_farm, 'accepted'));
    if v <> 'Une autre heure est proposée : attendez la réponse du client' then
        raise exception 'FAIL: confirming during a proposal gave « % »', v;
    end if;
    perform set_config('request.jwt.claim.sub', '12512512-0000-0000-0000-000000000002', true);
    if shop_pending_orders('12500000-0000-0000-0000-000000000002') <> 0
       or (home_counts('12500000-0000-0000-0000-000000000002') ->> 'bookings')::int <> 0 then
        raise exception 'FAIL: a booking waiting for the customer is still counted: % / %',
            shop_pending_orders('12500000-0000-0000-0000-000000000002'),
            home_counts('12500000-0000-0000-0000-000000000002');
    end if;
    perform set_config('request.jwt.claim.sub', '12512512-0000-0000-0000-000000000003', true);
    if shop_pending_orders('12500000-0000-0000-0000-000000000003') <> 1
       or (home_counts('12500000-0000-0000-0000-000000000003') ->> 'bookings')::int <> 1 then
        raise exception 'FAIL: a booking to answer is not counted';
    end if;
    -- The customer accepts: confirmed at the new time; the farm hears it.
    perform pg_temp.do125('12512512-0000-0000-0000-000000000004',
                          format('select accept_booking_time(%L)::text', v_farm));
    select * into o from orders where id = v_farm;
    select * into n from notifications where kind = 'booking_accepted' and (params ->> 'order_id')::uuid = v_farm;
    if o.status <> 'accepted' or o.booked_for <> v_new or o.proposed_for is not null or o.decided_at is null
       or n.recipient_id <> '12512512-0000-0000-0000-000000000002'
       or n.message <> 'Cliente Cent-Vingt-Cinq accepte le rendez-vous : ' || booking_when_fr(v_new)
       or n.scope <> 'shop' then
        raise exception 'FAIL: accepting gave % and %', to_jsonb(o), to_jsonb(n);
    end if;
    -- The rest as any order: « Terminée », paid.
    perform pg_temp.do125('12512512-0000-0000-0000-000000000002',
                          format('select decide_order(%L, %L)::text', v_farm, 'picked_up'));
    perform pg_temp.do125('12512512-0000-0000-0000-000000000002',
                          format('select set_order_paid(%L, true)::text', v_farm));
    if (select status from orders where id = v_farm) <> 'picked_up'
       or (select paid_at from orders where id = v_farm) is null
       or not exists (select 1 from notifications where kind = 'order_picked_up'
                         and (params ->> 'order_id')::uuid = v_farm
                         and message = 'Votre réservation chez Ferme Cent-Vingt-Cinq : terminée') then
        raise exception 'FAIL: finishing a booking is not as finishing an order';
    end if;

    -- The association proposes, then refuses with its reason.
    perform pg_temp.do125('12512512-0000-0000-0000-000000000003',
                          format('select propose_booking_time(%L, %L)::text', v_assoc, pg_temp.slot(2, 6, '00:30')));
    perform pg_temp.do125('12512512-0000-0000-0000-000000000003',
                          format('select refuse_order(%L, %L)::text', v_assoc, 'Pas de place à cette heure'));
    select * into n from notifications where kind = 'booking_declined' and (params ->> 'order_id')::uuid = v_assoc;
    if (select status from orders where id = v_assoc) <> 'refused'
       or n.message <> 'Votre demande de rendez-vous chez Entraide Cent-Vingt-Cinq est refusée — Pas de place à cette heure'
       or n.params ->> 'reason' <> 'Pas de place à cette heure' then
        raise exception 'FAIL: refusing gave %', to_jsonb(n);
    end if;
    v := pg_temp.try125('12512512-0000-0000-0000-000000000004', format('select accept_booking_time(%L)', v_assoc));
    if v <> 'Aucune autre heure n''est proposée pour ce rendez-vous' then
        raise exception 'FAIL: accepting a refused booking gave « % »', v;
    end if;

    -- The shop refuses the lesson outright.
    perform pg_temp.do125('12512512-0000-0000-0000-000000000001',
                          format('select refuse_order(%L, %L)::text', v_dec, ''));
    if (select message from notifications where kind = 'booking_declined' and (params ->> 'order_id')::uuid = v_dec)
       <> 'Votre demande de rendez-vous chez Boutique Cent-Vingt-Cinq est refusée' then
        raise exception 'FAIL: a refusal with no reason';
    end if;
    raise notice 'PASS: confirmed (booking_confirmed), proposed (booking_proposed, the same rules, not confirmable meanwhile, off the red number), accepted (booking_accepted, confirmed at the new time), finished and paid as any order, refused with or without a reason (booking_declined)';
end $$;

\echo ''
\echo '--- TEST 8: the customer cancels a proposal; a proposal already past cannot be accepted ---'
do $$
declare
    v_id uuid;
    v    text;
begin
    v_id := pg_temp.do125('12512512-0000-0000-0000-000000000004',
                pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002', pg_temp.slot(2, 5, '16:00')))::uuid;
    perform pg_temp.do125('12512512-0000-0000-0000-000000000001',
                          format('select propose_booking_time(%L, %L)::text', v_id, pg_temp.slot(2, 5, '16:30')));
    -- The proposed time passes before the customer answers.
    update orders set proposed_for = now() - interval '1 minute' where id = v_id;
    v := pg_temp.try125('12512512-0000-0000-0000-000000000004', format('select accept_booking_time(%L)', v_id));
    if v <> 'Cette heure est passée : demandez-en une autre' then
        raise exception 'FAIL: accepting a past proposal gave « % »', v;
    end if;
    perform pg_temp.do125('12512512-0000-0000-0000-000000000004', format('select cancel_order(%L)::text', v_id));
    if (select status from orders where id = v_id) <> 'cancelled'
       or not exists (select 1 from notifications where kind = 'order_withdrawn'
                         and (params ->> 'order_id')::uuid = v_id
                         and message = 'Cliente Cent-Vingt-Cinq a annulé sa demande') then
        raise exception 'FAIL: cancelling a proposed booking';
    end if;
    raise notice 'PASS: a proposal already past is refused; the customer cancels (099''s cancel_order), the business hears it';
end $$;

\echo ''
\echo '--- TEST 9: the bell''s switches — « Mes réservations » off writes no booking bell ---'
do $$
declare
    v_id uuid;
begin
    insert into notification_prefs (user_id, type, enabled)
    values ('12512512-0000-0000-0000-000000000004', 'bookings', false);
    v_id := pg_temp.do125('12512512-0000-0000-0000-000000000004',
                pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002', pg_temp.slot(2, 1, '09:00')))::uuid;
    perform pg_temp.do125('12512512-0000-0000-0000-000000000001',
                          format('select propose_booking_time(%L, %L)::text', v_id, pg_temp.slot(2, 1, '09:30')));
    if exists (select 1 from notifications where (params ->> 'order_id')::uuid = v_id and kind like 'booking\_%') then
        raise exception 'FAIL: a booking bell rang with « Mes réservations » off';
    end if;
    if notification_type_of('booking_accepted', '{"to": "shop"}') <> 'shop_orders'
       or notification_type_of('booking_confirmed', '{"to": "customer"}') <> 'bookings' then
        raise exception 'FAIL: the booking kinds'' switches';
    end if;
    delete from notification_prefs where user_id = '12512512-0000-0000-0000-000000000004';
    raise notice 'PASS: booking_* rows answer to « Mes réservations » (the customer) and « Commandes de la vitrine » (the business)';
end $$;

\echo ''
\echo '--- TEST 10: the doors — the street calls none; the helpers are nobody''s ---'
do $$
declare
    f text;
    v text;
begin
    foreach f in array array['book_service(text, uuid, timestamptz, integer, text, text)',
                             'propose_booking_time(uuid, timestamptz)', 'accept_booking_time(uuid)'] loop
        if has_function_privilege('anon', f, 'execute') or has_function_privilege('public', f, 'execute') then
            raise exception 'FAIL: the street may call %', f;
        end if;
        if not has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: a signed-in person may not call %', f;
        end if;
    end loop;
    foreach f in array array['booking_tz()', 'booking_schedule(uuid)', 'vitrine_open_at(jsonb, timestamp)',
                             'booking_when_fr(timestamptz)', 'booking_check_slot(uuid, timestamptz)'] loop
        if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
           or has_function_privilege('public', f, 'execute') then
            raise exception 'FAIL: the helper % is open', f;
        end if;
    end loop;
    v := pg_temp.try125(null, pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002',
                                              pg_temp.slot(2, 2, '10:00')), 'anon');
    if v not like 'permission denied%' then
        raise exception 'FAIL: the street booked: « % »', v;
    end if;
    v := pg_temp.try125(null, pg_temp.book125('boutique-125', '125aaaaa-0000-0000-0000-000000000002',
                                              pg_temp.slot(2, 2, '10:00')));
    if v <> 'Sign in to order' then
        raise exception 'FAIL: signed out gave « % »', v;
    end if;
    if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.prosecdef
                  and p.proname in ('book_service', 'propose_booking_time', 'accept_booking_time',
                                    'booking_schedule', 'booking_check_slot')
                  and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')) then
        raise exception 'FAIL: a definer without a pinned search path';
    end if;
    raise notice 'PASS: anon calls no booking door (refused at the door); signed out is asked to sign in; the helpers are nobody''s; search paths pinned';
end $$;

\echo ''
\echo '--- TEST 10b: an app installed before 125 — a basket of services with no slot is 109''s « sur rendez-vous » ---'
do $$
declare
    v_buyer constant uuid := '12512512-0000-0000-0000-000000000004';
    v_id    uuid;
    v       text;
    o       orders;
    n       notifications;
    l       jsonb;
begin
    -- The old app's call: the service in the basket, its day in the note.
    v_id := pg_temp.do125(v_buyer, format('select place_order(%L, %L::jsonb, %L, %L)', 'boutique-125',
                '[{"product_id": "125aaaaa-0000-0000-0000-000000000002", "quantity": 1}]', 'pickup', 'Samedi 10 h'))::uuid;
    select * into o from orders where id = v_id;
    select * into n from notifications where kind = 'new_order' and (params ->> 'order_id')::uuid = v_id;
    if o.booked_for is not null or o.proposed_for is not null or o.status <> 'pending'
       or o.note <> 'Samedi 10 h' or o.total <> 3000
       or n.message <> 'Nouvelle demande de Cliente Cent-Vingt-Cinq : ' || to_char(3000::numeric, 'FM999G999G999D00') || ' XOF'
       or (n.params ->> 'booking')::boolean is not true or n.params ? 'at' then
        raise exception 'FAIL: the old app''s booking was % and %', to_jsonb(o), to_jsonb(n);
    end if;
    -- Its rules are 109's: the day in the note, never delivered; how many
    -- as the old basket said; goods beside it and two services, as 109 let them.
    if pg_temp.try125(v_buyer, format('select place_order(%L, %L::jsonb, %L, %L)', 'boutique-125',
              '[{"product_id": "125aaaaa-0000-0000-0000-000000000002", "quantity": 1}]', 'pickup', '  '))
          <> 'Indiquez la date et l''heure souhaitées'
       or pg_temp.try125(v_buyer, format('select place_order(%L, %L::jsonb, %L, %L, %L)', 'boutique-125',
              '[{"product_id": "125aaaaa-0000-0000-0000-000000000002", "quantity": 1}]', 'delivery', 'Samedi', 'Gounghin'))
          <> 'Un service se réserve sur rendez-vous : pas de livraison'
       or pg_temp.try125(v_buyer, format('select place_order(%L, %L::jsonb, %L, %L)', 'boutique-125',
              '[{"product_id": "125aaaaa-0000-0000-0000-000000000002", "quantity": 2}]', 'pickup', 'Samedi'))
          <> '(went through)'
       or pg_temp.try125(v_buyer, format('select place_order(%L, %L::jsonb)', 'boutique-125',
              '[{"product_id": "125aaaaa-0000-0000-0000-000000000002", "quantity": 1}, {"product_id": "125aaaaa-0000-0000-0000-000000000001", "quantity": 1}]'))
          <> '(went through)'
       or pg_temp.try125(v_buyer, format('select place_order(%L, %L::jsonb, %L, %L)', 'boutique-125',
              '[{"product_id": "125aaaaa-0000-0000-0000-000000000002", "quantity": 1}, {"product_id": "125aaaaa-0000-0000-0000-000000000003", "quantity": 3}]',
              'pickup', 'Samedi'))
          <> '(went through)' then
        raise exception 'FAIL: the old app''s rules are not 109''s';
    end if;
    -- The lists carry no slot on it; the business answers it as before 125
    -- (« acceptée », no booking_* bell), and cannot propose another time.
    perform set_config('request.jwt.claim.sub', v_buyer::text, true);
    select lines into l from my_orders() where id = v_id;
    if l -> 0 ? 'booked_for' then
        raise exception 'FAIL: an old booking''s line carries a slot: %', l;
    end if;
    if pg_temp.try125('12512512-0000-0000-0000-000000000001',
            format('select propose_booking_time(%L, %L)', v_id, pg_temp.slot(2, 2, '11:00')))
       <> 'Seul un rendez-vous peut changer d''heure' then
        raise exception 'FAIL: another time proposed on an old booking';
    end if;
    perform pg_temp.do125('12512512-0000-0000-0000-000000000001',
                          format('select decide_order(%L, %L)::text', v_id, 'accepted'));
    if not exists (select 1 from notifications where kind = 'order_accepted' and (params ->> 'order_id')::uuid = v_id
                      and message = 'Votre réservation chez Boutique Cent-Vingt-Cinq : acceptée')
       or exists (select 1 from notifications where kind like 'booking\_%' and (params ->> 'order_id')::uuid = v_id) then
        raise exception 'FAIL: an old booking was answered as a new one';
    end if;
    raise notice 'PASS: the app installed before 125 still books as 109 let it (note required, no delivery, goods beside it, two services); booked_for stays null, its bells and answers are 109''s/115''s';
end $$;

\echo ''
\echo '--- TEST 10c: the hours « Proposer une autre heure » offers — the business''s own, even with the vitrine closed ---'
do $$
declare
    v text;
begin
    update orgs set storefront_enabled = false where id = '12500000-0000-0000-0000-000000000001';
    if pg_temp.do125('12512512-0000-0000-0000-000000000001',
            $q$select booking_hours('12500000-0000-0000-0000-000000000001')::text$q$)::jsonb
       <> '{"days": [1, 2, 3, 4, 5, 6], "open": "08:00", "close": "18:00"}'::jsonb
       or pg_temp.do125('12512512-0000-0000-0000-000000000002',
            $q$select booking_hours('12500000-0000-0000-0000-000000000002')::text$q$)::jsonb
       <> '{"days": [1, 2, 3, 4, 5, 6, 7], "open": "08:00", "close": "20:00"}'::jsonb then
        raise exception 'FAIL: booking_hours did not hand the hours the slot rules read';
    end if;
    update orgs set storefront_enabled = true where id = '12500000-0000-0000-0000-000000000001';
    v := pg_temp.try125('12512512-0000-0000-0000-000000000004',
            $q$select booking_hours('12500000-0000-0000-0000-000000000001')$q$);
    if v <> 'Only the shop can answer its orders' then
        raise exception 'FAIL: a customer read the hours: « % »', v;
    end if;
    if has_function_privilege('anon', 'booking_hours(uuid)', 'execute')
       or has_function_privilege('public', 'booking_hours(uuid)', 'execute')
       or not has_function_privilege('authenticated', 'booking_hours(uuid)', 'execute') then
        raise exception 'FAIL: booking_hours'' doors';
    end if;
    raise notice 'PASS: booking_hours hands the business the hours its proposal is held to (closed vitrine too; none set = every day 08:00–20:00); nobody else; not the street';
end $$;

\echo ''
\echo '--- TEST 11: a showcase refuses a booking as it refuses an order ---'
do $$
declare
    v text;
begin
    update orgs set showcase = true where id = '12500000-0000-0000-0000-000000000003';
    v := pg_temp.try125('12512512-0000-0000-0000-000000000004',
            pg_temp.book125('entraide-125', '125aaaaa-0000-0000-0000-000000000006', pg_temp.slot(2, 5, '21:00')));
    update orgs set showcase = false where id = '12500000-0000-0000-0000-000000000003';
    if v not like 'Pas à proximité%' then
        raise exception 'FAIL: a showcase took a booking: « % »', v;
    end if;
    raise notice 'PASS: « Pas à proximité » — a vitrine d''exemple takes no booking';
end $$;

\echo ''
\echo '--- TEST 12: P1 — an order of goods, and an older app''s slot-less basket of services, are what 109 and 115 made them: the order, its lines, its bells, each answer, each refusal ---'
begin;
create or replace function pg_temp.goods125()
returns jsonb
language plpgsql
as $$
declare
    v_a  uuid;
    v_b  uuid;
    v_c  uuid;
    -- An older app's bookings (no slot): a service alone, goods beside a
    -- service, two services, the farm's visit for three.
    v_l1 uuid;
    v_l2 uuid;
    v_l3 uuid;
    v_l4 uuid;
    v_refused jsonb;
    v_out jsonb;
begin
    begin
        v_a := pg_temp.do125('12512512-0000-0000-0000-000000000004',
                 format('select place_order(%L, %L::jsonb, %L, %L, null, %L)', 'boutique-125',
                        '[{"product_id": "125aaaaa-0000-0000-0000-000000000001", "quantity": 2}]',
                        'pickup', 'Vers midi', '70 12 50 00'))::uuid;
        v_b := pg_temp.do125('12512512-0000-0000-0000-000000000004',
                 format('select place_order(%L, %L::jsonb)', 'ferme-125',
                        '[{"product_id": "125aaaaa-0000-0000-0000-000000000004", "quantity": 3}]'))::uuid;
        v_c := pg_temp.do125('12512512-0000-0000-0000-000000000004',
                 format('select place_order(%L, %L::jsonb)', 'boutique-125',
                        '[{"product_id": "125aaaaa-0000-0000-0000-000000000001", "quantity": 1}]'))::uuid;
        perform pg_temp.do125('12512512-0000-0000-0000-000000000001', format('select decide_order(%L, %L)::text', v_a, 'accepted'));
        perform pg_temp.do125('12512512-0000-0000-0000-000000000001', format('select decide_order(%L, %L)::text', v_a, 'ready'));
        perform pg_temp.do125('12512512-0000-0000-0000-000000000001', format('select decide_order(%L, %L)::text', v_a, 'picked_up'));
        perform pg_temp.do125('12512512-0000-0000-0000-000000000002', format('select decide_order(%L, %L)::text', v_b, 'accepted'));
        perform pg_temp.do125('12512512-0000-0000-0000-000000000001', format('select refuse_order(%L, %L)::text', v_c, 'Plus en stock'));
        v_l1 := pg_temp.do125('12512512-0000-0000-0000-000000000004',
                 format('select place_order(%L, %L::jsonb, %L, %L)', 'boutique-125',
                        '[{"product_id": "125aaaaa-0000-0000-0000-000000000002", "quantity": 1}]',
                        'pickup', 'Samedi 10 h'))::uuid;
        v_l2 := pg_temp.do125('12512512-0000-0000-0000-000000000004',
                 format('select place_order(%L, %L::jsonb, %L, %L)', 'boutique-125',
                        '[{"product_id": "125aaaaa-0000-0000-0000-000000000002", "quantity": 1}, {"product_id": "125aaaaa-0000-0000-0000-000000000001", "quantity": 1}]',
                        'pickup', 'Avec le savon'))::uuid;
        v_l3 := pg_temp.do125('12512512-0000-0000-0000-000000000004',
                 format('select place_order(%L, %L::jsonb, %L, %L)', 'boutique-125',
                        '[{"product_id": "125aaaaa-0000-0000-0000-000000000002", "quantity": 1}, {"product_id": "125aaaaa-0000-0000-0000-000000000003", "quantity": 2}]',
                        'pickup', 'Deux services'))::uuid;
        v_l4 := pg_temp.do125('12512512-0000-0000-0000-000000000004',
                 format('select place_order(%L, %L::jsonb, %L, %L)', 'ferme-125',
                        '[{"product_id": "125aaaaa-0000-0000-0000-000000000005", "quantity": 3}]',
                        'pickup', 'Dimanche matin'))::uuid;
        perform pg_temp.do125('12512512-0000-0000-0000-000000000001', format('select decide_order(%L, %L)::text', v_l1, 'accepted'));
        perform pg_temp.do125('12512512-0000-0000-0000-000000000001', format('select decide_order(%L, %L)::text', v_l1, 'picked_up'));
        perform pg_temp.do125('12512512-0000-0000-0000-000000000001', format('select decide_order(%L, %L)::text', v_l2, 'accepted'));
        perform pg_temp.do125('12512512-0000-0000-0000-000000000002', format('select refuse_order(%L, %L)::text', v_l4, 'Complet'));
        v_refused := jsonb_build_object(
            'no note', pg_temp.try125('12512512-0000-0000-0000-000000000004',
                format('select place_order(%L, %L::jsonb)', 'boutique-125',
                       '[{"product_id": "125aaaaa-0000-0000-0000-000000000002", "quantity": 1}]')),
            'delivered', pg_temp.try125('12512512-0000-0000-0000-000000000004',
                format('select place_order(%L, %L::jsonb, %L, %L, %L)', 'boutique-125',
                       '[{"product_id": "125aaaaa-0000-0000-0000-000000000002", "quantity": 1}]', 'delivery', 'Samedi', 'Gounghin')),
            'too many soaps', pg_temp.try125('12512512-0000-0000-0000-000000000004',
                format('select place_order(%L, %L::jsonb)', 'boutique-125',
                       '[{"product_id": "125aaaaa-0000-0000-0000-000000000001", "quantity": 50}]')));
        select jsonb_build_object(
                   'orders', (select jsonb_agg(to_jsonb(o) - 'id' - 'created_at' - 'updated_at' - 'decided_at'
                                                - 'handover_code' - 'customer_id' - 'number' - 'ref'
                                                order by o.total, o.org_id, o.note)
                                from orders o where o.id in (v_a, v_b, v_c, v_l1, v_l2, v_l3, v_l4)),
                   'lines', (select jsonb_agg(to_jsonb(l) - 'id' - 'order_id' order by l.name, l.quantity)
                               from order_lines l where l.order_id in (v_a, v_b, v_c, v_l1, v_l2, v_l3, v_l4)),
                   'bells', (select jsonb_agg(jsonb_build_object('to', n.recipient_id, 'kind', n.kind,
                                                                 'message', n.message,
                                                                 'params', n.params - 'order_id')
                                              order by n.kind, n.message, (n.params - 'order_id')::text)
                               from notifications n
                              where (n.params ->> 'order_id')::uuid in (v_a, v_b, v_c, v_l1, v_l2, v_l3, v_l4)),
                   'refused', v_refused)
          into v_out;
        raise exception using errcode = 'P0125', message = 'taken back';
    exception when sqlstate 'P0125' then
        return v_out;
    end;
end;
$$;
create temporary table t125_p1 (version text, v jsonb) on commit drop;
insert into t125_p1 select '125', pg_temp.goods125();
-- 109's place_order and 115's decide_order put back, in this transaction only.
\i database/migrations/109_shopper_order_gate.sql
\i database/migrations/115_notifications.sql
insert into t125_p1 select 'before', pg_temp.goods125();
do $$
declare
    a jsonb := (select v from t125_p1 where version = '125');
    b jsonb := (select v from t125_p1 where version = 'before');
begin
    if a is null or jsonb_array_length(a -> 'orders') <> 7 or jsonb_array_length(a -> 'bells') < 12
       or a -> 'refused' ->> 'no note' <> 'Indiquez la date et l''heure souhaitées'
       or a -> 'refused' ->> 'delivered' <> 'Un service se réserve sur rendez-vous : pas de livraison' then
        raise exception 'FAIL: the P1 orders were not all written: %', a;
    end if;
    if a is distinct from b then
        raise exception 'FAIL: an order of goods differs from 109/115: % instead of %', a, b;
    end if;
    if exists (select 1 from jsonb_array_elements(a -> 'orders') o where o ->> 'booked_for' is not null) then
        raise exception 'FAIL: an order of goods, or an older app''s booking, has a slot';
    end if;
    raise notice 'PASS: P1 — three orders of goods (shop and farm: placed, accepted, ready, picked up, refused with a reason) and four slot-less bookings from an older app (a service alone, beside goods, two services, the farm''s visit for three: accepted, done, refused), their lines, their % bells and three refusals, identical to 109''s and 115''s', jsonb_array_length(a -> 'bells');
end $$;
rollback;

\echo ''
\echo '=== test_batch125.sql: every claim holds ==='
