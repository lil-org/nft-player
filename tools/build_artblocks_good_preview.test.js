"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const { runInNewContext } = require("node:vm");
const { createHash } = require("node:crypto");
const { selectProjects, aspectRatio, validateSource, createScript, readTree, sameTree,
  planPreview, planFrozenParameters, applyPreview, main, GENESIS, PINATA, PINATA_CID, PINATA_ADAPTER,
  EMPTY_BODY_PROJECTS, NULL_JS_PROJECTS, PROCESSING_PROJECTS, HTML_PROJECTS, MODULE_PROJECT, TRANSFORMATIONS,
  validateCompatibility, fallbackImage, DEFAULT_COMPATIBILITY,
  SECONDARY_DEPENDENCY_PROFILES, DEFAULT_PARAMETERS, validateContractParameterSnapshot,
  validateRequiredContractParameters } = require("./build_artblocks_good_preview");

const DEFAULT_OUTPUT = path.join(__dirname, "artblocks/archive/pass-5/Development/Good");

const address = "0x0000000000000000000000000000000000000001";
const hash = invocation => `0x${String(invocation + 1).padStart(64, "0")}`;

function entry(key, name, invocations = [0, 2], group = "good") {
  const [chain, contract, project] = key.split(":");
  return { name, artist: `${name} artist`, group, directory: `${name}-${chain}-${project}`,
    ...(group === "excluded" ? {} : { samples: invocations.map(invocation => ({
      tokenId: String(BigInt(project) * 1000000n + BigInt(invocation)), invocation,
      url: `https://example.test/${contract}/${project}/${invocation}.png`, extension: "png",
    })) }) };
}

function registry(collections = {
  [`1:${address}:2`]: entry(`1:${address}:2`, "Zebra"),
  [`1:${address}:1`]: entry(`1:${address}:1`, "Alpha"),
  [`42161:${address}:1`]: entry(`42161:${address}:1`, "Alpha"),
  [`1:${address}:3`]: entry(`1:${address}:3`, "Excluded", [], "excluded"),
  [`1:${address}:4`]: entry(`1:${address}:4`, "Okay", [0], "ok"),
}) {
  return { version: 1, source: { endpoint: "https://data.artblocks.io/v1/graphql", discoveredAt: "2026-09-06T00:00:00Z" }, collections };
}

function source(project, dependency = "p5@1.0.0") {
  return { id: project.apiId, chain_id: project.chainId, contract_address: project.address,
    project_id: project.projectId, name: project.name, artist_name: project.artist, aspect_ratio: 4 / 3,
    script: 'function setup() { createCanvas(10, 10); }\nfunction draw() { background(tokenData.hash); }',
    script_count: 3, dependency_name_and_version: dependency, script_type_and_version: dependency,
    external_asset_dependency_count: 0, external_asset_dependencies: [] };
}

function apiTokens(project) {
  return project.tokenIds.map(id => ({ id: `${project.address}-${id}`, token_id: id,
    contract_address: project.address, chain_id: project.chainId, project_id: project.apiId,
    invocation: Number(BigInt(id) % 1000000n), hash: hash(Number(BigInt(id) % 1000000n)),
    image: { url: `https://example.test/api/${id}.png`, extension: "png", metadata: { width: 1600, height: 1200 } } }));
}

async function fixture(t, curation = registry()) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "good-preview-test-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const curationFile = path.join(directory, "curation.json"), output = path.join(directory, "Good");
  await fs.writeFile(curationFile, JSON.stringify(curation));
  const projects = selectProjects(curation), requests = [];
  const sources = new Map(projects.map(project => [project.key, source(project)]));
  const tokens = new Map(projects.map(project => [project.key, apiTokens(project)]));
  const request = async (query, variables) => {
    requests.push({ query, variables });
    const project = projects.find(project => project.chainId === variables.chain && project.apiId === (variables.id ?? variables.project));
    assert.ok(project, "API query must be restricted to a retained project and chain");
    if (query.includes("GoodPreviewProject")) return { projects_metadata: [sources.get(project.key)] };
    assert.match(query, /chain_id: \{_eq: \$chain\}/u);
    assert.match(query, /contract_address: \{_eq: \$address\}/u);
    assert.match(query, /token_id: \{_in: \$ids\}/u);
    assert.match(query, /limit: 24/u);
    assert.equal(variables.address, project.address);
    assert.deepEqual(variables.ids, project.tokenIds);
    return { tokens_metadata: [...tokens.get(project.key)].reverse() };
  };
  return { directory, curation: curationFile, output, projects, sources, tokens, requests, request, parameterSnapshot: null };
}

test("saved review selection has 519 projects and exactly 11,627 sample tokens", async () => {
  const saved = JSON.parse(await fs.readFile(path.join(__dirname, "artblocks", "reviews", "pass-1-curation.json"), "utf8"));
  const projects = selectProjects(saved);
  assert.equal(projects.length, 519);
  assert.equal(projects.reduce((count, project) => count + project.tokenIds.length, 0), 11627);
  assert.equal(new Set(projects.map(project => project.collectionId)).size, 519);
  assert.equal(projects.filter(project => project.chainId === 8453).length, 1);
  assert.deepEqual(Object.fromEntries(["good", "ok", "hmm"].map(group => [group, projects.filter(project => project.group === group).length])), { good: 55, ok: 237, hmm: 227 });
  assert.equal(projects.find(project => project.name === "Circulate").tokenIds.length, 11);
  assert.equal(projects.filter(project => project.group === "good").reduce((count, project) => count + project.tokenIds.length, 0), 1253);
});

