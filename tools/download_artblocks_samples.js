#!/usr/bin/env node
"use strict";

const fs = require("node:fs/promises");
const { createReadStream, createWriteStream } = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { Readable, Transform } = require("node:stream");
const { pipeline } = require("node:stream/promises");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const { GROUPS, identity, projectIdentity, validateCuration, scanGroups, captureCuration,
  curationStats, projectFromEntry } = require("./artblocks/curation");

const runFile = promisify(execFile);
const ROOT = path.resolve(__dirname, "..");
const API_URL = "https://data.artblocks.io/v1/graphql";
const SAMPLE_COUNT = 23;
const GIB = 1024 ** 3;
const TRANSIENT_STATUSES = new Set([408, 425, 429, 500, 502, 503, 504]);
const IMAGE_EXTENSIONS = new Set(["png", "jpg", "jpeg", "webp", "gif", "avif", "heic", "heif", "tif", "tiff", "bmp"]);
const VIDEO_EXTENSIONS = new Set(["mp4", "mov", "webm", "m4v"]);
const MIME_EXTENSIONS = new Map([
  ["image/png", "png"], ["image/apng", "png"], ["image/jpeg", "jpg"],
  ["image/webp", "webp"], ["image/gif", "gif"], ["image/avif", "avif"],
  ["image/heic", "heic"], ["image/heif", "heif"], ["image/tiff", "tiff"],
  ["image/bmp", "bmp"], ["image/svg+xml", "svg"], ["text/html", "html"],
  ["application/xhtml+xml", "html"], ["video/mp4", "mp4"],
  ["video/quicktime", "mov"], ["video/webm", "webm"], ["video/x-m4v", "m4v"],
]);
function folderName(project) {
  const slug = String(project.name || "untitled").normalize("NFKD").replace(/\p{M}/gu, "")
    .toLowerCase().replace(/[^a-z0-9]+/gu, "-").replace(/^-|-$/gu, "").slice(0, 80).replace(/-$/u, "") || "untitled";
  projectIdentity(project);
  return `${slug}--${project.chain_id}--${project.contract_address.toLowerCase()}--${BigInt(project.project_id)}`;
}

async function readJSON(file) {
  try { return JSON.parse(await fs.readFile(file, "utf8")); }
  catch (error) { if (error.code === "ENOENT") return null; throw error; }
}

