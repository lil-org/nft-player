#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const defaultItemsPath = path.join(repositoryRoot, "Suggested Items/Suggested.bundle/items.json");
const defaultOutputDirectory = path.join(repositoryRoot, "build/test-artwork-sources/ArtworkScripts");

export function artworkSourceDescriptors(items) {
  if (!Array.isArray(items)) throw new Error("items.json must contain an array.");
  return items.flatMap((item) => {
    const script = item.script;
    if (script == null) return [];
    const slug = item.internal_slug;
    if (typeof script.kind !== "string" || script.kind.length === 0) {
      throw new Error(`${slug}: missing script kind.`);
    }
    if (script.kind.startsWith("native.")) {
      if (script.expectedByteCount != null || script.sha256 != null || script.sourceURL != null) {
        throw new Error(`${slug}: native renderers must not declare source descriptors.`);
      }
      return [];
    }
    if (typeof slug !== "string" || !/^[a-z0-9]+(?:_[a-z0-9]+)*$/u.test(slug)
        || !Number.isSafeInteger(script.expectedByteCount) || script.expectedByteCount <= 0
        || typeof script.sha256 !== "string" || !/^[a-f0-9]{64}$/u.test(script.sha256)) {
      throw new Error(`${slug}: invalid pinned artwork source descriptor.`);
    }
    const extension = script.kind === "html" ? "html" : script.kind === "processingjs146" ? "pde" : "js";
    const sourceURL = script.sourceURL ?? `https://cdn.lil.org/player/scripts/${slug}.${extension}`;
    let url;
    try { url = new URL(sourceURL); } catch { throw new Error(`${slug}: sourceURL must be an absolute HTTPS URL.`); }
    if (typeof sourceURL !== "string" || url.protocol !== "https:" || !url.hostname || url.username || url.password
        || url.href.includes("#")) {
      throw new Error(`${slug}: sourceURL must be an absolute HTTPS URL.`);
    }
    return [{
      slug,
      url: url.href,
      expectedByteCount: script.expectedByteCount,
      sha256: script.sha256,
      extension,
      filename: `${script.sha256}.${extension}`,
    }];
  });
}

function validateSource(data, descriptor) {
  if (data.length !== descriptor.expectedByteCount) {
    throw new Error(`${descriptor.slug}: expected ${descriptor.expectedByteCount} bytes, received ${data.length}.`);
  }
  if (crypto.createHash("sha256").update(data).digest("hex") !== descriptor.sha256) {
    throw new Error(`${descriptor.slug}: artwork source SHA-256 mismatch.`);
  }
  try { new TextDecoder("utf-8", { fatal: true }).decode(data); } catch {
    throw new Error(`${descriptor.slug}: artwork source is not valid UTF-8.`);
  }
}

async function hasValidSource(filePath, descriptor) {
  let data;
  try { data = await fs.readFile(filePath); } catch (error) {
    if (error.code === "ENOENT") return false;
    throw error;
  }
  try { validateSource(data, descriptor); return true; } catch { return false; }
}

async function download(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(60_000) });
  if (response.status !== 200) return { statusCode: response.status, data: Buffer.alloc(0) };
  return { statusCode: response.status, data: Buffer.from(await response.arrayBuffer()) };
}

export async function hydrateArtworkTestSources({
  itemsPath = defaultItemsPath,
  outputDirectory = defaultOutputDirectory,
  check = false,
  transport = download,
} = {}) {
  const descriptors = artworkSourceDescriptors(JSON.parse(await fs.readFile(itemsPath, "utf8")));
  const uniqueDescriptors = new Map();
  for (const descriptor of descriptors) {
    const existing = uniqueDescriptors.get(descriptor.filename);
    if (existing && existing.expectedByteCount !== descriptor.expectedByteCount) {
      throw new Error(`${descriptor.slug}: conflicting byte count for shared source ${descriptor.sha256}.`);
    }
    uniqueDescriptors.set(descriptor.filename, descriptor);
  }
  const sources = [...uniqueDescriptors.values()];
  if (!check) await fs.mkdir(outputDirectory, { recursive: true });
  let next = 0;
  let cached = 0;
  let downloaded = 0;
  let failure;
  await Promise.all(Array.from({ length: Math.min(4, sources.length) }, async () => {
    while (next < sources.length && failure == null) {
      const descriptor = sources[next++];
      const destination = path.join(outputDirectory, descriptor.filename);
      try {
        if (await hasValidSource(destination, descriptor)) {
          cached += 1;
          continue;
        }
        if (check) {
          throw new Error(`${descriptor.slug}: missing or corrupt test source; run node scripts/hydrate-artwork-test-sources.mjs.`);
        }
        const response = await transport(descriptor.url);
        if (response.statusCode !== 200) {
          throw new Error(`${descriptor.slug}: artwork source download returned HTTP ${response.statusCode}.`);
        }
        const data = Buffer.from(response.data);
        validateSource(data, descriptor);
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
  return { sources: sources.length, cached, downloaded };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const flags = process.argv.slice(2);
  if (flags.some((flag) => flag !== "--check")) {
    console.error("Usage: node scripts/hydrate-artwork-test-sources.mjs [--check]");
    process.exitCode = 1;
  } else {
    hydrateArtworkTestSources({ check: flags.includes("--check") }).then(({ sources, cached, downloaded }) => {
      console.log(`Artwork test sources verified: ${sources} (${cached} cached, ${downloaded} downloaded).`);
    }).catch((error) => {
      console.error(error.message);
      process.exitCode = 1;
    });
  }
}
