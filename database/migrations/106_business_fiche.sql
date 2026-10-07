-- ============================================================
-- 106_business_fiche.sql — the fiche entreprise (batch 104, builder D).
--
-- The command center opens one business on one page: what it is (its
-- health, its owner, its plan and cauris, what wants attention), who it is
-- (its name, kind, address, money, contact lines, verification), its
-- vitrine, its functions, its team, its Pro and cauris, and its journal.
-- This migration is that page's server half. It stands on 104's contract
-- (platform_actions, platform_log_action, platform_undo_fns, platform_undo)
-- and redefines nothing another migration of this batch owns.
--
--   1. platform_org_overview(org): the Aperçu, in one call. Platform only.
--   2. platform_update_org_identity(...): the Identité. Platform only; the
--      kind changes only with the business's name typed back; every change
--      logged before/after with undo, the owner told « Mara a modifié … ».
--   3. platform_undo_org_columns(args): the one undo for 2 and 4 — puts the
--      columns back, but only those still as Mara left them (an owner's
--      later change is never overwritten: the undo is refused instead).
--      Called by platform_undo only (whitelisted in platform_undo_fns).
--   4. A trigger on orgs, not wrappers: when a platform admin who is not a
--      member of the business changes its vitrine (open, text, dressing,
--      colours, logo, pin, delivery), its identity (name, address, kind,
--      money, phone, address, verification) or its plan through ANY
--      function — the owner's own editor opened as Mara, the old console's
--      sheet, set_org_plan, set_org_verified — the change is logged with
--      its undo and (vitrine, identity) the owner is told. The functions
--      that write those columns (052, 053, 061, 065, 069, 080, 081, 088,
--      093, 103) stay as they are: none is redefined here. One editing
--      session is one journal line: changes by the same person to the same
--      part of the same business within 30 minutes, with nothing logged in
--      between, are folded into the line already open (its « before » kept,
--      its « after » brought forward) and the owner is told once.
--      A platform function that logs its own action sets the transaction's
--      mara.logged_write so the trigger does not log it twice (2 and 3 do).
--
-- Kinds: every part applies to a shop ('retail'), a farm and an association
-- ('association', legacy 'church') alike; the verification (088) is an
-- association's only, as it is today. A kind change seeds the new kind's
-- chart of accounts (additive, idempotent: nothing is removed).
--
-- P1: nothing a business or a vitrine shows is read from anything new
-- here; the trigger only writes the journal and the bell.
--
-- Re-runnable: functions replaced in place, the trigger dropped and
-- recreated, the whitelist row inserted on conflict do nothing.
-- ============================================================

-- ------------------------------------------------------------
-- 0. What the fiche watches, and the words for it (internal)
-- ------------------------------------------------------------

-- The business's columns, by the part of the fiche they belong to.
create or replace function mara_edit_columns(p_what text)
returns text[]
language sql
immutable
as $$
    select case p_what
        when 'vitrine'  then array['storefront_enabled', 'storefront_blurb', 'storefront_style',
                                   'theme', 'logo_key', 'lat', 'lng',
                                   'delivery_base', 'delivery_per_km', 'delivery_max_km',
                                   'delivery_included_km']
        when 'identity' then array['name', 'slug', 'profile', 'default_currency',
                                   'phone', 'address', 'verified_at', 'verified_by']
        when 'plan'     then array['plan', 'plan_until', 'plan_note']
        else array[]::text[]
    end;
$$;

-- The columns of [p_obj] that belong to the part, in the part's own order
-- (a jsonb object keeps its keys by length, which is no order to read in).
create or replace function mara_edit_keys(p_what text, p_obj jsonb)
returns text[]
language sql
immutable
as $$
    select coalesce(array_agg(c order by n), '{}')
      from unnest(mara_edit_columns(p_what)) with ordinality as x(c, n)
     where coalesce(p_obj, '{}'::jsonb) ? c;
$$;

-- « nom, adresse web » — the French words for the columns changed, once each.
create or replace function mara_edit_words(p_cols text[])
returns text
language sql
immutable
as $$
    select string_agg(w, ', ' order by o)
      from (
        select distinct on (w) w, o
          from (
            select case c
                when 'storefront_enabled'   then 'ouverture'
                when 'storefront_blurb'     then 'présentation'
                when 'storefront_style'     then 'habillage'
                when 'theme'                then 'couleurs'
                when 'logo_key'             then 'logo'
                when 'lat'                  then 'position'
                when 'lng'                  then 'position'
                when 'delivery_base'        then 'livraison'
                when 'delivery_per_km'      then 'livraison'
                when 'delivery_max_km'      then 'livraison'
                when 'delivery_included_km' then 'livraison'
                when 'name'                 then 'nom'
                when 'slug'                 then 'adresse web'
                when 'profile'              then 'type d''activité'
                when 'default_currency'     then 'monnaie'
                when 'phone'                then 'téléphone'
                when 'address'              then 'adresse'
                when 'verified_at'          then 'vérification'
                when 'verified_by'          then 'vérification'
                when 'plan'                 then 'formule'
                when 'plan_until'           then 'date de fin'
                when 'plan_note'            then 'note'
                else c
            end as w, ordinality as o
              from unnest(p_cols) with ordinality c
          ) x
         order by w, o
      ) y;
