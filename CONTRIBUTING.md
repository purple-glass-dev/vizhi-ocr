# Contributing to Vizhi OCR

First off — thank you. Vizhi OCR is an on-device, privacy-first OCR utility for macOS, and it
gets better when people who care about that mission pitch in. This guide covers how to get
set up, what we expect in a change, and how to get it merged. 

**Background**: I am a student, with access to only a M1 Macbook Air (8 GB) and will not be able to 
test large OCR models effectively on my machine. Also, this project started with my need to transcribe my handwritten notes (written in Noteshelf 2) to markdown (including tables and formulas). This project would not have happened if GLM-OCR hadn't worked so wonderfully. I am just providing a user friendly frontend because I use it everyday and also wanted to learn Swift/Swift UI/Swift 6 Concurrency. I am not looking for any feature that is overly complicated. However, I am glad to discuss your specific use case.


## The one rule that matters most

**Vizhi is on-device only.** No telemetry, no analytics, no crash reporters that phone home,
no network calls at inference time. The *only* permitted network access is the one-time model
download (and optional, user-disableable update checks). If your change adds any other network
dependency — stop, and open an issue to discuss it first. This isn't a style preference; it's
the product.

Anything that touches **network, storage, or permissions** must update
[`docs/PRIVACY.md`](docs/PRIVACY.md) in the same change. Privacy claims are load-bearing.

---

## Prerequisites

- A **Mac with Apple Silicon** (M1 or later) running **macOS 15 (Sequoia) or newer**. Vizhi
  is Apple-Silicon- and Sequoia-only by design — please don't add Intel or pre-15 shims.
- **Xcode 16+** and its command-line tools (`xcode-select --install`). Xcode is required for
  any work touching the **AI (MLX) path** — see the note below.
- **Swift 6** toolchain (ships with Xcode 16).

---

## Getting set up

```sh
git clone https://github.com/<your-fork>/vizhi-ocr.git
cd vizhi-ocr
swift build          # builds the whole local package graph
```

To run the app during development:

```sh
swift run VizhiOCR   # Fast (Apple Vision) mode works fully here
```

### ⚠️ The MLX / Xcode gotcha — read this

`swift build` and `swift run` **do not** compile MLX's Metal shader library
(`default.metallib`). The Fast/Vision path runs fine under `swift run`, but the **AI (MLX)**
path will crash with *"Failed to load the default metallib."*

To run or test the AI path, you must use Xcode's build system:

```sh
make app                 # -> dist/VizhiOCR.app (uses xcodebuild, bundles the metallib)
open dist/VizhiOCR.app
```

…or open `Package.swift` in Xcode and run the `VizhiOCR` scheme directly. There's no way
around this — it's a constraint of how MLX compiles its Metal kernels.

---

## Project layout in 30 seconds

Vizhi is a Swift 6 SwiftPM workspace: a thin app target composing focused local packages.

| Module | Responsibility |
|---|---|
| `Sources/VizhiOCR` (app) | Menubar/lifecycle, `AppServices` wiring, `CaptureController` (engine selection + fallback + output), result preview |
| `Packages/VizhiCore` | Domain models, the `OCREngine` protocol, output formats + pure renderers — engine-agnostic, imports nothing upward |
| `Packages/VizhiCapture` | ScreenCaptureKit capture, region geometry, Carbon global hotkeys |
| `Packages/VizhiVision` | Apple Vision fast-mode OCR + reading-order reconstruction |
| `Packages/VizhiMLX` | MLX VLM inference and the parser turning model output back into an `OCRDocument` |
| `Packages/VizhiModels` | Model catalog, RAM-tiering, download manager (HF + CDN fallback) |
| `Packages/VizhiUI` | SwiftUI surfaces: menubar, settings, model manager, import window |

**Dependency direction:** the app composes everything; `VizhiCore` is the engine-agnostic
core; lower packages never import `VizhiUI`.

---

## Coding conventions

- **Swift 6 strict concurrency.** Inference runs off the main actor; UI updates hop back to
  `@MainActor`. Never block the main thread on model load or OCR.
- **No force-unwraps** in non-test code. Model and capture failures are *expected* paths —
  surface them as typed errors with a user-facing recovery, not a crash.
