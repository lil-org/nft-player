"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { mergeGeneratedSuggestedItem } = require("./suggested_items");

test("preserves standard thumbnail path availability when regenerating a suggested item", () => {
  const existingItem = {
    address: "collection-id",
    chain: "solana",
    internal_slug: "example_collection",
    standardThumbsPathsAvailable: true,
  };
  const generatedItem = {
    address: "collection-id",
    chain: "solana",
    name: "Example Collection",
    tokenCount: 100,
  };

  assert.deepEqual(mergeGeneratedSuggestedItem(existingItem, generatedItem), {
    internal_slug: "example_collection",
    standardThumbsPathsAvailable: true,
    address: "collection-id",
    chain: "solana",
    name: "Example Collection",
    tokenCount: 100,
  });
});
