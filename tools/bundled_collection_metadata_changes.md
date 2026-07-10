# Bundled Collection Metadata Changes

This document records the metadata-facing changes made by the downloadable collection source audit. The generated audit and downloader reports live under `tools/reports/`, but that directory is ignored by git; this file is the tracked summary.

The subsequent full-download dimension audit and its 482 additional token URL corrections are documented in `tools/downloaded_collection_quality_changes.md`.

## Scope

- Audited downloadable collections in `Suggested Items/Suggested.bundle`.
- Excluded collections whose bundled token media resolves to `cdn.lil.org` or whose native renderer is explicitly backed by `cdn.lil.org`.
- Fetched source inventories from OpenSea, Helius, and TzKT, then rewrote only token metadata that was incomplete or pointed at a lower-quality fallback when a supported original/source URL was available.
- Preserved collection ordering, names, covers, and item metadata except for `tokenCount` updates listed below.
- Did not add private audit fields to token JSON.

## Files Changed

- `Suggested Items/Suggested.bundle/items.json`
  - Updated `tokenCount` for collections whose API inventory did not match the previous bundled count.
- `Suggested Items/Suggested.bundle/Tokens/*.json`
  - Rewrote token rows to point at source/original media where reachable and app-supported.
  - Converted many `sh` SimpleHash rows and EVM ID-only Art Blocks fallback rows into compact `urlPrefixes` rows.
  - Kept compact token JSON where possible.
- `tools/audit_bundled_collection_sources.js`
  - Added the reusable dry-run/apply audit and rebundle tool used for these changes.

## Skipped CDN-Owned Collections

These collections are excluded because their resolved bundled media URLs contain `cdn.lil.org` or their native renderer is CDN-managed:

| Chain | Collection |
| --- | --- |
| ethereum | Super Metal Mons! |
| ethereum | Super Metal Mons!! |
| solana | card nft |
| solana | Drifella 2 |
| solana | Poncho Drifella |
| solana | Card NFT 2 |

## Native CDN Restoration

The source-audit commit incorrectly treated the two native Metal card collections as ordinary Solana inventories even though their curated renderers load card fronts and effects from `cdn.lil.org`.

- Restored `Poncho Drifella` to its exact pre-audit token file: 207 ordered ID-only rows used by the native renderer.
- Removed the audit-added 6,896-row `Card NFT 2` token file so the native renderer again supplies its generated collection.
- Removed the audit-added `tokenCount` values for both items.
- Added explicit collection-ID guards to the Solana bundler, source audit, originals downloader, and downloaded-quality audit. These collections remain excluded even though their token JSON does not contain a literal CDN URL.

## `items.json` Token Count Changes

| Chain | Collection | `tokenCount` |
| --- | --- | --- |
| ethereum | Nouns | `1889` -> `1933` |
| ethereum | Constant | `15` -> `40` |
| ethereum | screenshot catalog | `319` -> `331` |
| solana | ICSA | `2865` -> `2899` |
| solana | Record of Hyperwar | `548` -> `549` |
| solana | little swag world | `3323` -> `3327` |
| solana | Organic Evolution | `69` -> `72` |
| tezos | BESTIARY | `23` -> `24` |
| tezos | Drawing Exercises | `76` -> `79` |
| tezos | moeshit | `1526` -> `1593` |
| tezos | real world data | `126` -> `129` |
| tezos | Multi Windows | `191` -> `208` |
| tezos | skomra | `128` -> `140` |

## Token Metadata Changes By Collection

`Rows` is the token row count in the bundled token JSON before and after the audit. `Format` describes the dominant row encoding before and after. `Media source changes` summarizes URL source upgrades or canonicalization by count.

