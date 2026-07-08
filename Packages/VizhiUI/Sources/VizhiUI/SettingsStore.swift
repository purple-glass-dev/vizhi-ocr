import Foundation
import Observation
import ServiceManagement
import VizhiCapture
import VizhiCore

/// User preferences, persisted to `UserDefaults` and observable by SwiftUI. Inject a custom
/// `UserDefaults` (e.g. a suite) in tests.
@Observable
public final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults

    public var defaultMode: CaptureMode {
        didSet { defaults.set(defaultMode.rawValue, forKey: Keys.defaultMode) }
    }

    public var outputFormat: OutputFormat {
        didSet { defaults.set(outputFormat.rawValue, forKey: Keys.outputFormat) }
    }

    /// Currently selected AI model id, or `nil` when none is chosen (Fast mode only).
    public var selectedModelID: String? {
        didSet { defaults.set(selectedModelID, forKey: Keys.selectedModelID) }
    }

    /// Optional local history; off by default to honor the privacy promise.
    public var historyEnabled: Bool {
        didSet { defaults.set(historyEnabled, forKey: Keys.historyEnabled) }
    }

    /// Play a short sound when a capture completes (in addition to the on-screen HUD). Off by default.
    public var playsCompletionSound: Bool {
        didSet { defaults.set(playsCompletionSound, forKey: Keys.playsCompletionSound) }
    }

    /// Show an editable preview of the recognized text before it's copied/saved, so a misread can
    /// be fixed first. On by default — it's the most useful way to catch a misread.
    public var previewBeforeCopy: Bool {
        didSet { defaults.set(previewBeforeCopy, forKey: Keys.previewBeforeCopy) }
    }

    /// Register the app as a macOS login item so it starts at the next login. Off by default.
    /// The source of truth is `SMAppService`; this mirrors its status and applies changes on toggle.
    public var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    /// Set while reverting `launchAtLogin` after a failed (un)register, to avoid re-entrant didSet.
    @ObservationIgnored private var isSyncingLaunchAtLogin = false

    /// Whether the first-run welcome has been completed; gates the onboarding window.
    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    /// Where results are delivered: clipboard, a saved Markdown file, or both.
    public var outputDestination: OutputDestination {
        didSet { defaults.set(outputDestination.rawValue, forKey: Keys.outputDestination) }
    }

    /// Folder where Markdown files are saved when the destination includes a file.
    public var saveFolderURL: URL {
        didSet { defaults.set(saveFolderURL.path, forKey: Keys.saveFolderPath) }
    }

    /// Save the original captured region as a PNG alongside the recognized text. Screen captures
    /// only (not imported files). Off by default to honor the privacy promise.
    public var saveScreenshotsEnabled: Bool {
        didSet { defaults.set(saveScreenshotsEnabled, forKey: Keys.saveScreenshotsEnabled) }
    }

    /// Folder where screenshot PNGs are saved when `saveScreenshotsEnabled` is on. Kept separate
    /// from `saveFolderURL` so images and text notes can live in different places.
    /// Note: persisted as a plain path, so it assumes the app stays un-sandboxed; a sandboxed build
    /// would need a security-scoped bookmark here (as would `saveFolderURL`).
    public var screenshotFolderURL: URL {
        didSet { defaults.set(screenshotFolderURL.path, forKey: Keys.screenshotFolderPath) }
    }

    /// Global capture shortcuts, keyed by action. Starts from `Hotkey.defaults()` and is
    /// overridden by anything the user has recorded. Persisted as JSON keyed by action name.
    public var hotkeys: [CaptureAction: Hotkey] {
        didSet { persistHotkeys() }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.defaultMode = defaults.string(forKey: Keys.defaultMode)
            .flatMap(CaptureMode.init) ?? .fast
        self.outputFormat = defaults.string(forKey: Keys.outputFormat)
            .flatMap(OutputFormat.init) ?? .markdown
        self.selectedModelID = defaults.string(forKey: Keys.selectedModelID)
        self.historyEnabled = defaults.bool(forKey: Keys.historyEnabled)
        self.playsCompletionSound = defaults.bool(forKey: Keys.playsCompletionSound)
        // Default to on when the user hasn't made a choice yet; preview & edit is the useful default.
        self.previewBeforeCopy = defaults.object(forKey: Keys.previewBeforeCopy) as? Bool ?? true
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.outputDestination = defaults.string(forKey: Keys.outputDestination)
            .flatMap(OutputDestination.init) ?? .clipboard
        self.saveFolderURL = defaults.string(forKey: Keys.saveFolderPath).map { URL(fileURLWithPath: $0) }
            ?? Self.defaultSaveFolder
        self.saveScreenshotsEnabled = defaults.bool(forKey: Keys.saveScreenshotsEnabled)
        self.screenshotFolderURL = defaults.string(forKey: Keys.screenshotFolderPath).map { URL(fileURLWithPath: $0) }
            ?? Self.defaultSaveFolder
        self.hotkeys = Self.loadHotkeys(defaults)
    }

    /// Registers or unregisters the app as a login item. On failure, reverts the published value so
    /// the toggle reflects the real `SMAppService` state rather than the user's intent.
    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            isSyncingLaunchAtLogin = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            isSyncingLaunchAtLogin = false
        }
    }

    private func persistHotkeys() {
        let byName = Dictionary(uniqueKeysWithValues: hotkeys.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(byName) {
            defaults.set(data, forKey: Keys.hotkeys)
        }
    }

    /// Merges any saved overrides onto the factory defaults, so a newly added action always has a
    /// shortcut and a corrupt/missing entry falls back cleanly.
    private static func loadHotkeys(_ defaults: UserDefaults) -> [CaptureAction: Hotkey] {
        var result = Hotkey.defaults()
        if let data = defaults.data(forKey: Keys.hotkeys),
           let byName = try? JSONDecoder().decode([String: Hotkey].self, from: data) {
            for (name, hotkey) in byName {
                if let action = CaptureAction(rawValue: name) { result[action] = hotkey }
            }
        }
        return result
    }

    /// Default save location: the user's Downloads folder (falls back to the home directory).
    static var defaultSaveFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private enum Keys {
        static let defaultMode = "defaultMode"
        static let outputFormat = "outputFormat"
        static let selectedModelID = "selectedModelID"
        static let historyEnabled = "historyEnabled"
        static let playsCompletionSound = "playsCompletionSound"
        static let previewBeforeCopy = "previewBeforeCopy"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let outputDestination = "outputDestination"
        static let saveFolderPath = "saveFolderPath"
        static let saveScreenshotsEnabled = "saveScreenshotsEnabled"
        static let screenshotFolderPath = "screenshotFolderPath"
        static let hotkeys = "hotkeys"
    }
}
