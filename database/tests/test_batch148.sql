-- ============================================================
-- test_batch148.sql — batch 152 (148): an association's « Membres » and
-- its « Analyses ».
--
-- The claims:
--   1. installed twice, the same: church_members' note and removed_at, the
--      FOR ALL policy gone for an INSERT and an UPDATE policy and no
--      DELETE, the guard trigger, every new door SECURITY INVOKER with its
--      search path pinned, authenticated's and never anon's or PUBLIC's,
--      the analyses offered to an association on the switchboard;
--   2. allowed: the owner and an employee add a member (name, phone,
--      note, date); edit; the same phone as another member refused
--      (MA148, the other's name) then taken when allowed; a note over 80
--      characters, a date in the future, an empty name refused; removing
--      is soft — the row stays, removed_at dated, the gifts still theirs
--      and still on the « Relevé de dons »;
--   3. refused: an observer and an approver add, edit and remove nothing;
--      nobody deletes a member (the owner's DELETE touches no row); a
--      member never moves to another business; another association's
--      owner reads and changes nothing; anon executes nothing; a shop and
--      a farm are refused (« Réservé aux associations »);
--   4. the list: this year's total given, its cotisations and dons, a gift
--      undone left out of the totals (and off the giving statement —
--      148's fix), kept in the history marked undone; a
--      summary observer gets the names and nulls;
--   5. where a member stands on the usual cotisation (1 000 a month):
--      none without a usual cotisation; entered this month and not paid
--      'due' (never late); entered three months ago, one month paid,
--      'late' since the second month; four months paid 'up_to_date'
--      with paid_through the end of this month; a year-joined member
--      counted from the day entered, not from a date typed years back;
--   6. the analyses: 12 months of money in and out and the money held,
--      income by category (Cotisations, Dons, « Dîme » named by the
--      association), expenses by category, the members' counts, the top
--      givers for an administrator only (an employee with full visibility
--      gets null), a summary observer the totals only; refused on a Free
--      association (« Marakaj Pro : »), hidden by the switchboard
--      (MA002), the reports dial at hidden, to a stranger, to a farm.
-- Names: « Membre n° 01 », « Le trésorier », brand-like associations;
-- Ouagadougou. Wrapped in one transaction rolled back: runs twice the same.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- As test_reports: the app's role may call the books' doors (record_entry,
-- reverse_entry…); then 148 again, twice — what it grants and revokes is
-- what is tested.
grant execute on all functions in schema public to authenticated;
\i database/migrations/148_association_members.sql
\i database/migrations/148_association_members.sql

begin;


insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('14814814-0000-0000-0000-000000000001',  '+22614800001', 'owner148@example.com',  '{"full_name": "Présidence Fondation Espoir"}', now() - interval '2 years'),
    ('14814814-0000-0000-0000-000000000002',    '+22614800002', 'emp148@example.com',    '{"full_name": "Le trésorier"}',               now() - interval '2 years'),
    ('14814814-0000-0000-0000-000000000003',    '+22614800003', 'obs148@example.com',    '{"full_name": "Regard Fondation Espoir"}',    now() - interval '2 years'),
    ('14814814-0000-0000-0000-000000000004',   '+22614800004', 'appr148@example.com',   '{"full_name": "Visa Fondation Espoir"}',      now() - interval '2 years'),
    ('14814814-0000-0000-0000-000000000005',   '+22614800005', 'summ148@example.com',   '{"full_name": "Partenaire Fondation Espoir"}', now() - interval '2 years'),
    ('14814814-0000-0000-0000-000000000006',  '+22614800006', 'rival148@example.com',  '{"full_name": "Présidence Cercle Lumière"}',  now() - interval '2 years'),
    ('14814814-0000-0000-0000-000000000007', '+22614800007', 'farm148@example.com',   '{"full_name": "Gérance Ferme Horizon"}',      now() - interval '2 years');
update profiles p set phone = u.phone from auth.users u where u.id = p.id and p.phone is null;

insert into orgs (id, name, slug, profile, default_currency, plan, plan_until, city) values
    ('14800000-0000-0000-0000-000000000001', 'Fondation Espoir', 'fondation-espoir-148', 'association', 'XOF', 'pro', current_date + 30, 'Ouagadougou'),
    ('14800000-0000-0000-0000-000000000002', 'Cercle Lumière',   'cercle-lumiere-148',   'church',      'XOF', 'pro', current_date + 30, 'Ouagadougou'),
    ('14800000-0000-0000-0000-000000000003',  'Ferme Horizon',    'ferme-horizon-148',    'farm',        'XOF', 'pro', current_date + 30, 'Ouagadougou'),
    ('14800000-0000-0000-0000-000000000004',  'Kiosque Nova',     'kiosque-nova-148',     'retail',      'XOF', 'pro', current_date + 30, 'Ouagadougou'),
    ('14800000-0000-0000-0000-000000000005', 'Club Avenir',      'club-avenir-148',      'association', 'XOF', 'free', null,             'Ouagadougou');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    ('14800000-0000-0000-0000-000000000001', '14814814-0000-0000-0000-000000000001',  'owner',    'org', '14800000-0000-0000-0000-000000000001', 'full'),
    ('14800000-0000-0000-0000-000000000001', '14814814-0000-0000-0000-000000000002',    'employee', 'org', '14800000-0000-0000-0000-000000000001', 'full'),
    ('14800000-0000-0000-0000-000000000001', '14814814-0000-0000-0000-000000000003',    'observer', 'org', '14800000-0000-0000-0000-000000000001', 'full'),
    ('14800000-0000-0000-0000-000000000001', '14814814-0000-0000-0000-000000000004',   'approver', 'org', '14800000-0000-0000-0000-000000000001', 'full'),
    ('14800000-0000-0000-0000-000000000001', '14814814-0000-0000-0000-000000000005',   'observer', 'org', '14800000-0000-0000-0000-000000000001', 'summary'),
    ('14800000-0000-0000-0000-000000000002', '14814814-0000-0000-0000-000000000006',  'owner',    'org', '14800000-0000-0000-0000-000000000002', 'full'),
    ('14800000-0000-0000-0000-000000000003',  '14814814-0000-0000-0000-000000000007', 'owner',    'org', '14800000-0000-0000-0000-000000000003',  'full'),
    ('14800000-0000-0000-0000-000000000004',  '14814814-0000-0000-0000-000000000007', 'owner',    'org', '14800000-0000-0000-0000-000000000004',  'full'),
    ('14800000-0000-0000-0000-000000000005', '14814814-0000-0000-0000-000000000001',  'owner',    'org', '14800000-0000-0000-0000-000000000005', 'full');
select seed_church_accounts('14800000-0000-0000-0000-000000000001') \gset zz_
select seed_church_accounts('14800000-0000-0000-0000-000000000002') \gset zz_
select seed_church_accounts('14800000-0000-0000-0000-000000000005') \gset zz_

-- As PostgREST names a caller.
create function pg_temp.as148(p_who uuid)
returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true),
           set_config('request.jwt.claims', case when p_who is null then '' else
                      json_build_object('sub', p_who, 'role', 'authenticated')::text end, true);
$$;

-- A value as somebody, under their role (anon when nobody): its text, or
-- « ERR: <sqlstate> <message> ».
create function pg_temp.v148(p_who uuid, p_sql text)
returns text language plpgsql as $$
declare v text;
begin
    perform pg_temp.as148(p_who);
    execute case when p_who is null then 'set local role anon' else 'set local role authenticated' end;
    execute p_sql into v;
    execute 'reset role';
    return coalesce(v, '<null>');
exception when others then
    execute 'reset role';
    return 'ERR: ' || sqlstate || ' ' || sqlerrm;
end;
$$;

-- A statement's row count as somebody: 'n', or the error.
create function pg_temp.n148(p_who uuid, p_sql text)
returns text language plpgsql as $$
declare v int;
begin
    perform pg_temp.as148(p_who);
    execute 'set local role authenticated';
    execute p_sql;
    get diagnostics v = row_count;
    execute 'reset role';
    return v::text;
exception when others then
    execute 'reset role';
    return 'ERR: ' || sqlstate || ' ' || sqlerrm;
end;
$$;

-- A gift recorded through the app's door (record_entry, 007), as the owner.
create function pg_temp.gift148(p_member uuid, p_amount numeric, p_category text,
                                p_at timestamptz default now(), p_org uuid default '14800000-0000-0000-0000-000000000001')
returns uuid language plpgsql as $$
declare v text;
begin
    v := pg_temp.v148('14814814-0000-0000-0000-000000000001', format(
        'select record_entry(%L::uuid, %s, ''in'', %L, null, %L, ''cash'', %L::uuid, null, ''{}''::jsonb, null, null, null, null, %L::timestamptz)::text',
        p_org, p_amount, p_category || ' — test', p_category, p_member, p_at));
    if v like 'ERR:%' then raise exception 'FAIL: the gift was not recorded: %', v; end if;
    return v::uuid;
end;
$$;

\echo ''
\echo '--- 1. installed twice, the same ---'
do $$
declare v text;
begin
    if not exists (select 1 from information_schema.columns where table_name = 'church_members' and column_name = 'note')
       or not exists (select 1 from information_schema.columns where table_name = 'church_members' and column_name = 'removed_at') then
        raise exception 'FAIL: the note or the removal date is missing';
    end if;
    select string_agg(polname || ':' || polcmd::text, ', ' order by polname) into v
      from pg_policy where polrelid = 'church_members'::regclass;
    if v <> 'members added by writers:a, members changed by writers:w, members readable with help access:r, members readable within org:r' then
        raise exception 'FAIL: church_members policies are %', v;
    end if;
    if not exists (select 1 from pg_trigger where tgrelid = 'church_members'::regclass
                      and tgname = 'church_member_guard' and not tgisinternal) then
        raise exception 'FAIL: no guard trigger';
    end if;
    select string_agg(p.proname, ', ' order by p.proname) into v
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('save_association_member', 'remove_association_member', 'association_member_dues',
                         'association_members', 'association_member_history', 'association_analytics',
                         'trg_church_member_guard')
       and (p.prosecdef
            or not coalesce((select true from unnest(p.proconfig) c where c = 'search_path=public'), false));
    if v is not null then
        raise exception 'FAIL: definer or loose search path: %', v;
    end if;
    foreach v in array array['save_association_member(uuid, uuid, text, text, text, date, boolean)',
                             'remove_association_member(uuid)', 'association_member_dues(uuid)',
                             'association_members(uuid, integer)', 'association_member_history(uuid)',
                             'association_analytics(uuid, date, date)'] loop
        if has_function_privilege('anon', v, 'execute') then
            raise exception 'FAIL: anon may execute %', v;
        end if;
        if not has_function_privilege('authenticated', v, 'execute') then
            raise exception 'FAIL: authenticated may not execute %', v;
        end if;
        if exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                    where p.oid = v::regprocedure and a.grantee = 0) then
            raise exception 'FAIL: PUBLIC may execute %', v;
        end if;
    end loop;
    if has_function_privilege('anon', 'member_giving_statement_core(uuid, integer)', 'execute')
       or has_function_privilege('authenticated', 'member_giving_statement_core(uuid, integer)', 'execute') then
        raise exception 'FAIL: the giving statement''s core was reopened';
    end if;
    if not exists (select 1 from feature_catalog where key = 'analytics' and 'association' = any (kinds)
                      and pro_tool = 'analytics') then
        raise exception 'FAIL: the analyses are not offered to an association';
    end if;
    raise notice 'PASS: columns, policies (insert/update, no delete), guard, invoker doors pinned, authenticated only, catalog';
end $$;

\echo ''
\echo '--- 2. allowed: add, edit, same phone, limits, a soft removal ---'
do $$
declare v text; v_m1 text; v_m2 text; v_gift uuid;
begin
    v_m1 := pg_temp.v148('14814814-0000-0000-0000-000000000001', $q$select save_association_member('14800000-0000-0000-0000-000000000001', null,
        '  Membre n° 01 ', '+226 70 00 00 01', ' Trésorier ', current_date - 10)::text$q$);
    if v_m1 like 'ERR:%' then raise exception 'FAIL: the owner could not add: %', v_m1; end if;
    if (select full_name || '|' || phone || '|' || note || '|' || joined_on from church_members where id = v_m1::uuid)
       <> 'Membre n° 01|+22670000001|Trésorier|' || (current_date - 10) then
        raise exception 'FAIL: the member was not kept as typed and trimmed';
    end if;
    v_m2 := pg_temp.v148('14814814-0000-0000-0000-000000000002', $q$select save_association_member('14800000-0000-0000-0000-000000000001', null,
        'Membre n° 02', '+22670000002')::text$q$);
    if v_m2 like 'ERR:%' then raise exception 'FAIL: an employee could not add: %', v_m2; end if;
    if (select joined_on from church_members where id = v_m2::uuid) is null then
        raise exception 'FAIL: no date of joining by default';
    end if;
    -- Edit.
    v := pg_temp.v148('14814814-0000-0000-0000-000000000002', format($q$select save_association_member('14800000-0000-0000-0000-000000000001', %L,
        'Membre n° 02 bis', '+22670000002', 'Section jeunes')::text$q$, v_m2));
    if v <> v_m2 or (select full_name || '|' || note from church_members where id = v_m2::uuid) <> 'Membre n° 02 bis|Section jeunes' then
        raise exception 'FAIL: the edit was not kept: %', v;
    end if;
    -- The same phone: refused, then taken when allowed.
    v := pg_temp.v148('14814814-0000-0000-0000-000000000001', $q$select save_association_member('14800000-0000-0000-0000-000000000001', null,
        'Membre n° 03', '+22670000001')::text$q$);
    if v not like 'ERR: MA148 Ce numéro est déjà celui de Membre n° 01.' then
        raise exception 'FAIL: the same phone was not warned: %', v;
    end if;
    v := pg_temp.v148('14814814-0000-0000-0000-000000000001', $q$select save_association_member('14800000-0000-0000-0000-000000000001', null,
        'Membre n° 03', '+22670000001', null, null, true)::text$q$);
    if v like 'ERR:%' then raise exception 'FAIL: the same phone allowed was refused: %', v; end if;
    -- Editing a member keeps their own phone without a warning.
    v := pg_temp.v148('14814814-0000-0000-0000-000000000001', format($q$select save_association_member('14800000-0000-0000-0000-000000000001', %L,
        'Membre n° 01', '+22670000001', 'Trésorier', null, true)::text$q$, v_m1));
    if v <> v_m1 then raise exception 'FAIL: the member''s own phone: %', v; end if;
    -- Limits.
    if pg_temp.v148('14814814-0000-0000-0000-000000000001', $q$select save_association_member('14800000-0000-0000-0000-000000000001', null, 'Membre n° 04', null, repeat('x', 81))::text$q$)
          not like 'ERR:%80 caractères%'
       or pg_temp.v148('14814814-0000-0000-0000-000000000001', $q$select save_association_member('14800000-0000-0000-0000-000000000001', null, 'Membre n° 04', null, null, current_date + 30)::text$q$)
          not like 'ERR:%futur%'
       or pg_temp.v148('14814814-0000-0000-0000-000000000001', $q$select save_association_member('14800000-0000-0000-0000-000000000001', null, '   ')::text$q$)
          not like 'ERR:%Le nom du membre%' then
        raise exception 'FAIL: a long note, a future date or an empty name was taken';
    end if;
    -- A soft removal: the gift stays theirs and on the statement.
    v_gift := pg_temp.gift148(v_m2::uuid, 2500, 'Donations');
    v := pg_temp.v148('14814814-0000-0000-0000-000000000002', format('select remove_association_member(%L)::text', v_m2));
    if v like 'ERR:%' then raise exception 'FAIL: the employee could not remove: %', v; end if;
    if (select is_active from church_members where id = v_m2::uuid)
       or (select removed_at from church_members where id = v_m2::uuid) is null
       or not exists (select 1 from contribution_attributions where journal_entry_id = v_gift and member_id = v_m2::uuid) then
        raise exception 'FAIL: the removal was not soft';
    end if;
    if pg_temp.v148('14814814-0000-0000-0000-000000000001', format('select sum(amount)::text from member_giving_statement(%L, extract(year from current_date)::int)', v_m2)) <> '2500.00' then
        raise exception 'FAIL: the removed member''s statement lost the gift';
    end if;
    if pg_temp.v148('14814814-0000-0000-0000-000000000001', format('select count(*)::text from association_members(%L) where id = %L', '14800000-0000-0000-0000-000000000001', v_m2)) <> '0' then
        raise exception 'FAIL: a removed member is still listed';
    end if;
    if pg_temp.v148('14814814-0000-0000-0000-000000000001', format('select remove_association_member(%L)::text', v_m2)) not like 'ERR:%pas modifiable%'
       or pg_temp.v148('14814814-0000-0000-0000-000000000001', format($q$select save_association_member('14800000-0000-0000-0000-000000000001', %L, 'Revenu')::text$q$, v_m2))
          not like 'ERR:%pas modifiable%' then
        raise exception 'FAIL: a removed member was changed again';
    end if;
    raise notice 'PASS: added by the owner and an employee, trimmed, edited, the same phone warned then allowed, limits held, removed softly with the gift kept';
end $$;

\echo ''
\echo '--- 3. refused: observers, approvers, deletes, moves, strangers, anon, shops and farms ---'
do $$
declare v text; v_m uuid;
begin
    select id into v_m from church_members where org_id = '14800000-0000-0000-0000-000000000001' and full_name = 'Membre n° 01';
    foreach v in array array['14814814-0000-0000-0000-000000000003', '14814814-0000-0000-0000-000000000004', '14814814-0000-0000-0000-000000000005'] loop
        if pg_temp.v148(v::uuid, $q$select save_association_member('14800000-0000-0000-0000-000000000001', null, 'Intrus')::text$q$) not like 'ERR:%'
           or pg_temp.v148(v::uuid, format($q$select save_association_member('14800000-0000-0000-0000-000000000001', %L, 'Changé')::text$q$, v_m)) not like 'ERR:%'
           or pg_temp.v148(v::uuid, format('select remove_association_member(%L)::text', v_m)) not like 'ERR:%'
           or pg_temp.n148(v::uuid, format('update church_members set full_name = %L where id = %L', 'Changé', v_m)) <> '0'
           or pg_temp.n148(v::uuid, format('insert into church_members (org_id, full_name) values (%L, %L)', '14800000-0000-0000-0000-000000000001', 'Intrus')) not like 'ERR:%' then
            raise exception 'FAIL: % wrote a member', v;
        end if;
    end loop;
    if pg_temp.n148('14814814-0000-0000-0000-000000000001', format('delete from church_members where id = %L', v_m)) <> '0'
       or not exists (select 1 from church_members where id = v_m) then
        raise exception 'FAIL: a member was deleted';
    end if;
    if pg_temp.n148('14814814-0000-0000-0000-000000000001', format('update church_members set org_id = %L where id = %L', '14800000-0000-0000-0000-000000000005', v_m)) not like 'ERR:%reste dans son association%' then
        raise exception 'FAIL: a member moved to another business';
    end if;
    -- Another association's owner.
    if pg_temp.v148('14814814-0000-0000-0000-000000000006', format('select count(*)::text from church_members where org_id = %L', '14800000-0000-0000-0000-000000000001')) <> '0'
       or pg_temp.v148('14814814-0000-0000-0000-000000000006', format('select count(*)::text from association_members(%L)', '14800000-0000-0000-0000-000000000001')) not like 'ERR:%Réservé aux associations%'
       or pg_temp.v148('14814814-0000-0000-0000-000000000006', format($q$select save_association_member('14800000-0000-0000-0000-000000000001', %L, 'Changé')::text$q$, v_m)) not like 'ERR:%'
       or pg_temp.v148('14814814-0000-0000-0000-000000000006', format('select remove_association_member(%L)::text', v_m)) not like 'ERR:%pas modifiable%'
       or pg_temp.v148('14814814-0000-0000-0000-000000000006', format('select count(*)::text from association_member_history(%L)', v_m)) <> '0'
       or pg_temp.v148('14814814-0000-0000-0000-000000000006', format('select association_analytics(%L)::text', '14800000-0000-0000-0000-000000000001')) not like 'ERR:%Réservé aux membres%' then
        raise exception 'FAIL: another association reached this one''s members';
    end if;
    -- anon.
    if pg_temp.v148(null, format('select count(*)::text from association_members(%L)', '14800000-0000-0000-0000-000000000001')) not like 'ERR: 42501%'
       or pg_temp.v148(null, format($q$select save_association_member(%L, null, 'Intrus')::text$q$, '14800000-0000-0000-0000-000000000001')) not like 'ERR: 42501%'
       or pg_temp.v148(null, format('select association_analytics(%L)::text', '14800000-0000-0000-0000-000000000001')) not like 'ERR: 42501%'
       or pg_temp.v148(null, format('select count(*)::text from association_member_history(%L)', v_m)) not like 'ERR: 42501%' then
        raise exception 'FAIL: anon reached a door';
    end if;
    -- A farm and a shop.
    if pg_temp.v148('14814814-0000-0000-0000-000000000007', $q$select save_association_member('14800000-0000-0000-0000-000000000003', null, 'Ouvrier')::text$q$) not like 'ERR:%Réservé aux associations%'
       or pg_temp.v148('14814814-0000-0000-0000-000000000007', $q$select save_association_member('14800000-0000-0000-0000-000000000004', null, 'Client')::text$q$) not like 'ERR:%Réservé aux associations%'
       or pg_temp.v148('14814814-0000-0000-0000-000000000007', format('select count(*)::text from association_members(%L)', '14800000-0000-0000-0000-000000000003')) not like 'ERR:%Réservé aux associations%'
       or pg_temp.v148('14814814-0000-0000-0000-000000000007', format('select association_analytics(%L)::text', '14800000-0000-0000-0000-000000000003')) not like 'ERR:%Réservé aux associations%'
       or pg_temp.v148('14814814-0000-0000-0000-000000000007', format('select association_analytics(%L)::text', '14800000-0000-0000-0000-000000000004')) not like 'ERR:%Réservé aux associations%' then
        raise exception 'FAIL: a farm or a shop was answered';
    end if;
    raise notice 'PASS: observers, approvers and a summary observer write nothing; no delete; no move; a stranger, anon, a farm and a shop refused';
end $$;

\echo ''
\echo '--- 4. the list: totals, an undone gift left out, a summary observer''s nulls ---'
do $$
declare v text; v_m uuid; v_e uuid; v_rev text;
begin
    select id into v_m from church_members where org_id = '14800000-0000-0000-0000-000000000001' and full_name = 'Membre n° 01';
    perform pg_temp.gift148(v_m, 1000, 'Cotisations');
    perform pg_temp.gift148(v_m, 3000, 'Donations');
    perform pg_temp.gift148(v_m, 500,  'Dîme');
    -- Last year: not this year's.
    perform pg_temp.gift148(v_m, 7000, 'Donations', now() - interval '1 year');
    -- Undone: left out everywhere.
    v_e := pg_temp.gift148(v_m, 9000, 'Donations');
    v_rev := pg_temp.v148('14814814-0000-0000-0000-000000000001', format('select reverse_entry(%L, %L, ''Erreur'')::text', v_e, '14814814-0000-0000-0000-000000000001'));
    if v_rev like 'ERR:%' then raise exception 'FAIL: the gift could not be undone: %', v_rev; end if;
    v := pg_temp.v148('14814814-0000-0000-0000-000000000001', format(
        'select given_year || ''|'' || cotisations_year || ''|'' || dons_year || ''|'' || last_given_on || ''|'' || coalesce(note, '''')
           from association_members(%L) where id = %L', '14800000-0000-0000-0000-000000000001', v_m));
    if v <> '4500.00|1000.00|3000.00|' || (now() at time zone 'Africa/Ouagadougou')::date || '|Trésorier' then
        raise exception 'FAIL: the list says %', v;
    end if;
    v := pg_temp.v148('14814814-0000-0000-0000-000000000001', format('select count(*) || ''|'' || sum(amount) filter (where not reversed) || ''|'' || count(*) filter (where kind = ''autre'') || ''|'' || count(*) filter (where reversed)
                                      from association_member_history(%L)', v_m));
    if v <> '5|11500.00|1|1' then
        raise exception 'FAIL: the history says %', v;
    end if;
    if pg_temp.v148('14814814-0000-0000-0000-000000000001', format('select coalesce(sum(amount), 0)::text from member_giving_statement(%L, extract(year from current_date)::int)', v_m)) <> '4500.00' then
        raise exception 'FAIL: the giving statement still has the undone gift';
    end if;
    v := pg_temp.v148('14814814-0000-0000-0000-000000000005', format('select count(*) || ''|'' || count(given_year) || ''|'' || count(dues_status) from association_members(%L)', '14800000-0000-0000-0000-000000000001'));
    if v <> '2|0|0' then
        raise exception 'FAIL: a summary observer was given amounts: %', v;
    end if;
    if pg_temp.v148('14814814-0000-0000-0000-000000000005', format('select count(*)::text from association_member_history(%L)', v_m)) <> '0' then
        raise exception 'FAIL: a summary observer read the history';
    end if;
    raise notice 'PASS: this year''s total, cotisations and dons; an undone gift out of the list, the history and the statement; a summary observer''s names and nulls';
end $$;

\echo ''
\echo '--- 5. where a member stands on the usual cotisation ---'
do $$
declare v text; v_new uuid; v_old uuid; v_typed uuid; v_m0 date := date_trunc('month', (now() at time zone 'Africa/Ouagadougou'))::date;
begin
    if pg_temp.v148('14814814-0000-0000-0000-000000000001', format('select count(dues_status)::text from association_members(%L)', '14800000-0000-0000-0000-000000000001')) <> '0' then
        raise exception 'FAIL: a status without a usual cotisation';
    end if;
    perform pg_temp.v148('14814814-0000-0000-0000-000000000001', format('select set_contribution_default(%L, 1000, ''month'')::text', '14800000-0000-0000-0000-000000000001'));
    v_new := pg_temp.v148('14814814-0000-0000-0000-000000000001', $q$select save_association_member('14800000-0000-0000-0000-000000000001', null, 'Membre n° 05')::text$q$)::uuid;
    v_old := pg_temp.v148('14814814-0000-0000-0000-000000000001', $q$select save_association_member('14800000-0000-0000-0000-000000000001', null, 'Membre n° 06')::text$q$)::uuid;
    v_typed := pg_temp.v148('14814814-0000-0000-0000-000000000001', $q$select save_association_member('14800000-0000-0000-0000-000000000001', null, 'Membre n° 07', null, null, date '2015-01-10')::text$q$)::uuid;
    -- Membre n° 06 was entered three months ago.
    update church_members set created_at = (v_m0 - interval '3 months') + interval '5 days',
                              joined_on = (v_m0 - interval '3 months')::date + 5
     where id = v_old;
    perform pg_temp.gift148(v_old, 1000, 'Cotisations');
    v := pg_temp.v148('14814814-0000-0000-0000-000000000001', format('select string_agg(full_name || '':'' || dues_status || '':'' || coalesce(late_since::text, ''-''), '', '' order by full_name)
                                        from association_members(%L) where id in (%L, %L, %L)', '14800000-0000-0000-0000-000000000001', v_new, v_old, v_typed));
    if v <> format('Membre n° 05:due:-, Membre n° 06:late:%s, Membre n° 07:due:-', (v_m0 - interval '2 months')::date) then
        raise exception 'FAIL: the statuses are %', v;
    end if;
    perform pg_temp.gift148(v_old, 3000, 'Cotisations');
    v := pg_temp.v148('14814814-0000-0000-0000-000000000001', format('select dues_status || '':'' || paid_through from association_members(%L) where id = %L', '14800000-0000-0000-0000-000000000001', v_old));
    if v <> 'up_to_date:' || ((v_m0 + interval '1 month')::date - 1) then
        raise exception 'FAIL: four months paid says %', v;
    end if;
    -- Membre n° 01 paid one cotisation this month: up to date.
    if pg_temp.v148('14814814-0000-0000-0000-000000000001', format($q$select dues_status from association_members(%L) where full_name = 'Membre n° 01'$q$, '14800000-0000-0000-0000-000000000001')) <> 'up_to_date' then
        raise exception 'FAIL: a member who paid this month is not up to date';
    end if;
    raise notice 'PASS: none without a usual cotisation; due this month, never late; late since the first month not covered; up to date with paid_through; counted from the day entered';
end $$;

\echo ''
\echo '--- 6. the analyses ---'
do $$
declare v jsonb; t text; v_m uuid;
begin
    select id into v_m from church_members where org_id = '14800000-0000-0000-0000-000000000001' and full_name = 'Membre n° 01';
    -- An expense, in two categories.
    perform pg_temp.v148('14814814-0000-0000-0000-000000000001', format($q$select record_entry(%L, 2000, 'out', 'Loyer de la salle', null, 'Loyer')::text$q$, '14800000-0000-0000-0000-000000000001'));
    perform pg_temp.v148('14814814-0000-0000-0000-000000000001', format($q$select record_entry(%L, 1500, 'out', 'Eau', null, 'Eau et électricité')::text$q$, '14800000-0000-0000-0000-000000000001'));
    t := pg_temp.v148('14814814-0000-0000-0000-000000000001', format('select association_analytics(%L, date_trunc(''year'', current_date)::date, current_date)::text', '14800000-0000-0000-0000-000000000001'));
    if t like 'ERR:%' then raise exception 'FAIL: the owner''s analyses: %', t; end if;
    v := t::jsonb;
    if jsonb_array_length(v -> 'months') <> 12
       or (v -> 'months' -> 11 ->> 'month') <> to_char(date_trunc('month', (now() at time zone 'Africa/Ouagadougou')), 'YYYY-MM-DD') then
        raise exception 'FAIL: not twelve months ending this one: %', v -> 'months';
    end if;
    -- This month: in = 1000+3000+500 (+ n° 02's 2500, n° 06's 4000), the undone 9000 nets out.
    if (v -> 'months' -> 11 ->> 'income')::numeric <> 11000
       or (v -> 'months' -> 11 ->> 'expenses')::numeric <> 3500
       or (v -> 'months' -> 11 ->> 'balance')::numeric
          <> (select coalesce(sum(jl.debit - jl.credit), 0) from journal_lines jl
                join journal_entries je on je.id = jl.journal_entry_id join accounts a on a.id = jl.account_id
               where je.org_id = '14800000-0000-0000-0000-000000000001' and a.type = 'asset') then
        raise exception 'FAIL: this month says %', v -> 'months' -> 11;
    end if;
    if (select string_agg((e ->> 'name') || '=' || (e ->> 'amount')::numeric::int || ':' || (e ->> 'entries'), ', ' order by e ->> 'name' collate "C")
          from jsonb_array_elements(v -> 'income') e) <> 'Cotisations=5000:3, Donations=5500:2, Dîme=500:1' then
        raise exception 'FAIL: income by category %', v -> 'income';
    end if;
    if (select string_agg((e ->> 'name') || '=' || (e ->> 'amount')::numeric::int, ', ' order by e ->> 'name' collate "C")
          from jsonb_array_elements(v -> 'expenses') e) <> 'Eau et électricité=1500, Loyer=2000' then
        raise exception 'FAIL: expenses by category %', v -> 'expenses';
    end if;
    if (v -> 'members' ->> 'registered')::int <> 5
       or (v -> 'members' ->> 'gave')::int <> 2
       or not (v -> 'members' ->> 'has_dues')::boolean
       or (v -> 'members' ->> 'up_to_date')::int <> 2
       or (v -> 'members' ->> 'due')::int <> 3
       or (v -> 'members' ->> 'late')::int <> 0
       or jsonb_array_length(v -> 'members' -> 'new_by_month') <> 12 then
        raise exception 'FAIL: the members say %', v -> 'members';
    end if;
    -- Membre n° 02 bis gave too, and was removed: not listed.
    if (v -> 'top_givers' -> 0 ->> 'name') <> 'Membre n° 01'
       or (v -> 'top_givers' -> 0 ->> 'amount')::numeric <> 4500
       or (v -> 'top_givers' -> 1 ->> 'name') <> 'Membre n° 06'
       or jsonb_array_length(v -> 'top_givers') <> 2 then
        raise exception 'FAIL: the top givers %', v -> 'top_givers';
    end if;
    -- An employee with full visibility: no names.
    v := pg_temp.v148('14814814-0000-0000-0000-000000000002', format('select association_analytics(%L)::text', '14800000-0000-0000-0000-000000000001'))::jsonb;
    if v -> 'top_givers' <> 'null'::jsonb or v -> 'income' = 'null'::jsonb then
        raise exception 'FAIL: the employee''s analyses %', v -> 'top_givers';
    end if;
    -- A summary observer: the totals only.
    t := pg_temp.v148('14814814-0000-0000-0000-000000000005', format('select association_analytics(%L)::text', '14800000-0000-0000-0000-000000000001'));
    if t like 'ERR:%' then raise exception 'FAIL: the summary observer was refused: %', t; end if;
    v := t::jsonb;
    if (v -> 'months' -> 11 ->> 'income')::numeric <> 11000
       or (v -> 'months' -> 11 ->> 'expenses')::numeric <> 3500
       or (v -> 'months' -> 11 ->> 'balance') is null
       or v -> 'income' <> 'null'::jsonb or v -> 'expenses' <> 'null'::jsonb
       or v -> 'top_givers' <> 'null'::jsonb
       or v -> 'members' -> 'gave' <> 'null'::jsonb
       or (v -> 'members' ->> 'registered')::int <> 5 then
        raise exception 'FAIL: the summary observer saw %', v;
    end if;
    -- Free: Marakaj Pro's words.
    if pg_temp.v148('14814814-0000-0000-0000-000000000001', format('select association_analytics(%L)::text', '14800000-0000-0000-0000-000000000005')) not like 'ERR:%Marakaj Pro :%' then
        raise exception 'FAIL: a Free association read its analyses';
    end if;
    -- The switchboard hides it (on a business that has not paid for it:
    -- a paid tool is never hidden, 104).
    insert into feature_rules (scope, org_id, feature, state) values ('org', '14800000-0000-0000-0000-000000000005', 'analytics', 'hidden');
    if pg_temp.v148('14814814-0000-0000-0000-000000000001', format('select association_analytics(%L)::text', '14800000-0000-0000-0000-000000000005')) not like 'ERR: MA002%' then
        raise exception 'FAIL: the switchboard did not hide the analyses';
    end if;
    delete from feature_rules where org_id = '14800000-0000-0000-0000-000000000005' and feature = 'analytics';
    -- The reports dial at hidden for the employee.
    insert into org_feature_rules (org_id, tier, feature, access) values ('14800000-0000-0000-0000-000000000001', 'employee', 'reports', 'hidden');
    if pg_temp.v148('14814814-0000-0000-0000-000000000002', format('select association_analytics(%L)::text', '14800000-0000-0000-0000-000000000001')) not like 'ERR:%' then
        raise exception 'FAIL: the reports dial did not close the analyses';
    end if;
    delete from org_feature_rules where org_id = '14800000-0000-0000-0000-000000000001';
    raise notice 'PASS: twelve months in, out and held; income and expenses by category; the members'' counts; top givers for an admin only; a summary''s totals; Pro, the switchboard and the dial hold';
end $$;

rollback;

\echo ''
\echo '=== test_batch148.sql: all checks passed ==='
