"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  INTERNAL_SLUG_PATTERN,
  IOS_COLLECTION_BROWSER_COLUMN_COUNT_KEY,
  suggestedItemId,
  withIOSCollectionBrowserColumnCount,
} = require("./suggested_items");
const {
  ASPECT_RATIOS_KEY,
  ASPECT_RATIO_OVERRIDES_KEY,
  COLLECTION_BROWSER_DEFAULT_COLUMN_COUNT,
  COLLECTION_BROWSER_LANDSCAPE_COLUMN_COUNT,
  collectionBrowserColumnCountFromAspectRatios,
  decodeAspectRatioMetadata,
  encodeAspectRatioMetadata,
  tokenIdsFromPayload,
} = require("./thumbnail_aspect_ratios");

const SUGGESTED_BUNDLE_PATH = path.resolve(__dirname, "../Suggested Items/Suggested.bundle");
const ARTISTS_PATH = path.join(SUGGESTED_BUNDLE_PATH, "artists.json");
const ITEMS_PATH = path.join(SUGGESTED_BUNDLE_PATH, "items.json");
const SCRIPTS_PATH = path.join(SUGGESTED_BUNDLE_PATH, "Scripts");
const TOKENS_PATH = path.join(SUGGESTED_BUNDLE_PATH, "Tokens");
const COVERS_PATH = path.resolve(__dirname, "../Suggested Items/Covers.xcassets");
const WIDGET_TOKENS_PATH = path.resolve(__dirname, "../Suggested Items/WidgetSuggested.bundle/Tokens");
const MANUAL_THREE_COLUMN_COLLECTION_SLUGS = [
  "blume",
  "moeshit",
  "screenshot_catalog",
  "skomra",
  "super_metal_mons_2",
];
const NATIVE_SCRIPT_THUMBNAIL_COLLECTIONS = new Set([
  "card_nft_2",
  "poncho_drifella",
]);
const NEW_CDN_COLLECTIONS = [
  {
    address: "0xcde288d791b10b38eca62e6e82a609541fab94e0",
    chain: "ethereum",
    chainId: 1,
    name: "Chair NFT",
    tokenCount: 1999,
    standardThumbsPathsAvailable: true,
    internal_slug: "chair_nft",
    artists: [],
  },
  {
    address: "36NQDyvCBqg4N1z5mZi2i4nW1K9ELdzmntMMKnqbChVZ",
    chain: "solana",
    chainId: 0,
    name: "Artifact Magazine 3",
    tokenCount: 593,
    standardThumbsPathsAvailable: true,
    sizedThumbsIndexOffset: 1,
    internal_slug: "artifact_magazine_3",
    artists: [],
  },
  {
    address: "3Rb9mG22dkAFVA8PVRgD76SiHUwUTK38Kq55NkrZuR2k",
    chain: "solana",
    chainId: 0,
    name: "Rare Weitsmans",
    tokenCount: 1968,
    standardThumbsPathsAvailable: true,
    internal_slug: "rare_weitsmans",
    artists: [],
  },
  {
    address: "Es6NZcYQpyo8wukzvznTHXbFXsGMWAP7YbyohEe77poo",
    chain: "solana",
    chainId: 0,
    name: "Tomodachi Void Club",
    tokenCount: 192,
    standardThumbsPathsAvailable: true,
    internal_slug: "tomodachi_void_club",
    artists: [],
  },
  {
    address: "KT1LiZ9cFA9fRQdKkbJtfz1djC7AkrTkTcDE",
    chain: "tezos",
    chainId: 0,
    name: "Friedeberg",
    tokenCount: 94,
    standardThumbsPathsAvailable: true,
    internal_slug: "friedeberg",
    artists: [],
  },
  {
    address: "KT1MSEve3ZVZWH1MVeWHTeafWq3sq2GYwMwC",
    chain: "tezos",
    chainId: 0,
    name: "Matchstick",
    tokenCount: 415,
    standardThumbsPathsAvailable: true,
    internal_slug: "matchstick",
    artists: [],
  },
  {
    address: "9irtKRLZkY4MjFFQNZPX3o6ZTszfR8kXFJXPBUvEDo9v",
    chain: "solana",
    chainId: 0,
    name: "Planet Peppa",
    tokenCount: 14997,
    standardThumbsPathsAvailable: true,
    internal_slug: "planet_peppa",
    artists: [],
  },
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

function sizedThumbnailURL(thumbnailURL, tokenIndex, width, thumbsBaseURL) {
  const fileName = `${tokenIndex}.webp`;
  if (thumbsBaseURL != null) {
    return new URL(`${width}/${fileName}`, thumbsBaseURL);
  }

  const url = new URL(thumbnailURL);
  const thumbnailParentPath = path.posix.dirname(url.pathname);
  url.pathname = `${thumbnailParentPath}/${width}/${fileName}`;
  return url;
}

function midImageURL(thumbnailURL) {
  const url = new URL(thumbnailURL);
  const thumbnailParentPath = path.posix.dirname(url.pathname);
  const collectionParentPath = path.posix.dirname(thumbnailParentPath);
  url.pathname = `${collectionParentPath}/mid/${path.posix.basename(url.pathname)}`;
  return url;
}

function largeImageURL(payload, sourceURL, thumbnailURL) {
  return payload.hasMid === false ? new URL(sourceURL) : midImageURL(thumbnailURL);
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

test("artist catalog is a slug-keyed dictionary with valid records", () => {
  const artists = readJSON(ARTISTS_PATH);
  assert.ok(
    artists != null && typeof artists === "object" && !Array.isArray(artists),
    "artists.json must contain an object keyed by artist slug"
  );
  assert.ok(Object.keys(artists).length > 0, "artists.json must not be empty");

  const allowedFields = new Set(["name", "x", "website", "bluesky", "collections"]);
  for (const [artistSlug, artist] of Object.entries(artists)) {
    assert.match(artistSlug, INTERNAL_SLUG_PATTERN, `Invalid artist slug ${artistSlug}`);
    assert.ok(
      artist != null && typeof artist === "object" && !Array.isArray(artist),
      `${artistSlug} must map to an artist object`
    );
    assert.deepEqual(
      Object.keys(artist).filter((field) => !allowedFields.has(field)),
      [],
      `${artistSlug} has unexpected fields`
    );
    assert.ok(
      typeof artist.name === "string" && artist.name.trim() !== "",
      `${artistSlug} has no valid name`
    );

    for (const linkField of ["x", "website", "bluesky"]) {
      if (Object.prototype.hasOwnProperty.call(artist, linkField)) {
        assert.ok(
          typeof artist[linkField] === "string" && artist[linkField].trim() !== "",
          `${artistSlug}.${linkField} must be a non-empty string when present`
        );
      }
    }

    assert.ok(Array.isArray(artist.collections), `${artistSlug}.collections must be an array`);
    assert.equal(
      new Set(artist.collections).size,
      artist.collections.length,
      `${artistSlug}.collections contains duplicate slugs`
    );
    for (const collectionSlug of artist.collections) {
      assert.equal(
        typeof collectionSlug,
        "string",
        `${artistSlug}.collections contains a non-string slug`
      );
      assert.match(
        collectionSlug,
        INTERNAL_SLUG_PATTERN,
        `${artistSlug}.collections contains invalid slug ${collectionSlug}`
      );
    }
  }
});

test("collection and artist catalogs have exact bidirectional links", () => {
  const items = readJSON(ITEMS_PATH);
  const artists = readJSON(ARTISTS_PATH);
  const itemsBySlug = new Map();

  for (const item of items) {
    assert.match(
      item.internal_slug,
      INTERNAL_SLUG_PATTERN,
      `${item.name ?? suggestedItemId(item)} has no valid internal_slug`
    );
    assert.equal(
      itemsBySlug.has(item.internal_slug),
      false,
      `Duplicate collection slug ${item.internal_slug}`
    );
    itemsBySlug.set(item.internal_slug, item);

    assert.ok(Array.isArray(item.artists), `${item.internal_slug}.artists must be an array`);
    assert.equal(
      new Set(item.artists).size,
      item.artists.length,
      `${item.internal_slug}.artists contains duplicate slugs`
    );
    for (const artistSlug of item.artists) {
      assert.equal(typeof artistSlug, "string", `${item.internal_slug}.artists contains a non-string slug`);
      assert.match(
        artistSlug,
        INTERNAL_SLUG_PATTERN,
        `${item.internal_slug}.artists contains invalid slug ${artistSlug}`
      );
      assert.ok(
        Object.prototype.hasOwnProperty.call(artists, artistSlug),
        `${item.internal_slug} references unknown artist ${artistSlug}`
      );
      assert.ok(
        artists[artistSlug].collections.includes(item.internal_slug),
        `${item.internal_slug} -> ${artistSlug} is missing the reverse artist link`
      );
    }
  }

  for (const [artistSlug, artist] of Object.entries(artists)) {
    assert.ok(Array.isArray(artist.collections), `${artistSlug}.collections must be an array`);
    for (const collectionSlug of artist.collections) {
      const item = itemsBySlug.get(collectionSlug);
      assert.ok(item, `${artistSlug} references unknown collection ${collectionSlug}`);
      assert.ok(
        item.artists.includes(artistSlug),
        `${artistSlug} -> ${collectionSlug} is missing the reverse collection link`
      );
    }
  }
});

test("catalog web URL overrides are absolute HTTP URLs", () => {
  const items = readJSON(ITEMS_PATH);

  for (const item of items) {
    for (const field of ["webURL", "collectionWebURL"]) {
      if (item[field] == null) continue;

      const url = new URL(item[field]);
      assert.ok(
        url.protocol === "http:" || url.protocol === "https:",
        `${item.internal_slug}.${field} must use HTTP or HTTPS`
      );
      assert.notEqual(
        url.hostname,
        "",
        `${item.internal_slug}.${field} must have a hostname`
      );
    }
  }
});

test("new CDN collections have their exact catalog metadata", () => {
  const items = readJSON(ITEMS_PATH);

  for (const expected of NEW_CDN_COLLECTIONS) {
    const item = items.find((candidate) => candidate.internal_slug === expected.internal_slug);
    assert.ok(item, `Missing ${expected.internal_slug}`);
    assert.deepEqual(
      Object.fromEntries(Object.keys(expected).map((key) => [key, item[key]])),
      expected
    );
  }
});

test("Artifact Magazine 3 uses one-based CDN media tiers", () => {
  const items = readJSON(ITEMS_PATH);
  const item = items.find((candidate) => candidate.internal_slug === "artifact_magazine_3");
  assert.ok(item, "Missing artifact_magazine_3");
  assert.equal(item.sizedThumbsIndexOffset, 1);

  const payload = readJSON(path.join(TOKENS_PATH, `${suggestedItemId(item)}.json`));
  assert.equal(payload.items.length, 593);
  assert.equal(payload.items[0][0], "3dJFRCd9VCKVBu4XRbuofqTyCqDE1jZHAmprKcU9otsm");
  assert.equal(payload.items.at(-1)[0], "2R53LsQgyUCeQtsd7r92nqdKd2AWEF2asYjpeRcZQbHP");

  for (const [tokenIndex, cdnIndex] of [[0, 1], [592, 593]]) {
    const sourceURL = tokenSourceURL(payload, payload.items[tokenIndex]);
    const thumbnailURL = standardThumbnailURL(sourceURL);
    assert.equal(sourceURL, `https://cdn.lil.org/player/artifact_magazine_3/${cdnIndex}.png`);
    assert.equal(thumbnailURL.href, `https://cdn.lil.org/player/artifact_magazine_3/thumbs/${cdnIndex}.webp`);
    assert.equal(midImageURL(thumbnailURL).href, `https://cdn.lil.org/player/artifact_magazine_3/mid/${cdnIndex}.webp`);
    for (const width of [140, 260]) {
      assert.equal(
        sizedThumbnailURL(thumbnailURL, tokenIndex + item.sizedThumbsIndexOffset, width).href,
        `https://cdn.lil.org/player/artifact_magazine_3/thumbs/${width}/${cdnIndex}.webp`
      );
    }
  }
});

test("Planet Peppa retains original filenames and uses original large images", () => {
  const item = readJSON(ITEMS_PATH).find((candidate) => candidate.internal_slug === "planet_peppa");
  assert.ok(item, "Missing planet_peppa");
  const payload = readJSON(path.join(TOKENS_PATH, `${suggestedItemId(item)}.json`));
  assert.equal(payload.isComplete, true);
  assert.equal(payload.hasMid, false);
  assert.equal(payload.defaultFileExtension, "webp");
  assert.equal(payload.items.length, item.tokenCount);
  assert.equal(new Set(tokenIdsFromPayload(payload)).size, item.tokenCount);
  assert.equal(payload.items.filter((row) => row[0].startsWith("unminted-")).length, 11268);
  assert.deepEqual(payload.thumbnailAspectRatios, [[1, 1]]);
  assert.equal(item.iosCollectionBrowserColumnCount, undefined);
  assert.equal(item.sizedThumbsIndexOffset, undefined);

  for (const [tokenIndex, fileIndex] of [[0, 0], [1501, 1502], [6479, 6481], [8965, 8968], [14996, 14999]]) {
    const sourceURL = tokenSourceURL(payload, payload.items[tokenIndex]);
    const thumbnailURL = standardThumbnailURL(sourceURL);
    assert.equal(sourceURL, `https://cdn.lil.org/player/planet_peppa/${fileIndex}.webp`);
    assert.equal(thumbnailURL.href, `https://cdn.lil.org/player/planet_peppa/thumbs/${fileIndex}.webp`);
    assert.equal(largeImageURL(payload, sourceURL, thumbnailURL).href, sourceURL);
    for (const width of [140, 260]) {
      assert.equal(
        sizedThumbnailURL(thumbnailURL, tokenIndex, width).href,
        `https://cdn.lil.org/player/planet_peppa/thumbs/${width}/${tokenIndex}.webp`
      );
    }
  }
});

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

test("eligible token manifests derive unique browse image tier URLs", () => {
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
    assert.ok(
      payload.hasMid == null || typeof payload.hasMid === "boolean",
      `${item.internal_slug} has an invalid mid image availability value`
    );
    assert.ok(Array.isArray(payload.items), `${item.internal_slug} has no token items array`);
    assert.ok(payload.items.length > 0, `${item.internal_slug} has an empty token manifest`);
    const sizedThumbsIndexOffset = item.sizedThumbsIndexOffset ?? 0;
    assert.ok(
      Number.isSafeInteger(sizedThumbsIndexOffset),
      `${item.internal_slug} has an invalid sized thumbnail index offset`
    );

    const originalURLByDerivedURL = new Map();
    const originalURLByLargeURL = new Map();
    const sizedURLsByWidth = new Map([
      [140, new Set()],
      [260, new Set()],
    ]);
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

      const largeURL = largeImageURL(payload, sourceURL, thumbnailURL);
      if (payload.hasMid === false) {
        assert.equal(largeURL.href, originalURL.href);
      } else {
        assert.equal(
          largeURL.pathname,
          `${path.posix.dirname(path.posix.dirname(thumbnailURL.pathname))}/mid/${expectedStem}.webp`,
          `${item.internal_slug} token ${index} derives an unexpected mid path`
        );
        assert.equal(largeURL.search, "");
        assert.equal(largeURL.hash, "");
      }

      for (const [width, sizedURLs] of sizedURLsByWidth) {
        const sizedThumbnailIndex = index + sizedThumbsIndexOffset;
        assert.ok(
          Number.isSafeInteger(sizedThumbnailIndex) && sizedThumbnailIndex >= 0,
          `${item.internal_slug} token ${index} derives an invalid sized thumbnail index`
        );
        const sizedURL = sizedThumbnailURL(thumbnailURL, sizedThumbnailIndex, width);
        assert.equal(
          sizedURL.pathname,
          `${path.posix.dirname(thumbnailURL.pathname)}/${width}/${sizedThumbnailIndex}.webp`,
          `${item.internal_slug} token ${index} derives an unexpected ${width} path`
        );
        assert.equal(sizedURL.search, "");
        assert.equal(sizedURL.hash, "");
        assert.equal(
          sizedURLs.has(sizedURL.href),
          false,
          `${item.internal_slug} has a duplicate ${width} URL at ${sizedURL.href}`
        );
        sizedURLs.add(sizedURL.href);
      }

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

      const previousLargeOriginalURL = originalURLByLargeURL.get(largeURL.href);
      if (previousLargeOriginalURL != null) {
        assert.equal(
          originalURL.href,
          previousLargeOriginalURL,
          `${item.internal_slug} has distinct originals colliding at ${largeURL.href}`
        );
      } else {
        originalURLByLargeURL.set(largeURL.href, originalURL.href);
      }
    }
  }
});

