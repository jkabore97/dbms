// Cloudflare Worker: Wave checkout for Kaj (migration 076).
//
// Kaj holds one Wave Business account, registered as an aggregator. A
// shopper's order, a Kaj Pro subscription and a spot are paid through a
// Wave checkout session; Wave tells this Worker when it is paid; the
// database marks it paid; and for an order the Worker sends the goods'
// price, less the platform's share, to the shop's own Wave number. Doors:
//
//   POST /v1/checkout   the app, with the person's own Supabase token:
//                       { kind: order|pro|spot, ref, method: wave|card,
//                         period: month|year } → { url, payment_id }
//   POST /v1/wave       Wave's webhook, signed with WAVE_WEBHOOK_SECRET
//   cron */15           payouts that failed are tried again (five times)
//
// What it holds, and why (secrets set by deploy-pay.yml):
//
//   WAVE_API_KEY               Kaj's Wave Business key — never in an app
//   WAVE_WEBHOOK_SECRET        what Wave signs its webhook with
//   SUPABASE_SERVICE_ROLE_KEY  used for exactly four functions granted to
//                              the service role alone: wave_attach,
//                              wave_settle, wave_payout_done,
//                              wave_payout_queue
//
// The amount is never the app's: wave_begin() (called with the person's
// own token, so under their identity) reads it from the order, the plan or
// the spot, and refuses what is not theirs to pay.

import { createSession, sendPayout, verifySignature } from "./wave.js";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const cors = corsHeaders(request.headers.get("Origin"), env);

    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });

    if (request.method === "GET" && url.pathname === "/v1/health") {
      return json({ ready: Boolean(env.WAVE_API_KEY && env.WAVE_WEBHOOK_SECRET) }, 200, cors);
    }

    if (request.method === "POST" && url.pathname === "/v1/checkout") {
      if (!env.WAVE_API_KEY) return json({ error: "Wave n'est pas encore configuré." }, 503, cors);
      const token = bearer(request);
      if (!token) return json({ error: "Connectez-vous pour payer." }, 401, cors);
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: "body is not JSON" }, 400, cors);
      }
      try {
        const result = await checkout(body, token, env);
        return json(result, 200, cors);
      } catch (error) {
        return json({ error: error.message || "Le paiement n'a pas pu commencer." },
          error.status && error.status < 500 ? error.status : 502, cors);
      }
    }

    if (request.method === "POST" && url.pathname === "/v1/wave") {
      const raw = await request.text();
      const ok = await verifySignature(request.headers.get("Wave-Signature"), raw, env.WAVE_WEBHOOK_SECRET);
      if (!ok) return json({ error: "bad signature" }, 401, {});
      let event;
      try {
        event = JSON.parse(raw);
      } catch {
        return json({ error: "body is not JSON" }, 400, {});
      }
      const result = await onWebhook(event, env);
      // 200 whatever we made of it: Wave retries non-2xx, and a duplicate
      // or an event we do not use must not be retried forever.
      return json(result, 200, {});
    }

    return json({ error: "not found" }, 404, cors);
  },

  async scheduled(_event, env, ctx) {
    if (!env.WAVE_API_KEY) return;
    ctx.waitUntil(retryPayouts(env));
  },
};

/// The app asked to pay something.
export async function checkout(body, userToken, env, io = { fetch }) {
  const kind = String(body?.kind || "");
  const method = body?.method === "card" ? "card" : "wave";
  const begun = await rpcAs(env, userToken, "wave_begin", {
    p_kind: kind,
    p_ref: body?.ref,
    p_method: method,
    p_period: body?.period === "year" ? "year" : "month",
  }, io.fetch);

  const origin = (env.APP_ORIGIN || "").replace(/\/$/, "");
  const back = `${origin}/paiement/${begun.payment_id}`;
  const session = await createSession(env, {
    amount: begun.amount,
    currency: begun.currency,
    clientReference: begun.client_reference,
    successUrl: `${back}?issue=ok`,
    errorUrl: `${back}?issue=erreur`,
    aggregatedMerchantId: begun.aggregated_merchant_id || null,
  }, io.fetch);

  await rpcService(env, "wave_attach", {
    p_payment_id: begun.payment_id,
    p_session_id: session.id,
    p_launch_url: session.wave_launch_url,
  }, io.fetch);

  return { url: session.wave_launch_url, payment_id: begun.payment_id, method };
}

/// Wave says a session ended.
export async function onWebhook(event, env, io = { fetch, sendPayout }) {
  const type = event?.type || "";
  const data = event?.data || {};
  if (type !== "checkout.session.completed" && type !== "checkout.session.payment_failed") {
    return { ignored: type };
  }
  const succeeded = type === "checkout.session.completed" && data.payment_status === "succeeded";
  const payout = await rpcService(env, "wave_settle", {
    p_client_reference: data.client_reference,
    p_session_id: data.id || null,
    p_succeeded: succeeded,
    p_transaction_id: data.transaction_id || null,
  }, io.fetch);
  if (!payout) return { settled: succeeded };
  await payOut(payout, env, io);
  return { settled: true, payout: true };
}

/// Sends one shop its money and records the outcome either way.
export async function payOut(payout, env, io = { fetch, sendPayout }) {
  try {
    const sent = await io.sendPayout(env, {
      paymentId: payout.payment_id,
      amount: payout.amount,
      currency: payout.currency,
      mobile: payout.mobile,
      name: payout.name,
    }, io.fetch);
    const ok = sent?.status !== "failed" && sent?.status !== "reversed";
    await rpcService(env, "wave_payout_done", {
      p_payment_id: payout.payment_id,
      p_ok: ok,
      p_payout_id: sent?.id || null,
      p_error: ok ? null : (sent?.payout_error?.error_message || sent?.status || "failed"),
    }, io.fetch);
    return ok;
  } catch (error) {
    await rpcService(env, "wave_payout_done", {
      p_payment_id: payout.payment_id,
      p_ok: false,
      p_payout_id: null,
      p_error: String(error?.message || error),
    }, io.fetch).catch(() => {});
    return false;
  }
}

export async function retryPayouts(env, io = { fetch, sendPayout }) {
  const queue = await rpcService(env, "wave_payout_queue", {}, io.fetch);
  let sent = 0;
  for (const row of queue || []) {
    if (await payOut(row, env, io)) sent++;
  }
  return sent;
}

/// PostgREST as the person: their token, the public key.
async function rpcAs(env, token, fn, args, fetchImpl) {
  return rpc(env, fn, args, env.SUPABASE_PUBLISHABLE_KEY, token, fetchImpl);
}

/// PostgREST as the service role, for the four functions it alone runs.
async function rpcService(env, fn, args, fetchImpl) {
  return rpc(env, fn, args, env.SUPABASE_SERVICE_ROLE_KEY, env.SUPABASE_SERVICE_ROLE_KEY, fetchImpl);
}

async function rpc(env, fn, args, apikey, token, fetchImpl = fetch) {
  const response = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey,
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(args),
  });
  const text = await response.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = null; }
  if (!response.ok) {
    // The database's own words ("Cette commande est déjà payée") reach the
    // person; a 4xx stays a 4xx.
    const error = new Error(data?.message || `${fn} answered ${response.status}`);
    error.status = response.status >= 500 ? 502 : 400;
    throw error;
  }
  return data;
}

function bearer(request) {
  const value = request.headers.get("Authorization") || "";
  return value.startsWith("Bearer ") ? value.slice(7).trim() : "";
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
