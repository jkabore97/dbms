-- ============================================================
-- test_batch123.sql — how many people have looked at a vitrine (123).
--
-- The claims, for a shop, a farm and an association alike:
--   * the same visitor twice the same day counts once; a new visitor
--     counts; the same visitor the next day adds a day's row but not to
--     the all-time count;
--   * a member of the business (its own preview) is not counted, and is
--     told the count;
--   * an id that is not 16–64 of [A-Za-z0-9-] is refused;
--   * a vitrine the street cannot open (switched off, under the minimum,
--     archived) is not counted and answers null; a vitrine d'exemple is
--     not counted;
--   * only a hash of the visitor id is kept, never the id;
--   * at most 5 000 new rows a vitrine a day; the next day counts again;
--   * rows older than 400 days are deleted now and then, the total kept;
--   * storefront() says 'visitors' in its style from the first visitor,
--     and nothing at 0;
--   * the doors: anon and authenticated may call record_vitrine_visit,
--     PUBLIC may not; neither reads nor writes the two tables.
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
-- Earlier suites hand the app's roles every table and function: 123 again,
-- so what follows is 123's own doors.
\i database/migrations/123_vitrine_views.sql

\set sowner '''12312312-0000-0000-0000-000000000001'''
\set fowner '''12312312-0000-0000-0000-000000000002'''
\set aowner '''12312312-0000-0000-0000-000000000003'''
\set awa    '''12312312-0000-0000-0000-000000000004'''
\set shop   '''12300000-0000-0000-0000-000000000001'''
\set farm   '''12300000-0000-0000-0000-000000000002'''
\set assoc  '''12300000-0000-0000-0000-000000000003'''
\set off    '''12300000-0000-0000-0000-000000000004'''
\set empty  '''12300000-0000-0000-0000-000000000005'''
\set gone   '''12300000-0000-0000-0000-000000000006'''
\set expo   '''12300000-0000-0000-0000-000000000007'''

insert into auth.users (id, phone, raw_user_meta_data) values
    (:sowner, '+22612301001', '{"full_name": "Patronne 123"}'),
    (:fowner, '+22612301002', '{"full_name": "Fermier 123"}'),
    (:aowner, '+22612301003', '{"full_name": "Trésorière 123"}'),
    (:awa,    '+22612301004', '{"full_name": "Awa Cliente 123"}');
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, archived_at, showcase) values
    (:shop,  'Boutique 123', 'boutique-123', 'retail',      'XOF', true,  null,  false),
    (:farm,  'Ferme 123',    'ferme-123',    'farm',        'XOF', true,  null,  false),
    (:assoc, 'Entraide 123', 'entraide-123', 'association', 'XOF', true,  null,  false),
    (:off,   'Fermée 123',   'fermee-123',   'retail',      'XOF', false, null,  false),
    (:empty, 'Vide 123',     'vide-123',     'retail',      'XOF', true,  null,  false),
    (:gone,  'Partie 123',   'partie-123',   'retail',      'XOF', true,  now(), false),
    (:expo,  'Exemple 123',  'exemple-123',  'retail',      'XOF', true,  null,  true);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :sowner, 'owner', 'org', :shop,  'full'),
    (:farm,  :fowner, 'owner', 'org', :farm,  'full'),
    (:assoc, :aowner, 'owner', 'org', :assoc, 'full'),
    (:empty, :sowner, 'owner', 'org', :empty, 'full');
-- Ten published articles each (over any minimum), none for « Vide ».
insert into products (org_id, name, sale_price, cost_price, quantity, is_published)
select o.id, 'Article 123 ' || g, 100 * g, 50 * g, 10, true
  from orgs o cross join generate_series(1, 10) g
 where o.id in (:shop, :farm, :assoc, :off, :gone, :expo);

create or replace function pg_temp.as123(p_who uuid)
returns void
language sql
as $$ select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true); $$;

-- One call through the street's door, as anon (p_who null) or as a
-- signed-in person.
create or replace function pg_temp.visit123(p_slug text, p_visitor text, p_who uuid default null)
returns bigint
language plpgsql
as $$
declare v bigint;
begin
    perform pg_temp.as123(p_who);
    if p_who is null then
        execute 'set local role anon';
    else
        execute 'set local role authenticated';
    end if;
    v := record_vitrine_visit(p_slug, p_visitor);
    execute 'reset role';
    perform pg_temp.as123(null);
    return v;
end;
$$;

create or replace function pg_temp.refused123(p_sql text, p_role text default null)
returns text
language plpgsql
as $$
begin
    if p_role is not null then
        execute format('set local role %I', p_role);
    end if;
    execute p_sql;
    execute 'reset role';
    return '(went through)';
exception when others then
    execute 'reset role';
    return sqlerrm;
end;
$$;

