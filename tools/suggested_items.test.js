"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  applyIOSCollectionBrowserColumnCounts,
  mergeGeneratedSuggestedItem,
  withIOSCollectionBrowserColumnCount,
} = require("./suggested_items");

test("preserves standard thumbnail metadata when regenerating a suggested item", () => {
  const existingItem = {
    address: "collection-id",
    chain: "solana",
    internal_slug: "example_collection",
    artists: ["example_artist", "collaborating_artist"],
    iosCollectionBrowserColumnCount: 3,
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
    artists: ["example_artist", "collaborating_artist"],
    iosCollectionBrowserColumnCount: 3,
    standardThumbsPathsAvailable: true,
    standardThumbsBaseURL: "https://cdn.lil.org/player/example_collection/thumbs/",
    address: "collection-id",
    chain: "solana",
    name: "Example Collection",
    tokenCount: 100,
  });
});

test("encodes automatic two-column decisions and preserves manual three-column overrides", () => {
  const item = {
    address: "collection-id",
    chain: "solana",
    iosCollectionBrowserColumnCount: 7,
  };
  const manualDefaultItem = {
    address: "manual-default",
    chain: "solana",
    iosCollectionBrowserColumnCount: 3,
  };

  assert.deepEqual(withIOSCollectionBrowserColumnCount(item, 2), {
    address: "collection-id",
    chain: "solana",
    iosCollectionBrowserColumnCount: 2,
  });
  assert.deepEqual(withIOSCollectionBrowserColumnCount(item, 3), {
    address: "collection-id",
    chain: "solana",
  });
  assert.deepEqual(withIOSCollectionBrowserColumnCount(item, null), {
    address: "collection-id",
    chain: "solana",
  });
  assert.deepEqual(withIOSCollectionBrowserColumnCount(manualDefaultItem, 2), {
    address: "manual-default",
    chain: "solana",
    iosCollectionBrowserColumnCount: 3,
  });
  assert.deepEqual(withIOSCollectionBrowserColumnCount(manualDefaultItem, 3), {
    address: "manual-default",
    chain: "solana",
    iosCollectionBrowserColumnCount: 3,
  });
  assert.deepEqual(withIOSCollectionBrowserColumnCount(manualDefaultItem, null), {
    address: "manual-default",
    chain: "solana",
    iosCollectionBrowserColumnCount: 3,
  });
});

test("updates only catalog entries selected by collection id", () => {
  const items = [
    { address: "wide", chain: "solana" },
    {
      address: "default",
      chain: "solana",
      iosCollectionBrowserColumnCount: 2,
    },
    {
      address: "manual-default",
      chain: "solana",
      iosCollectionBrowserColumnCount: 3,
    },
    { address: "untouched", chain: "solana", custom: true },
  ];

  assert.deepEqual(
    applyIOSCollectionBrowserColumnCounts(items, new Map([
      ["wide", 2],
      ["default", 3],
      ["manual-default", 2],
    ])),
    [
      {
        address: "wide",
        chain: "solana",
        iosCollectionBrowserColumnCount: 2,
      },
      { address: "default", chain: "solana" },
      {
        address: "manual-default",
        chain: "solana",
        iosCollectionBrowserColumnCount: 3,
      },
      { address: "untouched", chain: "solana", custom: true },
    ]
  );
});

test("rejects noncanonical collection browser column counts", () => {
  assert.throws(
    () => withIOSCollectionBrowserColumnCount({ address: "collection" }, 4),
    /must be 2, 3, or null/u
  );
});
