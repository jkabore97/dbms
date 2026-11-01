-- ============================================================
-- 160 — Three classic cards after the owner's pictures.
--
-- Cimbrone (the couple's photo filling the hero, the names over it, a
-- black band with the weekend), Bouquet (a soft flowered page: four small
-- promises, three photo cards for the day's moments, a blush band, an
-- olive foot) and Rivage (deep sage around a cream page, a framed photo,
-- a veil of green for the couple's word, the day as drawn icons, stripes
-- beside the answer). Their pages are under /cartes like the twelve; here
-- they become designs a card may take (events.card references
-- event_templates). Free, for a wedding. For a shop, a farm or an
-- association: nothing — the cards are an Événementiel's. Applies twice.
-- ============================================================

do $$ begin
    if to_regclass('event_templates') is null then
        raise exception '160 needs 153 (event_templates) applied first';
    end if;
end $$;

insert into event_templates (key, family, name, premium, sort, kinds, line) values
    ('cimbrone', 'classique', 'Cimbrone', false, 48, array['mariage'], 'Une photo plein cadre, le noir et blanc'),
    ('bouquet', 'classique', 'Bouquet', false, 49, array['mariage'], 'Des fleurs, une longue table, l’olive'),
    ('rivage', 'classique', 'Rivage', false, 50, array['mariage'], 'Vert sauge, un lac, les heures en dessins')
on conflict (key) do update
    set family = excluded.family, name = excluded.name, premium = excluded.premium,
        sort = excluded.sort, kinds = excluded.kinds, line = excluded.line;

notify pgrst, 'reload schema';
