#!/usr/bin/env node

import { constants as fsConstants } from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import suggestedItems from "../tools/suggested_items.js";

const { assertValidInternalSlugs, INTERNAL_SLUG_PATTERN, MAX_INTERNAL_SLUG_LENGTH } = suggestedItems;

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, "..");
const suggestedItemsDirectory = path.join(repositoryRoot, "Suggested Items");
export async function generateWidgetResources(directory, { check = false } = {}) {
  const sourceBundleDirectory = path.join(directory, "Suggested.bundle");
  const outputBundleDirectory = path.join(directory, "WidgetSuggested.bundle");
  const eligibleCollectionsPath = path.join(directory, "widget-eligible-collections.json");
  const eligibleSlugs = await readEligibleCollectionSlugs(eligibleCollectionsPath);
  const sourceItems = await readJSON(path.join(sourceBundleDirectory, "items.json"));
  if (!Array.isArray(sourceItems)) {
    throw new Error("Suggested.bundle/items.json must contain a JSON array.");
  }
  assertValidInternalSlugs(sourceItems);
  const itemsBySlug = new Map(sourceItems.map((item) => [item.internal_slug, item]));

  const selectedItems = [];
  const missingItems = [];
  for (const slug of eligibleSlugs) {
    const item = itemsBySlug.get(slug);
    if (item) {
      selectedItems.push(item);
    } else {
      missingItems.push(slug);
    }
  }
  failIfAny("Missing collection slugs in Suggested.bundle/items.json", missingItems);

  const expectedBundleFiles = new Map();
  expectedBundleFiles.set(
    "items.json",
    Buffer.from(`${JSON.stringify(selectedItems, null, 2)}\n`)
  );

  const missingTokens = [];
  for (const slug of eligibleSlugs) {
    const tokenPath = path.join(sourceBundleDirectory, "Tokens", `${slug}.json`);
    if (!(await exists(tokenPath))) {
      missingTokens.push(slug);
      continue;
    }
    const source = await fs.readFile(tokenPath, "utf8");
    const payload = widgetTokenPayload(JSON.parse(source), itemsBySlug.get(slug));
    const indentation = /^\s*\{[^\S\n]*\n/u.test(source) ? 2 : undefined;
    expectedBundleFiles.set(
      path.join("Tokens", path.basename(tokenPath)),
      Buffer.from(`${JSON.stringify(payload, null, indentation)}${source.endsWith("\n") ? "\n" : ""}`)
    );
  }
  failIfAny("Missing token JSON files in Suggested.bundle/Tokens", missingTokens);

  if (check) {
    await checkOutput(outputBundleDirectory, expectedBundleFiles);
    return;
  }

  await writeOutput(outputBundleDirectory, expectedBundleFiles);
}

function widgetTokenPayload(payload, collection) {
  const urlPrefix = payload.urlPrefix ?? "";
  let usesPrefix = false;
  let usesDefaultFileExtension = false;
  const items = payload.items.map((item) => {
    const compact = Array.isArray(item);
    const id = compact ? item[0] : item.id;
    const url = compact ? urlPrefix + item[1] : item.url;
    const sourceURL = url
      ?? (item.sh != null ? `https://cdn.simplehash.com/assets/${item.sh}` : undefined)
      ?? (collection.chain === "ethereum" ? `https://media-proxy.artblocks.io/${collection.address}/${id}.png` : undefined);
    const pathExtension = explicitPathExtension(sourceURL);
    const fileExtension = pathExtension
      ? undefined
      : normalizedFileExtension(compact ? item[2] : item.fileExtension);
    if (sourceURL != null && !pathExtension && fileExtension == null) {
      usesDefaultFileExtension = true;
    }
    if (compact) {
      usesPrefix = true;
      return fileExtension == null ? item.slice(0, 2) : [...item.slice(0, 2), fileExtension];
    }
    return {
      id,
      ...(url != null ? { url } : item.sh != null ? { sh: item.sh } : {}),
      ...(fileExtension != null ? { fileExtension } : {}),
    };
  });
  const defaultFileExtension = usesDefaultFileExtension
    ? normalizedFileExtension(payload.defaultFileExtension)
    : undefined;
  return {
    ...(defaultFileExtension != null ? { defaultFileExtension } : {}),
    ...(usesPrefix ? { urlPrefix } : {}),
    items,
  };
}

function normalizedFileExtension(value) {
  if (typeof value !== "string") return undefined;
  const normalized = value.replace(/^[. \n\t\r]+|[. \n\t\r]+$/gu, "").toLowerCase();
  return normalized === "" ? undefined : normalized;
}

function explicitPathExtension(url) {
  if (url == null) return undefined;
  try {
    return normalizedFileExtension(path.posix.extname(new URL(url).pathname));
  } catch {
    return undefined;
  }
}

async function readEligibleCollectionSlugs(eligibleCollectionsPath) {
  const value = await readJSON(eligibleCollectionsPath);
  if (!Array.isArray(value)) {
    throw new Error("widget-eligible-collections.json must contain a JSON array.");
  }

  const slugs = value.map((item) => {
    if (typeof item !== "string" || !INTERNAL_SLUG_PATTERN.test(item) || item.length > MAX_INTERNAL_SLUG_LENGTH) {
      throw new Error("widget-eligible-collections.json must contain only valid internal_slug strings.");
    }
    return item;
  });

  const duplicates = slugs.filter((slug, index) => slugs.indexOf(slug) !== index);
  failIfAny("Duplicate collection slugs in widget-eligible-collections.json", duplicates);
  return slugs;
}

async function readJSON(filePath) {
  return JSON.parse(await fs.readFile(filePath, "utf8"));
}

async function exists(filePath) {
  try {
    await fs.access(filePath, fsConstants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function collectFiles(directory, visit, relativeDirectory = "") {
  const entries = await fs.readdir(path.join(directory, relativeDirectory), {
    withFileTypes: true,
  });
  entries.sort((a, b) => a.name.localeCompare(b.name));

  for (const entry of entries) {
    const relativePath = path.join(relativeDirectory, entry.name);
    const absolutePath = path.join(directory, relativePath);
    if (entry.isDirectory()) {
      await collectFiles(directory, visit, relativePath);
    } else if (entry.isFile()) {
      await visit(absolutePath, relativePath);
    }
  }
}

async function checkOutput(outputDirectory, expectedFiles) {
  const actualFiles = await listFiles(outputDirectory);
  const failures = [];

  for (const expectedPath of expectedFiles.keys()) {
    if (!actualFiles.has(expectedPath)) {
      failures.push(`missing ${path.join(outputDirectory, expectedPath)}`);
    }
  }

  for (const actualPath of actualFiles) {
    if (!expectedFiles.has(actualPath)) {
      failures.push(`unexpected ${path.join(outputDirectory, actualPath)}`);
    }
  }

  for (const [relativePath, expectedContent] of expectedFiles) {
    if (!actualFiles.has(relativePath)) {
      continue;
    }
    const actualContent = await fs.readFile(path.join(outputDirectory, relativePath));
    if (!actualContent.equals(expectedContent)) {
      failures.push(`changed ${path.join(outputDirectory, relativePath)}`);
    }
  }

  if (failures.length > 0) {
    throw new Error(`Generated widget resources are out of date:\n${failures.join("\n")}`);
  }
}

async function listFiles(directory) {
  if (!(await exists(directory))) {
    return new Set();
  }

  const files = new Set();
  await collectFiles(directory, async (_absolutePath, relativePath) => {
    files.add(relativePath);
  });
  return files;
}

async function writeOutput(outputDirectory, files) {
  await fs.rm(outputDirectory, { force: true, recursive: true });
  for (const [relativePath, content] of files) {
    const filePath = path.join(outputDirectory, relativePath);
    await fs.mkdir(path.dirname(filePath), { recursive: true });
    await fs.writeFile(filePath, content);
  }
}

function failIfAny(title, values) {
  if (values.length === 0) {
    return;
  }
  throw new Error(`${title}:\n${Array.from(new Set(values)).join("\n")}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const check = process.argv.includes("--check");
  generateWidgetResources(suggestedItemsDirectory, { check }).then(() => {
    if (check) {
      console.log("Widget resources are current.");
    } else {
      console.log("Generated Suggested Items/WidgetSuggested.bundle");
    }
  }).catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}
