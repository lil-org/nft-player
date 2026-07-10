const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const MIGRATION_SCRIPT = path.join(__dirname, "migrate_downloaded_collection_slugs.js");
const DOWNLOADER_SCRIPT = path.join(__dirname, "download_bundled_collection_originals.js");
const DOWNLOAD_TEST_SOURCE = "data:image/png;base64,iVBORw0KGgo=";

test("migration renames directories, updates manifests, and is idempotent", (t) => {
  const fixture = createMigrationFixture(t);

  const dryRun = runScript(MIGRATION_SCRIPT, migrationArgs(fixture));
  assert.equal(dryRun.status, 0, dryRun.stderr);
  assert.equal(JSON.parse(dryRun.stdout).directoriesToRename, 1);
  assert.equal(fs.existsSync(fixture.oldDirectory), true);

  const applied = runScript(MIGRATION_SCRIPT, ["--apply", ...migrationArgs(fixture)]);
  assert.equal(applied.status, 0, applied.stderr);
  const summary = JSON.parse(applied.stdout);
  assert.equal(summary.newlyAssignedSlugs, 2);
  assert.equal(summary.directoriesToRename, 1);

  const targetDirectory = path.join(fixture.downloadRoot, "active_collection");
  assert.equal(fs.existsSync(fixture.oldDirectory), false);
  assert.equal(fs.existsSync(targetDirectory), true);
  const items = readJson(fixture.itemsPath);
  assert.deepEqual(items.map((item) => item.internal_slug), ["active_collection", "case_sensitive_skip"]);

  const childManifest = readJson(path.join(targetDirectory, "manifest.json"));
  assert.equal(childManifest.collection.internal_slug, "active_collection");
  assert.equal(childManifest.outputDirectory, targetDirectory);
  const rootManifest = readJson(fixture.rootManifestPath);
  assert.equal(rootManifest.collections[0].outputDirectory, targetDirectory);
  assert.equal(rootManifest.skippedCollections[0].internal_slug, "case_sensitive_skip");
  assert.equal(rootManifest.failures[0].internal_slug, "active_collection");

  const beforeRerun = snapshotFiles([fixture.itemsPath, fixture.rootManifestPath, path.join(targetDirectory, "manifest.json")]);
  const rerun = runScript(MIGRATION_SCRIPT, ["--apply", ...migrationArgs(fixture)]);
  assert.equal(rerun.status, 0, rerun.stderr);
  const rerunSummary = JSON.parse(rerun.stdout);
  assert.equal(rerunSummary.directoriesToRename, 0);
  assert.equal(rerunSummary.manifestsToUpdate, 0);
  assert.equal(rerunSummary.rootManifestWillChange, false);
  assert.equal(rerunSummary.itemsWillChange, false);
  assert.deepEqual(snapshotFiles([...beforeRerun.keys()]), beforeRerun);
});

test("migration dry-run rejects unknown skipped collections without changing files", (t) => {
  const fixture = createMigrationFixture(t);
  const rootManifest = readJson(fixture.rootManifestPath);
  rootManifest.skippedCollections[0].id = "abcdef";
  writeJson(fixture.rootManifestPath, rootManifest);
  const beforeItems = fs.readFileSync(fixture.itemsPath, "utf8");

  const result = runScript(MIGRATION_SCRIPT, migrationArgs(fixture));
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unknown collection/u);
  assert.equal(fs.readFileSync(fixture.itemsPath, "utf8"), beforeItems);
  assert.equal(fs.existsSync(fixture.oldDirectory), true);
  assert.equal(fs.existsSync(path.join(fixture.downloadRoot, "active_collection")), false);
});

test("migration resumes after directories were renamed but metadata was not updated", (t) => {
  const fixture = createMigrationFixture(t);
  const targetDirectory = path.join(fixture.downloadRoot, "active_collection");
  fs.renameSync(fixture.oldDirectory, targetDirectory);

  const result = runScript(MIGRATION_SCRIPT, ["--apply", ...migrationArgs(fixture)]);
  assert.equal(result.status, 0, result.stderr);
  const summary = JSON.parse(result.stdout);
  assert.equal(summary.directoriesToRename, 0);
  assert.equal(summary.manifestsToUpdate, 1);
  assert.equal(readJson(path.join(targetDirectory, "manifest.json")).outputDirectory, targetDirectory);
  assert.equal(readJson(fixture.itemsPath)[0].internal_slug, "active_collection");
});

