#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="/tmp/cijing-derived"
APP_PATH="$DERIVED_DATA/Build/Products/Release-iphonesimulator/词鲸背单词.app"
BUNDLE_ID="com.joy-coder.cijingapp"
IPHONE_ID="${CIJING_IPHONE_SIMULATOR_ID:-EBE81B35-E9F3-46CD-9209-F8F02C924C0A}"
IPAD_ID="${CIJING_IPAD_SIMULATOR_ID:-D1547B6D-B368-425C-8F81-7BEE5B76809C}"
OUTPUT_ROOT="$ROOT_DIR/docs/assets/app-store-connect/zh-Hans"
STAGING_ROOT="$(mktemp -d /tmp/cijing-app-store-screenshots.XXXXXX)"

xcodebuild \
  -project "$ROOT_DIR/client/CiJing.xcodeproj" \
  -scheme CiJing \
  -configuration Release \
  -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

capture_device() {
  local device_id="$1"
  local output_dir="$2"
  mkdir -p "$output_dir"

  xcrun simctl boot "$device_id" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$device_id" -b
  xcrun simctl ui "$device_id" appearance light
  xcrun simctl install "$device_id" "$APP_PATH"
  xcrun simctl status_bar "$device_id" override --time "9:41" --batteryState charged --batteryLevel 100

  local tabs=(home library lookup settings)
  local labels=(01-home 02-library 03-lookup 04-settings)
  for index in "${!tabs[@]}"; do
    local staged_path="$STAGING_ROOT/${device_id}-${labels[$index]}.jpg"
    xcrun simctl terminate "$device_id" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl launch "$device_id" "$BUNDLE_ID" -ui-preview -ui-tab "${tabs[$index]}" >/dev/null
    # SwiftUI may still be animating the four-item tab bar after a cold launch.
    # Wait long enough that App Store assets never capture an intermediate layout.
    sleep 5
    xcrun simctl io "$device_id" screenshot --type=jpeg --mask=black "$staged_path"
    mv "$staged_path" "$output_dir/${labels[$index]}.jpg"
  done
}

capture_learning_flow() {
  local device_id="$1"
  local output_dir="$2"
  local flows=(reading-setup reading practice shadowing progress)
  local labels=(05-reading-setup 06-reading 07-practice 08-shadowing 09-progress)

  for index in "${!flows[@]}"; do
    local staged_path="$STAGING_ROOT/${device_id}-${labels[$index]}.jpg"
    xcrun simctl terminate "$device_id" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl launch "$device_id" "$BUNDLE_ID" -ui-preview -ui-flow "${flows[$index]}" >/dev/null
    sleep 5
    xcrun simctl io "$device_id" screenshot --type=jpeg --mask=black "$staged_path"
    mv "$staged_path" "$output_dir/${labels[$index]}.jpg"
  done
}

capture_device "$IPHONE_ID" "$OUTPUT_ROOT/iphone-6.5"
capture_learning_flow "$IPHONE_ID" "$OUTPUT_ROOT/iphone-6.5"
capture_device "$IPAD_ID" "$OUTPUT_ROOT/ipad-13"

rmdir "$STAGING_ROOT"
echo "Captured App Store screenshots in $OUTPUT_ROOT"
