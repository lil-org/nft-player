#!/usr/bin/env node
"use strict";

const fs = require("node:fs/promises");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { Script: JavaScript } = require("node:vm");
const { spawnSync } = require("node:child_process");
const { graphql } = require("./download_artblocks_samples");
const { validateHashes } = require("./bundle_artblocks_scripts");
const { validateCuration } = require("./artblocks/curation");

const ROOT = path.resolve(__dirname, "..");
const API_URL = "https://data.artblocks.io/v1/graphql";
const DEFAULT_OUTPUT = path.join(ROOT, "build", "artblocks-historical-review", "Good");
const DEFAULT_CURATION = path.join(ROOT, "tools", "artblocks", "reviews", "pass-1-curation.json");
const DEFAULT_COMPATIBILITY = path.join(ROOT, "tools", "artblocks", "review-compatibility.json");
const DEFAULT_PARAMETERS = path.join(ROOT, "tools", "artblocks", "review-contract-parameters.json");
const DEPENDENCIES = Object.freeze({
  "p5@1.0.0": "p5js100", "p5@1.9.0": "p5js190", "p5@1.11.11": "p5js11111", "js@na": "js", "svg@na": "svg",
  "three@0.124.0": "three", "paper@0.12.15": "paper", "processing-js@1.4.6": "processingjs146",
  "three@0.160.0": "three160", "three@0.167.0": "three167", "babylon@5.0.0": "babylon500",
  "regl@2.1.0": "regl", "tone@14.8.15": "tone", "tone@15.0.4": "tone1504",
});
const EMPTY_BODY_PROJECTS = new Map([
  ["42161:0x47a91457a3a1f700097199fd63c039c4784384ab:3", "Afterimage"],
  ["42161:0x47a91457a3a1f700097199fd63c039c4784384ab:80", "Autopoiesis "],
]);
const GENESIS = "1:0x059edd72cd353df5106d2b9cc5ab83a52287ac3a:1";
const PROCESSING_PROJECTS = new Map([[GENESIS, "Genesis"], ["1:0x059edd72cd353df5106d2b9cc5ab83a52287ac3a:2", "Construction Token"]]);
const NULL_JS_PROJECTS = new Map([
  ...EMPTY_BODY_PROJECTS,
  ["1:0x00000007cc35dcab4a396249aefa295a8b6e16ba:5", "Jankpop"],
  ["42161:0x47a91457a3a1f700097199fd63c039c4784384ab:75", "striation"],
  ["42161:0x47a91457a3a1f700097199fd63c039c4784384ab:82", "Delights"],
]);
const HTML_PROJECTS = new Map([
  ["1:0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270:136", { name: "SpiroFlakes", dependency: "custom@na" }],
  ["1:0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270:195", { name: "Paramecircle", dependency: "custom@na" }],
  ["42161:0x47a91457a3a1f700097199fd63c039c4784384ab:39", { name: "Shooting Serenade", dependency: "p5@1.0.0" }],
]);
const MODULE_PROJECT = "1:0x96a83b48de94e130cf2aa81b28391c28ee33d253:9";
const TRANSFORMATIONS = "1:0x000000b394cac6057d87df835bea27844b3e2828:0";
const LYCORISES = "1:0x1353fd9d3dc70d1a18149c8fb2adb4fb906de4e8:4";
const SECONDARY_DEPENDENCY_PROFILES = new Map([
  ["1:0x7c3ea2b7b3befa1115ab51c09f0c9f245c500b18:7", {
    name: "INFINITE | 無限", kind: "js", profile: "infinite", additionalLibraries: ["ort1140", "p5js160"],
    requiresInitialCanvas: false, sourceReferences: [
      "Qme4ecY56Lo6aooP3vpZR2Pv6HrEGApqurkqfWGZPknBXJ/ort.min.js",
      "QmSkuz26ut6v4SUMG8PFvHPfNoHwUaVz6JFuBzqZ54RcNB/p5.min.js",
      "QmbCoDK981VBunhucbW2kbkiqN2wg7GWZDDztq4nnrqrTi/",
      "QmbGmTZpw1byJzYKvtt9WnJtyXFX8ZCa6EwLzfhXDEDrKP/",
      "mobilestylegan_ffhq_v2-map.onnx", "mobilestylegan_ffhq_v2-synth.onnx",
    ],
  }],
  ["1:0x7c3ea2b7b3befa1115ab51c09f0c9f245c500b18:11", {
    name: "Time after vessels", kind: "js", profile: "timeAfterVessels", additionalLibraries: ["ort1140", "seedrandom305"],
    requiresInitialCanvas: false, sourceReferences: [
      "QmdtN6MqV6KEm3XFT3SYmBBUb1zeDrmPZGpRwd9Z3iKmFh", "seedrandom.min.js", "ort.min.js",
      "sc-bm1.onnx", "sc-bm2.onnx", "sc-bm3.onnx",
    ],
  }],
  ["1:0x7c3ea2b7b3befa1115ab51c09f0c9f245c500b18:1", {
    name: "Spongenuity's Portrait Lab", kind: "p5js100", profile: "spongenuity", additionalLibraries: ["p5svg"],
    sourceReferences: ["QmU28NZxGoJ7dTWdJPj2Y52aBVpDcCt12AWiRBZDGkPbem", "QmUuKkbMptQBmivcUDbzs7V8v3RqKkHFtJm53RvqtP8aPz/"],
  }],
  ["42161:0x47a91457a3a1f700097199fd63c039c4784384ab:211", {
    name: "The Tallest Poppy", kind: "p5js100", profile: "tallestPoppy", additionalLibraries: ["three155"],
    sourceReferences: ["/model.js", "/three.min.js", "/draco/", "ttpmodel"],
    externalAssetCID: "bafybeieocnugxnd6lwozwzi3s6t6drqi7ycxkbrwplh3uiwmdoykd4fodq",
  }],
]);
const PINATA = "1:0xa73300003e020c436a67809e9300301600013000:0";
const PINATA_CID = "9xF_r6tV6Tvq8dewxprR-pb1O8a8XuHONypLFudo6oY";
const PINATA_ADAPTER = `tokenData.externalAssetDependencies = [{ cid: "${PINATA_CID}", dependency_type: "ARWEAVE" }];
tokenData.preferredArweaveGateway = "https://arweave.net/";
tokenData.preferredIPFSGateway = "https://ipfs.io/ipfs/";
(() => {
  const failed = new WeakSet();
  const loadImage = p5.prototype.loadImage;
  p5.prototype.loadImage = function (url, success, failure) {
    const instance = this;
    const report = () => {
      failed.add(instance);
      showPreviewError("Could not load this artwork's image assets.");
    };
    const timer = setTimeout(report, 60000);
    try {
      return loadImage.call(instance, url, function () {
        clearTimeout(timer);
        if (typeof success === "function") success.apply(this, arguments);
      }, function () {
        clearTimeout(timer);
        report();
        if (typeof failure === "function") failure.apply(this, arguments);
      });
    } catch (error) {
      clearTimeout(timer);
      report();
      throw error;
    }
  };
  p5.prototype.registerMethod("beforeSetup", function () {
    if (failed.has(this)) {
      this.draw = function () {};
      this.setup = function () {
        this.noLoop();
        this.noCanvas();
        showPreviewError("Could not load this artwork's image assets.");
      };
    }
  });
})();
`;

