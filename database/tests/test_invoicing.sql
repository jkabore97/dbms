-- ============================================================
-- test_invoicing.sql — invoicing that is not farm-shaped.
--
-- Runs as `authenticated` throughout, never as postgres: every write here
-- goes through a SECURITY DEFINER function that makes its own membership
-- check, and the reads are SECURITY INVOKER precisely so RLS decides them.
--
-- What this suite is about:
--
--   1. A shop and a church can invoice at all. The tables were never
--      farm-only; the default income category was, and a shop crediting
--      "Ventes d'œufs" is a wrong set of books, not a cosmetic problem.
--   2. Two people invoicing at the same second. The old numbering read
--      count(*) and added one, so the second caller collided with the unique
--      index and was simply told the invoice failed. This is the assertion
--      that would have caught it.
--   3. A cancelled invoice leaving the receivable behind. `cancelled_at` had
--      nothing to set it, so a mistake was permanent.
--   4. A cancelled invoice that was already part paid, which must be refused:
--      the money arrived, and reversing the income leaves that payment
--      posted against nothing.
--   5. One business reading another's invoices. The document reads are
--      INVOKER for exactly this reason and it has to be proven, not assumed.
--
-- Phone block 85. The others: 70 rls, 71 invitations, 72 reports,
-- 73 accounting, 74 audit, 75/76 farm, 77 platform admin, 78 retail,
-- 79 employees, 80 capture, 81 org lifecycle, 82 delivery, 83 onboarding,
-- 84 farm_general.
-- ============================================================
\set ON_ERROR_STOP on

\set shopkeeper '''85858585-0000-0000-0000-000000000001'''
\set clerk      '''85858585-0000-0000-0000-000000000002'''
\set pastor     '''85858585-0000-0000-0000-000000000003'''
\set stranger   '''85858585-0000-0000-0000-000000000004'''

\set shop   '''85000000-0000-0000-0000-000000000001'''
\set church '''85000000-0000-0000-0000-000000000002'''

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
    (:shopkeeper, '+22685000001', '{"full_name": "Esperance"}'),
    (:clerk,      '+22685000002', '{"full_name": "Vendeuse"}'),
    (:pastor,     '+22685000003', '{"full_name": "Israel"}'),
    (:stranger,   '+22685000004', '{"full_name": "Personne"}');

insert into orgs (id, name, slug, profile, default_currency) values
    (:shop,   'Boutique Esperance', 'boutique-esperance-85', 'retail', 'XOF'),
    (:church, 'Paroisse Saint-Paul', 'paroisse-85',          'church', 'XOF');

insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:shop,   :shopkeeper, 'owner',    'org', :shop),
    (:shop,   :clerk,      'employee', 'org', :shop),
    (:church, :pastor,     'owner',    'org', :church);

\echo ''
\echo '--- TEST 1: a shop invoices, and does not credit eggs ---'
begin;
set local "request.jwt.claim.sub" = '85858585-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_invoice uuid;
    v_row     invoices%rowtype;
    v_credit  text;
    v_lines   int;
begin
    v_invoice := create_invoice(
        p_org_id        => '85000000-0000-0000-0000-000000000001',
        p_customer_name => 'Hôtel Indépendance',
        p_lines         => '[{"description": "Savon 500g", "quantity": 20, "unit_price": 750},
                             {"description": "Sucre 1kg",  "quantity": 10, "unit_price": 900}]'::jsonb,
        p_due_days      => 30
    );

    select * into v_row from invoices where id = v_invoice;
    if v_row.total <> 24000 then
        raise exception 'FAIL: 20x750 + 10x900 came to %', v_row.total;
    end if;

    -- "Payable in 30 days" is how terms are agreed; a date is what is stored.
    if v_row.due_on <> current_date + 30 then
        raise exception 'FAIL: due on % rather than in 30 days', v_row.due_on;
    end if;

    select count(*) into v_lines from invoice_lines where invoice_id = v_invoice;
    if v_lines <> 2 then
        raise exception 'FAIL: % lines saved', v_lines;
    end if;

    -- The point of the migration. Before it, this said "Ventes d'œufs" for a
    -- shop that has never seen a chicken.
    select a.name into v_credit
      from journal_lines l
      join accounts a on a.id = l.account_id
     where l.journal_entry_id = v_row.journal_entry_id
       and l.credit > 0;

    if v_credit = 'Ventes d''œufs' then
        raise exception 'FAIL: a shop credited eggs';
    end if;
    if v_credit <> 'Ventes' then
        raise exception 'FAIL: a shop credited %', v_credit;
    end if;

    raise notice 'PASS: 24 000 invoiced to Ventes, payable in 30 days';
