import Foundation

/// Selects which models a machine can run and which one to recommend, based on installed RAM.
///
/// The app must never offer a model that cannot load, so eligibility is a hard filter on
/// `minRAMGB` (which already encodes the minimum *installed* RAM). The recommendation is the
/// highest-tier model that fits.
public struct ModelTiering: Sendable {
    public init() {}

    /// Models that can load on a machine with `installedRAMGB`, ordered by tier (highest first).
    /// Ties within a tier preserve catalog order, so the default recommendation is deterministic
    /// even when several models share a tier.
    public func eligibleModels(in catalog: ModelCatalog, installedRAMGB: Int) -> [ModelDescriptor] {
        catalog.models
            .enumerated()
            .filter { $0.element.minRAMGB <= installedRAMGB }
            .sorted { lhs, rhs in
                lhs.element.tier == rhs.element.tier
                    ? lhs.offset < rhs.offset
                    : lhs.element.tier > rhs.element.tier
            }
            .map(\.element)
    }

    /// The model to recommend by default — the most capable one that fits — or `nil` if none do.
    public func recommendedModel(in catalog: ModelCatalog, installedRAMGB: Int) -> ModelDescriptor? {
        eligibleModels(in: catalog, installedRAMGB: installedRAMGB).first
    }

    /// Whether the machine has the `recommendedRAMGB` headroom for comfortable performance, as
    /// opposed to merely meeting `minRAMGB`. Useful for a "runs, but tight" hint in the UI.
    public func isComfortable(_ model: ModelDescriptor, installedRAMGB: Int) -> Bool {
        installedRAMGB >= model.recommendedRAMGB
    }
}

public extension ModelTiering {
    /// Installed physical memory in GB, rounded down.
    static var installedRAMGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    }
}
