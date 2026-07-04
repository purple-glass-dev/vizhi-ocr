#!/usr/bin/env bash
#
# Produces a signed-but-NOT-notarized VizhiOCR.dmg for self-install / manual approval.
#
# This is notarize.sh minus the two Apple round-trips (notarytool submit + stapler). The app is
# still signed with hardened runtime + the MLX entitlement, so the AI engine works; it just isn't
# notarized. On first launch Gatekeeper will say it "cannot be checked for malicious software" —
# approve it once via System Settings ▸ Privacy & Security ▸ Open Anyway, or right-click ▸ Open.
#
# Signing identity:
#   - Auto-detects a "Developer ID Application" cert if present (best: only an "unverified
#     developer" prompt, overridable). Set SIGN_IDENTITY to override / pick among multiple.
#   - Falls back to ad-hoc ("-") if no Developer ID cert is found — fine for your own machine;
#     on other Macs run `xattr -dr com.apple.quarantine /Applications/VizhiOCR.app` after copying.
#
# Usage:
#   scripts/build-dmg.sh
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="VizhiOCR"
VERSION="${VERSION:-$("$PWD/scripts/version.sh")}"   # latest git tag; see scripts/version.sh
VOLNAME="Vizhi OCR"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

DIST="$PWD/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGE="$DIST/dmg-stage"

# --- Pick a signing identity -------------------------------------------------
if [ -z "$SIGN_IDENTITY" ] || [ "$SIGN_IDENTITY" = "-" ]; then
  ids="$(security find-identity -v -p codesigning | grep 'Developer ID Application' || true)"
  count="$(printf '%s\n' "$ids" | grep -c 'Developer ID Application' || true)"
  if [ "$count" -eq 1 ]; then
    SIGN_IDENTITY="$(printf '%s\n' "$ids" | awk '{print $2}')"   # SHA-1 hash
    echo "==> Signing with Developer ID:$(printf '%s' "$ids" | sed 's/.*) //')"
  elif [ "$count" -gt 1 ]; then
    echo "!! Multiple Developer ID Application identities — set SIGN_IDENTITY to pick one:" >&2
    printf '%s\n' "$ids" | sed 's/^/     /' >&2
    exit 1
  else
    SIGN_IDENTITY="-"
    echo "==> No Developer ID cert found — signing ad-hoc (self-install only)."
  fi
fi

# --- 1. Build & sign the .app ------------------------------------------------
SIGN_IDENTITY="$SIGN_IDENTITY" VERSION="$VERSION" scripts/build-app.sh

# --- 2. Build the DMG --------------------------------------------------------
echo "==> Building the DMG…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

# --- 3. Sign the DMG (skip if ad-hoc — no benefit) ---------------------------
if [ "$SIGN_IDENTITY" != "-" ]; then
  echo "==> Signing the DMG…"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

echo "==> Done (NOT notarized): $DMG"
echo "    First launch: right-click the app ▸ Open, or System Settings ▸ Privacy & Security ▸ Open Anyway."