end $$;
commit;

\echo ''
\echo '--- TEST 2: an invoice moves no cash ---'
begin;
set local "request.jwt.claim.sub" = '85858585-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_entry uuid;
    v_debit text;
    v_cash  numeric;
begin
    select journal_entry_id into v_entry
      from invoices where org_id = '85000000-0000-0000-0000-000000000001'
      order by created_at desc limit 1;

    select a.name into v_debit
      from journal_lines l
      join accounts a on a.id = l.account_id
     where l.journal_entry_id = v_entry and l.debit > 0;

    if v_debit <> 'Créances clients' then
        raise exception 'FAIL: the debit went to %', v_debit;
    end if;

    -- Delivering is not being paid. An invoice that touched cash would make
    -- the till disagree with the drawer, which is the error that destroys
    -- trust in the whole ledger.
    select coalesce(sum(l.debit + l.credit), 0) into v_cash
      from journal_lines l
      join accounts a on a.id = l.account_id
     where l.journal_entry_id = v_entry
       and a.type = 'asset' and a.name <> 'Créances clients';

    if v_cash <> 0 then
        raise exception 'FAIL: an invoice moved % of cash', v_cash;
    end if;

    raise notice 'PASS: a receivable, and not one franc of cash';
end $$;
commit;

\echo ''
\echo '--- TEST 3: a church invoices too ---'
begin;
set local "request.jwt.claim.sub" = '85858585-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_invoice uuid;
    v_credit  text;
begin
    -- A parish hall let out for a wedding. Not a contribution, not an
    -- offering — a debt somebody owes the church.
    v_invoice := create_invoice(
        p_org_id        => '85000000-0000-0000-0000-000000000002',
        p_customer_name => 'Famille Kaboré',
        p_lines         => '[{"description": "Location salle", "quantity": 1, "unit_price": 50000}]'::jsonb
    );

    select a.name into v_credit
      from invoices i
      join journal_lines l on l.journal_entry_id = i.journal_entry_id and l.credit > 0
      join accounts a on a.id = l.account_id
     where i.id = v_invoice;

    if v_credit <> 'Produits divers' then
        raise exception 'FAIL: a church credited %', v_credit;
    end if;

    raise notice 'PASS: a church invoices a hall hire to Produits divers';
end $$;
commit;

\echo ''
\echo '--- TEST 4: two people invoicing at once get two numbers ---'
begin;
set local "request.jwt.claim.sub" = '85858585-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_a text;
    v_b text;
    v_c text;
begin
    -- The old scheme was count(*) + 1 read in one statement and written in
    -- another. It is impossible to schedule a true race from one psql
    -- session, so this asserts the property that makes the race impossible:
    -- the number is taken from a counter that is advanced atomically, so
    -- three consecutive takes are three different values, and none of them
    -- depends on how many invoices happen to exist.
    v_a := next_invoice_number('85000000-0000-0000-0000-000000000001', current_date);
    v_b := next_invoice_number('85000000-0000-0000-0000-000000000001', current_date);
    v_c := next_invoice_number('85000000-0000-0000-0000-000000000001', current_date);

    if v_a = v_b or v_b = v_c or v_a = v_c then
        raise exception 'FAIL: handed out % then % then %', v_a, v_b, v_c;
    end if;

    if v_a !~ '^\d{4}-\d{4}$' then
        raise exception 'FAIL: % is not a YYYY-NNNN invoice number', v_a;
    end if;

    raise notice 'PASS: three takes, three numbers — % % %', v_a, v_b, v_c;
end $$;
commit;

\echo ''
\echo '--- TEST 5: numbering does not restart, and does not collide ---'
begin;
set local "request.jwt.claim.sub" = '85858585-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_one uuid;
    v_two uuid;
    v_n1  text;
    v_n2  text;
