#!/usr/bin/env node
"use strict";

const fs = require("node:fs/promises");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { spawnSync } = require("node:child_process");
const { isDeepStrictEqual } = require("node:util");
const { assignInternalSlugs, slugifyCollectionName, suggestedItemId } = require("./suggested_items");
const { validateRequiredContractParameters } = require("./build_artblocks_good_preview");

const ROOT = path.resolve(__dirname, "..");
const ARCHIVE = path.join(ROOT, "tools/artblocks/archive/pass-5");
const PRODUCTION = path.join(ROOT, "tools/artblocks/production");
const BUNDLE = path.join(ROOT, "Suggested Items/Suggested.bundle");
const json = value => JSON.stringify(value, null, 2) + "\n";
const sha256 = value => createHash("sha256").update(value).digest("hex");
const read = async file => JSON.parse(await fs.readFile(file, "utf8"));

function productionToken(token) {
  const result = { ...token };
  for (const [old, current] of [["previewContractParameters", "contractParameters"], ["previewReferencePixelSize", "referencePixelSize"], ["previewImageAspectRatio", "imageAspectRatio"]]) {
    if (Object.hasOwn(result, old)) { result[current] = result[old]; delete result[old]; }
  }
  return result;
}


function validateParameterRecord(identity, script, token, record, reviewed) {
  const label = `${identity}/${token.token_id}`;
  if (!record || typeof record.hash !== "string" || record.hash.toLowerCase() !== token.hash.toLowerCase()) throw new Error(`Parameter hash conflict: ${label}`);
  if (!record.parameters || Array.isArray(record.parameters) || typeof record.parameters !== "object" || Object.values(record.parameters).some(value => typeof value !== "string")) throw new Error(`Invalid frozen parameter object: ${label}`);
  if (reviewed?.previewContractParameters != null) {
    if (record.source !== "reviewed-frozen-record" || !isDeepStrictEqual(record.parameters, reviewed.previewContractParameters)) throw new Error(`Reviewed parameter overwrite: ${label}`);
  } else {
    const dependencies = script.externalAssetDependencies?.filter(asset => asset.dependency_type === "ONCHAIN" && asset.bytecode_address) ?? [];
    const [chain, address] = identity.split(":");
    if (record.sourceScriptSHA256 !== sha256(script.value)) throw new Error(`Frozen parameter source fingerprint conflict: ${label}`);
    if (dependencies.length !== 1 || !isDeepStrictEqual(record.dependency, dependencies[0])) throw new Error(`Frozen parameter dependency conflict: ${label}`);
    if (record.sourceURL !== `https://generator.artblocks.io/${chain}/${address}/${token.token_id}`) throw new Error(`Frozen parameter source URL conflict: ${label}`);
  }
}

function addArtist(artists, name, slug) {
  const normalized = name.normalize("NFC").trim().toLocaleLowerCase("en-US");
  const match = Object.entries(artists).find(([, artist]) => artist.name.normalize("NFC").trim().toLocaleLowerCase("en-US") === normalized);
  let key = match?.[0] ?? slugifyCollectionName(name);
  if (!key) key = `artist_${sha256(name).slice(0, 12)}`;
  if (!match && artists[key]) key += `_${sha256(name).slice(0, 8)}`;
  if (!artists[key]) artists[key] = { name, collections: [] };
  if (!artists[key].collections.includes(slug)) artists[key].collections.push(slug);
  return key;
}

