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
const { suggestedItemId } = require("./suggested_items");

const DEFAULT_BUNDLE_PATH = path.join("Suggested Items", "Suggested.bundle");
const DEFAULT_COVERS_PATH = path.join("Suggested Items", "Covers.xcassets");
const DEFAULT_REPORT_PATH = path.join("tools", "reports", "ethereum-collection-bundle-report.md");
const DEFAULT_JSON_REPORT_PATH = path.join("tools", "reports", "ethereum-collection-bundle-report.json");
const DEFAULT_API_KEY_PATH = path.join(os.homedir(), "Developer", "secrets", "tools", "OPENSEA_API_KEY");
const DEFAULT_MAX_TOKENS = 15000;
const OPENSEA_API_BASE_URL = "https://api.opensea.io/api/v2";
const IPFS_GATEWAY_URL = "https://ipfs.io/ipfs/";
const MEDIA_TYPE_PROBE_TIMEOUT_MS = 10000;
const DEFAULT_MEDIA_PROBE_CONCURRENCY = 16;
const OPENSEA_RAW_MEDIA_HOST = "raw2.seadn.io";
const SUPPORTED_EXTENSIONS = new Set(["png", "jpg", "jpeg", "webp", "heic", "heif", "gif", "svg", "mp4", "mov", "html"]);
const STATIC_EXTENSIONS = new Set(["png", "jpg", "jpeg", "webp", "heic", "heif"]);
const ANIMATED_EXTENSIONS = new Set(["gif", "svg"]);
const VIDEO_EXTENSIONS = new Set(["mp4", "mov"]);
const HTML_EXTENSIONS = new Set(["html"]);
const TRANSIENT_HTTP_STATUSES = new Set([408, 425, 429, 500, 502, 503, 504]);
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
  ["video/webm", "webm"],
  ["text/html", "html"],
  ["application/xhtml+xml", "html"],
]);
const SUPPORTED_CHAINS = new Map([
  ["ethereum", { openSeaChain: "ethereum", appChain: "ethereum", chainId: 1, collectionIdSuffix: "" }],
  ["base", { openSeaChain: "base", appChain: "base", chainId: 8453, collectionIdSuffix: "base" }],
  ["optimism", { openSeaChain: "optimism", appChain: "optimism", chainId: 10, collectionIdSuffix: "optimism" }],
  ["zora", { openSeaChain: "zora", appChain: "zora", chainId: 7777777, collectionIdSuffix: "" }],
]);
const CHAIN_ALIASES = new Map([
  ["eth", "ethereum"],
  ["mainnet", "ethereum"],
  ["ethereum-mainnet", "ethereum"],
  ["base-mainnet", "base"],
  ["optimism-mainnet", "optimism"],
  ["op", "optimism"],
  ["zora-mainnet", "zora"],
]);

