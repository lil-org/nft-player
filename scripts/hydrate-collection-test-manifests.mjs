#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import suggestedItems from "../tools/suggested_items.js";
import tokenManifest from "../tools/token_manifest.js";

const { assertValidInternalSlugs } = suggestedItems;
const { decodeTokenManifest } = tokenManifest;
const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const defaultItemsPath = path.join(repositoryRoot, "Suggested Items/items.json");
const defaultOutputDirectory = path.join(repositoryRoot, "build/test-collection-manifests/CollectionManifests");

export function collectionManifestDescriptors(items) {
  if (!Array.isArray(items)) throw new Error("items.json must contain an array.");
  assertValidInternalSlugs(items);
  return items.flatMap((item) => {
    if (item.internal_slug === "card_nft_2" && item.script?.kind === "native.card-nft-2") return [];
    if (!Number.isSafeInteger(item.bundledTokenCount) || item.bundledTokenCount < 0) {
      throw new Error(`${item.internal_slug}: invalid bundledTokenCount.`);
    }
    return [{
      slug: item.internal_slug,
      filename: `${item.internal_slug}.json`,
      url: `https://cdn.lil.org/player/collections/${item.internal_slug}.json`,
      count: item.bundledTokenCount,
    }];
  });
}

function validateManifest(data, descriptor) {
  const payload = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(data));
  const decoded = decodeTokenManifest(payload, { allowLegacy: false });
  if (decoded.items.length !== descriptor.count) {
    throw new Error(`${descriptor.slug}: expected ${descriptor.count} tokens, received ${decoded.items.length}.`);
  }
}

async function hasValidManifest(filePath, descriptor) {
  let data;
  try { data = await fs.readFile(filePath); } catch (error) {
    if (error.code === "ENOENT") return false;
    throw error;
  }
  try { validateManifest(data, descriptor); return true; } catch { return false; }
}

async function download(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(60_000) });
  if (response.status !== 200) return { statusCode: response.status, data: Buffer.alloc(0) };
  return { statusCode: response.status, data: Buffer.from(await response.arrayBuffer()) };
}

export async function hydrateCollectionTestManifests({
  itemsPath = defaultItemsPath,
  outputDirectory = defaultOutputDirectory,
  check = false,
  transport = download,
} = {}) {
  const descriptors = collectionManifestDescriptors(JSON.parse(await fs.readFile(itemsPath, "utf8")));
  if (!check) await fs.mkdir(outputDirectory, { recursive: true });
  let next = 0;
  let cached = 0;
  let downloaded = 0;
  let failure;
  await Promise.all(Array.from({ length: Math.min(4, descriptors.length) }, async () => {
    while (next < descriptors.length && failure == null) {
      const descriptor = descriptors[next++];
      const destination = path.join(outputDirectory, descriptor.filename);
      try {
        if (await hasValidManifest(destination, descriptor)) {
          cached += 1;
          continue;
        }
        if (check) {
          throw new Error(`${descriptor.slug}: missing or corrupt test manifest; run node scripts/hydrate-collection-test-manifests.mjs.`);
        }
        const response = await transport(descriptor.url);
        if (response.statusCode !== 200) {
          throw new Error(`${descriptor.slug}: collection manifest download returned HTTP ${response.statusCode}.`);
        }
        const data = Buffer.from(response.data);
        validateManifest(data, descriptor);
        const staging = `${destination}.${crypto.randomUUID()}.partial`;
        try {
          await fs.writeFile(staging, data, { flag: "wx" });
          await fs.rename(staging, destination);
        } finally {
          await fs.rm(staging, { force: true });
        }
        downloaded += 1;
      } catch (error) {
        failure ??= error;
      }
    }
  }));
  if (failure) throw failure;
  return { manifests: descriptors.length, cached, downloaded };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const flags = process.argv.slice(2);
  if (flags.some((flag) => flag !== "--check")) {
    console.error("Usage: node scripts/hydrate-collection-test-manifests.mjs [--check]");
    process.exitCode = 1;
  } else {
    hydrateCollectionTestManifests({ check: flags.includes("--check") }).then(({ manifests, cached, downloaded }) => {
      console.log(`Collection test manifests verified: ${manifests} (${cached} cached, ${downloaded} downloaded).`);
    }).catch((error) => {
      console.error(error.message);
      process.exitCode = 1;
    });
  }
}
