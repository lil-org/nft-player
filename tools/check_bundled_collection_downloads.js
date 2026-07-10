#!/usr/bin/env node

const fs = require("node:fs/promises");
const path = require("node:path");
const { suggestedItemId: collectionIdFor } = require("./suggested_items");
const {
  SKIP_REASON: BUNDLED_GENERATIVE_SKIP_REASON,
  isBundledGenerativeCollectionId,
  loadBundledGenerativeCollectionIds,
} = require("./bundled_generative_collections");

const DEFAULT_BUNDLE_PATH = path.join("Suggested Items", "Suggested.bundle");
const DEFAULT_REPORT_PATH = path.join("tools", "reports", "bundled-collection-download-report.md");
const DEFAULT_JSON_PATH = path.join("tools", "reports", "bundled-collection-download-report.json");

function usage() {
  return `
Usage:
  node tools/check_bundled_collection_downloads.js [options]

Collections represented by Suggested.bundle/Scripts/*.json are always skipped.

Options:
  --bundle <path>       Suggested.bundle path. Default: ${DEFAULT_BUNDLE_PATH}
  --samples <number>    Number of token downloads to try per collection. Default: 3
  --concurrency <n>     Number of simultaneous network checks. Default: 4
  --timeout-ms <ms>     Timeout per item download attempt. Default: 15000
  --bytes <number>      Bytes to read from each response before stopping. Default: 65536
  --retries <number>    Retries for transient failures such as 429/5xx. Default: 1
  --retry-delay-ms <ms> Base retry delay. Default: 1000
  --opensea-api-key <key>
                       OpenSea API key for suggested items without bundled token JSON.
                       Can also be set with OPENSEA_API_KEY.
  --opensea-pages <n|all>
                       OpenSea NFT pages to fetch per missing-token collection. Default: 1
  --full                Read each response fully instead of stopping after --bytes
  --no-head-fallback    Do not use HEAD to confirm URLs after repeated GET 429s
  --output <path>       Markdown report path. Default: ${DEFAULT_REPORT_PATH}
  --json-output <path>  JSON report path. Default: ${DEFAULT_JSON_PATH}
  --collection <text>   Optional collection name or id filter for debugging. Can be repeated.
  --verbose             Print every failed sample while running
  --help                Show this help
`.trim();
}

