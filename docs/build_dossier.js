const fs = require('fs');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, ShadingType, BorderStyle,
  LevelFormat, PageBreak, convertInchesToTwip,
} = require('docx');

// A4 portrait, 1" margins -> usable width in DXA
const W = 9026;
const TEAL = '0D7A70';
const TEAL_DARK = '0A5A53';
const GREY = '5A6B6A';
const RULE = 'D6E2E0';
const BAND = 'EEF5F4';

// ---------------------------------------------------------------- helpers

const p = (text, opts = {}) => new Paragraph({
  spacing: { after: opts.after ?? 140, line: 276 },
  alignment: opts.align,
  children: [new TextRun({
    text,
    font: 'Calibri',
    size: opts.size ?? 21,          // half-points: 21 = 10.5pt
    color: opts.color ?? '1A1A1A',
    bold: opts.bold,
    italics: opts.italics,
  })],
});

/** A paragraph mixing bold lead-in and normal text. */
const pRich = (runs, opts = {}) => new Paragraph({
  spacing: { after: opts.after ?? 140, line: 276 },
  children: runs.map((r) => new TextRun({
    text: r.t,
    font: 'Calibri',
    size: opts.size ?? 21,
    color: r.color ?? opts.color ?? '1A1A1A',
    bold: r.b,
    italics: r.i,
  })),
});

const h1 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_1,
  spacing: { before: 380, after: 160 },
  border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: TEAL, space: 6 } },
  children: [new TextRun({ text, font: 'Cambria', size: 30, bold: true, color: TEAL_DARK })],
});

const h2 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_2,
  spacing: { before: 260, after: 100 },
  children: [new TextRun({ text, font: 'Cambria', size: 24, bold: true, color: '1A1A1A' })],
});

const bullet = (text, opts = {}) => new Paragraph({
  numbering: { reference: 'puces', level: 0 },
  spacing: { after: 80, line: 276 },
  children: [new TextRun({
    text, font: 'Calibri', size: 21, color: '1A1A1A', bold: opts.bold,
  })],
});

const bulletRich = (runs) => new Paragraph({
  numbering: { reference: 'puces', level: 0 },
  spacing: { after: 80, line: 276 },
  children: runs.map((r) => new TextRun({
    text: r.t, font: 'Calibri', size: 21, color: '1A1A1A', bold: r.b, italics: r.i,
  })),
});

const numbered = (text) => new Paragraph({
  numbering: { reference: 'chiffres', level: 0 },
  spacing: { after: 80, line: 276 },
  children: [new TextRun({ text, font: 'Calibri', size: 21, color: '1A1A1A' })],
});

const cell = (text, { widths, bold, shade, color, align } = {}) => new TableCell({
  width: { size: widths, type: WidthType.DXA },
  shading: shade ? { type: ShadingType.CLEAR, fill: shade, color: 'auto' } : undefined,
  margins: { top: 90, bottom: 90, left: 130, right: 130 },
  children: [new Paragraph({
    alignment: align,
    spacing: { after: 0, line: 260 },
    children: [new TextRun({
      text, font: 'Calibri', size: 20, bold, color: color ?? '1A1A1A',
    })],
  })],
});

/** cols: array of DXA widths. rows: array of arrays of strings. */
const table = (cols, header, rows) => new Table({
  columnWidths: cols,
  width: { size: W, type: WidthType.DXA },
  borders: {
    top: { style: BorderStyle.SINGLE, size: 4, color: RULE },
    bottom: { style: BorderStyle.SINGLE, size: 4, color: RULE },
    left: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
    right: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
    insideHorizontal: { style: BorderStyle.SINGLE, size: 4, color: RULE },
    insideVertical: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
  },
  rows: [
    new TableRow({
      tableHeader: true,
      children: header.map((t, i) =>
        cell(t, { widths: cols[i], bold: true, shade: BAND, color: TEAL_DARK })),
    }),
    ...rows.map((r) => new TableRow({
      children: r.map((t, i) => cell(t, { widths: cols[i] })),
    })),
  ],
});

