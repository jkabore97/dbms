-- ============================================================
-- 150_farm_animal_sales.sql — animals sold once, counted once.
--
-- The owner: « Animal sales … will be connected to the stock and it will
-- avoid having two things being recorded at the same time. … we want to be
-- able to sell the same chicken and not create another chicken and forget
-- to remove it from the stock or from animal. »
--
-- Before this, a farm that sold ten chickens recorded it twice: a sale of
-- its « À vendre » article « Poulet de chair » at the till (money in, the
-- article's own stock down) and « Vendus vivants » on the batch (the head
-- count down, no money). Two records of one fact, and nothing to make them
-- agree — forget one and the books or the batch are wrong for good.
--
-- The design: ONE COUNT. An « À vendre » article may follow an animal group
-- — a flock (009) or a herd (019) — and its stock then IS that group's
-- number alive, kept equal in the same transaction by two triggers, so the
-- two can never drift:
--
--   * products.flock_id / products.herd_id (one of them, one article per
--     group). Linked, the article's quantity is the group's number alive
--     (0 once the group is closed); unlinked again, it goes to 0 — the
--     animals stay with their group, the article stops counting them.
--   * trg_stock_follows_animals (products, BEFORE): every path that moves
--     products.quantity — record_sale (011/029: the till, cash, mobile,
--     Wave, credit), the vitrine order accepted or cancelled (101/131),
--     record_return (146), a production's ingredient (026) — is caught
--     where the count is written, as 101 catches stock below zero. A fall
--     of n writes ONE 'sold' event of n on the group (flock_events, or
--     herd_events with herds.head_count down by n), tagged with the
--     article (product_id); more than are alive, or a closed group, is
--     refused with SQLSTATE MA001, so the till's outbox sets a sale kept
--     offline aside instead of retrying it for ever (101). A rise of n
--     (a return, a cancelled order) gives n back — a 'sold' event of -n —
--     never more than the article took. A hand on the count through the
--     API (current_user authenticated: the edit sheet, a stale form) moves
--     no animal: the count is put back to the group's. The flock keeps
--     009's semantics (bird_count arrived, never edited; alive = arrived
--     less mortality and sold), the herd 019's (head_count is the count).
--   * trg_animals_follow_group (flock_events, flocks, herds, AFTER): any
--     other change to the group — a death, a birth, a weighing corrected,
--     « Vendus vivants » without money, the group closed or reopened —
--     sets the article's count to the group's again.
--   The two speak through one transaction-local setting (kaj.animals),
--   so neither re-enters the other; it carries no power — in either mode
--   the count is recomputed from the group.
--
-- Selling a group that has no article yet (the till lists the farm's live
-- groups beside its articles, and « Vendus vivants » now takes the money):
--
--   sell_animals(org, lines, method, note, client_uuid, device_id,
--                occurred_at, customer_name, customer_phone, recorded_by)
--     record_sale's parameters (and p_recorded_by, so the outbox's generic
--     path sends it). A line is an article ({product_id, …}) or a group
--     ({flock_id | herd_id, quantity, unit_price}); a group without an
--     article gets one, created in the same transaction (named after the
--     batch, « par tête », price as sold, OFF the vitrine — P1 as 119: a
--     sale never puts an article in front of the street), and the sale is
--     then record_sale's, once: one sale, one journal entry, one 'sold'
--     event per group. Idempotent by p_client_uuid before anything is
--     written (the till's offline retry). SECURITY INVOKER on purpose,
--     like record_contribution and record_expense: it reads the groups
--     and creates the article under the caller's own RLS (members read,
--     can_write_org inserts), then hands the sale to record_sale — the
--     door every sale already goes through, DEFINER with its own
--     can_write_org check, as since 011. Bound, therefore, by exactly what
--     a sale at the till is bound by.
--   farm_animals_for_sale(org) — INVOKER: the open groups, how many are
--     alive, and the article that follows each (if any), for the till and
--     the « À vendre » sheet. Through flock_status (009: full visibility)
--     and herds (019: members). It is also how the app knows 150 is live.
--   link_product_animals(product, flock, herd) — INVOKER: link an article
--     to a group, or unlink it (both null). An UPDATE under the caller's
--     RLS (031: the 'products' dial at 'edit', as any article edit), the
--     group checked to be this business's and open, one article per group
--     said in French. Returns the article's new count.
--
-- Guards: a closed group sells nothing; more than alive is refused for a
-- flock and a herd alike — 009 and 019 already refuse it on the server;
-- the app keeps warning for a flock (its count may be days old on a phone)
-- and refusing for a herd, as « Mortalité » does. A delivery (stock
-- receipt) into an article that follows animals is refused: animals arrive
-- by « Ajouter des animaux », not as stock.
--
-- Corrections: a sale undone by a return gives the animals back (above). A
-- 'sold' event written by a sale cannot be edited as a farm entry
-- (update_flock_event, update_herd_event): its sale is corrected instead,
-- or the count and the money would part. AND A BUG FIXED ON THE WAY:
-- update_herd_event (033) changed a herd event's number and left
-- herds.head_count as it was — « 70 morts » corrected to « 7 » kept 63
-- animals out of the herd for good, and now the article that follows the
-- herd with them. It now moves head_count by the difference (refused below
-- zero), as 100 made update_flock_event hold the flock's rule.
--
-- Reports: nothing double. The sale is record_sale's (sales, sale_lines,
-- one journal entry: the income statement, the journal, 101's
-- farm_analytics, the reports of 149); the head count moves once (the
-- event); flock_status' « sold » is the net sold (a return's -n counts
-- back). herd_events.quantity may now be negative for 'sold' only (a
-- give-back); 019's check said >= 0.
--
-- Kinds: a farm only — flocks and herds exist nowhere else. A shop's or an
-- association's article has neither column set and every trigger here
-- returns at once for it: their till, returns, orders and vitrine behave
-- exactly as before.
--
-- Re-runnable (the bundle runs twice): columns and indexes if not exists,
-- constraints and triggers dropped and recreated, functions replaced in
-- place with their own signatures.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The link, and the tag on an event a sale wrote
-- ------------------------------------------------------------
alter table products add column if not exists flock_id uuid references flocks(id) on delete set null;
alter table products add column if not exists herd_id  uuid references herds(id)  on delete set null;

