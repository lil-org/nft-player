#!/usr/bin/env node

const fs = require("node:fs");
const fsp = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawn } = require("node:child_process");
const { Readable, Transform } = require("node:stream");
const { pipeline } = require("node:stream/promises");
const {
  assertValidInternalSlugs,
  collectionIdentityKey,
  suggestedItemId: collectionIdFor,
} = require("./suggested_items");
const { isCdnLilManagedCollection } = require("./cdn_lil_managed_collections");

const DEFAULT_BUNDLE_PATH = path.join("Suggested Items", "Suggested.bundle");
const DEFAULT_OUTPUT_ROOT = "Originals Downloaded";
const DEFAULT_REPORT_PATH = path.join("tools", "reports", "originals-download-report.md");
const DEFAULT_JSON_REPORT_PATH = path.join("tools", "reports", "originals-download-report.json");
const CDN_LIL_HOST_RE = /(^|\.)cdn\.lil\.org$/iu;
const TRANSIENT_HTTP_STATUSES = new Set([408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524]);
const EXTENSION_BY_MIME = new Map([
  ["image/png", "png"],
  ["image/jpeg", "jpg"],
  ["image/jpg", "jpg"],
  ["image/webp", "webp"],
  ["image/heic", "heic"],
  ["image/heif", "heif"],
  ["image/gif", "gif"],
  ["image/svg+xml", "svg"],
  ["video/mp4", "mp4"],
  ["video/quicktime", "mov"],
  ["video/x-quicktime", "mov"],
  ["text/html", "html"],
  ["application/xhtml+xml", "html"],
  ["application/json", "json"],
]);

function usage() {
  return `
Usage:
  node tools/download_bundled_collection_originals.js [options]

Options:
  --apply                 Write downloaded media and manifests. Default is dry-run preflight.
  --bundle <path>         Suggested.bundle path. Default: ${DEFAULT_BUNDLE_PATH}
  --output-root <path>    Download root. Default: ${DEFAULT_OUTPUT_ROOT}
  --report <path>         Markdown report path. Default: ${DEFAULT_REPORT_PATH}
  --json-report <path>    JSON report path. Default: ${DEFAULT_JSON_REPORT_PATH}
                          Filtered runs use *.filtered.* unless a path is explicit.
  --collection <text>     Optional collection name/slug/id/address filter. Can be repeated.
  --start-at <text>       Start processing at the first matching collection name/slug/id/address.
  --skip-collection <text>
                          Optional collection name/slug/id/address skip filter. Can be repeated.
  --include-cdn-lil       Include collections whose resolved media points at cdn.lil.org.
  --concurrency <number>  Simultaneous token downloads/checks. Default: 4
  --retries <number>      Retries for transient failures. Default: 3
  --timeout-ms <number>   Timeout per request. Default: 60000
  --retry-delay-ms <n>    Base retry delay. Default: 1000
  --overwrite             Redownload even when a manifest-verified file already exists.
  --no-retry-failures     Preserve existing failed manifest entries instead of retrying them.
  --keep-partials         Keep failed .part files. Default removes partial files.
  --no-estimate-head      Dry-run without HEAD content-length checks.
  --help                  Show this help.
`.trim();
}

function parseArgs(argv) {
  const options = {
    apply: false,
    bundlePath: DEFAULT_BUNDLE_PATH,
    outputRoot: DEFAULT_OUTPUT_ROOT,
    reportPath: DEFAULT_REPORT_PATH,
    jsonReportPath: DEFAULT_JSON_REPORT_PATH,
    collectionFilters: [],
    startAtFilter: null,
    skipCollectionFilters: [],
    includeCdnLil: false,
    concurrency: 4,
    retries: 3,
    timeoutMs: 60000,
    retryDelayMs: 1000,
    overwrite: false,
    retryFailures: true,
    keepPartials: false,
    estimateHead: true,
    reportPathExplicit: false,
    jsonReportPathExplicit: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const readValue = () => {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) {
        throw new Error(`Missing value for ${arg}`);
      }
      index += 1;
      return value;
    };

    switch (arg) {
      case "--apply":
        options.apply = true;
        break;
      case "--bundle":
        options.bundlePath = readValue();
        break;
      case "--output-root":
        options.outputRoot = readValue();
        break;
      case "--report":
        options.reportPath = readValue();
        options.reportPathExplicit = true;
        break;
      case "--json-report":
        options.jsonReportPath = readValue();
        options.jsonReportPathExplicit = true;
        break;
      case "--collection":
        options.collectionFilters.push(readValue().toLowerCase());
        break;
      case "--start-at":
        options.startAtFilter = readValue().toLowerCase();
        break;
      case "--skip-collection":
        options.skipCollectionFilters.push(readValue().toLowerCase());
        break;
      case "--include-cdn-lil":
        options.includeCdnLil = true;
        break;
      case "--concurrency":
        options.concurrency = positiveInteger(readValue(), arg);
        break;
      case "--retries":
        options.retries = nonNegativeInteger(readValue(), arg);
        break;
      case "--timeout-ms":
        options.timeoutMs = positiveInteger(readValue(), arg);
        break;
      case "--retry-delay-ms":
        options.retryDelayMs = positiveInteger(readValue(), arg);
        break;
      case "--overwrite":
        options.overwrite = true;
        break;
      case "--no-retry-failures":
        options.retryFailures = false;
        break;
      case "--keep-partials":
        options.keepPartials = true;
        break;
      case "--no-estimate-head":
        options.estimateHead = false;
        break;
      case "--help":
        console.log(usage());
        process.exit(0);
        break;
      default:
        throw new Error(`Unknown option: ${arg}`);
    }
  }

  return options;
}

function positiveInteger(value, optionName) {
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) {
    throw new Error(`${optionName} must be a positive integer`);
  }
  return number;
}

function nonNegativeInteger(value, optionName) {
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0) {
    throw new Error(`${optionName} must be a non-negative integer`);
  }
  return number;
}

function hasRunFilters(options) {
  return options.collectionFilters.length > 0
    || options.startAtFilter != null
    || options.skipCollectionFilters.length > 0;
}

function adjustFilteredReportPaths(options) {
  if (!hasRunFilters(options)) return;
  if (!options.reportPathExplicit) {
    options.reportPath = pathWithSuffix(options.reportPath, "filtered");
  }
  if (!options.jsonReportPathExplicit) {
    options.jsonReportPath = pathWithSuffix(options.jsonReportPath, "filtered");
  }
}

function pathWithSuffix(filePath, suffix) {
  const extension = path.extname(filePath);
  if (!extension) return `${filePath}.${suffix}`;
  return `${filePath.slice(0, filePath.length - extension.length)}.${suffix}${extension}`;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  adjustFilteredReportPaths(options);
  const startedAt = new Date();
  const loaded = await loadCollections(options);
  if (options.apply) {
    await assertOutputDirectoryOwnership(loaded);
  }
  const freeDiskBytes = await availableBytesForPath(path.resolve(options.outputRoot));

  const selectedCollections = loaded.collections.filter((collection) => !collection.skipped);
  const totalTokens = selectedCollections.reduce((sum, collection) => sum + collection.tokens.length, 0);
  const skippedTokens = loaded.collections
    .filter((collection) => collection.skipped)
    .reduce((sum, collection) => sum + collection.tokens.length, 0);

  console.error(`${options.apply ? "Downloading" : "Preflighting"} ${selectedCollections.length} collection(s), ${totalTokens} token file(s); skipped ${loaded.collections.length - selectedCollections.length} collection(s), ${skippedTokens} token row(s).`);

  let result;
  if (options.apply) {
    result = await runDownload(loaded, options, startedAt, freeDiskBytes);
  } else {
    result = await runDryRun(loaded, options, startedAt, freeDiskBytes);
  }

  await writeReportFiles(result, options);
  console.log(JSON.stringify(result.summary, null, 2));
}

