#!/usr/bin/env node

const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const { suggestedItemId } = require("./suggested_items");
const {
  SKIP_REASON: BUNDLED_GENERATIVE_SKIP_REASON,
  isBundledGenerativeCollectionId,
  loadBundledGenerativeCollectionIds,
} = require("./bundled_generative_collections");
const { isCdnLilManagedCollection } = require("./cdn_lil_managed_collections");

const DEFAULT_BUNDLE_PATH = path.join("Suggested Items", "Suggested.bundle");
const DEFAULT_REPORT_PATH = path.join("tools", "reports", "bundled-collection-source-audit.md");
const DEFAULT_JSON_REPORT_PATH = path.join("tools", "reports", "bundled-collection-source-audit.json");
const DEFAULT_HELIUS_API_KEY_PATH = path.join(os.homedir(), "Developer", "secrets", "tools", "HELIUS_API_KEY");
const DEFAULT_OPENSEA_API_KEY_PATH = path.join(os.homedir(), "Developer", "secrets", "tools", "OPENSEA_API_KEY");
const HELIUS_MAINNET_URL = "https://mainnet.helius-rpc.com/";
const OPENSEA_API_BASE_URL = "https://api.opensea.io/api/v2";
const TZKT_API_BASE_URL = "https://api.tzkt.io";
const IPFS_GATEWAY_URL = "https://ipfs.io/ipfs/";
const APP_IPFS_GATEWAY_URL = "https://ipfs.decentralized-content.com/ipfs/";
const OPENSEA_RAW_MEDIA_HOST = "raw2.seadn.io";
const SIMPLEHASH_ASSET_BASE_URL = "https://cdn.simplehash.com/assets/";
const ARTBLOCKS_MEDIA_PROXY_BASE_URL = "https://media-proxy.artblocks.io/";
const MEDIA_PROBE_TIMEOUT_MS = 30000;
const MEDIA_PROBE_TIMEOUT = Symbol("media-probe-timeout");
const RETRY_DELAY_CAP_MS = 15000;
const TRANSIENT_HTTP_STATUSES = new Set([408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524]);
const TRANSIENT_RPC_CODES = new Set([-32005, -32603]);
const CDN_LIL_HOST_RE = /(^|\.)cdn\.lil\.org$/iu;

const STATIC_EXTENSIONS = new Set(["png", "jpg", "jpeg", "webp", "heic", "heif"]);
const ANIMATED_EXTENSIONS = new Set(["gif", "svg"]);
const SOLANA_TEZOS_ANIMATED_EXTENSIONS = new Set(["gif"]);
const VIDEO_EXTENSIONS = new Set(["mp4", "mov"]);
const HTML_EXTENSIONS = new Set(["html"]);
const EVM_SUPPORTED_EXTENSIONS = new Set([
  ...STATIC_EXTENSIONS,
  ...ANIMATED_EXTENSIONS,
  ...VIDEO_EXTENSIONS,
  ...HTML_EXTENSIONS,
]);
const SOLANA_TEZOS_SUPPORTED_EXTENSIONS = new Set([
  ...STATIC_EXTENSIONS,
  ...SOLANA_TEZOS_ANIMATED_EXTENSIONS,
  ...VIDEO_EXTENSIONS,
]);
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

const EVM_CHAIN_CONFIGS = new Map([
  ["ethereum", { openSeaChain: "ethereum", appChain: "ethereum", chainId: 1, collectionIdSuffix: "" }],
  ["base", { openSeaChain: "base", appChain: "base", chainId: 8453, collectionIdSuffix: "base" }],
  ["optimism", { openSeaChain: "optimism", appChain: "optimism", chainId: 10, collectionIdSuffix: "optimism" }],
  ["zora", { openSeaChain: "zora", appChain: "zora", chainId: 7777777, collectionIdSuffix: "zora" }],
]);
const CHAIN_ALIASES = new Map([
  ["eth", "ethereum"],
  ["mainnet", "ethereum"],
  ["ethereum-mainnet", "ethereum"],
  ["base-mainnet", "base"],
  ["op", "optimism"],
  ["optimism-mainnet", "optimism"],
  ["zora-mainnet", "zora"],
]);

function usage() {
  return `
Usage:
  node tools/audit_bundled_collection_sources.js [options]

Collections represented by Suggested.bundle/Scripts/*.json are always skipped.

Options:
  --apply                 Rewrite token JSON and items.json. Default is dry-run.
  --dry-run               Report only. Default.
  --bundle <path>         Suggested.bundle path. Default: ${DEFAULT_BUNDLE_PATH}
  --chain <name>          Limit by chain. Repeatable. Supports ethereum, base, zora, solana, tezos.
  --collection <value>    Limit by collection id, address, or name. Repeatable.
  --include-cdn-lil       Audit collections whose current token URLs contain cdn.lil.org.
  --report <path>         Markdown report path. Default: ${DEFAULT_REPORT_PATH}
  --json-report <path>    JSON report path. Default: ${DEFAULT_JSON_REPORT_PATH}
  --opensea-api-key <key> OpenSea API key. Defaults to OPENSEA_API_KEY or ${DEFAULT_OPENSEA_API_KEY_PATH}
  --helius-api-key <key>  Helius API key. Defaults to HELIUS_API_KEY or ${DEFAULT_HELIUS_API_KEY_PATH}
  --tzkt-api-base-url <url>
                           TzKT API base URL. Default: ${TZKT_API_BASE_URL}
  --limit <number>        API page size. Default: 1000 for Helius/TzKT, 200 for OpenSea.
  --opensea-limit <n>     OpenSea page size. Default: 200.
  --timeout-ms <number>   Request timeout. Default: 30000.
  --delay-ms <number>     Delay between API calls per provider. Default: 250.
  --media-probe-concurrency <n>
                           Concurrent media content-type probes. Default: 64.
  --max-retries <n|forever>
                           Transient retry limit per request. Default: 5.
  --verbose               Print per-collection diagnostics.
  --help                  Show this help.
`.trim();
}

