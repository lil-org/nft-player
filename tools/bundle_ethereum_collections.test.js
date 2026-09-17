"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const {
  decodeAspectRatioMetadata,
  tokenIdsFromPayload,
} = require("./thumbnail_aspect_ratios");

const BUNDLER_PATH = path.resolve(__dirname, "bundle_ethereum_collections.js");
const LOWERCASE_ID = "0xec0a7a26456b8451aefc4b00393ce1beff5eb3e9";
const CHECKSUM_ID = "0xEC0a7A26456B8451aefc4b00393ce1BefF5eB3e9";

function createFixture(t, {
  catalogColumnCount,
  includeTokenManifest = true,
  internalSlug = "allstarz",
} = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "nft-player-ethereum-bundler-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));

  const bundlePath = path.join(root, "Suggested.bundle");
  const tokensPath = path.join(bundlePath, "Tokens");
  const coversPath = path.join(root, "covers");
  const itemsPath = path.join(bundlePath, "items.json");
  const tokenPath = path.join(tokensPath, `${internalSlug}.json`);
  const reportPath = path.join(root, "reports", "report.md");
  const jsonReportPath = path.join(root, "reports", "report.json");
  fs.mkdirSync(tokensPath, { recursive: true });
  fs.mkdirSync(coversPath, { recursive: true });

  const itemsText = `${JSON.stringify([{
    address: CHECKSUM_ID,
    chain: "ethereum",
    chainId: 1,
    name: "Allstarz",
    tokenCount: 2,
    internal_slug: internalSlug,
    ...(catalogColumnCount == null
      ? {}
      : { iosCollectionBrowserColumnCount: catalogColumnCount }),
  }], null, 2)}\n`;
  const tokenText = `${JSON.stringify({
    hasMid: false,
    tmp_files: { "1": "original.png" },
    defaultFileExtension: "png",
    urlPrefixes: ["https://old.example/"],
    items: [["2", 0, "2.png"], ["1", 0, "1.png"]],
    thumbnailAspectRatios: [[16, 9], [4, 3]],
    thumbnailAspectRatioOverrides: [[1, 1]],
  })}\n`;
  fs.writeFileSync(itemsPath, itemsText);
  if (includeTokenManifest) {
    fs.writeFileSync(tokenPath, tokenText);
  }

  return {
    bundlePath,
    coversPath,
    itemsPath,
    itemsText,
    jsonReportPath,
    reportPath,
    tokenPath,
    tokenText,
    tokensPath,
  };
}

function runBundler(fixture, {
  injectTokenCollision = false,
  apply = true,
  skipCovers = true,
} = {}) {
  const argv = [
    process.execPath,
    BUNDLER_PATH,
    "--api-key", "test",
    "--delay-ms", "0",
    "--max-retries", "0",
    "--timeout-ms", "1000",
    apply ? "--apply" : "--dry-run",
    "--bundle", fixture.bundlePath,
    "--covers", fixture.coversPath,
    "--report", fixture.reportPath,
    "--json-report", fixture.jsonReportPath,
    ...(skipCovers ? ["--skip-covers"] : []),
    LOWERCASE_ID,
  ];
  const harness = `
const path = require("node:path");
const fsPromises = require("node:fs/promises");
const originalReaddir = fsPromises.readdir.bind(fsPromises);
fsPromises.readdir = async (directoryPath, ...args) => {
  const names = await originalReaddir(directoryPath, ...args);
  if (
    ${JSON.stringify(injectTokenCollision)}
    && path.resolve(directoryPath) === ${JSON.stringify(path.resolve(fixture.tokensPath))}
  ) {
    return [...names, "ALLSTARZ.json"];
  }
  return names;
};
global.fetch = async (input) => {
  const url = String(input);
  let payload;
  if (/\\/nfts(?:\\?|$)/u.test(url)) {
    payload = {
      nfts: [
        { identifier: "2", name: "Allstarz #2", image_url: "https://assets.example/2.png" },
        { identifier: "1", name: "Allstarz #1", image_url: "https://assets.example/1.png" },
      ],
      next: null,
    };
  } else if (url.includes("/collections/allstarz")) {
    payload = { name: "Allstarz", total_supply: 2 };
  } else if (url.includes("/contract/")) {
    payload = { collection: "allstarz", name: "Allstarz", total_supply: 2 };
  } else {
    throw new Error("Unexpected request: " + url);
  }
  return {
    ok: true,
    status: 200,
    headers: { get: () => null },
    text: async () => JSON.stringify(payload),
  };
};
process.argv = ${JSON.stringify(argv)};
require(${JSON.stringify(BUNDLER_PATH)});
`;

  return spawnSync(process.execPath, ["-e", harness], {
    cwd: path.resolve(__dirname, ".."),
    encoding: "utf8",
    timeout: 5000,
  });
}

