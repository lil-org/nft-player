#!/usr/bin/env node
"use strict";

const fs = require("node:fs/promises");
const { createReadStream } = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const { graphql, downloadCandidate, validateMedia } = require("./download_artblocks_samples");

const runFile = promisify(execFile);
const ROOT = path.resolve(__dirname, "..");
const INDEX = "tools/artblocks/reviews/deferred-static.json";
const REJECTED = "tools/artblocks/rejected.json";
const INVENTORY = "tools/artblocks/reviews/static-downloads.json";
const PAGE_SIZE = 200;
const json = value => JSON.stringify(value, null, 2) + "\n";
const sha256 = value => createHash("sha256").update(value).digest("hex");
const requireValid = (condition, message) => { if (!condition) throw new Error(message); };

async function read(file) { return JSON.parse(await fs.readFile(file, "utf8")); }
async function optional(file) { try { return await read(file); } catch (error) { if (error.code === "ENOENT") return null; throw error; } }
async function hashFile(file) { const hash = createHash("sha256"); for await (const chunk of createReadStream(file)) hash.update(chunk); return hash.digest("hex"); }
async function safePath(root, relative) {
  requireValid(!path.isAbsolute(relative) && !relative.split(/[\\/]/u).includes(".."), `Unsafe path: ${relative}`);
  let current = root;
  for (const part of relative.split("/")) {
    current = path.join(current, part);
    const stat = await fs.lstat(current).catch(error => { if (error.code === "ENOENT") return null; throw error; });
    requireValid(!stat?.isSymbolicLink(), `Symlink refused: ${current}`);
  }
  return current;
}
async function save(file, value) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  const temporary = file + ".tmp";
  const handle = await fs.open(temporary, "w");
  try { await handle.writeFile(json(value)); await handle.sync(); } finally { await handle.close(); }
  await fs.rename(temporary, file);
}

function projectKey(project) { return `${project.chain_id}:${project.contract_address.toLowerCase()}:${project.project_id}`; }
function projectFor(identity) {
  const [chain, address, id] = identity.split(":");
  requireValid(/^\d+$/u.test(chain) && /^0x[0-9a-f]+$/u.test(address) && /^\d+$/u.test(id), `Invalid identity: ${identity}`);
  return { chain_id: Number(chain), contract_address: address, project_id: id, id: `${address}-${id}` };
}
function validateTokens(tokens, project, cutoff) {
  requireValid(tokens.length === cutoff, `Incomplete token coverage: ${project.id}: ${tokens.length}/${cutoff}`);
  for (let invocation = 0; invocation < cutoff; invocation++) {
    const token = tokens[invocation], id = String(BigInt(project.project_id) * 1000000n + BigInt(invocation));
    requireValid(token.token_id === id && token.invocation === invocation && token.chain_id === project.chain_id
      && token.contract_address?.toLowerCase() === project.contract_address && token.project_id === project.id
      && token.id === `${project.contract_address}-${id}`, `Token identity/order mismatch: ${project.id}/${invocation}`);
  }
}
function pngCandidates(token, project) {
  const choices = [
    ["image", token.image?.url, token.image?.extension],
    ["preview_asset_url", token.preview_asset_url, "png"],
    ["media_proxy", `https://media-proxy.artblocks.io/${project.chain_id}/${project.contract_address}/${token.token_id}.png`, "png"],
  ];
  const seen = new Set();
  return choices.flatMap(([source, value, extension]) => {
    let url;
    try { url = new URL(value); } catch { return []; }
    if (url.protocol !== "https:" || url.username || url.password || seen.has(url.href)) return [];
    if (extension?.toLowerCase() !== "png" && !/\.png$/iu.test(url.pathname)) return [];
    seen.add(url.href);
    return [{ source, url: url.href, extension: "png", exact: true }];
  });
}

