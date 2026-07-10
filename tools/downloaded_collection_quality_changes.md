# Downloaded Collection Original-Media Quality Audit

This document records the full-download and post-download quality work performed for `Originals Downloaded/`. The generated media directory is intentionally ignored by git; per-token evidence is stored in each collection's `manifest.json`, and aggregate machine-readable reports are stored under `tools/reports/`.

## Scope And Exclusions

- Processed every token-backed collection in `Suggested Items/Suggested.bundle` except the exclusions below.
- Skipped `Super Metal Mons!`, `Super Metal Mons!!`, `card nft`, and `Drifella 2` because their resolved bundled media uses `cdn.lil.org`.
- Skipped the native CDN-managed `Poncho Drifella` and `Card NFT 2` collections even though their curated bundle metadata does not contain literal CDN URLs.
- Skipped `The Abyssal Unseen` completely because its originals were too large for this corpus.
- Audited downloaded dimensions for all 100 non-Art Blocks, non-skipped collections. Art Blocks projects were excluded from the cross-token dimension audit because generative project outputs can intentionally vary and already use project-specific source handling.
- Never upscaled, resized, transcoded, or otherwise modified media. A replacement was accepted only after downloading and probing the remote candidate.

## Final Download State

The final resumability/integrity pass covered 215 collections and 191,477 in-scope token rows.

| Result | Count |
| --- | ---: |
| Files present and verified by manifest size/SHA-256 | 190,908 |
| Source-unavailable files | 569 |
| Collections with at least one source-unavailable file | 7 |
| Wholly unreachable collections | 0 |
| Skipped collections | 7 |
| Leftover `.part` or `.quality.part` files | 0 |

The corpus occupies approximately 367 GiB. Successful files were streamed to temporary files, hashed, and atomically renamed. A second full run verified and reused all successful files without downloading them again.

A follow-up retry campaign recovered 1,396 of the original 1,965 failures in the remaining collections. It used low-concurrency, longer-timeout passes after the initial broad retry to recover files that were reachable but too slow for the short retry window. The largest recoveries were 600 `Tojiba CPU Corp`, 529 `Scarecrow`, 266 `Tojiba Disc Buddies`, and the final `Little Fellow` file.

## Applied Quality Repairs

The audit dimension-probed 138,021 successfully downloaded files in the 100 non-Art Blocks collections. It applied 771 replacements across 21 collections: 424 recovered failed downloads and 347 replaced materially smaller files. Direct/source media supplied 753 replacements. The remaining 18 were API cache fallbacks accepted only when their measured dimensions matched the collection baseline.

`Failure` means a previously unavailable local file was recovered. `Quality` means an existing lower-dimension file was replaced. `Cache` means a modified/cache endpoint rather than an API-declared original URI; these cache files are local-only and were not written back into bundled token metadata.

| Chain | Collection | Total | Failure | Quality | Direct/source | Cache | Source evidence |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| solana | Tojiba Disc Buddies | 209 | 209 | 0 | 207 | 2 | `content.files.uri` / dimension-matched Helius cache |
| ethereum | Vacation | 204 | 0 | 204 | 204 | 0 | metadata `image` source |
| solana | Scarecrow | 141 | 141 | 0 | 141 | 0 | `content.files.uri` |
| solana | Tojiba CPU Corp | 58 | 58 | 0 | 54 | 4 | `content.files.uri` / dimension-matched Helius cache |
| ethereum | IMAGINED WRECKAGE | 42 | 0 | 42 | 42 | 0 | metadata `image` source |
| ethereum | EMOJIPACK | 35 | 0 | 35 | 35 | 0 | metadata `image` source |
| ethereum | Bloomers | 33 | 0 | 33 | 33 | 0 | metadata `image` source |
| tezos | moeshit | 16 | 0 | 16 | 16 | 0 | `formats[].artifactUri` |
| ethereum | Cigawrette Packs | 9 | 9 | 0 | 0 | 9 | dimension-matched OpenSea raw cache |
| ethereum | Finiliar | 5 | 5 | 0 | 5 | 0 | `original_animation_url` / `original_image_url` |
| ethereum | pfp+ | 5 | 0 | 5 | 5 | 0 | metadata `image` source |
| ethereum | Sproto Gremlins | 4 | 1 | 3 | 2 | 2 | `original_image_url` / dimension-matched OpenSea raw cache |
| ethereum | Storms | 2 | 0 | 2 | 2 | 0 | metadata `image` source |
| ethereum | Crowded Fields | 1 | 0 | 1 | 1 | 0 | metadata `image` source |
| ethereum | Math Art | 1 | 0 | 1 | 1 | 0 | metadata `image` source |
| tezos | real world data | 1 | 0 | 1 | 1 | 0 | `formats[].artifactUri` |
| solana | Record of Hyperwar | 1 | 0 | 1 | 1 | 0 | `content.files.uri` |
| ethereum | screenshot catalog | 1 | 0 | 1 | 1 | 0 | metadata `image` source |
| tezos | skomra | 1 | 0 | 1 | 1 | 0 | `formats[].artifactUri` WebM |
| ethereum | Tigerbob | 1 | 1 | 0 | 0 | 1 | dimension-matched OpenSea raw cache |
| ethereum | Tokyo Nude | 1 | 0 | 1 | 1 | 0 | metadata `image` source |

