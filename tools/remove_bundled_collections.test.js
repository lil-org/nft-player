"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const REMOVER_PATH = path.resolve(__dirname, "remove_bundled_collections.js");
const ADDRESS = "0x1111111111111111111111111111111111111111";

function createFixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "nft-player-remove-bundle-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const coversPath = path.join(root, "Covers.xcassets");
  const items = [
    { address: ADDRESS, chain: "ethereum", internal_slug: "first_collection", name: "First Collection" },
    { address: ADDRESS, chain: "base", internal_slug: "second_collection", name: "Second Collection" },
  ];
  const itemsPath = path.join(root, "items.json");
  fs.writeFileSync(itemsPath, JSON.stringify(items));
  for (const item of items) {
    for (const directory of ["Tokens", "Scripts"]) {
      fs.mkdirSync(path.join(root, directory), { recursive: true });
      fs.writeFileSync(path.join(root, directory, `${item.internal_slug}.json`), "{}");
    }
    fs.mkdirSync(path.join(coversPath, `${item.internal_slug}.imageset`), { recursive: true });
  }
  return { root, coversPath, itemsPath, items };
}

function runRemover(fixture, selector, apply = true) {
  return spawnSync(process.execPath, [
    REMOVER_PATH, apply ? "--apply" : "--dry-run",
    "--bundle", fixture.root, "--covers", fixture.coversPath, selector,
  ], { encoding: "utf8", timeout: 5000 });
}

test("removing by slug deletes its resources and preserves a collection with the same address on another chain", (t) => {
  const fixture = createFixture(t);
  const result = runRemover(fixture, "first_collection");
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(fs.readFileSync(fixture.itemsPath, "utf8")), [fixture.items[1]]);
  for (const directory of ["Tokens", "Scripts"]) {
    assert.deepEqual(fs.readdirSync(path.join(fixture.root, directory)), ["second_collection.json"]);
  }
  assert.deepEqual(fs.readdirSync(fixture.coversPath), ["second_collection.imageset"]);
});

test("removal by name resolves slug resources in a read-only dry run", (t) => {
  const fixture = createFixture(t);
  const original = fs.readFileSync(fixture.itemsPath, "utf8");
  const result = runRemover(fixture, "First Collection", false);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Tokens\/first_collection\.json/u);
  assert.match(result.stdout, /Scripts\/first_collection\.json/u);
  assert.equal(fs.readFileSync(fixture.itemsPath, "utf8"), original);
  assert.equal(fs.existsSync(path.join(fixture.root, "Tokens", "first_collection.json")), true);
});

test("ambiguous address selectors fail before deleting resources", (t) => {
  const fixture = createFixture(t);
  const original = fs.readFileSync(fixture.itemsPath, "utf8");
  const result = runRemover(fixture, ADDRESS);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /matched multiple catalog entries/u);
  assert.equal(fs.readFileSync(fixture.itemsPath, "utf8"), original);
});

test("exact slug selectors disambiguate collections with the same display name", (t) => {
  const fixture = createFixture(t);
  for (const [index, slug] of ["balance", "balance_2"].entries()) {
    const item = fixture.items[index];
    for (const directory of ["Tokens", "Scripts"]) {
      fs.renameSync(
        path.join(fixture.root, directory, `${item.internal_slug}.json`),
        path.join(fixture.root, directory, `${slug}.json`)
      );
    }
    fs.renameSync(
      path.join(fixture.coversPath, `${item.internal_slug}.imageset`),
      path.join(fixture.coversPath, `${slug}.imageset`)
    );
    item.internal_slug = slug;
    item.name = "Balance";
  }
  const original = JSON.stringify(fixture.items);
  fs.writeFileSync(fixture.itemsPath, original);

  const ambiguousNameResult = runRemover(fixture, "Balance");
  assert.equal(ambiguousNameResult.status, 1);
  assert.match(ambiguousNameResult.stderr, /matched multiple catalog entries/u);
  assert.equal(fs.readFileSync(fixture.itemsPath, "utf8"), original);

  const slugResult = runRemover(fixture, "balance");
  assert.equal(slugResult.status, 0, slugResult.stderr);
  assert.deepEqual(JSON.parse(fs.readFileSync(fixture.itemsPath, "utf8")), [fixture.items[1]]);
  for (const directory of ["Tokens", "Scripts"]) {
    assert.deepEqual(fs.readdirSync(path.join(fixture.root, directory)), ["balance_2.json"]);
  }
  assert.deepEqual(fs.readdirSync(fixture.coversPath), ["balance_2.imageset"]);
});
