#!/usr/bin/env node
"use strict";

const fs = require("fs");
const fsp = fs.promises;
const path = require("path");
const crypto = require("crypto");
const { spawn } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const DOWNLOAD_ROOT = path.join(ROOT, "Originals Downloaded");
const ROOT_MANIFEST_PATH = path.join(DOWNLOAD_ROOT, "manifest.json");
const BASELINE_REPORT_PATH = path.join(__dirname, "reports", "originals-download-recovery.json");
const DEFAULT_REPORT_PATH = path.join(__dirname, "reports", "remaining-originals-arweave-recovery.md");
const DEFAULT_JSON_REPORT_PATH = path.join(__dirname, "reports", "remaining-originals-arweave-recovery.json");
const ARWEAVE_GRAPHQL = "https://arweave.net/graphql";
const ARWEAVE_GATEWAY = "https://arweave.net";
const CHUNK_SIZE = 256 * 1024;

const COLLECTION_REQUIREMENTS = new Map([
  ["scarecrow", { format: "png", width: 1000, height: 1250 }],
  ["tojiba_disc_buddies", { format: "png", width: 512, height: 512 }],
  ["organic_evolution", { format: "jpeg", minWidth: 2400, minHeight: 2400 }],
  ["tojia", { format: "png", width: 640, height: 640 }],
  ["tojiba_cpu_corp", { format: "png", width: 640, height: 640 }],
]);

const SIGNATURE_CONFIG = new Map([
  [1, { signatureLength: 512, ownerLength: 512, name: "arweave" }],
  [2, { signatureLength: 64, ownerLength: 32, name: "ed25519" }],
  [3, { signatureLength: 65, ownerLength: 65, name: "ethereum" }],
  [4, { signatureLength: 64, ownerLength: 32, name: "solana" }],
]);

// These parents were found by walking the block-local ANS-104 bundle set after
// the gateway GraphQL index omitted the child data items themselves.
const UNINDEXED_PARENT_HINTS = new Map([
  ["scarecrow", [
    "amhq0ZWE5SZKPYUjqaDp-ovGBzd0Spc2RxSf_1XY1cg",
  ]],
  ["tojia", [
    "IQsf1PC1a6FSjNx0J_HgOJBJ4Rm0c7MZbPlu_GMQaVw",
    "R2a1S8r-B8obgKnWgplB10FxiYa8oL1TCN0q84Ir27c",
    "jiIqeO903riiKUm6GxUdkxBmsbcLQ-TglmlFY11BFbI",
    "w7P6vzbWXLw9kPEBtqQnPZmQd6EahT20-l8nIMDT4CM",
    "a3dseO6waBhGs7K35TKtNTeQsUvR6KS0SgNRXYtXd8g",
    "LnZrD0VNUYPcfaS4sTcaf3Vhz28QgSr5riidiF5hbaI",
  ]],
]);

const HELP = `Usage: node tools/recover_failed_originals_from_arweave_bundles.js [options]

Recover only unresolved rows from tools/reports/originals-download-recovery.json by
extracting their exact ANS-104 payloads from the live parent Arweave bundles.

Options:
  --apply                    Commit validated payloads and update manifests.
  --concurrency <number>     Concurrent item recoveries. Default: 6.
  --retries <number>         Retries for transient HTTP failures. Default: 5.
  --timeout-ms <number>      Per-request timeout. Default: 120000.
  --retry-delay-ms <number>  Base exponential retry delay. Default: 1000.
  --report <path>            Markdown report output.
  --json-report <path>       JSON report output.
  --help                     Show this help.
`;

async function main() {
  const options = parseOptions(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(HELP);
    return;
  }

  const startedAt = new Date();
  const baseline = await readJson(BASELINE_REPORT_PATH);
  const scope = await loadScope(baseline);
  console.error(`Scoped unresolved report rows: ${scope.targets.length}; already recovered rows excluded: ${scope.alreadyRecovered.length}.`);
  if (scope.targets.length === 0) throw new Error("No unresolved baseline-report rows remain");

  const requestStats = { attempts: 0, retries: 0, decodedChunkBytes: 0, httpChunkBytes: 0, chunks: 0 };
  const context = {
    options,
    requestStats,
    manifestByRootId: new Map(),
    parentById: new Map(),
    bundleHeaderById: new Map(),
    graphqlByItemId: new Map(),
  };

  await resolveSourceItemIds(scope.targets, context);
  await resolveBundleLocations(scope, context);

  const unresolvedLocation = scope.targets.filter((target) => !target.bundleLocation);
  if (unresolvedLocation.length > 0) {
    console.error(`Direct indexing left ${unresolvedLocation.length} item(s) unmapped; scanning parent headers referenced by successful peers in the same collections.`);
    await resolveLocationsFromPeerBundles(unresolvedLocation, scope, context);
  }

  const recoverable = scope.targets.filter((target) => target.bundleLocation);
  const unresolved = scope.targets
    .filter((target) => !target.bundleLocation)
    .map((target) => publicTargetError(target, "no parent bundle containing the source data-item could be located"));
  console.error(`Native bundle payloads located: ${recoverable.length}/${scope.targets.length}.`);

  const recovered = [];
  await runPool(recoverable, options.concurrency, async (target, index) => {
    try {
      const result = await recoverTarget(target, context);
      recovered.push(result);
      console.error(`  ${index + 1}/${recoverable.length} ${target.internal_slug} ${target.tokenId}: ${result.mediaProbe.width}x${result.mediaProbe.height}, ${formatBytes(result.bytesWritten)}`);
    } catch (error) {
      unresolved.push(publicTargetError(target, error.message));
      console.error(`  ${index + 1}/${recoverable.length} ${target.internal_slug} ${target.tokenId}: ${error.message}`);
    }
  });

  recovered.sort(targetSort);
  unresolved.sort(targetSort);
  let committed = [];
  if (options.apply) {
    committed = await commitRecoveries(recovered, scope, context);
  } else {
    await removeCandidateFiles(recovered);
  }

  const finalState = options.apply ? await validateFinalState(scope) : null;
  const report = buildReport({ options, startedAt, scope, recovered, committed, unresolved, context, finalState });
  await writeReports(report, options);

  if (options.apply) {
    await updateRootManifest(scope, report);
    await removeStalePartFiles(scope);
  }

  console.error(`Recovered ${report.summary.recoveredFiles}/${report.summary.scopedFailures}; unresolved ${report.summary.unresolvedFiles}.`);
  if (report.summary.unresolvedFiles > 0) process.exitCode = 2;
}

