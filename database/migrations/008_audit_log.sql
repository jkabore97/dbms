-- ============================================================
-- 008_audit_log.sql
--
-- What happened, who did it, and what the database actually holds.
--
-- The ledger has been its own audit trail since the first schema: entries are
-- never edited or deleted, and an undo is a reversing entry. That covers
-- money and nothing else. Everything that decides who may touch the money —
-- a role granted, an invitation issued, a category renamed, a business
-- renamed — has been silently mutable this whole time. An admin could grant
-- themselves ownership, do something, and revoke it again, and there would be
-- no trace anywhere that it had happened.
--
-- So: one append-only table, one generic trigger, and two functions that let
-- a super admin read the log and see the shape of the data underneath it.
--
-- Three decisions worth stating.
--
--   * The trigger is generic. A per-table audit function is a per-table thing
--     to forget to write, and the tables it would have to be written for are
--     exactly the ones somebody adds in a hurry. This one reads the row as
--     jsonb and works out the org, the subject and the changed columns
--     without knowing which table it is on.
--
--   * The log is append-only in the strongest sense available: RLS is enabled
--     with a select policy and no insert, update or delete policy at all. RLS
--     denies what it is not told to allow, so no caller can write to it,
--     amend it or clear it. The rows arrive because the trigger function is
--     SECURITY DEFINER and runs outside policy — which is the only door in,
--     and it is not a door anyone can knock on.
--
--   * Reading it needs admin. The log names people and says what they did,
--     which is precisely the thing an ordinary employee has no business
--     browsing about their colleagues.
-- ============================================================

-- ------------------------------------------------------------
-- 1. THE LOG
-- ------------------------------------------------------------
create table if not exists audit_log (
    id          bigint generated always as identity primary key,

    -- Null only for a row whose org could not be resolved, which should never
    -- happen and is kept visible rather than dropped if it does.
    org_id      uuid references orgs(id) on delete cascade,

    -- Who. Nullable because a row written by a migration, a seeder or a
    -- server-side job has no signed-in user behind it, and "the system did
    -- it" is a true and useful answer.
    actor_id    uuid references profiles(id) on delete set null,

    -- The name as it read at the time. Denormalised on purpose: a log entry
    -- that says "Aminata revoked Salif" must keep saying that after Aminata
    -- has changed her name and Salif's profile has been deleted.
    actor_label text,

    action      text not null check (action in ('insert', 'update', 'delete')),
    table_name  text not null,
    row_id      uuid,

    -- One human-readable line, resolved at write time for the same reason as
    -- actor_label: the log has to stay readable after its subject is gone.
    summary     text,

    -- For an update, {column: [before, after]} for the columns that actually
    -- changed. For an insert or a delete, the whole row.
    changed     jsonb,

    at          timestamptz not null default now()
);

-- The console reads one org's log newest-first, which is the only access
-- pattern there is.
create index if not exists audit_log_by_org on audit_log (org_id, id desc);
create index if not exists audit_log_by_actor on audit_log (org_id, actor_id, id desc);

-- ------------------------------------------------------------
-- 2. THE TRIGGER
-- ------------------------------------------------------------
-- SECURITY DEFINER so it can write the log from under a policy that lets
-- nobody write the log. search_path is pinned so a caller cannot shadow
-- `audit_log` or `profiles` with tables of their own and redirect the trail.
create or replace function audit_row()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_row     jsonb;
    v_old     jsonb;
    v_org     uuid;
    v_changed jsonb;
    v_actor   uuid := auth.uid();
    v_label   text;
    v_summary text;
