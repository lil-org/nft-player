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
const BASELINE_MARKDOWN_PATH = path.join(__dirname, "reports", "originals-download-recovery.md");
const CANDIDATE_REPORT_PATH = path.join(__dirname, "reports", "remaining-solana-marketplace-candidates.json");
const REPORT_PATH = path.join(__dirname, "reports", "originals-download-recovery-final.md");
const JSON_REPORT_PATH = path.join(__dirname, "reports", "originals-download-recovery-final.json");
const BUNDLE_TOKEN_ROOT = path.join(ROOT, "Suggested Items", "Suggested.bundle", "Tokens");

async function main() {
  const startedAt = new Date();
  const [baseline, candidates, rootManifest, baselineStat, baselineSha256, baselineMarkdownStat, baselineMarkdownSha256] = await Promise.all([
    readJson(BASELINE_REPORT_PATH),
    readJson(CANDIDATE_REPORT_PATH),
    readJson(ROOT_MANIFEST_PATH),
    fsp.stat(BASELINE_REPORT_PATH),
    sha256File(BASELINE_REPORT_PATH),
    fsp.stat(BASELINE_MARKDOWN_PATH),
    sha256File(BASELINE_MARKDOWN_PATH),
  ]);
  if (!Array.isArray(baseline.failures)) throw new Error("Baseline report has no failures array");
  if (!Array.isArray(candidates.candidates)) throw new Error("Candidate report has no candidates array");

  const manifestBySlug = new Map();
  for (const slug of new Set(baseline.failures.map((entry) => entry.internal_slug))) {
    const manifestPath = path.join(DOWNLOAD_ROOT, slug, "manifest.json");
    manifestBySlug.set(slug, { manifestPath, directory: path.dirname(manifestPath), manifest: await readJson(manifestPath) });
  }

  const entries = new Array(baseline.failures.length);
  await runPool(baseline.failures, 8, async (failure, index) => {
    entries[index] = await verifyFailure(failure, manifestBySlug.get(failure.internal_slug));
    const entry = entries[index];
    console.error(`  ${index + 1}/${baseline.failures.length} ${failure.internal_slug} ${failure.tokenId}: ${entry.valid ? "verified" : entry.issues.join("; ")}`);
  });

  const partFiles = [];
  for (const [slug, collection] of manifestBySlug) {
    const names = await fsp.readdir(collection.directory);
    for (const name of names.filter((entry) => entry.endsWith(".part"))) partFiles.push({ internal_slug: slug, fileName: name });
  }
  const bundleValidation = await validateCandidateBundleRows(candidates.candidates, manifestBySlug);
  const report = buildReport({
    startedAt,
    baseline,
    rootManifest,
    entries,
    partFiles,
    bundleValidation,
    baselineStat,
    baselineSha256,
    baselineMarkdownStat,
    baselineMarkdownSha256,
  });
  await Promise.all([writeJsonAtomic(JSON_REPORT_PATH, report), writeMarkdownReport(report)]);
  console.error(`Verified ${report.summary.verifiedFiles}/${report.summary.baselineFailures}; unresolved ${report.summary.unresolvedFiles}; root failures ${report.summary.rootManifestFailures}.`);
  if (!report.summary.passed) process.exitCode = 2;
}

async function verifyFailure(failure, collection) {
  const issues = [];
  if (!collection) {
    return { ...publicFailure(failure), valid: false, issues: ["collection manifest is missing"] };
  }
  const token = collection.manifest.tokens.find((entry) => String(entry.tokenId) === String(failure.tokenId));
  if (!token) return { ...publicFailure(failure), valid: false, issues: ["token is missing from collection manifest"] };
  if (token.status !== "success") issues.push(`manifest status is ${token.status ?? "missing"}`);
  if (!token.sha256) issues.push("manifest SHA-256 is missing");
  const filePath = path.join(collection.directory, String(token.fileName ?? ""));
  const exists = await fileExists(filePath);
  if (!exists) issues.push("downloaded file is missing");
  const [actualSha256, mediaProbe] = exists
    ? await Promise.all([sha256File(filePath), identifyFile(filePath)])
    : [null, null];
  if (exists && token.sha256 && actualSha256 !== token.sha256) issues.push("downloaded file SHA-256 does not match manifest");
  if (!mediaProbe) issues.push("downloaded file is not a readable image");
  else {
    const qualityIssue = validateCollectionQuality(failure.internal_slug, mediaProbe);
    if (qualityIssue) issues.push(qualityIssue);
  }
  const stat = exists ? await fsp.stat(filePath) : null;
  if (stat && Number(token.bytesWritten) !== stat.size) issues.push("downloaded file byte length does not match manifest");
  return {
    ...publicFailure(failure),
    status: token.status ?? null,
    fileName: token.fileName ?? null,
    exists,
    bytes: stat?.size ?? null,
    sha256: actualSha256,
    manifestSha256: token.sha256 ?? null,
    mediaProbe,
    recoveryClass: recoveryClass(token),
    recoverySource: token.recoverySource ?? null,
    qualityRepair: token.qualityRepair ? {
      apiSource: token.qualityRepair.apiSource ?? null,
      modifiedFallback: Boolean(token.qualityRepair.modifiedFallback),
      decision: token.qualityRepair.decision ?? null,
    } : null,
    valid: issues.length === 0,
    issues,
  };
}