function parseOptions(argv) {
  const options = {
    apply: false,
    concurrency: 6,
    retries: 5,
    timeoutMs: 120000,
    retryDelayMs: 1000,
    reportPath: DEFAULT_REPORT_PATH,
    jsonReportPath: DEFAULT_JSON_REPORT_PATH,
    help: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      const value = argv[index + 1];
      if (value == null) throw new Error(`Missing value for ${arg}`);
      index += 1;
      return value;
    };
    if (arg === "--apply") options.apply = true;
    else if (arg === "--concurrency") options.concurrency = positiveInteger(next(), arg);
    else if (arg === "--retries") options.retries = nonnegativeInteger(next(), arg);
    else if (arg === "--timeout-ms") options.timeoutMs = positiveInteger(next(), arg);
    else if (arg === "--retry-delay-ms") options.retryDelayMs = positiveInteger(next(), arg);
    else if (arg === "--report") options.reportPath = path.resolve(next());
    else if (arg === "--json-report") options.jsonReportPath = path.resolve(next());
    else if (arg === "--help" || arg === "-h") options.help = true;
    else throw new Error(`Unknown option: ${arg}`);
  }
  return options;
}

async function loadScope(baseline) {
  if (!Array.isArray(baseline.failures)) throw new Error("Baseline recovery report has no failures array");
  const bySlug = new Map();
  const targets = [];
  const alreadyRecovered = [];
  const seen = new Set();

  for (const failure of baseline.failures) {
    const internal_slug = String(failure.internal_slug ?? "");
    const tokenId = String(failure.tokenId ?? "");
    const key = `${internal_slug}\u0000${tokenId}`;
    if (seen.has(key)) throw new Error(`Duplicate baseline failure: ${internal_slug} ${tokenId}`);
    seen.add(key);

    let collection = bySlug.get(internal_slug);
    if (!collection) {
      const manifestPath = path.join(DOWNLOAD_ROOT, internal_slug, "manifest.json");
      const manifest = await readJson(manifestPath);
      collection = { internal_slug, manifestPath, directory: path.dirname(manifestPath), manifest };
      bySlug.set(internal_slug, collection);
    }
    const token = collection.manifest.tokens.find((entry) => String(entry.tokenId) === tokenId);
    if (!token) throw new Error(`Baseline failure is absent from current manifest: ${internal_slug} ${tokenId}`);
    if (token.status === "success") {
      alreadyRecovered.push({ internal_slug, tokenId });
      continue;
    }
    if (!COLLECTION_REQUIREMENTS.has(internal_slug)) {
      throw new Error(`Unresolved report row has no approved native-quality requirement: ${internal_slug} ${tokenId}`);
    }
    targets.push({
      ...failure,
      internal_slug,
      tokenId,
      collection,
      token,
      requirement: COLLECTION_REQUIREMENTS.get(internal_slug),
    });
  }

  const unresolvedSlugs = new Set(targets.map((target) => target.internal_slug));
  for (const slug of bySlug.keys()) {
    if (!unresolvedSlugs.has(slug)) bySlug.delete(slug);
  }

  return { baseline, bySlug, targets, alreadyRecovered };
}

async function resolveSourceItemIds(targets, context) {
  for (const target of targets) {
    target.sourceItemId = await sourceItemIdForUrl(target.downloadUrl, context);
    if (!target.sourceItemId) throw new Error(`Could not resolve source data-item for ${target.internal_slug} ${target.tokenId}`);
  }
}

async function sourceItemIdForUrl(urlString, context) {
  const url = new URL(urlString);
  const segments = url.pathname.split("/").filter(Boolean).map(decodeURIComponent);
  if (!segments[0] || !isArweaveId(segments[0])) return null;
  if (segments.length === 1) return segments[0];
  const rootId = segments[0];
  let manifest = context.manifestByRootId.get(rootId);
  if (!manifest) {
    manifest = await fetchJson(`${ARWEAVE_GATEWAY}/raw/${rootId}`, context, `manifest ${rootId}`);
    if (manifest?.manifest !== "arweave/paths" || !manifest.paths) throw new Error(`${rootId} is not an Arweave path manifest`);
    context.manifestByRootId.set(rootId, manifest);
  }
  const manifestPath = segments.slice(1).join("/");
  const itemId = manifest.paths[manifestPath]?.id;
  if (!isArweaveId(itemId)) throw new Error(`Manifest ${rootId} has no valid item for ${manifestPath}`);
  return itemId;
}

