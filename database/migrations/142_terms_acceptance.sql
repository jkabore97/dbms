-- ============================================================
-- 142_terms_acceptance.sql — batch 147: Mara's new Conditions
-- d'utilisation, accepted by everyone, and enforced by the server.
--
-- The owner: « Update the user conditions and make people accept them
-- just after they sign in for the first time … I need to protect my
-- business. People are very creative with fraud and scams. »
--
-- Four documents, each with a version:
--   terms    the Conditions d'utilisation (version 2: the rewrite of
--            batch 147 — version 1 was « en utilisant Mara, vous
--            acceptez », never accepted explicitly);
--   privacy  the Politique de confidentialité (version 2: identity
--            checks, records kept, phone verification added);
--   seller   the « Engagements du vendeur » (version 1, new), accepted
--            before a business is created;
--   courier  the charte du livreur (112's charter: version 1 as 112
--            wrote it; version 2 adds two lines — the courier works on
--            their own account, the delivery code is asked at the door).
--
--   1. terms_acceptances: one row per (person, document, version), with
--      when, and the app's platform and version when it said them.
--      Append-only: no policy writes it; the person reads their own rows
--      (RLS), nothing is open to anon. Deleted with the account (the
--      account deletion promises the profile goes; flagged to the lawyer).
--   2. platform_settings.terms_versions: one object — each document's
--      current version, since when, and until when a person who already
--      had an account before that version is not refused by the server
--      (« grace_until », below); the date, and the « what changed » line in
--      French and in English. An object, so 105's board and setter never
--      list it (as application_form): it changes through its own door.
--   3. The doors (SECURITY DEFINER, search_path pinned, closed to PUBLIC
--      and anon, open to authenticated):
--        accept_terms(doc, version, platform, app_version) — the version
--          must be the current one; written once, returns the state;
--        my_terms_state() — each document's current and accepted version,
--          and « gate »: what the app asks before anything else (terms and
--          privacy for everyone; seller for someone who owns a business;
--          courier for an approved courier);
--        platform_terms_board(), platform_terms_of(user),
--        platform_terms_bump(docs, changes, changes_en, grace_days) — the
--          command center's: the versions and how many accepted them, a
--          person's acceptances, a new version (everyone asked again).
--   4. THE SERVER ENFORCES IT (the app's gate comes first; this is the
--      backstop for an older app, or a call made without the app):
--        * an order (place_order's insert into orders, as the customer)
--          needs the terms — a trigger on orders, so place_order is not
--          copied here (131's, and whatever redefines it next, keeps it);
--        * a business made through create_my_business or create_org needs
--          the seller's commitments of its owner — org_create_core, which
--          both call, checks them (create_org stays SECURITY DEFINER and
--          platform-only, as CLAUDE.md says, and is not touched);
--        * a courier's application sent (112's courier_application_send:
--          the row turning « pending ») needs the courier's — a trigger on
--          courier_applications; the charter ticked (112's step) is written
--          as the courier's acceptance by the same trigger, so an app
--          before 147 records it too.
--      Each refusal is one French sentence the app translates (en.dart).
--      Internal paths are never asked: a check runs only when the
--      signed-in caller is the person concerned (auth.uid() = the
--      customer / the owner / the courier). The showcase vitrines (094)
--      insert orgs directly, the seeds and SQL run with no caller: none is
--      refused.
--   5. Existing people keep working: during « grace_until » (30 days from
--      142; 14 by default after a bump), an account made before that
--      version is not refused by the server — the app (from batch 147)
--      asks them at once, an app still on an older build is not broken
--      mid-order. An account made after it must have accepted. Existing
--      businesses and approved couriers are never stopped by the server:
--      only creating a business and sending an application are asked.
--   6. 112's charter acceptances are kept as courier version 1, with their
--      date; courier_rules() (122's, verbatim but one line) now says the
--      charter's version from terms_versions.
--   7. Found by the supervisor's review: 112's courier_open_steps reopens
--      the charter step of a dossier sent back whose charter is not the
--      current version (else, from 142's version 2 on, such a courier could
--      never send again); and 056's read policies on orders and
--      order_lines lose the courier's clause — the courier who carried an
--      order read its row, delivery code included, so could close it
--      without the customer. Every courier screen reads through definers.
--
-- Shop, farm and association alike: the documents and the doors do not
-- depend on the kind of business.
--
-- Re-runnable: create if not exists, create or replace, drop … if exists,
-- the setting inserted only when absent, the backfill on conflict do
-- nothing. Needs 105 (platform_actions, platform_only), 111
-- (org_create_core), 112 (courier_applications) and 122 (courier_rules).
-- ============================================================

do $$
begin
    if to_regprocedure('public.org_create_core(uuid, text, text, text, text)') is null
       or to_regclass('public.courier_applications') is null
       or to_regprocedure('public.platform_only()') is null
       or to_regprocedure('public.plan_limit(text, integer)') is null then
        raise exception '142 needs 105 (platform_only), 111 (org_create_core), 112 (courier_applications) and 122 applied first';
    end if;
end $$;

-- ------------------------------------------------------------
-- 1. The acceptances
-- ------------------------------------------------------------
create table if not exists terms_acceptances (
    id          bigint generated always as identity primary key,
    user_id     uuid not null references auth.users(id) on delete cascade,
    document    text not null check (document in ('terms', 'privacy', 'seller', 'courier')),
    version     int  not null check (version between 1 and 1000),
    accepted_at timestamptz not null default now(),
    -- What the app said of itself: 'web', 'android', 'ios'; its version.
    platform    text check (platform in ('web', 'android', 'ios')),
    app_version text check (char_length(app_version) <= 40),
    unique (user_id, document, version)
);

comment on table terms_acceptances is
    'Who accepted which version of Mara''s documents, and when (142). Written by accept_terms() and 112''s charter step only; read by the person (RLS) and the platform.';

create index if not exists terms_acceptances_by_user
    on terms_acceptances (user_id, document, version desc);

alter table terms_acceptances enable row level security;

drop policy if exists "terms acceptances read by their person" on terms_acceptances;
create policy "terms acceptances read by their person" on terms_acceptances
for select
using (user_id = auth.uid());
-- No write policy: every row goes through a door, and stays.

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on table terms_acceptances from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke insert, update, delete, truncate on table terms_acceptances from authenticated;
        grant select on table terms_acceptances to authenticated;
    end if;
end $$;

-- ------------------------------------------------------------
-- 2. The versions
-- ------------------------------------------------------------
insert into platform_settings (key, value)
select 'terms_versions', jsonb_build_object(
    'terms',   jsonb_build_object('version', 2, 'since', now(), 'grace_until', now() + interval '30 days'),
    'privacy', jsonb_build_object('version', 2, 'since', now(), 'grace_until', now() + interval '30 days'),
    'seller',  jsonb_build_object('version', 1, 'since', now(), 'grace_until', now() + interval '30 days'),
    'courier', jsonb_build_object('version', 2, 'since', now(), 'grace_until', now() + interval '30 days'),
    'date',       '2026-10-14',
    'changes',    'Nouvelles conditions : Mara est une plateforme, chaque entreprise vend elle-même ; les règles contre la fraude ; les engagements du vendeur et du livreur.',
    'changes_en', 'New terms: Mara is a platform, each business sells for itself; the rules against fraud; the seller''s and the courier''s commitments.')
where not exists (select 1 from platform_settings where key = 'terms_versions');

create or replace function terms_documents()
returns text[]
language sql
immutable
set search_path = public
as $$
    select array['terms', 'privacy', 'seller', 'courier'];
$$;

-- The setting, as stored (an empty object if somebody removed it).
create or replace function terms_setting()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((select value from platform_settings where key = 'terms_versions'
                      and jsonb_typeof(value) = 'object'), '{}'::jsonb);
$$;

-- A document's current version: 1 when the setting does not say.
create or replace function terms_version(p_doc text)
returns int
language sql
stable
security definer
set search_path = public
as $$
    select greatest(1, coalesce((terms_setting() -> p_doc ->> 'version')::int, 1));
$$;

-- The latest version a person accepted, or null.
create or replace function terms_accepted_version(p_user uuid, p_doc text)
returns int
language sql
stable
security definer
set search_path = public
as $$
    select max(version) from terms_acceptances where user_id = p_user and document = p_doc;
$$;

-- May the server let this person through for this document? Accepted the
-- current version — or, while that version's grace lasts, an account that
-- existed before it.
create or replace function terms_ok(p_user uuid, p_doc text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_doc   jsonb := terms_setting() -> p_doc;
    v_since timestamptz;
    v_grace timestamptz;
begin
    if p_user is null then
        return true;
    end if;
    if coalesce(terms_accepted_version(p_user, p_doc), 0) >= terms_version(p_doc) then
        return true;
    end if;
    begin
        v_since := (v_doc ->> 'since')::timestamptz;
        v_grace := (v_doc ->> 'grace_until')::timestamptz;
    exception when others then
        return false;
    end;
    return v_since is not null and v_grace is not null and now() < v_grace
       and exists (select 1 from auth.users u where u.id = p_user and u.created_at < v_since);
end;
$$;

-- ------------------------------------------------------------
-- 3. The person's doors
-- ------------------------------------------------------------
create or replace function my_terms_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_me      uuid := auth.uid();
    v_set     jsonb := terms_setting();
    v_docs    jsonb := '{}'::jsonb;
    v_gate    text[] := '{}';
    v_owner   boolean;
    v_courier boolean;
    v_cur     int;
    v_acc     int;
    d         text;
begin
    if v_me is null then
        raise exception 'Connectez-vous pour accepter les conditions.';
    end if;
    v_owner := exists (select 1 from memberships m join orgs o on o.id = m.org_id
                        where m.user_id = v_me and m.role = 'owner' and o.archived_at is null);
    v_courier := exists (select 1 from couriers c where c.user_id = v_me and c.status = 'approved');
    foreach d in array terms_documents() loop
        v_cur := terms_version(d);
        v_acc := terms_accepted_version(v_me, d);
        v_docs := v_docs || jsonb_build_object(d, jsonb_build_object(
            'current', v_cur, 'accepted', v_acc, 'pending', coalesce(v_acc, 0) < v_cur,
            'accepted_at', (select max(accepted_at) from terms_acceptances
                             where user_id = v_me and document = d and version = v_acc)));
        if coalesce(v_acc, 0) < v_cur
           and (d in ('terms', 'privacy')
                or (d = 'seller' and v_owner)
                or (d = 'courier' and v_courier)) then
            v_gate := v_gate || d;
        end if;
    end loop;
    return jsonb_build_object(
        'version',    142,
        'documents',  v_docs,
        'gate',       to_jsonb(v_gate),
        -- An earlier version of the terms was accepted: « what changed ».
        'changed',    coalesce(terms_accepted_version(v_me, 'terms'), 0) > 0,
        'owner',      v_owner,
        'courier',    v_courier,
        'date',       v_set ->> 'date',
        'changes',    v_set ->> 'changes',
        'changes_en', v_set ->> 'changes_en');
end;
$$;

create or replace function accept_terms(
    p_doc         text,
    p_version     int,
    p_platform    text default null,
    p_app_version text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_me uuid := auth.uid();
begin
    if v_me is null then
        raise exception 'Connectez-vous pour accepter les conditions.';
    end if;
    if p_doc is null or not p_doc = any (terms_documents()) then
        raise exception 'Document inconnu.';
    end if;
    if p_version is distinct from terms_version(p_doc) then
        raise exception 'Ces conditions ont changé entre-temps : relisez-les, puis acceptez-les à nouveau.';
    end if;
    insert into terms_acceptances (user_id, document, version, platform, app_version)
    values (v_me, p_doc, p_version,
            case when p_platform in ('web', 'android', 'ios') then p_platform end,
            left(nullif(btrim(coalesce(p_app_version, '')), ''), 40))
    on conflict (user_id, document, version) do nothing;
    return my_terms_state();
end;
$$;

-- ------------------------------------------------------------
-- 4. The server's refusals
-- ------------------------------------------------------------
-- An order, as its customer.
create or replace function trg_orders_terms()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if new.customer_id is not null and new.customer_id = auth.uid()
       and not terms_ok(new.customer_id, 'terms') then
        raise exception 'Acceptez d''abord les Conditions d''utilisation de Mara pour commander (mettez l''application à jour si elle ne vous les montre pas).';
    end if;
    return new;
end;
$$;

drop trigger if exists orders_terms_check on orders;
create trigger orders_terms_check
before insert on orders
for each row execute function trg_orders_terms();

-- A business, by its owner: 111's org_create_core, verbatim but for the
-- check at its top. create_org (the platform's « Nouvelle entreprise »)
-- and create_my_business (everybody's « Créer mon activité ») both make
-- their business here.
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
    -- 142: the owner's seller commitments, when the owner is the caller.
    if p_owner is not null and p_owner = auth.uid() and not terms_ok(p_owner, 'seller') then
        raise exception 'Acceptez d''abord les engagements du vendeur pour créer une activité (mettez l''application à jour si elle ne vous les montre pas).';
    end if;

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

-- A courier's application: the charter ticked is the courier's acceptance;
-- sending it needs that acceptance (or the grace of an older account).
create or replace function trg_courier_terms()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if new.charter_version is not null
       and new.charter_version is distinct from old.charter_version
       and new.user_id = auth.uid()
       and new.charter_version = terms_version('courier') then
        insert into terms_acceptances (user_id, document, version)
        values (new.user_id, 'courier', new.charter_version)
        on conflict (user_id, document, version) do nothing;
    end if;
    if new.status = 'pending' and old.status is distinct from 'pending'
       and new.user_id = auth.uid()
       and not terms_ok(new.user_id, 'courier') then
        raise exception 'Acceptez d''abord la charte du livreur pour envoyer votre demande (mettez l''application à jour si elle ne vous la montre pas).';
    end if;
    return new;
end;
$$;

drop trigger if exists courier_applications_terms on courier_applications;
create trigger courier_applications_terms
before update on courier_applications
for each row execute function trg_courier_terms();

-- 112's charter acceptances, kept as what they were: courier version 1.
insert into terms_acceptances (user_id, document, version, accepted_at)
select a.user_id, 'courier', a.charter_version, coalesce(a.charter_at, a.updated_at, now())
  from courier_applications a
  join auth.users u on u.id = a.user_id
 where a.charter_version between 1 and 1000
on conflict (user_id, document, version) do nothing;

-- 112's courier_open_steps, verbatim but for one line: a dossier sent
-- back (refused, a photo to take again) whose charter is not the current
-- version has its charter step open too. Without it, 142's version 2 (and
-- every later bump) left such a courier unable ever to send again: 112's
-- send asks the current charter, and the charter step was closed to them
-- (the supervisor's review of 147).
create or replace function courier_open_steps(p_user uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_status  text;
    v_open    text[];
    v_charter int;
begin
    select status, reopened, charter_version into v_status, v_open, v_charter
      from courier_applications where user_id = p_user;
    if v_status is null or v_status = 'draft' then
        return array['zone', 'hours', 'vehicle', 'selfie', 'id', 'phone', 'charter'];
    end if;
    if v_status <> 'refused' then
        return '{}';
    end if;
    select coalesce(array_agg(distinct s), '{}') into v_open
      from unnest(v_open || (select coalesce(array_agg(courier_part_step(m)), '{}')
                               from unnest(courier_missing_parts(p_user)) m)
                         || case when v_charter is distinct from terms_version('courier')
                                 then array['charter'] else '{}'::text[] end) s;
    return v_open;
end;
$$;

-- 122's courier_rules, verbatim but for the charter's version: the
-- courier document's.
create or replace function courier_rules()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'licence_required', coalesce((select value = 'true'::jsonb from platform_settings
                                       where key = 'courier_licence_required'), false),
        'phone_verified',   coalesce((select value = 'true'::jsonb from platform_settings
                                       where key = 'courier_phone_verified'), false),
        -- RULE M: a mobile-money payout only while Mara takes mobile payment.
        'mobile_money',     wave_on(),
        'charter_version',  terms_version('courier'),
        'radius_km',        least(100, greatest(1, plan_limit('courier_radius_km', 10))));
$$;

-- The delivery code at the door, kept from the courier (found by the
-- supervisor's review of 147, checking « Qui voit vos informations »): 056
-- let the courier who carries an order read its whole row — and 073's
-- handover_code with it, so a courier could read the code, mark the order
-- delivered without the customer, and the terms' « the code proves the
-- order was handed over » was not true. Every courier screen reads through
-- its definer doors (courier_deliveries, delivery_board, courier_handover,
-- order_tracking …), never the table: the courier's clause goes from the
-- two read policies; the customer and the business read as before.
drop policy if exists "orders readable by their customer and the shop" on orders;
create policy "orders readable by their customer and the shop"
on orders for select
using (customer_id = auth.uid()
       or is_org_member(org_id));

drop policy if exists "order lines readable with their order" on order_lines;
create policy "order lines readable with their order"
on order_lines for select
using (exists (select 1 from orders o
                where o.id = order_id
                  and (o.customer_id = auth.uid()
                       or is_org_member(o.org_id))));

-- ------------------------------------------------------------
-- 5. The platform's doors
-- ------------------------------------------------------------
-- The versions, and how many people accepted each current one.
create or replace function platform_terms_board()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_set  jsonb := terms_setting();
    v_docs jsonb := '{}'::jsonb;
    d      text;
begin
    perform platform_only();
    foreach d in array terms_documents() loop
        v_docs := v_docs || jsonb_build_object(d, jsonb_build_object(
            'version',     terms_version(d),
            'since',       v_set -> d -> 'since',
            'grace_until', v_set -> d -> 'grace_until',
            'accepted',    (select count(distinct user_id) from terms_acceptances
                             where document = d and version >= terms_version(d))));
    end loop;
    return jsonb_build_object(
        'documents',  v_docs,
        'people',     (select count(*) from auth.users),
        'date',       v_set ->> 'date',
        'changes',    v_set ->> 'changes',
        'changes_en', v_set ->> 'changes_en');
end;
$$;

-- One person's acceptances, newest first (their fiche).
create or replace function platform_terms_of(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    perform platform_only();
    return coalesce((
        select jsonb_agg(jsonb_build_object(
                   'document', a.document, 'version', a.version,
                   'accepted_at', a.accepted_at, 'platform', a.platform,
                   'app_version', a.app_version,
                   'current', a.version >= terms_version(a.document))
               order by a.accepted_at desc, a.document)
          from terms_acceptances a where a.user_id = p_user), '[]'::jsonb);
end;
$$;

-- A new version of one or more documents: everyone is asked again. The
-- server goes on letting the people already here through for
-- p_grace_days (0 to 90); the app asks them at once.
create or replace function platform_terms_bump(
    p_docs       text[],
    p_changes    text,
    p_changes_en text default null,
    p_grace_days int  default 14
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_before  jsonb;
    v_after   jsonb;
    v_changes text := nullif(btrim(coalesce(p_changes, '')), '');
    v_en      text := nullif(btrim(coalesce(p_changes_en, '')), '');
    v_days    int  := coalesce(p_grace_days, 14);
    d         text;
begin
    perform platform_only();
    if p_docs is null or cardinality(p_docs) = 0 then
        raise exception 'Choisissez au moins un document.';
    end if;
    foreach d in array p_docs loop
        if not d = any (terms_documents()) then
            raise exception 'Document inconnu.';
        end if;
    end loop;
    if v_changes is null then
        raise exception 'Dites en une phrase ce qui a changé.';
    end if;
    if char_length(v_changes) > 200 or char_length(coalesce(v_en, '')) > 200 then
        raise exception 'Une phrase de 200 caractères au plus.';
    end if;
    if v_days < 0 or v_days > 90 then
        raise exception 'Un délai de 0 à 90 jours.';
    end if;

    select value into v_before from platform_settings where key = 'terms_versions' for update;
    v_after := coalesce(v_before, '{}'::jsonb);
    foreach d in array p_docs loop
        v_after := jsonb_set(v_after, array[d], jsonb_build_object(
            'version', terms_version(d) + 1,
            'since', now(),
            'grace_until', now() + make_interval(days => v_days)), true);
    end loop;
    v_after := v_after || jsonb_build_object(
        'date', to_char(now() at time zone 'UTC', 'YYYY-MM-DD'),
        'changes', v_changes,
        'changes_en', coalesce(v_en, v_changes));
    insert into platform_settings (key, value, updated_at)
    values ('terms_versions', v_after, now())
    on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at;

    insert into platform_actions (at, actor, org_id, kind, summary, before, after)
    values (clock_timestamp(), auth.uid(), null, 'terms_version',
            'Nouvelle version : ' || array_to_string(p_docs, ', ') || ' — ' || v_changes,
            v_before, v_after);
    return platform_terms_board();
end;
$$;

-- ------------------------------------------------------------
-- 6. Who may call what (063: born closed to PUBLIC and anon)
-- ------------------------------------------------------------
do $$
declare
    -- The app's doors.
    v_app text[] := array[
        'my_terms_state()',
        'accept_terms(text, integer, text, text)',
        'platform_terms_board()',
        'platform_terms_of(uuid)',
        'platform_terms_bump(text[], text, text, integer)'];
    -- Internal: the doors and the triggers call them as their owner.
    v_internal text[] := array[
        'terms_documents()',
        'terms_setting()',
        'terms_version(text)',
        'terms_accepted_version(uuid, text)',
        'terms_ok(uuid, text)',
        'trg_orders_terms()',
        'trg_courier_terms()',
        'org_create_core(uuid, text, text, text, text)',
        -- As 122 left it: my_courier_application (definer) reads it.
        'courier_rules()',
        -- As 112 left it: its definers read it.
        'courier_open_steps(uuid)'];
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
