"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fsp = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
  CleanupError,
  buildCleanupPlan,
  detectFileKind,
  executeTwoPhaseRenames,
  numericUriBasename,
  recoverStaleTransaction,
  rollbackPhysicalRenames,
  resolveSolanaCollectionIds,
  validateRenamePlan,
} = require("./normalize_downloaded_originals");

test("detects canonical signatures without trusting the current suffix", () => {
  assert.equal(detectFileKind(Buffer.from([0xff, 0xd8, 0xff, 0x00]), 4), "jpg");
  assert.equal(detectFileKind(Buffer.from("GIF89a"), 6), "gif");
  assert.equal(detectFileKind(Buffer.from("glTF"), 4), "glb");
  assert.equal(detectFileKind(Buffer.from("{\"manifest\":\"arweave/paths\"}")), "json");
  assert.equal(detectFileKind(Buffer.from([0x00]), 1), "one-byte");
});

test("extracts only explicit decimal URI basenames", () => {
  assert.equal(numericUriBasename("https://example.test/meta/00033.json?x=1"), "33");
  assert.equal(numericUriBasename("ipfs://cid/7.png"), "7");
  assert.equal(numericUriBasename("https://example.test/meta/mint-33.json"), null);
  assert.equal(numericUriBasename("https://example.test/meta/33/final.json"), null);
});

test("keys Solana ordinals strictly by mint, independent of response order", () => {
  const collection = { slug: "demo" };
  const records = [record("mint-b", "png"), record("mint-a", "jpg")];
  const assets = new Map([
    ["mint-a", asset("Demo #41")],
    ["mint-b", asset("Demo #9")],
  ]);

  const result = resolveSolanaCollectionIds(collection, records, assets);

  assert.equal(result.method, "metadata-name");
  assert.equal(result.localIds.get("mint-a"), "41");
  assert.equal(result.localIds.get("mint-b"), "9");
});

test("allows a repeated ordinal only when complete filenames remain unique", () => {
  const collection = { slug: "record_of_hyperwar" };
  const imageMint = "AfpgARLXMYdx39KU8Rmko5LiKZzxwVkUBww979r7ZN3g";
  const videoMint = "7ux4UTRhtQxnn2DhtScR1sgCc1UB2uUnDKCHXpMo9tpV";
  const records = [record(imageMint, "png"), record(videoMint, "mp4")];
  const assets = new Map([
    [videoMint, asset("Scroll 0")],
    [imageMint, asset("Scroll 0")],
  ]);

  const result = resolveSolanaCollectionIds(collection, records, assets);

  assert.equal(result.localIds.get(imageMint), "0");
  assert.equal(result.localIds.get(videoMint), "0");
  assert.deepEqual(result.repairs, []);
});

test("rejects an unapproved repeated ordinal even when extensions differ", () => {
  const collection = { slug: "not_record_of_hyperwar" };
  const records = [record("mint-image", "png"), record("mint-video", "mp4")];
  const assets = new Map([
    ["mint-video", asset("Item 0")],
    ["mint-image", asset("Item 0")],
  ]);

  assert.throws(
    () => resolveSolanaCollectionIds(collection, records, assets),
    (error) => error instanceof CleanupError && /ordinal-collisions/u.test(error.message),
  );
});

test("applies the audited Cloudcastle duplicate repair by lexical mint order", () => {
  const firstLexically = "GngC88gV7Q3RYmDjvJmV9SjxJHexcVAhmHHCyxNjZhmp";
  const secondLexically = "HmTNthqfH81V6GnPEGcMkREBUE3e3WqaP7dgmstiCgca";
  const collection = { slug: "cloudcastle" };
  const records = [record(secondLexically, "png"), record(firstLexically, "png")];
  const assets = new Map([
    [secondLexically, asset("Cloudcastle 0")],
    [firstLexically, asset("Cloudcastle 0")],
  ]);

  const result = resolveSolanaCollectionIds(collection, records, assets);

  assert.equal(result.localIds.get(firstLexically), "0");
  assert.equal(result.localIds.get(secondLexically), "9");
  assert.equal(result.repairs.length, 1);
});

test("rejects unplanned Solana ambiguity before any path is assigned", () => {
  const collection = { slug: "unapproved" };
  const records = [record("mint-a", "png"), record("mint-b", "png")];
  const assets = new Map([
    ["mint-a", asset("Item 0")],
    ["mint-b", asset("Item 0")],
  ]);

  assert.throws(
    () => resolveSolanaCollectionIds(collection, records, assets),
    (error) => error instanceof CleanupError && /no complete, unambiguous Helius ordinal source/u.test(error.message),
  );
});

