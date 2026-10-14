-- ============================================================
-- 138_help_basic_pro.sql — batch 143: the help, Basic and Pro, as the
-- owner decided it; several requests per business; trainers chosen in the
-- command center.
--
-- The owner, for a shop, a farm and an association alike: Basic gets
-- WhatsApp « Réponse sous 48 h » (with, once a day, an invitation to Pro)
-- and the FAQ; Pro gets WhatsApp « 24/7 » and « Demander un formateur »,
-- a step-by-step request, and sees every request of the business with its
-- status. The app does the screens; this migration does what the server
-- must hold:
--
-- 1. SEVERAL REQUESTS AT ONCE. 133 allowed one active request (open or
--    taken) per business, by a partial unique index and a check in
--    help_request_create. Both go: a business may have several requests
--    open together. help_daily_limit (5 in 24 hours, checked in the same
--    door) is kept and is now the only bound. Nothing else assumed one per
--    business: the ringing, the escalation (help_tick), the inbox, the
--    console, « Aujourd'hui »'s counts and the temporary access all work
--    request by request (an access grant is one per request — two live
--    grants of one trainer to one business read the same, each ends with
--    its own request).
--
-- 2. THE SUBJECTS the request flow offers (the app's chips):
--      every kind  catalogue (Articles / Catalogue), vitrine, ventes
--                  (Caisse / Ventes), factures, livraison, rapports,
--                  equipe (Compte / Équipe), autre;
--      a farm      also bandes (Bandes / Récoltes), stock (Stock de la
--                  ferme);
--      an association also membres, contributions (Cotisations),
--                  evenements (Événements).
--    Three keys are new (catalogue, livraison, evenements); the others are
--    133's, so old requests keep their words. commandes stays valid for
--    the requests made with it.
--
-- 3. « QUAND ? »: now, or a chosen time (preferred_at, in the 14 days to
--    come). A chosen time more than an hour away is routed 30 minutes
--    before it, with 133's own queue (routed_at in the future: nobody is
--    rung, the inbox does not show it, help_tick routes it then), so it is
--    neither rung now nor « late » in the console; the trainer reads the
--    time on the request. Carried in p_context ->> 'preferred_at', so
--    help_request_create keeps 133's signature: an app before 138 calls it
--    unchanged, and no second overload can make a call ambiguous.
--    The photo is 133's photo_document_id (the app's picker and upload).
--
-- 4. help_state() says more, for the new screens: requests (the business's
--    active and resolved requests and its closed ones of the last 30 days,
--    20 at most, active first — every one for the owner or an admin by a
--    real membership, the caller's own for anybody else; « request » too), version 138 (the app's sign that this is
--    installed), can_upgrade (the caller is the business's owner or admin
--    by a real membership — an employee is told to ask the owner), and ref
--    (the business's short reference, below). « request » stays for an app
--    before 143.
--
-- 5. THE REFERENCE. A WhatsApp or an e-mail to Mara names the business and
--    a short, stable reference: the first eight characters of its id, in
--    capitals (a slug can change, the id never does). platform_search (105,
--    the command center's search) now finds a business by the start of its
--    id: typed « 3F2A91C0 » — capitals or not — the business comes first.
--    105's function verbatim (live-checked: no migration since redefined
--    it), and one more clause.
--
-- 6. TRAINERS CHOSEN IN THE COMMAND CENTER. A trainer is 038's
--    profiles.is_trainer (help_trainer_status is only the « en service »
--    switch, defaulting to on). 038's set_trainer_by_phone finds the
--    account by its number; the fiche of « Personnes » has the account
--    itself, so:
--      platform_trainer_state(user)   {is_trainer, phone, on_duty}
--      platform_set_trainer(user, on) sets is_trainer, journaled in
--                                     104's platform_actions (undo-less:
--                                     the switch is its own undo)
--    both SECURITY DEFINER (they read and write another person's profile,
--    which RLS keeps from everybody but its owner), path pinned, closed to
--    anon and PUBLIC, open to authenticated, each refusing anybody but a
--    platform admin inside. Unmarking fires 133's trg_help_trainer_demoted
--    (live grants end) and removes 038's assignments (the observer
--    memberships with is_trainer: no assigned business read in full any
--    more), the businesses lost said in the journal and the answer. The number a trainer is reached on is the
--    profile's own (help_ring_list, 133); the fiche warns when there is
--    none. The console's Formateurs (help_console, 133) lists every
--    is_trainer account, so the ones made here are there.
--
-- SECURITY. Every function here is SECURITY DEFINER as 133's doors are, for
-- 133's reasons (they read rows RLS keeps from the caller — another
-- person's requests for the business's admins, the trainer's first name,
-- the settings, another person's profile), each checking auth.uid() and
-- the caller's place first. None is called by an RLS policy, so the six
-- policy helpers test_least_privilege pins are untouched. No view.
--
-- PER KIND. Shop, farm and association: the same tables and doors; only
-- the subject keys differ (2).
--
-- Re-runnable (the bundle runs twice): drop … if exists, add column if not
-- exists, create or replace, the constraint dropped and added.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The table: several active requests, the new subjects, « quand »
-- ------------------------------------------------------------
drop index if exists help_requests_one_active;
-- What the business's list reads: its requests, newest first, by status.
create index if not exists help_requests_org_status on help_requests (org_id, status, created_at desc);

