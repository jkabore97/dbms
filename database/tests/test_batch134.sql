-- ============================================================
-- test_batch134.sql — batch 138 (134): « La caisse et la cotisation », a
-- booking cancelled by its customer up to 2 hours before, and the weekly
-- prize's bell off.
--
-- The claims:
--   * the opening balance: an owner or admin of an association only
--     (an employee, a stranger, a shop's owner, anon refused); 0 or more;
--     once (a retry with its client_uuid answers the same, another call
--     refuses); never over books with movements, unless the opening entry
--     was reversed (002's reverse_entry) — then written again, at its
--     first date; a balanced entry: cash debit, « Solde de départ »
--     (equity) credit; trial_balance balanced, balance_sheet showing it
--     on both sides, income_statement unmoved, church_balances the cash;
--     zero: a row, no entry; the table's own guards hold for a direct
--     write (a forged entry, an old entry, an amount without one);
--   * the usual cotisation: an administrator's, > 0, by week, month or
--     year, read by every member, cleared by null; a shop refused;
--   * the home's card: books_start says what it needs; put away by an
--     administrator, for the business;
--   * the booking cancel: a confirmed or requested booking until booked_for
--     minus booking_cancel_hours (2), refused after in French, by nobody
--     but its customer; a proposal declined at any time (125 unchanged);
--     an order of goods: pending only, its bell unchanged; a booking paid
--     online refused; the business hears « Rendez-vous annulé par le
--     client — <jour>, <heure> »; booking_cancel_terms for the customer
--     alone; the setting 0 to 168, journaled by platform_set_setting;
--   * the week's close: prizes awarded and no bell with
--     cauris_prize_notify 0; the bells with it at 1;
--   * RLS and grants: three tables with row security, nothing for anon,
--     the INVOKER doors invoker, the definers' paths pinned and closed to
--     anon, the internals nobody's;
--   * the three kinds: shops and farms refused the books' start (an
--     association's), the booking cancel the same for a shop, a farm and
--     an association.
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
grant select, insert, update, delete on all tables in schema public to authenticated;
-- Supabase's own: the app's role reads auth.uid() (the INVOKER doors ask
-- it as the caller). Taken back at the end, as test_batch122 does.
grant usage on schema auth to authenticated;
-- Earlier suites re-apply older migrations (099's cancel_order, 086's
-- week close, 107's steps): 125 and 134 again, so what follows is 134's.
\i database/migrations/125_service_booking.sql
\i database/migrations/134_caisse_booking_cancel.sql
-- And the street's own grants, as they stand (an earlier suite hands
-- the app's roles every function).
revoke execute on function booking_cancel_hours() from authenticated;
revoke execute on function cauris_week_close(date) from authenticated;
revoke execute on function trg_books_opening_guard() from authenticated;
revoke execute on function trg_contribution_default_guard() from authenticated;
revoke execute on function trg_settings_134() from authenticated;

update platform_settings set value = '1'
 where key in ('vitrine_min_items', 'vitrine_min_items_association');
update platform_settings set value = '2' where key = 'booking_cancel_hours';

insert into auth.users (id, phone, email, raw_user_meta_data) values
    ('13413413-0000-0000-0000-000000000001', '+22613400001', null, '{"full_name": "Awa Trésorière134"}'),
    ('13413413-0000-0000-0000-000000000002', '+22613400002', null, '{"full_name": "Issa Employé134"}'),
    ('13413413-0000-0000-0000-000000000003', '+22613400003', null, '{"full_name": "Paul Étranger134"}'),
    ('13413413-0000-0000-0000-000000000004', null, 'cliente134@example.com', '{"full_name": "Cliente Cent-Trente-Quatre"}'),
    ('13413413-0000-0000-0000-000000000005', null, 'autre134@example.com',   '{"full_name": "Autre Cliente"}'),
    ('13413413-0000-0000-0000-000000000006', '+22613400006', null, '{"full_name": "Rose Boutique134"}'),
    ('13413413-0000-0000-0000-000000000007', '+22613400007', null, '{"full_name": "Ignace Ferme134"}'),
    ('13413413-0000-0000-0000-000000000008', '+22613400008', null, '{"full_name": "Mara Admin134"}');
update profiles set is_platform_admin = true where id = '13413413-0000-0000-0000-000000000008';

insert into orgs (id, name, slug, profile, default_currency, plan, storefront_enabled, storefront_blurb, storefront_style, phone) values
    ('13400000-0000-0000-0000-000000000001', 'Entraide 134',  'entraide-134',  'association', 'XOF', 'free', true, 'Bienvenue', '{}', '+22670134001'),
    -- An association that already has books.
    ('13400000-0000-0000-0000-000000000002', 'Amicale 134',   'amicale-134',   'association', 'XOF', 'free', false, null, '{}', null),
    -- A fresh one whose box is empty.
    ('13400000-0000-0000-0000-000000000003', 'Club 134',      'club-134',      'association', 'XOF', 'free', false, null, '{}', null),
    ('13400000-0000-0000-0000-000000000004', 'Boutique 134',  'boutique-134',  'retail',      'XOF', 'free', true, 'Bienvenue', '{}', '+22670134004'),
    ('13400000-0000-0000-0000-000000000005', 'Ferme 134',     'ferme-134',     'farm',        'XOF', 'free', true, 'Bienvenue', '{}', '+22670134005');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    ('13400000-0000-0000-0000-000000000001', '13413413-0000-0000-0000-000000000001', 'owner',    'org', '13400000-0000-0000-0000-000000000001', 'full'),
    ('13400000-0000-0000-0000-000000000001', '13413413-0000-0000-0000-000000000002', 'employee', 'org', '13400000-0000-0000-0000-000000000001', 'full'),
    ('13400000-0000-0000-0000-000000000002', '13413413-0000-0000-0000-000000000001', 'owner',    'org', '13400000-0000-0000-0000-000000000002', 'full'),
    ('13400000-0000-0000-0000-000000000003', '13413413-0000-0000-0000-000000000001', 'admin',    'org', '13400000-0000-0000-0000-000000000003', 'full'),
    ('13400000-0000-0000-0000-000000000004', '13413413-0000-0000-0000-000000000006', 'owner',    'org', '13400000-0000-0000-0000-000000000004', 'full'),
    ('13400000-0000-0000-0000-000000000005', '13413413-0000-0000-0000-000000000007', 'owner',    'org', '13400000-0000-0000-0000-000000000005', 'full');
select seed_church_accounts('13400000-0000-0000-0000-000000000001');
select seed_church_accounts('13400000-0000-0000-0000-000000000002');
select seed_church_accounts('13400000-0000-0000-0000-000000000003');
select seed_retail_accounts('13400000-0000-0000-0000-000000000004');

insert into products (id, org_id, name, sale_price, cost_price, quantity, is_active, is_published) values
    ('134aaaaa-0000-0000-0000-000000000001', '13400000-0000-0000-0000-000000000004', 'Savon 134', 500, 300, 50, true, true);
insert into products (id, org_id, name, sale_price, unit, is_service, is_active, is_published) values
    ('134aaaaa-0000-0000-0000-000000000002', '13400000-0000-0000-0000-000000000001', 'Location de la salle 134', 10000, null, true, true, true),
    ('134aaaaa-0000-0000-0000-000000000003', '13400000-0000-0000-0000-000000000004', 'Coupe 134', 3000, 'séance', true, true, true),
    ('134aaaaa-0000-0000-0000-000000000004', '13400000-0000-0000-0000-000000000005', 'Visite 134', 1000, null, true, true, true);

-- A call as a person, taken back: '(went through)' or the refusal's words.
create or replace function pg_temp.try134(p_who uuid, p_sql text, p_role text default 'authenticated')
returns text
language plpgsql
as $$
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true);
    begin
        execute format('set local role %I', p_role);
        execute p_sql;
        raise exception using errcode = 'P0134', message = 'taken back';
    exception
        when sqlstate 'P0134' then
            execute 'reset role';
            return '(went through)';
        when others then
            execute 'reset role';
            return sqlerrm;
    end;
end;
$$;

-- The same call, kept: its answer as text.
create or replace function pg_temp.do134(p_who uuid, p_sql text)
returns text
language plpgsql
as $$
declare v text;
begin
    perform set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true);
    execute 'set local role authenticated';
    execute p_sql into v;
    execute 'reset role';
    return v;
end;
$$;

-- Two days from now at 10:00 in Ouagadougou: a slot every vitrine with no
-- hours takes.
create or replace function pg_temp.slot134(p_days int default 2, p_time time default '10:00')
returns timestamptz
language sql
as $$
    select (((now() at time zone 'Africa/Ouagadougou')::date + p_days) + p_time)
           at time zone 'Africa/Ouagadougou';
$$;

create or replace function pg_temp.book134(p_slug text, p_product text, p_at timestamptz)
returns text
language sql
as $$
    select format('select book_service(%L, %L::uuid, %L::timestamptz, 1, %L)',
                  p_slug, p_product, p_at, 'Pour une réunion');
$$;

\echo ''
\echo '--- TEST 1: the opening balance — who may set it ---'
do $$
declare v text;
begin
    v := pg_temp.try134('13413413-0000-0000-0000-000000000002',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000001'', 50000)');
    if v <> 'Seul un responsable de l''association peut indiquer la caisse de départ.' then
        raise exception 'FAIL: an employee set the opening: %', v;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000003',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000001'', 50000)');
    if v not like 'Seul un responsable%' then
        raise exception 'FAIL: a stranger set the opening: %', v;
    end if;
    v := pg_temp.try134(null,
        'select set_opening_balance(''13400000-0000-0000-0000-000000000001'', 50000)', 'anon');
    if v not like 'permission denied%' then
        raise exception 'FAIL: anon reached the door: %', v;
    end if;
    -- A platform admin is not a member: not the treasurer's door.
    v := pg_temp.try134('13413413-0000-0000-0000-000000000008',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000001'', 50000)');
    if v not like 'Seul un responsable%' then
        raise exception 'FAIL: the platform set an association''s opening: %', v;
    end if;
    -- A shop's and a farm's owner: an association's word only.
    v := pg_temp.try134('13413413-0000-0000-0000-000000000006',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000004'', 50000)');
    if v <> 'Le solde de départ est celui d''une association.' then
        raise exception 'FAIL: a shop set an opening: %', v;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000007',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000005'', 50000)');
    if v <> 'Le solde de départ est celui d''une association.' then
        raise exception 'FAIL: a farm set an opening: %', v;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000001'', -5)');
    if v <> 'Un montant de 0 ou plus, s''il vous plaît.' then
        raise exception 'FAIL: a negative opening: %', v;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000001'', 5, ''sous le matelas'')');
    if v not like 'La caisse, la banque ou le Mobile Money%' then
        raise exception 'FAIL: an unknown method: %', v;
    end if;
    if exists (select 1 from books_opening where org_id::text like '13400000-%') then
        raise exception 'FAIL: something was written';
    end if;
    raise notice 'PASS: an employee, a stranger, anon, the platform, a shop and a farm refused; below zero and an unknown box refused';