async function loadCollections(options) {
  const bundlePath = path.resolve(options.bundlePath);
  const outputRoot = path.resolve(options.outputRoot);
  const itemsPath = path.join(bundlePath, "items.json");
  const tokensPath = path.join(bundlePath, "Tokens");
  const [items, tokenFileNames] = await Promise.all([
    readJson(itemsPath),
    fsp.readdir(tokensPath),
  ]);
  assertValidInternalSlugs(items);
  const collectionFilters = prepareCollectionFilters(options.collectionFilters, items);
  const startAtFilters = prepareCollectionFilters(options.startAtFilter == null ? [] : [options.startAtFilter], items);
  const skipCollectionFilters = prepareCollectionFilters(options.skipCollectionFilters, items);

  const tokenFileNameById = new Map(
    tokenFileNames
      .filter((fileName) => fileName.endsWith(".json"))
      .flatMap((fileName) => {
        const id = fileName.slice(0, -".json".length);
        return [[id, fileName], [id.toLowerCase(), fileName]];
      }),
  );

  const collections = [];
  const missingTokenFiles = [];
  let startAtMatched = options.startAtFilter == null;
  for (const item of items) {
    const collectionId = collectionIdFor(item);
    const managedByCdnLil = isCdnLilManagedCollection(item);
    if (!startAtMatched) {
      if (matchesCollectionFilter(collectionId, item, startAtFilters)) {
        startAtMatched = true;
      } else {
        continue;
      }
    }

    if (options.collectionFilters.length > 0) {
      if (!matchesCollectionFilter(collectionId, item, collectionFilters)) {
        continue;
      }
    }

    const skippedByFilter = matchesCollectionFilter(collectionId, item, skipCollectionFilters);

    const tokenFileName = tokenFileNameById.get(collectionId) ?? tokenFileNameById.get(collectionId.toLowerCase());
    if (!tokenFileName) {
      if (managedByCdnLil && !options.includeCdnLil) {
        collections.push({
          id: collectionId,
          name: item.name ?? null,
          internalSlug: item.internal_slug,
          address: item.address ?? null,
          chain: item.chain ?? null,
          chainId: item.chainId ?? null,
          projectId: item.abId ?? item.collectionId ?? null,
          tokenFile: null,
          tokenFilePath: null,
          outputDirectory: path.join(outputRoot, item.internal_slug),
          tokenCount: 0,
          skipped: true,
          skippedByCdnLil: true,
          skippedByFilter,
          skipReason: "native collection media is managed by cdn.lil.org",
          tokens: [],
        });
        continue;
      }
      missingTokenFiles.push({
        id: collectionId,
        name: item.name,
        address: item.address,
        chain: item.chain,
        chainId: item.chainId,
      });
      continue;
    }

    const tokenFilePath = path.join(tokensPath, tokenFileName);
    const payload = await readJson(tokenFilePath);
    const tokens = assignFileNames(normalizeBundledTokenRows(payload, item));
    const hasCdnLil = tokens.some((token) => isCdnLilURL(token.downloadUrl));
    const skippedByCdnLil = (hasCdnLil || managedByCdnLil) && !options.includeCdnLil;
    const skipReasons = [
      skippedByCdnLil
        ? managedByCdnLil
          ? "native collection media is managed by cdn.lil.org"
          : "current resolved bundled token URL contains cdn.lil.org"
        : null,
      skippedByFilter ? "matched --skip-collection filter" : null,
    ].filter(Boolean);
    const skipped = skipReasons.length > 0;
    collections.push({
      id: collectionId,
      name: item.name ?? null,
      internalSlug: item.internal_slug,
      address: item.address ?? null,
      chain: item.chain ?? null,
      chainId: item.chainId ?? null,
      projectId: item.abId ?? item.collectionId ?? null,
      tokenFile: tokenFileName,
      tokenFilePath,
      outputDirectory: path.join(outputRoot, item.internal_slug),
      tokenCount: tokens.length,
      skipped,
      skippedByCdnLil,
      skippedByFilter,
      skipReason: skipped ? skipReasons.join("; ") : null,
      tokens,
    });
  }

  if (!startAtMatched) {
    throw new Error(`No collection matched --start-at ${options.startAtFilter}`);
  }

  return {
    bundlePath,
    outputRoot,
    itemsPath,
    tokensPath,
    items,
    collections,
    missingTokenFiles,
    suggestedItemsMatched: items.length,
    bundledTokenJsonFiles: tokenFileNameById.size / 2,
  };
}

function prepareCollectionFilters(filters, items) {
  return filters.map((value) => {
    const normalized = String(value).toLowerCase();
    const exactIdentity = items.some((item) => collectionFilterIdentities(collectionIdFor(item), item).includes(normalized));
    return { value: normalized, exactIdentity };
  });
}

function collectionFilterIdentities(collectionId, item) {
  return [collectionId, item.internal_slug, item.address]
    .filter((value) => value != null)
    .map((value) => String(value).toLowerCase());
}

function matchesCollectionFilter(collectionId, item, filters) {
  if (filters.length === 0) {
    return false;
  }
  const identities = collectionFilterIdentities(collectionId, item);
  const fuzzyHaystack = `${collectionId} ${item.name ?? ""} ${item.address ?? ""}`.toLowerCase();
  return filters.some((filter) => filter.exactIdentity
    ? identities.includes(filter.value)
    : fuzzyHaystack.includes(filter.value));
}

function normalizeBundledTokenRows(payload, item) {
  const defaultFileExtension = normalizeExtension(payload.defaultFileExtension);
  const urlPrefixes = Array.isArray(payload.urlPrefixes) ? payload.urlPrefixes : [];
  return (payload.items ?? []).map((row, index) => {
    const record = normalizeBundledTokenRow(row, index, defaultFileExtension, urlPrefixes, item);
    const extension = record.fileExtension
      ?? extensionFromURL(record.downloadUrl)
      ?? extensionFromMime(record.mimeType)
      ?? (record.sourceKind === "artblocks-media-proxy" ? "png" : null)
      ?? "bin";
    return {
      ...record,
      extension,
    };
  });
}

function normalizeBundledTokenRow(row, index, defaultFileExtension, urlPrefixes, item) {
  if (Array.isArray(row)) {
    const id = String(row[0]);
    const prefix = urlPrefixes[Number(row[1])] ?? "";
    const rawUrl = `${prefix}${row[2] ?? ""}`;
    const target = normalizeAppURL(rawUrl);
    return {
      id,
      name: null,
      originalBundledSource: "compact-url",
      originalBundledURL: rawUrl,
      downloadUrl: target.url,
      sourceKind: target.kind,
      fileExtension: normalizeExtension(row[3]) ?? defaultFileExtension,
      mimeType: target.mimeType ?? null,
    };
  }

  const id = String(row?.id ?? row?.tokenId ?? index);
  if (row?.sh) {
    const url = `https://cdn.simplehash.com/assets/${row.sh}`;
    return {
      id,
      name: row.name ?? null,
      originalBundledSource: "sh",
      originalBundledURL: row.sh,
      downloadUrl: url,
      sourceKind: "simplehash",
      fileExtension: normalizeExtension(row.fileExtension) ?? extensionFromURL(url) ?? defaultFileExtension,
      mimeType: null,
    };
  }

  if (row?.url) {
    const target = normalizeAppURL(row.url);
    return {
      id,
      name: row.name ?? null,
      originalBundledSource: "url",
      originalBundledURL: row.url,
      downloadUrl: target.url,
      sourceKind: target.kind,
      fileExtension: normalizeExtension(row.fileExtension) ?? defaultFileExtension,
      mimeType: target.mimeType ?? null,
      embeddedBytes: target.embeddedBytes ?? null,
    };
  }

  const url = `https://media-proxy.artblocks.io/${item.address}/${id}.png`;
  return {
    id,
    name: row?.name ?? null,
    originalBundledSource: "id-only",
    originalBundledURL: null,
    downloadUrl: url,
    sourceKind: "artblocks-media-proxy",
    fileExtension: normalizeExtension(row?.fileExtension) ?? defaultFileExtension ?? "png",
    mimeType: null,
  };
}