alter table help_requests add column if not exists preferred_at timestamptz;

alter table help_requests drop constraint if exists help_requests_subject_check;
alter table help_requests add constraint help_requests_subject_check check (subject in (
    'ventes', 'stock', 'factures', 'vitrine', 'commandes', 'equipe', 'autre',
    'bandes', 'contributions', 'rapports', 'membres',
    'catalogue', 'livraison', 'evenements'));

-- The app reads the table through the doors; the column grant (133) lists
-- the readable columns, and preferred_at is one.
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant select (preferred_at) on help_requests to authenticated;
    end if;
end $$;

-- ------------------------------------------------------------
-- 2. Words
-- ------------------------------------------------------------
create or replace function help_subject_label(p_subject text)
returns text
language sql
immutable
set search_path = public
as $$
    select case p_subject
        when 'catalogue'     then 'Articles'
        when 'ventes'        then 'Caisse et ventes'
        when 'stock'         then 'Stock'
        when 'factures'      then 'Factures'
        when 'vitrine'       then 'Vitrine'
        when 'commandes'     then 'Commandes'
        when 'livraison'     then 'Livraison'
        when 'equipe'        then 'Compte et équipe'
        when 'bandes'        then 'Bandes et récoltes'
        when 'contributions' then 'Cotisations'
        when 'rapports'      then 'Rapports'
        when 'membres'       then 'Membres'
        when 'evenements'    then 'Événements'
        else 'Autre'
    end;
$$;

-- The business's short reference (5): the id's first eight characters.
create or replace function org_ref(p_org_id uuid)
returns text
language sql
immutable
set search_path = public
as $$
    select upper(left(p_org_id::text, 8));
$$;

-- ------------------------------------------------------------
-- 3. One request as its business reads it: 133's, and « quand »
-- ------------------------------------------------------------
create or replace function help_request_json(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'id', r.id, 'org_id', r.org_id, 'subject', r.subject, 'message', r.message,
        'photo_document_id', r.photo_document_id,
        'contact', r.contact, 'status', r.status,
        -- The caller asked it (else: one of the business's admins reads it).
        'mine', r.requested_by = auth.uid(),
        'created_at', r.created_at, 'routed_at', r.routed_at,
        'preferred_at', r.preferred_at,
        'queued', r.routed_at > r.created_at + interval '1 second',
        'escalated', r.escalated_at is not null,
        'taken_at', r.taken_at,
        'trainer', case when r.taken_by is not null then jsonb_build_object(
            'first_name', help_first_name(r.taken_by),
            'phone', (select nullif(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), '')
                        from profiles p where p.id = r.taken_by),
            'member', exists (select 1 from memberships m
                               where m.org_id = r.org_id and m.user_id = r.taken_by)) end,
        'visit_answer', r.visit_answer, 'visit_note', r.visit_note,
        'resolved_at', r.resolved_at, 'resolution_note', r.resolution_note,
        'closed_at', r.closed_at, 'rating', r.rating,
        'access', (select jsonb_build_object('granted_at', g.granted_at, 'expires_at', g.expires_at,
                                             'live', g.expires_at > now(),
                                             'opened', g.opened_count)
                     from help_access_grants g
                    where g.request_id = r.id and g.revoked_at is null
                    order by g.granted_at desc limit 1),
        'events', coalesce((select jsonb_agg(jsonb_build_object(
                                'event', e.event, 'at', e.at,
                                'who', case when e.actor_id is not null
                                            then help_first_name(e.actor_id) end)
                                order by e.at, e.id)
                              from help_request_events e where e.request_id = r.id), '[]'::jsonb))
    from help_requests r where r.id = p_id;
