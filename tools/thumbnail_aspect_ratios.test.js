"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
  ASPECT_RATIOS_KEY,
  ASPECT_RATIO_OVERRIDES_KEY,
  collectionBrowserColumnCountFromAspectRatios,
  decodeAspectRatioMetadata,
  encodeAspectRatioMetadata,
  preserveAspectRatioMetadataFromFile,
  reportAspectRatioMetadataChanges,
  tokenIdsFromPayload,
} = require("./thumbnail_aspect_ratios");

test("extracts token IDs from compact and object payloads", () => {
  assert.deepEqual(
    tokenIdsFromPayload({
      items: [
        ["compact", 0, "compact.png"],
        { id: "object", url: "https://example.com/object.png" },
        [42, 0, "numeric.png"],
      ],
    }),
    ["compact", "object", "42"]
  );
});

test("encodes normalized ratios by frequency and first appearance", () => {
  assert.deepEqual(
    encodeAspectRatioMetadata([
      [1920, 1080],
      [640, 480],
      [1280, 720],
      [800, 600],
      [400, 400],
    ]),
    {
      [ASPECT_RATIOS_KEY]: [[16, 9], [4, 3], [1, 1]],
      [ASPECT_RATIO_OVERRIDES_KEY]: [[1, 1], [3, 1], [4, 2]],
    }
  );
});

test("decodes normalized defaults and overrides", () => {
  assert.deepEqual(
    decodeAspectRatioMetadata({
      items: [["a"], ["b"], ["c"]],
      [ASPECT_RATIOS_KEY]: [[32, 18], [8, 6]],
      [ASPECT_RATIO_OVERRIDES_KEY]: [[1, 1]],
    }),
    [[16, 9], [4, 3], [16, 9]]
  );
  assert.equal(decodeAspectRatioMetadata({ items: [["a"]] }), null);
});

test("uses two columns when landscape ratios strictly outnumber portrait ratios", () => {
  assert.equal(
    collectionBrowserColumnCountFromAspectRatios([
      [16, 9],
      [4, 3],
      [3, 4],
    ]),
    2
  );
});

test("uses three columns for portrait dominance and orientation ties", () => {
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

test("ignores square ratios when classifying the collection browser layout", () => {
  assert.equal(
    collectionBrowserColumnCountFromAspectRatios([
      [1, 1],
      [400, 400],
      [16, 9],
    ]),
    2
  );
  assert.equal(
    collectionBrowserColumnCountFromAspectRatios([
      [1, 1],
      [400, 400],
    ]),
    3
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

test("rejects malformed aspect-ratio metadata", () => {
  const validItems = [["a"], ["b"]];
  const invalidPayloads = [
    { items: validItems, [ASPECT_RATIO_OVERRIDES_KEY]: [] },
    { items: validItems, [ASPECT_RATIOS_KEY]: [] },
    { items: validItems, [ASPECT_RATIOS_KEY]: [[1, 1], [2, 2]] },
    { items: validItems, [ASPECT_RATIOS_KEY]: [[1]] },
    { items: validItems, [ASPECT_RATIOS_KEY]: [[1, 1, 1]] },
    { items: validItems, [ASPECT_RATIOS_KEY]: [[0, 1]] },
    { items: validItems, [ASPECT_RATIOS_KEY]: [[1.5, 1]] },
    { items: validItems, [ASPECT_RATIOS_KEY]: [["1", 1]] },
    {
      items: validItems,
      [ASPECT_RATIOS_KEY]: [[1, 1], [4, 3]],
      [ASPECT_RATIO_OVERRIDES_KEY]: {},
    },
    {
      items: validItems,
      [ASPECT_RATIOS_KEY]: [[1, 1], [4, 3]],
      [ASPECT_RATIO_OVERRIDES_KEY]: [[0]],
    },
    {
      items: validItems,
      [ASPECT_RATIOS_KEY]: [[1, 1], [4, 3]],
      [ASPECT_RATIO_OVERRIDES_KEY]: [[-1, 1]],
    },
    {
      items: validItems,
      [ASPECT_RATIOS_KEY]: [[1, 1], [4, 3]],
      [ASPECT_RATIO_OVERRIDES_KEY]: [[2, 1]],
    },
    {
      items: validItems,
      [ASPECT_RATIOS_KEY]: [[1, 1], [4, 3]],
      [ASPECT_RATIO_OVERRIDES_KEY]: [[0, 0]],
    },
    {
      items: validItems,
      [ASPECT_RATIOS_KEY]: [[1, 1], [4, 3]],
      [ASPECT_RATIO_OVERRIDES_KEY]: [[0, 2]],
    },
    {
      items: validItems,
      [ASPECT_RATIOS_KEY]: [[1, 1], [4, 3]],
      [ASPECT_RATIO_OVERRIDES_KEY]: [[0, 1], [0, 1]],
    },
  ];

  for (const payload of invalidPayloads) {
    assert.throws(() => decodeAspectRatioMetadata(payload));
  }
});

test("preserves ratios by token ID across reorder and removal", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-player-aspect-ratios-"));
  const filePath = path.join(directory, "tokens.json");
  const existingPayload = {
    items: [["a"], ["b"], ["c"]],
    [ASPECT_RATIOS_KEY]: [[16, 9], [4, 3]],
    [ASPECT_RATIO_OVERRIDES_KEY]: [[1, 1]],
  };
  await fs.writeFile(filePath, JSON.stringify(existingPayload));

  try {
    const result = await preserveAspectRatioMetadataFromFile(
      filePath,
      { items: [["c"], ["b"]] }
    );
    assert.deepEqual(result.payload, {
      items: [["c"], ["b"]],
      [ASPECT_RATIOS_KEY]: [[16, 9], [4, 3]],
      [ASPECT_RATIO_OVERRIDES_KEY]: [[1, 1]],
    });
    assert.deepEqual(result.report, {
      sourceExists: true,
      metadataExists: true,
      preservedIds: ["c", "b"],
      staleIds: ["a"],
      missingIds: [],
    });
    assert.equal(result.collectionBrowserColumnCount, 2);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("omits metadata when a new token has no preserved ratio", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-player-aspect-ratios-"));
  const filePath = path.join(directory, "tokens.json");
  await fs.writeFile(filePath, JSON.stringify({
    items: [["a"]],
    [ASPECT_RATIOS_KEY]: [[16, 9]],
  }));

  try {
    const result = await preserveAspectRatioMetadataFromFile(
      filePath,
      {
        items: [["a"], ["new"]],
        [ASPECT_RATIOS_KEY]: [[1, 1]],
      }
    );
    assert.deepEqual(result.payload, { items: [["a"], ["new"]] });
    assert.deepEqual(result.report.missingIds, ["new"]);
    assert.deepEqual(result.report.preservedIds, []);
    assert.equal(result.collectionBrowserColumnCount, null);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("missing source leaves the next payload without stale metadata", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-player-aspect-ratios-"));
  try {
    const result = await preserveAspectRatioMetadataFromFile(
      path.join(directory, "missing.json"),
      {
        items: [["a"]],
        [ASPECT_RATIOS_KEY]: [[1, 1]],
      }
    );
    assert.deepEqual(result.payload, { items: [["a"]] });
    assert.equal(result.report.sourceExists, false);
    assert.equal(result.report.metadataExists, false);
    assert.equal(result.collectionBrowserColumnCount, null);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
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
