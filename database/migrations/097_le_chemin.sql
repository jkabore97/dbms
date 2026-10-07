-- ============================================================
-- 097_le_chemin.sql — « Le Chemin »: one path, four stages, the server
-- holds every step.
--
-- The owner: « the training system combined with point earning … I see
-- many pages one after the other and it's confusing ». Seven surfaces told
-- the same progress: the first setup, the home path card, the vitrine
-- guide, the vitrine meter, the settings ticks, the Académie (087) and
-- Mes cauris. Now one spine, for shops and farms:
--
--   1 Ouvrir   first article, vitrine open, phone and address
--   2 Remplir  {min} articles, three photos, a sentence, the pin, a first
--              sale (a shop) or a first log line (a farm)
--   3 Vendre   a first accepted order, three finished, a customer back,
--              the till (or the log) kept 7 days
--   4 Grandir  a first tool bought with cauris, a business sponsored, the
--              week's top 3
--
--   * path_steps: the definitions (titles, why it matters, where to go,
--     what it pays, what it opens) — data, editable from SQL.
--   * org_path_done: a step reached stays reached, recorded once, and
--     paid once into cauris_ledger (reason 'path_step', ref = the step;
--     the ledger's unique (org, reason, ref) makes payment idempotent).
--   * path_state(org): what the app draws, for the business's members
--     (the wallet's balance and week for its admins only).
--   * The tool gates (089) become step-based and stay computed live from
--     the data: invoices with `articles` and `photos`, production with
--     stage 2 complete, the credit book with `three_orders`, a second
--     business with Pro. Pro and other profiles are never locked.
--   * 096's triggers record and pay the steps as the data moves, so a
--     business that never opens the app is still paid; new triggers on
--     sales, the farm log, cauris unlocks, sponsoring and the week's
--     podium. Each swallows its own failure.
--   * What every business already reached is recorded unpaid, once: the
--     lessons and the vitrine paid for it already.
--   * 096's seed, run under the percentages, is undone where the steps
--     still lock the tool, so the bell rings when they open it.
--   * The Académie (087) is removed: its functions and tables, its cauris
--     rule. Ledger lines of reason 'lesson' stay as history, labelled.
--
-- Re-runnable: tables if not exists, functions replaced, triggers dropped
-- and recreated, the seed guarded by a platform setting.
-- ============================================================

-- ------------------------------------------------------------
-- 0. Settings
-- ------------------------------------------------------------
insert into platform_settings (key, value) values
    -- Businesses racing in a league before the board says more than « Bientôt ».
    ('path_league_min', '3'),
    -- 1 opens every tool gate for everyone (the owner's switch; the test
    -- suites that are about something else use it for their fixtures).
    ('path_gates_open', '0')
on conflict (key) do nothing;

-- The vitrine percentages no longer gate anything (path_locked below).
delete from platform_settings where key in ('progress_invoices_pct', 'progress_production_pct');

-- ------------------------------------------------------------
-- 1. The steps
-- ------------------------------------------------------------
create table if not exists path_steps (
    key        text primary key,
    stage      integer not null check (stage between 1 and 4),
    sort       integer not null default 0,
    profiles   text[] not null default array['retail', 'farm'],
    title      text not null,
    title_farm text,
    line       text not null,
    line_farm  text,
    reward     integer not null default 0 check (reward >= 0),
    go         text not null default '',
    go_farm    text,
    opens      text check (opens is null or opens in ('invoices', 'production', 'credits'))
);

comment on table path_steps is
    'Le Chemin (097): each step of the path, its words, reward and what it opens.';

alter table path_steps enable row level security;
drop policy if exists path_steps_read on path_steps;
create policy path_steps_read on path_steps for select using (true);

insert into path_steps (key, stage, sort, profiles, title, title_farm, line, line_farm, reward, go, go_farm, opens) values
    ('first_article', 1, 10, array['retail', 'farm'],
        'Mon premier article', 'Mon premier produit en vente',
        'Un article en vente, et votre boutique existe pour vos clients.',
        'Un produit en vente, et votre ferme existe pour vos clients.',
        5, 'produits', 'a-vendre', null),
    ('vitrine_open', 1, 20, array['retail', 'farm'],
        'Ouvrir ma vitrine', null,
        'Votre vitrine, c''est votre boutique ouverte sur internet.',
        'Votre vitrine, c''est votre ferme ouverte sur internet.',
        5, 'administration/parametres?partie=vitrine', null, null),
    ('contact', 1, 30, array['retail', 'farm'],
        'Mon téléphone et mon adresse', null,
        'Vos clients savent vous appeler et vous trouver.', null,
        5, 'administration/parametres?partie=vitrine', null, null),
    ('articles', 2, 10, array['retail', 'farm'],
        '{min} articles en vente', '{min} produits en vente',
        'Avec {min} articles, votre vitrine se montre à tout le monde.',
        'Avec {min} produits, votre vitrine se montre à tout le monde.',
        20, 'produits', 'a-vendre', null),
    ('photos', 2, 20, array['retail', 'farm'],
        'Trois articles en photo', 'Trois produits en photo',
        'Une photo fait vendre : vos clients voient ce qu''ils achètent.', null,
        20, 'produits', 'a-vendre', 'invoices'),
    ('blurb', 2, 30, array['retail', 'farm'],
        'Une phrase de présentation', null,
        'Une phrase pour dire qui vous êtes et ce que vous vendez.', null,
        10, 'administration/parametres?partie=vitrine', null, null),
    ('pin', 2, 40, array['retail', 'farm'],
        'Ma position sur la carte', null,
        'Vos clients vous trouvent sur la carte du quartier.', null,
        10, 'administration/parametres?partie=position', null, null),
    ('first_sale', 2, 50, array['retail'],
        'Ma première vente à la caisse', null,
        'Chaque vente notée, et votre caisse se tient toute seule.', null,
        10, '', null, 'production'),
    ('farm_log', 2, 50, array['farm'],
        'Mon cahier de la ferme', null,
        'Notez une pesée, un vaccin ou une perte : la ferme se suit.', null,
        10, 'bandes', null, 'production'),
    ('first_order', 3, 10, array['retail', 'farm'],
        'Ma première commande acceptée', null,
        'Un client a commandé sur votre vitrine : répondez-lui vite.', null,
        10, 'commandes', null, null),
    ('three_orders', 3, 20, array['retail', 'farm'],
        'Trois commandes terminées', null,
        'Trois commandes remises, et le carnet de crédit s''ouvre.', null,
        20, 'commandes', null, 'credits'),
    ('returning', 3, 30, array['retail', 'farm'],
        'Un client revenu', null,
        'Un client qui revient, c''est un client content.', null,
        15, 'commandes', null, null),
    ('till_week', 3, 40, array['retail'],
        'La caisse tenue 7 jours', null,
        'Sept jours de caisse, et vous voyez ce que vous gagnez.', null,
        20, '', null, null),
    ('log_week', 3, 40, array['farm'],
        'Le cahier tenu 7 jours', null,
        'Sept jours de cahier, et vous voyez votre ferme grandir.', null,
        20, 'bandes', null, null),
    ('first_unlock', 4, 10, array['retail', 'farm'],
        'Mon premier outil avec mes cauris', null,
        'Vos cauris ouvrent les outils de Mara Pro.', null,
        10, 'chemin', null, null),
    ('referral', 4, 20, array['retail', 'farm'],
        'Parrainer une entreprise', null,
        'Une entreprise vous nomme parrain. Quand elle décolle, +{referral} cauris de plus.', null,
        10, 'chemin', null, null),
    ('podium', 4, 30, array['retail', 'farm'],
        'Dans le top 3 de la semaine', null,
        'Les trois premiers de la semaine gagnent des cauris en plus.', null,
        20, 'classement', null, null)
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- 2. What each business reached
-- ------------------------------------------------------------
create table if not exists org_path_done (
    org_id  uuid not null references orgs(id) on delete cascade,
    step    text not null references path_steps(key) on delete cascade,
    done_at timestamptz not null default now(),
    paid    integer not null default 0,
    primary key (org_id, step)
);

comment on table org_path_done is
    'Each path step (097) a business reached, once, and the cauris it was paid for it.';

alter table org_path_done enable row level security;
drop policy if exists org_path_done_read on org_path_done;
create policy org_path_done_read on org_path_done
    for select using (is_org_member(org_id));

-- ------------------------------------------------------------
-- 3. How far a step is, live
-- ------------------------------------------------------------
create or replace function path_goal(p_org uuid, p_step text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select case p_step
        when 'contact'      then 2
        when 'articles'     then greatest(cauris_param('vitrine_min_items', 8), 1)
        when 'photos'       then 3
        when 'three_orders' then greatest(cauris_param('progress_credit_orders', 3), 0)
        when 'till_week'    then 7
        when 'log_week'     then 7
        else 1
    end;
$$;

create or replace function path_progress(p_org uuid, p_step text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
    select (case p_step
        when 'first_article' then
            (select count(*) from products p
              where p.org_id = p_org and p.is_active and p.is_published)
        when 'articles' then
            (select count(*) from products p
              where p.org_id = p_org and p.is_active and p.is_published)
        when 'vitrine_open' then
            (select count(*) from orgs o where o.id = p_org and o.storefront_enabled)
        when 'contact' then
            (select (nullif(btrim(coalesce(o.phone, '')), '') is not null)::int
                  + (nullif(btrim(coalesce(o.address, '')), '') is not null)::int
               from orgs o where o.id = p_org)
        when 'photos' then
            (select count(*) from products p
              where p.org_id = p_org and p.is_active and p.is_published
                and exists (select 1 from documents d where d.product_id = p.id))
        when 'blurb' then
            (select count(*) from orgs o
              where o.id = p_org and nullif(btrim(coalesce(o.storefront_blurb, '')), '') is not null)
        when 'pin' then
            (select count(*) from orgs o
              where o.id = p_org and o.lat is not null and o.lng is not null)
        when 'first_sale' then
            (select count(*) from (select 1 from sales s
                                    where s.org_id = p_org and s.kind = 'sale' limit 1) x)
        when 'farm_log' then
            (select count(*) from (select 1 from flock_events e join flocks f on f.id = e.flock_id
                                    where f.org_id = p_org limit 1) x)
        when 'first_order' then
            (select count(*) from (select 1 from orders x
                                    where x.org_id = p_org
                                      and x.status in ('accepted', 'ready', 'picked_up', 'delivered')
                                    limit 1) y)
        when 'three_orders' then
            (select count(*) from orders x
              where x.org_id = p_org and x.status in ('picked_up', 'delivered'))
        when 'returning' then
            (select count(*) from (select 1 from orders x
                                    where x.org_id = p_org and x.customer_id is not null
                                      and x.status in ('picked_up', 'delivered')
                                    group by x.customer_id having count(*) >= 2 limit 1) y)
        when 'till_week' then
            (select count(distinct (s.occurred_at at time zone 'Africa/Ouagadougou')::date)
               from sales s where s.org_id = p_org and s.kind = 'sale')
        when 'log_week' then
            (select count(distinct (e.occurred_at at time zone 'Africa/Ouagadougou')::date)
               from flock_events e join flocks f on f.id = e.flock_id
              where f.org_id = p_org)
        when 'first_unlock' then
            (select count(*) from (select 1 from cauris_unlocks u
                                    where u.org_id = p_org limit 1) x)
        when 'referral' then
            (select count(*) from (select 1 from orgs r
                                    where r.referred_by = p_org limit 1) x)
        -- A podium counts only in a week its league was a race: at least
        -- path_league_min businesses that earned that week. The week's
        -- results keep the podium alone (rank <= 3), so the racers are
        -- counted again from that week's ledger (league_scores over the
        -- week), in the league the result was written for. The league a
        -- business is in is worked out today (its town, its size), which
        -- for a past week may differ at the margin; the scores do not.
        when 'podium' then
            (select count(*) from (select 1 from cauris_week_results w
                                    where w.org_id = p_org and w.rank <= 3
                                      and (select count(*)
                                             from league_scores(
                                                    w.week_start::timestamp at time zone 'Africa/Ouagadougou',
                                                    (w.week_start + 7)::timestamp at time zone 'Africa/Ouagadougou') l
                                            where l.league = w.league and l.score > 0)
                                          >= cauris_param('path_league_min', 3)
                                    limit 1) x)
        else 0
    end)::int;
$$;

-- A step's words for this business: the farm's when it has its own, with
-- the vitrine minimum and what a sponsored business pays said.
create or replace function path_text(p_text text, p_farm_text text, p_profile text)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select replace(replace(case when p_profile = 'farm' and p_farm_text is not null
                                then p_farm_text else p_text end,
                           '{min}', path_goal(null, 'articles')::text),
                   '{referral}',
                   coalesce((select r.points from cauris_rules r where r.key = 'referral'), 0)::text);
$$;

-- ------------------------------------------------------------
-- 4. Recording and paying
-- ------------------------------------------------------------
-- The steps reached and not yet recorded: recorded, and each paid its
-- reward, once. Returns how many were recorded. A showcase vitrine (094)
-- records its steps but its ledger lines are dropped by 094's trigger, so
-- it is paid nothing.
create or replace function path_sync(p_org uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_profile text;
    v_step    path_steps%rowtype;
    v_made    integer := 0;
    v_rows    integer;
begin
    select o.profile::text into v_profile from orgs o where o.id = p_org;
    if v_profile is null or v_profile not in ('retail', 'farm') then
        return 0;
    end if;
    for v_step in
        select s.* from path_steps s
         where v_profile = any (s.profiles)
           and not exists (select 1 from org_path_done d
                            where d.org_id = p_org and d.step = s.key)
         order by s.stage, s.sort
    loop
        if path_progress(p_org, v_step.key) >= path_goal(p_org, v_step.key) then
            insert into org_path_done (org_id, step) values (p_org, v_step.key)
                on conflict do nothing;
            if found then
                v_made := v_made + 1;
                if v_step.reward > 0 then
                    perform cauris_expire(p_org);
                    insert into cauris_ledger (org_id, delta, reason, ref, note)
                    values (p_org, v_step.reward, 'path_step', v_step.key,
                            path_text(v_step.title, v_step.title_farm, v_profile))
                    on conflict (org_id, reason, ref) do nothing;
                    get diagnostics v_rows = row_count;
                    if v_rows > 0 then
                        update org_path_done set paid = v_step.reward
                         where org_id = p_org and step = v_step.key;
                    end if;
                end if;
            end if;
        end if;
    end loop;
    return v_made;
end;
$$;

-- ------------------------------------------------------------
-- 5. The gates, by the steps (089's rule, rewritten)
-- ------------------------------------------------------------
create or replace function path_locked(p_org_id uuid, p_step text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select case
        when o.profile not in ('retail', 'farm') then false
        when p_step = 'second_business' then org_plan(o.id) <> 'pro'
        when org_plan(o.id) = 'pro' then false
        when cauris_param('path_gates_open', 0) = 1 then false
        when p_step = 'invoices'
            then path_progress(o.id, 'articles') < path_goal(o.id, 'articles')
              or path_progress(o.id, 'photos')   < path_goal(o.id, 'photos')
        when p_step = 'production'
            then exists (select 1 from path_steps s
                          where s.stage = 2 and o.profile = any (s.profiles)
                            and path_progress(o.id, s.key) < path_goal(o.id, s.key))
        when p_step = 'credits'
            then path_progress(o.id, 'three_orders') < path_goal(o.id, 'three_orders')
        else false
    end
    from orgs o where o.id = p_org_id;
$$;

create or replace function path_lock_message(p_step text)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select case p_step
        when 'invoices'   then 'Factures : ' || path_goal(null, 'articles')
                               || ' articles en vente et ' || path_goal(null, 'photos')
                               || ' en photo pour les débloquer.'
        when 'production' then 'Production : terminez l''étape Remplir pour la débloquer.'
        when 'credits'    then 'Carnet de crédit : '
                               || path_goal(null, 'three_orders')
                               || ' commandes terminées pour le débloquer.'
        when 'second_business' then 'Une deuxième entreprise : avec Mara Pro.'
        else 'Outil verrouillé.'
    end;
$$;

-- 096's bell, saying the steps.
create or replace function unlock_message(p_step text)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select case p_step
        when 'invoices'   then 'Factures débloquées : ' || path_goal(null, 'articles')
                               || ' articles en vente et ' || path_goal(null, 'photos')
                               || ' en photo.'
        when 'production' then 'Production débloquée : l''étape Remplir est terminée.'
        when 'credits'    then 'Carnet de crédit débloqué : '
                               || path_goal(null, 'three_orders')
                               || ' commandes terminées.'
        else 'Un outil est débloqué.'
    end;
$$;

-- 096's seed recorded as seen what was open under 089's percentages.
-- Where the steps still lock it, that row would keep the bell from ever
-- ringing when the steps do open it: dropped. Only rows that seed wrote in
-- this same transaction (the bundle is one), so a bell already earned
-- under the steps is never taken back. No live shop had invoices or
-- production open under the percentages when this shipped.
delete from org_unlocks
 where unlocked_at = now() and seen_at = now() and path_locked(org_id, step);

-- 089's progress, without the vitrine percentages that no longer gate
-- anything (an older app falls back to its own defaults for them).
create or replace function org_progress(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'gated',         o.profile in ('retail', 'farm'),
        'trial_until',   null,
        'in_trial',      false,
        'score',         vitrine_score(o.id),
        'orders',        (select count(*) from orders x
                           where x.org_id = o.id and x.status in ('picked_up', 'delivered')),
        'street_pct',    cauris_param('progress_street_pct', 60),
        'credit_orders', cauris_param('progress_credit_orders', 3),
        'orders_needed', cauris_param('progress_credit_orders', 3),
        'pro',           org_plan(o.id) = 'pro',
        'locks', jsonb_build_object(
            'invoices',        path_locked(o.id, 'invoices'),
            'production',      path_locked(o.id, 'production'),
            'credits',         path_locked(o.id, 'credits'),
            'second_business', path_locked(o.id, 'second_business')),
        'on_street',     o.progress_since is null
                         or vitrine_score(o.id) >= cauris_param('progress_street_pct', 60)
    )
    from orgs o where o.id = p_org_id;
$$;

-- ------------------------------------------------------------
-- 6. What the app draws
-- ------------------------------------------------------------
create or replace function path_state(p_org uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth
as $$
declare
    v_profile text;
    v_stage   integer;
    v_steps   jsonb;
    v_stages  jsonb;
    v_next    text;
    v_league  boolean := false;
    v_admin   boolean;
begin
    if p_org is null or not is_org_member(p_org) then
        return null;
    end if;
    v_admin := is_org_admin(p_org);
    select o.profile::text into v_profile from orgs o where o.id = p_org;
    if v_profile is null or v_profile not in ('retail', 'farm') then
        return null;
    end if;
    perform path_sync(p_org);
    perform cauris_expire(p_org);

    select coalesce(jsonb_agg(jsonb_build_object(
               'key', r.key, 'stage', r.stage, 'title', r.title, 'line', r.line,
               'go', r.go,
               -- A step reached stays reached: it shows its goal met, even
               -- if the data fell back since.
               'progress', case when r.done then r.goal else least(r.live, r.goal) end,
               -- What the data says right now, for the gates (live).
               'live', least(r.live, r.goal),
               'goal', r.goal, 'done', r.done, 'reward', r.reward, 'opens', r.opens)
               order by r.stage, r.sort), '[]'::jsonb)
      into v_steps
      from (select s.key, s.stage, s.sort, s.reward, s.opens,
                   path_text(s.title, s.title_farm, v_profile) as title,
                   path_text(s.line, s.line_farm, v_profile) as line,
                   case when v_profile = 'farm' and s.go_farm is not null
                        then s.go_farm else s.go end as go,
                   path_progress(p_org, s.key) as live,
                   path_goal(p_org, s.key) as goal,
                   exists (select 1 from org_path_done d
                            where d.org_id = p_org and d.step = s.key) as done
              from path_steps s
             where v_profile = any (s.profiles)) r;

    select coalesce(min((e ->> 'stage')::int), 5) into v_stage
      from jsonb_array_elements(v_steps) e where not (e ->> 'done')::boolean;
    select e ->> 'key' into v_next
      from jsonb_array_elements(v_steps) with ordinality x(e, i)
     where not (e ->> 'done')::boolean order by i limit 1;

    select jsonb_agg(jsonb_build_object(
               'n', n.n,
               'title', (array['Ouvrir', 'Remplir', 'Vendre', 'Grandir'])[n.n],
               'done', not exists (select 1 from jsonb_array_elements(v_steps) e
                                    where (e ->> 'stage')::int = n.n
                                      and not (e ->> 'done')::boolean))
               order by n.n)
      into v_stages from generate_series(1, 4) n(n);

    if v_stage >= 4 then
        -- A race is businesses earning this week: one that earned once,
        -- long ago, is on the board at 0 and does not make it one.
        v_league := (select count(*) from league_scores(cauris_week_start(),
                                                        now() + interval '1 second') l
                      where l.league = league_key(p_org) and l.score > 0)
                    >= cauris_param('path_league_min', 3);
    end if;

    return jsonb_build_object(
        'stage', v_stage,
        'stages', v_stages,
        'next', v_next,
        'steps', coalesce(v_steps, '[]'::jsonb),
        'tools', jsonb_build_object(
            'invoices',        not path_locked(p_org, 'invoices'),
            'production',      not path_locked(p_org, 'production'),
            'credits',         not path_locked(p_org, 'credits'),
            'second_business', not path_locked(p_org, 'second_business')),
        -- The wallet is the admins' (as my_cauris): null for the others.
        'balance', case when v_admin then cauris_balance(p_org) end,
        -- This week's score, as the league counts it (086).
        'week', case when v_admin then
                    (select coalesce(sum(l.delta), 0)::int from cauris_ledger l
                      where l.org_id = p_org and l.delta > 0
                        and l.reason not in ('prize', 'expired', 'spent')
                        and l.created_at >= cauris_week_start()) end,
        'league_open', v_league
    );
end;
$$;

-- ------------------------------------------------------------
-- 7. Recorded as the data moves: 096's triggers, and more
-- ------------------------------------------------------------
create or replace function trg_check_unlocks()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org uuid;
    v_ref uuid;
begin
    if tg_table_name = 'orgs' then
        v_org := new.id;
        -- Sponsoring is the sponsor's step.
        if tg_op = 'UPDATE' and new.referred_by is distinct from old.referred_by then
            v_ref := new.referred_by;
        end if;
    elsif tg_table_name = 'flock_events' then
        select f.org_id into v_org from flocks f where f.id = new.flock_id;
    elsif tg_op = 'DELETE' then
        v_org := old.org_id;
    else
        v_org := new.org_id;
    end if;
    begin
        perform path_sync(v_org);
    exception when others then
        null;  -- a step must never cost the write that reached it
    end;
    if v_ref is not null then
        begin
            perform path_sync(v_ref);
        exception when others then
            null;
        end;
    end if;
    begin
        perform check_unlocks(v_org);
    exception when others then
        null;  -- a bell must never cost the write that rang it
    end;
    return null;
end;
$$;

drop trigger if exists products_check_unlocks on products;
create trigger products_check_unlocks
    after insert or delete or update of is_published, is_active on products
    for each row execute function trg_check_unlocks();

drop trigger if exists documents_check_unlocks on documents;
create trigger documents_check_unlocks
    after insert or delete or update of product_id on documents
    for each row execute function trg_check_unlocks();

drop trigger if exists orgs_check_unlocks on orgs;
create trigger orgs_check_unlocks
    after update of storefront_enabled, storefront_blurb, phone, address, lat, lng, plan, referred_by
    on orgs
    for each row execute function trg_check_unlocks();

drop trigger if exists orders_check_unlocks on orders;
create trigger orders_check_unlocks
    after insert or update of status on orders
    for each row execute function trg_check_unlocks();

drop trigger if exists sales_check_unlocks on sales;
create trigger sales_check_unlocks
    after insert on sales
    for each row execute function trg_check_unlocks();

drop trigger if exists flock_events_check_unlocks on flock_events;
create trigger flock_events_check_unlocks
    after insert on flock_events
    for each row execute function trg_check_unlocks();

drop trigger if exists cauris_unlocks_check_unlocks on cauris_unlocks;
create trigger cauris_unlocks_check_unlocks
    after insert on cauris_unlocks
    for each row execute function trg_check_unlocks();

drop trigger if exists cauris_week_results_check_unlocks on cauris_week_results;
create trigger cauris_week_results_check_unlocks
    after insert on cauris_week_results
    for each row execute function trg_check_unlocks();

-- ------------------------------------------------------------
-- 8. What was reached before this shipped: recorded, not paid
-- ------------------------------------------------------------
-- Once: the lessons and the vitrine paid for it already. Guarded so the
-- bundle run again does not record, unpaid, what was reached since.
do $$
begin
    if not exists (select 1 from platform_settings where key = 'path_seeded') then
        insert into org_path_done (org_id, step, paid)
        select o.id, s.key, 0
          from orgs o
          join path_steps s on o.profile::text = any (s.profiles)
         where o.profile in ('retail', 'farm')
           and path_progress(o.id, s.key) >= path_goal(o.id, s.key)
        on conflict do nothing;
        insert into platform_settings (key, value) values ('path_seeded', to_jsonb(now()))
        on conflict (key) do nothing;
    end if;
end $$;

-- ------------------------------------------------------------
-- 9. The Académie goes
-- ------------------------------------------------------------
drop function if exists complete_lesson(uuid, text);
drop function if exists my_academy(uuid);
drop function if exists academy_mission_met(uuid, text);
drop table if exists academy_done;
drop table if exists academy_lessons;
-- No ledger line points at a rule (my_cauris labels by a left join), so
-- the rule can go; the 'lesson' lines stay, labelled below.
delete from cauris_rules where key = 'lesson';

-- 092's wallet, with the labels for what has no rule.
create or replace function my_cauris(p_org_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_last timestamptz;
begin
    if not is_org_admin(p_org_id) then
        return null;
    end if;
    perform cauris_expire(p_org_id);
    select max(created_at) into v_last from cauris_ledger
     where org_id = p_org_id and reason <> 'expired';
    return jsonb_build_object(
        'balance', cauris_balance(p_org_id),
        'week', (select coalesce(sum(delta), 0) from cauris_ledger
                  where org_id = p_org_id and delta > 0 and reason <> 'expired'
                    and created_at >= date_trunc('week', now() at time zone 'Africa/Ouagadougou')
                                      at time zone 'Africa/Ouagadougou'),
        'expires_on', case when v_last is null then null
                           else ((v_last at time zone 'Africa/Ouagadougou')::date
                                 + cauris_param('cauris_expire_days', 180)) end,
        'referral_code', (select slug from orgs where id = p_org_id),
        'referred', (select referred_by is not null from orgs where id = p_org_id),
        'referral_points', coalesce((select points from cauris_rules where key = 'referral'), 0),
        'referrals', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'name', r.name,
                       'score', vitrine_score(r.id),
                       'orders', (select count(*) from orders o
                                   where o.org_id = r.id and o.status in ('picked_up', 'delivered')),
                       'paid', exists (select 1 from cauris_ledger l
                                        where l.org_id = p_org_id and l.reason = 'referral'
                                          and l.ref = r.id::text)
                   ) order by r.created_at desc)
              from orgs r where r.referred_by = p_org_id), '[]'::jsonb),
        'history', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'delta', l.delta,
                       'reason', l.reason,
                       'label', coalesce(r.label, case l.reason
                                    when 'expired'   then 'Cauris expirés'
                                    when 'spent'     then 'Dépensés'
                                    when 'path_step' then 'Étape du chemin'
                                    when 'prize'     then 'Podium de la semaine'
                                    when 'lesson'    then 'Leçon de l''Académie Mara'
                                    else l.reason end),
                       'note', case when l.reason in ('expired', 'spent', 'prize', 'referral', 'path_step')
                                    then l.note end,
                       'at', l.created_at) order by l.created_at desc)
              from (select * from cauris_ledger where org_id = p_org_id
                     order by created_at desc limit 60) l
              left join cauris_rules r on r.key = l.reason), '[]'::jsonb),
        'rules', coalesce((
            select jsonb_agg(jsonb_build_object('key', key, 'points', points,
                       'daily_cap', daily_cap, 'label', label) order by sort)
              from cauris_rules where points > 0), '[]'::jsonb)
    );
