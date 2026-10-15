-- ============================================================
-- test_marakaj_name.sql — 147: the product is called Marakaj.
--
-- The claims:
--   1. installed twice, the same: every function 147 re-creates keeps its
--      SECURITY DEFINER (or not), its search_path, its owner and its
--      grants, every definer among them pinned — 147 changes words only;
--   2. no function of the schema says « Mara » in its own quoted text any
--      more (a refusal, a bell, a journal line, a label), comments aside;
--   3. the words, as a shop, a farm or an association reads them: the
--      second business's lock, « Marakaj Pro complet », Le Chemin's line;
--   4. the two seeded lines are changed only while they are the seed: a
--      line the platform rewrote is left as written.
-- Wrapped in one transaction rolled back, so it runs twice the same.
-- ============================================================
\set ON_ERROR_STOP on

-- The other suites re-apply their own migrations (with the old words):
-- 147 again, as it is applied live, after them.
\i database/migrations/147_marakaj_name.sql

begin;

-- The two lines as 097 and 142 seeded them (an earlier suite may have
-- bumped the terms since): 147 must change them.
update path_steps set line = 'Vos cauris ouvrent les outils de Mara Pro.' where key = 'first_unlock';
update platform_settings
   set value = value || jsonb_build_object(
       'changes', 'Nouvelles conditions : Mara est une plateforme, chaque entreprise vend elle-même ; les règles contre la fraude ; les engagements du vendeur et du livreur.',
       'changes_en', 'New terms: Mara is a platform, each business sells for itself; the rules against fraud; the seller''s and the courier''s commitments.')
 where key = 'terms_versions';

create temp table before_147 on commit drop as
select p.oid, p.prosecdef, p.proconfig, p.proowner, p.proacl::text as acl
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.prosrc like '%Marakaj%';

\i database/migrations/147_marakaj_name.sql
\i database/migrations/147_marakaj_name.sql

do $$
declare
    v_n int;
    v_changed int;
    v_unpinned int;
    v_left text;
begin
    -- 1. The same functions, the same rights.
    select count(*) into v_n from before_147;
    if v_n < 52 then
        raise exception 'FAIL: 147 re-creates 52 functions, % say Marakaj', v_n;
    end if;
    select count(*) into v_changed
      from before_147 b join pg_proc p on p.oid = b.oid
     where p.prosecdef is distinct from b.prosecdef
        or p.proconfig is distinct from b.proconfig
        or p.proowner is distinct from b.proowner
        or p.proacl::text is distinct from b.acl;
    if v_changed > 0 then
        raise exception 'FAIL: % function(s) changed security, path, owner or grants', v_changed;
    end if;
    select count(*) into v_unpinned
      from before_147 b join pg_proc p on p.oid = b.oid
     where p.prosecdef
       and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%');
    if v_unpinned > 0 then
        raise exception 'FAIL: % definer(s) of 147 without a pinned search_path', v_unpinned;
    end if;
    if not (select prosecdef from pg_proc where oid = 'trg_orders_terms()'::regprocedure)
       or (select prosecdef from pg_proc where oid = 'cauris_feature_label(text)'::regprocedure) then
        raise exception 'FAIL: a definer or an invoker changed sides';
    end if;
    raise notice 'PASS: % functions, each its security, path, owner and grants as before', v_n;

    -- 2. No quoted « Mara » left (line and block comments set aside).
    select string_agg(p.oid::regprocedure::text, ', ') into v_left
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g')
           ~ '''[^'']*\mMara\M[^'']*''';
    if v_left is not null then
        raise exception 'FAIL: still saying « Mara »: %', v_left;
    end if;
    raise notice 'PASS: no function says « Mara » in its own words';

    -- 3. The words (the same for a shop, a farm and an association).
    if path_lock_message('second_business') <> 'Une deuxième entreprise : avec Marakaj Pro.'
       or cauris_feature_label('pro_all') <> 'Marakaj Pro complet' then
        raise exception 'FAIL: the lock and the label read « % » and « % »',
            path_lock_message('second_business'), cauris_feature_label('pro_all');
    end if;
    if (select line from path_steps where key = 'first_unlock')
       <> 'Vos cauris ouvrent les outils de Marakaj Pro.' then
        raise exception 'FAIL: Le Chemin''s line is « % »', (select line from path_steps where key = 'first_unlock');
    end if;
    if (select value ->> 'changes' from platform_settings where key = 'terms_versions') !~ '^Nouvelles conditions : Marakaj est'
       or (select value ->> 'changes_en' from platform_settings where key = 'terms_versions') !~ '^New terms: Marakaj is' then
        raise exception 'FAIL: the terms'' « what changed » still says the old name';
    end if;
    raise notice 'PASS: « avec Marakaj Pro », « Marakaj Pro complet », Le Chemin and the terms say the new name';
end $$;

-- 4. A line the platform rewrote is its own: 147 again leaves it.
update path_steps set line = 'Avec vos cauris, ouvrez un outil.' where key = 'first_unlock';
update platform_settings set value = jsonb_set(value, '{changes}', '"Un texte écrit par la plateforme."')
 where key = 'terms_versions';
\i database/migrations/147_marakaj_name.sql
do $$ begin
    if (select line from path_steps where key = 'first_unlock') <> 'Avec vos cauris, ouvrez un outil.'
       or (select value ->> 'changes' from platform_settings where key = 'terms_versions') <> 'Un texte écrit par la plateforme.' then
        raise exception 'FAIL: 147 rewrote a line the platform had changed';
    end if;
    raise notice 'PASS: a line the platform rewrote is left as written';
end $$;

rollback;
