const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
  isValidTmpFileName,
  preserveTmpFiles,
  preserveTmpFilesFromFile,
  reportTmpFilesChanges,
} = require("./tmp_files");

test("preserves only valid tmp_files for token IDs that remain", () => {
  const existingPayload = {
    items: [["1", 0, "old-1"], ["2", 0, "old-2"], ["stale", 0, "old-stale"]],
    tmp_files: {
      stale: "99.jpg",
      2: "2.png",
      1: "1.jpg",
      invalid: "nested/3.jpg",
    },
  };
  const nextRows = [["2", 1, "new-2", "png"], ["1", 0, "new-1"]];
  const nextPayload = {
    defaultFileExtension: "jpg",
    urlPrefixes: ["https://example.com/"],
    items: nextRows,
  };

  const { payload, report } = preserveTmpFiles(existingPayload, nextPayload);

  assert.deepEqual(payload, {
    ...nextPayload,
    tmp_files: {
      2: "2.png",
      1: "1.jpg",
    },
  });
  assert.deepEqual(payload.items, nextRows);
  assert.deepEqual(report.preservedIds, ["2", "1"]);
  assert.deepEqual(report.staleIds, ["stale"]);
  assert.deepEqual(report.invalidIds, ["invalid"]);
});

test("omits tmp_files when no valid current entries remain", () => {
  const { payload, report } = preserveTmpFiles(
    { tmp_files: { stale: "stale.jpg", current: "../current.jpg" } },
    { items: [["current", 0, "current.jpg"]] }
  );

  assert.equal(Object.hasOwn(payload, "tmp_files"), false);
  assert.deepEqual(report.staleIds, ["stale"]);
  assert.deepEqual(report.invalidIds, ["current"]);
});

test("missing existing token payload is a no-op", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-player-tmp-files-"));
  const nextPayload = { items: [["1", 0, "1.jpg"]] };
  try {
    const { payload, report } = await preserveTmpFilesFromFile(path.join(directory, "missing.json"), nextPayload);
    assert.deepEqual(payload, nextPayload);
    assert.equal(report.sourceExists, false);
    assert.deepEqual(report.preservedIds, []);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("rejects unsafe or extensionless file names", () => {
  for (const value of ["", " 1.jpg", "1.jpg ", "1", ".jpg", "../1.jpg", "nested/1.jpg", "nested\\1.jpg", "bad\0.jpg"]) {
    assert.equal(isValidTmpFileName(value), false, String(value));
  }
  for (const value of ["0.jpg", "33.png", "mint-address.mp4", "0.final.gif"]) {
    assert.equal(isValidTmpFileName(value), true, value);
  }
});

test("reports invalid and stale entries", () => {
  const warnings = [];
  reportTmpFilesChanges("collection-id", {
    invalidMap: false,
    invalidIds: ["bad"],
    staleIds: ["gone"],
  }, { warn: (message) => warnings.push(message) });

  assert.equal(warnings.length, 2);
  assert.match(warnings[0], /invalid tmp_files entry.*bad/u);
  assert.match(warnings[1], /stale tmp_files entry.*gone/u);
});
