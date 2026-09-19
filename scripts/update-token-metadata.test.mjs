import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { tokenMetadata, updateTokenMetadata } from "./update-token-metadata.mjs";
import suggestedItems from "../tools/suggested_items.js";
import tokenManifest from "../tools/token_manifest.js";

const { decodeTokenManifest } = tokenManifest;

async function fixture(t, items, manifests) {
  const bundleDirectory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-token-metadata-"));
  t.after(() => fs.rm(bundleDirectory, { recursive: true, force: true }));
  await fs.mkdir(path.join(bundleDirectory, "Tokens"));
  const itemsPath = path.join(bundleDirectory, "items.json");
  await fs.writeFile(itemsPath, `${JSON.stringify(items, null, 2)}\n`);
  for (const [slug, payload] of Object.entries(manifests)) {
    await fs.writeFile(path.join(bundleDirectory, "Tokens", `${slug}.json`), JSON.stringify(payload));
  }
  return { bundleDirectory, itemsPath };
}

test("counts bundled rows and recognizes normalized ratios and inherited defaults", () => {
  assert.deepEqual(tokenMetadata({ internal_slug: "sample", aspectRatio: [8, 6] }, {
    items: [{ id: "1" }, { id: "7", aspectRatio: [4, 3] }, { id: "42", aspectRatio: null }],
  }), { bundledTokenCount: 3, hasUniformAspectRatio: true });
});

test("requires every effective ratio to match an existing collection default", () => {
  assert.deepEqual(tokenMetadata({ internal_slug: "sample", aspectRatio: [4, 3] }, {
    items: [{ id: "1" }, { id: "2", aspectRatio: [1, 1] }],
  }), { bundledTokenCount: 2, hasUniformAspectRatio: false });
  for (const items of [[{ id: "1" }], [{ id: "1", aspectRatio: [4, 3] }]]) {
    assert.deepEqual(tokenMetadata({ internal_slug: "sample" }, { items }), {
      bundledTokenCount: 1, hasUniformAspectRatio: false,
    });
  }
});

test("empty manifests have zero tokens and are never uniform", () => {
  for (const aspectRatio of [undefined, [1, 1]]) {
    assert.deepEqual(tokenMetadata({ internal_slug: "empty", aspectRatio }, { items: [] }), {
      bundledTokenCount: 0, hasUniformAspectRatio: false,
    });
  }
});

test("rejects invalid collection and token ratios even when no uniform fast path applies", () => {
  for (const ratio of [[0, 1], [1, -1], [1.5, 2], [1], [1, 1, 1], "1:1", [Number.MAX_SAFE_INTEGER + 1, 1]]) {
    assert.throws(() => tokenMetadata({ internal_slug: "sample", aspectRatio: ratio }, { items: [] }), /integer pair/u);
    assert.throws(() => tokenMetadata({ internal_slug: "sample" }, {
      items: [{ id: "1" }, { id: "2", aspectRatio: ratio }],
    }), /integer pair/u);
  }
});

test("rejects malformed token payloads and values that the runtime cannot decode", () => {
  for (const payload of [null, [], {}, { items: {} }, { items: [null] }, { items: [[]] },
    { items: [{}] }, { items: [{ id: 1 }] }, { items: [{ id: "" }] },
    { items: [{ id: "1", name: 1 }] }, { items: [{ id: "1", urlSuffix: {} }] },
    { items: [{ id: "1", hash: false }] }, { items: [{ id: "1", contractParameters: [] }] },
    { items: [{ id: "1", contractParameters: { count: 1 } }] }]) {
    assert.throws(() => tokenMetadata({ internal_slug: "sample" }, payload), /sample:/u);
  }
});