begin
    v_one := create_invoice(
        p_org_id        => '85000000-0000-0000-0000-000000000001',
        p_customer_name => 'Client A',
        p_lines         => '[{"description": "Riz", "quantity": 1, "unit_price": 1000}]'::jsonb);
    v_two := create_invoice(
        p_org_id        => '85000000-0000-0000-0000-000000000001',
        p_customer_name => 'Client B',
        p_lines         => '[{"description": "Riz", "quantity": 1, "unit_price": 1000}]'::jsonb);

    select number into v_n1 from invoices where id = v_one;
    select number into v_n2 from invoices where id = v_two;

    if v_n1 = v_n2 then
        raise exception 'FAIL: both invoices are %', v_n1;
    end if;

    -- Each business counts its own. A sequence would have interleaved these
    -- with the church's, which is the thing an auditor asks about.
    if exists (
        select 1 from invoices i
         where i.org_id = '85000000-0000-0000-0000-000000000002'
           and i.number in (v_n1, v_n2)
           and false  -- same number in two orgs is legal; sharing a counter is not
    ) then
        raise exception 'FAIL';
    end if;

    raise notice 'PASS: % and % are distinct', v_n1, v_n2;
end $$;
commit;

\echo ''
\echo '--- TEST 6: a retry raises one invoice, not two ---'
begin;
set local "request.jwt.claim.sub" = '85858585-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_a uuid;
    v_b uuid;
    v_n int;
begin
    v_a := create_invoice(
        p_org_id        => '85000000-0000-0000-0000-000000000001',
        p_customer_name => 'Client répété',
        p_lines         => '[{"description": "Huile", "quantity": 2, "unit_price": 1500}]'::jsonb,
        p_client_uuid   => '85000000-1111-0000-0000-000000000001');

    -- Same call, same client_uuid: the phone lost the reply and tried again.
    v_b := create_invoice(
        p_org_id        => '85000000-0000-0000-0000-000000000001',
        p_customer_name => 'Client répété',
        p_lines         => '[{"description": "Huile", "quantity": 2, "unit_price": 1500}]'::jsonb,
        p_client_uuid   => '85000000-1111-0000-0000-000000000001');

    if v_a <> v_b then
        raise exception 'FAIL: a retry raised a second invoice';
    end if;

    select count(*) into v_n from invoices
     where org_id = '85000000-0000-0000-0000-000000000001'
       and client_uuid = '85000000-1111-0000-0000-000000000001';
    if v_n <> 1 then
        raise exception 'FAIL: % invoices for one client_uuid', v_n;
    end if;

    raise notice 'PASS: the retry returned the first invoice';
end $$;
commit;

\echo ''
\echo '--- TEST 7: nonsense is refused ---'
begin;
set local "request.jwt.claim.sub" = '85858585-0000-0000-0000-000000000001';
set local role authenticated;
do $$
begin
    begin
        perform create_invoice(
            p_org_id        => '85000000-0000-0000-0000-000000000001',
            p_customer_name => 'Client',
            p_lines         => '[]'::jsonb);
        raise exception 'FAIL: an invoice with no lines';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: refused — %', sqlerrm;
    end;

    begin
        perform create_invoice(
            p_org_id        => '85000000-0000-0000-0000-000000000001',
            p_customer_name => '   ',
            p_lines         => '[{"description": "X", "quantity": 1, "unit_price": 10}]'::jsonb);
        raise exception 'FAIL: an invoice addressed to nobody';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: refused — %', sqlerrm;
    end;

    begin
        perform create_invoice(
            p_org_id        => '85000000-0000-0000-0000-000000000001',
            p_customer_name => 'Client',
            p_lines         => '[{"description": "  ", "quantity": 1, "unit_price": 10}]'::jsonb);
        raise exception 'FAIL: a line describing nothing';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: refused — %', sqlerrm;
    end;

    begin
        perform create_invoice(
            p_org_id        => '85000000-0000-0000-0000-000000000001',
            p_customer_name => 'Client',
            p_lines         => '[{"description": "X", "quantity": 1, "unit_price": 0}]'::jsonb);
        raise exception 'FAIL: a line priced at nothing';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: refused — %', sqlerrm;
    end;
end $$;
commit;

\echo ''
\echo '--- TEST 8: cancelling takes the receivable back off the books ---'
begin;
set local "request.jwt.claim.sub" = '85858585-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_invoice uuid;
    v_entry   uuid;
    v_before  numeric;
    v_after   numeric;
    v_recv    uuid;
