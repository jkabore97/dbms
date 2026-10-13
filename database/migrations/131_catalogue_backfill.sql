-- ============================================================
-- 131_catalogue_backfill.sql — batch 134: the folded bars' database side,
-- an association's Catalogue, « Vous êtes ici pour… », and the existing
-- businesses given what a new one gets.
--
--   1. An association's Catalogue (the owner: « associations need items
--      and service in their catalog. Not very similar to the shop »).
--      Nothing in the database ever stopped an association's articles:
--      products' row security is the business's members' (is_org_member,
--      can_write_org, feature_access 'products'), ensure_product and
--      place_order ask no kind, storefront_products shows every published
--      article (vitrine_shows: only Mara's switchboard hides), an order
--      collected books its sale on « Ventes » through ensure_account —
--      made the first time, an association's books included — and its
--      vitrine opens from one item (vitrine_min). What was missing was the
--      app's door (a tab) and one count: home_counts said « articles »
--      (at zero, or under their alert level) for a shop and a farm only.
--      It now says it for an association too — Catalogue's red number.
--      The rest of the counts are unchanged, for every kind.
--
--   2. « Vous êtes ici pour… » — one question after sign-up (Acheter /
--      Vendre ou gérer / Livrer / Je choisirai plus tard), asked once per
--      account and never of somebody who already has a business.
--      profiles.arrival_asked_at (when it was answered) and
--      profiles.arrival_intent ('buy', 'sell', 'deliver', 'later').
--        * arrival_pending(): true for a signed-in account that has no
--          answer yet, belongs to no business and is not Mara's own —
--          false for everybody else, a stranger included;
--        * arrival_answer(intent): the answer, for the caller's own
--          account only; the first answer's time is kept (asked once).
--      Both SECURITY DEFINER with a pinned search path — they touch only
--      auth.uid()'s own row, and a profile's new columns are given to
--      nobody directly — closed to PUBLIC and anon (063), open to
--      authenticated. An app with no 131 behind it asks nothing: the call
--      fails, the question is not shown.
--
--   3. The backfill (the owner: « if you find a business, an association
--      or a farm that do not have a feature that all new businesses are
--      supposed to have, just apply that to them directly »). What a new
--      business gets — org_create_core: its owner and its kind's chart of
--      accounts (seed_retail_accounts, seed_farm_accounts,
--      seed_church_accounts); over time: Le Chemin's steps reached
--      (path_sync, run by the triggers on what the business does) — was
--      compared with the live businesses (read only, October 12):
--        * the chart of accounts: every live business has its kind's
--          full seed (retail 8 codes, farm 16, association 14) — 0 rows
--          to add; the step below is kept, idempotent, for any database
--          that is behind (insert … on conflict do nothing: an account
--          the owner renamed or switched off — is_active = false — keeps
--          its code, so it is never touched);
--        * Le Chemin: one step reached and never marked (a shop whose
--          articles passed the goal before anything triggered path_sync
--          again): path_sync, for every live shop and farm. It marks what
--          is reached and pays the step's cauris once (on conflict do
--          nothing), exactly as the next sale would have; a step not
--          reached stays open. Associations have no Chemin (097).
--      Not touched, on purpose:
--        * showcase businesses (094): Mara's examples, not anybody's;
--        * orgs.progress_since NULL on the businesses from before 085:
--          that is « on the street » — they keep every tool they had —
--          not a missing feature; filling it would lock them;
--        * orgs.storefront_enabled false, orgs.association_kind NULL: an
--          owner's choice cannot be told from « never had it » there, so
--          nothing is decided for them;
--        * the owners' dial (org_feature_rules) and Mara's switchboard
--          (feature_rules): choices, never filled in.
--
-- Shop, farm and association (CLAUDE.md):
--   * shop: home_counts unchanged; the backfill's chart (none missing)
--     and Le Chemin (one step);
--   * farm: home_counts unchanged; the chart (none missing) and Le Chemin;
--   * association: home_counts counts its articles; the chart (none
--     missing); no Chemin;
--   * everybody without a business: the question, once.
-- Re-runnable: create or replace, add column if not exists, the backfill
-- idempotent.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Catalogue's red number for an association too
-- ------------------------------------------------------------
create or replace function home_counts(p_org uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
    v_kind      text;
    v_orders    int := 0;
    v_bookings  int := 0;
    v_articles  int := 0;
    v_invoices  int := 0;
    v_credit    int := 0;
    v_invites   int := 0;
    v_supplies  int := 0;
    v_livestock int := 0;
begin
    if p_org is null or not is_org_member(p_org) then
        return null;
    end if;
    select profile into v_kind from orgs where id = p_org;

    -- Orders not answered yet; a basket of services only is a booking.
    select count(*) filter (where not x.booking), count(*) filter (where x.booking)
      into v_orders, v_bookings
      from (select exists (select 1 from order_lines l where l.order_id = o.id)
                   and not exists (select 1 from order_lines l
                                    where l.order_id = o.id and not l.is_service) as booking
              from orders o
             where o.org_id = p_org and o.status = 'pending'
               and o.proposed_for is null) x;

    -- 131: an association's articles (its Catalogue) are counted too.
    if v_kind in ('retail', 'farm', 'association', 'church') then
        select count(*) into v_articles
          from products p
         where p.org_id = p_org and p.is_active and not p.is_service
           and (p.quantity <= 0 or (p.low_stock_at is not null and p.quantity <= p.low_stock_at));
    end if;

    select count(*) into v_invoices
      from invoices i
     where i.org_id = p_org and i.cancelled_at is null
       and i.due_on is not null and i.due_on < current_date
       and i.total > coalesce((select sum(ip.amount) from invoice_payments ip
                                where ip.invoice_id = i.id), 0);

    -- A due date on a credit is 117's; before it, nothing is « overdue ».
    if exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'debts'
                  and column_name = 'due_on') then
        execute 'select count(*) from debts d
                  where d.org_id = $1 and d.due_on < current_date
                    and d.amount > coalesce((select sum(dp.amount) from debt_payments dp
                                              where dp.debt_id = d.id), 0)'
           into v_credit using p_org;
    end if;

    select count(*) into v_invites
      from pending_invitations pi
     where pi.org_id = p_org and pi.claimed_at is null and pi.expires_at > now();

    if v_kind = 'farm' then
        select count(*) into v_supplies from stock_on_hand(p_org) s where s.below_reorder;
        select count(*) into v_livestock
          from flocks f
         where f.org_id = p_org and f.closed_on is null
           and not exists (select 1 from flock_events e
                            where e.flock_id = f.id and e.occurred_at >= current_date)
           and not exists (select 1 from egg_production g
                            where g.flock_id = f.id and g.produced_on = current_date);
    end if;

    return jsonb_build_object(
        'orders', v_orders, 'bookings', v_bookings, 'articles', v_articles,
        'invoices', v_invoices, 'credit', v_credit, 'invitations', v_invites,
        'supplies', v_supplies, 'livestock', v_livestock);