test("selection orders by name and stable identity with separate cross-chain IDs", () => {
  const projects = selectProjects(registry());
  assert.deepEqual(projects.map(project => project.name), ["Alpha", "Alpha", "Okay", "Zebra"]);
  assert.deepEqual(projects.map(project => project.chainId), [1, 42161, 1, 1]);
  assert.equal(projects[0].collectionId, `${address}-dev-good-1-1`);
  assert.equal(projects[1].collectionId, `${address}-dev-good-42161-1`);
  assert.throws(() => selectProjects(registry({})), /no retained collections/u);
  const invalid = registry();
  invalid.collections[`1:${address}:1`].samples.push(invalid.collections[`1:${address}:1`].samples[0]);
  assert.throws(() => selectProjects(invalid), /Duplicate or out-of-order/u);
});

test("dry run fetches only exact saved tokens, writes nothing, and preserves all identities and token order", async t => {
  const f = await fixture(t), before = await readTree(f.directory);
  const plan = await planPreview(f);
  assert.ok(sameTree(before, await readTree(f.directory)));
  assert.equal(plan.report.collectionCount, 4);
  assert.equal(plan.report.tokenCount, 7);
  assert.equal(plan.files.size, 11);
  assert.equal(f.requests.length, 8);
  const catalog = JSON.parse(plan.files.get("items.json"));
  for (const [index, project] of f.projects.entries()) {
    assert.equal(catalog[index].collectionId, project.suffix);
    assert.equal(catalog[index].address, project.address);
    assert.equal(catalog[index].chainId, project.chainId);
    assert.equal(catalog[index].reviewIdentity, project.key);
    assert.equal(catalog[index].reviewGroup, project.group);
    assert.equal(catalog[index].name, project.name);
    for (const key of ["tokenCount", "abId", "standardThumbsPathsAvailable"]) assert.equal(catalog[index][key], undefined);
    assert.deepEqual(catalog[index].artists, []);
    const script = JSON.parse(plan.files.get(`Scripts/${project.collectionId}.json`));
    assert.equal(script.value, f.sources.get(project.key).script);
    assert.equal(script.collectionIdOverride, project.collectionId);
    assert.equal(script.abId, project.projectId);
    assert.equal(script.isDevelopmentPreview, true);
    assert.equal(script.requiresInitialCanvas, undefined);
    const manifest = JSON.parse(plan.files.get(`Tokens/${project.collectionId}.json`));
    assert.deepEqual(manifest.items, project.tokenIds.map(id => ({ id, hash: hash(Number(BigInt(id) % 1000000n)),
      url: `https://example.test/api/${id}.png`, previewImageAspectRatio: [1600, 1200], previewReferencePixelSize: [1600, 1200] })));
    assert.deepEqual(manifest.thumbnailAspectRatios, [[4, 3]]);
    assert.ok(manifest.items.every(item => Object.keys(item).sort().join(",") === "hash,id,previewImageAspectRatio,previewReferencePixelSize,url"));
  }
});

test("apply writes and validates all resources before the catalog, publishes the complete tree, and is idempotent", async t => {
  const f = await fixture(t), plan = await planPreview(f), writes = [];
  const tracedFS = { ...fs, writeFile: async (file, contents) => { writes.push(path.basename(file)); return fs.writeFile(file, contents); } };
  assert.equal(await applyPreview(plan, tracedFS), true);
  assert.equal(writes.at(-1), "items.json");
  assert.ok(writes.slice(0, -1).some(file => file === "provenance.json"));
  assert.ok(sameTree(await readTree(f.output), plan.files));
  const before = await fs.stat(path.join(f.output, "items.json"));
  const repeated = await planPreview(f);
  assert.equal(await applyPreview(repeated), false);
  assert.equal((await fs.stat(path.join(f.output, "items.json"))).mtimeMs, before.mtimeMs);
  assert.deepEqual((await fs.readdir(f.directory)).sort(), ["Good", "curation.json"]);
});

test("staging write failure keeps the previous catalog and resources intact", async t => {
  const f = await fixture(t);
  await fs.mkdir(f.output);
  await fs.writeFile(path.join(f.output, "items.json"), "[]\n");
  const plan = await planPreview(f), before = await readTree(f.output), writes = [];
  const failingFS = { ...fs, writeFile: async (file, contents) => {
    writes.push(file);
    if (file.includes(`${path.sep}Scripts${path.sep}`)) throw Object.assign(new Error("Script directory is unwritable"), { code: "EACCES" });
    return fs.writeFile(file, contents);
  } };
  await assert.rejects(applyPreview(plan, failingFS), /unwritable/u);
  assert.ok(sameTree(before, await readTree(f.output)));
  assert.ok(writes.every(file => path.basename(file) !== "items.json"));
  assert.deepEqual((await fs.readdir(f.directory)).sort(), ["Good", "curation.json"]);
});

test("publishing failure rolls back the previous preview directory", async t => {
  const f = await fixture(t);
  await fs.mkdir(f.output);
  await fs.writeFile(path.join(f.output, "items.json"), "[]\n");
  const plan = await planPreview(f), before = await readTree(f.output);
  const failingFS = { ...fs, rename: async (from, to) => {
    if (path.basename(from) === "new") throw Object.assign(new Error("Cannot publish"), { code: "EACCES" });
    return fs.rename(from, to);
  } };
  await assert.rejects(applyPreview(plan, failingFS), /Cannot publish/u);
  assert.ok(sameTree(before, await readTree(f.output)));
  assert.deepEqual((await fs.readdir(f.directory)).sort(), ["Good", "curation.json"]);
});

test("apply rejects concurrent resource edits", async t => {
  const f = await fixture(t), plan = await planPreview(f);
  await fs.mkdir(f.output);
  await fs.writeFile(path.join(f.output, "items.json"), "[]\n");
  await assert.rejects(applyPreview(plan), /changed during validation/u);
  assert.equal(await fs.readFile(path.join(f.output, "items.json"), "utf8"), "[]\n");
});

