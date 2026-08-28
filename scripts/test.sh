#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
derived_data_path="${TEST_DERIVED_DATA_PATH:-$repo_root/build/test-derived-data}"

cd "$repo_root"

echo "Running Swift package tests..."
swift test --package-path "$repo_root"

if [[ -n "${IOS_TEST_DESTINATION:-}" ]]; then
  ios_test_destination="$IOS_TEST_DESTINATION"
else
  if ! simulator_list="$(xcrun simctl list devices available)"; then
    echo "Could not list available simulators. Open Xcode and install an iOS Simulator runtime." >&2
    exit 1
  fi

  iphone_udid=""
  iphone_pattern='^[[:space:]]*iPhone.*[[:space:]]+\(([[:xdigit:]-]{36})\)[[:space:]]+\((Booted|Shutdown)\)[[:space:]]*$'

  while IFS= read -r simulator; do
    if [[ "$simulator" =~ $iphone_pattern ]]; then
      iphone_udid="${BASH_REMATCH[1]}"
      break
    fi
  done <<< "$simulator_list"

  if [[ -z "$iphone_udid" ]]; then
    echo "No available iPhone simulator found. Open Xcode and install an iOS Simulator runtime." >&2
    exit 1
  fi

  ios_test_destination="platform=iOS Simulator,id=$iphone_udid"
fi

echo "Running iOS tests on $ios_test_destination..."
xcodebuild test -quiet \
  -project "$repo_root/nft-player.xcodeproj" \
  -scheme nft-player-ios \
  -configuration Debug \
  -destination "$ios_test_destination" \
  -derivedDataPath "$derived_data_path"
