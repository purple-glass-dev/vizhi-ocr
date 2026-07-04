#!/usr/bin/env bash
#
# Generates assets/AppIcon.icns from scripts/make-icon.swift. Run this whenever the icon art
# changes; build-app.sh bundles the committed .icns, so you don't need to run it every build.
#
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER="$(mktemp -t vizhi-icon).png"
ICONSET="$(mktemp -d -t vizhi-iconset).iconset"
mkdir -p assets "$ICONSET"

echo "==> Rendering 1024px master…"
swift scripts/make-icon.swift "$MASTER"

echo "==> Slicing into an .iconset…"
# size  iconset-name (Apple's required set: 16–512 at @1x and @2x)
while read -r px name; do
  [ -z "$px" ] && continue
  sips -z "$px" "$px" "$MASTER" --out "$ICONSET/icon_$name.png" >/dev/null
done <<'SIZES'
16 16x16
32 16x16@2x
32 32x32
64 32x32@2x
128 128x128
256 128x128@2x
256 256x256
512 256x256@2x
512 512x512
1024 512x512@2x
SIZES

echo "==> Building assets/AppIcon.icns…"
iconutil -c icns "$ICONSET" -o assets/AppIcon.icns

rm -rf "$MASTER" "$ICONSET"
echo "==> Done: assets/AppIcon.icns"
