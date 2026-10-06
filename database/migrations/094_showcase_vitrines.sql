-- ============================================================
-- 094_showcase_vitrines.sql — vitrines d'exemple on the street.
--
-- The owner: « Now we need to motivate users with store. Create fictive
-- stores in vitrine that I can manage from admin panel. » Seven businesses
-- the platform runs itself, each with 10 to 15 articles and their photos,
-- so a shopper sees what a full vitrine looks like and a shopkeeper sees
-- what theirs could become.
--
-- The rules:
--   * orgs.showcase marks them. They are Mara Pro (so they show the full
--     dressing of 093) and have no pin: they are never on the map, and the
--     page says « Pas à proximité ».
--   * Nobody can order from them: a BEFORE INSERT trigger on orders refuses
--     with the « Pas à proximité » sentence, whatever the path.
--   * They earn no cauris and so never stand in a league (086).
--   * The platform admins manage them as their owners, with the ordinary
--     business screens (articles, photos, prices, Habiller ma vitrine).
--     showcase_list() and showcase_join() serve the console's page;
--     set_showcase_visible() takes one off the street and puts it back.
--   * showcase_seed() creates the stores that do not exist yet — run once
--     here for the first platform admin, and again from the console after
--     one is deleted. It never touches a store that exists, so what the
--     admin edited stays edited.
--   * The photographs ship with the web app under /showcase/… (keys
--     « showcase/<store>/<file>.jpg »): the app reads them from the site, not
--     from the uploads Worker. A photo the admin takes later is an ordinary
--     upload and replaces it (the newest photo wins, 052).
--
-- No destructive statement.
-- ============================================================

alter table orgs add column if not exists showcase boolean not null default false;

comment on column orgs.showcase is
    'A vitrine d''exemple run by the platform (094): Pro, off the map, takes '
    'no orders, earns no cauris.';

-- The seven, and what they sell.
create or replace function showcase_seed()
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_owner   uuid;
    v_store   record;
    v_org     uuid;
    v_made    int := 0;
    v_item    record;
    v_product uuid;
    v_cover   text;
