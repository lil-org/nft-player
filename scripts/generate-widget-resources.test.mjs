import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { generateWidgetResources, widgetTokenPayload } from "./generate-widget-resources.mjs";
import tokenManifest from "../tools/token_manifest.js";

const { decodeTokenManifest, serializeTokenManifest } = tokenManifest;

test("widget projection preserves every source ordinal and only retains ID and URL suffix", () => {
  const source = { version: 2, count: 3, ids: ["same", "same", "other"],
    name: ["one", null, "three"], hash: ["first", "second", "third"],
    urlTemplate: { value: "index1", suffix: ".png" }, excludedMediaIndices: [0] };
  const projected = widgetTokenPayload(source);
  assert.deepEqual(projected, { items: [
    { id: "same", urlSuffix: "1.png" }, { id: "same", urlSuffix: "2.png" }, { id: "other", urlSuffix: "3.png" },
  ] });
  const compact = JSON.parse(serializeTokenManifest(projected));
  assert.deepEqual(compact.urlTemplate, source.urlTemplate);
  assert.equal(compact.excludedMediaIndices, undefined);
  assert.deepEqual(decodeTokenManifest(compact), projected);
});

test("widget generation is canonical, current, and read-only in check mode", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-widget-resources-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const sourceBundle = path.join(directory, "Suggested.bundle");
  await fs.mkdir(path.join(sourceBundle, "Tokens"), { recursive: true });
  await fs.writeFile(path.join(directory, "widget-eligible-collections.json"), '["sample"]');
  const item = { internal_slug: "sample", bundledTokenCount: 2, hasUniformAspectRatio: true };
  await fs.writeFile(path.join(sourceBundle, "items.json"), JSON.stringify([item]));
  await fs.writeFile(path.join(sourceBundle, "Tokens", "sample.json"), serializeTokenManifest([
    { id: "1", urlSuffix: "1.png", name: "Art" }, { id: "2", urlSuffix: "2.png", aspectRatio: [4, 3] },
  ]));
  await generateWidgetResources(directory);
  const outputFile = path.join(directory, "WidgetSuggested.bundle", "Tokens", "sample.json");
  const expected = '{"version":2,"count":2,"firstId":"1","urlTemplate":{"value":"id","suffix":".png"}}\n';
  assert.equal(await fs.readFile(outputFile, "utf8"), expected);
  assert.deepEqual(JSON.parse(await fs.readFile(path.join(directory, "WidgetSuggested.bundle", "items.json"))), [item]);
  await generateWidgetResources(directory, { check: true });
  await fs.writeFile(outputFile, "stale");
  await assert.rejects(generateWidgetResources(directory, { check: true }), /out of date/u);
  assert.equal(await fs.readFile(outputFile, "utf8"), "stale");
  await generateWidgetResources(directory);
  await fs.writeFile(path.join(directory, "WidgetSuggested.bundle", "extra.json"), "{}");
  await assert.rejects(generateWidgetResources(directory, { check: true }), /unexpected/u);
  await generateWidgetResources(directory);
  await generateWidgetResources(directory, { check: true });
});

test("invalid widget source does not replace existing generated output", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-widget-invalid-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  await fs.mkdir(path.join(directory, "Suggested.bundle", "Tokens"), { recursive: true });
  await fs.mkdir(path.join(directory, "WidgetSuggested.bundle"));
  await fs.writeFile(path.join(directory, "widget-eligible-collections.json"), '["sample"]');
  await fs.writeFile(path.join(directory, "Suggested.bundle", "items.json"), '[{"internal_slug":"sample"}]');
  await fs.writeFile(path.join(directory, "Suggested.bundle", "Tokens", "sample.json"), '{"version":2,"count":2,"ids":[]}');
  const marker = path.join(directory, "WidgetSuggested.bundle", "items.json");
  await fs.writeFile(marker, "existing");
  await assert.rejects(generateWidgetResources(directory), /ids must/u);
  assert.equal(await fs.readFile(marker, "utf8"), "existing");
});