create or replace function pg_temp.rows123(p_org uuid)
returns bigint
language sql
as $$ select count(*) from vitrine_visits where org_id = p_org; $$;

\echo ''
\echo '--- TEST 1: once a day per visitor, a new visitor counts — shop, farm, association ---'
do $$
declare
    s   text;
    v   bigint;
    org uuid;
begin
    foreach s in array array['boutique-123', 'ferme-123', 'entraide-123'] loop
        org := (select id from orgs where slug = s);
        v := pg_temp.visit123(s, 'visitor-aaaa-0001');
        if v <> 1 then raise exception 'FAIL: % first visitor gave %', s, v; end if;
        v := pg_temp.visit123(s, 'visitor-aaaa-0001');
        if v <> 1 or pg_temp.rows123(org) <> 1 then
            raise exception 'FAIL: % the same visitor twice the same day gave % (% rows)', s, v, pg_temp.rows123(org);
        end if;
        -- Signed in, with the same random id: still the one visitor.
        v := pg_temp.visit123(s, 'visitor-aaaa-0001', '12312312-0000-0000-0000-000000000004');
        if v <> 1 then raise exception 'FAIL: % the signed-in same id counted again (%)', s, v; end if;
        v := pg_temp.visit123(s, 'visitor-bbbb-0002');
        if v <> 2 or pg_temp.rows123(org) <> 2 then
            raise exception 'FAIL: % a new visitor gave %', s, v;
        end if;
    end loop;
    raise notice 'PASS: shop, farm, association — the same visitor twice a day counts once (signed out or in), a new one counts: 2';
end $$;

\echo ''
\echo '--- TEST 2: the next day — a row for the day, the all-time count unchanged ---'
do $$
declare v bigint;
begin
    -- Yesterday, as far as the vitrine knows.
    update vitrine_visits  set day = day - 1 where org_id = '12300000-0000-0000-0000-000000000001';
    update org_view_counts set day = day - 1 where org_id = '12300000-0000-0000-0000-000000000001';
    v := pg_temp.visit123('boutique-123', 'visitor-aaaa-0001');
    if v <> 2 then raise exception 'FAIL: a visitor back the next day changed the count to %', v; end if;
    if pg_temp.rows123('12300000-0000-0000-0000-000000000001') <> 3 then
        raise exception 'FAIL: the next day''s visit wrote no row of its own';
    end if;
    if (select day_new from org_view_counts where org_id = '12300000-0000-0000-0000-000000000001') <> 1 then
        raise exception 'FAIL: the day''s new rows did not start again at 1';
    end if;
    raise notice 'PASS: back the next day — one more row for the day, still 2 unique visitors; the day''s rows counted afresh';
end $$;

\echo ''
\echo '--- TEST 3: the business''s own people are not counted, and see the count ---'
do $$
declare v bigint;
begin
    v := pg_temp.visit123('boutique-123', 'owner-device-0000001', '12312312-0000-0000-0000-000000000001');
    if v <> 2 or pg_temp.rows123('12300000-0000-0000-0000-000000000001') <> 3 then
        raise exception 'FAIL: the owner''s visit counted, or the owner was told %', v;
    end if;
    v := pg_temp.visit123('ferme-123', 'owner-device-0000002', '12312312-0000-0000-0000-000000000002');
    if v <> 2 then raise exception 'FAIL: the farmer''s visit gave %', v; end if;
    v := pg_temp.visit123('entraide-123', 'owner-device-0000003', '12312312-0000-0000-0000-000000000003');
    if v <> 2 then raise exception 'FAIL: the treasurer''s visit gave %', v; end if;
    -- Under the minimum the owner still opens it (098) — and is not counted.
    v := pg_temp.visit123('vide-123', 'owner-device-0000001', '12312312-0000-0000-0000-000000000001');
    if v <> 0 or pg_temp.rows123('12300000-0000-0000-0000-000000000005') <> 0 then
        raise exception 'FAIL: the owner of a vitrine under the minimum was counted (%)', v;
    end if;
    raise notice 'PASS: owner, farmer and treasurer see 2 and add nothing; an owner previewing a vitrine under the minimum sees 0';
end $$;

\echo ''
\echo '--- TEST 4: a bad visitor id is refused ---'
do $$
declare
    b text;
    r text;
begin
    foreach b in array array['short-id', 'x', '', 'has a space in it 1234',
                             'accent-é-0000000000', 'semi;colon;0000000000',
                             repeat('a', 65)] loop
        r := pg_temp.refused123(format('select record_vitrine_visit(%L, %L)', 'boutique-123', b));
        if r <> 'Identifiant de visiteur invalide' then
            raise exception 'FAIL: the id « % » gave « % »', b, r;
        end if;
    end loop;
    r := pg_temp.refused123('select record_vitrine_visit(''boutique-123'', null)');
    if r <> 'Identifiant de visiteur invalide' then
        raise exception 'FAIL: a null id gave « % »', r;
    end if;
    if pg_temp.visit123('boutique-123', repeat('Z', 64)) <> 3
       or pg_temp.visit123('boutique-123', 'ABCDEFGHIJKLMNOP') <> 4 then
        raise exception 'FAIL: 64 and 16 characters were not taken';
    end if;
    raise notice 'PASS: too short, too long, a space, an accent, a semicolon and null refused in French; 16 and 64 taken (4 visitors)';