end $$;

\echo ''
\echo '--- TEST 2: the owner says 50 000 in the box — one balanced entry, the reports show it ---'
do $$
declare
    r     jsonb;
    e     journal_entries%rowtype;
    v_eq  accounts%rowtype;
    n     int;
begin
    r := pg_temp.do134('13413413-0000-0000-0000-000000000001',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000001'', 50000, ''cash'', ''13400000-aaaa-0000-0000-000000000001'')::text')::jsonb;
    if (r ->> 'amount')::numeric <> 50000 or r ->> 'entry_id' is null or (r ->> 'again')::boolean then
        raise exception 'FAIL: the answer %', r;
    end if;
    select * into e from journal_entries where id = (r ->> 'entry_id')::uuid;
    if e.label <> 'Solde de départ' or e.details ->> 'kind' <> 'opening_balance'
       or e.created_by <> '13413413-0000-0000-0000-000000000001' then
        raise exception 'FAIL: the entry %', to_jsonb(e);
    end if;
    select a.* into v_eq from accounts a
     where a.org_id = '13400000-0000-0000-0000-000000000001' and a.type = 'equity';
    if v_eq.name <> 'Solde de départ' or v_eq.code <> '3000' then
        raise exception 'FAIL: the equity account %', to_jsonb(v_eq);
    end if;
    select count(*) into n from journal_lines jl join accounts a on a.id = jl.account_id
     where jl.journal_entry_id = e.id
       and ((a.code = '1000' and jl.debit = 50000 and jl.credit = 0)
         or (a.id = v_eq.id and jl.credit = 50000 and jl.debit = 0));
    if n <> 2 or (select count(*) from journal_lines where journal_entry_id = e.id) <> 2 then
        raise exception 'FAIL: the lines are not cash 50 000 / Solde de départ 50 000';
    end if;
    -- The reports, as the owner reads them.
    perform set_config('request.jwt.claim.sub', '13413413-0000-0000-0000-000000000001', true);
    set local role authenticated;
    if (select sum(total_debit) - sum(total_credit) from trial_balance('13400000-0000-0000-0000-000000000001')) <> 0 then
        raise exception 'FAIL: the trial balance does not balance';
    end if;
    if (select amount from balance_sheet('13400000-0000-0000-0000-000000000001')
         where section = 'equity' and name = 'Solde de départ') <> 50000
       or (select amount from balance_sheet('13400000-0000-0000-0000-000000000001')
            where section = 'asset' and name = 'Cash on Hand') <> 50000
       or (select amount from balance_sheet('13400000-0000-0000-0000-000000000001') where name = 'Total actif')
          <> (select amount from balance_sheet('13400000-0000-0000-0000-000000000001') where name = 'Total passif') then
        raise exception 'FAIL: the balance sheet: %',
            (select jsonb_agg(to_jsonb(b)) from balance_sheet('13400000-0000-0000-0000-000000000001') b);
    end if;
    if (select amount from income_statement('13400000-0000-0000-0000-000000000001') where name = 'Résultat') <> 0 then
        raise exception 'FAIL: the opening was counted as income';
    end if;
    if (select balance from church_balances('13400000-0000-0000-0000-000000000001') where account_name = 'Cash on Hand') <> 50000 then
        raise exception 'FAIL: the cash balance';
    end if;
    if not exists (select 1 from journal_page('13400000-0000-0000-0000-000000000001')
                    where label = 'Solde de départ' and amount = 50000 and direction = 'transfer') then
        raise exception 'FAIL: the journal does not show it';
    end if;
    r := books_start('13400000-0000-0000-0000-000000000001');
    reset role;
    if not (r ->> 'opening_set')::boolean or (r ->> 'opening_amount')::numeric <> 50000
       or (r ->> 'can_set')::boolean or (r ->> 'movements')::boolean then
        raise exception 'FAIL: books_start after the opening: %', r;
    end if;
    raise notice 'PASS: cash 50 000 debit / « Solde de départ » (3000, equity) 50 000 credit; balanced; on the balance sheet, not in the result; in the journal';
end $$;

