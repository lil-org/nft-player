"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const BUNDLER_PATH = path.resolve(__dirname, "bundle_solana_collections.js");
const BASE58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
const NATIVE_RENDERER_COLLECTION_IDS = [
  "EAzEpagtyeRAx9npnpVMpygoA8ouX7DRpLTghhPvYTiu",
  "JCTP3kK3xGtWs5mDHxJBuRro38HftaiCDdKsfkXuK2gH",
];
const CASE_VARIANT_COLLECTION_IDS = [
  "EazEpagtyeRAx9npnpVMpygoA8ouX7DRpLTghhPvYTiu",
  "JCtP3kK3xGtWs5mDHxJBuRro38HftaiCDdKsfkXuK2gH",
];

function runBundler(input, { resolvedCollectionId = null, assets = [], args = [] } = {}) {
  const harness = `
global.fetch = async (_url, options) => {
  const request = JSON.parse(options.body);
  const result = request.method === "getAssetsByGroup"
    ? { items: ${JSON.stringify(assets)}, total: ${assets.length}, page: 1, limit: 1000 }
    : ${resolvedCollectionId == null
      ? "{}"
      : `{ grouping: [{ group_key: "collection", group_value: ${JSON.stringify(resolvedCollectionId)}, verified: true }] }`};
  console.log("MOCK_RPC", request.method, request.params.groupValue ?? request.params.id);
  return {
    ok: true,
    status: 200,
    headers: { get: () => null },
    json: async () => ({ jsonrpc: "2.0", id: request.id, result }),
    text: async () => "",
  };
};
process.argv = [
  process.execPath,
  ${JSON.stringify(BUNDLER_PATH)},
  "--api-key", "test",
  "--delay-ms", "0",
  "--max-retries", "0",
  "--skip-covers",
  ...${JSON.stringify(args)},
  ${JSON.stringify(input)},
];
require(${JSON.stringify(BUNDLER_PATH)});
`;

  return spawnSync(process.execPath, ["-e", harness], {
    cwd: path.resolve(__dirname, ".."),
    encoding: "utf8",
    timeout: 5000,
  });
}

function decodedBase58ByteLength(value) {
  let decoded = 0n;
  for (const character of value) {
    const digit = BASE58_ALPHABET.indexOf(character);
    assert.notEqual(digit, -1, `${value} contains a non-base58 character`);
    decoded = (decoded * 58n) + BigInt(digit);
  }

  let byteLength = 0;
  for (let remaining = decoded; remaining > 0n; remaining >>= 8n) {
    byteLength += 1;
  }
  for (const character of value) {
    if (character !== "1") {
      break;
    }
    byteLength += 1;
  }
  return byteLength;
}

test("rejects the exact native-renderer collection IDs before querying Helius", () => {
  for (const collectionId of NATIVE_RENDERER_COLLECTION_IDS) {
    const result = runBundler(collectionId);

    assert.equal(result.status, 1);
    assert.match(result.stderr, /uses a curated native cdn\.lil\.org renderer/u);
    assert.doesNotMatch(result.stdout, /MOCK_RPC/u);
  }
});

test("does not conflate valid case-variant Solana public keys with native-renderer IDs", () => {
  for (const [nativeId, caseVariantId] of NATIVE_RENDERER_COLLECTION_IDS.map(
    (nativeId, index) => [nativeId, CASE_VARIANT_COLLECTION_IDS[index]]
  )) {
    assert.notEqual(caseVariantId, nativeId);
    assert.equal(caseVariantId.toLowerCase(), nativeId.toLowerCase());
    assert.equal(decodedBase58ByteLength(caseVariantId), 32);

    const result = runBundler(caseVariantId);

    assert.equal(result.status, 1);
    assert.doesNotMatch(result.stderr, /uses a curated native cdn\.lil\.org renderer/u);
    assert.match(result.stderr, /No assets found/u);
    assert.match(result.stdout, new RegExp(`MOCK_RPC getAssetsByGroup ${caseVariantId}`, "u"));
  }
});

