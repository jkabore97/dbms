-- ============================================================
-- 088_association_trust.sql — the trust level of an association.
--
-- An association does not race and earns no cauris (084): ranking churches
-- and associations by what they raise would press the givers and reward
-- the loudest, not the most honest. What it climbs instead is a trust
-- level, read off its own books — never declared, never bought:
--
--   verified    Mara checked who they are (a platform admin's tick).
--   regular     money recorded in at least 6 of the last 8 weeks.
--   justified   at least 80 % of the last 90 days' expenses carry their
--               receipt (a document filed against the entry); at least
--               3 expenses, so an empty book proves nothing.
--   clean       corrections (reversals) under 10 % of the last 90 days'
--               entries.
--   lasting     six months on Mara.
--
-- Five pillars, four levels: Nouvelle (0–1), Régulière (2–3), Fiable (4),
-- Exemplaire (all five — so never without Mara's verification).
--
-- This is the level and nothing it opens yet: the fundraising vitrine and
-- Wave collection it is meant to unlock wait on the platform's decisions.
-- ============================================================

alter table orgs add column if not exists verified_at timestamptz;
alter table orgs add column if not exists verified_by uuid references profiles(id) on delete set null;

-- Mara's tick, or its removal. A platform admin only; who ticked is kept.
create or replace function set_org_verified(p_org_id uuid, p_verified boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Seul Mara peut vérifier une association';
    end if;
    if not exists (select 1 from orgs where id = p_org_id) then
        raise exception 'No such business';
    end if;
    update orgs
       set verified_at = case when p_verified then coalesce(verified_at, now()) end,
           verified_by = case when p_verified then coalesce(verified_by, auth.uid()) end
     where id = p_org_id;
end;
$$;

-- The five pillars and the level, for the association's own members (and
-- for Mara's admins). Null for anyone else and for a business: a shop's
-- standing is its cauris, not this.
create or replace function association_trust(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    o           orgs%rowtype;
    v_weeks     int;
    v_expenses  int;
    v_receipts  int;
    v_entries   int;
    v_reversals int;
    v_age_days  int;
    p_verified  boolean;
    p_regular   boolean;
    p_justified boolean;
    p_clean     boolean;
    p_lasting   boolean;
    v_met       int;
begin
    select * into o from orgs where id = p_org_id;
    if not found or o.profile not in ('church', 'association') then
        return null;
    end if;
    if not (is_org_member(p_org_id)
            or exists (select 1 from profiles where id = auth.uid() and is_platform_admin)) then
        return null;
    end if;

    select count(distinct date_trunc('week', je.created_at)) into v_weeks
      from journal_entries je
     where je.org_id = p_org_id and je.reverses_entry_id is null
       and je.created_at >= date_trunc('week', now()) - interval '7 weeks';

    select count(*), count(*) filter (where exists (
               select 1 from documents d where d.linked_journal_entry_id = je.id))
      into v_expenses, v_receipts
      from journal_entries je
     where je.org_id = p_org_id and je.reverses_entry_id is null
       and je.created_at >= now() - interval '90 days'
       and not exists (select 1 from journal_entries r where r.reverses_entry_id = je.id)
       and exists (select 1 from journal_lines jl join accounts a on a.id = jl.account_id
                    where jl.journal_entry_id = je.id and jl.debit > 0 and a.code like '5%');

    select count(*) filter (where je.reverses_entry_id is null),
           count(*) filter (where je.reverses_entry_id is not null)
      into v_entries, v_reversals
      from journal_entries je
     where je.org_id = p_org_id and je.created_at >= now() - interval '90 days';

    v_age_days := extract(day from now() - o.created_at)::int;

    p_verified  := o.verified_at is not null;
    p_regular   := v_weeks >= 6;
    p_justified := v_expenses >= 3 and v_receipts * 100 >= v_expenses * 80;
    p_clean     := v_entries >= 5 and v_reversals * 100 < v_entries * 10;
    p_lasting   := v_age_days >= 182;
    v_met := p_verified::int + p_regular::int + p_justified::int + p_clean::int + p_lasting::int;

    return jsonb_build_object(
        'level', case when v_met = 5 then 'Exemplaire'
                      when v_met = 4 then 'Fiable'
                      when v_met >= 2 then 'Régulière'
                      else 'Nouvelle' end,
        'met', v_met,
        'verified_at', o.verified_at,
        'pillars', jsonb_build_array(
            jsonb_build_object('key', 'verified', 'met', p_verified),
            jsonb_build_object('key', 'regular', 'met', p_regular,
                               'value', v_weeks, 'target', 6),
            jsonb_build_object('key', 'justified', 'met', p_justified,
                               'value', v_receipts, 'of', v_expenses),
            jsonb_build_object('key', 'clean', 'met', p_clean,
                               'value', v_reversals, 'of', v_entries),
            jsonb_build_object('key', 'lasting', 'met', p_lasting,
                               'value', v_age_days, 'target', 182)));
end;
$$;

revoke execute on function set_org_verified(uuid, boolean) from public;
revoke execute on function association_trust(uuid)        from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function set_org_verified(uuid, boolean) from anon;
        revoke execute on function association_trust(uuid)        from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function set_org_verified(uuid, boolean) to authenticated;
        grant execute on function association_trust(uuid)        to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
