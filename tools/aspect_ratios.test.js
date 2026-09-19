"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const {
  collectionBrowserColumnCountFromAspectRatios,
  decodeAspectRatioMetadata,
  encodeAspectRatioMetadata,
  preserveAspectRatioMetadataFromFile,
  reportAspectRatioMetadataChanges,
  tokenIdsFromPayload,
} = require("./aspect_ratios");

test("extracts IDs from named token objects and rejects positional rows", () => {
  assert.deepEqual(tokenIdsFromPayload({ items: [{ id: "a" }, { id: 42 }] }), ["a", "42"]);
  assert.throws(() => tokenIdsFromPayload({ items: [["a", "a.png"]] }));
});

test("chooses a normalized default by frequency and first appearance", () => {
  const payload = {
    items: [
      { id: "a", urlSuffix: "a.png", hash: "0xabc" },
      { id: "b", name: "B" },
      { id: "c", aspectRatio: [9, 2] },
      { id: "d" },
      { id: "e" },
    ],
  };
  const original = structuredClone(payload);
  const result = encodeAspectRatioMetadata(payload, [[1920, 1080], [640, 480], [1280, 720], [800, 600], [400, 400]]);
  assert.deepEqual(result.payload, {
    items: [
      { id: "a", urlSuffix: "a.png", hash: "0xabc" },
      { id: "b", name: "B", aspectRatio: [4, 3] },
      { id: "c" },
      { id: "d", aspectRatio: [4, 3] },
      { id: "e", aspectRatio: [1, 1] },
    ],
  });
  assert.deepEqual(result.aspectRatio, [16, 9]);
  assert.deepEqual(payload, original);
  assert.deepEqual(encodeAspectRatioMetadata(result.payload, decodeAspectRatioMetadata(result.payload, result.aspectRatio)), result);
});

test("decodes collection defaults, exceptions, token-only values, and missing values", () => {
  assert.deepEqual(decodeAspectRatioMetadata({
    items: [{ id: "a" }, { id: "b", aspectRatio: [8, 6] }, { id: "c", aspectRatio: null }],
  }, [32, 18]), [[16, 9], [4, 3], [16, 9]]);
  assert.deepEqual(decodeAspectRatioMetadata({
    items: [{ id: "a", aspectRatio: [8, 6] }, { id: "b" }],
  }), [[4, 3], null]);
  assert.equal(decodeAspectRatioMetadata({ items: [{ id: "a" }] }), null);
  assert.equal(decodeAspectRatioMetadata({ items: [{ id: "a", aspectRatio: null }] }, null), null);
});

test("uses two columns when landscape ratios strictly outnumber vertical ratios", () => {
  assert.equal(
    collectionBrowserColumnCountFromAspectRatios([
      [16, 9],
      [4, 3],
      [3, 4],
    ]),
    2
  );
});

test("uses three columns for vertical dominance and orientation ties", () => {
  assert.equal(
    collectionBrowserColumnCountFromAspectRatios([
      [16, 9],
      [3, 4],
      [2, 3],
    ]),
    3
  );
  assert.equal(
    collectionBrowserColumnCountFromAspectRatios([
      [16, 9],
      [3, 4],
    ]),
    3
  );
});

test("counts square ratios as vertical when classifying the collection browser layout", () => {
  assert.equal(
    collectionBrowserColumnCountFromAspectRatios([
      [1, 1],
      [400, 400],
      [16, 9],
    ]),
    3
  );
  assert.equal(
    collectionBrowserColumnCountFromAspectRatios([
      [1, 1],
      [16, 9],
      [4, 3],
    ]),
    2
  );
});

test("rejects malformed ratios while classifying browser columns", () => {
  for (const values of [
    null,
    [],
    [[0, 1]],
    [[1.5, 1]],
    [["16", 9]],
  ]) {
    assert.throws(() => collectionBrowserColumnCountFromAspectRatios(values));
  }
});

test("rejects malformed collection and token ratios", () => {
  for (const aspectRatio of [[], [1], [1, 1, 1], [0, 1], [-1, 1], [1.5, 1], ["1", 1], "1:1", {}]) {
    assert.throws(() => decodeAspectRatioMetadata({ items: [{ id: "a" }] }, aspectRatio));
    assert.throws(() => decodeAspectRatioMetadata({ items: [{ id: "a", aspectRatio }] }, [1, 1]));
    assert.throws(() => encodeAspectRatioMetadata({ items: [{ id: "a" }] }, [aspectRatio]));
  }
  assert.throws(() => encodeAspectRatioMetadata({ items: [{ id: "a" }] }, []));
  assert.throws(() => encodeAspectRatioMetadata({ items: [{ id: "a" }] }, [[1, 1], [1, 1]]));
});

