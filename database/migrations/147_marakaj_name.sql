-- ============================================================
-- 147_marakaj_name.sql — the product is called Marakaj.
--
-- « Mara » becomes « Marakaj » everywhere a person reads it, for a shop,
-- a farm and an association alike (the domain marakaj.com, the store
-- product ids, the bundle id bf.kaj.app and every table, column and
-- function name stay as they are). The app and the Workers say the new
-- name themselves; what the database writes is changed here:
--
-- 1. THE SENTENCES THE FUNCTIONS WRITE. The 52 functions below are the
--    ones whose own text — a refusal, a bell, a journal line, a label —
--    says « Mara ». Each is its latest version (the migration named
--    above it) verbatim, the word inside its quoted text the only change:
--    « Mara Pro » → « Marakaj Pro », « Seul Mara » → « Seul Marakaj »,
--    « l'équipe Mara » → « l'équipe Marakaj »… Its signature, its
--    language, SECURITY DEFINER or not, its pinned search_path and its
--    body otherwise are untouched; create or replace keeps its owner and
--    its grants, so none is said again here (saying an old migration's
--    grant again could reopen what a later one closed). The comments
--    inside the bodies keep the old name: they are not read by anyone
--    using the app.
--
-- 2. TWO DEFAULTS STILL AS SEEDED. Le Chemin's « Mon premier outil avec
--    mes cauris » (097's path_steps.line) and the terms' « what changed »
--    line (142's platform_settings.terms_versions.changes / changes_en).
--    Each is updated only while it is still exactly the old default: a
--    line the platform rewrote is left as it was written.
--
-- Rows already written (a bell, a journal summary, a promotion's note)
-- keep the words they were written with; the app and the push Worker read
-- « Mara » in them as « Marakaj », so a person sees one name. The app
-- works on a database without 147 the same way: it reads the old
-- sentences with the new name until this is applied.
--
-- Apply after 146 (every function below is its 146 state). Re-runnable:
-- create or replace everywhere, and each update guarded by the old value.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The functions' own words
-- ------------------------------------------------------------

-- trg_order_showcase() — 094_showcase_vitrines.sql's, the name only.
create or replace function trg_order_showcase()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if exists (select 1 from orgs where id = new.org_id and showcase) then
        raise exception 'Pas à proximité : cette boutique ne prend pas de commandes près de chez vous. C''est une vitrine d''exemple de Marakaj.';
    end if;
    return new;
end;
$$;

-- trg_orders_terms() — 142_terms_acceptance.sql's, the name only.
create or replace function trg_orders_terms()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if new.customer_id is not null and new.customer_id = auth.uid()
       and not terms_ok(new.customer_id, 'terms') then
        raise exception 'Acceptez d''abord les Conditions d''utilisation de Marakaj pour commander (mettez l''application à jour si elle ne vous les montre pas).';
    end if;
    return new;
end;
$$;

-- audit_log_page(uuid,integer,bigint,text,uuid,text) — 103_admin_security.sql's, the name only.
create or replace function audit_log_page(
    p_org_id  uuid,
    p_limit   int    default 50,
    p_before  bigint default null,
    p_table   text   default null,
    p_actor   uuid   default null,
    p_action  text   default null
)
returns table (
    id          bigint,
    at          timestamptz,
    actor_id    uuid,
    actor_label text,
    action      text,
    table_name  text,
    row_id      uuid,
    summary     text,
    changed     jsonb
)
language sql
stable
security definer
set search_path = public, auth
as $$
    with me as (select caller_is_platform_admin() as platform)
    select l.id, l.at,
           case when pa.id is not null and not me.platform then null else l.actor_id end,
           case when pa.id is not null and not me.platform then 'Marakaj' else l.actor_label end,
           l.action, l.table_name, l.row_id, l.summary, l.changed
    from audit_log l
    cross join me
    left join profiles pa on pa.id = l.actor_id and pa.is_platform_admin
    where l.org_id = p_org_id
      and is_org_head(p_org_id)
      and (p_before is null or l.id < p_before)
      and (p_table  is null or l.table_name = p_table)
      and (p_actor  is null or l.actor_id = p_actor)
      and (p_action is null or l.action = p_action)
    order by l.id desc
    limit greatest(coalesce(p_limit, 50), 1);
$$;

-- my_cauris(uuid) — 100_team_photos_gifts.sql's, the name only.
create or replace function my_cauris(p_org_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_last timestamptz;
begin
    if not is_org_admin(p_org_id) then
        return null;
    end if;
    perform cauris_expire(p_org_id);
    select max(created_at) into v_last from cauris_ledger
     where org_id = p_org_id and reason <> 'expired';
    return jsonb_build_object(
        'balance', cauris_balance(p_org_id),
        'week', (select coalesce(sum(delta), 0) from cauris_ledger
                  where org_id = p_org_id and delta > 0
                    and reason not in ('expired', 'gift', 'promo')
                    and created_at >= date_trunc('week', now() at time zone 'Africa/Ouagadougou')
                                      at time zone 'Africa/Ouagadougou'),
        'expires_on', case when v_last is null then null
                           else ((v_last at time zone 'Africa/Ouagadougou')::date
                                 + cauris_param('cauris_expire_days', 180)) end,
        'promo', cauris_promo_left(p_org_id),
        'referral_code', (select slug from orgs where id = p_org_id),
        'referred', (select referred_by is not null from orgs where id = p_org_id),
        'referral_points', coalesce((select points from cauris_rules where key = 'referral'), 0),
        'referrals', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'name', r.name,
                       'score', vitrine_score(r.id),
                       'orders', (select count(*) from orders o
                                   where o.org_id = r.id and o.status in ('picked_up', 'delivered')),
                       'paid', exists (select 1 from cauris_ledger l
                                        where l.org_id = p_org_id and l.reason = 'referral'
                                          and l.ref = r.id::text)
                   ) order by r.created_at desc)
              from orgs r where r.referred_by = p_org_id), '[]'::jsonb),
        'history', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'delta', l.delta,
                       'reason', l.reason,
                       'label', coalesce(r.label, case l.reason
                                    when 'expired'   then 'Cauris expirés'
                                    when 'spent'     then 'Dépensés'
                                    when 'path_step' then 'Étape du chemin'
                                    when 'prize'     then 'Podium de la semaine'
                                    when 'lesson'    then 'Leçon de l''Académie Marakaj'
                                    when 'gift'      then 'Cadeau de Marakaj'
                                    when 'promo'     then 'Cauris offerts par Marakaj'
                                    else l.reason end),
                       'note', case when l.reason in ('expired', 'spent', 'prize', 'referral',
                                                      'path_step', 'gift', 'promo')
                                    then l.note end,
                       'at', l.created_at) order by l.created_at desc)
              from (select * from cauris_ledger where org_id = p_org_id
                     order by created_at desc limit 60) l
              left join cauris_rules r on r.key = l.reason), '[]'::jsonb),
        'rules', coalesce((
            select jsonb_agg(jsonb_build_object('key', key, 'points', points,
                       'daily_cap', daily_cap, 'label', label) order by sort)
              from cauris_rules where points > 0), '[]'::jsonb)
    );
end;
$$;