$$;

-- The journal's line for one part: « Vitrine : présentation, logo ».
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
            then 'Mara Pro'
                 || case when nullif(p_after ->> 'plan_until', '') is not null
                         then ' jusqu''au ' || to_char((p_after ->> 'plan_until')::date, 'DD/MM/YYYY')
                         else ' sans date de fin' end
        when p_what = 'plan' and p_after ? 'plan'
            then 'Mara (gratuit)'
        else coalesce(mara_edit_words(mara_edit_keys(p_what, p_after)), '')
    end;
$$;

-- What the owner's bell says when Mara changed a part, and when she took
-- it back. The plan rings no bell: it is the platform's, not the owner's.
create or replace function mara_edit_message(p_what text, p_cols text[], p_undone boolean)
returns text
language sql
immutable
as $$
    select case
        when p_undone and p_what = 'vitrine'
            then 'Mara a annulé sa modification de votre vitrine'
        when p_undone
            then 'Mara a annulé sa modification de l''identité de votre activité'
        when p_what = 'vitrine'
            then 'Mara a modifié votre vitrine'
        else 'Mara a modifié l''identité de votre activité : ' || coalesce(mara_edit_words(p_cols), '')
    end;
$$;

-- ------------------------------------------------------------
-- 1. Aperçu
-- ------------------------------------------------------------
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
        raise exception 'Réservé à l''équipe Mara';
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

-- ------------------------------------------------------------
-- 2. Identité
-- ------------------------------------------------------------
-- Null leaves a field as it is; an empty phone or address clears it. The
-- kind changes only with the business's present name typed back in
-- [p_confirm]. Returns the journal line, or null when nothing changed.
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
        raise exception 'Réservé à l''équipe Mara';
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
        raise exception 'La vérification par Mara concerne les associations';
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

-- ------------------------------------------------------------
-- 3. The undo: the columns back, if nobody changed them since
-- ------------------------------------------------------------
-- [p_args] is what the journal line carries: {org, what, before, after}.
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
        raise exception 'Réservé à l''équipe Mara';
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

insert into platform_undo_fns (fn) values ('platform_undo_org_columns')
on conflict do nothing;

-- ------------------------------------------------------------
-- 4. Mara's hand on a business she is not a member of: logged, told
-- ------------------------------------------------------------
create or replace function trg_orgs_mara_edit()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_uid    uuid := auth.uid();
    v_old    jsonb := to_jsonb(old);
    v_new    jsonb := to_jsonb(new);
    v_what   text;
    v_col    text;
    v_before jsonb;
    v_after  jsonb;
    v_open   platform_actions%rowtype;
    v_action uuid;
    v_cols   text[];
begin
    if v_uid is null
       or coalesce(current_setting('mara.logged_write', true), '') = 'on'
       or not caller_is_platform_admin()
       or exists (select 1 from memberships m where m.org_id = new.id and m.user_id = v_uid) then
        return null;
    end if;

    foreach v_what in array array['vitrine', 'identity', 'plan'] loop
        v_before := '{}'::jsonb;
        v_after  := '{}'::jsonb;
        foreach v_col in array mara_edit_columns(v_what) loop
            if v_old -> v_col is distinct from v_new -> v_col then
                v_before := v_before || jsonb_build_object(v_col, v_old -> v_col);
                v_after  := v_after  || jsonb_build_object(v_col, v_new -> v_col);
            end if;
        end loop;
        continue when v_before = '{}'::jsonb;

        -- The line still open: the newest of this business's journal, by the
        -- same person, for the same part, not undone, under 30 minutes old.
        select a.* into v_open
          from platform_actions a
         where a.org_id = new.id
         order by a.at desc, a.id desc
         limit 1;
        if v_open.id is not null
           and v_open.kind = v_what
           and v_open.actor = v_uid
           and v_open.undone_at is null
           and v_open.undo_fn = 'platform_undo_org_columns'
           and v_open.at > now() - interval '30 minutes' then
            -- The first « before » of each column stands; the newest « after ».
            v_before := v_before || coalesce(v_open.before, '{}'::jsonb);
            v_after  := coalesce(v_open.after, '{}'::jsonb) || v_after;
            update platform_actions
               set before    = v_before,
                   after     = v_after,
                   summary   = mara_edit_summary(v_what, v_after),
                   undo_args = jsonb_build_object('org', new.id, 'what', v_what,
                                                  'before', v_before, 'after', v_after)
             where id = v_open.id;
            continue;
        end if;

        v_action := platform_log_action(new.id, v_what,
            mara_edit_summary(v_what, v_after), v_before, v_after,
            'platform_undo_org_columns',
            jsonb_build_object('org', new.id, 'what', v_what,
                               'before', v_before, 'after', v_after));
        if v_what in ('vitrine', 'identity') then
            v_cols := mara_edit_keys(v_what, v_after);
            perform notify_org_owners(new.id, 'mara_edited',
                mara_edit_message(v_what, v_cols, false),
                jsonb_build_object('what', v_what, 'fields', to_jsonb(v_cols),
                                   'action', v_action));
        end if;
    end loop;
    return null;