test("missing, duplicate, invalid, and wrong-chain hashes abort without partial outputs", async t => {
  for (const mutation of [
    tokens => tokens.pop(),
    tokens => tokens.push(tokens[0]),
    tokens => { tokens[0].hash = "0x1234"; },
    tokens => { tokens[0].chain_id = 42; },
  ]) {
    const f = await fixture(t);
    mutation(f.tokens.get(f.projects[0].key));
    await assert.rejects(planPreview(f), error => error instanceof AggregateError && error.errors.some(cause => /hash|token|identity/iu.test(cause.message)));
    assert.equal((await readTree(f.output)).size, 0);
  }
});

test("source identity, incomplete scripts, unsupported libraries and unexpected assets fail validation", () => {
  const project = selectProjects(registry())[0];
  for (const change of [
    { chain_id: 42161 }, { id: "different-project" }, { script: "" }, { script_count: 0 },
    { dependency_name_and_version: "p5@2.0.0" }, { dependency_name_and_version: null, script_type_and_version: null },
    { external_asset_dependency_count: 1, external_asset_dependencies: [{ index: 0, cid: "unexpected", dependency_type: "UNSUPPORTED" }] },
    { script: "function setup( {" }, { aspect_ratio: 0 },
  ]) assert.throws(() => validateSource(project, { ...source(project), ...change }));
});

test("previous hashes cannot silently change on refresh", async t => {
  const f = await fixture(t);
  await applyPreview(await planPreview(f));
  f.tokens.get(f.projects[0].key)[0].hash = `0x${"f".repeat(64)}`;
  await assert.rejects(planPreview(f), error => error.errors.some(cause => /Existing hash changed/u.test(cause.message)));
});

test("aspect ratios normalize to positive rational dimensions", () => {
  for (const [value, expected] of [[4 / 3, [4, 3]], [0.75, [3, 4]], [0.625, [5, 8]], [0.8, [4, 5]], [1, [1, 1]]]) {
    assert.deepEqual(aspectRatio(value), expected);
  }
  for (const value of [0.7142857142, 0.7070980616, 0.66666, 1.40023337223, 1.778]) {
    const [width, height] = aspectRatio(value);
    assert.ok(Number.isInteger(width) && Number.isInteger(height) && width > 0 && height > 0);
    assert.ok(Math.abs(width / height - value) < 1e-6);
  }
  for (const value of [null, 0, -1, NaN, Infinity, "1"]) assert.throws(() => aspectRatio(value));
});

test("Genesis retains unmodified Processing source while the two exact null-library projects get empty JavaScript bodies", () => {
  const genesis = selectProjects(registry({ [GENESIS]: entry(GENESIS, "Genesis") }))[0];
  const genesisSource = { ...source(genesis, "processing-js@1.4.6"), script: "void setup() { size(500, 375); }\nvoid draw() { float value = 1.0; }" };
  const result = createScript(genesis, genesisSource);
  assert.equal(result.kind, "processingjs146");
  assert.equal(result.value, genesisSource.script);
  assert.equal(result.requiresInitialCanvas, undefined);
  for (const [key, name] of EMPTY_BODY_PROJECTS) {
    const project = selectProjects(registry({ [key]: entry(key, name) }))[0];
    const result = createScript(project, source(project, null));
    assert.equal(result.kind, "js");
    assert.equal(result.requiresInitialCanvas, false);
  }
});

test("piñata3 adapter keeps original artist code and only accepts its known Arweave dependency", () => {
  const project = selectProjects(registry({ [PINATA]: entry(PINATA, "piñata3") }))[0];
  const pinataSource = { ...source(project, "p5@1.9.0"), external_asset_dependency_count: 1,
    external_asset_dependencies: [{ index: 0, cid: PINATA_CID, dependency_type: "ARWEAVE" }] };
  const result = createScript(project, pinataSource);
  assert.equal(result.value, PINATA_ADAPTER + pinataSource.script);
  pinataSource.external_asset_dependencies[0].cid = "changed";
  assert.throws(() => createScript(project, pinataSource), /Unexpected external assets/u);
});

function pinataGuard() {
  const callbacks = [], pending = new Map(), errors = [], hooks = new Map();
  function P5() {}
  P5.prototype.loadImage = function (url, success, failure) { callbacks.push({ instance: this, url, success, failure }); return { image: url }; };
  P5.prototype.registerMethod = (name, hook) => hooks.set(name, hook);
  let timerId = 0;
  const tokenData = {};
  runInNewContext(PINATA_ADAPTER, { p5: P5, tokenData, showPreviewError: error => errors.push(error),
    setTimeout: (callback, timeout) => { assert.equal(timeout, 60000); pending.set(++timerId, callback); return timerId; },
    clearTimeout: id => pending.delete(id) });
  return { P5, callbacks, pending, errors, hooks, tokenData };
}

test("piñata3 guard preserves successful callbacks and rendering", () => {
  const f = pinataGuard(), instance = new f.P5(), received = [];
  instance.setup = () => received.push("setup");
  const value = instance.loadImage("https://arweave.net/image.png", image => received.push(image));
  assert.equal(value.image, "https://arweave.net/image.png");
  f.callbacks[0].success("image");
  assert.equal(f.pending.size, 0);
  f.hooks.get("beforeSetup").call(instance);
  instance.setup();
  assert.deepEqual(received, ["image", "setup"]);
  assert.equal(f.errors.length, 0);
  assert.equal(f.tokenData.externalAssetDependencies[0].cid, PINATA_CID);
});

