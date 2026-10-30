-- ============================================================
-- 151_welcome_cauris.sql — a welcome gift of cauris for every new business.
--
-- The owner: « Je vais offrir 5000 cauris à toute nouvelle boutique,
-- c'est-à-dire tout nouvel inscrit qui a créé une nouvelle boutique … Ce
-- sera équivalent à 3 mois d'utilisation gratuite de Marakaj Pro. »
--
-- Before this, a gift of cauris was the platform's hand only (100's
-- platform_give_cauris, one business at a time from the console): a new
-- business started at 0 while the launch adverts promise 5 000.
--
-- The design:
--   * The gift is a 100 promotion: a cauris_promos row (left_points,
--     expires_on) and its 'promo' ledger line, exactly what the console's
--     « Offrir des cauris » writes — so the wallet, « Mes cauris », spending
--     (cauris_take spends the soonest promotion first), expiry and the
--     console's lists read it with no change. Mara Pro complet costs 1 500
--     cauris for 30 days (085's cauris_costs 'pro_all'): 5 000 open it three
--     times.
--   * Where: org_create_core (111, as 142 left it) — the one place a
--     business is born with its owner: 111's create_my_business (the app's
--     « Créer mon activité ») and create_org. It is 142's verbatim, with
--     cauris_welcome_give() called once the owner is in.
--   * Who: a shop, a farm and an association alike (100: an association
--     earns no cauris, but what the platform gives it, it may spend — its
--     tontines, its accounting, Mara Pro complet). Never a showcase vitrine
--     (094's seed does not come through here; the flag is checked anyway).
--   * Once per person, ever: cauris_welcomes keeps who received it, and
--     keeps it when the business is deleted — so a gift cannot buy the Pro
--     that opens a second business (099) which brings a second gift, and
--     deleting and recreating a business brings nothing.
--   * How much and for how long are the platform's settings:
--     cauris_welcome_points (5 000; 0 stops the gift) and
--     cauris_welcome_days (120: four months to spend three months of Pro).
--   * The owner's bell rings (« cauris_promo », the app's existing kind),
--     saying what the gift opens. A bell never costs the gift.
--   * Nothing backfilled: a business already here keeps what it has.
--
-- Shop, farm, association: the same gift; nothing else changes for any of
-- them. The app needs no update: « Mes cauris » already shows a promotion
-- and its date. Re-runnable.
-- ============================================================

insert into platform_settings (key, value) values
    ('cauris_welcome_points', '5000'),
    ('cauris_welcome_days',   '120')
on conflict (key) do nothing;

-- Who has received the welcome gift: one row per person, kept when the
-- business is deleted (org_id is set to null then).
create table if not exists cauris_welcomes (
    user_id    uuid primary key references profiles(id) on delete cascade,
    org_id     uuid references orgs(id) on delete set null,
    points     integer not null check (points > 0),
    expires_on date not null,
    created_at timestamptz not null default now()
);
alter table cauris_welcomes enable row level security;
-- No policies: written by cauris_welcome_give, read by the platform's
-- functions only.
comment on table cauris_welcomes is
    'The welcome gift of cauris (151): who received it, once per person, for which business.';

-- The gift itself: to a business just born, for its owner, once per person.
create or replace function cauris_welcome_give(p_org_id uuid, p_owner uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_points  int := cauris_param('cauris_welcome_points', 5000);
    v_days    int := cauris_param('cauris_welcome_days', 120);
    v_until   date;
    v_promo   uuid;
    v_cost    int;
    v_months  int;
begin
    if p_org_id is null or p_owner is null or v_points <= 0 or v_days <= 0 then
        return 0;
    end if;
    if exists (select 1 from orgs where id = p_org_id and showcase) then
        return 0;
    end if;

    perform pg_advisory_xact_lock(hashtext('cauris_welcome:' || p_owner::text));
    if exists (select 1 from cauris_welcomes where user_id = p_owner) then
        return 0;
    end if;

    v_until := cauris_today() + v_days;
    perform pg_advisory_xact_lock(hashtext('cauris:' || p_org_id::text));
    insert into cauris_promos (org_id, points, left_points, expires_on, note, given_by)
    values (p_org_id, v_points, v_points, v_until, 'Cadeau de bienvenue', null)
    returning id into v_promo;
    insert into cauris_ledger (org_id, delta, reason, ref, note)
    values (p_org_id, v_points, 'promo', v_promo::text,
            'Cadeau de bienvenue · avant le ' || to_char(v_until, 'DD/MM/YYYY'));
    insert into cauris_welcomes (user_id, org_id, points, expires_on)
    values (p_owner, p_org_id, v_points, v_until);

    select cost into v_cost from cauris_costs where feature = 'pro_all';
    v_months := case when coalesce(v_cost, 0) > 0 then v_points / v_cost else 0 end;
    begin
        perform notify_org_admins(p_org_id, 'cauris_promo',
            'Bienvenue sur Marakaj ! Nous vous offrons ' || v_points || ' cauris'
            || case when v_months >= 2 then ' : de quoi ouvrir Marakaj Pro ' || v_months || ' mois'
                    when v_months = 1 then ' : de quoi ouvrir Marakaj Pro 1 mois'
                    else '' end
            || ', à utiliser avant le ' || to_char(v_until, 'DD/MM/YYYY') || '.',
            jsonb_build_object('to', 'shop', 'points', v_points, 'note', 'Cadeau de bienvenue',
                               'until', v_until));
    exception when others then
        null;  -- a bell never costs the gift
    end;
    return v_points;
end;
$$;

-- A business, by its owner: 142's org_create_core, verbatim but for the
-- welcome gift at the end.
create or replace function org_create_core(
    p_owner    uuid,
    p_name     text,
    p_slug     text,
    p_profile  text,
    p_currency text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_org_id uuid;
begin
    -- 142: the owner's seller commitments, when the owner is the caller.
    if p_owner is not null and p_owner = auth.uid() and not terms_ok(p_owner, 'seller') then
        raise exception 'Acceptez d''abord les engagements du vendeur pour créer une activité (mettez l''application à jour si elle ne vous les montre pas).';
    end if;

    insert into orgs (name, slug, profile, default_currency)
    values (p_name, p_slug, p_profile, p_currency)
    returning id into v_org_id;

    insert into memberships (org_id, user_id, role, scope_kind, scope_id)
    values (v_org_id, p_owner, 'owner', 'org', v_org_id);

    if p_profile in ('church', 'association') then
        perform seed_church_accounts(v_org_id);
    elsif p_profile = 'retail' then
        perform seed_retail_accounts(v_org_id);
    elsif p_profile = 'farm' then
        perform seed_farm_accounts(v_org_id);
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

    -- 151: the welcome gift, once per person.
    perform cauris_welcome_give(v_org_id, p_owner);

    return v_org_id;
end;
$$;


-- Internal, both: org_create_core calls the gift as its owner, and
-- org_create_core stays 111's (the app comes in through create_my_business
-- and create_org). Restated here since it is redefined.
revoke execute on function cauris_welcome_give(uuid, uuid) from public;
revoke execute on function org_create_core(uuid, text, text, text, text) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function cauris_welcome_give(uuid, uuid) from anon;
        revoke execute on function org_create_core(uuid, text, text, text, text) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function cauris_welcome_give(uuid, uuid) from authenticated;
        revoke execute on function org_create_core(uuid, text, text, text, text) from authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
