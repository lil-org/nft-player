"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const { suggestedItemId } = require("./suggested_items");

const SUGGESTED_BUNDLE_PATH = path.resolve(__dirname, "../Suggested Items/Suggested.bundle");
const ITEMS_PATH = path.join(SUGGESTED_BUNDLE_PATH, "items.json");
const SCRIPTS_PATH = path.join(SUGGESTED_BUNDLE_PATH, "Scripts");
const TOKENS_PATH = path.join(SUGGESTED_BUNDLE_PATH, "Tokens");
const STANDARD_THUMBNAIL_EXCEPTIONS = new Set([
  "card_nft",
  "card_nft_2",
  "poncho_drifella",
]);
const NATIVE_SCRIPT_THUMBNAIL_EXCEPTIONS = [
  "card_nft_2",
  "poncho_drifella",
];
const SUPPORTED_MEDIA_EXTENSIONS = new Set([
  "gif", "heic", "heif", "htm", "html", "jpeg", "jpg", "mov", "mp4",
  "png", "svg", "tiff", "webp", "xhtml",
]);

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function scriptCollectionIds() {
  return new Set(scriptCollectionKinds().keys());
}

function scriptCollectionKinds() {
  return new Map(
    fs.readdirSync(SCRIPTS_PATH)
      .filter((fileName) => path.extname(fileName) === ".json")
      .map((fileName) => [
        path.basename(fileName, ".json"),
        readJSON(path.join(SCRIPTS_PATH, fileName)).kind,
      ])
  );
}

function eligibleItems(items, scriptIds) {
  return items.filter((item) => (
    !scriptIds.has(suggestedItemId(item)) && item.internal_slug !== "card_nft"
  ));
}

function tokenSourceURL(payload, row) {
  if (!Array.isArray(row)) {
    return row.url;
  }

  const [, prefixIndex, urlSuffix] = row;
  const prefix = payload.urlPrefixes?.[prefixIndex] ?? "";
  return prefix + urlSuffix;
}

function standardThumbnailURL(sourceURL) {
  const url = new URL(sourceURL);
  const lastSlashIndex = url.pathname.lastIndexOf("/");
  const fileName = url.pathname.slice(lastSlashIndex + 1);
  const fileExtension = path.posix.extname(fileName);

  assert.notEqual(fileExtension, "", `Expected an extension-bearing URL: ${sourceURL}`);

  const stem = fileName.slice(0, -fileExtension.length);
  const parentPath = url.pathname.slice(0, lastSlashIndex);
  url.pathname = `${parentPath}/thumbs/${stem}.webp`;
  url.search = "";
  url.hash = "";
  return url;
}

test("standard thumbnail availability covers every non-script collection except card_nft", () => {
  const items = readJSON(ITEMS_PATH);
  const scriptKinds = scriptCollectionKinds();
  const scriptIds = new Set(scriptKinds.keys());
  const expectedEnabledItems = eligibleItems(items, scriptIds);
  const expectedEnabledIds = new Set(expectedEnabledItems.map(suggestedItemId));

  for (const [collectionId, kind] of scriptKinds) {
    assert.ok(
      typeof kind === "string" && kind.length > 0,
      `${collectionId} has a script without a valid kind`
    );
  }

  const nativeScriptSlugs = items
    .filter((item) => String(scriptKinds.get(suggestedItemId(item)) ?? "").startsWith("native."))
    .map((item) => item.internal_slug)
    .sort();
  assert.deepEqual(nativeScriptSlugs, [...NATIVE_SCRIPT_THUMBNAIL_EXCEPTIONS].sort());

  for (const item of items) {
    const expectedValue = expectedEnabledIds.has(suggestedItemId(item)) ? true : undefined;
    assert.equal(
      item.standardThumbsPathsAvailable,
      expectedValue,
      `${item.internal_slug} has an unexpected standard thumbnail availability value`
    );
  }

  for (const internalSlug of STANDARD_THUMBNAIL_EXCEPTIONS) {
    const item = items.find((candidate) => candidate.internal_slug === internalSlug);
    assert.ok(item, `Expected ${internalSlug} to be present in the suggested catalog`);
    assert.equal(item.standardThumbsPathsAvailable, undefined);
  }

  assert.equal(
    items.filter((item) => item.standardThumbsPathsAvailable === true).length,
    expectedEnabledItems.length
  );
});

test("eligible token manifests derive unique /thumbs webp URLs", () => {
  const items = readJSON(ITEMS_PATH);
  const scriptIds = scriptCollectionIds();

  for (const item of eligibleItems(items, scriptIds)) {
    const collectionId = suggestedItemId(item);
    const tokensPath = path.join(TOKENS_PATH, `${collectionId}.json`);
    assert.ok(fs.existsSync(tokensPath), `${item.internal_slug} is missing its token manifest`);

    const payload = readJSON(tokensPath);
    assert.ok(Array.isArray(payload.items), `${item.internal_slug} has no token items array`);
    assert.ok(payload.items.length > 0, `${item.internal_slug} has an empty token manifest`);

    const originalURLByDerivedURL = new Map();
    for (const [index, row] of payload.items.entries()) {
      const sourceURL = tokenSourceURL(payload, row);
      assert.equal(
        typeof sourceURL,
        "string",
        `${item.internal_slug} token ${index} has no source URL`
      );

      const originalURL = new URL(sourceURL);
      const originalFileName = path.posix.basename(originalURL.pathname);
      const originalExtension = path.posix.extname(originalFileName);
      assert.notEqual(
        originalExtension,
        "",
        `${item.internal_slug} token ${index} has no URL path extension: ${sourceURL}`
      );
      assert.ok(
        SUPPORTED_MEDIA_EXTENSIONS.has(originalExtension.slice(1).toLowerCase()),
        `${item.internal_slug} token ${index} has an unsupported media extension: ${sourceURL}`
      );

      const thumbnailURL = standardThumbnailURL(sourceURL);
      const originalParentPath = path.posix.dirname(originalURL.pathname);
      const expectedStem = originalFileName.slice(0, -originalExtension.length);
      assert.ok(
        expectedStem !== "" && expectedStem !== "." && expectedStem !== "..",
        `${item.internal_slug} token ${index} has an invalid thumbnail stem: ${sourceURL}`
      );
      assert.equal(
        thumbnailURL.pathname,
        `${originalParentPath}/thumbs/${expectedStem}.webp`,
        `${item.internal_slug} token ${index} derives an unexpected thumbnail path`
      );
      assert.equal(thumbnailURL.search, "");
      assert.equal(thumbnailURL.hash, "");
      const previousOriginalURL = originalURLByDerivedURL.get(thumbnailURL.href);
      if (previousOriginalURL != null) {
        assert.equal(
          originalURL.href,
          previousOriginalURL,
          `${item.internal_slug} has distinct originals colliding at ${thumbnailURL.href}`
        );
      } else {
        originalURLByDerivedURL.set(thumbnailURL.href, originalURL.href);
      }
    }
  }
});

test("standard thumbnail derivation removes an original query and fragment", () => {
  assert.equal(
    standardThumbnailURL("https://cdn.lil.org/player/example/42.gif?size=large#frame").href,
    "https://cdn.lil.org/player/example/thumbs/42.webp"
  );
});
