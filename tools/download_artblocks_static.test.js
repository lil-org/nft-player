"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const http = require("node:http");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const { capture, selection, validateTokens, pngCandidates, validateInventory, downloadOne, download, verify, save, hashFile } = require("./download_artblocks_static");
const runFile = promisify(execFile);
const address = "0x1234", identity = "1:0x1234:2";
const project = { id: "0x1234-2", chain_id: 1, contract_address: address, project_id: "2", name: "Static fixture", invocations: 3 };
const token = i => ({ id: `${address}-${2000000 + i}`, chain_id: 1, contract_address: address, project_id: project.id, token_id: String(2000000 + i), invocation: i, image: { url: `https://example.test/${2000000 + i}.png`, extension: "png" } });

async function fixture(t, count = 3) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "artblocks-static-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const folder = "samples/mb-static/static--1--0x1234--2", directory = path.join(root, folder);
  await fs.mkdir(directory, { recursive: true });
  await runFile("magick", ["-size", "8x8", "xc:red", path.join(directory, "2000000.png")]);
  const sha256 = await hashFile(path.join(directory, "2000000.png")), bytes = (await fs.stat(path.join(directory, "2000000.png"))).size;
  await save(path.join(directory, "manifest.json"), { identity, project, tokens: [{ token: token(0), download: { file: "2000000.png", extension: "png", width: 8, height: 8, bytes, sha256, source: "image", sourceURL: "https://example.test/2000000.png", resolvedURL: "https://example.test/2000000.png", contentType: "image/png" } }] });
  const row = { identity, name: project.name, decision: "mb static", localCollectionFolder: folder, samples: [{ tokenId: "2000000", localPath: folder + "/2000000.png" }] };
  await save(path.join(root, "tools/artblocks/reviews/deferred-static.json"), { version: 1, collectionCount: 1, tokenCount: 1, collections: [row] });
  await save(path.join(root, "tools/artblocks/rejected.json"), { collections: [] });
  const context = { output: path.join(root, "samples/mb-static"), minFreeGiB: 0, timeoutMs: 5000, maxRetries: 0, stopReason: null, apiURL: "https://api.example.test" };
  const offsets = [];
  const inventory = await capture(root, context, async (query, variables) => {
    if (query.includes("StaticProjects")) return { projects_metadata: [{ ...project, invocations: count }] };
    offsets.push(variables.offset);
    return { tokens_metadata: Array.from({ length: Math.min(200, count - variables.offset) }, (_, i) => token(i + variables.offset)) };
  });
  return { root, context, inventory, folder, directory, offsets, row };
}
async function server(t, data) {
  const requests = [];
  const httpServer = http.createServer((req, res) => {
    requests.push(req.url);
    if (req.url === "/bad.png") { res.writeHead(200, { "Content-Type": "image/png" }); res.end("<html>Access denied</html>"); }
    else { res.writeHead(200, { "Content-Type": "image/png", "Content-Length": data.length }); res.end(data); }
  });
  await new Promise(resolve => httpServer.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise(resolve => { httpServer.closeAllConnections(); httpServer.close(resolve); }));
  return { base: `http://127.0.0.1:${httpServer.address().port}`, requests };
}

test("capture paginates the full cutoff and preserves original files and manifests", async t => {
  const f = await fixture(t, 405);
  assert.deepEqual(f.offsets, [0, 200, 400]);
  assert.equal(f.inventory.collections[0].tokens.length, 405);
  assert.equal(f.inventory.collections[0].tokens.filter(t => t.original).length, 1);
  assert.equal(await hashFile(path.join(f.directory, "manifest.json")), f.inventory.collections[0].originalManifestSHA256);
});

test("token validation rejects gaps, duplicates, and other project identities", () => {
  validateTokens([token(0), token(1), token(2)], project, 3);
  for (const rows of [[token(0), token(2)], [token(0), token(0), token(2)], [token(0), { ...token(1), chain_id: 42161 }, token(2)]]) assert.throws(() => validateTokens(rows, project, 3));
});

test("PNG selection prefers standard images and never selects video, thumbnail, or live HTML", () => {
  const t = { ...token(0), video: { url: "https://example.test/video.mp4" }, high_res_image: { url: "https://example.test/high.png" }, low_res_image: { url: "https://example.test/low.png" }, preview_asset_url: "https://example.test/preview.png", live_view_url: "https://example.test/live.html" };
  assert.deepEqual(pngCandidates(t, project).map(c => c.source), ["image", "preview_asset_url", "media_proxy"]);
  assert.equal(pngCandidates({ ...t, image: { url: "https://example.test/animated.gif", extension: "gif" } }, project)[0].source, "preview_asset_url");
  assert(pngCandidates(t, project).every(c => c.exact && c.extension === "png"));
});

test("rejected and removed collections cannot be restored by resuming a frozen selection", async t => {
  const f = await fixture(t);
  await save(path.join(f.root, "tools/artblocks/rejected.json"), { collections: [{ identity }] });
  await assert.rejects(() => selection(f.root), /Ineligible/);
  await assert.rejects(() => validateInventory(f.root, f.inventory));
});

