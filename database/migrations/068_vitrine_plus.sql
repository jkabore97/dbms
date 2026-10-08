-- ============================================================
-- 068_vitrine_plus.sql — a Kaj Pro business dresses its window.
--
-- The vitrine (052) is one design for every shop on purpose: a name, a few
-- words, the goods on their squares. That is what keeps the street legible.
-- What a paying business gets on top is the shopkeeper's touch, within
-- that design: a cover photograph over the band, a tagline under the
-- name, opening hours, the colour of its buttons, up to six articles held
-- at the top of the shelf, and the choice to hide what is out of stock.
--
-- The rules:
--   * One column, orgs.storefront_style, a small JSON with known keys and
--     nothing else. set_storefront_style() validates every key and drops
--     the ones it does not know, so a build ahead of the database cannot
--     write something the street would then render.
--   * Behind the plan (066): the tool is 'vitrine_plus' on the Pro list.
--     A Free business is refused with the "Kaj Pro :" sentence that opens
--     the door to pay. The platform admin is never gated.
--   * The street sees the style only while the business is Pro. A lapsed
--     Pro keeps what it wrote — nothing is deleted — and the window goes
--     back to the common design until it pays again. Lapsing is not a
--     cliff; it is also not free.
--   * The cover is one of the business's own photographs (a documents row
--     of that org). The uploads Worker asks storefront_photo_allowed()
--     before serving a photo to the street; that gate learns the cover.
--   * Pinned articles must be the business's own; the app orders the shelf
--     by them. Nothing here changes what storefront_products() returns.
-- ============================================================

alter table orgs add column if not exists storefront_style jsonb not null default '{}'::jsonb;

comment on column orgs.storefront_style is
    'The Pro dressing of the vitrine (068): tagline, hours, accent, '
    'cover_key, pinned, hide_out_of_stock. Written only by '
    'set_storefront_style(); shown by storefront() only while the business '
    'is Pro.';

-- The tool joins the Pro list on every database, including ones where 066
-- already seeded the list without it.
update platform_settings
   set value = value || '["vitrine_plus"]'::jsonb
 where key = 'pro_features'
   and jsonb_typeof(value) = 'array'
   and not value ? 'vitrine_plus';

-- The shopkeeper's touch, validated key by key. Null clears everything.
create or replace function set_storefront_style(p_org_id uuid, p_style jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_in       jsonb := coalesce(p_style, '{}'::jsonb);
    v_out      jsonb := '{}'::jsonb;
    v_text     text;
    v_pinned   jsonb;
    v_id       text;
    v_count    int;
begin
    if auth.uid() is null then
        raise exception 'set_storefront_style() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur peut habiller la vitrine';
    end if;
    if feature_access(p_org_id, 'vitrine_plus') <> 'edit' then
        if pro_locked(p_org_id, 'vitrine_plus') then
            raise exception 'Kaj Pro : la vitrine personnalisée fait partie de Kaj Pro. Ouvrez Compte › Kaj Pro pour passer à la formule payante.';
        end if;
        raise exception 'La vitrine personnalisée vous est fermée. Voyez le propriétaire.';
    end if;
    if jsonb_typeof(v_in) <> 'object' then
        raise exception 'Le style de la vitrine doit être un objet';
    end if;

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

    v_text := nullif(btrim(coalesce(v_in ->> 'accent', '')), '');
    if v_text is not null then
        if v_text !~ '^#[0-9A-Fa-f]{6}$' then
            raise exception 'La couleur doit s''écrire #RRGGBB';
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

    update orgs set storefront_style = v_out where id = p_org_id;
end;
$$;

-- The window carries the style — while the business is Pro. 057 verbatim
-- plus the column; the return type changes, so dropped and recreated.
drop function if exists storefront(text);
create function storefront(p_slug text)
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
           o.wave_merchant,
           case when org_plan(o.id) = 'pro' then o.storefront_style
                else '{}'::jsonb end
    from orgs o
    where o.id = storefront_open(p_slug);
$$;

-- The photos the Worker may serve to the street: the published articles'
-- (052) and now a Pro business's cover, while it is Pro and open.
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
          and org_plan(o.id) = 'pro'
    );
$$;

revoke execute on function set_storefront_style(uuid, jsonb) from public;
revoke execute on function storefront(text)                  from public;
revoke execute on function storefront_photo_allowed(text)    from public;

do $$
begin
    -- The window is for the street: anonymous callers may look (063 rule:
    -- a recreated street function says its grant again, by name).
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function storefront(text)               to anon;
        grant execute on function storefront_photo_allowed(text) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_storefront_style(uuid, jsonb) to authenticated;
        grant execute on function storefront(text)                  to authenticated;
        grant execute on function storefront_photo_allowed(text)    to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
