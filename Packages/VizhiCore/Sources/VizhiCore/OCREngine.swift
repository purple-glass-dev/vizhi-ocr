import CoreGraphics

/// An image handed to an OCR engine. Wraps `CGImage`, which is not `Sendable`; access is
/// confined to the engine that receives it, so the unchecked conformance is sound here.
public struct OCRImage: @unchecked Sendable {
    public let cgImage: CGImage

    public init(cgImage: CGImage) {
        self.cgImage = cgImage
    }
}

/// A recognition backend. `VizhiVision` (Apple Vision) and `VizhiMLX` (MLX models) each provide
/// a concrete conformance; `VizhiCore` depends only on this protocol, and the app injects the
/// concrete engines at composition time.
public protocol OCREngine: Sendable {
    /// Stable identifier, e.g. `"vision"` or a model id like `"glm-ocr-standard"`.
    var identifier: String { get }

    /// Recognize the image and return a normalized document.
    func recognize(_ image: OCRImage) async throws -> OCRDocument
}

/// Which engine family a request targets.
public enum CaptureMode: String, Sendable, CaseIterable {
    /// Apple Vision — instant, no download. The default.
    case fast
    /// MLX model — higher quality for tables, math, multi-column, handwriting.
    case ai
}
