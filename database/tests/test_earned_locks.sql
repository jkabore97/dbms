-- ============================================================
-- test_earned_locks.sql — tools are earned (089), by the steps of Le
-- Chemin (097). Phone block 59.
--
-- The claims: a shop starts with invoices, production and the credit book
-- locked, with no trial; invoices open with the articles on sale and three
-- in photo, production once stage 2 (« Remplir ») is complete, the credit
-- book after 3 finished orders; a locked tool still reads
-- what was kept and still takes a repayment; Pro opens all three; a
-- second business needs Pro; an association is not on the path; and a
-- farm follows the same rule as a shop.
-- ============================================================
\set ON_ERROR_STOP on
-- 092 hides a vitrine below 8 items (test_vitrine_minimum.sql); this
-- suite is about something else, so it keeps the old rule (no minimum).
update platform_settings set value = '0' where key = 'vitrine_min_items';

\set owner '''59595959-0000-0000-0000-000000000001'''
\set prop  '''59595959-0000-0000-0000-000000000002'''
\set fresh '''59595959-0000-0000-0000-000000000003'''
\set treas '''59595959-0000-0000-0000-000000000004'''
\set shop  '''59000000-0000-0000-0000-000000000001'''
\set pro   '''59000000-0000-0000-0000-000000000002'''
\set farm  '''59000000-0000-0000-0000-000000000003'''
\set assoc '''59000000-0000-0000-0000-000000000004'''

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
grant execute on all functions in schema public to authenticated;
-- Earlier suites open the doors for their own fixtures: this one puts the
-- owner's numbers back, and takes 089's grants back — then 097's rule,
-- which replaces 089's functions.
update platform_settings set value = '0' where key = 'path_gates_open';
update platform_settings set value = '3' where key = 'progress_credit_orders';
\i database/migrations/089_earned_locks.sql
\i database/migrations/097_le_chemin.sql

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22659000001', '{"full_name": "Awa"}'),
    (:prop,  '+22659000002', '{"full_name": "Pro"}'),
    (:fresh, '+22659000003', '{"full_name": "Nouveau"}'),
    (:treas, '+22659000004', '{"full_name": "Trésorière"}');
insert into orgs (id, name, slug, profile, default_currency, progress_since, plan) values
    (:shop,  'Boutique 59', 'boutique-59', 'retail',      'XOF', null, 'free'),
    (:pro,   'Pro 59',      'pro-59',      'retail',      'XOF', null, 'pro'),
    (:farm,  'Ferme 59',    'ferme-59',    'farm',        'XOF', null, 'free'),
    (:assoc, 'Asso 59',     'asso-59',     'association', 'XOF', null, 'free');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :owner, 'owner', 'org', :shop,  'full'),
    (:farm,  :owner, 'owner', 'org', :farm,  'full'),
    (:pro,   :prop,  'owner', 'org', :pro,   'full'),
    (:assoc, :treas, 'owner', 'org', :assoc, 'full');

\echo ''
\echo '--- TEST 1: everything locked from the start, for an old shop too ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '59595959-0000-0000-0000-000000000001';
do $$
declare p jsonb := org_progress('59000000-0000-0000-0000-000000000001');
begin
    if (p ->> 'in_trial')::boolean
       or not (p -> 'locks' ->> 'invoices')::boolean
       or not (p -> 'locks' ->> 'production')::boolean
       or not (p -> 'locks' ->> 'credits')::boolean
       or not (p -> 'locks' ->> 'second_business')::boolean then
        raise exception 'FAIL: a business born before 085 is not locked: %', p;
    end if;
    begin
        perform create_invoice('59000000-0000-0000-0000-000000000001', 'Awa',
            '[{"description": "Riz", "quantity": 1, "unit_price": 1000}]'::jsonb);
        raise exception 'FAIL: an invoice on a locked shop';
    exception when others then
        if sqlerrm not like 'Factures : 1 articles en vente et 3 en photo%%' then raise; end if;
    end;
    begin
        perform record_credit_sale('59000000-0000-0000-0000-000000000001', 'Awa', 2000, 'Riz');
        raise exception 'FAIL: a debt on a locked shop';
    exception when others then
        if sqlerrm not like 'Carnet de crédit : 3 commandes%' then raise; end if;
    end;
    raise notice 'PASS: all locked, no trial, refused with the reason';
