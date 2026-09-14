# Art Blocks curation

`curation.json` preserves the review decisions independently of downloaded files. Each entry is keyed by `chain-id:lowercase-contract-address:project-id` and contains its name, artist, group, and local folder basename. Retained collections also record the reviewed token IDs, invocations, media URLs, and extensions.

The original snapshot in `reviews/pass-1-curation.json` contains 55 `good`, 237 `ok`, 227 `hmm`, and 618 `excluded` collections, with 11,627 sample references across 519 retained collections. After the second device review, live `curation.json` contains 54 `good`, 233 `ok`, 219 `hmm`, and 631 `excluded` collections, with 11,349 references across 506 retained collections. Only the 13 newly rejected collections were excluded and their sample folders removed; the earlier 104 device-review rejections retain their historical curation and local samples. The source inventory was fetched on September 6, 2026; these are review decisions for that inventory, not a current API count.

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

## Review collections on iPhone and iPad

The active development build is the fourth review pass: only `pool party`, with its 20 saved tokens. Its decisions, notes, viewing state, and grid position start clean in the `pass-4` namespace and then persist normally. Previous on-device pass state remains intact. The fixed selection remains visible when a new decision is assigned.

pool party starts in the artist's existing Cycle mode and suppresses the optional long-press hint. Cycle animates the frozen price history at the authored ten seconds per interval; it does not rotate through the Prices or PNL screens. The exact-identity/source-hash-gated adapter sets only `timeline_mode`, `show_info`, `show_pnl`, and `_vuiHintAlpha` before drawing starts. No timer, synthetic gesture, source rewrite, new parameter request, or startup delay is added.

The exact exports remain archived in `reviews/pass-1.json` and `reviews/pass-2.json`. `reviews/pass-3-decisions.json` preserves the user's subsequent message and resolved decisions as a recorded instruction, explicitly not a device export. It also records the approved automatic Cycle mode for `pool party`. `reviews/pass-3-runtime.json` and `reviews/pass-3-curation.json` snapshot the previous selection and curation.

[The cumulative approved list](reviews/approved.md) sets aside 291 `yes` collections and 6,504 saved tokens. Its `reviews/approved.json` manifest combines the 214 approvals from pass 2 and 77 from pass 3, retaining their provenance, historical notes, original media paths, and PNG alternatives. [The combined static-review list](reviews/deferred-static.md) remains unchanged at 109 collections and 2,486 token references. The previous 13 second-pass rejections remain excluded, and `aaa` is now also excluded with its 23 local samples removed.

`node tools/prepare_artblocks_review_pass.js --check` validates the active selection, recorded instruction, approvals, current curation, and `aaa`'s folder removal offline. The default is a dry run; `--apply` publishes the manifests and completes only that recorded removal after validating the folder identity and publishing immutable archives. Repeating the operation is safe. Changed inputs or unrelated curation edits stop preparation. Ordinary publication failures restore mutable outputs; interruption during deletion is completed by rerunning `--apply`.

`--pass pass-3 --check` validates the historical 79-collection selection and its curation snapshot. `--pass pass-2 --check` validates the historical 315-collection selection and original static manifest. These historical operations use archived runtime/curation outputs, so they never change the active pass or restore excluded collections. `Development/review-pass.json` remains outside the builder's generated `Good` directory. Notes, decisions, viewing progress, completion status, Continue Viewing entries, and grid position are isolated by pass; review progress neither imports nor exports cloud state. Device exports use version 3, include `passID`, and are now named `artblocks-review-decisions-pass-4.json`.

### Original resource corpus

The historical generator corpus retains all original 519 collections: 55 `good`, 237 `ok`, and 227 `hmm`, with their exact 11,627 saved sample tokens. The builder defaults to immutable `reviews/pass-1-curation.json`, keeping its original provenance fingerprint and complete corpus separate from current sample exclusions. It fetches artist source, dependency metadata, token hashes, and API PNG image metadata. It does not download images, covers, thumbnails, or saved sample videos. Changing review passes does not rebuild these resources.

```sh
node tools/build_artblocks_good_preview.js
node tools/build_artblocks_good_preview.js --apply
node --test tools/build_artblocks_good_preview.test.js
```

