// Cloudflare Worker: the code that proves a shopper's number, on WhatsApp
// (migration 109).
//
// Supabase makes the code and checks it; this Worker only carries it. The
// app asks Supabase to change the account's phone (auth.updateUser({phone}));
// Supabase's « Send SMS » auth hook POSTs here, signed the Standard Webhooks
// way, with the account and the six digits; the Worker sends them through
// the WhatsApp Cloud API with Mara's approved « authentication » template;
// the shopper types them back in the app (verifyOTP, type phone_change) and
// Supabase marks the number proved — which is what 109's place_order asks
// for once the platform turns order_phone_verified on.
//
// Doors:
//
//   POST /v1/send-sms   Supabase's Send SMS hook, signed with
//                       SEND_SMS_HOOK_SECRET → 200 {} once WhatsApp took
//                       the message, or 200 { error: { http_code, message } }
//                       which Supabase hands back to the app as the refusal
//   GET  /v1/health     { ready } — whether the four secrets are set; never
//                       a value
//
// What it holds (Worker secrets only, put there by deploy-whatsapp-otp.yml
// from GitHub secrets the owner made — never in this file, never in a log):
//
//   WHATSAPP_TOKEN        Meta's token for Mara's WhatsApp Business account
//                         (a system user's, permission
//                         whatsapp_business_messaging)
//   WHATSAPP_PHONE_ID     the « Phone number ID » of Mara's WhatsApp number
//   WHATSAPP_TEMPLATE     the approved authentication template's name
//   SEND_SMS_HOOK_SECRET  the hook's secret Supabase shows, « v1,whsec_… »
//
// and two plain settings in wrangler.toml: WHATSAPP_LANGUAGE (the
// template's language, fr) and GRAPH_API_VERSION.
//
// The code is never logged, never kept, and sent nowhere but to Meta. A
// code goes only to an account that already exists by e-mail or Google —
// the app's only ways in — so the hook cannot be used to open accounts by
// phone or to send messages at Mara's expense to numbers nobody signed up
// with.

const HOOK_TOLERANCE_SECONDS = 5 * 60;

export default {
  async fetch(request, env) {
    return route(request, env, fetch);
  },
};

/// The doors, with the network passed in so the tests can play Meta.
export async function route(request, env, fetchImpl) {
  const url = new URL(request.url);
  if (request.method === "GET" && url.pathname === "/v1/health") {
    return json({ ready: ready(env) }, 200);
  }
  if (url.pathname === "/v1/send-sms") {
    if (request.method !== "POST") return json({ error: "POST only" }, 405);
    return onSendSms(request, env, fetchImpl);
  }
  return json({ error: "not found" }, 404);
}

/// All four secrets are there.
export function ready(env) {
  return Boolean(env.WHATSAPP_TOKEN && env.WHATSAPP_PHONE_ID
    && env.WHATSAPP_TEMPLATE && env.SEND_SMS_HOOK_SECRET);
}

/// Supabase's Send SMS hook.
export async function onSendSms(request, env, fetchImpl) {
  const raw = await request.text();
  if (!env.SEND_SMS_HOOK_SECRET
      || !(await verifyHook(request.headers, raw, env.SEND_SMS_HOOK_SECRET))) {
    // Not Supabase, or a secret that does not match: nothing is sent, and
    // Supabase says « hook requires authorization » to whoever asked.
    return json({ error: "bad signature" }, 401);
  }
  if (!ready(env)) {
    return hookError(503, "L'envoi du code par WhatsApp n'est pas encore configuré.");
  }
  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    return hookError(400, "Demande illisible.");
  }
  const target = hookTarget(payload);
  if (target.error) return hookError(target.status, target.error);

  let answer;
  try {
    answer = await fetchImpl(graphUrl(env), {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.WHATSAPP_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(whatsappMessage(target.to, target.otp, env)),
    });
  } catch {
    return hookError(502, "WhatsApp n'a pas répondu. Réessayez dans un moment.");
  }
  if (answer.ok) return json({}, 200);
  let metaCode = null;
  try {
    metaCode = (await answer.json())?.error?.code ?? null;
  } catch {}
  // What went wrong, without the number or the code.
  console.log(`whatsapp-otp: Meta answered ${answer.status}, error ${metaCode ?? "none"}`);
  return hookError(...refusalFor(answer.status, metaCode));
}