end $$;

\echo ''
\echo '--- TEST 5: a vitrine the street cannot open, or a vitrine d''exemple, is not counted ---'
do $$
declare v bigint;
begin
    if pg_temp.visit123('fermee-123', 'visitor-aaaa-0001') is not null
       or pg_temp.visit123('vide-123', 'visitor-aaaa-0001') is not null
       or pg_temp.visit123('partie-123', 'visitor-aaaa-0001') is not null
       or pg_temp.visit123('nulle-part-123', 'visitor-aaaa-0001') is not null then
        raise exception 'FAIL: a closed, empty, archived or unknown vitrine answered a count';
    end if;
    v := pg_temp.visit123('exemple-123', 'visitor-aaaa-0001');
    if v <> 0 then raise exception 'FAIL: a vitrine d''exemple counted (%)', v; end if;
    if exists (select 1 from vitrine_visits where org_id in (
                 '12300000-0000-0000-0000-000000000004', '12300000-0000-0000-0000-000000000005',
                 '12300000-0000-0000-0000-000000000006', '12300000-0000-0000-0000-000000000007'))
       or exists (select 1 from org_view_counts where visitors > 0 and org_id in (
                 '12300000-0000-0000-0000-000000000004', '12300000-0000-0000-0000-000000000005',
                 '12300000-0000-0000-0000-000000000006', '12300000-0000-0000-0000-000000000007')) then
        raise exception 'FAIL: a row was written for a vitrine the street does not count';
    end if;
    raise notice 'PASS: switched off, under the minimum, archived, unknown — null, nothing written; a vitrine d''exemple — 0, nothing counted';
end $$;

\echo ''
\echo '--- TEST 6: only a hash is kept, one per vitrine ---'
do $$
begin
    if exists (select 1 from vitrine_visits
                where position(convert_to('visitor-aaaa-0001', 'UTF8') in visitor_hash) > 0
                   or length(visitor_hash) <> 32) then
        raise exception 'FAIL: a raw id is kept, or a hash is not sha256';
    end if;
    if (select count(distinct visitor_hash) from vitrine_visits
         where visitor_hash in (
             sha256(convert_to('12300000-0000-0000-0000-000000000001:visitor-aaaa-0001', 'UTF8')),
             sha256(convert_to('12300000-0000-0000-0000-000000000002:visitor-aaaa-0001', 'UTF8')),
             sha256(convert_to('12300000-0000-0000-0000-000000000003:visitor-aaaa-0001', 'UTF8')))) <> 3 then
        raise exception 'FAIL: the same device is not a different hash at each vitrine';
    end if;
    raise notice 'PASS: sha256 of org id and visitor id, 32 bytes, never the id; the same device a different hash at each vitrine';
end $$;

\echo ''
\echo '--- TEST 7: 5 000 new rows a day at most; the next day counts again ---'
do $$
declare v bigint;
begin
    update org_view_counts set day_new = 5000 where org_id = '12300000-0000-0000-0000-000000000002';
    v := pg_temp.visit123('ferme-123', 'visitor-cccc-0003');
    if v <> 2 or pg_temp.rows123('12300000-0000-0000-0000-000000000002') <> 2 then
        raise exception 'FAIL: past 5 000 a day a new visitor still counted (%)', v;
    end if;
    update org_view_counts set day = day - 1 where org_id = '12300000-0000-0000-0000-000000000002';
    v := pg_temp.visit123('ferme-123', 'visitor-cccc-0003');
    if v <> 3 then raise exception 'FAIL: the next day the visitor was not counted (%)', v; end if;
    raise notice 'PASS: at 5 000 new rows the day writes nothing more (the count still answered); the next day counts again: 3';
end $$;

\echo ''
\echo '--- TEST 8: rows older than 400 days go now and then, the total stays ---'
do $$
declare
    i int := 0;
    v bigint;