Size alone was not used as an acceptance criterion; media class, pixel dimensions, collection baseline, and source provenance were checked first. The `skomra` repair replaced a static preview with the API-declared 1280x930 WebM locally, but did not change the bundle because WebM is not supported by that bundled-player path.

## Bundled Token Metadata Changes

The post-download quality pass changed 471 resolved token URLs in 12 remaining bundled token JSON files. It did not change token IDs, token counts, collection ordering, names, covers, or `items.json`.

| Chain | Collection | Rows | Previous endpoint | New endpoint | Meaning |
| --- | --- | ---: | --- | --- | --- |
| ethereum | Vacation | 204 | `raw2.seadn.io` | `0prod.infura-ipfs.io` | OpenSea cache to metadata-declared IPFS source |
| solana | Scarecrow | 141 | `arweave.net` | `gateway.irys.xyz` | Same Arweave source via reachable API-declared gateway |
| ethereum | IMAGINED WRECKAGE | 42 | `raw2.seadn.io` | `0prod.infura-ipfs.io` | OpenSea cache to metadata-declared IPFS source |
| ethereum | EMOJIPACK | 35 | `raw2.seadn.io` | `arweave.net` | OpenSea cache to metadata-declared Arweave source |
| ethereum | Bloomers | 33 | `raw2.seadn.io` | `ipfs.decentralized-content.com` | OpenSea cache to metadata-declared IPFS source |
| ethereum | Finiliar | 5 | `permagate.io` | `turbo-gateway.com` | Same original Arweave media through a reachable gateway |
| ethereum | pfp+ | 5 | `raw2.seadn.io` | `pfp-pl.us` | OpenSea cache to project source media |
| ethereum | Storms | 2 | `raw2.seadn.io` | `ipfs.decentralized-content.com` | OpenSea cache to metadata-declared IPFS source |
| ethereum | screenshot catalog | 1 | `raw2.seadn.io` | `cdn.blot.im` | OpenSea cache to metadata-declared source image |
| ethereum | Tokyo Nude | 1 | `raw2.seadn.io` | `ipfs.decentralized-content.com` | OpenSea cache to metadata-declared IPFS source |
| ethereum | Math Art | 1 | `raw2.seadn.io` | `ipfs.decentralized-content.com` | OpenSea cache to metadata-declared IPFS source |
| ethereum | Crowded Fields | 1 | `raw2.seadn.io` | `ipfs.decentralized-content.com` | OpenSea cache to metadata-declared IPFS source |

All other local repairs either used the already-bundled content-addressed source through another gateway, used a source URL that had already been corrected by the earlier bundle source audit, or used a quality-gated cache fallback that was intentionally kept local. Per-token `qualityRepair.previous`, selected URL, dimensions, byte count, hash, and API source are retained in the collection manifests.

## Resume And Inspection Metadata

Downloader resume now compares the selected manifest source with the current bundled source after normalizing equivalent IPFS and Arweave gateways. The following fields preserve the decision evidence:

- `sourceUpgrade` records the previous filename, URL, byte count, SHA-256, and `qualityRepair` when a newly reachable or newly selected bundled source safely replaces a verified local file.
- `sourceRefresh` records a failed preferred-source retry. The verified existing file remains successful and untouched; the retry error and status are retained for the next run.
- `sourceOverridePreserved` and `preferredBundledSource` identify a dimension-based `qualityRepair` intentionally kept instead of reverting to the same previously measured lower-quality source.
- Collection totals and root totals include `sourceRefreshFailures` so preferred-source retry gaps remain visible without misclassifying retained files as missing.

Filtered downloader runs merge updated collections and failures into the existing root manifest. `mergedWithExistingManifest` identifies that state and `lastFilteredRun` records the filtered options and report paths. Unless explicitly overridden, filtered reports use `originals-download-report.filtered.{md,json}` so the canonical full-corpus reports are not replaced.

## Remaining Download Failures

These entries remain absent after direct bundled URLs, equivalent IPFS/Arweave gateways, API-declared source candidates, and quality-gated cache fallbacks were exhausted. They are recorded as failures and were not replaced with lower-quality substitutes.

| Chain | Collection | Verified | Failed |
| --- | --- | ---: | ---: |
| solana | Scarecrow | 4,017 | 31 |
| solana | Tojiba Disc Buddies | 4,549 | 449 |
| solana | Organic Evolution | 68 | 4 |
| solana | TOJIA | 4,411 | 27 |
| solana | Tojiba CPU Corp | 2,168 | 53 |
| ethereum | Cigawrette Packs | 9,996 | 1 |
| ethereum | Tigerbob | 996 | 4 |

## Remaining Quality Concerns

The clean follow-up audit detected 5,162 statistical dimension outliers. It verified 1,763 as source-native variations or files at least as large as every reachable source candidate. The 3,399 entries below remain unresolved because no reachable provenance-safe candidate met the collection baseline; the existing file was retained rather than replaced with another thumbnail or an unverified substitute.

| Chain | Collection | Unresolved | Current dimensions | Collection norm |
| --- | --- | ---: | --- | --- |
| ethereum | Cigawrette Packs | 3,366 | 500x625 | 3456x4320 |
| ethereum | Bloomers | 20 | 500x500 | 2048x2048 |
| tezos | moeshit | 7 | 64-315 px variants | usually 1000x1000; one 1600x1440 group |
| ethereum | tubbypxgan | 4 | 500x500 | 990x990 |
| ethereum | Beyond the Veil | 1 | 500x700 | 3214x4500 |
| ethereum | screenshot catalog | 1 | 500x269 | 1010x540 |

`Cigawrette Packs` is the dominant unresolved case. Of 9,996 downloaded files, 6,630 are 3456x4320 originals and 3,366 are 500x625 OpenSea raw images. OpenSea exposes no `original_image_url` for those affected tokens. Their metadata points into a shared IPFS metadata directory that was unavailable through every tested content-address-equivalent gateway, so the original image CIDs could not be recovered. No upscaling or cross-token substitution was performed.

For the seven unresolved `moeshit` files, the reachable API-declared artifact is HTML and does not provide a measurable higher-resolution image replacement. The audit retained the current small images instead of changing media class to dimensionless HTML. The other unresolved collections similarly had no reachable API-declared source file that passed the provenance and dimension gates.

## Reports And Verification

- Full corpus manifest: `Originals Downloaded/manifest.json`
- Per-collection evidence: `Originals Downloaded/<internal_slug>/manifest.json`
- Download report: `tools/reports/originals-download-report.md` and `.json`
- Quality report: `tools/reports/downloaded-collection-quality-audit.md` and `.json`
- Downloader: `tools/download_bundled_collection_originals.js`
- Quality audit/recovery tool: `tools/audit_downloaded_collection_quality.js`

Final verification commands:

```sh
node tools/download_bundled_collection_originals.js --apply --retries 0 --concurrency 8 --skip-collection "The Abyssal Unseen" --no-retry-failures
node tools/audit_downloaded_collection_quality.js --apply --skip-failure-recovery --probe-concurrency 12 --download-concurrency 12 --timeout-ms 10000 --retries 0
```

The final downloader pass reused and verified all 194,663 successful files. The clean quality rerun found no additional acceptable replacements, confirming that all currently reachable upgrades had already been applied.
