-- ============================================================
-- test_batch126.sql — « Aide Mara »: the support e-mail, hours and
-- WhatsApp number, for the page /aide and the app (126).
--
-- The claims (the platform's help — the same for a shop, a farm, an
-- association, a shopper or a courier):
--   * the defaults: hello@kaj-consulting.com, « 24 h/24, 7 j/7 », no
--     WhatsApp number — support_contacts() says the three;
--   * the checks: a bad e-mail is refused, hours too long (or empty) are
--     refused, each in French; a WhatsApp number pasted with invisible
--     direction marks or non-breaking hyphens is taken (113 refused it),
--     a word still refused;
--   * a stranger (anon) and a signed-in person read support_contacts();
--   * a stranger writes nothing: platform_set_setting and the table are
--     closed to anon, the triggers to everybody;
--   * platform_set_setting takes both settings for a platform admin
--     (journaled, « Annuler ») and refuses them to anybody else;
--   * P1: installing 126 changes nothing else — every other setting, and
--     what the vitrines of the three kinds show and the shopper's page
--     reads, answer for answer.
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
-- Earlier suites hand the app's roles every table and function: taken
-- back, then 126 again, so what follows is 126's own doors.
do $$ begin
    if to_regprocedure('support_contacts()') is not null then
        revoke all on function support_contacts() from anon, authenticated;
    end if;
end $$;
\i database/migrations/126_support.sql

\set mara    '''12612612-0000-0000-0000-000000000001'''
\set sowner  '''12612612-0000-0000-0000-000000000002'''
\set fowner  '''12612612-0000-0000-0000-000000000003'''
\set aowner  '''12612612-0000-0000-0000-000000000004'''
\set shopper '''12612612-0000-0000-0000-000000000005'''
\set shop    '''12600000-0000-0000-0000-000000000001'''
\set farm    '''12600000-0000-0000-0000-000000000002'''
\set assoc   '''12600000-0000-0000-0000-000000000003'''

create or replace function pg_temp.as126(p_who uuid)
returns void
language sql
as $$ select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true); $$;

-- The message of a refused call, or « (went through) » — never null.
create or replace function pg_temp.refused126(p_sql text, p_role text default null)
returns text
language plpgsql
as $$
begin
    if p_role is not null then
        execute format('set local role %I', p_role);
    end if;
    execute p_sql;
    execute 'reset role';
    return '(went through)';
exception when others then
    execute 'reset role';
    return sqlerrm;
end;
$$;

-- The settings this suite moves, put back at its end.
create temp table b126_saved as
    select key, value from platform_settings
     where key in ('support_whatsapp', 'support_email', 'support_hours');
update platform_settings set value = '""' where key = 'support_whatsapp';

insert into auth.users (id, phone, email, raw_user_meta_data) values
    (:mara,    '+22612601001', 'mara126@example.org',   '{"full_name": "Mara Cent-Vingt-Six"}'),
    (:sowner,  '+22612601002', 'boutique126@example.org', '{"full_name": "Patronne 126"}'),
    (:fowner,  '+22612601003', 'ferme126@example.org',    '{"full_name": "Fermier 126"}'),
    (:aowner,  '+22612601004', 'entraide126@example.org', '{"full_name": "Trésorière 126"}'),
    (:shopper, '+22612601005', 'cliente126@example.org',  '{"full_name": "Cliente 126"}');
update profiles set is_platform_admin = true where id = :mara;
insert into orgs (id, name, slug, profile, default_currency, storefront_enabled) values
    (:shop,  'Boutique 126', 'boutique-126', 'retail',      'XOF', true),
    (:farm,  'Ferme 126',    'ferme-126',    'farm',        'XOF', true),
    (:assoc, 'Entraide 126', 'entraide-126', 'association', 'XOF', true);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :sowner, 'owner', 'org', :shop,  'full'),
    (:farm,  :fowner, 'owner', 'org', :farm,  'full'),
    (:assoc, :aowner, 'owner', 'org', :assoc, 'full');