function normalizeAppURL(urlString) {
  if (!urlString || typeof urlString !== "string") {
    return {
      kind: "embedded-data",
      url: null,
    };
  }

  if (urlString.startsWith("ipfs://")) {
    return {
      kind: "ipfs-gateway",
      url: `https://ipfs.decentralized-content.com/ipfs/${urlString.slice("ipfs://".length).replace(/^ipfs\//u, "")}`,
    };
  }

  if (urlString.startsWith("ar://")) {
    return {
      kind: "arweave-gateway",
      url: `https://arweave.net/${urlString.slice("ar://".length)}`,
    };
  }

  if (urlString.startsWith("data:")) {
    const data = parseDataURL(urlString);
    return {
      kind: "data-url",
      url: null,
      mimeType: data.mimeType,
      embeddedBytes: data.bytes,
    };
  }

  if (!urlString.startsWith("http://") && !urlString.startsWith("https://")) {
    return {
      kind: "embedded-data",
      url: null,
    };
  }

  return {
    kind: "explicit-url",
    url: urlString,
  };
}

function parseDataURL(urlString) {
  const match = /^data:([^,]*),(.*)$/su.exec(urlString);
  if (!match) {
    return {
      mimeType: "application/octet-stream",
      bytes: Buffer.alloc(0),
    };
  }

  const metadata = match[1] || "text/plain;charset=US-ASCII";
  const data = match[2] ?? "";
  const isBase64 = /;base64(?:;|$)/iu.test(metadata);
  const mimeType = metadata.split(";")[0] || "application/octet-stream";
  return {
    mimeType,
    bytes: isBase64 ? Buffer.from(data, "base64") : Buffer.from(decodeURIComponent(data)),
  };
}

function assignFileNames(tokens) {
  const used = new Set();
  return tokens.map((token) => {
    const base = safePathComponent(token.id, 160) || shortHash(token.id);
    const extension = normalizeExtension(token.extension) ?? "bin";
    let fileName = `${base}.${extension}`;
    if (used.has(fileName)) {
      fileName = `${base}__${shortHash(token.id)}.${extension}`;
    }
    while (used.has(fileName)) {
      fileName = `${base}__${shortHash(`${token.id}:${used.size}`)}.${extension}`;
    }
    used.add(fileName);
    return {
      ...token,
      fileName,
    };
  });
}

async function runDryRun(loaded, options, startedAt, freeDiskBytes) {
  const collectionResults = [];
  const skippedCollections = [];
  let totalEstimatedBytes = 0;
  let knownEstimatedBytes = 0;
  let headFailures = 0;
  const activeCollections = loaded.collections.filter((collection) => !collection.skipped);

  for (const collection of loaded.collections) {
    if (collection.skipped) {
      skippedCollections.push(skippedCollectionResult(collection));
      continue;
    }

    const tokens = collection.tokens;
    const tokenEntries = [];
    if (options.estimateHead) {
      await runPool(tokens, options.concurrency, async (token) => {
        const estimate = await estimateTarget(token, options);
        if (estimate.contentLength != null) {
          totalEstimatedBytes += estimate.contentLength;
          knownEstimatedBytes += 1;
        }
        if (estimate.status && estimate.status >= 400) {
          headFailures += 1;
        }
        tokenEntries.push({
          tokenId: token.id,
          fileName: token.fileName,
          downloadUrl: token.downloadUrl,
          sourceKind: token.sourceKind,
          extension: token.extension,
          status: estimate.status,
          contentType: estimate.contentType,
          contentLength: estimate.contentLength,
          error: estimate.error,
        });
      }, () => {});
    }

    collectionResults.push({
      id: collection.id,
      name: collection.name,
      internal_slug: collection.internalSlug,
      chain: collection.chain,
      address: collection.address,
      tokenCount: collection.tokenCount,
      outputDirectory: collection.outputDirectory,
      estimatedKnownTokenCount: tokenEntries.filter((entry) => entry.contentLength != null).length,
      estimatedBytes: tokenEntries.reduce((sum, entry) => sum + (entry.contentLength ?? 0), 0),
      headFailures: tokenEntries.filter((entry) => entry.error).length,
      tokens: tokenEntries,
    });
  }

  const elapsedMs = Date.now() - startedAt.getTime();
  return {
    generatedAt: new Date().toISOString(),
    mode: "dry-run",
    bundlePath: loaded.bundlePath,
    outputRoot: loaded.outputRoot,
    options: publicOptions(options),
    summary: {
      collectionsMatched: loaded.collections.length,
      collectionsToDownload: activeCollections.length,
      skippedCollections: skippedCollections.length,
      tokenRowsToDownload: activeCollections.reduce((sum, collection) => sum + collection.tokens.length, 0),
      skippedTokenRows: skippedCollections.reduce((sum, collection) => sum + collection.tokenCount, 0),
      estimatedBytes: totalEstimatedBytes,
      estimatedBytesFormatted: formatBytes(totalEstimatedBytes),
      estimatedKnownTokenCount: knownEstimatedBytes,
      freeDiskBytes,
      freeDiskFormatted: formatBytes(freeDiskBytes),
      headFailures,
      elapsedMs,
    },
    missingTokenFiles: loaded.missingTokenFiles,
    skippedCollections,
    collections: collectionResults,
  };
}

async function runDownload(loaded, options, startedAt, freeDiskBytes) {
  await fsp.mkdir(loaded.outputRoot, { recursive: true });
  const existingRootManifest = hasRunFilters(options)
    ? await readOptionalJson(path.join(loaded.outputRoot, "manifest.json"))
    : null;
  if (existingRootManifest) validateRootManifestForMerge(existingRootManifest);

  const skippedCollections = [];
  const collectionResults = [];
  const failures = [];
  let downloadedFiles = 0;
  let reusedFiles = 0;
  let sourceRefreshFailures = 0;
  let failedFiles = 0;
  let bytesWritten = 0;
  let totalAttempts = 0;

  const activeCollections = loaded.collections.filter((collection) => !collection.skipped);
  for (const collection of loaded.collections) {
    if (collection.skipped) {
      const skipped = skippedCollectionResult(collection);
      skippedCollections.push(skipped);
      collectionResults.push(skipped);
    }
  }

  for (let index = 0; index < activeCollections.length; index += 1) {
    const collection = activeCollections[index];
    console.error(`[${index + 1}/${activeCollections.length}] ${collection.name} (${collection.tokenCount} token file(s))`);
    await fsp.mkdir(collection.outputDirectory, { recursive: true });
    const result = await downloadCollection(collection, options);
    collectionResults.push(result);
    downloadedFiles += result.downloadedFiles;
    reusedFiles += result.reusedFiles;
    sourceRefreshFailures += result.sourceRefreshFailures;
    failedFiles += result.failedFiles;
    bytesWritten += result.bytesWritten;
    totalAttempts += result.totalAttempts;
    failures.push(...result.tokens.filter((token) => token.status === "failed").map((token) => ({
      collectionId: collection.id,
      collectionName: collection.name,
      internal_slug: collection.internalSlug,
      tokenId: token.tokenId,
      downloadUrl: token.downloadUrl,
      statusCode: token.statusCode,
      error: token.error,
    })));

    await writeRootManifest(loaded, options, {
      mode: "apply",
      startedAt,
      collectionResults,
      skippedCollections,
      failures,
      downloadedFiles,
      reusedFiles,
      sourceRefreshFailures,
      failedFiles,
      bytesWritten,
      totalAttempts,
      freeDiskBytes,
      partial: true,
    }, existingRootManifest);
  }

  const elapsedMs = Date.now() - startedAt.getTime();
  const report = {
    generatedAt: new Date().toISOString(),
    mode: "apply",
    bundlePath: loaded.bundlePath,
    outputRoot: loaded.outputRoot,
    options: publicOptions(options),
    summary: {
      collectionsMatched: loaded.collections.length,
      collectionsDownloaded: activeCollections.length,
      skippedCollections: skippedCollections.length,
      tokenRowsToDownload: activeCollections.reduce((sum, collection) => sum + collection.tokens.length, 0),
      skippedTokenRows: skippedCollections.reduce((sum, collection) => sum + collection.tokenCount, 0),
      downloadedFiles,
      reusedFiles,
      sourceRefreshFailures,
      failedFiles,
      totalAttempts,
      bytesWritten,
      bytesWrittenFormatted: formatBytes(bytesWritten),
      freeDiskBytes,
      freeDiskFormatted: formatBytes(freeDiskBytes),
      unreachableCollections: collectionResults.filter((collection) => !collection.skipped && collection.successfulFiles === 0 && collection.failedFiles > 0).length,
      partiallyFailedCollections: collectionResults.filter((collection) => !collection.skipped && collection.failedFiles > 0 && collection.successfulFiles > 0).length,
      elapsedMs,
    },
    missingTokenFiles: loaded.missingTokenFiles,
    skippedCollections,
    failures,
    collections: collectionResults,
  };

  await writeRootManifest(loaded, options, {
    mode: "apply",
    startedAt,
    collectionResults,
    skippedCollections,
    failures,
    downloadedFiles,
    reusedFiles,
    sourceRefreshFailures,
    failedFiles,
    bytesWritten,
    totalAttempts,
    freeDiskBytes,
    partial: false,
  }, existingRootManifest);

  return report;
}

