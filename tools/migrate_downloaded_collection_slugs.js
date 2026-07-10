#!/usr/bin/env node

const fs = require("node:fs/promises");
const path = require("node:path");
const {
  assignInternalSlugs,
  assertValidInternalSlugs,
  collectionIdentityKey,
  suggestedItemId,
} = require("./suggested_items");
const {
  isBundledGenerativeCollectionId,
  isBundledGenerativeDownloadDirectory,
  loadBundledGenerativeCollectionIds,
} = require("./bundled_generative_collections");

const DEFAULT_BUNDLE_PATH = path.join("Suggested Items", "Suggested.bundle");
const DEFAULT_DOWNLOAD_ROOT = "Originals Downloaded";
const CASE_INSENSITIVE_ID_CHAINS = new Set(["base", "ethereum", "optimism", "zora"]);

function usage() {
  return `
Usage:
  node tools/migrate_downloaded_collection_slugs.js [options]

The Art Blocks Generative subtree and bundled-script collections are always skipped.

Options:
  --apply                 Write internal_slug metadata and rename directories. Default is dry-run.
  --bundle <path>         Suggested.bundle path. Default: ${DEFAULT_BUNDLE_PATH}
  --download-root <path>  Download root. Default: ${DEFAULT_DOWNLOAD_ROOT}
  --help                  Show this help.
`.trim();
}

function parseArgs(argv) {
  const options = {
    apply: false,
    bundlePath: DEFAULT_BUNDLE_PATH,
    downloadRoot: DEFAULT_DOWNLOAD_ROOT,
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
      case "--bundle":
        options.bundlePath = readValue();
        break;
      case "--download-root":
        options.downloadRoot = readValue();
        break;
      case "--help":
        console.log(usage());
        process.exit(0);
        break;
      default:
        throw new Error(`Unknown option: ${arg}`);
    }
  }

  return options;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const bundlePath = path.resolve(options.bundlePath);
  const downloadRoot = path.resolve(options.downloadRoot);
  const itemsPath = path.join(bundlePath, "items.json");
  const rootManifestPath = path.join(downloadRoot, "manifest.json");
  const [existingItems, rootManifest, directoryEntries, bundledGenerativeCollectionIds] = await Promise.all([
    readJson(itemsPath),
    readJson(rootManifestPath),
    fs.readdir(downloadRoot, { withFileTypes: true }),
    loadBundledGenerativeCollectionIds(bundlePath),
  ]);

  assertRootManifestShape(rootManifest);
  const items = assignInternalSlugs(existingItems);
  assertValidInternalSlugs(items);
  const itemByKey = uniqueItemMap(items);
  const directoryRecords = await loadDirectoryRecords(
    downloadRoot,
    directoryEntries,
    bundledGenerativeCollectionIds,
  );
  const recordByKey = uniqueRecordMap(directoryRecords);
  validateManifestCoverage(rootManifest, itemByKey, recordByKey, bundledGenerativeCollectionIds);

  const operations = [];
  for (const record of directoryRecords) {
    const item = itemByKey.get(record.key);
    if (!item) {
      throw new Error(`Downloaded directory ${record.directory} belongs to unknown collection ${record.id}`);
    }
    const targetDirectory = path.join(downloadRoot, item.internal_slug);
    if (record.directory !== targetDirectory && await pathExists(targetDirectory)) {
      throw new Error(`Cannot migrate ${record.directory}; destination already exists: ${targetDirectory}`);
    }
    const nextManifest = migratedCollectionManifest(record.manifest, item.internal_slug, targetDirectory);
    operations.push({
      ...record,
      internalSlug: item.internal_slug,
      targetDirectory,
      rename: record.directory !== targetDirectory,
      nextManifest,
      manifestChanged: !sameJson(record.manifest, nextManifest),
    });
  }

  const nextRootManifest = updateRootManifest(
    rootManifest,
    itemByKey,
    recordByKey,
    downloadRoot,
    items,
    bundledGenerativeCollectionIds,
  );
  const itemsChanged = !sameJson(existingItems, items);
  const rootManifestChanged = !sameJson(rootManifest, nextRootManifest);

  // Force serialization before apply so formatter errors cannot leave a partially migrated tree.
  formatSuggestedItems(items);
  formatJson(nextRootManifest);
  for (const operation of operations) formatJson(operation.nextManifest);

  const summary = {
    mode: options.apply ? "apply" : "dry-run",
    collectionRecords: items.length,
    newlyAssignedSlugs: items.filter((item, index) => existingItems[index]?.internal_slug == null && item.internal_slug != null).length,
    uniqueSlugs: new Set(items.map((item) => item.internal_slug)).size,
    matchedDirectories: operations.length,
    directoriesToRename: operations.filter((operation) => operation.rename).length,
    alreadyMigratedDirectories: operations.filter((operation) => !operation.rename).length,
    manifestsToUpdate: operations.filter((operation) => operation.manifestChanged).length,
    rootManifestWillChange: rootManifestChanged,
    itemsWillChange: itemsChanged,
    collectionsWithoutDirectories: items.length - operations.length,
    unknownDirectories: 0,
    destinationConflicts: 0,
  };

  if (!options.apply) {
    console.log(JSON.stringify(summary, null, 2));
    return;
  }

  // Renames are safe to resume. Metadata is updated only after all paths are in place,
  // and items.json is last so the canonical store never gets ahead of the filesystem.
  for (const operation of operations) {
    if (operation.rename) {
      await fs.rename(operation.directory, operation.targetDirectory);
    }
  }
  for (const operation of operations) {
    if (operation.manifestChanged) {
      await writeJsonAtomicIfChanged(path.join(operation.targetDirectory, "manifest.json"), operation.nextManifest);
    }
  }
  if (rootManifestChanged) {
    await writeJsonAtomicIfChanged(rootManifestPath, nextRootManifest);
  }
  if (itemsChanged) {
    await writeJsonAtomicIfChanged(itemsPath, items, formatSuggestedItems);
  }
  console.log(JSON.stringify(summary, null, 2));
}

