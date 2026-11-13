#!/bin/bash
# Prints the GitHub release notes for a tag: install steps, then the commits since the previous tag.
# Usage: scripts/release-notes.sh v0.3.7   (needs full git history and tags)
set -euo pipefail
TAG="${1:?usage: release-notes.sh <tag>}"
REPO="${GITHUB_REPOSITORY:-heyhadi/notchi}"
PREV="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"

cat <<'EOF'
Open Notchi.dmg and drag Notchi into Applications. macOS 14 or later, Apple Silicon or Intel.

The app is not notarized yet, so macOS blocks the first launch. Open Notchi once, then go to System Settings → Privacy & Security and click Open Anyway next to Notchi. You only do this once.

## What's changed

EOF
if [ -z "$PREV" ]; then
  echo "First release."
else
  git log --no-merges --reverse --format='- %s' "$PREV..$TAG"
  echo
  echo "**Full changelog**: https://github.com/$REPO/compare/$PREV...$TAG"
fi
