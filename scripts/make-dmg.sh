#!/bin/bash
# Packs build/NotchBuddy.app into build/Notchi.dmg as Notchi.app, next to an Applications shortcut.
# Run scripts/make-app.sh first (UNIVERSAL=1 for the release build).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/NotchBuddy.app"
DMG="build/Notchi.dmg"
[[ -d "$APP" ]] || { echo "No $APP: run scripts/make-app.sh first" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Notchi.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Notchi" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Done! $DMG ($(du -h "$DMG" | cut -f1))"
