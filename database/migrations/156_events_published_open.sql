-- ============================================================
-- 156 — A published card opens for its guests, whatever the switch.
--
-- 152 showed a published card to the street only once the platform's
-- switch events_public was on — the switch that opens the module to
-- every business. The owner, with a card published and its short link in
-- hand while the switch was off: « Cette carte n'est pas ouverte ».
-- Publishing is the organiser's deliberate act, for guests who are never
-- members: a published card opens for anyone with its link, switch or
-- not. The switch keeps its other meaning — who may make an
-- Événementiel (create_my_business, 153) and whether members see the
-- module (events_open, 152). The preview and edit tokens open a card as
-- before; an unpublished card stays closed to the street.
-- Applies twice.
-- ============================================================

do $$ begin
    if to_regprocedure('event_visible(events, text, text)') is null then
        raise exception '156 needs 154 (event_visible with the edit token) applied first';
    end if;
end $$;

create or replace function event_visible(p_event events, p_preview text, p_edit text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select (p_edit is not null and p_edit = p_event.edit_token)
        or (p_preview is not null and p_preview = p_event.preview_token)
        or p_event.published
        or (auth.uid() is not null and is_org_admin(p_event.org_id));
$$;

-- The grants of 154 stand: never callable by the street itself — the
-- doors (event_public, event_rsvp, the album's) call it.
revoke execute on function event_visible(events, text, text) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function event_visible(events, text, text) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function event_visible(events, text, text) from authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
