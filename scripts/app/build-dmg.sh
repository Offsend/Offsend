#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${APP_PATH:-build/Release/Offsend.app}"
DMG_PATH="${DMG_PATH:-build/Offsend.dmg}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at $APP_PATH"
  echo "Build the app first, then rerun this script."
  exit 1
fi

if ! command -v create-dmg &>/dev/null; then
  echo "create-dmg not found. Install with: brew install create-dmg"
  exit 1
fi

mkdir -p "$(dirname "$DMG_PATH")"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$APP_PATH" "$stage/"
app_name="$(basename "$APP_PATH")"

create-dmg \
  --volname "Offsend" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 100 \
  --icon "$app_name" 180 190 \
  --hide-extension "$app_name" \
  --app-drop-link 480 190 \
  "$DMG_PATH" \
  "$stage"

echo "Created $DMG_PATH"
