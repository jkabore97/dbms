-- ============================================================
-- 186 — Admin levels: each platform admin, the parts of the console
-- they are given.
--
-- The owner: « I need admin levels so I can decide what they have
-- access to. » Until now a platform admin was a single flag: whoever held
-- it held everything — every business, the money, the street, the rules,
-- and the right to make more admins. And nothing kept a trace of who was
-- made admin, or when.
--
--   * profiles.platform_access: the sections an admin is given, among the
--     command center's five places (135) and one more —
--       today     « Aujourd'hui » (the to-do, the analyses)
--       clients   « Clients » (the businesses, the people, the couriers,
--                 the trainers — and, with it, the right to open any
--                 business as its admin would)
--       money     « Argent » (Pro, Événementiel, payments, settlements,
--                 cauris)
--       street    « La rue » (À la une, the examples, the reports)
--       settings  « Réglages » (the rules, the types of business, the
--                 journal, the terms)
--       admins    « Administrateurs » (who is admin, and with what)
--     Null: everything — every admin of before keeps what they had.
--
--   * Held on the server, not by hiding buttons. Every admin check in the
--     schema — some 150 functions and six policies, written over 170
--     migrations as « exists (select 1 from profiles where id = auth.uid()
--     and is_platform_admin) » — now asks caller_is_platform_admin(), and
--     caller_is_platform_admin() answers « admin, for what this request
--     is » : the RPC called names its section (platform_rpc_sections);
--     anything else — a table read, a business's own RPC — is « clients »,
--     the one section that opens other people's businesses. So an admin
--     without « Clients » is, in a business that is not theirs, nobody;
--     in their own, its owner as before.
--   * The pre-request hook (077's two_step_gate) refuses, first, an RPC of
--     a section the admin is not given: « Cette partie de la console ne
--     vous est pas ouverte. » (hint platform_section).
--   * platform_set_admin_access(user, on, sections): who is admin, with
--     what. Only an admin given « Administrateurs »; never oneself; an
--     admin of a few sections gives only those they hold, and never
--     touches an admin of everything. Each change a line in the journal
--     (104), with its undo. set_platform_admin (010) is now its « tout ».
--   * platform_admins(): the admins, their sections, whether their
--     authenticator is set up.
--   * platform_reset_two_step(user): an admin who lost their phone — their
--     authenticator removed, so the next sign-in shows the QR code again.
--     Journaled.
--
-- Shop, farm, association: nothing changes for them — the levels are the
-- platform's staff's, and a business's own roles are untouched.
-- ============================================================

alter table profiles add column if not exists platform_access text[];

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'profiles_platform_access_known') then
        alter table profiles add constraint profiles_platform_access_known
            check (platform_access is null
                   or platform_access <@ array['today', 'clients', 'money', 'street', 'settings', 'admins']);
    end if;
end $$;

comment on column profiles.platform_access is
    '186: the console sections a platform admin is given; null = all of them.';

-- ------------------------------------------------------------
-- The RPCs of each section
-- ------------------------------------------------------------
create table if not exists platform_rpc_sections (
    fn       text primary key,
    sections text[] not null
);
alter table platform_rpc_sections enable row level security;
comment on table platform_rpc_sections is
    '186: the console section(s) each admin RPC belongs to. An RPC not listed is « clients ».';