async function downloadCollection(collection, options) {
  const manifestPath = path.join(collection.outputDirectory, "manifest.json");
  const existingManifest = await readOptionalJson(manifestPath);
  if (existingManifest) {
    assertCollectionManifestIdentity(existingManifest, collection, manifestPath);
  }
  const existingByTokenId = new Map((existingManifest?.tokens ?? []).map((entry) => [String(entry.tokenId), entry]));
  const startedAt = new Date();
  const entries = collection.tokens.map((token) => existingByTokenId.get(token.id) ?? null);
  let downloadedFiles = 0;
  let reusedFiles = 0;
  let sourceRefreshFailures = 0;
  let bytesWritten = 0;
  let totalAttempts = 0;
  let lastManifestWrite = Date.now();
  let manifestWritePromise = Promise.resolve();

  await removeStalePartials(collection.outputDirectory, options);

  await runPool(collection.tokens, options.concurrency, async (token, tokenIndex) => {
    const existingEntry = existingByTokenId.get(token.id);
    const existing = !options.overwrite
      ? await verifiedExistingEntry(collection.outputDirectory, existingEntry)
      : null;
    const reusePolicy = existing ? existingEntryReusePolicy(existing, token) : null;

    let entry;
    if (existing && reusePolicy !== "refresh") {
      entry = {
        ...existing,
        tokenId: token.id,
        reusedExisting: true,
        ...(reusePolicy === "preserve-quality-repair" ? {
          sourceOverridePreserved: true,
          preferredBundledSource: selectedTokenSource(token),
        } : {}),
        status: "success",
        attempts: 0,
        checkedAt: new Date().toISOString(),
      };
      reusedFiles += 1;
    } else if (existing) {
      const replacement = await downloadToken(collection.outputDirectory, token, options);
      totalAttempts += replacement.attempts ?? 0;
      if (replacement.status === "success") {
        if (existing.fileName && existing.fileName !== replacement.fileName) {
          await fsp.rm(path.join(collection.outputDirectory, existing.fileName), { force: true });
        }
        entry = {
          ...replacement,
          sourceUpgrade: {
            upgradedAt: new Date().toISOString(),
            previousFileName: existing.fileName,
            previousDownloadUrl: existing.downloadUrl ?? null,
            previousOriginalBundledURL: existing.originalBundledURL ?? null,
            previousBytesWritten: existing.bytesWritten ?? null,
            previousSha256: existing.sha256 ?? null,
            previousQualityRepair: existing.qualityRepair ?? null,
          },
        };
        downloadedFiles += 1;
        bytesWritten += replacement.bytesWritten ?? 0;
      } else {
        const checkedAt = new Date().toISOString();
        entry = {
          ...existing,
          tokenId: token.id,
          reusedExisting: true,
          status: "success",
          attempts: 0,
          checkedAt,
          sourceRefresh: {
            checkedAt,
            status: "failed",
            preferredDownloadUrl: token.downloadUrl,
            preferredOriginalBundledURL: token.originalBundledURL,
            attempts: replacement.attempts ?? 0,
            statusCode: replacement.statusCode ?? null,
            error: replacement.error ?? "source refresh failed",
          },
        };
        reusedFiles += 1;
        sourceRefreshFailures += 1;
      }
    } else if (!options.overwrite && !options.retryFailures && existingEntry?.status === "failed") {
      entry = {
        ...existingEntry,
        tokenId: token.id,
        reusedExistingFailure: true,
        attempts: 0,
        checkedAt: new Date().toISOString(),
      };
    } else {
      entry = await downloadToken(collection.outputDirectory, token, options);
      totalAttempts += entry.attempts ?? 0;
      if (entry.status === "success") {
        downloadedFiles += 1;
        bytesWritten += entry.bytesWritten ?? 0;
      }
    }

    entries[tokenIndex] = entry;
    if (Date.now() - lastManifestWrite > 10000) {
      lastManifestWrite = Date.now();
      manifestWritePromise = manifestWritePromise.then(() => writeCollectionManifest(
        manifestPath,
        collection,
        entries.filter(Boolean),
        {
          startedAt,
          partial: true,
        }
      ));
      await manifestWritePromise;
    }
  }, (completed, total) => {
    if (completed === total || completed % 100 === 0) {
      console.error(`  ${collection.name}: ${completed}/${total}`);
    }
  });

  await manifestWritePromise;
  await writeCollectionManifest(manifestPath, collection, entries, {
    startedAt,
    partial: false,
  });

  return {
    id: collection.id,
    name: collection.name,
    internal_slug: collection.internalSlug,
    chain: collection.chain,
    address: collection.address,
    outputDirectory: collection.outputDirectory,
    manifestPath,
    tokenCount: collection.tokenCount,
    successfulFiles: entries.filter((entry) => entry.status === "success").length,
    downloadedFiles,
    reusedFiles,
    sourceRefreshFailures,
    failedFiles: entries.filter((entry) => entry.status === "failed").length,
    bytesWritten,
    totalAttempts,
    tokens: entries,
  };
}

async function assertOutputDirectoryOwnership(loaded) {
  const outputRoot = loaded.outputRoot;
  let entries;
  try {
    entries = await fsp.readdir(outputRoot, { withFileTypes: true });
  } catch (error) {
    if (error.code === "ENOENT") return;
    throw error;
  }

  const legacyDirectories = entries
    .filter((entry) => entry.isDirectory() && entry.name.includes("__"))
    .map((entry) => entry.name)
    .sort();
  if (legacyDirectories.length > 0) {
    const preview = legacyDirectories.slice(0, 5).join(", ");
    const remainder = legacyDirectories.length > 5 ? ` and ${legacyDirectories.length - 5} more` : "";
    throw new Error(
      `Legacy collection directories remain in ${outputRoot}: ${preview}${remainder}. `
      + "Run node tools/migrate_downloaded_collection_slugs.js --apply before downloading.",
    );
  }

  const itemByIdentity = new Map();
  for (const item of loaded.items) {
    const key = collectionIdentityKey(collectionIdFor(item), item.chain);
    if (itemByIdentity.has(key)) {
      throw new Error(`items.json contains duplicate collection identity ${item.chain}:${collectionIdFor(item)}`);
    }
    itemByIdentity.set(key, item);
  }
  for (const entry of entries) {
    if (entry.isSymbolicLink()) {
      throw new Error(`Downloaded collection path must not be a symbolic link: ${path.join(outputRoot, entry.name)}`);
    }
    if (!entry.isDirectory()) continue;

    const directory = path.join(outputRoot, entry.name);
    const manifestPath = path.join(directory, "manifest.json");
    const manifest = await readOptionalJson(manifestPath);
    if (!manifest) {
      throw new Error(`Existing collection directory has no manifest.json and will not be overwritten: ${directory}`);
    }
    const manifestCollection = manifest.collection;
    const key = collectionIdentityKey(manifestCollection?.id, manifestCollection?.chain);
    const item = itemByIdentity.get(key);
    if (!item) {
      throw new Error(`Existing collection directory belongs to a collection not present in items.json: ${directory}`);
    }

    const expected = {
      id: collectionIdFor(item),
      name: item.name ?? null,
      internalSlug: item.internal_slug,
      chain: item.chain ?? null,
      address: item.address ?? null,
    };
    assertCollectionManifestIdentity(manifest, expected, manifestPath);
    if (entry.name !== item.internal_slug) {
      throw new Error(
        `Existing collection directory ${directory} should be named ${item.internal_slug}. `
        + "Run node tools/migrate_downloaded_collection_slugs.js --apply before downloading.",
      );
    }
  }
}

