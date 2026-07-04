import Testing
@testable import VizhiCore

@Suite("Markdown rendering")
struct MarkdownRendererTests {
    let renderer = MarkdownRenderer()

    @Test("Headings clamp to levels 1...6")
    func headings() {
        let doc = OCRDocument(blocks: [.heading(level: 2, text: "Results"), .heading(level: 9, text: "Deep")])
        #expect(renderer.render(doc) == "## Results\n\n###### Deep")
    }

    @Test("Unordered and ordered lists")
    func lists() {
        let doc = OCRDocument(blocks: [
            .list(ordered: false, items: ["a", "b"]),
            .list(ordered: true, items: ["x", "y"]),
        ])
        #expect(renderer.render(doc) == "- a\n- b\n\n1. x\n2. y")
    }

    @Test("GFM table with ragged rows pads to column count")
    func table() {
        let table = Table(headers: ["H1", "H2"], rows: [["a", "b"], ["c"]])
        let doc = OCRDocument(blocks: [.table(table)])
        #expect(renderer.render(doc) == """
        | H1 | H2 |
        | --- | --- |
        | a | b |
        | c |  |
        """)
    }

    @Test("Math block emits $$ fences")
    func math() {
        let doc = OCRDocument(blocks: [.mathBlock(latex: "E = mc^2")])
        #expect(renderer.render(doc) == "$$\nE = mc^2\n$$")
    }

    @Test("Code block carries language")
    func code() {
        let doc = OCRDocument(blocks: [.codeBlock(language: "swift", code: "let x = 1")])
        #expect(renderer.render(doc) == "```swift\nlet x = 1\n```")
    }
}

@Suite("Plain-text rendering")
struct PlainTextRendererTests {
    @Test("Strips structure, keeps content; tables become TSV")
    func strips() {
        let doc = OCRDocument(blocks: [
            .heading(level: 1, text: "Title"),
            .table(Table(headers: ["A", "B"], rows: [["1", "2"]])),
        ])
        #expect(PlainTextRenderer().render(doc) == "Title\n\nA\tB\n1\t2")
    }
}

@Suite("CSV rendering")
struct CSVRendererTests {
    let renderer = CSVRenderer()

    @Test("Table becomes header + padded data rows")
    func table() {
        let doc = OCRDocument(blocks: [.table(Table(headers: ["A", "B"], rows: [["1", "2"], ["3"]]))])
        #expect(renderer.render(doc) == "A,B\n1,2\n3,")
    }

    @Test("Cells with commas, quotes, or newlines are quoted per RFC 4180")
    func quoting() {
        let doc = OCRDocument(blocks: [.table(Table(
            headers: ["plain", "comma,here", "quote\"here", "new\nline"],
            rows: []
        ))])
        #expect(renderer.render(doc) == "plain,\"comma,here\",\"quote\"\"here\",\"new\nline\"")
    }

    @Test("Non-table blocks degrade to single-cell rows; tables separated by blank line")
    func mixed() {
        let doc = OCRDocument(blocks: [
            .heading(level: 1, text: "Title"),
            .table(Table(headers: ["A"], rows: [["1"]])),
            .list(ordered: false, items: ["x", "y"]),
        ])
        #expect(renderer.render(doc) == "Title\n\nA\n1\n\nx\ny")
    }
}

@Suite("JSON rendering")
struct JSONRendererTests {
    let renderer = JSONRenderer()

    @Test("Document serializes blocks and metadata with stable keys")
    func document() {
        let doc = OCRDocument(
            blocks: [
                .heading(level: 2, text: "H"),
                .table(Table(headers: ["A"], rows: [["1"]])),
                .mathBlock(latex: "E=mc^2"),
            ],
            metadata: Metadata(engine: "ai", model: "glm-ocr", languages: ["en"], durationSeconds: 1.5)
        )
        #expect(renderer.render(doc) == """
        {
          "blocks" : [
            {
              "level" : 2,
              "text" : "H",
              "type" : "heading"
            },
            {
              "headers" : [
                "A"
              ],
              "rows" : [
                [
                  "1"
                ]
              ],
              "type" : "table"
            },
            {
              "latex" : "E=mc^2",
              "type" : "mathBlock"
            }
          ],
          "metadata" : {
            "durationSeconds" : 1.5,
            "engine" : "ai",
            "languages" : [
              "en"
            ],
            "model" : "glm-ocr"
          }
        }
        """)
    }
}

@Suite("Format grouping")
struct FormatGroupingTests {
    @Test("General formats exclude the table-oriented ones")
    func grouping() {
        #expect(OutputFormat.generalCases == [.markdown, .plainText])
        #expect(OutputFormat.tableCases == [.csv, .json])
    }

    @Test("hasTable detects a table block")
    func hasTable() {
        #expect(OCRDocument(blocks: [.table(Table(headers: ["A"], rows: []))]).hasTable)
        #expect(!OCRDocument(blocks: [.paragraph(text: "x")]).hasTable)
    }
}

@Suite("Output format wiring")
struct OutputFormatTests {
    @Test("Every format resolves a renderer", arguments: OutputFormat.allCases)
    func renderers(format: OutputFormat) {
        let doc = OCRDocument(blocks: [.paragraph(text: "hi")])
        #expect(!format.renderer.render(doc).isEmpty)
    }
}

@Suite("Output destination")
struct OutputDestinationTests {
    @Test("Clipboard/file flags per case")
    func flags() {
        #expect(OutputDestination.clipboard.savesToClipboard && !OutputDestination.clipboard.savesToFile)
        #expect(!OutputDestination.file.savesToClipboard && OutputDestination.file.savesToFile)
        #expect(OutputDestination.both.savesToClipboard && OutputDestination.both.savesToFile)
    }
}
