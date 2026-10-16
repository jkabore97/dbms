-- ============================================================
-- 148_association_members.sql — batch 152: an association's « Membres »
-- and its « Analyses » (a legacy 'church' org is an association and gets
-- the same).
--
-- Until now church_members (002) was written by the first setup alone
-- (102's add_association_member, three members) and read by « Relevé de
-- dons » and Recette's « De qui ? ». There was no way to add a fourth
-- member, correct a name or take somebody off the list. The members are
-- records, not app users: they take no seat and need no Pro.
--
--   1. church_members gains `note` (optional, 80 characters: « Trésorier »,
--      « Section jeunes ») and `removed_at` (when « Retirer » was pressed).
--      Removing is soft: is_active goes false, the row stays, and every
--      entry attributed to the member (contribution_attributions) stays
--      theirs — the giving statement and the history still find it.
--   2. Who writes: 002's « members writable by non-observers » was FOR ALL,
--      so a hard DELETE was open to every writer — and a delete cascades
--      to contribution_attributions, quietly un-naming every gift the
--      member ever made. It is replaced by an INSERT and an UPDATE policy
--      (the same people: a member of the business who is not an observer
--      or an approver, in a business that is not suspended — 049's
--      can_write_org), and no DELETE policy: nobody deletes a member
--      through the API. The business's own deletion (014/128, definer)
--      still clears its rows. A guard trigger keeps a member in its
--      business (org_id never changes), trims the name (required) and the
--      note, keeps the phone to digits and « + », refuses a date of joining
--      in the future, and dates the removal.
--   3. save_association_member(org, id, name, phone, note, joined_on,
--      allow_same_phone) — add (id null) or edit; SECURITY INVOKER, so the
--      policies above decide. The same phone as another active member is
--      refused (errcode MA148, the other member's name in the message)
--      unless allow_same_phone: the app warns, the person decides.
--      remove_association_member(id): the soft removal, INVOKER too.
--   4. association_members(org, year) — the list: each active member with
--      this year's total given (every income attributed to them through
--      record_entry's p_member_id, 007), its cotisations and dons, the
--      last gift, and where they stand on the usual cotisation (134's
--      contribution_defaults) — association_member_dues(org). INVOKER:
--      the amounts are read under RLS, so they are given to a caller with
--      full visibility only (006: attributions are line detail); anybody
--      else in the business gets the names and nulls.
--      association_member_history(member) — every gift of one member, all
--      years, newest first, with whether it was undone. INVOKER, the same.
--   5. Where a member stands (association_member_dues): counted from the
--      later of the day they joined and the day they were entered in
--      Marakaj (no debt is invented for years the app never saw), one
--      cotisation of the usual amount per period (week, month, year).
--      What they paid in cotisations (entries filed under « Cotisations »,
--      not undone) covers floor(paid / amount) periods from that start:
--        * every period up to the current one covered → 'up_to_date';
--        * all but the current one → 'due' (this period not paid yet —
--          not late: on the 3rd of the month nobody is « en retard »);
--        * otherwise 'late', late_since = the first period not covered.
--      No usual cotisation: no status at all.
--   6. association_analytics(org, from, to) → jsonb, INVOKER, path pinned,
--      authenticated only: money in and out by month for the last 12
--      months and the money held at each month's end; income and expenses
--      by category over the period (every account, « Dîme » and any
--      « Autre » the association named); the members (how many, how many
--      gave in the period, up to date / due / late, new per month); the
--      top givers for the business's administrators only. A caller with
--      'summary' visibility gets the totals only — the months and the
--      balance, through the report functions that already decide what a
--      summary may see (income_statement, balance_sheet), the member count
--      — and nulls for every line. Gated like the farm's (101/104): the
--      'reports' dial, the switchboard ('analytics', now offered for an
--      association too) and Marakaj Pro (pro_locked 'analytics').
--   7. A gift undone (reverse_entry, « Annuler ») is no longer on the
--      member's « Relevé de dons »: member_giving_statement's core (006)
--      read the original entry's credit whatever had become of it.
--
-- Shops and farms: nothing (their customers and analyses are their own);
-- every function here refuses a business that is not an association.
--
-- Apply after 147. Re-runnable (the bundle runs twice): columns if not
-- exists, constraints, policies and triggers dropped and recreated,
-- functions replaced in place, the catalog row upserted.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The member's note and removal
-- ------------------------------------------------------------
alter table church_members add column if not exists note text;
alter table church_members add column if not exists removed_at timestamptz;

alter table church_members drop constraint if exists church_members_note_length;
alter table church_members add constraint church_members_note_length
    check (note is null or char_length(note) <= 80);

comment on column church_members.note is
    'A word about the member (148): « Trésorier », « Section jeunes ». Optional, 80 characters.';
comment on column church_members.removed_at is
    'When the member was taken off the list (148). The row stays: their entries keep their name.';

create index if not exists church_members_org_phone
    on church_members (org_id, phone) where is_active and phone is not null;

-- ------------------------------------------------------------
-- 2. Who writes, and what is kept
-- ------------------------------------------------------------
drop policy if exists "members writable by non-observers" on church_members;

drop policy if exists "members added by writers" on church_members;
create policy "members added by writers"
on church_members for insert
with check (
    can_write_org(org_id)
    and exists (
        select 1 from memberships m
        where m.user_id = auth.uid()
          and m.org_id = church_members.org_id
          and m.role not in ('observer', 'approver')
    )
);

drop policy if exists "members changed by writers" on church_members;
create policy "members changed by writers"
on church_members for update
using (
    can_write_org(org_id)
    and exists (
        select 1 from memberships m
        where m.user_id = auth.uid()
          and m.org_id = church_members.org_id
          and m.role not in ('observer', 'approver')
    )
)
with check (
    can_write_org(org_id)
    and exists (
        select 1 from memberships m
        where m.user_id = auth.uid()
          and m.org_id = church_members.org_id
          and m.role not in ('observer', 'approver')
    )
);

-- No delete policy, on purpose: see the header (a delete would un-name
-- every gift the member made).

create or replace function trg_church_member_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    if tg_op = 'UPDATE' and new.org_id is distinct from old.org_id then
        raise exception 'Un membre reste dans son association.';
    end if;
    new.full_name := nullif(btrim(coalesce(new.full_name, '')), '');
    if new.full_name is null then
        raise exception 'Le nom du membre, s''il vous plaît.';
    end if;
    if char_length(new.full_name) > 120 then
        raise exception 'Un nom de 120 caractères au plus, s''il vous plaît.';
    end if;
    new.phone := nullif(regexp_replace(coalesce(new.phone, ''), '[^0-9+]', '', 'g'), '');
    new.note := nullif(btrim(coalesce(new.note, '')), '');
    if new.joined_on is not null
       and new.joined_on > (now() at time zone 'Africa/Ouagadougou')::date + 1 then
        raise exception 'La date d''arrivée ne peut pas être dans le futur.';
    end if;
    if new.is_active then
        new.removed_at := null;
    elsif tg_op = 'INSERT' or old.is_active then
        new.removed_at := coalesce(new.removed_at, now());
    end if;
    return new;
end;
$$;

drop trigger if exists church_member_guard on church_members;
create trigger church_member_guard
before insert or update on church_members
for each row execute function trg_church_member_guard();

-- ------------------------------------------------------------
-- 3. Add, edit, remove
-- ------------------------------------------------------------
create or replace function save_association_member(
    p_org_id           uuid,
    p_member_id        uuid    default null,
    p_full_name        text    default null,
    p_phone            text    default null,
    p_note             text    default null,
    p_joined_on        date    default null,
    p_allow_same_phone boolean default false
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
    v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), '');
    v_other text;
    v_id    uuid;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord.';
    end if;
    if not exists (select 1 from orgs where id = p_org_id
                      and profile::text in ('association', 'church')) then
        raise exception 'Réservé aux associations';
    end if;
    if char_length(coalesce(btrim(p_note), '')) > 80 then
        raise exception 'Une note de 80 caractères au plus, s''il vous plaît.';
    end if;
    if v_phone is not null and not coalesce(p_allow_same_phone, false) then
        select full_name into v_other from church_members
         where org_id = p_org_id and phone = v_phone and is_active
           and id is distinct from p_member_id
         order by created_at limit 1;
        if found then
            raise exception 'Ce numéro est déjà celui de %.', v_other
                using errcode = 'MA148';
        end if;
    end if;
    if p_member_id is null then
        insert into church_members (org_id, full_name, phone, note, joined_on)
        values (p_org_id, p_full_name, v_phone, p_note,
                coalesce(p_joined_on, (now() at time zone 'Africa/Ouagadougou')::date))
        returning id into v_id;
        return v_id;
    end if;
    update church_members
       set full_name = p_full_name,
           phone     = v_phone,
           note      = p_note,
           joined_on = coalesce(p_joined_on, joined_on)
     where id = p_member_id and org_id = p_org_id and is_active
    returning id into v_id;
    if v_id is null then
        raise exception 'Ce membre n''est pas modifiable.';
    end if;
    return v_id;
end;
$$;

create or replace function remove_association_member(p_member_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord.';
    end if;
    update church_members set is_active = false
     where id = p_member_id and is_active;
    if not found then
        raise exception 'Ce membre n''est pas modifiable.';
    end if;
end;
$$;

-- ------------------------------------------------------------
-- 5. Where each member stands on the usual cotisation
-- ------------------------------------------------------------
-- One row per active member of an association with a usual cotisation.
-- Read under the caller's RLS: without full visibility the attributions
-- are not readable and nothing is answered (the callers return nulls).
create or replace function association_member_dues(p_org_id uuid)
returns table (
    member_id    uuid,
    status       text,
    late_since   date,
    paid_through date,
    owed_periods int,
    covered      int
)
language sql
stable
security invoker
set search_path = public
as $$
    with d as (
        select c.amount, c.period,
               case c.period when 'week' then interval '1 week'
                             when 'month' then interval '1 month'
                             else interval '1 year' end as step,
               (now() at time zone 'Africa/Ouagadougou')::date as today
          from contribution_defaults c
         where c.org_id = p_org_id
           and has_full_visibility(p_org_id)
    ),
    m as (
        select cm.id,
               date_trunc(d.period,
                   greatest(coalesce(cm.joined_on, (cm.created_at at time zone 'Africa/Ouagadougou')::date),
                            (cm.created_at at time zone 'Africa/Ouagadougou')::date))::date as start_p,
               date_trunc(d.period, d.today)::date as cur_p,
               d.amount, d.period, d.step
          from church_members cm cross join d
         where cm.org_id = p_org_id and cm.is_active
    ),
    paid as (
        select ca.member_id, sum(jl.credit - jl.debit) as amount
          from contribution_attributions ca
          join journal_entries je on je.id = ca.journal_entry_id
          join journal_lines jl on jl.journal_entry_id = je.id
          join accounts a on a.id = jl.account_id
         where je.org_id = p_org_id
           and a.type = 'income'
           and lower(btrim(a.name)) = 'cotisations'
           and je.reverses_entry_id is null
           and not exists (select 1 from journal_entries r where r.reverses_entry_id = je.id)
         group by ca.member_id
    ),
    n as (
        select m.id, m.start_p, m.cur_p, m.step,
               (case m.period
                    when 'week'  then ((m.cur_p - m.start_p) / 7)
                    when 'month' then ((extract(year from m.cur_p) - extract(year from m.start_p)) * 12
                                       + extract(month from m.cur_p) - extract(month from m.start_p))::int
                    else (extract(year from m.cur_p) - extract(year from m.start_p))::int
                end + 1)::int as owed,
               floor(greatest(coalesce(p.amount, 0), 0) / m.amount)::int as covered
          from m left join paid p on p.member_id = m.id
    )
    select n.id,
           case when n.covered >= n.owed then 'up_to_date'
                when n.covered = n.owed - 1 then 'due'
                else 'late' end,
           case when n.covered < n.owed - 1
                then (n.start_p + n.step * n.covered)::date end,
           case when n.covered > 0
                then ((n.start_p + n.step * n.covered)::date - 1) end,
           n.owed,
           n.covered
      from n;
$$;

-- ------------------------------------------------------------
-- 4. The list, and one member's history
-- ------------------------------------------------------------
create or replace function association_members(
    p_org_id uuid,
    p_year   int default null
)
returns table (
    id               uuid,
    full_name        text,
    phone            text,
    note             text,
    joined_on        date,
    created_at       timestamptz,
    given_year       numeric,
    cotisations_year numeric,
    dons_year        numeric,
    last_given_on    date,
    dues_status      text,
    late_since       date,
    paid_through     date
)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
    v_year int := coalesce(p_year, extract(year from (now() at time zone 'Africa/Ouagadougou'))::int);
    v_full boolean := has_full_visibility(p_org_id);
begin
    if not exists (select 1 from orgs o where o.id = p_org_id
                      and o.profile::text in ('association', 'church')) then
        raise exception 'Réservé aux associations';
    end if;
    return query
    with gifts as (
        select ca.member_id,
               (je.created_at at time zone 'Africa/Ouagadougou')::date as day,
               lower(btrim(a.name)) as account,
               jl.credit - jl.debit as amount
          from contribution_attributions ca
          join journal_entries je on je.id = ca.journal_entry_id
          join journal_lines jl on jl.journal_entry_id = je.id
          join accounts a on a.id = jl.account_id
         where v_full
           and je.org_id = p_org_id
           and a.type = 'income'
           and je.reverses_entry_id is null
           and not exists (select 1 from journal_entries r where r.reverses_entry_id = je.id)
    ),
    sums as (
        select g.member_id,
               sum(g.amount) filter (where extract(year from g.day) = v_year) as given,
               sum(g.amount) filter (where extract(year from g.day) = v_year
                                       and g.account = 'cotisations') as cotis,
               sum(g.amount) filter (where extract(year from g.day) = v_year
                                       and g.account = 'donations') as dons,
               max(g.day) as last_day
          from gifts g
         group by g.member_id
    )
    select cm.id, cm.full_name, cm.phone, cm.note, cm.joined_on, cm.created_at,
           case when v_full then coalesce(s.given, 0) end,
           case when v_full then coalesce(s.cotis, 0) end,
           case when v_full then coalesce(s.dons, 0) end,
           s.last_day,
           dd.status, dd.late_since, dd.paid_through
      from church_members cm
      left join sums s on s.member_id = cm.id
      left join association_member_dues(p_org_id) dd on dd.member_id = cm.id
     where cm.org_id = p_org_id and cm.is_active
     order by lower(cm.full_name), cm.created_at;
end;
$$;

create or replace function association_member_history(p_member_id uuid)
returns table (
    entry_id     uuid,
    occurred_on  date,
    account_name text,
    kind         text,
    amount       numeric,
    reversed     boolean
)
language sql
stable
security invoker
set search_path = public
as $$
    select je.id,
           (je.created_at at time zone 'Africa/Ouagadougou')::date,
           a.name,
           case lower(btrim(a.name)) when 'cotisations' then 'cotisation'
                                     when 'donations' then 'don'
                                     else 'autre' end,
           jl.credit - jl.debit,
           exists (select 1 from journal_entries r where r.reverses_entry_id = je.id)
      from contribution_attributions ca
      join church_members cm on cm.id = ca.member_id
      join journal_entries je on je.id = ca.journal_entry_id
      join journal_lines jl on jl.journal_entry_id = je.id
      join accounts a on a.id = jl.account_id
     where ca.member_id = p_member_id
       and has_full_visibility(cm.org_id)
       and a.type = 'income'
       and je.reverses_entry_id is null
     order by je.created_at desc, je.id;
$$;

-- ------------------------------------------------------------
-- 6. The analyses
-- ------------------------------------------------------------
insert into feature_catalog (key, label, grp, kinds, pro_tool, sort) values
    ('analytics', 'Analyses', 'Rapports', '{retail,farm,association}', 'analytics', 70)
on conflict (key) do update
    set label    = excluded.label,
        grp      = excluded.grp,
        kinds    = excluded.kinds,
        pro_tool = excluded.pro_tool,
        sort     = excluded.sort;

create or replace function association_analytics(
    p_org_id uuid,
    p_from   date default null,
    p_to     date default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
    v_tz     constant text := 'Africa/Ouagadougou';
    v_today  date := (now() at time zone v_tz)::date;
    v_m0     date := (date_trunc('month', (now() at time zone v_tz)) - interval '11 months')::date;
    v_from   date := coalesce(p_from, '-infinity'::date);
    v_to     date := coalesce(p_to, 'infinity'::date);
    v_full   boolean;
    v_admin  boolean;
    v_months jsonb;
    v_m      date;
    v_in     numeric;
    v_out    numeric;
    v_bal    numeric;
    v_out_j  jsonb;
begin
    if auth.uid() is null or not is_org_member(p_org_id) then
        raise exception 'Réservé aux membres de l''association';
    end if;
    if not exists (select 1 from orgs o where o.id = p_org_id
                      and o.profile::text in ('association', 'church')) then
        raise exception 'Réservé aux associations';
    end if;
    perform require_feature(p_org_id, 'reports');
    perform feature_guard(p_org_id, 'analytics');
    if pro_locked(p_org_id, 'analytics') then
        raise exception 'Marakaj Pro : les analyses font partie de Marakaj Pro. Ouvrez Compte › Marakaj Pro, ou débloquez-les avec vos cauris.';
    end if;
    v_full  := has_full_visibility(p_org_id);
    v_admin := is_org_admin(p_org_id);

    if v_full then
        -- Every line is readable: the months straight from the books.
        with months as (
            select generate_series(v_m0, date_trunc('month', v_today)::date, interval '1 month')::date as m
        ),
        lines as (
            select (je.created_at at time zone v_tz)::date as day, a.type, jl.debit, jl.credit
              from journal_lines jl
              join journal_entries je on je.id = jl.journal_entry_id
              join accounts a on a.id = jl.account_id
             where je.org_id = p_org_id
        )
        select jsonb_agg(jsonb_build_object(
                   'month', to_char(mo.m, 'YYYY-MM-DD'),
                   'income', coalesce((select sum(l.credit - l.debit) from lines l
                                        where l.type = 'income' and l.day >= mo.m
                                          and l.day < (mo.m + interval '1 month')::date), 0),
                   'expenses', coalesce((select sum(l.debit - l.credit) from lines l
                                          where l.type = 'expense' and l.day >= mo.m
                                            and l.day < (mo.m + interval '1 month')::date), 0),
                   'balance', coalesce((select sum(l.debit - l.credit) from lines l
                                         where l.type = 'asset'
                                           and l.day < (mo.m + interval '1 month')::date), 0))
               order by mo.m)
          into v_months
          from months mo;
    else
        -- A summary: the totals the report functions already give it.
        v_months := '[]'::jsonb;
        for v_m in select generate_series(v_m0, date_trunc('month', v_today)::date, interval '1 month')::date loop
            begin
                select coalesce(sum(s.amount) filter (where s.section = 'total' and s.code = '1'), 0),
                       coalesce(sum(s.amount) filter (where s.section = 'total' and s.code = '2'), 0)
                  into v_in, v_out
                  from income_statement(p_org_id, v_m, (v_m + interval '1 month' - interval '1 day')::date) s;
                select coalesce(sum(b.amount) filter (where b.section = 'total' and b.code = '1'), 0)
                  into v_bal
                  from balance_sheet(p_org_id, (v_m + interval '1 month' - interval '1 day')::date) b;
            exception when others then
                v_in := null; v_out := null; v_bal := null;
            end;
            v_months := v_months || jsonb_build_object(
                'month', to_char(v_m, 'YYYY-MM-DD'),
                'income', v_in, 'expenses', v_out, 'balance', v_bal);
        end loop;
    end if;

    with lines as (
        select a.id as account_id, a.code, a.name, a.type, jl.debit, jl.credit, je.id as entry_id,
               -- An entry undone and its undoing net to nothing in the
               -- amounts; neither is counted as an entry.
               (je.reverses_entry_id is not null
                or exists (select 1 from journal_entries r where r.reverses_entry_id = je.id)) as undone
          from journal_lines jl
          join journal_entries je on je.id = jl.journal_entry_id
          join accounts a on a.id = jl.account_id
         where v_full
           and je.org_id = p_org_id
           and a.type in ('income', 'expense')
           and (je.created_at at time zone v_tz)::date between v_from and v_to
    ),
    gifts as (
        select ca.member_id, sum(jl.credit - jl.debit) as amount
          from contribution_attributions ca
          join journal_entries je on je.id = ca.journal_entry_id
          join journal_lines jl on jl.journal_entry_id = je.id
          join accounts a on a.id = jl.account_id
          join church_members cm on cm.id = ca.member_id
         where v_full
           and je.org_id = p_org_id
           and a.type = 'income'
           and je.reverses_entry_id is null
           and not exists (select 1 from journal_entries r where r.reverses_entry_id = je.id)
           and (je.created_at at time zone v_tz)::date between v_from and v_to
         group by ca.member_id
        having sum(jl.credit - jl.debit) > 0
    ),
    dues as (
        select * from association_member_dues(p_org_id)
    )
    select jsonb_build_object(
        'full', v_full,
        'admin', v_admin,
        'months', coalesce(v_months, '[]'::jsonb),
        'income', case when v_full then coalesce((
            select jsonb_agg(jsonb_build_object('account_id', x.account_id, 'code', x.code,
                                                'name', x.name, 'amount', x.amount, 'entries', x.n)
                             order by x.amount desc, x.name)
              from (select l.account_id, l.code, l.name, sum(l.credit - l.debit) as amount,
                           count(distinct l.entry_id) filter (where not l.undone) as n
                      from lines l where l.type = 'income'
                     group by l.account_id, l.code, l.name
                    having sum(l.credit - l.debit) <> 0) x), '[]'::jsonb) end,
        'expenses', case when v_full then coalesce((
            select jsonb_agg(jsonb_build_object('account_id', x.account_id, 'code', x.code,
                                                'name', x.name, 'amount', x.amount, 'entries', x.n)
                             order by x.amount desc, x.name)
              from (select l.account_id, l.code, l.name, sum(l.debit - l.credit) as amount,
                           count(distinct l.entry_id) filter (where not l.undone) as n
                      from lines l where l.type = 'expense'
                     group by l.account_id, l.code, l.name
                    having sum(l.debit - l.credit) <> 0) x), '[]'::jsonb) end,
        'members', jsonb_build_object(
            'registered', (select count(*) from church_members cm
                            where cm.org_id = p_org_id and cm.is_active),
            'gave', case when v_full then (select count(*) from gifts g
                                             join church_members cm on cm.id = g.member_id
                                            where cm.is_active) end,
            'has_dues', exists (select 1 from contribution_defaults c where c.org_id = p_org_id),
            'up_to_date', case when v_full then (select count(*) from dues where status = 'up_to_date') end,
            'due',        case when v_full then (select count(*) from dues where status = 'due') end,
            'late',       case when v_full then (select count(*) from dues where status = 'late') end,
            'new_by_month', (
                select jsonb_agg(jsonb_build_object('month', to_char(mo.m, 'YYYY-MM-DD'),
                                                    'count', (select count(*) from church_members cm
                                                               where cm.org_id = p_org_id
                                                                 and date_trunc('month', coalesce(cm.joined_on,
                                                                       (cm.created_at at time zone v_tz)::date))::date = mo.m))
                                 order by mo.m)
                  from (select generate_series(v_m0, date_trunc('month', v_today)::date,
                                               interval '1 month')::date as m) mo)),
        'top_givers', case when v_full and v_admin then coalesce((
            select jsonb_agg(jsonb_build_object('member_id', t.member_id, 'name', t.full_name,
                                                'amount', t.amount)
                             order by t.amount desc, t.full_name)
              from (select g.member_id, cm.full_name, g.amount
                      from gifts g join church_members cm on cm.id = g.member_id
                     where cm.is_active
                     order by g.amount desc, cm.full_name
                     limit 10) t), '[]'::jsonb) end
    ) into v_out_j;

    return v_out_j;
end;
$$;

-- ------------------------------------------------------------
-- 7. The giving statement leaves an undone gift out
-- ------------------------------------------------------------
-- 006's body (kept by 069 as the core behind its guard), with the entry
-- undone (reverse_entry) left out. Its owner and grants are kept by
-- create or replace (069 closed the core to every app role).
create or replace function member_giving_statement_core(
    p_member_id uuid,
    p_year      int default extract(year from current_date)::int
)
returns table (contribution_date date, kind text, amount numeric)
language sql
stable
security definer
set search_path = public, auth
as $$
    select je.created_at::date, a.name, jl.credit
    from contribution_attributions ca
    join church_members cm on cm.id = ca.member_id
    join journal_entries je on je.id = ca.journal_entry_id
    join journal_lines jl on jl.journal_entry_id = je.id
    join accounts a on a.id = jl.account_id
    where ca.member_id = p_member_id
      and has_full_visibility(cm.org_id)
      and a.type = 'income'
      and jl.credit > 0
      and extract(year from je.created_at) = p_year
      and not exists (select 1 from journal_entries r where r.reverses_entry_id = je.id)
    order by 1;
$$;

-- ------------------------------------------------------------
-- Grants: the app's doors to authenticated, nothing to anon or PUBLIC.
-- ------------------------------------------------------------
revoke execute on function trg_church_member_guard()                          from public;
revoke execute on function save_association_member(uuid, uuid, text, text, text, date, boolean) from public;
revoke execute on function remove_association_member(uuid)                    from public;
revoke execute on function association_member_dues(uuid)                      from public;
revoke execute on function association_members(uuid, integer)                 from public;
revoke execute on function association_member_history(uuid)                   from public;
revoke execute on function association_analytics(uuid, date, date)            from public;
-- Re-created above: closed again as 069 closed it (only its guard calls it).
revoke execute on function member_giving_statement_core(uuid, integer)        from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function trg_church_member_guard()                 from anon;
        revoke execute on function save_association_member(uuid, uuid, text, text, text, date, boolean) from anon;
        revoke execute on function remove_association_member(uuid)           from anon;
        revoke execute on function association_member_dues(uuid)             from anon;
        revoke execute on function association_members(uuid, integer)        from anon;
        revoke execute on function association_member_history(uuid)          from anon;
        revoke execute on function association_analytics(uuid, date, date)   from anon;
        revoke execute on function member_giving_statement_core(uuid, integer) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function trg_church_member_guard()                 from authenticated;
        revoke execute on function member_giving_statement_core(uuid, integer) from authenticated;
        grant execute on function save_association_member(uuid, uuid, text, text, text, date, boolean) to authenticated;
        grant execute on function remove_association_member(uuid)            to authenticated;
        -- Called as the caller by association_members and the analyses.
        grant execute on function association_member_dues(uuid)              to authenticated;
        grant execute on function association_members(uuid, integer)         to authenticated;
        grant execute on function association_member_history(uuid)           to authenticated;
        grant execute on function association_analytics(uuid, date, date)    to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