test("piñata3 failure and timeout prevent its original infinite setup loop without affecting other instances", () => {
  for (const fail of [f => f.callbacks[0].failure("failed"), f => [...f.pending.values()][0]()]) {
    const f = pinataGuard(), instance = new f.P5(), calls = [];
    instance.setup = () => { throw new Error("Infinite wait loop reached"); };
    instance.noLoop = () => calls.push("noLoop");
    instance.noCanvas = () => calls.push("noCanvas");
    instance.loadImage("missing.png", null, error => calls.push(error));
    fail(f);
    f.hooks.get("beforeSetup").call(instance);
    instance.setup();
    assert.ok(calls.includes("noLoop") && calls.includes("noCanvas"));
    assert.ok(f.errors.length > 0);
    const other = new f.P5(), setup = () => {};
    other.setup = setup;
    f.hooks.get("beforeSetup").call(other);
    assert.equal(other.setup, setup);
  }
});

test("CLI defaults to a nonmutating dry run and accepts explicit apply", async t => {
  const f = await fixture(t), log = [];
  await main([], { ...f, log: value => log.push(value) });
  assert.equal((await readTree(f.output)).size, 0);
  assert.match(log.at(-1), /^Dry run: 4 collections, 7 tokens/u);
  await main(["--apply"], { ...f, log: value => log.push(value) });
  assert.equal((await readTree(f.output)).size, 11);
  assert.match(log.at(-1), /^Applied:/u);
  await assert.rejects(main(["--unknown"], f), /Unknown option/u);
});

test("all explicit null metadata overrides and both Processing projects retain their sources", () => {
  for (const [key, name] of NULL_JS_PROJECTS) {
    const project = selectProjects(registry({ [key]: entry(key, name) }))[0];
    const value = source(project, null), script = createScript(project, value);
    assert.equal(script.kind, "js");
    assert.equal(script.value, value.script);
    assert.equal(script.requiresInitialCanvas, EMPTY_BODY_PROJECTS.has(key) ? false : undefined);
  }
  for (const [key, name] of PROCESSING_PROJECTS) {
    const project = selectProjects(registry({ [key]: entry(key, name) }))[0];
    const value = { ...source(project, "processing-js@1.4.6"), script: "void setup() { size(400, 500); }" };
    assert.equal(createScript(project, value).value, value.script);
  }
});

test("full HTML, direct modules, and modules created by classic scripts retain their source format", () => {
  for (const [key, { name, dependency }] of HTML_PROJECTS) {
    const project = selectProjects(registry({ [key]: entry(key, name) }))[0];
    const value = { ...source(project, dependency), script: '<html><body><canvas id="A"></canvas><script>const test = 1;</script></body></html>' };
    const script = createScript(project, value);
    assert.equal(script.kind, "html");
    assert.equal(script.value, value.script);
    assert.throws(() => createScript(project, { ...value, script: "<html><script>const = 1;</script></html>" }), SyntaxError);
  }
  const moduleProject = selectProjects(registry({ [MODULE_PROJECT]: entry(MODULE_PROJECT, "Materialistic - Digital Edition") }))[0];
  const direct = { ...source(moduleProject, "three@0.167.0"), script: 'import * as THREE from "three"; const scene = new THREE.Scene();' };
  assert.equal(createScript(moduleProject, direct).isModule, true);
  assert.equal(createScript(moduleProject, direct).value, direct.script);
  assert.throws(() => createScript(moduleProject, { ...direct, script: 'import ? from "three";' }), /Invalid module source/u);
  const classic = selectProjects(registry({ [TRANSFORMATIONS]: entry(TRANSFORMATIONS, "Transformations du Champ") }))[0];
  const script = createScript(classic, source(classic, "three@0.167.0"));
  assert.equal(script.kind, "three167");
  assert.equal(script.isModule, undefined);
  assert.deepEqual(script.additionalLibraries, ["tone1504"]);
});

test("external metadata preserves index order and exact library combinations", () => {
  const project = selectProjects(registry())[0];
  const value = { ...source(project, "tone@14.8.15"), external_asset_dependency_count: 3, external_asset_dependencies: [
    { index: 2, cid: "third", dependency_type: "ARWEAVE", data: null, bytecode_address: null },
    { index: 0, cid: "p5@1.0.0", dependency_type: "ART_BLOCKS_DEPENDENCY_REGISTRY", data: null, bytecode_address: null },
    { index: 1, cid: "second", dependency_type: "IPFS", data: null, bytecode_address: null },
  ] };
  const script = createScript(project, value);
  assert.deepEqual(script.additionalLibraries, ["p5js100"]);
  assert.equal(script.requiresInitialCanvas, false);
  assert.deepEqual(script.externalAssetDependencies.map(asset => asset.cid), ["p5@1.0.0", "second", "third"]);
  value.external_asset_dependencies[0].index = 1;
  assert.throws(() => createScript(project, value), /Invalid external asset metadata/u);
  value.external_asset_dependencies[0].index = 2;
  value.external_asset_dependencies[1].cid = "p5@99.0.0";
  assert.throws(() => createScript(project, value), /Unsupported external library/u);
});