function usage() {
  return `
Usage:
  node tools/bundle_ethereum_collections.js [options] <chain:collection-contract>...
  node tools/bundle_ethereum_collections.js --input collections.txt --apply

Options:
  --input <path>          File containing one EVM collection contract per line. Use chain:address.
  --apply                 Write token JSON, items.json, covers, and reports.
  --dry-run               Fetch and validate without writing bundle assets. Default.
  --bundle <path>         Suggested.bundle path. Default: ${DEFAULT_BUNDLE_PATH}
  --covers <path>         Covers.xcassets path. Default: ${DEFAULT_COVERS_PATH}
  --report <path>         Markdown report path. Default: ${DEFAULT_REPORT_PATH}
  --json-report <path>    JSON report path. Default: ${DEFAULT_JSON_REPORT_PATH}
  --api-key <key>         OpenSea API key. Defaults to OPENSEA_API_KEY env or ${DEFAULT_API_KEY_PATH}
  --delay-ms <number>     Delay between OpenSea calls. Default: 250
  --limit <number>        OpenSea page size. Default: 200
  --timeout-ms <number>   Request timeout. Default: 30000
  --max-tokens <number>   Maximum OpenSea tokens to bundle per collection. Default: ${DEFAULT_MAX_TOKENS}
  --media-probe-concurrency <n>
                           Concurrent media content-type probes. Default: ${DEFAULT_MEDIA_PROBE_CONCURRENCY}
  --cover-size <number>   Cover width/height in pixels. Default: 300
  --cover-quality <n>     JPEG quality passed to ImageMagick. Default: 85
  --max-retries <n|forever>
                           Transient retry limit per request. Default: forever
  --skip-covers           Do not download or generate cover images.
  --continue-on-error     Continue with later inputs if one collection cannot be bundled.
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
    apiKey: process.env.OPENSEA_API_KEY ?? null,
    delayMs: 250,
    limit: 200,
    timeoutMs: 30000,
    maxTokens: DEFAULT_MAX_TOKENS,
    mediaProbeConcurrency: DEFAULT_MEDIA_PROBE_CONCURRENCY,
    coverSize: 300,
    coverQuality: 85,
    maxRetries: Number.POSITIVE_INFINITY,
    skipCovers: false,
    continueOnError: false,
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
        options.limit = boundedInteger(readValue(), arg, 1, 200);
        break;
      case "--timeout-ms":
        options.timeoutMs = positiveInteger(readValue(), arg);
        break;
      case "--max-tokens":
        options.maxTokens = positiveInteger(readValue(), arg);
        break;
      case "--media-probe-concurrency":
        options.mediaProbeConcurrency = positiveInteger(readValue(), arg);
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
      case "--continue-on-error":
        options.continueOnError = true;
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
    throw new Error("No EVM collection contracts provided. Pass chain:address values or use --input.");
  }

  const context = {
    options,
    apiKey,
    lastOpenSeaCallAt: 0,
    contentTypeByURL: new Map(),
    tempRoot: path.join(os.tmpdir(), `ethereum-collection-bundler-${process.pid}`),
  };

  await fs.mkdir(context.tempRoot, { recursive: true });
  const collectionResults = [];
  const failedCollections = [];
  const seenCollectionIds = new Set();

  for (const input of inputs) {
    const target = parseInput(input);
    const collectionId = collectionIdForTarget(target);
    if (seenCollectionIds.has(collectionId)) {
      console.log(`Skipping duplicate ${input} -> ${collectionId}`);
      continue;
    }
    seenCollectionIds.add(collectionId);

    console.log(`Fetching ${target.openSeaChain}:${target.address}`);
    try {
      const result = await fetchCollectionBundle(input, target, context);
      collectionResults.push(result);
      console.log(`  ${result.name}: ${result.tokens.length} token media row(s), ${result.tokenPayload.urlPrefixes.length} URL prefix(es)`);
    } catch (error) {
      if (!options.continueOnError) {
        throw error;
      }
      failedCollections.push({
        input,
        address: target.address,
        chain: target.appChain,
        chainId: target.chainId,
        openSeaChain: target.openSeaChain,
        error: error.message,
      });
      console.error(`  Skipping ${target.openSeaChain}:${target.address}: ${error.message}`);
    }
  }

  if (options.apply) {
    await writeBundle(collectionResults, context, failedCollections);
  } else {
    assertUniqueCoverAssetIds(collectionResults, { caseInsensitive: true });
    await writeReports(collectionResults, options, true, failedCollections);
    console.log("Dry run complete. Reports were written; bundle assets were not changed.");
  }

  const reviewCount = collectionResults.reduce((count, collection) =>
    count
    + collection.mediaReview.decisionItems.length
    + collection.mediaReview.duplicateFileURLItems.length
    + collection.mediaReview.duplicateNameItems.length
    + collection.mediaReview.unsupportedItems.length
    + collection.mediaReview.missingMediaItems.length,
  0);
  if (reviewCount > 0) {
    console.log(`${reviewCount} media item(s) reported. See ${options.reportPath}`);
  }
  if (failedCollections.length > 0) {
    console.log(`${failedCollections.length} collection(s) skipped due to errors. See ${options.reportPath}`);
  }
}

async function readApiKey(options) {
  if (options.apiKey) {
    return options.apiKey.trim();
  }

  try {
    const key = await fs.readFile(DEFAULT_API_KEY_PATH, "utf8");
    const trimmed = key.trim();
    if (trimmed) {
      return trimmed;
    }
  } catch {
    // Fall through to a clear error.
  }

  throw new Error(`Missing OpenSea API key. Set OPENSEA_API_KEY, pass --api-key, or create ${DEFAULT_API_KEY_PATH}.`);
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
      const key = value.toLowerCase();
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    });
}

function parseInput(input) {
  const match = /^(?:(?<chain>[a-z0-9_-]+):)?(?<address>0x[a-f0-9]{40})$/iu.exec(input.trim());
  if (!match?.groups) {
    throw new Error(`Invalid input "${input}". Expected chain:0x... or 0x...`);
  }

  const requestedChain = normalizeChainKey(match.groups.chain ?? "ethereum");
  const chain = SUPPORTED_CHAINS.get(requestedChain);
  if (!chain) {
    throw new Error(`Unsupported chain "${match.groups.chain}". Supported chains: ${[...SUPPORTED_CHAINS.keys()].join(", ")}`);
  }

  return {
    input,
    address: match.groups.address.toLowerCase(),
    chainKey: requestedChain,
    ...chain,
  };
}

function normalizeChainKey(value) {
  const key = String(value).trim().toLowerCase();
  return CHAIN_ALIASES.get(key) ?? key;
}

function collectionIdForTarget(target) {
  return `${target.address}${target.collectionIdSuffix}`;
}

async function fetchCollectionBundle(input, target, context) {
  const contractInfo = await getContractInfo(target, context);
  const collectionInfo = contractInfo.collection
    ? await getCollectionInfo(contractInfo.collection, context).catch((error) => ({
        _collectionInfoError: error.message,
      }))
    : null;
  assertCollectionWithinTokenLimit({
    target,
    count: collectionInfo?.total_supply ?? contractInfo.total_supply,
    source: "reported supply",
    options: context.options,
  });
  const tokens = await getTokens(target, context);

  if (tokens.length === 0) {
    throw new Error(`No OpenSea tokens found for ${target.openSeaChain}:${target.address}.`);
  }

  const name = collectionInfo?.name
    || contractInfo.name
    || contractInfo.collection
    || `${target.openSeaChain}:${target.address}`;
  const preparedTokens = await prepareTokens(tokens, target, context);
  if (preparedTokens.tokens.length === 0) {
    throw new Error(`No app-supported image, GIF, or MP4 media found for ${target.openSeaChain}:${target.address} (${name}).`);
  }

  const collectionId = collectionIdForTarget(target);
  const coverSource = firstCollectionCoverURL(collectionInfo);
  const tokenPayload = buildTokenPayload(preparedTokens.tokens);

  return {
    input,
    address: target.address,
    appChain: target.appChain,
    chainId: target.chainId,
    collectionId,
    collectionIdSuffix: target.collectionIdSuffix,
    openSeaChain: target.openSeaChain,
    openSeaCollection: contractInfo.collection ?? null,
    name,
    totalSupply: collectionInfo?.total_supply ?? contractInfo.total_supply ?? null,
    tokensSeen: tokens.length,
    tokens: preparedTokens.tokens,
    tokenPayload,
    mediaReview: preparedTokens.mediaReview,
    cover: {
      sourceUrl: coverSource?.url ?? null,
      sourceKind: coverSource?.kind ?? "none",
      fallbackSourceUrl: firstImageMediaURL(preparedTokens.tokens),
      fallbackSourceUrls: sampleImageMediaURLs(preparedTokens.tokens, 24),
      collectionInfoError: collectionInfo?._collectionInfoError ?? null,
    },
  };
}

async function getContractInfo(target, context) {
  const url = new URL(`${OPENSEA_API_BASE_URL}/chain/${target.openSeaChain}/contract/${target.address}`);
  return fetchOpenSeaJson(url, context);
}

async function getCollectionInfo(collectionSlug, context) {
  const url = new URL(`${OPENSEA_API_BASE_URL}/collections/${collectionSlug}`);
  return fetchOpenSeaJson(url, context);
}

async function getTokens(target, context) {
  const tokens = [];
  let nextCursor = null;
  let page = 0;

  do {
    const url = new URL(`${OPENSEA_API_BASE_URL}/chain/${target.openSeaChain}/contract/${target.address}/nfts`);
    url.searchParams.set("limit", String(context.options.limit));
    if (nextCursor) {
      url.searchParams.set("next", nextCursor);
    }

    const body = await fetchOpenSeaJson(url, context);
    const pageTokens = Array.isArray(body.nfts) ? body.nfts : [];
    tokens.push(...pageTokens);
    assertCollectionWithinTokenLimit({
      target,
      count: tokens.length,
      source: "fetched token count",
      options: context.options,
    });
    nextCursor = body.next ?? null;
    page += 1;

    if (context.options.verbose) {
      console.log(`  page ${page}: ${pageTokens.length} token(s), total ${tokens.length}${nextCursor ? ", more" : ""}`);
    }
  } while (nextCursor);

  return tokens;
}

function assertCollectionWithinTokenLimit({ target, count, source, options }) {
  const tokenCount = numericTokenCount(count);
  if (tokenCount != null && tokenCount > options.maxTokens) {
    throw new Error(`${target.openSeaChain}:${target.address} has ${tokenCount} token(s) by ${source}, exceeding --max-tokens ${options.maxTokens}. Refusing to bundle a likely shared contract.`);
  }
}

function numericTokenCount(value) {
  if (value == null || value === "") {
    return null;
  }
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

async function fetchOpenSeaJson(url, context) {
  for (let attempt = 0; ; attempt += 1) {
    await waitForOpenSeaSlot(context);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), context.options.timeoutMs);

    try {
      const response = await fetch(url, {
        method: "GET",
        redirect: "follow",
        signal: controller.signal,
        headers: {
          accept: "application/json",
          "x-api-key": context.apiKey,
          "User-Agent": "nft-player-ethereum-collection-bundler/1.0",
        },
      });
      const text = await response.text();
      clearTimeout(timeout);

      if (!response.ok) {
        if (shouldRetryHttp(response.status, attempt, context.options)) {
          await sleep(retryDelayMs(attempt, response.headers.get("retry-after")));
          continue;
        }
        throw new Error(`OpenSea HTTP ${response.status} for ${url}: ${formatOpenSeaErrorText(text)}`);
      }

      try {
        return JSON.parse(text);
      } catch (error) {
        throw new Error(`OpenSea JSON parse failed for ${url}: ${error.message}`);
      }
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

async function waitForOpenSeaSlot(context) {
  const elapsed = Date.now() - context.lastOpenSeaCallAt;
  if (elapsed < context.options.delayMs) {
    await sleep(context.options.delayMs - elapsed);
  }
  context.lastOpenSeaCallAt = Date.now();
}

function shouldRetryHttp(status, attempt, options) {
  return TRANSIENT_HTTP_STATUSES.has(status) && attempt < options.maxRetries;
}

function shouldRetryError(error, attempt, options) {
  if (attempt >= options.maxRetries) {
    return false;
  }
  return error?.name === "AbortError"
    || ["ECONNRESET", "ETIMEDOUT", "ENOTFOUND", "EAI_AGAIN", "UND_ERR_CONNECT_TIMEOUT", "UND_ERR_HEADERS_TIMEOUT"].includes(error?.code)
    || /fetch failed|network|timeout/iu.test(error?.message ?? "");
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

function formatOpenSeaErrorText(text) {
  if (!text) {
    return "<empty response>";
  }
  try {
    const body = JSON.parse(text);
    if (Array.isArray(body.errors) && body.errors.length > 0) {
      return body.errors.join("; ");
    }
    if (typeof body.error === "string") {
      return body.error;
    }
    if (typeof body.message === "string") {
      return body.message;
    }
  } catch {
    // Return the trimmed raw response below.
  }
  return text.trim().slice(0, 300);
}

async function prepareTokens(tokens, target, context) {
  const { options } = context;
  const candidatesByToken = [];
  const decisionItems = [];
  const duplicateFileURLItems = [];
  const duplicateNameItems = [];
  const unsupportedItems = [];
  const missingMediaItems = [];

  const tokenResults = await mapConcurrent(tokens, options.mediaProbeConcurrency, async (token) => {
    const id = tokenId(token);
    if (!id) {
      return null;
    }
    const name = tokenName(token);
    const candidates = await resolveCandidateExtensionsForSelection(mediaCandidatesForToken(token), context);
    const supportedCandidates = candidates.filter((candidate) => SUPPORTED_EXTENSIONS.has(candidate.extension));
    const selected = choosePreferredCandidate(supportedCandidates);

    if (!selected) {
      if (candidates.length > 0) {
        return {
          kind: "unsupported",
          item: {
            id,
            name,
            candidates: candidates.map(reportableCandidate),
          },
        };
      } else {
        return {
          kind: "missing",
          item: {
            id,
            name,
          },
        };
      }
    }

    return {
      kind: "candidate",
      item: {
        id,
        name,
        media: selected,
        candidates,
        supportedCandidates,
        coverUrls: coverCandidatesForToken(token),
        sortKey: sortKeyForToken(token, selected),
      },
    };
  });

  for (const result of tokenResults) {
    if (!result) {
      continue;
    }

    switch (result.kind) {
      case "candidate":
        candidatesByToken.push(result.item);
        break;
      case "unsupported":
        unsupportedItems.push(result.item);
        break;
      case "missing":
        missingMediaItems.push(result.item);
        break;
      default:
        throw new Error(`Unexpected token preparation result: ${result.kind}`);
    }
  }

  candidatesByToken.sort(comparePreparedTokens);

  const prepared = [];
  const seenMediaURLs = new Map();
  for (const token of candidatesByToken) {
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

    const distinctSupported = uniqueCandidates(token.supportedCandidates);
    const alternates = distinctSupported
      .filter((candidate) => shouldReportAlternateCandidate(candidate, token.media))
      .map(reportableCandidate);
    const unsupported = token.candidates
      .filter((candidate) => !SUPPORTED_EXTENSIONS.has(candidate.extension))
      .filter((candidate) => shouldReportAlternateCandidate(candidate, token.media))
      .map(reportableCandidate);
    if (alternates.length > 0 || unsupported.length > 0) {
      decisionItems.push({
        id: token.id,
        name: token.name,
        selected: reportableCandidate(token.media),
        alternates,
        unsupported,
      });
    }

    prepared.push({
      id: token.id,
      name: token.name,
      media: token.media,
      coverUrls: token.coverUrls,
      sortKey: token.sortKey,
    });
  }

  duplicateNameItems.push(...nameCollisionItems(prepared));

  if (options.verbose && (duplicateFileURLItems.length > 0 || duplicateNameItems.length > 0 || unsupportedItems.length > 0 || missingMediaItems.length > 0)) {
    console.log(`  ${target.openSeaChain}:${target.address}: skipped ${duplicateFileURLItems.length} duplicate URL, found ${duplicateNameItems.length} duplicate-name group(s), skipped ${unsupportedItems.length} unsupported, and ${missingMediaItems.length} missing-media token(s)`);
  }

  return {
    tokens: prepared,
    mediaReview: {
      decisionItems,
      duplicateFileURLItems,
      duplicateNameItems,
      unsupportedItems,
      missingMediaItems,
    },
  };
}

function mediaCandidatesForToken(token) {
  const candidates = [];
  appendCandidate(candidates, {
    url: token.original_animation_url ?? token.originalAnimationUrl,
    mime: null,
    source: "original_animation_url",
  });
  appendCandidate(candidates, {
    url: token.original_image_url ?? token.originalImageUrl,
    mime: null,
    source: "original_image_url",
  });
  appendCandidate(candidates, {
    url: token.display_animation_url ?? token.displayAnimationUrl,
    mime: null,
    source: "display_animation_url",
  });
  appendCandidate(candidates, {
    url: token.animation_url ?? token.animationUrl,
    mime: null,
    source: "animation_url",
  });
  appendCandidate(candidates, {
    url: token.image_url ?? token.imageUrl,
    mime: null,
    source: "image_url",
  });
  appendCandidate(candidates, {
    url: token.display_image_url ?? token.displayImageUrl,
    mime: null,
    source: "display_image_url",
  });

  const metadata = token.metadata ?? token.raw_metadata ?? token.rawMetadata;
  if (metadata && typeof metadata === "object") {
    appendCandidate(candidates, {
      url: metadata.animation_url ?? metadata.animationUrl,
      mime: metadata.mime_type ?? metadata.mimeType ?? metadata.mime,
      source: "metadata.animation_url",
    });
    appendCandidate(candidates, {
      url: metadata.image,
      mime: metadata.mime_type ?? metadata.mimeType ?? metadata.mime,
      source: "metadata.image",
    });
  }

  return uniqueCandidates(candidates);
}

async function resolveCandidateExtensionsForSelection(candidates, context) {
  let resolved = await resolveUnknownCandidateExtensions(
    candidates,
    (candidate) => isAnimationCandidateSource(candidate.source) || isOriginalCandidateSource(candidate.source),
    context
  );
  if (resolved.some((candidate) => SUPPORTED_EXTENSIONS.has(candidate.extension))) {
    return resolved;
  }
  return resolveUnknownCandidateExtensions(
    resolved,
    (candidate) => candidate.extension === "unknown",
    context
  );
}

async function resolveUnknownCandidateExtensions(candidates, shouldProbe, context) {
  const resolved = [];
  for (const candidate of candidates) {
    if (candidate.extension !== "unknown" || !shouldProbe(candidate)) {
      resolved.push(candidate);
      continue;
    }

    const contentType = await contentTypeForURL(candidate.url, context);
    const extension = extensionForContentType(contentType);
    resolved.push(extension
      ? {
          ...candidate,
          mime: candidate.mime ?? contentType,
          extension,
        }
      : candidate);
  }
  return uniqueCandidates(resolved);
}

function isAnimationCandidateSource(source) {
  return String(source).includes("animation");
}

function isOriginalCandidateSource(source) {
  const sourceName = String(source);
  return sourceName.includes("original") || sourceName.startsWith("metadata.");
}

function coverCandidatesForToken(token) {
  const candidates = [];
  const imageExtensions = new Set([...STATIC_EXTENSIONS, ...ANIMATED_EXTENSIONS]);

  for (const candidate of mediaCandidatesForToken(token)) {
    if (imageExtensions.has(candidate.extension) && !VIDEO_EXTENSIONS.has(candidate.extension)) {
      candidates.push(candidate.url);
    }
  }

  for (const url of [
    token.image_url ?? token.imageUrl,
    token.display_image_url ?? token.displayImageUrl,
    token.display_animation_url ?? token.displayAnimationUrl,
  ]) {
    const normalizedURL = normalizeAssetUrl(url);
    if (normalizedURL && !isKnownInteractiveGeneratorURL(normalizedURL)) {
      candidates.push(normalizedURL);
    }
  }

  return uniqueStrings(candidates);
}

function appendCandidate(candidates, candidate) {
  const normalizedUrl = normalizeAssetUrl(candidate.url);
  if (!normalizedUrl) {
    return;
  }
  appendNormalizedCandidate(candidates, {
    ...candidate,
    url: normalizedUrl,
  });

  const rawOpenSeaURL = rawOpenSeaMediaURL(normalizedUrl);
  if (rawOpenSeaURL) {
    appendNormalizedCandidate(candidates, {
      ...candidate,
      url: rawOpenSeaURL,
      source: `raw2.${candidate.source}`,
    });
  }
}

function appendNormalizedCandidate(candidates, candidate) {
  if (isKnownInteractiveGeneratorURL(candidate.url)) {
    candidates.push({
      ...candidate,
      extension: "interactive-html",
    });
    return;
  }
  if (isKnownMathcastlesHTMLURL(candidate.url)) {
    candidates.push({
      ...candidate,
      extension: "html",
    });
    return;
  }

  const extension = fileExtensionForURL(candidate.url, candidate.mime);
  if (!extension) {
    candidates.push({
      ...candidate,
      extension: "unknown",
    });
    return;
  }
  candidates.push({
    ...candidate,
    extension,
  });
}

function isKnownInteractiveGeneratorURL(urlString) {
  try {
    const url = new URL(urlString);
    return url.hostname === "generator.artblocks.io";
  } catch {
    return false;
  }
}

function isKnownMathcastlesHTMLURL(urlString) {
  try {
    const url = new URL(urlString);
    return url.hostname === "tokens.mathcastles.xyz" && /\/token-html\//u.test(url.pathname);
  } catch {
    return false;
  }
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
    }
  }
  return unique;
}

function shouldReportAlternateCandidate(candidate, selected) {
  if (candidate.url === selected.url && candidate.extension === selected.extension) {
    return false;
  }
  if (isOpenSeaDerivativeMediaURL(candidate.url) && !isOpenSeaDerivativeMediaURL(selected.url)) {
    return false;
  }
  if (String(candidate.source ?? "").startsWith("raw2.") && String(selected.source ?? "").includes("original")) {
    return false;
  }
  return true;
}

function choosePreferredCandidate(candidates) {
  if (candidates.length === 0) {
    return null;
  }

  const ranked = [...candidates].sort((left, right) => candidateRank(left) - candidateRank(right));
  return ranked[0];
}

function candidateRank(candidate) {
  const source = String(candidate.source ?? "");
  let rank = 100;
  if (VIDEO_EXTENSIONS.has(candidate.extension)) {
    rank = 0;
  } else if (HTML_EXTENSIONS.has(candidate.extension)) {
    rank = 5;
  } else if (ANIMATED_EXTENSIONS.has(candidate.extension)) {
    rank = 10;
  } else if (STATIC_EXTENSIONS.has(candidate.extension)) {
    rank = 30;
  }
  if (source.includes("animation")) {
    rank -= 20;
  }
  if (source.includes("original")) {
    rank -= 10;
  } else if (source.startsWith("raw2.")) {
    rank -= 8;
  } else if (source === "display_image_url") {
    rank += 8;
  } else if (source === "image_url" || source === "metadata.image") {
    rank += 6;
  }
  if (isOpenSeaDerivativeMediaURL(candidate.url)) {
    rank += 50;
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
    return `${IPFS_GATEWAY_URL}${trimmed.slice("ipfs://".length).replace(/^ipfs\//u, "")}`;
  }
  if (trimmed.startsWith("ar://")) {
    return `https://arweave.net/${trimmed.slice("ar://".length)}`;
  }
  if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
    return trimmed;
  }
  return null;
}

