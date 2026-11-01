-- ============================================================
-- test_batch156.sql — 156: a published card opens for its guests,
-- whatever the platform's switch.
--
-- The claims:
--   1. installed twice, the same: with the switch events_public off, a
--      published card opens for the street by its short link (not as a
--      preview), its answer is taken and its album read; an unpublished
--      one stays closed unless the preview or the edit token; the street
--      still cannot call event_visible itself;
--   2. the switch keeps its other meanings: events_options says it is
--      off, and a business's member still sees nothing of the module
--      (events_open) — only Marakaj's admins.
-- Wrapped in one transaction rolled back: runs twice the same.
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
grant select, insert, update, delete on all tables in schema public to authenticated;
-- Installed twice, the same.
\i database/migrations/156_events_published_open.sql
\i database/migrations/156_events_published_open.sql

begin;

update platform_settings set value = 'false' where key = 'events_public';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('15615615-0000-0000-0000-000000000001', '+22615610001', 'awa156@example.com', '{"full_name": "Awa Planner"}', now());
insert into orgs (id, name, slug, profile, default_currency) values
    ('15615615-1111-0000-0000-000000000001', 'Awa Événements 156', 'awa-evenements-156', 'events', 'XOF');
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('15615615-0000-0000-0000-000000000001', '15615615-1111-0000-0000-000000000001', 'owner', 'org', '15615615-1111-0000-0000-000000000001', 'full');
-- The card, made by the owner as a platform admin would (the switch off
-- keeps event_create to Marakaj's admins: the row goes in directly).
insert into events (org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, tz)
values ('15615615-1111-0000-0000-000000000001', '15615615-0000-0000-0000-000000000001', 'anniversaire', 'anime_champagne_p',
        'esperance-anniversaire-156', 'aaaaaaaaaaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbbbbbbbbbb', 'Espérance Anniversaire',
        '2026-12-12 18:00+00', 'Ouagadougou', '{"type": "anniversaire"}', 'Africa/Ouagadougou');

-- 1. the published card opens by its short link, the switch off
do $$
declare
    j jsonb;
    v_id uuid;
    f text;
begin
    assert (select value from platform_settings where key = 'events_public') = 'false'::jsonb, 'the switch is off';
    set local role anon;
    assert event_public('esperance-anniversaire-156') is null, 'unpublished: nothing for the street';
    assert event_public('esperance-anniversaire-156', 'aaaaaaaaaaaaaaaaaaaaaaaa') is not null, 'the preview token opens it';
    assert event_public('esperance-anniversaire-156', null, 'bbbbbbbbbbbbbbbbbbbbbbbb') is not null, 'the edit token opens it';
    assert event_album('esperance-anniversaire-156') is null, 'unpublished: no album for the street';
    reset role;

    update events set published = true where slug = 'esperance-anniversaire-156';
    set local role anon;
    j := event_public('esperance-anniversaire-156');
    assert j is not null and (j ->> 'published')::boolean and not (j ->> 'preview')::boolean and not (j ->> 'editor')::boolean,
        'published, the switch off: the street sees the card by its short link: ' || coalesce(j::text, 'nothing');
    v_id := event_rsvp('esperance-anniversaire-156', null, 'Tanti Rose', 2, 'oui', null, '{}');
    assert v_id is not null, 'and answers through it';
    assert event_album('esperance-anniversaire-156') = '[]'::jsonb, 'and reads its album';
    reset role;

    foreach f in array array['event_visible(events, text, text)', 'event_visible(events, text)'] loop
        assert not has_function_privilege('anon', f, 'execute'), 'the street cannot call ' || f;
        assert not has_function_privilege('public', f, 'execute'), 'PUBLIC cannot call ' || f;
    end loop;
end $$;

-- 2. the switch keeps its other meanings
do $$
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '15615615-0000-0000-0000-000000000001', true);
    assert (events_options() ->> 'public')::boolean = false, 'the app is told the module is not public';
    assert (select count(*) from events where slug = 'esperance-anniversaire-156') = 0,
        'the switch off: the business''s own admin reads no event in the app (events_open)';
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    raise notice 'PASS: 156 — a published card opens for its guests by its short link whatever the switch; unpublished, only its tokens; the switch still decides the module''s reach';
end $$;

rollback;