const PROJECT_QUERY = `query GoodPreviewProject($id: String!, $chain: Int!) {
  projects_metadata(where: {id: {_eq: $id}, chain_id: {_eq: $chain}}) {
    id chain_id contract_address project_id name artist_name aspect_ratio script script_count
    script_type_and_version dependency_name_and_version external_asset_dependency_count
    external_asset_dependencies(order_by: {index: asc}) { index cid dependency_type data bytecode_address }
  }
}`;
const TOKENS_QUERY = `query GoodPreviewTokens($project: String!, $chain: Int!, $address: String!, $ids: [String!]!) {
  tokens_metadata(where: {project_id: {_eq: $project}, chain_id: {_eq: $chain},
    contract_address: {_eq: $address}, token_id: {_in: $ids}},
    order_by: [{invocation: asc}, {id: asc}], limit: 24) {
    id chain_id contract_address project_id token_id invocation hash
    image { url extension metadata }
  }
}`;

function sha256(value) { return createHash("sha256").update(value).digest("hex"); }
function json(value) { return JSON.stringify(value, null, 2) + "\n"; }

function selectProjects(registry) {
  validateCuration(registry);
  const collator = new Intl.Collator("en-US", { sensitivity: "base", numeric: true });
  const projects = Object.entries(registry.collections).filter(([, entry]) => ["good", "ok", "hmm"].includes(entry.group)).map(([key, entry]) => {
    const [chain, address, projectId] = key.split(":");
    const chainId = Number(chain), suffix = `-dev-good-${chainId}-${projectId}`;
    if (![1, 8453, 42161].includes(chainId)) throw new Error(`Unsupported preview chain: ${key}`);
    if (!entry.name.trim() || !entry.samples.length) throw new Error(`Empty preview collection: ${key}`);
    return { key, chainId, address, projectId, name: entry.name, artist: entry.artist, group: entry.group,
      suffix, collectionId: address + suffix, apiId: `${address}-${projectId}`,
      tokenIds: entry.samples.map(sample => sample.tokenId) };
  });
  if (!projects.length) throw new Error("Curation has no retained collections to preview");
  projects.sort((a, b) => collator.compare(a.name, b.name) || a.key.localeCompare(b.key, "en-US"));
  return projects;
}

function aspectRatio(value) {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0 || value > 100) {
    throw new Error(`Invalid project aspect ratio: ${value}`);
  }
  let remainder = value, n0 = 0, d0 = 1, n1 = 1, d1 = 0;
  for (let step = 0; step < 32; step++) {
    const whole = Math.floor(remainder), n = whole * n1 + n0, d = whole * d1 + d0;
    if (d > 1000000 || !Number.isSafeInteger(n)) break;
    [n0, d0, n1, d1] = [n1, d1, n, d];
    if (Math.abs(value - n / d) <= 1e-8 || remainder === whole) break;
    remainder = 1 / (remainder - whole);
  }
  if (n1 <= 0 || d1 <= 0 || Math.abs(value - n1 / d1) > 1e-6) throw new Error(`Cannot represent aspect ratio: ${value}`);
  return [n1, d1];
}

