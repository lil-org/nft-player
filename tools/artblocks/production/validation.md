# Production promotion validation — 2026-09-14

The app now bundles the approved 292 collections with all 143,847 minted tokens captured at 2026-09-14T08:36:36.394302Z. They appear in normal iOS/iPadOS Debug and Release builds, with no review flow, covers, thumbnail browser, or remote sample fallback. The shared catalog contains 517 entries. Each addition records `bundledDate: "2026-09-14"`.

## Preservation and reproducibility

- All 6,524 previously reviewed token records preserve their hashes, names, URLs, frozen parameter values, and framing. Per-token image/reference fields were renamed; authored fitted geometry is stored independently as artworkAspectRatios.
- All 6,524 generated wrappers match the captured renderer after required identity normalization, including encoded startup metadata. All 292 rendering policies remain unchanged: 213 direct and 79 calibrated.
- All 225 previous catalog records and 339 existing script/token resource files remain unchanged. The existing renderer produced identical first/middle/last wrappers for all 115 existing scripts (342 comparisons).
- Complete token coverage, all 296 required input checksums, and all 586 generated output files were verified. Offline reconstruction produces byte-identical output. Capture rejects conflicting hashes, missing rows, incomplete checksum manifests, and stale parameter-source metadata.
- Atomic directory exchange and journal recovery were tested before and after an interrupted publication. The workflow refuses unexpected live metadata changes, including bundling-date changes, before mutation.
- The original 519-project corpus, review exports, frozen data, and retired review-tool sources remain in repository archives. The static 109/2,486-reference list and the 736-identity rejection ledger form a disjoint partition with the 292 approvals. All 11,866 local sample files were verified unchanged.

## Native and platform validation

- Both iPhone 17 Pro and iPad Pro 11-inch (M5) simulators exercised all 292 collections, using first, next, middle, last, and revisited tokens: 2,920 final presentations, one document each, with unchanged token identity. Populated backing-quality reports remain within the existing tolerance.
- All 150 Hypertype tokens render offline and match their original SVG output on both devices. Frozen parameters were validated for all 365 Gift of Time, 37 degenerative, and 20 pool party tokens; representative native offline playback also passed.
- Focused coverage includes late layers, intentional pixelation, failed calibration, stale callbacks, errors, navigation during loading, all reviewed Cushions tokens plus additional variants, pool party Cycle mode, and fitted/fullscreen geometry.
- An isolated migration test preserved valid legacy calibration and historical review defaults. Actual player/controller tests verified generic error/retry recovery and external-display token changes, calibrated startup, coalesced resize, and no image fallback. External-display coverage uses the real controller in simulator windows; it is not a physical-monitor test.
- Normal UI inspection confirmed neutral missing covers, search, direct generative playback, the 38,965-token Friendship Bracelets count, fullscreen and next-token controls, and no review actions.
- Signed iOS Debug/Release and macOS/tvOS/visionOS compatibility builds passed. Non-iOS catalog identities and order remain unchanged: 225 on macOS, 220 on tvOS, 218 on visionOS. All 115 prior generators and 112 downloadable identities retain availability; the 292 additions are unavailable outside iOS.
- Widget eligibility and generated resources remain unchanged. The shared-core suite passed 431 tests.

## Test interpretation

The final native acceptance set contains 458 iPhone and 312 iPad cases after resolving stale test assumptions and rerunning the affected checks. One Décorés WebGL error during the long iPhone sweep did not reproduce in a fresh five-presentation run; its startup and iPad checks also passed. No artist-source change was made for that result.

Earlier baseline-replay fixtures required correction of encoded collection identities and equal preparation of HTML before native timing measurement. Superseded timing rows are retained as evidence but are excluded from final conclusions. Historical whole-build measurements and native HTML-replay measurements are distinct experiments; simulator variance is not presented as an application speedup. No fixed startup wait was introduced. The final equal-preparation comparison passed all 80 paired cases with unchanged profile, token identity, zoom, display scale, and one document load. Median paired native-startup changes were iphone: direct -7.4 ms, calibrated -13.3 ms, ipad: direct -5.1 ms, calibrated -21.6 ms. These short simulator samples show run-to-run variation; they are not treated as a measured speedup or proof of identical wall-clock latency.

Early screenshots capture first presentation, not necessarily completed progressive artwork. Authored animation, initial dark frames, and previously documented fixed-pipeline/static-image differences remain preserved. Every minted token's data was checked; native visual coverage samples tokens across every collection rather than claiming individual visual inspection of all 143,847 tokens.

Machine-readable capture/resource provenance is committed beside this report. Detailed test results, screenshots, timing measurements, wrapper comparisons, and preservation checks remain under the ignored build/artblocks-promotion directory.
