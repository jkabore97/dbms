-- ============================================================
-- 027_product_lifecycle.sql — taking a product off the shelves.
--
-- The owner asked for two things: to fix a product's name, and to delete a
-- product. The first needs no schema at all — `products` has been updatable
-- by staff under RLS since 011, and every sale line, production input and
-- receipt snapshots the name it saw, so a rename cannot rewrite history.
--
-- The second is deliberately not a DELETE. A product that has ever been
-- sold, received or produced is referenced by that history, and history
-- here is never erased — the same rule that makes a wrong sale a return
-- rather than an edit. "Deleting" a product means archiving it:
-- `is_active` goes false, it disappears from the shelves, the sale sheet
-- and the pickers, and every number it ever touched stays exactly where
-- it is. Archiving is reversible for the same reason.
--
-- Who may do it: an owner or admin, checked by the server. Prices and
-- names are the daily texture of running a shop and stay open to staff;
-- making a product vanish is a decision about what the business sells,
-- and that belongs to the person who answers for the business. RLS
-- cannot gate one column more tightly than the rest of the row, so the
-- flip goes through a SECURITY DEFINER function that makes the check
-- the policy cannot.
-- ============================================================

create or replace function archive_product(
    p_product_id uuid,
    p_archived   boolean default true
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org uuid;
begin
    if auth.uid() is null then
        raise exception 'archive_product() needs a signed-in caller';
    end if;

    select org_id into v_org from products where id = p_product_id;
    if v_org is null then
        raise exception 'No such product';
    end if;

    if not is_org_admin(v_org) then
        raise exception 'Only an owner or admin can remove a product from the shop';
    end if;

    update products set is_active = not p_archived where id = p_product_id;
end;
$$;

comment on function archive_product(uuid, boolean) is
    'Removes a product from the shelves without touching its history, or puts it back. Owner/admin only.';

revoke execute on function archive_product(uuid, boolean) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function archive_product(uuid, boolean) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
