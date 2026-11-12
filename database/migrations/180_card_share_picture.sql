-- ============================================================
-- 180 — A shared card's link shows the card.
--
-- The owner, on a WhatsApp message carrying a card's link (a title, a
-- line, no picture): « Can you make a nice preview for the link? ». The
-- link's picture (173) was the card's first photo: a card made in Studio
-- with a living picture and no photo showed none.
--
-- events.card_og: the key of the card's wide picture (1200 × 630) — its own
-- picture (177) in the middle, over a blurred, darkened copy of it — drawn
-- by Studio with the card's picture, each one replacing the last (its
-- bytes deleted by the uploads Worker). WhatsApp, Facebook and the others
-- show a wide picture large; a tall one, small.
--
-- event_share_image(slug, preview): for the site's page, the picture its
-- link shows — the wide one, else the card's own picture (177), else none
-- (the page then keeps 173's photo) — only for a card that page may show.
-- event_og_of(slug, edit): Studio asks whether the card has one.
--
-- For a shop, a farm and an association: nothing (an Événementiel's
-- cards only). Applies twice.
-- ============================================================

alter table events add column if not exists card_og text;

create or replace function event_og_slot(p_slug text, p_edit text, p_ext text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    e events;
    v_ext text := lower(btrim(coalesce(p_ext, '')));
    v_key text;
begin
    e := event_for_edit(p_slug, p_edit);
    if v_ext not in ('jpg', 'png', 'webp') then
        raise exception 'Photos uniquement (JPEG, PNG ou WebP).';
    end if;
    if (select count(*) from event_pictures
         where event_id = e.id and source = 'preview' and created_at > now() - interval '1 day') >= 120 then
        raise exception 'Trop d''aperçus aujourd''hui. Réessayez demain.';
    end if;
    v_key := 'events/' || e.id || '/' || replace(gen_random_uuid()::text, '-', '') || '.' || v_ext;
    insert into event_pictures (key, event_id, state, source) values (v_key, e.id, 'slot', 'preview');
    return v_key;
end;
$$;

create or replace function event_og_done(p_key text, p_edit text, p_bytes integer default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    p event_pictures;
    e events;
    v_old text;
begin
    select * into p from event_pictures
     where key = p_key and state = 'slot' and source = 'preview' and created_at > now() - interval '1 hour'
     for update;
    if not found then
        raise exception 'Envoi inconnu.';
    end if;
    select * into e from events where id = p.event_id for update;
    if p_edit is null or p_edit <> e.edit_token then
        raise exception 'Cette carte ne peut pas être modifiée d''ici.';
    end if;
    update event_pictures set state = 'stored', bytes = p_bytes, done_at = clock_timestamp() where key = p_key;
    v_old := e.card_og;
    update events set card_og = p_key where id = e.id;
    if v_old is not null and v_old <> p_key and v_old is distinct from e.card_preview then
        delete from event_pictures where key = v_old and event_id = e.id and source = 'preview';
    end if;
    return case when v_old is distinct from p_key and v_old is distinct from e.card_preview then v_old end;
end;
$$;

create or replace function event_og_of(p_slug text, p_edit text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    e events;
begin
    e := event_for_edit(p_slug, p_edit);
    return e.card_og;
end;
$$;

create or replace function event_share_image(p_slug text, p_preview text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    e events;
begin
    select * into e from events where slug = lower(btrim(coalesce(p_slug, '')));
    if not found or not event_visible(e, nullif(btrim(coalesce(p_preview, '')), '')) then
        return null;
    end if;
    if e.card_og is not null and exists (select 1 from event_pictures p
                                          where p.key = e.card_og and p.event_id = e.id and p.state = 'stored') then
        return jsonb_build_object('key', e.card_og, 'wide', true);
    end if;
    if e.card_preview is not null and exists (select 1 from event_pictures p
                                               where p.key = e.card_preview and p.event_id = e.id and p.state = 'stored') then
        return jsonb_build_object('key', e.card_preview, 'wide', false);
    end if;
    return null;
end;
$$;

revoke execute on function event_og_slot(text, text, text) from public;
revoke execute on function event_og_done(text, text, integer) from public;
revoke execute on function event_og_of(text, text) from public;
revoke execute on function event_share_image(text, text) from public;
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function event_og_slot(text, text, text) to anon;
        grant execute on function event_og_done(text, text, integer) to anon;
        grant execute on function event_og_of(text, text) to anon;
        grant execute on function event_share_image(text, text) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function event_og_slot(text, text, text) to authenticated;
        grant execute on function event_og_done(text, text, integer) to authenticated;
        grant execute on function event_og_of(text, text) to authenticated;
        grant execute on function event_share_image(text, text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
