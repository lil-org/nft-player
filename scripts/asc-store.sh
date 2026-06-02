#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-nft-folder.xcodeproj}"
PROJECT_FILE="$PROJECT/project.pbxproj"
EXPORT_OPTIONS="${EXPORT_OPTIONS:-.asc/export-options-app-store.plist}"
TVOS_EXPORT_OPTIONS="${TVOS_EXPORT_OPTIONS:-.asc/export-options-tvos.plist}"
UPLOAD_EXPORT_OPTIONS="${UPLOAD_EXPORT_OPTIONS:-.asc/export-options-upload.plist}"
DRY_RUN="${DRY_RUN:-0}"
VERSION_OVERRIDE="${VERSION:-}"
BUILD_NUMBER_OVERRIDE="${BUILD_NUMBER:-}"

read_project_setting() {
  local key="$1"
  local values
  local count

  values="$(awk -v key="$key" '$1 == key && $2 == "=" { gsub(/[";]/, "", $3); print $3 }' "$PROJECT_FILE" | sort -u)"
  count="$(printf '%s\n' "$values" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [[ "$count" == "0" ]]; then
    echo "Could not read $key from $PROJECT_FILE" >&2
    return 1
  fi

  if [[ "$count" != "1" ]]; then
    echo "$key has inconsistent values in $PROJECT_FILE: $values" >&2
    return 1
  fi

  printf '%s' "$values"
}

project_version() {
  read_project_setting MARKETING_VERSION
}

project_build_number() {
  read_project_setting CURRENT_PROJECT_VERSION
}

project_bundle_identifier() {
  node - "$PROJECT_FILE" <<'NODE'
const fs = require('fs');
const projectFile = process.argv[2];
const text = fs.readFileSync(projectFile, 'utf8');
const objectPattern = /\n\t\t([A-F0-9]{24}) \/\* [^*]* \*\/ = \{([\s\S]*?)\n\t\t\};/g;
const applicationConfigurationLists = new Set();
const applicationBuildConfigurations = new Set();
const values = new Set();

for (const match of text.matchAll(objectPattern)) {
  const block = match[2];
  if (
    block.includes('isa = PBXNativeTarget;') &&
    block.includes('productType = "com.apple.product-type.application";')
  ) {
    const listMatch = block.match(/buildConfigurationList = ([A-F0-9]{24}) \/\*/);
    if (listMatch) {
      applicationConfigurationLists.add(listMatch[1]);
    }
  }
}

for (const match of text.matchAll(objectPattern)) {
  const [id, block] = [match[1], match[2]];
  if (!applicationConfigurationLists.has(id)) continue;

  for (const configMatch of block.matchAll(/^\t\t\t\t([A-F0-9]{24}) \/\*/gm)) {
    applicationBuildConfigurations.add(configMatch[1]);
  }
}

for (const match of text.matchAll(objectPattern)) {
  const [id, block] = [match[1], match[2]];
  if (!applicationBuildConfigurations.has(id)) continue;

  const valueMatch = block.match(/PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/);
  if (valueMatch) {
    values.add(valueMatch[1].replace(/^"|"$/g, '').trim());
  }
}

const bundleIdentifiers = [...values].filter(Boolean).sort();

if (bundleIdentifiers.length === 0) {
  console.error(`Could not read application PRODUCT_BUNDLE_IDENTIFIER from ${projectFile}`);
  process.exit(1);
}

if (bundleIdentifiers.length !== 1) {
  console.error(`Application PRODUCT_BUNDLE_IDENTIFIER has inconsistent values in ${projectFile}: ${bundleIdentifiers.join('\n')}`);
  process.exit(1);
}

process.stdout.write(bundleIdentifiers[0]);
NODE
}

VERSION="${VERSION_OVERRIDE:-$(project_version)}"
BUILD_NUMBER="${BUILD_NUMBER_OVERRIDE:-$(project_build_number)}"
BUNDLE_ID="${BUNDLE_ID:-}"
APP_ID_OVERRIDE="${ASC_APP_ID:-${APP_ID:-}}"
RESOLVED_ASC_APP_ID=""

is_dry_run() {
  [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]
}

require_node() {
  if ! command -v node >/dev/null 2>&1; then
    echo "Node.js is required by scripts/asc-store.sh for JSON parsing." >&2
    return 1
  fi
}

usage() {
  cat <<'EOF'
Usage:
  scripts/asc-store.sh validate [all|ios|macos|tvos|visionos|comma-list]
  scripts/asc-store.sh metadata [all|ios|macos|tvos|visionos|comma-list]
  scripts/asc-store.sh screenshots [all|ios|macos|tvos|visionos|comma-list]
  scripts/asc-store.sh release [all|ios|macos|tvos|visionos|comma-list]
  scripts/asc-store.sh bump [version]
  scripts/asc-store.sh version

Prerequisites:
  asc and Node.js must be available on PATH.

Environment:
  ASC_APP_ID or APP_ID   Optional App Store Connect app id override.
  BUNDLE_ID              Optional bundle id override. Defaults to PRODUCT_BUNDLE_IDENTIFIER.
  EXPORT_OPTIONS         Export options for iOS and visionOS local releases.
  TVOS_EXPORT_OPTIONS    Export options for tvOS local releases.
  UPLOAD_EXPORT_OPTIONS  Export options for direct upload releases.
  VERSION                Optional release version override. Defaults to the Xcode project version.
  BUILD_NUMBER           Optional build number override. Defaults to the Xcode project build number.
  DRY_RUN=1              Preview asc mutations where the command supports it.
EOF
}

trim_space() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