async function selection(root) {
  const indexBytes = await fs.readFile(path.join(root, INDEX));
  const index = JSON.parse(indexBytes), rejectedBytes = await fs.readFile(path.join(root, REJECTED));
  const rejected = new Set(JSON.parse(rejectedBytes).collections.map(row => row.identity));
  const seen = new Set();
  for (const row of index.collections) {
    requireValid(row.decision === "mb static" && !rejected.has(row.identity) && !seen.has(row.identity), `Ineligible or duplicate collection: ${row.identity}`);
    requireValid(row.localCollectionFolder.startsWith("samples/mb-static/") && row.localCollectionFolder.split("/").length === 3, `Unexpected folder: ${row.localCollectionFolder}`);
    const directory = await safePath(root, row.localCollectionFolder);
    requireValid((await fs.stat(directory)).isDirectory(), `Missing collection folder: ${row.name}`);
    seen.add(row.identity);
  }
  requireValid(seen.size === index.collectionCount && index.tokenCount === index.collections.reduce((sum, row) => sum + row.samples.length, 0), "Invalid static index totals");
  const folders = await fs.readdir(path.join(root, "samples/mb-static"), { withFileTypes: true });
  const expected = new Set(index.collections.map(row => path.basename(row.localCollectionFolder)));
  for (const entry of folders) requireValid(!entry.isSymbolicLink() && (entry.isDirectory() ? expected.has(entry.name) : entry.name === ".DS_Store"), `Unexpected static entry: ${entry.name}`);
  return { index, indexSHA256: sha256(indexBytes), rejectedSHA256: sha256(rejectedBytes) };
}

async function capture(root, context, request = (query, variables) => graphql(context, query, variables)) {
  const selected = await selection(root);
  const where = { _or: selected.index.collections.map(row => {
    const project = projectFor(row.identity);
    return { chain_id: { _eq: project.chain_id }, contract_address: { _eq: project.contract_address }, project_id: { _eq: project.project_id } };
  }) };
  let cutoff = context.cutoffPath ? await optional(context.cutoffPath) : null;
  if (!cutoff) {
    const result = await request(`query StaticProjects($where: projects_metadata_bool_exp!) {
      projects_metadata(where: $where) { id chain_id contract_address project_id name invocations }
    }`, { where });
    cutoff = { capturedAt: new Date().toISOString(), sourceIndexSHA256: selected.indexSHA256,
      sourceRejectedSHA256: selected.rejectedSHA256, projects: result.projects_metadata };
    if (context.cutoffPath) await save(context.cutoffPath, cutoff);
  }
  requireValid(cutoff.sourceIndexSHA256 === selected.indexSHA256 && cutoff.sourceRejectedSHA256 === selected.rejectedSHA256, "Decisions changed since frozen cutoff");
  const rows = cutoff.projects, projects = new Map(rows.map(row => [projectKey(row), row]));
  requireValid(projects.size === rows.length && projects.size === selected.index.collectionCount, "Project capture is incomplete or duplicated");
  const inventory = { version: 1, capturedAt: cutoff.capturedAt, apiURL: context.apiURL,
    sourceIndexSHA256: selected.indexSHA256, sourceRejectedSHA256: selected.rejectedSHA256,
    status: "incomplete", collections: [] };
  for (const row of selected.index.collections) {
    const project = projects.get(row.identity);
    requireValid(project && project.name === row.name && Number.isSafeInteger(project.invocations) && project.invocations >= row.samples.length, `Invalid cutoff: ${row.name}`);
    const directory = await safePath(root, row.localCollectionFolder);
    const manifestBytes = await fs.readFile(await safePath(root, row.localCollectionFolder + "/manifest.json")), manifest = JSON.parse(manifestBytes);
    requireValid(manifest.identity === row.identity && projectKey(manifest.project) === row.identity, `Original manifest mismatch: ${row.name}`);
    const originals = new Map(manifest.tokens.map(entry => [entry.token.token_id, entry]));
    const tokens = [];
    for (let offset = 0; offset < project.invocations; offset += PAGE_SIZE) {
      const pagePath = context.metadataDirectory ? path.join(context.metadataDirectory, row.identity.replaceAll(":", "-") + `-${offset}.json`) : null;
      let page = pagePath ? await optional(pagePath) : null;
      if (page) requireValid(page.capturedAt === cutoff.capturedAt && page.invocationCutoff === project.invocations, `Stale metadata page: ${row.name}/${offset}`);
      if (!page) {
        page = await request(`query StaticTokens($project: String!, $chain: Int!, $address: String!, $cutoff: Int!, $offset: Int!) {
        tokens_metadata(where: { project_id: {_eq: $project}, chain_id: {_eq: $chain}, contract_address: {_eq: $address}, invocation: {_lt: $cutoff} },
          order_by: [{invocation: asc}, {id: asc}], limit: ${PAGE_SIZE}, offset: $offset) {
          id chain_id contract_address project_id token_id invocation image { url extension } preview_asset_url
        }
      }`, { project: project.id, chain: project.chain_id, address: project.contract_address, cutoff: project.invocations, offset });
        page.capturedAt = cutoff.capturedAt;
        page.invocationCutoff = project.invocations;
        if (pagePath) await save(pagePath, page);
      }
      requireValid(page.tokens_metadata.length === Math.min(PAGE_SIZE, project.invocations - offset), `Incomplete token page: ${row.name}/${offset}`);
      tokens.push(...page.tokens_metadata);
    }
    validateTokens(tokens, project, project.invocations);
    const originalIDs = new Set(row.samples.map(sample => sample.tokenId));
    requireValid(originalIDs.size === row.samples.length && originals.size === row.samples.length, `Original token mismatch: ${row.name}`);
    const records = [];
    for (const token of tokens) {
      const original = originals.get(token.token_id), file = token.token_id + ".png";
      if (originalIDs.has(token.token_id)) {
        const reference = row.samples.find(sample => sample.tokenId === token.token_id);
        requireValid(original?.download?.file === file && original.download.extension === "png" && reference.localPath === row.localCollectionFolder + "/" + file, `Original file mismatch: ${row.name}/${file}`);
        const data = original.download, target = await safePath(root, reference.localPath), info = await fs.stat(target);
        requireValid(info.isFile() && info.size === data.bytes && await hashFile(target) === data.sha256, `Original PNG changed: ${target}`);
        records.push({ id: token.token_id, file, original: true, status: "downloaded",
          download: { source: data.source, sourceURL: data.sourceURL, resolvedURL: data.resolvedURL, bytes: data.bytes, sha256: data.sha256,
            width: data.width, height: data.height, extension: "png", contentType: data.contentType } });
      } else {
        const candidates = pngCandidates(token, project);
        requireValid(candidates.length, `No PNG source: ${row.name}/${file}`);
        records.push({ id: token.token_id, file, original: false, status: "pending", candidates });
      }
    }
    requireValid(records.filter(entry => entry.original).length === row.samples.length, `Original selection outside cutoff: ${row.name}`);
    inventory.collections.push({ identity: row.identity, name: row.name, folder: row.localCollectionFolder,
      invocationCutoff: project.invocations, originalManifestSHA256: sha256(manifestBytes), tokens: records });
    console.log(`Captured ${inventory.collections.length}/${selected.index.collectionCount}: ${row.name} (${records.length} tokens)`);
  }
  await validateInventory(root, inventory);
  return inventory;
}

