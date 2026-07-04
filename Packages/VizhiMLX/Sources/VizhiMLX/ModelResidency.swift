import Observation

/// Whether an AI model is currently held in memory. Surfaced so the user can see that a multi-GB
/// model is resident (and when it's released). Driven entirely by `MLXModelCache`.
public enum ModelResidencyState: Equatable, Sendable {
    case unloaded
    case loading(model: String)
    case loaded(model: String)
    case unloading(model: String)

    /// Short status line for the menubar / import window.
    public var label: String {
        switch self {
        case .unloaded: "No model in memory"
        case let .loading(model): "Loading \(model)…"
        case let .loaded(model): "\(model) loaded in memory"
        case let .unloading(model): "Unloading \(model)…"
        }
    }

    /// SF Symbol that reads at a glance: filled when resident, hollow when not.
    public var systemImage: String {
        switch self {
        case .unloaded: "memorychip"
        case .loading: "arrow.down.circle"
        case .loaded: "memorychip.fill"
        case .unloading: "arrow.up.circle"
        }
    }

    /// True while weights occupy memory (loaded, or in the act of being released).
    public var isResident: Bool {
        switch self {
        case .loaded, .unloading: true
        case .unloaded, .loading: false
        }
    }
}

/// Observable mirror of `MLXModelCache`'s residency, for SwiftUI. A shared singleton because the
/// cache itself is a process-wide singleton; the cache writes, the UI reads.
@MainActor
@Observable
public final class ModelResidency {
    public static let shared = ModelResidency()

    public private(set) var state: ModelResidencyState = .unloaded

    public init() {}

    public func set(_ state: ModelResidencyState) {
        self.state = state
    }
}
