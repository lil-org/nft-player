import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { importTokenManifests } from "./import-token-manifests.mjs";
import tokenManifest from "../tools/token_manifest.js";

const { decodeTokenManifest, serializeTokenManifest } = tokenManifest;

async function fixture(t, manifests) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-import-manifests-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const inputDirectory = path.join(directory, "input");
  const outputDirectory = path.join(directory, "output");
  await fs.mkdir(inputDirectory);
  for (const [name, payload] of Object.entries(manifests)) {
    await fs.writeFile(path.join(inputDirectory, name), JSON.stringify(payload));
  }
  return { inputDirectory, outputDirectory };
}

test("imports mixed legacy and v2 directories without changing ordered values, exclusions, or sources", async (t) => {
  const rows = [
    { id: "same", name: "", hash: "abc", urlSuffix: "0.png", aspectRatio: [8, 6], contractParameters: { z: "2", a: "1" } },
    { id: "same", urlSuffix: "1.png" },
    { id: "0007", urlSuffix: "2.png" },
    { id: "9223372036854775808", urlSuffix: "3.png" },
  ];
  const compact = { version: 2, count: 2, firstId: "9223372036854775806", excludedMediaIndices: [1] };
  const options = await fixture(t, { "legacy.json": { items: rows, excludedMediaIndices: [0, 2] }, "current.json": compact });
  const before = await fs.readFile(path.join(options.inputDirectory, "legacy.json"), "utf8");
  assert.deepEqual(await importTokenManifests(options), { manifests: 2, tokens: 6, written: 2 });
  const imported = await fs.readFile(path.join(options.outputDirectory, "legacy.json"), "utf8");
  assert.equal(imported, serializeTokenManifest(rows, { excludedMediaIndices: [0, 2] }));
  assert.deepEqual(decodeTokenManifest(JSON.parse(imported)), { items: rows, excludedMediaIndices: [0, 2] });
  assert.equal(await fs.readFile(path.join(options.outputDirectory, "current.json"), "utf8"), serializeTokenManifest(compact));
  assert.equal(await fs.readFile(path.join(options.inputDirectory, "legacy.json"), "utf8"), before);
  assert.deepEqual(await importTokenManifests(options), { manifests: 2, tokens: 6, written: 0 });
});

test("validates every source before creating any output", async (t) => {
  const options = await fixture(t, { "a_valid.json": { items: [{ id: "1" }] } });
  const invalidFile = path.join(options.inputDirectory, "z_invalid.json");
  for (const invalid of [
    "{", "null", "[]", "{}",
    JSON.stringify({ items: [{ id: "1", unsupported: "lost" }] }),
    JSON.stringify({ items: [{ id: "1", aspectRatio: [0, 1] }] }),
    JSON.stringify({ items: [{ id: "1", contractParameters: { amount: 1 } }] }),
    JSON.stringify({ items: [{ id: "1" }], excludedMediaIndices: [1] }),
    JSON.stringify({ items: [], version: 2 }),
    JSON.stringify({ version: 2, count: 2, ids: ["1"] }),
  ]) {
    await fs.writeFile(invalidFile, invalid);
    await assert.rejects(importTokenManifests(options), /z_invalid.json:/u);
    await assert.rejects(fs.access(options.outputDirectory), { code: "ENOENT" });
  }
});

test("conflicting outputs prevent all writes and identical outputs remain untouched", async (t) => {
  const options = await fixture(t, { "a_new.json": { items: [] }, "z_existing.json": { items: [{ id: "1" }] } });
  await fs.mkdir(options.outputDirectory);
  const existingPath = path.join(options.outputDirectory, "z_existing.json");
  await fs.writeFile(existingPath, "existing");
  await assert.rejects(importTokenManifests(options), /already exists with different content/u);
  assert.deepEqual(await fs.readdir(options.outputDirectory), ["z_existing.json"]);
  assert.equal(await fs.readFile(existingPath, "utf8"), "existing");
  await fs.writeFile(existingPath, serializeTokenManifest([{ id: "1" }]));
  const modificationTime = (await fs.stat(existingPath)).mtimeMs;
  assert.deepEqual(await importTokenManifests(options), { manifests: 2, tokens: 1, written: 1 });
  assert.equal((await fs.stat(existingPath)).mtimeMs, modificationTime);
});

test("rejects the same directory including symlink aliases", async (t) => {
  const options = await fixture(t, { "sample.json": { items: [{ id: "1" }] } });
  await assert.rejects(importTokenManifests({ ...options, outputDirectory: options.inputDirectory }), /must be different/u);
  await fs.symlink(options.inputDirectory, options.outputDirectory);
  await assert.rejects(importTokenManifests(options), /must be different/u);
  assert.deepEqual(JSON.parse(await fs.readFile(path.join(options.inputDirectory, "sample.json"), "utf8")), { items: [{ id: "1" }] });
});

test("CLI requires both explicit directories and imports using the documented flags", async (t) => {
  const script = fileURLToPath(new URL("./import-token-manifests.mjs", import.meta.url));
  const options = await fixture(t, { "sample.json": { items: [{ id: "1" }] } });
  for (const flags of [[], ["--input-directory", options.inputDirectory], ["--unknown"],
    ["--input-directory", options.inputDirectory, "--input-directory", options.inputDirectory]]) {
    const result = spawnSync(process.execPath, [script, ...flags], { encoding: "utf8" });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Usage:/u);
  }
  const result = spawnSync(process.execPath, [script, "--input-directory", options.inputDirectory,
    "--output-directory", options.outputDirectory], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Imported 1 manifests, 1 tokens; 1 files written/u);
  assert.equal(await fs.readFile(path.join(options.outputDirectory, "sample.json"), "utf8"), serializeTokenManifest([{ id: "1" }]));
});
