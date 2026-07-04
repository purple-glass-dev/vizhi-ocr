/// Renders a document as RFC 4180 CSV, optimized for tables. Each `.table` becomes a header row
/// plus data rows padded to a consistent width; other blocks degrade to single-cell rows so no
/// content is silently dropped. Multiple tables are separated by a blank line.
public struct CSVRenderer: DocumentRenderer {
    public init() {}

    public func render(_ document: OCRDocument) -> String {
        document.blocks
            .map(rows(for:))
            .filter { !$0.isEmpty }
            .map { $0.map(line).joined(separator: "\n") }
            .joined(separator: "\n\n")
    }

    /// The CSV rows (each a list of cells) a block contributes.
    private func rows(for block: Block) -> [[String]] {
        switch block {
        case let .heading(_, text):
            return [[text]]
        case let .paragraph(text):
            return [[text]]
        case let .list(_, items):
            return items.map { [$0] }
        case let .table(table):
            return rows(for: table)
        case let .codeBlock(_, code):
            return [[code]]
        case let .mathBlock(latex):
            return [[latex]]
        }
    }

    private func rows(for table: Table) -> [[String]] {
        let columnCount = max(table.headers.count, table.rows.map(\.count).max() ?? 0)
        guard columnCount > 0 else { return [] }

        func pad(_ cells: [String]) -> [String] {
            (0..<columnCount).map { $0 < cells.count ? cells[$0] : "" }
        }
        return [pad(table.headers)] + table.rows.map(pad)
    }

    private func line(_ cells: [String]) -> String {
        cells.map(escape).joined(separator: ",")
    }

    /// Quote a cell per RFC 4180 if it contains a comma, quote, or newline; interior quotes double.
    private func escape(_ cell: String) -> String {
        guard cell.contains(",") || cell.contains("\"") || cell.contains("\n") || cell.contains("\r") else {
            return cell
        }
        return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
