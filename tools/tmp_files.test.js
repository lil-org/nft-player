const assert = require("node:assert/strict");
const test = require("node:test");

const {
  isValidTmpFileName,
  preserveTmpFiles,
  reportTmpFilesChanges,
} = require("./tmp_files");

test("preserves only valid tmp_files for token IDs that remain", () => {
  const existingCollection = {
    tmp_files: {
      stale: "99.jpg",
      2: "2.png",
      1: "1.jpg",
      invalid: "nested/3.jpg",
    },
  };
  const nextRows = [{ id: "2", urlSuffix: "new-2", fileExtension: "png" }, { id: "1", urlSuffix: "new-1", fileExtension: "jpg" }];
  const nextPayload = {
    items: nextRows,
  };

  const { payload, report } = preserveTmpFiles(existingCollection, nextPayload);

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
    { items: [{ id: "current", urlSuffix: "current.jpg" }] }
  );

  assert.equal(Object.hasOwn(payload, "tmp_files"), false);
  assert.deepEqual(report.staleIds, ["stale"]);
  assert.deepEqual(report.invalidIds, ["current"]);
});

test("missing collection metadata is a no-op", () => {
  const nextPayload = { items: [{ id: "1", urlSuffix: "1.jpg" }] };
  const { payload, report } = preserveTmpFiles(null, nextPayload);
  assert.deepEqual(payload, nextPayload);
  assert.equal(report.sourceExists, false);
  assert.deepEqual(report.preservedIds, []);
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