\echo ''
\echo '--- TEST 1: the defaults — hello@kaj-consulting.com, « 24 h/24, 7 j/7 », no WhatsApp ---'
do $$
declare v jsonb;
begin
    if (select value from platform_settings where key = 'support_email') is distinct from '"hello@kaj-consulting.com"'::jsonb
       or (select value from platform_settings where key = 'support_hours') is distinct from '"24 h/24, 7 j/7"'::jsonb then
        raise exception 'FAIL: the defaults are % and %',
            (select value from platform_settings where key = 'support_email'),
            (select value from platform_settings where key = 'support_hours');
    end if;
    v := support_contacts();
    if v is distinct from '{"email": "hello@kaj-consulting.com", "whatsapp": null, "hours": "24 h/24, 7 j/7"}'::jsonb then
        raise exception 'FAIL: support_contacts() gave %', v;
    end if;
    raise notice 'PASS: the e-mail and the hours as installed, no number; support_contacts() says the three';
end $$;

\echo ''
\echo '--- TEST 2: the checks — a bad e-mail, hours too long or empty refused in French; a pasted number taken ---'
begin;
do $$
declare
    v_bad text;
    v_r   text;
    v_msg_mail  constant text := 'L''e-mail de l''aide : une adresse comme hello@kaj-consulting.com.';
    v_msg_hours constant text := 'Les heures de l''aide : quelques mots, 60 caractères au plus (par exemple 24 h/24, 7 j/7).';
    v_msg_wa    constant text := 'Le numéro WhatsApp de l''aide : l''indicatif du pays puis le numéro, en chiffres (par exemple 22670000000).';
begin
    foreach v_bad in array array['', 'hello', 'hello@', '@kaj-consulting.com', 'hello@kaj',
                                 'hello @kaj-consulting.com', 'hello@kaj-consulting.com ',
                                 'a@b@c.com', 'hello@kaj-consulting.', repeat('a', 110) || '@example.org',
                                 -- Nothing that breaks the page's mailto: link or an attribute.
                                 'a<b@x.io', 'a>b@x.io', 'a"b@x.io', 'a''b@x.io', 'a@x.io?cc=y@z.io',
                                 'a&b@x.io', 'a,b@x.io', 'a;b@x.io', 'a@x;y.io', 'a@x,y.io', 'a@x.i<o',
                                 'a@x.io&body=1', E'a\tb@x.io'] loop
        v_r := pg_temp.refused126(format($q$update platform_settings set value = %L where key = 'support_email'$q$,
                                         to_jsonb(v_bad)));
        if v_r is distinct from v_msg_mail then
            raise exception 'FAIL: the e-mail « % » gave « % »', v_bad, v_r;
        end if;
    end loop;
    v_r := pg_temp.refused126($q$update platform_settings set value = '12' where key = 'support_email'$q$);
    if v_r is distinct from v_msg_mail then
        raise exception 'FAIL: a number for the e-mail gave « % »', v_r;
    end if;
    -- 120 characters, counted as characters (« é » is two bytes): taken.
    update platform_settings set value = to_jsonb(repeat('é', 115) || '@x.io') where key = 'support_email';
    update platform_settings set value = '"aide+mara@marakaj.com"' where key = 'support_email';
    update platform_settings set value = '"aide@marakaj.co.uk"' where key = 'support_email';

    foreach v_bad in array array['', '   ', repeat('x', 61)] loop
        v_r := pg_temp.refused126(format($q$update platform_settings set value = %L where key = 'support_hours'$q$,
                                         to_jsonb(v_bad)));
        if v_r is distinct from v_msg_hours then
            raise exception 'FAIL: the hours « % » gave « % »', v_bad, v_r;
        end if;
    end loop;
    update platform_settings set value = to_jsonb(repeat('x', 60)) where key = 'support_hours';
    -- 60 emoji: 60 characters (240 bytes, 120 UTF-16 units) — taken, as
    -- the app and the site count them.
    update platform_settings set value = to_jsonb(repeat(E'\U0001F558', 60)) where key = 'support_hours';
    v_r := pg_temp.refused126(format($q$update platform_settings set value = %L where key = 'support_hours'$q$,
                                     to_jsonb(repeat(E'\U0001F558', 61))));
    if v_r is distinct from v_msg_hours then
        raise exception 'FAIL: 61 emoji for the hours gave « % »', v_r;
    end if;
    update platform_settings set value = '"du lundi au samedi, 8 h – 20 h"' where key = 'support_hours';

    -- A number copied from WhatsApp: direction marks around it, a
    -- non-breaking hyphen inside — 113 refused it.
    update platform_settings set value = to_jsonb(E'\u202A+1 (862) 335\u20114492\u202C'::text) where key = 'support_whatsapp';
    if support_whatsapp() is distinct from '18623354492' then
        raise exception 'FAIL: the pasted number reads %', support_whatsapp();
    end if;
    foreach v_bad in array array['le support', '7000', E'\u202A7000\u202C', '+1 862 335 4492 poste 3',
                                 -- Two numbers, never run together into one.
                                 '22670000 / 22676000', '22670000;22676000', '22670000, 22676000',
                                 '226/70000000', '+226 70 00 00 00 ; +226 76 00 00 00'] loop
        v_r := pg_temp.refused126(format($q$update platform_settings set value = %L where key = 'support_whatsapp'$q$,
                                         to_jsonb(v_bad)));
        if v_r is distinct from v_msg_wa then
            raise exception 'FAIL: the number « % » gave « % »', v_bad, v_r;
        end if;
    end loop;
    if support_contacts() is distinct from
       '{"email": "aide@marakaj.co.uk", "whatsapp": "18623354492", "hours": "du lundi au samedi, 8 h – 20 h"}'::jsonb then
        raise exception 'FAIL: support_contacts() gave %', support_contacts();
    end if;
    raise notice 'PASS: twenty-three bad e-mails (< > " '' ? & , ; a space or a tab among them) and a number refused, 120 « é » characters taken; 61 characters (or 61 emoji) or nothing for the hours refused, 60 (or 60 emoji) taken; two numbers joined by / ; or , refused; a pasted « +1 (862) 335-4492 » wrapped in direction marks reads 18623354492, a word or 4 digits still refused; support_contacts() follows';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: a stranger and a signed-in person read support_contacts() ---'