begin
    insert into vitrine_visits (org_id, visitor_hash, day) values
        ('12300000-0000-0000-0000-000000000003', sha256('old-401'::bytea), current_date - 401),
        ('12300000-0000-0000-0000-000000000003', sha256('old-399'::bytea), current_date - 399);
    -- About one call in a hundred: 3 000 calls miss it with odds of 1e-13.
    while exists (select 1 from vitrine_visits where visitor_hash = sha256('old-401'::bytea)) and i < 3000 loop
        v := pg_temp.visit123('entraide-123', 'visitor-aaaa-0001');
        i := i + 1;
    end loop;
    if exists (select 1 from vitrine_visits where visitor_hash = sha256('old-401'::bytea)) then
        raise exception 'FAIL: a 401-day-old row survived % calls', i;
    end if;
    if not exists (select 1 from vitrine_visits where visitor_hash = sha256('old-399'::bytea)) then
        raise exception 'FAIL: a 399-day-old row was deleted';
    end if;
    if v <> 2 then raise exception 'FAIL: the total changed with the retention (%)', v; end if;
    delete from vitrine_visits where visitor_hash = sha256('old-399'::bytea);
    raise notice 'PASS: a 401-day-old row deleted after % calls, a 399-day-old one kept, the total still 2', i;
end $$;

\echo ''
\echo '--- TEST 9: storefront() says the visitors from the first one, nothing at 0 ---'
do $$
declare st jsonb;
begin
    perform pg_temp.as123(null);
    set local role anon;
    if (select (style ->> 'visitors')::bigint from storefront('boutique-123')) <> 4
       or (select (style ->> 'visitors')::bigint from storefront('ferme-123')) <> 3
       or (select (style ->> 'visitors')::bigint from storefront('entraide-123')) <> 2 then
        reset role;
        raise exception 'FAIL: storefront() does not say 4 / 3 / 2 visitors';
    end if;
    reset role;
    -- No visitor yet: no key at all (P1's same answer).
    update orgs set storefront_enabled = true where id = '12300000-0000-0000-0000-000000000004';
    select style into st from storefront('fermee-123');
    if st ? 'visitors' then
        raise exception 'FAIL: a vitrine never visited says visitors: %', st -> 'visitors';
    end if;
    update orgs set storefront_enabled = false where id = '12300000-0000-0000-0000-000000000004';
    raise notice 'PASS: the street reads 4 (shop), 3 (farm), 2 (association) in storefront().style; a vitrine never visited has no such key';
end $$;

\echo ''
\echo '--- TEST 10: the doors ---'
do $$
declare
    v_bad  text;
    v_r    text;
    v_role text;
begin
    select string_agg(f || ' ' || r, ', ') into v_bad
      from (values
              ('record_vitrine_visit(text,text)', 'anon', true),
              ('record_vitrine_visit(text,text)', 'authenticated', true),
              ('storefront(text)', 'anon', true),
              ('storefront(text)', 'authenticated', true)) t(f, r, ok)
     where has_function_privilege(r, f, 'execute') <> ok;
    if v_bad is not null then
        raise exception 'FAIL: the doors are wrong for %', v_bad;
    end if;
    if has_function_privilege('public', 'record_vitrine_visit(text,text)', 'execute') then
        raise exception 'FAIL: PUBLIC may call record_vitrine_visit';
    end if;
    if (select prosecdef from pg_proc where proname = 'record_vitrine_visit') is not true
       or not exists (select 1 from pg_proc where proname = 'record_vitrine_visit'
                         and proconfig::text like '%search_path=public%') then
        raise exception 'FAIL: record_vitrine_visit is not a definer with its search path';
    end if;
    foreach v_role in array array['anon', 'authenticated'] loop
        if has_table_privilege(v_role, 'vitrine_visits', 'select')
           or has_table_privilege(v_role, 'vitrine_visits', 'insert')
           or has_table_privilege(v_role, 'org_view_counts', 'select')
           or has_table_privilege(v_role, 'org_view_counts', 'update') then
            raise exception 'FAIL: % has a right on the visit tables', v_role;
        end if;
    end loop;
    v_r := pg_temp.refused123('select count(*) from vitrine_visits', 'anon');
    if v_r not like 'permission denied%' then
        raise exception 'FAIL: anon reading vitrine_visits gave « % »', v_r;
    end if;
    v_r := pg_temp.refused123('select count(*) from org_view_counts', 'anon');
    if v_r not like 'permission denied%' then
        raise exception 'FAIL: anon reading org_view_counts gave « % »', v_r;
    end if;
    v_r := pg_temp.refused123('select count(*) from vitrine_visits', 'authenticated');
    if v_r not like 'permission denied%' then
        raise exception 'FAIL: a signed-in person reading vitrine_visits gave « % »', v_r;
    end if;
    if not (select relrowsecurity from pg_class where relname = 'vitrine_visits')
       or not (select relrowsecurity from pg_class where relname = 'org_view_counts') then
        raise exception 'FAIL: RLS is off on a visit table';
    end if;
    raise notice 'PASS: record_vitrine_visit and storefront the street''s and the signed-in''s, not PUBLIC''s; a definer with its search path; the two tables closed to anon and authenticated, RLS on';
end $$;

\echo '=== test_batch123.sql: all claims hold ==='
