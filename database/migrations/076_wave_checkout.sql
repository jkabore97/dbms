-- ============================================================
-- 076_wave_checkout.sql — paying by Wave (or card, on Wave's page), and the
-- shop paid on its own Wave number a moment later.
--
-- Until now every payment closed by hand: "J'ai payé" for Kaj Pro and spots,
-- « Paiement reçu » from the shop for a vitrine order paid on its own Wave
-- link. This is the automatic path, and it is Kaj's to run (the owner's
-- choice, "option 2"): Kaj holds one Wave Business account, registered with
-- Wave as an aggregator, and
--
--   * a shopper pays an order through a Wave checkout session tagged with
--     the shop (its aggregated-merchant id);
--   * Wave tells the kaj-pay Worker it is paid (a signed webhook);
--   * the order is marked paid, the shop and shopper are told, and the
--     Worker sends the goods' price, less the platform's share, to the
--     shop's own Wave number through Wave's Payout API — no Wave Business,
--     no RCCM, no key on the shop's side;
--   * Kaj Pro and spots paid the same way activate themselves.
--
-- "Card": Wave's checkout page is where a card is taken, when Wave offers it
-- for the account. The session is the same; the app opens it in a browser
-- rather than the Wave app. Nothing here touches a card number.
--
-- Dormant by design: nothing is offered until the platform turns
-- `wave_checkout` on (after the Worker has its WAVE_API_KEY), and an order is
-- payable this way only once its shop has given a payout number.
--
--   1. orgs.wave_payout_number (the shop's), orgs.wave_merchant_ref (the
--      aggregated-merchant id Wave gives each shop, set by the platform).
--   2. wave_payments: every session, its status, and the payout behind it.
--   3. wave_begin(): the caller's side — checks the thing exists, is theirs
--      to pay and is not paid, and fixes the amount from the database, never
--      from the phone.
--   4. wave_attach / wave_settle / wave_payout_done / wave_payout_queue:
--      the Worker's side, for the service role alone.
--   5. The reads: wave_terms(), my_wave_payment(), platform_wave_payments().
-- ============================================================

insert into platform_settings (key, value) values
    ('wave_checkout',       'false'),
    -- Whether Wave's page takes cards for this account: Wave's to offer,
    -- the platform's to say once it has seen it work.
    ('wave_card',           'false'),
    ('wave_commission_pct', '0')
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- 1. The shop's side
-- ------------------------------------------------------------
alter table orgs add column if not exists wave_payout_number text;
alter table orgs add column if not exists wave_merchant_ref text;

