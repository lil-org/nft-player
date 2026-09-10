"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const { runInNewContext } = require("node:vm");
const { PROJECTS, DEFACEMENT_ADAPTER, DEFACEMENT_DISPLAY_TUNING, expandManifest,
  validateProject, validateHashes, createScript, convertCatalog, planBundle, applyPlan, main } = require("./bundle_artblocks_scripts");

const hash = invocation => `0x${(invocation + 1).toString(16).padStart(64, "0")}`;
const tokenId = (project, invocation) => String(BigInt(project.projectId) * 1000000n + BigInt(invocation));

function apiToken(project, invocation) {
  const id = tokenId(project, invocation);
  return { id: `${project.address}-${id}`, token_id: id, project_id: project.apiId,
    chain_id: project.chainId, contract_address: project.address, invocation, hash: hash(invocation) };
}

function sourceProject(project) {
  return { id: project.apiId, project_id: project.projectId, chain_id: project.chainId,
    contract_address: project.address, name: project.name, artist_name: `Artist for ${project.name}`,
    script: 'function setup() { return tokenData.hash; }\nfunction draw() { return "complete script"; }\n',
    script_count: 4, script_type_and_version: project.dependency, dependency_name_and_version: project.dependency,
    external_asset_dependency_count: project.externalAssetCid ? 1 : 0,
    external_asset_dependencies: project.externalAssetCid ? [{ cid: project.externalAssetCid, dependency_type: "IPFS" }] : [] };
}

function catalogEntry(project) {
  return { ...(project.legacySuffix ? {} : { abId: project.projectId }), address: project.address,
    chain: "ethereum", chainId: 1, collectionId: project.legacySuffix ?? `legacy-${project.projectId}`,
    name: project.name, tokenCount: project.count, standardThumbsPathsAvailable: true,
    internal_slug: project.name.toLowerCase().replaceAll(" ", "_"), artists: ["artist"], iosCollectionBrowserColumnCount: 2 };
}

async function snapshot(directory) {
  const result = {};
  async function walk(current) {
    for (const entry of await fs.readdir(current, { withFileTypes: true })) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) await walk(full);
      else result[path.relative(directory, full)] = await fs.readFile(full, "utf8");
    }
  }
  await walk(directory);
  return result;
}

async function fixture(t, count = 2, selected = PROJECTS) {
  const bundle = await fs.mkdtemp(path.join(os.tmpdir(), "artblocks-scripts-test-"));
  t.after(() => fs.rm(bundle, { recursive: true, force: true }));
  const projects = selected.map(project => ({ ...project, count }));
  await fs.mkdir(path.join(bundle, "Tokens"));
  await fs.mkdir(path.join(bundle, "Scripts"));
  const flore = { abId: "29", address: "0x7c3ea2b7b3befa1115ab51c09f0c9f245c500b18", name: "Flore Perdue", tokenCount: 100, artists: ["linda_dounia"] };
  const staticProjects = [
    { name: "Fragments of an Infinite Field", abId: "159", tokenCount: 1024 },
    { name: "Letters to My Future Self", abId: "174", tokenCount: 1000 },
  ].map(item => ({ ...item, address: PROJECTS[0].address, chain: "ethereum", chainId: 1 }));
  const catalog = [...projects.map(catalogEntry), ...staticProjects, flore];
  const catalogText = JSON.stringify(catalog, null, 2).replaceAll('": ', '" : ') + "\n";
  await fs.writeFile(path.join(bundle, "items.json"), catalogText);
  await fs.writeFile(path.join(bundle, "Tokens", "flore.json"), '{"items":[["29000000",0,"flore.png"]]}');
  for (const project of projects) {
    const invocations = Array.from({ length: count }, (_, index) => count - index - 1);
    const manifest = { defaultFileExtension: "png", urlPrefixes: ["https://cdn.lil.org/player/fixture/"],
      items: invocations.map(invocation => [tokenId(project, invocation), 0, `${invocation}.png`]),
      thumbnailAspectRatios: [[3, 4], [1, 1]], thumbnailAspectRatioOverrides: [[0, 1]],
      hasMid: false, isComplete: true, tmpFiles: ["keep-me"] };
    await fs.writeFile(path.join(bundle, "Tokens", `${project.collectionId}.json`), JSON.stringify(manifest));
  }
  for (const item of staticProjects) {
    await fs.writeFile(path.join(bundle, "Tokens", `${item.address}${item.abId}.json`), JSON.stringify({
      defaultFileExtension: "png", urlPrefixes: ["https://cdn.lil.org/player/static/"],
      items: [[`${item.abId}000000`, 0, "0.png"]], thumbnailAspectRatios: [[1, 1]],
    }));
  }
  const requests = [];
  const request = async (query, variables) => {
    requests.push({ query, variables });
    const project = projects.find(project => project.apiId === (variables.id ?? variables.project));
    assert.ok(project, "request must target one of the explicit projects");
    assert.equal(variables.chain, 1);
    if (query.includes("query ScriptProject")) return { projects_metadata: [sourceProject(project)] };
    assert.match(query, /order_by: \[\{invocation: asc\}, \{id: asc\}\]/u);
    assert.equal(variables.address, project.address);
    const selected = new Set(variables.ids);
    const tokens = Array.from({ length: project.count + 3 }, (_, i) => apiToken(project, i)).filter(token => selected.has(token.token_id));
    return { tokens_metadata: tokens.slice(variables.offset, variables.offset + 200) };
  };
  return { bundle, projects, catalog, catalogText, request, requests };
}

