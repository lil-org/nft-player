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
  const coversPath = path.join(root, "covers");
  const items = [
    { address: ADDRESS, chain: "ethereum", internal_slug: "first_collection", name: "First Collection", script: { kind: "js" } },
    { address: ADDRESS, chain: "base", internal_slug: "second_collection", name: "Second Collection", script: { kind: "js" } },
  ];
  const itemsPath = path.join(root, "items.json");
  fs.writeFileSync(itemsPath, JSON.stringify(items));
  for (const item of items) {
    for (const [directory, extension] of [["Tokens", "json"], ["Scripts", "js"]]) {
      fs.mkdirSync(path.join(root, directory), { recursive: true });
      fs.writeFileSync(path.join(root, directory, `${item.internal_slug}.${extension}`), directory === "Scripts" ? "void 0;" : "{}");
    }
    fs.mkdirSync(coversPath, { recursive: true });
    fs.writeFileSync(path.join(coversPath, `${item.internal_slug}.jpg`), "existing cover");
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
  for (const [directory, extension] of [["Tokens", "json"], ["Scripts", "js"]]) {
    assert.deepEqual(fs.readdirSync(path.join(fixture.root, directory)), [`second_collection.${extension}`]);
  }
  assert.deepEqual(fs.readdirSync(fixture.coversPath), ["second_collection.jpg"]);
});

test("removal by name resolves slug resources in a read-only dry run", (t) => {
  const fixture = createFixture(t);
  const original = fs.readFileSync(fixture.itemsPath, "utf8");
  const result = runRemover(fixture, "First Collection", false);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Tokens\/first_collection\.json/u);
  assert.match(result.stdout, /Scripts\/first_collection\.js/u);
  assert.match(result.stdout, /covers\/first_collection\.jpg/u);
  assert.equal(fs.readFileSync(path.join(fixture.coversPath, "first_collection.jpg"), "utf8"), "existing cover");
  assert.equal(fs.readFileSync(fixture.itemsPath, "utf8"), original);
  assert.equal(fs.existsSync(path.join(fixture.root, "Tokens", "first_collection.json")), true);
  assert.equal(fs.readFileSync(path.join(fixture.root, "Scripts", "first_collection.js"), "utf8"), "void 0;");
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
    for (const [directory, extension] of [["Tokens", "json"], ["Scripts", "js"]]) {
      fs.renameSync(
        path.join(fixture.root, directory, `${item.internal_slug}.${extension}`),
        path.join(fixture.root, directory, `${slug}.${extension}`)
      );
    }
    fs.renameSync(
      path.join(fixture.coversPath, `${item.internal_slug}.jpg`),
      path.join(fixture.coversPath, `${slug}.jpg`)
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
  for (const [directory, extension] of [["Tokens", "json"], ["Scripts", "js"]]) {
    assert.deepEqual(fs.readdirSync(path.join(fixture.root, directory)), [`balance_2.${extension}`]);
  }
  assert.deepEqual(fs.readdirSync(fixture.coversPath), ["balance_2.jpg"]);
});

test("removal succeeds when no local cover staging directory exists", (t) => {
  const fixture = createFixture(t);
  fs.rmSync(fixture.coversPath, { recursive: true });
  const result = runRemover(fixture, "first_collection");
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /staged cover JPEG: missing/u);
  assert.deepEqual(JSON.parse(fs.readFileSync(fixture.itemsPath, "utf8")), [fixture.items[1]]);
  assert.equal(fs.existsSync(fixture.coversPath), false);
});

test("removal handles HTML, Processing, and native script collections", async (t) => {
  for (const [kind, extension] of [["html", "html"], ["processingjs146", "pde"], ["native.card-nft-2", null]]) {
    await t.test(kind, (t) => {
      const fixture = createFixture(t);
      fixture.items[0].script.kind = kind;
      fs.writeFileSync(fixture.itemsPath, JSON.stringify(fixture.items));
      fs.rmSync(path.join(fixture.root, "Scripts", "first_collection.js"));
      if (extension != null) {
        fs.writeFileSync(path.join(fixture.root, "Scripts", `first_collection.${extension}`), "source");
      }

      const preview = runRemover(fixture, "first_collection", false);
      assert.equal(preview.status, 0, preview.stderr);
      if (extension != null) {
        assert.ok(preview.stdout.includes(`Scripts/first_collection.${extension}`));
      } else {
        assert.match(preview.stdout, /script source: none/u);
      }
      const result = runRemover(fixture, "first_collection");
      assert.equal(result.status, 0, result.stderr);
      assert.deepEqual(fs.readdirSync(path.join(fixture.root, "Scripts")), ["second_collection.js"]);
      assert.deepEqual(JSON.parse(fs.readFileSync(fixture.itemsPath, "utf8")), [fixture.items[1]]);
    });
  }
});

test("removal cleans orphaned token and source files by slug", (t) => {
  const fixture = createFixture(t);
  fs.writeFileSync(fixture.itemsPath, JSON.stringify([fixture.items[1]]));

  const result = runRemover(fixture, "first_collection");
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /catalog entry: no/u);
  assert.deepEqual(fs.readdirSync(path.join(fixture.root, "Scripts")), ["second_collection.js"]);
  assert.deepEqual(fs.readdirSync(path.join(fixture.root, "Tokens")), ["second_collection.json"]);
  assert.deepEqual(JSON.parse(fs.readFileSync(fixture.itemsPath, "utf8")), [fixture.items[1]]);
});
