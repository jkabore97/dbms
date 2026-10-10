// /aide — « Aide Mara », the page the App Store's Support URL points to:
// how to reach the people who run Mara, readable with no JavaScript, in
// the legal pages' look (legal.js's sitePage).
//
// The e-mail, the WhatsApp number and the hours are the platform's own
// (migration 126, Réglages › « Aide aux clients »), read live through
// support_contacts() — kept a minute in this Worker so a burst of visits
// asks Supabase once. Supabase down, or 126 not applied yet: the e-mail and
// the hours as installed, and no WhatsApp button (no number is never a
// wrong number). Never a 500.
//
// The questions are the app's own (app/lib/features/account/
// legal_screens.dart, FaqScreen), French with the English under each;
// app/test/legal_pages_test.dart fails if they drift apart.

import { escape, sitePage } from "./legal.js";

export const DEFAULT_CONTACTS = Object.freeze({
  email: "hello@kaj-consulting.com",
  whatsapp: null,
  hours: "24 h/24, 7 j/7",
});

// [French question, French answer, English question, English answer].
export const FAQ = [
  [
    "L'application fonctionne-t-elle sans internet ?",
    "Oui. Vous pouvez enregistrer des ventes et des dépenses hors ligne ; elles sont envoyées au serveur dès que la connexion revient. Certains écrans (rapports, historique) ont besoin de la connexion.",
    "Does the app work without internet?",
    "Yes. You can record sales and expenses offline; they are sent to the server as soon as the connection is back. Some screens (reports, history) need the connection.",
  ],
  [
    "Comment ajouter un employé ?",
    "Dans Compte › Administration › Personnel, puis invitez la personne. Vous décidez ce que chacun peut voir et modifier.",
    "How do I add an employee?",
    "In Account › Administration › Staff, then invite the person. You decide what each one can see and change.",
  ],
  [
    "Comment recevoir un paiement Wave ?",
    "Renseignez votre numéro Wave dans Paramètres, puis choisissez « Wave » au moment de la vente : le client scanne le QR et paie.",
    "How do I receive a Wave payment?",
    "Enter your Wave number in Settings, then choose “Wave” at the time of the sale: the customer scans the QR code and pays.",
  ],
  [
    "Comment imprimer ou envoyer une facture ?",
    "Ouvrez la facture : l'icône imprimante lance l'impression, et « Envoyer » la partage en image (WhatsApp ou autre). Le propriétaire peut aussi la corriger tant que rien n'a été payé.",
    "How do I print or send an invoice?",
    "Open the invoice: the printer icon prints it, and “Send” shares it as an image (WhatsApp or another app). The owner can also correct it as long as nothing has been paid.",
  ],
  [
    "J'ai oublié mon code (PIN).",
    "Reconnectez-vous avec votre mot de passe pour définir un nouveau code.",
    "I forgot my code (PIN).",
    "Sign in again with your password to set a new code.",
  ],
  [
    "Comment contacter quelqu'un ?",
    "Depuis Compte › Aide (ou Mon profil › Aide) : par e-mail, ou sur WhatsApp quand le bouton est affiché.",
    "How do I reach someone?",
    "From Account › Help (or My profile › Help): by e-mail, or on WhatsApp when the button is shown.",
  ],
];

const GREETING = "Bonjour, j'ai besoin d'aide avec Mara.";

/** What support_contacts() said, each value checked; the defaults for the rest. */
export function contactsFrom(value) {
  const v = value && typeof value === "object" && !Array.isArray(value) ? value : {};
  const email = typeof v.email === "string" && /^[^@\s]+@[^@\s]+\.[^@\s.]+$/.test(v.email.trim())
    ? v.email.trim() : DEFAULT_CONTACTS.email;
  const whatsapp = typeof v.whatsapp === "string" && /^\d{8,15}$/.test(v.whatsapp) ? v.whatsapp : null;
  const hours = typeof v.hours === "string" && v.hours.trim() !== "" && v.hours.length <= 60
    ? v.hours.trim() : DEFAULT_CONTACTS.hours;
  return { email, whatsapp, hours };
}

