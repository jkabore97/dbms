-- ============================================================
-- 093_vitrine_dressing.sql — every vitrine dresses itself; Pro arranges it.
--
-- The owner asked for vitrine customisation for every user. Recommended
-- and agreed: chosen presets, not free design — a shopkeeper on a phone
-- picks well among good options, and the street stays legible.
--
-- 1. For every business (the basics): a cover photograph, the buttons'
--    colour among six that read on the street's paper, a tagline, and the
--    opening hours — now days and times (schedule), from which the line
--    « Lun–Sam 8h–19h » is written.
-- 2. With Mara Pro or its cauris unlock (vitrine_plus, 068): the shelf's
--    layout (grille, grandes photos, liste, menu), up to six articles « à
--    la une », hiding what is out of stock, any colour, and the live
--    « Ouvert maintenant / Fermé » banner the schedule drives.
--
-- A platform setting, vitrine_free_basics (1), opens the basics; at 0 the
-- 068 behaviour returns whole (everything behind Pro).
--
-- A business that stops being Pro keeps what it wrote — the Pro keys stay
-- stored and are carried over by every save it makes meanwhile — and the
-- street shows only the basics until it is Pro again.
--
-- No destructive statement: functions replaced with their own signatures.
-- ============================================================

insert into platform_settings (key, value) values ('vitrine_free_basics', '1')
on conflict (key) do nothing;

-- The six colours of the vitrine card (vitrine_plus_card.dart), the only
-- ones open to a business without vitrine_plus.
create or replace function vitrine_free_accents()
returns text[]
language sql
immutable
set search_path = public
as $$
    select array['#B1541A', '#2E7D5B', '#1F5FA8', '#8E3B6B', '#B8860B', '#444444'];
$$;

-- Open now, by the schedule, in Ouagadougou's time. Null without one.
-- A close earlier than the open is a night shop: open past midnight.
create or replace function vitrine_open_now(p_schedule jsonb)
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
    v_now   timestamp := now() at time zone 'Africa/Ouagadougou';
    v_day   int := extract(isodow from v_now)::int;
    v_prev  int := case when v_day = 1 then 7 else v_day - 1 end;
    v_t     time := v_now::time;
    v_open  time;
    v_close time;
begin
    if p_schedule is null or jsonb_typeof(p_schedule) <> 'object'
       or jsonb_typeof(p_schedule -> 'days') <> 'array' then
        return null;
    end if;
    v_open  := (p_schedule ->> 'open')::time;
    v_close := (p_schedule ->> 'close')::time;
    if v_close > v_open then
        return (p_schedule -> 'days') @> to_jsonb(v_day)
           and v_t >= v_open and v_t < v_close;
    end if;
    return ((p_schedule -> 'days') @> to_jsonb(v_day) and v_t >= v_open)
        or ((p_schedule -> 'days') @> to_jsonb(v_prev) and v_t < v_close);
exception when others then
    return null;
end;
$$;

-- 068's writer, split: the basics for everyone, the arrangement for Pro.
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
    if not v_plus and cauris_param('vitrine_free_basics', 1) = 0 then
        if pro_locked(p_org_id, 'vitrine_plus') then
            raise exception 'Kaj Pro : la vitrine personnalisée fait partie de Kaj Pro. Ouvrez Compte › Kaj Pro pour passer à la formule payante.';
        end if;
        raise exception 'La vitrine personnalisée vous est fermée. Voyez le propriétaire.';
    end if;
    if jsonb_typeof(v_in) <> 'object' then
        raise exception 'Le style de la vitrine doit être un objet';
    end if;
    select storefront_style into v_old from orgs where id = p_org_id;

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

    -- The arrangement: written by vitrine_plus, carried over otherwise.
    if not v_plus then
        update orgs
           set storefront_style = v_out
               || jsonb_strip_nulls(jsonb_build_object(
                      'pinned', v_old -> 'pinned',
                      'hide_out_of_stock', v_old -> 'hide_out_of_stock',
                      'layout', v_old -> 'layout'))
         where id = p_org_id;
        return;
    end if;

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

    if (v_in -> 'hide_out_of_stock') = 'true'::jsonb then
        v_out := v_out || '{"hide_out_of_stock": true}'::jsonb;
    end if;

    v_text := nullif(btrim(coalesce(v_in ->> 'layout', '')), '');
    if v_text is not null and v_text <> 'grid' then
        if v_text not in ('large', 'list', 'menu') then
            raise exception 'La présentation est grille, grandes photos, liste ou menu';
        end if;
        v_out := v_out || jsonb_build_object('layout', v_text);
    end if;

    update orgs set storefront_style = v_out where id = p_org_id;
end;
$$;

-- 090's window: the basics for every plan, the arrangement and the live
-- banner with vitrine_plus.
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

-- 080's photo gate: a cover is servable for every plan while the basics
-- are open.
create or replace function storefront_photo_allowed(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from documents d
        join products p on p.id = d.product_id
        join orgs     o on o.id = p.org_id
        where d.r2_key = p_key
          and p.is_active
          and p.is_published
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
    ) or exists (
        select 1
        from orgs o
        where o.storefront_style ->> 'cover_key' = p_key
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
          and (org_has(o.id, 'vitrine_plus')
               or cauris_param('vitrine_free_basics', 1) = 1)
    ) or exists (
        select 1
        from orgs o
        where o.logo_key = p_key
          and o.storefront_enabled
          and o.archived_at  is null
          and o.suspended_at is null
    );
$$;

revoke execute on function vitrine_free_accents()           from public;
revoke execute on function vitrine_open_now(jsonb)          from public;
revoke execute on function set_storefront_style(uuid, jsonb) from public;
revoke execute on function storefront(text)                  from public;
revoke execute on function storefront_photo_allowed(text)    from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function vitrine_free_accents()            from anon;
        revoke execute on function vitrine_open_now(jsonb)           from anon;
        revoke execute on function set_storefront_style(uuid, jsonb) from anon;
        grant execute on function storefront(text)                   to anon;
        grant execute on function storefront_photo_allowed(text)     to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function vitrine_free_accents()            from authenticated;
        revoke execute on function vitrine_open_now(jsonb)           from authenticated;
        grant execute on function set_storefront_style(uuid, jsonb)  to authenticated;
        grant execute on function storefront(text)                   to authenticated;
        grant execute on function storefront_photo_allowed(text)     to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
