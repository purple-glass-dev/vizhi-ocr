import Foundation
import Observation
import os
import VizhiCore
import VizhiMLX
import VizhiModels
import VizhiVision

/// Drives a single recognition: picks the engine for the requested mode, runs it, falls back to
/// Vision if the AI engine isn't available, and copies the result to the clipboard. This is the
/// composition-root "brain" referenced in docs/DESIGN.md; it depends on the concrete engines so
/// VizhiCore can stay engine-agnostic.
@MainActor
@Observable
final class CaptureController {
    enum Status: Equatable {
        case idle
        case working
        case loadingModel(fraction: Double)
        case recognizing(page: Int, pageCount: Int, tokens: Int)
        case finished(blocks: Int, engine: String, destination: OutputDestination, savedTo: URL?)
        case failed(String)
    }

    private(set) var status: Status = .idle

    /// Diagnostics channel. The interesting line is the warning logged when an AI capture fails and
    /// silently retries with Apple Vision — that's how a model issue surfaces without crashing the
    /// capture. Read it with: `log stream --predicate 'subsystem == "com.vizhi.ocr"'`.
    private static let logger = Logger(subsystem: "com.vizhi.ocr", category: "capture")

    /// A user-facing capture update for the floating HUD: an in-progress state (amber, persistent)
    /// that resolves to success (green) or failure (red), an informational note (blue), or a
    /// cancellation that just dismisses it.
    struct CaptureNotice: Equatable {
        enum Kind: Equatable { case working, success, failure, info, cancelled }
        let kind: Kind
        let message: String
    }

    /// Fired as a capture starts and again when it finishes, so the app can show/keep/resolve a
    /// floating HUD — the only feedback a hotkey capture gets, since its menubar popover is closed.
    @ObservationIgnored var onNotice: ((CaptureNotice) -> Void)?

    /// Fired when an AI capture needs a model that isn't downloaded yet, so the app can open the
    /// Model Manager and start the download there (with progress) instead of a silent inline fetch.
    @ObservationIgnored var onNeedsModelDownload: ((ModelDescriptor) -> Void)?

    /// Fired when a finished result is held for the user to review/edit (preview-before-copy is on),
    /// so the app can open the preview window. The result waits in `pendingPreview`.
    @ObservationIgnored var onPreview: (() -> Void)?

    /// A recognized result awaiting review in the editable preview, before it's copied/saved.
    /// Non-nil only while the preview window is showing this result.
    struct PreviewResult {
        /// Identifies this particular result so the preview view can reset its editor when a new
        /// capture replaces the one on screen.
        let token = UUID()
        let document: OCRDocument
        /// The source page crops (every page of an imported PDF, or the single screen region),
        /// shown alongside the text so a misread is easy to spot.
        let images: [OCRImage]
        let engine: String
    }

    private(set) var pendingPreview: PreviewResult?

    private func notify(_ kind: CaptureNotice.Kind, _ message: String) {
        onNotice?(CaptureNotice(kind: kind, message: message))
    }

    /// Live text streamed from the AI model during recognition, for a real-time preview.
    private(set) var streamedText: String = ""

    /// Current page being recognized (1-based) and total pages, for multipage progress.
    @ObservationIgnored private var currentPage = 0
    @ObservationIgnored private var pageCount = 0

    /// The in-flight recognition, so it can be cancelled (Stop button / new capture).
    @ObservationIgnored private var activeTask: Task<Void, Never>?

    /// True while a capture is loading a model or recognizing — used to show a Stop control.
    var isBusy: Bool {
        switch status {
        case .working, .loadingModel, .recognizing: true
        case .idle, .finished, .failed: false
        }
    }

    /// Progress label for the recognizing state, including page count for multipage inputs.
    static func recognizingLabel(page: Int, pageCount: Int, tokens: Int) -> String {
        let pagePart = pageCount > 1 ? "Page \(page)/\(pageCount) · " : ""
        return "\(pagePart)Recognizing… \(tokens) tokens"
    }

    /// Human-readable summary of a finished recognition for the status UI.
    static func finishedMessage(blocks: Int, engine: String, destination: OutputDestination, savedTo: URL?) -> String {
        let count = "\(blocks) block\(blocks == 1 ? "" : "s")"
        switch destination {
        case .clipboard:
            return "Copied \(count) via \(engine)"
        case .file:
            return "Saved \(count) to \(savedTo?.lastPathComponent ?? "file")"
        case .both:
            return "Copied \(count) · saved \(savedTo?.lastPathComponent ?? "file")"
        }
    }

    /// Surfaces a non-recognition failure (e.g. a screen-capture error) through the same status
    /// channel the UI already observes.
    func report(failure message: String) {
        status = .failed(message)
        notify(.failure, message)
    }

    /// Marks the start of a capture so the menubar shows progress before pixels arrive.
    func beginWorking() {
        status = .working
        notify(.working, "Recognizing…")
    }

    private let settings: SettingsContext
    private let catalog: ModelCatalog
    private let store: ModelStore
    private let history: HistoryRecording?

