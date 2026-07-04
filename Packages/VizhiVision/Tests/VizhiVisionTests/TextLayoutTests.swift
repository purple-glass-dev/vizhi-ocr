import CoreGraphics
import Testing
@testable import VizhiVision
import VizhiCore

@Suite("Vision text layout assembly")
struct TextLayoutTests {
    /// Box helper: y is the line's vertical position (bottom-left origin), height fixed.
    private func line(_ text: String, y: CGFloat, x: CGFloat = 0.1, height: CGFloat = 0.03) -> RecognizedLine {
        RecognizedLine(text: text, boundingBox: CGRect(x: x, y: y, width: 0.3, height: height))
    }

    @Test("Orders top-to-bottom regardless of input order")
    func readingOrder() {
        let doc = TextLayout.assemble([
            line("third", y: 0.40),
            line("first", y: 0.90),
            line("second", y: 0.65),
        ], paragraphGap: 0.5)
        #expect(doc.blocks == [.paragraph(text: "first\nsecond\nthird")])
    }

    @Test("Large vertical gaps split paragraphs")
    func paragraphSplitting() {
        let doc = TextLayout.assemble([
            line("p1 line1", y: 0.90),
            line("p1 line2", y: 0.86),
            line("p2 line1", y: 0.40),
        ], paragraphGap: 0.1)
        #expect(doc.blocks == [
            .paragraph(text: "p1 line1\np1 line2"),
            .paragraph(text: "p2 line1"),
        ])
    }

    @Test("Empty input yields an empty document tagged with the engine")
    func empty() {
        let doc = TextLayout.assemble([])
        #expect(doc.blocks.isEmpty)
        #expect(doc.metadata.engine == "vision")
    }

    @Test("Same-row lines order left-to-right")
    func sameRow() {
        let doc = TextLayout.assemble([
            line("right", y: 0.80, x: 0.6),
            line("left", y: 0.80, x: 0.1),
        ], paragraphGap: 0.5)
        #expect(doc.blocks == [.paragraph(text: "left\nright")])
    }
}
