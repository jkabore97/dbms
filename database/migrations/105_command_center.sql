-- ============================================================
-- 105_command_center.sql — Mara's command center: what waits, one search,
-- several businesses at once, the settings, all written in the journal.
--
-- The owner's words: « when signed in with my admin profile, I want an
-- admin button displayed where I can click and access the admin panel »,
-- and « everything will be properly wired to the admin command center ».
-- The app's side is the center itself (the « Admin » pill on every top
-- bar, the side rail on a computer, the bottom bar on a phone). This is
-- the server's side, standing on 104's journal (platform_actions,
-- platform_log_action, platform_undo and its whitelist platform_undo_fns):
--
--   1. platform_todo(): the counts « À faire » opens on — requests
--      waiting, « J'ai payé » to confirm (Mara Pro and the spots), couriers
--      to check, orders stuck, businesses silent 30 days, and what ends in
--      the next 7 days (a Pro plan, a tool opened, promotional cauris, a
--      spot, a rule of the switchboard), and Wave payouts that failed.
--      platform_todo_list(key) gives the rows behind the counts that have
--      no screen of their own, so every count opens something to act on.
--      (Refused offline sales are not counted: the server never sees
--      them — a refused sale stays on the phone that made it.)
--   2. platform_search(q): one bar for the whole platform — businesses by
--      name, address (slug), phone or owner; people by name, phone or
--      e-mail; orders by their number or the customer's name or phone.
--   3. platform_bulk(action, orgs, args): several businesses ticked at
--      once — give cauris (or promotional cauris before a date), open a
--      tool until a date, send a message, archive, restore. It loops the
--      single doors that already exist (100's platform_give_cauris and
--      platform_give_unlock, 072's send_platform_message, 014's archive_org
--      and restore_org) — so every rule of theirs still holds — and writes
--      one platform_action per business, with its undo where the act can
--      be taken back. One business refused (a vitrine d'exemple gets no
--      cauris) never stops the others: each is said with its reason. The
--      app sends its single gifts and its single archive through here too,
--      so they are in the journal as well.
--   4. The undos, whitelisted in platform_undo_fns: a gift of cauris takes
--      back what is still in the wallet (never more; refused when it has
--      all been spent); a tool opened goes back to how it was, unless it
--      changed since; an archive is restored, a restore archived again; a
--      setting goes back to its value, unless it changed since. A message
--      cannot be unsent: it has no undo. The business is told on its bell
--      when a gift is taken back.
--   5. platform_settings_board() and platform_set_setting(key, value): the
--      settings that already exist, read and changed from Réglages. Only a
--      key already there (never an internal marker), only a value of its
--      own type (a number for a number, oui/non for oui/non, a text, a list
--      of words), a number never below zero, a percentage never above 100;
--      logged with its before and after, undoable. The app's other places
--      that change a setting (the Pro console, the Wave console, the
--      couriers' share, the two-step switch) go through it as well.
--
-- Nothing here changes what any shop, farm or association, or any vitrine,
-- shows: no setting's value is touched, no table a business reads is
-- written; the functions only answer the platform. Every one checks
-- caller_is_platform_admin() on the server and refuses anyone else in
-- French; every one is born closed (063) and granted by name below.
-- Re-runnable: functions replaced with their own signatures, the
-- whitelist inserted with « on conflict do nothing ».
-- ============================================================

do $$
begin
    if to_regclass('public.platform_actions') is null
       or to_regclass('public.platform_undo_fns') is null
       or to_regprocedure('public.platform_log_action(uuid, text, text, jsonb, jsonb, text, jsonb)') is null then
        raise exception '105 needs 104 (platform_actions, platform_log_action, platform_undo_fns) applied first';
    end if;
end $$;

-- ------------------------------------------------------------
-- 0. One refusal, said once
-- ------------------------------------------------------------
create or replace function platform_only()
returns void
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
end;
$$;

-- ------------------------------------------------------------
-- 1. À faire
-- ------------------------------------------------------------
create or replace function platform_todo()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_week timestamptz := now() + interval '7 days';
    v_today date := cauris_today();
begin
    perform platform_only();
    return jsonb_build_object(
        'applications',   (select count(*) from org_applications where status = 'pending'),
        'pro_paid',       (select count(*) from plan_requests where handled_at is null),
        'spots_paid',     (select count(*) from promotions where status = 'paid_claimed'),
        'spots_asked',    (select count(*) from promotions where status = 'requested'),
        'couriers',       (select count(*) from couriers where status = 'pending'),
        'orders_stuck',   (select count(*) from orders
                            where (status = 'pending' and created_at < now() - interval '2 hours')
                               or (status = 'picked_up' and updated_at < now() - interval '3 hours')),
        -- The same businesses the list's « Silencieuses (30 j) » filter shows.
        'silent_30',      (select count(*) from orgs
                            where archived_at is null and last_activity_at is not null
                              and last_activity_at < now() - interval '30 days'),
        'plans_ending',   (select count(*) from orgs
                            where archived_at is null and plan = 'pro' and plan_until is not null
                              and plan_until between v_today and v_today + 7),
        'unlocks_ending', (select count(*) from cauris_unlocks u join orgs o on o.id = u.org_id
                            where o.archived_at is null and u.until > now() and u.until <= v_week),
        'promos_ending',  (select count(*) from cauris_promos c join orgs o on o.id = c.org_id
                            where o.archived_at is null and c.left_points > 0
                              and c.expires_on > v_today and c.expires_on <= v_today + 7),
        'spots_ending',   (select count(*) from promotions
                            where status = 'approved' and ends_at > now() and ends_at <= v_week),
        'rules_ending',   (select count(*) from feature_rules
                            where until is not null and until > now() and until <= v_week),
        'payouts_failed', (select count(*) from wave_payments where payout_status = 'failed')
    );
end;
$$;

-- The rows behind a count that has no screen of its own.
create or replace function platform_todo_list(p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_week timestamptz := now() + interval '7 days';
    v_today date := cauris_today();
    v_rows jsonb;
begin
    perform platform_only();
    case p_key
    when 'silent_30' then
        select jsonb_agg(r order by r->>'at') into v_rows from (
            select jsonb_build_object('org_id', o.id, 'org_name', o.name, 'profile', o.profile,
                                      'at', o.last_activity_at) as r
              from orgs o
             where o.archived_at is null and o.last_activity_at is not null
               and o.last_activity_at < now() - interval '30 days'
             order by o.last_activity_at limit 200) x;
    when 'plans_ending' then
        select jsonb_agg(r order by r->>'at') into v_rows from (
            select jsonb_build_object('org_id', o.id, 'org_name', o.name, 'profile', o.profile,
                                      'at', o.plan_until) as r
              from orgs o
             where o.archived_at is null and o.plan = 'pro' and o.plan_until is not null
               and o.plan_until between v_today and v_today + 7
             order by o.plan_until limit 200) x;
    when 'unlocks_ending' then
        select jsonb_agg(r order by r->>'at') into v_rows from (
            select jsonb_build_object('org_id', o.id, 'org_name', o.name, 'profile', o.profile,
                                      'feature', u.feature, 'gift', u.gifted_by is not null,
                                      'at', u.until) as r
              from cauris_unlocks u join orgs o on o.id = u.org_id
             where o.archived_at is null and u.until > now() and u.until <= v_week
             order by u.until limit 200) x;
    when 'promos_ending' then
        select jsonb_agg(r order by r->>'at') into v_rows from (
            select jsonb_build_object('org_id', o.id, 'org_name', o.name, 'profile', o.profile,
                                      'points', c.left_points, 'at', c.expires_on) as r
              from cauris_promos c join orgs o on o.id = c.org_id
             where o.archived_at is null and c.left_points > 0
               and c.expires_on > v_today and c.expires_on <= v_today + 7
             order by c.expires_on limit 200) x;
    when 'spots_ending' then
        select jsonb_agg(r order by r->>'at') into v_rows from (
            select jsonb_build_object('org_id', o.id, 'org_name', o.name, 'profile', o.profile,
                                      'spot', p.kind, 'at', p.ends_at) as r
              from promotions p join orgs o on o.id = p.org_id
             where p.status = 'approved' and p.ends_at > now() and p.ends_at <= v_week
             order by p.ends_at limit 200) x;
    when 'rules_ending' then
        select jsonb_agg(r order by r->>'at') into v_rows from (
            select jsonb_build_object('org_id', f.org_id, 'org_name', o.name, 'profile', o.profile,
                                      'kind', f.kind, 'feature', f.feature, 'state', f.state,
                                      'at', f.until) as r
              from feature_rules f left join orgs o on o.id = f.org_id
             where f.until is not null and f.until > now() and f.until <= v_week
             order by f.until limit 200) x;
    when 'orders_stuck' then
        select jsonb_agg(r order by r->>'at') into v_rows from (
            select jsonb_build_object('org_id', o.id, 'org_name', o.name, 'profile', o.profile,
                                      'order_id', d.id, 'customer', d.customer_name,
                                      'status', d.status, 'amount', d.total,
                                      'currency', d.currency,
                                      'at', case when d.status = 'pending' then d.created_at
                                                 else d.updated_at end) as r
              from orders d join orgs o on o.id = d.org_id
             where (d.status = 'pending' and d.created_at < now() - interval '2 hours')
                or (d.status = 'picked_up' and d.updated_at < now() - interval '3 hours')
             order by d.created_at limit 200) x;
    when 'payouts_failed' then
        select jsonb_agg(r order by r->>'at' desc) into v_rows from (
            select jsonb_build_object('org_id', o.id, 'org_name', o.name, 'profile', o.profile,
                                      'payment_id', w.id, 'amount', w.payout_amount,
                                      'currency', w.currency, 'error', w.payout_error,
                                      'at', w.paid_at) as r
              from wave_payments w join orgs o on o.id = w.org_id
             where w.payout_status = 'failed'
             order by w.paid_at desc nulls last limit 200) x;
    else
        raise exception 'Liste inconnue : %', coalesce(p_key, '');
    end case;
    return coalesce(v_rows, '[]'::jsonb);
end;
$$;

-- ------------------------------------------------------------
-- 2. One search for the platform
-- ------------------------------------------------------------
create or replace function platform_search(p_q text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_q      text := btrim(coalesce(p_q, ''));
    v_like   text;
    v_digits text;
    v_orgs   jsonb;
    v_people jsonb;
    v_orders jsonb;
begin
    perform platform_only();
    if length(v_q) < 2 then
        return jsonb_build_object('businesses', '[]'::jsonb, 'people', '[]'::jsonb,
                                  'orders', '[]'::jsonb);
    end if;
    -- What was typed, literally: a « % » or a « _ » is a character here.
    v_like := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
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
            or (v_digits is not null
                and (regexp_replace(coalesce(o.phone, ''), '\D', '', 'g') like '%' || v_digits || '%'
                  or regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') like '%' || v_digits || '%'))
         order by (o.name ilike v_q || '%') desc, o.archived_at is not null, lower(o.name)
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
         order by (p.full_name ilike v_q || '%') desc, lower(coalesce(p.full_name, u.email, p.phone))
         limit 8) x;

    select jsonb_agg(r) into v_orders from (
        select jsonb_build_object(
                   'id', d.id, 'org_id', d.org_id, 'org_name', o.name, 'profile', o.profile,
                   'customer', d.customer_name, 'phone', d.phone, 'status', d.status,
                   'fulfilment', d.fulfilment, 'total', d.total, 'currency', d.currency,
                   'at', d.created_at) as r
          from orders d
          join orgs o on o.id = d.org_id
         where d.id::text like lower(v_q) || '%'
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
-- 3. Several businesses at once
-- ------------------------------------------------------------
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
    v_org     uuid;
    v_name    text;
    v_archived timestamptz;
    v_by      uuid;
    v_kind    text;
    v_ref     uuid;
    v_promo   uuid;
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
                v_before := jsonb_build_object('balance', cauris_balance(v_org));
                v_res := platform_give_cauris(v_org, v_points, v_note, v_expires);
                v_promo := null;
                if v_expires is not null then
                    select id into v_promo from cauris_promos
                     where org_id = v_org and given_by = auth.uid()
                     order by created_at desc limit 1;
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
                                       'promo_id', v_promo, 'ref', v_ref));
            elsif p_action = 'unlock' then
                -- A tool the kind does not have is not opened (099: an
                -- association has no analyses and no delivery).
                if (v_feature = 'analytics' and v_kind not in ('retail', 'farm'))
                   or (v_feature = 'delivery' and v_kind in ('association', 'church')) then
                    raise exception 'Cet outil n''existe pas pour ce genre d''activité';
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
                v_sent := send_platform_message(v_org, v_message);
                v_res := jsonb_build_object('sent', v_sent);
                v_action := platform_log_action(
                    v_org, 'message',
                    'Message à ' || v_name || ' : « ' || left(v_message, 120) || ' »',
                    null, jsonb_build_object('message', v_message, 'sent', v_sent),
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
                    jsonb_build_object('org_id', v_org));
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
-- 4. The undos (called by 104's platform_undo, by name, from its list)
-- ------------------------------------------------------------
create or replace function platform_undo_cauris(p_args jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org     uuid := (p_args->>'org_id')::uuid;
    v_points  int  := (p_args->>'points')::int;
    v_promo   uuid := nullif(p_args->>'promo_id', '')::uuid;
    v_ref     text := coalesce(p_args->>'ref', gen_random_uuid()::text);
    v_balance int;
    v_left    int;
    v_take    int;
begin
    perform platform_only();
    perform pg_advisory_xact_lock(hashtext('cauris:' || v_org::text));
    perform cauris_expire(v_org);
    v_balance := greatest(cauris_balance(v_org), 0);
    if v_promo is not null then
        select left_points into v_left from cauris_promos where id = v_promo for update;
        v_take := least(coalesce(v_left, 0), v_balance);
    else
        v_take := least(coalesce(v_points, 0), v_balance);
    end if;
    if v_take <= 0 then
        raise exception 'Ces cauris ont déjà été dépensés : il n''y a rien à reprendre.';
    end if;
    if v_promo is not null then
        update cauris_promos set left_points = 0, closed_at = coalesce(closed_at, now())
         where id = v_promo;
    end if;
    -- A gift line of its own, negative: the wallet's history says « Cadeau
    -- de Mara » with the word below, and the league never counts it.
    insert into cauris_ledger (org_id, delta, reason, ref, note)
    values (v_org, -v_take, case when v_promo is null then 'gift' else 'promo' end,
            'undo:' || v_ref, 'Cadeau annulé par Mara');
    begin
        perform notify_org_admins(v_org, 'gift_undone',
            'Mara a repris ' || v_take || ' cauris offerts.',
            jsonb_build_object('to', 'shop', 'points', v_take));
    exception when others then
        null;  -- a bell never blocks the undo
    end;
end;
$$;

create or replace function platform_undo_unlock(p_args jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org     uuid := (p_args->>'org_id')::uuid;
    v_feature text := p_args->>'feature';
    v_before  jsonb := p_args->'before';
    v_until   timestamptz := (p_args->>'until')::timestamptz;
    r         cauris_unlocks%rowtype;
begin
    perform platform_only();
    select * into r from cauris_unlocks where org_id = v_org and feature = v_feature for update;
    if not found then
        raise exception 'Cet outil n''est plus ouvert : il n''y a rien à annuler.';
    end if;
    if r.until is distinct from v_until then
        raise exception 'Cet outil a changé depuis (acheté ou prolongé) : il n''est pas annulé.';
    end if;
    if v_before is null or jsonb_typeof(v_before) = 'null' then
        delete from cauris_unlocks where org_id = v_org and feature = v_feature;
    else
        update cauris_unlocks
           set until = (v_before->>'until')::timestamptz,
               note = v_before->>'note',
               gifted_by = nullif(v_before->>'gifted_by', '')::uuid,
               updated_at = now()
         where org_id = v_org and feature = v_feature;
    end if;
    begin
        perform notify_org_admins(v_org, 'gift_undone',
            'Mara a annulé l''ouverture de ' || cauris_feature_label(v_feature) || '.',
            jsonb_build_object('to', 'shop', 'feature', v_feature));
    exception when others then
        null;
    end;
end;
$$;

create or replace function platform_undo_archive(p_args jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org uuid := (p_args->>'org_id')::uuid;
begin
    perform platform_only();
    if not exists (select 1 from orgs where id = v_org and archived_at is not null) then
        raise exception 'Cette entreprise n''est plus archivée.';
    end if;
    perform restore_org(v_org);
end;
$$;

create or replace function platform_undo_restore(p_args jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org uuid := (p_args->>'org_id')::uuid;
begin
    perform platform_only();
    if not exists (select 1 from orgs where id = v_org and archived_at is null) then
        raise exception 'Cette entreprise est déjà archivée.';
    end if;
    perform archive_org(v_org);
end;
$$;

create or replace function platform_undo_setting(p_args jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_key  text := p_args->>'key';
    v_now  jsonb;
begin
    perform platform_only();
    select value into v_now from platform_settings where key = v_key for update;
    if not found then
        raise exception 'Réglage inconnu : %', coalesce(v_key, '');
    end if;
    if v_now is distinct from p_args->'after' then
        raise exception 'Ce réglage a changé depuis : annulez d''abord le dernier changement.';
    end if;
    update platform_settings set value = p_args->'before', updated_at = now()
     where key = v_key;
end;
$$;

insert into platform_undo_fns (fn) values
    ('platform_undo_cauris'),
    ('platform_undo_unlock'),
    ('platform_undo_archive'),
    ('platform_undo_restore'),
    ('platform_undo_setting')
on conflict do nothing;

-- ------------------------------------------------------------
-- 5. Réglages
-- ------------------------------------------------------------
-- Not a Réglages setting: the markers a migration leaves to remember it
-- ran once, and a key with a page and a checked setter of its own — the
-- request page (107's application_form, platform_set_application_form),
-- which only its own setter may write, with its own undo.
create or replace function platform_setting_internal(p_key text)
returns boolean
language sql
immutable
set search_path = public
as $$
    select p_key like '%\_seeded' or p_key like '%\_marked'
        or p_key in ('application_form');
$$;

create or replace function platform_settings_board()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    perform platform_only();
    return coalesce((
        select jsonb_object_agg(s.key, jsonb_build_object(
                   'value', s.value,
                   'updated_at', s.updated_at,
                   'changed_by', (select person_name(a.actor) from platform_actions a
                                   where a.kind = 'setting' and a.after->>'key' = s.key
                                   order by a.at desc limit 1)))
          from platform_settings s
         where not platform_setting_internal(s.key)
           and jsonb_typeof(s.value) <> 'object'), '{}'::jsonb);
end;
$$;

create or replace function platform_set_setting(p_key text, p_value jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_before jsonb;
    v_type   text;
begin
    perform platform_only();
    select value into v_before from platform_settings where key = p_key for update;
    if not found or platform_setting_internal(p_key) then
        raise exception 'Réglage inconnu : %', coalesce(p_key, '');
    end if;
    v_type := jsonb_typeof(v_before);
    -- A whole object is a page's, never a single setting.
    if v_type = 'object' then
        raise exception 'Réglage inconnu : %', p_key;
    end if;
    if p_value is null or jsonb_typeof(p_value) <> v_type then
        raise exception '%', case v_type
            when 'number'  then 'Ce réglage attend un nombre.'
            when 'boolean' then 'Ce réglage attend oui ou non.'
            when 'string'  then 'Ce réglage attend un texte.'
            when 'array'   then 'Ce réglage attend une liste.'
            else 'Ce réglage n''accepte pas cette valeur.' end;
    end if;
    if v_type = 'number' then
        if (p_value #>> '{}')::numeric < 0 then
            raise exception 'Un nombre positif, s''il vous plaît.';
        end if;
        if p_key like '%\_pct' and (p_value #>> '{}')::numeric > 100 then
            raise exception 'Un pourcentage ne dépasse pas 100.';
        end if;
    elsif v_type = 'string' then
        if length(p_value #>> '{}') > 200 then
            raise exception 'Un texte de 200 caractères au plus.';
        end if;
    elsif v_type = 'array' then
        if exists (select 1 from jsonb_array_elements(p_value) e
                    where jsonb_typeof(e) <> 'string') then
            raise exception 'Ce réglage attend une liste de mots.';
        end if;
    end if;
    if p_value = v_before then
        return null;  -- nothing changed, nothing to write in the journal
    end if;

    update platform_settings set value = p_value, updated_at = now() where key = p_key;
    return platform_log_action(
        null, 'setting',
        'Réglage ' || p_key || ' : ' || v_before::text || ' → ' || p_value::text,
        jsonb_build_object('key', p_key, 'value', v_before),
        jsonb_build_object('key', p_key, 'value', p_value),
        'platform_undo_setting',
        jsonb_build_object('key', p_key, 'before', v_before, 'after', p_value));
end;
$$;

-- ------------------------------------------------------------
-- 6. Doors
-- ------------------------------------------------------------
revoke execute on function platform_only()                         from public;
revoke execute on function platform_todo()                         from public;
revoke execute on function platform_todo_list(text)                from public;
revoke execute on function platform_search(text)                   from public;
revoke execute on function platform_bulk(text, uuid[], jsonb)      from public;
revoke execute on function platform_undo_cauris(jsonb)             from public;
revoke execute on function platform_undo_unlock(jsonb)             from public;
revoke execute on function platform_undo_archive(jsonb)            from public;
revoke execute on function platform_undo_restore(jsonb)            from public;
revoke execute on function platform_undo_setting(jsonb)            from public;
revoke execute on function platform_setting_internal(text)         from public;
revoke execute on function platform_settings_board()               from public;
revoke execute on function platform_set_setting(text, jsonb)       from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function platform_only()                     from anon;
        revoke execute on function platform_todo()                     from anon;
        revoke execute on function platform_todo_list(text)            from anon;
        revoke execute on function platform_search(text)               from anon;
        revoke execute on function platform_bulk(text, uuid[], jsonb)  from anon;
        revoke execute on function platform_undo_cauris(jsonb)         from anon;
        revoke execute on function platform_undo_unlock(jsonb)         from anon;
        revoke execute on function platform_undo_archive(jsonb)        from anon;
        revoke execute on function platform_undo_restore(jsonb)        from anon;
        revoke execute on function platform_undo_setting(jsonb)        from anon;
        revoke execute on function platform_setting_internal(text)     from anon;
        revoke execute on function platform_settings_board()           from anon;
        revoke execute on function platform_set_setting(text, jsonb)   from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: the refusal, the markers, and the undos, which only
        -- platform_undo (104) calls, as its owner, from its whitelist.
        revoke execute on function platform_only()                     from authenticated;
        revoke execute on function platform_setting_internal(text)     from authenticated;
        revoke execute on function platform_undo_cauris(jsonb)         from authenticated;
        revoke execute on function platform_undo_unlock(jsonb)         from authenticated;
        revoke execute on function platform_undo_archive(jsonb)        from authenticated;
        revoke execute on function platform_undo_restore(jsonb)        from authenticated;
        revoke execute on function platform_undo_setting(jsonb)        from authenticated;
        -- The center's doors; each checks the platform on the server.
        grant execute on function platform_todo()                      to authenticated;
        grant execute on function platform_todo_list(text)             to authenticated;
        grant execute on function platform_search(text)                to authenticated;
        grant execute on function platform_bulk(text, uuid[], jsonb)   to authenticated;
        grant execute on function platform_settings_board()            to authenticated;
        grant execute on function platform_set_setting(text, jsonb)    to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