begin
    if TG_OP = 'DELETE' then
        v_row := to_jsonb(OLD);
    else
        v_row := to_jsonb(NEW);
    end if;

    -- Which business this belongs to. Most tables carry org_id; orgs itself is
    -- its own org; departments reach it through their entity.
    v_org := nullif(v_row ->> 'org_id', '')::uuid;

    if v_org is null and TG_TABLE_NAME = 'orgs' then
        v_org := nullif(v_row ->> 'id', '')::uuid;
    end if;

    if v_org is null and v_row ? 'entity_id' then
        select e.org_id into v_org
          from entities e
         where e.id = nullif(v_row ->> 'entity_id', '')::uuid;
    end if;

    if v_actor is not null then
        select p.full_name into v_label from profiles p where p.id = v_actor;
    end if;

    -- Whichever of these the table happens to have, in the order a person
    -- would recognise the row by. A log that says "membership 8f2c…" is a log
    -- nobody reads twice.
    --
    -- This list is the one part of a generic trigger that cannot be generic:
    -- every table names its subject differently, and a table whose naming
    -- column is not here logs a null summary rather than failing — which is
    -- quiet, and is how it went unnoticed until 009 added `flocks` and its
    -- batch codes stopped appearing. A new table with a new naming column
    -- belongs on this list.
    v_summary := coalesce(
        v_row ->> 'name',
        v_row ->> 'label',
        v_row ->> 'full_name',
        v_row ->> 'batch_code',   -- flocks (009)
        v_row ->> 'number',       -- invoices (009)
        v_row ->> 'role',
        v_row ->> 'code',
        v_row ->> 'memo',
        v_row ->> 'description'
    );

    if TG_OP = 'UPDATE' then
        v_old := to_jsonb(OLD);
        -- Only the columns that moved. A diff listing every column is a diff
        -- nobody can read, and updated_at noise is how audit logs die.
        select jsonb_object_agg(e.key, jsonb_build_array(v_old -> e.key, e.value))
          into v_changed
          from jsonb_each(v_row) e
         where e.value is distinct from v_old -> e.key;

        -- Nothing actually changed. Postgres fires the trigger anyway on an
        -- UPDATE that sets a column to the value it already had.
        if v_changed is null then
            return coalesce(NEW, OLD);
        end if;
    else
        v_changed := v_row;
    end if;

    insert into audit_log (
        org_id, actor_id, actor_label, action, table_name, row_id, summary, changed
    )
    values (
        v_org,
        v_actor,
        coalesce(v_label, case when v_actor is null then 'Système' else 'Inconnu' end),
        lower(TG_OP),
        TG_TABLE_NAME,
        nullif(v_row ->> 'id', '')::uuid,
        v_summary,
        v_changed
    );

    return coalesce(NEW, OLD);
end;
$$;

-- ------------------------------------------------------------
-- 3. WHAT IS WATCHED
-- ------------------------------------------------------------
-- Everything that decides who may see or touch a business's money, plus the
-- ledger itself so the log is a single place to look rather than two.
--
-- journal_lines is deliberately absent: it has no independent life, an entry's
-- lines are written in the same transaction as the entry, and logging them
-- would double the busiest table in the schema to record nothing that the
-- entry's own row does not already say.
do $$
declare
    v_table text;
begin
    foreach v_table in array array[
        'orgs',
        'memberships',
        'entities',
        'departments',
        'accounts',
        'pending_invitations',
        'journal_entries',
        'church_members'
    ]
    loop
        execute format('drop trigger if exists audit_%1$s on %1$I', v_table);
        execute format(
            'create trigger audit_%1$s after insert or update or delete on %1$I
             for each row execute function audit_row()',
            v_table
        );
    end loop;
end $$;

-- ------------------------------------------------------------
-- 4. RLS — readable by admins, writable by nobody
-- ------------------------------------------------------------
alter table audit_log enable row level security;

drop policy if exists "audit log readable by org admins" on audit_log;

create policy "audit log readable by org admins"
on audit_log for select
using (is_org_admin(org_id));

-- No insert, update or delete policy. That omission is the whole guarantee:
-- the only writer is audit_row(), which runs as definer and outside policy.