function validateCompatibility(value) {
  if (value?.version !== 1 || !value.staticFirst || typeof value.staticFirst !== "object" || Array.isArray(value.staticFirst)) {
    throw new Error("Invalid review compatibility manifest");
  }
  for (const [identity, entry] of Object.entries(value.staticFirst)) {
    if (!/^(1|8453|42161):0x[0-9a-f]{40}:(0|[1-9][0-9]*)$/u.test(identity)
      || typeof entry.name !== "string" || !entry.name.trim() || typeof entry.reason !== "string" || !entry.reason.trim()
      || entry.expectedDependency?.dependency_type !== "ONCHAIN" || entry.expectedDependency.data !== "#web3call_contract#"
      || !/^0x[0-9a-f]{40}$/u.test(entry.expectedDependency.bytecode_address)) {
      throw new Error(`Invalid review compatibility entry: ${identity}`);
    }
  }
  return value;
}

function object(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function timestamp(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}T/u.test(value) && Number.isFinite(Date.parse(value));
}

function validateRequiredContractParameters(identity, parameters, label) {
  if (identity === "1:0x00000053a75735169ad44f6760c11f3d3d3b3544:0") {
    const blockHeight = Number(parameters.blockHeight), invocations = Number(parameters.projectInvocations);
    if (!/^\d+$/u.test(parameters.blockHeight ?? "") || !Number.isSafeInteger(blockHeight)
      || !/^\d+$/u.test(parameters.projectInvocations ?? "") || !Number.isSafeInteger(invocations) || invocations < 1) {
      throw new Error(`Incomplete frozen block parameters: ${label}`);
    }
  }
  if (identity === "1:0x000000dc68934ed27fd11e32491cdf6717acaf21:1") {
    const blockTimestamp = Number(parameters.blockTimestamp);
    if (!Number.isFinite(blockTimestamp) || blockTimestamp <= 1e9) {
      throw new Error(`Missing frozen block timestamp: ${label}`);
    }
  }
  if (identity === "1:0xcfa6a2d5bc2a77c0cdd3046e09da21e45d1df0f1:1") {
    const keys = Object.keys(parameters).filter(key => /^p\d+$/u.test(key)).sort((a, b) => Number(a.slice(1)) - Number(b.slice(1)));
    if (!keys.length || keys.some((key, index) => key !== `p${index}`)
      || !/^\d+$/u.test(parameters.week ?? "") || Number(parameters.week) < 1 || Number(parameters.week) > 52
      || !/^\d+$/u.test(parameters.chaos ?? "") || Number(parameters.chaos) > 100) {
      throw new Error(`Invalid frozen drawing parameters: ${label}`);
    }
    const chunks = keys.map(key => {
      const value = parameters[key];
      if (!value || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u.test(value)) {
        throw new Error(`Invalid frozen drawing base64: ${label}`);
      }
      const bytes = Buffer.from(value, "base64");
      if (bytes.toString("base64") !== value) throw new Error(`Invalid frozen drawing base64: ${label}`);
      return bytes;
    });
    const drawing = Buffer.concat(chunks);
    const strokes = drawing.length >= 4 ? drawing.readUInt16BE(2) : 0;
    if (strokes < 1 || drawing.length !== Math.ceil((32 + 162 * strokes) / 8)) {
      throw new Error(`Incomplete frozen drawing: ${label}`);
    }
  }
  if (identity === "1:0xaa00b2b2db36b8f8004a9aa96f0012005d92b300:0") {
    const count = Number(parameters.priceHistoryLength);
    const keys = Object.keys(parameters).filter(key => /^priceHistory\d+$/u.test(key)).sort((a, b) => Number(a.slice(12)) - Number(b.slice(12)));
    if (!parameters.tokenSymbol?.trim() || !/^\d+$/u.test(parameters.priceHistoryLength ?? "") || !Number.isSafeInteger(count) || count < 1
      || keys.length < count || keys.some((key, index) => key !== `priceHistory${index}` || !/^\d+$/u.test(parameters[key]))) {
      throw new Error(`Incomplete frozen price history: ${label}`);
    }
  }
}

