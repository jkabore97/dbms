-- ============================================================
-- 102_association_setup.sql — a new association is walked through its
-- first minutes, as a shop and a farm are (091).
--
-- The owner: « Association walkthrough » — its name and its kind (a
-- tontine, a church, a groupement, a cultural or sports association, or
-- something else) with a line about it; its first three members (name and
-- phone — records, not app users: they take no seat and need no Pro) and/or
-- a WhatsApp invitation to share; optionally one service on the vitrine,
-- its phone and its area. Then a guide card « Encaissez la première
-- cotisation » on the home. Finishing sets orgs.setup_done_at, which earns
-- the one free worker (100).
--
--   1. orgs.association_kind: what the association is ('tontine', 'eglise',
--      'groupement', 'culturelle', 'sportive', 'autre'); null until said.
--      set_association_kind(org, kind, about) writes it, and the line about
--      it as the vitrine's sentence (052's storefront_blurb) — an admin's,
--      for an association or a legacy church only.
--   2. add_association_member(org, name, phone): one member record
--      (church_members, 002). SECURITY INVOKER on purpose: bound by 002's
--      RLS like a direct write (a member who is no observer). The same
--      phone twice in one association is the same member (its name is
--      updated), so a retried tap adds nobody twice.
--   3. Every association and church that exists now is set up: marked
--      done once (a marker in platform_settings, so a re-run never marks
--      an association still in its walkthrough). Nobody already there is
--      ever shown the walkthrough, and nobody loses a worker.
--   4. org_setup_done (100) counts an association's and a church's setup
--      as a shop's: setup_done_at. A generic business still has no
--      walkthrough, so it is done.
--   5. finish_setup (091): an association finishes with nothing required
--      (every step but its name may be skipped); a shop or a farm still
--      needs its first article.
--   6. feature_states (100): 'setup_done' is org_setup_done — it read the
--      column alone, so an association created after 091 was told « not
--      set up » (the Pro strip hid for it) while its team was told « done ».
--      'first_income' says, for an association or a church, whether any
--      money has come in (an income line, or a tontine payment) — the
--      home's guide card; null for the others.
--
-- Shops and farms: unchanged (finish_setup's article rule, their setup
-- mark, their walkthrough). Associations and churches: the walkthrough is
-- theirs from now on, for new ones only.
--
-- Re-runnable (the bundle runs twice): a column if not exists, a check
-- dropped and recreated, the marking guarded by its marker, functions
-- replaced in place.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The kind of association
-- ------------------------------------------------------------
alter table orgs add column if not exists association_kind text;
alter table orgs drop constraint if exists orgs_association_kind_check;
alter table orgs add constraint orgs_association_kind_check
    check (association_kind is null
           or association_kind in ('tontine', 'eglise', 'groupement', 'culturelle', 'sportive', 'autre'));

comment on column orgs.association_kind is
    'What an association is (102): tontine, eglise, groupement, culturelle, sportive, autre.';

-- ------------------------------------------------------------
-- 3. Every association already there is set up — once
-- ------------------------------------------------------------
do $$
begin
    if not exists (select 1 from platform_settings where key = 'association_setup_marked') then
        update orgs set setup_done_at = now()
         where setup_done_at is null
           and profile::text in ('association', 'church');
        insert into platform_settings (key, value) values ('association_setup_marked', to_jsonb(now()))
        on conflict (key) do nothing;
    end if;
end $$;