end;
$$;

drop trigger if exists orgs_mara_edit on orgs;
create trigger orgs_mara_edit
after update on orgs
for each row
when (   old.storefront_enabled   is distinct from new.storefront_enabled
      or old.storefront_blurb     is distinct from new.storefront_blurb
      or old.storefront_style     is distinct from new.storefront_style
      or old.theme                is distinct from new.theme
      or old.logo_key             is distinct from new.logo_key
      or old.lat                  is distinct from new.lat
      or old.lng                  is distinct from new.lng
      or old.delivery_base        is distinct from new.delivery_base
      or old.delivery_per_km      is distinct from new.delivery_per_km
      or old.delivery_max_km      is distinct from new.delivery_max_km
      or old.delivery_included_km is distinct from new.delivery_included_km
      or old.name                 is distinct from new.name
      or old.slug                 is distinct from new.slug
      or old.profile              is distinct from new.profile
      or old.default_currency     is distinct from new.default_currency
      or old.phone                is distinct from new.phone
      or old.address              is distinct from new.address
      or old.verified_at          is distinct from new.verified_at
      or old.verified_by          is distinct from new.verified_by
      or old.plan                 is distinct from new.plan
      or old.plan_until           is distinct from new.plan_until
      or old.plan_note            is distinct from new.plan_note)
execute function trg_orgs_mara_edit();

-- ------------------------------------------------------------
-- Grants (063: born closed; said by name)
-- ------------------------------------------------------------
revoke execute on function mara_edit_columns(text)                    from public;
revoke execute on function mara_edit_keys(text, jsonb)                from public;
revoke execute on function mara_edit_words(text[])                    from public;
revoke execute on function mara_edit_summary(text, jsonb)             from public;
revoke execute on function mara_edit_message(text, text[], boolean)   from public;
revoke execute on function platform_org_overview(uuid)                from public;
revoke execute on function platform_update_org_identity(uuid, text, text, text, text, text, text, boolean, text) from public;
revoke execute on function platform_undo_org_columns(jsonb)           from public;
revoke execute on function trg_orgs_mara_edit()                       from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function mara_edit_columns(text)                    from anon;
        revoke execute on function mara_edit_keys(text, jsonb)                from anon;
        revoke execute on function mara_edit_words(text[])                    from anon;
        revoke execute on function mara_edit_summary(text, jsonb)             from anon;
        revoke execute on function mara_edit_message(text, text[], boolean)   from anon;
        revoke execute on function platform_org_overview(uuid)                from anon;
        revoke execute on function platform_update_org_identity(uuid, text, text, text, text, text, text, boolean, text) from anon;
        revoke execute on function platform_undo_org_columns(jsonb)           from anon;
        revoke execute on function trg_orgs_mara_edit()                       from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: the trigger, the undo platform_undo calls, their words.
        revoke execute on function mara_edit_columns(text)                    from authenticated;
        revoke execute on function mara_edit_keys(text, jsonb)                from authenticated;
        revoke execute on function mara_edit_words(text[])                    from authenticated;
        revoke execute on function mara_edit_summary(text, jsonb)             from authenticated;
        revoke execute on function mara_edit_message(text, text[], boolean)   from authenticated;
        revoke execute on function platform_undo_org_columns(jsonb)           from authenticated;
        revoke execute on function trg_orgs_mara_edit()                       from authenticated;
        -- The fiche's doors; each refuses anybody but the platform.
        grant execute on function platform_org_overview(uuid)                 to authenticated;
        grant execute on function platform_update_org_identity(uuid, text, text, text, text, text, text, boolean, text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
