#!/usr/bin/env node
// Makes the site's push identity: one P-256 key pair, printed once.
//
//   node workers/push/scripts/make-vapid.mjs
//
// Store the PRIVATE line as the repository secret VAPID_PRIVATE_KEY and the
// PUBLIC line as the repository variable VAPID_PUBLIC_KEY (README: "Push
// notifications"). Run it once: every browser that subscribes is bound to
// this public key, and a new pair silently orphans them all.

const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const jwk = await crypto.subtle.exportKey("jwk", pair.privateKey);
const raw = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
const b64url = (bytes) => Buffer.from(bytes).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

console.log("VAPID_PUBLIC_KEY   (repository variable):");
console.log(b64url(raw));
console.log();
console.log("VAPID_PRIVATE_KEY  (repository secret — never commit, never paste elsewhere):");
console.log(JSON.stringify(jwk));
