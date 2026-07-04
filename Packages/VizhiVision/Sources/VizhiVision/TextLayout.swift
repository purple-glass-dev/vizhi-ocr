import CoreGraphics
import VizhiCore

/// One line of recognized text with its normalized bounding box (Vision's coordinate space:
/// origin bottom-left, 0...1 on each axis). Kept separate from Vision types so the layout
/// assembly is pure and unit-testable without running OCR on a real image.
public struct RecognizedLine: Sendable, Equatable {
    public var text: String
    public var boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

enum TextLayout {
    /// Assembles recognized lines into a document: orders them top-to-bottom / left-to-right and
    /// groups lines into paragraphs, breaking where the vertical gap between lines is large.
    ///
    /// - Parameter paragraphGap: vertical gap (in normalized units) above which a new paragraph
    ///   begins. Tuned for typical screen captures.
    static func assemble(_ lines: [RecognizedLine], paragraphGap: CGFloat = 0.02) -> OCRDocument {
        let ordered = lines.sorted { lhs, rhs in
            // Vision origin is bottom-left, so larger maxY is higher on the page.
            if abs(lhs.boundingBox.maxY - rhs.boundingBox.maxY) > 0.01 {
                return lhs.boundingBox.maxY > rhs.boundingBox.maxY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        guard !ordered.isEmpty else {
            return OCRDocument(blocks: [], metadata: .init(engine: "vision"))
        }

        var paragraphs: [[String]] = [[]]
        var previousMinY: CGFloat?

        for line in ordered {
            if let previousMinY, previousMinY - line.boundingBox.maxY > paragraphGap {
                paragraphs.append([])
            }
            paragraphs[paragraphs.count - 1].append(line.text)
            previousMinY = line.boundingBox.minY
        }

        let blocks = paragraphs
            .filter { !$0.isEmpty }
            .map { Block.paragraph(text: $0.joined(separator: "\n")) }

        return OCRDocument(blocks: blocks, metadata: .init(engine: "vision"))
    }
}