create or replace function set_wave_payout_number(p_org_id uuid, p_number text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare v text := nullif(regexp_replace(coalesce(p_number, ''), '[^0-9+]', '', 'g'), '');
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur choisit le numéro qui reçoit l''argent';
    end if;
    if v is not null and length(regexp_replace(v, '\D', '', 'g')) < 8 then
        raise exception 'Numéro Wave trop court';
    end if;
    if v is not null and left(v, 1) <> '+' then
        v := '+226' || right(v, 8);
    end if;
    update orgs set wave_payout_number = v where id = p_org_id;
end;
$$;

create or replace function set_wave_merchant_ref(p_org_id uuid, p_ref text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Seule la plateforme enregistre une boutique chez Wave';
    end if;
    update orgs set wave_merchant_ref = nullif(btrim(coalesce(p_ref, '')), '')
     where id = p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- 2. The payments
-- ------------------------------------------------------------
create table if not exists wave_payments (
    id              uuid primary key default gen_random_uuid(),
    kind            text not null check (kind in ('order', 'pro', 'spot')),
    org_id          uuid not null references orgs(id) on delete cascade,
    order_id        uuid references orders(id) on delete set null,
    promotion_id    uuid references promotions(id) on delete set null,
    period          text check (period in ('month', 'year')),
    payer_id        uuid references profiles(id) on delete set null,
    method          text not null default 'wave' check (method in ('wave', 'card')),
    amount          numeric(14, 2) not null check (amount > 0),
    currency        text not null default 'XOF',
    commission      numeric(14, 2) not null default 0,
    session_id      text unique,
    launch_url      text,
    status          text not null default 'created'
                    check (status in ('created', 'open', 'succeeded', 'failed', 'expired')),
    transaction_id  text,
    payout_status   text not null default 'none'
                    check (payout_status in ('none', 'pending', 'sent', 'failed')),
    payout_to       text,
    payout_amount   numeric(14, 2),
    payout_id       text,
    payout_error    text,
    payout_attempts integer not null default 0,
    created_at      timestamptz not null default now(),
    paid_at         timestamptz,
    paid_out_at     timestamptz
);
create index if not exists wave_payments_payouts on wave_payments (created_at)
    where payout_status in ('pending', 'failed');
create index if not exists wave_payments_by_order on wave_payments (order_id);
alter table wave_payments enable row level security;
-- No policies: read through the functions below.

-- ------------------------------------------------------------
-- 3. The caller's side
-- ------------------------------------------------------------
create or replace function wave_on()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((select (value #>> '{}')::boolean
                       from platform_settings where key = 'wave_checkout'), false);
$$;

-- Starts a payment: kind 'order' (p_ref an order of the caller's), 'pro'
-- (p_ref an org the caller administers; p_period month or year) or 'spot'
-- (p_ref a promotion awaiting payment). Returns what the Worker needs to ask
-- Wave for a session. The amount is the database's.
create or replace function wave_begin(
    p_kind   text,
    p_ref    uuid,
    p_method text default 'wave',
    p_period text default 'month'
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_me     uuid := auth.uid();
    v_org    orgs%rowtype;
    v_amount numeric;
    v_cur    text := 'XOF';
    v_order  orders%rowtype;
    v_spot   promotions%rowtype;
    v_id     uuid;
    v_pct    numeric := coalesce((select (value #>> '{}')::numeric
                                    from platform_settings where key = 'wave_commission_pct'), 0);
begin
    if v_me is null then
        raise exception 'wave_begin() needs a signed-in caller';
    end if;
    if not wave_on() then
        raise exception 'Le paiement Wave n''est pas encore ouvert';
    end if;
    if p_method not in ('wave', 'card') then
        raise exception 'Moyen de paiement inconnu : %', p_method;
    end if;

    if p_kind = 'order' then
        select * into v_order from orders where id = p_ref;
        if not found or v_order.customer_id <> v_me then
            raise exception 'Commande introuvable';
        end if;
        if v_order.status in ('refused', 'cancelled') then
            raise exception 'Cette commande est annulée';
        end if;
        if v_order.paid_at is not null then
            raise exception 'Cette commande est déjà payée';
        end if;
        select * into v_org from orgs where id = v_order.org_id;
        if v_org.wave_payout_number is null then
            raise exception 'Cette boutique ne reçoit pas encore les paiements Wave';
        end if;
        v_amount := v_order.total;
        v_cur := v_order.currency;
    elsif p_kind = 'pro' then
        if not is_org_admin(p_ref) then
            raise exception 'Seul un administrateur paie Kaj Pro';
        end if;
        select * into v_org from orgs where id = p_ref;
        if p_period not in ('month', 'year') then
            raise exception 'Période inconnue : %', p_period;
        end if;
        v_amount := plan_limit(case when p_period = 'year' then 'pro_price_year'
                                    else 'pro_price_month' end,
                               case when p_period = 'year' then 25000 else 2500 end);
    elsif p_kind = 'spot' then
        select * into v_spot from promotions where id = p_ref;
        if not found or not is_org_admin(v_spot.org_id) then
            raise exception 'Mise en avant introuvable';
        end if;
        if v_spot.status not in ('requested', 'paid_claimed') then
            raise exception 'Cette mise en avant n''attend pas de paiement';
        end if;
        select * into v_org from orgs where id = v_spot.org_id;
        v_amount := v_spot.price;
        v_cur := v_spot.currency;
    else
        raise exception 'Paiement inconnu : %', p_kind;
    end if;

    if v_cur <> 'XOF' then
        raise exception 'Wave encaisse en francs CFA (XOF) seulement';
    end if;
    if coalesce(v_amount, 0) <= 0 then
        raise exception 'Rien à payer';
    end if;

    insert into wave_payments (kind, org_id, order_id, promotion_id, period,
                               payer_id, method, amount, currency, commission)
    values (p_kind, v_org.id,
            case when p_kind = 'order' then p_ref end,
            case when p_kind = 'spot' then p_ref end,
            case when p_kind = 'pro' then p_period end,
            v_me, p_method, v_amount, v_cur,
            case when p_kind = 'order' then round(v_amount * v_pct / 100.0) else 0 end)
    returning id into v_id;

    return jsonb_build_object(
        'payment_id',      v_id,
        'client_reference', v_id,
        'amount',          v_amount,
        'currency',        v_cur,
        'kind',            p_kind,
        -- Only an order is the shop's money; Kaj Pro and spots are Kaj's own.
        'aggregated_merchant_id', case when p_kind = 'order' then v_org.wave_merchant_ref end
    );
end;
$$;

-- What the app reads after coming back from Wave: did it go through?
create or replace function my_wave_payment(p_payment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select jsonb_build_object('status', p.status, 'kind', p.kind,
                              'amount', p.amount, 'paid_at', p.paid_at)
    from wave_payments p
    where p.id = p_payment_id
      and (p.payer_id = auth.uid() or is_org_member(p.org_id));
$$;

-- Whether to draw « Payer avec Wave » at all: the platform's switch, and for
-- an order, the shop's payout number.
create or replace function wave_terms(p_org_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'on', wave_on(),
        'shop_ready', p_org_id is not null and exists (
            select 1 from orgs where id = p_org_id and wave_payout_number is not null),
        'card', coalesce((select (value #>> '{}')::boolean
                            from platform_settings where key = 'wave_card'), false),
        'commission_pct', coalesce((select (value #>> '{}')::numeric
                                      from platform_settings where key = 'wave_commission_pct'), 0)
    );
$$;

-- ------------------------------------------------------------
-- 4. The Worker's side (service role only)
-- ------------------------------------------------------------
create or replace function wave_attach(p_payment_id uuid, p_session_id text, p_launch_url text)
returns void
language sql
security definer
set search_path = public
as $$
    update wave_payments
       set session_id = p_session_id, launch_url = p_launch_url, status = 'open'
     where id = p_payment_id and status = 'created';
$$;

-- Wave says a session ended. Idempotent: a second delivery of the same
-- webhook changes nothing and asks for no second payout. Returns the payout
-- to send, or null.
create or replace function wave_settle(
    p_client_reference uuid,
    p_session_id       text,
    p_succeeded        boolean,
    p_transaction_id   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v     wave_payments%rowtype;
    v_org orgs%rowtype;
    v_start timestamptz;
    v_until date;
begin
    select * into v from wave_payments where id = p_client_reference for update;
    if not found then
        return null;
    end if;
    if v.session_id is not null and p_session_id is not null and v.session_id <> p_session_id then
        return null;
    end if;
    if v.status = 'succeeded' then
        return null;  -- delivered twice
    end if;
    if not p_succeeded then
        update wave_payments set status = 'failed' where id = v.id;
        return null;
    end if;

    update wave_payments
       set status = 'succeeded', paid_at = now(),
           transaction_id = p_transaction_id,
           session_id = coalesce(session_id, p_session_id)
     where id = v.id;
    select * into v_org from orgs where id = v.org_id;

    if v.kind = 'order' then
        update orders set paid_at = coalesce(paid_at, now()), payment_method = 'wave'
         where id = v.order_id;
        update wave_payments
           set payout_status = 'pending',
               payout_to = v_org.wave_payout_number,
               payout_amount = v.amount - v.commission
         where id = v.id;
        begin
            perform notify_org_admins(v.org_id, 'order_paid',
                'Commande payée par Wave : ' || to_char(v.amount, 'FM999G999G999')
                || ' F. L''argent part sur votre numéro Wave.');
            insert into notifications (recipient_id, org_id, kind, message)
            select o.customer_id, o.org_id, 'order_paid',
                   'Paiement reçu par ' || v_org.name || ' : merci !'
              from orders o where o.id = v.order_id;
        exception when others then null;
        end;
        return jsonb_build_object(
            'payment_id', v.id,
            'amount', v.amount - v.commission,
            'currency', v.currency,
            'mobile', v_org.wave_payout_number,
            'name', v_org.name);
    elsif v.kind = 'pro' then
        v_until := greatest(coalesce(case when v_org.plan = 'pro' then v_org.plan_until end,
                                     current_date), current_date)
                   + case when v.period = 'year' then interval '1 year' else interval '1 month' end;
        update orgs set plan = 'pro', plan_until = v_until,
                        plan_note = 'Wave ' || coalesce(p_transaction_id, '')
         where id = v.org_id;
        insert into plan_requests (org_id, user_id, amount, note, handled_at)
        values (v.org_id, v.payer_id, v.amount, 'Payé par Wave', now());
        begin
            perform notify_org_admins(v.org_id, 'pro_active',
                'Kaj Pro est actif jusqu''au ' || to_char(v_until, 'DD/MM/YYYY') || '.');
        exception when others then null;
        end;
    elsif v.kind = 'spot' then
        v_start := next_spot_start('article');
        update promotions
           set status = 'approved',
               starts_at = case when kind = 'shop' then now() else v_start end,
               ends_at = case when kind = 'shop' then now() else v_start end
                         + make_interval(days => days),
               decided_at = now(),
               note = 'Payé par Wave'
         where id = v.promotion_id and status in ('requested', 'paid_claimed');
        begin
            perform notify_org_admins(v.org_id, 'spot_approved',
                'Mise en avant payée par Wave : elle est programmée.');
        exception when others then null;
        end;
    end if;
    return null;
end;
$$;

create or replace function wave_payout_done(
    p_payment_id uuid,
    p_ok         boolean,
    p_payout_id  text default null,
    p_error      text default null
)
returns void
language sql
security definer
set search_path = public
as $$
    update wave_payments
       set payout_status = case when p_ok then 'sent' else 'failed' end,
           payout_id = coalesce(p_payout_id, payout_id),
           payout_error = case when p_ok then null else left(p_error, 300) end,
           paid_out_at = case when p_ok then now() end,
           payout_attempts = payout_attempts + 1
     where id = p_payment_id and payout_status in ('pending', 'failed');
$$;

-- Payouts still owed (the Worker's cron retries them), at most five tries.
create or replace function wave_payout_queue()
returns table (payment_id uuid, amount numeric, currency text, mobile text, name text)
language sql
stable
security definer
set search_path = public
as $$
    select p.id, p.payout_amount, p.currency, p.payout_to, o.name
    from wave_payments p join orgs o on o.id = p.org_id
    where p.payout_status in ('pending', 'failed')
      and p.payout_attempts < 5
      and p.payout_to is not null
    order by p.paid_at
    limit 20;
$$;

-- ------------------------------------------------------------
-- 5. The console's view
-- ------------------------------------------------------------
create or replace function platform_wave_payments(p_limit integer default 50)
returns table (
    id uuid, kind text, org_name text, amount numeric, commission numeric,
    method text, status text, payout_status text, payout_to text,
    payout_error text, created_at timestamptz, paid_at timestamptz
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select p.id, p.kind, o.name, p.amount, p.commission, p.method, p.status,
           p.payout_status, p.payout_to, p.payout_error, p.created_at, p.paid_at
    from wave_payments p join orgs o on o.id = p.org_id
    where exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
    order by (p.payout_status = 'failed') desc, p.created_at desc
    limit least(greatest(coalesce(p_limit, 50), 1), 200);
$$;

-- ------------------------------------------------------------
-- Grants
-- ------------------------------------------------------------
revoke execute on function set_wave_payout_number(uuid, text)          from public;
revoke execute on function set_wave_merchant_ref(uuid, text)           from public;
revoke execute on function wave_on()                                   from public;
revoke execute on function wave_begin(text, uuid, text, text)          from public;
revoke execute on function my_wave_payment(uuid)                       from public;
revoke execute on function wave_terms(uuid)                            from public;
revoke execute on function wave_attach(uuid, text, text)               from public;
revoke execute on function wave_settle(uuid, text, boolean, text)      from public;
revoke execute on function wave_payout_done(uuid, boolean, text, text) from public;
revoke execute on function wave_payout_queue()                         from public;
revoke execute on function platform_wave_payments(integer)             from public;

do $$
begin
    -- Supabase's default privileges grant every new function to
    -- authenticated directly (063 closed only anon and PUBLIC), so the
    -- Worker's four are taken back from it by name, as 060 does for push.
    -- Without this any signed-in person could settle their own order.
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function wave_attach(uuid, text, text)               from anon;
        revoke execute on function wave_settle(uuid, text, boolean, text)      from anon;
        revoke execute on function wave_payout_done(uuid, boolean, text, text) from anon;
        revoke execute on function wave_payout_queue()                         from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function wave_attach(uuid, text, text)               from authenticated;
        revoke execute on function wave_settle(uuid, text, boolean, text)      from authenticated;
        revoke execute on function wave_payout_done(uuid, boolean, text, text) from authenticated;
        revoke execute on function wave_payout_queue()                         from authenticated;
        grant execute on function set_wave_payout_number(uuid, text) to authenticated;
        grant execute on function set_wave_merchant_ref(uuid, text)  to authenticated;
        grant execute on function wave_begin(text, uuid, text, text) to authenticated;
        grant execute on function my_wave_payment(uuid)              to authenticated;
        grant execute on function wave_terms(uuid)                   to authenticated;
        grant execute on function platform_wave_payments(integer)    to authenticated;
    end if;
    -- The kaj-pay Worker, and nothing else.
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function wave_attach(uuid, text, text)               to service_role;
        grant execute on function wave_settle(uuid, text, boolean, text)      to service_role;
        grant execute on function wave_payout_done(uuid, boolean, text, text) to service_role;
        grant execute on function wave_payout_queue()                         to service_role;
    end if;
end $$;

notify pgrst, 'reload schema';
