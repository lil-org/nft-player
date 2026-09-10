#!/usr/bin/env node
"use strict";

const fs = require("node:fs/promises");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { isDeepStrictEqual } = require("node:util");
const { Script: JavaScript } = require("node:vm");
const { graphql } = require("./download_artblocks_samples");

const ROOT = path.resolve(__dirname, "..");
const API_URL = "https://data.artblocks.io/v1/graphql";
const MAIN_CONTRACT = "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270";
const PARNASSUS_CONTRACT = "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce3676";
const DEFACEMENT_ADAPTER = 'tokenData.preferredIPFSGateway = "https://cdn.lil.org/player/instructions_for_defacement/";\ntokenData.externalAssetDependencies = [{ cid: "background.jpg" }];\n';
const DEFACEMENT_DISPLAY_TUNING = 'document.documentElement.style.height = "100%";\ndocument.body.style.minHeight = "100%";';
const PARNASSUS_DISPLAY_TUNING = `(() => {
  const style = document.createElement("style");
  style.textContent = \`
    #defaultCanvas0 {
      position: fixed !important;
      left: 50% !important;
      top: 50% !important;
      margin: 0 !important;
      width: min(100vw, 56.25vh) !important;
      height: min(100vh, calc(100vw * 16 / 9)) !important;
      transform: translate(-50%, -50%) !important;
    }
    #defaultCanvas0[style*="rotate(-90deg)"] {
      width: min(100vh, 56.25vw) !important;
      height: min(100vw, calc(100vh * 16 / 9)) !important;
      transform: translate(-50%, -50%) rotate(-90deg) !important;
    }
  \`;
  document.head.appendChild(style);
})();`;
const PROJECTS = [
  { name: "Archetype", address: MAIN_CONTRACT, projectId: "23", kind: "p5js100", count: 600 },
  { name: "Fidenza", address: MAIN_CONTRACT, projectId: "78", kind: "p5js100", count: 999 },
  { name: "Ringers", address: MAIN_CONTRACT, projectId: "13", kind: "p5js100", count: 1000 },
  { name: "Instructions for Defacement", address: "0x18de6097ce5b5b2724c9cae6ac519917f3f178c0", projectId: "0", kind: "js", count: 712,
    externalAssetCid: "bafkreibpc3wpdg4mq3bbkesqrxtoho25s3shnfhyotd6rymsag3bcfpeni" },
  { name: "Meridian", address: MAIN_CONTRACT, projectId: "163", kind: "js", count: 1000 },
  { name: "The Eternal Pump", address: MAIN_CONTRACT, projectId: "22", kind: "three", count: 50 },
  { name: "Parnassus", address: PARNASSUS_CONTRACT, projectId: "2", kind: "p5js100", count: 100,
    legacySuffix: "71f6ddfea755d56de211919de8fc87ec" },
].map(project => Object.freeze({ ...project, chainId: 1,
  apiId: `${project.address}-${project.projectId}`,
  collectionId: project.address + (project.legacySuffix ?? project.projectId),
  dependency: { p5js100: "p5@1.0.0", three: "three@0.124.0", js: "js@na" }[project.kind],
}));

const PROJECT_QUERY = `query ScriptProject($id: String!, $chain: Int!) {
  projects_metadata(where: {id: {_eq: $id}, chain_id: {_eq: $chain}}) {
    id chain_id contract_address project_id name artist_name script script_count
    script_type_and_version dependency_name_and_version external_asset_dependency_count
    external_asset_dependencies { cid dependency_type }
  }
}`;
const TOKENS_QUERY = `query ScriptTokens($project: String!, $chain: Int!, $address: String!, $ids: [String!]!, $offset: Int!) {
  tokens_metadata(where: {project_id: {_eq: $project}, chain_id: {_eq: $chain},
    contract_address: {_eq: $address}, token_id: {_in: $ids}},
    order_by: [{invocation: asc}, {id: asc}], limit: 200, offset: $offset) {
    id chain_id contract_address project_id token_id invocation hash
  }
}`;

function sha256(value) { return createHash("sha256").update(value).digest("hex"); }

async function readOptional(file) {
  try { return await fs.readFile(file, "utf8"); }
  catch (error) { if (error.code === "ENOENT") return null; throw error; }
}

function validateTokenId(id, project) {
  if (typeof id !== "string" || !/^(0|[1-9]\d*)$/u.test(id)
    || BigInt(id) / 1000000n !== BigInt(project.projectId)) {
    throw new Error(`Wrong project or invalid token ID in ${project.name}: ${id}`);
  }
}

