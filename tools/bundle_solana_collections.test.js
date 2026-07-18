"use strict";

const assert = require("node:assert/strict");
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

function runBundler(input, { resolvedCollectionId = null } = {}) {
  const harness = `
global.fetch = async (_url, options) => {
  const request = JSON.parse(options.body);
  const result = request.method === "getAssetsByGroup"
    ? { items: [], total: 0, page: 1, limit: 1000 }
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