test("downloader refuses to apply while legacy collection directories remain", (t) => {
  const fixture = createDownloaderFixture(t);
  fs.mkdirSync(path.join(fixture.outputRoot, "Old Name__ethereum-id"), { recursive: true });

  const result = runScript(DOWNLOADER_SCRIPT, downloaderArgs(fixture));
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Legacy collection directories remain/u);
  assert.equal(fs.existsSync(path.join(fixture.outputRoot, "download_test")), false);
});

test("downloader refuses to reuse a slug directory belonging to another collection", (t) => {
  const fixture = createDownloaderFixture(t);
  const collectionDirectory = path.join(fixture.outputRoot, "download_test");
  fs.mkdirSync(collectionDirectory, { recursive: true });
  writeJson(path.join(collectionDirectory, "manifest.json"), {
    collection: {
      id: "0xwrong",
      chain: "ethereum",
      address: "0xwrong",
      internal_slug: "download_test",
    },
    tokens: [],
  });

  const result = runScript(DOWNLOADER_SCRIPT, downloaderArgs(fixture));
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /belongs to a collection not present in items\.json/u);
  assert.equal(fs.existsSync(path.join(collectionDirectory, "1.png")), false);
});

test("downloader refuses an existing slug directory without a manifest", (t) => {
  const fixture = createDownloaderFixture(t);
  fs.mkdirSync(path.join(fixture.outputRoot, "download_test"), { recursive: true });

  const result = runScript(DOWNLOADER_SCRIPT, downloaderArgs(fixture));
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /has no manifest\.json and will not be overwritten/u);
});

test("downloader skips bundled generative collections and their reserved directory", (t) => {
  const fixture = createDownloaderFixture(t);
  const scriptsPath = path.join(fixture.bundlePath, "Scripts");
  const generativeRoot = path.join(fixture.outputRoot, "Art Blocks Generative");
  const preservedMedia = path.join(generativeRoot, "download_test", "0.png");
  fs.mkdirSync(path.dirname(preservedMedia), { recursive: true });
  fs.mkdirSync(scriptsPath, { recursive: true });
  fs.writeFileSync(path.join(scriptsPath, "0xabc.json"), "not read by download tools");
  fs.writeFileSync(path.join(fixture.tokensPath, "0xabc.json"), "not valid JSON");
  fs.writeFileSync(preservedMedia, "preserved");

  const result = runScript(DOWNLOADER_SCRIPT, downloaderArgs(fixture));
  assert.equal(result.status, 0, result.stderr);
  const summary = JSON.parse(result.stdout);
  assert.equal(summary.collectionsDownloaded, 0);
  assert.equal(summary.skippedCollections, 1);
  assert.equal(summary.downloadedFiles, 0);
  assert.equal(fs.readFileSync(preservedMedia, "utf8"), "preserved");

  const report = readJson(fixture.jsonReportPath);
  assert.equal(report.skippedCollections[0].skipReason, "rendered from a bundled generative script");
});

test("slug migration ignores the bundled generative subtree", (t) => {
  const fixture = createMigrationFixture(t);
  const scriptsPath = path.join(fixture.bundlePath, "Scripts");
  const generativeRoot = path.join(fixture.downloadRoot, "Art Blocks Generative");
  fs.mkdirSync(scriptsPath, { recursive: true });
  fs.mkdirSync(generativeRoot, { recursive: true });
  fs.writeFileSync(path.join(scriptsPath, "0xabc.json"), "not read by migration tools");
  fs.renameSync(fixture.oldDirectory, path.join(generativeRoot, "active_collection"));
  fs.rmSync(path.join(generativeRoot, "active_collection", "manifest.json"));

  const result = runScript(MIGRATION_SCRIPT, migrationArgs(fixture));
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).matchedDirectories, 0);
});

test("downloader refuses an existing collection directory whose stored slug changed", (t) => {
  const fixture = createDownloaderFixture(t);
  const oldDirectory = path.join(fixture.outputRoot, "old_download_test");
  fs.mkdirSync(oldDirectory, { recursive: true });
  writeJson(path.join(oldDirectory, "manifest.json"), {
    collection: { id: "0xabc", chain: "ethereum", address: "0xabc" },
    tokens: [],
  });

  const result = runScript(DOWNLOADER_SCRIPT, downloaderArgs(fixture));
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /should be named download_test/u);
  assert.equal(fs.existsSync(path.join(fixture.outputRoot, "download_test")), false);
});