begin;
update platform_settings set value = '"+1 862 335 4492"' where key = 'support_whatsapp';
do $$
declare v jsonb;
begin
    execute 'set local role anon';
    v := support_contacts();
    execute 'reset role';
    if v is distinct from '{"email": "hello@kaj-consulting.com", "whatsapp": "18623354492", "hours": "24 h/24, 7 j/7"}'::jsonb then
        raise exception 'FAIL: anon read %', v;
    end if;
    perform pg_temp.as126('12612612-0000-0000-0000-000000000005');
    execute 'set local role authenticated';
    v := support_contacts();
    execute 'reset role';
    if v ->> 'whatsapp' is distinct from '18623354492' then
        raise exception 'FAIL: a signed-in shopper read %', v;
    end if;
    -- Nothing else on that door: three keys, no business, no person.
    if (select array_agg(k order by k) from jsonb_object_keys(v) k) <> array['email', 'hours', 'whatsapp'] then
        raise exception 'FAIL: support_contacts() says more: %', v;
    end if;
    raise notice 'PASS: anon and a signed-in shopper read the e-mail, the digits and the hours — three keys, nothing else';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: a stranger writes nothing ---'
do $$
declare v_r text;
begin
    v_r := pg_temp.refused126($q$select platform_set_setting('support_email', '"pirate@example.org"')$q$, 'anon');
    if v_r not like 'permission denied%' then
        raise exception 'FAIL: anon calling platform_set_setting gave « % »', v_r;
    end if;
    v_r := pg_temp.refused126($q$update platform_settings set value = '"pirate@example.org"' where key = 'support_email'$q$, 'anon');
    if v_r = '(went through)' and (select value from platform_settings where key = 'support_email') = '"pirate@example.org"'::jsonb then
        raise exception 'FAIL: anon rewrote the e-mail';
    end if;
    v_r := pg_temp.refused126($q$insert into platform_settings (key, value) values ('support_extra', '"x"')$q$, 'anon');
    if exists (select 1 from platform_settings where key = 'support_extra') then
        raise exception 'FAIL: anon added a setting';
    end if;
    if has_function_privilege('anon', 'platform_set_setting(text, jsonb)', 'execute')
       or has_function_privilege('anon', 'support_whatsapp()', 'execute') then
        raise exception 'FAIL: anon may call platform_set_setting or support_whatsapp()';
    end if;
    if (select value from platform_settings where key = 'support_email') is distinct from '"hello@kaj-consulting.com"'::jsonb then
        raise exception 'FAIL: the e-mail moved: %', (select value from platform_settings where key = 'support_email');
    end if;
    raise notice 'PASS: platform_set_setting is permission denied to anon; the table takes no write from anon; the e-mail unchanged';
end $$;

