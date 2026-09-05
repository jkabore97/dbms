// Cloudflare Worker: carries the bell to a closed app.
//
// The bell (database/migrations/030) writes one notifications row per
// recipient at the moments worth interrupting somebody for. This Worker
// is woken by a Supabase database webhook on each of those inserts and
// turns the row into a Web Push to every browser that person said "yes"
// in (060). Two doors:
//
//   GET  /v1/key      the VAPID public key, for the app's subscribe call
//   POST /v1/notify   the webhook: Authorization: Bearer <PUSH_WEBHOOK_SECRET>
//
// What it holds, and why (wrangler.toml, secrets set by deploy-push.yml):
//
//   SUPABASE_SERVICE_ROLE_KEY   the one privileged key in the platform's
//                               Workers. It is used for exactly two
//                               functions — push_targets() and
//                               remove_push_target() — which are granted to
//                               the service role alone, and it never
//                               reaches a browser. The uploads Worker
//                               deliberately holds no such key; this one
//                               must, because "where can I reach this
//                               person" is not a question the app's own
//                               role may answer about anyone else.
//   VAPID_PRIVATE_KEY           the site's push identity (JWK)
//   VAPID_PUBLIC_KEY            its public half, handed to browsers
//   PUSH_WEBHOOK_SECRET         what the database must present at /notify
//   PUSH_SUBJECT                mailto:… the push services may write to
//   APP_ORIGIN                  where a tapped notification opens

import { importVapidPrivateKey, sendPush } from "./webpush.js";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const cors = corsHeaders(request.headers.get("Origin"), env);

    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });

    if (request.method === "GET" && url.pathname === "/v1/key") {
      return json({ key: env.VAPID_PUBLIC_KEY || "" }, 200, cors);
    }

    if (request.method === "POST" && url.pathname === "/v1/notify") {
      if (!constantTimeEqual(bearer(request), env.PUSH_WEBHOOK_SECRET || "")) {
        return json({ error: "unauthorised" }, 401, cors);
      }
      let hook;
      try {
        hook = await request.json();
      } catch {
        return json({ error: "body is not JSON" }, 400, cors);
      }
      const row = hook?.record;
      if (hook?.type !== "INSERT" || hook?.table !== "notifications" || !row?.recipient_id) {
        // Not ours to carry; say so gently so a misconfigured webhook is
        // visible in the dashboard without being retried forever.
        return json({ skipped: "not a notifications insert" }, 200, cors);
      }
      const result = await deliver(row, env);
      return json(result, 200, cors);
    }

    return json({ error: "not found" }, 404, cors);
  },
};

/// One notifications row → a push to every browser of its recipient.
export async function deliver(row, env, io = { sendPush, fetch }) {
  const targets = await rpc(env, "push_targets", { p_recipient: row.recipient_id }, io.fetch);
  if (!Array.isArray(targets) || targets.length === 0) return { sent: 0, dropped: 0, failed: 0 };

  const vapid = {
    publicKey: env.VAPID_PUBLIC_KEY,
    privateKey: await importVapidPrivateKey(env.VAPID_PRIVATE_KEY),
    subject: env.PUSH_SUBJECT || "mailto:kabore.boss@gmail.com",
  };
  const payload = payloadFor(row, env);

  let sent = 0, dropped = 0, failed = 0;
  for (const target of targets) {
    let status;
    try {
      status = await io.sendPush(target, payload, vapid);
    } catch {
      status = 0;
    }
    if (status === 201 || status === 200) {
      sent++;
    } else if (status === 404 || status === 410) {
      dropped++;
      await rpc(env, "remove_push_target", { p_endpoint: target.endpoint }, io.fetch).catch(() => {});
    } else {
      failed++;
    }
  }
  return { sent, dropped, failed };
}

/// What the notification says and where a tap lands. The bell row already
/// carries the line the app shows; the title names the app, and the URL
/// sends an order bell to the shop's orders and a courier bell to the
/// board — the two places somebody woken by a push wants to be.
export function payloadFor(row, env) {
  const origin = (env.APP_ORIGIN || "").replace(/\/$/, "");
  const kind = row.kind || "";
  let path = "/";
  if (kind.startsWith("courier_") || kind === "delivery_available") path = "/livreur";
  else if (row.org_id && (kind.startsWith("order") || kind.startsWith("delivery"))) path = `/o/${row.org_id}/commandes`;
  else if (row.org_id) path = `/o/${row.org_id}`;
  return {
    title: "Kaj",
    body: row.message || "",
    url: `${origin}${path}`,
    tag: row.id ? `kaj-${row.id}` : undefined,
  };
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

function corsHeaders(origin, env) {
  const allowed = (env.ALLOWED_ORIGINS || "").split(",").map((s) => s.trim()).filter(Boolean);
  const headers = {
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
    Vary: "Origin",
  };
  if (origin && allowed.includes(origin)) headers["Access-Control-Allow-Origin"] = origin;
  return headers;
}

function json(body, status, headers) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });
}