insert into platform_rpc_sections (fn, sections) values
    -- Aujourd'hui
    ('platform_today',                          '{today}'),
    ('platform_today_counts',                   '{today}'),
    ('platform_todo',                           '{today}'),
    ('platform_todo_list',                      '{today}'),
    ('review_todo_counts',                      '{today}'),
    ('help_todo_counts',                        '{today}'),
    ('help_console',                            '{today,clients}'),
    ('spot_refunds_todo',                       '{today,money}'),
    ('plan_requests_open',                      '{today,money}'),
    ('platform_analytics_headline',             '{today}'),
    ('platform_analytics_by_currency',          '{today}'),
    ('platform_business_performance',           '{today}'),
    ('platform_business_currencies',            '{today}'),
    ('platform_search',                         '{today,clients}'),
    ('platform_overview',                       '{today,clients}'),
    ('send_platform_message',                   '{today,clients}'),
    ('platform_message_send',                   '{today,clients}'),
    -- Clients
    ('all_orgs',                                '{clients}'),
    ('search_orgs',                             '{clients}'),
    ('platform_org_overview',                   '{clients}'),
    ('platform_user_orgs',                      '{clients}'),
    ('platform_people',                         '{clients,admins}'),
    ('platform_created_businesses',             '{clients}'),
    ('platform_pending_applications',           '{clients}'),
    ('pending_org_applications',                '{clients}'),
    ('approve_org_application',                 '{clients}'),
    ('reject_org_application',                  '{clients}'),
    ('archive_org',                             '{clients}'),
    ('restore_org',                             '{clients}'),
    ('delete_org',                              '{clients}'),
    ('create_org',                              '{clients}'),
    ('platform_update_org_identity',            '{clients}'),
    ('set_org_suspended',                       '{clients}'),
    ('set_org_verified',                        '{clients}'),
    ('platform_couriers',                       '{clients}'),
    ('platform_courier_application',            '{clients}'),
    ('platform_courier_applications',           '{clients}'),
    ('platform_decide_courier_application',     '{clients}'),
    ('decide_courier',                          '{clients}'),
    ('list_trainers',                           '{clients}'),
    ('assign_trainer',                          '{clients}'),
    ('unassign_trainer',                        '{clients}'),
    ('platform_set_trainer',                    '{clients}'),
    ('platform_trainer_state',                  '{clients}'),
    ('set_trainer_by_phone',                    '{clients}'),
    ('merge_accounts',                          '{clients}'),
    ('account_merge_preview',                   '{clients}'),
    ('platform_add_member',                     '{clients}'),
    ('platform_bulk',                           '{clients}'),
    ('platform_feature_board',                  '{clients,settings}'),
    ('platform_actions_page',                   '{clients,settings}'),
    -- Argent
    ('set_org_plan',                            '{money}'),
    ('handle_plan_request',                     '{money}'),
    ('plan_terms',                              '{money}'),
    ('platform_wave_payments',                  '{money}'),
    ('set_org_wave_allowed',                    '{money}'),
    ('set_wave_merchant_ref',                   '{money}'),
    ('platform_delivery_settlement',            '{money}'),
    ('platform_delivery_settlement_by_currency','{money}'),
    ('cauris_watch',                            '{money}'),
    ('cauris_rules_list',                       '{money}'),
    ('cauris_costs_list',                       '{money}'),
    ('set_cauris_rule',                         '{money}'),
    ('set_cauris_cost',                         '{money}'),
    ('platform_set_cauris_cost',                '{money}'),
    ('platform_give_cauris',                    '{money}'),
    ('platform_give_unlock',                    '{money}'),
    ('admin_events_settings',                   '{money}'),
    ('admin_events_set',                        '{money}'),
    ('admin_event_template_premium',            '{money}'),
    ('events_allowed_orgs',                     '{money}'),
    ('set_events_allowed',                      '{money}'),
    ('platform_spot_refunds',                   '{today,money}'),
    ('platform_spot_refund_done',               '{today,money}'),
    -- La rue
    ('platform_featured_candidates',            '{street}'),
    ('set_product_featured',                    '{street}'),
    ('showcase_list',                           '{street}'),
    ('showcase_join',                           '{street}'),
    ('showcase_seed',                           '{street}'),
    ('set_showcase_visible',                    '{street}'),
    ('platform_reports',                        '{street}'),
    ('platform_handle_report',                  '{street}'),
    ('platform_review_queue',                   '{today,street}'),
    ('platform_promotions',                     '{street}'),
    ('decide_promotion',                        '{street}'),
    ('platform_stop_promotion',                 '{street}'),
    ('platform_change_promotion_product',       '{street}'),
    -- Réglages (the Pro console's switches are platform settings too)
    ('set_platform_setting',                    '{settings,money}'),
    ('platform_set_setting',                    '{settings}'),
    ('platform_settings_board',                 '{settings}'),
    ('platform_kind_models',                    '{settings}'),
    ('platform_set_kind_setting',               '{settings}'),
    ('platform_restore_kind_setting',           '{settings}'),
    ('platform_set_feature_rule',               '{settings}'),
    ('platform_restore_feature_rule',           '{settings}'),
    ('platform_feature_impact',                 '{settings}'),
    ('platform_set_application_form',           '{settings}'),
    ('platform_restore_application_form',       '{settings}'),
    ('platform_audit_page',                     '{settings}'),
    ('platform_terms_board',                    '{settings}'),
    ('platform_terms_bump',                     '{settings}'),
    ('platform_terms_of',                       '{settings}'),
    ('send_test_notification',                  '{settings}'),
    -- « Annuler », offered after an act in every section
    ('platform_undo',                           '{today,clients,money,street,settings,admins}'),
    -- Administrateurs
    ('set_platform_admin',                      '{admins}'),
    ('platform_set_admin_access',               '{admins}'),
    ('platform_admins',                         '{admins}'),
    ('platform_reset_two_step',                 '{admins}')
on conflict (fn) do update set sections = excluded.sections;

-- The section(s) of the request in flight: its RPC's, or « clients ».
create or replace function platform_request_sections()
returns text[]
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        (select s.sections from platform_rpc_sections s
          where s.fn = substring(ltrim(coalesce(current_setting('request.path', true), ''), '/') from '^rpc/([a-z0-9_]+)$')),
        array['clients']);