platforms_for() {
  local target="${1:-all}"
  local platform
  local seen_platforms=""
  local -a requested_platforms
  local -a normalized_platforms

  if [[ "$target" == *","* ]]; then
    if [[ "$target" == *, ]]; then
      echo "Empty platform in comma-separated target: $target" >&2
      return 1
    fi

    IFS=',' read -ra requested_platforms <<< "$target"
    for platform in "${requested_platforms[@]}"; do
      platform="$(trim_space "$platform")"
      case "$platform" in
        ios|macos|tvos|visionos) ;;
        "") echo "Empty platform in comma-separated target: $target" >&2; return 1 ;;
        *) echo "Unsupported platform: $platform" >&2; return 1 ;;
      esac

      case " $seen_platforms " in
        *" $platform "*) echo "Duplicate platform in comma-separated target: $platform" >&2; return 1 ;;
      esac

      seen_platforms="${seen_platforms:+$seen_platforms }$platform"
      normalized_platforms+=("$platform")
    done
    printf '%s\n' "${normalized_platforms[@]}"
    return 0
  fi

  case "$target" in
    all) printf '%s\n' ios macos tvos visionos ;;
    ios|macos|tvos|visionos) printf '%s\n' "$target" ;;
    *) echo "Unsupported platform: $target" >&2; return 1 ;;
  esac
}

asc_platform() {
  case "$1" in
    ios) echo "IOS" ;;
    macos) echo "MAC_OS" ;;
    tvos) echo "TV_OS" ;;
    visionos) echo "VISION_OS" ;;
  esac
}

scheme_for() {
  case "$1" in
    ios) echo "nft-folder-ios" ;;
    macos) echo "nft-folder" ;;
    tvos) echo "nft-folder-tvos" ;;
    visionos) echo "nft-folder-vision" ;;
  esac
}

screenshot_types_for() {
  case "$1" in
    ios) printf '%s\n' APP_IPHONE_67 APP_IPAD_PRO_3GEN_129 ;;
    macos) printf '%s\n' APP_DESKTOP ;;
    tvos) printf '%s\n' APP_APPLE_TV ;;
    visionos) printf '%s\n' APP_APPLE_VISION_PRO ;;
  esac
}

metadata_dir() {
  echo "app_store/metadata/$1"
}

version_metadata_dir_for() {
  echo "app_store/metadata/$1/version/$2"
}

export_options_for() {
  case "$1" in
    tvos) echo "$TVOS_EXPORT_OPTIONS" ;;
    *) echo "$EXPORT_OPTIONS" ;;
  esac
}

version_metadata_dir() {
  version_metadata_dir_for "$1" "$VERSION"
}

release_settings_file() {
  echo "app_store/release/$1/settings.json"
}

review_details_file() {
  echo "app_store/review/$1/details.json"
}

ensure_app_id() {
  if [[ -n "$RESOLVED_ASC_APP_ID" ]]; then
    return 0
  fi

  if [[ -n "$APP_ID_OVERRIDE" ]]; then
    RESOLVED_ASC_APP_ID="$APP_ID_OVERRIDE"
    return 0
  fi

  if [[ -z "$BUNDLE_ID" ]]; then
    BUNDLE_ID="$(project_bundle_identifier)"
  fi

  local apps_json
  if ! apps_json="$(asc apps list --bundle-id "$BUNDLE_ID" --limit 2 --output json)"; then
    echo "Could not resolve App Store Connect app id for bundle id $BUNDLE_ID." >&2
    echo "Authenticate asc or set ASC_APP_ID once in your shell/CI environment." >&2
    return 1
  fi

  RESOLVED_ASC_APP_ID="$(printf '%s' "$apps_json" | node -e '
    let input = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", chunk => input += chunk);
    process.stdin.on("end", () => {
      const parsed = JSON.parse(input);
      const apps = Array.isArray(parsed.data) ? parsed.data : [];
      if (apps.length !== 1 || !apps[0].id) {
        console.error(`Expected one app match, found ${apps.length}. Set ASC_APP_ID to disambiguate.`);
        process.exit(1);
      }
      process.stdout.write(String(apps[0].id));
    });
  ')"
}

ensure_version_metadata_dir() {
  local platform="$1"
  local dir

  dir="$(version_metadata_dir "$platform")"
  if [[ ! -d "$dir" ]]; then
    echo "Missing metadata for $platform version $VERSION at $dir" >&2
    echo "Run scripts/asc-store.sh bump or move the version metadata directory." >&2
    return 1
  fi
}

validate_metadata() {
  local platform="$1"
  ensure_version_metadata_dir "$platform"
  asc metadata validate --dir "$(metadata_dir "$platform")"
}

validate_screenshots() {
  local platform="$1"
  local root="app_store/screenshots/$platform"
  local status=0
  local saw_directory=0
  local expected_type
  local dir

  if [[ ! -d "$root" ]]; then
    return 0
  fi

  while IFS= read -r -d '' dir; do
    local display_type
    local screenshot_count

    saw_directory=1
    display_type="$(basename "$dir")"
    if ! screenshot_type_is_expected "$platform" "$display_type"; then
      echo "Unexpected screenshot display type for $platform: $display_type at $dir" >&2
      status=1
      continue
    fi

    screenshot_count="$(screenshot_file_count "$dir")"
    if [[ "$screenshot_count" == "0" ]]; then
      echo "No PNG or JPEG screenshots found in $dir" >&2
      status=1
    fi
  done < <(find "$root" -mindepth 2 -maxdepth 2 -type d -print0 | sort -z)

  if [[ "$saw_directory" == "0" ]]; then
    echo "No screenshot display-type directories found under $root" >&2
    return 1
  fi

  while IFS= read -r expected_type; do
    if [[ -z "$(find "$root" -mindepth 2 -maxdepth 2 -type d -name "$expected_type" -print -quit)" ]]; then
      echo "Missing screenshot directory for $platform display type $expected_type under $root/<locale>/$expected_type" >&2
      status=1
    fi
  done < <(screenshot_types_for "$platform")

  return "$status"
}

screenshot_type_is_expected() {
  local platform="$1"
  local display_type="$2"
  local expected_type

  while IFS= read -r expected_type; do
    if [[ "$display_type" == "$expected_type" ]]; then
      return 0
    fi
  done < <(screenshot_types_for "$platform")

  return 1
}

screenshot_file_count() {
  find "$1" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | wc -l | tr -d ' '
}