async function writeJSON(file, value) {
  const temporary = `${file}.tmp`;
  await fs.writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`);
  await fs.rename(temporary, file);
}

async function historicalDecisions(context) {
  const root = context.decisionDirectory ?? path.join(__dirname, "artblocks");
  const rejected = await readJSON(path.join(root, "rejected.json"));
  const deferred = await readJSON(path.join(root, "reviews/deferred-static.json"));
  return new Set([...(rejected?.collections ?? []), ...(deferred?.collections ?? [])].map(collection => collection.identity));
}

async function bundledIdentities(projects, bundle) {
  const items = await readJSON(path.join(bundle, "items.json"));
  if (!Array.isArray(items)) throw new Error("Missing bundled collection catalog");
  const apiKeys = new Set(projects.map(projectIdentity));
  const contracts = new Set(projects.map(p => `${p.chain_id}:${p.contract_address.toLowerCase()}`));
  const keys = new Set();
  const inferred = [];
  for (const item of items) {
    if (!contracts.has(`${item.chainId}:${item.address.toLowerCase()}`)) continue;
    if (item.abId != null) {
      keys.add(identity(item.chainId, item.address, item.abId));
      continue;
    }
    const stem = item.address + (item.collectionId ?? "");
    const tokens = await readJSON(path.join(bundle, "Tokens", `${stem}.json`))
      ?? await readJSON(path.join(bundle, "Tokens", `${stem.toLowerCase()}.json`));
    if (!Array.isArray(tokens?.items)) throw new Error(`Cannot resolve bundled tokens for ${item.name}`);
    const projectIds = new Set();
    for (const token of tokens.items) {
      const id = String(Array.isArray(token) ? token[0] : token.id);
      if (!/^\d+$/u.test(id)) throw new Error(`Non-numeric bundled Art Blocks token in ${item.name}: ${id}`);
      const projectId = String(BigInt(id) / 1000000n);
      const key = identity(item.chainId, item.address, projectId);
      if (apiKeys.has(key)) { keys.add(key); projectIds.add(projectId); }
    }
    inferred.push({ name: item.name, chainId: item.chainId, address: item.address, projectIds: [...projectIds] });
  }
  return { keys, inferred };
}

function retryDelay(attempt, retryAfter, now = Date.now()) {
  const header = retryAfter == null ? 0 : /^\d+(\.\d+)?$/u.test(retryAfter)
    ? Number(retryAfter) * 1000 : Math.max(0, Date.parse(retryAfter) - now) || 0;
  return Math.max(header, 1000 * 2 ** attempt);
}

async function retry(context, action) {
  for (let attempt = 0; ; attempt++) {
    if (context.stopReason) throw new Error(context.stopReason);
    try { return await action(); }
    catch (error) {
      if (!error.retryable || attempt >= context.maxRetries || context.stopReason) throw error;
      const delay = retryDelay(attempt, error.retryAfter);
      if (context.sleep) await context.sleep(delay);
      else await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
}

async function response(context, url, options = {}) {
  try {
    const result = await fetch(url, { ...options, redirect: "follow", signal: AbortSignal.timeout(context.timeoutMs) });
    if (!result.ok) {
      await result.body?.cancel();
      throw Object.assign(new Error(`HTTP ${result.status}: ${url}`), {
        httpStatus: result.status,
        retryable: TRANSIENT_STATUSES.has(result.status),
        retryAfter: result.headers.get("retry-after"),
      });
    }
    return result;
  } catch (error) {
    if (error.retryable == null) error.retryable = true;
    throw error;
  }
}

async function graphql(context, query, variables = {}) {
  return retry(context, async () => {
    const start = Math.max(Date.now(), context.nextGraphqlAt ?? 0);
    context.nextGraphqlAt = start + 750;
    if (start > Date.now()) await new Promise(resolve => setTimeout(resolve, start - Date.now()));
    const result = await response(context, context.apiURL, {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ query, variables }),
    });
    let data;
    try { data = await result.json(); }
    catch (error) { error.retryable = true; throw error; }
    if (data.errors?.length) {
      const rateLimited = data.errors.some(error => error.extensions?.code === "rate-limit-exceeded");
      throw Object.assign(new Error(`GraphQL: ${JSON.stringify(data.errors)}`), {
        retryable: rateLimited, retryAfter: rateLimited ? "60" : null,
      });
    }
    if (!data.data) throw new Error("GraphQL response has no data");
    return data.data;
  });
}

async function discover(context) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const projects = [];
    const before = (await graphql(context, "{ projects_metadata_aggregate { aggregate { count } } }"))
      .projects_metadata_aggregate.aggregate.count;
    for (let offset = 0; ; offset += 200) {
      const data = await graphql(context, `query Inventory($offset: Int!) {
        projects_metadata(order_by: [{chain_id: asc}, {id: asc}], limit: 200, offset: $offset) {
          id chain_id contract_address project_id name artist_name invocations
        }
      }`, { offset });
      projects.push(...data.projects_metadata);
      if (data.projects_metadata.length < 200) break;
    }
    const after = (await graphql(context, "{ projects_metadata_aggregate { aggregate { count } } }"))
      .projects_metadata_aggregate.aggregate.count;
    if (before !== after || projects.length !== after || new Set(projects.map(projectIdentity)).size !== after) continue;
    const bundled = await bundledIdentities(projects, context.bundle);
    const missing = projects.filter(p => !bundled.keys.has(projectIdentity(p)));
    return { fetchedAt: new Date().toISOString(), apiURL: context.apiURL, total: after,
      excluded: after - missing.length, inferredExclusions: bundled.inferred, projects: missing };
  }
  throw new Error("API inventory changed or pagination is incomplete after three attempts");
}

function selectTokens(tokens, project, availableCount) {
  const sorted = [...tokens].sort((a, b) => a.invocation - b.invocation);
  const expected = Math.min(SAMPLE_COUNT, availableCount);
  if (sorted.length !== expected || new Set(sorted.map(t => t.token_id)).size !== expected) {
    throw new Error(`Incomplete or duplicate token selection for ${project.id}: ${sorted.length}/${expected}`);
  }
  for (const token of sorted) {
    if (token.chain_id !== project.chain_id || !/^\d+$/u.test(token.token_id)
      || BigInt(token.token_id) / 1000000n !== BigInt(project.project_id)) {
      throw new Error(`Token identity mismatch: ${token.id}`);
    }
  }
  return sorted;
}

async function mapConcurrent(values, concurrency, work) {
  let next = 0;
  const results = new Array(values.length);
  await Promise.all(Array.from({ length: Math.min(concurrency, values.length) }, async () => {
    while (next < values.length) {
      const index = next++;
      results[index] = await work(values[index], index);
    }
  }));
  return results;
}

async function resolveCuratedRecords(context, curation) {
  validateCuration(curation);
  const local = await scanGroups(context.output);
  const locations = new Map([...local].map(([key, record]) => [record.directory.normalize("NFC").toLowerCase(), key]));
  for (const [key] of local) {
    if (!curation.collections[key] || curation.collections[key].group === "excluded") {
      throw new Error(`Unrecorded local collection ${key}; capture curation before downloading`);
    }
  }
  const records = [];
  const decided = await historicalDecisions(context);
  for (const [key, entry] of Object.entries(curation.collections)) {
    if (entry.group === "excluded" || decided.has(key)) continue;
    const found = local.get(key);
    const group = found?.group ?? entry.group;
    if (context.group && group !== context.group) continue;
    const directory = found?.directory ?? path.join(context.output, group, entry.directory);
    const location = directory.normalize("NFC").toLowerCase();
    if (locations.has(location) && locations.get(location) !== key) {
      throw new Error(`Collection directory is occupied by another identity: ${directory}`);
    }
    locations.set(location, key);
    const project = projectFromEntry(key, entry);
    project.group = group;
    project.directory = path.relative(context.output, directory);
    const manifest = found?.manifest ?? {
      version: 1, identity: key, project,
      capturedAt: curation.source.discoveredAt, selection: "first-minted", requestedCount: SAMPLE_COUNT,
      selectionComplete: true, availableCount: entry.samples.length, expectedCount: entry.samples.length,
      metadataError: null,
      tokens: entry.samples.map(sample => ({
        token: { id: `${project.contract_address}-${sample.tokenId}`, chain_id: project.chain_id,
          token_id: sample.tokenId, invocation: sample.invocation },
        status: "pending", failures: [],
      })),
    };
    selectTokens(manifest.tokens.map(e => e.token), project, entry.samples.length);
    for (let index = 0; index < entry.samples.length; index++) {
      const sample = entry.samples[index];
      const token = manifest.tokens[index];
      if (token.token.token_id !== sample.tokenId || token.token.invocation !== sample.invocation) {
        throw new Error(`Local sample selection conflicts with curation for ${key}`);
      }
      if (token.download && (token.download.sourceURL !== sample.url || token.download.extension !== sample.extension)) {
        throw new Error(`Local sample media conflicts with curation for ${key}/${sample.tokenId}`);
      }
      token.reference = sample;
    }
    manifest.project = project;
    records.push({ directory, file: path.join(directory, "manifest.json"), manifest });
  }
  return records;
}

async function prepareCuratedRecords(records) {
  for (const record of records) {
    await fs.mkdir(record.directory, { recursive: true });
    await writeJSON(record.file, record.manifest);
  }
}

function normalizeURL(value) {
  if (!value) return null;
  let url = String(value).trim();
  if (url.startsWith("ipfs://")) url = `https://ipfs.io/ipfs/${url.slice(7).replace(/^ipfs\//u, "")}`;
  if (url.startsWith("ar://")) url = `https://arweave.net/${url.slice(5)}`;
  try {
    const parsed = new URL(url);
    return ["http:", "https:"].includes(parsed.protocol) && !parsed.username && !parsed.password ? parsed.href : null;
  } catch { return null; }
}