function parseArgs(argv) {
  const options = {
    apply: false,
    bundlePath: DEFAULT_BUNDLE_PATH,
    chains: [],
    collections: [],
    includeCdnLil: false,
    reportPath: DEFAULT_REPORT_PATH,
    jsonReportPath: DEFAULT_JSON_REPORT_PATH,
    openSeaApiKey: process.env.OPENSEA_API_KEY ?? null,
    heliusApiKey: process.env.HELIUS_API_KEY ?? null,
    tzktApiBaseUrl: TZKT_API_BASE_URL,
    limit: 1000,
    openSeaLimit: 200,
    timeoutMs: 30000,
    delayMs: 250,
    mediaProbeConcurrency: 64,
    maxRetries: 5,
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
      case "--apply":
        options.apply = true;
        break;
      case "--dry-run":
        options.apply = false;
        break;
      case "--bundle":
        options.bundlePath = readValue();
        break;
      case "--chain":
        options.chains.push(normalizeChainKey(readValue()));
        break;
      case "--collection":
        options.collections.push(readValue().trim().toLowerCase());
        break;
      case "--include-cdn-lil":
        options.includeCdnLil = true;
        break;
      case "--report":
        options.reportPath = readValue();
        break;
      case "--json-report":
        options.jsonReportPath = readValue();
        break;
      case "--opensea-api-key":
        options.openSeaApiKey = readValue();
        break;
      case "--helius-api-key":
        options.heliusApiKey = readValue();
        break;
      case "--tzkt-api-base-url":
        options.tzktApiBaseUrl = readValue().replace(/\/+$/u, "");
        break;
      case "--limit":
        options.limit = boundedInteger(readValue(), arg, 1, 10000);
        break;
      case "--opensea-limit":
        options.openSeaLimit = boundedInteger(readValue(), arg, 1, 200);
        break;
      case "--timeout-ms":
        options.timeoutMs = positiveInteger(readValue(), arg);
        break;
      case "--delay-ms":
        options.delayMs = nonNegativeInteger(readValue(), arg);
        break;
      case "--media-probe-concurrency":
        options.mediaProbeConcurrency = positiveInteger(readValue(), arg);
        break;
      case "--max-retries": {
        const value = readValue();
        options.maxRetries = value === "forever" ? Number.POSITIVE_INFINITY : nonNegativeInteger(value, arg);
        break;
      }
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

function normalizeChainKey(value) {
  const key = String(value).trim().toLowerCase();
  return CHAIN_ALIASES.get(key) ?? key;
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
  const context = {
    options,
    openSeaApiKey: null,
    heliusApiKey: null,
    lastOpenSeaCallAt: 0,
    lastHeliusCallAt: 0,
    lastTzktCallAt: 0,
    contentTypeByURL: new Map(),
    evmTokensByTarget: new Map(),
    evmTokensBySlug: new Map(),
    evmNftByTargetId: new Map(),
    solanaTokensByCollectionId: new Map(),
    tezosTokensByContract: new Map(),
  };

  const loaded = await loadBundle(options);
  const selected = selectCollections(loaded.collections, options);
  if (selected.length === 0) {
    throw new Error("No downloadable collections matched.");
  }

  context.openSeaApiKey = await maybeReadApiKey(
    options.openSeaApiKey,
    DEFAULT_OPENSEA_API_KEY_PATH,
    selected.some((collection) => !collection.bundledGenerative && isEvmChain(collection.item.chain))
  );
  context.heliusApiKey = await maybeReadApiKey(
    options.heliusApiKey,
    DEFAULT_HELIUS_API_KEY_PATH,
    selected.some((collection) => !collection.bundledGenerative && collection.item.chain === "solana")
  );

  const audited = [];
  const skipped = [];
  let processed = 0;

  for (const collection of selected) {
    processed += 1;
    if (collection.bundledGenerative) {
      skipped.push({
        id: collection.id,
        name: collection.item.name,
        chain: collection.item.chain,
        reason: BUNDLED_GENERATIVE_SKIP_REASON,
      });
      continue;
    }
    if (!options.includeCdnLil && collection.containsCdnLil) {
      skipped.push({
        id: collection.id,
        name: collection.item.name,
        chain: collection.item.chain,
        reason: "current bundled token URL contains cdn.lil.org",
      });
      continue;
    }

    console.error(`Auditing ${processed}/${selected.length}: ${collection.item.chain} ${collection.item.name} (${collection.id})`);
    const result = await auditCollection(collection, context);
    audited.push(result);
    if (options.verbose || result.changed || result.failures.length > 0 || result.missingBundledTokenIds.length > 0 || result.replacedFallbackItems.length > 0) {
      console.error(`  ${result.status}: API ${result.apiTokenCount}, bundled ${result.originalTokenCount} -> ${result.nextTokenCount}, changes ${result.changeCount}, failures ${result.failures.length}`);
    }
  }

  if (options.apply) {
    await applyAuditResults(loaded, audited);
  }

  await writeReports({
    options,
    bundlePath: loaded.bundlePath,
    collections: audited,
    skipped,
  });

  const summary = summarize(audited, skipped, options);
  console.log(JSON.stringify(summary, null, 2));
}

async function maybeReadApiKey(value, fallbackPath, required) {
  if (value?.trim()) {
    return value.trim();
  }
  try {
    const key = (await fs.readFile(fallbackPath, "utf8")).trim();
    if (key) {
      return key;
    }
  } catch {
    // Fall through to the required check.
  }
  if (required) {
    throw new Error(`Missing API key. Set the env var, pass the CLI option, or create ${fallbackPath}.`);
  }
  return null;
}

async function loadBundle(options) {
  const bundlePath = path.resolve(options.bundlePath);
  const itemsPath = path.join(bundlePath, "items.json");
  const tokensPath = path.join(bundlePath, "Tokens");
  const [items, bundledGenerativeCollectionIds] = await Promise.all([
    fs.readFile(itemsPath, "utf8").then((contents) => JSON.parse(contents)),
    loadBundledGenerativeCollectionIds(bundlePath),
  ]);
  const collections = [];

  for (const [itemIndex, item] of items.entries()) {
    const id = suggestedItemId(item);
    if (isBundledGenerativeCollectionId(id, bundledGenerativeCollectionIds)) {
      collections.push({
        item,
        itemIndex,
        id,
        tokenPath: null,
        payload: null,
        records: [],
        containsCdnLil: false,
        loadError: null,
        bundledGenerative: true,
      });
      continue;
    }
    if (item.tokenCount == null) {
      continue;
    }
    const tokenPath = path.join(tokensPath, `${id}.json`);
    let payload;
    try {
      payload = JSON.parse(await fs.readFile(tokenPath, "utf8"));
    } catch (error) {
      collections.push({
        item,
        itemIndex,
        id,
        tokenPath,
        payload: null,
        records: [],
        containsCdnLil: isCdnLilManagedCollection(item),
        loadError: error.message,
        bundledGenerative: false,
      });
      continue;
    }

    const records = normalizeBundledTokenRecords(payload, item);
    collections.push({
      item,
      itemIndex,
      id,
      tokenPath,
      payload,
      records,
      containsCdnLil: isCdnLilManagedCollection(item) || records.some((record) => isCdnLilURL(record.url)),
      loadError: null,
      bundledGenerative: false,
    });
  }

  return {
    bundlePath,
    itemsPath,
    tokensPath,
    items,
    collections,
  };
}

function selectCollections(collections, options) {
  const chainFilter = new Set(options.chains);
  const collectionFilter = new Set(options.collections);
  return collections.filter((collection) => {
    const chain = normalizeChainKey(collection.item.chain);
    if (chainFilter.size > 0 && !chainFilter.has(chain)) {
      return false;
    }
    if (collectionFilter.size === 0) {
      return true;
    }
    const values = [
      collection.id,
      collection.item.address,
      collection.item.collectionId,
      collection.item.abId,
      collection.item.name,
    ].filter(Boolean).map((value) => String(value).toLowerCase());
    return values.some((value) =>
      collectionFilter.has(value)
      || [...collectionFilter].some((filter) => value.includes(filter))
    );
  });
}

function normalizeBundledTokenRecords(payload, item) {
  const defaultFileExtension = normalizeExtension(payload.defaultFileExtension);
  const urlPrefixes = Array.isArray(payload.urlPrefixes) ? payload.urlPrefixes : [];
  return (payload.items ?? []).map((row, index) => {
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
        rowKind: "compact",
        id,
        name: null,
        url,
        fileExtension,
        sourceKind: sourceKindForBundledURL(url),
      };
    }

    if (row && typeof row === "object") {
      const id = String(row.id ?? row.tokenId ?? index);
      const url = resolvedObjectRowURL(row, item);
      const fileExtension = normalizeExtension(row.fileExtension)
        ?? extensionFromURL(url ?? "")
        ?? defaultFileExtension
        ?? normalizeExtension(row.sh && extensionFromURL(row.sh));
      return {
        row,
        rowIndex: index,
        rowKind: "object",
        id,
        name: row.name ?? null,
        url,
        fileExtension,
        sourceKind: row.url
          ? sourceKindForBundledURL(row.url)
          : row.sh
            ? "simplehash"
            : item.chain === "ethereum"
              ? "artblocks-media-proxy"
              : "missing-url",
      };
    }

    return {
      row,
      rowIndex: index,
      rowKind: "unknown",
      id: String(index),
      name: null,
      url: null,
      fileExtension: null,
      sourceKind: "unknown-row",
    };
  });
}

function resolvedObjectRowURL(row, item) {
  if (row.url) {
    return normalizeAppURL(row.url);
  }
  if (row.sh) {
    return `${SIMPLEHASH_ASSET_BASE_URL}${row.sh}`;
  }
  if (item.chain === "ethereum") {
    return `${ARTBLOCKS_MEDIA_PROXY_BASE_URL}${item.address}/${row.id}.png`;
  }
  return null;
}

function normalizeAppURL(urlString) {
  if (!urlString || typeof urlString !== "string") {
    return null;
  }
  const trimmed = urlString.trim();
  if (trimmed.startsWith("ipfs://")) {
    return `${APP_IPFS_GATEWAY_URL}${trimmed.slice("ipfs://".length).replace(/^ipfs\//u, "")}`;
  }
  if (trimmed.startsWith("ar://")) {
    return `https://arweave.net/${trimmed.slice("ar://".length)}`;
  }
  return trimmed;
}

function sourceKindForBundledURL(urlString) {
  if (!urlString) {
    return "missing-url";
  }
  if (isOpenSeaDerivativeMediaURL(urlString)) {
    return "opensea-derivative";
  }
  if (isRawOpenSeaMediaURL(urlString)) {
    return "opensea-raw";
  }
  if (/cdn\.helius-rpc\.com/iu.test(urlString)) {
    return "helius-cdn";
  }
  if (/permagate\.io/iu.test(urlString)) {
    return "permagate";
  }
  if (/cdn\.simplehash\.com/iu.test(urlString)) {
    return "simplehash";
  }
  if (/media-proxy\.artblocks\.io/iu.test(urlString)) {
    return "artblocks-media-proxy";
  }
  return "explicit-url";
}

function isCdnLilURL(urlString) {
  if (!urlString) {
    return false;
  }
  try {
    return CDN_LIL_HOST_RE.test(new URL(urlString).hostname);
  } catch {
    return /cdn\.lil\.org/iu.test(urlString);
  }
}

async function auditCollection(collection, context) {
  if (collection.loadError) {
    return failedCollectionResult(collection, [`failed to read token JSON: ${collection.loadError}`]);
  }

  try {
    if (collection.item.chain === "solana") {
      return await auditSolanaCollection(collection, context);
    }
    if (collection.item.chain === "tezos") {
      return await auditTezosCollection(collection, context);
    }
    if (isEvmChain(collection.item.chain)) {
      return await auditEvmCollection(collection, context);
    }
    return failedCollectionResult(collection, [`unsupported chain ${collection.item.chain}`]);
  } catch (error) {
    return failedCollectionResult(collection, [error.message]);
  }
}

function failedCollectionResult(collection, failures) {
  return {
    id: collection.id,
    item: collection.item,
    tokenPath: collection.tokenPath,
    status: "failed",
    changed: false,
    changeCount: 0,
    originalTokenCount: collection.records.length,
    nextTokenCount: collection.records.length,
    apiTokenCount: 0,
    missingBundledTokenIds: [],
    extraBundledTokenIds: [],
    unsupportedApiTokenIds: [],
    missingApiMediaTokenIds: [],
    replacedFallbackItems: [],
    keptFallbackItems: [],
    duplicateUrlItems: [],
    warnings: [],
    failures,
    nextPayload: collection.payload,
    nextRecords: collection.records,
  };
}

async function auditSolanaCollection(collection, context) {
  const apiAssets = await getSolanaAssets(collection.item.address, context);
  const prepared = await prepareSolanaTokens(apiAssets, context);
  return buildAuditResult(collection, prepared, {
    chainKind: "solana",
    apiTokenCount: apiAssets.length,
  });
}

async function getSolanaAssets(collectionId, context) {
  const cacheKey = collectionId;
  if (context.solanaTokensByCollectionId.has(cacheKey)) {
    return context.solanaTokensByCollectionId.get(cacheKey);
  }

  const pages = [];
  let page = 1;
  for (;;) {
    const response = await heliusRpc("getAssetsByGroup", {
      groupKey: "collection",
      groupValue: collectionId,
      page,
      limit: context.options.limit,
      options: {
        showCollectionMetadata: true,
        showUnverifiedCollections: true,
        showGrandTotal: page === 1,
      },
    }, context);
    const items = response.items ?? [];
    pages.push(...items.filter((asset) => asset && !asset.burnt));
    if (context.options.verbose) {
      console.error(`  Helius ${collectionId} page ${page}: ${items.length}`);
    }
    if (items.length < context.options.limit) {
      break;
    }
    page += 1;
  }

  context.solanaTokensByCollectionId.set(cacheKey, pages);
  return pages;
}

