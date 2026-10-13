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
// and, optional (130, SEC_AUDIT_2 M6), the database's ration:
//
//   SUPABASE_URL               the project's address (a variable)
//   SUPABASE_SERVICE_ROLE_KEY  used for one function, otp_send_allow(),
//                              granted to the service role alone
//
// The code is never logged, never kept, and sent nowhere but to Meta. A
// code goes only to an account that already exists by e-mail or Google —
// the app's only ways in — so the hook cannot be used to open accounts by
// phone. But the number is whatever the account typed: any signed-in
// account could make Mara pay for messages to any number. So every code
// is rationed before it goes (otpGate): at most 3 per number per 10
// minutes and 10 a day, 5 per account per 10 minutes and 20 a day. The
// database counts (130's otp_send_allow, md5 of the number, two days);
// without it — not configured, 130 not applied yet, unreachable — this
// Worker's own memory counts the same limits (per isolate: weaker, never
// none). Over the limit the code is not sent, the log says which limit
// (never the number), and the shopper reads only « too many codes ».
// Supabase's hook carries no client address: the limits are per number
// and per account; Supabase's own « SMS per hour » is the global cap.

//
// 133 (batch 136, « Besoin d'aide »): the same Worker carries the alert a
// trainer receives when a Pro business asks for help. No new secret: the
// WHATSAPP_TOKEN and WHATSAPP_PHONE_ID above, and 130's SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY. Every minute (the cron trigger in
// wrangler.toml) it claims the outbox rows the database wrote
// (help_whatsapp_claim, the service role's alone — it also runs the
// help's clock), sends each with the template the row names (the
// platform setting help_whatsapp_template, default « aide_demande »:
// body {{1}} the business, {{2}} its kind, {{3}} the subject; the button's
// URL suffix the request's id) and says how it went
// (help_whatsapp_done: sent, or template | not_whatsapp | rate | meta |
// network). A template Meta has not approved fails at Meta and the
// console says so; an empty setting writes no row at all. Nothing here
// can fail a request: the bell was written with it, before any of this.
//
//   GET /v1/help/health  { help } — whether the four it needs are set
//
// Meta's webhook: Meta asked for one, subscribed to the
// « messages » field (message statuses come through it), before it lets
// Mara's account create templates. Two optional secrets, made by the owner:
//
//   META_VERIFY_TOKEN  any long random string, typed in the app's webhook
//                      settings at Meta too (« Verify token »)
//   META_APP_SECRET    the Mara app's « App secret » (App settings › Basic):
//                      every event Meta POSTs is signed with it
//                      (X-Hub-Signature-256), and one unsigned or signed
//                      otherwise is refused
//
//   GET  /v1/meta   Meta's check: hub.mode=subscribe and the verify token
//                   → hub.challenge, else 403
//   POST /v1/meta   an event: signature checked, then only counted in the
//                   log (statuses sent / delivered / read / failed, the
//                   template reviews) — never a number, a name or a text
//                   — and 200 at once, as Meta wants

const HOOK_TOLERANCE_SECONDS = 5 * 60;

export default {
  async fetch(request, env) {
    return route(request, env, fetch);
  },
  // 133: the help's minute.
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(helpRelay(env, fetch).then(
      (r) => console.log(`whatsapp-otp: help relay ${JSON.stringify(r)}`),
      () => console.log("whatsapp-otp: help relay failed"),
    ));
  },
};

/// The doors, with the network passed in so the tests can play Meta.
export async function route(request, env, fetchImpl) {
  const url = new URL(request.url);
  if (request.method === "GET" && url.pathname === "/v1/health") {
    return json({ ready: ready(env) }, 200);
  }
  if (request.method === "GET" && url.pathname === "/v1/help/health") {
    return json({ help: helpReady(env) }, 200);
  }
  if (url.pathname === "/v1/meta") {
    if (request.method === "GET") return onMetaVerify(url, env);
    if (request.method === "POST") return onMetaEvent(request, env);
    return json({ error: "GET or POST only" }, 405);
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

  const gate = await otpGate(env, target.userId, target.to, fetchImpl);
  if (!gate.ok) {
    // Which limit, and who counted — never the number or the code.
    console.log(`whatsapp-otp: refused, over the limit (${gate.reason || "limit"}, ${gate.by})`);
    return hookError(429, "Trop de codes envoyés. Réessayez plus tard.");
  }

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
  const id = String(user.id ?? "");
  return { to: phone, otp, userId: UUID.test(id) ? id : null };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ----------------------------------------------------------------
// The ration (130, SEC_AUDIT_2 M6)
// ----------------------------------------------------------------

/// The limits — the same as 130's otp_send_allow().
export const LIMITS = Object.freeze({
  phonePer10Minutes: 3,
  phonePerDay: 10,
  accountPer10Minutes: 5,
  accountPerDay: 20,
});

const TEN_MINUTES = 10 * 60 * 1000;
const DAY = 24 * 60 * 60 * 1000;

/// May a code go to this number for this account now? The database
/// decides when it can be asked; otherwise this isolate's memory does.
/// { ok, by: "database" | "memory", reason? }.
export async function otpGate(env, userId, phone, fetchImpl, now = Date.now()) {
  if (env.SUPABASE_URL && env.SUPABASE_SERVICE_ROLE_KEY) {
    try {
      const answer = await fetchImpl(`${String(env.SUPABASE_URL).replace(/\/$/, "")}/rest/v1/rpc/otp_send_allow`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: env.SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        },
        body: JSON.stringify({ p_phone: phone, p_user: userId }),
      });
      if (answer.ok) {
        const body = await answer.json().catch(() => null);
        if (body && typeof body.ok === "boolean") {
          return { ok: body.ok, by: "database", reason: typeof body.reason === "string" ? body.reason : undefined };
        }
      }
      // 404: 130 not applied yet; anything else: the database unwell.
      console.log(`whatsapp-otp: the ration answered ${answer.status}; counted in memory`);
    } catch {
      console.log("whatsapp-otp: the ration did not answer; counted in memory");
    }
  }
  return { ...memoryAllow(phone, userId, now), by: "memory" };
}

