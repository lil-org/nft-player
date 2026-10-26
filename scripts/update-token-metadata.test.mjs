import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { tokenMetadata, updateTokenMetadata } from "./update-token-metadata.mjs";
import tokenManifest from "../tools/token_manifest.js";

const { decodeTokenManifest, encodeTokenManifest } = tokenManifest;

async function fixture(t, items, manifests) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-token-metadata-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const manifestDirectory = path.join(directory, "manifests");
  await fs.mkdir(manifestDirectory);
  const itemsPath = path.join(directory, "items.json");
  await fs.writeFile(itemsPath, `${JSON.stringify(items, null, 2)}\n`);
  for (const [slug, payload] of Object.entries(manifests)) {
    await fs.writeFile(path.join(manifestDirectory, `${slug}.json`), JSON.stringify(payload));
  }
  return { manifestDirectory, itemsPath };
}

test("counts manifest rows and recognizes normalized ratios and inherited defaults", () => {
  assert.deepEqual(tokenMetadata({ internal_slug: "sample", aspectRatio: [8, 6] }, {
    version: 2, count: 3, ids: ["1", "7", "42"], aspectRatio: [null, [4, 3], null],
  }), { manifestTokenCount: 3, hasUniformAspectRatio: true });
});

test("requires every effective ratio to match an existing collection default", () => {
  assert.deepEqual(tokenMetadata({ internal_slug: "sample", aspectRatio: [4, 3] }, {
    version: 2, count: 2, firstId: "1", aspectRatio: [null, [1, 1]],
  }), { manifestTokenCount: 2, hasUniformAspectRatio: false });
  for (const aspectRatio of [undefined, [[4, 3]]]) {
    assert.deepEqual(tokenMetadata({ internal_slug: "sample" }, {
      version: 2, count: 1, firstId: "1", ...(aspectRatio ? { aspectRatio } : {}),
    }), { manifestTokenCount: 1, hasUniformAspectRatio: false });
  }
});

test("empty manifests have zero tokens and are never uniform", () => {
  for (const aspectRatio of [undefined, [1, 1]]) {
    assert.deepEqual(tokenMetadata({ internal_slug: "empty", aspectRatio }, {
      version: 2, count: 0, ids: [],
    }), { manifestTokenCount: 0, hasUniformAspectRatio: false });
  }
});

test("rejects invalid collection and token ratios even when no uniform fast path applies", () => {
  for (const ratio of [[0, 1], [1, -1], [1.5, 2], [1], [1, 1, 1], "1:1", [Number.MAX_SAFE_INTEGER + 1, 1]]) {
    assert.throws(() => tokenMetadata({ internal_slug: "sample", aspectRatio: ratio }, {
      version: 2, count: 0, ids: [],
    }), /integer pair/u);
    assert.throws(() => tokenMetadata({ internal_slug: "sample" }, {
      version: 2, count: 2, firstId: "1", aspectRatio: [null, ratio],
    }), /integer pair/u);
  }
});

test("rejects legacy and malformed manifests with collection context", () => {
  for (const payload of [null, [], {}, { items: [] }, { version: 1, count: 0, ids: [] },
    { version: 2, count: 1, ids: [1] }, { version: 2, count: 1, ids: [""] },
    { version: 2, count: 1, firstId: "1", name: [1] },
    { version: 2, count: 1, firstId: "1", contractParameters: [{ count: 1 }] }]) {
    assert.throws(() => tokenMetadata({ internal_slug: "sample" }, payload), /sample:/u);
  }
});

test("updates deterministically while preserving tokenCount values and absence", async (t) => {
  const items = [
    { internal_slug: "counted", chain: "ethereum", tokenCount: 2, urlPrefix: "https://cdn.lil.org/", aspectRatio: [8, 6] },
    { internal_slug: "uncounted" },
    { internal_slug: "zero", tokenCount: 0, aspectRatio: [1, 1] },
  ];
  const { manifestDirectory, itemsPath } = await fixture(t, items, {
    counted: encodeTokenManifest([{ id: "5", urlSuffix: "5.png" }, { id: "9", urlSuffix: "9.png", aspectRatio: [4, 3] }]),
    uncounted: encodeTokenManifest([{ id: "1" }]),
    zero: encodeTokenManifest([]),
  });
  const tokenPath = path.join(manifestDirectory, "counted.json");
  assert.deepEqual(await updateTokenMetadata({ manifestDirectory, itemsPath }), { collections: 3, tokens: 3, updated: 3 });
  const tokenBytes = await fs.readFile(tokenPath);
  assert.deepEqual(JSON.parse(tokenBytes), { version: 2, count: 2, ids: ["5", "9"], urlTemplate: { value: "id", suffix: ".png" }, aspectRatio: [null, [4, 3]] });
  const generated = await fs.readFile(itemsPath, "utf8");
  assert.deepEqual(JSON.parse(generated), [
    { ...items[0], manifestTokenCount: 2, hasUniformAspectRatio: true },
    { ...items[1], manifestTokenCount: 1, hasUniformAspectRatio: false },
    { ...items[2], manifestTokenCount: 0, hasUniformAspectRatio: false },
  ]);
  assert.deepEqual(await updateTokenMetadata({ manifestDirectory, itemsPath }), { collections: 3, tokens: 3, updated: 0 });
  assert.equal(await fs.readFile(itemsPath, "utf8"), generated);
  await updateTokenMetadata({ manifestDirectory, itemsPath, check: true });
  assert.deepEqual(await fs.readFile(tokenPath), tokenBytes);
});

