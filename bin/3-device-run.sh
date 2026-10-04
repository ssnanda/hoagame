#!/usr/bin/env bash
set -euo pipefail

# HOA President — install the built IPA on a connected iPhone
# Run ./bin/2a-hoagame-ipa.sh first.
#
#   ./bin/3-device-run.sh
#   ./bin/3-device-run.sh --device <UDID>   (only if several devices are connected)

IPA="$HOME/Documents/GitHub/ipa/hoagame.ipa"
BUNDLE_ID="com.ssnanda.hoagame"
DEVICE_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE_ID="${2:-}"; shift 2 ;;
    --help|-h) sed -n 3,8p "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$IPA" ]] || { echo "Error: $IPA missing — run ./bin/2a-hoagame-ipa.sh first" >&2; exit 1; }

if [[ -z "$DEVICE_ID" ]]; then
  TMP_JSON="$(mktemp)"
  xcrun devicectl list devices --json-output "$TMP_JSON" >/dev/null 2>&1 || true
  MATCHES="$(python3 - "$TMP_JSON" <<'PY'
import json, sys
try:
    devs = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devs = []
for d in devs:
    if d.get("hardwareProperties", {}).get("platform") == "iOS" and \
       d.get("connectionProperties", {}).get("tunnelState") == "connected":
        print(d["identifier"])
PY
)"
  rm -f "$TMP_JSON"
  COUNT="$(echo "$MATCHES" | grep -c . || true)"
  if [[ "$COUNT" -eq 1 ]]; then
    DEVICE_ID="$MATCHES"
    echo "Found device: $DEVICE_ID"
  else
    echo "Error: expected exactly one connected iPhone, found $COUNT. Unlock/plug in your phone, or pass --device <ID>:" >&2
    xcrun devicectl list devices >&2
    exit 1
  fi
fi

xcrun devicectl device install app --device "$DEVICE_ID" "$IPA"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"
