-- ============================================================
-- test_batch186.sql — 186: admin levels.
--
-- The claims:
--   1. an admin of everything (the admins of before): nothing changes —
--      any business theirs to run, every section's RPC theirs;
--   2. an admin given « Argent » only: Argent's RPCs pass; a Clients' RPC
--      is refused by the pre-request hook (platform_section); another
--      business, read or written, is not theirs; their own business is,
--      as its owner; the second step still asked of them;
--   3. an admin given « Clients »: any business theirs to run, as before;
--   4. platform_set_admin_access: only with « Administrateurs », never
--      oneself; an admin of a few sections gives only those and never
--      touches an admin of everything; each change a journal line with its
--      undo; set_platform_admin (010) is its « tout »;
--   5. nobody gives themselves sections by writing their own row;
--   6. platform_admins lists them with their authenticator;
--      platform_reset_two_step removes it, journaled;
--   7. the schema: no function checks the caller's flag inline any more
--      (the forms 186 rewrote) — a new one must ask
--      caller_is_platform_admin();
--   8. the doors.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
\i database/migrations/186_admin_levels.sql
\i database/migrations/186_admin_levels.sql

begin;
grant select, insert, update, delete on all tables in schema public to authenticated;
insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('18618618-0000-0000-0000-000000000001', '22618610001', 'jo186@example.com', '{"full_name": "Jo Tout"}', now()),
    ('18618618-0000-0000-0000-000000000002', '22618610002', 'max186@example.com', '{"full_name": "Max Argent"}', now()),
    ('18618618-0000-0000-0000-000000000003', '22618610003', 'cli186@example.com', '{"full_name": "Cléo Clients"}', now()),
    ('18618618-0000-0000-0000-000000000004', '22618610004', 'ter186@example.com', '{"full_name": "Tertius Nouveau"}', now()),
    ('18618618-0000-0000-0000-000000000005', '22618610005', 'awa186@example.com', '{"full_name": "Awa Commerçante"}', now());
insert into profiles (id, full_name) values
    ('18618618-0000-0000-0000-000000000001', 'Jo Tout'), ('18618618-0000-0000-0000-000000000002', 'Max Argent'),
    ('18618618-0000-0000-0000-000000000003', 'Cléo Clients'), ('18618618-0000-0000-0000-000000000004', 'Tertius Nouveau'),
    ('18618618-0000-0000-0000-000000000005', 'Awa Commerçante')
on conflict (id) do update set full_name = excluded.full_name;
-- the trusted context (no JWT) seeds the admins
update profiles set is_platform_admin = true, platform_access = null where id = '18618618-0000-0000-0000-000000000001';
update profiles set is_platform_admin = true, platform_access = '{money}' where id = '18618618-0000-0000-0000-000000000002';
update profiles set is_platform_admin = true, platform_access = '{clients,street,admins}' where id = '18618618-0000-0000-0000-000000000003';
insert into orgs (id, name, slug, profile, default_currency) values
    ('18618618-1111-0000-0000-000000000001', 'Boutique Awa 186', 'boutique-awa-186', 'shop', 'XOF'),
    ('18618618-1111-0000-0000-000000000002', 'Ferme Max 186', 'ferme-max-186', 'farm', 'XOF');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('18618618-0000-0000-0000-000000000005', '18618618-1111-0000-0000-000000000001', 'owner', 'org', '18618618-1111-0000-0000-000000000001', 'full'),
    ('18618618-0000-0000-0000-000000000002', '18618618-1111-0000-0000-000000000002', 'owner', 'org', '18618618-1111-0000-0000-000000000002', 'full');
insert into auth.mfa_factors (user_id, status) values ('18618618-0000-0000-0000-000000000002', 'verified');

-- as somebody, through an address
create or replace function pg_temp.as_(p_user text, p_path text, p_aal text default 'aal2') returns void
language sql as $$
    select set_config('request.jwt.claim.sub', p_user, true),
           set_config('request.jwt.claims', jsonb_build_object('sub', p_user, 'aal', p_aal)::text, true),
           set_config('request.path', p_path, true);
$$;
grant execute on function pg_temp.as_(text, text, text) to authenticated;
create or replace function pg_temp.gate() returns text
language plpgsql as $$
begin
    perform two_step_gate();
    return 'ok';
