#!/usr/bin/env node

import { constants as fsConstants } from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, "..");
const suggestedItemsDirectory = path.join(repositoryRoot, "Suggested Items");
const sourceBundleDirectory = path.join(suggestedItemsDirectory, "Suggested.bundle");
const sourceCoversDirectory = path.join(suggestedItemsDirectory, "Covers.xcassets");
const outputBundleDirectory = path.join(suggestedItemsDirectory, "WidgetSuggested.bundle");
const outputCoversDirectory = path.join(suggestedItemsDirectory, "WidgetCovers.xcassets");
const eligibleCollectionsPath = path.join(suggestedItemsDirectory, "widget-eligible-collections.json");

const isCheckMode = process.argv.includes("--check");

async function main() {
  const eligibleIds = await readEligibleCollectionIds();
  const sourceItems = await readJSON(path.join(sourceBundleDirectory, "items.json"));
  const itemsById = new Map();

  for (const item of sourceItems) {
    const id = collectionId(item);
    if (id && !itemsById.has(id)) {
      itemsById.set(id, item);
    }
  }

  const selectedItems = [];
  const missingItems = [];
  for (const id of eligibleIds) {
    const item = itemsById.get(id);
    if (item) {
      selectedItems.push(item);
    } else {
      missingItems.push(id);
    }
  }
  failIfAny("Missing collection ids in Suggested.bundle/items.json", missingItems);

  const expectedBundleFiles = new Map();
  expectedBundleFiles.set(
    "items.json",
    Buffer.from(`${JSON.stringify(selectedItems, null, 2)}\n`)
  );

  const missingTokens = [];
  for (const id of eligibleIds) {
    const tokenPath = await firstExistingPath([
      path.join(sourceBundleDirectory, "Tokens", `${id}.json`),
      path.join(sourceBundleDirectory, "Tokens", `${id.toLowerCase()}.json`),
    ]);
    if (!tokenPath) {
      missingTokens.push(id);
      continue;
    }
    expectedBundleFiles.set(
      path.join("Tokens", path.basename(tokenPath)),
      await fs.readFile(tokenPath)
    );
  }
  failIfAny("Missing token JSON files in Suggested.bundle/Tokens", missingTokens);

  const expectedCoverFiles = new Map();
  expectedCoverFiles.set(
    "Contents.json",
    await fs.readFile(path.join(sourceCoversDirectory, "Contents.json"))
  );

  const missingCovers = [];
  for (const id of eligibleIds) {
    const sourceImageset = path.join(sourceCoversDirectory, `${id}.imageset`);
    if (!(await exists(sourceImageset))) {
      missingCovers.push(id);
      continue;
    }
    await collectFiles(sourceImageset, async (sourceFilePath, relativePath) => {
      expectedCoverFiles.set(
        path.join(`${id}.imageset`, relativePath),
        await fs.readFile(sourceFilePath)
      );
    });
  }
  failIfAny("Missing cover imagesets in Covers.xcassets", missingCovers);

  if (isCheckMode) {
    await checkOutput(outputBundleDirectory, expectedBundleFiles);
    await checkOutput(outputCoversDirectory, expectedCoverFiles);
    console.log("Widget resources are current.");
    return;
  }

  await writeOutput(outputBundleDirectory, expectedBundleFiles);
  await writeOutput(outputCoversDirectory, expectedCoverFiles);
  console.log(`Generated ${path.relative(repositoryRoot, outputBundleDirectory)}`);
  console.log(`Generated ${path.relative(repositoryRoot, outputCoversDirectory)}`);
}

async function readEligibleCollectionIds() {
  const value = await readJSON(eligibleCollectionsPath);
  if (!Array.isArray(value)) {
    throw new Error("widget-eligible-collections.json must contain a JSON array.");
  }

  const ids = value.map((item) => {
    if (typeof item !== "string" || item.trim() === "") {
      throw new Error("widget-eligible-collections.json must contain only non-empty strings.");
    }
    return item;
  });

  const duplicates = ids.filter((id, index) => ids.indexOf(id) !== index);
  failIfAny("Duplicate collection ids in widget-eligible-collections.json", duplicates);
  return ids;
}

function collectionId(item) {
  if (!item || typeof item.address !== "string") {
    return undefined;
  }
  return item.address + (item.abId ?? item.collectionId ?? "");
}

async function readJSON(filePath) {
  return JSON.parse(await fs.readFile(filePath, "utf8"));
}

async function firstExistingPath(paths) {
  for (const filePath of paths) {
    if (await exists(filePath)) {
      return filePath;
    }
  }
  return undefined;
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

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
