#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import suggestedItems from "../tools/suggested_items.js";

const { assertValidInternalSlugs, INTERNAL_SLUG_PATTERN, MAX_INTERNAL_SLUG_LENGTH } = suggestedItems;
const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const suggestedItemsDirectory = path.join(repositoryRoot, "Suggested Items");
const stringFields = ["address", "internal_slug", "collectionId", "abId", "name", "urlPrefix", "standardThumbsBaseURL"];
const booleanFields = ["hasMid", "standardThumbsPathsAvailable", "iosOnly", "generativeOnly"];
const widgetFields = ["address", "internal_slug", "collectionId", "abId", "name", "urlPrefix", "hasMid",
  "standardThumbsPathsAvailable", "standardThumbsBaseURL", "iosOnly", "generativeOnly"];

function widgetMetadata(item) {
  for (const key of ["address", "internal_slug", "name"]) {
    if (typeof item[key] !== "string" || /^[\p{White_Space}\u200B]*$/u.test(item[key])) {
      throw new TypeError(`${item.internal_slug}: ${key} must be a non-empty string.`);
    }
  }
  for (const [fields, type] of [[stringFields, "string"], [booleanFields, "boolean"]]) {
    for (const key of fields) {
      if (item[key] != null && typeof item[key] !== type) {
        throw new TypeError(`${item.internal_slug}: ${key} must be a ${type}.`);
      }
    }
  }
  const result = Object.fromEntries(widgetFields.filter((key) => Object.hasOwn(item, key))
    .map((key) => [key, item[key]]));
  if (Object.hasOwn(item, "script")) {
    if (item.script == null) {
      result.script = null;
    } else {
      if (typeof item.script !== "object" || Array.isArray(item.script)
          || typeof item.script.kind !== "string" || item.script.kind.length === 0) {
        throw new TypeError(`${item.internal_slug}: script must contain a non-empty kind string.`);
      }
      result.script = { kind: item.script.kind };
    }
  }
  return result;
}

export async function generateWidgetResources(directory, { check = false } = {}) {
  const eligibleSlugs = JSON.parse(await fs.readFile(path.join(directory, "widget-eligible-collections.json"), "utf8"));
  if (!Array.isArray(eligibleSlugs) || eligibleSlugs.some((slug) => typeof slug !== "string"
      || !INTERNAL_SLUG_PATTERN.test(slug) || slug.length > MAX_INTERNAL_SLUG_LENGTH)) {
    throw new Error("widget-eligible-collections.json must contain an array of valid internal_slug strings.");
  }
  if (new Set(eligibleSlugs).size !== eligibleSlugs.length) {
    throw new Error("Duplicate collection slugs in widget-eligible-collections.json.");
  }
  const sourceItems = JSON.parse(await fs.readFile(path.join(directory, "items.json"), "utf8"));
  if (!Array.isArray(sourceItems)) throw new Error("items.json must contain a JSON array.");
  assertValidInternalSlugs(sourceItems);
  const itemsBySlug = new Map(sourceItems.map((item) => [item.internal_slug, item]));
  const selectedItems = eligibleSlugs.map((slug) => {
    const item = itemsBySlug.get(slug);
    if (!item) throw new Error(`Missing collection slug in items.json: ${slug}`);
    return widgetMetadata(item);
  });
  const outputPath = path.join(directory, "widget-items.json");
  const expectedContent = `${JSON.stringify(selectedItems, null, 2)}\n`;
  if (check) {
    let actualContent;
    try {
      actualContent = await fs.readFile(outputPath, "utf8");
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    if (actualContent !== expectedContent) {
      throw new Error("Generated widget resources are out of date; run node scripts/generate-widget-resources.mjs.");
    }
  } else {
    await fs.writeFile(outputPath, expectedContent);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const flags = process.argv.slice(2);
  if (flags.some((flag) => flag !== "--check")) {
    console.error("Usage: node scripts/generate-widget-resources.mjs [--check]");
    process.exitCode = 1;
  } else {
    const check = flags.includes("--check");
    generateWidgetResources(suggestedItemsDirectory, { check }).then(() => {
      console.log(check ? "Widget resources are current." : "Generated Suggested Items/widget-items.json");
    }).catch((error) => {
      console.error(error.message);
      process.exitCode = 1;
    });
  }
}
