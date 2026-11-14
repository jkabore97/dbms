-- ============================================================
-- test_batch184.sql — 184: the days a card's guests add their photos.
--
-- The claims:
--   1. by default the days are the event's and the seven after, on the
--      card's clock: before, « Les photos s'ajoutent à partir du … »;
--      on the day, a photo; the seventh day after, a photo; the eighth,
--      « L'ajout de photos est clos depuis le … »;
--   2. my_event_invitations and event_presence_info say the two days and
--      whether today is one of them;
--   3. the organiser sets the days (the first day today on a card three
--      days away: a photo); a business that is not the card's sets none;
--      the last day before the first is refused;
--   4. a card with no date and no days takes photos any day;
--   5. the doors: the helpers closed to anon, public and authenticated.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
\i database/migrations/184_album_days.sql
\i database/migrations/184_album_days.sql

begin;
update platform_settings set value = 'true' where key = 'events_public';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('18418418-0000-0000-0000-000000000001', '22618410001', 'awa184@example.com', '{"full_name": "Awa Organisatrice"}', now()),
    ('18418418-0000-0000-0000-000000000002', '22618410002', 'bob184@example.com', '{"full_name": "Bob Autre"}', now()),
    ('18418418-0000-0000-0000-000000000003', '22670184003', 'nora184@example.com', '{"full_name": "Nora Invitée"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan, events_allowed) values
    ('18418418-1111-0000-0000-000000000001', 'Awa Fêtes 184', 'awa-fetes-184', 'events', 'XOF', 'pro', true),
    ('18418418-1111-0000-0000-000000000002', 'Bob Fêtes 184', 'bob-fetes-184', 'events', 'XOF', 'pro', true);
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('18418418-0000-0000-0000-000000000001', '18418418-1111-0000-0000-000000000001', 'owner', 'org', '18418418-1111-0000-0000-000000000001', 'full'),
    ('18418418-0000-0000-0000-000000000002', '18418418-1111-0000-0000-000000000002', 'owner', 'org', '18418418-1111-0000-0000-000000000002', 'full');
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, tz, published, album_on)
values
    ('18418418-2222-0000-0000-000000000001', '18418418-1111-0000-0000-000000000001', '18418418-0000-0000-0000-000000000001', 'mariage', 'come',
     'bientot-184', 'aaaaaaaaaaaaaaaaaaaaa184', 'bbbbbbbbbbbbbbbbbbbbb184', 'Bientôt', now() + interval '3 days', 'Ouaga', '{}', 'Africa/Ouagadougou', true, true),
    ('18418418-2222-0000-0000-000000000002', '18418418-1111-0000-0000-000000000001', '18418418-0000-0000-0000-000000000001', 'mariage', 'come',
     'aujourdhui-184', 'ccccccccccccccccccccc184', 'ddddddddddddddddddddd184', 'Aujourd''hui', now(), 'Ouaga', '{}', 'Africa/Ouagadougou', true, true),
    ('18418418-2222-0000-0000-000000000003', '18418418-1111-0000-0000-000000000001', '18418418-0000-0000-0000-000000000001', 'mariage', 'come',
     'semaine-184', 'eeeeeeeeeeeeeeeeeeeee184', 'fffffffffffffffffffff184', 'Il y a sept jours', now() - interval '7 days', 'Ouaga', '{}', '+00:00', true, true),
    ('18418418-2222-0000-0000-000000000004', '18418418-1111-0000-0000-000000000001', '18418418-0000-0000-0000-000000000001', 'mariage', 'come',
     'passe-184', 'ggggggggggggggggggggg184', 'hhhhhhhhhhhhhhhhhhhhh184', 'Il y a huit jours', now() - interval '8 days', 'Ouaga', '{}', 'Africa/Ouagadougou', true, true),
    ('18418418-2222-0000-0000-000000000005', '18418418-1111-0000-0000-000000000001', '18418418-0000-0000-0000-000000000001', 'gala', 'gala',
     'sans-date-184', 'iiiiiiiiiiiiiiiiiiiii184', 'jjjjjjjjjjjjjjjjjjjjj184', 'Sans date', null, 'Ouaga', '{}', 'Africa/Ouagadougou', true, true);

create temp table t184 (k text primary key, v text);
grant all on t184 to anon, authenticated;

-- the guest confirms the five cards (the past ones too: the answers stay
-- open, no closing day set)
do $$
declare s text;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18418418-0000-0000-0000-000000000003', true);
    foreach s in array array['bientot-184', 'aujourdhui-184', 'semaine-184', 'passe-184', 'sans-date-184'] loop
        perform event_presence_confirm(s, null, 1, null);
    end loop;
    reset role;
end $$;