async function resolveBundleLocations(scope, context) {
  const ids = [...new Set(scope.targets.map((target) => target.sourceItemId))];
  const nodes = await queryTransactions(ids, context);
  for (const target of scope.targets) {
    const node = nodes.get(target.sourceItemId);
    if (!node?.bundledIn?.id) continue;
    target.declaredDataSize = numeric(node.data?.size);
    await locateTargetsInParent(node.bundledIn.id, [target], context);
  }
}

async function resolveLocationsFromPeerBundles(unresolvedTargets, scope, context) {
  const missingBySlug = groupBy(unresolvedTargets, (target) => target.internal_slug);
  for (const [slug, missing] of missingBySlug) {
    const collection = scope.bySlug.get(slug);
    const wanted = new Set(missing.filter((target) => !target.bundleLocation).map((target) => target.sourceItemId));
    if (wanted.size === 0) continue;
    const hintedParents = UNINDEXED_PARENT_HINTS.get(slug) ?? [];
    for (const parentId of hintedParents) {
      const remaining = missing.filter((target) => !target.bundleLocation);
      if (remaining.length === 0) break;
      await locateTargetsInParent(parentId, remaining, context);
    }
    if (missing.every((target) => target.bundleLocation)) {
      console.error(`  ${slug}: located every unindexed item in ${hintedParents.length} block-local parent bundle hint(s).`);
      continue;
    }
    const peerIds = [];
    for (const token of collection.manifest.tokens) {
      if (token.status !== "success" || !token.downloadUrl) continue;
      try {
        const id = await sourceItemIdForUrl(token.downloadUrl, context);
        if (id && !wanted.has(id)) peerIds.push(id);
      } catch {}
    }
    const uniquePeerIds = [...new Set(peerIds)];
    const sampledPeerIds = sampleEvenly(uniquePeerIds, 180);
    const peerNodes = await queryTransactions(sampledPeerIds, context);
    const candidateParents = [...new Set([...peerNodes.values()].map((node) => node.bundledIn?.id).filter(isArweaveId))];
    console.error(`  ${slug}: sampled ${sampledPeerIds.length}/${uniquePeerIds.length} successful peer items and is scanning ${candidateParents.length} parent bundle header(s) for ${wanted.size} unindexed item(s).`);
    for (const parentId of candidateParents) {
      const remaining = missing.filter((target) => !target.bundleLocation);
      if (remaining.length === 0) break;
      await locateTargetsInParent(parentId, remaining, context);
    }
  }
}

