#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import tokenManifest from "../tools/token_manifest.js";

const { decodeTokenManifest, serializeTokenManifest, validateTokenRows } = tokenManifest;
const usage = "Usage: node scripts/import-token-manifests.mjs --input-directory <directory> --output-directory <directory>";

function importedManifest(payload) {
  if (payload == null || typeof payload !== "object" || Array.isArray(payload)) {
    throw new TypeError("Token payload must be an object");
  }
  if (!Object.hasOwn(payload, "items")) return decodeTokenManifest(payload);
  const unknown = Object.keys(payload).find((key) => !["items", "excludedMediaIndices"].includes(key));
  if (unknown) throw new TypeError(`Unsupported import field ${unknown}`);
  const items = validateTokenRows(payload.items);
  const options = Object.hasOwn(payload, "excludedMediaIndices")
    ? { excludedMediaIndices: payload.excludedMediaIndices } : {};
  return decodeTokenManifest(JSON.parse(serializeTokenManifest(items, options)));
}

export async function importTokenManifests({ inputDirectory, outputDirectory } = {}) {
  if (typeof inputDirectory !== "string" || inputDirectory.length === 0
      || typeof outputDirectory !== "string" || outputDirectory.length === 0) {
    throw new Error(usage);
  }
  const inputPath = await fs.realpath(inputDirectory);
  const outputPath = path.resolve(outputDirectory);
  let resolvedOutputPath;
  try {
    resolvedOutputPath = await fs.realpath(outputPath);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    resolvedOutputPath = outputPath;
  }
  if (inputPath === resolvedOutputPath) {
    throw new Error("Input and output directories must be different.");
  }
  const entries = (await fs.readdir(inputPath, { withFileTypes: true }))
    .filter((entry) => entry.name.endsWith(".json"))
    .sort((left, right) => left.name < right.name ? -1 : left.name > right.name ? 1 : 0);
  if (entries.length === 0) throw new Error("Input directory contains no JSON manifests.");
  const pending = [];
  let tokens = 0;
  for (const entry of entries) {
    if (!entry.isFile()) throw new Error(`${entry.name}: expected a regular JSON file.`);
    let decoded;
    let expected;
    try {
      decoded = importedManifest(JSON.parse(await fs.readFile(path.join(inputPath, entry.name), "utf8")));
      expected = serializeTokenManifest(decoded.items, {
        excludedMediaIndices: decoded.excludedMediaIndices ?? [],
      });
      assert.deepEqual(decodeTokenManifest(JSON.parse(expected)), decoded,
        "Conversion must preserve every ordered token value and exclusion");
    } catch (error) {
      throw new Error(`${entry.name}: ${error.message}`, { cause: error });
    }
    tokens += decoded.items.length;
    const destination = path.join(outputPath, entry.name);
    let existing;
    try {
      existing = await fs.readFile(destination, "utf8");
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    if (existing != null && existing !== expected) {
      throw new Error(`${entry.name}: output already exists with different content.`);
    }
    if (existing == null) pending.push({ destination, expected });
  }
  await fs.mkdir(outputPath, { recursive: true });
  for (const { destination, expected } of pending) {
    await fs.writeFile(destination, expected, { flag: "wx" });
  }
  return { manifests: entries.length, tokens, written: pending.length };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const flags = process.argv.slice(2);
    const options = {};
    for (let index = 0; index < flags.length; index += 1) {
      const field = { "--input-directory": "inputDirectory", "--output-directory": "outputDirectory" }[flags[index]];
      if (!field || options[field] || !flags[index + 1] || flags[index + 1].startsWith("--")) {
        throw new Error(usage);
      }
      options[field] = flags[++index];
    }
    const { manifests, tokens, written } = await importTokenManifests(options);
    console.log(`Imported ${manifests} manifests, ${tokens} tokens; ${written} files written.`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
