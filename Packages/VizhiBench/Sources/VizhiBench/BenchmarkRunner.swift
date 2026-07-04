import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VizhiCore

/// The outcome of running one engine against one corpus item.
public struct BenchmarkResult: Sendable {
    public let itemID: String
    public let category: String
    public let engineID: String
    /// Scores, or `nil` if recognition threw (see `error`).
    public let rates: ErrorRates?
    /// Wall-clock recognition time in seconds (excludes image load).
    public let durationSeconds: Double
    /// The rendered hypothesis (for an output dump / manual inspection).
    public let hypothesis: String
    /// Non-nil if recognition failed; `rates` is then `nil`.
    public let error: String?

    public init(
        itemID: String, category: String, engineID: String,
        rates: ErrorRates?, durationSeconds: Double, hypothesis: String, error: String?
    ) {
        self.itemID = itemID
        self.category = category
        self.engineID = engineID
        self.rates = rates
        self.durationSeconds = durationSeconds
        self.hypothesis = hypothesis
        self.error = error
    }
}

/// Drives one or more `OCREngine`s over a `BenchmarkCorpus` and scores each result.
///
/// Runs strictly sequentially (engine by engine, item by item): the MLX backend keeps a single
/// model resident at a time, so parallelism would only thrash memory. Each engine is paired with a
/// human label for the report (e.g. "GLM-OCR (4-bit)") since `OCREngine.identifier` is a slug.
public struct BenchmarkRunner: Sendable {
    /// An engine to evaluate, with the display name to show in the report.
    public struct Subject: Sendable {
        public let label: String
        public let engine: any OCREngine
        public init(label: String, engine: any OCREngine) {
            self.label = label
            self.engine = engine
        }
    }

    private let scorer = OCRScorer()
    /// Turns a recognized document back into text for comparison against the ground truth.
    private let render: @Sendable (OCRDocument) -> String

    public init(render: @escaping @Sendable (OCRDocument) -> String) {
        self.render = render
    }

    /// Runs every subject over every corpus item. `progress` is called as each result lands so a CLI
    /// can print a live line.
    public func run(
        corpus: BenchmarkCorpus,
        subjects: [Subject],
        progress: (@Sendable (BenchmarkResult) -> Void)? = nil
    ) async -> [BenchmarkResult] {
        var results: [BenchmarkResult] = []
        for subject in subjects {
            for item in corpus.items {
                let result = await evaluate(item: item, subject: subject)
                progress?(result)
                results.append(result)
            }
        }
        return results
    }

    private func evaluate(item: BenchmarkItem, subject: Subject) async -> BenchmarkResult {
        let label = subject.engine.identifier
        guard let image = Self.loadImage(at: item.imageURL) else {
            return BenchmarkResult(
                itemID: item.id, category: item.category, engineID: label,
                rates: nil, durationSeconds: 0, hypothesis: "",
                error: "could not load image at \(item.imageURL.path)"
            )
        }

        let start = Date()
        do {
            let document = try await subject.engine.recognize(image)
            let duration = Date().timeIntervalSince(start)
            let hypothesis = render(document)
            let rates = scorer.score(
                reference: item.referenceMarkdown, hypothesis: hypothesis, category: item.category
            )
            return BenchmarkResult(
                itemID: item.id, category: item.category, engineID: label,
                rates: rates, durationSeconds: duration, hypothesis: hypothesis, error: nil
            )
        } catch {
            return BenchmarkResult(
                itemID: item.id, category: item.category, engineID: label,
                rates: nil, durationSeconds: Date().timeIntervalSince(start),
                hypothesis: "", error: String(describing: error)
            )
        }
    }

    /// Decodes an image file to a `CGImage`. Returns `nil` on any failure (unreadable/corrupt).
    static func loadImage(at url: URL) -> OCRImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return OCRImage(cgImage: cg)
    }
}