function assertCollectionManifestIdentity(manifest, collection, manifestPath) {
  const actual = manifest.collection;
  if (!actual || typeof actual !== "object") {
    throw new Error(`Existing manifest has no collection identity: ${manifestPath}`);
  }

  const mismatches = [];
  if (collectionIdentityKey(actual.id, actual.chain) !== collectionIdentityKey(collection.id, collection.chain)) {
    mismatches.push(`id/chain ${JSON.stringify(actual.id)}/${JSON.stringify(actual.chain)}`);
  }
  if (collectionIdentityKey(actual.address, actual.chain) !== collectionIdentityKey(collection.address, collection.chain)) {
    mismatches.push(`address ${JSON.stringify(actual.address)}`);
  }
  if (actual.internal_slug != null && actual.internal_slug !== collection.internalSlug) {
    mismatches.push(`internal_slug ${JSON.stringify(actual.internal_slug)}`);
  }
  if (mismatches.length === 0) return;

  throw new Error(
    `Existing manifest does not match ${collection.name} (${collection.id}) at ${manifestPath}: ${mismatches.join(", ")}`,
  );
}

async function removeStalePartials(collectionDirectory, options) {
  if (options.keepPartials) {
    return;
  }

  let fileNames;
  try {
    fileNames = await fsp.readdir(collectionDirectory);
  } catch (error) {
    if (error.code === "ENOENT") {
      return;
    }
    throw error;
  }

  await Promise.all(
    fileNames
      .filter((fileName) => fileName.endsWith(".part"))
      .map((fileName) => fsp.rm(path.join(collectionDirectory, fileName), { force: true })),
  );
}

async function verifiedExistingEntry(collectionDirectory, entry) {
  if (!entry || entry.status !== "success" || !entry.fileName) {
    return null;
  }

  const filePath = path.join(collectionDirectory, entry.fileName);
  let stat;
  try {
    stat = await fsp.stat(filePath);
  } catch {
    return null;
  }

  if (typeof entry.bytesWritten === "number" && stat.size !== entry.bytesWritten) {
    return null;
  }

  if (entry.sha256) {
    const digest = await sha256File(filePath);
    if (digest !== entry.sha256) {
      return null;
    }
  }

  return entry;
}

function existingEntryReusePolicy(entry, token) {
  const currentSource = comparableMediaSource(selectedTokenSource(token));
  const existingSource = comparableMediaSource(selectedEntrySource(entry));
  if (currentSource === existingSource) return "reuse";
  if (shouldPreserveQualityRepair(entry, currentSource)) return "preserve-quality-repair";
  return "refresh";
}

function shouldPreserveQualityRepair(entry, currentSource) {
  const repair = entry.qualityRepair;
  if (!repair) return false;
  const previous = repair.previous;
  if (!previous || previous.status == null) return true;

  const previousSource = comparableMediaSource(previous.downloadUrl ?? previous.originalBundledURL ?? null);
  if (previousSource != null && currentSource != null && previousSource !== currentSource) {
    return false;
  }
  return previous.status !== "failed";
}

function selectedTokenSource(token) {
  return token.downloadUrl ?? token.originalBundledURL ?? null;
}

function selectedEntrySource(entry) {
  return entry.downloadUrl ?? entry.originalBundledURL ?? null;
}

function comparableMediaSource(value) {
  if (value == null) return null;
  const source = String(value);
  if (source.startsWith("data:")) return `data:${shortHash(source)}`;
  const ipfs = ipfsGatewayURLParts(source);
  if (ipfs) return `ipfs://${ipfs.cid}${ipfs.pathSuffix}${ipfs.search}`;
  const arweave = arweaveGatewayURLParts(source);
  if (arweave) return `ar://${arweave.transactionId}${arweave.pathSuffix}${arweave.search}`;
  try {
    const url = new URL(source);
    url.hash = "";
    return url.toString();
  } catch {
    return source;
  }
}

async function downloadToken(collectionDirectory, token, options) {
  const startedAt = new Date();
  const filePath = path.join(collectionDirectory, token.fileName);
  const partPath = `${filePath}.part`;
  const baseEntry = {
    tokenId: token.id,
    tokenName: token.name,
    fileName: token.fileName,
    originalBundledSource: token.originalBundledSource,
    originalBundledURL: token.originalBundledURL,
    downloadUrl: token.downloadUrl,
    sourceKind: token.sourceKind,
    extension: token.extension,
    startedAt: startedAt.toISOString(),
  };

  if (token.embeddedBytes) {
    const hash = crypto.createHash("sha256").update(token.embeddedBytes).digest("hex");
    await fsp.writeFile(partPath, token.embeddedBytes);
    await fsp.rename(partPath, filePath);
    return {
      ...baseEntry,
      status: "success",
      finalUrl: null,
      contentType: token.mimeType,
      contentLength: token.embeddedBytes.length,
      bytesWritten: token.embeddedBytes.length,
      sha256: hash,
      attempts: 1,
      statusCode: null,
      finishedAt: new Date().toISOString(),
    };
  }

  if (!token.downloadUrl) {
    return {
      ...baseEntry,
      status: "failed",
      finalUrl: null,
      contentType: token.mimeType,
      contentLength: null,
      bytesWritten: 0,
      sha256: null,
      attempts: 0,
      statusCode: null,
      error: "no downloadable URL",
      finishedAt: new Date().toISOString(),
    };
  }

  let lastResult = null;
  let attempts = 0;
  const candidateUrls = downloadUrlCandidates(token.downloadUrl);
  for (let attemptIndex = 0; attemptIndex <= options.retries; attemptIndex += 1) {
    for (const downloadUrl of candidateUrls) {
      attempts += 1;
      const result = await fetchAndWrite(token, partPath, filePath, options, downloadUrl);
      result.attempts = attempts;
      result.attemptUrl = downloadUrl;
      if (result.status === "success") {
        return {
          ...baseEntry,
          ...result,
          finishedAt: new Date().toISOString(),
        };
      }

      lastResult = result;
      await removePartial(partPath, options);
    }

    if (attemptIndex >= options.retries || !shouldRetry(lastResult)) {
      break;
    }

    await sleep(retryDelayMs(lastResult, options.retryDelayMs, attemptIndex));
  }

  await removePartial(partPath, options);
  return {
    ...baseEntry,
    status: "failed",
    finalUrl: lastResult?.finalUrl ?? null,
    contentType: lastResult?.contentType ?? null,
    contentLength: lastResult?.contentLength ?? null,
    bytesWritten: lastResult?.bytesWritten ?? 0,
    sha256: null,
    attempts: lastResult?.attempts ?? 0,
    statusCode: lastResult?.statusCode ?? null,
    error: lastResult?.error ?? "download failed",
    finishedAt: new Date().toISOString(),
  };
}

function downloadUrlCandidates(urlString) {
  const urls = [];
  const ipfs = ipfsGatewayURLParts(urlString);
  if (ipfs) {
    urls.push(`https://ipfs.io/ipfs/${ipfs.cid}${ipfs.pathSuffix}${ipfs.search}`);
    urls.push(urlString);
    urls.push(`https://ipfs.decentralized-content.com/ipfs/${ipfs.cid}${ipfs.pathSuffix}${ipfs.search}`);
  } else {
    urls.push(urlString);
  }
  const arweave = arweaveGatewayURLParts(urlString);
  if (arweave) {
    urls.push(`https://arweave.net/${arweave.transactionId}${arweave.pathSuffix}${arweave.search}`);
    urls.push(`https://gateway.irys.xyz/${arweave.transactionId}${arweave.pathSuffix}${arweave.search}`);
  }
  return [...new Set(urls)];
}

function ipfsGatewayURLParts(urlString) {
  try {
    const url = new URL(urlString);
    const match = /^\/ipfs\/([^/]+)(\/.*)?$/u.exec(url.pathname);
    if (!match) {
      return null;
    }
    return {
      cid: match[1],
      pathSuffix: match[2] ?? "",
      search: url.search,
    };
  } catch {
    return null;
  }
}

