-- ============================================================
-- test_farm_edits.sql — correcting a farm entry (033).
--
-- Phone block 98. A notebook lets you cross out a wrong number; these prove
-- the app now does too, for the three farm entries that carry no ledger:
-- flock events, herd events, harvests. And that an observer — who cannot
-- record — cannot correct either, and that a harvest cannot be corrected to
-- nothing.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''98989898-0000-0000-0000-000000000001'''
\set observer '''98989898-0000-0000-0000-000000000002'''
\set org      '''98000000-0000-0000-0000-000000000001'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22698000001', '{"full_name": "Fermier"}'),
    (:observer, '+22698000002', '{"full_name": "Témoin"}');

insert into orgs (id, name, slug, profile, default_currency) values
    (:org, 'Ferme 98', 'ferme-98', 'farm', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:org, :owner,    'owner',    'org', :org),
    (:org, :observer, 'observer', 'org', :org);


\echo ''
\echo '--- TEST 1: the owner corrects each of the three entry kinds ---'
begin;
set local "request.jwt.claim.sub" = '98989898-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_org   uuid := '98000000-0000-0000-0000-000000000001';
    v_flock uuid; v_fe uuid; v_herd uuid; v_he uuid; v_cycle uuid; v_h uuid;
    v_q numeric; v_kind text; v_grade text;
begin
    -- Fixtures, through the real record path.
    v_flock := open_flock(v_org, 'B-2026-98', 100);
    v_fe    := record_flock_event(v_flock, 'mortality', 70);  -- a fat-fingered 70
    v_herd  := open_herd(v_org, 'goat', 'Troupeau A', 20);
    v_he    := record_herd_event(v_org, v_herd, 'mortality', 3);
    v_cycle := open_crop_cycle(v_org, 'Tomate');
    v_h     := record_harvest(v_org, v_cycle, 50);

    -- Correct the mortality 70 -> 7.
    perform update_flock_event(v_fe, p_quantity => 7);
    select quantity into v_q from flock_events where id = v_fe;
    if v_q <> 7 then raise exception 'FAIL: flock event not corrected (got %)', v_q; end if;

    -- Correct a herd event's count and kind.
    perform update_herd_event(v_he, p_quantity => 2, p_kind => 'sold');
    select quantity, kind into v_q, v_kind from herd_events where id = v_he;
    if v_q <> 2 or v_kind <> 'sold' then
        raise exception 'FAIL: herd event not corrected (% %)', v_q, v_kind;
    end if;

    -- Correct a harvest's quantity and grade.
    perform update_harvest(v_h, p_quantity => 120, p_grade => 'second');
    select quantity, grade into v_q, v_grade from harvests where id = v_h;
    if v_q <> 120 or v_grade <> 'second' then
        raise exception 'FAIL: harvest not corrected (% %)', v_q, v_grade;
    end if;

    raise notice 'PASS: all three entry kinds correct in place';
end $$;
rollback;


\echo ''
\echo '--- TEST 2: an observer cannot correct what it cannot record ---'
begin;
-- Build the event as the owner first (separate txn state via the same session).
set local "request.jwt.claim.sub" = '98989898-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_org uuid := '98000000-0000-0000-0000-000000000001'; v_flock uuid; v_fe uuid;
begin
    v_flock := open_flock(v_org, 'B-OBS-98', 50);
    v_fe := record_flock_event(v_flock, 'mortality', 4);
    -- Stash the id for the next block via a temp setting.
    perform set_config('test.fe_id', v_fe::text, true);
end $$;

set local "request.jwt.claim.sub" = '98989898-0000-0000-0000-000000000002';
do $$
declare v_fe uuid := current_setting('test.fe_id')::uuid;
begin
    perform update_flock_event(v_fe, p_quantity => 999);
    raise exception 'FAIL: an observer corrected a flock event';
exception
    when others then
        if sqlerrm like '%cannot correct%' then
            raise notice 'PASS: observer refused — %', sqlerrm;
        else raise; end if;
end $$;
rollback;


\echo ''
\echo '--- TEST 3: a harvest cannot be corrected to nothing ---'
begin;
set local "request.jwt.claim.sub" = '98989898-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_org uuid := '98000000-0000-0000-0000-000000000001'; v_cycle uuid; v_h uuid;
begin
    v_cycle := open_crop_cycle(v_org, 'Oignon');
    v_h := record_harvest(v_org, v_cycle, 30);
    begin
        perform update_harvest(v_h, p_quantity => 0);
        raise exception 'FAIL: a harvest was corrected to zero';
    exception
        when others then
            if sqlerrm like '%How much was harvested%' then
                raise notice 'PASS: zero harvest refused — %', sqlerrm;
            else raise; end if;
    end;
end $$;
rollback;

\echo ''
\echo '=== test_farm_edits.sql: all checks passed ==='
