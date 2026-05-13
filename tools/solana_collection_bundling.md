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

## Output

`--apply` writes:

- `Suggested Items/Suggested.bundle/Tokens/<collectionId>.json`
- `Suggested Items/Suggested.bundle/items.json`
- `Suggested Items/Covers.xcassets/<collectionId>.imageset/<collectionId>.heic`
- `tools/reports/solana-collection-bundle-report.md`
- `tools/reports/solana-collection-bundle-report.json`

Token JSON uses the iOS app's compact Solana format:

```json
{
  "defaultFileExtension": "png",
  "urlPrefixes": ["https://example.com/assets/"],
  "items": [["mint-address", 0, "1.png"]]
}
```

Rows include a fourth extension field only when a token differs from `defaultFileExtension`.

## Media Policy

- Prefer original `content.files[].uri` from Helius over CDN URLs.
- Fall back to `content.links.image`.
- Normalize `ipfs://` and `ar://` URLs to HTTPS gateways.
- Keep active playback to app-supported media: `png`, `jpg`, `jpeg`, `webp`, `heic`, `heif`, `gif`, and `mp4`.
- Prefer app-supported video/animated candidates (`mp4`, then `gif`) over static images when a token has both.
- Deduplicate by selected normalized file URL within each collection. Tokens are sorted first by token number/name hints, file basename hints, basename, then mint address; the first token in that order is kept.
- Unsupported media, alternate candidates, duplicates, and missing media are listed in the generated report for review.

## Validation

After applying a bundle, run:

```sh
node tools/check_bundled_collection_downloads.js --samples 5 --retries 3 --full --collection "<collection id or name>"
xcodebuild -project nft-folder.xcodeproj -scheme nft-folder-ios -destination 'generic/platform=iOS' build
```

For a full batch, omit `--collection` from the download checker if you want it to sample every bundled collection.

## Removal

Use `tools/remove_bundled_collections.js` when a bundled collection needs to come back out of the app bundle:

```sh
node tools/remove_bundled_collections.js "Collection Name"
node tools/remove_bundled_collections.js --apply "Collection Name"
node tools/remove_bundled_collections.js --apply "<collection id>"
```

The remover matches exact collection id, address, or collection name. `--apply` removes the matching `items.json` entry, `Tokens/<collectionId>.json`, and `Covers.xcassets/<collectionId>.imageset`.