test("rejects an exact native-renderer ID discovered from a token lookup", () => {
  const tokenId = "11111111111111111111111111111111";

  for (const collectionId of NATIVE_RENDERER_COLLECTION_IDS) {
    const result = runBundler(tokenId, { resolvedCollectionId: collectionId });

    assert.equal(result.status, 1);
    assert.match(result.stderr, /uses a curated native cdn\.lil\.org renderer/u);
    assert.match(result.stdout, new RegExp(`MOCK_RPC getAssetsByGroup ${tokenId}`, "u"));
    assert.match(result.stdout, new RegExp(`MOCK_RPC getAsset ${tokenId}`, "u"));
    assert.doesNotMatch(result.stdout, new RegExp(`MOCK_RPC getAssetsByGroup ${collectionId}`, "u"));
  }
});

test("continues resolving known token aliases to their canonical collection ID", () => {
  const aliasId = "GCrHWAXj2dSyHtevh98HBvVFc3BcAJb9DK4skJTMWBEL";
  const canonicalId = "GVQ4Zsd7jLZbVCxq9QsmQySuKekwT1XbMSjGbwt8UtcB";
  const result = runBundler(aliasId);

  assert.equal(result.status, 1);
  assert.match(result.stdout, new RegExp(`Fetching ${aliasId} -> ${canonicalId}`, "u"));
  assert.match(result.stdout, new RegExp(`MOCK_RPC getAssetsByGroup ${canonicalId}`, "u"));
  assert.doesNotMatch(result.stderr, /uses a curated native cdn\.lil\.org renderer/u);
});

test("Solana bundling preserves media hints without reparsing source URLs", async (t) => {
  const tokenIds = ["BQGjKNV22ZD8AaEFZXNftV7xn3LrGbujfNQXCjQSBnhW", "EazEpagtyeRAx9npnpVMpygoA8ouX7DRpLTghhPvYTiu"];
  for (const [urls, prefix] of [
    [["https://assets.example/art/1.png", "https://assets.example/art/2.png"], "https://assets.example/art/"],
    [["https://assets.example/art/one/1.png", "https://assets.example/art/two/2.png"], "https://assets.example/art/"],
    [["https://assets.example/1.png", "https://other.example/2.png"], ""],
    [["https://assets.example/1", "https://assets.example/2"], "https://assets.example/"],
    [["https://assets.example/1?ext=png", "https://assets.example/2?ext=png"], "https://assets.example/"],
    [["https://assets.example/1.png", "https://assets.example/collection.v1%2F42"], "https://assets.example/"],
    [["https://assets.example/1.png", "https://bad host.example/42.png"], ""],
  ]) {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-player-solana-prefix-"));
    t.after(() => fs.rm(directory, { recursive: true, force: true }));
    await fs.writeFile(path.join(directory, "items.json"), "[]");
    const result = runBundler("9irtKRLZkY4MjFFQNZPX3o6ZTszfR8kXFJXPBUvEDo9v", {
      assets: urls.map((url, index) => ({
        id: tokenIds[index],
        content: {
          metadata: { name: `Planet Peppa #${index}`, symbol: "Planet Peppa" },
          files: [{ uri: url, mime: "image/png" }],
        },
      })),
      args: [
        "--apply", "--bundle", directory,
        "--report", path.join(directory, "report.md"),
        "--json-report", path.join(directory, "report.json"),
      ],
    });
    assert.equal(result.status, 0, result.stderr);
    const payload = JSON.parse(await fs.readFile(path.join(directory, "Tokens", "planet_peppa.json"), "utf8"));
    assert.equal(payload.urlPrefix, prefix);
    assert.equal(Object.hasOwn(payload, "urlPrefixes"), false);
    assert.equal(Object.hasOwn(payload, "defaultFileExtension"), false);
    assert.equal(Object.hasOwn(payload, "isComplete"), false);
    assert.deepEqual(payload.items, urls.map((url, index) => ({ id: tokenIds[index], urlSuffix: url.slice(prefix.length), fileExtension: "png" })));
    assert.deepEqual(payload.items.map((row) => payload.urlPrefix + row.urlSuffix), urls);
  }
});

