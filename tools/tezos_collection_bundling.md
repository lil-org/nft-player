# Tezos Collection Bundling

Use `tools/bundle_tezos_collections.js` to fetch Tezos FA2 collection tokens from TzKT and write them into the app's existing iOS downloadable collection bundle format.

## Inputs

The script accepts Tezos collection contract addresses as CLI arguments or from a text file:

```sh
node tools/bundle_tezos_collections.js --input tools/wip/tezos_collections.txt --dry-run
node tools/bundle_tezos_collections.js --input tools/wip/tezos_collections.txt --apply
```

It uses the public TzKT API by default:

```sh
https://api.tzkt.io
```

Use `--api-base-url` to point at another TzKT-compatible API.

By default, the script refuses to bundle collections above 15,000 tokens. Use `--max-tokens <number>` only when intentionally bundling a larger collection.

## Output

`--apply` writes:

- `Suggested Items/Suggested.bundle/Tokens/<contract>.json`
- `Suggested Items/Suggested.bundle/items.json`
- `Suggested Items/Covers.xcassets/<coverAssetId>.imageset/<coverAssetId>.jpg`
- `tools/reports/tezos-collection-bundle-report.md`
- `tools/reports/tezos-collection-bundle-report.json`

For Tezos bundles, `<coverAssetId>` is currently the same value as `<contract>`.

Cover generation requires ImageMagick, macOS `sips`, and Xcode `actool`. ImageMagick writes a static 300x300 JPEG from the first source frame with no alpha, flattened on an opaque black canvas; `--cover-quality` is passed to ImageMagick's JPEG encoder. The converter writes standard sRGB pixels with a standard sRGB ICC profile instead of preserving device/display profiles, which keeps colors stable across Apple platforms and avoids the pale-cover regression. Covers are JPEG instead of HEIC because tvOS/visionOS can render some bundled HEIF renditions as blank even when macOS and iOS decode them. The bundler validates each final JPEG structurally, validates the completed catalog with temporary tvOS/visionOS asset-catalog compiles, then fails the collection cover write if Apple tooling reports an unsafe cover.

Token JSON uses the iOS app's compact downloadable collection format:

```json
{
  "defaultFileExtension": "gif",
  "urlPrefixes": ["https://ipfs.io/ipfs/"],
  "items": [["0", 0, "QmHash"]]
}
```

Rows include a fourth extension field only when a token differs from `defaultFileExtension`.

If an existing token JSON contains a top-level `tmp_files` map, `--apply` preserves entries whose token ID is still present in `items`. It drops and reports stale token IDs, ignores invalid file names, and omits the map when no valid entries remain. This preservation reads only the existing token JSON; rebundling does not require `Originals Downloaded` to exist.

The bundler also preserves compact `thumbnailAspectRatios` metadata by token ID, so reordering or removing tokens cannot attach a ratio to the wrong asset. If a newly discovered token has no existing ratio, the bundler omits the incomplete metadata and reports the missing ID; regenerate the ratios before shipping.

## Media Policy

- Prefer token `artifactUri` and matching `formats[].uri` over display and thumbnail URLs.
- Fall back to `displayUri`, `image`, then `thumbnailUri` only when artifact/source media is missing, unavailable, or not app-supported.
- Normalize `ipfs://` and `ar://` URLs to HTTPS gateways. The Tezos helper uses `https://ipfs.io/ipfs/` for IPFS media because full MP4 reads from `https://ipfs.decentralized-content.com/ipfs/` can terminate early for some Tezos artifacts.
- Probe extensionless artifact/source URLs by content type. If the TzKT metadata exposes an app-playable MIME type, add the extension mapping instead of falling back to display or thumbnail media.
- Keep active playback to app-supported media: `png`, `jpg`, `jpeg`, `webp`, `heic`, `heif`, `gif`, `mp4`, and `mov`.
- Deduplicate by selected normalized file URL within each collection. The lowest numeric token id is kept; duplicate token ids are listed in the generated report.
- Warn on repeated normalized token names within each bundled collection. These warnings do not block bundling or remove tokens, because some collections intentionally reuse names, but they flag likely MP4/GIF or still/animated variants for manual review.
- Unsupported media, alternate candidates, duplicates, and missing media are listed in the generated report for review.

## Validation

After applying a bundle, run:

```sh
node --test tools/*.test.js
node scripts/generate-widget-resources.mjs --check
sips -g format -g pixelWidth -g pixelHeight -g hasAlpha -g samplesPerPixel -g profile "Suggested Items/Covers.xcassets/<coverAssetId>.imageset/<coverAssetId>.jpg"
magick identify -format "%m %[colorspace] %[channels] %w %h %[profiles]\n" "Suggested Items/Covers.xcassets/<coverAssetId>.imageset/<coverAssetId>.jpg"
xcodebuild -project nft-player.xcodeproj -scheme nft-player-ios -destination 'generic/platform=iOS' build
```

Before shipping, do a highest-resolution source audit against the TzKT metadata:

- Review `tools/reports/tezos-collection-bundle-report.json` and confirm every selected display, image, or thumbnail URL has no app-supported `artifactUri` or `formats[].uri` candidate.
- For extensionless artifact/source URLs, probe the response status and content type. If the media is available and app-playable, update the bundler MIME/extension mapping and rebundle.
- Keep a fallback only when artifact/source media is unavailable, unsupported by the iOS downloadable player, or a duplicate of an already bundled file.

Tezos collections are catalog-visible only in the iOS app, matching the Solana collection behavior.

## Removal

Use `tools/remove_bundled_collections.js` when a bundled collection needs to come back out of the app bundle:

```sh
node tools/remove_bundled_collections.js "Drawing Exercises"
node tools/remove_bundled_collections.js --apply "Drawing Exercises"
node tools/remove_bundled_collections.js --apply "KT1D9bUmPBXK1KgpgaTDjH6yNnBubof1ELzK"
```

The remover matches exact collection id, address, or collection name. `--apply` removes the matching `items.json` entry, `Tokens/<collectionId>.json`, and `Covers.xcassets/<coverAssetId>.imageset`.
