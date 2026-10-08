-- ============================================================
-- test_batch112.sql — becoming a courier, approved by the platform (112).
-- Phone block 112.
--
-- The claims — a courier is a person, not a business, so the owner of a
-- shop, of a farm and of an association are each tried as an applicant
-- and as a stranger to someone else's dossier:
--   * P1: installed, both new settings are off and today's courier model
--     answers as before — register_courier, courier_status,
--     platform_couriers, decide_courier, the « Livreurs à valider » count
--     and the board — answer for answer with and without 112's objects;
--   * the dossier: one step at a time, each checked in French; the
--     applicant's read says which photos are there, never their keys;
--     RULE M: the payout number only while mobile payment is on;
--   * the photos: a key under courier/<the caller>/ for a step that is
--     theirs to fill, the retake retiring the old one;
--   * « Envoyer ma demande »: everything checked (the licence optional
--     until the platform says otherwise, the number proved once it says
--     so), the courier row pending, the platform rung, the count up;
--   * the review: approve, refuse with a reason (that step reopens, the
--     rest kept), ask for a new photo — each journaled, « Annuler » puts
--     it back, the applicant rung each time;
--   * THE PHOTOS: a platform admin reads a current one; the applicant,
--     another person, a business owner of each kind and the street do
--     not, through any function or table; documents can never name one;
--   * deleted 30 days after a refusal (and the replaced, the unfinished,
--     the idle draft, the deleted account), through the purge pair only;
--   * the doors: nothing for the street, the internals for nobody.
-- ============================================================
\set ON_ERROR_STOP on