function expandManifest(manifest, project) {
  if (!Array.isArray(manifest.items) || manifest.items.length !== project.count) {
    throw new Error(`${project.name}: expected ${project.count} existing tokens, found ${manifest.items?.length}`);
  }
  const seen = new Set();
  return manifest.items.map(item => {
    let expanded;
    if (Array.isArray(item)) {
      if (item.length !== 3 || !Number.isInteger(item[1]) || typeof item[2] !== "string") {
        throw new Error(`Invalid compact token in ${project.name}`);
      }
      const prefix = manifest.urlPrefixes?.[item[1]];
      if (prefix != null && typeof prefix !== "string") throw new Error(`Invalid URL prefix in ${project.name}`);
      expanded = { id: item[0], url: (prefix ?? "") + item[2] };
    } else if (item && typeof item === "object") expanded = { ...item };
    else throw new Error(`Invalid token row in ${project.name}`);
    validateTokenId(expanded.id, project);
    if (seen.has(expanded.id)) throw new Error(`Duplicate bundled token in ${project.name}: ${expanded.id}`);
    seen.add(expanded.id);
    if (typeof expanded.url !== "string" || !expanded.url.startsWith("https://cdn.lil.org/")) {
      throw new Error(`Missing existing CDN URL in ${project.name}: ${expanded.id}`);
    }
    return expanded;
  });
}

function validateProject(project, source) {
  if (!source || source.id !== project.apiId || source.chain_id !== project.chainId
    || source.contract_address?.toLowerCase() !== project.address || source.project_id !== project.projectId) {
    throw new Error(`API project identity mismatch for ${project.name}`);
  }
  if (source.name !== project.name) throw new Error(`API project name changed for ${project.name}: ${source.name}`);
  if (typeof source.script !== "string" || !source.script.trim() || !Number.isInteger(source.script_count) || source.script_count < 1) {
    throw new Error(`Missing complete artist script for ${project.name}`);
  }
  const dependency = source.dependency_name_and_version || source.script_type_and_version;
  if (dependency !== project.dependency) throw new Error(`Unsupported dependency for ${project.name}: ${dependency}`);
  const assets = source.external_asset_dependencies;
  if (!Array.isArray(assets) || source.external_asset_dependency_count !== assets.length
    || (project.externalAssetCid ? assets.length !== 1 || assets[0].cid !== project.externalAssetCid || assets[0].dependency_type !== "IPFS" : assets.length !== 0)) {
    throw new Error(`Unexpected external asset dependencies for ${project.name}`);
  }
  new JavaScript(source.script, { filename: project.name });
}

function validateHashes(project, ids, tokens) {
  const expected = new Set(ids);
  const hashes = new Map();
  for (const token of tokens) {
    validateTokenId(token.token_id, project);
    if (token.chain_id !== project.chainId || token.contract_address?.toLowerCase() !== project.address
      || token.project_id !== project.apiId || token.id !== `${project.address}-${token.token_id}`
      || token.invocation !== Number(BigInt(token.token_id) % 1000000n)) {
      throw new Error(`API token identity mismatch in ${project.name}: ${token.token_id}`);
    }
    if (!expected.has(token.token_id)) throw new Error(`Unexpected API token in ${project.name}: ${token.token_id}`);
    if (hashes.has(token.token_id)) throw new Error(`Duplicate API token in ${project.name}: ${token.token_id}`);
    if (typeof token.hash !== "string" || !/^0x[0-9a-fA-F]{64}$/u.test(token.hash)) {
      throw new Error(`Invalid token hash in ${project.name}: ${token.token_id}`);
    }
    hashes.set(token.token_id, token.hash);
  }
  const missing = ids.filter(id => !hashes.has(id));
  if (missing.length) throw new Error(`Missing API token hashes in ${project.name}: ${missing.join(", ")}`);
  return hashes;
}

async function fetchProject(project, ids, request) {
  const data = await request(PROJECT_QUERY, { id: project.apiId, chain: project.chainId });
  if (data.projects_metadata?.length !== 1) throw new Error(`Expected one API project for ${project.name}`);
  const source = data.projects_metadata[0];
  validateProject(project, source);
  const tokens = [];
  for (let offset = 0; ; offset += 200) {
    const page = await request(TOKENS_QUERY, { project: project.apiId, chain: project.chainId,
      address: project.address, ids, offset });
    if (!Array.isArray(page.tokens_metadata) || page.tokens_metadata.length > 200) throw new Error(`Invalid API token page for ${project.name}`);
    tokens.push(...page.tokens_metadata);
    if (tokens.length > ids.length) throw new Error(`Duplicate or unexpected API token page for ${project.name}`);
    if (page.tokens_metadata.length < 200) break;
  }
  return { source, hashes: validateHashes(project, ids, tokens) };
}