async function heliusRpc(method, params, context) {
  const url = `${HELIUS_MAINNET_URL}?api-key=${encodeURIComponent(context.heliusApiKey)}`;
  const body = JSON.stringify({
    jsonrpc: "2.0",
    id: `${method}-${Date.now()}`,
    method,
    params,
  });

  for (let attempt = 0; ; attempt += 1) {
    await waitForSlot(context, "lastHeliusCallAt");
    const result = await fetchJson(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    }, context, "Helius");
    if (result.error) {
      if (TRANSIENT_RPC_CODES.has(result.error.code) && attempt < context.options.maxRetries) {
        await sleep(retryDelayMs(attempt));
        continue;
      }
      throw new Error(`Helius RPC ${result.error.code} for ${method}: ${result.error.message}`);
    }
    return result.result;
  }
}

async function prepareSolanaTokens(assets, context) {
  const results = await mapConcurrent(assets, context.options.mediaProbeConcurrency, async (asset) => {
    const candidates = await resolveCandidateMedia(mediaCandidatesForSolanaAsset(asset), "solana", context);
    const selected = chooseBestCandidate(candidates, "solana");
    if (!selected) {
      return {
        kind: candidates.length > 0 ? "unsupported" : "missing",
        id: asset.id,
      };
    }
    return {
      kind: "token",
      token: {
        id: asset.id,
        name: asset.content?.metadata?.name ?? null,
        media: selected,
        candidates,
        sortKey: solanaSortKey(asset, selected),
      },
    };
  });

  const tokens = [];
  const unsupported = [];
  const missingMedia = [];
  for (const result of results) {
    if (!result) {
      continue;
    }
    if (result.kind === "token") {
      tokens.push(result.token);
    } else if (result.kind === "unsupported") {
      unsupported.push(result.id);
    } else if (result.kind === "missing") {
      missingMedia.push(result.id);
    }
  }
  tokens.sort(compareSolanaPreparedTokens);
  return dedupePreparedTokens(tokens, unsupported, missingMedia, context);
}

function mediaCandidatesForSolanaAsset(asset) {
  const candidates = [];
  for (const file of asset.content?.files ?? []) {
    appendCandidate(candidates, {
      url: file.uri,
      mime: file.mime,
      source: "content.files.uri",
      sourceRank: 0,
      chainKind: "solana",
    });
  }
  appendCandidate(candidates, {
    url: asset.content?.links?.animation_url,
    mime: null,
    source: "content.links.animation_url",
    sourceRank: 2,
    chainKind: "solana",
  });
  appendCandidate(candidates, {
    url: asset.content?.links?.image,
    mime: null,
    source: "content.links.image",
    sourceRank: 3,
    chainKind: "solana",
  });
  return uniqueCandidates(candidates);
}

function solanaSortKey(asset, selected) {
  const name = asset.content?.metadata?.name ?? "";
  const basename = urlLastPathComponent(selected.url);
  return {
    numericName: numericTokenIdFromName(name),
    numericBasename: numericTokenIdFromBasename(basename),
    basename,
    id: asset.id,
  };
}

function compareSolanaPreparedTokens(left, right) {
  return compareNullableBigInts(left.sortKey.numericName, right.sortKey.numericName)
    || compareNullableBigInts(left.sortKey.numericBasename, right.sortKey.numericBasename)
    || naturalCompare(left.sortKey.basename, right.sortKey.basename)
    || naturalCompare(left.id, right.id);
}

async function auditTezosCollection(collection, context) {
  const apiTokens = await getTezosTokens(collection.item.address, context);
  const prepared = await prepareTezosTokens(apiTokens, context);
  return buildAuditResult(collection, prepared, {
    chainKind: "tezos",
    apiTokenCount: apiTokens.length,
  });
}

async function getTezosTokens(contract, context) {
  if (context.tezosTokensByContract.has(contract)) {
    return context.tezosTokensByContract.get(contract);
  }
  const tokens = [];
  let offset = 0;
  for (;;) {
    const url = new URL(`${context.options.tzktApiBaseUrl}/v1/tokens`);
    url.searchParams.set("contract", contract);
    url.searchParams.set("limit", String(context.options.limit));
    url.searchParams.set("offset", String(offset));
    await waitForSlot(context, "lastTzktCallAt");
    const page = await fetchJson(url, {}, context, "TzKT");
    const items = Array.isArray(page) ? page : [];
    tokens.push(...items);
    if (context.options.verbose) {
      console.error(`  TzKT ${contract} offset ${offset}: ${items.length}`);
    }
    if (items.length < context.options.limit) {
      break;
    }
    offset += context.options.limit;
  }
  tokens.sort((left, right) =>
    compareNullableBigInts(numericTokenId(tezosTokenId(left)), numericTokenId(tezosTokenId(right)))
    || naturalCompare(tezosTokenId(left), tezosTokenId(right))
  );
  context.tezosTokensByContract.set(contract, tokens);
  return tokens;
}

async function prepareTezosTokens(apiTokens, context) {
  const results = await mapConcurrent(apiTokens, context.options.mediaProbeConcurrency, async (token) => {
    const id = tezosTokenId(token);
    const candidates = await resolveCandidateMedia(mediaCandidatesForTezosToken(token), "tezos", context);
    const selected = chooseBestCandidate(candidates, "tezos");
    if (!selected) {
      return {
        kind: candidates.length > 0 ? "unsupported" : "missing",
        id,
      };
    }
    return {
      kind: "token",
      token: {
        id,
        name: token.metadata?.name ?? null,
        media: selected,
        candidates,
        sortKey: tezosSortKey(token, selected),
      },
    };
  });

  const tokens = [];
  const unsupported = [];
  const missingMedia = [];
  for (const result of results) {
    if (!result) {
      continue;
    }
    if (result.kind === "token") {
      tokens.push(result.token);
    } else if (result.kind === "unsupported") {
      unsupported.push(result.id);
    } else if (result.kind === "missing") {
      missingMedia.push(result.id);
    }
  }
  tokens.sort(compareTezosPreparedTokens);
  return dedupePreparedTokens(tokens, unsupported, missingMedia, context);
}

function mediaCandidatesForTezosToken(token) {
  const metadata = token.metadata ?? {};
  const candidates = [];
  const artifactURL = normalizeTezosAssetURL(metadata.artifactUri);
  const displayURL = normalizeTezosAssetURL(metadata.displayUri ?? metadata.image);
  const thumbnailURL = normalizeTezosAssetURL(metadata.thumbnailUri);

  for (const format of metadata.formats ?? []) {
    const normalizedURL = normalizeTezosAssetURL(format.uri);
    let source = "formats.uri";
    let sourceRank = 1;
    if (normalizedURL && artifactURL && normalizedURL === artifactURL) {
      source = "formats.artifactUri";
      sourceRank = 0;
    } else if (normalizedURL && displayURL && normalizedURL === displayURL) {
      source = "formats.displayUri";
      sourceRank = 2;
    } else if (normalizedURL && thumbnailURL && normalizedURL === thumbnailURL) {
      source = "formats.thumbnailUri";
      sourceRank = 4;
    }
    appendCandidate(candidates, {
      url: format.uri,
      mime: format.mimeType,
      source,
      sourceRank,
      chainKind: "tezos",
    });
  }

  appendCandidate(candidates, {
    url: metadata.artifactUri,
    mime: metadata.mimeType ?? metadata.mime,
    source: "artifactUri",
    sourceRank: 0,
    chainKind: "tezos",
  });
  appendCandidate(candidates, {
    url: metadata.displayUri,
    mime: null,
    source: "displayUri",
    sourceRank: 2,
    chainKind: "tezos",
  });
  appendCandidate(candidates, {
    url: metadata.image,
    mime: null,
    source: "image",
    sourceRank: 3,
    chainKind: "tezos",
  });
  appendCandidate(candidates, {
    url: metadata.thumbnailUri,
    mime: null,
    source: "thumbnailUri",
    sourceRank: 4,
    chainKind: "tezos",
  });
  return uniqueCandidates(candidates);
}

function tezosSortKey(token, selected) {
  const id = tokenId(token);
  const name = token.metadata?.name ?? "";
  const basename = urlLastPathComponent(selected.url);
  return {
    numericId: numericTokenId(id),
    numericName: numericTokenIdFromName(name),
    numericBasename: numericTokenIdFromBasename(basename),
    basename,
    id,
  };
}

function compareTezosPreparedTokens(left, right) {
  return compareNullableBigInts(left.sortKey.numericId, right.sortKey.numericId)
    || compareNullableBigInts(left.sortKey.numericName, right.sortKey.numericName)
    || compareNullableBigInts(left.sortKey.numericBasename, right.sortKey.numericBasename)
    || naturalCompare(left.sortKey.basename, right.sortKey.basename)
    || naturalCompare(left.id, right.id);
}

async function auditEvmCollection(collection, context) {
  const target = evmTargetForItem(collection.item);
  const slugScopedTokens = await getEvmSlugScopedTokens(collection, target, context);
  if (slugScopedTokens.ok) {
    const prepared = await prepareEvmTokens(slugScopedTokens.tokens, context);
    return buildAuditResult(collection, prepared, {
      chainKind: "evm",
      apiTokenCount: slugScopedTokens.tokens.length,
      selection: slugScopedTokens.selection,
    });
  }

  const allTokens = await getEvmContractTokens(target, context);
  const selectedTokens = selectEvmTokensForCollection(collection, allTokens);
  if (!selectedTokens.ok) {
    return failedCollectionResult(collection, [selectedTokens.error]);
  }

  const prepared = await prepareEvmTokens(selectedTokens.tokens, context);
  return buildAuditResult(collection, prepared, {
    chainKind: "evm",
    apiTokenCount: selectedTokens.tokens.length,
    selection: selectedTokens.selection,
  });
}