function parseArgs(argv) {
  const options = {
    bundle: DEFAULT_BUNDLE_PATH,
    samples: 3,
    concurrency: 4,
    timeoutMs: 15000,
    bytes: 65536,
    retries: 1,
    retryDelayMs: 1000,
    openSeaApiKey: process.env.OPENSEA_API_KEY ?? null,
    openSeaPages: 1,
    headFallbackOn429: true,
    full: false,
    output: DEFAULT_REPORT_PATH,
    jsonOutput: DEFAULT_JSON_PATH,
    collectionFilters: [],
    verbose: false,
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
      case "--bundle":
        options.bundle = readValue();
        break;
      case "--samples":
        options.samples = positiveInteger(readValue(), arg);
        break;
      case "--concurrency":
        options.concurrency = positiveInteger(readValue(), arg);
        break;
      case "--timeout-ms":
        options.timeoutMs = positiveInteger(readValue(), arg);
        break;
      case "--bytes":
        options.bytes = positiveInteger(readValue(), arg);
        break;
      case "--retries":
        options.retries = nonNegativeInteger(readValue(), arg);
        break;
      case "--retry-delay-ms":
        options.retryDelayMs = positiveInteger(readValue(), arg);
        break;
      case "--opensea-api-key":
        options.openSeaApiKey = readValue();
        break;
      case "--opensea-pages":
        options.openSeaPages = openSeaPageLimit(readValue(), arg);
        break;
      case "--output":
        options.output = readValue();
        break;
      case "--json-output":
        options.jsonOutput = readValue();
        break;
      case "--collection":
        options.collectionFilters.push(readValue().toLowerCase());
        break;
      case "--full":
        options.full = true;
        break;
      case "--no-head-fallback":
        options.headFallbackOn429 = false;
        break;
      case "--verbose":
        options.verbose = true;
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

function openSeaPageLimit(value, optionName) {
  if (value === "all") {
    return Number.POSITIVE_INFINITY;
  }
  return positiveInteger(value, optionName);
}

function projectIdFor(item) {
  return item.abId ?? item.collectionId ?? "";
}

function buildDownloadTarget(collection, token) {
  if (collection.source === "opensea-api") {
    return buildOpenSeaDownloadTarget(token);
  }

  if (token.sh) {
    return {
      kind: "simplehash",
      url: `https://cdn.simplehash.com/assets/${token.sh}`,
    };
  }

  if (token.url) {
    return normalizeAppURL(token.url);
  }

  return {
    kind: "artblocks-media-proxy",
    url: `https://media-proxy.artblocks.io/${collection.address}/${token.id}.png`,
  };
}

function buildOpenSeaDownloadTarget(token) {
  const candidates = [
    { kind: "opensea-image-url", url: token.imageUrl },
    { kind: "opensea-display-image-url", url: token.displayImageUrl },
    { kind: "opensea-metadata-url", url: token.metadataUrl },
  ];

  for (const candidate of candidates) {
    if (!candidate.url) {
      continue;
    }
    const target = normalizeAppURL(candidate.url);
    return {
      ...target,
      kind: target.kind === "explicit-url" ? candidate.kind : `${candidate.kind}:${target.kind}`,
    };
  }

  return {
    kind: "opensea-no-downloadable-url",
    url: null,
    okWithoutURL: false,
    error: "no downloadable image or metadata URL in OpenSea NFT response",
  };
}

function normalizeAppURL(urlString) {
  if (urlString.startsWith("ipfs://")) {
    return {
      kind: "ipfs-gateway",
      url: `https://ipfs.decentralized-content.com/ipfs/${urlString.slice("ipfs://".length)}`,
    };
  }

  if (urlString.startsWith("ar://")) {
    return {
      kind: "arweave-gateway",
      url: `https://arweave.net/${urlString.slice("ar://".length)}`,
    };
  }

  if (!urlString.startsWith("http")) {
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

function normalizeBundledTokenRows(bundledTokens) {
  const urlPrefixes = Array.isArray(bundledTokens.urlPrefixes) ? bundledTokens.urlPrefixes : [];
  const defaultFileExtension = typeof bundledTokens.defaultFileExtension === "string"
    ? bundledTokens.defaultFileExtension
    : null;

  return (bundledTokens.items ?? []).map((token) => {
    if (!Array.isArray(token)) {
      return token;
    }

    const [id, prefixIndex, urlSuffix, fileExtension] = token;
    const urlPrefix = urlPrefixes[prefixIndex] ?? "";
    const extension = typeof fileExtension === "string" ? fileExtension : defaultFileExtension;

    return {
      id,
      url: `${urlPrefix}${urlSuffix ?? ""}`,
      fileExtension: extension,
    };
  });
}

function sampleTokens(tokens, count) {
  const validTokens = tokens.filter((token) => token && token.id);
  if (validTokens.length <= count) {
    return validTokens;
  }

  const indexes = new Set();
  if (count === 1) {
    indexes.add(0);
  } else {
    for (let index = 0; index < count; index += 1) {
      indexes.add(Math.round((index * (validTokens.length - 1)) / (count - 1)));
    }
  }

  for (let index = 0; indexes.size < count && index < validTokens.length; index += 1) {
    indexes.add(index);
  }

  return [...indexes].sort((a, b) => a - b).map((index) => validTokens[index]);
}

async function readJson(filePath) {
  return JSON.parse(await fs.readFile(filePath, "utf8"));
}

async function readCollections(options) {
  const bundlePath = path.resolve(options.bundle);
  const itemsPath = path.join(bundlePath, "items.json");
  const tokensPath = path.join(bundlePath, "Tokens");
  const [items, tokenFileNames, bundledGenerativeCollectionIds] = await Promise.all([
    readJson(itemsPath),
    fs.readdir(tokensPath),
    loadBundledGenerativeCollectionIds(bundlePath),
  ]);

  const tokenFileNameById = new Map(
    tokenFileNames
      .filter((fileName) => fileName.endsWith(".json"))
      .map((fileName) => [fileName.slice(0, -".json".length), fileName]),
  );

  const collections = [];
  const missingTokenFiles = [];
  const skippedCollections = [];
  let suggestedItemsMatched = 0;
  for (const item of items) {
    const id = collectionIdFor(item);
    if (options.collectionFilters.length > 0) {
      const haystack = `${id} ${item.name ?? ""} ${item.address ?? ""}`.toLowerCase();
      if (!options.collectionFilters.some((filter) => haystack.includes(filter))) {
        continue;
      }
    }

    suggestedItemsMatched += 1;
    if (isBundledGenerativeCollectionId(id, bundledGenerativeCollectionIds)) {
      skippedCollections.push({
        id,
        name: item.name,
        address: item.address,
        projectId: projectIdFor(item),
        chain: item.chain,
        chainId: item.chainId,
        reason: BUNDLED_GENERATIVE_SKIP_REASON,
      });
      continue;
    }

    const tokenFileName = tokenFileNameById.get(id) ?? tokenFileNameById.get(id.toLowerCase());
    if (!tokenFileName) {
      missingTokenFiles.push({
        id,
        name: item.name,
        address: item.address,
        projectId: projectIdFor(item),
        chain: item.chain,
        chainId: item.chainId,
      });
      continue;
    }

    const tokenFilePath = path.join(tokensPath, tokenFileName);
    const bundledTokens = await readJson(tokenFilePath);
    const normalizedTokens = normalizeBundledTokenRows(bundledTokens);
    collections.push({
      source: "bundled-tokens",
      id,
      name: item.name,
      address: item.address,
      projectId: projectIdFor(item),
      chain: item.chain,
      chainId: item.chainId,
      isComplete: bundledTokens.isComplete !== false,
      tokenCount: normalizedTokens.length,
      sampledTokens: sampleTokens(normalizedTokens, options.samples),
    });
  }

  return {
    bundlePath,
    collections,
    missingTokenFiles,
    skippedCollections,
    suggestedItemsMatched,
    bundledTokenJsonFiles: tokenFileNameById.size,
  };
}

async function loadOpenSeaFallbackCollections(missingTokenFiles, options) {
  const collections = [];
  if (missingTokenFiles.length === 0) {
    return collections;
  }

  if (!options.openSeaApiKey) {
    return missingTokenFiles.map((item) => ({
      ...item,
      source: "opensea-api",
      isComplete: false,
      tokenCount: 0,
      sampledTokens: [],
      openSeaApiError: "missing OpenSea API key; pass --opensea-api-key or set OPENSEA_API_KEY",
    }));
  }

  for (const item of missingTokenFiles) {
    const result = await fetchOpenSeaCollectionNfts(item, options);
    if (!result.ok) {
      collections.push({
        ...item,
        source: "opensea-api",
        isComplete: false,
        tokenCount: 0,
        sampledTokens: [],
        openSeaApiError: result.error,
        openSeaStatus: result.status ?? null,
        openSeaPagesFetched: result.pagesFetched ?? 0,
      });
      continue;
    }

    collections.push({
      ...item,
      source: "opensea-api",
      isComplete: false,
      tokenCount: result.tokens.length,
      sampledTokens: sampleTokens(result.tokens, options.samples),
      openSeaPagesFetched: result.pagesFetched,
      openSeaHasMore: Boolean(result.nextCursor),
    });
  }

  return collections;
}

async function fetchOpenSeaCollectionNfts(collection, options) {
  const tokens = [];
  let nextCursor = null;
  let pagesFetched = 0;

  while (pagesFetched < options.openSeaPages) {
    const result = await fetchOpenSeaNftPage(collection, nextCursor, options);
    if (!result.ok) {
      return {
        ...result,
        tokens,
        pagesFetched,
      };
    }

    pagesFetched += 1;
    tokens.push(...result.nfts.map(normalizeOpenSeaNft).filter((token) => token.id));
    nextCursor = result.nextCursor ?? null;
    if (!nextCursor) {
      break;
    }
  }

  return {
    ok: true,
    tokens,
    nextCursor,
    pagesFetched,
  };
}

async function fetchOpenSeaNftPage(collection, nextCursor, options) {
  const url = new URL(`https://api.opensea.io/api/v2/chain/${openSeaChain(collection)}/contract/${collection.address}/nfts`);
  if (nextCursor) {
    url.searchParams.set("next", nextCursor);
  }

  let lastResult = null;
  for (let attemptIndex = 0; attemptIndex <= options.retries; attemptIndex += 1) {
    const result = await fetchOpenSeaJson(url, options);
    if (result.ok || !shouldRetry(result) || attemptIndex >= options.retries) {
      return result;
    }

    lastResult = result;
    const retryDelay = retryDelayMs(result, options.retryDelayMs, attemptIndex);
    await sleep(retryDelay);
  }

  return lastResult;
}

function openSeaChain(collection) {
  switch (collection.chainId) {
    case 10:
      return "optimism";
    case 7777777:
      return "zora";
    case 8453:
      return "base";
    case 42161:
      return "arbitrum";
    case 238:
      return "blast";
    case 1:
    default:
      return "ethereum";
  }
}

async function fetchOpenSeaJson(url, options) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), options.timeoutMs);

  try {
    const response = await fetch(url, {
      method: "GET",
      redirect: "follow",
      signal: controller.signal,
      headers: {
        "accept": "application/json",
        "x-api-key": options.openSeaApiKey,
        "User-Agent": "nft-player-bundled-download-check/1.0",
      },
    });

    const text = await response.text();
    if (!response.ok) {
      return {
        ok: false,
        status: response.status,
        retryAfterMs: parseRetryAfter(response.headers.get("retry-after")),
        error: `OpenSea HTTP ${response.status}${formatOpenSeaErrorText(text)}`,
      };
    }

    let body;
    try {
      body = JSON.parse(text);
    } catch (error) {
      return {
        ok: false,
        status: response.status,
        retryable: false,
        error: `OpenSea JSON parse failed: ${error.message}`,
      };
    }

    return {
      ok: true,
      status: response.status,
      nfts: Array.isArray(body.nfts) ? body.nfts : [],
      nextCursor: body.next ?? null,
    };
  } catch (error) {
    return {
      ok: false,
      status: null,
      error: error.name === "AbortError" ? `OpenSea timeout after ${options.timeoutMs}ms` : `OpenSea request failed: ${error.message}`,
    };
  } finally {
    clearTimeout(timeout);
  }
}

function formatOpenSeaErrorText(text) {
  if (!text) {
    return "";
  }

  try {
    const body = JSON.parse(text);
    if (Array.isArray(body.errors) && body.errors.length > 0) {
      return `: ${body.errors.join("; ")}`;
    }
    if (typeof body.error === "string") {
      return `: ${body.error}`;
    }
    if (typeof body.message === "string") {
      return `: ${body.message}`;
    }
  } catch {
    const trimmed = text.trim();
    if (trimmed) {
      return `: ${trimmed.slice(0, 160)}`;
    }
  }

  return "";
}

function normalizeOpenSeaNft(nft) {
  return {
    id: nft.identifier,
    name: nft.name ?? null,
    imageUrl: nft.image_url ?? null,
    displayImageUrl: nft.display_image_url ?? null,
    displayAnimationUrl: nft.display_animation_url ?? null,
    metadataUrl: nft.metadata_url ?? null,
  };
}

async function attemptDownload(target, options) {
  if (!target.url) {
    return {
      ok: target.okWithoutURL !== false,
      targetKind: target.kind,
      url: null,
      status: null,
      finalUrl: null,
      contentType: null,
      bytesRead: 0,
      elapsedMs: 0,
      attempts: 0,
      error: target.okWithoutURL === false ? target.error : null,
      note: target.okWithoutURL === false ? null : "embedded data, no network URL",
    };
  }

  let lastResult = null;
  for (let attemptIndex = 0; attemptIndex <= options.retries; attemptIndex += 1) {
    const result = await fetchTarget(target, options, "GET");
    result.attempts = attemptIndex + 1;
    if (result.ok) {
      return result;
    }

    lastResult = result;
    if (attemptIndex >= options.retries || !shouldRetry(result)) {
      break;
    }

    const retryDelay = retryDelayMs(result, options.retryDelayMs, attemptIndex);
    await sleep(retryDelay);
  }

  if (options.headFallbackOn429 && lastResult?.status === 429) {
    const headResult = await fetchTarget(target, options, "HEAD");
    if (headResult.ok) {
      return {
        ...headResult,
        ok: true,
        bytesRead: 0,
        attempts: lastResult.attempts,
        headFallbackConfirmed: true,
        getStatus: lastResult.status,
        getError: lastResult.error,
        note: `GET returned HTTP 429 after ${lastResult.attempts} attempt(s); HEAD fallback confirmed reachable`,
      };
    }

    lastResult.headFallback = {
      status: headResult.status,
      error: headResult.error,
      elapsedMs: headResult.elapsedMs,
      finalUrl: headResult.finalUrl,
    };
  }

  return lastResult;
}

async function fetchTarget(target, options, method) {
  const startedAt = Date.now();

  let parsedURL;
  try {
    parsedURL = new URL(target.url);
  } catch (error) {
    return {
      ok: false,
      targetKind: target.kind,
      url: target.url,
      status: null,
      finalUrl: null,
      contentType: null,
      bytesRead: 0,
      elapsedMs: Date.now() - startedAt,
      method,
      retryable: false,
      error: `invalid URL: ${error.message}`,
    };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), options.timeoutMs);

  try {
    const response = await fetch(parsedURL, {
      method,
      redirect: "follow",
      signal: controller.signal,
      headers: {
        "User-Agent": "nft-player-bundled-download-check/1.0",
      },
    });

    const result = {
      ok: false,
      targetKind: target.kind,
      url: target.url,
      status: response.status,
      finalUrl: response.url,
      contentType: response.headers.get("content-type"),
      bytesRead: 0,
      elapsedMs: Date.now() - startedAt,
      method,
      retryAfterMs: parseRetryAfter(response.headers.get("retry-after")),
    };

    if (!response.ok) {
      result.error = `HTTP ${response.status}`;
      return result;
    }

    if (method === "HEAD") {
      result.ok = true;
      return result;
    }

    result.bytesRead = await readResponseBytes(response, options);
    result.elapsedMs = Date.now() - startedAt;
    if (result.bytesRead > 0) {
      result.ok = true;
      return result;
    }

    result.error = "empty response body";
    return result;
  } catch (error) {
    const elapsedMs = Date.now() - startedAt;
    return {
      ok: false,
      targetKind: target.kind,
      url: target.url,
      status: null,
      finalUrl: null,
      contentType: null,
      bytesRead: 0,
      elapsedMs,
      method,
      error: error.name === "AbortError" ? `timeout after ${options.timeoutMs}ms` : error.message,
    };
  } finally {
    clearTimeout(timeout);
  }
}

