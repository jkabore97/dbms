-- ============================================================
-- test_batch149.sql — batch 153 (149): the recette and dépense types a
-- business adds itself, kept in its chart of accounts.
--
-- The claims:
--   1. installed twice, the same: accounts.label (1 to 60) and
--      sort_order; money_types SECURITY INVOKER; save_money_type,
--      reorder_money_types and money_type_writer SECURITY DEFINER; every
--      one with its search path pinned; the three doors authenticated's
--      and never anon's or PUBLIC's; the fold and the writer test
--      nobody's;
--   2. allowed: the owner adds « Quête » with a description, an employee
--      adds « Loyer de salle »; an entry recorded under « Quête »
--      (record_entry, 007) lands on that very account — no second one —
--      and the income statement and 148's analyses count it; money_types
--      lists it with its line;
--   3. a duplicate is refused (MA149) accents, case and spaces aside —
--      « quete », « QUÊTE  », « Dons » is not a duplicate of 'Donations'
--      on the server (the app refuses that one), an expense name may
--      repeat an income one; with adopt, the account of that name is
--      taken (and shown again) instead;
--   4. renaming: a type nothing was posted to takes the new name itself;
--      one with entries keeps its name (the entries keep it) and takes
--      the label; renaming into another type's name is refused;
--   5. hiding keeps the account and its entries: is_active false, the
--      lines still there, still listed (hidden), still posted to by name;
--      shown again;
--   6. the order: sort_order as given, another business's id untouched;
--   7. refused: an observer, an approver and a summary observer add,
--      rename, hide and order nothing; another business's owner touches
--      nothing (by their business or by ours); anon executes nothing; a
--      suspended business writes nothing; an income type for a shop or a
--      farm is refused (an expense type for a farm is not); an asset
--      account is no type; nobody writes on behalf of another;
--      money_types answers a stranger nothing.
-- Names: « Le trésorier », brand-like businesses; Ouagadougou. Wrapped
-- in one transaction rolled back: runs twice the same.
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
-- As test_batch148: the app's role may call the books' doors (record_entry,
-- income_statement…); then 149 again, twice — what it grants and revokes
-- is what is tested.
grant execute on all functions in schema public to authenticated;
\i database/migrations/149_money_types.sql
\i database/migrations/149_money_types.sql

begin;

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('14914914-0000-0000-0000-000000000001', '+22614900001', 'owner149@example.com', '{"full_name": "Présidence Cercle Horizon"}', now() - interval '1 year'),
    ('14914914-0000-0000-0000-000000000002', '+22614900002', 'emp149@example.com',   '{"full_name": "Le trésorier"}',             now() - interval '1 year'),
    ('14914914-0000-0000-0000-000000000003', '+22614900003', 'obs149@example.com',   '{"full_name": "Regard Cercle Horizon"}',    now() - interval '1 year'),
    ('14914914-0000-0000-0000-000000000004', '+22614900004', 'appr149@example.com',  '{"full_name": "Visa Cercle Horizon"}',      now() - interval '1 year'),
    ('14914914-0000-0000-0000-000000000005', '+22614900005', 'summ149@example.com',  '{"full_name": "Partenaire Cercle Horizon"}', now() - interval '1 year'),
    ('14914914-0000-0000-0000-000000000006', '+22614900006', 'rival149@example.com', '{"full_name": "Présidence Club Zénith"}',   now() - interval '1 year'),
    ('14914914-0000-0000-0000-000000000007', '+22614900007', 'farm149@example.com',  '{"full_name": "Gérance Ferme Aurore"}',     now() - interval '1 year');
update profiles p set phone = u.phone from auth.users u where u.id = p.id and p.phone is null;

