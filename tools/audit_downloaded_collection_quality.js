#!/usr/bin/env node

const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const path = require("node:path");
const { spawn } = require("node:child_process");
const { suggestedItemId } = require("./suggested_items");
const sourceAudit = require("./audit_bundled_collection_sources");
const {
  SKIP_REASON: BUNDLED_GENERATIVE_SKIP_REASON,
  isBundledGenerativeCollectionId,
  isBundledGenerativeDownloadDirectory,
  loadBundledGenerativeCollectionIds,
} = require("./bundled_generative_collections");
const { isCdnLilManagedCollection } = require("./cdn_lil_managed_collections");

const DEFAULT_BUNDLE_PATH = path.join("Suggested Items", "Suggested.bundle");
const DEFAULT_DOWNLOAD_ROOT = "Originals Downloaded";
const DEFAULT_REPORT_PATH = path.join("tools", "reports", "downloaded-collection-quality-audit.md");
const DEFAULT_JSON_REPORT_PATH = path.join("tools", "reports", "downloaded-collection-quality-audit.json");
const DEFAULT_SIMPLEHASH_API_KEY_PATH = path.join(process.env.HOME ?? "", "Developer", "secrets", "tools", "SIMPLEHASH_API_KEY");
const IMAGE_EXTENSIONS = new Set(["png", "jpg", "jpeg", "webp", "gif", "heic", "heif", "svg"]);
const VIDEO_EXTENSIONS = new Set(["mp4", "mov", "webm"]);
const HTML_EXTENSIONS = new Set(["html", "interactive-html"]);
const CDN_LIL_RE = /(^|\.)cdn\.lil\.org$/iu;

function usage() {
  return `
Usage: node tools/audit_downloaded_collection_quality.js [options]

Audits downloaded non-Art Blocks collections for missing files and within-collection
dimension/quality outliers. Dry-run is the default.
Collections represented by Suggested.bundle/Scripts/*.json are always skipped.

Options:
  --apply                    Write recovered/replaced files, manifests, and source URL updates.
  --recover-failures-only    Recover failed manifest entries without scanning all dimensions.
  --skip-failure-recovery    Full quality scan without retrying known failed entries.
  --bundle <path>            Suggested bundle path. Default: ${DEFAULT_BUNDLE_PATH}
  --download-root <path>     Download root. Default: ${DEFAULT_DOWNLOAD_ROOT}
  --collection <text>        Repeatable collection id/name/address filter.
  --include-art-blocks       Include items with abId that do not have bundled scripts.
  --include-cdn-lil          Include cdn.lil.org collections. Default: excluded.
  --probe-concurrency <n>    Concurrent media probes. Default: 12.
  --download-concurrency <n> Concurrent candidate recoveries. Default: 6.
  --timeout-ms <n>           Candidate request timeout. Default: 60000.
  --retries <n>              Candidate retry count. Default: 1.
  --report <path>            Markdown report path. Default: ${DEFAULT_REPORT_PATH}
  --json-report <path>       JSON report path. Default: ${DEFAULT_JSON_REPORT_PATH}
  --opensea-api-key <key>    OpenSea key override.
  --helius-api-key <key>     Helius key override.
  --help                     Show this help.
`.trim();
}

function parseArgs(argv) {
  const options = {
    apply: false,
    failuresOnly: false,
    skipFailureRecovery: false,
    bundlePath: DEFAULT_BUNDLE_PATH,
    downloadRoot: DEFAULT_DOWNLOAD_ROOT,
    collections: [],
    includeArtBlocks: false,
    includeCdnLil: false,
    probeConcurrency: 12,
    downloadConcurrency: 6,
    timeoutMs: 60000,
    retries: 1,
    reportPath: DEFAULT_REPORT_PATH,
    jsonReportPath: DEFAULT_JSON_REPORT_PATH,
    openSeaApiKey: process.env.OPENSEA_API_KEY ?? null,
    heliusApiKey: process.env.HELIUS_API_KEY ?? null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const value = () => {
      const next = argv[index + 1];
      if (!next || next.startsWith("--")) throw new Error(`Missing value for ${arg}`);
      index += 1;
      return next;
    };
    switch (arg) {
      case "--apply": options.apply = true; break;
      case "--recover-failures-only": options.failuresOnly = true; break;
      case "--skip-failure-recovery": options.skipFailureRecovery = true; break;
      case "--bundle": options.bundlePath = value(); break;
      case "--download-root": options.downloadRoot = value(); break;
      case "--collection": options.collections.push(value().toLowerCase()); break;
      case "--include-art-blocks": options.includeArtBlocks = true; break;
      case "--include-cdn-lil": options.includeCdnLil = true; break;
      case "--probe-concurrency": options.probeConcurrency = positiveInt(value(), arg); break;
      case "--download-concurrency": options.downloadConcurrency = positiveInt(value(), arg); break;
      case "--timeout-ms": options.timeoutMs = positiveInt(value(), arg); break;
      case "--retries": options.retries = nonNegativeInt(value(), arg); break;
      case "--report": options.reportPath = value(); break;
      case "--json-report": options.jsonReportPath = value(); break;
      case "--opensea-api-key": options.openSeaApiKey = value(); break;
      case "--helius-api-key": options.heliusApiKey = value(); break;
      case "--help": console.log(usage()); process.exit(0); break;
      default: throw new Error(`Unknown option: ${arg}`);
    }
  }
  return options;
}

function positiveInt(value, name) {
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) throw new Error(`${name} must be a positive integer`);
  return number;
}

function nonNegativeInt(value, name) {
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0) throw new Error(`${name} must be a non-negative integer`);
  return number;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const startedAt = new Date();
  const loaded = await loadCollections(options);
  if (loaded.collections.length === 0 && loaded.skipped.length === 0) {
    throw new Error("No downloaded collections matched.");
  }

  const needsEvm = loaded.collections.some((collection) => isEvm(collection.item.chain));
  const needsSolana = loaded.collections.some((collection) => collection.item.chain === "solana");
  const openSeaApiKey = await readKey(options.openSeaApiKey, sourceAudit.DEFAULT_OPENSEA_API_KEY_PATH, needsEvm);
  const heliusApiKey = await readKey(options.heliusApiKey, sourceAudit.DEFAULT_HELIUS_API_KEY_PATH, needsSolana);
  const context = makeSourceContext(options, openSeaApiKey, heliusApiKey);
  const results = [];

  for (let index = 0; index < loaded.collections.length; index += 1) {
    const collection = loaded.collections[index];
    console.error(`[${index + 1}/${loaded.collections.length}] ${collection.item.name}`);
    const result = await auditCollection(collection, context, options);
    results.push(result);
    console.error(`  probed ${result.probedFiles}, outliers ${result.outliers.length}, recovered ${result.recovered.length}, unresolved ${result.unresolved.length}`);
  }

  if (options.apply) await applyBundleChanges(loaded, results);
  const report = buildReport(startedAt, options, loaded, results);
  await writeReports(report, options);
  console.log(JSON.stringify(report.summary, null, 2));
}