test("updates deterministically while preserving tokenCount values and absence", async (t) => {
  const items = [
    { internal_slug: "counted", chain: "ethereum", tokenCount: 2, aspectRatio: [8, 6] },
    { internal_slug: "uncounted" },
    { internal_slug: "zero", tokenCount: 0, aspectRatio: [1, 1] },
  ];
  const { bundleDirectory, itemsPath } = await fixture(t, items, {
    counted: { items: [{ id: "5" }, { id: "9", aspectRatio: [4, 3] }] },
    uncounted: { items: [{ id: "1" }] },
    zero: { items: [] },
  });
  const tokenPath = path.join(bundleDirectory, "Tokens", "counted.json");
  assert.deepEqual(await updateTokenMetadata({ bundleDirectory }), { collections: 3, tokens: 3, updated: 3 });
  const tokenBytes = await fs.readFile(tokenPath);
  assert.deepEqual(JSON.parse(tokenBytes), { version: 2, count: 2, ids: ["5", "9"], aspectRatio: [null, [4, 3]] });
  const generated = await fs.readFile(itemsPath, "utf8");
  assert.deepEqual(JSON.parse(generated), [
    { ...items[0], bundledTokenCount: 2, hasUniformAspectRatio: true },
    { ...items[1], bundledTokenCount: 1, hasUniformAspectRatio: false },
    { ...items[2], bundledTokenCount: 0, hasUniformAspectRatio: false },
  ]);
  assert.deepEqual(await updateTokenMetadata({ bundleDirectory }), { collections: 3, tokens: 3, updated: 0 });
  assert.equal(await fs.readFile(itemsPath, "utf8"), generated);
  await updateTokenMetadata({ bundleDirectory, check: true });
  assert.deepEqual(await fs.readFile(tokenPath), tokenBytes);
});

test("rejects stale downloadable counts in write and check modes without changing files", async (t) => {
  const item = { internal_slug: "sample", chain: "ethereum", tokenCount: 1, aspectRatio: [1, 1] };
  const { bundleDirectory, itemsPath } = await fixture(t, [item], {
    sample: { items: [{ id: "1" }, { id: "2" }] },
  });
  const source = await fs.readFile(itemsPath, "utf8");
  for (const check of [false, true]) {
    await assert.rejects(updateTokenMetadata({ bundleDirectory, check }), /tokenCount is 1, but 2 tokens/u);
    assert.equal(await fs.readFile(itemsPath, "utf8"), source);
  }
});

test("validates filtered media counts using path extensions before the first query hint", async (t) => {
  const collection = { internal_slug: "sample", tokenCount: 4, urlPrefix: "https://example.com/" };
  const suffixes = ["1.PNG", "2?ext=%20.HTML%20", "3?ext=jpg&ext=bad", "4%2Esvg", "5.txt?ext=png", "6?ext=&ext=png", "7?EXT=png", "8?ext=+png+"];
  const payload = { items: suffixes.map((urlSuffix, id) => ({ id: String(id), urlSuffix })) };
  const { bundleDirectory, itemsPath } = await fixture(t, [collection], { sample: payload });
  await updateTokenMetadata({ bundleDirectory });
  assert.equal(JSON.parse(await fs.readFile(itemsPath, "utf8"))[0].bundledTokenCount, 8);
  assert.deepEqual(JSON.parse(await fs.readFile(path.join(bundleDirectory, "Tokens", "sample.json"), "utf8")).excludedMediaIndices, [4, 5, 6, 7]);
  await fs.writeFile(itemsPath, JSON.stringify([{ ...collection, tokenCount: 8 }]));
  await assert.rejects(updateTokenMetadata({ bundleDirectory }), /but 4 tokens/u);
});

test("matches Foundation for literal percent filenames and trailing path whitespace", async (t) => {
  const collection = { internal_slug: "sample", tokenCount: 1, urlPrefix: "https://example.com/" };
  const { bundleDirectory, itemsPath } = await fixture(t, [collection], {
    sample: { items: [{ id: "1", urlSuffix: "artwork-50%.png" }] },
  });
  await updateTokenMetadata({ bundleDirectory });
  await updateTokenMetadata({ bundleDirectory, check: true });
  const source = await fs.readFile(itemsPath, "utf8");
  for (const urlSuffix of ["artwork.png%20", "artwork.png ", "artwork.png/."]) {
    await fs.writeFile(path.join(bundleDirectory, "Tokens", "sample.json"), JSON.stringify({
      items: [{ id: "1", urlSuffix }],
    }));
    for (const check of [false, true]) {
      await assert.rejects(updateTokenMetadata({ bundleDirectory, check }), /tokenCount is 1, but 0 tokens/u);
      assert.equal(await fs.readFile(itemsPath, "utf8"), source);
    }
  }
});

