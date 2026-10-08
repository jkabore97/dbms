-- ============================================================
-- 108_owner_fixes.sql — the owner's next list (batch 108, items E1–E6).
--
-- Most of the batch is the app's: the bar on every tool page (E1), the
-- administration in « Plus » (E2), the helper line of « Nouvelle vente »
-- (E4), the device code asked only of somebody who belongs to a business
-- (E6). What the database holds:
--
--   1. E3 « Ma position sur la carte » should be « La position de ma
--      boutique »: Le Chemin's « pin » step names the business's place —
--      « La position de ma boutique », for a farm « La position de ma
--      ferme » (an association is not on the path). Only the row as 097
--      wrote it is changed: a title Mara changed by hand stays.
--   2. E5 « Some features do not allow to be paid with cauris even when you
--      have enough »: the audit's server half.
--        * min_days — the days a new business waits before cauris open a
--          tool (085: accounting 60, tontines 90) — is the platform's to
--          change now, with the price: platform_set_cauris_cost(feature,
--          cost, min_days), checked on the server, journaled with its
--          « Annuler » (platform_undo_cauris_cost, refused once changed
--          since). 085's set_cauris_cost (the price alone) goes through it,
--          so an older console's change is journaled too.
--        * spend_cauris says why, never a wall: the wait with its date
--          (« Disponible avec vos cauris dans 23 jours, le 31/10/2026 »);
--          and it no longer takes cauris for nothing — a tool the
--          business's kind does not have (104's catalog: the analyses of an
--          association; 099: its delivery — the app already hides both), or
--          a tool a paid Mara Pro already opens. 104's refusal of a hidden
--          tool is kept word for word (110's switches rely on it).
--
-- Nothing else a shop, a farm, an association or a vitrine shows moves.
-- No destructive statement: each function replaced in place with its own
-- signature, the step's text updated only where it is 097's.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Le Chemin's « pin » step: the business's own place (E3)
-- ------------------------------------------------------------
update path_steps
   set title = 'La position de ma boutique',
       title_farm = 'La position de ma ferme'
 where key = 'pin'
   and title = 'Ma position sur la carte'
   and title_farm is null;

-- ------------------------------------------------------------
-- 2. The price and the wait of a tool, the platform's (E5)
-- ------------------------------------------------------------
-- A tool in the journal's words: 100's label, and the photo slot.
create or replace function cauris_cost_label(p_feature text)
returns text
language sql
immutable
set search_path = public
as $$
    select case p_feature
        when 'photo_slot' then 'une place photo'
        else cauris_feature_label(p_feature)
    end;
$$;

create or replace function platform_set_cauris_cost(p_feature text, p_cost int, p_min_days int)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_before cauris_costs%rowtype;
begin
    perform platform_only();
    select * into v_before from cauris_costs where feature = p_feature for update;
    if not found then
        raise exception 'Outil inconnu : %', coalesce(p_feature, '');
    end if;
    if p_cost is null or p_cost <= 0 or p_cost > 1000000 then
        raise exception 'Prix hors limites';
    end if;
    if p_min_days is null or p_min_days < 0 or p_min_days > 3650 then
        raise exception 'Une attente de 0 à 3650 jours, s''il vous plaît.';
    end if;
    -- A photo slot is bought on the spot (100's buy_photo_slot asks no wait).
    if p_feature = 'photo_slot' and p_min_days <> 0 then
        raise exception 'Une place photo s''achète sans attente.';
    end if;
    if p_cost = v_before.cost and p_min_days = v_before.min_days then
        return null;  -- nothing changed, nothing to write in the journal
    end if;

    update cauris_costs set cost = p_cost, min_days = p_min_days
     where feature = p_feature;
    return platform_log_action(
        null, 'cauris_cost',
        'Cauris, ' || cauris_cost_label(p_feature) || ' : ' || v_before.cost || ' → ' || p_cost
            || ' cauris, attente ' || v_before.min_days || ' → ' || p_min_days || ' jours',
        jsonb_build_object('feature', p_feature, 'cost', v_before.cost, 'min_days', v_before.min_days),
        jsonb_build_object('feature', p_feature, 'cost', p_cost, 'min_days', p_min_days),
        'platform_undo_cauris_cost',
        jsonb_build_object('feature', p_feature,
                           'before', jsonb_build_object('cost', v_before.cost, 'min_days', v_before.min_days),
                           'after',  jsonb_build_object('cost', p_cost, 'min_days', p_min_days)));
end;
$$;

-- « Annuler »: the price and the wait as they were, unless changed since.
create or replace function platform_undo_cauris_cost(p_args jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_now cauris_costs%rowtype;
begin
    perform platform_only();
    select * into v_now from cauris_costs where feature = p_args->>'feature' for update;
    if not found then
        raise exception 'Outil inconnu : %', coalesce(p_args->>'feature', '');
    end if;
    if v_now.cost <> (p_args #>> '{after,cost}')::int
       or v_now.min_days <> (p_args #>> '{after,min_days}')::int then
        raise exception 'Ce prix a changé depuis : annulez d''abord le dernier changement.';
    end if;
    update cauris_costs
       set cost = (p_args #>> '{before,cost}')::int,
           min_days = (p_args #>> '{before,min_days}')::int
     where feature = v_now.feature;
end;
$$;

insert into platform_undo_fns (fn) values ('platform_undo_cauris_cost')
on conflict (fn) do nothing;

-- 085's price alone (an older console): the same check, the same journal,
-- the wait kept.
create or replace function set_cauris_cost(p_feature text, p_cost int)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Only the platform sets the cauris prices';
    end if;
    perform platform_set_cauris_cost(
        p_feature, p_cost,
        coalesce((select min_days from cauris_costs where feature = p_feature), 0));
end;
$$;

-- ------------------------------------------------------------
-- 3. Spending: the reason said, nothing taken for nothing (E5)
-- ------------------------------------------------------------
-- 104's spend_cauris, with three refusals before any cauris move: the
-- wait with its date (it was a number of days only), a tool this kind of
-- business does not have, a tool a paid Mara Pro already opens. A
-- business on Mara Pro complet bought with cauris may still buy a tool:
-- it stays open after Pro complet ends. Everything else as 104 wrote it.
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
        raise exception 'Votre entreprise est sur Mara Pro : cet outil est déjà ouvert, vos cauris restent à vous.';
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

-- ------------------------------------------------------------
-- Grants: born closed (063); each opened to whom it is for.
-- ------------------------------------------------------------
revoke execute on function cauris_cost_label(text)                      from public;
revoke execute on function platform_set_cauris_cost(text, int, int)     from public;
revoke execute on function platform_undo_cauris_cost(jsonb)             from public;
revoke execute on function set_cauris_cost(text, int)                   from public;
revoke execute on function spend_cauris(uuid, text)                     from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function cauris_cost_label(text)                  from anon;
        revoke execute on function platform_set_cauris_cost(text, int, int) from anon;
        revoke execute on function platform_undo_cauris_cost(jsonb)         from anon;
        revoke execute on function set_cauris_cost(text, int)               from anon;
        revoke execute on function spend_cauris(uuid, text)                 from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- The journal's words and the undo are the database's own: the
        -- undo runs through platform_undo().
        revoke execute on function cauris_cost_label(text)                  from authenticated;
        revoke execute on function platform_undo_cauris_cost(jsonb)         from authenticated;
        grant  execute on function platform_set_cauris_cost(text, int, int) to authenticated;
        grant  execute on function set_cauris_cost(text, int)               to authenticated;
        grant  execute on function spend_cauris(uuid, text)                 to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
