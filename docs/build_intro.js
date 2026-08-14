const fs = require('fs');
const {
  Document, Packer, Paragraph, TextRun, AlignmentType, BorderStyle,
  LevelFormat, convertInchesToTwip,
} = require('docx');
const {
  W, TEAL, TEAL_DARK, GREY, RULE,
  p, pRich, h1, h2, bulletRich, table, callout, spacer,
} = require('./kit');

// A short document whose only job is to make the project understood.
// The detailed dossier follows later, once it is.

const doc = new Document({
  creator: 'Kaj',
  title: 'Kaj — Comprendre le projet',
  description: "Présentation courte du projet Kaj",
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
    properties: { page: { margin: { top: 1300, bottom: 1300, left: 1440, right: 1440 } } },
    children: [

      // ---------------------------------------------------- en-tête compact
      new Paragraph({
        spacing: { after: 40 },
        children: [new TextRun({
          text: 'KAJ', font: 'Cambria', size: 56, bold: true, color: TEAL_DARK,
        })],
      }),
      new Paragraph({
        spacing: { after: 340 },
        border: { bottom: { style: BorderStyle.SINGLE, size: 12, color: TEAL, space: 8 } },
        children: [new TextRun({
          text: 'Comprendre le projet en quelques minutes',
          font: 'Cambria', size: 24, color: GREY,
        })],
      }),

      // ---------------------------------------------------- 1
      h1('En une phrase'),
      p("Kaj remplace le cahier de comptes des petites entreprises burkinabè par une application téléphone qui s'utilise en quelques touches par jour, qui fonctionne même sans réseau, et qui transforme ces saisies en une véritable comptabilité.", { size: 23 }),

      // ---------------------------------------------------- 2
      h1('Le problème, tel qu’il se voit sur le terrain'),
      p("Prenons une boutique de quartier à Ouagadougou. La propriétaire vend toute la journée. Le soir, l'argent est dans la caisse et rien n'est écrit, ou bien quelques lignes dans un cahier."),
      p('Trois conséquences, toutes coûteuses :'),
      bulletRich([{ t: "Elle ne sait pas si elle gagne de l'argent. ", b: true }, { t: "Elle sait ce qu'il y a dans la caisse, ce qui n'est pas la même chose." }]),
      bulletRich([{ t: "Elle perd de la marchandise sans le voir. ", b: true }, { t: "Des produits atteignent leur date de péremption sur une étagère que personne ne contrôle ; elle le découvre en les jetant." }]),
      bulletRich([{ t: "Elle ne peut rien démontrer. ", b: true }, { t: "Le jour où elle a besoin d'un crédit pour agrandir, elle n'a aucun historique à présenter." }]),
      p("La même situation se retrouve chez un éleveur qui ne sait pas que sa mortalité augmente avant que la production ne chute, et dans une association qui ne peut pas montrer à ses membres où est passé l'argent."),

      // ---------------------------------------------------- 3
      h1('Ce que fait l’application'),
      p("Une journée type dans cette boutique :"),
      bulletRich([{ t: "Le matin, ", b: true }, { t: "elle ouvre l'application et voit ce qui va périmer cette semaine." }]),
      bulletRich([{ t: "Pendant la journée, ", b: true }, { t: "elle enregistre chaque vente en trois touches. Un employé peut le faire aussi, avec son propre accès." }]),
      bulletRich([{ t: "Le soir, ", b: true }, { t: "elle compte la caisse et saisit le montant. L'application lui dit immédiatement si le compte tombe juste, et de combien il s'écarte sinon." }]),
      bulletRich([{ t: "À la fin du mois, ", b: true }, { t: "il n'y a rien à rattraper : chaque saisie a déjà produit son écriture comptable." }]),
      spacer(60),
      p("C'est le point important. L'utilisateur voit un carnet très simple — de gros chiffres, peu de texte, quelques boutons. Derrière, l'application tient une comptabilité en partie double complète, produit des factures conformes avec le numéro IFU de l'entreprise, et suit le personnel et les salaires."),
      spacer(140),
      h2("Une application, trois métiers"),
      p("L'écran d'accueil s'adapte à l'activité de l'entreprise."),
      table(
        [2500, 6526],
        ['Type d’entreprise', 'Ce que le responsable voit en premier'],
        [
          ['Commerce', "La recette du jour, et la valeur du stock qui va bientôt périmer"],
          ['Ferme', "La production du jour, et le taux de mortalité du troupeau"],
          ['Association, paroisse', "Ce qui a été reçu et ce qui a été dépensé aujourd'hui"],
        ],
      ),

      // ---------------------------------------------------- 4
      h1('Ce qui la distingue vraiment'),
      p("Les solutions de gestion qui existent déjà exigent une connexion internet permanente. Or c'est précisément ce qui manque là où sont les clients : dans un marché, dans une boutique de quartier, dans une ferme à quarante kilomètres de la ville."),
      pRich([
        { t: "Kaj écrit d'abord sur le téléphone, puis se synchronise plus tard, quand le réseau revient. ", b: true },
        { t: "Ce n'est pas un mode de secours : c'est le fonctionnement normal. L'application ne s'arrête jamais d'être utilisable, et aucune saisie n'est perdue." },
      ]),
      spacer(60),
      callout("La démonstration la plus rapide", [
        "Mettre le téléphone en mode avion, puis enregistrer une vente et clôturer la journée. Tout fonctionne. En remettant le réseau, les données remontent seules.",
        "C'est en une minute la différence entre ce produit et tous ceux qui se présentent comme des concurrents.",
      ]),

      // ---------------------------------------------------- 5
      h1('Où en est le projet aujourd’hui'),
      p("L'application est construite, testée et déployée. Elle n'est pas au stade de la maquette : la base de données, la comptabilité, la facturation, la gestion du personnel et le fonctionnement hors ligne sont terminés et vérifiés automatiquement à chaque modification."),
      p("Ce qui reste n'est pas du développement, c'est de la mise sur le marché. Aucune entreprise réelle ne l'utilise encore, et c'est la prochaine étape : la mettre entre les mains de trois commerçants et les regarder s'en servir."),

      // ---------------------------------------------------- 6
      h1('Pourquoi j’aimerais en parler avec toi'),
      p("Une petite entreprise qui tient ses comptes pendant six mois devient une entreprise qu'une banque ou une institution de microfinance peut évaluer. Aujourd'hui, l'obstacle au financement de ces entreprises n'est pas seulement le risque : c'est l'impossibilité de le mesurer, faute du moindre historique."),
      p("Je pense qu'il y a là un rapprochement évident entre ce que produit cette application et le métier du financement des PME — mais c'est une intuition, pas une certitude, et c'est exactement le point sur lequel ton expérience vaut plus que la mienne."),
      spacer(80),
      p("J'ai préparé un dossier complet — architecture technique, modèle économique, feuille de route sur douze mois, risques — que je te transmettrai volontiers. Ce document-ci n'a qu'un seul objectif : que tu voies clairement de quoi il s'agit. Le reste viendra ensuite, et une démonstration de dix minutes sur mon téléphone vaudra mieux que les deux.", { italics: true }),

      spacer(240),
      new Paragraph({
        spacing: { before: 160 },
        border: { top: { style: BorderStyle.SINGLE, size: 6, color: RULE, space: 8 } },
        children: [new TextRun({
          text: "Document de présentation — version courte",
          font: 'Calibri', size: 17, color: GREY, italics: true,
        })],
      }),
    ],
  }],
});

Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync('Kaj_Comprendre_le_projet.docx', buf);
  console.log('written', (buf.length / 1024).toFixed(0), 'KB');
});
