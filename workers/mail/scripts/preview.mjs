#!/usr/bin/env node
// Writes the welcome e-mail as Resend would receive it, to look at in a
// browser before it goes out:
//
//   node workers/mail/scripts/preview.mjs <out-dir> [first name]
//
// gives <out-dir>/welcome_fr.html, welcome_en.html, welcome_unknown.html
// and the plain-text versions beside them.
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { welcomeEmail } from "../src/welcome.js";

const [out, name = "Awa"] = process.argv.slice(2);
if (!out) {
  console.error("usage: preview.mjs <out-dir> [first name]");
  process.exit(2);
}
mkdirSync(out, { recursive: true });
for (const lang of ["fr", "en", null]) {
  const tag = lang ?? "unknown";
  const mail = welcomeEmail({ firstName: name, lang });
  writeFileSync(join(out, `welcome_${tag}.html`), mail.html);
  writeFileSync(join(out, `welcome_${tag}.txt`), `Subject: ${mail.subject}\n\n${mail.text}`);
  console.log(`${tag}: ${mail.subject}`);
}