push_metadata() {
  local platform="$1"
  local args=(metadata push)
  local app_info_id
  local app_info_status

  ensure_app_id
  args+=(--app "$RESOLVED_ASC_APP_ID")
  args+=(
    --version "$VERSION"
    --platform "$(asc_platform "$platform")"
    --dir "$(metadata_dir "$platform")"
  )
  if is_dry_run; then
    args+=(--dry-run)
  fi

  if app_info_id="$(resolve_app_info_id_for_metadata "$platform")"; then
    args+=(--app-info "$app_info_id")
  else
    app_info_status=$?
    if [[ "$app_info_status" -ne 2 ]]; then
      return "$app_info_status"
    fi
  fi

  asc "${args[@]}"
}

upload_screenshots() {
  local platform="$1"
  local root="app_store/screenshots/$platform"

  [[ -d "$root" ]] || return 0

  while IFS= read -r display_type; do
    local args=(screenshots upload)
    ensure_app_id
    args+=(--app "$RESOLVED_ASC_APP_ID")
    args+=(
      --version "$VERSION"
      --platform "$(asc_platform "$platform")"
      --path "$root"
      --device-type "$display_type"
      --replace
    )
    if is_dry_run; then
      args+=(--dry-run)
    fi
    asc "${args[@]}"
  done < <(screenshot_types_for "$platform")
}

publish_local_appstore() {
  local platform="$1"
  local archive_path=".asc/artifacts/nft-folder-$(asc_platform "$platform")-$VERSION-$BUILD_NUMBER.xcarchive"
  local ipa_path=".asc/artifacts/nft-folder-$(asc_platform "$platform")-$VERSION-$BUILD_NUMBER.ipa"
  local export_json

  ensure_app_id

  if [[ -z "$BUILD_NUMBER" ]]; then
    echo "BUILD_NUMBER is required for $platform release because the archive needs a fixed build number." >&2
    return 1
  fi

  if is_dry_run; then
    printf 'Would archive %s with scheme %s, export %s, and publish it to App Store Connect\n' "$archive_path" "$(scheme_for "$platform")" "$ipa_path"
    return 0
  fi

  mkdir -p .asc/artifacts

  asc xcode archive \
    --project "$PROJECT" \
    --scheme "$(scheme_for "$platform")" \
    --configuration Release \
    --archive-path "$archive_path" \
    --clean \
    --overwrite \
    --xcodebuild-flag=-destination \
    --xcodebuild-flag="generic/platform=$(xcode_destination_platform "$platform")" \
    --xcodebuild-flag="MARKETING_VERSION=$VERSION" \
    --xcodebuild-flag="CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
    --xcodebuild-flag=-allowProvisioningUpdates

  export_json="$(asc xcode export \
    --archive-path "$archive_path" \
    --export-options "$(export_options_for "$platform")" \
    --ipa-path "$ipa_path" \
    --overwrite \
    --xcodebuild-flag=-allowProvisioningUpdates \
    --output json)"

  if [[ ! -f "$ipa_path" ]]; then
    echo "Expected exported IPA at $ipa_path" >&2
    echo "$export_json" >&2
    return 1
  fi

  asc publish appstore \
    --app "$RESOLVED_ASC_APP_ID" \
    --ipa "$ipa_path" \
    --version "$VERSION" \
    --platform "$(asc_platform "$platform")" \
    --wait \
    --submit \
    --confirm
}

xcode_destination_platform() {
  case "$1" in
    ios) echo "iOS" ;;
    macos) echo "macOS" ;;
    tvos) echo "tvOS" ;;
    visionos) echo "visionOS" ;;
    *) echo "Unsupported platform: $1" >&2; return 1 ;;
  esac
}

next_patch_version() {
  node -e '
    const value = process.argv[1];
    const parts = value.split(".");
    const last = Number(parts[parts.length - 1]);
    if (!Number.isInteger(last)) {
      console.error(`Cannot patch-increment version: ${value}`);
      process.exit(1);
    }
    parts[parts.length - 1] = String(last + 1);
    process.stdout.write(parts.join("."));
  ' "$1"
}

ensure_bump_paths_clean() {
  local paths=("$PROJECT_FILE" "app_store/metadata" "app_store/release")

  if ! git diff --quiet -- "${paths[@]}"; then
    echo "Version files have unstaged changes. Commit or stash them before bumping." >&2
    return 1
  fi

  if ! git diff --cached --quiet -- "${paths[@]}"; then
    echo "Version files have staged changes. Commit or unstage them before bumping." >&2
    return 1
  fi
}

set_project_versions() {
  local version="$1"
  local build_number="$2"

  perl -0pi -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/g; s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $build_number;/g" "$PROJECT_FILE"
}

preflight_version_metadata_dirs_move() {
  local old_version="$1"
  local new_version="$2"
  local platform
  local old_dir
  local new_dir
  local status=0

  while IFS= read -r platform; do
    old_dir="$(version_metadata_dir_for "$platform" "$old_version")"
    new_dir="$(version_metadata_dir_for "$platform" "$new_version")"

    if [[ "$old_dir" == "$new_dir" ]]; then
      continue
    fi

    if [[ ! -d "$old_dir" ]]; then
      echo "Missing metadata directory for $platform version $old_version: $old_dir" >&2
      status=1
    fi

    if [[ -e "$new_dir" ]]; then
      echo "Refusing to overwrite existing metadata directory: $new_dir" >&2
      status=1
    fi
  done < <(platforms_for all)

  if [[ "$status" != "0" ]]; then
    return "$status"
  fi

  return 0
}

move_version_metadata_dirs() {
  local old_version="$1"
  local new_version="$2"
  local platform
  local old_dir
  local new_dir

  preflight_version_metadata_dirs_move "$old_version" "$new_version" || return

  while IFS= read -r platform; do
    old_dir="$(version_metadata_dir_for "$platform" "$old_version")"
    new_dir="$(version_metadata_dir_for "$platform" "$new_version")"

    if [[ "$old_dir" == "$new_dir" ]]; then
      continue
    fi

    mkdir -p "$(dirname "$new_dir")"
    mv "$old_dir" "$new_dir"
  done < <(platforms_for all)
}

