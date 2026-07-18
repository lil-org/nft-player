#!/usr/bin/env node

const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const {
  assertCoverCatalogIsAssetCatalogCompatible,
  assertUniqueCoverAssetIds,
  convertCover,
  coverAssetIdForCollection,
  resolveCoverTools,
  writeCoverContents,
  writePlaceholderCover,
} = require("./cover_images");
const { assignInternalSlugs, mergeGeneratedSuggestedItem } = require("./suggested_items");
const {
  preserveAspectRatioMetadataFromFile,
  reportAspectRatioMetadataChanges,
} = require("./thumbnail_aspect_ratios");
const { preserveTmpFilesFromFile, reportTmpFilesChanges } = require("./tmp_files");

const DEFAULT_BUNDLE_PATH = path.join("Suggested Items", "Suggested.bundle");
const DEFAULT_COVERS_PATH = path.join("Suggested Items", "Covers.xcassets");
const DEFAULT_REPORT_PATH = path.join("tools", "reports", "solana-collection-bundle-report.md");
const DEFAULT_JSON_REPORT_PATH = path.join("tools", "reports", "solana-collection-bundle-report.json");
const DEFAULT_API_KEY_PATH = path.join(os.homedir(), "Developer", "secrets", "tools", "HELIUS_API_KEY");
const DEFAULT_MAX_TOKENS = 15000;
const HELIUS_MAINNET_URL = "https://mainnet.helius-rpc.com/";
const SUPPORTED_EXTENSIONS = new Set(["png", "jpg", "jpeg", "webp", "heic", "heif", "gif", "mp4", "mov"]);
const STATIC_EXTENSIONS = new Set(["png", "jpg", "jpeg", "webp", "heic", "heif"]);
const ANIMATED_EXTENSIONS = new Set(["gif"]);
const VIDEO_EXTENSIONS = new Set(["mp4", "mov"]);
const TRANSIENT_HTTP_STATUSES = new Set([408, 425, 429, 500, 502, 503, 504]);
const TRANSIENT_RPC_CODES = new Set([-32005, -32603]);
const EXTENSION_BY_MIME = new Map([
  ["image/png", "png"],
  ["image/jpeg", "jpg"],
  ["image/jpg", "jpg"],
  ["image/webp", "webp"],
  ["image/heic", "heic"],
  ["image/heif", "heif"],
  ["image/gif", "gif"],
  ["video/mp4", "mp4"],
  ["video/quicktime", "mov"],
  ["video/x-quicktime", "mov"],
  ["video/webm", "webm"],
]);
const NATIVE_RENDERER_COLLECTION_IDS = new Set([
  "EAzEpagtyeRAx9npnpVMpygoA8ouX7DRpLTghhPvYTiu", // Card NFT 2
  "JCTP3kK3xGtWs5mDHxJBuRro38HftaiCDdKsfkXuK2gH", // Poncho Drifella
]);

const CANONICAL_COLLECTION_IDS = new Map([
  ["GCrHWAXj2dSyHtevh98HBvVFc3BcAJb9DK4skJTMWBEL", "GVQ4Zsd7jLZbVCxq9QsmQySuKekwT1XbMSjGbwt8UtcB"],
  ["2cTY8zjJyaEtLfWec948gkzEmZ66qPcfLv4UpdHXXwgR", "F2nMPDhNSoSDdCVjENSvbxqTvF7e5BV4YsfYNMGv2rqM"],
  ["3VwhE71zNXo5cjbrd3NpW8uZeQKn2mLDne9viKNMc51z", "2W68ofaUBEQYoFUwEWWHoYq8MBauPbxhZtv71vqZsyhp"],
]);

function usage() {
  return `
Usage:
  node tools/bundle_solana_collections.js [options] <collection-or-token>...
  node tools/bundle_solana_collections.js --input collections.txt --apply

Options:
  --input <path>          File containing one collection/token address per line.
  --apply                 Write token JSON, items.json, covers, and reports.
  --dry-run               Fetch and validate without writing bundle assets. Default.
  --bundle <path>         Suggested.bundle path. Default: ${DEFAULT_BUNDLE_PATH}
  --covers <path>         Covers.xcassets path. Default: ${DEFAULT_COVERS_PATH}
  --report <path>         Markdown report path. Default: ${DEFAULT_REPORT_PATH}
  --json-report <path>    JSON report path. Default: ${DEFAULT_JSON_REPORT_PATH}
  --api-key <key>         Helius API key. Defaults to HELIUS_API_KEY env or ${DEFAULT_API_KEY_PATH}
  --delay-ms <number>     Delay between Helius calls. Default: 650
  --limit <number>        Helius page size. Default: 1000
  --timeout-ms <number>   Request timeout. Default: 30000
  --max-tokens <number>   Maximum Helius assets to bundle per collection. Default: ${DEFAULT_MAX_TOKENS}
  --cover-size <number>   Cover width/height in pixels. Default: 300
  --cover-quality <n>     JPEG quality passed to ImageMagick. Default: 85
  --max-retries <n|forever>
                           Transient retry limit per request. Default: forever
  --skip-covers           Do not download or generate cover images.
  --verbose               Print per-page and media diagnostics.
  --help                  Show this help.
`.trim();
}

