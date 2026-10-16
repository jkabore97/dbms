-- ============================================================
-- 149_money_types.sql — batch 153: the recette and dépense types a
-- business adds itself, kept in its chart of accounts.
--
-- Recette's step 1 (« Qu'est-ce que c'est ? ») offered four fixed cards;
-- « Autre » asked for a name and record_entry (007) opened an income
-- account of that name the first time (ensure_account). Dépense's step 1
-- already showed the business's expense accounts as tiles. Neither could
-- be given a description, put in an order, renamed or taken off the
-- tiles by the people who record — the chart of accounts screen (admin
-- only, Pro) could retire an account, nothing else could.
--
-- A type IS an income or expense account: the income statement, the
-- ledgers, 148's analyses and every report count it with no mapping.
--
--   1. accounts gains `label` (what the card says when it was renamed
--      after entries were posted to it — the account's own name stays,
--      because « accounts are never renamed: the entries posted against
--      them would be rewritten », income_flow's rule) and `sort_order`
--      (the order on step 1; null after, by code). The description (007)
--      is the card's short line. Hiding a type is 007's is_active = false:
--      what the chart screen already calls « Retirer » and what the
--      recording sheets already stop offering — the account and every
--      entry on it stay, record_entry still posts to it by name.
--   2. money_types(org) — the business's income and expense accounts with
--      their label, description, order, whether shown, and how many lines
--      they carry. SECURITY INVOKER: read under 004's RLS (a member of the
--      business reads its chart; anybody else reads nothing). Not behind
--      the 'accounting' switch: recording is free, the chart screen is Pro.
--   3. save_money_type(org, direction, account, name, description,
--      active, adopt, recorded_by) — add (account null) or change one
--      type. SECURITY DEFINER on purpose, the way record_entry is: 004's
--      policies let only an administrator insert or update an account,
--      and the people who record — an employee as much as the owner —
--      must be able to add « Quête » the way « Autre » already lets them
--      open it. It checks what the policy would have: a signed-in member
--      of the business who may write (049's can_write_org: not an
--      observer, not suspended) and is not an approver (148's writers),
--      and touches only income/expense accounts of that business, and
--      only their label, description, order and is_active — never a
--      code, a type or another business's row. A name already used by an
--      account of the same kind (name or label, accents, case and spaces
--      aside) is refused (errcode MA149) — unless `adopt`, which the
--      phone's outbox sends for a type added with no signal: the account
--      that exists (opened meanwhile by an entry, or by another phone) is
--      taken and shown again, so a queued add never fails for good.
--      Renaming: an account nothing was posted to takes the new name
--      itself; one with entries keeps its name and takes the label.
--      An income type is an association's (a shop's and a farm's money
--      in comes from their sales): refused elsewhere.
--      reorder_money_types(org, direction, ids[]) — the order, the same
--      checks, SECURITY DEFINER for the same reason.
--   4. money_type_key(text) — the duplicate test's fold. Internal.
--
-- Nothing already posted changes: no name, code or line is rewritten on
-- installing, and every existing account keeps its is_active.
--
-- Apply after 148. Re-runnable (the bundle runs twice): columns if not
-- exists, constraints dropped and re-added, functions replaced in place.
-- ============================================================

-- ------------------------------------------------------------
-- 1. The card's label and order
-- ------------------------------------------------------------
alter table accounts add column if not exists label text;
alter table accounts add column if not exists sort_order int;

alter table accounts drop constraint if exists accounts_label_length;
alter table accounts add constraint accounts_label_length
    check (label is null or char_length(label) between 1 and 60);

comment on column accounts.label is
    'What the recording card calls this account after it was renamed with entries on it (149). The name stays: entries keep it.';
comment on column accounts.sort_order is
    'The order of the recording cards (149). Null: after, by code.';

-- ------------------------------------------------------------
-- 4. The fold the duplicate test compares
-- ------------------------------------------------------------
create or replace function money_type_key(p_text text)
returns text
language sql
immutable
set search_path = public
as $$
    select regexp_replace(
               translate(replace(replace(lower(btrim(coalesce(p_text, ''))), 'œ', 'oe'), 'æ', 'ae'),
                         'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ',
                         'aaaaaaceeeeiiiinooooouuuuyy'),
               '\s+', ' ', 'g');
$$;

-- ------------------------------------------------------------
-- 2. The list
-- ------------------------------------------------------------
create or replace function money_types(p_org_id uuid)
returns table (
    account_id  uuid,
    code        text,
    name        text,
    type        text,
    label       text,
    description text,
    is_active   boolean,
    sort_order  int,
    entry_count bigint
)
language sql
stable
security invoker
set search_path = public
as $$
    select a.id, a.code, a.name, a.type, a.label, a.description, a.is_active,
           a.sort_order,
           (select count(*) from journal_lines jl where jl.account_id = a.id)
      from accounts a
     where a.org_id = p_org_id
       and a.type in ('income', 'expense')
     order by a.type, a.sort_order nulls last, a.code;
$$;