set_release_settings_version() {
  local version="$1"
  node - "$version" <<'NODE'
const fs = require('fs');
const path = require('path');
const version = process.argv[2];
const root = path.join(process.cwd(), 'app_store', 'release');

for (const platform of fs.readdirSync(root)) {
  const file = path.join(root, platform, 'settings.json');
  if (!fs.existsSync(file)) continue;
  const settings = JSON.parse(fs.readFileSync(file, 'utf8'));
  settings.version = version;
  fs.writeFileSync(file, `${JSON.stringify(settings, null, 2)}\n`);
}
NODE
}

bump_version() {
  local old_version
  local old_build_number
  local new_version
  local new_build_number

  old_version="$(project_version)"
  old_build_number="$(project_build_number)"
  new_version="${1:-${VERSION_OVERRIDE:-$(next_patch_version "$old_version")}}"
  new_build_number="${BUILD_NUMBER_OVERRIDE:-$((old_build_number + 1))}"

  if is_dry_run; then
    printf 'Would bump version to %s (%s), update metadata version directories, commit, and push.\n' "$new_version" "$new_build_number"
    return 0
  fi

  ensure_bump_paths_clean
  preflight_version_metadata_dirs_move "$old_version" "$new_version"
  set_project_versions "$new_version" "$new_build_number"
  move_version_metadata_dirs "$old_version" "$new_version"
  set_release_settings_version "$new_version"

  git add -A "$PROJECT_FILE" app_store/metadata app_store/release
  git commit -m "bump version to $new_version ($new_build_number)" -- "$PROJECT_FILE" app_store/metadata app_store/release
  git push
}

json_field() {
  node -e '
    let input = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", chunk => input += chunk);
    process.stdin.on("end", () => {
      const data = JSON.parse(input);
      for (const key of process.argv.slice(1)) {
        const value = data[key];
        if (typeof value === "string" && value.trim()) {
          process.stdout.write(value.trim());
          return;
        }
      }
      process.exit(1);
    });
  ' "$@"
}

json_file_string() {
  local file="$1"
  local key="$2"

  node - "$file" "$key" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
const key = process.argv[3];
const data = JSON.parse(fs.readFileSync(file, 'utf8'));
const value = data[key];
if (typeof value !== 'string' || !value.trim()) {
  process.exit(1);
}
process.stdout.write(value.trim());
NODE
}

version_field_from_list_json() {
  local field="$1"
  local version="$2"
  local platform="$3"

  node -e '
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const field = process.argv[1];
  const version = process.argv[2];
  const platform = process.argv[3];
  const parsed = JSON.parse(input);
  const versions = Array.isArray(parsed.data) ? parsed.data : [];
  if (versions.length === 0) {
    process.exit(2);
  }
  if (versions.length !== 1 || !versions[0].id) {
    console.error(`Expected one App Store version for ${version} ${platform}, found ${versions.length}.`);
    process.exit(1);
  }

  const attributes = versions[0].attributes || {};
  let value = "";
  if (field === "id") {
    value = versions[0].id;
  } else if (field === "state") {
    value = attributes.appVersionState || attributes.appStoreState || attributes.state || "";
  } else {
    console.error(`Unsupported version field: ${field}`);
    process.exit(1);
  }

  if (typeof value !== "string" || !value.trim()) {
    console.error(`Missing ${field} for App Store version ${version} ${platform}.`);
    process.exit(1);
  }
  process.stdout.write(value.trim());
});
  ' "$field" "$version" "$platform"
}

version_list_json() {
  local platform="$1"
  ensure_app_id
  asc versions list \
    --app "$RESOLVED_ASC_APP_ID" \
    --version "$VERSION" \
    --platform "$(asc_platform "$platform")" \
    --limit 2 \
    --output json
}

find_version_id() {
  local platform="$1"
  local versions_json

  versions_json="$(version_list_json "$platform")"
  printf '%s' "$versions_json" | version_field_from_list_json id "$VERSION" "$(asc_platform "$platform")"
}

resolve_version_id() {
  local platform="$1"
  local version_id
  local status

  if version_id="$(find_version_id "$platform")"; then
    printf '%s' "$version_id"
    return 0
  else
    status=$?
  fi
  if [[ "$status" -eq 2 ]]; then
    echo "No App Store version found for $VERSION $(asc_platform "$platform")." >&2
  fi
  return "$status"
}

resolve_version_state() {
  local platform="$1"
  local version_id="$2"
  local versions_json

  versions_json="$(version_list_json "$platform")"
  printf '%s' "$versions_json" | node -e '
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const versionID = process.argv[1];
  const version = process.argv[2];
  const platform = process.argv[3];
  const parsed = JSON.parse(input);
  const versions = Array.isArray(parsed.data) ? parsed.data : [];
  const match = versions.find(item => item && item.id === versionID);
  if (!match) {
    console.error(`App Store version ${versionID} was not found for ${version} ${platform}.`);
    process.exit(1);
  }
  const attributes = match.attributes || {};
  const state = attributes.appVersionState || attributes.appStoreState || attributes.state || "";
  if (typeof state !== "string" || !state.trim()) {
    console.error(`Missing state for App Store version ${versionID}.`);
    process.exit(1);
  }
  process.stdout.write(state.trim());
});
  ' "$version_id" "$VERSION" "$(asc_platform "$platform")"
}

