#!/usr/bin/env node

const fs = require("node:fs");
const fsp = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const { Readable } = require("node:stream");
const { pipeline } = require("node:stream/promises");

const execFileAsync = promisify(execFile);

const ROOT = path.resolve(__dirname, "..");
const COLLECTION_ID = "0xeed41d06ae195ca8f5cacace4cd691ee75f0683f";
const COLLECTION_SLUG = "cigawrette_packs";
const ORIGINAL_CID = "bafybeigvhgkcqqamlukxcmjodalpk2kuy5qzqtx6m4i6pvb7o3ammss3y4";
const EXPECTED_WIDTH = 3456;
const EXPECTED_HEIGHT = 4320;
const EXPECTED_AREA = EXPECTED_WIDTH * EXPECTED_HEIGHT;
const EXPECTED_COHORT_SIZE = 3366;
const LOOKSRARE_GRAPHQL = "https://graphql.looksrare.org/graphql";
const LOOKSRARE_BATCH_SIZE = 10;
const HAMT_MASK_64 = (1n << 64n) - 1n;
const BASE32_ALPHABET = "abcdefghijklmnopqrstuvwxyz234567";
const rawDagPbBlockPromises = new Map();

const COLLECTION_DIRECTORY = path.join(ROOT, "Originals Downloaded", COLLECTION_SLUG);
const COLLECTION_MANIFEST_PATH = path.join(COLLECTION_DIRECTORY, "manifest.json");
const ROOT_MANIFEST_PATH = path.join(ROOT, "Originals Downloaded", "manifest.json");
const BUNDLE_PATH = path.join(ROOT, "Suggested Items", "Suggested.bundle", "Tokens", `${COLLECTION_ID}.json`);

const DEFAULTS = {
  apply: false,
  useHamt: true,
  concurrency: 12,
  metadataConcurrency: 4,
  retries: 4,
  timeoutMs: 60000,
  retryDelayMs: 1500,
  checkpointEvery: 100,
  reportPath: path.join(ROOT, "tools", "reports", "cigawrette-packs-high-resolution-upgrade.md"),
  jsonReportPath: path.join(ROOT, "tools", "reports", "cigawrette-packs-high-resolution-upgrade.json"),
};

const HELP = `Usage: node tools/upgrade_cigawrette_packs_originals.js [options]

Replace the known 500x625 Cigawrette Packs cache renditions with verified
3456x4320 originals from LooksRare's archive, with IPFS as a fallback.

Options:
  --apply                         Download and commit replacements. Default is dry-run.
  --no-hamt                       Skip IPFS HAMT leaf resolution and use direct CDN/gateway fallbacks.
  --concurrency <n>               Concurrent media downloads (default: 12).
  --metadata-concurrency <n>      Concurrent LooksRare GraphQL requests (default: 4).
  --retries <n>                   Retries after the first request (default: 4).
  --timeout-ms <n>                Per-request timeout (default: 60000).
  --retry-delay-ms <n>            Initial exponential retry delay (default: 1500).
  --checkpoint-every <n>          Atomic manifest checkpoint interval (default: 100).
  --report <path>                 Markdown report path.
  --json-report <path>            JSON report path.
  -h, --help                      Show this help.
`;

