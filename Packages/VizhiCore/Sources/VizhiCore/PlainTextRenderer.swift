/// Renders a document as unformatted plain text — structure stripped, content preserved.
public struct PlainTextRenderer: DocumentRenderer {
    public init() {}

    public func render(_ document: OCRDocument) -> String {
        document.blocks.map(render(block:)).joined(separator: "\n\n")
    }

    private func render(block: Block) -> String {
        switch block {
        case let .heading(_, text):
            return text
        case let .paragraph(text):
            return text
        case let .list(_, items):
            return items.joined(separator: "\n")
        case let .table(table):
            let rows = [table.headers] + table.rows
            return rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
        case let .codeBlock(_, code):
            return code
        case let .mathBlock(latex):
            return latex
        }
    }
}
