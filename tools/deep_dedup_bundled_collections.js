#!/usr/bin/env node

const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const path = require("node:path");
const { spawn } = require("node:child_process");
const { Readable } = require("node:stream");
const { suggestedItemId } = require("./suggested_items");

const DEFAULT_BUNDLE_PATH = path.join("Suggested Items", "Suggested.bundle");
const DEFAULT_REPORT_PATH = path.join("tools", "reports", "deep-dedup-bundled-collections.md");
const DEFAULT_JSON_REPORT_PATH = path.join("tools", "reports", "deep-dedup-bundled-collections.json");
const TRANSIENT_HTTP_STATUSES = new Set([408, 425, 429, 500, 502, 503, 504]);
const SIMPLEHASH_ASSET_BASE_URL = "https://cdn.simplehash.com/assets/";

function usage() {
  return `
Usage:
  node tools/deep_dedup_bundled_collections.js --chain tezos --apply
  node tools/deep_dedup_bundled_collections.js --collection "Drawing Exercises" --dry-run

Options:
  --bundle <path>         Suggested.bundle path. Default: ${DEFAULT_BUNDLE_PATH}
  --chain <name>          Limit by chain. Repeatable.
  --collection <value>    Limit by collection id, address, or name. Repeatable.
  --apply                 Rewrite token JSON and items.json.
  --dry-run               Report only. Default.
  --report <path>         Markdown report path. Default: ${DEFAULT_REPORT_PATH}
  --json-report <path>    JSON report path. Default: ${DEFAULT_JSON_REPORT_PATH}
  --concurrency <number>  Concurrent file hash downloads. Default: 6
  --timeout-ms <number>   Per-request timeout. Default: 45000
  --retries <number>      Retry count for transient download failures. Default: 2
  --verbose               Print duplicate details while running.
  --help                  Show this help.
`.trim();
}

