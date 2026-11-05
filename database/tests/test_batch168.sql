-- ============================================================
-- test_batch168.sql — 168: two accounts of one person, merged.
--
-- The claims:
--   1. installed twice, the same;
--   2. only a platform admin previews or merges; never absorbing oneself or
--      a platform admin; the absorbed account's email typed back, or nothing;
--   3. merged: the Apple sign-in now opens the kept account; its businesses
--      (one shared, one its own) are the kept one's; a book entry it wrote —
--      which no one may change — is the kept one's; a setting both had keeps
--      the kept one's, one only it had moves; the kept profile's empty phone
--      takes the absorbed one's; the absorbed account is gone; the merge is
--      logged;
--   4. the street and a member call none of it.
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
\i database/migrations/168_merge_accounts.sql
\i database/migrations/168_merge_accounts.sql

begin;
insert into auth.users (id, email, raw_user_meta_data, created_at) values
    ('16816816-0000-0000-0000-00000000000a', 'awa.google@example.com', '{"full_name": "Awa Ouédraogo"}', now()),
    ('16816816-0000-0000-0000-00000000000b', 'x7relay@privaterelay.appleid.com', '{"full_name": ""}', now()),
    ('16816816-0000-0000-0000-00000000000c', 'admin168@example.com', '{"full_name": "Admin"}', now());
update profiles set is_platform_admin = true where id = '16816816-0000-0000-0000-00000000000c';
update profiles set phone = null where id = '16816816-0000-0000-0000-00000000000a';
update profiles set phone = '+22670000168' where id = '16816816-0000-0000-0000-00000000000b';
insert into auth.identities (provider_id, user_id, provider) values
    ('g-168', '16816816-0000-0000-0000-00000000000a', 'google'),
    ('a-168', '16816816-0000-0000-0000-00000000000b', 'apple');
insert into orgs (id, name, slug, profile, default_currency) values
    ('16816816-1111-0000-0000-000000000001', 'Boutique Awa 168', 'boutique-awa-168', 'retail', 'XOF'),
    ('16816816-1111-0000-0000-000000000002', 'Ferme Awa 168', 'ferme-awa-168', 'farm', 'XOF');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('16816816-0000-0000-0000-00000000000a', '16816816-1111-0000-0000-000000000001', 'admin', 'org', '16816816-1111-0000-0000-000000000001', 'full'),
    ('16816816-0000-0000-0000-00000000000b', '16816816-1111-0000-0000-000000000001', 'owner', 'org', '16816816-1111-0000-0000-000000000001', 'full'),
    ('16816816-0000-0000-0000-00000000000b', '16816816-1111-0000-0000-000000000002', 'owner', 'org', '16816816-1111-0000-0000-000000000002', 'full');
insert into journal_entries (id, org_id, created_by, memo) values
    ('16816816-3333-0000-0000-000000000001', '16816816-1111-0000-0000-000000000002', '16816816-0000-0000-0000-00000000000b', 'Vente 168');
insert into notification_prefs (user_id, type, enabled) values
    ('16816816-0000-0000-0000-00000000000a', 'order_new', true),
    ('16816816-0000-0000-0000-00000000000b', 'order_new', false),
    ('16816816-0000-0000-0000-00000000000b', 'stock_low', false);

-- 2. who may
set local role authenticated;
select set_config('request.jwt.claim.sub', '16816816-0000-0000-0000-00000000000a', true);
do $$
begin
    begin
        perform account_merge_preview('16816816-0000-0000-0000-00000000000a', '16816816-0000-0000-0000-00000000000b');
        raise exception 'a member previewed a merge';
    exception when raise_exception then
        assert sqlerrm like 'Réservé%', sqlerrm;
    end;
    begin
        perform merge_accounts('16816816-0000-0000-0000-00000000000a', '16816816-0000-0000-0000-00000000000b', 'x7relay@privaterelay.appleid.com');
        raise exception 'a member merged two accounts';
    exception when raise_exception then
        assert sqlerrm like 'Réservé%', sqlerrm;
    end;
    raise notice 'PASS: 168 — a member neither previews nor merges';
end $$;

