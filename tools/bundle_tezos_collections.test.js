"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");
const { decodeAspectRatioMetadata, tokenIdsFromPayload } = require("./aspect_ratios");

const BUNDLER_PATH = path.resolve(__dirname, "bundle_tezos_collections.js");
const CONTRACT = "KT1LiZ9cFA9fRQdKkbJtfz1djC7AkrTkTcDE";

function createFixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "nft-player-tezos-bundler-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const tokensPath = path.join(root, "Tokens");
  const itemsPath = path.join(root, "items.json");
  const tokenPath = path.join(tokensPath, "curated_collection.json");
  fs.mkdirSync(tokensPath);
  fs.writeFileSync(itemsPath, JSON.stringify([{
    address: CONTRACT,
    chain: "tezos",
    name: "Old Collection Name",
    internal_slug: "curated_collection",
    artists: ["curated_artist"],
  }]));
  fs.writeFileSync(tokenPath, JSON.stringify({
    hasMid: false,
    items: [{ id: "2", urlSuffix: "2.png" }, { id: "1", urlSuffix: "1.png", aspectRatio: [4, 3] }],
    urlPrefix: "https://old.example/",
    tmp_files: { "1": "original.png" },
    aspectRatio: [16, 9],
  }));
  return { root, tokensPath, itemsPath, tokenPath };
}

function runBundler(fixture, apply, urls = ["https://assets.example/1.png", "https://assets.example/2.png"], mime = null) {
  const argv = [
    process.execPath, BUNDLER_PATH,
    "--delay-ms", "0", "--max-retries", "0", "--skip-covers",
    apply ? "--apply" : "--dry-run",
    "--bundle", fixture.root,
    "--covers", path.join(fixture.root, "covers"),
    "--report", path.join(fixture.root, "report.md"),
    "--json-report", path.join(fixture.root, "report.json"),
    CONTRACT,
  ];
  const harness = `
global.fetch = async (input) => {
  const url = String(input);
  const payload = url.includes("/contracts/")
    ? { metadata: { name: "New Collection Name" } }
    : url.includes("/tokens/count")
      ? 2
      : ["1", "2"].map((id) => ({ tokenId: id, metadata: {
        name: "Collection #" + id,
        artifactUri: ${JSON.stringify(urls)}[Number(id) - 1],
        mimeType: ${JSON.stringify(mime)},
      } }));
  return { ok: true, status: 200, json: async () => payload };
};
process.argv = ${JSON.stringify(argv)};
require(${JSON.stringify(BUNDLER_PATH)});
`;
  return spawnSync(process.execPath, ["-e", harness], {
    encoding: "utf8",
    timeout: 5000,
  });
}

test("Tezos bundling reconstructs URLs with one prefix across directories and origins", (t) => {
  for (const [urls, prefix] of [
    [["https://assets.example/art/1.png", "https://assets.example/art/2.png"], "https://assets.example/art/"],
    [["https://assets.example/art/one/1.png", "https://assets.example/art/two/2.png"], "https://assets.example/art/"],
    [["https://assets.example/1.png", "https://other.example/2.png"], ""],
  ]) {
    const fixture = createFixture(t);
    const result = runBundler(fixture, true, urls);
    assert.equal(result.status, 0, result.stderr);
    const payload = JSON.parse(fs.readFileSync(fixture.tokenPath, "utf8"));
    assert.equal(payload.urlPrefix, prefix);
    assert.equal(Object.hasOwn(payload, "urlPrefixes"), false);
    assert.equal(Object.hasOwn(payload, "defaultFileExtension"), false);
    assert.equal(Object.hasOwn(payload, "isComplete"), false);
    assert.deepEqual(payload.items, urls.map((url, index) => ({ id: String(index + 1), urlSuffix: url.slice(prefix.length), fileExtension: "png", ...(index === 1 ? { aspectRatio: [16, 9] } : {}) })));
    assert.deepEqual(payload.items.map((row) => payload.urlPrefix + row.urlSuffix), urls);
  }
});

test("Tezos bundling preserves media hints without reparsing source URLs", (t) => {
  for (const [urls, mime, extensions] of [
    [["https://assets.example/1", "https://assets.example/2"], "image/gif", ["gif", "gif"]],
    [["https://assets.example/1?ext=png", "https://assets.example/2?ext=webp"], null, ["png", "webp"]],
    [["https://assets.example/1.png", "https://assets.example/collection.v1%2F42"], "image/png", ["png", "png"]],
    [["https://assets.example/1.png", "https://bad host.example/42.png"], "image/png", ["png", "png"]],
  ]) {
    const fixture = createFixture(t);
    const result = runBundler(fixture, true, urls, mime);
    assert.equal(result.status, 0, result.stderr);
    const payload = JSON.parse(fs.readFileSync(fixture.tokenPath, "utf8"));
    assert.equal(Object.hasOwn(payload, "defaultFileExtension"), false);
    assert.deepEqual(payload.items.map((row) => row.fileExtension), extensions);
    assert.deepEqual(payload.items.map((row) => payload.urlPrefix + row.urlSuffix), urls);
  }
});

test("Tezos rebundling preserves curated slugs and token metadata when a name changes", (t) => {
  const fixture = createFixture(t);
  const result = runBundler(fixture, true);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(fs.readdirSync(fixture.tokensPath), ["curated_collection.json"]);
  const payload = JSON.parse(fs.readFileSync(fixture.tokenPath, "utf8"));
  assert.equal(payload.hasMid, false);
  assert.deepEqual(payload.tmp_files, { "1": "original.png" });
  assert.deepEqual(tokenIdsFromPayload(payload), ["1", "2"]);
  assert.deepEqual(decodeAspectRatioMetadata(payload), [[4, 3], [16, 9]]);
  const [item] = JSON.parse(fs.readFileSync(fixture.itemsPath, "utf8"));
  assert.equal(item.address, CONTRACT);
  assert.equal(item.name, "New Collection Name");
  assert.equal(item.internal_slug, "curated_collection");
  assert.deepEqual(item.artists, ["curated_artist"]);
});

test("Tezos dry-run paths use the preserved catalog slug", (t) => {
  const fixture = createFixture(t);
  const original = fs.readFileSync(fixture.itemsPath, "utf8");
  const result = runBundler(fixture, false);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(fixture.itemsPath, "utf8"), original);
  const report = JSON.parse(fs.readFileSync(path.join(fixture.root, "report.json"), "utf8"));
  assert.equal(report.collections[0].cover.assetId, "curated_collection");
  assert.equal(report.collections[0].cover.outputPath, path.join(fixture.root, "covers", "curated_collection.jpg"));
});
