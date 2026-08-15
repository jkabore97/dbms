-- ============================================================
-- 029_sale_on_credit.sql — crédit becomes a payment method.
--
-- The carnet (024) records money faithfully but never touched the goods:
-- a sack of rice taken on credit stayed on the shelf count, missed the
-- day's totals, and carried no cost — the shop knew what Awa owed but not
-- what the sale earned. The fix is not to bolt products onto the carnet;
-- it is to let the normal sale flow say "crédit" where it says "espèces".
--
-- A credit sale through record_sale() is a *sale* in every respect —
-- lines, stock decrements, cost snapshots, the day's numbers — except
-- where the money lands: debit 1100 Créances clients instead of the cash
-- box, plus a debt in the carnet naming the customer and linked to the
-- sale, so the carnet can show what was taken. Repayments were already
-- built in 024 and need nothing new.
--
-- record_sale() is dropped and recreated because its signature grows two
-- parameters; CREATE OR REPLACE alone would leave the old seven-argument
-- version alongside as an overload, and PostgREST would refuse the
-- ambiguity. The rewrite also adds the explicit caller checks the 011
-- version left to its callees.
--
-- record_return() now refuses credit sales, loudly. A return posts money
-- out of a cash account, which is simply false for a sale nobody has paid
-- yet; the honest correction path for credit is a repayment in the carnet
-- (or a correcting entry), and a clear refusal beats books that lie.
-- ============================================================

-- What the carnet can now show: the sale a debt came from.
alter table debts
    add column if not exists sale_id uuid references sales(id);

comment on column debts.sale_id is
    'Set when the debt was created by a credit sale through record_sale(); the carnet shows what was taken.';

drop function if exists record_sale(uuid, jsonb, text, text, uuid, text, timestamptz);

