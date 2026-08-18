-- ============================================================
-- test_invoice_revision.sql — the owner corrects an invoice (040).
--
-- Phone block 18. What matters, in order of what it would cost to get wrong:
--   1. A revision withdraws the old document AND its ledger entry, issues a
--      replacement with its own number that names the old one, and the books
--      end up carrying the corrected amount once — not both.
--   2. Only an admin revises. An employee who may bill cannot rewrite what
--      was billed.
--   3. An invoice money has already arrived against refuses revision — the
--      correction for that is a refund or credit note, and the message from
--      cancel_invoice says so.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''18181818-0000-0000-0000-000000000001'''
\set clerk '''18181818-0000-0000-0000-000000000002'''
\set org   '''18000000-0000-0000-0000-000000000001'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into auth.users (id, phone, raw_user_meta_data) values
    (:owner, '+22618000001', '{"full_name": "Patronne"}'),
    (:clerk, '+22618000002', '{"full_name": "Vendeuse"}');

insert into orgs (id, name, slug, profile, default_currency)
values (:org, 'Boutique Facture', 'boutique-facture-18', 'retail', 'XOF');
insert into memberships (org_id, user_id, role, scope_kind, scope_id) values
    (:org, :owner, 'owner',    'org', :org),
    (:org, :clerk, 'employee', 'org', :org);


\echo ''
\echo '--- TEST 1: a revision replaces the document and corrects the books ---'
begin;
set local "request.jwt.claim.sub" = '18181818-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare
    v_old uuid; v_new uuid;
    v_old_row invoices%rowtype; v_new_row invoices%rowtype;
    v_receivable numeric; v_memo text;
begin
    -- Billed 20 savons... but it should have been 12.
    v_old := create_invoice(
        p_org_id        => '18000000-0000-0000-0000-000000000001',
        p_customer_name => 'Hôtel Liberté',
        p_lines         => '[{"description": "Savon 500g", "quantity": 20, "unit_price": 750}]'::jsonb,
        p_due_days      => 30
    );

    v_new := revise_invoice(
        p_invoice_id    => v_old,
        p_customer_name => 'Hôtel Liberté',
        p_lines         => '[{"description": "Savon 500g", "quantity": 12, "unit_price": 750}]'::jsonb,
        p_due_days      => 30
    );

    select * into v_old_row from invoices where id = v_old;
    select * into v_new_row from invoices where id = v_new;

    if v_old_row.cancelled_at is null then
        raise exception 'FAIL: the old invoice was not withdrawn';
    end if;
    if v_new_row.total <> 9000 then
        raise exception 'FAIL: replacement total is % (want 9000)', v_new_row.total;
    end if;
    if v_new_row.number = v_old_row.number then
        raise exception 'FAIL: the replacement reused number %', v_old_row.number;
    end if;

    -- The replacement says which document it replaces (memo on its entry).
    select memo into v_memo from journal_entries where id = v_new_row.journal_entry_id;
    if position(v_old_row.number in coalesce(v_memo, '')) = 0 then
        raise exception 'FAIL: the replacement does not name % (memo: %)',
            v_old_row.number, v_memo;
    end if;

    -- The books: the old entry contre-passed, the new one posted — the
    -- receivable carries 9 000 once, not 15 000 + 9 000.
    select coalesce(sum(jl.debit), 0) - coalesce(sum(jl.credit), 0)
      into v_receivable
      from journal_lines jl
      join accounts a on a.id = jl.account_id
     where a.org_id = '18000000-0000-0000-0000-000000000001'
       and a.type = 'asset' and a.code = '1300';
    if v_receivable <> 9000 then
        raise exception 'FAIL: receivable reads % (want 9000)', v_receivable;
    end if;

    raise notice 'PASS: old withdrawn, % issued for 9000, books carry 9000',
        v_new_row.number;
end $$;
rollback;


\echo ''
\echo '--- TEST 2: an employee cannot revise what was billed ---'
begin;
set local "request.jwt.claim.sub" = '18181818-0000-0000-0000-000000000002';
set local role authenticated;
do $$
declare v_inv uuid; v_raised boolean := false;
begin
    -- The clerk may bill (can_write_org)...
    v_inv := create_invoice(
        p_org_id        => '18000000-0000-0000-0000-000000000001',
        p_customer_name => 'Client Comptoir',
        p_lines         => '[{"description": "Sucre", "quantity": 2, "unit_price": 900}]'::jsonb
    );
    -- ...but not rewrite it.
    begin
        perform revise_invoice(
            p_invoice_id    => v_inv,
            p_customer_name => 'Client Comptoir',
            p_lines         => '[{"description": "Sucre", "quantity": 1, "unit_price": 900}]'::jsonb
        );
    exception when others then v_raised := true;
    end;
    if not v_raised then
        raise exception 'FAIL: an employee revised an invoice';
    end if;
    raise notice 'PASS: the employee is refused';
end $$;
rollback;


\echo ''
\echo '--- TEST 3: money already received blocks a revision ---'
begin;
set local "request.jwt.claim.sub" = '18181818-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare v_inv uuid; v_raised boolean := false;
begin
    v_inv := create_invoice(
        p_org_id        => '18000000-0000-0000-0000-000000000001',
        p_customer_name => 'Hôtel Liberté',
        p_lines         => '[{"description": "Savon", "quantity": 10, "unit_price": 750}]'::jsonb
    );
    perform record_invoice_payment(v_inv, 3000);

    begin
        perform revise_invoice(
            p_invoice_id    => v_inv,
            p_customer_name => 'Hôtel Liberté',
            p_lines         => '[{"description": "Savon", "quantity": 8, "unit_price": 750}]'::jsonb
        );
    exception when others then v_raised := true;
    end;
    if not v_raised then
        raise exception 'FAIL: a part-paid invoice was revised';
    end if;
    raise notice 'PASS: a part-paid invoice refuses revision';
end $$;
rollback;

\echo ''
\echo '=== test_invoice_revision.sql: all checks passed ==='
