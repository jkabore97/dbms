// Wave's side of kaj-pay: the three calls and the webhook signature.
//
// Wave Business API (docs.wave.com): bearer-key HTTPS, amounts as strings,
// XOF with no decimals. A Burkina Faso key only works in Burkina Faso.

const WAVE = "https://api.wave.com";

/// Creates a checkout session. Returns { id, wave_launch_url, ... }.
export async function createSession(env, args, fetchImpl = fetch) {
  const body = {
    amount: wholeFrancs(args.amount),
    currency: args.currency || "XOF",
    client_reference: args.clientReference,
    success_url: args.successUrl,
    error_url: args.errorUrl,
  };
  if (args.aggregatedMerchantId) body.aggregated_merchant_id = args.aggregatedMerchantId;
  return waveCall(env, "/v1/checkout/sessions", body, null, fetchImpl);
}

/// Sends a shop its money. The payment id is the idempotency key: a retry
/// of the same payout is never a second payout.
export async function sendPayout(env, args, fetchImpl = fetch) {
  return waveCall(env, "/v1/payout", {
    currency: args.currency || "XOF",
    receive_amount: wholeFrancs(args.amount),
    mobile: args.mobile,
    name: args.name || undefined,
    client_reference: args.paymentId,
    payment_reason: "Kaj · vente sur la vitrine",
  }, args.paymentId, fetchImpl);
}

async function waveCall(env, path, body, idempotencyKey, fetchImpl) {
  const headers = {
    Authorization: `Bearer ${env.WAVE_API_KEY}`,
    "Content-Type": "application/json",
  };
  if (idempotencyKey) headers["idempotency-key"] = idempotencyKey;
  const response = await fetchImpl(`${WAVE}${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  const text = await response.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  if (!response.ok) {
    const message = data?.message || data?.code || `Wave answered ${response.status}`;
    const error = new Error(message);
    error.status = response.status;
    throw error;
  }
  return data;
}

/// "5000.00" → "5000": Wave takes francs CFA whole.
export function wholeFrancs(amount) {
  return String(Math.round(Number(amount)));
}

/// Checks `Wave-Signature: t=<unix>,v1=<hex>[,v1=<hex>]` — an HMAC-SHA256
/// over the timestamp followed by the raw body, with the webhook secret.
/// Older than five minutes is refused: a captured delivery cannot be
/// replayed later.
export async function verifySignature(header, rawBody, secret, nowSeconds = Math.floor(Date.now() / 1000)) {
  if (!header || !secret) return false;
  let timestamp = null;
  const signatures = [];
  for (const part of header.split(",")) {
    const [key, value] = part.trim().split("=", 2);
    if (key === "t") timestamp = value;
    else if (key === "v1" && value) signatures.push(value.toLowerCase());
  }
  if (!timestamp || signatures.length === 0) return false;
  const t = Number(timestamp);
  if (!Number.isFinite(t) || Math.abs(nowSeconds - t) > 300) return false;
  const expected = await hmacHex(secret, `${timestamp}${rawBody}`);
  return signatures.some((s) => constantTimeEqual(s, expected));
}

export async function hmacHex(secret, message) {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)));
  return [...mac].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function constantTimeEqual(a, b) {
  if (a.length !== b.length || a.length === 0) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
