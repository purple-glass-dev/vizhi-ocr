/// Renders an `OCRDocument` to a string in a particular output format. Renderers are pure and
/// have no UI or engine dependencies, which makes them the primary unit-test target.
public protocol DocumentRenderer: Sendable {
    func render(_ document: OCRDocument) -> String
}

public extension OutputFormat {
    /// The renderer that produces this format.
    var renderer: DocumentRenderer {
        switch self {
        case .markdown: MarkdownRenderer()
        case .plainText: PlainTextRenderer()
        case .csv: CSVRenderer()
        case .json: JSONRenderer()
        }
    }
}
