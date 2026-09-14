# Art Blocks curation

`curation.json` preserves the review decisions independently of downloaded files. Each entry is keyed by `chain-id:lowercase-contract-address:project-id` and contains its name, artist, group, and local folder basename. Retained collections also record the reviewed token IDs, invocations, media URLs, and extensions.

The original snapshot in `reviews/pass-1-curation.json` preserves the September 6, 2026 inventory. Current production eligibility is recorded by the approved, deferred-static, and rejected ledgers described below; live curation retains historical group labels and saved sample references.

The entire project-root `samples/` directory remains Git-ignored, including media, raw manifests, and generated reports. Only this compact registry, documentation, and tooling belong in Git. Excluded collections have no sample references and are never automatically downloaded again.

## Capture and check decisions

Run commands from the repository root with Node.js 22 or newer:

```sh
node tools/download_artblocks_samples.js --check-curation
node tools/download_artblocks_samples.js --capture-curation
```

Both operations are offline. Capture requires all three local group directories and either the original `samples/inventory.json` or an existing registry. It matches collections using their manifests, preserves actual folder names (including spaces), and requires each retained sample to exist with its recorded byte size. It writes deterministic JSON and records previously known collections absent from the groups as `excluded`.

To change a rating, move its whole collection folder between `samples/good/`, `samples/ok/`, and `samples/hmm/`, then capture and review the JSON diff. To exclude a collection, delete its folder and capture. To restore an excluded collection, recover its original folder and manifest into one of the groups, then capture; excluded entries intentionally do not retain token references. Duplicate identities, conflicting sample selections, invalid paths, and incomplete downloads cause capture to fail before writing the registry.

Checking validates the registry and compares it with local groups when collections are present. On a fresh checkout with no local collections, it validates saved decisions without inferring deletions. An ordinary download never changes curation decisions. Capture should only run after intentional local organization; do not use it on a partially restored sample set.

## Restore or resume samples

Downloading and media verification additionally require ImageMagick's `magick` and FFmpeg's `ffprobe` on `PATH`:

```sh
node tools/download_artblocks_samples.js --group good
node tools/download_artblocks_samples.js
node tools/download_artblocks_samples.js --verify-only --group good
```

Downloads default to all three retained groups, restoring the exact reviewed tokens and selected media URLs into their group folders. Existing moved or renamed folders are found by manifest identity; group filters follow their current local location. The tool reuses valid files and creates local manifests from the registry on a fresh checkout. It does not replace missing reviewed items with other tokens or silently choose a different media format. Unavailable saved URLs are reported for later review.

Transfers follow redirects, validate media contents, use temporary files before renaming, and resume using SHA-256 and size checks. Six workers use up to five transient retries and preserve 10 GiB of free disk space. Local `download-summary.json` and `download-report.md` describe the selected run. Verification is read-only and exits nonzero for missing or invalid files.

Use `--output <directory>` for another local sample root or `--curation <file>` for a separate registry.

## Discover new projects

```sh
node tools/download_artblocks_samples.js --discover
```

Discovery queries the public `https://data.artblocks.io/v1/graphql` endpoint, verifies pagination against the aggregate count, and compares the result with the app's bundled collection identities and saved decisions. Unknown projects are written as `unreviewed` to the ignored `samples/discovery.json`. Discovery does not download them, recreate excluded collections, overwrite the original inventory, or assign ratings.

Adding a new project to the app is a separate bundling task. The sample downloader only preserves and restores the review corpus.

## Tests

```sh
node --test tools/download_artblocks_samples.test.js tools/artblocks/curation.test.js
```

Integration tests use a temporary local HTTP server and generated fixture images. They do not download public Art Blocks media or modify the real sample corpus.

## Bundle existing collections as local generators

The script bundler converts the seven explicitly mapped collections already in the app: Archetype, Fidenza, Ringers, Instructions for Defacement, Meridian, The Eternal Pump, and Parnassus. Flore Perdue, Fragments of an Infinite Field, and Letters to My Future Self remain on their existing CDN images and are excluded from script conversion.

```sh
node tools/bundle_artblocks_scripts.js
node tools/bundle_artblocks_scripts.js --apply
node --test tools/bundle_artblocks_scripts.test.js
```

Node.js 22 or newer is the only tooling dependency. The default dry run fetches complete artist scripts and hashes from the public Art Blocks GraphQL API and validates the entire conversion without writing files. `--apply` writes the seven script JSONs, expands existing compact token rows to objects with hashes and their original CDN URLs, and removes only the seven catalog `tokenCount` fields so the app selects generation. It preserves all 4,461 existing token IDs and their order, collection identities, thumbnails, aspect ratios, and other manifest metadata. New mints are not added.

All source projects, library versions, external dependencies, and token identities are checked against the explicit mapping in `tools/bundle_artblocks_scripts.js`. Missing, duplicate, unexpected, cross-project, or invalid hashes stop the conversion before any files are written. Two project workers share the sample downloader's throttled GraphQL client and retry transient failures up to five times. Reapplying validates the API data again, rejects changed existing hashes, and leaves byte-identical outputs untouched.