function validateContractParameterSnapshot(snapshot, projects, compatibility) {
  if (!object(snapshot) || snapshot.version !== 1 || snapshot.source !== "https://generator.artblocks.io"
    || !timestamp(snapshot.capturedAt) || !object(snapshot.collections)) throw new Error("Invalid contract parameter snapshot");
  const projectsByIdentity = new Map(projects.map(project => [project.key, project]));
  for (const [identity, collection] of Object.entries(snapshot.collections)) {
    const project = projectsByIdentity.get(identity), expected = compatibility.staticFirst[identity];
    if (!project || !expected || !object(collection) || collection.name !== project.name
      || collection.name !== expected.name || !/^[0-9a-f]{64}$/u.test(collection.sourceScriptSHA256 ?? "")
      || collection.dependency?.index !== 0 || collection.dependency.dependency_type !== "ONCHAIN"
      || collection.dependency.bytecode_address !== expected.expectedDependency.bytecode_address
      || !object(collection.tokens)) throw new Error(`Invalid contract parameter collection: ${identity}`);
    const tokenIDs = Object.keys(collection.tokens);
    if (tokenIDs.length !== project.tokenIds.length || !project.tokenIds.every(id => Object.hasOwn(collection.tokens, id))) {
      throw new Error(`Incomplete contract parameter token coverage: ${project.name}`);
    }
    for (const [id, token] of Object.entries(collection.tokens)) {
      let sourceURL;
      try { sourceURL = new URL(token?.sourceURL); } catch { throw new Error(`Invalid parameter source URL: ${project.name} #${id}`); }
      if (!object(token) || !/^0x[0-9a-f]{64}$/iu.test(token.hash ?? "") || !timestamp(token.fetchedAt)
        || !object(token.parameters) || Object.values(token.parameters).some(value => typeof value !== "string")
        || sourceURL.origin !== snapshot.source || sourceURL.username || sourceURL.password
        || token.sourceURL !== `${snapshot.source}/${project.chainId}/${project.address}/${id}`) {
        throw new Error(`Invalid contract parameters: ${project.name} #${id}`);
      }
      validateRequiredContractParameters(identity, token.parameters, `${project.name} #${id}`);
    }
  }
  return snapshot;
}

async function readContractParameters(options, projects, compatibility) {
  if (options.parameterSnapshot === null) return null;
  let text;
  if (options.parameterSnapshot !== undefined) text = json(options.parameterSnapshot);
  else {
    try { text = await fs.readFile(options.parameters ?? DEFAULT_PARAMETERS, "utf8"); }
    catch (error) {
      if (error.code === "ENOENT" && options.parameters === undefined) return null;
      throw error;
    }
  }
  const snapshot = validateContractParameterSnapshot(JSON.parse(text), projects, compatibility);
  return { snapshot, text };
}

function applyContractParameterSnapshot(plan, projects, compatibility, input) {
  const catalog = JSON.parse(plan.files.get("items.json"));
  const report = JSON.parse(plan.files.get("provenance.json"));
  if (!Array.isArray(catalog) || catalog.length !== projects.length || report.collections?.length !== projects.length) {
    throw new Error("Existing preview catalog or provenance is incomplete");
  }
  const snapshot = input?.snapshot;
  let frozenCollectionCount = 0, frozenTokenCount = 0;
  for (const [index, project] of projects.entries()) {
    const item = catalog[index], provenance = report.collections[index];
    if (item.reviewIdentity !== project.key || item.name !== project.name || item.address + item.collectionId !== project.collectionId
      || provenance.identity !== project.key || provenance.collectionId !== project.collectionId) {
      throw new Error(`Existing preview identity mismatch: ${project.name}`);
    }
    const frozen = snapshot?.collections[project.key];
    const tokenPath = path.join("Tokens", `${project.collectionId}.json`);
    const tokenText = plan.files.get(tokenPath);
    const tokens = JSON.parse(tokenText ?? "null");
    if (!Array.isArray(tokens?.items) || tokens.items.length !== project.tokenIds.length
      || tokens.items.some((token, index) => token.id !== project.tokenIds[index])) {
      throw new Error(`Existing preview token order mismatch: ${project.name}`);
    }
    if (frozen) {
      const script = JSON.parse(plan.files.get(path.join("Scripts", `${project.collectionId}.json`)) ?? "null");
      const dependency = script?.externalAssetDependencies;
      if (script?.isDevelopmentPreview !== true || script.collectionIdOverride !== project.collectionId || script.name !== project.name || typeof script.value !== "string"
        || sha256(script.value) !== frozen.sourceScriptSHA256 || provenance.sourceScriptSHA256 !== frozen.sourceScriptSHA256
        || dependency?.length !== 1 || dependency[0].index !== 0 || dependency[0].dependency_type !== "ONCHAIN"
        || dependency[0].bytecode_address !== frozen.dependency.bytecode_address
        || provenance.externalAssets?.length !== 1 || provenance.externalAssets[0].data !== "#web3call_contract#") {
        throw new Error(`Contract parameter source or dependency mismatch: ${project.name}`);
      }
      for (const token of tokens.items) {
        const captured = frozen.tokens[token.id];
        if (captured.hash !== token.hash) throw new Error(`Contract parameter token hash mismatch: ${project.name} #${token.id}`);
        token.previewContractParameters = Object.fromEntries(Object.entries(captured.parameters).sort(([a], [b]) => a.localeCompare(b, "en")));
      }
      frozenCollectionCount++;
      frozenTokenCount += tokens.items.length;
      delete item.previewStaticReason;
      delete provenance.staticReason;
      provenance.contractParametersSHA256 = sha256(JSON.stringify(tokens.items.map(({ id, hash, previewContractParameters }) => ({ id, hash, parameters: previewContractParameters }))));
      provenance.contractParameterTokenCount = tokens.items.length;
    } else {
      for (const token of tokens.items) delete token.previewContractParameters;
      if (compatibility.staticFirst[project.key]) {
        item.previewStaticReason = compatibility.staticFirst[project.key].reason;
        provenance.staticReason = compatibility.staticFirst[project.key].reason;
      }
      delete provenance.contractParametersSHA256;
      delete provenance.contractParameterTokenCount;
    }
    const encoded = json(tokens);
    if (encoded !== tokenText) plan.files.set(tokenPath, encoded);
  }
  report.staticFirstCount = catalog.filter(item => item.previewStaticReason != null).length;
  if (input) report.contractParameters = { version: 1, source: snapshot.source, capturedAt: snapshot.capturedAt,
    snapshotSHA256: sha256(input.text), collectionCount: frozenCollectionCount, tokenCount: frozenTokenCount };
  else delete report.contractParameters;
  plan.files.set("provenance.json", json(report));
  plan.files.delete("items.json");
  plan.files.set("items.json", json(catalog));
  plan.report = report;
  return plan;
}