test("rejects stale downloadable counts in write and check modes without changing files", async (t) => {
  const item = { internal_slug: "sample", chain: "ethereum", tokenCount: 1, urlPrefix: "https://cdn.lil.org/", aspectRatio: [1, 1] };
  const { manifestDirectory, itemsPath } = await fixture(t, [item], {
    sample: encodeTokenManifest([{ id: "1", urlSuffix: "1.png" }, { id: "2", urlSuffix: "2.png" }]),
  });
  const source = await fs.readFile(itemsPath, "utf8");
  for (const check of [false, true]) {
    await assert.rejects(updateTokenMetadata({ manifestDirectory, itemsPath, check }), /tokenCount is 1, but 2 tokens/u);
    assert.equal(await fs.readFile(itemsPath, "utf8"), source);
  }
});

test("validates filtered media counts using path extensions before the first query hint", async (t) => {
  const collection = { internal_slug: "sample", tokenCount: 4, urlPrefix: "https://cdn.lil.org/" };
  const suffixes = ["1.PNG", "2?ext=%20.HTML%20", "3?ext=jpg&ext=bad", "4%2Esvg", "5.txt?ext=png", "6?ext=&ext=png", "7?EXT=png", "8?ext=+png+"];
  const payload = encodeTokenManifest(suffixes.map((urlSuffix, id) => ({ id: String(id), urlSuffix })));
  const { manifestDirectory, itemsPath } = await fixture(t, [collection], { sample: payload });
  await updateTokenMetadata({ manifestDirectory, itemsPath });
  assert.equal(JSON.parse(await fs.readFile(itemsPath, "utf8"))[0].manifestTokenCount, 8);
  assert.deepEqual(JSON.parse(await fs.readFile(path.join(manifestDirectory, "sample.json"), "utf8")).excludedMediaIndices, [4, 5, 6, 7]);
  await fs.writeFile(itemsPath, JSON.stringify([{ ...collection, tokenCount: 8 }]));
  await assert.rejects(updateTokenMetadata({ manifestDirectory, itemsPath }), /but 4 tokens/u);
});

test("excludes missing URLs and external media while preserving CDN and Terraforms sources", async (t) => {
  const urls = [
    null,
    "https://cdn.lil.org/player/sample/1.png",
    "https://tokens.mathcastles.xyz/terraforms/token-html/42?ext=html",
    "https://media-proxy.artblocks.io/0xcontract/1.png",
    "https://cdn.lil.org.example.com/1.png",
    "http://cdn.lil.org/1.png",
    "https://tokens.mathcastles.xyz/other/42?ext=html",
    "https://tokens.mathcastles.xyz/terraforms/token-html/42?ext=png",
  ];
  const rows = urls.map((urlSuffix, id) => ({ id: String(id), ...(urlSuffix == null ? {} : { urlSuffix }) }));
  const { manifestDirectory, itemsPath } = await fixture(t, [{
    internal_slug: "sample", chain: "ethereum", tokenCount: 2,
  }], { sample: encodeTokenManifest(rows) });
  await updateTokenMetadata({ manifestDirectory, itemsPath });
  const payload = JSON.parse(await fs.readFile(path.join(manifestDirectory, "sample.json"), "utf8"));
  assert.deepEqual(payload.excludedMediaIndices, [0, 3, 4, 5, 6, 7]);
  assert.deepEqual(decodeTokenManifest(payload).items, rows);
  await updateTokenMetadata({ manifestDirectory, itemsPath, check: true });
});

