import CoreGraphics
import Foundation
import Vision
import VizhiCore

/// Fast-mode engine backed by Apple's Vision framework. Instant, on-device, no model download —
/// the default capture engine. Produces primarily paragraph text with reading-order
/// reconstruction; richer structure (tables, math) is the AI engine's job.
public struct VisionOCREngine: OCREngine {
    public let identifier = "vision"

    /// Recognition languages, in priority order. Empty uses Vision's automatic detection.
    public var languages: [String]
    public var usesLanguageCorrection: Bool

    public init(languages: [String] = [], usesLanguageCorrection: Bool = true) {
        self.languages = languages
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    public func recognize(_ image: OCRImage) async throws -> OCRDocument {
        let cgImage = image.cgImage
        let lines = try await Task.detached(priority: .userInitiated) { [languages, usesLanguageCorrection] in
            try Self.recognizeLines(
                in: cgImage,
                languages: languages,
                usesLanguageCorrection: usesLanguageCorrection
            )
        }.value
        return TextLayout.assemble(lines)
    }

    /// Synchronous Vision call, run off the main actor by the caller.
    private static func recognizeLines(
        in cgImage: CGImage,
        languages: [String],
        usesLanguageCorrection: Bool
    ) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = usesLanguageCorrection
        if !languages.isEmpty {
            request.recognitionLanguages = languages
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: candidate.string, boundingBox: observation.boundingBox)
        }
    }
}
