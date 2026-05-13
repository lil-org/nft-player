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
node tools/check_bundled_collection_downloads.js --samples 5 --retries 3 --full --collection "<collection id or name>"
xcodebuild -project nft-folder.xcodeproj -scheme nft-folder-ios -destination 'generic/platform=iOS' build
```

For a full batch, omit `--collection` from the download checker if you want it to sample every bundled collection.

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

The remover matches exact collection id, address, or collection name. `--apply` removes the matching `items.json` entry, `Tokens/<collectionId>.json`, and `Covers.xcassets/<collectionId>.imageset`.