- **Rendering** (`OCRDocument` → Markdown / text / CSV / JSON) lives in `VizhiCore`;
  **parsing** model output back into an `OCRDocument` lives in `VizhiMLX`. Both are pure and
  unit-tested, and neither depends on UI.
- **Model identifiers** are centralized in the `VizhiModels` catalog. Never hardcode a
  Hugging Face repo or download URL anywhere else.
- **Comments** are sparse — only where intent isn't obvious.
- **Keep diffs focused.** Don't reformat unrelated code or churn imports.

---

## Testing

We use **Swift Testing** (`import Testing`, `@Test`) — not XCTest — for new tests.

Tests live per package (the root package is just the executable), so run them per package:

```sh
# one package
(cd Packages/VizhiCore && swift test)

# all of them
for p in VizhiCore VizhiModels VizhiVision VizhiMLX VizhiCapture VizhiUI VizhiBench; do
  (cd "Packages/$p" && swift test) || break
done
```

New logic needs test coverage. The pure pieces — renderers (`VizhiCore`), the Markdown/HTML
parser (`VizhiMLX`), region geometry (`VizhiCapture`), Vision layout reconstruction, and the
model RAM-tiering/download logic (`VizhiModels`) — are all unit-testable without a GUI, so
there's rarely an excuse to skip a test for them.

OCR-quality work can be measured with the benchmark harness (*TODO*: This is rudimentary at this point, need more samples..May be accept contributions here):

```sh
scripts/benchmark.sh
```

---

## Making a change

1. **Open an issue first** for anything non-trivial — a new feature, a behavior change, a new
   model, or anything touching the privacy/permissions surface. It saves you from building
   something that conflicts with a hard constraint or the roadmap.
2. **Branch** off `main` with a short, descriptive name (`fix/pdf-page-order`,
   `feat/csv-export`).
3. **Make the change**, keeping the diff tight and the conventions above.
4. **Update the docs that travel with the code** — this is part of "done", not a follow-up:
   - New Features or breaking changes - README.md
   - New or changed model → [`docs/MODELS.md`](docs/MODELS.md)
   - Anything touching network/storage/permissions → [`docs/PRIVACY.md`](docs/PRIVACY.md)
5. **Run the tests** and make sure the build is clean.

### Definition of done

A change is ready when it:

- Builds clean.
- Passes the test suite (`swift test` across the packages).
- Has Swift Testing coverage for any new logic.
- Adds **no new network or storage surface** without a matching `docs/PRIVACY.md` update.
- Keeps the relevant design/requirements/model docs in sync.

---

## Commits & pull requests

- Write clear, present-tense commit messages explaining *why*, not just *what*.
- Keep PRs focused on a single concern; split unrelated changes.
- In the PR description, note: what changed, why, how you tested it, and **whether it touches
  the network/storage/permissions surface** (and the doc update if so).
- Include before/after screenshots or a short clip for any UI change.
- Expect review feedback — Vizhi has tight constraints, and most back-and-forth is about
  keeping the privacy and on-device guarantees airtight.

---

## Reporting bugs & requesting features

Open a GitHub issue. For bugs, please include:

- Your **Mac model and chip** (e.g. M1 Macbook Air) and **macOS version**.
- The Vizhi **version and commit** — both are shown right in the menubar.
- Which **mode** (Fast / AI) and, for AI mode, **which model**.
- Steps to reproduce, and what you expected vs. what happened.
- A sample image/PDF if the OCR output is wrong — but **only if it contains nothing private**.
  Never attach anything sensitive; describe it instead.

---

## Licensing

Vizhi uses a split structure (see the README's *Licensing* section for the full explanation):

- **All source code and assets** in this repository are licensed under the
  **GNU General Public License v3.0** (see [`LICENSE.md`](LICENSE.md)). By contributing, you
  agree your contributions are licensed under GPL-3.0, and any fork or redistribution must
  also be fully open-sourced under the same license.
- The **official pre-compiled binaries** (`.dmg`) distributed via Releases/website are covered
  by a separate Terms of Service and may not be commercially repackaged or resold outside this
  official repository.

If you're not comfortable contributing under GPL-3.0, please don't submit a PR.

---

Thanks again for helping make a fast, private, genuinely good OCR tool for the Mac.
