import Foundation

/// The running build's version and source commit, read from the bundle's Info.plist.
///
/// `scripts/build-app.sh` writes `CFBundleShortVersionString` (the semver derived from the latest
/// `vX.Y.Z` git tag) and `VizhiGitCommit` (the short commit hash) at build time. When the app is
/// run outside that script (e.g. `swift run` / a bare Xcode build), those keys may be absent, so we
/// fall back to a "dev" label.
enum AppVersion {
    /// Marketing version, e.g. "0.1.2".
    static var shortVersion: String {
        info("CFBundleShortVersionString") ?? "dev"
    }

    /// Short git commit hash baked in at build time, e.g. "6b85b4e".
    static var commit: String {
        info("VizhiGitCommit") ?? "local"
    }

    /// One-line build identifier for the menu, e.g. "v0.1.2 (6b85b4e)".
    static var display: String {
        "v\(shortVersion) (\(commit))"
    }

    private static func info(_ key: String) -> String? {
        guard let value = Bundle.main.infoDictionary?[key] as? String, !value.isEmpty else { return nil }
        return value
    }
}