function validateCollectionQuality(slug, probe) {
  const format = probe.format === "jpg" ? "jpeg" : probe.format;
  if (slug === "scarecrow" && !(format === "png" && probe.width === 1000 && probe.height === 1250)) return `expected native 1000x1250 PNG, found ${probe.width}x${probe.height} ${format}`;
  if (slug === "tojiba_disc_buddies" && !(format === "png" && probe.width === 512 && probe.height === 512)) return `expected native 512x512 PNG, found ${probe.width}x${probe.height} ${format}`;
  if (slug === "organic_evolution" && !(format === "jpeg" && probe.width >= 2400 && probe.height >= 2400 && probe.width === probe.height)) return `expected native-dimension square JPEG at least 2400px, found ${probe.width}x${probe.height} ${format}`;
  if (slug === "tojia" && !(format === "png" && probe.width === 640 && probe.height === 640)) return `expected native 640x640 PNG, found ${probe.width}x${probe.height} ${format}`;
  if (slug === "tojiba_cpu_corp" && !(["png", "jpeg"].includes(format) && probe.width === 640 && probe.height === 640)) return `expected native-dimension 640x640 image, found ${probe.width}x${probe.height} ${format}`;
  if (slug === "cigawrette_packs" && !(format === "jpeg" && probe.width >= 3456 && probe.height >= 4320)) return `expected high-resolution Cigawrette JPEG, found ${probe.width}x${probe.height} ${format}`;
  if (slug === "tigerbob" && !(["png", "jpeg"].includes(format) && probe.width >= 1000 && probe.height >= 1000)) return `expected at least 1000x1000 Tigerbob image, found ${probe.width}x${probe.height} ${format}`;
  return null;
}

async function validateCandidateBundleRows(candidates, manifestBySlug) {
  const bundleBySlug = new Map();
  const entries = [];
  for (const candidate of candidates) {
    const slug = String(candidate.slug ?? candidate.internal_slug ?? "");
    let bundle = bundleBySlug.get(slug);
    if (!bundle) {
      const collection = manifestBySlug.get(slug);
      if (!collection) throw new Error(`Candidate collection is outside baseline scope: ${slug}`);
      const bundlePath = path.join(BUNDLE_TOKEN_ROOT, `${collection.manifest.collection.id}.json`);
      bundle = { bundlePath, payload: await readJson(bundlePath) };
      bundleBySlug.set(slug, bundle);
    }
    const row = bundle.payload.items.find((item) => String(Array.isArray(item) ? item[0] : item?.id) === String(candidate.tokenId));
    let actualUrl = null;
    let extension = null;
    if (Array.isArray(row)) {
      actualUrl = `${bundle.payload.urlPrefixes[Number(row[1])] ?? ""}${row[2] ?? ""}`;
      extension = row[3] ?? bundle.payload.defaultFileExtension ?? null;
    } else if (row && typeof row === "object") {
      actualUrl = row.url ?? null;
      extension = row.fileExtension ?? bundle.payload.defaultFileExtension ?? null;
    }
    const expectedExtension = String(candidate.contentType).includes("png") ? "png" : "jpg";
    const valid = actualUrl === candidate.candidateUrl && [expectedExtension, expectedExtension === "jpg" ? "jpeg" : expectedExtension].includes(extension);
    entries.push({ internal_slug: slug, tokenId: candidate.tokenId, expectedUrl: candidate.candidateUrl, actualUrl, expectedExtension, actualExtension: extension, valid });
  }
  return { candidates: entries.length, validRows: entries.filter((entry) => entry.valid).length, invalidRows: entries.filter((entry) => !entry.valid).length, entries };
}