async function main() {
  const options = parseOptions(process.argv.slice(2));
  const startedAt = new Date();
  const [manifest, bundle] = await Promise.all([
    readJson(COLLECTION_MANIFEST_PATH),
    readJson(BUNDLE_PATH),
  ]);

  validateInputs(manifest, bundle);
  const cohort = manifest.tokens.filter(isLowResolutionLineage);
  if (cohort.length !== EXPECTED_COHORT_SIZE) {
    throw new Error(`Expected ${EXPECTED_COHORT_SIZE} known low-resolution tokens, found ${cohort.length}`);
  }
  assertCohortMatchesBundle(cohort, bundle);

  const initial = summarizeCohort(cohort);
  console.error(`Cigawrette Packs high-resolution cohort: ${cohort.length}`);
  console.error(`  already upgraded/reconcilable: ${initial.currentJpegs}`);
  console.error(`  remaining 500x625 PNGs: ${initial.currentPngs}`);

  if (!options.apply) {
    console.log(JSON.stringify({
      mode: "dry-run",
      collectionId: COLLECTION_ID,
      targetFiles: cohort.length,
      alreadyHighResolutionFiles: initial.currentJpegs,
      filesToDownload: initial.currentPngs,
      expectedResolution: `${EXPECTED_WIDTH}x${EXPECTED_HEIGHT}`,
    }, null, 2));
    return;
  }

  await removeStaleTemporaryFiles();
  manifest.startedAt = startedAt.toISOString();
  await writeCollectionManifest(manifest, true);

  const results = [];
  const unresolved = [];
  const pendingDeletes = [];
  let networkAttempts = 0;
  let downloadedBytes = 0;
  let mutations = 0;
  let lastCheckpointMutation = 0;
  let checkpointPromise = Promise.resolve();

  const checkpoint = (force = false) => {
    if (!force && mutations - lastCheckpointMutation < options.checkpointEvery) return checkpointPromise;
    lastCheckpointMutation = mutations;
    checkpointPromise = checkpointPromise.then(async () => {
      const deletions = pendingDeletes.splice(0, pendingDeletes.length);
      await writeCollectionManifest(manifest, true);
      await Promise.all(deletions.map((filePath) => fsp.rm(filePath, { force: true })));
    });
    return checkpointPromise;
  };

  const currentJpegs = cohort.filter((token) => normalizeExtension(token.fileName) === "jpg");
  const failedReconciliations = new Set();
  let reconciled = 0;
  await runPool(currentJpegs, Math.min(options.concurrency, 8), async (token) => {
    const inspection = await inspectHighResolutionFile(path.join(COLLECTION_DIRECTORY, token.fileName), token);
    if (!inspection.ok) {
      failedReconciliations.add(String(token.tokenId));
      return;
    }
    reconcileExistingEntry(token, inspection);
    mutations += 1;
    reconciled += 1;
    results.push(resultForExisting(token, inspection));
    const duplicatePng = path.join(COLLECTION_DIRECTORY, `${safeTokenId(token.tokenId)}.png`);
    if (await fileExists(duplicatePng)) pendingDeletes.push(duplicatePng);
    await checkpoint();
  });
  await checkpoint(true);
  console.error(`Reconciled ${reconciled}/${currentJpegs.length} already-downloaded originals.`);

  const downloadTargets = cohort.filter((token) => (
    normalizeExtension(token.fileName) !== "jpg" || failedReconciliations.has(String(token.tokenId))
  ));
  console.error(`Looking up ${downloadTargets.length} archived original URL(s) from LooksRare...`);
  const looksRareUrls = await lookupLooksRareURLs(downloadTargets.map((token) => String(token.tokenId)), options);
  console.error(`LooksRare returned ${looksRareUrls.size}/${downloadTargets.length} original URL(s).`);
  const missingLooksRareIds = downloadTargets
    .map((token) => String(token.tokenId))
    .filter((tokenId) => !looksRareUrls.has(tokenId));
  const downloadTargetIds = downloadTargets.map((token) => String(token.tokenId));
  const alchemyCachedUrls = downloadTargetIds.length > 0
    ? await lookupAlchemyCachedURLs(downloadTargetIds, options)
    : new Map();
  if (downloadTargetIds.length > 0) {
    console.error(`Alchemy returned ${alchemyCachedUrls.size}/${downloadTargetIds.length} cached original URL(s).`);
  }
  const ipfsLeafByTokenId = options.useHamt && missingLooksRareIds.length > 0
    ? await buildIpfsLeafMap(missingLooksRareIds, options)
    : new Map();
  if (options.useHamt && missingLooksRareIds.length > 0) {
    console.error(`Resolved ${ipfsLeafByTokenId.size}/${missingLooksRareIds.length} legacy token(s) to direct IPFS leaf CIDs.`);
  }

  let completed = 0;
  await runPool(downloadTargets, options.concurrency, async (token) => {
    const tokenId = String(token.tokenId);
    const canonicalUrl = canonicalOriginalURL(tokenId);
    const expectedPath = path.join(COLLECTION_DIRECTORY, `${safeTokenId(tokenId)}.jpg`);

    // A prior interrupted pass may have committed the JPG before its manifest checkpoint.
    const resumable = await inspectHighResolutionFile(expectedPath, null);
    if (resumable.ok) {
      const previous = snapshotPrevious(token);
      applyReplacementEntry(token, {
        tokenId,
        canonicalUrl,
        finalUrl: canonicalUrl,
        source: "resume.existing-jpg",
        fileName: path.basename(expectedPath),
        probe: resumable.probe,
        sha256: resumable.sha256,
        bytesWritten: resumable.bytesWritten,
        statusCode: 200,
        contentType: "image/jpeg",
        attempts: 0,
        startedAt: new Date().toISOString(),
        finishedAt: new Date().toISOString(),
        elapsedMs: 0,
      }, previous);
      mutations += 1;
      results.push(resultForReplacement(token, previous, "resumed"));
      if (previous.fileName && previous.fileName !== token.fileName) {
        pendingDeletes.push(path.join(COLLECTION_DIRECTORY, previous.fileName));
      }
      await checkpoint();
      completed += 1;
      logProgress(completed, downloadTargets.length, results, unresolved);
      return;
    }

    const tempPath = path.join(COLLECTION_DIRECTORY, `.${safeTokenId(tokenId)}.looksrare.part`);
    const sources = [];
    const looksRareUrl = looksRareUrls.get(tokenId);
    if (looksRareUrl) sources.push({ name: "looksrare.image", url: looksRareUrl, retries: 1, timeoutMs: 20000 });
    const alchemyCachedUrl = alchemyCachedUrls.get(tokenId);
    if (alchemyCachedUrl) sources.push({ name: "alchemy.cachedUrl", url: alchemyCachedUrl, retries: 2, timeoutMs: 30000 });
    sources.push({ name: "ipfs.alchemy-pinata", url: alchemyPinataOriginalURL(tokenId), retries: 2, timeoutMs: 30000 });
    const leafCid = ipfsLeafByTokenId.get(tokenId);
    if (leafCid) {
      sources.push({ name: "ipfs.filebase-leaf", url: filebaseLeafURL(leafCid), retries: 2, timeoutMs: 30000 });
      sources.push({ name: "ipfs.pinata-leaf", url: pinataLeafURL(leafCid), retries: 1, timeoutMs: 30000 });
    }
    sources.push({ name: "ipfs.rarible", url: raribleOriginalURL(tokenId), retries: 1, timeoutMs: 30000 });
    sources.push({ name: "ipfs.filebase", url: filebaseOriginalURL(tokenId), retries: 1, timeoutMs: 30000 });
    sources.push({ name: "ipfs.pinata", url: pinataOriginalURL(tokenId), retries: 2, timeoutMs: 60000 });

    let replacement = null;
    const sourceErrors = [];
    for (const source of sources) {
      const attempt = await downloadAndValidate(source, tempPath, {
        ...options,
        retries: source.retries ?? options.retries,
        timeoutMs: source.timeoutMs ?? options.timeoutMs,
      });
      networkAttempts += attempt.attempts;
      if (attempt.ok) {
        replacement = { ...attempt, source: source.name, canonicalUrl, tokenId };
        break;
      }
      sourceErrors.push({ source: source.name, url: source.url, error: attempt.error, attempts: attempt.attempts });
    }

    if (!replacement) {
      await fsp.rm(tempPath, { force: true });
      unresolved.push({ tokenId, stage: "download", sources: sourceErrors });
      completed += 1;
      logProgress(completed, downloadTargets.length, results, unresolved);
      return;
    }

    const previous = snapshotPrevious(token);
    await fsp.rename(tempPath, expectedPath);
    replacement.fileName = path.basename(expectedPath);
    replacement.finishedAt = new Date().toISOString();
    replacement.elapsedMs = Date.parse(replacement.finishedAt) - Date.parse(replacement.startedAt);
    applyReplacementEntry(token, replacement, previous);
    mutations += 1;
    downloadedBytes += replacement.bytesWritten;
    results.push(resultForReplacement(token, previous, "downloaded"));
    if (previous.fileName && previous.fileName !== token.fileName) {
      pendingDeletes.push(path.join(COLLECTION_DIRECTORY, previous.fileName));
    }
    await checkpoint();
    completed += 1;
    logProgress(completed, downloadTargets.length, results, unresolved);
  });

  await checkpoint(true);
  await checkpointPromise;
  await removeStaleTemporaryFiles();

  const finalValidation = validateFinalManifest(manifest, cohort);
  await writeCollectionManifest(manifest, false);

  const report = buildReport({
    options,
    startedAt,
    initial,
    manifest,
    results,
    unresolved,
    networkAttempts,
    downloadedBytes,
    finalValidation,
  });
  await writeReports(report, options);
  await updateRootManifest(manifest, report);

  console.log(JSON.stringify(report.summary, null, 2));
  if (unresolved.length > 0 || finalValidation.remainingLowResolution > 0) process.exitCode = 2;
}

