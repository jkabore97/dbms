-- ============================================================
-- 179 — An album open to everyone, so many photos per phone.
--
-- The owner, on « Phanuel & Espérance » (the guest was told « L'album est
-- réservé aux invités … »): « only for this one, allow everyone to add
-- photos please. Only 2 photos per person ».
--
-- events.album_open_quota: null — as before (164: everyone, or, with
-- album_limit, those who answered or hold a ticket, five each); a number
-- from 1 to 20 — anyone with the card's link adds photos, that many per
-- phone. A phone is the card page's own random identifier (kept in the
-- browser, sent with each photo, kept on the picture as `device`): a
-- soft limit, which is what a party album needs — someone who clears
-- their browser can add more. album_limit is the stricter rule and wins
-- when both are set. The album's 300 and the day's 200 stay.
--
-- event_album_add takes p_device; event_album_rules says 'open_quota'.
-- Migration number 178 is unused (the phone batch needed none).
--
-- For a shop, a farm and an association: nothing (an Événementiel's
-- cards only). Applies twice.
-- ============================================================

alter table events add column if not exists album_open_quota smallint;
alter table events drop constraint if exists events_album_open_quota_check;
alter table events add constraint events_album_open_quota_check
    check (album_open_quota is null or album_open_quota between 1 and 20);

alter table event_pictures add column if not exists device text;
alter table event_pictures drop constraint if exists event_pictures_device_check;
alter table event_pictures add constraint event_pictures_device_check
    check (device is null or device ~ '^[a-zA-Z0-9-]{16,64}$');
create index if not exists event_pictures_device_idx on event_pictures (event_id, device) where device is not null;

drop function if exists event_album_add(text, text, text, text, uuid);
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
    return jsonb_build_object('on', e.album_on, 'limit', e.album_limit, 'review', e.album_review, 'per_pass', 5,
                              'open_quota', case when e.album_limit then null else e.album_open_quota end);
end;
$$;

revoke execute on function event_album_add(text, text, text, text, uuid, text) from public;
revoke execute on function event_album_rules(text, text) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function event_album_add(text, text, text, text, uuid, text) to anon;
        grant execute on function event_album_rules(text, text) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function event_album_add(text, text, text, text, uuid, text) to authenticated;
        grant execute on function event_album_rules(text, text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