async function loadCollections(options) {
  const bundlePath = path.resolve(options.bundlePath);
  const downloadRoot = path.resolve(options.downloadRoot);
  const itemsPath = path.join(bundlePath, "items.json");
  const tokensPath = path.join(bundlePath, "Tokens");
  const [items, manifestPaths, bundledGenerativeCollectionIds] = await Promise.all([
    fs.readFile(itemsPath, "utf8").then((contents) => JSON.parse(contents)),
    findManifestPaths(downloadRoot),
    loadBundledGenerativeCollectionIds(bundlePath),
  ]);
  const manifestById = new Map();
  for (const manifestPath of manifestPaths) {
    const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
    if (manifest.collection?.id) manifestById.set(String(manifest.collection.id).toLowerCase(), { manifest, manifestPath });
  }

  const collections = [];
  const skipped = [];
  for (const item of items) {
    const id = suggestedItemId(item);
    if (options.collections.length > 0 && !matchesFilter(item, id, options.collections)) continue;
    if (!options.includeCdnLil && isCdnLilManagedCollection(item)) {
      skipped.push({ id, name: item.name, reason: "native collection media is managed by cdn.lil.org" });
      continue;
    }
    if (isBundledGenerativeCollectionId(id, bundledGenerativeCollectionIds)) {
      skipped.push({ id, name: item.name, reason: BUNDLED_GENERATIVE_SKIP_REASON });
      continue;
    }
    const manifestRecord = manifestById.get(id.toLowerCase());
    if (!manifestRecord) {
      skipped.push({ id, name: item.name, reason: "no downloaded collection manifest" });
      continue;
    }
    if (!options.includeArtBlocks && item.abId != null) {
      skipped.push({ id, name: item.name, reason: "Art Blocks collection" });
      continue;
    }
    const containsCdnLil = manifestRecord.manifest.tokens.some((token) => isCdnLil(token.downloadUrl ?? token.originalBundledURL));
    if (!options.includeCdnLil && containsCdnLil) {
      skipped.push({ id, name: item.name, reason: "resolved media contains cdn.lil.org" });
      continue;
    }
    let tokenPath = path.join(tokensPath, `${id}.json`);
    let payload = null;
    try {
      payload = JSON.parse(await fs.readFile(tokenPath, "utf8"));
    } catch {
      const actual = (await fs.readdir(tokensPath)).find((entry) => entry.toLowerCase() === `${id}.json`.toLowerCase());
      if (actual) {
        tokenPath = path.join(tokensPath, actual);
        payload = JSON.parse(await fs.readFile(tokenPath, "utf8"));
      }
    }
    collections.push({
      id,
      item,
      tokenPath,
      payload,
      records: payload ? normalizeTokenPayload(payload, item) : [],
      manifest: manifestRecord.manifest,
      manifestPath: manifestRecord.manifestPath,
      directory: path.dirname(manifestRecord.manifestPath),
    });
  }
  return { bundlePath, downloadRoot, itemsPath, items, collections, skipped };
}

async function findManifestPaths(root) {
  const entries = await fs.readdir(root, { withFileTypes: true });
  const paths = [];
  for (const entry of entries) {
    if (!entry.isDirectory() || isBundledGenerativeDownloadDirectory(entry.name)) continue;
    const manifestPath = path.join(root, entry.name, "manifest.json");
    try {
      await fs.access(manifestPath);
      paths.push(manifestPath);
    } catch {}
  }
  return paths;
}

function matchesFilter(item, id, filters) {
  const text = `${id} ${item.name ?? ""} ${item.address ?? ""}`.toLowerCase();
  return filters.some((filter) => text.includes(filter));
}

function isCdnLil(value) {
  if (!value) return false;
  try { return CDN_LIL_RE.test(new URL(value).hostname); } catch { return /cdn\.lil\.org/iu.test(value); }
}

function normalizeTokenPayload(payload, item) {
  const prefixes = Array.isArray(payload.urlPrefixes) ? payload.urlPrefixes : [];
  const defaultExtension = normalizeExtension(payload.defaultFileExtension);
  return (payload.items ?? []).map((row, index) => {
    if (Array.isArray(row)) {
      const prefixIndex = Number(row[1]);
      const prefix = prefixes[Number.isInteger(prefixIndex) ? prefixIndex : 0] ?? "";
      return { id: String(row[0] ?? index), url: `${prefix}${row[2] ?? ""}`, fileExtension: normalizeExtension(row[3]) ?? defaultExtension };
    }
    const id = String(row.id ?? index);
    const url = row.url
      ?? (row.sh ? `https://cdn.simplehash.com/assets/${row.sh}` : null)
      ?? (item.chain === "ethereum" && item.address ? `https://media-proxy.artblocks.io/${item.address}/${id}.png` : null);
    return { id, url, fileExtension: normalizeExtension(row.fileExtension) ?? defaultExtension ?? extensionFromURL(url) };
  });
}

