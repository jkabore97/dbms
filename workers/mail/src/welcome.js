// The welcome e-mail itself: subject, HTML and plain text, in French or
// English. Pure — no network, no env — so the tests and the preview
// script render exactly what Resend receives.
//
// Written for mail clients, not browsers: tables for layout, every style
// inline, one column that is the phone's width and stops at 560 px, no web
// font, no background image, no script. Gmail (web and app), Outlook
// (desktop's Word engine included) and Apple Mail draw it the same. The
// logo is the site's own PNG at an absolute address (the web build copies
// app/web/brand/ to https://marakaj.com/brand/), with its words in alt.

export const BRAND = {
  graphite: "#3B3A38",
  caramel: "#C59A6A",
  paper: "#F4F2EE",
  ink: "#2A2927",
  muted: "#6E6B66",
  line: "#E4E0D8",
};

export const LINKS = {
  app: "https://marakaj.com",
  play: "https://play.google.com/store/apps/details?id=bf.kaj.app",
  privacy: "https://marakaj.com/confidentialite",
  logo: "https://marakaj.com/brand/mara-stacked.png",
};

const COPY = {
  fr: {
    subject: (n) => (n ? `Bienvenue sur Mara, ${n} !` : "Bienvenue sur Mara !"),
    hello: (n) => (n ? `Bienvenue sur Mara, ${n} !` : "Bienvenue sur Mara !"),
    preheader: "Trois pas pour commencer — votre vitrine vous attend.",
    lead: "Votre compte est prêt. Trois pas pour commencer :",
    steps: [
      ["🛍️", "Ajoutez vos articles"],
      ["🏪", "Ouvrez votre vitrine"],
      ["💰", "Faites votre première vente"],
    ],
    button: "Ouvrir Mara",
    play: "Sur Android : Mara sur Google Play",
    question: "Une question ? Répondez simplement à cet e-mail.",
    privacy: "Confidentialité",
    signature: "Mara — Au Service du Peuple · KAJ Consulting LLC",
    logoAlt: "Mara",
    // Said when the language is not known: the person may not read French.
    english: "Welcome to Mara! Prefer English? Reply to this e-mail and we will help.",
  },
  en: {
    subject: (n) => (n ? `Welcome to Mara, ${n}!` : "Welcome to Mara!"),
    hello: (n) => (n ? `Welcome to Mara, ${n}!` : "Welcome to Mara!"),
    preheader: "Three steps to get started — your shop window is waiting.",
    lead: "Your account is ready. Three steps to get started:",
    steps: [
      ["🛍️", "Add your items"],
      ["🏪", "Open your shop window"],
      ["💰", "Make your first sale"],
    ],
    button: "Open Mara",
    play: "On Android: Mara on Google Play",
    question: "A question? Just reply to this e-mail.",
    privacy: "Privacy",
    signature: "Mara — Au Service du Peuple · KAJ Consulting LLC",
    logoAlt: "Mara",
    english: null,
  },
};

/// A first name fit for a subject line and a page: one line, no markup
/// characters doing anything, 40 characters at most.
export function cleanName(name) {
  return String(name ?? "")
    .replace(/[\u0000-\u001f\u007f<>]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 40)
    .trim();
}

export function escapeHtml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/// { subject, html, text } for one person. `lang` is 'fr', 'en' or
/// unknown (null): unknown is French with one English line.
export function welcomeEmail({ firstName, lang } = {}) {
  const known = lang === "fr" || lang === "en";
  const c = COPY[lang === "en" ? "en" : "fr"];
  const name = cleanName(firstName);
  const english = known ? null : COPY.fr.english;
  return {
    subject: c.subject(name),
    html: html(c, name, english, lang === "en" ? "en" : "fr"),
    text: text(c, name, english),
  };
}

