-- ============================================================
-- test_batch183.sql — 183: « Confirmer ma présence », five photos per
-- guest from the app.
--
-- The claims:
--   1. signed out, nothing: neither a confirmation nor a photo;
--   2. a signed-in guest confirms: one answer, the account's name and
--      number, the guest's bell and the organiser's;
--   3. confirming again changes how many and the word — still one answer,
--      no second bell for anyone;
--   4. my_event_invitations lists it (a draft's link only to the guest who
--      came through it); event_presence_info says it is theirs;
--   5. an account that has not confirmed adds no photo; a confirmed guest
--      adds five, the sixth refused; event_album_done completes the
--      guest's own slot; the old signed-out door now says the way;
--   6. a free (not Pro) business's album takes none (182);
--   7. the doors: anon executes none of the new functions;
--   8. (the review) a nameless account's name is « Invité », never its
--      phone — on its photos (anon's album) and in the organiser's bell;
--      the number reaches the organiser only when shared, and a later
--      confirmation without it takes it back;
--   9. refused: a cancelled card (confirm and photo), answers off with
--      tickets off, the closing date passed, a word over 500, a photo for
--      a card the guest did not confirm, a draft whose link changed;
--  10. a slot not completed within ten minutes no longer counts, and can
--      no longer be completed; the two bells answer to switches.
-- Installed twice, the same. Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
\i database/migrations/183_events_presence.sql
\i database/migrations/183_events_presence.sql

begin;
update platform_settings set value = 'true' where key = 'events_public';

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('18318318-0000-0000-0000-000000000001', '22618310001', 'awa183@example.com', '{"full_name": "Awa Organisatrice"}', now()),
    ('18318318-0000-0000-0000-000000000002', '22618310002', 'bob183@example.com', '{"full_name": "Bob Libre"}', now()),
    ('18318318-0000-0000-0000-000000000003', '22670183003', 'nora183@example.com', '{"full_name": "Nora Invitée"}', now()),
    ('18318318-0000-0000-0000-000000000004', '22670183004', 'ali183@example.com', '{"full_name": "Ali Curieux"}', now());
insert into orgs (id, name, slug, profile, default_currency, plan, events_allowed) values
    ('18318318-1111-0000-0000-000000000001', 'Awa Fêtes 183', 'awa-fetes-183', 'events', 'XOF', 'pro', true),
    ('18318318-1111-0000-0000-000000000002', 'Bob Fêtes 183', 'bob-fetes-183', 'events', 'XOF', 'free', true);
insert into memberships (user_id, org_id, role, scope_kind, scope_id, visibility) values
    ('18318318-0000-0000-0000-000000000001', '18318318-1111-0000-0000-000000000001', 'owner', 'org', '18318318-1111-0000-0000-000000000001', 'full'),
    ('18318318-0000-0000-0000-000000000002', '18318318-1111-0000-0000-000000000002', 'owner', 'org', '18318318-1111-0000-0000-000000000002', 'full');
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, tz, published, album_on)
values
    ('18318318-2222-0000-0000-000000000001', '18318318-1111-0000-0000-000000000001', '18318318-0000-0000-0000-000000000001', 'mariage', 'come',
     'mariage-awa-183', 'aaaaaaaaaaaaaaaaaaaaa183', 'bbbbbbbbbbbbbbbbbbbbb183', 'Mariage Awa', now() + interval '10 days', 'Ouaga 2000', '{}', 'Africa/Ouagadougou', false, true),
    ('18318318-2222-0000-0000-000000000002', '18318318-1111-0000-0000-000000000002', '18318318-0000-0000-0000-000000000002', 'gala', 'gala',
     'fete-bob-183', 'ccccccccccccccccccccc183', 'ddddddddddddddddddddd183', 'Fête Bob', now() + interval '10 days', 'Bazoulé', '{}', 'Africa/Ouagadougou', true, false),
    ('18318318-2222-0000-0000-000000000003', '18318318-1111-0000-0000-000000000001', '18318318-0000-0000-0000-000000000001', 'gala', 'gala',
     'soiree-awa-183', 'eeeeeeeeeeeeeeeeeeeee183', 'fffffffffffffffffffff183', 'Soirée Awa', now() + interval '10 days', 'Ouaga', '{}', 'Africa/Ouagadougou', true, true),
    ('18318318-2222-0000-0000-000000000004', '18318318-1111-0000-0000-000000000001', '18318318-0000-0000-0000-000000000001', 'gala', 'gala',
     'gala-annule-183', 'ggggggggggggggggggggg183', 'hhhhhhhhhhhhhhhhhhhhh183', 'Gala annulé', now() + interval '10 days', 'Ouaga', '{}', 'Africa/Ouagadougou', true, true);