function parseArgs(argv) {
  const options = {
    inputs: [],
    inputFile: null,
    apply: false,
    bundlePath: DEFAULT_BUNDLE_PATH,
    coversPath: DEFAULT_COVERS_PATH,
    reportPath: DEFAULT_REPORT_PATH,
    jsonReportPath: DEFAULT_JSON_REPORT_PATH,
    apiKey: process.env.HELIUS_API_KEY ?? null,
    delayMs: 650,
    limit: 1000,
    timeoutMs: 30000,
    maxTokens: DEFAULT_MAX_TOKENS,
    coverSize: 300,
    coverQuality: 85,
    maxRetries: Number.POSITIVE_INFINITY,
    skipCovers: false,
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
      case "--input":
        options.inputFile = readValue();
        break;
      case "--apply":
        options.apply = true;
        break;
      case "--dry-run":
        options.apply = false;
        break;
      case "--bundle":
        options.bundlePath = readValue();
        break;
      case "--covers":
        options.coversPath = readValue();
        break;
      case "--report":
        options.reportPath = readValue();
        break;
      case "--json-report":
        options.jsonReportPath = readValue();
        break;
      case "--api-key":
        options.apiKey = readValue();
        break;
      case "--delay-ms":
        options.delayMs = nonNegativeInteger(readValue(), arg);
        break;
      case "--limit":
        options.limit = boundedInteger(readValue(), arg, 1, 1000);
        break;
      case "--timeout-ms":
        options.timeoutMs = positiveInteger(readValue(), arg);
        break;
      case "--max-tokens":
        options.maxTokens = positiveInteger(readValue(), arg);
        break;
      case "--cover-size":
        options.coverSize = positiveInteger(readValue(), arg);
        break;
      case "--cover-quality":
        options.coverQuality = boundedInteger(readValue(), arg, 1, 100);
        break;
      case "--max-retries": {
        const value = readValue();
        options.maxRetries = value === "forever" ? Number.POSITIVE_INFINITY : nonNegativeInteger(value, arg);
        break;
      }
      case "--skip-covers":
        options.skipCovers = true;
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
        options.inputs.push(arg);
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

function boundedInteger(value, optionName, minimum, maximum) {
  const number = Number(value);
  if (!Number.isInteger(number) || number < minimum || number > maximum) {
    throw new Error(`${optionName} must be an integer from ${minimum} to ${maximum}`);
  }
  return number;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const apiKey = await readApiKey(options);
  const inputs = await readInputs(options);
  if (inputs.length === 0) {
    throw new Error("No collection addresses provided. Pass addresses or use --input.");
  }

  const context = {
    options,
    apiKey,
    lastHeliusCallAt: 0,
    tempRoot: path.join(os.tmpdir(), `solana-collection-bundler-${process.pid}`),
  };

  await fs.mkdir(context.tempRoot, { recursive: true });
  const collectionResults = [];
  const seenCanonicalIds = new Set();

  for (const input of inputs) {
    const canonicalId = CANONICAL_COLLECTION_IDS.get(input) ?? input;
    if (seenCanonicalIds.has(canonicalId)) {
      console.log(`Skipping duplicate ${input} -> ${canonicalId}`);
      continue;
    }
    seenCanonicalIds.add(canonicalId);

    console.log(`Fetching ${input}${input === canonicalId ? "" : ` -> ${canonicalId}`}`);
    const result = await fetchCollectionBundle(input, canonicalId, context);
    collectionResults.push(result);
    console.log(`  ${result.name}: ${result.tokens.length} tokens, ${result.tokenPayload.urlPrefixes.length} URL prefix(es)`);
  }

  if (!options.skipCovers) {
    assertUniqueCoverAssetIds(collectionResults);
  }

  const report = buildReport(collectionResults, options);
  const jsonReport = {
    generatedAt: new Date().toISOString(),
    dryRun: !options.apply,
    inputs,
    collections: collectionResults.map((collection) => reportableCollection(collection)),
  };

  if (options.apply) {
    await writeBundle(collectionResults, context);
  } else {
    await fs.mkdir(path.dirname(options.reportPath), { recursive: true });
    await fs.writeFile(options.reportPath, report);
    await fs.writeFile(options.jsonReportPath, `${JSON.stringify(jsonReport, null, 2)}\n`);
    console.log("Dry run complete. Reports were written; bundle assets were not changed.");
  }

  const decisionCount = collectionResults.reduce(
    (count, collection) =>
      count
        + collection.mediaReview.decisionItems.length
        + collection.mediaReview.duplicateFileURLItems.length
        + collection.mediaReview.unsupportedItems.length
        + collection.mediaReview.missingMediaItems.length,
    0,
  );
  if (decisionCount > 0) {
    console.log(`${decisionCount} media item(s) need review. See ${options.reportPath}`);
  }
}

async function readApiKey(options) {
  if (options.apiKey) {
    return options.apiKey.trim();
  }

  try {
    return (await fs.readFile(DEFAULT_API_KEY_PATH, "utf8")).trim();
  } catch (error) {
    throw new Error(`Missing Helius API key. Set HELIUS_API_KEY or create ${DEFAULT_API_KEY_PATH}`);
  }
}

async function readInputs(options) {
  const values = [...options.inputs];
  if (options.inputFile) {
    const text = await fs.readFile(options.inputFile, "utf8");
    values.push(...text.split(/\r?\n/u));
  }

  const seen = new Set();
  return values
    .map((value) => value.trim())
    .filter((value) => value && !value.startsWith("#"))
    .filter((value) => {
      if (seen.has(value)) {
        return false;
      }
      seen.add(value);
      return true;
    });
}

async function fetchCollectionBundle(input, canonicalId, context) {
  let collectionId = canonicalId;
  assertNotNativeRendererCollection(collectionId);
  let firstPage = await getAssetsByGroup(collectionId, 1, context, { includeGrandTotal: true });
  let resolvedFromToken = input === collectionId
    ? null
    : {
        tokenId: input,
        tokenName: null,
        collectionId,
        source: "canonical-map",
      };

  if (firstPage.items.length === 0) {
    const asset = await getAsset(input, context);
    const grouping = verifiedCollectionGrouping(asset);
    if (!grouping) {
      throw new Error(`No assets found for ${input}, and getAsset did not expose a verified collection grouping.`);
    }
    collectionId = grouping.group_value;
    assertNotNativeRendererCollection(collectionId);
    resolvedFromToken = {
      tokenId: input,
      tokenName: asset.content?.metadata?.name ?? null,
      collectionId,
      source: "getAsset-grouping",
    };
    firstPage = await getAssetsByGroup(collectionId, 1, context, { includeGrandTotal: true });
    if (firstPage.items.length === 0) {
      throw new Error(`Resolved ${input} to ${collectionId}, but that collection returned no assets.`);
    }
  }
  assertCollectionWithinTokenLimit({
    collectionId,
    count: firstPage.total,
    source: "reported supply",
    options: context.options,
  });

  const pages = [firstPage];
  let page = 2;
  while (pages[pages.length - 1].items.length === context.options.limit) {
    const nextPage = await getAssetsByGroup(collectionId, page, context, { includeGrandTotal: false });
    pages.push(nextPage);
    assertCollectionWithinTokenLimit({
      collectionId,
      count: pages.reduce((count, pageResult) => count + pageResult.items.length, 0),
      source: "fetched asset count",
      options: context.options,
    });
    page += 1;
  }

  const assets = pages.flatMap((pageResult) => pageResult.items).filter((asset) => asset && !asset.burnt);
  const collectionMetadata = collectionMetadataFromAssets(assets, collectionId);
  const name = collectionMetadata?.name || fallbackCollectionName(assets, collectionId);
  const preparedTokens = prepareTokens(assets, collectionId, context.options);
  if (preparedTokens.tokens.length === 0) {
    throw new Error(`No app-supported image, GIF, or MP4 media found for ${collectionId} (${name}).`);
  }

  const tokenPayload = buildTokenPayload(preparedTokens.tokens, {
    input,
    collectionId,
    name,
    resolvedFromToken,
    totalFromHelius: firstPage.total ?? null,
    assetsSeen: assets.length,
    duplicateFileURLItems: preparedTokens.mediaReview.duplicateFileURLItems,
    unsupportedMedia: preparedTokens.mediaReview.unsupportedItems,
    mediaDecisionItems: preparedTokens.mediaReview.decisionItems,
    missingMediaItems: preparedTokens.mediaReview.missingMediaItems,
  });

  const tokenCoverUrls = preparedTokens.tokens.flatMap((token) => token.coverUrls);
  return {
    input,
    collectionId,
    name,
    tokenCount: preparedTokens.tokens.length,
    totalFromHelius: firstPage.total ?? null,
    resolvedFromToken,
    collectionMetadata,
    assetsSeen: assets.length,
    tokens: preparedTokens.tokens,
    tokenPayload,
    mediaReview: preparedTokens.mediaReview,
    cover: {
      assetId: collectionId,
      sourceUrl: normalizeAssetUrl(collectionMetadata?.image)
        ?? tokenCoverUrls[0]
        ?? firstImageMediaURL(preparedTokens.tokens)
        ?? null,
      fallbackSourceUrl: tokenCoverUrls[0] ?? firstImageMediaURL(preparedTokens.tokens) ?? null,
      fallbackSourceUrls: uniqueStrings([
        ...tokenCoverUrls,
        ...sampleTokens(preparedTokens.tokens, 40).map((token) => token.media.url),
      ]),
      sourceKind: collectionMetadata?.image ? "collection-metadata" : "first-token",
      outputPath: path.join(context.options.coversPath, `${collectionId}.imageset`, `${collectionId}.jpg`),
    },
  };
}

function assertNotNativeRendererCollection(collectionId) {
  if (NATIVE_RENDERER_COLLECTION_IDS.has(collectionId)) {
    throw new Error(`${collectionId} uses a curated native cdn.lil.org renderer and must not be rebuilt from Helius assets.`);
  }
}

function assertCollectionWithinTokenLimit({ collectionId, count, source, options }) {
  const tokenCount = numericTokenCount(count);
  if (tokenCount != null && tokenCount > options.maxTokens) {
    throw new Error(`${collectionId} has ${tokenCount} asset(s) by ${source}, exceeding --max-tokens ${options.maxTokens}. Refusing to bundle a likely shared collection.`);
  }
}

function numericTokenCount(value) {
  if (value == null || value === "") {
    return null;
  }
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

async function getAssetsByGroup(collectionId, page, context, requestOptions) {
  const params = {
    groupKey: "collection",
    groupValue: collectionId,
    page,
    limit: context.options.limit,
    options: {
      showCollectionMetadata: true,
      showUnverifiedCollections: true,
      showGrandTotal: requestOptions.includeGrandTotal,
    },
  };

  const response = await heliusRpc("getAssetsByGroup", params, context);
  if (context.options.verbose) {
    console.log(`  page ${page}: ${response.items?.length ?? 0}/${response.total ?? "?"}`);
  }
  return {
    total: response.total,
    page: response.page,
    limit: response.limit,
    items: response.items ?? [],
  };
}

async function getAsset(id, context) {
  return heliusRpc("getAsset", {
    id,
    options: {
      showCollectionMetadata: true,
      showUnverifiedCollections: true,
    },
  }, context);
}

async function heliusRpc(method, params, context) {
  const url = `${HELIUS_MAINNET_URL}?api-key=${encodeURIComponent(context.apiKey)}`;
  const body = JSON.stringify({
    jsonrpc: "2.0",
    id: `${method}-${Date.now()}`,
    method,
    params,
  });

  for (let attempt = 0; ; attempt += 1) {
    await waitForHeliusSlot(context);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), context.options.timeoutMs);

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body,
        signal: controller.signal,
      });
      clearTimeout(timeout);

      if (!response.ok) {
        const responseText = await safeResponseText(response);
        if (shouldRetryHttp(response.status, attempt, context.options)) {
          await sleep(retryDelayMs(attempt, response.headers.get("retry-after")));
          continue;
        }
        throw new Error(`Helius HTTP ${response.status} for ${method}: ${responseText}`);
      }

      const payload = await response.json();
      if (payload.error) {
        if (shouldRetryRpc(payload.error, attempt, context.options)) {
          await sleep(retryDelayMs(attempt));
          continue;
        }
        throw new Error(`Helius RPC ${payload.error.code} for ${method}: ${payload.error.message}`);
      }
      return payload.result;
    } catch (error) {
      clearTimeout(timeout);
      if (shouldRetryError(error, attempt, context.options)) {
        await sleep(retryDelayMs(attempt));
        continue;
      }
      throw error;
    }
  }
}

