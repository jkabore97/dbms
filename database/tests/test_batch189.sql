-- ============================================================
-- test_batch189.sql — 189: the guests hear that the album is open.
--
-- The claims:
--   1. installed twice, the same: on the album's first day, from 9 h on
--      the card's own clock, each guest who said yes with an account gets
--      one bell — « L'album de « … » est ouvert : ajoutez vos photos
--      jusqu'au samedi 28 novembre. », the confirmation's kind, opening
--      « Mes invitations »; once;
--   2. before 9 h there, a draft, a cancelled card, an album off, a free
--      business's (its album shut, 182), a « non », a guest with no
--      account: nothing;
--   3. the install counts past albums and those told by hand as told; the
--      tick is nobody's to call.
-- Wrapped in one transaction rolled back.
-- ============================================================
\set ON_ERROR_STOP on

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;
\i database/migrations/189_album_open_notice.sql
\i database/migrations/189_album_open_notice.sql

begin;
delete from notifications;
-- only this test's cards count: the others are told already
update events set album_announced_at = now() where album_announced_at is null;

insert into auth.users (id, phone, email, raw_user_meta_data, created_at) values
    ('18918918-0000-0000-0000-000000000001', '22618910001', 'awa189@example.com', '{"full_name": "Awa Planner"}', now()),
    ('18918918-0000-0000-0000-000000000002', '22618910002', 'rose189@example.com', '{"full_name": "Tanti Rose"}', now()),
    ('18918918-0000-0000-0000-000000000003', '22618910003', 'sam189@example.com', '{"full_name": "Oncle Sam"}', now()),
    ('18918918-0000-0000-0000-000000000004', '22618910004', 'lea189@example.com', '{"full_name": "Cousine Léa"}', now());
insert into profiles (id, full_name) values
    ('18918918-0000-0000-0000-000000000001', 'Awa'), ('18918918-0000-0000-0000-000000000002', 'Rose'),
    ('18918918-0000-0000-0000-000000000003', 'Sam'), ('18918918-0000-0000-0000-000000000004', 'Léa')
on conflict (id) do update set full_name = excluded.full_name;
insert into orgs (id, name, slug, profile, default_currency, plan) values
    ('18918918-1111-0000-0000-000000000001', 'Awa Événements 189', 'awa-evenements-189', 'events', 'XOF', 'pro'),
    ('18918918-1111-0000-0000-000000000002', 'Gratuit 189', 'gratuit-189', 'events', 'XOF', 'free');

-- Two clocks chosen from now: one where it is 12 h, one where it is 3 h.
create temp table c189 as
select (((12 - h) + 60) % 24) - 12 as noon, (((3 - h) + 60) % 24) - 12 as night
  from (select extract(hour from now() at time zone 'UTC')::int as h) x;
create temp table z189 as
select to_char(make_interval(hours => abs(noon)), '"' || case when noon < 0 then '-' else '+' end || '"HH24:MI') as noon_tz,
       to_char(make_interval(hours => abs(night)), '"' || case when night < 0 then '-' else '+' end || '"HH24:MI') as night_tz
  from c189;

insert into events (org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, content, tz, published, album_on, album_until, cancelled_at)
select '18918918-1111-0000-0000-000000000001'::uuid, '18918918-0000-0000-0000-000000000001'::uuid, 'mariage', 'come',
       s.slug, left(md5(s.slug || 'p'), 24), left(md5(s.slug || 'e'), 24), s.title, now(), '{}'::jsonb, s.tz, s.pub, s.album, '2026-11-28'::date, s.cancelled
  from z189, lateral (values
       ('noces-189', 'Inès & Thomas', noon_tz, true, true, null::timestamptz),
       ('nuit-189', 'À l''aube', night_tz, true, true, null),
       ('brouillon-189', 'Brouillon', noon_tz, false, true, null),
       ('annule-189', 'Annulé', noon_tz, true, true, now()),
       ('sans-album-189', 'Sans album', noon_tz, true, false, null)) as s(slug, title, tz, pub, album, cancelled);
