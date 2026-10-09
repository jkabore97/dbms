-- ============================================================
-- 123_vitrine_views.sql — how many people have looked at a vitrine.
--
-- The owner: « I want a views system for vitrine, a small icon that will
-- show in vitrines the count number of visitors, visible to everyone. »
--
--   1. vitrine_visits(org_id, visitor_hash, day): one row per visitor per
--      vitrine per day. The app keeps a random id on the device (web: the
--      browser's localStorage; Android and iOS: the app's own device
--      storage) — random, never the person, never the account; a
--      signed-in person sends the same random id. The table keeps only
--      sha256(org id ':' visitor id), never the id itself, so one
--      vitrine's rows cannot be matched with another's.
--   2. org_view_counts(org_id, visitors, day, day_new): the vitrine's
--      all-time unique visitors, kept up to date in the same call so the
--      street reads one row (O(1)), never a count. A visitor is new when
--      the vitrine has no row of theirs at all — back the next day, they
--      add a row for that day but not to the total.
--   3. record_vitrine_visit(p_slug, p_visitor) → the vitrine's visitors:
--      the street's call when a vitrine opens, signed out or in. At most
--      one row per visitor per vitrine per day (on conflict do nothing).
--      Not counted: a member of that business (its own preview), a
--      vitrine the street cannot open (storefront_open's rule: switched
--      off, archived, suspended, under the minimum — the same door as
--      storefront()), and a vitrine d'exemple (094's showcase, whose
--      orders and cauris are already closed). The id must be 16 to 64 of
--      [A-Za-z0-9-], refused otherwise.
--   4. Abuse guard: at most 5 000 new rows per vitrine per day (day_new),
--      so a script sending fresh ids cannot inflate a count without
--      limit; past it the day's visits are no longer written, and the
--      count is still returned.
--   5. Retention: about one call in a hundred deletes the rows older than
--      400 days. The total in org_view_counts keeps them counted; a
--      visitor away for more than 400 days counts once more.
--   6. storefront() (110's, redefined, same columns): style gains
--      'visitors' once a vitrine has one — said only then, so a vitrine
--      nobody has visited is the same answer, key for key (P1).
--
-- Shop, farm and association alike: every vitrine is a storefront() of
-- any kind, and the rule above has no kind in it. The street's cards
-- (storefront_directory) are unchanged.
--
-- Re-runnable (the bundle runs twice): tables if not exists, functions
-- replaced with their arguments and results unchanged.
-- ============================================================

-- ------------------------------------------------------------
-- 1–2. The visits and the count
-- ------------------------------------------------------------
create table if not exists vitrine_visits (
    org_id       uuid  not null references orgs(id) on delete cascade,
    visitor_hash bytea not null,
    day          date  not null,
    primary key (org_id, visitor_hash, day)
);
create index if not exists vitrine_visits_by_day on vitrine_visits (day);
alter table vitrine_visits enable row level security;

create table if not exists org_view_counts (
    org_id   uuid    primary key references orgs(id) on delete cascade,
    visitors bigint  not null default 0,
    day      date,
    day_new  integer not null default 0
);
alter table org_view_counts enable row level security;

comment on table vitrine_visits is
    'One row per visitor per vitrine per day (123): sha256 of the org id and the device''s random id, never the id.';
comment on table org_view_counts is
    'A vitrine''s all-time unique visitors (123), kept by record_vitrine_visit; day_new caps the new rows of one day.';

-- No policies, and no table rights for the app's roles: written by
-- record_vitrine_visit(), read by storefront(), both as their definer.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on vitrine_visits, org_view_counts from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on vitrine_visits, org_view_counts from authenticated;
    end if;
end $$;

-- ------------------------------------------------------------
-- 3–5. The street's call
-- ------------------------------------------------------------
create or replace function record_vitrine_visit(p_slug text, p_visitor text)
returns bigint
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org   uuid := storefront_open(p_slug);
    v_id    text := btrim(coalesce(p_visitor, ''));
    v_hash  bytea;
    v_count org_view_counts%rowtype;
    v_new   boolean;
    v_n     int;
begin
    if v_id !~ '^[A-Za-z0-9-]{16,64}$' then
        raise exception 'Identifiant de visiteur invalide';
    end if;
    if v_org is null then
        return null; -- not a vitrine the street can open
    end if;
    if not exists (select 1 from orgs where id = v_org and showcase)
       and not (auth.uid() is not null and exists (
                select 1 from memberships where org_id = v_org and user_id = auth.uid())) then
        v_hash := sha256(convert_to(v_org::text || ':' || v_id, 'UTF8'));
        insert into org_view_counts (org_id) values (v_org) on conflict do nothing;
        select * into v_count from org_view_counts where org_id = v_org for update;
        if v_count.day is distinct from current_date then
            v_count.day_new := 0;
        end if;
        -- The guard: 5 000 new rows a day at most for one vitrine.
        if v_count.day_new < 5000 then
            v_new := not exists (select 1 from vitrine_visits
                                  where org_id = v_org and visitor_hash = v_hash);
            insert into vitrine_visits (org_id, visitor_hash, day)
            values (v_org, v_hash, current_date)
            on conflict do nothing;
            get diagnostics v_n = row_count;
            if v_n > 0 then
                update org_view_counts
                   set visitors = visitors + v_new::int,
                       day      = current_date,
                       day_new  = v_count.day_new + 1
                 where org_id = v_org;
            end if;
        end if;
        -- Retention, now and then: the total keeps what is deleted.
        if random() < 0.01 then
            delete from vitrine_visits where day < current_date - 400;
        end if;
    end if;
    return coalesce((select visitors from org_view_counts where org_id = v_org), 0);
end;
$$;

-- ------------------------------------------------------------
-- 6. storefront (110): the vitrine's visitors, once it has one
-- ------------------------------------------------------------
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
           -- Wave on the vitrine (090's tick, and 110's switch: both open).
           case when o.wave_allowed and not feature_hidden(o.id, 'online_payment')
                then o.wave_merchant end,
           (case when vitrine_plus_on(o.id) then
                     o.storefront_style
                     || case when o.storefront_style ? 'schedule'
                             then jsonb_strip_nulls(jsonb_build_object('open_now',
                                      vitrine_open_now(o.storefront_style -> 'schedule')))
                             else '{}'::jsonb end
                 when cauris_param('vitrine_free_basics', 1) = 1 then
                     o.storefront_style - 'pinned' - 'hide_out_of_stock' - 'layout'
                 else '{}'::jsonb end)
           || vitrine_default_style(o.id)
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
           -- « Commandes en ligne » hidden (110): a showcase — the shelf, no
           -- basket. Said only then, so a vitrine no switch touches is the
           -- same answer, key for key.
           || case when feature_hidden(o.id, 'online_orders')
                   then '{"orders_closed": true}'::jsonb
                   else '{}'::jsonb end
           -- The vitrine's unique visitors (123), from its first one.
           || coalesce((
                select jsonb_build_object('visitors', c.visitors)
                  from org_view_counts c
                 where c.org_id = o.id and c.visitors > 0),
              '{}'::jsonb)
    from orgs o
    where o.id = storefront_open(p_slug);
$$;

-- ------------------------------------------------------------
-- Who may call what (063: a new function is born closed to anon and
-- PUBLIC; each door said again)
-- ------------------------------------------------------------
revoke execute on function record_vitrine_visit(text, text) from public;
revoke execute on function storefront(text)                 from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        -- The street's: a vitrine is opened signed out.
        grant execute on function record_vitrine_visit(text, text) to anon;
        grant execute on function storefront(text)                 to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function record_vitrine_visit(text, text) to authenticated;
        grant execute on function storefront(text)                 to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