test("matches Foundation for literal percent filenames and trailing path whitespace", async (t) => {
  const collection = { internal_slug: "sample", tokenCount: 1, urlPrefix: "https://cdn.lil.org/" };
  const { manifestDirectory, itemsPath } = await fixture(t, [collection], {
    sample: encodeTokenManifest([{ id: "1", urlSuffix: "artwork-50%.png" }]),
  });
  await updateTokenMetadata({ manifestDirectory, itemsPath });
  await updateTokenMetadata({ manifestDirectory, itemsPath, check: true });
  const source = await fs.readFile(itemsPath, "utf8");
  for (const urlSuffix of ["artwork.png%20", "artwork.png ", "artwork.png/."]) {
    await fs.writeFile(path.join(manifestDirectory, "sample.json"), JSON.stringify(encodeTokenManifest([{ id: "1", urlSuffix }])));
    for (const check of [false, true]) {
      await assert.rejects(updateTokenMetadata({ manifestDirectory, itemsPath, check }), /tokenCount is 1, but 0 tokens/u);
      assert.equal(await fs.readFile(itemsPath, "utf8"), source);
    }
  }
});

test("leaves counts on generative-only collections independent of downloadable media", async (t) => {
  const { manifestDirectory, itemsPath } = await fixture(t, [{
    internal_slug: "sample", generativeOnly: true, tokenCount: 900,
  }], { sample: encodeTokenManifest([{ id: "1" }]) });
  await updateTokenMetadata({ manifestDirectory, itemsPath });
  assert.equal(JSON.parse(await fs.readFile(itemsPath, "utf8"))[0].manifestTokenCount, 1);
});

test("check detects missing fields, count drift, and ratio drift without writing", async (t) => {
  const item = { internal_slug: "sample", aspectRatio: [1, 1] };
  const { manifestDirectory, itemsPath } = await fixture(t, [item], { sample: encodeTokenManifest([{ id: "1" }]) });
  for (const metadata of [{}, { manifestTokenCount: 1 }, { hasUniformAspectRatio: true },
    { manifestTokenCount: 2, hasUniformAspectRatio: true },
    { manifestTokenCount: 1, hasUniformAspectRatio: false }]) {
    const source = JSON.stringify([{ ...item, ...metadata }]);
    await fs.writeFile(itemsPath, source);
    await assert.rejects(updateTokenMetadata({ manifestDirectory, itemsPath, check: true }), /out of date.*\nsample/su);
    assert.equal(await fs.readFile(itemsPath, "utf8"), source);
  }
  await updateTokenMetadata({ manifestDirectory, itemsPath });
  const source = await fs.readFile(itemsPath, "utf8");
  await fs.writeFile(path.join(manifestDirectory, "sample.json"), JSON.stringify(encodeTokenManifest([{ id: "1", aspectRatio: [4, 3] }])));
  await assert.rejects(updateTokenMetadata({ manifestDirectory, itemsPath, check: true }), /out of date/u);
  assert.equal(await fs.readFile(itemsPath, "utf8"), source);
});

test("fails missing expected manifests before updating any catalog entries", async (t) => {
  const { manifestDirectory, itemsPath } = await fixture(t, [
    { internal_slug: "present" }, { internal_slug: "missing" },
  ], { present: encodeTokenManifest([{ id: "1" }]) });
  const source = await fs.readFile(itemsPath, "utf8");
  for (const check of [false, true]) {
    await assert.rejects(updateTokenMetadata({ manifestDirectory, itemsPath, check }), /missing: cannot read token manifest/u);
    assert.equal(await fs.readFile(itemsPath, "utf8"), source);
  }
});

test("native ranged card collection omits metadata and requires no token file", async (t) => {
  const native = { internal_slug: "card_nft_2", script: { kind: "native.card-nft-2" } };
  const { manifestDirectory, itemsPath } = await fixture(t, [{
    ...native, manifestTokenCount: 0, hasUniformAspectRatio: false,
  }], {});
  await assert.rejects(updateTokenMetadata({ manifestDirectory, itemsPath, check: true }), /out of date/u);
  assert.deepEqual(await updateTokenMetadata({ manifestDirectory, itemsPath }), { collections: 0, tokens: 0, updated: 1 });
  assert.deepEqual(JSON.parse(await fs.readFile(itemsPath, "utf8")), [native]);
  await updateTokenMetadata({ manifestDirectory, itemsPath, check: true });
  await fs.writeFile(itemsPath, JSON.stringify([{ internal_slug: "card_nft_2", script: { kind: "js" } }]));
  await assert.rejects(updateTokenMetadata({ manifestDirectory, itemsPath }), /cannot read token manifest/u);
});

test("rejects malformed catalog and token JSON without writing", async (t) => {
  const { manifestDirectory, itemsPath } = await fixture(t, [{ internal_slug: "sample" }], {
    sample: encodeTokenManifest([{ id: "1" }]),
  });
  const source = await fs.readFile(itemsPath, "utf8");
  await fs.writeFile(path.join(manifestDirectory, "sample.json"), "{");
  await assert.rejects(updateTokenMetadata({ manifestDirectory, itemsPath }), /sample: cannot read token manifest/u);
  assert.equal(await fs.readFile(itemsPath, "utf8"), source);
  for (const invalid of ["{", "{}", '[{"internal_slug":"../sample"}]',
    '[{"internal_slug":"sample"},{"internal_slug":"sample"}]']) {
    await fs.writeFile(itemsPath, invalid);
    await assert.rejects(updateTokenMetadata({ manifestDirectory, itemsPath }));
    assert.equal(await fs.readFile(itemsPath, "utf8"), invalid);
  }
});

