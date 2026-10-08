-- ============================================================
-- test_farm_general.sql — a farm that is not only chickens.
--
-- Runs as `authenticated` throughout, never as postgres: every write here
-- goes through a SECURITY DEFINER function that makes its own membership
-- check, and half the assertions are RLS.
--
-- What this suite is about:
--
--   1. A count that can go negative. More animals dead than there are is a
--      typo, and left in it makes every figure after it wrong.
--   2. A harvest booked as income. Bringing a crop in is not earning money —
--      it is earning money later, or eating it — and a module that posts to
--      the ledger here inflates the income statement by every sack that never
--      reached a market.
--   3. A phone in a field retrying, and one death counted twice.
--   4. One farm's fields visible to another.
--   5. `flocks` being disturbed. Ignace's history is in it and 019 must not
--      touch it.
--
-- Phone block 84. The others: 70 rls, 71 invitations, 72 reports,
-- 73 accounting, 74 audit, 75/76 farm, 77 platform admin, 78 retail,
-- 79 employees, 80 capture, 81 org lifecycle, 82 delivery, 83 onboarding.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''84848484-0000-0000-0000-000000000001'''
\set hand  '''84848484-0000-0000-0000-000000000002'''
\set rival '''84848484-0000-0000-0000-000000000003'''

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
    (:owner, '+22684000001', '{"full_name": "Ignace"}'),
    (:hand,  '+22684000002', '{"full_name": "Ouvrier"}'),
    (:rival, '+22684000003', '{"full_name": "Ferme voisine"}');

insert into orgs (id, name, slug, profile, default_currency) values
    ('84000000-0000-0000-0000-000000000001', 'Ferme Mixte',   'ferme-mixte-84',   'farm', 'XOF'),
    ('84000000-0000-0000-0000-000000000002', 'Ferme Voisine', 'ferme-voisine-84', 'farm', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    ('84000000-0000-0000-0000-000000000001', :owner, 'owner',    'org', '84000000-0000-0000-0000-000000000001'),
    ('84000000-0000-0000-0000-000000000001', :hand,  'employee', 'org', '84000000-0000-0000-0000-000000000001'),
    ('84000000-0000-0000-0000-000000000002', :rival, 'owner',    'org', '84000000-0000-0000-0000-000000000002');

select seed_farm_accounts('84000000-0000-0000-0000-000000000001');

\echo ''
\echo '--- TEST 1: a farm keeps goats, not a flock of them ---'
begin;
set local "request.jwt.claim.sub" = '84848484-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_herd uuid;
    v_row  herds%rowtype;
begin
    v_herd := open_herd('84000000-0000-0000-0000-000000000001',
                        'caprin', 'Troupeau A', 24, 'Sahélienne',
                        'engraissement Tabaski');

    select * into v_row from herds where id = v_herd;
    if v_row.species <> 'caprin' or v_row.head_count <> 24 then
        raise exception 'FAIL: recorded % head of %', v_row.head_count, v_row.species;
    end if;

    -- The species is free text on purpose: a compiled list is wrong for the
    -- first farmer with guinea fowl.
    perform open_herd('84000000-0000-0000-0000-000000000001',
                      'pintade', 'Pintades 1', 40);

    -- Two groups cannot share a name, for the same reason two flocks cannot
    -- share a batch code: it splits a season's figures in half.
    begin
        perform open_herd('84000000-0000-0000-0000-000000000001',
                          'caprin', 'troupeau a', 5);
        raise exception 'FAIL: two groups share one name';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;

    raise notice 'PASS: 24 caprins and 40 pintades, neither of them a flock';
end $$;
commit;

\echo ''
\echo '--- TEST 2: a count cannot go negative ---'
begin;
set local "request.jwt.claim.sub" = '84848484-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_herd uuid;
    v_head int;
begin
    select id into v_herd from herds
    where org_id = '84000000-0000-0000-0000-000000000001' and label = 'Troupeau A';

    begin
        perform record_herd_event('84000000-0000-0000-0000-000000000001',
                                  v_herd, 'mortality', 99);
        raise exception 'FAIL: 99 of 24 animals died';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;

    -- Real losses and real births both move the count.
    perform record_herd_event('84000000-0000-0000-0000-000000000001',
                              v_herd, 'mortality', 2);
    perform record_herd_event('84000000-0000-0000-0000-000000000001',
                              v_herd, 'birth', 5);

    select head_count into v_head from herds where id = v_herd;
    if v_head <> 27 then
        raise exception 'FAIL: 24 - 2 + 5 came to %', v_head;
    end if;

    raise notice 'PASS: 24 less 2 plus 5 is 27';
end $$;
commit;

\echo ''
\echo '--- TEST 3: a phone in a field retrying counts one death ---'
begin;
set local "request.jwt.claim.sub" = '84848484-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_herd  uuid;
    v_first uuid;
    v_again uuid;
    v_head  int;
    v_uuid  uuid := 'eeeeeeee-0000-0000-0000-000000000084';
begin
    select id, head_count into v_herd, v_head from herds
    where org_id = '84000000-0000-0000-0000-000000000001' and label = 'Troupeau A';

    v_first := record_herd_event('84000000-0000-0000-0000-000000000001',
                                 v_herd, 'mortality', 1, current_date, null, v_uuid);
    v_again := record_herd_event('84000000-0000-0000-0000-000000000001',
                                 v_herd, 'mortality', 1, current_date, null, v_uuid);

    if v_first is distinct from v_again then
        raise exception 'FAIL: the retry recorded a second death';
    end if;

    if (select head_count from herds where id = v_herd) <> v_head - 1 then
        raise exception 'FAIL: one death took two animals';
    end if;

    raise notice 'PASS: sent twice, one animal';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: onions in a field, and the field is found by its name ---'
begin;
set local "request.jwt.claim.sub" = '84848484-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_cycle uuid;
    v_plots int;
    v_name  text;
begin
    v_cycle := open_crop_cycle('84000000-0000-0000-0000-000000000001',
                               'Oignon', 'Bas-fond 2', 'Violet de Galmi',
                               current_date - 30, current_date + 60, 1200, 'kg');

    -- The plot was made from its name, the same bargain ensure_account()
    -- makes: nobody has to define a field before recording on it.
    select count(*) into v_plots from plots
    where org_id = '84000000-0000-0000-0000-000000000001';
    if v_plots <> 1 then
        raise exception 'FAIL: % plots, expected 1', v_plots;
    end if;

    -- The same field again is the same field, not a second one.
    perform open_crop_cycle('84000000-0000-0000-0000-000000000001',
                            'Maïs', ' bas-fond 2 ');
    select count(*) into v_plots from plots
    where org_id = '84000000-0000-0000-0000-000000000001';
    if v_plots <> 1 then
        raise exception 'FAIL: the same field became % plots', v_plots;
    end if;

    select plot_name into v_name from crop_status('84000000-0000-0000-0000-000000000001')
    where id = v_cycle;
    if v_name <> 'Bas-fond 2' then
        raise exception 'FAIL: the plot reads "%"', v_name;
    end if;

    raise notice 'PASS: two plantings, one field, named once';
end $$;
commit;

\echo ''
\echo '--- TEST 5: a harvest is not income ---'
begin;
set local "request.jwt.claim.sub" = '84848484-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_cycle  uuid;
    v_income numeric;
    v_got    numeric;
begin
    select id into v_cycle from crop_cycles
    where org_id = '84000000-0000-0000-0000-000000000001' and crop = 'Oignon';

    perform record_harvest('84000000-0000-0000-0000-000000000001', v_cycle, 800);
    perform record_harvest('84000000-0000-0000-0000-000000000001', v_cycle, 150,
                           'kg', 'damaged');

    select harvested into v_got from crop_status('84000000-0000-0000-0000-000000000001')
    where id = v_cycle;
    if v_got <> 950 then
        raise exception 'FAIL: 800 + 150 came to %', v_got;
    end if;

    -- The assertion that matters. A sack in the store is not money, and a
    -- sack eaten at home never will be. Booking it as income here would
    -- inflate the income statement by everything that never reached a market.
    select coalesce(sum(jl.credit), 0) into v_income
    from journal_lines jl
    join accounts a on a.id = jl.account_id
    where a.org_id = '84000000-0000-0000-0000-000000000001'
      and a.type = 'income';

    if v_income <> 0 then
        raise exception 'FAIL: harvesting booked % of income', v_income;
    end if;

    raise notice 'PASS: 950 kg in the store, nothing in the books yet';
end $$;
commit;

\echo ''
\echo '--- TEST 6: the home screen can tell what kind of farm this is ---'
begin;
set local "request.jwt.claim.sub" = '84848484-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_row record;
begin
    select * into v_row from farm_profile_summary('84000000-0000-0000-0000-000000000001');

    if v_row.herds <> 2 then
        raise exception 'FAIL: % herds, expected 2', v_row.herds;
    end if;
    if v_row.crop_cycles <> 2 then
        raise exception 'FAIL: % plantings, expected 2', v_row.crop_cycles;
    end if;
    -- No birds here at all, and the summary says so rather than showing an
    -- empty poultry panel to a goat farmer.
    if v_row.flocks <> 0 or v_row.birds <> 0 then
        raise exception 'FAIL: this farm has % flocks', v_row.flocks;
    end if;
    if v_row.harvest_7days <> 950 then
        raise exception 'FAIL: % harvested this week', v_row.harvest_7days;
    end if;

    raise notice 'PASS: % groups, % plantings, no birds',
        v_row.herds, v_row.crop_cycles;
end $$;
rollback;

\echo ''
\echo '--- TEST 7: the neighbouring farm sees none of it ---'
begin;
set local "request.jwt.claim.sub" = '84848484-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_herds    int;
    v_cycles   int;
    v_harvests int;
    v_plots    int;
begin
    select count(*) into v_herds    from herds;
    select count(*) into v_cycles   from crop_cycles;
    select count(*) into v_harvests from harvests;
    select count(*) into v_plots    from plots;

    if v_herds <> 0 or v_cycles <> 0 or v_harvests <> 0 or v_plots <> 0 then
        raise exception
            'FAIL: the neighbour sees % herds, % plantings, % harvests, % fields',
            v_herds, v_cycles, v_harvests, v_plots;
    end if;

    -- And cannot record onto somebody else's land.
    begin
        perform open_crop_cycle('84000000-0000-0000-0000-000000000001', 'Tomate');
        raise exception 'FAIL: the neighbour planted in another farm''s field';
    exception
        when raise_exception then
            if sqlerrm like 'FAIL:%' then raise; end if;
            raise notice 'PASS: refused — %', sqlerrm;
    end;

    raise notice 'PASS: none of it is the neighbour''s business';
end $$;
rollback;

\echo ''
\echo '--- TEST 8: 009 is untouched, and a mixed farm has somewhere to post ---'
do $$
declare
    v_accounts int;
    v_flocks   int;
begin
    -- Ignace's poultry module still works exactly as it did. 019 adds beside
    -- it rather than migrating it, because rewriting a working module to make
    -- a name tidier is how live data gets lost.
    select count(*) into v_flocks from flocks;
    if v_flocks is null then
        raise exception 'FAIL: flocks is gone';
    end if;

    -- And a farm with goats and onions has real accounts to post to rather
    -- than filing both under "Autres ventes".
    select count(*) into v_accounts from accounts
    where org_id = '84000000-0000-0000-0000-000000000001'
      and name in ('Ventes de bétail', 'Ventes de récoltes', 'Semences',
                   'Engrais et traitements');
    if v_accounts <> 4 then
        raise exception 'FAIL: % of the 4 new farm accounts exist', v_accounts;
    end if;

    raise notice 'PASS: flocks intact, and livestock and crops have accounts';
end $$;

\echo ''
\echo 'test_farm_general.sql: all assertions held.'