function createScript(project, source) {
  const script = { abId: project.projectId, address: project.address, chain: "ethereum",
    kind: project.kind, name: project.name,
    value: (project.externalAssetCid ? DEFACEMENT_ADAPTER : "") + source.script };
  if (project.legacySuffix) {
    script.collectionIdOverride = project.collectionId;
    script.nftPlayerDisplayTuning = PARNASSUS_DISPLAY_TUNING;
  }
  if (project.externalAssetCid) script.nftPlayerDisplayTuning = DEFACEMENT_DISPLAY_TUNING;
  new JavaScript(script.value, { filename: project.name });
  return script;
}

function catalogObjectSpans(text) {
  const spans = [];
  let depth = 0, start = -1, quoted = false, escaped = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (escaped) escaped = false;
      else if (c === "\\") escaped = true;
      else if (c === '"') quoted = false;
    } else if (c === '"') quoted = true;
    else if (c === "[") depth++;
    else if (c === "]") depth--;
    else if (c === "{") { if (depth === 1) start = i; depth++; }
    else if (c === "}") { depth--; if (depth === 1) spans.push([start, i + 1]); }
  }
  return spans;
}

function convertCatalog(text, projects) {
  const catalog = JSON.parse(text);
  if (!Array.isArray(catalog)) throw new Error("The bundled catalog is not an array");
  const spans = catalogObjectSpans(text);
  if (spans.length !== catalog.length) throw new Error("Cannot locate catalog entries");
  const selected = new Map();
  for (const project of projects) {
    const matches = catalog.flatMap((entry, index) => entry.address?.toLowerCase() === project.address
      && (project.legacySuffix ? entry.collectionId === project.legacySuffix && entry.abId == null : entry.abId === project.projectId) ? [index] : []);
    if (matches.length !== 1) throw new Error(`Expected one bundled catalog entry for ${project.name}`);
    const index = matches[0], entry = catalog[index];
    if (entry.name !== project.name || entry.chainId !== project.chainId || entry.chain !== "ethereum"
      || (entry.tokenCount != null && entry.tokenCount !== project.count)) {
      throw new Error(`Bundled catalog metadata mismatch for ${project.name}`);
    }
    if (selected.has(index)) throw new Error(`Duplicate project mapping for ${project.name}`);
    selected.set(index, project);
  }
  let result = text;
  for (const [index] of [...selected].sort((a, b) => b[0] - a[0])) {
    if (catalog[index].tokenCount == null) continue;
    const [start, end] = spans[index];
    const original = text.slice(start, end);
    let edited = original.replace(/^[ \t]*"tokenCount"\s*:\s*\d+,[ \t]*\r?\n/mu, "");
    if (edited === original) edited = original.replace(/"tokenCount"\s*:\s*\d+\s*,/u, "");
    if (edited === original) edited = original.replace(/,\s*"tokenCount"\s*:\s*\d+(?=\s*\})/u, "");
    if (edited === original) throw new Error(`Cannot remove catalog tokenCount for ${catalog[index].name}`);
    result = result.slice(0, start) + edited + result.slice(end);
    delete catalog[index].tokenCount;
  }
  if (!isDeepStrictEqual(JSON.parse(result), catalog)) throw new Error("Unexpected catalog modification");
  return result;
}