insert into orgs (id, name, slug, profile, default_currency, plan, plan_until, city) values
    ('14900000-0000-0000-0000-000000000001', 'Cercle Horizon', 'cercle-horizon-149', 'association', 'XOF', 'pro', current_date + 30, 'Ouagadougou'),
    ('14900000-0000-0000-0000-000000000002', 'Club Zénith',    'club-zenith-149',    'association', 'XOF', 'free', null,            'Ouagadougou'),
    ('14900000-0000-0000-0000-000000000003', 'Ferme Aurore',   'ferme-aurore-149',   'farm',        'XOF', 'free', null,            'Ouagadougou'),
    ('14900000-0000-0000-0000-000000000004', 'Kiosque Vega',   'kiosque-vega-149',   'retail',      'XOF', 'free', null,            'Ouagadougou');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    ('14900000-0000-0000-0000-000000000001', '14914914-0000-0000-0000-000000000001', 'owner',    'org', '14900000-0000-0000-0000-000000000001', 'full'),
    ('14900000-0000-0000-0000-000000000001', '14914914-0000-0000-0000-000000000002', 'employee', 'org', '14900000-0000-0000-0000-000000000001', 'full'),
    ('14900000-0000-0000-0000-000000000001', '14914914-0000-0000-0000-000000000003', 'observer', 'org', '14900000-0000-0000-0000-000000000001', 'full'),
    ('14900000-0000-0000-0000-000000000001', '14914914-0000-0000-0000-000000000004', 'approver', 'org', '14900000-0000-0000-0000-000000000001', 'full'),
    ('14900000-0000-0000-0000-000000000001', '14914914-0000-0000-0000-000000000005', 'observer', 'org', '14900000-0000-0000-0000-000000000001', 'summary'),
    ('14900000-0000-0000-0000-000000000002', '14914914-0000-0000-0000-000000000006', 'owner',    'org', '14900000-0000-0000-0000-000000000002', 'full'),
    ('14900000-0000-0000-0000-000000000003', '14914914-0000-0000-0000-000000000007', 'owner',    'org', '14900000-0000-0000-0000-000000000003', 'full'),
    ('14900000-0000-0000-0000-000000000004', '14914914-0000-0000-0000-000000000007', 'owner',    'org', '14900000-0000-0000-0000-000000000004', 'full');
select seed_church_accounts('14900000-0000-0000-0000-000000000001') \gset zz_
select seed_church_accounts('14900000-0000-0000-0000-000000000002') \gset zz_
select seed_farm_accounts('14900000-0000-0000-0000-000000000003') \gset zz_
select seed_retail_accounts('14900000-0000-0000-0000-000000000004') \gset zz_

-- As PostgREST names a caller.
create function pg_temp.as149(p_who uuid)
returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true),
           set_config('request.jwt.claims', case when p_who is null then '' else
                      json_build_object('sub', p_who, 'role', 'authenticated')::text end, true);
$$;

-- A value as somebody, under their role (anon when nobody): its text, or
-- « ERR: <sqlstate> <message> ».
create function pg_temp.v149(p_who uuid, p_sql text)
returns text language plpgsql as $$
declare v text;
begin
    perform pg_temp.as149(p_who);
    execute case when p_who is null then 'set local role anon' else 'set local role authenticated' end;
    execute p_sql into v;
    execute 'reset role';
    return coalesce(v, '<null>');
exception when others then
    execute 'reset role';
    return 'ERR: ' || sqlstate || ' ' || sqlerrm;
end;
$$;

create function pg_temp.must149(p_label text, p_got text, p_want text)
returns void language plpgsql as $$
begin
    if p_got is distinct from p_want then
        raise exception 'FAIL: % — got %, wanted %', p_label, p_got, p_want;
    end if;
    raise notice 'PASS: %', p_label;
end;
$$;

create function pg_temp.err149(p_label text, p_got text, p_like text)
returns void language plpgsql as $$
begin
    if p_got not like 'ERR:%' or p_got not like p_like then
        raise exception 'FAIL: % — got %', p_label, p_got;
    end if;
    raise notice 'PASS: % (%)', p_label, left(p_got, 90);
end;
$$;

create function pg_temp.add149(p_who uuid, p_org uuid, p_dir text, p_name text,
                               p_desc text default null, p_adopt boolean default false)
returns text language sql as $$
    select pg_temp.v149(p_who, format(
        'select save_money_type(%L::uuid, %L, null, %L, %L, null, %L)::text',
        p_org, p_dir, p_name, p_desc, p_adopt));
$$;

create function pg_temp.set149(p_who uuid, p_org uuid, p_dir text, p_id uuid,
                               p_name text default null, p_desc text default null,
                               p_active boolean default null)
returns text language sql as $$
    select pg_temp.v149(p_who, format(
        'select save_money_type(%L::uuid, %L, %L::uuid, %L, %L, %L::boolean)::text',
        p_org, p_dir, p_id, p_name, p_desc, p_active));
$$;

