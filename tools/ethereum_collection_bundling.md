# Ethereum/EVM Collection Bundling

Use `tools/bundle_ethereum_collections.js` to fetch EVM collection assets from OpenSea and write them into the app's existing iOS downloadable collection bundle format.

## Inputs

The script accepts `chain:contract` values as CLI arguments or from a text file:

```sh
node tools/bundle_ethereum_collections.js --input tools/wip/ethereum_collections.txt --dry-run
node tools/bundle_ethereum_collections.js --input tools/wip/ethereum_collections.txt --apply
```

Use explicit chains for contracts that may exist on multiple networks:

```sh
node tools/bundle_ethereum_collections.js --apply \
  ethereum:0xeed41d06ae195ca8f5cacace4cd691ee75f0683f \
  ethereum:0x30f9efa712dde239a13a5fef1a8c7a6ac530a26d \
  base:0x41dc69132cce31fcbf6755c84538ca268520246f
```

Bare `0x...` addresses default to `ethereum`.

The script reads the OpenSea API key from `OPENSEA_API_KEY`, then from:

```sh
$HOME/Developer/secrets/tools/OPENSEA_API_KEY
```

By default, the script refuses to bundle collections above 15,000 tokens. Use `--max-tokens <number>` only when intentionally bundling a larger collection.

## Output

`--apply` writes:

- `Suggested Items/Suggested.bundle/Tokens/<collectionId>.json`
- `Suggested Items/Suggested.bundle/items.json`
- `Suggested Items/Covers.xcassets/<collectionId>.imageset/<collectionId>.heic`
- `tools/reports/ethereum-collection-bundle-report.md`
- `tools/reports/ethereum-collection-bundle-report.json`

Token JSON uses the iOS app's compact downloadable collection format:

```json
{
  "defaultFileExtension": "png",
  "urlPrefixes": ["https://i2c.seadn.io/base/0x.../"],
  "items": [["29122", 0, "asset.png"]]
}
```

Rows include a fourth extension field only when a token differs from `defaultFileExtension`.

## Collection IDs

Ethereum mainnet collections use the contract address as the bundle collection id. Non-mainnet EVM collections append a deterministic chain suffix so the same contract address can be bundled on multiple supported chains:

- `ethereum:0xabc...` -> `0xabc...`
- `base:0xabc...` -> `0xabc...base`
- `optimism:0xabc...` -> `0xabc...optimism`
- `zora:0xabc...` -> `0xabc...zora`

The corresponding `items.json` entries include `"iosOnly" : true`, so these downloadable OpenSea bundles appear only in the iOS catalog.

## Media Policy

- Fetch every OpenSea NFT page from `/api/v2/chain/{chain}/contract/{address}/nfts`.
- Prefer supported animated/video media from `original_animation_url`, `display_animation_url`, and `animation_url`.
- Prefer `original_image_url` for static image media when OpenSea provides it.
- For OpenSea `i*.seadn.io` cached derivative URLs, add and prefer the matching `raw2.seadn.io` URL only after app-supported original/source media candidates.
- Fall back to `image_url`, then `display_image_url`, only after original/raw media candidates.
- Do not replace `original_*` or metadata source URLs with OpenSea CDN/cache derivatives solely because the original URL uses IPFS or Arweave. Use cache/CDN media only when the original/source media is missing, unavailable, or not app-supported.
- Normalize `ipfs://` and `ar://` URLs to HTTPS gateways.
- Probe extensionless original/source and animation URLs by content type. If the API exposes an app-playable MIME type, add the extension mapping instead of falling back to a compressed derivative.
- Treat OpenSea derivative CDN URLs as preview-quality fallbacks. They should not be bundled when an original media URL or raw OpenSea media URL is available.
- Keep active playback to app-supported media: `png`, `jpg`, `jpeg`, `webp`, `heic`, `heif`, `gif`, `mp4`, and `mov`.
- Deduplicate by selected normalized file URL within each collection. Tokens are sorted by token id, token number/name hints, file basename hints, basename, then token id before deduplication, so the lowest numeric token id is kept.
- Warn on repeated normalized token names within each bundled collection.
- Unsupported media, alternate candidates, duplicates, and missing media are listed in the generated report for review.

## Validation

After applying a bundle, run:

```sh
node tools/check_bundled_collection_downloads.js --samples 5 --retries 3 --full --collection "<collection id or name>"
xcodebuild -project nft-folder.xcodeproj -scheme nft-folder-ios -destination 'generic/platform=iOS' build
```

For a full batch, omit `--collection` from the download checker if you want it to sample every bundled collection.

Before shipping, do a highest-resolution source audit against the OpenSea response data:

- Review `tools/reports/ethereum-collection-bundle-report.json` and confirm every selected CDN/cache, `raw2.*`, `image_url`, or `display_*` URL has no app-supported `original_*` or metadata source candidate.
- For extensionless `original_*` or metadata URLs, probe the response status and content type. If the media is available and app-playable, update the bundler MIME/extension mapping and rebundle instead of keeping a compressed fallback.
- Keep a fallback only when the original/source media is unavailable, unsupported by the iOS downloadable player, or a duplicate of an already bundled file.

## Removal

Use `tools/remove_bundled_collections.js` when a bundled collection needs to come back out of the app bundle:

```sh
node tools/remove_bundled_collections.js "DX Terminal"
node tools/remove_bundled_collections.js --apply "DX Terminal"
node tools/remove_bundled_collections.js --apply "0x41dc69132cce31fcbf6755c84538ca268520246fbase"
```

The remover matches exact collection id, address, or collection name. `--apply` removes the matching `items.json` entry, `Tokens/<collectionId>.json`, and `Covers.xcassets/<collectionId>.imageset`.