async function validateInventory(root, inventory) {
  const selected = await selection(root);
  requireValid(inventory.version === 1 && inventory.sourceIndexSHA256 === selected.indexSHA256 && inventory.sourceRejectedSHA256 === selected.rejectedSHA256, "Decisions changed since capture; refusing to expand or restore selection");
  const rows = new Map(selected.index.collections.map(row => [row.identity, row]));
  requireValid(inventory.collections.length === rows.size && new Set(inventory.collections.map(row => row.identity)).size === rows.size, "Frozen collection membership mismatch");
  for (const collection of inventory.collections) {
    const row = rows.get(collection.identity), project = projectFor(collection.identity);
    requireValid(row && row.localCollectionFolder === collection.folder && row.name === collection.name, `Frozen identity mismatch: ${collection.identity}`);
    requireValid(Number.isSafeInteger(collection.invocationCutoff) && collection.invocationCutoff >= row.samples.length && collection.tokens.length === collection.invocationCutoff, `Incomplete inventory: ${collection.name}`);
    const directory = await safePath(root, collection.folder);
    requireValid(await hashFile(path.join(directory, "manifest.json")) === collection.originalManifestSHA256, `Original manifest changed: ${collection.name}`);
    const original = await read(path.join(directory, "manifest.json")), originals = new Map(original.tokens.map(entry => [entry.token.token_id, entry]));
    const expectedOriginalIDs = new Set(row.samples.map(sample => sample.tokenId));
    for (let i = 0; i < collection.tokens.length; i++) {
      const token = collection.tokens[i], expectedID = String(BigInt(project.project_id) * 1000000n + BigInt(i));
      requireValid(token.id === expectedID && token.file === expectedID + ".png" && token.original === expectedOriginalIDs.has(token.id), `Frozen token mismatch: ${collection.name}/${i}`);
      if (token.original) {
        const saved = originals.get(token.id)?.download;
        requireValid(saved && saved.file === token.file && saved.sha256 === token.download?.sha256 && saved.bytes === token.download?.bytes, `Original record changed: ${collection.name}/${token.id}`);
      }
      if (token.download) requireValid(/^[0-9a-f]{64}$/u.test(token.download.sha256) && token.download.bytes > 0 && token.download.extension === "png", `Invalid file metadata: ${collection.name}/${token.id}`);
    }
    const files = await fs.readdir(directory, { withFileTypes: true }), expected = new Set(collection.tokens.map(token => token.file));
    for (const file of files) requireValid(!file.isSymbolicLink() && file.isFile() && (expected.has(file.name) || file.name === "manifest.json" || file.name === ".DS_Store"), `Unexpected collection file: ${collection.name}/${file.name}`);
  }
}

