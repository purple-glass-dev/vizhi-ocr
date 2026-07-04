import Foundation
import VizhiModels

/// Pure presentation logic for a model row in the model-manager UI. Kept free of SwiftUI so the
/// labels and badges are unit-testable.
public struct ModelPresentation: Sendable, Equatable {
    public let model: ModelDescriptor
    public let installState: ModelInstallState
    public let isRecommended: Bool
    public let fits: Bool
    public let isComfortable: Bool
    /// Whether this catalog entry has real files to fetch. Placeholder/aspirational models have
    /// an empty file list and aren't downloadable yet.
    public let isDownloadable: Bool

    public init(
        model: ModelDescriptor,
        installedRAMGB: Int,
        installState: ModelInstallState,
        recommendedID: String?,
        tiering: ModelTiering = ModelTiering()
    ) {
        self.model = model
        self.installState = installState
        self.isRecommended = (model.id == recommendedID)
        self.fits = model.minRAMGB <= installedRAMGB
        self.isComfortable = tiering.isComfortable(model, installedRAMGB: installedRAMGB)
        self.isDownloadable = !model.files.isEmpty
    }

    /// "1.2 GB" style download size, or "—" when the catalog has no file sizes yet.
    public var sizeText: String {
        guard model.totalSizeBytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: model.totalSizeBytes, countStyle: .file)
    }

    /// One-line status for the row.
    public var statusText: String {
        switch installState {
        case .installed:
            return "Installed"
        case .notInstalled:
            if !isDownloadable { return "Not yet available" }
            if !fits { return "Needs \(model.minRAMGB) GB RAM" }
            return isComfortable ? "Ready to download" : "Runs, but tight (\(model.recommendedRAMGB) GB recommended)"
        }
    }

    public var isInstalled: Bool {
        if case .installed = installState { return true }
        return false
    }
}