The default command validates without writing. `--apply` writes only `Suggested Items/Suggested.bundle/Development/Good`: a separate catalog, scripts, token manifests, compatibility manifest, and deterministic `provenance.json` with group counts, artist names, canonical identities, library versions, source fingerprints, and curation and compatibility fingerprints. It validates every selected project, hash, aspect ratio, ordered dependency, and HTTPS PNG reference before staging the complete resource set, writes the catalog last, then publishes the directory. An ordinary write or publication failure preserves the previous preview. Reapplying identical API data leaves files untouched; changed existing token hashes are rejected. JavaScript and modules are parsed for syntax but never executed by the Node builder; Genesis and Construction Token retain their Processing sources. `--curation <file>`, `--compatibility <file>`, `--output <directory>`, and `--api-url <url>` support separate fixtures. Treat the output directory as generated: applying replaces its whole contents.

`ArtBlocksDevelopmentPreview.enabledForDevelopment` in `Suggested Items/ArtBlocksDevelopmentPreview.swift` enables the selected review catalog only for iOS Debug builds. Set it to `false` to restore the normal grid. The preview preserves all runtime collection IDs in the `address-dev-good-chain-project` namespace. Its grid scroll key is scoped to the review pass. The final review uses plain collection names throughout the grid, search, menus, and player. Original `good`/`ok`/`hmm` metadata remains available in data and exports. Preview items also carry canonical `chainId:lowercaseContractAddress:projectId` review identities.

Decisions are local to the device and independent of the original groups. The player More menu and collection context menu provide `yes`, `no`, `mb static`, `double-check`, and clearing. Green, red, yellow, and blue decision text appears above grid names, respectively; `double-check` marks a collection for additional review. Both menus also offer a separate Add note or Edit note control with a multiline editor, Save, and Cancel. Saving blank text removes a note; notes can exist without a decision, and changing or clearing either preserves the other. Decisions and notes persist in UserDefaults under the same canonical collection identities without changing repository curation or playback behavior. Export review decisions in the grid gear menu shares the active pass through Save to Files or AirDrop. Each collection record includes `name`, `group`, `decision`, and `note`, using explicit `null` for absent decisions and notes. First-pass version 2 exports remain preserved and readable.

Preview playback enters the one-per-page player with neutral covers, browser controls and thumbnail requests disabled. Artwork uses the saved project ratio; sample images use their recorded dimensions when available. Every token's `url` is the API `image.url` PNG reference, even where the original selected sample is an MP4. Sample images load through the app image cache on demand.

Review canvases are checked against the display's native pixel density after their dimensions settle. Ordinary canvases participate after an actual drawing operation; transferred offscreen canvases participate on transfer. Empty contexts cannot trigger a correction. Measurement continues for late layers and changing styles, including small detail canvases. Explicit pixelated/crisp sampling and positive blur are preserved separately for each surface; a protected layer does not suppress checks on other layers. Undersampled viewport-based artwork regenerates from the same saved HTML at an adjusted WebKit page zoom. The correction must increase the same measured surface's bitmap dimensions while preserving its displayed size. Attempts are bounded, ineffective changes restore the preferred presentation, and successful settings are cached per collection, token, and display scale for resize/revisit.

The final review uses an explicit direct/calibrated startup policy: 213 collections retain immediate direct presentation, and 79 use exact-identity/library/name/source-SHA-256-guarded calibration profiles. The latter comprise the existing 78 approved optimized collections plus Autopoiesis, whose density-1 tiled canvases now begin at the previously corrected resolution without an initial reload. Existing profile revisions and calibration caches remain unchanged; direct collections receive no new cover, readiness wait, or forced viewport dimensions. Verified artist density settings are applied before the first document loads. Initial bounds settle before loading; scoped explicit document width and height prevent WebKit from shrinking the layout after the first frame. A neutral cover remains until the initial presentation is stable; necessary later corrections retain a frame from the same token. Duplicate loads, subpixel changes, and canceled resizes do not restart or cover completed artwork. Calibration is bounded and stored separately from review decisions, keyed by token, profile revision, viewport, display scale, device idiom, and OS version. Increment the startup profile revision when changing its rendering policy.

