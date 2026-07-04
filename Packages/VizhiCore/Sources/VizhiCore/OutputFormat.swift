/// Clipboard/file output formats. Markdown is the default; LaTeX math is emitted inline within the
/// Markdown rather than as a separate format. CSV/JSON are structured, table-oriented formats
/// offered per-result (in the editable preview) only when the document actually contains a table.
public enum OutputFormat: String, Sendable, CaseIterable, Identifiable {
    case markdown
    case plainText
    case csv
    case json

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .markdown: "Markdown"
        case .plainText: "Plain Text"
        case .csv: "CSV"
        case .json: "JSON"
        }
    }

    /// File extension for a saved result in this format. Text formats save as Markdown (`.md`);
    /// CSV/JSON save in their own format so the file round-trips into spreadsheets and tooling.
    public var fileExtension: String {
        switch self {
        case .markdown, .plainText: "md"
        case .csv: "csv"
        case .json: "json"
        }
    }

    /// Formats that always apply to any result — the choices offered as a global default.
    public static var generalCases: [OutputFormat] { [.markdown, .plainText] }

    /// Structured, table-oriented formats — offered per-result only when a table is detected.
    public static var tableCases: [OutputFormat] { [.csv, .json] }
}