end $$;
commit;

\echo ''
\echo '--- TEST 2: invoices with articles and photos, production with stage 2 ---'
-- Articles (the minimum is 1 here), three in photo, the sentence, phone
-- and address — no pin, no sale yet: stage 2 is not complete.
update orgs set storefront_enabled = true, storefront_blurb = 'Le riz du quartier',
               phone = '+22659000001', address = 'Gounghin'
 where id = '59000000-0000-0000-0000-000000000001';
insert into products (org_id, name, sale_price, quantity, is_active, is_published)
select '59000000-0000-0000-0000-000000000001', 'Article ' || i, 100, 5, true, true
  from generate_series(1, 3) i;
insert into documents (org_id, product_id, kind, r2_key, uploaded_by)
select org_id, id, 'product_photo', 'p/' || id, '59595959-0000-0000-0000-000000000001'
  from products where org_id = '59000000-0000-0000-0000-000000000001';
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '59595959-0000-0000-0000-000000000001';
do $$
declare p jsonb := org_progress('59000000-0000-0000-0000-000000000001');
begin
    if (p -> 'locks' ->> 'invoices')::boolean or not (p -> 'locks' ->> 'production')::boolean then
        raise exception 'FAIL: with articles and photos invoices/production are wrong: %', p;
    end if;
    perform create_invoice('59000000-0000-0000-0000-000000000001', 'Awa',
        '[{"description": "Riz", "quantity": 1, "unit_price": 1000}]'::jsonb);
end $$;
commit;
update orgs set lat = 12.37, lng = -1.52 where id = '59000000-0000-0000-0000-000000000001';
do $$ begin
    -- A vitrine at 100 % is not the step: the first sale is still ahead.
    if not path_locked('59000000-0000-0000-0000-000000000001', 'production') then
        raise exception 'FAIL: production open without the first sale';
    end if;
    if path_lock_message('production') <> 'Production : terminez l''étape Remplir pour la débloquer.' then
        raise exception 'FAIL: the production lock says %', path_lock_message('production');
    end if;
end $$;
insert into sales (org_id, total) values ('59000000-0000-0000-0000-000000000001', 1000);
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '59595959-0000-0000-0000-000000000001';
do $$ begin
    if path_locked('59000000-0000-0000-0000-000000000001', 'production') then
        raise exception 'FAIL: production still locked with stage 2 complete';
    end if;
    raise notice 'PASS: invoices open with articles and photos, production with stage 2';
end $$;
commit;

\echo ''
\echo '--- TEST 3: locked again, the invoice kept is still read ---'
update products set is_published = false where org_id = '59000000-0000-0000-0000-000000000001';
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '59595959-0000-0000-0000-000000000001';
do $$ begin
    begin
        perform create_invoice('59000000-0000-0000-0000-000000000001', 'Awa',
            '[{"description": "Riz", "quantity": 1, "unit_price": 1000}]'::jsonb);
        raise exception 'FAIL: a new invoice once the vitrine fell back';
    exception when others then
        if sqlerrm not like 'Factures%' then raise; end if;
    end;
    if (select count(*) from invoices where org_id = '59000000-0000-0000-0000-000000000001') <> 1 then
        raise exception 'FAIL: the invoice kept is not readable';
    end if;
    raise notice 'PASS: no new invoice, the old one still there';
end $$;
commit;

