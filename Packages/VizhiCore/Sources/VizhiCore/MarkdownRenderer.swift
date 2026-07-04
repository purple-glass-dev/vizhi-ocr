/// Renders a document as GitHub-flavored Markdown: headings, lists, GFM tables, fenced code,
/// and `$$…$$` math blocks. This is the default output format.
public struct MarkdownRenderer: DocumentRenderer {
    public init() {}

    public func render(_ document: OCRDocument) -> String {
        document.blocks.map(render(block:)).joined(separator: "\n\n")
    }

    private func render(block: Block) -> String {
        switch block {
        case let .heading(level, text):
            let hashes = String(repeating: "#", count: min(max(level, 1), 6))
            return "\(hashes) \(text)"

        case let .paragraph(text):
            return text

        case let .list(ordered, items):
            return items.enumerated().map { index, item in
                ordered ? "\(index + 1). \(item)" : "- \(item)"
            }.joined(separator: "\n")

        case let .table(table):
            return renderTable(table)

        case let .codeBlock(language, code):
            return "```\(language ?? "")\n\(code)\n```"

        case let .mathBlock(latex):
            return "$$\n\(latex)\n$$"
        }
    }

    private func renderTable(_ table: Table) -> String {
        let columnCount = max(table.headers.count, table.rows.map(\.count).max() ?? 0)
        guard columnCount > 0 else { return "" }

        func row(_ cells: [String]) -> String {
            let padded = (0..<columnCount).map { index in
                index < cells.count ? cells[index] : ""
            }
            return "| " + padded.joined(separator: " | ") + " |"
        }

        let header = row(table.headers)
        let separator = "| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |"
        let body = table.rows.map(row).joined(separator: "\n")
        return body.isEmpty ? "\(header)\n\(separator)" : "\(header)\n\(separator)\n\(body)"
    }
}