async function queryTransactions(ids, context) {
  const result = new Map();
  const uncached = [];
  for (const id of ids) {
    if (context.graphqlByItemId.has(id)) {
      const cached = context.graphqlByItemId.get(id);
      if (cached) result.set(id, cached);
    } else uncached.push(id);
  }
  for (const batch of chunk(uncached, 9)) {
    const body = {
      query: "query($ids: [ID!]) { transactions(first: 1000, ids: $ids) { edges { node { id bundledIn { id } data { size type } } } } }",
      variables: { ids: batch },
    };
    const payload = await fetchJson(ARWEAVE_GRAPHQL, context, "Arweave GraphQL", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    if (payload.errors?.length) throw new Error(`Arweave GraphQL: ${payload.errors.map((entry) => entry.message).join("; ")}`);
    const nodes = (payload.data?.transactions?.edges ?? []).map((edge) => edge.node).filter(Boolean);
    const byId = new Map(nodes.map((node) => [node.id, node]));
    for (const id of batch) {
      const node = byId.get(id) ?? null;
      context.graphqlByItemId.set(id, node);
      if (node) result.set(id, node);
    }
  }
  return result;
}

async function locateTargetsInParent(parentId, targets, context) {
  const wanted = targets.filter((target) => !target.bundleLocation);
  if (wanted.length === 0) return;
  const header = await loadBundleHeader(parentId, context);
  for (const target of wanted) {
    const item = header.itemsById.get(target.sourceItemId);
    if (!item) continue;
    target.bundleLocation = {
      parentId,
      parentDataStart: header.parent.dataStart,
      parentSize: header.parent.size,
      itemIndex: item.index,
      itemOffset: item.offset,
      itemSize: item.size,
    };
  }
}

async function loadBundleHeader(parentId, context) {
  if (context.bundleHeaderById.has(parentId)) return context.bundleHeaderById.get(parentId);
  const parent = await parentInfo(parentId, context);
  const first = await fetchChunk(parent.dataStart + 1n, context);
  const firstOffset = parent.dataStart - first.start;
  if (firstOffset < 0n || firstOffset + 32n > BigInt(first.buffer.length)) throw new Error(`First chunk did not cover bundle header for ${parentId}`);
  const count = toSafeNumber(readLittleEndian(first.buffer.subarray(Number(firstOffset), Number(firstOffset) + 32)), `item count for ${parentId}`);
  const headerSize = 32 + count * 64;
  if (headerSize > parent.size) throw new Error(`Invalid ANS-104 header size for ${parentId}`);
  const buffer = await fetchParentRange(parent, 0, headerSize, context);
  const itemsById = new Map();
  let itemOffset = headerSize;
  for (let index = 0; index < count; index += 1) {
    const at = 32 + index * 64;
    const size = toSafeNumber(readLittleEndian(buffer.subarray(at, at + 32)), `item size in ${parentId}`);
    const id = base64Url(buffer.subarray(at + 32, at + 64));
    itemsById.set(id, { id, index, size, offset: itemOffset });
    itemOffset += size;
  }
  if (itemOffset !== parent.size) throw new Error(`ANS-104 items total ${itemOffset}, parent ${parentId} declares ${parent.size}`);
  const header = { parent, count, headerSize, itemsById };
  context.bundleHeaderById.set(parentId, header);
  return header;
}

async function parentInfo(parentId, context) {
  if (context.parentById.has(parentId)) return context.parentById.get(parentId);
  const payload = await fetchJson(`${ARWEAVE_GATEWAY}/tx/${parentId}/offset`, context, `parent offset ${parentId}`);
  const size = toSafeNumber(BigInt(payload.size), `parent size ${parentId}`);
  const end = BigInt(payload.offset);
  const parent = { id: parentId, size, dataStart: end - BigInt(size), dataEnd: end };
  context.parentById.set(parentId, parent);
  return parent;
}

async function recoverTarget(target, context) {
  const started = Date.now();
  const location = target.bundleLocation;
  const parent = await parentInfo(location.parentId, context);
  const itemBuffer = await fetchParentRange(parent, location.itemOffset, location.itemSize, context);
  const item = parseDataItem(itemBuffer, target.sourceItemId);
  if (target.declaredDataSize && item.data.length !== target.declaredDataSize) {
    throw new Error(`payload length ${item.data.length} does not match indexed data size ${target.declaredDataSize}`);
  }
  const candidatePath = path.join(target.collection.directory, `.${safeFileComponent(target.tokenId)}.ans104.part`);
  await fsp.writeFile(candidatePath, item.data);
  const mediaProbe = await identifyFile(candidatePath);
  if (!mediaProbe) {
    await fsp.rm(candidatePath, { force: true });
    throw new Error("extracted payload is not a probeable image");
  }
  const decision = validateNativeQuality(mediaProbe, target.requirement);
  if (!decision.ok) {
    await fsp.rm(candidatePath, { force: true });
    throw new Error(decision.error);
  }
  const sha256 = crypto.createHash("sha256").update(item.data).digest("hex");
  return {
    internal_slug: target.internal_slug,
    collectionId: target.collectionId,
    collectionName: target.collectionName,
    tokenId: target.tokenId,
    fileName: target.token.fileName,
    downloadUrl: target.downloadUrl,
    candidatePath,
    destinationPath: path.join(target.collection.directory, target.token.fileName),
    bytesWritten: item.data.length,
    sha256,
    contentType: mediaContentType(mediaProbe.format),
    mediaProbe,
    signatureType: item.signatureType,
    signatureKind: item.signatureKind,
    tagsCount: item.tagsCount,
    tagsBytes: item.tagsBytes,
    itemDataOffset: item.dataOffset,
    sourceItemId: target.sourceItemId,
    parentBundleId: location.parentId,
    parentBundleSize: parent.size,
    bundleItemIndex: location.itemIndex,
    bundleItemOffset: location.itemOffset,
    bundleItemSize: location.itemSize,
    elapsedMs: Date.now() - started,
  };
}

function parseDataItem(buffer, expectedId) {
  if (buffer.length < 2) throw new Error("truncated ANS-104 data item");
  const signatureType = buffer.readUInt16LE(0);
  const config = SIGNATURE_CONFIG.get(signatureType);
  if (!config) throw new Error(`unsupported ANS-104 signature type ${signatureType}`);
  const signatureStart = 2;
  const signatureEnd = signatureStart + config.signatureLength;
  const actualId = base64Url(crypto.createHash("sha256").update(buffer.subarray(signatureStart, signatureEnd)).digest());
  if (actualId !== expectedId) throw new Error(`data-item signature hash ${actualId} does not match ${expectedId}`);
  let offset = signatureEnd + config.ownerLength;
  if (offset + 2 > buffer.length) throw new Error("truncated ANS-104 owner/flags");
  const targetFlag = buffer[offset];
  offset += 1;
  if (targetFlag === 1) offset += 32;
  else if (targetFlag !== 0) throw new Error(`invalid ANS-104 target flag ${targetFlag}`);
  const anchorFlag = buffer[offset];
  offset += 1;
  if (anchorFlag === 1) offset += 32;
  else if (anchorFlag !== 0) throw new Error(`invalid ANS-104 anchor flag ${anchorFlag}`);
  if (offset + 16 > buffer.length) throw new Error("truncated ANS-104 tag lengths");
  const tagsCount = toSafeNumber(readLittleEndian(buffer.subarray(offset, offset + 8)), "tag count");
  offset += 8;
  const tagsBytes = toSafeNumber(readLittleEndian(buffer.subarray(offset, offset + 8)), "tag byte length");
  offset += 8;
  const dataOffset = offset + tagsBytes;
  if (dataOffset > buffer.length) throw new Error("ANS-104 tag bytes exceed item length");
  return { signatureType, signatureKind: config.name, tagsCount, tagsBytes, dataOffset, data: buffer.subarray(dataOffset) };
}

async function fetchParentRange(parent, relativeStart, size, context) {
  const absoluteStart = parent.dataStart + BigInt(relativeStart);
  const absoluteEnd = absoluteStart + BigInt(size);
  if (relativeStart < 0 || size < 0 || relativeStart + size > parent.size) throw new Error(`range exceeds parent ${parent.id}`);
  const parts = [];
  let at = absoluteStart;
  while (at < absoluteEnd) {
    const chunkResult = await fetchChunk(at + 1n, context);
    if (at < chunkResult.start || at >= chunkResult.end) throw new Error(`chunk response does not cover requested offset ${at}`);
    const from = Number(at - chunkResult.start);
    const untilAbsolute = absoluteEnd < chunkResult.end ? absoluteEnd : chunkResult.end;
    const until = Number(untilAbsolute - chunkResult.start);
    parts.push(chunkResult.buffer.subarray(from, until));
    at = untilAbsolute;
  }
  const buffer = Buffer.concat(parts);
  if (buffer.length !== size) throw new Error(`range returned ${buffer.length} bytes, expected ${size}`);
  return buffer;
}

async function fetchChunk(absoluteOffset, context) {
  const response = await fetchWithRetry(`${ARWEAVE_GATEWAY}/chunk/${absoluteOffset}`, context, `chunk ${absoluteOffset}`);
  const text = await response.text();
  context.requestStats.httpChunkBytes += Buffer.byteLength(text);
  let payload;
  try { payload = JSON.parse(text); } catch { throw new Error(`chunk ${absoluteOffset} returned invalid JSON`); }
  const buffer = decodeBase64Url(payload.chunk ?? "");
  const end = BigInt(payload.absolute_end_offset);
  const start = end - BigInt(buffer.length);
  if (buffer.length === 0 || end <= start) throw new Error(`chunk ${absoluteOffset} returned no data`);
  context.requestStats.chunks += 1;
  context.requestStats.decodedChunkBytes += buffer.length;
  return { start, end, buffer };
}

async function fetchJson(url, context, label, init = {}) {
  const response = await fetchWithRetry(url, context, label, init);
  const text = await response.text();
  try { return JSON.parse(text); } catch { throw new Error(`${label} returned invalid JSON`); }
}

async function fetchWithRetry(url, context, label, init = {}) {
  let lastError;
  for (let retry = 0; retry <= context.options.retries; retry += 1) {
    context.requestStats.attempts += 1;
    try {
      const response = await fetch(url, {
        ...init,
        headers: { "user-agent": "nft-player-ans104-original-recovery/1.0", ...(init.headers ?? {}) },
        signal: AbortSignal.timeout(context.options.timeoutMs),
      });
      if (response.ok) return response;
      const detail = (await response.text()).trim().slice(0, 500);
      const error = new Error(`${label} returned HTTP ${response.status}${detail ? `: ${detail}` : ""}`);
      error.status = response.status;
      if (!isTransientStatus(response.status) || retry === context.options.retries) throw error;
      lastError = error;
    } catch (error) {
      lastError = error;
      if (retry === context.options.retries || (error.status && !isTransientStatus(error.status))) break;
    }
    context.requestStats.retries += 1;
    await delay(Math.min(30000, context.options.retryDelayMs * (2 ** retry)));
  }
  throw new Error(`${label}: ${lastError?.message ?? "request failed"}`);
}

async function commitRecoveries(recovered, scope, context) {
  const committed = [];
  const bySlug = groupBy(recovered, (entry) => entry.internal_slug);
  for (const [slug, entries] of bySlug) {
    const collection = scope.bySlug.get(slug);
    const tokenById = new Map(collection.manifest.tokens.map((token) => [String(token.tokenId), token]));
    for (const entry of entries) {
      const token = tokenById.get(entry.tokenId);
      if (!token || token.status === "success") {
        await fsp.rm(entry.candidatePath, { force: true });
        throw new Error(`Refusing to replace non-failed token ${slug} ${entry.tokenId}`);
      }
      if (await fileExists(entry.destinationPath)) {
        await fsp.rm(entry.candidatePath, { force: true });
        throw new Error(`Refusing to overwrite unexpected existing file ${entry.destinationPath}`);
      }
      await fsp.rename(entry.candidatePath, entry.destinationPath);
      const now = new Date().toISOString();
      delete token.error;
      Object.assign(token, {
        status: "success",
        statusCode: 200,
        finalUrl: token.downloadUrl,
        attemptUrl: `ar://${entry.sourceItemId}`,
        contentType: entry.contentType,
        contentLength: entry.bytesWritten,
        bytesWritten: entry.bytesWritten,
        sha256: entry.sha256,
        elapsedMs: entry.elapsedMs,
        attempts: 0,
        finishedAt: now,
        recoveredAt: now,
        reusedExisting: false,
        mediaProbe: entry.mediaProbe,
        recoverySource: {
          kind: "ans-104-parent-bundle-chunks",
          gateway: ARWEAVE_GATEWAY,
          itemId: entry.sourceItemId,
          parentBundleId: entry.parentBundleId,
          parentBundleSize: entry.parentBundleSize,
          bundleItemIndex: entry.bundleItemIndex,
          bundleItemOffset: entry.bundleItemOffset,
          bundleItemSize: entry.bundleItemSize,
          itemDataOffset: entry.itemDataOffset,
          signatureType: entry.signatureType,
        },
      });
      committed.push(entry);
    }
    const now = new Date().toISOString();
    collection.manifest.generatedAt = now;
    collection.manifest.updatedAt = now;
    collection.manifest.partial = false;
    collection.manifest.totals = manifestTotals(collection.manifest.tokens);
    await writeJsonAtomic(collection.manifestPath, collection.manifest);
  }
  return committed;
}

async function validateFinalState(scope) {
  const collections = [];
  let successfulFiles = 0;
  let failedFiles = 0;
  for (const collection of scope.bySlug.values()) {
    const manifest = await readJson(collection.manifestPath);
    const scoped = scope.targets.filter((target) => target.internal_slug === collection.internal_slug);
    const scopedResults = [];
    for (const target of scoped) {
      const token = manifest.tokens.find((entry) => String(entry.tokenId) === target.tokenId);
      const filePath = token ? path.join(collection.directory, token.fileName) : null;
      const exists = Boolean(filePath && await fileExists(filePath));
      const partExists = await fileExists(path.join(collection.directory, `.${safeFileComponent(target.tokenId)}.ans104.part`));
      const hashMatches = Boolean(exists && token.sha256 && await sha256File(filePath) === token.sha256);
      scopedResults.push({ tokenId: target.tokenId, status: token?.status ?? "missing", exists, hashMatches, partExists, mediaProbe: token?.mediaProbe ?? null });
      if (token?.status === "success" && exists && hashMatches && !partExists) successfulFiles += 1;
      else failedFiles += 1;
    }
    collections.push({ internal_slug: collection.internal_slug, scopedFiles: scoped.length, successfulFiles: scopedResults.filter((entry) => entry.status === "success" && entry.exists && entry.hashMatches && !entry.partExists).length, failedFiles: scopedResults.filter((entry) => !(entry.status === "success" && entry.exists && entry.hashMatches && !entry.partExists)).length, tokens: scopedResults });
  }
  return { scopedFiles: scope.targets.length, successfulFiles, failedFiles, collections };
}

function buildReport({ options, startedAt, scope, recovered, committed, unresolved, context, finalState }) {
  const appliedRecovered = options.apply ? committed : recovered;
  const collections = [];
  for (const [slug, targets] of groupBy(scope.targets, (target) => target.internal_slug)) {
    const rows = appliedRecovered.filter((entry) => entry.internal_slug === slug);
    const failures = unresolved.filter((entry) => entry.internal_slug === slug);
    collections.push({
      internal_slug: slug,
      name: targets[0].collectionName,
      scopedFailures: targets.length,
      recoveredFiles: rows.length,
      unresolvedFiles: failures.length,
      recoveredBytes: rows.reduce((sum, entry) => sum + entry.bytesWritten, 0),
      nativeDimensions: [...new Set(rows.map((entry) => `${entry.mediaProbe.width}x${entry.mediaProbe.height} ${entry.mediaProbe.format}`))].sort(),
    });
  }
  collections.sort((left, right) => left.internal_slug.localeCompare(right.internal_slug));
  return {
    generatedAt: new Date().toISOString(),
    startedAt: startedAt.toISOString(),
    mode: options.apply ? "apply" : "dry-run",
    baselineReportPath: BASELINE_REPORT_PATH,
    rootManifestPath: ROOT_MANIFEST_PATH,
    reportPath: options.reportPath,
    jsonReportPath: options.jsonReportPath,
    source: {
      kind: "ANS-104 parent bundle chunk extraction",
      gateway: ARWEAVE_GATEWAY,
      graphql: ARWEAVE_GRAPHQL,
      validation: "SHA-256(data-item signature) equals source item ID; extracted payload meets collection-native dimensions",
    },
    options: { concurrency: options.concurrency, retries: options.retries, timeoutMs: options.timeoutMs, retryDelayMs: options.retryDelayMs },
    summary: {
      baselineFailures: scope.baseline.failures.length,
      excludedAlreadyRecovered: scope.alreadyRecovered.length,
      scopedFailures: scope.targets.length,
      recoveredFiles: appliedRecovered.length,
      unresolvedFiles: unresolved.length,
      recoveredBytes: appliedRecovered.reduce((sum, entry) => sum + entry.bytesWritten, 0),
      parentBundlesRead: context.bundleHeaderById.size,
      chunkResponses: context.requestStats.chunks,
      decodedChunkBytes: context.requestStats.decodedChunkBytes,
      httpChunkBytes: context.requestStats.httpChunkBytes,
      networkAttempts: context.requestStats.attempts,
      networkRetries: context.requestStats.retries,
      finalScopedSuccessfulFiles: finalState?.successfulFiles ?? null,
      finalScopedFailedFiles: finalState?.failedFiles ?? null,
      elapsedMs: Date.now() - startedAt.getTime(),
    },
    excludedAlreadyRecovered: scope.alreadyRecovered,
    collections,
    recovered: appliedRecovered.map(publicRecovery),
    unresolved,
    finalValidation: finalState,
  };
}

async function writeReports(report, options) {
  await Promise.all([fsp.mkdir(path.dirname(options.reportPath), { recursive: true }), fsp.mkdir(path.dirname(options.jsonReportPath), { recursive: true })]);
  await writeJsonAtomic(options.jsonReportPath, report);
  const lines = [
    "# Remaining Original-Media Arweave Recovery",
    "",
    `Generated: ${report.generatedAt}`,
    "",
    "## Summary",
    "",
    `- Baseline report failures: ${report.summary.baselineFailures}`,
    `- Already recovered and excluded: ${report.summary.excludedAlreadyRecovered}`,
    `- Failures in this exact pass: ${report.summary.scopedFailures}`,
    `- Exact native payloads recovered: ${report.summary.recoveredFiles}`,
    `- Still unresolved: ${report.summary.unresolvedFiles}`,
    `- Recovered payload bytes: ${formatBytes(report.summary.recoveredBytes)}`,
    `- Parent bundle headers read: ${report.summary.parentBundlesRead}`,
    `- Arweave chunks read: ${report.summary.chunkResponses} (${formatBytes(report.summary.decodedChunkBytes)} decoded)`,
    "",
    "Each recovered file is the exact payload from its original ANS-104 data item. The recovery validates the data-item ID from its signature before accepting the payload, then requires the same native dimensions and format as successful peers in that collection.",
    "",
    "## Collections",
    "",
    "| Collection | Scoped | Recovered | Unresolved | Native recovered dimensions |",
    "| --- | ---: | ---: | ---: | --- |",
    ...report.collections.map((entry) => `| ${escapeCell(entry.name)} | ${entry.scopedFailures} | ${entry.recoveredFiles} | ${entry.unresolvedFiles} | ${escapeCell(entry.nativeDimensions.join(", ") || "none")} |`),
    "",
    "## Unresolved",
    "",
    ...(report.unresolved.length ? report.unresolved.map((entry) => `- ${escapeMarkdown(entry.collectionName)} token ${escapeMarkdown(entry.tokenId)}: ${escapeMarkdown(entry.error)}`) : ["None."]),
    "",
  ];
  await fsp.writeFile(options.reportPath, `${lines.join("\n")}\n`);
}

async function updateRootManifest(scope, report) {
  const root = await readJson(ROOT_MANIFEST_PATH);
  if (!Array.isArray(root.collections) || !Array.isArray(root.failures)) throw new Error("Root manifest has an unexpected shape");
  const recoveredBySlug = groupBy(report.recovered, (entry) => entry.internal_slug);
  const unresolvedKeys = new Set(report.unresolved.map((entry) => `${entry.internal_slug}\u0000${entry.tokenId}`));
  const scopedKeys = new Set(scope.targets.map((target) => `${target.internal_slug}\u0000${target.tokenId}`));

  for (const collection of scope.bySlug.values()) {
    const manifest = await readJson(collection.manifestPath);
    const index = root.collections.findIndex((entry) => entry.internal_slug === collection.internal_slug);
    if (index < 0) throw new Error(`Root manifest has no ${collection.internal_slug} record`);
    const recovered = recoveredBySlug.get(collection.internal_slug) ?? [];
    const failed = manifest.tokens.filter((token) => token.status !== "success");
    root.collections[index] = {
      ...root.collections[index],
      successfulFiles: manifest.tokens.length - failed.length,
      downloadedFiles: Number(root.collections[index].downloadedFiles ?? 0) + recovered.length,
      failedFiles: failed.length,
      bytesWritten: Number(root.collections[index].bytesWritten ?? 0) + recovered.reduce((sum, entry) => sum + Number(entry.bytesWritten ?? 0), 0),
      totalAttempts: Number(root.collections[index].totalAttempts ?? 0),
    };
  }

  root.failures = root.failures.filter((failure) => !scopedKeys.has(`${failure.internal_slug}\u0000${failure.tokenId}`));
  for (const target of scope.targets) {
    const key = `${target.internal_slug}\u0000${target.tokenId}`;
    if (!unresolvedKeys.has(key)) continue;
    const unresolved = report.unresolved.find((entry) => `${entry.internal_slug}\u0000${entry.tokenId}` === key);
    root.failures.push({
      collectionId: target.collectionId,
      collectionName: target.collectionName,
      internal_slug: target.internal_slug,
      tokenId: target.tokenId,
      downloadUrl: target.downloadUrl,
      statusCode: null,
      error: unresolved?.error ?? "recovery failed",
    });
  }
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
  root.lastFailureRecovery = {
    generatedAt: report.generatedAt,
    baselineReportPath: path.resolve(report.baselineReportPath),
    reportPath: path.resolve(report.reportPath),
    jsonReportPath: path.resolve(report.jsonReportPath),
    summary: report.summary,
  };
  await writeJsonAtomic(ROOT_MANIFEST_PATH, root);
}

async function removeCandidateFiles(recovered) {
  await Promise.all(recovered.map((entry) => fsp.rm(entry.candidatePath, { force: true })));
}

async function removeStalePartFiles(scope) {
  for (const collection of scope.bySlug.values()) {
    const names = await fsp.readdir(collection.directory);
    await Promise.all(names.filter((name) => name.endsWith(".ans104.part") || name === "manifest.json.tmp").map((name) => fsp.rm(path.join(collection.directory, name), { force: true })));
  }
}

function validateNativeQuality(probe, requirement) {
  const format = probe.format === "jpg" ? "jpeg" : probe.format;
  if (format !== requirement.format) return { ok: false, error: `extracted format ${format} does not match required ${requirement.format}` };
  if (requirement.width && (probe.width !== requirement.width || probe.height !== requirement.height)) {
    return { ok: false, error: `extracted dimensions ${probe.width}x${probe.height} do not match required ${requirement.width}x${requirement.height}` };
  }
  if (requirement.minWidth && (probe.width < requirement.minWidth || probe.height < requirement.minHeight)) {
    return { ok: false, error: `extracted dimensions ${probe.width}x${probe.height} are below required ${requirement.minWidth}x${requirement.minHeight}` };
  }
  return { ok: true };
}

async function identifyFile(filePath) {
  const execution = await runCommand("identify", ["-ping", "-format", "%w\t%h\t%m\t%z\t%Q", `${filePath}[0]`], 60000);
  if (execution.exitCode !== 0) return null;
  const [widthValue, heightValue, formatValue, bitDepthValue, qualityValue] = execution.stdout.trim().split("\t");
  const width = numeric(widthValue);
  const height = numeric(heightValue);
  if (!width || !height) return null;
  return { kind: "image", format: String(formatValue).toLowerCase(), width, height, area: width * height, aspectRatio: Number((width / height).toFixed(5)), bitDepth: numeric(bitDepthValue), quality: numeric(qualityValue) };
}

function runCommand(command, args, timeoutMs) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (data) => stdout.push(data));
    child.stderr.on("data", (data) => stderr.push(data));
    const timer = setTimeout(() => child.kill("SIGKILL"), timeoutMs);
    child.on("close", (exitCode, signal) => {
      clearTimeout(timer);
      resolve({ exitCode: exitCode ?? (signal ? 1 : 0), stdout: Buffer.concat(stdout).toString("utf8"), stderr: Buffer.concat(stderr).toString("utf8") });
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      resolve({ exitCode: 1, stdout: "", stderr: error.message });
    });
  });
}

