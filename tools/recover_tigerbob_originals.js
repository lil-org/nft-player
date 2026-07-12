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
const COLLECTION_ID = "0xd497a414bb00803e846b53d07fcb742831b24906";
const COLLECTION_SLUG = "tigerbob";
const ORIGINAL_CID = "bafybeigblulyzewk4ofbbzw6cq6t4s4okhpme52vn7w5oxfruyfoubiuwe";
const COLLECTION_DIRECTORY = path.join(ROOT, "Originals Downloaded", COLLECTION_SLUG);
const COLLECTION_MANIFEST_PATH = path.join(COLLECTION_DIRECTORY, "manifest.json");
const ROOT_MANIFEST_PATH = path.join(ROOT, "Originals Downloaded", "manifest.json");
const BUNDLE_PATH = path.join(ROOT, "Suggested Items", "Suggested.bundle", "Tokens", `${COLLECTION_ID}.json`);

const EXPECTED = new Map(Object.entries({
  "295": {
    relativePath: "media/0296.jpg",
    extension: "png",
    format: "png",
    width: 5000,
    height: 5000,
    bytes: 41235,
    sha256: "e71dab2149f60ac12adcf17d07ecee15f36823c372c974cc3391e29799c7f477",
    recover: true,
  },
  "699": {
    relativePath: "media/0700.jpg",
    extension: "jpg",
    format: "jpeg",
    width: 1000,
    height: 1000,
    bytes: 89034,
    sha256: "ca6430571d5536e8bbab9e5b19ebd565e41c3759dbc594a7ff2abd1b3f55d218",
    recover: true,
  },
  "927": {
    relativePath: "media/0928.jpg",
    extension: "png",
    format: "png",
    width: 1000,
    height: 1000,
    bytes: 5551,
    sha256: "3020fa542b6827d0a5a49794986fa5581c4a65137282bc39158f6d23b72fa425",
    recover: false,
  },
  "989": {
    relativePath: "media/0990.jpg",
    extension: "jpg",
    format: "jpeg",
    width: 1000,
    height: 1000,
    bytes: 74960,
    sha256: "e8564c0c06406ac132aad29eb4654d0b69ef2194e173a28b4bf1099c7cb69c8d",
    recover: true,
  },
}));

const DEFAULTS = {
  apply: false,
  retries: 3,
  timeoutMs: 60000,
  retryDelayMs: 1500,
  reportPath: path.join(ROOT, "tools", "reports", "tigerbob-high-resolution-recovery.md"),
  jsonReportPath: path.join(ROOT, "tools", "reports", "tigerbob-high-resolution-recovery.json"),
};

const HELP = `Usage: node tools/recover_tigerbob_originals.js [options]

Recover Tigerbob's three missing canonical originals, preserve the source-native
PNG for token 927, and record the 5000x5000 token 295 exception correctly.

Options:
  --apply                  Download and commit recovery files. Default is dry-run.
  --retries <n>            Retries after the first gateway request (default: 3).
  --timeout-ms <n>         Per-request timeout (default: 60000).
  --retry-delay-ms <n>     Initial exponential retry delay (default: 1500).
  --report <path>          Markdown report path.
  --json-report <path>     JSON report path.
  -h, --help               Show this help.
`;

