#!/usr/bin/env bash
set -euo pipefail

# HOA President — iPhone simulator launcher
# Exports the Xcode project with Godot, builds for the simulator, installs, launches.
#
#   ./bin/2b-sim-iphone.sh
#   ./bin/2b-sim-iphone.sh --device <UDID>

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
DEVICE_ID="BAE45ECD-3952-41E5-AAF0-5AD93C703CBE"
BUNDLE_ID="com.ssnanda.hoagame"
OUT_DIR="$ROOT_DIR/build/ios-sim"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE_ID="${2:-}"; shift 2 ;;
    --help|-h) sed -n 3,7p "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

xcrun simctl list devices | grep -q "$DEVICE_ID" || {
  echo "Device $DEVICE_ID not found. Available iPhones:" >&2
  xcrun simctl list devices | grep iPhone >&2
  exit 1
}

echo "Exporting Xcode project..."
rm -rf "$OUT_DIR"; mkdir -p "$OUT_DIR"
"$GODOT" --headless --path "$ROOT_DIR" --export-debug "iOS" "$OUT_DIR/hoagame.xcodeproj"

echo "Building for simulator..."
xcodebuild -project "$OUT_DIR/hoagame.xcodeproj" -scheme hoagame -configuration Debug \
  -sdk iphonesimulator -destination "id=$DEVICE_ID" \
  -derivedDataPath "$OUT_DIR/derived" CODE_SIGNING_ALLOWED=NO build -quiet

APP_PATH="$(find "$OUT_DIR/derived/Build/Products" -maxdepth 2 -name '*.app' -print -quit)"
[[ -n "$APP_PATH" ]] || { echo "Error: built .app not found" >&2; exit 1; }

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
open -a Simulator
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