test("writes slug resources while preserving checksum identity and manifest metadata", (t) => {
  const fixture = createFixture(t);
  const result = runBundler(fixture);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(
    fs.readdirSync(fixture.tokensPath),
    ["allstarz.json"]
  );

  const payload = JSON.parse(fs.readFileSync(fixture.tokenPath, "utf8"));
  assert.equal(payload.hasMid, false);
  assert.deepEqual(payload.tmp_files, { "1": "original.png" });
  assert.deepEqual(tokenIdsFromPayload(payload), ["1", "2"]);
  assert.deepEqual(decodeAspectRatioMetadata(payload), [[4, 3], [16, 9]]);

  const [item] = JSON.parse(fs.readFileSync(fixture.itemsPath, "utf8"));
  assert.equal(item.address, CHECKSUM_ID);
  assert.equal(item.iosCollectionBrowserColumnCount, 2);
});

test("preserves an explicit three-column override for a landscape collection", (t) => {
  const fixture = createFixture(t, { catalogColumnCount: 3 });
  const result = runBundler(fixture);

  assert.equal(result.status, 0, result.stderr);
  const [item] = JSON.parse(fs.readFileSync(fixture.itemsPath, "utf8"));
  assert.equal(item.iosCollectionBrowserColumnCount, 3);
});

test("creates a missing manifest using the catalog slug", (t) => {
  const fixture = createFixture(t, { includeTokenManifest: false });
  const result = runBundler(fixture);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(
    fs.readdirSync(fixture.tokensPath),
    ["allstarz.json"]
  );
  assert.ok(fs.existsSync(fixture.tokenPath));
  const [item] = JSON.parse(fs.readFileSync(fixture.itemsPath, "utf8"));
  assert.equal(
    Object.prototype.hasOwnProperty.call(item, "iosCollectionBrowserColumnCount"),
    false
  );
});

test("rejects case-colliding manifests before modifying the bundle", (t) => {
  const fixture = createFixture(t);
  const result = runBundler(fixture, { injectTokenCollision: true });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /Ambiguous token manifest/u);
  assert.equal(fs.readFileSync(fixture.tokenPath, "utf8"), fixture.tokenText);
  assert.equal(fs.readFileSync(fixture.itemsPath, "utf8"), fixture.itemsText);
});

test("rejects a cover casing conflict before modifying tokens or items", (t) => {
  const fixture = createFixture(t);
  fs.writeFileSync(path.join(fixture.coversPath, "ALLSTARZ.jpg"), "existing cover");

  const result = runBundler(fixture, { skipCovers: false });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /Filename casing mismatch for cover image/u);
  assert.equal(fs.readFileSync(fixture.tokenPath, "utf8"), fixture.tokenText);
  assert.equal(fs.readFileSync(fixture.itemsPath, "utf8"), fixture.itemsText);
});


test("dry runs preserve custom slugs and report slug cover paths without changing assets", (t) => {
  const fixture = createFixture(t, { internalSlug: "curated_allstarz" });
  const result = runBundler(fixture, { apply: false });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(fixture.itemsPath, "utf8"), fixture.itemsText);
  assert.equal(fs.readFileSync(fixture.tokenPath, "utf8"), fixture.tokenText);
  const report = JSON.parse(fs.readFileSync(fixture.jsonReportPath, "utf8"));
  assert.equal(report.collections[0].internal_slug, "curated_allstarz");
  assert.equal(report.collections[0].cover.assetId, "curated_allstarz");
  assert.equal(report.collections[0].cover.outputPath, path.join(fixture.coversPath, "curated_allstarz.jpg"));
});

test("assigns new resource slugs without colliding with existing catalog names", (t) => {
  const fixture = createFixture(t, { includeTokenManifest: false });
  fs.writeFileSync(fixture.itemsPath, JSON.stringify([{
    address: "0x1111111111111111111111111111111111111111",
    chain: "ethereum",
    name: "Previously Curated",
    internal_slug: "allstarz",
  }]));
  const originalItems = fs.readFileSync(fixture.itemsPath, "utf8");
  const dryRun = runBundler(fixture, { apply: false });
  assert.equal(dryRun.status, 0, dryRun.stderr);
  assert.equal(fs.readFileSync(fixture.itemsPath, "utf8"), originalItems);
  assert.deepEqual(fs.readdirSync(fixture.tokensPath), []);
  const dryRunReport = JSON.parse(fs.readFileSync(fixture.jsonReportPath, "utf8"));
  assert.equal(dryRunReport.collections[0].internal_slug, "allstarz_2");
  assert.equal(dryRunReport.collections[0].cover.outputPath, path.join(fixture.coversPath, "allstarz_2.jpg"));
  const result = runBundler(fixture);
  assert.equal(result.status, 0, result.stderr);
  const items = JSON.parse(fs.readFileSync(fixture.itemsPath, "utf8"));
  const imported = items.find((item) => item.address.toLowerCase() === LOWERCASE_ID);
  assert.equal(items[0].internal_slug, "allstarz");
  assert.equal(imported.internal_slug, "allstarz_2");
  assert.deepEqual(fs.readdirSync(fixture.tokensPath), ["allstarz_2.json"]);
  const report = JSON.parse(fs.readFileSync(fixture.jsonReportPath, "utf8"));
  assert.equal(report.collections[0].cover.assetId, "allstarz_2");
  assert.equal(report.collections[0].cover.outputPath, dryRunReport.collections[0].cover.outputPath);
});