function shouldRetry(result) {
  if (result.retryable === false) {
    return false;
  }

  if (result.status == null) {
    return true;
  }

  return [408, 429, 500, 502, 503, 504].includes(result.status);
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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function readResponseBytes(response, options) {
  if (!response.body) {
    const buffer = await response.arrayBuffer();
    return buffer.byteLength;
  }

  const reader = response.body.getReader();
  let bytesRead = 0;
  const byteLimit = options.full ? Number.POSITIVE_INFINITY : options.bytes;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }

      bytesRead += value.byteLength;
      if (bytesRead >= byteLimit) {
        await reader.cancel();
        break;
      }
    }
  } finally {
    reader.releaseLock();
  }

  return bytesRead;
}

async function runPool(items, concurrency, worker, onProgress) {
  let nextIndex = 0;
  let completed = 0;
  const workers = Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    while (nextIndex < items.length) {
      const currentIndex = nextIndex;
      nextIndex += 1;
      await worker(items[currentIndex], currentIndex);
      completed += 1;
      onProgress(completed, items.length);
    }
  });

  await Promise.all(workers);
}

function summarizeCollection(collection) {
  const successes = collection.samples.filter((sample) => sample.ok).length;
  const failures = collection.samples.length - successes;
  const apiFailures = collection.openSeaApiError ? 1 : 0;
  return {
    ...collection,
    successes,
    failures,
    apiFailures,
    totalFailures: failures + apiFailures,
    reachable: apiFailures === 0 && successes > 0,
    fullyReachable: apiFailures === 0 && failures === 0 && collection.samples.length > 0,
  };
}

