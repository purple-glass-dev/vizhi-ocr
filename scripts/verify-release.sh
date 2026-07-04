#!/usr/bin/env bash
#
# Verifies a signed/notarized VizhiOCR build: code signature, hardened runtime, notarization
# stapling, and Gatekeeper assessment. Also prints the manual zero-network (privacy) checklist.
#
# Usage:
#   scripts/verify-release.sh [path/to/VizhiOCR.app] [path/to/VizhiOCR.dmg]
#   (defaults to dist/VizhiOCR.app and the newest dist/*.dmg)
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-dist/VizhiOCR.app}"
DMG="${2:-$(ls -t dist/*.dmg 2>/dev/null | head -1 || true)}"

fail=0
check() { # check "<label>" <cmd...>
  local label="$1"; shift
  if "$@" > /tmp/vizhi-verify.out 2>&1; then
    echo "  ✓ $label"
  else
    echo "  ✗ $label"; sed 's/^/      /' /tmp/vizhi-verify.out; fail=1
  fi
}

echo "==> App: $APP"
[ -d "$APP" ] || { echo "!! app not found"; exit 1; }

check "code signature valid (strict, nested)" codesign --verify --deep --strict --verbose=2 "$APP"

# Hardened runtime must be on (CodeDirectory flags include 'runtime').
# Capture first, then grep: piping directly into `grep -q` lets grep close the pipe on the first
# match, codesign dies with SIGPIPE, and `set -o pipefail` turns that into a false failure.
sig_info="$(codesign -d --verbose=2 "$APP" 2>&1 || true)"
if printf '%s' "$sig_info" | grep -q "flags=.*runtime"; then
  echo "  ✓ hardened runtime enabled"
else
  echo "  ✗ hardened runtime NOT enabled"; fail=1
fi

# disable-library-validation present (needed for MLX's runtime-compiled CPU kernels).
entitlements="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
if printf '%s' "$entitlements" | grep -q "disable-library-validation"; then
  echo "  ✓ disable-library-validation entitlement present"
else
  echo "  ⚠ disable-library-validation NOT present — AI capture may crash under hardened runtime"
fi

check "notarization ticket stapled (app)" xcrun stapler validate "$APP"
check "Gatekeeper accepts the app" spctl --assess --type execute --verbose=4 "$APP"

if [ -n "${DMG:-}" ] && [ -f "$DMG" ]; then
  echo "==> DMG: $DMG"
  check "DMG signature valid" codesign --verify --verbose=2 "$DMG"
  check "notarization ticket stapled (dmg)" xcrun stapler validate "$DMG"
else
  echo "==> DMG: (none found — skipping DMG checks)"
fi

echo
echo "==> Zero-network (privacy) check — MANUAL, do this once per release:"
cat <<'CHECKLIST'
  1. Fresh Mac/user (or delete ~/Library/Application Support/VizhiOCR/Models).
  2. Launch the app, download one model in Manage Models (the ONLY allowed network use).
  3. Go fully offline: Airplane Mode, or Network Link Conditioner at 100% loss, or pull the cable.
     (Optionally run Little Snitch / `nettop` to watch for outbound connections.)
  4. Confirm BOTH engines still work offline:
       - Fast (Vision) capture  -> text on clipboard
       - AI capture with the downloaded model -> Markdown on clipboard
  5. Confirm NO outbound connection occurs during capture/inference.
  A release passes only if inference is fully functional with zero network traffic.
CHECKLIST

[ "$fail" -eq 0 ] && echo && echo "==> Automated checks passed." || { echo; echo "!! Some checks failed."; exit 1; }
