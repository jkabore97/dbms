-- ============================================================
-- test_association_trust.sql — the trust level (088). Phone block 58.
--
-- The claims: a new association is « Nouvelle »; books kept every week,
-- receipts on the expenses, few corrections and six months on Mara climb
-- it to « Fiable »; only Mara's verification makes it « Exemplaire »; only
-- a platform admin verifies; a stranger and a shop read nothing.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''58585858-0000-0000-0000-000000000001'''
\set admin '''58585858-0000-0000-0000-000000000002'''
\set other '''58585858-0000-0000-0000-000000000003'''
\set assoc '''58000000-0000-0000-0000-000000000001'''
\set shop  '''58000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- Earlier files hand every function to everyone: 088 takes its own back.
\i database/migrations/088_association_trust.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22658000001', '{"full_name": "Trésorière"}'),
    (:admin, '+22658000002', '{"full_name": "Mara"}'),
    (:other, '+22658000003', '{"full_name": "Autre"}');
update profiles set is_platform_admin = true where id = :admin;
insert into orgs (id, name, slug, profile, default_currency) values
    (:assoc, 'Association 58', 'assoc-58', 'association', 'XOF'),
    (:shop,  'Boutique 58',    'shop-58',  'retail',      'XOF');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:assoc, :owner, 'owner', 'org', :assoc, 'full'),
    (:shop,  :owner, 'owner', 'org', :shop,  'full');
select seed_church_accounts(:assoc);

\echo ''
\echo '--- TEST 1: a new association is « Nouvelle » ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '58585858-0000-0000-0000-000000000001';
do $$
declare t jsonb := association_trust('58000000-0000-0000-0000-000000000001');
begin
    if t ->> 'level' <> 'Nouvelle' or (t ->> 'met')::int <> 0 then
        raise exception 'FAIL: a new association is not Nouvelle: %', t;
    end if;
    if association_trust('58000000-0000-0000-0000-000000000002') is not null then
        raise exception 'FAIL: a shop has a trust level';
    end if;
    raise notice 'PASS: Nouvelle, and a shop has none';
end $$;
commit;

\echo ''
\echo '--- TEST 2: kept books climb it to « Fiable » ---'
-- Eight weeks of offerings, one expense a week with its receipt but one.
update orgs set created_at = now() - interval '200 days'
 where id = '58000000-0000-0000-0000-000000000001';
do $$
declare w int; e uuid;
begin
    for w in 0..7 loop
        perform record_contribution('58000000-0000-0000-0000-000000000001', 5000, 'offering',
            '58585858-0000-0000-0000-000000000001', p_occurred_at => now() - (w || ' weeks')::interval);
        e := record_expense('58000000-0000-0000-0000-000000000001', 1000, '5000',
            '58585858-0000-0000-0000-000000000001', p_occurred_at => now() - (w || ' weeks')::interval);
        if w > 0 then
            insert into documents (org_id, kind, r2_key, uploaded_by, linked_journal_entry_id)
            values ('58000000-0000-0000-0000-000000000001', 'receipt', 'r/' || e,
                    '58585858-0000-0000-0000-000000000001', e);
        end if;
    end loop;
end $$;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '58585858-0000-0000-0000-000000000001';
do $$
declare t jsonb := association_trust('58000000-0000-0000-0000-000000000001');
        p jsonb;
begin
    for p in select * from jsonb_array_elements(t -> 'pillars') loop
        if (p ->> 'key') <> 'verified' and not (p ->> 'met')::boolean then
            raise exception 'FAIL: pillar % not met: %', p ->> 'key', t;
        end if;
    end loop;
    if t ->> 'level' <> 'Fiable' then
        raise exception 'FAIL: kept books are not Fiable: %', t;
    end if;
    raise notice 'PASS: Fiable with four pillars, unverified';
end $$;
commit;

\echo ''
\echo '--- TEST 3: only Mara verifies, and only then « Exemplaire » ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '58585858-0000-0000-0000-000000000001';
do $$ begin
    begin
        perform set_org_verified('58000000-0000-0000-0000-000000000001', true);
        raise exception 'FAIL: an association verified itself';
    exception when others then
        if sqlerrm not like 'Seul Mara%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '58585858-0000-0000-0000-000000000002';
select set_org_verified('58000000-0000-0000-0000-000000000001', true);
do $$
declare t jsonb := association_trust('58000000-0000-0000-0000-000000000001');
begin
    if t ->> 'level' <> 'Exemplaire' then
        raise exception 'FAIL: verified and kept is not Exemplaire: %', t;
    end if;
    raise notice 'PASS: refused to the owner, Exemplaire once Mara ticked it';
end $$;
commit;

\echo ''
\echo '--- TEST 4: corrections and missing receipts cost it; strangers out ---'
-- Reverse a third of the entries: no longer clean.
do $$
declare e uuid;
begin
    for e in select id from journal_entries
              where org_id = '58000000-0000-0000-0000-000000000001'
                and reverses_entry_id is null order by created_at desc limit 5 loop
        perform reverse_entry(e, '58585858-0000-0000-0000-000000000001');
    end loop;
end $$;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '58585858-0000-0000-0000-000000000001';
do $$
declare t jsonb := association_trust('58000000-0000-0000-0000-000000000001');
begin
    if (select (p ->> 'met')::boolean from jsonb_array_elements(t -> 'pillars') p
         where p ->> 'key' = 'clean') then
        raise exception 'FAIL: many corrections still count as clean: %', t;
    end if;
    if t ->> 'level' = 'Exemplaire' then
        raise exception 'FAIL: still Exemplaire after the corrections';
    end if;
end $$;
set local "request.jwt.claim.sub" = '58585858-0000-0000-0000-000000000003';
do $$ begin
    if association_trust('58000000-0000-0000-0000-000000000001') is not null then
        raise exception 'FAIL: a stranger reads the trust level';
    end if;
end $$;
commit;
do $$ begin
    if has_function_privilege('anon', 'association_trust(uuid)', 'execute')
       or has_function_privilege('anon', 'set_org_verified(uuid, boolean)', 'execute') then
        raise exception 'FAIL: the grants are not as drawn';
    end if;
    raise notice 'PASS: corrections cost the level; strangers and anon read nothing';
end $$;

\echo ''
\echo 'test_association_trust: all passed'
