-- ============================================================
-- 112_courier_application.sql — becoming a courier, approved by the
-- platform: a dossier, its photos kept private, and the review.
--
-- The owner approved the proposal: a person who wants to carry fills a
-- dossier, one question per screen — where (a city and its quartiers),
-- when (days and hours), on what (moto, vélo, voiture, tricycle, à pied;
-- a motor vehicle's make, model, colour and plate), a selfie, an identity
-- document front and back (CNIB, passeport or carte consulaire; a driving
-- licence for a moto or a car, optional unless the platform says
-- otherwise), a WhatsApp number, the driver charter — and sends it. The
-- platform opens « Livreurs à valider », sees the selfie and the document
-- side by side, and approves, refuses with a reason the applicant can fix
-- (that step reopens, the rest is kept), or asks for a new photo. Each
-- decision is journaled with its « Annuler » and rings the applicant.
--
-- Today's model is untouched (056/073/099): couriers keeps who may carry
-- and courier_status() still answers pending / approved / suspended.
-- A dossier puts its courier row in « pending » when it is sent — so
-- 105's « Livreurs à valider » count, platform_couriers() and an old app
-- read it exactly as before — and takes it out again when it is sent
-- back to the applicant (a refusal waits on them, not on the platform).
-- register_courier() and decide_courier() stay as they were for an app
-- that does not know dossiers yet; nothing of 056–107 is redefined here.
--
-- THE PHOTOS ARE SENSITIVE. They are stored in the bucket under their own
-- prefix, courier/<user>/<uuid>.<ext>, which no route of the uploads
-- Worker that serves org/ photos will ever serve (both check the prefix
-- first), and which only the Worker's courier routes touch:
--
--   * POST /v1/courier/uploads — the applicant's own photo, as the
--     applicant: courier_upload_slot() names the key (the step must be
--     theirs to fill), the bytes are put, courier_upload_done() makes it
--     the current photo of its part and retires the one it replaces;
--   * GET /v1/courier/objects/<key> — courier_photo_allowed(): yes for a
--     platform admin, for a current photo that is not due for deletion;
--     no for everyone else, the applicant included, and for a stranger;
--   * POST /v1/courier/purge — courier_files_due() names the photos to
--     delete, the Worker deletes them, courier_files_purged() forgets
--     them.
--
-- No table here is readable by an app role: row-level security is on and
-- there are no policies; everything goes through the functions below.
-- The applicant's own read (my_courier_application) says which photos
-- are there, never their keys.
--
-- Deleted 30 days after a refusal — and sooner for what nobody needs: a
-- photo replaced by a newer one, an upload that never finished, a draft
-- left alone for 30 days, the account deleted. No new scheduler: from
-- that moment Postgres never serves the photo again (courier_photo_
-- allowed and the dossier read leave it out), and the bytes are deleted
-- the next time either side reads — the platform opening its couriers,
-- or the applicant opening their dossier — through the purge route.
-- documents can never point at a courier/ key (a constraint), so no
-- vitrine, logo or gallery door can name one either.
--
-- Two platform settings, off as installed, listed in Réglages:
--   courier_licence_required — a moto or a car needs its licence photo;
--   courier_phone_verified   — the WhatsApp number must be proved (109's
--     code) before sending; off until 109's WhatsApp code is set up, so
--     the step offers the proof and takes a typed number meanwhile.
-- RULE M: the payout mobile-money number is asked, kept and shown only
-- while the platform takes mobile payment (076's wave_checkout,
-- wave_on()); otherwise a courier is paid in cash at the door.
--
-- Re-runnable: tables and columns if not exists, functions replaced in
-- place with their own signatures, settings on conflict do nothing.
-- ============================================================

do $$
begin
    if to_regclass('public.couriers') is null
       or to_regclass('public.platform_actions') is null
       or to_regclass('public.platform_undo_fns') is null
       or to_regprocedure('public.my_verified_phone()') is null then
        raise exception '112 needs 056 (couriers), 104 (platform_actions, platform_undo_fns) and 109 (my_verified_phone) applied first';
    end if;
end $$;

insert into platform_settings (key, value) values
    ('courier_licence_required', 'false'),
    ('courier_phone_verified',   'false')
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- 1. The dossier and its photos
-- ------------------------------------------------------------
create table if not exists courier_applications (
    user_id        uuid primary key references profiles(id) on delete cascade,
    status         text not null default 'draft'
                   check (status in ('draft', 'pending', 'refused', 'approved')),
    city           text,
    zones          text[] not null default '{}',
    days           text[] not null default '{}',
    hours_from     text,
    hours_to       text,
    vehicle        text check (vehicle in ('moto', 'velo', 'voiture', 'tricycle', 'pied')),
    vehicle_make   text,
    vehicle_model  text,
    vehicle_colour text,
    vehicle_plate  text,
    id_kind        text check (id_kind in ('cnib', 'passeport', 'carte_consulaire')),
    phone          text,
    phone_verified boolean not null default false,
    payout_number  text,
    charter_version int,
    charter_at     timestamptz,
    sent_at        timestamptz,
    decided_at     timestamptz,
    decided_by     uuid references profiles(id) on delete set null,
    refusal_reason text,
    refusal_note   text,
    reopened       text[] not null default '{}',
    timeline       jsonb not null default '[]'::jsonb,
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now()
);

comment on table courier_applications is
    'A person''s dossier to become a courier (112). Written and read only '
    'through the functions of 112; no policy, so no app role reads it.';

-- One row per photo. user_id is set null, not cascaded, when the account
-- goes: the key must outlive the person so the bytes can still be found
-- and deleted.
create table if not exists courier_files (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid references profiles(id) on delete set null,
    part        text not null check (part in ('selfie', 'id_front', 'id_back', 'licence')),
    r2_key      text not null unique
                check (r2_key ~ '^courier/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp|heic|heif)$'),
    state       text not null default 'slot' check (state in ('slot', 'current', 'replaced')),
    created_at  timestamptz not null default now(),
    done_at     timestamptz,
    replaced_at timestamptz
);

create unique index if not exists courier_files_one_current
    on courier_files (user_id, part) where state = 'current';
create index if not exists courier_files_by_user on courier_files (user_id);

comment on table courier_files is
    'The photos of a courier dossier (112), in the bucket under courier/. '
    'Private: only a platform admin reads them, through the uploads '
    'Worker''s courier route and courier_photo_allowed().';

alter table courier_applications enable row level security;
alter table courier_files enable row level security;
-- No policies on purpose. And no grants either, belt and braces.
do $$
begin
    revoke all on courier_applications, courier_files from public;
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke all on courier_applications, courier_files from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke all on courier_applications, courier_files from authenticated;
    end if;
end $$;

-- A gallery row, a logo or a cover can never name a courier photo: every
-- door that serves org photos starts from documents.
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'documents_never_courier') then
        alter table documents add constraint documents_never_courier
            check (r2_key not like 'courier/%');
    end if;
