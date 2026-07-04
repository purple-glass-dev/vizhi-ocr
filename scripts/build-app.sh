#!/usr/bin/env bash
#
# Builds VizhiOCR.app — a double-clickable macOS app bundle.
#
# Why xcodebuild and not `swift build`? MLX's Metal kernels are compiled into a `default.metallib`
# only by Xcode's build system. `swift build`/`swift run` skip that step, so the AI (MLX) engine
# crashes at runtime with "Failed to load the default metallib". xcodebuild compiles it; this
# script then assembles the products into a proper .app where the metallib bundle is found.
#
# Usage:
#   scripts/build-app.sh                 # Release build -> dist/VizhiOCR.app
#   CONFIG=Debug scripts/build-app.sh    # faster Debug build
#   SIGN_IDENTITY="Developer ID Application: You (TEAMID)" scripts/build-app.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="VizhiOCR"
APP_NAME="VizhiOCR"
BUNDLE_ID="${BUNDLE_ID:-com.vizhi.ocr}"
# Version comes from the latest `vX.Y.Z` git tag (set via `make bump-*`); the short commit hash is
# baked in too, so the running app can show "v0.1.2 (abc1234)" in its menu.
VERSION="${VERSION:-$("$PWD/scripts/version.sh")}"
GIT_COMMIT="${GIT_COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}"
MIN_MACOS="15.0"
CONFIG="${CONFIG:-Release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" = ad-hoc; set to a Developer ID for distribution.
ENTITLEMENTS="$PWD/scripts/entitlements.plist"

DERIVED="$PWD/build/xcode"
DIST="$PWD/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building $SCHEME $VERSION ($GIT_COMMIT, $CONFIG) with xcodebuild (compiles the Metal library)…"
xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  build | tail -1

PRODUCTS="$DERIVED/Build/Products/$CONFIG"
EXE="$PRODUCTS/$APP_NAME"
[ -x "$EXE" ] || { echo "!! executable not found at $EXE"; exit 1; }

echo "==> Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXE" "$APP/Contents/MacOS/$APP_NAME"

# Copy SwiftPM resource bundles (incl. mlx-swift_Cmlx.bundle, which holds default.metallib).
shopt -s nullglob
bundles=("$PRODUCTS"/*.bundle)
if [ ${#bundles[@]} -eq 0 ]; then
  echo "!! no resource bundles found in $PRODUCTS (metallib would be missing)"; exit 1
fi
for bundle in "${bundles[@]}"; do
  cp -R "$bundle" "$APP/Contents/Resources/"
  echo "    + $(basename "$bundle")"
done

# Embed dynamic frameworks/dylibs if the build produced any. Release usually links the package
# graph statically (so this is a no-op), but handle the dynamic case so the .app stays
# self-contained and every Mach-O can be signed for notarization.
FW_SRC="$PRODUCTS/PackageFrameworks"
if [ -d "$FW_SRC" ] && compgen -G "$FW_SRC/*.framework" > /dev/null; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R "$FW_SRC"/*.framework "$APP/Contents/Frameworks/"
  echo "    embedded $(ls "$APP/Contents/Frameworks" | wc -l | tr -d ' ') framework(s)"
fi

# App icon (Finder, About box, DMG). Regenerate the art with scripts/make-icon.sh.
ICON="$PWD/assets/AppIcon.icns"
if [ -f "$ICON" ]; then
  cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
  echo "    + AppIcon.icns"
else
  echo "    (no assets/AppIcon.icns — run scripts/make-icon.sh; using a generic icon)"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>Vizhi OCR</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>VizhiGitCommit</key><string>$GIT_COMMIT</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>On-device OCR. Nothing is ever uploaded.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing ($SIGN_IDENTITY)…"
# Hardened runtime + entitlements for notarization. A secure timestamp needs a real cert, so it's
# only added for a Developer ID identity (ad-hoc "-" can't reach Apple's timestamp server).
sign_flags=(--force --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then sign_flags+=(--timestamp); fi

# Sign nested Mach-O inside-out (frameworks, dylibs, code-bearing bundles) before the outer app —
# the modern replacement for the deprecated `--deep`.
while IFS= read -r -d '' item; do
  # Resource-only bundles (no Mach-O) may not be independently signable; that's fine — the outer
  # app signature seals them. Code-bearing items (frameworks, dylibs) must sign, and if one can't,
  # notarization will flag it later with a precise message.
  if codesign "${sign_flags[@]}" "$item" 2>/dev/null; then
    echo "    signed $(basename "$item")"
  else
    echo "    (skipped $(basename "$item") — sealed by the app signature)"
  fi
done < <(find "$APP/Contents/Frameworks" "$APP/Contents/Resources" \
           \( -name '*.framework' -o -name '*.dylib' -o -name '*.bundle' \) -print0 2>/dev/null)

codesign "${sign_flags[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP" || true

echo "==> Done: $APP"
echo "    Run it:   open \"$APP\""
echo "    Note: first AI capture downloads the GLM-OCR model (~1.3 GB), then runs offline."
echo "    To produce a notarized DMG for distribution: scripts/notarize.sh"
