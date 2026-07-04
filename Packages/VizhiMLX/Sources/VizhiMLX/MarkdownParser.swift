import Foundation
import VizhiCore

/// Parses a model's raw output back into an `OCRDocument` so every output formatter works
/// uniformly regardless of engine. Recognizes headings, GFM tables, `$$` math, paragraphs — and
/// **HTML tables**, which OCR VLMs like GLM-OCR emit instead of Markdown. Pure and unit-tested.
public struct MarkdownDocumentParser: Sendable {
    public init() {}

    public func parse(_ markdown: String, metadata: Metadata = .init()) -> OCRDocument {
        var blocks: [Block] = []
        // Pull out any HTML tables first; parse the surrounding text as Markdown.
        for segment in HTMLTableExtractor.split(markdown) {
            switch segment {
            case let .text(text):
                blocks.append(contentsOf: parseBlocks(text))
            case let .table(table):
                blocks.append(.table(table))
            }
        }
        return OCRDocument(blocks: blocks, metadata: metadata)
    }

    /// Line-based Markdown parsing for a text segment (no HTML tables).
    private func parseBlocks(_ markdown: String) -> [Block] {
        let rawLines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        // Put any inline `$$…$$` (and its surrounding text, e.g. a trailing "(1)") on its own line.
        let lines = rawLines.flatMap(splitInlineMath)
        var blocks: [Block] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(text: paragraph.joined(separator: "\n")))
                paragraph.removeAll()
            }
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
            } else if trimmed.hasPrefix("$$"), let (latex, next) = collectMath(lines, at: index) {
                flushParagraph()
                blocks.append(.mathBlock(latex: latex))
                index = next
            } else if trimmed.hasPrefix("$$") {
                // A spurious/malformed $$ (blank line, nested $$, or no closing delimiter). Treat it
                // as text and drop lone delimiter lines so the real content/inner math survives.
                if trimmed != "$$" { paragraph.append(trimmed) }
                index += 1
            } else if let level = headingLevel(trimmed) {
                flushParagraph()
                let text = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: level, text: text))
                index += 1
            } else if isTableRow(trimmed), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                flushParagraph()
                let (table, next) = collectTable(lines, startingAt: index)
                blocks.append(.table(table))
                index = next
            } else {
                paragraph.append(trimmed)
                index += 1
            }
        }
        flushParagraph()
        return blocks
    }

    // MARK: - Helpers

    /// Splits a line like `A $$math$$ B` into `["A", "$$math$$", "B"]` so a display equation with a
    /// trailing number/caption on the same line becomes a clean math block plus separate text.
    /// Lines that are entirely the math (or contain no `$$…$$` pair) are returned unchanged.
    private func splitInlineMath(_ line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\$\\$.+?\\$\\$") else { return [line] }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return [line]
        }
        let before = ns.substring(to: match.range.location).trimmingCharacters(in: .whitespaces)
        let math = ns.substring(with: match.range)
        let after = ns.substring(from: match.range.location + match.range.length).trimmingCharacters(in: .whitespaces)

        if before.isEmpty, after.isEmpty { return [line] }

        var result: [String] = []
        if !before.isEmpty { result.append(before) }
        result.append(math)
        if !after.isEmpty { result.append(contentsOf: splitInlineMath(after)) }
        return result
    }

    private func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6, line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    /// Collects a well-formed display-math block starting at `index`, or returns `nil` if it's
    /// malformed — a blank line inside, a nested `$$`, or no closing `$$`. Returning nil lets the
    /// caller treat a stray `$$` as plain text instead of swallowing prose into bogus math.
    private func collectMath(_ lines: [String], at index: Int) -> (latex: String, next: Int)? {
        let first = lines[index].trimmingCharacters(in: .whitespaces)

        // Single-line form: $$ … $$
        if first.count > 4, first.hasPrefix("$$"), first.hasSuffix("$$") {
            let inner = String(first.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
            return inner.isEmpty || inner.contains("$$") ? nil : (inner, index + 1)
        }

        // Multi-line form: opener line `$$` (optionally with the first latex line on it).
        var body: [String] = []
        let openerTail = String(first.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        if !openerTail.isEmpty {
            if openerTail.contains("$$") { return nil }
            body.append(openerTail)
        }

        var cursor = index + 1
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            // A line ending in `$$` closes the block — either a lone `$$` or the trailing delimiter
            // on a content line like `\end{cases}$$`. Anything else containing `$$` is malformed.
            if trimmed.hasSuffix("$$") {
                let inner = String(trimmed.dropLast(2)).trimmingCharacters(in: .whitespaces)
                if inner.contains("$$") { return nil }
                if !inner.isEmpty { body.append(inner) }
                let latex = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return latex.isEmpty || latex.contains("$$") ? nil : (latex, cursor + 1)
            }
            // Blank line or a stray inner $$ means this isn't a well-formed display-math block.
            if trimmed.isEmpty || trimmed.contains("$$") { return nil }
            body.append(lines[cursor])
            cursor += 1
        }
        return nil // no closing delimiter
    }

    private func isTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.contains("|") && line.dropFirst().contains("|")
    }

    private func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard isTableRow(trimmed) else { return false }
        return cells(trimmed).allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            return !c.isEmpty && c.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private func collectTable(_ lines: [String], startingAt index: Int) -> (Table, next: Int) {
        let headers = cells(lines[index].trimmingCharacters(in: .whitespaces))
        var rows: [[String]] = []
        var cursor = index + 2 // skip header + separator
        while cursor < lines.count, isTableRow(lines[cursor].trimmingCharacters(in: .whitespaces)) {
            rows.append(cells(lines[cursor].trimmingCharacters(in: .whitespaces)))
            cursor += 1
        }
        return (Table(headers: headers, rows: rows), cursor)
    }

    /// Splits a `| a | b |` row into trimmed cell strings.
    private func cells(_ row: String) -> [String] {
        var trimmed = Substring(row)
        if trimmed.hasPrefix("|") { trimmed = trimmed.dropFirst() }
        if trimmed.hasSuffix("|") { trimmed = trimmed.dropLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// A run of model output: either plain text or an HTML table lifted out of it.
enum HTMLSegment: Equatable {
    case text(String)
    case table(Table)
}

/// Finds `<table>…` regions (closed or truncated) and turns each into a `Table`, leaving
/// surrounding text intact. Tolerant of OCR models that emit malformed HTML.
enum HTMLTableExtractor {
    static func split(_ input: String) -> [HTMLSegment] {
        var segments: [HTMLSegment] = []
        var textStart = input.startIndex
        var searchFrom = input.startIndex

        while let open = input.range(of: "<table", options: .caseInsensitive, range: searchFrom..<input.endIndex) {
            if open.lowerBound > textStart {
                let pre = String(input[textStart..<open.lowerBound])
                if !pre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { segments.append(.text(pre)) }
            }
            // Region runs to the closing tag, or to the end of the string if the output was truncated.
            let close = input.range(of: "</table>", options: .caseInsensitive, range: open.upperBound..<input.endIndex)
            let regionEnd = close?.upperBound ?? input.endIndex
            segments.append(.table(HTMLTableParser.parse(String(input[open.lowerBound..<regionEnd]))))
            textStart = regionEnd
            searchFrom = regionEnd
        }

        if textStart < input.endIndex {
            let tail = String(input[textStart...])
            if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { segments.append(.text(tail)) }
        }
        return segments.isEmpty ? [.text(input)] : segments
    }
}

/// Marker-based HTML-table → `Table` conversion. Splits on `<tr>` and `<td>`/`<th>` openers rather
/// than matching well-formed closing tags, so it survives the malformed/truncated HTML that OCR
/// VLMs (e.g. GLM-OCR) produce — missing `>`, missing `</td>`, no final `</table>`. The first row
/// is treated as the header. Doesn't model rowspan/colspan (rare in OCR).
enum HTMLTableParser {
    static func parse(_ html: String) -> Table {
        // Each `<tr` starts a row; within a row each `<td`/`<th` starts a cell. Lookahead keeps the
        // delimiter out of the chunk and avoids matching `<thead>`/`<tbody>`.
        let rows = chunks(of: html, afterPattern: "<tr(?=[\\s></])").map { row in
            chunks(of: row, afterPattern: "<t[dh](?=[\\s></])").map(cellText)
        }
        guard let headers = rows.first else { return Table(headers: [], rows: []) }
        return Table(headers: headers, rows: Array(rows.dropFirst()))
    }

    /// Returns the text following each match of `pattern`, up to the next match (the chunk before
    /// the first match — table/row preamble — is dropped).
    private static func chunks(of input: String, afterPattern pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        return matches.enumerated().map { index, match in
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            return end > start ? ns.substring(with: NSRange(location: start, length: end - start)) : ""
        }
    }

    /// Extracts a cell's text from a chunk like `>value</td` (or attributes/`>` then value): skip an
    /// optional opening `>`, take up to the next `<`, decode entities, collapse whitespace.
    private static func cellText(_ chunk: String) -> String {
        var slice = Substring(chunk)
        if let gt = slice.firstIndex(of: ">") { slice = slice[slice.index(after: gt)...] }
        if let lt = slice.firstIndex(of: "<") { slice = slice[..<lt] }

        var text = String(slice)
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