insert into events (id, org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, place, content, tz, published, album_on, rsvp_on, tickets_on, doc)
values
    ('18318318-2222-0000-0000-000000000005', '18318318-1111-0000-0000-000000000001', '18318318-0000-0000-0000-000000000001', 'gala', 'gala',
     'sans-reponse-183', 'iiiiiiiiiiiiiiiiiiiii183', 'jjjjjjjjjjjjjjjjjjjjj183', 'Sans réponse', now() + interval '10 days', 'Ouaga', '{}', 'Africa/Ouagadougou', true, false, false, false, null),
    ('18318318-2222-0000-0000-000000000006', '18318318-1111-0000-0000-000000000001', '18318318-0000-0000-0000-000000000001', 'gala', 'gala',
     'close-183', 'kkkkkkkkkkkkkkkkkkkkk183', 'lllllllllllllllllllll183', 'Close', now() + interval '10 days', 'Ouaga', '{}', 'Africa/Ouagadougou', true, false, true, false,
     '{"blocks": [{"type": "rsvp", "props": {"closes": "2020-01-01"}}]}');
update events set album_review = false where id in ('18318318-2222-0000-0000-000000000003', '18318318-2222-0000-0000-000000000004');
-- a nameless account: a phone, no name anywhere
insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('18318318-0000-0000-0000-000000000005', '22670183005', null, '{}', now());
-- a free business's card opened before 182 (as 182's test does): the column set directly
alter table events disable trigger events_album_guard;
update events set album_on = true where id = '18318318-2222-0000-0000-000000000002';
alter table events enable trigger events_album_guard;

create temp table t183 (k text primary key, v text);
grant all on t183 to anon, authenticated;

