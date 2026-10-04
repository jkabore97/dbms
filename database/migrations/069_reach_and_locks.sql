-- ============================================================
-- 069_reach_and_locks.sql — a delivery has a reach, and three tools that
-- were only hidden are now locked.
--
-- Two findings of the October audit, both live:
--
--   1. A delivery had no maximum distance. delivery_fee() multiplied the
--      per-km rate by whatever lay between the shop's pin and the
--      customer's, so a shop pinned in New Jersey quoted a customer in
--      Ouagadougou 1 149 450 FCFA for 7 660 km. A moto delivers across a
--      town, not an ocean. From here a delivery has a reach: the platform's
--      default (delivery_max_km, 15 to start) unless the shop set its own.
--      Beyond it there is no fee (delivery_fee() answers null, as it does
--      for "no pin"), delivery_check() says so in numbers for the basket,
--      and an order for delivery beyond it is refused at the door — whatever
--      the app in front of it is old enough to believe.
--
--   2. The owner's dial (031) is enforced by the database for articles,
--      credits, production, tontines and payroll — and only by hiding
--      buttons for Factures, Photos and Rapports. A hidden button is not a
--      lock: an employee the owner shut out of invoices could still create
--      one through the API. Now:
--        * invoices: writing one (create, revise, cancel, a payment) needs
--          'edit' on 'invoices', by triggers on the tables, so every writer
--          present and future is caught — the 031 pattern.
--        * photos: a document needs 'edit' on 'photos' to be taken or
--          filed; one attached to an article needs 'edit' on 'products'
--          instead, the dial the owner set for articles. The gallery's two
--          lists need 'photos' not hidden.
--        * reports: the eight report functions refuse a caller whose dial
--          says 'hidden' for 'reports'.
--
-- How the report and gallery functions are guarded without rewriting
-- them: each is renamed <name>_core and closed to everyone, and a thin
-- function under the original name checks the dial and calls it. Their
-- bodies — the part that took care to get right — are not touched, and
-- the bundle stays re-runnable (an earlier migration re-creating the
-- original only replaces the guard, which this one then puts back).
-- ============================================================

-- ------------------------------------------------------------
-- 1. The reach of a delivery
-- ------------------------------------------------------------
insert into platform_settings (key, value) values ('delivery_max_km', '15')
on conflict (key) do nothing;

alter table orgs add column if not exists delivery_max_km numeric(8, 2);
alter table orgs drop constraint if exists orgs_delivery_max_km_positive;
alter table orgs add constraint orgs_delivery_max_km_positive
    check (delivery_max_km is null or (delivery_max_km > 0 and delivery_max_km <= 200));

comment on column orgs.delivery_max_km is
    'How far this shop delivers, in km (069). Null = the platform default '
    '(platform_settings.delivery_max_km). Beyond it no fee is quoted and a '
    'delivery order is refused.';

-- The reach that applies to a shop: its own, else the platform's.
create or replace function delivery_reach_km(p_org_id uuid)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        (select delivery_max_km from orgs where id = p_org_id),
        (select (value #>> '{}')::numeric from platform_settings
          where key = 'delivery_max_km'),
        15);
$$;

-- An administrator of the shop sets its reach; null returns it to the
-- platform's default.
create or replace function set_delivery_reach(p_org_id uuid, p_km numeric)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'set_delivery_reach() needs a signed-in caller';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur règle la distance de livraison';
    end if;
    if p_km is not null and (p_km <= 0 or p_km > 200) then
        raise exception 'La distance de livraison va de 1 à 200 km';
    end if;
    update orgs set delivery_max_km = p_km where id = p_org_id;
end;
$$;