function uniqueItemMap(items) {
  const result = new Map();
  for (const item of items) {
    const key = collectionIdentityKey(suggestedItemId(item), item.chain);
    if (result.has(key)) {
      throw new Error(`Duplicate suggested collection identity ${item.chain}:${suggestedItemId(item)}`);
    }
    result.set(key, item);
  }
  return result;
}

async function loadDirectoryRecords(downloadRoot, entries, bundledGenerativeCollectionIds) {
  const records = [];
  for (const entry of entries) {
    if (!entry.isDirectory() || isBundledGenerativeDownloadDirectory(entry.name)) continue;

    const directory = path.join(downloadRoot, entry.name);
    const manifestPath = path.join(directory, "manifest.json");
    if (!await pathExists(manifestPath)) {
      throw new Error(`Downloaded directory has no manifest.json: ${directory}`);
    }
    const manifest = await readJson(manifestPath);
    const id = String(manifest.collection?.id ?? "");
    const chain = String(manifest.collection?.chain ?? "");
    if (!id) {
      throw new Error(`Downloaded manifest has no collection.id: ${manifestPath}`);
    }
    if (!chain) {
      throw new Error(`Downloaded manifest has no collection.chain: ${manifestPath}`);
    }
    if (isBundledGenerativeCollectionId(id, bundledGenerativeCollectionIds)) continue;
    records.push({
      id,
      chain,
      key: collectionIdentityKey(id, chain),
      directory,
      manifestPath,
      manifest,
    });
  }
  return records;
}

function uniqueRecordMap(records) {
  const result = new Map();
  for (const record of records) {
    const previous = result.get(record.key);
    if (previous) {
      throw new Error(`Multiple downloaded directories represent ${record.chain}:${record.id}: ${previous.directory}, ${record.directory}`);
    }
    result.set(record.key, record);
  }
  return result;
}

function assertRootManifestShape(rootManifest) {
  for (const field of ["collections", "skippedCollections", "failures"]) {
    if (!Array.isArray(rootManifest[field])) {
      throw new Error(`Root manifest ${field} must be an array`);
    }
  }
}

