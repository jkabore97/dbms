-- ============================================================
-- 091_first_setup.sql — a new business is walked through its first steps
-- before it opens.
--
-- The owner: « a new store owner be prompted for basic initial setup —
-- identity, add stock, vitrine and position — before they can access the
-- store interface ». orgs.setup_done_at records that the owner went
-- through it; until then the app shows the guided setup instead of the
-- home, to the business's admins (an employee is never stopped by it).
--
-- A business already selling is not sent back to the start: every shop or
-- farm with an article, or an open vitrine, is marked done here.
-- Associations, churches and generic businesses have no such setup.
--
-- feature_states() carries 'setup_done' to the app. No destructive
-- statement: a column, a backfill, functions replaced in place.
-- ============================================================

alter table orgs add column if not exists setup_done_at timestamptz;

update orgs o set setup_done_at = now()
 where setup_done_at is null
   and (o.profile not in ('retail', 'farm')
        or o.storefront_enabled
        or exists (select 1 from products p where p.org_id = o.id));

-- The owner (or an admin) says the first steps are done. The article is
-- the one step that cannot be skipped: a shop with nothing to sell is not
-- set up. The position may be left for later (and then earns no cauris
-- until it is set — the vitrine is only complete with it).
create or replace function finish_setup(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur termine la mise en route';
    end if;
    if not exists (select 1 from products where org_id = p_org_id and is_active) then
        raise exception 'Ajoutez d''abord un article.';
    end if;
    update orgs set setup_done_at = coalesce(setup_done_at, now()) where id = p_org_id;
end;
$$;

-- 090's states, with the first setup.
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
        'wave_allowed', coalesce((select wave_allowed from orgs where id = p_org_id), false),
        'setup_done', coalesce((select setup_done_at is not null from orgs where id = p_org_id), true)
    ) end;
$$;

revoke execute on function finish_setup(uuid)   from public;
revoke execute on function feature_states(uuid) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function finish_setup(uuid)   from anon;
        revoke execute on function feature_states(uuid) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function finish_setup(uuid)   to authenticated;
        grant execute on function feature_states(uuid) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
