-- ============================================================
-- p1_110_after.sql — the second half of promise P1 for 110.
--
-- Run on the database p1_110_before.sql photographed before 110, once 110
-- and every later migration are applied. The same photograph, taken again
-- by the same function, must be the same answer for answer: the whole
-- street (every vitrine of every kind, the search, À la une, the
-- spotlights, the previews, the delivery quote and check, the photo gate),
-- what each owner reads (feature_states — its 'hidden' empty —, wave_terms,
-- spot_terms, the spots), and what every door did: an order picked up,
-- delivered, paid by Wave, a booking at a shop, a farm, an association and
-- a church, a spot asked for and paid, a vitrine dressed on Pro and on
-- Basic, the delivery numbers and the Wave payout changed, a service
-- created. And with no rule written, none of the vitrine's switches hides
-- anything for any business. Two answers change on purpose, set aside
-- below: since 141 the Basic dressing keeps the layout it was sent; since
-- 144 À la une and the spotlights show a spot only around its business.
-- ============================================================
\set ON_ERROR_STOP on

do $$
declare
    n       int;
    v_diff  text;
    v_count int;
begin
    n := p110_take('after');
    -- 136 (batch 141): the shelf grew photo_keys and duration_minutes. An
    -- item with no second photo (photo_keys null or its one photo) and no
    -- duration must read exactly as before: those two keys are set aside
    -- there, and only there — a photo or a duration more is a change.
    update p110_snap s
       set v = (select coalesce(jsonb_agg(e order by e::text), '[]'::jsonb)
                  from (select x
                               - case when coalesce(x -> 'photo_keys', 'null'::jsonb) = 'null'::jsonb
                                        or x -> 'photo_keys' = jsonb_build_array(x -> 'photo_key')
                                      then 'photo_keys' else '' end
                               - case when coalesce(x -> 'duration_minutes', 'null'::jsonb) = 'null'::jsonb
                                      then 'duration_minutes' else '' end as e
                          from jsonb_array_elements(s.v) x) z)
     where s.phase = 'after'
       and (s.what like 'storefront_products %' or s.what like 'own products %')
       and jsonb_typeof(s.v) = 'array';
    -- 141 (batch 146): a Basic business keeps the Pro choices it saves.
    -- « dress basic » sent « layout: menu »; before 141 that was dropped
    -- and the row's old layout (« list », from its Pro days) carried over;
    -- since 141 the « menu » sent is what the row keeps (the street still
    -- strips it: the vitrines' own answers are compared untouched). In
    -- that answer only, and only when it is exactly what was sent, the
    -- layout is read as before.
    update p110_snap s
       set v = (s.v - 'layout')
               || coalesce((select jsonb_build_object('layout', b.v -> 'layout')
                              from p110_snap b
                             where b.phase = 'before' and b.what = 'dress basic'
                               and b.v ? 'layout'), '{}'::jsonb)
     where s.phase = 'after'
       and s.what = 'dress basic'
       and s.v ->> 'layout' = 'menu';
    -- 144 (batch 148): a spot is shown only around its business. The
    -- photograph asks À la une and the spotlights from nowhere — since 144
    -- that shows no spot at all, on purpose (Mara's own pick stays). Asked
    -- from where the vitrines are (Gounghin, the photograph's « near »
    -- point), the street must show exactly the spots it showed before.
    if to_regprocedure('storefront_featured(double precision, double precision)') is not null then
        if exists (select 1 from storefront_spotlights())
           or (select count(*) from storefront_featured()) <> 1 then
            raise exception 'FAIL: asked from nowhere, the street still shows a spot (144)';
        end if;
        update p110_snap
           set v = (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]')
                      from storefront_featured(12.36, -1.53) x)
         where phase = 'after' and what = 'featured';
        update p110_snap
           set v = (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]')
                      from storefront_spotlights(12.36, -1.53) x)
         where phase = 'after' and what = 'spotlights';
    end if;
    select string_agg(coalesce(b.what, a.what), '; ' order by coalesce(b.what, a.what)), count(*)
      into v_diff, v_count
      from (select * from p110_snap where phase = 'before') b
      full join (select * from p110_snap where phase = 'after') a on a.what = b.what
     where a.v is distinct from b.v;
    if v_diff is not null then
        raise exception 'FAIL: % answers changed with 110 and after: %', v_count, v_diff;
    end if;
    raise notice 'PASS: P1 — % answers identical before and after 110 (every vitrine of every kind, the street, what each owner reads, and every order, booking, spot, dressing, delivery and Wave door)', n;
end $$;

do $$
declare
    v_keys text[] := array['online_orders', 'services', 'delivery', 'online_payment',
                           'vitrine_plus', 'spots', 'for_sale'];
begin
    if (select count(*) from feature_catalog where key = any (v_keys)) <> 7 then
        raise exception 'FAIL: the vitrine''s switches are not all in the catalog';
    end if;
    if exists (select 1 from orgs o cross join feature_catalog c where feature_hidden(o.id, c.key)) then
        raise exception 'FAIL: a catalog feature is hidden with no rule';
    end if;
    if exists (select 1 from feature_rules) then
        raise exception 'FAIL: installing wrote a switch';
    end if;
    raise notice 'PASS: P1 — every vitrine switch starts at « Par défaut »: % businesses × % catalog features, none hidden',
        (select count(*) from orgs), (select count(*) from feature_catalog);
end $$;

\echo '=== p1_110_after.sql: P1 holds ==='