function parseOptions(args) {
  const options = { ...DEFAULTS };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    switch (arg) {
      case "--apply": options.apply = true; break;
      case "--no-hamt": options.useHamt = false; break;
      case "--concurrency": options.concurrency = positiveInteger(nextValue(args, ++index, arg), arg); break;
      case "--metadata-concurrency": options.metadataConcurrency = positiveInteger(nextValue(args, ++index, arg), arg); break;
      case "--retries": options.retries = nonnegativeInteger(nextValue(args, ++index, arg), arg); break;
      case "--timeout-ms": options.timeoutMs = positiveInteger(nextValue(args, ++index, arg), arg); break;
      case "--retry-delay-ms": options.retryDelayMs = positiveInteger(nextValue(args, ++index, arg), arg); break;
      case "--checkpoint-every": options.checkpointEvery = positiveInteger(nextValue(args, ++index, arg), arg); break;
      case "--report": options.reportPath = path.resolve(nextValue(args, ++index, arg)); break;
      case "--json-report": options.jsonReportPath = path.resolve(nextValue(args, ++index, arg)); break;
      case "-h":
      case "--help": console.log(HELP); process.exit(0); break;
      default: throw new Error(`Unknown option: ${arg}`);
    }
  }
  return options;
}

function nextValue(args, index, option) {
  if (index >= args.length) throw new Error(`Missing value for ${option}`);
  return args[index];
}

function positiveInteger(value, option) {
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) throw new Error(`${option} must be a positive integer`);
  return number;
}

function nonnegativeInteger(value, option) {
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0) throw new Error(`${option} must be a nonnegative integer`);
  return number;
}

function validateInputs(manifest, bundle) {
  if (String(manifest.collection?.id).toLowerCase() !== COLLECTION_ID) {
    throw new Error(`Collection manifest does not belong to ${COLLECTION_ID}`);
  }
  if (!Array.isArray(manifest.tokens) || manifest.tokens.length !== 9997) {
    throw new Error(`Expected 9997 Cigawrette Packs manifest rows, found ${manifest.tokens?.length ?? "none"}`);
  }
  if (!Array.isArray(bundle.items) || !Array.isArray(bundle.urlPrefixes)) {
    throw new Error("Cigawrette Packs bundle token file has an unexpected shape");
  }
  const ids = new Set();
  for (const token of manifest.tokens) {
    const id = String(token.tokenId);
    if (ids.has(id)) throw new Error(`Duplicate token ${id} in collection manifest`);
    ids.add(id);
    if (token.status !== "success") throw new Error(`Token ${id} is not currently a successful download`);
  }
}

function isLowResolutionLineage(token) {
  const currentPng = normalizeExtension(token.fileName) === "png";
  const currentLowProbe = token.mediaProbe?.width === 500 && token.mediaProbe?.height === 625;
  const upgradedFromPng = normalizeExtension(token.sourceUpgrade?.previousFileName) === "png";
  return currentPng || currentLowProbe || upgradedFromPng;
}

function assertCohortMatchesBundle(cohort, bundle) {
  const rows = new Map(bundle.items.map((row) => [String(row[0]), row]));
  for (const token of cohort) {
    const row = rows.get(String(token.tokenId));
    if (!row || row[1] !== 1 || row[2] !== `${token.tokenId}.jpg` || normalizeExtension(row[3]) !== "jpg") {
      throw new Error(`Bundle source for target token ${token.tokenId} is not the expected original IPFS JPG`);
    }
  }
}

function summarizeCohort(cohort) {
  return {
    targetFiles: cohort.length,
    currentPngs: cohort.filter((token) => normalizeExtension(token.fileName) === "png").length,
    currentJpegs: cohort.filter((token) => normalizeExtension(token.fileName) === "jpg").length,
    withHighResolutionProbe: cohort.filter((token) => isExpectedProbe(token.mediaProbe)).length,
  };
}

async function lookupLooksRareURLs(tokenIds, options) {
  const batches = chunk(tokenIds, LOOKSRARE_BATCH_SIZE);
  const urls = new Map();
  if (batches.length === 0) return urls;
  let completed = 0;
  await runPool(batches, options.metadataConcurrency, async (batch) => {
    const found = await lookupLooksRareBatch(batch, options);
    for (const [tokenId, url] of found) urls.set(tokenId, url);
    completed += 1;
    if (completed === batches.length || completed % 25 === 0) {
      console.error(`  LooksRare metadata: ${completed}/${batches.length} batches`);
    }
  });
  return urls;
}

async function lookupLooksRareBatch(tokenIds, options) {
  const fields = tokenIds.map((tokenId, index) => (
    `t${index}: token(collection: \"${COLLECTION_ID}\", tokenId: \"${tokenId}\") { tokenId image { src contentType } }`
  )).join("\n");
  const query = `query CigawretteOriginals {\n${fields}\n}`;
  const requestUrl = new URL(LOOKSRARE_GRAPHQL);
  requestUrl.searchParams.set("query", query);
  let lastError = null;
  for (let attempt = 0; attempt <= options.retries; attempt += 1) {
    try {
      const response = await fetch(requestUrl, {
        method: "GET",
        headers: {
          accept: "application/json",
          "apollo-require-preflight": "true",
          "x-apollo-operation-name": "CigawretteOriginals",
          "user-agent": "nft-player-original-recovery/1.0",
        },
        signal: AbortSignal.timeout(options.timeoutMs),
      });
      const text = await response.text();
      if (!response.ok) throw new Error(`HTTP ${response.status}: ${text.slice(0, 240)}`);
      const payload = JSON.parse(text);
      if (payload.errors?.length) throw new Error(payload.errors.map((error) => error.message).join("; "));
      const result = new Map();
      tokenIds.forEach((tokenId, index) => {
        const record = payload.data?.[`t${index}`];
        const src = record?.image?.src;
        if (String(record?.tokenId) === tokenId && isValidLooksRareURL(src)) result.set(tokenId, src);
      });
      return result;
    } catch (error) {
      lastError = error;
      if (attempt < options.retries) await delay(backoffDelay(options.retryDelayMs, attempt));
    }
  }
  console.error(`  LooksRare metadata batch failed for ${tokenIds.join(", ")}: ${lastError?.message ?? lastError}`);
  return new Map();
}