test("explicit mapping contains seven projects and exactly 4,461 original tokens", () => {
  assert.equal(PROJECTS.length, 7);
  assert.equal(PROJECTS.reduce((total, project) => total + project.count, 0), 4461);
  assert.equal(new Set(PROJECTS.map(project => project.apiId)).size, 7);
  assert.ok(PROJECTS.every(project => !["Flore Perdue", "Fragments of an Infinite Field", "Letters to My Future Self"].includes(project.name)));
});

test("conversion preserves token order, CDN URLs, names and manifest metadata, leaving all three intentionally static collections untouched", async t => {
  const f = await fixture(t);
  const objectPath = path.join(f.bundle, "Tokens", `${f.projects[0].collectionId}.json`);
  const original = JSON.parse(await fs.readFile(objectPath, "utf8"));
  original.items = expandManifest(original, f.projects[0]);
  original.items[0].name = "Retained custom title";
  original.items[0].sh = "short identifier";
  await fs.writeFile(objectPath, JSON.stringify(original));
  const before = await snapshot(f.bundle);
  const plan = await planBundle(f);
  assert.deepEqual(await snapshot(f.bundle), before);
  await applyPlan(plan);
  const after = await snapshot(f.bundle);
  assert.equal(after["Tokens/flore.json"], before["Tokens/flore.json"]);
  const catalog = JSON.parse(after["items.json"]);
  for (let index = 0; index < f.projects.length; index++) {
    const entry = { ...f.catalog[index] };
    delete entry.tokenCount;
    assert.deepEqual(catalog[index], entry);
    const project = f.projects[index];
    const name = `Tokens/${project.collectionId}.json`;
    const oldManifest = JSON.parse(before[name]), nextManifest = JSON.parse(after[name]);
    const oldItems = expandManifest(oldManifest, project);
    assert.deepEqual(nextManifest.items.map(({ hash, ...item }) => item), oldItems);
    assert.deepEqual(nextManifest.items.map(item => item.hash), [hash(1), hash(0)]);
    const metadata = { ...oldManifest }; delete metadata.items; delete metadata.urlPrefixes;
    const nextMetadata = { ...nextManifest }; delete nextMetadata.items;
    assert.deepEqual(nextMetadata, metadata);
    assert.equal(nextManifest.urlPrefixes, undefined);
  }
  assert.deepEqual(catalog.slice(f.projects.length), f.catalog.slice(f.projects.length));
  for (const item of f.catalog.slice(f.projects.length, -1)) {
    const stem = `${item.address}${item.abId}`;
    assert.equal(after[`Tokens/${stem}.json`], before[`Tokens/${stem}.json`]);
    assert.equal(after[`Scripts/${stem}.json`], undefined);
  }
  assert.equal(plan.report.collections.length, 7);
  assert.equal(plan.report.collections[0].scriptCount, 4);
});