function arweaveGatewayURLParts(urlString) {
  try {
    const url = new URL(urlString);
    if (!["arweave.net", "gateway.irys.xyz", "permagate.io"].includes(url.hostname)) {
      return null;
    }
    const match = /^\/([A-Za-z0-9_-]{43})(\/.*)?$/u.exec(url.pathname);
    if (!match) {
      return null;
    }
    return {
      transactionId: match[1],
      pathSuffix: match[2] ?? "",
      search: url.search,
    };
  } catch {
    return null;
  }
}

async function fetchAndWrite(token, partPath, filePath, options, downloadUrl = token.downloadUrl) {
  return curlAndWrite(token, partPath, filePath, options, downloadUrl);
}

async function curlAndWrite(token, partPath, filePath, options, downloadUrl = token.downloadUrl) {
  const startedAt = Date.now();
  const timeoutSeconds = Math.max(1, Math.ceil(options.timeoutMs / 1000));
  const connectTimeoutSeconds = Math.min(15, timeoutSeconds);
  const metaMarker = "NFT_PLAYER_CURL_META\t";
  const args = [
    "--location",
    "--fail",
    "--http1.1",
    "--silent",
    "--show-error",
    "--max-time",
    String(timeoutSeconds),
    "--connect-timeout",
    String(connectTimeoutSeconds),
    "--user-agent",
    "nft-player-originals-downloader/1.0",
    "--header",
    "Connection: close",
    "--output",
    partPath,
    "--write-out",
    `\\n${metaMarker}%{http_code}\\t%{url_effective}\\t%{content_type}\\t%{size_download}`,
    downloadUrl,
  ];

  const result = await runCurl(args, options.timeoutMs + 5000);
  const meta = parseCurlMeta(result.stdout, metaMarker);
  const statusCode = Number.isInteger(meta.statusCode) && meta.statusCode > 0 ? meta.statusCode : null;

  if (result.exitCode !== 0) {
    return {
      status: "failed",
      statusCode,
      finalUrl: meta.finalUrl ?? null,
      contentType: meta.contentType ?? null,
      contentLength: null,
      bytesWritten: meta.bytesWritten ?? 0,
      error: curlErrorMessage(result, options.timeoutMs),
      elapsedMs: Date.now() - startedAt,
    };
  }

  if (statusCode != null && (statusCode < 200 || statusCode >= 300)) {
    return {
      status: "failed",
      statusCode,
      finalUrl: meta.finalUrl ?? null,
      contentType: meta.contentType ?? null,
      contentLength: null,
      bytesWritten: meta.bytesWritten ?? 0,
      error: `HTTP ${statusCode}`,
      elapsedMs: Date.now() - startedAt,
    }
  }

  const bytesWritten = (await fsp.stat(partPath)).size;
  const sha256 = await sha256File(partPath);
  await fsp.rename(partPath, filePath);
  return {
    status: "success",
    statusCode: statusCode ?? 200,
    finalUrl: meta.finalUrl ?? downloadUrl,
    contentType: meta.contentType ?? null,
    contentLength: null,
    bytesWritten,
    sha256,
    elapsedMs: Date.now() - startedAt,
  };
}

function runCurl(args, timeoutMs) {
  return new Promise((resolve) => {
    const child = spawn("curl", args, {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    const timeout = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
      setTimeout(() => child.kill("SIGKILL"), 2000).unref();
    }, timeoutMs);

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", (error) => {
      clearTimeout(timeout);
      resolve({
        exitCode: null,
        signal: null,
        stdout,
        stderr: error.message,
        timedOut,
      });
    });
    child.on("close", (exitCode, signal) => {
      clearTimeout(timeout);
      resolve({
        exitCode,
        signal,
        stdout,
        stderr,
        timedOut,
      });
    });
  });
}

function parseCurlMeta(stdout, marker) {
  const line = stdout.split(/\r?\n/u).findLast((entry) => entry.startsWith(marker));
  if (!line) {
    return {};
  }
  const [statusCode, finalUrl, contentType, bytesWritten] = line.slice(marker.length).split("\t");
  return {
    statusCode: Number.isInteger(Number(statusCode)) ? Number(statusCode) : null,
    finalUrl: finalUrl || null,
    contentType: contentType || null,
    bytesWritten: Number.isFinite(Number(bytesWritten)) ? Number(bytesWritten) : null,
  };
}

function curlErrorMessage(result, timeoutMs) {
  if (result.timedOut || result.exitCode === 28) {
    return `timeout after ${timeoutMs}ms`;
  }
  const stderr = result.stderr.trim();
  if (stderr) {
    return stderr.split(/\r?\n/u).at(-1);
  }
  if (result.signal) {
    return `curl terminated by ${result.signal}`;
  }
  return `curl exited with code ${result.exitCode}`;
}

async function streamResponseToFile(response, partPath, signal) {
  if (!response.body) {
    const buffer = Buffer.from(await response.arrayBuffer());
    const sha256 = crypto.createHash("sha256").update(buffer).digest("hex");
    await fsp.writeFile(partPath, buffer);
    return {
      bytesWritten: buffer.byteLength,
      sha256,
    };
  }

  const hash = crypto.createHash("sha256");
  let bytesWritten = 0;
  const hashStream = new Transform({
    transform(chunk, _encoding, callback) {
      bytesWritten += chunk.length;
      hash.update(chunk);
      callback(null, chunk);
    },
  });

  await pipeline(
    Readable.fromWeb(response.body),
    hashStream,
    fs.createWriteStream(partPath),
    { signal },
  );

  return {
    bytesWritten,
    sha256: hash.digest("hex"),
  };
}

async function estimateTarget(token, options) {
  if (token.embeddedBytes) {
    return {
      status: null,
      contentType: token.mimeType,
      contentLength: token.embeddedBytes.length,
      error: null,
    };
  }
  if (!token.downloadUrl) {
    return {
      status: null,
      contentType: token.mimeType,
      contentLength: null,
      error: "no downloadable URL",
    };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), options.timeoutMs);
  try {
    const response = await fetch(token.downloadUrl, {
      method: "HEAD",
      redirect: "follow",
      signal: controller.signal,
      headers: {
        "User-Agent": "nft-player-originals-downloader/1.0",
        Connection: "close",
        accept: "*/*",
      },
    });
    await response.body?.cancel?.();
    return {
      status: response.status,
      contentType: response.headers.get("content-type"),
      contentLength: numericHeader(response.headers.get("content-length")),
      error: response.ok ? null : `HTTP ${response.status}`,
    };
  } catch (error) {
    return {
      status: null,
      contentType: null,
      contentLength: null,
      error: error.name === "AbortError" ? `timeout after ${options.timeoutMs}ms` : error.message,
    };
  } finally {
    clearTimeout(timeout);
  }
}

function shouldRetry(result) {
  if (result.statusCode == null) {
    return true;
  }
  return TRANSIENT_HTTP_STATUSES.has(result.statusCode);
}

function retryDelayMs(result, baseDelayMs, attemptIndex) {
  if (result.retryAfterMs != null) {
    return Math.min(result.retryAfterMs, 30000);
  }
  return Math.min(baseDelayMs * 2 ** attemptIndex, 30000);
}

function parseRetryAfter(value) {
  if (!value) {
    return null;
  }
  const seconds = Number(value);
  if (Number.isFinite(seconds)) {
    return Math.max(0, seconds * 1000);
  }
  const dateMs = Date.parse(value);
  if (Number.isFinite(dateMs)) {
    return Math.max(0, dateMs - Date.now());
  }
  return null;
}

async function removePartial(partPath, options) {
  if (options.keepPartials) {
    return;
  }
  await fsp.rm(partPath, { force: true }).catch(() => {});
}