\echo ''
\echo '--- TEST 3: once — the same call again answers the same, another refuses ---'
do $$
declare r jsonb; v text;
begin
    r := pg_temp.do134('13413413-0000-0000-0000-000000000001',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000001'', 50000, ''cash'', ''13400000-aaaa-0000-0000-000000000001'')::text')::jsonb;
    if not (r ->> 'again')::boolean then
        raise exception 'FAIL: the retry wrote again: %', r;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000001'', 70000)');
    if v <> 'Le solde de départ est déjà enregistré.' then
        raise exception 'FAIL: a second opening: %', v;
    end if;
    if (select count(*) from journal_entries where org_id = '13400000-0000-0000-0000-000000000001') <> 1 then
        raise exception 'FAIL: more than one entry';
    end if;
    raise notice 'PASS: a retry is a no-op, a second opening refused, one entry';
end $$;

\echo ''
\echo '--- TEST 4: never over books with movements; zero is a row and no entry ---'
do $$
declare v text; r jsonb;
begin
    -- L'Amicale already recorded a cotisation.
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001',
        'select record_entry(''13400000-0000-0000-0000-000000000002'', 2000, ''in'', ''Cotisation'', null, ''Cotisations'')::text');
    r := pg_temp.do134('13413413-0000-0000-0000-000000000001',
        'select books_start(''13400000-0000-0000-0000-000000000002'')::text')::jsonb;
    if not (r ->> 'movements')::boolean or (r ->> 'can_set')::boolean then
        raise exception 'FAIL: books_start over movements: %', r;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000002'', 10000)');
    if v <> 'Vos comptes ont déjà des mouvements : le solde de départ ne s''indique plus.' then
        raise exception 'FAIL: an opening over movements: %', v;
    end if;
    -- Straight into the table, the same.
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001',
        'insert into books_opening (org_id, amount) values (''13400000-0000-0000-0000-000000000002'', 0)');
    if v not like 'Vos comptes ont déjà des mouvements%' then
        raise exception 'FAIL: a direct opening over movements: %', v;
    end if;
    -- Le Club's box is empty: zero.
    r := pg_temp.do134('13413413-0000-0000-0000-000000000001',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000003'', 0)::text')::jsonb;
    if (r ->> 'amount')::numeric <> 0 or r ->> 'entry_id' is not null
       or exists (select 1 from journal_entries where org_id = '13400000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: a zero opening: % ', r;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000003'', 0)');
    if v <> 'Le solde de départ est déjà enregistré.' then
        raise exception 'FAIL: a second zero: %', v;
    end if;
    raise notice 'PASS: books with movements refused (the door and the table); zero is a row, no entry, once';
end $$;

\echo ''
\echo '--- TEST 5: the table guards a direct write ---'
do $$
declare v text; v_old uuid;
begin
    delete from books_opening where org_id = '13400000-0000-0000-0000-000000000003';
    -- An amount and no entry.
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001',
        'insert into books_opening (org_id, amount) values (''13400000-0000-0000-0000-000000000003'', 9000)');
    if v not like '%books_opening_check%' then
        raise exception 'FAIL: an amount without its entry: %', v;
    end if;
    -- An entry that is not an opening (an ordinary one, of this very call).
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001', $q$
        with e as (insert into journal_entries (org_id, label, created_by)
                   values ('13400000-0000-0000-0000-000000000003', 'Rien', '13413413-0000-0000-0000-000000000001')
                   returning id)
        insert into books_opening (org_id, amount, entry_id)
        select '13400000-0000-0000-0000-000000000003', 9000, id from e $q$);
    if v not like 'Le solde de départ s''écrit avec son écriture.%' and v not like 'Vos comptes%' then
        raise exception 'FAIL: a forged entry: %', v;
    end if;
    -- An employee, straight in: RLS first.
    v := pg_temp.try134('13413413-0000-0000-0000-000000000002',
        'insert into books_opening (org_id, amount) values (''13400000-0000-0000-0000-000000000001'', 0)');
    if v not like 'Seul un responsable%' then
        raise exception 'FAIL: an employee wrote the table: %', v;
    end if;
    -- An old entry (another transaction's) named as the opening of L'Amicale.
    select id into v_old from journal_entries where org_id = '13400000-0000-0000-0000-000000000002' limit 1;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001',
        format('update books_opening set entry_id = %L where org_id = %L', v_old, '13400000-0000-0000-0000-000000000001'));
    if v not like 'Le solde de départ est déjà enregistré.%' then
        raise exception 'FAIL: an opening moved onto another entry: %', v;
    end if;
    -- A stranger reads no opening.
    if pg_temp.do134('13413413-0000-0000-0000-000000000003', 'select count(*)::text from books_opening') <> '0'
       or pg_temp.do134('13413413-0000-0000-0000-000000000003',
            'select coalesce(books_start(''13400000-0000-0000-0000-000000000001'')::text, ''null'')') <> 'null' then
        raise exception 'FAIL: a stranger reads the opening';
    end if;
    -- Le Club's zero again, for what follows.
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000003'', 0)::text');
    raise notice 'PASS: no amount without its entry, no forged or moved entry, no employee, nothing for a stranger';
end $$;

\echo ''
\echo '--- TEST 6: the correction path — the opening reversed, written again at its first date ---'
do $$
declare
    v_first uuid; v_at timestamptz; r jsonb; v text;
begin
    select entry_id into v_first from books_opening where org_id = '13400000-0000-0000-0000-000000000001';
    select created_at into v_at from journal_entries where id = v_first;
    -- A cotisation comes in: the books now have movements.
    perform pg_temp.do134('13413413-0000-0000-0000-000000000002',
        'select record_entry(''13400000-0000-0000-0000-000000000001'', 3000, ''in'', ''Cotisation'', null, ''Cotisations'')::text');
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000001'', 60000)');
    if v <> 'Le solde de départ est déjà enregistré.' then
        raise exception 'FAIL: a second opening before the correction: %', v;
    end if;
    -- « Annuler » on the opening (002's reverse_entry), as the owner.
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001',
        format('select reverse_entry(%L, %L, %L)::text', v_first, '13413413-0000-0000-0000-000000000001', 'Correction'));
    -- An employee still may not.
    v := pg_temp.try134('13413413-0000-0000-0000-000000000002',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000001'', 60000)');
    if v not like 'Seul un responsable%' then
        raise exception 'FAIL: an employee corrected the opening: %', v;
    end if;
    r := pg_temp.do134('13413413-0000-0000-0000-000000000001',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000001'', 60000)::text')::jsonb;
    if (select created_at from journal_entries where id = (r ->> 'entry_id')::uuid) <> v_at
       or (select amount from books_opening where org_id = '13400000-0000-0000-0000-000000000001') <> 60000 then
        raise exception 'FAIL: the correction: %', r;
    end if;
    perform set_config('request.jwt.claim.sub', '13413413-0000-0000-0000-000000000001', true);
    set local role authenticated;
    if (select amount from balance_sheet('13400000-0000-0000-0000-000000000001')
         where section = 'equity' and name = 'Solde de départ') <> 60000
       or (select amount from balance_sheet('13400000-0000-0000-0000-000000000001')
            where section = 'asset' and name = 'Cash on Hand') <> 63000
       or (select sum(total_debit) - sum(total_credit) from trial_balance('13400000-0000-0000-0000-000000000001')) <> 0 then
        raise exception 'FAIL: the books after the correction';
    end if;
    reset role;
    -- Corrected once, it is the opening again: no third.
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001',
        'select set_opening_balance(''13400000-0000-0000-0000-000000000001'', 1)');
    if v <> 'Le solde de départ est déjà enregistré.' then
        raise exception 'FAIL: a third opening: %', v;
    end if;
    raise notice 'PASS: reversed through 002''s « Annuler », written again at the first date over movements; balanced; not a third time';