release_settings_json() {
  local mode="$1"
  local file="$2"
  shift 2

  node - "$mode" "$file" "$@" <<'NODE'
const fs = require('fs');
const mode = process.argv[2];
const file = process.argv[3];
const extraArgs = process.argv.slice(4);
const settings = JSON.parse(fs.readFileSync(file, 'utf8'));
const allowed = new Set([
  'version',
  'appInfoId',
  'copyright',
  'releaseType',
  'earliestReleaseDate',
  'usesIdfa',
  'primaryCategory',
  'secondaryCategory',
  'primarySubcategoryOne',
  'primarySubcategoryTwo',
  'secondarySubcategoryOne',
  'secondarySubcategoryTwo',
]);
const optionalStrings = [
  'appInfoId',
  'releaseType',
  'earliestReleaseDate',
  'secondaryCategory',
  'primarySubcategoryOne',
  'primarySubcategoryTwo',
  'secondarySubcategoryOne',
  'secondarySubcategoryTwo',
];
const categoryFields = [
  ['primaryCategory', '--primary'],
  ['secondaryCategory', '--secondary'],
  ['primarySubcategoryOne', '--primary-subcategory-one'],
  ['primarySubcategoryTwo', '--primary-subcategory-two'],
  ['secondarySubcategoryOne', '--secondary-subcategory-one'],
  ['secondarySubcategoryTwo', '--secondary-subcategory-two'],
];

function fail(message) {
  console.error(message);
  process.exit(1);
}
for (const key of Object.keys(settings)) {
  if (!allowed.has(key)) {
    fail(`Unsupported release settings field in ${file}: ${key}`);
  }
}
function requireString(key) {
  const value = settings[key];
  if (typeof value !== 'string' || !value.trim()) {
    fail(`${key} in ${file} must be a non-empty string`);
  }
}
function optionalString(key) {
  const value = settings[key];
  if (value !== undefined && value !== null && typeof value !== 'string') {
    fail(`${key} in ${file} must be a string`);
  }
}
function requireBoolean(key) {
  const value = settings[key];
  if (typeof value !== 'boolean') {
    fail(`${key} in ${file} must be a boolean`);
  }
}
function emit(value) {
  process.stdout.write(`${value}\0`);
}
function emitString(key, flag) {
  const value = settings[key];
  if (value === undefined || value === null) return;
  if (typeof value !== 'string') {
    fail(`${key} in ${file} must be a string`);
  }
  const trimmed = value.trim();
  if (!trimmed) return;
  emit(flag);
  emit(trimmed);
}
function validateSettings() {
  requireString('version');
  requireString('copyright');
  requireString('primaryCategory');
  for (const key of optionalStrings) optionalString(key);
  requireBoolean('usesIdfa');
}
function emitCategories() {
  let hasPrimary = false;
  let hasCategorySetting = false;
  for (const [key, flag] of categoryFields) {
    const value = settings[key];
    if (value === undefined || value === null) continue;
    if (typeof value !== 'string') {
      fail(`${key} in ${file} must be a string`);
    }
    const trimmed = value.trim();
    if (!trimmed) continue;
    if (key === 'primaryCategory') hasPrimary = true;
    hasCategorySetting = true;
    emit(flag);
    emit(trimmed);
  }
  if (hasCategorySetting && !hasPrimary) {
    fail(`${file} must include primaryCategory when category settings are present`);
  }
}
function writeAppInfoID() {
  const value = settings.appInfoId;
  if (value === undefined || value === null) {
    process.exit(2);
  }
  if (typeof value !== 'string') {
    fail(`appInfoId in ${file} must be a string`);
  }
  const trimmed = value.trim();
  if (!trimmed) {
    process.exit(2);
  }
  process.stdout.write(trimmed);
}
function requireUsesIdfa() {
  const value = settings.usesIdfa;
  if (value === undefined || value === null) {
    process.exit(1);
  }
  if (typeof value !== 'boolean') {
    fail(`usesIdfa in ${file} must be a boolean`);
  }
  return value;
}
function writeUsesIdfa() {
  process.stdout.write(String(requireUsesIdfa()));
}

switch (mode) {
case 'validate':
  validateSettings();
  break;
case 'version-update':
  emitString('copyright', '--copyright');
  emitString('releaseType', '--release-type');
  emitString('earliestReleaseDate', '--earliest-release-date');
  break;
case 'version-create': {
  emitString('copyright', '--copyright');
  const releaseType = settings.releaseType;
  if (typeof releaseType === 'string' && releaseType.trim().toUpperCase() !== 'SCHEDULED') {
    emitString('releaseType', '--release-type');
  }
  break;
}
case 'categories':
  emitCategories();
  break;
case 'app-info-id':
  writeAppInfoID();
  break;
case 'uses-idfa':
  writeUsesIdfa();
  break;
default:
  fail(`Unsupported release settings mode: ${mode}`);
}
NODE
}

validate_release_settings_schema() {
  release_settings_json validate "$1"
}

validate_release_settings() {
  local platform="$1"
  local file
  local settings_version

  file="$(release_settings_file "$platform")"
  if [[ ! -f "$file" ]]; then
    echo "Missing release settings for $platform at $file" >&2
    return 1
  fi

  validate_release_settings_schema "$file"

  settings_version="$(json_file_string "$file" version)" || {
    echo "Missing release settings version in $file" >&2
    return 1
  }
  if [[ "$settings_version" != "$VERSION" ]]; then
    echo "Release settings version mismatch in $file: expected $VERSION, found $settings_version" >&2
    return 1
  fi
}

release_version_update_args() {
  release_settings_json version-update "$1"
}

release_version_create_args() {
  release_settings_json version-create "$1"
}

release_category_args() {
  release_settings_json categories "$1"
}

release_settings_app_info_id() {
  release_settings_json app-info-id "$1"
}

explicit_release_settings_app_info_id() {
  local platform="$1"
  local file

  file="$(release_settings_file "$platform")"
  [[ -f "$file" ]] || return 2
  release_settings_app_info_id "$file"
}

release_uses_idfa_value() {
  release_settings_json uses-idfa "$1"
}

apply_version_compliance_settings() {
  local file="$1"
  local version_id="$2"
  local uses_idfa
  local update_help

  uses_idfa="$(release_uses_idfa_value "$file")"
  if ! update_help="$(asc versions update --help 2>&1)"; then
    echo "Could not inspect 'asc versions update --help' before applying usesIdfa from $file." >&2
    printf '%s\n' "$update_help" >&2
    return 1
  fi
  if [[ "$update_help" != *"--uses-idfa"* ]]; then
    if [[ "$uses_idfa" == "false" ]]; then
      echo "Installed asc does not expose 'versions update --uses-idfa'; skipping usesIdfa=false from $file." >&2
      return 0
    fi
    echo "Installed asc does not expose 'versions update --uses-idfa'." >&2
    echo "Refusing to PATCH App Store Connect directly because release mutations must go through asccli." >&2
    echo "Upgrade asc to a version with --uses-idfa support before applying usesIdfa from $file." >&2
    return 1
  fi

  asc versions update --version-id "$version_id" --uses-idfa "$uses_idfa"
}