begin
    if auth.uid() is not null then
        if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
            raise exception 'Réservé à l''administration de la plateforme';
        end if;
        v_owner := auth.uid();
    else
        select id into v_owner from profiles where is_platform_admin
         order by created_at limit 1;
    end if;
    if v_owner is null then
        return 0;
    end if;

    for v_store in
        select * from (values
            ('rowan-bike-shop', 'Rowan Bike Shop',
             'Vélos de route, gravel et BMX, révisés et prêts à rouler.',
             'Le vélo qu''il vous faut', '#1F5FA8', 'grid', 'route-carbone-rouge',
             '[1,2,3,4,5,6]', '09:00', '19:00'),
            ('tony-pizza', 'Tony Pizza',
             'Pizzas, burgers et fritures, du midi à minuit.',
             'La pizza du quartier', '#B1541A', 'large', 'pizza-pepperoni',
             '[1,2,3,4,5,6,7]', '11:00', '23:30'),
            ('chinese-fu-restaurant', 'Chinese Fu Restaurant',
             'Cuisine chinoise maison : soupes, sautés, vapeur et plaques chauffantes.',
             'Le goût de Canton', '#8E3B6B', 'list', 'plaque-chauffante-fruits-de-mer',
             '[2,3,4,5,6,7]', '11:30', '22:30'),
            ('jersey-bakery', 'Jersey Bakery',
             'Pâtisserie, viennoiserie et boissons chaudes, chaque matin.',
             'Tout juste sorti du four', '#B8860B', 'grid', 'brownies',
             '[1,2,3,4,5,6,7]', '06:30', '20:00'),
            ('bob-electronics', 'Bob Electronics',
             'Téléphones, accessoires et solaire, avec garantie.',
             'Branché sur votre quotidien', '#444444', 'list', null,
             '[1,2,3,4,5,6]', '08:30', '19:30'),
            ('ghana-restaurant', 'Ghana Restaurant',
             'Les plats d''Accra : jollof, waakye, banku, fufu et suya.',
             'Akwaaba !', '#2E7D5B', 'menu', 'brochettes',
             '[1,2,3,4,5,6,7]', '10:00', '22:00'),
            ('thomas-university-restaurant', 'Thomas University Restaurant',
             'Le restaurant du campus : plats chauds, salades et sandwichs à petit prix.',
             'Bien manger entre deux cours', '#2E7D5B', 'grid', 'combo-2-personnes',
             '[1,2,3,4,5]', '07:00', '21:00')
        ) s(slug, name, blurb, tagline, accent, layout, cover, days, open_at, close_at)
    loop
        if exists (select 1 from orgs where slug = v_store.slug) then
            continue;
        end if;
        insert into orgs (name, slug, profile, default_currency, showcase,
                          plan, plan_until, plan_note, storefront_enabled,
                          storefront_blurb, setup_done_at, progress_since)
        values (v_store.name, v_store.slug, 'retail', 'XOF', true,
                'pro', null, 'Vitrine d''exemple (094)', true,
                v_store.blurb, now(), null)
        returning id into v_org;
        insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
        values (v_org, v_owner, 'owner', 'org', v_org, 'full');
        perform seed_retail_accounts(v_org);

        v_cover := null;
        for v_item in
            select * from (values
                -- Rowan Bike Shop
                ('rowan-bike-shop', 'gravel-carbone-gris', 'Vélo gravel carbone gris', 1250000, 3, 'Cadre carbone, freins à disque, pneus de 40 mm.'),
                ('rowan-bike-shop', 'gravel-arc-en-ciel', 'Vélo gravel « Arc-en-ciel »', 980000, 2, 'Cadre aluminium dégradé, transmission 1×11.'),
                ('rowan-bike-shop', 'route-carbone-rouge', 'Vélo de route carbone rouge', 2400000, 1, 'Cadre aéro, groupe électronique, roues carbone.'),
                ('rowan-bike-shop', 'triathlon-noir', 'Vélo de triathlon', 2900000, 1, 'Position contre-la-montre, prolongateurs intégrés.'),
                ('rowan-bike-shop', 'fixie-noir-celeste', 'Fixie noir et céleste', 350000, 4, 'Pignon fixe, guidon piste, idéal en ville.'),
                ('rowan-bike-shop', 'randonneuse-rouge', 'Randonneuse acier rouge', 650000, 2, 'Porte-bagages avant et arrière, garde-boue.'),
                ('rowan-bike-shop', 'route-alu-argent', 'Vélo de route aluminium', 550000, 3, 'Cadre léger, 2×11 vitesses, freins à disque.'),
                ('rowan-bike-shop', 'route-carbone-noir', 'Vélo de route carbone noir', 1450000, 2, 'Cadre carbone, groupe 2×12.'),
                ('rowan-bike-shop', 'route-acier-classique', 'Vélo de route acier classique', 420000, 2, 'Cadre acier chromé, allure rétro.'),
                ('rowan-bike-shop', 'bmx-race-noir', 'BMX course 20 pouces noir', 260000, 3, 'Cadre aluminium, pédalier 3 pièces.'),
                ('rowan-bike-shop', 'bmx-race-bleu', 'BMX junior bleu', 180000, 4, 'Pour les 8 à 12 ans.'),
                ('rowan-bike-shop', 'bmx-race-rouge', 'BMX rouge', 150000, 5, 'Acier robuste, freins V-brake.'),
                ('rowan-bike-shop', 'bmx-dirt-jaune', 'BMX enfant jaune', 120000, 5, 'Roues de 16 pouces, pour débuter.'),
                ('rowan-bike-shop', 'bmx-street-rouge', 'BMX street rouge', 210000, 3, 'Pegs et rotor, pour les figures.'),
                ('rowan-bike-shop', 'bmx-freestyle-jaune', 'BMX freestyle jaune', 230000, 3, 'Cadre chromoly, frein U.'),
                -- Tony Pizza
                ('tony-pizza', 'pizza-pepperoni', 'Pizza pepperoni', 6500, 30, 'Sauce tomate, mozzarella, pepperoni.'),
                ('tony-pizza', 'pizza-fruits-de-mer', 'Pizza fruits de mer', 8500, 20, 'Crevettes, calamars, citron vert.'),
                ('tony-pizza', 'pizza-poulet-alfredo', 'Pizza poulet Alfredo', 7500, 25, 'Crème, poulet, champignons.'),
                ('tony-pizza', 'pizza-vegetarienne', 'Pizza végétarienne', 6000, 25, 'Poivrons, oignons, olives, champignons.'),
                ('tony-pizza', 'cheezy-pizza-burger', 'Burger « Cheezy pizza »', 5500, 20, 'Steak, pepperoni, fromage fondu, frites.'),
                ('tony-pizza', 'mac-and-cheese-burger', 'Burger mac and cheese', 5500, 20, 'Pain brioché, macaronis au fromage.'),
                ('tony-pizza', 'ribs-bbq-burger', 'Burger ribs BBQ', 6000, 20, 'Effiloché de porc, sauce barbecue.'),
                ('tony-pizza', 'ailes-de-poulet', 'Ailes de poulet (8)', 4500, 30, 'Croustillantes, sauce piquante à part.'),
                ('tony-pizza', 'nachos', 'Nachos garnis', 4000, 20, 'Fromage, jalapeños, sauce salsa.'),
                ('tony-pizza', 'poutine', 'Poutine', 3500, 20, 'Frites, fromage, sauce brune.'),
                ('tony-pizza', 'tenders', 'Tenders de poulet', 4000, 25, 'Filets panés, sauce au choix.'),
                ('tony-pizza', 'nuggets', 'Nuggets (10)', 3500, 30, 'Pour les petits et les grands.'),
                ('tony-pizza', 'quesadillas', 'Quesadillas', 4500, 20, 'Tortilla grillée, poulet, fromage.'),
                ('tony-pizza', 'limonades', 'Limonade maison', 1500, 40, 'Citron, menthe ou fruits rouges.'),
                -- Chinese Fu Restaurant
                ('chinese-fu-restaurant', 'soupe-saint-jacques-oeuf', 'Soupe aux Saint-Jacques et à l''œuf', 3500, 20, 'Saint-Jacques séchées, œuf battu.'),
                ('chinese-fu-restaurant', 'aubergines-ail-pimente', 'Aubergines sauce ail pimentée', 4000, 20, 'Aubergines fondantes, porc haché.'),
                ('chinese-fu-restaurant', 'liseron-saute-porc', 'Liseron d''eau sauté au porc', 4500, 20, 'Ong choy croquant, ail.'),
                ('chinese-fu-restaurant', 'filet-poisson-vapeur-gingembre', 'Poisson vapeur, gingembre et oignon vert', 7000, 15, 'Filet blanc, sauce soja légère.'),
                ('chinese-fu-restaurant', 'plaque-chauffante-fruits-de-mer', 'Plaque chauffante aux fruits de mer', 9500, 10, 'Servie grésillante, légumes croquants.'),
                ('chinese-fu-restaurant', 'chou-aigre-doux-porc', 'Chou aigre-doux au porc', 4500, 20, 'Chou mariné, porc émincé.'),
                ('chinese-fu-restaurant', 'tofu-frit-legumes', 'Tofu frit aux légumes', 4000, 20, 'Tofu doré, brocoli chinois.'),
                ('chinese-fu-restaurant', 'tofu-farci-frit', 'Tofu farci frit', 4500, 15, 'Farce de porc et crevette, sauce brune.'),
                ('chinese-fu-restaurant', 'nems', 'Nems (6)', 3000, 30, 'Porc et légumes, sauce nuoc-mâm.'),
                ('chinese-fu-restaurant', 'potsticker', 'Raviolis grillés (6)', 3000, 30, 'Poêlés d''un côté, vapeur de l''autre.'),
                ('chinese-fu-restaurant', 'riz-cantonais', 'Riz cantonais', 3500, 30, 'Œuf, petits pois, jambon.'),
                ('chinese-fu-restaurant', 'salade-boeuf-thai', 'Salade de bœuf thaï', 4500, 15, 'Bœuf saisi, herbes, citron vert.'),
                -- Jersey Bakery
                ('jersey-bakery', 'brownies', 'Brownies au chocolat', 1500, 40, 'Fondants, aux noix.'),
                ('jersey-bakery', 'profiterole', 'Profiteroles', 3000, 20, 'Choux, glace vanille, chocolat chaud.'),
                ('jersey-bakery', 'crepe-nutella', 'Crêpe au Nutella', 2500, 30, 'Pâte à tartiner, banane en option.'),
                ('jersey-bakery', 'pain-perdu-tropical', 'Pain perdu tropical', 3500, 15, 'Brioche dorée, banane, caramel.'),
                ('jersey-bakery', 'fettucine-trois-chocolats', 'Fettucine trois chocolats', 3500, 15, 'Le dessert de la maison.'),
                ('jersey-bakery', 'affogato', 'Affogato', 2500, 20, 'Glace vanille, espresso chaud.'),
                ('jersey-bakery', 'lattes', 'Latte', 2000, 40, 'Nature, caramel ou vanille.'),
                ('jersey-bakery', 'smoothies', 'Smoothie mangue', 2500, 25, 'Mangue, banane, lait.'),
                ('jersey-bakery', 'bubble-teas', 'Bubble tea', 2500, 25, 'Perles de tapioca, trois parfums.'),
                ('jersey-bakery', 'salade-de-fruits', 'Salade de fruits frais', 2000, 20, 'Les fruits du jour.'),
                ('jersey-bakery', 'buche-caramel', 'Bûche caramel', 15000, 5, 'Pour 8 personnes, sur commande la veille.'),
                ('jersey-bakery', 'buche-rouge', 'Bûche fruits rouges', 15000, 5, 'Pour 8 personnes, sur commande la veille.'),
                ('jersey-bakery', 'crepe-jambon-fromage', 'Crêpe jambon-fromage', 3000, 20, 'Le salé du matin.'),
                ('jersey-bakery', 'oeuf-benedicte', 'Œufs Bénédicte', 4000, 15, 'Muffin, œuf poché, sauce hollandaise.'),
                -- Thomas University Restaurant
                ('thomas-university-restaurant', 'sandwich-roti-de-boeuf', 'Sandwich rôti de bœuf', 3000, 40, 'Baguette, bœuf, crudités.'),
                ('thomas-university-restaurant', 'sandwich-saumon', 'Sandwich saumon', 3500, 30, 'Saumon fumé, fromage frais.'),
                ('thomas-university-restaurant', 'salade-tortellini', 'Salade de tortellini', 3000, 25, 'Tortellini, olives, tomates.'),
                ('thomas-university-restaurant', 'feta-quinoa-betterave', 'Salade quinoa, feta et betterave', 3000, 25, 'Avocat, pois chiches.'),
                ('thomas-university-restaurant', 'stylish-bolognaise', 'Spaghetti bolognaise', 2500, 40, 'Sauce maison au bœuf.'),
                ('thomas-university-restaurant', 'poulet-milanais', 'Poulet milanais et pâtes', 3500, 30, 'Escalope panée, crème.'),
                ('thomas-university-restaurant', 'patate-douce-poulet-bbq', 'Patate douce et poulet BBQ', 3500, 25, 'Gratinée au fromage.'),
                ('thomas-university-restaurant', 'assiette-chawarma-poulet', 'Assiette chawarma poulet', 3500, 30, 'Frites, salade, sauce à l''ail.'),
                ('thomas-university-restaurant', 'chawarma-poulet', 'Chawarma poulet', 2000, 50, 'Le roulé du campus.'),
                ('thomas-university-restaurant', 'poulet-broasted', 'Poulet broasted', 3000, 30, 'Croustillant, avec pain.'),
                ('thomas-university-restaurant', 'ravioli-betterave', 'Raviolis à la betterave', 3500, 20, 'Sauce crème et parmesan.'),
                ('thomas-university-restaurant', 'sap-sap-salade', 'Salade sap-sap', 2500, 25, 'Pâtes, légumes croquants, œuf.'),
                ('thomas-university-restaurant', 'combo-2-personnes', 'Combo 2 personnes', 7000, 20, 'Poulet, croquettes, frites et sauces.'),
                ('thomas-university-restaurant', 'omelette-au-four', 'Omelette au four', 2000, 30, 'Le petit-déjeuner des révisions.'),
                ('thomas-university-restaurant', 'tortellini-fruits-de-mer', 'Tortellini aux fruits de mer', 4000, 20, 'Crevettes, sauce citronnée.'),
                -- Ghana Restaurant
                ('ghana-restaurant', 'brochettes', 'Suya (brochettes de bœuf épicées)', 2500, 40, 'Piment de suya, oignon, tomate.'),
                ('ghana-restaurant', null, 'Riz jollof au poulet', 3500, 40, 'Riz à la tomate, poulet grillé.'),
                ('ghana-restaurant', null, 'Waakye', 3000, 30, 'Riz et haricots, spaghetti, œuf, shito.'),
                ('ghana-restaurant', null, 'Banku et tilapia grillé', 5000, 20, 'Pâte de maïs fermentée, piment frais.'),
                ('ghana-restaurant', null, 'Fufu, soupe légère au poisson', 4000, 20, 'Igname et plantain pilés.'),
                ('ghana-restaurant', null, 'Kenkey et poisson frit', 3500, 20, 'Avec piment et oignon.'),
                ('ghana-restaurant', null, 'Kelewele', 1500, 40, 'Plantain frit épicé, gingembre.'),
                ('ghana-restaurant', null, 'Red red', 2500, 30, 'Haricots à l''huile rouge, plantain.'),
                ('ghana-restaurant', null, 'Soupe d''arachide au poulet', 4000, 20, 'Avec riz en boule (omo tuo).'),
                ('ghana-restaurant', null, 'Igname frite et shito', 2000, 30, 'Le goûter de la rue.'),
                ('ghana-restaurant', null, 'Sobolo', 1000, 50, 'Jus d''hibiscus au gingembre.'),
                ('ghana-restaurant', null, 'Shito maison (pot)', 2000, 20, 'Sauce pimentée au poisson séché.'),
                -- Bob Electronics
                ('bob-electronics', null, 'Smartphone Android 6,5 pouces', 95000, 10, '128 Go, double SIM.'),
                ('bob-electronics', null, 'Écouteurs Bluetooth', 12000, 25, 'Boîtier de charge, 20 h d''écoute.'),
                ('bob-electronics', null, 'Chargeur rapide 25 W', 6000, 40, 'Prise USB-C.'),
                ('bob-electronics', null, 'Batterie externe 20 000 mAh', 15000, 20, 'Deux ports, charge rapide.'),
                ('bob-electronics', null, 'Kit solaire 50 W', 85000, 5, 'Panneau, batterie, trois ampoules.'),
                ('bob-electronics', null, 'Ampoule LED rechargeable', 3500, 50, 'Six heures de lumière.'),
                ('bob-electronics', null, 'Téléviseur LED 32 pouces', 120000, 4, 'HD, deux ports HDMI.'),
                ('bob-electronics', null, 'Radio FM solaire', 9000, 15, 'Lampe torche intégrée.'),
                ('bob-electronics', null, 'Ventilateur rechargeable', 25000, 10, 'Batterie de huit heures.'),
                ('bob-electronics', null, 'Câble USB-C 1 m', 2000, 60, 'Tressé, charge rapide.'),
                ('bob-electronics', null, 'Clé USB 64 Go', 6500, 30, 'USB 3.0.'),
                ('bob-electronics', null, 'Montre connectée', 18000, 12, 'Pas, sommeil, notifications.'),
                ('bob-electronics', null, 'Enceinte Bluetooth', 20000, 12, 'Étanche, dix heures.')
            ) i(slug, photo, name, price, qty, description)
            where i.slug = v_store.slug
        loop
            insert into products (org_id, name, sale_price, quantity, is_active,
                                  is_published, description, created_by)
            values (v_org, v_item.name, v_item.price, v_item.qty, true,
                    true, v_item.description, v_owner)
            returning id into v_product;
            if v_item.photo is not null then
                insert into documents (org_id, r2_key, kind, product_id, uploaded_by)
                values (v_org, 'showcase/' || v_store.slug || '/' || v_item.photo || '.jpg',
                        'product_photo', v_product, v_owner);
            end if;
        end loop;

        if v_store.cover is not null then
            v_cover := 'showcase/' || v_store.slug || '/' || v_store.cover || '.jpg';
        end if;
        update orgs set storefront_style = jsonb_strip_nulls(jsonb_build_object(
                'tagline', v_store.tagline,
                'accent', v_store.accent,
                'layout', case when v_store.layout = 'grid' then null else v_store.layout end,
                'cover_key', v_cover,
                'schedule', jsonb_build_object('days', v_store.days::jsonb,
                                               'open', v_store.open_at,
                                               'close', v_store.close_at)))
         where id = v_org;
        v_made := v_made + 1;
    end loop;
    return v_made;