-- 1. signed out
set role anon;
do $$
declare v_err text;
begin
    begin perform event_presence_confirm('mariage-awa-183', 'aaaaaaaaaaaaaaaaaaaaa183', 2, null); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    insert into t183 values ('anon_confirm', v_err);
    begin perform event_album_add('mariage-awa-183', 'aaaaaaaaaaaaaaaaaaaaa183', 'jpg', 'Nora', null, 'phone-aaaaaaaaaaaaaaaa'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    insert into t183 values ('anon_album', v_err);
end $$;
reset role;
do $$ begin
    assert (select v from t183 where k = 'anon_confirm') like '%permission denied%', 'anon cannot even call it: ' || (select v from t183 where k = 'anon_confirm');
    assert (select v from t183 where k = 'anon_album') like 'Pour ajouter vos photos : « Confirmer ma présence »%', 'the old door says the way: ' || (select v from t183 where k = 'anon_album');
end $$;
do $$
declare v_err text;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '', true);
    begin perform event_presence_confirm('mariage-awa-183', 'aaaaaaaaaaaaaaaaaaaaa183', 2, null); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Connectez-vous pour confirmer votre présence.', 'no account, no confirmation: ' || v_err;
    begin perform event_album_add_guest('mariage-awa-183', 'jpg'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Connectez-vous pour ajouter vos photos.', 'no account, no photo: ' || v_err;
    reset role;
    raise notice 'PASS: signed out, no confirmation and no photo (the old door says the way)';
end $$;

-- 2. a guest confirms (a draft, through its preview link)
do $$
declare j jsonb; v_err text;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000003', true);
    begin perform event_presence_confirm('mariage-awa-183', null, 2, null); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Cette carte n''est pas ouverte.', 'a draft without its link: ' || v_err;
    begin perform event_presence_confirm('mariage-awa-183', 'aaaaaaaaaaaaaaaaaaaaa183', 11, null); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Entre 1 et 10 personnes.', 'how many, bounded: ' || v_err;
    j := event_presence_confirm('mariage-awa-183', 'aaaaaaaaaaaaaaaaaaaaa183', 2, 'Avec plaisir', true);
    insert into t183 values ('first', j::text);
    reset role;
end $$;
do $$
declare r event_rsvps;
begin
    assert (select (v::jsonb ->> 'first')::boolean and v::jsonb ->> 'title' = 'Mariage Awa' from t183 where k = 'first'), 'the first: ' || (select v from t183 where k = 'first');
    assert (select count(*) from event_rsvps where event_id = '18318318-2222-0000-0000-000000000001') = 1, 'one answer';
    select * into r from event_rsvps where event_id = '18318318-2222-0000-0000-000000000001';
    assert r.user_id = '18318318-0000-0000-0000-000000000003' and r.name = 'Nora Invitée' and r.people = 2 and r.answer = 'oui'
       and r.message = 'Avec plaisir' and r.extra ->> 'whatsapp' = '+22670183003' and r.extra ->> 'preview' = 'aaaaaaaaaaaaaaaaaaaaa183',
       'the account''s name and number: ' || row_to_json(r)::text;
    assert (select count(*) from notifications where recipient_id = '18318318-0000-0000-0000-000000000003' and kind = 'event_presence_guest'
              and message = 'Présence confirmée à « Mariage Awa » : vous pouvez ajouter vos photos.' and scope = 'customer') = 1, 'the guest''s bell';
    assert (select count(*) from notifications where recipient_id = '18318318-0000-0000-0000-000000000001' and kind = 'event_presence'
              and message = 'Nora Invitée a confirmé sa présence (2 personnes) — Mariage Awa' and org_id = '18318318-1111-0000-0000-000000000001'
              and scope = 'shop') = 1, 'the organiser''s bell';
    assert (select count(*) from notifications where kind = 'event_presence' and message ~ '70183003') = 0, 'no number in the organiser''s bell';
    raise notice 'PASS: a guest confirms — one answer, the account''s name and the number she shared, the guest''s bell and the organiser''s';
end $$;

-- 3. again
do $$
declare j jsonb;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000003', true);
    j := event_presence_confirm('mariage-awa-183', 'aaaaaaaaaaaaaaaaaaaaa183', 3, null);
    assert (j ->> 'first')::boolean = false, 'not the first: ' || j::text;
    reset role;
    assert (select count(*) from event_rsvps where event_id = '18318318-2222-0000-0000-000000000001') = 1, 'still one answer';
    assert (select people = 3 and message is null from event_rsvps where event_id = '18318318-2222-0000-0000-000000000001'), 'how many and the word changed';
    assert (select not (extra ? 'whatsapp') and extra ->> 'preview' = 'aaaaaaaaaaaaaaaaaaaaa183' from event_rsvps where event_id = '18318318-2222-0000-0000-000000000001'),
           'not shared this time: the number taken back, the draft''s link kept';
    assert (select count(*) from notifications where kind in ('event_presence', 'event_presence_guest') and params ->> 'event_id' = '18318318-2222-0000-0000-000000000001') = 2,
           'no second bell';
    raise notice 'PASS: confirming again changes how many and the word — one answer, no second bell; the number not shared again is taken back';
end $$;

-- 4. « Mes invitations »; the confirmation screen
do $$
declare j jsonb; i jsonb;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000003', true);
    j := my_event_invitations();
    assert jsonb_array_length(j) = 1, 'one card: ' || j::text;
    assert j -> 0 ->> 'slug' = 'mariage-awa-183' and j -> 0 ->> 'preview' = 'aaaaaaaaaaaaaaaaaaaaa183' and (j -> 0 ->> 'people')::int = 3
       and (j -> 0 ->> 'photos_used')::int = 0 and (j -> 0 ->> 'photos_limit')::int = 5 and (j -> 0 ->> 'album_allowed')::boolean
       and j -> 0 ->> 'place' = 'Ouaga 2000' and j -> 0 ->> 'tz' = 'Africa/Ouagadougou', 'what the list shows: ' || j::text;
    i := event_presence_info('mariage-awa-183', 'aaaaaaaaaaaaaaaaaaaaa183');
    assert i ->> 'title' = 'Mariage Awa' and (i ->> 'open')::boolean and (i -> 'mine' ->> 'people')::int = 3, 'the screen knows it is theirs: ' || i::text;
    assert (i ->> 'phone')::boolean and not (i -> 'mine' ->> 'share_phone')::boolean and not (i ->> 'cancelled')::boolean,
           'a number to share, not shared now: ' || i::text;
    assert event_presence_info('mariage-awa-183', null) is null, 'a draft without its link: nothing';
    -- another account: nothing of Nora's
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000004', true);
    assert my_event_invitations() = '[]'::jsonb, 'Ali has none';
    assert event_presence_info('mariage-awa-183', 'aaaaaaaaaaaaaaaaaaaaa183') -> 'mine' = 'null'::jsonb, 'not Ali''s answer';
    reset role;
    -- published, the draft's link is no longer handed out
    update events set published = true where id = '18318318-2222-0000-0000-000000000001';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000003', true);
    assert my_event_invitations() -> 0 -> 'preview' = 'null'::jsonb, 'a published card: no preview link';
    reset role;
    raise notice 'PASS: « Mes invitations » lists the card (its draft link only to the guest who came through it); the screen knows the answer';
end $$;

-- 5. the photos
do $$
declare v_err text; k text; n int;
begin
    set local role authenticated;
    -- Ali has not confirmed
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000004', true);
    begin perform event_album_add_guest('mariage-awa-183', 'jpg'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Confirmez d''abord votre présence pour ajouter vos photos.', 'not confirmed, no photo: ' || v_err;
    -- Nora: five
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000003', true);
    for n in 1..5 loop
        k := event_album_add_guest('mariage-awa-183', 'jpg');
        assert k ~ '^events/18318318-2222-0000-0000-000000000001/[0-9a-f]{32}\.jpg$', 'a key: ' || k;
        if n <= 2 then
            assert event_album_done(k, null, 1000), 'her own slot completed';
        end if;
    end loop;
    begin perform event_album_add_guest('mariage-awa-183', 'png'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Vous avez déposé vos 5 photos : c''est le maximum par invité.', 'the sixth refused: ' || v_err;
    assert (my_event_invitations() -> 0 ->> 'photos_used')::int = 5, 'five used';
    assert jsonb_array_length(my_event_invitations() -> 0 -> 'photos') = 2, 'her two stored photos listed';
    reset role;
    assert (select count(*) from event_pictures where event_id = '18318318-2222-0000-0000-000000000001' and user_id = '18318318-0000-0000-0000-000000000003'
              and guest = 'Nora Invitée' and source = 'guest') = 5, 'five rows, under her name';
    raise notice 'PASS: a guest who has not confirmed adds none; a confirmed guest adds five, the sixth refused; her own slots completed';
end $$;
-- a draft's slot completed by its own account only
do $$
declare v_err text; k text;
begin
    update events set published = false where id = '18318318-2222-0000-0000-000000000001';
    delete from event_pictures where user_id = '18318318-0000-0000-0000-000000000003' and state = 'slot';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000003', true);
    k := event_album_add_guest('mariage-awa-183', 'webp');
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000004', true);
    begin perform event_album_done(k, null, 10); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Cette carte n''est pas ouverte.', 'another account cannot complete a draft''s slot: ' || v_err;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000003', true);
    assert event_album_done(k, null, 10), 'its own account does, the card a draft';
    reset role;
    raise notice 'PASS: a draft''s photo is completed by its own account, not another''s';
end $$;

-- 6. a free business's album
do $$
declare v_err text;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000004', true);
    perform event_presence_confirm('fete-bob-183', null, 1, null);
    begin perform event_album_add_guest('fete-bob-183', 'jpg'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'L''album de cette carte est fermé.', 'a free album takes none: ' || v_err;
    assert (select (x ->> 'album_allowed')::boolean = false from jsonb_array_elements(my_event_invitations()) x where x ->> 'slug' = 'fete-bob-183'),
           'the list says so';
    reset role;
    raise notice 'PASS: a free business''s album takes no guest photo (182)';
end $$;

-- 8. a nameless account: « Invité », never its phone; the number only when shared
do $$
declare j jsonb; k text; i jsonb;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000005', true);
    j := event_presence_confirm('soiree-awa-183', null, 1, null);
    k := event_album_add_guest('soiree-awa-183', 'jpg');
    assert event_album_done(k, null, 100), 'stored';
    i := event_presence_info('soiree-awa-183', null);
    assert (i ->> 'phone')::boolean, 'the account has a number to share: ' || i::text;
    reset role;
    assert (select name = 'Invité' and not (extra ? 'whatsapp') from event_rsvps
             where event_id = '18318318-2222-0000-0000-000000000003' and user_id = '18318318-0000-0000-0000-000000000005'),
           'the answer: « Invité », no number';
    assert (select guest from event_pictures where key = k) = 'Invité', 'the photo''s name';
    assert (select count(*) from notifications where kind = 'event_presence' and params ->> 'event_id' = '18318318-2222-0000-0000-000000000003'
              and message = 'Invité a confirmé sa présence (1 personne) — Soirée Awa' and params ->> 'name' = 'Invité') = 1, 'the organiser''s bell says « Invité »';
    -- (129's « new account » bell to the platform is the platform's own: not counted)
    assert (select count(*) from notifications where kind like 'event\_%' and (message || params::text) ~ '70183005') = 0,
           'no digit of the phone in any event bell';
    set local role anon;
    j := event_album('soiree-awa-183', null);
    reset role;
    assert jsonb_array_length(j) = 1 and j -> 0 ->> 'guest' = 'Invité' and j::text !~ '70183005', 'anon''s album: « Invité »: ' || j::text;
    raise notice 'PASS: a nameless account is « Invité » on its answer, its photo (anon''s album) and the organiser''s bell — never its phone';
end $$;
do $$
declare v_err text;
begin
    set local role authenticated;
    -- Nora confirmed the wedding, not the soirée: no photo for it
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000003', true);
    begin perform event_album_add_guest('soiree-awa-183', 'jpg'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Confirmez d''abord votre présence pour ajouter vos photos.', 'confirmed on A, a photo for B: ' || v_err;
    -- shared, then not
    perform event_presence_confirm('soiree-awa-183', null, 2, null, true);
    reset role;
    assert (select extra ->> 'whatsapp' from event_rsvps where event_id = '18318318-2222-0000-0000-000000000003'
              and user_id = '18318318-0000-0000-0000-000000000003') = '+22670183003', 'shared: the organiser has it';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000003', true);
    assert (event_presence_info('soiree-awa-183', null) -> 'mine' ->> 'share_phone')::boolean, 'the screen knows it is shared';
    perform event_presence_confirm('soiree-awa-183', null, 2, null, false);
    reset role;
    assert (select not (extra ? 'whatsapp') from event_rsvps where event_id = '18318318-2222-0000-0000-000000000003'
              and user_id = '18318318-0000-0000-0000-000000000003'), 'not shared: taken back';
    raise notice 'PASS: confirmed on one card, no photo for another; the number shared by choice, taken back by choice';
end $$;

-- 9. refused
do $$
declare v_err text;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000003', true);
    -- a cancelled card: confirmed before, then cancelled
    perform event_presence_confirm('gala-annule-183', null, 1, null);
    reset role;
    update events set cancelled_at = now() where id = '18318318-2222-0000-0000-000000000004';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000003', true);
    begin perform event_presence_confirm('gala-annule-183', null, 1, null); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Cet événement est annulé.', 'a cancelled card: no confirmation: ' || v_err;
    begin perform event_album_add_guest('gala-annule-183', 'jpg'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Cet événement est annulé.', 'a cancelled card: no photo: ' || v_err;
    assert not (event_presence_info('gala-annule-183', null) ->> 'open')::boolean
       and (event_presence_info('gala-annule-183', null) ->> 'cancelled')::boolean, 'the screen says so';
    -- answers off, tickets off
    begin perform event_presence_confirm('sans-reponse-183', null, 1, null); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Les réponses sont fermées pour cet événement.', 'answers and tickets off: ' || v_err;
    -- the closing date passed
    begin perform event_presence_confirm('close-183', null, 1, null); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Les réponses sont closes depuis le 01/01/2020.', 'closed: ' || v_err;
    -- a word over 500
    begin perform event_presence_confirm('soiree-awa-183', null, 1, repeat('a', 501)); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Un mot de 500 caractères au plus.', 'the word bounded: ' || v_err;
    reset role;
    -- a draft whose link changed since the guest confirmed through it
    update events set preview_token = 'zzzzzzzzzzzzzzzzzzzzz183' where id = '18318318-2222-0000-0000-000000000001';
    delete from event_pictures where user_id = '18318318-0000-0000-0000-000000000003' and state = 'slot';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000003', true);
    begin perform event_album_add_guest('mariage-awa-183', 'jpg'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Cette carte n''est pas ouverte.', 'a draft no longer hers: ' || v_err;
    -- its organiser, confirmed on her own draft, still can
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000001', true);
    perform event_presence_confirm('mariage-awa-183', 'zzzzzzzzzzzzzzzzzzzzz183', 1, null);
    reset role;
    update event_rsvps set extra = extra - 'preview' where user_id = '18318318-0000-0000-0000-000000000001';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000001', true);
    assert event_album_add_guest('mariage-awa-183', 'jpg') is not null, 'the organiser''s own draft';
    reset role;
    update events set preview_token = 'aaaaaaaaaaaaaaaaaaaaa183' where id = '18318318-2222-0000-0000-000000000001';
    raise notice 'PASS: refused — a cancelled card, answers and tickets off, the closing date passed, a word over 500, a card not confirmed, a draft whose link changed';
end $$;

-- 10. the ten minutes; the switches
do $$
declare v_err text; k text; n int;
begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000005', true);
    -- one stored (8.), four on their way: the sixth refused
    for n in 1..4 loop perform event_album_add_guest('soiree-awa-183', 'jpg'); end loop;
    begin perform event_album_add_guest('soiree-awa-183', 'jpg'); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Vous avez déposé vos 5 photos : c''est le maximum par invité.', 'five with the slots: ' || v_err;
    reset role;
    select key into k from event_pictures where user_id = '18318318-0000-0000-0000-000000000005' and state = 'slot' limit 1;
    update event_pictures set created_at = now() - interval '11 minutes'
     where user_id = '18318318-0000-0000-0000-000000000005' and state = 'slot';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', '18318318-0000-0000-0000-000000000005', true);
    assert (select (x ->> 'photos_used')::int = 1 from jsonb_array_elements(my_event_invitations()) x where x ->> 'slug' = 'soiree-awa-183'),
           'the failed uploads no longer count';
    assert event_album_add_guest('soiree-awa-183', 'jpg') is not null, 'the place given back';
    begin perform event_album_done(k, null, 10); v_err := 'TAKEN';
    exception when others then v_err := sqlerrm; end;
    assert v_err = 'Envoi inconnu.', 'an old slot cannot be completed: ' || v_err;
    reset role;
    assert notification_type_of('event_presence', '{"to": "shop"}') = 'shop_orders'
       and notification_type_of('event_presence_guest', '{"to": "customer"}') = 'bookings'
       and notification_type_of('booking_accepted', '{"to": "shop"}') = 'shop_orders'
       and notification_type_of('order_ready', '{"to": "customer"}') = 'order_updates'
       and notification_type_of('event_tomorrow', '{"to": "shop"}') is null, 'the switches';
    raise notice 'PASS: a slot older than ten minutes no longer counts nor completes; the two bells answer to switches';
end $$;

-- 7. the doors
do $$ begin
    assert not has_function_privilege('anon', 'event_presence_confirm(text, text, integer, text, boolean)', 'execute')
       and not has_function_privilege('anon', 'my_event_invitations()', 'execute')
       and not has_function_privilege('anon', 'event_album_add_guest(text, text)', 'execute')
       and not has_function_privilege('anon', 'event_presence_info(text, text)', 'execute')
       and not has_function_privilege('anon', 'event_presence_who(uuid)', 'execute')
       and not has_function_privilege('authenticated', 'event_presence_who(uuid)', 'execute')
       and not has_function_privilege('public', 'event_presence_confirm(text, text, integer, text, boolean)', 'execute'), 'closed to anon and public';
    assert has_function_privilege('authenticated', 'event_presence_confirm(text, text, integer, text, boolean)', 'execute')
       and has_function_privilege('authenticated', 'my_event_invitations()', 'execute')
       and has_function_privilege('authenticated', 'event_album_add_guest(text, text)', 'execute')
       and has_function_privilege('authenticated', 'event_presence_info(text, text)', 'execute')
       and has_function_privilege('authenticated', 'event_album_done(text, text, integer)', 'execute'), 'open to the signed-in';
    assert (select count(*) from pg_proc where proname = 'event_album_add') = 1, 'one old door';
    assert (select count(*) from pg_proc where proname = 'event_presence_confirm') = 1, 'one confirmation, no overload of before';
    raise notice 'PASS: the doors — anon executes none of the new functions';
end $$;
rollback;