function manifestTotals(tokens) {
  const successful = tokens.filter((token) => token.status === "success");
  return {
    tokensRecorded: tokens.length,
    successfulFiles: successful.length,
    failedFiles: tokens.length - successful.length,
    reusedFiles: successful.filter((token) => token.reusedExisting).length,
    sourceRefreshFailures: tokens.filter((token) => token.sourceRefresh?.status === "failed").length,
    bytesWritten: successful.reduce((sum, token) => sum + Number(token.bytesWritten ?? 0), 0),
  };
}

function publicRecovery(entry) {
  const { candidatePath, destinationPath, ...publicEntry } = entry;
  return publicEntry;
}

function publicTargetError(target, error) {
  return { internal_slug: target.internal_slug, collectionId: target.collectionId, collectionName: target.collectionName, tokenId: target.tokenId, downloadUrl: target.downloadUrl, sourceItemId: target.sourceItemId ?? null, error };
}

function targetSort(left, right) {
  return String(left.internal_slug).localeCompare(String(right.internal_slug)) || String(left.tokenId).localeCompare(String(right.tokenId));
}

function groupBy(values, keyFunction) {
  const result = new Map();
  for (const value of values) {
    const key = keyFunction(value);
    const rows = result.get(key) ?? [];
    rows.push(value);
    result.set(key, rows);
  }
  return result;
}