-- ------------------------------------------------------------
-- 5. READING THE LOG
-- ------------------------------------------------------------
-- Keyset pagination on the identity column rather than OFFSET: the log grows
-- at the top while somebody is reading down it, and OFFSET would show them
-- the same row twice.
create or replace function audit_log_page(
    p_org_id  uuid,
    p_limit   int    default 50,
    p_before  bigint default null,   -- the id of the oldest row already shown
    p_table   text   default null,
    p_actor   uuid   default null,
    p_action  text   default null
)
returns table (
    id          bigint,
    at          timestamptz,
    actor_id    uuid,
    actor_label text,
    action      text,
    table_name  text,
    row_id      uuid,
    summary     text,
    changed     jsonb
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select l.id, l.at, l.actor_id, l.actor_label, l.action,
           l.table_name, l.row_id, l.summary, l.changed
    from audit_log l
    where l.org_id = p_org_id
      and is_org_admin(p_org_id)
      and (p_before is null or l.id < p_before)
      and (p_table  is null or l.table_name = p_table)
      and (p_actor  is null or l.actor_id = p_actor)
      and (p_action is null or l.action = p_action)
    order by l.id desc
    limit greatest(coalesce(p_limit, 50), 1);
$$;

-- The names to put in the filter, and how busy each has been. Reading a log
-- usually starts with "who has been doing things", not with a date.
create or replace function audit_log_actors(p_org_id uuid)
returns table (actor_id uuid, actor_label text, events bigint, last_seen timestamptz)
language sql
stable
security definer
set search_path = public, auth
as $$
    select l.actor_id, max(l.actor_label), count(*), max(l.at)
    from audit_log l
    where l.org_id = p_org_id
      and is_org_admin(p_org_id)
    group by l.actor_id
    order by 4 desc;
$$;

-- ------------------------------------------------------------
-- 6. THE DATABASE, AS A THING YOU CAN LOOK AT
-- ------------------------------------------------------------
-- A super admin who cannot see what the database holds has to trust the
-- screens, and the screens are the thing they are checking. This is the
-- shape of the data for one business: every table that holds anything of
-- theirs, what it is for, how many rows of it are theirs, and when it last
-- moved.
--
-- Written as a static UNION rather than dynamic SQL over the catalog on
-- purpose. Every count below is scoped to p_org_id by a WHERE clause someone
-- had to write, which is what makes this safe to expose; a loop over
-- information_schema counting whole tables would hand one client's row counts
-- to another's admin, and there would be no clause to point at and check.
create or replace function org_database_overview(p_org_id uuid)
returns table (
    table_name  text,
    label       text,
    purpose     text,
    row_count   bigint,
    last_change timestamptz
)
language sql
stable
security definer
set search_path = public, auth
as $$
    with allowed as (select is_org_admin(p_org_id) as ok),
    counts(table_name, label, purpose, row_count) as (
        select 'orgs', 'Activité', 'La fiche de l''activité elle-même',
               (select count(*) from orgs o where o.id = p_org_id)
        union all
        select 'entities', 'Sites', 'Campus, fermes, boutiques',
               (select count(*) from entities e where e.org_id = p_org_id)
        union all
        select 'departments', 'Départements', 'Sous-unités d''un site',
               (select count(*) from departments d
                 join entities e on e.id = d.entity_id where e.org_id = p_org_id)
        union all
        select 'memberships', 'Accès', 'Qui détient quel rôle, et sur quoi',
               (select count(*) from memberships m where m.org_id = p_org_id)
        union all
        select 'pending_invitations', 'Invitations', 'Codes émis, utilisés ou expirés',
               (select count(*) from pending_invitations i where i.org_id = p_org_id)
        union all
        select 'accounts', 'Plan comptable', 'Les catégories dans lesquelles l''argent tombe',
               (select count(*) from accounts a where a.org_id = p_org_id)
        union all
        select 'journal_entries', 'Écritures', 'Chaque enregistrement, jamais modifié',
               (select count(*) from journal_entries je where je.org_id = p_org_id)
        union all
        select 'journal_lines', 'Lignes d''écriture', 'Les débits et crédits sous chaque écriture',
               (select count(*) from journal_lines jl
                 join journal_entries je on je.id = jl.journal_entry_id
                where je.org_id = p_org_id)
        union all
        select 'church_members', 'Fidèles', 'Les personnes à qui une offrande peut être attribuée',
               (select count(*) from church_members cm where cm.org_id = p_org_id)
        union all
        select 'contribution_attributions', 'Attributions', 'Quelle écriture appartient à quel fidèle',
               (select count(*) from contribution_attributions ca
                 join journal_entries je on je.id = ca.journal_entry_id
                where je.org_id = p_org_id)
        union all
        select 'documents', 'Pièces jointes', 'Photos et factures liées aux écritures',
               (select count(*) from documents doc where doc.org_id = p_org_id)
        union all
        select 'audit_log', 'Journal d''activité', 'Ce que chacun a modifié, et quand',
               (select count(*) from audit_log al where al.org_id = p_org_id)
    )
    select c.table_name, c.label, c.purpose, c.row_count,
           (select max(l.at) from audit_log l
             where l.org_id = p_org_id and l.table_name = c.table_name)
    from counts c cross join allowed a
    where a.ok
    order by c.table_name;
$$;

-- The tables a super admin may inspect the structure of. Anything not on this
-- list — auth.users above all — is not describable through this function at
-- any privilege level, because the answer would be the same for every tenant
-- and there is nothing an org admin learns from it that they need.
create or replace function is_inspectable_table(p_table text)
returns boolean
language sql
immutable
as $$
    select p_table = any (array[
        'orgs', 'entities', 'departments', 'memberships', 'pending_invitations',
        'profiles', 'accounts', 'journal_entries', 'journal_lines',
        'church_members', 'contribution_attributions', 'documents', 'audit_log'
    ]);
$$;

-- What a table is made of: columns, types, what may be empty, what points
-- where. This is the schema browser behind the console's Database tab.
--
-- It returns structure and never a row of data, so it discloses nothing about
-- any tenant — but it is still gated on being an admin of some business,
-- because a schema is a map of what is worth attacking.
create or replace function org_table_columns(p_org_id uuid, p_table text)
returns table (
    column_name  text,
    data_type    text,
    is_nullable  boolean,
    has_default  boolean,
    is_key       boolean,
    references_table text
)
language sql
stable
security definer
set search_path = public, auth
as $$
    select
        c.column_name::text,
        c.data_type::text,
        c.is_nullable = 'YES',
        c.column_default is not null,
        exists (
            select 1
            from information_schema.key_column_usage k
            join information_schema.table_constraints tc
              on tc.constraint_name = k.constraint_name
             and tc.constraint_schema = k.constraint_schema
            where tc.constraint_type = 'PRIMARY KEY'
              and k.table_schema = 'public'
              and k.table_name = c.table_name
              and k.column_name = c.column_name
        ),
        (
            select ccu.table_name::text
            from information_schema.key_column_usage k
            join information_schema.table_constraints tc
              on tc.constraint_name = k.constraint_name
             and tc.constraint_schema = k.constraint_schema
            join information_schema.constraint_column_usage ccu
              on ccu.constraint_name = tc.constraint_name
             and ccu.constraint_schema = tc.constraint_schema
            where tc.constraint_type = 'FOREIGN KEY'
              and k.table_schema = 'public'
              and k.table_name = c.table_name
              and k.column_name = c.column_name
            limit 1
        )
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = p_table
      and is_inspectable_table(p_table)
      and is_org_admin(p_org_id)
    order by c.ordinal_position;
$$;

-- ------------------------------------------------------------
-- 7. GRANTS
-- ------------------------------------------------------------
revoke execute on function audit_log_page(uuid, int, bigint, text, uuid, text) from public;
revoke execute on function audit_log_actors(uuid) from public;
revoke execute on function org_database_overview(uuid) from public;
revoke execute on function org_table_columns(uuid, text) from public;

-- audit_row() is a trigger function. It cannot be called directly — Postgres
-- refuses a trigger function invoked as a plain function — but it is SECURITY
-- DEFINER and the default grant is to PUBLIC, so it is revoked with the rest.
revoke execute on function audit_row() from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        grant execute on function audit_log_page(uuid, int, bigint, text, uuid, text) to authenticated;
        grant execute on function audit_log_actors(uuid) to authenticated;
        grant execute on function org_database_overview(uuid) to authenticated;
        grant execute on function org_table_columns(uuid, text) to authenticated;
        -- Select only. There is no policy that would let an insert through
        -- anyway, and the grant should not suggest otherwise.
        grant select on audit_log to authenticated;
    end if;
end $$;