test("leaves counts on generative-only collections independent of downloadable media", async (t) => {
  const { bundleDirectory, itemsPath } = await fixture(t, [{
    internal_slug: "sample", generativeOnly: true, tokenCount: 900,
  }], { sample: { items: [{ id: "1" }] } });
  await updateTokenMetadata({ bundleDirectory });
  assert.equal(JSON.parse(await fs.readFile(itemsPath, "utf8"))[0].bundledTokenCount, 1);
});

test("check detects missing fields, count drift, and ratio drift without writing", async (t) => {
  const item = { internal_slug: "sample", aspectRatio: [1, 1] };
  const { bundleDirectory, itemsPath } = await fixture(t, [item], { sample: { items: [{ id: "1" }] } });
  for (const metadata of [{}, { bundledTokenCount: 1 }, { hasUniformAspectRatio: true },
    { bundledTokenCount: 2, hasUniformAspectRatio: true },
    { bundledTokenCount: 1, hasUniformAspectRatio: false }]) {
    const source = JSON.stringify([{ ...item, ...metadata }]);
    await fs.writeFile(itemsPath, source);
    await assert.rejects(updateTokenMetadata({ bundleDirectory, check: true }), /out of date.*\nsample/su);
    assert.equal(await fs.readFile(itemsPath, "utf8"), source);
  }
  await updateTokenMetadata({ bundleDirectory });
  const source = await fs.readFile(itemsPath, "utf8");
  await fs.writeFile(path.join(bundleDirectory, "Tokens", "sample.json"), JSON.stringify({
    items: [{ id: "1", aspectRatio: [4, 3] }],
  }));
  await assert.rejects(updateTokenMetadata({ bundleDirectory, check: true }), /out of date/u);
  assert.equal(await fs.readFile(itemsPath, "utf8"), source);
});

test("fails missing expected manifests before updating any catalog entries", async (t) => {
  const { bundleDirectory, itemsPath } = await fixture(t, [
    { internal_slug: "present" }, { internal_slug: "missing" },
  ], { present: { items: [{ id: "1" }] } });
  const source = await fs.readFile(itemsPath, "utf8");
  for (const check of [false, true]) {
    await assert.rejects(updateTokenMetadata({ bundleDirectory, check }), /missing: cannot read token manifest/u);
    assert.equal(await fs.readFile(itemsPath, "utf8"), source);
  }
});

test("native ranged card collection omits metadata and requires no token file", async (t) => {
  const native = { internal_slug: "card_nft_2", script: { kind: "native.card-nft-2" } };
  const { bundleDirectory, itemsPath } = await fixture(t, [{
    ...native, bundledTokenCount: 0, hasUniformAspectRatio: false,
  }], {});
  await assert.rejects(updateTokenMetadata({ bundleDirectory, check: true }), /out of date/u);
  assert.deepEqual(await updateTokenMetadata({ bundleDirectory }), { collections: 0, tokens: 0, updated: 1 });
  assert.deepEqual(JSON.parse(await fs.readFile(itemsPath, "utf8")), [native]);
  await updateTokenMetadata({ bundleDirectory, check: true });
  await fs.writeFile(itemsPath, JSON.stringify([{ internal_slug: "card_nft_2", script: { kind: "js" } }]));
  await assert.rejects(updateTokenMetadata({ bundleDirectory }), /cannot read token manifest/u);
});

test("rejects malformed catalog and token JSON without writing", async (t) => {
  const { bundleDirectory, itemsPath } = await fixture(t, [{ internal_slug: "sample" }], {
    sample: { items: [{ id: "1" }] },
  });
  const source = await fs.readFile(itemsPath, "utf8");
  await fs.writeFile(path.join(bundleDirectory, "Tokens", "sample.json"), "{");
  await assert.rejects(updateTokenMetadata({ bundleDirectory }), /sample: cannot read token manifest/u);
  assert.equal(await fs.readFile(itemsPath, "utf8"), source);
  for (const invalid of ["{", "{}", '[{"internal_slug":"../sample"}]',
    '[{"internal_slug":"sample"},{"internal_slug":"sample"}]']) {
    await fs.writeFile(itemsPath, invalid);
    await assert.rejects(updateTokenMetadata({ bundleDirectory }));
    assert.equal(await fs.readFile(itemsPath, "utf8"), invalid);
  }
});