Startup uses a display-frame layout check rather than a fixed pre-load delay. Drawing, layout, and media events trigger two consecutive animation-frame inspections; the existing quality check runs before the ready message, and native presentation has no extra timed grace period. Startup observers disconnect after readiness while the slower quality monitor continues checking late layers. Opacity transitions retain their authored fade, unchanged calibration values are not rewritten, and repeated ready messages do not recapture snapshots. The separate debounce for genuine player resizing remains in place. Vahria synchronizes its initial resolution before the first check without forcing another draw.

Into the Light skips ineffective calibration of its fixed pipeline. Gift of Time dismisses its artificial minimum loader after a successful draw; its frozen time parameters remain unchanged. Vahria's existing loop supplies the next aligned frame without an extra forced render. Can you see it delegates viewport changes to the native reload path, retaining the artist's setup sizing instead of invoking its inconsistent resize callback. Cushions tokens `231000008` and `231000020` receive an exact hash-gated first-read alpha correction from 254 to 255 for contour classification; RGB values and other tokens remain unchanged. SpiroFlakes' authored two-second pattern progression remains enabled.

Screen validation distinguishes startup stability from completed artwork. Descent can initially be black while its worker prepares the scene; Classical Revival begins its particle drawing after 30 authored frames, which can take several seconds on a simulator. Into the Light remained black on the tested iOS simulator with both the preserved pre-pass renderer and the new renderer, despite an active render loop and no WebGL errors. Its current shader pipeline is retained for manual review; native-size measurements do not establish that it produces visible artwork on every platform.

Reference PNG dimensions are retained without aspect-ratio normalization in optional `previewReferencePixelSize` pairs and recorded by `referencePixelSizesSHA256` in provenance. autoRAD keeps each token's recorded 1200- or 2400-pixel logical size and fits that result into the player, with at least 2400 backing pixels. The token without recorded dimensions uses 1200 logical pixels, verified against its saved grid geometry. A scoped p5 instance initialization retains double-density pixels for 1200-pixel renders. All 23 saved full-size PNGs are 2400×2400, but their logical render sizes differ. Its artist code quantizes geometry against logical size, so increasing backing density alone cannot reproduce the saved render's detail. Mask adapters for autoRAD, Mellifera, and Ode to Roy retain full backing pixels and the original logical placement. Scoped snapshot adapters also preserve full-resolution copies in Fumus, Murano Fantasy, Bauhaus Synthesis, Can you see it, and Time travel in a subconscious mind, including its alternate-view caches. Each adapter requires the exact preview identity, library, and relevant source signature; production rendering and bundled artist source are untouched.

100 Sunsets uses its authored density control, and Bubble Blobby selects its highest authored quality without its frame-rate downgrade. Inhabitants replaces the failed original video gateway with the saved token's official Bright Moments S3 video mirror; video content still requires network access. Intentional dither inputs and fixed simulation or shader grids retain their authored resolution. These checks address display and intermediate-copy losses; they do not establish pixel identity for every animated frame or every zoom level.

Växt uses its existing `pr` input to honor native density. Vahria synchronizes renderer density, composer targets, and both copies of its `ja` shader uniform. Genesis and Construction Token receive a scoped Processing 2D Retina backing adapter: their logical sizes, quantization, drawing coordinates, and default sampling style stay intact while backing pixels increase. Detached Processing font buffers retain their original behavior. Stored artist scripts and token hashes are unchanged. Artwork with an intrinsically fixed pipeline, such as Into the Light's 1080×1080 buffers, retains that authored limit; enlarging the viewport alone cannot add detail.

The renderer reuses pinned p5 1.0.0/1.9.0, Three 0.124.0, Paper 0.12.15, Processing.js 1.4.6, regl 2.1.0, and Tone 14.8.15. Added pinned libraries cover p5 1.11.11/1.4.0, Three 0.160.0/0.167.0, Babylon 5.0.0, and Tone 15.0.4. Songs of Utopia receives both Tone and p5; Transformations du Champ and Materialistic retain module support. SpiroFlakes, Paramecircle, and Shooting Serenade retain their full HTML documents; Shooting Serenade's exact p5 1.4.0 URL resolves to the bundled library. Afterimage and Autopoiesis start with an empty body; Jankpop, striation, and Delights explicitly use JavaScript despite null API library metadata.