test("catalog removes only the seven tokenCount lines without reformatting existing entries", async t => {
  const f = await fixture(t);
  const expected = f.catalogText.split("\n").filter(line => line !== '    "tokenCount" : 2,').join("\n");
  assert.equal(convertCatalog(f.catalogText, f.projects), expected);
  const compact = JSON.stringify(f.catalog);
  const converted = JSON.parse(convertCatalog(compact, f.projects));
  assert.ok(converted.slice(0, 7).every(entry => !Object.hasOwn(entry, "tokenCount")));
  assert.equal(converted.at(-1).tokenCount, 100);
});

test("Parnassus keeps its legacy catalog identity and script filename while exposing project 2", () => {
  const project = PROJECTS.find(project => project.name === "Parnassus");
  const script = createScript(project, sourceProject(project));
  assert.equal(script.abId, "2");
  assert.equal(script.collectionIdOverride, project.address + "71f6ddfea755d56de211919de8fc87ec");
  for (const other of PROJECTS.filter(p => p !== project)) assert.equal(createScript(other, sourceProject(other)).collectionIdOverride, undefined);
});

test("Parnassus fits only the main canvas and preserves the original renderer and rotation controls", () => {
  const project = PROJECTS.find(project => project.name === "Parnassus");
  const source = sourceProject(project);
  const script = createScript(project, source);
  assert.equal(script.value, source.script);
  const attached = [];
  runInNewContext(script.nftPlayerDisplayTuning, { document: {
    createElement: tag => ({ tag }),
    head: { appendChild: element => attached.push(element) },
  } });
  assert.equal(attached.length, 1);
  assert.equal(attached[0].tag, "style");
  const selectors = [...attached[0].textContent.matchAll(/([^{}]+)\{/gu)].map(match => match[1].trim());
  assert.deepEqual(selectors, ["#defaultCanvas0", '#defaultCanvas0[style*="rotate(-90deg)"]']);
});

test("Defacement prepends only the approved CDN adapter and uses the display-tuning hook", () => {
  const project = PROJECTS.find(project => project.externalAssetCid);
  const source = sourceProject(project);
  const script = createScript(project, source);
  assert.equal(script.kind, "js");
  assert.equal(script.value, DEFACEMENT_ADAPTER + source.script);
  assert.equal(script.nftPlayerDisplayTuning, DEFACEMENT_DISPLAY_TUNING);
  assert.match(DEFACEMENT_ADAPTER, /https:\/\/cdn\.lil\.org\/player\/instructions_for_defacement\//u);
  assert.match(DEFACEMENT_ADAPTER, /cid: "background.jpg"/u);
  for (const other of PROJECTS.filter(p => p !== project)) assert.equal(createScript(other, sourceProject(other)).value, sourceProject(other).script);
});

test("stable API pagination selects exact existing IDs and ignores extra minted tokens", async t => {
  const f = await fixture(t, 205, [PROJECTS[0]]);
  const plan = await planBundle(f);
  const pages = f.requests.filter(request => request.query.includes("ScriptTokens"));
  assert.deepEqual(pages.map(page => page.variables.offset), [0, 200]);
  assert.ok(pages.every(page => page.variables.ids.length === 205));
  assert.equal(plan.report.tokenCount, 205);
  const output = JSON.parse(plan.files.find(file => file.file.includes("/Tokens/")).after);
  assert.equal(output.items[0].id, tokenId(f.projects[0], 204));
  assert.equal(output.items.at(-1).id, tokenId(f.projects[0], 0));
});

for (const [name, mutate, pattern] of [
  ["missing", tokens => tokens.pop(), /Missing API token hashes/u],
  ["duplicate", tokens => { tokens[1] = tokens[0]; }, /Duplicate API token/u],
  ["invalid hash", tokens => { tokens[0].hash = "0x1234"; }, /Invalid token hash/u],
  ["wrong chain", tokens => { tokens[0].chain_id = 42161; }, /identity mismatch/u],
  ["wrong contract", tokens => { tokens[0].contract_address = PROJECTS.at(-1).address; }, /identity mismatch/u],
  ["wrong project", tokens => { tokens[0].project_id = PROJECTS[1].apiId; }, /identity mismatch/u],
  ["wrong invocation", tokens => { tokens[0].invocation = 99; }, /identity mismatch/u],
  ["unexpected", tokens => { tokens[1] = apiToken(PROJECTS[0], 2); }, /Unexpected API token/u],
]) {
  test(`rejects ${name} API token data`, () => {
    const project = PROJECTS[0];
    const tokens = [apiToken(project, 0), apiToken(project, 1)];
    const ids = tokens.map(token => token.token_id);
    mutate(tokens);
    assert.throws(() => validateHashes(project, ids, tokens), pattern);
  });
}

test("invalid final project stops the entire plan before any file is written", async t => {
  const f = await fixture(t);
  const before = await snapshot(f.bundle);
  const request = async (query, variables) => {
    const data = await f.request(query, variables);
    if (variables.id === f.projects.at(-1).apiId) data.projects_metadata[0].script = "";
    return data;
  };
  await assert.rejects(planBundle({ ...f, request }), /Missing complete artist script/u);
  assert.deepEqual(await snapshot(f.bundle), before);
});

test("rejects changed dependencies, external assets, invalid syntax and conflicting stored hashes", async t => {
  const project = PROJECTS[0], source = sourceProject(project);
  assert.throws(() => validateProject(project, { ...source, dependency_name_and_version: "p5@2.0.0" }), /Unsupported dependency/u);
  assert.throws(() => validateProject(project, { ...source, external_asset_dependency_count: 1, external_asset_dependencies: [{ cid: "new", dependency_type: "IPFS" }] }), /Unexpected external/u);
  assert.throws(() => validateProject(project, { ...source, script: "const invalid =" }), SyntaxError);
  const f = await fixture(t, 2, [project]);
  const file = path.join(f.bundle, "Tokens", `${project.collectionId}.json`);
  const manifest = JSON.parse(await fs.readFile(file, "utf8"));
  manifest.items = expandManifest(manifest, f.projects[0]);
  manifest.items[0].hash = hash(99);
  await fs.writeFile(file, JSON.stringify(manifest));
  await assert.rejects(planBundle(f), /Existing hash changed/u);
});

test("default CLI dry-run writes no bundle files or report", async t => {
  const f = await fixture(t);
  const before = await snapshot(f.bundle);
  const report = path.join(f.bundle, "report.json");
  const result = await main(["--bundle", f.bundle, "--report", report], { projects: f.projects, request: f.request, log: () => {} });
  assert.equal(result.changed.length, 15);
  assert.deepEqual(await snapshot(f.bundle), before);
});

test("reapplying is deterministic and does not rewrite identical files", async t => {
  const f = await fixture(t);
  const report = path.join(f.bundle, "report.json");
  const first = await planBundle(f);
  assert.equal((await applyPlan(first, report)).length, 15);
  const before = await snapshot(f.bundle);
  const stat = await fs.stat(path.join(f.bundle, "items.json"));
  const second = await planBundle(f);
  assert.deepEqual(second.report, first.report);
  assert.deepEqual(await applyPlan(second, report), []);
  assert.deepEqual(await snapshot(f.bundle), before);
  assert.equal((await fs.stat(path.join(f.bundle, "items.json"))).mtimeMs, stat.mtimeMs);
});

test("apply refuses a concurrent local change before writing any planned file", async t => {
  const f = await fixture(t);
  const plan = await planBundle(f);
  const last = plan.files.at(-1);
  await fs.writeFile(last.file, "other editor changed this script");
  const before = await snapshot(f.bundle);
  await assert.rejects(applyPlan(plan), /Bundle changed during validation/u);
  assert.deepEqual(await snapshot(f.bundle), before);
});

test("project fetch concurrency never exceeds two requests", async t => {
  const f = await fixture(t);
  let active = 0, maximum = 0;
  const request = async (query, variables) => {
    active++;
    maximum = Math.max(maximum, active);
    await new Promise(resolve => setTimeout(resolve, 2));
    try { return await f.request(query, variables); }
    finally { active--; }
  };
  await planBundle({ ...f, request });
  assert.equal(maximum, 2);
});
