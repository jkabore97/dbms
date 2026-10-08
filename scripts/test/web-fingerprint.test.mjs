// scripts/web-fingerprint.mjs on a little build of its own shape.
//
//   node --test scripts/test/*.test.mjs

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const script = join(dirname(fileURLToPath(import.meta.url)), "..", "web-fingerprint.mjs");
const sha = (s) => createHash("sha256").update(s).digest("hex");

function fakeBuild(overrides = {}) {
  const root = mkdtempSync(join(tmpdir(), "mara-fp-"));
  const files = {
    "index.html": '<script>_flutter.buildConfig={};</script><script>var PATHS = /*MARA_PATHS*/{}; var VERSION = /*MARA_VERSION*/"";</script>',
    "mara_sw.js": "const BUILD = /*MARA_BUILD*/null;",
    "main.dart.js": "main",
    "main.dart.js_1.part.js": "part one",
    "main.dart.js.map": "{}",
    "flutter_bootstrap.js": "old loader",
    "flutter.js": "loader",
    "canvaskit/canvaskit.js": "ck",
    "canvaskit/canvaskit.wasm": "ckw",
    "canvaskit/chromium/canvaskit.wasm": "ckc",
    "canvaskit/canvaskit.js.symbols": "syms",
    "assets/FontManifest.json": "[]",
    "assets/fonts/MaterialIcons-Regular.otf": "font",
    "sqflite_sw.js": "sqflite",
    "sqlite3.wasm": "sqlite",
    "manifest.json": "{}",
    "favicon.png": "png",
    "icons/Icon-192.png": "icon",
    "showcase/x/y.jpg": "photo",
    ...overrides,
  };
  for (const [p, body] of Object.entries(files)) {
    if (body === null) continue;
    mkdirSync(dirname(join(root, p)), { recursive: true });
    writeFileSync(join(root, p), body);
  }
  return root;
}

const run = (root, version = "abc123") =>
  spawnSync(process.execPath, [script, root, version], { encoding: "utf8" });

test("moves each changing file under a folder named after its content", () => {
  const root = fakeBuild();
  try {
    const r = run(root);
    assert.equal(r.status, 0, r.stderr);
    const html = readFileSync(join(root, "index.html"), "utf8");
    const paths = JSON.parse(html.match(/var PATHS = (\{[^;]*\});/)[1]);
    assert.match(paths.entrypointBaseUrl, /^\/app\/[0-9a-f]{12}\/$/);
    assert.match(paths.canvasKitBaseUrl, /^\/ck\/[0-9a-f]{12}\/$/);
    assert.match(paths.assetBase, /^\/a\/[0-9a-f]{12}\/$/);
    assert.ok(html.includes('var VERSION = "abc123";'));

    const at = (p) => join(root, p.slice(1));
    assert.equal(readFileSync(at(paths.entrypointBaseUrl + "main.dart.js"), "utf8"), "main");
    assert.equal(readFileSync(at(paths.entrypointBaseUrl + "main.dart.js_1.part.js"), "utf8"), "part one");
    assert.equal(readFileSync(at(paths.canvasKitBaseUrl + "chromium/canvaskit.wasm"), "utf8"), "ckc");
    assert.equal(readFileSync(at(paths.assetBase + "assets/FontManifest.json"), "utf8"), "[]");
    for (const gone of ["main.dart.js", "canvaskit", "assets", "flutter_bootstrap.js", "flutter.js"]) {
      assert.ok(!existsSync(join(root, gone)), gone);
    }
    // Fixed names stay where the plugin and the page look for them.
    assert.ok(existsSync(join(root, "sqflite_sw.js")));
    assert.ok(existsSync(join(root, "showcase/x/y.jpg")));

    const sw = readFileSync(join(root, "mara_sw.js"), "utf8");
    const build = JSON.parse(sw.match(/const BUILD = (\{.*\});/)[1]);
    assert.equal(build.version, "abc123");
    assert.deepEqual(build.dirs, { app: paths.entrypointBaseUrl, ck: paths.canvasKitBaseUrl, a: paths.assetBase });
    assert.equal(build.shell["/"], sha(html));
    assert.equal(build.shell["/sqlite3.wasm"], sha("sqlite"));
    assert.ok(build.files.includes(paths.entrypointBaseUrl + "main.dart.js_1.part.js"));
    assert.ok(build.files.includes(paths.canvasKitBaseUrl + "canvaskit.wasm"));
    // Never fetched by a browser, never listed.
    assert.ok(!build.files.some((f) => /\.(symbols|map)$/.test(f)));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("an unchanged engine keeps its folder from one build to the next", () => {
  const a = fakeBuild();
  const b = fakeBuild({ "main.dart.js": "main, changed" });
  try {
    assert.equal(run(a, "one").status, 0);
    assert.equal(run(b, "two").status, 0);
    const paths = (root) => JSON.parse(readFileSync(join(root, "index.html"), "utf8").match(/var PATHS = (\{[^;]*\});/)[1]);
    assert.equal(paths(a).canvasKitBaseUrl, paths(b).canvasKitBaseUrl);
    assert.equal(paths(a).assetBase, paths(b).assetBase);
    assert.notEqual(paths(a).entrypointBaseUrl, paths(b).entrypointBaseUrl);
  } finally {
    rmSync(a, { recursive: true, force: true });
    rmSync(b, { recursive: true, force: true });
  }
});

test("refuses, touching nothing, a build of the wrong shape", () => {
  for (const broken of [
    { "sqlite3.wasm": null },
    { "index.html": "<p>no loader, no placeholders</p>" },
    { "mara_sw.js": "const BUILD = {};" },
  ]) {
    const root = fakeBuild(broken);
    try {
      const r = run(root);
      assert.equal(r.status, 1, JSON.stringify(broken));
      assert.match(r.stderr, /web-fingerprint:/);
      assert.ok(existsSync(join(root, "main.dart.js")), "nothing moved");
      assert.ok(existsSync(join(root, "canvaskit")), "nothing moved");
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  }
});

test("run twice, the second run stops instead of nesting folders", () => {
  const root = fakeBuild();
  try {
    assert.equal(run(root).status, 0);
    const again = run(root);
    assert.equal(again.status, 1);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
