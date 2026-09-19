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

The script runs package tests, hydrates pinned artwork sources for offline rendering tests, then uses the first available iPhone simulator for the iOS tests. Node.js is required for hydration. Override the destination or derived-data location when needed:

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

The hydrator verifies the catalog's byte counts and SHA-256 pins and downloads only missing or corrupt versions, with at most four requests at a time. Its `--check` mode is offline and makes no changes. Verified files live in ignored `build/test-artwork-sources/ArtworkScripts/<sha256>.<extension>` and are copied only into the test bundle. Rendering tests use these local files through an injected transport; they never download artwork sources. Swift package and Node unit tests do not require this artwork cache. Run the Node suite with `node --test tools/*.test.js`.

Artwork sources are hosted at `https://cdn.lil.org/player/scripts/<internal_slug>.<extension>` and are not committed or included in application bundles. `items.json` keeps renderer metadata in `script`, together with `expectedByteCount` and `sha256` for web artwork. Source extensions are `.html` for HTML, `.pde` for Processing, and `.js` otherwise; native renderers have no source descriptor. Publish immutable source URLs before updating pins. Use an absolute HTTPS `script.sourceURL` override for a new version so older app releases retain access to their pinned bytes. The application downloads each requested source version once and retains it without an expiry; missing or corrupt cached files are fetched again. tvOS may purge its system cache.

Token manifests in `Suggested Items/Suggested.bundle/Tokens` use named objects in `items`. Tokens with explicit media share a `urlPrefix` and provide their own `urlSuffix`, for example `{"id":"1","urlSuffix":"1.png","name":"Artwork"}`. URLs are reconstructed by concatenating the prefix and suffix; an empty or absent prefix allows full URLs in `urlSuffix`. A token's explicit `url` is used directly and takes precedence over `urlSuffix`. Import tools use the longest shared directory prefix, or an empty string when no common base exists, and preserve the selected media’s `fileExtension` on every token. Tokens can also carry `fileExtension`, `name`, and `hash` fields, or omit URLs to use their implicit media source. Media resolution uses the URL path extension first, then the token’s `fileExtension`; include this hint for extensionless URLs, even when a query parameter identifies the format. After changing token manifests, regenerate widget resources with `node scripts/generate-widget-resources.mjs`.

A top-level `aspectRatio` supplies the collection default for browser layout and fitted artwork playback. Ratios are positive-integer `[width, height]` pairs. Tokens inherit the default unless they supply their own `aspectRatio`, for example `{"id":"2","urlSuffix":"2.png","aspectRatio":[4,3]}`. A token ratio can also be used without a collection default; if neither exists, the app keeps its existing sizing fallback. Bundling tools preserve effective ratios by token ID when tokens are reordered or removed, choose the most-common ratio as the default (first appearance breaks ties), and write only exceptions on individual tokens.

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