async function waitForHeliusSlot(context) {
  const elapsed = Date.now() - context.lastHeliusCallAt;
  if (elapsed < context.options.delayMs) {
    await sleep(context.options.delayMs - elapsed);
  }
  context.lastHeliusCallAt = Date.now();
}

function shouldRetryHttp(status, attempt, options) {
  return TRANSIENT_HTTP_STATUSES.has(status) && attempt < options.maxRetries;
}

function shouldRetryRpc(error, attempt, options) {
  return TRANSIENT_RPC_CODES.has(error?.code) && attempt < options.maxRetries;
}

function shouldRetryError(error, attempt, options) {
  if (attempt >= options.maxRetries) {
    return false;
  }
  return error?.name === "AbortError"
    || ["ECONNRESET", "ETIMEDOUT", "ENOTFOUND", "EAI_AGAIN", "UND_ERR_CONNECT_TIMEOUT", "UND_ERR_HEADERS_TIMEOUT"].includes(error?.code)
    || /fetch failed|network|timeout/i.test(error?.message ?? "");
}

async function safeResponseText(response) {
  try {
    return await response.text();
  } catch {
    return "<unreadable response>";
  }
}

function retryDelayMs(attempt, retryAfterHeader = null) {
  const retryAfter = retryAfterMs(retryAfterHeader);
  if (retryAfter != null) {
    return retryAfter;
  }
  const exponential = Math.min(60000, 1000 * (2 ** Math.min(attempt, 6)));
  return exponential + Math.floor(Math.random() * 400);
}