select set_config('request.jwt.claim.sub', '16816816-0000-0000-0000-00000000000c', true);
do $$
declare j jsonb;
begin
    j := account_merge_preview('16816816-0000-0000-0000-00000000000a', '16816816-0000-0000-0000-00000000000b');
    assert j -> 'absorb' ->> 'email' = 'x7relay@privaterelay.appleid.com', j::text;
    assert j -> 'absorb' -> 'providers' = '["apple"]'::jsonb, j::text;
    assert (j -> 'absorb' ->> 'password')::boolean = false, j::text;
    assert jsonb_array_length(j -> 'absorb' -> 'businesses') = 2, j::text;
    assert (j -> 'rows' ->> 'journal_entries.created_by')::int = 1, j::text;
    begin
        perform merge_accounts('16816816-0000-0000-0000-00000000000a', '16816816-0000-0000-0000-00000000000b', 'oui');
        raise exception 'merged without the email typed back';
    exception when raise_exception then
        assert sqlerrm like 'Pour confirmer%', sqlerrm;
    end;
    begin
        perform merge_accounts('16816816-0000-0000-0000-00000000000a', '16816816-0000-0000-0000-00000000000c', 'admin168@example.com');
        raise exception 'absorbed oneself';
    exception when raise_exception then null;
    end;
    begin
        perform merge_accounts('16816816-0000-0000-0000-00000000000b', '16816816-0000-0000-0000-00000000000c', 'admin168@example.com');
        raise exception 'absorbed a platform admin';
    exception when raise_exception then null;
    end;
    raise notice 'PASS: 168 — a platform admin previews; the email typed back, never oneself, never another platform admin';
end $$;

-- 3. merged (as the platform admin; read back as the database)
select merge_accounts('16816816-0000-0000-0000-00000000000a', '16816816-0000-0000-0000-00000000000b', 'X7RELAY@privaterelay.appleid.com ') is not null as merged;
reset role;
do $$
begin
    assert not exists (select 1 from auth.users where id = '16816816-0000-0000-0000-00000000000b'), 'the absorbed account is gone';
    assert (select user_id from auth.identities where provider = 'apple' and provider_id = 'a-168') = '16816816-0000-0000-0000-00000000000a',
        'the Apple sign-in opens the kept account';
    assert (select count(*) from memberships where user_id = '16816816-0000-0000-0000-00000000000a') = 3, 'its businesses are the kept one''s';
    assert exists (select 1 from memberships where user_id = '16816816-0000-0000-0000-00000000000a'
                    and org_id = '16816816-1111-0000-0000-000000000002' and role = 'owner'), 'owner of the farm';
    assert (select created_by from journal_entries where id = '16816816-3333-0000-0000-000000000001') = '16816816-0000-0000-0000-00000000000a',
        'the book entry is the kept one''s, guard or not';
    assert (select enabled from notification_prefs where user_id = '16816816-0000-0000-0000-00000000000a' and type = 'order_new'), 'the kept setting stays';
    assert exists (select 1 from notification_prefs where user_id = '16816816-0000-0000-0000-00000000000a' and type = 'stock_low'), 'the other''s moves';
    assert (select phone from profiles where id = '16816816-0000-0000-0000-00000000000a') = '+22670000168', 'the empty phone filled';
    assert (select count(*) from account_merges where kept_id = '16816816-0000-0000-0000-00000000000a') = 1, 'logged';
    raise notice 'PASS: 168 — merged: the Apple sign-in opens the kept account, its businesses and its book entry follow, settings combined, the merge logged';
end $$;

-- 4. the doors
do $$
declare f text;
begin
    assert (select tgenabled from pg_trigger where tgname = 'journal_entry_closed') = 'O', 'the guard is back on';
    foreach f in array array['account_merge_preview(uuid, uuid)', 'merge_accounts(uuid, uuid, text)'] loop
        assert not has_function_privilege('anon', f, 'execute'), f || ' open to the street';
    end loop;
    foreach f in array array['_merge_move(regclass, text, uuid, uuid)', '_person_columns()', '_merge_account_card(uuid)'] loop
        assert not has_function_privilege('authenticated', f, 'execute'), f || ' open to a member';
    end loop;
    raise notice 'PASS: 168 — the guard is back on; the street calls nothing, a member only the two doors the server guards';
end $$;
rollback;
