"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const generator = import("../scripts/generate-widget-resources.mjs");

async function writeFile(directory, relativePath, content) {
  const filePath = path.join(directory, relativePath);
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, content);
}

async function writeJSON(directory, relativePath, value) {
  await writeFile(directory, relativePath, `${JSON.stringify(value, null, 2)}\n`);
}

async function fixture(t) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-player-widget-slugs-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const items = [
    { address: "0xAbCd", abId: "1", internal_slug: "alpha", name: "Alpha" },
    { address: "0xAbCd", abId: "2", internal_slug: "beta", name: "Beta" },
  ];
  await writeJSON(directory, "Suggested.bundle/items.json", items);
  await writeJSON(directory, "widget-eligible-collections.json", ["beta", "alpha"]);
  for (const item of items) {
    const slug = item.internal_slug;
    await writeJSON(directory, `Suggested.bundle/Tokens/${slug}.json`, {
      items: [{ id: item.abId, url: `https://example.com/${slug}.jpg` }],
    });
  }
  return { directory, items };
}

test("widget resources use slugs and copy metadata and token bytes without local covers", async (t) => {
  const { directory, items } = await fixture(t);
  const { generateWidgetResources } = await generator;
  await generateWidgetResources(directory);

  assert.deepEqual(
    JSON.parse(await fs.readFile(path.join(directory, "WidgetSuggested.bundle/items.json"), "utf8")),
    [items[1], items[0]]
  );
  assert.deepEqual(
    (await fs.readdir(path.join(directory, "WidgetSuggested.bundle/Tokens"))).sort(),
    ["alpha.json", "beta.json"]
  );
  for (const slug of ["alpha", "beta"]) {
    assert.deepEqual(
      await fs.readFile(path.join(directory, `WidgetSuggested.bundle/Tokens/${slug}.json`)),
      await fs.readFile(path.join(directory, `Suggested.bundle/Tokens/${slug}.json`))
    );
  }
  assert.deepEqual((await fs.readdir(directory)).sort(), [
    "Suggested.bundle", "WidgetSuggested.bundle", "widget-eligible-collections.json",
  ]);
  await generateWidgetResources(directory, { check: true });
});

test("widget generation rejects invalid or ambiguous slug selections", async (t) => {
  const { generateWidgetResources } = await generator;
  const cases = [
    { name: "duplicate eligibility", selection: ["alpha", "alpha"], error: /Duplicate collection slugs/ },
    { name: "unknown eligibility", selection: ["unknown"], error: /Missing collection slugs/ },
    { name: "invalid eligibility", selection: ["../alpha"], error: /valid internal_slug strings/ },
    { name: "non-string eligibility", selection: [1], error: /valid internal_slug strings/ },
    { name: "non-array eligibility", selection: {}, error: /JSON array/ },
    { name: "duplicate catalog slug", alterItems: (items) => { items[1].internal_slug = "alpha"; }, error: /Duplicate internal_slug/ },
    { name: "missing catalog slug", alterItems: (items) => { delete items[0].internal_slug; }, error: /Invalid internal_slug/ },
    { name: "invalid catalog slug", alterItems: (items) => { items[0].internal_slug = "Alpha"; }, error: /Invalid internal_slug/ },
  ];
  for (const entry of cases) {
    await t.test(entry.name, async (t) => {
      const { directory, items } = await fixture(t);
      await writeFile(directory, "WidgetSuggested.bundle/sentinel", "existing output");
      if (entry.selection !== undefined) {
        await writeJSON(directory, "widget-eligible-collections.json", entry.selection);
      }
      if (entry.alterItems) {
        entry.alterItems(items);
        await writeJSON(directory, "Suggested.bundle/items.json", items);
      }
      await assert.rejects(generateWidgetResources(directory), entry.error);
      assert.equal(await fs.readFile(path.join(directory, "WidgetSuggested.bundle/sentinel"), "utf8"), "existing output");
    });
  }
});

test("widget generation requires slug-named token resources", async (t) => {
  const { generateWidgetResources } = await generator;
  const { directory, items } = await fixture(t);
  const oldId = items[0].address + items[0].abId;
  await fs.rename(
    path.join(directory, "Suggested.bundle/Tokens/alpha.json"),
    path.join(directory, `Suggested.bundle/Tokens/${oldId}.json`)
  );
  await assert.rejects(generateWidgetResources(directory), /Missing token JSON files/);
});

test("widget check reports stale output without changing it and generation removes old names", async (t) => {
  const { directory } = await fixture(t);
  const { generateWidgetResources } = await generator;
  await generateWidgetResources(directory);
  await writeFile(directory, "WidgetSuggested.bundle/Tokens/0xAbCd1.json", "old name");
  await writeFile(directory, "WidgetSuggested.bundle/Tokens/alpha.json", "changed bytes");
  await fs.rm(path.join(directory, "WidgetSuggested.bundle/Tokens/beta.json"));
  await assert.rejects(generateWidgetResources(directory, { check: true }), (error) => {
    assert.match(error.message, /missing .*beta\.json/);
    assert.match(error.message, /unexpected .*0xAbCd1\.json/);
    assert.match(error.message, /changed .*alpha\.json/);
    return true;
  });
  assert.equal(await fs.readFile(path.join(directory, "WidgetSuggested.bundle/Tokens/alpha.json"), "utf8"), "changed bytes");
  await generateWidgetResources(directory);
  await generateWidgetResources(directory, { check: true });
  await assert.rejects(fs.access(path.join(directory, "WidgetSuggested.bundle/Tokens/0xAbCd1.json")), { code: "ENOENT" });
});