\echo ''
\echo '--- 1. installed twice, the same ---'
do $$
declare v text;
begin
    if not exists (select 1 from information_schema.columns where table_name = 'accounts' and column_name = 'label')
       or not exists (select 1 from information_schema.columns where table_name = 'accounts' and column_name = 'sort_order') then
        raise exception 'FAIL: accounts.label or sort_order is missing';
    end if;
    if not exists (select 1 from pg_constraint where conname = 'accounts_label_length') then
        raise exception 'FAIL: no label length check';
    end if;
    select string_agg(p.proname || ':' || p.prosecdef::text, ', ' order by p.proname) into v
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('money_types', 'save_money_type', 'reorder_money_types', 'money_type_writer', 'money_type_key');
    perform pg_temp.must149('the security modes', v,
        'money_type_key:false, money_type_writer:true, money_types:false, reorder_money_types:true, save_money_type:true');
    select string_agg(p.proname, ', ' order by p.proname) into v
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('money_types', 'save_money_type', 'reorder_money_types', 'money_type_writer', 'money_type_key')
       and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=public%');
    perform pg_temp.must149('every search path pinned', v, null);
    foreach v in array array['money_types(uuid)',
                             'save_money_type(uuid, text, uuid, text, text, boolean, boolean, uuid)',
                             'reorder_money_types(uuid, text, uuid[])'] loop
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
    foreach v in array array['money_type_key(text)', 'money_type_writer(uuid)'] loop
        if has_function_privilege('anon', v, 'execute') or has_function_privilege('authenticated', v, 'execute') then
            raise exception 'FAIL: % is open to an app role', v;
        end if;
    end loop;
    raise notice 'PASS: the three doors authenticated''s alone, the fold and the writer test nobody''s';
end $$;

\echo ''
\echo '--- 2. allowed: adding, and an entry lands on the type ---'
do $$
declare
    v_owner uuid := '14914914-0000-0000-0000-000000000001';
    v_emp   uuid := '14914914-0000-0000-0000-000000000002';
    v_org   uuid := '14900000-0000-0000-0000-000000000001';
    v_quete text; v_loyer text; v_entry text; v text; n int;
begin
    v_quete := pg_temp.add149(v_owner, v_org, 'in', '  Quête ', 'Le dimanche, à la sortie');
    if v_quete like 'ERR:%' then raise exception 'FAIL: the owner could not add « Quête »: %', v_quete; end if;
    perform pg_temp.must149('« Quête » is an income account of the business, trimmed, described',
        (select a.org_id || '|' || a.type || '|' || a.name || '|' || a.description || '|' || a.is_active
           from accounts a where a.id = v_quete::uuid),
        v_org || '|income|Quête|Le dimanche, à la sortie|true');
    perform pg_temp.must149('its code is in the income band',
        (select (code::int between 4000 and 4999)::text from accounts where id = v_quete::uuid), 'true');

    v_loyer := pg_temp.add149(v_emp, v_org, 'in', 'Loyer de salle');
    if v_loyer like 'ERR:%' then raise exception 'FAIL: the employee could not add a type: %', v_loyer; end if;
    raise notice 'PASS: an employee adds « Loyer de salle »';

    -- An entry under « Quête », as the phone sends it (category = the name).
    v_entry := pg_temp.v149(v_emp, format(
        'select record_entry(%L::uuid, 7500, ''in'', ''Quête'', null, ''Quête'', ''cash'')::text', v_org));
    if v_entry like 'ERR:%' then raise exception 'FAIL: the entry was not recorded: %', v_entry; end if;
    perform pg_temp.must149('the entry is credited to « Quête » itself',
        (select jl.account_id::text from journal_lines jl
          where jl.journal_entry_id = v_entry::uuid and jl.credit > 0), v_quete);
    select count(*) into n from accounts where org_id = v_org and lower(name) = 'quête';
    perform pg_temp.must149('no second « Quête » account', n::text, '1');

    v := pg_temp.v149(v_owner, format(
        'select amount::text from income_statement(%L::uuid) where section = ''income'' and name = ''Quête''', v_org));
    perform pg_temp.must149('the income statement counts it', v, '7500.00');
    v := pg_temp.v149(v_owner, format(
        'select (select x->>''amount'' from jsonb_array_elements(association_analytics(%L::uuid)->''income'') x where x->>''name'' = ''Quête'')', v_org));
    perform pg_temp.must149('the analyses (148) count it', v, '7500.00');
    v := pg_temp.v149(v_emp, format(
        'select name || ''|'' || entry_count || ''|'' || is_active from money_types(%L::uuid) where account_id = %L::uuid', v_org, v_quete));
    perform pg_temp.must149('money_types lists it with its lines', v, 'Quête|1|true');
