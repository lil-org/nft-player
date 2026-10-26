# nft-player

ios / macos / visionos / tvos

download on the [app store](https://player.lil.org)

![nft player on apple tv](https://github.com/user-attachments/assets/abe9fe36-fa9d-4a49-9567-c435d8da6c2a)

> [!IMPORTANT]  
> big thanks to [nouns](https://nouns.camp) for supporting nft player with a [garden round](https://prop.house/0x6c7f962819d04c5e95a1ca750e8f076c9735da2b/2) grant

## development

Open `nft-player.xcodeproj` in Xcode to run the app. Install Node.js and an iPhone simulator runtime, then run the tooling, Swift package, and iOS tests:

```sh
scripts/test.sh
```

The script verifies generated metadata, prepares artwork fixtures, and selects the first available iPhone simulator. iOS tests run serially to avoid contention between WebKit renderers in simulator workers. Derived data defaults to the ignored `build/test-derived-data` directory. Override either setting when needed:

```sh
IOS_TEST_DESTINATION='platform=iOS Simulator,name=iPhone 18 Pro,OS=latest' \
TEST_DERIVED_DATA_PATH='build/custom-derived-data' \
scripts/test.sh
```

Before running iOS tests directly from Xcode, prepare their local fixtures:

```sh
node scripts/hydrate-artwork-test-sources.mjs
node scripts/hydrate-collection-test-manifests.mjs
```

Both hydrators support an offline `--check` mode. Rendering tests use the prepared fixtures; Swift package tests generate their own.

## reference

- [Catalog and artwork](docs/catalog.md): metadata, compact manifests, imports, CDN assets, and test fixtures.
- [Releasing](docs/releasing.md): App Store metadata, validation, releases, and version bumps with asc 1.9.1 or later.
