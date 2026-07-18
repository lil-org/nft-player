"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  IOS_COLLECTION_BROWSER_COLUMN_COUNT_KEY,
  suggestedItemId,
} = require("./suggested_items");
const {
  ASPECT_RATIOS_KEY,
  ASPECT_RATIO_OVERRIDES_KEY,
  COLLECTION_BROWSER_LANDSCAPE_COLUMN_COUNT,
  collectionBrowserColumnCountFromAspectRatios,
  decodeAspectRatioMetadata,
  encodeAspectRatioMetadata,
  tokenIdsFromPayload,
} = require("./thumbnail_aspect_ratios");

const SUGGESTED_BUNDLE_PATH = path.resolve(__dirname, "../Suggested Items/Suggested.bundle");
const ITEMS_PATH = path.join(SUGGESTED_BUNDLE_PATH, "items.json");
const SCRIPTS_PATH = path.join(SUGGESTED_BUNDLE_PATH, "Scripts");
const TOKENS_PATH = path.join(SUGGESTED_BUNDLE_PATH, "Tokens");
const COVERS_PATH = path.resolve(__dirname, "../Suggested Items/Covers.xcassets");
const WIDGET_TOKENS_PATH = path.resolve(__dirname, "../Suggested Items/WidgetSuggested.bundle/Tokens");
const NATIVE_SCRIPT_THUMBNAIL_COLLECTIONS = new Set([
  "card_nft_2",
  "poncho_drifella",
]);
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
  return items.filter((item) => !scriptIds.has(suggestedItemId(item)));
}

function tokenSourceURL(payload, row) {
  if (!Array.isArray(row)) {
    return row.url;
  }

  const [, prefixIndex, urlSuffix] = row;
  const prefix = payload.urlPrefixes?.[prefixIndex] ?? "";
  return prefix + urlSuffix;
}

function normalizedFileExtension(value) {
  if (typeof value !== "string") return undefined;
  const normalized = value.replace(/^[. \n\t\r]+|[. \n\t\r]+$/gu, "").toLowerCase();
  return normalized === "" ? undefined : normalized;
}

function resolvedFileExtension(payload, row, sourceURL) {
  const sourcePathExtension = normalizedFileExtension(
    path.posix.extname(new URL(sourceURL).pathname)
  );
  const rowFileExtension = normalizedFileExtension(
    Array.isArray(row) ? row[3] : row.fileExtension
  );
  return sourcePathExtension
    ?? rowFileExtension
    ?? normalizedFileExtension(payload.defaultFileExtension);
}

function standardThumbnailURL(sourceURL, thumbsBaseURL) {
  const url = new URL(sourceURL);
  const lastSlashIndex = url.pathname.lastIndexOf("/");
  const fileName = url.pathname.slice(lastSlashIndex + 1);
  const fileExtension = path.posix.extname(fileName);
  const stem = fileExtension === "" ? fileName : fileName.slice(0, -fileExtension.length);

  if (thumbsBaseURL != null) {
    return new URL(`${stem}.webp`, thumbsBaseURL);
  }

  assert.notEqual(fileExtension, "", `Expected an extension-bearing URL: ${sourceURL}`);
  const parentPath = url.pathname.slice(0, lastSlashIndex);
  url.pathname = `${parentPath}/thumbs/${stem}.webp`;
  url.search = "";
  url.hash = "";
  return url;
}

function entriesByLowercasedName(names) {
  const entries = new Map();
  for (const name of names) {
    const normalizedName = name.toLowerCase();
    const matches = entries.get(normalizedName) ?? [];
    matches.push(name);
    entries.set(normalizedName, matches);
  }
  return entries;
}

