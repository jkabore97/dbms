-- ============================================================
-- 086_cauris_leagues.sql — the weekly competition (phase 3).
--
-- The owner: « competition is key » — four times a week each owner hears
-- the top 3 of their league and how far they are from the next place, and
-- the best of each week win. As decided:
--
--   1. Leagues, so the race is fair: what the business is (shops race
--      shops, farms race farms), its city, and its size. The city is the
--      one it set (orgs.city) or the nearest Burkina town to its pin
--      within 40 km, else « Autres villes »; the size is how much it sold
--      in the last 30 days (orders and till sales counted), small under
--      30, medium under 150, large beyond. Pro subscribers race too.
--   2. The score is the week's earning — Monday to Sunday, Ouagadougou
--      time — never the wallet: spending cauris never costs a place.
--      Prizes, expiries and spending are not in it.
--   3. league_board(): the top 3, the business's rank, its score and the
--      gap to the place above. A business may hide its name from the
--      board (orgs.board_hidden: « Une boutique de Ouagadougou »).
--   4. Four times a week (Mon, Wed, Fri, Sun at 19:00 Ouagadougou,
--      which is UTC), cauris_board_notify() tells every business's admins
--      where they stand, unless they turned it off (orgs.board_notify).
--      Never the bottom of the board: only the top 3 and yourself.
--   5. Monday just after midnight, cauris_week_close() closes last week:
--      each league's top 3 (with a score) get prize cauris (100, 60, 30 —
--      platform settings), the winner a free 7-day « Mettre en avant »
--      spot for the shop, and all three the « Top 3 de la semaine » badge
--      on their vitrine for the week (storefront() style.top_week).
--   6. The schedule runs on pg_cron where the database has it (Supabase
--      does); elsewhere — a test cluster — the functions exist and wait.
--
-- No destructive statement: functions replaced with their own signatures,
-- jobs scheduled by name (cron.schedule replaces a job of the same name).
-- ============================================================

insert into platform_settings (key, value) values
    ('cauris_prize_1', '100'),
    ('cauris_prize_2',  '60'),
    ('cauris_prize_3',  '30'),
    ('league_small_max',  '30'),
    ('league_medium_max', '150')
on conflict (key) do nothing;

alter table orgs add column if not exists city text;
alter table orgs add column if not exists board_hidden boolean not null default false;
alter table orgs add column if not exists board_notify boolean not null default true;

-- Burkina's towns, for a business that pinned itself but named no city.
create table if not exists league_towns (
    name text primary key,
    lat  double precision not null,
    lng  double precision not null
);
alter table league_towns enable row level security;
insert into league_towns (name, lat, lng) values
    ('Ouagadougou',     12.3714, -1.5197),
    ('Bobo-Dioulasso',  11.1771, -4.2979),
    ('Koudougou',       12.2526, -2.3627),
    ('Ouahigouya',      13.5828, -2.4216),
    ('Banfora',         10.6333, -4.7667),
    ('Kaya',            13.0917, -1.0844),
    ('Tenkodogo',       11.7800, -0.3697),
    ('Fada N''Gourma',  12.0616,  0.3584),
    ('Dédougou',        12.4634, -3.4608),
    ('Dori',            14.0354, -0.0345),
    ('Gaoua',           10.3250, -3.1744),
    ('Ziniaré',         12.5822, -1.2983),
    ('Manga',           11.6636, -1.0731),
    ('Réo',             12.3197, -2.4719),
    ('Kombissiri',      12.0647, -1.3375),
    ('Pô',              11.1667, -1.1500),
    ('Koupéla',         12.1792, -0.3517),
    ('Houndé',          11.5000, -3.5167),
    ('Léo',             11.1000, -2.1000),
    ('Djibo',           14.1000, -1.6333)
on conflict (name) do nothing;

-- Each week's results, kept: the badge, the prizes, and the history.
create table if not exists cauris_week_results (
    week_start date not null,
    org_id     uuid not null references orgs(id) on delete cascade,
    league     text not null,
    rank       integer not null,
    score      integer not null,
    primary key (week_start, org_id)
);
alter table cauris_week_results enable row level security;

