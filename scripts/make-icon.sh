#!/bin/bash
# Renders the app icon from BoltView (Snapshot.swift, "app-icon") into assets/AppIcon.icns. Run after changing the icon's look.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
.build/debug/NotchBuddy --snapshot "$TMP/shots"

SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/shots/app-icon.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$TMP/shots/app-icon.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
mkdir -p assets
iconutil -c icns "$SET" -o assets/AppIcon.icns
echo "Wrote assets/AppIcon.icns"