end $$;

\echo ''
\echo '--- TEST 7: the usual cotisation ---'
do $$
declare v text; r jsonb;
begin
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001',
        'select set_contribution_default(''13400000-0000-0000-0000-000000000001'', 2000, ''month'')::text');
    r := pg_temp.do134('13413413-0000-0000-0000-000000000002',
        'select books_start(''13400000-0000-0000-0000-000000000001'')::text')::jsonb;
    if r -> 'contribution' <> '{"amount": 2000.00, "period": "month"}'::jsonb then
        raise exception 'FAIL: an employee reads %', r -> 'contribution';
    end if;
    if (r ->> 'can_set')::boolean then
        raise exception 'FAIL: an employee may set the opening';
    end if;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001',
        'select set_contribution_default(''13400000-0000-0000-0000-000000000001'', 500, ''week'')::text');
    if (select period from contribution_defaults where org_id = '13400000-0000-0000-0000-000000000001') <> 'week' then
        raise exception 'FAIL: changed';
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000002',
        'select set_contribution_default(''13400000-0000-0000-0000-000000000001'', 1000, ''month'')');
    if v not like 'Seul un responsable%' then
        raise exception 'FAIL: an employee set the cotisation: %', v;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001',
        'select set_contribution_default(''13400000-0000-0000-0000-000000000001'', 0, ''month'')');
    if v <> 'Une cotisation de plus de zéro, s''il vous plaît.' then
        raise exception 'FAIL: zero: %', v;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001',
        'select set_contribution_default(''13400000-0000-0000-0000-000000000001'', 1000, ''day'')');
    if v <> 'Par semaine, par mois ou par an, s''il vous plaît.' then
        raise exception 'FAIL: a day: %', v;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000006',
        'select set_contribution_default(''13400000-0000-0000-0000-000000000004'', 1000, ''month'')');
    if v <> 'La cotisation habituelle est celle d''une association.' then
        raise exception 'FAIL: a shop''s cotisation: %', v;
    end if;
    -- Cleared, then set for the rest.
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001',
        'select set_contribution_default(''13400000-0000-0000-0000-000000000003'', 1500, ''year'')::text');
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001',
        'select set_contribution_default(''13400000-0000-0000-0000-000000000003'', null)::text');
    if exists (select 1 from contribution_defaults where org_id = '13400000-0000-0000-0000-000000000003') then
        raise exception 'FAIL: not cleared';
    end if;
    raise notice 'PASS: set and changed by an administrator, read by a member, > 0, by week/month/year, a shop refused, cleared by null';
end $$;

\echo ''
\echo '--- TEST 8: the home''s card — books_start and « Plus tard » ---'
do $$
declare v text; r jsonb;
begin
    -- A fresh association: nothing yet.
    insert into orgs (id, name, slug, profile, default_currency)
    values ('13400000-0000-0000-0000-000000000006', 'Tontine 134', 'tontine-134', 'association', 'XOF');
    insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
        ('13400000-0000-0000-0000-000000000006', '13413413-0000-0000-0000-000000000001', 'owner', 'org', '13400000-0000-0000-0000-000000000006', 'full'),
        ('13400000-0000-0000-0000-000000000006', '13413413-0000-0000-0000-000000000002', 'employee', 'org', '13400000-0000-0000-0000-000000000006', 'full');
    r := pg_temp.do134('13413413-0000-0000-0000-000000000001',
        'select books_start(''13400000-0000-0000-0000-000000000006'')::text')::jsonb;
    if not (r ->> 'association')::boolean or not (r ->> 'can_set')::boolean or (r ->> 'opening_set')::boolean
       or (r ->> 'movements')::boolean or (r ->> 'dismissed')::boolean or r -> 'contribution' <> 'null'::jsonb then
        raise exception 'FAIL: a fresh association: %', r;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000002',
        'select dismiss_books_start(''13400000-0000-0000-0000-000000000006'')');
    if v not like 'new row violates row-level security%' then
        raise exception 'FAIL: an employee put the card away: %', v;
    end if;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001',
        'select dismiss_books_start(''13400000-0000-0000-0000-000000000006'')::text');
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001',
        'select dismiss_books_start(''13400000-0000-0000-0000-000000000006'')::text');
    r := pg_temp.do134('13413413-0000-0000-0000-000000000002',
        'select books_start(''13400000-0000-0000-0000-000000000006'')::text')::jsonb;
    if not (r ->> 'dismissed')::boolean then
        raise exception 'FAIL: not put away for the business';
    end if;
    -- A shop reads that it is not an association.
    r := pg_temp.do134('13413413-0000-0000-0000-000000000006',
        'select books_start(''13400000-0000-0000-0000-000000000004'')::text')::jsonb;
    if (r ->> 'association')::boolean or (r ->> 'can_set')::boolean then
        raise exception 'FAIL: a shop''s books_start: %', r;
    end if;
    -- The walkthrough's new step, optional.
    if not exists (select 1 from jsonb_array_elements(kind_setup_steps('association')) e
                    where e ->> 'key' = 'caisse' and not (e ->> 'required')::boolean)
       or (select jsonb_agg(e ->> 'key') from jsonb_array_elements(kind_setup_steps('association')) e)
          <> '["identity", "members", "caisse", "vitrine"]'::jsonb
       or exists (select 1 from jsonb_array_elements(kind_setup_steps('retail')) e where e ->> 'key' = 'caisse') then
        raise exception 'FAIL: the steps';
    end if;
    raise notice 'PASS: books_start says it all; « Plus tard » an administrator''s, for the business, twice harmless; a shop is no association; « caisse » the association''s third step, optional';
end $$;

\echo ''
\echo '--- TEST 9: a confirmed booking cancelled before the cutoff; the business hears it ---'
do $$
declare v_id uuid; v_at timestamptz := pg_temp.slot134(2, '10:00'); r jsonb; v text; n notifications%rowtype;
begin
    v_id := pg_temp.do134('13413413-0000-0000-0000-000000000004',
        pg_temp.book134('entraide-134', '134aaaaa-0000-0000-0000-000000000002', v_at))::uuid;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001',
        format('select decide_order(%L, ''accepted'')::text', v_id));
    r := pg_temp.do134('13413413-0000-0000-0000-000000000004',
        format('select booking_cancel_terms(%L)::text', v_id))::jsonb;
    if (r ->> 'hours')::int <> 2 or not (r ->> 'can_cancel')::boolean
       or (r ->> 'until')::timestamptz <> v_at - interval '2 hours' or r ->> 'phone' <> '+22670134001' then
        raise exception 'FAIL: the terms %', r;
    end if;
    -- Somebody else: no terms, no cancel.
    if pg_temp.do134('13413413-0000-0000-0000-000000000005',
           format('select coalesce(booking_cancel_terms(%L)::text, ''null'')', v_id)) <> 'null' then
        raise exception 'FAIL: another person reads the terms';
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000005', format('select cancel_order(%L)', v_id));
    if v <> 'This order can no longer be cancelled' then
        raise exception 'FAIL: another person cancelled: %', v;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001', format('select cancel_order(%L)', v_id));
    if v <> 'This order can no longer be cancelled' then
        raise exception 'FAIL: the business cancelled through the customer''s door: %', v;
    end if;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)::text', v_id));
    if (select status from orders where id = v_id) <> 'cancelled' then
        raise exception 'FAIL: not cancelled';
    end if;
    select * into n from notifications
     where kind = 'booking_cancelled' and (params ->> 'order_id')::uuid = v_id
       and recipient_id = '13413413-0000-0000-0000-000000000001';
    if not found or n.message <> 'Rendez-vous annulé par le client — ' || booking_when_fr(v_at)
       or n.params ->> 'to' <> 'shop' or (n.params ->> 'at')::timestamptz <> v_at
       or notification_type_of(n.kind, n.params) <> 'shop_orders' then
        raise exception 'FAIL: the bell %', to_jsonb(n);
    end if;
    -- The employee is not an administrator: no bell (as every order's).
    if exists (select 1 from notifications where kind = 'booking_cancelled'
                and recipient_id = '13413413-0000-0000-0000-000000000002') then
        raise exception 'FAIL: the employee was rung';
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)', v_id));
    if v <> 'This order can no longer be cancelled' then
        raise exception 'FAIL: cancelled twice: %', v;
    end if;
    raise notice 'PASS: confirmed, cancelled by its customer 2 days ahead; nobody else; « % »', n.message;