function html(c, name, english, htmlLang) {
  const b = BRAND;
  const font = "font-family:Helvetica,Arial,sans-serif;";
  const steps = c.steps
    .map(
      ([icon, label], i) => `
              <tr>
                <td width="56" valign="middle" style="padding:8px 0;">
                  <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
                    <td width="44" height="44" align="center" valign="middle" bgcolor="${b.paper}" style="width:44px;height:44px;border-radius:22px;background:${b.paper};font-size:22px;line-height:44px;">${icon}</td>
                  </tr></table>
                </td>
                <td valign="middle" style="padding:8px 0;${font}font-size:17px;line-height:24px;color:${b.ink};">
                  <span style="color:${b.caramel};font-weight:bold;">${i + 1}.</span>&nbsp; ${escapeHtml(label)}
                </td>
              </tr>`,
    )
    .join("");
  const englishRow = english
    ? `
          <tr>
            <td style="padding:0 32px 24px 32px;${font}font-size:14px;line-height:20px;color:${b.muted};" lang="en">${escapeHtml(english)}</td>
          </tr>`
    : "";
  return `<!DOCTYPE html>
<html lang="${htmlLang}" xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="x-apple-disable-message-reformatting">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>${escapeHtml(c.subject(name))}</title>
</head>
<body style="margin:0;padding:0;background:${b.paper};" bgcolor="${b.paper}">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:${b.paper};">${escapeHtml(c.preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${b.paper}" style="background:${b.paper};">
  <tr>
    <td align="center" style="padding:16px 12px;">
      <!--[if mso]><table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0"><tr><td><![endif]-->
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;width:100%;background:#FFFFFF;border-radius:16px;overflow:hidden;" bgcolor="#FFFFFF">
        <tr>
          <td align="center" bgcolor="${b.graphite}" style="background:${b.graphite};padding:32px 24px 24px 24px;">
            <a href="${LINKS.app}" style="text-decoration:none;"><img src="${LINKS.logo}" width="144" height="180" alt="${escapeHtml(c.logoAlt)}" style="display:block;width:144px;height:180px;border:0;outline:none;${font}font-size:32px;color:${b.paper};"></a>
          </td>
        </tr>
        <tr>
          <td height="6" bgcolor="${b.caramel}" style="background:${b.caramel};height:6px;line-height:6px;font-size:0;">&nbsp;</td>
        </tr>
        <tr>
          <td style="padding:32px 32px 8px 32px;${font}font-size:26px;line-height:32px;font-weight:bold;color:${b.graphite};">${escapeHtml(c.hello(name))}</td>
        </tr>
        <tr>
          <td style="padding:0 32px 12px 32px;${font}font-size:16px;line-height:24px;color:${b.muted};">${escapeHtml(c.lead)}</td>
        </tr>
        <tr>
          <td style="padding:0 32px 16px 32px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">${steps}
            </table>
          </td>
        </tr>
        <tr>
          <td align="center" style="padding:8px 32px 20px 32px;">
            <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width:320px;">
              <tr>
                <td align="center" bgcolor="${b.caramel}" style="background:${b.caramel};border-radius:12px;">
                  <a href="${LINKS.app}" style="display:block;padding:16px 24px;${font}font-size:18px;line-height:24px;font-weight:bold;color:#FFFFFF;text-decoration:none;border-radius:12px;">${escapeHtml(c.button)}</a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td align="center" style="padding:0 32px 28px 32px;${font}font-size:15px;line-height:22px;">
            <a href="${LINKS.play}" style="color:${b.graphite};text-decoration:underline;">▶ ${escapeHtml(c.play)}</a>
          </td>
        </tr>${englishRow}
        <tr>
          <td style="padding:0 32px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td height="1" bgcolor="${b.line}" style="background:${b.line};height:1px;line-height:1px;font-size:0;">&nbsp;</td></tr></table></td>
        </tr>
        <tr>
          <td align="center" style="padding:20px 32px 28px 32px;${font}font-size:13px;line-height:20px;color:${b.muted};">
            ${escapeHtml(c.question)}<br>
            <a href="${LINKS.privacy}" style="color:${b.muted};text-decoration:underline;">${escapeHtml(c.privacy)}</a><br>
            ${escapeHtml(c.signature)}
          </td>
        </tr>
      </table>
      <!--[if mso]></td></tr></table><![endif]-->
    </td>
  </tr>
</table>
</body>
</html>
`;
}

function text(c, name, english) {
  // French puts a space before the colon; English does not.
  const sep = c === COPY.en ? ": " : " : ";
  const lines = [
    c.hello(name),
    "",
    c.lead,
    ...c.steps.map(([, label], i) => `${i + 1}. ${label}`),
    "",
    `${c.button}${sep}${LINKS.app}`,
    `${c.play}${sep}${LINKS.play}`,
    "",
  ];
  if (english) lines.push(english, "");
  lines.push(
    "—",
    c.question,
    `${c.privacy}${sep}${LINKS.privacy}`,
    c.signature,
    "",
  );
  return lines.join("\n");
}
