-- ============================================================
-- test_org_plan.sql — the plan flag is the platform's to set, and lapsing is not a cliff (065).
-- Phone block 37.
--
-- The claims: only a platform admin sets a plan; a business born free reads
-- free; set to Pro with a date still ahead it reads pro — through
-- org_plan(), through my_orgs() for its owner, in platform_overview() and
-- behind the console's 'pro' filter; the day after plan_until it reads free
-- again and nothing else about it changed; a plan nobody knows is refused;
-- a date on a free plan is not kept; and the change is in the activity log
-- with the platform admin as actor, without any code written for it.
-- ============================================================
\set ON_ERROR_STOP on

\set plat  '''37373737-0000-0000-0000-000000000001'''
\set owner '''37373737-0000-0000-0000-000000000002'''
\set other '''37373737-0000-0000-0000-000000000003'''
\set org   '''37000000-0000-0000-0000-000000000001'''
\set org_b '''37000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:plat,  '+22637000001', '{"full_name": "Plateforme"}'),
    (:owner, '+22637000002', '{"full_name": "Patronne"}'),
    (:other, '+22637000003', '{"full_name": "Voisin"}');
update profiles set is_platform_admin = true where id = :plat;

insert into orgs (id, name, slug, profile, default_currency) values
    (:org,   'Boutique Plan', 'boutique-plan-37', 'retail', 'XOF'),
    (:org_b, 'Ferme Libre',   'ferme-libre-37',   'farm',   'XOF');
select seed_retail_accounts(:org);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:org,   :owner, 'owner', 'org', :org,   'full'),
    (:org_b, :other, 'owner', 'org', :org_b, 'full');


\echo ''
\echo '--- TEST 1: born free, and only the platform may change that ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '37373737-0000-0000-0000-000000000002';
do $$
declare v_plan text;
begin
    select plan into v_plan from my_orgs()
     where org_id = '37000000-0000-0000-0000-000000000001';
    if v_plan <> 'free' then
        raise exception 'FAIL: a new business reads % rather than free', v_plan;
    end if;
    if org_plan('37000000-0000-0000-0000-000000000001') <> 'free' then
        raise exception 'FAIL: org_plan() of a new business is not free';
    end if;
    if org_plan('00000000-0000-0000-0000-000000000000') <> 'free' then
        raise exception 'FAIL: org_plan() of a business that does not exist is not free';
    end if;
    begin
        perform set_org_plan('37000000-0000-0000-0000-000000000001', 'pro', null, 'moi-même');
        raise exception 'FAIL: an owner set their own plan';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: born free; the owner was refused — %', sqlerrm;
    end;
end $$;
rollback;

\echo ''
\echo '--- TEST 2: the platform sets Pro until a date ahead; everyone reads pro ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '37373737-0000-0000-0000-000000000001';
-- Other suites leave Pro businesses behind on a shared cluster, so the
-- count is measured as a difference, not an absolute.
create temp table before_plan as select pro from platform_overview();
select set_org_plan('37000000-0000-0000-0000-000000000001', 'pro',
                    current_date + 30, '  Wave 25 000 F  ');
do $$
declare v_pro int; v_before int; v_rows int; v_note text;
begin
    if org_plan('37000000-0000-0000-0000-000000000001') <> 'pro' then
        raise exception 'FAIL: org_plan() does not read pro after set_org_plan';
    end if;
    select pro into v_before from before_plan;
    select pro into v_pro from platform_overview();
    if v_pro <> v_before + 1 then
        raise exception 'FAIL: platform_overview went from % to % pro businesses, expected +1', v_before, v_pro;
    end if;
    if not exists (select 1 from search_orgs(null, null, 'active', 'pro', 'name', 200)
                    where name = 'Boutique Plan') then
        raise exception 'FAIL: the pro filter does not list the business';
    end if;
    if exists (select 1 from search_orgs(null, null, 'active', 'pro', 'name', 200)
                where name = 'Ferme Libre') then
        raise exception 'FAIL: the pro filter lists a free business';
    end if;
    select plan_note into v_note from orgs
     where id = '37000000-0000-0000-0000-000000000001';
    if v_note <> 'Wave 25 000 F' then
        raise exception 'FAIL: the note was not kept trimmed (got %)', quote_literal(v_note);
    end if;
end $$;
-- The owner, from their own list.
set local "request.jwt.claim.sub" = '37373737-0000-0000-0000-000000000002';
do $$
declare v_plan text;
begin
    select plan into v_plan from my_orgs()
     where org_id = '37000000-0000-0000-0000-000000000001';
    if v_plan <> 'pro' then
        raise exception 'FAIL: the owner''s my_orgs reads % rather than pro', v_plan;
    end if;
    raise notice 'PASS: pro through org_plan, my_orgs, the overview count and the pro filter';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: the day after plan_until it is free again, and nothing else moved ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '37373737-0000-0000-0000-000000000001';
create temp table before_lapse as select pro from platform_overview();
select set_org_plan('37000000-0000-0000-0000-000000000001', 'pro', current_date - 1, null);
do $$
declare v_pro int; v_before int; v_name text; v_susp timestamptz; v_arch timestamptz; v_raw text;
begin
    if org_plan('37000000-0000-0000-0000-000000000001') <> 'free' then
        raise exception 'FAIL: a lapsed pro still reads pro';
    end if;
    select pro into v_before from before_lapse;
    select pro into v_pro from platform_overview();
    if v_pro <> v_before then
        raise exception 'FAIL: a lapsed pro is still counted (% -> % pro)', v_before, v_pro;
    end if;
    if exists (select 1 from search_orgs(null, null, 'active', 'pro', 'name', 200)
                where name = 'Boutique Plan') then
        raise exception 'FAIL: the pro filter still lists a lapsed business';
    end if;
    -- Lapsing is not a cliff: the row is untouched but for the plan columns.
    select name, suspended_at, archived_at, plan
      into v_name, v_susp, v_arch, v_raw
      from orgs where id = '37000000-0000-0000-0000-000000000001';
    if v_name <> 'Boutique Plan' or v_susp is not null or v_arch is not null then
        raise exception 'FAIL: lapsing changed something other than the plan';
    end if;
    if v_raw <> 'pro' then
        raise exception 'FAIL: the raw plan column was rewritten on lapse (%)', v_raw;
    end if;
    -- Still today counts: paid until today is paid today.
    perform set_org_plan('37000000-0000-0000-0000-000000000001', 'pro', current_date, null);
    if org_plan('37000000-0000-0000-0000-000000000001') <> 'pro' then
        raise exception 'FAIL: paid until today does not read pro today';
    end if;
    raise notice 'PASS: yesterday''s date reads free and changes nothing else; today''s date still reads pro';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: unknown plans are refused; a date on a free plan is not kept ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '37373737-0000-0000-0000-000000000001';
do $$
declare v_until date;
begin
    begin
        perform set_org_plan('37000000-0000-0000-0000-000000000001', 'gold', null, null);
        raise exception 'FAIL: an unknown plan was accepted';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    begin
        perform set_org_plan('00000000-0000-0000-0000-000000000000', 'pro', null, null);
        raise exception 'FAIL: a plan was set on a business that does not exist';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
    end;
    perform set_org_plan('37000000-0000-0000-0000-000000000001', 'free', current_date + 30, 'remboursé');
    select plan_until into v_until from orgs
     where id = '37000000-0000-0000-0000-000000000001';
    if v_until is not null then
        raise exception 'FAIL: a free plan kept a paid-until date (%)', v_until;
    end if;
    raise notice 'PASS: gold refused, a ghost business refused, free keeps no date';
end $$;
rollback;

\echo ''
\echo '--- TEST 5: the change is in the activity log, signed by the platform ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '37373737-0000-0000-0000-000000000001';
select set_org_plan('37000000-0000-0000-0000-000000000001', 'pro', current_date + 365, 'partenaire');
do $$
declare v_rows int;
begin
    select count(*) into v_rows
      from audit_log
     where org_id = '37000000-0000-0000-0000-000000000001'
       and table_name = 'orgs'
       and action = 'update'
       and actor_id = '37373737-0000-0000-0000-000000000001'
       and changed ? 'plan'
       and changed ? 'plan_until';
    if v_rows <> 1 then
        raise exception 'FAIL: expected one audit row for the plan change, found %', v_rows;
    end if;
    raise notice 'PASS: the plan change is one audit row, by the platform admin, naming plan and plan_until';
end $$;
rollback;

\echo ''
\echo 'test_org_plan.sql: all tests passed'
