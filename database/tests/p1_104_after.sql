-- ============================================================
-- p1_104_after.sql — the second half of promise P1 (batch 104).
--
-- Run on the database p1_104_before.sql photographed at 103, once 104 and
-- every later migration are applied. The same photograph, taken again by
-- the same function, must be the same answer for answer: every member's
-- access to every tool, every business's feature_states (the new 'hidden'
-- aside, which must be empty), and everything the street is shown. And
-- with no rule written, nothing in the catalog is hidden for any business
-- of any kind.
-- ============================================================
\set ON_ERROR_STOP on

do $$
declare
    n       int;
    v_diff  text;
    v_count int;
begin
    n := p1_take('after');
    select string_agg(coalesce(b.what, a.what), '; ' order by coalesce(b.what, a.what)), count(*)
      into v_diff, v_count
      from (select * from p1_snap where phase = 'before') b
      full join (select * from p1_snap where phase = 'after') a on a.what = b.what
     where a.v is distinct from b.v;
    if v_diff is not null then
        raise exception 'FAIL: % answers changed with 104 and after: %', v_count, v_diff;
    end if;
    raise notice 'PASS: P1 — % answers identical before and after 104–107 (access, feature_states, every vitrine and the street)', n;
end $$;

do $$
declare
    r record;
    v jsonb;
begin
    for r in select mb.user_id, mb.org_id from memberships mb
              where mb.org_id::text like '11040000-%' loop
        perform set_config('request.jwt.claim.sub', r.user_id::text, true);
        execute 'set local role authenticated';
        v := feature_states(r.org_id)->'hidden';
        execute 'reset role';
        if v is distinct from '[]'::jsonb then
            raise exception 'FAIL: % is told % is hidden with no rule', r.org_id, v;
        end if;
    end loop;
    if exists (select 1 from orgs o cross join feature_catalog c where feature_hidden(o.id, c.key)) then
        raise exception 'FAIL: a catalog feature is hidden with no rule';
    end if;
    if exists (select 1 from feature_rules) then
        raise exception 'FAIL: installing wrote a switch';
    end if;
    raise notice 'PASS: P1 — every switch starts at « Par défaut »: % businesses × % catalog features, none hidden',
        (select count(*) from orgs), (select count(*) from feature_catalog);
end $$;

\echo '=== p1_104_after.sql: P1 holds ==='
