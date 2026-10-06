-- ============================================================
-- 089_earned_locks.sql — tools are earned, for everyone, and the database
-- holds the door.
--
-- The owner: « I need users to earn their feature, so lock them till they
-- earn it » — no trial days, no business kept open because it was here
-- first. 085 drew the path in the app only, opened everything for seven
-- days, and left every business older than 085 ungated. Now, for shops
-- and farms alike:
--
--   invoices         the vitrine at 70 %
--   production       the vitrine at 90 %
--   credits          3 orders picked up or delivered
--   second_business  Mara Pro only
--
-- Locked means no new record: a business that already kept invoices,
-- production runs or debts still reads them all (the owner's choice:
-- « lock, keep reading »), and still collects what it is owed — paying
-- back a debt is never blocked. Pro opens the three tools at once (a
-- business paying for Pro is not asked to earn its free tools), and so
-- does « Mara Pro complet » bought with cauris, since org_plan() then
-- says pro. Associations and churches are not on this path.
--
-- The thresholds are platform settings. No destructive statement: the
-- triggers are created only where missing, functions replaced in place.
-- ============================================================

insert into platform_settings (key, value) values
    ('progress_invoices_pct',   '70'),
    ('progress_production_pct', '90'),
    ('progress_credit_orders',  '3')
on conflict (key) do nothing;

-- The one rule: is this step still ahead of the business?
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
        when p_step = 'invoices'
            then vitrine_score(o.id) < cauris_param('progress_invoices_pct', 70)
        when p_step = 'production'
            then vitrine_score(o.id) < cauris_param('progress_production_pct', 90)
        when p_step = 'credits'
            then (select count(*) from orders x
                   where x.org_id = o.id and x.status in ('picked_up', 'delivered'))
                 < cauris_param('progress_credit_orders', 3)
        else false
    end
    from orgs o where o.id = p_org_id;
$$;

-- What the refusal says, short.
create or replace function path_lock_message(p_step text)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select case p_step
        when 'invoices'   then 'Factures : vitrine à '
                               || cauris_param('progress_invoices_pct', 70) || ' % pour les débloquer.'
        when 'production' then 'Production : vitrine à '
                               || cauris_param('progress_production_pct', 90) || ' % pour la débloquer.'
        when 'credits'    then 'Carnet de crédit : '
                               || cauris_param('progress_credit_orders', 3)
                               || ' commandes terminées pour le débloquer.'
        when 'second_business' then 'Une deuxième entreprise : avec Mara Pro.'
        else 'Outil verrouillé.'
    end;
$$;

-- The door: a new invoice, production run or debt on a locked business is
-- refused. A server-side job (no signed-in caller) and Mara's own admins
-- pass — the rule is for the business, not for repairs.
create or replace function trg_path_lock()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is not null
       and not exists (select 1 from profiles where id = auth.uid() and is_platform_admin)
       and path_locked(new.org_id, tg_argv[0]) then
        raise exception '%', path_lock_message(tg_argv[0]);
    end if;
    return new;
end;
$$;

-- A second business: asking for one needs Pro on a business already owned.
-- The first business is free, as ever.
create or replace function trg_second_business_lock()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if exists (select 1 from profiles where id = new.applicant_id and is_platform_admin) then
        return new;
    end if;
    if exists (select 1 from memberships m join orgs o on o.id = m.org_id
                where m.user_id = new.applicant_id and m.role = 'owner'
                  and o.profile in ('retail', 'farm'))
       and not exists (select 1 from memberships m
                        where m.user_id = new.applicant_id and m.role = 'owner'
                          and org_plan(m.org_id) = 'pro') then
        raise exception '%', path_lock_message('second_business');
    end if;
    return new;
end;
$$;

do $$
begin
    if not exists (select 1 from pg_trigger where tgname = 'path_lock_invoices') then
        create trigger path_lock_invoices before insert on invoices
            for each row execute function trg_path_lock('invoices');
    end if;
    if not exists (select 1 from pg_trigger where tgname = 'path_lock_production') then
        create trigger path_lock_production before insert on production_runs
            for each row execute function trg_path_lock('production');
    end if;
    if not exists (select 1 from pg_trigger where tgname = 'path_lock_debts') then
        create trigger path_lock_debts before insert on debts
            for each row execute function trg_path_lock('credits');
    end if;
    if not exists (select 1 from pg_trigger where tgname = 'path_lock_second_business') then
        create trigger path_lock_second_business before insert on org_applications
            for each row execute function trg_second_business_lock();
    end if;
end $$;

-- What the app draws: the same rule, step by step, and how far each is.
-- 085's keys stay (gated, in_trial, score, orders…) so an older app reads
-- it; in_trial is never true again.
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
        'tools_pct',     cauris_param('progress_production_pct', 90),
        'invoices_pct',  cauris_param('progress_invoices_pct', 70),
        'production_pct', cauris_param('progress_production_pct', 90),
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

revoke execute on function path_locked(uuid, text)       from public;
revoke execute on function path_lock_message(text)       from public;
revoke execute on function trg_path_lock()               from public;
revoke execute on function trg_second_business_lock()    from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function path_locked(uuid, text)    from anon;
        revoke execute on function path_lock_message(text)    from anon;
        revoke execute on function trg_path_lock()            from anon;
        revoke execute on function trg_second_business_lock() from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- The triggers call these as the writer; they read nothing private
        -- beyond a yes or no about the writer's own business.
        grant execute on function path_locked(uuid, text)    to authenticated;
        grant execute on function path_lock_message(text)    to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