function extensionForURL(url) {
  const parsed = new URL(url);
  const extension = path.extname(parsed.pathname).slice(1).toLowerCase();
  if (IMAGE_EXTENSIONS.has(extension) || VIDEO_EXTENSIONS.has(extension) || ["html", "svg"].includes(extension)) return extension;
  if (parsed.hostname === "generator.artblocks.io") return "html";
  return null;
}

function mediaRank(extension, source, animated = extension === "gif") {
  if (VIDEO_EXTENSIONS.has(extension)) return extension === "mp4" ? 0 : 1;
  if (IMAGE_EXTENSIONS.has(extension)) {
    if (animated) return 10;
    return source === "high_res_image" ? 30 : source === "low_res_image" ? 40 : 20;
  }
  if (extension === "svg") return 50;
  if (extension === "html") return 60;
  return 5;
}

function mediaCandidates(token, project) {
  const values = [
    ["video", token.video?.url, token.video?.extension],
    ["gif", token.gif?.url, token.gif?.extension],
    ["image", token.image?.url, token.image?.extension],
    ["preview_asset_url", token.preview_asset_url],
    ["media_url", token.media_url],
    ["primary_asset_url", token.primary_asset_url],
    ["media_proxy", `https://media-proxy.artblocks.io/${project.chain_id}/${project.contract_address}/${token.token_id}.png`],
    ["high_res_image", token.high_res_image?.url, token.high_res_image?.extension],
    ["low_res_image", token.low_res_image?.url, token.low_res_image?.extension],
    ["live_view_url", token.live_view_url],
  ];
  const seen = new Set();
  return values.flatMap(([source, value, hint], order) => {
    const url = normalizeURL(value);
    if (!url || seen.has(url)) return [];
    seen.add(url);
    const extension = extensionForURL(url) ?? hint?.toLowerCase() ?? null;
    return [{ url, source, order, extension, rank: mediaRank(extension, source) }];
  }).sort((a, b) => a.rank - b.rank || a.order - b.order);
}

