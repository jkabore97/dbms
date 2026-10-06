-- ============================================================
-- 090_cash_only.sql — cash for now; Wave when Mara allows it.
--
-- The owner: « Remove Wave configuration for now. Every order will be cash
-- payment for now. Enable admin to authorise that later. » Wave stays in
-- the code (076) but every business is closed to it until a platform admin
-- ticks orgs.wave_allowed for it:
--
--   * a vitrine order paid by Wave is refused (an order trigger), and the
--     vitrine stops offering it — storefront() keeps wave_merchant back;
--   * Wave checkout for an order needs the tick as well as Pro (081/085);
--   * wave_terms() says the shop is not ready;
--   * feature_states() carries the tick, so the app hides the Wave
--     settings and the till's Wave button.
--
-- Mara Pro and the spots are paid to Mara, not to the shop: not touched
-- here. No destructive statement: a column added, functions replaced in
-- place with their own signatures, a trigger created where missing.
-- ============================================================

alter table orgs add column if not exists wave_allowed boolean not null default false;

create or replace function set_org_wave_allowed(p_org_id uuid, p_allowed boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Seul Mara autorise Wave';
    end if;
    update orgs set wave_allowed = coalesce(p_allowed, false) where id = p_org_id;
    if not found then
        raise exception 'No such business';
    end if;
end;
$$;

-- A vitrine order paid by Wave, refused until Mara allows it.
create or replace function trg_order_cash_only()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.payment_method = 'wave'
       and not coalesce((select wave_allowed from orgs where id = new.org_id), false) then
        raise exception 'Paiement en espèces uniquement pour le moment.';
    end if;
    return new;
end;
$$;

do $$
begin
    if not exists (select 1 from pg_trigger where tgname = 'order_cash_only') then
        create trigger order_cash_only before insert on orders
            for each row execute function trg_order_cash_only();
    end if;
end $$;

-- 085's online-payment door, now also behind Mara's tick.
create or replace function trg_wave_order_pro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.kind = 'order' and not coalesce((select wave_allowed from orgs where id = new.org_id), false) then
        raise exception 'Paiement en espèces uniquement pour le moment.';
    end if;
    if new.kind = 'order' and not org_has(new.org_id, 'online_payment') then
        raise exception 'Kaj Pro : le paiement en ligne est réservé aux boutiques Kaj Pro';
    end if;
    return new;
end;
$$;

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
            select 1 from orgs where id = p_org_id and wave_payout_number is not null
               and wave_allowed and org_has(id, 'online_payment')),
        'card', coalesce((select (value #>> '{}')::boolean
                            from platform_settings where key = 'wave_card'), false),
        'commission_pct', coalesce((select (value #>> '{}')::numeric
                                      from platform_settings where key = 'wave_commission_pct'), 0)
    );
$$;

-- 086's window, keeping the Wave number back until Mara allows it.
create or replace function storefront(p_slug text)
returns table (
    org_id        uuid,
    name          text,
    slug          text,
    profile       text,
    blurb         text,
    phone         text,
    address       text,
    theme         text,
    currency      text,
    lat           double precision,
    lng           double precision,
    wave_merchant text,
    style         jsonb
)
language sql
stable
security definer
set search_path = public
as $$
    select o.id, o.name, o.slug, o.profile::text, o.storefront_blurb,
           o.phone, o.address, o.theme, o.default_currency, o.lat, o.lng,
           case when o.wave_allowed then o.wave_merchant end,
           (case when org_has(o.id, 'vitrine_plus') then o.storefront_style
                 else '{}'::jsonb end)
           || case when o.logo_key is not null
                   then jsonb_build_object('logo_key', o.logo_key)
                   else '{}'::jsonb end
           || jsonb_build_object('delivers', org_delivers(o.id))
           || coalesce((
                select jsonb_build_object('top_week', jsonb_build_object(
                           'rank', r.rank, 'league', league_label(r.league)))
                  from cauris_week_results r
                 where r.org_id = o.id
                   and r.week_start = (cauris_week_start() - interval '7 days')::date),
              '{}'::jsonb)
    from orgs o
    where o.id = storefront_open(p_slug);
$$;

-- 085's states, with the tick.
create or replace function feature_states(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select case when not is_org_member(p_org_id) then null else
    jsonb_build_object(
        'plan', org_plan(p_org_id),
        'balance', cauris_balance(p_org_id),
        'tools', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'feature', c.feature,
                       'cost', c.cost,
                       'until', u.until,
                       'waits_days', case
                           when c.min_days > 0
                            and o.created_at > now() - make_interval(days => c.min_days)
                           then c.min_days - extract(day from now() - o.created_at)::int end
                   ) order by c.sort)
              from cauris_costs c
              cross join orgs o
              left join cauris_unlocks u
                on u.org_id = p_org_id and u.feature = c.feature and u.until > now()
             where o.id = p_org_id), '[]'::jsonb),
        'progress', org_progress(p_org_id),
        'wave_allowed', coalesce((select wave_allowed from orgs where id = p_org_id), false)
    ) end;
$$;

revoke execute on function set_org_wave_allowed(uuid, boolean) from public;
revoke execute on function trg_order_cash_only()               from public;
revoke execute on function storefront(text)                     from public;
revoke execute on function wave_terms(uuid)                     from public;
revoke execute on function feature_states(uuid)                 from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function set_org_wave_allowed(uuid, boolean) from anon;
        revoke execute on function trg_order_cash_only()               from anon;
        revoke execute on function feature_states(uuid)                 from anon;
        grant execute on function storefront(text)                      to anon;
        revoke execute on function wave_terms(uuid)                     from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_org_wave_allowed(uuid, boolean) to authenticated;
        grant execute on function storefront(text)                     to authenticated;
        grant execute on function wave_terms(uuid)                     to authenticated;
        grant execute on function feature_states(uuid)                 to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
