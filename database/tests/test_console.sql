-- ============================================================
-- test_console.sql — a platform console at scale.
--
-- Runs as `authenticated` throughout. Both console functions are SECURITY
-- DEFINER because they read across every tenant on purpose, which means their
-- own platform-admin check is the only thing standing between an ordinary
-- shopkeeper and a list of every business on the platform. That check is what
-- most of this suite is about.
--
-- What this suite is about:
--
--   1. An ordinary member cannot list, search or count the platform. This is
--      the whole security surface of 021.
--   2. Paging returns each business once and only once. An off-by-one in the
--      offset means the console silently hides businesses, which is worse
--      than an error because nobody looks for what they cannot see.
--   3. `total_count` is the count of the *filter*, not of the page — the
--      pager is built on it.
--   4. `last_activity_at` follows real activity, and a backdated entry does
--      not drag it backwards and make a live business look abandoned.
--   5. The overview's health figures mean what they say: silent-30 excludes
--      a business that has never been active at all, because those two need
--      different people to fix them.
--
-- Phone block 86. The others: 70 rls, 71 invitations, 72 reports,
-- 73 accounting, 74 audit, 75/76 farm, 77 platform admin, 78 retail,
-- 79 employees, 80 capture, 81 org lifecycle, 82 delivery, 83 onboarding,
-- 84 farm_general, 85 invoicing.
-- ============================================================
\set ON_ERROR_STOP on

\set boss     '''86868686-0000-0000-0000-000000000001'''
\set trader   '''86868686-0000-0000-0000-000000000002'''

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:boss,   '+22686000001', '{"full_name": "Plateforme"}'),
    (:trader, '+22686000002', '{"full_name": "Commerçant"}');

update profiles set is_platform_admin = true where id = :boss;

