-- ============================================================
-- 087_academy.sql — Académie Mara: learning by doing, paid in cauris.
--
-- The owner: an animated training that helps people understand the app.
-- Two kinds of lesson, one list:
--
--   * A guide — watched, step by step, in the app — is done when it has
--     been seen to the end.
--   * A mission — « Encaissez votre première vente » — is done when the
--     thing is done, and only then: complete_lesson() asks the business's
--     own data (a sale exists, three articles have their photo...), so a
--     mission cannot be ticked without being lived.
--
-- Each lesson earns its business the « lesson » rule's cauris (084), once
-- per lesson per business — not per person, or a shop with ten staff
-- would farm it. Each person climbs the levels on their own: Apprenti,
-- Commerçant once half the lessons are done, Maître with all of them.
-- An association follows the lessons of its kind and earns no cauris
-- (084's rule), but its people still climb.
-- ============================================================

create table if not exists academy_lessons (
    key      text primary key,
    title    text not null,
    kind     text not null check (kind in ('guide', 'mission')),
    profiles text[] not null default array['retail', 'farm'],
    minutes  integer not null default 1,
    sort     integer not null default 0
);
alter table academy_lessons enable row level security;

insert into academy_lessons (key, title, kind, profiles, minutes, sort) values
    ('welcome',      'Bienvenue sur Mara',                     'guide',   array['retail', 'farm', 'association', 'church'], 1, 10),
    ('first_article','Mettre un article en vente',             'mission', array['retail', 'farm'], 2, 20),
    ('vitrine_open', 'Ouvrir sa vitrine',                      'mission', array['retail', 'farm'], 2, 30),
    ('photos',       'Trois articles en photo',                'mission', array['retail', 'farm'], 3, 40),
    ('first_sale',   'Encaisser une vente',                    'mission', array['retail'],         2, 50),
    ('farm_log',     'Tenir le cahier de la ferme',            'mission', array['farm'],           2, 55),
    ('first_order',  'Accepter une commande de la vitrine',    'mission', array['retail', 'farm'], 2, 60),
    ('cauris',       'Gagner et dépenser des cauris',          'guide',   array['retail', 'farm'], 2, 70),
    ('league',       'Le classement de la semaine',            'guide',   array['retail', 'farm'], 1, 80)
on conflict (key) do nothing;

create table if not exists academy_done (
    org_id  uuid not null references orgs(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    lesson  text not null references academy_lessons(key) on delete cascade,
    done_at timestamptz not null default now(),
    primary key (org_id, user_id, lesson)
);
alter table academy_done enable row level security;

-- Is a mission lived, by the business's own data?
create or replace function academy_mission_met(p_org_id uuid, p_lesson text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select case p_lesson
        when 'first_article' then exists (select 1 from products
                                           where org_id = p_org_id and is_active and is_published)
        when 'vitrine_open'  then exists (select 1 from orgs
                                           where id = p_org_id and storefront_enabled)
        when 'photos'        then (select count(*) from products p
                                    where p.org_id = p_org_id and p.is_active and p.is_published
                                      and exists (select 1 from documents d where d.product_id = p.id)) >= 3
        when 'first_sale'    then exists (select 1 from sales where org_id = p_org_id and kind = 'sale')
        when 'farm_log'      then exists (select 1 from flock_events e join flocks f on f.id = e.flock_id
                                           where f.org_id = p_org_id)
        when 'first_order'   then exists (select 1 from orders where org_id = p_org_id
                                           and status in ('accepted', 'ready', 'picked_up', 'delivered'))
        else true
    end;
$$;

-- A lesson finished: seen to the end, or — for a mission — lived.
create or replace function complete_lesson(p_org_id uuid, p_lesson text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_lesson academy_lessons%rowtype;
    v_earned int := 0;
begin
    if auth.uid() is null or not is_org_member(p_org_id) then
        raise exception 'Leçon réservée aux membres de l''entreprise';
    end if;
    select * into v_lesson from academy_lessons where key = p_lesson;
    if not found then
        raise exception 'Leçon inconnue : %', p_lesson;
    end if;
    if v_lesson.kind = 'mission' and not academy_mission_met(p_org_id, p_lesson) then
        return jsonb_build_object('done', false, 'earned', 0);
    end if;
    insert into academy_done (org_id, user_id, lesson)
    values (p_org_id, auth.uid(), p_lesson)
    on conflict do nothing;
    v_earned := cauris_award(p_org_id, 'lesson', p_lesson);
    return jsonb_build_object('done', true, 'earned', v_earned);
end;
$$;

-- The person's academy for this business: every lesson of its kind, done
-- or not, the missions already lived (ready to collect), and the level.
create or replace function my_academy(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, auth
as $$
    with o as (select * from orgs where id = p_org_id and is_org_member(p_org_id)),
    l as (
        select a.*, exists (select 1 from academy_done d
                             where d.org_id = p_org_id and d.user_id = auth.uid()
                               and d.lesson = a.key) as done
          from academy_lessons a, o
         where o.profile = any (a.profiles)
    ),
    n as (select count(*) filter (where done) as done, count(*) as total from l)
    select jsonb_build_object(
        'lessons', coalesce((select jsonb_agg(jsonb_build_object(
                       'key', l.key, 'title', l.title, 'kind', l.kind,
                       'minutes', l.minutes, 'done', l.done,
                       'ready', l.kind = 'mission' and not l.done
                                and academy_mission_met(p_org_id, l.key))
                       order by l.sort) from l), '[]'::jsonb),
        'done', n.done,
        'total', n.total,
        'level', case when n.total > 0 and n.done >= n.total then 'Maître'
                      when n.done * 2 >= n.total and n.total > 0 then 'Commerçant'
                      else 'Apprenti' end,
        'cauris_each', coalesce((select points from cauris_rules where key = 'lesson'), 0)
    )
    from n, o;
$$;

revoke execute on function academy_mission_met(uuid, text) from public;
revoke execute on function complete_lesson(uuid, text)     from public;
revoke execute on function my_academy(uuid)                from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function academy_mission_met(uuid, text) from anon;
        revoke execute on function complete_lesson(uuid, text)     from anon;
        revoke execute on function my_academy(uuid)                from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function academy_mission_met(uuid, text) from authenticated;
        grant execute on function complete_lesson(uuid, text)      to authenticated;
        grant execute on function my_academy(uuid)                 to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