\set mara    '''11211211-0000-0000-0000-000000000001'''
\set awa     '''11211211-0000-0000-0000-000000000002'''
\set ali     '''11211211-0000-0000-0000-000000000003'''
\set sowner  '''11211211-0000-0000-0000-000000000004'''
\set fowner  '''11211211-0000-0000-0000-000000000005'''
\set aowner  '''11211211-0000-0000-0000-000000000006'''
\set old     '''11211211-0000-0000-0000-000000000007'''
\set gone    '''11211211-0000-0000-0000-000000000008'''
\set shop    '''11200000-0000-0000-0000-000000000001'''
\set farm    '''11200000-0000-0000-0000-000000000002'''
\set assoc   '''11200000-0000-0000-0000-000000000003'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;
grant usage on schema public to anon, authenticated;
-- Earlier suites hand the app's roles every table and every function:
-- 112 again, so what follows tests its own doors.
\i database/migrations/112_courier_application.sql

insert into auth.users (id, phone, email, raw_user_meta_data, phone_confirmed_at) values
    (:mara,   '+22611200001', 'mara112@example.com',  '{"full_name": "Mara Cent-Douze"}',   null),
    -- Proved on WhatsApp (109): Supabase keeps it without the +.
    (:awa,    '22670112002',  'awa112@example.com',   '{"full_name": "Awa Livreuse"}',      now()),
    (:ali,    null,           'ali112@example.com',   '{"full_name": "Ali Cycliste"}',      null),
    (:sowner, '+22611200004', 'shop112@example.com',  '{"full_name": "Sali Boutique112"}',  null),
    (:fowner, '+22611200005', 'farm112@example.com',  '{"full_name": "Firmin Ferme112"}',   null),
    (:aowner, '+22611200006', 'asso112@example.com',  '{"full_name": "Aminata Entraide112"}', null),
    (:old,    '+22611200007', 'old112@example.com',   '{"full_name": "Oumar Ancien"}',      null),
    (:gone,   null,           'gone112@example.com',  '{"full_name": "Parti Bientôt"}',     null);
update profiles set is_platform_admin = true where id = :mara;
insert into orgs (id, name, slug, profile, default_currency, plan, storefront_enabled) values
    (:shop,  'Boutique Cent-Douze', 'boutique-112', 'retail',      'XOF', 'free', true),
    (:farm,  'Ferme Cent-Douze',    'ferme-112',    'farm',        'XOF', 'free', true),
    (:assoc, 'Entraide Cent-Douze', 'entraide-112', 'association', 'XOF', 'free', true);
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop,  :sowner, 'owner', 'org', :shop,  'full'),
    (:farm,  :fowner, 'owner', 'org', :farm,  'full'),
    (:assoc, :aowner, 'owner', 'org', :assoc, 'full');

-- As PostgREST names a caller, for one statement's transaction.
create or replace function pg_temp.as_(p_who uuid)
returns void language sql as $$
    select set_config('request.jwt.claim.sub', coalesce(p_who::text, ''), true);
$$;

-- What the uploads Worker does for one photo: the slot, (the bytes),
-- done. Returns the key.
create or replace function pg_temp.photo(p_who uuid, p_part text)
returns text language plpgsql as $$
declare v_key text;
begin
    perform pg_temp.as_(p_who);
    v_key := courier_upload_slot(p_part, 'jpg');
    perform courier_upload_done(v_key);
    return v_key;
end;
$$;

-- The refusal of a call, in its words; null when it went through.
create or replace function pg_temp.refusal(p_sql text)
returns text language plpgsql as $$
begin
    execute p_sql;
    return null;
exception when others then
    return sqlerrm;
end;
$$;

\echo ''
\echo '--- TEST 1: installed, the settings are off and today''s couriers answer as before (P1) ---'
-- The mobile-payment switch as an earlier suite left it, put back at the end.
select value::text as wave_was from platform_settings where key = 'wave_checkout' \gset
update platform_settings set value = 'false' where key = 'wave_checkout';
begin;
-- Today's courier model, the way an app that knows no dossier walks it:
-- a person registers, the platform's list and count, the approval, the
-- board, the bell, a suspension. Run once with 112 and once without its
-- objects; each answer kept in a psql variable across the rollback.
create or replace function pg_temp.today()
returns jsonb language plpgsql as $$
declare v jsonb := '{}';
begin
    perform pg_temp.as_('11211211-0000-0000-0000-000000000007');
    perform register_courier('+226 70 11 20 07');
    v := v || jsonb_build_object('status after register', courier_status());
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    v := v || jsonb_build_object('platform list',
        (select jsonb_agg(to_jsonb(c) - 'created_at' order by c.user_id) from platform_couriers() c
          where c.user_id = '11211211-0000-0000-0000-000000000007'));
    v := v || jsonb_build_object('to validate', platform_todo() -> 'couriers');
    perform decide_courier('11211211-0000-0000-0000-000000000007', 'approved');
    perform pg_temp.as_('11211211-0000-0000-0000-000000000007');
    v := v || jsonb_build_object('status after approval', courier_status());
    v := v || jsonb_build_object('board', (select coalesce(jsonb_agg(to_jsonb(d) order by d.order_id), '[]')
                                             from available_deliveries() d));
    v := v || jsonb_build_object('bell',
        (select jsonb_agg(jsonb_build_object('kind', n.kind, 'message', n.message, 'params', n.params) order by n.kind)
           from notifications n where n.recipient_id = '11211211-0000-0000-0000-000000000007'));
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    perform decide_courier('11211211-0000-0000-0000-000000000007', 'suspended');
    v := v || jsonb_build_object('list after suspension',
        (select to_jsonb(c) - 'created_at' from platform_couriers() c
          where c.user_id = '11211211-0000-0000-0000-000000000007'));
    return v;
end;
$$;
create or replace function pg_temp.same(p_with jsonb, p_before jsonb)
returns void language plpgsql as $$
declare k text;
begin
    if (select count(*) from jsonb_object_keys(p_with)) <> 7 then
        raise exception 'FAIL: % answers, 7 expected', (select count(*) from jsonb_object_keys(p_with));
    end if;
    for k in select jsonb_object_keys(p_with) loop
        if p_with -> k is distinct from p_before -> k then
            raise exception 'FAIL: « % » differs with 112: % instead of %', k, p_with -> k, p_before -> k;
        end if;
    end loop;
    if p_with ->> 'status after register' <> 'pending'
       or p_with ->> 'status after approval' <> 'approved'
       or p_with #>> '{list after suspension,status}' <> 'suspended'
       or (p_with ->> 'to validate')::int < 1 then
        raise exception 'FAIL: the walk is not what it claims: %', p_with;
    end if;
    raise notice 'PASS: off as installed; register, courier_status, platform_couriers, the count, decide_courier, the board and the bell answer the same with and without 112 (7 answers)';
end;
$$;
do $$
begin
    if (select value from platform_settings where key = 'courier_licence_required') <> 'false'::jsonb
       or (select value from platform_settings where key = 'courier_phone_verified') <> 'false'::jsonb then
        raise exception 'FAIL: a 112 setting is not installed off';
    end if;
end $$;
savepoint with112;
select pg_temp.today()::text as p1_with \gset
rollback to savepoint with112;
-- Without 112: its functions, tables, settings, constraint and undo gone.
drop function courier_rules(), courier_file_due(courier_files), courier_current_file(uuid, text),
    courier_missing_parts(uuid), courier_open_steps(uuid), courier_application_open(),
    courier_person_name(uuid), my_courier_application(), courier_application_save(text, jsonb),
    courier_application_send(), courier_upload_slot(text, text), courier_upload_done(text),
    courier_photo_allowed(text), courier_files_due(), courier_files_purged(text[]),
    platform_courier_applications(), platform_courier_application(uuid),
    platform_decide_courier_application(uuid, text, text, text[], text),
    platform_undo_courier_decision(jsonb), courier_part_step(text), courier_reason_label(text);
drop table courier_files, courier_applications;
delete from platform_settings where key in ('courier_licence_required', 'courier_phone_verified');
delete from platform_undo_fns where fn = 'platform_undo_courier_decision';
alter table documents drop constraint documents_never_courier;
select pg_temp.today()::text as p1_before \gset
select pg_temp.same(:'p1_with'::jsonb, :'p1_before'::jsonb);
rollback;

\echo ''
\echo '--- TEST 2: the dossier, one step at a time, checked in French; the applicant reads no key ---'
do $$
declare
    v jsonb;
begin
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    v := my_courier_application();
    if v ->> 'status' is not null or v -> 'rules' <> jsonb_build_object(
            'licence_required', false, 'phone_verified', false, 'mobile_money', false, 'charter_version', 1)
       or v ->> 'verified_phone' <> '+22670112002'
       or v -> 'open_steps' <> '["zone", "hours", "vehicle", "selfie", "id", "phone", "charter"]'::jsonb then
        raise exception 'FAIL: a person with no dossier reads %', v;
    end if;
    -- Each step refuses what is wrong, in words.
    if pg_temp.refusal($q$select courier_application_save('zone', '{"city": " ", "zones": ["Gounghin"]}')$q$) is distinct from 'Indiquez votre ville'
       or pg_temp.refusal($q$select courier_application_save('zone', '{"city": "Ouagadougou", "zones": []}')$q$) is distinct from 'Ajoutez au moins un quartier'
       or pg_temp.refusal($q$select courier_application_save('hours', '{"days": [], "hours_from": "08:00", "hours_to": "18:00"}')$q$) is distinct from 'Choisissez au moins un jour'
       or pg_temp.refusal($q$select courier_application_save('hours', '{"days": ["lun", "funday"], "hours_from": "08:00", "hours_to": "18:00"}')$q$) is distinct from 'Jour inconnu'
       or pg_temp.refusal($q$select courier_application_save('hours', '{"days": ["lun"], "hours_from": "8h", "hours_to": "18:00"}')$q$) is distinct from 'Indiquez vos heures (par exemple 08:00 à 18:00)'
       or pg_temp.refusal($q$select courier_application_save('hours', '{"days": ["lun"], "hours_from": "18:00", "hours_to": "08:00"}')$q$) is distinct from 'L''heure de fin vient après l''heure de début'
       or pg_temp.refusal($q$select courier_application_save('vehicle', '{"vehicle": "avion"}')$q$) is distinct from 'Choisissez votre moyen de transport'
       or pg_temp.refusal($q$select courier_application_save('vehicle', '{"vehicle": "moto", "vehicle_make": "Yamaha"}')$q$) is distinct from 'Indiquez la marque, le modèle, la couleur et la plaque'
       or pg_temp.refusal($q$select courier_application_save('id', '{"id_kind": "permis"}')$q$) is distinct from 'Choisissez votre pièce d''identité'
       or pg_temp.refusal($q$select courier_application_save('phone', '{"phone": "70 11 20 02"}')$q$) is distinct from 'Indiquez votre numéro WhatsApp avec l''indicatif (+226…)'
       or pg_temp.refusal($q$select courier_application_save('charter', '{"charter_version": 0}')$q$) is distinct from 'Acceptez la charte du livreur'
       or pg_temp.refusal($q$select courier_application_save('selfie', '{}')$q$) is distinct from 'Cette étape n''est pas à modifier'
       or pg_temp.refusal($q$select courier_application_save('nimporte', '{}')$q$) is distinct from 'Cette étape n''est pas à modifier' then
        raise exception 'FAIL: a step took what it should refuse';
    end if;
    raise notice 'PASS: every step refuses in French what is wrong (13 refusals)';
end $$;
do $$
declare
    v jsonb;
begin
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    perform courier_application_save('zone', '{"city": " Ouagadougou ", "zones": ["Gounghin", " Pissy ", "Gounghin", ""]}');
    perform courier_application_save('hours', '{"days": ["sam", "lun", "mar", "lun"], "hours_from": "07:30", "hours_to": "19:00"}');
    perform courier_application_save('vehicle', '{"vehicle": "moto", "vehicle_make": "Yamaha", "vehicle_model": "Crypton", "vehicle_colour": "Rouge", "vehicle_plate": "11 kk 2233"}');
    perform courier_application_save('id', '{"id_kind": "cnib"}');
    -- RULE M: mobile payment off, a payout number is not kept.
    perform courier_application_save('phone', '{"phone": "+226 70 11 20 02", "payout_number": "+22670112002"}');
    v := courier_application_save('charter', '{"charter_version": 1}');
    if v ->> 'status' <> 'draft' or v ->> 'city' <> 'Ouagadougou'
       or v -> 'zones' <> '["Gounghin", "Pissy"]'::jsonb
       or v -> 'days' <> '["lun", "mar", "sam"]'::jsonb
       or v ->> 'vehicle_plate' <> '11 KK 2233' or v ->> 'phone' <> '+22670112002'
       or v ->> 'payout_number' is not null or (v ->> 'charter_version')::int <> 1 then
        raise exception 'FAIL: the draft reads %', v;
    end if;
    if (select payout_number from courier_applications where user_id = '11211211-0000-0000-0000-000000000002') is not null then
        raise exception 'FAIL: a payout number was kept while mobile payment is off';
    end if;
    raise notice 'PASS: a draft kept, trimmed, deduplicated and in order; no payout number while mobile payment is off (RULE M)';
end $$;
-- RULE M, on: asked, kept, shown.
begin;
update platform_settings set value = 'true' where key = 'wave_checkout';
do $$
declare v jsonb;
begin
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    if pg_temp.refusal($q$select courier_application_save('phone', '{"phone": "+22670112002", "payout_number": "12"}')$q$) is distinct from 'Numéro Mobile Money invalide' then
        raise exception 'FAIL: a bad payout number was taken';
    end if;
    v := courier_application_save('phone', '{"phone": "+22670112002", "payout_number": "+22670112099"}');
    if v ->> 'payout_number' <> '+22670112099' or (v #>> '{rules,mobile_money}')::boolean is not true then
        raise exception 'FAIL: with mobile payment on, the payout number reads %', v;
    end if;
    raise notice 'PASS: with mobile payment on (wave_checkout), the payout number is asked, checked and kept';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: the photos — a key under courier/<the caller>/, for a step theirs to fill; a retake retires the old ---'
do $$
declare
    v_key  text;
    v_key2 text;
    v jsonb;
begin
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    v_key := courier_upload_slot('selfie', 'JPG');
    if v_key !~ '^courier/11211211-0000-0000-0000-000000000002/[0-9a-f-]{36}\.jpg$' then
        raise exception 'FAIL: the key is %', v_key;
    end if;
    -- Until the bytes are in, nothing is there.
    if (my_courier_application() #>> '{files,selfie}')::boolean then
        raise exception 'FAIL: a slot counts as a photo';
    end if;
    if courier_upload_done(v_key) <> 'selfie' then
        raise exception 'FAIL: done did not name the part';
    end if;
    if pg_temp.refusal(format('select courier_upload_done(%L)', v_key)) is distinct from 'Envoi inconnu' then
        raise exception 'FAIL: a slot was finished twice';
    end if;
    v_key2 := pg_temp.photo('11211211-0000-0000-0000-000000000002', 'selfie');
    if (select state from courier_files where r2_key = v_key) <> 'replaced'
       or (select state from courier_files where r2_key = v_key2) <> 'current' then
        raise exception 'FAIL: the retake did not retire the old selfie';
    end if;
    perform pg_temp.photo('11211211-0000-0000-0000-000000000002', 'id_front');
    perform pg_temp.photo('11211211-0000-0000-0000-000000000002', 'id_back');
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    v := my_courier_application();
    if v -> 'files' <> '{"selfie": true, "id_front": true, "id_back": true, "licence": false}'::jsonb then
        raise exception 'FAIL: the photos read %', v -> 'files';
    end if;
    -- The applicant's read carries no key at all.
    if v::text like '%courier/%' then
        raise exception 'FAIL: the applicant''s read carries a key: %', v;
    end if;
    raise notice 'PASS: slot → bytes → done; a slot is not a photo; a retake retires the old; the applicant reads which photos, never a key';
end $$;
do $$
declare v_key text;
begin
    -- Another person cannot finish a slot that is not theirs.
    perform pg_temp.as_('11211211-0000-0000-0000-000000000003');
    perform courier_application_save('zone', '{"city": "Bobo-Dioulasso", "zones": ["Sarfalao"]}');
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    v_key := courier_upload_slot('licence', 'png');
    perform pg_temp.as_('11211211-0000-0000-0000-000000000003');
    if pg_temp.refusal(format('select courier_upload_done(%L)', v_key)) is distinct from 'Envoi inconnu' then
        raise exception 'FAIL: someone finished another person''s slot';
    end if;
    if pg_temp.refusal($q$select courier_upload_slot('passport', 'jpg')$q$) is distinct from 'Photo inconnue'
       or pg_temp.refusal($q$select courier_upload_slot('selfie', 'svg')$q$) is distinct from 'Photos uniquement'
       or pg_temp.refusal($q$select courier_upload_slot('selfie', 'html')$q$) is distinct from 'Photos uniquement' then
        raise exception 'FAIL: a slot was given for something that is not a photo';
    end if;
    perform pg_temp.as_(null);
    if pg_temp.refusal($q$select courier_upload_slot('selfie', 'jpg')$q$) is distinct from 'Connectez-vous d''abord'
       or pg_temp.refusal($q$select my_courier_application()$q$) is distinct from 'Connectez-vous d''abord' then
        raise exception 'FAIL: nobody signed in got a slot or a dossier';
    end if;
    raise notice 'PASS: nobody finishes another''s slot; only photos; signed out, no slot and no dossier';
end $$;
-- Thirty a day at most.
begin;
do $$
declare i int;
begin
    perform pg_temp.as_('11211211-0000-0000-0000-000000000003');
    for i in 1..30 loop
        perform courier_upload_slot('selfie', 'jpg');
    end loop;
    if pg_temp.refusal($q$select courier_upload_slot('selfie', 'jpg')$q$) is distinct from 'Trop de photos envoyées aujourd''hui. Réessayez demain.' then
        raise exception 'FAIL: the 31st photo of the day was taken';
    end if;
    raise notice 'PASS: 30 photos a day at most';
end $$;
rollback;

\echo ''
\echo '--- TEST 4: « Envoyer ma demande » — everything checked, the courier pending, the platform rung, the count up ---'
do $$
declare
    v jsonb;
    v_count int;
begin
    -- Ali: a vélo, no number proved, nothing else yet.
    perform pg_temp.as_('11211211-0000-0000-0000-000000000003');
    if pg_temp.refusal('select courier_application_send()') is distinct from 'Choisissez vos jours et vos heures' then
        raise exception 'FAIL: hours: %', pg_temp.refusal('select courier_application_send()');
    end if;
    perform courier_application_save('hours', '{"days": ["lun", "mer"], "hours_from": "08:00", "hours_to": "12:00"}');
    if pg_temp.refusal('select courier_application_send()') is distinct from 'Choisissez votre moyen de transport' then
        raise exception 'FAIL: vehicle';
    end if;
    perform courier_application_save('vehicle', '{"vehicle": "velo", "vehicle_make": "ignored"}');
    if pg_temp.refusal('select courier_application_send()') is distinct from 'Prenez votre selfie' then
        raise exception 'FAIL: selfie';
    end if;
    perform pg_temp.photo('11211211-0000-0000-0000-000000000003', 'selfie');
    perform pg_temp.as_('11211211-0000-0000-0000-000000000003');
    if pg_temp.refusal('select courier_application_send()') is distinct from 'Choisissez votre pièce d''identité' then
        raise exception 'FAIL: id kind';
    end if;
    perform courier_application_save('id', '{"id_kind": "passeport"}');
    if pg_temp.refusal('select courier_application_send()') is distinct from 'Photographiez le recto et le verso de votre pièce' then
        raise exception 'FAIL: id photos';
    end if;
    perform pg_temp.photo('11211211-0000-0000-0000-000000000003', 'id_front');
    perform pg_temp.photo('11211211-0000-0000-0000-000000000003', 'id_back');
    perform pg_temp.as_('11211211-0000-0000-0000-000000000003');
    if pg_temp.refusal('select courier_application_send()') is distinct from 'Indiquez votre numéro WhatsApp' then
        raise exception 'FAIL: phone';
    end if;
    -- Off, a typed number is taken (not proved).
    perform courier_application_save('phone', '{"phone": "+22670112003"}');
    if pg_temp.refusal('select courier_application_send()') is distinct from 'Acceptez la charte du livreur' then
        raise exception 'FAIL: charter';
    end if;
    perform courier_application_save('charter', '{"charter_version": 1}');
    if (select vehicle_make from courier_applications where user_id = '11211211-0000-0000-0000-000000000003') is not null then
        raise exception 'FAIL: a vélo kept a make';
    end if;
    select count(*) into v_count from couriers where status = 'pending';
    v := courier_application_send();
    if v ->> 'status' <> 'pending' or v ->> 'courier_status' <> 'pending'
       or v -> 'timeline' -> 0 ->> 'kind' <> 'sent' or v -> 'open_steps' <> '[]'::jsonb then
        raise exception 'FAIL: sent, the dossier reads %', v;
    end if;
    if (select phone_verified from courier_applications where user_id = '11211211-0000-0000-0000-000000000003') then
        raise exception 'FAIL: a typed number was taken for proved';
    end if;
    if (select count(*) from couriers where status = 'pending') <> v_count + 1
       or (select phone from couriers where user_id = '11211211-0000-0000-0000-000000000003') <> '+22670112003' then
        raise exception 'FAIL: the courier row is not pending with the number';
    end if;
    if not exists (select 1 from notifications
                    where recipient_id = '11211211-0000-0000-0000-000000000001'
                      and kind = 'courier_application' and message = 'Nouvelle demande de livreur : Ali Cycliste'
                      and params = '{"to": "platform", "name": "Ali Cycliste"}') then
        raise exception 'FAIL: the platform was not rung';
    end if;
    -- While examined, nothing changes.
    if pg_temp.refusal($q$select courier_application_save('zone', '{"city": "Koudougou", "zones": ["Secteur 1"]}')$q$) is distinct from 'Votre demande est en cours d''examen'
       or pg_temp.refusal($q$select courier_upload_slot('selfie', 'jpg')$q$) is distinct from 'Votre demande est en cours d''examen'
       or pg_temp.refusal('select courier_application_send()') is distinct from 'Votre demande est en cours d''examen' then
        raise exception 'FAIL: a dossier under examination was changed';
    end if;
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    if (platform_todo() ->> 'couriers')::int < 1 then
        raise exception 'FAIL: « Livreurs à valider » does not count it';
    end if;
    raise notice 'PASS: a vélo needs no licence nor plate; each missing step said in turn; sent → pending (courier row pending, its number), the platform rung, counted in « Livreurs à valider », frozen while examined';
end $$;
-- Awa: a moto. The licence is optional as installed; required when the
-- platform says so — and only for a moto or a car.
begin;
update platform_settings set value = 'true' where key = 'courier_licence_required';
do $$
begin
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    -- TEST 3 left Awa a licence slot never finished: not a photo.
    if pg_temp.refusal('select courier_application_send()') is distinct from 'Photographiez votre permis de conduire' then
        raise exception 'FAIL: the licence, required: %', pg_temp.refusal('select courier_application_send()');
    end if;
    perform courier_application_save('vehicle', '{"vehicle": "tricycle", "vehicle_make": "Apsonic", "vehicle_model": "T3", "vehicle_colour": "Bleu", "vehicle_plate": "11 TT 0001"}');
    if pg_temp.refusal('select courier_application_send()') is not null then
        raise exception 'FAIL: a tricycle was asked a licence: %', pg_temp.refusal('select courier_application_send()');
    end if;
    raise notice 'PASS: licence required by the setting for a moto, never for a tricycle';
end $$;
rollback;
begin;
update platform_settings set value = 'true' where key = 'courier_phone_verified';
do $$
begin
    -- Ali's typed number, on: refused at the step and at the send.
    perform pg_temp.as_('11211211-0000-0000-0000-000000000005');
    perform courier_application_save('zone', '{"city": "Koudougou", "zones": ["Secteur 1"]}');
    if pg_temp.refusal($q$select courier_application_save('phone', '{"phone": "+22611200005"}')$q$) is distinct from 'Vérifiez d''abord votre numéro WhatsApp' then
        raise exception 'FAIL: an unproved number was taken with the setting on';
    end if;
    -- Awa's is proved: taken.
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    if pg_temp.refusal($q$select courier_application_save('phone', '{"phone": "+22670112002"}')$q$) is not null then
        raise exception 'FAIL: a proved number was refused';
    end if;
    raise notice 'PASS: with courier_phone_verified on, only the proved number is taken';
end $$;
rollback;
do $$
declare v jsonb;
begin
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    v := courier_application_send();
    if v ->> 'status' <> 'pending' then
        raise exception 'FAIL: Awa''s dossier: %', v;
    end if;
    if not (select phone_verified from courier_applications where user_id = '11211211-0000-0000-0000-000000000002') then
        raise exception 'FAIL: a proved number was not marked proved';
    end if;
    raise notice 'PASS: a moto with its plate and no licence is sent as installed; the proved number marked proved';
end $$;

\echo ''
\echo '--- TEST 5: the review — approve, refuse (that step reopens), a new photo; journaled, undone, rung ---'
do $$
begin
    -- A business owner of each kind is not the platform.
    perform pg_temp.as_('11211211-0000-0000-0000-000000000004');
    if pg_temp.refusal('select platform_courier_applications()') is distinct from 'Réservé à la plateforme'
       or pg_temp.refusal($q$select platform_courier_application('11211211-0000-0000-0000-000000000002')$q$) is distinct from 'Réservé à la plateforme'
       or pg_temp.refusal($q$select platform_decide_courier_application('11211211-0000-0000-0000-000000000002', 'approve')$q$) is distinct from 'Réservé à la plateforme' then
        raise exception 'FAIL: a shop owner reached the review';
    end if;
    perform pg_temp.as_('11211211-0000-0000-0000-000000000005');
    if pg_temp.refusal($q$select platform_courier_application('11211211-0000-0000-0000-000000000002')$q$) is distinct from 'Réservé à la plateforme' then
        raise exception 'FAIL: a farm owner reached the review';
    end if;
    perform pg_temp.as_('11211211-0000-0000-0000-000000000006');
    if pg_temp.refusal($q$select platform_decide_courier_application('11211211-0000-0000-0000-000000000002', 'refuse', 'blurry', array['selfie'])$q$) is distinct from 'Réservé à la plateforme' then
        raise exception 'FAIL: an association owner reached the review';
    end if;
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    if pg_temp.refusal($q$select platform_courier_application('11211211-0000-0000-0000-000000000002')$q$) is distinct from 'Réservé à la plateforme' then
        raise exception 'FAIL: the applicant read their own review';
    end if;
    raise notice 'PASS: the owner of a shop, of a farm, of an association and the applicant are refused the review';
end $$;
do $$
declare
    v jsonb;
    r record;
begin
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    select * into r from platform_courier_applications() a where a.user_id = '11211211-0000-0000-0000-000000000002';
    if r.status <> 'pending' or r.vehicle <> 'moto' or r.city <> 'Ouagadougou' or r.name <> 'Awa Livreuse' then
        raise exception 'FAIL: the list reads %', to_jsonb(r);
    end if;
    v := platform_courier_application('11211211-0000-0000-0000-000000000002');
    if v #>> '{photos,selfie}' !~ '^courier/11211211-0000-0000-0000-000000000002/'
       or v #>> '{photos,id_front}' is null or v #>> '{photos,id_back}' is null
       or v #>> '{photos,licence}' is not null
       or not (v ->> 'phone_verified')::boolean or v ->> 'vehicle_plate' <> '11 KK 2233'
       or v -> 'zones' <> '["Gounghin", "Pissy"]'::jsonb or v ->> 'id_kind' <> 'cnib' then
        raise exception 'FAIL: the review reads %', v;
    end if;
    if pg_temp.refusal($q$select platform_decide_courier_application('11211211-0000-0000-0000-000000000002', 'refuse', 'nope', array['selfie'])$q$) is distinct from 'Choisissez une raison'
       or pg_temp.refusal($q$select platform_decide_courier_application('11211211-0000-0000-0000-000000000002', 'refuse', 'other', array['selfie'])$q$) is distinct from 'Dites en un mot ce qui ne va pas'
       or pg_temp.refusal($q$select platform_decide_courier_application('11211211-0000-0000-0000-000000000002', 'refuse', 'missing', array[]::text[])$q$) is distinct from 'Choisissez l''étape à corriger'
       or pg_temp.refusal($q$select platform_decide_courier_application('11211211-0000-0000-0000-000000000002', 'refuse', 'missing', array['charter'])$q$) is distinct from 'Étape inconnue'
       or pg_temp.refusal($q$select platform_decide_courier_application('11211211-0000-0000-0000-000000000002', 'new_photo', 'licence')$q$) is distinct from 'Quelle photo ? Le selfie ou la pièce d''identité'
       or pg_temp.refusal($q$select platform_decide_courier_application('11211211-0000-0000-0000-000000000002', 'maybe')$q$) is distinct from 'Décision inconnue' then
        raise exception 'FAIL: a bad decision was taken';
    end if;
    raise notice 'PASS: the platform lists and reads the dossier (photo keys, the number proved, vehicle, zones); a bad decision refused in words';
end $$;
-- Refused « photo floue », the selfie reopened; « Annuler » puts it back.
do $$
declare
    v_action uuid;
    v jsonb;
begin
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    v_action := platform_decide_courier_application('11211211-0000-0000-0000-000000000002', 'refuse', 'blurry',
                                                    array['selfie'], 'Le visage est flou');
    if exists (select 1 from couriers where user_id = '11211211-0000-0000-0000-000000000002') then
        raise exception 'FAIL: a refused applicant is still waiting on the platform';
    end if;
    if not exists (select 1 from platform_actions_page(null, 50, null) a
                    where a.id = v_action and a.kind = 'courier' and a.undoable
                      and a.summary = 'Livreur Awa Livreuse : à corriger (photo floue)') then
        raise exception 'FAIL: the refusal is not journaled with its undo';
    end if;
    if not exists (select 1 from notifications
                    where recipient_id = '11211211-0000-0000-0000-000000000002' and kind = 'courier_refused'
                      and message = 'Votre demande de livreur est à corriger : photo floue. Le visage est flou'
                      and params ->> 'reason' = 'blurry' and params -> 'steps' = '["selfie"]') then
        raise exception 'FAIL: the applicant was not rung with the reason';
    end if;
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    v := my_courier_application();
    if v ->> 'status' <> 'refused' or v -> 'open_steps' <> '["selfie"]'::jsonb
       or v -> 'refusal' <> '{"note": "Le visage est flou", "reason": "blurry", "steps": ["selfie"]}'::jsonb
       or v ->> 'courier_status' is not null then
        raise exception 'FAIL: refused, the applicant reads %', v;
    end if;
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    perform platform_undo(v_action);
    if (select status from courier_applications where user_id = '11211211-0000-0000-0000-000000000002') <> 'pending'
       or (select status from couriers where user_id = '11211211-0000-0000-0000-000000000002') <> 'pending' then
        raise exception 'FAIL: « Annuler » did not put the dossier back under examination';
    end if;
    if not exists (select 1 from notifications
                    where recipient_id = '11211211-0000-0000-0000-000000000002' and kind = 'courier_pending') then
        raise exception 'FAIL: the undo was not said to the applicant';
    end if;
    if pg_temp.refusal(format('select platform_undo(%L)', v_action)) is distinct from 'Cette action a déjà été annulée.' then
        raise exception 'FAIL: an undo ran twice';
    end if;
    raise notice 'PASS: refused « photo floue » (journaled, the courier row out, rung with the reason, the selfie reopened); « Annuler » puts it back under examination and says so';
end $$;
-- Refused « informations manquantes » on the vehicle: only that step
-- opens; the rest is kept; a resend without change is allowed.
do $$
declare v jsonb;
begin
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    perform platform_decide_courier_application('11211211-0000-0000-0000-000000000002', 'refuse', 'missing', array['vehicle']);
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    if pg_temp.refusal($q$select courier_application_save('zone', '{"city": "Koudougou", "zones": ["Secteur 1"]}')$q$) is distinct from 'Cette étape n''est pas à modifier'
       or pg_temp.refusal($q$select courier_upload_slot('selfie', 'jpg')$q$) is distinct from 'Cette photo n''est pas à refaire' then
        raise exception 'FAIL: a step not reopened was changed';
    end if;
    perform courier_application_save('vehicle', '{"vehicle": "moto", "vehicle_make": "Yamaha", "vehicle_model": "Crypton", "vehicle_colour": "Rouge et noir", "vehicle_plate": "11 KK 2233"}');
    v := courier_application_send();
    if v ->> 'status' <> 'pending' or v ->> 'city' <> 'Ouagadougou'
       or v -> 'timeline' -> -1 ->> 'kind' <> 'resent' or not (v #>> '{files,selfie}')::boolean then
        raise exception 'FAIL: resent, the dossier reads %', v;
    end if;
    raise notice 'PASS: « informations manquantes » on the vehicle: only it reopens, the rest kept; resent';
end $$;
-- « Demander une nouvelle photo » (the selfie): resending needs a new one.
do $$
declare v_old text;
begin
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    v_old := platform_courier_application('11211211-0000-0000-0000-000000000002') #>> '{photos,selfie}';
    perform platform_decide_courier_application('11211211-0000-0000-0000-000000000002', 'new_photo', 'selfie');
    if not exists (select 1 from notifications
                    where recipient_id = '11211211-0000-0000-0000-000000000002' and kind = 'courier_photo'
                      and message = 'Mara demande une nouvelle photo de votre selfie.') then
        raise exception 'FAIL: the applicant was not asked for the photo';
    end if;
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    if my_courier_application() -> 'open_steps' <> '["selfie"]'::jsonb then
        raise exception 'FAIL: the new photo did not reopen the selfie alone';
    end if;
    if pg_temp.refusal('select courier_application_send()') is distinct from 'Reprenez la photo demandée' then
        raise exception 'FAIL: resent without the new photo';
    end if;
    perform pg_temp.photo('11211211-0000-0000-0000-000000000002', 'selfie');
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    perform courier_application_send();
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    if platform_courier_application('11211211-0000-0000-0000-000000000002') #>> '{photos,selfie}' = v_old then
        raise exception 'FAIL: the review still shows the old selfie';
    end if;
    raise notice 'PASS: « Demander une nouvelle photo » reopens the selfie alone, rings the applicant, and the resend needs the new one';
end $$;
-- Approved: a courier. « Annuler » back to pending; not while carrying.
do $$
declare
    v_action uuid;
begin
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    v_action := platform_decide_courier_application('11211211-0000-0000-0000-000000000002', 'approve');
    perform pg_temp.as_('11211211-0000-0000-0000-000000000002');
    if courier_status() <> 'approved' or my_courier_application() ->> 'status' <> 'approved' then
        raise exception 'FAIL: approved, courier_status reads %', courier_status();
    end if;
    perform available_deliveries();
    if not exists (select 1 from notifications
                    where recipient_id = '11211211-0000-0000-0000-000000000002' and kind = 'courier_approved'
                      and message = 'Vous êtes livreur Mara : les livraisons vous attendent.') then
        raise exception 'FAIL: the courier was not told';
    end if;
    if pg_temp.refusal($q$select courier_application_save('zone', '{"city": "Koudougou", "zones": ["Secteur 1"]}')$q$) is distinct from 'Vous êtes déjà livreur' then
        raise exception 'FAIL: an approved courier reopened the dossier';
    end if;
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    if pg_temp.refusal($q$select platform_decide_courier_application('11211211-0000-0000-0000-000000000002', 'approve')$q$) is distinct from 'Cette demande n''attend pas de décision' then
        raise exception 'FAIL: decided twice';
    end if;
    perform platform_undo(v_action);
    if (select status from couriers where user_id = '11211211-0000-0000-0000-000000000002') <> 'pending' then
        raise exception 'FAIL: « Annuler » did not take the approval back';
    end if;
    v_action := platform_decide_courier_application('11211211-0000-0000-0000-000000000002', 'approve');
    raise notice 'PASS: approved — courier_status approved, the board open, rung; « Annuler » puts it back to pending; approved again';
end $$;
begin;
-- The parcel on the road, put there directly (the order's own triggers —
-- Pro delivery, the vitrine's switches — are not what this proves).
set local session_replication_role = replica;
do $$
declare v_action uuid;
begin
    -- A running course: the approval is not taken back under a parcel.
    insert into orders (id, org_id, customer_id, customer_name, phone, status, fulfilment, total, currency, courier_id)
    values ('112aaaaa-0000-0000-0000-000000000001', '11200000-0000-0000-0000-000000000001',
            '11211211-0000-0000-0000-000000000006', 'Cliente', '+22670000000',
            'in_transit', 'delivery', 1000, 'XOF', '11211211-0000-0000-0000-000000000002');
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    select a.id into v_action from platform_actions_page(null, 50, null) a
     where a.kind = 'courier' and a.undoable and a.undone_at is null
     order by a.at desc limit 1;
    if pg_temp.refusal(format('select platform_undo(%L)', v_action)) is distinct from 'Ce livreur a une course en cours : suspendez-le plutôt.' then
        raise exception 'FAIL: an approval was taken back under a running course';
    end if;
    raise notice 'PASS: no undo of an approval while the courier carries a parcel';
end $$;
rollback;

\echo ''
\echo '--- TEST 6: THE PHOTOS — the platform reads a current one; nobody else, through no door ---'
do $$
declare
    v_key  text;
    v_old  text;
    v_who  uuid;
begin
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    v_key := platform_courier_application('11211211-0000-0000-0000-000000000002') #>> '{photos,id_front}';
    select r2_key into v_old from courier_files
     where user_id = '11211211-0000-0000-0000-000000000002' and part = 'selfie' and state = 'replaced' limit 1;
    if not courier_photo_allowed(v_key) then
        raise exception 'FAIL: the platform cannot read a current photo';
    end if;
    if courier_photo_allowed(v_old) then
        raise exception 'FAIL: a replaced photo is still served';
    end if;
    if courier_photo_allowed('courier/11211211-0000-0000-0000-000000000002/00000000-0000-0000-0000-000000000000.jpg') then
        raise exception 'FAIL: an unknown key is served';
    end if;
    -- The applicant, another applicant, the owner of a shop, a farm, an association.
    foreach v_who in array array['11211211-0000-0000-0000-000000000002', '11211211-0000-0000-0000-000000000003',
                                 '11211211-0000-0000-0000-000000000004', '11211211-0000-0000-0000-000000000005',
                                 '11211211-0000-0000-0000-000000000006']::uuid[] loop
        perform pg_temp.as_(v_who);
        if courier_photo_allowed(v_key) then
            raise exception 'FAIL: % may read an ID photo', v_who;
        end if;
        if pg_temp.refusal($q$select platform_courier_application('11211211-0000-0000-0000-000000000002')$q$) is null then
            raise exception 'FAIL: % read the dossier', v_who;
        end if;
    end loop;
    perform pg_temp.as_(null);
    if courier_photo_allowed(v_key) then
        raise exception 'FAIL: nobody signed in may read an ID photo';
    end if;
    raise notice 'PASS: courier_photo_allowed — yes for the platform (current photo only); no for the applicant, another person, a shop, a farm and an association owner, and nobody signed in';
end $$;
-- Through the tables, as the app's role, even handed every grant.
begin;
grant select, insert, update, delete on courier_applications, courier_files to authenticated, anon;
set local role authenticated;
set local "request.jwt.claim.sub" = '11211211-0000-0000-0000-000000000002';
do $$
begin
    if exists (select 1 from courier_files) or exists (select 1 from courier_applications) then
        raise exception 'FAIL: the applicant reads a courier table';
    end if;
end $$;
set local "request.jwt.claim.sub" = '11211211-0000-0000-0000-000000000001';
do $$
declare n int;
begin
    if exists (select 1 from courier_files) or exists (select 1 from courier_applications) then
        raise exception 'FAIL: even the platform reads a courier table directly';
    end if;
    update courier_files set state = 'current';
    get diagnostics n = row_count;
    if n <> 0 then
        raise exception 'FAIL: a direct update changed % courier photos', n;
    end if;
    begin
        insert into courier_files (user_id, part, r2_key)
        values ('11211211-0000-0000-0000-000000000002', 'selfie',
                'courier/11211211-0000-0000-0000-000000000002/11111111-1111-1111-1111-111111111111.jpg');
        raise exception 'FAIL: a courier table took a direct write';
    exception when insufficient_privilege then null;
    end;
end $$;
set local role anon;
set local "request.jwt.claim.sub" = '';
do $$
begin
    if exists (select 1 from courier_files) or exists (select 1 from courier_applications) then
        raise exception 'FAIL: the street reads a courier table';
    end if;
    raise notice 'PASS: row-level security with no policy — no row to the applicant, the platform or the street, and no direct write, even with every grant';
end $$;
rollback;
-- Documents can never name a courier photo, so neither can a vitrine.
do $$
declare v_key text;
begin
    select r2_key into v_key from courier_files where state = 'current' limit 1;
    begin
        insert into documents (org_id, uploaded_by, r2_key, content_type, kind)
        values ('11200000-0000-0000-0000-000000000001', '11211211-0000-0000-0000-000000000004',
                v_key, 'image/jpeg', 'photo');
        raise exception 'FAIL: a document points at a courier photo';
    exception when check_violation then null;
    end;
    if storefront_photo_allowed(v_key) then
        raise exception 'FAIL: the street may read a courier photo';
    end if;
    raise notice 'PASS: documents refuse a courier key (constraint), so no gallery, logo, cover or vitrine door can name one';
end $$;

\echo ''
-- Time passing for a decided dossier: its decision and the journal's
-- undo of it age together, as they would.
create or replace function pg_temp.age(p_who uuid, p_by interval)
returns void language sql as $$
    update courier_applications set decided_at = decided_at - p_by where user_id = p_who;
    update platform_actions
       set undo_args = jsonb_set(undo_args, '{decided_at}', to_jsonb((undo_args ->> 'decided_at')::timestamptz - p_by))
     where kind = 'courier' and undone_at is null and undo_args ->> 'user_id' = p_who::text;
$$;

\echo '--- TEST 7: deleted 30 days after a refusal — and the replaced, the unfinished, the idle draft, the deleted account ---'
do $$
declare
    v_due  text[];
    v_mine text[];
    v_key  text;
begin
    -- Replaced photos (Awa's old selfies) and the unfinished licence slot
    -- are due already; Awa's current photos, approved, are not.
    update courier_files set created_at = created_at - interval '2 hours' where state = 'slot';
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    v_due := courier_files_due();
    if not exists (select 1 from courier_files f where f.user_id = '11211211-0000-0000-0000-000000000002'
                                                   and f.state = 'replaced' and f.r2_key = any(v_due))
       or not exists (select 1 from courier_files f where f.state = 'slot' and f.r2_key = any(v_due))
       or exists (select 1 from courier_files f where f.user_id = '11211211-0000-0000-0000-000000000002'
                                               and f.state = 'current' and f.r2_key = any(v_due)) then
        raise exception 'FAIL: due: %', v_due;
    end if;
    -- An applicant purges only their own.
    perform pg_temp.as_('11211211-0000-0000-0000-000000000003');
    v_mine := courier_files_due();
    if exists (select 1 from courier_files f where f.r2_key = any(v_mine)
                                              and f.user_id is distinct from '11211211-0000-0000-0000-000000000003') then
        raise exception 'FAIL: an applicant was handed another''s keys';
    end if;
    if courier_files_purged(v_due) <> 0 then
        raise exception 'FAIL: an applicant purged another person''s photos';
    end if;
    -- A current, not due photo is never forgotten, even by the platform.
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    select r2_key into v_key from courier_files
     where user_id = '11211211-0000-0000-0000-000000000002' and state = 'current' limit 1;
    if courier_files_purged(array[v_key]) <> 0 then
        raise exception 'FAIL: a current photo was forgotten';
    end if;
    if courier_files_purged(v_due) <> cardinality(v_due) then
        raise exception 'FAIL: the due photos were not all forgotten';
    end if;
    if exists (select 1 from courier_files where r2_key = any(v_due)) then
        raise exception 'FAIL: a purged photo is still known';
    end if;
    perform pg_temp.as_(null);
    if pg_temp.refusal('select courier_files_due()') is distinct from 'Connectez-vous d''abord'
       or pg_temp.refusal($q$select courier_files_purged(array['x'])$q$) is distinct from 'Connectez-vous d''abord' then
        raise exception 'FAIL: the purge pair answered nobody';
    end if;
    raise notice 'PASS: replaced and unfinished photos are due, the approved courier''s current ones never; the platform purges all that is due, an applicant only their own, nobody signed out';
end $$;
do $$
declare
    v_keys text[];
begin
    -- Ali refused; 29 days later, still there; 31 days, gone from every door.
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    perform platform_decide_courier_application('11211211-0000-0000-0000-000000000003', 'refuse', 'face', array['selfie', 'id']);
    select array_agg(r2_key) into v_keys from courier_files
     where user_id = '11211211-0000-0000-0000-000000000003' and state = 'current';
    perform pg_temp.age('11211211-0000-0000-0000-000000000003', interval '29 days');
    if not courier_photo_allowed(v_keys[1]) or courier_files_due() && v_keys then
        raise exception 'FAIL: a photo refused 29 days ago is gone already';
    end if;
    perform pg_temp.age('11211211-0000-0000-0000-000000000003', interval '2 days');
    if courier_photo_allowed(v_keys[1]) then
        raise exception 'FAIL: a photo refused 31 days ago is still served';
    end if;
    if (platform_courier_application('11211211-0000-0000-0000-000000000003') -> 'photos')
       <> '{"selfie": null, "id_front": null, "id_back": null, "licence": null}'::jsonb then
        raise exception 'FAIL: the review still names a photo refused 31 days ago';
    end if;
    if not (courier_files_due() @> v_keys) then
        raise exception 'FAIL: the photos refused 31 days ago are not due';
    end if;
    -- The applicant, coming back, purges their own and redoes every photo.
    perform pg_temp.as_('11211211-0000-0000-0000-000000000003');
    if courier_files_purged(courier_files_due()) < cardinality(v_keys) then
        raise exception 'FAIL: the applicant could not purge their own';
    end if;
    if exists (select 1 from courier_files where r2_key = any(v_keys)) then
        raise exception 'FAIL: refused photos outlived their 30 days';
    end if;
    if my_courier_application() -> 'open_steps' <> '["id", "selfie"]'::jsonb then
        raise exception 'FAIL: the steps to redo read %', my_courier_application() -> 'open_steps';
    end if;
    -- An undo is too late now.
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    if pg_temp.refusal(format('select platform_undo(%L)',
           (select a.id from platform_actions_page(null, 50, null) a
             where a.kind = 'courier' and a.after ->> 'user_id' = '11211211-0000-0000-0000-000000000003'
             order by a.at desc limit 1))) is distinct from 'Trop tard : les photos de cette demande sont effacées.' then
        raise exception 'FAIL: a refusal was undone after its photos were deleted';
    end if;
    raise notice 'PASS: refused 29 days ago, kept; 31 days, never served again and named for deletion; purged by the applicant coming back, who redoes every photo; no undo after';
end $$;
do $$
declare v_key text;
begin
    -- A draft left alone 30 days, and an account deleted.
    v_key := pg_temp.photo('11211211-0000-0000-0000-000000000008', 'selfie');
    perform pg_temp.as_('11211211-0000-0000-0000-000000000001');
    if courier_files_due() @> array[v_key] then
        raise exception 'FAIL: a fresh draft''s photo is due';
    end if;
    update courier_applications set updated_at = now() - interval '31 days'
     where user_id = '11211211-0000-0000-0000-000000000008';
    if not (courier_files_due() @> array[v_key]) then
        raise exception 'FAIL: a draft idle 31 days kept its photo';
    end if;
    update courier_applications set updated_at = now() where user_id = '11211211-0000-0000-0000-000000000008';
    delete from auth.users where id = '11211211-0000-0000-0000-000000000008';
    if (select user_id from courier_files where r2_key = v_key) is not null then
        raise exception 'FAIL: the photo of a deleted account lost its key';
    end if;
    if not (courier_files_due() @> array[v_key]) then
        raise exception 'FAIL: the photo of a deleted account is not due';
    end if;
    if courier_files_purged(array[v_key]) <> 1 then
        raise exception 'FAIL: the platform could not purge it';
    end if;
    raise notice 'PASS: a draft idle 30 days and a deleted account''s photos are due; the key outlives the person so the bytes can go';
end $$;

\echo ''
\echo '--- TEST 8: the doors, and Réglages ---'
do $$
declare
    v_fn   text;
    v_open text;
begin
    -- Nothing of 112 for the street.
    select string_agg(p.oid::regprocedure::text, ', ') into v_open
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('courier_rules', 'courier_part_step', 'courier_file_due', 'courier_current_file',
                         'courier_missing_parts', 'courier_open_steps', 'courier_application_open',
                         'courier_person_name', 'courier_reason_label', 'my_courier_application',
                         'courier_application_save', 'courier_application_send', 'courier_upload_slot',
                         'courier_upload_done', 'courier_photo_allowed', 'courier_files_due',
                         'courier_files_purged', 'platform_courier_applications',
                         'platform_courier_application', 'platform_decide_courier_application',
                         'platform_undo_courier_decision')
       and (has_function_privilege('anon', p.oid, 'execute')
            or has_function_privilege('public', p.oid, 'execute'));
    if v_open is not null then
        raise exception 'FAIL: open to the street: %', v_open;
    end if;
    -- The internals for nobody; the doors for a signed-in person.
    foreach v_fn in array array['courier_rules()', 'courier_part_step(text)', 'courier_file_due(courier_files)',
            'courier_current_file(uuid, text)', 'courier_missing_parts(uuid)', 'courier_open_steps(uuid)',
            'courier_application_open()', 'courier_person_name(uuid)', 'courier_reason_label(text)',
            'platform_undo_courier_decision(jsonb)'] loop
        if has_function_privilege('authenticated', v_fn, 'execute') then
            raise exception 'FAIL: % is open to the app', v_fn;
        end if;
    end loop;
    foreach v_fn in array array['my_courier_application()', 'courier_application_save(text, jsonb)',
            'courier_application_send()', 'courier_upload_slot(text, text)', 'courier_upload_done(text)',
            'courier_photo_allowed(text)', 'courier_files_due()', 'courier_files_purged(text[])',
            'platform_courier_applications()', 'platform_courier_application(uuid)',
            'platform_decide_courier_application(uuid, text, text, text[], text)'] loop
        if not has_function_privilege('authenticated', v_fn, 'execute') then
            raise exception 'FAIL: % is closed to a signed-in person', v_fn;
        end if;
    end loop;
    if not exists (select 1 from platform_undo_fns where fn = 'platform_undo_courier_decision') then
        raise exception 'FAIL: the undo is not whitelisted';
    end if;
    raise notice 'PASS: nothing for the street; 10 internals closed to the app; 11 doors for the signed-in, each checking on the server; the undo whitelisted';
end $$;
begin;
set local role anon;
do $$
begin
    begin
        perform courier_photo_allowed('courier/x');
        raise exception 'FAIL: the street asked about a photo';
    exception when insufficient_privilege then null;
    end;
    begin
        perform my_courier_application();
        raise exception 'FAIL: the street read a dossier';
    exception when insufficient_privilege then null;
    end;
    raise notice 'PASS: the street is refused at the photo and the dossier (permission denied)';
end $$;
rollback;
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '11211211-0000-0000-0000-000000000004';
do $$
begin
    begin
        perform platform_set_setting('courier_licence_required', 'true');
        raise exception 'FAIL: a shop owner turned the platform''s switch';
    exception when others then
        if sqlerrm <> 'Réservé à la plateforme' then raise; end if;
    end;
end $$;
set local "request.jwt.claim.sub" = '11211211-0000-0000-0000-000000000001';
do $$
declare
    v_action uuid;
    k text;
begin
    foreach k in array array['courier_licence_required', 'courier_phone_verified'] loop
        if platform_settings_board() -> k ->> 'value' <> 'false' then
            raise exception 'FAIL: Réglages does not list % off', k;
        end if;
        v_action := platform_set_setting(k, 'true');
        if (my_courier_application() -> 'rules' ->> case k when 'courier_licence_required' then 'licence_required'
                                                           else 'phone_verified' end)::boolean is not true then
            raise exception 'FAIL: % on is not read by the dossier', k;
        end if;
        perform platform_undo(v_action);
        if platform_settings_board() -> k ->> 'value' <> 'false' then
            raise exception 'FAIL: « Annuler » did not put % back', k;
        end if;
    end loop;
    raise notice 'PASS: both switches in Réglages, the platform''s alone, journaled, read by the dossier, « Annuler » puts them back';
end $$;
rollback;

update platform_settings set value = :'wave_was'::jsonb where key = 'wave_checkout';

\echo ''
\echo 'test_batch112: done'
