# Vizhi OCR

**Screenshot any text on your screen or import any iamge/pdf file and get it back as clean, structured text. Tables, math, handwriting, the lot. All of it runs on your Mac, and nothing ever leaves the machine.**

Vizhi lives in your menubar. Hit a shortcut, drag a box around whatever you want to grab, and the text lands on your clipboard (saved as markdown or both!) a moment later. No browser tab, no upload, no account. If you've ever tried to copy text out of a PDF that won't let you select it, or retyped a table from a screenshot, or pointed your phone at a slide to capture an equation, this is the thing that makes all of that stop.

---
## How it works(Video demo)

<video src="https://github.com/user-attachments/assets/bed0875d-890e-4998-bb91-30539d59a28a" autoplay loop muted playsinline width="100%"></video>


## Why it exists

Most OCR tools fall into two camps. The fast ones are local but dumb: they hand you a wall of plain text with the table structure flattened and the layout scrambled. The smart ones understand tables and equations, but they do it by shipping your screenshot off to someone else's server.

Vizhi refuses that trade-off. It ships two engines and lets you pick per capture:

- **Fast mode** uses Apple's built-in Vision framework. Sub-second, no download, always available. Perfect for grabbing a line of text out of an app that won't let you select it.
- **AI mode** runs a real OCR vision model on Apple Silicon through MLX. It reads multi-column layouts, reconstructs tables, transcribes handwriting, and writes equations out as LaTeX. It downloads the model once (about 1.3 GB), and after that it works with your Wi-Fi switched off.

Either way, the image and the text stay on your Mac. There is no telemetry, no analytics, no crash reporting, no "anonymous usage data." The only time Vizhi touches the network is to download a model you explicitly asked for, and you can watch the progress  while it does.

---

## What you can do with it

**Grab text off the screen.** Press your shortcut, drag a selection box across any display, let go. The overlay dims everything else and shows you the pixel dimensions as you drag. Whatever was inside the box comes back as text.

**Import files instead.** Drop a PDF, PNG, JPEG, or a photo of a handwritten note onto the import window, or pick one through a file chooser. Multi-page PDFs are handled page by page, with progress as it goes. This path needs no Screen Recording permission at all, so if you'd rather not grant that, you lose nothing.

**Get real structure, not flattened text.** AI mode produces Markdown. A table in your screenshot comes back as a Markdown table you can paste straight into a doc. An equation comes back as LaTeX (`$$...$$`), ready to drop into a paper or a notebook. Multi-column academic PDFs read in the right order.

**Check it before it's yours.** Turn on "Preview & edit before copying" and every result opens in a review window first: the source image on one side, the recognized text on the other, side by side, every page of a PDF crop included. Fix a misread, then copy. The Markdown view has an Edit/Preview toggle that renders the formatting live and typesets the math, so you see exactly what you're about to paste.

**Send it where you want.** Clipboard, a saved Markdown file, or both. When a result contains a table, the preview also offers CSV and JSON export for that result, so a captured table can go straight into a spreadsheet or a script.

**Keep a history, or don't.** History is off by default. Switch it on and Vizhi keeps your recent captures locally for one-click re-copy. It lives in a file on your disk, never syncs anywhere, and "Clear All" deletes it for good.

---

## The models

AI mode is powered by purpose-built OCR vision models, not a general chatbot bolted onto an image input. Vizhi only ships models that were actually fine-tuned for document reading, because the general-purpose ones hallucinate text that was never on the page.

| Model | Size | Best at | RAM |
|---|---|---|---|
| **GLM-OCR (4-bit)** — *recommended default* | ~1.25 GB | The all-rounder. Strong on tables, math, and multi-column layouts at a modest memory footprint. | 8 GB min, 16 GB comfortable |
| **GLM-OCR (8-bit)** | ~1.6 GB | The same model at higher precision, for the cleanest tables and math when you have the RAM to spare. | 8 GB min, 16 GB comfortable |

The 4-bit GLM-OCR is the default because in practice it's as accurate as the 8-bit build on real documents, and often faster. The Model Manager reads your Mac's installed memory, only offers models that will actually fit, and flags the recommended one. You download, verify, switch, and delete models from there, with a live progress bar and a cancel button.

