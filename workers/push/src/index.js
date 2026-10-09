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
//   FCM_SERVICE_ACCOUNT         (115, optional) a Firebase service account's
//                               JSON key: Android phones ring through FCM
//                               HTTP v1 (src/fcm.js). Absent, the phones'
//                               rows are skipped and browsers ring as before.

import { FcmTokenError, readServiceAccount, sendFcm } from "./fcm.js";
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

/// One notifications row → a push to every device of its recipient: each
/// browser by Web Push, each Android phone by FCM (115). A database before
/// 115 has no push_devices(); its browsers are read from push_targets().
export async function deliver(row, env, io = { sendPush, sendFcm, fetch }) {
  let targets = null;
  try {
    targets = await rpc(env, "push_devices", { p_recipient: row.recipient_id }, io.fetch);
  } catch {
    targets = null;
  }
  if (!Array.isArray(targets)) {
    targets = await rpc(env, "push_targets", { p_recipient: row.recipient_id }, io.fetch);
  }
  if (!Array.isArray(targets) || targets.length === 0) return { sent: 0, dropped: 0, failed: 0 };

  const browsers = targets.filter((t) => (t.platform || "web") === "web");
  const phones = targets.filter((t) => t.platform === "android" && t.fcm_token);
  const vapid = browsers.length === 0 ? null : {
    publicKey: env.VAPID_PUBLIC_KEY,
    privateKey: await importVapidPrivateKey(env.VAPID_PRIVATE_KEY),
    subject: env.PUSH_SUBJECT || "mailto:kabore.boss@gmail.com",
  };
  // Dormant without its secret: the phones are not tried, nor counted.
  const account = phones.length === 0 ? null : readServiceAccount(env);
  const payload = payloadFor(row, env);

  let sent = 0, dropped = 0, failed = 0;
  // Google's token endpoint said no once: the other phones of this call
  // are counted failed without asking it again (it would say the same).
  let tokenFailed = false;
  for (const target of [...browsers, ...(account ? phones : [])]) {
    let status;
    if (target.platform === "android" && tokenFailed) {
      failed++;
      continue;
    }
    try {
      status = target.platform === "android"
        ? await (io.sendFcm || sendFcm)(target.fcm_token, payload, account, io.fetch)
        : await io.sendPush(target, payload, vapid);
    } catch (e) {
      if (e instanceof FcmTokenError) tokenFailed = true;
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
  // A followed vitrine's news (113) opens that vitrine; a shopper's
  // report answered, their own notifications.
  const slug = row.params && typeof row.params.slug === "string" ? row.params.slug : "";
  const to = (row.params && typeof row.params.to === "string" ? row.params.to : "") ||
    (row.scope === "customer" ? "customer" : "");
  if (kind === "vitrine_news" && /^[a-z0-9-]{1,80}$/.test(slug)) path = `/s/${slug}`;
  else if (kind === "report_handled") path = "/mon-compte/notifications";
  // 112: the platform's bell for a courier's application opens the
  // console's couriers; the applicant's refusal or « new photo » their
  // own application — as the app's notificationTarget does. Only an
  // approved courier's bells open the board.
  else if (kind === "courier_application") path = "/console/livreurs";
  else if (kind === "courier_refused" || kind === "courier_photo") path = "/devenir-livreur";
  // 111: an older app's request answered at once opens the creation.
  else if (kind === "application_update_app") path = "/creer-mon-activite";
  // 115: the dossier received opens its progress; the platform's own
  // bells their queue; the account's its security.
  else if (kind === "courier_received") path = "/devenir-livreur";
  else if (kind === "org_application") path = "/demandes";
  else if (kind.startsWith("spot_") && !row.org_id) path = "/console/a-la-une";
  else if (kind === "new_device") path = "/securite";
  else if (kind.startsWith("courier_") || kind === "delivery_available") path = "/livreur";
  // A customer's order or booking (to: customer, 099) opens their own
  // orders — never the shop's, which they cannot open.
  else if (to === "customer" && (kind.startsWith("order") || kind.startsWith("delivery"))) {
    path = row.params?.booking === true ? "/mon-compte/reservations" : "/mes-commandes";
  }
  // The shop's own: a new order (« new_order », which the bare prefix
  // missed — it opened the home) and every order or delivery line.
  else if (row.org_id && (kind === "new_order" || kind.startsWith("order") || kind.startsWith("delivery"))) {
    path = `/o/${row.org_id}/commandes`;
  }
  else if (row.org_id) path = `/o/${row.org_id}`;
  return {
    title: "Mara",
    // The database's sentences were written when the app was Kaj.
    body: (row.message || "").replace(/\bKaj\b(?![\s-]+[Cc]onsulting)(?![-_/\w])(?!\.\w)/g, "Mara"),
    url: `${origin}${path}`,
    // The app's own address, for the Android app's tap (115).
    path,
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