end;
$$;

-- ------------------------------------------------------------
-- 10. Grants
-- ------------------------------------------------------------
revoke execute on function path_goal(uuid, text)          from public;
revoke execute on function path_progress(uuid, text)      from public;
revoke execute on function path_text(text, text, text)    from public;
revoke execute on function path_sync(uuid)                from public;
revoke execute on function path_state(uuid)               from public;
revoke execute on function path_locked(uuid, text)        from public;
revoke execute on function path_lock_message(text)        from public;
revoke execute on function unlock_message(text)           from public;
revoke execute on function org_progress(uuid)             from public;
revoke execute on function trg_check_unlocks()            from public;
revoke execute on function my_cauris(uuid)                from public;
revoke all on table path_steps    from public;
revoke all on table org_path_done from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function path_goal(uuid, text)       from anon;
        revoke execute on function path_progress(uuid, text)   from anon;
        revoke execute on function path_text(text, text, text) from anon;
        revoke execute on function path_sync(uuid)             from anon;
        revoke execute on function path_state(uuid)            from anon;
        revoke execute on function path_locked(uuid, text)     from anon;
        revoke execute on function path_lock_message(text)     from anon;
        revoke execute on function unlock_message(text)        from anon;
        revoke execute on function org_progress(uuid)          from anon;
        revoke execute on function trg_check_unlocks()         from anon;
        revoke execute on function my_cauris(uuid)             from anon;
        revoke all on table path_steps    from anon;
        revoke all on table org_path_done from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- The engine is the database's own: nobody calls it from an app.
        revoke execute on function path_goal(uuid, text)       from authenticated;
        revoke execute on function path_progress(uuid, text)   from authenticated;
        revoke execute on function path_text(text, text, text) from authenticated;
        revoke execute on function path_sync(uuid)             from authenticated;
        revoke execute on function unlock_message(text)        from authenticated;
        revoke execute on function trg_check_unlocks()         from authenticated;
        grant execute on function path_state(uuid)             to authenticated;
        -- As 089: the triggers call these as the writer.
        grant execute on function path_locked(uuid, text)      to authenticated;
        grant execute on function path_lock_message(text)      to authenticated;
        grant execute on function my_cauris(uuid)              to authenticated;
        revoke insert, update, delete on table path_steps    from authenticated;
        revoke insert, update, delete on table org_path_done from authenticated;
        grant select on table path_steps    to authenticated;
        grant select on table org_path_done to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