exception when others then
    return sqlerrm;
end $$;

-- 1. the admin of everything
do $$
declare v text;
begin
    perform pg_temp.as_('18618618-0000-0000-0000-000000000001', '/rest/v1/orgs');
    assert is_org_admin('18618618-1111-0000-0000-000000000001') and can_write_org('18618618-1111-0000-0000-000000000001')
       and is_org_member('18618618-1111-0000-0000-000000000001') and has_full_visibility('18618618-1111-0000-0000-000000000001'),
       'any business theirs';
    assert (select count(*) from my_org_ids() i where i in ('18618618-1111-0000-0000-000000000001', '18618618-1111-0000-0000-000000000002')) = 2,
       'every business listed';
    foreach v in array array['/rpc/search_orgs', '/rpc/set_org_plan', '/rpc/platform_reports', '/rpc/platform_set_setting',
                             '/rpc/platform_admins', '/rpc/platform_today'] loop
        perform pg_temp.as_('18618618-0000-0000-0000-000000000001', v);
        assert pg_temp.gate() = 'ok', 'the hook lets ' || v || ' through';
        assert caller_is_platform_admin(), 'admin for ' || v;
    end loop;
    raise notice 'PASS: an admin of everything — nothing changes';
end $$;

-- 2. « Argent » only
do $$
declare v text;
begin
    perform pg_temp.as_('18618618-0000-0000-0000-000000000002', '/rpc/platform_wave_payments');
    assert pg_temp.gate() = 'ok' and caller_is_platform_admin(), 'Argent''s RPC';
    -- inside it, the businesses are theirs to read, for that RPC
    assert is_org_admin('18618618-1111-0000-0000-000000000001'), 'within an Argent RPC';
    foreach v in array array['/rpc/search_orgs', '/rpc/platform_reports', '/rpc/platform_set_setting', '/rpc/platform_admins',
                             '/rpc/platform_set_admin_access', '/rpc/merge_accounts'] loop
        perform pg_temp.as_('18618618-0000-0000-0000-000000000002', v);
        assert pg_temp.gate() = 'Cette partie de la console ne vous est pas ouverte.', 'refused: ' || v || ' ' || pg_temp.gate();
        assert not caller_is_platform_admin(), 'not admin for ' || v;
    end loop;
    -- a table read, a business's own RPC: « clients », not theirs
    foreach v in array array['/rest/v1/orgs', '/rpc/update_org', ''] loop
        perform pg_temp.as_('18618618-0000-0000-0000-000000000002', v);
        assert pg_temp.gate() = 'ok', 'the hook lets ' || v || ' through';
        assert not is_org_admin('18618618-1111-0000-0000-000000000001') and not can_write_org('18618618-1111-0000-0000-000000000001')
           and not is_org_member('18618618-1111-0000-0000-000000000001') and not has_full_visibility('18618618-1111-0000-0000-000000000001')
           and not is_org_owner('18618618-1111-0000-0000-000000000001') and feature_access('18618618-1111-0000-0000-000000000001', 'stock') = 'hidden',
           'another business is not theirs at ' || v;
        -- their own, as its owner
        assert is_org_admin('18618618-1111-0000-0000-000000000002') and can_write_org('18618618-1111-0000-0000-000000000002'), 'their own farm';
    end loop;
    assert (select array_agg(i) from my_org_ids() i) = array['18618618-1111-0000-0000-000000000002'::uuid], 'only their own listed';
    -- the second step, still
    perform pg_temp.as_('18618618-0000-0000-0000-000000000002', '/rpc/platform_wave_payments', 'aal1');
    update platform_settings set value = 'true' where key = 'admin_two_step';
    if not found then insert into platform_settings (key, value) values ('admin_two_step', 'true'); end if;
    assert pg_temp.gate() = 'Validation en deux étapes requise', 'the second step first';
    raise notice 'PASS: « Argent » only — Argent''s RPCs; the rest refused; other businesses not theirs; their own as before';
end $$;