async function verifyToken(root, collection, token, deep = false) {
  const target = await safePath(root, collection.folder + "/" + token.file);
  const stat = await fs.stat(target).catch(error => { if (error.code === "ENOENT") return null; throw error; });
  if (!stat) { requireValid(!token.original, `Original PNG missing: ${target}`); return false; }
  requireValid(token.download && stat.isFile() && stat.size === token.download.bytes && await hashFile(target) === token.download.sha256, `Conflicting existing PNG: ${target}`);
  if (deep) {
    const media = await validateMedia(target, "image/png");
    requireValid(media.extension === "png" && media.width === token.download.width && media.height === token.download.height, `Invalid PNG: ${target}`);
    await runFile("magick", [target, "null:"], { timeout: 90000, maxBuffer: 1024 * 1024 });
  }
  return true;
}

function summary(inventory) {
  const tokens = inventory.collections.flatMap(collection => collection.tokens);
  return { status: inventory.status, capturedAt: inventory.capturedAt, collections: inventory.collections.length,
    expectedPNGs: tokens.length, originalPNGs: tokens.filter(token => token.original).length,
    verifiedPNGs: tokens.filter(token => token.status === "downloaded").length,
    additionalPNGs: tokens.filter(token => !token.original && token.status === "downloaded").length,
    bytes: tokens.reduce((sum, token) => sum + (token.status === "downloaded" ? token.download.bytes : 0), 0),
    failures: inventory.collections.flatMap(collection => collection.tokens.filter(token => token.status === "failed").map(token => ({ collection: collection.name, tokenId: token.id, errors: token.errors }))) };
}
async function workConcurrent(jobs, count, work) {
  let next = 0;
  const results = await Promise.allSettled(Array.from({ length: count }, async () => {
    while (next < jobs.length) await work(jobs[next++]);
  }));
  const failed = results.find(result => result.status === "rejected");
  if (failed) throw failed.reason;
}

async function downloadOne(root, context, inventory, collection, token, persist, hooks = {}) {
  if (await verifyToken(root, collection, token)) { token.status = "downloaded"; return; }
  const partialDirectory = await safePath(root, "build/artblocks-static-download/partials");
  await fs.mkdir(partialDirectory, { recursive: true });
  const temporary = path.join(partialDirectory, collection.identity.replaceAll(":", "-") + "-" + token.id + ".part");
  token.status = "pending";
  token.errors = [];
  for (const candidate of token.candidates) {
    if (context.stopReason) return;
    let data;
    try {
      await fs.rm(temporary, { force: true });
      data = await (hooks.downloadCandidate ?? downloadCandidate)(context, candidate, temporary);
      requireValid(data.extension === "png", `Unexpected media: ${data.extension}`);
      await runFile("magick", [temporary, "null:"], { timeout: 90000, maxBuffer: 1024 * 1024 });
    } catch (error) {
      token.errors.push({ source: candidate.source, url: candidate.url, error: error.message });
      continue;
    }
    token.download = data;
    token.status = "verified";
    await persist();
    await hooks.beforePublish?.();
    const target = await safePath(root, collection.folder + "/" + token.file);
    try { await fs.link(temporary, target); }
    catch (error) {
      if (error.code === "EEXIST") throw new Error(`Refusing to overwrite newly appeared file: ${collection.name}/${token.id}`);
      throw error;
    }
    await fs.unlink(temporary);
    await hooks.afterPublish?.();
    token.status = "downloaded";
    delete token.errors;
    await persist();
    return;
  }
  await fs.rm(temporary, { force: true });
  token.status = "failed";
  delete token.download;
  await persist();
}