test("native browser thumbnails derive their sized tier layouts", () => {
  const cases = [
    {
      slug: "card_nft_2",
      thumbnailURL: "https://cdn.lil.org/nft/card_nft_2/fronts_1400/thumbs/0001.webp",
      sizedThumbsBaseURL: undefined,
      expectedBaseURL: "https://cdn.lil.org/nft/card_nft_2/fronts_1400/thumbs/",
    },
    {
      slug: "poncho_drifella",
      thumbnailURL: "https://cdn.lil.org/nft/poncho_drifella/fronts/thumbs/1.webp",
      sizedThumbsBaseURL: "https://cdn.lil.org/nft/poncho_drifella/thumbs/",
      expectedBaseURL: "https://cdn.lil.org/nft/poncho_drifella/thumbs/",
    },
  ];

  for (const entry of cases) {
    for (const width of [140, 260]) {
      assert.equal(
        sizedThumbnailURL(
          entry.thumbnailURL,
          0,
          width,
          entry.sizedThumbsBaseURL
        ).href,
        `${entry.expectedBaseURL}${width}/0.webp`,
        `${entry.slug} derives an unexpected ${width} path`
      );
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
  assert.equal(primaryFileNames.length, 224);

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
  let manualThreeColumnCollectionCount = 0;
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
    const expectedCatalogValue = withIOSCollectionBrowserColumnCount(
      item,
      derivedColumnCount
    )[IOS_COLLECTION_BROWSER_COLUMN_COUNT_KEY];
    assert.equal(
      item[IOS_COLLECTION_BROWSER_COLUMN_COUNT_KEY],
      expectedCatalogValue,
      `${item.internal_slug} has stale iOS collection browser layout metadata`
    );
    if (expectedCatalogValue === COLLECTION_BROWSER_LANDSCAPE_COLUMN_COUNT) {
      twoColumnCollectionCount += 1;
    } else if (expectedCatalogValue === COLLECTION_BROWSER_DEFAULT_COLUMN_COUNT) {
      manualThreeColumnCollectionCount += 1;
    }

    primaryTokenCount += payload.items.length;
    primaryByLowercasedFileName.set(fileName.toLowerCase(), { payload, ratios });
  }
  assert.equal(primaryTokenCount, 230_086);
  assert.equal(twoColumnCollectionCount, 39);
  assert.equal(
    manualThreeColumnCollectionCount,
    MANUAL_THREE_COLUMN_COLLECTION_SLUGS.length
  );
  assert.deepEqual(
    catalogItems
      .filter((item) =>
        item[IOS_COLLECTION_BROWSER_COLUMN_COUNT_KEY]
          === COLLECTION_BROWSER_DEFAULT_COLUMN_COUNT
      )
      .map((item) => item.internal_slug)
      .sort(),
    MANUAL_THREE_COLUMN_COLLECTION_SLUGS
  );

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