create or replace function record_sale(
    p_org_id         uuid,
    p_lines          jsonb,
    p_method         text        default 'cash',
    p_note           text        default null,
    p_client_uuid    uuid        default null,
    p_device_id      text        default null,
    p_occurred_at    timestamptz default now(),
    p_customer_name  text        default null,
    p_customer_phone text        default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor     uuid := auth.uid();
    v_credit    boolean := lower(coalesce(p_method, '')) in ('credit', 'crédit');
    v_cust_name text := btrim(coalesce(p_customer_name, ''));
    v_sale_id   uuid;
    v_existing  uuid;
    v_line      jsonb;
    v_product   uuid;
    v_name      text;
    v_qty       numeric;
    v_price     numeric;
    v_cost      numeric;
    v_total     numeric := 0;
    v_entry     uuid;
    v_customer  uuid;
    v_receivable uuid;
    v_income    uuid;
    v_label     text;
begin
    if v_actor is null then
        raise exception 'record_sale() needs a signed-in caller';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record entries for this business';
    end if;
    if p_lines is null or jsonb_typeof(p_lines) <> 'array'
       or jsonb_array_length(p_lines) = 0 then
        raise exception 'A sale needs at least one line';
    end if;
    if v_credit and v_cust_name = '' then
        raise exception 'A credit sale needs the customer''s name';
    end if;

    -- A retried sale returns the original rather than selling twice. The
    -- phone in a market retries whenever signal returns, which is often.
    if p_client_uuid is not null then
        select id into v_existing from sales
        where org_id = p_org_id and client_uuid = p_client_uuid;
        if v_existing is not null then
            return v_existing;
        end if;
    end if;

    insert into sales (org_id, kind, occurred_at, method, note, recorded_by,
                       device_id, client_uuid)
    values (p_org_id, 'sale', p_occurred_at,
            case when v_credit then 'credit' else p_method end,
            p_note, v_actor, p_device_id, p_client_uuid)
    returning id into v_sale_id;

    for v_line in select * from jsonb_array_elements(p_lines)
    loop
        v_name  := btrim(coalesce(v_line ->> 'name', ''));
        v_qty   := coalesce((v_line ->> 'quantity')::numeric, 0);
        v_price := coalesce((v_line ->> 'unit_price')::numeric, 0);

        if v_qty <= 0 then
            raise exception 'Every line needs a quantity greater than zero';
        end if;

        v_product := nullif(v_line ->> 'product_id', '')::uuid;

        if v_product is null then
            if v_name = '' then
                raise exception 'Every line needs a product or a name';
            end if;
            v_product := ensure_product(p_org_id, v_name,
                                        p_sale_price => v_price,
                                        p_actor      => v_actor);
        end if;

        select name, cost_price into v_name, v_cost
        from products where id = v_product and org_id = p_org_id;

        if v_name is null then
            raise exception 'No such product in this business';
        end if;

        insert into sale_lines (sale_id, product_id, name, quantity,
                                unit_price, unit_cost, line_total)
        values (v_sale_id, v_product, v_name, v_qty, v_price,
                coalesce(v_cost, 0), v_qty * v_price);

        -- Stock can go negative. That is deliberate: refusing the sale
        -- because the count is wrong would make the count more important than
        -- the customer standing there, and the count is the thing more likely
        -- to be wrong. A credit sale moves the goods exactly like a cash one
        -- — the sack leaves with Awa either way.
        update products set quantity = quantity - v_qty where id = v_product;

        v_total := v_total + (v_qty * v_price);
    end loop;

    if v_total > 0 then
        if v_credit then
            -- Same customer matching as the carnet in 024: case-insensitive,
            -- trimmed, oldest first — "awa " is Awa.
            select id into v_customer
              from customers
             where org_id = p_org_id
               and lower(btrim(name)) = lower(v_cust_name)
             order by created_at
             limit 1;
            if v_customer is null then
                insert into customers (org_id, name, phone, created_by)
                values (p_org_id, v_cust_name,
                        nullif(btrim(coalesce(p_customer_phone, '')), ''),
                        v_actor)
                returning id into v_customer;
            end if;

            -- What was taken, in the carnet's own words: "2× Riz, 1× Huile".
            select string_agg(
                       format('%s× %s', trim_scale(l.quantity), l.name),
                       ', ' order by l.id)
              into v_label
              from sale_lines l where l.sale_id = v_sale_id;
            v_label := left(coalesce(v_label, 'Vente à crédit'), 200);

            -- The money lands in créances instead of the cash box; the
            -- income side is identical to a cash sale, so the résultat
            -- reads both the same.
            v_receivable := ensure_account_by_code(
                p_org_id, '1100', 'Créances clients', 'asset', v_actor);
            v_income := ensure_account(p_org_id, 'Ventes', 'income', v_actor);

            insert into journal_entries
                (org_id, memo, created_by, device_id, client_uuid, created_at)
            values
                (p_org_id, v_label || ' — crédit ' || v_cust_name, v_actor,
                 p_device_id, p_client_uuid, p_occurred_at)
            returning id into v_entry;

            insert into journal_lines (journal_entry_id, account_id, debit, credit)
            values (v_entry, v_receivable, v_total, 0),
                   (v_entry, v_income, 0, v_total);

            -- The debt the repayment flow from 024 already knows how to
            -- settle. No separate client_uuid: the sale's own idempotency
            -- guard above means this insert can only run once per uuid.
            insert into debts (org_id, customer_id, journal_entry_id, sale_id,
                               label, amount, occurred_at, created_by)
            values (p_org_id, v_customer, v_entry, v_sale_id,
                    v_label, v_total, p_occurred_at, v_actor);
        else
            v_entry := record_entry(
                p_org_id      => p_org_id,
                p_amount      => v_total,
                p_direction   => 'in',
                p_label       => 'Vente',
                p_recorded_by => v_actor,
                p_category    => 'Ventes',
                p_method      => p_method,
                p_memo        => p_note,
                p_details     => jsonb_build_object('sale_id', v_sale_id),
                p_client_uuid => p_client_uuid,
                p_device_id   => p_device_id,
                p_occurred_at => p_occurred_at
            );
        end if;
    end if;

    update sales set total = v_total, entry_id = v_entry where id = v_sale_id;

    return v_sale_id;
end;
$$;

-- Same body as 011 plus one guard: a return posts money out of a cash
-- account, which is false for a sale nobody has paid yet. The correction
-- path for credit is the carnet.
create or replace function record_return(
    p_sale_id     uuid,
    p_note        text default null,
    p_client_uuid uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor    uuid := auth.uid();
    v_org      uuid;
    v_method   text;
    v_total    numeric;
    v_kind     text;
    v_return   uuid;
    v_existing uuid;
    v_line     record;
    v_entry    uuid;
begin
    select org_id, method, total, kind
      into v_org, v_method, v_total, v_kind
    from sales where id = p_sale_id;

    if v_org is null then
        raise exception 'No such sale';
    end if;
    if v_kind = 'return' then
        raise exception 'That is already a return';
    end if;
    if v_method = 'credit' then
        raise exception 'A credit sale is settled in the carnet, not by a return';
    end if;
    if exists (select 1 from sales where reverses_id = p_sale_id) then
        raise exception 'That sale has already been returned';
    end if;

    if p_client_uuid is not null then
        select id into v_existing from sales
        where org_id = v_org and client_uuid = p_client_uuid;
        if v_existing is not null then
            return v_existing;
        end if;
    end if;

    insert into sales (org_id, kind, method, note, total, reverses_id,
                       recorded_by, client_uuid)
    values (v_org, 'return', v_method, p_note, v_total, p_sale_id,
            v_actor, p_client_uuid)
    returning id into v_return;

    for v_line in select * from sale_lines where sale_id = p_sale_id
    loop
        insert into sale_lines (sale_id, product_id, name, quantity,
                                unit_price, unit_cost, line_total)
        values (v_return, v_line.product_id, v_line.name, v_line.quantity,
                v_line.unit_price, v_line.unit_cost, v_line.line_total);

        update products set quantity = quantity + v_line.quantity
        where id = v_line.product_id;
    end loop;

    if v_total > 0 then
        v_entry := record_entry(
            p_org_id      => v_org,
            p_amount      => v_total,
            p_direction   => 'out',
            p_label       => 'Retour de vente',
            p_recorded_by => v_actor,
            p_category    => 'Ventes',
            p_method      => v_method,
            p_memo        => p_note,
            p_details     => jsonb_build_object('reverses', p_sale_id),
            p_client_uuid => p_client_uuid
        );
        update sales set entry_id = v_entry where id = v_return;
    end if;

    return v_return;
end;
$$;

-- ------------------------------------------------------------
-- GRANTS — the drop above took record_sale's grants with it.
-- ------------------------------------------------------------
revoke execute on function record_sale(uuid, jsonb, text, text, uuid, text, timestamptz, text, text) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function record_sale(uuid, jsonb, text, text, uuid, text, timestamptz, text, text) to authenticated;
        grant execute on function record_return(uuid, text, uuid) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