function rawOpenSeaMediaURL(urlString) {
  try {
    const url = new URL(urlString);
    if (!isOpenSeaDerivativeMediaHost(url.hostname)) {
      return null;
    }
    url.hostname = OPENSEA_RAW_MEDIA_HOST;
    url.search = "";
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}

function isOpenSeaDerivativeMediaURL(urlString) {
  try {
    return isOpenSeaDerivativeMediaHost(new URL(urlString).hostname);
  } catch {
    return false;
  }
}

function isOpenSeaDerivativeMediaHost(hostname) {
  return /^(?:i|i\d+c?)\.seadn\.io$/iu.test(String(hostname));
}

function fileExtensionForURL(urlString, mime) {
  const mimeExtension = extensionForContentType(mime);
  const urlExtension = extensionFromURL(urlString);
  return normalizeExtension(urlExtension) ?? normalizeExtension(mimeExtension);
}

function extensionForContentType(contentType) {
  if (!contentType) {
    return null;
  }
  return normalizeExtension(EXTENSION_BY_MIME.get(String(contentType).toLowerCase().split(";")[0].trim()));
}

async function contentTypeForURL(urlString, context) {
  const cached = context.contentTypeByURL.get(urlString);
  if (cached !== undefined) {
    return cached;
  }

  const timeoutMs = Math.min(context.options.timeoutMs, MEDIA_TYPE_PROBE_TIMEOUT_MS);
  const contentType = await fetchContentType(urlString, "HEAD", timeoutMs)
    ?? await fetchContentType(urlString, "GET", timeoutMs);
  context.contentTypeByURL.set(urlString, contentType);
  return contentType;
}

async function fetchContentType(urlString, method, timeoutMs) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(urlString, {
      method,
      redirect: "follow",
      signal: controller.signal,
      headers: {
        accept: "image/*, text/html, application/xhtml+xml, video/mp4, video/*;q=0.8, */*;q=0.1",
        "User-Agent": "nft-player-ethereum-collection-bundler/1.0",
        ...(method === "GET" ? { Range: "bytes=0-0" } : {}),
      },
    });
    await response.body?.cancel?.();
    if (!response.ok && response.status !== 206) {
      return null;
    }
    return response.headers.get("content-type");
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
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
  if (normalized === "jpe") {
    return "jpg";
  }
  if (normalized === "htm" || normalized === "xhtml") {
    return "html";
  }
  return normalized;
}

