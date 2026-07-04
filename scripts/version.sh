#!/usr/bin/env bash
#
# Single source of truth for the app's version string: the latest `vX.Y.Z` git tag with the leading
# `v` stripped (e.g. "0.1.2"). Bump it with `make bump-patch|bump-minor|bump-major`.
#
# build-app.sh, build-dmg.sh, and notarize.sh all read this, so the menu, console output, and DMG
# filename always agree. Override by exporting VERSION before invoking those scripts.
set -euo pipefail
cd "$(dirname "$0")/.."
git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null | sed 's/^v//' || echo 0.1.0
