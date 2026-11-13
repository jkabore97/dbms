-- ============================================================
-- 182 — The Événementiel free, with limits; more with Marakaj Pro.
--
-- The owner: « make everything free but limit usage for pro and keep the
-- premium templates for pro also. Allow me to set number of ticket to be
-- free, the templates that will be free or pro in the admin panel », the
-- ticket count per card, and « they cannot use the option where invites
-- can upload their photos without [Pro]. It cost me space. »
--
--   * Tickets: every Événementiel business sells them once the platform's
--     switch events_tickets is on — a free one, the first
--     events_free_tickets of each card (50 to start; Marakaj's console sets
--     it), counted as the places taken (paid, and holds not yet expired);
--     Marakaj Pro without a limit. Held on every way a ticket is asked —
--     the buyer's request, a sale at the door, a ticket offered — by the
--     ticket lines themselves. The buyer is told the online tickets are
--     gone; the organiser, that Pro sells more. event_tickets_free_left:
--     what the organiser's screen counts.
--   * Designs: event_templates.premium is the console's switch, one design
--     at a time (admin_event_template_premium). A Premium design's animated
--     scene (lx-…) follows its design: free when Marakaj made the design
--     free (event_templates.scene), Pro otherwise (studio_doc_check, as 181
--     otherwise). event_premium_designs: the Premium keys, for Studio.
--   * The guests' album — guests sending photos, and its controls — is
--     Marakaj Pro's, the switch on or not (each photo is kept, at a cost).
--     A free business's open album takes no new photo (the photos it has
--     stay shown); the card's page says it is closed (event_album_rules).
--   * The writing assistant: free, events_assist_free_day a day per card
--     (5); Pro, 40 (event_assist_use says 'ok'). The PDF: free (Studio).
--   * A business one of Marakaj's admins belongs to: as Pro, as before.
--   * admin_events_settings / admin_events_set: the console reads and
--     sets the two numbers, Marakaj's admins only.
--
-- For a shop, a farm and an association: nothing (an Événementiel's cards
-- only). Applies twice.
-- ============================================================

insert into platform_settings (key, value) values ('events_free_tickets', '50'), ('events_assist_free_day', '5')
on conflict (key) do nothing;

alter table event_templates add column if not exists scene text;
update event_templates t set scene = v.scene
  from (values
    ('anime_sahel_p', 'lx-savane'),
    ('anime_lotus_p', 'lx-lotus'),
    ('anime_foret_p', 'lx-foret'),
    ('anime_cerisiers_p', 'lx-cerisiers'),
    ('anime_tournesols_p', 'lx-tournesols'),
    ('anime_lanternes_p', 'lx-lanternes'),
    ('anime_roseraie_p', 'lx-roseraie'),
    ('anime_desert_p', 'lx-dunes'),
    ('anime_ocean_p', 'lx-rivage'),
    ('anime_champagne_p', 'lx-champagne'),
    ('anime_papillons_p', 'lx-herbier'),
    ('anime_hiver_p', 'lx-givre'),
    ('anime_feux_p', 'lx-feux'),
    ('anime_aurore_p', 'lx-aurore')) as v(key, scene)
 where t.key = v.key and t.scene is distinct from v.scene;