Four canonical identities carry a `secondaryDependencyProfile`: INFINITE uses ONNX Runtime 1.14.0 and p5 1.6.0; Time after vessels uses ONNX Runtime 1.14.0 and seedrandom 3.0.5; Spongenuity's Portrait Lab uses the p5 SVG plugin; The Tallest Poppy uses Three 0.155.0 and preloads its model before renderer callbacks. The two JavaScript profiles start without an extra canvas. Bundled WASM and Draco resources use the preview resource bridge; ONNX model weights load on demand and use CacheStorage for reuse. These adapters supply the required support libraries and dependency resources while preserving every artist script byte. The builder checks the original dependency references and records the profile and ordered additional libraries in provenance; changed references stop validation instead of applying an outdated adapter.

Ordered external metadata and gateway preferences remain available to artist scripts. `review-compatibility.json` identifies ten projects using Art Blocks PostParams. Six historical corpus projects—DDUST, Hatches, Gift of Time, pool party, Diggly Collects All, and degenerative—have frozen values for all 135 saved tokens in `review-contract-parameters.json`; only pool party is in pass 4. The snapshot was captured from the official generator on September 11, 2026 UTC. It includes evaluated read-augmentation hooks, such as block values and pool history, and degenerative's complete drawing chunks. Parameter values retain their original strings; an empty object preserves the artist's own defaults for unset parameters.

Each saved token carries its `previewContractParameters` object, which the preview renderer supplies to the expected ONCHAIN dependency before running the artist script. The app does not fetch these parameters or refresh them over time. The builder verifies exact collection, token, hash, source fingerprint, dependency, and payload coverage before enabling generation. Partial or mismatched snapshots fail validation. The four projects outside the active pass remain static-first; review membership and state do not change. Artist source, token order, and image references are preserved.

Hypertype's one shared IPFS dependency is bundled at `nft-player/Generators/newlibs/secondary-assets/hypertype/dependency.js`. The original 712,587 bytes contain its generator helpers, 35 text-analysis datasets, 104 vector glyphs, and 14 palettes; the saved tokens select from that common data. Embedded `retrieved_url` values are source attribution, and `fetchData` reads the embedded array without network access. The preview adapter requires the exact collection identity, artist-source SHA-256, and declared CID, verifies the local dependency's SHA-256, then replaces only its script URL with a data URL and immediately restores the prior URL setter. This preserves authored asynchronous initialization, token randomness, SVG layout, and immediate presentation. A missing or corrupt resource reports an error instead of falling back online. Artist source and token metadata remain unchanged. The pinned source, checksum, and attribution are recorded in `nft-player/Generators/newlibs/manifest.json`; `python3 tools/vendor_artblocks_secondary_dependencies.py` verifies it and `--fetch` restores it.

DDUST also receives a scoped startup adapter for its invalid `addEventListener("load", setup())` registration. The original call has already started async setup; the adapter skips registering the returned Promise as a listener and immediately restores normal event registration. Setup still runs once, ordinary event listeners still work, and actual async setup failures remain reportable. The artist source is unchanged.

To refresh the snapshot deliberately and apply it without refetching the full 519-project corpus:

```sh
python3 tools/capture_artblocks_contract_parameters.py --output tools/artblocks/review-contract-parameters.json
node tools/build_artblocks_good_preview.js --parameters-only
node tools/build_artblocks_good_preview.js --parameters-only --apply
python3 -m unittest discover -s tools -p capture_artblocks_contract_parameters_test.py
```

Capture validates all saved token hashes and exact artist source bytes against the official generator before publishing the snapshot. Its raw response evidence goes under the ignored `build/artblocks-contract-parameters/` directory. The offline parameter-only apply stages the full resource directory atomically while retaining unchanged files; ordinary full rebuilds also use the committed snapshot.

Unknown or changed contract requirements fail the builder instead of silently dropping a collection. Generative scripts can still fall back to the sample image on errors or asset timeouts. View sample image and Retry artwork support manual inspection without changing a decision. piñata3 retains its p5 image failure guard, which prevents its original setup wait from hanging after a failed image request.

The normal catalog, production resources, and widgets are unchanged; other platforms and Release builds use the normal catalog. The live sample curation changes only for the 13 second-pass rejections described above. Focused iOS coverage includes `ArtBlocksGoodPreviewTests` and `ArtBlocksPreviewResizeTests` for player entry, aspect fitting, settled resize reloads, next-token navigation, and recovery behavior.