function escapeCell(value) {
  return String(value ?? "")
    .replace(/\|/g, "\\|")
    .replace(/\n/g, " ");
}

function formatStatus(sample) {
  if (sample.ok) {
    if (sample.headFallbackConfirmed) {
      return `ok HEAD after GET ${sample.getStatus}`;
    }
    return `ok ${sample.status ?? ""}`.trim();
  }
  return sample.error ?? `HTTP ${sample.status ?? "unknown"}`;
}

function markdownLink(url) {
  if (!url) {
    return "";
  }
  return `[link](${url})`;
}

function renderFailureList(samples) {
  return samples
    .filter((sample) => !sample.ok)
    .map((sample) => {
      const parts = [
        `token ${sample.tokenId}`,
        sample.targetKind,
        formatStatus(sample),
        sample.status ? `status ${sample.status}` : null,
        `${sample.elapsedMs}ms`,
        markdownLink(sample.url),
      ].filter(Boolean);
      return parts.join(" / ");
    })
    .join("<br>");
}

function renderMarkdownReport(report) {
  const unreachable = report.collections.filter((collection) => !collection.reachable);
  const partial = report.collections.filter((collection) => collection.reachable && !collection.fullyReachable);
  const openSeaFallback = report.collections.filter((collection) => collection.source === "opensea-api");
  const failedSamples = report.collections.flatMap((collection) =>
    collection.samples
      .filter((sample) => !sample.ok)
      .map((sample) => ({ collection, sample })),
  );

  const lines = [];
  lines.push("# Bundled Collection Download Reachability Report");
  lines.push("");
  lines.push(`Generated: ${report.generatedAt}`);
  lines.push("");
  lines.push("## Scope");
  lines.push("");
  lines.push(`- Suggested bundle: \`${report.bundlePath}\``);
  lines.push(`- Suggested items matched: ${report.summary.suggestedItemsMatched}`);
  lines.push(`- Bundled token JSON files present: ${report.summary.bundledTokenJsonFiles}`);
  lines.push(`- Bundled generative collections skipped: ${report.summary.bundledGenerativeCollectionsSkipped}`);
  lines.push(`- Token-backed suggested collections checked: ${report.summary.tokenBackedCollectionsChecked}`);
  lines.push(`- OpenSea fallback collections checked: ${report.summary.openSeaFallbackCollectionsChecked}`);
  lines.push(`- Collections checked: ${report.summary.collectionsChecked}`);
  lines.push(`- Download attempts: ${report.summary.downloadAttempts}`);
  lines.push(`- Samples per collection requested: ${report.options.samples}`);
  lines.push(`- OpenSea fallback API: ${report.options.openSeaApiEnabled ? `enabled, ${report.options.openSeaPages} page(s) per missing-token collection` : "disabled, no API key"}`);
  lines.push(`- Timeout per item: ${report.options.timeoutMs}ms`);
  lines.push(`- Response bytes read per item: ${report.options.full ? "full response" : report.options.bytes}`);
  lines.push(`- Retries per item: ${report.options.retries}`);
  lines.push(`- HEAD fallback after repeated GET 429s: ${report.options.headFallbackOn429 ? "yes" : "no"}`);
  lines.push(`- Concurrency: ${report.options.concurrency}`);
  lines.push("");
  lines.push("The script uses the same bundled item URL precedence as `WalletDownloader`: `sh` fields map to `https://cdn.simplehash.com/assets/{sh}`, explicit `url` fields are used after the app's `ipfs://` and `ar://` gateway normalization, and other bundled items map to `https://media-proxy.artblocks.io/{collectionAddress}/{tokenId}.png`. Suggested items without bundled token JSON use the same network-specific OpenSea contract NFT endpoint as `RawNftsApi.get(contract:)`, then sample the image, display image, and metadata URLs that the app would use by default.");
  lines.push("");
  lines.push("## Summary");
  lines.push("");
  lines.push(`- Fully reachable collections: ${report.summary.fullyReachableCollections}`);
  lines.push(`- Partially reachable collections: ${report.summary.partiallyReachableCollections}`);
  lines.push(`- Unreachable collections: ${report.summary.unreachableCollections}`);
  lines.push(`- Failed item samples: ${report.summary.failedSamples}`);
  lines.push(`- OpenSea fallback API failures: ${report.summary.openSeaFallbackApiFailures}`);
  lines.push(`- Samples confirmed by HEAD fallback after GET 429: ${report.summary.headFallbackConfirmedSamples}`);
  lines.push(`- Suggested items without bundled token JSON: ${report.summary.suggestedItemsWithoutTokenJson}`);
  lines.push("");
  lines.push("A collection is marked unreachable when every sampled item failed to return either a successful GET response with bytes or a successful HEAD fallback after repeated GET 429 rate-limit responses.");
  lines.push("");
  lines.push("## Skipped Bundled Generative Collections");
  lines.push("");
  if (report.skippedCollections.length === 0) {
    lines.push("None.");
  } else {
    lines.push("| Collection | Collection id | Reason |");
    lines.push("| --- | --- | --- |");
    for (const collection of report.skippedCollections) {
      lines.push(`| ${escapeCell(collection.name)} | \`${escapeCell(collection.id)}\` | ${escapeCell(collection.reason)} |`);
    }
  }
  lines.push("");
  lines.push("## Unreachable Collections");
  lines.push("");
  if (unreachable.length === 0) {
    lines.push("None.");
  } else {
    lines.push("| Collection | Collection id | Address | Project id | Tokens sampled | Failures |");
    lines.push("| --- | --- | --- | --- | ---: | --- |");
    for (const collection of unreachable) {
      lines.push(`| ${escapeCell(collection.name)} | \`${escapeCell(collection.id)}\` | \`${escapeCell(collection.address)}\` | \`${escapeCell(collection.projectId)}\` | ${collection.samples.length} | ${renderFailureList(collection.samples) || escapeCell(collection.openSeaApiError)} |`);
    }
  }
  lines.push("");
  lines.push("## Partially Reachable Collections");
  lines.push("");
  if (partial.length === 0) {
    lines.push("None.");
  } else {
    lines.push("| Collection | Collection id | Successes | Failures | Failed samples |");
    lines.push("| --- | --- | ---: | ---: | --- |");
    for (const collection of partial) {
      lines.push(`| ${escapeCell(collection.name)} | \`${escapeCell(collection.id)}\` | ${collection.successes} | ${collection.failures} | ${renderFailureList(collection.samples)} |`);
    }
  }
  lines.push("");
  lines.push("## Suggested Items Without Bundled Token JSON");
  lines.push("");
  if (report.missingTokenFiles.length === 0) {
    lines.push("None.");
  } else {
    lines.push("These items are present in `items.json` but do not have matching `Tokens/{collectionId}.json` files. The app falls through to the live OpenSea NFT API path for them, and this report now checks that path when an API key is available.");
    lines.push("");
    lines.push("| Collection | Collection id | Address | Chain | OpenSea tokens loaded | Status |");
    lines.push("| --- | --- | --- | --- | ---: | --- |");
    for (const item of report.missingTokenFiles) {
      const checked = openSeaFallback.find((collection) => collection.id === item.id);
      const status = checked?.openSeaApiError ? checked.openSeaApiError : checked ? "checked via OpenSea API" : "not checked";
      lines.push(`| ${escapeCell(item.name)} | \`${escapeCell(item.id)}\` | \`${escapeCell(item.address)}\` | ${escapeCell(item.chain ?? item.chainId ?? "")} | ${checked?.tokenCount ?? 0} | ${escapeCell(status)} |`);
    }
  }
  lines.push("");
  lines.push("## Failed Sample Details");
  lines.push("");
  if (failedSamples.length === 0) {
    lines.push("None.");
  } else {
    lines.push("| Collection | Token id | Source | Status | Bytes read | Elapsed | URL |");
    lines.push("| --- | --- | --- | --- | ---: | ---: | --- |");
    for (const { collection, sample } of failedSamples) {
      lines.push(`| ${escapeCell(collection.name)} | \`${escapeCell(sample.tokenId)}\` | ${escapeCell(sample.targetKind)} | ${escapeCell(formatStatus(sample))} | ${sample.bytesRead} | ${sample.elapsedMs}ms | ${markdownLink(sample.url)} |`);
    }
  }
  lines.push("");

  return `${lines.join("\n")}\n`;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const {
    bundlePath,
    collections: bundledCollections,
    missingTokenFiles,
    skippedCollections,
    suggestedItemsMatched,
    bundledTokenJsonFiles,
  } = await readCollections(options);
  if (missingTokenFiles.length > 0) {
    console.error(`Loading ${missingTokenFiles.length} suggested item(s) without bundled token JSON through OpenSea fallback...`);
  }
  const openSeaCollections = await loadOpenSeaFallbackCollections(missingTokenFiles, options);
  const collections = [...bundledCollections, ...openSeaCollections];
  const attempts = [];

  for (const collection of collections) {
    collection.samples = [];
    for (const token of collection.sampledTokens) {
      const target = buildDownloadTarget(collection, token);
      const sample = {
        collectionId: collection.id,
        tokenId: token.id,
        tokenName: token.name ?? null,
        targetKind: target.kind,
        url: target.url,
      };
      collection.samples.push(sample);
      attempts.push({ collection, sample, target });
    }
  }

  const startedAt = Date.now();
  let lastProgressAt = 0;
  console.error(`Checking ${collections.length} collections with ${attempts.length} download attempts...`);
  await runPool(
    attempts,
    options.concurrency,
    async ({ sample, target }) => {
      const result = await attemptDownload(target, options);
      Object.assign(sample, result);
      if (options.verbose && !sample.ok) {
        console.error(`failed: ${sample.collectionId} token ${sample.tokenId}: ${formatStatus(sample)} ${sample.url ?? ""}`);
      }
    },
    (completed, total) => {
      const now = Date.now();
      if (now - lastProgressAt > 5000 || completed === total) {
        lastProgressAt = now;
        console.error(`Checked ${completed}/${total} item downloads`);
      }
    },
  );

  const summarizedCollections = collections.map(summarizeCollection);
  const failedSamples = summarizedCollections.reduce((count, collection) => count + collection.failures, 0);
  const headFallbackConfirmedSamples = summarizedCollections.reduce(
    (count, collection) => count + collection.samples.filter((sample) => sample.headFallbackConfirmed).length,
    0,
  );
  const summary = {
    suggestedItemsMatched,
    bundledTokenJsonFiles,
    bundledGenerativeCollectionsSkipped: skippedCollections.length,
    tokenBackedCollectionsChecked: bundledCollections.length,
    openSeaFallbackCollectionsChecked: openSeaCollections.length,
    openSeaFallbackApiFailures: openSeaCollections.filter((collection) => collection.openSeaApiError).length,
    collectionsChecked: summarizedCollections.length,
    downloadAttempts: attempts.length,
    fullyReachableCollections: summarizedCollections.filter((collection) => collection.fullyReachable).length,
    partiallyReachableCollections: summarizedCollections.filter((collection) => collection.reachable && !collection.fullyReachable).length,
    unreachableCollections: summarizedCollections.filter((collection) => !collection.reachable).length,
    failedSamples,
    headFallbackConfirmedSamples,
    suggestedItemsWithoutTokenJson: missingTokenFiles.length,
    elapsedMs: Date.now() - startedAt,
  };

  const report = {
    generatedAt: new Date().toISOString(),
    bundlePath,
    options: {
      samples: options.samples,
      concurrency: options.concurrency,
      timeoutMs: options.timeoutMs,
      bytes: options.bytes,
      full: options.full,
      retries: options.retries,
      retryDelayMs: options.retryDelayMs,
      headFallbackOn429: options.headFallbackOn429,
      collectionFilter: options.collectionFilter,
      openSeaApiEnabled: Boolean(options.openSeaApiKey),
      openSeaPages: Number.isFinite(options.openSeaPages) ? options.openSeaPages : "all",
    },
    summary,
    missingTokenFiles,
    skippedCollections,
    collections: summarizedCollections,
  };

  const outputPath = path.resolve(options.output);
  const jsonOutputPath = path.resolve(options.jsonOutput);
  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  await fs.mkdir(path.dirname(jsonOutputPath), { recursive: true });
  await fs.writeFile(outputPath, renderMarkdownReport(report));
  await fs.writeFile(jsonOutputPath, `${JSON.stringify(report, null, 2)}\n`);

  console.error(`Report written to ${outputPath}`);
  console.error(`JSON written to ${jsonOutputPath}`);
  console.log(JSON.stringify(summary, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  console.error("");
  console.error(usage());
  process.exit(1);
});