function sortKeyForToken(token, selected) {
  const id = tokenId(token);
  const name = tokenName(token);
  const numericName = numericTokenIdFromName(name);
  const basename = urlLastPathComponent(selected.url);
  const numericBasename = numericTokenIdFromBasename(basename);
  return {
    numericId: numericTokenId(id),
    numericName,
    numericBasename,
    basename,
    id,
  };
}

function tokenId(token) {
  return String(token.identifier ?? token.id ?? token.token_id ?? token.tokenId ?? "");
}

function tokenName(token) {
  return String(token.name ?? "");
}

function numericTokenId(value) {
  const normalized = String(value);
  if (!/^\d+$/u.test(normalized)) {
    return null;
  }
  return BigInt(normalized);
}

function numericTokenIdFromName(name) {
  const hashMatches = [...String(name).matchAll(/#\s*(\d+)/gu)];
  if (hashMatches.length > 0) {
    return BigInt(hashMatches[hashMatches.length - 1][1]);
  }
  const trailing = /(\d+)\s*$/u.exec(String(name));
  return trailing ? BigInt(trailing[1]) : null;
}

function numericTokenIdFromBasename(basename) {
  const numeric = /^0*(\d+)(?:\.[a-z0-9]+)?$/iu.exec(basename);
  return numeric ? BigInt(numeric[1]) : null;
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
  return compareNullableBigInts(left.sortKey.numericId, right.sortKey.numericId)
    || compareNullableBigInts(left.sortKey.numericName, right.sortKey.numericName)
    || compareNullableBigInts(left.sortKey.numericBasename, right.sortKey.numericBasename)
    || naturalCompare(left.sortKey.basename, right.sortKey.basename)
    || naturalCompare(left.id, right.id);
}

function compareNullableBigInts(left, right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  if (left === right) {
    return 0;
  }
  return left < right ? -1 : 1;
}

function naturalCompare(left, right) {
  return String(left).localeCompare(String(right), undefined, { numeric: true, sensitivity: "base" });
}

function nameCollisionItems(tokens) {
  const groups = new Map();
  for (const token of tokens) {
    const nameKey = normalizedNameKey(token.name);
    if (!nameKey) {
      continue;
    }
    const group = groups.get(nameKey) ?? [];
    group.push({
      id: token.id,
      name: token.name,
      url: token.media.url,
      extension: token.media.extension,
    });
    groups.set(nameKey, group);
  }

  return [...groups.entries()]
    .filter(([, items]) => items.length > 1)
    .map(([nameKey, items]) => ({
      nameKey,
      items,
    }))
    .sort((left, right) =>
      compareNullableBigInts(numericTokenId(left.items[0].id), numericTokenId(right.items[0].id))
      || naturalCompare(left.items[0].id, right.items[0].id)
    );
}

function normalizedNameKey(value) {
  return String(value ?? "")
    .normalize("NFKC")
    .trim()
    .replace(/\s+/gu, " ")
    .toLowerCase();
}

function buildTokenPayload(tokens) {
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
    const pathParts = url.pathname.split("/").filter(Boolean);
    if (url.hostname.endsWith("seadn.io") && pathParts.length >= 2 && /^0x[a-f0-9]{40}$/iu.test(pathParts[1])) {
      url.pathname = `/${pathParts[0]}/${pathParts[1]}/`;
      url.search = "";
      url.hash = "";
      return url.toString();
    }
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

async function writeBundle(collections, context, failedCollections = []) {
  const { options } = context;
  const bundlePath = path.resolve(options.bundlePath);
  const tokensPath = path.join(bundlePath, "Tokens");
  const itemsPath = path.join(bundlePath, "items.json");
  await fs.mkdir(tokensPath, { recursive: true });

  const existingItems = JSON.parse(await fs.readFile(itemsPath, "utf8"));
  assertUniqueCoverAssetIds(collections, { caseInsensitive: true });
  const updatedItems = mergeSuggestedItems(existingItems, collections);

  for (const collection of collections) {
    const outputPath = path.join(tokensPath, `${collection.collectionId}.json`);
    await fs.writeFile(outputPath, `${JSON.stringify(collection.tokenPayload)}\n`);
  }

  await fs.writeFile(itemsPath, formatSuggestedItems(updatedItems));

  if (!options.skipCovers) {
    await writeCovers(collections, context);
  }

  await writeReports(collections, options, false, failedCollections);
  console.log(`Wrote ${collections.length} Ethereum/EVM collection bundle(s).`);
}

function mergeSuggestedItems(existingItems, collections) {
  const updatesById = new Map();
  for (const collection of collections) {
    for (const id of suggestedItemMergeIds(collection)) {
      updatesById.set(id.toLowerCase(), collection);
    }
  }
  const existingIds = new Set();

  const updated = [];
  for (const item of existingItems) {
    const id = suggestedItemId(item).toLowerCase();
    const collection = updatesById.get(id);
    if (collection) {
      const canonicalId = collection.collectionId.toLowerCase();
      if (existingIds.has(canonicalId)) {
        continue;
      }
      existingIds.add(canonicalId);
      updated.push(mergedSuggestedItem(item, collection));
    } else {
      updated.push(item);
    }
  }

  for (const collection of collections) {
    const id = collection.collectionId.toLowerCase();
    if (!existingIds.has(id)) {
      updated.push(newSuggestedItem(collection));
    }
  }

  return updated;
}

function suggestedItemMergeIds(collection) {
  const ids = new Set([collection.collectionId]);
  if (!collection.collectionIdSuffix && collection.appChain !== "ethereum") {
    ids.add(`${collection.address}${collection.appChain}`);
  }
  return ids;
}

function mergedSuggestedItem(item, collection) {
  const { collectionId, ...itemWithoutCollectionId } = item;
  return {
    ...itemWithoutCollectionId,
    chain: collection.appChain,
    chainId: collection.chainId,
    ...(collection.collectionIdSuffix ? { collectionId: collection.collectionIdSuffix } : {}),
    tokenCount: collection.tokens.length,
  };
}

function newSuggestedItem(collection) {
  return {
    address: collection.address,
    chain: collection.appChain,
    chainId: collection.chainId,
    ...(collection.collectionIdSuffix ? { collectionId: collection.collectionIdSuffix } : {}),
    name: collection.name,
    tokenCount: collection.tokens.length,
    iosOnly: true,
  };
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
        await downloadFileWithRetry(candidate.url, tempPath, context.options.timeoutMs, context.options.maxRetries);
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
        await writePlaceholderCover(coverTools, outputPath, collection.name, context.options.coverSize, context.options.coverQuality, "EVM");
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

async function downloadFileWithRetry(url, outputPath, timeoutMs, maxRetries) {
  let lastError = null;
  const retryLimit = Number.isFinite(maxRetries) ? maxRetries : 2;
  for (let attempt = 0; attempt <= retryLimit; attempt += 1) {
    try {
      await downloadFile(url, outputPath, timeoutMs);
      return;
    } catch (error) {
      lastError = error;
      if (!isTransientDownloadError(error) || attempt >= retryLimit) {
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
    || /fetch failed|network|timeout/iu.test(error?.message ?? "");
}

function coverSourceExtension(url) {
  const extension = extensionFromURL(url);
  return extension ? `.${normalizeExtension(extension)}` : ".img";
}

async function writeReports(collections, options, dryRun, failedCollections = []) {
  await fs.mkdir(path.dirname(options.reportPath), { recursive: true });
  await fs.mkdir(path.dirname(options.jsonReportPath), { recursive: true });
  await fs.writeFile(options.reportPath, buildReport(collections, { ...options, apply: !dryRun }, failedCollections));
  await fs.writeFile(options.jsonReportPath, `${JSON.stringify({
    generatedAt: new Date().toISOString(),
    dryRun,
    collections: collections.map((collection) => reportableCollection(collection)),
    failedCollections,
  }, null, 2)}\n`);
}

function buildReport(collections, options, failedCollections = []) {
  const lines = [
    "# Ethereum/EVM Collection Bundle Report",
    "",
    `Generated: ${new Date().toISOString()}`,
    `Mode: ${options.apply ? "apply" : "dry-run"}`,
    "",
    "## Collections",
    "",
    "| Input | Chain | Collection ID | Cover Asset ID | Name | OpenSea Tokens | Bundled Tokens | Cover | Review |",
    "| --- | --- | --- | --- | --- | ---: | ---: | --- | ---: |",
  ];

  for (const collection of collections) {
    const reviewCount = collection.mediaReview.decisionItems.length
      + collection.mediaReview.duplicateFileURLItems.length
      + collection.mediaReview.duplicateNameItems.length
      + collection.mediaReview.unsupportedItems.length
      + collection.mediaReview.missingMediaItems.length;
    lines.push(`| ${escapeMarkdownTable(collection.input)} | ${collection.appChain} (${collection.chainId}) | ${collection.collectionId} | ${coverAssetIdForCollection(collection)} | ${escapeMarkdownTable(collection.name)} | ${collection.tokensSeen} | ${collection.tokens.length} | ${collection.cover.sourceKind} | ${reviewCount} |`);
  }

  if (failedCollections.length > 0) {
    lines.push("", "## Failed Collections", "");
    lines.push("| Input | Chain | Error |", "| --- | --- | --- |");
    for (const failure of failedCollections) {
      lines.push(`| ${escapeMarkdownTable(failure.input)} | ${escapeMarkdownTable(`${failure.chain} (${failure.chainId})`)} | ${escapeMarkdownTable(failure.error)} |`);
    }
  }

  lines.push("", "## Media Review", "");
  const reviewCollections = collections.filter((collection) =>
    collection.mediaReview.decisionItems.length > 0
    || collection.mediaReview.duplicateFileURLItems.length > 0
    || collection.mediaReview.duplicateNameItems.length > 0
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
      appendNameCollisionSample(lines, collection.mediaReview.duplicateNameItems);
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

function appendNameCollisionSample(lines, items) {
  if (items.length === 0) {
    return;
  }
  lines.push("#### Duplicate token names to review", "");
  const sample = items.slice(0, 12);
  for (const item of sample) {
    const tokens = item.items
      .map((token) => `${token.id}${token.name ? ` (${escapeMarkdown(token.name)})` : ""} ${token.extension}: ${token.url}`)
      .join("; ");
    lines.push(`- ${escapeMarkdown(item.nameKey)}: ${tokens}`);
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
    address: collection.address,
    chain: collection.appChain,
    chainId: collection.chainId,
    openSeaChain: collection.openSeaChain,
    openSeaCollection: collection.openSeaCollection,
    name: collection.name,
    tokenCount: collection.tokens.length,
    tokensSeen: collection.tokensSeen,
    totalSupply: collection.totalSupply,
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

function firstCollectionCoverURL(collectionInfo) {
  if (!collectionInfo || collectionInfo._collectionInfoError) {
    return null;
  }
  const candidates = [
    ["image_url", collectionInfo.image_url],
    ["featured_image_url", collectionInfo.featured_image_url],
    ["banner_image_url", collectionInfo.banner_image_url],
  ];
  for (const [kind, url] of candidates) {
    const normalizedURL = normalizeAssetUrl(url);
    if (normalizedURL) {
      return {
        kind,
        url: normalizedURL,
      };
    }
  }
  return null;
}

function firstImageMediaURL(tokens) {
  return tokens.find((token) => STATIC_EXTENSIONS.has(token.media.extension) || ANIMATED_EXTENSIONS.has(token.media.extension))?.media.url ?? null;
}

function sampleImageMediaURLs(tokens, count) {
  return sampleTokens(
    tokens.filter((token) => STATIC_EXTENSIONS.has(token.media.extension) || ANIMATED_EXTENSIONS.has(token.media.extension)),
    count
  ).flatMap((token) => token.coverUrls.length > 0 ? token.coverUrls : [token.media.url]);
}

function reportableCandidate(candidate) {
  return {
    url: candidate.url,
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

async function mapConcurrent(values, concurrency, mapper) {
  const results = new Array(values.length);
  let nextIndex = 0;

  async function worker() {
    while (nextIndex < values.length) {
      const index = nextIndex;
      nextIndex += 1;
      results[index] = await mapper(values[index], index);
    }
  }

  await Promise.all(Array.from({ length: Math.min(concurrency, values.length) }, worker));
  return results;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((error) => {
  console.error(error.stack ?? error.message);
  process.exitCode = 1;
});
