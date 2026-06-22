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
- `Suggested Items/Covers.xcassets/<coverAssetId>.imageset/<coverAssetId>.heic`
- `tools/reports/tezos-collection-bundle-report.md`
- `tools/reports/tezos-collection-bundle-report.json`

For Tezos bundles, `<coverAssetId>` is currently the same value as `<contract>`.

Cover generation requires ImageMagick. Generated covers are static single-frame 300x300 HEIC files, three-channel RGB, no alpha channel, and flattened on an opaque black canvas. The converter strips non-color metadata but preserves an embedded ICC color profile when the source has one. The bundler validates the final file and fails the collection cover write if the output is not decode-safe for tvOS/visionOS.

Token JSON uses the iOS app's compact downloadable collection format:

```json
{
  "defaultFileExtension": "gif",
  "urlPrefixes": ["https://ipfs.io/ipfs/"],
  "items": [["0", 0, "QmHash"]]
}
```

Rows include a fourth extension field only when a token differs from `defaultFileExtension`.

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
node tools/check_bundled_collection_downloads.js --samples 5 --retries 3 --full --collection "<collection id or name>"
sips -g format -g pixelWidth -g pixelHeight -g hasAlpha -g samplesPerPixel -g profile "Suggested Items/Covers.xcassets/<coverAssetId>.imageset/<coverAssetId>.heic"
heif-info "Suggested Items/Covers.xcassets/<coverAssetId>.imageset/<coverAssetId>.heic"
xcodebuild -project nft-player.xcodeproj -scheme nft-player-ios -destination 'generic/platform=iOS' build
```

For a full batch, omit `--collection` from the download checker if you want it to sample every bundled collection.

Before shipping, do a highest-resolution source audit against the TzKT metadata:

- Review `tools/reports/tezos-collection-bundle-report.json` and confirm every selected display, image, or thumbnail URL has no app-supported `artifactUri` or `formats[].uri` candidate.
- For extensionless artifact/source URLs, probe the response status and content type. If the media is available and app-playable, update the bundler MIME/extension mapping and rebundle.
- Keep a fallback only when artifact/source media is unavailable, unsupported by the iOS downloadable player, or a duplicate of an already bundled file.

## Deep Dedup

The Tezos bundler removes duplicate selected media URLs during the initial TzKT import. To audit already-bundled collections more deeply, use the reusable bundled-collection dedup tool:

```sh
node tools/deep_dedup_bundled_collections.js --chain tezos --dry-run
node tools/deep_dedup_bundled_collections.js --chain tezos --apply
```

The tool resolves each bundled media URL, hashes the fetched file bytes, and removes later token rows that duplicate either the exact same URL or the same `byteCount + sha256` content within a collection. It rewrites compact token rows and updates `items.json` token counts when rows are removed.

Tezos collections are catalog-visible only in the iOS app, matching the Solana collection behavior.

## Removal

Use `tools/remove_bundled_collections.js` when a bundled collection needs to come back out of the app bundle:

```sh
node tools/remove_bundled_collections.js "Drawing Exercises"
node tools/remove_bundled_collections.js --apply "Drawing Exercises"
node tools/remove_bundled_collections.js --apply "KT1D9bUmPBXK1KgpgaTDjH6yNnBubof1ELzK"
```

The remover matches exact collection id, address, or collection name. `--apply` removes the matching `items.json` entry, `Tokens/<collectionId>.json`, and `Covers.xcassets/<coverAssetId>.imageset`.