Once a model is loaded it stays resident so the next capture is instant, then releases itself after five minutes of inactivity (or immediately if the system comes under memory pressure). The menubar always tells you whether a model is currently in memory and which one.

---

## Keyboard shortcuts

Everything important has a global shortcut that works from any app:

| Action | Default |
|---|---|
| Capture Text (Fast) | `⌃⌥2` |
| Capture Text (AI) | `⌃⌥3` |
| Import File | `⌃⌥4` |

The defaults deliberately avoid macOS's own `⇧⌘3/4/5` screenshot keys. All three are rebindable in Settings with a click-to-record control, and there's a reset-to-defaults button if you paint yourself into a corner.

---

## Privacy, plainly

This is the part that actually matters, so here it is without the hand-waving:

- All OCR runs on your Mac's CPU, GPU, and Neural Engine. Captured images and recognized text never leave the device.
- There is no telemetry, no analytics, no remote crash reporting, no identifiers of any kind.
- The model catalog is bundled into the app. There are no update checks phoning home.
- The only network access is downloading a model you chose, from the configured Hugging Face repo (with a CDN mirror as fallback). After that, AI mode works fully offline. Fast mode never needs the network at all.

If you handle confidential contracts, medical records, unpublished research, or anything else that simply cannot be uploaded somewhere, that's the whole point of this app.

---

## Requirements

- **Apple Silicon Mac** (M1 or newer). The AI engine is built on MLX, which is Apple-Silicon-only.
- **macOS 15 (Sequoia)** or later.
- A few GB of free disk for whichever AI models you download. Fast mode needs none.
- Screen Recording permission for screen-region capture. (The import path works without it.)

---

## Install

Grab the latest `VizhiOCR.dmg` from Releases, open it, and drag the app to Applications.

The build is signed but distributed directly rather than through the App Store, so on first launch macOS may ask you to confirm. Right-click the app and choose **Open**, or approve it once under **System Settings ▸ Privacy & Security ▸ Open Anyway**. After that it launches normally and sits in your menubar.

---

## Building from source

Vizhi is a Swift 6 package split into focused modules (capture, Vision engine, MLX engine, model management, UI, and the shared document model). MLX's Metal kernels are only compiled by Xcode's build system, so the app is assembled with `xcodebuild` rather than `swift build`.

```sh
make app      # builds dist/VizhiOCR.app
make dmg      # builds a distributable DMG
make test     # runs the test suite
```

Versioning is driven by git tags. Bump with one of:

```sh
make bump-patch    # 0.1.2 -> 0.1.3
make bump-minor    # 0.1.2 -> 0.2.0
make bump-major    # 0.1.2 -> 1.0.0
```

Each bump creates an annotated `vX.Y.Z` tag locally (push it yourself). The build bakes the version and the short commit hash into the app, and you can read both straight off the menubar so you always know exactly what you're running.

---

## How it fits together

The capture flow is the same regardless of where the image comes from. A trigger (hotkey, menubar, or a dropped file) hands an image to the controller, which picks an engine, runs recognition, and parses the output into a single structured document model. That model then renders to whatever you asked for: Markdown, plain text, CSV, or JSON. Because both engines feed the same model and the same renderers, a table captured off the screen and a table imported from a PDF come out formatted identically.

If an AI model fails to load or run, the capture falls back to Fast mode automatically, so you always get something rather than an error — and the fallback is flagged (not silent), so you know Apple Vision produced that result instead of the AI model you picked.

## Licensing

This project uses a split structure to protect its distribution channels while remaining open-source friendly.

### Source Code & Assets
The entire contents of this repository—including all source code, icons, UI layouts, and graphic assets—are licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See the `LICENSE.md` file for the full license text.

If you choose to fork, modify, or redistribute this project, your derivative version **must** also be entirely open-sourced under the exact same GPL-3.0 license. 

### Pre-Compiled Binaries (`.dmg`)
Official pre-compiled binaries distributed via GitHub Releases are distributed under a separate **Terms of Service**. 

While the underlying code is open-source, the specific pre-packaged binary wrappers I build and distribute cannot be commercially redistributed, resold, or repackaged outside of this official repository. For details, you can access "Terms of Service" by clicking the link in application menu.