async function auditCollection(collection, context, options) {
  const manifest = collection.manifest;
  const successful = manifest.tokens.filter((token) => token.status === "success");
  const failed = manifest.tokens.filter((token) => token.status === "failed");
  const probeTargets = options.failuresOnly ? evenlySample(successful, 80) : successful;
  const probes = await probeEntries(collection.directory, probeTargets, options.probeConcurrency);
  for (const token of successful) {
    const probe = probes.get(token.tokenId);
    if (probe) token.mediaProbe = probe;
  }
  const baselines = buildBaselines(successful);
  const outliers = options.failuresOnly ? [] : findOutliers(successful, baselines);
  const targetEntries = [...(options.skipFailureRecovery ? [] : failed), ...outliers.map((outlier) => outlier.token)]
    .filter((token, index, list) => list.findIndex((entry) => entry.tokenId === token.tokenId) === index);

  const apiById = await fetchApiTokens(collection, targetEntries.map((token) => token.tokenId), context);
  const recovered = [];
  const unresolved = [];
  const verifiedVariations = [];
  const bundleChanges = [];
  await runPool(targetEntries, options.downloadConcurrency, async (token) => {
    const outlier = outliers.find((entry) => entry.token.tokenId === token.tokenId) ?? null;
    const candidates = candidatesForApiToken(collection, apiById.get(token.tokenId), token.status === "failed");
    const result = await recoverToken(collection, token, outlier, candidates, baselines, options);
    if (result.ok) {
      recovered.push(result.evidence);
      if (result.bundleChange) bundleChanges.push(result.bundleChange);
    } else if (result.sourceVerified) {
      verifiedVariations.push({
        tokenId: token.tokenId,
        reason: outlier?.reason ?? result.reason,
        downloadUrl: token.downloadUrl,
        probe: token.mediaProbe ?? null,
        baseline: outlier?.baseline ? publicBaseline(outlier.baseline) : null,
      });
    } else {
      unresolved.push({ tokenId: token.tokenId, status: token.status, reason: result.reason, candidatesTried: result.candidatesTried });
    }
  });

  if (options.apply) {
    manifest.generatedAt = new Date().toISOString();
    manifest.updatedAt = manifest.generatedAt;
    manifest.partial = false;
    manifest.totals = manifestTotals(manifest.tokens);
    await writeJsonAtomic(collection.manifestPath, manifest);
  }

  return {
    id: collection.id,
    name: collection.item.name,
    chain: collection.item.chain,
    address: collection.item.address,
    manifestPath: collection.manifestPath,
    tokenPath: collection.tokenPath,
    tokenCount: manifest.tokens.length,
    probedFiles: probes.size,
    baselineGroups: [...baselines.values()].map(publicBaseline),
    initialFailures: failed.length,
    outliers: outliers.map(publicOutlier),
    recovered,
    verifiedVariations,
    unresolved,
    bundleChanges,
  };
}

async function probeEntries(directory, entries, concurrency) {
  const result = new Map();
  const images = entries.filter((entry) => IMAGE_EXTENSIONS.has(normalizeExtension(entry.extension) ?? extensionFromURL(entry.fileName)));
  const videos = entries.filter((entry) => VIDEO_EXTENSIONS.has(normalizeExtension(entry.extension) ?? extensionFromURL(entry.fileName)));
  const others = entries.filter((entry) => !images.includes(entry) && !videos.includes(entry));

  const imageBatches = chunk(images, 80);
  await runPool(imageBatches, Math.min(concurrency, 6), async (batch) => {
    const batchResult = await identifyBatch(directory, batch);
    for (const [id, probe] of batchResult) result.set(id, probe);
  });
  await runPool(videos, Math.min(concurrency, 8), async (entry) => {
    const probe = await ffprobeFile(path.join(directory, entry.fileName));
    if (probe) result.set(entry.tokenId, probe);
  });
  for (const entry of others) {
    const extension = normalizeExtension(entry.extension) ?? extensionFromURL(entry.fileName);
    result.set(entry.tokenId, { kind: HTML_EXTENSIONS.has(extension) ? "html" : "other", format: extension, width: null, height: null, area: null, aspectRatio: null });
  }
  return result;
}

async function identifyBatch(directory, entries) {
  const separator = "\u001e";
  const field = "\u001f";
  const args = ["-ping", "-format", `%i${field}%w${field}%h${field}%m${field}%z${field}%Q${separator}`];
  for (const entry of entries) args.push(`${path.join(directory, entry.fileName)}[0]`);
  const execution = await runCommand("identify", args, 120000);
  const byFileName = new Map(entries.map((entry) => [entry.fileName, entry]));
  const result = new Map();
  for (const record of execution.stdout.split(separator)) {
    if (!record.trim()) continue;
    const [input, width, height, format, bitDepth, quality] = record.split(field);
    const fileName = path.basename(String(input ?? "").replace(/\[0\]$/u, ""));
    const entry = byFileName.get(fileName);
    if (!entry) continue;
    const probe = dimensionsProbe("image", width, height, format, bitDepth, quality);
    if (probe) result.set(entry.tokenId, probe);
  }
  if (result.size !== entries.length) {
    for (const entry of entries) {
      if (result.has(entry.tokenId)) continue;
      const single = await identifyFile(path.join(directory, entry.fileName));
      if (single) result.set(entry.tokenId, single);
    }
  }
  return result;
}

async function identifyFile(filePath) {
  const execution = await runCommand("identify", ["-ping", "-format", "%w\t%h\t%m\t%z\t%Q", `${filePath}[0]`], 60000);
  if (execution.exitCode !== 0) return null;
  const [width, height, format, bitDepth, quality] = execution.stdout.trim().split("\t");
  return dimensionsProbe("image", width, height, format, bitDepth, quality);
}

async function ffprobeFile(filePath) {
  const execution = await runCommand("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height,codec_name,bit_rate", "-of", "json", filePath], 60000);
  if (execution.exitCode !== 0) return null;
  try {
    const stream = JSON.parse(execution.stdout).streams?.[0];
    if (!stream) return null;
    const probe = dimensionsProbe("video", stream.width, stream.height, stream.codec_name, null, null);
    if (probe) probe.bitRate = numeric(stream.bit_rate);
    return probe;
  } catch { return null; }
}

function dimensionsProbe(kind, widthValue, heightValue, format, bitDepthValue, qualityValue) {
  const width = numeric(widthValue);
  const height = numeric(heightValue);
  if (!width || !height) return null;
  return {
    kind,
    format: String(format ?? "").toLowerCase() || null,
    width,
    height,
    area: width * height,
    aspectRatio: Number((width / height).toFixed(5)),
    bitDepth: numeric(bitDepthValue),
    quality: numeric(qualityValue),
  };
}