/// Where the code goes, from the hook's payload. Supabase puts the number
/// the code is for in `sms.phone` (the new number of a phone change; older
/// versions only in `user.new_phone`), digits without a +.
export function hookTarget(payload) {
  const user = payload?.user ?? {};
  const otp = String(payload?.sms?.otp ?? "");
  if (!/^\d{4,10}$/.test(otp)) {
    return { status: 400, error: "Demande sans code." };
  }
  if (!String(user.email ?? "").trim()) {
    // A phone-only sign-up: not a way into Mara.
    return { status: 403, error: "Un numéro se vérifie depuis un compte Mara existant." };
  }
  const phone = String(payload?.sms?.phone || user.new_phone || user.phone || "").replace(/\D/g, "");
  if (phone.length < 8 || phone.length > 15) {
    return { status: 422, error: "Numéro de téléphone incomplet." };
  }
  return { to: phone, otp };
}

/// The authentication template, its code in the body and in the « copy
/// code » button (Meta's own shape for an authentication template).
export function whatsappMessage(to, otp, env) {
  return {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to,
    type: "template",
    template: {
      name: env.WHATSAPP_TEMPLATE,
      language: { code: env.WHATSAPP_LANGUAGE || "fr" },
      components: [
        { type: "body", parameters: [{ type: "text", text: otp }] },
        { type: "button", sub_type: "url", index: "0", parameters: [{ type: "text", text: otp }] },
      ],
    },
  };
}

export function graphUrl(env) {
  const version = env.GRAPH_API_VERSION || "v23.0";
  return `https://graph.facebook.com/${version}/${encodeURIComponent(env.WHATSAPP_PHONE_ID)}/messages`;
}

/// Meta's refusal, as the shopper reads it — [http_code, message].
export function refusalFor(status, metaCode) {
  // Not on WhatsApp, or a test number's allow-list (131030).
  if (metaCode === 131026 || metaCode === 131030 || metaCode === 131009) {
    return [422, "Ce numéro ne reçoit pas WhatsApp. Vérifiez-le, ou essayez un autre numéro."];
  }
  // Too many messages: to this number, or for Mara's account.
  if (status === 429 || metaCode === 131056 || metaCode === 130429 || metaCode === 80007) {
    return [429, "Trop de codes envoyés. Réessayez dans quelques minutes."];
  }
  return [502, "Le code n'a pas pu partir sur WhatsApp. Réessayez dans un moment."];
}

// ----------------------------------------------------------------
// Standard Webhooks: webhook-id, webhook-timestamp and webhook-signature
// (« v1,<base64> », several separated by spaces — Supabase writes « , »
// between them); the HMAC-SHA256 of « id.timestamp.body » with the secret
// that follows « v1,whsec_ », base64-decoded. Older than five minutes is
// refused, so a captured delivery cannot be replayed later than that.
// Within those five minutes no replay cache (no webhook-id remembered) is
// needed: the signed body names the number and the code, so a replay can
// only send the same code to the same number again — nothing a captured
// delivery could change, nothing it could learn. Meta's own limits (the
// 429 above) bound how often that can be done.
// ----------------------------------------------------------------

export async function verifyHook(headers, rawBody, secret, nowSeconds = Math.floor(Date.now() / 1000)) {
  const id = headers.get("webhook-id");
  const timestamp = headers.get("webhook-timestamp");
  const signatures = headers.get("webhook-signature");
  if (!id || !timestamp || !signatures || !secret) return false;
  const t = Number(timestamp);
  if (!Number.isInteger(t) || Math.abs(nowSeconds - t) > HOOK_TOLERANCE_SECONDS) return false;
  const key = hookKey(secret);
  if (!key) return false;
  const expected = await hmacBase64(key, `${id}.${timestamp}.${rawBody}`);
  return signatures
    .split(/\s+/)
    .map((s) => s.replace(/,+$/, ""))
    .some((s) => {
      const comma = s.indexOf(",");
      return comma > 0 && s.slice(0, comma) === "v1" && constantTimeEqual(s.slice(comma + 1), expected);
    });
}

/// « v1,whsec_<base64> » (or « whsec_<base64> », or the bare base64) → the
/// key's bytes; null when it is not base64.
export function hookKey(secret) {
  let s = String(secret).trim();
  if (s.startsWith("v1,")) s = s.slice(3);
  if (s.startsWith("whsec_")) s = s.slice(6);
  try {
    const bytes = Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
    return bytes.length ? bytes : null;
  } catch {
    return null;
  }
}

export async function hmacBase64(keyBytes, message) {
  const key = await crypto.subtle.importKey(
    "raw", keyBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)));
  let bin = "";
  for (const b of mac) bin += String.fromCharCode(b);
  return btoa(bin);
}

export function constantTimeEqual(a, b) {
  if (a.length !== b.length || a.length === 0) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/// A refusal Supabase passes on: its status and its words reach the app.
function hookError(httpCode, message) {
  return json({ error: { http_code: httpCode, message } }, 200);
}

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
