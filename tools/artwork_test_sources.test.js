"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const hydrator = import("../scripts/hydrate-artwork-test-sources.mjs");

function item(slug, source, kind = "js", overrides = {}) {
  return {
    internal_slug: slug,
    script: {
      kind,
      expectedByteCount: source.length,
      sha256: crypto.createHash("sha256").update(source).digest("hex"),
      ...overrides,
    },
  };
}

async function fixture(t, items) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "artwork-test-sources-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const itemsPath = path.join(root, "items.json");
  const outputDirectory = path.join(root, "ArtworkScripts");
  await fs.writeFile(itemsPath, JSON.stringify(items));
  return { itemsPath, outputDirectory };
}

test("artwork descriptors derive source formats and honor HTTPS overrides", async () => {
  const { artworkSourceDescriptors } = await hydrator;
  const data = Buffer.from("source");
  const descriptors = artworkSourceDescriptors([
    item("javascript", data), item("document", data, "html"), item("processing", data, "processingjs146"),
    item("override", data, "svg", { sourceURL: "https://example.test/immutable/source-v2.js" }),
    { internal_slug: "native", script: { kind: "native.card-nft-2" } },
    { internal_slug: "image" },
  ]);
  assert.deepEqual(descriptors.map((descriptor) => descriptor.url), [
    "https://cdn.lil.org/player/scripts/javascript.js",
    "https://cdn.lil.org/player/scripts/document.html",
    "https://cdn.lil.org/player/scripts/processing.pde",
    "https://example.test/immutable/source-v2.js",
  ]);
  assert.deepEqual(descriptors.map((descriptor) => descriptor.extension), ["js", "html", "pde", "js"]);
  for (const overrides of [
    { expectedByteCount: 0 }, { expectedByteCount: 1.5 }, { sha256: "invalid" },
    { sourceURL: "http://example.test/source.js" }, { sourceURL: "/relative.js" },
    { sourceURL: "https://example.test/source.js#fragment" }, { sourceURL: "https://example.test/source.js#" },
  ]) {
    assert.throws(() => artworkSourceDescriptors([item("invalid", data, "js", overrides)]));
  }
  assert.throws(() => artworkSourceDescriptors([item("../unsafe", data)]));
  assert.throws(() => artworkSourceDescriptors([item("native", data, "native.card-nft-2")]));
});

test("cold hydration writes exact bytes and warm or offline checks make no requests", async (t) => {
  const { hydrateArtworkTestSources, artworkSourceDescriptors } = await hydrator;
  const source = Buffer.from(" \tconst café = 'λ';\r\n\r\n");
  const items = [item("example", source)];
  const options = await fixture(t, items);
  let requests = 0;
  const result = await hydrateArtworkTestSources({ ...options, transport: async (url) => {
    requests += 1;
    assert.equal(url, "https://cdn.lil.org/player/scripts/example.js");
    assert.deepEqual(await fs.readdir(options.outputDirectory), []);
    return { statusCode: 200, data: source };
  } });
  assert.deepEqual(result, { sources: 1, cached: 0, downloaded: 1 });
  const file = path.join(options.outputDirectory, artworkSourceDescriptors(items)[0].filename);
  assert.deepEqual(await fs.readFile(file), source);
  const offline = async () => { requests += 1; throw new Error("offline"); };
  assert.deepEqual(await hydrateArtworkTestSources({ ...options, transport: offline }), { sources: 1, cached: 1, downloaded: 0 });
  assert.deepEqual(await hydrateArtworkTestSources({ ...options, check: true, transport: offline }), { sources: 1, cached: 1, downloaded: 0 });
  assert.equal(requests, 1);
  assert.deepEqual(await fs.readdir(options.outputDirectory), [path.basename(file)]);
});

test("offline checks do not create missing output or replace corrupt files", async (t) => {
  const { hydrateArtworkTestSources, artworkSourceDescriptors } = await hydrator;
  const source = Buffer.from("source");
  const items = [item("example", source)];
  const options = await fixture(t, items);
  const transport = async () => { assert.fail("offline checks must not fetch"); };
  await assert.rejects(hydrateArtworkTestSources({ ...options, check: true, transport }), /run node scripts\/hydrate-artwork-test-sources.mjs/u);
  await assert.rejects(fs.access(options.outputDirectory), { code: "ENOENT" });
  await fs.mkdir(options.outputDirectory);
  const file = path.join(options.outputDirectory, artworkSourceDescriptors(items)[0].filename);
  await fs.writeFile(file, "broken");
  await assert.rejects(hydrateArtworkTestSources({ ...options, check: true, transport }), /missing or corrupt/u);
  assert.equal(await fs.readFile(file, "utf8"), "broken");
});

