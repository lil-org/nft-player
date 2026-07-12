#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const MODULE_PATH = fileURLToPath(import.meta.url);
const DEFAULT_REPO_ROOT = path.resolve(path.dirname(MODULE_PATH), "..");
const MANIFEST_FILE_NAME = "manifest.json";
const NUMERIC_MEDIA_FILE_NAME = /^\d+\.[a-z0-9]+$/u;
const JSON_START = /^(?:\uFEFF)?\s*[{[]/u;

const CANONICAL_EXTENSION_BY_KIND = new Map([
  ["gif", "gif"],
  ["glb", "glb"],
  ["heic", "heic"],
  ["html", "html"],
  ["jpg", "jpg"],
  ["json", "json"],
  ["mov", "mov"],
  ["mp4", "mp4"],
  ["pdf", "pdf"],
  ["png", "png"],
  ["svg", "svg"],
  ["tiff", "tiff"],
  ["webm", "webm"],
  ["webp", "webp"],
]);

export class OriginalsCleanupVerificationError extends Error {
  constructor(issues, summary) {
    const displayedIssues = issues.messages.map((issue) => `  - ${issue}`).join("\n");
    const omitted = issues.total - issues.messages.length;
    const omittedLine = omitted > 0 ? `\n  - ...and ${omitted} more issue(s)` : "";
    super(`Originals cleanup verification failed with ${issues.total} issue(s):\n${displayedIssues}${omittedLine}`);
    this.name = "OriginalsCleanupVerificationError";
    this.issues = [...issues.messages];
    this.issueCount = issues.total;
    this.summary = summary;
  }
}

class IssueCollector {
  constructor(limit) {
    this.limit = limit;
    this.messages = [];
    this.total = 0;
  }

  add(message) {
    this.total += 1;
    if (this.messages.length < this.limit) {
      this.messages.push(message);
    }
  }
}

/**
 * Verify the applied Originals Downloaded filename migration without mutating files.
 * Throws OriginalsCleanupVerificationError with aggregated diagnostics on failure.
 */
export async function verifyOriginalsCleanup({
  repoRoot = DEFAULT_REPO_ROOT,
  expectedPhysicalFiles = 145_179,
  expectedMissingRows = 7,
  expectedJsonPathManifests = 83,
  expectedOneByteFiles = 28,
  expectedCollectionDirectories = 109,
  expectedWidgetCollectionsWithTmpFiles = 32,
  signatureConcurrency = 32,
  maxIssues = 200,
} = {}) {
  const resolvedRoot = path.resolve(repoRoot);
  const originalsRoot = path.join(resolvedRoot, "Originals Downloaded");
  const primaryTokensRoot = path.join(resolvedRoot, "Suggested Items", "Suggested.bundle", "Tokens");
  const widgetTokensRoot = path.join(resolvedRoot, "Suggested Items", "WidgetSuggested.bundle", "Tokens");
  const issues = new IssueCollector(maxIssues);

  const primaryBundles = await readTokenBundles(primaryTokensRoot, "primary", issues);
  const widgetBundles = await readTokenBundles(widgetTokensRoot, "widget", issues);
  const collections = await readDownloadedCollections(originalsRoot, issues);
  const signatureInputs = [];
  const collectionIds = new Set();
  let physicalFiles = 0;
  let primaryMappedFiles = 0;
  let missingRows = 0;

  for (const collection of collections) {
    const collectionLabel = `Originals Downloaded/${collection.directoryName}`;
    const manifest = collection.manifest;
    const collectionId = stringValue(manifest?.collection?.id);

    if (!collectionId) {
      issues.add(`${collectionLabel}/manifest.json has no string collection.id`);
      continue;
    }
    if (collectionIds.has(collectionId)) {
      issues.add(`${collectionLabel}/manifest.json repeats collection ID ${collectionId}`);
    }
    collectionIds.add(collectionId);

    const manifestSlug = stringValue(manifest?.collection?.internal_slug);
    if (manifestSlug && manifestSlug !== collection.directoryName) {
      issues.add(`${collectionLabel}/manifest.json internal_slug is ${manifestSlug}, expected ${collection.directoryName}`);
    }

    const primaryBundle = primaryBundles.get(`${collectionId}.json`);
    if (!primaryBundle) {
      issues.add(`${collectionLabel} has no primary token bundle for collection ID ${collectionId}`);
      continue;
    }

    const tmpFiles = primaryBundle.tmpFiles;
    if (tmpFiles === null) {
      issues.add(`${primaryBundle.label} must contain a non-empty tmp_files object`);
    }

    const tokens = Array.isArray(manifest.tokens) ? manifest.tokens : null;
    if (!tokens) {
      issues.add(`${collectionLabel}/manifest.json tokens must be an array`);
      continue;
    }

    const physicalFileNames = collection.physicalFileNames;
    const manifestPresentFileNames = new Set();
    const manifestTokenIds = new Set();
    const mappedFileNames = new Set(tmpFiles?.values() ?? []);
    let collectionMissingRows = 0;
    physicalFiles += physicalFileNames.size;
    primaryMappedFiles += tmpFiles?.size ?? 0;

    for (const fileName of physicalFileNames) {
      signatureInputs.push({
        absolutePath: path.join(collection.absolutePath, fileName),
        relativePath: `${collection.directoryName}/${fileName}`,
        fileName,
      });
    }

    for (let index = 0; index < tokens.length; index += 1) {
      const token = tokens[index];
      const tokenLabel = `${collectionLabel}/manifest.json token[${index}]`;
      const tokenId = stringValue(token?.tokenId);
      const fileName = stringValue(token?.fileName);

      if (!tokenId) {
        issues.add(`${tokenLabel} has no string tokenId`);
        continue;
      }
      if (manifestTokenIds.has(tokenId)) {
        issues.add(`${tokenLabel} repeats tokenId ${tokenId}`);
      }
      manifestTokenIds.add(tokenId);
      if (!primaryBundle.itemIds.has(tokenId)) {
        issues.add(`${tokenLabel} tokenId ${tokenId} is absent from the primary token bundle items`);
      }

      if (fileName && !isSafeBasename(fileName)) {
        issues.add(`${tokenLabel} has unsafe fileName ${JSON.stringify(fileName)}`);
        continue;
      }

      const fileIsPresent = Boolean(fileName && physicalFileNames.has(fileName));
      const mappedFileName = tmpFiles?.get(tokenId);
      if (fileIsPresent) {
        if (manifestPresentFileNames.has(fileName)) {
          issues.add(`${collectionLabel}/manifest.json maps more than one token to ${fileName}`);
        }
        manifestPresentFileNames.add(fileName);
        if (mappedFileName !== fileName) {
          issues.add(`${primaryBundle.label} tmp_files[${JSON.stringify(tokenId)}] is ${JSON.stringify(mappedFileName)}, expected ${JSON.stringify(fileName)}`);
        }
      } else {
        missingRows += 1;
        collectionMissingRows += 1;
        if (mappedFileName !== undefined) {
          issues.add(`${primaryBundle.label} maps missing token ${tokenId} to ${JSON.stringify(mappedFileName)}`);
        }
      }
    }

    for (const tokenId of primaryBundle.itemIds) {
      if (!manifestTokenIds.has(tokenId)) {
        issues.add(`${primaryBundle.label} item ${tokenId} is absent from ${collectionLabel}/manifest.json`);
      }
    }
    assertManifestTotal(manifest, "tokensRecorded", tokens.length, collectionLabel, issues);
    assertManifestTotal(manifest, "successfulFiles", physicalFileNames.size, collectionLabel, issues);
    assertManifestTotal(manifest, "failedFiles", collectionMissingRows, collectionLabel, issues);

    for (const [tokenId, fileName] of tmpFiles ?? []) {
      if (!manifestTokenIds.has(tokenId)) {
        issues.add(`${primaryBundle.label} tmp_files contains token ${tokenId}, which is absent from the collection manifest`);
      }
      if (!physicalFileNames.has(fileName)) {
        issues.add(`${primaryBundle.label} tmp_files[${JSON.stringify(tokenId)}] points to missing file ${JSON.stringify(fileName)}`);
      }
    }
    for (const fileName of physicalFileNames) {
      if (!manifestPresentFileNames.has(fileName)) {
        issues.add(`${collectionLabel}/${fileName} is not referenced by a present manifest token`);
      }
      if (!mappedFileNames.has(fileName)) {
        issues.add(`${collectionLabel}/${fileName} is not referenced by primary tmp_files`);
      }
    }
  }

  for (const bundle of primaryBundles.values()) {
    const hasDownloadedCollection = collectionIds.has(bundle.collectionId);
    if (bundle.tmpFiles && !hasDownloadedCollection) {
      issues.add(`${bundle.label} contains tmp_files but has no Originals Downloaded collection`);
    }
    if (!bundle.tmpFiles && hasDownloadedCollection) {
      issues.add(`${bundle.label} is missing tmp_files for its Originals Downloaded collection`);
    }
  }

  let widgetCollectionsWithTmpFiles = 0;
  for (const widgetBundle of widgetBundles.values()) {
    const primaryBundle = primaryBundles.get(widgetBundle.fileName);
    if (!primaryBundle) {
      issues.add(`${widgetBundle.label} has no matching primary token bundle`);
      continue;
    }

    const expectedWidgetMap = new Map();
    for (const [tokenId, fileName] of primaryBundle.tmpFiles ?? []) {
      if (widgetBundle.itemIds.has(tokenId)) {
        expectedWidgetMap.set(tokenId, fileName);
      }
    }
    if ((widgetBundle.tmpFiles?.size ?? 0) > 0) {
      widgetCollectionsWithTmpFiles += 1;
    }
    compareTmpFileMaps(widgetBundle, expectedWidgetMap, issues);
  }

  const signatureResults = await mapWithConcurrency(
    signatureInputs,
    signatureConcurrency,
    (input) => inspectFileSignature(input, issues),
  );
  const signatureCounts = {};
  const extensionCounts = {};
  const jsonPathManifestFiles = [];
  const oneByteFiles = [];

  for (const result of signatureResults) {
    if (!result) {
      continue;
    }
    signatureCounts[result.kind] = (signatureCounts[result.kind] ?? 0) + 1;
    extensionCounts[result.extension] = (extensionCounts[result.extension] ?? 0) + 1;
    if (result.kind === "json") {
      jsonPathManifestFiles.push(result.relativePath);
    } else if (result.kind === "one-byte") {
      oneByteFiles.push(result.relativePath);
    }
  }

  jsonPathManifestFiles.sort(naturalCompare);
  oneByteFiles.sort(naturalCompare);

  const primaryCollectionsWithTmpFiles = [...primaryBundles.values()]
    .filter((bundle) => (bundle.tmpFiles?.size ?? 0) > 0)
    .length;
  const summary = {
    collectionDirectories: collections.length,
    physicalFiles,
    primaryBundleFiles: primaryBundles.size,
    primaryCollectionsWithTmpFiles,
    primaryMappedFiles,
    missingRows,
    widgetBundleFiles: widgetBundles.size,
    widgetCollectionsWithTmpFiles,
    jsonPathManifestFiles,
    oneByteFiles,
    signatureCounts: sortCountObject(signatureCounts),
    extensionCounts: sortCountObject(extensionCounts),
  };

  assertExpectedCount(issues, "collection directories", collections.length, expectedCollectionDirectories);
  assertExpectedCount(issues, "physical downloaded files", physicalFiles, expectedPhysicalFiles);
  assertExpectedCount(issues, "primary tmp_files mappings", primaryMappedFiles, expectedPhysicalFiles);
  assertExpectedCount(issues, "primary collections with tmp_files", primaryCollectionsWithTmpFiles, expectedCollectionDirectories);
  assertExpectedCount(issues, "missing manifest rows", missingRows, expectedMissingRows);
  assertExpectedCount(issues, "widget collections with tmp_files", widgetCollectionsWithTmpFiles, expectedWidgetCollectionsWithTmpFiles);
  assertExpectedCount(issues, "JSON path manifests", jsonPathManifestFiles.length, expectedJsonPathManifests);
  assertExpectedCount(issues, "one-byte files", oneByteFiles.length, expectedOneByteFiles);

  if (issues.total > 0) {
    throw new OriginalsCleanupVerificationError(issues, summary);
  }
  return summary;
}

async function readDownloadedCollections(originalsRoot, issues) {
  let rootEntries;
  try {
    rootEntries = await fs.readdir(originalsRoot, { withFileTypes: true });
  } catch (error) {
    issues.add(`Cannot read Originals Downloaded: ${error.message}`);
    return [];
  }

  const collections = [];
  for (const entry of rootEntries.sort((left, right) => naturalCompare(left.name, right.name))) {
    if (!entry.isDirectory()) {
      continue;
    }
    const absolutePath = path.join(originalsRoot, entry.name);
    const manifestPath = path.join(absolutePath, MANIFEST_FILE_NAME);
    let manifest;
    try {
      manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
    } catch (error) {
      issues.add(`Cannot parse Originals Downloaded/${entry.name}/manifest.json: ${error.message}`);
      continue;
    }

    const physicalFileNames = new Set();
    const directoryEntries = await fs.readdir(absolutePath, { withFileTypes: true });
    for (const directoryEntry of directoryEntries) {
      if (directoryEntry.name === MANIFEST_FILE_NAME) {
        continue;
      }
      if (!directoryEntry.isFile()) {
        issues.add(`Originals Downloaded/${entry.name}/${directoryEntry.name} is not a regular file`);
        continue;
      }
      physicalFileNames.add(directoryEntry.name);
    }
    collections.push({
      directoryName: entry.name,
      absolutePath,
      manifest,
      physicalFileNames,
    });
  }
  return collections;
}

async function readTokenBundles(tokensRoot, kind, issues) {
  let entries;
  try {
    entries = await fs.readdir(tokensRoot, { withFileTypes: true });
  } catch (error) {
    issues.add(`Cannot read ${kind} token bundles at ${tokensRoot}: ${error.message}`);
    return new Map();
  }

  const bundles = new Map();
  for (const entry of entries.sort((left, right) => naturalCompare(left.name, right.name))) {
    if (!entry.isFile() || path.extname(entry.name).toLowerCase() !== ".json") {
      continue;
    }
    const absolutePath = path.join(tokensRoot, entry.name);
    const label = `${kind} token bundle ${entry.name}`;
    let payload;
    try {
      payload = JSON.parse(await fs.readFile(absolutePath, "utf8"));
    } catch (error) {
      issues.add(`Cannot parse ${label}: ${error.message}`);
      continue;
    }
    const bundle = validateTokenBundle(payload, entry.name, label, issues);
    bundles.set(entry.name, bundle);
  }
  return bundles;
}

function validateTokenBundle(payload, fileName, label, issues) {
  const itemIds = new Set();
  const items = Array.isArray(payload?.items) ? payload.items : null;
  const prefixes = Array.isArray(payload?.urlPrefixes) ? payload.urlPrefixes : [];
  const rowKinds = new Set();

  if (!items) {
    issues.add(`${label} items must be an array`);
  }
  if (payload?.urlPrefixes !== undefined && !Array.isArray(payload.urlPrefixes)) {
    issues.add(`${label} urlPrefixes must be an array when present`);
  }
  for (let index = 0; index < prefixes.length; index += 1) {
    if (typeof prefixes[index] !== "string") {
      issues.add(`${label} urlPrefixes[${index}] must be a string`);
    }
  }

  for (let index = 0; index < (items?.length ?? 0); index += 1) {
    const item = items[index];
    const itemLabel = `${label} item[${index}]`;
    let tokenId;

    if (Array.isArray(item)) {
      rowKinds.add("compact");
      if (item.length !== 3 && item.length !== 4) {
        issues.add(`${itemLabel} compact row must have 3 or 4 values`);
        continue;
      }
      tokenId = stringValue(item[0]);
      const prefixIndex = item[1];
      const suffix = item[2];
      if (!Number.isInteger(prefixIndex) || prefixIndex < 0 || prefixIndex >= prefixes.length) {
        issues.add(`${itemLabel} has invalid URL prefix index ${JSON.stringify(prefixIndex)}`);
      }
      if (typeof suffix !== "string") {
        issues.add(`${itemLabel} URL suffix must be a string`);
      } else if (Number.isInteger(prefixIndex) && typeof prefixes[prefixIndex] === "string") {
        assertParseableURL(`${prefixes[prefixIndex]}${suffix}`, `${itemLabel} reconstructed URL`, issues);
      }
      if (item.length === 4 && (typeof item[3] !== "string" || item[3].trim() === "")) {
        issues.add(`${itemLabel} file extension override must be a non-empty string`);
      }
    } else if (isPlainObject(item)) {
      rowKinds.add("object");
      tokenId = stringValue(item.id);
      if (item.url !== undefined && item.url !== null) {
        if (typeof item.url !== "string") {
          issues.add(`${itemLabel} url must be a string when present`);
        } else {
          assertParseableURL(item.url, `${itemLabel} URL`, issues);
        }
      }
    } else {
      issues.add(`${itemLabel} must be a compact row or object`);
      continue;
    }

    if (!tokenId) {
      issues.add(`${itemLabel} has no string token ID`);
    } else if (itemIds.has(tokenId)) {
      issues.add(`${itemLabel} repeats token ID ${tokenId}`);
    } else {
      itemIds.add(tokenId);
    }
  }
  if (rowKinds.size > 1) {
    issues.add(`${label} mixes compact and object token rows`);
  }

  const tmpFiles = validateTmpFiles(payload, itemIds, label, issues);
  return {
    fileName,
    collectionId: fileName.slice(0, -path.extname(fileName).length),
    label,
    payload,
    itemIds,
    tmpFiles,
  };
}

function validateTmpFiles(payload, itemIds, label, issues) {
  if (!Object.hasOwn(payload ?? {}, "tmp_files")) {
    return null;
  }
  if (!isPlainObject(payload.tmp_files)) {
    issues.add(`${label} tmp_files must be an object`);
    return null;
  }

  const result = new Map();
  const fileNames = new Set();
  for (const [tokenId, fileName] of Object.entries(payload.tmp_files)) {
    if (!tokenId || typeof fileName !== "string" || !isSafeBasename(fileName)) {
      issues.add(`${label} has invalid tmp_files entry ${JSON.stringify(tokenId)}: ${JSON.stringify(fileName)}`);
      continue;
    }
    if (!itemIds.has(tokenId)) {
      issues.add(`${label} tmp_files token ${tokenId} is absent from items`);
    }
    if (fileNames.has(fileName)) {
      issues.add(`${label} tmp_files maps more than one token to ${fileName}`);
    }
    fileNames.add(fileName);
    result.set(tokenId, fileName);
  }
  if (result.size === 0) {
    issues.add(`${label} must omit an empty tmp_files object`);
    return null;
  }
  return result;
}

function compareTmpFileMaps(widgetBundle, expectedMap, issues) {
  const actualMap = widgetBundle.tmpFiles ?? new Map();
  if (actualMap.size !== expectedMap.size) {
    issues.add(`${widgetBundle.label} has ${actualMap.size} tmp_files entries, expected ${expectedMap.size}`);
  }
  for (const [tokenId, expectedFileName] of expectedMap) {
    const actualFileName = actualMap.get(tokenId);
    if (actualFileName !== expectedFileName) {
      issues.add(`${widgetBundle.label} tmp_files[${JSON.stringify(tokenId)}] is ${JSON.stringify(actualFileName)}, expected ${JSON.stringify(expectedFileName)}`);
    }
  }
  for (const tokenId of actualMap.keys()) {
    if (!expectedMap.has(tokenId)) {
      issues.add(`${widgetBundle.label} tmp_files contains unexpected token ${tokenId}`);
    }
  }
}

async function inspectFileSignature(input, issues) {
  let handle;
  try {
    handle = await fs.open(input.absolutePath, "r");
    const stat = await handle.stat();
    const prefix = Buffer.alloc(Math.min(stat.size, 4096));
    const { bytesRead } = await handle.read(prefix, 0, prefix.length, 0);
    const bytes = prefix.subarray(0, bytesRead);
    let kind = detectFileKind(bytes, stat.size);

    if (kind === "json") {
      try {
        JSON.parse(await fs.readFile(input.absolutePath, "utf8"));
      } catch (error) {
        issues.add(`Originals Downloaded/${input.relativePath} looks like JSON but cannot be parsed: ${error.message}`);
        kind = "unknown";
      }
    }

    const extension = path.extname(input.fileName).slice(1);
    if (extension.toLowerCase() === "jpeg") {
      issues.add(`Originals Downloaded/${input.relativePath} still uses the .jpeg extension`);
    }
    if (extension !== extension.toLowerCase()) {
      issues.add(`Originals Downloaded/${input.relativePath} has a non-lowercase extension`);
    }
    if (!NUMERIC_MEDIA_FILE_NAME.test(input.fileName)) {
      issues.add(`Originals Downloaded/${input.relativePath} does not use a numeric normalized filename`);
    }

    if (kind === "unknown") {
      issues.add(`Originals Downloaded/${input.relativePath} has an unrecognized file signature`);
    } else if (kind !== "one-byte") {
      const canonicalExtension = CANONICAL_EXTENSION_BY_KIND.get(kind);
      if (canonicalExtension !== extension) {
        issues.add(`Originals Downloaded/${input.relativePath} has ${kind} content and must use .${canonicalExtension}`);
      }
    }

    return { ...input, size: stat.size, kind, extension };
  } catch (error) {
    issues.add(`Cannot inspect Originals Downloaded/${input.relativePath}: ${error.message}`);
    return null;
  } finally {
    await handle?.close();
  }
}

export function detectFileKind(bytes, fileSize = bytes.length) {
  if (fileSize === 1) {
    return "one-byte";
  }
  if (startsWithBytes(bytes, [0xff, 0xd8, 0xff])) {
    return "jpg";
  }
  if (startsWithBytes(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return "png";
  }
  if (/^GIF8[79]a/u.test(ascii(bytes, 0, 6))) {
    return "gif";
  }
  if (ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 12) === "WEBP") {
    return "webp";
  }
  if (ascii(bytes, 0, 4) === "glTF") {
    return "glb";
  }
  if (startsWithBytes(bytes, [0x49, 0x49, 0x2a, 0x00]) || startsWithBytes(bytes, [0x4d, 0x4d, 0x00, 0x2a])) {
    return "tiff";
  }
  if (ascii(bytes, 0, 5) === "%PDF-") {
    return "pdf";
  }
  if (ascii(bytes, 4, 8) === "ftyp") {
    const brand = ascii(bytes, 8, 12);
    if (brand === "qt  ") {
      return "mov";
    }
    if (["heic", "heix", "hevc", "hevx", "mif1", "msf1"].includes(brand)) {
      return "heic";
    }
    return "mp4";
  }
  if (startsWithBytes(bytes, [0x1a, 0x45, 0xdf, 0xa3])) {
    return "webm";
  }

  const text = bytes.toString("utf8");
  if (JSON_START.test(text)) {
    return "json";
  }
  const trimmedText = text.replace(/^\uFEFF/u, "").trimStart();
  if (/^(?:<!doctype\s+html|<html[\s>])/iu.test(trimmedText)) {
    return "html";
  }
  if (/^(?:<\?xml[\s\S]{0,400}<svg|<svg[\s>])/iu.test(trimmedText)) {
    return "svg";
  }
  return "unknown";
}

async function mapWithConcurrency(values, concurrency, transform) {
  const results = new Array(values.length);
  let nextIndex = 0;
  const workerCount = Math.max(1, Math.min(concurrency, values.length || 1));
  await Promise.all(Array.from({ length: workerCount }, async () => {
    while (nextIndex < values.length) {
      const index = nextIndex;
      nextIndex += 1;
      results[index] = await transform(values[index], index);
    }
  }));
  return results;
}

function assertExpectedCount(issues, label, actual, expected) {
  if (expected !== null && expected !== undefined && actual !== expected) {
    issues.add(`Found ${actual} ${label}, expected ${expected}`);
  }
}

function assertManifestTotal(manifest, key, expected, collectionLabel, issues) {
  const actual = manifest?.totals?.[key];
  if (actual !== expected) {
    issues.add(`${collectionLabel}/manifest.json totals.${key} is ${JSON.stringify(actual)}, expected ${expected}`);
  }
}

function assertParseableURL(value, label, issues) {
  try {
    new URL(value);
  } catch {
    issues.add(`${label} is not parseable: ${JSON.stringify(value)}`);
  }
}

function stringValue(value) {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isSafeBasename(value) {
  return value !== "."
    && value !== ".."
    && !value.includes("/")
    && !value.includes("\\")
    && !value.includes("\0")
    && path.basename(value) === value;
}

function startsWithBytes(buffer, values) {
  return buffer.length >= values.length && values.every((value, index) => buffer[index] === value);
}

function ascii(buffer, start, end) {
  return buffer.length >= end ? buffer.toString("ascii", start, end) : "";
}

function naturalCompare(left, right) {
  return String(left).localeCompare(String(right), undefined, { numeric: true, sensitivity: "base" });
}

function sortCountObject(counts) {
  return Object.fromEntries(Object.entries(counts).sort(([left], [right]) => naturalCompare(left, right)));
}

function parseArgs(argv) {
  const options = { repoRoot: DEFAULT_REPO_ROOT, json: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--json") {
      options.json = true;
    } else if (argument === "--root") {
      const value = argv[index + 1];
      if (!value) {
        throw new Error("--root requires a path");
      }
      options.repoRoot = value;
      index += 1;
    } else if (argument === "--help" || argument === "-h") {
      options.help = true;
    } else {
      throw new Error(`Unknown argument: ${argument}`);
    }
  }
  return options;
}

function printHelp() {
  console.log(`Usage: node tools/verify_originals_cleanup.mjs [--root PATH] [--json]\n\nVerifies downloaded-original filenames, signatures, manifests, and primary/widget tmp_files mappings without writing files.`);
}

function printHumanSummary(summary) {
  console.log("Originals cleanup verification passed.");
  console.log(`  Collection directories: ${summary.collectionDirectories.toLocaleString("en-US")}`);
  console.log(`  Physical files / primary mappings: ${summary.physicalFiles.toLocaleString("en-US")}`);
  console.log(`  Missing manifest rows: ${summary.missingRows.toLocaleString("en-US")}`);
  console.log(`  Widget collections with tmp_files: ${summary.widgetCollectionsWithTmpFiles.toLocaleString("en-US")}`);
  console.log(`  JSON path manifests: ${summary.jsonPathManifestFiles.length.toLocaleString("en-US")}`);
  console.log(`  One-byte files: ${summary.oneByteFiles.length.toLocaleString("en-US")}`);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    printHelp();
    return;
  }
  const summary = await verifyOriginalsCleanup({ repoRoot: options.repoRoot });
  if (options.json) {
    console.log(JSON.stringify(summary, null, 2));
  } else {
    printHumanSummary(summary);
  }
}

if (path.resolve(process.argv[1] ?? "") === MODULE_PATH) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  });
}
