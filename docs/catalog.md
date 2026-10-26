# Catalog and artwork

## Catalog metadata

Collection metadata lives in `Suggested Items/items.json`, keyed by required, unique `internal_slug` values. Artist metadata lives in `Suggested Items/artists.json`. Both files are included directly in app resources. `Suggested Items/widget-eligible-collections.json` selects records for the generated `Suggested Items/widget-items.json` widget resource.

Downloadable media URLs concatenate the collection's `urlPrefix` and each token's `urlSuffix`; an empty or absent prefix allows full URLs in suffixes. Missing suffixes and URLs outside the asset policy are unsupported downloadable media. Media resolution uses the URL path extension first, then the first `ext` query parameter when the path has no extension, such as `1?ext=html`. Extension values are trimmed and lowercased; empty or unsupported values remain unclassified. Generative artwork and CDN previews use their separate rendering conventions.

The collection's `aspectRatio` supplies the default for browser layout and fitted playback. Ratios are positive-integer `[width, height]` pairs. Tokens inherit the default when their ratio column is absent or their entry is `null`. A token ratio can also exist without a collection default. If neither exists, the player uses its sizing fallback. `hasMid` defaults to `true` when absent or null; `false` uses original static images for the large browse tier.

Every manifest-backed collection requires generated catalog fields that support layout before a manifest loads:

- `manifestTokenCount` includes every source row. For downloadable collections, `tokenCount` counts only supported media.
- `hasUniformAspectRatio` is true only for a nonempty manifest whose effective token ratios all equal the normalized collection default. It is false when the default is missing or the manifest is empty.

The native ranged `card_nft_2` collection has no manifest and omits these generated fields. Collection destinations open before loading finishes. They show static placeholders only when catalog metadata guarantees a uniform ratio; otherwise the content area stays empty. Failed loads offer Retry, Back cancels the opening, and playback and saved-position restoration begin once the manifest is ready.

## Compact token manifests

Apps, widgets, and the metadata updater accept compact JSON version 2. Each file contains:

- `version: 2` and `count`.
- Exactly one ID representation: `firstId` for consecutive canonical nonnegative decimal strings ending at or below `Int64.max`, or an `ids` string array for other sequences.
- Optional `name`, `hash`, `urlSuffix`, `aspectRatio`, and `contractParameters` columns with exactly `count` entries. Missing values are `null`; entirely absent columns are omitted. Contract parameters are string-to-string objects.
- Optional sorted `excludedMediaIndices` identifying unsupported source rows. Omission means every row is accepted. Unsupported rows remain in the shared manifest; collection loading uses the indices and validates URLs when individual media descriptors are requested.

Complete predictable URL suffix columns use `urlTemplate: {value, suffix}` instead. `value` is `id`, `index0`, or `index1`, followed by the literal `suffix`. Index templates use the source position before downloadable filtering. Templates are chosen only when they reconstruct every suffix exactly. For example:

```json
{"version":2,"count":10000,"firstId":"0","urlTemplate":{"value":"id","suffix":".png"}}
```

This describes IDs 0–9999 with matching PNG suffixes. Serialized files are deterministically minified with a trailing newline.

## Updating metadata

Keep manifests in a separate directory, named `<internal_slug>.json`. Run the updater and regenerate widget metadata before publishing:

```sh
node scripts/update-token-metadata.mjs --manifest-directory /path/to/collections
node scripts/generate-widget-resources.mjs
node scripts/update-token-metadata.mjs --manifest-directory /path/to/collections --check
node scripts/generate-widget-resources.mjs --check
```

The updater defaults to the repository catalog; use `--items-path` for another catalog. It validates every input before writing, verifies that canonical encoding preserves ordered token values, and recomputes media exclusions with the same Foundation resolver as the app using Xcode's Swift toolchain. It preserves `tokenCount` and rejects missing manifests, malformed data, or downloadable counts that differ from supported media records. Update an intentionally changed `tokenCount` before regenerating.

