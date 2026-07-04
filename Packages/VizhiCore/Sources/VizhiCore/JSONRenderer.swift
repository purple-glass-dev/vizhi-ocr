import Foundation

/// Serializes the full `OCRDocument` — blocks (with their structure preserved) and metadata — as
/// pretty-printed JSON with stable key ordering. This is the lossless format for feeding results
/// into other tooling or an LLM.
public struct JSONRenderer: DocumentRenderer {
    public init() {}

    public func render(_ document: OCRDocument) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let payload = EncodableDocument(document)
        guard let data = try? encoder.encode(payload), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

/// A JSON-shaped projection of `OCRDocument`. Mirrors the model so the output round-trips structure.
private struct EncodableDocument: Encodable {
    let blocks: [EncodableBlock]
    let metadata: EncodableMetadata

    init(_ document: OCRDocument) {
        self.blocks = document.blocks.map(EncodableBlock.init)
        self.metadata = EncodableMetadata(document.metadata)
    }
}

private struct EncodableBlock: Encodable {
    let block: Block

    init(_ block: Block) { self.block = block }

    enum CodingKeys: String, CodingKey {
        case type, level, text, ordered, items, headers, rows, language, code, latex
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch block {
        case let .heading(level, text):
            try container.encode("heading", forKey: .type)
            try container.encode(level, forKey: .level)
            try container.encode(text, forKey: .text)
        case let .paragraph(text):
            try container.encode("paragraph", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .list(ordered, items):
            try container.encode("list", forKey: .type)
            try container.encode(ordered, forKey: .ordered)
            try container.encode(items, forKey: .items)
        case let .table(table):
            try container.encode("table", forKey: .type)
            try container.encode(table.headers, forKey: .headers)
            try container.encode(table.rows, forKey: .rows)
        case let .codeBlock(language, code):
            try container.encode("codeBlock", forKey: .type)
            try container.encodeIfPresent(language, forKey: .language)
            try container.encode(code, forKey: .code)
        case let .mathBlock(latex):
            try container.encode("mathBlock", forKey: .type)
            try container.encode(latex, forKey: .latex)
        }
    }
}

private struct EncodableMetadata: Encodable {
    let engine: String?
    let model: String?
    let languages: [String]
    let durationSeconds: Double?

    init(_ metadata: Metadata) {
        self.engine = metadata.engine
        self.model = metadata.model
        self.languages = metadata.languages
        self.durationSeconds = metadata.durationSeconds
    }
}
