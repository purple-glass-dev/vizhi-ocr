#!/usr/bin/env bash
#
# Runs the offline OCR quality benchmark.
#
# The benchmark lives *inside* the app binary (behind a --benchmark argument) because the MLX engine
# needs the Metal library that only the Xcode build bundles — a plain `swift run` can't load it.
# So this builds the .app (build-app.sh, which compiles + bundles the metallib) and invokes it.
#
# Usage:
#   scripts/benchmark.sh                              # all installed models + Apple Vision
#   scripts/benchmark.sh --models glm-ocr-4bit        # just one model
#   scripts/benchmark.sh --no-vision                  # MLX models only
#   CORPUS=path/to/corpus OUT=path/to/report.md scripts/benchmark.sh
#
# Models must already be downloaded via the app's Model Manager (the benchmark loads them offline);
# pass --models <id> to force a specific not-yet-installed model to download on first use.
set -euo pipefail
cd "$(dirname "$0")/.."

CORPUS="${CORPUS:-benchmarks/corpus}"
OUT="${OUT:-benchmarks/report.md}"
APP="dist/VizhiOCR.app/Contents/MacOS/VizhiOCR"

if [ ! -d "$CORPUS" ]; then
  echo "!! corpus not found at $CORPUS — add samples (see benchmarks/corpus/README.md)" >&2
  exit 1
fi

echo "==> Building the app (compiles + bundles the Metal library)…"
CONFIG="${CONFIG:-Release}" scripts/build-app.sh >/dev/null

echo "==> Running benchmark over $CORPUS …"
"$APP" --benchmark "$CORPUS" --out "$OUT" "$@"
