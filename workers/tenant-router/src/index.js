// Cloudflare Worker: resolves an incoming hostname to a tenant (org) and
// forwards the request with tenant context attached.
//
// Handles both cases from the plan:
//   - subdomain.kajapp.com  (default, one DNS record covers every tenant)
//   - app.theirbusiness.com (custom domain, added per tenant as they grow)
//
// KV namespace binding expected: TENANT_ROUTES (see wrangler.toml)
// Each key   = hostname, e.g. "esperance.kajapp.com" or "app.esperancebeauty.com"
// Each value = JSON, e.g. {"orgId": "...", "orgSlug": "esperance"}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const hostname = url.hostname;

    const mapping = await env.TENANT_ROUTES.get(hostname, { type: "json" });

    if (!mapping) {
      return new Response("No business is registered at this address.", {
        status: 404,
      });
    }

    // The app resolves its own tenant from the authenticated session, not
    // from this header — these headers are for server-side routing only
    // (e.g. a Supabase Edge Function deciding which org's data to touch).
    const forwardedRequest = new Request(request);
    forwardedRequest.headers.set("X-Kaj-Org-Id", mapping.orgId);
    forwardedRequest.headers.set("X-Kaj-Org-Slug", mapping.orgSlug);

    return fetch(forwardedRequest);
  },
};