async function preserveFixture(t, existing, next, defaultAspectRatio) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-player-aspect-ratios-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const filePath = path.join(directory, "tokens.json");
  if (existing != null) await fs.writeFile(filePath, JSON.stringify(existing));
  return preserveAspectRatioMetadataFromFile(filePath, next, defaultAspectRatio);
}

test("preserves ratios by token ID across reorder and removal", async (t) => {
  const result = await preserveFixture(t, {
    items: [{ id: "a" }, { id: "b", aspectRatio: [4, 3] }, { id: "c" }],
  }, { items: [{ id: "c" }, { id: "b" }] }, [16, 9]);
  assert.deepEqual(result.payload, {
    items: [{ id: "c" }, { id: "b", aspectRatio: [4, 3] }],
  });
  assert.deepEqual(result.aspectRatio, [16, 9]);
  assert.deepEqual(result.report, {
    sourceExists: true, metadataExists: true,
    preservedIds: ["c", "b"], staleIds: ["a"], missingIds: [],
  });
  assert.equal(result.collectionBrowserColumnCount, 2);
});

test("reselects the most common default after removal", async (t) => {
  const result = await preserveFixture(t, {
    items: [{ id: "a" }, { id: "b", aspectRatio: [4, 3] }],
  }, { items: [{ id: "b" }] }, [16, 9]);
  assert.deepEqual(result.payload, { items: [{ id: "b" }] });
  assert.deepEqual(result.aspectRatio, [4, 3]);
});

test("omits all metadata when a new token has no preserved ratio", async (t) => {
  const result = await preserveFixture(t, {
    items: [{ id: "a" }],
  }, { items: [{ id: "a", aspectRatio: [4, 3] }, { id: "new" }] }, [16, 9]);
  assert.deepEqual(result.payload, { items: [{ id: "a" }, { id: "new" }] });
  assert.deepEqual(result.report.missingIds, ["new"]);
  assert.deepEqual(result.report.preservedIds, []);
  assert.equal(result.collectionBrowserColumnCount, null);
  assert.equal(result.aspectRatio, null);
});

test("reports a retained token with no known ratio as missing", async (t) => {
  const result = await preserveFixture(t, {
    items: [{ id: "a", aspectRatio: [4, 3] }, { id: "b" }],
  }, { items: [{ id: "b" }, { id: "a" }] });
  assert.deepEqual(result.report.missingIds, ["b"]);
  assert.equal(result.aspectRatio, null);
  assert.deepEqual(result.payload, { items: [{ id: "b" }, { id: "a" }] });
});

test("missing source leaves the next payload without stale metadata", async (t) => {
  const result = await preserveFixture(t, null, {
    items: [{ id: "a", aspectRatio: [4, 3] }],
  }, [1, 1]);
  assert.deepEqual(result.payload, { items: [{ id: "a" }] });
  assert.equal(result.report.sourceExists, false);
  assert.equal(result.report.metadataExists, false);
  assert.equal(result.collectionBrowserColumnCount, null);
  assert.equal(result.aspectRatio, null);
});

test("reports missing, stale, and unavailable preservation inputs", () => {
  const warnings = [];
  const logger = { warn: (message) => warnings.push(message) };
  reportAspectRatioMetadataChanges("collection", {
    sourceExists: true,
    metadataExists: true,
    preservedIds: [],
    missingIds: ["new"],
    staleIds: ["old"],
  }, logger);
  reportAspectRatioMetadataChanges("new-collection", {
    sourceExists: false,
    metadataExists: false,
    preservedIds: [],
    missingIds: [],
    staleIds: [],
  }, logger);

  assert.equal(warnings.length, 3);
  assert.match(warnings[0], /no existing ratio.*new/u);
  assert.match(warnings[1], /stale token id.*old/u);
  assert.match(warnings[2], /No existing token payload/u);
});

test("does not read collection defaults from the token payload", () => {
  assert.equal(decodeAspectRatioMetadata({ aspectRatio: [1, 1], items: [{ id: "a" }] }), null);
  assert.deepEqual(decodeAspectRatioMetadata({ aspectRatio: [1, 1], items: [{ id: "a" }] }, [4, 3]), [[4, 3]]);
});
