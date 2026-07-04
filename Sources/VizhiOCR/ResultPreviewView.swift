import SwiftUI
import VizhiCore
import VizhiMLX
import VizhiUI

/// Editable preview of a recognized result, shown before it's copied/saved when "Preview & edit
/// before copying" is on. The source crop sits beside the text so a misread is easy to spot and
/// fix; the format picker re-renders the result for this capture only (the structured document is
/// the source of truth). Copy/Save delivers the edited text to the configured destination.
struct ResultPreviewView: View {
    let settings: SettingsStore
    let controller: CaptureController
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var format: OutputFormat = .markdown
    @State private var text: String = ""
    /// Per-format editor contents, so switching format and back preserves your edits. A format is
    /// rendered from the document on first view and cached here; subsequent visits restore it.
    @State private var drafts: [OutputFormat: String] = [:]
    /// Markdown only: show the rendered preview instead of the editable source.
    @State private var isPreviewing = false
    /// Crop-pane zoom; 1.0 = best-fit each page to the pane. `pinchBase` holds the zoom at the start
    /// of a magnify gesture.
    @State private var zoom: CGFloat = 1
    @State private var pinchBase: CGFloat?

    var body: some View {
        Group {
            if controller.pendingPreview != nil {
                content
            } else {
                placeholder
            }
        }
        .frame(minWidth: 720, minHeight: 440)
        .onAppear(perform: load)
        .onChange(of: controller.pendingPreview?.token) { _, _ in load() }
        // As a menubar (accessory) app there's no Dock icon to reselect this window, so float it and
        // let it follow across Spaces — otherwise it sinks behind other apps and looks "lost".
        .background(WindowAccessor { window in
            window.level = .floating
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
        })
    }

    /// The formats offered for this result: the general ones, plus the table-oriented formats only
    /// when the document actually contains a table.
    private var availableFormats: [OutputFormat] {
        let hasTable = controller.pendingPreview?.document.hasTable ?? false
        return OutputFormat.generalCases + (hasTable ? OutputFormat.tableCases : [])
    }

    /// Format selection that stashes the current editor into `drafts` before switching, then
    /// restores the target format's cached draft (or renders it fresh). Preserves manual edits.
    private var formatBinding: Binding<OutputFormat> {
        Binding(
            get: { format },
            set: { newFormat in
                guard newFormat != format else { return }
                drafts[format] = text
                format = newFormat
                if newFormat != .markdown { isPreviewing = false }
                if let cached = drafts[newFormat] {
                    text = cached
                } else if let preview = controller.pendingPreview {
                    text = newFormat.renderer.render(preview.document)
                }
            }
        )
    }

    private var content: some View {
        VStack(spacing: 0) {
            HSplitView {
                cropPane
                editorPane
            }
            Divider()
            actionBar
        }
    }

    /// Source page crops for the pending result (every PDF page, or the single screen region).
    private var pageImages: [OCRImage] {
        controller.pendingPreview?.images ?? []
    }

    @ViewBuilder
    private var cropPane: some View {
        if pageImages.isEmpty {
            Color.clear.frame(minWidth: 0, idealWidth: 0, maxWidth: 0)
        } else {
            GeometryReader { geo in
                // Each page is best-fit to the pane (zoom 1); zooming past that enables scrolling.
                // LazyVStack so a long PDF only realizes the visible page images.
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(pageImages.enumerated()), id: \.offset) { index, image in
                            let size = fittedSize(image, in: geo.size)
                            VStack(spacing: 4) {
                                Image(decorative: image.cgImage, scale: 1)
                                    .resizable()
                                    .frame(width: size.width * zoom, height: size.height * zoom)
                                if pageImages.count > 1 {
                                    Text("Page \(index + 1)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                }
                .gesture(magnify)
            }
            .background(.quaternary.opacity(0.3))
            .overlay(alignment: .bottom) { zoomControls }
            .frame(minWidth: 260, idealWidth: 360)
        }
    }

    /// Zoom controls overlaid on the crop pane: out, a fit/percentage button that resets to best-fit,
    /// and in.
    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { setZoom(zoom * 0.8) } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Zoom out")
            Button { setZoom(1) } label: {
                Text(abs(zoom - 1) < 0.01 ? "Fit" : "\(Int((zoom * 100).rounded()))%")
                    .monospacedDigit().frame(minWidth: 36)
            }
            .help("Fit to window")
            Button { setZoom(zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom in")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .padding(8)
    }

    /// Magnify (trackpad pinch) the crop pane, relative to the zoom at the gesture's start.
    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBase ?? zoom
                if pinchBase == nil { pinchBase = zoom }
                setZoom(base * value.magnification)
            }
            .onEnded { _ in pinchBase = nil }
    }

    private func setZoom(_ value: CGFloat) {
        zoom = min(max(value, 0.25), 6)
    }

    /// Size that fits `image` within the pane (minus chrome) at zoom 1.0, preserving aspect ratio.
    private func fittedSize(_ image: OCRImage, in pane: CGSize) -> CGSize {
        let width = CGFloat(image.cgImage.width)
        let height = CGFloat(image.cgImage.height)
        guard width > 0, height > 0, pane.width > 0, pane.height > 0 else { return pane }
        let chromeHeight: CGFloat = pageImages.count > 1 ? 40 : 18
        let scale = min((pane.width - 18) / width, (pane.height - chromeHeight) / height)
        return CGSize(width: width * scale, height: height * scale)
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Format", selection: formatBinding) {
                    ForEach(availableFormats) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .fixedSize()
                Spacer()
                if format == .markdown {
                    Picker("View", selection: $isPreviewing) {
                        Text("Edit").tag(false)
                        Text("Preview").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .labelsHidden()
                }
            }
            if isPreviewing && format == .markdown {
                MarkdownPreview(blocks: MarkdownDocumentParser().parse(text).blocks)
                    .frame(minWidth: 320, minHeight: 320, maxHeight: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            } else {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 320, minHeight: 320)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                Text("Edit freely — your changes are kept when you switch formats.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var actionBar: some View {
        HStack {
            Button("Discard", role: .cancel, action: discard)
            Spacer()
            Button(commitLabel, action: commit)
                .keyboardShortcut(.defaultAction)
                .disabled(text.isEmpty)
        }
        .padding(12)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass").font(.system(size: 32)).foregroundStyle(.secondary)
            Text("No result to preview").font(.headline)
            Text("Captures will appear here for review before they're copied.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Primary-action label reflecting where the result will go.
    private var commitLabel: String {
        switch settings.outputDestination {
        case .clipboard: "Copy"
        case .file: "Save"
        case .both: "Copy & Save"
        }
    }

    /// Initializes the editor for the current pending result, in the user's default output format,
    /// and resets the per-format draft cache.
    private func load() {
        guard let preview = controller.pendingPreview else { return }
        let initial = settings.outputFormat
        format = initial
        text = initial.renderer.render(preview.document)
        drafts = [initial: text]
        isPreviewing = false
        zoom = 1
    }

    private func commit() {
        controller.commitPreview(text: text, format: format)
        dismissWindow(id: WindowID.preview)
    }

    private func discard() {
        controller.discardPreview()
        dismissWindow(id: WindowID.preview)
    }
}