resolve_app_info_id_for_version() {
  local platform="$1"
  local version_id="$2"
  local explicit_app_info_id
  local app_info_status
  local version_state
  local app_infos_json

  if explicit_app_info_id="$(explicit_release_settings_app_info_id "$platform")"; then
    printf '%s' "$explicit_app_info_id"
    return 0
  else
    app_info_status=$?
    if [[ "$app_info_status" -ne 2 ]]; then
      return "$app_info_status"
    fi
  fi

  ensure_app_id
  version_state="$(resolve_version_state "$platform" "$version_id")"
  app_infos_json="$(asc apps info list --app "$RESOLVED_ASC_APP_ID" --output json)"

  printf '%s' "$app_infos_json" | node -e '
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const version = process.argv[1];
  const platform = process.argv[2];
  const versionState = process.argv[3];
  const appID = process.argv[4];
  const parsed = JSON.parse(input);
  const appInfos = Array.isArray(parsed.data) ? parsed.data : [];

  function stringAttribute(item, keys) {
    const attributes = item && item.attributes ? item.attributes : {};
    for (const key of keys) {
      const value = attributes[key];
      if (typeof value === "string" && value.trim()) {
        return value.trim();
      }
    }
    return "";
  }
  function formatCandidates(items) {
    if (!items.length) return "none";
    return items
      .map(item => {
        const id = item && item.id ? item.id : "unknown";
        const state = stringAttribute(item, ["state", "appStoreState"]) || "unknown";
        return `${id}:${state}`;
      })
      .join(", ");
  }
  function statePreference(state) {
    const resolved = String(state || "").trim().toUpperCase();
    if (!resolved) return [];
    switch (resolved) {
      case "PREPARE_FOR_SUBMISSION":
      case "DEVELOPER_REJECTED":
      case "REJECTED":
        return [
          resolved,
          "READY_FOR_REVIEW",
          "WAITING_FOR_REVIEW",
          "IN_REVIEW",
          "PENDING_DEVELOPER_RELEASE",
          "PENDING_APPLE_RELEASE",
          "PENDING_RELEASE",
          "READY_FOR_DISTRIBUTION",
          "READY_FOR_SALE",
        ];
      case "READY_FOR_REVIEW":
      case "WAITING_FOR_REVIEW":
      case "IN_REVIEW":
        return [
          resolved,
          "READY_FOR_REVIEW",
          "WAITING_FOR_REVIEW",
          "IN_REVIEW",
          "PENDING_DEVELOPER_RELEASE",
          "PENDING_APPLE_RELEASE",
          "PENDING_RELEASE",
        ];
      case "PENDING_DEVELOPER_RELEASE":
      case "PENDING_APPLE_RELEASE":
        return [resolved, "PENDING_RELEASE", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW"];
      case "REPLACED_WITH_NEW_VERSION":
        return [resolved, "REPLACED_WITH_NEW_INFO"];
      case "READY_FOR_SALE":
      case "PREORDER_READY_FOR_SALE":
        return [resolved, "READY_FOR_DISTRIBUTION"];
      default:
        return [resolved];
    }
  }

  if (appInfos.length === 0) {
    console.error(`No App Info records found for app ${appID}.`);
    process.exit(1);
  }
  if (appInfos.length === 1) {
    if (!appInfos[0].id) {
      console.error(`App Info record for app ${appID} is missing an id.`);
      process.exit(1);
    }
    process.stdout.write(String(appInfos[0].id));
    return;
  }

  for (const preferredState of statePreference(versionState)) {
    const matches = appInfos.filter(item => {
      if (!item || !item.id) return false;
      const state = stringAttribute(item, ["state", "appStoreState"]).toUpperCase();
      return state === preferredState;
    });
    if (matches.length === 1) {
      process.stdout.write(String(matches[0].id));
      return;
    }
    if (matches.length > 1) {
      console.error(
        `Could not resolve a single App Info for ${version} ${platform} in state ${versionState}. ` +
        `Candidates: ${formatCandidates(appInfos)}. Add appInfoId to ${platform} release settings if this is ambiguous.`
      );
      process.exit(1);
    }
  }
  console.error(
    `Could not resolve a single App Info for ${version} ${platform} in state ${versionState}. ` +
    `Candidates: ${formatCandidates(appInfos)}. Add appInfoId to ${platform} release settings if this is ambiguous.`
  );
  process.exit(1);
});
  ' "$VERSION" "$(asc_platform "$platform")" "$version_state" "$RESOLVED_ASC_APP_ID"
}

resolve_app_info_id_for_metadata() {
  local platform="$1"
  local explicit_app_info_id
  local app_info_status
  local version_id
  local status

  if explicit_app_info_id="$(explicit_release_settings_app_info_id "$platform")"; then
    printf '%s' "$explicit_app_info_id"
    return 0
  else
    app_info_status=$?
    if [[ "$app_info_status" -ne 2 ]]; then
      return "$app_info_status"
    fi
  fi

  if version_id="$(find_version_id "$platform")"; then
    resolve_app_info_id_for_version "$platform" "$version_id"
    return
  else
    status=$?
  fi

  if [[ "$status" -eq 2 ]]; then
    return 2
  fi
  return "$status"
}

ensure_app_store_version() {
  local platform="$1"
  local file
  local version_id
  local status
  local args=()
  local arg

  file="$(release_settings_file "$platform")"
  validate_release_settings "$platform"

  if is_dry_run; then
    printf 'Would ensure App Store version %s exists for %s\n' "$VERSION" "$platform"
    return 0
  fi

  if version_id="$(find_version_id "$platform")"; then
    printf 'Using existing %s App Store version %s\n' "$platform" "$version_id"
    return 0
  else
    status=$?
  fi
  if [[ "$status" -ne 2 ]]; then
    return "$status"
  fi

  ensure_app_id
  args=(
    versions create
    --app "$RESOLVED_ASC_APP_ID"
    --version "$VERSION"
    --platform "$(asc_platform "$platform")"
  )
  while IFS= read -r -d '' arg; do
    args+=("$arg")
  done < <(release_version_create_args "$file")
  asc "${args[@]}"
}

