-- ============================================================
-- 107_kinds_requests.sql — the types of business, and the request page
-- (the command center's phase 3, on 104's switchboard and journal).
--
-- The owner: « As an admin I need to be able to edit a store or a type of
-- business … I need to be able to edit the business request page and
-- vitrine. » And: « The new admin setup will not modify anything to the
-- stores and vitrine until I make the change myself? » — so nothing here
-- changes what any shop, farm, association or vitrine shows until Mara
-- writes a row: no kind_settings row, no vitrine default and no request
-- form is exactly today (test_batch107 computes it before and after).
--
--   1. Réglages par type: kind_settings (kind, key) holds a kind's own
--      value for the free numbers that differ by kind — free_photo_items,
--      free_max_staff, free_max_invoices_month, vitrine_min_items (shops
--      and farms), vitrine_min_items_association (associations).
--      kind_setting(kind, key) reads the kind's value, else the global
--      platform setting. Every reader of those numbers now asks for the
--      business's kind (org_kind_limit): org_free_workers (the free seat),
--      org_photo_limit (photographed articles), trg_cap_free_plan (the
--      invoices a month), vitrine_min (what opens a vitrine), path_goal
--      (Le Chemin's « articles » step), and plan_terms(), which carries a
--      kind's own numbers under 'kinds' — only when there are any — so the
--      paywall says the business's own figure. Delivery is left out: each
--      shop and farm already sets its own distance (069), and an
--      association does not deliver (099).
--   2. Vitrine par défaut: a kind's default presentation (layout), colour
--      (accent) and cover (none, or the first photographed article on the
--      shelf), stored as kind_settings 'vitrine_default'. Used ONLY by a
--      vitrine that was never dressed: orgs.storefront_style is still '{}'
--      — the column's default, which set_storefront_style (093) leaves as
--      soon as the owner keeps any dressing of their own (a tagline, hours,
--      a colour, a cover, a layout, pinned articles). A vitrine whose
--      dressing was all cleared is at '{}' too, and reads as never dressed:
--      it shows Mara's default, which is what « par défaut » means. A
--      vitrine d'exemple (094) never takes it. As 093's options: on a
--      Basic vitrine only the free ones — the colour and the cover, while
--      the basics are free —, the presentation (layout) only on a Vitrine+
--      (Mara Pro) one; storefront() adds it after the business's own
--      (empty) style.
--   3. Mise en route: a kind's optional walkthrough steps turned off
--      (kind_settings 'setup_off') — a shop's or a farm's « vitrine » and
--      « position », an association's « members » and « vitrine » — never
--      the required ones (the name, the first article; the association's
--      name and kind). setup_steps_off(org) is what the setup screens read.
--   4. The request page: platform_settings.application_form — a welcome
--      text, which kinds can be asked for, extra questions (texte, choix,
--      nombre, oui-non; label, help, required) in order; the name, the
--      address and the kind always stay. No form = today's page. The
--      answers are kept with the application (org_applications.answers, a
--      snapshot of each question as it was asked) and shown on the
--      Demandes cards (platform_pending_applications). apply_for_org
--      gains its answers as an 8-argument signature; 101's seven-argument
--      one stays (an older build sends it) and now goes through the same
--      checks with no answers. Two signatures and not a default: a re-run
--      of 017 or 101 (the bundle, or a suite) recreates the seven-argument
--      one, and a default on the new one would make every call ambiguous.
--      The applicant hears the decision: accepted (the business opens) or
--      refused with the reason, and each decision is in the journal.
--
-- Every change here is the platform's (caller_is_platform_admin, checked on
-- the server), logged in platform_actions with its undo (104).
-- Shops, farms and associations (a legacy church reads as an association):
-- each has its tab; the numbers each kind has are in kind_setting_catalog.
--
-- Functions replaced, each from its latest definition: org_free_workers,
-- org_photo_limit, trg_cap_free_plan and plan_terms (100), vitrine_min
-- (098), path_goal (097), storefront (093), apply_for_org (101).
--
-- Re-runnable (the bundle runs twice): tables and columns if not exists,
-- triggers dropped and recreated, functions replaced in place.
-- ============================================================

do $$
begin
    if to_regclass('public.platform_actions') is null
       or to_regclass('public.platform_undo_fns') is null
       or to_regprocedure('public.platform_log_action(uuid, text, text, jsonb, jsonb, text, jsonb)') is null
       or to_regprocedure('public.org_kind(uuid)') is null then
        raise exception '107 needs 104 (platform_actions, platform_log_action, platform_undo_fns, org_kind) applied first';
    end if;
end $$;

-- ------------------------------------------------------------
-- 1. A kind's own settings
-- ------------------------------------------------------------
create table if not exists kind_settings (
    kind   text not null,
    key    text not null,
    value  jsonb not null,
    set_by uuid references profiles(id) on delete set null,
    set_at timestamptz not null default now(),
    primary key (kind, key)
);
alter table kind_settings drop constraint if exists kind_settings_kind;
alter table kind_settings add constraint kind_settings_kind
    check (kind in ('retail', 'farm', 'association'));
alter table kind_settings drop constraint if exists kind_settings_key;
alter table kind_settings add constraint kind_settings_key
    check (key in ('free_photo_items', 'free_max_staff', 'free_max_invoices_month',
                   'vitrine_min_items', 'vitrine_min_items_association',
                   'vitrine_default', 'setup_off'));
alter table kind_settings enable row level security;
comment on table kind_settings is
    'A kind''s own value for a platform setting (107), its vitrine default and its '
    'walkthrough steps turned off. No row: the global setting, i.e. today. '
    'Written by platform_set_kind_setting() only.';

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on kind_settings from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on kind_settings from anon;
    end if;
end $$;

alter table org_applications add column if not exists answers jsonb;

