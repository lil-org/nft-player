# Review snapshots

`pass-1.json` is the original version 2 device export, preserved byte-for-byte. Its SHA-256 is `076a3b03c9a09987e9c1a4e1feca664231219f12794db8c5feaa2c4d188b2689`. It records all 519 decisions and four notes; the export did not include a review timestamp.

| First-pass decision | Collections | Saved sample tokens |
| --- | ---: | ---: |
| yes | 315 | 7,028 |
| no | 104 | 2,316 |
| mb static | 100 | 2,283 |

`pass-1-static.json` preserves the deferred static-review selection. Its collection folders and sample paths are relative to the repository root and continue to point into the original ignored `samples/good`, `samples/ok`, and `samples/hmm` folders. Use `fallbackImageURL` for static review: 70 selected local samples are MP4s, while every deferred token has a saved HTTPS PNG reference.

`pass-1-curation.json` preserves the exact original curation bytes. Its SHA-256 is `eff11e853fb991e49ffbb76771eeff5af415a6afa008544c29a0b1d3be4d8cba`, matching the unchanged generator corpus provenance. `pass-2-runtime.json` preserves the 315 first-pass `yes` identities in existing catalog order and their four initial notes for historical validation.

`pass-2.json` preserves the exact version 3 `pass-2` device export, including its 13 historical notes. Its SHA-256 is `c95cda472c92db8e6bb7afc1d667aade0cbca41c59f0cf3bac1e8898d1c76916`.

| Second-pass decision | Collections | Saved sample tokens | Next action |
| --- | ---: | ---: | --- |
| yes | 214 | 4,753 | Set aside in `pass-2-approved.json` |
| no | 13 | 278 | Excluded from live curation; sample folders removed |
| mb static | 9 | 203 | Added to the combined static-review list |
| double-check | 79 | 1,794 | The archived third review pass |

The original combined static-review selection contained 109 collections and 2,486 token references from both passes; its exact indexes are preserved in `../archive/sample-cleanup-2026-09-14/`. `deferred-static.json` retains source-pass provenance, notes, original local paths, and PNG references. Its 89 original MP4 samples have separate PNG fallbacks. The two original first-pass artifacts remain unchanged.

`pass-3-decisions.json` records the user's instruction that all 79 reviewed collections are now `yes` except `aaa` (`no`) and `pool party` (`double-check`). This is explicitly a recorded user instruction, **not a device export**. It preserves the literal message, the approved Cycle-mode preference, the resolved identities, and null notes; it does not claim to export unprovided device notes. Its SHA-256 is `ccb8f359b8a13d71fb6236a4c745b9807eb767d33b6742a71264cdf65b17abd7`.

| Third-pass decision | Collections | Saved sample tokens | Next action |
| --- | ---: | ---: | --- |
| yes | 77 | 1,751 | Set aside in `pass-3-approved.json` |
| no | 1 | 23 | `aaa` excluded from live curation; sample folder removed |
| double-check | 1 | 20 | `pool party` alone in the archived fourth review pass |

`pass-4-approved.json` and `pass-4-approved.md` preserve the previous cumulative approval list of **291 collections and 6,504 token references** from passes 2 and 3 byte-for-byte. Each decision's provenance, previous archived notes, original media paths, and PNG references remain intact. The 109-collection static list remains byte-for-byte unchanged.

`pass-3-runtime.json` preserves the previous 79-collection selection and empty initial notes exactly. `pass-3-curation.json` preserves the live curation before excluding `aaa`; its SHA-256 is `868309eccd0e9b4183b2cddfb9761004bb52d56989592f246bb03163d72243b2`. The original curation snapshot and 519-collection generator corpus remain unchanged.

`pass-4-runtime.json` preserves the one-collection review selection and empty initial notes. `pass-4-curation.json` preserves the exact live curation after excluding `aaa`; final review preparation does not modify live curation or remove any samples.

`pass-4-decisions.json` records the user's subsequent approval of `pool party` and request for a final clean review. It retains the literal instruction, including the spelling `poll party`, and resolves it to the exact frozen `pool party` identity. This is a recorded user instruction, **not a device export**; no unprovided device notes are fabricated. Its SHA-256 is `12875590b158a87d34cfda8ffcb59547f4f6987e3e66731db452175887189f74`.

[The cumulative approved list](approved.md) now contains **292 collections and 6,524 token references** from passes 2, 3, and 4. `approved.json` preserves all 291 earlier records exactly and adds `pool party`'s 20 saved tokens with `pass-4` decision provenance.

The final pass-5 runtime selection is preserved under `../archive/pass-5/Development/review-pass.json`. It selected all 292 approved collections with fresh review state. The user subsequently confirmed all 292 for production; that instruction is retained in `../production/final-approval.md`.

The production app has no active review pass, decision store, note editor, export controls, or sample-image switch. Historical device review keys are left untouched. Valid rendering calibration is migrated separately because it is permanent renderer state.

Temporary pass-preparation commands and their tests were retired. Their source and prior documentation are preserved as inert text under `../archive/pass-5/retired-review-tooling`. The [production workflow](../production/README.md) validates the current 292/12/833 partition and the complete frozen token capture without recreating app review resources.


## Finder sample cleanup

After production promotion, the user requested that only `mb static` samples remain downloaded. Current `deferred-static.json` sample paths now point into `samples/mb-static/`. Its decisions, notes, groups, token IDs, and PNG alternative URLs are unchanged. The exact previous JSON and Markdown indexes are archived in `../archive/sample-cleanup-2026-09-14/`, alongside the move/delete inventory and verification result. Older exports retain their historical paths as provenance.


## Subsequent Finder decisions

`finder-deletions.json` records the user's confirmation that removed local collection folders should be remembered as deleted. The first reconciliation found 92 missing folders and 17 complete remaining collections. A subsequent user-confirmed update records five additional deletions: Bokeh (lamps), Ephemeral Tides, Jankpop, Kai-Gen, and Odysseys. The deleted collections now carry `decision: no`, `status: deleted`, their prior `mb static` decision and source pass, and original notes in the rejection ledger. No further sample files were deleted or downloaded by this reconciliation.

The current static list contains 12 collections and 275 original PNG sample references; their full local download contains 1,665 PNGs. `deferred-static-supply.json` records the official Art Blocks API count checked on September 14, 2026: 4,287 minted tokens across the original 17 collections, reduced to 1,665 for the remaining 12 identities without refreshing the cutoff. The removed Jankpop had 143 tokens at that check. The existing 292 approvals are unchanged; cumulative rejected/deleted identities now total 833.

The original cleanup plan and completion journal remain immutable historical evidence. Its verifier recognizes only explicitly recorded later deletions, still checks all remaining media against their original checksums, and refuses unexplained missing folders.


The second Finder update is recorded in the `updates` array of `finder-deletions.json`, including the exact user instruction and prior index/inventory hashes. Existing deletion records are preserved. `static-downloads.json` retains unchanged records and checksums for the remaining collections and records the selection reduction in `selectionReconciliations`; the full prior inventory remains available at its recorded Git commit. No additional media was deleted or downloaded by this bookkeeping update.