const memory = new Map();

/// For the tests: a fresh isolate.
export function resetMemoryLimits() {
  memory.clear();
}

/// The same limits, counted in this isolate's memory.
export function memoryAllow(phone, userId, now = Date.now()) {
  if (memory.size > 5000) memory.clear();
  const recent = (key) => {
    const kept = (memory.get(key) || []).filter((t) => now - t < DAY);
    memory.set(key, kept);
    return kept;
  };
  const within = (list, ms) => list.filter((t) => now - t < ms).length;
  const byPhone = recent(`p:${phone}`);
  if (within(byPhone, TEN_MINUTES) >= LIMITS.phonePer10Minutes) return { ok: false, reason: "phone_10_minutes" };
  if (byPhone.length >= LIMITS.phonePerDay) return { ok: false, reason: "phone_day" };
  const byAccount = userId ? recent(`u:${userId}`) : null;
  if (byAccount) {
    if (within(byAccount, TEN_MINUTES) >= LIMITS.accountPer10Minutes) return { ok: false, reason: "account_10_minutes" };
    if (byAccount.length >= LIMITS.accountPerDay) return { ok: false, reason: "account_day" };
    byAccount.push(now);
  }
  byPhone.push(now);
  return { ok: true };
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
// « Besoin d'aide » (133): the trainers' alert
// ----------------------------------------------------------------

/// What the relay needs: Meta's two and the database's two.
export function helpReady(env) {
  return Boolean(env.WHATSAPP_TOKEN && env.WHATSAPP_PHONE_ID
    && env.SUPABASE_URL && env.SUPABASE_SERVICE_ROLE_KEY);
}

/// One minute's work: claim, send, say. Answers what it did, never a
/// number, a name or a message.
export async function helpRelay(env, fetchImpl, limit = 20) {
  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) return { skipped: "no database" };
  // Without Meta's two the rows are left alone: the database marks them
  // stale after an hour and the console says WhatsApp waits.
  if (!env.WHATSAPP_TOKEN || !env.WHATSAPP_PHONE_ID) return { skipped: "no whatsapp" };
  let rows;
  try {
    rows = await serviceRpc(env, "help_whatsapp_claim", { p_limit: limit }, fetchImpl);
  } catch (e) {
    // 404: 133 not applied yet. Anything else: the database unwell.
    return { skipped: e?.status === 404 ? "no help" : "database" };
  }
  if (!Array.isArray(rows)) return { sent: 0, failed: 0 };
  let sent = 0, failed = 0;
  for (const row of rows) {
    const outcome = await sendHelp(row, env, fetchImpl);
    if (outcome === null) sent++;
    else failed++;
    try {
      await serviceRpc(env, "help_whatsapp_done",
        { p_id: row.id, p_ok: outcome === null, p_error: outcome }, fetchImpl);
    } catch {
      // Left « sending »: the database calls it stale within the hour.
    }
  }
  return { sent, failed };
}

/// Sends one alert: null when Meta took it, else the word for why not.
export async function sendHelp(row, env, fetchImpl) {
  if (!row || typeof row.template !== "string" || !/^[a-z0-9_]{1,250}$/.test(row.template)) return "off";
  const to = String(row.to ?? "").replace(/\D/g, "");
  if (to.length < 8 || to.length > 15) return "not_whatsapp";
  let answer;
  try {
    answer = await fetchImpl(graphUrl(env), {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.WHATSAPP_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(helpMessage(row, env)),
    });
  } catch {
    return "network";
  }
  if (answer.ok) return null;
  let metaCode = null;
  try {
    metaCode = (await answer.json())?.error?.code ?? null;
  } catch {}
  console.log(`whatsapp-otp: help alert, Meta answered ${answer.status}, error ${metaCode ?? "none"}`);
  return helpRefusal(answer.status, metaCode);
}

