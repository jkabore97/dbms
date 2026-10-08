-- ============================================================
-- 037_wave_payment.sql — preparing the ground for Wave mobile payments.
--
-- The plan the user set: at a sale, offer Wave; show the merchant's Wave QR so
-- the customer scans and pays; later, when a payment signal can be wired in,
-- the app confirms automatically and prints a receipt carrying the Wave
-- sender's name. This migration builds everything that does not need the live
-- signal — the data model, the account routing, and the two small functions the
-- app calls — and leaves a clean seam where the webhook will attach later.
--
-- WHAT IS DELIBERATELY NOT HERE. No Wave API call, no secret, no webhook. Those
-- need a Wave merchant credential held as a Worker secret, which is a separate,
-- guarded step. Until then the owner confirms a Wave payment by hand (they are
-- standing there watching the customer's phone), and `attach_wave_payment`
-- records it exactly as the webhook eventually will — so wiring the signal is a
-- matter of calling the same function from the Worker, not reworking this.
--
-- WHY record_sale IS NOT REWRITTEN. A Wave sale is an ordinary sale whose money
-- lands in mobile money; the only new facts are the payer's name and a
-- reference. Reproducing the 180-line record_sale (029) just to store two
-- columns is how the two copies drift apart. Instead 'wave' is taught to the
-- account router, and a second small call stamps the Wave facts onto the sale
-- record_sale already returned.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The merchant's Wave handle, per business. This is what the QR encodes;
--    the owner sets it once in settings. Null until they do — the sale sheet
--    then knows not to offer Wave.
-- ------------------------------------------------------------
alter table orgs add column if not exists wave_merchant text;

-- ------------------------------------------------------------
-- 2. The Wave facts on a sale. All null for every non-Wave sale, so nothing
--    existing changes and the columns mean something only where they are set.
--      wave_sender    — the name Wave reports for the payer, for the receipt.
--      payment_ref    — Wave's transaction id, for reconciliation later.
--      payment_status — 'pending' | 'confirmed'. The seam for auto-confirm:
--                       today it is written 'confirmed' by the owner's hand;
--                       tomorrow by the webhook, unchanged here.
-- ------------------------------------------------------------
alter table sales add column if not exists wave_sender    text;
alter table sales add column if not exists payment_ref    text;
alter table sales add column if not exists payment_status text
    check (payment_status is null or payment_status in ('pending', 'confirmed'));

-- ------------------------------------------------------------
-- 3. A Wave sale's money is mobile money. The router in 007 sent any unknown
--    method to an account named after it; 'wave' would have minted a stray
--    "wave" asset account. Teach it that Wave is mobile money (1020), so the
--    books read a Wave sale beside every other mobile-money one. Rest verbatim.
-- ------------------------------------------------------------
create or replace function resolve_cash_account(
    p_org_id uuid,
    p_method text,
    p_actor  uuid default null
)
returns uuid
language plpgsql
as $$
begin
    return case btrim(lower(coalesce(p_method, 'cash')))
        when 'cash'         then ensure_account_by_code(p_org_id, '1000', 'Cash on Hand', 'asset', p_actor)
        when 'bank'         then ensure_account_by_code(p_org_id, '1010', 'Bank Account', 'asset', p_actor)
        when 'mobile_money' then ensure_account_by_code(p_org_id, '1020', 'Mobile Money', 'asset', p_actor)
        when 'wave'         then ensure_account_by_code(p_org_id, '1020', 'Mobile Money', 'asset', p_actor)
        else ensure_account(p_org_id, p_method, 'asset', p_actor)
    end;
end;
$$;
revoke execute on function resolve_cash_account(uuid, text, uuid) from public;

-- ------------------------------------------------------------
-- 4. The owner sets (or clears) their Wave handle. Admin-only, their own
--    business only — the same gate update_org uses.
-- ------------------------------------------------------------
create or replace function set_org_wave(
    p_org_id   uuid,
    p_merchant text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'set_org_wave() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Only an administrator can change the Wave account';
    end if;
    update orgs
       set wave_merchant = nullif(btrim(coalesce(p_merchant, '')), '')
     where id = p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- 5. Stamp the Wave facts onto a sale. Called by the app right after
--    record_sale for a Wave payment, and — once the signal is wired — by the
--    Worker webhook with the same arguments. Idempotent: re-running with the
--    same values changes nothing, so a retried confirmation is safe.
--
--    Gated by can_write_org on the sale's own org: whoever may record the sale
--    may confirm its payment, and no one may touch another business's sale.
-- ------------------------------------------------------------
create or replace function attach_wave_payment(
    p_sale_id uuid,
    p_sender  text,
    p_ref     text default null,
    p_status  text default 'confirmed'
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
        raise exception 'attach_wave_payment() needs a signed-in caller';
    end if;

    select org_id into v_org from sales where id = p_sale_id;
    if v_org is null then
        raise exception 'No such sale';
    end if;
    if not can_write_org(v_org) then
        raise exception 'You cannot confirm payment for this business';
    end if;
    if coalesce(p_status, 'confirmed') not in ('pending', 'confirmed') then
        raise exception 'Unknown payment status: %', p_status;
    end if;

    update sales set
        wave_sender    = nullif(btrim(coalesce(p_sender, '')), ''),
        payment_ref    = nullif(btrim(coalesce(p_ref, '')), ''),
        payment_status = coalesce(p_status, 'confirmed')
    where id = p_sale_id;
end;
$$;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_org_wave(uuid, text)                      to authenticated;
        grant execute on function attach_wave_payment(uuid, text, text, text)   to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