function recoveryClass(token) {
  const kind = token.recoverySource?.kind;
  if (kind === "ans-104-parent-bundle-chunks") return "exact original ANS-104 payload";
  if (kind === "official-cross-deployment-ipfs-exact") return "exact original official IPFS mirror";
  if (kind === "project-archive-native-dimension-derivative") return "native-dimension project archive derivative";
  if (kind === "marketplace-cache-native-dimension-recompression") return "native-dimension marketplace cache recompression";
  if (token.qualityRepair?.modifiedFallback) return "prior high-resolution alternate-source repair";
  if (token.qualityRepair) return "prior canonical-source repair";
  return "recovered success";
}

function buildReport({ startedAt, baseline, rootManifest, entries, partFiles, bundleValidation, baselineStat, baselineSha256, baselineMarkdownStat, baselineMarkdownSha256 }) {
  const unresolved = entries.filter((entry) => !entry.valid);
  const recoveryClasses = countsBy(entries, (entry) => entry.recoveryClass);
  const collections = [];
  for (const [slug, rows] of groupBy(entries, (entry) => entry.internal_slug)) {
    const bytes = rows.map((entry) => Number(entry.bytes ?? 0)).filter((value) => value > 0);
    collections.push({
      internal_slug: slug,
      collectionName: rows[0].collectionName,
      baselineFailures: rows.length,
      verifiedFiles: rows.filter((entry) => entry.valid).length,
      unresolvedFiles: rows.filter((entry) => !entry.valid).length,
      formatsAndDimensions: [...new Set(rows.filter((entry) => entry.mediaProbe).map((entry) => `${entry.mediaProbe.width}x${entry.mediaProbe.height} ${entry.mediaProbe.format}`))].sort(),
      bytesMin: bytes.length ? Math.min(...bytes) : null,
      bytesMax: bytes.length ? Math.max(...bytes) : null,
    });
  }
  collections.sort((left, right) => left.internal_slug.localeCompare(right.internal_slug));
  const rootManifestFailures = Array.isArray(rootManifest.failures) ? rootManifest.failures.length : null;
  const rootFailedFiles = Number(rootManifest.totals?.failedFiles);
  const passed = unresolved.length === 0
    && partFiles.length === 0
    && bundleValidation.invalidRows === 0
    && rootManifestFailures === 0
    && rootFailedFiles === 0;
  return {
    generatedAt: new Date().toISOString(),
    startedAt: startedAt.toISOString(),
    scope: "Only the failures persisted in originals-download-recovery.json; no other tokens or collections were probed",
    baselineReport: {
      json: {
        path: BASELINE_REPORT_PATH,
        sha256: baselineSha256,
        bytes: baselineStat.size,
        modifiedAt: baselineStat.mtime.toISOString(),
      },
      markdown: {
        path: BASELINE_MARKDOWN_PATH,
        sha256: baselineMarkdownSha256,
        bytes: baselineMarkdownStat.size,
        modifiedAt: baselineMarkdownStat.mtime.toISOString(),
      },
    },
    rootManifestPath: ROOT_MANIFEST_PATH,
    reportPath: REPORT_PATH,
    jsonReportPath: JSON_REPORT_PATH,
    summary: {
      passed,
      baselineFailures: baseline.failures.length,
      verifiedFiles: entries.length - unresolved.length,
      unresolvedFiles: unresolved.length,
      rootManifestFailures,
      rootFailedFiles,
      partFiles: partFiles.length,
      candidateBundleRows: bundleValidation.candidates,
      validCandidateBundleRows: bundleValidation.validRows,
      invalidCandidateBundleRows: bundleValidation.invalidRows,
      verifiedBytes: entries.reduce((sum, entry) => sum + Number(entry.bytes ?? 0), 0),
      elapsedMs: Date.now() - startedAt.getTime(),
    },
    recoveryClasses,
    collections,
    unresolved,
    partFiles,
    bundleValidation,
    entries,
  };
}

