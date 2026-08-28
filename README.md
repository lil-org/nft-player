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

The script runs package tests first, then uses the first available iPhone simulator for the iOS tests. Override the destination or derived-data location when needed:

```sh
IOS_TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
TEST_DERIVED_DATA_PATH='build/custom-derived-data' \
scripts/test.sh
```

Derived data defaults to the ignored `build/test-derived-data` directory.

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