-- Sixty businesses, so paging is exercised against more than one page.
do $$
declare i int;
begin
    for i in 1..60 loop
        insert into orgs (id, name, slug, profile, default_currency)
        values (
            ('86000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
            'Boutique ' || lpad(i::text, 3, '0'),
            'boutique-86-' || i,
            case when i % 3 = 0 then 'farm'
                 when i % 3 = 1 then 'retail'
                 else 'church' end,
            'XOF'
        );
    end loop;
end $$;

-- The trader belongs to exactly one of them and is a platform admin of none.
insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    ('86000000-0000-0000-0000-000000000001', :trader, 'owner', 'org',
     '86000000-0000-0000-0000-000000000001');

\echo ''
\echo '--- TEST 1: an ordinary member cannot see the platform ---'
begin;
set local "request.jwt.claim.sub" = '86868686-0000-0000-0000-000000000002';
set local role authenticated;
do $$
begin
    begin
        perform * from platform_overview();
        raise exception 'FAIL: a shopkeeper read the platform overview';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: refused — %', sqlerrm;
    end;

    begin
        perform * from search_orgs();
        raise exception 'FAIL: a shopkeeper searched every business';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
commit;

\echo ''
\echo '--- TEST 2: paging returns every business exactly once ---'
begin;
set local "request.jwt.claim.sub" = '86868686-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_page   int := 0;
    v_seen   uuid[] := '{}';
    v_rows   int;
    v_total  int;
begin
    -- Walk the whole list in pages of 25 and collect what comes back.
    loop
        select count(*), coalesce(max(s.total_count), 0)
          into v_rows, v_total
          from search_orgs(p_query => 'boutique-86-', p_status => 'all',
                           p_limit => 25, p_offset => v_page * 25) s;

        v_seen := v_seen || array(
            select s.org_id from search_orgs(p_query => 'boutique-86-',
                p_status => 'all', p_limit => 25, p_offset => v_page * 25) s);
        exit when v_rows = 0;
        v_page := v_page + 1;
        exit when v_page > 10;   -- guard against a paging bug looping forever
    end loop;

    if array_length(v_seen, 1) <> 60 then
        raise exception 'FAIL: paging returned % businesses, expected 60',
            array_length(v_seen, 1);
    end if;

    -- Once each. A duplicate means the ordering is unstable across pages,
    -- which also means something else is being skipped.
    if (select count(distinct x) from unnest(v_seen) x) <> 60 then
        raise exception 'FAIL: paging returned duplicates';
    end if;

    raise notice 'PASS: 60 businesses across % pages, no duplicates, no gaps',
        v_page;
end $$;
commit;

\echo ''
\echo '--- TEST 3: total_count counts the filter, not the page ---'
begin;
set local "request.jwt.claim.sub" = '86868686-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_rows  int;
    v_total int;
begin
    select count(*), max(s.total_count) into v_rows, v_total
      from search_orgs(p_query => 'boutique-86-', p_status => 'all',
                       p_limit => 10) s;

    if v_rows <> 10 then
        raise exception 'FAIL: asked for 10 rows, got %', v_rows;
    end if;
    -- The pager is built on this: 10 rows on screen, 60 in the result set.
    if v_total <> 60 then
        raise exception 'FAIL: total_count said % rather than 60', v_total;
    end if;

    raise notice 'PASS: 10 rows on the page, total_count says 60';
end $$;
commit;

\echo ''
\echo '--- TEST 4: search finds by name and by slug, in any case ---'
begin;
set local "request.jwt.claim.sub" = '86868686-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_n int;
begin
    select count(*) into v_n
      from search_orgs(p_query => 'BOUTIQUE 007', p_status => 'all') s;
    if v_n <> 1 then
        raise exception 'FAIL: an upper-case name search found % rows', v_n;
    end if;

    select count(*) into v_n
      from search_orgs(p_query => 'boutique-86-42', p_status => 'all') s;
    if v_n <> 1 then
        raise exception 'FAIL: a slug search found % rows', v_n;
    end if;

    select count(*) into v_n
      from search_orgs(p_query => 'zzz-nothing', p_status => 'all') s;
    if v_n <> 0 then
        raise exception 'FAIL: a nonsense search found % rows', v_n;
    end if;

    raise notice 'PASS: name, slug, and a miss';
end $$;
commit;

\echo ''
\echo '--- TEST 5: filters narrow, and combine ---'
begin;
set local "request.jwt.claim.sub" = '86868686-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_total int;
begin
    select max(s.total_count) into v_total
      from search_orgs(p_query => 'boutique-86-', p_profile => 'farm',
                       p_status => 'all', p_limit => 200) s;
    if v_total <> 20 then
        raise exception 'FAIL: % farms, expected 20', v_total;
    end if;

    -- Archive one and prove the default status hides it.
    update orgs set archived_at = now()
     where id = '86000000-0000-0000-0000-000000000003';

    select max(s.total_count) into v_total
      from search_orgs(p_query => 'boutique-86-', p_profile => 'farm',
                       p_status => 'active', p_limit => 200) s;
    if v_total <> 19 then
        raise exception 'FAIL: % active farms after archiving one, expected 19',
            v_total;
    end if;

    select max(s.total_count) into v_total
      from search_orgs(p_query => 'boutique-86-', p_status => 'archived',
                       p_limit => 200) s;
    if v_total <> 1 then
        raise exception 'FAIL: % archived, expected 1', v_total;
    end if;

    raise notice 'PASS: profile and status narrow, and combine';
end $$;
commit;

\echo ''
\echo '--- TEST 6: activity follows the ledger, and never goes backwards ---'
-- Deliberately NOT as `authenticated`: RLS on journal_entries refuses a
-- platform admin who is not a member of the business, which is correct and is
-- proven by test_platform_admin.sql. What is under test here is the trigger,
-- so the rows go in as the owner of the schema.
begin;
do $$
declare
    v_org   uuid := '86000000-0000-0000-0000-000000000005';
    v_first timestamptz;
    v_after timestamptz;
begin
    if (select last_activity_at from orgs where id = v_org) is not null then
        raise exception 'FAIL: a business with no entries has an activity date';
    end if;

    insert into journal_entries (org_id, memo, created_by)
    values (v_org, 'Première écriture', '86868686-0000-0000-0000-000000000001');

    select last_activity_at into v_first from orgs where id = v_org;
    if v_first is null then
        raise exception 'FAIL: the trigger did not record any activity';
    end if;

    -- A backdated correction. It must not make a live business look
    -- abandoned, which is what a naive "set to the new row's date" would do.
    insert into journal_entries (org_id, memo, created_by, created_at)
    values (v_org, 'Régularisation ancienne',
            '86868686-0000-0000-0000-000000000001', now() - interval '90 days');

    select last_activity_at into v_after from orgs where id = v_org;
    if v_after < v_first then
        raise exception 'FAIL: a backdated entry dragged activity from % to %',
            v_first, v_after;
    end if;

    raise notice 'PASS: activity recorded, and a backdated entry did not move it back';
end $$;
commit;

\echo ''
\echo '--- TEST 7: the overview separates "went quiet" from "never started" ---'
begin;
set local "request.jwt.claim.sub" = '86868686-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_row record;
    v_org uuid := '86000000-0000-0000-0000-000000000007';
begin
    -- A business that was alive and has gone quiet.
    update orgs set last_activity_at = now() - interval '45 days' where id = v_org;

    select * into v_row from platform_overview();

    -- The suites share a database, so the overview legitimately counts other
    -- suites' businesses too. Asserted as "at least ours" plus the invariant
    -- that the parts sum to the whole.
    if v_row.total < 60 then
        raise exception 'FAIL: overview counted % businesses, expected >= 60',
            v_row.total;
    end if;
    if v_row.archived < 1 then
        raise exception 'FAIL: % archived, expected at least ours', v_row.archived;
    end if;
    if v_row.active + v_row.archived <> v_row.total then
        raise exception 'FAIL: active + archived (% + %) <> total %',
            v_row.active, v_row.archived, v_row.total;
    end if;
    if v_row.farms + v_row.shops + v_row.churches + v_row.other_profiles
       <> v_row.total then
        raise exception 'FAIL: the profile counts do not sum to the total';
    end if;
    if v_row.silent_30d < 1 then
        raise exception 'FAIL: a business quiet for 45 days was not counted';
    end if;

    -- The distinction that matters operationally: a business that never
    -- recorded anything is a failed onboarding, not a churn risk, and the
    -- person who fixes it is different.
    if v_row.never_active < 50 then
        raise exception 'FAIL: only % never-active, expected most of them',
            v_row.never_active;
    end if;

    raise notice 'PASS: % total, % silent 30d, % never active',
        v_row.total, v_row.silent_30d, v_row.never_active;
end $$;
commit;

\echo ''
\echo '--- TEST 8: a page is bounded however much is asked for ---'
begin;
set local "request.jwt.claim.sub" = '86868686-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_rows int;
begin
    -- The console must not be able to ask for the whole platform in one
    -- request, whatever a modified client sends.
    select count(*) into v_rows
      from search_orgs(p_query => 'boutique-86-', p_status => 'all',
                       p_limit => 100000) s;
    if v_rows > 200 then
        raise exception 'FAIL: a page of % rows was allowed', v_rows;
    end if;

    select count(*) into v_rows
      from search_orgs(p_query => 'boutique-86-', p_status => 'all',
                       p_limit => -5) s;
    if v_rows < 1 then
        raise exception 'FAIL: a negative limit returned nothing';
    end if;

    raise notice 'PASS: the page size is clamped at both ends';
end $$;
commit;

\echo ''
\echo '========================================'
\echo ' test_console.sql: all assertions passed'
\echo '========================================'
