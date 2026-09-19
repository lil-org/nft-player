#!/usr/bin/env node

import fs from "node:fs/promises";
import { rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import aspectRatios from "../tools/aspect_ratios.js";
import suggestedItems from "../tools/suggested_items.js";
import tokenManifest from "../tools/token_manifest.js";

const { decodeAspectRatioMetadata, normalizedRatio } = aspectRatios;
const { assertValidInternalSlugs } = suggestedItems;
const { decodeTokenManifest, serializeTokenManifest } = tokenManifest;
const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const defaultBundleDirectory = path.join(repositoryRoot, "Suggested Items/Suggested.bundle");
const metadataFields = ["bundledTokenCount", "hasUniformAspectRatio"];
let mediaValidator;

async function validateDownloadableCounts(collections) {
  if (collections.length === 0) return;
  if (!mediaValidator) {
    const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-media-validator-"));
    process.once("exit", () => rmSync(temporaryDirectory, { recursive: true, force: true }));
    const executable = path.join(temporaryDirectory, "validate-media");
    const compilation = spawnSync("xcrun", ["swiftc", "-O",
      path.join(repositoryRoot, "Shared/Models/BundledMediaResolver.swift"),
      path.join(repositoryRoot, "scripts/count-downloadable-media.swift"), "-o", executable], { encoding: "utf8" });
    if (compilation.error) throw compilation.error;
    if (compilation.status !== 0) throw new Error(`Cannot compile downloadable media validator: ${compilation.stderr.trim()}`);
    mediaValidator = executable;
  }
  const result = spawnSync(mediaValidator, [], {
    input: JSON.stringify(collections.map(({ urls }) => urls)),
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`Cannot validate downloadable media: ${result.stderr.trim()}`);
  const excludedGroups = JSON.parse(result.stdout);
  collections.forEach((collection, index) => {
    const { slug, tokenCount, urls } = collection;
    const excludedMediaIndices = excludedGroups[index];
    const acceptedCount = urls.length - excludedMediaIndices.length;
    if (tokenCount !== acceptedCount) {
      throw new Error(`${slug}: tokenCount is ${tokenCount}, but ${acceptedCount} tokens have supported downloadable media. Update tokenCount before regenerating metadata.`);
    }
    collection.manifest.excludedMediaIndices = excludedMediaIndices;
  });
}

function decodePayload(payload, slug) {
  try {
    return decodeTokenManifest(payload);
  } catch (error) {
    throw new Error(`${slug}: ${error.message}`, { cause: error });
  }
}

export function tokenMetadata(collection, payload) {
  const slug = collection.internal_slug;
  const decoded = decodePayload(payload, slug);
  const defaultRatio = collection.aspectRatio == null
    ? null
    : normalizedRatio(collection.aspectRatio, `${slug}: collection aspectRatio`);
  let ratios;
  try {
    ratios = decodeAspectRatioMetadata({ items: decoded.items }, defaultRatio);
  } catch (error) {
    throw new Error(`${slug}: ${error.message}`, { cause: error });
  }
  return {
    bundledTokenCount: decoded.items.length,
    hasUniformAspectRatio: decoded.items.length > 0 && defaultRatio != null
      && ratios.every((ratio) => ratio != null
        && ratio[0] === defaultRatio[0] && ratio[1] === defaultRatio[1]),
  };
}

export async function updateTokenMetadata({
  bundleDirectory = defaultBundleDirectory,
  check = false,
} = {}) {
  const itemsPath = path.join(bundleDirectory, "items.json");
  const items = JSON.parse(await fs.readFile(itemsPath, "utf8"));
  if (!Array.isArray(items)) throw new TypeError("items.json must contain an array.");
  assertValidInternalSlugs(items);
  const updatedItems = [];
  const staleSlugs = [];
  const downloadableCollections = [];
  const manifests = [];
  let tokenFileCount = 0;
  let tokenCount = 0;
  for (const item of items) {
    const slug = item.internal_slug;
    const updated = { ...item };
    metadataFields.forEach((field) => { delete updated[field]; });
    if (slug !== "card_nft_2" || item.script?.kind !== "native.card-nft-2") {
      const tokenPath = path.join(bundleDirectory, "Tokens", `${slug}.json`);
      let payload;
      let source;
      try {
        source = await fs.readFile(tokenPath, "utf8");
        payload = JSON.parse(source);
      } catch (error) {
        throw new Error(`${slug}: cannot read token manifest ${tokenPath}: ${error.message}`, { cause: error });
      }
      const metadata = tokenMetadata(item, payload);
      const decoded = decodePayload(payload, slug);
      const manifest = { slug, tokenPath, source, items: decoded.items, excludedMediaIndices: [] };
      manifests.push(manifest);
      if (item.tokenCount != null && item.generativeOnly !== true) {
        downloadableCollections.push({
          slug,
          tokenCount: item.tokenCount,
          manifest,
          urls: decoded.items.map((token) => token.urlSuffix != null
            ? `${item.urlPrefix ?? ""}${token.urlSuffix}`
            : item.chain === "ethereum"
              ? `https://media-proxy.artblocks.io/${item.address}/${token.id}.png`
              : null),
        });
      }
      Object.assign(updated, metadata);
      tokenFileCount += 1;
      tokenCount += metadata.bundledTokenCount;
    }
    if (metadataFields.some((field) => Object.hasOwn(item, field) !== Object.hasOwn(updated, field)
        || item[field] !== updated[field])) staleSlugs.push(slug);
    updatedItems.push(updated);
  }
  await validateDownloadableCounts(downloadableCollections);
  const staleManifests = [];
  for (const manifest of manifests) {
    const { items, excludedMediaIndices } = manifest;
    manifest.expected = serializeTokenManifest(items, { excludedMediaIndices });
    assert.deepEqual(decodeTokenManifest(JSON.parse(manifest.expected), { allowLegacy: false }).items,
      items, `${manifest.slug}: compact conversion must preserve every ordered token value`);
    if (manifest.source !== manifest.expected) staleManifests.push(manifest);
  }
  const changedSlugs = new Set([...staleSlugs, ...staleManifests.map(({ slug }) => slug)]);
  if (check && changedSlugs.size > 0) {
    throw new Error(`Generated token manifests or metadata are out of date; run node scripts/update-token-metadata.mjs:\n${[...changedSlugs].join("\n")}`);
  }
  if (!check) {
    for (const { tokenPath, expected } of staleManifests) await fs.writeFile(tokenPath, expected);
    if (staleSlugs.length > 0) await fs.writeFile(itemsPath, `${JSON.stringify(updatedItems, null, 2)}\n`);
  }
  return { collections: tokenFileCount, tokens: tokenCount, updated: changedSlugs.size };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const flags = process.argv.slice(2);
  if (flags.some((flag) => flag !== "--check")) {
    console.error("Usage: node scripts/update-token-metadata.mjs [--check]");
    process.exitCode = 1;
  } else {
    updateTokenMetadata({ check: flags.includes("--check") }).then(({ collections, tokens, updated }) => {
      console.log(`Token manifests and metadata verified: ${collections} collections, ${tokens} tokens, ${updated} updated.`);
    }).catch((error) => {
      console.error(error.message);
      process.exitCode = 1;
    });
  }
}