end $$;

\echo ''
\echo '--- 3. a duplicate is refused; adopt takes it ---'
do $$
declare
    v_owner uuid := '14914914-0000-0000-0000-000000000001';
    v_org   uuid := '14900000-0000-0000-0000-000000000001';
    v_quete uuid := (select id from accounts where org_id = '14900000-0000-0000-0000-000000000001' and name = 'Quête');
    v text;
begin
    perform pg_temp.err149('« quete » refused', pg_temp.add149(v_owner, v_org, 'in', 'quete'), 'ERR: MA149 %');
    perform pg_temp.err149('« QUÊTE  » refused', pg_temp.add149(v_owner, v_org, 'in', 'QUÊTE  '), 'ERR: MA149 %');
    perform pg_temp.err149('« donations » refused (the seeded account)', pg_temp.add149(v_owner, v_org, 'in', 'donations'), 'ERR: MA149 %');
    v := pg_temp.add149(v_owner, v_org, 'out', 'Quête');
    if v like 'ERR:%' then raise exception 'FAIL: an expense may share an income type''s name: %', v; end if;
    raise notice 'PASS: an expense « Quête » is not an income duplicate';
    perform pg_temp.err149('an empty name refused', pg_temp.add149(v_owner, v_org, 'in', '   '), 'ERR: % Le nom du type%');
    perform pg_temp.err149('a name of 61 refused', pg_temp.add149(v_owner, v_org, 'in', repeat('x', 61)), 'ERR: % 60 caractères%');
    perform pg_temp.err149('a description of 81 refused', pg_temp.add149(v_owner, v_org, 'in', 'Kermesse', repeat('x', 81)), 'ERR: % 80 caractères%');

    update accounts set is_active = false where id = v_quete;
    v := pg_temp.add149(v_owner, v_org, 'in', 'Quete', 'ignorée', true);
    perform pg_temp.must149('adopt takes the existing account', v, v_quete::text);
    perform pg_temp.must149('… shows it again, its description kept',
        (select is_active || '|' || description from accounts where id = v_quete), 'true|Le dimanche, à la sortie');
end $$;

\echo ''
\echo '--- 4. renaming ---'
do $$
declare
    v_owner uuid := '14914914-0000-0000-0000-000000000001';
    v_org   uuid := '14900000-0000-0000-0000-000000000001';
    v_quete uuid := (select id from accounts where org_id = '14900000-0000-0000-0000-000000000001' and name = 'Quête' and type = 'income');
    v_loyer uuid := (select id from accounts where org_id = '14900000-0000-0000-0000-000000000001' and name = 'Loyer de salle');
    v text;
begin
    v := pg_temp.set149(v_owner, v_org, 'in', v_loyer, 'Location de la salle');
    if v like 'ERR:%' then raise exception 'FAIL: %', v; end if;
    perform pg_temp.must149('an unused type takes the new name itself',
        (select name || '|' || coalesce(label, '-') from accounts where id = v_loyer), 'Location de la salle|-');

    v := pg_temp.set149(v_owner, v_org, 'in', v_quete, 'Quête du dimanche', '');
    if v like 'ERR:%' then raise exception 'FAIL: %', v; end if;
    perform pg_temp.must149('a used type keeps its name and takes the label (description cleared)',
        (select name || '|' || label || '|' || coalesce(description, '-') from accounts where id = v_quete),
        'Quête|Quête du dimanche|-');
    perform pg_temp.must149('its entries are untouched',
        (select count(*)::text from journal_lines jl join journal_entries je on je.id = jl.journal_entry_id
          where jl.account_id = v_quete and je.label = 'Quête'), '1');
    perform pg_temp.err149('a label is a name for the duplicate test',
        pg_temp.add149(v_owner, v_org, 'in', 'quête du DIMANCHE'), 'ERR: MA149 %');
    perform pg_temp.err149('renaming into another type''s name refused',
        pg_temp.set149(v_owner, v_org, 'in', v_loyer, 'QUÊTE'), 'ERR: MA149 %');
    v := pg_temp.set149(v_owner, v_org, 'in', v_quete, 'Quête');
    perform pg_temp.must149('renamed back to its name, the label goes',
        (select coalesce(label, '-') from accounts where id = v_quete), '-');
    v := pg_temp.set149(v_owner, v_org, 'in', v_quete, 'Quête du dimanche');