end $$;

\echo ''
\echo '--- TEST 10: after the cutoff — refused, the booking stays; requested the same; paid online refused ---'
do $$
declare v_conf uuid; v_req uuid; v_paid uuid; v text; r jsonb;
begin
    -- A shop's and a farm's: the same rule for every kind.
    v_conf := pg_temp.do134('13413413-0000-0000-0000-000000000004',
        pg_temp.book134('boutique-134', '134aaaaa-0000-0000-0000-000000000003', pg_temp.slot134(3, '11:00')))::uuid;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000006', format('select decide_order(%L, ''accepted'')::text', v_conf));
    v_req := pg_temp.do134('13413413-0000-0000-0000-000000000004',
        pg_temp.book134('ferme-134', '134aaaaa-0000-0000-0000-000000000004', pg_temp.slot134(3, '15:00')))::uuid;
    -- The slots come close: one hour away.
    update orders set booked_for = now() + interval '1 hour' where id in (v_conf, v_req);
    r := pg_temp.do134('13413413-0000-0000-0000-000000000004', format('select booking_cancel_terms(%L)::text', v_conf))::jsonb;
    if (r ->> 'can_cancel')::boolean or r ->> 'phone' <> '+22670134004' then
        raise exception 'FAIL: the terms after the cutoff %', r;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)', v_conf));
    if v <> 'Trop tard pour annuler : appelez la boutique.' then
        raise exception 'FAIL: a confirmed booking an hour away: %', v;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)', v_req));
    if v <> 'Trop tard pour annuler : appelez la boutique.' then
        raise exception 'FAIL: a requested booking an hour away: %', v;
    end if;
    if (select status from orders where id = v_conf) <> 'accepted'
       or (select status from orders where id = v_req) <> 'pending' then
        raise exception 'FAIL: a refused cancel moved the booking';
    end if;
    -- Requested, far ahead: cancelled, and heard as a booking.
    update orders set booked_for = pg_temp.slot134(4, '09:00') where id = v_req;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)::text', v_req));
    if not exists (select 1 from notifications where kind = 'booking_cancelled'
                    and (params ->> 'order_id')::uuid = v_req
                    and recipient_id = '13413413-0000-0000-0000-000000000007') then
        raise exception 'FAIL: the farm did not hear its requested booking cancelled';
    end if;
    -- Paid online, far ahead: the business gives the money back, not the app.
    v_paid := pg_temp.do134('13413413-0000-0000-0000-000000000004',
        pg_temp.book134('entraide-134', '134aaaaa-0000-0000-0000-000000000002', pg_temp.slot134(5, '10:00')))::uuid;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001', format('select decide_order(%L, ''accepted'')::text', v_paid));
    update orders set payment_method = 'wave', paid_at = now() where id = v_paid;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)', v_paid));
    if v <> 'Ce rendez-vous est déjà payé : appelez la boutique pour l''annuler.' then
        raise exception 'FAIL: a booking paid online: %', v;
    end if;
    if (pg_temp.do134('13413413-0000-0000-0000-000000000004', format('select booking_cancel_terms(%L)::text', v_paid))::jsonb ->> 'can_cancel')::boolean then
        raise exception 'FAIL: the terms of a paid booking';
    end if;
    raise notice 'PASS: an hour away refused in French and left as it was (shop confirmed, farm requested); far ahead cancelled; paid online refused';
end $$;

\echo ''
\echo '--- TEST 11: the setting — read by the door, 0 to 168, journaled ---'
do $$
declare v_id uuid; v text;
begin
    v_id := (select id from orders where org_id = '13400000-0000-0000-0000-000000000004'
               and status = 'accepted' and booked_for < now() + interval '2 hours');
    v := pg_temp.try134('13413413-0000-0000-0000-000000000008',
        'select platform_set_setting(''booking_cancel_hours'', ''200'')');
    if v <> 'Un nombre d''heures de 0 à 168, s''il vous plaît.' then
        raise exception 'FAIL: 200 hours: %', v;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000008',
        'select platform_set_setting(''booking_cancel_hours'', ''1.5'')');
    if v not like 'Un nombre entier%' and v not like 'Un nombre d''heures%' then
        raise exception 'FAIL: 1.5 hours: %', v;
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001',
        'select platform_set_setting(''booking_cancel_hours'', ''0'')');
    if v = '(went through)' then
        raise exception 'FAIL: a business set the platform''s hours';
    end if;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000008',
        'select platform_set_setting(''booking_cancel_hours'', ''0'')::text');
    if booking_cancel_hours() <> 0 or not exists (
        select 1 from platform_actions where after ->> 'key' = 'booking_cancel_hours') then
        raise exception 'FAIL: not set, or not journaled';
    end if;
    -- At 0 the booking an hour away is cancelled.
    perform pg_temp.do134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)::text', v_id));
    if (select status from orders where id = v_id) <> 'cancelled' then
        raise exception 'FAIL: the setting was not read';
    end if;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000008',
        'select platform_set_setting(''booking_cancel_hours'', ''2'')::text');
    raise notice 'PASS: 0 to 168 whole hours, the platform''s alone, journaled, read by cancel_order';
end $$;

\echo ''
\echo '--- TEST 12: P1 — an order of goods, a proposal, a slot-less booking: as 099 and 125 left them ---'
do $$
declare v_goods uuid; v_acc uuid; v_prop uuid; v text;
begin
    insert into orders (org_id, customer_id, customer_name, status, total)
    values ('13400000-0000-0000-0000-000000000004', '13413413-0000-0000-0000-000000000004', 'Cliente Cent-Trente-Quatre', 'pending', 500)
    returning id into v_goods;
    insert into order_lines (order_id, product_id, name, unit_price, quantity, is_service)
    values (v_goods, '134aaaaa-0000-0000-0000-000000000001', 'Savon 134', 500, 1, false);
    insert into orders (org_id, customer_id, customer_name, status, total)
    values ('13400000-0000-0000-0000-000000000004', '13413413-0000-0000-0000-000000000004', 'Cliente Cent-Trente-Quatre', 'accepted', 500)
    returning id into v_acc;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)', v_acc));
    if v <> 'This order can no longer be cancelled' then
        raise exception 'FAIL: an accepted order of goods was cancelled: %', v;
    end if;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)::text', v_goods));
    if (select message from notifications where kind = 'order_withdrawn' and (params ->> 'order_id')::uuid = v_goods)
       <> 'Cliente Cent-Trente-Quatre a annulé sa commande' then
        raise exception 'FAIL: the goods'' bell changed';
    end if;
    -- A proposal whose time has passed: still declined by cancelling (125's TEST 8).
    v_prop := pg_temp.do134('13413413-0000-0000-0000-000000000004',
        pg_temp.book134('boutique-134', '134aaaaa-0000-0000-0000-000000000003', pg_temp.slot134(2, '16:00')))::uuid;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000006',
        format('select propose_booking_time(%L, %L)::text', v_prop, pg_temp.slot134(2, '16:30')));
    update orders set proposed_for = now() - interval '1 minute', booked_for = now() + interval '10 minutes' where id = v_prop;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)::text', v_prop));
    if (select message from notifications where kind = 'order_withdrawn' and (params ->> 'order_id')::uuid = v_prop)
       <> 'Cliente Cent-Trente-Quatre a annulé sa demande' then
        raise exception 'FAIL: declining a proposal';
    end if;
    -- An order with no slot has no terms.
    if pg_temp.do134('13413413-0000-0000-0000-000000000004',
           format('select coalesce(booking_cancel_terms(%L)::text, ''null'')', v_acc)) <> 'null' then
        raise exception 'FAIL: terms for an order of goods';
    end if;
    raise notice 'PASS: goods pending only and « a annulé sa commande »; a proposal declined at any time, « a annulé sa demande »; no terms without a slot';
