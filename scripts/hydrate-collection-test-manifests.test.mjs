import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { collectionManifestDescriptors, hydrateCollectionTestManifests } from "./hydrate-collection-test-manifests.mjs";

async function fixture(t) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-collection-manifests-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const itemsPath = path.join(directory, "items.json");
  const outputDirectory = path.join(directory, "CollectionManifests");
  await fs.writeFile(itemsPath, JSON.stringify([{ internal_slug: "sample", bundledTokenCount: 2 }]));
  return { itemsPath, outputDirectory };
}

const validData = Buffer.from('{"version":2,"count":2,"firstId":"1"}\n');

test("descriptors use collection slugs and omit the native ranged collection", () => {
  assert.deepEqual(collectionManifestDescriptors([
    { internal_slug: "fidenza", bundledTokenCount: 1 },
    { internal_slug: "card_nft_2", script: { kind: "native.card-nft-2" } },
  ]), [{ slug: "fidenza", filename: "fidenza.json", url: "https://cdn.lil.org/player/collections/fidenza.json", count: 1 }]);
  for (const items of [{}, [{ internal_slug: "../sample", bundledTokenCount: 1 }],
    [{ internal_slug: "sample" }], [{ internal_slug: "sample", bundledTokenCount: -1 }]]) {
    assert.throws(() => collectionManifestDescriptors(items));
  }
});

test("hydration downloads once and remains usable with an offline transport", async (t) => {
  const options = await fixture(t);
  let calls = 0;
  const transport = async (url) => {
    calls += 1;
    assert.equal(url, "https://cdn.lil.org/player/collections/sample.json");
    return { statusCode: 200, data: validData };
  };
  assert.deepEqual(await hydrateCollectionTestManifests({ ...options, transport }), { manifests: 1, cached: 0, downloaded: 1 });
  const offline = async () => { throw new Error("offline"); };
  assert.deepEqual(await hydrateCollectionTestManifests({ ...options, transport: offline }), { manifests: 1, cached: 1, downloaded: 0 });
  await hydrateCollectionTestManifests({ ...options, check: true, transport: offline });
  assert.equal(calls, 1);
  assert.deepEqual(await fs.readFile(path.join(options.outputDirectory, "sample.json")), validData);
});

test("check is offline and read-only when fixtures are missing or corrupt", async (t) => {
  const options = await fixture(t);
  const transport = async () => { assert.fail("check must not download"); };
  await assert.rejects(hydrateCollectionTestManifests({ ...options, check: true, transport }), /missing or corrupt/u);
  await assert.rejects(fs.access(options.outputDirectory), { code: "ENOENT" });
  await fs.mkdir(options.outputDirectory);
  const file = path.join(options.outputDirectory, "sample.json");
  await fs.writeFile(file, "corrupt");
  await assert.rejects(hydrateCollectionTestManifests({ ...options, check: true, transport }), /missing or corrupt/u);
  assert.equal(await fs.readFile(file, "utf8"), "corrupt");
});

test("invalid HTTP responses, schema, and counts never become fixtures", async (t) => {
  const options = await fixture(t);
  for (const response of [
    { statusCode: 404, data: validData },
    { statusCode: 200, data: Buffer.from("<html>error</html>") },
    { statusCode: 200, data: Buffer.from('{"items":[{"id":"1"},{"id":"2"}]}') },
    { statusCode: 200, data: Buffer.from('{"version":2,"count":1,"firstId":"1"}') },
    { statusCode: 200, data: Buffer.from('{"version":2,"count":2,"ids":[]}') },
  ]) {
    await assert.rejects(hydrateCollectionTestManifests({ ...options, transport: async () => response }));
    assert.deepEqual(await fs.readdir(options.outputDirectory), []);
  }
});

test("corrupt fixtures are replaced only after a valid download", async (t) => {
  const options = await fixture(t);
  await fs.mkdir(options.outputDirectory);
  const file = path.join(options.outputDirectory, "sample.json");
  await fs.writeFile(file, "corrupt");
  await assert.rejects(hydrateCollectionTestManifests({ ...options, transport: async () => ({ statusCode: 200, data: Buffer.from("{}")} ) }));
  assert.equal(await fs.readFile(file, "utf8"), "corrupt");
  await hydrateCollectionTestManifests({ ...options, transport: async () => ({ statusCode: 200, data: validData }) });
  assert.deepEqual(await fs.readFile(file), validData);
  assert.deepEqual(await fs.readdir(options.outputDirectory), ["sample.json"]);
});
