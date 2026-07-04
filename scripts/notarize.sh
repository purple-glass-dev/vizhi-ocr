#!/usr/bin/env bash
#
# Produces a notarized, stapled VizhiOCR.dmg for direct distribution.
#
# Pipeline: build & sign the .app (build-app.sh) -> notarize & staple the .app -> build a DMG ->
# sign, notarize, and staple the DMG -> verify. Stapling both the app and the DMG means Gatekeeper
# passes whether the user runs the app from the mounted image or after dragging it to /Applications,
# even offline.
#
# One-time setup (see docs/DISTRIBUTION.md):
#   1. A "Developer ID Application" certificate in your login keychain (Apple Developer account).
#   2. A notarytool keychain profile holding your App Store Connect credentials:
#        xcrun notarytool store-credentials vizhi-notary \
#          --apple-id "you@example.com" --team-id TEAMID --password <app-specific-password>
#
# Usage:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="vizhi-notary" \
#   scripts/notarize.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="VizhiOCR"
VERSION="${VERSION:-$("$PWD/scripts/version.sh")}"   # latest git tag; see scripts/version.sh
VOLNAME="Vizhi OCR"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

DIST="$PWD/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGE="$DIST/dmg-stage"

# --- Preflight ---------------------------------------------------------------
# Auto-detect the Developer ID Application identity from the keychain when SIGN_IDENTITY isn't set,
# so it never has to be hardcoded. We use the certificate's SHA-1 hash, which codesign accepts and
# which is unambiguous. Set SIGN_IDENTITY explicitly only to override (e.g. multiple certs).
if [ -z "$SIGN_IDENTITY" ] || [ "$SIGN_IDENTITY" = "-" ]; then
  ids="$(security find-identity -v -p codesigning | grep 'Developer ID Application' || true)"
  count="$(printf '%s\n' "$ids" | grep -c 'Developer ID Application' || true)"
  if [ -z "$ids" ] || [ "$count" -eq 0 ]; then
    echo "!! No 'Developer ID Application' identity found in the keychain." >&2
    echo "   Create one (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates), or set SIGN_IDENTITY." >&2
    exit 1
  fi
  if [ "$count" -gt 1 ]; then
    echo "!! Multiple Developer ID Application identities found — set SIGN_IDENTITY to pick one:" >&2
    printf '%s\n' "$ids" | sed 's/^/     /' >&2
    exit 1
  fi
  SIGN_IDENTITY="$(printf '%s\n' "$ids" | awk '{print $2}')"   # the SHA-1 hash
  echo "==> Auto-detected signing identity:$(printf '%s' "$ids" | sed 's/.*) //')"
fi
if [ -z "$NOTARY_PROFILE" ]; then
  echo "!! NOTARY_PROFILE must name a notarytool keychain profile (see header)." >&2
  exit 1
fi

# --- 1. Build & sign the .app ------------------------------------------------
echo "==> Building and signing the app…"
SIGN_IDENTITY="$SIGN_IDENTITY" VERSION="$VERSION" scripts/build-app.sh

# --- 2. Notarize & staple the .app ------------------------------------------
echo "==> Notarizing the app (this uploads the app to Apple and waits)…"
APP_ZIP="$DIST/$APP_NAME.zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$APP_ZIP"

# --- 3. Build the DMG (from the stapled app) --------------------------------
echo "==> Building the DMG…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

# --- 4. Sign, notarize & staple the DMG -------------------------------------
echo "==> Signing the DMG…"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

echo "==> Notarizing the DMG…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# --- 5. Verify ---------------------------------------------------------------
echo "==> Verifying…"
scripts/verify-release.sh "$APP" "$DMG"

# --- 6. Refresh the Homebrew cask (non-fatal) --------------------------------
# Regenerate the cask in the external tap so its version + sha256 match this DMG. A failure
# here must NOT fail the release — the notarized DMG is already built and verified above.
if [ "${SKIP_CASK:-0}" != "1" ]; then
  echo "==> Updating Homebrew cask…"
  VERSION="$VERSION" scripts/update-cask.sh "$DMG" \
    || echo "!! Cask update failed (non-fatal) — run scripts/update-cask.sh manually." >&2
fi

echo "==> Done: $DMG"
