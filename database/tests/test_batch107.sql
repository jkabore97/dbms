-- ============================================================
-- test_batch107.sql — the types of business and the request page (107).
--
-- The claims, for a shop, a farm and an association (and a legacy church)
-- alike:
--   P1. With no kind_settings row, no vitrine default, no walkthrough step
--       turned off and no request form, every number a business reads, its
--       vitrine (storefront, storefront_products, storefront_open, the
--       street's directory, the photo gate) and the paywall's terms are
--       exactly what the functions as 093–101 left them say: computed with
--       107 in place, then with the old definitions put back in the same
--       transaction, and compared. The request page asks what it asked and
--       keeps no answers.
--   2. A kind's own numbers are read by every reader — the free seat, the
--      photographed articles, the invoices a month, what opens a vitrine,
--      Le Chemin's articles step, the terms — and only for that kind;
--      cleared, the global number again.
--   3. Mara's vitrine default dresses only a vitrine never dressed, of that
--      kind, never a vitrine d'exemple; its cover is served by the photo
--      gate; the owner's first dressing takes over.
--   4. A kind's optional walkthrough steps turn off, never a required one;
--      a member reads their own kind's, a stranger nothing.
--   5. The request page: the kinds it offers, its questions and their
--      types, answered and kept as asked, an older build held to the same
--      page, the Demandes cards read the answers.
--   6. The applicant hears the decision; the journal keeps it.
--   P3. Only a platform admin changes anything here, every change is in the
--       journal and undoes once, a stale undo is refused, and the doors are
--       closed to the street and the internals to the app.
-- ============================================================
\set ON_ERROR_STOP on
\set mara     '''10710710-0000-0000-0000-000000000001'''
\set shopo    '''10710710-0000-0000-0000-000000000002'''
\set shop2o   '''10710710-0000-0000-0000-000000000003'''
\set farmo    '''10710710-0000-0000-0000-000000000004'''
\set assoo    '''10710710-0000-0000-0000-000000000005'''
\set churcho  '''10710710-0000-0000-0000-000000000006'''
\set proo     '''10710710-0000-0000-0000-000000000007'''
\set appl     '''10710710-0000-0000-0000-000000000008'''
\set stranger '''10710710-0000-0000-0000-000000000009'''
\set appl2    '''10710710-0000-0000-0000-000000000010'''
\set shop1    '''10700000-0000-0000-0000-000000000001'''
\set shop2    '''10700000-0000-0000-0000-000000000002'''
\set farm1    '''10700000-0000-0000-0000-000000000003'''
\set asso1    '''10700000-0000-0000-0000-000000000004'''
\set church1  '''10700000-0000-0000-0000-000000000005'''
\set pro1     '''10700000-0000-0000-0000-000000000006'''
\set show1    '''10700000-0000-0000-0000-000000000007'''
\set new1     '''10700000-0000-0000-0000-000000000008'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
-- Earlier suites re-apply older migrations over 107's functions (093, 098,
-- 100, 101…) and hand the app's roles every function: 107 again.
\i database/migrations/107_kinds_requests.sql

-- The platform's numbers as they stand live; earlier suites move them.
update platform_settings set value = '1'  where key = 'free_max_staff';
update platform_settings set value = '20' where key = 'free_max_invoices_month';
update platform_settings set value = '10' where key = 'free_photo_items';
update platform_settings set value = '8'  where key = 'vitrine_min_items';
update platform_settings set value = '1'  where key = 'vitrine_min_items_association';
update platform_settings set value = '1'  where key = 'vitrine_free_basics';
-- Le Chemin's doors open, so an invoice meets only the plan's cap.
update platform_settings set value = '1'  where key = 'path_gates_open';
delete from platform_settings where key = 'application_form';
delete from kind_settings;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:mara,     '+22610710001', '{"full_name": "Mara"}'),
    (:shopo,    '+22610710002', '{"full_name": "Awa Boutique"}'),
    (:shop2o,   '+22610710003', '{"full_name": "Bintou Boutique"}'),
    (:farmo,    '+22610710004', '{"full_name": "Fermier"}'),
    (:assoo,    '+22610710005', '{"full_name": "Trésorière"}'),
    (:churcho,  '+22610710006', '{"full_name": "Pasteur"}'),
    (:proo,     '+22610710007', '{"full_name": "Pro"}'),
    (:appl,     '+22610710008', '{"full_name": "Coumba Demande"}'),
    (:stranger, '+22610710009', '{"full_name": "Passant"}'),
    (:appl2,    '+22610710010', '{"full_name": "Deuxième Demande"}');
update profiles set is_platform_admin = true where id = :mara;
update profiles set first_name = 'Coumba', last_name = 'Demande' where id = :appl;

insert into orgs (id, name, slug, profile, default_currency, plan, storefront_enabled,
                  setup_done_at, showcase, storefront_style) values
    (:shop1,   'Boutique 107',   'boutique-107',   'retail',      'XOF', 'free', true, now(),  false, '{}'),
    (:shop2,   'Habillée 107',   'habillee-107',   'retail',      'XOF', 'free', true, now(),  false,
               '{"tagline": "Chez Bintou", "accent": "#B1541A"}'),
    (:farm1,   'Ferme 107',      'ferme-107',      'farm',        'XOF', 'free', true, now(),  false, '{}'),
    (:asso1,   'Entraide 107',   'entraide-107',   'association', 'XOF', 'free', true, now(),  false, '{}'),
    (:church1, 'Église 107',     'eglise-107',     'church',      'XOF', 'free', true, now(),  false, '{}'),
    (:pro1,    'Pro 107',        'pro-107',        'retail',      'XOF', 'pro',  true, now(),  false, '{}'),
    (:show1,   'Exemple 107',    'exemple-107',    'retail',      'XOF', 'pro',  true, now(),  true,  '{}'),
    (:new1,    'Neuve 107',      'neuve-107',      'retail',      'XOF', 'free', true, null,   false, '{}');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop1,   :shopo,   'owner', 'org', :shop1,   'full'),
    (:shop2,   :shop2o,  'owner', 'org', :shop2,   'full'),
    (:farm1,   :farmo,   'owner', 'org', :farm1,   'full'),
    (:asso1,   :assoo,   'owner', 'org', :asso1,   'full'),
    (:church1, :churcho, 'owner', 'org', :church1, 'full'),
    (:pro1,    :proo,    'owner', 'org', :pro1,    'full'),
    (:new1,    :shopo,   'owner', 'org', :new1,    'full');

-- Shelves: nine articles for each shop (three photographed), eight for the
-- farm (one), a service for the association and for the church.
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
select o.id, o.name || ' article ' || g, 500 + g, 5, true, true
  from orgs o cross join generate_series(1, 9) g
 where o.id in (:shop1, :shop2, :pro1, :show1, :new1);
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
select :farm1, 'Plateau ' || g, 2500, 10, true, true from generate_series(1, 8) g;
insert into products (org_id, name, sale_price, is_service, is_active, is_published) values
    (:asso1,   'Location de la salle', 15000, true, true, true),
    (:church1, 'Baptême',               5000, true, true, true);
-- Photos: the 2nd, 5th and 7th article of each shop (by name), the farm's 3rd.
insert into documents (org_id, r2_key, kind, uploaded_by, product_id)
select p.org_id, 'org/' || p.org_id || '/' || replace(p.name, ' ', '_') || '.jpg', 'product_photo',
       '10710710-0000-0000-0000-000000000002', p.id
  from products p
 where p.org_id in (:shop1, :shop2, :pro1, :show1, :new1)
   and (p.name like '% article 2' or p.name like '% article 5' or p.name like '% article 7');
insert into documents (org_id, r2_key, kind, uploaded_by, product_id)
select p.org_id, 'org/' || p.org_id || '/plateau3.jpg', 'product_photo',
       '10710710-0000-0000-0000-000000000004', p.id
  from products p where p.org_id = :farm1 and p.name = 'Plateau 3';
-- A delivery note filed on the shop's first article is paperwork, never a cover.
insert into documents (org_id, r2_key, kind, uploaded_by, product_id)
select p.org_id, 'org/' || p.org_id || '/bon.jpg', 'invoice',
       '10710710-0000-0000-0000-000000000002', p.id
  from products p where p.org_id = :shop1 and p.name = 'Boutique 107 article 1';

-- What a business sees, as one value: every number, the vitrine as the
-- street reads it, the terms. Read with nobody signed in (the street).
create function pg_temp.p1_snapshot() returns jsonb
language sql
as $$
    select jsonb_build_object(
        'orgs', (select jsonb_object_agg(o.slug, jsonb_build_object(
                     'free_workers', org_free_workers(o.id),
                     'photo_limit',  org_photo_limit(o.id),
                     'vitrine_min',  vitrine_min(o.id),
                     'path_goal',    path_goal(o.id, 'articles'),
                     'team',         team_seats(o.id),
                     'photos',       photo_state(o.id),
                     'checklist',    vitrine_checklist(o.id),
                     'open',         storefront_open(o.slug),
                     'storefront',   (select to_jsonb(s) from storefront(o.slug) s),
                     'products',     (select jsonb_agg(to_jsonb(p) order by p.name)
                                        from storefront_products(o.slug) p),
                     'photo_gate',   (select jsonb_object_agg(d.r2_key, storefront_photo_allowed(d.r2_key))
                                        from documents d where d.org_id = o.id)))
                   from orgs o where o.slug like '%-107'),
        'directory', (select jsonb_agg(to_jsonb(d) order by d.slug)
                        from storefront_directory() d where d.slug like '%-107'),
        'terms', plan_terms());
$$;

-- How many invoices a business may raise this month before the cap, and
-- what the cap says — tried, then rolled back.
create function pg_temp.invoice_cap(p_org uuid, p_user uuid) returns text
language plpgsql
as $$
declare
    n    int := 0;
    msg  text;
    cust uuid;
begin
    perform set_config('request.jwt.claim.sub', p_user::text, true);
    begin
        insert into customers (org_id, name) values (p_org, 'Client 107') returning id into cust;
        loop
            n := n + 1;
            exit when n > 60;
            insert into invoices (org_id, customer_id, number, total, created_by)
            values (p_org, cust, 'F107-' || n, 1000, p_user);
        end loop;
        raise exception 'no cap';
    exception when others then
        msg := sqlerrm;
    end;
    perform set_config('request.jwt.claim.sub', '', true);
    return (n - 1) || ' | ' || msg;
end;
$$;

-- An application as the queue keeps it, without its id and its time.
create function pg_temp.application_of(p_user uuid) returns jsonb
language sql
as $$
    select to_jsonb(a) - 'id' - 'created_at'
      from org_applications a where a.applicant_id = p_user and a.status = 'pending';
$$;

\echo ''
\echo '--- TEST P1: nothing set — every number, every vitrine, the terms and the request page as before 107 ---'
select set_config('request.jwt.claim.sub', '', false);
create temp table p1_after as
select pg_temp.p1_snapshot() as snap,
       pg_temp.invoice_cap('10700000-0000-0000-0000-000000000001', '10710710-0000-0000-0000-000000000002') as shop_cap,
       pg_temp.invoice_cap('10700000-0000-0000-0000-000000000004', '10710710-0000-0000-0000-000000000005') as asso_cap;
-- The request page, as the person asking meets it with 107 and no form.
do $$
begin
    perform set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000008', true);
    if application_form() is not null then
        raise exception 'FAIL: a request form is set before Mara set one';
    end if;
    perform apply_for_org('Atelier 107', 'atelier-107', 'retail', 'XOF', 'Couture', null, null);
    perform set_config('request.jwt.claim.sub', '', true);
end $$;
create temp table p1_apply_after as
select pg_temp.application_of('10710710-0000-0000-0000-000000000008') as app;
delete from org_applications where applicant_id = :appl;
do $$
declare
    s jsonb := (select snap from p1_after);
    o text;
begin
    if (select count(*) from jsonb_object_keys(s -> 'orgs')) <> 8 then
        raise exception 'FAIL: the snapshot misses businesses: %', s -> 'orgs';
    end if;
    -- The setup screens' read: nothing turned off, for every kind.
    for o in select id::text from orgs where slug like '%-107' loop
        if setup_steps_off(o::uuid) <> '[]'::jsonb then
            raise exception 'FAIL: a walkthrough step is off for % with no row', o;
        end if;
    end loop;
    if (s -> 'terms') ? 'kinds' then
        raise exception 'FAIL: the terms carry kinds with no kind row: %', s -> 'terms';
    end if;
    if (select app ->> 'answers' from p1_apply_after) is not null then
        raise exception 'FAIL: an application kept answers with no form';
    end if;
    raise notice 'PASS: with 107 and nothing set, no step off, no kinds in the terms, no answers kept';
end $$;

-- Before 107: the same transaction with the readers put back as 093–101
-- defined them (verbatim), the same reads, then rolled back.
begin;
-- org_free_workers as 100 left it
create or replace function org_free_workers(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case when org_setup_done(p_org_id)
                then greatest(plan_limit('free_max_staff', 1), 0) else 0 end;
$$;

-- org_photo_limit as 100 left it
create or replace function org_photo_limit(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case
        when org_plan(o.id) = 'pro' or o.showcase then null
        else greatest(plan_limit('free_photo_items', 10), 0) + o.photo_slots
    end
    from orgs o where o.id = p_org_id;
$$;

-- vitrine_min as 098 left it
create or replace function vitrine_min(p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case when o.profile in ('church', 'association')
                then greatest(cauris_param('vitrine_min_items_association', 1), 1)
                else cauris_param('vitrine_min_items', 8) end
      from orgs o where o.id = p_org_id;
$$;

-- path_goal as 097 left it
create or replace function path_goal(p_org uuid, p_step text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case p_step
        when 'contact'      then 2
        when 'articles'     then greatest(cauris_param('vitrine_min_items', 8), 1)
        when 'photos'       then 3
        when 'three_orders' then greatest(cauris_param('progress_credit_orders', 3), 0)
        when 'till_week'    then 7
        when 'log_week'     then 7
        else 1
    end;
$$;

-- plan_terms as 100 left it
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
    );
$$;

-- storefront as 093 left it
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

-- trg_cap_free_plan as 100 left it
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
        v_cap := plan_limit('free_max_invoices_month', 20);
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

-- apply_for_org as 101 left it
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
declare
    v_actor   uuid := auth.uid();
    v_name    text := nullif(btrim(coalesce(p_name, '')), '');
    v_slug    text := nullif(lower(btrim(coalesce(p_slug, ''))), '');
    v_problem text;
    v_id      uuid;
    v_full    text;
    v_phone   text;
    v_email   text;
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
        contact_name, contact_phone, contact_email, description
    )
    values (
        v_actor, v_name, v_slug,
        coalesce(nullif(btrim(coalesce(p_profile, '')), ''), 'generic'),
        coalesce(nullif(btrim(coalesce(p_currency, '')), ''), 'XOF'),
        v_full,
        coalesce(v_phone, nullif(btrim(coalesce(p_phone, '')), '')),
        coalesce(v_email, nullif(btrim(coalesce(p_email, '')), '')),
        nullif(btrim(coalesce(p_description, '')), '')
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
        created_at    = now()
    returning id into v_id;

    return v_id;
end;
$$;
-- 101 had one apply_for_org; 107's answers signature is not called here.
drop function apply_for_org(text, text, text, text, text, text, text, jsonb);
select set_config('request.jwt.claim.sub', '', true);
do $$
declare
    v_after   jsonb := (select snap from p1_after);
    v_before  jsonb := pg_temp.p1_snapshot();
    v_shop    text  := pg_temp.invoice_cap('10700000-0000-0000-0000-000000000001', '10710710-0000-0000-0000-000000000002');
    v_asso    text  := pg_temp.invoice_cap('10700000-0000-0000-0000-000000000004', '10710710-0000-0000-0000-000000000005');
    v_app     jsonb;
    k         text;
begin
    for k in select jsonb_object_keys(v_before -> 'orgs') loop
        if v_before -> 'orgs' -> k is distinct from v_after -> 'orgs' -> k then
            raise exception 'FAIL: % reads differently after 107: before % after %',
                k, v_before -> 'orgs' -> k, v_after -> 'orgs' -> k;
        end if;
    end loop;
    if v_before is distinct from v_after then
        raise exception 'FAIL: the street or the terms differ: before % after %', v_before, v_after;
    end if;
    if v_shop is distinct from (select shop_cap from p1_after)
       or v_asso is distinct from (select asso_cap from p1_after) then
        raise exception 'FAIL: the invoice cap moved: before % / % after % / %', v_shop, v_asso,
            (select shop_cap from p1_after), (select asso_cap from p1_after);
    end if;
    if v_shop not like '20 | Kaj Pro : la formule gratuite permet 20 factures par mois%' then
        raise exception 'FAIL: the cap is not 20 a month: %', v_shop;
    end if;
    perform set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000008', true);
    perform apply_for_org('Atelier 107', 'atelier-107', 'retail', 'XOF', 'Couture', null, null);
    perform set_config('request.jwt.claim.sub', '', true);
    v_app := pg_temp.application_of('10710710-0000-0000-0000-000000000008');
    if v_app is distinct from (select app from p1_apply_after) then
        raise exception 'FAIL: the application differs: before % after %', v_app, (select app from p1_apply_after);
    end if;
    raise notice 'PASS: P1 — for 8 businesses (shops, a farm, an association, a church, Pro, a vitrine d''exemple, one not set up) every number, storefront, storefront_products, storefront_open, the directory, the photo gate, the terms, the invoice cap and the application are identical before and after 107';
end $$;
rollback;

\echo ''
\echo '--- TEST 2: a kind''s own numbers, read by every reader, for that kind only; cleared, the global again ---'
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000001', true);
do $$
declare
    v_shop  uuid := '10700000-0000-0000-0000-000000000001';
    v_farm  uuid := '10700000-0000-0000-0000-000000000003';
    v_asso  uuid := '10700000-0000-0000-0000-000000000004';
    v_ch    uuid := '10700000-0000-0000-0000-000000000005';
    v_pro   uuid := '10700000-0000-0000-0000-000000000006';
    v_new   uuid := '10700000-0000-0000-0000-000000000008';
    v_act   uuid;
    m       jsonb;
begin
    -- The tab reads the kind's businesses and its numbers.
    m := platform_kind_models('retail');
    if (m ->> 'orgs')::int < 4 or (m ->> 'never_dressed')::int < 3
       or jsonb_array_length(m -> 'settings') <> 4
       or (select count(*) from jsonb_array_elements(m -> 'settings') e
            where e ->> 'key' = 'vitrine_min_items' and (e ->> 'global')::int = 8
              and e -> 'value' = 'null'::jsonb) <> 1 then
        raise exception 'FAIL: the shops'' tab reads %', m;
    end if;
    m := platform_kind_models('church');
    if m ->> 'kind' <> 'association'
       or (select string_agg(e ->> 'key', ',' order by e ->> 'key') from jsonb_array_elements(m -> 'settings') e)
          <> 'free_max_invoices_month,free_max_staff,free_photo_items,vitrine_min_items_association' then
        raise exception 'FAIL: the associations'' tab reads %', m;
    end if;

    v_act := platform_set_kind_setting('retail', 'free_photo_items', '12');
    perform platform_set_kind_setting('farm', 'free_max_staff', '"2"');
    perform platform_set_kind_setting('association', 'free_max_invoices_month', '1');
    perform platform_set_kind_setting('retail', 'vitrine_min_items', '3');
    perform platform_set_kind_setting('association', 'vitrine_min_items_association', '2');
    if v_act is null then
        raise exception 'FAIL: a kind setting returned no journal line';
    end if;
end $$;
-- What the businesses read, as their readers run (the owner of each).
reset role;
do $$
declare
    v_shop  uuid := '10700000-0000-0000-0000-000000000001';
    v_farm  uuid := '10700000-0000-0000-0000-000000000003';
    v_asso  uuid := '10700000-0000-0000-0000-000000000004';
    v_ch    uuid := '10700000-0000-0000-0000-000000000005';
    v_pro   uuid := '10700000-0000-0000-0000-000000000006';
    v_new   uuid := '10700000-0000-0000-0000-000000000008';
    m       jsonb;
begin
    if org_photo_limit(v_shop) <> 12 or org_photo_limit(v_farm) <> 10
       or org_photo_limit(v_asso) <> 10 or org_photo_limit(v_pro) is not null then
        raise exception 'FAIL: photographed articles: shop % farm % asso % pro %',
            org_photo_limit(v_shop), org_photo_limit(v_farm), org_photo_limit(v_asso), org_photo_limit(v_pro);
    end if;
    if (photo_state(v_shop) ->> 'limit')::int <> 12 then
        raise exception 'FAIL: the photo counter does not say 12';
    end if;
    if org_free_workers(v_farm) <> 2 or (team_seats(v_farm) ->> 'free')::int <> 2
       or org_free_workers(v_shop) <> 1 or org_free_workers(v_new) <> 0 then
        raise exception 'FAIL: the free seat: farm % shop % not set up %',
            org_free_workers(v_farm), org_free_workers(v_shop), org_free_workers(v_new);
    end if;
    if vitrine_min(v_shop) <> 3 or path_goal(v_shop, 'articles') <> 3
       or vitrine_min(v_farm) <> 8 or path_goal(v_farm, 'articles') <> 8
       or vitrine_min(v_asso) <> 2 or vitrine_min(v_ch) <> 2 then
        raise exception 'FAIL: what opens a vitrine: shop % farm % asso % church %',
            vitrine_min(v_shop), vitrine_min(v_farm), vitrine_min(v_asso), vitrine_min(v_ch);
    end if;
    if (vitrine_checklist(v_shop) ->> 'min_items')::int <> 3 then
        raise exception 'FAIL: the vitrine checklist does not follow: %', vitrine_checklist(v_shop);
    end if;
    -- The church has one service, under its kind's two: closed to the street.
    if storefront_open('eglise-107') is not null then
        raise exception 'FAIL: the church opened with one service under a minimum of two';
    end if;
    m := plan_terms();
    if (m -> 'kinds' -> 'retail' ->> 'free_photo_items')::int <> 12
       or (m -> 'kinds' -> 'farm' ->> 'free_max_staff')::int <> 2
       or (m -> 'kinds' -> 'association' ->> 'free_max_invoices_month')::int <> 1
       or (m ->> 'free_photo_items')::int <> 10 then
        raise exception 'FAIL: the terms read %', m;
    end if;
    raise notice 'PASS: shops 12 photos and 3 to open (Le Chemin and the checklist too), farms 2 free people, associations 1 invoice and 2 services (the church too); other kinds and Pro untouched; the terms carry each kind''s own';
end $$;
commit;
-- The invoice cap by kind: the association's one, the shop's twenty.
do $$
declare
    v_a text := pg_temp.invoice_cap('10700000-0000-0000-0000-000000000004', '10710710-0000-0000-0000-000000000005');
    v_c text := pg_temp.invoice_cap('10700000-0000-0000-0000-000000000005', '10710710-0000-0000-0000-000000000006');
    v_s text := pg_temp.invoice_cap('10700000-0000-0000-0000-000000000001', '10710710-0000-0000-0000-000000000002');
begin
    if v_a not like '1 | Kaj Pro : la formule gratuite permet 1 factures par mois%'
       or v_c not like '1 | %' or v_s not like '20 | %' then
        raise exception 'FAIL: the invoice cap by kind: asso % church % shop %', v_a, v_c, v_s;
    end if;
    raise notice 'PASS: an association (and a church) stops at its kind''s 1 invoice a month, a shop at the global 20';
end $$;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000001', true);
do $$
begin
    begin
        perform platform_set_kind_setting('association', 'vitrine_min_items', '3');
        raise exception 'FAIL: an association took a shop''s minimum';
    exception when raise_exception then
        if sqlerrm <> 'Ce réglage n''existe pas pour ce type d''activité.' then raise; end if;
    end;
    begin
        perform platform_set_kind_setting('retail', 'free_photo_items', '5000');
        raise exception 'FAIL: 5000 photos taken';
    exception when raise_exception then
        if sqlerrm <> 'Ce nombre est hors des limites permises.' then raise; end if;
    end;
    begin
        perform platform_set_kind_setting('retail', 'free_photo_items', '2.5');
        raise exception 'FAIL: 2.5 photos taken';
    exception when raise_exception then
        if sqlerrm <> 'Ce réglage est un nombre entier.' then raise; end if;
    end;
    begin
        perform platform_set_kind_setting('association', 'vitrine_min_items_association', '0');
        raise exception 'FAIL: an association opened with nothing';
    exception when raise_exception then
        if sqlerrm <> 'Ce nombre est hors des limites permises.' then raise; end if;
    end;
    begin
        perform platform_set_kind_setting('retail', 'delivery_max_km', '30');
        raise exception 'FAIL: an unknown setting taken';
    exception when raise_exception then
        if sqlerrm not like 'Réglage inconnu%' then raise; end if;
    end;
    begin
        perform platform_set_kind_setting('generic', 'free_photo_items', '3');
        raise exception 'FAIL: an unknown kind taken';
    exception when raise_exception then
        if sqlerrm not like 'Type d''activité inconnu%' then raise; end if;
    end;
    -- The same value again changes nothing and writes nothing.
    if platform_set_kind_setting('retail', 'free_photo_items', '12') is not null then
        raise exception 'FAIL: an unchanged setting wrote a journal line';
    end if;
    raise notice 'PASS: a setting the kind does not have, out of bounds, not whole, unknown, or of an unknown kind is refused in French; the same value writes nothing';
end $$;
commit;
-- « Par défaut » again, kind by kind: the global numbers, exactly as before.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000001', true);
select platform_set_kind_setting('farm', 'free_max_staff', null) is not null as cleared;
select platform_set_kind_setting('association', 'free_max_invoices_month', 'null') is not null as cleared;
select platform_set_kind_setting('retail', 'vitrine_min_items', null) is not null as cleared;
select platform_set_kind_setting('association', 'vitrine_min_items_association', null) is not null as cleared;
commit;
select set_config('request.jwt.claim.sub', '', false);
do $$
begin
    if exists (select 1 from kind_settings where key <> 'free_photo_items') then
        raise exception 'FAIL: « par défaut » left a row';
    end if;
    -- The shops' 12 photos stays for the journal's test; the rest is today.
    if (pg_temp.p1_snapshot() -> 'orgs' -> 'ferme-107') is distinct from
           ((select snap from p1_after) -> 'orgs' -> 'ferme-107')
       or (pg_temp.p1_snapshot() -> 'orgs' -> 'entraide-107') is distinct from
           ((select snap from p1_after) -> 'orgs' -> 'entraide-107')
       or (pg_temp.p1_snapshot() -> 'orgs' -> 'eglise-107') is distinct from
           ((select snap from p1_after) -> 'orgs' -> 'eglise-107') then
        raise exception 'FAIL: cleared, the farm, the association or the church do not read as before';
    end if;
    raise notice 'PASS: each number back to « par défaut »: the farm, the association and the church read exactly as before';
end $$;

\echo ''
\echo '--- TEST 3 (P3): the journal and its undo; only the platform ---'
begin;
-- Read as the database (the journal and the readers are internal), signed in as Mara.
select set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000001', true);
do $$
declare
    v_act  uuid;
    v_act2 uuid;
    a      record;
begin
    select * into a from platform_actions
     where kind = 'kind_setting' and after ->> 'key' = 'free_photo_items' and undone_at is null
     order by at desc limit 1;
    if a.summary not like '« Articles en photo (formule gratuite) » — toutes les boutiques : 12 (avant : par défaut)'
       or a.undo_fn <> 'platform_restore_kind_setting' or a.actor <> auth.uid() then
        raise exception 'FAIL: the journal line reads % / %', a.summary, a.undo_fn;
    end if;
    perform platform_undo(a.id);
    if org_photo_limit('10700000-0000-0000-0000-000000000001') <> 10 then
        raise exception 'FAIL: the undo did not bring the shops back to 10';
    end if;
    begin
        perform platform_undo(a.id);
        raise exception 'FAIL: undone twice';
    exception when raise_exception then
        if sqlerrm <> 'Cette action a déjà été annulée.' then raise; end if;
    end;
    -- A stale undo: 3, then 4; undoing the 3 first is refused.
    v_act  := platform_set_kind_setting('farm', 'free_photo_items', '3');
    v_act2 := platform_set_kind_setting('farm', 'free_photo_items', '4');
    begin
        perform platform_undo(v_act);
        raise exception 'FAIL: a stale undo went through';
    exception when raise_exception then
        if sqlerrm <> 'Ce réglage a changé depuis : annulez d''abord le changement plus récent.' then raise; end if;
    end;
    perform platform_undo(v_act2);
    perform platform_undo(v_act);
    if exists (select 1 from kind_settings where kind = 'farm' and key = 'free_photo_items') then
        raise exception 'FAIL: two undos did not return the farms to the global number';
    end if;
    raise notice 'PASS: each change is a journal line with its words and its undo; undone once, a stale undo refused, newest first';
end $$;
commit;

-- Nobody else: an owner, a stranger, the street.
do $$
declare
    who uuid;
    f   text;
begin
    foreach who in array array['10710710-0000-0000-0000-000000000002',
                               '10710710-0000-0000-0000-000000000009']::uuid[] loop
        perform set_config('request.jwt.claim.sub', who::text, true);
        foreach f in array array[
            'select platform_kind_models(''retail'')',
            'select platform_set_kind_setting(''retail'', ''free_photo_items'', ''50'')',
            'select platform_set_kind_setting(''retail'', ''vitrine_default'', ''{"accent": "#2E7D5B"}'')',
            'select platform_set_kind_setting(''retail'', ''setup_off'', ''["position"]'')',
            'select platform_set_application_form(''{"welcome": "Bonjour"}'')',
            'select platform_pending_applications()'] loop
            begin
                execute f;
                raise exception 'FAIL: % went through for %', f, who;
            exception when raise_exception then
                if sqlerrm <> 'Réservé à la plateforme' then raise; end if;
            end;
        end loop;
    end loop;
    perform set_config('request.jwt.claim.sub', '', true);
    if exists (select 1 from kind_settings) then
        raise exception 'FAIL: somebody else wrote a kind setting';
    end if;
    raise notice 'PASS: an owner and a stranger are refused every platform door (« Réservé à la plateforme »)';
end $$;

do $$
declare f text;
begin
    foreach f in array array['kind_setting_catalog()', 'kind_setup_steps(text)',
        'kind_setting(text, text)', 'org_kind_limit(uuid, text, integer)',
        'vitrine_default_style(uuid)', 'kind_setting_words(text, jsonb)',
        'platform_restore_kind_setting(jsonb)', 'platform_restore_application_form(jsonb)',
        'trg_application_decided()'] loop
        if has_function_privilege('authenticated', f, 'execute')
           or has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: the internal % is open to an app role', f;
        end if;
    end loop;
    foreach f in array array['platform_kind_models(text)', 'platform_set_kind_setting(text, text, jsonb)',
        'setup_steps_off(uuid)', 'application_form()', 'platform_set_application_form(jsonb)',
        'platform_pending_applications()',
        'apply_for_org(text, text, text, text, text, text, text)',
        'apply_for_org(text, text, text, text, text, text, text, jsonb)'] loop
        if has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: the street may call %', f;
        end if;
        if not has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: the app may not call %', f;
        end if;
    end loop;
    if has_table_privilege('authenticated', 'kind_settings', 'select')
       or has_table_privilege('authenticated', 'kind_settings', 'insert')
       or has_table_privilege('anon', 'kind_settings', 'select') then
        raise exception 'FAIL: kind_settings is open to an app role';
    end if;
    raise notice 'PASS: the internals are closed to the app and the street, the doors open to the app only, kind_settings readable by no client';
end $$;

\echo ''
\echo '--- TEST 4: the vitrine default dresses only a vitrine never dressed, of its kind ---'
begin;
-- Read as the database (kind_settings is internal), signed in as Mara.
select set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000001', true);
do $$
declare
    f   text;
    ok  boolean;
begin
    foreach f in array array['{"layout": "mosaic"}', '{"accent": "vert"}', '{"cover": "logo"}',
                             '{"tagline": "Bonjour"}', '"list"'] loop
        ok := false;
        begin
            perform platform_set_kind_setting('retail', 'vitrine_default', f::jsonb);
        exception when raise_exception then
            ok := sqlerrm in ('La présentation est grille, grandes photos, liste ou menu',
                              'La couleur doit s''écrire #RRGGBB',
                              'La couverture est aucune ou la première photo de la vitrine.',
                              'La vitrine par défaut est une présentation, une couleur et une couverture.');
        end;
        if not ok then
            raise exception 'FAIL: the vitrine default % was not refused in French', f;
        end if;
    end loop;
    -- Grille and no cover are today's: nothing is kept.
    if platform_set_kind_setting('retail', 'vitrine_default', '{"layout": "grid", "cover": "none"}') is not null
       or exists (select 1 from kind_settings) then
        raise exception 'FAIL: today''s presentation was kept as a default';
    end if;
    perform platform_set_kind_setting('retail', 'vitrine_default',
        '{"layout": "list", "accent": "#2e7d5b", "cover": "first_photo"}');
    if (select value from kind_settings where kind = 'retail' and key = 'vitrine_default')
       <> '{"layout": "list", "accent": "#2E7D5B", "cover": "first_photo"}'::jsonb then
        raise exception 'FAIL: the default is kept as %',
            (select value from kind_settings where kind = 'retail' and key = 'vitrine_default');
    end if;
    raise notice 'PASS: an unknown layout, colour, cover or key is refused; grille and no cover keep nothing; the default is kept in a clean shape';
end $$;
commit;
select set_config('request.jwt.claim.sub', '', false);
do $$
declare
    s jsonb;
    v_cover text := 'org/10700000-0000-0000-0000-000000000001/Boutique_107_article_2.jpg';
    v_before jsonb := (select snap from p1_after);
begin
    -- A Basic vitrine: the free options only (093) — the colour and the
    -- cover; the presentation is Vitrine+'s.
    s := (select style from storefront('boutique-107'));
    if s ->> 'accent' is distinct from '#2E7D5B' or s ? 'layout'
       or s ->> 'cover_key' is distinct from v_cover then
        raise exception 'FAIL: the never-dressed Basic shop shows %', s;
    end if;
    if not storefront_photo_allowed(v_cover) then
        raise exception 'FAIL: the street may not load the default cover';
    end if;
    -- Dressed by its owner, a vitrine d'exemple, another kind: untouched.
    if (select to_jsonb(x) from storefront('habillee-107') x) is distinct from v_before -> 'orgs' -> 'habillee-107' -> 'storefront'
       or (select to_jsonb(x) from storefront('exemple-107') x) is distinct from v_before -> 'orgs' -> 'exemple-107' -> 'storefront'
       or (select to_jsonb(x) from storefront('ferme-107') x) is distinct from v_before -> 'orgs' -> 'ferme-107' -> 'storefront'
       or (select to_jsonb(x) from storefront('entraide-107') x) is distinct from v_before -> 'orgs' -> 'entraide-107' -> 'storefront' then
        raise exception 'FAIL: a dressed vitrine, a vitrine d''exemple, a farm or an association moved';
    end if;
    -- A Pro shop never dressed takes all of it, the presentation too.
    s := (select style from storefront('pro-107'));
    if s ->> 'layout' is distinct from 'list' or s ->> 'accent' is distinct from '#2E7D5B' then
        raise exception 'FAIL: the never-dressed Pro shop did not take the whole default: %', s;
    end if;
    -- The basics not free (093's switch at 0): a Basic vitrine shows none.
    update platform_settings set value = '0' where key = 'vitrine_free_basics';
    s := (select style from storefront('boutique-107'));
    update platform_settings set value = '1' where key = 'vitrine_free_basics';
    if s ? 'accent' or s ? 'layout' or s ? 'cover_key' then
        raise exception 'FAIL: with the basics not free, a Basic vitrine took the default: %', s;
    end if;
    raise notice 'PASS: a shop never dressed shows Mara''s green and its first photo as the cover (served by the photo gate) on Basic, and the list too on Pro — nothing on Basic when the basics are not free; a dressed shop, a vitrine d''exemple, the farm and the association as before';
end $$;
-- The owner's first dressing takes over.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000002', true);
select set_storefront_style('10700000-0000-0000-0000-000000000001', '{"tagline": "Chez Awa"}');
do $$
declare s jsonb := (select style from storefront('boutique-107'));
begin
    if s ? 'accent' or s ? 'layout' or s ? 'cover_key' or s ->> 'tagline' <> 'Chez Awa' then
        raise exception 'FAIL: the owner''s own dressing still shows the default: %', s;
    end if;
    raise notice 'PASS: once the owner dresses the vitrine, theirs shows and the default is gone';
end $$;
rollback;
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000001', true);
do $$
declare m jsonb := platform_kind_models('retail');
begin
    if m -> 'vitrine_default' <> '{"layout": "list", "accent": "#2E7D5B", "cover": "first_photo"}'::jsonb then
        raise exception 'FAIL: the tab does not read the default: %', m;
    end if;
    perform platform_set_kind_setting('retail', 'vitrine_default', null);
end $$;
commit;
select set_config('request.jwt.claim.sub', '', false);
do $$
begin
    if pg_temp.p1_snapshot() is distinct from (select snap from p1_after) then
        raise exception 'FAIL: cleared, the street is not as before';
    end if;
    raise notice 'PASS: the default cleared, every vitrine and number is exactly as before (P1 again)';
end $$;

\echo ''
\echo '--- TEST 5: the walkthrough''s optional steps turn off by kind, never a required one ---'
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000001', true);
do $$
declare m jsonb;
begin
    begin
        perform platform_set_kind_setting('retail', 'setup_off', '["article"]');
        raise exception 'FAIL: the first article was taken out of the walkthrough';
    exception when raise_exception then
        if sqlerrm <> 'Une étape obligatoire de la mise en route ne peut pas être retirée.' then raise; end if;
    end;
    begin
        perform platform_set_kind_setting('association', 'setup_off', '["identity"]');
        raise exception 'FAIL: an association''s name step was taken out';
    exception when raise_exception then
        if sqlerrm <> 'Une étape obligatoire de la mise en route ne peut pas être retirée.' then raise; end if;
    end;
    begin
        perform platform_set_kind_setting('farm', 'setup_off', '["members"]');
        raise exception 'FAIL: a farm took an association''s step';
    exception when raise_exception then
        if sqlerrm not like 'Étape inconnue%' then raise; end if;
    end;
    perform platform_set_kind_setting('retail', 'setup_off', '["position", "vitrine", "position"]');
    perform platform_set_kind_setting('association', 'setup_off', '["members"]');
    m := platform_kind_models('retail');
    if (select string_agg((e ->> 'key') || ':' || (e ->> 'on'), ',' order by n)
          from jsonb_array_elements(m -> 'setup') with ordinality s(e, n))
       <> 'identity:true,article:true,vitrine:false,position:false' then
        raise exception 'FAIL: the shops'' walkthrough reads %', m -> 'setup';
    end if;
end $$;
commit;
do $$
begin
    perform set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000002', true);
    if setup_steps_off('10700000-0000-0000-0000-000000000001') <> '["position", "vitrine"]'::jsonb then
        raise exception 'FAIL: the shop owner reads %', setup_steps_off('10700000-0000-0000-0000-000000000001');
    end if;
    perform set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000004', true);
    if setup_steps_off('10700000-0000-0000-0000-000000000003') <> '[]'::jsonb then
        raise exception 'FAIL: the farm took the shops'' steps';
    end if;
    perform set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000006', true);
    if setup_steps_off('10700000-0000-0000-0000-000000000005') <> '["members"]'::jsonb then
        raise exception 'FAIL: the church does not read the associations'' steps';
    end if;
    perform set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000009', true);
    if setup_steps_off('10700000-0000-0000-0000-000000000001') <> '[]'::jsonb then
        raise exception 'FAIL: a stranger read a shop''s walkthrough';
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    -- A row written by hand with a required step: still never off.
    update kind_settings set value = '["article", "position"]' where kind = 'retail' and key = 'setup_off';
    perform set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000002', true);
    if setup_steps_off('10700000-0000-0000-0000-000000000001') <> '["position"]'::jsonb then
        raise exception 'FAIL: a required step came through the reader';
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    delete from kind_settings where key = 'setup_off';
    raise notice 'PASS: shops without « vitrine » and « position », associations (the church too) without « members »; the first article and the name stay; a farm, a stranger read nothing off';
end $$;

\echo ''
\echo '--- TEST 6: the request page — kinds, questions, answers kept as asked, an older build held to it ---'
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000001', true);
do $$
declare
    f  text;
    ok boolean;
    v  jsonb;
begin
    foreach f in array array[
        '{"kinds": ["retail", "shop"]}',
        '{"kinds": []}',
        '{"questions": [{"label": ""}]}',
        '{"questions": [{"label": "Âge", "type": "date"}]}',
        '{"questions": [{"label": "Quoi ?", "type": "choice", "options": ["Un"]}]}',
        '{"questions": [{"label": "Quoi ?", "type": "choice", "options": ["Un", "Un"]}]}',
        '{"welcome": "' || repeat('x', 601) || '"}',
        '{"questions": [' || (select string_agg('{"label": "Q' || g || '"}', ',') from generate_series(1, 13) g) || ']}'] loop
        ok := false;
        begin
            perform platform_set_application_form(f::jsonb);
        exception when raise_exception then
            ok := sqlerrm in ('Les types proposés sont boutique, ferme ou association.',
                              'Proposez au moins un type d''activité.',
                              'Chaque question a son intitulé.',
                              'Une question est un texte, un choix, un nombre ou oui-non.',
                              'Une question à choix a de 2 à 12 réponses.',
                              'Une réponse proposée ne se répète pas.',
                              'Le mot d''accueil fait 600 caractères au plus.',
                              'Douze questions au plus.');
        end;
        if not ok then
            raise exception 'FAIL: the form % was not refused in French', left(f, 80);
        end if;
    end loop;
    -- All three kinds and nothing else is today's page: nothing kept.
    if platform_set_application_form('{"kinds": ["retail", "farm", "association"]}') is not null
       or application_form() is not null then
        raise exception 'FAIL: today''s page was kept as a form';
    end if;
    perform platform_set_application_form('{
        "welcome": "  Bienvenue chez Mara.  ",
        "kinds": ["retail", "farm", "retail"],
        "questions": [
            {"id": "ville", "label": "Votre ville", "help": "Où est l''activité", "required": true, "type": "text"},
            {"label": "Depuis combien d''années ?", "type": "number"},
            {"label": "Vous vendez", "type": "choice", "options": ["Alimentation", " Habits ", ""], "required": true},
            {"label": "Avez-vous un local ?", "type": "yesno", "required": true}]}');
    v := application_form();
    if v ->> 'welcome' <> 'Bienvenue chez Mara.' or v -> 'kinds' <> '["farm", "retail"]'::jsonb
       or jsonb_array_length(v -> 'questions') <> 4
       or v -> 'questions' -> 0 ->> 'id' <> 'ville'
       or v -> 'questions' -> 1 ->> 'id' !~ '^q[0-9a-f]{8}$'
       or v -> 'questions' -> 1 ->> 'required' <> 'false'
       or v -> 'questions' -> 2 -> 'options' <> '["Alimentation", "Habits"]'::jsonb then
        raise exception 'FAIL: the form is kept as %', v;
    end if;
    raise notice 'PASS: a form with an unknown kind, no kind, an empty label, an unknown type, a choice of one or twice the same, a long welcome or 13 questions is refused; today''s page keeps nothing; the form is kept clean (ids, order, trimmed)';
end $$;
commit;
do $$
declare
    v      jsonb := application_form();
    q2     text  := v -> 'questions' -> 1 ->> 'id';
    q3     text  := v -> 'questions' -> 2 ->> 'id';
    q4     text  := v -> 'questions' -> 3 ->> 'id';
    a      jsonb;
    ans    jsonb;
begin
    perform set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000008', true);
    -- The person asking reads the page.
    if application_form() is distinct from v then
        raise exception 'FAIL: the applicant does not read the page';
    end if;
    ans := jsonb_build_object('ville', 'Ouagadougou', q2, '3,5', q3, 'Habits', q4, 'oui', 'inconnue', 'x');
    begin
        perform apply_for_org('Entraide 107 bis', 'entraide-107-bis', 'association', 'XOF', null, null, null, ans);
        raise exception 'FAIL: an association was asked for on a page that offers none';
    exception when raise_exception then
        if sqlerrm <> 'Ce type d''activité ne peut pas être demandé pour l''instant.' then raise; end if;
    end;
    begin
        perform apply_for_org('Église 107 bis', 'eglise-107-bis', 'church', 'XOF', null, null, null, ans);
        raise exception 'FAIL: a church was asked for on a page that offers no association';
    exception when raise_exception then
        if sqlerrm <> 'Ce type d''activité ne peut pas être demandé pour l''instant.' then raise; end if;
    end;
    begin
        perform apply_for_org('Atelier 107', 'atelier-107', 'retail', 'XOF', null, null, null, ans - 'ville');
        raise exception 'FAIL: a required question went unanswered';
    exception when raise_exception then
        if sqlerrm <> 'Réponse obligatoire : Votre ville' then raise; end if;
    end;
    begin
        perform apply_for_org('Atelier 107', 'atelier-107', 'retail', 'XOF', null, null, null,
                              ans || jsonb_build_object(q3, 'Voitures'));
        raise exception 'FAIL: an answer not offered was taken';
    exception when raise_exception then
        if sqlerrm not like 'Choisissez une des réponses proposées%' then raise; end if;
    end;
    begin
        perform apply_for_org('Atelier 107', 'atelier-107', 'retail', 'XOF', null, null, null,
                              ans || jsonb_build_object(q2, 'trois'));
        raise exception 'FAIL: a number in words was taken';
    exception when raise_exception then
        if sqlerrm not like 'Répondez en chiffres%' then raise; end if;
    end;
    -- No to a required yes/no is an answer.
    perform apply_for_org('Atelier 107', 'atelier-107', 'retail', 'XOF', 'Couture', null, null,
                          ans || jsonb_build_object(q4, false));
    a := (select answers from org_applications
           where applicant_id = '10710710-0000-0000-0000-000000000008' and status = 'pending');
    if jsonb_array_length(a) <> 4
       or a -> 0 <> '{"id": "ville", "label": "Votre ville", "type": "text", "value": "Ouagadougou"}'::jsonb
       or a -> 1 -> 'value' <> '3.5'::jsonb or a -> 2 -> 'value' <> '"Habits"'::jsonb
       or a -> 3 -> 'value' <> 'false'::jsonb then
        raise exception 'FAIL: the answers are kept as %', a;
    end if;
    -- An older build sends no answers: held to the same page.
    perform set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000010', true);
    begin
        perform apply_for_org('Vieille 107', 'vieille-107', 'farm');
        raise exception 'FAIL: an older build walked past a required question';
    exception when raise_exception then
        if sqlerrm <> 'Réponse obligatoire : Votre ville' then raise; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', true);
    raise notice 'PASS: a kind the page does not offer (an association, a church) is refused; a required answer missing, a choice not offered, a number in words refused; the answers are kept as asked (3,5 → 3.5, « non » kept); an older build is held to the page';
end $$;
-- The Demandes cards read the answers; the street and the applicant do not.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000001', true);
do $$
declare
    q jsonb := platform_pending_applications();
    c jsonb;
begin
    select e into c from jsonb_array_elements(q) e where e ->> 'slug' = 'atelier-107';
    if c is null or jsonb_array_length(c -> 'answers') <> 4 or c ->> 'applicant' <> 'Coumba Demande'
       or c ->> 'profile' <> 'retail' then
        raise exception 'FAIL: the Demandes card reads %', c;
    end if;
    raise notice 'PASS: the Demandes cards carry the answers with the applicant and the kind';
end $$;
commit;

\echo ''
\echo '--- TEST 7: the applicant hears the decision, the journal keeps it ---'
begin;
-- Read as the database (the bell and the journal), signed in as Mara.
select set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000001', true);
do $$
declare
    v_app uuid := (select id from org_applications
                    where applicant_id = '10710710-0000-0000-0000-000000000008' and status = 'pending');
    v_org uuid;
    n     record;
begin
    v_org := approve_org_application(v_app);
    select * into n from notifications
     where recipient_id = '10710710-0000-0000-0000-000000000008' and kind = 'application_approved';
    if n.org_id <> v_org or n.message <> 'Votre demande est acceptée : Atelier 107 est ouverte.'
       or n.params ->> 'name' <> 'Atelier 107' then
        raise exception 'FAIL: the approval rang %', to_jsonb(n);
    end if;
    if not exists (select 1 from platform_actions
                    where kind = 'application' and org_id = v_org
                      and summary = 'Demande acceptée : Atelier 107 (atelier-107)' and undo_fn is null) then
        raise exception 'FAIL: the approval is not in the journal';
    end if;
end $$;
commit;
-- The second applicant asks (answering), and is refused with a ready reason.
do $$
declare v jsonb := application_form();
begin
    perform set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000010', true);
    perform apply_for_org('Vieille 107', 'vieille-107', 'farm', 'XOF', null, null, null,
        jsonb_build_object('ville', 'Bobo', v -> 'questions' -> 2 ->> 'id', 'Alimentation',
                           v -> 'questions' -> 3 ->> 'id', true));
    perform set_config('request.jwt.claim.sub', '', true);
end $$;
begin;
-- Read as the database (the bell and the journal), signed in as Mara.
select set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000001', true);
do $$
declare
    v_app uuid := (select id from org_applications
                    where applicant_id = '10710710-0000-0000-0000-000000000010' and status = 'pending');
    n     record;
begin
    perform reject_org_application(v_app, 'Informations manquantes');
    select * into n from notifications
     where recipient_id = '10710710-0000-0000-0000-000000000010' and kind = 'application_refused';
    if n.org_id is not null
       or n.message <> 'Votre demande pour Vieille 107 est refusée : Informations manquantes'
       or n.params ->> 'reason' <> 'Informations manquantes' then
        raise exception 'FAIL: the refusal rang %', to_jsonb(n);
    end if;
    if not exists (select 1 from platform_actions
                    where kind = 'application'
                      and summary = 'Demande refusée : Vieille 107 — Informations manquantes') then
        raise exception 'FAIL: the refusal is not in the journal';
    end if;
    raise notice 'PASS: accepted, the applicant hears it with the business to open; refused, with the reason; both in the journal (not undoable)';
end $$;
commit;

-- The page back to today's, through the journal: undone, it is gone.
begin;
-- Read as the database (the journal), signed in as Mara.
select set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000001', true);
do $$
declare a uuid;
begin
    select id into a from platform_actions
     where kind = 'application_form' and undone_at is null order by at desc limit 1;
    perform platform_undo(a);
    if application_form() is not null then
        raise exception 'FAIL: the form outlived its undo';
    end if;
    raise notice 'PASS: the request page''s change undone from the journal: today''s page again';
end $$;
commit;
select set_config('request.jwt.claim.sub', '', false);

\echo ''
\echo '--- TEST 8: a request is written through its functions only — a direct insert or decision refused ---'
do $$
declare v_app uuid;
begin
    perform set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000009', true);
    execute 'set local role authenticated';
    -- Past the page's kinds and its required questions: refused at the door.
    begin
        insert into org_applications (applicant_id, name, slug, profile)
        values ('10710710-0000-0000-0000-000000000009', 'Direct 107', 'direct-107', 'retail');
        raise exception 'FAIL: a request was written past apply_for_org';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
    -- Nor decided by a platform admin straight on the table.
    select id into v_app from org_applications limit 1;
    perform set_config('request.jwt.claim.sub', '10710710-0000-0000-0000-000000000001', true);
    execute 'set local role authenticated';
    begin
        update org_applications set status = 'approved' where id = v_app;
        raise exception 'FAIL: a request was decided past approve_org_application';
    exception when insufficient_privilege then null;
    end;
    begin
        delete from org_applications where id = v_app;
        raise exception 'FAIL: a request was deleted';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '', true);
    if exists (select 1 from org_applications where slug = 'direct-107') then
        raise exception 'FAIL: the direct request is there';
    end if;
    raise notice 'PASS: a signed-in caller cannot write a request directly, nor a platform admin decide or delete one: apply_for_org, approve_org_application and reject_org_application only';
end $$;

-- Leave the platform's numbers as the next suite expects them.
update platform_settings set value = '0' where key = 'path_gates_open';
delete from kind_settings;