| Chain | Collection | Rows | Format | Media source changes | Metadata action |
| --- | ---: | ---: | --- | --- | --- |
| base | Babes | `339` -> `339` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 321; SimpleHash CDN -> app IPFS gateway: 18 | Rewrote 339 URLs. |
| ethereum | 0xmons | `341` -> `341` | `sh` object -> compact | SimpleHash CDN -> ipfs.io: 341 | Rebuilt all rows from contract `tokenURI.image` IPFS GIFs after verifying OpenSea WebP/raw candidates were modified derivatives for some tokens. |
| ethereum | Allstarz | `10000` -> `10000` | compact -> compact | app IPFS gateway -> OpenSea raw: 2 | Rewrote 2 URLs. |
| ethereum | Allstarz PSX | `2500` -> `2500` | compact -> compact | app IPFS gateway -> OpenSea raw: 4 | Rewrote 4 URLs. |
| ethereum | Archetype | `600` -> `600` | ID-only object -> compact | Art Blocks media proxy -> OpenSea raw: 399; Art Blocks media proxy -> Art Blocks media proxy: 15 | Rewrote 414 URLs and replaced ID-only rows. |
| ethereum | Beyond the Veil | `24` -> `24` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 24 | Rewrote 24 URLs. |
| ethereum | Bibos | `1111` -> `1111` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 1110 | Rewrote 1110 URLs. |
| ethereum | Bloomers | `502` -> `502` | compact -> compact | OpenSea derivative -> OpenSea raw: 500 | Rewrote 500 URLs. |
| ethereum | Bonkler | `150` -> `150` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 83 | Rewrote 83 URLs. |
| ethereum | CAR | `999` -> `999` | URL object / ID-only object -> compact | SimpleHash CDN -> OpenSea raw: 979; SimpleHash CDN -> Arweave: 15; Art Blocks media proxy -> OpenSea raw: 3 | Rewrote 997 URLs and replaced ID-only rows. |
| ethereum | Changing Places | `500` -> `500` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 477; SimpleHash CDN -> app IPFS gateway: 23 | Rewrote 500 URLs. |
| ethereum | Constant | `15` -> `40` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 14; SimpleHash CDN -> project source SVG service: 1; added source SVG service rows: 25 | Added 25 tokens, rewrote 15 existing URLs, then replaced OpenSea display-animation HTML wrappers with OpenSea `original_image_url` SVG source URLs where available. |
| ethereum | COSMOS | `60` -> `60` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 60 | Rewrote 60 URLs. |
| ethereum | Crowded Fields | `41` -> `41` | URL object / ID-only object -> compact | SimpleHash CDN -> OpenSea raw: 40; Art Blocks media proxy -> OpenSea raw: 1 | Rewrote 41 URLs and replaced ID-only rows. |
| ethereum | EMOJIPACK | `71` -> `71` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 71 | Rewrote 71 URLs. |
| ethereum | Fidenza | `999` -> `999` | ID-only object -> compact | Art Blocks media proxy -> OpenSea raw: 814; Art Blocks media proxy -> Art Blocks media proxy: 5 | Rewrote 819 URLs and replaced ID-only rows. |
| ethereum | Fifty Ways of Looking at a Poem | `44` -> `44` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 40; SimpleHash CDN -> Arweave: 4 | Rewrote 44 URLs. |
| ethereum | Finiliar | `10000` -> `10000` | URL object / ID-only object -> compact | SimpleHash CDN / ID-only fallback -> Turbo gateway: 9725; SimpleHash CDN / ID-only fallback -> OpenSea raw: 191; SimpleHash CDN / ID-only fallback -> Permagate: 84 | Rewrote 10000 URLs and replaced ID-only rows. Preferred OpenSea `original_animation_url` MP4s, then used reachable source fallbacks for 657 slow/broken gateway rows found by a full 10000-row range probe sweep. |
| ethereum | Flore Perdue | `100` -> `100` | ID-only object -> compact | Art Blocks media proxy -> OpenSea raw: 79; Art Blocks media proxy -> Art Blocks media proxy: 21 | Rewrote 100 URLs and replaced ID-only rows. |
| ethereum | Fragments of an Infinite Field | `1024` -> `1024` | ID-only object -> compact | Art Blocks media proxy -> OpenSea raw: 836; Art Blocks media proxy -> Art Blocks media proxy: 5 | Rewrote 841 URLs and replaced ID-only rows. |
| ethereum | IMAGINED WRECKAGE | `96` -> `96` | URL object / ID-only object -> compact | SimpleHash CDN -> OpenSea raw: 91; Art Blocks media proxy -> OpenSea raw: 4; SimpleHash CDN -> 0prod.infura-ipfs.io: 1 | Rewrote 96 URLs and replaced ID-only rows. |
| ethereum | Instructions for Defacement | `712` -> `712` | ID-only object -> compact | Art Blocks media proxy -> OpenSea raw: 488; Art Blocks media proxy -> Art Blocks media proxy: 7 | Rewrote 495 URLs and replaced ID-only rows. |
| ethereum | Landscape Sublime | `18` -> `18` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 18 | Rewrote 18 URLs. |
| ethereum | Letters to My Future Self | `1000` -> `1000` | ID-only object -> compact | Art Blocks media proxy -> OpenSea raw: 881 | Rewrote 881 URLs and replaced ID-only rows. |
| ethereum | Lost Memories | `69` -> `69` | compact -> compact | 0prod.infura-ipfs.io -> OpenSea raw: 8; 0prod.infura-ipfs.io -> 0prod.infura-ipfs.io: 2 | Rewrote 10 URLs. |
| ethereum | Math Art | `100` -> `100` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 100 | Rewrote 100 URLs. |
| ethereum | Meridian | `1000` -> `1000` | ID-only object -> compact | Art Blocks media proxy -> OpenSea raw: 767; Art Blocks media proxy -> Art Blocks media proxy: 6 | Rewrote 773 URLs and replaced ID-only rows. |
| ethereum | Nouns | `1889` -> `1933` | compact -> compact | no media source changes | Added 44 tokens and updated `items.json`. |
| ethereum | Parnassus | `100` -> `100` | `sh` object -> compact | SimpleHash CDN -> Art Blocks media proxy: 100 | Rewrote 100 URLs. |
| ethereum | pfp+ | `376` -> `376` | compact -> compact | OpenSea derivative -> OpenSea raw: 376 | Rewrote 376 URLs. |
| ethereum | Red Trucks | `50` -> `50` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 45; SimpleHash CDN -> Arweave: 5 | Rewrote 50 URLs. |
| ethereum | Ringers | `1000` -> `1000` | ID-only object -> compact | Art Blocks media proxy -> OpenSea raw: 701; Art Blocks media proxy -> Art Blocks media proxy: 10 | Rewrote 711 URLs and replaced ID-only rows. |
| ethereum | screenshot catalog | `319` -> `331` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 319 | Added 12 tokens, rewrote 319 URLs, and updated `items.json`. |
| ethereum | Sproto Gremlins | `3333` -> `3333` | compact -> compact | OpenSea derivative -> OpenSea raw: 2815; OpenSea derivative -> app IPFS gateway: 515 | Rewrote 3330 URLs. |
| ethereum | Storms | `75` -> `75` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 75 | Rewrote 75 URLs. |
| ethereum | Temporals | `222` -> `222` | `sh` object -> compact | SimpleHash CDN -> temporals-api S3 media: 222 | Rewrote 222 URLs. |
| ethereum | The Abyssal Unseen | `1000` -> `1000` | `sh` object -> compact | SimpleHash CDN -> ipfs.io: 1000 | Rewrote all rows to OpenSea `original_animation_url` CIDs. Switched equivalent IPFS gateway from `ipfs.decentralized-content.com` to `ipfs.io` after full-download validation showed `ipfs.io` completed large MP4 downloads reliably. |
| ethereum | The Eternal Pump | `50` -> `50` | ID-only object -> compact | Art Blocks media proxy -> OpenSea raw: 35; Art Blocks media proxy -> Art Blocks media proxy: 15 | Rewrote 50 URLs and replaced ID-only rows. |
| ethereum | Tokyo Nude | `55` -> `55` | `sh` object -> compact | SimpleHash CDN -> OpenSea raw: 55 | Rewrote 55 URLs. |
| ethereum | Vacation | `428` -> `428` | URL object / ID-only object -> compact | SimpleHash CDN -> OpenSea raw: 382; Art Blocks media proxy -> OpenSea raw: 40; SimpleHash CDN -> 0prod.infura-ipfs.io: 4; Art Blocks media proxy -> 0prod.infura-ipfs.io: 2 | Rewrote 428 URLs and replaced ID-only rows. |
| solana | ICSA | `2865` -> `2899` | compact -> compact | no media source changes | Added 34 tokens and updated `items.json`. |
| solana | little swag world | `3323` -> `3327` | compact -> compact | Helius CDN -> Lighthouse IPFS gateway: 3296; ipfs.io -> Lighthouse IPFS gateway: 19; ipfs.filebase.io -> Lighthouse IPFS gateway: 6; dweb.link -> Lighthouse IPFS gateway: 1; Pinata gateway -> Lighthouse IPFS gateway: 1 | Added 4 tokens, rewrote 3323 URLs, and updated `items.json`. |
| solana | Little Swag World: HEXP | `332` -> `332` | compact -> compact | gateway.irys.xyz -> gateway.irys.xyz: 2 | Rewrote 2 URLs. |
| solana | Organic Evolution | `69` -> `72` | compact -> compact | no media source changes | Added 3 tokens and updated `items.json`. |
| solana | Record of Hyperwar | `548` -> `549` | compact -> compact | gateway.irys.xyz -> gateway.irys.xyz: 548 | Added 1 token, rewrote 548 URLs, and updated `items.json`. |
| solana | Scarecrow | `4048` -> `4048` | compact -> compact | Permagate -> Arweave: 897; Arweave -> gateway.irys.xyz: 173 | Rewrote 1070 URLs. |
| solana | swag pack | `467` -> `467` | compact -> compact | gateway.irys.xyz -> gateway.irys.xyz: 66 | Rewrote 66 URLs. |
| solana | TOJIA | `4438` -> `4438` | compact -> compact | Arweave -> gateway.irys.xyz: 4438 | Rewrote 4438 URLs. |
| solana | Vehicle Wammin | `1289` -> `1289` | compact -> compact | gateway.pinit.io -> gateway.pinit.io: 1 | Rewrote 1 URL. |
| tezos | BESTIARY | `23` -> `24` | compact -> compact | no media source changes | Added 1 token and updated `items.json`. |
| tezos | Drawing Exercises | `76` -> `79` | compact -> compact | ipfs.io -> ipfs.io: 17 | Added 3 tokens, rewrote 17 URLs, and updated `items.json`. |
| tezos | moeshit | `1526` -> `1593` | compact -> compact | ipfs.io -> ipfs.io: 262 | Added 67 tokens, rewrote 262 URLs, and updated `items.json`. |
| tezos | Multi Windows | `191` -> `208` | compact -> compact | ipfs.io -> ipfs.io: 36 | Added 17 tokens, rewrote 36 URLs, and updated `items.json`. |
| tezos | real world data | `126` -> `129` | compact -> compact | ipfs.io -> ipfs.io: 43 | Added 3 tokens, rewrote 43 URLs, and updated `items.json`. |
| tezos | skomra | `128` -> `140` | compact -> compact | ipfs.io -> ipfs.io: 4 | Added 12 tokens, rewrote 4 URLs, and updated `items.json`. |

