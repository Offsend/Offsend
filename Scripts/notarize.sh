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

# notarytool may exit 0 even when status is Invalid; always inspect JSON before stapling.
NOTARY_JSON="$(
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait \
    --output-format json
)"

STATUS="$(printf '%s' "$NOTARY_JSON" | /usr/bin/python3 -c 'import sys, json; print(json.load(sys.stdin).get("status", ""))')"
SUBMISSION_ID="$(printf '%s' "$NOTARY_JSON" | /usr/bin/python3 -c 'import sys, json; print(json.load(sys.stdin).get("id", ""))')"

if [[ "$STATUS" != "Accepted" ]]; then
  echo "Notarization finished with status: ${STATUS:-unknown}" >&2
  echo "notarytool JSON response:" >&2
  printf '%s\n' "$NOTARY_JSON" >&2
  if [[ -n "$SUBMISSION_ID" ]]; then
    echo "Apple notarization log (notarytool log):" >&2
    xcrun notarytool log "$SUBMISSION_ID" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_PASSWORD" >&2 || true
  fi
  exit 1
fi

xcrun stapler staple "$DMG_PATH"

if ! xcrun stapler validate "$DMG_PATH"; then
  echo "stapler validate failed for $DMG_PATH" >&2
  exit 1
fi

echo "Notarization complete; stapler validate OK."