async function download(root, context, inventory, inventoryPath = path.join(root, INVENTORY)) {
  await validateInventory(root, inventory);
  let writes = Promise.resolve();
  const persist = () => { writes = writes.then(() => save(inventoryPath, inventory)); return writes; };
  const jobs = inventory.collections.flatMap(collection => collection.tokens.map(token => ({ collection, token })));
  for (const { collection, token } of jobs) await verifyToken(root, collection, token);
  let completed = 0;
  await workConcurrent(jobs, 6, async ({ collection, token }) => {
    if (context.stopReason) return;
    try { await downloadOne(root, context, inventory, collection, token, persist); }
    catch (error) { context.stopReason = error.message; throw error; }
    completed++;
    if (completed % 50 === 0 || completed === jobs.length) console.log(JSON.stringify({ checked: completed, ...summary(inventory) }));
  });
  await writes;
  inventory.status = context.stopReason ? "paused" : jobs.every(({ token }) => token.status === "downloaded") ? "complete" : "incomplete";
  await persist();
  return summary(inventory);
}
async function verify(root, inventory) {
  await validateInventory(root, inventory);
  const jobs = inventory.collections.flatMap(collection => collection.tokens.map(token => ({ collection, token })));
  await workConcurrent(jobs, 4, async ({ collection, token }) => requireValid(await verifyToken(root, collection, token, true), `Missing PNG: ${collection.name}/${token.id}`));
  requireValid(inventory.status === "complete" && jobs.every(({ token }) => token.status === "downloaded"), "Inventory is incomplete");
  return summary(inventory);
}

async function main(args = process.argv.slice(2)) {
  requireValid(args.length <= 1 && (!args.length || ["--plan", "--download", "--verify"].includes(args[0])), "Usage: node tools/download_artblocks_static.js [--plan|--download|--verify]");
  const mode = args[0] ?? "--plan", inventoryPath = path.join(ROOT, INVENTORY);
  const context = { apiURL: "https://data.artblocks.io/v1/graphql", output: path.join(ROOT, "samples/mb-static"), minFreeGiB: 10, maxRetries: 5, timeoutMs: 90000, stopReason: null };
  let inventory = await optional(inventoryPath);
  if (mode === "--verify") { requireValid(inventory, "No frozen download inventory"); console.log(json(await verify(ROOT, inventory))); return; }
  if (mode === "--plan") { inventory ??= await capture(ROOT, context); await validateInventory(ROOT, inventory); console.log(json(summary(inventory))); return; }
  context.cutoffPath = path.join(ROOT, "build/artblocks-static-download/cutoff.json");
  context.metadataDirectory = path.join(ROOT, "build/artblocks-static-download/metadata");
  const lock = path.join(ROOT, "build/artblocks-static-download/run.lock");
  await fs.mkdir(path.dirname(lock), { recursive: true });
  const previous = await optional(lock);
  if (previous) {
    requireValid(Number.isSafeInteger(previous.pid) && previous.pid > 0, "Invalid download lock");
    let alive = true;
    try { process.kill(previous.pid, 0); } catch (error) { if (error.code === "ESRCH") alive = false; else throw error; }
    requireValid(!alive, "Another static download is running");
    await fs.unlink(lock);
  }
  const handle = await fs.open(lock, "wx");
  await handle.writeFile(json({ pid: process.pid }));
  await handle.close();
  const stop = () => { context.stopReason = "Interrupted; rerun --download to resume"; };
  process.once("SIGINT", stop); process.once("SIGTERM", stop);
  try {
    inventory ??= await capture(ROOT, context);
    await save(inventoryPath, inventory);
    console.log(json(await download(ROOT, context, inventory)));
    if (inventory.status !== "complete") process.exitCode = 2;
  } finally {
    process.removeListener("SIGINT", stop); process.removeListener("SIGTERM", stop);
    await fs.unlink(lock);
  }
}
module.exports = { capture, selection, validateTokens, pngCandidates, validateInventory, verifyToken, downloadOne, download, verify, summary, main, save, hashFile };
if (require.main === module) main().catch(error => { console.error(error.stack ?? error.message); process.exitCode = 1; });
