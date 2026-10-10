// Cloudflare Worker: Mara's welcome e-mail, sent once through Resend.
//
// Wired as the push Worker is (workers/push, migration 115): the database
// writes a row — here a welcome_emails row (124), written by a trigger on
// auth.users the first time a new account has a confirmed address — and a
// Supabase Database Webhook created in the dashboard (table
// welcome_emails, event INSERT) posts it here with the shared secret. One
// door:
//
//   POST /v1/welcome   Authorization: Bearer <MAIL_WEBHOOK_SECRET>
//                      body: the webhook's { type, table, record } or
//                      { user_id } (a hand-made retry, curl)
//
// Never twice: the Worker claims the row (welcome_email_claim: pending →
// sending, under a lock) before Resend is called, and only a pending row
// is claimed — a second webhook, a retry or a replay finds it « already
// sending/sent » and sends nothing. Resend is also given the user's id as
// its Idempotency-Key. The outcome is written back (welcome_email_done):
// sent with Resend's id, or failed with its words.
//
// What it holds (wrangler.toml; secrets set by deploy-mail.yml):
//
//   SUPABASE_SERVICE_ROLE_KEY   for welcome_email_claim / _done alone,
//                               granted to the service role only; it never
//                               reaches a browser (as push's).
//   MAIL_WEBHOOK_SECRET         what the database must present.
//   RESEND_API_KEY              Resend's key. Absent, the Worker logs it,
//                               claims nothing and sends nothing — the row
//                               stays pending.
//   MAIL_FROM  MAIL_REPLY_TO    « Mara <bienvenue@marakaj.com> »,
//                               hello@kaj-consulting.com.

import { welcomeEmail } from "./welcome.js";

const RESEND_URL = "https://api.resend.com/emails";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/v1/welcome") {
      if (!constantTimeEqual(bearer(request), env.MAIL_WEBHOOK_SECRET || "")) {
        return json({ error: "unauthorised" }, 401);
      }
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: "body is not JSON" }, 400);
      }
      const userId = userIdOf(body);
      if (!userId) {
        // Not ours; said gently so a misconfigured webhook shows in the
        // dashboard without being retried forever (as push does).
        return json({ skipped: "not a welcome_emails insert" }, 200);
      }
      return json(await welcome(userId, env), 200);
    }
    return json({ error: "not found" }, 404);
  },
};

/// The user id from the webhook's record, or from a bare { user_id }.
export function userIdOf(body) {
  if (body && body.record) {
    if (body.type !== "INSERT" || body.table !== "welcome_emails") return null;
    body = body.record;
  }
  const id = body && typeof body.user_id === "string" ? body.user_id : "";
  return UUID.test(id) ? id.toLowerCase() : null;
}

/// One person's welcome: claim, send, write the outcome back.
export async function welcome(userId, env, io = { fetch, log: console.log }) {
  const log = io.log || console.log;
  if (!env.RESEND_API_KEY) {
    log(`kaj-mail: RESEND_API_KEY is not set — the welcome for ${userId} is not sent (its row stays pending). README « Welcome e-mail (Resend) ».`);
    return { skipped: "RESEND_API_KEY not set" };
  }
  const claim = await rpc(env, "welcome_email_claim", { p_user: userId }, io.fetch);
  if (!claim || claim.send !== true) {
    const reason = (claim && claim.reason) || "nothing to send";
    log(`kaj-mail: ${userId} not sent: ${reason}`);
    return { skipped: reason };
  }
  const mail = welcomeEmail({ firstName: claim.first_name, lang: claim.lang });
  let ok = false, id = null, error = null;
  try {
    const response = await io.fetch(RESEND_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.RESEND_API_KEY}`,
        "Content-Type": "application/json",
        "Idempotency-Key": `welcome-${userId}`,
      },
      body: JSON.stringify({
        from: env.MAIL_FROM || "Mara <bienvenue@marakaj.com>",
        to: [claim.email],
        reply_to: env.MAIL_REPLY_TO || "hello@kaj-consulting.com",
        subject: mail.subject,
        html: mail.html,
        text: mail.text,
        tags: [{ name: "kind", value: "welcome" }],
      }),
    });
    const answer = await response.json().catch(() => ({}));
    if (response.ok && answer && answer.id) {
      ok = true;
      id = String(answer.id);
    } else {
      error = `Resend ${response.status}: ${(answer && (answer.message || answer.name)) || "refused"}`;
    }
  } catch (e) {
    // Resend may or may not have it: the row is marked failed, never
    // claimed again, so it is never sent twice.
    error = `Resend unreachable: ${e && e.message ? e.message : e}`;
  }
  await rpc(env, "welcome_email_done",
    { p_user: userId, p_ok: ok, p_id: id, p_error: error }, io.fetch).catch((e) => {
    log(`kaj-mail: ${userId} outcome not written back: ${e.message}`);
  });
  if (ok) {
    log(`kaj-mail: welcome sent to ${userId} (${id})`);
    return { sent: true, id };
  }
  log(`kaj-mail: welcome for ${userId} failed: ${error}`);
  return { sent: false, error };
}

async function rpc(env, fn, args, fetchImpl = fetch) {
  const response = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify(args),
  });
  if (!response.ok) throw new Error(`${fn} answered ${response.status}`);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

function bearer(request) {
  const value = request.headers.get("Authorization") || "";
  return value.startsWith("Bearer ") ? value.slice(7).trim() : "";
}

// Compared without an early exit so a guess cannot be timed.
function constantTimeEqual(a, b) {
  if (a.length !== b.length || a.length === 0) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
