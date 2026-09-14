# Static sample consolidation — 2026-09-14

This archive records the user-authorized removal of downloaded samples other than the committed `mb static` selection. It is a filesystem cleanup, not a new curation decision or device review export.

- Retained: 109 collections, 2,486 samples (2,397 PNGs and 89 MP4s), 17,149,509,759 bytes including collection manifests.
- Removed: 396 top-level sample folders (292 approved and 104 previously rejected), plus the already rejected Blind Spots collection nested inside Alien DNA. The complete removed content occupied 38,098,680,668 bytes.
- AlgoBeats' existing folder has a trailing space; its exact path was validated against the committed rejection ledger and preserved in the deletion inventory.

`plan.json` records exact paths, identities, original ledger fingerprints, retained SHA-256 checksums, and removed file inventories. `progress.json` records the completed, resumable operations. `result.json` records verified totals. Original static indexes and obsolete local reports are preserved byte-for-byte here. The current static indexes contain the relocated paths.

All retained media and collection manifests passed SHA-256 comparison before deletion and again after completion. No app resources, bundled token data, artist scripts, frozen parameters, approvals, rejection records, or historical exports were changed. The samples remain Git-ignored.

Run `python3 tools/cleanup_artblocks_samples.py --check` from the repository root to verify the retained corpus. Finder's regular `.DS_Store` metadata is tolerated; unexpected sample files and symlinks are refused. The old grouped sample-capture command must not be used to infer curation from this reduced directory.