## Follow-up Source Quality Corrections

- Restored apparent media-class regressions found by an independent `HEAD` vs worktree scanner:
  - Lost Memories static JPG rows were restored to OpenSea `original_animation_url` MP4s.
  - Little Swag World: HEXP static PNG rows were restored to Helius `content.files[]` MP4s.
  - Tezos rows in Drawing Exercises, real world data, Multi Windows, and moeshit were restored from display/thumbnail files to `artifactUri` GIF/MP4 source files.
- Rebuilt `0xmons` from contract `tokenURI.image` IPFS GIFs because sampled old SimpleHash GIFs matched the tokenURI GIF byte sizes, while OpenSea WebP/raw candidates were smaller modified derivatives.
- Directly rebuilt Finiliar and The Abyssal Unseen from OpenSea source fields:
  - Finiliar uses source MP4s where reachable, with reachable OpenSea raw display MP4/MOV or source GIF fallbacks where the declared original MP4 gateway failed.
  - The Abyssal Unseen uses all 1000 OpenSea `original_animation_url` CIDs through `ipfs.io`, preserving the same original IPFS content with a gateway that completed full downloads.
- Added audit comparison canonicalization for equivalent IPFS gateways so `ipfs.io`, `ipfs.decentralized-content.com`, and Lighthouse gateway URLs with the same CID compare as the same source media.
- Tightened source selection in `tools/audit_bundled_collection_sources.js` so confirmed reachable trusted sources outrank timed-out trusted sources, and confirmed failed trusted sources are not selected.