async function planBundle(options = {}) {
  const bundle = path.resolve(options.bundle ?? path.join(ROOT, "Suggested Items", "Suggested.bundle"));
  const projects = options.projects ?? PROJECTS;
  const apiURL = options.apiURL ?? API_URL;
  const context = { apiURL, maxRetries: 5, timeoutMs: 45000 };
  const request = options.request ?? ((query, variables) => graphql(context, query, variables));
  const catalogPath = path.join(bundle, "items.json");
  const catalogBefore = await fs.readFile(catalogPath, "utf8");
  const catalogAfter = convertCatalog(catalogBefore, projects);
  const inputs = await Promise.all(projects.map(async project => {
    const tokenPath = path.join(bundle, "Tokens", `${project.collectionId}.json`);
    const scriptPath = path.join(bundle, "Scripts", `${project.collectionId}.json`);
    const [tokensBefore, scriptBefore] = await Promise.all([fs.readFile(tokenPath, "utf8"), readOptional(scriptPath)]);
    const manifest = JSON.parse(tokensBefore);
    const items = expandManifest(manifest, project);
    return { project, tokenPath, scriptPath, tokensBefore, scriptBefore, manifest, items };
  }));
  let next = 0;
  const results = new Array(inputs.length);
  await Promise.all(Array.from({ length: Math.min(2, inputs.length) }, async () => {
    while (next < inputs.length) {
      const index = next++;
      const input = inputs[index], { project, items } = input;
      const ids = items.map(item => item.id);
      const { source, hashes } = await fetchProject(project, ids, request);
      const tokenManifest = { ...input.manifest, items: items.map(item => {
        if (item.hash != null && item.hash !== hashes.get(item.id)) throw new Error(`Existing hash changed in ${project.name}: ${item.id}`);
        return { ...item, hash: hashes.get(item.id) };
      }) };
      delete tokenManifest.urlPrefixes;
      const script = createScript(project, source);
      results[index] = { ...input, source, tokenManifest, script };
    }
  }));
  const files = [{ file: catalogPath, before: catalogBefore, after: catalogAfter }];
  const report = { version: 1, apiURL, collections: [], tokenCount: 0 };
  for (const result of results) {
    const { project, source, tokenManifest, script } = result;
    const tokensAfter = JSON.stringify(tokenManifest) + (result.tokensBefore.endsWith("\n") ? "\n" : "");
    const scriptAfter = `${JSON.stringify(script, null, 2)}\n`;
    files.push({ file: result.tokenPath, before: result.tokensBefore, after: tokensAfter },
      { file: result.scriptPath, before: result.scriptBefore, after: scriptAfter });
    report.tokenCount += tokenManifest.items.length;
    report.collections.push({ name: project.name, apiProjectId: project.apiId, chainId: project.chainId,
      collectionId: project.collectionId, artist: source.artist_name, kind: project.kind,
      dependency: project.dependency, tokenCount: tokenManifest.items.length,
      scriptCount: source.script_count, sourceScriptBytes: Buffer.byteLength(source.script),
      sourceScriptSHA256: sha256(source.script), bundledScriptSHA256: sha256(script.value),
      tokenIdsSHA256: sha256(JSON.stringify(tokenManifest.items.map(item => item.id))),
      tokenHashesSHA256: sha256(JSON.stringify(tokenManifest.items.map(item => [item.id, item.hash]))),
      externalAssets: project.externalAssetCid ? ["https://cdn.lil.org/player/instructions_for_defacement/background.jpg"] : [] });
  }
  return { bundle, files, report };
}

async function writeAtomic(file, content) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  const temporary = `${file}.${process.pid}.tmp`;
  try { await fs.writeFile(temporary, content); await fs.rename(temporary, file); }
  finally { await fs.rm(temporary, { force: true }); }
}

async function applyPlan(plan, reportPath) {
  for (const file of plan.files) {
    if (await readOptional(file.file) !== file.before) throw new Error(`Bundle changed during validation: ${file.file}`);
  }
  const changed = plan.files.filter(file => file.before !== file.after);
  for (const file of changed) await writeAtomic(file.file, file.after);
  if (reportPath) {
    const report = `${JSON.stringify(plan.report, null, 2)}\n`;
    if (await readOptional(reportPath) !== report) await writeAtomic(reportPath, report);
  }
  return changed.map(file => file.file);
}

function parseArgs(args) {
  const options = { apply: false, report: path.join(ROOT, "tools", "reports", "artblocks-script-bundle.json") };
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--apply") options.apply = true;
    else if (arg === "--dry-run") options.apply = false;
    else if (arg === "--help" || arg === "-h") options.help = true;
    else if (["--bundle", "--api-url", "--report"].includes(arg)) {
      const value = args[++i];
      if (!value || value.startsWith("--")) throw new Error(`Missing value for ${arg}`);
      options[{ "--bundle": "bundle", "--api-url": "apiURL", "--report": "report" }[arg]] = value;
    } else throw new Error(`Unknown option: ${arg}`);
  }
  return options;
}

async function main(args = process.argv.slice(2), dependencies = {}) {
  const options = parseArgs(args);
  const log = dependencies.log ?? console.log;
  if (options.help) {
    log("Usage: node tools/bundle_artblocks_scripts.js [--dry-run|--apply] [--bundle PATH] [--api-url URL] [--report PATH]\nDefaults to fetching and validating without writing. Apply converts only the seven explicit mapped collections.");
    return;
  }
  const plan = await planBundle({ ...options, ...dependencies });
  const changed = options.apply ? await applyPlan(plan, path.resolve(options.report)) : plan.files.filter(file => file.before !== file.after).map(file => file.file);
  for (const entry of plan.report.collections) log(`${entry.name}: ${entry.tokenCount} tokens, ${entry.sourceScriptBytes} script bytes, SHA-256 ${entry.sourceScriptSHA256}`);
  log(`${options.apply ? "Applied" : "Dry run"}: ${plan.report.collections.length} collections, ${plan.report.tokenCount} tokens, ${changed.length} changed files.`);
  return { plan, changed };
}

module.exports = { PROJECTS, DEFACEMENT_ADAPTER, DEFACEMENT_DISPLAY_TUNING, PARNASSUS_DISPLAY_TUNING, expandManifest,
  validateProject, validateHashes, createScript, convertCatalog, planBundle, applyPlan, parseArgs, main };

if (require.main === module) main().catch(error => { console.error(error.stack ?? error.message); process.exitCode = 1; });