-- ------------------------------------------------------------
-- 3. Add, change, order
-- ------------------------------------------------------------
-- Who may: what 004's policy would admit if it admitted the people who
-- record — a member of the business who may write and is not an approver.
create or replace function money_type_writer(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select auth.uid() is not null
       and can_write_org(p_org_id)
       and exists (select 1 from memberships m
                    where m.user_id = auth.uid()
                      and m.org_id = p_org_id
                      and m.role not in ('observer', 'approver'));
$$;

create or replace function save_money_type(
    p_org_id      uuid,
    p_direction   text,
    p_account_id  uuid    default null,
    p_name        text    default null,
    p_description text    default null,
    p_active      boolean default null,
    p_adopt       boolean default false,
    p_recorded_by uuid    default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_type  text;
    v_name  text := nullif(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'), '');
    v_desc  text := btrim(coalesce(p_description, ''));
    v_key   text;
    v_id    uuid;
    v_acct  accounts%rowtype;
    v_used  boolean;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord.';
    end if;
    if p_recorded_by is not null and p_recorded_by <> auth.uid() then
        raise exception 'save_money_type() cannot write on behalf of another user';
    end if;
    if not money_type_writer(p_org_id) then
        raise exception 'Vous ne pouvez pas modifier les types de cette activité.';
    end if;
    v_type := case p_direction when 'in' then 'income' when 'out' then 'expense' end;
    if v_type is null then
        raise exception 'Direction must be in or out (got %)', p_direction;
    end if;
    if v_type = 'income' and not exists (
        select 1 from orgs o where o.id = p_org_id and o.profile::text in ('association', 'church')
    ) then
        raise exception 'Les types de recette sont ceux d''une association : une boutique et une ferme reçoivent par leurs ventes.';
    end if;
    if v_name is not null and char_length(v_name) > 60 then
        raise exception 'Un nom de 60 caractères au plus, s''il vous plaît.';
    end if;
    if char_length(v_desc) > 80 then
        raise exception 'Une description de 80 caractères au plus, s''il vous plaît.';
    end if;
    v_key := money_type_key(v_name);

    if p_account_id is null then
        if v_name is null then
            raise exception 'Le nom du type, s''il vous plaît.';
        end if;
        -- Oldest first, as ensure_account takes the oldest match.
        select a.id into v_id
          from accounts a
         where a.org_id = p_org_id and a.type = v_type
           and (money_type_key(a.name) = v_key or money_type_key(a.label) = v_key)
         order by a.created_at, a.code
         limit 1;
        if v_id is not null then
            if not coalesce(p_adopt, false) then
                raise exception 'Un type porte déjà ce nom : %.', v_name using errcode = 'MA149';
            end if;
            update accounts
               set is_active   = true,
                   description = coalesce(description, nullif(v_desc, ''))
             where id = v_id;
            return v_id;
        end if;
        insert into accounts (org_id, code, name, type, description, created_by)
        values (p_org_id, next_account_code(p_org_id, v_type), v_name, v_type,
                nullif(v_desc, ''), auth.uid())
        returning id into v_id;
        return v_id;
    end if;

    select * into v_acct from accounts
     where id = p_account_id and org_id = p_org_id and type = v_type
     for update;
    if not found then
        raise exception 'Ce type n''est pas modifiable.';
    end if;

    if v_name is not null
       and v_name is distinct from coalesce(v_acct.label, v_acct.name) then
        if exists (
            select 1 from accounts a
             where a.org_id = p_org_id and a.type = v_type and a.id <> v_acct.id
               and (money_type_key(a.name) = v_key or money_type_key(a.label) = v_key)
        ) then
            raise exception 'Un type porte déjà ce nom : %.', v_name using errcode = 'MA149';
        end if;
        v_used := exists (select 1 from journal_lines jl where jl.account_id = v_acct.id);
        if not v_used then
            -- Nothing was posted to it: the account itself takes the name.
            update accounts set name = v_name, label = null where id = v_acct.id;
        elsif v_name = v_acct.name then
            update accounts set label = null where id = v_acct.id;
        else
            -- Entries carry its name: only the card is renamed.
            update accounts set label = v_name where id = v_acct.id;
        end if;
    end if;
    if p_description is not null then
        update accounts set description = nullif(v_desc, '') where id = v_acct.id;
    end if;
    if p_active is not null then
        update accounts set is_active = p_active where id = v_acct.id;
    end if;
    return v_acct.id;
end;
$$;

create or replace function reorder_money_types(
    p_org_id      uuid,
    p_direction   text,
    p_account_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_type text := case p_direction when 'in' then 'income' when 'out' then 'expense' end;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord.';
    end if;
    if not money_type_writer(p_org_id) then
        raise exception 'Vous ne pouvez pas modifier les types de cette activité.';
    end if;
    if v_type is null then
        raise exception 'Direction must be in or out (got %)', p_direction;
    end if;
    update accounts a
       set sort_order = o.n::int
      from unnest(coalesce(p_account_ids, '{}'::uuid[])) with ordinality as o(id, n)
     where a.id = o.id and a.org_id = p_org_id and a.type = v_type;
end;
$$;

-- ------------------------------------------------------------
-- Grants: the doors to authenticated; nothing to anon or PUBLIC.
-- ------------------------------------------------------------
revoke execute on function money_type_key(text)                                          from public;
revoke execute on function money_types(uuid)                                             from public;
revoke execute on function money_type_writer(uuid)                                       from public;
revoke execute on function save_money_type(uuid, text, uuid, text, text, boolean, boolean, uuid) from public;
revoke execute on function reorder_money_types(uuid, text, uuid[])                       from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function money_type_key(text)                                  from anon;
        revoke execute on function money_types(uuid)                                     from anon;
        revoke execute on function money_type_writer(uuid)                               from anon;
        revoke execute on function save_money_type(uuid, text, uuid, text, text, boolean, boolean, uuid) from anon;
        revoke execute on function reorder_money_types(uuid, text, uuid[])               from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: called by the two definer doors, as their owner.
        revoke execute on function money_type_key(text)                                  from authenticated;
        revoke execute on function money_type_writer(uuid)                               from authenticated;
        grant execute on function money_types(uuid)                                      to authenticated;
        grant execute on function save_money_type(uuid, text, uuid, text, text, boolean, boolean, uuid) to authenticated;
        grant execute on function reorder_money_types(uuid, text, uuid[])                to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
