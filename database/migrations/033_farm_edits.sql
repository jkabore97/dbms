-- ============================================================
-- 033_farm_edits.sql — correcting a farm entry after it is recorded.
--
-- The farm records events the way a notebook does: a line per mortality, per
-- weighing, per harvest. A notebook lets you cross a wrong number out and write
-- the right one, and until now the app did not — a mistyped "70 dead" instead
-- of "7" could only be lived with. These three functions let an entry be
-- corrected in place.
--
-- Why a plain UPDATE and not a reversal, when sales and stock use reversals:
-- those post to the double-entry ledger, where a figure, once booked, has to
-- be unbooked by an equal and opposite figure so the books always balance. A
-- flock event, a herd event and a harvest post NO ledger entry (bringing a
-- crop in is not earning money — see record_harvest). There is nothing to keep
-- balanced, so the honest correction is to fix the number, exactly as the
-- notebook does. Selling still goes through the ledger and still corrects by
-- reversal; this is only for the physical counts.
--
-- All three are SECURITY DEFINER with a can_write_org() guard, the same shape
-- as the record_* functions they mirror: the event tables have no UPDATE
-- policy (writing was always through a function), so the guard here IS the
-- authorization. An observer cannot correct what an observer cannot record.
-- ============================================================

-- ------------------------------------------------------------
-- Flock events (009): org is reached through the flock, which carries it.
-- ------------------------------------------------------------
create or replace function update_flock_event(
    p_event_id    uuid,
    p_quantity    numeric     default null,
    p_kind        text        default null,
    p_note        text        default null,
    p_occurred_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org uuid;
begin
    if auth.uid() is null then
        raise exception 'update_flock_event() needs a signed-in caller';
    end if;

    select f.org_id into v_org
      from flock_events e
      join flocks f on f.id = e.flock_id
     where e.id = p_event_id;

    if v_org is null then
        raise exception 'No such flock event';
    end if;
    if not can_write_org(v_org) then
        raise exception 'You cannot correct entries for this business';
    end if;
    if p_quantity is not null and p_quantity < 0 then
        raise exception 'A count cannot be negative (got %)', p_quantity;
    end if;

    update flock_events set
        quantity    = coalesce(p_quantity, quantity),
        kind        = coalesce(nullif(btrim(coalesce(p_kind, '')), ''), kind),
        note        = coalesce(p_note, note),
        occurred_at = coalesce(p_occurred_at, occurred_at)
    where id = p_event_id;

    return p_event_id;
end;
$$;

-- ------------------------------------------------------------
-- Herd events (019): org_id is on the row.
-- ------------------------------------------------------------
create or replace function update_herd_event(
    p_event_id    uuid,
    p_quantity    numeric default null,
    p_kind        text    default null,
    p_note        text    default null,
    p_occurred_on date    default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org uuid;
begin
    if auth.uid() is null then
        raise exception 'update_herd_event() needs a signed-in caller';
    end if;

    select org_id into v_org from herd_events where id = p_event_id;

    if v_org is null then
        raise exception 'No such herd event';
    end if;
    if not can_write_org(v_org) then
        raise exception 'You cannot correct entries for this business';
    end if;
    if p_quantity is not null and p_quantity < 0 then
        raise exception 'A count cannot be negative (got %)', p_quantity;
    end if;

    update herd_events set
        quantity    = coalesce(p_quantity, quantity),
        kind        = coalesce(nullif(btrim(coalesce(p_kind, '')), ''), kind),
        note        = coalesce(p_note, note),
        occurred_on = coalesce(p_occurred_on, occurred_on)
    where id = p_event_id;

    return p_event_id;
end;
$$;

-- ------------------------------------------------------------
-- Harvests (019): org_id is on the row. Quantity must stay positive — a
-- harvest of nothing is not a harvest, it is a deletion, which is a different
-- act the app does not offer here.
-- ------------------------------------------------------------
create or replace function update_harvest(
    p_harvest_id   uuid,
    p_quantity     numeric default null,
    p_grade        text    default null,
    p_note         text    default null,
    p_harvested_on date    default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org uuid;
begin
    if auth.uid() is null then
        raise exception 'update_harvest() needs a signed-in caller';
    end if;

    select org_id into v_org from harvests where id = p_harvest_id;

    if v_org is null then
        raise exception 'No such harvest';
    end if;
    if not can_write_org(v_org) then
        raise exception 'You cannot correct entries for this business';
    end if;
    if p_quantity is not null and p_quantity <= 0 then
        raise exception 'How much was harvested? (got %)', p_quantity;
    end if;

    update harvests set
        quantity     = coalesce(p_quantity, quantity),
        grade        = coalesce(nullif(btrim(coalesce(p_grade, '')), ''), grade),
        note         = coalesce(p_note, note),
        harvested_on = coalesce(p_harvested_on, harvested_on)
    where id = p_harvest_id;

    return p_harvest_id;
end;
$$;

-- ------------------------------------------------------------
-- GRANTS
-- ------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function update_flock_event(uuid, numeric, text, text, timestamptz) to authenticated;
        grant execute on function update_herd_event(uuid, numeric, text, text, date) to authenticated;
        grant execute on function update_harvest(uuid, numeric, text, text, date) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
