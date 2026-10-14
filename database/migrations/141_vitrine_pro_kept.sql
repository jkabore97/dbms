-- ============================================================
-- 141_vitrine_pro_kept.sql — batch 146: a Basic business keeps the Pro
-- choices it makes for its vitrine; the street still shows them only with
-- Mara Pro.
--
-- The owner, for a shop, a farm and an association alike: the vitrine's
-- Pro options (Vitrine Plus, 068/093) — the layout (grille, grandes
-- photos, liste, menu), « Articles en tête » (six at most) and « Masquer
-- les épuisés » — are tried by a Basic business in the app's preview, and
-- saved. Until now set_storefront_style (110) threw them away for a
-- business without vitrine_plus and carried over the old ones; a business
-- that tried a list and saved got its grid back with no trace of what it
-- chose. From 141:
--
-- 1. set_storefront_style saves the Pro choices for a business without
--    vitrine_plus too, with the same checks as for Pro: six pinned at
--    most, each once, each one of its own products; the layout one of
--    grid, large, list, menu. A key the caller does not send is carried
--    over as before (an app before batch 146 sends none of the three on
--    Basic, so it never wipes what a lapsed Pro or a newer app saved); a
--    key sent is what is kept (« grid », [] and false clear it). Vitrine
--    Plus hidden by Mara's switchboard (110): unchanged — the basics only,
--    nothing of the Pro part taken. Still SECURITY DEFINER, as 068, 093
--    and 110 had it (an admin of the business only, said inside), path
--    pinned; its grants said again.
--
--    « Ouvert maintenant » is not a choice to keep: the schedule is a
--    basic (every plan saves it since 093) and storefront() computes the
--    banner from it for Vitrine Plus alone. Nothing to change there.
--
-- 2. The street keeps stripping them. Every function that hands the style
--    to anon or to the street, checked (batch 146's audit):
--      storefront()            (123, unchanged) — without vitrine_plus:
--                              style - pinned - hide_out_of_stock - layout,
--                              and no open_now; with it, everything.
--      vitrine_default_style() (136, replaced below) — see 3.
--      booking_schedule()      (125, unchanged) — reads the schedule only.
--      storefront_products / _stock / _featured / _previews, search_products,
--      storefront_directory    — never read storefront_style.
--      storefront_photo_allowed, 127's cover guard — the cover only.
--    The day the business gets vitrine_plus (the plan, or 085's cauris
--    unlock — org_has asks both), storefront() shows what it saved, with
--    nothing more to do; the day it loses it, the street goes back to the
--    basics and the choices stay.
--
-- 3. vitrine_default_style (107, 136): the kind's default look applies to
--    a vitrine never dressed — storefront_style = '{}'. A Basic business
--    that saves only Pro choices now has a style that is not '{}' while the
--    street sees none of it, so the default would have gone from its
--    vitrine for nothing. « Never dressed » is now read on what the street
--    may show: the whole style with Vitrine Plus, the style without the
--    three Pro keys otherwise. A Pro vitrine reads exactly as before.
--    platform_kind_models (107, replaced below, still definer and the
--    platform's only) counts its « vitrines jamais habillées » the same
--    way, so the console's number is the vitrines the default reaches.
--
-- 4. storefront_style_keeps_pro() — true: the app's sign that this is
--    installed, so its « Vos choix sont gardés » is said only where they
--    are (an app on a database before 141 says plainly that they are not,
--    and reads the style back after saving to be sure). Closed to anon
--    and PUBLIC, open to authenticated.
--
-- Re-runnable: create or replace only; nothing written to any row.
-- ============================================================

-- ------------------------------------------------------------
-- 1. set_storefront_style (110): the Pro choices kept on Basic
-- ------------------------------------------------------------
create or replace function set_storefront_style(p_org_id uuid, p_style jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_in       jsonb := coalesce(p_style, '{}'::jsonb);
    v_out      jsonb := '{}'::jsonb;
    v_old      jsonb;
    v_plus     boolean;
    v_hidden   boolean;
    v_text     text;
    v_pinned   jsonb;
    v_sched    jsonb;
    v_id       text;
    v_count    int;
begin
    if auth.uid() is null then
        raise exception 'set_storefront_style() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur peut habiller la vitrine';
    end if;
    v_plus := feature_access(p_org_id, 'vitrine_plus') = 'edit';
    -- 110: Vitrine Plus hidden by Mara's switchboard — the free basics
    -- only, and no door to Pro offered for it.
    v_hidden := feature_hidden(p_org_id, 'vitrine_plus');
    if v_plus and v_hidden then
        v_plus := false;
    end if;
    if not v_plus and cauris_param('vitrine_free_basics', 1) = 0 then
        perform feature_guard(p_org_id, 'vitrine_plus');
        if pro_locked(p_org_id, 'vitrine_plus') then
            raise exception 'Kaj Pro : la vitrine personnalisée fait partie de Kaj Pro. Ouvrez Compte › Kaj Pro pour passer à la formule payante.';
        end if;
        raise exception 'La vitrine personnalisée vous est fermée. Voyez le propriétaire.';
    end if;
    if jsonb_typeof(v_in) <> 'object' then
        raise exception 'Le style de la vitrine doit être un objet';
    end if;
    select storefront_style into v_old from orgs where id = p_org_id;
    v_old := coalesce(v_old, '{}'::jsonb);

    -- The basics.
    v_text := nullif(btrim(coalesce(v_in ->> 'tagline', '')), '');
    if v_text is not null then
        if char_length(v_text) > 80 then
            raise exception 'La phrase d''accroche fait 80 caractères au plus';
        end if;
        v_out := v_out || jsonb_build_object('tagline', v_text);
    end if;

    v_text := nullif(btrim(coalesce(v_in ->> 'hours', '')), '');
    if v_text is not null then
        if char_length(v_text) > 120 then
            raise exception 'Les horaires font 120 caractères au plus';
        end if;
        v_out := v_out || jsonb_build_object('hours', v_text);
    end if;

    v_sched := v_in -> 'schedule';
    if v_sched is not null and v_sched <> 'null'::jsonb then
        if jsonb_typeof(v_sched) <> 'object'
           or jsonb_typeof(v_sched -> 'days') <> 'array'
           or jsonb_array_length(v_sched -> 'days') = 0
           or coalesce(v_sched ->> 'open', '')  !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
           or coalesce(v_sched ->> 'close', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
           or v_sched ->> 'open' = v_sched ->> 'close'
           or exists (select 1 from jsonb_array_elements(v_sched -> 'days') d
                       where jsonb_typeof(d) <> 'number'
                          or d::text not in ('1','2','3','4','5','6','7'))
           or (select count(distinct d) from jsonb_array_elements(v_sched -> 'days') d)
              <> jsonb_array_length(v_sched -> 'days') then
            raise exception 'Les horaires : choisissez les jours, puis une heure d''ouverture et une de fermeture';
        end if;
        v_out := v_out || jsonb_build_object('schedule', jsonb_build_object(
            'days', (select jsonb_agg(d order by d::text::int)
                       from jsonb_array_elements(v_sched -> 'days') d),
            'open', v_sched ->> 'open',
            'close', v_sched ->> 'close'));
    end if;

    v_text := nullif(btrim(coalesce(v_in ->> 'accent', '')), '');
    if v_text is not null then
        if v_text !~ '^#[0-9A-Fa-f]{6}$' then
            raise exception 'La couleur doit s''écrire #RRGGBB';
        end if;
        if not v_plus and not upper(v_text) = any (vitrine_free_accents()) then
            perform feature_guard(p_org_id, 'vitrine_plus');
            raise exception 'Kaj Pro : les autres couleurs font partie de Kaj Pro. Choisissez l''une des six couleurs proposées.';
        end if;
        v_out := v_out || jsonb_build_object('accent', upper(v_text));
    end if;

    v_text := nullif(btrim(coalesce(v_in ->> 'cover_key', '')), '');
    if v_text is not null then
        if not exists (select 1 from documents d
                        where d.org_id = p_org_id and d.r2_key = v_text) then
            raise exception 'La photo de couverture doit être une photo de cette entreprise';
        end if;
        v_out := v_out || jsonb_build_object('cover_key', v_text);
    end if;

    -- Vitrine Plus hidden by Mara (110): the arrangement is not this
    -- business's to change for now — carried over, as before.
    if v_hidden and not v_plus then
        update orgs
           set storefront_style = v_out
               || jsonb_strip_nulls(jsonb_build_object(
                      'pinned', v_old -> 'pinned',
                      'hide_out_of_stock', v_old -> 'hide_out_of_stock',
                      'layout', v_old -> 'layout'))
         where id = p_org_id;
        return;
    end if;

    -- The arrangement: written by Pro as before; on Basic (141) written
    -- too — the street shows it once Pro is on — with a key not sent
    -- carried over, so an older app's Basic save keeps what was chosen.
    if v_plus or v_in ? 'pinned' then
        v_pinned := v_in -> 'pinned';
        if v_pinned is not null and jsonb_typeof(v_pinned) = 'array'
           and jsonb_array_length(v_pinned) > 0 then
            if jsonb_array_length(v_pinned) > 6 then
                raise exception 'Six articles épinglés au plus';
            end if;
            for v_id in select jsonb_array_elements_text(v_pinned) loop
                if v_id !~ '^[0-9a-fA-F-]{36}$' or not exists (
                    select 1 from products p
                     where p.id = v_id::uuid and p.org_id = p_org_id) then
                    raise exception 'Un article épinglé doit être un article de cette entreprise';
                end if;
            end loop;
            select count(distinct e) into v_count
              from jsonb_array_elements_text(v_pinned) e;
            if v_count <> jsonb_array_length(v_pinned) then
                raise exception 'Un article ne s''épingle qu''une fois';
            end if;
            v_out := v_out || jsonb_build_object('pinned', v_pinned);
        end if;
    elsif v_old ? 'pinned' then
        v_out := v_out || jsonb_build_object('pinned', v_old -> 'pinned');
    end if;

    if v_plus or v_in ? 'hide_out_of_stock' then
        if (v_in -> 'hide_out_of_stock') = 'true'::jsonb then
            v_out := v_out || '{"hide_out_of_stock": true}'::jsonb;
        end if;
    elsif v_old ? 'hide_out_of_stock' then
        v_out := v_out || jsonb_build_object('hide_out_of_stock', v_old -> 'hide_out_of_stock');
    end if;

    if v_plus or v_in ? 'layout' then
        v_text := nullif(btrim(coalesce(v_in ->> 'layout', '')), '');
        if v_text is not null and v_text <> 'grid' then
            if v_text not in ('large', 'list', 'menu') then
                raise exception 'La présentation est grille, grandes photos, liste ou menu';
            end if;
            v_out := v_out || jsonb_build_object('layout', v_text);
        end if;
    elsif v_old ? 'layout' then
        v_out := v_out || jsonb_build_object('layout', v_old -> 'layout');
    end if;

    update orgs set storefront_style = v_out where id = p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- 3. vitrine_default_style (136): « never dressed » as the street sees it
-- ------------------------------------------------------------
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
                       select product_cover_key(p.id)
                         from products p
                        where p.org_id = o.id and p.is_active and p.is_published
                          and exists (select 1 from documents doc
                                       where doc.product_id = p.id
                                         and doc_is_photo(doc.kind, doc.content_type))
                        order by p.is_service, p.name
                        limit 1) end))
               - case when vitrine_plus_on(o.id) then '{}'::text[]
                      else array['layout'] end
          from orgs o
          cross join lateral (select kind_setting(o.profile::text, 'vitrine_default') as v) d
         where o.id = p_org
           -- 141: a Basic business's kept Pro choices are not a dressing
           -- the street sees, so they do not end the kind's default.
           and (case when vitrine_plus_on(o.id) then o.storefront_style
                     else o.storefront_style - 'pinned' - 'hide_out_of_stock' - 'layout'
                end) = '{}'::jsonb
           and not o.showcase
           and jsonb_typeof(d.v) = 'object'
           and (vitrine_plus_on(o.id) or cauris_param('vitrine_free_basics', 1) = 1)),
        '{}'::jsonb);