function sniffExtension(buffer, mime = "") {
  if (buffer.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) return "png";
  if (buffer[0] === 255 && buffer[1] === 216 && buffer[2] === 255) return "jpg";
  if (/^GIF8[79]a/u.test(buffer.toString("ascii", 0, 6))) return "gif";
  if (buffer.toString("ascii", 0, 4) === "RIFF" && buffer.toString("ascii", 8, 12) === "WEBP") return "webp";
  if (["II*\u0000", "MM\u0000*"].includes(buffer.toString("ascii", 0, 4))) return "tiff";
  if (buffer.toString("ascii", 0, 2) === "BM") return "bmp";
  if (buffer.subarray(0, 4).equals(Buffer.from([26, 69, 223, 163]))) return "webm";
  if (buffer.toString("ascii", 4, 8) === "ftyp") {
    const brands = buffer.toString("ascii", 8, Math.min(buffer.length, buffer.readUInt32BE(0), 64));
    if (/avif|avis/u.test(brands)) return "avif";
    if (/heic|heix|hevc|hevx/u.test(brands)) return "heic";
    if (/mif1|msf1/u.test(brands)) return "heif";
    return /qt {2}/u.test(brands) ? "mov" : "mp4";
  }
  if (["moov", "mdat", "wide"].includes(buffer.toString("ascii", 4, 8)) && mime.startsWith("video/")) return "mov";
  const text = buffer.toString("utf8").replace(/^\uFEFF/u, "").trimStart();
  if (/^(?:<\?xml[^>]*>\s*)?(?:<!--[\s\S]*?-->\s*)*(?:<!DOCTYPE svg[^>]*>\s*)?<svg[\s>]/iu.test(text)) return "svg";
  if (/^(?:<!doctype html[^>]*>\s*)?<html[\s>]/iu.test(text)) return "html";
  return null;
}

async function validateMedia(file, declaredMime = "") {
  const handle = await fs.open(file, "r");
  let header;
  try {
    const buffer = Buffer.alloc(32768);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    header = buffer.subarray(0, bytesRead);
  } finally { await handle.close(); }
  const extension = sniffExtension(header, declaredMime);
  if (!extension) throw new Error("Unrecognized media contents");
  const mimeExtension = MIME_EXTENSIONS.get(declaredMime.split(";")[0].trim().toLowerCase());
  if (mimeExtension && ["svg", "html"].includes(extension) && mimeExtension !== extension) {
    throw new Error(`Response claims ${declaredMime} but contains ${extension}`);
  }
  if (["html", "svg"].includes(extension)) {
    const text = header.toString("utf8");
    if (/<(?:title|h1)[^>]*>\s*(?:error|access denied|not found|just a moment|attention required|404|500)/iu.test(text)
      || /<Code>(?:AccessDenied|NoSuchKey)<\/Code>/u.test(text)) throw new Error("Received an error document");
    return { extension, kind: extension, requiresNetwork: extension === "html" };
  }
  if (VIDEO_EXTENSIONS.has(extension)) {
    const { stdout } = await runFile("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries",
      "stream=codec_name,width,height,duration:format=duration", "-of", "json", file], { timeout: 60000 });
    const data = JSON.parse(stdout);
    const stream = data.streams?.[0];
    const duration = Number(stream?.duration ?? data.format?.duration);
    if (!(stream?.width > 0 && stream.height > 0 && duration > 0)) throw new Error("Invalid video dimensions or duration");
    return { extension, kind: "video", width: stream.width, height: stream.height, duration, codec: stream.codec_name };
  }
  const { stdout } = await runFile("magick", ["identify", "-ping", "-format", "%m %w %h %n\n", file],
    { timeout: 60000, maxBuffer: 2 * 1024 * 1024 });
  const [format, width, height, frames] = stdout.trim().split(/\s+/u);
  if (!(Number(width) > 0 && Number(height) > 0 && Number(frames) >= 1)) throw new Error("Invalid raster image");
  const animated = Number(frames) > 1 || extension === "png" && header.includes(Buffer.from("acTL"));
  return { extension, kind: animated ? "animated-image" : "image", width: Number(width), height: Number(height),
    frames: Number(frames), format };
}