function appendFinderRejections(rejected, initialStatic, journal, curation) {
  if (journal.version !== 1 || journal.collectionCount !== journal.collections?.length) throw new Error("Invalid Finder deletion record");
  const original = new Map(initialStatic.collections.map(row => [row.identity, row]));
  const sourceFile = "tools/artblocks/reviews/finder-deletions.json";
  for (const row of journal.collections) {
    const previous = original.get(row.identity);
    if (!previous || rejected.has(row.identity) || row.decision !== "no" || row.status !== "deleted" || row.previousDecision !== "mb static"
        || row.name !== previous.name || row.group !== previous.group || row.note !== previous.note || row.sourcePassID !== previous.sourcePassID
        || row.sampleCount !== previous.samples.length || row.localCollectionFolder !== `samples/mb-static/${path.basename(previous.localCollectionFolder)}`) {
      throw new Error(`Conflicting Finder deletion: ${row.identity}`);
    }
    rejected.set(row.identity, { ...row, artist: curation.collections[row.identity].artist,
      source: "finder-static-review", sourceFile });
  }
}

async function curationLedgers() {
  const base = await read(path.join(ROOT, "tools/artblocks/reviews/pass-1-curation.json"));
  const rejected = new Map();
  for (const [identity, entry] of Object.entries(base.collections)) {
    if (entry.group === "excluded") rejected.set(identity, { identity, ...entry, decision: "no", note: null, source: "original-curation", sourceFile: "tools/artblocks/reviews/pass-1-curation.json" });
  }
  for (const [pass, file] of [["pass-1", "pass-1.json"], ["pass-2", "pass-2.json"], ["pass-3", "pass-3-decisions.json"]]) {
    const review = await read(path.join(ROOT, "tools/artblocks/reviews", file));
    for (const [identity, entry] of Object.entries(review.collections)) {
      if (entry.decision !== "no") continue;
      if (rejected.has(identity)) throw new Error(`Duplicate rejection: ${identity}`);
      rejected.set(identity, { identity, ...entry, artist: base.collections[identity].artist,
        localCollectionFolder: `samples/${base.collections[identity].group}/${base.collections[identity].directory}`,
        source: pass, sourceFile: `tools/artblocks/reviews/${file}` });
    }
  }
  const initialStatic = await read(path.join(ROOT, "tools/artblocks/archive/sample-cleanup-2026-09-14/deferred-static.json"));
  const finder = await read(path.join(ROOT, "tools/artblocks/reviews/finder-deletions.json"));
  appendFinderRejections(rejected, initialStatic, finder, base);
  const approved = await read(path.join(ROOT, "tools/artblocks/reviews/approved.json"));
  const deferred = await read(path.join(ROOT, "tools/artblocks/reviews/deferred-static.json"));
  const seen = new Set(rejected.keys());
  for (const group of [approved, deferred]) for (const item of group.collections) {
    if (seen.has(item.identity)) throw new Error(`Overlapping curation partition: ${item.identity}`);
    seen.add(item.identity);
  }
  const kept = new Set(deferred.collections.map(row => row.identity));
  const deleted = new Set(finder.collections.map(row => row.identity));
  const validStatic = initialStatic.collections.every(row => kept.has(row.identity) !== deleted.has(row.identity));
  if (rejected.size !== 736 + finder.collectionCount || approved.collectionCount !== 292
      || deferred.collectionCount !== deferred.collections.length || deferred.collectionCount + finder.collectionCount !== initialStatic.collectionCount
      || deferred.tokenCount !== deferred.collections.reduce((sum, row) => sum + row.samples.length, 0)
      || !validStatic || seen.size !== 1137) throw new Error("Unexpected curation partition counts");
  return { version: 1, collectionCount: rejected.size, sources: { originalCuration: 618, pass1: 104, pass2: 13, pass3: 1, finderStatic: finder.collectionCount },
    collections: [...rejected.values()].sort((a, b) => a.identity.localeCompare(b.identity, "en-US")) };
}

async function validateCaptureChecksums(capture, complete, required) {
  if (!complete.files || !isDeepStrictEqual(Object.keys(complete.files).sort(), [...required].sort())) throw new Error("Frozen capture checksum membership mismatch");
  for (const [relative, digest] of Object.entries(complete.files)) {
    if (sha256(await fs.readFile(path.join(capture, relative))) !== digest) throw new Error(`Frozen capture checksum mismatch: ${relative}`);
  }
}

