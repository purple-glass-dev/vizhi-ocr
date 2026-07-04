import Foundation

/// Engine-agnostic representation of a recognized document.
///
/// Both the Fast (Vision) and AI (MLX) engines normalize their output into this model so the
/// output formatters work uniformly regardless of which engine produced the result.
public struct OCRDocument: Sendable, Equatable {
    public var blocks: [Block]
    public var metadata: Metadata

    public init(blocks: [Block], metadata: Metadata = .init()) {
        self.blocks = blocks
        self.metadata = metadata
    }

    /// Whether the document contains at least one table — gates the table-oriented output formats.
    public var hasTable: Bool {
        blocks.contains { if case .table = $0 { true } else { false } }
    }
}

/// A top-level structural element of a document.
public enum Block: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case list(ordered: Bool, items: [String])
    case table(Table)
    case codeBlock(language: String?, code: String)
    /// Display math as LaTeX (rendered as a `$$…$$` block in Markdown).
    case mathBlock(latex: String)
}

/// A simple rectangular table. `rows` cells are aligned to `headers` by index.
public struct Table: Sendable, Equatable {
    public var headers: [String]
    public var rows: [[String]]

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }
}

/// Provenance and timing for a recognition result.
public struct Metadata: Sendable, Equatable {
    public var engine: String?
    public var model: String?
    public var languages: [String]
    public var durationSeconds: Double?

    public init(
        engine: String? = nil,
        model: String? = nil,
        languages: [String] = [],
        durationSeconds: Double? = nil
    ) {
        self.engine = engine
        self.model = model
        self.languages = languages
        self.durationSeconds = durationSeconds
    }
}