-- ------------------------------------------------------------
-- 1. The league
-- ------------------------------------------------------------
create or replace function league_city(p_org_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        nullif(btrim(o.city), ''),
        (select t.name from league_towns t
          where o.lat is not null and o.lng is not null
            and distance_km(o.lat, o.lng, t.lat, t.lng) <= 40
          order by distance_km(o.lat, o.lng, t.lat, t.lng)
          limit 1),
        'Autres villes')
    from orgs o where o.id = p_org_id;
$$;

create or replace function league_size(p_org_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    with n as (
        select (select count(*) from orders x
                 where x.org_id = p_org_id and x.status in ('picked_up', 'delivered')
                   and x.created_at >= now() - interval '30 days')
             + (select count(*) from sales s
                 where s.org_id = p_org_id and s.kind = 'sale'
                   and s.occurred_at >= now() - interval '30 days') as c
    )
    select case
        when c < cauris_param('league_small_max', 30)   then 'petites'
        when c < cauris_param('league_medium_max', 150) then 'moyennes'
        else 'grandes' end
    from n;
$$;

create or replace function league_key(p_org_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select (case o.profile when 'farm' then 'farm' else 'retail' end)
           || '|' || league_city(o.id) || '|' || league_size(o.id)
    from orgs o where o.id = p_org_id;
$$;

-- « Boutiques · Ouagadougou · petites »
create or replace function league_label(p_key text)
returns text
language sql
immutable
as $$
    select (case split_part(p_key, '|', 1) when 'farm' then 'Fermes' else 'Boutiques' end)
        || ' · ' || split_part(p_key, '|', 2)
        || ' · ' || split_part(p_key, '|', 3);
$$;

create or replace function cauris_week_start(p_at timestamptz default now())
returns timestamptz
language sql
stable
as $$
    select date_trunc('week', p_at at time zone 'Africa/Ouagadougou')
           at time zone 'Africa/Ouagadougou';
$$;

-- Who races: shops and farms that earned at least once, not archived.
create or replace function league_scores(p_from timestamptz, p_to timestamptz)
returns table (org_id uuid, name text, hidden boolean, league text, score integer)
language sql
stable
security definer
set search_path = public
as $$
    select o.id, o.name, o.board_hidden, league_key(o.id),
           coalesce((select sum(l.delta) from cauris_ledger l
                      where l.org_id = o.id and l.delta > 0
                        and l.reason not in ('prize', 'expired', 'spent')
                        and l.created_at >= p_from and l.created_at < p_to), 0)::int
      from orgs o
     where o.profile not in ('church', 'association')
       and o.archived_at is null and o.suspended_at is null
       and exists (select 1 from cauris_ledger l where l.org_id = o.id);
$$;

-- ------------------------------------------------------------
-- 2. The board
-- ------------------------------------------------------------
create or replace function league_board(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    with me_org as (
        select o.id, o.name, o.board_hidden, o.board_notify, league_key(o.id) as league
          from orgs o
         where o.id = p_org_id and is_org_member(p_org_id)
    ), board as (
        select s.org_id, s.name, s.hidden, s.score,
               (rank() over (order by s.score desc, s.name))::int as rank
          from league_scores(cauris_week_start(), now() + interval '1 second') s, me_org m
         where s.league = m.league
    ), me as (
        select coalesce((select b.score from board b where b.org_id = p_org_id), 0) as score
    ), mine as (
        select me.score,
               (select count(*) from board b where b.score > me.score)::int + 1 as rank,
               (select min(b.score) from board b where b.score > me.score) as above
          from me
    )
    select jsonb_build_object(
        'league', m.league,
        'label', league_label(m.league),
        'week_start', cauris_week_start(),
        'size', greatest((select count(*) from board), 1),
        'top', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'rank', t.rank,
                       'name', case when t.hidden and t.org_id <> p_org_id
                                    then 'Une ' || case when split_part(m.league, '|', 1) = 'farm'
                                                        then 'ferme' else 'boutique' end
                                         || ' de ' || split_part(m.league, '|', 2)
                                    else t.name end,
                       'score', t.score,
                       'me', t.org_id = p_org_id) order by t.rank, t.name)
              from (select * from board where score > 0 order by rank, name limit 3) t),
            '[]'::jsonb),
        'rank', x.rank,
        'score', x.score,
        'gap', case when x.above is null then null else x.above - x.score + 1 end,
        'hidden', m.board_hidden,
        'notify', m.board_notify,
        'last_week', (select jsonb_build_object('rank', r.rank, 'score', r.score)
                        from cauris_week_results r
                       where r.org_id = p_org_id
                         and r.week_start = (cauris_week_start() - interval '7 days')::date)
    )
    from me_org m, mine x;
