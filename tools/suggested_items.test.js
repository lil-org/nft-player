"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { mergeGeneratedSuggestedItem } = require("./suggested_items");

test("preserves standard thumbnail metadata when regenerating a suggested item", () => {
  const existingItem = {
    address: "collection-id",
    chain: "solana",
    internal_slug: "example_collection",
    standardThumbsPathsAvailable: true,
    standardThumbsBaseURL: "https://cdn.lil.org/player/example_collection/thumbs/",
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
    standardThumbsBaseURL: "https://cdn.lil.org/player/example_collection/thumbs/",
    address: "collection-id",
    chain: "solana",
    name: "Example Collection",
    tokenCount: 100,
  });
});