apply_release_settings() {
  local platform="$1"
  local file
  local version_id
  local uses_idfa
  local version_args=()
  local category_args=()
  local arg

  file="$(release_settings_file "$platform")"
  validate_release_settings "$platform"

  while IFS= read -r -d '' arg; do
    version_args+=("$arg")
  done < <(release_version_update_args "$file")

  while IFS= read -r -d '' arg; do
    category_args+=("$arg")
  done < <(release_category_args "$file")

  if is_dry_run; then
    uses_idfa="$(release_uses_idfa_value "$file")"
    if [[ "${#version_args[@]}" -gt 0 ]]; then
      printf 'Would update %s version settings from %s\n' "$platform" "$file"
    fi
    if [[ -n "$uses_idfa" ]]; then
      printf 'Would update %s usesIdfa to %s from %s\n' "$platform" "$uses_idfa" "$file"
    fi
    if [[ "${#category_args[@]}" -gt 0 ]]; then
      printf 'Would update %s categories from %s\n' "$platform" "$file"
    fi
    return 0
  fi

  version_id="$(resolve_version_id "$platform")"
  if [[ "${#version_args[@]}" -gt 0 ]]; then
    asc versions update --version-id "$version_id" "${version_args[@]}"
  fi
  apply_version_compliance_settings "$file" "$version_id"
  if [[ "${#category_args[@]}" -gt 0 ]]; then
    local app_info_id
    app_info_id="$(resolve_app_info_id_for_version "$platform" "$version_id")"
    asc categories set --app "$RESOLVED_ASC_APP_ID" --app-info "$app_info_id" "${category_args[@]}"
  fi
}

review_details_json() {
  local mode="$1"
  local file="$2"

  node - "$mode" "$file" <<'NODE'
const fs = require('fs');
const mode = process.argv[2];
const file = process.argv[3];
const details = JSON.parse(fs.readFileSync(file, 'utf8'));
const allowed = new Set([
  'contactFirstName',
  'contactLastName',
  'contactEmail',
  'contactPhone',
  'demoAccountName',
  'demoAccountPassword',
  'demoAccountRequired',
  'notes',
]);

function fail(message) {
  console.error(message);
  process.exit(1);
}
for (const key of Object.keys(details)) {
  if (!allowed.has(key)) {
    fail(`Unsupported review details field in ${file}: ${key}`);
  }
}
function requireString(key) {
  const value = details[key];
  if (typeof value !== 'string' || !value.trim()) {
    fail(`${key} in ${file} must be a non-empty string`);
  }
}
function optionalString(key) {
  const value = details[key];
  if (value !== undefined && value !== null && typeof value !== 'string') {
    fail(`${key} in ${file} must be a string`);
  }
}
function emit(value) {
  process.stdout.write(`${value}\0`);
}
function emitString(key, flag) {
  const value = details[key];
  if (value === undefined || value === null) return;
  if (typeof value !== 'string') {
    fail(`${key} in ${file} must be a string`);
  }
  emit(flag);
  emit(value.trim());
}
function validateDetails() {
  requireString('contactFirstName');
  requireString('contactLastName');
  requireString('contactEmail');
  requireString('contactPhone');
  optionalString('notes');
  optionalString('demoAccountName');
  optionalString('demoAccountPassword');
  if (details.demoAccountRequired !== undefined && details.demoAccountRequired !== null && typeof details.demoAccountRequired !== 'boolean') {
    fail(`demoAccountRequired in ${file} must be a boolean`);
  }
  if (details.demoAccountRequired === true) {
    requireString('demoAccountName');
    requireString('demoAccountPassword');
  }
}

switch (mode) {
case 'validate':
  validateDetails();
  break;
case 'args':
  emitString('contactFirstName', '--contact-first-name');
  emitString('contactLastName', '--contact-last-name');
  emitString('contactEmail', '--contact-email');
  emitString('contactPhone', '--contact-phone');
  emitString('demoAccountName', '--demo-account-name');
  emitString('demoAccountPassword', '--demo-account-password');
  emitString('notes', '--notes');
  if (details.demoAccountRequired !== undefined && details.demoAccountRequired !== null) {
    if (typeof details.demoAccountRequired !== 'boolean') {
      fail(`demoAccountRequired in ${file} must be a boolean`);
    }
    emit(`--demo-account-required=${details.demoAccountRequired ? 'true' : 'false'}`);
  } else {
    emit('--demo-account-required=false');
  }
  break;
default:
  fail(`Unsupported review details mode: ${mode}`);
}
NODE
}

validate_review_details_schema() {
  review_details_json validate "$1"
}

validate_review_details() {
  local platform="$1"
  local file

  file="$(review_details_file "$platform")"
  if [[ ! -f "$file" ]]; then
    echo "Missing review details for $platform at $file" >&2
    return 1
  fi

  validate_review_details_schema "$file"
}

review_details_args() {
  review_details_json args "$1"
}

id_from_json() {
  node -e '
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const parsed = JSON.parse(input);
  const id = parsed && parsed.data && parsed.data.id ? parsed.data.id : parsed.id;
  if (typeof id !== "string" || !id.trim()) {
    process.exit(1);
  }
  process.stdout.write(id.trim());
});
  '
}

review_detail_id_from_json() {
  id_from_json
}