-- 061 verbatim, with the reach: beyond it, no fee.
create or replace function delivery_fee(
    p_org_id uuid,
    p_lat    double precision,
    p_lng    double precision
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_org      orgs%rowtype;
    v_base     numeric;
    v_per_km   numeric;
    v_currency text;
    v_fee      numeric;
    v_km       double precision;
begin
    if p_lat is null or p_lng is null then
        return null;
    end if;
    select * into v_org from orgs where id = p_org_id;
    if not found or v_org.lat is null or v_org.lng is null then
        return null;
    end if;
    v_km := distance_km(v_org.lat, v_org.lng, p_lat, p_lng);
    if v_km > delivery_reach_km(p_org_id) then
        return null; -- out of reach: there is no price for an impossible run
    end if;
    if v_org.delivery_base is not null then
        v_base   := v_org.delivery_base;
        v_per_km := v_org.delivery_per_km;
    else
        select (value #>> '{}')::text into v_currency
          from platform_settings where key = 'delivery_currency';
        if coalesce(v_org.default_currency, 'XOF') <> coalesce(v_currency, 'XOF') then
            return null; -- the platform's numbers are in another money
        end if;
        select (value #>> '{}')::numeric into v_base
          from platform_settings where key = 'delivery_base';
        select (value #>> '{}')::numeric into v_per_km
          from platform_settings where key = 'delivery_per_km';
        if v_base is null or v_per_km is null then
            return null;
        end if;
    end if;
    v_fee := v_base + v_per_km * v_km;
    return round(v_fee / 25) * 25;
end;
$$;

-- The basket's question, answered in numbers: the fee (or none), how far
-- the door is, how far this shop goes, and whether it is too far. One row
-- when the shop is open and has a pin; none otherwise. A new function
-- rather than a new shape for delivery_quote(), so an app built before
-- 069 keeps asking its old question and gets its old kind of answer.
create or replace function delivery_check(
    p_slug text,
    p_lat  double precision,
    p_lng  double precision
)
returns table (
    fee         numeric,
    distance_km numeric,
    max_km      numeric,
    too_far     boolean
)
language sql
stable
security definer
set search_path = public
as $$
    select delivery_fee(o.id, p_lat, p_lng),
           round(distance_km(o.lat, o.lng, p_lat, p_lng)::numeric, 1),
           delivery_reach_km(o.id),
           distance_km(o.lat, o.lng, p_lat, p_lng) > delivery_reach_km(o.id)
    from orgs o
    where o.id = storefront_open(p_slug)
      and o.lat is not null and o.lng is not null
      and p_lat is not null and p_lng is not null;
$$;

-- The door: a delivery pinned beyond the shop's reach is refused, by
-- whichever path the order arrives.
create or replace function trg_order_within_reach()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org orgs%rowtype;
    v_km  double precision;
    v_max numeric;
begin
    if new.fulfilment <> 'delivery'
       or new.drop_lat is null or new.drop_lng is null then
        return new;
    end if;
    select * into v_org from orgs where id = new.org_id;
    if v_org.lat is null or v_org.lng is null then
        return new; -- no shop pin: no distance to hold it to
    end if;
    v_km  := distance_km(v_org.lat, v_org.lng, new.drop_lat, new.drop_lng);
    v_max := delivery_reach_km(new.org_id);
    if v_km > v_max then
        raise exception 'Trop loin pour une livraison : % km, la boutique livre jusqu''à % km. Choisissez le retrait en boutique.',
            round(v_km::numeric, 1), v_max;
    end if;
    return new;
end;
$$;

drop trigger if exists order_within_reach on orders;
create trigger order_within_reach
before insert on orders
for each row execute function trg_order_within_reach();

-- ------------------------------------------------------------
-- 2. Factures: locked by the dial
-- ------------------------------------------------------------
-- Its own guard rather than 031's shared one: that one fails closed when
-- nobody is signed in, which would also lock the platform itself out of
-- an invoice (the SQL editor, a service key).
create or replace function trg_guard_invoice()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        return new; -- the platform itself; see trg_guard_document()
    end if;
    if feature_access(new.org_id, 'invoices') <> 'edit' then
        raise exception 'Les factures vous sont fermées. Voyez le propriétaire.';
    end if;
    return new;
end;
$$;

drop trigger if exists guard_invoices on invoices;
create trigger guard_invoices
before insert or update on invoices
for each row execute function trg_guard_invoice();

-- invoice_payments carries no org_id; its invoice knows it.
create or replace function trg_guard_invoice_payment()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org uuid;
begin
    if auth.uid() is null then
        return new; -- the platform itself; see trg_guard_document()
    end if;
    select org_id into v_org from invoices where id = new.invoice_id;
    if v_org is not null and feature_access(v_org, 'invoices') <> 'edit' then
        raise exception 'Les factures vous sont fermées. Voyez le propriétaire.';
    end if;
    return new;
end;
$$;

drop trigger if exists guard_invoice_payments on invoice_payments;
create trigger guard_invoice_payments
before insert on invoice_payments
for each row execute function trg_guard_invoice_payment();

-- ------------------------------------------------------------
-- 3. Photos: locked by the dial
-- ------------------------------------------------------------
-- Taking or filing a document is 'photos'; an article's own photograph is
-- the articles dial's business, since that is where the owner said who may
-- change an article.
create or replace function trg_guard_document()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    -- No signed-in person: the platform itself (the SQL editor, a service
    -- key). A stranger never gets here — anon holds no grant on documents
    -- and every function that writes one demands a member (can_write_org).
    if auth.uid() is null then
        return new;
    end if;
    if new.product_id is not null then
        if feature_access(new.org_id, 'products') <> 'edit' then
            raise exception 'Les articles vous sont fermés. Voyez le propriétaire.';
        end if;
    elsif feature_access(new.org_id, 'photos') <> 'edit' then
        raise exception 'Les photos vous sont fermées. Voyez le propriétaire.';
    end if;
    return new;
end;
$$;

drop trigger if exists guard_documents on documents;
create trigger guard_documents
before insert or update on documents
for each row execute function trg_guard_document();

-- ------------------------------------------------------------
-- 4. The guard in front of a function
-- ------------------------------------------------------------
-- Raises when the caller's dial is below what the tool needs. 'view' means
-- "not hidden"; 'edit' means edit.
create or replace function require_feature(
    p_org_id  uuid,
    p_feature text,
    p_need    text default 'view'
)
returns void
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v text;
begin
    -- No signed-in person: step aside and let the function behind decide,
    -- as it did before 069 (each answers a non-member with nothing).
    -- feature_access() fails closed for "nobody" (032), which is right for
    -- a permission answer and wrong for a guard in front of one.
    if auth.uid() is null then
        return;
    end if;
    -- A stranger to the business is not refused here either: the function
    -- behind answers them with nothing, the promise the report suites hold
    -- it to. Only a member the owner shut out is told no.
    if not exists (select 1 from memberships
                    where org_id = p_org_id and user_id = auth.uid()) then
        return;
    end if;
    v := feature_access(p_org_id, p_feature);
    if v = 'hidden' or (p_need = 'edit' and v <> 'edit') then
        raise exception '%', case p_feature
            when 'reports'  then 'Les rapports vous sont fermés. Voyez le propriétaire.'
            when 'photos'   then 'Les photos vous sont fermées. Voyez le propriétaire.'
            when 'invoices' then 'Les factures vous sont fermées. Voyez le propriétaire.'
            else 'Cet outil vous est fermé. Voyez le propriétaire.' end;
    end if;
end;
$$;

-- Renames f(args) to f_core(args) once, and closes the core to everyone:
-- only the guard in front of it calls it.
do $$
declare
    v_sig text;
    v_core text;
begin
    foreach v_sig in array array[
        'income_statement(uuid, date, date)',
        'balance_sheet(uuid, date)',
        'trial_balance(uuid, date, date)',
        'account_ledger(uuid, uuid, date, date, integer)',
        'journal_page(uuid, date, date, integer, integer)',
        'church_weekly_summary(uuid, date)',
        'church_balances(uuid)',
        'member_giving_statement(uuid, integer)',
        'org_documents(uuid, text, integer, integer)',
        'unfiled_documents(uuid, integer)'
    ] loop
        v_core := split_part(v_sig, '(', 1) || '_core(' || split_part(v_sig, '(', 2);
        -- Once only. On a re-run of the bundle the core already exists, and
        -- the original that an earlier migration re-created over the guard
        -- is simply replaced by the guard below.
        if to_regprocedure(v_core) is null then
            execute format('alter function %s rename to %s',
                           v_sig, split_part(v_sig, '(', 1) || '_core');
        end if;
        execute format('revoke execute on function %s from public', v_core);
        if exists (select 1 from pg_roles where rolname = 'anon') then
            execute format('revoke execute on function %s from anon', v_core);
        end if;
        if exists (select 1 from pg_roles where rolname = 'authenticated') then
            execute format('revoke execute on function %s from authenticated', v_core);
        end if;
    end loop;
end $$;

create or replace function income_statement(
    p_org_id uuid, p_from date default null, p_to date default null)
returns table (section text, code text, name text, amount numeric)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
    perform require_feature(p_org_id, 'reports');
    return query select * from income_statement_core(p_org_id, p_from, p_to);
end;
$$;

create or replace function balance_sheet(
    p_org_id uuid, p_as_of date default null)
returns table (section text, code text, name text, amount numeric)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
    perform require_feature(p_org_id, 'reports');
    return query select * from balance_sheet_core(p_org_id, p_as_of);
end;
$$;

create or replace function trial_balance(
    p_org_id uuid, p_from date default null, p_to date default null)
returns table (code text, name text, type text,
               total_debit numeric, total_credit numeric, balance numeric)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
    perform require_feature(p_org_id, 'reports');
    return query select * from trial_balance_core(p_org_id, p_from, p_to);
end;
$$;

create or replace function account_ledger(
    p_org_id uuid, p_account_id uuid,
    p_from date default null, p_to date default null, p_limit int default 200)
returns table (entry_id uuid, occurred_at timestamptz, label text, memo text,
               debit numeric, credit numeric, balance numeric,
               reversed boolean, recorded_by text)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
    perform require_feature(p_org_id, 'reports');
    return query select * from account_ledger_core(
        p_org_id, p_account_id, p_from, p_to, p_limit);
end;
$$;

create or replace function journal_page(
    p_org_id uuid, p_from date default null, p_to date default null,
    p_limit int default 100, p_offset int default 0)
returns table (entry_id uuid, occurred_at timestamptz, label text, memo text,
               details jsonb, amount numeric, debit_names text,
               credit_names text, direction text, reversed boolean,
               is_reversal boolean, recorded_by text)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
    perform require_feature(p_org_id, 'reports');
    return query select * from journal_page_core(
        p_org_id, p_from, p_to, p_limit, p_offset);
end;
$$;

create or replace function church_weekly_summary(
    p_org_id uuid, p_week_ending date default current_date)
returns table (category text, label text, amount numeric)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
    perform require_feature(p_org_id, 'reports');
    return query select * from church_weekly_summary_core(p_org_id, p_week_ending);
end;
$$;

create or replace function church_balances(p_org_id uuid)
returns table (account_name text, balance numeric)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
    perform require_feature(p_org_id, 'reports');
    return query select * from church_balances_core(p_org_id);
end;
$$;

-- Keyed by member, not by business: the member's business holds the dial.
create or replace function member_giving_statement(
    p_member_id uuid,
    p_year int default extract(year from current_date)::int)
returns table (contribution_date date, kind text, amount numeric)
language plpgsql stable security definer set search_path = public, auth
as $$
declare
    v_org uuid;
begin
    select org_id into v_org from church_members where id = p_member_id;
    if v_org is not null then
        perform require_feature(v_org, 'reports');
    end if;
    return query select * from member_giving_statement_core(p_member_id, p_year);
end;
$$;

-- The gallery's lists run as the caller (013), and stay so.
create or replace function org_documents(
    p_org_id uuid, p_kind text default null,
    p_limit int default 60, p_offset int default 0)
returns table (id uuid, r2_key text, kind text, caption text,
               content_type text, byte_size bigint, captured_at timestamptz,
               ocr_status text, ocr_text text, barcode text, product_id uuid,
               product_name text, entry_id uuid, entry_label text,
               uploaded_by uuid, uploaded_name text)
language plpgsql stable security invoker set search_path = public
as $$
begin
    perform require_feature(p_org_id, 'photos');
    return query select * from org_documents_core(p_org_id, p_kind, p_limit, p_offset);
end;
$$;

create or replace function unfiled_documents(p_org_id uuid, p_limit int default 60)
returns table (id uuid, r2_key text, kind text, content_type text,
               captured_at timestamptz, ocr_status text, ocr_text text,
               barcode text)
language plpgsql stable security invoker set search_path = public
as $$
begin
    perform require_feature(p_org_id, 'photos');
    return query select * from unfiled_documents_core(p_org_id, p_limit);
end;
$$;

-- The invoker gallery calls a core it may not execute directly: the cores
-- of the two invoker lists stay callable by authenticated (they were
-- invoker before and still are — RLS still decides every row), and only
-- the definer report cores are closed.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function org_documents_core(uuid, text, integer, integer) to authenticated;
        grant execute on function unfiled_documents_core(uuid, integer)            to authenticated;
    end if;
end $$;

-- ------------------------------------------------------------
-- 5. Grants
-- ------------------------------------------------------------
revoke execute on function delivery_reach_km(uuid)                 from public;
revoke execute on function set_delivery_reach(uuid, numeric)       from public;
revoke execute on function delivery_check(text, double precision, double precision) from public;
revoke execute on function require_feature(uuid, text, text)       from public;
revoke execute on function income_statement(uuid, date, date)      from public;
revoke execute on function balance_sheet(uuid, date)               from public;
revoke execute on function trial_balance(uuid, date, date)         from public;
revoke execute on function account_ledger(uuid, uuid, date, date, integer) from public;
revoke execute on function journal_page(uuid, date, date, integer, integer) from public;
revoke execute on function church_weekly_summary(uuid, date)       from public;
revoke execute on function church_balances(uuid)                   from public;
revoke execute on function member_giving_statement(uuid, integer)  from public;
revoke execute on function org_documents(uuid, text, integer, integer) from public;
revoke execute on function unfiled_documents(uuid, integer)        from public;

do $$
begin
    -- The street asks the reach before an order (063 rule: say it by name).
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function delivery_check(text, double precision, double precision) to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function delivery_check(text, double precision, double precision) to authenticated;
        grant execute on function set_delivery_reach(uuid, numeric)       to authenticated;
        -- Called as the caller by the two invoker gallery lists.
        grant execute on function require_feature(uuid, text, text)       to authenticated;
        grant execute on function income_statement(uuid, date, date)      to authenticated;
        grant execute on function balance_sheet(uuid, date)               to authenticated;
        grant execute on function trial_balance(uuid, date, date)         to authenticated;
        grant execute on function account_ledger(uuid, uuid, date, date, integer) to authenticated;
        grant execute on function journal_page(uuid, date, date, integer, integer) to authenticated;
        grant execute on function church_weekly_summary(uuid, date)       to authenticated;
        grant execute on function church_balances(uuid)                   to authenticated;
        grant execute on function member_giving_statement(uuid, integer)  to authenticated;
        grant execute on function org_documents(uuid, text, integer, integer) to authenticated;
        grant execute on function unfiled_documents(uuid, integer)        to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