function retryAfterMs(value) {
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

function verifiedCollectionGrouping(asset) {
  const grouping = asset?.grouping ?? [];
  return grouping.find((entry) => entry.group_key === "collection" && entry.verified)
    ?? grouping.find((entry) => entry.group_key === "collection");
}

function collectionMetadataFromAssets(assets, collectionId) {
  for (const asset of assets) {
    for (const grouping of asset.grouping ?? []) {
      if (grouping.group_key === "collection" && grouping.group_value === collectionId && grouping.collection_metadata) {
        return grouping.collection_metadata;
      }
    }
  }
  return null;
}

function fallbackCollectionName(assets, collectionId) {
  for (const asset of assets) {
    const symbol = asset.content?.metadata?.symbol;
    if (symbol) {
      return symbol;
    }
  }
  return collectionId;
}

function prepareTokens(assets, collectionId, options) {
  const selectedTokens = [];
  const tokens = [];
  const seenMediaURLs = new Map();
  const decisionItems = [];
  const duplicateFileURLItems = [];
  const unsupportedItems = [];
  const missingMediaItems = [];

  for (const asset of assets) {
    const candidates = mediaCandidatesForAsset(asset);
    const supportedCandidates = candidates.filter((candidate) => SUPPORTED_EXTENSIONS.has(candidate.extension));
    const selected = choosePreferredCandidate(supportedCandidates);

    if (!selected) {
      if (candidates.length > 0) {
        unsupportedItems.push({
          id: asset.id,
          name: asset.content?.metadata?.name ?? "",
          candidates: candidates.map(reportableCandidate),
        });
      } else {
        missingMediaItems.push({
          id: asset.id,
          name: asset.content?.metadata?.name ?? "",
        });
      }
      continue;
    }

    const distinctSupported = uniqueCandidates(supportedCandidates);
    const alternates = distinctSupported
      .filter((candidate) => candidate.url !== selected.url || candidate.extension !== selected.extension)
      .map(reportableCandidate);

    const reviewItem = alternates.length > 0 || candidates.some((candidate) => !SUPPORTED_EXTENSIONS.has(candidate.extension))
      ? {
        id: asset.id,
        name: asset.content?.metadata?.name ?? "",
        selected: reportableCandidate(selected),
        alternates,
        unsupported: candidates
          .filter((candidate) => !SUPPORTED_EXTENSIONS.has(candidate.extension))
          .map(reportableCandidate),
      }
      : null;

    selectedTokens.push({
      id: asset.id,
      name: asset.content?.metadata?.name ?? "",
      media: selected,
      coverUrls: coverCandidatesForAsset(asset),
      reviewItem,
      sortKey: sortKeyForAsset(asset, selected),
    });
  }

  selectedTokens.sort(comparePreparedTokens);

  for (const token of selectedTokens) {
    const existing = seenMediaURLs.get(token.media.url);
    if (existing) {
      duplicateFileURLItems.push({
        id: token.id,
        name: token.name,
        keptId: existing.id,
        keptName: existing.name,
        url: token.media.url,
      });
      continue;
    }

    seenMediaURLs.set(token.media.url, {
      id: token.id,
      name: token.name,
    });

    if (token.reviewItem) {
      decisionItems.push(token.reviewItem);
    }
    delete token.reviewItem;
    tokens.push(token);
  }

  if (options.verbose && (duplicateFileURLItems.length > 0 || unsupportedItems.length > 0 || missingMediaItems.length > 0)) {
    console.log(`  ${collectionId}: skipped ${duplicateFileURLItems.length} duplicate, ${unsupportedItems.length} unsupported, and ${missingMediaItems.length} missing-media token(s)`);
  }

  return {
    tokens,
    mediaReview: {
      decisionItems,
      duplicateFileURLItems,
      unsupportedItems,
      missingMediaItems,
    },
  };
}

function mediaCandidatesForAsset(asset) {
  const candidates = [];
  for (const file of asset.content?.files ?? []) {
    appendCandidate(candidates, {
      url: file.uri,
      cdnUrl: file.cdn_uri,
      mime: file.mime,
      source: "content.files.uri",
    });
  }

  appendCandidate(candidates, {
    url: asset.content?.links?.image,
    mime: null,
    source: "content.links.image",
  });

  appendCandidate(candidates, {
    url: asset.content?.links?.animation_url,
    mime: null,
    source: "content.links.animation_url",
  });

  return uniqueCandidates(candidates);
}

function coverCandidatesForAsset(asset) {
  const candidates = [];
  const imageExtensions = new Set([...STATIC_EXTENSIONS, ...ANIMATED_EXTENSIONS]);

  for (const candidate of mediaCandidatesForAsset(asset)) {
    if (imageExtensions.has(candidate.extension) && !VIDEO_EXTENSIONS.has(candidate.extension)) {
      candidates.push(candidate.url);
    }
  }

  const imageUrl = normalizeAssetUrl(asset.content?.links?.image);
  if (imageUrl) {
    candidates.push(imageUrl);
  }

  return uniqueStrings(candidates);
}

function appendCandidate(candidates, candidate) {
  const normalizedUrl = normalizeAssetUrl(candidate.url);
  if (!normalizedUrl) {
    return;
  }
  const extension = fileExtensionForURL(normalizedUrl, candidate.mime);
  if (!extension) {
    candidates.push({
      ...candidate,
      url: normalizedUrl,
      extension: "unknown",
    });
    return;
  }
  candidates.push({
    ...candidate,
    url: normalizedUrl,
    extension,
  });
}

function uniqueCandidates(candidates) {
  const unique = [];
  const indexByURL = new Map();

  for (const candidate of candidates) {
    const existingIndex = indexByURL.get(candidate.url);
    if (existingIndex == null) {
      indexByURL.set(candidate.url, unique.length);
      unique.push(candidate);
      continue;
    }

    const existing = unique[existingIndex];
    if (existing.extension === "unknown" && candidate.extension !== "unknown") {
      unique[existingIndex] = {
        ...candidate,
        source: existing.source === candidate.source ? candidate.source : `${candidate.source}+${existing.source}`,
      };
    } else if (existing.cdnUrl == null && candidate.cdnUrl != null) {
      unique[existingIndex] = {
        ...existing,
        cdnUrl: candidate.cdnUrl,
      };
    }
  }
  return unique;
}

function choosePreferredCandidate(candidates) {
  if (candidates.length === 0) {
    return null;
  }

  const ranked = [...candidates].sort((left, right) => candidateRank(left) - candidateRank(right));
  return ranked[0];
}

function candidateRank(candidate) {
  let rank = 0;
  if (candidate.source === "content.files.uri") {
    rank -= 30;
  }
  if (candidate.source === "content.links.image") {
    rank -= 10;
  }
  if (VIDEO_EXTENSIONS.has(candidate.extension)) {
    rank -= 100;
  }
  if (ANIMATED_EXTENSIONS.has(candidate.extension)) {
    rank -= 90;
  }
  if (STATIC_EXTENSIONS.has(candidate.extension)) {
    rank -= 5;
  }
  if (candidate.url.includes("cdn.helius-rpc.com")) {
    rank += 15;
  }
  return rank;
}

function normalizeAssetUrl(urlString) {
  if (!urlString || typeof urlString !== "string") {
    return null;
  }
  const trimmed = urlString.trim();
  if (!trimmed) {
    return null;
  }
  if (trimmed.startsWith("ipfs://")) {
    return `https://ipfs.decentralized-content.com/ipfs/${trimmed.slice("ipfs://".length).replace(/^ipfs\//u, "")}`;
  }
  if (trimmed.startsWith("ar://")) {
    return `https://arweave.net/${trimmed.slice("ar://".length)}`;
  }
  if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
    return trimmed;
  }
  return null;
}

