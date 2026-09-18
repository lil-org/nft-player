#!/usr/bin/env node

const fs = require("node:fs/promises");
const path = require("node:path");
const {
  suggestedItemId: collectionIdFor,
  suggestedItemIdentityKey,
  suggestedItemResourceName,
} = require("./suggested_items");

const DEFAULT_BUNDLE_PATH = path.join("Suggested Items", "Suggested.bundle");
const DEFAULT_COVERS_PATH = "covers";

function usage() {
  return `
Usage:
  node tools/remove_bundled_collections.js [options] <collection-slug-id-or-name>...

Options:
  --apply           Remove matching catalog entries, token JSON, script source files, and local staged cover JPEGs.
  --dry-run         Print what would be removed without changing files. Default.
  --bundle <path>   Suggested.bundle path. Default: ${DEFAULT_BUNDLE_PATH}
  --covers <path>   Cover JPEG staging directory. Default: ${DEFAULT_COVERS_PATH}
  --help            Show this help.
`.trim();
}

function parseArgs(argv) {
  const options = {
    apply: false,
    bundlePath: DEFAULT_BUNDLE_PATH,
    coversPath: DEFAULT_COVERS_PATH,
    inputs: [],
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
      case "--covers":
        options.coversPath = readValue();
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

  if (options.inputs.length === 0) {
    throw new Error("Pass at least one collection slug, id, address, or exact collection name.");
  }

  return options;
}

function normalized(value) {
  return String(value ?? "").trim().toLowerCase();
}

function formatSuggestedItems(items) {
  return `${JSON.stringify(items, null, 2).replace(/"([^"]+)":/gu, "\"$1\" :")}\n`;
}

function resolveTargets(items, tokenFileIds, inputs) {
  const targets = new Map();

  for (const input of inputs) {
    const inputKey = normalized(input);
    const exactIdMatches = items.filter((item) => normalized(collectionIdFor(item)) === inputKey);
    const exactSlugMatches = items.filter((item) => item.internal_slug === input);
    const exactAddressMatches = items.filter((item) => normalized(item.address) === inputKey);
    const exactNameMatches = items.filter((item) => normalized(item.name) === inputKey);
    const matches = uniqueItems(exactSlugMatches.length > 0
      ? exactSlugMatches
      : [...exactIdMatches, ...exactAddressMatches, ...exactNameMatches]);

    if (matches.length > 1) {
      throw new Error(`Input "${input}" matched multiple catalog entries: ${matches.map((item) => `${item.name} (${collectionIdFor(item)})`).join(", ")}`);
    }

    if (matches.length === 1) {
      const item = matches[0];
      const id = collectionIdFor(item);
      const identity = suggestedItemIdentityKey(item);
      targets.set(identity, {
        input,
        id,
        identity,
        resourceName: suggestedItemResourceName(item),
        name: item.name ?? null,
        foundCatalogEntry: true,
      });
      continue;
    }

    if (tokenFileIds.has(input)) {
      targets.set(input, {
        input,
        id: input,
        resourceName: input,
        name: null,
        foundCatalogEntry: false,
      });
      continue;
    }

    throw new Error(`No bundled collection matched "${input}". Use the exact collection slug, id, address, or name.`);
  }

  return [...targets.values()];
}

function uniqueItems(items) {
  const seen = new Set();
  const unique = [];
  for (const item of items) {
    const id = suggestedItemIdentityKey(item);
    if (!seen.has(id)) {
      seen.add(id);
      unique.push(item);
    }
  }
  return unique;
}

async function pathExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function readTokenFileIds(tokensPath) {
  try {
    const fileNames = await fs.readdir(tokensPath);
    return new Set(
      fileNames
        .filter((fileName) => fileName.endsWith(".json"))
        .map((fileName) => fileName.slice(0, -".json".length)),
    );
  } catch (error) {
    if (error.code === "ENOENT") {
      return new Set();
    }
    throw error;
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const bundlePath = path.resolve(options.bundlePath);
  const coversPath = path.resolve(options.coversPath);
  const itemsPath = path.join(bundlePath, "items.json");
  const tokensPath = path.join(bundlePath, "Tokens");
  const scriptsPath = path.join(bundlePath, "Scripts");

  const items = JSON.parse(await fs.readFile(itemsPath, "utf8"));
  const tokenFileIds = await readTokenFileIds(tokensPath);
  const targets = resolveTargets(items, tokenFileIds, options.inputs);
  const targetIds = new Set(targets.map((target) => target.identity));

  const nextItems = items.filter((item) => !targetIds.has(suggestedItemIdentityKey(item)));
  const removedCatalogEntries = items.length - nextItems.length;

  const filePlans = [];
  for (const target of targets) {
    const tokenFilePath = path.join(tokensPath, `${target.resourceName}.json`);
    const scriptFilePaths = [];
    for (const extension of ["js", "html", "pde"]) {
      const filePath = path.join(scriptsPath, `${target.resourceName}.${extension}`);
      if (await pathExists(filePath)) scriptFilePaths.push(filePath);
    }
    const coverFilePath = path.join(coversPath, `${target.resourceName}.jpg`);
    filePlans.push({
      ...target,
      tokenFilePath,
      tokenFileExists: await pathExists(tokenFilePath),
      scriptFilePaths,
      coverFilePath,
      coverFileExists: await pathExists(coverFilePath),
    });
  }

  console.log(`${options.apply ? "Removing" : "Would remove"} ${targets.length} bundled collection(s):`);
  for (const plan of filePlans) {
    console.log(`- ${plan.name ?? plan.id} (${plan.id})`);
    console.log(`  catalog entry: ${plan.foundCatalogEntry ? "yes" : "no"}`);
    console.log(`  token JSON: ${plan.tokenFileExists ? plan.tokenFilePath : "missing"}`);
    console.log(`  script source: ${plan.scriptFilePaths.length > 0 ? plan.scriptFilePaths.join(", ") : "none"}`);
    console.log(`  staged cover JPEG: ${plan.coverFileExists ? plan.coverFilePath : "missing"}`);
  }

  if (!options.apply) {
    console.log(`Dry run. ${removedCatalogEntries} catalog entr${removedCatalogEntries === 1 ? "y" : "ies"} would be removed.`);
    return;
  }

  await fs.writeFile(itemsPath, formatSuggestedItems(nextItems));
  for (const plan of filePlans) {
    await fs.rm(plan.tokenFilePath, { force: true });
    for (const filePath of plan.scriptFilePaths) await fs.rm(filePath, { force: true });
    await fs.rm(plan.coverFilePath, { force: true });
  }

  console.log(`Removed ${removedCatalogEntries} catalog entr${removedCatalogEntries === 1 ? "y" : "ies"}.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