async function main() {
  const options = parseOptions(process.argv.slice(2));
  const startedAt = new Date();
  const [manifest, bundle] = await Promise.all([
    readJson(COLLECTION_MANIFEST_PATH),
    readJson(BUNDLE_PATH),
  ]);
  validateInputs(manifest, bundle);

  const tokenById = new Map(manifest.tokens.map((token) => [String(token.tokenId), token]));
  const failedAtStart = manifest.tokens.filter((token) => token.status === "failed").map((token) => String(token.tokenId));
  const distributionAtStart = probeDistribution(manifest.tokens);
  const work = [];
  const alreadyCanonical = [];
  for (const [tokenId, expected] of EXPECTED) {
    const token = tokenById.get(tokenId);
    const inspection = await inspectExisting(token, expected);
    if (inspection.ok) alreadyCanonical.push({ tokenId, ...inspection });
    else if (expected.recover) work.push({ tokenId, token, expected, inspection });
    else throw new Error(`Canonical verification failed for Tigerbob ${tokenId}: ${inspection.error}`);
  }

  console.error(`Tigerbob canonical recovery: ${work.length} file(s) to download, ${alreadyCanonical.length} verified.`);
  if (!options.apply) {
    console.log(JSON.stringify({
      mode: "dry-run",
      collectionId: COLLECTION_ID,
      failedAtStart,
      filesToRecover: work.map((entry) => entry.tokenId),
      alreadyCanonical: alreadyCanonical.map((entry) => entry.tokenId),
      canonicalException: { tokenId: "295", resolution: "5000x5000", format: "png" },
    }, null, 2));
    return;
  }

  await removeStaleTemporaryFiles();
  manifest.startedAt = startedAt.toISOString();
  await writeCollectionManifest(manifest, true);

  const recovered = [];
  const unresolved = [];
  let totalAttempts = 0;
  let downloadedBytes = 0;

  const downloads = await Promise.all(work.map(async (entry) => {
    const tempPath = path.join(COLLECTION_DIRECTORY, `.${entry.tokenId}.tigerbob.part`);
    const result = await downloadCanonical(entry.tokenId, entry.expected, tempPath, options);
    totalAttempts += result.attempts;
    return { ...entry, tempPath, result };
  }));

  for (const download of downloads) {
    const { tokenId, token, expected, tempPath, result } = download;
    if (!result.ok) {
      unresolved.push({ tokenId, error: result.error, attempts: result.attempts, sources: result.sources });
      await fsp.rm(tempPath, { force: true });
      continue;
    }

    const previous = snapshotPrevious(token);
    const fileName = `${safeTokenId(tokenId)}.${expected.extension}`;
    const finalPath = path.join(COLLECTION_DIRECTORY, fileName);
    await fsp.rename(tempPath, finalPath);
    const finishedAt = new Date().toISOString();
    Object.assign(token, {
      fileName,
      originalBundledSource: token.originalBundledSource ?? "compact-url",
      originalBundledURL: canonicalURL(expected.relativePath),
      downloadUrl: canonicalURL(expected.relativePath),
      sourceKind: "explicit-url",
      extension: expected.extension,
      startedAt: result.startedAt,
      status: "success",
      statusCode: result.statusCode,
      finalUrl: result.finalUrl,
      contentType: expected.format === "png" ? "image/png" : "image/jpeg",
      contentLength: expected.bytes,
      bytesWritten: expected.bytes,
      sha256: expected.sha256,
      elapsedMs: Date.parse(finishedAt) - Date.parse(result.startedAt),
      attempts: result.attempts,
      attemptUrl: result.attemptUrl,
      finishedAt,
      error: null,
      mediaProbe: result.probe,
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
        reason: previous.status === "failed" ? "previous download failed" : "local file differed from canonical original",
        decision: `canonical IPFS media verified as ${expected.width}x${expected.height} ${expected.format.toUpperCase()}`,
        apiSource: result.source,
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
    for (const key of ["reusedExisting", "reusedExistingFailure", "checkedAt", "sourceRefresh", "sourceOverridePreserved", "preferredBundledSource"]) {
      delete token[key];
    }

    await writeCollectionManifest(manifest, true);
    if (previous.fileName && previous.fileName !== fileName) {
      await fsp.rm(path.join(COLLECTION_DIRECTORY, previous.fileName), { force: true });
    }
    downloadedBytes += expected.bytes;
    recovered.push({
      tokenId,
      source: result.source,
      sourceUrl: result.finalUrl,
      fileName,
      bytesWritten: expected.bytes,
      sha256: expected.sha256,
      previousStatus: previous.status,
      previousProbe: previous.mediaProbe,
      nextProbe: result.probe,
    });
  }

  updateBundleExtensions(bundle);
  await writeCompactJsonAtomic(BUNDLE_PATH, bundle);
  await removeStaleTemporaryFiles();
  await writeCollectionManifest(manifest, false);

  const finalValidation = await validateFinalCollection(manifest);
  const report = buildReport({
    options,
    startedAt,
    manifest,
    failedAtStart,
    distributionAtStart,
    recovered,
    unresolved,
    alreadyCanonical,
    totalAttempts,
    downloadedBytes,
    finalValidation,
  });
  await writeReports(report, options);
  await updateRootManifest(manifest, report);

  console.log(JSON.stringify(report.summary, null, 2));
  if (unresolved.length > 0 || finalValidation.failedFiles > 0) process.exitCode = 2;
}

function parseOptions(args) {
  const options = { ...DEFAULTS };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    switch (arg) {
      case "--apply": options.apply = true; break;
      case "--retries": options.retries = nonnegativeInteger(nextValue(args, ++index, arg), arg); break;
      case "--timeout-ms": options.timeoutMs = positiveInteger(nextValue(args, ++index, arg), arg); break;
      case "--retry-delay-ms": options.retryDelayMs = positiveInteger(nextValue(args, ++index, arg), arg); break;
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
  if (String(manifest.collection?.id).toLowerCase() !== COLLECTION_ID) throw new Error("Tigerbob manifest identity mismatch");
  if (!Array.isArray(manifest.tokens) || manifest.tokens.length !== 1000) throw new Error("Expected 1000 Tigerbob manifest rows");
  if (!Array.isArray(bundle.items) || bundle.items.length !== 1000 || !Array.isArray(bundle.urlPrefixes)) {
    throw new Error("Tigerbob bundled token file has an unexpected shape");
  }
  const failed = manifest.tokens.filter((token) => token.status === "failed").map((token) => String(token.tokenId)).sort();
  const expectedFailed = ["295", "699", "989"];
  if (failed.length > 0 && JSON.stringify(failed) !== JSON.stringify(expectedFailed)) {
    throw new Error(`Unexpected Tigerbob failure set: ${failed.join(", ")}`);
  }
  for (const [tokenId, expected] of EXPECTED) {
    const row = bundle.items.find((item) => String(item[0]) === tokenId);
    if (!row) throw new Error(`Missing Tigerbob bundle row ${tokenId}`);
    const sourceUrl = `${bundle.urlPrefixes[row[1]]}${row[2]}`;
    if (sourceUrl !== canonicalURL(expected.relativePath)) {
      throw new Error(`Tigerbob ${tokenId} bundle URL is not the canonical media path`);
    }
  }
}

async function inspectExisting(token, expected) {
  if (token?.status !== "success" || !token.fileName) return { ok: false, error: `manifest status is ${token?.status ?? "missing"}` };
  const filePath = path.join(COLLECTION_DIRECTORY, token.fileName);
  if (!await fileExists(filePath)) return { ok: false, error: "manifest file is missing" };
  try {
    const [stat, sha256, probe] = await Promise.all([fsp.stat(filePath), sha256File(filePath), identifyFile(filePath)]);
    if (stat.size !== expected.bytes) return { ok: false, error: `byte count ${stat.size} != ${expected.bytes}` };
    if (sha256 !== expected.sha256) return { ok: false, error: "SHA-256 differs from canonical original" };
    if (!matchesProbe(probe, expected)) return { ok: false, error: `probe differs: ${probe?.width ?? "?"}x${probe?.height ?? "?"} ${probe?.format ?? "unknown"}` };
    return { ok: true, fileName: token.fileName, bytesWritten: stat.size, sha256, probe };
  } catch (error) {
    return { ok: false, error: error.message };
  }
}

async function downloadCanonical(tokenId, expected, tempPath, options) {
  const sources = gatewayURLs(expected.relativePath);
  let attempts = 0;
  let lastError = null;
  const startedAt = new Date().toISOString();
  for (const source of sources) {
    for (let retry = 0; retry <= options.retries; retry += 1) {
      attempts += 1;
      await fsp.rm(tempPath, { force: true });
      try {
        const response = await fetch(source.url, {
          redirect: "follow",
          headers: { "user-agent": "nft-player-tigerbob-original-recovery/1.0" },
          signal: AbortSignal.timeout(options.timeoutMs),
        });
        if (!response.ok || !response.body) throw new Error(`HTTP ${response.status}`);
        await pipeline(Readable.fromWeb(response.body), fs.createWriteStream(tempPath, { flags: "wx" }));
        const [stat, sha256, probe] = await Promise.all([fsp.stat(tempPath), sha256File(tempPath), identifyFile(tempPath)]);
        if (stat.size !== expected.bytes) throw new Error(`byte count ${stat.size} != ${expected.bytes}`);
        if (sha256 !== expected.sha256) throw new Error(`SHA-256 mismatch for token ${tokenId}`);
        if (!matchesProbe(probe, expected)) throw new Error(`media probe mismatch for token ${tokenId}`);
        return {
          ok: true,
          source: source.name,
          finalUrl: response.url || source.url,
          attemptUrl: source.url,
          statusCode: response.status,
          attempts,
          startedAt,
          probe,
        };
      } catch (error) {
        lastError = error;
        await fsp.rm(tempPath, { force: true });
        if (retry < options.retries) await delay(backoffDelay(options.retryDelayMs, retry));
      }
    }
  }
  return { ok: false, attempts, error: lastError?.message ?? "download failed", sources };
}

function gatewayURLs(relativePath) {
  const suffix = `${ORIGINAL_CID}/${relativePath}`;
  return [
    { name: "ipfs.pinata", url: `https://gateway.pinata.cloud/ipfs/${suffix}` },
    { name: "ipfs.alchemy-pinata", url: `https://alchemy.mypinata.cloud/ipfs/${suffix}` },
    { name: "ipfs.rarible", url: `https://ipfs.raribleuserdata.com/ipfs/${suffix}` },
    { name: "ipfs.filebase", url: `https://ipfs.filebase.io/ipfs/${suffix}` },
    { name: "ipfs.io", url: `https://ipfs.io/ipfs/${suffix}` },
  ];
}

function canonicalURL(relativePath) {
  return `https://ipfs.io/ipfs/${ORIGINAL_CID}/${relativePath}`;
}

function matchesProbe(probe, expected) {
  return probe?.kind === "image"
    && probe.format === expected.format
    && probe.width === expected.width
    && probe.height === expected.height
    && probe.bitDepth === 8;
}

async function identifyFile(filePath) {
  const { stdout } = await execFileAsync("magick", ["identify", "-ping", "-format", "%w\t%h\t%m\t%z\t%Q", `${filePath}[0]`], {
    timeout: 60000,
    maxBuffer: 1024 * 1024,
    encoding: "utf8",
  });
  const [width, height, format, bitDepth, quality] = stdout.trim().split("\t");
  return {
    kind: "image",
    format: String(format).toLowerCase() === "jpg" ? "jpeg" : String(format).toLowerCase(),
    width: Number(width),
    height: Number(height),
    area: Number(width) * Number(height),
    aspectRatio: Number((Number(width) / Number(height)).toFixed(5)),
    bitDepth: Number(bitDepth),
    quality: Number(quality),
  };
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

function updateBundleExtensions(bundle) {
  for (const [tokenId, expected] of EXPECTED) {
    if (expected.extension !== "png") continue;
    const row = bundle.items.find((item) => String(item[0]) === tokenId);
    row[3] = "png";
  }
}

async function validateFinalCollection(manifest) {
  const failures = manifest.tokens.filter((token) => token.status !== "success");
  const missingSha = manifest.tokens.filter((token) => !/^[0-9a-f]{64}$/u.test(token.sha256 ?? ""));
  const files = await fsp.readdir(COLLECTION_DIRECTORY);
  const tempFiles = files.filter((name) => name.includes(".part") || name.endsWith(".tmp"));
  const distribution = probeDistribution(manifest.tokens);
  return {
    tokensRecorded: manifest.tokens.length,
    successfulFiles: manifest.tokens.length - failures.length,
    failedFiles: failures.length,
    failedTokenIds: failures.map((token) => String(token.tokenId)),
    sha256Entries: manifest.tokens.length - missingSha.length,
    tempFiles,
    distribution,
  };
}

function probeDistribution(tokens) {
  const result = {};
  for (const token of tokens) {
    const probe = token.mediaProbe;
    const key = `${token.status}|${probe?.format ?? "none"}|${probe?.width ?? "?"}x${probe?.height ?? "?"}`;
    result[key] = (result[key] ?? 0) + 1;
  }
  return result;
}

async function writeCollectionManifest(manifest, partial) {
  const now = new Date().toISOString();
  manifest.generatedAt = now;
  manifest.updatedAt = now;
  manifest.partial = partial;
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

function buildReport({ options, startedAt, manifest, failedAtStart, distributionAtStart, recovered, unresolved, alreadyCanonical, totalAttempts, downloadedBytes, finalValidation }) {
  return {
    generatedAt: new Date().toISOString(),
    startedAt: startedAt.toISOString(),
    mode: "apply",
    collection: manifest.collection,
    collectionManifestPath: COLLECTION_MANIFEST_PATH,
    bundlePath: BUNDLE_PATH,
    reportPath: options.reportPath,
    jsonReportPath: options.jsonReportPath,
    canonicalIpfsRoot: `ipfs://${ORIGINAL_CID}`,
    summary: {
      tokensAudited: manifest.tokens.length,
      failuresAtStart: failedAtStart.length,
      canonicalFilesVerifiedBeforeRecovery: alreadyCanonical.length,
      recoveredFiles: recovered.length,
      unresolvedFiles: unresolved.length,
      downloadedBytes,
      totalAttempts,
      finalSuccessfulFiles: finalValidation.successfulFiles,
      finalFailedFiles: finalValidation.failedFiles,
      finalSha256Entries: finalValidation.sha256Entries,
      tempFiles: finalValidation.tempFiles.length,
      canonicalHighResolutionException: "Tigerbob 295: 5000x5000 PNG",
    },
    distributionAtStart,
    finalValidation,
    verifiedCanonical: alreadyCanonical,
    recovered,
    unresolved,
  };
}

async function writeReports(report, options) {
  await Promise.all([
    fsp.mkdir(path.dirname(options.reportPath), { recursive: true }),
    fsp.mkdir(path.dirname(options.jsonReportPath), { recursive: true }),
  ]);
  await writeJsonAtomic(options.jsonReportPath, report);
  const lines = [
    "# Tigerbob High-Resolution Original Recovery",
    "",
    `Generated: ${report.generatedAt}`,
    "",
    "## Summary",
    "",
    `- Tokens audited: ${report.summary.tokensAudited}`,
    `- Failures at start: ${report.summary.failuresAtStart}`,
    `- Canonical files recovered: ${report.summary.recoveredFiles}`,
    `- Remaining unresolved: ${report.summary.unresolvedFiles}`,
    `- Final successful files: ${report.summary.finalSuccessfulFiles}`,
    `- Final failed files: ${report.summary.finalFailedFiles}`,
    `- Canonical exception: ${report.summary.canonicalHighResolutionException}`,
    `- Downloaded bytes: ${formatBytes(report.summary.downloadedBytes)}`,
    "",
    "All existing successful Tigerbob media is source-native at 1000x1000. Token 295 is the sole canonical 5000x5000 original; marketplace archives only retained a 1000x1000 rendition for it.",
    "Token 927 remains its byte-identical canonical 1000x1000 PNG rather than being replaced by a larger-byte but non-canonical marketplace JPEG.",
    "",
    "## Recovered",
    "",
    ...report.recovered.map((entry) => `- Token ${entry.tokenId}: ${entry.nextProbe.width}x${entry.nextProbe.height} ${entry.nextProbe.format.toUpperCase()}, ${entry.bytesWritten} bytes, SHA-256 ${entry.sha256}.`),
    "",
    "## Unresolved",
    "",
    ...(report.unresolved.length ? report.unresolved.map((entry) => `- Token ${entry.tokenId}: ${entry.error}.`) : ["None."]),
    "",
  ];
  await fsp.writeFile(options.reportPath, `${lines.join("\n")}\n`);
  console.error(`Report written to ${options.reportPath}`);
  console.error(`JSON written to ${options.jsonReportPath}`);
}

async function updateRootManifest(collectionManifest, report) {
  const root = await readJson(ROOT_MANIFEST_PATH);
  const index = root.collections.findIndex((collection) => (
    String(collection.id).toLowerCase() === COLLECTION_ID && String(collection.chain).toLowerCase() === "ethereum"
  ));
  if (index < 0) throw new Error("Root manifest has no Tigerbob record");
  const successfulFiles = collectionManifest.tokens.filter((token) => token.status === "success").length;
  const failedTokens = collectionManifest.tokens.filter((token) => token.status === "failed");
  root.collections[index] = {
    ...root.collections[index],
    successfulFiles,
    downloadedFiles: report.summary.recoveredFiles,
    reusedFiles: collectionManifest.tokens.length - report.summary.recoveredFiles,
    sourceRefreshFailures: 0,
    failedFiles: failedTokens.length,
    bytesWritten: report.summary.downloadedBytes,
    totalAttempts: report.summary.totalAttempts,
  };
  root.failures = root.failures.filter((failure) => String(failure.collectionId).toLowerCase() !== COLLECTION_ID);
  for (const token of failedTokens) {
    root.failures.push({
      collectionId: COLLECTION_ID,
      collectionName: "Tigerbob",
      internal_slug: COLLECTION_SLUG,
      tokenId: String(token.tokenId),
      downloadUrl: token.downloadUrl,
      statusCode: token.statusCode ?? null,
      error: token.error ?? "download failed",
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
    .filter((name) => name.endsWith(".tigerbob.part") || name === "manifest.json.tmp")
    .map((name) => fsp.rm(path.join(COLLECTION_DIRECTORY, name), { force: true })));
}

async function fileExists(filePath) {
  try {
    return (await fsp.stat(filePath)).isFile();
  } catch (error) {
    if (error.code === "ENOENT") return false;
    throw error;
  }
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

async function writeCompactJsonAtomic(filePath, value) {
  const tempPath = `${filePath}.tmp`;
  await fsp.writeFile(tempPath, `${JSON.stringify(value)}\n`);
  await fsp.rename(tempPath, filePath);
}

function safeTokenId(value) {
  const tokenId = String(value);
  if (!/^\d+$/u.test(tokenId)) throw new Error(`Unsafe token ID: ${tokenId}`);
  return tokenId;
}

function backoffDelay(base, retry) {
  return Math.min(30000, base * (2 ** retry));
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function formatBytes(bytes) {
  const units = ["B", "KiB", "MiB", "GiB"];
  let value = Number(bytes);
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(unit === 0 ? 0 : 2)} ${units[unit]}`;
}

main().catch((error) => {
  console.error(error.stack ?? error.message ?? error);
  process.exitCode = 1;
});