function buildBaselines(tokens) {
  const groups = new Map();
  for (const token of tokens) {
    const probe = token.mediaProbe;
    if (!probe?.area || !["image", "video"].includes(probe.kind)) continue;
    const key = baselineKey(probe);
    const values = groups.get(key) ?? [];
    values.push({ token, probe });
    groups.set(key, values);
  }
  const baselines = new Map();
  for (const [key, values] of groups) {
    if (values.length < 5) continue;
    const areas = values.map((entry) => entry.probe.area).sort(numberSort);
    const widths = values.map((entry) => entry.probe.width).sort(numberSort);
    const heights = values.map((entry) => entry.probe.height).sort(numberSort);
    const qualities = values.map((entry) => entry.probe.quality).filter(Number.isFinite).sort(numberSort);
    const dimensions = mostCommon(values.map((entry) => `${entry.probe.width}x${entry.probe.height}`));
    baselines.set(key, {
      key,
      kind: values[0].probe.kind,
      aspectBucket: aspectBucket(values[0].probe),
      count: values.length,
      width: median(widths),
      height: median(heights),
      area: median(areas),
      upperArea: percentile(areas, 0.75),
      quality: qualities.length >= 5 ? median(qualities) : null,
      dominantDimensions: dimensions.value,
      dominantCount: dimensions.count,
    });
  }
  return baselines;
}

function baselineKey(probe) {
  return `${probe.kind}:${aspectBucket(probe)}`;
}

function aspectBucket(probe) {
  return Math.round(Math.log2(probe.width / probe.height) * 4) / 4;
}

function findOutliers(tokens, baselines) {
  const outliers = [];
  for (const token of tokens) {
    const probe = token.mediaProbe;
    if (!probe?.area) continue;
    const baseline = baselines.get(baselineKey(probe));
    if (!baseline) continue;
    const areaRatio = probe.area / baseline.area;
    const widthRatio = probe.width / baseline.width;
    const heightRatio = probe.height / baseline.height;
    const dimensionOutlier = areaRatio < 0.6 && Math.max(widthRatio, heightRatio) < 0.86;
    const bothDimensionsSmall = widthRatio < 0.68 && heightRatio < 0.68;
    const qualityOutlier = baseline.quality != null && probe.quality != null && probe.quality <= baseline.quality - 18 && probe.quality < 75;
    if (!dimensionOutlier && !bothDimensionsSmall && !qualityOutlier) continue;
    outliers.push({
      token,
      probe,
      baseline,
      reason: qualityOutlier && !dimensionOutlier && !bothDimensionsSmall ? "encoding quality below collection baseline" : "pixel dimensions below collection baseline",
      areaRatio: Number(areaRatio.toFixed(4)),
      widthRatio: Number(widthRatio.toFixed(4)),
      heightRatio: Number(heightRatio.toFixed(4)),
    });
  }
  return outliers;
}

function makeSourceContext(options, openSeaApiKey, heliusApiKey) {
  return {
    options: {
      delayMs: 75,
      timeoutMs: Math.min(options.timeoutMs, 30000),
      maxRetries: Math.max(options.retries, 3),
      limit: 1000,
      openSeaLimit: 200,
      tzktApiBaseUrl: sourceAudit.TZKT_API_BASE_URL,
    },
    openSeaApiKey,
    heliusApiKey,
    lastOpenSeaCallAt: 0,
    lastHeliusCallAt: 0,
    lastTzktCallAt: 0,
    evmNftByTargetId: new Map(),
    evmTokensByTarget: new Map(),
    evmTokensBySlug: new Map(),
    metadataByUrl: new Map(),
    unavailableMetadataRoots: new Set(),
    tezosTokensByContract: new Map(),
  };
}

async function fetchApiTokens(collection, ids, context) {
  const map = new Map();
  if (ids.length === 0) return map;
  if (collection.item.chain === "solana") {
    for (const batch of chunk(ids, 100)) {
      const assets = await sourceAudit.heliusRpc("getAssetBatch", { ids: batch }, context);
      for (const asset of assets ?? []) if (asset?.id) map.set(String(asset.id), asset);
    }
    return map;
  }
  if (collection.item.chain === "tezos") {
    const tokens = await sourceAudit.getTezosTokens(collection.item.address, context);
    const wanted = new Set(ids);
    for (const token of tokens) {
      const id = String(token.tokenId ?? token.id ?? "");
      if (wanted.has(id)) map.set(id, token);
    }
    return map;
  }
  if (isEvm(collection.item.chain)) {
    const target = sourceAudit.evmTargetForItem(collection.item);
    const auditCollectionShape = { item: collection.item, records: collection.records };
    let tokens = [];
    try {
      const scoped = await sourceAudit.getEvmSlugScopedTokens(auditCollectionShape, target, context);
      if (scoped.ok) tokens = scoped.tokens;
    } catch {}
    if (tokens.length === 0) {
      try {
        const contractTokens = await sourceAudit.getEvmContractTokens(target, context);
        const selected = sourceAudit.selectEvmTokensForCollection(auditCollectionShape, contractTokens);
        if (selected.ok) tokens = selected.tokens;
      } catch {}
    }
    const wanted = new Set(ids);
    for (const token of tokens) {
      const id = String(token.identifier ?? token.token_id ?? token.tokenId ?? token.id ?? "");
      if (wanted.has(id)) map.set(id, token);
    }
    await runPool([...map.values()], 8, async (token) => {
      if (token.metadata && typeof token.metadata === "object") return;
      const metadataUrl = token.metadata_url ?? token.metadataUrl;
      if (!metadataUrl) return;
      const metadata = await fetchTokenMetadata(metadataUrl, context);
      if (metadata) token.metadata = metadata;
    });
  }
  return map;
}

async function fetchTokenMetadata(urlString, context) {
  if (context.metadataByUrl.has(urlString)) return context.metadataByUrl.get(urlString);
  const rootKey = contentAddressRoot(urlString);
  if (rootKey && context.unavailableMetadataRoots.has(rootKey)) return null;
  for (const candidateUrl of downloadCandidates(sourceAudit.normalizeAssetURL(urlString, "evm") ?? urlString)) {
    const execution = await runCommand("curl", [
      "--location", "--fail", "--http1.1", "--silent", "--show-error",
      "--max-time", String(Math.max(1, Math.ceil(context.options.timeoutMs / 1000))),
      "--connect-timeout", "15", "--header", "Connection: close",
      "--user-agent", "nft-player-downloaded-quality-audit/1.0",
      candidateUrl,
    ], context.options.timeoutMs + 5000);
    if (execution.exitCode !== 0) continue;
    try {
      const metadata = JSON.parse(execution.stdout);
      context.metadataByUrl.set(urlString, metadata);
      return metadata;
    } catch {}
  }
  context.metadataByUrl.set(urlString, null);
  if (rootKey) context.unavailableMetadataRoots.add(rootKey);
  return null;
}

