// /api/maps-link: a short Google Maps link's position, and nothing else.
//
//   node --test workers/kaj-app/test

import assert from "node:assert/strict";
import { test } from "node:test";

import { allowedMapsHost, mapsLink, positionIn, positionInPage } from "../src/maps.js";

const ask = (u) => new Request(`https://marakaj.com/api/maps-link?u=${encodeURIComponent(u)}`);

function fakeGoogle(routes) {
  const seen = [];
  const impl = async (href) => {
    seen.push(href);
    const r = routes[href];
    if (!r) return new Response("", { status: 404 });
    if (r.location) return new Response("", { status: 302, headers: { Location: r.location } });
    return new Response(r.body || "", { status: 200 });
  };
  return { impl, seen };
}

test("a short link is followed to the place and its position read", async () => {
  const g = fakeGoogle({
    "https://maps.app.goo.gl/AbC123": {
      location: "https://www.google.com/maps/place/Boutique/@12.3714277,-1.5196603,17z/data=!3m1",
    },
  });
  const res = await mapsLink(ask("https://maps.app.goo.gl/AbC123"), g.impl);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { lat: 12.3714277, lng: -1.5196603 });
});

test("a landing address without a position: read from the page", async () => {
  const g = fakeGoogle({
    "https://maps.app.goo.gl/xyz": { location: "https://maps.google.com/?q=Boutique&ftid=0x1:0x2" },
    "https://maps.google.com/?q=Boutique&ftid=0x1:0x2": {
      body: 'window.APP_INITIALIZATION_STATE=[[[1500.5,-1.52,12.37],[0,0,0]]];[null,null,12.371234,-1.519876]',
    },
  });
  const res = await mapsLink(ask("https://maps.app.goo.gl/xyz"), g.impl);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { lat: 12.371234, lng: -1.519876 });
});

test("never leaves Google Maps, at the start or at any hop", async () => {
  assert.equal((await mapsLink(ask("https://evil.example/maps"), fakeGoogle({}).impl)).status, 400);
  assert.equal((await mapsLink(ask("http://maps.app.goo.gl/x"), fakeGoogle({}).impl)).status, 400);
  const g = fakeGoogle({ "https://maps.app.goo.gl/bad": { location: "http://169.254.169.254/latest" } });
  const res = await mapsLink(ask("https://maps.app.goo.gl/bad"), g.impl);
  assert.equal(res.status, 400);
  assert.deepEqual(g.seen, ["https://maps.app.goo.gl/bad"]);
  assert.equal(allowedMapsHost(new URL("https://www.google.com.evil.com/maps")), false);
  assert.equal(allowedMapsHost(new URL("https://www.google.bf/maps/place/x")), true);
  assert.equal(allowedMapsHost(new URL("https://goo.gl/abc")), false);
});

test("no position anywhere: 404", async () => {
  const g = fakeGoogle({ "https://maps.app.goo.gl/none": { body: "<html>nothing</html>" } });
  assert.equal((await mapsLink(ask("https://maps.app.goo.gl/none"), g.impl)).status, 404);
});

test("the shapes a full link takes", () => {
  assert.deepEqual(positionIn("https://www.google.com/maps?q=12.37%2C-1.52"), { lat: 12.37, lng: -1.52 });
  assert.deepEqual(positionIn("https://www.google.com/maps/search/12.37,+-1.52"), { lat: 12.37, lng: -1.52 });
  assert.deepEqual(positionIn("https://www.google.com/maps/place/x/data=!3d12.5!4d-1.6"), { lat: 12.5, lng: -1.6 });
  assert.equal(positionIn("https://www.google.com/maps/place/x"), null);
  assert.equal(positionInPage("[null,null,95.123,-1.123]"), null);
});
