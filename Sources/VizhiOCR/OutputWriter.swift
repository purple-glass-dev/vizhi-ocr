import AppKit
import Foundation
import VizhiCore

/// Delivers a recognized document to the chosen destination(s): the clipboard (in the user's
/// output format) and/or a saved Markdown file. Returns the saved file URL, if any.
enum OutputWriter {
    @MainActor
    @discardableResult
    static func write(
        _ document: OCRDocument,
        format: OutputFormat,
        destination: OutputDestination,
        folder: URL
    ) throws -> URL? {
        if destination.savesToClipboard {
            let text = format.renderer.render(document)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }

        guard destination.savesToFile else { return nil }
        // A saved file from a direct (non-preview) capture is always Markdown. CSV/JSON are chosen
        // per-result in the preview, which commits via `writeText`.
        let markdown = MarkdownRenderer().render(document)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(filename(ext: OutputFormat.markdown.fileExtension))
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Delivers already-rendered (and possibly user-edited) text to the chosen destination(s). Used
    /// by the editable preview, where the text — not the structured document — is the source of
    /// truth. The saved file's extension follows `format`. Returns the saved file URL, if any.
    @MainActor
    @discardableResult
    static func writeText(
        _ text: String,
        format: OutputFormat,
        destination: OutputDestination,
        folder: URL
    ) throws -> URL? {
        if destination.savesToClipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }

        guard destination.savesToFile else { return nil }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(filename(ext: format.fileExtension))
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Timestamped filename like `VizhiOCR-2026-06-27-153012.md`.
    private static func filename(ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "VizhiOCR-\(formatter.string(from: Date())).\(ext)"
    }
}
