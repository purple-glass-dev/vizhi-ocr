#!/usr/bin/env bash
#
# Downloads established public OCR benchmarks into benchmarks/external/ (gitignored) for local
# evaluation. These are NOT committed and NOT bundled in the app — they're third-party data with
# their own licenses (see benchmarks/corpus/README.md). In particular OmniDocBench is research-only
# / non-commercial; review each dataset's license before using results publicly.
#
# Their ground truth is in their own formats (HTML tables, KaTeX math, JSON) — converting a subset
# into our <name>.expected.md convention is a manual import step; this just fetches the raw data.
#
# Requires the HuggingFace CLI:  pip install -U "huggingface_hub[cli]"
#
# Usage:
#   scripts/fetch-bench-corpus.sh olmocr        # allenai/olmOCR-bench
#   scripts/fetch-bench-corpus.sh omnidocbench  # opendatalab/OmniDocBench (non-commercial)
#   scripts/fetch-bench-corpus.sh getomni       # getomni-ai/ocr-benchmark (MIT)
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="benchmarks/external"
mkdir -p "$DEST"

if ! command -v huggingface-cli >/dev/null 2>&1; then
  echo "!! huggingface-cli not found. Install with: pip install -U \"huggingface_hub[cli]\"" >&2
  exit 1
fi

case "${1:-}" in
  olmocr)       REPO="allenai/olmOCR-bench" ;;
  omnidocbench) REPO="opendatalab/OmniDocBench"
                echo "NOTE: OmniDocBench is Apache-2.0 but research-only / non-commercial." ;;
  getomni)      REPO="getomni-ai/ocr-benchmark" ;;
  *) echo "usage: $0 {olmocr|omnidocbench|getomni}" >&2; exit 2 ;;
esac

echo "==> Downloading $REPO into $DEST/$1 …"
huggingface-cli download "$REPO" --repo-type dataset --local-dir "$DEST/$1"
echo "==> Done. Raw data in $DEST/$1 — import a subset into benchmarks/corpus/ as <name>.expected.md."