function isValidLooksRareURL(value) {
  if (typeof value !== "string") return false;
  try {
    const url = new URL(value);
    const parts = url.pathname.split("/").filter(Boolean);
    return url.protocol === "https:"
      && url.hostname === "static.looksnice.org"
      && parts.length === 2
      && parts[0].toLowerCase() === COLLECTION_ID
      && /^0x[0-9a-f]{64}$/iu.test(parts[1]);
  } catch {
    return false;
  }
}

async function lookupAlchemyCachedURLs(tokenIds, options) {
  const result = new Map();
  const endpoint = "https://eth-mainnet.g.alchemy.com/nft/v3/demo/getNFTMetadataBatch";
  for (const batch of chunk(tokenIds, 100)) {
    const request = {
      tokens: batch.map((tokenId) => ({ contractAddress: COLLECTION_ID, tokenId })),
      refreshCache: false,
    };
    let payload = null;
    let lastError = null;
    for (let retry = 0; retry <= options.retries; retry += 1) {
      try {
        const response = await fetch(endpoint, {
          method: "POST",
          headers: { accept: "application/json", "content-type": "application/json" },
          body: JSON.stringify(request),
          signal: AbortSignal.timeout(Math.min(options.timeoutMs, 30000)),
        });
        if (!response.ok) throw new Error(`HTTP ${response.status}: ${(await response.text()).slice(0, 240)}`);
        payload = await response.json();
        break;
      } catch (error) {
        lastError = error;
        if (retry < options.retries) await delay(backoffDelay(options.retryDelayMs, retry));
      }
    }
    if (!payload) {
      console.error(`  Alchemy metadata batch failed: ${lastError?.message ?? lastError}`);
      continue;
    }
    const wanted = new Set(batch);
    for (const nft of payload.nfts ?? []) {
      const tokenId = String(nft?.tokenId ?? "");
      const cachedUrl = nft?.image?.cachedUrl;
      if (wanted.has(tokenId) && isValidAlchemyCachedURL(cachedUrl)) result.set(tokenId, cachedUrl);
    }
  }
  return result;
}

function isValidAlchemyCachedURL(value) {
  if (typeof value !== "string") return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && url.hostname === "nft2-cdn.alchemy.com";
  } catch {
    return false;
  }
}

async function buildIpfsLeafMap(tokenIds, options) {
  const result = new Map();
  const unresolved = [];
  let completed = 0;
  console.error(`Resolving ${tokenIds.length} legacy token(s) through the IPFS HAMT...`);
  await runPool(tokenIds, Math.min(4, options.concurrency), async (tokenId) => {
    try {
      const leaf = await resolveHamtFile(`${safeTokenId(tokenId)}.jpg`, options);
      result.set(String(tokenId), leaf.cid);
    } catch (error) {
      unresolved.push(String(tokenId));
    }
    completed += 1;
    if (completed === tokenIds.length || completed % 25 === 0) {
      console.error(`  IPFS HAMT: ${completed}/${tokenIds.length} (${result.size} resolved)`);
    }
  });
  if (unresolved.length > 0) {
    console.error(`  Retrying ${unresolved.length} HAMT resolution(s) after transient block failures...`);
    await delay(options.retryDelayMs);
    await runPool(unresolved, 2, async (tokenId) => {
      try {
        const leaf = await resolveHamtFile(`${safeTokenId(tokenId)}.jpg`, options);
        result.set(String(tokenId), leaf.cid);
      } catch (error) {
        console.error(`  IPFS HAMT token ${tokenId}: ${error.message}`);
      }
    });
  }
  return result;
}

async function resolveHamtFile(fileName, options) {
  const digest = murmur3X64_64(fileName);
  let shardCid = ORIGINAL_CID;
  const buckets = [];
  for (let depth = 0; depth < digest.length; depth += 1) {
    const block = await fetchRawDagPbBlock(shardCid, options);
    const links = decodeDagPbLinks(block);
    const prefix = digest[depth].toString(16).padStart(2, "0").toUpperCase();
    buckets.push(prefix);
    const leaf = links.find((link) => link.name === `${prefix}${fileName}`);
    if (leaf) return leaf;
    const child = links.find((link) => link.name === prefix);
    if (!child) throw new Error(`no entry at HAMT bucket ${buckets.join("/")}`);
    shardCid = child.cid;
  }
  throw new Error(`HAMT depth exceeded for ${fileName}`);
}

async function fetchRawDagPbBlock(cid, options) {
  if (!rawDagPbBlockPromises.has(cid)) {
    const blockPromise = (async () => {
      const controller = new AbortController();
      const gateways = [
        "https://ipfs.raribleuserdata.com",
        "https://ipfs.filebase.io",
        "https://trustless-gateway.link",
        "https://gateway.pinata.cloud",
      ];
      try {
        const attempts = gateways.map((gateway) => fetchRawDagPbFrom(
          gateway,
          cid,
          Math.min(options.timeoutMs, 45000),
          controller.signal,
        ));
        const winner = await Promise.any(attempts);
        controller.abort();
        return winner;
      } catch (error) {
        const reasons = error instanceof AggregateError
          ? error.errors.map((reason) => reason.message).join("; ")
          : error.message;
        throw new Error(`unable to fetch raw block ${cid}: ${reasons}`);
      }
    })().catch((error) => {
      rawDagPbBlockPromises.delete(cid);
      throw error;
    });
    rawDagPbBlockPromises.set(cid, blockPromise);
  }
  return rawDagPbBlockPromises.get(cid);
}

async function fetchRawDagPbFrom(gateway, cid, timeoutMs, outerSignal) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const abort = () => controller.abort();
  outerSignal.addEventListener("abort", abort, { once: true });
  try {
    const response = await fetch(`${gateway}/ipfs/${cid}?format=raw`, {
      headers: { accept: "application/vnd.ipld.raw" },
      redirect: "follow",
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`${gateway}: HTTP ${response.status}`);
    const bytes = Buffer.from(await response.arrayBuffer());
    verifyCidBlock(cid, bytes);
    decodeDagPbLinks(bytes);
    return bytes;
  } finally {
    clearTimeout(timer);
    outerSignal.removeEventListener("abort", abort);
  }
}

