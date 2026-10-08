-- ============================================================
-- 111_create_my_business.sql — a person creates their business, at once,
-- with no request to approve.
--
-- The owner: « All 3 proposals are approved » — « … no request for
-- business creation. » Until now somebody starting a business filled in a
-- request (017, 101, 107's apply_for_org) and waited for Mara to approve it
-- (approve_org_application). Now they answer a few questions, one per
-- screen, and the business exists the moment they tap « Créer mon
-- activité »: they are its owner and walk straight into its first setup
-- (091's, 102's for an association).
--
--   1. create_my_business(...): the one door, for a signed-in person. It
--      checks everything the approval used to: a kind the creation page
--      offers (107's application_form — its welcome text, kinds and extra
--      questions now shape the creation flow), the name, the address
--      (org_slug_problem, not taken), what the business does (a shop's or
--      a farm's line of trade, an association's kind of 102), its town and
--      area, its phone, its currency, the page's questions answered as 107
--      checks them. The business is made by the very path create_org takes
--      — org_create_core: the business, its owner, its starting chart of
--      accounts — so it is exactly what Mara's own « Nouvelle entreprise »
--      makes; 107's vitrine defaults are read-time and apply as to any
--      business never dressed. Its town, area, phone and sentence are
--      written where the business keeps them (orgs.city, address, phone,
--      storefront_blurb; association_kind for an association), so the
--      setup and the vitrine start from them. The answers and the line of
--      trade are kept in business_creations — the history Mara reads —,
--      and the creation is written in the platform's journal.
--   2. Protection without approval:
--        * one free business per person: a second still needs Mara Pro on
--          one already owned — 099's second_business_locked, asked here, on
--          the server; two taps at once cannot make two (a per-person lock
--          for the transaction);
--        * platform_settings.create_phone_verified, OFF as installed (as
--          109's order_phone_verified): on, an account with no number
--          proved on WhatsApp (auth.users.phone_confirmed_at) is refused
--          « Vérifiez d'abord votre numéro WhatsApp » before anything is
--          written. Listed in Réglages, changed through 105's
--          platform_set_setting (oui/non, journaled, undone);
--        * a new vitrine reaches the street only once it meets its minimum
--          — 092's and 107's rule, unchanged: storefront_open and the
--          directory still ask vitrine_min.
--   3. my_business_start(): what the app asks before the first screen —
--      may this person create one now (or does a second need Pro), is a
--      proved number asked and which one they have (the phone screen is
--      prefilled with it), and the creation page Mara set.
--      business_address_check(slug): the address as it is typed, said at
--      once — its problem, or taken, with a free one to suggest.
--   4. create_org (035) is rebuilt on org_create_core and keeps its door
--      (a platform admin only). One fix on the way: a farm made by Mara's
--      « Nouvelle entreprise » got the generic chart (Cash, Sales,
--      Purchases…) — create_org had no farm branch since 011, while every
--      farm approved from a request got 019's farm chart. org_create_core
--      gives a farm the farm chart, whoever makes it. No existing business
--      is touched.
--   5. The approval path, for people, ends. Nothing in the new app files a
--      request or approves one; apply_for_org, approve_org_application and
--      reject_org_application stay, untouched, for an older app until the
--      new one is live. A person who still had a request waiting and now
--      creates directly has that request closed as « approved » with the
--      business it became, so an older app can never approve it into a
--      second business. The command center's « Demandes » becomes
--      « Activités créées »: platform_created_businesses() lists the
--      businesses people created (with their answers), and keeps the
--      requests of before readable (approved or refused, with the reason).
--   6. À faire (105's platform_todo, rebuilt from 105, the only definition):
--      « Nouvelles activités (7 j) » ('new_7'), the businesses created in
--      the last seven days, and platform_todo_list('new_7') behind it.
--      'applications' stays in the answer for an older app. 'reports_open'
--      is 113's « Signalements » (builder K's problem_reports), read only
--      when that table exists — 111 stands live with or without 113.
--
-- Shops ('retail'), farms and associations (a legacy 'church' is created
-- as an association): each kind is created here, each with its own line
-- of trade and its own walkthrough. Generic is no longer offered.
--
-- P1: nothing an existing store, farm, association or vitrine shows
-- changes — no existing row is written (one setting row is added, off);
-- create_org makes what it made for a shop and an association, and the
-- farm chart for a farm (4); the other functions are new.
--
-- Born closed (063): the internals are revoked from every app role; the
-- doors are the signed-in person's (each checks auth.uid()) or the
-- platform's (each checks caller_is_platform_admin). Re-runnable: a table
-- and a column if not exists, functions replaced in place, the setting
-- inserted « on conflict do nothing ».
-- ============================================================

do $$
begin
    if to_regprocedure('public.application_form()') is null
       or to_regprocedure('public.second_business_locked(uuid)') is null
       or to_regprocedure('public.my_verified_phone()') is null
       or to_regprocedure('public.platform_set_setting(text, jsonb)') is null
       or to_regclass('public.platform_actions') is null then
        raise exception '111 needs 099 (second_business_locked), 105 (platform_set_setting), 107 (application_form) and 109 (my_verified_phone) applied first';
    end if;
end $$;

-- ------------------------------------------------------------
-- 1. The switch, off
-- ------------------------------------------------------------
insert into platform_settings (key, value) values ('create_phone_verified', 'false')
on conflict (key) do nothing;

-- On only when the platform said oui; anything else is off.
create or replace function create_phone_required()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((select value = 'true'::jsonb from platform_settings
                      where key = 'create_phone_verified'), false);
$$;

-- ------------------------------------------------------------
-- 2. What a creation keeps: the history Mara reads
-- ------------------------------------------------------------
create table if not exists business_creations (
    org_id        uuid primary key references orgs(id) on delete cascade,
    created_by    uuid references profiles(id) on delete set null,
    created_at    timestamptz not null default now(),
    -- A shop's or a farm's line of trade; an association's kind (102).
    activity      text,
    about         text,
    city          text,
    area          text,
    phone         text,
    -- The creation page's questions as they were asked and answered, as
    -- 107 keeps a request's: [{id, label, type, value}]. Null: none asked.
    answers       jsonb,
    -- Who it was, as the platform reads it then.
    contact_name  text,
    contact_phone text,
    contact_email text
);
create index if not exists business_creations_by_time on business_creations (created_at desc);
alter table business_creations enable row level security;
comment on table business_creations is
    'A business a person created themselves (111): its line of trade, its place, its '
    'phone and the creation page''s answers. Written by create_my_business() only, '
    'read through platform_created_businesses().';

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on business_creations from authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on business_creations from anon;
    end if;
end $$;

-- The lines of trade a creation offers, per kind (the app's chips, in its
-- order). An association's are 102's kinds.
create or replace function business_activities(p_kind text)
returns text[]
language sql
immutable
set search_path = public
as $$
    select case p_kind
        when 'retail' then array['alimentation', 'telephonie', 'vetements', 'beaute',
                                 'restaurant', 'quincaillerie', 'autre']
        when 'farm' then array['volaille', 'elevage', 'maraichage', 'cereales', 'mixte', 'autre']
        when 'association' then array['tontine', 'eglise', 'groupement', 'culturelle',
                                      'sportive', 'autre']
        else array[]::text[] end;
$$;

-- ------------------------------------------------------------
-- 3. One way a business is made
-- ------------------------------------------------------------
-- What create_org (035) did, apart from its door: the business, its
-- owner, its starting chart — and a farm's own chart (019), which 035's
-- create_org left out. Internal: create_org and create_my_business call it
-- as its owner.
create or replace function org_create_core(
    p_owner    uuid,
    p_name     text,
    p_slug     text,
    p_profile  text,
    p_currency text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org_id uuid;
begin
    insert into orgs (name, slug, profile, default_currency)
    values (p_name, p_slug, p_profile, p_currency)
    returning id into v_org_id;

    insert into memberships (org_id, user_id, role, scope_kind, scope_id)
    values (v_org_id, p_owner, 'owner', 'org', v_org_id);

    if p_profile in ('church', 'association') then
        perform seed_church_accounts(v_org_id);
    elsif p_profile = 'retail' then
        perform seed_retail_accounts(v_org_id);
    elsif p_profile = 'farm' then
        perform seed_farm_accounts(v_org_id);
    else
        insert into accounts (org_id, code, name, type) values
            (v_org_id, '1000', 'Cash on Hand',        'asset'),
            (v_org_id, '1010', 'Bank Account',        'asset'),
            (v_org_id, '1020', 'Mobile Money',        'asset'),
            (v_org_id, '4000', 'Sales',                'income'),
            (v_org_id, '5000', 'Purchases',            'expense'),
            (v_org_id, '5010', 'Operating Expenses',   'expense')
        on conflict (org_id, code) do nothing;
    end if;

    return v_org_id;
end;
$$;

-- 035's create_org: the same door (a platform admin only), the same
-- signature and grant, made by org_create_core.
create or replace function create_org(
    p_name     text,
    p_slug     text,
    p_profile  text default 'generic',
    p_currency text default 'XOF'
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists(select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can create a new business';
    end if;
    return org_create_core(auth.uid(), p_name, p_slug, p_profile, p_currency);
end;
$$;

-- ------------------------------------------------------------
-- 4. The creation page's answers, checked as 107 checks a request's
-- ------------------------------------------------------------
-- p_answers is {question id: answer}. Returns the snapshot kept
-- ([{id, label, type, value}]), null when nothing was asked or answered;
-- raises on a required question left empty or an answer of the wrong
-- type — 107's apply_for_org rules, word for word.
create or replace function business_answers(p_form jsonb, p_answers jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
    v_answers jsonb := '[]'::jsonb;
    q         jsonb;
    v_raw     jsonb;
    v_val     jsonb;
    v_text    text;
begin
    if p_form is null or jsonb_typeof(p_form -> 'questions') <> 'array' then
        return null;
    end if;
    for q in select value from jsonb_array_elements(p_form -> 'questions') loop
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
    return nullif(v_answers, '[]'::jsonb);
end;
$$;

-- ------------------------------------------------------------
-- 5. Before the first screen, and the address as it is typed
-- ------------------------------------------------------------
create or replace function my_business_start()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_actor  uuid := auth.uid();
    v_locked boolean;
begin
    if v_actor is null then
        raise exception 'Connectez-vous pour créer votre activité.';
    end if;
    v_locked := second_business_locked(v_actor);
    return jsonb_build_object(
        'owns', (select count(*) from memberships m join orgs o on o.id = m.org_id
                  where m.user_id = v_actor and m.role = 'owner' and o.archived_at is null),
        'locked', v_locked,
        'lock_message', case when v_locked then path_lock_message('second_business') end,
        'phone_required', create_phone_required(),
        'verified_phone', my_verified_phone(),
        'form', application_form());
end;
$$;

-- The address as typed: its problem (org_slug_problem's words), or taken
-- — with the first free one after it, « -2 » to « -20 ». Signed-in only:
-- the street already shows every open vitrine's address; this says no
-- more than that one is in use.
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

-- ------------------------------------------------------------
-- 6. The door
-- ------------------------------------------------------------
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

    if v_activity is null then
        raise exception 'Dites ce que fait votre activité.';
    end if;
    if not v_activity = any (business_activities(v_profile)) then
        raise exception 'Choisissez ce que fait votre activité dans la liste.';
    end if;
    if char_length(coalesce(v_about, '')) > 160 then
        raise exception 'Une phrase de 160 caractères au plus.';
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

-- ------------------------------------------------------------
-- 7. « Activités créées »: the businesses people created, and the
--    requests of before
-- ------------------------------------------------------------
create or replace function platform_created_businesses(p_limit int default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_limit int := least(greatest(coalesce(p_limit, 100), 1), 500);
begin
    if not caller_is_platform_admin() then
        raise exception 'Réservé à la plateforme';
    end if;
    return jsonb_build_object(
        'items', coalesce((
            select jsonb_agg(r order by r ->> 'at' desc) from (
                select r from (
                    -- Created by the person (111).
                    select jsonb_build_object(
                               'how', 'created',
                               'org_id', o.id,
                               'name', o.name,
                               'slug', o.slug,
                               'profile', o.profile,
                               'archived', o.archived_at is not null,
                               'activity', c.activity,
                               'about', c.about,
                               'city', c.city,
                               'area', c.area,
                               'phone', c.phone,
                               'person', c.contact_name,
                               'person_phone', c.contact_phone,
                               'person_email', c.contact_email,
                               'answers', coalesce(c.answers, '[]'::jsonb),
                               'at', c.created_at) as r
                      from business_creations c
                      join orgs o on o.id = c.org_id
                    union all
                    -- Asked for, and decided by Mara (017–107): kept readable.
                    select jsonb_build_object(
                               'how', a.status,
                               'org_id', a.org_id,
                               'name', coalesce(o.name, a.name),
                               'slug', coalesce(o.slug, a.slug),
                               'profile', coalesce(o.profile, a.profile),
                               'archived', o.archived_at is not null,
                               'about', a.description,
                               'person', a.contact_name,
                               'person_phone', a.contact_phone,
                               'person_email', a.contact_email,
                               'note', a.decision_note,
                               'answers', coalesce(a.answers, '[]'::jsonb),
                               'at', coalesce(a.reviewed_at, a.created_at)) as r
                      from org_applications a
                      left join orgs o on o.id = a.org_id
                     where a.status in ('approved', 'rejected')
                       and not exists (select 1 from business_creations c
                                        where c.org_id = a.org_id)
                ) all_rows
                order by r ->> 'at' desc
                limit v_limit) x), '[]'::jsonb),
        -- Requests an older app sent, still waiting: the person can now
        -- create their business themselves.
        'old_requests', (select count(*) from org_applications where status = 'pending'));
end;
$$;

-- ------------------------------------------------------------
-- 8. À faire: 105's, with the new businesses (and 113's reports)
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
    v_reports int := 0;
begin
    perform platform_only();
    -- 113's « Signaler un problème » (problem_reports), when it is there.
    if to_regclass('public.problem_reports') is not null then
        execute 'select count(*)::int from problem_reports where status = ''open''' into v_reports;
    end if;
    return jsonb_build_object(
        -- An older app's « Demandes »: requests still waiting.
        'applications',   (select count(*) from org_applications where status = 'pending'),
        -- The businesses created in the last seven days (111), Mara's
        -- vitrines d'exemple aside.
        'new_7',          (select count(*) from orgs
                            where archived_at is null and not showcase
                              and created_at > now() - interval '7 days'),
        'pro_paid',       (select count(*) from plan_requests where handled_at is null),
        'spots_paid',     (select count(*) from promotions where status = 'paid_claimed'),
        'spots_asked',    (select count(*) from promotions where status = 'requested'),
        'couriers',       (select count(*) from couriers where status = 'pending'),
        -- As 072 counted them: waiting over 2 hours, on the road over 3. A
        -- « picked_up » order is finished (collected at the counter).
        'orders_stuck',   (select count(*) from orders
                            where (status = 'pending' and created_at < now() - interval '2 hours')
                               or (status = 'in_transit' and updated_at < now() - interval '3 hours')),
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
        'payouts_failed', (select count(*) from wave_payments where payout_status = 'failed'),
        -- A Pro tool a rule hides, back to hidden when its payment ended
        -- (104's feature_pay_watch), still hidden now.
        'features_lapsed', (select count(*) from feature_pay_watch w join orgs o on o.id = w.org_id
                             where w.state = 'lapsed' and o.archived_at is null
                               and feature_hidden(w.org_id, w.feature)),
        'reports_open',   v_reports
    );
end;
$$;

-- 105's rows behind a count, with the new businesses.
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
    when 'new_7' then
        select jsonb_agg(r order by r->>'at' desc) into v_rows from (
            select jsonb_build_object('org_id', o.id, 'org_name', o.name, 'profile', o.profile,
                                      'owner', w.owner_name, 'city', o.city,
                                      'by_person', c.org_id is not null,
                                      'at', o.created_at) as r
              from orgs o
              left join business_creations c on c.org_id = o.id
              left join lateral (select coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                                                 p.full_name) as owner_name
                                   from memberships m join profiles p on p.id = m.user_id
                                  where m.org_id = o.id and m.role = 'owner'
                                  order by m.created_at limit 1) w on true
             where o.archived_at is null and not o.showcase
               and o.created_at > now() - interval '7 days'
             order by o.created_at desc limit 200) x;
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
                or (d.status = 'in_transit' and d.updated_at < now() - interval '3 hours')
             order by d.created_at limit 200) x;
    when 'features_lapsed' then
        select jsonb_agg(r order by r->>'at') into v_rows from (
            select jsonb_build_object('org_id', o.id, 'org_name', o.name, 'profile', o.profile,
                                      'feature', w.feature, 'label', c.label,
                                      'at', w.since) as r
              from feature_pay_watch w
              join orgs o on o.id = w.org_id
              join feature_catalog c on c.key = w.feature
             where w.state = 'lapsed' and o.archived_at is null
               and feature_hidden(w.org_id, w.feature)
             order by w.since limit 200) x;
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
-- Grants: born closed (063); each opened to whom it is for.
-- ------------------------------------------------------------
revoke execute on function create_phone_required()                     from public;
revoke execute on function business_activities(text)                   from public;
revoke execute on function org_create_core(uuid, text, text, text, text) from public;
revoke execute on function create_org(text, text, text, text)          from public;
revoke execute on function business_answers(jsonb, jsonb)              from public;
revoke execute on function my_business_start()                         from public;
revoke execute on function business_address_check(text)                from public;
revoke execute on function create_my_business(text, text, text, text, text, text, text, text, text, jsonb) from public;
revoke execute on function platform_created_businesses(int)            from public;
revoke execute on function platform_todo()                             from public;
revoke execute on function platform_todo_list(text)                    from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function create_phone_required()                     from anon;
        revoke execute on function business_activities(text)                   from anon;
        revoke execute on function org_create_core(uuid, text, text, text, text) from anon;
        revoke execute on function create_org(text, text, text, text)          from anon;
        revoke execute on function business_answers(jsonb, jsonb)              from anon;
        revoke execute on function my_business_start()                         from anon;
        revoke execute on function business_address_check(text)                from anon;
        revoke execute on function create_my_business(text, text, text, text, text, text, text, text, text, jsonb) from anon;
        revoke execute on function platform_created_businesses(int)            from anon;
        revoke execute on function platform_todo()                             from anon;
        revoke execute on function platform_todo_list(text)                    from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: read by the doors below, as their owner.
        revoke execute on function create_phone_required()                     from authenticated;
        revoke execute on function business_activities(text)                   from authenticated;
        revoke execute on function org_create_core(uuid, text, text, text, text) from authenticated;
        revoke execute on function business_answers(jsonb, jsonb)              from authenticated;
        -- The doors; each checks who is asking (a signed-in person, a
        -- platform admin).
        grant execute on function create_org(text, text, text, text)           to authenticated;
        grant execute on function my_business_start()                          to authenticated;
        grant execute on function business_address_check(text)                to authenticated;
        grant execute on function create_my_business(text, text, text, text, text, text, text, text, text, jsonb) to authenticated;
        grant execute on function platform_created_businesses(int)             to authenticated;
        grant execute on function platform_todo()                              to authenticated;
        grant execute on function platform_todo_list(text)                     to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