\echo ''
\echo '--- TEST 5: platform_set_setting — the platform sets both (journaled, « Annuler »), nobody else ---'
begin;
do $$
declare v_who text; a1 uuid; a2 uuid; v_r text;
begin
    -- A shop's, a farm's and an association's owner, and a shopper: refused.
    foreach v_who in array array['12612612-0000-0000-0000-000000000002', '12612612-0000-0000-0000-000000000003',
                                 '12612612-0000-0000-0000-000000000004', '12612612-0000-0000-0000-000000000005'] loop
        perform pg_temp.as126(v_who::uuid);
        v_r := pg_temp.refused126($q$select platform_set_setting('support_email', '"autre@example.org"')$q$, 'authenticated');
        if v_r is distinct from 'Réservé à la plateforme' then
            raise exception 'FAIL: % setting the e-mail gave « % »', v_who, v_r;
        end if;
        v_r := pg_temp.refused126($q$select platform_set_setting('support_hours', '"le matin"')$q$, 'authenticated');
        if v_r is distinct from 'Réservé à la plateforme' then
            raise exception 'FAIL: % setting the hours gave « % »', v_who, v_r;
        end if;
    end loop;

    perform pg_temp.as126('12612612-0000-0000-0000-000000000001');
    execute 'set local role authenticated';
    a1 := platform_set_setting('support_email', '"aide@marakaj.com"');
    a2 := platform_set_setting('support_hours', '"7 j/7, de 7 h à 22 h"');
    execute 'reset role';
    if a1 is null or a2 is null
       or support_contacts() ->> 'email' is distinct from 'aide@marakaj.com'
       or support_contacts() ->> 'hours' is distinct from '7 j/7, de 7 h à 22 h' then
        raise exception 'FAIL: the platform''s change gave % % %', a1, a2, support_contacts();
    end if;
    if not exists (select 1 from platform_actions where id = a1 and kind = 'setting' and after ->> 'key' = 'support_email')
       or not exists (select 1 from platform_actions where id = a2 and kind = 'setting' and after ->> 'key' = 'support_hours') then
        raise exception 'FAIL: a change is not in the journal';
    end if;
    -- The checks hold through the door too, in French.
    v_r := pg_temp.refused126($q$select platform_set_setting('support_email', '"hello"')$q$, 'authenticated');
    if v_r is distinct from 'L''e-mail de l''aide : une adresse comme hello@kaj-consulting.com.' then
        raise exception 'FAIL: a bad e-mail through the door gave « % »', v_r;
    end if;
    v_r := pg_temp.refused126(format($q$select platform_set_setting('support_hours', %L)$q$, to_jsonb(repeat('h', 61))), 'authenticated');
    if v_r is distinct from 'Les heures de l''aide : quelques mots, 60 caractères au plus (par exemple 24 h/24, 7 j/7).' then
        raise exception 'FAIL: long hours through the door gave « % »', v_r;
    end if;
    v_r := pg_temp.refused126($q$select platform_set_setting('support_email', '12')$q$, 'authenticated');
    if v_r is distinct from 'Ce réglage attend un texte.' then
        raise exception 'FAIL: a number for the e-mail through the door gave « % »', v_r;
    end if;
    -- The owner's number, as typed in Réglages, and pasted.
    execute 'set local role authenticated';
    perform platform_set_setting('support_whatsapp', '"+1 862 335 4492"');
    perform platform_set_setting('support_whatsapp', to_jsonb(E'\u202A+1 (862) 335-4492\u202C'::text));
    perform platform_set_setting('support_whatsapp', '"18623354492"');
    execute 'reset role';
    if support_contacts() ->> 'whatsapp' is distinct from '18623354492' then
        raise exception 'FAIL: the owner''s number reads %', support_contacts() ->> 'whatsapp';
    end if;
    execute 'set local role authenticated';
    perform platform_undo(a2);
    perform platform_undo(a1);
    execute 'reset role';
    if support_contacts() ->> 'email' is distinct from 'hello@kaj-consulting.com'
       or support_contacts() ->> 'hours' is distinct from '24 h/24, 7 j/7' then
        raise exception 'FAIL: « Annuler » did not put back %', support_contacts();
    end if;
    raise notice 'PASS: the owners of a shop, a farm, an association and a shopper refused; the platform sets the e-mail and the hours, journaled, the checks in French through the door, the number typed or pasted, « Annuler » puts both back';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: P1 — installing 126 changes nothing else ---'
