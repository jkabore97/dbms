// The privacy policy and the terms of use as plain pages, readable with no
// JavaScript: Google's app verification (the « Mara » name on the Google
// sign-in screen) reads these addresses without running the Flutter app.
//
// The same words as the app's own screens (app/lib/features/account/
// legal_screens.dart); app/test/legal_pages_test.dart fails if the two drift
// apart. A paragraph starting with « # » is a heading.

export const PRIVACY = {
  title: "Politique de confidentialité",
  blocks: [
    "Mara enregistre les informations que vous saisissez pour faire fonctionner votre activité : ventes, dépenses, membres, produits, photos de pièces justificatives, et les personnes de votre équipe.",
    "# Ce que nous collectons",
    "Votre nom et votre numéro de téléphone, les données que vous entrez dans l'application, et les photos que vous prenez pour vos reçus et livraisons.",
    "# Connexion avec Google",
    "Si vous vous connectez avec Google, nous recevons de Google votre nom, votre adresse e-mail et votre photo de profil. Ils servent uniquement à vous identifier et à afficher votre nom dans l'application. Nous ne lisons rien d'autre de votre compte Google et ne transmettons ces informations à personne.",
    "# Comment elles sont utilisées",
    "Uniquement pour vous fournir le service : afficher vos livres, vos rapports et vos stocks à vous et aux personnes que vous autorisez. Nous ne vendons pas vos données et ne les partageons pas à des fins publicitaires.",
    "# Où elles sont stockées",
    "Sur des serveurs sécurisés (Supabase et Cloudflare). Chaque activité ne voit que ses propres données ; l'isolement entre activités est appliqué par le serveur.",
    "# Devenir livreur",
    "Pour devenir livreur, vous envoyez un selfie et la photo de votre pièce d'identité (à moto ou en voiture, aussi votre permis). Ces photos sont gardées à part, en privé : seule l'équipe Mara qui examine les demandes peut les voir, jamais les boutiques, les clients ni la rue. Si votre demande est refusée et que vous ne la renvoyez pas, elles ne sont plus jamais montrées après 30 jours, et sont effacées la fois suivante où la liste des livreurs est ouverte (par l'équipe Mara, ou par vous sur « Devenir livreur »). Il en va de même, sans attendre, d'une photo remplacée par une nouvelle et, après 30 jours sans suite, d'une demande commencée puis laissée. Si vous êtes accepté, elles sont gardées tant que vous êtes livreur ; votre compte supprimé, elles ne sont plus montrées et sont effacées de la même façon.",
    "# Vos droits",
    "Vous pouvez demander la correction ou la suppression de vos données en contactant le support. Vous pouvez aussi télécharger vos données et supprimer votre compte vous-même, depuis Mon profil › Mes données : vos adresses, vos favoris et vos signalements partent avec lui ; vos commandes restent chez les boutiques, au nom de « Client supprimé », sans votre numéro ni votre adresse (une vente déjà inscrite dans leurs comptes y reste telle quelle). La suppression d'une activité efface ses données de façon définitive.",
    "# Contact",
    "Pour toute question sur vos données, contactez le support depuis l'écran Compte › Aide.",
  ],
};

export const TERMS = {
  title: "Conditions d'utilisation",
  blocks: [
    "En utilisant Mara, vous acceptez ces conditions.",
    "# Votre compte",
    "Vous êtes responsable de l'exactitude des informations que vous saisissez et de la confidentialité de votre code (PIN). Ne partagez pas votre accès avec une personne qui ne devrait pas voir vos données.",
    "# Utilisation correcte",
    "Mara est un outil de gestion pour votre activité. N'utilisez pas l'application pour enregistrer des activités illégales ou pour nuire à autrui.",
    "# Disponibilité",
    "Nous faisons de notre mieux pour que le service reste disponible, mais nous ne pouvons pas le garantir sans interruption. L'application continue de fonctionner hors ligne et synchronise dès que la connexion revient.",
    "# Responsabilité",
    "Mara vous aide à tenir vos comptes, mais la responsabilité finale de vos décisions commerciales et de vos obligations légales vous revient.",
    "# Modifications",
    "Ces conditions peuvent évoluer. Les changements importants vous seront signalés dans l'application.",
  ],
};

const PAGES = { "/confidentialite": PRIVACY, "/conditions": TERMS };

/** The page for [pathname], or null when it is not one of the two. */
export function legalPage(pathname) {
  const doc = PAGES[pathname.replace(/\/$/, "")];
  if (!doc) return null;
  const body = doc.blocks
    .map((b) => (b.startsWith("# ") ? `<h2>${escape(b.slice(2))}</h2>` : `<p>${escape(b)}</p>`))
    .join("\n");
  const html = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(doc.title)} · Mara</title>
<meta name="description" content="${escape(doc.title)} de Mara — Au Service du Peuple.">
<link rel="icon" type="image/png" href="/favicon.png">
<style>
  :root { color-scheme: light; }
  body { margin: 0; background: #F4F2EE; color: #0E0D0C; font: 16px/1.6 system-ui, sans-serif; }
  header { background: #3B3A38; color: #F4F2EE; padding: 18px 20px; }
  header a { color: #F4F2EE; text-decoration: none; font-weight: 800; letter-spacing: 0.02em; }
  main { max-width: 720px; margin: 0 auto; padding: 24px 20px 48px; }
  h1 { font-size: 26px; margin: 0 0 16px; }
  h2 { font-size: 18px; margin: 24px 0 6px; }
  footer { max-width: 720px; margin: 0 auto; padding: 0 20px 32px; color: #6B6660; font-size: 14px; }
  footer a { color: #8B5A3C; }
</style>
</head>
<body>
<header><a href="/">Mara — Au Service du Peuple</a></header>
<main>
<h1>${escape(doc.title)}</h1>
${body}
</main>
<footer>
<a href="/">Ouvrir Mara</a> · <a href="/confidentialite">Politique de confidentialité</a> · <a href="/conditions">Conditions d'utilisation</a>
</footer>
</body>
</html>`;
  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=3600",
    },
  });
}

function escape(text) {
  return String(text).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
}