Parnassus uses project 2 in its script and a `collectionIdOverride` containing its original full app ID. Its catalog entry and resource filenames retain the legacy identity. Instructions for Defacement retains the artist script with a small prepended `tokenData` adapter pointing to `https://cdn.lil.org/player/instructions_for_defacement/background.jpg`; this background is a runtime network dependency. Its display-tuning hook gives the document and body the official wrapper's full-height layout. The other six generators need no external assets and use libraries already bundled with the app.

Parnassus also applies main-canvas CSS sizing to fit narrow portrait and landscape screens without cropping, including its original portrait/landscape controls. This changes only presentation: all three 2160×3840 canvas backing stores and the artist's algorithm are retained. It is a heavy generator; desktop WebKit validation observed roughly 1.0–1.2 GiB peak WebContent memory per page, so physical-device memory behavior merits particular attention.

Apply also writes the Git-ignored `tools/reports/artblocks-script-bundle.json` with API project identities, artist names, original script part counts, byte counts, SHA-256 fingerprints, token counts, and runtime asset URLs. `--bundle <directory>`, `--api-url <url>`, and `--report <file>` override the bundle, endpoint, and provenance report destinations. Tests use temporary fixtures and an injected API client; they do not mutate real app resources or download artwork.

After applying, run `node scripts/generate-widget-resources.mjs`, then `node scripts/generate-widget-resources.mjs --check` and the app's generator checks. The retained CDN URLs continue to supply static widget images. This command does not regenerate widgets, alter cover assets, download sample media, or change curation decisions.

## Bundled approved Art Blocks collections

The September 14, 2026 production batch adds **292 collections and 143,847 minted tokens** to the normal iOS/iPadOS app. The catalog contains **517 entries**, including the original 225. Other platforms keep their prior visible catalogs and generator availability; widget resources and eligibility remain unchanged.

The additions are generative-only, with neutral covers and no thumbnail browser or remote sample-image fallback. Artist scripts, embedded fonts/data, pinned rendering libraries, Hypertype's local dependency, and frozen contract parameters ship in the app. The permanent Art Blocks renderer preserves 213 direct and 79 calibrated startup policies, quality monitoring, collection fixes, and cache migration. `bundledDate` records `2026-09-14` for this batch and remains stable on rebuilds.

Use the [production capture and publication workflow](production/README.md):

```sh
python3 tools/capture_artblocks_production.py --offline
node tools/promote_artblocks_collections.js
node tools/promote_artblocks_collections.js --publish
```

The complete original 519-project resource corpus and unused historical dependencies are preserved under `archive/pass-5`, outside application targets. The temporary review UI, decisions/notes/export controls, pass selection, and executable pass-preparation commands have been removed. Historical command sources and documentation are retained as inert text in `archive/pass-5/retired-review-tooling`.

The [static candidates](reviews/deferred-static.md) retain 17 collections and 387 reviewed sample references, including original media and PNG alternatives. The [rejection ledger](rejected.json) retains 828 rejected/deleted identities. Future discovery and sample selection consult these records. Promotion left the existing sample files untouched. The subsequent authorized sample cleanup removed non-static samples and consolidated the retained collection folders under `samples/mb-static/`.

Live `curation.json` retains legacy group labels (53 good, 233 ok, 219 hmm, and 632 excluded); the cumulative rejection ledger additionally includes 104 first-pass rejections and 92 user-confirmed Finder deletions. Use the cumulative ledgers for current eligibility, rather than inferring eligibility from those historical group labels. The known inventory partitions exactly into 292 approved, 17 deferred-static, 828 rejected, and zero pending collections.

Historical source regeneration remains available through `build_artblocks_good_preview.js`, which also supplies production parameter validation. Its default output is the ignored `build/artblocks-historical-review/Good` directory. It does not activate an application review pass. Frozen parameter parsing is shared with production capture; reviewed parameter records are never refreshed by the production workflow.

## Local samples for Finder review

Following the user’s Finder review, 17 `mb static` collections remain downloaded in `samples/mb-static/`, with 387 PNG samples. The 92 missing collection folders are recorded as deleted in `reviews/finder-deletions.json` and the cumulative rejection ledger. The remaining collections have 4,287 minted tokens in the official API check recorded in [deferred-static-supply.json](reviews/deferred-static-supply.json). Their original collection folders and file bytes are preserved. The current [static index](reviews/deferred-static.md) links to the new locations; decisions, notes, original groups, token IDs, and PNG alternatives remain unchanged.

```sh
python3 tools/cleanup_artblocks_samples.py
python3 tools/cleanup_artblocks_samples.py --check
```

The cleanup command defaults to a read-only inventory summary. `--apply` resumes the exact recorded cleanup or verifies an already completed run. It validates identities against committed decision ledgers, hashes every retained file before moving, and verifies all moved files before deleting any other collection. Its journal, original indexes, local reports, and deletion inventory are retained in `archive/sample-cleanup-2026-09-14/`. The original removal set contains 396 top-level folders, plus the already rejected Blind Spots collection found inside Alien DNA's folder.

Do not run the historical grouped `--capture-curation` operation against this reduced corpus: the files' presence is no longer a statement of curation eligibility. Use the cleanup verifier for this layout. App bundles, production tokens, frozen parameters, approval/rejection ledgers, and historical exports are unaffected. No new media was downloaded or converted.