async function getEvmSlugScopedTokens(collection, target, context) {
  const slug = await discoverOpenSeaCollectionSlug(collection, target, context);
  if (!slug) {
    return {
      ok: false,
      error: "could not discover OpenSea collection slug from bundled token ids",
    };
  }
  const tokens = await getOpenSeaCollectionTokens(slug, target, context);
  if (tokens.length === 0) {
    return {
      ok: false,
      error: `OpenSea collection slug ${slug} returned no tokens for ${target.address}`,
    };
  }
  const bundledIds = new Set(collection.records.map((record) => record.id));
  const matchedBundled = tokens.filter((token) => bundledIds.has(tokenId(token))).length;
  if (matchedBundled === 0) {
    return {
      ok: false,
      error: `OpenSea collection slug ${slug} did not match bundled token ids`,
    };
  }
  if (collection.item.abId != null) {
    const projectId = numericTokenId(collection.item.abId);
    const mismatched = tokens.filter((token) => artBlocksProjectIdForTokenId(tokenId(token)) !== projectId);
    if (projectId == null || mismatched.length > 0) {
      return {
        ok: false,
        error: `OpenSea collection slug ${slug} did not uniquely match Art Blocks project id ${collection.item.abId}`,
      };
    }
  }
  return {
    ok: true,
    tokens,
    selection: {
      kind: "opensea-token-slug",
      value: slug,
      matchedBundled,
    },
  };
}

async function discoverOpenSeaCollectionSlug(collection, target, context) {
  for (const record of sampleRecordsForSlugDiscovery(collection.records)) {
    const nft = await getOpenSeaNft(target, record.id, context).catch((error) => {
      if (context.options.verbose) {
        console.error(`  OpenSea token slug lookup failed for ${record.id}: ${error.message}`);
      }
      return null;
    });
    const slug = nft?.collection;
    if (slug) {
      return slug;
    }
  }
  return null;
}

function sampleRecordsForSlugDiscovery(records) {
  if (records.length <= 8) {
    return records;
  }
  const indexes = new Set([0, 1, 2, records.length - 1]);
  indexes.add(Math.floor(records.length / 2));
  return [...indexes]
    .filter((index) => records[index])
    .sort((left, right) => left - right)
    .map((index) => records[index]);
}

function evmTargetForItem(item) {
  const chain = normalizeChainKey(item.chain);
  const config = EVM_CHAIN_CONFIGS.get(chain);
  if (!config) {
    throw new Error(`unsupported EVM chain ${item.chain}`);
  }
  return {
    ...config,
    address: String(item.address).toLowerCase(),
    appChain: chain,
  };
}

function isEvmChain(chain) {
  return EVM_CHAIN_CONFIGS.has(normalizeChainKey(chain));
}

async function getEvmContractTokens(target, context) {
  const cacheKey = `${target.openSeaChain}:${target.address}`;
  if (context.evmTokensByTarget.has(cacheKey)) {
    return context.evmTokensByTarget.get(cacheKey);
  }

  const tokens = [];
  let nextCursor = null;
  let page = 0;
  do {
    const url = new URL(`${OPENSEA_API_BASE_URL}/chain/${target.openSeaChain}/contract/${target.address}/nfts`);
    url.searchParams.set("limit", String(context.options.openSeaLimit));
    if (nextCursor) {
      url.searchParams.set("next", nextCursor);
    }
    await waitForSlot(context, "lastOpenSeaCallAt");
    const body = await fetchJson(url, {
      headers: {
        accept: "application/json",
        "x-api-key": context.openSeaApiKey,
        "User-Agent": "nft-player-bundled-source-audit/1.0",
      },
    }, context, "OpenSea");
    const pageTokens = Array.isArray(body.nfts) ? body.nfts : [];
    tokens.push(...pageTokens);
    nextCursor = body.next ?? null;
    page += 1;
    if (context.options.verbose) {
      console.error(`  OpenSea ${cacheKey} page ${page}: ${pageTokens.length}, total ${tokens.length}${nextCursor ? ", more" : ""}`);
    }
  } while (nextCursor);

  context.evmTokensByTarget.set(cacheKey, tokens);
  return tokens;
}

async function getOpenSeaNft(target, tokenIdValue, context) {
  const cacheKey = `${target.openSeaChain}:${target.address}:${tokenIdValue}`;
  if (context.evmNftByTargetId.has(cacheKey)) {
    return context.evmNftByTargetId.get(cacheKey);
  }
  const url = new URL(`${OPENSEA_API_BASE_URL}/chain/${target.openSeaChain}/contract/${target.address}/nfts/${encodeURIComponent(tokenIdValue)}`);
  await waitForSlot(context, "lastOpenSeaCallAt");
  const body = await fetchJson(url, {
    headers: {
      accept: "application/json",
      "x-api-key": context.openSeaApiKey,
      "User-Agent": "nft-player-bundled-source-audit/1.0",
    },
  }, context, "OpenSea");
  const nft = body.nft ?? null;
  context.evmNftByTargetId.set(cacheKey, nft);
  return nft;
}

async function getOpenSeaCollectionTokens(slug, target, context) {
  const cacheKey = `${target.openSeaChain}:${target.address}:${slug}`;
  if (context.evmTokensBySlug.has(cacheKey)) {
    return context.evmTokensBySlug.get(cacheKey);
  }

  const tokens = [];
  let nextCursor = null;
  let page = 0;
  do {
    const url = new URL(`${OPENSEA_API_BASE_URL}/collection/${encodeURIComponent(slug)}/nfts`);
    url.searchParams.set("limit", String(context.options.openSeaLimit));
    if (nextCursor) {
      url.searchParams.set("next", nextCursor);
    }
    await waitForSlot(context, "lastOpenSeaCallAt");
    const body = await fetchJson(url, {
      headers: {
        accept: "application/json",
        "x-api-key": context.openSeaApiKey,
        "User-Agent": "nft-player-bundled-source-audit/1.0",
      },
    }, context, "OpenSea");
    const pageTokens = (Array.isArray(body.nfts) ? body.nfts : [])
      .filter((token) => String(token.contract ?? "").toLowerCase() === target.address);
    tokens.push(...pageTokens);
    nextCursor = body.next ?? null;
    page += 1;
    if (context.options.verbose) {
      console.error(`  OpenSea collection ${slug} page ${page}: ${pageTokens.length}, total ${tokens.length}${nextCursor ? ", more" : ""}`);
    }
  } while (nextCursor);

  context.evmTokensBySlug.set(cacheKey, tokens);
  return tokens;
}

function selectEvmTokensForCollection(collection, allTokens) {
  const item = collection.item;
  const bundledIds = new Set(collection.records.map((record) => record.id));
  if (item.abId != null) {
    const projectId = numericTokenId(item.abId);
    if (projectId == null) {
      return {
        ok: false,
        error: `invalid Art Blocks project id ${item.abId}`,
      };
    }
    const tokens = allTokens.filter((token) => artBlocksProjectIdForTokenId(tokenId(token)) === projectId);
    const tokenIds = new Set(tokens.map(tokenId));
    const matchedBundled = [...bundledIds].filter((id) => tokenIds.has(id)).length;
    if (tokens.length === 0 || matchedBundled === 0) {
      return {
        ok: false,
        error: `could not match Art Blocks project id ${item.abId} in OpenSea contract response`,
      };
    }
    return {
      ok: true,
      tokens,
      selection: {
        kind: "abId-project-id",
        value: String(item.abId),
        matchedBundled,
      },
    };
  }

  const slugs = new Map();
  for (const token of allTokens) {
    const slug = token.collection ?? "";
    if (!slug) {
      continue;
    }
    const bucket = slugs.get(slug) ?? { slug, tokens: [], matchedBundled: 0 };
    bucket.tokens.push(token);
    if (bundledIds.has(tokenId(token))) {
      bucket.matchedBundled += 1;
    }
    slugs.set(slug, bucket);
  }
  const matchingSlugs = [...slugs.values()]
    .filter((entry) => entry.matchedBundled > 0)
    .sort((left, right) =>
      right.matchedBundled - left.matchedBundled
      || Math.abs(left.tokens.length - collection.records.length) - Math.abs(right.tokens.length - collection.records.length)
      || naturalCompare(left.slug, right.slug)
    );

  if (matchingSlugs.length === 1) {
    return {
      ok: true,
      tokens: matchingSlugs[0].tokens,
      selection: {
        kind: "opensea-collection-slug",
        value: matchingSlugs[0].slug,
        matchedBundled: matchingSlugs[0].matchedBundled,
      },
    };
  }

  const exactSlugs = matchingSlugs.filter((entry) =>
    entry.matchedBundled === bundledIds.size
    || entry.tokens.length === collection.records.length
    || normalizeSlug(entry.slug).includes(normalizeSlug(item.name))
  );
  if (exactSlugs.length === 1) {
    return {
      ok: true,
      tokens: exactSlugs[0].tokens,
      selection: {
        kind: "opensea-collection-slug",
        value: exactSlugs[0].slug,
        matchedBundled: exactSlugs[0].matchedBundled,
      },
    };
  }

  if (matchingSlugs.length === 0) {
    if (allTokens.length === collection.records.length) {
      return {
        ok: true,
        tokens: allTokens,
        selection: {
          kind: "full-contract",
          value: item.address,
          matchedBundled: collection.records.length,
        },
      };
    }
    return {
      ok: false,
      error: "could not infer OpenSea collection slug from bundled token ids",
    };
  }

  return {
    ok: false,
    error: `ambiguous OpenSea collection slug: ${matchingSlugs.slice(0, 5).map((entry) => `${entry.slug} (${entry.matchedBundled}/${entry.tokens.length})`).join(", ")}`,
  };
}