test("corrupt files and changed pins fetch fresh bytes without deleting other versions", async (t) => {
  const { hydrateArtworkTestSources, artworkSourceDescriptors } = await hydrator;
  const first = Buffer.from("version one");
  const second = Buffer.from("version two");
  const items = [item("example", first)];
  const options = await fixture(t, items);
  let requests = 0;
  let source = first;
  const transport = async () => { requests += 1; return { statusCode: 200, data: source }; };
  await hydrateArtworkTestSources({ ...options, transport });
  const firstFile = path.join(options.outputDirectory, artworkSourceDescriptors(items)[0].filename);
  await fs.writeFile(firstFile, "bad version");
  await hydrateArtworkTestSources({ ...options, transport });
  assert.deepEqual(await fs.readFile(firstFile), first);
  source = second;
  const nextItems = [item("example", second, "js", { sourceURL: "https://example.test/source-v2.js" })];
  await fs.writeFile(options.itemsPath, JSON.stringify(nextItems));
  await hydrateArtworkTestSources({ ...options, transport });
  const secondFile = path.join(options.outputDirectory, artworkSourceDescriptors(nextItems)[0].filename);
  assert.deepEqual(await fs.readFile(secondFile), second);
  assert.deepEqual(await fs.readFile(firstFile), first);
  assert.equal(requests, 3);
});

test("failed downloads never publish unverified or partial source files", async (t) => {
  const { hydrateArtworkTestSources } = await hydrator;
  for (const [name, expected, response, error] of [
    ["HTTP", Buffer.from("abc"), { statusCode: 404, data: Buffer.from("abc") }, /HTTP 404/u],
    ["size", Buffer.from("abc"), { statusCode: 200, data: Buffer.from("abcd") }, /expected 3 bytes/u],
    ["checksum", Buffer.from("abc"), { statusCode: 200, data: Buffer.from("xyz") }, /SHA-256 mismatch/u],
    ["UTF-8", Buffer.from([0xff]), { statusCode: 200, data: Buffer.from([0xff]) }, /not valid UTF-8/u],
  ]) {
    await t.test(name, async (t) => {
      const options = await fixture(t, [item("example", expected)]);
      await assert.rejects(hydrateArtworkTestSources({ ...options, transport: async () => response }), error);
      assert.deepEqual(await fs.readdir(options.outputDirectory), []);
    });
  }
  await t.test("transport", async (t) => {
    const options = await fixture(t, [item("example", Buffer.from("abc"))]);
    await assert.rejects(hydrateArtworkTestSources({ ...options, transport: async () => { throw new Error("offline"); } }), /offline/u);
    assert.deepEqual(await fs.readdir(options.outputDirectory), []);
  });
});

test("hydration deduplicates shared pins and limits downloads to four at a time", async (t) => {
  const { hydrateArtworkTestSources } = await hydrator;
  const sources = Array.from({ length: 9 }, (_, index) => Buffer.from(`source ${index}`));
  const items = sources.map((source, index) => item(`example_${index}`, source));
  items.push(item("same_source", sources[0]));
  const options = await fixture(t, items);
  let active = 0;
  let maximumActive = 0;
  let requests = 0;
  let releaseFirstBatch;
  const firstBatch = new Promise((resolve) => { releaseFirstBatch = resolve; });
  await hydrateArtworkTestSources({ ...options, transport: async (url) => {
    requests += 1;
    active += 1;
    maximumActive = Math.max(maximumActive, active);
    if (requests === 4) releaseFirstBatch();
    await firstBatch;
    active -= 1;
    const index = url.includes("same_source") ? 0 : Number(url.match(/example_(\d+)\.js$/u)[1]);
    return { statusCode: 200, data: sources[index] };
  } });
  assert.equal(requests, 9);
  assert.equal(maximumActive, 4);
});
