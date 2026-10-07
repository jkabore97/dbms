-- ============================================================
-- 096_unlock_notices.sql — « Factures débloquées ! »: the business hears
-- when a tool on its path opens.
--
-- The owner: « User should get a notification when a feature is
-- unlocked. » The path (089) opens invoices at a 70 % vitrine, production
-- at 90 %, the credit book after three finished orders — and until now
-- said nothing when it happened: the lock was simply gone the next time
-- somebody looked.
--
--   * org_unlocks keeps, per business, each step the path has opened and
--     when its admins saw the celebration. One row per step, ever: a step
--     that closes again (a photo taken off) and reopens is not news twice.
--   * check_unlocks(org) adds the steps that are open now and were not
--     before, and for each rings the admins' bell (notify_org_admins, so
--     the push of 060 follows). Only a Free shop or farm walks the path;
--     Mara Pro and every other profile have nothing to open.
--   * Triggers call it after what moves the path: an article published,
--     withdrawn or photographed, the vitrine's words, phone, address or
--     pin, an order finished. Each swallows its own failure — a bell must
--     never cost the write that rang it.
--   * unseen_unlocks(org) / mark_unlocks_seen(org): the home shows the
--     celebration once, to an admin, then forgets it.
--
-- What is open today is recorded as already seen: nobody is told on the
-- day this ships about a door that opened last month.
--
-- No destructive statement: one new table, new functions and triggers.
-- ============================================================

create table if not exists org_unlocks (
    org_id      uuid not null references orgs(id) on delete cascade,
    step        text not null check (step in ('invoices', 'production', 'credits')),
    unlocked_at timestamptz not null default now(),
    seen_at     timestamptz,
    primary key (org_id, step)
);

comment on table org_unlocks is
    'Each path step (089) a business has opened, once, and when its admins saw it (096).';

alter table org_unlocks enable row level security;

drop policy if exists org_unlocks_read on org_unlocks;
create policy org_unlocks_read on org_unlocks
    for select using (is_org_member(org_id));

-- What the bell says.
create or replace function unlock_message(p_step text)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select case p_step
        when 'invoices'   then 'Factures débloquées : votre vitrine a atteint '
                               || cauris_param('progress_invoices_pct', 70) || ' %.'
        when 'production' then 'Production débloquée : votre vitrine a atteint '
                               || cauris_param('progress_production_pct', 90) || ' %.'
        when 'credits'    then 'Carnet de crédit débloqué : '
                               || cauris_param('progress_credit_orders', 3)
                               || ' commandes terminées.'
        else 'Un outil est débloqué.'
    end;
$$;

-- The steps open now and not before: recorded, and the admins told.
create or replace function check_unlocks(p_org_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_profile text;
    v_step    text;
    v_made    integer := 0;
begin
    select o.profile::text into v_profile from orgs o where o.id = p_org_id;
    if v_profile is null or v_profile not in ('retail', 'farm')
       or org_plan(p_org_id) = 'pro' then
        return 0;
    end if;
    -- All three already open: one index lookup, the common case.
    if (select count(*) from org_unlocks u where u.org_id = p_org_id) >= 3 then
        return 0;
    end if;
    foreach v_step in array array['invoices', 'production', 'credits'] loop
        if not exists (select 1 from org_unlocks u
                        where u.org_id = p_org_id and u.step = v_step)
           and not path_locked(p_org_id, v_step) then
            insert into org_unlocks (org_id, step) values (p_org_id, v_step)
                on conflict do nothing;
            if found then
                v_made := v_made + 1;
                perform notify_org_admins(p_org_id, 'unlock', unlock_message(v_step));
            end if;
        end if;
    end loop;
    return v_made;
end;
$$;

-- After what moves the path. The business is new.org_id on every table
-- but orgs, where it is the row itself.
create or replace function trg_check_unlocks()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org uuid;
begin
    if tg_table_name = 'orgs' then
        v_org := new.id;
    elsif tg_op = 'DELETE' then
        v_org := old.org_id;
    else
        v_org := new.org_id;
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
    after update of storefront_blurb, phone, address, lat, lng, plan on orgs
    for each row execute function trg_check_unlocks();

drop trigger if exists orders_check_unlocks on orders;
create trigger orders_check_unlocks
    after insert or update of status on orders
    for each row execute function trg_check_unlocks();

-- The celebration on the home: once, to an admin.
create or replace function unseen_unlocks(p_org_id uuid)
returns setof text
language sql
stable
security definer
set search_path = public
as $$
    select u.step from org_unlocks u
     where u.org_id = p_org_id and u.seen_at is null and is_org_admin(p_org_id)
     order by u.unlocked_at, u.step;
$$;

create or replace function mark_unlocks_seen(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not is_org_admin(p_org_id) then
        raise exception 'Only an administrator sees the unlocks';
    end if;
    update org_unlocks set seen_at = now()
     where org_id = p_org_id and seen_at is null;
end;
$$;

-- What is open today was open before this shipped: recorded as seen,
-- nobody told.
insert into org_unlocks (org_id, step, unlocked_at, seen_at)
select o.id, s.step, now(), now()
  from orgs o
 cross join unnest(array['invoices', 'production', 'credits']) as s(step)
 where not path_locked(o.id, s.step)
on conflict do nothing;

revoke execute on function unlock_message(text)       from public;
revoke execute on function check_unlocks(uuid)        from public;
revoke execute on function trg_check_unlocks()        from public;
revoke execute on function unseen_unlocks(uuid)       from public;
revoke execute on function mark_unlocks_seen(uuid)    from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function unlock_message(text)    from anon;
        revoke execute on function check_unlocks(uuid)     from anon;
        revoke execute on function trg_check_unlocks()     from anon;
        revoke execute on function unseen_unlocks(uuid)    from anon;
        revoke execute on function mark_unlocks_seen(uuid) from anon;
        revoke all on table org_unlocks from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function unlock_message(text)    from authenticated;
        revoke execute on function check_unlocks(uuid)     from authenticated;
        revoke execute on function trg_check_unlocks()     from authenticated;
        grant execute on function unseen_unlocks(uuid)     to authenticated;
        grant execute on function mark_unlocks_seen(uuid)  to authenticated;
        revoke insert, update, delete on table org_unlocks from authenticated;
        grant select on table org_unlocks to authenticated;
    end if;
end $$;