-- 3. « Clients »
do $$
begin
    perform pg_temp.as_('18618618-0000-0000-0000-000000000003', '/rest/v1/orgs');
    assert is_org_admin('18618618-1111-0000-0000-000000000001') and can_write_org('18618618-1111-0000-0000-000000000001'), 'any business';
    perform pg_temp.as_('18618618-0000-0000-0000-000000000003', '/rpc/search_orgs');
    assert pg_temp.gate() = 'ok' and caller_is_platform_admin(), 'Clients'' RPC';
    perform pg_temp.as_('18618618-0000-0000-0000-000000000003', '/rpc/set_org_plan');
    assert pg_temp.gate() <> 'ok' and not caller_is_platform_admin(), 'Argent''s refused';
    raise notice 'PASS: « Clients » — any business, as before';
end $$;

-- 4. who is admin, with what
do $$
declare v_err text; v_id uuid; a platform_actions;
begin
    set local role authenticated;
    -- not without « Administrateurs »
    perform pg_temp.as_('18618618-0000-0000-0000-000000000002', '/rpc/platform_set_admin_access');
    begin perform platform_set_admin_access('18618618-0000-0000-0000-000000000004', true, '{money}'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Réservé aux administrateurs qui gèrent les accès.', 'Max cannot: ' || v_err;
    -- the admin of everything gives Tertius two sections
    perform pg_temp.as_('18618618-0000-0000-0000-000000000001', '/rpc/platform_set_admin_access');
    v_id := platform_set_admin_access('18618618-0000-0000-0000-000000000004', true, '{street,clients}');
    reset role;
    assert (select is_platform_admin and platform_access = '{clients,street}' from profiles where id = '18618618-0000-0000-0000-000000000004'), 'given';
    select * into a from platform_actions where id = v_id;
    assert a.kind = 'admin_access' and a.summary = 'Tertius Nouveau : administrateur (Clients, La rue)'
       and a.actor = '18618618-0000-0000-0000-000000000001' and a.undo_fn = 'platform_undo_admin_access', 'journaled: ' || a.summary;
    set local role authenticated;
    -- never oneself
    begin perform platform_set_admin_access('18618618-0000-0000-0000-000000000001', true, '{money}'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Vous ne pouvez pas changer vos propres accès.', 'oneself: ' || v_err;
    -- « Annuler »
    perform pg_temp.as_('18618618-0000-0000-0000-000000000001', '/rpc/platform_undo');
    perform platform_undo(v_id);
    reset role;
    assert (select not is_platform_admin and platform_access is null from profiles where id = '18618618-0000-0000-0000-000000000004'), 'undone';
    set local role authenticated;
    -- an admin of a few sections: only theirs, and never an admin of everything
    perform pg_temp.as_('18618618-0000-0000-0000-000000000003', '/rpc/platform_set_admin_access');
    begin perform platform_set_admin_access('18618618-0000-0000-0000-000000000004', true, '{money}'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Vous ne pouvez donner que les sections que vous avez.', 'not theirs to give: ' || v_err;
    begin perform platform_set_admin_access('18618618-0000-0000-0000-000000000004', true, null); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Vous ne pouvez donner que les sections que vous avez.', 'not everything: ' || v_err;
    begin perform platform_set_admin_access('18618618-0000-0000-0000-000000000001', false, null); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Seul un administrateur complet modifie un administrateur complet.', 'the admin of everything untouched: ' || v_err;
    perform platform_set_admin_access('18618618-0000-0000-0000-000000000004', true, '{street}');
    begin perform platform_set_admin_access('18618618-0000-0000-0000-000000000004', true, '{nowhere}'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Section inconnue.', 'unknown: ' || v_err;
    -- 010's call: « tout », journaled
    perform pg_temp.as_('18618618-0000-0000-0000-000000000001', '/rpc/set_platform_admin');
    perform set_platform_admin('18618618-0000-0000-0000-000000000004', true);
    reset role;
    assert (select is_platform_admin and platform_access is null from profiles where id = '18618618-0000-0000-0000-000000000004'), 'everything';
    assert (select summary from platform_actions where kind = 'admin_access' order by at desc limit 1) = 'Tertius Nouveau : administrateur (tout)', 'journaled';
    set local role authenticated;
    perform set_platform_admin('18618618-0000-0000-0000-000000000004', false);
    reset role;
    assert (select summary from platform_actions where kind = 'admin_access' order by at desc limit 1) = 'Tertius Nouveau : plus administrateur', 'removed, journaled';
    raise notice 'PASS: who is admin — only with « Administrateurs », never oneself, only one''s sections; journaled with its undo';
end $$;

-- 5. nobody gives themselves sections
do $$
declare v_err text;
begin
    set local role authenticated;
    perform pg_temp.as_('18618618-0000-0000-0000-000000000002', '/rest/v1/profiles');
    begin update profiles set platform_access = null where id = '18618618-0000-0000-0000-000000000002'; v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    reset role;
    assert v_err = 'Only a platform administrator can change platform access', 'own row: ' || v_err;
    assert (select platform_access from profiles where id = '18618618-0000-0000-0000-000000000002') = '{money}', 'kept';
    raise notice 'PASS: nobody gives themselves sections';
end $$;

-- 6. the list; the authenticator reset
do $$
declare j jsonb; v_err text; c jsonb;
begin
    set local role authenticated;
    perform pg_temp.as_('18618618-0000-0000-0000-000000000001', '/rpc/platform_admins');
    j := platform_admins();
    select x into c from jsonb_array_elements(j) x where x ->> 'user_id' = '18618618-0000-0000-0000-000000000002';
    assert c -> 'access' = '["money"]'::jsonb and (c ->> 'two_step')::boolean and c ->> 'email' = 'max186@example.com', 'Max: ' || c::text;
    select x into c from jsonb_array_elements(j) x where x ->> 'user_id' = '18618618-0000-0000-0000-000000000001';
    assert c -> 'access' = 'null'::jsonb and (c ->> 'me')::boolean, 'me, everything';
    perform pg_temp.as_('18618618-0000-0000-0000-000000000001', '/rpc/platform_reset_two_step');
    perform platform_reset_two_step('18618618-0000-0000-0000-000000000002');
    begin perform platform_reset_two_step('18618618-0000-0000-0000-000000000005'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Ce compte n''est pas administrateur.', 'not an admin: ' || v_err;
    perform pg_temp.as_('18618618-0000-0000-0000-000000000003', '/rpc/platform_reset_two_step');
    begin perform platform_reset_two_step('18618618-0000-0000-0000-000000000001'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Seul un administrateur complet modifie un administrateur complet.', 'not the admin of everything: ' || v_err;
    reset role;
    assert not exists (select 1 from auth.mfa_factors where user_id = '18618618-0000-0000-0000-000000000002'), 'removed';
    assert (select summary from platform_actions where kind = 'admin_two_step_reset' order by at desc limit 1)
         = 'Max Argent : application d''authentification réinitialisée', 'journaled';
    raise notice 'PASS: the admins listed; an authenticator reset, journaled';
end $$;

-- 7. the schema: no inline check of the caller's flag left
do $$
declare v text;
begin
    select string_agg(proname, ', ' order by proname) into v
      from pg_proc
     where pronamespace = 'public'::regnamespace
       and prosrc ~* 'id\s*=\s*(auth\.uid\(\)|v_actor)\s+and\s+(\w+\.)?is_platform_admin'
       and proname not in ('caller_is_platform_admin', 'platform_admin_can');
    assert v is null, 'still checking the flag inline (ask caller_is_platform_admin()): ' || v;
    raise notice 'PASS: every admin check asks caller_is_platform_admin()';
end $$;

-- 8. the doors
do $$ begin
    assert not has_function_privilege('anon', 'platform_set_admin_access(uuid, boolean, text[])', 'execute')
       and not has_function_privilege('anon', 'platform_admins()', 'execute')
       and not has_function_privilege('anon', 'platform_reset_two_step(uuid)', 'execute')
       and not has_function_privilege('authenticated', 'platform_admin_can(text)', 'execute')
       and not has_function_privilege('authenticated', 'platform_request_sections()', 'execute')
       and not has_function_privilege('authenticated', 'platform_undo_admin_access(jsonb)', 'execute'), 'closed';
    assert has_function_privilege('authenticated', 'platform_set_admin_access(uuid, boolean, text[])', 'execute')
       and has_function_privilege('authenticated', 'platform_admins()', 'execute')
       and has_function_privilege('authenticated', 'platform_reset_two_step(uuid)', 'execute')
       and has_function_privilege('authenticated', 'set_platform_admin(uuid, boolean)', 'execute'), 'the signed-in''s';
    raise notice 'PASS: the doors';
end $$;
rollback;
