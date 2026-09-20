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
    { internal_slug: "first", bundledTokenCount: 2, hasUniformAspectRatio: true },
    { internal_slug: "second", tokenCount: 3, urlPrefix: "https://example.com/" },
    { internal_slug: "third" },
  ];
  await fs.writeFile(path.join(directory, "items.json"), JSON.stringify(items));
  await fs.writeFile(path.join(directory, "widget-eligible-collections.json"), '["second","first"]');
  return { directory, items, outputPath: path.join(directory, "widget-items.json") };
}

test("widget generation preserves selected metadata and eligibility order without token files", async (t) => {
  const { directory, items, outputPath } = await fixture(t);
  await generateWidgetResources(directory);
  assert.equal(await fs.readFile(outputPath, "utf8"), `${JSON.stringify([items[1], items[0]], null, 2)}\n`);
  await generateWidgetResources(directory, { check: true });
  assert.deepEqual((await fs.readdir(directory)).sort(), ["items.json", "widget-eligible-collections.json", "widget-items.json"]);
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