end $$;

\echo ''
\echo '--- TEST 13: the week''s close — the prizes, and the bell only with cauris_prize_notify ---'
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled, city) values
    ('13400000-0000-0000-0000-0000000000c1', 'Premier 134', 'premier-134', 'retail', 'XOF', true, 'Ville 134'),
    ('13400000-0000-0000-0000-0000000000c2', 'Second 134',  'second-134',  'retail', 'XOF', true, 'Ville 134');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    ('13400000-0000-0000-0000-0000000000c1', '13413413-0000-0000-0000-000000000006', 'owner', 'org', '13400000-0000-0000-0000-0000000000c1', 'full'),
    ('13400000-0000-0000-0000-0000000000c2', '13413413-0000-0000-0000-000000000007', 'owner', 'org', '13400000-0000-0000-0000-0000000000c2', 'full');
-- Two weeks long ago, nobody else's: the one rang off, the other on.
insert into cauris_ledger (org_id, delta, reason, ref, created_at) values
    ('13400000-0000-0000-0000-0000000000c1', 300, 'order_done', 't134-a1', '2020-01-08 12:00+00'),
    ('13400000-0000-0000-0000-0000000000c2', 100, 'order_done', 't134-b1', '2020-01-08 12:00+00'),
    ('13400000-0000-0000-0000-0000000000c1', 300, 'order_done', 't134-a2', '2020-01-15 12:00+00'),
    ('13400000-0000-0000-0000-0000000000c2', 100, 'order_done', 't134-b2', '2020-01-15 12:00+00');
do $$
declare v_n int;
begin
    if cauris_param('cauris_prize_notify', -1) <> 0 then
        raise exception 'FAIL: cauris_prize_notify is not installed at 0';
    end if;
    v_n := cauris_week_close('2020-01-06');
    -- (The balance itself is no measure here: 2020's cauris expired long
    -- ago — the prize is its own ledger row.)
    if v_n < 2 or not exists (select 1 from cauris_ledger where reason = 'prize' and ref = '2020-01-06'
                               and org_id = '13400000-0000-0000-0000-0000000000c1' and delta > 0)
       or not exists (select 1 from cauris_week_results where week_start = '2020-01-06'
                       and org_id = '13400000-0000-0000-0000-0000000000c1' and rank = 1)
       or not exists (select 1 from promotions where org_id = '13400000-0000-0000-0000-0000000000c1'
                       and note = 'Premier de la semaine (cauris)') then
        raise exception 'FAIL: the prizes were not awarded with the bell off';
    end if;
    if exists (select 1 from notifications where kind = 'cauris_prize'
                and org_id in ('13400000-0000-0000-0000-0000000000c1', '13400000-0000-0000-0000-0000000000c2')) then
        raise exception 'FAIL: a prize rang with cauris_prize_notify at 0';
    end if;
    -- 0 or 1 only.
    begin
        update platform_settings set value = '2' where key = 'cauris_prize_notify';
        raise exception 'FAIL: cauris_prize_notify took 2';
    exception when others then
        if sqlerrm not like 'Ce réglage vaut 0 (non) ou 1 (oui).%' then raise; end if;
    end;
    update platform_settings set value = '1' where key = 'cauris_prize_notify';
    perform cauris_week_close('2020-01-13');
    if (select count(*) from notifications where kind = 'cauris_prize'
         and org_id in ('13400000-0000-0000-0000-0000000000c1', '13400000-0000-0000-0000-0000000000c2')) <> 2 then
        raise exception 'FAIL: with cauris_prize_notify at 1 the winners were not rung';
    end if;
    update platform_settings set value = '0' where key = 'cauris_prize_notify';
    raise notice 'PASS: at 0 the cauris, the result and the spot, no bell (so no push); at 1 the bells; 0 or 1 only';
end $$;

\echo ''
\echo '--- TEST 14: RLS and grants ---'
do $$
declare f text; t text;
begin
    foreach t in array array['books_opening', 'contribution_defaults', 'books_start_dismissals'] loop
        if not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass) then
            raise exception 'FAIL: % has no row security', t;
        end if;
        if has_table_privilege('anon', 'public.' || t, 'select')
           or has_table_privilege('anon', 'public.' || t, 'insert') then
            raise exception 'FAIL: anon reaches %', t;
        end if;
    end loop;
    if (select count(*) from pg_policy where polrelid = 'books_opening'::regclass and polcmd = 'd') <> 0 then
        raise exception 'FAIL: an opening can be deleted';
    end if;
    -- The INVOKER doors, as record_contribution.
    foreach f in array array['set_opening_balance(uuid,numeric,text,uuid)',
                             'set_contribution_default(uuid,numeric,text)', 'dismiss_books_start(uuid)'] loop
        if (select prosecdef from pg_proc where oid = f::regprocedure) then
            raise exception 'FAIL: % is a definer', f;
        end if;
    end loop;
    -- The definers: path pinned.
    foreach f in array array['books_start(uuid)', 'cancel_order(uuid)', 'booking_cancel_terms(uuid)',
                             'booking_cancel_hours()', 'trg_books_opening_guard()',
                             'trg_contribution_default_guard()', 'cauris_week_close(date)'] loop
        if not (select prosecdef from pg_proc where oid = f::regprocedure)
           or not exists (select 1 from pg_proc p, unnest(p.proconfig) c
                           where p.oid = f::regprocedure and c like 'search_path=%') then
            raise exception 'FAIL: % is not a definer with its path pinned', f;
        end if;
    end loop;
    foreach f in array array['set_opening_balance(uuid,numeric,text,uuid)',
                             'set_contribution_default(uuid,numeric,text)', 'dismiss_books_start(uuid)',
                             'books_start(uuid)', 'cancel_order(uuid)', 'booking_cancel_terms(uuid)',
                             'booking_cancel_hours()', 'trg_books_opening_guard()',
                             'trg_contribution_default_guard()', 'trg_settings_134()',
                             'cauris_week_close(date)'] loop
        if has_function_privilege('anon', f, 'execute') then
            raise exception 'FAIL: anon may call %', f;
        end if;
    end loop;
    foreach f in array array['set_opening_balance(uuid,numeric,text,uuid)',
                             'set_contribution_default(uuid,numeric,text)', 'dismiss_books_start(uuid)',
                             'books_start(uuid)', 'cancel_order(uuid)', 'booking_cancel_terms(uuid)'] loop
        if not has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: the app cannot call %', f;
        end if;
    end loop;
    foreach f in array array['booking_cancel_hours()', 'trg_books_opening_guard()',
                             'trg_contribution_default_guard()', 'trg_settings_134()',
                             'cauris_week_close(date)'] loop
        if has_function_privilege('authenticated', f, 'execute') then
            raise exception 'FAIL: the app may call the internal %', f;
        end if;
    end loop;
    raise notice 'PASS: three tables with row security, no delete of an opening, nothing for anon; the doors invoker, the definers pinned, the internals nobody''s';