async function planPromotion({ capture = path.join(PRODUCTION, "capture"), archive = ARCHIVE } = {}) {
  const approved = await read(path.join(ROOT, "tools/artblocks/reviews/approved.json"));
  const cutoff = await read(path.join(capture, "cutoff.json"));
  const complete = await read(path.join(capture, "complete.json"));
  const provenance = new Map((await read(path.join(archive, "Development/Good/provenance.json"))).collections.map(p => [p.identity, p]));
  const scripts = new Map(), required = new Set(["cutoff.json"]);
  for (const collection of approved.collections) {
    const source = provenance.get(collection.identity), stem = collection.identity.replaceAll(":", "-");
    const script = await read(path.join(archive, "Development/Good/Scripts", `${source.collectionId}.json`));
    scripts.set(collection.identity, script);
    required.add(`tokens/${stem}.json`);
    if (script.externalAssetDependencies?.some(asset => asset.dependency_type === "ONCHAIN")) required.add(`parameters/${stem}.json`);
  }
  await validateCaptureChecksums(capture, complete, required);
  if (complete.collections !== approved.collectionCount || complete.capturedAt !== cutoff.capturedAt) throw new Error("Incomplete or mismatched capture");
  const original = await read(path.join(archive, "production-items.json"));
  const artists = await read(path.join(archive, "production-artists.json"));
  const newItems = approved.collections.map(collection => {
    const [chainId, address, abId] = collection.identity.split(":");
    return { address, abId, chain: "ethereum", chainId: Number(chainId), name: collection.name,
      bundledDate: "2026-09-14", iosOnly: true, generativeOnly: true, hasCover: false, hasThumbnails: false, artists: [] };
  });
  const items = assignInternalSlugs([...original, ...newItems]);
  if (items.length !== 517 || new Set(items.map(suggestedItemId)).size !== 517) throw new Error("Catalog identity collision");
  const files = new Map(), identities = [], records = [];
  let tokenCount = 0, reviewedCount = 0;
  for (let index = 0; index < approved.collections.length; index++) {
    const collection = approved.collections[index], item = items[original.length + index], source = provenance.get(collection.identity);
    item.artists = [addArtist(artists, source.artist, item.internal_slug)];
    const script = scripts.get(collection.identity);
    if (sha256(script.value) !== source.bundledScriptSHA256 || script.name !== item.name || script.address !== item.address || script.abId !== item.abId) throw new Error(`Reviewed script mismatch: ${item.name}`);
    const oldManifest = await read(path.join(archive, "Development/Good/Tokens", `${source.collectionId}.json`));
    const reviewed = new Map(oldManifest.items.map(token => [token.id, token]));
    const stem = collection.identity.replaceAll(":", "-");
    const tokens = await read(path.join(capture, "tokens", `${stem}.json`));
    const cutoffProject = cutoff.collections[collection.identity];
    if (!cutoffProject || cutoffProject.invocations !== tokens.length) throw new Error(`Incomplete collection: ${item.name}`);
    let parameters = {};
    if (script.externalAssetDependencies?.some(asset => asset.dependency_type === "ONCHAIN")) parameters = await read(path.join(capture, "parameters", `${stem}.json`));
    const mapped = tokens.map((token, invocation) => {
      const id = String(BigInt(item.abId) * 1000000n + BigInt(invocation));
      if (token.token_id !== id || token.invocation !== invocation || token.chain_id !== item.chainId || token.contract_address.toLowerCase() !== item.address
        || token.project_id !== `${item.address}-${item.abId}` || token.id !== `${item.address}-${id}` || !/^0x[0-9a-fA-F]{64}$/u.test(token.hash)) throw new Error(`Token identity conflict: ${item.name}/${id}`);
      const old = reviewed.get(id);
      if (old && old.hash.toLowerCase() !== token.hash.toLowerCase()) throw new Error(`Reviewed hash conflict: ${item.name}/${id}`);
      const result = old ? productionToken(old) : { id, hash: token.hash };
      if (!old) {
        const dimensions = token.image?.metadata;
        if (Number.isSafeInteger(dimensions?.width) && Number.isSafeInteger(dimensions?.height) && dimensions.width > 0 && dimensions.height > 0) {
          result.imageAspectRatio = [dimensions.width, dimensions.height];
          result.referencePixelSize = [dimensions.width, dimensions.height];
        }
        if (parameters[id]) result.contractParameters = parameters[id].parameters;
      }
      if (script.externalAssetDependencies?.some(asset => asset.dependency_type === "ONCHAIN")) {
        validateParameterRecord(collection.identity, script, token, parameters[id], old);
        if (!isDeepStrictEqual(parameters[id].parameters, result.contractParameters)) throw new Error(`Missing or conflicting frozen parameters: ${item.name}/${id}`);
        validateRequiredContractParameters(collection.identity, result.contractParameters, `${item.name}/${id}`);
      }
      if (item.name.trim().toLowerCase() === "autorad" && !result.referencePixelSize) throw new Error(`Missing autoRAD reference size: ${id}`);
      if (old) reviewedCount++;
      return result;
    });
    if (reviewed.size !== mapped.filter(t => reviewed.has(t.id)).length) throw new Error(`Lost reviewed tokens: ${item.name}`);
    const collectionId = suggestedItemId(item);
    delete script.isDevelopmentPreview;
    delete script.collectionIdOverride;
    script.renderingProfile = "artBlocks";
    script.chainId = item.chainId;
    const scriptBytes = json(script);
    const tokenBytes = json({ items: mapped, artworkAspectRatios: oldManifest.thumbnailAspectRatios, ...(oldManifest.thumbnailAspectRatioOverrides ? { artworkAspectRatioOverrides: oldManifest.thumbnailAspectRatioOverrides } : {}) });
    files.set(`Scripts/${collectionId}.json`, scriptBytes);
    files.set(`Tokens/${collectionId}.json`, tokenBytes);
    identities.push({ identity: collection.identity, oldCollectionId: source.collectionId, collectionId, chainId: item.chainId, name: item.name });
    records.push({ identity: collection.identity, collectionId, name: item.name, artist: source.artist, tokenCount: mapped.length, reviewedTokenCount: reviewed.size,
      sourceScriptSHA256: sha256(script.value), scriptResourceSHA256: sha256(scriptBytes), tokenResourceSHA256: sha256(tokenBytes), capturedAt: cutoff.capturedAt, invocationCutoff: cutoffProject.invocations });
    tokenCount += mapped.length;
  }
  if (reviewedCount !== 6524 || complete.tokens !== tokenCount) throw new Error("Capture/review totals changed");
  files.set("items.json", json(items));
  files.set("artists.json", json(artists));
  return { files, originalCatalog: original, mapping: { version: 1, collections: identities }, provenance: { version: 1, bundledDate: "2026-09-14", capturedAt: cutoff.capturedAt,
    approvedCollections: 292, reviewedTokens: reviewedCount, tokenCount, totalCatalogCollections: items.length, collections: records } };
}