function parseArgs(argv) {
  const options = {
    bundlePath: DEFAULT_BUNDLE_PATH,
    chains: [],
    collections: [],
    apply: false,
    reportPath: DEFAULT_REPORT_PATH,
    jsonReportPath: DEFAULT_JSON_REPORT_PATH,
    concurrency: 6,
    timeoutMs: 45000,
    retries: 2,
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
        options.bundlePath = readValue();
        break;
      case "--chain":
        options.chains.push(readValue().toLowerCase());
        break;
      case "--collection":
        options.collections.push(readValue().toLowerCase());
        break;
      case "--apply":
        options.apply = true;
        break;
      case "--dry-run":
        options.apply = false;
        break;
      case "--report":
        options.reportPath = readValue();
        break;
      case "--json-report":
        options.jsonReportPath = readValue();
        break;
      case "--concurrency":
        options.concurrency = positiveInteger(readValue(), arg);
        break;
      case "--timeout-ms":
        options.timeoutMs = positiveInteger(readValue(), arg);
        break;
      case "--retries":
        options.retries = nonNegativeInteger(readValue(), arg);
        break;
      case "--verbose":
        options.verbose = true;
        break;
      case "--help":
        console.log(usage());
        process.exit(0);
        break;
      default:
        if (arg.startsWith("--")) {
          throw new Error(`Unknown option: ${arg}`);
        }
        options.collections.push(arg.toLowerCase());
        break;
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

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const context = await loadContext(options);
  if (context.collections.length === 0) {
    throw new Error("No bundled collections matched. Use --chain or --collection to select targets.");
  }

  console.log(`Loaded ${context.collections.length} bundled collection(s).`);
  for (const collection of context.collections) {
    console.log(`  ${collection.name}: ${collection.records.length} token row(s)`);
  }

  removeDuplicateURLs(context.collections);

  const hashResultsByUrl = await hashCollectionMedia(context.collections, options);
  removeDuplicateContent(context.collections, hashResultsByUrl, options);

  await writeReports(context.collections, options);

  if (options.apply) {
    await writeUpdatedBundle(context);
    console.log(`Applied deep dedup to ${context.collections.length} collection(s).`);
  } else {
    console.log("Dry run complete. Reports were written; bundle assets were not changed.");
  }

  const removedCount = context.collections.reduce((sum, collection) => sum + collection.removedRecords.length, 0);
  const failedCount = context.collections.reduce((sum, collection) => sum + collection.failedHashItems.length, 0);
  console.log(`Removed candidates: ${removedCount}. Hash failures: ${failedCount}.`);
}

async function loadContext(options) {
  const bundlePath = path.resolve(options.bundlePath);
  const itemsPath = path.join(bundlePath, "items.json");
  const tokensPath = path.join(bundlePath, "Tokens");
  const items = JSON.parse(await fs.readFile(itemsPath, "utf8"));
  const selectedItems = selectSuggestedItems(items, options);
  const collections = [];

  for (const item of selectedItems) {
    const collectionId = suggestedItemId(item);
    const tokenPath = path.join(tokensPath, `${collectionId}.json`);
    const tokenPayload = JSON.parse(await fs.readFile(tokenPath, "utf8"));
    const records = parseTokenRecords(tokenPayload, item);
    collections.push({
      item,
      collectionId,
      tokenPath,
      tokenPayload,
      originalTokenCount: records.length,
      name: item.name,
      records,
      keptRecords: records,
      removedRecords: [],
      duplicateUrlItems: [],
      duplicateContentItems: [],
      failedHashItems: [],
    });
  }

  return {
    options,
    bundlePath,
    itemsPath,
    items,
    collections,
  };
}

function selectSuggestedItems(items, options) {
  const chainFilter = new Set(options.chains);
  const collectionFilter = new Set(options.collections);

  return items.filter((item) => {
    if (item.tokenCount == null) {
      return false;
    }

    if (chainFilter.size > 0 && !chainFilter.has(String(item.chain).toLowerCase())) {
      return false;
    }

    if (collectionFilter.size === 0) {
      return true;
    }

    const values = [
      suggestedItemId(item),
      item.address,
      item.collectionId,
      item.name,
    ].filter(Boolean).map((value) => String(value).toLowerCase());

    return values.some((value) => collectionFilter.has(value));
  });
}

function parseTokenRecords(payload, collectionItem) {
  const rows = Array.isArray(payload.items) ? payload.items : [];
  const urlPrefixes = Array.isArray(payload.urlPrefixes) ? payload.urlPrefixes : [];
  const defaultFileExtension = normalizeExtension(payload.defaultFileExtension);
  const metadataById = tokenMetadataById(payload);

  return rows.map((row, index) => {
    const metadata = metadataById.get(String(Array.isArray(row) ? row[0] : row?.id ?? row?.tokenId ?? index)) ?? {};
    if (Array.isArray(row)) {
      const id = String(row[0]);
      const prefixIndex = Number(row[1]);
      const suffix = String(row[2] ?? "");
      const prefix = urlPrefixes[prefixIndex] ?? "";
      const url = prefix + suffix;
      const fileExtension = normalizeExtension(row[3]) ?? defaultFileExtension ?? extensionFromURL(url);
      return {
        row,
        rowIndex: index,
        id,
        name: metadata.name ?? null,
        url,
        fileExtension,
        rowKind: "compact",
      };
    }

    if (row && typeof row === "object") {
      const id = String(row.id ?? row.tokenId ?? index);
      const url = resolvedObjectRowURL(row, collectionItem);
      return {
        row,
        rowIndex: index,
        id,
        name: row.name ?? metadata.name ?? null,
        url,
        fileExtension: normalizeExtension(row.fileExtension ?? row.extension) ?? extensionFromURL(url) ?? defaultFileExtension,
        rowKind: "object",
      };
    }

    return {
      row,
      rowIndex: index,
      id: String(index),
      name: metadata.name ?? null,
      url: null,
      fileExtension: defaultFileExtension,
      rowKind: "unknown",
    };
  });
}

function tokenMetadataById(payload) {
  const map = new Map();
  const decisionItems = payload?._tezosBundler?.mediaReview?.decisionItems;
  if (!Array.isArray(decisionItems)) {
    return map;
  }
  for (const item of decisionItems) {
    if (item?.id != null) {
      map.set(String(item.id), {
        name: item.name ?? null,
      });
    }
  }
  return map;
}

function resolvedObjectRowURL(row, collectionItem) {
  if (typeof row.url === "string" && row.url.length > 0) {
    return row.url;
  }
  if (typeof row.sh === "string" && row.sh.length > 0) {
    return `${SIMPLEHASH_ASSET_BASE_URL}${row.sh}`;
  }
  if (String(collectionItem.chain).toLowerCase() === "ethereum" && row.id != null) {
    return `https://media-proxy.artblocks.io/${collectionItem.address}/${row.id}.png`;
  }
  return null;
}

function removeDuplicateURLs(collections) {
  for (const collection of collections) {
    const seenByUrl = new Map();
    const kept = [];

    for (const record of collection.keptRecords) {
      if (!record.url) {
        kept.push(record);
        continue;
      }

      const existing = seenByUrl.get(record.url);
      if (existing) {
        const duplicate = duplicateItem(record, existing, {
          reason: "duplicate-url",
          url: record.url,
        });
        collection.duplicateUrlItems.push(duplicate);
        collection.removedRecords.push(record);
        continue;
      }

      seenByUrl.set(record.url, record);
      kept.push(record);
    }

    collection.keptRecords = kept;
  }
}

async function hashCollectionMedia(collections, options) {
  const urls = uniqueStrings(collections.flatMap((collection) =>
    collection.keptRecords
      .filter((record) => record.url)
      .map((record) => record.url)
  ));
  const total = urls.length;
  let completed = 0;
  const results = new Map();

  console.log(`Hashing ${total} unique media URL(s) with concurrency ${options.concurrency}.`);
  await runPool(urls, options.concurrency, async (url) => {
    const result = await hashURLWithRetry(url, options);
    completed += 1;
    results.set(url, result);
    if (completed === total || completed % 25 === 0) {
      console.log(`  hashed ${completed}/${total}`);
    }
  });

  return results;
}

async function runPool(values, concurrency, worker) {
  let cursor = 0;
  async function runWorker() {
    for (;;) {
      const index = cursor;
      cursor += 1;
      if (index >= values.length) {
        return;
      }
      await worker(values[index], index);
    }
  }

  await Promise.all(Array.from({ length: Math.min(concurrency, values.length) }, runWorker));
}

async function hashURLWithRetry(url, options) {
  let lastError = null;
  for (let attempt = 0; attempt <= options.retries; attempt += 1) {
    try {
      return await hashURL(url, options.timeoutMs);
    } catch (error) {
      lastError = error;
      if (!isTransientDownloadError(error) || attempt >= options.retries) {
        break;
      }
      await sleep(retryDelayMs(attempt));
    }
  }

  try {
    return await hashURLWithCurl(url, options.timeoutMs);
  } catch (error) {
    const fetchMessage = lastError?.message ?? "Unknown fetch failure";
    return {
      url,
      ok: false,
      error: `${fetchMessage}; curl fallback failed: ${error.message}`,
    };
  }
}

async function hashURLWithCurl(url, timeoutMs) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash("sha256");
    let bytes = 0;
    let stderr = "";
    const timeoutSeconds = String(Math.ceil(timeoutMs / 1000));
    const child = spawn("curl", [
      "-L",
      "--fail",
      "--silent",
      "--show-error",
      "--max-time",
      timeoutSeconds,
      url,
    ], {
      stdio: ["ignore", "pipe", "pipe"],
    });

    child.stdout.on("data", (chunk) => {
      bytes += chunk.length;
      hash.update(chunk);
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("close", (code) => {
      if (code === 0) {
        resolve({
          url,
          ok: true,
          sha256: hash.digest("hex"),
          bytes,
          contentType: null,
          finalUrl: null,
          transport: "curl",
        });
      } else {
        reject(new Error(`curl exited ${code}: ${stderr.trim()}`));
      }
    });
    child.on("error", reject);
  });
}