$$;

-- ------------------------------------------------------------
-- 4. help_state(): the business's requests, the version, who may buy Pro
-- ------------------------------------------------------------
create or replace function help_state(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_id    uuid;
    v_list  jsonb;
    v_admin boolean;
begin
    if not help_can_ask(p_org_id) then
        return jsonb_build_object('available', false, 'version', 138);
    end if;
    -- Whose requests the caller reads: the owner or an admin by a real
    -- membership, every one of the business's; anybody else, their own
    -- alone (help_is_owner_side's people) — an employee never reads what
    -- the owner asked (« Je soupçonne ma caissière… »).
    v_admin := exists (select 1 from memberships m
                        where m.org_id = p_org_id and m.user_id = auth.uid()
                          and m.role in ('owner', 'super_admin', 'admin'));
    -- 133's « request », for an app before 143: the newest active one,
    -- else the last resolved and not closed.
    select id into v_id from help_requests
     where org_id = p_org_id and status in ('open', 'taken', 'resolved')
       and (v_admin or requested_by = auth.uid())
     order by (status in ('open', 'taken')) desc, created_at desc
     limit 1;
    select coalesce(jsonb_agg(help_request_json(x.id) order by x.ord, x.created_at desc), '[]'::jsonb)
      into v_list
      from (select r.id, r.created_at,
                   case when r.status in ('open', 'taken') then 0
                        when r.status = 'resolved' then 1 else 2 end as ord
              from help_requests r
             where r.org_id = p_org_id
               and (v_admin or r.requested_by = auth.uid())
               and (r.status in ('open', 'taken', 'resolved')
                    or r.closed_at > now() - interval '30 days')
             order by 3, r.created_at desc
             limit 20) x;
    return jsonb_build_object(
        'available', true,
        'version', 138,
        'pro', org_plan(p_org_id) = 'pro',
        -- The owner or an admin by a real membership: they may buy Pro.
        'can_upgrade', v_admin,
        'ref', org_ref(p_org_id),
        'hours', jsonb_build_object(
            'open', help_setting_int('help_hours_open'),
            'close', help_setting_int('help_hours_close'),
            'in_hours', help_in_hours(now()),
            'next_open', help_next_open(now())),
        'request', case when v_id is null then null else help_request_json(v_id) end,
        'requests', v_list,
        'left', greatest(help_setting_int('help_daily_limit') - (
            select count(*) from help_requests
             where org_id = p_org_id and created_at > now() - interval '24 hours'), 0));
end;
$$;

-- ------------------------------------------------------------
-- 5. « Envoyer la demande »: several at once, the new subjects, « quand »
-- ------------------------------------------------------------
-- 133's signature, kept (3): the chosen time rides in p_context.
create or replace function help_request_create(
    p_org_id   uuid,
    p_subject  text,
    p_message  text default null,
    p_contact  text default 'whatsapp',
    p_phone    text default null,
    p_photo    uuid default null,
    p_context  jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_me       uuid := auth.uid();
    v_phone    text;
    v_message  text;
    v_routed   timestamptz;
    v_esc      timestamptz;
    v_id       uuid;
    v_assigned boolean;
    v_context  jsonb;
    v_when     timestamptz;
begin
    if v_me is null then
        raise exception 'Connectez-vous pour demander de l''aide.';
    end if;
    if not help_can_ask(p_org_id) then
        raise exception 'Seule l''équipe de l''entreprise peut demander de l''aide ici.';
    end if;
    if org_plan(p_org_id) <> 'pro' then
        raise exception 'L''aide d''un formateur vient avec Mara Pro.';
    end if;
    if p_subject is null or p_subject not in ('ventes', 'stock', 'factures', 'vitrine', 'commandes',
            'equipe', 'autre', 'bandes', 'contributions', 'rapports', 'membres',
            'catalogue', 'livraison', 'evenements') then
        raise exception 'Choisissez de quoi il s''agit.';
    end if;
    if p_contact is null or p_contact not in ('call', 'whatsapp', 'visit') then
        raise exception 'Choisissez comment être aidé : appel, WhatsApp ou visite.';
    end if;
    v_message := nullif(btrim(regexp_replace(coalesce(p_message, ''), '[[:cntrl:]]', ' ', 'g')), '');
    if char_length(v_message) > 500 then
        raise exception 'Un message de 500 caractères au plus, s''il vous plaît.';
    end if;
    v_phone := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');
    if v_phone is null then
        select nullif(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g'), '')
          into v_phone from profiles where id = v_me;
    end if;
    if v_phone is null or v_phone !~ '^[0-9]{8,15}$' then
        raise exception 'Un numéro où vous joindre, avec l''indicatif (par exemple 22670000000).';
    end if;
    if p_photo is not null and not exists (
            select 1 from documents d where d.id = p_photo and d.org_id = p_org_id) then
        raise exception 'Cette photo n''est pas de cette entreprise.';
    end if;
    -- « Quand ? » — now (nothing), or a time in the next 14 days.
    if nullif(btrim(coalesce(p_context ->> 'preferred_at', '')), '') is not null then
        begin
            v_when := (p_context ->> 'preferred_at')::timestamptz;
        exception when others then
            raise exception 'Choisissez un jour et une heure, s''il vous plaît.';
        end;
        if v_when < now() - interval '5 minutes' or v_when > now() + interval '14 days' then
            raise exception 'Choisissez un moment dans les 14 jours qui viennent.';
        end if;
    end if;
    -- 133's « one active request » is gone (1); the day's limit holds.
    -- 133's unique index also serialised two sends at once; without it,
    -- two at the same instant would both count 4 and both pass. One
    -- business's sends wait for each other here (until the transaction
    -- ends), so the count is always the committed one.
    perform pg_advisory_xact_lock(hashtextextended('help_request_create:' || p_org_id::text, 0));
    if (select count(*) from help_requests
         where org_id = p_org_id and created_at > now() - interval '24 hours')
       >= help_setting_int('help_daily_limit') then
        raise exception 'Les demandes d''aide de ces 24 heures sont toutes faites. Réessayez demain, ou écrivez à Mara.';
    end if;

    v_context := jsonb_strip_nulls(jsonb_build_object(
        'screen',   notify_plain(p_context ->> 'screen', 60),
        'version',  notify_plain(p_context ->> 'version', 40, true),
        'platform', notify_plain(p_context ->> 'platform', 20)));

    -- A chosen time more than an hour away: routed 30 minutes before it,
    -- through 133's queue (3); else at the next opening, as in 133.
    if v_when is not null and v_when > now() + interval '1 hour' then
        v_routed := help_next_open(v_when - interval '30 minutes');
    else
        v_routed := help_next_open(now());
    end if;
    select exists (
        select 1 from memberships m join profiles p on p.id = m.user_id
         where m.org_id = p_org_id and m.is_trainer and p.is_trainer
           and coalesce((select s.on_duty from help_trainer_status s where s.user_id = p.id), true))
      into v_assigned;
    -- No assigned trainer on duty: everyone, at once.
    v_esc := case when v_assigned
                  then help_add_open(v_routed, help_setting_int('help_escalate_minutes'))
                  else v_routed end;

    insert into help_requests (org_id, requested_by, subject, message, photo_document_id,
                               contact, contact_phone, context, routed_at, escalate_at,
                               preferred_at)
    values (p_org_id, v_me, p_subject, v_message, p_photo, p_contact, v_phone,
            v_context, v_routed, v_esc, v_when)
    returning id into v_id;
    perform help_log(v_id, 'created', null);
    if v_routed > now() then
        perform help_log(v_id, 'queued', null);
    else
        -- In the hours: the assigned now, everyone at once without them.
        perform help_ring(v_id, false);
        update help_requests set routed_rung_at = now() where id = v_id;
        if not v_assigned then
            update help_requests set escalated_at = now() where id = v_id;
            perform help_ring(v_id, true);
            insert into help_request_events (request_id, event) values (v_id, 'escalated');
        end if;
    end if;
    return help_request_json(v_id);
end;
$$;

-- ------------------------------------------------------------
-- 6. The trainer reads « quand » too: 133's row, and preferred_at
-- ------------------------------------------------------------
create or replace function help_inbox_row(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'id', r.id, 'org_id', r.org_id, 'org', o.name, 'profile', o.profile, 'city', o.city,
        'subject', r.subject, 'message', r.message, 'contact', r.contact,
        'has_photo', r.photo_document_id is not null,
        'context', r.context, 'status', r.status,
        'created_at', r.created_at, 'routed_at', r.routed_at,
        'preferred_at', r.preferred_at,
        'escalated', r.escalated_at is not null,
        'mine', r.taken_by = auth.uid(),
        'taken_by', case when r.taken_by is not null then help_first_name(r.taken_by) end,
        'assigned', exists (select 1 from memberships m
                             where m.user_id = auth.uid() and m.org_id = r.org_id and m.is_trainer),
        'member', exists (select 1 from memberships m
                           where m.user_id = auth.uid() and m.org_id = r.org_id),
        'requester', help_first_name(r.requested_by),
        'phone', case when r.taken_by = auth.uid()
                        or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
                      then r.contact_phone end,
        'visit_answer', r.visit_answer, 'visit_note', r.visit_note,
        'resolved_at', r.resolved_at, 'resolution_note', r.resolution_note,
        'closed_at', r.closed_at, 'rating', r.rating,
        'access', (select jsonb_build_object('granted_at', g.granted_at, 'expires_at', g.expires_at,
                                             'live', g.expires_at > now())
                     from help_access_grants g
                    where g.request_id = r.id and g.trainer_id = auth.uid()
                      and g.revoked_at is null and g.expires_at > now()
                    order by g.granted_at desc limit 1))
    from help_requests r join orgs o on o.id = r.org_id
    where r.id = p_id;
$$;

-- ------------------------------------------------------------
-- 7. The command center's search finds the reference (5)
-- ------------------------------------------------------------
-- 105 verbatim, and « o.id::text like v_ref » for the businesses.
create or replace function platform_search(p_q text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_q      text := btrim(coalesce(p_q, ''));
    v_lit    text;
    v_like   text;
    v_start  text;
    v_number text;
    v_digits text;
    v_ref    text;
    v_orgs   jsonb;
    v_people jsonb;
    v_orders jsonb;
begin
    perform platform_only();
    if length(v_q) < 2 then
        return jsonb_build_object('businesses', '[]'::jsonb, 'people', '[]'::jsonb,
                                  'orders', '[]'::jsonb);
    end if;
    -- What was typed, literally: a « % » or a « _ » is a character here —
    -- in every like below (\ is like's own escape).
    v_lit   := replace(replace(replace(left(v_q, 100), '\', '\\'), '%', '\%'), '_', '\_');
    v_like  := '%' || v_lit || '%';
    v_start := v_lit || '%';
    -- An order is found by the start of its number only when what was
    -- typed can be one (hex digits and dashes, 4 at least): no other words
    -- scan every order's number.
    if v_q ~ '^[0-9A-Fa-f-]{4,36}$' then
        v_number := lower(v_q) || '%';
    end if;
    -- 138: a business by its reference, the start of its id (« Réf. »
    -- in a WhatsApp or an e-mail to Mara), 6 hex characters at least.
    if v_q ~ '^[0-9A-Fa-f]{6,8}$' or v_q ~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{0,28}$' then
        v_ref := lower(v_q) || '%';
    end if;
    -- A phone is typed with spaces and without the country, kept with both.
    v_digits := regexp_replace(v_q, '\D', '', 'g');
    if length(v_digits) < 4 then v_digits := null; end if;

    select jsonb_agg(r) into v_orgs from (
        select jsonb_build_object(
                   'id', o.id, 'name', o.name, 'slug', o.slug, 'profile', o.profile,
                   'phone', o.phone, 'archived', o.archived_at is not null,
                   'owner', p.full_name, 'owner_phone', p.phone) as r
          from orgs o
          left join lateral (select m.user_id from memberships m
                              where m.org_id = o.id and m.role = 'owner'
                              order by m.created_at limit 1) w on true
          left join profiles p on p.id = w.user_id
         where o.name ilike v_like or o.slug ilike v_like
            or p.full_name ilike v_like
            or (v_ref is not null and o.id::text like v_ref)
            or (v_digits is not null
                and (regexp_replace(coalesce(o.phone, ''), '\D', '', 'g') like '%' || v_digits || '%'
                  or regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') like '%' || v_digits || '%'))
         order by (v_ref is not null and o.id::text like v_ref) desc,
                  (o.name ilike v_start) desc, o.archived_at is not null, lower(o.name)
         limit 8) x;

    select jsonb_agg(r) into v_people from (
        select jsonb_build_object(
                   'id', p.id, 'name', p.full_name, 'phone', p.phone, 'email', u.email::text,
                   'platform', p.is_platform_admin,
                   'businesses', (select count(distinct m.org_id) from memberships m
                                   where m.user_id = p.id)) as r
          from profiles p
          join auth.users u on u.id = p.id
         where p.full_name ilike v_like or u.email ilike v_like
            or (v_digits is not null
                and regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') like '%' || v_digits || '%')
         order by (p.full_name ilike v_start) desc, lower(coalesce(p.full_name, u.email, p.phone))
         limit 8) x;

    select jsonb_agg(r) into v_orders from (
        select jsonb_build_object(
                   'id', d.id, 'org_id', d.org_id, 'org_name', o.name, 'profile', o.profile,
                   'customer', d.customer_name, 'phone', d.phone, 'status', d.status,
                   'fulfilment', d.fulfilment, 'total', d.total, 'currency', d.currency,
                   'at', d.created_at) as r
          from orders d
          join orgs o on o.id = d.org_id
         where (v_number is not null and d.id::text like v_number)
            or d.customer_name ilike v_like
            or (v_digits is not null
                and regexp_replace(coalesce(d.phone, ''), '\D', '', 'g') like '%' || v_digits || '%')
         order by d.created_at desc
         limit 8) x;

    return jsonb_build_object('businesses', coalesce(v_orgs, '[]'::jsonb),
                              'people', coalesce(v_people, '[]'::jsonb),
                              'orders', coalesce(v_orders, '[]'::jsonb));
end;
$$;

-- ------------------------------------------------------------
-- 8. Trainers chosen in the command center (6)
-- ------------------------------------------------------------
-- One account as the fiche's switch needs it. Null for anybody but a
-- platform admin (as 105's readers answer), and for an unknown account.
create or replace function platform_trainer_state(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return null;
    end if;
    return (select jsonb_build_object(
                'user_id', p.id,
                'is_trainer', coalesce(p.is_trainer, false),
                -- The number the trainer is reached on: the profile's own,
                -- as help_ring_list (133) reads it — digits, or nothing.
                'phone', nullif(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), ''),
                'on_duty', coalesce((select s.on_duty from help_trainer_status s where s.user_id = p.id), true),
                'assigned', (select count(*) from memberships m where m.user_id = p.id and m.is_trainer))
              from profiles p where p.id = p_user_id);
end;
$$;

-- « Formateur Mara » on or off. A platform admin only; journaled.
create or replace function platform_set_trainer(p_user_id uuid, p_on boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_was  boolean;
    v_name text;
    v_orgs jsonb := '[]'::jsonb;
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Seule l''équipe Mara choisit les formateurs.';
    end if;
    if p_on is null then
        raise exception 'Formateur : oui ou non.';
    end if;
    select coalesce(is_trainer, false), coalesce(nullif(btrim(full_name), ''), phone, 'Sans nom')
      into v_was, v_name
      from profiles where id = p_user_id for update;
    if not found then
        raise exception 'Ce compte n''existe pas.';
    end if;
    if v_was is distinct from p_on or (not p_on and exists (
            select 1 from memberships where user_id = p_user_id
               and role = 'observer' and is_trainer)) then
        -- Off fires 133's trg_help_trainer_demoted: their live grants end.
        update profiles set is_trainer = p_on where id = p_user_id;
        -- Off also ends 038's assignments: the observer memberships that
        -- let a trainer read an assigned business in full (unassign_trainer's
        -- rows; any other role the person holds there is untouched).
        if not p_on then
            with gone as (
                delete from memberships
                 where user_id = p_user_id and role = 'observer' and is_trainer
                returning org_id)
            select coalesce(jsonb_agg(distinct org_id), '[]'::jsonb) into v_orgs from gone;
        end if;
        perform platform_log_action(
            null, 'trainer',
            case when p_on then format('%s devient formateur Mara', notify_plain(v_name, 60))
                 when jsonb_array_length(v_orgs) > 0
                 then format('%s n''est plus formateur Mara (%s entreprise(s) retirée(s))',
                             notify_plain(v_name, 60), jsonb_array_length(v_orgs))
                 else format('%s n''est plus formateur Mara', notify_plain(v_name, 60)) end,
            jsonb_build_object('user_id', p_user_id, 'is_trainer', v_was, 'assigned_orgs', v_orgs),
            jsonb_build_object('user_id', p_user_id, 'is_trainer', p_on, 'assigned_orgs', '[]'::jsonb),
            null, null);
    end if;
    return platform_trainer_state(p_user_id)
        || jsonb_build_object('unassigned', jsonb_array_length(v_orgs));
end;
$$;

-- ------------------------------------------------------------
-- 9. Who may call what (063: born closed to PUBLIC and anon)
-- ------------------------------------------------------------
do $$
declare
    -- The app's doors: authenticated (help_state, help_request_create,
    -- platform_search keep 133's and 105's grants: create or replace keeps
    -- a function's privileges; said again here all the same).
    v_app text[] := array[
        'help_state(uuid)',
        'help_request_create(uuid, text, text, text, text, uuid, jsonb)',
        'platform_search(text)',
        'platform_trainer_state(uuid)',
        'platform_set_trainer(uuid, boolean)'];
    -- Internal: the definer doors call them.
    v_internal text[] := array[
        'help_subject_label(text)',
        'org_ref(uuid)',
        'help_request_json(uuid)',
        'help_inbox_row(uuid)'];
    v_has_anon boolean := exists (select 1 from pg_roles where rolname = 'anon');
    v_has_auth boolean := exists (select 1 from pg_roles where rolname = 'authenticated');
    f text;
begin
    foreach f in array v_app || v_internal loop
        execute format('revoke execute on function %s from public', f);
        if v_has_anon then execute format('revoke execute on function %s from anon', f); end if;
    end loop;
    foreach f in array v_app loop
        if v_has_auth then execute format('grant execute on function %s to authenticated', f); end if;
    end loop;
    foreach f in array v_internal loop
        if v_has_auth then execute format('revoke execute on function %s from authenticated', f); end if;
    end loop;
end $$;

notify pgrst, 'reload schema';
