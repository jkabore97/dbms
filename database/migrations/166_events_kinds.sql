-- ============================================================
-- 166 — Concerts, festivals, conferences (batch 166).
--
-- The owner: « Il n'y a ni concert ni événement culturel ?? » — a business
-- that sells tickets (161) has a stage or a hall, not only a family's
-- day. Three kinds join the ten of 152: concert (« Concert, spectacle »),
-- culture (« Festival, événement culturel »), conference (« Conférence,
-- séminaire »). The classic « Dix ans » (a soirée) is drawn for them too;
-- the animated designs already had their words.
--
-- For a shop, a farm or an association: nothing — the kinds are an
-- event's. Applies twice.
-- ============================================================

do $$ begin
    alter table events drop constraint if exists events_kind_check;
    alter table events add constraint events_kind_check
        check (kind in ('mariage', 'dot', 'anniversaire', 'bapteme', 'naissance', 'diplome', 'gala',
                        'inauguration', 'retraite', 'hommage', 'concert', 'culture', 'conference'));
end $$;

update event_templates
   set kinds = array(select distinct unnest(kinds || array['concert', 'culture', 'conference']) order by 1)
 where key = 'gala' and not kinds @> array['concert', 'culture', 'conference'];

notify pgrst, 'reload schema';