async function checkSpace(context, expectedBytes = 0) {
  if (context.stopReason) throw new Error(context.stopReason);
  const stats = await fs.statfs(context.output);
  const available = stats.bavail * stats.bsize;
  if (available - expectedBytes <= context.minFreeGiB * GIB) {
    context.stopReason = `Paused for disk space: ${(available / GIB).toFixed(2)} GiB available; reserve ${context.minFreeGiB} GiB`;
    throw new Error(context.stopReason);
  }
}

async function hashFile(file) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest("hex");
}

async function downloadCandidate(context, candidate, temporary) {
  return retry(context, async () => {
    await checkSpace(context);
    let result;
    try {
      result = await response(context, candidate.url);
      const length = Number(result.headers.get("content-length")) || 0;
      await checkSpace(context, length);
      let bytes = 0;
      let lastSpaceCheck = 0;
      const hash = createHash("sha256");
      const meter = new Transform({
        transform(chunk, encoding, callback) {
          bytes += chunk.length;
          hash.update(chunk);
          if (bytes - lastSpaceCheck >= 8 * 1024 * 1024) {
            lastSpaceCheck = bytes;
            checkSpace(context).then(() => callback(null, chunk), callback);
          } else callback(null, chunk);
        },
      });
      try {
        await pipeline(Readable.fromWeb(result.body), meter, createWriteStream(temporary));
      } catch (error) { if (!context.stopReason) error.retryable = true; throw error; }
      if (!bytes || length && !result.headers.get("content-encoding") && bytes !== length) {
        throw Object.assign(new Error(`Incomplete download: ${bytes}/${length} bytes`), { retryable: true });
      }
      const contentType = result.headers.get("content-type") ?? "";
      const validation = await validateMedia(temporary, contentType);
      if (candidate.exact && validation.extension !== candidate.extension) {
        throw new Error(`Saved sample requires ${candidate.extension}, received ${validation.extension}`);
      }
      if (["html", "svg"].includes(validation.extension) && candidate.extension
        && !["html", "svg"].includes(candidate.extension)) throw new Error("Rendered media URL returned markup");
      return { source: candidate.source, sourceURL: candidate.url, resolvedURL: result.url,
        contentType, bytes, sha256: hash.digest("hex"), ...validation, verifiedAt: new Date().toISOString() };
    } catch (error) {
      if (result?.body && !result.body.locked) await result.body.cancel().catch(() => {});
      await fs.rm(temporary, { force: true });
      throw error;
    }
  });
}

async function verifiedDownload(directory, entry, deep = false) {
  if (entry.status !== "downloaded" || !entry.download?.file) return false;
  const name = entry.download.file;
  if (path.basename(name) !== name || name !== `${entry.token.token_id}.${entry.download.extension}`) return false;
  const file = path.join(directory, name);
  try {
    const stats = await fs.stat(file);
    if (stats.size !== entry.download.bytes || await hashFile(file) !== entry.download.sha256) return false;
    if (deep) await validateMedia(file, entry.download.contentType);
    return true;
  } catch { return false; }
}

