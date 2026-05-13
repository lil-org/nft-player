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

## Output

`--apply` writes:

- `Suggested Items/Suggested.bundle/Tokens/<contract>.json`
- `Suggested Items/Suggested.bundle/items.json`
- `Suggested Items/Covers.xcassets/<contract>.imageset/<contract>.heic`
- `tools/reports/tezos-collection-bundle-report.md`
- `tools/reports/tezos-collection-bundle-report.json`

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
- Fall back to `displayUri`, `image`, then `thumbnailUri`.
- Normalize `ipfs://` and `ar://` URLs to HTTPS gateways. The Tezos helper uses `https://ipfs.io/ipfs/` for IPFS media because full MP4 reads from `https://ipfs.decentralized-content.com/ipfs/` can terminate early for some Tezos artifacts.
- Keep active playback to app-supported media: `png`, `jpg`, `jpeg`, `webp`, `heic`, `heif`, `gif`, and `mp4`.
- Deduplicate by selected normalized file URL within each collection. The lowest numeric token id is kept; duplicate token ids are listed in the generated report.
- Unsupported media, alternate candidates, duplicates, and missing media are listed in the generated report for review.

## Validation

After applying a bundle, run:

```sh
node tools/check_bundled_collection_downloads.js --samples 5 --retries 3 --full --collection "<collection id or name>"
xcodebuild -project nft-folder.xcodeproj -scheme nft-folder-ios -destination 'generic/platform=iOS' build
```

For a full batch, omit `--collection` from the download checker if you want it to sample every bundled collection.

Tezos collections are catalog-visible only in the iOS app, matching the Solana collection behavior.

## Removal

Use `tools/remove_bundled_collections.js` when a bundled collection needs to come back out of the app bundle:

```sh
node tools/remove_bundled_collections.js "Drawing Exercises"
node tools/remove_bundled_collections.js --apply "Drawing Exercises"
node tools/remove_bundled_collections.js --apply "KT1D9bUmPBXK1KgpgaTDjH6yNnBubof1ELzK"
```

The remover matches exact collection id, address, or collection name. `--apply` removes the matching `items.json` entry, `Tokens/<collectionId>.json`, and `Covers.xcassets/<collectionId>.imageset`.
