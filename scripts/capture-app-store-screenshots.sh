#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="/tmp/cijing-derived/Build/Products/Debug-iphonesimulator/词鲸背单词.app"
BUNDLE_ID="com.joy-coder.cijingapp"
IPHONE_ID="${CIJING_IPHONE_SIMULATOR_ID:-EBE81B35-E9F3-46CD-9209-F8F02C924C0A}"
IPAD_ID="${CIJING_IPAD_SIMULATOR_ID:-D1547B6D-B368-425C-8F81-7BEE5B76809C}"
OUTPUT_ROOT="$ROOT_DIR/docs/assets/app-store-connect/zh-Hans"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Simulator app not found at $APP_PATH. Build it before capturing screenshots." >&2
  exit 1
fi

capture_device() {
  local device_id="$1"
  local output_dir="$2"
  mkdir -p "$output_dir"

  xcrun simctl boot "$device_id" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$device_id" -b
  xcrun simctl install "$device_id" "$APP_PATH"
  xcrun simctl status_bar "$device_id" override --time "9:41" --batteryState charged --batteryLevel 100

  local tabs=(home library lookup settings)
  local labels=(01-home 02-library 03-lookup 04-settings)
  for index in "${!tabs[@]}"; do
    xcrun simctl terminate "$device_id" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl launch "$device_id" "$BUNDLE_ID" -ui-preview -ui-tab "${tabs[$index]}" >/dev/null
    sleep 2
    xcrun simctl io "$device_id" screenshot --type=jpeg --mask=black "$output_dir/${labels[$index]}.jpg"
  done
}

capture_learning_flow() {
  local device_id="$1"
  local output_dir="$2"
  local flows=(reading-setup reading practice shadowing progress)
  local labels=(05-reading-setup 06-reading 07-practice 08-shadowing 09-progress)

  for index in "${!flows[@]}"; do
    xcrun simctl terminate "$device_id" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl launch "$device_id" "$BUNDLE_ID" -ui-preview -ui-flow "${flows[$index]}" >/dev/null
    sleep 2
    xcrun simctl io "$device_id" screenshot --type=jpeg --mask=black "$output_dir/${labels[$index]}.jpg"
  done
}

capture_device "$IPHONE_ID" "$OUTPUT_ROOT/iphone-6.5"
capture_learning_flow "$IPHONE_ID" "$OUTPUT_ROOT/iphone-6.5"
capture_device "$IPAD_ID" "$OUTPUT_ROOT/ipad-13"

echo "Captured App Store screenshots in $OUTPUT_ROOT"
