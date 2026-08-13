-- Bootstrap a super administrator, and two businesses for them to administer.
--
-- Why this file exists and why it cannot be an app screen: there is no INSERT
-- policy on `orgs`. That is deliberate — a signed-in stranger must not be able
-- to conjure a business into existence — but it means the very first org has
-- to arrive from outside the API, by someone holding the database itself.
-- That is this file.
--
-- Run it as the database owner, either in the Supabase SQL editor
-- (Dashboard -> SQL Editor -> paste -> Run) or:
--
--     psql "$SUPABASE_DB_URL" -f scripts/bootstrap-superadmin.sql
--
-- It is safe to run twice. Every insert is guarded, so a second run adds
-- nothing and changes nothing.
--
-- The account must already exist in auth.users — sign up on the login screen
-- first, or POST to /auth/v1/signup. This file grants; it does not create
-- logins, because passwords are GoTrue's business and not the schema's.

do $$
declare
    -- The only line you should need to edit.
    v_email      text := 'admin@kajapp.com';

    v_user_id    uuid;
    v_church_id  uuid;
    v_farm_id    uuid;
    v_entity_id  uuid;
begin
    select id into v_user_id from auth.users where email = v_email;

    if v_user_id is null then
        raise exception 'No account for % — sign up first, then run this again.', v_email;
    end if;

    -- 004 installs a trigger that mirrors new auth.users rows into profiles,
    -- but an account created before that trigger existed would have no profile,
    -- and memberships.user_id points at profiles, not at auth.users.
    insert into profiles (id, full_name, preferred_locale)
    values (v_user_id, 'Super Admin', 'fr')
    on conflict (id) do nothing;

    -- ----------------------------------------------------------------
    -- Two businesses, on purpose: the home screen is chosen by the org's
    -- `profile` column, so one church and one farm exercise both routes and
    -- the org picker in between them.
    -- ----------------------------------------------------------------
    insert into orgs (name, slug, profile, default_currency)
    values ('Église de Test', 'test-church', 'church', 'XOF')
    on conflict (slug) do nothing;
    select id into v_church_id from orgs where slug = 'test-church';

    insert into orgs (name, slug, profile, default_currency)
    values ('Ferme de Test', 'test-farm', 'farm', 'XOF')
    on conflict (slug) do nothing;
    select id into v_farm_id from orgs where slug = 'test-farm';

    -- A site each. Nothing requires one — journal_entries.entity_id is
    -- nullable — but an org with no location is a shape real businesses never
    -- have, and testing against it hides the bugs that only appear when a
    -- second site does.
    if not exists (select 1 from entities where org_id = v_church_id) then
        insert into entities (org_id, name, kind)
        values (v_church_id, 'Campus principal', 'campus');
    end if;

    if not exists (select 1 from entities where org_id = v_farm_id) then
        insert into entities (org_id, name, kind)
        values (v_farm_id, 'Site principal', 'farm_site')
        returning id into v_entity_id;

        insert into departments (entity_id, name)
        values (v_entity_id, 'Aviculture');
    end if;

    -- Charts of accounts. Recording anything raises an exception without them.
    perform seed_church_accounts(v_church_id);
    perform seed_farm_accounts(v_farm_id);

    -- ----------------------------------------------------------------
    -- The grants. `super_admin` at org scope in both — scope_kind='org'
    -- means scope_id is the org id itself, which is what my_org_ids() and
    -- every policy built on it resolve against.
    -- ----------------------------------------------------------------
    insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
    values (v_church_id, v_user_id, 'super_admin', 'org', v_church_id, 'full')
    on conflict (user_id, scope_kind, scope_id, role) do nothing;

    insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
    values (v_farm_id, v_user_id, 'super_admin', 'org', v_farm_id, 'full')
    on conflict (user_id, scope_kind, scope_id, role) do nothing;

    raise notice 'Super admin % ready.', v_email;
    raise notice 'Church: % (test-church)', v_church_id;
    raise notice 'Farm:   % (test-farm)', v_farm_id;
end $$;

-- What the app will see when it calls my_orgs() as this user.
select o.name, o.slug, o.profile, m.role, m.scope_kind, m.visibility
from memberships m
join orgs o on o.id = m.org_id
join auth.users u on u.id = m.user_id
where u.email = 'admin@kajapp.com'
order by o.name;