function contentAddressRoot(urlString) {
  try {
    const url = new URL(urlString);
    const ipfs = /^\/ipfs\/([^/]+)/u.exec(url.pathname);
    if (ipfs) return `ipfs:${ipfs[1]}`;
    const arweave = /^\/([A-Za-z0-9_-]{43})/u.exec(url.pathname);
    if (arweave && ["arweave.net", "gateway.irys.xyz", "permagate.io"].includes(url.hostname)) return `arweave:${arweave[1]}`;
  } catch {}
  return null;
}

function candidatesForApiToken(collection, token, includeFallbacks) {
  if (!token) return [];
  let candidates = [];
  if (collection.item.chain === "solana") {
    candidates = sourceAudit.mediaCandidatesForSolanaAsset(token).map((candidate) => ({ ...candidate, modifiedFallback: false }));
    if (includeFallbacks) {
      for (const file of token.content?.files ?? []) {
        if (file.cdn_uri) {
          candidates.push({
            url: file.cdn_uri,
            mime: file.mime ?? null,
            extension: sourceAudit.fileExtensionForURL(file.cdn_uri, file.mime, "solana") ?? "unknown",
            source: "content.files.cdn_uri",
            sourceRank: 99,
            rank: 999,
            chainKind: "solana",
            modifiedFallback: true,
          });
        }
      }
    }
  } else if (collection.item.chain === "tezos") {
    candidates = sourceAudit.mediaCandidatesForTezosToken(token).map((candidate) => ({ ...candidate, modifiedFallback: !/artifactUri|formats\.uri/u.test(candidate.source) }));
  } else {
    candidates = sourceAudit.mediaCandidatesForEvmToken(token).map((candidate) => ({
      ...candidate,
      modifiedFallback: !/^(?:raw2\.)?(?:original_|metadata\.)/u.test(candidate.source),
    }));
  }
  const seen = new Set();
  return candidates
    .filter((candidate) => candidate.url && !isKnownDerivative(candidate.url, candidate.source))
    .filter((candidate) => {
      const key = sourceAudit.normalizeComparableURL(candidate.url) ?? candidate.url;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .sort((left, right) => Boolean(left.modifiedFallback) - Boolean(right.modifiedFallback) || Number(left.rank ?? 999) - Number(right.rank ?? 999));
}

function isKnownDerivative(url, source) {
  return /(?:^|\.)i\d*c\.seadn\.io$/iu.test(hostname(url))
    || /[?&](?:w|h|width|height|format)=/iu.test(url)
    || (/cdn\.helius-rpc\.com/iu.test(url) && source !== "content.files.cdn_uri");
}

async function recoverToken(collection, token, outlier, candidates, baselines, options) {
  const currentComparable = sourceAudit.normalizeComparableURL(token.downloadUrl ?? token.finalUrl);
  const currentSourceCandidate = outlier ? candidates.find((candidate) =>
    !candidate.modifiedFallback
    && sourceAudit.normalizeComparableURL(candidate.url) === currentComparable
  ) : null;
  const currentIsDeclaredSource = Boolean(currentSourceCandidate);
  const candidatePool = currentSourceCandidate
    ? candidates.filter((candidate) => !candidate.modifiedFallback && Number(candidate.rank ?? 999) < Number(currentSourceCandidate.rank ?? 999))
    : candidates;
  if (outlier && currentIsDeclaredSource && candidatePool.length === 0) {
    return {
      ok: false,
      sourceVerified: true,
      reason: "lower dimensions are present in the highest-priority API-declared original/source file",
      candidatesTried: [],
    };
  }
  const expectedProbe = token.mediaProbe ?? outlier?.probe ?? null;
  const baseline = expectedProbe ? baselines.get(baselineKey(expectedProbe)) ?? null : bestBaselineForExtension(token.extension, baselines);
  const candidatesTried = [];
  for (const candidate of candidatePool) {
    const comparable = sourceAudit.normalizeComparableURL(candidate.url);
    if (outlier && comparable && comparable === currentComparable) continue;
    const attempt = await downloadAndProbeCandidate(collection, token, candidate, options);
    candidatesTried.push({ url: candidate.url, source: candidate.source, status: attempt.status, error: attempt.error ?? null, probe: attempt.probe ?? null });
    if (!attempt.ok) continue;
    const quality = candidateQualityDecision(token, outlier, attempt.probe, baseline, candidate);
    if (!quality.accept) {
      await fs.rm(attempt.tempPath, { force: true });
      continue;
    }
    const evidence = await commitCandidate(collection, token, outlier, candidate, attempt, quality, options);
    return {
      ok: true,
      evidence,
      bundleChange: candidate.modifiedFallback || !isBundleSupportedExtension(collection.item.chain, evidence.extension)
        ? null
        : { id: token.tokenId, url: candidate.url, fileExtension: evidence.extension, source: candidate.source },
    };
  }
  const currentProbe = token.mediaProbe ?? outlier?.probe ?? null;
  const measurableSources = candidatesTried.filter((attempt) => attempt.probe?.area);
  const currentAtLeastAsGood = Boolean(outlier && currentProbe?.area && measurableSources.length > 0 && measurableSources.every((attempt) =>
    attempt.probe.area <= currentProbe.area * 1.05
    && !(attempt.probe.width > currentProbe.width * 1.05 && attempt.probe.height > currentProbe.height * 1.05)
  ));
  return {
    ok: false,
    sourceVerified: currentIsDeclaredSource || currentAtLeastAsGood,
    reason: currentIsDeclaredSource
      ? "lower dimensions are present in the API-declared original/source file"
      : currentAtLeastAsGood
      ? "downloaded file is at least as large as every reachable API-declared source candidate"
      : candidatePool.length === 0
      ? "API returned no usable source candidates"
      : "no reachable candidate met provenance and collection-quality requirements",
    candidatesTried,
  };
}

function bestBaselineForExtension(extension, baselines) {
  const kind = VIDEO_EXTENSIONS.has(normalizeExtension(extension)) ? "video" : IMAGE_EXTENSIONS.has(normalizeExtension(extension)) ? "image" : null;
  if (!kind) return null;
  return [...baselines.values()].filter((baseline) => baseline.kind === kind).sort((left, right) => right.count - left.count)[0] ?? null;
}

async function downloadAndProbeCandidate(collection, token, candidate, options) {
  const tempPath = path.join(collection.directory, `.${safeName(token.tokenId)}.${shortHash(candidate.url)}.quality.part`);
  let last = null;
  let attempts = 0;
  for (let retry = 0; retry <= options.retries; retry += 1) {
    for (const url of downloadCandidates(candidate.url)) {
      attempts += 1;
      const result = await curlDownload(url, tempPath, options.timeoutMs);
      last = { ...result, url };
      if (!result.ok) {
        await fs.rm(tempPath, { force: true });
        continue;
      }
      const extension = extensionForDownloaded(result.contentType, candidate.extension, url);
      const probe = await probeCandidate(tempPath, extension);
      if (!probe && (IMAGE_EXTENSIONS.has(extension) || VIDEO_EXTENSIONS.has(extension))) {
        await fs.rm(tempPath, { force: true });
        last = { ...last, ok: false, error: "downloaded media could not be dimension-probed" };
        continue;
      }
      return { ...result, ok: true, tempPath, attempts, extension, probe, attemptedUrl: url };
    }
  }
  return { ok: false, status: last?.status ?? null, error: last?.error ?? "download failed", attempts };
}

async function probeCandidate(filePath, extension) {
  if (IMAGE_EXTENSIONS.has(extension)) return identifyFile(filePath);
  if (VIDEO_EXTENSIONS.has(extension)) return ffprobeFile(filePath);
  if (HTML_EXTENSIONS.has(extension)) return { kind: "html", format: extension, width: null, height: null, area: null, aspectRatio: null };
  return null;
}

function candidateQualityDecision(token, outlier, probe, baseline, candidate) {
  const expectedKind = token.mediaProbe?.kind ?? (VIDEO_EXTENSIONS.has(normalizeExtension(token.extension)) ? "video" : IMAGE_EXTENSIONS.has(normalizeExtension(token.extension)) ? "image" : null);
  const sourceVideoUpgrade = Boolean(outlier && expectedKind === "image" && probe?.kind === "video" && !candidate.modifiedFallback);
  if (expectedKind && probe?.kind && expectedKind !== probe.kind && !sourceVideoUpgrade) return { accept: false, reason: `media class changed from ${expectedKind} to ${probe.kind}` };
  if (baseline?.area && probe?.area) {
    const baselineRatio = probe.area / baseline.area;
    if (baselineRatio < 0.65 || probe.width < baseline.width * 0.65 || probe.height < baseline.height * 0.65) {
      return { accept: false, reason: "candidate dimensions remain below collection baseline" };
    }
  }
  if (outlier?.probe?.area && probe?.area) {
    const areaGain = probe.area / outlier.probe.area;
    const widthGain = probe.width / outlier.probe.width;
    const heightGain = probe.height / outlier.probe.height;
    if (areaGain < 1.35 && (widthGain < 1.18 || heightGain < 1.18)) return { accept: false, reason: "candidate is not materially higher resolution" };
  }
  if (candidate.modifiedFallback && !probe?.area) return { accept: false, reason: "modified fallback has no measurable dimensions" };
  return { accept: true, reason: candidate.modifiedFallback ? "fallback cache matches collection dimensions" : "source candidate meets collection dimensions" };
}

function isBundleSupportedExtension(chain, extension) {
  const normalized = normalizeExtension(extension);
  if (isEvm(chain)) return new Set(["png", "jpg", "jpeg", "webp", "heic", "heif", "gif", "svg", "mp4", "mov", "html", "interactive-html"]).has(normalized);
  return new Set(["png", "jpg", "jpeg", "webp", "heic", "heif", "gif", "mp4", "mov"]).has(normalized);
}

async function commitCandidate(collection, token, outlier, candidate, attempt, quality, options) {
  const previous = {
    status: token.status,
    fileName: token.fileName,
    downloadUrl: token.downloadUrl,
    finalUrl: token.finalUrl,
    bytesWritten: token.bytesWritten,
    sha256: token.sha256,
    mediaProbe: token.mediaProbe ?? null,
  };
  const extension = normalizeExtension(attempt.extension) ?? normalizeExtension(token.extension) ?? "bin";
  const baseName = token.fileName ? token.fileName.replace(/\.[^.]+$/u, "") : safeName(token.tokenId);
  const fileName = `${baseName}.${extension}`;
  const finalPath = path.join(collection.directory, fileName);
  const hash = await sha256File(attempt.tempPath);
  const stat = await fs.stat(attempt.tempPath);
  if (options.apply) {
    await fs.rename(attempt.tempPath, finalPath);
    if (previous.fileName && previous.fileName !== fileName) await fs.rm(path.join(collection.directory, previous.fileName), { force: true });
  } else {
    await fs.rm(attempt.tempPath, { force: true });
  }
  const finishedAt = new Date().toISOString();
  if (options.apply) {
    Object.assign(token, {
      fileName,
      downloadUrl: candidate.url,
      sourceKind: sourceAudit.sourceKindForBundledURL(candidate.url),
      extension,
      status: "success",
      statusCode: attempt.status,
      finalUrl: attempt.finalUrl ?? attempt.attemptedUrl,
      contentType: attempt.contentType,
      contentLength: attempt.contentLength,
      bytesWritten: stat.size,
      sha256: hash,
      attempts: attempt.attempts,
      error: null,
      finishedAt,
      mediaProbe: attempt.probe,
      qualityRepair: {
        repairedAt: finishedAt,
        reason: outlier?.reason ?? "previous download failed",
        decision: quality.reason,
        apiSource: candidate.source,
        modifiedFallback: Boolean(candidate.modifiedFallback),
        previous,
      },
    });
  }
  return {
    tokenId: token.tokenId,
    previousStatus: previous.status,
    reason: outlier?.reason ?? "previous download failed",
    source: candidate.source,
    sourceUrl: candidate.url,
    finalUrl: attempt.finalUrl ?? attempt.attemptedUrl,
    modifiedFallback: Boolean(candidate.modifiedFallback),
    extension,
    bytesWritten: stat.size,
    sha256: hash,
    previousProbe: previous.mediaProbe,
    nextProbe: attempt.probe,
    applied: options.apply,
  };
}

function downloadCandidates(urlString) {
  const urls = [];
  try {
    const url = new URL(urlString);
    const ipfs = /^\/ipfs\/([^/]+)(\/.*)?$/u.exec(url.pathname);
    if (ipfs) {
      urls.push(`https://ipfs.io/ipfs/${ipfs[1]}${ipfs[2] ?? ""}${url.search}`);
      urls.push(urlString);
      urls.push(`https://ipfs.decentralized-content.com/ipfs/${ipfs[1]}${ipfs[2] ?? ""}${url.search}`);
    } else if (["arweave.net", "gateway.irys.xyz", "permagate.io"].includes(url.hostname)) {
      const match = /^\/([A-Za-z0-9_-]{43})(\/.*)?$/u.exec(url.pathname);
      if (match) {
        urls.push(urlString);
        urls.push(`https://arweave.net/${match[1]}${match[2] ?? ""}${url.search}`);
        urls.push(`https://gateway.irys.xyz/${match[1]}${match[2] ?? ""}${url.search}`);
      } else urls.push(urlString);
    } else urls.push(urlString);
  } catch { urls.push(urlString); }
  return [...new Set(urls)];
}

async function curlDownload(url, outputPath, timeoutMs) {
  const marker = "QUALITY_CURL\t";
  const execution = await runCommand("curl", [
    "--location", "--fail", "--http1.1", "--silent", "--show-error",
    "--max-time", String(Math.max(1, Math.ceil(timeoutMs / 1000))),
    "--connect-timeout", "15", "--header", "Connection: close",
    "--user-agent", "nft-player-downloaded-quality-audit/1.0",
    "--output", outputPath,
    "--write-out", `\n${marker}%{http_code}\t%{url_effective}\t%{content_type}\t%{size_download}`,
    url,
  ], timeoutMs + 5000);
  const line = execution.stdout.split(/\r?\n/u).findLast((entry) => entry.startsWith(marker));
  const fields = line ? line.slice(marker.length).split("\t") : [];
  const status = numeric(fields[0]);
  if (execution.exitCode !== 0 || !status || status < 200 || status >= 300) {
    return { ok: false, status, error: execution.stderr.trim().split(/\r?\n/u).at(-1) || `curl exited ${execution.exitCode}` };
  }
  return {
    ok: true,
    status,
    finalUrl: fields[1] || url,
    contentType: fields[2] || null,
    contentLength: numeric(fields[3]),
  };
}

function extensionForDownloaded(contentType, candidateExtension, url) {
  return sourceAudit.extensionForContentType(contentType)
    ?? normalizeExtension(candidateExtension)
    ?? extensionFromURL(url)
    ?? "bin";
}

async function applyBundleChanges(loaded, results) {
  for (const result of results) {
    if (result.bundleChanges.length === 0) continue;
    const collection = loaded.collections.find((entry) => entry.id === result.id);
    if (!collection?.payload || collection.records.length === 0) continue;
    const changes = new Map(result.bundleChanges.map((change) => [change.id, change]));
    const records = collection.records.map((record) => {
      const change = changes.get(record.id);
      return change ? { ...record, url: change.url, fileExtension: change.fileExtension } : record;
    });
    await fs.writeFile(collection.tokenPath, `${JSON.stringify(sourceAudit.buildTokenPayload(records))}\n`);
  }
}

function manifestTotals(tokens) {
  const successful = tokens.filter((token) => token.status === "success");
  return {
    tokensRecorded: tokens.length,
    successfulFiles: successful.length,
    failedFiles: tokens.length - successful.length,
    reusedFiles: successful.filter((token) => token.reusedExisting).length,
    bytesWritten: successful.reduce((sum, token) => sum + Number(token.bytesWritten ?? 0), 0),
  };
}

function publicBaseline(baseline) {
  return { ...baseline };
}

function publicOutlier(outlier) {
  return {
    tokenId: outlier.token.tokenId,
    fileName: outlier.token.fileName,
    downloadUrl: outlier.token.downloadUrl,
    reason: outlier.reason,
    probe: outlier.probe,
    baseline: publicBaseline(outlier.baseline),
    areaRatio: outlier.areaRatio,
    widthRatio: outlier.widthRatio,
    heightRatio: outlier.heightRatio,
  };
}

function buildReport(startedAt, options, loaded, results) {
  const recovered = results.flatMap((result) => result.recovered.map((entry) => ({ collection: result.name, chain: result.chain, ...entry })));
  const verifiedVariations = results.flatMap((result) => result.verifiedVariations.map((entry) => ({ collection: result.name, chain: result.chain, ...entry })));
  const unresolved = results.flatMap((result) => result.unresolved.map((entry) => ({ collection: result.name, chain: result.chain, ...entry })));
  const outliers = results.reduce((sum, result) => sum + result.outliers.length, 0);
  return {
    generatedAt: new Date().toISOString(),
    startedAt: startedAt.toISOString(),
    mode: options.apply ? "apply" : "dry-run",
    failuresOnly: options.failuresOnly,
    bundlePath: loaded.bundlePath,
    downloadRoot: loaded.downloadRoot,
    summary: {
      auditedCollections: results.length,
      skippedCollections: loaded.skipped.length,
      probedFiles: results.reduce((sum, result) => sum + result.probedFiles, 0),
      detectedOutliers: outliers,
      initialFailures: results.reduce((sum, result) => sum + result.initialFailures, 0),
      recoveredFiles: recovered.length,
      verifiedSourceVariations: verifiedVariations.length,
      unresolvedFiles: unresolved.length,
      sourceUrlChanges: results.reduce((sum, result) => sum + result.bundleChanges.length, 0),
      elapsedMs: Date.now() - startedAt.getTime(),
    },
    skipped: loaded.skipped,
    recovered,
    verifiedVariations,
    unresolved,
    collections: results,
  };
}

async function writeReports(report, options) {
  const jsonPath = path.resolve(options.jsonReportPath);
  const markdownPath = path.resolve(options.reportPath);
  await fs.mkdir(path.dirname(jsonPath), { recursive: true });
  await fs.mkdir(path.dirname(markdownPath), { recursive: true });
  await writeJsonAtomic(jsonPath, report);
  const lines = [
    "# Downloaded Collection Quality Audit", "",
    `Generated: ${report.generatedAt}`, `Mode: ${report.mode}${report.failuresOnly ? " (failure recovery only)" : ""}`, "",
    "## Summary", "",
    `- Audited non-Art Blocks collections: ${report.summary.auditedCollections}`,
    `- Probed local files: ${report.summary.probedFiles}`,
    `- Detected quality outliers: ${report.summary.detectedOutliers}`,
    `- Initial failed downloads: ${report.summary.initialFailures}`,
    `- Recovered/replaced files: ${report.summary.recoveredFiles}`,
    `- Lower-dimension files verified as API-declared originals: ${report.summary.verifiedSourceVariations}`,
    `- Remaining unresolved files: ${report.summary.unresolvedFiles}`,
    `- Bundled source URL changes: ${report.summary.sourceUrlChanges}`, "",
    "## Collections", "",
    "| Collection | Chain | Probed | Outliers | Initial failures | Recovered | Source-native | Unresolved |",
    "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ...report.collections.map((entry) => `| ${escapeCell(entry.name)} | ${escapeCell(entry.chain)} | ${entry.probedFiles} | ${entry.outliers.length} | ${entry.initialFailures} | ${entry.recovered.length} | ${entry.verifiedVariations.length} | ${entry.unresolved.length} |`),
    "", "## Recovered Or Replaced", "",
    ...(report.recovered.length ? report.recovered.map((entry) => `- ${escapeMarkdown(entry.collection)} token ${escapeMarkdown(entry.tokenId)}: ${escapeMarkdown(entry.reason)} via ${escapeMarkdown(entry.source)} (${entry.nextProbe?.width ?? "?"}x${entry.nextProbe?.height ?? "?"}).`) : ["None."]),
    "", "## Verified Source-Native Variations", "",
    ...(report.verifiedVariations.length ? report.verifiedVariations.map((entry) => `- ${escapeMarkdown(entry.collection)} token ${escapeMarkdown(entry.tokenId)}: API source matches the downloaded file (${entry.probe?.width ?? "?"}x${entry.probe?.height ?? "?"}).`) : ["None."]),
    "", "## Unresolved", "",
    ...(report.unresolved.length ? report.unresolved.map((entry) => `- ${escapeMarkdown(entry.collection)} token ${escapeMarkdown(entry.tokenId)}: ${escapeMarkdown(entry.reason)}.`) : ["None."]), "",
  ];
  await fs.writeFile(markdownPath, `${lines.join("\n")}\n`);
  console.error(`Report written to ${markdownPath}`);
  console.error(`JSON written to ${jsonPath}`);
}

async function readKey(value, fallbackPath, required) {
  if (value?.trim()) return value.trim();
  try {
    const key = (await fs.readFile(fallbackPath, "utf8")).trim();
    if (key) return key;
  } catch {}
  if (required) throw new Error(`Missing API key at ${fallbackPath}`);
  return null;
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

function runCommand(command, args, timeoutMs) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
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
    child.stdout.on("data", (chunkValue) => { stdout += chunkValue; });
    child.stderr.on("data", (chunkValue) => { stderr += chunkValue; });
    child.on("error", (error) => {
      clearTimeout(timeout);
      resolve({ exitCode: null, stdout, stderr: error.message, timedOut });
    });
    child.on("close", (exitCode) => {
      clearTimeout(timeout);
      resolve({ exitCode, stdout, stderr, timedOut });
    });
  });
}