test("an exact slug filter does not match longer slugs", (t) => {
  const fixture = createDownloaderFixture(t);
  addDownloaderCollection(fixture, {
    name: "Download Test Extra",
    internal_slug: "download_test_extra",
    chain: "ethereum",
    address: "0xdef",
  }, {
    defaultFileExtension: "png",
    items: [{ id: "2", url: DOWNLOAD_TEST_SOURCE }],
  });

  const result = runScript(DOWNLOADER_SCRIPT, [...downloaderArgs(fixture), "--collection", "download_test"]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).collectionsMatched, 1);
  assert.equal(fs.existsSync(path.join(fixture.outputRoot, "download_test")), true);
  assert.equal(fs.existsSync(path.join(fixture.outputRoot, "download_test_extra")), false);
});

test("downloader reuses a verified file from a matching manifest", (t) => {
  const fixture = createDownloaderFixture(t);
  const collectionDirectory = path.join(fixture.outputRoot, "download_test");
  const media = Buffer.from("89504e470d0a1a0a", "hex");
  fs.mkdirSync(collectionDirectory, { recursive: true });
  fs.writeFileSync(path.join(collectionDirectory, "1.png"), media);
  writeJson(path.join(collectionDirectory, "manifest.json"), {
    collection: {
      id: "0xABC",
      chain: "ethereum",
      address: "0xABC",
    },
    tokens: [{
      tokenId: "1",
      fileName: "1.png",
      originalBundledURL: DOWNLOAD_TEST_SOURCE,
      status: "success",
      bytesWritten: media.length,
      sha256: crypto.createHash("sha256").update(media).digest("hex"),
    }],
  });

  const result = runScript(DOWNLOADER_SCRIPT, downloaderArgs(fixture));
  assert.equal(result.status, 0, result.stderr);
  const summary = JSON.parse(result.stdout);
  assert.equal(summary.downloadedFiles, 0);
  assert.equal(summary.reusedFiles, 1);
  assert.equal(readJson(path.join(collectionDirectory, "manifest.json")).collection.internal_slug, "download_test");
});

test("downloader replaces a verified file when the bundled source changes", (t) => {
  const fixture = createDownloaderFixture(t);
  const oldMedia = Buffer.from("old media");
  seedExistingDownload(fixture, {
    media: oldMedia,
    originalBundledURL: "data:application/octet-stream;base64,b2xkIG1lZGlh",
    qualityRepair: {
      decision: "fallback cache matches collection dimensions",
      previous: { status: "failed", downloadUrl: DOWNLOAD_TEST_SOURCE },
    },
  });

  const result = runScript(DOWNLOADER_SCRIPT, downloaderArgs(fixture));
  assert.equal(result.status, 0, result.stderr);
  const summary = JSON.parse(result.stdout);
  assert.equal(summary.downloadedFiles, 1);
  assert.equal(summary.reusedFiles, 0);
  assert.deepEqual(fs.readFileSync(path.join(fixture.outputRoot, "download_test", "1.png")), Buffer.from("89504e470d0a1a0a", "hex"));
  assert.equal(readJson(path.join(fixture.outputRoot, "download_test", "manifest.json")).tokens[0].sourceUpgrade.previousSha256, sha256(oldMedia));
});

test("downloader keeps a verified file when a changed source is still unavailable", (t) => {
  const fixture = createDownloaderFixture(t);
  const payload = readJson(path.join(fixture.tokensPath, "0xabc.json"));
  payload.items[0].url = "not-a-downloadable-url";
  writeJson(path.join(fixture.tokensPath, "0xabc.json"), payload);
  const oldMedia = Buffer.from("known good fallback");
  seedExistingDownload(fixture, {
    media: oldMedia,
    originalBundledURL: "data:application/octet-stream;base64,a25vd24gZ29vZCBmYWxsYmFjaw==",
  });

  const result = runScript(DOWNLOADER_SCRIPT, downloaderArgs(fixture));
  assert.equal(result.status, 0, result.stderr);
  const summary = JSON.parse(result.stdout);
  assert.equal(summary.downloadedFiles, 0);
  assert.equal(summary.reusedFiles, 1);
  assert.equal(summary.sourceRefreshFailures, 1);
  assert.deepEqual(fs.readFileSync(path.join(fixture.outputRoot, "download_test", "1.png")), oldMedia);
  const entry = readJson(path.join(fixture.outputRoot, "download_test", "manifest.json")).tokens[0];
  assert.equal(entry.status, "success");
  assert.equal(entry.sourceRefresh.status, "failed");
});

