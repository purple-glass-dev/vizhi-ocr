import CoreImage
import Foundation
import MLXLMCommon
import VizhiCore
import VizhiModels

public enum MLXEngineError: Error, Equatable, LocalizedError {
    /// The selected model isn't installed on disk.
    case modelNotInstalled(modelID: String)

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            "The selected AI model isn't downloaded yet."
        }
    }
}

/// AI-mode engine that runs an OCR/VLM via MLX and parses its Markdown output into an
/// `OCRDocument`. Owns the prompt, the model descriptor, and the Markdown→document parsing;
/// the model container itself is loaded/cached by `MLXModelCache`.
public struct MLXOCREngine: OCREngine {
    public let model: ModelDescriptor

    /// Local directory where the model was downloaded (by our download manager). When it contains
    /// the model files, MLX loads from disk; otherwise it downloads from Hugging Face on demand.
    private let modelDirectory: URL?

    /// Reports model load/download progress (0...1) during the first use of a model.
    private let onLoadProgress: (@Sendable (Double) -> Void)?

    /// Optional per-document hint the user typed, appended to the instruction.
    private let userHint: String?

    private let promptBuilder = OCRPromptBuilder()
    private let parser = MarkdownDocumentParser()

    public var identifier: String { model.id }

    /// Inference tuning constants.
    enum Limits {
        /// Token budget. Dense pages/tables need a high budget so output isn't truncated mid-table.
        static let maxTokens = 8192
        /// Upper bound on the longest image side fed to the model (aspect-preserved), high enough
        /// that small table text stays legible without ballooning compute.
        static let maxImageSide: CGFloat = 1568
        /// Lower bound on the longest side: small captures (e.g. a tiny selected region) are
        /// **upscaled** to at least this, so the vision encoder gets enough pixels per glyph instead
        /// of guessing at blurry text.
        static let minImageSide: CGFloat = 1024
        /// Cap on how much a small image is enlarged — past this it's just blur and wasted compute.
        static let maxUpscale: CGFloat = 3
    }

    /// Reports streaming generation progress: (tokens emitted so far, full text so far).
    private let onStream: (@Sendable (Int, String) -> Void)?

    public init(
        model: ModelDescriptor,
        modelDirectory: URL? = nil,
        userHint: String? = nil,
        onLoadProgress: (@Sendable (Double) -> Void)? = nil,
        onStream: (@Sendable (Int, String) -> Void)? = nil
    ) {
        self.model = model
        self.modelDirectory = modelDirectory
        self.userHint = userHint
        self.onLoadProgress = onLoadProgress
        self.onStream = onStream
    }

    public func recognize(_ image: OCRImage) async throws -> OCRDocument {
        let markdown = try await runInference(on: image)
        return parser.parse(markdown, metadata: .init(engine: "mlx", model: model.id))
    }

    /// Loads (caching) the model and streams generation, returning the full Markdown. Streaming
    /// lets the UI show live progress (token count + partial text) instead of an opaque spinner.
    private func runInference(on image: OCRImage) async throws -> String {
        let prompt = promptBuilder.instruction(for: model, userHint: userHint)
        let onLoadProgress = self.onLoadProgress
        let onStream = self.onStream
        let container = try await loadContainer(onLoadProgress: onLoadProgress)

        let ciImage = CIImage(cgImage: image.cgImage)
        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(maxTokens: Limits.maxTokens, temperature: 0),
            // Aspect-preserving resize: downscale big captures, upscale tiny ones, so text resolution
            // lands in a band the vision encoder reads well.
            processing: .init(resize: Self.resizeTarget(
                for: image.cgImage,
                maxSide: Limits.maxImageSide,
                minSide: Limits.minImageSide,
                maxUpscale: Limits.maxUpscale
            ))
        )

        var fullText = ""
        var tokens = 0
        for try await chunk in session.streamResponse(to: prompt, image: .ciImage(ciImage)) {
            // Stop promptly when the user aborts: throws CancellationError out of the stream.
            try Task.checkCancellation()
            fullText += chunk
            tokens += 1
            onStream?(tokens, fullText)
        }
        return fullText
    }

    /// Aspect-preserving target size. The longest side is clamped into `[minSide, maxSide]`:
    /// oversized captures are downscaled, and small ones are upscaled (bounded by `maxUpscale`) so
    /// tiny text reaches a resolution the model reads reliably. Pure, for unit testing.
    static func resizeTarget(for image: CGImage, maxSide: CGFloat, minSide: CGFloat, maxUpscale: CGFloat) -> CGSize {
        resizeTarget(width: CGFloat(image.width), height: CGFloat(image.height),
                     maxSide: maxSide, minSide: minSide, maxUpscale: maxUpscale)
    }

    static func resizeTarget(
        width: CGFloat, height: CGFloat, maxSide: CGFloat, minSide: CGFloat, maxUpscale: CGFloat
    ) -> CGSize {
        let longest = max(width, height)
        guard longest > 0 else { return CGSize(width: width, height: height) }
        let targetLongest = min(max(longest, minSide), maxSide)   // clamp into the band
        let scale = min(targetLongest / longest, maxUpscale)      // but never upscale past the cap
        return CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
    }

    /// Prefers a fully-downloaded local directory (offline load); otherwise downloads from
    /// Hugging Face on demand, reporting progress.
    private func loadContainer(onLoadProgress: (@Sendable (Double) -> Void)?) async throws -> MLXLMCommon.ModelContainer {
        if let directory = modelDirectory, modelIsPresent(in: directory) {
            return try await MLXModelCache.shared.container(forDirectory: directory, displayName: model.displayName)
        }
        return try await MLXModelCache.shared.container(
            for: model.source.huggingFaceRepo,
            displayName: model.displayName
        ) { fraction in
            onLoadProgress?(fraction)
        }
    }

    /// True when every catalog-declared file for the model exists in the directory.
    private func modelIsPresent(in directory: URL) -> Bool {
        guard !model.files.isEmpty else { return false }
        return model.files.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.name).path)
        }
    }
}