\echo ''
\echo '--- TEST 4: the credit book after 3 finished orders; repayments always ---'
insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency)
select '59000000-0000-0000-0000-000000000001', '59595959-0000-0000-0000-000000000003',
       'Client', 'delivered', 'pickup', 1000, 'XOF'
  from generate_series(1, 2);
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '59595959-0000-0000-0000-000000000001';
do $$ begin
    if not path_locked('59000000-0000-0000-0000-000000000001', 'credits') then
        raise exception 'FAIL: the credit book opened after 2 orders';
    end if;
end $$;
commit;
insert into orders (org_id, customer_id, customer_name, status, fulfilment, total, currency)
values ('59000000-0000-0000-0000-000000000001', '59595959-0000-0000-0000-000000000003',
        'Client', 'picked_up', 'pickup', 1000, 'XOF');
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '59595959-0000-0000-0000-000000000001';
do $$
declare d uuid;
begin
    d := record_credit_sale('59000000-0000-0000-0000-000000000001', 'Awa', 2000, 'Riz');
    raise notice 'PASS: the third order opens the credit book';
end $$;
commit;
-- Lock it again: the repayment of what is owed still goes through.
update platform_settings set value = '99' where key = 'progress_credit_orders';
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '59595959-0000-0000-0000-000000000001';
do $$
declare v_debt uuid;
begin
    select id into v_debt from debts
     where org_id = '59000000-0000-0000-0000-000000000001' limit 1;
    perform record_debt_payment(v_debt, 500);
    raise notice 'PASS: a locked credit book still takes a repayment';
end $$;
commit;
update platform_settings set value = '3' where key = 'progress_credit_orders';

\echo ''
\echo '--- TEST 5: Pro opens the tools; a second business needs Pro ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '59595959-0000-0000-0000-000000000002';
do $$ begin
    if path_locked('59000000-0000-0000-0000-000000000002', 'invoices')
       or path_locked('59000000-0000-0000-0000-000000000002', 'production')
       or path_locked('59000000-0000-0000-0000-000000000002', 'credits') then
        raise exception 'FAIL: Pro is asked to earn its tools';
    end if;
    perform apply_for_org('Pro 59 bis', 'pro-59-bis', 'retail');
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '59595959-0000-0000-0000-000000000001';
do $$ begin
    begin
        perform apply_for_org('Boutique 59 bis', 'boutique-59-bis', 'retail');
        raise exception 'FAIL: a second business without Pro';
    exception when others then
        if sqlerrm not like 'Une deuxième entreprise : avec Mara Pro%' then raise; end if;
    end;
end $$;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '59595959-0000-0000-0000-000000000003';
do $$ begin
    perform apply_for_org('Première 59', 'premiere-59', 'retail');
    raise notice 'PASS: Pro passes, a second business without Pro does not, a first one does';
end $$;
commit;

\echo ''
\echo '--- TEST 6: a farm is held like a shop; an association is not ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '59595959-0000-0000-0000-000000000001';
do $$ begin
    if not path_locked('59000000-0000-0000-0000-000000000003', 'invoices')
       or not path_locked('59000000-0000-0000-0000-000000000003', 'production') then
        raise exception 'FAIL: a farm is not on the path';
    end if;
    begin
        perform create_invoice('59000000-0000-0000-0000-000000000003', 'Awa',
            '[{"description": "Oeufs", "quantity": 1, "unit_price": 2500}]'::jsonb);
        raise exception 'FAIL: an invoice on a locked farm';
    exception when others then
        if sqlerrm not like 'Factures%' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '59595959-0000-0000-0000-000000000004';
do $$ begin
    if path_locked('59000000-0000-0000-0000-000000000004', 'invoices') then
        raise exception 'FAIL: an association is on the path';
    end if;
end $$;
commit;
do $$ begin
    if has_function_privilege('anon', 'path_locked(uuid, text)', 'execute') then
        raise exception 'FAIL: anon asks about the locks';
    end if;
    raise notice 'PASS: the farm locked, the association free, anon out';
end $$;

\echo ''
\echo 'test_earned_locks: all passed'