    init(
        settings: SettingsContext,
        history: HistoryRecording? = nil,
        catalog: ModelCatalog = .bundled(),
        store: ModelStore = ModelStore()
    ) {
        self.settings = settings
        self.history = history
        self.catalog = catalog
        self.store = store
    }

    /// Starts recognizing a set of images (one for a screenshot; many for a PDF), cancelling any
    /// in-flight capture first. Owns the Task so `cancel()` can abort it. `hint` is an optional
    /// per-document note appended to the AI instruction.
    func recognize(_ images: [OCRImage], mode: CaptureMode, hint: String? = nil) {
        guard !images.isEmpty else { return }
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.recognizeAndCopy(images, mode: mode, hint: hint)
        }
    }

    /// Aborts the in-flight recognition, if any. Returns the UI to idle.
    func cancel() {
        activeTask?.cancel()
    }

    /// Recognizes a multi-page set of images and copies a single combined document to the clipboard.
    private func recognizeAndCopy(_ images: [OCRImage], mode: CaptureMode, hint: String?) async {
        guard !images.isEmpty else { return }

        // Fresh app, first AI capture: if the chosen model isn't downloaded, hand off to the Model
        // Manager (download + progress there) rather than fetching silently during inference.
        if mode == .ai,
           let model = catalog.activeModel(selectedID: settings.selectedModelID),
           !modelIsInstalled(model) {
            onNeedsModelDownload?(model)
            status = .idle
            notify(.info, "Downloading \(model.displayName)… watch progress in Manage Models, then capture again.")
            return
        }

        status = .working
        streamedText = ""
        pageCount = images.count
        notify(.working, "Recognizing…")
        do {
            try Task.checkCancellation()
            let resolved = engine(for: mode, hint: hint)
            var blocks: [Block] = []
            // The engines that actually produced text. Usually one; can include "vision" when an AI
            // capture fell back. Insertion-ordered so the label matches the order pages were read.
            var enginesUsed: [String] = []
            var fellBackToVision = false
            for (index, image) in images.enumerated() {
                try Task.checkCancellation()
                currentPage = index + 1
                let page = try await recognizeOne(
                    image,
                    requested: resolved.engine,
                    allowVisionFallback: resolved.allowVisionFallback
                )
                blocks.append(contentsOf: page.document.blocks)
                if !enginesUsed.contains(page.engineIdentifier) { enginesUsed.append(page.engineIdentifier) }
                if page.fellBack { fellBackToVision = true }
            }
            // Label the result with the engine that actually ran, not the one we asked for — so a
            // silent Vision fallback can never masquerade as the AI model the user chose.
            let actualEngine = enginesUsed.joined(separator: "+")
            let combined = OCRDocument(blocks: blocks, metadata: .init(engine: actualEngine))
            let fallbackNote = fellBackToVision
                ? "\(resolved.engine.identifier) couldn't run — used Apple Vision instead. "
                : nil

            // Preview-before-copy: hold the result for the user to review/edit instead of copying
            // it straight away. The preview window commits (or discards) it.
            if settings.previewBeforeCopy {
                pendingPreview = PreviewResult(
                    document: combined,
                    images: images,
                    engine: actualEngine
                )
                status = .idle
                onPreview?()
                notify(fellBackToVision ? .failure : .info, "\(fallbackNote ?? "")Review your result, then copy.")
                return
            }

            let savedTo = try OutputWriter.write(
                combined,
                format: settings.outputFormat,
                destination: settings.outputDestination,
                folder: settings.saveFolderURL
            )
            recordAndFinish(
                blocks: combined.blocks.count,
                engine: actualEngine,
                savedTo: savedTo,
                historyText: MarkdownRenderer().render(combined),
                note: fallbackNote
            )
        } catch is CancellationError {
            // User aborted — return to idle and dismiss the HUD.
            streamedText = ""
            status = .idle
            notify(.cancelled, "")
        } catch {
            let message = Self.userFacingMessage(for: error)
            status = .failed(message)
            notify(.failure, message)
        }
    }

    /// Commits the previewed result — writing the user's (possibly edited) text to the configured
    /// destination in the chosen format, recording history, and resolving the HUD. No-op if there's
    /// nothing pending.
    func commitPreview(text: String, format: OutputFormat) {
        guard let preview = pendingPreview else { return }
        pendingPreview = nil
        do {
            let savedTo = try OutputWriter.writeText(
                text,
                format: format,
                destination: settings.outputDestination,
                folder: settings.saveFolderURL
            )
            recordAndFinish(
                blocks: preview.document.blocks.count,
                engine: preview.engine,
                savedTo: savedTo,
                historyText: text
            )
        } catch {
            let message = Self.userFacingMessage(for: error)
            status = .failed(message)
            notify(.failure, message)
        }
    }

    /// Discards the previewed result without copying or saving anything.
    func discardPreview() {
        pendingPreview = nil
        status = .idle
        notify(.cancelled, "")
    }

    /// Shared tail for a delivered result: record history (if enabled), set the finished status, and
    /// resolve the HUD with a success notice.
    private func recordAndFinish(blocks: Int, engine: String, savedTo: URL?, historyText: String, note: String? = nil) {
        if settings.historyEnabled {
            history?.add(HistoryEntry(engine: engine, text: historyText))
        }
        let destination = settings.outputDestination
        let message = (note ?? "") + Self.finishedMessage(blocks: blocks, engine: engine, destination: destination, savedTo: savedTo)
        status = .finished(blocks: blocks, engine: engine, destination: destination, savedTo: savedTo)
        // A fallback still copied text, but the user's chosen model didn't run — flag it red, not green.
        notify(note == nil ? .success : .failure, message)
    }

    /// Maps an error to plain-language text with a recovery hint, instead of dumping a raw debug
    /// string. Known engine failures get specific guidance; anything else gets a safe fallback.
    static func userFacingMessage(for error: Error) -> String {
        if let mlx = error as? MLXEngineError {
            switch mlx {
            case .modelNotInstalled:
                return "That AI model isn't downloaded yet. Open Manage Models to get it, or use Fast mode."
            }
        }
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return "Recognition failed. Please try again, or switch to Fast mode."
    }

    /// Whether the model's files are present in our managed store (i.e. downloaded via Manage Models).
    private func modelIsInstalled(_ model: ModelDescriptor) -> Bool {
        if case .installed = store.installState(for: model) { return true }
        return false
    }

    /// Resolves the engine for a mode. `allowVisionFallback` is true only for the AI engine, so a
    /// failed MLX run can retry with Vision (and Vision never falls back to itself).
    private func engine(for mode: CaptureMode, hint: String?) -> (engine: OCREngine, allowVisionFallback: Bool) {
        switch mode {
        case .fast:
            return (VisionOCREngine(), false)
        case .ai:
            // Use the user's selected model if any, otherwise the catalog's default OCR model.
            // If it's been downloaded (Manage Models), MLX loads from disk; otherwise MLX
            // downloads it on demand and progress flows to the UI. No model at all → Vision.
            guard let model = catalog.activeModel(selectedID: settings.selectedModelID) else {
                return (VisionOCREngine(), false)
            }
            let engine = MLXOCREngine(
                model: model,
                modelDirectory: store.directory(for: model),
                userHint: hint,
                onLoadProgress: { [weak self] fraction in
                    Task { @MainActor in self?.status = .loadingModel(fraction: fraction) }
                },
                onStream: { [weak self] tokens, text in
                    Task { @MainActor in
                        guard let self else { return }
                        self.status = .recognizing(page: self.currentPage, pageCount: self.pageCount, tokens: tokens)
                        self.streamedText = text
                    }
                }
            )
            return (engine, true)
        }
    }

    /// One page's result, tagged with the engine that actually produced it so a Vision fallback is
    /// never reported as the AI model the user asked for.
    private struct RecognizedPage {
        let document: OCRDocument
        /// Identifier of the engine that actually ran (Vision's id when the AI engine fell back).
        let engineIdentifier: String
        /// True when the requested AI engine failed and Vision produced this page instead.
        let fellBack: Bool
    }

    /// Recognizes one image with the requested engine; on AI-engine failure, retries with Vision so
    /// the user still gets a result — but logs the real error and tags the page as a fallback so the
    /// substitution is visible rather than silent. A user cancellation is re-thrown, never masked by
    /// a Vision retry.
    private func recognizeOne(
        _ image: OCRImage,
        requested engine: OCREngine,
        allowVisionFallback: Bool
    ) async throws -> RecognizedPage {
        do {
            let document = try await engine.recognize(image)
            return RecognizedPage(document: document, engineIdentifier: engine.identifier, fellBack: false)
        } catch is CancellationError {
            throw CancellationError()   // user aborted — must cancel, not silently run Vision instead
        } catch {
            guard allowVisionFallback else { throw error }
            // This is the line that explains your symptom: the AI model threw, so we fell back to
            // Apple Vision (instant, no model resident). The real reason rides along here.
            Self.logger.warning(
                "AI engine \(engine.identifier, privacy: .public) failed; falling back to Apple Vision. Reason: \(String(describing: error), privacy: .public)"
            )
            let vision = VisionOCREngine()
            let document = try await vision.recognize(image)
            return RecognizedPage(document: document, engineIdentifier: vision.identifier, fellBack: true)
        }
    }
}

/// The slice of settings the controller needs. Backed by `SettingsStore` in the app; a plain
/// value keeps the controller decoupled from the UI layer.
@MainActor
protocol SettingsContext: AnyObject {
    var outputFormat: OutputFormat { get }
    var selectedModelID: String? { get }
    var outputDestination: OutputDestination { get }
    var saveFolderURL: URL { get }
    var historyEnabled: Bool { get }
    var previewBeforeCopy: Bool { get }
}

/// Records finished captures into local history. Implemented by `CaptureHistoryStore`; abstracted so
/// the controller stays decoupled from the UI layer.
@MainActor
protocol HistoryRecording: AnyObject {
    func add(_ entry: HistoryEntry)
}