test("catalog IDs exactly match token manifest and cover asset casing", () => {
  const items = readJSON(ITEMS_PATH);
  const scriptIds = scriptCollectionIds();
  const tokenFileNames = fs.readdirSync(TOKENS_PATH)
    .filter((fileName) => path.extname(fileName) === ".json");
  const coverImagesetNames = fs.readdirSync(COVERS_PATH, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name.endsWith(".imageset"))
    .map((entry) => entry.name);
  const tokenFilesByLowercasedName = entriesByLowercasedName(tokenFileNames);
  const coverImagesetsByLowercasedName = entriesByLowercasedName(coverImagesetNames);

  for (const [normalizedName, matches] of tokenFilesByLowercasedName) {
    assert.equal(matches.length, 1, `Token manifests collide by case for ${normalizedName}: ${matches.join(", ")}`);
  }
  for (const [normalizedName, matches] of coverImagesetsByLowercasedName) {
    assert.equal(matches.length, 1, `Cover assets collide by case for ${normalizedName}: ${matches.join(", ")}`);
  }

  for (const item of items) {
    const collectionId = suggestedItemId(item);
    const expectedTokenFileName = `${collectionId}.json`;
    const tokenMatches = tokenFilesByLowercasedName.get(expectedTokenFileName.toLowerCase()) ?? [];
    if (!scriptIds.has(collectionId) || tokenMatches.length > 0) {
      assert.deepEqual(
        tokenMatches,
        [expectedTokenFileName],
        `${item.internal_slug} token manifest casing does not exactly match its catalog ID`
      );
    }

    const expectedCoverImagesetName = `${collectionId}.imageset`;
    assert.deepEqual(
      coverImagesetsByLowercasedName.get(expectedCoverImagesetName.toLowerCase()) ?? [],
      [expectedCoverImagesetName],
      `${item.internal_slug} cover asset casing does not exactly match its catalog ID`
    );
  }
});

test("standard thumbnail availability covers downloadable and native-script collections", () => {
  const items = readJSON(ITEMS_PATH);
  const scriptKinds = scriptCollectionKinds();
  const scriptIds = new Set(scriptKinds.keys());
  const expectedEnabledItems = [
    ...eligibleItems(items, scriptIds),
    ...items.filter((item) =>
      NATIVE_SCRIPT_THUMBNAIL_COLLECTIONS.has(item.internal_slug)
    ),
  ];
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
  assert.deepEqual(nativeScriptSlugs, [...NATIVE_SCRIPT_THUMBNAIL_COLLECTIONS].sort());

  for (const item of items) {
    const expectedValue = expectedEnabledIds.has(suggestedItemId(item)) ? true : undefined;
    assert.equal(
      item.standardThumbsPathsAvailable,
      expectedValue,
      `${item.internal_slug} has an unexpected standard thumbnail availability value`
    );
  }
  assert.equal(
    items.filter((item) => item.standardThumbsPathsAvailable === true).length,
    expectedEnabledItems.length
  );
});

test("media extension resolution prefers URL, then row, then manifest defaults", () => {
  const payload = {
    defaultFileExtension: ".HTML",
    urlPrefixes: ["https://example.com/tokens/"],
  };

  assert.equal(
    resolvedFileExtension(payload, ["1", 0, "1.svg", "mov"], "https://example.com/tokens/1.svg"),
    "svg"
  );
  assert.equal(
    resolvedFileExtension(payload, ["2", 0, "2", ".MOV"], "https://example.com/tokens/2"),
    "mov"
  );
  assert.equal(
    resolvedFileExtension(payload, ["3", 0, "3"], "https://example.com/tokens/3"),
    "html"
  );
});