$$;

create or replace function set_board_prefs(p_org_id uuid, p_hidden boolean, p_notify boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur règle le classement';
    end if;
    update orgs set board_hidden = coalesce(p_hidden, board_hidden),
                    board_notify = coalesce(p_notify, board_notify)
     where id = p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- 3. The four notifications, and the week's close
-- ------------------------------------------------------------
create or replace function cauris_board_notify()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_from timestamptz := cauris_week_start();
    v_n    int := 0;
    r      record;
    v_top  text;
    v_me   record;
    v_gap  int;
begin
    create temporary table if not exists _all (
        org_id uuid, name text, hidden boolean, league text, score int, rank int) on commit drop;
    truncate _all;
    insert into _all
    select s.org_id, s.name, s.hidden, s.league, s.score,
           (rank() over (partition by s.league order by s.score desc, s.name))::int
      from league_scores(v_from, now()) s;

    for r in select a.* from _all a join orgs o on o.id = a.org_id where o.board_notify loop
        select string_agg(t.rank || '. ' ||
                   case when t.hidden then 'une ' ||
                        case when split_part(r.league, '|', 1) = 'farm' then 'ferme' else 'boutique' end
                        else t.name end
                   || ' ' || t.score, ' · ' order by t.rank, t.name)
          into v_top
          from (select * from _all where league = r.league and score > 0
                 order by rank, name limit 3) t;
        if v_top is null then
            continue;  -- nobody has earned yet in this league this week
        end if;
        select min(score) into v_gap from _all
         where league = r.league and score > r.score;
        perform notify_org_admins(r.org_id, 'cauris_board',
            '🏆 ' || league_label(r.league) || ' : ' || v_top || '. '
            || case
                 when r.rank = 1 and r.score > 0 then 'Vous êtes 1er, bravo ! Gardez la tête.'
                 when v_gap is not null then 'Vous êtes ' || r.rank || 'e : encore '
                      || (v_gap - r.score + 1) || ' cauris pour la place devant.'
                 else 'Vous êtes ' || r.rank || 'e.'
               end);
        v_n := v_n + 1;
    end loop;
    return v_n;
end;
$$;

create or replace function cauris_week_close(p_week_start date default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_from timestamptz := coalesce(p_week_start::timestamp at time zone 'Africa/Ouagadougou',
                                   cauris_week_start() - interval '7 days');
    v_to   timestamptz := v_from + interval '7 days';
    v_week date := (v_from at time zone 'Africa/Ouagadougou')::date;
    v_n    int := 0;
    r      record;
    v_pts  int;
begin
    for r in
        select x.* from (
            select s.org_id, s.league, s.score,
                   (rank() over (partition by s.league order by s.score desc, s.name))::int as rank
              from league_scores(v_from, v_to) s
             where s.score > 0
        ) x where x.rank <= 3
    loop
        insert into cauris_week_results (week_start, org_id, league, rank, score)
        values (v_week, r.org_id, r.league, r.rank, r.score)
        on conflict (week_start, org_id) do nothing;
        if not found then
            continue;  -- already closed: once per week
        end if;
        v_pts := cauris_param('cauris_prize_' || r.rank, 0);
        if v_pts > 0 then
            insert into cauris_ledger (org_id, delta, reason, ref, note)
            values (r.org_id, v_pts, 'prize', v_week::text,
                    r.rank || 'e de la semaine · ' || league_label(r.league))
            on conflict do nothing;
        end if;
        if r.rank = 1 then
            insert into promotions (org_id, kind, days, price, currency, free, status,
                                    starts_at, ends_at, decided_at, note)
            values (r.org_id, 'shop', 7, 0, 'XOF', true, 'approved',
                    next_spot_start('shop'), next_spot_start('shop') + interval '7 days',
                    now(), 'Premier de la semaine (cauris)');
        end if;
        begin
            perform notify_org_admins(r.org_id, 'cauris_prize',
                '🏆 ' || r.rank || 'e de la semaine en ' || league_label(r.league)
                || ' ! +' || v_pts || ' cauris'
                || case when r.rank = 1 then ', et votre vitrine mise en avant 7 jours.' else '.' end);
        exception when others then null;
        end;
        v_n := v_n + 1;
    end loop;
    return v_n;
end;
$$;

-- ------------------------------------------------------------
-- 4. The vitrine's badge: last week's top 3
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
           o.wave_merchant,
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

-- ------------------------------------------------------------
-- 5. Grants, and the schedule
-- ------------------------------------------------------------
revoke execute on function league_city(uuid)                         from public;
revoke execute on function league_size(uuid)                         from public;
revoke execute on function league_key(uuid)                          from public;
revoke execute on function league_label(text)                        from public;
revoke execute on function cauris_week_start(timestamptz)            from public;
revoke execute on function league_scores(timestamptz, timestamptz)   from public;
revoke execute on function league_board(uuid)                        from public;
revoke execute on function set_board_prefs(uuid, boolean, boolean)   from public;
revoke execute on function cauris_board_notify()                     from public;
revoke execute on function cauris_week_close(date)                   from public;
revoke execute on function storefront(text)                          from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        grant execute on function storefront(text) to anon;
        revoke execute on function league_city(uuid)                       from anon;
        revoke execute on function league_size(uuid)                       from anon;
        revoke execute on function league_key(uuid)                        from anon;
        revoke execute on function league_scores(timestamptz, timestamptz) from anon;
        revoke execute on function league_board(uuid)                      from anon;
        revoke execute on function set_board_prefs(uuid, boolean, boolean) from anon;
        revoke execute on function cauris_board_notify()                   from anon;
        revoke execute on function cauris_week_close(date)                 from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function storefront(text)                         to authenticated;
        grant execute on function league_label(text)                       to authenticated;
        grant execute on function cauris_week_start(timestamptz)           to authenticated;
        grant execute on function league_board(uuid)                       to authenticated;
        grant execute on function set_board_prefs(uuid, boolean, boolean)  to authenticated;
        revoke execute on function league_city(uuid)                       from authenticated;
        revoke execute on function league_size(uuid)                       from authenticated;
        revoke execute on function league_key(uuid)                        from authenticated;
        revoke execute on function league_scores(timestamptz, timestamptz) from authenticated;
        revoke execute on function cauris_board_notify()                   from authenticated;
        revoke execute on function cauris_week_close(date)                 from authenticated;
    end if;
end $$;

do $$
begin
    if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
        begin
            create extension if not exists pg_cron;
            -- Ouagadougou is UTC all year: 19:00 there is 19:00 UTC.
            perform cron.schedule('cauris-board', '0 19 * * 0,1,3,5',
                                  'select public.cauris_board_notify()');
            perform cron.schedule('cauris-week-close', '10 0 * * 1',
                                  'select public.cauris_week_close()');
        exception when others then
            raise notice 'pg_cron not scheduled here: %', sqlerrm;
        end;
    end if;
end $$;

notify pgrst, 'reload schema';