end;
$$;

-- ------------------------------------------------------------
-- 2. « Vous êtes ici pour… », once per account
-- ------------------------------------------------------------
alter table profiles add column if not exists arrival_asked_at timestamptz;
alter table profiles add column if not exists arrival_intent text;

do $$ begin
    if not exists (select 1 from pg_constraint
                    where conname = 'profiles_arrival_intent_check') then
        alter table profiles add constraint profiles_arrival_intent_check
            check (arrival_intent is null
                   or arrival_intent in ('buy', 'sell', 'deliver', 'later'));
    end if;
end $$;

create or replace function arrival_pending()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select auth.uid() is not null
       and exists (select 1 from profiles p
                    where p.id = auth.uid()
                      and p.arrival_asked_at is null
                      and not coalesce(p.is_platform_admin, false))
       and not exists (select 1 from memberships m where m.user_id = auth.uid());
$$;

create or replace function arrival_answer(p_intent text)
returns void
language plpgsql
volatile
security definer
set search_path = public, auth
as $$
declare
    v_intent text := lower(btrim(coalesce(p_intent, '')));
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord.';
    end if;
    if v_intent not in ('buy', 'sell', 'deliver', 'later') then
        raise exception 'Réponse inconnue : %', p_intent;
    end if;
    update profiles
       set arrival_intent   = v_intent,
           arrival_asked_at = coalesce(arrival_asked_at, now())
     where id = auth.uid();
end;
$$;

revoke execute on function arrival_pending()     from public;
revoke execute on function arrival_answer(text)  from public;
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function arrival_pending()    from anon;
        revoke execute on function arrival_answer(text) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function arrival_pending()    to authenticated;
        grant execute on function arrival_answer(text) to authenticated;
    end if;
end $$;

-- ------------------------------------------------------------
-- 3. The backfill: what every new business gets, for the old ones
-- ------------------------------------------------------------
do $$
declare
    o record;
begin
    -- The kind's chart of accounts: a missing code only (never had it).
    for o in
        select id, profile::text as kind from orgs where not showcase
    loop
        if o.kind in ('association', 'church') then
            perform seed_church_accounts(o.id);
        elsif o.kind = 'retail' then
            perform seed_retail_accounts(o.id);
        elsif o.kind = 'farm' then
            perform seed_farm_accounts(o.id);
        end if;
    end loop;

    -- Le Chemin's steps reached and never marked (097), shops and farms
    -- open today. Best-effort per business, as the triggers run it.
    for o in
        select id from orgs
         where not showcase and archived_at is null
           and profile::text in ('retail', 'farm')
    loop
        begin
            perform path_sync(o.id);
        exception when others then
            raise notice '131: Le Chemin not synced for % (%)', o.id, sqlerrm;
        end;
    end loop;
end $$;