-- Written through its functions only: apply_for_org (the applicant, with
-- the page's checks and answers), approve_org_application and
-- reject_org_application (the platform) — all definer. 017 let a signed-in
-- caller insert a pending row of their own and a platform admin update one
-- directly; neither app writes the table itself, and a direct insert would
-- walk past the request page's kinds and required questions. Reading stays
-- as 017 has it (the applicant's own, the platform's all).
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke insert, update, delete, truncate on org_applications from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke insert, update, delete, truncate on org_applications from anon;
    end if;
end $$;
comment on column org_applications.answers is
    'The request page''s extra questions as they were asked and answered (107): '
    '[{id, label, type, value}]. Null when the page asked none.';

-- The numbers a kind may have of its own: which kinds, the fallback the
-- readers already used, and the bounds.
create or replace function kind_setting_catalog()
returns table (key text, label text, kinds text[], fallback int,
               min_value int, max_value int, sort int)
language sql
immutable
set search_path = public
as $$
    values
        ('free_photo_items', 'Articles en photo (formule gratuite)',
         array['retail', 'farm', 'association'], 10, 0, 1000, 10),
        ('free_max_staff', 'Personnes offertes en plus du propriétaire',
         array['retail', 'farm', 'association'], 1, 0, 50, 20),
        ('free_max_invoices_month', 'Factures par mois (formule gratuite)',
         array['retail', 'farm', 'association'], 20, 0, 10000, 30),
        ('vitrine_min_items', 'Articles en vente pour ouvrir la vitrine',
         array['retail', 'farm'], 8, 0, 100, 40),
        ('vitrine_min_items_association', 'Services pour ouvrir la vitrine',
         array['association'], 1, 1, 100, 50);
$$;

-- The walkthrough's steps per kind (setup_screen.dart and
-- association_setup_screen.dart, in their order); the required ones can
-- never be turned off.
create or replace function kind_setup_steps(p_kind text)
returns jsonb
language sql
immutable
set search_path = public
as $$
    select case when p_kind in ('association', 'church') then
        '[{"key": "identity", "label": "Le nom et ce qu''elle est", "required": true},
          {"key": "members",  "label": "Les premiers membres",     "required": false},
          {"key": "vitrine",  "label": "La vitrine",               "required": false}]'::jsonb
    when p_kind in ('retail', 'farm') then
        '[{"key": "identity", "label": "Le nom",                   "required": true},
          {"key": "article",  "label": "Le premier article",       "required": true},
          {"key": "vitrine",  "label": "La vitrine",               "required": false},
          {"key": "position", "label": "La position sur la carte", "required": false}]'::jsonb
    else '[]'::jsonb end;
$$;

-- The kind's value, else the platform's. Null when neither has one.
create or replace function kind_setting(p_kind text, p_key text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        (select k.value from kind_settings k
          where k.kind = case when p_kind = 'church' then 'association' else p_kind end
            and k.key = p_key),
        (select s.value from platform_settings s where s.key = p_key));
$$;

