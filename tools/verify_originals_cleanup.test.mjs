import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  OriginalsCleanupVerificationError,
  detectFileKind,
  verifyOriginalsCleanup,
} from "./verify_originals_cleanup.mjs";

const COLLECTION_ID = "collection-address";
const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const JPEG_SIGNATURE = Buffer.from([0xff, 0xd8, 0xff, 0xe0]);

test("verifies physical mappings, an expected missing row, and a widget subset", async (t) => {
  const root = await makeFixture(t, {
    physicalFiles: { "0.png": PNG_SIGNATURE },
    manifestTokens: [
      { tokenId: "mint-present", fileName: "0.png", status: "success" },
      { tokenId: "mint-missing", fileName: "1.png", status: "missing" },
    ],
    primaryItems: [
      ["mint-present", 0, "0.png"],
      ["mint-missing", 0, "1.png"],
    ],
    primaryTmpFiles: { "mint-present": "0.png" },
    widgetItems: [["mint-present", 0, "0.png"]],
    widgetTmpFiles: { "mint-present": "0.png" },
  });

  const summary = await verifyOriginalsCleanup({
    repoRoot: root,
    expectedPhysicalFiles: 1,
    expectedMissingRows: 1,
    expectedJsonPathManifests: 0,
    expectedOneByteFiles: 0,
    expectedCollectionDirectories: 1,
    expectedWidgetCollectionsWithTmpFiles: 1,
    signatureConcurrency: 2,
  });

  assert.equal(summary.primaryMappedFiles, 1);
  assert.equal(summary.signatureCounts.png, 1);
  assert.equal(summary.widgetCollectionsWithTmpFiles, 1);
});

test("rejects unreferenced media, .jpeg, and a signature/extension mismatch", async (t) => {
  const root = await makeFixture(t, {
    physicalFiles: {
      "0.png": PNG_SIGNATURE,
      "1.jpeg": JPEG_SIGNATURE,
    },
    manifestTokens: [{ tokenId: "mint-present", fileName: "0.png", status: "success" }],
    primaryItems: [["mint-present", 0, "0.png"]],
    primaryTmpFiles: { "mint-present": "0.png" },
    widgetItems: [["mint-present", 0, "0.png"]],
    widgetTmpFiles: { "mint-present": "0.png" },
  });

  await assert.rejects(
    verifyOriginalsCleanup({
      repoRoot: root,
      expectedPhysicalFiles: 2,
      expectedMissingRows: 0,
      expectedJsonPathManifests: 0,
      expectedOneByteFiles: 0,
      expectedCollectionDirectories: 1,
      expectedWidgetCollectionsWithTmpFiles: 1,
    }),
    (error) => {
      assert.ok(error instanceof OriginalsCleanupVerificationError);
      assert.match(error.message, /is not referenced by primary tmp_files/u);
      assert.match(error.message, /still uses the \.jpeg extension/u);
      assert.match(error.message, /has jpg content and must use \.jpg/u);
      return true;
    },
  );
});

test("recognizes the canonical signature families used by downloaded originals", () => {
  assert.equal(detectFileKind(JPEG_SIGNATURE), "jpg");
  assert.equal(detectFileKind(PNG_SIGNATURE), "png");
  assert.equal(detectFileKind(Buffer.from("GIF89a", "ascii")), "gif");
  assert.equal(detectFileKind(Buffer.from("glTF", "ascii")), "glb");
  assert.equal(detectFileKind(Buffer.from("%PDF-1.7", "ascii")), "pdf");
  assert.equal(detectFileKind(Buffer.from(" {\"path\":\"asset.png\"}", "utf8")), "json");
  assert.equal(detectFileKind(Buffer.from([0]), 1), "one-byte");
});

async function makeFixture(t, {
  physicalFiles,
  manifestTokens,
  primaryItems,
  primaryTmpFiles,
  widgetItems,
  widgetTmpFiles,
}) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "verify-originals-cleanup-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  const collectionRoot = path.join(root, "Originals Downloaded", "demo");
  const primaryRoot = path.join(root, "Suggested Items", "Suggested.bundle", "Tokens");
  const widgetRoot = path.join(root, "Suggested Items", "WidgetSuggested.bundle", "Tokens");
  await Promise.all([
    fs.mkdir(collectionRoot, { recursive: true }),
    fs.mkdir(primaryRoot, { recursive: true }),
    fs.mkdir(widgetRoot, { recursive: true }),
  ]);

  for (const [fileName, contents] of Object.entries(physicalFiles)) {
    await fs.writeFile(path.join(collectionRoot, fileName), contents);
  }
  await writeJSON(path.join(collectionRoot, "manifest.json"), {
    collection: { id: COLLECTION_ID, internal_slug: "demo" },
    totals: {
      tokensRecorded: manifestTokens.length,
      successfulFiles: Object.keys(physicalFiles).length,
      failedFiles: manifestTokens.length - Object.keys(physicalFiles).length,
    },
    tokens: manifestTokens,
  });

  const basePayload = {
    defaultFileExtension: "png",
    urlPrefixes: ["https://example.test/media/"],
  };
  await writeJSON(path.join(primaryRoot, `${COLLECTION_ID}.json`), {
    ...basePayload,
    items: primaryItems,
    ...(primaryTmpFiles ? { tmp_files: primaryTmpFiles } : {}),
  });
  await writeJSON(path.join(widgetRoot, `${COLLECTION_ID}.json`), {
    ...basePayload,
    items: widgetItems,
    ...(widgetTmpFiles ? { tmp_files: widgetTmpFiles } : {}),
  });
  return root;
}

async function writeJSON(filePath, value) {
  await fs.writeFile(filePath, `${JSON.stringify(value)}\n`);
}