apply_review_details() {
  local platform="$1"
  local file
  local version_id
  local details_json
  local detail_id
  local args=()
  local arg

  file="$(review_details_file "$platform")"
  validate_review_details "$platform"

  while IFS= read -r -d '' arg; do
    args+=("$arg")
  done < <(review_details_args "$file")

  if is_dry_run; then
    printf 'Would upsert %s review details from %s\n' "$platform" "$file"
    return 0
  fi

  version_id="$(resolve_version_id "$platform")"
  details_json="$(asc review details-for-version --version-id "$version_id" --output json)"
  if detail_id="$(printf '%s' "$details_json" | review_detail_id_from_json)"; then
    asc review details-update --id "$detail_id" "${args[@]}"
  else
    asc review details-create --version-id "$version_id" "${args[@]}"
  fi
}

asc_supports_review_submit() {
  asc review submit --help >/dev/null 2>&1
}

asc_supports_review_submission_fallback() {
  asc versions attach-build --help >/dev/null 2>&1 &&
    asc review submissions-create --help >/dev/null 2>&1 &&
    asc review items-add --help >/dev/null 2>&1 &&
    asc review submissions-submit --help >/dev/null 2>&1
}

ensure_macos_review_submission_commands() {
  if asc_supports_review_submit || asc_supports_review_submission_fallback; then
    return 0
  fi

  echo "Installed asc does not expose a supported macOS review submission path." >&2
  echo "Expected either 'asc review submit' or the documented 'versions attach-build' plus 'review submissions-*' commands." >&2
  return 1
}

submit_macos_review() {
  local build_id="$1"
  local version_id
  local submission_json
  local submission_id
  local submit_args=()

  ensure_app_id
  if asc_supports_review_submit; then
    submit_args=(review submit)
    submit_args+=(--app "$RESOLVED_ASC_APP_ID")
    submit_args+=(
      --version "$VERSION"
      --build "$build_id"
      --platform MAC_OS
      --confirm
    )
    asc "${submit_args[@]}"
    return
  fi

  if ! asc_supports_review_submission_fallback; then
    ensure_macos_review_submission_commands
    return
  fi

  version_id="$(resolve_version_id macos)"
  asc versions attach-build --version-id "$version_id" --build "$build_id"
  submission_json="$(asc review submissions-create --app "$RESOLVED_ASC_APP_ID" --platform MAC_OS --output json)"
  if ! submission_id="$(printf '%s' "$submission_json" | id_from_json)"; then
    echo "Could not read review submission id from asc review submissions-create output." >&2
    return 1
  fi
  asc review items-add --submission "$submission_id" --item-type appStoreVersions --item-id "$version_id"
  asc review submissions-submit --id "$submission_id" --confirm
}

release_macos() {
  if [[ -z "$BUILD_NUMBER" ]]; then
    echo "BUILD_NUMBER is required for macos release because the direct-upload export needs a fixed build number." >&2
    return 1
  fi

  local archive_path=".asc/artifacts/nft-folder-MAC_OS-$VERSION-$BUILD_NUMBER.xcarchive"
  local ipa_placeholder=".asc/artifacts/nft-folder-MAC_OS-$VERSION-$BUILD_NUMBER.ipa"

  if is_dry_run; then
    printf 'Would archive %s with scheme %s and upload via %s\n' "$archive_path" "$(scheme_for macos)" "$UPLOAD_EXPORT_OPTIONS"
    return 0
  fi

  ensure_macos_review_submission_commands
  mkdir -p .asc/artifacts

  asc xcode archive \
    --project "$PROJECT" \
    --scheme "$(scheme_for macos)" \
    --configuration Release \
    --archive-path "$archive_path" \
    --clean \
    --overwrite \
    --xcodebuild-flag=-destination \
    --xcodebuild-flag=generic/platform=macOS \
    --xcodebuild-flag="MARKETING_VERSION=$VERSION" \
    --xcodebuild-flag="CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
    --xcodebuild-flag=-allowProvisioningUpdates

  local export_json
  export_json="$(asc xcode export \
    --archive-path "$archive_path" \
    --export-options "$UPLOAD_EXPORT_OPTIONS" \
    --ipa-path "$ipa_placeholder" \
    --overwrite \
    --wait \
    --xcodebuild-flag=-allowProvisioningUpdates \
    --output json)"

  local build_id
  build_id="$(printf '%s' "$export_json" | json_field build_id)"

  submit_macos_review "$build_id"
}

release_platform() {
  local platform="$1"

  validate_platform "$platform"
  ensure_app_store_version "$platform"
  push_metadata "$platform"
  apply_release_settings "$platform"
  apply_review_details "$platform"
  upload_screenshots "$platform"

  if [[ "$platform" == "macos" ]]; then
    release_macos
  else
    publish_local_appstore "$platform"
  fi
}

metadata_platform() {
  local platform="$1"

  validate_metadata "$platform"
  ensure_app_store_version "$platform"
  push_metadata "$platform"
}

screenshots_platform() {
  local platform="$1"
  local root="app_store/screenshots/$platform"

  validate_screenshots "$platform"
  [[ -d "$root" ]] || return 0
  ensure_app_store_version "$platform"
  upload_screenshots "$platform"
}

validate_platform() {
  local platform="$1"

  validate_metadata "$platform"
  validate_screenshots "$platform"
  validate_release_settings "$platform"
  validate_review_details "$platform"
}

run_for_platforms() {
  local target="$1"
  local action="$2"
  local platform
  local platforms

  if ! platforms="$(platforms_for "$target")"; then
    return 1
  fi

  [[ -n "$platforms" ]] || return 0
  while IFS= read -r platform; do
    "$action" "$platform"
  done <<< "$platforms"
}

command="${1:-}"
target="${2:-all}"

if [[ -z "$command" || "$command" == "-h" || "$command" == "--help" ]]; then
  usage
  exit 0
fi

case "$command" in
  validate|metadata|screenshots|release|bump)
    require_node
    ;;
esac

case "$command" in
  validate)
    run_for_platforms "$target" validate_platform
    ;;
  metadata)
    run_for_platforms "$target" metadata_platform
    ;;
  screenshots)
    run_for_platforms "$target" screenshots_platform
    ;;
  release)
    run_for_platforms "$target" release_platform
    ;;
  bump)
    bump_version "${2:-}"
    ;;
  version)
    printf '%s (%s)\n' "$VERSION" "$BUILD_NUMBER"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
