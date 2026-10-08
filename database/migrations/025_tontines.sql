-- ============================================================
-- 025 — TONTINES
-- ============================================================
-- The rotating savings group is how a large share of working capital moves
-- here: each member pays a fixed amount each round, and each round one
-- member takes the pot, in an order fixed when the group forms. A church or
-- shop owner is almost certainly in one, and today they track it in a
-- school notebook.
--
-- Version 1 is deliberately the **rotating** form and deliberately a
-- **tracker**: it records who has paid this round and whose turn the pot
-- is, and it does not write to the ledger. Two reasons, both about honesty:
--
--   * The tontine's money is usually not the business's money. Posting
--     contributions into the business's books would mix personal savings
--     into a shop's income statement — precisely the confusion the app
--     exists to end. The organiser who *does* run it through the till can
--     record that movement with record_entry(), which already exists.
--   * The variants (accumulating tontines, penalty rules, interest) differ
--     more than the business profiles do. The build plan says design those
--     with three real organisers first; this schema holds the common core
--     every variant shares and no rule it would have to unlearn.
--
-- Members are names, not accounts. Most tontine members will never touch
-- the app; requiring them to sign up would kill the feature on day one.

create table if not exists tontines (
    id            uuid primary key default gen_random_uuid(),
    org_id        uuid not null references orgs(id) on delete cascade,
    name          text not null,
    amount        numeric(14,2) not null check (amount > 0),  -- per member, per round
    period        text not null default 'monthly'
                  check (period in ('daily', 'weekly', 'monthly')),
    current_round int  not null default 1 check (current_round >= 1),
    is_active     boolean not null default true,
    created_by    uuid not null references profiles(id),
    created_at    timestamptz not null default now()
);

create index if not exists tontines_by_org on tontines (org_id) where is_active;

create table if not exists tontine_members (
    id         uuid primary key default gen_random_uuid(),
    tontine_id uuid not null references tontines(id) on delete cascade,
    org_id     uuid not null references orgs(id) on delete cascade,
    name       text not null,
    phone      text,
    -- Whose turn: the member at position N takes the pot in round N (and
    -- again at N + member-count, if the group runs on). Unique per tontine,
    -- so two people cannot hold the same turn.
    position   int not null check (position >= 1),
    created_at timestamptz not null default now(),
    unique (tontine_id, position)
);

create table if not exists tontine_contributions (
    id          uuid primary key default gen_random_uuid(),
    tontine_id  uuid not null references tontines(id) on delete cascade,
    member_id   uuid not null references tontine_members(id) on delete restrict,
    org_id      uuid not null references orgs(id) on delete cascade,
    round       int not null check (round >= 1),
    amount      numeric(14,2) not null check (amount > 0),
    client_uuid uuid unique,
    paid_at     timestamptz not null default now(),
    created_by  uuid not null references profiles(id),
    -- One payment per member per round: the second is a mistake, not a
    -- bonus. Corrections are a delete by the organiser, visible in the
    -- audit trigger like any other.
    unique (tontine_id, member_id, round)
);

alter table tontines enable row level security;
alter table tontine_members enable row level security;
alter table tontine_contributions enable row level security;

-- The whole surface is org-scoped, and unlike the ledger these rows carry no
-- money of the business's — so ordinary member CRUD under RLS is the right
-- gate, with writes for non-observers exactly as customers/products have.
drop policy if exists "tontines readable within org" on tontines;
create policy "tontines readable within org"
on tontines for select using (is_org_member(org_id));
drop policy if exists "tontines managed by writers" on tontines;
create policy "tontines managed by writers"
on tontines for all using (can_write_org(org_id)) with check (can_write_org(org_id));

drop policy if exists "tontine members readable within org" on tontine_members;
create policy "tontine members readable within org"
on tontine_members for select using (is_org_member(org_id));
drop policy if exists "tontine members managed by writers" on tontine_members;
create policy "tontine members managed by writers"
on tontine_members for all using (can_write_org(org_id)) with check (can_write_org(org_id));

drop policy if exists "contributions readable within org" on tontine_contributions;
create policy "contributions readable within org"
on tontine_contributions for select using (is_org_member(org_id));
drop policy if exists "contributions recorded by writers" on tontine_contributions;
create policy "contributions recorded by writers"
on tontine_contributions for insert with check (can_write_org(org_id));
drop policy if exists "contributions corrected by writers" on tontine_contributions;
create policy "contributions corrected by writers"
on tontine_contributions for delete using (can_write_org(org_id));

-- ------------------------------------------------------------
-- THE ROUND, ANSWERED IN ONE CALL
-- ------------------------------------------------------------
-- Who has paid, who has not, whose turn the pot is. SECURITY INVOKER: RLS
-- on the three tables is the gate, and it is the right one.
create or replace function tontine_round_status(p_tontine_id uuid)
returns table (
    member_id     uuid,
    member_name   text,
    phone         text,
    turn_position int,
    has_paid      boolean,
    is_taker      boolean
)
language sql
stable
security invoker
as $$
    select m.id, m.name, m.phone, m.position,
           exists (
               select 1 from tontine_contributions c
                where c.tontine_id = t.id
                  and c.member_id = m.id
                  and c.round = t.current_round),
           -- The pot rotates: position N takes round N, then N + count.
           ((t.current_round - 1) % (select count(*) from tontine_members
                                      where tontine_id = t.id)) + 1 = m.position
      from tontines t
      join tontine_members m on m.tontine_id = t.id
     where t.id = p_tontine_id
     order by m.position;
$$;

-- Closing a round: refused while somebody has not paid, because "everyone
-- paid" is the tontine's whole contract and skipping it silently is how
-- notebook tontines end in a quarrel. The organiser who must move on anyway
-- deletes the defaulter or records the payment — both visible acts.
create or replace function advance_tontine_round(p_tontine_id uuid)
returns int
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org     uuid;
    v_round   int;
    v_unpaid  int;
begin
    select org_id, current_round into v_org, v_round
      from tontines where id = p_tontine_id and is_active;
    if not found then
        raise exception 'No such tontine';
    end if;
    if not can_write_org(v_org) then
        raise exception 'You cannot manage this tontine';
    end if;

    select count(*) into v_unpaid
      from tontine_members m
     where m.tontine_id = p_tontine_id
       and not exists (
           select 1 from tontine_contributions c
            where c.tontine_id = p_tontine_id
              and c.member_id = m.id and c.round = v_round);
    if v_unpaid > 0 then
        raise exception
            'Impossible de clore le tour : % membre(s) n''ont pas encore payé',
            v_unpaid;
    end if;

    update tontines set current_round = current_round + 1
     where id = p_tontine_id
    returning current_round into v_round;
    return v_round;
end;
$$;

revoke execute on function advance_tontine_round(uuid) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant select, insert, update, delete on tontines, tontine_members to authenticated;
        grant select, insert, delete on tontine_contributions to authenticated;
        grant execute on function tontine_round_status(uuid) to authenticated;
        grant execute on function advance_tontine_round(uuid) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