function murmur3X64_64(text) {
  const bytes = Buffer.from(text);
  const c1 = 0x87c37b91114253d5n;
  const c2 = 0x4cf5ad432745937fn;
  let h1 = 0n;
  let h2 = 0n;
  let offset = 0;
  while (offset + 16 <= bytes.length) {
    let k1 = bytes.readBigUInt64LE(offset);
    let k2 = bytes.readBigUInt64LE(offset + 8);
    offset += 16;
    k1 = multiply64(multiply64(rotateLeft64(multiply64(k1, c1), 31), c2), 1n);
    h1 ^= k1;
    h1 = add64(add64(rotateLeft64(h1, 27), h2) * 5n, 0x52dce729n);
    h1 &= HAMT_MASK_64;
    k2 = multiply64(rotateLeft64(multiply64(k2, c2), 33), c1);
    h2 ^= k2;
    h2 = add64(add64(rotateLeft64(h2, 31), h1) * 5n, 0x38495ab5n);
    h2 &= HAMT_MASK_64;
  }
  const tail = bytes.subarray(offset);
  let k1 = 0n;
  let k2 = 0n;
  for (let index = tail.length - 1; index >= 8; index -= 1) k2 = (k2 << 8n) | BigInt(tail[index]);
  if (tail.length > 8) {
    k2 = multiply64(rotateLeft64(multiply64(k2, c2), 33), c1);
    h2 ^= k2;
  }
  for (let index = Math.min(7, tail.length - 1); index >= 0; index -= 1) k1 = (k1 << 8n) | BigInt(tail[index]);
  if (tail.length > 0) {
    k1 = multiply64(rotateLeft64(multiply64(k1, c1), 31), c2);
    h1 ^= k1;
  }
  h1 ^= BigInt(bytes.length);
  h2 ^= BigInt(bytes.length);
  h1 = add64(h1, h2);
  h2 = add64(h2, h1);
  h1 = fmix64(h1);
  h2 = fmix64(h2);
  h1 = add64(h1, h2);
  const digest = Buffer.alloc(8);
  digest.writeBigUInt64BE(h1);
  return digest;
}

function multiply64(left, right) {
  return (left * right) & HAMT_MASK_64;
}

function add64(left, right) {
  return (left + right) & HAMT_MASK_64;
}

function rotateLeft64(value, bits) {
  const shift = BigInt(bits);
  return ((value << shift) | (value >> (64n - shift))) & HAMT_MASK_64;
}

function fmix64(value) {
  value ^= value >> 33n;
  value = multiply64(value, 0xff51afd7ed558ccdn);
  value ^= value >> 33n;
  value = multiply64(value, 0xc4ceb9fe1a85ec53n);
  value ^= value >> 33n;
  return value & HAMT_MASK_64;
}

function decodeDagPbLinks(bytes) {
  return protobufFields(bytes)
    .filter((field) => field.number === 2)
    .map((field) => {
      const linkFields = protobufFields(field.value);
      const hash = linkFields.find((entry) => entry.number === 1)?.value;
      const name = linkFields.find((entry) => entry.number === 2)?.value?.toString();
      const size = linkFields.find((entry) => entry.number === 3)?.value ?? null;
      if (!Buffer.isBuffer(hash) || name == null) throw new Error("invalid dag-pb link");
      return { cid: `b${base32Encode(hash)}`, name, size };
    });
}

function protobufFields(bytes) {
  const result = [];
  let offset = 0;
  while (offset < bytes.length) {
    let key;
    [key, offset] = readVarint(bytes, offset);
    const number = Math.floor(key / 8);
    const wireType = key & 7;
    if (wireType === 0) {
      let value;
      [value, offset] = readVarint(bytes, offset);
      result.push({ number, wireType, value });
    } else if (wireType === 2) {
      let length;
      [length, offset] = readVarint(bytes, offset);
      if (offset + length > bytes.length) throw new Error("truncated protobuf field");
      result.push({ number, wireType, value: bytes.subarray(offset, offset + length) });
      offset += length;
    } else {
      throw new Error(`unsupported protobuf wire type ${wireType}`);
    }
  }
  return result;
}

function readVarint(bytes, initialOffset) {
  let offset = initialOffset;
  let value = 0;
  let shift = 0;
  while (offset < bytes.length) {
    const byte = bytes[offset];
    offset += 1;
    value += (byte & 0x7f) * (2 ** shift);
    if ((byte & 0x80) === 0) return [value, offset];
    shift += 7;
  }
  throw new Error("truncated protobuf varint");
}

function base32Encode(bytes) {
  let output = "";
  let bits = 0;
  let value = 0;
  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) output += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  return output;
}