function normalizeSlug(value) {
  return String(value ?? "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/gu, "-")
    .replace(/^-|-$/gu, "");
}

function artBlocksProjectIdForTokenId(value) {
  const numeric = numericTokenId(value);
  if (numeric == null) {
    return null;
  }
  return numeric / 1000000n;
}

async function prepareEvmTokens(tokens, context) {
  const results = await mapConcurrent(tokens, context.options.mediaProbeConcurrency, async (token) => {
    const id = tokenId(token);
    if (!id) {
      return null;
    }
    const candidates = await resolveCandidateMedia(mediaCandidatesForEvmToken(token), "evm", context);
    const selected = chooseBestCandidate(candidates, "evm");
    if (!selected) {
      return {
        kind: candidates.length > 0 ? "unsupported" : "missing",
        id,
      };
    }
    return {
      kind: "token",
      token: {
        id,
        name: token.name ?? null,
        media: selected,
        candidates,
        sortKey: evmSortKey(token, selected),
      },
    };
  });

  const prepared = [];
  const unsupported = [];
  const missingMedia = [];
  for (const result of results) {
    if (!result) {
      continue;
    }
    if (result.kind === "token") {
      prepared.push(result.token);
    } else if (result.kind === "unsupported") {
      unsupported.push(result.id);
    } else if (result.kind === "missing") {
      missingMedia.push(result.id);
    }
  }
  prepared.sort(compareEvmPreparedTokens);
  return dedupePreparedTokens(prepared, unsupported, missingMedia, context);
}

function mediaCandidatesForEvmToken(token) {
  const candidates = [];
  appendCandidate(candidates, {
    url: token.original_animation_url ?? token.originalAnimationUrl,
    mime: null,
    source: "original_animation_url",
    sourceRank: 0,
    chainKind: "evm",
  });
  appendCandidate(candidates, {
    url: token.original_image_url ?? token.originalImageUrl,
    mime: null,
    source: "original_image_url",
    sourceRank: 1,
    chainKind: "evm",
  });

  const metadata = token.metadata ?? token.raw_metadata ?? token.rawMetadata;
  if (metadata && typeof metadata === "object") {
    appendCandidate(candidates, {
      url: metadata.animation_url ?? metadata.animationUrl,
      mime: metadata.mime_type ?? metadata.mimeType ?? metadata.mime,
      source: "metadata.animation_url",
      sourceRank: 2,
      chainKind: "evm",
    });
    appendCandidate(candidates, {
      url: metadata.image,
      mime: metadata.mime_type ?? metadata.mimeType ?? metadata.mime,
      source: "metadata.image",
      sourceRank: 3,
      chainKind: "evm",
    });
  }

  appendCandidate(candidates, {
    url: token.display_animation_url ?? token.displayAnimationUrl,
    mime: null,
    source: "display_animation_url",
    sourceRank: 4,
    chainKind: "evm",
  });
  appendCandidate(candidates, {
    url: token.animation_url ?? token.animationUrl,
    mime: null,
    source: "animation_url",
    sourceRank: 5,
    chainKind: "evm",
  });
  appendCandidate(candidates, {
    url: token.image_url ?? token.imageUrl,
    mime: null,
    source: "image_url",
    sourceRank: 6,
    chainKind: "evm",
  });
  appendCandidate(candidates, {
    url: token.display_image_url ?? token.displayImageUrl,
    mime: null,
    source: "display_image_url",
    sourceRank: 7,
    chainKind: "evm",
  });
  return uniqueCandidates(candidates);
}

async function resolveCandidateMedia(candidates, chainKind, context) {
  const trustedKnownCandidates = candidates.filter((candidate) => {
    const initialExtension = normalizeExtension(candidate.extension);
    return initialExtension
      && initialExtension !== "unknown"
      && isTrustedSourceCandidate({
        ...candidate,
        extension: initialExtension,
      }, chainKind);
  });
  if (trustedKnownCandidates.length > 0) {
    const trustedResolvedByURL = new Map(await Promise.all(trustedKnownCandidates.map(async (candidate) => {
      const initialExtension = normalizeExtension(candidate.extension);
      const contentType = await contentTypeForURL(candidate.url, context);
      if (contentType === MEDIA_PROBE_TIMEOUT) {
        return [candidate.url, {
          ...candidate,
          extension: initialExtension,
          reachable: "unknown",
        }];
      }
      const resolvedExtension = extensionForContentType(contentType) ?? initialExtension;
      return [candidate.url, {
        ...candidate,
        mime: candidate.mime ?? contentType,
        extension: resolvedExtension,
        reachable: Boolean(contentType) && supportedExtensions(chainKind).has(resolvedExtension),
      }];
    })));

    return candidates.map((candidate) => {
      const initialExtension = normalizeExtension(candidate.extension);
      if (!initialExtension || initialExtension === "unknown") {
        return candidate;
      }
      if (!supportedExtensions(chainKind).has(initialExtension)) {
        return candidate;
      }
      return trustedResolvedByURL.get(candidate.url) ?? candidate;
    });
  }

  const resolved = await Promise.all(candidates.map(async (candidate) => {
    const initialExtension = normalizeExtension(candidate.extension);
    if (initialExtension && initialExtension !== "unknown" && !supportedExtensions(chainKind).has(initialExtension)) {
      return candidate;
    }
    if (initialExtension && initialExtension !== "unknown" && isTrustedSourceCandidate({
      ...candidate,
      extension: initialExtension,
    }, chainKind)) {
      return {
        ...candidate,
        extension: initialExtension,
        reachable: true,
      };
    }

    const contentType = await contentTypeForURL(candidate.url, context);
    if (contentType === MEDIA_PROBE_TIMEOUT) {
      return {
        ...candidate,
        reachable: "unknown",
      };
    }
    const extension = extensionForContentType(contentType);
    const resolvedExtension = extension ?? (initialExtension === "unknown" ? null : initialExtension);
    if (!contentType || !resolvedExtension) {
      return {
        ...candidate,
        reachable: false,
      };
    }
    return {
      ...candidate,
      mime: candidate.mime ?? contentType,
      extension: resolvedExtension,
      reachable: supportedExtensions(chainKind).has(resolvedExtension),
    };
  }));
  return uniqueCandidates(resolved);
}

function evmSortKey(token, selected) {
  const id = tokenId(token);
  const name = token.name ?? "";
  const basename = urlLastPathComponent(selected.url);
  return {
    numericId: numericTokenId(id),
    numericName: numericTokenIdFromName(name),
    numericBasename: numericTokenIdFromBasename(basename),
    basename,
    id,
  };
}

function compareEvmPreparedTokens(left, right) {
  return compareNullableBigInts(left.sortKey.numericId, right.sortKey.numericId)
    || compareNullableBigInts(left.sortKey.numericName, right.sortKey.numericName)
    || compareNullableBigInts(left.sortKey.numericBasename, right.sortKey.numericBasename)
    || naturalCompare(left.sortKey.basename, right.sortKey.basename)
    || naturalCompare(left.id, right.id);
}

function dedupePreparedTokens(tokens, unsupported, missingMedia, context) {
  const kept = [];
  const duplicateUrlItems = [];
  const seen = new Map();
  for (const token of tokens) {
    const existing = seen.get(token.media.url);
    if (existing) {
      duplicateUrlItems.push({
        id: token.id,
        name: token.name,
        keptId: existing.id,
        keptName: existing.name,
        url: token.media.url,
      });
      continue;
    }
    seen.set(token.media.url, {
      id: token.id,
      name: token.name,
    });
    kept.push(token);
  }

  return {
    tokens: kept,
    unsupportedTokenIds: unsupported,
    missingMediaTokenIds: missingMedia,
    duplicateUrlItems,
  };
}

function buildAuditResult(collection, prepared, extra) {
  const apiById = new Map(prepared.tokens.map((token) => [token.id, token]));
  const bundledById = new Map(collection.records.map((record) => [record.id, record]));
  const missingBundledTokenIds = prepared.tokens
    .filter((token) => !bundledById.has(token.id))
    .map((token) => token.id);
  const extraBundledTokenIds = collection.records
    .filter((record) => !apiById.has(record.id))
    .map((record) => record.id);
  const apiInventoryIncomplete = extraBundledTokenIds.length > 0 && prepared.tokens.length < collection.records.length;
  if (apiInventoryIncomplete) {
    const { nextRecords, replacedFallbackItems, keptFallbackItems, rowChanges } = buildReplacementsForExistingRows(collection, apiById, extra.chainKind);
    const changed = rowChanges.length > 0;
    return {
      id: collection.id,
      item: collection.item,
      tokenPath: collection.tokenPath,
      status: changed ? "changed-api-incomplete" : "api-incomplete",
      changed,
      changeCount: rowChanges.length,
      originalTokenCount: collection.records.length,
      nextTokenCount: collection.records.length,
      apiTokenCount: extra.apiTokenCount,
      selection: extra.selection ?? null,
      missingBundledTokenIds,
      extraBundledTokenIds,
      unsupportedApiTokenIds: prepared.unsupportedTokenIds,
      missingApiMediaTokenIds: prepared.missingMediaTokenIds,
      replacedFallbackItems,
      keptFallbackItems,
      duplicateUrlItems: prepared.duplicateUrlItems,
      warnings: [
        changed
          ? `API returned ${prepared.tokens.length} app-supported token(s), fewer than the ${collection.records.length} bundled row(s); preserving existing row set and applying only safe replacements for matched token ids.`
          : `API returned ${prepared.tokens.length} app-supported token(s), fewer than the ${collection.records.length} bundled row(s); preserving existing bundle rows and skipping rewrites for this collection.`,
      ],
      failures: [],
      rowChanges,
      nextPayload: changed ? buildTokenPayload(nextRecords) : collection.payload,
      nextRecords,
    };
  }
  const nextRecordById = new Map();
  const replacedFallbackItems = [];
  const keptFallbackItems = [];
  const rowChanges = [];

  for (const token of prepared.tokens) {
    const current = bundledById.get(token.id);
    if (!current) {
      nextRecordById.set(token.id, recordFromPreparedToken(token, collection.item));
      rowChanges.push({
        id: token.id,
        kind: "missing-bundled-token",
        nextUrl: token.media.url,
        nextSource: token.media.source,
      });
      continue;
    }

    const comparison = compareBundledRecordToPreparedToken(current, token, extra.chainKind);
    if (comparison.shouldReplace) {
      nextRecordById.set(token.id, recordFromPreparedToken(token, collection.item, current.name));
      replacedFallbackItems.push({
        id: token.id,
        name: token.name ?? current.name ?? null,
        previousUrl: current.url,
        previousSourceKind: current.sourceKind,
        nextUrl: token.media.url,
        nextSource: token.media.source,
        reason: comparison.reason,
      });
      rowChanges.push({
        id: token.id,
        kind: "replace-fallback-media",
        reason: comparison.reason,
      });
    } else {
      nextRecordById.set(token.id, current);
      if (comparison.fallbackKept) {
        keptFallbackItems.push({
          id: token.id,
          name: token.name ?? current.name ?? null,
          url: current.url,
          sourceKind: current.sourceKind,
          bestSource: token.media.source,
          reason: comparison.reason,
        });
      }
    }
  }

  const nextRecords = [];
  const emittedIds = new Set();
  for (const record of collection.records) {
    const nextRecord = nextRecordById.get(record.id);
    nextRecords.push(nextRecord ?? record);
    emittedIds.add(record.id);
  }
  for (const token of prepared.tokens) {
    if (emittedIds.has(token.id)) {
      continue;
    }
    nextRecords.push(nextRecordById.get(token.id) ?? recordFromPreparedToken(token, collection.item));
    emittedIds.add(token.id);
  }

  const nextPayload = buildTokenPayload(nextRecords);
  const changed = rowChanges.length > 0 || nextRecords.length !== collection.records.length;
  return {
    id: collection.id,
    item: collection.item,
    tokenPath: collection.tokenPath,
    status: changed ? "changed" : "ok",
    changed,
    changeCount: rowChanges.length,
    originalTokenCount: collection.records.length,
    nextTokenCount: nextRecords.length,
    apiTokenCount: extra.apiTokenCount,
    selection: extra.selection ?? null,
    missingBundledTokenIds,
    extraBundledTokenIds,
    unsupportedApiTokenIds: prepared.unsupportedTokenIds,
    missingApiMediaTokenIds: prepared.missingMediaTokenIds,
    replacedFallbackItems,
    keptFallbackItems,
    duplicateUrlItems: prepared.duplicateUrlItems,
    warnings: [],
    failures: [],
    rowChanges,
    nextPayload,
    nextRecords,
  };
}

function buildReplacementsForExistingRows(collection, apiById, chainKind) {
  const replacedFallbackItems = [];
  const keptFallbackItems = [];
  const rowChanges = [];
  const nextRecords = collection.records.map((record) => {
    const token = apiById.get(record.id);
    if (!token) {
      return record;
    }
    const comparison = compareBundledRecordToPreparedToken(record, token, chainKind);
    if (!comparison.shouldReplace) {
      if (comparison.fallbackKept) {
        keptFallbackItems.push({
          id: record.id,
          name: token.name ?? record.name ?? null,
          url: record.url,
          sourceKind: record.sourceKind,
          bestSource: token.media.source,
          reason: comparison.reason,
        });
      }
      return record;
    }

    replacedFallbackItems.push({
      id: record.id,
      name: token.name ?? record.name ?? null,
      previousUrl: record.url,
      previousSourceKind: record.sourceKind,
      nextUrl: token.media.url,
      nextSource: token.media.source,
      reason: comparison.reason,
    });
    rowChanges.push({
      id: record.id,
      kind: "replace-fallback-media",
      reason: comparison.reason,
    });
    return recordFromPreparedToken(token, collection.item, record.name);
  });

  return {
    nextRecords,
    replacedFallbackItems,
    keptFallbackItems,
    rowChanges,
  };
}

function compareBundledRecordToPreparedToken(record, token, chainKind) {
  const currentUrl = normalizeComparableURL(record.url);
  const bestUrl = normalizeComparableURL(token.media.url);
  if (currentUrl && bestUrl && currentUrl === bestUrl) {
    return {
      shouldReplace: false,
      fallbackKept: false,
      reason: "current URL already matches selected source",
    };
  }

  const currentCandidate = token.candidates.find((candidate) => normalizeComparableURL(candidate.url) === currentUrl);
  if (currentCandidate && currentCandidate.rank > token.media.rank && bestUrl) {
    return {
      shouldReplace: true,
      fallbackKept: false,
      reason: `selected ${token.media.source} outranks bundled ${currentCandidate.source}`,
    };
  }

  if (currentCandidate?.reachable === false && bestUrl && !isTrustedSourceCandidate(currentCandidate, chainKind)) {
    return {
      shouldReplace: true,
      fallbackKept: false,
      reason: `bundled URL is unreachable; selected reachable ${token.media.source}`,
    };
  }

  if (record.sourceKind === "explicit-url" || record.sourceKind === "opensea-raw") {
    return {
      shouldReplace: false,
      fallbackKept: false,
      reason: "current explicit/source URL is kept because it is not a known fallback",
    };
  }

  const currentRank = bundledSourceQualityRank(record, chainKind);
  const bestRank = token.media.rank;
  if (currentRank > bestRank && bestUrl) {
    return {
      shouldReplace: true,
      fallbackKept: false,
      reason: `selected ${token.media.source} outranks bundled ${record.sourceKind}`,
    };
  }

  if (currentRank > 0) {
    return {
      shouldReplace: false,
      fallbackKept: true,
      reason: "bundled fallback kept because no strictly better selected source was available",
    };
  }

  return {
    shouldReplace: false,
    fallbackKept: false,
    reason: "current source is not lower quality than selected source",
  };
}

function bundledSourceQualityRank(record, chainKind) {
  if (record.sourceKind === "artblocks-media-proxy") {
    return 90;
  }
  if (record.sourceKind === "simplehash") {
    return 80;
  }
  if (record.sourceKind === "opensea-derivative") {
    return 70;
  }
  if (record.sourceKind === "helius-cdn") {
    return 70;
  }
  if (record.sourceKind === "permagate") {
    return 60;
  }
  if (chainKind === "solana" && record.sourceKind !== "explicit-url") {
    return 50;
  }
  return 0;
}

function recordFromPreparedToken(token, item, fallbackName = null) {
  return {
    rowKind: "generated",
    id: token.id,
    name: token.name ?? fallbackName ?? null,
    url: token.media.url,
    fileExtension: token.media.extension,
    sourceKind: sourceKindForBundledURL(token.media.url),
  };
}

function buildTokenPayload(records) {
  const urls = records.map((record) => record.url).filter(Boolean);
  const prefixes = buildUrlPrefixes(urls);
  const extensions = records.map((record) => record.fileExtension).filter(Boolean);
  const defaultFileExtension = mostCommonValue(extensions);
  return {
    defaultFileExtension,
    urlPrefixes: prefixes,
    items: records.map((record) => {
      const url = record.url ?? "";
      const prefixIndex = bestPrefixIndex(url, prefixes);
      const suffix = prefixIndex >= 0 ? url.slice(prefixes[prefixIndex].length) : url;
      const row = [record.id, Math.max(prefixIndex, 0), suffix];
      if (record.fileExtension && record.fileExtension !== defaultFileExtension) {
        row.push(record.fileExtension);
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
  return bestIndex;
}

function mostCommonValue(values) {
  const counts = new Map();
  for (const value of values) {
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  return [...counts.entries()].sort((left, right) => right[1] - left[1] || naturalCompare(left[0], right[0]))[0]?.[0] ?? null;
}

async function applyAuditResults(loaded, audited) {
  const changed = audited.filter((collection) => collection.changed && collection.failures.length === 0);
  for (const collection of changed) {
    await fs.writeFile(collection.tokenPath, `${JSON.stringify(collection.nextPayload)}\n`);
  }

  if (changed.length > 0) {
    const changedById = new Map(changed.map((collection) => [collection.id, collection]));
    const nextItems = loaded.items.map((item) => {
      const id = suggestedItemId(item);
      const collection = changedById.get(id);
      if (!collection) {
        return item;
      }
      return {
        ...item,
        tokenCount: collection.nextTokenCount,
      };
    });
    await fs.writeFile(loaded.itemsPath, formatSuggestedItems(nextItems));
  }
}

function formatSuggestedItems(items) {
  return `${JSON.stringify(items, null, 2).replace(/"([^"]+)":/gu, "\"$1\" :")}\n`;
}

function appendCandidate(candidates, candidate) {
  const normalizedUrl = normalizeAssetURL(candidate.url, candidate.chainKind);
  if (!normalizedUrl) {
    return;
  }
  appendNormalizedCandidate(candidates, {
    ...candidate,
    url: normalizedUrl,
  });

  const rawOpenSeaURL = candidate.chainKind === "evm" ? rawOpenSeaMediaURL(normalizedUrl) : null;
  if (rawOpenSeaURL) {
    appendNormalizedCandidate(candidates, {
      ...candidate,
      url: rawOpenSeaURL,
      source: `raw2.${candidate.source}`,
      sourceRank: Math.min(candidate.sourceRank + 0.5, 3.5),
    });
  }
}

function appendNormalizedCandidate(candidates, candidate) {
  const extension = fileExtensionForURL(candidate.url, candidate.mime, candidate.chainKind);
  const rank = candidateRank({
    ...candidate,
    extension: extension ?? "unknown",
  }, candidate.chainKind);
  candidates.push({
    ...candidate,
    extension: extension ?? "unknown",
    rank,
  });
}

function normalizeAssetURL(urlString, chainKind) {
  if (!urlString || typeof urlString !== "string") {
    return null;
  }
  const trimmed = urlString.trim();
  if (!trimmed) {
    return null;
  }
  if (trimmed.startsWith("ipfs://")) {
    const pathPart = trimmed.slice("ipfs://".length).replace(/^ipfs\//u, "");
    return `${chainKind === "tezos" ? IPFS_GATEWAY_URL : APP_IPFS_GATEWAY_URL}${pathPart}`;
  }
  if (trimmed.startsWith("ar://")) {
    return `https://arweave.net/${trimmed.slice("ar://".length)}`;
  }
  if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
    return trimmed;
  }
  return null;
}

function normalizeTezosAssetURL(urlString) {
  return normalizeAssetURL(urlString, "tezos");
}

function fileExtensionForURL(urlString, mime, chainKind) {
  if (chainKind === "evm" && isKnownInteractiveGeneratorURL(urlString)) {
    return "interactive-html";
  }
  if (chainKind === "evm" && isKnownMathcastlesHTMLURL(urlString)) {
    return "html";
  }
  const urlExtension = extensionFromURL(urlString);
  const mimeExtension = extensionForContentType(mime);
  return normalizeExtension(urlExtension) ?? normalizeExtension(mimeExtension);
}

function extensionForContentType(contentType) {
  if (!contentType) {
    return null;
  }
  return normalizeExtension(EXTENSION_BY_MIME.get(String(contentType).toLowerCase().split(";")[0].trim()));
}

function chooseBestCandidate(candidates, chainKind) {
  const supported = candidates.filter((candidate) =>
    supportedExtensions(chainKind).has(candidate.extension)
    && (candidate.reachable === true || (
      candidate.reachable !== false
      && isTrustedSourceCandidate(candidate, chainKind)
    ))
  );
  if (supported.length === 0) {
    return null;
  }
  return [...supported].sort((left, right) =>
    candidateReachabilityRank(left) - candidateReachabilityRank(right)
    || left.rank - right.rank
    || candidateMediaRank(left, chainKind) - candidateMediaRank(right, chainKind)
    || naturalCompare(left.url, right.url)
  )[0];
}

function candidateReachabilityRank(candidate) {
  return candidate.reachable === true ? 0 : 1;
}

function isTrustedSourceCandidate(candidate, chainKind) {
  if (!candidate || !supportedExtensions(chainKind).has(candidate.extension)) {
    return false;
  }

  const source = String(candidate.source ?? "");
  if (chainKind === "solana") {
    return source === "content.files.uri" && Boolean(candidate.mime);
  }
  if (chainKind === "tezos") {
    return Boolean(candidate.mime) && (
      source === "artifactUri"
      || source === "formats.artifactUri"
      || source === "formats.uri"
    );
  }
  return source === "original_animation_url"
    || source === "original_image_url"
    || source === "metadata.animation_url"
    || source === "metadata.image"
    || source === "raw2.original_animation_url"
    || source === "raw2.original_image_url"
    || source === "raw2.metadata.animation_url"
    || source === "raw2.metadata.image";
}

function supportedExtensions(chainKind) {
  return chainKind === "evm" ? EVM_SUPPORTED_EXTENSIONS : SOLANA_TEZOS_SUPPORTED_EXTENSIONS;
}

function candidateRank(candidate, chainKind) {
  if (chainKind === "evm") {
    return evmCandidateRank(candidate);
  }
  return solanaTezosCandidateRank(candidate, chainKind);
}

function evmCandidateRank(candidate) {
  const source = String(candidate.source ?? "");
  let rank = Number(candidate.sourceRank ?? 50) * 10;
  if (VIDEO_EXTENSIONS.has(candidate.extension)) {
    rank -= 8;
  } else if (HTML_EXTENSIONS.has(candidate.extension)) {
    rank -= 6;
  } else if (ANIMATED_EXTENSIONS.has(candidate.extension)) {
    rank -= 5;
  }
  if (source.startsWith("raw2.")) {
    rank -= 2;
  }
  if (isOpenSeaDerivativeMediaURL(candidate.url)) {
    rank += 60;
  }
  return rank;
}

function solanaTezosCandidateRank(candidate, chainKind) {
  let rank = Number(candidate.sourceRank ?? 50) * 10;
  if (VIDEO_EXTENSIONS.has(candidate.extension)) {
    rank -= 8;
  } else if (SOLANA_TEZOS_ANIMATED_EXTENSIONS.has(candidate.extension)) {
    rank -= 6;
  } else if (STATIC_EXTENSIONS.has(candidate.extension)) {
    rank -= 5;
  }
  if (chainKind === "solana" && candidate.url.includes("cdn.helius-rpc.com")) {
    rank += 50;
  }
  return rank;
}

function candidateMediaRank(candidate, chainKind) {
  if (VIDEO_EXTENSIONS.has(candidate.extension)) {
    return 0;
  }
  if (chainKind === "evm" && HTML_EXTENSIONS.has(candidate.extension)) {
    return 1;
  }
  if (ANIMATED_EXTENSIONS.has(candidate.extension) || SOLANA_TEZOS_ANIMATED_EXTENSIONS.has(candidate.extension)) {
    return 2;
  }
  if (STATIC_EXTENSIONS.has(candidate.extension)) {
    return 3;
  }
  return 10;
}

function uniqueCandidates(candidates) {
  const unique = [];
  const indexByURL = new Map();
  for (const candidate of candidates) {
    const key = normalizeComparableURL(candidate.url) ?? candidate.url;
    const existingIndex = indexByURL.get(key);
    if (existingIndex == null) {
      indexByURL.set(key, unique.length);
      unique.push(candidate);
      continue;
    }
    const existing = unique[existingIndex];
    if (existing.reachable !== true && candidate.reachable === true) {
      unique[existingIndex] = candidate;
    } else if (existing.extension === "unknown" && candidate.extension !== "unknown") {
      unique[existingIndex] = candidate;
    } else if (candidate.rank < existing.rank) {
      unique[existingIndex] = candidate;
    }
  }
  return unique;
}

function normalizeComparableURL(urlString) {
  if (!urlString) {
    return null;
  }
  try {
    const url = new URL(urlString);
    const ipfsPathMatch = /^\/ipfs\/(.+)/u.exec(url.pathname);
    if (ipfsPathMatch && (
      url.hostname === "ipfs.io"
      || url.hostname === "ipfs.decentralized-content.com"
      || url.hostname === "gateway.lighthouse.storage"
    )) {
      return `ipfs://${ipfsPathMatch[1]}`;
    }
    url.hash = "";
    return url.toString();
  } catch {
    return String(urlString);
  }
}

async function contentTypeForURL(urlString, context) {
  if (context.contentTypeByURL.has(urlString)) {
    return context.contentTypeByURL.get(urlString);
  }
  const headContentType = await fetchContentType(urlString, "HEAD", context);
  const contentType = headContentType === MEDIA_PROBE_TIMEOUT
    ? await fetchContentType(urlString, "GET", context)
    : headContentType === null
    ? await fetchContentType(urlString, "GET", context)
    : headContentType;
  context.contentTypeByURL.set(urlString, contentType ?? null);
  return contentType;
}

async function fetchContentType(urlString, method, context) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Math.min(context.options.timeoutMs, MEDIA_PROBE_TIMEOUT_MS));
  try {
    const response = await fetch(urlString, {
      method,
      redirect: "follow",
      signal: controller.signal,
      headers: {
        accept: "image/*, text/html, application/xhtml+xml, video/mp4, video/*;q=0.8, */*;q=0.1",
        "User-Agent": "nft-player-bundled-source-audit/1.0",
        ...(method === "GET" ? { Range: "bytes=0-0" } : {}),
      },
    });
    await response.body?.cancel?.();
    if (!response.ok && response.status !== 206) {
      if (TRANSIENT_HTTP_STATUSES.has(response.status)) {
        return MEDIA_PROBE_TIMEOUT;
      }
      return null;
    }
    return response.headers.get("content-type");
  } catch (error) {
    return error?.name === "AbortError" ? MEDIA_PROBE_TIMEOUT : null;
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchJson(url, fetchOptions, context, providerName) {
  const urlString = url.toString();
  for (let attempt = 0; ; attempt += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), context.options.timeoutMs);
    try {
      const response = await fetch(urlString, {
        redirect: "follow",
        ...fetchOptions,
        signal: controller.signal,
        headers: {
          accept: "application/json",
          "User-Agent": "nft-player-bundled-source-audit/1.0",
          ...(fetchOptions.headers ?? {}),
        },
      });
      const text = await response.text();
      clearTimeout(timeout);
      if (!response.ok) {
        if (shouldRetryHttp(response.status, attempt, context.options)) {
          await sleep(retryDelayMs(attempt, response.headers.get("retry-after")));
          continue;
        }
        throw new Error(`${providerName} HTTP ${response.status} for ${urlString}: ${formatJsonErrorText(text)}`);
      }
      try {
        return JSON.parse(text);
      } catch (error) {
        throw new Error(`${providerName} JSON parse failed for ${urlString}: ${error.message}`);
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
    return Math.min(retryAfter, RETRY_DELAY_CAP_MS);
  }
  const exponential = Math.min(60000, 1000 * (2 ** Math.min(attempt, 6)));
  return Math.min(RETRY_DELAY_CAP_MS, exponential + Math.floor(Math.random() * 400));
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

function formatJsonErrorText(text) {
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
    // Return raw text below.
  }
  return text.trim().slice(0, 300);
}

async function waitForSlot(context, propertyName) {
  const elapsed = Date.now() - context[propertyName];
  if (elapsed < context.options.delayMs) {
    await sleep(context.options.delayMs - elapsed);
  }
  context[propertyName] = Date.now();
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function mapConcurrent(items, concurrency, mapper) {
  const results = new Array(items.length);
  let cursor = 0;
  async function worker() {
    for (;;) {
      const index = cursor;
      cursor += 1;
      if (index >= items.length) {
        return;
      }
      results[index] = await mapper(items[index], index);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, worker));
  return results;
}

function tokenId(token) {
  return String(token.identifier ?? token.id ?? token.token_id ?? token.tokenId ?? "");
}

function tezosTokenId(token) {
  return String(token.tokenId ?? token.id ?? "");
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
    const queryMatch = /[?&]ext=([a-z0-9]+)/iu.exec(String(urlString));
    if (queryMatch) {
      return queryMatch[1];
    }
    const pathMatch = /\.([a-z0-9]+)(?:[?#]|$)/iu.exec(String(urlString));
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

function isKnownInteractiveGeneratorURL(urlString) {
  try {
    return new URL(urlString).hostname === "generator.artblocks.io";
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

function isRawOpenSeaMediaURL(urlString) {
  try {
    return new URL(urlString).hostname === OPENSEA_RAW_MEDIA_HOST;
  } catch {
    return false;
  }
}

function numericTokenId(value) {
  const normalized = String(value);
  return /^\d+$/u.test(normalized) ? BigInt(normalized) : null;
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
  const numeric = /^0*(\d+)(?:\.[a-z0-9]+)?$/iu.exec(String(basename));
  return numeric ? BigInt(numeric[1]) : null;
}

function urlLastPathComponent(urlString) {
  try {
    const url = new URL(urlString);
    const basename = path.posix.basename(url.pathname);
    return basename || urlString;
  } catch {
    return path.posix.basename(String(urlString));
  }
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

async function writeReports(report) {
  const outputPath = path.resolve(report.options.reportPath);
  const jsonOutputPath = path.resolve(report.options.jsonReportPath);
  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  await fs.mkdir(path.dirname(jsonOutputPath), { recursive: true });
  await fs.writeFile(outputPath, renderMarkdownReport(report));
  await fs.writeFile(jsonOutputPath, `${JSON.stringify(reportableAudit(report), null, 2)}\n`);
  console.error(`Report written to ${outputPath}`);
  console.error(`JSON written to ${jsonOutputPath}`);
}

function summarize(collections, skipped, options) {
  return {
    generatedAt: new Date().toISOString(),
    mode: options.apply ? "apply" : "dry-run",
    auditedCollections: collections.length,
    skippedCollections: skipped.length,
    bundledGenerativeCollectionsSkipped: skipped.filter((collection) => collection.reason === BUNDLED_GENERATIVE_SKIP_REASON).length,
    changedCollections: collections.filter((collection) => collection.changed).length,
    failedCollections: collections.filter((collection) => collection.failures.length > 0).length,
    warningCollections: collections.filter((collection) => collection.warnings.length > 0).length,
    missingBundledTokens: collections.reduce((sum, collection) => sum + collection.missingBundledTokenIds.length, 0),
    replacedFallbackItems: collections.reduce((sum, collection) => sum + collection.replacedFallbackItems.length, 0),
    keptFallbackItems: collections.reduce((sum, collection) => sum + collection.keptFallbackItems.length, 0),
    unsupportedApiTokens: collections.reduce((sum, collection) => sum + collection.unsupportedApiTokenIds.length, 0),
    missingApiMediaTokens: collections.reduce((sum, collection) => sum + collection.missingApiMediaTokenIds.length, 0),
  };
}

function reportableAudit(report) {
  return {
    generatedAt: new Date().toISOString(),
    mode: report.options.apply ? "apply" : "dry-run",
    bundlePath: report.bundlePath,
    options: {
      chains: report.options.chains,
      collections: report.options.collections,
      includeCdnLil: report.options.includeCdnLil,
      limit: report.options.limit,
      openSeaLimit: report.options.openSeaLimit,
      timeoutMs: report.options.timeoutMs,
      delayMs: report.options.delayMs,
      mediaProbeConcurrency: report.options.mediaProbeConcurrency,
    },
    summary: summarize(report.collections, report.skipped, report.options),
    skipped: report.skipped,
    collections: report.collections.map(reportableCollection),
  };
}

function reportableCollection(collection) {
  return {
    id: collection.id,
    name: collection.item.name,
    address: collection.item.address,
    chain: collection.item.chain,
    abId: collection.item.abId ?? null,
    collectionId: collection.item.collectionId ?? null,
    status: collection.status,
    changed: collection.changed,
    originalTokenCount: collection.originalTokenCount,
    nextTokenCount: collection.nextTokenCount,
    apiTokenCount: collection.apiTokenCount,
    selection: collection.selection ?? null,
    missingBundledTokenIds: collection.missingBundledTokenIds,
    extraBundledTokenIds: collection.extraBundledTokenIds,
    unsupportedApiTokenIds: collection.unsupportedApiTokenIds,
    missingApiMediaTokenIds: collection.missingApiMediaTokenIds,
    duplicateUrlItems: collection.duplicateUrlItems,
    replacedFallbackItems: collection.replacedFallbackItems,
    keptFallbackItems: collection.keptFallbackItems.slice(0, 200),
    keptFallbackItemCount: collection.keptFallbackItems.length,
    failures: collection.failures,
    warnings: collection.warnings,
  };
}

function renderMarkdownReport(report) {
  const generatedAt = new Date().toISOString();
  const summary = summarize(report.collections, report.skipped, report.options);
  const failed = report.collections.filter((collection) => collection.failures.length > 0);
  const warnings = report.collections.filter((collection) => collection.warnings.length > 0);
  const changed = report.collections.filter((collection) => collection.changed);
  const missing = report.collections.filter((collection) => collection.missingBundledTokenIds.length > 0);
  const replaced = report.collections.filter((collection) => collection.replacedFallbackItems.length > 0);

  const lines = [];
  lines.push("# Bundled Collection Source Audit");
  lines.push("");
  lines.push(`Generated: ${generatedAt}`);
  lines.push(`Mode: ${report.options.apply ? "apply" : "dry-run"}`);
  lines.push("");
  lines.push("## Summary");
  lines.push("");
  lines.push(`- Audited collections: ${summary.auditedCollections}`);
  lines.push(`- Skipped collections: ${summary.skippedCollections}`);
  lines.push(`- Bundled generative collections skipped: ${summary.bundledGenerativeCollectionsSkipped}`);
  lines.push(`- Changed collections: ${summary.changedCollections}`);
  lines.push(`- Failed collections: ${summary.failedCollections}`);
  lines.push(`- Warning collections: ${summary.warningCollections}`);
  lines.push(`- Missing bundled API tokens: ${summary.missingBundledTokens}`);
  lines.push(`- Replaced fallback/downsampled rows: ${summary.replacedFallbackItems}`);
  lines.push(`- Kept fallback rows: ${summary.keptFallbackItems}`);
  lines.push(`- Unsupported API tokens: ${summary.unsupportedApiTokens}`);
  lines.push(`- API tokens without media: ${summary.missingApiMediaTokens}`);
  lines.push("");
  lines.push("## Collections");
  lines.push("");
  lines.push("| Collection | Chain | Status | API Tokens | Bundled -> Next | Missing | Replaced | Kept Fallback | Failures |");
  lines.push("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |");
  for (const collection of report.collections) {
    lines.push(`| ${escapeCell(collection.item.name)} | ${escapeCell(collection.item.chain)} | ${escapeCell(collection.status)} | ${collection.apiTokenCount} | ${collection.originalTokenCount} -> ${collection.nextTokenCount} | ${collection.missingBundledTokenIds.length} | ${collection.replacedFallbackItems.length} | ${collection.keptFallbackItems.length} | ${escapeCell(collection.failures.join("; "))} |`);
  }
  lines.push("");
  lines.push("## Skipped Collections");
  lines.push("");
  if (report.skipped.length === 0) {
    lines.push("None.");
  } else {
    lines.push("| Collection | Chain | ID | Reason |");
    lines.push("| --- | --- | --- | --- |");
    for (const item of report.skipped) {
      lines.push(`| ${escapeCell(item.name)} | ${escapeCell(item.chain)} | \`${escapeCell(item.id)}\` | ${escapeCell(item.reason)} |`);
    }
  }
  lines.push("");
  renderDetails(lines, "Failed Collections", failed, (collection) => collection.failures.map((failure) => `- ${escapeMarkdown(collection.item.name)}: ${escapeMarkdown(failure)}`));
  renderDetails(lines, "Warnings", warnings, (collection) => collection.warnings.map((warning) => `- ${escapeMarkdown(collection.item.name)}: ${escapeMarkdown(warning)}`));
  renderDetails(lines, "Missing Bundled Tokens", missing, (collection) => [
    `- ${escapeMarkdown(collection.item.name)} (${collection.id}): ${collection.missingBundledTokenIds.slice(0, 50).join(", ")}${collection.missingBundledTokenIds.length > 50 ? " ..." : ""}`,
  ]);
  renderDetails(lines, "Replaced Fallback Media", replaced, (collection) =>
    collection.replacedFallbackItems.slice(0, 50).map((item) =>
      `- ${escapeMarkdown(collection.item.name)} token ${escapeMarkdown(item.id)}: ${escapeMarkdown(item.previousSourceKind)} -> ${escapeMarkdown(item.nextSource)}`
    )
  );
  renderDetails(lines, "Changed Collections", changed, (collection) => [
    `- ${escapeMarkdown(collection.item.name)} (${collection.id}): ${collection.changeCount} change(s), ${collection.originalTokenCount} -> ${collection.nextTokenCount}`,
  ]);
  return `${lines.join("\n")}\n`;
}

function renderDetails(lines, heading, collections, renderer) {
  lines.push(`## ${heading}`);
  lines.push("");
  if (collections.length === 0) {
    lines.push("None.");
  } else {
    for (const collection of collections) {
      lines.push(...renderer(collection));
    }
  }
  lines.push("");
}

function escapeCell(value) {
  return String(value ?? "").replace(/\|/gu, "\\|").replace(/\n/gu, " ");
}

function escapeMarkdown(value) {
  return String(value ?? "").replace(/\*/gu, "\\*").replace(/_/gu, "\\_");
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message);
    console.error("");
    console.error(usage());
    process.exit(1);
  });
}

module.exports = {
  DEFAULT_HELIUS_API_KEY_PATH,
  DEFAULT_OPENSEA_API_KEY_PATH,
  TZKT_API_BASE_URL,
  buildTokenPayload,
  evmTargetForItem,
  extensionForContentType,
  fileExtensionForURL,
  formatSuggestedItems,
  getOpenSeaNft,
  getEvmContractTokens,
  getEvmSlugScopedTokens,
  getTezosTokens,
  heliusRpc,
  mediaCandidatesForEvmToken,
  mediaCandidatesForSolanaAsset,
  mediaCandidatesForTezosToken,
  maybeReadApiKey,
  normalizeAssetURL,
  normalizeComparableURL,
  normalizeExtension,
  sourceKindForBundledURL,
  selectEvmTokensForCollection,
};
