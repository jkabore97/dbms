-- ============================================================
-- 003_sync_support.sql
--
-- The app only ever knows the client_uuid it generated on the device — it
-- may never have received the server's entry id, because the original
-- contribution and its undo can both happen offline, in that order, before
-- either reaches the server.
--
-- This resolves a client_uuid to the real entry and reverses it.
-- ============================================================

create or replace function reverse_entry_by_client_uuid(
    p_org_id                uuid,
    p_original_client_uuid  uuid,
    p_reversed_by           uuid,
    p_reason                text default null
)
returns uuid
language plpgsql
as $$
declare
    v_entry_id uuid;
begin
    select id into v_entry_id
    from journal_entries
    where org_id = p_org_id
      and client_uuid = p_original_client_uuid;

    if v_entry_id is null then
        -- The original hasn't synced yet. The caller should retry after the
        -- outbox has drained further; ordering by created_at usually prevents
        -- this, but a partial sync can still get here.
        raise exception 'Original entry % not yet synced', p_original_client_uuid;
    end if;

    return reverse_entry(v_entry_id, p_reversed_by, p_reason);
end;
$$;