async function hashURL(url, timeoutMs) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  let response;

  try {
    response = await fetch(url, {
      headers: {
        "Accept-Encoding": "identity",
      },
      redirect: "follow",
      signal: controller.signal,
    });
    clearTimeout(timeout);

    if (!response.ok) {
      const error = new Error(`HTTP ${response.status} for ${url}`);
      error.status = response.status;
      await response.body?.cancel?.();
      throw error;
    }

    const hash = crypto.createHash("sha256");
    let bytes = 0;
    const nodeStream = Readable.fromWeb(response.body);
    for await (const chunk of nodeStream) {
      bytes += chunk.length;
      hash.update(chunk);
    }

    return {
      url,
      ok: true,
      sha256: hash.digest("hex"),
      bytes,
      contentType: response.headers.get("content-type") ?? null,
      finalUrl: response.url,
    };
  } catch (error) {
    clearTimeout(timeout);
    throw error;
  }
}

function removeDuplicateContent(collections, hashResultsByUrl, options) {
  for (const collection of collections) {
    const seenByHash = new Map();
    const kept = [];

    for (const record of collection.keptRecords) {
      if (!record.url) {
        kept.push(record);
        continue;
      }

      const hashResult = hashResultsByUrl.get(record.url);
      if (!hashResult?.ok) {
        collection.failedHashItems.push({
          id: record.id,
          name: record.name,
          url: record.url,
          error: hashResult?.error ?? "Hash result missing",
        });
        kept.push(record);
        continue;
      }

      record.contentHash = hashResult.sha256;
      record.byteCount = hashResult.bytes;
      const hashKey = `${hashResult.bytes}:${hashResult.sha256}`;
      const existing = seenByHash.get(hashKey);
      if (existing) {
        const duplicate = duplicateItem(record, existing, {
          reason: "duplicate-content",
          url: record.url,
          keptUrl: existing.url,
          sha256: hashResult.sha256,
          bytes: hashResult.bytes,
        });
        collection.duplicateContentItems.push(duplicate);
        collection.removedRecords.push(record);
        if (options.verbose) {
          console.log(`  ${collection.name}: ${record.id} duplicates ${existing.id}`);
        }
        continue;
      }

      seenByHash.set(hashKey, record);
      kept.push(record);
    }

    collection.keptRecords = kept;
  }
}