end $$;

-- ------------------------------------------------------------
-- 2. The rules, and the small helpers
-- ------------------------------------------------------------
-- What the dossier asks, as the platform has set it.
create or replace function courier_rules()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'licence_required', coalesce((select value = 'true'::jsonb from platform_settings
                                       where key = 'courier_licence_required'), false),
        'phone_verified',   coalesce((select value = 'true'::jsonb from platform_settings
                                       where key = 'courier_phone_verified'), false),
        -- RULE M: a mobile-money payout only while Mara takes mobile payment.
        'mobile_money',     wave_on(),
        'charter_version',  1);
$$;

-- The step a photo belongs to.
create or replace function courier_part_step(p_part text)
returns text
language sql
immutable
set search_path = public
as $$
    select case p_part when 'selfie' then 'selfie'
                       when 'id_front' then 'id'
                       when 'id_back' then 'id'
                       when 'licence' then 'id' end;
$$;

-- When a photo must be gone: the account deleted, replaced, never
-- finished, its dossier gone, refused 30 days ago, or a draft left alone
-- for 30 days.
create or replace function courier_file_due(f courier_files)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select f.user_id is null
        or f.state = 'replaced'
        or (f.state = 'slot' and f.created_at < now() - interval '1 hour')
        or not exists (select 1 from courier_applications a where a.user_id = f.user_id)
        or exists (select 1 from courier_applications a
                    where a.user_id = f.user_id
                      and ((a.status = 'refused' and a.decided_at < now() - interval '30 days')
                           or (a.status = 'draft' and a.updated_at < now() - interval '30 days')));
$$;

-- The photo of a part a person has now, if any.
create or replace function courier_current_file(p_user uuid, p_part text)
returns courier_files
language sql
stable
security definer
set search_path = public
as $$
    select f.* from courier_files f
     where f.user_id = p_user and f.part = p_part and f.state = 'current'
       and not courier_file_due(f)
     limit 1;
$$;

-- The photos a dossier still needs, for its vehicle.
create or replace function courier_missing_parts(p_user uuid)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(array_agg(p order by o), '{}')
      from (values ('selfie', 1), ('id_front', 2), ('id_back', 3), ('licence', 4)) v(p, o)
     where (courier_current_file(p_user, p)).id is null
       and (p <> 'licence'
            or ((courier_rules() ->> 'licence_required')::boolean
                and exists (select 1 from courier_applications a
                             where a.user_id = p_user and a.vehicle in ('moto', 'voiture'))));
$$;