-- 1. the default days
do $$
declare v_err text; v_day date := (now() at time zone 'Africa/Ouagadougou')::date;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18418418-0000-0000-0000-000000000003', true);
    begin perform event_album_add_guest('bientot-184', 'jpg'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Les photos s''ajoutent à partir du ' || to_char(v_day + 3, 'DD/MM/YYYY') || '.', 'before the day: ' || v_err;
    assert event_album_add_guest('aujourdhui-184', 'jpg') like 'events/18418418-2222-0000-0000-000000000002/%', 'on the day';
    assert event_album_add_guest('semaine-184', 'jpg') like 'events/18418418-2222-0000-0000-000000000003/%', 'the seventh day after';
    begin perform event_album_add_guest('passe-184', 'jpg'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'L''ajout de photos est clos depuis le ' || to_char(v_day - 1, 'DD/MM/YYYY') || '.', 'the eighth day after: ' || v_err;
    reset role;
    raise notice 'PASS: by default the event''s day and the seven after, on the card''s clock';
end $$;

-- 2. what the guest's screens read
do $$
declare j jsonb; c jsonb; v_day date := (now() at time zone 'Africa/Ouagadougou')::date;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18418418-0000-0000-0000-000000000003', true);
    j := my_event_invitations();
    select x into c from jsonb_array_elements(j) x where x ->> 'slug' = 'bientot-184';
    assert c ->> 'photos_from' = (v_day + 3)::text and c ->> 'photos_until' = (v_day + 10)::text
       and (c ->> 'photos_open')::boolean = false, 'the days, closed for now: ' || c::text;
    select x into c from jsonb_array_elements(j) x where x ->> 'slug' = 'aujourdhui-184';
    assert (c ->> 'photos_open')::boolean, 'open today: ' || c::text;
    select x into c from jsonb_array_elements(j) x where x ->> 'slug' = 'sans-date-184';
    assert c -> 'photos_from' = 'null'::jsonb and c -> 'photos_until' = 'null'::jsonb and (c ->> 'photos_open')::boolean, 'no date, no days: ' || c::text;
    j := event_presence_info('passe-184', null);
    assert j ->> 'photos_until' = (v_day - 1)::text and not (j ->> 'photos_open')::boolean, 'the confirmation screen: ' || j::text;
    reset role;
    raise notice 'PASS: « Mes invitations » and the confirmation screen say the days';
end $$;

-- 3. the organiser's days
do $$
declare v_err text; v_day date := (now() at time zone 'Africa/Ouagadougou')::date; v_n int;
begin
    set local role authenticated;
    -- another business sets nothing (RLS)
    perform set_config('request.jwt.claim.sub', '18418418-0000-0000-0000-000000000002', true);
    update events set album_from = v_day where id = '18418418-2222-0000-0000-000000000001';
    get diagnostics v_n = row_count;
    assert v_n = 0, 'another business''s update: ' || v_n;
    -- the organiser opens today
    perform set_config('request.jwt.claim.sub', '18418418-0000-0000-0000-000000000001', true);
    update events set album_from = v_day, album_until = v_day + 20 where id = '18418418-2222-0000-0000-000000000001';
    get diagnostics v_n = row_count;
    assert v_n = 1, 'the organiser''s update';
    begin update events set album_until = v_day - 1 where id = '18418418-2222-0000-0000-000000000001'; v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err like '%events_album_days%', 'the last day before the first: ' || v_err;
    -- and closes a past one's days for good
    update events set album_until = v_day - 1 where id = '18418418-2222-0000-0000-000000000002';
    perform set_config('request.jwt.claim.sub', '18418418-0000-0000-0000-000000000003', true);
    assert event_album_add_guest('bientot-184', 'jpg') like 'events/18418418-2222-0000-0000-000000000001/%', 'opened today by the organiser';
    begin perform event_album_add_guest('aujourdhui-184', 'jpg'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err like 'L''ajout de photos est clos depuis le %', 'closed by the organiser: ' || v_err;
    reset role;
    assert (select album_until from events where id = '18418418-2222-0000-0000-000000000001') = v_day + 20, 'kept';
    raise notice 'PASS: the organiser sets the days; nobody else; the last never before the first';
end $$;

-- 4. no date, no days: any day
do $$
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18418418-0000-0000-0000-000000000003', true);
    assert event_album_add_guest('sans-date-184', 'png') like 'events/18418418-2222-0000-0000-000000000005/%', 'any day';
    reset role;
    raise notice 'PASS: a card with no date and no days takes photos any day';
end $$;

-- 5. the doors
do $$ begin
    assert not has_function_privilege('anon', 'event_album_opens(events)', 'execute')
       and not has_function_privilege('authenticated', 'event_album_closes(events)', 'execute')
       and not has_function_privilege('public', 'event_album_today(events)', 'execute')
       and not has_function_privilege('anon', 'my_event_invitations()', 'execute')
       and not has_function_privilege('anon', 'event_album_add_guest(text, text)', 'execute'), 'closed';
    assert has_function_privilege('authenticated', 'my_event_invitations()', 'execute')
       and has_function_privilege('authenticated', 'event_album_add_guest(text, text)', 'execute')
       and has_function_privilege('authenticated', 'event_presence_info(text, text)', 'execute'), 'open to the signed-in';
    assert has_column_privilege('authenticated', 'events', 'album_from', 'update')
       and has_column_privilege('authenticated', 'events', 'album_until', 'update'), 'the two columns, the signed-in''s';
    raise notice 'PASS: the doors';
end $$;
rollback;