test("invalid PNG response falls back, atomic publication resumes, originals stay byte-identical", async t => {
  const f = await fixture(t, 2), data = await fs.readFile(path.join(f.directory, "2000000.png"));
  const web = await server(t, data), collection = f.inventory.collections[0], entry = collection.tokens[1];
  const manifest = await fs.readFile(path.join(f.directory, "manifest.json"));
  entry.candidates = [{ source: "image", url: web.base + "/bad.png", extension: "png", exact: true }, { source: "preview", url: web.base + "/valid.png", extension: "png", exact: true }];
  await download(f.root, f.context, f.inventory);
  assert.equal(entry.status, "downloaded");
  assert.equal(entry.download.source, "preview");
  assert.deepEqual(web.requests, ["/bad.png", "/valid.png"]);
  await download(f.root, f.context, f.inventory);
  assert.equal(web.requests.length, 2);
  assert.deepEqual(await fs.readFile(path.join(f.directory, "2000000.png")), data);
  assert.deepEqual(await fs.readFile(path.join(f.directory, "manifest.json")), manifest);
  await verify(f.root, f.inventory);
});

test("interruption after publication is recovered without a second network request", async t => {
  const f = await fixture(t, 2), data = await fs.readFile(path.join(f.directory, "2000000.png"));
  const web = await server(t, data), collection = f.inventory.collections[0], entry = collection.tokens[1];
  entry.candidates = [{ source: "image", url: web.base + "/valid.png", extension: "png", exact: true }];
  let persisted;
  await assert.rejects(() => downloadOne(f.root, f.context, f.inventory, collection, entry, async () => { persisted = structuredClone(f.inventory); }, { afterPublish: () => { throw new Error("interrupted"); } }), /interrupted/);
  assert.equal(persisted.collections[0].tokens[1].status, "verified");
  await download(f.root, f.context, persisted);
  assert.equal(web.requests.length, 1);
  await verify(f.root, persisted);
});

test("existing conflicting PNGs are never overwritten", async t => {
  const f = await fixture(t, 2), target = path.join(f.directory, "2000001.png");
  await fs.writeFile(target, "user file");
  await assert.rejects(() => download(f.root, f.context, f.inventory), /Conflicting existing PNG/);
  assert.equal(await fs.readFile(target, "utf8"), "user file");
});

test("PNG tampering, original-manifest changes, and symlinks stop verification", async t => {
  const f = await fixture(t, 1);
  f.inventory.status = "complete";
  await verify(f.root, f.inventory);
  await fs.writeFile(path.join(f.directory, "2000000.png"), "broken original");
  await assert.rejects(() => verify(f.root, f.inventory), /Conflicting existing PNG/);
  await fs.writeFile(path.join(f.directory, "manifest.json"), "{}");
  await assert.rejects(() => validateInventory(f.root, f.inventory), /Original manifest changed/);
});

test("metadata resume reuses the frozen cutoff instead of following later mints", async t => {
  const f = await fixture(t, 205);
  f.context.cutoffPath = path.join(f.root, "build/cutoff.json");
  f.context.metadataDirectory = path.join(f.root, "build/pages");
  await save(f.context.cutoffPath, { capturedAt: f.inventory.capturedAt, sourceIndexSHA256: f.inventory.sourceIndexSHA256,
    sourceRejectedSHA256: f.inventory.sourceRejectedSHA256, projects: [{ ...project, invocations: 205 }] });
  let requests = 0;
  const first = await capture(f.root, f.context, async (query, variables) => {
    assert(query.includes("StaticTokens"));
    requests++;
    return { tokens_metadata: Array.from({ length: Math.min(200, 205 - variables.offset) }, (_, i) => token(i + variables.offset)) };
  });
  assert.equal(requests, 2);
  const resumed = await capture(f.root, f.context, async () => { throw new Error("Unexpected metadata refresh"); });
  assert.deepEqual(resumed, first);
});

test("interruption before publication retries only the missing token", async t => {
  const f = await fixture(t, 2), data = await fs.readFile(path.join(f.directory, "2000000.png"));
  const web = await server(t, data), collection = f.inventory.collections[0], entry = collection.tokens[1];
  entry.candidates = [{ source: "image", url: web.base + "/valid.png", extension: "png", exact: true }];
  let persisted;
  await assert.rejects(() => downloadOne(f.root, f.context, f.inventory, collection, entry, async () => { persisted = structuredClone(f.inventory); }, { beforePublish: () => { throw new Error("interrupted"); } }), /interrupted/);
  assert.equal(persisted.collections[0].tokens[1].status, "verified");
  await assert.rejects(() => fs.stat(path.join(f.directory, "2000001.png")), { code: "ENOENT" });
  await download(f.root, f.context, persisted);
  await verify(f.root, persisted);
  assert.equal(web.requests.length, 2);
});

test("symlinked sample files and incomplete API pages are refused", async t => {
  const f = await fixture(t, 2);
  await fs.symlink(path.join(f.directory, "2000000.png"), path.join(f.directory, "2000001.png"));
  await assert.rejects(() => validateInventory(f.root, f.inventory), /Unexpected collection file/);
  await fs.unlink(path.join(f.directory, "2000001.png"));
  await assert.rejects(() => capture(f.root, f.context, async query => query.includes("StaticProjects")
    ? { projects_metadata: [{ ...project, invocations: 2 }] } : { tokens_metadata: [token(0)] }), /Incomplete token page/);
});

test("disk reserve pauses transfers without publishing a file", async t => {
  const f = await fixture(t, 2), collection = f.inventory.collections[0], entry = collection.tokens[1];
  f.context.minFreeGiB = Number.MAX_SAFE_INTEGER;
  await download(f.root, f.context, f.inventory);
  assert.equal(f.inventory.status, "paused");
  assert.match(f.context.stopReason, /disk space/);
  await assert.rejects(() => fs.stat(path.join(f.directory, "2000001.png")), { code: "ENOENT" });
});