test("dry-run validation rejects exact target collisions", () => {
  const directoryPath = path.resolve(os.tmpdir(), "normalizer-collision-fixture");
  const collection = { slug: "demo", directoryPath };
  const records = [
    renameRecord(collection, "mint-a", "mint-a.png", "0.png"),
    renameRecord(collection, "mint-b", "mint-b.png", "0.png"),
  ];

  assert.throws(
    () => validateRenamePlan(records),
    (error) => error instanceof CleanupError && /both target 0\.png/u.test(error.message),
  );
});

test("two-phase rename supports cycles without overwriting bytes", async () => {
  const directory = await fsp.mkdtemp(path.join(os.tmpdir(), "normalizer-swap-"));
  const first = path.join(directory, "1.jpg");
  const second = path.join(directory, "2.jpg");
  await fsp.writeFile(first, "first");
  await fsp.writeFile(second, "second");
  const records = [
    { currentPath: first, tempPath: path.join(directory, ".tmp-a"), targetPath: second },
    { currentPath: second, tempPath: path.join(directory, ".tmp-b"), targetPath: first },
  ];
  try {
    await executeTwoPhaseRenames(records, { concurrency: 2 });
    assert.equal(await fsp.readFile(first, "utf8"), "second");
    assert.equal(await fsp.readFile(second, "utf8"), "first");
  } finally {
    await fsp.rm(directory, { recursive: true, force: true });
  }
});

test("two-phase failure restores the original source", async () => {
  const directory = await fsp.mkdtemp(path.join(os.tmpdir(), "normalizer-rollback-"));
  const source = path.join(directory, "mint.jpg");
  const target = path.join(directory, "1.jpg");
  const temporary = path.join(directory, ".tmp");
  await fsp.writeFile(source, "source bytes");
  await fsp.writeFile(target, "unplanned obstruction");
  const records = [{ currentPath: source, tempPath: temporary, targetPath: target }];
  try {
    await assert.rejects(() => executeTwoPhaseRenames(records), /rolled back/u);
    await rollbackPhysicalRenames(records);
    assert.equal(await fsp.readFile(source, "utf8"), "source bytes");
    assert.equal(await fsp.readFile(target, "utf8"), "unplanned obstruction");
    await assert.rejects(() => fsp.stat(temporary), { code: "ENOENT" });
  } finally {
    await fsp.rm(directory, { recursive: true, force: true });
  }
});

test("an already-normalized corpus preserves its original rename and drift audit", async () => {
  const root = await fsp.mkdtemp(path.join(os.tmpdir(), "normalizer-idempotent-"));
  const originals = path.join(root, "Originals Downloaded", "demo");
  const primaryRoot = path.join(root, "Suggested Items", "Suggested.bundle", "Tokens");
  const widgetRoot = path.join(root, "Suggested Items", "WidgetSuggested.bundle", "Tokens");
  const bytes = Buffer.from([0xff, 0xd8, 0xff, 0x01]);
  const sha256 = crypto.createHash("sha256").update(bytes).digest("hex");
  const generatedAt = "2026-07-12T00:00:00.000Z";
  const oldRename = { collection: "demo", tokenId: "1", from: "mint.jpg", to: "1.jpg" };
  const oldDrift = { collection: "demo", tokenId: "1", actualSha256: sha256 };
  try {
    await Promise.all([
      fsp.mkdir(originals, { recursive: true }),
      fsp.mkdir(primaryRoot, { recursive: true }),
      fsp.mkdir(widgetRoot, { recursive: true }),
    ]);
    await fsp.writeFile(path.join(originals, "1.jpg"), bytes);
    await writeJson(path.join(originals, "manifest.json"), {
      generatedAt,
      partial: false,
      collection: { id: "demo-id", internal_slug: "demo", chain: "ethereum" },
      totals: { tokensRecorded: 1, successfulFiles: 1, failedFiles: 0, reusedFiles: 1, bytesWritten: bytes.length, missingFiles: 0 },
      updatedAt: generatedAt,
      tokens: [{ tokenId: "1", fileName: "1.jpg", extension: "jpg", status: "success", bytesWritten: bytes.length, sha256 }],
      filenameCleanup: { version: 1, normalizedAt: generatedAt, report: "../filename-cleanup-report.json" },
    });
    await writeJson(path.join(primaryRoot, "demo-id.json"), {
      defaultFileExtension: "jpg",
      urlPrefixes: ["https://example.test/"],
      items: [["1", 0, "1.jpg"]],
      tmp_files: { 1: "1.jpg" },
    });
    await writeJson(path.join(root, "Originals Downloaded", "filename-cleanup-report.json"), {
      schemaVersion: 1,
      generatedAt,
      summary: { physicalFiles: 1 },
      renames: [oldRename],
      missingFiles: [],
      warnings: { arweaveJsonManifests: [], oneByteFiles: [], presentButNonPlayable: [] },
      knownManifestDrifts: [oldDrift],
    });

    const plan = await buildCleanupPlan({ repoRoot: root, strictCorpus: false, hashConcurrency: 1 });

    assert.equal(plan.alreadyNormalized, true);
    assert.deepEqual(plan.report.renames, [oldRename]);
    assert.deepEqual(plan.report.knownManifestDrifts, [oldDrift]);
  } finally {
    await fsp.rm(root, { recursive: true, force: true });
  }
});

