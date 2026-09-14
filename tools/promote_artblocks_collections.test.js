"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { createHash } = require("node:crypto");
const sha256 = value => createHash("sha256").update(value).digest("hex");
const { appendFinderRejections, exchangeDirectories, validateCaptureChecksums, validateParameterRecord, productionToken, addArtist, curationLedgers, planPromotion, publish } = require("./promote_artblocks_collections");
const { mergeGeneratedSuggestedItem } = require("./suggested_items");
const { historicalDecisions } = require("./download_artblocks_samples");

test("production field migration preserves frozen values without changing its input", () => {
  const before = { id: "2", hash: "original", url: "https://original.invalid/2", previewContractParameters: { p0: "AA==" }, previewReferencePixelSize: [400, 500], previewImageAspectRatio: [4, 5], name: "original" };
  const clone = structuredClone(before), after = productionToken(before);
  assert.deepEqual(after, { id: "2", hash: "original", url: before.url, contractParameters: { p0: "AA==" }, referencePixelSize: [400, 500], imageAspectRatio: [4, 5], name: "original" });
  assert.deepEqual(before, clone);
});

test("generated catalog updates retain bundle date and media/platform capabilities", () => {
  const retained = { bundledDate: "2026-09-14", iosOnly: true, generativeOnly: true, hasCover: false, hasThumbnails: false };
  assert.deepEqual(mergeGeneratedSuggestedItem(retained, { name: "New name", bundledDate: "2099-01-01" }), { ...retained, name: "New name" });
});

test("artist matching reserves existing identity and adds an exact credit", () => {
  const artists = { alice: { name: "Alice", collections: ["old"] } };
  assert.equal(addArtist(artists, "ALICE", "new"), "alice");
  assert.deepEqual(artists.alice.collections, ["old", "new"]);
  const key = addArtist(artists, "新しい", "artwork");
  assert.equal(artists[key].name, "新しい");
});

test("historical partitions are disjoint and future selection excludes rejected/static collections", async () => {
  const ledger = await curationLedgers();
  assert.equal(ledger.collectionCount, 828);
  assert.equal(ledger.sources.finderStatic, 92);
  const decisions = await historicalDecisions({});
  assert.equal(decisions.size, 845);
  for (const entry of ledger.collections) assert(decisions.has(entry.identity));
});

test("publication validates staged files, replaces complete directory, and preserves unrelated resources", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "promotion-test-"));
  const bundle = path.join(root, "Suggested.bundle");
  try {
    await fs.mkdir(path.join(bundle, "Development"), { recursive: true });
    await fs.writeFile(path.join(bundle, "existing.txt"), "unchanged");
    await publish({ files: new Map([["Scripts/collection.json", '{"name":"new"}'], ["items.json", "[]"]]) }, bundle);
    assert.equal(await fs.readFile(path.join(bundle, "existing.txt"), "utf8"), "unchanged");
    assert.equal(await fs.readFile(path.join(bundle, "Scripts/collection.json"), "utf8"), '{"name":"new"}');
    await assert.rejects(fs.access(path.join(bundle, "Development")));
    await fs.mkdir(`${bundle}.promotion-previous`);
    await assert.rejects(publish({ files: new Map() }, bundle), /Unfinished publication/);
    assert.equal(await fs.readFile(path.join(bundle, "items.json"), "utf8"), "[]");
  } finally { await fs.rm(root, { recursive: true, force: true }); }
});

test("completed production capture rebuilds deterministically and preserves the full reviewed records", async () => {
  try { await fs.access(path.join(__dirname, "artblocks/production/capture/complete.json")); } catch { return; }
  const first = await planPromotion(), second = await planPromotion();
  assert.deepEqual(first, second);
  assert.equal(first.provenance.reviewedTokens, 6524);
  assert.equal(first.provenance.approvedCollections, 292);
  assert.equal(first.provenance.tokenCount, 143847);
  assert.equal(JSON.parse(first.files.get("items.json")).length, 517);
});


test("publication validates cached parameter source and dependency even when token hash matches", () => {
  const address = "0x" + "1".repeat(40), identity = `1:${address}:2`;
  const dependency = { index: 0, dependency_type: "ONCHAIN", bytecode_address: "0x" + "2".repeat(40) };
  const script = { value: "const immutableArtistSource = true;", externalAssetDependencies: [dependency] };
  const token = { token_id: "2000000", hash: "0x" + "a".repeat(64) };
  const record = { hash: token.hash, parameters: { value: "frozen" }, sourceScriptSHA256: sha256(script.value), dependency,
    sourceURL: `https://generator.artblocks.io/1/${address}/2000000` };
  validateParameterRecord(identity, script, token, record);
  for (const changes of [{ sourceScriptSHA256: "0".repeat(64) }, { dependency: { ...dependency, bytecode_address: "0x" + "3".repeat(40) } }, { sourceURL: "https://wrong.invalid" }]) {
    assert.throws(() => validateParameterRecord(identity, script, token, { ...record, ...changes }), /Frozen parameter/);
  }
  const reviewed = { previewContractParameters: { value: "original" } };
  validateParameterRecord(identity, script, token, { hash: token.hash, parameters: reviewed.previewContractParameters, source: "reviewed-frozen-record" }, reviewed);
  assert.throws(() => validateParameterRecord(identity, script, token, record, reviewed), /Reviewed parameter overwrite/);
});