async function runPool(items, concurrency, worker) {
  let next = 0;
  const runners = Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    for (;;) {
      const index = next;
      next += 1;
      if (index >= items.length) return;
      await worker(items[index], index);
    }
  });
  await Promise.all(runners);
}

function chunk(values, size) {
  const result = [];
  for (let index = 0; index < values.length; index += size) result.push(values.slice(index, index + size));
  return result;
}

function sampleEvenly(values, maximum) {
  if (values.length <= maximum) return values;
  const sampled = [];
  const seen = new Set();
  for (let index = 0; index < maximum; index += 1) {
    const sourceIndex = Math.round(index * (values.length - 1) / (maximum - 1));
    const value = values[sourceIndex];
    if (!seen.has(value)) {
      seen.add(value);
      sampled.push(value);
    }
  }
  return sampled;
}

function readLittleEndian(buffer) {
  let value = 0n;
  for (let index = buffer.length - 1; index >= 0; index -= 1) value = (value << 8n) + BigInt(buffer[index]);
  return value;
}

function toSafeNumber(value, label) {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < 0) throw new Error(`${label} is outside the safe integer range`);
  return number;
}

function base64Url(buffer) {
  return buffer.toString("base64").replace(/=/gu, "").replace(/\+/gu, "-").replace(/\//gu, "_");
}

function decodeBase64Url(value) {
  return Buffer.from(String(value).replace(/-/gu, "+").replace(/_/gu, "/"), "base64");
}

function isArweaveId(value) {
  return typeof value === "string" && /^[A-Za-z0-9_-]{43}$/u.test(value);
}

function safeFileComponent(value) {
  const text = String(value);
  if (!/^[A-Za-z0-9_-]+$/u.test(text)) throw new Error(`Unsafe file component: ${text}`);
  return text;
}

function mediaContentType(format) {
  return format === "jpeg" || format === "jpg" ? "image/jpeg" : `image/${format}`;
}

function isTransientStatus(status) {
  return status === 408 || status === 425 || status === 429 || status >= 500;
}

function positiveInteger(value, name) {
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) throw new Error(`${name} must be a positive integer`);
  return number;
}

function nonnegativeInteger(value, name) {
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0) throw new Error(`${name} must be a nonnegative integer`);
  return number;
}

function numeric(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function formatBytes(value) {
  const units = ["B", "KB", "MB", "GB", "TB"];
  let number = Number(value ?? 0);
  let unit = 0;
  while (number >= 1024 && unit < units.length - 1) { number /= 1024; unit += 1; }
  return `${number.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`;
}

function escapeCell(value) {
  return String(value ?? "").replace(/\|/gu, "\\|").replace(/\n/gu, " ");
}

function escapeMarkdown(value) {
  return String(value ?? "").replace(/([*_`])/gu, "\\$1");
}

async function fileExists(filePath) {
  try { return (await fsp.stat(filePath)).isFile(); }
  catch (error) { if (error.code === "ENOENT") return false; throw error; }
}

async function sha256File(filePath) {
  const hash = crypto.createHash("sha256");
  for await (const data of fs.createReadStream(filePath)) hash.update(data);
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

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack ?? error.message);
    process.exitCode = 1;
  });
}

module.exports = { parseDataItem, readLittleEndian, validateNativeQuality };
