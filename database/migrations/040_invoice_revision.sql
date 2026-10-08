-- ============================================================
-- 040_invoice_revision.sql — the owner corrects an invoice.
--
-- An invoice is not a row to edit: creating one posted income and a
-- receivable into the ledger (020), so silently rewriting its lines would
-- leave a document that disagrees with the books it came from. The correct
-- correction — the one an accountant would make — is to withdraw the wrong
-- document and issue a right one, and cancel_invoice already knows how to
-- withdraw (it contre-passes the entry and refuses an invoice money has
-- already arrived against).
--
-- So revise_invoice is exactly that, in one transaction: cancel the old,
-- create the new, and say on the new document which one it replaces. One
-- call, because two calls from a phone that loses signal in between would
-- leave a business with a cancelled invoice and no replacement.
--
-- Admin-only, deliberately tighter than cancel_invoice's can_write_org: the
-- employee who may bill a customer does not get to rewrite what was already
-- billed — that is the owner's pen.
-- ============================================================

create or replace function revise_invoice(
    p_invoice_id       uuid,
    p_customer_name    text,
    p_lines            jsonb,
    p_customer_phone   text default null,
    p_customer_address text default null,
    p_due_on           date default null,
    p_due_days         int  default null,
    p_memo             text default null,
    p_issued_on        date default current_date
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor      uuid := auth.uid();
    v_org        uuid;
    v_old_number text;
    v_cancelled  timestamptz;
    v_memo       text;
    v_new        uuid;
begin
    if v_actor is null then
        raise exception 'revise_invoice() needs a signed-in caller';
    end if;

    select org_id, number, cancelled_at
      into v_org, v_old_number, v_cancelled
      from invoices where id = p_invoice_id;

    if v_org is null then
        raise exception 'No such invoice';
    end if;
    if not is_org_admin(v_org) then
        raise exception 'Only an administrator can revise an invoice';
    end if;
    if v_cancelled is not null then
        raise exception
            'Invoice % is already cancelled. Issue a new invoice instead.',
            v_old_number;
    end if;

    -- Withdraws the old document and contre-passes its entry; refuses when
    -- money has already arrived against it, with a message that says what to
    -- do instead. Its own checks run in this same transaction.
    perform cancel_invoice(p_invoice_id,
                           'Remplacée par une facture corrigée');

    -- The replacement carries its own (next) number — a corrected invoice is
    -- a new document, not history rewritten — and names the one it replaces.
    v_memo := nullif(btrim(coalesce(p_memo, '')), '');
    v_memo := coalesce(v_memo || ' — ', '')
              || 'Remplace la facture ' || v_old_number;

    v_new := create_invoice(
        p_org_id           => v_org,
        p_customer_name    => p_customer_name,
        p_lines            => p_lines,
        p_customer_phone   => p_customer_phone,
        p_customer_address => p_customer_address,
        p_due_on           => p_due_on,
        p_due_days         => p_due_days,
        p_memo             => v_memo,
        p_issued_on        => p_issued_on
    );

    return v_new;
end;
$$;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function revise_invoice(
            uuid, text, jsonb, text, text, date, int, text, date
        ) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
