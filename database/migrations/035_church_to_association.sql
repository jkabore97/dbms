-- ============================================================
-- 035_church_to_association.sql — the church profile becomes association.
--
-- A church and a neighbourhood association keep books the same way: members,
-- and money given by them or spent for them. The app was written church-first
-- and the word was everywhere; this makes "Association" the name a new business
-- picks and the word it reads, and migrates the businesses already on the
-- church profile so they read as associations too — with every row of their
-- data intact.
--
-- HOW DEEP, AND WHY NOT DEEPER. This renames what a user sees (the profile
-- value, and every French label — done in the app) and nothing the database
-- names internally. The physical `church_members` table keeps its name. That
-- is deliberate, not laziness: functions created in earlier migrations (member
-- giving statements in 006, the console's data catalog in 008) name
-- `church_members` in their bodies, and those migrations run *before* this one
-- every single time the paste-once bundle is applied. Renaming the table here
-- and recreating those functions to say `members` would work on a first run and
-- fail on the second, when 006 and 008 rebuild their references against a table
-- that no longer exists. Re-runnability is a hard requirement of the bundle, so
-- the table name stays `church_members` and only the profile value moves.
--
-- What DOES change here: the profile value 'church' -> 'association' on existing
-- businesses, and the three functions that decide behaviour by profile now
-- accept both values, so nothing depends on the migration having reached every
-- row before the code does.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Businesses already on the church profile read as associations now.
--    Idempotent.
-- ------------------------------------------------------------
update orgs set profile = 'association' where profile = 'church';

-- ------------------------------------------------------------
-- 2. The three functions that branch on profile accept both values, so a
--    business created or approved as either seeds the same chart, and so this
--    does not depend on step 1 having run first. Only that one condition each
--    changes; the rest is 011 / 017 / 014 verbatim.
-- ------------------------------------------------------------

-- create_org (011): seed the members/association chart for either value.
create or replace function create_org(
    p_name     text,
    p_slug     text,
    p_profile  text default 'generic',
    p_currency text default 'XOF'
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org_id uuid;
begin
    if not exists(select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Only a platform admin can create a new business';
    end if;

    insert into orgs (name, slug, profile, default_currency)
    values (p_name, p_slug, p_profile, p_currency)
    returning id into v_org_id;

    insert into memberships (org_id, user_id, role, scope_kind, scope_id)
    values (v_org_id, auth.uid(), 'owner', 'org', v_org_id);

    if p_profile in ('church', 'association') then
        perform seed_church_accounts(v_org_id);
    elsif p_profile = 'retail' then
        perform seed_retail_accounts(v_org_id);
    else
        insert into accounts (org_id, code, name, type) values
            (v_org_id, '1000', 'Cash on Hand',        'asset'),
            (v_org_id, '1010', 'Bank Account',        'asset'),
            (v_org_id, '1020', 'Mobile Money',        'asset'),
            (v_org_id, '4000', 'Sales',                'income'),
            (v_org_id, '5000', 'Purchases',            'expense'),
            (v_org_id, '5010', 'Operating Expenses',   'expense')
        on conflict (org_id, code) do nothing;
    end if;

    return v_org_id;
end;
$$;

-- approve_org_application (017): same, for a business born from an application.
create or replace function approve_org_application(
    p_application_id uuid,
    p_note           text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor uuid := auth.uid();
    v_app   org_applications%rowtype;
    v_org   uuid;
begin
    if v_actor is null then
        raise exception 'approve_org_application() needs a signed-in caller';
    end if;

    if not exists (select 1 from profiles where id = v_actor and is_platform_admin) then
        raise exception 'Only a platform admin can approve a business';
    end if;

    select * into v_app from org_applications
    where id = p_application_id for update;
    if not found then
        raise exception 'No such application';
    end if;
    if v_app.status <> 'pending' then
        raise exception 'This application has already been %', v_app.status;
    end if;

    if exists (select 1 from orgs where slug = v_app.slug) then
        raise exception
            'The address % was taken while this was waiting. Ask them for another.',
            v_app.slug;
    end if;

    insert into orgs (name, slug, profile, default_currency)
    values (v_app.name, v_app.slug, v_app.profile, v_app.currency)
    returning id into v_org;

    insert into memberships (org_id, user_id, role, scope_kind, scope_id)
    values (v_org, v_app.applicant_id, 'owner', 'org', v_org)
    on conflict do nothing;

    if v_app.profile in ('church', 'association') then
        perform seed_church_accounts(v_org);
    elsif v_app.profile = 'retail' then
        perform seed_retail_accounts(v_org);
    elsif v_app.profile = 'farm' then
        perform seed_farm_accounts(v_org);
    else
        insert into accounts (org_id, code, name, type) values
            (v_org, '1000', 'Cash on Hand',      'asset'),
            (v_org, '1010', 'Bank Account',      'asset'),
            (v_org, '1020', 'Mobile Money',      'asset'),
            (v_org, '4000', 'Sales',             'income'),
            (v_org, '5000', 'Purchases',         'expense'),
            (v_org, '5010', 'Operating Expenses','expense')
        on conflict (org_id, code) do nothing;
    end if;

    update org_applications set
        status        = 'approved',
        decision_note = nullif(btrim(coalesce(p_note, '')), ''),
        reviewed_by   = v_actor,
        reviewed_at   = now(),
        org_id        = v_org
    where id = p_application_id;

    return v_org;
end;
$$;

-- update_org (014): 'association' is a known profile; 'church' stays accepted
-- so a business mid-migration is never refused its own edit.
create or replace function update_org(
    p_org_id   uuid,
    p_name     text default null,
    p_slug     text default null,
    p_profile  text default null,
    p_currency text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_actor   uuid := auth.uid();
    v_name    text := nullif(btrim(coalesce(p_name, '')), '');
    v_slug    text := nullif(lower(btrim(coalesce(p_slug, ''))), '');
    v_profile text := nullif(btrim(coalesce(p_profile, '')), '');
    v_problem text;
begin
    if v_actor is null then
        raise exception 'update_org() needs a signed-in caller';
    end if;

    if not is_org_admin(p_org_id) then
        raise exception 'You cannot change this business';
    end if;

    if not exists (select 1 from orgs where id = p_org_id) then
        raise exception 'No such business';
    end if;

    if exists (select 1 from orgs where id = p_org_id and archived_at is not null) then
        raise exception 'This business is archived. Restore it before changing it.';
    end if;

    if v_slug is not null then
        v_problem := org_slug_problem(v_slug);
        if v_problem is not null then
            raise exception '%', v_problem;
        end if;
        if exists (select 1 from orgs where slug = v_slug and id <> p_org_id) then
            raise exception 'That address is already taken.';
        end if;
    end if;

    if v_profile is not null
       and v_profile not in ('church', 'association', 'farm', 'retail', 'generic') then
        raise exception 'Unknown profile: %', v_profile;
    end if;

    update orgs set
        name             = coalesce(v_name, name),
        slug             = coalesce(v_slug, slug),
        profile          = coalesce(v_profile, profile),
        default_currency = coalesce(nullif(btrim(coalesce(p_currency, '')), ''),
                                    default_currency)
    where id = p_org_id;

    return p_org_id;
end;
$$;

notify pgrst, 'reload schema';
