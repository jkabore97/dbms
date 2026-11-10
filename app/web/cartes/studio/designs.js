// Marakaj Studio — the starting documents and the converter (171).
// Every design of today becomes a starting point: its colours, its fonts,
// its photo, and the blocks a card of that kind needs. A card made before
// Studio is turned into a document the first time its organiser opens
// Studio: the card is read as the guests see it (in a hidden frame, the
// organiser's own words and pictures in it) — nothing changes for the
// guests until the organiser saves.
(function () {
  'use strict';
  var S = window.Studio;
  var uid = S.util.uid;

  // ------------------------------------------------- what each kind says
  // The classic cards' presets (shared.js), as Studio's.
  var IC = { rings: 'rings', glass: 'glass', camera: 'camera', dinner: 'food', cake: 'cake', party: 'party', car: 'car', pin: 'pin', dress: 'dress', bed: 'bed',
    cal: 'calendar', gift: 'gift', up: 'star', dove: 'dove', cap: 'star', mic: 'mic', ribbon: 'star', candle: 'star', baby: 'heart', music: 'music' };
  S.CLASSIC_ICONS = IC;
  function steps(l) { return l.map(function (x) { return { time: x[0], icon: IC[x[1]] || 'star', title: x[2], detail: x[3] }; }); }
  var KINDS = {
    mariage: { label: 'Mariage', kicker: 'Nous nous marions', sub: 'se marient !', word: 'Notre jour', prog: 'Le jour J', progIntro: 'Rendez-vous dès 14 h 30. La cérémonie commence à 15 h.', rsvp: 'Serez-vous des nôtres ?', rsvpLead: 'Dites-nous si vous pouvez être des nôtres.', album: 'Vos photos du jour', albumLead: 'Vous avez pris une belle photo pendant la fête ? Ajoutez-la ici : les mariés la verront, et tout le monde la retrouvera dans l’album.',
      body: 'Nous sommes si heureux de partager ce moment avec notre famille et nos amis les plus chers. Votre présence compte tant pour nous.',
      items: steps([['15 h', 'rings', 'Cérémonie', 'Sous la tonnelle'], ['16 h 30', 'glass', 'Cocktail', 'Jus frais et bouchées'], ['18 h', 'camera', 'Photos', 'Avec chaque famille'], ['19 h 30', 'dinner', 'Dîner', 'Tables sous les lumières'], ['21 h', 'cake', 'Gâteau', 'Et la première danse'], ['22 h', 'party', 'Soirée', 'Jusqu’au bout de la nuit']]) },
    dot: { label: 'Fiançailles · dot', kicker: 'Cérémonie de dot', sub: 'unissent leurs familles', word: 'Un mot des deux familles', prog: 'Le déroulement', progIntro: 'Les familles sont accueillies dès 9 h 30.', rsvp: 'Vous venez ?', rsvpLead: 'Dites-nous si vous serez des nôtres.', album: 'Vos photos de la cérémonie', albumLead: 'Ajoutez les photos que vous prenez : les deux familles les retrouveront dans l’album.',
      body: 'Les anciens ont parlé, les colas ont été acceptées. Nous vous attendons pour témoigner, bénir, et manger ensemble.', families: true,
      items: steps([['10 h', 'pin', 'Accueil des familles', 'Sous le hangar'], ['11 h', 'gift', 'Présentation de la dot', 'Colas, pagnes, bijoux'], ['12 h 30', 'rings', 'Bénédictions', 'Des anciens'], ['13 h 30', 'dinner', 'Repas', 'Riz gras, poulet, tô'], ['16 h', 'party', 'Danses', 'Jusqu’au soir']]) },
    anniversaire: { label: 'Anniversaire', kicker: 'Anniversaire', sub: 'fête son anniversaire', word: 'Un mot', prog: 'La soirée', progIntro: 'Les portes ouvrent à 19 h.', rsvp: 'Vous venez ?', rsvpLead: 'Dites-moi si vous serez là, pour le gâteau.', album: 'Vos photos de la soirée', albumLead: 'Ajoutez vos photos de la fête : elles iront dans l’album de la soirée.',
      body: 'Venez fêter ce jour avec moi : de la bonne musique, un bon repas et tous ceux que j’aime.',
      items: steps([['19 h', 'glass', 'Accueil', 'Un verre pour commencer'], ['20 h 30', 'dinner', 'Dîner', 'Buffet'], ['22 h', 'cake', 'Gâteau', 'Les bougies'], ['22 h 30', 'party', 'DJ', 'Jusqu’à 2 h']]) },
    bapteme: { label: 'Baptême', kicker: 'Baptême', sub: 'est baptisé', word: 'Un mot des parents', prog: 'La journée', progIntro: 'La cérémonie commence à 10 h.', rsvp: 'Vous venez ?', rsvpLead: 'Dites-nous si vous serez là.', album: 'Vos photos du jour', albumLead: 'Ajoutez vos photos : elles iront dans l’album de la famille.',
      body: 'Nous avons la joie de vous inviter au baptême de notre enfant. Votre présence nous ferait chaud au cœur.',
      items: steps([['10 h', 'dove', 'Cérémonie', 'À l’église'], ['11 h 30', 'camera', 'Photos', 'Sur le parvis'], ['12 h 30', 'dinner', 'Déjeuner', 'À la maison'], ['15 h', 'cake', 'Gâteau', 'Et les cadeaux']]) },
    naissance: { label: 'Naissance · dénomination', kicker: 'Dénomination', sub: 'est arrivé·e', word: 'Un mot des parents', prog: 'La cérémonie', progIntro: 'Le septième jour, dès 9 h.', rsvp: 'Vous venez ?', rsvpLead: 'Dites-nous si vous serez là.', album: 'Vos photos', albumLead: 'Ajoutez vos photos : elles iront dans l’album du bébé.',
      body: 'Notre famille s’agrandit. Venez fêter l’arrivée de notre bébé avec nous.',
      items: steps([['9 h', 'baby', 'Cérémonie', 'Le nom est donné'], ['10 h', 'dove', 'Bénédictions', 'Des anciens'], ['12 h', 'dinner', 'Repas', 'Pour tous'], ['14 h', 'gift', 'Cadeaux', 'Et les photos']]) },
    diplome: { label: 'Remise de diplômes', kicker: 'Remise de diplômes', sub: 'Promotion 2027', word: 'Un mot', prog: 'La cérémonie', progIntro: 'Les familles sont attendues dès 8 h 30.', rsvp: 'Inscription', rsvpLead: 'Confirmez votre présence et le nombre de places.', album: 'Vos photos', albumLead: 'Ajoutez vos photos de la cérémonie : elles iront dans l’album de la promotion.',
      body: 'Des années d’efforts, un diplôme en poche : venez le fêter avec nous !',
      items: steps([['9 h', 'cap', 'Remise des diplômes', 'Amphithéâtre'], ['11 h', 'mic', 'Discours', 'Major et parrain'], ['12 h', 'camera', 'Photos', 'Par filière'], ['13 h', 'glass', 'Réception', 'Dans le jardin']]) },
    gala: { label: 'Soirée · gala', kicker: 'Soirée', sub: 'vous invite', word: 'Le mot de la direction', prog: 'Le programme', progIntro: 'Accueil à partir de 18 h 30.', rsvp: 'Inscription', rsvpLead: 'Confirmez votre participation.', album: 'Photos de la soirée', albumLead: 'Ajoutez vos photos : elles iront dans l’album de la soirée.',
      body: 'Une soirée pour se retrouver, bien manger et danser. Votre présence compte.',
      items: steps([['18 h 30', 'glass', 'Accueil', 'Cocktail'], ['19 h 30', 'mic', 'Allocutions', 'Dix minutes chacune'], ['20 h 30', 'dinner', 'Dîner', 'Placé'], ['22 h', 'music', 'Concert', 'Sur la terrasse'], ['23 h', 'party', 'Soirée', 'Jusqu’à 1 h']]) },
    inauguration: { label: 'Inauguration', kicker: 'Inauguration', sub: 'ouvre ses portes', word: 'Un mot', prog: 'Le programme', progIntro: 'Rendez-vous devant l’entrée dès 9 h 45.', rsvp: 'Inscription', rsvpLead: 'Confirmez votre venue.', album: 'Photos de l’inauguration', albumLead: 'Ajoutez vos photos : elles iront dans l’album.',
      body: 'Nous avons le plaisir de vous convier à notre inauguration. Venez découvrir ce que nous préparons.',
      items: steps([['10 h', 'ribbon', 'Coupure du ruban', 'Devant l’entrée'], ['10 h 30', 'mic', 'Discours', 'Dans la cour'], ['11 h', 'pin', 'Visite', 'Guidée'], ['12 h', 'glass', 'Cocktail', 'Sur la terrasse']]) },
    concert: { label: 'Concert · spectacle', kicker: 'En concert', sub: 'en live', word: 'Le mot de l’artiste', prog: 'La soirée', progIntro: 'Ouverture des portes à 19 h.', rsvp: 'Réservation', rsvpLead: 'Réservez votre place.', album: 'Photos du concert', albumLead: 'Ajoutez vos photos du concert : elles iront dans l’album de la soirée.',
      body: 'Une scène, des artistes et vous. Venez vibrer avec nous.',
      items: steps([['19 h', 'pin', 'Ouverture des portes', 'Placement libre'], ['20 h', 'mic', 'Première partie', 'Pour chauffer la salle'], ['21 h', 'music', 'Concert', 'Le grand moment'], ['23 h', 'party', 'After', 'Avec le DJ']]) },
    culture: { label: 'Festival · événement culturel', kicker: 'Festival', sub: 'vous attend', word: 'Le mot des organisateurs', prog: 'Le programme', progIntro: 'Ouverture du site à 10 h.', rsvp: 'Réservation', rsvpLead: 'Réservez votre place.', album: 'Photos du festival', albumLead: 'Ajoutez vos photos : elles iront dans l’album du festival.',
      body: 'Contes, danse, théâtre et musique : venez nombreux.',
      items: steps([['10 h', 'pin', 'Ouverture', 'Le village du festival'], ['11 h', 'camera', 'Expositions', 'Artistes et artisans'], ['15 h', 'mic', 'Spectacles', 'Contes, danse, théâtre'], ['20 h', 'music', 'Concerts', 'Sur la grande scène']]) },
    conference: { label: 'Conférence · séminaire', kicker: 'Conférence', sub: 'vous invite', word: 'Le mot des organisateurs', prog: 'Le programme', progIntro: 'Accueil des participants dès 8 h 30.', rsvp: 'Inscription', rsvpLead: 'Inscrivez-vous : les places sont limitées.', album: 'Photos de la journée', albumLead: 'Ajoutez vos photos : elles iront dans l’album de la conférence.',
      body: 'Une journée d’échanges et d’idées. Inscrivez-vous, les places sont limitées.',
      items: steps([['8 h 30', 'glass', 'Accueil', 'Badges et café'], ['9 h', 'mic', 'Interventions', 'À la tribune'], ['12 h 30', 'dinner', 'Déjeuner', 'Sur place'], ['14 h', 'pin', 'Ateliers', 'En petits groupes']]) },
    hommage: { label: 'Hommage · funérailles', kicker: 'En sa mémoire', sub: 'nous a quittés', word: 'Un mot de la famille', prog: 'Les obsèques', progIntro: 'La famille vous remercie de votre présence.', rsvp: 'Vous serez là ?', rsvpLead: 'Pour que la famille s’organise.', album: 'Souvenirs', albumLead: 'Partagez une photo, un souvenir : la famille les gardera.',
      body: 'Nous vous invitons à nous rejoindre pour rendre hommage à un être cher.',
      items: steps([['8 h', 'candle', 'Levée du corps', 'À la morgue'], ['10 h', 'dove', 'Messe', 'À l’église'], ['12 h', 'pin', 'Inhumation', 'Au cimetière'], ['14 h', 'dinner', 'Retour', 'À la maison familiale']]) },
    autre: { label: 'Événement', kicker: 'Vous êtes invités', sub: '', word: 'Un mot', prog: 'Le programme', progIntro: '', rsvp: 'Serez-vous là ?', rsvpLead: 'Dites-nous si vous venez.', album: 'Vos photos', albumLead: 'Ajoutez vos photos : elles iront dans l’album de l’événement.',
      body: 'Nous serions heureux de vous compter parmi nous pour ce moment.',
      items: steps([['15 h', 'pin', 'Accueil', 'Bienvenue à tous'], ['17 h', 'star', 'Le temps fort', 'Le cœur de l’événement'], ['19 h', 'dinner', 'Partage', 'Repas et musique']]) }
  };
  KINDS.anniv = KINDS.anniversaire;
  S.KINDS = KINDS;
  function kindOf(k) { return KINDS[k] || KINDS.autre; }

  // ---------------------------------------------------------- the designs
  // [id, name, back, paper, ink, accent, line, display, body, script, cover variant, stock photo, motif, kinds it suits]
  var D = [
    ['dot', 'Dot', '#0f6b4f', '#fbf5e8', '#1f2a23', '#c2185b', '#e3d3b0', 'yeseva', 'mulish', 'great-vibes', 'cadre', 'dot-1', 'wax', 'dot'],
    ['come', 'Côme', '#4e5c47', '#f6f2e8', '#2f3a2c', '#5b6b52', '#c9c4b1', 'bodoni', 'jost', 'pinyon', 'plein', 'wed-couple-1', '', 'mariage'],
    ['rivage', 'Rivage', '#5c6a4d', '#fbf6ec', '#3c4733', '#4c5c3d', '#d8d0bd', 'italiana', 'cormorant', 'great-vibes', 'plein', 'garden-3', '', 'mariage'],
    ['jardin', 'Jardin', '#6b7557', '#fbf6f1', '#3a3a33', '#6b7557', '#d8cbc0', 'marcellus', 'nunito-sans', 'parisienne', 'arche', 'garden-2', 'fleurs', 'mariage'],
    ['bouquet', 'Bouquet', '#56603f', '#fbfaf7', '#3a3a33', '#5f6a45', '#e3ddd2', 'cormorant', 'jost', 'pinyon', 'cadre', 'garden-1', '', 'mariage'],
    ['cimbrone', 'Cimbrone', '#1a1715', '#f2f0eb', '#161412', '#121110', '#bdb8ae', 'bodoni', 'montserrat', 'mrs-saint', 'plein', 'wed-lake', '', 'mariage'],
    ['ravello', 'Ravello', '#141414', '#f3f1ec', '#151515', '#0f0f0f', '#9d9a92', 'cormorant', 'montserrat', 'mrs-saint', 'plein', 'wed-bw-1', '', 'mariage'],
    ['minuit', 'Minuit', '#06080f', '#0d1322', '#e9e2cf', '#c9a45c', '#3a4260', 'cinzel', 'eb-garamond', 'parisienne', 'plein', 'wed-night-1', 'etoiles', 'mariage gala'],
    ['sahel', 'Sahel', '#2a2342', '#f4e9d8', '#2b1d14', '#b9552f', '#c9ab85', 'fraunces', 'dm-sans', 'great-vibes', 'plein', 'africa-sunset', 'bogolan', 'mariage dot'],
    ['anniv', 'Fête', '#1d1a1a', '#fff4e6', '#1d1a1a', '#e0559b', '#e6cfbb', 'syne', 'dm-sans', 'caveat', 'cadre', 'birthday-cake', 'pois', 'anniversaire'],
    ['bapteme', 'Baptême', '#2f4a6b', '#f7f4ee', '#243244', '#2f4a6b', '#cfd8e0', 'lora', 'nunito', 'allura', 'arche', 'baby-1', '', 'bapteme naissance'],
    ['naissance', 'Naissance', '#c9683f', '#fff8f2', '#3b2d26', '#c9683f', '#e8d3c6', 'josefin', 'lora', 'caveat', 'arche', 'baby-2', 'pois', 'naissance bapteme'],
    ['diplome', 'Diplôme', '#4a1520', '#f7f2ea', '#2a1a1c', '#6b1f2a', '#d9cdb8', 'playfair', 'source-sans', 'great-vibes', 'cadre', 'grad-1', '', 'diplome'],
    ['gala', 'Gala', '#0b0c10', '#15171c', '#f4f6fb', '#2f6bff', '#2b2f3a', 'archivo', 'dm-sans', 'alex-brush', 'plein', 'gala-1', 'lignes', 'gala conference inauguration concert culture'],
    ['hommage', 'Hommage', '#3a3d3a', '#f8f6f1', '#2e2e2e', '#2e2e2e', '#d9d6cf', 'cormorant', 'jost', 'parisienne', 'cadre', 'memorial-1', '', 'hommage'],
    ['wax', 'Wax', '#5a0f3c', '#fdf2f7', '#3d0b28', '#d2468e', '#f0cfe0', 'yeseva', 'mulish', 'great-vibes', 'typo', 'wed-africa-1', 'wax', 'mariage dot anniversaire'],
    ['faso', 'Faso Dan Fani', '#13315c', '#f8f3e6', '#13284d', '#d9a52c', '#e2d6b8', 'fraunces', 'mulish', 'great-vibes', 'typo', 'wed-africa-2', 'kente', 'mariage dot gala culture'],
    ['champagne', 'Champagne', '#8a7558', '#fbf7ef', '#3b3226', '#a88a4f', '#e7dcc7', 'cormorant', 'montserrat', 'pinyon', 'arche', 'wed-couple-2', '', 'mariage anniversaire'],
    ['minimal', 'Épure', '#111111', '#ffffff', '#111111', '#111111', '#dddddd', 'italiana', 'raleway', 'sacramento', 'typo', '', '', 'mariage conference gala autre'],
    ['corail', 'Corail', '#e0664c', '#fff6f1', '#4a2c22', '#d46e4a', '#f1d6c9', 'prata', 'nunito', 'allura', 'cadre', 'party-1', 'fleurs', 'anniversaire naissance autre']
  ];
  var DESIGNS = D.map(function (d) {
    return { id: d[0], name: d[1], theme: { preset: d[0], colors: { back: d[2], paper: d[3], ink: d[4], accent: d[5], line: d[6] }, fonts: { display: d[7], body: d[8], script: d[9] },
      motif: d[12] ? { id: d[12], opacity: 0.1 } : null, motion: 'douce', corners: 'doux' }, cover: d[10], photo: d[11], kinds: d[13].split(' ') };
  });
  // [key, name, what, paper, ink, accent, soft, back, display, body, script, scene, premium] — the animated cards of /evenements/, now Studio designs (173): their living picture behind the cover, the motion « vivante »; the « lx- » ones are Premium
  var A = [
    ["anime_lettre", "La Lettre", "Une enveloppe qui s'ouvre", "#f6f1e9", "#4b4238", "#b98d48", "#e9dcc6", "#2e2620", "cormorant", "cormorant", "great-vibes", "silk", 0],
    ["anime_jardin", "Le Jardin", "Une arche fleurie qui pousse", "#f2f3ee", "#3a4a3e", "#6f8f76", "#dfe7dc", "#26332a", "parisienne", "cormorant", "parisienne", "garden", 0],
    ["anime_nuit", "La Nuit", "Du coucher de soleil aux étoiles", "#0b241b", "#e8dcc0", "#d1ac5e", "#f2a86b", "#f5ebd2", "italiana", "eb-garamond", "pinyon", "sky", 0],
    ["anime_pagne", "Le Pagne", "Couleurs tissées du Faso", "#f4ecdc", "#1d3a6b", "#e2b13c", "#f8f2e6", "#13284d", "anton", "montserrat", "dancing", "loom", 0],
    ["anime_mag", "Le Magazine", "Une couverture et des pages", "#f3e4dc", "#3a2620", "#c86b4f", "#e9c8b8", "#2a1a15", "dm-serif", "montserrat", "great-vibes", "blobs", 0],
    ["anime_blason", "Le Blason", "Un monogramme royal", "#f7f2e8", "#3b3226", "#b08a3e", "#ece1c8", "#2a2117", "cinzel", "cormorant", "parisienne", "velvet", 0],
    ["anime_carnet", "Le Carnet", "Polaroïds et petits mots", "#fbf6ef", "#3a2f2a", "#e86f51", "#f6dcc7", "#2b2420", "caveat", "lora", "homemade", "party", 0],
    ["anime_sahel", "Sahel", "Acacias, girafe, coucher de soleil", "#f6ead4", "#4a3420", "#c9822e", "#efdcbc", "#3a2412", "tenor", "raleway", "alex-brush", "sahel", 0],
    ["anime_lotus", "Le Lotus", "Un étang, des carpes koï, des lotus", "#f7f1f0", "#3b3a3c", "#e0739b", "#e3efe8", "#24403a", "fraunces", "lora", "sacramento", "lotus", 0],
    ["anime_foret", "La Forêt", "Brume, rayons de lumière, fougères", "#eef2ea", "#2c3a2e", "#7a8f4e", "#dfe8dc", "#1b2a1e", "italiana", "eb-garamond", "parisienne", "forest", 0],
    ["anime_cerisiers", "Les Cerisiers", "Une branche en fleurs, des pétales au vent", "#fbf3f4", "#4a3a3e", "#e48aa2", "#f6dfe4", "#3a2329", "shippori", "shippori", "mrs-saint", "sakura", 0],
    ["anime_tournesols", "Les Tournesols", "Des fleurs qui suivent le soleil", "#fffaf0", "#3a3018", "#e6a417", "#f7ecc8", "#2b2208", "abril", "josefin", "dancing", "sunflowers", 0],
    ["anime_lanternes", "Les Lanternes", "Des lanternes qui s'envolent sur l'eau", "#1a1630", "#efe4d2", "#f0a35a", "#2c2650", "#fff4e2", "yeseva", "eb-garamond", "petit-formal", "lanterns", 0],
    ["anime_roseraie", "La Roseraie", "Des rosiers grimpants qui fleurissent", "#fbf4f1", "#45302c", "#c0303f", "#f1ddd6", "#3a1a1c", "playfair", "lora", "great-vibes", "roses", 0],
    ["anime_desert", "Le Désert", "Une bande-annonce dans les dunes", "#f4e6cf", "#3a2a18", "#d6a04e", "#e8d2a8", "#2a1c0e", "julius", "montserrat", "cormorant", "desert", 0],
    ["anime_ocean", "L'Océan", "Des cartes postales du bord de mer", "#f6efe8", "#33302e", "#e07a5f", "#f0dcd0", "#22303e", "marcellus", "montserrat", "dancing", "ocean", 0],
    ["anime_champagne", "Champagne", "Bulles, paillettes et lumières", "#1a1712", "#efe4cc", "#d9b56a", "#2e2a22", "#fbf3e0", "limelight", "raleway", "poiret", "champagne", 0],
    ["anime_papillons", "Les Papillons", "Un nuage de papillons qui dessine un cœur", "#fdf8f2", "#3e3026", "#e8892f", "#f5e6d2", "#2a1e14", "cormorant", "eb-garamond", "homemade", "butterflies", 0],
    ["anime_hiver", "Boule à neige", "Un village d'hiver qu'on secoue", "#e9eef6", "#26324a", "#b89650", "#d6deec", "#16223a", "cinzel", "raleway", "parisienne", "globe", 0],
    ["anime_feux", "Feux d'artifice", "Une ville en fête, de plus en plus de feux", "#0c0b18", "#e8e4f4", "#f2c14e", "#1c1a30", "#ffffff", "dm-serif", "montserrat", "great-vibes", "fireworks", 0],
    ["anime_aurore", "L'Aurore", "Des aurores boréales sur un lac", "#0a1220", "#dfeef4", "#6fe0b8", "#14223a", "#ffffff", "poiret", "tenor", "pinyon", "aurora", 0],
    ["anime_sahel_p", "Savane d'or", "Soleil couchant, acacias, un horizon d'or", "#f6ead4", "#4a3420", "#c9822e", "#efdcbc", "#3a2412", "marcellus", "cormorant", "alex-brush", "lx-savane", 1],
    ["anime_lotus_p", "Étang de lotus", "Eau vivante, carpes koï, médaillon de verre", "#f7f1f0", "#3b3a3c", "#e0739b", "#e3efe8", "#24403a", "tenor", "lora", "sacramento", "lx-lotus", 1],
    ["anime_foret_p", "Forêt enchantée", "Brume, rayons de lumière, lucioles", "#eef2ea", "#2c3a2e", "#7a8f4e", "#dfe8dc", "#1b2a1e", "fraunces", "fraunces", "parisienne", "lx-foret", 1],
    ["anime_cerisiers_p", "Paravent de cerisiers", "Panneaux d'or, papiers, sceau rouge", "#fbf3f4", "#4a3a3e", "#e48aa2", "#f6dfe4", "#3a2329", "shippori", "shippori", "mrs-saint", "lx-cerisiers", 1],
    ["anime_tournesols_p", "Champ d'or", "Affiche audacieuse, tournesols au soleil", "#fffaf0", "#3a3018", "#e6a417", "#f7ecc8", "#2b2208", "abril", "josefin", "dancing", "lx-tournesols", 1],
    ["anime_lanternes_p", "Nuit des lanternes", "Chaque chapitre est une lanterne", "#1a1630", "#efe4d2", "#f0a35a", "#2c2650", "#fff4e2", "yeseva", "eb-garamond", "petit-formal", "lx-lanternes", 1],
    ["anime_roseraie_p", "Velours & roses", "Roses épanouies, cartes ivoire, sceau de cire", "#fbf4f1", "#45302c", "#c0303f", "#f1ddd6", "#3a1a1c", "bodoni", "cormorant", "great-vibes", "lx-roseraie", 1],
    ["anime_desert_p", "Caravane des dunes", "Dunes éclairées, piste d'étape en étape", "#f4e6cf", "#3a2a18", "#d6a04e", "#e8d2a8", "#2a1c0e", "julius", "tenor", "cormorant", "lx-dunes", 1],
    ["anime_ocean_p", "Carte du rivage", "Vagues réelles, rose des vents, écume", "#f6efe8", "#33302e", "#e07a5f", "#f0dcd0", "#22303e", "playfair", "montserrat", "dancing", "lx-rivage", 1],
    ["anime_champagne_p", "Champagne Gatsby", "Bulles, or et cadres Art déco", "#1a1712", "#efe4cc", "#d9b56a", "#2e2a22", "#fbf3e0", "limelight", "raleway", "poiret", "lx-champagne", 1],
    ["anime_papillons_p", "Herbier aux papillons", "Vieux papier, planches, papillons vrais", "#fdf8f2", "#3e3026", "#e8892f", "#f5e6d2", "#2a1e14", "cormorant", "eb-garamond", "homemade", "lx-herbier", 1],
    ["anime_hiver_p", "Fenêtre givrée", "Le givre gagne la vitre en défilant", "#e9eef6", "#26324a", "#b89650", "#d6deec", "#16223a", "cinzel", "raleway", "parisienne", "lx-givre", 1],
    ["anime_feux_p", "Grand soir", "Vos prénoms écrits par les étincelles", "#0c0b18", "#e8e4f4", "#f2c14e", "#1c1a30", "#ffffff", "dm-serif", "montserrat", "great-vibes", "lx-feux", 1],
    ["anime_aurore_p", "Boréale", "Aurores sur le lac, une constellation", "#0a1220", "#dfeef4", "#6fe0b8", "#14223a", "#ffffff", "italiana", "tenor", "pinyon", "lx-aurore", 1]
  ];
  A.forEach(function (a) {
    DESIGNS.push({ id: a[0], name: a[1], what: a[2], animated: true, premium: !!a[12], scene: a[11],
      theme: { preset: a[0], colors: { back: a[7], paper: a[3], ink: a[4], accent: a[5], soft: a[6], line: a[6] }, fonts: { display: a[8], body: a[9], script: a[10] },
        motif: null, motion: 'vivante', corners: 'doux', scene: a[11] },
      cover: 'typo', photo: '', kinds: Object.keys(KINDS) });
  });
  S.DESIGNS = DESIGNS;
  function design(id) { return DESIGNS.filter(function (d) { return d.id === id; })[0] || null; }
  S.design = design;
  // The animated designs (anime_<layout>), to the nearest starting design.
  var ANIM = { lettre: 'champagne', jardin: 'jardin', nuit: 'minuit', pagne: 'faso', mag: 'minimal', blason: 'diplome', carnet: 'corail', sahel: 'sahel', lotus: 'bapteme',
    foret: 'come', cerisiers: 'champagne', tournesols: 'anniv', lanternes: 'minuit', roseraie: 'jardin', desert: 'sahel', ocean: 'bapteme', champagne: 'champagne',
    papillons: 'corail', hiver: 'bapteme', feux: 'gala', aurore: 'minuit' };
  function designFor(card, kind) {
    if (design(card)) return design(card);
    var m = /^anime_([a-z]+?)(_p)?$/.exec(String(card || ''));
    if (m && ANIM[m[1]]) return design(ANIM[m[1]]);
    return DESIGNS.filter(function (d) { return d.kinds.indexOf(kind) >= 0; })[0] || design('come');
  }
  S.designFor = designFor;

  // ----------------------------------------------------- a starting document
  // an animated design: its living picture behind the cover (and the answer)
  function sceneStyle(d) { return d && d.scene ? { bg: 'scene', scene: d.scene } : null; }
  S.sceneStyle = sceneStyle;
  function blk(type, variant, props, style) { var b = { id: uid(), type: type, variant: variant, props: props || {} }; if (style) b.style = style; return b; }
  S.starter = function (designId, ctx) {
    var d = design(designId) || designFor(ctx.card, ctx.kind), k = kindOf(ctx.kind), title = ctx.title || 'Vos prénoms';
    var two = title.split(/\s*(?:&|\bet\b)\s*/);
    var blocks = [
      blk('cover', d.cover, { kicker: k.kicker, names: title, sub: '', photo: d.photo ? { stock: d.photo, pos: [50, 40] } : null, showDate: true, showPlace: true }, sceneStyle(d)),
      blk('text', 'simple', { kicker: '', title: k.word, body: k.body, sign: two.length > 1 ? two.join(' & ') : '' }, { sep: 'fleur' })
    ];
    if (k.families) blocks.push(blk('families', 'cote', { title: 'Les familles', left: 'Famille ' + (two[0] || ''), leftNote: '', right: 'Famille ' + (two[1] || ''), rightNote: '', joiner: '&' }, { bg: 'soft' }));
    blocks.push(blk('programme', 'timeline', { title: k.prog, intro: k.progIntro, showTimes: true, items: JSON.parse(JSON.stringify(k.items)) }));
    blocks.push(blk('countdown', 'grand', { title: 'Plus que', doneText: 'C’est aujourd’hui !' }, { bg: 'accent' }));
    blocks.push(blk('place', 'simple', { title: 'Le lieu', name: ctx.place || 'Le lieu', address: '', note: '' }));
    blocks.push(blk('rsvp', 'carte', { title: k.rsvp, lead: k.rsvpLead, yes: 'Je viens', no: 'Je ne peux pas', askPhone: true, pass: false }, sceneStyle(d) || { bg: 'back' }));
    blocks.push(blk('album', 'grille', { title: k.album, lead: k.albumLead }));
    blocks.push(blk('footer', 'simple', { text: title }));
    return { v: 2, theme: JSON.parse(JSON.stringify(d.theme)), blocks: blocks, meta: { from: d.id } };
  };

  // ----------------------------------------------------------- the converter
  // A card made before Studio, read as the organiser sees it (the page in a
  // hidden frame), into a document.
  function t(el) { return el ? el.textContent.replace(/[ \t]+/g, ' ').replace(/\s*\n\s*/g, '\n').trim() : ''; }
  // the names as they read (173): « Inès<span class="et">et</span>Thomas »
  // draws « et » on a line of its own — read plainly, it was « InèsetThomas »
  // (Côme, Cimbrone, Jardin, Ravello, Rivage, Sahel)
  function spaced(el) {
    if (!el) return '';
    var c = el.cloneNode(true);
    Array.prototype.forEach.call(c.querySelectorAll('*'), function (x) { x.before(' '); x.after(' '); });
    return t(c).replace(/\s+/g, ' ').trim();
  }
  S.spacedText = spaced;
  function stockOf(src) { var m = /\/img\/([a-z0-9-]+)\.jpg/.exec(src || ''); return m && S.STOCK.indexOf(m[1]) >= 0 ? m[1] : null; }
  function picFrom(content, key, img) {
    var c = content && content['p:' + key];
    if (c && c.key) { var pos = /^(\d+(?:\.\d+)?)% (\d+(?:\.\d+)?)%$/.exec(c.pos || ''); return { key: c.key, pos: pos ? [+pos[1], +pos[2]] : [50, 50] }; }
    var st = stockOf(img && img.getAttribute('src'));
    return st ? { stock: st, pos: [50, 50] } : null;
  }
  var FONT_MATCH = [[/cormorant garamond/i, 'cormorant'], [/cormorant/i, 'cormorant'], [/playfair/i, 'playfair'], [/bodoni/i, 'bodoni'], [/cinzel/i, 'cinzel'], [/italiana/i, 'italiana'],
    [/fraunces/i, 'fraunces'], [/yeseva/i, 'yeseva'], [/dm serif/i, 'dm-serif'], [/marcellus/i, 'marcellus'], [/prata/i, 'prata'], [/abril/i, 'abril'], [/gilda/i, 'gilda'],
    [/tenor/i, 'tenor'], [/montserrat/i, 'montserrat'], [/jost/i, 'jost'], [/lora/i, 'lora'], [/eb garamond/i, 'eb-garamond'], [/raleway/i, 'raleway'], [/mulish/i, 'mulish'],
    [/nunito sans/i, 'nunito-sans'], [/nunito/i, 'nunito'], [/karla/i, 'karla'], [/work sans/i, 'work-sans'], [/crimson/i, 'crimson'], [/josefin/i, 'josefin'],
    [/great vibes/i, 'great-vibes'], [/pinyon/i, 'pinyon'], [/parisienne/i, 'parisienne'], [/allura/i, 'allura'], [/alex brush/i, 'alex-brush'], [/dancing/i, 'dancing'],
    [/caveat/i, 'caveat'], [/sacramento/i, 'sacramento'], [/tangerine/i, 'tangerine'], [/syne/i, 'syne'], [/dm sans/i, 'dm-sans'], [/source sans/i, 'source-sans'],
    [/archivo/i, 'archivo'], [/saint delafield/i, 'mrs-saint']];
  function fontId(family) { family = String(family || ''); for (var i = 0; i < FONT_MATCH.length; i++) if (FONT_MATCH[i][0].test(family)) return FONT_MATCH[i][1]; return null; }
  function hexOf(v) {
    v = String(v || '').trim();
    if (/^#[0-9a-f]{6}$/i.test(v)) return v.toLowerCase();
    if (/^#[0-9a-f]{3}$/i.test(v)) return ('#' + v[1] + v[1] + v[2] + v[2] + v[3] + v[3]).toLowerCase();
    var m = v.match(/\d+(\.\d+)?/g); if (!m || m.length < 3) return null;
    return '#' + m.slice(0, 3).map(function (x) { return ('0' + Math.round(+x).toString(16)).slice(-2); }).join('');
  }
  var ICON_OF = function (use) { var h = use && (use.getAttribute('href') || use.getAttribute('xlink:href')) || ''; var m = /#i-([a-z]+)/.exec(h); return m ? (IC[m[1]] || 'star') : 'star'; };
  // The guest's card (QR) as the card showed it: on, except on a fiançailles card unless switched on (170d).
  function passOn(content, boot) {
    var has = function (k, x) { return new RegExp('(^|,)' + x + '(,|$)').test(content[k] || ''); };
    if (has('t:hide', 'qr')) return false;
    return boot.kind === 'dot' ? has('t:show', 'qr') : true;
  }
  function visible(el) { return el && !el.closest('.is-off, .li-off, [hidden]'); }
  // The organiser's own Google Maps link for « Itinéraire » (t:map), https only.
  function mapOf(content) { var v = String((content && content['t:map']) || '').trim(); return /^https:\/\/[^\s<>"'`]+$/.test(v) && v.length <= 600 ? v : ''; }

  // A classic card (/cartes/<design>.html, shared.js), its DOM as drawn.
  function harvestClassic(doc, boot) {
    var root = doc.documentElement, cs = doc.defaultView.getComputedStyle(root), content = boot.content || {};
    var base = designFor(boot.card, boot.kind), theme = JSON.parse(JSON.stringify(base.theme));
    ['back', 'paper', 'ink', 'accent', 'line'].forEach(function (k) { var v = hexOf(cs.getPropertyValue('--' + k)); if (v) theme.colors[k] = v; });
    var h1 = doc.querySelector('h1'), body = doc.body;
    var fd = fontId(cs.getPropertyValue('--display')) || fontId(h1 && doc.defaultView.getComputedStyle(h1).fontFamily), fb = fontId(cs.getPropertyValue('--body')) || fontId(doc.defaultView.getComputedStyle(body).fontFamily), fs = fontId(cs.getPropertyValue('--script'));
    if (fd) theme.fonts.display = fd; if (fb) theme.fonts.body = fb; if (fs) theme.fonts.script = fs;
    var blocks = [], k = kindOf(boot.kind);
    // the cover
    var names = spaced(doc.querySelector('[data-edit="names"]')) || boot.title || '';
    var heroSlot = doc.querySelector('[data-pic="hero"]');
    blocks.push(blk('cover', base.cover, { kicker: t(doc.querySelector('[data-edit="kicker"]')) || k.kicker, names: names, sub: t(doc.querySelector('[data-edit="sub"]')),
      photo: picFrom(content, 'hero', heroSlot && heroSlot.querySelector('img')) || (base.photo ? { stock: base.photo, pos: [50, 40] } : null), showDate: true, showPlace: true }));
    // the word (or the welcome)
    var wt = doc.querySelector('[data-role="word-title"]'), ws = (wt && wt.closest('section')) || doc.querySelector('section.word, section.welcome');
    if (ws && visible(ws)) {
      var paras = Array.prototype.filter.call(ws.querySelectorAll('p, blockquote'), function (p) { return !p.closest('.slot') && p !== wt && !p.classList.contains('eyebrow') && !p.classList.contains('plus') && t(p); });
      var sign = ws.querySelector('.sign, cite');
      blocks.push(blk('text', 'simple', { kicker: t(ws.querySelector('.eyebrow')), title: t(wt) || t(ws.querySelector('h2')), body: paras.map(t).join('\n\n'), sign: t(sign) }, { sep: 'fleur' }));
    }
    // the photos of the model, then the organiser's gallery
    var photos = [];
    Array.prototype.forEach.call(doc.querySelectorAll('.pics .slot[data-pic], .xpics .slot[data-pic]'), function (s) {
      if (!visible(s)) return; var p = picFrom(content, s.getAttribute('data-pic'), s.querySelector('img')); if (p) photos.push(p);
    });
    // the programme
    var pl = doc.querySelector('[data-prog]');
    if (pl && visible(pl)) {
      var noTimes = !!(doc.querySelector('[data-prog] [data-t].is-off, [data-prog] [data-t].is-blank'));
      blocks.push(blk('programme', 'timeline', { title: t(doc.querySelector('[data-role="prog-title"]')) || k.prog, intro: t(doc.querySelector('[data-role="prog-intro"]')), showTimes: !noTimes,
        items: Array.prototype.filter.call(pl.querySelectorAll('li'), visible).map(function (li) {
          return { time: t(li.querySelector('[data-t]')), title: t(li.querySelector('[data-b]')), detail: t(li.querySelector('[data-s]')), icon: ICON_OF(li.querySelector('use')) };
        }) }));
    }
    if (photos.length) blocks.push(blk('gallery', photos.length >= 3 ? 'mosaique' : 'grille', { title: '', photos: photos }));
    var cd = doc.querySelector('[data-count]');
    if (cd && visible(cd)) blocks.push(blk('countdown', 'grand', { title: 'Plus que', doneText: 'C’est aujourd’hui !' }, { bg: 'accent' }));
    // Bon à savoir
    var inf = doc.querySelector('ul.infos');
    if (inf && visible(inf)) {
      blocks.push(blk('infos', 'liste', { title: t(inf.closest('section') && inf.closest('section').querySelector('.eyebrow, h2')) || 'Bon à savoir',
        items: Array.prototype.filter.call(inf.querySelectorAll('li'), visible).map(function (li) {
          var a = li.querySelector('a[href^="https://"]');
          return { icon: ICON_OF(li.querySelector('use')), title: t(li.querySelector('b')), text: t(li.querySelector('p')), href: a ? a.getAttribute('href') : '', hrefLabel: a ? t(a) : '' };
        }) }, { bg: 'soft' }));
    }
    blocks.push(blk('place', 'simple', { title: 'Le lieu', name: boot.place || '', address: '', note: '', href: mapOf(content) }));
    // the answer, the album, the footer
    var form = doc.querySelector('form.rsvp');
    if (form && visible(form)) blocks.push(blk('rsvp', 'carte', { title: t(doc.querySelector('[data-role="rsvp-title"]')) || k.rsvp, lead: t(doc.querySelector('[data-role="rsvp-lead"]')) || k.rsvpLead, yes: 'Je viens', no: 'Je ne peux pas', askPhone: true, pass: passOn(content, boot) }, { bg: 'back' }));
    var al = doc.querySelector('.album-box');
    if (al && visible(al) && boot.album_on !== false) blocks.push(blk('album', 'grille', { title: t(doc.querySelector('[data-role="album-title"]')) || k.album, lead: t(doc.querySelector('[data-role="album-lead"]')) || k.albumLead }));
    var foot = doc.querySelector('.foot');
    if (!foot || visible(foot)) blocks.push(blk('footer', 'simple', { text: names }));
    // the organiser's own texts, in their places
    addPlus(blocks, content, 't:');
    return { v: 2, theme: theme, blocks: blocks, meta: { from: boot.card || base.id, converted: true } };
  }
  // The organiser's added texts (170c), into text blocks at their places.
  function addPlus(blocks, content, pre) {
    var at = String(content[pre + 'plus-at'] || '').split(',').map(function (s) { var m = /^(\d+)@(intro|prog|rsvp)$/.exec(s.trim()); return m ? { n: +m[1], at: m[2] } : null; }).filter(Boolean);
    Object.keys(content).forEach(function (k) { var m = new RegExp('^' + pre.replace(':', '\\:') + 'plus-(\\d+)$').exec(k); if (m && !at.some(function (x) { return x.n === +m[1]; })) at.push({ n: +m[1], at: 'intro' }); });
    at.forEach(function (x) {
      var html = content[pre + 'plus-' + x.n]; if (!html) return;
      var d = document.createElement('div'); d.innerHTML = String(html); var text = d.textContent.replace(/\s+/g, ' ').trim(); if (!text) return;
      var b = blk('text', 'simple', { kicker: '', title: '', body: text, sign: '' });
      var anchorType = { intro: 'text', prog: 'programme', rsvp: 'rsvp' }[x.at], i = -1;
      blocks.forEach(function (bb, j) { if (bb.type === anchorType && i < 0) i = j; });
      if (x.at === 'rsvp') blocks.splice(i < 0 ? blocks.length : i, 0, b); else blocks.splice(i < 0 ? 1 : i + 1, 0, b);
    });
  }
  // An animated card (/evenements/), its DOM as drawn for the organiser ([data-t] words).
  function harvestAnimated(doc, boot) {
    var root = doc.documentElement, cs = doc.defaultView.getComputedStyle(root), content = boot.content || {};
    var base = designFor(boot.card, boot.kind), theme = JSON.parse(JSON.stringify(base.theme));
    var bg = hexOf(cs.getPropertyValue('--bg')), ink = hexOf(cs.getPropertyValue('--ink')), acc = hexOf(cs.getPropertyValue('--accent')), soft = hexOf(cs.getPropertyValue('--soft')), deep = hexOf(cs.getPropertyValue('--deep'));
    if (bg) theme.colors.paper = bg; if (ink) theme.colors.ink = ink; if (acc) theme.colors.accent = acc; if (soft) theme.colors.soft = soft; if (deep) theme.colors.back = deep;
    var w = function (k) { var e = doc.querySelector('[data-t="' + k + '"]'); return e && !e.classList.contains('off') ? t(e) : ''; };
    var names = w('plain') || [w('a'), w('b')].filter(Boolean).join(' & ') || boot.title || '';
    var k = kindOf(boot.kind), blocks = [];
    var p1 = content['p:p1'] && content['p:p1'].key ? picFrom(content, 'p1') : (base.photo ? { stock: base.photo, pos: [50, 40] } : null);
    // its living picture kept (173): behind the cover and the answer, as on its page
    blocks.push(blk('cover', base.animated && p1 && p1.key ? 'cadre' : base.cover, { kicker: w('eye') || k.kicker, names: names, sub: '', photo: p1, showDate: true, showPlace: true }, sceneStyle(base)));
    var intro = w('intro');
    if (intro) blocks.push(blk('text', 'simple', { kicker: '', title: '', body: intro, sign: '' }, { sep: 'fleur' }));
    var items = [];
    for (var i = 0; i < 8; i++) {
      var n = w('prog-' + i + '-1'); if (!doc.querySelector('[data-t="prog-' + i + '-1"]')) break;
      if (n || w('prog-' + i + '-2')) items.push({ time: w('prog-' + i + '-0'), title: n, detail: w('prog-' + i + '-2'), icon: 'star' });
    }
    if (items.length) blocks.push(blk('programme', 'timeline', { title: k.prog, intro: '', showTimes: !/(^|,)times(,|$)/.test(content['t:hide'] || ''), items: items }));
    var gal = Object.keys(content).filter(function (x) { return /^p:g\d+$/.test(x) && content[x] && content[x].key; }).map(function (x) { return picFrom(content, x.slice(2)); }).filter(Boolean);
    if (gal.length) blocks.push(blk('gallery', 'grille', { title: '', photos: gal }));
    if (!/(^|,)cd(,|$)/.test(content['t:hide'] || '')) blocks.push(blk('countdown', 'grand', { title: 'Plus que', doneText: 'C’est aujourd’hui !' }, { bg: 'accent' }));
    if (!/(^|,)place(,|$)/.test(content['t:hide'] || '')) blocks.push(blk('place', 'simple', { title: 'Le lieu', name: w('place') || boot.place || '', address: '', note: '', href: mapOf(content) }));
    if (!/(^|,)rsvp(,|$)/.test(content['t:hide'] || '')) blocks.push(blk('rsvp', 'carte', { title: k.rsvp, lead: k.rsvpLead, yes: 'Je viens', no: 'Je ne peux pas', askPhone: true, pass: passOn(content, boot) }, sceneStyle(base) || { bg: 'back' }));
    if (boot.album_on !== false) blocks.push(blk('album', 'grille', { title: k.album, lead: k.albumLead }));
    if (!/(^|,)foot(,|$)/.test(content['t:hide'] || '')) blocks.push(blk('footer', 'simple', { text: names }));
    addPlus(blocks, content, 't:');
    if (/^#[0-9a-f]{6},#[0-9a-f]{6},#[0-9a-f]{6}$/i.test(content['t:colors'] || '')) { var c = content['t:colors'].split(','); theme.colors.paper = c[0]; theme.colors.ink = c[1]; theme.colors.accent = c[2]; delete theme.colors.soft; }
    return { v: 2, theme: theme, blocks: blocks, meta: { from: boot.card || base.id, converted: true } };
  }
  // The card in a hidden frame, read once drawn; the model's document if it cannot be read.
  S.convert = function (boot, done) {
    var fallback = function () { done(S.starter(designFor(boot.card, boot.kind).id, boot), false); };
    if (!boot.slug || !boot.edit || typeof document === 'undefined') { fallback(); return; }
    var f = document.createElement('iframe'), finished = false;
    f.className = 'ed-hidden-frame'; f.setAttribute('aria-hidden', 'true'); f.tabIndex = -1;
    var finish = function (doc, ok) { if (finished) return; finished = true; clearTimeout(timer); if (f.parentNode) f.parentNode.removeChild(f); if (doc) done(doc, ok); else fallback(); };
    var timer = setTimeout(function () { finish(null); }, 15000);
    f.onload = function () {
      setTimeout(function () {
        try {
          var d = f.contentDocument; if (!d || !d.body) return finish(null);
          var animated = !!d.getElementById('site');
          var doc = animated ? harvestAnimated(d, boot) : harvestClassic(d, boot);
          finish(doc, true);
        } catch (e) { finish(null); }
      }, 1200);
    };
    f.src = '/e/' + encodeURIComponent(boot.slug) + '?modifier=' + encodeURIComponent(boot.edit) + '&studio=lire';
    document.body.appendChild(f);
  };
  S.harvestClassic = harvestClassic; S.harvestAnimated = harvestAnimated;
})();