test("compatibility lists the ten exact static-first identities and rejects stale or unknown contract requirements", async t => {
  const compatibility = validateCompatibility(JSON.parse(await fs.readFile(DEFAULT_COMPATIBILITY, "utf8")));
  assert.equal(Object.keys(compatibility.staticFirst).length, 10);
  assert.deepEqual(Object.values(compatibility.staticFirst).map(value => value.name).sort(),
    ["DDUST", "Portraits I", "Hatches", "Broken Dreams", "Gift of Time", "Primavera", "pool party", "Drawings for a Monument", "Diggly Collects All", "degenerative"].sort());
  const [key, item] = Object.entries(compatibility.staticFirst)[0];
  const f = await fixture(t, registry({ [key]: entry(key, item.name, [0], "hmm") }));
  const value = { ...source(f.projects[0]), external_asset_dependency_count: 1,
    external_asset_dependencies: [{ index: 0, cid: "", ...item.expectedDependency }] };
  f.sources.set(key, value);
  const plan = await planPreview(f);
  const catalog = JSON.parse(plan.files.get("items.json"));
  assert.equal(catalog[0].previewStaticReason, item.reason);
  assert.equal(catalog[0].reviewGroup, "hmm");
  assert.equal(plan.report.staticFirstCount, 1);
  const script = JSON.parse(plan.files.get(`Scripts/${f.projects[0].collectionId}.json`));
  assert.equal(script.value, value.script);
  assert.equal(script.externalAssetDependencies[0].data, undefined);
  assert.equal(plan.report.collections[0].externalAssets[0].data, "#web3call_contract#");
  assert.throws(() => createScript(f.projects[0], value), /Unsupported live contract dependency/u);
  assert.throws(() => createScript(f.projects[0], { ...value, external_asset_dependency_count: 0, external_asset_dependencies: [] }, compatibility), /no longer matches/u);
  assert.throws(() => validateCompatibility({ ...compatibility, version: 2 }), /Invalid review compatibility manifest/u);
  value.external_asset_dependencies[0].bytecode_address = address;
  await assert.rejects(planPreview(f), error => error.errors.some(cause => /Unsupported live contract dependency/u.test(cause.message)));
});

test("fallbacks use API PNG images even for video selections and reject missing or unsafe images", async t => {
  const curation = registry();
  curation.collections[`1:${address}:1`].samples[0].url = "https://example.test/movie.mp4";
  curation.collections[`1:${address}:1`].samples[0].extension = "mp4";
  const f = await fixture(t, curation), project = f.projects[0];
  const plan = await planPreview(f), manifest = JSON.parse(plan.files.get(`Tokens/${project.collectionId}.json`));
  assert.equal(manifest.items[0].url, `https://example.test/api/${project.tokenIds[0]}.png`);
  const token = f.tokens.get(project.key)[0];
  assert.deepEqual(fallbackImage(project, token).previewReferencePixelSize, [1600, 1200]);
  assert.deepEqual(fallbackImage(project, { ...token, image: { ...token.image, metadata: null } }), { url: token.image.url });
  for (const change of [{ image: null }, { image: { ...token.image, url: "http://example.test/image.png" } },
    { image: { ...token.image, extension: "mp4", url: "https://example.test/image.mp4" } },
    { image: { ...token.image, url: "https://example.test/image.jpg" } }]) {
    assert.throws(() => fallbackImage(project, { ...token, ...change }), /fallback image/u);
  }
  token.image = null;
  await assert.rejects(planPreview(f), error => error.errors.some(cause => /fallback image/u.test(cause.message)));
  assert.equal((await readTree(f.output)).size, 0);
});

test("the complete bundled review reconciles all identities, groups, hashes, sources, images, and compatibility decisions", async () => {
  const saved = JSON.parse(await fs.readFile(path.join(__dirname, "artblocks", "reviews", "pass-1-curation.json"), "utf8"));
  const projects = selectProjects(saved), tree = await readTree(DEFAULT_OUTPUT);
  const items = JSON.parse(tree.get("items.json")), report = JSON.parse(tree.get("provenance.json"));
  const compatibility = validateCompatibility(JSON.parse(tree.get("compatibility.json")));
  const parameters = JSON.parse(await fs.readFile(DEFAULT_PARAMETERS, "utf8"));
  assert.equal(tree.get("compatibility.json"), await fs.readFile(DEFAULT_COMPATIBILITY, "utf8"));
  assert.equal(tree.size, 1041);
  assert.equal(items.length, 519);
  assert.deepEqual(items.map(item => item.reviewIdentity), projects.map(project => project.key));
  assert.deepEqual(report.groupCounts, { good: 55, ok: 237, hmm: 227 });
  assert.equal(report.staticFirstCount, 4);
  assert.equal(report.contractParameters.collectionCount, 6);
  assert.equal(report.contractParameters.tokenCount, 135);
  let count = 0, oldGoodCount = 0;
  for (const [index, project] of projects.entries()) {
    const item = items[index], recorded = report.collections[index];
    const script = JSON.parse(tree.get(`Scripts/${project.collectionId}.json`));
    const manifest = JSON.parse(tree.get(`Tokens/${project.collectionId}.json`));
    assert.equal(item.address + item.collectionId, project.collectionId);
    assert.equal(item.reviewGroup, project.group);
    assert.equal(item.name, project.name);
    const frozen = parameters.collections[project.key];
    assert.equal(item.previewStaticReason, frozen ? undefined : compatibility.staticFirst[project.key]?.reason);
    assert.equal(script.collectionIdOverride, project.collectionId);
    assert.equal(script.name, project.name);
    assert.equal(script.isDevelopmentPreview, true);
    const secondaryProfile = SECONDARY_DEPENDENCY_PROFILES.get(project.key);
    assert.equal(script.secondaryDependencyProfile, secondaryProfile?.profile);
    assert.equal(recorded.secondaryDependencyProfile, secondaryProfile?.profile);
    if (secondaryProfile) {
      assert.deepEqual(script.additionalLibraries, secondaryProfile.additionalLibraries);
      assert.deepEqual(recorded.additionalLibraries, secondaryProfile.additionalLibraries);
      assert.equal(script.requiresInitialCanvas, secondaryProfile.requiresInitialCanvas);
    }
    assert.deepEqual(manifest.items.map(token => token.id), project.tokenIds);
    for (const token of manifest.items) {
      assert.match(token.hash, /^0x[0-9a-f]{64}$/iu);
      assert.match(token.url, /^https:\/\/.+\.png(?:\?.*)?$/iu);
      if (token.previewImageAspectRatio) assert.ok(token.previewImageAspectRatio.every(value => Number.isSafeInteger(value) && value > 0));
      assert.deepEqual(token.previewContractParameters, frozen?.tokens[token.id]?.parameters);
      if (frozen) assert.equal(token.hash, frozen.tokens[token.id].hash);
    }
    const original = project.key === PINATA ? script.value.slice(PINATA_ADAPTER.length) : script.value;
    assert.equal(createHash("sha256").update(original).digest("hex"), recorded.sourceScriptSHA256);
    assert.equal(Buffer.byteLength(original), recorded.sourceScriptBytes);
    assert.equal(manifest.items.length, recorded.tokenCount);
    count += manifest.items.length;
    if (project.group === "good") oldGoodCount += manifest.items.length;
  }
  assert.equal(count, 11627);
  assert.equal(oldGoodCount, 1253);
  assert.equal(report.tokenCount, count);
});

