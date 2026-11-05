-- ============================================================
-- 168 — Two accounts of one person, merged (batch 168).
--
-- The owner: « some people have two accounts — they sign in with Apple,
-- then with Google — and it looks like two different accounts. I want to
-- merge them, so whatever they sign in with they reach the same account.
-- Others may want different emails for different businesses: don't block
-- them. » Apple's « Masquer mon e-mail » gives an address Google never
-- sees, so Supabase cannot link the two by itself.
--
--   * account_merge_preview(keep, absorb): what each account is (email,
--     ways of signing in, businesses and roles) and how many rows of the
--     absorbed one move. A platform admin's.
--   * merge_accounts(keep, absorb, confirm): the absorbed account's ways of
--     signing in with Google or Apple (auth.identities) move to the kept
--     one, so they now open it; every row of every table that points at the
--     absorbed person points at the kept one; where a table holds one row
--     per person (a setting, a device, a follow, a terms acceptance) and
--     both have one, the kept one's stays; the kept profile's empty fields
--     take the absorbed one's; the absorbed account is deleted. One
--     transaction: all of it, or nothing. Logged in account_merges.
--     A platform admin only, never on themselves, never absorbing a
--     platform admin; `confirm` is the absorbed account's email (or its
--     phone, or its id when it has neither), typed back.
--   * The guards of each table (closed periods, issued invoices, the
--     same-org check…) watch business columns, not who made a row: when one
--     refuses only because a person's id changes, that table's triggers
--     are set aside for this one statement, inside the transaction, and put
--     back before it ends. No lock is waited for more than 5 seconds.
--
-- An email-and-password login lives on the account itself, not in
-- auth.identities: absorbed, it stops working. The preview says so; keep
-- the account with the password when only one has one.
--
-- For a shop, a farm, an association and an Événementiel alike: a person
-- and their memberships, nothing else. Not reversible. Applies twice.
-- ============================================================

create table if not exists account_merges (
    id            bigint generated always as identity primary key,
    kept_id       uuid not null,
    absorbed_id   uuid not null,
    absorbed_label text,
    merged_by     uuid,
    moved         jsonb not null default '{}'::jsonb,
    created_at    timestamptz not null default now()
);
alter table account_merges enable row level security;
revoke all on account_merges from public;
do $$ begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on account_merges from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on account_merges from authenticated;
    end if;
end $$;

-- Every column of the public schema that names a person: the foreign keys
-- to auth.users and profiles, and the few that name one without a key.
create or replace function _person_columns()
returns table (tbl regclass, col text)
language sql
stable
set search_path = public, pg_catalog
as $$
    select distinct c.conrelid::regclass, a.attname::text
      from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
     where c.contype = 'f'
       and c.confrelid in ('auth.users'::regclass, 'public.profiles'::regclass)
       and c.connamespace = 'public'::regnamespace
       and not (c.conrelid = 'public.profiles'::regclass and a.attname = 'id')
    union
    select to_regclass('public.order_events'), 'by_user'
     where to_regclass('public.order_events') is not null;
$$;
revoke execute on function _person_columns() from public;

-- One column: the absorbed person's rows become the kept one's; a row that
-- would repeat one the kept person already has is dropped.
create or replace function _merge_move(p_tbl regclass, p_col text, p_keep uuid, p_absorb uuid)
returns integer
language plpgsql
set search_path = public, pg_catalog
as $$
declare
    r record;
    n integer := 0;
begin
    for r in execute format('select ctid from %s where %I = $1', p_tbl, p_col) using p_absorb loop
        begin
            execute format('update %s set %I = $1 where ctid = $2', p_tbl, p_col) using p_keep, r.ctid;
            n := n + 1;
        exception when unique_violation then
            execute format('delete from %s where ctid = $1', p_tbl) using r.ctid;
        end;
    end loop;
    return n;
end;
$$;
revoke execute on function _merge_move(regclass, text, uuid, uuid) from public;

create or replace function _merge_caller_ok()
returns void
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null
       or not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Réservé aux administrateurs de Marakaj';
    end if;
end;
$$;
revoke execute on function _merge_caller_ok() from public;

