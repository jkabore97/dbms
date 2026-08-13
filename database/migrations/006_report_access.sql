-- ============================================================
-- 006_report_access.sql
--
-- M3 puts the reports on screen. Before they can be shown to anyone, two
-- things about who may read what have to be fixed.
--
-- 1. A LEAK. `church_account_activity` (002) is a view, and in Postgres 15+ a
--    view runs as its owner unless told otherwise. Its owner is the role that
--    created the tables, which bypasses RLS — so selecting from the view
--    returned every org's daily totals to anybody who asked, including a
--    caller holding nothing but the publishable key, which is public by
--    design and ships inside the web build.
--
--    Every policy in 004 was intact and none of them ever ran. The proof in
--    test_rls.sql was true and beside the point: it tested the tables, and
--    this was a view over them.
--
-- 2. VISIBILITY WAS DECORATION. `memberships.visibility` has meant 'summary'
--    since the first schema, and nothing enforced it. The observer granted
--    summary access — the quieter investor in the schema comment — could read
--    every individual transaction through the API whatever the app drew on
--    screen.
--
-- The second fix forces a change in the reports themselves. Once raw entries
-- are closed to a summary observer, a report that reads those tables as the
-- caller returns nothing at all — including the totals they ARE entitled to.
-- So the three report functions become SECURITY DEFINER and check entitlement
-- themselves: totals for any member, line items only with full visibility.
-- ============================================================

-- ------------------------------------------------------------
-- 1. THE VIEW
-- ------------------------------------------------------------
-- security_invoker makes the view run as whoever selects from it, so the
-- policies on journal_entries, journal_lines and accounts finally apply.
-- Nothing else about the view changes.
alter view church_account_activity set (security_invoker = on);

-- ------------------------------------------------------------
-- 2. WHAT 'summary' MEANS
-- ------------------------------------------------------------
-- Full visibility is held, not inferred: a person with several grants in one
-- org gets the widest of them, which is the same rule my_orgs() already uses
-- when it decides what to send the client.
create or replace function has_full_visibility(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select exists (
        select 1 from memberships m
        where m.user_id = auth.uid()
          and m.org_id = p_org_id
          and m.visibility = 'full'
    );
$$;

-- ------------------------------------------------------------
-- 3. LINE ITEMS ARE FOR FULL VISIBILITY ONLY
-- ------------------------------------------------------------
-- Each of these replaces a policy that asked only "are you in this org?".
-- Nothing is widened: every caller who could read these rows before and holds
-- full visibility still can.

drop policy if exists "read within your org" on journal_entries;

create policy "entries readable with full visibility"
on journal_entries for select
using (has_full_visibility(org_id));

drop policy if exists "lines readable with their entry" on journal_lines;

create policy "lines readable with full visibility"
on journal_lines for select
using (
    exists (
        select 1 from journal_entries je
        where je.id = journal_lines.journal_entry_id
          and has_full_visibility(je.org_id)
    )
);

drop policy if exists "attributions readable with their entry" on contribution_attributions;

-- Who gave what, by name. If anything in this schema is line-item detail,
-- it is this.
create policy "attributions readable with full visibility"
on contribution_attributions for select
using (
    exists (
        select 1 from journal_entries je
        where je.id = contribution_attributions.journal_entry_id
          and has_full_visibility(je.org_id)
    )
);

drop policy if exists "documents readable within org" on documents;

-- A receipt is a transaction with a photograph attached.
create policy "documents readable with full visibility"
on documents for select
using (has_full_visibility(org_id));

-- ------------------------------------------------------------
-- 4. THE REPORTS
-- ------------------------------------------------------------
-- SECURITY DEFINER, because a summary observer can no longer read the tables
-- these are computed from and is still entitled to the total. Each one
-- therefore checks entitlement itself rather than leaning on RLS underneath,
-- and each is gated inside the query so a non-member gets an empty result
-- instead of an error that would confirm the org exists.

-- Totals and per-account lines for the week. Any member may call it; the
-- caller decides how much of the answer to show, and RLS no longer can,
-- so the line detail is gated here too.
create or replace function church_weekly_summary(
    p_org_id uuid,
    p_week_ending date default current_date
)
returns table (
    category text,
    label    text,
    amount   numeric
)
language sql
stable
security definer
set search_path = public, auth
as $$
    with access as (
        select is_org_member(p_org_id) as member,
               has_full_visibility(p_org_id) as detailed
    ),
    window_bounds as (
        select (p_week_ending - interval '6 days')::date as start_date,
               p_week_ending as end_date
    ),
    lines as (
        select a.type, a.name, jl.debit, jl.credit
        from journal_entries je
        join journal_lines jl on jl.journal_entry_id = je.id
        join accounts a on a.id = jl.account_id
        cross join window_bounds w
        cross join access x
        where x.member
          and je.org_id = p_org_id
          and je.created_at::date between w.start_date and w.end_date
    )
    -- Per-account detail: withheld from a summary observer.
    select 'income'::text, name, sum(credit - debit)
    from lines cross join access x
    where type = 'income' and x.detailed
    group by name having sum(credit - debit) <> 0

    union all

    select 'expense'::text, name, sum(debit - credit)
    from lines cross join access x
    where type = 'expense' and x.detailed
    group by name having sum(debit - credit) <> 0

    union all

    -- The two totals: the whole of what a summary observer was granted.
    select 'total'::text, 'Total received', coalesce(sum(credit - debit), 0)
    from lines where type = 'income'

    union all

    select 'total'::text, 'Total spent', coalesce(sum(debit - credit), 0)
    from lines where type = 'expense'

    order by 1, 2;
$$;

-- Cash position. A balance is a total by definition, so any member of the org
-- may see it whatever their visibility.
create or replace function church_balances(p_org_id uuid)
returns table (account_name text, balance numeric)
language sql
stable
security definer
set search_path = public, auth
as $$
    select a.name, coalesce(sum(jl.debit - jl.credit), 0)
    from accounts a
    left join journal_lines jl on jl.account_id = a.id
    where a.org_id = p_org_id
      and a.type = 'asset'
      and is_org_member(p_org_id)
    group by a.name
    order by a.name;
$$;

-- One named person's giving. This is the most private thing the church module
-- holds, so it needs full visibility and not merely membership.
create or replace function member_giving_statement(
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
    order by 1;
$$;

-- ------------------------------------------------------------
-- 5. GRANTS
-- ------------------------------------------------------------
-- These are SECURITY DEFINER now, so the PUBLIC default that Postgres applies
-- to a new function would hand them to `anon`. Each one already refuses a
-- caller with no session — auth.uid() is null, so no membership matches — but
-- the grant is made deliberate rather than inherited.
revoke execute on function church_weekly_summary(uuid, date) from public;
revoke execute on function church_balances(uuid) from public;
revoke execute on function member_giving_statement(uuid, int) from public;

-- has_full_visibility() is deliberately left on the PUBLIC default, exactly
-- like the scope helpers in 004. It is named by the policies above, so every
-- role that can attempt a select has to be able to run it — revoking it from
-- anon turns "you may see no rows" into "permission denied for function",
-- which is a worse answer to the same question and breaks the reads an
-- anonymous caller is legitimately allowed to make. It answers only about the
-- caller's own memberships, so it discloses nothing.

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function church_weekly_summary(uuid, date) to authenticated;
        grant execute on function church_balances(uuid) to authenticated;
        grant execute on function member_giving_statement(uuid, int) to authenticated;
    end if;
end $$;