end $$;

\echo ''
\echo '--- TEST 16 (review): the trust level does not move; a reversed opening is offered again ---'
insert into orgs (id, name, slug, profile, default_currency) values
    ('13400000-0000-0000-0000-000000000007', 'Confiance 134', 'confiance-134', 'association', 'XOF'),
    ('13400000-0000-0000-0000-000000000008', 'Codes 134',     'codes-134',     'association', 'XOF'),
    -- Confiance's twin: the same books, never an opening.
    ('13400000-0000-0000-0000-000000000009', 'Jumelle 134',   'jumelle-134',   'association', 'XOF');
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    ('13400000-0000-0000-0000-000000000007', '13413413-0000-0000-0000-000000000001', 'owner',    'org', '13400000-0000-0000-0000-000000000007', 'full'),
    ('13400000-0000-0000-0000-000000000007', '13413413-0000-0000-0000-000000000002', 'employee', 'org', '13400000-0000-0000-0000-000000000007', 'full'),
    ('13400000-0000-0000-0000-000000000008', '13413413-0000-0000-0000-000000000001', 'owner',    'org', '13400000-0000-0000-0000-000000000008', 'full'),
    ('13400000-0000-0000-0000-000000000009', '13413413-0000-0000-0000-000000000001', 'owner',    'org', '13400000-0000-0000-0000-000000000009', 'full'),
    ('13400000-0000-0000-0000-000000000009', '13413413-0000-0000-0000-000000000002', 'employee', 'org', '13400000-0000-0000-0000-000000000009', 'full');
select seed_church_accounts('13400000-0000-0000-0000-000000000007');
select seed_church_accounts('13400000-0000-0000-0000-000000000008');
select seed_church_accounts('13400000-0000-0000-0000-000000000009');
create or replace function pg_temp.pillars134(p_org uuid)
returns text
language sql
as $$
    select string_agg((e ->> 'key') || '=' || coalesce(e ->> 'value', '') || '/' || coalesce(e ->> 'of', ''), ' ' order by e ->> 'key')
      from jsonb_array_elements(
          pg_temp.do134('13413413-0000-0000-0000-000000000001',
                        format('select association_trust(%L)::text', p_org))::jsonb -> 'pillars') e;
$$;
do $$
declare
    v_org  uuid := '13400000-0000-0000-0000-000000000007';
    v_twin uuid := '13400000-0000-0000-0000-000000000009';
    v_first uuid; r jsonb; v text; o uuid;
begin
    r := pg_temp.do134('13413413-0000-0000-0000-000000000001',
        format('select set_opening_balance(%L, 40000)::text', v_org))::jsonb;
    v_first := (r ->> 'entry_id')::uuid;
    -- Then the same two cotisations in both: books being kept.
    foreach o in array array[v_org, v_twin] loop
        perform pg_temp.do134('13413413-0000-0000-0000-000000000002',
            format('select record_entry(%L, 1000, ''in'', ''Cotisation'', null, ''Cotisations'')::text', o));
        perform pg_temp.do134('13413413-0000-0000-0000-000000000002',
            format('select record_entry(%L, 1500, ''in'', ''Cotisation'', null, ''Cotisations'')::text', o));
    end loop;
    if pg_temp.pillars134(v_org) <> pg_temp.pillars134(v_twin) then
        raise exception 'FAIL: the opening moved the trust level: % against %', pg_temp.pillars134(v_org), pg_temp.pillars134(v_twin);
    end if;
    -- Reversed (the correction path): no mistake counted, and offered again.
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001',
        format('select reverse_entry(%L, %L, %L)::text', v_first, '13413413-0000-0000-0000-000000000001', 'Correction'));
    if pg_temp.pillars134(v_org) <> pg_temp.pillars134(v_twin) then
        raise exception 'FAIL: the reversed opening moved the trust level: %', pg_temp.pillars134(v_org);
    end if;
    r := pg_temp.do134('13413413-0000-0000-0000-000000000001',
        format('select books_start(%L)::text', v_org))::jsonb;
    if not (r ->> 'can_set')::boolean or (r ->> 'opening_set')::boolean or not (r ->> 'movements')::boolean then
        raise exception 'FAIL: a reversed opening is not offered again: %', r;
    end if;
    r := pg_temp.do134('13413413-0000-0000-0000-000000000002',
        format('select books_start(%L)::text', v_org))::jsonb;
    if (r ->> 'can_set')::boolean then
        raise exception 'FAIL: an employee offered the correction: %', r;
    end if;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001',
        format('select set_opening_balance(%L, 45000)::text', v_org));
    r := pg_temp.do134('13413413-0000-0000-0000-000000000001',
        format('select books_start(%L)::text', v_org))::jsonb;
    if (r ->> 'can_set')::boolean or not (r ->> 'opening_set')::boolean
       or (r ->> 'opening_amount')::numeric <> 45000 then
        raise exception 'FAIL: after the correction: %', r;
    end if;
    if pg_temp.pillars134(v_org) <> pg_temp.pillars134(v_twin)
       or (select replaced_entry_ids from books_opening where org_id = v_org) <> array[v_first] then
        raise exception 'FAIL: the corrected opening moved the trust level, or lost its history: %',
            pg_temp.pillars134(v_org);
    end if;
    -- The income statement: the two cotisations, nothing of the opening.
    perform set_config('request.jwt.claim.sub', '13413413-0000-0000-0000-000000000001', true);
    set local role authenticated;
    if (select amount from income_statement(v_org) where section = 'total' and name = 'Résultat') <> 2500 then
        raise exception 'FAIL: the result moved with the opening';
    end if;
    reset role;
    -- The history is the guard's to write, not the caller's.
    v := pg_temp.try134('13413413-0000-0000-0000-000000000001',
        format('update books_opening set replaced_entry_ids = ''{}'' where org_id = %L', v_org));
    if v not like 'Le solde de départ est déjà enregistré.%' then
        raise exception 'FAIL: the history rewritten: %', v;
    end if;
    -- An entry that only CALLS itself an opening (record_entry takes any
    -- details) is counted as any other.
    perform pg_temp.do134('13413413-0000-0000-0000-000000000002',
        format('select record_entry(%L, 700, ''in'', ''Cotisation'', null, ''Cotisations'', ''cash'', null, null, ''{"kind": "opening_balance"}'')::text', v_org));
    if pg_temp.pillars134(v_org) = pg_temp.pillars134(v_twin) then
        raise exception 'FAIL: a forged « opening » was left out of the trust level';
    end if;
    raise notice 'PASS: opening, reversal and correction leave « Régulière » and « Propre » as its twin''s (%); a reversed opening offered again to an administrator; a forged one counted', pg_temp.pillars134(v_twin);
end $$;

