#!/usr/bin/env bash
#
# Semantic-version bump: reads the latest `vX.Y.Z` git tag, increments the requested part, and
# creates a new annotated tag. The tag is the single source of truth for the app's version —
# build-app.sh derives CFBundleShortVersionString from it.
#
# Usage (normally via the Makefile):
#   scripts/bump-version.sh patch     # v0.1.1 -> v0.1.2
#   scripts/bump-version.sh minor     # v0.1.1 -> v0.2.0
#   scripts/bump-version.sh major     # v0.1.1 -> v1.0.0
#
# The tag is created locally only; push it yourself with `git push origin <tag>`.
set -euo pipefail
cd "$(dirname "$0")/.."

part="${1:-}"
case "$part" in
  patch|minor|major) ;;
  *) echo "usage: $(basename "$0") patch|minor|major" >&2; exit 2 ;;
esac

# Refuse to tag a dirty tree — a tag should point at a committed, reproducible state.
if ! git diff --quiet HEAD 2>/dev/null; then
  echo "!! working tree has uncommitted changes; commit or stash before bumping" >&2
  exit 1
fi

latest="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || echo v0.0.0)"
IFS=. read -r major minor patch <<< "${latest#v}"
major="${major:-0}"; minor="${minor:-0}"; patch="${patch:-0}"

case "$part" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
esac

new="v${major}.${minor}.${patch}"

if git rev-parse -q --verify "refs/tags/$new" >/dev/null; then
  echo "!! tag $new already exists" >&2
  exit 1
fi

git tag -a "$new" -m "Release $new"
echo "==> Tagged $new (was $latest) at $(git rev-parse --short HEAD)"
echo "    Push it:   git push origin $new"
echo "    Build it:  make app   # bakes $new + commit hash into the .app"