$$;

-- An admin given that section (or everything).
create or replace function platform_admin_can(p_section text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (select 1 from profiles
                    where id = auth.uid() and is_platform_admin
                      and (platform_access is null or p_section = any (platform_access)));
$$;

-- 103's helper, now « admin, for what this request is ».
create or replace function caller_is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (select 1 from profiles
                    where id = auth.uid() and is_platform_admin
                      and (platform_access is null or platform_access && platform_request_sections()));
$$;

-- ------------------------------------------------------------
-- Every inline check becomes caller_is_platform_admin()
-- ------------------------------------------------------------
-- The forms the schema wrote, the caller's own row asked: « exists (select
-- 1 from profiles where id = auth.uid() and is_platform_admin) », with
-- « profiles. » or without, v_actor (= auth.uid()) for the actor, an alias
-- p or pr. Left as they are: the checks about somebody else (« is the
-- person being removed an admin »), the two-step's own (every admin has
-- the second step, whatever their sections), and « may I delete my
-- account » (an admin may not, whatever their sections).
do $$
declare
    r record;
    v_def text;
    v_new text;
begin
    for r in
        select p.oid, p.proname
          from pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.prokind = 'f'
           and p.prosrc like '%is_platform_admin%'
           and p.proname not in ('caller_is_platform_admin', 'platform_admin_can', 'two_step_gate', 'my_two_step',
                                 'guard_is_platform_admin', 'set_platform_admin',
                                 'delete_my_account_check', 'delete_my_account_plan')
    loop
        v_def := pg_get_functiondef(r.oid);
        v_new := regexp_replace(v_def,
            'exists\s*\(\s*select\s+1\s+from\s+(public\.)?profiles\s+where\s+((public\.)?profiles\.)?id\s*=\s*(auth\.uid\(\)|v_actor)\s+and\s+((public\.)?profiles\.)?is_platform_admin\s*\)',
            'caller_is_platform_admin()', 'gi');
        v_new := regexp_replace(v_new,
            'exists\s*\(\s*select\s+1\s+from\s+(?:public\.)?profiles\s+(p|pr)\s+where\s+\1\.id\s*=\s*auth\.uid\(\)\s+and\s+\1\.is_platform_admin\s*\)',
            'caller_is_platform_admin()', 'gi');
        if v_new <> v_def then
            execute v_new;
        end if;
    end loop;
end $$;

