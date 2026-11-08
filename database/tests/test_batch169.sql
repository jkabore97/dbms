-- ============================================================
-- test_batch169.sql — 169: a platform admin adds an existing account to
-- a business.
--
-- The claims:
--   1. installed twice, the same;
--   2. only a platform admin adds; a business's own admin cannot;
--   3. added: the account is in the business at once, for the whole
--      business, with the role chosen; the console's journal holds it;
--      undone, the access is gone;
--   4. refused: already in the business, super_admin, an archived business,
--      the free plan's full team (an owner still goes in);
--   5. the street calls none of it.
-- Wrapped in one transaction rolled back.
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
grant usage on schema auth to anon, authenticated;
\i database/migrations/169_platform_add_member.sql
\i database/migrations/169_platform_add_member.sql

begin;
insert into auth.users (id, email, raw_user_meta_data, created_at) values
    ('16916916-0000-0000-0000-00000000000a', 'awa169@example.com', '{"full_name": "Awa 169"}', now()),
    ('16916916-0000-0000-0000-00000000000b', 'boss169@example.com', '{"full_name": "Boss 169"}', now()),
    ('16916916-0000-0000-0000-00000000000c', 'admin169@example.com', '{"full_name": "Admin 169"}', now()),
    ('16916916-0000-0000-0000-00000000000d', 'seydou169@example.com', '{"full_name": "Seydou 169"}', now());
update profiles set is_platform_admin = true where id = '16916916-0000-0000-0000-00000000000c';
insert into orgs (id, name, slug, profile, default_currency) values
    ('16916916-1111-0000-0000-000000000001', 'Boutique 169', 'boutique-169', 'retail', 'XOF'),
    ('16916916-1111-0000-0000-000000000002', 'Ferme 169', 'ferme-169', 'farm', 'XOF'),
    ('16916916-1111-0000-0000-000000000003', 'Association 169', 'asso-169', 'association', 'XOF');
update orgs set archived_at = now() where id = '16916916-1111-0000-0000-000000000003';
-- Set up, so the free plan's first person is open (as a real business after « Terminer »).
update orgs set setup_done_at = now() where id in ('16916916-1111-0000-0000-000000000001', '16916916-1111-0000-0000-000000000002');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('16916916-0000-0000-0000-00000000000b', '16916916-1111-0000-0000-000000000001', 'owner', 'org', '16916916-1111-0000-0000-000000000001', 'full');

-- 2. who may
set local role authenticated;
select set_config('request.jwt.claim.sub', '16916916-0000-0000-0000-00000000000b', true);
do $$
begin
    begin
        perform platform_add_member('16916916-1111-0000-0000-000000000001', '16916916-0000-0000-0000-00000000000a', 'employee');
        raise exception 'a business owner used the platform''s add';
    exception when raise_exception then
        assert sqlerrm like 'Réservé%', sqlerrm;
    end;
    raise notice 'PASS: 169 — a business''s own owner cannot use it';
end $$;

-- 3. added, journaled, undone (the add as the platform admin; what it
-- left, read as the owner of the tables)
select set_config('request.jwt.claim.sub', '16916916-0000-0000-0000-00000000000c', true);
select set_config('t169.id', platform_add_member('16916916-1111-0000-0000-000000000001', '16916916-0000-0000-0000-00000000000a', 'manager')::text, true);
do $$
begin
    begin
        perform platform_add_member('16916916-1111-0000-0000-000000000001', '16916916-0000-0000-0000-00000000000a', 'employee');
        raise exception 'added twice';
    exception when raise_exception then
        assert sqlerrm like '%fait déjà partie%', sqlerrm;
    end;
    raise notice 'PASS: 169 — an account already in the business is refused';
end $$;
reset role;
do $$
declare
    m     memberships%rowtype;
    v_act uuid;