## Remaining External Media Failures

The full download sample check completed with 220 of the 222 remaining token-backed collections fully reachable. Two sampled tokens still fail because the best available source endpoint itself is unavailable, and no better supported original/source media URL was found during the audit:

| Collection | Token | URL | Failure |
| --- | --- | --- | --- |
| little swag world | `bKgCX1d94rYZFMb3e1s5RWdAXCLzmc5eUbKY6AM8DRm` | `https://gateway.lighthouse.storage/ipfs/bafybeihyzombwwbpjnr6yefirjqcyqegleworx6b22mb3bjavzqy3hoaju` | HTTP 402 |
| Organic Evolution | `AxgDRBuLQHRiHH8TLKNPa8vSph8n4yNqQY1ch7rmy8MB` | `https://arweave.net/4J0kQl63NMn_vI9EQICvphyYMzZ9PZQQdj0-g8OGOp0` | HTTP 404 |

## Validation

- `node --check tools/audit_bundled_collection_sources.js` passed.
- The full source audit dry-run after the main apply pass had 0 failed collections. It found 21 remaining Constant source SVG replacements, which were applied and then passed a targeted clean audit.
- Targeted clean audits passed for Constant and The Abyssal Unseen after the final source/gateway corrections.
- A focused Finiliar 10000-row byte-range sweep found 657 slow or broken current gateway rows and resolved all of them to reachable source-ordered candidates.
- Independent `HEAD` vs worktree URL scanner result after all fixes: 57 changed token files, 36265 changed existing URLs, 398 added rows, 207 removed rows, 0 source downgrades, and 0 media-class downgrades.
- `node tools/check_bundled_collection_downloads.js --samples 5 --retries 3 --full` checked 226 token-backed collections, 1130 sample downloads, 224 fully reachable collections, 2 partially reachable collections, 0 unreachable collections, and 2 residual external sample failures listed above.
- `xcodebuild -project nft-player.xcodeproj -scheme nft-player-ios -destination 'generic/platform=iOS' build` passed earlier in this audit; the final follow-up changes were token JSON and audit-tool changes only.