end $$;

\echo ''
\echo '--- 5. hiding keeps the account and its entries ---'
do $$
declare
    v_emp   uuid := '14914914-0000-0000-0000-000000000002';
    v_org   uuid := '14900000-0000-0000-0000-000000000001';
    v_quete uuid := (select id from accounts where org_id = '14900000-0000-0000-0000-000000000001' and name = 'Quête' and type = 'income');
    v text;
begin
    v := pg_temp.set149(v_emp, v_org, 'in', v_quete, null, null, false);
    if v like 'ERR:%' then raise exception 'FAIL: the employee could not hide: %', v; end if;
    perform pg_temp.must149('hidden: the account stays, is_active false',
        (select is_active::text from accounts where id = v_quete), 'false');
    perform pg_temp.must149('… its lines stay', (select count(*)::text from journal_lines where account_id = v_quete), '1');
    perform pg_temp.must149('… still listed, hidden',
        pg_temp.v149(v_emp, format('select is_active::text from money_types(%L::uuid) where account_id = %L::uuid', v_org, v_quete)),
        'false');
    v := pg_temp.v149(v_emp, format(
        'select record_entry(%L::uuid, 500, ''in'', ''Quête'', null, ''Quête'', ''cash'')::text', v_org));
    perform pg_temp.must149('… and an entry by its name still posts to it',
        (select jl.account_id::text from journal_lines jl where jl.journal_entry_id = v::uuid and jl.credit > 0),
        v_quete::text);
    v := pg_temp.set149(v_emp, v_org, 'in', v_quete, null, null, true);
    perform pg_temp.must149('shown again', (select is_active::text from accounts where id = v_quete), 'true');
end $$;

\echo ''
\echo '--- 6. the order ---'
do $$
declare
    v_owner uuid := '14914914-0000-0000-0000-000000000001';
    v_org   uuid := '14900000-0000-0000-0000-000000000001';
    v_quete uuid := (select id from accounts where org_id = '14900000-0000-0000-0000-000000000001' and name = 'Quête' and type = 'income');
    v_loc   uuid := (select id from accounts where org_id = '14900000-0000-0000-0000-000000000001' and name = 'Location de la salle');
    v_rival uuid := (select id from accounts where org_id = '14900000-0000-0000-0000-000000000002' and name = 'Donations');
    v text;
begin
    v := pg_temp.v149(v_owner, format('select reorder_money_types(%L::uuid, ''in'', array[%L, %L, %L]::uuid[])::text',
                                     v_org, v_loc, v_rival, v_quete));
    if v like 'ERR:%' then raise exception 'FAIL: %', v; end if;
    perform pg_temp.must149('the order as given',
        (select string_agg(name || '=' || sort_order, ', ' order by sort_order) from accounts where id in (v_loc, v_quete)),
        'Location de la salle=1, Quête=3');
    perform pg_temp.must149('another business''s account untouched',
        (select coalesce(sort_order::text, '-') from accounts where id = v_rival), '-');
    perform pg_temp.must149('money_types reads in that order',
        pg_temp.v149(v_owner, format('select string_agg(name, '', '') from (select name from money_types(%L::uuid) where type = ''income'' and sort_order is not null) x', v_org)),
        'Location de la salle, Quête');
end $$;

\echo ''
\echo '--- 7. refused ---'
do $$
declare
    v_obs   uuid := '14914914-0000-0000-0000-000000000003';
    v_appr  uuid := '14914914-0000-0000-0000-000000000004';
    v_summ  uuid := '14914914-0000-0000-0000-000000000005';
    v_rival uuid := '14914914-0000-0000-0000-000000000006';
    v_farm  uuid := '14914914-0000-0000-0000-000000000007';
    v_owner uuid := '14914914-0000-0000-0000-000000000001';
    v_org   uuid := '14900000-0000-0000-0000-000000000001';
    v_quete uuid := (select id from accounts where org_id = '14900000-0000-0000-0000-000000000001' and name = 'Quête' and type = 'income');
    v_cash  uuid := (select id from accounts where org_id = '14900000-0000-0000-0000-000000000001' and code = '1000');
    v_who   uuid;
    v text;