function validateManifestCoverage(rootManifest, itemByKey, recordByKey, bundledGenerativeCollectionIds) {
  for (const collection of [...rootManifest.collections, ...rootManifest.skippedCollections]) {
    const key = collectionIdentityKey(collection.id, collection.chain);
    if (!itemByKey.has(key)) {
      throw new Error(`Root manifest references unknown collection ${collection.chain}:${collection.id}`);
    }
  }
  for (const collection of rootManifest.collections) {
    if (isBundledGenerativeCollectionId(collection.id, bundledGenerativeCollectionIds)) continue;
    const key = collectionIdentityKey(collection.id, collection.chain);
    if (!collection.skipped && !recordByKey.has(key)) {
      throw new Error(`Root manifest collection ${collection.chain}:${collection.id} has no downloaded directory`);
    }
  }
  for (const record of recordByKey.values()) {
    if (!itemByKey.has(record.key)) {
      throw new Error(`Downloaded directory references unknown collection ${record.chain}:${record.id}`);
    }
  }
}

function migratedCollectionManifest(manifest, internalSlug, outputDirectory) {
  if (manifest.collection?.internal_slug === internalSlug && manifest.outputDirectory === outputDirectory) {
    return manifest;
  }
  return {
    ...manifest,
    collection: {
      ...manifest.collection,
      internal_slug: internalSlug,
    },
    outputDirectory,
    updatedAt: new Date().toISOString(),
  };
}

function updateRootManifest(
  rootManifest,
  itemByKey,
  recordByKey,
  downloadRoot,
  items,
  bundledGenerativeCollectionIds,
) {
  const updateCollection = (collection) => {
    if (isBundledGenerativeCollectionId(collection.id, bundledGenerativeCollectionIds)) return collection;
    const key = collectionIdentityKey(collection.id, collection.chain);
    const item = itemByKey.get(key);
    if (!item) {
      throw new Error(`Cannot update root manifest collection ${collection.chain}:${collection.id}`);
    }
    const record = recordByKey.get(key);
    const outputDirectory = path.join(downloadRoot, item.internal_slug);
    const next = {
      ...collection,
      internal_slug: item.internal_slug,
      outputDirectory,
    };
    if (record || collection.manifestPath) {
      next.manifestPath = path.join(outputDirectory, "manifest.json");
    }
    return next;
  };

  const next = {
    ...rootManifest,
    skippedCollections: rootManifest.skippedCollections.map(updateCollection),
    failures: rootManifest.failures.map((failure) => {
      if (isBundledGenerativeCollectionId(failure.collectionId, bundledGenerativeCollectionIds)) return failure;
      const item = resolveFailureItem(failure.collectionId, items);
      return item ? { ...failure, internal_slug: item.internal_slug } : failure;
    }),
    collections: rootManifest.collections.map(updateCollection),
  };
  if (sameJson(rootManifest, next)) return rootManifest;
  return {
    ...next,
    generatedAt: new Date().toISOString(),
  };
}

function resolveFailureItem(collectionId, items) {
  const id = String(collectionId ?? "");
  const exact = items.filter((item) => suggestedItemId(item) === id);
  if (exact.length === 1) return exact[0];
  if (exact.length > 1) {
    throw new Error(`Failure collection id is ambiguous: ${id}`);
  }

  const insensitive = items.filter((item) => (
    CASE_INSENSITIVE_ID_CHAINS.has(String(item.chain ?? "").toLowerCase())
    && suggestedItemId(item).toLowerCase() === id.toLowerCase()
  ));
  if (insensitive.length > 1) {
    throw new Error(`Failure collection id is ambiguous: ${id}`);
  }
  return insensitive[0] ?? null;
}

async function readJson(filePath) {
  return JSON.parse(await fs.readFile(filePath, "utf8"));
}

async function pathExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch (error) {
    if (error.code === "ENOENT") return false;
    throw error;
  }
}

async function writeJsonAtomicIfChanged(filePath, value, formatter = formatJson) {
  const output = formatter(value);
  let current = null;
  try {
    current = await fs.readFile(filePath, "utf8");
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  if (current === output) return false;

  const tempPath = `${filePath}.tmp-${process.pid}`;
  await fs.writeFile(tempPath, output);
  await fs.rename(tempPath, filePath);
  return true;
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function formatJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function formatSuggestedItems(items) {
  return `${JSON.stringify(items, null, 2).replace(/"([^"]+)":/gu, "\"$1\" :")}\n`;
}

main().catch((error) => {
  console.error(error.stack ?? error.message);
  process.exitCode = 1;
});
