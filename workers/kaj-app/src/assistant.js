// Studio's writing assistant (173), Marakaj Pro: a few sentences for a
// card, written or rewritten in French by Claude.
//
//   POST /api/assistant  { slug, edit, kind, title, place, date, block, what, text }
//
// The card's edit token is the key (as everything in Studio); the server
// says whether the business is Pro and counts the day's uses
// (event_assist_use, forty a day per card) before anything is asked of
// Claude. Without the ANTHROPIC_API_KEY secret the assistant says it is not
// available, and nothing else changes.

import Anthropic from "@anthropic-ai/sdk";

const WHAT = {
  ecrire: "Écris le texte de ce bloc.",
  raccourcir: "Raccourcis ce texte de moitié environ, sans perdre l’essentiel.",
  chaleureux: "Réécris ce texte sur un ton plus chaleureux et plus personnel.",
  solennel: "Réécris ce texte sur un ton plus solennel et plus élégant.",
  corriger: "Corrige l’orthographe, la grammaire et la ponctuation de ce texte, sans en changer le sens ni le ton.",
};

const BLOCK = {
  text: "un mot d’accueil (deux à quatre phrases)",
  story: "notre histoire, racontée simplement (un court paragraphe)",
  quote: "une citation, un proverbe ou un verset adapté (une phrase, avec son auteur ou sa référence entre parenthèses)",
  rsvp: "une phrase qui invite à répondre (une ou deux phrases)",
  footer: "un dernier mot de remerciement (une phrase)",
  infos: "une information pratique pour les invités (une ou deux phrases)",
};

const SYSTEM = [
  "Tu écris les textes des cartes d’invitation de Marakaj, une application utilisée surtout au Burkina Faso et en Afrique de l’Ouest francophone.",
  "Écris en français simple, chaleureux et correct, avec les guillemets « » et les apostrophes typographiques.",
  "Respecte les usages de l’événement (mariage, dot, baptême, funérailles, gala, conférence…) : sobre et digne pour un hommage, joyeux pour une fête.",
  "N’invente aucun fait précis absent de la demande : ni nom, ni date, ni heure, ni lieu, ni numéro.",
  "Réponds uniquement par le texte à poser sur la carte, sans titre, sans guillemets autour, sans commentaire ni explication.",
].join("\n");

const json = (status, body) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
});

const clip = (v, n) => String(v ?? "").replace(/\s+/g, " ").trim().slice(0, n);

// The server's word on this card: Pro or not, the day's allowance.
async function allowance(env, slug, edit) {
  const r = await fetch(`${env.SUPABASE_URL.replace(/\/$/, "")}/rest/v1/rpc/event_assist_use`, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_PUBLISHABLE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_slug: slug, p_edit: edit }),
  });
  const body = await r.json().catch(() => null);
  if (!r.ok) return { error: (body && body.message) || "Cette carte ne peut pas être modifiée d’ici." };
  return body || {};
}

export async function assistant(request, env, { client } = {}) {
  if (request.method !== "POST") return json(405, { error: "Méthode refusée." });
  if (!env.ANTHROPIC_API_KEY && !client) return json(503, { error: "L’assistant n’est pas disponible pour le moment." });
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return json(503, { error: "L’assistant n’est pas disponible pour le moment." });
  let q;
  try {
    q = await request.json();
  } catch (_) {
    return json(400, { error: "Demande mal formée." });
  }
  const slug = clip(q && q.slug, 80).toLowerCase(), edit = clip(q && q.edit, 24);
  const what = WHAT[q && q.what] ? q.what : "ecrire";
  const text = clip(q && q.text, 2000);
  if (!/^[a-z0-9-]{1,80}$/.test(slug) || edit.length !== 24) return json(403, { error: "Cette carte ne peut pas être modifiée d’ici." });
  if (what !== "ecrire" && !text) return json(400, { error: "Écrivez d’abord un texte : l’assistant le reprendra." });

  const allowed = await allowance(env, slug, edit).catch(() => ({ error: "Pas de réseau : réessayez." }));
  if (allowed.error) return json(/demain/.test(allowed.error) ? 429 : 403, { error: allowed.error });
  // free so many a day, Pro forty (182): « ok »; before 182, Pro only
  if (allowed.pro !== true && allowed.ok !== true) return json(402, { error: "L’assistant d’écriture a écrit ses textes gratuits du jour : il revient demain, ou sans limite avec Marakaj Pro." });

  const facts = [
    `Événement : ${clip(q.kind, 40) || "autre"}`,
    q.title ? `Titre de la carte : ${clip(q.title, 120)}` : "",
    q.date ? `Date : ${clip(q.date, 60)}` : "",
    q.place ? `Lieu : ${clip(q.place, 120)}` : "",
    `Le bloc : ${BLOCK[q.block] || BLOCK.text}`,
  ].filter(Boolean).join("\n");
  const ask = `${facts}\n\n${WHAT[what]}` + (text ? `\n\nLe texte actuel :\n${text}` : "");

  const claude = client || new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, timeout: 45_000, maxRetries: 1 });
  try {
    const response = await claude.beta.messages.create({
      model: "claude-opus-5-5",
      // a few sentences: a card's text, never more
      max_tokens: 1024,
      output_config: { effort: "low" },
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: SYSTEM,
      messages: [{ role: "user", content: ask }],
    });
    if (response.stop_reason === "refusal") {
      return json(422, { error: "L’assistant ne peut pas écrire ce texte. Essayez d’autres mots." });
    }
    const out = response.content.filter((b) => b.type === "text").map((b) => b.text).join("").trim()
      .replace(/^[«"“]\s*|\s*[»"”]$/g, "");
    if (!out) return json(502, { error: "L’assistant n’a rien écrit. Réessayez." });
    return json(200, { text: out.slice(0, 2000), left: allowed.left ?? null });
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) return json(429, { error: "L’assistant est très demandé : réessayez dans une minute." });
    if (error instanceof Anthropic.AuthenticationError) return json(503, { error: "L’assistant n’est pas disponible pour le moment." });
    if (error instanceof Anthropic.BadRequestError) return json(502, { error: "L’assistant n’a pas compris la demande. Réessayez." });
    if (error instanceof Anthropic.APIError) return json(502, { error: "L’assistant ne répond pas. Réessayez." });
    return json(502, { error: "Pas de réseau : réessayez." });
  }
}