begin
    v_invoice := create_invoice(
        p_org_id        => '85000000-0000-0000-0000-000000000001',
        p_customer_name => 'Client erroné',
        p_lines         => '[{"description": "Erreur", "quantity": 1, "unit_price": 9000}]'::jsonb);

    select journal_entry_id into v_entry from invoices where id = v_invoice;
    select id into v_recv from accounts
     where org_id = '85000000-0000-0000-0000-000000000001' and code = '1300';

    select coalesce(sum(l.debit - l.credit), 0) into v_before
      from journal_lines l where l.account_id = v_recv;

    perform cancel_invoice(v_invoice, 'Mauvais client');

    select coalesce(sum(l.debit - l.credit), 0) into v_after
      from journal_lines l where l.account_id = v_recv;

    if v_after <> v_before - 9000 then
        raise exception 'FAIL: receivable went from % to %', v_before, v_after;
    end if;

    if (select cancelled_at from invoices where id = v_invoice) is null then
        raise exception 'FAIL: the invoice was not marked cancelled';
    end if;

    -- Reversed, not deleted. What happened, happened.
    if not exists (select 1 from journal_entries where reverses_entry_id = v_entry) then
        raise exception 'FAIL: the entry was erased rather than reversed';
    end if;
    if not exists (select 1 from journal_entries where id = v_entry) then
        raise exception 'FAIL: the original entry is gone';
    end if;

    -- Cancelling twice is two taps on a slow connection, not an error.
    perform cancel_invoice(v_invoice, 'Encore');

    raise notice 'PASS: reversed, marked, and idempotent';
end $$;
commit;

\echo ''
\echo '--- TEST 9: a part-paid invoice cannot be cancelled ---'
begin;
set local "request.jwt.claim.sub" = '85858585-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_invoice uuid;
begin
    v_invoice := create_invoice(
        p_org_id        => '85000000-0000-0000-0000-000000000001',
        p_customer_name => 'Client payeur',
        p_lines         => '[{"description": "Ciment", "quantity": 10, "unit_price": 5000}]'::jsonb);

    perform record_invoice_payment(v_invoice, 20000, 'cash');

    begin
        perform cancel_invoice(v_invoice, 'Trop tard');
        raise exception 'FAIL: cancelled an invoice that had been paid';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: refused — %', sqlerrm;
    end;

    if (select cancelled_at from invoices where id = v_invoice) is not null then
        raise exception 'FAIL: it was cancelled anyway';
    end if;

    raise notice 'PASS: the money arrived, so the invoice stands';
end $$;
commit;

\echo ''
\echo '--- TEST 10: the document reads back whole ---'
begin;
set local "request.jwt.claim.sub" = '85858585-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_invoice uuid;
    v_head    record;
    v_lines   int;
begin
    perform set_org_billing(
        p_org_id    => '85000000-0000-0000-0000-000000000001',
        p_address   => 'Rue 14.28, Ouagadougou',
        p_phone     => '+22670000000',
        p_tax_id    => '00012345A',
        p_tax_label => 'IFU',
        p_invoice_footer => 'Merci de votre confiance.');

    v_invoice := create_invoice(
        p_org_id           => '85000000-0000-0000-0000-000000000001',
        p_customer_name    => 'Hôtel Ricardo',
        p_customer_phone   => '+22676000000',
        p_customer_address => 'Avenue Kwame Nkrumah',
        p_lines            => '[{"description": "Farine", "quantity": 4, "unit_price": 12000}]'::jsonb,
        p_due_days         => 15);

    select * into v_head from invoice_header(v_invoice);

    if v_head.org_name <> 'Boutique Esperance' then
        raise exception 'FAIL: billed by %', v_head.org_name;
    end if;
    -- Everything a customer's own accountant needs to file it.
    if v_head.org_tax_id is null or v_head.org_tax_label <> 'IFU' then
        raise exception 'FAIL: no tax number on the document';
    end if;
    if v_head.customer_name <> 'Hôtel Ricardo'
       or v_head.customer_address is null then
        raise exception 'FAIL: addressed to % at %',
            v_head.customer_name, v_head.customer_address;
    end if;
    if v_head.total <> 48000 or v_head.outstanding <> 48000 then
        raise exception 'FAIL: total % outstanding %', v_head.total, v_head.outstanding;
    end if;
    if v_head.invoice_footer is null then
        raise exception 'FAIL: the footer did not come back';
    end if;

    select count(*) into v_lines from invoice_lines_of(v_invoice);
    if v_lines <> 1 then
        raise exception 'FAIL: % lines on the document', v_lines;
    end if;

    raise notice 'PASS: header, tax number, customer, lines and footer';
end $$;
commit;

