#!/usr/bin/env node

const fs = require("node:fs/promises");
const path = require("node:path");

const DEFAULT_BUNDLE_PATH = path.join("Suggested Items", "Suggested.bundle");
const DEFAULT_REPORT_PATH = path.join("tools", "reports", "bundled-collection-download-report.md");
const DEFAULT_JSON_PATH = path.join("tools", "reports", "bundled-collection-download-report.json");

function usage() {
  return `
Usage:
  node tools/check_bundled_collection_downloads.js [options]

Options:
  --bundle <path>       Suggested.bundle path. Default: ${DEFAULT_BUNDLE_PATH}
  --samples <number>    Number of token downloads to try per collection. Default: 3
  --concurrency <n>     Number of simultaneous network checks. Default: 4
  --timeout-ms <ms>     Timeout per item download attempt. Default: 15000
  --bytes <number>      Bytes to read from each response before stopping. Default: 65536
  --retries <number>    Retries for transient failures such as 429/5xx. Default: 1
  --retry-delay-ms <ms> Base retry delay. Default: 1000
  --full                Read each response fully instead of stopping after --bytes
  --no-head-fallback    Do not use HEAD to confirm URLs after repeated GET 429s
  --output <path>       Markdown report path. Default: ${DEFAULT_REPORT_PATH}
  --json-output <path>  JSON report path. Default: ${DEFAULT_JSON_PATH}
  --collection <text>   Optional collection name or id filter for debugging
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
    headFallbackOn429: true,
    full: false,
    output: DEFAULT_REPORT_PATH,
    jsonOutput: DEFAULT_JSON_PATH,
    collectionFilter: null,
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
      case "--output":
        options.output = readValue();
        break;
      case "--json-output":
        options.jsonOutput = readValue();
        break;
      case "--collection":
        options.collectionFilter = readValue().toLowerCase();
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

function collectionIdFor(item) {
  return `${item.address}${item.abId ?? item.collectionId ?? ""}`;
}

function projectIdFor(item) {
  return item.abId ?? item.collectionId ?? "";
}

function buildDownloadTarget(collection, token) {
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
  const [items, tokenFileNames] = await Promise.all([
    readJson(itemsPath),
    fs.readdir(tokensPath),
  ]);

  const tokenIds = new Set(
    tokenFileNames
      .filter((fileName) => fileName.endsWith(".json"))
      .map((fileName) => fileName.slice(0, -".json".length)),
  );

  const collections = [];
  const missingTokenFiles = [];
  for (const item of items) {
    const id = collectionIdFor(item);
    if (options.collectionFilter) {
      const haystack = `${id} ${item.name ?? ""} ${item.address ?? ""}`.toLowerCase();
      if (!haystack.includes(options.collectionFilter)) {
        continue;
      }
    }

    if (!tokenIds.has(id)) {
      missingTokenFiles.push({ id, name: item.name });
      continue;
    }

    const tokenFilePath = path.join(tokensPath, `${id}.json`);
    const bundledTokens = await readJson(tokenFilePath);
    collections.push({
      id,
      name: item.name,
      address: item.address,
      projectId: projectIdFor(item),
      chain: item.chain,
      chainId: item.chainId,
      isComplete: Boolean(bundledTokens.isComplete),
      tokenCount: Array.isArray(bundledTokens.items) ? bundledTokens.items.length : 0,
      sampledTokens: sampleTokens(bundledTokens.items ?? [], options.samples),
    });
  }

  return { bundlePath, collections, missingTokenFiles };
}

async function attemptDownload(target, options) {
  if (!target.url) {
    return {
      ok: true,
      targetKind: target.kind,
      url: null,
      status: null,
      finalUrl: null,
      contentType: null,
      bytesRead: 0,
      elapsedMs: 0,
      attempts: 0,
      note: "embedded data, no network URL",
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
        "User-Agent": "nft-folder-bundled-download-check/1.0",
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
  return {
    ...collection,
    successes,
    failures,
    reachable: successes > 0,
    fullyReachable: failures === 0 && collection.samples.length > 0,
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
  lines.push(`- Bundled collections checked: ${report.summary.collectionsChecked}`);
  lines.push(`- Download attempts: ${report.summary.downloadAttempts}`);
  lines.push(`- Samples per collection requested: ${report.options.samples}`);
  lines.push(`- Timeout per item: ${report.options.timeoutMs}ms`);
  lines.push(`- Response bytes read per item: ${report.options.full ? "full response" : report.options.bytes}`);
  lines.push(`- Retries per item: ${report.options.retries}`);
  lines.push(`- HEAD fallback after repeated GET 429s: ${report.options.headFallbackOn429 ? "yes" : "no"}`);
  lines.push(`- Concurrency: ${report.options.concurrency}`);
  lines.push("");
  lines.push("The script uses the same bundled item URL precedence as `WalletDownloader`: `sh` fields map to `https://cdn.simplehash.com/assets/{sh}`, explicit `url` fields are used after the app's `ipfs://` and `ar://` gateway normalization, and other items map to `https://media-proxy.artblocks.io/{collectionAddress}/{tokenId}.png`.");
  lines.push("");
  lines.push("## Summary");
  lines.push("");
  lines.push(`- Fully reachable collections: ${report.summary.fullyReachableCollections}`);
  lines.push(`- Partially reachable collections: ${report.summary.partiallyReachableCollections}`);
  lines.push(`- Unreachable collections: ${report.summary.unreachableCollections}`);
  lines.push(`- Failed item samples: ${report.summary.failedSamples}`);
  lines.push(`- Samples confirmed by HEAD fallback after GET 429: ${report.summary.headFallbackConfirmedSamples}`);
  lines.push(`- Suggested items without bundled token JSON: ${report.summary.suggestedItemsWithoutTokenJson}`);
  lines.push("");
  lines.push("A collection is marked unreachable when every sampled item failed to return either a successful GET response with bytes or a successful HEAD fallback after repeated GET 429 rate-limit responses.");
  lines.push("");
  lines.push("## Unreachable Collections");
  lines.push("");
  if (unreachable.length === 0) {
    lines.push("None.");
  } else {
    lines.push("| Collection | Collection id | Address | Project id | Tokens sampled | Failures |");
    lines.push("| --- | --- | --- | --- | ---: | --- |");
    for (const collection of unreachable) {
      lines.push(`| ${escapeCell(collection.name)} | \`${escapeCell(collection.id)}\` | \`${escapeCell(collection.address)}\` | \`${escapeCell(collection.projectId)}\` | ${collection.samples.length} | ${renderFailureList(collection.samples)} |`);
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
  const { bundlePath, collections, missingTokenFiles } = await readCollections(options);
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
  console.error(`Checking ${collections.length} bundled collections with ${attempts.length} download attempts...`);
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
    },
    summary,
    missingTokenFiles,
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