test("apply preserves explicit mid availability and leaves legacy manifests unset", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-player-solana-bundle-"));
  const collectionId = "9irtKRLZkY4MjFFQNZPX3o6ZTszfR8kXFJXPBUvEDo9v";
  const tokenId = "BQGjKNV22ZD8AaEFZXNftV7xn3LrGbujfNQXCjQSBnhW";
  const tokenPath = path.join(directory, "Tokens", "planet_peppa.json");
  const options = {
    assets: [{
      id: tokenId,
      content: {
        metadata: { name: "Planet Peppa #0", symbol: "Planet Peppa" },
        files: [{ uri: "https://cdn.lil.org/player/planet_peppa/0.webp", mime: "image/webp" }],
      },
    }],
    args: [
      "--apply", "--bundle", directory,
      "--report", path.join(directory, "report.md"),
      "--json-report", path.join(directory, "report.json"),
    ],
  };

  try {
    await fs.mkdir(path.dirname(tokenPath));
    await fs.writeFile(path.join(directory, "items.json"), "[]");

    for (const hasMid of [false, true, undefined, null]) {
      const original = {
        hasMid,
        urlPrefix: "https://cdn.lil.org/player/planet_peppa/",
        items: [{ id: tokenId, urlSuffix: "0.webp", fileExtension: "webp" }],
        aspectRatio: [1, 1],
      };
      await fs.writeFile(tokenPath, JSON.stringify(original));

      const result = runBundler(collectionId, options);
      assert.equal(result.status, 0, result.stderr);
      const updated = JSON.parse(await fs.readFile(tokenPath, "utf8"));
      assert.equal(Object.hasOwn(updated, "hasMid"), typeof hasMid === "boolean");
      assert.equal(updated.hasMid, typeof hasMid === "boolean" ? hasMid : undefined);
      assert.deepEqual(updated.items, original.items);
      assert.deepEqual(updated.aspectRatio, original.aspectRatio);
    }

    await fs.unlink(tokenPath);
    const result = runBundler(collectionId, options);
    assert.equal(result.status, 0, result.stderr);
    const created = JSON.parse(await fs.readFile(tokenPath, "utf8"));
    assert.equal(Object.hasOwn(created, "hasMid"), false);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("Solana dry runs preserve curated slugs when the fetched collection name changes", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-player-solana-slug-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const collectionId = "9irtKRLZkY4MjFFQNZPX3o6ZTszfR8kXFJXPBUvEDo9v";
  const itemsPath = path.join(directory, "items.json");
  const original = JSON.stringify([{
    address: collectionId,
    chain: "solana",
    name: "Old Name",
    internal_slug: "curated_collection",
  }]);
  await fs.writeFile(itemsPath, original);
  const result = runBundler(collectionId, {
    assets: [{
      id: "BQGjKNV22ZD8AaEFZXNftV7xn3LrGbujfNQXCjQSBnhW",
      content: {
        metadata: { name: "Planet Peppa #0", symbol: "Planet Peppa" },
        files: [{ uri: "https://cdn.lil.org/player/planet_peppa/0.webp", mime: "image/webp" }],
      },
    }],
    args: [
      "--dry-run", "--bundle", directory,
      "--covers", path.join(directory, "covers"),
      "--report", path.join(directory, "report.md"),
      "--json-report", path.join(directory, "report.json"),
    ],
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(await fs.readFile(itemsPath, "utf8"), original);
  const report = JSON.parse(await fs.readFile(path.join(directory, "report.json"), "utf8"));
  assert.equal(report.collections[0].internal_slug, "curated_collection");
  assert.equal(report.collections[0].cover.outputPath, path.join(directory, "covers", "curated_collection.jpg"));
  await assert.rejects(fs.access(path.join(directory, "Tokens")), { code: "ENOENT" });
});
