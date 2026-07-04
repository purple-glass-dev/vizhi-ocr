import VizhiModels

/// Pure mapping from a download state to a UI label and (optional) progress fraction. Kept out of
/// the view so it's unit-testable.
public enum DownloadStatusPresentation {
    public static func label(for state: ModelDownloadState, fallback: String) -> String {
        switch state {
        case .notInstalled: fallback
        case let .downloading(fraction): "Downloading… \(Int((fraction * 100).rounded()))%"
        case .verifying: "Verifying…"
        case .installed: "Installed"
        case let .failed(message): "Failed: \(message)"
        }
    }

    /// Progress 0...1 while downloading; nil otherwise (so the row shows a determinate bar only
    /// during download).
    public static func fraction(for state: ModelDownloadState) -> Double? {
        if case let .downloading(fraction) = state { return fraction }
        return nil
    }

    public static func isInstalled(_ state: ModelDownloadState) -> Bool {
        state == .installed
    }

    public static func isBusy(_ state: ModelDownloadState) -> Bool {
        switch state {
        case .downloading, .verifying: true
        default: false
        }
    }
}
