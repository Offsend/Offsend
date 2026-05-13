#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${APP_PATH:-build/Release/Offsend.app}"
DMG_PATH="${DMG_PATH:-build/Offsend.dmg}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at $APP_PATH"
  echo "Build the app first, then rerun this script."
  exit 1
fi

mkdir -p "$(dirname "$DMG_PATH")"
hdiutil create -volname "Offsend" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"
echo "Created $DMG_PATH"
