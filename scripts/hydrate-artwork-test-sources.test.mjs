import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { artworkSourceDescriptors, hydrateArtworkTestSources } from "./hydrate-artwork-test-sources.mjs";
import { downloadCDNAsset } from "../tools/cdn-assets.mjs";

const source = Buffer.from("window.render = () => {};\n");
const script = {
  kind: "js", expectedByteCount: source.length,
  sha256: crypto.createHash("sha256").update(source).digest("hex"),
};
const item = { internal_slug: "sample", script };

test("accepts default CDN sources and pinned CDN overrides", () => {
  assert.equal(artworkSourceDescriptors([item])[0].url, "https://cdn.lil.org/player/scripts/sample.js");
  const sourceURL = "https://cdn.lil.org/player/scripts/sample-v2.js";
  assert.equal(artworkSourceDescriptors([{ ...item, script: { ...script, sourceURL } }])[0].url, sourceURL);
});

test("rejects external artwork sources including Terraforms and malformed CDN URLs", () => {
  for (const sourceURL of [
    "https://example.com/sample.js", "https://cdn.lil.org.example.com/sample.js",
    "https://tokens.mathcastles.xyz/terraforms/token-html/42?ext=html",
    "http://cdn.lil.org/sample.js", "https://user@cdn.lil.org/sample.js",
    "https://cdn.lil.org:8443/sample.js", "https://cdn.lil.org/sample.js#fragment", "/sample.js",
  ]) {
    assert.throws(() => artworkSourceDescriptors([{ ...item, script: { ...script, sourceURL } }]), /HTTPS on cdn.lil.org/u);
  }
});

test("follows CDN redirects manually", async () => {
  const calls = [];
  const response = await downloadCDNAsset("https://cdn.lil.org/start.js", async (url, options) => {
    calls.push(url);
    assert.equal(options.redirect, "manual");
    return calls.length === 1
      ? new Response(null, { status: 302, headers: { location: "/final.js" } })
      : new Response(source);
  });
  assert.deepEqual(calls, ["https://cdn.lil.org/start.js", "https://cdn.lil.org/final.js"]);
  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.data, source);
});

test("rejects redirects away from the CDN before requesting their targets", async () => {
  for (const location of ["https://example.com/final.js", "http://cdn.lil.org/final.js",
    "https://tokens.mathcastles.xyz/terraforms/token-html/42?ext=html"]) {
    let requests = 0;
    await assert.rejects(downloadCDNAsset("https://cdn.lil.org/start.js", async () => {
      requests += 1;
      return new Response(null, { status: 307, headers: { location } });
    }), /HTTPS on cdn.lil.org/u);
    assert.equal(requests, 1);
  }
});

test("bounds redirect loops", async () => {
  let requests = 0;
  await assert.rejects(downloadCDNAsset("https://cdn.lil.org/loop.js", async () => {
    requests += 1;
    return new Response(null, { status: 302, headers: { location: "/loop.js" } });
  }), /Invalid CDN asset redirect/u);
  assert.equal(requests, 6);
});

test("hydrates and reuses a validated pinned source without another download", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-artwork-hydration-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const itemsPath = path.join(directory, "items.json");
  const outputDirectory = path.join(directory, "sources");
  await fs.writeFile(itemsPath, JSON.stringify([item]));
  let requests = 0;
  const transport = async () => { requests += 1; return { statusCode: 200, data: source }; };
  assert.deepEqual(await hydrateArtworkTestSources({ itemsPath, outputDirectory, transport }),
    { sources: 1, cached: 0, downloaded: 1 });
  assert.deepEqual(await hydrateArtworkTestSources({ itemsPath, outputDirectory, transport, check: true }),
    { sources: 1, cached: 1, downloaded: 0 });
  assert.equal(requests, 1);
});
