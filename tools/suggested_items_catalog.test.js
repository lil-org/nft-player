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
  COLLECTION_BROWSER_DEFAULT_COLUMN_COUNT,
  COLLECTION_BROWSER_LANDSCAPE_COLUMN_COUNT,
  collectionBrowserColumnCountFromAspectRatios,
  decodeAspectRatioMetadata,
  encodeAspectRatioMetadata,
  tokenIdsFromPayload,
} = require("./aspect_ratios");

const SUGGESTED_BUNDLE_PATH = path.resolve(__dirname, "../Suggested Items/Suggested.bundle");
const ARTISTS_PATH = path.join(SUGGESTED_BUNDLE_PATH, "artists.json");
const ITEMS_PATH = path.join(SUGGESTED_BUNDLE_PATH, "items.json");
const SCRIPTS_PATH = path.join(SUGGESTED_BUNDLE_PATH, "Scripts");
const TOKENS_PATH = path.join(SUGGESTED_BUNDLE_PATH, "Tokens");
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
const GENERATIVE_CDN_PREVIEW_COLLECTIONS = new Set([
  "archetype",
  "fidenza",
  "instructions_for_defacement",
  "meridian",
  "parnassus",
  "ringers",
  "the_eternal_pump",
]);
const NEW_CDN_COLLECTIONS = [
  {
    address: "0x495f947276749ce646f68ac8c248420045cb7b5e",
    collectionId: "minote",
    chain: "ethereum",
    chainId: 1,
    name: "Mi Note",
    tokenCount: 166,
    bundledDate: "2026-09-14",
    iosOnly: true,
    standardThumbsPathsAvailable: true,
    collectionWebURL: "https://opensea.io/collection/minote",
    internal_slug: "mi_note",
    artists: ["yomme"],
  },
  {
    address: "0xc22bd85e6d6c058226f46a693f0df4054496db5b",
    chain: "ethereum",
    chainId: 1,
    name: "Mi Note 3",
    tokenCount: 105,
    bundledDate: "2026-09-14",
    iosOnly: true,
    standardThumbsPathsAvailable: true,
    collectionWebURL: "https://opensea.io/collection/mi-note-3",
    internal_slug: "mi_note_3",
    artists: ["yomme"],
  },
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

function isSeptemberGenerativeCollection(item) {
  return item?.bundledDate === "2026-09-14" && item.generativeOnly === true;
}

function scriptCollectionIds() {
  return new Set(scriptCollectionKinds().keys());
}

function scriptCollectionKinds() {
  return new Map(
    readJSON(ITEMS_PATH)
      .filter((item) => item.script != null)
      .map((item) => [suggestedItemId(item), item.script.kind])
  );
}

function eligibleItems(items, scriptIds) {
  return items.filter((item) => !scriptIds.has(suggestedItemId(item)));
}

function tokenSourceURL(payload, token) {
  return token.url ?? (token.urlSuffix == null ? undefined : (payload.urlPrefix ?? "") + token.urlSuffix);
}

function tokenItem(payload, token) {
  const { urlSuffix, aspectRatio, ...item } = token;
  const url = tokenSourceURL(payload, token);
  return { ...item, ...(url == null ? {} : { url }) };
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
    row.fileExtension
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

test("Mi Note collections retain on-chain identities, names, and exported media order", () => {
  const items = readJSON(ITEMS_PATH);
  const samplesBySlug = {
    mi_note: [
      [0, "1792024277779561240403209846655221275479918327843323078189317850316310315009", "Angel Lady", "0"],
      [83, "1792024277779561240403209846655221275479918327843323078189317973461612625921", "Bear Raincoat", "83"],
      [165, "1792024277779561240403209846655221275479918327843323078189318095507403309057", "Kabukimono", "165"],
    ],
    mi_note_3: [
      [0, "2", "Crying Pajama Kid in an Alien Hat with Milady Fumo", "2"],
      [52, "60", "Alien Hat Ronin", "60"],
      [104, "117", "Drifella Employee 111", "117"],
    ],
  };

  for (const [slug, samples] of Object.entries(samplesBySlug)) {
    const item = items.find((candidate) => candidate.internal_slug === slug);
    const payload = readJSON(path.join(TOKENS_PATH, `${item.internal_slug}.json`));
    assert.equal(payload.items.length, item.tokenCount);
    assert.equal(new Set(tokenIdsFromPayload(payload)).size, item.tokenCount);
    assert.equal(item.iosCollectionBrowserColumnCount, undefined);
    assert.equal(item.sizedThumbsIndexOffset, undefined);
    assert.equal(payload.hasMid, undefined);
    for (const [index, compactRow] of payload.items.entries()) {
      const row = tokenItem(payload, compactRow);
      assert.equal(typeof row.name, "string");
      assert.ok(row.name.length > 0);
      assert.match(row.id, slug === "mi_note" ? /^\d{76}$/u : /^\d+$/u);
      const stem = slug === "mi_note" ? index : row.id;
      assert.equal(row.url, `https://cdn.lil.org/player/${slug}/${stem}.jpg`);
    }
    for (const [index, id, name, stem] of samples) {
      const row = tokenItem(payload, payload.items[index]);
      assert.deepEqual(row, { id, name, url: `https://cdn.lil.org/player/${slug}/${stem}.jpg` });
      const thumbnailURL = standardThumbnailURL(row.url);
      assert.equal(thumbnailURL.href, `https://cdn.lil.org/player/${slug}/thumbs/${stem}.webp`);
      assert.equal(largeImageURL(payload, row.url, thumbnailURL).href, `https://cdn.lil.org/player/${slug}/mid/${stem}.webp`);
      for (const width of [140, 260]) {
        assert.equal(sizedThumbnailURL(thumbnailURL, index, width).href, `https://cdn.lil.org/player/${slug}/thumbs/${width}/${index}.webp`);
      }
    }
  }
});

test("token manifests use named objects and a shared URL prefix in both bundles", () => {
  for (const directory of [TOKENS_PATH, WIDGET_TOKENS_PATH]) {
    for (const fileName of fs.readdirSync(directory).filter((name) => name.endsWith(".json"))) {
      const payload = readJSON(path.join(directory, fileName));
      for (const key of ["urlPrefixes", "aspectRatios", "aspectRatioOverrides"]) {
        assert.equal(Object.hasOwn(payload, key), false, `${fileName}: ${key}`);
      }
      for (const token of payload.items) {
        assert.ok(token != null && typeof token === "object" && !Array.isArray(token), fileName);
        assert.equal(typeof token.id, "string", fileName);
        if (token.urlSuffix != null) {
          assert.equal(typeof token.urlSuffix, "string", fileName);
          assert.equal(typeof payload.urlPrefix, "string", fileName);
          assert.equal(Object.hasOwn(token, "url"), false, fileName);
        }
      }
    }
  }
});

test("Artifact Magazine 3 uses one-based CDN media tiers", () => {
  const items = readJSON(ITEMS_PATH);
  const item = items.find((candidate) => candidate.internal_slug === "artifact_magazine_3");
  assert.ok(item, "Missing artifact_magazine_3");
  assert.equal(item.sizedThumbsIndexOffset, 1);

  const payload = readJSON(path.join(TOKENS_PATH, `${item.internal_slug}.json`));
  assert.equal(payload.items.length, 593);
  assert.equal(payload.items[0].id, "3dJFRCd9VCKVBu4XRbuofqTyCqDE1jZHAmprKcU9otsm");
  assert.equal(payload.items.at(-1).id, "2R53LsQgyUCeQtsd7r92nqdKd2AWEF2asYjpeRcZQbHP");

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
  const payload = readJSON(path.join(TOKENS_PATH, `${item.internal_slug}.json`));
  assert.equal(payload.isComplete ?? true, true);
  assert.equal(payload.hasMid, false);
  assert.equal(
    resolvedFileExtension(payload, payload.items[0], tokenSourceURL(payload, payload.items[0])),
    "webp"
  );
  assert.equal(payload.items.length, item.tokenCount);
  assert.equal(new Set(tokenIdsFromPayload(payload)).size, item.tokenCount);
  assert.equal(payload.items.filter((row) => row.id.startsWith("unminted-")).length, 11268);
  assert.deepEqual(payload.aspectRatio, [1, 1]);
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

test("catalog scripts pin remote sources without bundling artwork source files", async () => {
  const { artworkSourceDescriptors } = await import("../scripts/hydrate-artwork-test-sources.mjs");
  const items = readJSON(ITEMS_PATH);
  const tokenFileNames = fs.readdirSync(TOKENS_PATH)
    .filter((fileName) => path.extname(fileName) === ".json");
  assert.deepEqual(
    tokenFileNames.sort(),
    items.filter((item) => item.internal_slug !== "card_nft_2")
      .map((item) => `${item.internal_slug}.json`).sort()
  );

  const scriptedItems = items.filter((item) => item.script != null);
  assert.equal(scriptedItems.length, 407);
  const allowedFields = new Set([
    "kind", "renderingProfile", "nftPlayerDisplayTuning", "requiresInitialCanvas",
    "additionalLibraries", "isModule", "externalAssetDependencies", "projectId",
    "expectedByteCount", "sha256", "sourceURL",
  ]);
  for (const item of scriptedItems) {
    assert.equal(typeof item.script, "object", item.internal_slug);
    assert.equal(Array.isArray(item.script), false, item.internal_slug);
    assert.ok(typeof item.script.kind === "string" && item.script.kind.length > 0, item.internal_slug);
    assert.deepEqual(
      Object.keys(item.script).filter((field) => !allowedFields.has(field)),
      [],
      `${item.internal_slug} duplicates identity or source fields in script metadata`
    );
  }
  assert.deepEqual(
    scriptedItems.filter((item) => item.script.projectId != null)
      .map((item) => [item.internal_slug, item.script.projectId]),
    [["parnassus", "2"]]
  );

  const sources = artworkSourceDescriptors(items);
  assert.equal(sources.length, 405);
  assert.equal(sources.filter((source) => source.extension === "js").length, 402);
  assert.equal(sources.filter((source) => source.extension === "pde").length, 2);
  assert.equal(sources.filter((source) => source.extension === "html").length, 1);
  assert.equal(fs.existsSync(SCRIPTS_PATH), false, "Artwork sources must not be bundled with the app");
});

test("standard thumbnail availability covers downloadable, native, and bundled generative collections", () => {
  const items = readJSON(ITEMS_PATH);
  const scriptKinds = scriptCollectionKinds();
  const scriptIds = new Set(scriptKinds.keys());
  const expectedEnabledItems = [
    ...eligibleItems(items, scriptIds),
    ...items.filter((item) =>
      NATIVE_SCRIPT_THUMBNAIL_COLLECTIONS.has(item.internal_slug)
      || GENERATIVE_CDN_PREVIEW_COLLECTIONS.has(item.internal_slug)
      || isSeptemberGenerativeCollection(item)
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

test("September generative collections expose indexed CDN tiers without changing playback identity", () => {
  const items = readJSON(ITEMS_PATH).filter(isSeptemberGenerativeCollection);
  const widgetSlugs = new Set(readJSON(path.resolve(__dirname, "../Suggested Items/widget-eligible-collections.json")));
  assert.equal(items.length, 292);
  let count = 0;
  for (const item of items) {
    assert.equal(item.hasThumbnails, true, item.name);
    assert.equal(item.standardThumbsPathsAvailable, true, item.name);
    assert.equal(item.generativeOnly, true);
    assert.equal(item.iosOnly, true);
    assert.equal(item.hasCover, true);
    assert.equal(item.tokenCount, undefined);
    assert.equal(item.sizedThumbsIndexOffset, undefined);
    assert.equal(widgetSlugs.has(item.internal_slug), false);
    assert.equal(item.script.renderingProfile, "artBlocks");
    assert.ok(item.script.expectedByteCount > 0);
    assert.match(item.script.sha256, /^[a-f0-9]{64}$/u);
    const payload = readJSON(path.join(TOKENS_PATH, `${item.internal_slug}.json`));
    const ratios = decodeAspectRatioMetadata(payload);
    assert.equal(ratios.length, payload.items.length);
    const base = `https://cdn.lil.org/player/${item.internal_slug}`;
    const indicesById = new Map(tokenIdsFromPayload(payload).map((id, index) => [id, index]));
    assert.equal(indicesById.size, payload.items.length);
    for (const [index, token] of payload.items.entries()) {
      assert.equal(token.id, String(BigInt(item.abId) * 1000000n + BigInt(index)), item.name);
      assert.match(token.hash, /^0x[0-9a-fA-F]{64}$/u);
      assert.equal(indicesById.get(token.id), index);
      const thumbnailURL = new URL(`${base}/thumbs/${index}.webp`);
      assert.equal(midImageURL(thumbnailURL).href, `${base}/mid/${index}.webp`);
      assert.equal(sizedThumbnailURL(thumbnailURL, index, 260).href, `${base}/thumbs/260/${index}.webp`);
      assert.equal(sizedThumbnailURL(thumbnailURL, index, 140).href, `${base}/thumbs/140/${index}.webp`);
    }
    count += payload.items.length;
  }
  assert.equal(count, 143_847);
  const neighborhood = items.find(item => item.internal_slug === "neighborhood");
  assert.ok(neighborhood);
  const payload = readJSON(path.join(TOKENS_PATH, `${neighborhood.internal_slug}.json`));
  const ratios = decodeAspectRatioMetadata(payload);
  for (const [index, ratio] of [[0, [16, 9]], [3, [1, 1]], [7, [9, 16]]]) {
    assert.deepEqual(ratios[index], ratio);
    assert.equal(payload.items[index].id, String(146000000 + index));
  }
});

test("media extension resolution prefers URL, then token, then manifest defaults", () => {
  const payload = {
    defaultFileExtension: ".HTML",
    urlPrefix: "https://example.com/tokens/",
  };

  assert.equal(
    resolvedFileExtension(payload, { id: "1", urlSuffix: "1.svg", fileExtension: "mov" }, "https://example.com/tokens/1.svg"),
    "svg"
  );
  assert.equal(
    resolvedFileExtension(payload, { id: "2", urlSuffix: "2", fileExtension: ".MOV" }, "https://example.com/tokens/2"),
    "mov"
  );
  assert.equal(
    resolvedFileExtension(payload, { id: "3", urlSuffix: "3" }, "https://example.com/tokens/3"),
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
    const tokensPath = path.join(TOKENS_PATH, `${item.internal_slug}.json`);
    assert.ok(
      tokenFileNames.has(`${item.internal_slug}.json`),
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

test("bundled tokens have default and per-token aspect ratios with matching iOS layouts", () => {
  const primaryFileNames = fs.readdirSync(TOKENS_PATH)
    .filter((fileName) => path.extname(fileName) === ".json")
    .sort();
  assert.equal(primaryFileNames.length, 528);

  const catalogItems = readJSON(ITEMS_PATH);
  const catalogItemByFileName = new Map(
    catalogItems.map((item) => [
      `${item.internal_slug}.json`,
      item,
    ])
  );
  const primaryByFileName = new Map();
  let primaryTokenCount = 0;
  let twoColumnCollectionCount = 0;
  let manualThreeColumnCollectionCount = 0;
  for (const fileName of primaryFileNames) {
    const payload = readJSON(path.join(TOKENS_PATH, fileName));
    const catalogItem = catalogItemByFileName.get(fileName);
    if (isSeptemberGenerativeCollection(catalogItem)) {
      assert.equal(catalogItem.generativeOnly, true);
      assert.equal(catalogItem.iosOnly, true);
      assert.equal(catalogItem.tokenCount, undefined);
      assert.equal(catalogItem.bundledDate, "2026-09-14");
      assert.equal(catalogItem.hasThumbnails, true);
      assert.ok(payload.items.every(token => /^0x[0-9a-fA-F]{64}$/u.test(token.hash)));
    }
    const ratios = decodeAspectRatioMetadata(payload);
    assert.ok(ratios, `${fileName} has no aspect-ratio metadata`);
    assert.equal(Object.keys(payload).some(key => /^(artwork|thumbnail)AspectRatio/u.test(key)), false, fileName);
    assert.equal(ratios.length, payload.items.length, `${fileName} has incomplete aspect-ratio metadata`);
    assert.deepEqual(
      payload,
      encodeAspectRatioMetadata(payload, ratios),
      `${fileName} does not use the canonical default and per-token aspect ratios`
    );

    const item = catalogItemByFileName.get(fileName);
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
    primaryByFileName.set(fileName, { payload, ratios });
  }
  assert.equal(primaryTokenCount, 375_745);
  assert.equal(twoColumnCollectionCount, 76);
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
    const fileName = `${item.internal_slug}.json`;
    if (!primaryByFileName.has(fileName)) {
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
  assert.equal(widgetFileNames.length, 42);
  let widgetTokenCount = 0;
  for (const fileName of widgetFileNames) {
    const widgetPayload = readJSON(path.join(WIDGET_TOKENS_PATH, fileName));
    const primary = primaryByFileName.get(fileName);
    assert.ok(primary, `${fileName} has no matching primary token manifest`);
    const collection = catalogItems.find((item) => `${item.internal_slug}.json` === fileName);
    const mediaReferences = (payload) => payload.items.map((row) => {
      const id = row.id;
      const url = tokenSourceURL(payload, row)
        ?? (row.sh != null ? `https://cdn.simplehash.com/assets/${row.sh}` : undefined)
        ?? (collection.chain === "ethereum" ? `https://media-proxy.artblocks.io/${collection.address}/${id}.png` : undefined);
      return { id, url, fileExtension: url == null ? undefined : resolvedFileExtension(payload, row, url) };
    });
    assert.deepEqual(mediaReferences(widgetPayload), mediaReferences(primary.payload), fileName);
    assert.ok(Object.keys(widgetPayload).every((key) => ["items", "urlPrefix", "defaultFileExtension"].includes(key)), fileName);
    for (const row of widgetPayload.items) {
      assert.ok(
        Object.keys(row).every((key) => ["id", "url", "urlSuffix", "sh", "fileExtension"].includes(key)),
        fileName
      );
    }
    widgetTokenCount += widgetPayload.items.length;
  }
  assert.equal(widgetTokenCount, 61_742);
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

  const payload = readJSON(path.join(TOKENS_PATH, `${terraforms.internal_slug}.json`));
  assert.equal(Object.prototype.hasOwnProperty.call(payload, "tmp_files"), false);
  assert.equal(payload.defaultFileExtension, "html");
  assert.equal(payload.urlPrefix, "https://tokens.mathcastles.xyz/terraforms/token-html/");
  assert.equal(payload.items.length, 9844);

  for (const [index, row] of payload.items.entries()) {
    assert.deepEqual(Object.keys(row).sort(), ["id", "urlSuffix"], `Terraforms token ${index} has unexpected metadata`);
    const { id: tokenId, urlSuffix } = row;
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
