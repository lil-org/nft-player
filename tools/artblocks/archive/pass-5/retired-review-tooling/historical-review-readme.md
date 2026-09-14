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

[The combined static-review list](deferred-static.md) contains 109 collections and 2,486 token references from both passes. `deferred-static.json` retains source-pass provenance, notes, original local paths, and PNG references. Its 89 original MP4 samples have separate PNG fallbacks. The two original first-pass artifacts remain unchanged.

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

`Suggested Items/Suggested.bundle/Development/review-pass.json` selects all 292 previously approved collections in the existing alphabetical catalog order. The new `pass-5` starts with no decisions, notes, viewing progress, or grid position; prior on-device namespaces and archived records remain preserved. Rendering calibration caches remain valid independently of the review pass. New choices never change this fixed final-review selection.

Run `node tools/prepare_artblocks_review_pass.js` for a read-only final-review plan, `--check` to validate current artifacts, or `--apply` to publish missing or stale final-review artifacts without deleting samples or changing live curation. The default source is the frozen recorded approval instruction. `--pass pass-4 --check` validates the archived one-collection runtime and 291-collection approvals. `--pass pass-3 --check` validates the historical 79-collection runtime, curation snapshot, second-pass approval manifest, and cumulative static list. `--pass pass-2 --check` validates the historical 315-collection runtime and original static manifest. Historical operations use archived runtime, curation, and approval paths, so even `--apply` does not replace the active final review, current approvals, or live curation. Existing source archives cannot be overwritten by different bytes.

Preparation is offline. It validates frozen source fingerprints, full identity coverage, metadata, exact token order, and PNG fallbacks against the immutable original curation and full preview corpus. All previous exclusions remain as recorded. Final-review publication reuses validated, staged publication and rollback handling with an empty removal list. Artist sources, token resources, static-review artifacts, and every remaining sample folder remain unchanged.