-- The steps a person may fill now: all of them on a draft; on a dossier
-- sent back, the reopened ones and any photo that is no longer there;
-- none while it is examined or once approved.
create or replace function courier_open_steps(p_user uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_status text;
    v_open   text[];
begin
    select status, reopened into v_status, v_open
      from courier_applications where user_id = p_user;
    if v_status is null or v_status = 'draft' then
        return array['zone', 'hours', 'vehicle', 'selfie', 'id', 'phone', 'charter'];
    end if;
    if v_status <> 'refused' then
        return '{}';
    end if;
    select coalesce(array_agg(distinct s), '{}') into v_open
      from unnest(v_open || (select coalesce(array_agg(courier_part_step(m)), '{}')
                               from unnest(courier_missing_parts(p_user)) m)) s;
    return v_open;
end;
$$;

-- The dossier the caller may write to, created as a draft the first time.
create or replace function courier_application_open()
returns courier_applications
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_uid     uuid := auth.uid();
    v_courier text;
    v_app     courier_applications%rowtype;
begin
    if v_uid is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    select status into v_courier from couriers where user_id = v_uid;
    if v_courier = 'approved' then
        raise exception 'Vous êtes déjà livreur';
    end if;
    if v_courier = 'suspended' then
        raise exception 'Votre accès livreur est suspendu. Contactez la plateforme.';
    end if;
    insert into courier_applications (user_id) values (v_uid)
    on conflict (user_id) do nothing;
    select * into v_app from courier_applications where user_id = v_uid for update;
    if v_app.status = 'pending' then
        raise exception 'Votre demande est en cours d''examen';
    end if;
    if v_app.status = 'approved' then
        raise exception 'Vous êtes déjà livreur';
    end if;
    return v_app;
end;
$$;

-- A display name, as the platform's other lists write it.
create or replace function courier_person_name(p_user uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                    nullif(btrim(coalesce(p.full_name, '')), ''),
                    'Sans nom')
      from profiles p where p.id = p_user;
$$;

-- ------------------------------------------------------------
-- 3. The applicant's side
-- ------------------------------------------------------------
-- Everything the applicant's pages need — which photos are there, never
-- their keys.
create or replace function my_courier_application()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_uid   uuid := auth.uid();
    v_app   courier_applications%rowtype;
    v_rules jsonb := courier_rules();
begin
    if v_uid is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    select * into v_app from courier_applications where user_id = v_uid;
    return jsonb_build_object(
        'status',          v_app.status,
        'courier_status',  (select status from couriers where user_id = v_uid),
        'city',            v_app.city,
        'zones',           to_jsonb(coalesce(v_app.zones, '{}')),
        'days',            to_jsonb(coalesce(v_app.days, '{}')),
        'hours_from',      v_app.hours_from,
        'hours_to',        v_app.hours_to,
        'vehicle',         v_app.vehicle,
        'vehicle_make',    v_app.vehicle_make,
        'vehicle_model',   v_app.vehicle_model,
        'vehicle_colour',  v_app.vehicle_colour,
        'vehicle_plate',   v_app.vehicle_plate,
        'id_kind',         v_app.id_kind,
        'phone',           v_app.phone,
        'payout_number',   case when (v_rules ->> 'mobile_money')::boolean then v_app.payout_number end,
        'charter_version', v_app.charter_version,
        'files', jsonb_build_object(
            'selfie',   (courier_current_file(v_uid, 'selfie')).id is not null,
            'id_front', (courier_current_file(v_uid, 'id_front')).id is not null,
            'id_back',  (courier_current_file(v_uid, 'id_back')).id is not null,
            'licence',  (courier_current_file(v_uid, 'licence')).id is not null),
        'open_steps',      to_jsonb(courier_open_steps(v_uid)),
        'refusal', case when v_app.status = 'refused' then jsonb_build_object(
            'reason', v_app.refusal_reason,
            'note',   v_app.refusal_note,
            'steps',  to_jsonb(v_app.reopened)) end,
        'timeline',        coalesce(v_app.timeline, '[]'::jsonb),
        'sent_at',         v_app.sent_at,
        'decided_at',      v_app.decided_at,
        'verified_phone',  my_verified_phone(),
        'rules',           v_rules);
end;
$$;

-- Saves one step of the dossier (the step's own fields only), checked.
create or replace function courier_application_save(p_step text, p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_app   courier_applications%rowtype;
    v_rules jsonb := courier_rules();
    v_d     jsonb := coalesce(p_data, '{}'::jsonb);
    v_list  text[];
    v_text  text;
    v_from  text;
    v_to    text;
    v_kind  text;
    v_phone text;
    v_pay   text;
begin
    v_app := courier_application_open();
    if p_step is null or not (p_step = any(courier_open_steps(v_app.user_id))) then
        raise exception 'Cette étape n''est pas à modifier';
    end if;
    if jsonb_typeof(v_d) <> 'object' then
        raise exception 'Réponse invalide';
    end if;

    if p_step = 'zone' then
        v_text := nullif(btrim(coalesce(v_d ->> 'city', '')), '');
        if v_text is null or length(v_text) > 80 then
            raise exception 'Indiquez votre ville';
        end if;
        if jsonb_typeof(coalesce(v_d -> 'zones', '[]')) <> 'array' then
            raise exception 'Réponse invalide';
        end if;
        select coalesce(array_agg(z order by i), '{}') into v_list
          from (select z, min(i) as i
                  from (select btrim(value) as z, i
                          from jsonb_array_elements_text(coalesce(v_d -> 'zones', '[]')) with ordinality t(value, i)) s
                 where z <> '' group by z) u;
        if cardinality(v_list) = 0 then
            raise exception 'Ajoutez au moins un quartier';
        end if;
        if cardinality(v_list) > 12 or exists (select 1 from unnest(v_list) z where length(z) > 40) then
            raise exception '12 quartiers au plus, de 40 lettres au plus';
        end if;
        update courier_applications set city = v_text, zones = v_list, updated_at = now()
         where user_id = v_app.user_id;

    elsif p_step = 'hours' then
        if jsonb_typeof(coalesce(v_d -> 'days', '[]')) <> 'array' then
            raise exception 'Réponse invalide';
        end if;
        select coalesce(array_agg(d order by array_position(
                   array['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'], d)), '{}')
          into v_list
          from (select distinct value as d from jsonb_array_elements_text(coalesce(v_d -> 'days', '[]'))) s;
        if cardinality(v_list) = 0 then
            raise exception 'Choisissez au moins un jour';
        end if;
        if exists (select 1 from unnest(v_list) d
                    where d not in ('lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim')) then
            raise exception 'Jour inconnu';
        end if;
        v_from := btrim(coalesce(v_d ->> 'hours_from', ''));
        v_to   := btrim(coalesce(v_d ->> 'hours_to', ''));
        if v_from !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or v_to !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
            raise exception 'Indiquez vos heures (par exemple 08:00 à 18:00)';
        end if;
        if v_from >= v_to then
            raise exception 'L''heure de fin vient après l''heure de début';
        end if;
        update courier_applications
           set days = v_list, hours_from = v_from, hours_to = v_to, updated_at = now()
         where user_id = v_app.user_id;

    elsif p_step = 'vehicle' then
        v_kind := v_d ->> 'vehicle';
        if v_kind is null or v_kind not in ('moto', 'velo', 'voiture', 'tricycle', 'pied') then
            raise exception 'Choisissez votre moyen de transport';
        end if;
        if v_kind in ('moto', 'voiture', 'tricycle') then
            if nullif(btrim(coalesce(v_d ->> 'vehicle_make', '')), '') is null
               or nullif(btrim(coalesce(v_d ->> 'vehicle_model', '')), '') is null
               or nullif(btrim(coalesce(v_d ->> 'vehicle_colour', '')), '') is null
               or length(btrim(coalesce(v_d ->> 'vehicle_plate', ''))) < 2 then
                raise exception 'Indiquez la marque, le modèle, la couleur et la plaque';
            end if;
            if length(btrim(v_d ->> 'vehicle_make')) > 40 or length(btrim(v_d ->> 'vehicle_model')) > 40
               or length(btrim(v_d ->> 'vehicle_colour')) > 40 or length(btrim(v_d ->> 'vehicle_plate')) > 20 then
                raise exception 'Réponse trop longue';
            end if;
            update courier_applications
               set vehicle = v_kind,
                   vehicle_make   = btrim(v_d ->> 'vehicle_make'),
                   vehicle_model  = btrim(v_d ->> 'vehicle_model'),
                   vehicle_colour = btrim(v_d ->> 'vehicle_colour'),
                   vehicle_plate  = upper(btrim(v_d ->> 'vehicle_plate')),
                   updated_at = now()
             where user_id = v_app.user_id;
        else
            update courier_applications
               set vehicle = v_kind, vehicle_make = null, vehicle_model = null,
                   vehicle_colour = null, vehicle_plate = null, updated_at = now()
             where user_id = v_app.user_id;
        end if;

    elsif p_step = 'id' then
        v_kind := v_d ->> 'id_kind';
        if v_kind is null or v_kind not in ('cnib', 'passeport', 'carte_consulaire') then
            raise exception 'Choisissez votre pièce d''identité';
        end if;
        update courier_applications set id_kind = v_kind, updated_at = now()
         where user_id = v_app.user_id;

    elsif p_step = 'phone' then
        v_phone := regexp_replace(coalesce(v_d ->> 'phone', ''), '[^0-9+]', '', 'g');
        if v_phone !~ '^\+[0-9]{8,15}$' then
            raise exception 'Indiquez votre numéro WhatsApp avec l''indicatif (+226…)';
        end if;
        if (v_rules ->> 'phone_verified')::boolean
           and v_phone is distinct from my_verified_phone() then
            raise exception 'Vérifiez d''abord votre numéro WhatsApp';
        end if;
        -- RULE M: a payout number only while mobile payment is on.
        if (v_rules ->> 'mobile_money')::boolean then
            v_pay := nullif(regexp_replace(coalesce(v_d ->> 'payout_number', ''), '[^0-9+]', '', 'g'), '');
            if v_pay is not null and v_pay !~ '^\+?[0-9]{8,15}$' then
                raise exception 'Numéro Mobile Money invalide';
            end if;
        end if;
        update courier_applications
           set phone = v_phone, payout_number = v_pay, updated_at = now()
         where user_id = v_app.user_id;

    elsif p_step = 'charter' then
        if (v_d ->> 'charter_version') is distinct from (v_rules ->> 'charter_version') then
            raise exception 'Acceptez la charte du livreur';
        end if;
        update courier_applications
           set charter_version = (v_rules ->> 'charter_version')::int, charter_at = now(), updated_at = now()
         where user_id = v_app.user_id;

    else
        -- 'selfie' is a photo: sent through the uploads Worker.
        raise exception 'Cette étape n''est pas à modifier';
    end if;

    return my_courier_application();
end;
$$;

-- « Envoyer ma demande »: every step checked, the dossier to the platform.
create or replace function courier_application_send()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_app      courier_applications%rowtype;
    v_rules    jsonb := courier_rules();
    v_missing  text[];
    v_verified text := my_verified_phone();
    v_first    boolean;
    v_name     text;
begin
    v_app := courier_application_open();
    v_missing := courier_missing_parts(v_app.user_id);

    if v_app.city is null or cardinality(v_app.zones) = 0 then
        raise exception 'Indiquez votre ville et vos quartiers';
    end if;
    if cardinality(v_app.days) = 0 or v_app.hours_from is null or v_app.hours_to is null then
        raise exception 'Choisissez vos jours et vos heures';
    end if;
    if v_app.vehicle is null then
        raise exception 'Choisissez votre moyen de transport';
    end if;
    if v_app.vehicle in ('moto', 'voiture', 'tricycle') and v_app.vehicle_plate is null then
        raise exception 'Indiquez la marque, le modèle, la couleur et la plaque';
    end if;
    if 'selfie' = any(v_missing) then
        raise exception 'Prenez votre selfie';
    end if;
    if v_app.id_kind is null then
        raise exception 'Choisissez votre pièce d''identité';
    end if;
    if 'id_front' = any(v_missing) or 'id_back' = any(v_missing) then
        raise exception 'Photographiez le recto et le verso de votre pièce';
    end if;
    if 'licence' = any(v_missing) then
        raise exception 'Photographiez votre permis de conduire';
    end if;
    if v_app.phone is null then
        raise exception 'Indiquez votre numéro WhatsApp';
    end if;
    if (v_rules ->> 'phone_verified')::boolean and v_app.phone is distinct from v_verified then
        raise exception 'Vérifiez d''abord votre numéro WhatsApp';
    end if;
    if v_app.charter_version is distinct from (v_rules ->> 'charter_version')::int then
        raise exception 'Acceptez la charte du livreur';
    end if;
    -- Sent back for a photo: a new one of that step, taken since.
    if v_app.status = 'refused' then
        if 'selfie' = any(v_app.reopened)
           and coalesce((courier_current_file(v_app.user_id, 'selfie')).done_at, '-infinity') <= v_app.decided_at then
            raise exception 'Reprenez la photo demandée';
        end if;
        if 'id' = any(v_app.reopened)
           and greatest(coalesce((courier_current_file(v_app.user_id, 'id_front')).done_at, '-infinity'),
                        coalesce((courier_current_file(v_app.user_id, 'id_back')).done_at, '-infinity'),
                        coalesce((courier_current_file(v_app.user_id, 'licence')).done_at, '-infinity'))
               <= v_app.decided_at then
            raise exception 'Reprenez la photo demandée';
        end if;
    end if;

    -- A licence kept for a vehicle that needs none is not kept.
    if v_app.vehicle not in ('moto', 'voiture') then
        update courier_files set state = 'replaced', replaced_at = clock_timestamp()
         where user_id = v_app.user_id and part = 'licence' and state = 'current';
    end if;

    v_first := v_app.sent_at is null;
    update courier_applications
       set status = 'pending',
           sent_at = coalesce(sent_at, now()),
           phone_verified = (v_verified is not null and phone = v_verified),
           refusal_reason = null, refusal_note = null, reopened = '{}',
           timeline = timeline || jsonb_build_array(jsonb_build_object(
               'at', now(), 'kind', case when v_first then 'sent' else 'resent' end)),
           updated_at = now()
     where user_id = v_app.user_id;

    -- The platform's queue, as 056 keeps it: one pending courier.
    insert into couriers (user_id, phone, status)
    values (v_app.user_id, v_app.phone, 'pending')
    on conflict (user_id) do update set phone = excluded.phone
     where couriers.status = 'pending';

    v_name := courier_person_name(v_app.user_id);
    begin
        insert into notifications (recipient_id, org_id, kind, message, params)
        select id, null::uuid, 'courier_application',
               'Nouvelle demande de livreur : ' || v_name,
               jsonb_build_object('name', v_name)
          from profiles where is_platform_admin;
    exception when others then
        null;
    end;
    return my_courier_application();
end;
$$;

-- ------------------------------------------------------------
-- 4. The photos, for the uploads Worker (called as the caller)
-- ------------------------------------------------------------
-- The key a new photo goes to — only for a step the caller may fill.
create or replace function courier_upload_slot(p_part text, p_ext text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_app courier_applications%rowtype;
    v_ext text := lower(btrim(coalesce(p_ext, '')));
    v_key text;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    if p_part is null or p_part not in ('selfie', 'id_front', 'id_back', 'licence') then
        raise exception 'Photo inconnue';
    end if;
    if v_ext not in ('jpg', 'png', 'webp', 'heic', 'heif') then
        raise exception 'Photos uniquement';
    end if;
    v_app := courier_application_open();
    if not (courier_part_step(p_part) = any(courier_open_steps(v_app.user_id))) then
        raise exception 'Cette photo n''est pas à refaire';
    end if;
    if (select count(*) from courier_files
         where user_id = v_app.user_id and created_at > now() - interval '1 day') >= 30 then
        raise exception 'Trop de photos envoyées aujourd''hui. Réessayez demain.';
    end if;
    v_key := 'courier/' || v_app.user_id || '/' || gen_random_uuid() || '.' || v_ext;
    insert into courier_files (user_id, part, r2_key) values (v_app.user_id, p_part, v_key);
    return v_key;
end;
$$;

-- The bytes are in: this photo is now its part's, the old one retired.
create or replace function courier_upload_done(p_key text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_file courier_files%rowtype;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    select * into v_file from courier_files
     where r2_key = p_key and user_id = auth.uid() and state = 'slot'
       and created_at > now() - interval '1 hour'
     for update;
    if not found then
        raise exception 'Envoi inconnu';
    end if;
    update courier_files set state = 'replaced', replaced_at = clock_timestamp()
     where user_id = v_file.user_id and part = v_file.part and state = 'current';
    update courier_files set state = 'current', done_at = clock_timestamp() where id = v_file.id;
    update courier_applications set updated_at = now() where user_id = v_file.user_id;
    return v_file.part;
end;
$$;

-- May the caller see this photo? A platform admin, a current photo, not
-- due. Nobody else — not even the person in it.
create or replace function courier_photo_allowed(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
    select caller_is_platform_admin()
       and exists (select 1 from courier_files f
                    where f.r2_key = p_key and f.state = 'current'
                      and not courier_file_due(f));
$$;

-- The photos to delete now: every due one for the platform, the caller's
-- own for an applicant. At most 200 a call.
create or replace function courier_files_due()
returns text[]
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_admin boolean := caller_is_platform_admin();
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    return coalesce((
        select array_agg(k.r2_key order by k.created_at)
          from (select f.r2_key, f.created_at from courier_files f
                 where courier_file_due(f) and (v_admin or f.user_id = auth.uid())
                 order by f.created_at limit 200) k), '{}');
end;
$$;

-- Deleted from the bucket: forgotten here. Only what is due, and only
-- what the caller may purge.
create or replace function courier_files_purged(p_keys text[])
returns int
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_admin boolean := caller_is_platform_admin();
    v_count int;
begin
    if auth.uid() is null then
        raise exception 'Connectez-vous d''abord';
    end if;
    delete from courier_files f
     where f.r2_key = any(coalesce(p_keys, '{}'))
       and courier_file_due(f)
       and (v_admin or f.user_id = auth.uid());
    get diagnostics v_count = row_count;
    return v_count;
end;
$$;

-- ------------------------------------------------------------
-- 5. The platform's side
-- ------------------------------------------------------------
-- « Livreurs à valider »: every dossier sent, waiting first (oldest
-- first), then those sent back, then the decided.
create or replace function platform_courier_applications()
returns table (
    user_id        uuid,
    name           text,
    status         text,
    courier_status text,
    city           text,
    vehicle        text,
    sent_at        timestamptz,
    decided_at     timestamptz,
    refusal_reason text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    perform platform_only();
    return query
    select a.user_id, courier_person_name(a.user_id),
           case when c.status in ('approved', 'suspended') then c.status else a.status end,
           c.status, a.city, a.vehicle, a.sent_at, a.decided_at, a.refusal_reason
      from courier_applications a
      left join couriers c on c.user_id = a.user_id
     where a.status <> 'draft'
     order by case when c.status in ('approved', 'suspended') then 3
                   when a.status = 'pending' then 1
                   when a.status = 'refused' then 2
                   else 3 end,
              case when a.status = 'pending' then a.sent_at end asc nulls last,
              a.decided_at desc nulls last;
end;
$$;

-- One dossier, for the review page: everything, the photo keys included
-- (read through the Worker's courier route, which asks again).
create or replace function platform_courier_application(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
    v_app courier_applications%rowtype;
    v_verified text;
begin
    perform platform_only();
    select * into v_app from courier_applications where user_id = p_user_id;
    if not found then
        raise exception 'Aucune demande de livreur pour cette personne';
    end if;
    select case when left(btrim(u.phone), 1) = '+' then btrim(u.phone) else '+' || btrim(u.phone) end
      into v_verified
      from auth.users u
     where u.id = p_user_id and u.phone_confirmed_at is not null
       and nullif(btrim(coalesce(u.phone, '')), '') is not null;
    return jsonb_build_object(
        'user_id',         v_app.user_id,
        'name',            courier_person_name(v_app.user_id),
        'status',          v_app.status,
        'courier_status',  (select status from couriers where user_id = p_user_id),
        'city',            v_app.city,
        'zones',           to_jsonb(v_app.zones),
        'days',            to_jsonb(v_app.days),
        'hours_from',      v_app.hours_from,
        'hours_to',        v_app.hours_to,
        'vehicle',         v_app.vehicle,
        'vehicle_make',    v_app.vehicle_make,
        'vehicle_model',   v_app.vehicle_model,
        'vehicle_colour',  v_app.vehicle_colour,
        'vehicle_plate',   v_app.vehicle_plate,
        'id_kind',         v_app.id_kind,
        'phone',           v_app.phone,
        'phone_verified',  v_verified is not null and v_app.phone = v_verified,
        'payout_number',   v_app.payout_number,
        'charter_version', v_app.charter_version,
        'charter_at',      v_app.charter_at,
        'sent_at',         v_app.sent_at,
        'decided_at',      v_app.decided_at,
        'refusal', case when v_app.status = 'refused' then jsonb_build_object(
            'reason', v_app.refusal_reason, 'note', v_app.refusal_note,
            'steps', to_jsonb(v_app.reopened)) end,
        'timeline',        v_app.timeline,
        'photos', jsonb_build_object(
            'selfie',   (courier_current_file(p_user_id, 'selfie')).r2_key,
            'id_front', (courier_current_file(p_user_id, 'id_front')).r2_key,
            'id_back',  (courier_current_file(p_user_id, 'id_back')).r2_key,
            'licence',  (courier_current_file(p_user_id, 'licence')).r2_key),
        'rules',           courier_rules());
end;
$$;

-- What a reason is called, in the applicant's bell.
create or replace function courier_reason_label(p_reason text)
returns text
language sql
immutable
set search_path = public
as $$
    select case p_reason
        when 'blurry'     then 'photo floue'
        when 'unreadable' then 'pièce illisible'
        when 'face'       then 'visage différent de la pièce'
        when 'missing'    then 'informations manquantes'
        when 'new_selfie' then 'nouveau selfie demandé'
        when 'new_id'     then 'nouvelle photo de la pièce demandée'
        else 'autre raison' end;
$$;

-- Approve, refuse with a reason (the steps to redo reopen), or ask for a
-- new photo (selfie or ID). Journaled, undoable; the applicant is told.
create or replace function platform_decide_courier_application(
    p_user_id  uuid,
    p_decision text,
    p_reason   text   default null,
    p_steps    text[] default null,
    p_note     text   default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_app     courier_applications%rowtype;
    v_now     timestamptz := clock_timestamp();
    v_courier text;
    v_reason  text;
    v_steps   text[];
    v_note    text := nullif(btrim(coalesce(p_note, '')), '');
    v_name    text;
    v_status  text;
    v_message text;
    v_kind    text;
begin
    perform platform_only();
    select * into v_app from courier_applications where user_id = p_user_id for update;
    if not found then
        raise exception 'Aucune demande de livreur pour cette personne';
    end if;
    if v_app.status <> 'pending' then
        raise exception 'Cette demande n''attend pas de décision';
    end if;
    if length(v_note) > 300 then
        raise exception 'Un mot de 300 caractères au plus';
    end if;
    v_name := courier_person_name(p_user_id);
    select status into v_courier from couriers where user_id = p_user_id;

    if p_decision = 'approve' then
        if v_courier = 'suspended' then
            raise exception 'Ce livreur est suspendu';
        end if;
        v_status := 'approved';
        update courier_applications
           set status = 'approved', decided_at = v_now, decided_by = auth.uid(),
               refusal_reason = null, refusal_note = null, reopened = '{}',
               timeline = timeline || jsonb_build_array(jsonb_build_object('at', v_now, 'kind', 'approved')),
               updated_at = now()
         where user_id = p_user_id;
        insert into couriers (user_id, phone, status, decided_at)
        values (p_user_id, v_app.phone, 'approved', v_now)
        on conflict (user_id) do update
           set status = 'approved', decided_at = v_now,
               phone = coalesce(excluded.phone, couriers.phone);
        v_kind := 'courier_approved';
        v_message := 'Vous êtes livreur Mara : les livraisons vous attendent.';

    elsif p_decision in ('refuse', 'new_photo') then
        if p_decision = 'new_photo' then
            if p_reason not in ('selfie', 'id') then
                raise exception 'Quelle photo ? Le selfie ou la pièce d''identité';
            end if;
            v_reason := 'new_' || p_reason;
            v_steps := array[p_reason];
            v_kind := 'courier_photo';
            v_message := 'Mara demande une nouvelle photo '
                         || case p_reason when 'selfie' then 'de votre selfie.'
                                          else 'de votre pièce d''identité.' end;
        else
            if p_reason is null or p_reason not in ('blurry', 'unreadable', 'face', 'missing', 'other') then
                raise exception 'Choisissez une raison';
            end if;
            if p_reason = 'other' and v_note is null then
                raise exception 'Dites en un mot ce qui ne va pas';
            end if;
            v_reason := p_reason;
            select coalesce(array_agg(distinct s), '{}') into v_steps
              from unnest(coalesce(p_steps, '{}')) s;
            if cardinality(v_steps) = 0 then
                raise exception 'Choisissez l''étape à corriger';
            end if;
            if exists (select 1 from unnest(v_steps) s
                        where s not in ('zone', 'hours', 'vehicle', 'selfie', 'id', 'phone')) then
                raise exception 'Étape inconnue';
            end if;
            v_kind := 'courier_refused';
            v_message := 'Votre demande de livreur est à corriger : '
                         || courier_reason_label(v_reason) || '.'
                         || coalesce(' ' || v_note, '');
        end if;
        v_status := 'refused';
        update courier_applications
           set status = 'refused', decided_at = v_now, decided_by = auth.uid(),
               refusal_reason = v_reason, refusal_note = v_note, reopened = v_steps,
               timeline = timeline || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
                   'at', v_now, 'kind', case when p_decision = 'new_photo' then 'photo' else 'refused' end,
                   'reason', v_reason, 'note', v_note, 'steps', to_jsonb(v_steps)))),
               updated_at = now()
         where user_id = p_user_id;
        -- Back with the applicant: no longer the platform's to validate.
        delete from couriers where user_id = p_user_id and status = 'pending';
    else
        raise exception 'Décision inconnue';
    end if;

    begin
        insert into notifications (recipient_id, org_id, kind, message, params)
        values (p_user_id, null, v_kind, v_message,
                jsonb_strip_nulls(jsonb_build_object('to', 'courier', 'status', v_status,
                    'reason', v_reason, 'note', v_note, 'steps', to_jsonb(v_steps))));
    exception when others then
        null;
    end;

    return platform_log_action(
        null, 'courier',
        'Livreur ' || v_name || ' : '
            || case when v_status = 'approved' then 'approuvé'
                    else 'à corriger (' || courier_reason_label(v_reason) || ')' end,
        jsonb_build_object('user_id', p_user_id, 'name', v_name, 'status', 'pending'),
        jsonb_strip_nulls(jsonb_build_object('user_id', p_user_id, 'name', v_name,
            'status', v_status, 'reason', v_reason, 'steps', to_jsonb(v_steps))),
        'platform_undo_courier_decision',
        jsonb_build_object('user_id', p_user_id, 'status', v_status, 'decided_at', v_now));
end;
$$;

-- « Annuler » (through 104's platform_undo only): the dossier back to
-- « en cours d'examen », if nothing has moved since.
create or replace function platform_undo_courier_decision(p jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_user uuid := (p ->> 'user_id')::uuid;
    v_app  courier_applications%rowtype;
begin
    perform platform_only();
    select * into v_app from courier_applications where user_id = v_user for update;
    if not found or v_app.status is distinct from (p ->> 'status')
       or v_app.decided_at is distinct from (p ->> 'decided_at')::timestamptz then
        raise exception 'La demande a changé depuis : rien à annuler.';
    end if;
    if v_app.status = 'approved' then
        if exists (select 1 from orders where courier_id = v_user
                                          and status in ('ready', 'in_transit')) then
            raise exception 'Ce livreur a une course en cours : suspendez-le plutôt.';
        end if;
        update couriers set status = 'pending' where user_id = v_user and status = 'approved';
    else
        if v_app.decided_at < now() - interval '30 days' then
            raise exception 'Trop tard : les photos de cette demande sont effacées.';
        end if;
        insert into couriers (user_id, phone, status) values (v_user, v_app.phone, 'pending')
        on conflict (user_id) do nothing;
    end if;
    update courier_applications
       set status = 'pending', decided_at = null, decided_by = null,
           refusal_reason = null, refusal_note = null, reopened = '{}',
           timeline = timeline || jsonb_build_array(jsonb_build_object('at', now(), 'kind', 'reopened')),
           updated_at = now()
     where user_id = v_user;
    begin
        insert into notifications (recipient_id, org_id, kind, message, params)
        values (v_user, null, 'courier_pending',
                'Votre demande de livreur est de nouveau à l''étude.',
                jsonb_build_object('to', 'courier', 'status', 'pending'));
    exception when others then
        null;
    end;
end;
$$;

insert into platform_undo_fns (fn) values ('platform_undo_courier_decision')
on conflict do nothing;

-- ------------------------------------------------------------
-- 6. Doors
-- ------------------------------------------------------------
-- Every function here is born closed to anon and PUBLIC (063) and open to
-- authenticated; the internal ones are closed to the app as well.
revoke execute on function courier_rules()                       from public;
revoke execute on function courier_part_step(text)               from public;
revoke execute on function courier_file_due(courier_files)       from public;
revoke execute on function courier_current_file(uuid, text)      from public;
revoke execute on function courier_missing_parts(uuid)           from public;
revoke execute on function courier_open_steps(uuid)              from public;
revoke execute on function courier_application_open()            from public;
revoke execute on function courier_person_name(uuid)             from public;
revoke execute on function courier_reason_label(text)            from public;
revoke execute on function my_courier_application()              from public;
revoke execute on function courier_application_save(text, jsonb) from public;
revoke execute on function courier_application_send()            from public;
revoke execute on function courier_upload_slot(text, text)       from public;
revoke execute on function courier_upload_done(text)             from public;
revoke execute on function courier_photo_allowed(text)           from public;
revoke execute on function courier_files_due()                   from public;
revoke execute on function courier_files_purged(text[])          from public;
revoke execute on function platform_courier_applications()       from public;
revoke execute on function platform_courier_application(uuid)    from public;
revoke execute on function platform_decide_courier_application(uuid, text, text, text[], text) from public;
revoke execute on function platform_undo_courier_decision(jsonb) from public;

do $$
declare
    f text;
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        foreach f in array array[
            'courier_rules()', 'courier_part_step(text)', 'courier_file_due(courier_files)',
            'courier_current_file(uuid, text)', 'courier_missing_parts(uuid)',
            'courier_open_steps(uuid)', 'courier_application_open()', 'courier_person_name(uuid)',
            'courier_reason_label(text)', 'my_courier_application()',
            'courier_application_save(text, jsonb)', 'courier_application_send()',
            'courier_upload_slot(text, text)', 'courier_upload_done(text)',
            'courier_photo_allowed(text)', 'courier_files_due()', 'courier_files_purged(text[])',
            'platform_courier_applications()', 'platform_courier_application(uuid)',
            'platform_decide_courier_application(uuid, text, text, text[], text)',
            'platform_undo_courier_decision(jsonb)'] loop
            execute format('revoke execute on function %s from anon', f);
        end loop;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        -- Internal: called by the functions below, as their owner.
        foreach f in array array[
            'courier_rules()', 'courier_part_step(text)', 'courier_file_due(courier_files)',
            'courier_current_file(uuid, text)', 'courier_missing_parts(uuid)',
            'courier_open_steps(uuid)', 'courier_application_open()', 'courier_person_name(uuid)',
            'courier_reason_label(text)',
            -- Only 104's platform_undo calls it, from its whitelist.
            'platform_undo_courier_decision(jsonb)'] loop
            execute format('revoke execute on function %s from authenticated', f);
        end loop;
        -- The applicant's doors, and the Worker's (it calls as the caller);
        -- each checks the caller on the server.
        grant execute on function my_courier_application()              to authenticated;
        grant execute on function courier_application_save(text, jsonb) to authenticated;
        grant execute on function courier_application_send()            to authenticated;
        grant execute on function courier_upload_slot(text, text)       to authenticated;
        grant execute on function courier_upload_done(text)             to authenticated;
        grant execute on function courier_photo_allowed(text)           to authenticated;
        grant execute on function courier_files_due()                   to authenticated;
        grant execute on function courier_files_purged(text[])          to authenticated;
        -- The platform's; each refuses anyone else (platform_only).
        grant execute on function platform_courier_applications()       to authenticated;
        grant execute on function platform_courier_application(uuid)    to authenticated;
        grant execute on function platform_decide_courier_application(uuid, text, text, text[], text) to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
