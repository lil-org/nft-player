# Releasing

## Requirements and files

Install [asc](https://asccli.sh) **1.9.1 or later** and Node.js, then authenticate asc with App Store Connect. The helper checks the asc version before validation or release operations. No npm packages are required.

| Content | Location |
| --- | --- |
| App information | `app_store/metadata/<platform>/app-info` |
| Version metadata | `app_store/metadata/<platform>/version/<version>` |
| Screenshots | `app_store/screenshots/<platform>` |
| Release settings | `app_store/release/<platform>/settings.json` |
| Review details | `app_store/review/<platform>/details.json` |
| Workflows | `.asc/workflow.json` |

Platforms are `ios`, `macos`, `tvos`, and `visionos`. Release commands resolve the app from the project bundle ID and read `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `nft-player.xcodeproj`. Use `ASC_APP_ID`, `VERSION`, or `BUILD_NUMBER` only when an override is intentional.

## Validation and previews

Validate local metadata, screenshots, release settings, and review details:

```sh
asc workflow run validate
```

Preview a release with:

```sh
DRY_RUN=1 scripts/asc-store.sh release all
```

Dry runs preview supported uploads, releases, and version bumps. Release previews may read App Store Connect state and require authentication. They pass `--dry-run` to asc upload commands and skip archives, submission, and local version changes.

## Release commands

```sh
asc workflow run release
asc workflow run release PLATFORMS:macos,tvos,visionos
asc workflow run release_ios
asc workflow run release_macos
asc workflow run release_tvos
asc workflow run release_visionos
```

A release validates local files, prepares the store version, updates metadata and settings, uploads screenshots, builds and uploads the app, then submits it for review. macOS uses a direct-upload export followed by `asc review submit --platform MAC_OS`.

To upload only metadata or screenshots:

```sh
asc workflow run metadata
asc workflow run screenshots
```

The helper defaults `ASC_TIMEOUT` to `600s`. Override it explicitly when needed. If a submission request times out after App Store Connect accepts it, the helper checks the remote version state and continues when submission has already succeeded.

Release settings are applied through asc commands. If the installed asc lacks `versions update --uses-idfa`, `usesIdfa: false` is skipped with a notice; `true` fails with an upgrade instruction. asc 1.9.1 does not expose this flag. The helper does not directly patch App Store Connect to apply it.

## Version bumps

```sh
DRY_RUN=1 scripts/asc-store.sh bump
asc workflow run bump
```

The bump workflow increments the patch version and build number, renames the version metadata directories, updates release settings, then commits and pushes those files. Its dry run previews the new version without changing files or Git state. For an explicit version, run `scripts/asc-store.sh bump <version>`.

Run `scripts/asc-store.sh --help` for supported environment overrides and commands.