function duplicateItem(record, keptRecord, details) {
  return {
    id: record.id,
    name: record.name,
    keptId: keptRecord.id,
    keptName: keptRecord.name,
    ...details,
  };
}

async function writeUpdatedBundle(context) {
  for (const collection of context.collections) {
    const newPayload = rebuildTokenPayload(collection);
    const nextText = `${JSON.stringify(newPayload)}\n`;
    const previousText = await fs.readFile(collection.tokenPath, "utf8");
    if (nextText !== previousText) {
      await fs.writeFile(collection.tokenPath, nextText);
    }
  }

  const updatedItems = context.items.map((item) => {
    const collection = context.collections.find((candidate) => suggestedItemId(item) === candidate.collectionId);
    if (!collection) {
      return item;
    }
    return {
      ...item,
      tokenCount: collection.keptRecords.length,
    };
  });

  await fs.writeFile(context.itemsPath, formatSuggestedItems(updatedItems));
}

function rebuildTokenPayload(collection) {
  const payload = collection.tokenPayload;
  const rowsAreCompact = collection.records.every((record) => record.rowKind === "compact");
  const nextPayload = {
    ...payload,
    items: rowsAreCompact
      ? compactRows(collection.keptRecords)
      : collection.keptRecords.map((record) => record.row),
  };

  if (rowsAreCompact) {
    const urls = collection.keptRecords.map((record) => record.url).filter(Boolean);
    const prefixes = buildUrlPrefixes(urls);
    const defaultFileExtension = mostCommonValue(
      collection.keptRecords.map((record) => record.fileExtension).filter(Boolean)
    ) ?? normalizeExtension(payload.defaultFileExtension);

    nextPayload.defaultFileExtension = defaultFileExtension;
    nextPayload.urlPrefixes = prefixes;
    nextPayload.items = collection.keptRecords.map((record) => {
      const prefixIndex = bestPrefixIndex(record.url, prefixes);
      const suffix = record.url.slice(prefixes[prefixIndex].length);
      const row = [record.id, prefixIndex, suffix];
      if (record.fileExtension && record.fileExtension !== defaultFileExtension) {
        row.push(record.fileExtension);
      }
      return row;
    });
  }

  if (nextPayload._tezosBundler?.tokenCount != null) {
    nextPayload._tezosBundler = {
      ...nextPayload._tezosBundler,
      tokenCount: collection.keptRecords.length,
    };
  }

  delete nextPayload._deepDedup;
  return nextPayload;
}