async function writeCollectionManifest(manifestPath, collection, entries, state) {
  const tokens = entries.filter(Boolean);
  const manifest = {
    generatedAt: new Date().toISOString(),
    partial: state.partial,
    collection: {
      id: collection.id,
      name: collection.name,
      internal_slug: collection.internalSlug,
      chain: collection.chain,
      chainId: collection.chainId,
      address: collection.address,
      projectId: collection.projectId,
      tokenCount: collection.tokenCount,
      skipped: false,
      skipReason: null,
    },
    outputDirectory: collection.outputDirectory,
    totals: {
      tokensRecorded: tokens.length,
      successfulFiles: tokens.filter((entry) => entry.status === "success").length,
      failedFiles: tokens.filter((entry) => entry.status === "failed").length,
      reusedFiles: tokens.filter((entry) => entry.reusedExisting).length,
      sourceRefreshFailures: tokens.filter((entry) => entry.sourceRefresh?.status === "failed").length,
      bytesWritten: tokens.reduce((sum, entry) => sum + (entry.bytesWritten ?? 0), 0),
    },
    startedAt: state.startedAt.toISOString(),
    updatedAt: new Date().toISOString(),
    tokens,
  };
  await writeJsonAtomic(manifestPath, manifest);
}

async function writeRootManifest(loaded, options, state, existingRootManifest = null) {
  const manifestPath = path.join(loaded.outputRoot, "manifest.json");
  const elapsedMs = Date.now() - state.startedAt.getTime();
  const currentManifest = {
    generatedAt: new Date().toISOString(),
    partial: state.partial,
    mode: state.mode,
    bundlePath: loaded.bundlePath,
    outputRoot: loaded.outputRoot,
    reportPath: path.resolve(options.reportPath),
    jsonReportPath: path.resolve(options.jsonReportPath),
    options: publicOptions(options),
    totals: {
      collectionsMatched: loaded.collections.length,
      collectionsDownloaded: state.collectionResults.filter((collection) => !collection.skipped).length,
      skippedCollections: state.skippedCollections.length,
      downloadedFiles: state.downloadedFiles,
      reusedFiles: state.reusedFiles,
      sourceRefreshFailures: state.sourceRefreshFailures,
      failedFiles: state.failedFiles,
      totalAttempts: state.totalAttempts,
      bytesWritten: state.bytesWritten,
      freeDiskBytes: state.freeDiskBytes,
      elapsedMs,
    },
    skippedCollections: state.skippedCollections,
    failures: state.failures,
    collections: state.collectionResults.map((collection) => compactCollectionResult(collection)),
  };
  const manifest = existingRootManifest
    ? mergeRootManifest(existingRootManifest, currentManifest, loaded)
    : currentManifest;
  await writeJsonAtomic(manifestPath, manifest);
}

function mergeRootManifest(existing, current, loaded) {
  validateRootManifestForMerge(existing);
  assertUniqueCollectionRecords(current.collections, "current filtered run");
  const replaceCollections = loaded.collections.filter((collection) => (
    !collection.skippedByFilter || collection.skippedByCdnLil
  ));
  const replaceKeys = new Set(replaceCollections.map(collectionRecordKey));
  const collections = mergeCollectionRecords(existing.collections, current.collections, replaceKeys);
  const currentKeys = new Set(current.collections.map(collectionRecordKey));
  const failureReplaceCollections = replaceCollections.filter((collection) => currentKeys.has(collectionRecordKey(collection)));
  const failures = [
    ...existing.failures.filter((failure) => !failureReplaceCollections.some((collection) => failureBelongsToCollection(failure, collection))),
    ...current.failures,
  ];
  const skippedCollections = collections.filter((collection) => collection.skipped);
  return {
    ...current,
    mergedWithExistingManifest: true,
    reportPath: existing.reportPath ?? current.reportPath,
    jsonReportPath: existing.jsonReportPath ?? current.jsonReportPath,
    options: existing.options ?? current.options,
    lastFilteredRun: {
      generatedAt: current.generatedAt,
      partial: current.partial,
      options: current.options,
      reportPath: current.reportPath,
      jsonReportPath: current.jsonReportPath,
    },
    totals: summarizeMergedRootTotals(current.totals, collections),
    skippedCollections,
    failures,
    collections,
  };
}

function validateRootManifestForMerge(manifest) {
  if (!Array.isArray(manifest.collections) || !Array.isArray(manifest.failures)) {
    throw new Error("Existing root manifest cannot be safely merged because collections or failures is not an array");
  }
  assertUniqueCollectionRecords(manifest.collections, "existing root manifest");
}

function assertUniqueCollectionRecords(records, label) {
  const seen = new Set();
  for (const record of records) {
    const key = collectionRecordKey(record);
    if (seen.has(key)) throw new Error(`${label} contains duplicate collection ${record.chain}:${record.id}`);
    seen.add(key);
  }
}

function mergeCollectionRecords(existing, current, replaceKeys) {
  const currentByKey = new Map(current.map((record) => [collectionRecordKey(record), record]));
  const merged = existing.map((record) => {
    const key = collectionRecordKey(record);
    return replaceKeys.has(key) && currentByKey.has(key) ? currentByKey.get(key) : record;
  });
  const existingKeys = new Set(existing.map(collectionRecordKey));
  for (const record of current) {
    if (!existingKeys.has(collectionRecordKey(record))) merged.push(record);
  }
  return merged;
}

function collectionRecordKey(record) {
  return collectionIdentityKey(record.id, record.chain);
}

function failureBelongsToCollection(failure, collection) {
  return collectionIdentityKey(failure.collectionId, collection.chain) === collectionRecordKey(collection);
}

function summarizeMergedRootTotals(currentTotals, collections) {
  const sum = (field) => collections.reduce((total, collection) => total + Number(collection[field] ?? 0), 0);
  return {
    ...currentTotals,
    collectionsMatched: collections.length,
    collectionsDownloaded: collections.filter((collection) => !collection.skipped).length,
    skippedCollections: collections.filter((collection) => collection.skipped).length,
    downloadedFiles: sum("downloadedFiles"),
    reusedFiles: sum("reusedFiles"),
    sourceRefreshFailures: sum("sourceRefreshFailures"),
    failedFiles: sum("failedFiles"),
    totalAttempts: sum("totalAttempts"),
    bytesWritten: sum("bytesWritten"),
  };
}

function skippedCollectionResult(collection) {
  return {
    id: collection.id,
    name: collection.name,
    internal_slug: collection.internalSlug,
    chain: collection.chain,
    address: collection.address,
    outputDirectory: collection.outputDirectory,
    tokenCount: collection.tokenCount,
    skipped: true,
    skipReason: collection.skipReason,
    successfulFiles: 0,
    downloadedFiles: 0,
    reusedFiles: 0,
    sourceRefreshFailures: 0,
    failedFiles: 0,
    bytesWritten: 0,
    totalAttempts: 0,
    tokens: [],
  };
}

function compactCollectionResult(collection) {
  return {
    id: collection.id,
    name: collection.name,
    internal_slug: collection.internal_slug ?? collection.internalSlug,
    chain: collection.chain,
    address: collection.address,
    outputDirectory: collection.outputDirectory,
    manifestPath: collection.manifestPath,
    tokenCount: collection.tokenCount,
    skipped: Boolean(collection.skipped),
    skipReason: collection.skipReason ?? null,
    successfulFiles: collection.successfulFiles ?? 0,
    downloadedFiles: collection.downloadedFiles ?? 0,
    reusedFiles: collection.reusedFiles ?? 0,
    sourceRefreshFailures: collection.sourceRefreshFailures ?? 0,
    failedFiles: collection.failedFiles ?? 0,
    bytesWritten: collection.bytesWritten ?? 0,
    totalAttempts: collection.totalAttempts ?? 0,
  };
}

async function writeReportFiles(report, options) {
  await Promise.all([
    fsp.mkdir(path.dirname(path.resolve(options.reportPath)), { recursive: true }),
    fsp.mkdir(path.dirname(path.resolve(options.jsonReportPath)), { recursive: true }),
  ]);
  await Promise.all([
    fsp.writeFile(options.reportPath, renderMarkdownReport(report)),
    fsp.writeFile(options.jsonReportPath, `${JSON.stringify(report, null, 2)}\n`),
  ]);
  console.error(`Report written to ${path.resolve(options.reportPath)}`);
  console.error(`JSON written to ${path.resolve(options.jsonReportPath)}`);
}

