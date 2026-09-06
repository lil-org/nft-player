# Solana Collection Bundling

Use `tools/bundle_solana_collections.js` to fetch Solana collection assets from Helius DAS and write them into the app's existing bundle format.

## Inputs

The script accepts collection mint addresses as CLI arguments or from a text file:

```sh
node tools/bundle_solana_collections.js --input tools/wip/solana_collections.txt --dry-run
node tools/bundle_solana_collections.js --input tools/wip/solana_collections.txt --apply
```

It reads the Helius API key from `HELIUS_API_KEY`, then from:

```sh
$HOME/Developer/secrets/tools/HELIUS_API_KEY
```

By default, the script refuses to bundle collections above 15,000 assets. Use `--max-tokens <number>` only when intentionally bundling a larger collection.

## Output

`--apply` writes:

- `Suggested Items/Suggested.bundle/Tokens/<collectionId>.json`
- `Suggested Items/Suggested.bundle/items.json`
- `Suggested Items/Covers.xcassets/<coverAssetId>.imageset/<coverAssetId>.jpg`
- `tools/reports/solana-collection-bundle-report.md`
- `tools/reports/solana-collection-bundle-report.json`

For Solana bundles, `<coverAssetId>` is currently the same value as `<collectionId>`.

Cover generation requires ImageMagick, macOS `sips`, and Xcode `actool`. ImageMagick writes a static 300x300 JPEG from the first source frame with no alpha, flattened on an opaque black canvas; `--cover-quality` is passed to ImageMagick's JPEG encoder. The converter writes standard sRGB pixels with a standard sRGB ICC profile instead of preserving device/display profiles, which keeps colors stable across Apple platforms and avoids the pale-cover regression. Covers are JPEG instead of HEIC because tvOS/visionOS can render some bundled HEIF renditions as blank even when macOS and iOS decode them. The bundler validates each final JPEG structurally, validates the completed catalog with temporary tvOS/visionOS asset-catalog compiles, then fails the collection cover write if Apple tooling reports an unsafe cover.

Token JSON uses the iOS app's compact Solana format:

```json
{
  "defaultFileExtension": "png",
  "urlPrefixes": ["https://example.com/assets/"],
  "items": [["mint-address", 0, "1.png"]]
}
```

Rows include a fourth extension field only when a token differs from `defaultFileExtension`.

Static-image collections with standard thumbnails but no `/mid` files can set top-level `"hasMid": false`. The grid uses each original image for its large tier and retains thumbnails for non-static media. Regular and sized thumbnail paths stay unchanged. Both token row formats support the field, and rebundling preserves boolean values. Omitted or null values retain the existing `/mid` behavior.

If an existing token JSON contains a top-level `tmp_files` map, `--apply` preserves entries whose token mint is still present in `items`. It drops and reports stale token mints, ignores invalid file names, and omits the map when no valid entries remain. This preservation reads only the existing token JSON; rebundling does not require `Originals Downloaded` to exist.

The bundler also preserves compact `thumbnailAspectRatios` metadata by token mint, so reordering or removing tokens cannot attach a ratio to the wrong asset. If a newly discovered mint has no existing ratio, the bundler omits the incomplete metadata and reports the missing mint; regenerate the ratios before shipping.

## Media Policy

- Prefer original `content.files[].uri` from Helius over CDN URLs.
- Do not use `content.files[].cdn_uri` or `cdn.helius-rpc.com` media when an app-supported `content.files[].uri` is available.
- Fall back to `content.links.image` and `content.links.animation_url` only after original file URI candidates.
- Normalize `ipfs://` and `ar://` URLs to HTTPS gateways.
- Probe extensionless original/source URLs by content type. If the Helius response exposes an app-playable MIME type, add the extension mapping instead of falling back to CDN media.
- Keep active playback to app-supported media: `png`, `jpg`, `jpeg`, `webp`, `heic`, `heif`, `gif`, `mp4`, and `mov`.
- Prefer app-supported video/animated candidates (`mp4`, then `gif`) over static images when a token has both.
- Deduplicate by selected normalized file URL within each collection. Tokens are sorted first by token number/name hints, file basename hints, basename, then mint address; the first token in that order is kept.
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

Before shipping, do a highest-resolution source audit against the Helius response data:

- Review `tools/reports/solana-collection-bundle-report.json` and confirm every selected CDN/cache or `content.links.*` URL has no app-supported `content.files[].uri` candidate.
- For extensionless `content.files[].uri` URLs, probe the response status and content type. If the media is available and app-playable, update the bundler MIME/extension mapping and rebundle.
- Keep a fallback only when the original file URI is unavailable, unsupported by the iOS downloadable player, or a duplicate of an already bundled file.

## Removal

Use `tools/remove_bundled_collections.js` when a bundled collection needs to come back out of the app bundle:

```sh
node tools/remove_bundled_collections.js "Collection Name"
node tools/remove_bundled_collections.js --apply "Collection Name"
node tools/remove_bundled_collections.js --apply "<collection id>"
```

The remover matches exact collection id, address, or collection name. `--apply` removes the matching `items.json` entry, `Tokens/<collectionId>.json`, and `Covers.xcassets/<coverAssetId>.imageset`.