/** A tinted callout block. */
const callout = (title, lines) => new Table({
  columnWidths: [W],
  width: { size: W, type: WidthType.DXA },
  borders: {
    top: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
    bottom: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
    left: { style: BorderStyle.SINGLE, size: 18, color: TEAL },
    right: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
    insideHorizontal: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
    insideVertical: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
  },
  rows: [new TableRow({
    children: [new TableCell({
      width: { size: W, type: WidthType.DXA },
      shading: { type: ShadingType.CLEAR, fill: BAND, color: 'auto' },
      margins: { top: 170, bottom: 170, left: 220, right: 200 },
      children: [
        new Paragraph({
          spacing: { after: 90 },
          children: [new TextRun({
            text: title, font: 'Cambria', size: 22, bold: true, color: TEAL_DARK,
          })],
        }),
        ...lines.map((t, i) => new Paragraph({
          spacing: { after: i === lines.length - 1 ? 0 : 90, line: 276 },
          children: [new TextRun({ text: t, font: 'Calibri', size: 21, color: '1A1A1A' })],
        })),
      ],
    })],
  })],
});

const spacer = (h = 200) => new Paragraph({ spacing: { after: h }, children: [] });

// ---------------------------------------------------------------- document

const doc = new Document({
  creator: 'Kaj',
  title: 'Kaj — Dossier de présentation',
  description: "Plateforme de gestion pour les petites entreprises burkinabè",
  numbering: {
    config: [
      {
        reference: 'puces',
        levels: [{
          level: 0,
          format: LevelFormat.BULLET,
          text: '•',
          alignment: AlignmentType.LEFT,
          style: {
            paragraph: { indent: { left: convertInchesToTwip(0.3), hanging: convertInchesToTwip(0.18) } },
            run: { color: TEAL },
          },
        }],
      },
      {
        reference: 'chiffres',
        levels: [{
          level: 0,
          format: LevelFormat.DECIMAL,
          text: '%1.',
          alignment: AlignmentType.LEFT,
          style: {
            paragraph: { indent: { left: convertInchesToTwip(0.32), hanging: convertInchesToTwip(0.22) } },
            run: { color: TEAL, bold: true },
          },
        }],
      },
    ],
  },
  sections: [{
    properties: { page: { margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 } } },
    children: [

      // ============================= COUVERTURE
      spacer(1400),
      new Paragraph({
        spacing: { after: 60 },
        children: [new TextRun({
          text: 'KAJ', font: 'Cambria', size: 84, bold: true, color: TEAL_DARK,
        })],
      }),
      new Paragraph({
        spacing: { after: 420 },
        border: { bottom: { style: BorderStyle.SINGLE, size: 14, color: TEAL, space: 10 } },
        children: [new TextRun({
          text: 'La gestion quotidienne des petites entreprises burkinabè, sur un téléphone qui fonctionne sans réseau.',
          font: 'Cambria', size: 26, color: GREY,
        })],
      }),
      p('Dossier de présentation', { size: 24, bold: true }),
      p("À l'attention d'un partenaire potentiel", { size: 21, color: GREY }),
      spacer(260),
      p('Document confidentiel — usage interne', { size: 18, color: GREY, italics: true }),

      new Paragraph({ children: [new PageBreak()] }),

      // ============================= RÉSUMÉ
      h1('1. Résumé'),
      p("Kaj est une application de gestion destinée aux très petites et petites entreprises du Burkina Faso : boutiques, exploitations agricoles, associations et paroisses. Elle remplace le cahier papier par un enregistrement quotidien tenu sur téléphone, et produit automatiquement une comptabilité en partie double, des factures conformes et des états de synthèse."),
      pRich([
        { t: "Sa particularité technique est décisive sur ce marché : ", b: false },
        { t: "l'application fonctionne intégralement sans connexion", b: true },
        { t: ". Les enregistrements sont écrits sur l'appareil et synchronisés plus tard, lorsque le réseau revient. Une commerçante peut enregistrer sa journée dans un marché sans couverture, un éleveur peut compter sa production à la ferme : rien n'est perdu, rien n'attend le réseau." },
      ]),
      p("Le produit est construit et fonctionnel. Ce qui reste à faire n'est pas du développement mais de la mise sur le marché : validation auprès des premiers utilisateurs réels, mise en place du réseau d'agents de terrain, et activation de la facturation par paiement mobile."),
      spacer(120),
      callout("Pourquoi ce document vous est adressé", [
        "Une banque ou une institution de microfinance ne peut pas évaluer le risque d'une petite entreprise qui ne tient aucun registre. C'est la contrainte structurelle du financement des PME dans la sous-région.",
        "Kaj produit précisément ce registre : un historique daté, cohérent et vérifiable de l'activité réelle d'une entreprise. Le rapprochement entre ce produit et le métier du financement des PME est direct, et c'est sur ce point que votre regard m'est le plus utile.",
      ]),

      // ============================= PROBLÈME
      h1('2. Le problème'),
      p("La quasi-totalité des petites entreprises burkinabè tient ses comptes sur papier, quand elle les tient. Les conséquences sont connues et coûteuses :"),
      bulletRich([{ t: "Les pertes sont invisibles. ", b: true }, { t: "Une boutique perd de l'argent sur des produits périmés sur une étagère que personne ne contrôle. Le propriétaire ne le découvre qu'au moment de jeter la marchandise." }]),
      bulletRich([{ t: "Le vol et l'erreur ne se distinguent pas. ", b: true }, { t: "Sans caisse rapprochée quotidiennement, un écart n'est jamais attribué, et la confiance dans les employés se dégrade sans preuve." }]),
      bulletRich([{ t: "L'accès au crédit est fermé. ", b: true }, { t: "Une entreprise sans historique ne peut pas démontrer sa capacité de remboursement. Le financement se fait alors sur la relation personnelle plutôt que sur les chiffres." }]),
      bulletRich([{ t: "La formalisation est bloquée. ", b: true }, { t: "Sans facture conforme portant un IFU, une petite entreprise ne peut pas travailler avec des clients institutionnels qui, eux, doivent justifier leurs achats." }]),
      p("Les solutions existantes échouent pour deux raisons : elles exigent une connexion permanente, et elles sont conçues pour des entreprises qui disposent déjà d'un comptable."),

      // ============================= SOLUTION
      h1('3. La solution'),
      p("Kaj se présente à l'utilisateur comme un carnet simple : quelques boutons, de gros chiffres, très peu de texte à lire. Derrière cette simplicité, chaque saisie alimente une comptabilité complète."),
      h2("Trois métiers, trois écrans d'accueil"),
      p("L'application s'adapte à l'activité de l'entreprise. Un même téléphone affiche un commerce, une ferme ou une association selon le profil de l'entreprise ouverte."),
      table(
        [2100, 3300, 3626],
        ['Profil', 'Ce qui est suivi', 'Ce que le responsable voit en premier'],
        [
          ['Commerce', "Ventes, stock, dates de péremption, employés", "Recette du jour et valeur du stock qui va périmer"],
          ['Ferme', "Récoltes, troupeaux, cultures, aliments, mortalité", "Production du jour et taux de mortalité"],
          ['Association / paroisse', "Cotisations, offrandes, dépenses, dons", "Ce qui a été reçu et dépensé aujourd'hui"],
        ],
      ),
      spacer(160),
      h2('Fonctions communes à toutes les entreprises'),
      bulletRich([{ t: 'Comptabilité en partie double ', b: true }, { t: "tenue automatiquement à partir des saisies quotidiennes, avec plan de comptes, grand livre et états de synthèse. Aucune écriture n'est jamais supprimée : une correction est une contre-passation, ce qui rend l'historique auditable." }]),
      bulletRich([{ t: 'Facturation ', b: true }, { t: "avec en-tête de l'entreprise, numéro fiscal (IFU), numérotation continue par exercice, suivi des impayés et relances. La facture s'envoie en une touche par WhatsApp." }]),
      bulletRich([{ t: 'Gestion du personnel ', b: true }, { t: "— contrats, présences, salaires — adaptée aussi bien à un employé permanent qu'à un journalier ou un bénévole." }]),
      bulletRich([{ t: 'Rôles et permissions ', b: true }, { t: "— propriétaire, responsable, employé, observateur. Un comptable externe peut consulter sans jamais pouvoir modifier." }]),
      bulletRich([{ t: 'Photographie de documents ', b: true }, { t: "— bons de livraison et ordonnances, avec lecture automatique du texte pour éviter la ressaisie." }]),

      // ============================= AVANCEMENT
      h1("4. État d'avancement"),
      p("Le produit n'est pas une maquette. Les chiffres ci-dessous sont vérifiables dans le dépôt de code."),
      table(
        [4400, 2200, 2426],
        ['Élément', 'Volume', 'État'],
        [
          ['Base de données (PostgreSQL)', '20 migrations', 'En production'],
          ['Logique métier en SQL', '9 758 lignes, 127 fonctions', 'En production'],
          ["Règles de cloisonnement des données", '89 politiques', 'En production'],
          ['Tests automatisés de la base', '203 assertions, 16 suites', 'Tous au vert'],
          ["Tests automatisés de l'application", '205 tests', 'Tous au vert'],
          ['Application', 'Web + Android', 'Déployée'],
        ],
      ),
      spacer(160),
      p("Chaque modification de la base est accompagnée de sa propre suite de tests, exécutée automatiquement à chaque livraison. Le cloisonnement entre entreprises — le fait qu'une entreprise ne puisse jamais lire les données d'une autre — est vérifié par des tests dédiés qui tentent explicitement l'accès et doivent échouer."),

      // ============================= ARCHITECTURE
      h1('5. Architecture technique'),
      p("Cette section s'adresse à un lecteur technique ; elle peut être survolée sans perte."),
      h2("Le choix structurant : l'appareil est la source de vérité"),
      p("L'application écrit d'abord dans une base de données locale sur le téléphone, puis pousse les opérations vers le serveur lorsqu'une connexion est disponible. Chaque opération porte un identifiant unique généré par l'appareil, ce qui rend les renvois inoffensifs : un téléphone qui réessaie après une coupure ne crée jamais de doublon."),
      p("Ce n'est pas un mode dégradé, c'est le mode normal. C'est ce qui différencie l'application des solutions concurrentes, dont la démonstration s'arrête à la première zone sans couverture."),
      h2('Composants'),
      table(
        [2600, 6426],
        ['Couche', 'Technologie et rôle'],
        [
          ['Application', "Flutter — une seule base de code pour le web et Android. Aucune autre plateforme n'est ciblée."],
          ['Base locale', "SQLite sur l'appareil, avec une file d'attente de synchronisation."],
          ['Serveur', "PostgreSQL managé (Supabase). Toute la logique métier — écritures comptables, facturation, paie — est écrite en SQL et exécutée côté serveur."],
          ['Sécurité', "Cloisonnement au niveau des lignes de la base (Row Level Security). Une requête d'une entreprise ne peut techniquement pas retourner les lignes d'une autre, quelle que soit l'application cliente."],
          ['Diffusion', "Cloudflare Workers, avec un déploiement automatisé à chaque livraison."],
        ],
      ),
      spacer(160),
      callout("Le point sur lequel je n'ai pas transigé", [
        "La sécurité multi-entreprises n'est pas implémentée dans l'application mais dans la base de données elle-même. Même si une version de l'application comportait une faille, le serveur refuserait de renvoyer les données d'une autre entreprise.",
        "C'est la seule architecture acceptable pour un produit qui détient les comptes de tiers, et c'est aussi ce qui rendra un audit possible le jour où un partenaire financier l'exigera.",
      ]),

      // ============================= MODÈLE ÉCONOMIQUE
      h1('6. Modèle économique'),
      p("Le principe : l'application est gratuite tant que l'entreprise est petite, et devient payante lorsqu'elle a grandi grâce à elle. Le concurrent réel est un cahier à 500 FCFA qui ne tombe jamais en panne ; une version gratuite réellement utile est la seule façon de gagner le premier mois."),
      table(
        [2600, 6426],
        ['Offre', 'Contenu'],
        [
          ['Gratuit, sans limite de durée', "Un utilisateur, enregistrement illimité, totaux quotidiens et hebdomadaires."],
          ['Payant', "Comptes employés, factures avec IFU, états de synthèse et exports, plusieurs sites."],
          ['Frais de mise en service', "Facturé une fois : visite, saisie des soldes d'ouverture, formation de deux personnes."],
        ],
      ),
      spacer(160),
      h2('Encaissement'),
      bulletRich([{ t: "Par paiement mobile ", b: true }, { t: "(Orange Money, Moov), via un agrégateur agréé, avec reversement sur un compte bancaire d'entreprise." }]),
      bulletRich([{ t: "Vendu par périodes prépayées ", b: true }, { t: "de 3, 6 ou 12 mois plutôt qu'en abonnement mensuel : le paiement mobile fonctionne par validation à l'initiative du client, et chaque échéance mensuelle serait une occasion de résiliation." }]),
      bulletRich([{ t: "La lecture reste toujours gratuite, ", b: true }, { t: "y compris après expiration. Une entreprise privée d'accès à son propre historique ne reviendra jamais, et le dira. L'expiration bloque l'écriture des fonctions payantes, jamais la consultation." }]),
      bulletRich([{ t: "Aucun agent ne collecte d'argent. ", b: true }, { t: "Le client paie directement l'agrégateur depuis son propre téléphone ; l'agent perçoit ensuite une commission. Le risque de détournement est supprimé par construction plutôt que surveillé." }]),
      p("Ce que le modèle exclut délibérément : la publicité, et surtout la revente de données. L'architecture entière repose sur le fait qu'aucune entreprise ne voit les comptes d'une autre ; le jour où cette donnée deviendrait une ligne de revenu, le produit vendu n'existerait plus."),

      // ============================= MARCHÉ
      h1('7. Stratégie de déploiement'),
      p("Le déploiement ne repose pas sur la publicité mais sur des personnes et sur la densité."),
      numbered("Concentrer sur un seul quartier de Ouagadougou jusqu'à saturation. Les voisins se parlent, et les visites de soutien doivent rester faisables à pied ou en deux-roues. Un client à Bobo-Dioulasso au deuxième mois est un client qu'on ne peut pas servir."),
      numbered("Recruter des agents de terrain — étudiants en comptabilité, anciens agents de crédit, gérants de cybercafé — qui installent, saisissent les soldes d'ouverture, forment deux personnes par entreprise et assurent le premier niveau de support. C'est le modèle qui a permis au paiement mobile d'atteindre chaque village de la sous-région."),
      numbered("Passer par les institutions qui détiennent déjà la confiance : institutions de microfinance, coopératives, associations professionnelles, cabinets comptables. Une seule conversation y vaut plusieurs centaines de clients."),
      numbered("Vendre une douleur précise, jamais « la comptabilité ». Personne ne se lève le matin en souhaitant tenir des livres. La commerçante veut cesser de perdre de l'argent sur des produits périmés ; l'éleveur veut être prévenu d'une mortalité anormale avant que la production ne chute."),
      numbered("Démontrer systématiquement le mode hors ligne, téléphone en mode avion. C'est l'avantage le plus difficile à copier, et celui que les concurrents ne peuvent pas montrer."),

      // ============================= INTÉRÊT BANCAIRE
      h1("8. Intérêt pour un établissement financier"),
      p("C'est le point sur lequel votre expérience m'est la plus précieuse, et je le soumets à votre jugement plutôt que de le présenter comme acquis."),
      h2("Le problème que Kaj résout pour un prêteur"),
      p("L'obstacle au financement des petites entreprises n'est pas seulement le risque : c'est l'impossibilité de le mesurer. Un dossier de crédit repose sur des déclarations invérifiables, et l'analyse coûte plus cher que la marge du prêt."),
      p("Une entreprise qui utilise Kaj depuis six mois dispose d'un historique daté et cohérent : recettes quotidiennes, rotation du stock, régularité de l'activité, créances clients, charges de personnel. Ce sont exactement les éléments qu'un comité de crédit reconstitue aujourd'hui à la main, quand il le peut."),
      h2("Ce que cela peut représenter concrètement"),
      bulletRich([{ t: "Réduction du coût d'instruction ", b: true }, { t: "des petits dossiers, aujourd'hui difficilement rentables." }]),
      bulletRich([{ t: "Élargissement de la base de clients finançables ", b: true }, { t: "à des entreprises réelles mais actuellement indocumentées." }]),
      bulletRich([{ t: "Suivi après décaissement ", b: true }, { t: "— l'activité de l'emprunteur reste visible pendant la vie du prêt, avec son consentement." }]),
      bulletRich([{ t: "Canal de distribution ", b: true }, { t: "— l'établissement a une raison commerciale de recommander l'outil à ses clients, ce qui résout simultanément mon problème d'acquisition." }]),
      spacer(120),
      callout("Une limite que je pose d'emblée", [
        "Les données appartiennent à l'entreprise, pas à Kaj. Aucun partage avec un tiers, y compris un partenaire financier, ne peut avoir lieu sans le consentement explicite de l'entreprise concernée, donné dans l'application et révocable.",
        "Ce n'est pas seulement une position éthique : c'est la condition de survie du produit. Une plateforme soupçonnée de transmettre les comptes de ses clients perd ses clients.",
      ]),

      // ============================= FEUILLE DE ROUTE
      h1('9. Feuille de route sur douze mois'),
      table(
        [1500, 3400, 4126],
        ['Période', 'Objectif', 'Ce qui est prouvé à la fin'],
        [
          ['Mois 0–1', "Constitution de la société", "RCCM, IFU, compte bancaire et compte marchand opérationnels"],
          ['Mois 1–3', "Trois entreprises pilotes, gratuites", "Elles enregistrent encore seules au trentième jour"],
          ['Mois 3–6', "Premier agent, premières institutions", "Dix entreprises signées sans mon intervention"],
          ['Mois 6–9', "Activation du paiement", "Trente entreprises ont payé sans assistance"],
          ['Mois 9–12', "Saturation d'un quartier", "Les recommandations dépassent la prospection"],
        ],
      ),

      // ============================= RISQUES
      h1('10. Ce qui reste à faire et ce qui peut échouer'),
      p("Je préfère présenter ces points moi-même plutôt que vous laisser les découvrir."),
      h2("Travaux techniques restants"),
      bulletRich([{ t: "Aucun utilisateur réel à ce jour. ", b: true }, { t: "C'est la première chose à corriger et elle réordonnera probablement le reste de cette liste." }]),
      bulletRich([{ t: "L'application n'existe qu'en français. ", b: true }, { t: "Une part importante du marché lit le français avec difficulté. La traduction des écrans quotidiens en mooré et en dioula est le chantier le plus rentable qui reste." }]),
      bulletRich([{ t: "L'application Android n'a jamais été exécutée sur un téléphone physique ", b: true }, { t: "dans son environnement de développement actuel. Le lecteur de codes-barres et la lecture de documents restent donc à confirmer sur matériel réel." }]),
      bulletRich([{ t: "La couche de facturation des abonnements reste à construire. ", b: true }, { t: "Elle est spécifiée mais non développée." }]),
      h2('Risques principaux'),
      bulletRich([{ t: "Adoption. ", b: true }, { t: "Changer une habitude vieille de vingt ans est plus difficile que d'écrire un logiciel. C'est le risque numéro un et il ne se résout pas par la technique, mais par la présence sur le terrain." }]),
      bulletRich([{ t: "Alphabétisation et aisance numérique. ", b: true }, { t: "Atténué par la réduction du texte à l'écran, la formation de deux personnes par entreprise — souvent un jeune proche qui manie le téléphone — et les langues locales." }]),
      bulletRich([{ t: "Capacité à payer. ", b: true }, { t: "Le prix doit s'ancrer sur ce que l'entreprise paie déjà à un comptable, et non sur les tarifs pratiqués ailleurs. Cette validation fait partie de la phase pilote." }]),
      bulletRich([{ t: "Dépendance à une seule personne. ", b: true }, { t: "Le produit repose aujourd'hui entièrement sur moi. C'est précisément l'une des raisons de ce document." }]),

      // ============================= DEMANDE
      h1('11. Ce que je recherche'),
      p("Je ne cherche pas d'abord un financement. Je cherche un regard expérimenté sur les deux points où je suis le plus exposé : la crédibilité auprès d'un établissement financier, et la conduite d'un projet qui va passer d'une personne à une équipe."),
      p("Plusieurs formes de participation seraient utiles, séparément ou ensemble :"),
      bulletRich([{ t: "Conseil et cadrage. ", b: true }, { t: "Un avis régulier sur les priorités, et une lecture critique de ce dossier avant qu'il ne soit présenté à un tiers." }]),
      bulletRich([{ t: "Mise en relation. ", b: true }, { t: "Introductions auprès d'institutions de microfinance, de coopératives ou d'associations professionnelles." }]),
      bulletRich([{ t: "Validation du cas d'usage bancaire. ", b: true }, { t: "Confirmer, ou infirmer, que l'historique produit par l'application répond réellement à un besoin d'un comité de crédit." }]),
      bulletRich([{ t: "Participation au projet. ", b: true }, { t: "Sous la forme qui vous conviendrait — accompagnement, gouvernance, ou association au capital — et que je souhaite discuter avec vous." }]),
      spacer(160),
      p("Je suis disponible pour une démonstration à tout moment, y compris sur un téléphone en mode avion, ce qui reste la façon la plus rapide de comprendre ce qui distingue ce produit.", { italics: true }),

      spacer(300),
      new Paragraph({
        spacing: { before: 200 },
        border: { top: { style: BorderStyle.SINGLE, size: 6, color: RULE, space: 8 } },
        children: [new TextRun({
          text: "Les chiffres relatifs au code et aux tests sont vérifiables dans le dépôt du projet. Les éléments juridiques, fiscaux et tarifaires cités doivent être confirmés auprès du CEFORE, d'un expert-comptable et des agrégateurs de paiement concernés ; ils sont indiqués ici comme hypothèses de travail.",
          font: 'Calibri', size: 17, color: GREY, italics: true,
        })],
      }),
    ],
  }],
});

Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync('Kaj_Dossier_Presentation.docx', buf);
  console.log('written', (buf.length / 1024).toFixed(0), 'KB');
});