create or replace function _merge_account_card(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    select jsonb_build_object(
        'id', u.id,
        'email', u.email,
        'phone', coalesce(p.phone, u.phone),
        'name', p.full_name,
        'created_at', u.created_at,
        'last_sign_in_at', u.last_sign_in_at,
        'platform_admin', coalesce(p.is_platform_admin, false),
        'password', u.encrypted_password is not null and u.encrypted_password <> '',
        'providers', coalesce((select jsonb_agg(distinct i.provider order by i.provider)
                                 from auth.identities i where i.user_id = u.id), '[]'::jsonb),
        'businesses', coalesce((select jsonb_agg(jsonb_build_object('org', o.name, 'role', m.role) order by o.name)
                                  from memberships m join orgs o on o.id = m.org_id
                                 where m.user_id = u.id), '[]'::jsonb))
      from auth.users u left join profiles p on p.id = u.id
     where u.id = p_user;
$$;
revoke execute on function _merge_account_card(uuid) from public;

create or replace function account_merge_preview(p_keep uuid, p_absorb uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_rows jsonb := '{}'::jsonb;
    c record;
    n bigint;
begin
    perform _merge_caller_ok();
    if p_keep is null or p_absorb is null or p_keep = p_absorb then
        raise exception 'Choisissez deux comptes différents';
    end if;
    if not exists (select 1 from auth.users where id = p_keep)
       or not exists (select 1 from auth.users where id = p_absorb) then
        raise exception 'Compte introuvable';
    end if;
    for c in select * from _person_columns() loop
        execute format('select count(*) from %s where %I = $1', c.tbl, c.col) into n using p_absorb;
        if n > 0 then
            v_rows := v_rows || jsonb_build_object(c.tbl::text || '.' || c.col, n);
        end if;
    end loop;
    return jsonb_build_object(
        'keep', _merge_account_card(p_keep),
        'absorb', _merge_account_card(p_absorb),
        'rows', v_rows);
end;
$$;
revoke execute on function account_merge_preview(uuid, uuid) from public;

create or replace function merge_accounts(p_keep uuid, p_absorb uuid, p_confirm text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_absorb auth.users%rowtype;
    v_prof   profiles%rowtype;
    v_label  text;
    v_moved  jsonb := '{}'::jsonb;
    c record;
    n integer;
begin
    perform _merge_caller_ok();
    if p_keep is null or p_absorb is null or p_keep = p_absorb then
        raise exception 'Choisissez deux comptes différents';
    end if;
    select * into v_absorb from auth.users where id = p_absorb;
    if not found or not exists (select 1 from auth.users where id = p_keep) then
        raise exception 'Compte introuvable';
    end if;
    if p_absorb = auth.uid() then
        raise exception 'Vous ne pouvez pas fusionner votre propre compte dans un autre';
    end if;
    select * into v_prof from profiles where id = p_absorb;
    if coalesce(v_prof.is_platform_admin, false) then
        raise exception 'Un compte administrateur de Marakaj ne peut pas être absorbé : retirez d''abord son accès plateforme';
    end if;
    v_label := coalesce(nullif(v_absorb.email, ''), nullif(coalesce(v_prof.phone, v_absorb.phone), ''), p_absorb::text);
    if lower(trim(coalesce(p_confirm, ''))) <> lower(v_label) then
        raise exception 'Pour confirmer, tapez exactement : %', v_label;
    end if;
    perform pg_advisory_xact_lock(hashtext('merge_accounts'));

    -- Google and Apple sign-ins: now the kept account's.
    update auth.identities set user_id = p_keep, updated_at = now() where user_id = p_absorb;

    -- A lock the app holds is waited for a few seconds at most: past that
    -- the merge stops, whole, and can be run again.
    perform set_config('lock_timeout', '5s', true);
    for c in select * from _person_columns() loop
        begin
            n := _merge_move(c.tbl, c.col, p_keep, p_absorb);
        exception when others then
            -- A guard of that table refused: its triggers set aside for this
            -- one move, inside this transaction, then put back.
            execute format('alter table %s disable trigger user', c.tbl);
            n := _merge_move(c.tbl, c.col, p_keep, p_absorb);
            execute format('alter table %s enable trigger user', c.tbl);
        end;
        if n > 0 then
            v_moved := v_moved || jsonb_build_object(c.tbl::text || '.' || c.col, n);
        end if;
    end loop;

    delete from auth.users where id = p_absorb;

    -- The kept profile keeps its own words; its empty ones take the other's.
    update profiles p set
        full_name   = coalesce(nullif(p.full_name, ''), v_prof.full_name),
        first_name  = coalesce(nullif(p.first_name, ''), v_prof.first_name),
        middle_name = coalesce(nullif(p.middle_name, ''), v_prof.middle_name),
        last_name   = coalesce(nullif(p.last_name, ''), v_prof.last_name),
        title       = coalesce(nullif(p.title, ''), v_prof.title),
        date_of_birth = coalesce(p.date_of_birth, v_prof.date_of_birth),
        is_trainer  = p.is_trainer or coalesce(v_prof.is_trainer, false),
        profile_completed_at = coalesce(p.profile_completed_at, v_prof.profile_completed_at)
     where p.id = p_keep;
    if v_prof.phone is not null and v_prof.phone <> '' then
        begin
            update profiles set phone = v_prof.phone where id = p_keep and (phone is null or phone = '');
        exception when unique_violation then null;
        end;
    end if;

    insert into account_merges (kept_id, absorbed_id, absorbed_label, merged_by, moved)
    values (p_keep, p_absorb, v_label, auth.uid(), v_moved);
    return jsonb_build_object('kept', p_keep, 'absorbed', v_label, 'moved', v_moved);
end;
$$;
revoke execute on function merge_accounts(uuid, uuid, text) from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function _person_columns() from anon;
        revoke execute on function _merge_move(regclass, text, uuid, uuid) from anon;
        revoke execute on function _merge_caller_ok() from anon;
        revoke execute on function _merge_account_card(uuid) from anon;
        revoke execute on function account_merge_preview(uuid, uuid) from anon;
        revoke execute on function merge_accounts(uuid, uuid, text) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function _person_columns() from authenticated;
        revoke execute on function _merge_move(regclass, text, uuid, uuid) from authenticated;
        revoke execute on function _merge_caller_ok() from authenticated;
        revoke execute on function _merge_account_card(uuid) from authenticated;
        grant execute on function account_merge_preview(uuid, uuid) to authenticated;
        grant execute on function merge_accounts(uuid, uuid, text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