function validateJavaScript(value, name, isModule = false) {
  if (!isModule) { new JavaScript(value, { filename: name }); return; }
  const result = spawnSync(process.execPath, ["--input-type=module", "--check"], { input: value, encoding: "utf8" });
  if (result.error || result.status !== 0) throw new Error(`Invalid module source for ${name}: ${result.error?.message ?? result.stderr}`);
}

function validateHTML(value, name) {
  let count = 0;
  for (const match of value.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/giu)) {
    if (/\bsrc\s*=/iu.test(match[1])) continue;
    validateJavaScript(match[2], name, /\btype\s*=\s*["']module["']/iu.test(match[1]));
    count++;
  }
  if (!count) throw new Error(`Missing inline artwork script in ${name}`);
}

function validateAssets(project, source, compatibility) {
  const assets = source.external_asset_dependencies, entry = compatibility.staticFirst[project.key];
  if (!Array.isArray(assets) || source.external_asset_dependency_count !== assets.length) {
    throw new Error(`Unexpected external assets: ${project.name}`);
  }
  const ordered = [...assets].sort((a, b) => a.index - b.index);
  for (const [index, asset] of ordered.entries()) {
    if (asset.index !== index || !["IPFS", "ARWEAVE", "ONCHAIN", "ART_BLOCKS_DEPENDENCY_REGISTRY"].includes(asset.dependency_type)
      || typeof asset.cid !== "string" || (asset.data != null && typeof asset.data !== "string")
      || (asset.bytecode_address != null && !/^0x[0-9a-f]{40}$/iu.test(asset.bytecode_address))) {
      throw new Error(`Invalid external asset metadata: ${project.name}`);
    }
    if (asset.dependency_type === "ONCHAIN") {
      if (!entry || asset.data !== entry.expectedDependency.data || asset.bytecode_address !== entry.expectedDependency.bytecode_address) {
        throw new Error(`Unsupported live contract dependency: ${project.name}`);
      }
    } else if (asset.dependency_type === "ART_BLOCKS_DEPENDENCY_REGISTRY") {
      if (!DEPENDENCIES[asset.cid]) throw new Error(`Unsupported external library: ${project.name}: ${asset.cid}`);
    } else if (!asset.cid || /\s/u.test(asset.cid)) throw new Error(`Missing external asset CID: ${project.name}`);
  }
  if (entry && (entry.name !== project.name || !ordered.some(asset => asset.dependency_type === "ONCHAIN"))) {
    throw new Error(`Review compatibility entry no longer matches: ${project.name}`);
  }
  if (project.key === PINATA && (assets.length !== 1 || assets[0].cid !== PINATA_CID || assets[0].dependency_type !== "ARWEAVE")) {
    throw new Error(`Unexpected external assets: ${project.name}`);
  }
  return ordered;
}

function validateSecondaryDependencies(project, source, kind, assets) {
  const profile = SECONDARY_DEPENDENCY_PROFILES.get(project.key);
  if (!profile) return undefined;
  if (profile.name !== project.name || profile.kind !== kind
    || !profile.sourceReferences.every(reference => source.script.includes(reference))
    || (profile.externalAssetCID && (assets.length !== 1 || assets[0].dependency_type !== "IPFS" || assets[0].cid !== profile.externalAssetCID))) {
    throw new Error(`Secondary dependency profile no longer matches: ${project.name}`);
  }
  return profile;
}

function validateSource(project, source, compatibility = { version: 1, staticFirst: {} }) {
  if (!source || source.id !== project.apiId || source.chain_id !== project.chainId
    || source.contract_address?.toLowerCase() !== project.address || source.project_id !== project.projectId
    || source.name !== project.name) throw new Error(`API project identity mismatch: ${project.name}`);
  if (typeof source.script !== "string" || !source.script.trim()
    || !Number.isInteger(source.script_count) || source.script_count < 1) {
    throw new Error(`Missing complete artist script: ${project.name}`);
  }
  aspectRatio(source.aspect_ratio);
  const dependency = source.dependency_name_and_version ?? source.script_type_and_version;
  const emptyBody = EMPTY_BODY_PROJECTS.get(project.key) === project.name;
  const html = HTML_PROJECTS.get(project.key);
  const kind = html?.name === project.name && html.dependency === dependency ? "html"
    : dependency == null && NULL_JS_PROJECTS.get(project.key) === project.name ? "js" : DEPENDENCIES[dependency];
  if (!kind || (kind === "processingjs146" && PROCESSING_PROJECTS.get(project.key) !== project.name)) {
    throw new Error(`Unsupported dependency for ${project.name}: ${dependency}`);
  }
  const assets = validateAssets(project, source, compatibility);
  if (kind === "html") validateHTML(source.script, project.name);
  else if (kind !== "processingjs146") validateJavaScript(source.script, project.name, project.key === MODULE_PROJECT);
  else if (!/\bvoid\s+setup\s*\(/u.test(source.script)) throw new Error(`${project.name} has no Processing setup function`);
  const secondaryProfile = validateSecondaryDependencies(project, source, kind, assets);
  return { kind, dependency, emptyBody, assets, secondaryProfile };
}

function createScript(project, source, compatibility) {
  const { kind, emptyBody, assets, secondaryProfile } = validateSource(project, source, compatibility);
  const script = { address: project.address, name: project.name, abId: project.projectId, chain: "ethereum",
    kind, value: (project.key === PINATA ? PINATA_ADAPTER : "") + source.script,
    collectionIdOverride: project.collectionId, isDevelopmentPreview: true };
  if (emptyBody || secondaryProfile?.requiresInitialCanvas === false) script.requiresInitialCanvas = false;
  if (kind === "babylon500") script.requiresInitialCanvas = project.key !== LYCORISES;
  if (project.key === MODULE_PROJECT) script.isModule = true;
  const additionalLibraries = assets.filter(asset => asset.dependency_type === "ART_BLOCKS_DEPENDENCY_REGISTRY").map(asset => DEPENDENCIES[asset.cid]);
  if (project.key === TRANSFORMATIONS) additionalLibraries.push("tone1504");
  if (secondaryProfile) additionalLibraries.push(...secondaryProfile.additionalLibraries);
  if (additionalLibraries.length) script.additionalLibraries = [...new Set(additionalLibraries)];
  if (kind === "tone" && additionalLibraries.includes("p5js100")) script.requiresInitialCanvas = false;
  if (assets.length) script.externalAssetDependencies = assets.map(asset => {
    const value = { ...asset };
    if (value.data === "#web3call_contract#") delete value.data;
    return value;
  });
  if (secondaryProfile) script.secondaryDependencyProfile = secondaryProfile.profile;
  return script;
}

function fallbackImage(project, token) {
  const image = token.image;
  let url;
  try { url = new URL(image?.url); } catch { throw new Error(`Missing fallback image: ${project.name} #${token.token_id}`); }
  if (image.extension?.toLowerCase() !== "png" || url.protocol !== "https:" || !url.hostname || url.username || url.password
    || image.url !== image.url.trim() || /[\x00-\x1f\x7f]/u.test(image.url) || !/\.png$/iu.test(url.pathname)) {
    throw new Error(`Invalid PNG fallback image: ${project.name} #${token.token_id}`);
  }
  const width = image.metadata?.width, height = image.metadata?.height;
  const dimensions = Number.isSafeInteger(width) && width > 0 && Number.isSafeInteger(height) && height > 0 ? [width, height] : undefined;
  return { url: image.url, ...(dimensions ? {
    previewImageAspectRatio: dimensions,
    previewReferencePixelSize: dimensions,
  } : {}) };
}

async function readTree(directory, fileSystem = fs) {
  const files = new Map();
  async function visit(relative = "") {
    let entries;
    try { entries = await fileSystem.readdir(path.join(directory, relative), { withFileTypes: true }); }
    catch (error) { if (!relative && error.code === "ENOENT") return; throw error; }
    for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name, "en-US"))) {
      const file = path.join(relative, entry.name);
      if (entry.isDirectory()) await visit(file);
      else if (entry.isFile()) files.set(file, await fileSystem.readFile(path.join(directory, file), "utf8"));
      else throw new Error(`Unexpected file in preview resources: ${file}`);
    }
  }
  await visit();
  return files;
}

