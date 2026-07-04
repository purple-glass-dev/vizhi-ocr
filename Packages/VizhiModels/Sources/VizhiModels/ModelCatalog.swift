import Foundation

/// The set of AI models the app knows about. Loaded from a bundled JSON manifest, with a
/// hand-written fallback so the app always has a catalog even if the resource is missing.
public struct ModelCatalog: Sendable, Codable, Equatable {
    public var version: Int
    /// The catalog's preferred default model (by id). The app picks this when the user hasn't chosen
    /// one and the machine can run it — so quality, not just RAM tier, drives the default. Optional;
    /// falls back to RAM tiering when absent or it doesn't fit.
    public var defaultModelID: String?
    public var models: [ModelDescriptor]

    public init(version: Int, defaultModelID: String? = nil, models: [ModelDescriptor]) {
        self.version = version
        self.defaultModelID = defaultModelID
        self.models = models
    }

    public func model(id: String) -> ModelDescriptor? {
        models.first { $0.id == id }
    }

    /// The model AI capture uses when the user hasn't explicitly chosen one: the catalog's preferred
    /// default if it fits, else the most capable model the machine can run, else the first listed.
    public func defaultOCRModel(installedRAMGB: Int = ModelTiering.installedRAMGB) -> ModelDescriptor? {
        if let id = defaultModelID, let preferred = model(id: id), preferred.minRAMGB <= installedRAMGB {
            return preferred
        }
        return ModelTiering().recommendedModel(in: self, installedRAMGB: installedRAMGB) ?? models.first
    }

    /// The model AI capture will actually use: the user's explicit selection if it resolves, else
    /// the RAM-appropriate default. Single source of truth so the engine and UI never disagree.
    public func activeModel(
        selectedID: String?,
        installedRAMGB: Int = ModelTiering.installedRAMGB
    ) -> ModelDescriptor? {
        selectedID.flatMap { model(id: $0) } ?? defaultOCRModel(installedRAMGB: installedRAMGB)
    }
}

public extension ModelCatalog {
    /// The bundled `catalog.json`, parsed once and cached (it's static data), falling back to
    /// `defaultCatalog` if the resource is absent or invalid.
    static func bundled() -> ModelCatalog { cachedBundled }

    private static let cachedBundled: ModelCatalog = {
        let bundle: Bundle = .module
        guard
            let url = bundle.url(forResource: "catalog", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode(ModelCatalog.self, from: data)
        else {
            return defaultCatalog
        }
        return catalog
    }()

    /// Compiled-in fallback catalog, kept in sync with `Resources/catalog.json` (the runtime
    /// source of truth). File lists mirror each model's Hugging Face repo so the download manager
    /// fetches exactly what MLX needs to load from the local directory. See docs/MODELS.md.
    static let defaultCatalog = ModelCatalog(
        version: 4,
        // GLM-OCR 4-bit is the preferred default: small, fast, and in practice as accurate as — often
        // better than — the 8-bit build on real documents.
        defaultModelID: "glm-ocr-4bit",
        models: [
            ModelDescriptor(
                id: "glm-ocr-4bit",
                displayName: "GLM-OCR (4-bit)",
                summary: "Balanced default. Strong on tables, math, and multi-column layouts at modest RAM.",
                tier: .standard, capabilities: [.text, .tables, .multicolumn, .math, .handwriting],
                minRAMGB: 8, recommendedRAMGB: 16, quantization: "q4",
                source: ModelSource(huggingFaceRepo: "mlx-community/GLM-OCR-4bit"),
                files: [
                ModelFile(name: "chat_template.jinja", sizeBytes: 4606, sha256: ""),
                ModelFile(name: "config.json", sizeBytes: 2080, sha256: ""),
                ModelFile(name: "generation_config.json", sizeBytes: 165, sha256: ""),
                ModelFile(name: "model.safetensors", sizeBytes: 1247191941, sha256: ""),
                ModelFile(name: "model.safetensors.index.json", sizeBytes: 55990, sha256: ""),
                ModelFile(name: "preprocessor_config.json", sizeBytes: 367, sha256: ""),
                ModelFile(name: "processor_config.json", sizeBytes: 597, sha256: ""),
                ModelFile(name: "tokenizer.json", sizeBytes: 6838609, sha256: ""),
                ModelFile(name: "tokenizer_config.json", sizeBytes: 1066, sha256: ""),
                ]
            ),
            ModelDescriptor(
                id: "glm-ocr-8bit",
                displayName: "GLM-OCR (8-bit, higher quality)",
                summary: "Higher-precision GLM-OCR for the cleanest tables and math when you have the RAM.",
                tier: .ultra, capabilities: [.text, .tables, .multicolumn, .math, .handwriting],
                minRAMGB: 16, recommendedRAMGB: 24, quantization: "q8",
                source: ModelSource(huggingFaceRepo: "mlx-community/GLM-OCR-8bit"),
                files: [
                ModelFile(name: "chat_template.jinja", sizeBytes: 4606, sha256: ""),
                ModelFile(name: "config.json", sizeBytes: 2080, sha256: ""),
                ModelFile(name: "generation_config.json", sizeBytes: 165, sha256: ""),
                ModelFile(name: "model.safetensors", sizeBytes: 1583785269, sha256: ""),
                ModelFile(name: "model.safetensors.index.json", sizeBytes: 55990, sha256: ""),
                ModelFile(name: "preprocessor_config.json", sizeBytes: 367, sha256: ""),
                ModelFile(name: "processor_config.json", sizeBytes: 597, sha256: ""),
                ModelFile(name: "tokenizer.json", sizeBytes: 6838609, sha256: ""),
                ModelFile(name: "tokenizer_config.json", sizeBytes: 1066, sha256: ""),
                ]
            ),
        ]
    )
}
