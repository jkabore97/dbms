// Firebase Cloud Messaging, HTTP v1 — the Android phone's ring with the app
// closed (115), next to Web Push for browsers.
//
// What it needs is one Worker secret, FCM_SERVICE_ACCOUNT: the JSON key of
// a Firebase service account allowed to send (Firebase console → Project
// settings → Service accounts → Generate new private key). Without it the
// phones' rows are skipped, nothing is attempted and nothing fails.
//
// The OAuth dance is done here, on WebCrypto: a JWT signed RS256 with the
// account's private key is traded at Google's token endpoint for an access
// token (an hour), kept in memory and reused until a minute before it ends.
// Neither the key nor the token is ever logged or returned.

import { b64urlEncode } from "./webpush.js";

const te = new TextEncoder();
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

/// The account from the secret, or null when absent or unreadable.
export function readServiceAccount(env) {
  const raw = env.FCM_SERVICE_ACCOUNT || "";
  if (!raw) return null;
  try {
    const sa = JSON.parse(raw);
    if (!sa.client_email || !sa.private_key || !sa.project_id) return null;
    return {
      clientEmail: sa.client_email,
      privateKey: sa.private_key,
      projectId: sa.project_id,
      tokenUri: sa.token_uri || "https://oauth2.googleapis.com/token",
    };
  } catch {
    return null;
  }
}

function pemToPkcs8(pem) {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const s = atob(body);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

/// The signed assertion Google's token endpoint trades for an access token.
export async function signedAssertion(sa, now = Math.floor(Date.now() / 1000)) {
  const header = b64urlEncode(te.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64urlEncode(te.encode(JSON.stringify({
    iss: sa.clientEmail,
    scope: SCOPE,
    aud: sa.tokenUri,
    iat: now,
    exp: now + 3600,
  })));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(sa.privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, te.encode(`${header}.${claims}`));
  return `${header}.${claims}.${b64urlEncode(new Uint8Array(signature))}`;
}

let cached = null; // { token, until, email }

/// Forgets the access token (tests; a 401 from FCM).
export function forgetAccessToken() {
  cached = null;
}

async function accessToken(sa, fetchImpl) {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.email === sa.clientEmail && cached.until > now + 60) return cached.token;
  const response = await fetchImpl(sa.tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: await signedAssertion(sa, now),
    }).toString(),
  });
  if (!response.ok) throw new Error(`token endpoint answered ${response.status}`);
  const body = await response.json();
  if (!body.access_token) throw new Error("token endpoint gave no token");
  cached = { token: body.access_token, until: now + (body.expires_in || 3600), email: sa.clientEmail };
  return cached.token;
}

/// One phone, one ring. Answers an HTTP-like status the caller sorts the
/// way it sorts Web Push: 200 sent, 404 a token gone (dropped), else failed.
export async function sendFcm(token, payload, sa, fetchImpl = fetch) {
  const bearer = await accessToken(sa, fetchImpl);
  const response = await fetchImpl(
    `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(sa.projectId)}/messages:send`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${bearer}` },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: payload.title, body: payload.body },
          // Where a tap lands, read by the app (core/notify/push_client_android.dart).
          data: { path: payload.path || "/", url: payload.url || "" },
          android: {
            priority: "high",
            notification: { tag: payload.tag || undefined },
          },
        },
      }),
    },
  );
  if (response.ok) return 200;
  if (response.status === 401) forgetAccessToken();
  // A token the phone no longer holds: UNREGISTERED (404), or one FCM
  // refuses as malformed (400 INVALID_ARGUMENT naming the token).
  if (response.status === 404) return 404;
  if (response.status === 400) {
    const text = await response.text().catch(() => "");
    if (/registration token|UNREGISTERED/i.test(text)) return 404;
  }
  return response.status;
}