async function secondaryDependencySources() {
  const saved = JSON.parse(await fs.readFile(path.join(__dirname, "artblocks", "reviews", "pass-1-curation.json"), "utf8"));
  const projects = selectProjects(saved), report = JSON.parse(await fs.readFile(path.join(DEFAULT_OUTPUT, "provenance.json"), "utf8"));
  return Promise.all([...SECONDARY_DEPENDENCY_PROFILES].map(async ([key, profile]) => {
    const project = projects.find(project => project.key === key);
    const metadata = report.collections.find(collection => collection.identity === key);
    const existing = JSON.parse(await fs.readFile(path.join(DEFAULT_OUTPUT, "Scripts", `${project.collectionId}.json`), "utf8"));
    const value = { ...source(project, metadata.dependency), script: existing.value,
      external_asset_dependency_count: metadata.externalAssets.length,
      external_asset_dependencies: metadata.externalAssets };
    return { key, profile, project, metadata, existing, value };
  }));
}

test("four exact secondary-dependency profiles preserve artist source and reject changed dependency references", async () => {
  const fixtures = await secondaryDependencySources();
  assert.equal(fixtures.length, 4);
  assert.deepEqual(fixtures.map(value => value.profile.profile), ["infinite", "timeAfterVessels", "spongenuity", "tallestPoppy"]);
  for (const { profile, project, existing, value } of fixtures) {
    const script = createScript(project, value);
    assert.equal(script.kind, existing.kind);
    assert.equal(script.value, existing.value);
    assert.equal(script.collectionIdOverride, existing.collectionIdOverride);
    assert.equal(script.secondaryDependencyProfile, profile.profile);
    assert.deepEqual(script.additionalLibraries, profile.additionalLibraries);
    assert.equal(script.requiresInitialCanvas, profile.requiresInitialCanvas);
    assert.throws(() => createScript(project, { ...value,
      script: value.script.replace(profile.sourceReferences[0], "changed-dependency-reference") }), /Secondary dependency profile no longer matches/u);
    if (profile.externalAssetCID) {
      assert.throws(() => createScript(project, { ...value, external_asset_dependencies: [
        { ...value.external_asset_dependencies[0], cid: "changed-asset-cid" },
      ] }), /Secondary dependency profile no longer matches/u);
    }
    const other = selectProjects(registry({ [`1:${address}:999`]: entry(`1:${address}:999`, profile.name) }))[0];
    const otherScript = createScript(other, { ...source(other, value.dependency_name_and_version), script: value.script });
    assert.equal(otherScript.secondaryDependencyProfile, undefined);
    assert.equal(otherScript.additionalLibraries, undefined);
  }
});

test("secondary-dependency metadata and provenance reproduce without modifying source bytes or token selections", async t => {
  const fixtures = await secondaryDependencySources();
  const f = await fixture(t, registry(Object.fromEntries(fixtures.map(({ key, profile }) => [key, entry(key, profile.name)]))));
  for (const { key, value } of fixtures) f.sources.set(key, value);
  const plan = await planPreview(f);
  assert.equal(plan.report.collectionCount, 4);
  assert.equal(plan.report.tokenCount, 8);
  for (const { key, profile, existing, metadata } of fixtures) {
    const project = f.projects.find(project => project.key === key);
    const script = JSON.parse(plan.files.get(`Scripts/${project.collectionId}.json`));
    const recorded = plan.report.collections.find(collection => collection.identity === key);
    assert.equal(script.value, existing.value);
    assert.equal(recorded.secondaryDependencyProfile, profile.profile);
    assert.deepEqual(recorded.additionalLibraries, profile.additionalLibraries);
    assert.equal(recorded.sourceScriptSHA256, metadata.sourceScriptSHA256);
    const tokens = JSON.parse(plan.files.get(`Tokens/${project.collectionId}.json`));
    assert.deepEqual(tokens.items.map(token => token.id), project.tokenIds);
  }
  await applyPreview(plan);
  assert.equal(await applyPreview(await planPreview(f)), false);
});

async function frozenFixture(t) {
  const key = "1:0x0000006693e685fcfc54c9d423b5e321b4a15192:0";
  const f = await fixture(t, registry({ [key]: entry(key, "Hatches"), [`1:${address}:9`]: entry(`1:${address}:9`, "Unchanged") }));
  const project = f.projects.find(project => project.key === key);
  const compatibility = JSON.parse(await fs.readFile(DEFAULT_COMPATIBILITY, "utf8"));
  const dependency = { index: 0, dependency_type: "ONCHAIN", bytecode_address: compatibility.staticFirst[key].expectedDependency.bytecode_address };
  const value = { ...source(project, "p5@1.9.0"), external_asset_dependency_count: 1,
    external_asset_dependencies: [{ cid: "", data: "#web3call_contract#", ...dependency }] };
  f.sources.set(key, value);
  await applyPreview(await planPreview(f));
  const snapshot = { version: 1, source: "https://generator.artblocks.io", capturedAt: "2026-09-12T00:00:00+00:00", collections: {
    [key]: { name: project.name, sourceScriptSHA256: createHash("sha256").update(value.script).digest("hex"), dependency,
      tokens: Object.fromEntries(f.tokens.get(key).map((token, index) => [token.token_id, { hash: token.hash,
        parameters: index === 0 ? {} : { Brush: "A literal string", empty: "", escaped: "</script>\n&" },
        sourceURL: `https://generator.artblocks.io/${project.chainId}/${project.address}/${token.token_id}`,
        fetchedAt: "2026-09-12T00:00:00+00:00" }])) }
  } };
  return { ...f, key, project, snapshot, parameterSnapshot: snapshot };
}