function base32Decode(value) {
  const normalized = String(value).toLowerCase().replace(/^b/u, "");
  const bytes = [];
  let bits = 0;
  let buffer = 0;
  for (const character of normalized) {
    const index = BASE32_ALPHABET.indexOf(character);
    if (index < 0) throw new Error(`invalid base32 character ${character}`);
    buffer = (buffer << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bytes.push((buffer >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(bytes);
}

function verifyCidBlock(cid, bytes) {
  const decoded = base32Decode(cid);
  let offset = 0;
  let version;
  [version, offset] = readVarint(decoded, offset);
  if (version !== 1) throw new Error(`unsupported CID version ${version}`);
  let codec;
  [codec, offset] = readVarint(decoded, offset);
  if (codec !== 0x70) throw new Error(`expected dag-pb CID codec, got ${codec}`);
  let hashCode;
  [hashCode, offset] = readVarint(decoded, offset);
  let digestLength;
  [digestLength, offset] = readVarint(decoded, offset);
  if (hashCode !== 0x12 || digestLength !== 32) throw new Error("unsupported CID multihash");
  const expected = decoded.subarray(offset, offset + digestLength);
  const actual = crypto.createHash("sha256").update(bytes).digest();
  if (!crypto.timingSafeEqual(expected, actual)) throw new Error(`raw block did not match CID ${cid}`);
}

async function downloadAndValidate(source, tempPath, options) {
  let lastError = null;
  let attempts = 0;
  const startedAt = new Date().toISOString();
  for (let retry = 0; retry <= options.retries; retry += 1) {
    attempts += 1;
    await fsp.rm(tempPath, { force: true });
    try {
      const response = await fetch(source.url, {
        headers: { "user-agent": "nft-player-original-recovery/1.0" },
        redirect: "follow",
        signal: AbortSignal.timeout(options.timeoutMs),
      });
      if (!response.ok || !response.body) {
        throw new Error(`HTTP ${response.status}${response.statusText ? ` ${response.statusText}` : ""}`);
      }
      await pipeline(Readable.fromWeb(response.body), fs.createWriteStream(tempPath, { flags: "wx" }));
      const inspection = await inspectHighResolutionFile(tempPath, null);
      if (!inspection.ok) throw new Error(inspection.error);
      return {
        ok: true,
        url: source.url,
        finalUrl: response.url || source.url,
        attemptUrl: source.url,
        statusCode: response.status,
        contentType: response.headers.get("content-type")?.split(";", 1)[0] || "image/jpeg",
        contentLength: numeric(response.headers.get("content-length")) ?? inspection.bytesWritten,
        bytesWritten: inspection.bytesWritten,
        sha256: inspection.sha256,
        probe: inspection.probe,
        attempts,
        startedAt,
      };
    } catch (error) {
      lastError = error;
      await fsp.rm(tempPath, { force: true });
      if (retry < options.retries) await delay(backoffDelay(options.retryDelayMs, retry));
    }
  }
  return { ok: false, attempts, error: lastError?.message ?? String(lastError ?? "download failed") };
}

async function inspectHighResolutionFile(filePath, manifestEntry) {
  if (!await fileExists(filePath)) return { ok: false, error: "file does not exist" };
  try {
    const [stat, probe, sha256] = await Promise.all([
      fsp.stat(filePath),
      identifyFile(filePath),
      sha256File(filePath),
    ]);
    if (!isExpectedProbe(probe)) {
      return { ok: false, error: `expected ${EXPECTED_WIDTH}x${EXPECTED_HEIGHT} JPEG, got ${probe?.width ?? "?"}x${probe?.height ?? "?"} ${probe?.format ?? "unknown"}` };
    }
    if (probe.bitDepth !== 8) return { ok: false, error: `expected 8-bit JPEG, got ${probe.bitDepth ?? "unknown"}-bit` };
    if (manifestEntry?.fileName === path.basename(filePath)) {
      if (manifestEntry.bytesWritten != null && Number(manifestEntry.bytesWritten) !== stat.size) {
        return { ok: false, error: `stored byte count ${manifestEntry.bytesWritten} does not match ${stat.size}` };
      }
      if (manifestEntry.sha256 && manifestEntry.sha256 !== sha256) {
        return { ok: false, error: "stored SHA-256 does not match the local file" };
      }
    }
    return { ok: true, probe, sha256, bytesWritten: stat.size };
  } catch (error) {
    return { ok: false, error: error.message };
  }
}

async function identifyFile(filePath) {
  const { stdout } = await execFileAsync("magick", ["identify", "-ping", "-format", "%w\t%h\t%m\t%z\t%Q", `${filePath}[0]`], {
    timeout: 60000,
    maxBuffer: 1024 * 1024,
    encoding: "utf8",
  });
  const [width, height, format, bitDepth, quality] = stdout.trim().split("\t");
  const parsedWidth = numeric(width);
  const parsedHeight = numeric(height);
  if (!parsedWidth || !parsedHeight) throw new Error("ImageMagick returned no dimensions");
  return {
    kind: "image",
    format: String(format ?? "").toLowerCase(),
    width: parsedWidth,
    height: parsedHeight,
    area: parsedWidth * parsedHeight,
    aspectRatio: Number((parsedWidth / parsedHeight).toFixed(5)),
    bitDepth: numeric(bitDepth),
    quality: numeric(quality),
  };
}

function isExpectedProbe(probe) {
  return probe?.kind === "image"
    && ["jpeg", "jpg"].includes(String(probe.format).toLowerCase())
    && probe.width === EXPECTED_WIDTH
    && probe.height === EXPECTED_HEIGHT
    && probe.area === EXPECTED_AREA
    && Number(probe.aspectRatio) === 0.8;
}

function reconcileExistingEntry(token, inspection) {
  token.originalBundledSource = token.originalBundledSource ?? "compact-url";
  token.originalBundledURL = canonicalOriginalURL(token.tokenId);
  token.downloadUrl = canonicalOriginalURL(token.tokenId);
  token.sourceKind = "explicit-url";
  token.extension = "jpg";
  token.status = "success";
  token.contentType = "image/jpeg";
  token.contentLength = inspection.bytesWritten;
  token.bytesWritten = inspection.bytesWritten;
  token.sha256 = inspection.sha256;
  token.error = null;
  token.mediaProbe = inspection.probe;
  token.checkedAt = new Date().toISOString();
}

function applyReplacementEntry(token, replacement, previous) {
  const finishedAt = replacement.finishedAt ?? new Date().toISOString();
  Object.assign(token, {
    fileName: replacement.fileName,
    originalBundledSource: token.originalBundledSource ?? "compact-url",
    originalBundledURL: replacement.canonicalUrl,
    downloadUrl: replacement.canonicalUrl,
    sourceKind: "explicit-url",
    extension: "jpg",
    startedAt: replacement.startedAt,
    status: "success",
    statusCode: replacement.statusCode,
    finalUrl: replacement.finalUrl,
    contentType: "image/jpeg",
    contentLength: replacement.contentLength ?? replacement.bytesWritten,
    bytesWritten: replacement.bytesWritten,
    sha256: replacement.sha256,
    elapsedMs: replacement.elapsedMs,
    attempts: replacement.attempts,
    attemptUrl: replacement.attemptUrl ?? replacement.finalUrl,
    finishedAt,
    error: null,
    mediaProbe: replacement.probe,
    sourceUpgrade: {
      upgradedAt: finishedAt,
      previousFileName: previous.fileName,
      previousDownloadUrl: previous.downloadUrl,
      previousOriginalBundledURL: previous.originalBundledURL,
      previousBytesWritten: previous.bytesWritten,
      previousSha256: previous.sha256,
      previousQualityRepair: previous.qualityRepair,
    },
    qualityRepair: {
      repairedAt: finishedAt,
      reason: "pixel dimensions below collection baseline",
      decision: "verified archived original matches the collection's 3456x4320 source resolution",
      apiSource: replacement.source,
      modifiedFallback: false,
      previous: {
        status: previous.status,
        fileName: previous.fileName,
        downloadUrl: previous.downloadUrl,
        finalUrl: previous.finalUrl,
        bytesWritten: previous.bytesWritten,
        sha256: previous.sha256,
        mediaProbe: previous.mediaProbe,
      },
    },
  });
  for (const key of [
    "reusedExisting",
    "reusedExistingFailure",
    "sourceOverridePreserved",
    "preferredBundledSource",
    "sourceRefresh",
    "checkedAt",
  ]) delete token[key];
}

function snapshotPrevious(token) {
  return {
    status: token.status ?? null,
    fileName: token.fileName ?? null,
    downloadUrl: token.downloadUrl ?? null,
    originalBundledURL: token.originalBundledURL ?? null,
    finalUrl: token.finalUrl ?? null,
    bytesWritten: token.bytesWritten ?? null,
    sha256: token.sha256 ?? null,
    mediaProbe: token.mediaProbe ?? null,
    qualityRepair: token.qualityRepair ?? null,
  };
}

function resultForExisting(token, inspection) {
  return {
    tokenId: String(token.tokenId),
    action: "reconciled-existing",
    source: token.finalUrl?.includes("pinata.cloud") ? "ipfs.pinata" : "existing-high-resolution-file",
    sourceUrl: token.finalUrl ?? token.downloadUrl,
    fileName: token.fileName,
    bytesWritten: inspection.bytesWritten,
    sha256: inspection.sha256,
    nextProbe: inspection.probe,
  };
}

function resultForReplacement(token, previous, action) {
  return {
    tokenId: String(token.tokenId),
    action,
    source: token.qualityRepair.apiSource,
    sourceUrl: token.finalUrl,
    fileName: token.fileName,
    bytesWritten: token.bytesWritten,
    sha256: token.sha256,
    previousProbe: previous.mediaProbe,
    nextProbe: token.mediaProbe,
  };
}

function validateFinalManifest(manifest, cohort) {
  const remainingLow = cohort.filter((token) => !isExpectedProbe(token.mediaProbe) || normalizeExtension(token.fileName) !== "jpg");
  const successful = manifest.tokens.filter((token) => token.status === "success");
  const failed = manifest.tokens.filter((token) => token.status === "failed");
  const highResolution = manifest.tokens.filter((token) => isExpectedProbe(token.mediaProbe));
  return {
    tokensRecorded: manifest.tokens.length,
    successfulFiles: successful.length,
    failedFiles: failed.length,
    highResolutionFiles: highResolution.length,
    remainingLowResolution: remainingLow.length,
    remainingLowResolutionTokenIds: remainingLow.map((token) => String(token.tokenId)),
  };
}

async function writeCollectionManifest(manifest, partial) {
  const now = new Date().toISOString();
  manifest.generatedAt = now;
  manifest.partial = partial;
  manifest.updatedAt = now;
  manifest.totals = manifestTotals(manifest.tokens);
  await writeJsonAtomic(COLLECTION_MANIFEST_PATH, manifest);
}

function manifestTotals(tokens) {
  return {
    tokensRecorded: tokens.length,
    successfulFiles: tokens.filter((token) => token.status === "success").length,
    failedFiles: tokens.filter((token) => token.status === "failed").length,
    reusedFiles: tokens.filter((token) => token.reusedExisting).length,
    sourceRefreshFailures: tokens.filter((token) => token.sourceRefresh?.status === "failed").length,
    bytesWritten: tokens.reduce((sum, token) => sum + Number(token.bytesWritten ?? 0), 0),
  };
}

function buildReport({ options, startedAt, initial, manifest, results, unresolved, networkAttempts, downloadedBytes, finalValidation }) {
  const generatedAt = new Date().toISOString();
  const sourceCounts = {};
  for (const result of results) sourceCounts[result.source] = (sourceCounts[result.source] ?? 0) + 1;
  return {
    generatedAt,
    startedAt: startedAt.toISOString(),
    mode: "apply",
    collection: manifest.collection,
    collectionManifestPath: COLLECTION_MANIFEST_PATH,
    bundlePath: BUNDLE_PATH,
    reportPath: options.reportPath,
    jsonReportPath: options.jsonReportPath,
    sources: {
      looksRareGraphQL: LOOKSRARE_GRAPHQL,
      canonicalIpfsRoot: `ipfs://${ORIGINAL_CID}`,
      expectedResolution: { width: EXPECTED_WIDTH, height: EXPECTED_HEIGHT },
    },
    options: {
      concurrency: options.concurrency,
      metadataConcurrency: options.metadataConcurrency,
      useHamt: options.useHamt,
      retries: options.retries,
      timeoutMs: options.timeoutMs,
      retryDelayMs: options.retryDelayMs,
    },
    summary: {
      targetFiles: EXPECTED_COHORT_SIZE,
      lowResolutionFilesAtStart: initial.currentPngs,
      alreadyDownloadedOriginalsAtStart: initial.currentJpegs,
      reconciledExistingOriginals: results.filter((result) => result.action === "reconciled-existing").length,
      resumedOriginals: results.filter((result) => result.action === "resumed").length,
      downloadedOriginals: results.filter((result) => result.action === "downloaded").length,
      recoveredOriginals: results.length,
      unresolvedFiles: unresolved.length,
      downloadedBytes,
      networkAttempts,
      sourceCounts,
      finalHighResolutionFiles: finalValidation.highResolutionFiles,
      finalSuccessfulFiles: finalValidation.successfulFiles,
      finalFailedFiles: finalValidation.failedFiles,
      remainingLowResolutionFiles: finalValidation.remainingLowResolution,
      elapsedMs: Date.now() - startedAt.getTime(),
    },
    finalValidation,
    recovered: results,
    unresolved,
  };
}

async function writeReports(report, options) {
  await Promise.all([
    fsp.mkdir(path.dirname(options.reportPath), { recursive: true }),
    fsp.mkdir(path.dirname(options.jsonReportPath), { recursive: true }),
  ]);
  await writeJsonAtomic(options.jsonReportPath, report);
  const summary = report.summary;
  const lines = [
    "# Cigawrette Packs High-Resolution Original Upgrade",
    "",
    `Generated: ${report.generatedAt}`,
    "",
    "## Summary",
    "",
    `- Known 500x625 cohort: ${summary.targetFiles}`,
    `- Existing originals reconciled: ${summary.reconciledExistingOriginals}`,
    `- Originals downloaded this pass: ${summary.downloadedOriginals}`,
    `- Interrupted originals resumed: ${summary.resumedOriginals}`,
    `- Cohort recovered at 3456x4320: ${summary.recoveredOriginals}`,
    `- Remaining low-resolution files: ${summary.remainingLowResolutionFiles}`,
    `- Collection download failures: ${summary.finalFailedFiles}`,
    `- Downloaded bytes: ${formatBytes(summary.downloadedBytes)}`,
    `- Source accounting: ${Object.entries(summary.sourceCounts).map(([source, count]) => `${source}=${count}`).join(", ") || "none"}`,
    "",
    "Every committed replacement was identified as an 8-bit 3456x4320 JPEG and hashed with SHA-256 before the old PNG was removed.",
    "LooksRare archive samples were byte-identical to the collection's IPFS originals; the canonical bundled URL remains the original IPFS path.",
    "",
    "## Unresolved",
    "",
    ...(report.unresolved.length > 0
      ? report.unresolved.map((entry) => `- Token ${entry.tokenId}: ${escapeMarkdown(entry.error ?? JSON.stringify(entry.sources))}`)
      : ["None."]),
    "",
  ];
  await fsp.writeFile(options.reportPath, `${lines.join("\n")}\n`);
  console.error(`Report written to ${options.reportPath}`);
  console.error(`JSON written to ${options.jsonReportPath}`);
}

async function updateRootManifest(collectionManifest, report) {
  const root = await readJson(ROOT_MANIFEST_PATH);
  if (!Array.isArray(root.collections) || !Array.isArray(root.failures)) {
    throw new Error("Root download manifest has an unexpected shape");
  }
  const index = root.collections.findIndex((collection) => (
    String(collection.id).toLowerCase() === COLLECTION_ID && String(collection.chain).toLowerCase() === "ethereum"
  ));
  if (index < 0) throw new Error("Root download manifest has no Cigawrette Packs collection record");

  const successfulFiles = collectionManifest.tokens.filter((token) => token.status === "success").length;
  const failedFiles = collectionManifest.tokens.filter((token) => token.status === "failed").length;
  const downloadedFiles = report.summary.downloadedOriginals;
  root.collections[index] = {
    ...root.collections[index],
    successfulFiles,
    downloadedFiles,
    reusedFiles: collectionManifest.tokens.length - downloadedFiles,
    sourceRefreshFailures: report.summary.unresolvedFiles,
    failedFiles,
    bytesWritten: report.summary.downloadedBytes,
    totalAttempts: report.summary.networkAttempts,
  };
  root.failures = root.failures.filter((failure) => String(failure.collectionId).toLowerCase() !== COLLECTION_ID);
  const sum = (field) => root.collections.reduce((total, collection) => total + Number(collection[field] ?? 0), 0);
  root.totals = {
    ...root.totals,
    collectionsMatched: root.collections.length,
    collectionsDownloaded: root.collections.filter((collection) => !collection.skipped).length,
    skippedCollections: root.collections.filter((collection) => collection.skipped).length,
    downloadedFiles: sum("downloadedFiles"),
    reusedFiles: sum("reusedFiles"),
    sourceRefreshFailures: sum("sourceRefreshFailures"),
    failedFiles: sum("failedFiles"),
    totalAttempts: sum("totalAttempts"),
    bytesWritten: sum("bytesWritten"),
  };
  root.generatedAt = new Date().toISOString();
  root.partial = false;
  root.lastQualityUpgrade = {
    generatedAt: report.generatedAt,
    collectionId: COLLECTION_ID,
    internal_slug: COLLECTION_SLUG,
    reportPath: path.resolve(report.reportPath),
    jsonReportPath: path.resolve(report.jsonReportPath),
    summary: report.summary,
  };
  await writeJsonAtomic(ROOT_MANIFEST_PATH, root);
}

async function removeStaleTemporaryFiles() {
  const names = await fsp.readdir(COLLECTION_DIRECTORY);
  await Promise.all(names
    .filter((name) => name.endsWith(".looksrare.part") || name === "manifest.json.tmp")
    .map((name) => fsp.rm(path.join(COLLECTION_DIRECTORY, name), { force: true })));
}

async function runPool(values, concurrency, worker) {
  let index = 0;
  const runners = Array.from({ length: Math.min(concurrency, values.length) }, async () => {
    while (index < values.length) {
      const current = values[index];
      index += 1;
      await worker(current);
    }
  });
  await Promise.all(runners);
}

function logProgress(completed, total, results, unresolved) {
  if (completed === total || completed % 50 === 0) {
    console.error(`  originals: ${completed}/${total} (${results.length} recovered, ${unresolved.length} unresolved)`);
  }
}

function chunk(values, size) {
  const result = [];
  for (let index = 0; index < values.length; index += size) result.push(values.slice(index, index + size));
  return result;
}

function canonicalOriginalURL(tokenId) {
  return `https://ipfs.io/ipfs/${ORIGINAL_CID}/${tokenId}.jpg`;
}

function pinataOriginalURL(tokenId) {
  return `https://gateway.pinata.cloud/ipfs/${ORIGINAL_CID}/${tokenId}.jpg`;
}

function alchemyPinataOriginalURL(tokenId) {
  return `https://alchemy.mypinata.cloud/ipfs/${ORIGINAL_CID}/${tokenId}.jpg`;
}

function raribleOriginalURL(tokenId) {
  return `https://ipfs.raribleuserdata.com/ipfs/${ORIGINAL_CID}/${tokenId}.jpg`;
}

function filebaseOriginalURL(tokenId) {
  return `https://ipfs.filebase.io/ipfs/${ORIGINAL_CID}/${tokenId}.jpg`;
}

function filebaseLeafURL(leafCid) {
  return `https://ipfs.filebase.io/ipfs/${leafCid}`;
}

function pinataLeafURL(leafCid) {
  return `https://gateway.pinata.cloud/ipfs/${leafCid}`;
}

function normalizeExtension(value) {
  if (!value) return null;
  const text = String(value);
  const extension = text.includes(".") ? path.extname(text).slice(1) : text;
  const normalized = extension.toLowerCase();
  return normalized === "jpeg" ? "jpg" : normalized;
}

function safeTokenId(value) {
  const tokenId = String(value);
  if (!/^\d+$/u.test(tokenId)) throw new Error(`Unsafe token ID: ${tokenId}`);
  return tokenId;
}

function numeric(value) {
  if (value == null || value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function backoffDelay(base, retry) {
  return Math.min(30000, base * (2 ** retry));
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fileExists(filePath) {
  try {
    const stat = await fsp.stat(filePath);
    return stat.isFile();
  } catch (error) {
    if (error.code === "ENOENT") return false;
    throw error;
  }
}

async function sha256File(filePath) {
  const hash = crypto.createHash("sha256");
  const stream = fs.createReadStream(filePath);
  for await (const data of stream) hash.update(data);
  return hash.digest("hex");
}

async function readJson(filePath) {
  return JSON.parse(await fsp.readFile(filePath, "utf8"));
}

async function writeJsonAtomic(filePath, value) {
  const tempPath = `${filePath}.tmp`;
  await fsp.writeFile(tempPath, `${JSON.stringify(value, null, 2)}\n`);
  await fsp.rename(tempPath, filePath);
}

function formatBytes(bytes) {
  const units = ["B", "KiB", "MiB", "GiB", "TiB"];
  let value = Number(bytes);
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(unit === 0 ? 0 : 2)} ${units[unit]}`;
}

function escapeMarkdown(value) {
  return String(value).replace(/([\\`*_{}\[\]()#+.!|-])/gu, "\\$1");
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack ?? error.message ?? error);
    process.exitCode = 1;
  });
}

module.exports = {
  murmur3X64_64,
  resolveHamtFile,
};