function sameTree(a, b) {
  return a.size === b.size && [...a].every(([file, content]) => b.get(file) === content);
}

async function planPreview(options = {}) {
  const output = path.resolve(options.output ?? DEFAULT_OUTPUT);
  const registryText = await fs.readFile(options.curation ?? DEFAULT_CURATION, "utf8");
  const projects = selectProjects(JSON.parse(registryText));
  const compatibilityText = await fs.readFile(options.compatibility ?? DEFAULT_COMPATIBILITY, "utf8");
  const compatibility = validateCompatibility(JSON.parse(compatibilityText));
  const before = await readTree(output);
  const apiURL = options.apiURL ?? API_URL;
  const context = { apiURL, maxRetries: 5, timeoutMs: 45000 };
  const request = options.request ?? ((query, variables) => graphql(context, query, variables));
  const results = new Array(projects.length);
  let next = 0;
  const workers = await Promise.allSettled(Array.from({ length: Math.min(2, projects.length) }, async () => {
    while (next < projects.length) {
      const index = next++, project = projects[index];
      const data = await request(PROJECT_QUERY, { id: project.apiId, chain: project.chainId });
      if (data.projects_metadata?.length !== 1) throw new Error(`Expected one API project: ${project.name}`);
      const source = data.projects_metadata[0], script = createScript(project, source, compatibility);
      const dataTokens = await request(TOKENS_QUERY, { project: project.apiId, chain: project.chainId,
        address: project.address, ids: project.tokenIds });
      if (!Array.isArray(dataTokens.tokens_metadata)) throw new Error(`Missing API tokens: ${project.name}`);
      const hashes = validateHashes(project, project.tokenIds, dataTokens.tokens_metadata);
      const images = new Map(dataTokens.tokens_metadata.map(token => [token.token_id, fallbackImage(project, token)]));
      const oldManifest = before.get(path.join("Tokens", `${project.collectionId}.json`));
      if (oldManifest) {
        for (const item of JSON.parse(oldManifest).items) {
          if (hashes.has(item.id) && item.hash !== hashes.get(item.id)) throw new Error(`Existing hash changed: ${project.name} #${item.id}`);
        }
      }
      results[index] = { project, source, script,
        tokens: { items: project.tokenIds.map(id => ({ id, hash: hashes.get(id), ...images.get(id) })),
          thumbnailAspectRatios: [aspectRatio(source.aspect_ratio)] } };
      options.onProject?.(project);
    }
  }));
  const failures = workers.filter(result => result.status === "rejected");
  if (failures.length) throw new AggregateError(failures.map(failure => failure.reason), "Preview source validation failed");
  const files = new Map(), catalog = [];
  const report = { version: 2, apiURL, curationSHA256: sha256(registryText), compatibilitySHA256: sha256(compatibilityText),
    collectionCount: projects.length, groupCounts: { good: 0, ok: 0, hmm: 0 }, tokenCount: 0, staticFirstCount: 0, collections: [] };
  for (const { project, source, script, tokens } of results) {
    files.set(path.join("Scripts", `${project.collectionId}.json`), json(script));
    files.set(path.join("Tokens", `${project.collectionId}.json`), json(tokens));
    catalog.push({ address: project.address, chain: "ethereum", chainId: project.chainId,
      collectionId: project.suffix, name: project.name,
      reviewIdentity: project.key, reviewGroup: project.group,
      ...(compatibility.staticFirst[project.key] ? { previewStaticReason: compatibility.staticFirst[project.key].reason } : {}),
      internal_slug: `dev_good_${project.chainId}_${project.address}_${project.projectId}`, artists: [] });
    report.groupCounts[project.group]++;
    if (compatibility.staticFirst[project.key]) report.staticFirstCount++;
    report.tokenCount += tokens.items.length;
    report.collections.push({ identity: project.key, collectionId: project.collectionId, name: project.name,
      artist: source.artist_name, group: project.group, apiProjectId: project.apiId, chainId: project.chainId,
      kind: script.kind, dependency: source.dependency_name_and_version ?? source.script_type_and_version,
      aspectRatio: source.aspect_ratio, tokenCount: tokens.items.length, scriptCount: source.script_count,
      sourceScriptBytes: Buffer.byteLength(source.script), sourceScriptSHA256: sha256(source.script),
      bundledScriptSHA256: sha256(script.value), tokenIdsSHA256: sha256(JSON.stringify(project.tokenIds)),
      tokenHashesSHA256: sha256(JSON.stringify(tokens.items.map(({ id, hash }) => ({ id, hash })))),
      fallbackImagesSHA256: sha256(JSON.stringify(tokens.items.map(({ id, url, previewImageAspectRatio }) => ({ id, url, previewImageAspectRatio })))),
      referencePixelSizesSHA256: sha256(JSON.stringify(tokens.items.map(({ id, previewReferencePixelSize }) => ({ id, previewReferencePixelSize })))),
      externalAssets: [...source.external_asset_dependencies].sort((a, b) => a.index - b.index),
      ...(script.secondaryDependencyProfile ? { secondaryDependencyProfile: script.secondaryDependencyProfile,
        additionalLibraries: script.additionalLibraries } : {}),
      ...(compatibility.staticFirst[project.key] ? { staticReason: compatibility.staticFirst[project.key].reason } : {}) });
  }
  files.set("provenance.json", json(report));
  files.set("compatibility.json", compatibilityText);
  files.set("items.json", json(catalog));
  const parameters = await readContractParameters(options, projects, compatibility);
  return applyContractParameterSnapshot({ output, before, files, report }, projects, compatibility, parameters);
}

