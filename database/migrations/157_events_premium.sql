-- ============================================================
-- 157 — A Premium design is Marakaj Pro's.
--
-- 153 marked fourteen animated designs Premium (event_templates.premium)
-- and the gallery showed the chip; nothing held the door: any business
-- could make its card with one, or switch a card to one (a direct update
-- of events.card). The server holds it now: a card's design, at creation
-- or at a change of design, may be Premium only for a business whose
-- plan is Pro (org_plan, 065: pro and not past plan_until). Refused the
-- way every Pro door is refused — « Marakaj Pro : … » — so the app opens
-- the Pro sheet. A card already made keeps its design: only a change of
-- design is asked again. For a shop, a farm or an association: nothing —
-- the cards are an Événementiel's. Applies twice.
-- ============================================================

do $$ begin
    if to_regclass('event_templates') is null or to_regprocedure('org_plan(uuid)') is null then
        raise exception '157 needs 153 (event_templates) and 065 (org_plan) applied first';
    end if;
end $$;

-- DEFINER on purpose: the guard reads the templates' table and the
-- business's plan whoever writes the card; it writes nothing.
create or replace function events_premium_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_premium boolean;
begin
    select t.premium into v_premium from event_templates t where t.key = new.card;
    if coalesce(v_premium, false) and org_plan(new.org_id) <> 'pro' then
        raise exception 'Marakaj Pro : ce modèle Premium fait partie de Marakaj Pro. Ouvrez Compte › Marakaj Pro, ou choisissez un autre modèle.';
    end if;
    return new;
end;
$$;

revoke execute on function events_premium_guard() from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function events_premium_guard() from anon;
    end if;
end $$;

drop trigger if exists events_premium_guard on events;
create trigger events_premium_guard before insert or update of card on events
    for each row execute function events_premium_guard();

notify pgrst, 'reload schema';