/// Controls, zero-width and direction marks, line and paragraph
/// separators, the byte-order mark — written as escapes, never as the
/// characters themselves.
const INVISIBLE = new RegExp("[\\u0000-\\u001f\\u007f-\\u009f\\u200b-\\u200f\\u2028-\\u202e\\u2060-\\u2069\\ufeff]", "g");

/// A template's parameter: plain words on one line (Meta refuses a new
/// line, a tab or four spaces in a row), 60 characters at most.
export function helpParam(value) {
  const s = String(value ?? "").replace(INVISIBLE, " ")
    .replace(/\s+/g, " ").trim();
  return (s || "—").slice(0, 60);
}

/// The utility template: {{1}} the business, {{2}} its kind, {{3}} the
/// subject; the button « Ouvrir dans Mara », its URL ending in the
/// request's id.
export function helpMessage(row, env) {
  const p = row.params || {};
  const id = String(p.request_id ?? "");
  return {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: String(row.to).replace(/\D/g, ""),
    type: "template",
    template: {
      name: row.template,
      language: { code: env.HELP_LANGUAGE || env.WHATSAPP_LANGUAGE || "fr" },
      components: [
        {
          type: "body",
          parameters: [
            { type: "text", text: helpParam(p.name) },
            { type: "text", text: helpParam(p.kind) },
            { type: "text", text: helpParam(p.subject) },
          ],
        },
        {
          type: "button",
          sub_type: "url",
          index: "0",
          parameters: [{ type: "text", text: /^[0-9a-f-]{36}$/i.test(id) ? id : "" }],
        },
      ],
    },
  };
}

/// Meta's refusal, in one word for the console.
export function helpRefusal(status, metaCode) {
  // The template: missing, not approved, paused, its parameters wrong.
  if ([132000, 132001, 132005, 132007, 132012, 132015, 132016, 132068, 132069].includes(metaCode)) {
    return "template";
  }
  if (metaCode === 131026 || metaCode === 131030 || metaCode === 131009) return "not_whatsapp";
  if (status === 429 || metaCode === 131056 || metaCode === 130429 || metaCode === 80007) return "rate";
  return "meta";
}

async function serviceRpc(env, fn, args, fetchImpl) {
  const answer = await fetchImpl(`${String(env.SUPABASE_URL).replace(/\/$/, "")}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify(args),
  });
  if (!answer.ok) {
    const e = new Error(`${fn} answered ${answer.status}`);
    e.status = answer.status;
    throw e;
  }
  const text = await answer.text();
  return text ? JSON.parse(text) : null;
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

/// Meta's subscription check: the challenge back only for our token.
export function onMetaVerify(url, env) {
  const mode = url.searchParams.get("hub.mode");
  const token = url.searchParams.get("hub.verify_token");
  const challenge = url.searchParams.get("hub.challenge") || "";
  if (env.META_VERIFY_TOKEN && mode === "subscribe"
      && token !== null && timingSafeEqual(token, env.META_VERIFY_TOKEN)) {
    return new Response(challenge, { status: 200, headers: { "content-type": "text/plain" } });
  }
  return new Response("forbidden", { status: 403 });
}

/// An event from Meta: signed with the app secret, or refused.
export async function onMetaEvent(request, env) {
  const raw = await request.text();
  if (!env.META_APP_SECRET) return json({ error: "not configured" }, 503);
  const header = request.headers.get("x-hub-signature-256") || "";
  const expected = "sha256=" + (await hmacHex(env.META_APP_SECRET, raw));
  if (!timingSafeEqual(header, expected)) return json({ error: "bad signature" }, 401);
  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    return json({ ok: true }, 200);
  }
  console.log(`whatsapp-otp: meta event ${JSON.stringify(metaSummary(payload))}`);
  return json({ ok: true }, 200);
}

/// What an event says, counted — nothing that names anybody.
export function metaSummary(payload) {
  const out = { statuses: {}, messages: 0, templates: {} };
  for (const entry of Array.isArray(payload?.entry) ? payload.entry : []) {
    for (const change of Array.isArray(entry?.changes) ? entry.changes : []) {
      const v = change?.value || {};
      if (change?.field === "messages") {
        for (const st of Array.isArray(v.statuses) ? v.statuses : []) {
          const k = String(st?.status || "unknown").slice(0, 20);
          out.statuses[k] = (out.statuses[k] || 0) + 1;
        }
        out.messages += Array.isArray(v.messages) ? v.messages.length : 0;
      } else if (change?.field === "message_template_status_update") {
        const k = `${String(v.message_template_name || "?").slice(0, 40)}:${String(v.event || "?").slice(0, 20)}`;
        out.templates[k] = (out.templates[k] || 0) + 1;
      }
    }
  }
  return out;
}

async function hmacHex(secret, message) {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)));
  return [...mac].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(a, b) {
  const x = new TextEncoder().encode(String(a));
  const y = new TextEncoder().encode(String(b));
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] || 0) ^ (y[i] || 0);
  return diff === 0;
}