begin
    foreach v_who in array array[v_obs, v_appr, v_summ, v_rival] loop
        perform pg_temp.err149('no add for ' || v_who, pg_temp.add149(v_who, v_org, 'in', 'Kermesse'), 'ERR: % ne pouvez pas%');
        perform pg_temp.err149('no hide for ' || v_who, pg_temp.set149(v_who, v_org, 'in', v_quete, null, null, false), 'ERR: % ne pouvez pas%');
        perform pg_temp.err149('no rename for ' || v_who, pg_temp.set149(v_who, v_org, 'in', v_quete, 'Autre chose'), 'ERR: % ne pouvez pas%');
        perform pg_temp.err149('no order for ' || v_who,
            pg_temp.v149(v_who, format('select reorder_money_types(%L::uuid, ''in'', array[%L]::uuid[])::text', v_org, v_quete)),
            'ERR: % ne pouvez pas%');
    end loop;
    perform pg_temp.must149('nothing changed', (select is_active || '|' || label from accounts where id = v_quete), 'true|Quête du dimanche');
    perform pg_temp.err149('another owner, through their own business',
        pg_temp.set149(v_rival, '14900000-0000-0000-0000-000000000002', 'in', v_quete, null, null, false), 'ERR: % pas modifiable%');
    perform pg_temp.must149('money_types answers a stranger nothing',
        pg_temp.v149(v_rival, format('select count(*)::text from money_types(%L::uuid)', v_org)), '0');
    perform pg_temp.must149('a summary observer reads the chart',
        pg_temp.v149(v_summ, format('select (count(*) > 0)::text from money_types(%L::uuid)', v_org)), 'true');
    perform pg_temp.err149('anon executes money_types', pg_temp.v149(null, format('select count(*)::text from money_types(%L::uuid)', v_org)), 'ERR: 42501 %');
    perform pg_temp.err149('anon executes save_money_type', pg_temp.add149(null, v_org, 'in', 'Kermesse'), 'ERR: 42501 %');
    perform pg_temp.err149('anon executes reorder_money_types',
        pg_temp.v149(null, format('select reorder_money_types(%L::uuid, ''in'', array[]::uuid[])::text', v_org)), 'ERR: 42501 %');
    perform pg_temp.err149('an asset account is no type', pg_temp.set149(v_owner, v_org, 'in', v_cash, 'Caisse'), 'ERR: % pas modifiable%');
    perform pg_temp.err149('an income account is no expense type', pg_temp.set149(v_owner, v_org, 'out', v_quete, null, null, false), 'ERR: % pas modifiable%');
    perform pg_temp.err149('nobody writes on behalf of another',
        pg_temp.v149(v_owner, format('select save_money_type(%L::uuid, ''in'', null, ''Kermesse'', null, null, false, %L::uuid)::text', v_org, v_obs)),
        'ERR: % on behalf of another%');
    perform pg_temp.err149('an income type for a farm refused', pg_temp.add149(v_farm, '14900000-0000-0000-0000-000000000003', 'in', 'Location du tracteur'), 'ERR: %d''une association%');
    perform pg_temp.err149('an income type for a shop refused', pg_temp.add149(v_farm, '14900000-0000-0000-0000-000000000004', 'in', 'Location'), 'ERR: %d''une association%');
    v := pg_temp.add149(v_farm, '14900000-0000-0000-0000-000000000003', 'out', 'Réparation du forage', 'Pompe et tuyaux');
    if v like 'ERR:%' then raise exception 'FAIL: a farm could not add an expense type: %', v; end if;
    raise notice 'PASS: a farm adds an expense type';
    perform pg_temp.err149('a farm''s expense duplicate refused',
        pg_temp.add149(v_farm, '14900000-0000-0000-0000-000000000003', 'out', 'reparation du FORAGE'), 'ERR: MA149 %');

    update orgs set suspended_at = now() where id = v_org;
    perform pg_temp.err149('a suspended business writes nothing', pg_temp.add149(v_owner, v_org, 'in', 'Kermesse'), 'ERR: % ne pouvez pas%');
    update orgs set suspended_at = null where id = v_org;
end $$;

rollback;
\echo ''
\echo 'test_batch149: every claim held'
