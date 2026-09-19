# nft-player

ios / macos / visionos / tvos

download on the [app store](https://player.lil.org)

![nft player on apple tv](https://github.com/user-attachments/assets/abe9fe36-fa9d-4a49-9567-c435d8da6c2a)

> [!IMPORTANT]  
> big thanks to [nouns](https://nouns.camp) for supporting nft player with a [garden round](https://prop.house/0x6c7f962819d04c5e95a1ca750e8f076c9735da2b/2) grant

## development

Open `nft-player.xcodeproj` in Xcode to run the app. Run the complete Swift package and iOS test suites with:

```sh
scripts/test.sh
```

The script tests the compact token codec and generation tools, checks canonical token manifests and widget resources, runs package tests, hydrates pinned artwork sources for offline rendering tests, then uses the first available iPhone simulator for the iOS tests. Node.js is required for metadata checks and hydration. Override the destination or derived-data location when needed:

```sh
IOS_TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
TEST_DERIVED_DATA_PATH='build/custom-derived-data' \
scripts/test.sh
```

Derived data defaults to the ignored `build/test-derived-data` directory.

Before running iOS tests directly from Xcode, prepare their artwork sources:

```sh
node scripts/hydrate-artwork-test-sources.mjs
node scripts/hydrate-artwork-test-sources.mjs --check
```

The hydrator verifies the catalog's byte counts and SHA-256 pins and downloads only missing or corrupt versions, with at most four requests at a time. Its `--check` mode is offline and makes no changes. Verified files live in ignored `build/test-artwork-sources/ArtworkScripts/<sha256>.<extension>` and are copied only into the test bundle. Rendering tests use these local files through an injected transport; they never download artwork sources. Swift package tests do not require this artwork cache.

Artwork sources are hosted at `https://cdn.lil.org/player/scripts/<internal_slug>.<extension>` and are not committed or included in application bundles. `items.json` keeps renderer metadata in `script`, together with `expectedByteCount` and `sha256` for web artwork. Source extensions are `.html` for HTML, `.pde` for Processing, and `.js` otherwise; native renderers have no source descriptor. Publish immutable source URLs before updating pins. Use an absolute HTTPS `script.sourceURL` override for a new version so older app releases retain access to their pinned bytes. The application downloads each requested source version once and retains it without an expiry; missing or corrupt cached files are fetched again. tvOS may purge its system cache.

Token manifests in `Suggested Items/Suggested.bundle/Tokens` use compact JSON version 2. Each file has `version: 2`, `count`, and exactly one ID representation: `firstId` for consecutive canonical nonnegative decimal strings ending at or below `Int64.max`, or an `ids` string array for every other sequence. Optional `name`, `hash`, `urlSuffix`, `aspectRatio`, and `contractParameters` columns have exactly `count` entries, with `null` for missing values. Entirely absent columns are omitted. Contract parameters remain string-to-string objects. Files are deterministically minified with a trailing newline.

Complete predictable URL suffix columns become `urlTemplate: {value, suffix}`. `value` is `id`, `index0`, or `index1`, followed by the literal `suffix`; index templates use the original source position before downloadable filtering. For example, `{"version":2,"count":10000,"firstId":"0","urlTemplate":{"value":"id","suffix":".png"}}` describes IDs 0–9999 and matching PNG suffixes. Templates are chosen only when they reconstruct every original suffix exactly.

Collection metadata lives on the matching `internal_slug` record in `Suggested Items/Suggested.bundle/items.json`. Media URLs concatenate the collection’s `urlPrefix` and each token’s suffix; an empty or absent prefix allows full URLs in suffixes. Tokens without a suffix use their implicit media source. Media resolution uses the URL path extension first; when the path has no extension, it uses the first `ext` query parameter, such as `1?ext=html`. Extension values are trimmed and lowercased; empty or unsupported values remain unclassified.

The collection record’s `aspectRatio` supplies the default for browser layout and fitted artwork playback. Ratios are positive-integer `[width, height]` pairs. Tokens inherit the default when their ratio column is absent or their entry is `null`. A token ratio can also be used without a collection default; if neither exists, the app keeps its existing sizing fallback. Collection `hasMid` defaults to `true` when absent or null; `false` uses original static images for the large browse tier. Generated widget token files use the same compact schema with only IDs and URL suffixes, retaining every source row and original order. Collection defaults are copied into `WidgetSuggested.bundle/items.json`.

Collection records also contain generated `bundledTokenCount` and `hasUniformAspectRatio` fields so browser layout can use counts and uniform ratios without decoding token manifests. `bundledTokenCount` includes every source row. For downloadable collections, `tokenCount` counts only supported media. The generator stores sorted `excludedMediaIndices` for unsupported source rows; omission means every row is accepted. Collection loading uses these indices without parsing media URLs, and validates a URL when its individual descriptor is requested. Unsupported rows stay in the shared manifest for other consumers. `hasUniformAspectRatio` is true only for a nonempty manifest whose effective token ratios all equal the collection default after normalization; it is false when the default is missing or the manifest is empty. The native ranged `card_nft_2` collection has no token manifest and omits these fields.

After changing token manifests, collection aspect ratios, or collection URL metadata, normalize the main manifests and update catalog metadata before regenerating widget resources:

```sh
node scripts/update-token-metadata.mjs
node scripts/generate-widget-resources.mjs
node scripts/update-token-metadata.mjs --check
node scripts/generate-widget-resources.mjs --check
```

The updater accepts existing version 2 files and legacy imports shaped as `{"items":[{"id":"1","urlSuffix":"1.png","name":"Artwork"}]}`. Save an imported manifest under its collection slug and run the commands above; the compact file becomes its sole canonical copy. The app accepts version 2 only. Shared tooling in `tools/token_manifest.js` decodes, encodes, and serializes both import forms; aspect-ratio preservation reads compact files through this codec. The separately maintained external CLI is not changed here.

Before writing any files, the updater validates every input, checks that each compact conversion reconstructs identical ordered token values, and recomputes media exclusions through the same Foundation resolver as the app using Xcode's Swift toolchain. It preserves `tokenCount` and rejects malformed manifests, missing expected token files, or downloadable counts that differ from supported media records; adjust an intentionally changed `tokenCount` before regenerating. Its `--check` mode recomputes expected compact files, exclusions, and catalog fields without writing, detecting stale data after collection URL changes as well as noncanonical formatting. Widget generation copies updated collection metadata and produces the reduced compact manifests; its check also detects missing or extra generated files.

## app store
Install [asc](https://asccli.sh) and Node.js, then authenticate asc with App Store Connect. The release helper uses Node for JSON parsing; no npm packages are required.

The release metadata lives in `app_store/metadata/<platform>/app-info` and `app_store/metadata/<platform>/version/<version>`, screenshots live in `app_store/screenshots/<platform>`, and asc workflows live in `.asc/workflow.json`.

```sh
asc workflow run validate
asc workflow run release
asc workflow run bump
```

Release commands resolve the app from the project bundle id and read `MARKETING_VERSION` plus `CURRENT_PROJECT_VERSION` from `nft-player.xcodeproj`. Use `ASC_APP_ID`, `VERSION`, or `BUILD_NUMBER` only when an override is intentional.

Release settings are applied through asccli commands only. `usesIdfa` requires an asc release that exposes `asc versions update --uses-idfa`; the helper stops with an explicit error instead of mutating App Store Connect through a raw API fallback.

Use platform-specific workflows when needed:

```sh
asc workflow run metadata
asc workflow run screenshots
asc workflow run release PLATFORMS:macos,tvos,visionos
asc workflow run release_ios
asc workflow run release_macos
asc workflow run release_tvos
asc workflow run release_visionos
```

Use `DRY_RUN=1` with `scripts/asc-store.sh` commands to preview supported uploads, releases, and version bumps. The helper defaults `ASC_TIMEOUT` to `600s` for slower App Store Connect review-submission requests; set `ASC_TIMEOUT` explicitly to override it. If a review-submission request times out after App Store Connect accepts it, the helper verifies the remote version state and continues when the version is already in review.

## see also
[nft-player-cli](https://github.com/sameoldlab/nft-player-cli)