function compactRows(records) {
  return records.map((record) => record.row);
}

function buildUrlPrefixes(urls) {
  const groups = new Map();
  for (const url of urls) {
    const prefix = urlPrefixForCompression(url);
    groups.set(prefix, (groups.get(prefix) ?? 0) + 1);
  }

  return [...groups.entries()]
    .sort((left, right) => right[1] - left[1] || right[0].length - left[0].length || naturalCompare(left[0], right[0]))
    .map(([prefix]) => prefix);
}

function urlPrefixForCompression(urlString) {
  try {
    const url = new URL(urlString);
    const slashIndex = url.pathname.lastIndexOf("/");
    url.pathname = slashIndex >= 0 ? url.pathname.slice(0, slashIndex + 1) : url.pathname;
    url.search = "";
    url.hash = "";
    return url.toString();
  } catch {
    const slashIndex = urlString.lastIndexOf("/");
    return slashIndex >= 0 ? urlString.slice(0, slashIndex + 1) : "";
  }
}

function bestPrefixIndex(url, prefixes) {
  let bestIndex = -1;
  for (let index = 0; index < prefixes.length; index += 1) {
    if (url.startsWith(prefixes[index]) && (bestIndex === -1 || prefixes[index].length > prefixes[bestIndex].length)) {
      bestIndex = index;
    }
  }
  return bestIndex === -1 ? 0 : bestIndex;
}

function formatSuggestedItems(items) {
  return `${JSON.stringify(items, null, 2).replace(/"([^"]+)":/gu, "\"$1\" :")}\n`;
}

async function writeReports(collections, options) {
  await fs.mkdir(path.dirname(options.reportPath), { recursive: true });
  await fs.mkdir(path.dirname(options.jsonReportPath), { recursive: true });
  await fs.writeFile(options.reportPath, buildMarkdownReport(collections, options));
  await fs.writeFile(options.jsonReportPath, `${JSON.stringify({
    generatedAt: new Date().toISOString(),
    mode: options.apply ? "apply" : "dry-run",
    collections: collections.map(reportableCollection),
  }, null, 2)}\n`);
}

function buildMarkdownReport(collections, options) {
  const lines = [
    "# Deep Dedup Bundled Collections Report",
    "",
    `Generated: ${new Date().toISOString()}`,
    `Mode: ${options.apply ? "apply" : "dry-run"}`,
    "",
    "## Collections",
    "",
    "| Collection | ID | Original | Removed URL Dups | Removed Content Dups | Final | Hash Failures |",
    "| --- | --- | ---: | ---: | ---: | ---: | ---: |",
  ];

  for (const collection of collections) {
    lines.push(`| ${escapeMarkdownTable(collection.name)} | ${collection.collectionId} | ${collection.originalTokenCount} | ${collection.duplicateUrlItems.length} | ${collection.duplicateContentItems.length} | ${collection.keptRecords.length} | ${collection.failedHashItems.length} |`);
  }

  const collectionsWithDuplicates = collections.filter((collection) =>
    collection.duplicateUrlItems.length > 0
    || collection.duplicateContentItems.length > 0
    || collection.failedHashItems.length > 0
  );

  lines.push("", "## Details", "");
  if (collectionsWithDuplicates.length === 0) {
    lines.push("No duplicates or hash failures found.");
  }

  for (const collection of collectionsWithDuplicates) {
    lines.push(`### ${escapeMarkdown(collection.name)} (${collection.collectionId})`, "");
    appendDuplicateItems(lines, "Duplicate URLs removed", collection.duplicateUrlItems);
    appendDuplicateItems(lines, "Duplicate file bytes removed", collection.duplicateContentItems);
    appendHashFailures(lines, collection.failedHashItems);
    lines.push("");
  }

  return `${lines.join("\n")}\n`;
}