-- The two that read the flag off the caller's row beside other things.
create or replace function is_org_member(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((
        select caller_is_platform_admin()
            or exists (select 1 from memberships m
                        where m.user_id = p.id and m.org_id = p_org_id)
            -- 133: a trainer's temporary, read-only access, while it lasts.
            or (p.is_trainer and exists (
                    select 1 from help_access_grants g
                     where g.trainer_id = p.id and g.org_id = p_org_id
                       and g.revoked_at is null and g.expires_at > now()))
          from profiles p
         where p.id = auth.uid()), false);
$$;

create or replace function has_full_visibility(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((
        select caller_is_platform_admin()
            or exists (select 1 from memberships m
                        where m.user_id = p.id and m.org_id = p_org_id
                          and m.visibility = 'full')
            -- 133: a trainer's temporary, read-only access, while it lasts.
            or (p.is_trainer and exists (
                    select 1 from help_access_grants g
                     where g.trainer_id = p.id and g.org_id = p_org_id
                       and g.revoked_at is null and g.expires_at > now()))
          from profiles p
         where p.id = auth.uid()), false);
$$;

-- The six policies that asked the flag inline (as the caller, under RLS:
-- their own row). All of them about businesses — « clients »; the audit
-- trail is also Réglages' « Audit ».
alter policy "memberships revoked by org admins" on memberships
    using (is_org_admin(org_id) and (role <> 'owner' or user_id = auth.uid()
           or exists (select 1 from profiles where profiles.id = auth.uid() and profiles.is_platform_admin
                       and (profiles.platform_access is null or 'clients' = any (profiles.platform_access)))));
alter policy "audit log readable by the owner" on audit_log
    using (exists (select 1 from memberships m
                    where m.org_id = audit_log.org_id and m.user_id = auth.uid()
                      and m.role = any (array['owner'::role_name, 'super_admin'::role_name]))
           or exists (select 1 from profiles where profiles.id = auth.uid() and profiles.is_platform_admin
                       and (profiles.platform_access is null or profiles.platform_access && array['clients', 'settings'])));
alter policy "feature rules written by the owner" on org_feature_rules
    using ((exists (select 1 from memberships m
                     where m.org_id = org_feature_rules.org_id and m.user_id = auth.uid() and m.role = 'owner'::role_name)
            or exists (select 1 from profiles where profiles.id = auth.uid() and profiles.is_platform_admin
                        and (profiles.platform_access is null or 'clients' = any (profiles.platform_access))))
           and feature_access(org_id, 'team_access') = 'edit')
    with check ((exists (select 1 from memberships m
                          where m.org_id = org_feature_rules.org_id and m.user_id = auth.uid() and m.role = 'owner'::role_name)
                 or exists (select 1 from profiles where profiles.id = auth.uid() and profiles.is_platform_admin
                             and (profiles.platform_access is null or 'clients' = any (profiles.platform_access))))
                and feature_access(org_id, 'team_access') = 'edit');
alter policy "tombstones readable by platform admins" on deleted_orgs
    using (exists (select 1 from profiles where profiles.id = auth.uid() and profiles.is_platform_admin
                    and (profiles.platform_access is null or 'clients' = any (profiles.platform_access))));
alter policy "applications readable by applicant and platform" on org_applications
    using (applicant_id = auth.uid()
           or exists (select 1 from profiles where profiles.id = auth.uid() and profiles.is_platform_admin
                       and (profiles.platform_access is null or 'clients' = any (profiles.platform_access))));
alter policy "applications decided by platform admins" on org_applications
    using (exists (select 1 from profiles where profiles.id = auth.uid() and profiles.is_platform_admin
                    and (profiles.platform_access is null or 'clients' = any (profiles.platform_access))))
    with check (exists (select 1 from profiles where profiles.id = auth.uid() and profiles.is_platform_admin
                         and (profiles.platform_access is null or 'clients' = any (profiles.platform_access))));

-- ------------------------------------------------------------
-- The pre-request hook (077): the second step, then the section
-- ------------------------------------------------------------
create or replace function two_step_gate()
returns void
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_admin  boolean;
    v_access text[];
    v_path   text := ltrim(coalesce(current_setting('request.path', true), ''), '/');
    v_fn     text;
    v_need   text[];
begin
    if auth.uid() is null then
        return;
    end if;
    select is_platform_admin, platform_access into v_admin, v_access from profiles where id = auth.uid();
    if not coalesce(v_admin, false) then
        return;
    end if;
    if coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' and two_step_on() and v_path <> 'rpc/my_two_step' then
        raise exception 'Validation en deux étapes requise'
            using errcode = '42501',
                  hint = 'two_step_required';
    end if;
    if v_access is null then
        return;
    end if;
    v_fn := substring(v_path from '^rpc/([a-z0-9_]+)$');
    if v_fn is null then
        return;
    end if;
    select sections into v_need from platform_rpc_sections where fn = v_fn;
    if v_need is not null and not (v_access && v_need) then
        raise exception 'Cette partie de la console ne vous est pas ouverte.'
            using errcode = '42501',
                  hint = 'platform_section';
    end if;
end;
$$;

-- 010's guard: platform access — the flag or the sections — changed only
-- by an admin given « Administrateurs » (or the trusted context, no JWT).
create or replace function guard_is_platform_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_caller uuid := auth.uid();
    v_becoming boolean;
begin
    if tg_op = 'INSERT' then
        v_becoming := coalesce(new.is_platform_admin, false) or new.platform_access is not null;
    else
        v_becoming := new.is_platform_admin is distinct from old.is_platform_admin
                   or new.platform_access is distinct from old.platform_access;
    end if;

    if v_becoming and v_caller is not null and not platform_admin_can('admins') then
        raise exception 'Only a platform administrator can change platform access'
            using errcode = 'insufficient_privilege';
    end if;
    return new;
end;
$$;

-- ------------------------------------------------------------
-- Who is admin, with what
-- ------------------------------------------------------------
create or replace function platform_access_words(p_on boolean, p_access text[])
returns text
language sql
immutable
set search_path = public
as $$
    select case
        when not coalesce(p_on, false) then 'plus administrateur'
        when p_access is null then 'administrateur (tout)'
        when cardinality(p_access) = 0 then 'administrateur (aucune section)'
        else 'administrateur (' || array_to_string(array(
            select case s when 'today' then 'Aujourd''hui' when 'clients' then 'Clients' when 'money' then 'Argent'
                          when 'street' then 'La rue' when 'settings' then 'Réglages' when 'admins' then 'Administrateurs' end
              from unnest(array['today', 'clients', 'money', 'street', 'settings', 'admins']) s
             where s = any (p_access)), ', ') || ')'
    end;
$$;

create or replace function platform_set_admin_access(p_user_id uuid, p_on boolean, p_access text[] default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_me      uuid := auth.uid();
    v_mine    text[];
    t         profiles;
    v_access  text[];
    v_name    text;
begin
    if not platform_admin_can('admins') then
        raise exception 'Réservé aux administrateurs qui gèrent les accès.';
    end if;
    if p_user_id = v_me then
        raise exception 'Vous ne pouvez pas changer vos propres accès.';
    end if;
    select * into t from profiles where id = p_user_id;
    if not found then
        raise exception 'Compte introuvable.';
    end if;
    v_access := case when coalesce(p_on, false) and p_access is not null then
                    array(select distinct s from unnest(p_access) s order by 1) end;
    if v_access is not null and not (v_access <@ array['today', 'clients', 'money', 'street', 'settings', 'admins']) then
        raise exception 'Section inconnue.';
    end if;
    -- An admin of a few sections gives only those they hold, and never
    -- touches an admin of everything.
    select platform_access into v_mine from profiles where id = v_me;
    if v_mine is not null then
        if t.is_platform_admin and t.platform_access is null then
            raise exception 'Seul un administrateur complet modifie un administrateur complet.';
        end if;
        if coalesce(p_on, false) and (v_access is null or not (v_access <@ v_mine)) then
            raise exception 'Vous ne pouvez donner que les sections que vous avez.';
        end if;
    end if;
    if t.is_platform_admin = coalesce(p_on, false) and t.platform_access is not distinct from v_access then
        return null;
    end if;

    update profiles set is_platform_admin = coalesce(p_on, false), platform_access = v_access
     where id = p_user_id;

    v_name := coalesce(nullif(btrim(t.full_name), ''), 'Un compte');
    return platform_log_action(
        null, 'admin_access',
        v_name || ' : ' || platform_access_words(p_on, v_access),
        jsonb_build_object('user_id', p_user_id, 'on', t.is_platform_admin, 'access', to_jsonb(t.platform_access)),
        jsonb_build_object('user_id', p_user_id, 'on', coalesce(p_on, false), 'access', to_jsonb(v_access)),
        'platform_undo_admin_access',
        jsonb_build_object('user_id', p_user_id, 'on', t.is_platform_admin, 'access', to_jsonb(t.platform_access)));
end;
$$;

-- « Annuler » of the above: the access as it was.
create or replace function platform_undo_admin_access(p_args jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not platform_admin_can('admins') then
        raise exception 'Réservé aux administrateurs qui gèrent les accès.';
    end if;
    perform platform_set_admin_access(
        (p_args ->> 'user_id')::uuid,
        coalesce((p_args ->> 'on')::boolean, false),
        case when jsonb_typeof(p_args -> 'access') = 'array'
             then array(select jsonb_array_elements_text(p_args -> 'access')) end);
end;
$$;
insert into platform_undo_fns (fn) values ('platform_undo_admin_access') on conflict do nothing;

-- 010's call, kept: « admin » is everything, « not » is nothing.
create or replace function set_platform_admin(p_user_id uuid, p_value boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    perform platform_set_admin_access(p_user_id, coalesce(p_value, false), null);
end;
$$;

-- The admins, with their sections and their authenticator.
create or replace function platform_admins()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not platform_admin_can('admins') then
        raise exception 'Réservé aux administrateurs qui gèrent les accès.';
    end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object(
            'user_id', p.id,
            'name', p.full_name,
            'email', u.email,
            'phone', u.phone,
            'access', to_jsonb(p.platform_access),
            'two_step', exists (select 1 from auth.mfa_factors f where f.user_id = p.id and f.status::text = 'verified'),
            'me', p.id = auth.uid())
            order by p.platform_access is not null, p.full_name)
          from profiles p left join auth.users u on u.id = p.id
         where p.is_platform_admin), '[]'::jsonb);
end;
$$;

-- An admin who lost their phone: their authenticator removed, so the next
-- sign-in shows the QR code again.
create or replace function platform_reset_two_step(p_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    t profiles;
    v_mine text[];
    v_n int;
begin
    if not platform_admin_can('admins') then
        raise exception 'Réservé aux administrateurs qui gèrent les accès.';
    end if;
    if p_user_id = auth.uid() then
        raise exception 'Vous ne pouvez pas réinitialiser votre propre application.';
    end if;
    select * into t from profiles where id = p_user_id;
    if not found or not t.is_platform_admin then
        raise exception 'Ce compte n''est pas administrateur.';
    end if;
    select platform_access into v_mine from profiles where id = auth.uid();
    if v_mine is not null and t.platform_access is null then
        raise exception 'Seul un administrateur complet modifie un administrateur complet.';
    end if;
    delete from auth.mfa_factors where user_id = p_user_id;
    get diagnostics v_n = row_count;
    return platform_log_action(
        null, 'admin_two_step_reset',
        coalesce(nullif(btrim(t.full_name), ''), 'Un compte') || ' : application d''authentification réinitialisée',
        jsonb_build_object('user_id', p_user_id, 'factors', v_n), null, null, null);
end;
$$;

-- ------------------------------------------------------------
-- The doors (063)
-- ------------------------------------------------------------
revoke execute on function platform_request_sections() from public;
revoke execute on function platform_admin_can(text) from public;
revoke execute on function platform_access_words(boolean, text[]) from public;
revoke execute on function platform_set_admin_access(uuid, boolean, text[]) from public;
revoke execute on function platform_undo_admin_access(jsonb) from public;
revoke execute on function platform_admins() from public;
revoke execute on function platform_reset_two_step(uuid) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function platform_request_sections() from anon;
        revoke execute on function platform_admin_can(text) from anon;
        revoke execute on function platform_access_words(boolean, text[]) from anon;
        revoke execute on function platform_set_admin_access(uuid, boolean, text[]) from anon;
        revoke execute on function platform_undo_admin_access(jsonb) from anon;
        revoke execute on function platform_admins() from anon;
        revoke execute on function platform_reset_two_step(uuid) from anon;
        revoke execute on function set_platform_admin(uuid, boolean) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- the helpers run inside the definer functions, as their owner
        revoke execute on function platform_request_sections() from authenticated;
        revoke execute on function platform_admin_can(text) from authenticated;
        revoke execute on function platform_access_words(boolean, text[]) from authenticated;
        revoke execute on function platform_undo_admin_access(jsonb) from authenticated;
        grant execute on function platform_set_admin_access(uuid, boolean, text[]) to authenticated;
        grant execute on function platform_admins() to authenticated;
        grant execute on function platform_reset_two_step(uuid) to authenticated;
        grant execute on function set_platform_admin(uuid, boolean) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
