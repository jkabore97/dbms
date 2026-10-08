-- ============================================================
-- 034_production_edit.sql — correcting a production run after it is recorded.
--
-- A batch is recorded the morning it is made: "40 cakes from this much flour,
-- sugar, eggs". A wrong output count — 40 typed as 20 — could only be lived
-- with until now. update_production_run() corrects the run in place, the same
-- shape as the farm corrections (033) and for the same reason: a production run
-- posts NO ledger entry (see 026), so there is nothing to keep balanced and the
-- honest fix is to change the number.
--
-- What a correction does NOT do: re-run the stock math. The ingredients a batch
-- consumed are snapshotted per run and are a fact about what left the shelf that
-- morning; correcting how many cakes came out does not un-consume flour. So the
-- inputs and the run's total_cost are left exactly as recorded, and only the
-- OUTPUT is corrected — with one derived consequence: unit_cost is total_cost
-- over quantity, so fixing "20" to "40" halves what each cake costs to make,
-- which is precisely the correction intended. A wrong INGREDIENT is a different
-- act (re-record the run); this is for the output count, its name, its note.
--
-- SECURITY DEFINER with a can_write_org() guard, mirroring record_production.
-- Note it also passes under the trg_guard_feature_edit trigger 031 put on
-- production_runs: an employee dialled to 'view' on production cannot correct a
-- run any more than they can record one. That is enforced by the trigger on the
-- UPDATE below, on top of the guard here.
-- ============================================================

create or replace function update_production_run(
    p_run_id       uuid,
    p_quantity     numeric     default null,
    p_product_name text        default null,
    p_note         text        default null,
    p_occurred_at  timestamptz default null
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
        raise exception 'update_production_run() needs a signed-in caller';
    end if;

    select org_id into v_org from production_runs where id = p_run_id;

    if v_org is null then
        raise exception 'No such production run';
    end if;
    if not can_write_org(v_org) then
        raise exception 'You cannot correct entries for this business';
    end if;
    if p_quantity is not null and p_quantity <= 0 then
        raise exception 'A production needs the quantity that was made (got %)',
            p_quantity;
    end if;

    update production_runs set
        quantity     = coalesce(p_quantity, quantity),
        product_name = coalesce(nullif(btrim(coalesce(p_product_name, '')), ''),
                                product_name),
        note         = coalesce(p_note, note),
        occurred_at  = coalesce(p_occurred_at, occurred_at),
        -- The ingredients, and so total_cost, are unchanged by a correction to
        -- the output count. Unit cost re-derives from the fixed total.
        unit_cost    = case
                         when p_quantity is not null and p_quantity > 0
                         then round(total_cost / p_quantity, 4)
                         else unit_cost
                       end
    where id = p_run_id;

    return p_run_id;
end;
$$;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function update_production_run(uuid, numeric, text, text, timestamptz) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