async function planFrozenParameters(options = {}) {
  const output = path.resolve(options.output ?? DEFAULT_OUTPUT);
  const projects = selectProjects(JSON.parse(await fs.readFile(options.curation ?? DEFAULT_CURATION, "utf8")));
  const compatibilityText = await fs.readFile(options.compatibility ?? DEFAULT_COMPATIBILITY, "utf8");
  const compatibility = validateCompatibility(JSON.parse(compatibilityText));
  const before = await readTree(output);
  if (!before.has("items.json") || !before.has("provenance.json") || before.get("compatibility.json") !== compatibilityText) {
    throw new Error("Parameter-only refresh requires a complete preview with matching compatibility metadata");
  }
  const parameters = await readContractParameters(options, projects, compatibility);
  if (!parameters) throw new Error("Parameter-only refresh requires a frozen contract parameter snapshot");
  return applyContractParameterSnapshot({ output, before, files: new Map(before), preserveUnchangedFiles: true }, projects, compatibility, parameters);
}

async function applyPreview(plan, fileSystem = fs) {
  if (!sameTree(await readTree(plan.output, fileSystem), plan.before)) throw new Error("Preview resources changed during validation");
  if (sameTree(plan.before, plan.files)) return false;
  if ([...plan.files.keys()].at(-1) !== "items.json") throw new Error("The preview catalog must be written last");
  const parent = path.dirname(plan.output);
  await fileSystem.mkdir(parent, { recursive: true });
  const temporary = await fileSystem.mkdtemp(path.join(parent, ".good-preview-"));
  const stage = path.join(temporary, "new"), backup = path.join(temporary, "previous");
  let movedPrevious = false, published = false;
  try {
    await fileSystem.mkdir(stage);
    for (const [relative, content] of plan.files) {
      await fileSystem.mkdir(path.dirname(path.join(stage, relative)), { recursive: true });
      if (plan.preserveUnchangedFiles && plan.before.get(relative) === content) {
        await fileSystem.link(path.join(plan.output, relative), path.join(stage, relative));
      } else {
        await fileSystem.writeFile(path.join(stage, relative), content);
      }
      if (await fileSystem.readFile(path.join(stage, relative), "utf8") !== content) throw new Error(`Staged preview validation failed: ${relative}`);
      JSON.parse(content);
    }
    if (!sameTree(await readTree(plan.output, fileSystem), plan.before)) throw new Error("Preview resources changed while staging");
    try { await fileSystem.rename(plan.output, backup); movedPrevious = true; }
    catch (error) { if (error.code !== "ENOENT") throw error; }
    try { await fileSystem.rename(stage, plan.output); published = true; }
    catch (error) {
      if (movedPrevious) {
        try { await fileSystem.rename(backup, plan.output); movedPrevious = false; }
        catch (restoreError) { throw new AggregateError([error, restoreError], `Preview publish and rollback failed; previous resources remain at ${backup}`); }
      }
      throw error;
    }
  } finally {
    if (!movedPrevious || published) await fileSystem.rm(temporary, { recursive: true, force: true });
  }
  return true;
}