The updater's `--check` mode writes nothing and detects stale metadata, exclusions, and noncanonical formatting. Widget generation needs only the catalog and eligibility list; its check detects missing or stale `widget-items.json`.

Row-based source imports shaped as `{"items":[{"id":"1","urlSuffix":"1.png","name":"Artwork"}]}` must first be converted explicitly:

```sh
node scripts/import-token-manifests.mjs \
  --input-directory /path/to/imports \
  --output-directory /path/to/collections
```

The importer reads flat `.json` files and also accepts version 2 files, so mixed source directories are supported. It preserves token order, values, and any sorted `excludedMediaIndices`. Input and output directories must be separate. Every source and existing output is validated before writes; conflicting output files are rejected and identical files are skipped. Then run the metadata commands above to compute catalog fields and media exclusions for publication.

## CDN sources and caching

Artwork sources live at `https://cdn.lil.org/player/scripts/<internal_slug>.<extension>` and are not committed or included in app bundles. The catalog's `script` object contains renderer metadata plus `expectedByteCount` and `sha256` for web artwork. Extensions are `.html` for HTML, `.pde` for Processing, and `.js` otherwise. Native renderers have no source descriptor.

Publish immutable source URLs before updating pins. Use an absolute HTTPS `script.sourceURL` override on `cdn.lil.org` for a new version so existing app releases retain access to their pinned bytes. The app downloads each requested source version once and caches it without expiry; missing or corrupt files are fetched again. tvOS may purge its system cache.

Token manifests live at `https://cdn.lil.org/player/collections/<internal_slug>.json` and are not committed or included in app or widget bundles. CDN collection paths are immutable once shipped: installations retain their first valid copy indefinitely. Apps and widgets download collections on demand and share validated files through the `group.org.lil.nft-folder` App Group. Files persist in Application Support without expiry or scheduled refresh; only missing or corrupt files are downloaded again. Concurrent requests share downloads, including across app and widget processes. tvOS uses its purgeable system cache. First use requires a network connection; cached collections work offline.

Remote artwork assets and redirects must use HTTPS on `cdn.lil.org`. Terraforms HTML at `https://tokens.mathcastles.xyz/terraforms/token-html/<numeric-token-id>?ext=html` is the sole external exception. Artwork HTML's Content Security Policy restricts remote dependencies to the CDN while supporting locally cached, inline, data, and blob content. Emoji render natively. Artist websites, block explorers, and other user-opened links are unaffected.

## Widgets

Widgets use the same manifests and retain source IDs for deep links and URL suffixes for media. Their generated catalog includes only identity, name, media settings, availability flags, and the script kind. They display mid WebP images, including static previews of video and animated artwork, or original static images when `hasMid` is `false`. Mid filenames preserve the original source stem, including zero padding. For web generative collections without token URL suffixes, widgets use `https://cdn.lil.org/player/<internal_slug>/mid/<zero-based-manifest-index>.webp`.

If an image cannot load, widgets retain an image cached under the current policy or show a black placeholder and retry after 30 minutes. Downloaded artwork is resized and cached locally as PNG. Widget choices and daily rotation follow platform availability rules. Each refresh resolves randomly sampled entries until it finds a supported image, without retaining arrays of token objects or image URLs. The shared manifest remains cached on disk.

## Test fixtures

Prepare fixtures before running iOS tests directly from Xcode:

```sh
node scripts/hydrate-artwork-test-sources.mjs
node scripts/hydrate-collection-test-manifests.mjs
```

The artwork hydrator verifies byte counts and SHA-256 pins. The collection hydrator validates compact manifests and catalog counts. Both download only missing or corrupt files, with at most four requests at a time. Their `--check` modes are offline and write nothing.

Fixtures live in ignored `build/test-artwork-sources/ArtworkScripts/<sha256>.<extension>` and `build/test-collection-manifests/CollectionManifests/<internal_slug>.json` directories and are copied only into the test bundle. Rendering tests inject these files and never download sources or manifests. Swift package tests use generated fixtures and require neither cache.