async function sha256File(filePath) {
  const hash = crypto.createHash("sha256");
  const handle = await fs.open(filePath, "r");
  try {
    const stream = handle.createReadStream();
    for await (const data of stream) hash.update(data);
  } finally { await handle.close(); }
  return hash.digest("hex");
}

async function writeJsonAtomic(filePath, value) {
  const tempPath = `${filePath}.tmp`;
  await fs.writeFile(tempPath, `${JSON.stringify(value, null, 2)}\n`);
  await fs.rename(tempPath, filePath);
}

function evenlySample(values, limit) {
  if (values.length <= limit) return values;
  const selected = [];
  for (let index = 0; index < limit; index += 1) selected.push(values[Math.floor(index * values.length / limit)]);
  return selected;
}

function chunk(values, size) {
  const result = [];
  for (let index = 0; index < values.length; index += size) result.push(values.slice(index, index + size));
  return result;
}

function mostCommon(values) {
  const counts = new Map();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  const entry = [...counts.entries()].sort((left, right) => right[1] - left[1] || String(left[0]).localeCompare(String(right[0])))[0];
  return { value: entry?.[0] ?? null, count: entry?.[1] ?? 0 };
}

function median(sorted) {
  if (sorted.length === 0) return null;
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function percentile(sorted, fraction) {
  if (sorted.length === 0) return null;
  return sorted[Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * fraction))];
}

function numberSort(left, right) { return left - right; }
function numeric(value) { const number = Number(value); return Number.isFinite(number) && number > 0 ? number : null; }
function normalizeExtension(value) { return sourceAudit.normalizeExtension(value); }
function extensionFromURL(value) { try { return normalizeExtension(path.extname(new URL(value).pathname).slice(1)); } catch { return normalizeExtension(path.extname(String(value ?? "")).slice(1)); } }
function hostname(value) { try { return new URL(value).hostname; } catch { return ""; } }
function shortHash(value) { return crypto.createHash("sha256").update(String(value)).digest("hex").slice(0, 10); }
function safeName(value) { return String(value).normalize("NFKD").replace(/[^A-Za-z0-9._-]+/gu, "_").slice(0, 120) || shortHash(value); }
function isEvm(chain) { return ["ethereum", "base", "zora"].includes(String(chain).toLowerCase()); }
function escapeCell(value) { return String(value ?? "").replace(/\|/gu, "\\|").replace(/\n/gu, " "); }
function escapeMarkdown(value) { return String(value ?? "").replace(/([*_`])/gu, "\\$1"); }

main().catch((error) => {
  console.error(error.stack ?? error.message);
  console.error("");
  console.error(usage());
  process.exit(1);
});
