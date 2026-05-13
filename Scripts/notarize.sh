#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${DMG_PATH:-build/Offsend.dmg}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH"
  exit 1
fi

if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" ]]; then
  echo "Set APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD before notarization."
  exit 1
fi

echo "Submitting for notarization: $DMG_PATH ($(stat -f%z "$DMG_PATH") bytes)"

xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

xcrun stapler staple "$DMG_PATH"

if ! xcrun stapler validate "$DMG_PATH"; then
  echo "stapler validate failed for $DMG_PATH" >&2
  exit 1
fi

echo "Notarization complete; stapler validate OK."