test("preserves mixed records, duplicate IDs, and source positions while computing exclusions", async (t) => {
  const rows = [
    { id: "same", urlSuffix: "0.txt" },
    { id: "same", urlSuffix: "1.png" },
    { id: "third", urlSuffix: "2.svg" },
    { id: "last", urlSuffix: "3.bin" },
  ];
  const { manifestDirectory, itemsPath } = await fixture(t, [{
    internal_slug: "sample", tokenCount: 2, urlPrefix: "https://cdn.lil.org/",
  }], { sample: encodeTokenManifest(rows) });
  await updateTokenMetadata({ manifestDirectory, itemsPath });
  const payload = JSON.parse(await fs.readFile(path.join(manifestDirectory, "sample.json"), "utf8"));
  assert.deepEqual(payload.excludedMediaIndices, [0, 3]);
  const decoded = decodeTokenManifest(payload);
  assert.deepEqual(decoded.items, rows);
  assert.deepEqual(decoded.items.filter((_, index) => !decoded.excludedMediaIndices.includes(index)), rows.slice(1, 3));
  await updateTokenMetadata({ manifestDirectory, itemsPath, check: true });
});

test("check recomputes eligibility after collection URL changes without writing", async (t) => {
  const item = { internal_slug: "sample", tokenCount: 1, urlPrefix: "https://cdn.lil.org/" };
  const { manifestDirectory, itemsPath } = await fixture(t, [item], {
    sample: encodeTokenManifest([{ id: "1", urlSuffix: "1.png" }, { id: "2", urlSuffix: "2" }]),
  });
  await updateTokenMetadata({ manifestDirectory, itemsPath });
  const tokenPath = path.join(manifestDirectory, "sample.json");
  const tokenBytes = await fs.readFile(tokenPath, "utf8");
  const catalog = JSON.parse(await fs.readFile(itemsPath, "utf8"));
  catalog[0].urlPrefix = "https://cdn.lil.org/file.png?token=";
  catalog[0].tokenCount = 2;
  const catalogBytes = JSON.stringify(catalog);
  await fs.writeFile(itemsPath, catalogBytes);
  await assert.rejects(updateTokenMetadata({ manifestDirectory, itemsPath, check: true }), /out of date/u);
  assert.equal(await fs.readFile(itemsPath, "utf8"), catalogBytes);
  assert.equal(await fs.readFile(tokenPath, "utf8"), tokenBytes);
  await updateTokenMetadata({ manifestDirectory, itemsPath });
  assert.equal(JSON.parse(await fs.readFile(tokenPath, "utf8")).excludedMediaIndices, undefined);
  await updateTokenMetadata({ manifestDirectory, itemsPath, check: true });
});

test("validates later inputs before rewriting earlier noncanonical v2 manifests", async (t) => {
  const { manifestDirectory, itemsPath } = await fixture(t, [
    { internal_slug: "first" }, { internal_slug: "bad" },
  ], { first: encodeTokenManifest([{ id: "1" }]), bad: { version: 2, count: 2, ids: ["1"] } });
  const tokenPath = path.join(manifestDirectory, "first.json");
  const before = await Promise.all([fs.readFile(itemsPath, "utf8"), fs.readFile(tokenPath, "utf8")]);
  await assert.rejects(updateTokenMetadata({ manifestDirectory, itemsPath }), /bad:/u);
  assert.deepEqual(await Promise.all([fs.readFile(itemsPath, "utf8"), fs.readFile(tokenPath, "utf8")]), before);
});

test("legacy imports require the explicit importer and never change files", async (t) => {
  const { manifestDirectory, itemsPath } = await fixture(t, [
    { internal_slug: "first" }, { internal_slug: "legacy" },
  ], { first: { version: 2, count: 1, firstId: "1" }, legacy: { items: [{ id: "2" }] } });
  const paths = [itemsPath, path.join(manifestDirectory, "first.json"), path.join(manifestDirectory, "legacy.json")];
  const before = await Promise.all(paths.map((file) => fs.readFile(file, "utf8")));
  for (const check of [false, true]) {
    await assert.rejects(updateTokenMetadata({ manifestDirectory, itemsPath, check }), /legacy: Unsupported token manifest version/u);
    assert.deepEqual(await Promise.all(paths.map((file) => fs.readFile(file, "utf8"))), before);
  }
});