begin;
-- The database as before 126: no e-mail, no hours, no door.
drop function support_contacts();
drop trigger support_email_check on platform_settings;
drop trigger support_hours_check on platform_settings;
drop function trg_support_email();
drop function trg_support_hours();
delete from platform_settings where key in ('support_email', 'support_hours');
select pg_temp.as126(:shopper);
create temp table b126_seen on commit drop as
    select 'setting ' || key as k, value::text as v from platform_settings
    union all
    select 'storefront ' || o.slug, (select jsonb_agg(to_jsonb(s)) from storefront(o.slug) s)::text
      from orgs o where o.slug in ('boutique-126', 'ferme-126', 'entraide-126')
    union all
    select 'shelf ' || o.slug, (select jsonb_agg(to_jsonb(s) order by s.id) from storefront_products(o.slug) s)::text
      from orgs o where o.slug in ('boutique-126', 'ferme-126', 'entraide-126')
    union all
    select 'links', app_store_links()::text
    union all
    select 'shopper', my_shopper_profile()::text
    union all
    select 'number', coalesce(support_whatsapp(), '(none)');
\i database/migrations/126_support.sql
do $$
declare v_diff text;
begin
    with now_seen as (
        select 'setting ' || key as k, value::text as v from platform_settings
         where key not in ('support_email', 'support_hours')
        union all
        select 'storefront ' || o.slug, (select jsonb_agg(to_jsonb(s)) from storefront(o.slug) s)::text
          from orgs o where o.slug in ('boutique-126', 'ferme-126', 'entraide-126')
        union all
        select 'shelf ' || o.slug, (select jsonb_agg(to_jsonb(s) order by s.id) from storefront_products(o.slug) s)::text
          from orgs o where o.slug in ('boutique-126', 'ferme-126', 'entraide-126')
        union all
        select 'links', app_store_links()::text
        union all
        select 'shopper', my_shopper_profile()::text
        union all
        select 'number', coalesce(support_whatsapp(), '(none)'))
    select string_agg(coalesce(a.k, b.k), ', ') into v_diff
      from b126_seen a full join now_seen b on a.k = b.k
     where a.v is distinct from b.v;
    if v_diff is not null then
        raise exception 'FAIL: installing 126 changed %', v_diff;
    end if;
    if (select count(*) from b126_seen where k like 'storefront %') <> 3 then
        raise exception 'FAIL: the three vitrines were not photographed';
    end if;
    if support_contacts() is distinct from
       '{"email": "hello@kaj-consulting.com", "whatsapp": null, "hours": "24 h/24, 7 j/7"}'::jsonb then
        raise exception 'FAIL: the fresh install gave %', support_contacts();
    end if;
    raise notice 'PASS: every other setting, the three vitrines (shop, farm, association) and their shelves, the store links, the shopper''s page and the number answer the same after 126';
end $$;
rollback;

\echo ''
\echo '--- TEST 7: the doors ---'
do $$
declare v_role text;
begin
    if not has_function_privilege('anon', 'support_contacts()', 'execute')
       or not has_function_privilege('authenticated', 'support_contacts()', 'execute') then
        raise exception 'FAIL: support_contacts() is not open to the street and the app';
    end if;
    if has_function_privilege('public', 'support_contacts()', 'execute') then
        raise exception 'FAIL: support_contacts() is open to PUBLIC';
    end if;
    foreach v_role in array array['anon', 'authenticated'] loop
        if has_function_privilege(v_role, 'trg_support_email()', 'execute')
           or has_function_privilege(v_role, 'trg_support_hours()', 'execute')
           or has_function_privilege(v_role, 'trg_support_whatsapp()', 'execute') then
            raise exception 'FAIL: % may call a support trigger', v_role;
        end if;
    end loop;
    if not (select prosecdef from pg_proc where proname = 'support_contacts')
       or exists (select 1 from pg_proc
                   where proname in ('support_contacts', 'trg_support_email', 'trg_support_hours', 'trg_support_whatsapp')
                     and not coalesce((select true from unnest(proconfig) c where c like 'search_path=%'), false)) then
        raise exception 'FAIL: support_contacts() is not a definer, or a function has no search path';
    end if;
    raise notice 'PASS: support_contacts() open to anon and authenticated (not PUBLIC), a definer; the triggers nobody''s; search paths pinned';
end $$;

update platform_settings s set value = b.value from b126_saved b where s.key = b.key;

\echo '=== test_batch126.sql: all claims hold ==='