test("frozen parameters apply offline with complete coverage, exact empty/string values, and unchanged artist resources", async t => {
  const f = await frozenFixture(t), before = await readTree(f.output), requestsBefore = f.requests.length;
  const plan = await planFrozenParameters(f);
  assert.equal(f.requests.length, requestsBefore);
  assert.equal(plan.report.contractParameters.collectionCount, 1);
  assert.equal(plan.report.contractParameters.tokenCount, 2);
  assert.equal(plan.report.staticFirstCount, 0);
  const changed = [...plan.files].filter(([file, content]) => before.get(file) !== content).map(([file]) => file).sort();
  assert.deepEqual(changed, [`Tokens/${f.project.collectionId}.json`, "items.json", "provenance.json"].sort());
  const catalog = JSON.parse(plan.files.get("items.json"));
  assert.equal(catalog.find(item => item.reviewIdentity === f.key).previewStaticReason, undefined);
  const oldTokens = JSON.parse(before.get(`Tokens/${f.project.collectionId}.json`));
  const tokens = JSON.parse(plan.files.get(`Tokens/${f.project.collectionId}.json`));
  assert.deepEqual(tokens.items.map(({ previewContractParameters, ...token }) => token), oldTokens.items);
  assert.deepEqual(tokens.items.map(token => token.previewContractParameters), [{}, { Brush: "A literal string", empty: "", escaped: "</script>\n&" }]);
  const scriptPath = path.join(f.output, "Scripts", `${f.project.collectionId}.json`), originalStat = await fs.stat(scriptPath);
  await applyPreview(plan);
  const finalStat = await fs.stat(scriptPath);
  assert.equal(finalStat.ino, originalStat.ino);
  assert.equal(finalStat.mtimeMs, originalStat.mtimeMs);
  assert.ok(sameTree(await readTree(f.output), plan.files));
  assert.equal(await applyPreview(await planFrozenParameters(f)), false);
  const fullBuild = await planPreview(f);
  assert.ok(sameTree(fullBuild.files, plan.files));
});

test("invalid, partial, stale, or foreign snapshots cannot publish any resource changes", async t => {
  const f = await frozenFixture(t), before = await readTree(f.output);
  const firstID = f.project.tokenIds[0];
  for (const mutate of [
    snapshot => { delete snapshot.collections[f.key].tokens[firstID]; },
    snapshot => { snapshot.collections[f.key].tokens.extra = snapshot.collections[f.key].tokens[firstID]; },
    snapshot => { snapshot.collections[f.key].tokens[firstID].hash = `0x${"f".repeat(64)}`; },
    snapshot => { snapshot.collections[f.key].sourceScriptSHA256 = "f".repeat(64); },
    snapshot => { snapshot.collections[f.key].dependency.index = 1; },
    snapshot => { snapshot.collections[f.key].tokens[firstID].parameters = { value: 1 }; },
    snapshot => { snapshot.collections[f.key].tokens[firstID].parameters = []; },
    snapshot => { snapshot.collections[f.key].tokens[firstID].sourceURL += "?different-token=1"; },
    snapshot => { snapshot.collections[f.key].tokens[firstID].sourceURL = "https://example.test/"; },
    snapshot => { snapshot.collections[f.key].tokens[firstID].fetchedAt = "not-a-date"; },
    snapshot => { snapshot.collections[`1:${address}:9`] = snapshot.collections[f.key]; },
  ]) {
    const snapshot = structuredClone(f.snapshot);
    mutate(snapshot);
    await assert.rejects(planFrozenParameters({ ...f, parameterSnapshot: snapshot }), /contract parameter|Contract parameter|parameters|Parameter source|parameter source/iu);
    assert.ok(sameTree(before, await readTree(f.output)));
  }
});

test("parameter publication failure rolls back while preserving hard-linked unchanged sources", async t => {
  const f = await frozenFixture(t), plan = await planFrozenParameters(f), before = await readTree(f.output);
  const scriptPath = path.join(f.output, "Scripts", `${f.project.collectionId}.json`), stat = await fs.stat(scriptPath);
  const failingFS = { ...fs, rename: async (from, to) => {
    if (path.basename(from) === "new") throw new Error("Frozen publication failed");
    return fs.rename(from, to);
  } };
  await assert.rejects(applyPreview(plan, failingFS), /Frozen publication failed/u);
  assert.ok(sameTree(before, await readTree(f.output)));
  assert.equal((await fs.stat(scriptPath)).ino, stat.ino);
  assert.equal((await fs.stat(scriptPath)).mtimeMs, stat.mtimeMs);
});

test("parameter-only CLI performs no API requests and remains idempotent", async t => {
  const f = await frozenFixture(t), before = await readTree(f.output), messages = [];
  const dependencies = { ...f, request: async () => { throw new Error("Offline parameter refresh requested the API"); }, log: value => messages.push(value) };
  await main(["--parameters-only", "--dry-run"], dependencies);
  assert.ok(sameTree(before, await readTree(f.output)));
  assert.match(messages.at(-1), /^Dry run:/u);
  const result = await main(["--parameters-only", "--apply"], dependencies);
  assert.equal(result.changed, true);
  const repeated = await main(["--parameters-only", "--apply"], dependencies);
  assert.equal(repeated.changed, false);
  assert.match(messages.at(-1), /resources unchanged/u);
});