function renderMarkdownReport(report) {
  const lines = [];
  lines.push("# Original Bundle Media Download Report");
  lines.push("");
  lines.push(`Generated: ${report.generatedAt}`);
  lines.push(`Mode: ${report.mode}`);
  lines.push("");
  lines.push("## Summary");
  lines.push("");
  for (const [key, value] of Object.entries(report.summary)) {
    lines.push(`- ${key}: ${value}`);
  }
  lines.push("");
  lines.push("## Skipped Collections");
  lines.push("");
  if (report.skippedCollections.length === 0) {
    lines.push("None.");
  } else {
    lines.push("| Collection | Chain | Tokens | Reason |");
    lines.push("| --- | --- | ---: | --- |");
    for (const collection of report.skippedCollections) {
      lines.push(`| ${escapeCell(collection.name)} | ${escapeCell(collection.chain)} | ${collection.tokenCount} | ${escapeCell(collection.skipReason)} |`);
    }
  }
  lines.push("");
  lines.push("## Failed Tokens");
  lines.push("");
  if (!report.failures || report.failures.length === 0) {
    lines.push("None.");
  } else {
    lines.push("| Collection | Token | Status | Error | URL |");
    lines.push("| --- | --- | --- | --- | --- |");
    for (const failure of report.failures) {
      const status = failure.statusCode == null ? "" : String(failure.statusCode);
      lines.push(`| ${escapeCell(failure.collectionName)} | \`${escapeCell(failure.tokenId)}\` | ${escapeCell(status)} | ${escapeCell(failure.error)} | ${failure.downloadUrl ? `[link](${failure.downloadUrl})` : ""} |`);
    }
  }
  lines.push("");
  lines.push("## Preferred Source Retry Failures");
  lines.push("");
  const sourceRefreshFailures = (report.collections ?? []).flatMap((collection) => (collection.tokens ?? [])
    .filter((token) => token.sourceRefresh?.status === "failed")
    .map((token) => ({ collection, token })));
  if (sourceRefreshFailures.length === 0) {
    lines.push("None.");
  } else {
    lines.push("| Collection | Token | Error | Preferred URL |");
    lines.push("| --- | --- | --- | --- |");
    for (const { collection, token } of sourceRefreshFailures) {
      const refresh = token.sourceRefresh;
      lines.push(`| ${escapeCell(collection.name)} | \`${escapeCell(token.tokenId)}\` | ${escapeCell(refresh.error)} | ${refresh.preferredDownloadUrl ? `[link](${refresh.preferredDownloadUrl})` : ""} |`);
    }
  }
  lines.push("");
  lines.push("## Collections");
  lines.push("");
  lines.push("| Collection | Chain | Tokens | Success | Reused | Source retry failures | Failed | Bytes |");
  lines.push("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |");
  for (const collection of report.collections ?? []) {
    lines.push(`| ${escapeCell(collection.name)} | ${escapeCell(collection.chain)} | ${collection.tokenCount} | ${collection.successfulFiles ?? 0} | ${collection.reusedFiles ?? 0} | ${collection.sourceRefreshFailures ?? 0} | ${collection.failedFiles ?? 0} | ${formatBytes(collection.bytesWritten ?? 0)} |`);
  }
  lines.push("");
  return `${lines.join("\n")}\n`;
}

function publicOptions(options) {
  return {
    bundlePath: options.bundlePath,
    outputRoot: options.outputRoot,
    includeCdnLil: options.includeCdnLil,
    collectionFilters: options.collectionFilters,
    startAtFilter: options.startAtFilter,
    skipCollectionFilters: options.skipCollectionFilters,
    concurrency: options.concurrency,
    retries: options.retries,
    timeoutMs: options.timeoutMs,
    retryDelayMs: options.retryDelayMs,
    overwrite: options.overwrite,
    retryFailures: options.retryFailures,
    keepPartials: options.keepPartials,
    estimateHead: options.estimateHead,
  };
}

async function readJson(filePath) {
  return JSON.parse(await fsp.readFile(filePath, "utf8"));
}

async function readOptionalJson(filePath) {
  try {
    return await readJson(filePath);
  } catch (error) {
    if (error.code === "ENOENT") {
      return null;
    }
    throw error;
  }
}

async function writeJsonAtomic(filePath, value) {
  await fsp.mkdir(path.dirname(filePath), { recursive: true });
  const tempPath = `${filePath}.tmp-${process.pid}`;
  await fsp.writeFile(tempPath, `${JSON.stringify(value, null, 2)}\n`);
  await fsp.rename(tempPath, filePath);
}

async function sha256File(filePath) {
  const hash = crypto.createHash("sha256");
  await new Promise((resolve, reject) => {
    const stream = fs.createReadStream(filePath);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("error", reject);
    stream.on("end", resolve);
  });
  return hash.digest("hex");
}

async function runPool(items, concurrency, worker, onProgress) {
  let nextIndex = 0;
  let completed = 0;
  const workers = Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    for (;;) {
      const currentIndex = nextIndex;
      nextIndex += 1;
      if (currentIndex >= items.length) {
        return;
      }
      await worker(items[currentIndex], currentIndex);
      completed += 1;
      onProgress(completed, items.length);
    }
  });
  await Promise.all(workers);
}

function safePathComponent(value, maxLength = 160) {
  const normalized = String(value ?? "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/gu, "")
    .replace(/[<>:"/\\|?*\u0000-\u001f]/gu, "_")
    .replace(/\s+/gu, " ")
    .replace(/[. ]+$/gu, "")
    .trim();
  const safe = normalized || "untitled";
  if (safe.length <= maxLength) {
    return safe;
  }
  return `${safe.slice(0, maxLength - 11)}__${shortHash(safe)}`;
}

function shortHash(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex").slice(0, 10);
}

function isCdnLilURL(urlString) {
  if (!urlString) {
    return false;
  }
  try {
    return CDN_LIL_HOST_RE.test(new URL(urlString).hostname);
  } catch {
    return false;
  }
}

function extensionFromURL(urlString) {
  if (!urlString) {
    return null;
  }
  try {
    const url = new URL(urlString);
    const extParam = url.searchParams.get("ext");
    if (extParam) {
      return normalizeExtension(extParam);
    }
    const basename = path.posix.basename(url.pathname);
    const match = /\.([a-z0-9]+)$/iu.exec(basename);
    return normalizeExtension(match?.[1]);
  } catch {
    const match = /\.([a-z0-9]+)(?:[?#]|$)/iu.exec(String(urlString));
    return normalizeExtension(match?.[1]);
  }
}

function extensionFromMime(contentType) {
  if (!contentType) {
    return null;
  }
  return normalizeExtension(EXTENSION_BY_MIME.get(String(contentType).split(";")[0].trim().toLowerCase()));
}

function normalizeExtension(value) {
  if (!value) {
    return null;
  }
  const normalized = String(value).trim().replace(/^\./u, "").toLowerCase();
  if (!normalized) {
    return null;
  }
  if (normalized === "jpe") {
    return "jpg";
  }
  if (normalized === "htm" || normalized === "xhtml") {
    return "html";
  }
  return normalized;
}

function numericHeader(value) {
  if (!value) {
    return null;
  }
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

async function availableBytesForPath(targetPath) {
  let current = path.resolve(targetPath);
  for (;;) {
    try {
      const stat = await fsp.stat(current);
      const checkPath = stat.isDirectory() ? current : path.dirname(current);
      const output = await execFile("df", ["-k", checkPath]);
      const lines = output.trim().split(/\n/u);
      const columns = lines[lines.length - 1].trim().split(/\s+/u);
      const availableKBlocks = Number(columns[3]);
      return Number.isFinite(availableKBlocks) ? availableKBlocks * 1024 : null;
    } catch (error) {
      const parent = path.dirname(current);
      if (parent === current) {
        return null;
      }
      current = parent;
    }
  }
}

function execFile(command, args) {
  const { execFile: execFileCallback } = require("node:child_process");
  return new Promise((resolve, reject) => {
    execFileCallback(command, args, { encoding: "utf8" }, (error, stdout, stderr) => {
      if (error) {
        error.stderr = stderr;
        reject(error);
        return;
      }
      resolve(stdout);
    });
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function formatBytes(bytes) {
  if (bytes == null) {
    return "unknown";
  }
  const units = ["B", "KB", "MB", "GB", "TB"];
  let value = bytes;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
}

function escapeCell(value) {
  return String(value ?? "").replace(/\|/gu, "\\|").replace(/\n/gu, " ");
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