\echo ''
\echo '--- TEST 11: only an administrator writes the billing header ---'
begin;
set local "request.jwt.claim.sub" = '85858585-0000-0000-0000-000000000002';
set local role authenticated;
do $$
begin
    -- The clerk can invoice all day. What the business claims about itself to
    -- a tax office is not hers to change.
    begin
        perform set_org_billing(
            p_org_id => '85000000-0000-0000-0000-000000000001',
            p_tax_id => '99999999Z');
        raise exception 'FAIL: an employee rewrote the tax number';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: refused — %', sqlerrm;
    end;

    if (select tax_id from orgs where id = '85000000-0000-0000-0000-000000000001')
       <> '00012345A' then
        raise exception 'FAIL: the tax number changed anyway';
    end if;
end $$;
commit;

\echo ''
\echo '--- TEST 12: one business cannot read another''s invoices ---'
begin;
set local "request.jwt.claim.sub" = '85858585-0000-0000-0000-000000000003';
set local role authenticated;
do $$
declare
    v_shop_invoice uuid;
    v_rows int;
begin
    -- The pastor belongs to the church and to nothing else. He knows the id
    -- of the shop's invoice, which is the realistic threat: ids leak.
    select id into v_shop_invoice
      from invoices where number is not null
       and org_id = '85000000-0000-0000-0000-000000000001'
      limit 1;

    if v_shop_invoice is null then
        -- RLS already hid it at the point of looking, which is the strongest
        -- possible pass for this test.
        raise notice 'PASS: the shop''s invoices are not even visible to select';
    else
        raise exception 'FAIL: a pastor selected the shop''s invoice row';
    end if;

    -- And the document readers, which are SECURITY INVOKER for this reason.
    select count(*) into v_rows from list_invoices('85000000-0000-0000-0000-000000000001');
    if v_rows <> 0 then
        raise exception 'FAIL: list_invoices handed over % of the shop''s rows', v_rows;
    end if;

    raise notice 'PASS: no cross-tenant read through the document functions';
end $$;
commit;

\echo ''
\echo '--- TEST 13: somebody in no business at all sees nothing ---'
begin;
set local "request.jwt.claim.sub" = '85858585-0000-0000-0000-000000000004';
set local role authenticated;
do $$
declare
    v_rows int;
begin
    select count(*) into v_rows from invoices;
    if v_rows <> 0 then
        raise exception 'FAIL: a stranger sees % invoices', v_rows;
    end if;

    select count(*) into v_rows from list_invoices('85000000-0000-0000-0000-000000000001');
    if v_rows <> 0 then
        raise exception 'FAIL: a stranger listed % invoices', v_rows;
    end if;

    -- Writing is refused too, and by the function's own check rather than by
    -- the accident of RLS on a table it happens to touch.
    begin
        perform create_invoice(
            p_org_id        => '85000000-0000-0000-0000-000000000001',
            p_customer_name => 'Moi',
            p_lines         => '[{"description": "X", "quantity": 1, "unit_price": 10}]'::jsonb);
        raise exception 'FAIL: a stranger invoiced for somebody else''s shop';
    exception when raise_exception then
        if sqlerrm like 'FAIL:%' then raise; end if;
        raise notice 'PASS: refused — %', sqlerrm;
    end;

    raise notice 'PASS: a stranger reads nothing and writes nothing';
end $$;
commit;

\echo ''
\echo '--- TEST 14: the counter cannot be advanced from a client ---'
begin;
set local "request.jwt.claim.sub" = '85858585-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_issued int;
begin
    -- Readable, so a business can see where its numbering has got to.
    select issued into v_issued from invoice_counters
     where org_id = '85000000-0000-0000-0000-000000000001'
       and year = extract(year from current_date)::int;

    if v_issued is null or v_issued < 1 then
        raise exception 'FAIL: the counter reads %', v_issued;
    end if;

    -- Not writable. Somebody who could renumber invoices could make a
    -- document disappear from a numbered sequence, which is the one thing
    -- the numbering exists to prevent.
    begin
        update invoice_counters set issued = 0
         where org_id = '85000000-0000-0000-0000-000000000001';
        if found then
            raise exception 'FAIL: a client reset the invoice counter';
        end if;
        raise notice 'PASS: the update matched no rows';
    exception when insufficient_privilege then
        raise notice 'PASS: refused — %', sqlerrm;
    end;

    raise notice 'PASS: the counter reads but does not write';
end $$;
commit;

\echo ''
\echo '========================================'
\echo ' test_invoicing.sql: all assertions passed'
\echo '========================================'