async function downloadToken(context, record, entry) {
  if (await verifiedDownload(record.directory, entry)) return;
  for (const file of await fs.readdir(record.directory)) {
    const suffix = file.startsWith(`${entry.token.token_id}.`) ? file.slice(entry.token.token_id.length + 1) : "";
    if (/^\d+\.part$/u.test(suffix) || IMAGE_EXTENSIONS.has(suffix) || VIDEO_EXTENSIONS.has(suffix)
      || ["html", "svg"].includes(suffix)) {
      await fs.rm(path.join(record.directory, file), { force: true });
    }
  }
  entry.status = "pending";
  entry.failures = [];
  delete entry.download;
  const candidates = entry.reference
    ? [{ url: entry.reference.url, source: "curation", extension: entry.reference.extension, rank: 0, order: 0, exact: true }]
    : mediaCandidates(entry.token, record.manifest.project);
  for (const candidate of candidates.filter(c => !c.extension)) {
    try {
      const result = await retry(context, () => response(context, candidate.url, { method: "HEAD" }));
      candidate.extension = MIME_EXTENSIONS.get((result.headers.get("content-type") ?? "").split(";")[0].trim())
        ?? extensionForURL(result.url);
      candidate.rank = mediaRank(candidate.extension, candidate.source);
      await result.body?.cancel();
    } catch { }
  }
  candidates.sort((a, b) => a.rank - b.rank || a.order - b.order);
  let best = null;
  const temporaryFiles = [];
  try {
    for (let index = 0; index < candidates.length; index++) {
      if (context.stopReason) break;
      const candidate = candidates[index];
      if (best && candidate.rank >= best.rank) break;
      const temporary = path.join(record.directory, `${entry.token.token_id}.${index}.part`);
      temporaryFiles.push(temporary);
      try {
        const download = await downloadCandidate(context, candidate, temporary);
        const rank = mediaRank(download.extension, candidate.source, download.kind === "animated-image");
        if (!best || rank < best.rank) best = { download, temporary, rank };
      } catch (error) {
        entry.failures.push({ source: candidate.source, url: candidate.url, error: error.message,
          transient: !!error.retryable, at: new Date().toISOString() });
      }
    }
    if (best && !context.stopReason) {
      const file = `${entry.token.token_id}.${best.download.extension}`;
      await fs.rename(best.temporary, path.join(record.directory, file));
      entry.status = "downloaded";
      entry.download = { ...best.download, file };
    } else entry.status = context.stopReason ? "pending" : "failed";
  } finally {
    await Promise.all(temporaryFiles.map(file => fs.rm(file, { force: true })));
  }
}

function buildSummary(records, curation, context) {
  const stats = curationStats(curation);
  const summary = { updatedAt: new Date().toISOString(), curationCollections: stats.collections,
    excludedCollections: stats.excluded, retainedCollections: stats.retained, selectedCollections: records.length,
    group: context.group ?? "all",
    expectedFiles: 0, downloadedFiles: 0, downloadedBytes: 0, formats: {},
    completeCollections: 0, sampledCollections: 0, incompleteCollections: [], status: context.stopReason ? "paused" : "incomplete",
    stopReason: context.stopReason ?? null, selection: "first 23 minted tokens", standardRenders: true };
  for (const record of records) {
    const manifest = record.manifest;
    const expected = manifest.expectedCount ?? Math.min(SAMPLE_COUNT, Number(manifest.project.invocations));
    summary.expectedFiles += expected;
    const downloaded = manifest.tokens.filter(t => t.status === "downloaded");
    if (downloaded.length) summary.sampledCollections++;
    summary.downloadedFiles += downloaded.length;
    for (const entry of downloaded) {
      summary.downloadedBytes += entry.download.bytes;
      const format = entry.download.extension;
      summary.formats[format] = (summary.formats[format] ?? 0) + 1;
    }
    if (manifest.selectionComplete && downloaded.length === expected) summary.completeCollections++;
    else summary.incompleteCollections.push({ name: manifest.project.name, identity: manifest.identity,
      directory: path.relative(context.output, record.directory), expected, downloaded: downloaded.length,
      metadataError: manifest.metadataError, failedTokens: manifest.tokens.filter(t => t.status === "failed")
        .map(t => ({ tokenId: t.token.token_id, failures: t.failures })) });
  }
  if (!summary.incompleteCollections.length && !context.stopReason) summary.status = "complete";
  return summary;
}

