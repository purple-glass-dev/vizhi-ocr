import CoreGraphics
import Foundation
import Testing
@testable import VizhiMLX
import VizhiCore
import VizhiModels

@Suite("Image resize targeting")
struct ResizeTargetTests {
    // Mirrors MLXOCREngine.Limits defaults.
    private func target(_ w: CGFloat, _ h: CGFloat) -> CGSize {
        MLXOCREngine.resizeTarget(width: w, height: h, maxSide: 1568, minSide: 1024, maxUpscale: 3)
    }

    @Test("Oversized captures downscale so the longest side is maxSide")
    func downscale() {
        #expect(target(3000, 2000) == CGSize(width: 1568, height: 1045))
    }

    @Test("Captures already in the band are unchanged")
    func inBand() {
        #expect(target(1200, 800) == CGSize(width: 1200, height: 800))
    }

    @Test("Small captures upscale so the longest side reaches minSide")
    func upscaleToFloor() {
        // 700 → 1024 is ~1.463×, applied to both sides (aspect preserved).
        #expect(target(700, 400) == CGSize(width: 1024, height: 585))
    }

    @Test("Tiny captures upscale only up to maxUpscale, not all the way to the floor")
    func upscaleCapped() {
        // 200 → would need 5.12× to hit 1024; capped at 3× → 600×300.
        #expect(target(200, 100) == CGSize(width: 600, height: 300))
    }

    @Test("Degenerate zero size is returned untouched")
    func zero() {
        #expect(target(0, 0) == CGSize(width: 0, height: 0))
    }
}

@Suite("Markdown → document parsing")
struct MarkdownParserTests {
    let parser = MarkdownDocumentParser()

    @Test("Headings and paragraphs")
    func headingsAndParagraphs() {
        let doc = parser.parse("# Title\n\nFirst line\nsecond line\n\nNext para")
        #expect(doc.blocks == [
            .heading(level: 1, text: "Title"),
            .paragraph(text: "First line\nsecond line"),
            .paragraph(text: "Next para"),
        ])
    }

    @Test("GFM table parses into headers and rows")
    func table() {
        let md = """
        | Name | Qty |
        | --- | --- |
        | Apple | 3 |
        | Pear | 5 |
        """
        let doc = parser.parse(md)
        #expect(doc.blocks == [.table(Table(
            headers: ["Name", "Qty"],
            rows: [["Apple", "3"], ["Pear", "5"]]
        ))])
    }

    @Test("Multi-line display math block")
    func mathBlock() {
        let doc = parser.parse("Intro\n\n$$\n\\int_0^1 x\\,dx\n$$")
        #expect(doc.blocks == [
            .paragraph(text: "Intro"),
            .mathBlock(latex: "\\int_0^1 x\\,dx"),
        ])
    }

    @Test("Single-line $$ math form")
    func inlineMathBlock() {
        let doc = parser.parse("$$ E = mc^2 $$")
        #expect(doc.blocks == [.mathBlock(latex: "E = mc^2")])
    }

    @Test("Spurious outer $$ wrapping prose and a real inner block is unwrapped")
    func nestedSpuriousMath() {
        let md = """
        $$
        Nor in tables:

        $$\\begin{array}{c|c} a & b \\end{array}$$

        Table 1: stats
        $$
        """
        let doc = parser.parse(md)
        #expect(doc.blocks == [
            .paragraph(text: "Nor in tables:"),
            .mathBlock(latex: "\\begin{array}{c|c} a & b \\end{array}"),
            .paragraph(text: "Table 1: stats"),
        ])
    }

    @Test("Inline $$…$$ with a trailing equation number splits cleanly")
    func inlineMathWithTrailingNumber() {
        let doc = parser.parse("$$\\text{C}_6 + 6\\text{O}_2 \\to 6\\text{CO}_2$$ (1)")
        #expect(doc.blocks == [
            .mathBlock(latex: "\\text{C}_6 + 6\\text{O}_2 \\to 6\\text{CO}_2"),
            .paragraph(text: "(1)"),
        ])
    }

    @Test("Leading text before inline $$…$$ splits onto its own line")
    func textBeforeInlineMath() {
        let doc = parser.parse("Reaction: $$a + b$$")
        #expect(doc.blocks == [.paragraph(text: "Reaction:"), .mathBlock(latex: "a + b")])
    }

    @Test("Unclosed lone $$ is dropped, not treated as empty math")
    func unclosedMath() {
        let doc = parser.parse("Some text\n$$")
        #expect(doc.blocks == [.paragraph(text: "Some text")])
    }

    @Test("Well-formed multi-line math still parses")
    func wellFormedMultilineMath() {
        let doc = parser.parse("$$\n\\int_0^1 x\\,dx\n$$")
        #expect(doc.blocks == [.mathBlock(latex: "\\int_0^1 x\\,dx")])
    }

    @Test("Multi-line $$ block with delimiters attached to content (cases)")
    func attachedDelimiterMath() {
        let md = """
        Intro

        $$r(a) = \\begin{cases}
        1, & x \\\\
        0, & y
        \\end{cases}$$
        """
        let doc = parser.parse(md)
        #expect(doc.blocks == [
            .paragraph(text: "Intro"),
            .mathBlock(latex: "r(a) = \\begin{cases}\n1, & x \\\\\n0, & y\n\\end{cases}"),
        ])
    }

    @Test("HTML table (as GLM-OCR emits) becomes a Table block")
    func htmlTable() {
        let md = "<table><tr><td>Name</td><td>Qty</td></tr><tr><td>Apple</td><td>3</td></tr></table>"
        let doc = parser.parse(md)
        #expect(doc.blocks == [.table(Table(headers: ["Name", "Qty"], rows: [["Apple", "3"]]))])
    }

    @Test("HTML table with th headers, entities, and surrounding text")
    func htmlTableWithContext() {
        let md = """
        Here is the data:
        <table>
          <tr><th>A &amp; B</th><th>C</th></tr>
          <tr><td>1</td><td>x &lt; y</td></tr>
        </table>
        Done.
        """
        let doc = parser.parse(md)
        #expect(doc.blocks == [
            .paragraph(text: "Here is the data:"),
            .table(Table(headers: ["A & B", "C"], rows: [["1", "x < y"]])),
            .paragraph(text: "Done."),
        ])
    }

    @Test("HTML table renders as clean GFM Markdown")
    func htmlTableRendersGFM() {
        let doc = parser.parse("<table><tr><td>H1</td><td>H2</td></tr><tr><td>a</td><td>b</td></tr></table>")
        let rendered = MarkdownRenderer().render(doc)
        #expect(rendered == "| H1 | H2 |\n| --- | --- |\n| a | b |")
    }

    @Test("Malformed, truncated HTML table (missing > and no </table>) still parses")
    func malformedTruncatedTable() {
        // Mirrors real GLM-OCR output: tags missing '>', no closing </table>, cut off mid-row.
        let md = #"<table class="t"<thead<tr<th>City</th<th>No.</th></tr></thead<tbody<tr<td>Antelope</td<td>55</td></tr<tr<td>Chico</td<td>22"#
        let doc = parser.parse(md)
        #expect(doc.blocks == [.table(Table(
            headers: ["City", "No."],
            rows: [["Antelope", "55"], ["Chico", "22"]]
        ))])
    }

    @Test("Does not treat <thead>/<tbody> as cells")
    func ignoresSectionTags() {
        let md = "<table><thead><tr><td>A</td></tr></thead><tbody><tr><td>1</td></tr></tbody></table>"
        let doc = parser.parse(md)
        #expect(doc.blocks == [.table(Table(headers: ["A"], rows: [["1"]]))])
    }

    @Test("Round-trips with the Markdown renderer for a table")
    func roundTrip() {
        let table = Table(headers: ["A", "B"], rows: [["1", "2"]])
        let rendered = MarkdownRenderer().render(OCRDocument(blocks: [.table(table)]))
        let reparsed = parser.parse(rendered)
        #expect(reparsed.blocks == [.table(table)])
    }
}