-- set_org_wave_allowed(uuid,boolean) — 090_cash_only.sql's, the name only.
create or replace function set_org_wave_allowed(p_org_id uuid, p_allowed boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Seul Marakaj autorise Wave';
    end if;
    update orgs set wave_allowed = coalesce(p_allowed, false) where id = p_org_id;
    if not found then
        raise exception 'No such business';
    end if;
end;
$$;

-- set_org_verified(uuid,boolean) — 088_association_trust.sql's, the name only.
create or replace function set_org_verified(p_org_id uuid, p_verified boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Seul Marakaj peut vérifier une association';
    end if;
    if not exists (select 1 from orgs where id = p_org_id) then
        raise exception 'No such business';
    end if;
    update orgs
       set verified_at = case when p_verified then coalesce(verified_at, now()) end,
           verified_by = case when p_verified then coalesce(verified_by, auth.uid()) end
     where id = p_org_id;
end;
$$;

-- path_lock_message(text) — 097_le_chemin.sql's, the name only.
create or replace function path_lock_message(p_step text)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select case p_step
        when 'invoices'   then 'Factures : ' || path_goal(null, 'articles')
                               || ' articles en vente et ' || path_goal(null, 'photos')
                               || ' en photo pour les débloquer.'
        when 'production' then 'Production : terminez l''étape Remplir pour la débloquer.'
        when 'credits'    then 'Carnet de crédit : '
                               || path_goal(null, 'three_orders')
                               || ' commandes terminées pour le débloquer.'
        when 'second_business' then 'Une deuxième entreprise : avec Marakaj Pro.'
        else 'Outil verrouillé.'
    end;
$$;

-- apply_for_org(text,text,text,text,text,text,text,jsonb) — 111_create_my_business.sql's, the name only.
create or replace function apply_for_org(
    p_name        text,
    p_slug        text,
    p_profile     text,
    p_currency    text,
    p_description text,
    p_phone       text,
    p_email       text,
    p_answers     jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
    v_name  text := coalesce(nullif(btrim(coalesce(p_name, '')), ''), '—');
    v_note  constant text := 'Mettez à jour Marakaj : vous créez maintenant votre activité vous-même';
    v_id    uuid;
    v_full  text;
    v_phone text;
    v_email text;
begin
    if v_actor is null then
        raise exception 'apply_for_org() needs a signed-in caller';
    end if;

    -- Who asked, as Mara reads it in « Activités créées » (107's way).
    select coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                    nullif(btrim(coalesce(p.full_name, '')), ''),
                    nullif(btrim(coalesce(u.raw_user_meta_data ->> 'full_name', '')), '')),
           coalesce(nullif(btrim(coalesce(p.phone, '')), ''),
                    nullif(btrim(coalesce(u.phone, '')), '')),
           nullif(btrim(coalesce(u.email, '')), '')
      into v_full, v_phone, v_email
      from auth.users u
      left join profiles p on p.id = u.id
     where u.id = v_actor;

    insert into org_applications (
        applicant_id, name, slug, profile, currency,
        contact_name, contact_phone, contact_email, description,
        status, decision_note, reviewed_at
    )
    values (
        v_actor, v_name, coalesce(nullif(lower(btrim(coalesce(p_slug, ''))), ''), '—'),
        coalesce(nullif(btrim(coalesce(p_profile, '')), ''), 'generic'),
        coalesce(nullif(btrim(coalesce(p_currency, '')), ''), 'XOF'),
        v_full,
        coalesce(v_phone, nullif(btrim(coalesce(p_phone, '')), '')),
        coalesce(v_email, nullif(btrim(coalesce(p_email, '')), '')),
        nullif(btrim(coalesce(p_description, '')), ''),
        'rejected', v_note, now()
    )
    returning id into v_id;

    -- The bell (099: its facts in params): an older app shows the French
    -- message as written; the new one says it in the reader's language.
    begin
        insert into notifications (recipient_id, org_id, kind, message, params)
        values (v_actor, null, 'application_update_app', v_note,
                jsonb_build_object('to', 'applicant', 'name', v_name));
    exception when others then
        null;
    end;
    return v_id;
end;
$$;

-- courier_idle_nudge() — 115_notifications.sql's, the name only.
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
           'Cela fait 7 jours sans livraison : des courses vous attendent sur Marakaj.',
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

-- team_full_message(uuid) — 100_team_photos_gifts.sql's, the name only.
create or replace function team_full_message(p_org_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select case when org_setup_done(p_org_id)
        then 'Kaj Pro : cette entreprise a déjà sa personne offerte en plus du propriétaire. '
             || 'Pour ajouter quelqu''un : Marakaj Pro, ou l''équipe débloquée avec des cauris.'
        else 'Kaj Pro : la personne offerte s''ouvre une fois la mise en route de l''entreprise terminée. '
             || 'Avant : Marakaj Pro, ou l''équipe débloquée avec des cauris.'
    end;
$$;

-- cauris_feature_label(text) — 100_team_photos_gifts.sql's, the name only.
create or replace function cauris_feature_label(p_feature text)
returns text
language sql
immutable
set search_path = public
as $$
    select case p_feature
        when 'pro_all'        then 'Marakaj Pro complet'
        when 'analytics'      then 'les analyses'
        when 'delivery'       then 'la livraison'
        when 'online_payment' then 'le paiement en ligne'
        when 'vitrine_plus'   then 'la vitrine personnalisée'
        when 'accounting'     then 'la comptabilité'
        when 'team_access'    then 'l''équipe'
        when 'payroll'        then 'la paie'
        when 'currencies'     then 'les devises'
        when 'tontines'       then 'les tontines'
        else p_feature
    end;
$$;

-- platform_give_cauris(uuid,integer,text,date) — 100_team_photos_gifts.sql's, the name only.
create or replace function platform_give_cauris(
    p_org_id     uuid,
    p_points     integer,
    p_note       text default null,
    p_expires_on date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org   orgs%rowtype;
    v_note  text := nullif(btrim(coalesce(p_note, '')), '');
    v_ref   text := gen_random_uuid()::text;
    v_promo uuid;
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Seule la plateforme offre des cauris';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if not found then
        raise exception 'Entreprise inconnue';
    end if;
    if v_org.showcase then
        raise exception 'Une vitrine d''exemple ne reçoit pas de cauris';
    end if;
    if p_points is null or p_points <= 0 or p_points > 100000 then
        raise exception 'Le nombre de cauris doit être entre 1 et 100 000';
    end if;
    if p_expires_on is not null and p_expires_on <= cauris_today() then
        raise exception 'La date doit être après aujourd''hui';
    end if;

    perform pg_advisory_xact_lock(hashtext('cauris:' || p_org_id::text));
    perform cauris_expire(p_org_id);
    if p_expires_on is null then
        insert into cauris_ledger (org_id, delta, reason, ref, note)
        values (p_org_id, p_points, 'gift', v_ref, coalesce(v_note, 'Offert par Marakaj'));
    else
        insert into cauris_promos (org_id, points, left_points, expires_on, note, given_by)
        values (p_org_id, p_points, p_points, p_expires_on, v_note, auth.uid())
        returning id into v_promo;
        insert into cauris_ledger (org_id, delta, reason, ref, note)
        values (p_org_id, p_points, 'promo', v_promo::text,
                coalesce(v_note, 'Offert par Marakaj') || ' · avant le '
                || to_char(p_expires_on, 'DD/MM/YYYY'));
    end if;

    begin
        perform notify_org_admins(p_org_id,
            case when p_expires_on is null then 'cauris_gift' else 'cauris_promo' end,
            'Marakaj vous offre ' || p_points || ' cauris'
            || case when p_expires_on is not null
                    then ', à utiliser avant le ' || to_char(p_expires_on, 'DD/MM/YYYY') else '' end
            || case when v_note is not null then ' : ' || v_note else '' end || '.',
            jsonb_build_object('to', 'shop', 'points', p_points, 'note', v_note,
                               'until', p_expires_on));
    exception when others then
        null;  -- a bell never costs the gift
    end;

    return jsonb_build_object('balance', cauris_balance(p_org_id),
                              'promo', cauris_promo_left(p_org_id));
end;
$$;

-- trg_photo_revive() — 100_team_photos_gifts.sql's, the name only.
create or replace function trg_photo_revive()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_limit int;
begin
    if old.is_active or not new.is_active
       or auth.uid() is null
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
       or not exists (select 1 from documents d
                       where d.product_id = new.id and doc_is_photo(d.kind, d.content_type)) then
        return new;
    end if;
    v_limit := org_photo_limit(new.org_id);
    if v_limit is null then
        return new;
    end if;
    perform pg_advisory_xact_lock(hashtext('photos:' || new.org_id::text));
    if org_photo_items(new.org_id) >= v_limit then
        raise exception 'Kaj Pro : cet article a une photo et toutes vos places photo sont prises. '
            'Pour le remettre : Marakaj Pro, une place photo achetée avec des cauris, '
            'ou un autre article photographié retiré.';
    end if;
    return new;
end;
$$;

-- trg_photo_items() — 100_team_photos_gifts.sql's, the name only.
create or replace function trg_photo_items()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_limit int;
begin
    if new.product_id is null or not doc_is_photo(new.kind, new.content_type) then
        return new;  -- no article, or paperwork: 066's general cap
    end if;
    if tg_op = 'UPDATE' and old.product_id is not distinct from new.product_id
       and doc_is_photo(old.kind, old.content_type) then
        return new;  -- already this article's picture
    end if;
    if auth.uid() is null
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        return new;
    end if;
    v_limit := org_photo_limit(new.org_id);
    if v_limit is null then
        return new;
    end if;
    perform pg_advisory_xact_lock(hashtext('photos:' || new.org_id::text));
    -- Another picture of an article already photographed takes no new
    -- place; an article out of the shop is counted when it comes back
    -- (trg_photo_revive).
    if exists (select 1 from documents d
                where d.product_id = new.product_id and d.id <> new.id
                  and doc_is_photo(d.kind, d.content_type))
       or not exists (select 1 from products p
                       where p.id = new.product_id and p.is_active) then
        return new;
    end if;
    if org_photo_items(new.org_id) >= v_limit then
        if tg_op = 'UPDATE' then
            raise exception 'Kaj Pro : toutes vos places photo sont prises. '
                'La photo reste dans vos documents, sans article. Pour la mettre sur l''article : '
                'Marakaj Pro, ou une place photo achetée avec des cauris.';
        end if;
        raise exception 'Kaj Pro : toutes vos places photo sont prises. '
            'Pour photographier un article de plus : Marakaj Pro, ou une place photo achetée avec des cauris.';
    end if;
    return new;
end;
$$;

-- platform_give_unlock(uuid,text,date,text) — 100_team_photos_gifts.sql's, the name only.
create or replace function platform_give_unlock(
    p_org_id  uuid,
    p_feature text,
    p_until   date,
    p_note    text default null
)
returns timestamptz
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org   orgs%rowtype;
    v_until timestamptz;
    v_note  text := coalesce(nullif(btrim(coalesce(p_note, '')), ''), 'Offert par Marakaj');
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Seule la plateforme offre un outil';
    end if;
    select * into v_org from orgs where id = p_org_id;
    if not found then
        raise exception 'Entreprise inconnue';
    end if;
    if p_feature is null or p_feature = 'photo_slot'
       or not (coalesce(plan_setting('pro_features'), '[]'::jsonb) ? p_feature
               or exists (select 1 from cauris_costs where feature = p_feature)) then
        raise exception 'Outil inconnu : %', coalesce(p_feature, '');
    end if;
    if p_until is null or p_until < cauris_today() then
        raise exception 'La date doit être aujourd''hui ou plus tard';
    end if;
    v_until := (p_until + 1)::timestamp at time zone 'Africa/Ouagadougou';

    -- A tool the business bought and still has open stays its own: the gift
    -- only lengthens it, and never relabels it « Offert par Mara » (nor takes
    -- it off Le Chemin's « premier outil »).
    insert into cauris_unlocks (org_id, feature, until, note, gifted_by)
    values (p_org_id, p_feature, v_until, v_note, auth.uid())
    on conflict (org_id, feature) do update
        set until = greatest(cauris_unlocks.until, excluded.until),
            note = case when cauris_unlocks.gifted_by is null and cauris_unlocks.until > now()
                        then cauris_unlocks.note else excluded.note end,
            gifted_by = case when cauris_unlocks.gifted_by is null and cauris_unlocks.until > now()
                             then null else excluded.gifted_by end,
            updated_at = now()
    returning until into v_until;

    begin
        perform notify_org_admins(p_org_id, 'feature_gift',
            'Marakaj vous offre ' || cauris_feature_label(p_feature) || ' jusqu''au '
            || to_char(p_until, 'DD/MM/YYYY') || '.',
            jsonb_build_object('to', 'shop', 'feature', p_feature, 'until', p_until,
                               'note', v_note));
    exception when others then
        null;
    end;
    return v_until;
end;
$$;

-- audit_log_actors(uuid) — 103_admin_security.sql's, the name only.
create or replace function audit_log_actors(p_org_id uuid)
returns table (actor_id uuid, actor_label text, events bigint, last_seen timestamptz)
language sql
stable
security definer
set search_path = public, auth
as $$
    with me as (select caller_is_platform_admin() as platform),
    rows as (
        select case when pa.id is not null and not me.platform then null else l.actor_id end as actor_id,
               case when pa.id is not null and not me.platform then 'Marakaj' else l.actor_label end as actor_label,
               l.at
          from audit_log l
          cross join me
          left join profiles pa on pa.id = l.actor_id and pa.is_platform_admin
         where l.org_id = p_org_id
           and is_org_head(p_org_id)
    )
    select r.actor_id, max(r.actor_label), count(*), max(r.at)
      from rows r
     group by r.actor_id
     order by 4 desc;
$$;

-- update_org(uuid,text,text,text,text) — 111_create_my_business.sql's, the name only.
create or replace function update_org(
    p_org_id   uuid,
    p_name     text default null,
    p_slug     text default null,
    p_profile  text default null,
    p_currency text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor   uuid := auth.uid();
    v_name    text := nullif(btrim(coalesce(p_name, '')), '');
    v_slug    text := nullif(lower(btrim(coalesce(p_slug, ''))), '');
    v_profile text := nullif(btrim(coalesce(p_profile, '')), '');
    v_problem text;
    v_old     text;
begin
    if v_actor is null then
        raise exception 'update_org() needs a signed-in caller';
    end if;

    if not is_org_admin(p_org_id) then
        raise exception 'You cannot change this business';
    end if;

    select profile::text into v_old from orgs where id = p_org_id;
    if not found then
        raise exception 'No such business';
    end if;

    if exists (select 1 from orgs where id = p_org_id and archived_at is not null) then
        raise exception 'This business is archived. Restore it before changing it.';
    end if;

    if v_slug is not null then
        v_problem := org_slug_problem(v_slug);
        if v_problem is not null then
            raise exception '%', v_problem;
        end if;
        if exists (select 1 from orgs where slug = v_slug and id <> p_org_id) then
            raise exception 'That address is already taken.';
        end if;
        if business_address_reserved(v_slug)
           and not caller_is_platform_admin()
           and not exists (select 1 from orgs where id = p_org_id and slug = v_slug) then
            raise exception 'Cette adresse est réservée à Marakaj : choisissez-en une autre.';
        end if;
    end if;

    if v_profile is not null
       and v_profile not in ('church', 'association', 'farm', 'retail', 'generic') then
        raise exception 'Unknown profile: %', v_profile;
    end if;
    if v_profile is not null and v_profile is distinct from v_old then
        if not is_org_owner(p_org_id) then
            raise exception 'Seul le propriétaire change le genre d''activité';
        end if;
        perform notify_org_owners(p_org_id, 'org_kind_changed',
            'Le genre de votre activité a été changé',
            jsonb_build_object('profile', v_profile));
    end if;

    update orgs set
        name             = coalesce(v_name, name),
        slug             = coalesce(v_slug, slug),
        profile          = coalesce(v_profile, profile),
        default_currency = coalesce(nullif(btrim(coalesce(p_currency, '')), ''),
                                    default_currency)
    where id = p_org_id;

    return p_org_id;
end;
$$;

-- feature_lapse_watch(uuid) — 104_feature_switchboard.sql's, the name only.
create or replace function feature_lapse_watch(p_org uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    c      record;
    v_kind text := org_kind(p_org);
begin
    if v_kind is null
       or (not exists (select 1 from feature_rules r
                        where (r.scope = 'org' and r.org_id = p_org)
                           or (r.scope = 'kind' and r.kind = v_kind))
           and not exists (select 1 from feature_pay_watch w where w.org_id = p_org)) then
        return;
    end if;
    for c in select f.key, f.label from feature_catalog f
              where f.pro_tool is not null order by f.sort, f.key loop
        if not feature_rule_hides(p_org, c.key) then
            delete from feature_pay_watch where org_id = p_org and feature = c.key;
        elsif feature_paid(p_org, c.key) then
            insert into feature_pay_watch (org_id, feature, state, since)
            values (p_org, c.key, 'kept', now())
            on conflict (org_id, feature) do update set state = 'kept', since = now()
                where feature_pay_watch.state <> 'kept';
        else
            update feature_pay_watch set state = 'lapsed', since = now()
             where org_id = p_org and feature = c.key and state = 'kept';
            if found then
                -- The owner, whoever is reading (notify_org_owners would
                -- skip an owner who is the one opening the app).
                insert into notifications (recipient_id, org_id, kind, message, params)
                select distinct m.user_id, p_org, 'feature_lapsed',
                       'Votre Marakaj Pro a pris fin : ' || c.label
                           || ' n''est plus disponible pour votre activité.',
                       jsonb_build_object('to', 'shop', 'feature', c.key, 'label', c.label)
                  from memberships m
                 where m.org_id = p_org and m.role = 'owner' and not m.is_trainer;
            end if;
        end if;
    end loop;
end;
$$;

-- platform_set_feature_rule(text,text,uuid,text,text,timestamp with time zone,text) — 104_feature_switchboard.sql's, the name only.
create or replace function platform_set_feature_rule(
    p_scope   text,
    p_kind    text,
    p_org     uuid,
    p_feature text,
    p_state   text,
    p_until   timestamptz default null,
    p_note    text        default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_kind   text := case when p_kind = 'church' then 'association' else p_kind end;
    v_note   text := nullif(btrim(coalesce(p_note, '')), '');
    v_before jsonb;
    v_after  jsonb;
    v_name   text;
    v_label  text;
    c        feature_catalog%rowtype;
    v_action uuid;
    v_what   text;
    v_org    uuid := case when p_scope = 'org' then p_org end;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    select * into c from feature_catalog where key = p_feature;
    if not found then
        raise exception 'Fonction inconnue : %', coalesce(p_feature, '');
    end if;
    if p_state is null or p_state not in ('default', 'visible', 'hidden') then
        raise exception 'Réglage inconnu : %', coalesce(p_state, '');
    end if;
    if p_until is not null and p_until <= now() then
        raise exception 'La date de fin doit être dans le futur';
    end if;

    if p_scope = 'kind' then
        if v_kind is null or v_kind not in ('retail', 'farm', 'association') then
            raise exception 'Type d''activité inconnu : %', coalesce(p_kind, '');
        end if;
    elsif p_scope = 'org' then
        select name into v_name from orgs where id = p_org;
        if not found then
            raise exception 'Entreprise inconnue';
        end if;
        v_kind := org_kind(p_org);
    else
        raise exception 'Portée inconnue : %', coalesce(p_scope, '');
    end if;
    -- A tool the kind does not have is never switched — only a rule left
    -- over from a former kind may be put back « Par défaut » (cleared).
    if not (v_kind = any (c.kinds)) and p_state <> 'default' then
        raise exception 'Cette fonction n''existe pas pour ce type d''activité.';
    end if;
    if p_scope = 'org' and p_state = 'hidden' and feature_paid(p_org, p_feature) then
        raise exception 'Fonction payée par l''activité : elle ne peut pas être masquée.';
    end if;

    v_before := feature_rule_json(p_scope, v_kind, p_org, p_feature);
    if p_state = 'default' then
        delete from feature_rules r
         where r.feature = p_feature
           and ((p_scope = 'kind' and r.scope = 'kind' and r.kind = v_kind)
                or (p_scope = 'org' and r.scope = 'org' and r.org_id = p_org));
    elsif p_scope = 'kind' then
        insert into feature_rules (scope, kind, feature, state, until, note, set_by)
        values ('kind', v_kind, p_feature, p_state, p_until, v_note, auth.uid())
        on conflict (kind, feature) where scope = 'kind' do update
            set state = excluded.state, until = excluded.until, note = excluded.note,
                set_by = excluded.set_by, set_at = now();
    else
        insert into feature_rules (scope, org_id, feature, state, until, note, set_by)
        values ('org', p_org, p_feature, p_state, p_until, v_note, auth.uid())
        on conflict (org_id, feature) where scope = 'org' do update
            set state = excluded.state, until = excluded.until, note = excluded.note,
                set_by = excluded.set_by, set_at = now();
    end if;
    v_after := feature_rule_json(p_scope, v_kind, p_org, p_feature);

    -- Nothing moved: nothing to log, nobody to tell.
    if v_before is not distinct from v_after then
        return null;
    end if;

    -- A kind's switch hides a Pro tool: every business of that kind paying
    -- for it keeps it — remembered, so its owner is told the day the
    -- payment ends and the tool goes (feature_lapse_watch).
    if p_scope = 'kind' and p_state = 'hidden' and c.pro_tool is not null then
        insert into feature_pay_watch (org_id, feature, state, since)
        select o.id, p_feature, 'kept', now()
          from orgs o
         where o.archived_at is null
           and (case when o.profile::text = 'church' then 'association' else o.profile::text end) = v_kind
           and feature_paid(o.id, p_feature)
        on conflict (org_id, feature) do update set state = 'kept', since = now();
    end if;

    v_label := c.label;
    v_what := case p_state
        when 'hidden'  then 'masqué'
        when 'visible' then 'rendu visible'
        else 'remis par défaut' end;
    v_action := platform_log_action(
        v_org,
        'feature_rule',
        '« ' || v_label || ' » ' || v_what || ' — '
            || case when p_scope = 'kind'
                    then case v_kind when 'retail' then 'toutes les boutiques'
                                     when 'farm' then 'toutes les fermes'
                                     else 'toutes les associations' end
                    else v_name end
            || case when p_until is not null
                    then ' (jusqu''au ' || to_char(p_until at time zone 'Africa/Ouagadougou', 'DD/MM/YYYY') || ')'
                    else '' end,
        v_before,
        v_after,
        'platform_restore_feature_rule',
        jsonb_build_object('scope', p_scope, 'kind', case when p_scope = 'kind' then v_kind end,
                           'org_id', v_org, 'feature', p_feature,
                           'rule', v_before, 'expect', v_after));

    -- A leftover cleared rings no bell: the business never had that tool.
    if p_scope = 'org' and v_kind = any (c.kinds) then
        perform notify_org_owners(p_org, 'feature_rule',
            case p_state
                when 'hidden'  then 'Marakaj a masqué « ' || v_label || ' » pour votre activité.'
                when 'visible' then 'Marakaj a rendu « ' || v_label || ' » visible pour votre activité.'
                else 'Marakaj a remis « ' || v_label || ' » comme par défaut pour votre activité.' end,
            jsonb_build_object('feature', p_feature, 'label', v_label, 'state', p_state,
                               'until', p_until));
    end if;
    return v_action;
end;
$$;

-- platform_restore_feature_rule(jsonb) — 104_feature_switchboard.sql's, the name only.
create or replace function platform_restore_feature_rule(p_args jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_scope   text  := p_args->>'scope';
    v_kind    text  := p_args->>'kind';
    v_org     uuid  := nullif(p_args->>'org_id', '')::uuid;
    v_feature text  := p_args->>'feature';
    v_rule    jsonb := nullif(p_args->'rule', 'null'::jsonb);
    v_label   text;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    if feature_rule_json(v_scope, v_kind, v_org, v_feature)
       is distinct from nullif(p_args->'expect', 'null'::jsonb) then
        raise exception 'Ce réglage a changé depuis : annulez d''abord le changement plus récent.';
    end if;
    delete from feature_rules r
     where r.feature = v_feature
       and ((v_scope = 'kind' and r.scope = 'kind' and r.kind = v_kind)
            or (v_scope = 'org' and r.scope = 'org' and r.org_id = v_org));
    if v_rule is not null then
        insert into feature_rules (scope, kind, org_id, feature, state, until, note, set_by)
        values (v_scope, case when v_scope = 'kind' then v_kind end,
                case when v_scope = 'org' then v_org end, v_feature,
                v_rule->>'state', nullif(v_rule->>'until', '')::timestamptz,
                v_rule->>'note', auth.uid());
    end if;
    if v_scope = 'org' then
        select label into v_label from feature_catalog where key = v_feature;
        perform notify_org_owners(v_org, 'feature_rule',
            case coalesce(v_rule->>'state', 'default')
                when 'hidden'  then 'Marakaj a masqué « ' || v_label || ' » pour votre activité.'
                when 'visible' then 'Marakaj a rendu « ' || v_label || ' » visible pour votre activité.'
                else 'Marakaj a remis « ' || v_label || ' » comme par défaut pour votre activité.' end,
            jsonb_build_object('feature', v_feature, 'label', v_label,
                               'state', coalesce(v_rule->>'state', 'default')));
    end if;
end;
$$;

-- platform_actions_page(uuid,integer,timestamp with time zone,uuid) — 104_feature_switchboard.sql's, the name only.
create or replace function platform_actions_page(
    p_org       uuid        default null,
    p_limit     int         default 50,
    p_before    timestamptz default null,
    p_before_id uuid        default null
)
returns table (
    id              uuid,
    at              timestamptz,
    actor_id        uuid,
    actor_label     text,
    org_id          uuid,
    org_name        text,
    kind            text,
    summary         text,
    before          jsonb,
    after           jsonb,
    undoable        boolean,
    undone_at       timestamptz,
    undone_by_label text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    return query
    select a.id, a.at, a.actor,
           coalesce(nullif(btrim(pa.full_name), ''), 'Marakaj'),
           a.org_id, o.name, a.kind, a.summary, a.before, a.after,
           a.undo_fn is not null and a.undone_at is null
               and exists (select 1 from platform_undo_fns f where f.fn = a.undo_fn),
           a.undone_at,
           case when a.undone_at is not null
                then coalesce(nullif(btrim(pu.full_name), ''), 'Marakaj') end
      from platform_actions a
      left join orgs o      on o.id  = a.org_id
      left join profiles pa on pa.id = a.actor
      left join profiles pu on pu.id = a.undone_by
     where (p_org is null or a.org_id = p_org)
       and (p_before is null
            or a.at < p_before
            or (a.at = p_before and p_before_id is not null and a.id < p_before_id))
     order by a.at desc, a.id desc
     limit greatest(1, least(coalesce(p_limit, 50), 200));
end;
$$;

-- platform_undo_cauris(jsonb) — 105_command_center.sql's, the name only.
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
    v_line    bigint := nullif(p_args->>'ledger_id', '')::bigint;
    v_ref     text := coalesce(p_args->>'ref', gen_random_uuid()::text);
    v_balance int;
    v_left    int;
    v_spent   int;
    v_take    int;
begin
    perform platform_only();
    perform pg_advisory_xact_lock(hashtext('cauris:' || v_org::text));
    perform cauris_expire(v_org);
    v_balance := greatest(cauris_balance(v_org), 0);
    if v_promo is not null then
        -- Promotional cauris are a lot of their own: spending takes from it
        -- first (100's cauris_take), so what is left of it is exactly what
        -- may be taken back.
        select left_points into v_left from cauris_promos where id = v_promo for update;
        v_take := least(coalesce(v_left, 0), v_balance);
    else
        -- Plain cauris mix with what the business earns: never take back
        -- more than the gift less what was spent since — cauris earned
        -- after it are the business's own. Spent: every line out of the
        -- wallet after the gift's own (spending, expiry), but not another
        -- gift's undo nor a promotional lot's expiry, which are not these.
        if v_line is null then
            raise exception 'Ce cadeau est introuvable dans le porte-monnaie : il n''est pas repris.';
        end if;
        select coalesce(sum(-l.delta), 0)::int into v_spent
          from cauris_ledger l
         where l.org_id = v_org and l.id > v_line and l.delta < 0
           and l.reason not in ('gift', 'promo')
           and not (l.reason = 'expired' and l.ref like 'promo:%');
        v_take := least(coalesce(v_points, 0) - v_spent, v_balance);
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
            'undo:' || v_ref, 'Cadeau annulé par Marakaj');
    begin
        perform notify_org_admins(v_org, 'gift_undone',
            'Marakaj a repris ' || v_take || ' cauris offerts.',
            jsonb_build_object('to', 'shop', 'points', v_take));
    exception when others then
        null;  -- a bell never blocks the undo
    end;
end;
$$;

-- platform_undo_unlock(jsonb) — 105_command_center.sql's, the name only.
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
            'Marakaj a annulé l''ouverture de ' || cauris_feature_label(v_feature) || '.',
            jsonb_build_object('to', 'shop', 'feature', v_feature));
    exception when others then
        null;
    end;
end;
$$;

-- mara_edit_summary(text,jsonb) — 106_business_fiche.sql's, the name only.
create or replace function mara_edit_summary(p_what text, p_after jsonb)
returns text
language sql
stable
as $$
    select case p_what
        when 'vitrine'  then 'Vitrine : '
        when 'identity' then 'Identité : '
        when 'plan'     then 'Formule : '
        else ''
    end
    || case
        when p_what = 'plan' and p_after ? 'plan' and p_after ->> 'plan' = 'pro'
            then 'Marakaj Pro'
                 || case when nullif(p_after ->> 'plan_until', '') is not null
                         then ' jusqu''au ' || to_char((p_after ->> 'plan_until')::date, 'DD/MM/YYYY')
                         else ' sans date de fin' end
        when p_what = 'plan' and p_after ? 'plan'
            then 'Marakaj (gratuit)'
        else coalesce(mara_edit_words(mara_edit_keys(p_what, p_after)), '')
    end;
$$;

-- mara_edit_message(text,text[],boolean) — 106_business_fiche.sql's, the name only.
create or replace function mara_edit_message(p_what text, p_cols text[], p_undone boolean)
returns text
language sql
immutable
as $$
    select case
        when p_undone and p_what = 'vitrine'
            then 'Marakaj a annulé sa modification de votre vitrine'
        when p_undone
            then 'Marakaj a annulé sa modification de l''identité de votre activité'
        when p_what = 'vitrine'
            then 'Marakaj a modifié votre vitrine'
        else 'Marakaj a modifié l''identité de votre activité : ' || coalesce(mara_edit_words(p_cols), '')
    end;
$$;

-- platform_org_overview(uuid) — 106_business_fiche.sql's, the name only.
create or replace function platform_org_overview(p_org uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    o        orgs%rowtype;
    v_owner  jsonb;
    v_days   int;
    v_health text;
    v_alerts jsonb := '[]'::jsonb;
    v_today  date := (now() at time zone 'Africa/Ouagadougou')::date;
    v_n      int;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à l''équipe Marakaj';
    end if;
    select * into o from orgs where id = p_org;
    if not found then
        raise exception 'Entreprise inconnue';
    end if;

    select jsonb_build_object(
               'user_id', m.user_id,
               'name',    person_name(m.user_id),
               'phone',   coalesce(nullif(btrim(p.phone), ''), u.phone),
               'email',   u.email)
      into v_owner
      from memberships m
      left join profiles p on p.id = m.user_id
      left join auth.users u on u.id = m.user_id
     where m.org_id = p_org and m.role = 'owner' and not m.is_trainer
     order by m.created_at
     limit 1;

    v_days := case when o.last_activity_at is null then null
                   else extract(day from now() - o.last_activity_at)::int end;
    v_health := case
        when o.archived_at is not null then 'archived'
        when o.last_activity_at is null then 'never'
        when v_days >= 30 then 'silent'
        when v_days >= 7 then 'slowing'
        else 'healthy'
    end;

    -- What wants attention, most urgent first.
    if o.suspended_at is not null then
        v_alerts := v_alerts || jsonb_build_object('kind', 'suspended', 'at', o.suspended_at);
    end if;
    select count(*) into v_n from plan_requests r where r.org_id = p_org and r.handled_at is null;
    if v_n > 0 then
        v_alerts := v_alerts || jsonb_build_object('kind', 'paid_claim', 'n', v_n);
    end if;
    select count(*) into v_n from promotions s
     where s.org_id = p_org and s.status in ('requested', 'paid_claimed');
    if v_n > 0 then
        v_alerts := v_alerts || jsonb_build_object('kind', 'promotion', 'n', v_n);
    end if;
    if o.plan = 'pro' and o.plan_until is not null
       and o.plan_until between v_today and v_today + 7 then
        v_alerts := v_alerts || jsonb_build_object('kind', 'pro_ending', 'until', o.plan_until);
    end if;
    select count(*) into v_n from cauris_unlocks u
     where u.org_id = p_org and u.until > now() and u.until <= now() + interval '7 days';
    if v_n > 0 then
        v_alerts := v_alerts || jsonb_build_object('kind', 'unlock_ending', 'n', v_n);
    end if;
    select count(*) into v_n from feature_rules r
     where r.scope = 'org' and r.org_id = p_org
       and r.until is not null and r.until > now() and r.until <= now() + interval '7 days';
    if v_n > 0 then
        v_alerts := v_alerts || jsonb_build_object('kind', 'rule_ending', 'n', v_n);
    end if;
    if o.archived_at is null and v_health in ('silent', 'never') then
        v_alerts := v_alerts || jsonb_build_object('kind', v_health, 'days', v_days);
    end if;
    if o.archived_at is null and not org_setup_done(p_org) then
        v_alerts := v_alerts || jsonb_build_object('kind', 'setup');
    end if;

    return jsonb_build_object(
        'id',               o.id,
        'name',             o.name,
        'slug',             o.slug,
        'profile',          o.profile,
        'association_kind', o.association_kind,
        'currency',         o.default_currency,
        'phone',            o.phone,
        'address',          o.address,
        'city',             o.city,
        'created_at',       o.created_at,
        'archived_at',      o.archived_at,
        'suspended_at',     o.suspended_at,
        'verified_at',      o.verified_at,
        'showcase',         o.showcase,
        'wave_allowed',     o.wave_allowed,
        'setup_done',       org_setup_done(p_org),
        'health',           v_health,
        'last_activity_at', o.last_activity_at,
        'days_silent',      v_days,
        'owner',            v_owner,
        'members',          (select count(distinct m.user_id) from memberships m
                              where m.org_id = p_org and not m.is_trainer),
        'roles',            coalesce((select jsonb_object_agg(r.role, r.n)
                                        from (select m.role::text as role, count(distinct m.user_id) as n
                                                from memberships m
                                               where m.org_id = p_org and not m.is_trainer
                                               group by m.role) r), '{}'::jsonb),
        'plan',             org_plan(p_org),
        'plan_raw',         o.plan,
        'plan_until',       o.plan_until,
        'plan_note',        o.plan_note,
        'cauris',           cauris_balance(p_org),
        'promo',            cauris_promo_left(p_org),
        'unlocks',          coalesce((select jsonb_agg(jsonb_build_object(
                                            'feature', u.feature, 'until', u.until,
                                            'gift', u.gifted_by is not null, 'note', u.note)
                                          order by u.until)
                                        from cauris_unlocks u
                                       where u.org_id = p_org and u.until > now()), '[]'::jsonb),
        'vitrine',          jsonb_build_object(
                                'open', o.storefront_enabled,
                                'published', (select count(*) from products p
                                               where p.org_id = p_org and p.is_active and p.is_published)),
        'rules',            (select count(*) from feature_rules r
                              where r.scope = 'org' and r.org_id = p_org),
        'actions',          (select count(*) from platform_actions a
                              where a.org_id = p_org and a.undone_at is null),
        'last_action_at',   (select max(a.at) from platform_actions a where a.org_id = p_org),
        'alerts',           v_alerts
    );
end;
$$;

-- platform_update_org_identity(uuid,text,text,text,text,text,text,boolean,text) — 106_business_fiche.sql's, the name only.
create or replace function platform_update_org_identity(
    p_org      uuid,
    p_name     text    default null,
    p_profile  text    default null,
    p_slug     text    default null,
    p_currency text    default null,
    p_phone    text    default null,
    p_address  text    default null,
    p_verified boolean default null,
    p_confirm  text    default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    o         orgs%rowtype;
    v_old     jsonb;
    v_new     jsonb;
    v_before  jsonb := '{}'::jsonb;
    v_after   jsonb := '{}'::jsonb;
    v_name    text := nullif(btrim(coalesce(p_name, '')), '');
    v_profile text := nullif(btrim(coalesce(p_profile, '')), '');
    v_slug    text := nullif(lower(btrim(coalesce(p_slug, ''))), '');
    v_cur     text := nullif(upper(btrim(coalesce(p_currency, ''))), '');
    v_problem text;
    v_col     text;
    v_cols    text[];
    v_action  uuid;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à l''équipe Marakaj';
    end if;
    select * into o from orgs where id = p_org for update;
    if not found then
        raise exception 'Entreprise inconnue';
    end if;
    if o.archived_at is not null then
        raise exception 'Cette activité est archivée : restaurez-la avant de la modifier';
    end if;
    if p_name is not null and v_name is null then
        raise exception 'Le nom de l''activité ne peut pas être vide';
    end if;
    if v_slug is not null and v_slug is distinct from o.slug then
        v_problem := org_slug_problem(v_slug);
        if v_problem is not null then
            raise exception '%', v_problem;
        end if;
        if exists (select 1 from orgs where slug = v_slug and id <> p_org) then
            raise exception 'Cette adresse est déjà prise';
        end if;
    end if;
    if v_profile is not null and v_profile is distinct from o.profile::text then
        if v_profile not in ('retail', 'farm', 'association') then
            raise exception 'Type d''activité inconnu : %', v_profile;
        end if;
        if lower(btrim(coalesce(p_confirm, ''))) <> lower(btrim(o.name)) then
            raise exception 'Pour changer le type d''activité, tapez le nom de l''activité : %', o.name;
        end if;
    end if;
    if v_cur is not null and v_cur !~ '^[A-Z]{3}$' then
        raise exception 'Monnaie inconnue : %', p_currency;
    end if;
    if p_verified is not null
       and p_verified is distinct from (o.verified_at is not null)
       and coalesce(v_profile, o.profile::text) not in ('association', 'church') then
        raise exception 'La vérification par Marakaj concerne les associations';
    end if;

    v_old := to_jsonb(o);
    perform set_config('mara.logged_write', 'on', true);
    update orgs set
        name             = coalesce(v_name, name),
        slug             = coalesce(v_slug, slug),
        profile          = coalesce(v_profile, profile::text),
        default_currency = coalesce(v_cur, default_currency),
        phone            = case when p_phone is null then phone
                                else nullif(btrim(p_phone), '') end,
        address          = case when p_address is null then address
                                else nullif(btrim(p_address), '') end,
        verified_at      = case when p_verified is null then verified_at
                                when p_verified then coalesce(verified_at, now()) end,
        verified_by      = case when p_verified is null then verified_by
                                when p_verified then coalesce(verified_by, auth.uid()) end
     where id = p_org
    returning to_jsonb(orgs) into v_new;
    perform set_config('mara.logged_write', '', true);

    foreach v_col in array mara_edit_columns('identity') loop
        if v_old -> v_col is distinct from v_new -> v_col then
            v_before := v_before || jsonb_build_object(v_col, v_old -> v_col);
            v_after  := v_after  || jsonb_build_object(v_col, v_new -> v_col);
        end if;
    end loop;
    if v_before = '{}'::jsonb then
        return null;
    end if;

    -- A new kind finds its own chart of accounts (create_org's, 035);
    -- nothing of the old one is removed.
    if v_after ? 'profile' then
        case v_after ->> 'profile'
            when 'association' then perform seed_church_accounts(p_org);
            when 'retail'      then perform seed_retail_accounts(p_org);
            when 'farm'        then perform seed_farm_accounts(p_org);
            else null;
        end case;
    end if;

    v_action := platform_log_action(p_org, 'identity',
        mara_edit_summary('identity', v_after), v_before, v_after,
        'platform_undo_org_columns',
        jsonb_build_object('org', p_org, 'what', 'identity',
                           'before', v_before, 'after', v_after));
    v_cols := mara_edit_keys('identity', v_after);
    perform notify_org_owners(p_org, 'mara_edited',
        mara_edit_message('identity', v_cols, false),
        jsonb_build_object('what', 'identity', 'fields', to_jsonb(v_cols), 'action', v_action));
    return v_action;
end;
$$;

-- platform_undo_org_columns(jsonb) — 106_business_fiche.sql's, the name only.
create or replace function platform_undo_org_columns(p_args jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org    uuid := nullif(p_args ->> 'org', '')::uuid;
    v_what   text := p_args ->> 'what';
    v_before jsonb := coalesce(p_args -> 'before', '{}'::jsonb);
    v_after  jsonb := coalesce(p_args -> 'after', '{}'::jsonb);
    v_now    jsonb;
    v_col    text;
    v_sets   text[] := '{}';
    v_cols   text[];
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à l''équipe Marakaj';
    end if;
    if v_what not in ('vitrine', 'identity', 'plan')
       or jsonb_typeof(v_before) <> 'object' or v_before = '{}'::jsonb then
        raise exception 'Rien à annuler';
    end if;
    select to_jsonb(o) into v_now from orgs o where o.id = v_org for update;
    if v_now is null then
        raise exception 'Entreprise inconnue';
    end if;
    if exists (select 1 from jsonb_object_keys(v_before) k
                where not k = any (mara_edit_columns(v_what))) then
        raise exception 'Rien à annuler';
    end if;
    foreach v_col in array mara_edit_keys(v_what, v_before) loop
        -- Somebody changed it after Mara: theirs wins, and the undo says so.
        if (v_now -> v_col) is distinct from (v_after -> v_col) then
            raise exception 'Annulation impossible : « % » a été modifié depuis',
                mara_edit_words(array[v_col]);
        end if;
        v_sets := v_sets || format('%I = r.%I', v_col, v_col);
    end loop;
    if v_before ? 'slug' and exists (
        select 1 from orgs where slug = v_before ->> 'slug' and id <> v_org) then
        raise exception 'Annulation impossible : l''ancienne adresse est prise par une autre activité';
    end if;

    perform set_config('mara.logged_write', 'on', true);
    execute format('update orgs o set %s from jsonb_populate_record(null::orgs, $1) r where o.id = $2',
                   array_to_string(v_sets, ', '))
      using v_before, v_org;
    perform set_config('mara.logged_write', '', true);

    if v_what in ('vitrine', 'identity') then
        v_cols := mara_edit_keys(v_what, v_before);
        perform notify_org_owners(v_org, 'mara_undone',
            mara_edit_message(v_what, v_cols, true),
            jsonb_build_object('what', v_what, 'fields', to_jsonb(v_cols)));
    end if;
end;
$$;

-- spend_cauris(uuid,text) — 108_owner_fixes.sql's, the name only.
create or replace function spend_cauris(p_org_id uuid, p_feature text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_cost   cauris_costs%rowtype;
    v_org    orgs%rowtype;
    v_until  timestamptz;
    v_days   int := cauris_param('cauris_unlock_days', 30);
    v_after  int;
    v_opens  date;
    v_today  date := (now() at time zone 'Africa/Ouagadougou')::date;
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur dépense les cauris de l''entreprise';
    end if;
    -- The business moves: a payment that ended under a rule is noticed.
    perform feature_lapse_watch(p_org_id);
    -- No cauris for a tool the platform hid here (104).
    perform feature_guard(p_org_id, c.key) from feature_catalog c where c.pro_tool = p_feature;
    select * into v_cost from cauris_costs where feature = p_feature;
    if not found or p_feature = 'photo_slot' then
        raise exception 'Cet outil ne s''ouvre pas avec des cauris';
    end if;
    select * into v_org from orgs where id = p_org_id;
    -- A tool this kind does not have — the switchboard's catalog says
    -- which kinds have each tool (104: no analyses for an association), and
    -- 099 that an association delivers nothing (110 writes it in the
    -- catalog too) — the app draws neither: its cauris stay its own.
    if exists (select 1 from feature_catalog c
                where c.pro_tool = p_feature
                  and not (org_kind(p_org_id) = any (c.kinds)))
       or (p_feature = 'delivery' and org_kind(p_org_id) = 'association') then
        raise exception 'Cet outil n''existe pas pour votre activité : vos cauris restent à vous.';
    end if;
    -- A paid Mara Pro opens every tool already.
    if v_org.plan = 'pro' and (v_org.plan_until is null or v_org.plan_until >= v_today) then
        raise exception 'Votre entreprise est sur Marakaj Pro : cet outil est déjà ouvert, vos cauris restent à vous.';
    end if;
    if v_cost.min_days > 0 and v_org.created_at > now() - make_interval(days => v_cost.min_days) then
        v_opens := ((v_org.created_at + make_interval(days => v_cost.min_days))
                    at time zone 'Africa/Ouagadougou')::date;
        raise exception 'Disponible avec vos cauris dans % jours, le % : il faut un peu d''activité pour que cet outil serve.',
            greatest(v_opens - v_today, 1), to_char(v_opens, 'DD/MM/YYYY');
    end if;

    v_after := cauris_take(p_org_id, v_cost.cost,
                           p_feature || ':' || gen_random_uuid()::text, p_feature);

    select greatest(coalesce(u.until, now()), now()) + make_interval(days => v_days)
      into v_until
      from (select 1) x left join cauris_unlocks u
        on u.org_id = p_org_id and u.feature = p_feature;

    insert into cauris_unlocks (org_id, feature, until)
    values (p_org_id, p_feature, v_until)
    on conflict (org_id, feature) do update
        set until = excluded.until, updated_at = now(), note = null, gifted_by = null;

    return jsonb_build_object('feature', p_feature, 'until', v_until,
                              'balance', v_after);
end;
$$;

-- business_address_check(text) — 111_create_my_business.sql's, the name only.
create or replace function business_address_check(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_slug    text := lower(btrim(coalesce(p_slug, '')));
    v_problem text;
    v_taken   boolean := false;
    v_free    text;
    v_try     text;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous pour créer votre activité.';
    end if;
    v_problem := org_slug_problem(v_slug);
    if v_problem is null and business_address_reserved(v_slug) then
        v_problem := 'Cette adresse est réservée à Marakaj : choisissez-en une autre.';
    end if;
    if v_problem is null then
        v_taken := exists (select 1 from orgs where slug = v_slug);
        if v_taken then
            for i in 2..20 loop
                v_try := left(v_slug, 60) || '-' || i;
                if not exists (select 1 from orgs where slug = v_try) then
                    v_free := v_try;
                    exit;
                end if;
            end loop;
        end if;
    end if;
    return jsonb_build_object('slug', v_slug, 'problem', v_problem,
                              'taken', v_taken, 'suggestion', v_free);
end;
$$;

-- create_my_business(text,text,text,text,text,text,text,text,text,jsonb) — 111_create_my_business.sql's, the name only.
create or replace function create_my_business(
    p_profile  text,
    p_name     text,
    p_slug     text,
    p_activity text  default null,
    p_about    text  default null,
    p_city     text  default null,
    p_area     text  default null,
    p_phone    text  default null,
    p_currency text  default 'XOF',
    p_answers  jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_profile  text := lower(btrim(coalesce(p_profile, '')));
    v_name     text := nullif(btrim(coalesce(p_name, '')), '');
    v_slug     text := lower(btrim(coalesce(p_slug, '')));
    v_activity text := nullif(lower(btrim(coalesce(p_activity, ''))), '');
    v_about    text := nullif(btrim(coalesce(p_about, '')), '');
    v_city     text := nullif(btrim(coalesce(p_city, '')), '');
    v_area     text := nullif(btrim(coalesce(p_area, '')), '');
    v_phone    text := nullif(regexp_replace(coalesce(p_phone, ''), '[\s().-]', '', 'g'), '');
    v_currency text := upper(coalesce(nullif(btrim(coalesce(p_currency, '')), ''), 'XOF'));
    v_proved   text;
    v_form     jsonb := application_form();
    v_answers  jsonb;
    v_problem  text;
    v_org      uuid;
    v_full     text;
    v_cphone   text;
    v_email    text;
begin
    if v_actor is null then
        raise exception 'Connectez-vous pour créer votre activité.';
    end if;

    -- The platform's switch: a number proved on WhatsApp first.
    v_proved := my_verified_phone();
    if create_phone_required() and v_proved is null then
        raise exception 'Vérifiez d''abord votre numéro WhatsApp';
    end if;

    if v_profile = 'church' then
        v_profile := 'association';
    end if;
    if v_profile not in ('retail', 'farm', 'association') then
        raise exception 'Choisissez boutique, ferme ou association.';
    end if;
    -- The kinds the creation page offers (107's form).
    if v_form is not null and jsonb_typeof(v_form -> 'kinds') = 'array'
       and not ((v_form -> 'kinds') ? v_profile) then
        raise exception 'Ce type d''activité ne peut pas être créé pour l''instant.';
    end if;

    if v_name is null then
        raise exception 'Le nom de votre activité, s''il vous plaît.';
    end if;
    if char_length(v_name) > 80 then
        raise exception 'Un nom de 80 caractères au plus.';
    end if;

    v_problem := org_slug_problem(v_slug);
    if v_problem is not null then
        raise exception '%', v_problem;
    end if;
    if business_address_reserved(v_slug) then
        raise exception 'Cette adresse est réservée à Marakaj : choisissez-en une autre.';
    end if;

    if v_activity is null then
        raise exception 'Dites ce que fait votre activité.';
    end if;
    if not v_activity = any (business_activities(v_profile)) then
        raise exception 'Choisissez ce que fait votre activité dans la liste.';
    end if;
    -- The vitrine's sentence, as the setup and the settings keep it (80).
    if char_length(coalesce(v_about, '')) > 80 then
        raise exception 'Une phrase de 80 caractères au plus.';
    end if;

    if v_city is null then
        raise exception 'La ville, s''il vous plaît.';
    end if;
    if char_length(v_city) > 60 or char_length(coalesce(v_area, '')) > 80 then
        raise exception 'La ville fait 60 caractères au plus, le quartier 80.';
    end if;

    -- The business's phone: the one typed, else the proved one.
    v_phone := coalesce(v_phone, v_proved);
    if v_phone is null then
        raise exception 'Le numéro de votre activité, s''il vous plaît.';
    end if;
    if left(v_phone, 2) = '00' then
        v_phone := '+' || substr(v_phone, 3);
    end if;
    if v_phone !~ '^\+[1-9][0-9]{7,14}$' then
        raise exception 'Ce numéro n''est pas valide : l''indicatif du pays, puis le numéro.';
    end if;

    if v_currency !~ '^[A-Z]{3}$' then
        raise exception 'Une monnaie s''écrit en trois lettres (XOF, GHS…).';
    end if;

    -- The page's questions, as 107 checks a request's.
    v_answers := business_answers(v_form, p_answers);

    -- One person, one creation at a time: two taps cannot both pass the
    -- rule below.
    perform pg_advisory_xact_lock(hashtext('create_my_business:' || v_actor::text));

    -- Three a day at most, whatever the plan: a loop of creations is not a
    -- person starting a business. Counted in the journal, which keeps the
    -- line even when the business is deleted afterwards.
    if (select count(*) from platform_actions
         where actor = v_actor and kind = 'business_created'
           and at > now() - interval '24 hours') >= 3 then
        raise exception 'Vous avez déjà créé 3 activités en 24 heures : c''est le maximum, réessayez demain.';
    end if;

    -- One free business per person; a second needs Mara Pro (099).
    if second_business_locked(v_actor) then
        raise exception '%', path_lock_message('second_business');
    end if;

    if exists (select 1 from orgs where slug = v_slug) then
        raise exception 'Cette adresse est déjà prise : choisissez-en une autre.';
    end if;

    begin
        v_org := org_create_core(v_actor, v_name, v_slug, v_profile, v_currency);
    exception when unique_violation then
        raise exception 'Cette adresse vient d''être prise : choisissez-en une autre.';
    end;

    -- Where the business keeps what it said: the setup and the vitrine
    -- start from it (102's kind and sentence for an association).
    update orgs
       set city             = v_city,
           address          = v_area,
           phone            = v_phone,
           storefront_blurb = v_about,
           association_kind = case when v_profile = 'association' then v_activity
                                   else association_kind end
     where id = v_org;

    select coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                    nullif(btrim(coalesce(p.full_name, '')), ''),
                    nullif(btrim(coalesce(u.raw_user_meta_data ->> 'full_name', '')), '')),
           coalesce(nullif(btrim(coalesce(p.phone, '')), ''),
                    nullif(btrim(coalesce(u.phone, '')), '')),
           nullif(btrim(coalesce(u.email, '')), '')
      into v_full, v_cphone, v_email
      from auth.users u
      left join profiles p on p.id = u.id
     where u.id = v_actor;

    insert into business_creations (org_id, created_by, activity, about, city, area, phone,
                                    answers, contact_name, contact_phone, contact_email)
    values (v_org, v_actor, v_activity, v_about, v_city, v_area, v_phone,
            v_answers, v_full, v_cphone, v_email);

    -- A request still waiting from an older app is what this became: it
    -- is closed with the business, so it can never be approved into a
    -- second one.
    update org_applications
       set status        = 'approved',
           name          = v_name,
           slug          = v_slug,
           profile       = v_profile,
           org_id        = v_org,
           reviewed_at   = now(),
           decision_note = 'Créée directement par la personne'
     where applicant_id = v_actor and status = 'pending';

    -- The platform's journal: who created what. Nothing to undo — the
    -- business is the person's; Mara archives it from its fiche if needed.
    insert into platform_actions (at, actor, org_id, kind, summary, before, after)
    values (clock_timestamp(), v_actor, v_org, 'business_created',
            'Activité créée : ' || v_name || ' (' || v_slug || ') — '
                || case v_profile when 'retail' then 'boutique'
                                  when 'farm' then 'ferme'
                                  else 'association' end
                || ', ' || v_city,
            null,
            jsonb_build_object('name', v_name, 'slug', v_slug, 'profile', v_profile,
                               'activity', v_activity, 'city', v_city, 'area', v_area,
                               'phone', v_phone, 'currency', v_currency,
                               'answers', coalesce(v_answers, '[]'::jsonb)));

    return v_org;
end;
$$;

-- platform_decide_courier_application(uuid,text,text,text[],text) — 112_courier_application.sql's, the name only.
create or replace function platform_decide_courier_application(
    p_user_id  uuid,
    p_decision text,
    p_reason   text   default null,
    p_steps    text[] default null,
    p_note     text   default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_app     courier_applications%rowtype;
    v_now     timestamptz := clock_timestamp();
    v_courier text;
    v_reason  text;
    v_steps   text[];
    v_note    text := nullif(btrim(coalesce(p_note, '')), '');
    v_name    text;
    v_status  text;
    v_message text;
    v_kind    text;
begin
    perform platform_only();
    select * into v_app from courier_applications where user_id = p_user_id for update;
    if not found then
        raise exception 'Aucune demande de livreur pour cette personne';
    end if;
    if v_app.status <> 'pending' then
        raise exception 'Cette demande n''attend pas de décision';
    end if;
    if length(v_note) > 300 then
        raise exception 'Un mot de 300 caractères au plus';
    end if;
    v_name := courier_person_name(p_user_id);
    select status into v_courier from couriers where user_id = p_user_id;

    if p_decision = 'approve' then
        if v_courier = 'suspended' then
            raise exception 'Ce livreur est suspendu';
        end if;
        v_status := 'approved';
        update courier_applications
           set status = 'approved', decided_at = v_now, decided_by = auth.uid(),
               refusal_reason = null, refusal_note = null, reopened = '{}',
               timeline = timeline || jsonb_build_array(jsonb_build_object('at', v_now, 'kind', 'approved')),
               updated_at = now()
         where user_id = p_user_id;
        insert into couriers (user_id, phone, status, decided_at)
        values (p_user_id, v_app.phone, 'approved', v_now)
        on conflict (user_id) do update
           set status = 'approved', decided_at = v_now,
               phone = coalesce(excluded.phone, couriers.phone);
        v_kind := 'courier_approved';
        v_message := 'Vous êtes livreur Marakaj : les livraisons vous attendent.';

    elsif p_decision in ('refuse', 'new_photo') then
        if p_decision = 'new_photo' then
            if p_reason not in ('selfie', 'id') then
                raise exception 'Quelle photo ? Le selfie ou la pièce d''identité';
            end if;
            v_reason := 'new_' || p_reason;
            v_steps := array[p_reason];
            v_kind := 'courier_photo';
            v_message := 'Marakaj demande une nouvelle photo '
                         || case p_reason when 'selfie' then 'de votre selfie.'
                                          else 'de votre pièce d''identité.' end;
        else
            if p_reason is null or p_reason not in ('blurry', 'unreadable', 'face', 'missing', 'other') then
                raise exception 'Choisissez une raison';
            end if;
            if p_reason = 'other' and v_note is null then
                raise exception 'Dites en un mot ce qui ne va pas';
            end if;
            v_reason := p_reason;
            select coalesce(array_agg(distinct s), '{}') into v_steps
              from unnest(coalesce(p_steps, '{}')) s;
            if cardinality(v_steps) = 0 then
                raise exception 'Choisissez l''étape à corriger';
            end if;
            if exists (select 1 from unnest(v_steps) s
                        where s not in ('zone', 'hours', 'vehicle', 'selfie', 'id', 'phone')) then
                raise exception 'Étape inconnue';
            end if;
            v_kind := 'courier_refused';
            v_message := 'Votre demande de livreur est à corriger : '
                         || courier_reason_label(v_reason) || '.'
                         || coalesce(' ' || v_note, '');
        end if;
        v_status := 'refused';
        update courier_applications
           set status = 'refused', decided_at = v_now, decided_by = auth.uid(),
               refusal_reason = v_reason, refusal_note = v_note, reopened = v_steps,
               timeline = timeline || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
                   'at', v_now, 'kind', case when p_decision = 'new_photo' then 'photo' else 'refused' end,
                   'reason', v_reason, 'note', v_note, 'steps', to_jsonb(v_steps)))),
               updated_at = now()
         where user_id = p_user_id;
        -- Back with the applicant: no longer the platform's to validate.
        delete from couriers where user_id = p_user_id and status = 'pending';
    else
        raise exception 'Décision inconnue';
    end if;

    begin
        insert into notifications (recipient_id, org_id, kind, message, params)
        values (p_user_id, null, v_kind, v_message,
                jsonb_strip_nulls(jsonb_build_object('to', 'courier', 'status', v_status,
                    'reason', v_reason, 'note', v_note, 'steps', to_jsonb(v_steps))));
    exception when others then
        null;
    end;

    return platform_log_action(
        null, 'courier',
        'Livreur ' || v_name || ' : '
            || case when v_status = 'approved' then 'approuvé'
                    else 'à corriger (' || courier_reason_label(v_reason) || ')' end,
        jsonb_build_object('user_id', p_user_id, 'name', v_name, 'status', 'pending'),
        jsonb_strip_nulls(jsonb_build_object('user_id', p_user_id, 'name', v_name,
            'status', v_status, 'reason', v_reason, 'steps', to_jsonb(v_steps))),
        'platform_undo_courier_decision',
        jsonb_build_object('user_id', p_user_id, 'status', v_status, 'decided_at', v_now));
end;
$$;

-- trg_notify_courier_received() — 115_notifications.sql's, the name only.
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
                'Votre demande de livreur est bien arrivée : Marakaj l''examine et vous répond ici.',
                jsonb_build_object('to', 'courier', 'status', 'pending'));
    end if;
    return new;
exception when others then
    return new;
end;
$$;

-- delete_my_account_check() — 113_shopper_profile.sql's, the name only.
create or replace function delete_my_account_check()
returns uuid
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_me   uuid := auth.uid();
    v_held boolean;
    r      record;
begin
    if v_me is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    if exists (select 1 from profiles where id = v_me and is_platform_admin) then
        raise exception 'Un compte de la plateforme ne se supprime pas ici.';
    end if;
    if exists (select 1 from memberships where user_id = v_me) then
        raise exception 'Vous faites partie d''une activité sur Marakaj : votre compte se supprime une fois que vous n''en faites plus partie.';
    end if;
    if exists (select 1 from couriers where user_id = v_me)
       or exists (select 1 from orders where courier_id = v_me) then
        raise exception 'Vous êtes livreur sur Marakaj : écrivez à Marakaj pour fermer votre compte livreur.';
    end if;
    if exists (select 1 from orders where customer_id = v_me
                 and status in ('pending', 'accepted', 'ready', 'in_transit')) then
        raise exception 'Une commande est en cours : attendez qu''elle soit terminée, ou annulez-la, puis supprimez votre compte.';
    end if;
    for r in
        select c.conrelid::regclass as tbl, a.attname as col
          from pg_constraint c
          join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
         where c.contype = 'f'
           and c.confrelid = 'public.profiles'::regclass
           and c.confdeltype in ('a', 'r')
           and cardinality(c.conkey) = 1
         order by 1, 2
    loop
        execute format('select exists (select 1 from %s where %I = $1)', r.tbl, r.col)
           into v_held using v_me;
        if v_held then
            raise exception 'Votre nom reste sur ce que vous avez inscrit pour une activité sur Marakaj (ventes, stock, factures…) : écrivez à Marakaj pour fermer votre compte.';
        end if;
    end loop;
    return v_me;
end;
$$;

-- report_problem(text,text,text,uuid) — 113_shopper_profile.sql's, the name only.
create or replace function report_problem(
    p_topic    text,
    p_message  text,
    p_slug     text default null,
    p_order_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_me      uuid := auth.uid();
    v_message text := btrim(coalesce(p_message, ''));
    v_org     uuid;
    v_id      uuid;
begin
    if v_me is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    if p_topic is null or p_topic not in ('order', 'vitrine', 'payment', 'delivery', 'app', 'other') then
        raise exception 'Choisissez de quoi il s''agit.';
    end if;
    if char_length(v_message) < 10 then
        raise exception 'Dites en quelques mots ce qui ne va pas (10 caractères au moins).';
    end if;
    if char_length(v_message) > 1000 then
        raise exception 'Un message de 1 000 caractères au plus.';
    end if;
    if (select count(*) from problem_reports
         where reporter_id = v_me and created_at > now() - interval '24 hours') >= 5 then
        raise exception 'Vous avez déjà envoyé 5 signalements aujourd''hui : Marakaj les lit et vous répond.';
    end if;
    if p_order_id is not null then
        select org_id into v_org from orders where id = p_order_id and customer_id = v_me;
        if not found then
            raise exception 'Commande introuvable.';
        end if;
    elsif nullif(btrim(coalesce(p_slug, '')), '') is not null then
        select id into v_org from orgs where slug = lower(btrim(p_slug));
    end if;
    insert into problem_reports (reporter_id, topic, message, org_id, order_id, contact)
    values (v_me, p_topic, v_message, v_org, p_order_id,
            coalesce(my_verified_phone(),
                     (select nullif(btrim(coalesce(phone, '')), '') from profiles where id = v_me),
                     (select email from auth.users where id = v_me)))
    returning id into v_id;
    return v_id;
end;
$$;

-- platform_handle_report(uuid,text) — 113_shopper_profile.sql's, the name only.
create or replace function platform_handle_report(p_id uuid, p_answer text default null)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_r      problem_reports%rowtype;
    v_answer text := nullif(btrim(coalesce(p_answer, '')), '');
begin
    perform platform_only();
    if char_length(v_answer) > 500 then
        raise exception 'Une réponse de 500 caractères au plus.';
    end if;
    select * into v_r from problem_reports where id = p_id for update;
    if not found then
        raise exception 'Signalement introuvable.';
    end if;
    if v_r.status = 'handled' then
        raise exception 'Ce signalement est déjà traité.';
    end if;
    update problem_reports
       set status = 'handled', handled_at = now(), handled_by = auth.uid(), answer = v_answer
     where id = p_id;
    begin
        insert into notifications (recipient_id, org_id, kind, message, params)
        values (v_r.reporter_id, null, 'report_handled',
                case when v_answer is null then 'Marakaj a traité votre signalement. Merci !'
                     else 'Marakaj a traité votre signalement : ' || v_answer end,
                -- The facts (099): the app says it in the reader's language.
                jsonb_build_object('to', 'customer', 'answer', v_answer));
    exception when others then
        null;
    end;
    return platform_log_action(
        v_r.org_id, 'report',
        'Signalement traité : ' || left(v_r.message, 80),
        jsonb_build_object('status', 'open'),
        jsonb_build_object('status', 'handled', 'answer', v_answer),
        'platform_undo_report',
        jsonb_build_object('id', p_id));
end;
$$;

-- send_test_notification() — 115_notifications.sql's, the name only.
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
            'Marakaj : ceci est une notification test. Si elle s''affiche sur votre téléphone, tout marche.',
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

-- help_request_create(uuid,text,text,text,text,uuid,jsonb) — 138_help_basic_pro.sql's, the name only.
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
        raise exception 'L''aide d''un formateur vient avec Marakaj Pro.';
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
        raise exception 'Les demandes d''aide de ces 24 heures sont toutes faites. Réessayez demain, ou écrivez à Marakaj.';
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

-- store_verify_begin(uuid) — 128_store_billing.sql's, the name only.
create or replace function store_verify_begin(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'store_verify_begin() needs a signed-in caller';
    end if;
    if p_org_id is null or not exists (select 1 from orgs where id = p_org_id
                                                          and archived_at is null) then
        raise exception 'Entreprise introuvable';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur abonne l''entreprise à Marakaj Pro';
    end if;
    return jsonb_build_object('org_id', p_org_id, 'user_id', auth.uid(),
                              'store_billing_on', store_billing_on());
end;
$$;

-- store_settle(text,uuid,text,text,text,timestamp with time zone,boolean,text,jsonb,uuid,text,timestamp with time zone) — 130_audit_fixes.sql's, the name only.
create or replace function store_settle(
    p_platform    text,
    p_org_id      uuid,
    p_product_id  text,
    p_original_id text,
    p_state       text,
    p_expires_at  timestamptz,
    p_auto_renew  boolean,
    p_environment text,
    p_raw         jsonb default null,
    p_bought_by   uuid default null,
    p_replaces    text default null,
    p_signed_at   timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_row   store_subscriptions%rowtype;
    v_found boolean;
    v_was   boolean;
    v_now   boolean;
    v_fresh boolean;
begin
    if p_platform not in ('apple', 'google') then
        return jsonb_build_object('ok', false, 'reason', 'unknown store');
    end if;
    if coalesce(p_original_id, '') = '' or coalesce(p_product_id, '') = '' then
        return jsonb_build_object('ok', false, 'reason', 'no purchase');
    end if;
    if not exists (select 1 from orgs where id = p_org_id) then
        return jsonb_build_object('ok', false, 'reason', 'no such business');
    end if;
    select * into v_row from store_subscriptions
     where platform = p_platform and original_id = p_original_id
       for update;
    v_found := found;
    if v_found and v_row.org_id <> p_org_id then
        -- A purchase is the business it was bought for.
        return jsonb_build_object('ok', false, 'reason', 'another business');
    end if;
    -- 5c: a test purchase, for Mara's own businesses and App Review's only.
    if p_environment = 'sandbox' and not store_sandbox_allowed(p_org_id) then
        return jsonb_build_object('ok', false, 'reason', 'sandbox');
    end if;
    -- 5b: older news than what is held changes nothing (a notification
    -- retried after a refund, two answers crossing).
    if v_found and v_row.signed_at is not null and p_signed_at is not null
       and p_signed_at < v_row.signed_at then
        return jsonb_build_object('ok', true, 'stale', true,
                                  'pro', org_plan(p_org_id) = 'pro',
                                  'state', v_row.state, 'expires_at', v_row.expires_at);
    end if;
    v_was := store_pro_active(p_org_id) or org_plan(p_org_id) = 'pro';
    -- 130: is this a new subscription, or the same one renewing? A renewal
    -- whose news lands a little after the paid end finds the plan briefly
    -- free (v_was false), and rang « Mara Pro est actif » once a period.
    --   new: this original id never seen (Apple keeps one originalTransactionId
    --        through every renewal; Google one token) — unless, on Google,
    --        it replaces (linkedPurchaseToken) a subscription of this
    --        business that was running in the last 24 hours: an upgrade or
    --        a re-buy, not news;
    --   or a true re-subscription: the subscription held had lapsed more
    --        than 24 hours ago (its paid end, or for a refund the moment it
    --        was written).
    v_fresh := case
        when not v_found then
            p_platform <> 'google' or p_replaces is null or p_replaces = p_original_id
            or not exists (select 1 from store_subscriptions r
                            where r.platform = p_platform and r.original_id = p_replaces
                              and r.org_id = p_org_id
                              and (r.state in ('active', 'grace', 'on_hold', 'paused', 'pending')
                                   or (r.state <> 'revoked' and r.expires_at > now() - interval '24 hours')
                                   or (r.state = 'revoked' and r.last_verified_at > now() - interval '24 hours')))
        else
            case when v_row.state = 'revoked' then v_row.last_verified_at
                 else v_row.expires_at end < now() - interval '24 hours'
    end;

    insert into store_subscriptions (org_id, platform, product_id, original_id, state,
                                     expires_at, auto_renew, environment, bought_by,
                                     last_verified_at, signed_at, raw)
    values (p_org_id, p_platform, p_product_id, p_original_id, p_state,
            p_expires_at, coalesce(p_auto_renew, false),
            case when p_environment = 'sandbox' then 'sandbox' else 'production' end,
            p_bought_by, now(), p_signed_at, p_raw)
    on conflict (platform, original_id) do update set
        product_id       = excluded.product_id,
        state            = excluded.state,
        expires_at       = excluded.expires_at,
        auto_renew       = excluded.auto_renew,
        environment      = excluded.environment,
        bought_by        = coalesce(store_subscriptions.bought_by, excluded.bought_by),
        last_verified_at = now(),
        signed_at        = coalesce(excluded.signed_at, store_subscriptions.signed_at),
        raw              = excluded.raw;

    -- Google: an upgrade or a re-subscription is a new token naming the old
    -- one (linkedPurchaseToken); the old one is over.
    if p_replaces is not null and p_replaces <> p_original_id then
        update store_subscriptions
           set state = 'expired', last_verified_at = now()
         where platform = p_platform and original_id = p_replaces and org_id = p_org_id
           and state not in ('expired', 'revoked');
    end if;

    v_now := org_plan(p_org_id) = 'pro';
    if v_now and not v_was and coalesce(v_fresh, false) then
        begin
            perform notify_org_admins(p_org_id, 'pro_active',
                case when p_platform = 'apple'
                     then 'Marakaj Pro est actif, payé sur l''App Store, jusqu''au '
                     else 'Marakaj Pro est actif, payé sur Google Play, jusqu''au ' end
                || to_char((p_expires_at at time zone 'Africa/Ouagadougou')::date, 'DD/MM/YYYY') || '.',
                jsonb_build_object('to', 'shop', 'store', p_platform,
                                   'until', (p_expires_at at time zone 'Africa/Ouagadougou')::date));
        exception when others then null;
        end;
    end if;
    return jsonb_build_object('ok', true, 'pro', v_now, 'state', p_state,
                              'expires_at', p_expires_at);
end;
$$;

-- delete_my_account_plan(uuid) — 128_store_billing.sql's, the name only.
create or replace function delete_my_account_plan(p_me uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_blocked    text;
    v_code       text;
    v_shop       text;
    v_businesses jsonb;
    v_leaves     jsonb;
    v_name       text;
begin
    if p_me is null then
        return jsonb_build_object('blocked', 'Connectez-vous d''abord', 'blocked_code', 'signed_out');
    end if;

    -- The businesses that disappear: those the person is the only owner of.
    select coalesce(jsonb_agg(jsonb_build_object(
               'id', o.id, 'name', o.name, 'profile', o.profile,
               'members', (select count(*) from memberships x
                            where x.org_id = o.id and x.user_id <> p_me),
               'orders', (select count(*) from orders d
                           where d.org_id = o.id and d.status in ('pending', 'accepted', 'ready')),
               'store', coalesce((select jsonb_agg(jsonb_build_object('platform', s.platform,
                                     'state', s.state, 'auto_renew', s.auto_renew,
                                     'expires_at', s.expires_at))
                           from store_subscriptions s
                          where s.org_id = o.id
                            and s.state in ('active', 'grace', 'cancelled', 'on_hold', 'paused', 'pending')
                            and (s.expires_at is null or s.expires_at > now())), '[]'::jsonb),
               'stripe', exists (select 1 from stripe_subscriptions t
                                  where t.org_id = o.id and t.subscription_id is not null
                                    and t.status in ('active', 'trialing', 'past_due', 'unpaid', 'incomplete')))
               order by o.name), '[]'::jsonb)
      into v_businesses
      from orgs o
     where exists (select 1 from memberships m
                    where m.org_id = o.id and m.user_id = p_me and m.role = 'owner')
       and not exists (select 1 from memberships m
                        where m.org_id = o.id and m.user_id <> p_me and m.role = 'owner');

    -- The businesses the person only leaves.
    select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name) order by o.name), '[]'::jsonb)
      into v_leaves
      from orgs o
     where exists (select 1 from memberships m where m.org_id = o.id and m.user_id = p_me)
       and o.id not in (select (b ->> 'id')::uuid from jsonb_array_elements(v_businesses) b);

    -- Each refusal has a code (the app says it in the reader's language)
    -- and, where it names one, the business (blocked_shop).
    if exists (select 1 from profiles where id = p_me and is_platform_admin) then
        v_code := 'platform';
        v_blocked := 'Un compte de la plateforme ne se supprime pas ici.';
    elsif exists (select 1 from orders where customer_id = p_me
                    and status in ('pending', 'accepted', 'ready', 'in_transit')) then
        v_code := 'own_order';
        v_blocked := 'Une commande est en cours : attendez qu''elle soit terminée, ou annulez-la, puis supprimez votre compte.';
    elsif exists (select 1 from orders where courier_id = p_me and status in ('ready', 'in_transit')) then
        v_code := 'delivering';
        v_blocked := 'Une livraison est en cours : terminez-la, puis supprimez votre compte.';
    else
        select o.name into v_name
          from orders d join orgs o on o.id = d.org_id
         where d.org_id in (select (b ->> 'id')::uuid from jsonb_array_elements(v_businesses) b)
           and (d.status = 'in_transit'
                or (d.status in ('pending', 'accepted', 'ready')
                    and d.payment_method = 'wave' and d.paid_at is not null))
         order by o.name
         limit 1;
        if v_name is not null then
            v_code := 'business_order';
            v_shop := v_name;
            v_blocked := format('Une commande de « %s » est en route ou déjà payée en ligne : livrez-la ou remboursez-la, puis supprimez votre compte.', v_name);
        else
            -- S5: money Mara still owes the business (a Wave payout
            -- pending, or failed and to be retried) is never lost with it.
            select o.name into v_name
              from wave_payments w join orgs o on o.id = w.org_id
             where w.org_id in (select (b ->> 'id')::uuid from jsonb_array_elements(v_businesses) b)
               and w.payout_status in ('pending', 'failed')
             order by o.name
             limit 1;
            if v_name is not null then
                v_code := 'payout';
                v_shop := v_name;
                v_blocked := format('Marakaj doit encore verser à « %s » l''argent d''une commande payée par Wave (versement en attente ou en échec) : attendez qu''il arrive, ou écrivez à l''aide Marakaj, puis supprimez votre compte.', v_name);
            end if;
        end if;
    end if;

    return jsonb_build_object(
        'blocked',      v_blocked,
        'blocked_code', v_code,
        'blocked_shop', v_shop,
        'businesses',   v_businesses,
        'leaves',       v_leaves,
        'courier',      exists (select 1 from couriers where user_id = p_me),
        'apple_store',  (select count(*) from jsonb_array_elements(v_businesses) b,
                                jsonb_array_elements(b -> 'store') s
                          where s ->> 'platform' = 'apple' and (s ->> 'auto_renew')::boolean));
end;
$$;

-- delete_my_account_stops(uuid,uuid[]) — 128_store_billing.sql's, the name only.
create or replace function delete_my_account_stops(p_me uuid, p_confirmed_orgs uuid[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_plan    jsonb;
    v_doomed  uuid[];
    v_names   text[];
    v_google  jsonb;
    v_stripe  jsonb;
begin
    if p_me is null or not exists (select 1 from profiles where id = p_me) then
        raise exception 'Connectez-vous d''abord';
    end if;
    v_plan := delete_my_account_plan(p_me);
    if v_plan ->> 'blocked' is not null then
        raise exception '%', v_plan ->> 'blocked'
            using detail = coalesce(v_plan ->> 'blocked_code', ''),
                  hint = coalesce(v_plan ->> 'blocked_shop', '');
    end if;
    select coalesce(array_agg((b ->> 'id')::uuid order by (b ->> 'id')), '{}'),
           coalesce(array_agg(b ->> 'name' order by b ->> 'name'), '{}')
      into v_doomed, v_names
      from jsonb_array_elements(v_plan -> 'businesses') b;
    if cardinality(v_doomed) > 0 then
        if p_confirmed_orgs is null then
            raise exception 'Mettez Marakaj à jour : la suppression d''un compte qui tient une activité se confirme dans la dernière version de l''application.'
                using detail = 'old_app';
        end if;
        if (select coalesce(array_agg(distinct x order by x), '{}') from unnest(p_confirmed_orgs) x)
           is distinct from v_doomed then
            raise exception 'La liste de vos activités a changé : relisez-la avant de supprimer votre compte.'
                using detail = 'list_changed';
        end if;
    end if;

    select coalesce(jsonb_agg(jsonb_build_object('token', s.original_id, 'org_id', o.id, 'org', o.name)
                              order by s.original_id), '[]'::jsonb)
      into v_google
      from store_subscriptions s join orgs o on o.id = s.org_id
     where s.org_id = any (v_doomed) and s.platform = 'google'
       and s.state in ('active', 'grace', 'cancelled', 'on_hold', 'paused', 'pending');
    select coalesce(jsonb_agg(jsonb_build_object('id', t.subscription_id, 'org_id', o.id, 'org', o.name)
                              order by t.subscription_id), '[]'::jsonb)
      into v_stripe
      from stripe_subscriptions t join orgs o on o.id = t.org_id
     where t.org_id = any (v_doomed) and t.subscription_id is not null
       and t.status in ('active', 'trialing', 'past_due', 'unpaid', 'incomplete');

    return jsonb_build_object(
        'user_id',     p_me,
        'orgs',        to_jsonb(v_doomed),
        'businesses',  to_jsonb(v_names),
        'google',      v_google,
        'stripe',      v_stripe,
        'apple_store', coalesce((v_plan ->> 'apple_store')::int, 0));
end;
$$;

-- delete_my_account(uuid,uuid[],jsonb) — 128_store_billing.sql's, the name only.
create or replace function delete_my_account(
    p_me             uuid,
    p_confirmed_orgs uuid[] default null,
    p_stopped        jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_stops   jsonb;
    v_doomed  uuid[];
    v_mode    text := 'hard';
    v_held    boolean;
    v_left    text;
    r         record;
    v_o       record;
begin
    -- Its refusals, the list check, and what had to be stopped — again,
    -- now, under the deletion's own transaction.
    v_stops := delete_my_account_stops(p_me, p_confirmed_orgs);
    select coalesce(array_agg(x::uuid), '{}') into v_doomed
      from jsonb_array_elements_text(v_stops -> 'orgs') x;

    -- Every subscription still running on a business that goes was
    -- stopped by the Worker (one started since step 1 refuses it all).
    select string_agg(g ->> 'org', ', ') into v_left
      from jsonb_array_elements(v_stops -> 'google') g
     where not coalesce(p_stopped -> 'google', '[]'::jsonb) ? (g ->> 'token');
    if v_left is null then
        select string_agg(t ->> 'org', ', ') into v_left
          from jsonb_array_elements(v_stops -> 'stripe') t
         where not coalesce(p_stopped -> 'stripe', '[]'::jsonb) ? (t ->> 'id');
    end if;
    if v_left is not null then
        raise exception 'Nous n''avons pas pu arrêter l''abonnement de « % » : rien n''a été supprimé. Réessayez dans un moment ou écrivez à l''aide.', v_left
            using detail = 'not_stopped';
    end if;

    insert into account_deletion_log (user_id, stage, businesses, stopped)
    values (p_me, 'deleted', v_stops -> 'businesses',
            jsonb_build_object('google', v_stops -> 'google', 'stripe', v_stops -> 'stripe',
                               'apple_store', v_stops -> 'apple_store'));

    -- Each business the person alone owns: its customers and members told
    -- on their own bell (no business: the notice outlives it), then
    -- archived and purged — 014's lifecycle, in one transaction.
    for v_o in select * from orgs where id = any (v_doomed) loop
        insert into notifications (recipient_id, org_id, kind, message, params)
        select distinct d.customer_id, null::uuid, 'order_cancelled',
               format('Votre commande chez %s est annulée : l''activité a fermé sur Marakaj.', v_o.name),
               jsonb_build_object('to', 'customer', 'status', 'cancelled', 'shop', v_o.name,
                                  'booking', d.booked_for is not null)
          from orders d
         where d.org_id = v_o.id and d.status in ('pending', 'accepted', 'ready')
           and d.customer_id is not null and d.customer_id <> p_me;
        insert into notifications (recipient_id, org_id, kind, message, params)
        select distinct m.user_id, null::uuid, 'org_closed',
               format('« %s » a fermé sur Marakaj : vous n''en faites plus partie. Votre compte reste le vôtre.', v_o.name),
               jsonb_build_object('to', 'me', 'shop', v_o.name)
          from memberships m
         where m.org_id = v_o.id and m.user_id <> p_me;
        update orgs set archived_at = coalesce(archived_at, now()),
                        archived_by = coalesce(archived_by, p_me)
         where id = v_o.id;
        perform purge_org(v_o.id, p_me, 'Compte du propriétaire supprimé');
    end loop;

    -- The person: what GoTrue's delete cascades, done as it does it — with
    -- no caller (the triggers that guard a member's removal by somebody
    -- else stand aside, as for GoTrue).
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{}', true);

    update orders
       set customer_name = 'Client supprimé', phone = null, address = null,
           drop_lat = null, drop_lng = null
     where customer_id = p_me;

    -- One statement per foreign key to profiles, each on its own column
    -- (not every one is indexed: a full scan per key, fine at Mara's size;
    -- an index belongs beside any of these tables that grows large).
    for r in
        select c.conrelid::regclass as tbl, a.attname as col, c.confdeltype as act,
               not a.attnotnull as nullable
          from pg_constraint c
          join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
         where c.contype = 'f'
           and c.confrelid = 'public.profiles'::regclass
           and cardinality(c.conkey) = 1
         order by 1, 2
    loop
        begin
            if r.act = 'c' then
                execute format('delete from %s where %I = $1', r.tbl, r.col) using p_me;
            elsif r.act = 'n' or (r.act in ('a', 'r') and r.nullable) then
                execute format('update %s set %I = null where %I = $1', r.tbl, r.col, r.col) using p_me;
            end if;
        exception when others then
            -- Left as it is: the row then holds the account (soft below).
            raise notice 'delete_my_account: %.% kept (%)', r.tbl, r.col, sqlerrm;
        end;
    end loop;

    update profiles
       set full_name = 'Compte supprimé', first_name = null, middle_name = null,
           last_name = null, phone = null, date_of_birth = null, title = null,
           profile_completed_at = null, preferred_locale = 'fr'
     where id = p_me;

    -- Whatever still names the person is the businesses' books (NOT NULL
    -- « written by »): the account stays as an empty shell.
    for r in
        select c.conrelid::regclass as tbl, a.attname as col
          from pg_constraint c
          join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
         where c.contype = 'f'
           and c.confrelid = 'public.profiles'::regclass
           and c.confdeltype in ('a', 'r')
           and cardinality(c.conkey) = 1
    loop
        execute format('select exists (select 1 from %s where %I = $1)', r.tbl, r.col)
           into v_held using p_me;
        if v_held then
            v_mode := 'soft';
            exit;
        end if;
    end loop;

    return jsonb_build_object(
        'user_id',     p_me,
        'mode',        v_mode,
        'businesses',  v_stops -> 'businesses',
        'google',      v_stops -> 'google',
        'stripe',      v_stops -> 'stripe',
        'apple_store', coalesce((v_stops ->> 'apple_store')::int, 0));
end;
$$;

-- help_set_on_duty(boolean) — 133_help_requests.sql's, the name only.
create or replace function help_set_on_duty(p_on boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_trainer) then
        raise exception 'Réservé aux formateurs de Marakaj.';
    end if;
    insert into help_trainer_status (user_id, on_duty, updated_at)
    values (auth.uid(), coalesce(p_on, true), now())
    on conflict (user_id) do update set on_duty = excluded.on_duty, updated_at = now();
    return coalesce(p_on, true);
end;
$$;

-- help_first_name(uuid) — 133_help_requests.sql's, the name only.
create or replace function help_first_name(p_user uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        notify_plain(nullif(btrim(p.first_name), ''), 40),
        notify_plain(nullif(split_part(btrim(coalesce(p.full_name, '')), ' ', 1), ''), 40),
        'Marakaj')
      from profiles p where p.id = p_user;
$$;

-- help_take(uuid) — 133_help_requests.sql's, the name only.
create or replace function help_take(p_request uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org uuid;
    v_by  uuid;
    v_who text := help_first_name(auth.uid());
begin
    if not help_is_trainer() or not help_helper_sees(p_request) then
        raise exception 'Cette demande ne vous est pas adressée.';
    end if;
    update help_requests
       set status = 'taken', taken_by = auth.uid(), taken_at = now()
     where id = p_request and status = 'open'
     returning org_id, requested_by into v_org, v_by;
    if v_org is null then
        if exists (select 1 from help_requests where id = p_request and taken_by = auth.uid()) then
            return help_inbox_row(p_request);
        end if;
        raise exception 'Un autre formateur s''occupe déjà de cette demande.';
    end if;
    perform help_log(p_request, 'taken', null);
    perform help_bell(v_by, p_request, 'help_taken',
        format('%s (formation Marakaj) s''occupe de votre demande d''aide.', v_who), 'shop');
    return help_inbox_row(p_request);
end;
$$;

-- product_photo_add(uuid,uuid) — 136_item_photos.sql's, the name only.
create or replace function product_photo_add(p_product_id uuid, p_document_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = public, auth
as $$
declare
    v_org    uuid;
    v_doc    documents%rowtype;
    v_cover  documents%rowtype;
    v_count  int;
    v_limit  int;
begin
    if auth.uid() is null then
        raise exception 'product_photo_add() needs a signed-in caller';
    end if;
    select org_id into v_org from products where id = p_product_id;
    if v_org is null then
        raise exception 'Article introuvable.';
    end if;
    if not can_write_org(v_org) or feature_access(v_org, 'products') <> 'edit' then
        raise exception 'Vous ne pouvez pas changer les photos de cet article.';
    end if;
    select * into v_doc from documents where id = p_document_id and org_id = v_org;
    if not found or not doc_is_photo(v_doc.kind, v_doc.content_type) then
        raise exception 'Photo introuvable.';
    end if;
    if v_doc.product_id is not null and v_doc.product_id <> p_product_id then
        raise exception 'Cette photo est déjà sur un autre article.';
    end if;
    if exists (select 1 from product_photos where product_id = p_product_id and document_id = p_document_id) then
        return product_gallery(p_product_id);
    end if;

    perform pg_advisory_xact_lock(hashtext('item_photos:' || p_product_id::text));
    select count(*) into v_count from product_photos where product_id = p_product_id;
    if v_count = 0 then
        select d.* into v_cover from documents d
         where d.product_id = p_product_id and d.id <> p_document_id
           and doc_is_photo(d.kind, d.content_type)
         order by coalesce(d.captured_at, d.created_at) desc
         limit 1;
        if v_cover.id is not null then
            v_count := 1;
        end if;
    end if;
    v_limit := coalesce(item_photo_limit(v_org), 1);
    if v_count >= v_limit then
        if v_limit <= 1 then
            raise exception 'Marakaj Pro : plusieurs photos par article. Sans Pro, un article garde une photo.'
                using errcode = 'check_violation';
        end if;
        raise exception 'Pas plus de % photos par article.', v_limit
            using errcode = 'check_violation';
    end if;
    if v_cover.id is not null then
        insert into product_photos (org_id, product_id, document_id, photo_key, position)
        values (v_org, p_product_id, v_cover.id, v_cover.r2_key, 0);
    end if;

    perform set_config('mara.gallery_doc', p_document_id::text, true);
    if v_doc.product_id is null then
        perform file_document(p_document_id, null, null, null, p_product_id);
    end if;
    perform set_config('mara.gallery_doc', '', true);

    insert into product_photos (org_id, product_id, document_id, photo_key, position)
    values (v_org, p_product_id, p_document_id, v_doc.r2_key,
            coalesce((select max(position) + 1 from product_photos where product_id = p_product_id), 0));
    return product_gallery(p_product_id);
end;
$$;

-- trg_product_photos_limit() — 136_item_photos.sql's, the name only.
create or replace function trg_product_photos_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_limit int;
begin
    -- A row moved onto another item counts there as a new one.
    if tg_op = 'UPDATE' and new.product_id = old.product_id then
        return new;
    end if;
    perform pg_advisory_xact_lock(hashtext('item_photos:' || new.product_id::text));
    v_limit := coalesce(item_photo_limit(new.org_id), 1);
    if (select count(*) from product_photos where product_id = new.product_id) >= v_limit then
        if v_limit <= 1 then
            raise exception 'Marakaj Pro : plusieurs photos par article. Sans Pro, un article garde une photo.'
                using errcode = 'check_violation';
        end if;
        raise exception 'Pas plus de % photos par article.', v_limit
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

-- platform_set_trainer(uuid,boolean) — 138_help_basic_pro.sql's, the name only.
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
        raise exception 'Seule l''équipe Marakaj choisit les formateurs.';
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
            case when p_on then format('%s devient formateur Marakaj', notify_plain(v_name, 60))
                 when jsonb_array_length(v_orgs) > 0
                 then format('%s n''est plus formateur Marakaj (%s entreprise(s) retirée(s))',
                             notify_plain(v_name, 60), jsonb_array_length(v_orgs))
                 else format('%s n''est plus formateur Marakaj', notify_plain(v_name, 60)) end,
            jsonb_build_object('user_id', p_user_id, 'is_trainer', v_was, 'assigned_orgs', v_orgs),
            jsonb_build_object('user_id', p_user_id, 'is_trainer', p_on, 'assigned_orgs', '[]'::jsonb),
            null, null);
    end if;
    return platform_trainer_state(p_user_id)
        || jsonb_build_object('unassigned', jsonb_array_length(v_orgs));
end;
$$;

-- cancel_promotion(uuid) — 144_spots_by_area.sql's, the name only.
create or replace function cancel_promotion(p_promotion_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v promotions%rowtype;
begin
    if auth.uid() is null then
        raise exception 'cancel_promotion() needs a signed-in caller';
    end if;
    select * into v from promotions where id = p_promotion_id for update;
    if not found or not is_org_admin(v.org_id) then
        raise exception 'Mise en avant introuvable';
    end if;
    if v.status = 'paid_claimed' then
        raise exception 'Paiement signalé : Marakaj le vérifie, la demande ne s''annule plus';
    end if;
    if v.status <> 'requested' then
        raise exception 'Seule une demande pas encore payée s''annule';
    end if;
    if exists (select 1 from wave_payments w
                where w.promotion_id = v.id and w.status in ('created', 'open')
                  and w.created_at > now() - interval '1 hour') then
        raise exception 'Un paiement Wave est en cours pour cette demande : réessayez dans une heure';
    end if;
    update promotions set status = 'cancelled', note = 'Annulée par l''entreprise' where id = v.id;
    insert into promotion_fixes (promotion_id, org_id, action, from_product, by_user)
    values (v.id, v.org_id, 'cancel', v.product_id, auth.uid());
end;
$$;

-- platform_stop_promotion(uuid) — 144_spots_by_area.sql's, the name only.
create or replace function platform_stop_promotion(p_promotion_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare v promotions%rowtype;
begin
    perform platform_only();
    select * into v from promotions where id = p_promotion_id for update;
    if not found then
        raise exception 'Mise en avant introuvable';
    end if;
    if not (v.status = 'approved' and v.ends_at > now()) then
        raise exception 'Seule une mise en avant en cours ou programmée s''arrête';
    end if;
    if v.starts_at > now() then
        -- Waiting its turn: never shown.
        update promotions set status = 'cancelled', note = 'Arrêtée par Marakaj' where id = v.id;
    else
        update promotions set ends_at = now(), note = 'Arrêtée par Marakaj' where id = v.id;
    end if;
    insert into promotion_fixes (promotion_id, org_id, action, from_product, by_user, by_platform)
    values (v.id, v.org_id, 'stop', v.product_id, auth.uid(), true);
    begin
        perform notify_org_admins(v.org_id, 'spot_stopped',
            'Marakaj a arrêté votre mise en avant.',
            jsonb_build_object('to', 'shop', 'promotion_id', v.id));
    exception when others then null;
    end;
    return platform_log_action(v.org_id, 'spot_stop', 'Mise en avant arrêtée',
        jsonb_build_object('promotion_id', v.id, 'status', v.status, 'ends_at', v.ends_at),
        jsonb_build_object('promotion_id', v.id, 'stopped_at', now()),
        null, null);
end;
$$;

-- platform_change_promotion_product(uuid,uuid) — 144_spots_by_area.sql's, the name only.
create or replace function platform_change_promotion_product(p_promotion_id uuid, p_product_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v      promotions%rowtype;
    v_name text;
begin
    perform platform_only();
    select * into v from promotions where id = p_promotion_id;
    if not found then
        raise exception 'Mise en avant introuvable';
    end if;
    perform promotion_change_item(p_promotion_id, p_product_id, true);
    select name into v_name from products where id = p_product_id;
    begin
        perform notify_org_admins(v.org_id, 'spot_changed',
            'Marakaj a changé l''article de votre mise en avant : ' || coalesce(v_name, '') || '.',
            jsonb_build_object('to', 'shop', 'promotion_id', v.id, 'name', v_name));
    exception when others then null;
    end;
    return platform_log_action(v.org_id, 'spot_change',
        'Mise en avant : article changé pour « ' || coalesce(v_name, '?') || ' »',
        jsonb_build_object('promotion_id', v.id, 'product_id', v.product_id),
        jsonb_build_object('promotion_id', v.id, 'product_id', p_product_id),
        null, null);
end;
$$;

-- ------------------------------------------------------------
-- 2. Two seeded lines, while still the seed
-- ------------------------------------------------------------
update path_steps
   set line = 'Vos cauris ouvrent les outils de Marakaj Pro.'
 where key = 'first_unlock'
   and line = 'Vos cauris ouvrent les outils de Mara Pro.';

update platform_settings
   set value = jsonb_set(value, '{changes}',
           to_jsonb('Nouvelles conditions : Marakaj est une plateforme, chaque entreprise vend elle-même ; les règles contre la fraude ; les engagements du vendeur et du livreur.'::text)),
       updated_at = now()
 where key = 'terms_versions'
   and value ->> 'changes' = 'Nouvelles conditions : Mara est une plateforme, chaque entreprise vend elle-même ; les règles contre la fraude ; les engagements du vendeur et du livreur.';

update platform_settings
   set value = jsonb_set(value, '{changes_en}',
           to_jsonb('New terms: Marakaj is a platform, each business sells for itself; the rules against fraud; the seller''s and the courier''s commitments.'::text)),
       updated_at = now()
 where key = 'terms_versions'
   and value ->> 'changes_en' = 'New terms: Mara is a platform, each business sells for itself; the rules against fraud; the seller''s and the courier''s commitments.';

notify pgrst, 'reload schema';