alter table products drop constraint if exists products_one_animal_group;
alter table products add constraint products_one_animal_group
    check (flock_id is null or herd_id is null);

-- One article per group: two would offer the same birds twice.
create unique index if not exists products_by_flock on products (flock_id) where flock_id is not null;
create unique index if not exists products_by_herd  on products (herd_id)  where herd_id  is not null;

comment on column products.flock_id is
    'The flock (009) this article follows (150): its quantity is the flock''s number alive, kept by trg_stock_follows_animals.';
comment on column products.herd_id is
    'The herd (019) this article follows (150): its quantity is herds.head_count, kept by trg_stock_follows_animals.';

alter table flock_events add column if not exists product_id uuid references products(id) on delete set null;
alter table herd_events  add column if not exists product_id uuid references products(id) on delete set null;

comment on column flock_events.product_id is
    'Set when the event was written by the article''s stock moving (150): a sale, a vitrine order, a return. Corrected through the sale, not as a farm entry.';
comment on column herd_events.product_id is
    'Set when the event was written by the article''s stock moving (150): a sale, a vitrine order, a return. Corrected through the sale, not as a farm entry.';

-- 127's guard: no reference may point into another business. The three
-- tables that gain one are guarded on every reference they now hold.
drop trigger if exists same_org on products;
create trigger same_org before insert or update on products
for each row execute function trg_same_org('flock_id:flocks', 'herd_id:herds');
drop trigger if exists same_org on flock_events;
create trigger same_org before insert or update on flock_events
for each row execute function trg_same_org('flock_id:flocks', 'product_id:products');
drop trigger if exists same_org on herd_events;
create trigger same_org before insert or update on herd_events
for each row execute function trg_same_org('herd_id:herds', 'product_id:products');

