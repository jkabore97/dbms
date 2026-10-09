-- ============================================================
-- 121_stripe_usd.sql — Mara Pro by card, charged in dollars.
--
-- The owner (Mara's Stripe account is in the US): « Keep the prices in
-- FCFA and change it to dollar at checkout. »
--
--   1. stripe_xof_per_usd: a platform setting, the FCFA for one dollar
--      (seeded 600), changed from the command center's Réglages like
--      every other number — a whole number, and never zero (the one
--      line added to 105's platform_set_setting).
--   2. stripe_usd_raw_cents(amount): a Pro price, in pro_currency, as
--      dollar cents — ceil(amount × 100 / rate), so rounded up to the
--      cent, computed in numeric (a rate of 1 on a 30 000 000 F year is
--      3 000 000 000 cents, past an int). FCFA (XOF, or XAF at the same
--      parity) is converted; a price already in USD is charged as it is;
--      any other currency, or no rate the server can read (061's older
--      set_platform_setting checks nothing), is null: no card.
--      stripe_usd_cents(amount): the same cents as Stripe takes them, an
--      int — null as well under Stripe's 50-cent minimum and above its
--      8-digit unit_amount (99 999 999 cents), so plan_terms never says
--      a « ≈ » the card would refuse, and never fails on a big number.
--   3. stripe_begin (082's, the Worker's only source of the amount):
--      'amount' is now the dollar cents and 'currency' 'usd' — what Stripe
--      charges, computed here, never by the app or the Worker; 'price'
--      and 'price_currency' are the Pro price as the app shows it, for the
--      line's name on Stripe's page (« Mara Pro · Mensuel · 15 000 FCFA »).
--      Refused in French with no rate, under Stripe's 50-cent minimum or
--      above its 99 999 999 cents.
--      An older Worker reads 'amount' and 'currency' as before and
--      charges the same dollars.
--   4. plan_terms (107's): two more keys, stripe_usd_month and
--      stripe_usd_year, the same cents from the same function, so the
--      app's « ≈ $25.00 par mois, payé en dollars » is what Stripe asks.
--
-- Every price the app shows stays in FCFA, as before. stripe_settle is
-- untouched: it reads the subscription's status and period, never an
-- amount. A running subscription (none live when this was written)
-- renews at the price Stripe took it at. Shop, farm and association
-- alike: Mara Pro is the same for the three kinds.
-- ============================================================

insert into platform_settings (key, value) values ('stripe_xof_per_usd', '600')
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- 2. A price, as dollar cents
-- ------------------------------------------------------------
create or replace function stripe_usd_raw_cents(p_amount numeric)
returns numeric
language plpgsql
stable
set search_path = public
as $$
declare
    v_cur  text := upper(coalesce(plan_setting('pro_currency') #>> '{}', 'XOF'));
    v_raw  jsonb := plan_setting('stripe_xof_per_usd');
    v_rate numeric;
begin
    if p_amount is null or p_amount <= 0 then
        return null;
    end if;
    if v_cur = 'USD' then
        return ceil(p_amount * 100);
    end if;
    if v_cur not in ('XOF', 'XAF') then
        return null;
    end if;
    if jsonb_typeof(v_raw) = 'number' then
        v_rate := (v_raw #>> '{}')::numeric;
    end if;
    if v_rate is null or v_rate <= 0 then
        return null;
    end if;
    return ceil(p_amount * 100 / v_rate);
end;
$$;

-- Stripe's bounds: 50 cents at least, an 8-digit unit_amount at most.
create or replace function stripe_usd_cents(p_amount numeric)
returns int
language sql
stable
set search_path = public
as $$
    select case when c between 50 and 99999999 then c::int end
      from (select stripe_usd_raw_cents(p_amount) as c) r;
$$;

-- ------------------------------------------------------------
-- 3. The checkout, in dollars
-- ------------------------------------------------------------
create or replace function stripe_begin(p_org_id uuid, p_period text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_terms jsonb := plan_terms();
    v_org   orgs%rowtype;
    v_amount numeric;
    v_cents  numeric;
begin
    if auth.uid() is null then
        raise exception 'stripe_begin() needs a signed-in caller';
    end if;
    if not stripe_on() then
        raise exception 'Le paiement par carte n''est pas encore ouvert';
    end if;
    if not is_org_admin(p_org_id) then
        raise exception 'Seul un administrateur abonne l''entreprise à Kaj Pro';
    end if;
    if p_period not in ('month', 'year') then
        raise exception 'Période inconnue : %', p_period;
    end if;
    select * into v_org from orgs where id = p_org_id;
    v_amount := (v_terms ->> case when p_period = 'year' then 'pro_price_year'
                                  else 'pro_price_month' end)::numeric;
    if coalesce(v_amount, 0) <= 0 then
        raise exception 'Le prix de Kaj Pro n''est pas fixé';
    end if;
    v_cents := stripe_usd_raw_cents(v_amount);
    if v_cents is null then
        raise exception 'Le taux de la carte (FCFA pour 1 $) n''est pas fixé';
    end if;
    if v_cents < 50 then
        raise exception 'Le prix en dollars est trop petit pour la carte (0,50 $ au moins)';
    end if;
    if v_cents > 99999999 then
        raise exception 'Le prix en dollars est trop grand pour la carte (999 999,99 $ au plus)';
    end if;
    return jsonb_build_object(
        'org_id',         v_org.id,
        'org_name',       v_org.name,
        'period',         p_period,
        'amount',         v_cents::int,
        'currency',       'usd',
        'price',          v_amount,
        'price_currency', upper(v_terms ->> 'pro_currency'),
        'customer_id',    (select customer_id from stripe_subscriptions where org_id = p_org_id),
        'email',          (select email from auth.users where id = auth.uid())
    );
end;
$$;

-- ------------------------------------------------------------
-- 4. The terms, with the dollars the card asks
-- ------------------------------------------------------------
create or replace function plan_terms()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'pro_features',            coalesce(plan_setting('pro_features'), '[]'::jsonb),
        'free_max_staff',          plan_limit('free_max_staff', 1),
        'free_max_invoices_month', plan_limit('free_max_invoices_month', 20),
        'free_max_photos',         plan_limit('free_max_photos', 50),
        'free_photo_items',        plan_limit('free_photo_items', 10),
        'free_history_months',     plan_limit('free_history_months', 12),
        'pro_price_month',         plan_limit('pro_price_month', 2500),
        'pro_price_year',          plan_limit('pro_price_year', 25000),
        'pro_currency',            coalesce(plan_setting('pro_currency') #>> '{}', 'XOF'),
        'platform_wave',           coalesce(plan_setting('platform_wave') #>> '{}', ''),
        'platform_wave_name',      coalesce(plan_setting('platform_wave_name') #>> '{}', ''),
        'delivery_share_pct',      plan_limit('delivery_share_pct', 10),
        'stripe_on',               stripe_on(),
        'stripe_usd_month',        stripe_usd_cents(plan_limit('pro_price_month', 2500)),
        'stripe_usd_year',         stripe_usd_cents(plan_limit('pro_price_year', 25000))
    )
    || coalesce((
        select jsonb_build_object('kinds', jsonb_object_agg(k.kind, k.vals))
          from (select s.kind, jsonb_object_agg(s.key, s.value) as vals
                  from kind_settings s
                 where s.key in (select c.key from kind_setting_catalog() c)
                 group by s.kind) k
        having count(*) > 0), '{}'::jsonb);
$$;

-- ------------------------------------------------------------
-- 5. Réglages (item 1): 105's platform_set_setting, the rate never zero
-- ------------------------------------------------------------
create or replace function platform_set_setting(p_key text, p_value jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_before jsonb;
    v_type   text;
    v_num    numeric;
begin
    perform platform_only();
    select value into v_before from platform_settings where key = p_key for update;
    if not found or platform_setting_internal(p_key) then
        raise exception 'Réglage inconnu : %', coalesce(p_key, '');
    end if;
    v_type := jsonb_typeof(v_before);
    -- A whole object is a page's, never a single setting.
    if v_type = 'object' then
        raise exception 'Réglage inconnu : %', p_key;
    end if;
    if p_value is null or jsonb_typeof(p_value) <> v_type then
        raise exception '%', case v_type
            when 'number'  then 'Ce réglage attend un nombre.'
            when 'boolean' then 'Ce réglage attend oui ou non.'
            when 'string'  then 'Ce réglage attend un texte.'
            when 'array'   then 'Ce réglage attend une liste.'
            else 'Ce réglage n''accepte pas cette valeur.' end;
    end if;
    if v_type = 'number' then
        v_num := (p_value #>> '{}')::numeric;
        if v_num < 0 then
            raise exception 'Un nombre positif, s''il vous plaît.';
        end if;
        if v_num > 1000000000 then
            raise exception 'Un nombre d''un milliard au plus.';
        end if;
        if p_key like '%\_pct' and v_num > 100 then
            raise exception 'Un pourcentage ne dépasse pas 100.';
        end if;
        -- A whole number, but for the five every reader takes as numeric
        -- (061/069/081/085's delivery fee and reach, 076's commission).
        -- Every other number is read as an integer (plan_limit,
        -- cauris_param, a ::int cast: « 12.5 » would break plan_terms(), the
        -- caps and the leagues), or is a count or a price in francs read
        -- through 071's spot_setting, where a decimal means nothing.
        if v_num <> trunc(v_num)
           and p_key not in ('delivery_base', 'delivery_per_km', 'delivery_max_km',
                             'delivery_included_km', 'wave_commission_pct') then
            raise exception 'Un nombre entier, s''il vous plaît.';
        end if;
        -- 121: the card's rate divides a price — never zero.
        if p_key = 'stripe_xof_per_usd' and v_num <= 0 then
            raise exception 'Un nombre entier plus grand que zéro, s''il vous plaît.';
        end if;
        -- Two switches kept as numbers (093, 097): read as « = 1 ».
        if p_key in ('vitrine_free_basics', 'path_gates_open') and v_num not in (0, 1) then
            raise exception 'Ce réglage vaut 0 (non) ou 1 (oui).';
        end if;
        -- Written the way an integer reader reads it: « 12 », never « 12.0 ».
        p_value := case when v_num = trunc(v_num) then to_jsonb(v_num::bigint) else to_jsonb(v_num) end;
    elsif v_type = 'string' then
        if length(p_value #>> '{}') > 200 then
            raise exception 'Un texte de 200 caractères au plus.';
        end if;
    elsif v_type = 'array' then
        if exists (select 1 from jsonb_array_elements(p_value) e
                    where jsonb_typeof(e) <> 'string') then
            raise exception 'Ce réglage attend une liste de mots.';
        end if;
    end if;
    if p_value = v_before then
        return null;  -- nothing changed, nothing to write in the journal
    end if;

    update platform_settings set value = p_value, updated_at = now() where key = p_key;
    return platform_log_action(
        null, 'setting',
        'Réglage ' || p_key || ' : ' || v_before::text || ' → ' || p_value::text,
        jsonb_build_object('key', p_key, 'value', v_before),
        jsonb_build_object('key', p_key, 'value', p_value),
        'platform_undo_setting',
        jsonb_build_object('key', p_key, 'before', v_before, 'after', p_value));
end;
$$;


-- The doors, said again as 082 and 105 left them: stripe_begin a signed-in
-- owner's, never the street's; plan_terms and platform_set_setting a
-- signed-in caller's (each checks who). The two new helpers are only
-- ever called inside them (security definer, as their owner): no one's else.
revoke execute on function stripe_usd_raw_cents(numeric)    from public;
revoke execute on function stripe_usd_cents(numeric)        from public;
revoke execute on function stripe_begin(uuid, text)         from public;
revoke execute on function plan_terms()                     from public;
revoke execute on function platform_set_setting(text, jsonb) from public;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function stripe_usd_raw_cents(numeric)     from anon;
        revoke execute on function stripe_usd_cents(numeric)         from anon;
        revoke execute on function stripe_begin(uuid, text)          from anon;
        revoke execute on function platform_set_setting(text, jsonb) from anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function stripe_usd_raw_cents(numeric)     from authenticated;
        revoke execute on function stripe_usd_cents(numeric)         from authenticated;
        grant execute on function stripe_begin(uuid, text)           to authenticated;
        grant execute on function plan_terms()                       to authenticated;
        grant execute on function platform_set_setting(text, jsonb)  to authenticated;
    end if;
end $$;

notify pgrst, 'reload schema';
