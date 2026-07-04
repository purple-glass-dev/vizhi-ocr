import SwiftUI
import VizhiCore
import VizhiMLX
import VizhiModels
import VizhiUI

/// The import window: drop a PDF/image, run OCR via the controller, copy Markdown. Works with no
/// Screen Recording permission. The engine picker chooses Fast (Apple Vision) or AI (the active
/// on-device model).
struct ImportWindowView: View {
    let settings: SettingsStore
    let controller: CaptureController
    @Bindable var residency: ModelResidency

    @State private var mode: CaptureMode = .fast
    /// Optional per-document hint the user can type to steer AI recognition.
    @State private var hint: String = ""
    /// Whether to show the result status/preview. True only once a file is handled in this window
    /// session, so reopening the window starts clean instead of showing the previous import's
    /// result (the controller's status/streamed text are long-lived and shared with the menubar).
    @State private var showsResult = false

    var body: some View {
        VStack(spacing: 12) {
            enginePicker
            if mode == .ai { hintField }
            ImportDropView(onDropFiles: handleDrop)
            controlRow
            statusLine
            preview
            residencyLine
        }
        .padding()
        .frame(minWidth: 420, minHeight: 420)
        .onAppear {
            mode = settings.defaultMode
            // Start clean on (re)open; keep showing a capture that's still running.
            showsResult = controller.isBusy
        }
    }

    /// Optional guidance the user types about this specific document (AI mode only).
    private var hintField: some View {
        TextField(
            "Optional: hint about this document (e.g. \"invoice — keep all line-item columns\")",
            text: $hint,
            axis: .vertical
        )
        .textFieldStyle(.roundedBorder)
        .lineLimit(1...3)
        .font(.caption)
        .disabled(controller.isBusy)
    }

    /// A Stop button while a capture is running, so a long transcription can be aborted.
    @ViewBuilder
    private var controlRow: some View {
        if controller.isBusy {
            Button(role: .destructive) { controller.cancel() } label: {
                Label("Stop", systemImage: "stop.circle")
            }
            .controlSize(.small)
        }
    }

    /// Shows whether the AI model is resident — only relevant in AI mode.
    @ViewBuilder
    private var residencyLine: some View {
        if mode == .ai {
            Label(residency.state.label, systemImage: residency.state.systemImage)
                .font(.caption2)
                .foregroundStyle(residency.state.isResident ? .primary : .secondary)
        }
    }

    private var enginePicker: some View {
        VStack(spacing: 4) {
            Picker("Engine", selection: $mode) {
                Text("Fast (Vision)").tag(CaptureMode.fast)
                Text("AI (\(activeModelName))").tag(CaptureMode.ai)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if mode == .ai {
                Text("Structured Markdown with tables and math, on-device.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Display name of the model AI mode will use (the user's selection, else the RAM-default).
    /// `bundled()` is memoized, and `activeModel` is the same resolution the controller uses.
    private var activeModelName: String {
        ModelCatalog.bundled().activeModel(selectedID: settings.selectedModelID)?.displayName ?? "no model"
    }

    /// The hint shown before any file is handled in this session.
    private var idleHint: some View {
        Text(mode == .ai
             ? "AI mode downloads the model on first use, then runs offline."
             : "Fast mode (Apple Vision) — no download needed.")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var statusLine: some View {
        if !showsResult {
            idleHint
        } else {
            resultStatus
        }
    }

    @ViewBuilder
    private var resultStatus: some View {
        switch controller.status {
        case .idle:
            idleHint
        case .working:
            ProgressView().controlSize(.small)
        case let .loadingModel(fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction).frame(maxWidth: 200)
                Text("Loading model… \(Int((fraction * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
            }
        case let .recognizing(page, pageCount, tokens):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(CaptureController.recognizingLabel(page: page, pageCount: pageCount, tokens: tokens))
                    .font(.caption).foregroundStyle(.secondary)
            }
        case let .finished(blocks, engine, destination, savedTo):
            Label(
                CaptureController.finishedMessage(blocks: blocks, engine: engine, destination: destination, savedTo: savedTo),
                systemImage: "checkmark.circle"
            )
            .font(.caption).foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.red).lineLimit(3)
        }
    }

    /// Auto-scrolling preview of the recognized text. Shown whenever there's streamed text — during
    /// recognition and after it finishes — so a quick single-image result is visible too, not just
    /// multi-page PDFs. Independent of the exact status so it never flickers out between pages.
    @ViewBuilder
    private var preview: some View {
        if showsResult, !controller.streamedText.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(controller.streamedText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("end")
                }
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 180)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: controller.streamedText) { _, _ in
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
        }
    }

    private func handleDrop(_ urls: [URL]) {
        guard let url = urls.first else { return }
        showsResult = true   // this session now has a result to show
        let mode = mode
        let hint = hint
        Task {
            do {
                let images = try ImageLoader.images(from: url)
                controller.recognize(images, mode: mode, hint: hint)
            } catch {
                controller.report(failure: "Couldn't read that file: \(error.localizedDescription)")
            }
        }
    }
}
