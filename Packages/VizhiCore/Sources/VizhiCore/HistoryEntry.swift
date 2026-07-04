import Foundation

/// One recorded capture, stored **only** when the user opts into local history (off by default).
/// Local-only, never synced or uploaded — see docs/PRIVACY.md.
public struct HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    /// Engine that produced it: a model id, or Apple Vision's identifier.
    public let engine: String
    /// The Markdown rendering that was delivered, kept for preview and one-click re-copy.
    public let text: String

    public init(id: UUID = UUID(), date: Date = Date(), engine: String, text: String) {
        self.id = id
        self.date = date
        self.engine = engine
        self.text = text
    }

    /// A short, single-line preview (first non-empty line) for the history list.
    public var preview: String {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return "(empty)"
    }
}