\echo ''
\echo '--- TEST 17 (review): a « Solde de départ » beside codes that are not numbers ---'
do $$
declare v_org uuid := '13400000-0000-0000-0000-000000000008'; r jsonb;
begin
    insert into accounts (org_id, code, name, type) values
        (v_org, 'CAISSE-A', 'Caisse annexe', 'asset'),
        (v_org, '3000', 'Capital', 'equity');
    r := pg_temp.do134('13413413-0000-0000-0000-000000000001',
        format('select set_opening_balance(%L, 5000)::text', v_org))::jsonb;
    if (select a.code from journal_lines jl join accounts a on a.id = jl.account_id
         where jl.journal_entry_id = (r ->> 'entry_id')::uuid and jl.credit > 0) <> '3010' then
        raise exception 'FAIL: the equity account''s code';
    end if;
    raise notice 'PASS: 3010 beside « CAISSE-A » and a 3000 of its own';
end $$;

\echo ''
\echo '--- TEST 18 (review): every paid path refused; a Wave payment under way; a request whose time passed ---'
do $$
declare v_paid uuid; v_goods uuid; v_wave uuid; v_stale uuid; v_late uuid; v text; r jsonb;
begin
    -- Marked paid by the business (a deposit in cash): refused, as online.
    v_paid := pg_temp.do134('13413413-0000-0000-0000-000000000004',
        pg_temp.book134('entraide-134', '134aaaaa-0000-0000-0000-000000000002', pg_temp.slot134(6, '10:00')))::uuid;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001', format('select decide_order(%L, ''accepted'')::text', v_paid));
    perform pg_temp.do134('13413413-0000-0000-0000-000000000001', format('select set_order_paid(%L, true)::text', v_paid));
    v := pg_temp.try134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)', v_paid));
    if v <> 'Ce rendez-vous est déjà payé : appelez la boutique pour l''annuler.' then
        raise exception 'FAIL: a booking the business marked paid: %', v;
    end if;
    r := pg_temp.do134('13413413-0000-0000-0000-000000000004', format('select booking_cancel_terms(%L)::text', v_paid))::jsonb;
    if (r ->> 'can_cancel')::boolean or not (r ->> 'paid_online')::boolean then
        raise exception 'FAIL: the terms of a booking marked paid: %', r;
    end if;
    -- An order of goods paid online while pending (wave_begin allows it).
    insert into orders (org_id, customer_id, customer_name, status, total)
    values ('13400000-0000-0000-0000-000000000004', '13413413-0000-0000-0000-000000000004', 'Cliente Cent-Trente-Quatre',
            'pending', 500)
    returning id into v_goods;
    insert into order_lines (order_id, product_id, name, unit_price, quantity, is_service)
    values (v_goods, '134aaaaa-0000-0000-0000-000000000001', 'Savon 134', 500, 1, false);
    update orders set payment_method = 'wave', paid_at = now() where id = v_goods;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)', v_goods));
    if v <> 'Cette commande est déjà payée : appelez la boutique pour l''annuler.' then
        raise exception 'FAIL: a paid order of goods withdrawn: %', v;
    end if;
    -- A Wave payment opened ten minutes ago: it may still land.
    v_wave := pg_temp.do134('13413413-0000-0000-0000-000000000004',
        pg_temp.book134('boutique-134', '134aaaaa-0000-0000-0000-000000000003', pg_temp.slot134(6, '11:00')))::uuid;
    -- (Written as Wave's Worker would, past 090's « Wave allowed » gate.)
    set local session_replication_role = replica;
    insert into wave_payments (kind, org_id, order_id, payer_id, amount, status, created_at)
    values ('order', '13400000-0000-0000-0000-000000000004', v_wave, '13413413-0000-0000-0000-000000000004',
            3000, 'open', now() - interval '10 minutes');
    set local session_replication_role = origin;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)', v_wave));
    if v <> 'Un paiement Wave est en cours : attendez quelques minutes ou appelez la boutique.' then
        raise exception 'FAIL: cancelled under a Wave payment: %', v;
    end if;
    update wave_payments set created_at = now() - interval '31 minutes' where order_id = v_wave;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)::text', v_wave));
    if (select status from orders where id = v_wave) <> 'cancelled' then
        raise exception 'FAIL: a Wave payment abandoned half an hour ago still holds the booking';
    end if;
    -- A request nobody answered whose hour has gone: withdrawn (it can no
    -- longer be accepted); a confirmed one whose hour has gone: refused.
    v_stale := pg_temp.do134('13413413-0000-0000-0000-000000000004',
        pg_temp.book134('ferme-134', '134aaaaa-0000-0000-0000-000000000004', pg_temp.slot134(6, '15:00')))::uuid;
    v_late := pg_temp.do134('13413413-0000-0000-0000-000000000004',
        pg_temp.book134('ferme-134', '134aaaaa-0000-0000-0000-000000000004', pg_temp.slot134(6, '16:00')))::uuid;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000007', format('select decide_order(%L, ''accepted'')::text', v_late));
    update orders set booked_for = now() - interval '1 hour' where id in (v_stale, v_late);
    r := pg_temp.do134('13413413-0000-0000-0000-000000000004', format('select booking_cancel_terms(%L)::text', v_stale))::jsonb;
    if not (r ->> 'can_cancel')::boolean then
        raise exception 'FAIL: the terms of a request whose hour has gone: %', r;
    end if;
    perform pg_temp.do134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)::text', v_stale));
    if (select status from orders where id = v_stale) <> 'cancelled' then
        raise exception 'FAIL: a request whose hour has gone stays stuck';
    end if;
    v := pg_temp.try134('13413413-0000-0000-0000-000000000004', format('select cancel_order(%L)', v_late));
    if v <> 'Trop tard pour annuler : appelez la boutique.' then
        raise exception 'FAIL: a confirmed booking whose hour has gone: %', v;
    end if;
    raise notice 'PASS: paid by the business or online, booking or goods, refused; a Wave payment under way holds it 30 minutes; a dead request withdrawn, a past confirmed one refused';
end $$;

\echo ''
\echo '--- TEST 19 (review): the tables give the app what its doors use, nothing more ---'
do $$
declare t text; p text;
begin
    foreach t in array array['books_opening', 'contribution_defaults', 'books_start_dismissals'] loop
        foreach p in array array['references', 'trigger', 'truncate'] loop
            if has_table_privilege('authenticated', 'public.' || t, p) then
                raise exception 'FAIL: the app has % on %', p, t;
            end if;
        end loop;
    end loop;
    if has_table_privilege('authenticated', 'books_opening', 'delete')
       or has_table_privilege('authenticated', 'books_start_dismissals', 'delete')
       or has_table_privilege('authenticated', 'books_start_dismissals', 'update')
       or not has_table_privilege('authenticated', 'contribution_defaults', 'delete')
       or not has_table_privilege('authenticated', 'books_opening', 'update') then
        raise exception 'FAIL: the app''s rights on the three tables';
    end if;
    raise notice 'PASS: select/insert/update on the opening, + delete on the cotisation, select/insert on the card; no delete, references, trigger or truncate beyond';
end $$;

\echo ''
\echo '--- TEST 15: run twice, 134 changes nothing ---'
create temp table b134_seen as
    select 'opening ' || org_id as k, to_jsonb(b) - 'set_at' as v from books_opening b
    union all select 'setting ' || key, value from platform_settings where key in ('booking_cancel_hours', 'cauris_prize_notify');
\i database/migrations/134_caisse_booking_cancel.sql
revoke execute on function booking_cancel_hours() from authenticated;
do $$ begin
    if exists (
        (select 'opening ' || org_id as k, to_jsonb(b) - 'set_at' as v from books_opening b
         union all select 'setting ' || key, value from platform_settings where key in ('booking_cancel_hours', 'cauris_prize_notify'))
        except select k, v from b134_seen) then
        raise exception 'FAIL: 134 again changed something';
    end if;
    raise notice 'PASS: run twice, the same';
end $$;

revoke usage on schema auth from authenticated;
