#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const fsp = fs.promises;
const path = require("node:path");
const { spawn } = require("node:child_process");

const ROOT = path.resolve(__dirname, "..");
const DOWNLOAD_ROOT = path.join(ROOT, "Originals Downloaded");
const ROOT_MANIFEST_PATH = path.join(DOWNLOAD_ROOT, "manifest.json");
const BASELINE_REPORT_PATH = path.join(__dirname, "reports", "originals-download-recovery.json");
const CANDIDATE_REPORT_PATH = path.join(__dirname, "reports", "remaining-solana-marketplace-candidates.json");
const DEFAULT_REPORT_PATH = path.join(__dirname, "reports", "remaining-originals-archive-recovery.md");
const DEFAULT_JSON_REPORT_PATH = path.join(__dirname, "reports", "remaining-originals-archive-recovery.json");
const BUNDLE_TOKEN_ROOT = path.join(ROOT, "Suggested Items", "Suggested.bundle", "Tokens");

const COLLECTION_REQUIREMENTS = new Map([
  ["organic_evolution", { width: 2401, height: 2401, format: "jpeg" }],
  ["tojiba_cpu_corp", { width: 640, height: 640, format: "jpeg" }],
  ["tojia", { width: 640, height: 640, format: "png" }],
]);

const HELP = `Usage: node tools/recover_remaining_originals_from_archives.js [options]

Install only validated alternate-source candidates for currently failed rows in
tools/reports/originals-download-recovery.json. Successful tokens are never probed
or overwritten.

Options:
  --apply                    Commit files and update manifests/bundled URLs.
  --concurrency <number>     Concurrent downloads. Default: 4.
  --retries <number>         Retry count for transient failures. Default: 5.
  --timeout-ms <number>      Per-request timeout. Default: 120000.
  --retry-delay-ms <number>  Exponential-backoff base delay. Default: 2000.
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
  const [baseline, candidateResearch, rootManifest] = await Promise.all([
    readJson(BASELINE_REPORT_PATH),
    readJson(CANDIDATE_REPORT_PATH),
    readJson(ROOT_MANIFEST_PATH),
  ]);
  const scope = await loadScope(baseline, candidateResearch, rootManifest);
  console.error(`Validated alternate-source candidates still in scope: ${scope.targets.length}; candidate rows already recovered: ${scope.alreadyRecovered.length}.`);

  const stats = { attempts: 0, retries: 0 };
  const recovered = [];
  const unresolved = [];
  await runPool(scope.targets, options.concurrency, async (target, index) => {
    try {
      const result = await downloadAndValidate(target, options, stats);
      recovered.push(result);
      console.error(`  ${index + 1}/${scope.targets.length} ${target.internal_slug} ${target.tokenId}: ${result.mediaProbe.width}x${result.mediaProbe.height} ${formatBytes(result.bytesWritten)}`);
    } catch (error) {
      unresolved.push(publicFailure(target, error.message));
      console.error(`  ${index + 1}/${scope.targets.length} ${target.internal_slug} ${target.tokenId}: ${error.message}`);
    }
  });
  recovered.sort(targetSort);
  unresolved.sort(targetSort);

  let committed = [];
  if (options.apply) committed = await commitRecoveries(recovered, scope, rootManifest);
  else await removeCandidateFiles(recovered);

  const finalValidation = options.apply ? await validateCommitted(committed) : null;
  const report = buildReport({
    options,
    startedAt,
    baseline,
    candidateResearch,
    scope,
    recovered: options.apply ? committed : recovered,
    unresolved,
    stats,
    finalValidation,
  });
  await writeReports(report, options);
  if (options.apply) await finalizeRootManifest(rootManifest, scope, committed, report);
  await removeStalePartFiles(scope);

  console.error(`Recovered ${report.summary.recoveredFiles}/${report.summary.scopedCandidates}; unresolved candidates ${report.summary.unresolvedCandidates}.`);
  if (report.summary.unresolvedCandidates > 0) process.exitCode = 2;
}

function parseOptions(argv) {
  const options = {
    apply: false,
    concurrency: 4,
    retries: 5,
    timeoutMs: 120000,
    retryDelayMs: 2000,
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

async function loadScope(baseline, research, rootManifest) {
  if (!Array.isArray(baseline.failures)) throw new Error("Baseline recovery report has no failures array");
  if (!Array.isArray(research.candidates)) throw new Error("Candidate research report has no candidates array");
  if (!Array.isArray(rootManifest.failures)) throw new Error("Root manifest has no failures array");

  const baselineByKey = uniqueMap(baseline.failures, failureKey, "baseline failure");
  const currentFailureKeys = new Set(rootManifest.failures.map(failureKey));
  const collections = new Map();
  const targets = [];
  const alreadyRecovered = [];
  const seen = new Set();

  for (const candidate of research.candidates) {
    const internal_slug = String(candidate.slug ?? candidate.internal_slug ?? "");
    const tokenId = String(candidate.tokenId ?? "");
    const key = tokenKey(internal_slug, tokenId);
    if (seen.has(key)) throw new Error(`Duplicate candidate row: ${internal_slug} ${tokenId}`);
    seen.add(key);
    const baselineFailure = baselineByKey.get(key);
    if (!baselineFailure) throw new Error(`Candidate is outside the baseline failure report: ${internal_slug} ${tokenId}`);
    const requirement = COLLECTION_REQUIREMENTS.get(internal_slug);
    if (!requirement) throw new Error(`Candidate collection is not approved: ${internal_slug}`);

    let collection = collections.get(internal_slug);
    if (!collection) {
      const manifestPath = path.join(DOWNLOAD_ROOT, internal_slug, "manifest.json");
      const manifest = await readJson(manifestPath);
      collection = {
        internal_slug,
        directory: path.dirname(manifestPath),
        manifestPath,
        manifest,
        bundleTokenPath: path.join(BUNDLE_TOKEN_ROOT, `${manifest.collection.id}.json`),
      };
      collections.set(internal_slug, collection);
    }
    const token = collection.manifest.tokens.find((entry) => String(entry.tokenId) === tokenId);
    if (!token) throw new Error(`Candidate token is absent from the collection manifest: ${internal_slug} ${tokenId}`);
    if (token.status === "success") {
      alreadyRecovered.push({ internal_slug, tokenId, candidateUrl: candidate.candidateUrl });
      continue;
    }
    if (!currentFailureKeys.has(key)) throw new Error(`Failed token is missing from the root failure list: ${internal_slug} ${tokenId}`);
    validateResearchCandidate(candidate, requirement);
    targets.push({
      ...baselineFailure,
      ...candidate,
      internal_slug,
      tokenId,
      requirement,
      collection,
      token,
    });
  }
  return { targets, alreadyRecovered, collections };
}

function validateResearchCandidate(candidate, requirement) {
  if (!/^https:\/\//u.test(String(candidate.candidateUrl ?? ""))) throw new Error(`Candidate has no HTTPS URL: ${candidate.tokenId}`);
  if (!/^[a-f0-9]{64}$/u.test(String(candidate.sha256 ?? ""))) throw new Error(`Candidate has no valid SHA-256: ${candidate.tokenId}`);
  if (Number(candidate.bytes) <= 0) throw new Error(`Candidate has no byte length: ${candidate.tokenId}`);
  if (Number(candidate.width) !== requirement.width || Number(candidate.height) !== requirement.height) {
    throw new Error(`Candidate dimensions do not meet ${requirement.width}x${requirement.height}: ${candidate.tokenId}`);
  }
  const contentType = String(candidate.contentType ?? "").toLowerCase();
  if (requirement.format === "jpeg" && !contentType.includes("jpeg")) throw new Error(`Candidate is not JPEG: ${candidate.tokenId}`);
  if (requirement.format === "png" && !contentType.includes("png")) throw new Error(`Candidate is not PNG: ${candidate.tokenId}`);
}

async function downloadAndValidate(target, options, stats) {
  const started = Date.now();
  const partPath = path.join(target.collection.directory, `.${safeComponent(target.tokenId)}.archive.part`);
  await fsp.rm(partPath, { force: true });
  try {
    const response = await fetchWithRetry(target.candidateUrl, options, stats);
    const buffer = Buffer.from(await response.arrayBuffer());
    await fsp.writeFile(partPath, buffer, { flag: "wx" });
    const hash = sha256Buffer(buffer);
    if (hash !== target.sha256) throw new Error(`SHA-256 mismatch: expected ${target.sha256}, received ${hash}`);
    if (buffer.length !== Number(target.bytes)) throw new Error(`byte-length mismatch: expected ${target.bytes}, received ${buffer.length}`);
    const mediaProbe = await identifyFile(partPath);
    if (!mediaProbe) throw new Error("downloaded candidate is not a readable image");
    const format = mediaProbe.format === "jpg" ? "jpeg" : mediaProbe.format;
    if (format !== target.requirement.format) throw new Error(`format ${format} does not match required ${target.requirement.format}`);
    if (mediaProbe.width !== target.requirement.width || mediaProbe.height !== target.requirement.height) {
      throw new Error(`dimensions ${mediaProbe.width}x${mediaProbe.height} do not match required ${target.requirement.width}x${target.requirement.height}`);
    }
    const extension = format === "jpeg" ? "jpg" : format;
    const baseName = String(target.token.fileName ?? target.tokenId).replace(/\.[^.]+$/u, "");
    return {
      internal_slug: target.internal_slug,
      collectionId: target.collectionId,
      collectionName: target.collectionName,
      tokenId: target.tokenId,
      tokenName: target.tokenName ?? null,
      originalUrl: target.originalUrl ?? target.downloadUrl,
      candidateUrl: target.candidateUrl,
      source: target.source ?? (target.internal_slug === "tojiba_cpu_corp" ? "HowRare" : "alternate archive"),
      sourcePage: target.page ?? null,
      qualityClassification: target.qualityClassification ?? "recompressed_native_dimensions",
      contentType: format === "jpeg" ? "image/jpeg" : `image/${format}`,
      bytesWritten: buffer.length,
      sha256: hash,
      mediaProbe,
      extension,
      fileName: `${baseName}.${extension}`,
      previousFileName: target.token.fileName,
      candidatePath: partPath,
      destinationPath: path.join(target.collection.directory, `${baseName}.${extension}`),
      elapsedMs: Date.now() - started,
      attempts: response.attempts,
      sourceEvidence: publicSourceEvidence(target),
    };
  } catch (error) {
    await fsp.rm(partPath, { force: true });
    throw error;
  }
}

async function fetchWithRetry(url, options, stats) {
  let lastError;
  for (let retry = 0; retry <= options.retries; retry += 1) {
    stats.attempts += 1;
    try {
      const response = await fetch(url, {
        headers: { "user-agent": "nft-player-known-failure-archive-recovery/1.0" },
        signal: AbortSignal.timeout(options.timeoutMs),
      });
      if (response.ok) {
        response.attempts = retry + 1;
        return response;
      }
      const detail = (await response.text()).trim().slice(0, 300);
      const error = new Error(`HTTP ${response.status}${detail ? `: ${detail}` : ""}`);
      error.status = response.status;
      if (!isTransientStatus(response.status) || retry === options.retries) throw error;
      lastError = error;
    } catch (error) {
      lastError = error;
      if (retry === options.retries || (error.status && !isTransientStatus(error.status))) break;
    }
    stats.retries += 1;
    await delay(Math.min(30000, options.retryDelayMs * (2 ** retry)));
  }
  throw new Error(lastError?.message ?? "request failed");
}

async function commitRecoveries(recovered, scope, rootManifest) {
  if (recovered.length === 0) return [];
  const bySlug = groupBy(recovered, (entry) => entry.internal_slug);
  const committed = [];

  for (const [slug, entries] of bySlug) {
    const collection = scope.collections.get(slug);
    const bundle = await readJson(collection.bundleTokenPath);
    if (!Array.isArray(bundle.items) || !Array.isArray(bundle.urlPrefixes)) throw new Error(`Unexpected bundled-token shape for ${slug}`);
    const rowById = new Map(bundle.items.map((row) => [String(Array.isArray(row) ? row[0] : row?.id), row]));
    const tokenById = new Map(collection.manifest.tokens.map((token) => [String(token.tokenId), token]));

    for (const entry of entries) {
      const token = tokenById.get(entry.tokenId);
      const row = rowById.get(entry.tokenId);
      if (!token || token.status === "success") throw new Error(`Refusing to replace non-failed token ${slug} ${entry.tokenId}`);
      if (!Array.isArray(row)) throw new Error(`Bundled token row is missing or not compact: ${slug} ${entry.tokenId}`);
      if (await fileExists(entry.destinationPath)) throw new Error(`Refusing to overwrite unexpected file ${entry.destinationPath}`);

      await fsp.rename(entry.candidatePath, entry.destinationPath);
      if (entry.previousFileName && entry.previousFileName !== entry.fileName) {
        await fsp.rm(path.join(collection.directory, entry.previousFileName), { force: true });
      }

      updateCompactBundleRow(bundle, row, entry.candidateUrl, entry.extension);
      const now = new Date().toISOString();
      const previous = {
        status: token.status,
        fileName: token.fileName,
        downloadUrl: token.downloadUrl,
        finalUrl: token.finalUrl,
        bytesWritten: token.bytesWritten,
        sha256: token.sha256,
        mediaProbe: token.mediaProbe ?? null,
      };
      delete token.error;
      Object.assign(token, {
        fileName: entry.fileName,
        downloadUrl: entry.candidateUrl,
        sourceKind: "explicit-url",
        extension: entry.extension,
        status: "success",
        statusCode: 200,
        finalUrl: entry.candidateUrl,
        attemptUrl: entry.candidateUrl,
        contentType: entry.contentType,
        contentLength: entry.bytesWritten,
        bytesWritten: entry.bytesWritten,
        sha256: entry.sha256,
        attempts: entry.attempts,
        elapsedMs: entry.elapsedMs,
        finishedAt: now,
        recoveredAt: now,
        reusedExisting: false,
        mediaProbe: entry.mediaProbe,
        recoverySource: {
          kind: recoveryKind(entry.internal_slug),
          source: entry.source,
          sourceUrl: entry.candidateUrl,
          sourcePage: entry.sourcePage,
          qualityClassification: entry.qualityClassification,
          originalMediaUrl: entry.originalUrl,
          originalMediaUnavailable: true,
          evidence: entry.sourceEvidence,
        },
        qualityRepair: {
          repairedAt: now,
          reason: "original media download remained unavailable after bounded gateway and bundle recovery",
          decision: recoveryDecision(entry.internal_slug),
          apiSource: entry.source,
          modifiedFallback: true,
          previous,
        },
      });
      committed.push(entry);
    }

    const now = new Date().toISOString();
    collection.manifest.generatedAt = now;
    collection.manifest.updatedAt = now;
    collection.manifest.partial = false;
    collection.manifest.totals = manifestTotals(collection.manifest.tokens);
    await Promise.all([
      writeJsonAtomic(collection.manifestPath, collection.manifest),
      writeJsonAtomic(collection.bundleTokenPath, bundle, false),
    ]);

    const rootCollection = rootManifest.collections.find((entry) => entry.internal_slug === slug);
    if (!rootCollection) throw new Error(`Root manifest has no collection row for ${slug}`);
    const failed = collection.manifest.tokens.filter((token) => token.status !== "success");
    rootCollection.successfulFiles = collection.manifest.tokens.length - failed.length;
    rootCollection.downloadedFiles = Number(rootCollection.downloadedFiles ?? 0) + entries.length;
    rootCollection.failedFiles = failed.length;
    rootCollection.bytesWritten = Number(rootCollection.bytesWritten ?? 0) + entries.reduce((sum, entry) => sum + entry.bytesWritten, 0);
  }
  return committed;
}

function updateCompactBundleRow(bundle, row, sourceUrl, extension) {
  const prefix = preferredPrefix(sourceUrl);
  let prefixIndex = bundle.urlPrefixes.indexOf(prefix);
  if (prefixIndex < 0) {
    bundle.urlPrefixes.push(prefix);
    prefixIndex = bundle.urlPrefixes.length - 1;
  }
  row[1] = prefixIndex;
  row[2] = sourceUrl.slice(prefix.length);
  if (extension === bundle.defaultFileExtension) row.splice(3);
  else row[3] = extension;
}

function preferredPrefix(urlString) {
  const url = new URL(urlString);
  if (url.hostname === "cdn.sanity.io") return `${url.origin}/images/avty3dma/production/`;
  if (url.hostname === "media.howrare.is") return `${url.origin}/nft_images/tojibacpucorp/`;
  return `${url.origin}${url.pathname.slice(0, url.pathname.lastIndexOf("/") + 1)}`;
}

async function validateCommitted(committed) {
  const files = [];
  for (const entry of committed) {
    const exists = await fileExists(entry.destinationPath);
    const hashMatches = Boolean(exists && await sha256File(entry.destinationPath) === entry.sha256);
    const partExists = await fileExists(entry.candidatePath);
    const probe = exists ? await identifyFile(entry.destinationPath) : null;
    const valid = Boolean(
      exists
      && hashMatches
      && !partExists
      && probe
      && probe.width === entry.mediaProbe.width
      && probe.height === entry.mediaProbe.height
      && probe.format === entry.mediaProbe.format
    );
    files.push({ internal_slug: entry.internal_slug, tokenId: entry.tokenId, fileName: entry.fileName, exists, hashMatches, partExists, mediaProbe: probe, valid });
  }
  return { files: files.length, validFiles: files.filter((entry) => entry.valid).length, invalidFiles: files.filter((entry) => !entry.valid).length, entries: files };
}

function buildReport({ options, startedAt, baseline, candidateResearch, scope, recovered, unresolved, stats, finalValidation }) {
  const collections = [];
  for (const [slug, rows] of groupBy(scope.targets, (entry) => entry.internal_slug)) {
    const successful = recovered.filter((entry) => entry.internal_slug === slug);
    const failed = unresolved.filter((entry) => entry.internal_slug === slug);
    collections.push({
      internal_slug: slug,
      collectionName: rows[0].collectionName,
      scopedCandidates: rows.length,
      recoveredFiles: successful.length,
      unresolvedCandidates: failed.length,
      recoveredBytes: successful.reduce((sum, entry) => sum + entry.bytesWritten, 0),
      dimensions: [...new Set(successful.map((entry) => `${entry.mediaProbe.width}x${entry.mediaProbe.height} ${entry.mediaProbe.format}`))],
      qualityClassifications: [...new Set(successful.map((entry) => entry.qualityClassification))],
    });
  }
  collections.sort((left, right) => left.internal_slug.localeCompare(right.internal_slug));
  return {
    generatedAt: new Date().toISOString(),
    startedAt: startedAt.toISOString(),
    mode: options.apply ? "apply" : "dry-run",
    baselineReportPath: BASELINE_REPORT_PATH,
    candidateResearchPath: CANDIDATE_REPORT_PATH,
    rootManifestPath: ROOT_MANIFEST_PATH,
    reportPath: options.reportPath,
    jsonReportPath: options.jsonReportPath,
    options: { concurrency: options.concurrency, retries: options.retries, timeoutMs: options.timeoutMs, retryDelayMs: options.retryDelayMs },
    summary: {
      baselineFailures: baseline.failures.length,
      researchedCandidates: candidateResearch.candidates.length,
      candidatesAlreadyRecovered: scope.alreadyRecovered.length,
      scopedCandidates: scope.targets.length,
      recoveredFiles: recovered.length,
      unresolvedCandidates: unresolved.length,
      recoveredBytes: recovered.reduce((sum, entry) => sum + entry.bytesWritten, 0),
      networkAttempts: stats.attempts,
      networkRetries: stats.retries,
      finalValidFiles: finalValidation?.validFiles ?? null,
      finalInvalidFiles: finalValidation?.invalidFiles ?? null,
      elapsedMs: Date.now() - startedAt.getTime(),
    },
    collections,
    recovered: recovered.map(publicRecovery),
    unresolved,
    alreadyRecovered: scope.alreadyRecovered,
    finalValidation,
  };
}

async function writeReports(report, options) {
  await Promise.all([
    fsp.mkdir(path.dirname(options.reportPath), { recursive: true }),
    fsp.mkdir(path.dirname(options.jsonReportPath), { recursive: true }),
  ]);
  await writeJsonAtomic(options.jsonReportPath, report);
  const lines = [
    "# Remaining Original-Media Archive Recovery",
    "",
    `Generated: ${report.generatedAt}`,
    "",
    "## Summary",
    "",
    `- Baseline report failures: ${report.summary.baselineFailures}`,
    `- Validated alternate-source candidates in this pass: ${report.summary.scopedCandidates}`,
    `- Recovered: ${report.summary.recoveredFiles}`,
    `- Candidate downloads still unresolved: ${report.summary.unresolvedCandidates}`,
    `- Recovered bytes: ${formatBytes(report.summary.recoveredBytes)}`,
    "",
    "Only tokens that were still failed in the baseline recovery report and current root manifest were considered. No successful token was probed or overwritten. Candidates were accepted only at the collection's native pixel dimensions, and every installed file was checked against the research-stage SHA-256 digest.",
    "",
    "## Collections",
    "",
    "| Collection | Scoped | Recovered | Candidate failures | Dimensions | Quality source |",
    "| --- | ---: | ---: | ---: | --- | --- |",
    ...report.collections.map((entry) => `| ${escapeCell(entry.collectionName)} | ${entry.scopedCandidates} | ${entry.recoveredFiles} | ${entry.unresolvedCandidates} | ${escapeCell(entry.dimensions.join(", "))} | ${escapeCell(entry.qualityClassifications.join(", "))} |`),
    "",
    "## Remaining candidate failures",
    "",
    ...(report.unresolved.length ? report.unresolved.map((entry) => `- ${escapeMarkdown(entry.collectionName)} ${escapeMarkdown(entry.tokenId)}: ${escapeMarkdown(entry.error)}`) : ["None."]),
    "",
  ];
  await fsp.writeFile(options.reportPath, `${lines.join("\n")}\n`);
}

async function finalizeRootManifest(root, scope, committed, report) {
  const recoveredKeys = new Set(committed.map((entry) => tokenKey(entry.internal_slug, entry.tokenId)));
  root.failures = root.failures.filter((failure) => !recoveredKeys.has(failureKey(failure)));
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

async function removeCandidateFiles(entries) {
  await Promise.all(entries.map((entry) => fsp.rm(entry.candidatePath, { force: true })));
}

async function removeStalePartFiles(scope) {
  for (const collection of scope.collections.values()) {
    const names = await fsp.readdir(collection.directory);
    await Promise.all(names.filter((name) => name.endsWith(".archive.part") || name === "manifest.json.tmp").map((name) => fsp.rm(path.join(collection.directory, name), { force: true })));
  }
}

function publicSourceEvidence(target) {
  if (target.internal_slug === "organic_evolution") {
    return {
      sourceDocumentId: target.sourceDocumentId,
      assetRef: target.assetRef,
      canonicalUrl: target.canonicalUrl,
      sanityReportedOriginalBytes: target.sanityReportedOriginalBytes,
      sanityReportedOriginalSha1: target.sanityReportedOriginalSha1,
      jpegQuality: target.jpegQuality,
    };
  }
  if (target.internal_slug === "tojiba_cpu_corp") {
    return { howRareId: target.howRareId, jpegQualityComment: target.jpegQualityComment };
  }
  if (target.internal_slug === "tojia") {
    return {
      sourceContract: target.sourceContract ?? null,
      sourceMetadataUrl: target.sourceMetadataUrl ?? null,
      sourceImageUri: target.sourceImageUri ?? null,
      alternateGatewayUrl: target.alternateGatewayUrl ?? null,
      solanaMetadataUrl: target.solanaMetadataUrl ?? null,
      dna: target.dna ?? null,
      editionDate: target.editionDate ?? null,
      validation: target.validation ?? null,
    };
  }
  return {};
}

function recoveryKind(slug) {
  if (slug === "organic_evolution") return "project-archive-native-dimension-derivative";
  if (slug === "tojiba_cpu_corp") return "marketplace-cache-native-dimension-recompression";
  if (slug === "tojia") return "official-cross-deployment-ipfs-exact";
  return "validated-alternate-source";
}

function recoveryDecision(slug) {
  if (slug === "tojia") return "accepted exact official IPFS artwork after edition/DNA/trait mapping and byte-identical surviving-peer validation";
  return "accepted alternate source at the collection's native pixel dimensions";
}

function publicRecovery(entry) {
  const { candidatePath, destinationPath, previousFileName, ...result } = entry;
  return result;
}

function publicFailure(target, error) {
  return { internal_slug: target.internal_slug, collectionId: target.collectionId, collectionName: target.collectionName, tokenId: target.tokenId, originalUrl: target.originalUrl ?? target.downloadUrl, candidateUrl: target.candidateUrl, error };
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

function uniqueMap(values, keyFunction, label) {
  const map = new Map();
  for (const value of values) {
    const key = keyFunction(value);
    if (map.has(key)) throw new Error(`Duplicate ${label}: ${key}`);
    map.set(key, value);
  }
  return map;
}

function failureKey(value) {
  return tokenKey(String(value.internal_slug ?? value.slug ?? ""), String(value.tokenId ?? ""));
}

function tokenKey(slug, tokenId) {
  return `${slug}\u0000${tokenId}`;
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
  const workers = Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    for (;;) {
      const index = next;
      next += 1;
      if (index >= items.length) return;
      await worker(items[index], index);
    }
  });
  await Promise.all(workers);
}

function targetSort(left, right) {
  return String(left.internal_slug).localeCompare(String(right.internal_slug)) || String(left.tokenId).localeCompare(String(right.tokenId));
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

function safeComponent(value) {
  const text = String(value);
  if (!/^[A-Za-z0-9_-]+$/u.test(text)) throw new Error(`Unsafe file component: ${text}`);
  return text;
}

function numeric(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function sha256Buffer(buffer) {
  return crypto.createHash("sha256").update(buffer).digest("hex");
}

function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash("sha256");
    const stream = fs.createReadStream(filePath);
    stream.on("error", reject);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve(hash.digest("hex")));
  });
}

async function readJson(filePath) {
  return JSON.parse(await fsp.readFile(filePath, "utf8"));
}

async function writeJsonAtomic(filePath, value, pretty = true) {
  const temporary = `${filePath}.tmp`;
  const payload = pretty ? `${JSON.stringify(value, null, 2)}\n` : `${JSON.stringify(value)}\n`;
  await fsp.writeFile(temporary, payload);
  await fsp.rename(temporary, filePath);
}

async function fileExists(filePath) {
  try { await fsp.access(filePath); return true; } catch { return false; }
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function formatBytes(value) {
  const units = ["B", "KB", "MB", "GB"];
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

main().catch((error) => {
  console.error(error.stack ?? error.message);
  console.error("");
  console.error(HELP);
  process.exit(1);
});
