-- ============================================================
-- 181 — An album's counts hold when photos are sent together.
--
-- The owner, on « Phanuel & Espérance » (two photos per phone, 179): « I
-- was able to add 3 pictures while the limit should be 2 ». The three
-- were chosen at once; the card page sent them together and each request
-- counted the phone's photos at the same instant — none yet — so all
-- three passed. The same held for 164's five per pass and the album's 300.
--
-- event_album_add takes the card's row first (for update): a card's photos
-- are counted one request after the other, each seeing those before it.
-- The page now also sends them one after the other (its words then say
-- which were refused). Otherwise as 179.
--
-- For a shop, a farm and an association: nothing. Applies twice.
-- ============================================================

create or replace function event_album_add(p_slug text, p_preview text, p_ext text, p_guest text default null,
                                           p_pass uuid default null, p_device text default null)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    e events;
    v_ext text := lower(btrim(coalesce(p_ext, '')));
    v_guest text := nullif(left(btrim(coalesce(p_guest, '')), 60), '');
    v_device text := nullif(btrim(coalesce(p_device, '')), '');
    v_key text;
    v_quota integer;
begin
    e := event_for_album(p_slug, p_preview);
    -- one photo of this card at a time (181): photos sent together each
    -- counted the others before them — three got past « two per phone »
    perform 1 from events where id = e.id for update;
    if v_ext not in ('jpg', 'png', 'webp') then
        raise exception 'Photos uniquement (JPEG, PNG ou WebP).';
    end if;
    if v_device is not null and v_device !~ '^[a-zA-Z0-9-]{16,64}$' then
        v_device := null;
    end if;
    if e.album_limit then
        if p_pass is null then
            raise exception 'L''album est réservé aux invités : répondez d''abord à l''invitation, ou réservez votre billet, sur ce téléphone.';
        end if;
        v_quota := event_album_pass_quota(e.id, p_pass);
        if v_quota is null then
            raise exception 'L''album est réservé aux invités : cette carte d''invité ou ce billet n''est pas de cet événement.';
        end if;
        if (select count(*) from event_pictures where event_id = e.id and pass_id = p_pass and source = 'guest') >= v_quota then
            raise exception 'Vous avez déposé vos % photos : c''est le maximum par invité.', v_quota;
        end if;
    elsif e.album_open_quota is not null then
        if v_device is null then
            raise exception 'Rechargez la carte pour ajouter vos photos.';
        end if;
        if (select count(*) from event_pictures where event_id = e.id and device = v_device and source = 'guest') >= e.album_open_quota then
            raise exception 'Vous avez déposé vos % photo(s) : c''est le maximum par personne.', e.album_open_quota;
        end if;
    end if;
    if (select count(*) from event_pictures where event_id = e.id and source = 'guest') >= 300 then
        raise exception 'L''album est plein : 300 photos au plus.';
    end if;
    if (select count(*) from event_pictures
         where event_id = e.id and source = 'guest' and created_at > now() - interval '1 day') >= 200 then
        raise exception 'Trop de photos envoyées aujourd''hui. Réessayez demain.';
    end if;
    v_key := 'events/' || e.id || '/' || replace(gen_random_uuid()::text, '-', '') || '.' || v_ext;
    insert into event_pictures (key, event_id, state, source, guest, pass_id, approved, device)
    values (v_key, e.id, 'slot', 'guest', v_guest, p_pass, not e.album_review, v_device);
    return v_key;
end;
$$;

revoke execute on function event_album_add(text, text, text, text, uuid, text) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function event_album_add(text, text, text, text, uuid, text) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function event_album_add(text, text, text, text, uuid, text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
