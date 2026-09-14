# Production Art Blocks capture

The approved batch contains 292 collections. `final-approval.md` records the user's instruction; it is not a device export. `identity-mapping.json` maps historical review identities to production IDs. `provenance.json` records counts, invocation cutoffs, and source/resource checksums.

The complete original 519-project review corpus and the pre-promotion production catalog are retained in `../archive/pass-5`. Exact exports, approved manifests, and the current 17-project static list (the original 109-project selection is archived) remain in `../reviews`. The cumulative 828-project rejection ledger is `../rejected.json`. Discovery and sample selection consult both deferred and rejected identities. Existing sample folders are not deleted by this workflow.

## Frozen capture and reproducible publication

```sh
python3 tools/capture_artblocks_production.py
python3 tools/capture_artblocks_production.py --offline
node tools/promote_artblocks_collections.js
node tools/promote_artblocks_collections.js --publish
```

Capture freezes the project invocation cutoff once. Token pages resume from durable local files and are checked for exact contiguous invocation coverage, canonical project/chain/address/token identities, valid hashes, and preservation of every reviewed hash. New contract parameters are validated against the original artist-source hash, dependency identity, and token hash. Previously reviewed parameters are copied exactly; subsequent runs reuse them. Every reused additional parameter record must retain the frozen artist-source fingerprint, exact dependency, source URL, and token hash. The checksum inventory must contain every consumed cutoff, token, and parameter file (296 files for this batch), with no missing or extra membership. The offline command validates the complete capture without network requests.

Publication reads only frozen inputs, validates all 292 scripts and every token, checks the curation partition, constructs all output before writing, verifies a sibling staging bundle, and atomically exchanges the two directories with macOS `renamex_np(RENAME_SWAP)`. The live bundle path stays present throughout publication. A sibling recovery journal records exact before/after file checksums. On the next run, interruptions before exchange discard the recognized incomplete staging directory and rebuild; interruptions after exchange verify the complete live result and finish cleanup. Unrecognized staging folders or a live bundle matching neither state stop recovery without overwriting anything. Publication requires macOS; it does not silently fall back to a non-atomic rename sequence. Existing production entries remain intact, and pre-existing slugs/artist identities are reserved. Repeat runs reproduce identical bytes.

Artist source bytes remain unchanged. Production tokens retain reviewed URLs and names as historical metadata, but media capabilities disable their use as thumbnail/fallback requests. `artworkAspectRatios` preserves the authored project framing formerly stored as thumbnail ratios; per-token `imageAspectRatio` and `referencePixelSize` are independent. Frozen `contractParameters` retain the reviewed values. New token framing uses the same authored project ratio and captured image dimensions; autoRAD requires real reference dimensions.

Collection `bundledDate` is optional ISO calendar date metadata. This batch uses `2026-09-14`; existing dates are preserved by generated-catalog merges. Unknown historical dates are not inferred. A frozen batch republish refuses unrelated live catalog changes, including added or changed dates, so it cannot reset later metadata edits. General catalog regeneration preserves an existing date even if generated data offers a different date.
