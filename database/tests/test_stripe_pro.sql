-- ============================================================
-- test_stripe_pro.sql — Kaj Pro by card, through Stripe (082). Phone block 52.
--
-- The claims: nothing starts while the platform's switch is off; only an
-- administrator of the business starts, and the amount and currency are
-- the console's Pro prices, never the caller's; plan_terms() says whether
-- the card is open; Stripe's word that a subscription is active makes the
-- business Pro to the end of the paid period, a second delivery changes
-- nothing, a renewal moves the date on, a cancellation leaves what was
-- paid; a longer Wave date or an endless gift is never shortened; the
-- owner reads where theirs stands, a stranger reads nothing; and
-- stripe_settle answers neither an app user nor the public.
-- ============================================================
\set ON_ERROR_STOP on

\set owner '''52525252-0000-0000-0000-000000000001'''
\set other '''52525252-0000-0000-0000-000000000002'''
\set plat  '''52525252-0000-0000-0000-000000000003'''
\set shop  '''52000000-0000-0000-0000-000000000001'''
\set gift  '''52000000-0000-0000-0000-000000000002'''

do $$ begin
    if not exists (select 1 from pg_roles where rolname='authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname='anon') then
        create role anon nologin;
    end if;
end $$;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users (id, phone, email, raw_user_meta_data) values
    (:owner, '+22652000001', 'awa52@example.com', '{"full_name": "Awa"}'),
    (:other, '+22652000002', null, '{"full_name": "Autre"}'),
    (:plat,  '+22652000003', null, '{"full_name": "Plateforme"}');
update profiles set is_platform_admin = true where id = :plat;
insert into orgs (id, name, slug, profile, default_currency) values
    (:shop, 'Boutique Carte', 'carte-52', 'retail', 'XOF'),
    (:gift, 'Boutique Cadeau', 'cadeau-52', 'retail', 'XOF');
update orgs set plan = 'pro', plan_until = null where id = :gift;
insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility) values
    (:shop, :owner, 'owner', 'org', :shop, 'full'),
    (:gift, :owner, 'owner', 'org', :gift, 'full');

\echo ''
\echo '--- TEST 1: closed until the platform opens it ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '52525252-0000-0000-0000-000000000001';
do $$ begin
    if (plan_terms() ->> 'stripe_on')::boolean then
        raise exception 'FAIL: the card is open before the platform opened it';
    end if;
    begin
        perform stripe_begin('52000000-0000-0000-0000-000000000001', 'month');
        raise exception 'FAIL: a card subscription started while closed';
    exception when others then
        if sqlerrm not like 'Le paiement par carte n''est pas encore ouvert%' then raise; end if;
    end;
    raise notice 'PASS: closed, and plan_terms says so';
end $$;
rollback;

-- The platform opens it, and sets its prices, from the console.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '52525252-0000-0000-0000-000000000003';
select set_platform_setting('stripe_on', 'true');
select set_platform_setting('pro_price_month', '3000');
select set_platform_setting('pro_price_year', '30000');
commit;

\echo ''
\echo '--- TEST 2: an administrator starts, at the console''s price ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '52525252-0000-0000-0000-000000000001';
do $$
declare b jsonb;
begin
    if not (plan_terms() ->> 'stripe_on')::boolean then
        raise exception 'FAIL: plan_terms does not say the card is open';
    end if;
    b := stripe_begin('52000000-0000-0000-0000-000000000001', 'year');
    if (b ->> 'amount')::numeric <> 30000 or b ->> 'currency' <> 'xof'
       or b ->> 'period' <> 'year' or b ->> 'org_name' <> 'Boutique Carte'
       or b ->> 'email' <> 'awa52@example.com' then
        raise exception 'FAIL: the start is not the console''s price: %', b;
    end if;
    if (stripe_begin('52000000-0000-0000-0000-000000000001', 'month') ->> 'amount')::numeric <> 3000 then
        raise exception 'FAIL: the month is not the console''s month';
    end if;
    begin
        perform stripe_begin('52000000-0000-0000-0000-000000000001', 'week');
        raise exception 'FAIL: a week was taken';
    exception when others then
        if sqlerrm not like 'Période inconnue%' then raise; end if;
    end;
    raise notice 'PASS: 30 000 xof a year, 3 000 a month, nothing else';
end $$;
rollback;

begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '52525252-0000-0000-0000-000000000002';
do $$ begin
    begin
        perform stripe_begin('52000000-0000-0000-0000-000000000001', 'month');
        raise exception 'FAIL: a stranger subscribed someone else''s business';
    exception when others then
        if sqlerrm not like 'Seul un administrateur%' then raise; end if;
    end;
    if my_stripe_subscription('52000000-0000-0000-0000-000000000001') is not null
       or stripe_customer_of('52000000-0000-0000-0000-000000000001') is not null then
        raise exception 'FAIL: a stranger reads the subscription';
    end if;
    raise notice 'PASS: a stranger starts nothing and reads nothing';
end $$;
rollback;

\echo ''
\echo '--- TEST 3: Stripe says active: Pro to the end of the paid period ---'
do $$
declare
    r jsonb;
    until_was date;
