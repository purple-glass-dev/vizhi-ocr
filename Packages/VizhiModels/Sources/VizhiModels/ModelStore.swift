import Foundation

/// Install state of a model on disk.
public enum ModelInstallState: Sendable, Equatable {
    case notInstalled
    case installed(URL)
}

/// Resolves on-disk locations for downloaded models and reports install state. Downloading and
/// integrity verification land here next (HF primary, CDN fallback — see docs/MODELS.md);
/// for now this is the storage-layout source of truth.
public struct ModelStore: Sendable {
    /// Root directory holding per-model subfolders, e.g.
    /// `~/Library/Application Support/VizhiOCR/Models/`.
    public let modelsRoot: URL

    public init(modelsRoot: URL) {
        self.modelsRoot = modelsRoot
    }

    /// Default store under the user's Application Support directory.
    public init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.modelsRoot = appSupport
            .appendingPathComponent("VizhiOCR", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    /// Directory a model's files live in once installed.
    public func directory(for model: ModelDescriptor) -> URL {
        modelsRoot.appendingPathComponent(model.id, isDirectory: true)
    }

    /// Whether every declared file for the model is present on disk.
    public func installState(for model: ModelDescriptor, fileManager: FileManager = .default) -> ModelInstallState {
        let dir = directory(for: model)
        guard !model.files.isEmpty else {
            return fileManager.fileExists(atPath: dir.path) ? .installed(dir) : .notInstalled
        }
        let allPresent = model.files.allSatisfy { file in
            fileManager.fileExists(atPath: dir.appendingPathComponent(file.name).path)
        }
        return allPresent ? .installed(dir) : .notInstalled
    }
}
