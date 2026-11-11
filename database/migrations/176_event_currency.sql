-- ============================================================
-- 176 — The ticket screens speak the business's own money.
--
-- The owner, on « Bilan » showing 30 000,00 USD: « Looks like you didn't
-- fix the currency mismatch issue ». The organiser's ticket screens wrote
-- every price in FCFA (« Prix (FCFA) », the types' list, the requests'
-- totals, the door's sale, the journal, the holders), while the buyer's
-- page, the requests themselves and « Bilan » use the business's currency
-- (orgs.default_currency) — USD for a business whose owner's phone is
-- American: a price typed as 10 000 FCFA was sold as 10 000 USD.
--
-- event_currency(p_event): the event's business's currency, for anyone who
-- may read its sale — its admins and its team (event_ticket_can 'read',
-- 163); nobody else learns anything (null). The app formats every ticket
-- screen with it.
--
-- For a shop, a farm and an association: nothing (an Événementiel's
-- tickets only). Applies twice.
-- ============================================================

create or replace function event_currency(p_event uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    e events;
begin
    select * into e from events where id = p_event;
    if not found or not event_ticket_can(e, 'read') then
        return null;
    end if;
    return (select coalesce(default_currency, 'XOF') from orgs where id = e.org_id);
end;
$$;

revoke execute on function event_currency(uuid) from public;
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function event_currency(uuid) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function event_currency(uuid) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