function fileExtensionForURL(urlString, mime) {
  const mimeExtension = mime ? EXTENSION_BY_MIME.get(mime.toLowerCase().split(";")[0].trim()) : null;
  const urlExtension = extensionFromURL(urlString);
  return normalizeExtension(urlExtension) ?? normalizeExtension(mimeExtension);
}

function extensionFromURL(urlString) {
  try {
    const url = new URL(urlString);
    const extParam = url.searchParams.get("ext");
    if (extParam) {
      return extParam;
    }
    const basename = path.posix.basename(url.pathname);
    const match = /\.([a-z0-9]+)$/iu.exec(basename);
    return match?.[1] ?? null;
  } catch {
    const queryMatch = /[?&]ext=([a-z0-9]+)/iu.exec(urlString);
    if (queryMatch) {
      return queryMatch[1];
    }
    const pathMatch = /\.([a-z0-9]+)(?:[?#]|$)/iu.exec(urlString);
    return pathMatch?.[1] ?? null;
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

function sortKeyForAsset(asset, selected) {
  const name = asset.content?.metadata?.name ?? "";
  const numericName = numericTokenIdFromName(name);
  const basename = urlLastPathComponent(selected.url);
  const numericBasename = numericTokenIdFromBasename(basename);
  return {
    numericName,
    numericBasename,
    basename,
    mint: asset.id,
  };
}

function numericTokenIdFromName(name) {
  const hashMatches = [...String(name).matchAll(/#\s*(\d+)/gu)];
  if (hashMatches.length > 0) {
    return Number(hashMatches[hashMatches.length - 1][1]);
  }
  const trailing = /(\d+)\s*$/u.exec(String(name));
  return trailing ? Number(trailing[1]) : null;
}

function numericTokenIdFromBasename(basename) {
  const numeric = /^0*(\d+)(?:\.[a-z0-9]+)?$/iu.exec(basename);
  return numeric ? Number(numeric[1]) : null;
}

function urlLastPathComponent(urlString) {
  try {
    const url = new URL(urlString);
    const basename = path.posix.basename(url.pathname);
    return basename || urlString;
  } catch {
    return path.posix.basename(urlString);
  }
}

function comparePreparedTokens(left, right) {
  return compareNullableNumbers(left.sortKey.numericName, right.sortKey.numericName)
    || compareNullableNumbers(left.sortKey.numericBasename, right.sortKey.numericBasename)
    || naturalCompare(left.sortKey.basename, right.sortKey.basename)
    || naturalCompare(left.id, right.id);
}

function compareNullableNumbers(left, right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return left - right;
}

function naturalCompare(left, right) {
  return String(left).localeCompare(String(right), undefined, { numeric: true, sensitivity: "base" });
}

function buildTokenPayload(tokens, metadata) {
  const urls = tokens.map((token) => token.media.url);
  const prefixes = buildUrlPrefixes(urls);
  const extensions = tokens.map((token) => token.media.extension);
  const defaultFileExtension = mostCommonValue(extensions);

  return {
    defaultFileExtension,
    urlPrefixes: prefixes,
    items: tokens.map((token) => {
      const prefixIndex = bestPrefixIndex(token.media.url, prefixes);
      const suffix = token.media.url.slice(prefixes[prefixIndex].length);
      const row = [token.id, prefixIndex, suffix];
      if (token.media.extension !== defaultFileExtension) {
        row.push(token.media.extension);
      }
      return row;
    }),
    _solanaBundler: {
      generatedAt: new Date().toISOString(),
      input: metadata.input,
      collectionId: metadata.collectionId,
      name: metadata.name,
      resolvedFromToken: metadata.resolvedFromToken,
      totalFromHelius: metadata.totalFromHelius,
      assetsSeen: metadata.assetsSeen,
      tokenCount: tokens.length,
      mediaReview: {
        decisionItems: metadata.mediaDecisionItems,
        duplicateFileURLItemCount: metadata.duplicateFileURLItems.length,
        unsupportedItems: metadata.unsupportedMedia,
        missingMediaItems: metadata.missingMediaItems,
      },
    },
  };
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
    const pathname = url.pathname;
    const slashIndex = pathname.lastIndexOf("/");
    const pathPrefix = slashIndex >= 0 ? pathname.slice(0, slashIndex + 1) : pathname;
    url.pathname = pathPrefix;
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

function mostCommonValue(values) {
  const counts = new Map();
  for (const value of values) {
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  return [...counts.entries()].sort((left, right) => right[1] - left[1] || naturalCompare(left[0], right[0]))[0]?.[0] ?? null;
}

async function writeBundle(collections, context) {
  const { options } = context;
  const bundlePath = path.resolve(options.bundlePath);
  const tokensPath = path.join(bundlePath, "Tokens");
  const itemsPath = path.join(bundlePath, "items.json");
  if (!options.skipCovers) {
    assertUniqueCoverAssetIds(collections);
  }
  await fs.mkdir(tokensPath, { recursive: true });
  await fs.mkdir(path.dirname(options.reportPath), { recursive: true });

  const existingItems = JSON.parse(await fs.readFile(itemsPath, "utf8"));
  const updatedItems = assignInternalSlugs(mergeSuggestedItems(existingItems, collections));

  for (const collection of collections) {
    const outputPath = path.join(tokensPath, `${collection.collectionId}.json`);
    const tmpFilesResult = await preserveTmpFilesFromFile(outputPath, collection.tokenPayload);
    reportTmpFilesChanges(collection.collectionId, tmpFilesResult.report);
    const aspectRatioResult = await preserveAspectRatioMetadataFromFile(outputPath, tmpFilesResult.payload);
    reportAspectRatioMetadataChanges(collection.collectionId, aspectRatioResult.report);
    await fs.writeFile(outputPath, `${JSON.stringify(aspectRatioResult.payload)}\n`);
  }

  await fs.writeFile(itemsPath, formatSuggestedItems(updatedItems));

  if (!options.skipCovers) {
    await writeCovers(collections, context);
  }

  const report = buildReport(collections, options);
  const jsonReport = {
    generatedAt: new Date().toISOString(),
    dryRun: false,
    collections: collections.map((collection) => reportableCollection(collection)),
  };
  await fs.writeFile(options.reportPath, report);
  await fs.writeFile(options.jsonReportPath, `${JSON.stringify(jsonReport, null, 2)}\n`);
  console.log(`Wrote ${collections.length} collection bundle(s).`);
}

function mergeSuggestedItems(existingItems, collections) {
  const updatesById = new Map(collections.map((collection) => [
    collection.collectionId,
    {
      address: collection.collectionId,
      chain: "solana",
      chainId: 0,
      name: collection.name,
      tokenCount: collection.tokens.length,
    },
  ]));
  const existingIds = new Set();

  const updated = existingItems.map((item) => {
    if (item.chain === "solana" && updatesById.has(item.address)) {
      existingIds.add(item.address);
      return mergeGeneratedSuggestedItem(item, updatesById.get(item.address));
    }
    return item;
  });

  for (const collection of collections) {
    if (!existingIds.has(collection.collectionId)) {
      updated.push(updatesById.get(collection.collectionId));
    }
  }

  return updated;
}

function formatSuggestedItems(items) {
  return `${JSON.stringify(items, null, 2).replace(/"([^"]+)":/gu, "\"$1\" :")}\n`;
}

async function writeCovers(collections, context) {
  const coverTools = await resolveCoverTools();
  for (const collection of collections) {
    const coverAssetId = coverAssetIdForCollection(collection);
    const coverCandidates = uniqueCoverCandidates([
      {
        url: collection.cover.sourceUrl,
        kind: collection.cover.sourceKind,
      },
      {
        url: collection.cover.fallbackSourceUrl,
        kind: "first-token",
      },
      ...(collection.cover.fallbackSourceUrls ?? []).map((url) => ({
        url,
        kind: "sample-token",
      })),
    ]);

    if (coverCandidates.length === 0) {
      collection.cover.error = "No cover source URL";
      continue;
    }

    const imagesetPath = path.join(context.options.coversPath, `${coverAssetId}.imageset`);
    const outputPath = path.join(imagesetPath, `${coverAssetId}.jpg`);
    await fs.mkdir(imagesetPath, { recursive: true });

    let lastError = null;
    const reachableCandidates = await reachableCoverCandidates(coverCandidates, 2500, 8);
    for (let index = 0; index < reachableCandidates.length; index += 1) {
      const candidate = reachableCandidates[index];
      const tempPath = path.join(context.tempRoot, `${coverAssetId}-${index}${coverSourceExtension(candidate.url)}`);

      try {
        await downloadFileWithRetry(candidate.url, tempPath, context.options.timeoutMs);
        await convertCover(coverTools, tempPath, outputPath, context.options.coverSize, context.options.coverQuality);
        await writeCoverContents(imagesetPath, coverAssetId);
        collection.cover.assetId = coverAssetId;
        collection.cover.sourceUrl = candidate.url;
        collection.cover.sourceKind = candidate.kind;
        delete collection.cover.error;
        lastError = null;
        break;
      } catch (error) {
        lastError = error;
      }
    }

    if (reachableCandidates.length === 0) {
      lastError = new Error(`no reachable image cover candidates among ${coverCandidates.length} URL(s)`);
    }

    if (lastError) {
      collection.cover.error = lastError.message;
      try {
        await writePlaceholderCover(coverTools, outputPath, collection.name, context.options.coverSize, context.options.coverQuality, "Solana");
        await writeCoverContents(imagesetPath, coverAssetId);
        collection.cover.assetId = coverAssetId;
        collection.cover.sourceUrl = null;
        collection.cover.sourceKind = "generated-placeholder";
        console.error(`Cover placeholder used for ${coverAssetId}: ${lastError.message}`);
      } catch (placeholderError) {
        collection.cover.error = `${lastError.message}; placeholder failed: ${placeholderError.message}`;
        console.error(`Cover failed for ${coverAssetId}: ${collection.cover.error}`);
      }
    }
  }

  await assertCoverCatalogIsAssetCatalogCompatible(context.options.coversPath);
}

async function reachableCoverCandidates(candidates, timeoutMs, concurrency) {
  if (candidates.length === 0) {
    return [];
  }
  if (await isReachableImage(candidates[0].url, timeoutMs)) {
    return [candidates[0]];
  }

  const reachable = [];
  let cursor = 1;

  async function worker() {
    while (cursor < candidates.length) {
      const index = cursor;
      cursor += 1;
      const candidate = candidates[index];
      if (await isReachableImage(candidate.url, timeoutMs)) {
        reachable.push({ ...candidate, originalIndex: index });
      }
    }
  }

  await Promise.all(Array.from({ length: Math.min(concurrency, candidates.length) }, worker));
  return reachable.sort((left, right) => left.originalIndex - right.originalIndex);
}

async function isReachableImage(url, timeoutMs) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      headers: { Range: "bytes=0-0" },
      redirect: "follow",
      signal: controller.signal,
    });
    clearTimeout(timeout);
    await response.body?.cancel?.();
    return response.ok && /^image\//iu.test(response.headers.get("content-type") ?? "");
  } catch {
    clearTimeout(timeout);
    return false;
  }
}

function uniqueCoverCandidates(candidates) {
  const seen = new Set();
  const unique = [];
  for (const candidate of candidates) {
    for (const url of coverURLAlternates(candidate.url)) {
      if (!url || seen.has(url)) {
        continue;
      }
      seen.add(url);
      unique.push({
        ...candidate,
        url,
      });
    }
  }
  return unique;
}

function coverURLAlternates(urlString) {
  if (!urlString) {
    return [];
  }
  const alternates = [urlString];
  try {
    const url = new URL(urlString);
    const ipfsMatch = /\/ipfs\/(.+)$/u.exec(url.pathname);
    if (ipfsMatch && !url.hostname.includes("decentralized-content.com")) {
      const alternate = new URL(`https://ipfs.decentralized-content.com/ipfs/${ipfsMatch[1]}`);
      alternate.search = url.search;
      alternates.push(alternate.toString());
    }
  } catch {
    return alternates;
  }
  return alternates;
}

async function downloadFileWithRetry(url, outputPath, timeoutMs) {
  let lastError = null;
  for (let attempt = 0; attempt < 1; attempt += 1) {
    try {
      await downloadFile(url, outputPath, timeoutMs);
      return;
    } catch (error) {
      lastError = error;
      if (!isTransientDownloadError(error)) {
        break;
      }
      await sleep(retryDelayMs(attempt));
    }
  }
  throw lastError;
}

async function downloadFile(url, outputPath, timeoutMs) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const response = await fetch(url, { signal: controller.signal });
  clearTimeout(timeout);

  if (!response.ok) {
    const error = new Error(`download HTTP ${response.status} for ${url}`);
    error.status = response.status;
    throw error;
  }
  const buffer = Buffer.from(await response.arrayBuffer());
  await fs.writeFile(outputPath, buffer);
}

function isTransientDownloadError(error) {
  return error?.name === "AbortError"
    || TRANSIENT_HTTP_STATUSES.has(error?.status)
    || ["ECONNRESET", "ETIMEDOUT", "ENOTFOUND", "EAI_AGAIN", "UND_ERR_CONNECT_TIMEOUT", "UND_ERR_HEADERS_TIMEOUT"].includes(error?.code)
    || /fetch failed|network|timeout/i.test(error?.message ?? "");
}

function coverSourceExtension(url) {
  const extension = extensionFromURL(url);
  return extension ? `.${normalizeExtension(extension)}` : ".img";
}

function buildReport(collections, options) {
  const lines = [
    "# Solana Collection Bundle Report",
    "",
    `Generated: ${new Date().toISOString()}`,
    `Mode: ${options.apply ? "apply" : "dry-run"}`,
    "",
    "## Collections",
    "",
    "| Input | Collection ID | Cover Asset ID | Name | Loaded Assets | Bundled Tokens | Cover | Review |",
    "| --- | --- | --- | --- | ---: | ---: | --- | ---: |",
  ];

  for (const collection of collections) {
    const reviewCount = collection.mediaReview.decisionItems.length
      + collection.mediaReview.duplicateFileURLItems.length
      + collection.mediaReview.unsupportedItems.length
      + collection.mediaReview.missingMediaItems.length;
    lines.push(`| ${collection.input} | ${collection.collectionId} | ${coverAssetIdForCollection(collection)} | ${escapeMarkdownTable(collection.name)} | ${collection.assetsSeen} | ${collection.tokens.length} | ${collection.cover.sourceKind} | ${reviewCount} |`);
  }

  lines.push("", "## Resolved Inputs", "");
  const resolved = collections.filter((collection) => collection.resolvedFromToken);
  if (resolved.length === 0) {
    lines.push("No token inputs needed collection resolution.");
  } else {
    for (const collection of resolved) {
      lines.push(`- ${collection.input} -> ${collection.collectionId} (${escapeMarkdown(collection.name)})`);
    }
  }

  lines.push("", "## Media Review", "");
  const reviewCollections = collections.filter((collection) =>
    collection.mediaReview.decisionItems.length > 0
    || collection.mediaReview.duplicateFileURLItems.length > 0
    || collection.mediaReview.unsupportedItems.length > 0
    || collection.mediaReview.missingMediaItems.length > 0
  );
  if (reviewCollections.length === 0) {
    lines.push("No media decisions required.");
  } else {
    for (const collection of reviewCollections) {
      lines.push(`### ${escapeMarkdown(collection.name)} (${collection.collectionId})`, "");
      appendReviewSample(lines, "Selected media with alternates", collection.mediaReview.decisionItems);
      appendDuplicateSample(lines, collection.mediaReview.duplicateFileURLItems);
      appendReviewSample(lines, "Unsupported media skipped", collection.mediaReview.unsupportedItems);
      appendReviewSample(lines, "Missing media skipped", collection.mediaReview.missingMediaItems);
      lines.push("");
    }
  }

  lines.push("## Cover Sources", "");
  for (const collection of collections) {
    const status = collection.cover.error ? `failed: ${collection.cover.error}` : collection.cover.sourceKind;
    lines.push(`- ${escapeMarkdown(collection.name)} (${coverAssetIdForCollection(collection)}): ${status} - ${collection.cover.sourceUrl ?? "none"}`);
  }

  return `${lines.join("\n")}\n`;
}

function appendReviewSample(lines, title, items) {
  if (items.length === 0) {
    return;
  }
  lines.push(`#### ${title}`, "");
  const sample = items.slice(0, 12);
  for (const item of sample) {
    const selected = item.selected ? ` selected ${item.selected.extension} ${item.selected.url}` : "";
    lines.push(`- ${item.id}${item.name ? ` (${escapeMarkdown(item.name)})` : ""}${selected}`);
    for (const alternate of item.alternates ?? []) {
      lines.push(`  - alternate ${alternate.extension} ${alternate.source}: ${alternate.url}`);
    }
    for (const unsupported of item.unsupported ?? item.candidates ?? []) {
      lines.push(`  - unsupported ${unsupported.extension} ${unsupported.source}: ${unsupported.url}`);
    }
  }
  if (items.length > sample.length) {
    lines.push(`- ... ${items.length - sample.length} more`);
  }
  lines.push("");
}

function appendDuplicateSample(lines, items) {
  if (items.length === 0) {
    return;
  }
  lines.push("#### Duplicate file URLs skipped", "");
  const sample = items.slice(0, 12);
  for (const item of sample) {
    lines.push(`- ${item.id}${item.name ? ` (${escapeMarkdown(item.name)})` : ""} duplicates ${item.keptId}${item.keptName ? ` (${escapeMarkdown(item.keptName)})` : ""}: ${item.url}`);
  }
  if (items.length > sample.length) {
    lines.push(`- ... ${items.length - sample.length} more`);
  }
  lines.push("");
}

function reportableCollection(collection) {
  return {
    input: collection.input,
    collectionId: collection.collectionId,
    name: collection.name,
    tokenCount: collection.tokens.length,
    totalFromHelius: collection.totalFromHelius,
    assetsSeen: collection.assetsSeen,
    resolvedFromToken: collection.resolvedFromToken,
    cover: collection.cover,
    mediaReview: collection.mediaReview,
    sampleTokens: sampleTokens(collection.tokens, 5).map((token) => ({
      id: token.id,
      name: token.name,
      url: token.media.url,
      extension: token.media.extension,
    })),
  };
}

function sampleTokens(tokens, count) {
  if (tokens.length <= count) {
    return tokens;
  }
  const indexes = new Set();
  for (let index = 0; index < count; index += 1) {
    indexes.add(Math.round((index * (tokens.length - 1)) / (count - 1)));
  }
  return [...indexes].sort((a, b) => a - b).map((index) => tokens[index]);
}

function firstImageMediaURL(tokens) {
  return tokens.find((token) => STATIC_EXTENSIONS.has(token.media.extension) || ANIMATED_EXTENSIONS.has(token.media.extension))?.media.url ?? null;
}

function reportableCandidate(candidate) {
  return {
    url: candidate.url,
    cdnUrl: candidate.cdnUrl ?? null,
    extension: candidate.extension,
    mime: candidate.mime ?? null,
    source: candidate.source,
  };
}

function uniqueStrings(values) {
  const seen = new Set();
  const unique = [];
  for (const value of values) {
    if (!value || seen.has(value)) {
      continue;
    }
    seen.add(value);
    unique.push(value);
  }
  return unique;
}

function escapeMarkdownTable(value) {
  return escapeMarkdown(value).replace(/\|/gu, "\\|");
}

function escapeMarkdown(value) {
  return String(value ?? "").replace(/\n/gu, " ");
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
