// The camera button and the handwriting reader are writers' doors
// (review of batch 136): since 133 a trainer may READ a business for 48 h,
// so « the caller can read the business » must never be what lets a file
// into its folder. Both ask can_write_org as the caller.
//
//   node --test workers/uploads/test

import assert from "node:assert/strict";
import { test } from "node:test";

import worker from "../src/index.js";

const ORG = "6f1c2f8e-1111-4a2b-9c3d-000000000001";

function bucket() {
  return {
    puts: [],
    async put(key) { this.puts.push(key); },
  };
}

function env(extra) {
  return {
    SUPABASE_URL: "https://db.example",
    SUPABASE_PUBLISHABLE_KEY: "pub",
    ALLOWED_ORIGINS: "https://marakaj.com",
    UPLOADS: bucket(),
    ...extra,
  };
}

// Postgres, played: can_write_org answers [writes]; reading the business
// (the old check) would answer a row — it must not be asked.
function withPostgres(writes, run) {
  const real = globalThis.fetch;
  const asked = [];
  globalThis.fetch = async (url, init) => {
    asked.push({ url: String(url), auth: init.headers.Authorization, body: init.body ? JSON.parse(init.body) : null });
    if (String(url).endsWith("/rest/v1/rpc/can_write_org")) {
      return new Response(JSON.stringify(writes), { status: 200 });
    }
    if (String(url).includes("/rest/v1/orgs")) {
      return new Response(JSON.stringify([{ id: ORG }]), { status: 200 });
    }
    return new Response("{}", { status: 404 });
  };
  return run(asked).finally(() => { globalThis.fetch = real; });
}

const upload = (e) => worker.fetch(
  new Request(`https://up.example/v1/orgs/${ORG}/uploads`, {
    method: "POST",
    headers: { Authorization: "Bearer tok", "Content-Type": "image/jpeg", Origin: "https://marakaj.com" },
    body: new Uint8Array(100).fill(1),
  }), e);

test("a writer's photo goes in, can_write_org asked as the caller", async () => {
  const e = env();
  await withPostgres(true, async (asked) => {
    const r = await upload(e);
    assert.equal(r.status, 201);
    assert.equal(e.UPLOADS.puts.length, 1);
    assert.ok(e.UPLOADS.puts[0].startsWith(`org/${ORG}/`));
    assert.deepEqual(asked.map((a) => a.url), ["https://db.example/rest/v1/rpc/can_write_org"]);
    assert.equal(asked[0].auth, "Bearer tok");
    assert.deepEqual(asked[0].body, { p_org_id: ORG });
  });
});

test("a reader who may not write (an observer, a trainer with 48 h access) puts nothing", async () => {
  const e = env();
  await withPostgres(false, async () => {
    const r = await upload(e);
    assert.equal(r.status, 403);
    assert.equal(e.UPLOADS.puts.length, 0);
  });
});

test("the handwriting reader is refused to a reader too, before any paid call", async () => {
  const e = env({ ANTHROPIC_API_KEY: "k" });
  await withPostgres(false, async (asked) => {
    const r = await worker.fetch(new Request(`https://up.example/v1/orgs/${ORG}/read-page`, {
      method: "POST",
      headers: { Authorization: "Bearer tok", "Content-Type": "application/json", Origin: "https://marakaj.com" },
      body: JSON.stringify({ image: "aGVsbG8=", mime: "image/jpeg" }),
    }), e);
    assert.equal(r.status, 403);
    assert.ok(asked.every((a) => !a.url.includes("anthropic")));
  });
});