-- a free business's card, its album on before it went free
insert into events (org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, content, tz, published, album_on)
select '18918918-1111-0000-0000-000000000002'::uuid, '18918918-0000-0000-0000-000000000001'::uuid, 'gala', 'gala',
       'gratuit-189', left(md5('g189p'), 24), left(md5('g189e'), 24), 'Gratuit', now(), '{}'::jsonb, noon_tz, true, false from z189;
alter table events disable trigger events_album_guard;
update events set album_on = true where slug = 'gratuit-189';
alter table events enable trigger events_album_guard;
-- album_until in the past for « today »? keep it after today on every clock
update events set album_until = greatest(album_until, event_local_date(now(), tz) + 3) where slug like '%-189';

insert into event_rsvps (event_id, name, people, answer, user_id)
select e.id, g.name, 1, g.answer, g.uid::uuid
  from events e, (values
       ('Tanti Rose', 'oui', '18918918-0000-0000-0000-000000000002'),
       ('Oncle Sam', 'oui', '18918918-0000-0000-0000-000000000003'),
       ('Cousine Léa', 'non', '18918918-0000-0000-0000-000000000004'),
       ('Sans compte', 'oui', null)) as g(name, answer, uid)
 where e.slug like '%-189';

-- 1 and 2. the tick
do $$
declare v_n int; n record;
begin
    v_n := events_album_tick();
    assert v_n = 1, 'one card at 9 h or later, published, open: ' || v_n;
    assert (select count(*) from notifications where params ->> 'album' = 'open') = 2, 'the two who said yes with an account: '
        || (select count(*) from notifications where params ->> 'album' = 'open');
    select * into n from notifications where recipient_id = '18918918-0000-0000-0000-000000000002' and params ->> 'album' = 'open';
    assert n.kind = 'event_presence_guest' and n.org_id is null, 'the confirmation''s kind, the guest''s own';
    assert n.message = 'L''album de « Inès & Thomas » est ouvert : ajoutez vos photos jusqu''au '
        || fr_day_month((select album_until from events where slug = 'noces-189')) || '.', 'in words: ' || n.message;
    assert n.params ->> 'album' = 'open' and n.params ->> 'slug' = 'noces-189', 'in facts: ' || n.params::text;
    assert not exists (select 1 from notifications where recipient_id = '18918918-0000-0000-0000-000000000004' and params ->> 'album' = 'open'), 'the « non »: nothing';
    assert (select album_announced_at from events where slug = 'noces-189') is not null, 'the card remembers it';
    assert (select count(*) from events where slug like '%-189' and album_announced_at is not null) = 1,
        'before 9 h, the draft, the cancelled, no album, the free one: not told';
    assert events_album_tick() = 0 and (select count(*) from notifications where params ->> 'album' = 'open') = 2, 'told once';
    assert fr_day_month('2026-11-28') = 'samedi 28 novembre' and fr_day_month('2027-02-01') = 'lundi 1 février', 'the days in French';
    raise notice 'PASS: on the first day from 9 h there, each guest who said yes with an account — once; the others nothing';
end $$;

-- 3. the install and the doors
do $$
begin
    insert into events (org_id, created_by, kind, card, slug, preview_token, edit_token, title, starts_at, content, tz, published, album_on)
    values ('18918918-1111-0000-0000-000000000001', '18918918-0000-0000-0000-000000000001', 'gala', 'gala',
            'passe-189', left(md5('passe-189p'), 24), left(md5('passe-189e'), 24), 'Passé', now() - interval '3 days', '{}'::jsonb, 'Africa/Ouagadougou', true, true);
end $$;
\i database/migrations/189_album_open_notice.sql
do $$
begin
    assert (select album_announced_at from events where slug = 'passe-189') is not null, 'a past album, told on install';
    assert (select album_announced_at from events where slug = 'nuit-189') is null, 'today''s, left to the tick';
    assert not has_function_privilege('anon', 'events_album_tick()', 'execute')
       and not has_function_privilege('authenticated', 'events_album_tick()', 'execute'), 'nobody''s to call';
    raise notice 'PASS: the install counts the past as told; the doors';
end $$;
rollback;