test("eligible token manifests derive unique standard webp thumbnail URLs", () => {
  const items = readJSON(ITEMS_PATH);
  const scriptIds = scriptCollectionIds();
  const tokenFileNames = new Set(
    fs.readdirSync(TOKENS_PATH)
      .filter((fileName) => path.extname(fileName) === ".json")
  );

  for (const item of eligibleItems(items, scriptIds)) {
    const collectionId = suggestedItemId(item);
    const tokensPath = path.join(TOKENS_PATH, `${collectionId}.json`);
    assert.ok(
      tokenFileNames.has(`${collectionId}.json`),
      `${item.internal_slug} is missing an exact-case token manifest`
    );

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
      const fileExtension = resolvedFileExtension(payload, row, sourceURL);
      assert.ok(
        SUPPORTED_MEDIA_EXTENSIONS.has(fileExtension),
        `${item.internal_slug} token ${index} has an unsupported media extension: ${sourceURL}`
      );

      const thumbnailURL = standardThumbnailURL(sourceURL, item.standardThumbsBaseURL);
      const originalParentPath = path.posix.dirname(originalURL.pathname);
      const expectedStem = originalExtension === ""
        ? originalFileName
        : originalFileName.slice(0, -originalExtension.length);
      assert.ok(
        expectedStem !== "" && expectedStem !== "." && expectedStem !== "..",
        `${item.internal_slug} token ${index} has an invalid thumbnail stem: ${sourceURL}`
      );
      if (item.standardThumbsBaseURL == null) {
        assert.equal(
          thumbnailURL.pathname,
          `${originalParentPath}/thumbs/${expectedStem}.webp`,
          `${item.internal_slug} token ${index} derives an unexpected thumbnail path`
        );
      } else {
        assert.equal(
          thumbnailURL.href,
          new URL(`${expectedStem}.webp`, item.standardThumbsBaseURL).href,
          `${item.internal_slug} token ${index} derives an unexpected override thumbnail URL`
        );
      }
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

test("thumbnail base overrides support extensionless sources and strip source extensions", () => {
  const thumbsBaseURL = "https://cdn.lil.org/player/example/thumbs/";
  assert.equal(
    standardThumbnailURL("https://api.example.com/token-html/42", thumbsBaseURL).href,
    "https://cdn.lil.org/player/example/thumbs/42.webp"
  );
  assert.equal(
    standardThumbnailURL("https://api.example.com/tokens/42.svg?size=large#frame", thumbsBaseURL).href,
    "https://cdn.lil.org/player/example/thumbs/42.webp"
  );
});

test("bundled tokens have compact aspect ratios and matching iOS layouts", () => {
  const primaryFileNames = fs.readdirSync(TOKENS_PATH)
    .filter((fileName) => path.extname(fileName) === ".json")
    .sort();
  assert.equal(primaryFileNames.length, 217);

  const catalogItems = readJSON(ITEMS_PATH);
  const catalogItemByLowercasedFileName = new Map(
    catalogItems.map((item) => [
      `${suggestedItemId(item)}.json`.toLowerCase(),
      item,
    ])
  );
  const primaryByLowercasedFileName = new Map();
  let primaryTokenCount = 0;
  let twoColumnCollectionCount = 0;
  for (const fileName of primaryFileNames) {
    const payload = readJSON(path.join(TOKENS_PATH, fileName));
    const ratios = decodeAspectRatioMetadata(payload);
    assert.ok(ratios, `${fileName} has no thumbnail aspect-ratio metadata`);
    assert.equal(ratios.length, payload.items.length, `${fileName} has incomplete aspect-ratio metadata`);
    assert.deepEqual(
      {
        [ASPECT_RATIOS_KEY]: payload[ASPECT_RATIOS_KEY],
        ...(payload[ASPECT_RATIO_OVERRIDES_KEY] == null
          ? {}
          : { [ASPECT_RATIO_OVERRIDES_KEY]: payload[ASPECT_RATIO_OVERRIDES_KEY] }),
      },
      encodeAspectRatioMetadata(ratios),
      `${fileName} does not use the canonical compact aspect-ratio encoding`
    );

    const item = catalogItemByLowercasedFileName.get(fileName.toLowerCase());
    assert.ok(item, `${fileName} has no suggested catalog item`);
    const derivedColumnCount =
      collectionBrowserColumnCountFromAspectRatios(ratios);
    const expectedCatalogValue =
      derivedColumnCount === COLLECTION_BROWSER_LANDSCAPE_COLUMN_COUNT
        ? COLLECTION_BROWSER_LANDSCAPE_COLUMN_COUNT
        : undefined;
    assert.equal(
      item[IOS_COLLECTION_BROWSER_COLUMN_COUNT_KEY],
      expectedCatalogValue,
      `${item.internal_slug} has stale iOS collection browser layout metadata`
    );
    if (expectedCatalogValue != null) {
      twoColumnCollectionCount += 1;
    }

    primaryTokenCount += payload.items.length;
    primaryByLowercasedFileName.set(fileName.toLowerCase(), { payload, ratios });
  }
  assert.equal(primaryTokenCount, 209_828);
  assert.equal(twoColumnCollectionCount, 47);

  for (const item of catalogItems) {
    const fileName = `${suggestedItemId(item)}.json`.toLowerCase();
    if (!primaryByLowercasedFileName.has(fileName)) {
      assert.equal(
        item[IOS_COLLECTION_BROWSER_COLUMN_COUNT_KEY],
        undefined,
        `${item.internal_slug} has layout metadata without a token manifest`
      );
    }
  }

  const widgetFileNames = fs.readdirSync(WIDGET_TOKENS_PATH)
    .filter((fileName) => path.extname(fileName) === ".json")
    .sort();
  assert.equal(widgetFileNames.length, 32);
  let widgetTokenCount = 0;
  for (const fileName of widgetFileNames) {
    const widgetPayload = readJSON(path.join(WIDGET_TOKENS_PATH, fileName));
    const widgetRatios = decodeAspectRatioMetadata(widgetPayload);
    assert.ok(widgetRatios, `${fileName} has no widget thumbnail aspect-ratio metadata`);
    assert.equal(widgetRatios.length, widgetPayload.items.length);

    const primary = primaryByLowercasedFileName.get(fileName.toLowerCase());
    assert.ok(primary, `${fileName} has no matching primary token manifest`);
    const primaryRatioById = new Map(
      tokenIdsFromPayload(primary.payload).map((id, index) => [id, primary.ratios[index]])
    );
    tokenIdsFromPayload(widgetPayload).forEach((id, index) => {
      assert.deepEqual(
        widgetRatios[index],
        primaryRatioById.get(id),
        `${fileName} token ${id} differs from its primary thumbnail ratio`
      );
    });
    widgetTokenCount += widgetPayload.items.length;
  }
  assert.equal(widgetTokenCount, 60_201);
});

test("Terraforms uses Mathcastles HTML primaries with unchanged CDN thumbnails", () => {
  const items = readJSON(ITEMS_PATH);
  const terraforms = items.find((item) => item.internal_slug === "terraforms");
  assert.ok(terraforms, "Expected Terraforms to be present in the suggested catalog");
  assert.equal(terraforms.tokenCount, 9844);
  assert.equal(terraforms.standardThumbsPathsAvailable, true);
  assert.equal(
    terraforms.standardThumbsBaseURL,
    "https://cdn.lil.org/player/terraforms/thumbs/"
  );

  const payload = readJSON(path.join(TOKENS_PATH, `${suggestedItemId(terraforms)}.json`));
  assert.equal(Object.prototype.hasOwnProperty.call(payload, "tmp_files"), false);
  assert.equal(payload.defaultFileExtension, "html");
  assert.deepEqual(payload.urlPrefixes, [
    "https://tokens.mathcastles.xyz/terraforms/token-html/",
  ]);
  assert.equal(payload.items.length, 9844);

  for (const [index, row] of payload.items.entries()) {
    assert.ok(Array.isArray(row), `Terraforms token ${index} is not a compact row`);
    assert.equal(row.length, 3, `Terraforms token ${index} has unexpected row metadata`);
    const [tokenId, prefixIndex, urlSuffix] = row;
    assert.equal(prefixIndex, 0, `Terraforms token ${index} has an unexpected prefix`);
    assert.equal(urlSuffix, tokenId, `Terraforms token ${index} has an unexpected URL suffix`);

    const sourceURL = tokenSourceURL(payload, row);
    assert.equal(
      sourceURL,
      `https://tokens.mathcastles.xyz/terraforms/token-html/${tokenId}`
    );
    assert.equal(resolvedFileExtension(payload, row, sourceURL), "html");
    assert.equal(
      standardThumbnailURL(sourceURL, terraforms.standardThumbsBaseURL).href,
      `https://cdn.lil.org/player/terraforms/thumbs/${tokenId}.webp`
    );
  }
});