test("downloader preserves a documented dimension-based quality repair", (t) => {
  const fixture = createDownloaderFixture(t);
  const repairedMedia = Buffer.from("dimension checked fallback");
  seedExistingDownload(fixture, {
    media: repairedMedia,
    originalBundledURL: "data:application/octet-stream;base64,ZGltZW5zaW9uIGNoZWNrZWQgZmFsbGJhY2s=",
    qualityRepair: {
      decision: "fallback cache matches collection dimensions",
      previous: { status: "success", downloadUrl: DOWNLOAD_TEST_SOURCE },
    },
  });

  const result = runScript(DOWNLOADER_SCRIPT, downloaderArgs(fixture));
  assert.equal(result.status, 0, result.stderr);
  const summary = JSON.parse(result.stdout);
  assert.equal(summary.downloadedFiles, 0);
  assert.equal(summary.reusedFiles, 1);
  assert.deepEqual(fs.readFileSync(path.join(fixture.outputRoot, "download_test", "1.png")), repairedMedia);
  assert.equal(readJson(path.join(fixture.outputRoot, "download_test", "manifest.json")).tokens[0].sourceOverridePreserved, true);
});

test("downloader treats equivalent IPFS gateways as the same source", (t) => {
  const fixture = createDownloaderFixture(t);
  const payload = readJson(path.join(fixture.tokensPath, "0xabc.json"));
  payload.items[0].url = "https://ipfs.io/ipfs/bafy-test/file.png";
  writeJson(path.join(fixture.tokensPath, "0xabc.json"), payload);
  const media = Buffer.from("gateway-independent media");
  seedExistingDownload(fixture, {
    media,
    originalBundledURL: null,
    downloadUrl: "https://ipfs.decentralized-content.com/ipfs/bafy-test/file.png",
  });

  const result = runScript(DOWNLOADER_SCRIPT, [...downloaderArgs(fixture), "--timeout-ms", "1000"]);
  assert.equal(result.status, 0, result.stderr);
  const summary = JSON.parse(result.stdout);
  assert.equal(summary.downloadedFiles, 0);
  assert.equal(summary.reusedFiles, 1);
  assert.deepEqual(fs.readFileSync(path.join(fixture.outputRoot, "download_test", "1.png")), media);
});

test("filtered retries preserve the full root manifest and default reports", (t) => {
  const fixture = createDownloaderFixture(t);
  addDownloaderCollection(fixture, {
    name: "Unavailable Collection",
    internal_slug: "unavailable_collection",
    chain: "ethereum",
    address: "0xdef",
  }, {
    defaultFileExtension: "png",
    items: [{ id: "2", url: "not-a-downloadable-url" }],
  });
  const args = downloaderArgsWithoutReports(fixture);
  const full = runScript(DOWNLOADER_SCRIPT, args, fixture.root);
  assert.equal(full.status, 0, full.stderr);
  const canonicalReportPath = path.join(fixture.root, "tools", "reports", "originals-download-report.json");
  const canonicalReport = fs.readFileSync(canonicalReportPath, "utf8");

  const filtered = runScript(DOWNLOADER_SCRIPT, [...args, "--collection", "download_test"], fixture.root);
  assert.equal(filtered.status, 0, filtered.stderr);
  assert.equal(fs.readFileSync(canonicalReportPath, "utf8"), canonicalReport);
  const filteredReport = readJson(path.join(fixture.root, "tools", "reports", "originals-download-report.filtered.json"));
  assert.equal(filteredReport.collections.length, 1);

  const rootManifest = readJson(path.join(fixture.outputRoot, "manifest.json"));
  assert.equal(rootManifest.collections.length, 2);
  assert.equal(rootManifest.failures.length, 1);
  assert.equal(rootManifest.mergedWithExistingManifest, true);
  assert.match(rootManifest.reportPath, /originals-download-report\.md$/u);

  const skipped = runScript(DOWNLOADER_SCRIPT, [...args, "--skip-collection", "download_test"], fixture.root);
  assert.equal(skipped.status, 0, skipped.stderr);
  const afterSkip = readJson(path.join(fixture.outputRoot, "manifest.json"));
  const preserved = afterSkip.collections.find((collection) => collection.internal_slug === "download_test");
  assert.equal(preserved.skipped, false);
  assert.equal(preserved.successfulFiles, 1);
});

function createMigrationFixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "nft-player-slugs-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const bundlePath = path.join(root, "Suggested.bundle");
  const downloadRoot = path.join(root, "Originals Downloaded");
  fs.mkdirSync(bundlePath, { recursive: true });
  fs.mkdirSync(downloadRoot, { recursive: true });

  const active = { name: "Active Collection!", chain: "ethereum", address: "0xAbC" };
  const skipped = { name: "Case Sensitive Skip", chain: "solana", address: "AbCdEf" };
  const itemsPath = path.join(bundlePath, "items.json");
  writeJson(itemsPath, [active, skipped]);

  const oldDirectory = path.join(downloadRoot, "Active Collection__0xabc");
  fs.mkdirSync(oldDirectory, { recursive: true });
  writeJson(path.join(oldDirectory, "manifest.json"), {
    collection: { id: active.address, name: active.name, chain: active.chain, address: active.address },
    outputDirectory: oldDirectory,
    updatedAt: "2026-01-01T00:00:00.000Z",
    tokens: [],
  });

  const rootManifestPath = path.join(downloadRoot, "manifest.json");
  writeJson(rootManifestPath, {
    generatedAt: "2026-01-01T00:00:00.000Z",
    collections: [{
      id: active.address,
      name: active.name,
      chain: active.chain,
      address: active.address,
      outputDirectory: oldDirectory,
      manifestPath: path.join(oldDirectory, "manifest.json"),
      skipped: false,
    }],
    skippedCollections: [{
      id: skipped.address,
      name: skipped.name,
      chain: skipped.chain,
      address: skipped.address,
      outputDirectory: path.join(downloadRoot, "Case Sensitive Skip__AbCdEf"),
      skipped: true,
    }],
    failures: [{ collectionId: active.address, tokenId: "1" }],
  });

  return { bundlePath, downloadRoot, itemsPath, oldDirectory, rootManifestPath };
}

function createDownloaderFixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "nft-player-downloader-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const bundlePath = path.join(root, "Suggested.bundle");
  const tokensPath = path.join(bundlePath, "Tokens");
  const outputRoot = path.join(root, "Originals Downloaded");
  fs.mkdirSync(tokensPath, { recursive: true });
  fs.mkdirSync(outputRoot, { recursive: true });
  const itemsPath = path.join(bundlePath, "items.json");
  writeJson(itemsPath, [{
    name: "Download Test",
    internal_slug: "download_test",
    chain: "ethereum",
    address: "0xabc",
  }]);
  writeJson(path.join(tokensPath, "0xabc.json"), {
    defaultFileExtension: "png",
    items: [{ id: "1", url: DOWNLOAD_TEST_SOURCE }],
  });
  return {
    root,
    bundlePath,
    itemsPath,
    tokensPath,
    outputRoot,
    reportPath: path.join(root, "report.md"),
    jsonReportPath: path.join(root, "report.json"),
  };
}

function addDownloaderCollection(fixture, item, payload) {
  const items = readJson(fixture.itemsPath);
  items.push(item);
  writeJson(fixture.itemsPath, items);
  writeJson(path.join(fixture.tokensPath, `${item.address}.json`), payload);
}

function seedExistingDownload(fixture, { media, originalBundledURL, downloadUrl = null, qualityRepair = null }) {
  const collectionDirectory = path.join(fixture.outputRoot, "download_test");
  fs.mkdirSync(collectionDirectory, { recursive: true });
  fs.writeFileSync(path.join(collectionDirectory, "1.png"), media);
  writeJson(path.join(collectionDirectory, "manifest.json"), {
    collection: {
      id: "0xabc",
      chain: "ethereum",
      address: "0xabc",
      internal_slug: "download_test",
    },
    tokens: [{
      tokenId: "1",
      fileName: "1.png",
      originalBundledURL,
      downloadUrl,
      status: "success",
      bytesWritten: media.length,
      sha256: sha256(media),
      ...(qualityRepair ? { qualityRepair } : {}),
    }],
  });
}

function migrationArgs(fixture) {
  return ["--bundle", fixture.bundlePath, "--download-root", fixture.downloadRoot];
}

function downloaderArgs(fixture) {
  return [
    "--apply",
    "--bundle", fixture.bundlePath,
    "--output-root", fixture.outputRoot,
    "--report", fixture.reportPath,
    "--json-report", fixture.jsonReportPath,
    "--retries", "0",
    "--concurrency", "1",
  ];
}

function downloaderArgsWithoutReports(fixture) {
  return [
    "--apply",
    "--bundle", fixture.bundlePath,
    "--output-root", fixture.outputRoot,
    "--retries", "0",
    "--concurrency", "1",
  ];
}

function runScript(script, args, cwd = path.resolve(__dirname, "..")) {
  return spawnSync(process.execPath, [script, ...args], {
    cwd,
    encoding: "utf8",
  });
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function snapshotFiles(filePaths) {
  return new Map(filePaths.map((filePath) => [filePath, fs.readFileSync(filePath, "utf8")]));
}