-- A number for this business: its kind's, else the platform's, else the
-- default — with no kind row, exactly plan_limit(p_key, p_default).
create or replace function org_kind_limit(p_org uuid, p_key text, p_default int)
returns int
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(nullif(kind_setting(org_kind(p_org), p_key) #>> '{}', '')::int,
                    p_default);
$$;

-- ------------------------------------------------------------
-- 2. The readers, by kind
-- ------------------------------------------------------------
-- 100's free seat, the kind's number.
create or replace function org_free_workers(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case when org_setup_done(p_org_id)
                then greatest(org_kind_limit(p_org_id, 'free_max_staff', 1), 0) else 0 end;
$$;

-- 100's photographed articles, the kind's number.
create or replace function org_photo_limit(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case
        when org_plan(o.id) = 'pro' or o.showcase then null
        else greatest(org_kind_limit(o.id, 'free_photo_items', 10), 0) + o.photo_slots
    end
    from orgs o where o.id = p_org_id;
$$;

-- 098's minimum, the kind's number.
create or replace function vitrine_min(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case when o.profile in ('church', 'association')
                then greatest(org_kind_limit(o.id, 'vitrine_min_items_association', 1), 1)
                else org_kind_limit(o.id, 'vitrine_min_items', 8) end
      from orgs o where o.id = p_org_id;
$$;

-- 097's goals, the articles step at the kind's minimum.
create or replace function path_goal(p_org uuid, p_step text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case p_step
        when 'contact'      then 2
        when 'articles'     then greatest(org_kind_limit(p_org, 'vitrine_min_items', 8), 1)
        when 'photos'       then 3
        when 'three_orders' then greatest(cauris_param('progress_credit_orders', 3), 0)
        when 'till_week'    then 7
        when 'log_week'     then 7
        else 1
    end;
$$;

-- 100's caps, the invoices a month at the kind's number.
create or replace function trg_cap_free_plan()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_cap   int;
    v_count int;
begin
    if auth.uid() is null
       or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
       or org_plan(new.org_id) <> 'free' then
        return new;
    end if;

    if tg_table_name = 'memberships' then
        -- What the row makes of its person. An owner, a trainer (only the
        -- platform names one: trg_membership_roles) or Mara's own admin is
        -- no worker.
        if new.role = 'owner' or coalesce(new.is_trainer, false)
           or exists (select 1 from profiles where id = new.user_id and is_platform_admin) then
            return new;
        end if;
        -- A worker's row that stays a worker's — another role between
        -- workers, the same person, the same business — adds nobody. A row
        -- that stops being an owner's or a trainer's, or that changes hands
        -- or business, is somebody new: it takes the seat like an insert.
        if tg_op = 'UPDATE'
           and old.user_id = new.user_id and old.org_id = new.org_id
           and old.role <> 'owner' and not coalesce(old.is_trainer, false) then
            return new;
        end if;
        -- Somebody already there by another grant — a worker, or still its
        -- owner — adds nobody either. A trainer's grant does not count: a
        -- trainer given a second role becomes a worker.
        if exists (select 1 from memberships m
                    where m.org_id = new.org_id and m.user_id = new.user_id
                      and m.id <> new.id and not m.is_trainer) then
            return new;
        end if;
        -- One at a time per business: two codes claimed at once cannot both
        -- take the last seat.
        perform pg_advisory_xact_lock(hashtext('team:' || new.org_id::text));
        if team_full(new.org_id) then
            raise exception '%', team_full_message(new.org_id);
        end if;

    elsif tg_table_name = 'invoices' then
        v_cap := org_kind_limit(new.org_id, 'free_max_invoices_month', 20);
        select count(*) into v_count from invoices
         where org_id = new.org_id
           and issued_on >= date_trunc('month', coalesce(new.issued_on, current_date))::date
           and issued_on <  (date_trunc('month', coalesce(new.issued_on, current_date)) + interval '1 month')::date;
        if v_count >= v_cap then
            raise exception 'Kaj Pro : la formule gratuite permet % factures par mois. Ouvrez Compte › Kaj Pro pour continuer ce mois-ci.', v_cap;
        end if;

    elsif tg_table_name = 'documents' then
        -- An article's picture is counted by article (trg_photo_items); the
        -- paperwork filed on an article (a delivery note, a receipt) is
        -- counted here, with every capture that is about no article.
        if new.product_id is not null and doc_is_photo(new.kind, new.content_type) then
            return new;
        end if;
        v_cap := plan_limit('free_max_photos', 50);
        select count(*) into v_count from documents
         where org_id = new.org_id
           and (product_id is null or not doc_is_photo(kind, content_type));
        if v_count >= v_cap then
            raise exception 'Kaj Pro : la formule gratuite garde % photos. Ouvrez Compte › Kaj Pro pour en ajouter.', v_cap;
        end if;
    end if;

    return new;
end;
$$;

-- 100's terms, with each kind's own numbers under 'kinds' — the key is
-- there only when a kind has one, so with none the terms are 100's.
create or replace function plan_terms()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'pro_features',            coalesce(plan_setting('pro_features'), '[]'::jsonb),
        'free_max_staff',          plan_limit('free_max_staff', 1),
        'free_max_invoices_month', plan_limit('free_max_invoices_month', 20),
        'free_max_photos',         plan_limit('free_max_photos', 50),
        'free_photo_items',        plan_limit('free_photo_items', 10),
        'free_history_months',     plan_limit('free_history_months', 12),
        'pro_price_month',         plan_limit('pro_price_month', 2500),
        'pro_price_year',          plan_limit('pro_price_year', 25000),
        'pro_currency',            coalesce(plan_setting('pro_currency') #>> '{}', 'XOF'),
        'platform_wave',           coalesce(plan_setting('platform_wave') #>> '{}', ''),
        'platform_wave_name',      coalesce(plan_setting('platform_wave_name') #>> '{}', ''),
        'delivery_share_pct',      plan_limit('delivery_share_pct', 10),
        'stripe_on',               stripe_on()
    )
    || coalesce((
        select jsonb_build_object('kinds', jsonb_object_agg(k.kind, k.vals))
          from (select s.kind, jsonb_object_agg(s.key, s.value) as vals
                  from kind_settings s
                 where s.key in (select c.key from kind_setting_catalog() c)
                 group by s.kind) k
        having count(*) > 0), '{}'::jsonb);
$$;

-- ------------------------------------------------------------
-- 3. Vitrine par défaut
-- ------------------------------------------------------------
-- What Mara's default adds to this vitrine: nothing unless it was never
-- dressed (storefront_style = '{}') and its kind has a default. The cover
-- « first_photo » is the first photographed article on the shelf, in
-- storefront_products' order, its newest picture — a key the photo gate
-- (storefront_photo_allowed) already serves. What a vitrine of its plan
-- may show, as 093 says it: the colour and the cover on any vitrine while
-- the basics are free (vitrine_free_basics), the presentation (layout)
-- only with Vitrine+ (Mara Pro) — a Basic vitrine is never dressed beyond
-- what its owner could choose.
create or replace function vitrine_default_style(p_org uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((
        select jsonb_strip_nulls(jsonb_build_object(
                   'accent', d.v ->> 'accent',
                   'layout', nullif(d.v ->> 'layout', 'grid'),
                   'cover_key', case when d.v ->> 'cover' = 'first_photo' then (
                       select (select doc.r2_key from documents doc
                                where doc.product_id = p.id
                                  and doc_is_photo(doc.kind, doc.content_type)
                                order by coalesce(doc.captured_at, doc.created_at) desc
                                limit 1)
                         from products p
                        where p.org_id = o.id and p.is_active and p.is_published
                          and exists (select 1 from documents doc
                                       where doc.product_id = p.id
                                         and doc_is_photo(doc.kind, doc.content_type))
                        order by p.is_service, p.name
                        limit 1) end))
               - case when org_has(o.id, 'vitrine_plus') then '{}'::text[]
                      else array['layout'] end
          from orgs o
          cross join lateral (select kind_setting(o.profile::text, 'vitrine_default') as v) d
         where o.id = p_org
           and o.storefront_style = '{}'::jsonb
           and not o.showcase
           and jsonb_typeof(d.v) = 'object'
           and (org_has(o.id, 'vitrine_plus') or cauris_param('vitrine_free_basics', 1) = 1)),
        '{}'::jsonb);
$$;

-- 093's window, with Mara's default for a vitrine never dressed.
create or replace function storefront(p_slug text)
returns table (
    org_id        uuid,
    name          text,
    slug          text,
    profile       text,
    blurb         text,
    phone         text,
    address       text,
    theme         text,
    currency      text,
    lat           double precision,
    lng           double precision,
    wave_merchant text,
    style         jsonb
)
language sql
stable
security definer
set search_path = public
as $$
    select o.id, o.name, o.slug, o.profile::text, o.storefront_blurb,
           o.phone, o.address, o.theme, o.default_currency, o.lat, o.lng,
           case when o.wave_allowed then o.wave_merchant end,
           (case when org_has(o.id, 'vitrine_plus') then
                     o.storefront_style
                     || case when o.storefront_style ? 'schedule'
                             then jsonb_strip_nulls(jsonb_build_object('open_now',
                                      vitrine_open_now(o.storefront_style -> 'schedule')))
                             else '{}'::jsonb end
                 when cauris_param('vitrine_free_basics', 1) = 1 then
                     o.storefront_style - 'pinned' - 'hide_out_of_stock' - 'layout'
                 else '{}'::jsonb end)
           || vitrine_default_style(o.id)
           || case when o.logo_key is not null
                   then jsonb_build_object('logo_key', o.logo_key)
                   else '{}'::jsonb end
           || jsonb_build_object('delivers', org_delivers(o.id))
           || coalesce((
                select jsonb_build_object('top_week', jsonb_build_object(
                           'rank', r.rank, 'league', league_label(r.league)))
                  from cauris_week_results r
                 where r.org_id = o.id
                   and r.week_start = (cauris_week_start() - interval '7 days')::date),
              '{}'::jsonb)
    from orgs o
    where o.id = storefront_open(p_slug);
$$;

-- ------------------------------------------------------------
-- 4. Mise en route
-- ------------------------------------------------------------
-- The optional steps this business's kind has turned off, for its setup
-- screen. A required step is never in it, whatever the row says.
create or replace function setup_steps_off(p_org uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select case when not (is_org_member(p_org) or caller_is_platform_admin()) then '[]'::jsonb
    else coalesce((
        select jsonb_agg(s.step order by s.step)
          from orgs o
          cross join lateral (select kind_setting(o.profile::text, 'setup_off') as v) k
          cross join lateral jsonb_array_elements_text(
              case when jsonb_typeof(k.v) = 'array' then k.v else '[]'::jsonb end) as s(step)
         where o.id = p_org
           and exists (select 1 from jsonb_array_elements(kind_setup_steps(o.profile::text)) e
                        where e ->> 'key' = s.step and not (e ->> 'required')::boolean)),
        '[]'::jsonb) end;
$$;

-- ------------------------------------------------------------
-- 5. The command center: a kind's models
-- ------------------------------------------------------------
-- How a value reads in the journal.
create or replace function kind_setting_words(p_key text, p_value jsonb)
returns text
language sql
immutable
set search_path = public
as $$
    select case
        when p_value is null then 'par défaut'
        when p_key = 'vitrine_default' then concat_ws(', ',
            'présentation ' || case p_value ->> 'layout'
                when 'large' then 'grandes photos' when 'list' then 'liste'
                when 'menu' then 'menu' else 'grille' end,
            case when p_value ? 'accent' then 'couleur ' || (p_value ->> 'accent') end,
            case when p_value ->> 'cover' = 'first_photo' then 'couverture : la première photo' end)
        when p_key = 'setup_off' then 'étapes retirées : '
            || (select string_agg(e, ', ') from jsonb_array_elements_text(p_value) e)
        else p_value #>> '{}'
    end;
$$;

-- Everything a kind's tab draws: its businesses (for the impact line),
-- its numbers (the kind's own, the global), its vitrine default and its
-- walkthrough.
create or replace function platform_kind_models(p_kind text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_kind text := case when p_kind = 'church' then 'association' else p_kind end;
    v_off  jsonb;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    if v_kind is null or v_kind not in ('retail', 'farm', 'association') then
        raise exception 'Type d''activité inconnu : %', coalesce(p_kind, '');
    end if;
    select value into v_off from kind_settings where kind = v_kind and key = 'setup_off';

    return (
        with o as (
            select o.id, o.storefront_style
              from orgs o
             where o.archived_at is null and not o.showcase
               and (case when o.profile::text = 'church' then 'association'
                         else o.profile::text end) = v_kind
        )
        select jsonb_build_object(
            'kind', v_kind,
            'orgs', (select count(*) from o),
            'free', (select count(*) from o where org_plan(o.id) = 'free'),
            'never_dressed', (select count(*) from o where o.storefront_style = '{}'::jsonb),
            'settings', coalesce((
                select jsonb_agg(jsonb_build_object(
                           'key', c.key,
                           'label', c.label,
                           'global', coalesce(nullif(plan_setting(c.key) #>> '{}', '')::int, c.fallback),
                           'value', (select k.value from kind_settings k
                                      where k.kind = v_kind and k.key = c.key),
                           'min', c.min_value,
                           'max', c.max_value) order by c.sort)
                  from kind_setting_catalog() c
                 where v_kind = any (c.kinds)), '[]'::jsonb),
            'vitrine_default', (select k.value from kind_settings k
                                 where k.kind = v_kind and k.key = 'vitrine_default'),
            'setup', coalesce((
                select jsonb_agg(e || jsonb_build_object(
                           'on', (e ->> 'required')::boolean
                                 or not coalesce(v_off ? (e ->> 'key'), false))
                           order by n)
                  from jsonb_array_elements(kind_setup_steps(v_kind)) with ordinality s(e, n)),
                '[]'::jsonb)
        )
    );
end;
$$;

-- One kind setting: a number (null: back to the global one), the vitrine
-- default (an object; null or {} clears it) or the walkthrough steps
-- turned off (an array; null or [] turns them all on). Logged with its
-- undo. Returns the action's id, or null when nothing changed.
create or replace function platform_set_kind_setting(p_kind text, p_key text, p_value jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_kind   text := case when p_kind = 'church' then 'association' else p_kind end;
    v_value  jsonb := case when p_value = 'null'::jsonb then null else p_value end;
    v_before jsonb;
    v_label  text;
    v_text   text;
    v_steps  jsonb;
    v_step   text;
    v_out    jsonb;
    c        record;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    if v_kind is null or v_kind not in ('retail', 'farm', 'association') then
        raise exception 'Type d''activité inconnu : %', coalesce(p_kind, '');
    end if;

    select * into c from kind_setting_catalog() k where k.key = p_key;
    if found then
        if not (v_kind = any (c.kinds)) then
            raise exception 'Ce réglage n''existe pas pour ce type d''activité.';
        end if;
        if v_value is not null then
            v_text := btrim(v_value #>> '{}');
            if jsonb_typeof(v_value) not in ('number', 'string') or v_text !~ '^[0-9]{1,6}$' then
                raise exception 'Ce réglage est un nombre entier.';
            end if;
            if v_text::int < c.min_value or v_text::int > c.max_value then
                raise exception 'Ce nombre est hors des limites permises.';
            end if;
            v_value := to_jsonb(v_text::int);
        end if;
        v_label := c.label;

    elsif p_key = 'vitrine_default' then
        if v_value is not null then
            if jsonb_typeof(v_value) <> 'object' then
                raise exception 'La vitrine par défaut est une présentation, une couleur et une couverture.';
            end if;
            if exists (select 1 from jsonb_object_keys(v_value) k
                        where k not in ('layout', 'accent', 'cover')) then
                raise exception 'La vitrine par défaut est une présentation, une couleur et une couverture.';
            end if;
            v_out := '{}'::jsonb;
            v_text := nullif(btrim(coalesce(v_value ->> 'layout', '')), '');
            if v_text is not null and v_text not in ('grid', 'large', 'list', 'menu') then
                raise exception 'La présentation est grille, grandes photos, liste ou menu';
            end if;
            if v_text is not null and v_text <> 'grid' then
                v_out := v_out || jsonb_build_object('layout', v_text);
            end if;
            v_text := nullif(btrim(coalesce(v_value ->> 'accent', '')), '');
            if v_text is not null then
                if v_text !~ '^#[0-9A-Fa-f]{6}$' then
                    raise exception 'La couleur doit s''écrire #RRGGBB';
                end if;
                v_out := v_out || jsonb_build_object('accent', upper(v_text));
            end if;
            v_text := nullif(btrim(coalesce(v_value ->> 'cover', '')), '');
            if v_text is not null and v_text not in ('none', 'first_photo') then
                raise exception 'La couverture est aucune ou la première photo de la vitrine.';
            end if;
            if v_text = 'first_photo' then
                v_out := v_out || '{"cover": "first_photo"}'::jsonb;
            end if;
            v_value := nullif(v_out, '{}'::jsonb);
        end if;
        v_label := 'Vitrine par défaut';

    elsif p_key = 'setup_off' then
        if v_value is not null then
            if jsonb_typeof(v_value) <> 'array' then
                raise exception 'Les étapes retirées sont une liste.';
            end if;
            v_steps := kind_setup_steps(v_kind);
            for v_step in select jsonb_array_elements_text(v_value) loop
                if not exists (select 1 from jsonb_array_elements(v_steps) e where e ->> 'key' = v_step) then
                    raise exception 'Étape inconnue : %', v_step;
                end if;
                if exists (select 1 from jsonb_array_elements(v_steps) e
                            where e ->> 'key' = v_step and (e ->> 'required')::boolean) then
                    raise exception 'Une étape obligatoire de la mise en route ne peut pas être retirée.';
                end if;
            end loop;
            -- In the walkthrough's order, each once.
            select jsonb_agg(e ->> 'key' order by n) into v_value
              from jsonb_array_elements(v_steps) with ordinality s(e, n)
             where v_value ? (e ->> 'key');
        end if;
        v_label := 'Mise en route';

    else
        raise exception 'Réglage inconnu : %', coalesce(p_key, '');
    end if;

    select k.value into v_before from kind_settings k where k.kind = v_kind and k.key = p_key;
    if v_before is not distinct from v_value then
        return null;
    end if;
    if v_value is null then
        delete from kind_settings where kind = v_kind and key = p_key;
    else
        insert into kind_settings (kind, key, value, set_by)
        values (v_kind, p_key, v_value, auth.uid())
        on conflict (kind, key) do update
            set value = excluded.value, set_by = excluded.set_by, set_at = now();
    end if;

    return platform_log_action(
        null,
        'kind_setting',
        '« ' || v_label || ' » — '
            || case v_kind when 'retail' then 'toutes les boutiques'
                           when 'farm' then 'toutes les fermes'
                           else 'toutes les associations' end
            || ' : ' || kind_setting_words(p_key, v_value)
            || ' (avant : ' || kind_setting_words(p_key, v_before) || ')',
        jsonb_build_object('kind', v_kind, 'key', p_key, 'value', v_before),
        jsonb_build_object('kind', v_kind, 'key', p_key, 'value', v_value),
        'platform_restore_kind_setting',
        jsonb_build_object('kind', v_kind, 'key', p_key, 'value', v_before, 'expect', v_value));
end;
$$;

-- The undo of a kind setting: the value as it was — unless it changed
-- since, in which case the newer action is undone first (as 104's).
create or replace function platform_restore_kind_setting(p_args jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_kind  text  := p_args ->> 'kind';
    v_key   text  := p_args ->> 'key';
    v_value jsonb := nullif(p_args -> 'value', 'null'::jsonb);
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    if (select k.value from kind_settings k where k.kind = v_kind and k.key = v_key)
       is distinct from nullif(p_args -> 'expect', 'null'::jsonb) then
        raise exception 'Ce réglage a changé depuis : annulez d''abord le changement plus récent.';
    end if;
    if v_value is null then
        delete from kind_settings where kind = v_kind and key = v_key;
    else
        insert into kind_settings (kind, key, value, set_by)
        values (v_kind, v_key, v_value, auth.uid())
        on conflict (kind, key) do update
            set value = excluded.value, set_by = excluded.set_by, set_at = now();
    end if;
end;
$$;

-- ------------------------------------------------------------
-- 6. The request page
-- ------------------------------------------------------------
-- What the page asks, for the person asking (and the platform's editor).
-- Null: today's page.
create or replace function application_form()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select s.value from platform_settings s
     where s.key = 'application_form' and jsonb_typeof(s.value) = 'object';
$$;

-- Sets the page: {welcome, kinds, questions: [{id, label, help, required,
-- type, options}]}, checked and written back in a clean shape. Null or {}
-- returns the page to today's. Logged with its undo.
create or replace function platform_set_application_form(p_form jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_in       jsonb := case when p_form = 'null'::jsonb or p_form = '{}'::jsonb then null else p_form end;
    v_out      jsonb;
    v_before   jsonb;
    v_text     text;
    v_kinds    jsonb;
    v_qs       jsonb := '[]'::jsonb;
    v_ids      text[] := '{}';
    q          jsonb;
    v_id       text;
    v_label    text;
    v_help     text;
    v_type     text;
    v_opts     jsonb;
    v_opt      text;
    v_clean    jsonb;
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;

    if v_in is not null then
        if jsonb_typeof(v_in) <> 'object' then
            raise exception 'La page de demande est mal formée.';
        end if;
        v_out := '{}'::jsonb;

        v_text := nullif(btrim(coalesce(v_in ->> 'welcome', '')), '');
        if v_text is not null then
            if char_length(v_text) > 600 then
                raise exception 'Le mot d''accueil fait 600 caractères au plus.';
            end if;
            v_out := v_out || jsonb_build_object('welcome', v_text);
        end if;

        if v_in ? 'kinds' and v_in -> 'kinds' <> 'null'::jsonb then
            if jsonb_typeof(v_in -> 'kinds') <> 'array'
               or exists (select 1 from jsonb_array_elements_text(v_in -> 'kinds') k
                           where k not in ('retail', 'farm', 'association')) then
                raise exception 'Les types proposés sont boutique, ferme ou association.';
            end if;
            select jsonb_agg(k order by array_position(array['association', 'farm', 'retail'], k))
              into v_kinds
              from (select distinct k from jsonb_array_elements_text(v_in -> 'kinds') k) d;
            if v_kinds is null then
                raise exception 'Proposez au moins un type d''activité.';
            end if;
            -- All three is today's page: no list kept.
            if jsonb_array_length(v_kinds) < 3 then
                v_out := v_out || jsonb_build_object('kinds', v_kinds);
            end if;
        end if;

        if v_in ? 'questions' and v_in -> 'questions' <> 'null'::jsonb then
            if jsonb_typeof(v_in -> 'questions') <> 'array' then
                raise exception 'Les questions sont une liste.';
            end if;
            if jsonb_array_length(v_in -> 'questions') > 12 then
                raise exception 'Douze questions au plus.';
            end if;
            for q in select value from jsonb_array_elements(v_in -> 'questions') loop
                if jsonb_typeof(q) <> 'object' then
                    raise exception 'Une question est mal formée.';
                end if;
                v_label := nullif(btrim(coalesce(q ->> 'label', '')), '');
                if v_label is null then
                    raise exception 'Chaque question a son intitulé.';
                end if;
                if char_length(v_label) > 120 then
                    raise exception 'Un intitulé fait 120 caractères au plus.';
                end if;
                v_help := nullif(btrim(coalesce(q ->> 'help', '')), '');
                if v_help is not null and char_length(v_help) > 200 then
                    raise exception 'Une aide fait 200 caractères au plus.';
                end if;
                v_type := coalesce(nullif(q ->> 'type', ''), 'text');
                if v_type not in ('text', 'choice', 'number', 'yesno') then
                    raise exception 'Une question est un texte, un choix, un nombre ou oui-non.';
                end if;
                v_opts := null;
                if v_type = 'choice' then
                    if jsonb_typeof(q -> 'options') <> 'array' then
                        raise exception 'Une question à choix a de 2 à 12 réponses.';
                    end if;
                    v_opts := '[]'::jsonb;
                    for v_opt in select btrim(o) from jsonb_array_elements_text(q -> 'options') o loop
                        if v_opt = '' then
                            continue;
                        end if;
                        if char_length(v_opt) > 60 then
                            raise exception 'Une réponse proposée fait 60 caractères au plus.';
                        end if;
                        if v_opts ? v_opt then
                            raise exception 'Une réponse proposée ne se répète pas.';
                        end if;
                        v_opts := v_opts || to_jsonb(v_opt);
                    end loop;
                    if jsonb_array_length(v_opts) < 2 or jsonb_array_length(v_opts) > 12 then
                        raise exception 'Une question à choix a de 2 à 12 réponses.';
                    end if;
                end if;
                -- A question keeps its id, so answers already given still
                -- name it; a new one gets its own.
                v_id := q ->> 'id';
                if v_id is null or v_id !~ '^[a-z0-9_-]{1,40}$' or v_id = any (v_ids) then
                    v_id := 'q' || substr(md5(random()::text || clock_timestamp()::text), 1, 8);
                end if;
                v_ids := v_ids || v_id;
                v_clean := jsonb_build_object(
                    'id', v_id, 'label', v_label, 'type', v_type,
                    'required', coalesce(q -> 'required' = 'true'::jsonb, false));
                if v_help is not null then
                    v_clean := v_clean || jsonb_build_object('help', v_help);
                end if;
                if v_opts is not null then
                    v_clean := v_clean || jsonb_build_object('options', v_opts);
                end if;
                v_qs := v_qs || jsonb_build_array(v_clean);
            end loop;
            if jsonb_array_length(v_qs) > 0 then
                v_out := v_out || jsonb_build_object('questions', v_qs);
            end if;
        end if;
        v_in := nullif(v_out, '{}'::jsonb);
    end if;

    select s.value into v_before from platform_settings s where s.key = 'application_form';
    if v_before is not distinct from v_in then
        return null;
    end if;
    if v_in is null then
        delete from platform_settings where key = 'application_form';
    else
        insert into platform_settings (key, value) values ('application_form', v_in)
        on conflict (key) do update set value = excluded.value;
    end if;

    return platform_log_action(
        null,
        'application_form',
        case when v_in is null then 'Page de demande remise comme avant'
             else 'Page de demande modifiée — '
                  || coalesce(jsonb_array_length(v_in -> 'questions'), 0) || ' question(s), '
                  || coalesce((select string_agg(case k when 'retail' then 'boutique'
                                                         when 'farm' then 'ferme'
                                                         else 'association' end, ', ')
                                 from jsonb_array_elements_text(v_in -> 'kinds') k),
                              'tous les types')
        end,
        jsonb_build_object('form', v_before),
        jsonb_build_object('form', v_in),
        'platform_restore_application_form',
        jsonb_build_object('form', v_before, 'expect', v_in));
end;
$$;

create or replace function platform_restore_application_form(p_args jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_form jsonb := nullif(p_args -> 'form', 'null'::jsonb);
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    if (select s.value from platform_settings s where s.key = 'application_form')
       is distinct from nullif(p_args -> 'expect', 'null'::jsonb) then
        raise exception 'Ce réglage a changé depuis : annulez d''abord le changement plus récent.';
    end if;
    if v_form is null then
        delete from platform_settings where key = 'application_form';
    else
        insert into platform_settings (key, value) values ('application_form', v_form)
        on conflict (key) do update set value = excluded.value;
    end if;
end;
$$;

-- 101's apply_for_org, with the page's checks and its answers: the kind
-- must be one the page offers, each required question answered, each
-- answer of its type. With no page set, 101's exactly (answers null).
-- p_answers is {question id: answer}; what is kept is the snapshot.
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
    v_actor   uuid := auth.uid();
    v_name    text := nullif(btrim(coalesce(p_name, '')), '');
    v_slug    text := nullif(lower(btrim(coalesce(p_slug, ''))), '');
    v_profile text := coalesce(nullif(btrim(coalesce(p_profile, '')), ''), 'generic');
    v_problem text;
    v_id      uuid;
    v_full    text;
    v_phone   text;
    v_email   text;
    v_form    jsonb := application_form();
    v_answers jsonb;
    q         jsonb;
    v_raw     jsonb;
    v_val     jsonb;
    v_text    text;
begin
    if v_actor is null then
        raise exception 'apply_for_org() needs a signed-in caller';
    end if;

    if v_name is null then
        raise exception 'A business needs a name';
    end if;

    v_problem := org_slug_problem(v_slug);
    if v_problem is not null then
        raise exception '%', v_problem;
    end if;

    if exists (select 1 from orgs where slug = v_slug) then
        raise exception 'That address is already taken.';
    end if;

    -- The page Mara set: the kinds it offers, its questions.
    if v_form is not null then
        if jsonb_typeof(v_form -> 'kinds') = 'array'
           and not ((v_form -> 'kinds') ? (case when v_profile = 'church' then 'association'
                                               else v_profile end)) then
            raise exception 'Ce type d''activité ne peut pas être demandé pour l''instant.';
        end if;
        v_answers := '[]'::jsonb;
        for q in select value from jsonb_array_elements(
                     case when jsonb_typeof(v_form -> 'questions') = 'array'
                          then v_form -> 'questions' else '[]'::jsonb end) loop
            v_raw := case when jsonb_typeof(p_answers) = 'object' then p_answers -> (q ->> 'id') end;
            v_val := null;
            if v_raw is not null and v_raw <> 'null'::jsonb then
                v_text := btrim(v_raw #>> '{}');
                if q ->> 'type' = 'yesno' then
                    if jsonb_typeof(v_raw) = 'boolean' then
                        v_val := v_raw;
                    elsif lower(v_text) in ('oui', 'true') then
                        v_val := 'true'::jsonb;
                    elsif lower(v_text) in ('non', 'false') then
                        v_val := 'false'::jsonb;
                    elsif v_text <> '' then
                        raise exception 'Répondez par oui ou par non : %', q ->> 'label';
                    end if;
                elsif v_text <> '' then
                    if q ->> 'type' = 'number' then
                        v_text := replace(replace(v_text, ' ', ''), ',', '.');
                        if v_text !~ '^-?[0-9]{1,12}([.][0-9]{1,4})?$' then
                            raise exception 'Répondez en chiffres : %', q ->> 'label';
                        end if;
                        v_val := to_jsonb(v_text::numeric);
                    elsif q ->> 'type' = 'choice' then
                        if not coalesce((q -> 'options') ? v_text, false) then
                            raise exception 'Choisissez une des réponses proposées : %', q ->> 'label';
                        end if;
                        v_val := to_jsonb(v_text);
                    else
                        if char_length(v_text) > 500 then
                            raise exception 'Une réponse fait 500 caractères au plus.';
                        end if;
                        v_val := to_jsonb(v_text);
                    end if;
                end if;
            end if;
            if v_val is null and coalesce(q -> 'required' = 'true'::jsonb, false) then
                raise exception 'Réponse obligatoire : %', q ->> 'label';
            end if;
            if v_val is not null then
                v_answers := v_answers || jsonb_build_array(jsonb_build_object(
                    'id', q ->> 'id', 'label', q ->> 'label', 'type', q ->> 'type',
                    'value', v_val));
            end if;
        end loop;
        v_answers := nullif(v_answers, '[]'::jsonb);
    end if;

    -- Who this is, as the platform will see it in the queue: the profile
    -- first, then the account, then what an older build sent.
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
        contact_name, contact_phone, contact_email, description, answers
    )
    values (
        v_actor, v_name, v_slug,
        v_profile,
        coalesce(nullif(btrim(coalesce(p_currency, '')), ''), 'XOF'),
        v_full,
        coalesce(v_phone, nullif(btrim(coalesce(p_phone, '')), '')),
        coalesce(v_email, nullif(btrim(coalesce(p_email, '')), '')),
        nullif(btrim(coalesce(p_description, '')), ''),
        v_answers
    )
    on conflict (applicant_id) where status = 'pending'
    do update set
        name          = excluded.name,
        slug          = excluded.slug,
        profile       = excluded.profile,
        currency      = excluded.currency,
        description   = excluded.description,
        contact_name  = excluded.contact_name,
        contact_phone = excluded.contact_phone,
        contact_email = excluded.contact_email,
        answers       = excluded.answers,
        created_at    = now()
    returning id into v_id;

    return v_id;
end;
$$;

-- 101's signature, for an older build: the same checks, no answers — so a
-- page with a required question is not walked past.
create or replace function apply_for_org(
    p_name        text,
    p_slug        text,
    p_profile     text default 'generic',
    p_currency    text default 'XOF',
    p_description text default null,
    p_phone       text default null,
    p_email       text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    return apply_for_org(p_name, p_slug, p_profile, p_currency, p_description,
                         p_phone, p_email, null::jsonb);
end;
$$;

-- The Demandes cards: 017's queue with the answers. A new function (jsonb)
-- rather than 017's table grown, which a bundle re-run could not replace.
create or replace function platform_pending_applications()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object(
                   'id', a.id,
                   'applicant_id', a.applicant_id,
                   'applicant', coalesce(a.contact_name, p.full_name),
                   'name', a.name,
                   'slug', a.slug,
                   'profile', a.profile,
                   'currency', a.currency,
                   'contact_phone', a.contact_phone,
                   'contact_email', a.contact_email,
                   'description', a.description,
                   'answers', coalesce(a.answers, '[]'::jsonb),
                   'created_at', a.created_at) order by a.created_at)
          from org_applications a
          left join profiles p on p.id = a.applicant_id
         where a.status = 'pending'), '[]'::jsonb);
end;
$$;

-- The applicant hears the decision, and the journal keeps it. A bell or a
-- journal line never costs the decision.
create or replace function trg_application_decided()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if old.status <> 'pending' or new.status = old.status then
        return new;
    end if;
    begin
        if new.status = 'approved' then
            insert into notifications (recipient_id, org_id, kind, message, params)
            values (new.applicant_id, new.org_id, 'application_approved',
                    'Votre demande est acceptée : ' || new.name || ' est ouverte.',
                    jsonb_build_object('to', 'applicant', 'name', new.name));
        elsif new.status = 'rejected' then
            insert into notifications (recipient_id, org_id, kind, message, params)
            values (new.applicant_id, null, 'application_refused',
                    'Votre demande pour ' || new.name || ' est refusée : '
                        || coalesce(new.decision_note, '') ,
                    jsonb_build_object('to', 'applicant', 'name', new.name,
                                       'reason', new.decision_note));
        end if;
    exception when others then
        null;
    end;
    begin
        if caller_is_platform_admin() then
            perform platform_log_action(
                new.org_id,
                'application',
                case when new.status = 'approved'
                     then 'Demande acceptée : ' || new.name || ' (' || new.slug || ')'
                     else 'Demande refusée : ' || new.name || ' — ' || coalesce(new.decision_note, '') end,
                jsonb_build_object('status', old.status),
                jsonb_build_object('status', new.status, 'note', new.decision_note,
                                   'application', new.id),
                null, null);
        end if;
    exception when others then
        null;
    end;
    return new;
end;
$$;

drop trigger if exists application_decided on org_applications;
create trigger application_decided
after update of status on org_applications
for each row execute function trg_application_decided();

insert into platform_undo_fns (fn) values
    ('platform_restore_kind_setting'),
    ('platform_restore_application_form')
on conflict (fn) do nothing;

-- ------------------------------------------------------------
-- Grants: born closed (063); each opened to whom it is for.
-- ------------------------------------------------------------
revoke execute on function kind_setting_catalog()                    from public;
revoke execute on function kind_setup_steps(text)                    from public;
revoke execute on function kind_setting(text, text)                  from public;
revoke execute on function org_kind_limit(uuid, text, int)           from public;
revoke execute on function vitrine_default_style(uuid)               from public;
revoke execute on function setup_steps_off(uuid)                     from public;
revoke execute on function kind_setting_words(text, jsonb)           from public;
revoke execute on function platform_kind_models(text)                from public;
revoke execute on function platform_set_kind_setting(text, text, jsonb) from public;
revoke execute on function platform_restore_kind_setting(jsonb)      from public;
revoke execute on function application_form()                        from public;
revoke execute on function platform_set_application_form(jsonb)      from public;
revoke execute on function platform_restore_application_form(jsonb)  from public;
revoke execute on function apply_for_org(text, text, text, text, text, text, text, jsonb) from public;
revoke execute on function apply_for_org(text, text, text, text, text, text, text) from public;
revoke execute on function platform_pending_applications()           from public;
revoke execute on function trg_application_decided()                 from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function kind_setting_catalog()                    from anon;
        revoke execute on function kind_setup_steps(text)                    from anon;
        revoke execute on function kind_setting(text, text)                  from anon;
        revoke execute on function org_kind_limit(uuid, text, int)           from anon;
        revoke execute on function vitrine_default_style(uuid)               from anon;
        revoke execute on function setup_steps_off(uuid)                     from anon;
        revoke execute on function kind_setting_words(text, jsonb)           from anon;
        revoke execute on function platform_kind_models(text)                from anon;
        revoke execute on function platform_set_kind_setting(text, text, jsonb) from anon;
        revoke execute on function platform_restore_kind_setting(jsonb)      from anon;
        revoke execute on function application_form()                        from anon;
        revoke execute on function platform_set_application_form(jsonb)      from anon;
        revoke execute on function platform_restore_application_form(jsonb)  from anon;
        revoke execute on function apply_for_org(text, text, text, text, text, text, text, jsonb) from anon;
        revoke execute on function apply_for_org(text, text, text, text, text, text, text) from anon;
        revoke execute on function platform_pending_applications()           from anon;
        revoke execute on function trg_application_decided()                 from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: read by the functions above, as their owner.
        revoke execute on function kind_setting_catalog()                    from authenticated;
        revoke execute on function kind_setup_steps(text)                    from authenticated;
        revoke execute on function kind_setting(text, text)                  from authenticated;
        revoke execute on function org_kind_limit(uuid, text, int)           from authenticated;
        revoke execute on function vitrine_default_style(uuid)               from authenticated;
        revoke execute on function kind_setting_words(text, jsonb)           from authenticated;
        revoke execute on function platform_restore_kind_setting(jsonb)      from authenticated;
        revoke execute on function platform_restore_application_form(jsonb)  from authenticated;
        revoke execute on function trg_application_decided()                 from authenticated;
        -- The doors; each checks who is asking (the platform, a member, the
        -- signed-in applicant).
        grant execute on function setup_steps_off(uuid)                      to authenticated;
        grant execute on function platform_kind_models(text)                 to authenticated;
        grant execute on function platform_set_kind_setting(text, text, jsonb) to authenticated;
        grant execute on function application_form()                         to authenticated;
        grant execute on function platform_set_application_form(jsonb)       to authenticated;
        grant execute on function apply_for_org(text, text, text, text, text, text, text, jsonb) to authenticated;
        grant execute on function apply_for_org(text, text, text, text, text, text, text) to authenticated;
        grant execute on function platform_pending_applications()            to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
