import Foundation

/// Capability tiers, ordered by capability/size. `Comparable` so tiering can pick the highest
/// tier that fits a machine.
public enum ModelTier: String, Sendable, Codable, CaseIterable, Comparable {
    case lite
    case standard
    case ultra

    private var rank: Int {
        switch self {
        case .lite: 0
        case .standard: 1
        case .ultra: 2
        }
    }

    public static func < (lhs: ModelTier, rhs: ModelTier) -> Bool {
        lhs.rank < rhs.rank
    }

    public var displayName: String {
        switch self {
        case .lite: "Lite"
        case .standard: "Standard"
        case .ultra: "Ultra"
        }
    }
}

/// A capability a model claims to support, surfaced in the model manager UI.
public enum ModelCapability: String, Sendable, Codable, CaseIterable {
    case text
    case tables
    case multicolumn
    case math
    case handwriting
}

/// Where a model's weights are fetched from. Hugging Face is primary; the CDN is the fallback
/// mirror (see docs/MODELS.md and docs/PRIVACY.md — these are the only network endpoints).
public struct ModelSource: Sendable, Codable, Equatable {
    public var huggingFaceRepo: String
    public var cdnBaseURL: URL?

    public init(huggingFaceRepo: String, cdnBaseURL: URL? = nil) {
        self.huggingFaceRepo = huggingFaceRepo
        self.cdnBaseURL = cdnBaseURL
    }
}

/// One downloadable file belonging to a model, with an integrity checksum.
public struct ModelFile: Sendable, Codable, Equatable {
    public var name: String
    public var sizeBytes: Int64
    public var sha256: String

    public init(name: String, sizeBytes: Int64, sha256: String) {
        self.name = name
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
    }
}

/// A model in the catalog. The catalog is data, so models are added/removed without code
/// changes (docs/MODELS.md).
public struct ModelDescriptor: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    /// One-line speciality blurb shown in the model manager, e.g. what this model is best at.
    public var summary: String
    public var tier: ModelTier
    public var capabilities: [ModelCapability]
    /// Minimum installed RAM (GB) required to load the model. Source of truth for tiering.
    public var minRAMGB: Int
    /// RAM (GB) at or above which this model is the recommended choice.
    public var recommendedRAMGB: Int
    public var quantization: String
    /// Optional model-specific instruction prompt. OCR fine-tunes are trained to respond to their
    /// own prompt; when set, this overrides the generic capability-built instruction. Empty means
    /// "use the generic prompt" (works well for GLM-OCR).
    public var prompt: String
    public var source: ModelSource
    public var files: [ModelFile]

    public init(
        id: String,
        displayName: String,
        summary: String = "",
        tier: ModelTier,
        capabilities: [ModelCapability],
        minRAMGB: Int,
        recommendedRAMGB: Int,
        quantization: String,
        prompt: String = "",
        source: ModelSource,
        files: [ModelFile] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.tier = tier
        self.capabilities = capabilities
        self.minRAMGB = minRAMGB
        self.recommendedRAMGB = recommendedRAMGB
        self.quantization = quantization
        self.prompt = prompt
        self.source = source
        self.files = files
    }

    /// Total download size across all files.
    public var totalSizeBytes: Int64 {
        files.reduce(0) { $0 + $1.sizeBytes }
    }
}