$$;

-- ------------------------------------------------------------
-- 3b. platform_kind_models (107): its « vitrines jamais habillées » counted
--     on the same rule, so Réglages › Types d'activité's number is the
--     vitrines the kind's default look really reaches
-- ------------------------------------------------------------
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
            -- 141: « never dressed » as vitrine_default_style reads it — a
            -- Basic business's kept Pro choices are no dressing the street sees.
            'never_dressed', (select count(*) from o
                               where (case when vitrine_plus_on(o.id) then o.storefront_style
                                           else o.storefront_style - 'pinned' - 'hide_out_of_stock' - 'layout'
                                      end) = '{}'::jsonb),
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

-- ------------------------------------------------------------
-- 4. storefront_style_keeps_pro: the app's sign that 141 is here
-- ------------------------------------------------------------
create or replace function storefront_style_keeps_pro()
returns boolean
language sql
immutable
security invoker
set search_path = public
as $$
    select true;
$$;

-- ------------------------------------------------------------
-- Who may call what (063: a new function is born closed to anon and
-- PUBLIC; each door said again)
-- ------------------------------------------------------------
revoke execute on function set_storefront_style(uuid, jsonb) from public;
revoke execute on function vitrine_default_style(uuid)       from public;
revoke execute on function storefront_style_keeps_pro()      from public;
revoke execute on function platform_kind_models(text)        from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function set_storefront_style(uuid, jsonb) from anon;
        revoke execute on function vitrine_default_style(uuid)       from anon;
        revoke execute on function storefront_style_keeps_pro()      from anon;
        revoke execute on function platform_kind_models(text)        from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_storefront_style(uuid, jsonb) to authenticated;
        grant execute on function storefront_style_keeps_pro()      to authenticated;
        -- The platform's only, said inside (107).
        grant execute on function platform_kind_models(text)        to authenticated;
        -- Internal: storefront() (definer) calls it.
        revoke execute on function vitrine_default_style(uuid)       from authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