function parseArgs(args) {
  const options = { apply: false };
  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (arg === "--apply") options.apply = true;
    else if (arg === "--parameters-only") options.parametersOnly = true;
    else if (arg === "--dry-run") options.apply = false;
    else if (["--help", "-h"].includes(arg)) options.help = true;
    else if (["--curation", "--compatibility", "--parameters", "--output", "--api-url"].includes(arg)) {
      const value = args[++index];
      if (!value || value.startsWith("--")) throw new Error(`Missing value for ${arg}`);
      options[{ "--curation": "curation", "--compatibility": "compatibility", "--parameters": "parameters", "--output": "output", "--api-url": "apiURL" }[arg]] = value;
    } else throw new Error(`Unknown option: ${arg}`);
  }
  return options;
}

async function main(args = process.argv.slice(2), dependencies = {}) {
  const options = parseArgs(args), log = dependencies.log ?? console.log;
  if (options.help) {
    log("Usage: node tools/build_artblocks_good_preview.js [--dry-run|--apply] [--parameters-only] [--curation FILE] [--compatibility FILE] [--parameters FILE] [--output DIRECTORY] [--api-url URL]\nBuilds all saved good, ok, and hmm tokens into separate development review resources. --parameters-only applies a frozen snapshot to existing resources without network requests. Defaults to validation without writes.");
    return;
  }
  const plan = await (options.parametersOnly ? planFrozenParameters : planPreview)({ ...options, onProject: project => log(`Validated ${project.name}`), ...dependencies });
  const changed = options.apply ? await applyPreview(plan) : !sameTree(plan.before, plan.files);
  log(`${options.apply ? "Applied" : "Dry run"}: ${plan.report.collectionCount} collections, ${plan.report.tokenCount} tokens; ${changed ? "resources changed" : "resources unchanged"}.`);
  return { plan, changed };
}

module.exports = { API_URL, DEFAULT_OUTPUT, DEFAULT_COMPATIBILITY, DEFAULT_PARAMETERS, DEPENDENCIES, EMPTY_BODY_PROJECTS, GENESIS, PROCESSING_PROJECTS,
  NULL_JS_PROJECTS, HTML_PROJECTS, MODULE_PROJECT, TRANSFORMATIONS, SECONDARY_DEPENDENCY_PROFILES, validateSecondaryDependencies,
  PINATA, PINATA_CID, validateCompatibility, validateAssets, fallbackImage,
  PINATA_ADAPTER, PROJECT_QUERY, TOKENS_QUERY, selectProjects, aspectRatio, validateSource, createScript,
  readTree, sameTree, planPreview, planFrozenParameters, validateContractParameterSnapshot, validateRequiredContractParameters,
  applyContractParameterSnapshot, applyPreview, parseArgs, main };

if (require.main === module) main().catch(error => { console.error(error); process.exitCode = 1; });
