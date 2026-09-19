#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import aspectRatios from "../tools/aspect_ratios.js";
import suggestedItems from "../tools/suggested_items.js";

const { decodeAspectRatioMetadata, normalizedRatio } = aspectRatios;
const { assertValidInternalSlugs } = suggestedItems;
const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const defaultBundleDirectory = path.join(repositoryRoot, "Suggested Items/Suggested.bundle");
const metadataFields = ["bundledTokenCount", "hasUniformAspectRatio"];

function validateDownloadableCounts(collections) {
  if (collections.length === 0) return;
  const result = spawnSync("xcrun", ["swift", path.join(repositoryRoot, "scripts/count-downloadable-media.swift")], {
    input: JSON.stringify(collections.map(({ urls }) => urls)),
    encoding: "utf8",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`Cannot validate downloadable media: ${result.stderr.trim()}`);
  }
  const counts = JSON.parse(result.stdout);
  collections.forEach(({ slug, tokenCount }, index) => {
    if (tokenCount !== counts[index]) {
      throw new Error(`${slug}: tokenCount is ${tokenCount}, but ${counts[index]} tokens have supported downloadable media. Update tokenCount before regenerating metadata.`);
    }
  });
}

function validateTokenPayload(payload, slug) {
  if (payload == null || typeof payload !== "object" || Array.isArray(payload)
      || !Array.isArray(payload.items)) {
    throw new TypeError(`${slug}: token payload must contain an items array.`);
  }
  payload.items.forEach((item, index) => {
    const label = `${slug}: token item ${index}`;
    if (item == null || typeof item !== "object" || Array.isArray(item)
        || typeof item.id !== "string" || item.id.length === 0) {
      throw new TypeError(`${label} must be an object with a non-empty string id.`);
    }
    for (const field of ["name", "urlSuffix", "hash"]) {
      if (item[field] != null && typeof item[field] !== "string") {
        throw new TypeError(`${label} ${field} must be a string.`);
      }
    }
    const parameters = item.contractParameters;
    if (parameters != null && (typeof parameters !== "object" || Array.isArray(parameters)
        || Object.values(parameters).some((value) => typeof value !== "string"))) {
      throw new TypeError(`${label} contractParameters must be a string-to-string object.`);
    }
  });
}

export function tokenMetadata(collection, payload) {
  const slug = collection.internal_slug;
  validateTokenPayload(payload, slug);
  const defaultRatio = collection.aspectRatio == null
    ? null
    : normalizedRatio(collection.aspectRatio, `${slug}: collection aspectRatio`);
  let ratios;
  try {
    ratios = decodeAspectRatioMetadata(payload, defaultRatio);
  } catch (error) {
    throw new Error(`${slug}: ${error.message}`, { cause: error });
  }
  return {
    bundledTokenCount: payload.items.length,
    hasUniformAspectRatio: payload.items.length > 0 && defaultRatio != null
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
  let tokenFileCount = 0;
  let tokenCount = 0;
  for (const item of items) {
    const slug = item.internal_slug;
    const updated = { ...item };
    metadataFields.forEach((field) => { delete updated[field]; });
    if (slug !== "card_nft_2" || item.script?.kind !== "native.card-nft-2") {
      const tokenPath = path.join(bundleDirectory, "Tokens", `${slug}.json`);
      let payload;
      try {
        payload = JSON.parse(await fs.readFile(tokenPath, "utf8"));
      } catch (error) {
        throw new Error(`${slug}: cannot read token manifest ${tokenPath}: ${error.message}`, { cause: error });
      }
      const metadata = tokenMetadata(item, payload);
      if (item.tokenCount != null && item.generativeOnly !== true) {
        downloadableCollections.push({
          slug,
          tokenCount: item.tokenCount,
          urls: payload.items.map((token) => token.urlSuffix != null
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
        || item[field] !== updated[field])) {
      staleSlugs.push(slug);
    }
    updatedItems.push(updated);
  }
  validateDownloadableCounts(downloadableCollections);
  if (check && staleSlugs.length > 0) {
    throw new Error(`Generated token metadata is out of date; run node scripts/update-token-metadata.mjs:\n${staleSlugs.join("\n")}`);
  }
  if (!check && staleSlugs.length > 0) {
    await fs.writeFile(itemsPath, `${JSON.stringify(updatedItems, null, 2)}\n`);
  }
  return { collections: tokenFileCount, tokens: tokenCount, updated: staleSlugs.length };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const flags = process.argv.slice(2);
  if (flags.some((flag) => flag !== "--check")) {
    console.error("Usage: node scripts/update-token-metadata.mjs [--check]");
    process.exitCode = 1;
  } else {
    updateTokenMetadata({ check: flags.includes("--check") }).then(({ collections, tokens, updated }) => {
      console.log(`Token metadata verified: ${collections} collections, ${tokens} tokens, ${updated} updated.`);
    }).catch((error) => {
      console.error(error.message);
      process.exitCode = 1;
    });
  }
}