test("removing a snapshot restores static defaults and removes frozen token fields deterministically", async t => {
  const f = await frozenFixture(t);
  await applyPreview(await planFrozenParameters(f));
  const snapshot = { ...f.snapshot, collections: {} };
  const plan = await planFrozenParameters({ ...f, parameterSnapshot: snapshot });
  assert.equal(plan.report.staticFirstCount, 1);
  assert.equal(plan.report.contractParameters.collectionCount, 0);
  assert.ok(JSON.parse(plan.files.get("items.json")).find(item => item.reviewIdentity === f.key).previewStaticReason);
  const tokens = JSON.parse(plan.files.get(`Tokens/${f.project.collectionId}.json`));
  assert.ok(tokens.items.every(token => token.previewContractParameters === undefined));
});

test("drawing and price-history snapshot validation rejects silent truncation while preserving valid omissions", async () => {
  const snapshot = JSON.parse(await fs.readFile(DEFAULT_PARAMETERS, "utf8"));
  const drawingID = "1:0xcfa6a2d5bc2a77c0cdd3046e09da21e45d1df0f1:1";
  const poolID = "1:0xaa00b2b2db36b8f8004a9aa96f0012005d92b300:0";
  const drawing = Object.values(snapshot.collections[drawingID].tokens)[0].parameters;
  const pool = Object.values(snapshot.collections[poolID].tokens)[0].parameters;
  validateRequiredContractParameters(drawingID, drawing, "drawing");
  validateRequiredContractParameters(poolID, pool, "pool");
  for (const mutate of [
    values => { delete values.p1; },
    values => { values.p2 = values.p2.slice(0, -4); },
    values => { values.p0 = "invalid-base64"; },
    values => { values.week = "53"; },
    values => { values.chaos = "101"; },
  ]) {
    const values = { ...drawing }; mutate(values);
    assert.throws(() => validateRequiredContractParameters(drawingID, values, "drawing"), /frozen drawing/u);
  }
  for (const mutate of [values => { delete values.priceHistory0; }, values => { values.priceHistoryLength = "0"; }, values => { values.priceHistory1 = "NaN"; }]) {
    const values = { ...pool }; mutate(values);
    assert.throws(() => validateRequiredContractParameters(poolID, values, "pool"), /frozen price history/u);
  }
});

test("required chain values cannot silently fall back while optional artist controls and empty objects remain valid", async () => {
  const ddustID = "1:0x00000053a75735169ad44f6760c11f3d3d3b3544:0";
  const giftID = "1:0x000000dc68934ed27fd11e32491cdf6717acaf21:1";
  const ddust = { blockHeight: "25957314", projectInvocations: "500" };
  validateRequiredContractParameters(ddustID, ddust, "DDUST");
  validateRequiredContractParameters(giftID, { blockTimestamp: "1789167851" }, "Gift of Time");
  validateRequiredContractParameters("1:0x0000006693e685fcfc54c9d423b5e321b4a15192:0", {}, "Hatches");
  validateRequiredContractParameters("1:0xababababab20053426ad1c782de9ea8444358070:4", {}, "Diggly");
  for (const values of [{}, { blockHeight: ddust.blockHeight }, { projectInvocations: ddust.projectInvocations },
    { ...ddust, blockHeight: "NaN" }, { ...ddust, blockHeight: "-1" }, { ...ddust, projectInvocations: "0" }]) {
    assert.throws(() => validateRequiredContractParameters(ddustID, values, "DDUST"), /frozen block parameters/u);
  }
  for (const value of [undefined, "", "NaN", "Infinity", "1000000000"]) {
    assert.throws(() => validateRequiredContractParameters(giftID, { blockTimestamp: value }, "Gift"), /frozen block timestamp/u);
  }
  const snapshot = JSON.parse(await fs.readFile(DEFAULT_PARAMETERS, "utf8"));
  const firstDDUST = Object.values(snapshot.collections[ddustID].tokens)[0];
  delete firstDDUST.parameters.blockHeight;
  await assert.rejects(planFrozenParameters({ output: DEFAULT_OUTPUT, parameterSnapshot: snapshot }), /frozen block parameters/u);
});

test("committed snapshot covers all 135 saved tokens of the six selected contract-parameter collections", async () => {
  const saved = JSON.parse(await fs.readFile(path.join(__dirname, "artblocks", "reviews", "pass-1-curation.json"), "utf8"));
  const compatibility = JSON.parse(await fs.readFile(DEFAULT_COMPATIBILITY, "utf8"));
  const snapshot = validateContractParameterSnapshot(JSON.parse(await fs.readFile(DEFAULT_PARAMETERS, "utf8")), selectProjects(saved), compatibility);
  assert.deepEqual(Object.values(snapshot.collections).map(collection => collection.name).sort(),
    ["DDUST", "Hatches", "Gift of Time", "pool party", "Diggly Collects All", "degenerative"].sort());
  assert.equal(Object.values(snapshot.collections).reduce((count, collection) => count + Object.keys(collection.tokens).length, 0), 135);
  const plan = await planFrozenParameters({ output: DEFAULT_OUTPUT });
  assert.ok(sameTree(plan.before, plan.files));
  assert.equal(plan.report.staticFirstCount, 4);
  assert.equal(plan.report.contractParameters.tokenCount, 135);
  assert.ok(plan.report.collections.filter(collection => collection.contractParameterTokenCount).every(collection => !collection.staticReason));
});