begin
    r := stripe_settle('52000000-0000-0000-0000-000000000001', 'sub_52', 'cus_52',
                       'active', 'month', '2030-03-10 12:00+00', false);
    if not (r ->> 'active')::boolean then
        raise exception 'FAIL: an active subscription did not activate: %', r;
    end if;
    select plan_until into until_was from orgs where id = '52000000-0000-0000-0000-000000000001';
    if org_plan('52000000-0000-0000-0000-000000000001') <> 'pro' or until_was <> '2030-03-11' then
        raise exception 'FAIL: not Pro to the paid end and a day: %', until_was;
    end if;
    -- Stripe delivers the same event again.
    perform stripe_settle('52000000-0000-0000-0000-000000000001', 'sub_52', 'cus_52',
                          'active', 'month', '2030-03-10 12:00+00', false);
    if (select plan_until from orgs where id = '52000000-0000-0000-0000-000000000001') <> until_was
       or (select count(*) from stripe_subscriptions
            where org_id = '52000000-0000-0000-0000-000000000001') <> 1 then
        raise exception 'FAIL: a second delivery changed something';
    end if;
    -- The renewal.
    perform stripe_settle('52000000-0000-0000-0000-000000000001', 'sub_52', 'cus_52',
                          'active', 'month', '2030-04-10 12:00+00', false);
    if (select plan_until from orgs where id = '52000000-0000-0000-0000-000000000001') <> '2030-04-11' then
        raise exception 'FAIL: the renewal did not move the date on';
    end if;
    -- Cancelled: Pro runs to what was paid, no further.
    perform stripe_settle('52000000-0000-0000-0000-000000000001', 'sub_52', null,
                          'canceled', null, null, false);
    if (select plan_until from orgs where id = '52000000-0000-0000-0000-000000000001') <> '2030-04-11'
       or (select customer_id from stripe_subscriptions
            where org_id = '52000000-0000-0000-0000-000000000001') <> 'cus_52'
       or (select status from stripe_subscriptions
            where org_id = '52000000-0000-0000-0000-000000000001') <> 'canceled' then
        raise exception 'FAIL: a cancellation took back what was paid, or lost the customer';
    end if;
    if not exists (select 1 from notifications
                    where org_id = '52000000-0000-0000-0000-000000000001' and kind = 'pro_active') then
        raise exception 'FAIL: the owner was not told Pro is active';
    end if;
    raise notice 'PASS: active, idempotent, renewed, cancelled to the paid end';
end $$;

\echo ''
\echo '--- TEST 4: never shorter than what the business already has ---'
do $$ begin
    update orgs set plan_until = '2031-01-01' where id = '52000000-0000-0000-0000-000000000001';
    perform stripe_settle('52000000-0000-0000-0000-000000000001', 'sub_52b', 'cus_52',
                          'active', 'month', '2030-05-10 12:00+00', false);
    if (select plan_until from orgs where id = '52000000-0000-0000-0000-000000000001') <> '2031-01-01' then
        raise exception 'FAIL: a longer Wave date was shortened';
    end if;
    perform stripe_settle('52000000-0000-0000-0000-000000000002', 'sub_52g', 'cus_52g',
                          'active', 'month', '2030-05-10 12:00+00', false);
    if (select plan_until from orgs where id = '52000000-0000-0000-0000-000000000002') is not null then
        raise exception 'FAIL: an endless gift was given an end';
    end if;
    if (stripe_settle('52000000-0000-0000-0000-0000000000ff', 'sub_x', 'cus_x',
                      'active', 'month', now(), false) ->> 'ok')::boolean then
        raise exception 'FAIL: a business that does not exist was settled';
    end if;
    raise notice 'PASS: the longer date and the gift stay, a stranger id is refused';
end $$;

\echo ''
\echo '--- TEST 5: the owner reads theirs; the Worker''s function is the Worker''s ---'
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '52525252-0000-0000-0000-000000000001';
do $$
declare s jsonb := my_stripe_subscription('52000000-0000-0000-0000-000000000001');
begin
    if s ->> 'status' <> 'active' or not (s ->> 'has_customer')::boolean
       or s ? 'customer_id' then
        raise exception 'FAIL: the owner does not read theirs as it stands: %', s;
    end if;
    if stripe_customer_of('52000000-0000-0000-0000-000000000001') <> 'cus_52' then
        raise exception 'FAIL: the Worker cannot find the owner''s customer';
    end if;
    raise notice 'PASS: % — the customer id stays out of the app', s ->> 'status';
end $$;
rollback;

-- The stub hands every function to everyone; 082 takes stripe_settle back.
grant execute on function stripe_settle(uuid, text, text, text, text, timestamptz, boolean)
    to authenticated, anon;
\ir ../migrations/082_stripe_pro.sql
do $$ begin
    if has_function_privilege('authenticated',
           'stripe_settle(uuid, text, text, text, text, timestamptz, boolean)', 'execute')
       or has_function_privilege('anon',
           'stripe_settle(uuid, text, text, text, text, timestamptz, boolean)', 'execute')
       or has_function_privilege('anon', 'stripe_begin(uuid, text)', 'execute') then
        raise exception 'FAIL: an app user or the public can run the Worker''s function';
    end if;
    if not has_function_privilege('authenticated', 'plan_terms()', 'execute')
       or not has_function_privilege('authenticated', 'stripe_begin(uuid, text)', 'execute') then
        raise exception 'FAIL: the owner cannot read the terms or start';
    end if;
    raise notice 'PASS: stripe_settle is the service role''s alone';
end $$;
update platform_settings set value = 'false' where key = 'stripe_on';
update platform_settings set value = '2500'  where key = 'pro_price_month';
update platform_settings set value = '25000' where key = 'pro_price_year';

\echo ''
\echo 'test_stripe_pro: all passed'