async function saveSummary(context, records, curation) {
  const summary = buildSummary(records, curation, context);
  await writeJSON(path.join(context.output, "download-summary.json"), summary);
  const lines = ["# Art Blocks collection samples", "",
    `Updated: ${summary.updatedAt}`, "",
    `Status: ${summary.status}${summary.stopReason ? ` — ${summary.stopReason}` : ""}`, "",
    `Group: ${summary.group}. Collections: ${summary.sampledCollections}/${summary.selectedCollections} sampled; ${summary.completeCollections} complete; ${summary.excludedCollections} excluded by curation.`,
    `Files: ${summary.downloadedFiles}/${summary.expectedFiles}; ${(summary.downloadedBytes / GIB).toFixed(2)} GiB.`, "",
    "Selection: the exact reviewed tokens and media URLs recorded in tools/artblocks/curation.json.", "",
    "Formats: " + Object.entries(summary.formats).map(([type, count]) => `${type}: ${count}`).join(", "), "",
    "Each collection manifest records token identities, source URLs, verified files, and failed alternatives.", "",
    "## Incomplete collections", "",
    ...summary.incompleteCollections.map(p => `- ${p.name.replace(/\s+/gu, " ")} (${p.identity}): ${p.downloaded}/${p.expected}${p.metadataError ? ` — ${p.metadataError}` : ""}`), "",
  ];
  await fs.writeFile(path.join(context.output, "download-report.md"), lines.join("\n"));
  return summary;
}

async function runDownloads(context, records, inventory, selected) {
  const jobs = [];
  for (let index = 0; index < SAMPLE_COUNT; index++) {
    for (const record of selected) {
      const entry = record.manifest.tokens[index];
      if (entry) jobs.push({ record, entry });
    }
  }
  const writes = new Map();
  let summaryWrite = Promise.resolve();
  let completed = 0;
  let lastProgress = 0;
  await mapConcurrent(jobs, 6, async ({ record, entry }) => {
    if (context.stopReason) return;
    await downloadToken(context, record, entry);
    const write = (writes.get(record.file) ?? Promise.resolve()).then(() => writeJSON(record.file, record.manifest));
    writes.set(record.file, write);
    await write;
    completed++;
    if (Date.now() - lastProgress > 15000 || completed === jobs.length) {
      lastProgress = Date.now();
      const summary = buildSummary(records, inventory, context);
      console.log(`Files: ${summary.downloadedFiles}/${summary.expectedFiles}; collections: ${summary.sampledCollections} sampled, ${summary.completeCollections} complete / ${records.length}; ${(summary.downloadedBytes / GIB).toFixed(2)} GiB; processed ${completed}/${jobs.length}`);
      summaryWrite = summaryWrite.then(() => saveSummary(context, records, inventory));
      await summaryWrite;
    }
  });
  return saveSummary(context, records, inventory);
}

async function checkCuration(context, curation) {
  validateCuration(curation);
  const local = await scanGroups(context.output);
  if (local.size) {
    const captured = await captureCuration(context.output, curation);
    if (JSON.stringify(captured) !== JSON.stringify(curation)) {
      throw new Error("Local groups differ from the saved curation; inspect changes with --capture-curation");
    }
  }
  console.log(JSON.stringify({ ...curationStats(curation), localCollections: local.size,
    localStatus: local.size ? "matches" : "not present; saved decisions unchanged" }));
}

async function verifyRecords(context, records, curation) {
  let checked = 0;
  for (const record of records) {
    for (const entry of record.manifest.tokens) {
      if (context.stopReason) break;
      if (!await verifiedDownload(record.directory, entry, true)) {
        entry.status = "failed";
        entry.failures.push({ error: "Stored media is missing or failed integrity verification", at: new Date().toISOString() });
      }
    }
    checked++;
    if (checked % 100 === 0) console.log(`Verified ${checked}/${records.length} collections`);
  }
  const summary = buildSummary(records, curation, context);
  if (context.stopReason) summary.status = "paused";
  console.log(JSON.stringify(summary, null, 2));
  if (summary.status !== "complete") process.exitCode = 2;
}

