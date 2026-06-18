#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/SholatBar.app"
DMG_PATH="$ROOT_DIR/dist/SholatBar-mac.dmg"

if [[ ! -d "$APP_PATH" ]]; then
  echo "SholatBar.app not found at: $APP_PATH"
  echo "Build the app first, then run this script again."
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

VOLUME_DIR="$WORK_DIR/SholatBar"
mkdir -p "$VOLUME_DIR"

cp -R "$APP_PATH" "$VOLUME_DIR/"
ln -s /Applications "$VOLUME_DIR/Applications"

hdiutil create \
  -volname "SholatBar" \
  -srcfolder "$VOLUME_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

hdiutil verify "$DMG_PATH"

echo "Created: $DMG_PATH"