end;
$$;

-- The console's page: every vitrine d'exemple, how full it is, whether it
-- is on the street, and whether the caller already manages it.
create or replace function showcase_list()
returns table (
    org_id    uuid,
    name      text,
    slug      text,
    blurb     text,
    items     integer,
    photos    integer,
    visible   boolean,
    managing  boolean
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Réservé à l''administration de la plateforme';
    end if;
    return query
    select o.id, o.name, o.slug, o.storefront_blurb,
           (select count(*)::int from products p
             where p.org_id = o.id and p.is_active and p.is_published),
           (select count(distinct d.product_id)::int from documents d
              join products p on p.id = d.product_id
             where p.org_id = o.id and p.is_active and p.is_published),
           o.storefront_enabled and o.archived_at is null,
           exists (select 1 from memberships m
                    where m.org_id = o.id and m.user_id = auth.uid())
    from orgs o
    where o.showcase
    order by o.name;
end;
$$;

-- A platform admin takes the keys of one: owner, so every business screen
-- opens for them.
create or replace function showcase_join(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Réservé à l''administration de la plateforme';
    end if;
    if not exists (select 1 from orgs where id = p_org_id and showcase) then
        raise exception 'Ce n''est pas une vitrine d''exemple';
    end if;
    if not exists (select 1 from memberships
                    where org_id = p_org_id and user_id = auth.uid()) then
        insert into memberships (org_id, user_id, role, scope_kind, scope_id, visibility)
        values (p_org_id, auth.uid(), 'owner', 'org', p_org_id, 'full');
    end if;
end;
$$;

create or replace function set_showcase_visible(p_org_id uuid, p_visible boolean)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if not exists (select 1 from profiles where id = auth.uid() and is_platform_admin) then
        raise exception 'Réservé à l''administration de la plateforme';
    end if;
    update orgs set storefront_enabled = coalesce(p_visible, false)
     where id = p_org_id and showcase;
    if not found then
        raise exception 'Ce n''est pas une vitrine d''exemple';
    end if;
end;
$$;

-- What the street needs to say « Pas à proximité »: the open ones' slugs.
create or replace function showcase_slugs()
returns setof text
language sql
stable
security definer
set search_path = public
as $$
    select o.slug from orgs o
     where o.showcase and o.storefront_enabled
       and o.archived_at is null and o.suspended_at is null;
$$;

-- Nobody orders from a vitrine d'exemple, whatever the path.
create or replace function trg_order_showcase()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if exists (select 1 from orgs where id = new.org_id and showcase) then
        raise exception 'Pas à proximité : cette boutique ne prend pas de commandes près de chez vous. C''est une vitrine d''exemple de Mara.';
    end if;
    return new;
end;
$$;

do $$
begin
    if not exists (select 1 from pg_trigger where tgname = 'orders_showcase_closed') then
        create trigger orders_showcase_closed before insert on orders
            for each row execute function trg_order_showcase();
    end if;
end $$;

-- No cauris, so no league, no podium, no prize.
create or replace function trg_cauris_showcase()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if exists (select 1 from orgs where id = new.org_id and showcase) then
        return null;
    end if;
    return new;
end;
$$;

do $$
begin
    if not exists (select 1 from pg_trigger where tgname = 'cauris_ledger_showcase') then
        create trigger cauris_ledger_showcase before insert on cauris_ledger
            for each row execute function trg_cauris_showcase();
    end if;
end $$;

revoke execute on function showcase_seed()                   from public;
revoke execute on function showcase_list()                   from public;
revoke execute on function showcase_join(uuid)               from public;
revoke execute on function set_showcase_visible(uuid, boolean) from public;
revoke execute on function showcase_slugs()                  from public;
revoke execute on function trg_order_showcase()              from public;
revoke execute on function trg_cauris_showcase()             from public;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        revoke execute on function showcase_seed()                     from anon;
        revoke execute on function showcase_list()                     from anon;
        revoke execute on function showcase_join(uuid)                 from anon;
        revoke execute on function set_showcase_visible(uuid, boolean) from anon;
        revoke execute on function trg_order_showcase()                from anon;
        revoke execute on function trg_cauris_showcase()               from anon;
        grant execute on function showcase_slugs()                     to anon;
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        revoke execute on function trg_order_showcase()                from authenticated;
        revoke execute on function trg_cauris_showcase()               from authenticated;
        grant execute on function showcase_seed()                      to authenticated;
        grant execute on function showcase_list()                      to authenticated;
        grant execute on function showcase_join(uuid)                  to authenticated;
        grant execute on function set_showcase_visible(uuid, boolean)  to authenticated;
        grant execute on function showcase_slugs()                     to authenticated;
    end if;
end $$;

-- The seven, for the first platform admin. None yet (a fresh database):
-- nothing; the console's button makes them later.
select showcase_seed();

notify pgrst, 'reload schema';