/** The page, for these contacts. */
export function helpHtml(contacts) {
  const { email, whatsapp, hours } = contactsFrom(contacts);
  const hoursEn = hours === DEFAULT_CONTACTS.hours ? "24/7" : hours;
  const wa = whatsapp
    ? `<a class="button wa" href="https://wa.me/${whatsapp}?text=${encodeURIComponent(GREETING)}" rel="noopener">Écrire sur WhatsApp</a>\n`
    : "";
  const faq = FAQ.map(([q, a, qEn, aEn]) => `<h3>${escape(q)}</h3>
<p>${escape(a)}</p>
<p class="en" lang="en"><b>${escape(qEn)}</b> ${escape(aEn)}</p>`).join("\n");
  const main = `<h1>Aide Mara</h1>
<p class="lead">Une question, un souci ? Nous répondons ${escape(hours)}.</p>
<p class="en" lang="en">A question, a problem? We answer ${escape(hoursEn)}.</p>
<div class="contact">
${wa}<a class="button mail" href="mailto:${escape(email)}">Écrire à ${escape(email)}</a>
</div>
<p class="en" lang="en">${whatsapp ? "Write to us on WhatsApp or by e-mail." : "Write to us by e-mail."}</p>
<h2>Questions fréquentes</h2>
${faq}
<h2>Vos données</h2>
<p><a href="/confidentialite">Politique de confidentialité</a> · <a href="/conditions">Conditions d'utilisation</a> · <a href="/supprimer-mon-compte">Supprimer votre compte</a></p>
<p class="en" lang="en">Privacy policy, terms of use, deleting your account.</p>
<p class="editor">Mara est édité par KAJ Consulting LLC.</p>`;
  const title = "Aide Mara";
  const description = `Une question, un souci ? L'équipe Mara répond ${hours}, par e-mail${whatsapp ? " et sur WhatsApp" : ""}.`;
  const meta = {
    "og:title": title,
    "og:description": description,
    "og:url": "https://marakaj.com/aide",
    "og:type": "website",
    "og:site_name": "Mara",
  };
  const head = Object.entries(meta)
    .map(([k, v]) => `<meta property="${k}" content="${escape(v)}">\n`).join("")
    + `<link rel="canonical" href="https://marakaj.com/aide">\n`;
  const style = `  .lead { font-size: 19px; margin: 0 0 2px; }
  .en { color: #6B6660; font-size: 14px; margin-top: -6px; }
  .contact { display: flex; flex-wrap: wrap; gap: 12px; margin: 20px 0 8px; }
  .button { display: inline-block; padding: 12px 18px; border-radius: 12px; font-weight: 700; text-decoration: none; overflow-wrap: anywhere; }
  .wa { background: #1F7A4D; color: #FFFFFF; }
  .mail { background: #3B3A38; color: #F4F2EE; }
  h3 { font-size: 16px; margin: 18px 0 4px; }
  main a { color: #8B5A3C; }
  main .button { color: #FFFFFF; }
  .editor { margin-top: 28px; color: #6B6660; font-size: 14px; }
`;
  return sitePage({ title, description, main, head, style });
}

export function helpPage(contacts) {
  return new Response(helpHtml(contacts), {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      // A changed number shows within a minute or so.
      "Cache-Control": "public, max-age=60",
    },
  });
}

// support_contacts(), kept a minute.
let memo = null;

/** Forgets what was kept (tests). */
export function forgetSupportContacts() {
  memo = null;
}

/** The contacts, live, else the defaults — never throws. */
export async function supportContacts(env, now = Date.now()) {
  if (memo && now - memo.at < 60_000) return memo.value;
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return DEFAULT_CONTACTS;
  try {
    const response = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/support_contacts`, {
      method: "POST",
      headers: {
        apikey: env.SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_PUBLISHABLE_KEY}`,
        "Content-Type": "application/json",
      },
      body: "{}",
      signal: AbortSignal.timeout(3000),
    });
    if (!response.ok) return DEFAULT_CONTACTS;
    const value = contactsFrom(await response.json());
    memo = { at: now, value };
    return value;
  } catch (_) {
    return DEFAULT_CONTACTS;
  }
}