test("publication requires cutoff, every token file, and every parameter file in checksum inventory", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "capture-membership-test-"));
  const required = new Set(["cutoff.json", "tokens/project.json", "parameters/project.json"]);
  try {
    for (const relative of required) {
      await fs.mkdir(path.dirname(path.join(root, relative)), { recursive: true });
      await fs.writeFile(path.join(root, relative), "{}");
    }
    const files = Object.fromEntries([...required].map(relative => [relative, sha256("{}")]));
    await validateCaptureChecksums(root, { files }, required);
    for (const missing of required) {
      const incomplete = { ...files }; delete incomplete[missing];
      await assert.rejects(validateCaptureChecksums(root, { files: incomplete }, required), /membership/);
    }
    await assert.rejects(validateCaptureChecksums(root, { files: { ...files, unexpected: sha256("{}")} }, required), /membership/);
  } finally { await fs.rm(root, { recursive: true, force: true }); }
});

test("atomic publication recovers interruptions before and after directory exchange", async () => {
  for (const exchangeFirst of [false, true]) {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), "promotion-recovery-test-")), bundle = path.join(root, "Suggested.bundle");
    const originalCatalog = [{ name: "old" }], newCatalog = [{ name: "new", bundledDate: "2026-09-14" }];
    const plan = { originalCatalog, files: new Map([["items.json", JSON.stringify(newCatalog)], ["Scripts/new.json", "new-artwork"]]) };
    try {
      await fs.mkdir(bundle);
      await fs.writeFile(path.join(bundle, "items.json"), JSON.stringify(originalCatalog));
      await assert.rejects(publish(plan, bundle, { exchange: async (live, stage) => {
        if (exchangeFirst) exchangeDirectories(live, stage);
        throw new Error("Simulated interruption");
      } }), /Simulated interruption/);
      assert.deepEqual(JSON.parse(await fs.readFile(path.join(bundle, "items.json"), "utf8")), exchangeFirst ? newCatalog : originalCatalog);
      await fs.access(`${bundle}.promotion-transaction.json`);
      await publish(plan, bundle);
      assert.deepEqual(JSON.parse(await fs.readFile(path.join(bundle, "items.json"), "utf8")), newCatalog);
      assert.equal(await fs.readFile(path.join(bundle, "Scripts/new.json"), "utf8"), "new-artwork");
      await assert.rejects(fs.access(`${bundle}.promotion-stage`));
      await assert.rejects(fs.access(`${bundle}.promotion-transaction.json`));
    } finally { await fs.rm(root, { recursive: true, force: true }); }
  }
});

test("frozen batch publication refuses to reset a live bundling date", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "promotion-date-test-")), bundle = path.join(root, "Suggested.bundle");
  const originalCatalog = [{ name: "existing" }], current = [{ name: "existing", bundledDate: "2020-01-02" }];
  try {
    await fs.mkdir(bundle);
    const bytes = JSON.stringify(current);
    await fs.writeFile(path.join(bundle, "items.json"), bytes);
    await assert.rejects(publish({ originalCatalog, files: new Map([["items.json", JSON.stringify(originalCatalog)]]) }, bundle), /Live catalog changed/);
    assert.equal(await fs.readFile(path.join(bundle, "items.json"), "utf8"), bytes);
  } finally { await fs.rm(root, { recursive: true, force: true }); }
});

test("public promotion planner rejects a completion manifest that omits parameter checksums", async () => {
  const completePath = path.resolve(__dirname, "artblocks/production/capture/complete.json");
  const originalReadFile = fs.readFile;
  fs.readFile = async function (file, ...options) {
    const contents = await originalReadFile.call(this, file, ...options);
    if (path.resolve(file) !== completePath) return contents;
    const complete = JSON.parse(contents);
    for (const relative of Object.keys(complete.files)) if (relative.startsWith("parameters/")) delete complete.files[relative];
    return JSON.stringify(complete);
  };
  try { await assert.rejects(planPromotion(), /checksum membership/); }
  finally { fs.readFile = originalReadFile; }
});


test("Finder deletions retain provenance and cannot reject non-static or duplicate identities", () => {
  const identity = "1:0x123:1";
  const prior = { identity, name: "Static", group: "ok", note: "Original note", sourcePassID: "pass-1", localCollectionFolder: "samples/ok/static", samples: [{ tokenId: "1000000" }] };
  const row = { identity, name: "Static", group: "ok", note: "Original note", sourcePassID: "pass-1", localCollectionFolder: "samples/mb-static/static", sampleCount: 1, previousDecision: "mb static", decision: "no", status: "deleted" };
  const initial = { collections: [prior] }, curation = { collections: { [identity]: { artist: "Artist" } } };
  const journal = { version: 1, collectionCount: 1, collections: [row] };
  const rejected = new Map();
  appendFinderRejections(rejected, initial, journal, curation);
  assert.equal(rejected.get(identity).note, prior.note);
  assert.equal(rejected.get(identity).source, "finder-static-review");
  assert.throws(() => appendFinderRejections(rejected, initial, journal, curation), /Conflicting Finder/);
  assert.throws(() => appendFinderRejections(new Map(), { collections: [] }, journal, curation), /Conflicting Finder/);
  for (const changes of [{ note: "changed" }, { localCollectionFolder: "samples/another" }, { sampleCount: 2 }]) {
    assert.throws(() => appendFinderRejections(new Map(), initial, { ...journal, collections: [{ ...row, ...changes }] }, curation), /Conflicting Finder/);
  }
});
