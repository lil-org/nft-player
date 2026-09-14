# Recorded final approval instruction

Source type: user instruction, **not a device export**. Recorded date: 2026-09-14.

The user confirmed that all 292 collections were validated and approved this production promotion plan:

> PLEASE IMPLEMENT THIS PLAN:
> # Promote the 292 approved collections into the app
>
> ## Summary
>
> Ship the collections in normal **iOS/iPadOS Debug and Release builds**, including external-display playback, using the verified rendering behavior. Other platforms and widget eligibility remain unchanged.
>
> Bundle **every minted token at a recorded capture cutoff**. The cached inventory contains approximately 143,847 tokens; the capture will establish the actual total. Preserve the 6,524 reviewed token records and their frozen rendering data.
>
> ## Production catalog and complete token data
>
> - Record this message as the final approval instruction, explicitly distinguished from a device export. Capture the current catalog, scripts, token records, generated HTML, rendering policies, and representative runtime output before migration.
> - Add a resumable capture-and-publish workflow: freeze each project’s invocation cutoff, fetch paginated token metadata, validate identities/hashes and complete coverage, then publish atomically from validated inputs. Subsequent rebuilds use the frozen capture. Missing data or conflicting hashes stop publication.
> - Preserve reviewed artist source and existing frozen parameters. Capture parameters only for additional tokens requiring them—principally Gift of Time and degenerative. Validate each capture against the expected token, dependency, and artist-source fingerprint.
> - Retain artwork aspect ratios and reference dimensions independently of thumbnails. Capture the same metadata for additional tokens; require valid reference dimensions for autoRAD rather than guessing its framing.
> - Promote resources into the normal catalog using existing production ID conventions: lowercase contract address plus project ID, with canonical chain/address/project identity retained in provenance. Update rendering gates atomically through an explicit old-to-new ID mapping.
> - The catalog becomes **517 entries: 225 existing plus 292 additions**. Preserve exact collection names and artist credits, reuse existing artist records when they match, and reserve existing slugs when assigning new ones.
> - Add optional `bundledDate`, formatted `YYYY-MM-DD`, to collection JSON and its Swift model. Set the new batch to `2026-09-14`; preserve existing dates on subsequent runs and leave unknown historical dates absent. Update every catalog-writing tool to retain it.
> - Declare the additions `iosOnly: true`, `generativeOnly: true`, `hasCover: false`, and `hasThumbnails: false`, with backward-compatible defaults. Keep supply totals in token manifests/provenance rather than the catalog’s existing downloadable-media `tokenCount` field.
>
> ## Preserve rendering and remove review behavior
>
> - Replace review activation with a permanent `renderingProfile: "artBlocks"` capability on the 292 scripts. Retain exact source checks, library bytes, initialization order, embedded assets, frozen parameters, Hypertype’s local dependency, and collection-specific fixes.
> - Preserve **213 immediate/direct collections and 79 calibrated collections**, including quality monitoring, layout coalescing, resolution correction, retained frames, cancellation, and rollback. Add no startup waits.
> - Migrate valid calibration entries through the identity mapping without changing their renderer/source revisions. Keep legacy compatibility labels only where needed for cache or protocol continuity.
> - Remove decision controls, notes, exports, review filters, pass selection, review-specific grid/progress storage, sample-image switching, and automatic sample-image fallback. Restore normal collection browsing and shared viewing progress; leave historical device review data untouched.
> - Use ordinary neutral cover placeholders. Collections without thumbnails open directly in generative playback, with no thumbnail-browser toggle or fabricated CDN requests. Keep normal playback controls and a concise artwork error/retry state.
> - Enforce iOS availability in both catalog visibility and generator lookup. Platform availability must not imply downloadable-image support.
> - Remove the development corpus and unused review resources from app targets. Preserve historical sources and exports in repository archives. Retain only dependencies required by the existing catalog and promoted collections in shipped resources.
>
> ## Retained curation records
>
> - Commit the existing **109-collection static list**, preserving its 2,486 sample references, notes, original media paths, and PNG alternatives.
> - Commit a cumulative rejection ledger containing **736 identities**: 618 original exclusions, 104 first-pass rejections, 13 second-pass rejections, and aaa. Preserve each decision’s origin and available notes.
> - Make future discovery and bundling selection consult these ledgers, so rejected collections are not automatically reconsidered.
> - Preserve the exact historical exports and approval records. Remove active review machinery while retaining its archival evidence.
> - Delete no additional sample folders. The 104 earlier rejected folders still present locally remain untouched.
> - Commit the promotion, required rendering changes, and archival records; keep downloaded samples, caches, and build outputs ignored.
>
> ## Validation and acceptance
>
> - Verify complete minted-token coverage at the capture cutoff, deterministic rebuilds, unique catalog identities/slugs, and preservation of every reviewed hash, artist-source string, frozen parameter, and framing value.
> - Compare all 6,524 reviewed token wrappers against the baseline, allowing only required identity/protocol migration differences. Require unchanged rendering-policy selection and unchanged existing production output.
> - Exercise every promoted collection on iPhone and iPad using reviewed and newly added tokens. Cover navigation, revisit, fitted/fullscreen presentation, representative rotation and external-display cases, plus every existing rendering exception.
> - Retain offline asset checks, first-frame/timing comparisons, late-layer, error, cancellation, and no-flash regressions. Verify no thumbnail or sample-image requests occur for the additions.
> - Test large collections—especially Friendship Bracelets, Trademark, and Flowers—for lazy HTML generation and responsive navigation.
> - Verify date preservation across catalog rewrites, the disjoint **292 approved / 109 static / 736 rejected** partition, removal of review UI, and unchanged widget eligibility.
> - Run focused tests, iOS Debug/Release builds, and builds for the other platforms to confirm shared-code compatibility.