async function main(argv = process.argv.slice(2)) {
  const context = { apiURL: API_URL, bundle: path.join(ROOT, "Suggested Items", "Suggested.bundle"),
    output: path.join(ROOT, "samples"), minFreeGiB: 10, maxRetries: 5, timeoutMs: 90000, stopReason: null,
    curationPath: path.join(__dirname, "artblocks", "curation.json"), group: null };
  let mode = "download";
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (["--capture-curation", "--check-curation", "--discover", "--verify-only"].includes(arg)) {
      if (mode !== "download") throw new Error("Choose only one operation");
      mode = arg.slice(2);
    } else if (["--output", "--curation", "--group"].includes(arg)) {
      const value = argv[++index];
      if (!value || value.startsWith("--")) throw new Error(`Missing value for ${arg}`);
      if (arg === "--output") context.output = path.resolve(value);
      if (arg === "--curation") context.curationPath = path.resolve(value);
      if (arg === "--group") {
        if (!GROUPS.includes(value)) throw new Error(`Group must be one of: ${GROUPS.join(", ")}`);
        context.group = value;
      }
    } else if (arg === "--help") {
      console.log(`Usage: node tools/download_artblocks_samples.js [operation] [options]

Default: restore/resume retained collections from their committed sample references.
Operations:
  --capture-curation  Save local good/ok/hmm groups and explicit deletions, offline.
  --check-curation    Validate the saved registry and compare present local groups, offline.
  --discover         Report new API projects as unreviewed; do not download or change ratings.
  --verify-only      Verify local retained samples without modifying files or downloading.
Options:
  --group good|ok|hmm Restrict download/verification to one group.
  --output directory Local samples root. Default: samples/
  --curation file    Curation JSON. Default: tools/artblocks/curation.json

Downloads use six workers, five retries and a 10 GiB free-space reserve.`);
      return;
    } else throw new Error(`Unknown option: ${arg}`);
  }
  if (context.group && !["download", "verify-only"].includes(mode)) {
    throw new Error("--group applies only to download and verification");
  }
  const curation = await readJSON(context.curationPath);
  if (mode === "capture-curation") {
    const captured = await captureCuration(context.output, curation);
    const text = `${JSON.stringify(captured, null, 2)}\n`;
    if (await fs.readFile(context.curationPath, "utf8").catch(error => {
      if (error.code === "ENOENT") return null;
      throw error;
    }) !== text) {
      await fs.mkdir(path.dirname(context.curationPath), { recursive: true });
      await writeJSON(context.curationPath, captured);
    }
    console.log(JSON.stringify(curationStats(captured)));
    return;
  }
  if (!curation) throw new Error("No curation registry; use --capture-curation after organizing local samples");
  validateCuration(curation);
  if (mode === "check-curation") return checkCuration(context, curation);
  const stop = signal => { context.stopReason = `Interrupted by ${signal}`; };
  const onInterrupt = () => stop("SIGINT");
  const onTerminate = () => stop("SIGTERM");
  process.once("SIGINT", onInterrupt);
  process.once("SIGTERM", onTerminate);
  try {
    if (mode === "discover") {
      const inventory = await discover(context);
      const decided = await historicalDecisions(context);
      const unreviewed = inventory.projects.filter(project => !curation.collections[projectIdentity(project)] && !decided.has(projectIdentity(project)));
      await fs.mkdir(context.output, { recursive: true });
      await writeJSON(path.join(context.output, "discovery.json"), { ...inventory,
        projects: unreviewed.map(project => ({ ...project, status: "unreviewed" })) });
      console.log(JSON.stringify({ apiProjects: inventory.total, alreadyBundled: inventory.excluded,
        unreviewed: unreviewed.length, report: path.join(context.output, "discovery.json") }));
      return;
    }
    const records = await resolveCuratedRecords(context, curation);
    if (mode === "verify-only") return await verifyRecords(context, records, curation);
    await fs.mkdir(context.output, { recursive: true });
    await checkSpace(context);
    await prepareCuratedRecords(records);
    const summary = await runDownloads(context, records, curation, records);
    console.log(JSON.stringify({ status: summary.status, downloaded: summary.downloadedFiles,
      expected: summary.expectedFiles, incompleteCollections: summary.incompleteCollections.length, stopReason: summary.stopReason }));
    if (summary.status !== "complete") process.exitCode = 2;
  } finally {
    process.removeListener("SIGINT", onInterrupt);
    process.removeListener("SIGTERM", onTerminate);
  }
}

module.exports = { historicalDecisions, identity, projectIdentity, folderName, bundledIdentities, retryDelay, selectTokens, graphql,
  mediaCandidates, mediaRank, sniffExtension, validateMedia, downloadCandidate, downloadToken,
  verifiedDownload, buildSummary, discover, resolveCuratedRecords, prepareCuratedRecords, main };

if (require.main === module) main().catch(error => { console.error(error.stack ?? error.message); process.exitCode = 1; });
