-- ============================================================
-- test_tontines.sql — the rotating savings group.
--
-- Phone block 90. The claims that matter: the turn rotates correctly and
-- wraps; a member cannot pay the same round twice; a round cannot close
-- while somebody has not paid; and the neighbour's business sees nothing.
-- ============================================================
\set ON_ERROR_STOP on

\set owner    '''90909090-0000-0000-0000-000000000001'''
\set stranger '''90909090-0000-0000-0000-000000000002'''
\set shop     '''90000000-0000-0000-0000-000000000001'''
\set other    '''90000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner,    '+22690000001', '{"full_name": "Organisatrice"}'),
    (:stranger, '+22690000002', '{"full_name": "Voisin"}');

insert into orgs (id, name, slug, profile, default_currency) values
    (:shop,  'Boutique 90',  'boutique-90',  'retail', 'XOF'),
    (:other, 'Boutique 90b', 'boutique-90b', 'retail', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:shop,  :owner,    'owner', 'org', :shop),
    (:other, :stranger, 'owner', 'org', :other);

\echo ''
\echo '--- TEST 1: a three-member tontine knows whose turn it is ---'
begin;
set local "request.jwt.claim.sub" = '90909090-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_t uuid; v_taker text;
begin
    insert into tontines (id, org_id, name, amount, period, created_by)
    values ('90a00000-0000-0000-0000-000000000001',
            '90000000-0000-0000-0000-000000000001',
            'Tontine du marché', 5000, 'weekly',
            '90909090-0000-0000-0000-000000000001')
    returning id into v_t;

    insert into tontine_members (tontine_id, org_id, name, position) values
        (v_t, '90000000-0000-0000-0000-000000000001', 'Awa',    1),
        (v_t, '90000000-0000-0000-0000-000000000001', 'Moussa', 2),
        (v_t, '90000000-0000-0000-0000-000000000001', 'Fatou',  3);

    select member_name into v_taker
      from tontine_round_status(v_t) where is_taker;
    if v_taker is distinct from 'Awa' then
        raise exception 'FAIL: round 1 taker is %, expected Awa', v_taker;
    end if;
    raise notice 'PASS: round 1, the pot is Awa''s';
end $$;
commit;

\echo ''
\echo '--- TEST 2: the same member cannot pay a round twice ---'
begin;
set local "request.jwt.claim.sub" = '90909090-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_m uuid;
begin
    select id into v_m from tontine_members
     where tontine_id = '90a00000-0000-0000-0000-000000000001' and position = 1;

    insert into tontine_contributions
        (tontine_id, member_id, org_id, round, amount, created_by)
    values ('90a00000-0000-0000-0000-000000000001', v_m,
            '90000000-0000-0000-0000-000000000001', 1, 5000,
            '90909090-0000-0000-0000-000000000001');

    begin
        insert into tontine_contributions
            (tontine_id, member_id, org_id, round, amount, created_by)
        values ('90a00000-0000-0000-0000-000000000001', v_m,
                '90000000-0000-0000-0000-000000000001', 1, 5000,
                '90909090-0000-0000-0000-000000000001');
        raise exception 'FAIL: a double payment was accepted';
    exception when unique_violation then
        raise notice 'PASS: the second payment of round 1 was refused';
    end;
end $$;
commit;

\echo ''
\echo '--- TEST 3: a round cannot close while somebody has not paid ---'
begin;
set local "request.jwt.claim.sub" = '90909090-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_round int;
begin
    begin
        perform advance_tontine_round('90a00000-0000-0000-0000-000000000001');
        raise exception 'FAIL: the round closed with two members unpaid';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: refused — %', sqlerrm;
    end;

    insert into tontine_contributions (tontine_id, member_id, org_id, round, amount, created_by)
    select tontine_id, id, org_id, 1, 5000, '90909090-0000-0000-0000-000000000001'
      from tontine_members
     where tontine_id = '90a00000-0000-0000-0000-000000000001' and position > 1;

    v_round := advance_tontine_round('90a00000-0000-0000-0000-000000000001');
    if v_round <> 2 then
        raise exception 'FAIL: advanced to %, expected 2', v_round;
    end if;
    raise notice 'PASS: everyone paid, round is now 2';
end $$;
commit;

\echo ''
\echo '--- TEST 4: the turn rotates and wraps past the last member ---'
begin;
set local "request.jwt.claim.sub" = '90909090-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_taker text;
begin
    select member_name into v_taker
      from tontine_round_status('90a00000-0000-0000-0000-000000000001')
     where is_taker;
    if v_taker is distinct from 'Moussa' then
        raise exception 'FAIL: round 2 taker is %, expected Moussa', v_taker;
    end if;

    -- Jump to round 4: with three members, 4 wraps back to position 1.
    update tontines set current_round = 4
     where id = '90a00000-0000-0000-0000-000000000001';
    select member_name into v_taker
      from tontine_round_status('90a00000-0000-0000-0000-000000000001')
     where is_taker;
    if v_taker is distinct from 'Awa' then
        raise exception 'FAIL: round 4 taker is %, expected Awa again', v_taker;
    end if;
    raise notice 'PASS: round 2 → Moussa, round 4 wraps to Awa';
end $$;
commit;

\echo ''
\echo '--- TEST 5: two members cannot hold the same turn ---'
begin;
set local "request.jwt.claim.sub" = '90909090-0000-0000-0000-000000000001';
set local role authenticated;
do $$
begin
    begin
        insert into tontine_members (tontine_id, org_id, name, position) values
            ('90a00000-0000-0000-0000-000000000001',
             '90000000-0000-0000-0000-000000000001', 'Intruse', 2);
        raise exception 'FAIL: two members at position 2';
    exception when unique_violation then
        raise notice 'PASS: position 2 is already Moussa''s';
    end;
end $$;
commit;

\echo ''
\echo '--- TEST 6: the neighbour sees no tontine and writes none ---'
begin;
set local "request.jwt.claim.sub" = '90909090-0000-0000-0000-000000000002';
set local role authenticated;
do $$
begin
    if exists (select 1 from tontines
                where org_id = '90000000-0000-0000-0000-000000000001') then
        raise exception 'FAIL: a stranger read the tontine';
    end if;
    if exists (select 1
                 from tontine_round_status('90a00000-0000-0000-0000-000000000001')) then
        raise exception 'FAIL: round status leaked across orgs';
    end if;

    begin
        insert into tontine_members (tontine_id, org_id, name, position) values
            ('90a00000-0000-0000-0000-000000000001',
             '90000000-0000-0000-0000-000000000001', 'Pirate', 9);
        raise exception 'FAIL: a stranger added a member';
    exception when insufficient_privilege or check_violation then
        raise notice 'PASS: stranger''s write refused';
    when others then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: stranger''s write refused — %', sqlerrm;
    end;
    raise notice 'PASS: the tontine is invisible from next door';
end $$;
commit;

\echo ''
\echo '=== test_tontines.sql: all assertions passed ==='