-- ------------------------------------------------------------
-- 4. The setup is behind the business
-- ------------------------------------------------------------
-- 100's, with an association's and a church's walkthrough: their mark, as
-- a shop's. A generic business has none, so it is done.
create or replace function org_setup_done(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((select o.setup_done_at is not null
                            or o.profile::text not in ('retail', 'farm', 'association', 'church')
                       from orgs o where o.id = p_org_id), false);
$$;

-- ------------------------------------------------------------
-- 1. Its name is update_org's (014); its kind and its line are here
-- ------------------------------------------------------------
create or replace function set_association_kind(
    p_org_id uuid,
    p_kind   text,
    p_about  text default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_kind text := nullif(lower(btrim(coalesce(p_kind, ''))), '');
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur termine la mise en route';
    end if;
    if not exists (select 1 from orgs where id = p_org_id
                      and profile::text in ('association', 'church')) then
        raise exception 'Réservé aux associations';
    end if;
    if v_kind is not null
       and v_kind not in ('tontine', 'eglise', 'groupement', 'culturelle', 'sportive', 'autre') then
        raise exception 'Type d''association inconnu';
    end if;
    update orgs
       set association_kind = coalesce(v_kind, association_kind),
           -- Null leaves the sentence alone (set_storefront's rule, 052).
           storefront_blurb = case when p_about is null then storefront_blurb
                                   else nullif(left(btrim(p_about), 160), '') end
     where id = p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- 2. A member: a record, not an account
-- ------------------------------------------------------------
create or replace function add_association_member(
    p_org_id    uuid,
    p_full_name text,
    p_phone     text default null
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
    v_name  text := nullif(btrim(coalesce(p_full_name, '')), '');
    v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), '');
    v_id    uuid;
begin
    if v_name is null then
        raise exception 'Le nom du membre, s''il vous plaît.';
    end if;
    if not is_org_member(p_org_id) then
        raise exception 'Réservé aux membres de l''association';
    end if;
    if not exists (select 1 from orgs where id = p_org_id
                      and profile::text in ('association', 'church')) then
        raise exception 'Réservé aux associations';
    end if;
    if v_phone is not null then
        select id into v_id from church_members
         where org_id = p_org_id and phone = v_phone and is_active
         order by created_at limit 1;
        if found then
            update church_members set full_name = v_name where id = v_id;
            return v_id;
        end if;
    end if;
    insert into church_members (org_id, full_name, phone, joined_on)
    values (p_org_id, v_name, v_phone, current_date)
    returning id into v_id;
    return v_id;
end;
$$;

-- ------------------------------------------------------------
-- 5. Finishing
-- ------------------------------------------------------------
-- 091's, with an association's: nothing is required of it. A shop or a
-- farm still opens with its first article.
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
    if exists (select 1 from orgs where id = p_org_id and profile::text in ('retail', 'farm'))
       and not exists (select 1 from products where org_id = p_org_id and is_active) then
        raise exception 'Ajoutez d''abord un article.';
    end if;
    update orgs set setup_done_at = coalesce(setup_done_at, now()) where id = p_org_id;
end;
$$;

-- ------------------------------------------------------------
-- 6. What the app reads
-- ------------------------------------------------------------
-- Money has come in: a contribution or any income line (002), or a
-- tontine payment (025). Reversals (an entry undone) are not an income.
create or replace function org_first_income(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (select 1
                     from journal_entries je
                     join journal_lines jl on jl.journal_entry_id = je.id
                     join accounts a on a.id = jl.account_id
                    where je.org_id = p_org_id
                      and je.reverses_entry_id is null
                      and a.type = 'income'
                      and jl.credit > 0
                      and not exists (select 1 from journal_entries r
                                       where r.reverses_entry_id = je.id))
        or exists (select 1 from tontine_contributions t where t.org_id = p_org_id);
$$;

-- 100's states, with the setup said as the team says it, and the
-- association's first income.
create or replace function feature_states(p_org_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not is_org_member(p_org_id) then
        return null;
    end if;
    perform cauris_expire(p_org_id);
    return jsonb_build_object(
        'plan', org_plan(p_org_id),
        'balance', cauris_balance(p_org_id),
        'tools', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'feature', c.feature,
                       'cost', c.cost,
                       'until', u.until,
                       'gift', u.gifted_by is not null,
                       'waits_days', case
                           when c.min_days > 0
                            and o.created_at > now() - make_interval(days => c.min_days)
                           then c.min_days - extract(day from now() - o.created_at)::int end
                   ) order by c.sort)
              from cauris_costs c
              cross join orgs o
              left join cauris_unlocks u
                on u.org_id = p_org_id and u.feature = c.feature and u.until > now()
             where o.id = p_org_id and c.feature <> 'photo_slot'), '[]'::jsonb),
        'progress', org_progress(p_org_id),
        'wave_allowed', coalesce((select wave_allowed from orgs where id = p_org_id), false),
        'setup_done', org_setup_done(p_org_id),
        'first_income', (select case when o.profile::text in ('association', 'church')
                                     then org_first_income(p_org_id) end
                           from orgs o where o.id = p_org_id),
        'promo', cauris_promo_left(p_org_id),
        'photos', photo_state(p_org_id),
        'team', team_seats(p_org_id)
    );
end;
$$;

-- ------------------------------------------------------------
-- Grants: born closed (063); each opened to whom it is for.
-- ------------------------------------------------------------
revoke execute on function org_setup_done(uuid)                       from public;
revoke execute on function set_association_kind(uuid, text, text)     from public;
revoke execute on function add_association_member(uuid, text, text)   from public;
revoke execute on function finish_setup(uuid)                         from public;
revoke execute on function org_first_income(uuid)                     from public;
revoke execute on function feature_states(uuid)                       from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function org_setup_done(uuid)                       from anon;
        revoke execute on function set_association_kind(uuid, text, text)     from anon;
        revoke execute on function add_association_member(uuid, text, text)   from anon;
        revoke execute on function finish_setup(uuid)                         from anon;
        revoke execute on function org_first_income(uuid)                     from anon;
        revoke execute on function feature_states(uuid)                       from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- The engine, read inside feature_states and the team's readers.
        revoke execute on function org_setup_done(uuid)                       from authenticated;
        revoke execute on function org_first_income(uuid)                     from authenticated;
        -- The app's doors; each checks who is asking.
        grant execute on function set_association_kind(uuid, text, text)      to authenticated;
        grant execute on function add_association_member(uuid, text, text)    to authenticated;
        grant execute on function finish_setup(uuid)                          to authenticated;
        grant execute on function feature_states(uuid)                        to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