@Suite("OCR prompt building")
struct OCRPromptTests {
    let builder = OCRPromptBuilder()

    private func model(_ caps: [ModelCapability]) -> ModelDescriptor {
        ModelDescriptor(
            id: "test", displayName: "Test", tier: .standard, capabilities: caps,
            minRAMGB: 16, recommendedRAMGB: 16, quantization: "q4",
            source: ModelSource(huggingFaceRepo: "x/y")
        )
    }

    @Test("Full-capability model is asked for tables, math, and multicolumn")
    func fullCaps() {
        let prompt = builder.instruction(for: model([.text, .tables, .math, .multicolumn, .handwriting]))
        #expect(prompt.contains("Markdown tables"))
        #expect(prompt.contains("LaTeX"))
        #expect(prompt.contains("multi-column"))
    }

    @Test("Text-only model is not asked for tables or math")
    func textOnly() {
        let prompt = builder.instruction(for: model([.text]))
        #expect(!prompt.contains("Markdown tables"))
        #expect(!prompt.contains("LaTeX"))
    }

    @Test("A model-specific prompt overrides the generic instruction")
    func promptOverride() {
        let trained = "Return the tables in html format."
        let m = ModelDescriptor(
            id: "nano", displayName: "Nano", tier: .standard, capabilities: [.text, .tables],
            minRAMGB: 12, recommendedRAMGB: 24, quantization: "q4", prompt: trained,
            source: ModelSource(huggingFaceRepo: "x/y")
        )
        // Used verbatim — and the generic Markdown-table rule is not appended.
        #expect(builder.instruction(for: m) == trained)
        #expect(!builder.instruction(for: m).contains("Markdown tables"))
    }

    @Test("A user hint is appended after the base instruction")
    func userHint() {
        let m = model([.text, .tables])
        let withHint = builder.instruction(for: m, userHint: "  This is an invoice.  ")
        // Base instruction is preserved, hint is appended and trimmed.
        #expect(withHint.contains("Transcribe all text"))
        #expect(withHint.hasSuffix("Additional guidance for this document: This is an invoice."))
    }

    @Test("Blank or whitespace hints are ignored")
    func blankHint() {
        let m = model([.text])
        #expect(builder.instruction(for: m, userHint: "   ") == builder.instruction(for: m))
        #expect(builder.instruction(for: m, userHint: nil) == builder.instruction(for: m))
    }
}