async function fileDigest(file) {
  try { return sha256(await fs.readFile(file)); } catch (error) { if (error.code === "ENOENT") return null; throw error; }
}

async function matchesFiles(directory, checksums) {
  for (const [relative, digest] of Object.entries(checksums)) if (await fileDigest(path.join(directory, relative)) !== digest) return false;
  return true;
}

function exchangeDirectories(bundle, stage) {
  const result = spawnSync("python3", [path.join(__dirname, "swap_artblocks_bundle.py"), bundle, stage], { encoding: "utf8", timeout: 10000 });
  if (result.error || result.status !== 0) throw result.error ?? new Error(`Atomic directory exchange failed: ${result.stderr.trim()}`);
}

async function recoverPublication(plan, bundle) {
  const journalPath = `${bundle}.promotion-transaction.json`, stage = `${bundle}.promotion-stage`;
  let journal;
  try { journal = await read(journalPath); } catch (error) { if (error.code === "ENOENT") return false; throw error; }
  const after = Object.fromEntries([...plan.files].map(([relative, bytes]) => [relative, sha256(bytes)]));
  if (journal.version !== 1 || !isDeepStrictEqual(journal.after, after) || !isDeepStrictEqual(Object.keys(journal.before ?? {}).sort(), Object.keys(after).sort())) throw new Error("Unrecognized publication recovery journal; refusing to alter the bundle");
  const completed = await matchesFiles(bundle, after);
  if (!completed && !await matchesFiles(bundle, journal.before)) throw new Error("Live bundle differs from both publication states; refusing recovery");
  await fs.rm(stage, { recursive: true, force: true });
  await fs.rm(journalPath);
  return completed;
}