begin
    select * into m from memberships where id = current_setting('t169.id')::uuid;
    assert m.user_id = '16916916-0000-0000-0000-00000000000a' and m.role = 'manager'
       and m.scope_kind = 'org' and m.scope_id = '16916916-1111-0000-0000-000000000001'
       and m.visibility = 'full', 'not added as asked';
    select id into v_act from platform_actions
     where org_id = '16916916-1111-0000-0000-000000000001' and kind = 'member'
       and undo_fn = 'platform_undo_add_member';
    assert v_act is not null, 'not in the journal';
    perform set_config('t169.act', v_act::text, true);
    raise notice 'PASS: 169 — the account is in the business at once, as manager, journaled';
end $$;
set local role authenticated;
select platform_undo(current_setting('t169.act')::uuid);
-- a farm, as owner
select set_config('t169.farm', platform_add_member('16916916-1111-0000-0000-000000000002', '16916916-0000-0000-0000-00000000000a', 'owner')::text, true);
reset role;
do $$
begin
    assert not exists (select 1 from memberships where id = current_setting('t169.id')::uuid), 'undo left the access';
    raise notice 'PASS: 169 — undone, the access is gone';
    assert exists (select 1 from memberships where id = current_setting('t169.farm')::uuid and role = 'owner'), 'farm owner not added';
    raise notice 'PASS: 169 — a farm gets an owner';
end $$;
set local role authenticated;

-- 4. refused
do $$
begin
    begin
        perform platform_add_member('16916916-1111-0000-0000-000000000001', '16916916-0000-0000-0000-00000000000d', 'super_admin');
        raise exception 'super_admin given';
    exception when raise_exception then
        assert sqlerrm like '%ne se donne pas%', sqlerrm;
    end;
    begin
        perform platform_add_member('16916916-1111-0000-0000-000000000003', '16916916-0000-0000-0000-00000000000d', 'employee');
        raise exception 'added to an archived business';
    exception when raise_exception then
        assert sqlerrm like '%archivée%', sqlerrm;
    end;
    begin
        perform platform_add_member('16916916-1111-0000-0000-000000000001', '16916916-0000-0000-0000-0000000000ff', 'employee');
        raise exception 'added an account that does not exist';
    exception when raise_exception then
        assert sqlerrm like 'Compte introuvable%', sqlerrm;
    end;
    raise notice 'PASS: 169 — super_admin, an archived business and an unknown account are refused';
end $$;

-- the free plan's full team
reset role;
do $$
declare v_cap int;
begin
    -- fill the boutique's free team to its cap with fresh accounts
    select org_free_workers('16916916-1111-0000-0000-000000000001') into v_cap;
    for i in 1..greatest(v_cap - org_workers('16916916-1111-0000-0000-000000000001'), 0) loop
        insert into auth.users (id, email, created_at)
        values (('16916916-2222-0000-0000-' || lpad(i::text, 12, '0'))::uuid, 'w' || i || '@169.example', now());
        insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility)
        values (('16916916-2222-0000-0000-' || lpad(i::text, 12, '0'))::uuid, '16916916-1111-0000-0000-000000000001',
                'employee', 'org', '16916916-1111-0000-0000-000000000001', 'full');
    end loop;
    assert team_full('16916916-1111-0000-0000-000000000001'), 'the free team is not full';
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub', '16916916-0000-0000-0000-00000000000c', true);
do $$
begin
    begin
        perform platform_add_member('16916916-1111-0000-0000-000000000001', '16916916-0000-0000-0000-00000000000d', 'employee');
        raise exception 'added past the free plan''s team';
    exception when raise_exception then
        assert sqlerrm not like 'added past%' and sqlerrm not like '%fait déjà partie%', sqlerrm;
    end;
    perform platform_add_member('16916916-1111-0000-0000-000000000001', '16916916-0000-0000-0000-00000000000d', 'owner');
    raise notice 'PASS: 169 — a full free team refuses an employee, an owner still goes in';
end $$;

-- 5. the street
reset role;
do $$
begin
    assert not has_function_privilege('anon', 'platform_add_member(uuid, uuid, role_name)', 'execute'), 'anon may add';
    assert not has_function_privilege('authenticated', 'platform_undo_add_member(jsonb)', 'execute'), 'undo open';
    raise notice 'PASS: 169 — the street calls none of it';
end $$;

rollback;