-- ------------------------------------------------------------
-- Pro, or a business of Marakaj's admins
-- ------------------------------------------------------------
create or replace function event_org_unlimited(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select org_plan(p_org) = 'pro'
        or exists (select 1 from memberships m join profiles p on p.id = m.user_id
                    where m.org_id = p_org and p.is_platform_admin);
$$;

-- ------------------------------------------------------------
-- Tickets: everyone once the switch is on, so many a card when free
-- ------------------------------------------------------------
create or replace function event_tickets_allowed(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((select value from platform_settings where key = 'events_tickets') = 'true'::jsonb, false)
        or exists (select 1 from memberships m join profiles p on p.id = m.user_id
                    where m.org_id = p_org and p.is_platform_admin);
$$;

-- The free allowance of a card's tickets: null for Pro (no limit).
create or replace function event_tickets_cap(p_event uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case when event_org_unlimited(e.org_id) then null
                else greatest(coalesce((select (value #>> '{}')::integer from platform_settings where key = 'events_free_tickets'), 50), 0) end
      from events e where e.id = p_event;
$$;

-- Places taken on a card: paid, and holds not yet expired (as 161 counts a type's).
create or replace function event_tickets_used(p_event uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(sum(l.qty), 0)::integer
      from event_ticket_lines l join event_ticket_requests r on r.id = l.request_id
     where r.event_id = p_event
       and (r.status = 'paid' or (r.status = 'pending' and r.hold_until > now()));
$$;

create or replace function event_ticket_lines_cap()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    r event_ticket_requests;
    e events;
    v_cap integer;
begin
    select * into r from event_ticket_requests where id = new.request_id;
    select * into e from events where id = r.event_id for update;   -- one card's sales one after the other
    v_cap := event_tickets_cap(e.id);
    -- this request's lines already in are counted (it is paid or held)
    if v_cap is not null and event_tickets_used(e.id) + new.qty > v_cap then
        if is_org_admin(e.org_id) then
            raise exception 'Marakaj Pro : cette carte a vendu ses % billets gratuits. Ouvrez Compte › Marakaj Pro pour en vendre davantage.', v_cap;
        end if;
        raise exception 'Il ne reste plus de billets en ligne pour cet événement. Contactez l''organisateur.';
    end if;
    return new;
end;
$$;
drop trigger if exists event_ticket_lines_cap on event_ticket_lines;
create trigger event_ticket_lines_cap before insert on event_ticket_lines
    for each row execute function event_ticket_lines_cap();

-- What the organiser's screen shows: the card's allowance and its use.
create or replace function event_tickets_free_left(p_event uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    e events;
    v_cap integer;
begin
    select * into e from events where id = p_event;
    if not found or not is_org_admin(e.org_id) then
        raise exception 'Événement introuvable.';
    end if;
    v_cap := event_tickets_cap(e.id);
    return jsonb_build_object('cap', v_cap, 'used', event_tickets_used(e.id), 'pro', v_cap is null);
end;
$$;

-- ------------------------------------------------------------
-- The guests' album: Marakaj Pro's
-- ------------------------------------------------------------
create or replace function event_album_allowed(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select event_org_unlimited(p_org);
$$;

-- A guest's photo into a free business's album: refused, whatever door it came by.
create or replace function event_pictures_album_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.source = 'guest' and not event_album_allowed((select org_id from events where id = new.event_id)) then
        raise exception 'L''album de cette carte est fermé.';
    end if;
    return new;
end;
$$;
drop trigger if exists event_pictures_album_guard on event_pictures;
create trigger event_pictures_album_guard before insert on event_pictures
    for each row execute function event_pictures_album_guard();

create or replace function event_album_rules(p_slug text, p_preview text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    e events;
begin
    select * into e from events where slug = lower(trim(coalesce(p_slug, '')));
    if not found or not event_visible(e, nullif(btrim(coalesce(p_preview, '')), '')) then
        return null;
    end if;
    return jsonb_build_object('on', e.album_on and event_album_allowed(e.org_id), 'limit', e.album_limit, 'review', e.album_review, 'per_pass', 5,
                              'open_quota', case when e.album_limit then null else e.album_open_quota end);
end;
$$;

-- ------------------------------------------------------------
-- Designs: the console's switch; Studio's list
-- ------------------------------------------------------------
create or replace function event_premium_designs()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'designs', coalesce((select jsonb_agg(key order by key) from event_templates where premium), '[]'::jsonb),
        'scenes', coalesce((select jsonb_agg(scene order by scene) from event_templates where premium and scene is not null), '[]'::jsonb));
$$;

create or replace function studio_doc_check(p_event uuid, p_doc jsonb)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    k text;
    v jsonb;
    b jsonb;
    t jsonb;
    r text;
    n int := 0;
    ids text[] := '{}';
    v_org uuid := (select org_id from events where id = p_event);
    v_old jsonb := (select doc from events where id = p_event);
    types constant text[] := array['cover', 'text', 'photo', 'gallery', 'families', 'programme', 'infos',
        'countdown', 'place', 'calendar', 'contribution', 'quote', 'rsvp', 'tickets', 'album', 'pass',
        'video', 'music', 'divider', 'footer', 'free', 'spacer', 'button', 'faq', 'menu', 'story', 'dresscode'];
begin
    if p_doc is null or jsonb_typeof(p_doc) <> 'object' then
        raise exception 'La carte est mal formée.';
    end if;
    if octet_length(p_doc::text) > 200000 then
        raise exception 'La carte est trop lourde : moins de texte ou moins de blocs, s''il vous plaît.';
    end if;
    for k in select jsonb_object_keys(p_doc) loop
        if k not in ('v', 'theme', 'blocks', 'meta') then
            raise exception 'Champ inconnu : %', left(k, 40);
        end if;
    end loop;
    if p_doc -> 'v' is distinct from '2'::jsonb then
        raise exception 'Version de carte inconnue.';
    end if;

    -- the theme
    t := coalesce(p_doc -> 'theme', '{}'::jsonb);
    if jsonb_typeof(t) <> 'object' then
        raise exception 'Le thème est mal formé.';
    end if;
    for k, v in select * from jsonb_each(t) loop
        if k = 'colors' then
            if jsonb_typeof(v) <> 'object' or (select count(*) from jsonb_object_keys(v)) > 12 then
                raise exception 'Les couleurs sont mal formées.';
            end if;
            if exists (select 1 from jsonb_each(v) c
                        where c.key !~ '^[a-zA-Z]{1,16}$' or jsonb_typeof(c.value) <> 'string'
                           or (c.value #>> '{}') !~ '^#[0-9a-fA-F]{6}$') then
                raise exception 'Une couleur s''écrit #rrggbb.';
            end if;
        elsif k = 'fonts' then
            if jsonb_typeof(v) <> 'object' or exists (select 1 from jsonb_each(v) f
                        where f.key not in ('display', 'body', 'script') or jsonb_typeof(f.value) <> 'string'
                           or (f.value #>> '{}') !~ '^[a-z0-9_-]{1,32}$') then
                raise exception 'Les polices sont mal formées.';
            end if;
        elsif k in ('motion', 'corners', 'scene', 'preset', 'decor', 'fall') then
            if v <> 'null'::jsonb and (jsonb_typeof(v) <> 'string' or (v #>> '{}') !~ '^[a-z0-9_-]{0,40}$') then
                raise exception 'Thème mal formé (%).', k;
            end if;
        elsif k = 'motif' then
            if v <> 'null'::jsonb and (jsonb_typeof(v) <> 'object' or studio_value_problem(v, 2) is not null
                    or coalesce(v ->> 'id', '') !~ '^[a-z0-9_-]{0,40}$') then
                raise exception 'Le motif est mal formé.';
            end if;
        else
            raise exception 'Thème : champ inconnu (%).', left(k, 40);
        end if;
    end loop;

    -- the blocks
    if p_doc -> 'blocks' is null or jsonb_typeof(p_doc -> 'blocks') <> 'array' then
        raise exception 'La carte n''a pas de blocs.';
    end if;
    if jsonb_array_length(p_doc -> 'blocks') > 40 then
        raise exception 'Quarante blocs au plus par carte.';
    end if;
    for b in select * from jsonb_array_elements(p_doc -> 'blocks') loop
        n := n + 1;
        if jsonb_typeof(b) <> 'object' then
            raise exception 'Le bloc % est mal formé.', n;
        end if;
        for k in select jsonb_object_keys(b) loop
            if k not in ('id', 'type', 'variant', 'hidden', 'props', 'style') then
                raise exception 'Bloc % : champ inconnu (%).', n, left(k, 40);
            end if;
        end loop;
        if coalesce(b ->> 'id', '') !~ '^[a-z0-9]{1,16}$' then
            raise exception 'Bloc % : identifiant mal formé.', n;
        end if;
        if (b ->> 'id') = any (ids) then
            raise exception 'Deux blocs portent le même identifiant (%).', b ->> 'id';
        end if;
        ids := ids || (b ->> 'id');
        if jsonb_typeof(b -> 'type') is distinct from 'string' or not ((b ->> 'type') = any (types)) then
            raise exception 'Bloc % : type inconnu (%).', n, left(coalesce(b ->> 'type', ''), 40);
        end if;
        if b ? 'variant' and b -> 'variant' <> 'null'::jsonb
           and (jsonb_typeof(b -> 'variant') <> 'string' or (b ->> 'variant') !~ '^[a-z0-9-]{0,24}$') then
            raise exception 'Bloc % : variante mal formée.', n;
        end if;
        if b ? 'hidden' and jsonb_typeof(b -> 'hidden') not in ('boolean', 'null') then
            raise exception 'Bloc % : « masqué » mal formé.', n;
        end if;
        foreach k in array array['props', 'style'] loop
            if b ? k and b -> k <> 'null'::jsonb then
                if jsonb_typeof(b -> k) <> 'object' then
                    raise exception 'Bloc % : % mal formé.', n, k;
                end if;
                r := studio_value_problem(b -> k, 1);
                if r is not null then
                    raise exception 'Bloc % : %.', n, r;
                end if;
            end if;
        end loop;
    end loop;
    if p_doc ? 'meta' and p_doc -> 'meta' <> 'null'::jsonb then
        if jsonb_typeof(p_doc -> 'meta') <> 'object' then
            raise exception 'Les informations de la carte sont mal formées.';
        end if;
        r := studio_value_problem(p_doc -> 'meta', 2);
        if r is not null then
            raise exception 'Informations de la carte : %.', r;
        end if;
    end if;

    -- the pictures: stored (154), the card's own or one of the same
    -- business's other cards (173: « Mes photos »); 150 at most
    if (select count(distinct x #>> '{}') from jsonb_path_query(p_doc, 'lax $.**.key') x) > 150 then
        raise exception 'Cent cinquante photos au plus par carte.';
    end if;
    if exists (select 1 from jsonb_path_query(p_doc, 'lax $.**.key') x
                where jsonb_typeof(x) <> 'string'
                   or not exists (select 1 from event_pictures p join events pe on pe.id = p.event_id
                                   where p.key = x #>> '{}' and p.state = 'stored' and pe.org_id = v_org)) then
        raise exception 'Cette image n''est pas celle de la carte.';
    end if;
    -- a Premium animated scene (lx-…, drawn on the graphics card): Marakaj
    -- Pro (173), unless the card already had it when the plan lapsed —
    -- its saved card keeps what it was given, nothing new is added.
    if org_plan(v_org) <> 'pro' and not exists (select 1 from memberships m join profiles pr on pr.id = m.user_id
                                                 where m.org_id = v_org and pr.is_platform_admin) and exists (
            select 1 from jsonb_path_query(p_doc, 'lax $.**.scene') s
             where jsonb_typeof(s) = 'string' and (s #>> '{}') like 'lx-%'
               -- free when Marakaj's admins made its design free (182)
               and not exists (select 1 from event_templates t where t.scene = (s #>> '{}') and not t.premium)
               and not exists (select 1 from jsonb_path_query(coalesce(v_old, '{}'::jsonb), 'lax $.**.scene') o
                                where (o #>> '{}') = (s #>> '{}'))) then
        raise exception 'Ce décor animé est Premium : passez à Marakaj Pro pour l''utiliser.';
    end if;
    -- the links: https, tel, mailto (or nothing), 600 characters at most
    if exists (select 1 from (select x from jsonb_path_query(p_doc, 'lax $.**.href') x
                               union all select x from jsonb_path_query(p_doc, 'lax $.**.url') x) l
                where jsonb_typeof(l.x) <> 'string'
                   or ((l.x #>> '{}') <> '' and (length(l.x #>> '{}') > 600 or (l.x #>> '{}') !~ '^(https://|tel:|mailto:)[^\s<>"''`]+$'))) then
        raise exception 'Un lien doit commencer par https://, tel: ou mailto:.';
    end if;
    -- a stock picture: a name of the card bank
    if exists (select 1 from jsonb_path_query(p_doc, 'lax $.**.stock') x
                where jsonb_typeof(x) <> 'string' or (x #>> '{}') !~ '^[a-z0-9-]{1,40}$') then
        raise exception 'Photo de la banque inconnue.';
    end if;
    -- the colours inside blocks: #rrggbb or a theme role
    if exists (select 1 from jsonb_path_query(p_doc, 'lax $.blocks[*].** ? (@.type() == "object")') o,
                             jsonb_each(o) c
                where c.key in ('color', 'bg', 'fg', 'ink', 'tint')
                  and (jsonb_typeof(c.value) <> 'string' or (c.value #>> '{}') !~ '^(#[0-9a-fA-F]{6}|[a-z]{1,16})?$')) then
        raise exception 'Une couleur s''écrit #rrggbb.';
    end if;
end;
$$;

-- ------------------------------------------------------------
-- The writing assistant: free so many a day, Pro forty
-- ------------------------------------------------------------
create or replace function event_assist_use(p_slug text, p_edit text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    e events;
    v_uses integer;
    v_pro boolean;
    v_max integer;
begin
    e := event_for_edit(p_slug, p_edit);
    v_pro := event_org_unlimited(e.org_id);
    v_max := case when v_pro then 40
                  else greatest(coalesce((select (value #>> '{}')::integer from platform_settings where key = 'events_assist_free_day'), 5), 0) end;
    if v_max = 0 then
        return jsonb_build_object('pro', v_pro, 'ok', false, 'left', 0);
    end if;
    insert into event_assist_uses as u (event_id, day, uses) values (e.id, current_date, 1)
    on conflict (event_id, day) do update set uses = u.uses + 1
    returning uses into v_uses;
    if v_uses > v_max then
        raise exception '%', case when v_pro then 'L''assistant a assez écrit pour aujourd''hui : il revient demain.'
                                  else 'L''assistant a écrit ses ' || v_max || ' textes gratuits du jour : il revient demain, ou sans limite avec Marakaj Pro.' end;
    end if;
    return jsonb_build_object('pro', v_pro, 'ok', true, 'left', v_max - v_uses);
end;
$$;

-- What the Free / Pro page says to an Événementiel (its two numbers; no secret).
create or replace function events_plan_numbers()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'free_tickets', coalesce((select (value #>> '{}')::integer from platform_settings where key = 'events_free_tickets'), 50),
        'assist_free_day', coalesce((select (value #>> '{}')::integer from platform_settings where key = 'events_assist_free_day'), 5));
$$;

-- ------------------------------------------------------------
-- The console: Marakaj's admins only
-- ------------------------------------------------------------
create or replace function admin_events_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Réservé aux administrateurs de Marakaj.';
    end if;
    return jsonb_build_object(
        'free_tickets', coalesce((select (value #>> '{}')::integer from platform_settings where key = 'events_free_tickets'), 50),
        'assist_free_day', coalesce((select (value #>> '{}')::integer from platform_settings where key = 'events_assist_free_day'), 5),
        'tickets_on', coalesce((select value from platform_settings where key = 'events_tickets') = 'true'::jsonb, false),
        'templates', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'name', name, 'family', family, 'premium', premium) order by family, sort, key)
                                 from event_templates), '[]'::jsonb));
end;
$$;

create or replace function admin_events_set(p_free_tickets integer, p_assist_free_day integer)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Réservé aux administrateurs de Marakaj.';
    end if;
    if p_free_tickets is null or p_free_tickets < 0 or p_free_tickets > 100000 then
        raise exception 'Billets gratuits par carte : de 0 à 100 000.';
    end if;
    if p_assist_free_day is null or p_assist_free_day < 0 or p_assist_free_day > 40 then
        raise exception 'Textes gratuits par jour : de 0 à 40.';
    end if;
    insert into platform_settings (key, value) values ('events_free_tickets', to_jsonb(p_free_tickets)), ('events_assist_free_day', to_jsonb(p_assist_free_day))
    on conflict (key) do update set value = excluded.value;
    return admin_events_settings();
end;
$$;

create or replace function admin_event_template_premium(p_key text, p_premium boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Réservé aux administrateurs de Marakaj.';
    end if;
    update event_templates set premium = coalesce(p_premium, false) where key = p_key;
    if not found then
        raise exception 'Modèle inconnu.';
    end if;
    return admin_events_settings();
end;
$$;

-- ------------------------------------------------------------
-- The doors (063)
-- ------------------------------------------------------------
revoke execute on function event_org_unlimited(uuid) from public;
revoke execute on function event_tickets_allowed(uuid) from public;
revoke execute on function event_tickets_cap(uuid) from public;
revoke execute on function event_tickets_used(uuid) from public;
revoke execute on function event_ticket_lines_cap() from public;
revoke execute on function event_tickets_free_left(uuid) from public;
revoke execute on function event_album_allowed(uuid) from public;
revoke execute on function event_pictures_album_guard() from public;
revoke execute on function event_album_rules(text, text) from public;
revoke execute on function event_premium_designs() from public;
revoke execute on function event_assist_use(text, text) from public;
revoke execute on function admin_events_settings() from public;
revoke execute on function events_plan_numbers() from public;
revoke execute on function admin_events_set(integer, integer) from public;
revoke execute on function admin_event_template_premium(text, boolean) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function event_org_unlimited(uuid) from anon;
        revoke execute on function event_tickets_cap(uuid) from anon;
        revoke execute on function event_tickets_used(uuid) from anon;
        revoke execute on function event_tickets_free_left(uuid) from anon;
        revoke execute on function admin_events_settings() from anon;
        revoke execute on function admin_events_set(integer, integer) from anon;
        revoke execute on function admin_event_template_premium(text, boolean) from anon;
        grant execute on function event_album_rules(text, text) to anon;
        grant execute on function event_premium_designs() to anon;
        grant execute on function event_assist_use(text, text) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function event_tickets_free_left(uuid) to authenticated;
        grant execute on function event_album_rules(text, text) to authenticated;
        grant execute on function event_premium_designs() to authenticated;
        grant execute on function event_assist_use(text, text) to authenticated;
        grant execute on function admin_events_settings() to authenticated;
        grant execute on function events_plan_numbers() to authenticated;
        grant execute on function admin_events_set(integer, integer) to authenticated;
        grant execute on function admin_event_template_premium(text, boolean) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