async function publish(plan, bundle = BUNDLE, { exchange = exchangeDirectories } = {}) {
  if (await recoverPublication(plan, bundle)) return false;
  const stage = `${bundle}.promotion-stage`, previous = `${bundle}.promotion-previous`, journalPath = `${bundle}.promotion-transaction.json`;
  for (const dir of [stage, previous]) {
    try { await fs.access(dir); throw new Error(`Unfinished publication exists without a recognized recovery journal: ${dir}`); } catch (error) { if (error.code !== "ENOENT") throw error; }
  }
  if (plan.originalCatalog) {
    const current = await read(path.join(bundle, "items.json"));
    if (!isDeepStrictEqual(current, plan.originalCatalog) && !isDeepStrictEqual(current, JSON.parse(plan.files.get("items.json")))) throw new Error("Live catalog changed outside this frozen promotion; refusing to overwrite it");
  }
  const before = {}, after = {};
  for (const [relative, bytes] of plan.files) {
    before[relative] = await fileDigest(path.join(bundle, relative));
    after[relative] = sha256(bytes);
  }
  await fs.writeFile(`${journalPath}.tmp`, json({ version: 1, before, after }));
  await fs.rename(`${journalPath}.tmp`, journalPath);
  await fs.cp(bundle, stage, { recursive: true });
  await fs.rm(path.join(stage, "Development"), { recursive: true, force: true });
  for (const [relative, bytes] of plan.files) {
    const destination = path.join(stage, relative);
    await fs.mkdir(path.dirname(destination), { recursive: true });
    await fs.writeFile(destination, bytes);
    if (await fileDigest(destination) !== after[relative]) throw new Error(`Stage verification failed: ${relative}`);
  }
  if (!await matchesFiles(bundle, before)) throw new Error("Live bundle changed during staging; refusing to exchange it");
  await exchange(bundle, stage);
  await fs.rm(stage, { recursive: true });
  await fs.rm(journalPath);
  return true;
}

async function main(args = process.argv.slice(2)) {
  const rejected = await curationLedgers();
  await fs.writeFile(path.join(ROOT, "tools/artblocks/rejected.json"), json(rejected));
  if (args.includes("--ledgers-only")) return;
  const plan = await planPromotion();
  await fs.mkdir(PRODUCTION, { recursive: true });
  for (const [name, value] of [["identity-mapping.json", plan.mapping], ["provenance.json", plan.provenance]]) await fs.writeFile(path.join(PRODUCTION, name), json(value));
  if (args.includes("--publish")) await publish(plan);
  console.log(json({ ...plan.provenance, collections: undefined, publish: args.includes("--publish") }));
}

module.exports = { appendFinderRejections, exchangeDirectories, recoverPublication, validateCaptureChecksums, validateParameterRecord, productionToken, addArtist, curationLedgers, planPromotion, publish };
if (require.main === module) main().catch(error => { console.error(error); process.exitCode = 1; });
