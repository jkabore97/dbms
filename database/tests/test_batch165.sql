-- ============================================================
-- test_batch165.sql — 165: « Mettre en avant » for an Événementiel.
--
-- The claims:
--   1. an Événementiel with a public event to come asks a spot — no
--      vitrine, no pin; with none, it is told what to do; never an article;
--   2. its status says « placed », its queue is the Événementiels';
--   3. on the street its events come first, « sponsored »;
--   4. a shop is refused as before (no vitrine: « Ouvrez d'abord … »).
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
\i database/migrations/165_events_spots.sql
\i database/migrations/165_events_spots.sql

begin;
insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('16516516-0000-0000-0000-000000000001', '+22616510001', 'awa165@example.com', '{"full_name": "Awa"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan) values
    ('16516516-1111-0000-0000-000000000001', 'Awa Concerts 165', 'awa-concerts-165', 'events', 'XOF', 'pro'),
    ('16516516-1111-0000-0000-000000000002', 'Bob Fêtes 165', 'bob-fetes-165', 'events', 'XOF', 'free'),
    ('16516516-1111-0000-0000-000000000003', 'Boutique 165', 'boutique-165', 'retail', 'XOF', 'free');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility)
select '16516516-0000-0000-0000-000000000001', id, 'owner', 'org', id, 'full'
  from orgs where id in ('16516516-1111-0000-0000-000000000001', '16516516-1111-0000-0000-000000000002', '16516516-1111-0000-0000-000000000003');
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, content, tz, published, listed) values
    ('16516516-2222-0000-0000-000000000001', '16516516-1111-0000-0000-000000000001', '16516516-0000-0000-0000-000000000001', 'gala', 'gala',
     'concert-165', 'aaaaaaaaaaaaaaaaaaaaaa65', 'bbbbbbbbbbbbbbbbbbbbbb65', 'Concert 165', now() + interval '9 days', '{}', 'Africa/Ouagadougou', true, true),
    ('16516516-2222-0000-0000-000000000002', '16516516-1111-0000-0000-000000000002', '16516516-0000-0000-0000-000000000001', 'gala', 'gala',
     'fete-165', 'cccccccccccccccccccccc65', 'dddddddddddddddddddddd65', 'Fête 165', now() + interval '1 day', '{}', 'Africa/Ouagadougou', true, true),
    ('16516516-2222-0000-0000-000000000003', '16516516-1111-0000-0000-000000000002', '16516516-0000-0000-0000-000000000001', 'mariage', 'gala',
     'prive-165', 'eeeeeeeeeeeeeeeeeeeeee65', 'ffffffffffffffffffffff65', 'Privé 165', now() + interval '2 days', '{}', 'Africa/Ouagadougou', true, false);

do $$
declare v_err text; v_id uuid; j jsonb; mine jsonb;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '16516516-0000-0000-0000-000000000001', true);
    j := spot_area_status('16516516-1111-0000-0000-000000000001', 'shop');
    assert (j ->> 'positioned')::boolean and (j ->> 'free')::int >= 1, 'an Événementiel is placed: ' || j::text;
    v_id := request_promotion('16516516-1111-0000-0000-000000000001', null, 7);
    assert v_id is not null, 'asked, no vitrine, no pin';
    begin
        perform request_promotion('16516516-1111-0000-0000-000000000003', null, 7);
        raise exception 'a shop with no vitrine asked';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Ouvrez d''abord la vitrine%', 'a shop as before: ' || v_err;
    end;
    reset role;
    -- Bob's party leaves the street: no public event to come.
    update events set listed = false where id = '16516516-2222-0000-0000-000000000002';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '16516516-0000-0000-0000-000000000001', true);
    begin
        perform request_promotion('16516516-1111-0000-0000-000000000002', null, 7);
        raise exception 'an Événementiel with no public event asked';
    exception when others then
        get stacked diagnostics v_err = message_text;
        assert v_err like 'Rendez d''abord un événement public%', 'told what to do: ' || v_err;
    end;
    reset role;
    assert spot_ineligible('16516516-1111-0000-0000-000000000002', null) = 'event', 'ineligible: event';
    assert spot_ineligible('16516516-1111-0000-0000-000000000001', null) is null, 'eligible';
    assert spot_ineligible('16516516-1111-0000-0000-000000000003', null) = 'vitrine', 'a shop as before';

    -- Bob's party back on the street, sooner than Awa's concert; Awa's
    -- spot approved: the concert first, sponsored.
    update events set listed = true where id = '16516516-2222-0000-0000-000000000002';
    update promotions set status = 'approved', starts_at = now() - interval '1 minute', ends_at = now() + interval '7 days' where id = v_id;
    set local role anon;
    select jsonb_agg(x) into mine from jsonb_array_elements(street_events()) x where x ->> 'slug' like '%-165';
    assert jsonb_array_length(mine) = 2 and mine -> 0 ->> 'slug' = 'concert-165' and (mine -> 0 ->> 'sponsored')::boolean
           and mine -> 1 ->> 'slug' = 'fete-165' and not (mine -> 1 ->> 'sponsored')::boolean, 'sponsored first: ' || mine::text;
    reset role;
    raise notice 'PASS: 165 — an Événementiel puts its public events at the head of « Événements », no vitrine or pin; a shop as before';
end $$;

rollback;