function appendDuplicateItems(lines, title, items) {
  if (items.length === 0) {
    return;
  }
  lines.push(`#### ${title}`, "");
  for (const item of items) {
    const hashText = item.sha256 ? ` sha256=${item.sha256} bytes=${item.bytes}` : "";
    const keptUrlText = item.keptUrl ? ` keptUrl=${item.keptUrl}` : "";
    lines.push(`- ${item.id}${item.name ? ` (${escapeMarkdown(item.name)})` : ""} duplicates ${item.keptId}${item.keptName ? ` (${escapeMarkdown(item.keptName)})` : ""}: ${item.url}${keptUrlText}${hashText}`);
  }
  lines.push("");
}

function appendHashFailures(lines, items) {
  if (items.length === 0) {
    return;
  }
  lines.push("#### Hash failures kept", "");
  for (const item of items) {
    lines.push(`- ${item.id}${item.name ? ` (${escapeMarkdown(item.name)})` : ""}: ${item.error} - ${item.url}`);
  }
  lines.push("");
}

function reportableCollection(collection) {
  return {
    collectionId: collection.collectionId,
    name: collection.name,
    originalTokenCount: collection.originalTokenCount,
    tokenCount: collection.keptRecords.length,
    removedTokenCount: collection.removedRecords.length,
    duplicateUrlItems: collection.duplicateUrlItems,
    duplicateContentItems: collection.duplicateContentItems,
    failedHashItems: collection.failedHashItems,
  };
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
    return normalizeExtension(path.posix.extname(url.pathname));
  } catch {
    const match = /\.([a-z0-9]+)(?:[?#]|$)/iu.exec(urlString);
    return normalizeExtension(match?.[1]);
  }
}

function normalizeExtension(value) {
  if (!value) {
    return null;
  }
  const normalized = String(value).trim().replace(/^\./u, "").toLowerCase();
  if (!normalized) {
    return null;
  }
  return normalized === "jpe" ? "jpg" : normalized;
}

function mostCommonValue(values) {
  const counts = new Map();
  for (const value of values) {
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  return [...counts.entries()].sort((left, right) => right[1] - left[1] || naturalCompare(left[0], right[0]))[0]?.[0] ?? null;
}

function naturalCompare(left, right) {
  return String(left).localeCompare(String(right), undefined, { numeric: true, sensitivity: "base" });
}

function uniqueStrings(values) {
  const seen = new Set();
  const unique = [];
  for (const value of values) {
    if (seen.has(value)) {
      continue;
    }
    seen.add(value);
    unique.push(value);
  }
  return unique;
}

function isTransientDownloadError(error) {
  return error?.name === "AbortError"
    || TRANSIENT_HTTP_STATUSES.has(error?.status)
    || ["ECONNRESET", "ETIMEDOUT", "ENOTFOUND", "EAI_AGAIN", "UND_ERR_CONNECT_TIMEOUT", "UND_ERR_HEADERS_TIMEOUT"].includes(error?.code)
    || /fetch failed|network|timeout/iu.test(error?.message ?? "");
}

function retryDelayMs(attempt) {
  const exponential = Math.min(60000, 1000 * (2 ** Math.min(attempt, 6)));
  return exponential + Math.floor(Math.random() * 400);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function escapeMarkdown(value) {
  return String(value).replace(/([\\`*_{}[\]()#+\-.!|])/gu, "\\$1");
}

function escapeMarkdownTable(value) {
  return escapeMarkdown(value).replace(/\n/gu, " ");
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
