import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { generateWidgetResources } from "./generate-widget-resources.mjs";

async function fixture(t) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-widget-resources-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const items = [
    { address: "0xfirst", internal_slug: "first", collectionId: "collection", abId: "7", name: "First",
      manifestTokenCount: 2, hasUniformAspectRatio: true, aspectRatio: [4, 3],
      standardThumbsPathsAvailable: false, standardThumbsBaseURL: "https://cdn.lil.org/previews/",
      iosOnly: false, generativeOnly: true, artists: ["artist"],
      script: { kind: "js", sha256: "hash", expectedByteCount: 10, projectId: "7" } },
    { address: "0xsecond", internal_slug: "second", name: "Second", tokenCount: 3,
      urlPrefix: "https://cdn.lil.org/player/second/", hasMid: false },
    { address: "0xthird", internal_slug: "third", name: "Third" },
  ];
  await fs.writeFile(path.join(directory, "items.json"), JSON.stringify(items));
  await fs.writeFile(path.join(directory, "widget-eligible-collections.json"), '["second","first"]');
  return { directory, items, outputPath: path.join(directory, "widget-items.json") };
}

test("widget generation projects the exact runtime fields in eligibility order without token files", async (t) => {
  const { directory, items, outputPath } = await fixture(t);
  await generateWidgetResources(directory);
  const expected = [
    { address: "0xsecond", internal_slug: "second", name: "Second",
      urlPrefix: "https://cdn.lil.org/player/second/", hasMid: false },
    { address: "0xfirst", internal_slug: "first", collectionId: "collection", abId: "7", name: "First",
      standardThumbsPathsAvailable: false, standardThumbsBaseURL: "https://cdn.lil.org/previews/",
      iosOnly: false, generativeOnly: true, script: { kind: "js" } },
  ];
  assert.equal(await fs.readFile(outputPath, "utf8"), `${JSON.stringify(expected, null, 2)}\n`);
  const identity = (item) => `${item.address}${item.abId ?? item.collectionId ?? ""}`;
  assert.deepEqual(expected.map(identity), [items[1], items[0]].map(identity));
  await generateWidgetResources(directory, { check: true });
  assert.deepEqual((await fs.readdir(directory)).sort(), ["items.json", "widget-eligible-collections.json", "widget-items.json"]);
});

test("unused app metadata does not stale widget output, while runtime metadata does", async (t) => {
  const { directory, items } = await fixture(t);
  await generateWidgetResources(directory);
  items[0].manifestTokenCount = 100;
  items[0].script.sha256 = "changed";
  items[0].script.sourceURL = "https://cdn.lil.org/new-version.js";
  items[1].artists = ["new artist"];
  await fs.writeFile(path.join(directory, "items.json"), JSON.stringify(items));
  await generateWidgetResources(directory, { check: true });
  items[0].script.kind = "html";
  await fs.writeFile(path.join(directory, "items.json"), JSON.stringify(items));
  await assert.rejects(generateWidgetResources(directory, { check: true }), /out of date/u);
});

test("check detects missing and stale output without writing", async (t) => {
  const { directory, outputPath } = await fixture(t);
  await assert.rejects(generateWidgetResources(directory, { check: true }), /out of date/u);
  await assert.rejects(fs.access(outputPath), { code: "ENOENT" });
  await fs.writeFile(outputPath, "existing");
  await assert.rejects(generateWidgetResources(directory, { check: true }), /out of date/u);
  assert.equal(await fs.readFile(outputPath, "utf8"), "existing");
  await generateWidgetResources(directory);
  await generateWidgetResources(directory, { check: true });
});

test("invalid eligibility never replaces existing output", async (t) => {
  const { directory, outputPath } = await fixture(t);
  await fs.writeFile(outputPath, "existing");
  for (const invalid of ["{}", '["missing"]', '["first","first"]', '["../first"]', "[2]"]) {
    await fs.writeFile(path.join(directory, "widget-eligible-collections.json"), invalid);
    await assert.rejects(generateWidgetResources(directory));
    assert.equal(await fs.readFile(outputPath, "utf8"), "existing");
  }
});

test("invalid catalogs never replace existing output", async (t) => {
  const { directory, outputPath } = await fixture(t);
  await fs.writeFile(outputPath, "existing");
  for (const invalid of ["{}", '[{"internal_slug":"../first"}]', '[{"internal_slug":"first"},{"internal_slug":"first"}]']) {
    await fs.writeFile(path.join(directory, "items.json"), invalid);
    await assert.rejects(generateWidgetResources(directory));
    assert.equal(await fs.readFile(outputPath, "utf8"), "existing");
  }
});

test("invalid widget runtime fields fail before replacing output", async (t) => {
  const { directory, items, outputPath } = await fixture(t);
  await fs.writeFile(outputPath, "existing");
  for (const invalid of [
    { address: "" }, { name: null }, { name: 1 }, { name: "   " }, { name: "\t\n\r" },
    { name: "\u0085" }, { name: "\u200B" }, { name: "\u200B \t\u0085\n\u200B" },
    { abId: 7 }, { collectionId: [] },
    { urlPrefix: {} }, { hasMid: "false" }, { standardThumbsPathsAvailable: 0 },
    { standardThumbsBaseURL: true }, { iosOnly: 1 }, { generativeOnly: "true" },
    { script: [] }, { script: {} }, { script: { kind: "" } },
  ]) {
    await fs.writeFile(path.join(directory, "items.json"), JSON.stringify([{ ...items[0], ...invalid }, ...items.slice(1)]));
    await assert.rejects(generateWidgetResources(directory), /first:/u);
    await assert.rejects(generateWidgetResources(directory, { check: true }), /first:/u);
    assert.equal(await fs.readFile(outputPath, "utf8"), "existing");
  }
});

test("projection preserves optional nulls and omits absent fields", async (t) => {
  const { directory, items, outputPath } = await fixture(t);
  const item = { ...items[2], collectionId: null, hasMid: null, script: null };
  await fs.writeFile(path.join(directory, "items.json"), JSON.stringify([item]));
  await fs.writeFile(path.join(directory, "widget-eligible-collections.json"), '["third"]');
  await generateWidgetResources(directory);
  assert.deepEqual(JSON.parse(await fs.readFile(outputPath, "utf8")), [item]);
});