test("stale-journal recovery restores cyclic media and backed-up JSON", async () => {
  const root = await fsp.mkdtemp(path.join(os.tmpdir(), "normalizer-recovery-"));
  const originals = path.join(root, "Originals Downloaded", "demo");
  const transaction = path.join(root, ".filename-cleanup-transaction-test");
  const backups = path.join(transaction, "backups");
  const staged = path.join(transaction, "staged");
  const first = path.join(originals, "1.jpg");
  const second = path.join(originals, "2.jpg");
  const tempFirst = path.join(originals, ".filename-cleanup-test-a.tmp");
  const tempSecond = path.join(originals, ".filename-cleanup-test-b.tmp");
  const firstBytes = Buffer.from([0xff, 0xd8, 0xff, 0x01]);
  const secondBytes = Buffer.from([0xff, 0xd8, 0xff, 0x02]);
  const jsonTarget = path.join(root, "bundle.json");
  const jsonBackup = path.join(backups, "bundle.json");
  try {
    await Promise.all([
      fsp.mkdir(originals, { recursive: true }),
      fsp.mkdir(backups, { recursive: true }),
      fsp.mkdir(staged, { recursive: true }),
    ]);
    await fsp.writeFile(first, firstBytes);
    await fsp.writeFile(second, secondBytes);
    const firstStat = await fsp.stat(first);
    const secondStat = await fsp.stat(second);
    await fsp.rename(first, tempFirst);
    await fsp.rename(second, tempSecond);
    await fsp.rename(tempFirst, second);
    await fsp.rename(tempSecond, first);
    await writeJson(jsonBackup, { version: "old" });
    await writeJson(jsonTarget, { version: "new" });
    await writeJson(path.join(transaction, "journal.json"), {
      schemaVersion: 1,
      transactionId: "test",
      phase: "files-renamed",
      renames: [
        recoveryRename("demo", "1", first, tempFirst, second, firstStat, firstBytes),
        recoveryRename("demo", "2", second, tempSecond, first, secondStat, secondBytes),
      ],
      jsonUpdates: [{
        target: jsonTarget,
        staged: path.join(staged, "bundle.json"),
        backup: jsonBackup,
        targetExisted: true,
        kind: "primary",
      }],
    });

    const result = await recoverStaleTransaction(root);

    assert.match(result, /Rolled back interrupted transaction/u);
    assert.deepEqual(await fsp.readFile(first), firstBytes);
    assert.deepEqual(await fsp.readFile(second), secondBytes);
    assert.deepEqual(JSON.parse(await fsp.readFile(jsonTarget, "utf8")), { version: "old" });
    await assert.rejects(() => fsp.stat(transaction), { code: "ENOENT" });
  } finally {
    await fsp.rm(root, { recursive: true, force: true });
  }
});

function record(tokenId, extension) {
  return { tokenId, inspection: { canonicalExtension: extension } };
}

function asset(name) {
  return { content: { metadata: { name }, files: [], links: {} } };
}

function renameRecord(collection, tokenId, currentName, targetName) {
  return {
    collection,
    tokenId,
    currentName,
    targetName,
    currentPath: path.join(collection.directoryPath, currentName),
    targetPath: path.join(collection.directoryPath, targetName),
  };
}

function recoveryRename(collection, tokenId, from, temporary, to, stat, bytes) {
  return {
    collection,
    tokenId,
    from,
    temporary,
    to,
    dev: String(stat.dev),
    ino: String(stat.ino),
    size: bytes.length,
    sha256: crypto.createHash("sha256").update(bytes).digest("hex"),
  };
}

async function writeJson(filePath, value) {
  await fsp.writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`);
}