async function writeMarkdownReport(report) {
  const lines = [
    "# Original-Media Failure Recovery — Final Reconciliation",
    "",
    `Generated: ${report.generatedAt}`,
    "",
    "## Result",
    "",
    `- Baseline failed rows: ${report.summary.baselineFailures}`,
    `- Verified recovered files: ${report.summary.verifiedFiles}`,
    `- Still unresolved: ${report.summary.unresolvedFiles}`,
    `- Root manifest failures: ${report.summary.rootManifestFailures}`,
    `- Leftover partial files: ${report.summary.partFiles}`,
    `- Alternate-source bundle rows verified: ${report.summary.validCandidateBundleRows}/${report.summary.candidateBundleRows}`,
    `- Baseline files verified: ${formatBytes(report.summary.verifiedBytes)}`,
    "",
    "The verification scope is exactly the failure rows persisted in `originals-download-recovery.json`. It checks current success state, file existence, SHA-256, byte length, actual image format/native dimensions, partial-file cleanup, and the 48 alternate-source bundled URLs. It does not inspect unrelated tokens or collections.",
    "",
    "## Collections",
    "",
    "| Collection | Baseline failures | Verified | Unresolved | Current recovered formats |",
    "| --- | ---: | ---: | ---: | --- |",
    ...report.collections.map((entry) => `| ${escapeCell(entry.collectionName)} | ${entry.baselineFailures} | ${entry.verifiedFiles} | ${entry.unresolvedFiles} | ${escapeCell(entry.formatsAndDimensions.join(", "))} |`),
    "",
    "## Recovery provenance",
    "",
    "| Recovery class | Files |",
    "| --- | ---: |",
    ...Object.entries(report.recoveryClasses).sort((left, right) => right[1] - left[1]).map(([name, count]) => `| ${escapeCell(name)} | ${count} |`),
    "",
    "The 41 CPU Corp files are native 640x640 marketplace-cache JPEG recompressions. The three Organic Evolution files are native 2401x2401 quality-100 project-archive derivatives because the raw Sanity assets now require authentication. The four TOJIA files are exact official IPFS originals, established by matching edition/DNA/date/traits and byte-identical surviving peers.",
    "",
    "## Unresolved",
    "",
    ...(report.unresolved.length ? report.unresolved.map((entry) => `- ${escapeMarkdown(entry.collectionName)} ${escapeMarkdown(entry.tokenId)}: ${escapeMarkdown(entry.issues.join("; "))}`) : ["None."]),
    "",
    "## Baseline preservation",
    "",
    `- Original recovery Markdown SHA-256: \`${report.baselineReport.markdown.sha256}\``,
    `- Original recovery Markdown modified: ${report.baselineReport.markdown.modifiedAt}`,
    `- Original recovery JSON SHA-256: \`${report.baselineReport.json.sha256}\``,
    `- Original recovery JSON modified: ${report.baselineReport.json.modifiedAt}`,
    "",
    "The original recovery report remains the baseline; this final report is separate.",
    "",
  ];
  await fsp.writeFile(REPORT_PATH, `${lines.join("\n")}\n`);
}

function publicFailure(failure) {
  return {
    collectionId: failure.collectionId,
    collectionName: failure.collectionName,
    internal_slug: failure.internal_slug,
    tokenId: String(failure.tokenId),
    originalDownloadUrl: failure.downloadUrl,
    originalStatusCode: failure.statusCode ?? null,
    originalError: failure.error ?? null,
  };
}

function countsBy(values, keyFunction) {
  const result = {};
  for (const value of values) {
    const key = keyFunction(value);
    result[key] = (result[key] ?? 0) + 1;
  }
  return result;
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

async function identifyFile(filePath) {
  const execution = await runCommand("identify", ["-ping", "-format", "%w\t%h\t%m\t%z\t%Q", `${filePath}[0]`], 60000);
  if (execution.exitCode !== 0) return null;
  const [widthValue, heightValue, formatValue, bitDepthValue, qualityValue] = execution.stdout.trim().split("\t");
  const width = Number(widthValue);
  const height = Number(heightValue);
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return null;
  return { kind: "image", format: String(formatValue).toLowerCase(), width, height, area: width * height, aspectRatio: Number((width / height).toFixed(5)), bitDepth: Number(bitDepthValue) || null, quality: Number(qualityValue) || null };
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

function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash("sha256");
    const stream = fs.createReadStream(filePath);
    stream.on("error", reject);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve(hash.digest("hex")));
  });
}

async function fileExists(filePath) {
  try { await fsp.access(filePath); return true; } catch { return false; }
}

async function readJson(filePath) {
  return JSON.parse(await fsp.readFile(filePath, "utf8"));
}

async function writeJsonAtomic(filePath, value) {
  const temporary = `${filePath}.tmp`;
  await fsp.writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`);
  await fsp.rename(temporary, filePath);
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
  process.exit(1);
});
