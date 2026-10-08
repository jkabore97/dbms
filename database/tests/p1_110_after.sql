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
-- anything for any business.
-- ============================================================
\set ON_ERROR_STOP on

do $$
declare
    n       int;
    v_diff  text;
    v_count int;
begin
    n := p110_take('after');
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