-- A return gives animals back as a 'sold' of -n (the net stays the truth
-- every reader already sums); 019 allowed no negative number.
alter table herd_events drop constraint if exists herd_events_quantity_check;
alter table herd_events add constraint herd_events_quantity_check
    check (quantity >= 0 or kind = 'sold');

-- ------------------------------------------------------------
-- 2. How many a group has to sell
-- ------------------------------------------------------------
-- Alive (009's arithmetic for a flock, 019's head_count for a herd), and
-- nothing once the group is closed. Internal: called by the triggers.
create or replace function animal_group_alive(p_flock_id uuid, p_herd_id uuid)
returns numeric
language sql
stable
set search_path = public
as $$
    select case
        when p_flock_id is not null then (
            select case when f.closed_on is not null then 0
                        else greatest(f.bird_count - coalesce((
                                 select sum(e.quantity) from flock_events e
                                  where e.flock_id = f.id
                                    and e.kind in ('mortality', 'sold')), 0), 0) end
              from flocks f where f.id = p_flock_id)
        when p_herd_id is not null then (
            select case when h.closed_on is not null then 0
                        else greatest(h.head_count, 0) end
              from herds h where h.id = p_herd_id)
    end;
$$;

-- ------------------------------------------------------------
-- 3. The article's count is the group's
-- ------------------------------------------------------------
-- Who is writing: a definer trigger sees its owner as current_user, so
-- this one is INVOKER on purpose (as 101's trg_sale_order_by_trigger): it
-- says, for the row about to be written, whether the hand is the API's
-- (authenticated, anon — the edit sheet, a stale form) or a function's
-- (record_sale, the orders trigger, a return: the table owner). Set fresh
-- for every row, before the trigger below reads it, so it cannot be
-- forged by setting it earlier.
create or replace function trg_stock_animals_hand()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
    perform set_config('kaj.animals_hand',
        case when current_user in ('authenticated', 'anon') then 'on' else '' end, true);
    return new;
end;
$$;

-- Fires first (« stock_a… » before « stock_f… »), after service_no_stock.
drop trigger if exists stock_animals_hand on products;
create trigger stock_animals_hand
before insert or update of quantity, flock_id, herd_id, stock_tracked, is_service on products
for each row
when (new.flock_id is not null or new.herd_id is not null)
execute function trg_stock_animals_hand();

-- Named to fire after service_no_stock (098/131) and before
-- stock_not_below_zero (101): BEFORE triggers run in name order.
create or replace function trg_stock_follows_animals()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_mode    text := coalesce(current_setting('kaj.animals', true), '');
    v_relink  boolean;
    v_org     uuid;
    v_closed  date;
    v_label   text;
    v_alive   numeric;
    v_delta   numeric;
    v_took    numeric;
    v_actor   uuid;
begin
    -- Not (or no longer) following animals.
    if new.flock_id is null and new.herd_id is null then
        if tg_op = 'UPDATE' and (old.flock_id is not null or old.herd_id is not null) then
            -- Unlinked: the animals stay with their group; this article no
            -- longer counts them, so it has none of its own.
            new.quantity := 0;
        end if;
        return new;
    end if;

    if new.is_service then
        raise exception 'Un service ne peut pas suivre des animaux';
    end if;
    if not coalesce(new.stock_tracked, true) then
        raise exception '« % » suit des animaux : son stock est toujours suivi', new.name;
    end if;

    -- The group, locked: two phones selling the last birds wait in turn.
    if new.flock_id is not null then
        select f.org_id, f.closed_on, f.batch_code into v_org, v_closed, v_label
          from flocks f where f.id = new.flock_id for update;
    else
        select h.org_id, h.closed_on, h.label into v_org, v_closed, v_label
          from herds h where h.id = new.herd_id for update;
    end if;
    if v_org is distinct from new.org_id then
        raise exception 'Ces animaux ne sont pas à cette entreprise';
    end if;
    v_alive := coalesce(animal_group_alive(new.flock_id, new.herd_id), 0);

    v_relink := tg_op = 'INSERT'
             or new.flock_id is distinct from old.flock_id
             or new.herd_id  is distinct from old.herd_id;

    -- Linked just now, the group moved (trg_animals_follow_group), or a
    -- hand on the count through the API: the count is the group's, and no
    -- animal moves.
    if v_relink or v_mode = 'group'
       or coalesce(current_setting('kaj.animals_hand', true), '') = 'on' then
        new.quantity := v_alive;
        return new;
    end if;

    v_delta := new.quantity - old.quantity;
    if v_delta = 0 then
        new.quantity := v_alive;
        return new;
    end if;

    if v_delta < 0 then
        if v_closed is not null then
            raise exception using
                message = format('« %s » est clôturé : ces animaux ne se vendent plus', v_label),
                errcode = 'MA001';
        end if;
        if -v_delta > v_alive then
            raise exception using message = stock_short_message(new.name, v_alive),
                                  errcode = 'MA001';
        end if;
    else
        -- Given back: never more than this article took. A return or a
        -- cancelled order is never refused for it (an order accepted
        -- before the article followed the group gave nothing to the group
        -- and gets nothing from it); what is beyond is simply not added —
        -- animals arrive by « Ajouter des animaux », and a delivery is
        -- refused below (trg_receipt_not_animals).
        if new.flock_id is not null then
            select coalesce(sum(quantity), 0) into v_took
              from flock_events where product_id = new.id and kind = 'sold';
        else
            select coalesce(sum(quantity), 0) into v_took
              from herd_events where product_id = new.id and kind = 'sold';
        end if;
        v_delta := least(v_delta, greatest(v_took, 0));
        if v_delta <= 0 then
            new.quantity := v_alive;
            return new;
        end if;
    end if;

    -- Who: the seller; a courier closing at the door (073) is a profile
    -- too; a write with nobody signed in falls back to the owner.
    v_actor := coalesce(auth.uid(),
                        (select m.user_id from memberships m
                          where m.org_id = new.org_id and m.role = 'owner'
                          order by m.created_at limit 1));

    perform set_config('kaj.animals', 'product', true);
    if new.flock_id is not null then
        insert into flock_events (flock_id, kind, quantity, note, occurred_at,
                                  created_by, product_id)
        values (new.flock_id, 'sold', -v_delta,
                case when v_delta < 0 then 'Vente — ' else 'Rendus — ' end || new.name,
                now(), v_actor, new.id);
    else
        insert into herd_events (org_id, herd_id, kind, occurred_on, quantity,
                                 note, created_by, product_id)
        values (new.org_id, new.herd_id, 'sold',
                (now() at time zone 'Africa/Ouagadougou')::date, -v_delta,
                case when v_delta < 0 then 'Vente — ' else 'Rendus — ' end || new.name,
                v_actor, new.id);
        update herds set head_count = head_count + v_delta where id = new.herd_id;
    end if;
    perform set_config('kaj.animals', '', true);

    new.quantity := coalesce(animal_group_alive(new.flock_id, new.herd_id), 0);
    return new;
end;
$$;

drop trigger if exists stock_follows_animals on products;
create trigger stock_follows_animals
before insert or update of quantity, flock_id, herd_id, stock_tracked, is_service on products
for each row execute function trg_stock_follows_animals();

-- ------------------------------------------------------------
-- 4. The group's count is the article's
-- ------------------------------------------------------------
create or replace function trg_animals_follow_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_flock uuid;
    v_herd  uuid;
begin
    -- Written by the article itself (above): it has set its own count.
    if coalesce(current_setting('kaj.animals', true), '') = 'product' then
        return null;
    end if;
    if tg_table_name = 'flock_events' then
        v_flock := case when tg_op = 'DELETE' then old.flock_id else new.flock_id end;
    elsif tg_table_name = 'flocks' then
        v_flock := new.id;
    else
        v_herd := new.id;
    end if;
    if not exists (select 1 from products
                    where (v_flock is not null and flock_id = v_flock)
                       or (v_herd is not null and herd_id = v_herd)) then
        return null;
    end if;
    perform set_config('kaj.animals', 'group', true);
    -- The value is recomputed by trg_stock_follows_animals.
    update products set quantity = quantity
     where (v_flock is not null and flock_id = v_flock)
        or (v_herd is not null and herd_id = v_herd);
    perform set_config('kaj.animals', '', true);
    return null;
end;
$$;

drop trigger if exists animals_follow_group on flock_events;
create trigger animals_follow_group
after insert or update or delete on flock_events
for each row execute function trg_animals_follow_group();

drop trigger if exists animals_follow_group on flocks;
create trigger animals_follow_group
after update of bird_count, closed_on on flocks
for each row execute function trg_animals_follow_group();

drop trigger if exists animals_follow_group on herds;
create trigger animals_follow_group
after update of head_count, closed_on on herds
for each row execute function trg_animals_follow_group();

-- Animals are not delivered as stock: they arrive by « Ajouter des
-- animaux ». (receive_products, 016/032; a delivery reversed is a fall and
-- is caught above.)
create or replace function trg_receipt_not_animals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_name text;
begin
    select name into v_name from products
     where id = new.product_id and (flock_id is not null or herd_id is not null);
    if found then
        raise exception '« % » suit des animaux : ils s''ajoutent depuis « Ajouter des animaux », pas comme une livraison', v_name;
    end if;
    return new;
end;
$$;

drop trigger if exists receipt_not_animals on stock_receipts;
create trigger receipt_not_animals
before insert on stock_receipts
for each row execute function trg_receipt_not_animals();

-- ------------------------------------------------------------
-- 5. Correcting a farm entry: a sale's event is the sale's
-- ------------------------------------------------------------
-- 100's update_flock_event, one refusal added.
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
    v_org   uuid;
    v_flock uuid;
    v_ev    flock_events%rowtype;
    v_kind  text;
    v_qty   numeric;
    v_alive numeric;
begin
    if auth.uid() is null then
        raise exception 'update_flock_event() needs a signed-in caller';
    end if;

    select e.* into v_ev from flock_events e where e.id = p_event_id;
    select f.org_id, f.id into v_org, v_flock from flocks f where f.id = v_ev.flock_id;

    if v_org is null then
        raise exception 'No such flock event';
    end if;
    if not can_write_org(v_org) then
        raise exception 'You cannot correct entries for this business';
    end if;
    -- 150: written by a sale — the sale is what is corrected.
    if v_ev.product_id is not null then
        raise exception 'Ce mouvement vient d''une vente : corrigez la vente elle-même (Corrections)';
    end if;
    if p_quantity is not null and p_quantity < 0 then
        raise exception 'A count cannot be negative (got %)', p_quantity;
    end if;

    v_kind := coalesce(nullif(btrim(coalesce(p_kind, '')), ''), v_ev.kind);
    v_qty  := coalesce(p_quantity, v_ev.quantity);
    if v_kind in ('mortality', 'sold') then
        select f.bird_count - coalesce(sum(e.quantity) filter (
                   where e.kind in ('mortality', 'sold') and e.id <> p_event_id), 0)
          into v_alive
          from flocks f
          left join flock_events e on e.flock_id = f.id
         where f.id = v_flock
         group by f.bird_count;
        if v_qty > v_alive then
            raise exception
                'Only % birds left in this flock, cannot record % as %',
                v_alive, v_qty, v_kind;
        end if;
    end if;

    update flock_events set
        quantity    = v_qty,
        kind        = v_kind,
        note        = coalesce(p_note, note),
        occurred_at = coalesce(p_occurred_at, occurred_at)
    where id = p_event_id;

    return p_event_id;
end;
$$;

-- 033's update_herd_event: the sale's refusal, and head_count moved by the
-- difference the correction makes (the bug above).
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
    v_ev   herd_events%rowtype;
    v_kind text;
    v_qty  numeric;
    v_was  numeric;
    v_now  numeric;
    v_head int;
begin
    if auth.uid() is null then
        raise exception 'update_herd_event() needs a signed-in caller';
    end if;

    select * into v_ev from herd_events where id = p_event_id;

    if v_ev.id is null then
        raise exception 'No such herd event';
    end if;
    if not can_write_org(v_ev.org_id) then
        raise exception 'You cannot correct entries for this business';
    end if;
    if v_ev.product_id is not null then
        raise exception 'Ce mouvement vient d''une vente : corrigez la vente elle-même (Corrections)';
    end if;
    if p_quantity is not null and p_quantity < 0 then
        raise exception 'A count cannot be negative (got %)', p_quantity;
    end if;

    v_kind := coalesce(nullif(btrim(coalesce(p_kind, '')), ''), v_ev.kind);
    if v_kind not in ('mortality', 'birth', 'weight', 'vaccination', 'treatment', 'sold') then
        raise exception 'Unknown event: %', v_kind;
    end if;
    v_qty := coalesce(p_quantity, v_ev.quantity);

    -- What each version does to the head count: a death or a sale takes,
    -- a birth adds, the rest do nothing.
    v_was := case when v_ev.kind in ('mortality', 'sold') then -v_ev.quantity
                  when v_ev.kind = 'birth' then v_ev.quantity else 0 end;
    v_now := case when v_kind in ('mortality', 'sold') then -v_qty
                  when v_kind = 'birth' then v_qty else 0 end;

    select head_count into v_head from herds where id = v_ev.herd_id for update;
    if v_head + v_now - v_was < 0 then
        raise exception 'There are only % animals in this group', trim_scale(v_head - v_was);
    end if;

    update herd_events set
        quantity    = v_qty,
        kind        = v_kind,
        note        = coalesce(p_note, note),
        occurred_on = coalesce(p_occurred_on, occurred_on)
    where id = p_event_id;

    if v_now <> v_was then
        update herds set head_count = head_count + (v_now - v_was)
         where id = v_ev.herd_id;
    end if;

    return p_event_id;
end;
$$;

-- ------------------------------------------------------------
-- 6. Selling animals: one sale, one count
-- ------------------------------------------------------------
create or replace function sell_animals(
    p_org_id         uuid,
    p_lines          jsonb,
    p_method         text        default 'cash',
    p_note           text        default null,
    p_client_uuid    uuid        default null,
    p_device_id      text        default null,
    p_occurred_at    timestamptz default now(),
    p_customer_name  text        default null,
    p_customer_phone text        default null,
    p_recorded_by    uuid        default null
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
    v_actor   uuid := auth.uid();
    v_line    jsonb;
    v_out     jsonb := '[]'::jsonb;
    v_flock   uuid;
    v_herd    uuid;
    v_label   text;
    v_detail  text;
    v_closed  date;
    v_product uuid;
    v_name    text;
    v_price   numeric;
    v_existing uuid;
begin
    if v_actor is null then
        raise exception 'sell_animals() needs a signed-in caller';
    end if;
    if p_recorded_by is not null and p_recorded_by <> v_actor then
        raise exception 'sell_animals() cannot record on behalf of another user';
    end if;
    if not can_write_org(p_org_id) then
        raise exception 'You cannot record sales for this business';
    end if;
    if p_lines is null or jsonb_typeof(p_lines) <> 'array'
       or jsonb_array_length(p_lines) = 0 then
        raise exception 'A sale needs at least one line';
    end if;

    -- A retried sale (the till's outbox) returns the first one, before
    -- anything is written.
    if p_client_uuid is not null then
        select id into v_existing from sales
         where org_id = p_org_id and client_uuid = p_client_uuid;
        if v_existing is not null then
            return v_existing;
        end if;
    end if;

    for v_line in select * from jsonb_array_elements(p_lines) loop
        v_flock := nullif(v_line ->> 'flock_id', '')::uuid;
        v_herd  := nullif(v_line ->> 'herd_id', '')::uuid;
        if v_flock is null and v_herd is null then
            v_out := v_out || jsonb_build_array(v_line);
            continue;
        end if;
        if v_flock is not null and v_herd is not null then
            raise exception 'A line sells one group of animals';
        end if;

        v_label := null;
        if v_flock is not null then
            select batch_code, nullif(btrim(coalesce(breed, '')), ''), closed_on
              into v_label, v_detail, v_closed
              from flocks where id = v_flock and org_id = p_org_id;
        else
            select label, nullif(btrim(coalesce(species, '')), ''), closed_on
              into v_label, v_detail, v_closed
              from herds where id = v_herd and org_id = p_org_id;
        end if;
        if v_label is null then
            raise exception 'Ces animaux ne sont pas dans cette ferme';
        end if;
        if v_closed is not null then
            raise exception using
                message = format('« %s » est clôturé : ces animaux ne se vendent plus', v_label),
                errcode = 'MA001';
        end if;

        select id, name into v_product, v_name from products
         where (v_flock is not null and flock_id = v_flock)
            or (v_herd is not null and herd_id = v_herd);

        if v_product is null then
            -- The batch's article: « Poulets de chair — B-2026-07 », a
            -- herd by its own name; another article's name is never taken.
            v_name := case when v_flock is not null and v_detail is not null
                           then v_detail || ' — ' || v_label
                           else v_label end;
            if exists (select 1 from products
                        where org_id = p_org_id
                          and lower(btrim(name)) = lower(btrim(v_name))) then
                v_name := v_name || ' (' || coalesce(v_detail, case when v_flock is not null then 'bande' else 'groupe' end) || ')';
            end if;
            v_price := greatest(coalesce((v_line ->> 'unit_price')::numeric, 0), 0);
            insert into products (org_id, name, sale_price, cost_price, quantity,
                                  unit, is_published, created_by, flock_id, herd_id)
            values (p_org_id, v_name, v_price, 0, 0, 'tête', false, v_actor,
                    v_flock, v_herd)
            on conflict do nothing
            returning id into v_product;
            -- Another phone made it in the meantime: theirs.
            if v_product is null then
                select id, name into v_product, v_name from products
                 where (v_flock is not null and flock_id = v_flock)
                    or (v_herd is not null and herd_id = v_herd);
            end if;
        end if;

        v_out := v_out || jsonb_build_array(jsonb_build_object(
            'product_id', v_product,
            'name',       v_name,
            'quantity',   v_line -> 'quantity',
            'unit_price', v_line -> 'unit_price'));
    end loop;

    return record_sale(p_org_id, v_out, p_method, p_note, p_client_uuid,
                       p_device_id, p_occurred_at, p_customer_name,
                       p_customer_phone);
end;
$$;

-- The open groups and how many each has to sell, with the article that
-- follows it — the till's list and the « À vendre » sheet's choice.
create or replace function farm_animals_for_sale(p_org_id uuid)
returns table (
    kind         text,
    group_id     uuid,
    label        text,
    detail       text,
    alive        int,
    product_id   uuid,
    product_name text,
    sale_price   numeric,
    unit         text
)
language sql
stable
security invoker
set search_path = public
as $$
    select * from (
        select 'flock'::text, fs.flock_id, fs.batch_code, fs.breed, fs.alive,
               p.id, p.name, p.sale_price, p.unit
          from flock_status(p_org_id) fs
          left join products p on p.flock_id = fs.flock_id
         where fs.closed_on is null
        union all
        select 'herd'::text, h.id, h.label, h.species, h.head_count,
               p.id, p.name, p.sale_price, p.unit
          from herds h
          left join products p on p.herd_id = h.id
         where h.org_id = p_org_id and h.closed_on is null
    ) g
    order by 1, 3;
$$;

-- « Suit des animaux » on an article: link (one group) or unlink (none).
create or replace function link_product_animals(
    p_product_id uuid,
    p_flock_id   uuid default null,
    p_herd_id    uuid default null
)
returns numeric
language plpgsql
security invoker
set search_path = public
as $$
declare
    v_org    uuid;
    v_label  text;
    v_closed date;
    v_other  text;
    v_qty    numeric;
begin
    if auth.uid() is null then
        raise exception 'link_product_animals() needs a signed-in caller';
    end if;
    if p_flock_id is not null and p_herd_id is not null then
        raise exception 'Un article suit une seule bande ou un seul groupe';
    end if;
    select org_id into v_org from products where id = p_product_id;
    if v_org is null then
        raise exception 'No such article';
    end if;

    if p_flock_id is not null then
        select batch_code, closed_on into v_label, v_closed
          from flocks where id = p_flock_id and org_id = v_org;
        select name into v_other from products
         where flock_id = p_flock_id and id <> p_product_id;
    elsif p_herd_id is not null then
        select label, closed_on into v_label, v_closed
          from herds where id = p_herd_id and org_id = v_org;
        select name into v_other from products
         where herd_id = p_herd_id and id <> p_product_id;
    end if;
    if (p_flock_id is not null or p_herd_id is not null) then
        if v_label is null then
            raise exception 'Ces animaux ne sont pas dans cette ferme';
        end if;
        if v_closed is not null then
            raise exception '« % » est clôturé : ces animaux ne se vendent plus', v_label;
        end if;
        if v_other is not null then
            raise exception '« % » est déjà suivi par l''article « % »', v_label, v_other;
        end if;
    end if;

    update products set flock_id = p_flock_id, herd_id = p_herd_id
     where id = p_product_id
    returning quantity into v_qty;
    if not found then
        raise exception 'Vous ne pouvez pas modifier les articles de cette entreprise';
    end if;
    return v_qty;
end;
$$;

-- ------------------------------------------------------------
-- 7. Grants (063: born closed to anon and PUBLIC; Supabase hands new
-- functions to authenticated, which the internal ones must not keep)
-- ------------------------------------------------------------
revoke execute on function animal_group_alive(uuid, uuid)       from public;
revoke execute on function trg_stock_animals_hand()             from public;
revoke execute on function trg_stock_follows_animals()          from public;
revoke execute on function trg_animals_follow_group()           from public;
revoke execute on function trg_receipt_not_animals()            from public;
revoke execute on function sell_animals(uuid, jsonb, text, text, uuid, text, timestamptz, text, text, uuid) from public;
revoke execute on function farm_animals_for_sale(uuid)          from public;
revoke execute on function link_product_animals(uuid, uuid, uuid) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function animal_group_alive(uuid, uuid)       from anon;
        revoke execute on function trg_stock_animals_hand()             from anon;
        revoke execute on function trg_stock_follows_animals()          from anon;
        revoke execute on function trg_animals_follow_group()           from anon;
        revoke execute on function trg_receipt_not_animals()            from anon;
        revoke execute on function sell_animals(uuid, jsonb, text, text, uuid, text, timestamptz, text, text, uuid) from anon;
        revoke execute on function farm_animals_for_sale(uuid)          from anon;
        revoke execute on function link_product_animals(uuid, uuid, uuid) from anon;
        revoke execute on function update_flock_event(uuid, numeric, text, text, timestamptz) from anon;
        revoke execute on function update_herd_event(uuid, numeric, text, text, date) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function animal_group_alive(uuid, uuid)       from authenticated;
        revoke execute on function trg_stock_animals_hand()             from authenticated;
        revoke execute on function trg_stock_follows_animals()          from authenticated;
        revoke execute on function trg_animals_follow_group()           from authenticated;
        revoke execute on function trg_receipt_not_animals()            from authenticated;
        grant execute on function sell_animals(uuid, jsonb, text, text, uuid, text, timestamptz, text, text, uuid) to authenticated;
        grant execute on function farm_animals_for_sale(uuid)          to authenticated;
        grant execute on function link_product_animals(uuid, uuid, uuid) to authenticated;
        grant execute on function update_flock_event(uuid, numeric, text, text, timestamptz) to authenticated;
        grant execute on function update_herd_event(uuid, numeric, text, text, date) to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function sell_animals(uuid, jsonb, text, text, uuid, text, timestamptz, text, text, uuid) to service_role;
        grant execute on function farm_animals_for_sale(uuid)          to service_role;
        grant execute on function link_product_animals(uuid, uuid, uuid) to service_role;
    end if;
end $$;

notify pgrst, 'reload schema';