test("collection regeneration preserves generated metadata including zero and false", () => {
  assert.deepEqual(suggestedItems.mergeGeneratedSuggestedItem({
    bundledTokenCount: 0, hasUniformAspectRatio: false,
  }, { name: "Sample" }), { bundledTokenCount: 0, hasUniformAspectRatio: false, name: "Sample" });
});

test("preserves mixed records, duplicate IDs, and source positions while computing exclusions", async (t) => {
  const rows = [
    { id: "same", urlSuffix: "0.txt" },
    { id: "same", urlSuffix: "1.png" },
    { id: "third", urlSuffix: "2.svg" },
    { id: "last", urlSuffix: "3.bin" },
  ];
  const { bundleDirectory } = await fixture(t, [{
    internal_slug: "sample", tokenCount: 2, urlPrefix: "https://example.com/",
  }], { sample: { items: rows } });
  await updateTokenMetadata({ bundleDirectory });
  const payload = JSON.parse(await fs.readFile(path.join(bundleDirectory, "Tokens", "sample.json"), "utf8"));
  assert.deepEqual(payload.excludedMediaIndices, [0, 3]);
  const decoded = decodeTokenManifest(payload);
  assert.deepEqual(decoded.items, rows);
  assert.deepEqual(decoded.items.filter((_, index) => !decoded.excludedMediaIndices.includes(index)), rows.slice(1, 3));
  await updateTokenMetadata({ bundleDirectory, check: true });
});

test("check recomputes eligibility after collection URL changes without writing", async (t) => {
  const item = { internal_slug: "sample", tokenCount: 1, urlPrefix: "https://example.com/" };
  const { bundleDirectory, itemsPath } = await fixture(t, [item], {
    sample: { items: [{ id: "1", urlSuffix: "1.png" }, { id: "2", urlSuffix: "2" }] },
  });
  await updateTokenMetadata({ bundleDirectory });
  const tokenPath = path.join(bundleDirectory, "Tokens", "sample.json");
  const tokenBytes = await fs.readFile(tokenPath, "utf8");
  const catalog = JSON.parse(await fs.readFile(itemsPath, "utf8"));
  catalog[0].urlPrefix = "https://example.com/file.png?token=";
  catalog[0].tokenCount = 2;
  const catalogBytes = JSON.stringify(catalog);
  await fs.writeFile(itemsPath, catalogBytes);
  await assert.rejects(updateTokenMetadata({ bundleDirectory, check: true }), /out of date/u);
  assert.equal(await fs.readFile(itemsPath, "utf8"), catalogBytes);
  assert.equal(await fs.readFile(tokenPath, "utf8"), tokenBytes);
  await updateTokenMetadata({ bundleDirectory });
  assert.equal(JSON.parse(await fs.readFile(tokenPath, "utf8")).excludedMediaIndices, undefined);
  await updateTokenMetadata({ bundleDirectory, check: true });
});

test("validates later inputs before rewriting earlier valid legacy manifests", async (t) => {
  const { bundleDirectory, itemsPath } = await fixture(t, [
    { internal_slug: "first" }, { internal_slug: "bad" },
  ], { first: { items: [{ id: "1" }] }, bad: { version: 2, count: 2, ids: ["1"] } });
  const tokenPath = path.join(bundleDirectory, "Tokens", "first.json");
  const before = await Promise.all([fs.readFile(itemsPath, "utf8"), fs.readFile(tokenPath, "utf8")]);
  await assert.rejects(updateTokenMetadata({ bundleDirectory }), /bad:/u);
  assert.deepEqual(await Promise.all([fs.readFile(itemsPath, "utf8"), fs.readFile(tokenPath, "utf8")]), before);
});
